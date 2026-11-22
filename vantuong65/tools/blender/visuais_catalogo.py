"""Imagens dos visuais, das camuflagens e das vantagens (D-239).

Dono: "melhore oq eu apontei nas imagens": os cartões do Armário mostravam só o nome do encaixe, a
camuflagem vinha em branco e todas as vantagens usavam a mesma foto. Mesma luz e mesmo acabamento do
`armas_catalogo.py`, sem texto na imagem.

Saída em `assets/ui/visuais/<id>.png`, 512 x 512, RGBA. Sobem como `Catalogo.vis_<id>`.

    $env:VT65_CPU = "1"; $env:VT65_THREADS = "4"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/visuais_catalogo.py -- todas|<ids...> [--teste] [--amostras N] `
        [--saida PASTA]
"""

from __future__ import annotations

import math
import sys
import tempfile
import time
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import armas_catalogo as A  # noqa: E402
import caixas_loja as K  # noqa: E402
import comum as C  # noqa: E402
import loja as L  # noqa: E402

RAIZ = C.RAIZ
DESTINO = RAIZ / "assets" / "ui" / "visuais"
GHILLIE = RAIZ / "assets" / "ghillie"


# ------------------------------------------------------------------ materiais
def mat_camo(nome, cores, escala=26.0, cortes=(0.44, 0.51, 0.58)):
    """Pano com manchas de bordas vivas, em até quatro cores."""
    m = A.mat_tecido(nome, cores[0], escala=1500)
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    ruido = nt.nodes.new("ShaderNodeTexNoise")
    ruido.inputs["Scale"].default_value = escala
    ruido.inputs["Detail"].default_value = 3.4
    ruido.inputs["Roughness"].default_value = 0.52
    ruido.inputs["Distortion"].default_value = 0.9
    nt.links.new(coord.outputs["Object"], ruido.inputs["Vector"])
    rampa = nt.nodes.new("ShaderNodeValToRGB")
    rampa.color_ramp.interpolation = "CONSTANT"
    el = rampa.color_ramp.elements
    el[0].position = 0.0
    el[0].color = (*K.lin(cores[0]), 1.0)
    el[1].position = cortes[0]
    el[1].color = (*K.lin(cores[1]), 1.0)
    for i, cor in enumerate(cores[2:]):
        novo = el.new(cortes[min(i + 1, len(cortes) - 1)])
        novo.color = (*K.lin(cor), 1.0)
    nt.links.new(ruido.outputs["Fac"], rampa.inputs["Fac"])
    nt.links.new(rampa.outputs["Color"], b.inputs["Base Color"])
    return m


def forma_capacete(x, y, z):
    return (x, y * 1.13, z)


# ------------------------------------------------------------------ capacete
def capacete(pano, p, rede=False):
    perfil = [
        (0.0, 0.178),
        (0.046, 0.175),
        (0.092, 0.160),
        (0.125, 0.130),
        (0.143, 0.090),
        (0.150, 0.044),
        (0.151, 0.012),
        (0.165, 0.004),
        (0.176, -0.004),
        (0.172, -0.012),
        (0.150, -0.010),
        (0.0, -0.010),
    ]
    objs = [A.torno("Panela", perfil, pano, (0, 0, 0.012), n=96, deforma=forma_capacete, angulo=58)]
    tira = [(0.1495, 0.034), (0.1545, 0.036), (0.1535, 0.062), (0.1472, 0.066)]
    objs.append(A.torno("Tira", tira, p["borr"], (0, 0, 0.012), n=96, deforma=forma_capacete))
    # as dobras da capa, costuradas de cima para a aba
    for a in (20, 88, 160, 232, 304):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        pts = [
            (0.03 * c, 0.03 * 1.13 * s, 0.190),
            (0.09 * c, 0.09 * 1.13 * s, 0.174),
            (0.127 * c, 0.127 * 1.13 * s, 0.144),
            (0.146 * c, 0.146 * 1.13 * s, 0.104),
            (0.153 * c, 0.153 * 1.13 * s, 0.066),
        ]
        objs.append(A.tubo("Costura", pts, 0.0016, pano))
    jugular = [
        (-0.150, -0.02, 0.016),
        (-0.135, -0.11, -0.022),
        (-0.06, -0.185, -0.040),
        (0.06, -0.185, -0.040),
        (0.135, -0.11, -0.022),
        (0.150, -0.02, 0.016),
    ]
    tira_q = A.tubo("Jugular", jugular, 0.0, p["od2"])
    tira_q.data.bevel_depth = 0.0
    tira_q.data.extrude = 0.008
    objs.append(tira_q)
    if rede:
        for i in range(6):
            objs.append(
                A.toro("Rede", 0.05 + i * 0.019, 0.0007, p["od2"], (0, 0, 0.176 - i * i * 0.0014))
            )
    return objs


def v_cover_leaf(p):
    pano = mat_camo(
        "Folha", [(0.20, 0.27, 0.13), (0.34, 0.42, 0.18), (0.13, 0.18, 0.09), (0.47, 0.50, 0.26)]
    )
    return capacete(pano, p)


def v_cover_cloud(p):
    pano = mat_camo(
        "Nuvem",
        [(0.46, 0.36, 0.23), (0.62, 0.52, 0.34), (0.32, 0.24, 0.15), (0.26, 0.28, 0.16)],
        escala=15.0,
    )
    return capacete(pano, p)


def v_cover_faded(p):
    pano = mat_camo(
        "Desbotada",
        [(0.47, 0.47, 0.34), (0.60, 0.58, 0.44), (0.37, 0.39, 0.27), (0.70, 0.67, 0.52)],
    )
    return capacete(pano, p, rede=True)


def v_repellent_band(p):
    pano = mat_camo(
        "Folha2", [(0.20, 0.27, 0.13), (0.34, 0.42, 0.18), (0.13, 0.18, 0.09), (0.47, 0.50, 0.26)]
    )
    objs = capacete(pano, p)
    corpo = A.mat("Frasco", (0.30, 0.35, 0.18), rug=0.42, clear=0.5, forca=0.0)
    tampa = A.mat("Tampa", (0.10, 0.10, 0.09), rug=0.4, forca=0.0)
    frasco = [
        A.torno(
            "Frasco",
            [
                (0, 0),
                (0.019, 0),
                (0.021, 0.004),
                (0.021, 0.066),
                (0.014, 0.078),
                (0.010, 0.082),
                (0, 0.082),
            ],
            corpo,
        ),
        A.torno(
            "Tampa", [(0, 0.08), (0.0115, 0.08), (0.0115, 0.097), (0.009, 0.100), (0, 0.100)], tampa
        ),
    ]
    A.grupo(frasco, (0.095, -0.150, 0.018), (-14, 0, -30))
    return objs + frasco


def v_cigarette_band(p):
    pano = mat_camo(
        "Folha3", [(0.20, 0.27, 0.13), (0.34, 0.42, 0.18), (0.13, 0.18, 0.09), (0.47, 0.50, 0.26)]
    )
    objs = capacete(pano, p)
    papel = A.mat("Maco", (0.90, 0.87, 0.78), rug=0.46, forca=0.0)
    faixa = A.mat("Faixa", (0.60, 0.10, 0.09), rug=0.42, forca=0.0)
    maco = [
        A.bloco("Maco", (0.056, 0.020, 0.086), (0, 0, 0.043), papel, 0.0022),
        A.bloco("Faixa", (0.0572, 0.0212, 0.024), (0, 0, 0.040), faixa, 0.0008),
    ]
    for i in range(3):
        maco.append(
            A.torno(
                "Cigarro",
                [(0, 0), (0.0042, 0), (0.0042, 0.02), (0, 0.02)],
                p["branco"],
                (-0.012 + i * 0.012, 0, 0.082 + (i % 2) * 0.005),
                n=18,
            )
        )
    A.grupo(maco, (-0.098, -0.150, 0.026), (-14, 0, 32))
    return objs + maco


# ------------------------------------------------------------------ uniformes
def camisa(cor, enrolada=False):
    pano = A.mat_tecido("Farda", cor, escala=1250)
    escuro = A.mat_tecido("Dobra", tuple(c * 0.74 for c in cor), escala=1250)
    botao = A.mat("Botao", (0.09, 0.08, 0.06), rug=0.36, clear=0.4, forca=0.0)
    objs = [
        A.almofada("Base", (0.40, 0.31, 0.040), (0, 0, 0.020), escuro),
        A.almofada("Corpo", (0.385, 0.295, 0.040), (0, 0, 0.052), pano),
    ]
    # gola
    for s in (-1, 1):
        objs.append(
            A.prisma(
                "Gola",
                [(0.0, 0.0), (s * 0.082, 0.012), (s * 0.104, 0.070), (s * 0.018, 0.052)],
                0.009,
                pano if s > 0 else escuro,
                (0, 0.082, 0.073),
                (5, 0, 0),
                0.002,
            )
        )
    objs.append(A.bloco("Pescoco", (0.078, 0.056, 0.006), (0, 0.118, 0.073), escuro, 0.002))
    # carcela e botões
    objs.append(A.bloco("Carcela", (0.030, 0.222, 0.004), (0, -0.030, 0.0735), escuro, 0.001))
    for i in range(4):
        objs.append(
            A.torno(
                "Botao",
                [(0, 0), (0.0066, 0), (0.0068, 0.0016), (0.004, 0.0032), (0, 0.0032)],
                botao,
                (0, 0.056 - i * 0.056, 0.0755),
                n=20,
            )
        )
    # bolsos
    for s in (-1, 1):
        objs.append(
            A.bloco("Bolso", (0.106, 0.116, 0.005), (s * 0.095, 0.010, 0.0740), pano, 0.0016)
        )
        objs.append(
            A.bloco("Aba", (0.114, 0.042, 0.007), (s * 0.095, 0.058, 0.0772), escuro, 0.002)
        )
        objs.append(
            A.torno(
                "Botao",
                [(0, 0), (0.0054, 0), (0.0056, 0.0014), (0.0034, 0.0028), (0, 0.0028)],
                botao,
                (s * 0.095, 0.046, 0.0806),
                n=18,
            )
        )
    if enrolada:
        for s in (-1, 1):
            for j in range(2):
                objs.append(
                    A.torno(
                        "Punho",
                        [
                            (0, -0.09),
                            (0.021, -0.09),
                            (0.024, -0.085),
                            (0.024, 0.085),
                            (0.021, 0.09),
                            (0, 0.09),
                        ],
                        pano if j == 0 else escuro,
                        (s * 0.150, -0.112 + j * 0.030, 0.094),
                        (0, 90, 0),
                        n=24,
                    )
                )
    return objs


def v_utility_down(_p):
    return camisa((0.34, 0.37, 0.21))


def v_utility_rolled(_p):
    return camisa((0.38, 0.40, 0.23), enrolada=True)


def v_vc_khaki(_p):
    return camisa((0.56, 0.47, 0.30))


def v_vc_green(_p):
    return camisa((0.24, 0.33, 0.18))


# ------------------------------------------------------------------ acessórios
def v_nada(p):
    """Sem acessório: o cabide vazio no gancho."""
    pts = [
        (-0.21, 0, 0.02),
        (-0.11, 0, 0.075),
        (-0.018, 0, 0.128),
        (0.0, 0, 0.142),
        (0.018, 0, 0.128),
        (0.11, 0, 0.075),
        (0.21, 0, 0.02),
        (0.20, 0, 0.0),
        (0.0, 0, 0.0),
        (-0.20, 0, 0.0),
        (-0.21, 0, 0.02),
    ]
    objs = [A.tubo("Cabide", pts, 0.0048, p["aco"], ordem=2)]
    gancho = [
        (0.0, 0, 0.142),
        (0.0, 0, 0.176),
        (0.021, 0, 0.205),
        (0.002, 0, 0.232),
        (-0.024, 0, 0.214),
    ]
    objs.append(A.tubo("Gancho", gancho, 0.0044, p["aco"], ordem=3))
    return objs


def v_towel(_p):
    verde = A.mat_tecido("Toalha", (0.24, 0.32, 0.17), rug=0.95, escala=2200)
    claro = A.mat_tecido("Toalha2", (0.31, 0.39, 0.22), rug=0.95, escala=2200)
    objs = [
        A.almofada("Dobra1", (0.32, 0.20, 0.034), (0, 0, 0.017), verde),
        A.almofada("Dobra2", (0.315, 0.195, 0.034), (0.002, 0.002, 0.047), claro),
        A.almofada("Dobra3", (0.31, 0.19, 0.034), (-0.002, 0, 0.077), verde),
    ]
    for i in range(30):
        x = -0.145 + i * 0.01
        for lado in (-1, 1):
            objs.append(
                A.bloco("Franja", (0.0034, 0.022, 0.0028), (x, lado * 0.106, 0.005), claro, 0)
            )
    return objs


def v_zippo(p):
    aco = A.mat("Zippo", (0.78, 0.78, 0.76), metal=1.0, rug=0.24, escala=1600, forca=0.05)
    interno = A.mat("Interno", (0.62, 0.60, 0.56), metal=1.0, rug=0.34, forca=0.0)
    objs = [A.bloco("Corpo", (0.038, 0.013, 0.036), (0, 0, 0.018), aco, 0.0022)]
    objs.append(A.bloco("Interno", (0.033, 0.0105, 0.018), (0, 0, 0.044), interno, 0.0008))
    for i in range(4):
        for j in range(2):
            furo = A.torno(
                "Furo", [(0, 0), (0.0012, 0), (0.0012, 0.0016), (0, 0.0016)], p["preto"], n=10
            )
            furo.location = Vector((-0.010 + i * 0.0066, -0.0060, 0.040 + j * 0.0066))
            furo.rotation_euler = (math.pi / 2, 0, 0)
            objs.append(furo)
    roda = A.torno(
        "Roda",
        [(0, -0.0032), (0.0044, -0.0032), (0.0044, 0.0032), (0, 0.0032)],
        p["latao"],
        (0.008, 0, 0.0555),
        (0, 90, 0),
        n=22,
        angulo=20,
    )
    objs.append(roda)
    tampa = [A.bloco("Tampa", (0.038, 0.013, 0.021), (0.019, 0, 0.0105), aco, 0.0022)]
    A.grupo(tampa, (0.019, 0, 0.038), (0, -112, 0))
    estrela = A.ligar("Estrela", A.malha_estrela(0.0105, 0.0042, 0.0006), p["latao"])
    estrela.location = (0, -0.0066, 0.018)
    estrela.rotation_euler = (math.pi / 2, 0, 0)
    return objs + tampa + [estrela]


def v_rice_tube(_p):
    pano = A.mat_tecido("Saco", (0.60, 0.54, 0.40), rug=0.96, escala=1100)
    corda = A.mat_tecido("Corda", (0.30, 0.25, 0.17), rug=0.95, escala=2600)
    pts = [
        (-0.30, 0.02, 0.04),
        (-0.20, -0.06, 0.04),
        (-0.06, -0.10, 0.04),
        (0.08, -0.08, 0.04),
        (0.21, 0.0, 0.04),
        (0.29, 0.10, 0.04),
    ]
    objs = [A.tubo("Tubo", pts, 0.040, pano, ordem=3, resolucao=14)]
    for i, q in enumerate(((-0.22, -0.045), (-0.09, -0.098), (0.05, -0.088), (0.18, -0.026))):
        anel = A.toro("Amarra", 0.041, 0.0028, corda, (q[0], q[1], 0.04), (90, 0, 20 + i * 18))
        objs.append(anel)
    for q in ((-0.30, 0.02), (0.29, 0.10)):
        objs.append(
            A.torno(
                "Ponta",
                [(0, -0.022), (0.021, -0.016), (0.029, 0.0), (0.021, 0.016), (0, 0.022)],
                pano,
                (q[0], q[1], 0.04),
                (0, 90, 0),
                n=20,
            )
        )
    alca = [
        (-0.30, 0.02, 0.06),
        (-0.27, 0.16, 0.02),
        (0.0, 0.25, 0.012),
        (0.24, 0.20, 0.02),
        (0.29, 0.10, 0.06),
    ]
    objs.append(A.tubo("Alca", alca, 0.0044, corda))
    return objs


def v_scarf(_p):
    return [A.krama((0, 0, 0), 0, 0.46, 0.30)]


def v_tire_sandals(_p):
    borracha = A.mat("Pneu", (0.055, 0.055, 0.055), rug=0.74, escala=1400, forca=0.10)
    tira = A.mat("Camara", (0.10, 0.10, 0.10), rug=0.55, forca=0.0)
    return A.sandalia((-0.015, 0.058, 0), 12, borracha, tira, 1) + A.sandalia(
        (0.018, -0.056, 0), -8, borracha, tira, -1
    )


def forma_marmita(x, y, z):
    return (x * 1.32, y, z)


def v_mess_tin(p):
    alum = A.mat("Marmita", (0.76, 0.77, 0.75), metal=1.0, rug=0.34, escala=1100, forca=0.05)
    objs = []
    for i in range(3):
        perfil = [
            (0.0, 0.0),
            (0.066, 0.0),
            (0.070, 0.004),
            (0.070, 0.050),
            (0.073, 0.053),
            (0.073, 0.057),
            (0.0, 0.057),
        ]
        objs.append(A.torno("Tigela", perfil, alum, (0, 0, i * 0.056), n=72, deforma=forma_marmita))
    tampa = [(0, 0.024), (0.040, 0.021), (0.068, 0.010), (0.075, 0.0), (0.0, 0.0)]
    objs.append(A.torno("Tampa", tampa, alum, (0, 0, 0.168), n=72, deforma=forma_marmita))
    for s in (-1, 1):
        haste = [
            (s * 0.101, 0.0, 0.012),
            (s * 0.106, 0.0, 0.10),
            (s * 0.100, 0.0, 0.196),
            (s * 0.052, 0.0, 0.226),
            (0.0, 0.0, 0.232),
        ]
        objs.append(A.tubo("Alca", haste, 0.0034, p["aco"]))
    return objs


def v_ribbon(p):
    cores = [
        (0.70, 0.10, 0.10),
        (0.90, 0.85, 0.70),
        (0.12, 0.20, 0.42),
        (0.90, 0.85, 0.70),
        (0.70, 0.10, 0.10),
    ]
    objs = []
    larguras = [0.012, 0.006, 0.020, 0.006, 0.012]
    x = -sum(larguras) / 2
    for i, (cor, w) in enumerate(zip(cores, larguras, strict=True)):
        pano = A.mat_tecido(f"Fita{i}", cor, rug=0.5, escala=2600)
        objs.append(A.bloco("Fita", (w, 0.020, 0.058), (x + w / 2, 0, 0.082), pano, 0.0004))
        x += w
    objs.append(A.bloco("Presilha", (0.062, 0.024, 0.010), (0, 0, 0.113), p["latao"], 0.002))
    objs.append(A.toro("Argola", 0.006, 0.0012, p["latao"], (0, 0, 0.047), (90, 0, 0)))
    medalha = [
        (0.0, -0.0015),
        (0.021, -0.0015),
        (0.0225, 0.0),
        (0.021, 0.0015),
        (0.0, 0.0015),
    ]
    objs.append(A.torno("Medalha", medalha, p["latao"], (0, 0, 0.022), (90, 0, 0), n=48))
    estrela = A.ligar("Estrela", A.malha_estrela(0.014, 0.0056, 0.0016), p["aco"])
    estrela.location = (0, -0.0016, 0.022)
    estrela.rotation_euler = (math.pi / 2, 0, 0)
    objs.append(estrela)
    return objs


def v_pith_helmet(p):
    fibra = A.mat_tecido("Fibra", (0.34, 0.39, 0.21), rug=0.78, escala=1700)
    perfil = [
        (0.0, 0.192),
        (0.030, 0.190),
        (0.075, 0.170),
        (0.112, 0.128),
        (0.132, 0.076),
        (0.139, 0.030),
        (0.190, -0.010),
        (0.206, -0.022),
        (0.200, -0.030),
        (0.138, -0.004),
        (0.0, -0.004),
    ]
    objs = [A.torno("Casco", perfil, fibra, (0, 0, 0.035), n=96, deforma=forma_capacete, angulo=52)]
    objs.append(
        A.torno(
            "Respiro",
            [(0.0, 0.2), (0.016, 0.198), (0.024, 0.190), (0.022, 0.184), (0, 0.184)],
            fibra,
            (0, 0, 0.035),
            n=32,
        )
    )
    for a in range(0, 360, 45):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        pts = [
            (0.024 * c, 0.024 * 1.13 * s, 0.226),
            (0.072 * c, 0.072 * 1.13 * s, 0.206),
            (0.111 * c, 0.111 * 1.13 * s, 0.165),
            (0.132 * c, 0.132 * 1.13 * s, 0.112),
            (0.140 * c, 0.140 * 1.13 * s, 0.068),
        ]
        objs.append(A.tubo("Gomo", pts, 0.0012, fibra))
    distintivo = A.torno(
        "Distintivo",
        [(0, 0), (0.019, 0), (0.020, 0.0016), (0.018, 0.0032), (0, 0.0032)],
        A.mat("Vermelho", (0.68, 0.08, 0.07), rug=0.3, clear=0.6, forca=0.0),
        (0, -0.1545, 0.112),
        (88, 0, 0),
        n=36,
    )
    estrela = A.ligar("Estrela", A.malha_estrela(0.015, 0.006, 0.0018), p["amarelo"])
    estrela.location = (0, -0.1582, 0.112)
    estrela.rotation_euler = (math.radians(88), 0, 0)
    return objs + [distintivo, estrela]


def v_jungle_hat(_p):
    pano = mat_camo(
        "Selva",
        [(0.25, 0.31, 0.16), (0.34, 0.40, 0.21), (0.18, 0.23, 0.12), (0.30, 0.27, 0.15)],
        34.0,
    )
    faixa = A.mat_tecido("FaixaChapeu", (0.17, 0.22, 0.11), escala=1500)

    def ondula(x, y, z):
        r = math.hypot(x, y)
        a = math.atan2(y, x)
        q = max(0.0, (r - 0.115) / 0.12)
        return (
            x,
            y * 1.08,
            z + q * (0.016 * math.sin(a * 3 + 0.8) + 0.011 * math.sin(a * 7)) - q * q * 0.024,
        )

    perfil = [
        (0.0, 0.122),
        (0.052, 0.126),
        (0.097, 0.114),
        (0.116, 0.078),
        (0.122, 0.036),
        (0.128, 0.018),
        (0.176, 0.006),
        (0.226, -0.002),
        (0.238, -0.004),
        (0.236, -0.010),
        (0.124, 0.006),
        (0.0, 0.006),
    ]
    objs = [A.torno("Chapeu", perfil, pano, (0, 0, 0.03), n=120, deforma=ondula, angulo=70)]
    objs.append(
        A.torno(
            "FaixaC",
            [(0.1205, 0.040), (0.1265, 0.040), (0.1275, 0.070), (0.1185, 0.070)],
            faixa,
            (0, 0, 0.03),
            n=96,
            deforma=lambda x, y, z: (x, y * 1.08, z),
        )
    )
    return objs


# ------------------------------------------------------------------ vantagens
def v_perk_speed(p):
    """Par de botas de selva."""
    couro = A.mat("Couro", (0.12, 0.09, 0.07), rug=0.42, clear=0.25, escala=1400, forca=0.05)
    lona = A.mat_tecido("Lona", (0.28, 0.32, 0.17), escala=1500)
    objs = []

    def bota(pos, rz):
        cano = [
            (-0.100, 0.022),
            (0.012, 0.022),
            (0.110, 0.024),
            (0.158, 0.040),
            (0.160, 0.070),
            (0.112, 0.098),
            (0.060, 0.120),
            (0.040, 0.235),
            (-0.082, 0.235),
            (-0.104, 0.120),
        ]
        pecas = [
            A.prisma("Cano", cano, 0.096, lona, (0, 0.048, 0), (90, 0, 0), 0.012),
            A.bloco("Sola", (0.282, 0.104, 0.024), (0.028, 0, 0.012), p["borr"], 0.005),
            A.bloco("Salto", (0.092, 0.100, 0.018), (-0.058, 0, 0.004), p["borr"], 0.003),
            A.prisma(
                "Bico",
                [(0.05, 0.023), (0.162, 0.026), (0.167, 0.066), (0.112, 0.102), (0.05, 0.106)],
                0.102,
                couro,
                (0, 0.051, 0),
                (90, 0, 0),
                0.012,
            ),
            A.prisma(
                "Calcanhar",
                [(-0.105, 0.023), (-0.04, 0.023), (-0.05, 0.11), (-0.108, 0.11)],
                0.102,
                couro,
                (0, 0.051, 0),
                (90, 0, 0),
                0.010,
            ),
        ]
        for i in range(6):
            z = 0.118 + i * 0.020
            x = 0.056 - i * 0.0026
            pecas.append(A.bloco("Cadarco", (0.007, 0.078, 0.0042), (x, 0, z), p["preto"], 0.001))
        return A.grupo(pecas, pos, (0, 0, rz))

    objs += bota((-0.006, 0.075, 0), 12)
    objs += bota((0.012, -0.075, 0), -6)
    return objs


def colete(p, pos=(0, 0, 0), rot=(0, 0, 0)):
    """Colete à prova de estilhaços, com os gomos costurados."""
    pano = A.mat_tecido("Colete", (0.30, 0.34, 0.19), escala=1400)
    gomo = A.mat_tecido("Gomo", (0.35, 0.39, 0.22), escala=1400)
    objs = [
        A.almofada("Costas", (0.40, 0.46, 0.030), (0, 0, 0.015), pano),
        A.prisma(
            "Gola",
            [
                (-0.11, 0.21),
                (-0.06, 0.26),
                (0.06, 0.26),
                (0.11, 0.21),
                (0.075, 0.175),
                (-0.075, 0.175),
            ],
            0.018,
            pano,
            (0, 0, 0.022),
            (0, 0, 0),
            0.005,
        ),
    ]
    for lado in (-1, 1):
        for i in range(5):
            for j in range(2):
                objs.append(
                    A.almofada(
                        "Gomo",
                        (0.078, 0.070, 0.022),
                        (lado * (0.056 + j * 0.086), -0.160 + i * 0.078, 0.037),
                        gomo,
                    )
                )
        for i in range(4):
            objs.append(
                A.torno(
                    "Botao",
                    [(0, 0), (0.0056, 0), (0.0058, 0.002), (0.003, 0.0034), (0, 0.0034)],
                    p["preto"],
                    (lado * 0.010, -0.14 + i * 0.094, 0.030),
                    n=16,
                )
            )
    return A.grupo(objs, pos, rot)


def v_perk_health(p):
    return colete(p)


def luneta(p, pos=(0, 0, 0), rot=(0, 0, 0)):
    tubo = [
        (0.0, -0.20),
        (0.030, -0.20),
        (0.031, -0.186),
        (0.023, -0.150),
        (0.0165, -0.10),
        (0.0165, 0.070),
        (0.024, 0.118),
        (0.033, 0.150),
        (0.0345, 0.205),
        (0.031, 0.21),
        (0.0, 0.21),
    ]
    objs = [A.torno("Luneta", tubo, p["preto"], (0, 0, 0), (0, 90, 0), n=56, angulo=30)]
    for x, rz in ((0.0, 0.0), (0.0, 90.0)):
        torre = A.torno(
            "Torre",
            [(0, 0.0), (0.0130, 0.0), (0.0135, 0.018), (0.012, 0.022), (0, 0.022)],
            p["aco"],
            (x, 0, 0.012) if rz == 0 else (x, -0.012, 0),
            (0, 0, 0) if rz == 0 else (90, 0, 0),
            n=24,
            angulo=24,
        )
        objs.append(torre)
    vidro = A.mat_vidro("Lente")
    objs.append(
        A.torno(
            "Lente",
            [(0, 0), (0.030, 0), (0.030, 0.001), (0, 0.001)],
            vidro,
            (0.2112, 0, 0),
            (0, 90, 0),
            n=36,
        )
    )
    for x in (-0.06, 0.05):
        objs.append(A.bloco("Anel", (0.016, 0.040, 0.041), (x, 0, -0.002), p["aco"], 0.003))
        objs.append(A.bloco("Base", (0.03, 0.030, 0.010), (x, 0, -0.026), p["preto"], 0.002))
    return A.grupo(objs, pos, rot)


def v_perk_breath(p):
    return luneta(p)


def bolsas(p, pos=(0, 0, 0), rot=(0, 0, 0)):
    lona = A.mat_tecido("LonaBolsa", (0.31, 0.35, 0.19), escala=1500)
    aba = A.mat_tecido("AbaBolsa", (0.26, 0.30, 0.16), escala=1500)
    objs = [A.bloco("Cinto", (0.52, 0.056, 0.010), (0, 0, 0.005), lona, 0.002)]
    objs.append(A.bloco("Fivela", (0.056, 0.066, 0.016), (0, 0, 0.012), p["latao"], 0.003))
    for s in (-1, 1):
        x = s * 0.135
        objs.append(A.almofada("Bolsa", (0.118, 0.165, 0.060), (x, -0.058, 0.037), lona))
        objs.append(A.almofada("Aba", (0.126, 0.082, 0.024), (x, -0.008, 0.070), aba))
        objs.append(
            A.torno(
                "Pino",
                [(0, 0), (0.0058, 0), (0.006, 0.002), (0.003, 0.0036), (0, 0.0036)],
                p["latao"],
                (x, -0.034, 0.082),
                n=18,
            )
        )
    return A.grupo(objs, pos, rot)


def v_perk_pockets(p):
    return bolsas(p)


def v_perk_all(p):
    """As vantagens juntas: colete, botas, bolsas e luneta num só quadro."""
    objs = colete(p, (-0.02, 0.05, 0.0), (0, 0, 6))
    objs += bolsas(p, (0.08, -0.31, 0.0), (0, 0, -7))
    objs += luneta(p, (0.20, 0.07, 0.075), (0, 0, 74))
    return objs


# ------------------------------------------------------------------ camuflagens
def cena_camo(textura):
    """O soldado de bloco com os feixes do jogo (a mesma malha do `tools/ghillie.py`)."""
    import ghillie as G

    imagem = bpy.data.images.load(str(GHILLIE / textura))
    imagem.alpha_mode = "STRAIGHT"
    folhas = G._material(bpy, "Folhas", imagem)
    farda = A.mat_tecido("Farda", (0.20, 0.23, 0.13), escala=320)
    pele = A.mat("Pele", (0.77, 0.58, 0.44), rug=0.55, forca=0.0)
    objs = []
    malhas = G.malhas()
    for parte in G.PARTES:
        o = G._objeto(bpy, "Ghillie_" + parte.nome, malhas[parte.nome], folhas)
        o.location = G._bl(parte.centro)
        objs.append(o)
        objs.append(
            G._caixa(
                bpy,
                "Corpo_" + parte.nome,
                parte.ref,
                parte.centro,
                pele if parte.nome == "Head" else farda,
            )
        )
    for nome, tam, centro in G.MAOS_PES:
        objs.append(G._caixa(bpy, "Corpo_" + nome, tam, centro, pele if "Hand" in nome else farda))
    return objs


def v_camo_rice(_p):
    return cena_camo("ghillie2_arroz.png")


def v_camo_jungle(_p):
    return cena_camo("ghillie2_selva.png")


def v_camo_bamboo(_p):
    return cena_camo("ghillie2_bambu.png")


# id: função e direção da câmera (da cena para a câmera)
ITENS = {
    "us_cover_leaf": (v_cover_leaf, (0.62, -1.0, 0.46)),
    "us_cover_cloud": (v_cover_cloud, (0.62, -1.0, 0.46)),
    "us_cover_faded": (v_cover_faded, (0.62, -1.0, 0.46)),
    "us_repellent_band": (v_repellent_band, (0.55, -1.0, 0.34)),
    "us_cigarette_band": (v_cigarette_band, (-0.45, -1.0, 0.34)),
    "us_utility_down": (v_utility_down, (0.28, -0.72, 1.0)),
    "us_utility_rolled": (v_utility_rolled, (0.28, -0.72, 1.0)),
    "vc_khaki": (v_vc_khaki, (0.28, -0.72, 1.0)),
    "vc_green": (v_vc_green, (0.28, -0.72, 1.0)),
    "nada": (v_nada, (0.18, -1.0, 0.18)),
    "us_towel": (v_towel, (0.45, -1.0, 0.72)),
    "us_zippo": (v_zippo, (0.52, -1.0, 0.42)),
    "vc_rice_tube": (v_rice_tube, (0.20, -0.72, 1.0)),
    "vc_scarf": (v_scarf, (0.36, -0.80, 1.0)),
    "vc_tire_sandals": (v_tire_sandals, (0.40, -0.72, 1.0)),
    "vc_mess_tin": (v_mess_tin, (0.55, -1.0, 0.44)),
    "ribbon": (v_ribbon, (0.30, -1.0, 0.18)),
    "vc_pith_helmet": (v_pith_helmet, (0.42, -1.0, 0.40)),
    "vc_jungle_hat": (v_jungle_hat, (0.52, -1.0, 0.50)),
    "perk_speed": (v_perk_speed, (0.72, -1.0, 0.46)),
    "perk_health": (v_perk_health, (0.20, -0.62, 1.0)),
    "perk_breath": (v_perk_breath, (0.42, -1.0, 0.32)),
    "perk_pockets": (v_perk_pockets, (0.25, -0.66, 1.0)),
    "perk_all": (v_perk_all, (0.22, -0.66, 1.0)),
    "camo_rice": (v_camo_rice, (-0.46, 1.0, 0.16)),
    "camo_jungle": (v_camo_jungle, (-0.46, 1.0, 0.16)),
    "camo_bamboo": (v_camo_bamboo, (-0.46, 1.0, 0.16)),
}


def render(chave, amostras, teste, saida):
    C.cena_vazia()
    cena = bpy.context.scene
    lado = 256 if teste else 512
    L.configurar(cena, lado, lado, amostras)
    A.acabar(cena)
    cena.cycles.transparent_max_bounces = 128
    A.mundo_estudio(cena)
    fn, direcao = ITENS[chave]
    objs = fn(A.paleta())
    bpy.context.view_layer.update()
    vis = [o for o in objs if o.type in ("MESH", "CURVE", "FONT")]
    cam, centro, raio = L.camera_para(vis, lado, lado, direcao=direcao, lente=85.0, folga=1.16)
    cam.data.clip_start = 0.005
    A.luzes_catalogo(centro, raio * 1.05)
    lo, _ = L.caixa_mundo(vis)
    bpy.ops.mesh.primitive_plane_add(size=40 * raio, location=(centro.x, centro.y, float(lo.z)))
    chao = bpy.context.active_object
    chao.name = "Sombra"
    chao.is_shadow_catcher = True
    chao.visible_glossy = False
    chao.visible_shadow = False
    saida.mkdir(parents=True, exist_ok=True)
    arquivo = saida / f"{chave}.png"
    cena.render.filepath = str(arquivo)
    bpy.ops.render.render(write_still=True)
    A.apagar_bordas(arquivo, 0.04, 0.04)
    C.log("ok visual", chave)


def principal():
    args = C.argumentos()
    if not args:
        raise SystemExit(
            "uso: visuais_catalogo.py -- todas|<ids...> [--teste] [--amostras N] [--saida PASTA]"
        )
    teste = "--teste" in args
    amostras = (
        int(args[args.index("--amostras") + 1]) if "--amostras" in args else (20 if teste else 64)
    )
    saida = (
        Path(args[args.index("--saida") + 1])
        if "--saida" in args
        else (Path(tempfile.gettempdir()) / "vt65_visuais" if teste else DESTINO)
    )
    pulos = {args.index(k) + 1 for k in ("--amostras", "--saida") if k in args}
    ids = [a for i, a in enumerate(args) if i not in pulos and not a.startswith("--")]
    if ids == ["todas"]:
        ids = list(ITENS)
    t0 = time.time()
    for k in ids:
        if k not in ITENS:
            C.log("sem receita:", k)
            continue
        t1 = time.time()
        render(k, amostras, teste, saida)
        C.log("tempo", k, round(time.time() - t1, 1), "s")
    C.log("total", round(time.time() - t0, 1), "s")


if __name__ == "__main__":
    principal()
