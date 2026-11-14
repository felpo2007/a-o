"""Lâmina genérica (seção real): dorso, falso fio, sulco, plano, linha do chanfro e microbisel.

Numpy puro. A lâmina sai da face da guarda (s = 0, y = 0) para -Y (y = -s), o fio para -Z e as
faces planas para ±X. Medidas em mm.

Seção (meio anel do lado +X, do alto do dorso para o fio):
    S (0, topo) -> P0 (quina do dorso / alto do falso fio) -> P1 (fim do chanfro do dorso ou do
    falso fio) -> [sulco: F0..F4] ou [meio do plano] -> P7 (ombro: linha do chanfro primário)
    -> P8 (começo do microbisel) -> A (0, fio)
e o lado -X espelhado. Arestas vivas em P0, P1, F0, F4, P7, P8 e no fio.

Atributos por vértice: `d_fio` (mm de arco até o fio, exato nas faces planas do chanfro),
`bisel` (d_fio / d_fio do ombro: 0 no fio, 1 no ombro) e `afiado` (0 no ricasso, 1 onde afia).
"""

from __future__ import annotations

import math
from collections.abc import Callable
from dataclasses import dataclass

import numpy as np
from malha import Malha, estacoes


@dataclass
class Lamina:
    L: float  # da face da guarda à ponta (mm)
    topo: Callable[[float], float]  # z do dorso
    fio: Callable[[float], float]  # z do fio
    esp: Callable[[float], float]  # espessura no dorso
    bisel: Callable[[float], float]  # altura do chanfro primário (do fio ao ombro)
    e_fio: Callable[[float], float]  # espessura no começo do microbisel
    micro: float  # altura do microbisel
    chanfro: float  # quebra das quinas do dorso
    ponta_z: float
    afiado: Callable[[float], float]
    falso: Callable[[float], float] | None = None  # altura do falso fio (0 = só o chanfro)
    falso_esp: float = 0.3  # espessura no alto do falso fio
    falso_rampa: float = 1.5
    sulco: dict | None = None  # s0, s1, zc(s), w, prof
    meio: float = 0.0  # abaulado do plano (mm); > 0 põe um ponto no meio
    s_ini: float = -1.2  # começa dentro da guarda


def _sulco(lam: Lamina, s: float, T: float, hi: float, lo: float) -> list[tuple[float, float]]:
    su = lam.sulco
    r = su["w"] / 2
    k = 0.0
    if su["s0"] < s < su["s1"]:
        d0 = min(s - su["s0"], su["s1"] - s)
        k = math.sqrt(max(0.0, 1 - (max(0.0, r - d0) / r) ** 2))
    w = su["w"] * (0.35 + 0.65 * k)
    d = su["prof"] * k
    zc = su["zc"](s)
    offs = (0.5, 0.3, 0.0, -0.3, -0.5)
    prof = (0.0, 0.65, 1.0, 0.65, 0.0)
    zn = [zc + o * w for o in offs]
    m = 0.35
    a, b = lo + m, hi - m
    if b - a < 0.2:
        a, b = lo + 0.3 * (hi - lo), hi - 0.3 * (hi - lo)
    igual = [b - (i + 1) * (b - a) / 6 for i in range(5)]
    excesso = max(0.0, zn[0] - b, a - zn[4])
    beta = min(1.0, excesso / 1.5)
    z = [zn[i] * (1 - beta) + igual[i] * beta for i in range(5)]
    if beta >= 1.0 or z[0] > b or z[4] < a:
        z = igual
    return [(T / 2 - p * d, zz) for p, zz in zip(prof, z, strict=True)]


def lado(lam: Lamina, s: float) -> list[tuple[float, float]]:
    """Pontos (x, z) do lado +X entre S e A (sem eles)."""
    zt, zb = lam.topo(s), lam.fio(s)
    h = max(zt - zb, 1e-3)
    T = lam.esp(s)
    c = min(lam.chanfro, 0.12 * h, 0.3 * T)
    sw = max(c, min(lam.falso(s) if lam.falso else 0.0, 0.38 * h))
    k = min(1.0, max(0.0, (sw - c) / lam.falso_rampa))
    tt = (T - 2 * c) * (1 - k) + min(lam.falso_esp, T - 2 * c) * k
    bev = min(lam.bisel(s), 0.6 * h)
    mb = min(lam.micro, 0.3 * bev)
    e = min(lam.e_fio(s), 0.95 * T)
    zsh = zb + bev
    pts = [(tt / 2, zt), (T / 2, zt - sw)]
    if lam.sulco:
        pts += _sulco(lam, s, T, zt - sw, zsh)
    elif lam.meio > 0:
        pts.append((T / 2 + lam.meio, (zt - sw + zsh) / 2))
    pts += [(T / 2, zsh), (e / 2, zb + mb)]
    return pts


def anel(lam: Lamina, s: float):
    """Anel completo (N, 3) e os atributos d_fio e bisel (N,)."""
    sd = lado(lam, s)
    zt, zb = lam.topo(s), lam.fio(s)
    xz = [(0.0, zt)] + sd + [(0.0, zb)] + [(-x, z) for x, z in reversed(sd)]
    xz = np.array(xz)
    n = len(xz)
    ia = 1 + len(sd)  # índice do fio
    # arco do fio até cada ponto, pelo lado mais curto
    seg = np.linalg.norm(np.diff(np.vstack([xz, xz[:1]]), axis=0), axis=1)
    d = np.zeros(n)
    for j in range(ia - 1, -1, -1):  # subindo pelo lado +X
        d[j] = d[j + 1] + seg[j]
    for j in range(ia + 1, n):  # subindo pelo lado -X
        d[j] = d[j - 1] + seg[j - 1]
    d_ombro = d[ia - 2] if d[ia - 2] > 1e-6 else 1.0
    pts = np.column_stack([xz[:, 0], np.full(n, -s), xz[:, 1]])
    return pts, d, d / d_ombro


def construir(
    m: Malha,
    lam: Lamina,
    mat: str,
    passo: float = 0.4,
    tol: float = 0.035,
    fixas=(),
    peso: float = 1.0,
) -> dict:
    """Faz a lâmina na malha `m` e devolve dados (estações, índices, ponta)."""
    s_fim = lam.L - 0.7
    fino = np.arange(lam.s_ini, s_fim, passo)
    fixas = [lam.s_ini, 0.0, s_fim, *fixas]
    if lam.sulco:
        fixas += [lam.sulco["s0"], lam.sulco["s1"]]
    ss = estacoes(lambda s: anel(lam, s)[0], fino, tol, fixas=fixas)
    an, dfio, bis, afi = [], [], [], []
    for s in ss:
        p, d, b = anel(lam, s)
        an.append(p)
        dfio.append(d)
        bis.append(b)
        afi.append(np.full(len(d), lam.afiado(s)))
    an = np.array(an)
    N = an.shape[1]
    ia = N // 2
    nl = ia - 1  # pontos de um lado
    # vivas: P0, P1, (F0, F4), P7, P8 e o fio
    vivos_lado = [0, 1, nl - 2, nl - 1]
    if lam.sulco:
        vivos_lado += [2, 6]
    vivas = [ia]
    for i in vivos_lado:
        vivas += [1 + i, N - 1 - i]
    ponta = (0.0, -lam.L, lam.ponta_z)
    ids = m.loft(
        an,
        mat,
        ponta1=ponta,
        tampa0=True,
        ilhas=[{"j": (0, ia), "peso": peso}, {"j": (ia, N), "peso": peso}],
        peso_tampa=0.05,
        vivas_j=vivas,
        attrs={"d_fio": dfio, "bisel": bis, "afiado": afi},
        attrs_ponta={"d_fio": 0.0, "bisel": 0.0, "afiado": 1.0},
    )
    return {"estacoes": ss, "ids": ids, "ponta": ponta, "n_anel": N}
