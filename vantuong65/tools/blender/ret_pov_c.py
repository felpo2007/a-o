"""Povoado da Vila (D-255): a parte afetada pela guerra. Metros, Z para cima, frente em -Y.

Sem emblema de cruz vermelha nem símbolo real: o posto de socorro se lê pelos objetos. A entrada
disfarçada é só cenário; os túneis jogáveis continuam nos pontos do mapa.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_arrozal as A  # noqa: E402
import exp_comum as E  # noqa: E402
import exp_vila as X  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
import ret_comboio as RC  # noqa: E402
import ret_pov_kit as K  # noqa: E402
import ret_vila as RV  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from ret_pov_kit import B, T, Vg  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402


def _furos(rec, nome, lado, pts, mats):
    """Marcas de bala: lascas escuras rente à parede, baratas."""
    for k, (u, z, r) in enumerate(pts):
        p = lado.ponto(u, -lado.dentro * (lado.esp / 2 + 0.006), z)
        o = V.bloco(
            f"{nome}{k}", (r, 0.012, r * 0.82), tuple(p), mats.cinza, rot=(0.0, 0.5 + k, lado.ang)
        )
        K._mob(rec, o)


# =============================================================== 12. casa destruída
def receita_ret_pov_destruida():
    """Casa de tijolo partida ao meio: o interior aparece da rua, com móveis e telhado caído."""
    rec = V.Receita()
    sem = 941
    mats = Mats(sem)
    L, W, esp = 9.4, 6.0, 0.24
    gach = V.mat_gach("gach_ruina", exposto=0.8)
    ngoi = K.telha("#7f4d38", "#4c3226", "#96624a")
    V.nen(rec, "nen", -L / 2 - 0.15, -W / 2 - 0.15, L / 2 + 0.15, W / 2 + 0.15, mats)
    lados = V.lados_ret(0.0, 0.0, L, W, esp)
    fr, fu, es, di = lados["frente"], lados["fundo"], lados["esq"], lados["dir"]
    for i, (a, b, h0, h1) in enumerate(
        (
            (0.0, 1.0, 3.0, 3.0),
            (2.5, 3.6, 3.0, 2.6),
            (3.6, 4.6, 2.6, 1.3),
            (6.9, 7.8, 0.9, 1.9),
            (7.8, 9.4, 1.9, 2.8),
        )
    ):
        A.trecho(rec, f"fr{i}", fr, a, b, h0, h1, gach, sem=1.0)
    A.trecho(rec, "fr_verga", fr, 1.0, 2.5, 3.0, 3.0, gach, z0=2.72, sem=1.0)
    p = fr.ponto(1.75, 0.0, PISO)
    A.registrar_porta(rec, "porta", (p.x, p.y, PISO), 1.4, 2.5, (0, -1, 0))
    p = fr.ponto(5.7, 0.0, PISO)
    A.registrar_porta(rec, "brecha", (p.x, p.y, PISO), 2.2, 2.6, (0, -1, 0))
    for i, (a, b, h0, h1, z0) in enumerate(
        (
            (0.0, 1.8, 3.0, 3.0, 0.0),
            (1.8, 2.9, 1.0, 1.0, 0.0),
            (1.8, 2.9, 3.0, 3.0, 2.1),
            (2.9, 5.2, 3.0, 2.2, 0.0),
            (5.2, 6.4, 2.2, 0.8, 0.0),
            (7.9, 9.4, 1.5, 2.6, 0.0),
        )
    ):
        A.trecho(rec, f"fu{i}", fu, a, b, h0, h1, gach, z0=z0, sem=2.0)
    p = fu.ponto(7.15, 0.0, PISO)
    A.registrar_porta(rec, "brecha_f", (p.x, p.y, PISO), 1.5, 2.6, (0, 1, 0))
    for i, (a, b, h0, h1) in enumerate(((0.0, 2.2, 3.0, 3.0), (3.5, 5.52, 3.0, 3.0))):
        A.trecho(rec, f"es{i}", es, a, b, h0, h1, gach, sem=3.0)
    A.trecho(rec, "es_v", es, 2.2, 3.5, 3.0, 3.0, gach, z0=2.72, sem=3.0)
    p = es.ponto(2.85, 0.0, PISO)
    A.registrar_porta(rec, "porta_e", (p.x, p.y, PISO), 1.3, 2.5, (-1, 0, 0))
    for i, (a, b, h0, h1) in enumerate(
        ((0.0, 1.1, 2.6, 1.5), (1.1, 2.0, 1.5, 0.7), (3.5, 4.6, 0.8, 1.7), (4.6, 5.52, 1.7, 2.5))
    ):
        A.trecho(rec, f"di{i}", di, a, b, h0, h1, gach, sem=4.0)
    p = di.ponto(2.75, 0.0, PISO)
    A.registrar_porta(rec, "brecha_d", (p.x, p.y, PISO), 1.5, 2.6, (1, 0, 0))
    _furos(
        rec,
        "furo_a",
        fr,
        ((0.4, 1.6, 0.09), (0.7, 2.2, 0.07), (2.9, 1.5, 0.1), (3.2, 1.9, 0.06), (8.4, 1.5, 0.08)),
        mats,
    )
    _furos(rec, "furo_b", es, ((0.8, 1.4, 0.08), (1.4, 2.0, 0.1), (4.4, 1.7, 0.07)), mats)
    # o telhado que resistiu, sobre a metade esquerda, com caibros à mostra na quebra
    hr = 4.75
    A1 = (-L / 2 - 0.5, -W / 2 - 0.55, 2.85)
    B1 = (-0.5, -W / 2 - 0.55, 2.85)
    C1 = (-0.5, 0.0, hr)
    D1 = (-L / 2 - 0.5, 0.0, hr)
    ob, nrm = V.placa("agua_a", A1, B1, C1, D1, 0.1, "ngoi", ngoi, sem=941)
    rec.add(ob, "Telhado", "Telhado")
    V._prisma_placa(rec, "agua_a", [A1, B1, C1, D1], nrm, 0.06, "para", "Tile")
    A2 = (-L / 2 - 0.5, W / 2 + 0.55, 2.85)
    B2 = (0.7, W / 2 + 0.55, 2.85)
    C2 = (0.1, 0.0, hr)
    D2 = (-L / 2 - 0.5, 0.0, hr)
    ob, nrm = V.placa("agua_b", A2, B2, C2, D2, 0.1, "ngoi", ngoi, sem=942)
    rec.add(ob, "Telhado", "Telhado")
    V._prisma_placa(rec, "agua_b", [A2, B2, C2, D2], nrm, 0.06, "para", "Tile")
    Vg(
        rec,
        "cumeeira",
        (-L / 2 - 0.4, 0, hr - 0.08),
        (1.5, 0, hr - 0.08),
        0.14,
        0.15,
        mats.go_escuro,
        est=False,
    )
    for k, x in enumerate((-0.2, 0.5, 1.2)):
        for s in (-1, 1):
            t = 1.0 - k * 0.22
            a = Vector((x, 0, hr - 0.1))
            b = a.lerp(Vector((x, s * (W / 2 + 0.3), 2.86)), t)
            Vg(rec, f"caibro{k}{s}", tuple(a), tuple(b), 0.07, 0.08, mats.go, est=False)
    # viga caída e telhas no chão
    a2, b2 = Vector((2.4, 2.5, 2.1)), Vector((3.4, 0.2, PISO + 0.1))
    Vg(rec, "caida", tuple(a2), tuple(b2), 0.17, 0.19, mats.go_escuro, est=False)
    rec.prisma(
        "caida",
        [
            tuple(q + Vector((dx, 0, dz)))
            for q in (a2, b2)
            for dx in (-0.1, 0.1)
            for dz in (-0.1, 0.1)
        ],
        "para",
        "Wood",
    )
    A.entulho(rec, "ent_a", 2.6, -0.9, 1.3, 1.0, 0.56, gach, PISO, 1, 8, monte=mats.dat)
    A.entulho(rec, "ent_b", 3.7, 1.7, 0.8, 0.75, 0.42, gach, PISO, 2, 6, monte=mats.dat)
    A.entulho(rec, "ent_f", 1.1, -W / 2 - 0.5, 0.95, 0.36, 0.22, gach, 0.0, 3, 4, False, mats.dat)
    A.entulho(rec, "ent_d", L / 2 + 0.45, -1.4, 0.34, 0.8, 0.2, gach, 0.0, 4, 3, False, mats.dat)
    # a vida que ficou: cama, altar, mesa e potes
    xi, yi = L / 2 - esp, W / 2 - esp
    V.ban_tho(rec, "altar", (-3.0, yi - 0.3), 0, mats, comp=1.2, prof=0.5, alt=1.0)
    V.phan(rec, "phan", (-xi + 1.1, -1.7), 0, mats)
    V.cadeiras_mesa(rec, "mesa", (-1.4, 0.7), 18, mats)
    V.potes(rec, "lu", [(-xi + 0.4, 0.7)], mats, sem=sem)
    VC.camera(rec, (2.6, -W / 2 - 2.2, 1.7), (-1.8, 1.4, 1.0))
    return rec


# =============================================================== 34. posto de guarda
def receita_ret_pov_guarda():
    """Posto de guarda: plataforma de troncos, parapeito de sacos, cobertura de palha e escada."""
    rec = V.Receita()
    sem = 942
    mats = Mats(sem)
    L, W, Zp = 3.6, 3.4, 2.3
    topo = Zp + 2.25
    tora = RC._mat_tora()
    for sx in (-1, 1):
        for sy in (-1, 1):
            a = (sx * (L / 2 + 0.16), sy * (W / 2 + 0.16), 0.0)
            b = (sx * L / 2, sy * W / 2, topo)
            T(rec, f"pe{sx}{sy}", a, b, 0.12, tora, segs=7)
            c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, topo / 2)
            rec.caixa(f"pe{sx}{sy}", c, (0.26, 0.26, topo), "para", "Wood")
    for s in (-1, 1):
        for q, (p0, p1) in enumerate(((-1, 1), (1, -1))):
            Vg(
                rec,
                f"xx{s}{q}",
                (p0 * L / 2, s * W / 2, 0.25),
                (p1 * L / 2, s * W / 2, Zp - 0.2),
                0.09,
                0.1,
                mats.go_escuro,
            )
            Vg(
                rec,
                f"xy{s}{q}",
                (s * L / 2, p0 * W / 2, 0.25),
                (s * L / 2, p1 * W / 2, Zp - 0.2),
                0.09,
                0.1,
                mats.go_escuro,
            )
    E.piso_tabuas(rec, "piso", -L / 2 - 0.1, -W / 2 - 0.1, L / 2 + 0.1, W / 2 + 0.1, Zp, mats)
    E.barrotes(rec, "barrote", -L / 2, -W / 2, L / 2, W / 2, Zp, mats)
    RV._parede_sacos(rec, "par_t", -L / 2, L / 2, W / 2 - 0.2, 3, mats, z=Zp)
    RV._parede_sacos(rec, "par_f", -L / 2, 0.2, -W / 2 + 0.2, 3, mats, z=Zp)
    for nome, x in (("par_e", -L / 2 + 0.2), ("par_d", L / 2 - 0.2)):
        marca = rec.marca()
        RV._parede_sacos(rec, nome, -W / 2 + 0.4, W / 2 - 0.4, 0.0, 3, mats, z=Zp)
        rec.transformar(marca, V.lugar((x, 0.0, 0.0), 90))
    V.telhado(
        rec,
        "tel",
        L,
        W,
        topo,
        topo + 1.0,
        0.55,
        "4aguas",
        "la",
        0.18,
        V.mat_la("la"),
        mats,
        beiral_oitao=0.55,
        sem=sem,
        estrutura=False,
    )
    E.escada(rec, "escada", (1.0, -W / 2 - 2.9, 0.05), (1.0, -W / 2 + 0.02, Zp), 1.0, mats)
    RV._parede_sacos(rec, "chao_f", -2.9, 0.2, -W / 2 - 1.3, 3, mats)
    marca = rec.marca()
    RV._parede_sacos(rec, "chao_e", -1.6, 1.4, 0.0, 3, mats)
    rec.transformar(marca, V.lugar((-L / 2 - 1.2, 0.0, 0.0), 90))
    X._banco(rec, "banco", (-0.5, 0.7), 0, mats, comp=1.3)
    X._caixote(rec, "cx", (1.0, 1.0), 12, mats, dim=(0.7, 0.5, 0.45))
    RC._barril(rec, "barril", -1.15, 1.2, mats, r=0.26, alt=0.78)
    VC.camera(rec, (-3.4, -5.0, 1.8), (0.4, 0.3, 2.2))
    return rec


# =============================================================== 36. casa fortificada
def receita_ret_pov_defensiva():
    """Casa transformada em posição: janelas com sacos, seteiras, parapeito e munição dentro."""
    rec = V.Receita()
    sem = 943
    mats = Mats(sem)
    L, W, H = 8.6, 5.6, 2.95
    jan = [
        {"lado": "frente", "t": -2.6, "w": 1.1, "z0": 1.2, "z1": 1.65, "estilo": "aberta"},
        {"lado": "frente", "t": 2.6, "w": 1.1, "z0": 1.2, "z1": 1.65, "estilo": "aberta"},
        {"lado": "esq", "t": 0.0, "w": 1.0, "z0": 1.2, "z1": 1.65, "estilo": "aberta"},
        {"lado": "dir", "t": 0.0, "w": 1.0, "z0": 1.2, "z1": 1.65, "estilo": "aberta"},
    ]
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "gach",
        [
            {"lado": "frente", "t": 0.0, "estilo": "nada"},
            {"lado": "fundo", "t": -2.4, "estilo": "tabua", "folha": 1},
        ],
        jan,
        tel="chapa",
        alto=1.8,
        beiral=0.6,
        esp=0.24,
    )
    lados = V.lados_ret(0.0, 0.0, L, W, 0.24)
    _furos(
        rec,
        "furo_a",
        lados["frente"],
        ((0.5, 1.7, 0.08), (1.0, 2.3, 0.1), (6.7, 1.9, 0.08), (7.9, 2.4, 0.09), (8.1, 1.2, 0.06)),
        mats,
    )
    # sacos por dentro das seteiras e o parapeito na frente da porta
    RV._parede_sacos(rec, "s_a", -3.4, -1.8, -yi + 0.28, 3, mats, z=PISO)
    RV._parede_sacos(rec, "s_b", 1.8, 3.4, -yi + 0.28, 3, mats, z=PISO)
    RV._parede_sacos(rec, "s_p", -2.0, 2.0, -W / 2 - 1.4, 3, mats)
    RV._parede_sacos(rec, "s_c", -L / 2 - 1.5, -2.5, -W / 2 - 0.5, 2, mats)
    RV._parede_sacos(rec, "s_d", 2.5, L / 2 + 1.5, -W / 2 - 0.5, 2, mats)
    for k, (x, y) in enumerate(((3.4, 1.8), (2.6, 1.9), (3.1, 0.9))):
        X._caixote(rec, f"mun{k}", (x, y), 8 * k, mats, dim=(0.75, 0.42, 0.34), z=PISO)
    X._caixote(rec, "mun_t", (3.0, 1.85), -6, mats, dim=(0.72, 0.4, 0.32), z=PISO + 0.34)
    V.cho_tre(rec, "catre", (-xi + 0.62, 1.1), 90, mats)
    X._banco(rec, "banco", (-1.1, 1.6), 0, mats, comp=1.6, z=PISO)
    RC._barril(rec, "barril", xi - 0.42, -0.6, mats, z=PISO)
    VC.camera(rec, (-L / 2 + 0.7, -W / 2 + 0.7, PISO + 1.55), (2.6, W / 2 - 1.0, PISO + 0.7))
    return rec


# =============================================================== 37. armazém abandonado
def receita_ret_pov_armazem_ruina():
    """Armazém baleado: chapa caída de um lado, paredes quebradas e entradas por todos os lados."""
    rec = V.Receita()
    sem = 944
    mats = Mats(sem)
    L, W, esp = 13.0, 7.4, 0.2
    par = V.mat_gach("gach_gasto", exposto=0.65)
    V.nen(rec, "nen", -L / 2 - 0.1, -W / 2 - 0.1, L / 2 + 0.1, W / 2 + 0.1, mats)
    lados = V.lados_ret(0.0, 0.0, L, W, esp)
    fr, fu, es, di = lados["frente"], lados["fundo"], lados["esq"], lados["dir"]
    for i, (a, b, h0, h1) in enumerate(
        (
            (0.0, 1.8, 3.3, 3.3),
            (4.2, 6.2, 3.3, 2.5),
            (6.2, 7.4, 2.5, 1.2),
            (9.6, 11.0, 1.1, 2.9),
            (11.0, 13.0, 2.9, 3.3),
        )
    ):
        A.trecho(rec, f"fr{i}", fr, a, b, h0, h1, par, sem=1.0)
    A.trecho(rec, "fr_v", fr, 1.8, 4.2, 3.3, 3.3, par, z0=2.85, sem=1.0)
    for nome, u, lg in (("portao", 3.0, 2.4), ("brecha", 8.5, 2.2)):
        p = fr.ponto(u, 0.0, PISO)
        A.registrar_porta(rec, nome, (p.x, p.y, PISO), lg, 2.6, (0, -1, 0))
    for i, (a, b, h0, h1) in enumerate(
        ((0.0, 3.8, 3.3, 3.3), (5.4, 8.6, 3.3, 2.7), (8.6, 10.0, 2.7, 1.0), (11.6, 13.0, 1.3, 3.0))
    ):
        A.trecho(rec, f"fu{i}", fu, a, b, h0, h1, par, sem=2.0)
    A.trecho(rec, "fu_v", fu, 3.8, 5.4, 3.3, 3.3, par, z0=2.72, sem=2.0)
    for nome, u, lg in (("porta_f", 4.6, 1.4), ("brecha_f", 10.8, 1.6)):
        p = fu.ponto(u, 0.0, PISO)
        A.registrar_porta(rec, nome, (p.x, p.y, PISO), lg, 2.5, (0, 1, 0))
    A.trecho(rec, "es0", es, 0.0, 2.6, 3.3, 3.3, par, sem=3.0)
    A.trecho(rec, "es1", es, 4.2, 7.0, 3.3, 3.3, par, sem=3.0)
    A.trecho(rec, "es_v", es, 2.6, 4.2, 3.3, 3.3, par, z0=2.72, sem=3.0)
    p = es.ponto(3.4, 0.0, PISO)
    A.registrar_porta(rec, "porta_e", (p.x, p.y, PISO), 1.4, 2.5, (-1, 0, 0))
    A.trecho(rec, "di0", di, 0.0, 1.8, 3.0, 1.6, par, sem=4.0)
    A.trecho(rec, "di1", di, 3.8, 7.0, 1.2, 3.1, par, sem=4.0)
    p = di.ponto(2.8, 0.0, PISO)
    A.registrar_porta(rec, "brecha_d", (p.x, p.y, PISO), 2.0, 2.6, (1, 0, 0))
    _furos(
        rec,
        "furo_a",
        fr,
        (
            (0.5, 1.5, 0.1),
            (1.1, 2.2, 0.08),
            (4.8, 1.8, 0.09),
            (5.4, 1.2, 0.07),
            (11.5, 1.9, 0.1),
            (12.3, 2.5, 0.08),
        ),
        mats,
    )
    _furos(rec, "furo_b", fu, ((1.0, 1.4, 0.08), (2.2, 2.3, 0.1), (6.4, 1.6, 0.09)), mats)
    # treliças e a chapa que sobrou, na metade esquerda
    hr = 5.0
    for k, x in enumerate((-6.2, -3.6, -1.0, 1.6, 4.2)):
        if k < 3:
            Vg(
                rec,
                f"linha{k}",
                (x, -W / 2, 3.25),
                (x, W / 2, 3.25),
                0.13,
                0.15,
                mats.go_escuro,
                est=False,
            )
        for s in (-1, 1):
            if k >= 3 and s < 0:
                continue
            Vg(
                rec,
                f"perna{k}{s}",
                (x, s * W / 2, 3.3),
                (x, 0.0, hr if k < 3 else hr - 0.5),
                0.11,
                0.12,
                mats.go_escuro,
                est=False,
            )
    Vg(rec, "cumeeira", (-L / 2, 0, hr), (-0.4, 0, hr), 0.13, 0.14, mats.go_escuro, est=False)
    Vg(rec, "cumeeira_b", (-0.4, 0, hr), (4.4, 0, hr - 0.5), 0.13, 0.14, mats.go_escuro, est=False)
    marca = rec.marca()
    E.telhado_chapa(
        rec, "tel", 7.0, W, 3.3, hr, 0.45, mats, sem=sem, ferrugem=0.95, beiral_oitao=0.15
    )
    rec.transformar(marca, V.lugar((-3.0, 0.0, 0.0)))
    # chapa caída e entulho
    for k, (x, y, r) in enumerate(((3.1, -1.8, 0.3), (4.4, 1.2, -0.5), (1.7, 2.3, 0.9))):
        o = V.bloco(
            f"chapa_c{k}",
            (2.2, 1.0, 0.025),
            (x, y, PISO + 0.34),
            E.mat_chapa(f"cc{k}", 0.9),
            rot=(0.35, 0.2, r),
        )
        K._mob(rec, o)
    rec.caixa("chapa_c", (3.6, -0.2, PISO + 0.2), (2.4, 1.6, 0.4), "passa", "Metal")
    A.entulho(rec, "ent_a", 3.9, -2.6, 1.2, 0.8, 0.46, par, PISO, 5, 7, monte=mats.dat)
    A.entulho(rec, "ent_b", 5.3, 2.5, 0.9, 0.75, 0.4, par, PISO, 6, 5, monte=mats.dat)
    # o que restou guardado
    for k, (x, y, r) in enumerate(
        ((-5.2, 2.6, 8), (-4.2, 2.8, -6), (-5.3, 1.7, 20), (-1.2, -2.8, 40))
    ):
        X._caixote(rec, f"cx{k}", (x, y), r, mats, z=PISO)
    K.fardos(rec, "sacos", -2.6, 2.9, mats, colunas=4, linhas=2)
    RC._barril(rec, "barril_a", -5.6, -2.8, mats, z=PISO)
    RC._barril(rec, "barril_b", -4.8, -3.0, mats, z=PISO)
    VC.camera(rec, (-5.6, -2.6, 1.7), (3.8, 1.6, 1.1))
    return rec


# =============================================================== 38. posto de socorro
def receita_ret_pov_socorro():
    """Posto de socorro improvisado: lona em varas, macas, caixas, baldes e bandagens no varal."""
    rec = V.Receita()
    sem = 945
    mats = Mats(sem)
    L, W, H = 7.2, 4.8, 2.5
    lona = N.mat_pano("lona", cor="#6b6a4c", desbotado="#8c8a68")
    V.nen(rec, "nen", -L / 2, -W / 2, L / 2, W / 2, mats, h=0.05)
    for k in range(4):
        x = -L / 2 + k * L / 3
        for s in (-1, 1):
            T(
                rec,
                f"v{k}{s}",
                (x, s * W / 2, 0),
                (x, s * W / 2, H - 0.45),
                0.055,
                mats.tre,
                est=True,
            )
            rec.caixa(
                f"v{k}{s}",
                (x, s * W / 2, (H - 0.45) / 2),
                (0.12, 0.12, H - 0.45),
                "passa",
                "Bamboo",
            )
        T(rec, f"m{k}", (x, 0.0, 0.0), (x, 0.0, H + 0.42), 0.06, mats.tre, est=True)
        rec.caixa(f"m{k}", (x, 0.0, (H + 0.42) / 2), (0.13, 0.13, H + 0.42), "passa", "Bamboo")
    T(
        rec,
        "cume",
        (-L / 2 - 0.1, 0, H + 0.42),
        (L / 2 + 0.1, 0, H + 0.42),
        0.05,
        mats.tre,
        est=True,
    )
    for s in (-1, 1):
        T(
            rec,
            f"lat{s}",
            (-L / 2 - 0.1, s * W / 2, H - 0.45),
            (L / 2 + 0.1, s * W / 2, H - 0.45),
            0.04,
            mats.tre,
            est=True,
        )

        def f(u, v, sy=s):
            x = -L / 2 - 0.3 + u * (L + 0.6)
            y = sy * (v * (W / 2 + 0.3))
            z = H + 0.46 - v * 1.02 - 0.05 * math.sin(math.pi * v) - 0.03 * abs(math.sin(u * 13))
            return (x, y, z)

        o = V.grade(f"lona{s}", f, 10, 4, fora=(0, 0, 1))
        M.solidificar(o, 0.012, 0.0)
        V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z), s + 2.0)
        M.material(o, lona)
        K._mob(rec, M.suave(o, 60))
    rec.caixa("lona", (0, 0, H + 0.02), (L + 0.6, W + 0.6, 0.1), "passa", "Fabric")
    verde = N.mat_pano("maca", cor="#50553a", desbotado="#6e7350")
    for k, (x, y, r) in enumerate(
        ((-2.4, 1.1, 90), (-0.6, 1.2, 86), (1.3, 1.1, 93), (-2.2, -1.2, 92))
    ):
        q = [V.bloco(f"mc{k}_l", (0.62, 1.95, 0.025), (0, 0, 0.3), verde)]
        for s in (-1, 1):
            q.append(
                V.tre(
                    f"mc{k}_v{s}",
                    (s * 0.3, -1.12, 0.3),
                    (s * 0.3, 1.12, 0.3),
                    0.022,
                    mats.go,
                    segs=5,
                )
            )
            for t in (-0.8, 0.8):
                q.append(
                    V.bloco(f"mc{k}_p{s}{t}", (0.03, 0.03, 0.3), (s * 0.3, t, 0.15), mats.ferro)
                )
        X._colocar(
            rec,
            q,
            f"maca{k}",
            (x, y),
            r - 90,
            0.05,
            (0, 0, 0.17),
            (0.68, 2.2, 0.34),
            "passa",
            "Fabric",
        )
    for k, (x, y, r) in enumerate(((2.9, -1.6, 12), (2.9, -0.8, -8), (2.9, 1.2, 4))):
        X._caixote(rec, f"cx{k}", (x, y), r, mats, dim=(0.72, 0.5, 0.42), z=0.05)
    X._caixote(rec, "cx_t", (2.9, -1.2), 20, mats, dim=(0.6, 0.45, 0.3), z=0.47)
    balde = V.torno_local(
        "balde",
        [(0, 0), (0.13, 0), (0.17, 0.26), (0.15, 0.26), (0.11, 0.03), (0, 0.03)],
        8,
        mats.ferro,
    )
    M.mover(balde, Matrix.Translation((0.7, -1.6, 0.05)))
    K._mob(rec, balde)
    rec.caixa("balde", (0.7, -1.6, 0.18), (0.34, 0.34, 0.3), "passa", "Metal")
    faixa = N.mat_pano("gaze", cor="#d2ccba", desbotado="#b2ab98")
    T(
        rec,
        "varal",
        (-1.1, -W / 2 + 0.08, 1.8),
        (1.4, -W / 2 + 0.08, 1.8),
        0.008,
        mats.corda,
        segs=3,
    )
    for k in range(5):
        x = -0.9 + k * 0.5

        def g(u, v, x0=x, n0=k):
            return (
                x0 - 0.06 + u * 0.12,
                -W / 2 + 0.08 + 0.01 * math.sin(v * 7 + n0),
                1.79 - v * (0.48 + (n0 % 2) * 0.16),
            )

        o = V.grade(f"gaze{k}", g, 1, 2, fora=(0, -1, 0))
        M.solidificar(o, 0.005, 0.0)
        V.gravar_uv_local(o, lambda p: (p.x, p.z, p.y), k * 0.5)
        M.material(o, faixa)
        K._mob(rec, M.suave(o, 60))
    VC.camera(rec, (-3.2, -2.8, 1.5), (1.0, 0.9, 0.5))
    return rec


# =============================================================== 39. barricada
def receita_ret_pov_barricada():
    """Barricada: toras, sacos, carroça virada e guarita de tábuas, com passagem de um lado."""
    rec = V.Receita()
    sem = 946
    mats = Mats(sem)
    tora = RC._mat_tora()
    RC._toras(rec, "toras_a", -3.9, 0.0, 3.6, 3, 0.2, tora, ang=0.06, sem=1.0)
    RC._toras(rec, "toras_b", 0.0, -0.35, 2.6, 2, 0.19, tora, ang=-0.14, sem=2.0)
    RV._parede_sacos(rec, "sacos_a", -2.0, 1.6, 0.28, 3, mats)
    RV._parede_sacos(rec, "sacos_b", 1.5, 3.3, -0.1, 2, mats)
    # carroça virada, com uma roda no ar
    marca = rec.marca()
    X._carroca(rec, "carroca", (0.0, 0.0), 0, mats)
    giro = (
        Matrix.Translation((3.2, 1.4, 0.56))
        @ Matrix.Rotation(1.25, 4, "X")
        @ Matrix.Rotation(0.5, 4, "Z")
        @ Matrix.Translation((0, 0, -0.55))
    )
    i_o = marca[0]
    for o in rec.objs[i_o:]:
        M.mover(o, giro)
    rec.colisao = rec.colisao[: marca[1]]
    rec.caixa("carroca", (3.2, 1.4, 0.8), (2.6, 1.3, 1.6), "para", "Wood", rot_z=0.5)
    # guarita de tábuas na ponta
    x0, y0 = -6.4, 1.1
    van = K.parede("van")
    for sx in (-1, 1):
        for sy in (-1, 1):
            V.poste(rec, f"g{sx}{sy}", x0 + sx * 0.95, y0 + sy * 0.95, 2.6, mats.go_escuro, r=0.08)
    for s in (-1, 1):
        B(rec, f"g_par_x{s}", (0.05, 1.9, 1.2), (x0 + s * 0.95, y0, 0.72), van, est=True)
        rec.caixa(f"g_par_x{s}", (x0 + s * 0.95, y0, 0.72), (0.07, 1.9, 1.3), "para", "Wood")
    B(rec, "g_par_t", (1.9, 0.05, 1.2), (x0, y0 + 0.95, 0.72), van, est=True)
    rec.caixa("g_par_t", (x0, y0 + 0.95, 0.72), (1.9, 0.07, 1.3), "para", "Wood")
    E.telhado_varanda(
        rec, "g_tel", x0 - 1.25, x0 + 1.25, y0 + 1.25, 2.85, y0 - 1.35, 2.45, mats, sem=sem
    )
    rec.caixa("g_tel", (x0, y0, 2.62), (2.5, 2.6, 0.1), "para", "Metal")
    X._caixote(rec, "cx", (x0 + 0.1, y0 + 0.45), 12, mats, dim=(0.7, 0.5, 0.42))
    RC._barril(rec, "barril", 5.3, 0.1, mats, r=0.28, alt=0.84)
    VC.camera(rec, (-4.5, -4.8, 1.7), (0.5, 0.6, 0.8))
    return rec


# =============================================================== 40. esconderijo
def receita_ret_pov_esconderijo():
    """Entrada disfarçada: monte de palha aberto, tampa de tábuas e boca escura (só cenário)."""
    rec = V.Receita()
    sem = 947
    mats = Mats(sem)
    tranh = V.mat_tranh("tranh")
    feno = M.superelipsoide("monte", 1.9, 1.5, 1.45, 0.9, 0.85, 14, 8)
    M.deslocar(feno, lambda co, n, q=sem: 0.11 * M.fbm(co * 2.8, 3, q))
    V.apagar_faces(feno, lambda c, n: c.z < -0.02 or (c.x > 0.4 and c.y < -0.4 and c.z < 0.72))
    V.gravar_uv_local(feno, lambda p: (p.x, p.y, p.z))
    M.material(feno, tranh)
    K._mob(rec, M.suave(feno, 60))
    rec.caixa("monte", (-0.25, 0.25, 0.65), (2.7, 2.3, 1.3), "passa", "Fabric")
    T(rec, "vara", (0, 0, 0), (0.05, 0.03, 2.1), 0.05, mats.go_escuro, segs=5)
    # a boca escura, com moldura de troncos, e a tampa encostada
    breu = V.mat_liso("breu", "#070605", "#000000", rug=1.0, escala=2.0, forca=0.05)
    B(rec, "boca", (1.0, 1.0, 0.02), (1.3, -1.2, 0.02), breu)
    for s in (-1, 1):
        T(
            rec,
            f"mold_x{s}",
            (0.76, -1.2 + s * 0.56, 0.08),
            (1.84, -1.2 + s * 0.56, 0.08),
            0.075,
            RC._mat_tora(),
        )
        T(
            rec,
            f"mold_y{s}",
            (1.3 + s * 0.56, -1.74, 0.08),
            (1.3 + s * 0.56, -0.66, 0.08),
            0.075,
            RC._mat_tora(),
        )
    for k in range(5):
        B(
            rec,
            f"tampa{k}",
            (0.21, 1.15, 0.05),
            (2.1 + k * 0.22, -1.25, 0.58 + k * 0.1),
            mats.go,
            rot=(0.0, -0.42, 0.0),
        )
    rec.caixa("tampa", (2.55, -1.25, 0.72), (1.1, 1.15, 0.9), "passa", "Wood")
    for k in range(3):
        T(
            rec,
            f"escada{k}",
            (1.0, -1.45 + k * 0.25, 0.03),
            (1.6, -1.45 + k * 0.25, 0.03),
            0.018,
            mats.go_escuro,
            segs=4,
        )
    # palha e cesto espalhados para esconder
    for k, (x, y, a) in enumerate(((2.6, 0.4, 0.5), (-2.0, -1.4, 0.42), (0.3, -2.2, 0.36))):
        q = M.superelipsoide(f"tufo{k}", a, a * 0.8, a * 0.42, 0.9, 0.9, 7, 4)
        V.apagar_faces(q, lambda c, n: c.z < -0.02)
        V.gravar_uv_local(q, lambda p: (p.x, p.y, p.z), float(k))
        M.mover(q, Matrix.Translation((x, y, 0.0)))
        M.material(q, tranh)
        K._mob(rec, M.suave(q, 60))
    X._cesto(rec, "cesto", (-1.6, 1.8), mats, r=0.34, alt=0.44)
    VC.camera(rec, (3.4, -3.6, 1.5), (1.0, -1.0, 0.3))
    return rec


CASAS: dict[str, dict] = {
    "ret_pov_destruida": {
        "nome": "casa destruída com interior exposto",
        "tipo": "tijolo partido, meio telhado, entulho, móveis à vista e brechas passáveis",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_guarda": {
        "nome": "posto de guarda improvisado",
        "tipo": "bambu, chapa, sacos de areia e banco",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_defensiva": {
        "nome": "casa transformada em posição",
        "tipo": "tijolo com seteiras, sacos por dentro e parapeito, munição",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_armazem_ruina": {
        "nome": "armazém abandonado",
        "tipo": "paredes baleadas, chapa caída, entulho e seis entradas",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_socorro": {
        "nome": "posto de socorro",
        "tipo": "lona em varas, macas, caixas e gaze no varal parado",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_barricada": {
        "nome": "barricada com guarita",
        "tipo": "toras, sacos, carroça virada e guarita de tábuas",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_esconderijo": {
        "nome": "entrada disfarçada",
        "tipo": "monte de palha, tampa de tábuas e boca escura, só cenário",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
}
