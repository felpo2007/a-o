"""Gera os dados dos dois mapas retangulares (D-243) no formato de `VT65Build/Data`.

Saída, para cada mapa: `src/ServerStorage/VT65Build/Data_<id>/` (Grid, Heights_NN, Features,
Roads e Layout) e a planta `assets/mapas/<id>_planta.png`. Planta em metros (X leste, Y norte).
Mundo em studs: X = (x - comp / 2) / 0,28 e Z = -(y - prof / 2) / 0,28: o centro fica na origem.

Uso:
    lune run tools/trajeto_amostra.luau
    uv run --group arte python tools/mapas_ret.py [frente] [comboio]
"""

from __future__ import annotations

import base64
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

RAIZ = Path(__file__).resolve().parents[1]
BUILD = RAIZ / "src" / "ServerStorage" / "VT65Build"
SAIDA_PLANTA = RAIZ / "assets" / "mapas"
BUDGET = RAIZ / "src" / "ServerScriptService" / "Modules" / "ArtBudget.luau"

M = 0.28
CELL = 16  # studs
MARGEM = 150.0  # metros de cenário em volta da área jogável
HOFF = 1000  # cm somados à altura gravada
NIVEL = 16.0  # altura do chão, em metros
ROWS_PER = 60
MASK_M = 0.5  # resolução da máscara de ocupação
LEITO = 2.4  # fundo do rio abaixo da margem
CAPTURA_R = 16.0  # raio do pátio de captura mantido livre
CONJ_LIVRE_M = 4.5  # chão livre em volta de um conjunto de nascer
CONJ_SAIDA_M = 22.0  # comprimento conferido de cada saída
CONJ_SEPARA_GRAUS = 75  # as duas saídas não olham para o mesmo lado
CONJ_ENTRE_M = 24.0  # distância mínima entre dois conjuntos
CONJ_PASSO_M = 62.0  # um par de conjuntos a cada tanto de estrada (comboio, 60-90 m)
HEAD = "--!strict\n-- GERADO por tools/mapas_ret.py. Não editar.\n"
NOMES_CLASSE = ("mar", "areia", "arrozal", "vila", "capim", "riacho")


def dims_modelos() -> dict[str, tuple[float, float, float]]:
    txt = BUDGET.read_text("utf-8")
    bloco = txt[txt.index("ArtBudget.DIMS = {") :]
    bloco = bloco[: bloco.index("\n}")]
    pad = re.compile(r"(\w+) = \{ ([\d.]+), ([\d.]+), ([\d.]+) \}")
    return {m[1]: (float(m[2]), float(m[3]), float(m[4])) for m in pad.finditer(bloco)}


DIMS = dims_modelos()


# ===================================================================== curvas
def catmull(pts: list[tuple[float, float]], passo: float) -> np.ndarray:
    """Catmull-Rom centrípeta pelos pontos, reamostrada a cada `passo` metros."""
    p = [np.array(a, float) for a in pts]
    cheia = [2 * p[0] - p[1], *p, 2 * p[-1] - p[-2]]
    saida: list[np.ndarray] = []
    for i in range(1, len(cheia) - 2):
        p0, p1, p2, p3 = cheia[i - 1], cheia[i], cheia[i + 1], cheia[i + 2]
        t0 = 0.0
        t1 = t0 + max(np.linalg.norm(p1 - p0), 1e-3) ** 0.5
        t2 = t1 + max(np.linalg.norm(p2 - p1), 1e-3) ** 0.5
        t3 = t2 + max(np.linalg.norm(p3 - p2), 1e-3) ** 0.5
        n = max(4, int(np.linalg.norm(p2 - p1) / 0.5))
        for k in range(n):
            t = t1 + (t2 - t1) * k / n
            a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            saida.append((t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2)
    saida.append(p[-1])
    return reamostra(np.array(saida), passo)


def reamostra(c: np.ndarray, passo: float) -> np.ndarray:
    d = np.hypot(*np.diff(c, axis=0).T)
    s = np.concatenate(([0.0], np.cumsum(d)))
    n = max(2, int(round(s[-1] / passo)) + 1)
    alvo = np.linspace(0, s[-1], n)
    return np.column_stack((np.interp(alvo, s, c[:, 0]), np.interp(alvo, s, c[:, 1])))


def dist_polilinha(x: np.ndarray, y: np.ndarray, c: np.ndarray) -> np.ndarray:
    """Distância de cada ponto (x, y) à polilinha `c`."""
    melhor = np.full(x.shape, np.inf)
    ax, ay = c[:-1, 0], c[:-1, 1]
    bx, by = c[1:, 0], c[1:, 1]
    for i in range(len(ax)):
        ux, uy = bx[i] - ax[i], by[i] - ay[i]
        l2 = max(ux * ux + uy * uy, 1e-9)
        t = np.clip(((x - ax[i]) * ux + (y - ay[i]) * uy) / l2, 0, 1)
        melhor = np.minimum(melhor, np.hypot(x - ax[i] - t * ux, y - ay[i] - t * uy))
    return melhor


def liso(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


# ===================================================================== projeto de cada mapa
@dataclass
class Via:
    tipo: str  # principal | secundaria | rua | trilha
    pts: list[tuple[float, float]]
    amostrada: np.ndarray | None = None


@dataclass
class Bairro:
    id: str
    nome: str
    x: float
    y: float
    raio: float
    casas: int
    marcos: list[tuple] = field(default_factory=list)  # chave, dx, dy, rumo (graus), escala
    tipos: tuple[str, ...] = ()
    arvores: list[tuple] = field(default_factory=list)  # chave, dx, dy, escala
    praca: tuple[float, float, float] | None = None  # dx, dy, raio: terra batida, sem planta
    miolo: list[tuple] = field(default_factory=list)  # marcos dentro do pátio de captura


@dataclass
class Projeto:
    id: str
    comp: float
    prof: float
    setores: list[tuple[str, float, float]]
    bases: list[tuple[str, float, float]]
    rio: list[tuple[float, float]]
    rio_largura: float
    pontes_previstas: list[tuple[float, float]]
    morros: list[tuple[float, float, float, float]]
    vias: list[Via]
    bairros: list[Bairro]
    campos: list[tuple[float, float, float, float]]
    lombada: tuple[float, float, float, float, float] | None = None


RES = tuple(f"vila_casa_{i:02d}" for i in range(1, 11))
PAL = ("exp_palafita_a", "exp_palafita_b")
SOB = ("exp_sobrado_a", "exp_sobrado_b", "exp_sobrado_c", "exp_sobrado_d")
APOIO = ("exp_celeiro", "exp_deposito", "exp_telheiro", "exp_casa_verde")
ESCALA = {
    **dict.fromkeys(RES, 1.3),
    **dict.fromkeys(PAL, 1.2),
    **dict.fromkeys(SOB, 1.1),
    **dict.fromkeys(APOIO, 1.15),
    "exp_galpao": 1.25,
    "exp_casas_ligadas": 1.15,
    "exp_casa_vala": 1.15,
}


def frente() -> Projeto:
    principal = [
        (-120, 142), (-30, 140), (35, 136), (85, 128), (135, 122), (190, 130), (245, 146),
        (290, 140), (318, 128), (345, 122), (395, 126), (440, 138), (490, 138), (530, 126),
        (565, 120), (610, 130), (665, 142), (730, 144), (820, 146),
    ]  # fmt: skip
    norte = [
        (60, 190), (135, 207), (190, 226), (245, 232), (300, 238), (337, 232), (372, 236),
        (430, 238), (510, 222), (565, 205), (625, 190),
    ]  # fmt: skip
    sul = [
        (70, 95), (135, 85), (200, 70), (255, 62), (303, 62), (330, 62), (380, 70), (432, 68),
        (500, 70), (565, 86), (630, 100),
    ]  # fmt: skip
    vias = [
        Via("principal", principal),
        Via("trilha", norte),
        Via("trilha", sul),
        # ligações entre as três famílias de rotas, a cada 80-110 m
        Via("secundaria", [(88, 128), (98, 160), (112, 200)]),
        Via("secundaria", [(190, 130), (205, 180), (196, 226)]),
        Via("secundaria", [(268, 146), (282, 190), (272, 234)]),
        Via("secundaria", [(392, 126), (398, 182), (402, 237)]),
        Via("secundaria", [(495, 138), (510, 180), (508, 222)]),
        Via("secundaria", [(604, 130), (610, 165), (612, 192)]),
        Via("secundaria", [(100, 126), (108, 104), (112, 90)]),
        Via("secundaria", [(214, 134), (220, 100), (212, 68)]),
        Via("secundaria", [(375, 124), (372, 96), (378, 70)]),
        Via("secundaria", [(500, 136), (500, 100), (496, 70)]),
        Via("secundaria", [(590, 124), (596, 108), (600, 96)]),
        # ruas de acesso aos pátios dos objetivos
        Via("rua", [(135, 122), (133, 136)]),
        Via("rua", [(245, 146), (245, 172)]),
        Via("rua", [(350, 123), (352, 134)]),
        Via("rua", [(455, 137), (455, 124)]),
        Via("rua", [(565, 120), (566, 134)]),
        # ruas internas: a frente das casas acompanha estas linhas, sem fileira reta
        Via("rua", [(98, 158), (116, 176), (150, 182), (178, 168)]),
        Via("rua", [(150, 124), (168, 104), (150, 92)]),
        Via("rua", [(208, 176), (216, 208), (252, 222), (282, 204)]),
        Via("rua", [(232, 146), (226, 122), (250, 104), (276, 118), (276, 140)]),
        Via("rua", [(336, 176), (360, 188), (396, 180)]),
        Via("rua", [(362, 124), (384, 142), (396, 166)]),
        Via("rua", [(344, 118), (352, 98), (372, 96)]),
        Via("rua", [(420, 134), (416, 106), (432, 84), (470, 78), (498, 100)]),
        Via("rua", [(470, 138), (486, 158), (476, 176), (446, 172), (432, 140)]),
        Via("rua", [(526, 166), (548, 186), (586, 188), (610, 166)]),
        Via("rua", [(532, 122), (556, 100), (596, 106)]),
    ]
    bairros = [
        Bairro(
            "A",
            "Olaria do Barranco",
            135,
            150,
            62,
            16,
            [
                ("exp_galpao", -24, 18, 180, 1.25),
                ("exp_galpao", 24, 22, 180, 1.25),
                ("exp_telheiro", -26, -6, 90, 1.15),
                ("exp_telheiro", 27, -4, -90, 1.15),
                ("exp_deposito", 0, 31, 180, 1.15),
                ("exp_carroca", -10, -19, 20, 1.0),
            ],
            RES[:8] + ("exp_celeiro",),
            [("exp_figueira", 41, 30, 1.0), ("coconut_palm", -42, 24, 1.0)],
        ),
        Bairro(
            "B",
            "Escola do Pomar",
            245,
            190,
            60,
            15,
            [
                ("exp_sobrado_b", 0, 24, 180, 1.1),
                ("exp_sobrado_d", -27, 2, 90, 1.1),
                ("exp_sobrado_d", 27, 2, -90, 1.1),
                ("well", 0, -21, 0, 1.0),
                ("exp_telheiro", -34, 27, 135, 1.15),
            ],
            RES[2:] + ("exp_casa_verde",),
            [("exp_figueira", -3, 2, 1.1), ("ph_island_tree_01", 44, 26, 1.0)],
        ),
        Bairro(
            "C",
            "Mercado das Duas Margens",
            350,
            150,
            58,
            22,
            [
                # a praça das coberturas: o sobrado fecha o norte, a galeria o leste, e as bancas
                # em volta do pátio criam as aproximações diagonais
                ("ret_merc_sobrado", 5, 33, 180, 1.0),
                ("ret_merc_galeria", 35, 10, -90, 1.0),
                # anel de bancas em volta do pátio, com vãos nas diagonais
                ("ret_merc_banca_a", -15, 19, 135, 1.0),
                ("ret_merc_banca_c", -22, 8, 105, 1.0),
                ("ret_merc_banca_b", -22, -6, 75, 1.0),
                ("ret_merc_banca_a", -15, -18, 45, 1.0),
                ("ret_merc_banca_b", 15, -19, -45, 1.0),
                ("ret_merc_banca_c", 23, -9, -70, 1.0),
                ("ret_merc_banca_a", 24, 4, -100, 1.0),
                ("ret_merc_banca_b", 19, 21, -135, 1.0),
                ("ret_merc_cozinha", -13, 35, 160, 1.0),
                # a oficina fica na cabeceira da ponte, do outro lado da estrada
                ("ret_merc_oficina", -10, -38, 0, 1.0),
                ("exp_sobrado_c", 62, -4, -90, 1.1),
                ("exp_deposito", 8, 52, 180, 1.15),
            ],
            SOB + RES[5:] + ("exp_casas_ligadas", "exp_deposito"),
            [("exp_figueira", 28, 31, 1.25)],
            praca=(4, 4, 31),
            # cobertura dentro da captura, com o centro e as diagonais livres
            miolo=[
                ("ret_merc_banca_b", -9, 8, 130, 1.0),
                ("ret_merc_banca_a", 9, 9, -130, 1.0),
                ("ret_merc_banca_c", 9, -9, -50, 1.0),
                ("exp_carroca", -9, -9, 40, 1.0),
            ],
        ),
        Bairro(
            "D",
            "Engenho do Canal",
            455,
            110,
            60,
            15,
            [
                ("exp_galpao", -2, -22, 0, 1.25),
                ("exp_galpao", 26, -24, 0, 1.25),
                ("exp_deposito", -28, -6, 90, 1.15),
                ("exp_celeiro", 28, 1, -90, 1.15),
                ("exp_telheiro", 2, 4, 180, 1.15),
                ("exp_comporta", -30, -36, 0, 1.0),
            ],
            RES[:6] + ("exp_celeiro", "exp_deposito"),
            [("melaleuca_grove", 42, -30, 1.0)],
        ),
        Bairro(
            "E",
            "Vila dos Esteios",
            565,
            150,
            62,
            20,
            [
                ("exp_sobrado_a", 0, 30, 180, 1.1),
                ("exp_palafita_a", -26, 14, 110, 1.2),
                ("exp_palafita_b", 26, 16, -110, 1.2),
                ("exp_palafita_a", -24, -14, 60, 1.2),
                ("exp_palafita_b", 25, -13, -60, 1.2),
            ],
            PAL + PAL + RES[7:] + ("exp_casa_vala",),
            [("exp_figueira", 12, 8, 1.15), ("banana", -38, 30, 1.0)],
        ),
    ]
    return Projeto(
        id="frente",
        comp=700,
        prof=300,
        setores=[
            ("A", 135, 150),
            ("B", 245, 190),
            ("C", 350, 150),
            ("D", 455, 110),
            ("E", 565, 150),
        ],
        bases=[("oeste", 35, 150), ("leste", 665, 150)],
        rio=[
            (352, 470),
            (346, 330),
            (338, 250),
            (325, 190),
            (318, 128),
            (302, 70),
            (318, 0),
            (332, -30),
            (340, -170),
        ],  # fmt: skip
        rio_largura=15.0,
        pontes_previstas=[(318, 128), (337, 233), (303, 62)],
        morros=[
            (205, 268, 44, 8.5),
            (430, 276, 48, 9.0),
            (505, 34, 44, 8.5),
            (118, 36, 40, 7.5),
            (622, 266, 42, 8.0),
            (262, 22, 36, 6.0),
            (640, 30, 36, 6.0),
        ],  # fmt: skip
        vias=vias,
        bairros=bairros,
        campos=[
            (150, 18, 292, 56),
            (345, 18, 470, 56),
            (462, 244, 650, 288),
            (70, 232, 170, 280),
            (372, 196, 450, 228),
        ],  # fmt: skip
    )


def comboio() -> Projeto:
    tr = json.loads((SAIDA_PLANTA / "comboio_trajeto.json").read_text("utf-8"))
    guia = [(p[0], p[1]) for p in tr["pontos"]]
    principal = Via("principal", guia, amostrada=np.array(guia))
    vias = [
        principal,
        Via(
            "trilha",
            [
                (40, 200),
                (125, 228),
                (215, 200),
                (262, 240),
                (310, 250),
                (392, 238),
                (452, 208),
                (520, 232),
                (575, 250),
                (670, 212),
                (770, 240),
                (840, 214),
            ],
        ),  # fmt: skip
        Via(
            "trilha",
            [
                (55, 70),
                (125, 95),
                (215, 55),
                (310, 110),
                (372, 92),
                (428, 68),
                (480, 50),
                (560, 110),
                (640, 80),
                (720, 110),
                (790, 120),
                (842, 100),
            ],
        ),  # fmt: skip
        Via("secundaria", [(121, 168), (120, 200), (125, 228)]),
        Via("secundaria", [(214, 116), (205, 86), (215, 55)]),
        Via("secundaria", [(262, 158), (252, 200), (262, 240)]),
        Via("secundaria", [(312, 203), (305, 160), (310, 110)]),
        Via("secundaria", [(392, 160), (395, 200), (392, 238)]),
        Via("secundaria", [(392, 160), (382, 126), (372, 92)]),
        Via("secundaria", [(495, 112), (486, 80), (480, 50)]),
        Via("secundaria", [(574, 199), (578, 226), (575, 250)]),
        Via("secundaria", [(585, 192), (574, 150), (560, 110)]),
        Via("secundaria", [(668, 136), (654, 106), (640, 80)]),
        Via("secundaria", [(672, 137), (676, 176), (670, 212)]),
        Via("secundaria", [(770, 195), (772, 218), (770, 240)]),
        Via("secundaria", [(762, 192), (736, 150), (720, 110)]),
        Via("rua", [(70, 148), (92, 186), (136, 182)]),
        Via("rua", [(150, 158), (150, 128), (120, 112)]),
        Via("rua", [(226, 152), (250, 176), (286, 168)]),
        Via("rua", [(238, 104), (270, 122), (302, 140)]),
        Via("rua", [(322, 196), (336, 170), (322, 142)]),
        Via("rua", [(470, 76), (500, 70), (526, 92)]),
        Via("rua", [(506, 122), (530, 108), (520, 84)]),
        Via("rua", [(546, 176), (570, 160), (610, 166), (636, 186)]),
        Via("rua", [(600, 196), (622, 214), (606, 234)]),
        Via("rua", [(814, 132), (832, 110), (866, 118)]),
        Via("rua", [(808, 180), (834, 196), (872, 186)]),
    ]
    bairros = [
        Bairro(
            "R",
            "Arrozais das Comportas",
            100,
            150,
            58,
            10,
            [
                ("exp_celeiro", -38, 30, 150, 1.15),
                ("exp_celeiro", 30, 36, 200, 1.15),
                ("exp_comporta", -14, -46, 0, 1.0),
                ("exp_telheiro", 4, -30, 10, 1.15),
                ("us_tent_gp_large", -60, -6, 90, 1.0),
            ],
            ("vila_casa_01", "vila_casa_05", "vila_casa_09", "exp_celeiro"),
            [("canopy_tree", 56, -22, 1.0)],
        ),
        Bairro(
            "CP1",
            "Vila do Sino Baixo",
            262,
            150,
            74,
            26,
            [
                ("exp_sobrado_a", -36, -8, 40, 1.1),
                ("exp_palafita_a", 14, -28, 25, 1.2),
                ("exp_telheiro", -22, -42, 20, 1.15),
                ("shrine", -44, -30, 45, 1.0),
            ],
            PAL + RES + ("exp_casas_ligadas",),
            [("exp_figueira", -28, -26, 1.1)],
        ),
        Bairro(
            "CP2",
            "Ponte do Canal Torto",
            482,
            96,
            52,
            13,
            [
                ("exp_galpao", 22, -22, -20, 1.25),
                ("exp_deposito", 44, -8, -70, 1.15),
                ("exp_telheiro", -2, -32, 0, 1.15),
                ("exp_casa_vala", 30, 20, 200, 1.15),
            ],
            RES[3:9] + ("exp_deposito",),
            [("ph_island_tree_02", -8, -44, 1.0)],
        ),
        Bairro(
            "CP3",
            "Serraria",
            590,
            186,
            60,
            13,
            [
                ("exp_galpao", -28, 28, 170, 1.25),
                ("exp_galpao", 16, 34, 190, 1.25),
                ("exp_telheiro", 42, 12, -90, 1.15),
                ("exp_telheiro", -44, 2, 80, 1.15),
                ("exp_deposito", 34, -24, -40, 1.15),
            ],
            RES[1:7] + ("exp_celeiro",),
            [("canopy_tree", -6, 54, 1.0)],
        ),
        Bairro(
            "ENT",
            "Engenho do Espigão",
            845,
            165,
            56,
            13,
            [
                ("exp_sobrado_d", 8, 34, 180, 1.1),
                ("exp_galpao", -28, 26, 160, 1.25),
                ("exp_galpao", 34, -2, -90, 1.25),
                ("exp_deposito", -36, -18, 70, 1.15),
                ("exp_celeiro", 22, -36, -20, 1.15),
            ],
            RES[2:8] + ("exp_deposito",),
            [("exp_figueira", -40, 40, 1.0)],
        ),
    ]
    return Projeto(
        id="comboio",
        comp=900,
        prof=300,
        setores=[
            ("A", 95, 150),
            ("B", 215, 115),
            ("C", 480, 105),
            ("D", 575, 200),
            ("E", 850, 150),
        ],  # fmt: skip
        bases=[("oeste", 20, 168), ("leste", 882, 104)],
        rio=[
            (470, 470),
            (462, 330),
            (452, 212),
            (440, 130),
            (428, 68),
            (440, -30),
            (452, -170),
        ],  # fmt: skip
        rio_largura=15.0,
        pontes_previstas=[(440, 130), (452, 208), (428, 68)],
        morros=[
            (150, 270, 46, 8.0),
            (345, 276, 50, 8.0),
            (622, 280, 48, 9.0),
            (705, 34, 44, 8.0),
            (300, 30, 46, 7.0),
            (560, 26, 40, 6.5),
        ],  # fmt: skip
        vias=vias,
        bairros=bairros,
        campos=[
            (20, 196, 230, 280),
            (20, 18, 190, 96),
            (240, 262, 400, 288),
            (490, 16, 690, 48),
            (660, 232, 830, 286),
            (690, 28, 860, 84),
        ],  # fmt: skip
        lombada=(527.5, 152.5, 6.0, 44.0, 70.0),
    )


# ===================================================================== geração
class Mapa:
    def __init__(self, p: Projeto) -> None:
        self.p = p
        self.w = int(math.ceil((p.comp + 2 * MARGEM) / (CELL * M)))
        self.h = int(math.ceil((p.prof + 2 * MARGEM) / (CELL * M)))
        self.ox = -self.w * CELL / 2
        self.oz = -self.h * CELL / 2
        col = (np.arange(self.w) + 0.5) * CELL + self.ox
        row = (np.arange(self.h) + 0.5) * CELL + self.oz
        wx, wz = np.meshgrid(col, row)
        self.xm = wx * M + p.comp / 2
        self.ym = p.prof / 2 - wz * M
        self.rio = catmull(p.rio, 3.0)
        for v in p.vias:
            if v.amostrada is None:
                v.amostrada = catmull(v.pts, 3.0)
        self.waters: list[float] = []
        self.dikes: list[float] = []
        self.roads: list[dict] = []
        self.pontes: list[dict] = []
        self.items: list[dict] = []
        self.plantas: list[dict] = []
        self.falhas: list[str] = []

    def mundo(self, x: float, y: float) -> tuple[float, float]:
        return (x - self.p.comp / 2) / M, -(y - self.p.prof / 2) / M

    # ----------------------------------------------------------------- relevo e classes
    def relevo(self) -> None:
        p, x, y = self.p, self.xm, self.ym
        rng = np.random.default_rng(1965 + len(p.id))
        z = np.zeros_like(x)
        for amp, lam in ((0.9, 150), (0.5, 72), (0.22, 31)):
            for _ in range(4):
                a, f = rng.uniform(0, 2 * np.pi), rng.uniform(0, 2 * np.pi)
                k = 2 * np.pi / lam
                z += amp / 2 * np.sin(k * (x * np.cos(a) + y * np.sin(a)) + f)
        for mx, my, r, alt in p.morros:
            z += alt * np.exp(-(((x - mx) ** 2 + (y - my) ** 2) / (r * r)))
        if p.lombada:
            lx, ly, crista, ru, rv = p.lombada
            dx, dy = x - lx, y - ly
            # o eixo longo atravessa a estrada: a lomba interrompe a visão entre CP2 e CP3
            c, s = math.cos(math.radians(-45)), math.sin(math.radians(-45))
            u, v = dx * c + dy * s, -dx * s + dy * c
            z += crista * np.exp(-((u / ru) ** 2 + (v / rv) ** 2))
        # colinas além do limite jogável: fecham o horizonte
        fx = np.maximum(np.maximum(-x, x - p.comp), 0)
        fy = np.maximum(np.maximum(-y, y - p.prof), 0)
        z += 0.13 * np.hypot(fx, fy)
        z += 3.5 * liso(np.hypot(fx, fy) / 60) * np.sin(x / 41 + 0.7) * np.sin(y / 37)
        # os bairros ficam em chão firme e quase plano
        for b in p.bairros:
            d = np.hypot(x - b.x, y - b.y)
            t = liso((d - b.raio * 0.72) / (b.raio * 0.5))
            z = z * t + 0.6 * (1 - t)
        for _sid, sx, sy in p.setores:
            d = np.hypot(x - sx, y - sy)
            t = liso((d - 22) / 26)
            z = z * t + 0.6 * (1 - t)
        for _bid, bx, by in p.bases:
            d = np.hypot(x - bx, y - by)
            t = liso((d - 30) / 30)
            z = z * t + 0.8 * (1 - t)
        self.z = NIVEL + z
        # classes: a mata (4) por padrão, quintais (3) nos bairros e lavoura (2) nos campos
        c = np.full(x.shape, 4, np.uint8)
        for b in p.bairros:
            c[np.hypot(x - b.x, y - b.y) < b.raio * 1.05] = 3
        for x0, y0, x1, y1 in p.campos:
            c[(x >= x0) & (x <= x1) & (y >= y0) & (y <= y1)] = 2
        # rio: leito e margem em rampa
        d = dist_polilinha(x, y, self.rio)
        meio = p.rio_largura / 2
        margem = liso((d - meio) / 9.0)
        nivel = np.minimum(self.z, NIVEL + 0.2)
        self.z = (nivel - LEITO) * (1 - margem) + self.z * margem
        c[d <= meio] = 5
        self.dist_rio = d
        self.c = c

    def altura(self, x: float, y: float) -> float:
        fx = ((x - self.p.comp / 2) / M - self.ox) / CELL - 0.5
        fz = (-(y - self.p.prof / 2) / M - self.oz) / CELL - 0.5
        c0, r0 = int(math.floor(fx)), int(math.floor(fz))
        tx, tz = fx - c0, fz - r0

        def h(c: int, r: int) -> float:
            return float(self.z[np.clip(r, 0, self.h - 1), np.clip(c, 0, self.w - 1)])

        return (h(c0, r0) * (1 - tx) + h(c0 + 1, r0) * tx) * (1 - tz) + (
            h(c0, r0 + 1) * (1 - tx) + h(c0 + 1, r0 + 1) * tx
        ) * tz

    # ----------------------------------------------------------------- estradas e pontes
    def estradas(self) -> None:
        for v in self.p.vias:
            c = v.amostrada
            assert c is not None
            d = dist_polilinha(c[:, 0], c[:, 1], self.rio)
            limite = self.p.rio_largura / 2 + 2.5
            fora = d > limite
            trechos: list[np.ndarray] = []
            i = 0
            while i < len(c):
                if not fora[i]:
                    i += 1
                    continue
                j = i
                while j + 1 < len(c) and fora[j + 1]:
                    j += 1
                if j > i:
                    trechos.append(c[i : j + 1])
                i = j + 1
            ys = [self.perfil(t) for t in trechos]
            for t, y in zip(trechos, ys, strict=True):
                pts: list[float] = []
                for k in range(0, len(t)):
                    wx, wz = self.mundo(t[k, 0], t[k, 1])
                    pts += [round(wx, 2), round(wz, 2), round(float(y[k]) / M, 2)]
                self.roads.append({"kind": v.tipo, "pts": pts})
            for a in range(len(trechos) - 1):
                pa, pb = trechos[a][-1], trechos[a + 1][0]
                ya, yb = float(ys[a][-1]), float(ys[a + 1][0])
                # deck em nível: o maior dos dois encontros
                self.pontes.append(
                    {
                        "tipo": "rodoviaria" if v.tipo == "principal" else "passarela",
                        "a": (float(pa[0]), float(pa[1]), max(ya, yb)),
                        "b": (float(pb[0]), float(pb[1]), max(ya, yb)),
                    }
                )

    def perfil(self, t: np.ndarray) -> np.ndarray:
        y = np.array([self.altura(float(a), float(b)) for a, b in t])
        # média móvel e rampa máxima de 12%
        k = 9
        if len(y) > k:
            bord = np.pad(y, k // 2, mode="edge")
            y = np.convolve(bord, np.ones(k) / k, mode="valid")
        passos = np.hypot(*np.diff(t, axis=0).T)
        for i in range(1, len(y)):
            y[i] = min(y[i], y[i - 1] + 0.12 * passos[i - 1])
        for i in range(len(y) - 2, -1, -1):
            y[i] = min(y[i], y[i + 1] + 0.12 * passos[i])
        return y

    # ----------------------------------------------------------------- arrozais
    def arrozais(self) -> None:
        rng = np.random.default_rng(65 + len(self.p.id))
        for x0, y0, x1, y1 in self.p.campos:
            y = y0
            while y < y1 - 8:
                alt = min(rng.uniform(14, 22), y1 - y)
                x = x0
                while x < x1 - 10:
                    comp = min(rng.uniform(22, 38), x1 - x)
                    cx, cy = x + comp / 2, y + alt / 2
                    u, v = comp - 2.2, alt - 2.2
                    if self.tabuleiro_livre(cx, cy, u, v):
                        self.tabuleiro(cx, cy, u, v, float(rng.uniform(-0.05, 0.05)))
                    x += comp
                y += alt

    def tabuleiro_livre(self, cx: float, cy: float, u: float, v: float) -> bool:
        xs = np.array([cx + a * u / 2 for a in (-1, 0, 1) for _b in (-1, 0, 1)])
        ys = np.array([cy + b * v / 2 for _a in (-1, 0, 1) for b in (-1, 0, 1)])
        if (dist_polilinha(xs, ys, self.rio) < self.p.rio_largura / 2 + 7).any():
            return False
        for via in self.p.vias:
            assert via.amostrada is not None
            if (dist_polilinha(xs, ys, via.amostrada) < 6).any():
                return False
        return all(math.hypot(cx - b.x, cy - b.y) >= b.raio * 0.8 for b in self.p.bairros)

    def tabuleiro(self, cx: float, cy: float, u: float, v: float, ang: float) -> None:
        wx, wz = self.mundo(cx, cy)
        topo = self.altura(cx, cy)
        self.waters += [wx, wz, topo / M, u / M, v / M, ang]
        ca, sa = math.cos(ang), math.sin(ang)
        cantos = []
        for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            lu, lv = a * (u + 1) / 2 / M, b * (v + 1) / 2 / M
            cantos.append((wx + lu * ca + lv * sa, wz - lu * sa + lv * ca))
        for i in range(4):
            p, q = cantos[i], cantos[(i + 1) % 4]
            self.dikes += [p[0], p[1], q[0], q[1], (topo + 0.45) / M, topo / M]

    # ----------------------------------------------------------------- ocupação
    def mascara(self) -> None:
        p = self.p
        self.mw, self.mh = int(p.comp / MASK_M) + 1, int(p.prof / MASK_M) + 1
        im = Image.new("L", (self.mw, self.mh), 0)
        dr = ImageDraw.Draw(im)
        larg = {"principal": 8.5, "secundaria": 5.5, "rua": 6.0, "trilha": 3.5}

        def px(a):
            return (a[0] / MASK_M, (p.prof - a[1]) / MASK_M)

        for v in p.vias:
            assert v.amostrada is not None
            pts = [px(a) for a in v.amostrada]
            dr.line(pts, fill=255, width=int((larg[v.tipo] + 2.4) / MASK_M), joint="curve")
        rio = [px(a) for a in self.rio]
        dr.line(rio, fill=255, width=int((p.rio_largura + 7) / MASK_M), joint="curve")
        for _sid, sx, sy in p.setores:
            r = CAPTURA_R / MASK_M
            cx, cy = px((sx, sy))
            dr.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
        for _bid, bx, by in p.bases:
            r = 16 / MASK_M
            cx, cy = px((bx, by))
            dr.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
        for i in range(0, len(self.waters), 6):
            cx = self.waters[i] * M + p.comp / 2
            cy = p.prof / 2 - self.waters[i + 1] * M
            u, v = self.waters[i + 3] * M / 2, self.waters[i + 4] * M / 2
            a, b = px((cx - u, cy + v)), px((cx + u, cy - v))
            dr.rectangle((a[0], a[1], b[0], b[1]), fill=255)
        self.ocup = np.array(im, dtype=np.uint8)

    def caixa(self, x: float, y: float, rumo: float, hx: float, hy: float):
        """Cantos da pegada no plano; `rumo` = direção da frente do modelo (rad, plano)."""
        fx, fy = math.cos(rumo), math.sin(rumo)  # frente
        rx, ry = fy, -fx  # direita
        return [
            (x + a * hx * rx + b * hy * fx, y + a * hx * ry + b * hy * fy)
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))
        ]

    def cabe(self, x: float, y: float, rumo: float, hx: float, hy: float) -> bool:
        p = self.p
        fx, fy = math.cos(rumo), math.sin(rumo)
        rx, ry = fy, -fx
        nu = max(2, int(2 * hx / 0.8))
        nv = max(2, int(2 * hy / 0.8))
        for iu in range(nu + 1):
            a = -hx + 2 * hx * iu / nu
            for iv in range(nv + 1):
                b = -hy + 2 * hy * iv / nv
                qx, qy = x + a * rx + b * fx, y + a * ry + b * fy
                if not (2 <= qx <= p.comp - 2 and 2 <= qy <= p.prof - 2):
                    return False
                if self.ocup[int((p.prof - qy) / MASK_M), int(qx / MASK_M)]:
                    return False
        return True

    def marca(self, x: float, y: float, rumo: float, hx: float, hy: float, folga: float) -> None:
        p = self.p
        cantos = self.caixa(x, y, rumo, hx + folga, hy + folga)
        pts = [(a / MASK_M, (p.prof - b) / MASK_M) for a, b in cantos]
        im = Image.fromarray(self.ocup)
        ImageDraw.Draw(im).polygon(pts, fill=255)
        self.ocup = np.array(im, dtype=np.uint8)

    def poe(self, chave, x, y, rumo_graus, escala, tipo, forca=False) -> bool:
        d = DIMS.get(chave)
        if d is None:
            self.falhas.append(f"sem dimensão: {chave}")
            return False
        hx, hy = d[0] * M * escala / 2, d[2] * M * escala / 2
        rumo = math.radians(rumo_graus)
        if not forca and not self.cabe(x, y, rumo, hx, hy):
            return False
        self.marca(x, y, rumo, hx, hy, 1.3)
        # frente do modelo em -Z do Roblox: giro em Y com (fX, fZ) = (cos rumo, -sen rumo)
        fx, fz = math.cos(rumo), -math.sin(rumo)
        wx, wz = self.mundo(x, y)
        self.items.append(
            {
                "key": chave,
                "x": round(wx, 2),
                "z": round(wz, 2),
                "yaw": round(math.atan2(-fx, -fz), 4),
                "scale": escala,
                "tipo": tipo,
                "xm": x,
                "ym": y,
                "hx": hx,
                "hy": hy,
                "rumo": rumo,
            }
        )
        return True

    # ----------------------------------------------------------------- bairros
    def bairros(self) -> None:
        rng = np.random.default_rng(1965)
        for b in self.p.bairros:
            for chave, dx, dy, rumo, escala in b.marcos:
                ok = False
                # o marco pode correr até 6 m para caber fora das vias
                for r in (0, 2, 4, 6, 8, 10, 12):
                    for a in range(0, 360, 45) if r else (0,):
                        qx = b.x + dx + r * math.cos(math.radians(a))
                        qy = b.y + dy + r * math.sin(math.radians(a))
                        if self.poe(chave, qx, qy, 90 - rumo, escala, "marco"):
                            ok = True
                            break
                    if ok:
                        break
                if not ok:
                    self.falhas.append(f"{b.id}: marco {chave} sem lugar")
            for chave, dx, dy, rumo, escala in b.miolo:
                self.poe(chave, b.x + dx, b.y + dy, 90 - rumo, escala, "marco", forca=True)
            for chave, dx, dy, escala in b.arvores:
                self.plantas.append({"key": chave, "x": b.x + dx, "y": b.y + dy, "scale": escala})
            postos = 0
            tentativas = 0
            while postos < b.casas and tentativas < 2400:
                tentativas += 1
                chave = str(rng.choice(b.tipos))
                via = self.via_perto(b, rng)
                if via is None:
                    break
                qx, qy, nx, ny = via
                d = DIMS[chave]
                esc = ESCALA.get(chave, 1.2)
                recuo = d[2] * M * esc / 2 + float(rng.uniform(2.2, 4.8))
                lado = 1 if rng.random() < 0.5 else -1
                x = qx + nx * lado * recuo
                y = qy + ny * lado * recuo
                if math.hypot(x - b.x, y - b.y) > b.raio:
                    continue
                # a frente olha para a via, com um pouco de torção: nada de fila reta
                rumo = math.degrees(math.atan2(-ny * lado, -nx * lado)) + float(
                    rng.uniform(-11, 11)
                )
                if self.poe(chave, x, y, rumo, esc, "casa"):
                    postos += 1
            if postos < b.casas:
                self.falhas.append(f"{b.id}: {postos} de {b.casas} casas")

    def via_perto(self, b: Bairro, rng) -> tuple[float, float, float, float] | None:
        cand = []
        for v in self.p.vias:
            c = v.amostrada
            assert c is not None
            d = np.hypot(c[:, 0] - b.x, c[:, 1] - b.y)
            idx = np.nonzero(d < b.raio)[0]
            idx = idx[(idx > 0) & (idx < len(c) - 1)]
            if len(idx):
                cand.append((c, idx))
        if not cand:
            return None
        c, idx = cand[int(rng.integers(len(cand)))]
        i = int(rng.choice(idx))
        tx, ty = c[i + 1] - c[i - 1]
        n = max(math.hypot(tx, ty), 1e-6)
        return float(c[i, 0]), float(c[i, 1]), float(-ty / n), float(tx / n)

    # ----------------------------------------------------------------- conjuntos de nascer
    def conjuntos(self) -> None:
        """Lugares prontos para nascer, com chão livre e duas saídas a pé em direções diferentes."""
        p = self.p
        im = Image.new("L", (self.mw, self.mh), 0)
        dr = ImageDraw.Draw(im)

        def px(a: float, b: float) -> tuple[float, float]:
            return (a / MASK_M, (p.prof - b) / MASK_M)

        dr.line(
            [px(float(a), float(b)) for a, b in self.rio],
            fill=255,
            width=int((p.rio_largura + 4) / MASK_M),
            joint="curve",
        )
        for it in self.items:
            cantos = self.caixa(it["xm"], it["ym"], it["rumo"], it["hx"] + 0.8, it["hy"] + 0.8)
            dr.polygon([px(a, b) for a, b in cantos], fill=255)
        # a saída a pé não atravessa o corrimão de uma ponte
        for b in self.pontes:
            lg = (8.0 if p.id == "comboio" else 7.0) if b["tipo"] == "rodoviaria" else 3.0
            dr.line(
                (px(b["a"][0], b["a"][1]), px(b["b"][0], b["b"][1])),
                fill=255,
                width=int((lg + 2.0) / MASK_M),
            )
        solido = np.array(im, dtype=np.uint8) > 0
        soma = np.zeros((self.mh + 1, self.mw + 1), np.int64)
        soma[1:, 1:] = (self.ocup > 0).cumsum(0).cumsum(1)
        r = int(CONJ_LIVRE_M / MASK_M)

        def livre(x: float, y: float) -> bool:
            if not (6 <= x <= p.comp - 6 and 6 <= y <= p.prof - 6):
                return False
            i, j = int((p.prof - y) / MASK_M), int(x / MASK_M)
            i0, i1 = max(i - r, 0), min(i + r + 1, self.mh)
            j0, j1 = max(j - r, 0), min(j + r + 1, self.mw)
            if soma[i1, j1] - soma[i0, j1] - soma[i1, j0] + soma[i0, j0] != 0:
                return False
            z0 = self.altura(x, y)
            return all(
                abs(self.altura(x + a, y + b) - z0) <= 1.6
                for a, b in ((4, 0), (-4, 0), (0, 4), (0, -4))
            )

        def aberta(x: float, y: float, a: float) -> bool:
            for d in np.arange(3.0, CONJ_SAIDA_M + 0.1, 1.5):
                qx, qy = x + d * math.cos(a), y + d * math.sin(a)
                if not (2 <= qx <= p.comp - 2 and 2 <= qy <= p.prof - 2):
                    return False
                if solido[int((p.prof - qy) / MASK_M), int(qx / MASK_M)]:
                    return False
            return True

        def saidas(x: float, y: float, alvo: tuple[float, float]) -> list[tuple] | None:
            abertas = [a for a in (2 * math.pi * k / 24 for k in range(24)) if aberta(x, y, a)]
            rumo = math.atan2(alvo[1] - y, alvo[0] - x)
            melhor, par = -math.inf, None
            for i, a in enumerate(abertas):
                for b in abertas[i + 1 :]:
                    sep = abs((a - b + math.pi) % (2 * math.pi) - math.pi)
                    if sep < math.radians(CONJ_SEPARA_GRAUS):
                        continue
                    nota = math.cos(a - rumo) + math.cos(b - rumo)
                    if nota > melhor:
                        melhor, par = nota, (a, b)
            if par is None:
                return None
            return [(x + CONJ_SAIDA_M * math.cos(q), y + CONJ_SAIDA_M * math.sin(q)) for q in par]

        def longe(x: float, y: float) -> bool:
            if any(math.hypot(x - c["xm"], y - c["ym"]) < CONJ_ENTRE_M for c in self.conj):
                return False
            alvos = [(a, b) for _i, a, b in p.setores] + [(a, b) for _i, a, b in p.bases]
            return all(math.hypot(x - a, y - b) >= 30 for a, b in alvos)

        def escolhe(cands: list[tuple], alvo: tuple[float, float], s: float) -> bool:
            for _d, qx, qy in sorted(cands):
                if not (longe(qx, qy) and livre(qx, qy)):
                    continue
                sa = saidas(qx, qy, alvo)
                if sa:
                    self.conj.append({"xm": float(qx), "ym": float(qy), "s": s, "saidas": sa})
                    return True
            return False

        self.conj: list[dict] = []
        if p.id == "frente":
            for xt in range(55, 650, 42):
                for ya, yb, yc in ((195, 288, 232), (12, 105, 68)):
                    cands = [
                        (math.hypot(qx - xt, qy - yc), float(qx), float(qy))
                        for qx in np.arange(xt - 18, xt + 18.1, 2)
                        for qy in np.arange(ya, yb, 2)
                    ]
                    if not escolhe(cands, (float(xt), 150.0), 0.0):
                        self.falhas.append(f"conjunto sem lugar em x = {xt}, y = {yc}")
        else:
            tr = json.loads((SAIDA_PLANTA / "comboio_trajeto.json").read_text("utf-8"))
            g = np.array(tr["pontos"], float)
            for sv in np.arange(30.0, tr["comprimento"] - 20, CONJ_PASSO_M):
                i = int(round((sv + 18) / 3))
                i = int(np.clip(i, 1, len(g) - 2))
                tx, ty = g[i + 1] - g[i - 1]
                n = max(math.hypot(tx, ty), 1e-6)
                nx, ny = -ty / n, tx / n
                for lado in (1, -1):
                    cands = []
                    for afasta in np.arange(24.0, 62.0, 2.0):
                        for corre in np.arange(-22.0, 22.1, 3.0):
                            qx = g[i, 0] + nx * lado * afasta + tx / n * corre
                            qy = g[i, 1] + ny * lado * afasta + ty / n * corre
                            cands.append((afasta + abs(corre) * 0.3, float(qx), float(qy)))
                    alvo = (float(g[i, 0]), float(g[i, 1]))
                    if not escolhe(cands, alvo, float(sv)):
                        self.falhas.append(f"conjunto sem lugar em s = {sv:.0f}, lado {lado}")

    # ----------------------------------------------------------------- saída
    def grava(self) -> None:
        pasta = BUILD / f"Data_{self.p.id}"
        pasta.mkdir(parents=True, exist_ok=True)
        for velho in pasta.glob("*.luau"):
            velho.unlink()
        cm = np.clip(np.round(self.z * 100) + HOFF, 0, 65535).astype("<u2")
        nomes = []
        for k, r0 in enumerate(range(0, self.h, ROWS_PER)):
            parte = cm[r0 : r0 + ROWS_PER]
            nome = f"Heights_{k:02d}"
            nomes.append(nome)
            dado = base64.b64encode(parte.tobytes()).decode("ascii")
            (pasta / f"{nome}.luau").write_text(
                HEAD + f'return {{ row0 = {r0}, rows = {parte.shape[0]}, data = "{dado}" }}\n',
                "utf-8",
                newline="\n",
            )
        rle = bytearray()
        for linha in self.c:
            j = 0
            while j < len(linha):
                c, n = int(linha[j]), 1
                while j + n < len(linha) and linha[j + n] == c and n < 255:
                    n += 1
                rle += bytes((c, n))
                j += n
        lista = ", ".join(f'"{n}"' for n in nomes)
        classes = ", ".join(f'"{n}"' for n in NOMES_CLASSE)
        (pasta / "Grid.luau").write_text(
            HEAD + "return {\n"
            f"\twidth = {self.w}, height = {self.h}, cellStuds = {CELL},\n"
            f"\toriginX = {self.ox:.2f}, originZ = {self.oz:.2f},\n"
            f"\theightOffsetCm = {HOFF},\n"
            f"\tstreamCarvedCm = {int(LEITO * 100)},\n"
            f"\theightChunks = {{{lista}}}, rowsPerChunk = {ROWS_PER},\n"
            f"\tclassNames = {{{classes}}},\n"
            f'\tclassesRle = "{base64.b64encode(bytes(rle)).decode()}",\n'
            "}\n",
            "utf-8",
            newline="\n",
        )

        def lst(v: list[float]) -> str:
            return "{" + ",".join(f"{a:.2f}" for a in v) + "}"

        (pasta / "Features.luau").write_text(
            HEAD + "return {\n"
            f"\tdikes = {lst(self.dikes)},\n"
            "\thedges = {},\n"
            f"\twaters = {lst(self.waters)},\n"
            "\thouses = {},\n"
            "}\n",
            "utf-8",
            newline="\n",
        )
        larg = {"principal": 8.0 if self.p.id == "comboio" else 7.0, "secundaria": 5.0}
        larg |= {"rua": 6.0, "trilha": 3.0, "beco": 2.5}
        w_txt = ", ".join(f"{k} = {v / M:.2f}" for k, v in larg.items())
        rs = "".join(
            f'\t\t{{ kind = "{r["kind"]}", pts = {{'
            + ",".join(f"{a:g}" for a in r["pts"])
            + "} },\n"
            for r in self.roads
        )
        (pasta / "Roads.luau").write_text(
            HEAD + "return {\n"
            f"\twidth = {{ {w_txt} }},\n"
            f"\tshoulder = {3 / M:.2f}, gradeMax = 0.12,\n"
            "\troads = {\n" + rs + "\t},\n}\n",
            "utf-8",
            newline="\n",
        )
        itens = "".join(
            f'\t\t{{ key = "{i["key"]}", x = {i["x"]}, z = {i["z"]}, yaw = {i["yaw"]}, '
            f'scale = {i["scale"]}, tipo = "{i["tipo"]}" }},\n'
            for i in self.items
        )
        plantas = ""
        for a in self.plantas:
            wx, wz = self.mundo(a["x"], a["y"])
            plantas += (
                f'\t\t{{ key = "{a["key"]}", x = {wx:.2f}, z = {wz:.2f}, scale = {a["scale"]} }},\n'
            )
        pontes = ""
        for a in self.pontes:
            x1, z1 = self.mundo(a["a"][0], a["a"][1])
            x2, z2 = self.mundo(a["b"][0], a["b"][1])
            y = a["a"][2] / M
            lg = (8.0 if self.p.id == "comboio" else 7.0) if a["tipo"] == "rodoviaria" else 3.0
            pontes += (
                f'\t\t{{ tipo = "{a["tipo"]}", x1 = {x1:.2f}, z1 = {z1:.2f}, x2 = {x2:.2f}, '
                f"z2 = {z2:.2f}, y = {y:.2f}, largura = {lg / M:.2f} }},\n"
            )
        pracas = ""
        for b in self.p.bairros:
            if b.praca:
                wx, wz = self.mundo(b.x + b.praca[0], b.y + b.praca[1])
                pracas += f"\t\t{{ x = {wx:.2f}, z = {wz:.2f}, r = {b.praca[2] / M:.2f} }},\n"
        conj = ""
        for k, c in enumerate(self.conj, 1):
            wx, wz = self.mundo(c["xm"], c["ym"])
            s1 = self.mundo(*c["saidas"][0])
            s2 = self.mundo(*c["saidas"][1])
            conj += (
                f'\t\t{{ id = "c{k:02d}", x = {wx:.2f}, z = {wz:.2f}, s = {c["s"]:.1f}, '
                f"sx1 = {s1[0]:.2f}, sz1 = {s1[1]:.2f}, sx2 = {s2[0]:.2f}, sz2 = {s2[1]:.2f} }},\n"
            )
        (pasta / "Layout.luau").write_text(
            HEAD + "return {\n"
            f'\tid = "{self.p.id}",\n'
            "\titems = {\n" + itens + "\t},\n"
            "\tplantas = {\n" + plantas + "\t},\n"
            "\tpontes = {\n" + pontes + "\t},\n"
            "\tpracas = {\n" + pracas + "\t},\n"
            "\tconjuntos = {\n" + conj + "\t},\n}\n",
            "utf-8",
            newline="\n",
        )

    def planta(self) -> Path:
        p = self.p
        esc = 2
        margem = 40
        W, H = int((p.comp + 2 * margem) * esc), int((p.prof + 2 * margem) * esc)
        cores = {2: (140, 170, 96), 3: (172, 165, 112), 4: (64, 100, 56), 5: (66, 112, 150)}
        xs = (np.arange(W) + 0.5) / esc - margem
        ys = p.prof + margem - (np.arange(H) + 0.5) / esc
        fx = np.clip(((xs - p.comp / 2) / M - self.ox) / CELL, 0, self.w - 1).astype(int)
        fz = np.clip(((p.prof / 2 - ys) / M - self.oz) / CELL, 0, self.h - 1).astype(int)
        img = np.zeros((H, W, 3), np.uint8)
        cc, zz = self.c[fz][:, fx], self.z[fz][:, fx]
        for k, cor in cores.items():
            img[cc == k] = cor
        sombra = np.clip(0.75 + (zz - NIVEL) / 26, 0.55, 1.35)[..., None]
        img = np.clip(img * sombra, 0, 255).astype(np.uint8)
        im = Image.fromarray(img)
        dr = ImageDraw.Draw(im)

        def px(x, y):
            return ((x + margem) * esc, (p.prof + margem - y) * esc)

        for i in range(0, len(self.waters), 6):
            cx, cy = self.waters[i] * M + p.comp / 2, p.prof / 2 - self.waters[i + 1] * M
            u, v = self.waters[i + 3] * M / 2, self.waters[i + 4] * M / 2
            a, b = px(cx - u, cy + v), px(cx + u, cy - v)
            dr.rectangle((*a, *b), fill=(110, 170, 170), outline=(150, 130, 90))
        cor_via = {
            "principal": (214, 170, 110),
            "secundaria": (190, 150, 100),
            "rua": (200, 160, 110),
            "trilha": (160, 130, 90),
        }
        lv = {"principal": 7, "secundaria": 5, "rua": 6, "trilha": 3}
        for v in p.vias:
            assert v.amostrada is not None
            pts = [px(a, b) for a, b in v.amostrada]
            dr.line(pts, fill=cor_via[v.tipo], width=int(lv[v.tipo] * esc), joint="curve")
        for b in self.pontes:
            cor = (240, 240, 240) if b["tipo"] == "rodoviaria" else (240, 210, 120)
            dr.line((px(b["a"][0], b["a"][1]), px(b["b"][0], b["b"][1])), fill=cor, width=9)
        for it in self.items:
            cantos = self.caixa(it["xm"], it["ym"], it["rumo"], it["hx"], it["hy"])
            cor = (214, 88, 62) if it["tipo"] == "marco" else (156, 104, 76)
            dr.polygon([px(a, b) for a, b in cantos], fill=cor, outline=(30, 25, 20))
            fx2, fy2 = (
                it["xm"] + math.cos(it["rumo"]) * it["hy"],
                it["ym"] + math.sin(it["rumo"]) * it["hy"],
            )
            dr.line((px(it["xm"], it["ym"]), px(fx2, fy2)), fill=(255, 240, 200), width=2)
        for a in self.plantas:
            q = px(a["x"], a["y"])
            dr.ellipse(
                (q[0] - 13, q[1] - 13, q[0] + 13, q[1] + 13), outline=(190, 240, 120), width=3
            )
        for c in self.conj:
            q = px(c["xm"], c["ym"])
            for sa in c["saidas"]:
                dr.line((q, px(*sa)), fill=(255, 150, 240), width=2)
            dr.ellipse((q[0] - 7, q[1] - 7, q[0] + 7, q[1] + 7), fill=(255, 90, 220))
        for sid, sx, sy in p.setores:
            q = px(sx, sy)
            r = CAPTURA_R * esc
            dr.ellipse((q[0] - r, q[1] - r, q[0] + r, q[1] + r), outline=(255, 255, 80), width=3)
            dr.text((q[0] - 4, q[1] - 6), sid, fill=(255, 255, 80))
        for bid, bx, by in p.bases:
            q = px(bx, by)
            dr.rectangle(
                (q[0] - 18, q[1] - 18, q[0] + 18, q[1] + 18), outline=(120, 200, 255), width=3
            )
            dr.text((q[0] - 14, q[1] - 6), bid, fill=(120, 200, 255))
        dr.rectangle((*px(0, p.prof), *px(p.comp, 0)), outline=(255, 255, 255), width=2)
        SAIDA_PLANTA.mkdir(parents=True, exist_ok=True)
        destino = SAIDA_PLANTA / f"{p.id}_planta.png"
        im.save(destino)
        return destino


def gera(p: Projeto) -> None:
    m = Mapa(p)
    m.relevo()
    m.estradas()
    m.arrozais()
    m.mascara()
    m.bairros()
    m.conjuntos()
    m.grava()
    destino = m.planta()
    casas = sum(1 for i in m.items if i["tipo"] == "casa")
    marcos = sum(1 for i in m.items if i["tipo"] == "marco")
    print(
        f"{p.id}: grade {m.w}x{m.h}, {len(m.roads)} trechos de via, {len(m.pontes)} pontes, "
        f"{len(m.waters) // 6} tabuleiros, {marcos} marcos, {casas} casas, "
        f"{len(m.conj)} conjuntos de nascer"
    )
    for a in m.pontes:
        print(
            f"  ponte {a['tipo']}: ({a['a'][0]:.1f}, {a['a'][1]:.1f}) "
            f"a ({a['b'][0]:.1f}, {a['b'][1]:.1f})"
        )
    for f in m.falhas:
        print("  AVISO", f)
    print("  planta:", destino.relative_to(RAIZ))


def main() -> None:
    quer = sys.argv[1:] or ["frente", "comboio"]
    if "frente" in quer:
        gera(frente())
    if "comboio" in quer:
        gera(comboio())


if __name__ == "__main__":
    main()
