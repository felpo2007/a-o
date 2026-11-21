"""Vegetação nova, feita só por código (numpy + Blender para a prévia).

Chaves: exp_figueira, exp_arvore_a, exp_arvore_b, exp_rocha, exp_samambaia.

Formato igual ao das árvores prontas (tools/prep_trees.py):
- em studs (1 stud = 0,28 m), Y para cima, sem transformação nos nós;
- nós `Madeira0` (tronco e galhos), `Raizes0` (raízes, fora da medida do tools/troncos.py) e
  `Folhas0` (cartões com alfa: o AssetLoader liga Transparency e DoubleSided pelo nome);
- metal 0 e rugosidade alta; folha com alphaMode MASK, dupla face e cor sangrada sob o alfa.

O pivô é a origem, no pé do tronco. Y = 0 é a linha do chão e a base desce um pouco abaixo dela.

Uso:
  blender -b --factory-startup -P tools/blender/exp_plantas.py -- <chave ...|todas>
          [--so-previa] [--sem-previa]
"""

from __future__ import annotations

import json
import math
import struct
import sys
import zlib
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum  # noqa: E402
import glb  # noqa: E402

M = comum.M_POR_STUD
SAIDA = comum.SAIDA
TETO_ARVORE = 5960  # o teste cobra 6.000 por modelo de vegetação


# ---------------------------------------------------------------- utilidades
def unit(v: np.ndarray) -> np.ndarray:
    v = np.asarray(v, np.float64)
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def suave(a: float, b: float, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def png_bytes(a: np.ndarray) -> bytes:
    """PNG de 8 bits (RGB ou RGBA), linha de cima primeiro, com o filtro Sub."""
    h, w, c = a.shape
    f = a.astype(np.int16)
    sub = a.copy()
    sub[:, 1:] = ((f[:, 1:] - f[:, :-1]) & 255).astype(np.uint8)
    cru = b"".join(b"\x01" + sub[y].tobytes() for y in range(h))

    def bloco(t: bytes, d: bytes) -> bytes:
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, {3: 2, 4: 6}[c], 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + bloco(b"IHDR", ihdr)
        + bloco(b"IDAT", zlib.compress(cru, 8))
        + bloco(b"IEND", b"")
    )


def para_u8(a: np.ndarray) -> np.ndarray:
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def sangra(rgb: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Preenche a cor fora da máscara (pirâmide puxa-empurra): sem halo na borda do alfa."""
    pir = []
    c = rgb * mask[..., None]
    w = mask.astype(np.float64)
    while c.shape[0] > 1:
        pir.append((c, w))
        c = (c[::2, ::2] + c[1::2, ::2] + c[::2, 1::2] + c[1::2, 1::2]) / 4
        w = (w[::2, ::2] + w[1::2, ::2] + w[::2, 1::2] + w[1::2, 1::2]) / 4
    cor = c / np.maximum(w[..., None], 1e-6)
    for c, w in reversed(pir):
        cima = np.repeat(np.repeat(cor, 2, 0), 2, 1)
        cor = c + (1 - w)[..., None] * cima
    return np.where(mask[..., None], rgb, cor)


class Ruido3D:
    """Ruído de valor em 3D, com interpolação suave."""

    def __init__(self, seed: int, n: int = 64):
        self.n = n
        self.t = np.random.default_rng(seed).random((n, n, n), dtype=np.float32)

    def __call__(self, p: np.ndarray) -> np.ndarray:
        i = np.floor(p).astype(np.int64)
        f = (p - i).astype(np.float32)
        u = f * f * (3 - 2 * f)
        i0 = i % self.n
        i1 = (i + 1) % self.n
        t = self.t

        def v(a, b, c):
            return t[a[..., 0], b[..., 1], c[..., 2]]

        x, y, z = u[..., 0], u[..., 1], u[..., 2]
        c00 = v(i0, i0, i0) * (1 - x) + v(i1, i0, i0) * x
        c10 = v(i0, i1, i0) * (1 - x) + v(i1, i1, i0) * x
        c01 = v(i0, i0, i1) * (1 - x) + v(i1, i0, i1) * x
        c11 = v(i0, i1, i1) * (1 - x) + v(i1, i1, i1) * x
        return (c00 * (1 - y) + c10 * y) * (1 - z) + (c01 * (1 - y) + c11 * y) * z

    def fbm(self, p: np.ndarray, oitavas: int = 4) -> np.ndarray:
        soma, peso, amp = 0.0, 0.0, 1.0
        q = np.asarray(p, np.float64)
        for k in range(oitavas):
            soma = soma + amp * self(q + 17.3 * k)
            peso += amp
            amp *= 0.5
            q = q * 2.03
        return soma / peso


def ruido_fft(px: int, seed: int, beta: float, estica_y: float = 1.0) -> np.ndarray:
    """Ruído periódico (repete nas bordas), de 0 a 1. estica_y > 1 alonga na vertical."""
    w = np.random.default_rng(seed).normal(size=(px, px))
    fx = np.fft.fftfreq(px)[None, :] * px
    fy = np.fft.fftfreq(px)[:, None] * px * estica_y
    f2 = fx * fx + fy * fy
    f2[0, 0] = 1.0
    F = np.fft.fft2(w) / f2 ** (beta / 2)
    F[0, 0] = 0.0
    n = np.fft.ifft2(F).real
    return (n - n.min()) / (n.max() - n.min())


def mistura(a, b, t):
    a, b = np.asarray(a, np.float64), np.asarray(b, np.float64)
    t = np.asarray(t, np.float64)
    if t.ndim and a.ndim:
        t = t[..., None]
    return a * (1 - t) + b * t


# ---------------------------------------------------------------- malha
class Malha:
    def __init__(self):
        self.ps: list[np.ndarray] = []
        self.ns: list[np.ndarray] = []
        self.us: list[np.ndarray] = []
        self.fs: list[np.ndarray] = []
        self.nv = 0

    def add(self, p, n, uv, f) -> None:
        self.ps.append(np.asarray(p, np.float64))
        self.ns.append(np.asarray(n, np.float64))
        self.us.append(np.asarray(uv, np.float64))
        self.fs.append(np.asarray(f, np.int64) + self.nv)
        self.nv += len(p)

    @property
    def tris(self) -> int:
        return int(sum(len(f) for f in self.fs))

    def arrays(self):
        return np.vstack(self.ps), unit(np.vstack(self.ns)), np.vstack(self.us), np.vstack(self.fs)


def quadro(path: np.ndarray):
    """Tangente, normal e binormal por transporte paralelo (a normal começa puxada para cima)."""
    t = unit(np.gradient(path, axis=0))
    n = np.zeros_like(path)
    ref = np.array([0, 0, 1.0]) if abs(t[0, 2]) < 0.9 else np.array([1.0, 0, 0])
    n[0] = unit(ref - t[0] * (ref @ t[0]))
    for i in range(1, len(path)):
        v = n[i - 1] - t[i] * (n[i - 1] @ t[i])
        n[i] = unit(v)
    return t, n, np.cross(t, n)


def tubo(
    m: Malha,
    path,
    raios,
    lados: int,
    perfil=None,
    achata=(1.0, 1.0),
    tile_m: float = 1.7,
) -> None:
    """Tubo ao longo de `path`. perfil(th, s) multiplica o raio (sulcos do tronco)."""
    path = np.asarray(path, np.float64)
    raios = np.asarray(raios, np.float64)
    nr = len(path)
    t, nn, bb = quadro(path)
    th = np.linspace(0, 2 * math.pi, lados + 1)
    c, s = np.cos(th), np.sin(th)
    rad = np.repeat(raios[:, None], lados + 1, axis=1)
    if perfil is not None:
        rad = rad * perfil(th, np.linspace(0, 1, nr))
    radial = (
        c[None, :, None] * achata[0] * nn[:, None, :]
        + s[None, :, None] * achata[1] * bb[:, None, :]
    )
    P = path[:, None, :] + rad[..., None] * radial
    ida = np.r_[1:lados, 0, 1]
    volta = np.r_[lados - 1, 0 : lados - 1, lados - 1]
    du = P[:, ida] - P[:, volta]
    dv = np.gradient(P, axis=0)
    N = np.cross(du, dv)
    ln = np.linalg.norm(N, axis=-1, keepdims=True)
    N = np.where(ln > 1e-9, N / np.maximum(ln, 1e-12), unit(radial))
    r_med = float(max(raios.mean(), 1e-3))
    volta_m = 2 * math.pi * r_med
    arco = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))]
    if volta_m < tile_m:
        # tubo fino: um pedaço da casca, espelhado na volta (sem emenda e sem esmagar a textura,
        # que em volta inteira virava manchas de onça nas raízes aéreas)
        k = volta_m / tile_m / 2
        frac = 1 - np.abs(2 * np.arange(lados + 1) / lados - 1)
        U = np.repeat((k * frac)[None, :], nr, axis=0)
        V = np.repeat((arco / tile_m)[:, None], lados + 1, axis=1)
    else:
        ku = max(1, round(volta_m / tile_m))
        U = np.repeat((ku * np.arange(lados + 1) / lados)[None, :], nr, axis=0)
        V = np.repeat((arco / max(volta_m / ku, 1e-3))[:, None], lados + 1, axis=1)
    uv = np.stack([U, V], axis=-1)
    a = (np.arange(nr - 1)[:, None] * (lados + 1) + np.arange(lados)[None, :]).reshape(-1)
    b, c2, d = a + 1, a + lados + 2, a + lados + 1
    f = np.vstack([np.column_stack([a, b, c2]), np.column_stack([a, c2, d])])
    m.add(P.reshape(-1, 3), N.reshape(-1, 3), uv.reshape(-1, 2), f)


def bezier(a, b, c, n: int) -> np.ndarray:
    t = np.linspace(0, 1, n + 1)[:, None]
    return (1 - t) ** 2 * a + 2 * (1 - t) * t * b + t**2 * c


def ondula(p: np.ndarray, amp: float, rng) -> np.ndarray:
    n = len(p)
    if n < 3:
        return p
    jan = np.sin(np.linspace(0, math.pi, n))[:, None]
    return p + rng.normal(0, amp, (n, 3)) * jan


def lados_de(r: float) -> int:
    for lim, k in ((0.45, 7), (0.25, 5), (0.12, 4)):
        if r >= lim:
            return k
    return 3


def galho(m: Malha, a, d0, b, r0, r1, rng, m_seg=1.6, curva=0.42, sobe=0.12, tile=1.7):
    a, b = np.asarray(a, np.float64), np.asarray(b, np.float64)
    L = float(np.linalg.norm(b - a))
    n = int(np.clip(L / m_seg, 2, 8))
    ctrl = a + unit(d0) * L * curva + np.array([0, 0, sobe * L])
    p = ondula(bezier(a, ctrl, b, n), min(0.09, 0.022 * L), rng)
    p[0], p[-1] = a, b
    rr = np.linspace(r0, r1, n + 1)
    tubo(m, p, rr, lados_de(r0), tile_m=tile)
    return p, rr


def kmeans(p: np.ndarray, k: int, rng, it: int = 14):
    if len(p) <= k:
        return np.arange(len(p)), p.copy()
    c = p[rng.choice(len(p), k, replace=False)].copy()
    lab = np.zeros(len(p), np.int64)
    for _ in range(it):
        d = ((p[:, None] - c[None]) ** 2).sum(-1)
        lab = d.argmin(1)
        for j in range(k):
            if (lab == j).any():
                c[j] = p[lab == j].mean(0)
    return lab, c


# ---------------------------------------------------------------- pintura das texturas
def pinta_linha(buf, a, b, r, cor) -> None:
    h, w = buf.shape[:2]
    x0 = int(max(0, min(a[0], b[0]) - r - 2))
    x1 = int(min(w, max(a[0], b[0]) + r + 3))
    y0 = int(max(0, min(a[1], b[1]) - r - 2))
    y1 = int(min(h, max(a[1], b[1]) + r + 3))
    if x1 <= x0 or y1 <= y0:
        return
    X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
    ab = np.array(b, np.float64) - a
    t = np.clip(((X - a[0]) * ab[0] + (Y - a[1]) * ab[1]) / max(ab @ ab, 1e-6), 0, 1)
    d = np.hypot(X - a[0] - t * ab[0], Y - a[1] - t * ab[1])
    al = np.clip(r - d + 0.5, 0, 1)[..., None]
    reg = buf[y0:y1, x0:x1]
    reg[..., :3] = reg[..., :3] * (1 - al) + np.asarray(cor) * al
    reg[..., 3:] = reg[..., 3:] * (1 - al) + al


def pinta_folha(buf, x, y, ang, comp, larg, cor, forma, serra=0.0, sombra=0.42, nervo=True):
    """Uma folha em `buf` (RGB pré-multiplicado + alfa). larg = meia largura / comprimento."""
    h, w = buf.shape[:2]
    ca, sa = math.cos(ang), math.sin(ang)
    mx, my = x + ca * comp / 2, y + sa * comp / 2
    rb = comp * (0.56 + larg) + 5
    x0, x1 = int(max(0, mx - rb)), int(min(w, mx + rb + 1))
    y0, y1 = int(max(0, my - rb)), int(min(h, my + rb + 1))
    if x1 <= x0 or y1 <= y0:
        return
    X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)

    def mascara(ox: float, oy: float):
        dx, dy = X - x - ox, Y - y - oy
        u = (dx * ca + dy * sa) / comp
        v = (-dx * sa + dy * ca) / comp
        uc = np.clip(u, 0, 1)
        p = np.sin(math.pi * uc ** forma[0]) ** forma[1] * larg
        if serra > 0:
            p = p * (1 - serra * (0.5 + 0.5 * np.sin(uc * 46)))
        d = (p - np.abs(v)) * comp
        return np.clip(d / 1.1 + 0.5, 0, 1) * (u > 0) * (u < 1), u, v

    reg = buf[y0:y1, x0:x1]
    if sombra > 0:
        desl = max(1.5, comp * 0.07)
        ms, _, _ = mascara(desl * 0.7, desl)
        reg[..., :3] *= (1 - sombra * ms)[..., None]
    al, u, v = mascara(0.0, 0.0)
    if not al.any():
        return
    lado = np.tanh(v / max(larg * 0.25, 1e-3))
    tom = 1.0 + 0.15 * lado + 0.13 * (u - 0.45)
    if nervo:
        lat = np.cos((u - np.abs(v) * 1.5) * 2 * math.pi * 7)
        tom = tom * (1 - 0.07 * suave(0.72, 0.98, lat))
    c = np.asarray(cor)[None, None, :] * tom[..., None]
    if nervo:
        mid = np.exp(-((v / max(0.018, larg * 0.07)) ** 2))[..., None] * 0.45
        c = c * (1 - mid) + (np.asarray(cor) * 1.45 + 0.05)[None, None, :] * mid
    a = al[..., None]
    reg[..., :3] = reg[..., :3] * (1 - a) + np.clip(c, 0, 1) * a
    reg[..., 3:] = reg[..., 3:] * (1 - a) + a


def fecha_atlas(buf: np.ndarray, n_tiles: tuple[int, int]) -> np.ndarray:
    """2x -> 1x, alfa recortado, sem nada encostando na borda do tile, cor sangrada."""
    a2 = buf[..., 3]
    c2 = buf[..., :3]
    al = (a2[::2, ::2] + a2[1::2, ::2] + a2[::2, 1::2] + a2[1::2, 1::2]) / 4
    c = (c2[::2, ::2] + c2[1::2, ::2] + c2[::2, 1::2] + c2[1::2, 1::2]) / 4
    rgb = c / np.maximum(al[..., None], 1e-4)
    alfa = suave(0.36, 0.64, al)
    h, w = alfa.shape
    th, tw = h // n_tiles[0], w // n_tiles[1]
    fy = (np.arange(h) % th).astype(np.int64)
    fx = (np.arange(w) % tw).astype(np.int64)
    borda_y = (fy < 3) | (fy > th - 4)
    borda_x = (fx < 3) | (fx > tw - 4)
    alfa[borda_y, :] = 0
    alfa[:, borda_x] = 0
    rgb = sangra(np.clip(rgb, 0, 1), alfa > 0.5)
    return para_u8(np.dstack([rgb, alfa]))


def atlas_folhas(cfg: dict, seed: int, px: int = 1024) -> np.ndarray:
    """Atlas 4 x 4: cada linha é um tom (de sol a sombra), cada tile um ramalhete redondo."""
    rng = np.random.default_rng(seed)
    N = 4
    T = px * 2 // N
    buf = np.zeros((px * 2, px * 2, 4), np.float64)
    pal = [np.array(c, np.float64) for c in cfg["paleta"]]
    tons = (1.16, 1.03, 0.9, 0.76)
    for lin in range(N):
        for col in range(N):
            tile = np.zeros((T, T, 4), np.float64)
            cx = cy = T / 2
            for _ in range(7):
                a = rng.uniform(0, 2 * math.pi)
                r = T * rng.uniform(0.2, 0.36)
                fim = (cx + math.cos(a) * r, cy + math.sin(a) * r)
                pinta_linha(tile, np.array((cx, cy)), np.array(fim), T * 0.006, (0.2, 0.14, 0.09))
            nf = cfg["n"]
            rs = T * (0.02 + 0.37 * np.sqrt(rng.random(nf)))
            ordem = np.argsort(-rs + rng.normal(0, T * 0.05, nf))
            rumo = rng.uniform(0, 2 * math.pi)  # folhas para um lado: sem desenho de roseta
            for k in ordem:
                a = rng.uniform(0, 2 * math.pi)
                bx, by = cx + math.cos(a) * rs[k], cy + math.sin(a) * rs[k]
                ang = (rumo if rng.random() < 0.72 else a) + rng.normal(0, 0.7)
                comp = T * cfg["comp"] * rng.uniform(0.78, 1.22)
                folga = T * 0.46 - math.hypot(
                    bx + math.cos(ang) * comp - cx, by + math.sin(ang) * comp - cy
                )
                if folga < 0:
                    ang = a
                    comp = max(T * 0.05, min(comp, T * 0.46 - rs[k]))
                t = rng.random()
                base = (
                    mistura(pal[0], pal[1], t * 2)
                    if t < 0.5
                    else mistura(pal[1], pal[2], t * 2 - 1)
                )
                if rng.random() < 0.13:
                    base = mistura(base, pal[3], rng.uniform(0.35, 0.8))
                base = base * rng.uniform(0.92, 1.08) * tons[lin]
                pinta_folha(
                    tile,
                    bx,
                    by,
                    ang,
                    comp,
                    cfg["larg"] * rng.uniform(0.88, 1.12),
                    base,
                    cfg["forma"],
                )
            buf[lin * T : (lin + 1) * T, col * T : (col + 1) * T] = tile
    return fecha_atlas(buf, (N, N))


def atlas_samambaia(seed: int, px: int = 1024) -> np.ndarray:
    """Quatro frondes em pé, cada uma numa faixa de 1/4 da largura (base embaixo)."""
    rng = np.random.default_rng(seed)
    N = 4
    H = px * 2
    Wf = H // N
    buf = np.zeros((H, H, 4), np.float64)
    claro = np.array((0.42, 0.56, 0.15))
    medio = np.array((0.25, 0.42, 0.11))
    escuro = np.array((0.14, 0.29, 0.09))
    for f in range(N):
        tile = np.zeros((H, Wf, 4), np.float64)
        cx = Wf / 2
        topo, base = H * 0.012, H * 0.985
        curva = rng.uniform(-0.05, 0.05) * Wf
        pares = 34
        for i in range(pares):
            s = (i + 0.5) / pares
            if s < 0.13:  # pé da fronde sem folíolos: a touceira não vira um cone
                continue
            y = base + (topo - base) * s
            x = cx + curva * math.sin(s * math.pi)
            perfil = math.sin(math.pi * min(1.0, s * 0.94 + 0.09)) ** 0.72
            comp = Wf * 0.475 * perfil * rng.uniform(0.93, 1.03)
            if comp < 4:
                continue
            for lado in (-1, 1):
                sobe = 0.34 + 0.5 * s
                ang = -math.pi / 2 + lado * (math.pi / 2 - sobe)
                dy = (H / pares) * 0.28 * lado
                t = float(np.clip(s + rng.normal(0, 0.08), 0, 1))
                cor = mistura(escuro, medio, t * 2) if t < 0.5 else mistura(medio, claro, t * 2 - 1)
                cor = cor * rng.uniform(0.9, 1.12)
                pinta_folha(
                    tile, x, y + dy, ang, comp, 0.105, cor, (0.62, 0.72), serra=0.22, sombra=0.22
                )
        for i in range(60):
            s0, s1 = i / 60, (i + 1) / 60
            a = np.array((cx + curva * math.sin(s0 * math.pi), base + (topo - base) * s0))
            b = np.array((cx + curva * math.sin(s1 * math.pi), base + (topo - base) * s1))
            pinta_linha(tile, a, b, max(1.0, Wf * 0.016 * (1 - s0 * 0.85)), (0.27, 0.27, 0.10))
        buf[:, f * Wf : (f + 1) * Wf] = tile
    return fecha_atlas(buf, (1, N))


def casca(cfg: dict, seed: int, px: int = 512) -> tuple[np.ndarray, np.ndarray]:
    """Casca que repete: cor e mapa normal (OpenGL)."""
    a = ruido_fft(px, seed, 1.75, cfg.get("sulco", 3.4))
    sulco = 1 - np.abs(2 * a - 1)
    b = ruido_fft(px, seed + 1, 2.1, 2.2)
    c = ruido_fft(px, seed + 2, 1.05, 1.4)
    h = 0.56 * suave(0.34, 0.96, sulco) + 0.32 * b + 0.12 * c
    h = (h - h.min()) / (h.max() - h.min())
    escuro, medio, claro = (np.array(x, np.float64) for x in cfg["cores"])
    cor = np.where(
        (h < 0.5)[..., None], mistura(escuro, medio, h * 2), mistura(medio, claro, h * 2 - 1)
    )
    # manchas alongadas no sentido do tronco: redondas pareciam camuflagem
    liq = suave(0.6, 0.76, ruido_fft(px, seed + 3, 1.8, 3.2)) * suave(0.42, 0.68, c)
    cor = mistura(
        cor, np.array(cfg.get("liquen", (0.62, 0.61, 0.5))), liq * cfg.get("k_liquen", 0.55)
    )
    mus = suave(0.64, 0.82, ruido_fft(px, seed + 4, 2.2, 2.6))
    cor = mistura(cor, np.array((0.24, 0.31, 0.12)), mus * cfg.get("k_musgo", 0.4))
    cor = cor * (0.8 + 0.34 * h)[..., None]
    k = cfg.get("relevo", 7.0)
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * k
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * k
    n = unit(np.dstack([-dx, dy, np.ones_like(h)]))
    return para_u8(cor), para_u8(n * 0.5 + 0.5)


# ---------------------------------------------------------------- árvores
PAL_FIGUEIRA = (
    (0.19, 0.29, 0.07),
    (0.31, 0.42, 0.11),
    (0.45, 0.54, 0.15),
    (0.68, 0.66, 0.20),
)
PAL_A = (
    (0.22, 0.31, 0.08),
    (0.36, 0.45, 0.12),
    (0.50, 0.57, 0.16),
    (0.72, 0.68, 0.22),
)
PAL_B = (
    (0.16, 0.27, 0.08),
    (0.27, 0.39, 0.11),
    (0.39, 0.50, 0.14),
    (0.60, 0.61, 0.18),
)

ARVORES: dict[str, dict] = {
    "exp_figueira": {
        "seed": 1965,
        "fundo": 0.30,
        "tronco": {
            "h": 7.0,
            "r0": 1.62,
            "r1": 0.62,
            "incl": (0.3, -0.18),
            "lados": 40,
            "aneis": 10,
            "lobos": 9,
            "a0": 0.85,
            "a1": 0.27,
            "decai": 0.13,
            "giro": 1.0,
        },
        "raizes": {"n": 9, "comp": (3.2, 5.6), "r": (0.24, 0.40), "h": (1.0, 2.2), "filhas": 6},
        "copa": {
            "n": 46,
            "zc": 10.0,
            "rx": 7.1,
            "ry": 5.9,
            "rz": 4.2,
            "z_min": -0.30,
            "rtufo": (1.7, 2.6),
            "achata": 0.7,
            "ruga": 0.24,
        },
        "galhos": {"n": 8, "r": 0.78, "t0": 0.5, "sub": 3},
        "aereas": {"n": 11, "r": (0.05, 0.12)},
        "cartao": 0.56,
        "folha": {
            "n": 130,
            "comp": 0.105,
            "larg": 0.26,
            "forma": (0.74, 0.86),
            "paleta": PAL_FIGUEIRA,
        },
        "casca": {
            "cores": ((0.13, 0.09, 0.06), (0.33, 0.24, 0.16), (0.53, 0.43, 0.31)),
            "sulco": 3.8,
            "k_liquen": 0.3,
            "k_musgo": 0.15,
            "relevo": 10.0,
        },
    },
    "exp_arvore_a": {
        "seed": 1966,
        "fundo": 0.24,
        "tronco": {
            "h": 10.2,
            "r0": 0.40,
            "r1": 0.13,
            "incl": (0.7, 0.3),
            "curva": (-0.75, 0.4),
            "lados": 14,
            "aneis": 9,
            "lobos": 4,
            "a0": 0.45,
            "a1": 0.09,
            "decai": 0.09,
            "giro": 0.5,
        },
        "raizes": {"n": 5, "comp": (0.9, 1.7), "r": (0.08, 0.13), "h": (0.3, 0.55), "filhas": 2},
        "camadas": [
            (5.4, 2, 4.2, 1.35),
            (7.4, 3, 4.6, 1.4),
            (9.6, 3, 4.1, 1.35),
            (11.4, 2, 3.0, 1.25),
            (12.6, 2, 1.2, 1.2),
        ],
        "copa": {"achata": 0.66, "tufos_por_pad": 5},
        "galhos": {"n": 9, "r": 0.24, "t0": 0.36, "sub": 3},
        "aereas": None,
        "max_cartoes": 1500,  # copa aberta: o que sobra do teto fica sem usar
        "cartao": 0.5,
        "folha": {"n": 90, "comp": 0.13, "larg": 0.2, "forma": (0.8, 0.92), "paleta": PAL_A},
        "casca": {
            "cores": ((0.17, 0.13, 0.10), (0.40, 0.33, 0.26), (0.62, 0.56, 0.47)),
            "sulco": 2.8,
            "k_liquen": 0.6,
            "k_musgo": 0.18,
        },
    },
    "exp_arvore_b": {
        "seed": 1967,
        "fundo": 0.22,
        "tronco": {
            "h": 3.7,
            "r0": 0.36,
            "r1": 0.20,
            "incl": (1.7, 0.55),
            "lados": 12,
            "aneis": 7,
            "lobos": 5,
            "a0": 0.55,
            "a1": 0.08,
            "decai": 0.14,
            "giro": 0.6,
        },
        "raizes": {"n": 6, "comp": (0.9, 1.6), "r": (0.07, 0.12), "h": (0.25, 0.45), "filhas": 2},
        "copa": {
            "n": 30,
            "zc": 5.6,
            "cx": 1.15,
            "cy": 0.38,
            "rx": 3.25,
            "ry": 3.1,
            "rz": 2.15,
            "z_min": -0.42,
            "rtufo": (1.15, 1.6),
            "achata": 0.78,
            "ruga": 0.12,
        },
        "galhos": {"n": 6, "r": 0.24, "t0": 0.7, "sub": 3},
        "aereas": None,
        "max_cartoes": 2000,
        "cartao": 0.56,
        "folha": {"n": 120, "comp": 0.115, "larg": 0.32, "forma": (0.72, 0.8), "paleta": PAL_B},
        "casca": {
            "cores": ((0.12, 0.09, 0.07), (0.31, 0.24, 0.18), (0.49, 0.40, 0.31)),
            "sulco": 2.6,
            "k_liquen": 0.42,
            "k_musgo": 0.3,
        },
    },
}


def tufos_cupula(cfg: dict, rng) -> tuple[np.ndarray, np.ndarray]:
    c = cfg["copa"]
    n = c["n"]
    ouro = math.pi * (3 - math.sqrt(5))
    zs = np.linspace(0.97, c["z_min"], n)
    fase = rng.uniform(0, 2 * math.pi, 3)
    pts = []
    for i, z in enumerate(zs):
        r = math.sqrt(max(0.0, 1 - z * z))
        a = ouro * i + rng.normal(0, 0.18)
        ruga = 1 + c["ruga"] * (0.6 * math.sin(2 * a + fase[0]) + 0.4 * math.sin(3 * a + fase[1]))
        k = rng.uniform(0.78, 1.06) * ruga
        pts.append(
            (
                c.get("cx", 0.0) + c["rx"] * r * math.cos(a) * k,
                c.get("cy", 0.0) + c["ry"] * r * math.sin(a) * k,
                c["zc"] + c["rz"] * z * rng.uniform(0.92, 1.05),
            )
        )
    C = np.array(pts)
    R = rng.uniform(c["rtufo"][0], c["rtufo"][1], n)
    return C, R


def tufos_camadas(cfg: dict, rng) -> tuple[np.ndarray, np.ndarray]:
    """Copa aberta: almofadas de folha em andares, com vãos entre elas."""
    pts, rs = [], []
    k = cfg["copa"]["tufos_por_pad"]
    giro = rng.uniform(0, 2 * math.pi)
    for z, n, alcance, r in cfg["camadas"]:
        for i in range(n):
            a = giro + 2 * math.pi * (i + rng.uniform(-0.2, 0.2)) / n
            giro += 0.9
            d = alcance * rng.uniform(0.72, 1.12)
            cx = cfg["tronco"]["incl"][0] * z / 9 + math.cos(a) * d
            cy = cfg["tronco"]["incl"][1] * z / 9 + math.sin(a) * d
            cz = z + rng.uniform(-0.45, 0.45)
            for _ in range(k):
                # tufos menores e soltos: almofada lisa parecia árvore podada (topiaria)
                pts.append(
                    (
                        cx + rng.normal(0, r * 0.95),
                        cy + rng.normal(0, r * 0.95),
                        cz + rng.normal(0, r * 0.42),
                    )
                )
                rs.append(r * rng.uniform(0.5, 0.86))
    return np.array(pts), np.array(rs)


def faz_tronco(mad: Malha, cfg: dict, rng):
    t = cfg["tronco"]
    fundo = cfg["fundo"]
    ix, iy = t["incl"]
    a = np.array((0.0, 0.0, -fundo))
    sx, sy = t.get("curva", (0.0, 0.0))
    b = np.array((ix * 0.15 + sx, iy * 0.15 + sy, t["h"] * 0.48))
    c = np.array((ix, iy, t["h"]))
    s = np.linspace(0, 1, t["aneis"] + 1) ** 1.45
    tt = s[:, None]
    p = (1 - tt) ** 2 * a + 2 * (1 - tt) * tt * b + tt**2 * c
    r = t["r1"] + (t["r0"] - t["r1"]) * (1 - s) ** 1.5
    # o topo afina até fechar dentro da copa: a boca aberta do tubo aparecia entre os galhos
    rumo = unit(p[-1] - p[-2])
    extra = np.array((1.6, 3.6, 6.5))[:, None]
    p_tubo = np.vstack([p, p[-1] + rumo * t["r1"] * extra])
    r_tubo = np.r_[r, t["r1"] * np.array((0.84, 0.54, 0.04))]
    thk = np.sort(rng.uniform(0, 2 * math.pi, t["lobos"]))
    thk = (thk + np.linspace(0, 2 * math.pi, t["lobos"], endpoint=False)) / 2
    wk = rng.uniform(0.19, 0.34, t["lobos"])
    ak = rng.uniform(0.62, 1.0, t["lobos"])

    def perfil(th, si):
        si = si[:, None] ** 1.45
        amp = t["a0"] * np.exp(-si / t["decai"]) + t["a1"] * (1 - si * 0.55)
        soma = np.zeros((len(si), len(th)))
        for k in range(t["lobos"]):
            delta = th[None, :] - (thk[k] + t["giro"] * si)
            delta = (delta + math.pi) % (2 * math.pi) - math.pi
            soma += ak[k] * np.exp(-((delta / wk[k]) ** 2))
        return 0.86 + amp * soma

    tubo(mad, p_tubo, r_tubo, t["lados"], perfil=perfil, tile_m=1.5)
    return p, r, thk


def faz_raizes(raiz: Malha, cfg: dict, thk, rng) -> None:
    c = cfg["raizes"]
    r_t = cfg["tronco"]["r0"]
    fundo = cfg["fundo"]
    angs = list(thk) + list(rng.uniform(0, 2 * math.pi, max(0, c["n"] - len(thk))))
    for k in range(c["n"]):
        a = float(angs[k % len(angs)]) + rng.normal(0, 0.12)
        out = np.array((math.cos(a), math.sin(a), 0.0))
        lado = np.array((-out[1], out[0], 0.0))
        L = rng.uniform(*c["comp"])
        h = rng.uniform(*c["h"])
        r0 = rng.uniform(*c["r"])
        ini = out * r_t * 0.5 + np.array((0, 0, h))
        ctrl = out * (r_t + L * 0.24) + np.array((0, 0, 0.3 * h))
        meio = out * (r_t + L * 0.56) + lado * rng.normal(0, 0.34) + np.array((0, 0, 0.1))
        p1 = bezier(ini, ctrl, meio, 4)
        fim = meio + unit(out + lado * rng.normal(0, 0.5)) * L * 0.46
        fim[2] = -min(fundo, 0.12)
        p2 = bezier(
            meio, (meio + fim) / 2 + lado * rng.normal(0, 0.28) + np.array((0, 0, 0.07)), fim, 3
        )[1:]
        p = np.vstack([p1, p2])
        # serpenteia de lado (raiz reta parecia estaca) e sobe e desce um pouco no chão
        fase, onda = rng.uniform(0, 2 * math.pi), rng.uniform(1.6, 2.6)
        sv = np.linspace(0, 1, len(p))
        p += lado * (np.sin(sv * onda * math.pi + fase) * 0.16 * L * 0.32 * sv)[:, None]
        p[2:-1, 2] += rng.normal(0, 0.035, len(p) - 3)
        p[1:-1] += rng.normal(0, 0.03, (len(p) - 2, 3)) * np.array((1, 1, 0.25))
        rr = r0 * np.linspace(1.0, 0.14, len(p)) ** 0.85
        tubo(raiz, p, rr, 5 if r0 > 0.12 else 4, achata=(1.42, 0.82), tile_m=1.5)
        if k < c["filhas"]:
            j = 4
            b = p[j] + unit(out + lado * rng.choice((-1.0, 1.0)) * rng.uniform(0.7, 1.1)) * (
                L * rng.uniform(0.34, 0.52)
            )
            b[2] = -min(fundo, 0.12)
            q = bezier(p[j], (p[j] + b) / 2 + np.array((0, 0, 0.06)), b, 3)
            tubo(raiz, q, np.linspace(rr[j] * 0.55, 0.018, 4), 3, achata=(1.3, 0.85), tile_m=1.5)


def faz_galhos(mad: Malha, cfg: dict, p_t, r_t, C: np.ndarray, rng) -> list[tuple]:
    g = cfg["galhos"]
    tang = unit(np.gradient(p_t, axis=0))
    lab, cent = kmeans(C, g["n"], rng)
    zmin, zmax = float(C[:, 2].min()), float(C[:, 2].max())
    total = len(C)
    pendurar = []
    for k in range(g["n"]):
        idx = np.nonzero(lab == k)[0]
        if len(idx) == 0:
            continue
        alvo = cent[k]
        fz = float(np.clip((alvo[2] - zmin) / max(zmax - zmin, 1e-3), 0, 1))
        t = g["t0"] + (0.97 - g["t0"]) * fz
        i = int(t * (len(p_t) - 1))
        a = p_t[i]
        rad = unit((alvo - a) * np.array((1, 1, 0)))
        d0 = unit(rad * 0.62 + tang[i] * 0.7)
        rg = float(min(g["r"] * (len(idx) / total) ** 0.42, r_t[i] * 0.84))
        fim = a + (alvo - a) * 0.86
        p, rr = galho(mad, a, d0, fim, rg, rg * 0.34, rng)
        pendurar.append((p, rr))
        n_sub = int(np.clip(round(len(idx) / 2.4), 1, g["sub"]))
        lab2, c2 = kmeans(C[idx], n_sub, rng)
        for s in range(n_sub):
            ii = idx[lab2 == s]
            if len(ii) == 0:
                continue
            j = int(rng.integers(max(1, len(p) // 2 - 1), len(p) - 1))
            d1 = unit(np.gradient(p, axis=0)[j])
            rs = max(float(rr[j]) * 0.66, 0.05)
            alvo2 = p[j] + (c2[s] - p[j]) * 0.82
            q, rq = galho(mad, p[j], d1, alvo2, rs, max(rs * 0.42, 0.028), rng, m_seg=2.0)
            for n_c, c in enumerate(ii):
                # o tufo mais perto do sub-galho já esconde a ponta dele: só os outros pedem graveto
                if n_c % 5 == 4:
                    continue
                j2 = int(rng.integers(max(1, len(q) // 2), len(q)))
                d2 = unit(np.gradient(q, axis=0)[min(j2, len(q) - 1)])
                r3 = max(float(rq[min(j2, len(q) - 1)]) * 0.62, 0.026)
                galho(mad, q[j2], d2, C[c], r3, 0.014, rng, m_seg=3.2, curva=0.3, sobe=0.05)
    return pendurar


def faz_aereas(raiz: Malha, cfg: dict, pendurar: list, rng) -> None:
    c = cfg["aereas"]
    if not c:
        return
    feitas = 0
    tent = 0
    while feitas < c["n"] and tent < 200:
        tent += 1
        p, _ = pendurar[int(rng.integers(len(pendurar)))]
        j = int(rng.integers(1, len(p)))
        o = p[j]
        if o[2] < 3.2 or np.hypot(o[0], o[1]) < 2.0:
            continue
        # em feixes de 1 a 3, como cordas que descem juntas e se abrem perto do chão
        feixe = int(rng.integers(1, 4))
        base_pe = o[:2] + rng.normal(0, 0.32, 2)
        for _ in range(feixe):
            if feitas >= c["n"]:
                break
            topo = o + np.array((rng.normal(0, 0.1), rng.normal(0, 0.1), 0.0))
            pe = np.array((*(base_pe + rng.normal(0, 0.26, 2)), -0.2))
            n = 4
            q = topo[None, :] + (pe - topo)[None, :] * np.linspace(0, 1, n + 1)[:, None]
            q[1:-1, :2] += rng.normal(0, 0.13, (n - 1, 2))
            r0 = rng.uniform(*c["r"])
            rr = r0 * np.linspace(0.68, 1.0, n + 1)
            tubo(raiz, q, rr, 3, tile_m=1.0)
            feitas += 1


def poe_cartoes(fol: Malha, C, R, n_total: int, cfg: dict, rng) -> None:
    c = cfg["copa"]
    ach = c["achata"]
    pesos = R**2
    ni = np.maximum(4, np.floor(pesos / pesos.sum() * n_total).astype(np.int64))
    while ni.sum() > n_total:
        ni[int(np.argmax(ni))] -= 1
    k = 0
    while ni.sum() < n_total:
        ni[k % len(ni)] += 1
        k += 1
    z0, z1 = float(C[:, 2].min()), float(C[:, 2].max())
    for ci, ri, n in zip(C, R, ni, strict=True):
        d = unit(rng.normal(size=(int(n), 3)))
        baixo = d[:, 2] < -0.25
        d[baixo, 2] *= 0.45
        d = unit(d)
        prof = rng.uniform(0.58, 1.05, int(n))
        pos = ci + d * (ri * prof)[:, None] * np.array((1, 1, ach))
        nrm = unit(d * 0.9 + rng.normal(0, 0.3, (int(n), 3)) + np.array((0, 0, 0.14)))
        tan = unit(np.cross(nrm, rng.normal(size=(int(n), 3))))
        bit = np.cross(nrm, tan)
        s = ri * cfg["cartao"] * rng.uniform(0.82, 1.22, int(n))
        cant = np.array(((-1, -1), (1, -1), (1, 1), (-1, 1)), np.float64)
        Q = (
            pos[:, None, :]
            + (cant[None, :, 0, None] * tan[:, None, :] + cant[None, :, 1, None] * bit[:, None, :])
            * s[:, None, None]
        )
        fora = unit(Q - ci)
        vn = unit(nrm[:, None, :] * 0.5 + fora * 0.5 + np.array((0, 0, 0.12)))
        alt = (ci[2] - z0) / max(z1 - z0, 1e-3)
        nota = (
            0.62 * d[:, 2] + 0.5 * (alt - 0.5) + 0.32 * (prof - 0.82) + rng.normal(0, 0.14, int(n))
        )
        lin = np.digitize(-nota, (-0.33, -0.02, 0.28))
        col = rng.integers(0, 4, int(n))
        u0, v0 = col / 4, lin / 4
        uv = np.empty((int(n), 4, 2))
        vira = rng.random(int(n)) < 0.5
        uu = np.array((0, 1, 1, 0), np.float64)
        vv = np.array((1, 1, 0, 0), np.float64)
        for j in range(4):
            uj = np.where(vira, 1 - uu[j], uu[j])
            uv[:, j, 0] = u0 + uj / 4
            uv[:, j, 1] = v0 + vv[j] / 4
        base = np.arange(int(n)) * 4
        f = np.vstack(
            [
                np.column_stack([base, base + 1, base + 2]),
                np.column_stack([base, base + 2, base + 3]),
            ]
        )
        fol.add(Q.reshape(-1, 3), vn.reshape(-1, 3), uv.reshape(-1, 2), f)


def gera_arvore(chave: str) -> dict:
    cfg = ARVORES[chave]
    rng = np.random.default_rng(cfg["seed"])
    mad, raiz, fol = Malha(), Malha(), Malha()
    p_t, r_t, thk = faz_tronco(mad, cfg, rng)
    faz_raizes(raiz, cfg, thk, rng)
    C, R = tufos_camadas(cfg, rng) if "camadas" in cfg else tufos_cupula(cfg, rng)
    pendurar = faz_galhos(mad, cfg, p_t, r_t, C, rng)
    faz_aereas(raiz, cfg, pendurar, rng)
    n_cart = min((TETO_ARVORE - mad.tris - raiz.tris) // 2, cfg.get("max_cartoes", 10**6))
    poe_cartoes(fol, C, R, n_cart, cfg, rng)
    comum.log(chave, "madeira", mad.tris, "raizes", raiz.tris, "cartoes", n_cart)
    atlas = atlas_folhas(cfg["folha"], cfg["seed"] + 100)
    cor, nrm = casca(cfg["casca"], cfg["seed"] + 200)
    pecas = [("Madeira0", mad, "casca"), ("Raizes0", raiz, "casca"), ("Folhas0", fol, "folha")]
    return {"pecas": pecas, "atlas": atlas, "casca_cor": cor, "casca_nrm": nrm}


# ---------------------------------------------------------------- samambaia
def gera_samambaia() -> dict:
    rng = np.random.default_rng(1968)
    fol = Malha()
    anel = ((9, 0.30, 0.42), (15, 0.50, 0.46), (20, 0.70, 0.36))
    for n, alcance, alt in anel:
        fase = rng.uniform(0, 2 * math.pi)
        for k in range(n):
            az = fase + 2 * math.pi * (k + rng.uniform(-0.3, 0.3)) / n
            out = np.array((math.cos(az), math.sin(az), 0.0))
            lado = np.array((-out[1], out[0], 0.0))
            L = alcance * rng.uniform(0.88, 1.04)
            h = alt * rng.uniform(0.82, 1.14)
            a = np.array((0, 0, -0.05)) + out * 0.03
            b = out * L * 0.36 + np.array((0, 0, h * 1.42))
            c = out * L + np.array((0, 0, h * 0.1))
            esp = bezier(a, b, c, 5)
            comp = float(np.linalg.norm(np.diff(esp, axis=0), axis=1).sum())
            meia = comp * 0.21
            tg = unit(np.gradient(esp, axis=0))
            lat = unit(lado + rng.normal(0, 0.1, 3))
            up = unit(np.cross(lat, tg))
            P = np.empty((6, 3, 3))
            N = np.empty((6, 3, 3))
            uv = np.empty((6, 3, 2))
            f_col = int(rng.integers(0, 4))
            for i in range(6):
                s = i / 5
                w = meia * (0.34 + 0.66 * min(1.0, s / 0.3)) * (0.86 + 0.14 * math.sin(math.pi * s))
                cai = 0.26 * w
                P[i, 0] = esp[i] - lat * w - up[i] * cai
                P[i, 1] = esp[i]
                P[i, 2] = esp[i] + lat * w - up[i] * cai
                N[i, 0] = unit(up[i] - lat * 0.34)
                N[i, 1] = up[i]
                N[i, 2] = unit(up[i] + lat * 0.34)
                for j in range(3):
                    uv[i, j] = ((f_col + j / 2) / 4, 1.0 - s)
            idx = (np.arange(5)[:, None] * 3 + np.arange(2)[None, :]).reshape(-1)
            f = np.vstack(
                [
                    np.column_stack([idx, idx + 1, idx + 4]),
                    np.column_stack([idx, idx + 4, idx + 3]),
                ]
            )
            fol.add(P.reshape(-1, 3), N.reshape(-1, 3), uv.reshape(-1, 2), f)
    comum.log("exp_samambaia", "cartoes", fol.tris)
    atlas = atlas_samambaia(1969)
    return {"pecas": [("Folhas0", fol, "folha")], "atlas": atlas}


# ---------------------------------------------------------------- rocha
def icosfera(sub: int) -> tuple[np.ndarray, np.ndarray]:
    t = (1 + 5**0.5) / 2
    vs = [
        (-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t),
        (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1),
    ]  # fmt: skip
    fs = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4),
        (11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8),
        (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]  # fmt: skip
    v = [np.array(x, np.float64) / np.linalg.norm(x) for x in vs]

    def ponto_medio(meio: dict[tuple[int, int], int], a: int, b: int) -> int:
        k = (min(a, b), max(a, b))
        if k not in meio:
            v.append(unit(v[a] + v[b]))
            meio[k] = len(v) - 1
        return meio[k]

    for _ in range(sub):
        meio: dict[tuple[int, int], int] = {}
        novo = []
        for a, b, c in fs:
            ab = ponto_medio(meio, a, b)
            bc = ponto_medio(meio, b, c)
            ca = ponto_medio(meio, c, a)
            novo += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        fs = novo
    return np.array(v), np.array(fs, np.int64)


def normais_vertice(p: np.ndarray, f: np.ndarray) -> np.ndarray:
    n = np.zeros_like(p)
    fn = np.cross(p[f[:, 1]] - p[f[:, 0]], p[f[:, 2]] - p[f[:, 0]])
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    return unit(n)


def octa_uv(d: np.ndarray, sx, sy, sz) -> np.ndarray:
    # z com o sinal do triângulo: quem cruza o equador continua para fora, sem dobrar a UV
    s = np.maximum(np.abs(d[:, 0]) + np.abs(d[:, 1]) + sz * d[:, 2], 0.05)
    u, v = d[:, 0] / s, d[:, 1] / s
    if sz < 0:
        u, v = sx * (1 - d[:, 1] * sy / s), sy * (1 - d[:, 0] * sx / s)
    return np.clip(np.column_stack([u, v]) * 0.97 * 0.5 + 0.5, 0.0, 1.0)


def gera_rocha() -> dict:
    ru = Ruido3D(1970)
    d, f = icosfera(3)
    r = (
        1.0
        + 0.40 * (ru.fbm(d * 1.25 + 3.1, 3) - 0.5)
        + 0.15 * (ru.fbm(d * 3.1 + 7.7, 3) - 0.5)
        + 0.05 * (ru.fbm(d * 7.3 + 1.9, 2) - 0.5)
    )[:, None]
    p = d * r * np.array((1.16, 1.0, 0.98))
    p = p * (2.2 / float(p[:, 0].max() - p[:, 0].min()))
    p[:, :2] -= (p[:, :2].max(axis=0) + p[:, :2].min(axis=0)) / 2
    # o chão corta perto da parte mais larga: a pedra sai da terra, sem "pé" recolhido
    z0 = float(p[:, 2].min() + 0.36 * (p[:, 2].max() - p[:, 2].min()))
    p[:, 2] -= z0
    fundo = 0.26
    abaixo = p[:, 2] < 0
    p[abaixo, 2] *= fundo / float(-p[:, 2].min())
    n = normais_vertice(p, f)

    # UV octaédrica por triângulo: a dobra fica na metade de baixo, enterrada
    tri = f.reshape(-1)
    uv = np.empty((len(f), 3, 2))
    cen = d[f].mean(axis=1)
    for i in range(len(f)):
        sx = 1.0 if cen[i, 0] >= 0 else -1.0
        sy = 1.0 if cen[i, 1] >= 0 else -1.0
        sz = 1.0 if cen[i, 2] >= 0 else -1.0
        uv[i] = octa_uv(d[f[i]], sx, sy, sz)
    chave = np.column_stack([tri, np.round(uv.reshape(-1, 2), 6)])
    _, prim, inv = np.unique(chave, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    P, N, UV = p[tri[prim]], n[tri[prim]], uv.reshape(-1, 2)[prim]
    F = inv.reshape(-1, 3)
    m = Malha()
    m.add(P, N, UV, F)
    comum.log("exp_rocha", "tris", m.tris, "vertices", len(P))
    cor, nrm = textura_rocha(P, N, UV, F, ru)
    return {"pecas": [("Rocha0", m, "rocha")], "rocha_cor": cor, "rocha_nrm": nrm}


def textura_rocha(P, N, UV, F, ru: Ruido3D, px: int = 1024):
    """Cor e normal avaliadas em 3D em cada texel: sem emenda visível entre as dobras da UV."""
    pos = np.zeros((px, px, 3))
    nor = np.zeros((px, px, 3))
    cheio = np.zeros((px, px), bool)
    for t in F:
        q = UV[t] * px
        x0, x1 = int(max(0, np.floor(q[:, 0].min()) - 1)), int(min(px, np.ceil(q[:, 0].max()) + 2))
        y0, y1 = int(max(0, np.floor(q[:, 1].min()) - 1)), int(min(px, np.ceil(q[:, 1].max()) + 2))
        if x1 <= x0 or y1 <= y0:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        den = (q[1, 1] - q[2, 1]) * (q[0, 0] - q[2, 0]) + (q[2, 0] - q[1, 0]) * (q[0, 1] - q[2, 1])
        if abs(den) < 1e-9:
            continue
        a = ((q[1, 1] - q[2, 1]) * (X - q[2, 0]) + (q[2, 0] - q[1, 0]) * (Y - q[2, 1])) / den
        b = ((q[2, 1] - q[0, 1]) * (X - q[2, 0]) + (q[0, 0] - q[2, 0]) * (Y - q[2, 1])) / den
        c = 1 - a - b
        ok = (a >= -0.02) & (b >= -0.02) & (c >= -0.02)
        if not ok.any():
            continue
        bar = np.stack([a, b, c], axis=-1)[ok]
        reg_p, reg_n, reg_c = pos[y0:y1, x0:x1], nor[y0:y1, x0:x1], cheio[y0:y1, x0:x1]
        reg_p[ok] = bar @ P[t]
        reg_n[ok] = bar @ N[t]
        reg_c[ok] = True
    q = pos[cheio]
    nq = unit(nor[cheio])
    g1 = ru.fbm(q * 1.7 + 11.0, 4)
    g2 = ru.fbm(q * 6.5 + 2.0, 4)
    g3 = ru.fbm(q * 22.0 + 5.0, 3)
    # fenda fina, torcida e interrompida: linha contínua parecia curva de nível desenhada
    torce = np.column_stack(
        [ru.fbm(q * 2.6 + 71.0, 2), ru.fbm(q * 2.6 + 83.0, 2), ru.fbm(q * 2.6 + 97.0, 2)]
    )
    rach = 1 - np.abs(2 * ru.fbm(q * np.array((3.1, 3.1, 5.4)) + torce * 1.5 + 31.0, 5) - 1)
    fenda = suave(0.955, 0.995, rach) * suave(0.5, 0.62, ru.fbm(q * 1.9 + 113.0, 3))
    pedra = mistura((0.30, 0.285, 0.25), (0.53, 0.50, 0.44), suave(0.3, 0.72, g1 * 0.6 + g2 * 0.4))
    pedra = pedra * (0.82 + 0.34 * g3)[:, None]
    pedra = pedra * (1 - 0.42 * fenda)[:, None]
    liq = suave(0.63, 0.74, ru.fbm(q * 4.3 + 41.0, 4)) * (0.6 + 0.4 * g3)
    pedra = mistura(pedra, np.array((0.67, 0.67, 0.56)), liq * 0.6)
    base_m = ru.fbm(q * 1.5 + 53.0, 5)
    musgo = suave(0.53, 0.66, nq[:, 2] * 0.3 + base_m * 0.86 + 0.1 * g2 - 0.03)
    musgo = musgo * (1 - 0.7 * fenda)
    tom = suave(0.3, 0.75, ru.fbm(q * 9.5 + 61.0, 4))
    verde = mistura((0.15, 0.23, 0.07), (0.33, 0.40, 0.13), tom) * (0.78 + 0.42 * g3)[:, None]
    cor = mistura(pedra, verde, musgo)
    pe = suave(0.34, -0.02, q[:, 2])
    cor = mistura(cor, cor * np.array((0.62, 0.5, 0.4)), pe * 0.8)
    alt = (0.5 * g2 + 0.5 * g3) * (1 - 0.6 * musgo) - 0.55 * fenda + 0.34 * musgo * g3
    img_c = np.zeros((px, px, 3))
    img_c[cheio] = cor
    img_c = sangra(img_c, cheio)
    img_h = np.zeros((px, px, 3))
    img_h[cheio] = alt[:, None]
    img_h = sangra(img_h, cheio)[..., 0]
    h2 = (img_h[::2, ::2] + img_h[1::2, ::2] + img_h[::2, 1::2] + img_h[1::2, 1::2]) / 4
    k = 5.0
    dx = (np.roll(h2, -1, 1) - np.roll(h2, 1, 1)) * k
    dy = (np.roll(h2, -1, 0) - np.roll(h2, 1, 0)) * k
    nm = unit(np.dstack([-dx, dy, np.ones_like(h2)]))
    return para_u8(img_c), para_u8(nm * 0.5 + 0.5)


# ---------------------------------------------------------------- GLB
def caminho_glb(chave: str) -> Path:
    return SAIDA / chave / f"{chave}.glb"


def grava_glb(chave: str, dados: dict) -> None:
    g = glb.Glb(gerador="VT65 tools/blender/exp_plantas.py", repetir=True)
    mats: dict[str, int] = {}
    if "casca_cor" in dados:
        c = g.texture(png_bytes(dados["casca_cor"]), "image/png")
        n = g.texture(png_bytes(dados["casca_nrm"]), "image/png")
        mats["casca"] = g.material("Casca", c, n, rugosidade=0.93)
    if "rocha_cor" in dados:
        c = g.texture(png_bytes(dados["rocha_cor"]), "image/png")
        n = g.texture(png_bytes(dados["rocha_nrm"]), "image/png")
        mats["rocha"] = g.material("Rocha", c, n, rugosidade=0.94)
    if "atlas" in dados:
        c = g.texture(png_bytes(dados["atlas"]), "image/png")
        # rugosidade 1: com menos, o cartão quase de perfil pegava o céu e virava risco claro
        i = g.material("Folha", c, rugosidade=1.0)
        g.js["materials"][i].update({"alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True})
        mats["folha"] = i
    for nome, m, mat in dados["pecas"]:
        if m.tris == 0:
            continue
        p, n, uv, f = m.arrays()
        ps, ns, _ = glb.de_blender(p, n, uv)
        g.mesh(nome, ps, ns, uv.astype(np.float32), f.astype(np.uint32), mats[mat])
    destino = caminho_glb(chave)
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_bytes(g.bytes())


def medir(chave: str) -> dict:
    """Tudo lido do GLB gravado: caixa em studs, triângulos, raios por altura."""
    js, b = glb.ler(caminho_glb(chave))
    malhas = {}
    for me in js["meshes"]:
        pr = me["primitives"][0]
        v = glb.acessor(js, b, pr["attributes"]["POSITION"]).astype(np.float64)
        f = glb.acessor(js, b, pr["indices"]).astype(np.int64).reshape(-1, 3)
        malhas[me["name"]] = (v, f)
    tudo = np.vstack([v for v, _ in malhas.values()])
    lo, hi = tudo.min(axis=0), tudo.max(axis=0)
    info = {
        "chave": chave,
        "dim_studs_xyz": [round(float(x), 2) for x in hi - lo],
        "dim_m_xyz": [round(float(x) * M, 2) for x in hi - lo],
        "y_min_studs": round(float(lo[1]), 3),
        "y_max_studs": round(float(hi[1]), 3),
        "tris": {k: len(f) for k, (_, f) in malhas.items()},
        "tris_total": sum(len(f) for _, f in malhas.values()),
        "mb": round(caminho_glb(chave).stat().st_size / 2**20, 2),
    }
    if "Madeira0" in malhas:
        v, f = malhas["Madeira0"]
        cortes = {}
        for h_m in (0.05, 0.3, 0.6, 1.0, 1.3, 2.0, 3.0):
            y = h_m / M
            ya = v[f, 1] - y
            pts = []
            for a, c in ((0, 1), (1, 2), (2, 0)):
                sel = ya[:, a] * ya[:, c] < 0
                if not sel.any():
                    continue
                pa, pc = v[f[sel, a]], v[f[sel, c]]
                t = (ya[sel, a] / (ya[sel, a] - ya[sel, c]))[:, None]
                pts.append((pa + (pc - pa) * t)[:, [0, 2]])
            if pts:
                q = np.vstack(pts)
                meia = (q.max(axis=0) - q.min(axis=0)) / 2
                cortes[str(h_m)] = {
                    "raio_medio_studs": round(float(meia.mean()), 2),
                    "raio_max_studs": round(float(np.hypot(q[:, 0], q[:, 1]).max()), 2),
                }
        info["madeira_cortes_por_altura_m"] = cortes
    if "Raizes0" in malhas:
        v, _ = malhas["Raizes0"]
        pe = v[v[:, 1] < 0.6 / M]
        info["raizes_alcance_studs"] = round(float(np.hypot(pe[:, 0], pe[:, 2]).max()), 2)
    if chave in ("exp_rocha", "exp_samambaia"):
        v = np.vstack([x for x, _ in malhas.values()])
        pe = v[v[:, 1] < 0.1 / M]
        info["raio_no_chao_studs"] = round(float(np.hypot(pe[:, 0], pe[:, 2]).max()), 2)
    return info


# ---------------------------------------------------------------- prévia
def camera(cena, olho, alvo, lente: float = 50.0):
    cam = bpy.data.cameras.new("cam")
    cam.lens = lente
    ob = bpy.data.objects.new("cam", cam)
    cena.collection.objects.link(ob)
    ob.location = Vector(olho)
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = (Vector(alvo) - Vector(olho)).to_track_quat("-Z", "Y")
    return ob


def previa(chave: str, px: int = 660) -> None:
    cena = comum.cena_vazia()
    obj = comum.importar_glb(caminho_glb(chave))
    lo, hi = comum.caixa(obj)
    H = float(hi[2])
    W = float(max(hi[0] - lo[0], hi[1] - lo[1]))
    chao = comum.chao(tamanho=2000.0, z=0.0)
    mat = comum.novo_material("chao")
    pr = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    pr.inputs["Base Color"].default_value = (0.20, 0.095, 0.05, 1)
    pr.inputs["Roughness"].default_value = 1.0
    chao.data.materials.append(mat)
    mundo = bpy.data.worlds.new("ceu")
    mundo.use_nodes = True
    fundo = mundo.node_tree.nodes["Background"]
    fundo.inputs[0].default_value = (0.56, 0.72, 0.92, 1)
    fundo.inputs[1].default_value = 1.05
    cena.world = mundo
    sol = bpy.data.lights.new("sol", "SUN")
    sol.energy = 3.4
    sol.angle = math.radians(4)
    ob = bpy.data.objects.new("sol", sol)
    cena.collection.objects.link(ob)
    ob.rotation_euler = (math.radians(48), 0, math.radians(35))
    cena.render.resolution_x = px
    cena.render.resolution_y = px
    cena.render.image_settings.file_format = "PNG"
    cena.view_settings.view_transform = "Standard"
    cena.cycles.samples = 40
    cena.cycles.use_denoising = True
    cena.cycles.max_bounces = 5
    cena.cycles.transparent_max_bounces = 32
    cx, cy = float(lo[0] + hi[0]) / 2, float(lo[1] + hi[1]) / 2
    dist = max(H, W) * 1.72 + 0.8
    zm = max(H * 0.5, 0.25)
    vistas = []
    for az in (32.0, 165.0):
        r = math.radians(az)
        olho = (cx + math.cos(r) * dist, cy + math.sin(r) * dist, max(zm * 0.65, 0.6))
        vistas.append((olho, (cx, cy, zm), 50.0))
    if H > 4:
        r = math.radians(300)
        d = max(5.0, W * 0.42)
        vistas.append(((math.cos(r) * d, math.sin(r) * d, 1.65), (0, 0, min(2.6, H * 0.3)), 28.0))
    else:
        r = math.radians(290)
        d = max(1.8, W * 1.05)
        vistas.append(((math.cos(r) * d, math.sin(r) * d, H * 0.9 + 0.4), (cx, cy, H * 0.34), 40.0))
    pasta = comum.TRABALHO / "exp_plantas"
    pasta.mkdir(parents=True, exist_ok=True)
    quadros = []
    for k, (olho, alvo, lente) in enumerate(vistas):
        cam = camera(cena, olho, alvo, lente)
        cena.camera = cam
        arq = pasta / f"{chave}_{k}.png"
        cena.render.filepath = str(arq)
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(str(arq), check_existing=False)
        a = np.empty(px * px * 4, np.float32)
        im.pixels.foreach_get(a)
        quadros.append(para_u8(a.reshape(px, px, 4)[::-1, :, :3]))
        bpy.data.images.remove(im)
    (SAIDA / chave / "previa.png").write_bytes(png_bytes(np.hstack(quadros)))


# ---------------------------------------------------------------- principal
TODAS = ("exp_figueira", "exp_arvore_a", "exp_arvore_b", "exp_rocha", "exp_samambaia")


def main() -> None:
    args = comum.argumentos()
    so_previa = "--so-previa" in args
    sem_previa = "--sem-previa" in args
    chaves = [a for a in args if not a.startswith("--")]
    if not chaves or chaves == ["todas"]:
        chaves = list(TODAS)
    for chave in chaves:
        if not so_previa:
            if chave in ARVORES:
                dados = gera_arvore(chave)
            elif chave == "exp_rocha":
                dados = gera_rocha()
            elif chave == "exp_samambaia":
                dados = gera_samambaia()
            else:
                raise SystemExit(f"chave desconhecida: {chave}")
            grava_glb(chave, dados)
        comum.log("MEDIDA", json.dumps(medir(chave), ensure_ascii=False))
        if not sem_previa:
            previa(chave)
            comum.log("previa", SAIDA / chave / "previa.png")


if __name__ == "__main__":
    main()
