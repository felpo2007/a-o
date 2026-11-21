"""Imagens dos emblemas (D-218; dono, 21/11: "faça imagens sensacionais para os emblemas").

Cada emblema é uma insígnia de metal e esmalte modelada aqui (nada de terceiro), em Cycles:
- a chapa muda com a raridade: bronze redondo (comum), aço em escudo (incomum), prata em hexágono
  com rebites (raro), ouro em estrela de oito pontas (épico) e ouro em sol de raios com pedras
  (lendário);
- o esmalte do meio usa as duas cores do item (Shared/Cosmeticos);
- o símbolo de cada um (águia, dragão, lótus, bússola...) é desenhado por pontos e sai em relevo.

Saídas: `assets/ui/emblemas/<id>.png`, 512 x 512, RGBA.

Uso (sempre na CPU: a GPU de 2 GB é do Studio):
    $env:VT65_CPU = "1"; $env:VT65_THREADS = "4"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/emblemas.py -- todos [--amostras 48] [--teste]
    ... -- emb_dragao emb_lotus   (só esses)
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import loja as L  # noqa: E402

SAIDA = C.RAIZ / "assets" / "ui" / "emblemas"
FONTE = Path("C:/Windows/Fonts/STENCIL.TTF")
FONTE_RESERVA = Path("C:/Windows/Fonts/arialbd.ttf")

# os dois que não estão no Shared/Cosmeticos (Shared/Medalhas)
EXTRAS = {
    "emb_padrao": ("raro", (46, 58, 40), (226, 188, 96)),
    "emb_top10": ("epico", (70, 34, 26), (236, 202, 116)),
}


def log(*a):
    print("[VT65]", *a, flush=True)


def catalogo() -> dict:
    """Raridade e as duas cores de cada emblema, lidas do Shared/Cosmeticos."""
    txt = (C.RAIZ / "src/ReplicatedStorage/Shared/Cosmeticos.luau").read_text("utf-8")
    pad = re.compile(
        r'id = "(emb_[^"]+)".*?raridade = "([^"]+)".*?'
        r"cor = \{\s*(\d+),\s*(\d+),\s*(\d+)\s*\}.*?cor2 = \{\s*(\d+),\s*(\d+),\s*(\d+)\s*\}",
        re.S,
    )
    out = dict(EXTRAS)
    for m in pad.finditer(txt):
        g = m.groups()
        out[g[0]] = (g[1], tuple(int(x) for x in g[2:5]), tuple(int(x) for x in g[5:8]))
    return out


# ------------------------------------------------------------------ geometria 2D
def rad(a):
    return math.radians(a)


def arco(cx, cy, r, a0, a1, n=24):
    return [
        (
            cx + r * math.cos(rad(a0 + (a1 - a0) * i / n)),
            cy + r * math.sin(rad(a0 + (a1 - a0) * i / n)),
        )
        for i in range(n + 1)
    ]


def circulo(cx=0.0, cy=0.0, r=1.0, n=72):
    return arco(cx, cy, r, 0, 360 * (n - 1) / n, n - 1)


def elipse(cx, cy, rx, ry, rot=0.0, n=28):
    c, s = math.cos(rad(rot)), math.sin(rad(rot))
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cx + x * c - y * s, cy + x * s + y * c))
    return out


def estrela(n, R, r, rot=90.0, cx=0.0, cy=0.0):
    out = []
    for i in range(n * 2):
        q = R if i % 2 == 0 else r
        a = rad(rot + i * 180 / n)
        out.append((cx + q * math.cos(a), cy + q * math.sin(a)))
    return out


def regular(n, r, rot=90.0):
    return [
        (r * math.cos(rad(rot + i * 360 / n)), r * math.sin(rad(rot + i * 360 / n)))
        for i in range(n)
    ]


def mir(meio):
    """Fecha um contorno simétrico: a metade direita, de cima para baixo."""
    return list(meio) + [(-x, y) for x, y in reversed(meio) if abs(x) > 1e-6]


def gira(pts, graus, cx=0.0, cy=0.0):
    c, s = math.cos(rad(graus)), math.sin(rad(graus))
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def move(pts, dx, dy):
    return [(x + dx, y + dy) for x, y in pts]


def espelha(pts):
    return [(-x, y) for x, y in reversed(pts)]


def fita(linha, larguras):
    """Fita de largura variável ao longo de uma linha (corpo de cobra, dragão, caule)."""
    n = len(linha)
    if not isinstance(larguras, (list, tuple)):
        larguras = [larguras] * n
    esq, dir_ = [], []
    for i, (x, y) in enumerate(linha):
        ax, ay = linha[max(i - 1, 0)]
        bx, by = linha[min(i + 1, n - 1)]
        dx, dy = bx - ax, by - ay
        q = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / q, dx / q
        w = larguras[i] / 2
        esq.append((x + nx * w, y + ny * w))
        dir_.append((x - nx * w, y - ny * w))
    return esq + list(reversed(dir_))


def curva_s(p0, p1, amp, voltas, n=48):
    """Linha ondulada de p0 a p1 (o corpo da cobra e do dragão)."""
    out = []
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    q = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / q, dx / q
    for i in range(n + 1):
        u = i / n
        o = amp * math.sin(u * voltas * 2 * math.pi)
        out.append((p0[0] + dx * u + nx * o, p0[1] + dy * u + ny * o))
    return out


def pena(cx, cy, comp, larg, rot):
    """Pena: gota comprida com a ponta na direção `rot`."""
    meio = []
    for i in range(13):
        u = i / 12
        w = larg * math.sin(math.pi * u**0.8) * (1 - 0.25 * u)
        meio.append((comp * u, w))
    pts = meio + [(x, -y) for x, y in reversed(meio[1:-1])]
    return move(gira(pts, rot), cx, cy)


def engrenagem(dentes, R, r, furo=None, inclina=0.0):
    pts = []
    passo = 360 / dentes
    for i in range(dentes):
        a = i * passo
        pts += [
            (r * math.cos(rad(a - passo * 0.30)), r * math.sin(rad(a - passo * 0.30))),
            (
                R * math.cos(rad(a - passo * 0.17 + inclina)),
                R * math.sin(rad(a - passo * 0.17 + inclina)),
            ),
            (
                R * math.cos(rad(a + passo * 0.17 + inclina)),
                R * math.sin(rad(a + passo * 0.17 + inclina)),
            ),
            (r * math.cos(rad(a + passo * 0.30)), r * math.sin(rad(a + passo * 0.30))),
        ]
    return [pts] + ([circulo(0, 0, furo, 40)] if furo else [])


def louro(r=0.62, folhas=9):
    """Coroa de louros: folhas nos dois lados, abertas em cima."""
    out = []
    for lado in (1, -1):
        for i in range(folhas):
            a = -72 + i * (128 / (folhas - 1))
            x, y = r * math.cos(rad(a)), r * math.sin(rad(a))
            for desvio in (32, -32):
                f = pena(x, y, 0.17, 0.05, a + 90 + desvio)
                out.append(espelha(f) if lado < 0 else f)
    return out


# ------------------------------------------------------------------ os símbolos
# Cada um devolve camadas (polígonos, material, altura): "m" = metal do símbolo, "c" = cor 2 em
# esmalte, "e" = escuro, "b" = claro. As coordenadas ficam dentro do raio ~0,62.
def s_arrozais():
    cam = []
    for dx, ang, k in ((-0.26, 14, 0.9), (0.0, 0, 1.0), (0.26, -14, 0.9)):
        linha = [
            (dx + ang * -0.008 * (i / 16) ** 2 * 3, -0.56 + 1.0 * k * i / 16) for i in range(17)
        ]
        cam.append(([fita(linha, [0.045 - 0.022 * i / 16 for i in range(17)])], "m", 0.0))
        grãos = []
        for j in range(7):
            u = 0.5 + j * 0.075
            i = int(u * 16)
            x, y = linha[i]
            for lado in (1, -1):
                grãos.append(elipse(x + lado * 0.058, y, 0.05, 0.026, lado * 50 + ang, 16))
        grãos.append(elipse(linha[-1][0], linha[-1][1] + 0.03, 0.026, 0.05, ang, 16))
        cam.append((grãos, "c", 0.012))
    return cam


def s_serraria():
    return [
        (engrenagem(16, 0.60, 0.47, 0.13, inclina=7), "m", 0.0),
        ([circulo(0, 0, 0.30, 48), circulo(0, 0, 0.24, 48)], "c", 0.018),
    ]


def s_ponte():
    deck = [(-0.62, 0.10), (0.62, 0.10), (0.62, 0.0), (-0.62, 0.0)]
    arc = arco(0, -0.46, 0.5, 15, 165, 28) + list(reversed(arco(0, -0.46, 0.38, 15, 165, 28)))
    pilares = [
        [(x - 0.035, 0.0), (x + 0.035, 0.0), (x + 0.035, -0.38), (x - 0.035, -0.38)]
        for x in (-0.5, -0.25, 0.25, 0.5)
    ]
    onda = [
        fita(
            [(-0.6 + 1.2 * i / 40, -0.46 + 0.03 * math.sin(i * 0.9) + dy) for i in range(41)], 0.03
        )
        for dy in (0.0, -0.09)
    ]
    return [([deck, arc] + pilares, "m", 0.0), (onda, "c", 0.01)]


def s_engenho():
    miolo = [circulo(0, 0, 0.22, 40), circulo(0, 0, 0.1, 28)]
    return [
        (engrenagem(10, 0.60, 0.44, 0.27), "m", 0.0),
        (miolo, "c", 0.018),
    ]


def s_vila():
    teto = [(0.0, 0.54), (0.60, 0.04), (0.46, 0.0), (0.0, 0.34), (-0.46, 0.0), (-0.60, 0.04)]
    casa = [(-0.40, 0.04), (0.0, 0.34), (0.40, 0.04), (0.40, -0.48), (-0.40, -0.48)]
    porta = [(-0.11, -0.48), (0.11, -0.48), (0.11, -0.12), (-0.11, -0.12)]
    jan = [
        [(x - 0.07, -0.05), (x + 0.07, -0.05), (x + 0.07, -0.2), (x - 0.07, -0.2)]
        for x in (-0.25, 0.25)
    ]
    return [([casa], "c", 0.0), ([teto], "m", 0.02), ([porta] + jan, "e", 0.012)]


def s_starlite():
    raios = [gira(estrela(4, 0.34, 0.06, 90), 45)]
    return [
        (raios, "c", 0.0),
        ([estrela(4, 0.64, 0.11, 90)], "m", 0.016),
        ([circulo(0, 0, 0.09, 24)], "b", 0.03),
    ]


def s_chulai():
    haste = [(-0.04, 0.34), (0.04, 0.34), (0.04, -0.44), (-0.04, -0.44)]
    barra = [(-0.24, 0.24), (0.24, 0.24), (0.24, 0.17), (-0.24, 0.17)]
    aro = [circulo(0, 0.45, 0.12, 28), circulo(0, 0.45, 0.06, 20)]
    bracos = arco(0, -0.05, 0.47, 200, 340, 28) + list(reversed(arco(0, -0.05, 0.39, 204, 336, 28)))
    pontas = [
        [(-0.5, -0.03), (-0.34, -0.2), (-0.53, -0.26)],
        [(0.5, -0.03), (0.34, -0.2), (0.53, -0.26)],
    ]
    return [([haste, barra, bracos] + pontas, "m", 0.0), (aro, "c", 0.012)]


def s_operacao():
    aneis = [circulo(0, 0, 0.56, 56), circulo(0, 0, 0.48, 56)]
    meio = [circulo(0, 0, 0.25, 40), circulo(0, 0, 0.2, 40)]
    cruz = []
    for a in (0, 90, 180, 270):
        cruz.append(gira([(0.12, -0.025), (0.64, -0.025), (0.64, 0.025), (0.12, 0.025)], a))
    return [
        (aneis, "m", 0.0),
        (meio, "c", 0.008),
        (cruz, "b", 0.018),
        ([circulo(0, 0, 0.05, 16)], "c", 0.02),
    ]


def s_arquivo():
    folha = [(-0.38, 0.54), (0.20, 0.54), (0.40, 0.34), (0.40, -0.54), (-0.38, -0.54)]
    dobra = [(0.20, 0.54), (0.40, 0.34), (0.20, 0.34)]
    linhas = [
        [(-0.26, y), (0.28, y), (0.28, y - 0.05), (-0.26, y - 0.05)]
        for y in (0.2, 0.05, -0.1, -0.25)
    ]
    carimbo = [circulo(0.1, -0.33, 0.13, 28), circulo(0.1, -0.33, 0.095, 28)]
    return [([folha], "b", 0.0), ([dobra], "m", 0.012), (linhas, "e", 0.01), (carimbo, "c", 0.014)]


def asas(n, comp0, passo, abre0, abre1, base=(0.08, 0.1), largura=0.075):
    out = []
    for i in range(n):
        u = i / (n - 1)
        a = abre0 + (abre1 - abre0) * u
        c = comp0 - passo * i
        p = pena(base[0] + 0.03 * i, base[1] - 0.045 * i, c, largura, a)
        out.append(p)
        out.append(espelha(p))
    return out


def s_aguia():
    corpo = mir(
        [(0.0, 0.30), (0.09, 0.20), (0.11, -0.02), (0.07, -0.26), (0.13, -0.46), (0.0, -0.38)]
    )
    cabeca = mir([(0.0, 0.50), (0.07, 0.46), (0.09, 0.34), (0.05, 0.26), (0.0, 0.24)])
    bico = [(0.05, 0.46), (0.19, 0.40), (0.07, 0.36)]
    return [
        (asas(7, 0.58, 0.05, 28, -38), "m", 0.0),
        ([corpo], "c", 0.016),
        ([cabeca], "b", 0.024),
        ([bico], "c", 0.03),
        ([circulo(0.035, 0.42, 0.016, 10)], "e", 0.036),
    ]


def s_tigre():
    cara = mir(
        [
            (0.0, 0.40),
            (0.17, 0.42),
            (0.32, 0.60),
            (0.44, 0.40),
            (0.48, 0.12),
            (0.42, -0.16),
            (0.26, -0.38),
            (0.12, -0.52),
            (0.0, -0.56),
        ]
    )
    listras = []
    for lado in (1, -1):
        for y, x0, x1 in ((0.20, 0.47, 0.25), (0.04, 0.47, 0.27), (-0.13, 0.42, 0.25)):
            p = [(x0, y + 0.035), (x1, y - 0.015), (x0 - 0.03, y - 0.05)]
            listras.append(p if lado > 0 else espelha(p))
    testa = [[(-0.04, 0.38), (0.04, 0.38), (0.02, 0.18), (-0.02, 0.18)]]
    for lado in (1, -1):
        p = [(0.05, 0.36), (0.16, 0.32), (0.07, 0.22)]
        testa.append(p if lado > 0 else espelha(p))
    olhos = []
    for lado in (1, -1):
        p = [(0.10, 0.10), (0.30, 0.17), (0.24, 0.04), (0.13, 0.03)]
        olhos.append(p if lado > 0 else espelha(p))
    nariz = mir([(0.0, -0.10), (0.09, -0.10), (0.04, -0.20), (0.0, -0.24)])
    boca = [
        fita([(-0.15, -0.36), (-0.07, -0.33), (0.0, -0.24), (0.07, -0.33), (0.15, -0.36)], 0.022)
    ]
    return [
        ([cara], "m", 0.0),
        (listras + testa, "e", 0.016),
        (olhos, "c", 0.018),
        ([nariz], "e", 0.02),
        (boca, "e", 0.018),
    ]


def s_dragao():
    linha = curva_s((-0.50, -0.50), (0.28, 0.36), 0.19, 1.25, 60)
    w = [0.05 + 0.13 * math.sin(math.pi * min(1, i / 60 + 0.1)) for i in range(61)]
    corpo = fita(linha, w)
    espinhos = []
    for i in range(6, 56, 5):
        x, y = linha[i]
        ax, ay = linha[i + 1]
        dx, dy = ax - x, ay - y
        q = math.hypot(dx, dy) or 1
        nx, ny = -dy / q, dx / q
        h = w[i] / 2
        espinhos.append(
            [
                (x + nx * h - dx * 1.6, y + ny * h - dy * 1.6),
                (x + nx * (h + 0.085) + dx, y + ny * (h + 0.085) + dy),
                (x + nx * h + dx * 1.6, y + ny * h + dy * 1.6),
            ]
        )
    cabeca = [
        (0.15, 0.30),
        (0.30, 0.48),
        (0.33, 0.62),
        (0.40, 0.48),
        (0.56, 0.42),
        (0.62, 0.30),
        (0.48, 0.28),
        (0.56, 0.17),
        (0.40, 0.18),
        (0.28, 0.20),
    ]
    fogo = [
        pena(0.60, 0.22, 0.16, 0.035, -38),
        pena(0.60, 0.25, 0.20, 0.04, -14),
        pena(0.60, 0.28, 0.15, 0.03, 10),
    ]
    cauda = [(-0.50, -0.50), (-0.62, -0.42), (-0.60, -0.58), (-0.46, -0.60)]
    return [
        ([corpo, cauda], "m", 0.0),
        (espinhos, "c", 0.006),
        ([cabeca], "m", 0.016),
        (fogo, "c", 0.02),
        ([circulo(0.40, 0.38, 0.03, 12)], "b", 0.03),
    ]


def s_lotus():
    tras = [pena(0, -0.26, 0.74, 0.14, 90 + a) for a in (-62, -34, 0, 34, 62)]
    frente = [pena(0, -0.3, 0.52, 0.12, 90 + a) for a in (-84, -50, -20, 20, 50, 84)]
    agua = [fita([(-0.46 + 0.92 * i / 30, -0.46 + 0.02 * math.sin(i)) for i in range(31)], 0.03)]
    return [
        (tras, "c", 0.0),
        (frente, "m", 0.018),
        ([circulo(0, -0.24, 0.07, 20)], "b", 0.03),
        (agua, "c", 0.01),
    ]


def s_raio():
    bolt = [
        (0.14, 0.64),
        (-0.34, 0.02),
        (-0.04, 0.02),
        (-0.20, -0.64),
        (0.36, 0.12),
        (0.05, 0.12),
        (0.32, 0.64),
    ]
    return [
        ([estrela(12, 0.6, 0.46, 90)], "c", 0.0),
        ([bolt], "m", 0.022),
    ]


def s_fenix():
    corpo = mir([(0.0, 0.34), (0.08, 0.22), (0.10, 0.0), (0.05, -0.2), (0.0, -0.28)])
    cabeca = mir([(0.0, 0.52), (0.06, 0.46), (0.07, 0.34), (0.0, 0.28)])
    crista = [pena(0, 0.48, 0.16, 0.022, 90 + a) for a in (-30, 0, 30)]
    bico = [(0.04, 0.47), (0.15, 0.42), (0.05, 0.39)]
    cauda = [pena(0, -0.22, 0.42 - abs(a) * 0.002, 0.05, -90 + a) for a in (-34, -17, 0, 17, 34)]
    return [
        (asas(7, 0.60, 0.05, 58, -6, base=(0.07, 0.16), largura=0.07), "c", 0.0),
        (cauda, "m", 0.008),
        ([corpo], "m", 0.016),
        (crista, "c", 0.02),
        ([cabeca], "b", 0.024),
        ([bico], "c", 0.03),
    ]


def s_lua():
    disco = [circulo(0, 0, 0.5, 56)]
    crateras = [
        circulo(cx, cy, r, 20)
        for cx, cy, r in (
            (-0.16, 0.18, 0.12),
            (0.2, 0.08, 0.08),
            (-0.04, -0.2, 0.15),
            (0.26, -0.24, 0.06),
            (-0.32, -0.12, 0.05),
            (0.08, 0.34, 0.05),
        )
    ]
    bril = [
        estrela(4, 0.09, 0.02, 90, x, y)
        for x, y in ((-0.56, 0.42), (0.54, 0.46), (0.58, -0.32), (-0.52, -0.44))
    ]
    return [(disco, "m", 0.0), (crateras, "e", 0.012), (bril, "b", 0.008)]


def s_aurora():
    sol = [arco(0, -0.22, 0.32, 0, 180, 32)]
    raios = []
    for a in range(0, 181, 20):
        comp = 0.84 if a % 40 == 20 else 0.68
        raios.append(
            gira([(0.38, -0.022), (comp, -0.006), (comp, 0.006), (0.38, 0.022)], a, 0, -0.22)
        )
    hor = [[(-0.62, -0.22), (0.62, -0.22), (0.62, -0.28), (-0.62, -0.28)]]
    mar = [
        [
            (-0.46 + k * 0.1, y),
            (0.46 - k * 0.1, y),
            (0.44 - k * 0.1, y - 0.035),
            (-0.44 + k * 0.1, y - 0.035),
        ]
        for k, y in ((0, -0.34), (1, -0.43), (2, -0.52))
    ]
    return [(raios, "c", 0.0), (sol, "m", 0.014), (hor, "b", 0.02), (mar, "c", 0.008)]


def s_cobra():
    linha = curva_s((-0.40, -0.56), (0.16, 0.34), 0.24, 1.5, 60)
    w = [0.022 + 0.095 * min(1, i / 16) for i in range(61)]
    corpo = fita(linha, w)
    manchas = []
    for i in range(10, 58, 6):
        x, y = linha[i]
        manchas.append(elipse(x, y, 0.028, 0.028, 0, 10))
    cabeca = [(0.09, 0.30), (0.22, 0.34), (0.40, 0.46), (0.42, 0.53), (0.26, 0.54), (0.10, 0.44)]
    lingua = [
        fita([(0.41, 0.50), (0.52, 0.53), (0.58, 0.60)], 0.016),
        fita([(0.52, 0.53), (0.61, 0.52)], 0.014),
    ]
    return [
        ([corpo], "m", 0.0),
        (manchas, "c", 0.012),
        ([cabeca], "m", 0.014),
        (lingua, "c", 0.008),
        ([circulo(0.28, 0.46, 0.022, 10)], "e", 0.024),
    ]


def s_as():
    lobos = [
        (0.0, 0.60),
        (0.14, 0.42),
        (0.34, 0.24),
        (0.47, 0.02),
        (0.42, -0.16),
        (0.26, -0.24),
        (0.10, -0.18),
        (0.05, -0.12),
        (0.10, -0.40),
        (0.20, -0.52),
        (0.0, -0.52),
    ]
    return [
        ([mir(lobos)], "m", 0.0),
        ([estrela(4, 0.14, 0.03, 90, 0, 0.1)], "c", 0.02),
    ]


def s_lobo():
    cara = mir(
        [
            (0.0, 0.28),
            (0.10, 0.32),
            (0.22, 0.64),
            (0.36, 0.28),
            (0.48, 0.06),
            (0.40, -0.04),
            (0.46, -0.20),
            (0.30, -0.22),
            (0.26, -0.38),
            (0.12, -0.44),
            (0.07, -0.60),
            (0.0, -0.62),
        ]
    )
    orelhas = []
    for lado in (1, -1):
        p = [(0.15, 0.32), (0.22, 0.52), (0.30, 0.28)]
        orelhas.append(p if lado > 0 else espelha(p))
    focinho = mir([(0.0, -0.02), (0.08, -0.06), (0.16, -0.36), (0.07, -0.52), (0.0, -0.54)])
    olhos = []
    for lado in (1, -1):
        p = [(0.09, 0.06), (0.27, 0.15), (0.21, 0.01)]
        olhos.append(p if lado > 0 else espelha(p))
    nariz = mir([(0.0, -0.40), (0.07, -0.40), (0.03, -0.50), (0.0, -0.52)])
    return [
        ([cara], "m", 0.0),
        (orelhas, "e", 0.012),
        ([focinho], "b", 0.01),
        (olhos, "c", 0.02),
        ([nariz], "e", 0.022),
    ]


def s_trovao():
    nuvem = [
        circulo(cx, cy, r, 28)
        for cx, cy, r in (
            (-0.27, 0.16, 0.2),
            (0.0, 0.3, 0.27),
            (0.28, 0.16, 0.21),
            (0.05, 0.08, 0.26),
        )
    ]
    base = [[(-0.42, 0.14), (0.45, 0.14), (0.42, -0.02), (-0.40, -0.02)]]
    bolts = [
        [
            (0.06, 0.02),
            (-0.14, -0.28),
            (-0.02, -0.28),
            (-0.12, -0.62),
            (0.18, -0.2),
            (0.05, -0.2),
            (0.18, 0.02),
        ],
        move(esc(BOLT_MINI, 0.75), -0.36, -0.02),
        move(esc(BOLT_MINI, 0.75), 0.36, -0.02),
    ]
    return [(nuvem + base, "m", 0.0), (bolts, "c", 0.02)]


def esc(pts, k):
    return [(x * k, y * k) for x, y in pts]


BOLT_MINI = [
    (0.04, 0.0),
    (-0.09, -0.2),
    (-0.01, -0.2),
    (-0.07, -0.42),
    (0.12, -0.14),
    (0.03, -0.14),
    (0.12, 0.0),
]


def s_cadente():
    rastro = []
    for dx, dy, w, c in (
        (0.0, 0.0, 0.12, 0.95),
        (-0.13, 0.12, 0.05, 0.62),
        (0.13, -0.12, 0.05, 0.62),
    ):
        p0 = (0.26 + dx, 0.26 + dy)
        p1 = (0.26 + dx - c * 0.72, 0.26 + dy - c * 0.72)
        rastro.append(
            fita([p0, ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2), p1], [w, w * 0.55, 0.004])
        )
    return [
        (rastro, "c", 0.0),
        ([estrela(5, 0.34, 0.15, 90 + 20, 0.27, 0.27)], "m", 0.018),
        ([estrela(5, 0.12, 0.055, 90 + 20, 0.27, 0.27)], "b", 0.03),
    ]


def s_jade():
    topo = regular(8, 0.60, 22.5)
    meio = regular(8, 0.34, 22.5)
    facetas = []
    for i in range(8):
        a, b = topo[i], topo[(i + 1) % 8]
        c, d = meio[(i + 1) % 8], meio[i]
        facetas.append(([[a, b, c, d]], "c" if i % 2 else "m", 0.0))
    return facetas + [([meio], "b", 0.02), ([estrela(4, 0.2, 0.05, 45)], "c", 0.03)]


def s_bussola():
    pontas = []
    claro = []
    for a in (0, 90, 180, 270):
        pontas.append(gira([(0.0, 0.0), (0.09, 0.09), (0.0, 0.62)], a))
        claro.append(gira([(0.0, 0.0), (-0.09, 0.09), (0.0, 0.62)], a))
    menores = []
    for a in (45, 135, 225, 315):
        menores.append(gira([(0.0, 0.0), (0.06, 0.06), (0.0, 0.42)], a))
        menores.append(gira([(0.0, 0.0), (-0.06, 0.06), (0.0, 0.42)], a))
    anel = [circulo(0, 0, 0.5, 56), circulo(0, 0, 0.46, 56)]
    return [
        (anel, "c", 0.0),
        (menores, "e", 0.006),
        (pontas, "m", 0.014),
        (claro, "b", 0.014),
        ([circulo(0, 0, 0.055, 16)], "c", 0.03),
    ]


def s_sinalizador():
    rastro = fita(
        curva_s((-0.08, -0.62), (0.04, 0.06), 0.035, 1.5, 24),
        [0.012 + 0.05 * i / 24 for i in range(25)],
    )
    faiscas = []
    for i in range(12):
        a = i * 30 + 8
        comp = 0.44 if i % 2 else 0.34
        faiscas.append(pena(0.05, 0.2, comp, 0.024, a))
    pontos = [
        circulo(0.05 + 0.5 * math.cos(rad(i * 60)), 0.2 + 0.42 * math.sin(rad(i * 60)), 0.02, 8)
        for i in range(6)
    ]
    return [
        ([rastro], "b", 0.0),
        (faiscas, "c", 0.006),
        ([estrela(8, 0.17, 0.07, 90, 0.05, 0.2)], "m", 0.018),
        (pontos, "m", 0.01),
    ]


def s_fundador():
    return [
        (louro(0.58), "m", 0.0),
        ([estrela(5, 0.34, 0.14, 90, 0, 0.03)], "c", 0.016),
        ([estrela(5, 0.13, 0.055, 90, 0, 0.03)], "b", 0.03),
    ]


def s_texto_louro(texto):
    def f():
        return [(louro(0.58), "m", 0.0), ("texto:" + texto, "c", 0.02)]

    return f


def s_padrao():
    escudo = mir(
        [(0.0, 0.56), (0.28, 0.50), (0.46, 0.44), (0.44, -0.06), (0.30, -0.34), (0.0, -0.60)]
    )
    dentro = mir(
        [(0.0, 0.46), (0.25, 0.41), (0.37, 0.36), (0.35, -0.05), (0.24, -0.27), (0.0, -0.47)]
    )
    return [
        ([escudo, dentro], "m", 0.0),
        ([estrela(5, 0.3, 0.125, 90, 0, 0.0)], "c", 0.014),
    ]


# os que passam do campo de esmalte encolhem um pouco
ESCALA = {"emb_dragao": 0.86, "emb_aurora": 0.9, "emb_fenix": 0.94, "emb_aguia_dourada": 0.96}

SIMBOLOS = {
    "emb_arrozais": s_arrozais,
    "emb_serraria": s_serraria,
    "emb_ponte": s_ponte,
    "emb_engenho": s_engenho,
    "emb_xomgo": s_vila,
    "emb_starlite": s_starlite,
    "emb_chulai": s_chulai,
    "emb_operacao": s_operacao,
    "emb_arquivo": s_arquivo,
    "emb_aguia_dourada": s_aguia,
    "emb_tigre": s_tigre,
    "emb_dragao": s_dragao,
    "emb_lotus": s_lotus,
    "emb_raio": s_raio,
    "emb_fenix": s_fenix,
    "emb_lua_cheia": s_lua,
    "emb_aurora": s_aurora,
    "emb_cobra": s_cobra,
    "emb_as": s_as,
    "emb_lobo": s_lobo,
    "emb_trovao": s_trovao,
    "emb_estrela_cadente": s_cadente,
    "emb_jade": s_jade,
    "emb_bussola": s_bussola,
    "emb_sinalizador": s_sinalizador,
    "emb_fundador": s_fundador,
    "emb_fundador_65": s_texto_louro("65"),
    "emb_padrao": s_padrao,
    "emb_top10": s_texto_louro("10"),
}


# ------------------------------------------------------------------ materiais
def lin(c):
    return tuple((x / 255) ** 2.2 for x in c)


def mat_metal(nome, cor, rug=0.26):
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*lin(cor), 1.0)
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = rug
    coord = nt.nodes.new("ShaderNodeTexCoord")
    ruido = nt.nodes.new("ShaderNodeTexNoise")
    ruido.inputs["Scale"].default_value = 90.0
    ruido.inputs["Detail"].default_value = 6.0
    nt.links.new(coord.outputs["Object"], ruido.inputs["Vector"])
    faixa = nt.nodes.new("ShaderNodeMapRange")
    faixa.inputs["To Min"].default_value = max(0.05, rug - 0.08)
    faixa.inputs["To Max"].default_value = min(1.0, rug + 0.1)
    nt.links.new(ruido.outputs["Fac"], faixa.inputs["Value"])
    nt.links.new(faixa.outputs["Result"], b.inputs["Roughness"])
    return m


def mat_esmalte(nome, cor):
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*lin(cor), 1.0)
    b.inputs["Roughness"].default_value = 0.16
    for k in ("Coat Weight", "Clearcoat"):
        if k in b.inputs:
            b.inputs[k].default_value = 1.0
            break
    return m


# a chapa de cada raridade: metal, metal claro do filete e a cor do brilho atrás
CHAPAS = {
    "comum": ((168, 112, 66), (214, 160, 108)),
    "incomum": ((150, 156, 160), (214, 220, 222)),
    "raro": ((196, 204, 214), (240, 244, 250)),
    "epico": ((226, 170, 60), (255, 222, 130)),
    "lendario": ((240, 180, 50), (255, 232, 150)),
}


# ------------------------------------------------------------------ peças
def curva(nome, polys, mat, z, ext=0.018, bev=0.008):
    cu = bpy.data.curves.new(nome, "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    cu.extrude = ext
    cu.bevel_depth = bev
    cu.bevel_resolution = 3
    cu.resolution_u = 2
    for pts in polys:
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (x, y) in enumerate(pts):
            sp.points[i].co = (x, y, 0.0, 1.0)
        sp.use_cyclic_u = True
    ob = bpy.data.objects.new(nome, cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = (0, 0, z)
    cu.materials.append(mat)
    return ob


def texto(corpo, mat, z, altura):
    fonte = FONTE if FONTE.exists() else FONTE_RESERVA
    cu = bpy.data.curves.new("Texto", "FONT")
    cu.body = corpo
    cu.font = bpy.data.fonts.load(str(fonte), check_existing=True)
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = altura
    cu.extrude = 0.018
    cu.bevel_depth = 0.006
    cu.bevel_resolution = 2
    ob = bpy.data.objects.new("Texto", cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = (0, 0.02, z)
    cu.materials.append(mat)
    return ob


def dentro_de(pt, poly):
    """O ponto está dentro do polígono? (raio horizontal)"""
    x, y = pt
    d = False
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        if (ay > y) != (by > y) and x < ax + (y - ay) / (by - ay) * (bx - ax):
            d = not d
    return d


def area(poly):
    s = 0.0
    for i in range(len(poly)):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % len(poly)]
        s += ax * by - bx * ay
    return abs(s) / 2


def grupos(polys):
    """Junta cada contorno com os seus furos (polígono inteiro dentro de outro). O resto sai em
    peças separadas: numa curva só, o que se sobrepõe (penas, pétalas, nuvem) vira buraco."""
    pai = {}
    for i, p in enumerate(polys):
        melhor = None
        for j, q in enumerate(polys):
            if i != j and area(q) > area(p) and all(dentro_de(v, q) for v in p):
                if melhor is None or area(q) < area(polys[melhor]):
                    melhor = j
        pai[i] = melhor
    saida = {}
    for i in range(len(polys)):
        raiz = i if pai[i] is None else pai[i]
        saida.setdefault(raiz, []).append(polys[i])
    return list(saida.values())


def mat_halo(nome, cor, forca):
    """O brilho atrás das insígnias altas: emissão com o alfa caindo do centro para a borda."""
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    nt.links.new(coord.outputs["Object"], grad.inputs["Vector"])
    curva_a = nt.nodes.new("ShaderNodeMath")
    curva_a.operation = "POWER"
    curva_a.inputs[1].default_value = 1.8
    nt.links.new(grad.outputs["Fac"], curva_a.inputs[0])
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (*lin(cor), 1.0)
    e.inputs["Strength"].default_value = forca
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(curva_a.outputs[0], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(e.outputs[0], mix.inputs[2])
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], o.inputs["Surface"])
    return m


def contorno(raridade):
    """A silhueta da chapa e a do campo de esmalte."""
    if raridade == "comum":
        return circulo(0, 0, 0.98, 96), circulo(0, 0, 0.82, 96)
    if raridade == "incomum":
        fora = mir(
            [(0.0, 0.98), (0.46, 0.90), (0.86, 0.76), (0.84, -0.08), (0.56, -0.62), (0.0, -1.0)]
        )
        dentro = mir(
            [(0.0, 0.82), (0.40, 0.76), (0.72, 0.65), (0.70, -0.06), (0.47, -0.52), (0.0, -0.83)]
        )
        return fora, dentro
    if raridade == "raro":
        return regular(6, 1.0, 90), regular(6, 0.82, 90)
    if raridade == "epico":
        return estrela(8, 1.0, 0.82, 90), circulo(0, 0, 0.72, 96)
    return estrela(16, 1.0, 0.78, 90), circulo(0, 0, 0.70, 96)


def montar(chave, raridade, cor, cor2):
    objs = []
    metal, filete = CHAPAS[raridade]
    m_chapa = mat_metal("Chapa", metal, 0.3)
    m_filete = mat_metal("Filete", filete, 0.18)
    m_campo = mat_esmalte("Campo", cor)
    m_simb = mat_metal("Simbolo", filete, 0.2)
    m_cor2 = mat_esmalte("Cor2", cor2)
    m_escuro = mat_esmalte("Escuro", tuple(int(c * 0.28) for c in cor))
    m_claro = mat_metal("Claro", (250, 244, 226), 0.14)
    fora, dentro = contorno(raridade)
    objs.append(curva("Chapa", [fora], m_chapa, 0.0, ext=0.05, bev=0.022))
    # filete em volta do esmalte
    aro = [[(x * 1.06, y * 1.06) for x, y in dentro], dentro]
    objs.append(curva("Filete", aro, m_filete, 0.086, ext=0.012, bev=0.01))
    objs.append(curva("Campo", [dentro], m_campo, 0.076, ext=0.004, bev=0.0))
    # detalhe por raridade
    if raridade == "raro":
        for p in regular(6, 0.91, 90):
            objs.append(
                curva(
                    "Rebite",
                    [circulo(p[0], p[1], 0.035, 16)],
                    m_filete,
                    0.086,
                    ext=0.006,
                    bev=0.012,
                )
            )
    elif raridade == "epico":
        for i in range(8):
            a = 90 + i * 45
            p = (0.87 * math.cos(rad(a)), 0.87 * math.sin(rad(a)))
            objs.append(
                curva(
                    "Ponta", [estrela(4, 0.07, 0.02, a, *p)], m_filete, 0.086, ext=0.006, bev=0.006
                )
            )
    elif raridade == "lendario":
        for i in range(16):
            a = 90 + i * 22.5
            r = 0.8
            p = (r * math.cos(rad(a)), r * math.sin(rad(a)))
            m = m_cor2 if i % 2 == 0 else m_filete
            objs.append(
                curva("Conta", [circulo(p[0], p[1], 0.036, 14)], m, 0.09, ext=0.006, bev=0.012)
            )
    # o símbolo
    mats = {"m": m_simb, "c": m_cor2, "e": m_escuro, "b": m_claro}
    base = 0.108
    k = ESCALA.get(chave, 1.0) * (1.0 if raridade != "lendario" else 0.98)
    for polys, qual, dz in SIMBOLOS[chave]():
        if isinstance(polys, str):
            objs.append(texto(polys.split(":", 1)[1], mats[qual], base + dz, 0.56))
            continue
        polys = [[(x * k, y * k) for x, y in p] for p in polys]
        # cada peça um fio acima da anterior: as que se sobrepõem não brigam pela mesma altura
        for n, g in enumerate(grupos(polys)):
            objs.append(curva("Simbolo", g, mats[qual], base + dz + n * 0.0012))
    return objs


def render(chave, raridade, cor, cor2, amostras, lado, nome):
    C.cena_vazia()
    cena = bpy.context.scene
    L.configurar(cena, lado, lado, amostras)
    cena.view_settings.view_transform = "Standard"
    try:
        cena.view_settings.look = "None"
    except TypeError:
        pass
    cena.view_settings.exposure = -0.2
    objs = montar(chave, raridade, cor, cor2)
    # a insígnia inclinada um pouco, sem rodar, para o relevo aparecer; a câmera fica de frente
    pivo = bpy.data.objects.new("Pivo", None)
    cena.collection.objects.link(pivo)
    pivo.rotation_euler = (math.radians(-11), math.radians(8), 0.0)
    for o in objs:
        o.parent = pivo
    forca_halo = {"raro": 0.5, "epico": 1.0, "lendario": 1.6}.get(raridade)
    if forca_halo:
        bpy.ops.mesh.primitive_plane_add(size=2.0, location=(0, 0, -0.4))
        h = bpy.context.active_object
        h.name = "Halo"
        h.scale = (1.15, 1.15, 1.0)
        h.data.materials.append(
            mat_halo("Halo", CHAPAS[raridade][1] if raridade != "raro" else cor2, forca_halo)
        )
        h.visible_shadow = False
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.32
    cam = bpy.data.objects.new("Cam", cd)
    cena.collection.objects.link(cam)
    cam.location = (0.0, 0.0, 5.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)
    cena.camera = cam
    alvo = Vector((0, 0, 0.1))
    L.luz_area("Chave", (-2.4, 2.6, 3.4), alvo, 60, (1.0, 0.93, 0.82), 2.2)
    L.luz_area("Enche", (2.8, -1.2, 2.6), alvo, 22, (0.78, 0.86, 1.0), 2.4)
    L.luz_area("Raso", (0.0, -3.4, 0.9), alvo, 34, (1.0, 0.9, 0.74), 1.4)
    L.luz_area("Cima", (0.6, 0.4, 4.2), alvo, 18, (1.0, 1.0, 1.0), 3.0)
    # mundo escuro e quente: dá o que refletir no metal
    w = bpy.data.worlds.new("Mundo")
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.20, 0.17, 0.13, 1.0)
    bg.inputs[1].default_value = 0.9
    cena.world = w
    cena.render.film_transparent = True
    SAIDA.mkdir(parents=True, exist_ok=True)
    cena.render.filepath = str(SAIDA / nome)
    bpy.ops.render.render(write_still=True)
    log("ok", nome)


def principal():
    args = C.argumentos()
    if not args:
        raise SystemExit("uso: emblemas.py -- todos | <id>... [--amostras N] [--teste]")
    amostras = 48
    if "--amostras" in args:
        amostras = int(args[args.index("--amostras") + 1])
    teste = "--teste" in args
    cat = catalogo()
    faltam = [k for k in cat if k not in SIMBOLOS]
    if faltam:
        raise SystemExit(f"sem símbolo: {faltam}")
    pedidos = [a for a in args if a.startswith("emb_")]
    chaves = list(cat) if args[0] == "todos" else pedidos
    for k in chaves:
        rar, cor, cor2 = cat[k]
        render(
            k,
            rar,
            cor,
            cor2,
            amostras,
            256 if teste else 512,
            ("teste_" if teste else "") + k + ".png",
        )


if __name__ == "__main__":
    principal()
