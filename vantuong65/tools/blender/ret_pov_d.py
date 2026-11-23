"""Povoado da Vila (D-255): objetos de cena, leves e repetíveis. Metros, Z para cima, frente em -Y.

Eles preenchem quintais e ruas sem pesar: cada um é um MeshId só, usado várias vezes.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_vila as X  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
import ret_comboio as RC  # noqa: E402
import ret_pov_kit as K  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from ret_pov_kit import B, T  # noqa: E402
from vila_comum import Mats  # noqa: E402

ATLAS = {
    "Mobilia": {"tex": 512, "teto": 1500, "amostras_ao": 4},
    "Casa": {"tex": 256, "teto": 700, "amostras_ao": 4},
    "Telhado": {"tex": 256, "teto": 500, "amostras_ao": 4},
}


def receita_ret_pov_d_cestos():
    """Pilha de cestos, peneira e uma vara de carga encostada."""
    rec = V.Receita()
    mats = Mats(951)
    for k, (x, y, r, a, n) in enumerate(
        ((-0.45, 0.1, 0.36, 0.42, 3), (0.42, -0.1, 0.32, 0.38, 2), (0.05, 0.62, 0.26, 0.34, 2))
    ):
        for j in range(n):
            X._cesto(rec, f"c{k}{j}", (x, y), mats, r=r - j * 0.012, alt=a, z=j * 0.16)
    ne = V.torno_local(
        "nia", [(0, 0), (0.42, 0.02), (0.46, 0.07), (0.41, 0.05), (0, 0.03)], 12, mats.esteira
    )
    M.mover(ne, Matrix.Translation((0.3, -0.62, 0.34)) @ Matrix.Rotation(1.15, 4, "X"))
    K._mob(rec, ne)
    T(rec, "vara", (-0.95, -0.5, 0.0), (-0.72, 0.42, 1.55), 0.025, mats.tre)
    VC.camera(rec, (-1.6, -2.2, 1.2), (0.0, 0.1, 0.35))
    return rec


def receita_ret_pov_d_potes():
    """Potes de barro de vários tamanhos sobre uma laje."""
    rec = V.Receita()
    mats = Mats(952)
    B(rec, "laje", (1.9, 1.3, 0.07), (0, 0, 0.035), mats.pedra, chanfro=0.015)
    for k, (x, y, a, r, t) in enumerate(
        (
            (-0.5, 0.2, 0.78, 0.34, "madeira"),
            (0.25, 0.22, 0.62, 0.28, "palha"),
            (0.72, -0.12, 0.46, 0.2, None),
            (-0.1, -0.32, 0.4, 0.18, None),
        )
    ):
        X._pote(rec, f"p{k}", (x, y), mats, alt=a, r=r, z=0.07, tampa=t, sem=k + 2)
    VC.camera(rec, (-1.5, -2.0, 1.1), (0.0, 0.0, 0.35))
    return rec


def receita_ret_pov_d_lenha():
    """Lenha empilhada sob uma meia-água de palha, encostável num fundo de casa."""
    rec = V.Receita()
    mats = Mats(953)
    L, W = 2.9, 1.0
    for s in (-1, 1):
        for y, h in ((-W / 2, 1.42), (W / 2, 1.82)):
            T(rec, f"p{s}{y}", (s * L / 2, y, 0), (s * L / 2, y, h), 0.045, mats.tre, est=True)
    V.agua_unica(
        rec,
        "tel",
        -L / 2 - 0.2,
        L / 2 + 0.2,
        W / 2 + 0.1,
        1.88,
        -W / 2 - 0.34,
        1.4,
        0.16,
        "tranh",
        V.mat_tranh("tranh"),
        mats,
        sem=953,
    )
    X._lenha(rec, "l_a", -L / 2 + 0.1, L / 2 - 0.1, 0.18, mats, filas=5)
    X._lenha(rec, "l_b", -L / 2 + 0.25, 0.3, -0.25, mats, filas=2)
    VC.camera(rec, (-1.8, -2.6, 1.3), (0.1, 0.0, 0.7))
    return rec


def receita_ret_pov_d_varal():
    """Varal parado entre duas varas, com roupa de cores gastas."""
    rec = V.Receita()
    mats = Mats(954)
    L = 4.4
    tons = (
        ("#7d3c34", "#a56a5c"),
        ("#c7c0ad", "#a59e8c"),
        ("#3f5f6f", "#6b8894"),
        ("#2d2c33", "#55525a"),
    )
    panos = [N.mat_pano(f"rp{k}", cor=a, desbotado=b) for k, (a, b) in enumerate(tons)]
    for s in (-1, 1):
        T(rec, f"p{s}", (s * L / 2, 0, 0), (s * L / 2, 0, 2.15), 0.04, mats.tre, est=True)
        rec.caixa(f"p{s}", (s * L / 2, 0, 1.07), (0.09, 0.09, 2.15), "passa", "Bamboo")
    T(rec, "fio", (-L / 2, 0, 2.05), (L / 2, 0, 2.03), 0.009, mats.corda, segs=3)
    for k in range(5):
        x = -1.7 + k * 0.86

        def f(u, v, x0=x, n0=k):
            return (
                x0 - 0.34 + u * 0.68,
                0.015 * math.sin(u * 8 + n0),
                2.03 - v * (0.82 + (n0 % 3) * 0.16),
            )

        o = V.grade(f"roupa{k}", f, 3, 2, fora=(0, -1, 0))
        M.solidificar(o, 0.008, 0.0)
        V.gravar_uv_local(o, lambda p: (p.x, p.z, p.y), k * 0.8)
        M.material(o, panos[k % 4])
        K._mob(rec, M.suave(o, 60))
    VC.camera(rec, (-2.4, -3.2, 1.5), (0.0, 0.0, 1.4))
    return rec


def receita_ret_pov_d_horta():
    """Horta de canteiros elevados, com varas de feijão e cerquinha baixa."""
    rec = V.Receita()
    mats = Mats(955)
    terra = mats.dat
    verde = V.mat_liso("folha_horta", "#4f6a30", "#2f4522", rug=0.75, escala=18.0, forca=0.65)
    claro = V.mat_liso("folha_clara", "#6f8a3a", "#435c28", rug=0.75, escala=18.0, forca=0.55)
    for f, y in enumerate((-1.05, 0.0, 1.05)):
        o = M.superelipsoide(f"can{f}", 2.15, 0.42, 0.16, 0.45, 0.8, 10, 4)
        V.apagar_faces(o, lambda c, n: c.z < -0.01)
        V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z), float(f))
        M.mover(o, Matrix.Translation((0, y, 0)))
        M.material(o, terra)
        K._mob(rec, M.suave(o, 50))
        for k in range(11):
            x = -1.85 + k * 0.37 + ((k * 7 + f) % 3 - 1) * 0.03
            r = 0.12 + ((k * 3 + f) % 3) * 0.035
            p = M.superelipsoide(f"pl{f}{k}", r, r, r * 0.8, 0.9, 0.9, 5, 3)
            M.deslocar(p, lambda co, n, q=k + f: 0.03 * M.fbm(co * 11.0, 2, q))
            V.gravar_uv_local(p, lambda c: (c.x, c.y, c.z), float(k))
            M.mover(p, Matrix.Translation((x, y + ((k * 5) % 3 - 1) * 0.08, 0.2 + r * 0.4)))
            M.material(p, verde if (k + f) % 3 else claro)
            K._mob(rec, M.suave(p, 60))
    for k in range(6):
        x = -2.0 + k * 0.8
        for s in (-1, 1):
            T(
                rec,
                f"var{k}{s}",
                (x, 1.05 + s * 0.26, 0.05),
                (x, 1.05, 1.55),
                0.012,
                mats.tre,
                segs=3,
            )
    T(rec, "var_t", (-2.1, 1.05, 1.5), (2.1, 1.05, 1.5), 0.016, mats.tre, segs=3)
    VC.camera(rec, (-2.8, -3.4, 1.7), (0.0, 0.1, 0.25))
    return rec


def receita_ret_pov_d_feno():
    """Meda de palha de arroz em volta de um mastro."""
    rec = V.Receita()
    mats = Mats(956)
    tranh = V.mat_tranh("tranh")
    o = V.torno_local(
        "meda",
        [
            (0, 0),
            (0.92, 0),
            (1.12, 0.45),
            (1.08, 1.05),
            (0.82, 1.65),
            (0.42, 2.15),
            (0.1, 2.48),
            (0, 2.5),
        ],
        12,
        tranh,
    )
    M.deslocar(o, lambda co, n: 0.06 * M.fbm(co * 3.4, 3, 5))
    V.gravar_uv_local(o, lambda p: (math.atan2(p.y, p.x) * 1.1, p.z, 0.0))
    K._mob(rec, M.suave(o, 60))
    T(rec, "mastro", (0, 0, 2.3), (0.03, 0.02, 3.05), 0.04, mats.go_escuro)
    rec.caixa("meda", (0, 0, 1.05), (1.7, 1.7, 2.1), "para", "Fabric")
    VC.camera(rec, (-2.4, -3.2, 1.6), (0.0, 0.0, 1.1))
    return rec


def receita_ret_pov_d_esteira():
    """Esteira de secar arroz no chão, com rodo de madeira e cesto."""
    rec = V.Receita()
    mats = Mats(957)
    B(rec, "esteira", (3.6, 2.4, 0.025), (0, 0, 0.0125), mats.esteira)
    o = M.superelipsoide("grao", 1.55, 0.98, 0.05, 0.35, 0.7, 12, 3)
    M.deslocar(o, lambda co, n: 0.012 * M.fbm(co * 5.0, 2, 8))
    V.apagar_faces(o, lambda c, n: c.z < -0.002)
    V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
    M.mover(o, Matrix.Translation((0, 0, 0.025)))
    M.material(o, mats.arroz)
    K._mob(rec, M.suave(o, 50))
    B(rec, "rodo", (0.62, 0.06, 0.1), (1.1, -0.62, 0.11), mats.go, rot=(0, 0, 0.5))
    T(rec, "cabo", (1.1, -0.62, 0.15), (2.05, -1.6, 0.8), 0.02, mats.go)
    X._cesto(rec, "cesto", (-2.1, 0.8), mats, r=0.32, alt=0.42)
    VC.camera(rec, (-2.8, -3.0, 1.7), (0.1, 0.0, 0.1))
    return rec


def receita_ret_pov_d_muro():
    """Trecho de 4 m de muro de laterita, gasto no topo, para fechar quintais."""
    rec = V.Receita()
    lat = K.parede("laterita")
    lado = V.Lado((-2.0, 0.0), 0.0, 4.0, 0.34, 1.0)
    V.parede(rec, "m", lado, 0.0, 1.12, lat, (), "Brick", "para")
    for k, (x, lg, h) in enumerate(
        ((-1.5, 0.92, 0.09), (-0.55, 0.78, 0.13), (0.42, 0.98, 0.08), (1.45, 1.06, 0.12))
    ):
        B(rec, f"cap{k}", (lg, 0.4, h), (x, 0.0, 1.12 + h / 2), lat, est=True, chanfro=0.015)
    VC.camera(rec, (-2.2, -3.2, 1.4), (0.2, 0.0, 0.6))
    return rec


def _item(nome, tipo):
    return {"nome": nome, "tipo": tipo, "fontes": [], "atlas": ATLAS}


CASAS: dict[str, dict] = {
    "ret_pov_d_cestos": _item("cestos", "pilha de cestos, peneira e vara"),
    "ret_pov_d_potes": _item("potes", "potes de barro sobre laje"),
    "ret_pov_d_lenha": _item("lenha", "lenha sob meia-água de palha"),
    "ret_pov_d_varal": _item("varal", "roupa parada em varas de bambu"),
    "ret_pov_d_horta": _item("horta", "canteiros e varas de feijão"),
    "ret_pov_d_feno": _item("meda de palha", "palha de arroz em volta do mastro"),
    "ret_pov_d_esteira": _item("esteira de arroz", "grãos secando, rodo e cesto"),
    "ret_pov_d_muro": _item("muro de laterita", "trecho de 4 m com topo gasto"),
}

_ = RC
