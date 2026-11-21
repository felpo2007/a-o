"""Rostos pintados dos soldados de bloco (D-236; substituem os de traço da D-102).

Pedido do dono: "deixe os personagens mais bonitos com iluminação melhor faces uniformes reflexos".
A cabeça de bloco é lisa e o motor não ilumina um decalque por relevo, então o volume vai pintado:
luz de cima, órbita, ponte e asa do nariz, maçã, sulco, lábios, queixo e mandíbula. Tudo é sombra e
brilho com alfa sobre a cor da cabeça (Corpo.PELE), então cada rosto serve para todos os tons de
pele. A borda do decalque é transparente, para não marcar a quina da cabeça.

Os parâmetros (olho, nariz, boca, barba...) são os mesmos do make_rostos.py: a mesma geometria para
os dois lados, sem caricatura, e o mesmo soldado continua com o mesmo rosto.

Saídas: assets/rostos/v2/rosto_<lado>_NN.png (512 x 512) e assets/rostos/v2/previa.png.

Uso (a partir de vantuong65): uv run --group arte python tools/rostos/make_rostos2.py
"""

from __future__ import annotations

import importlib.util
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RAIZ = Path(__file__).resolve().parents[2]
SAIDA = RAIZ / "assets" / "rostos" / "v2"
PX = 512
SS = 2
W = PX * SS

_spec = importlib.util.spec_from_file_location(
    "make_rostos", Path(__file__).with_name("make_rostos.py")
)
assert _spec and _spec.loader
v1 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(v1)

_yy, _xx = np.mgrid[0:W, 0:W]
U = (_xx + 0.5) / W
V = (_yy + 0.5) / W
SOMBRA = (54, 28, 20)
LUZ = (255, 240, 224)


def g(cx: float, cy: float, rx: float, ry: float, ang: float = 0.0) -> np.ndarray:
    """Mancha gaussiana elíptica, girada `ang` graus."""
    dx, dy = U - cx, V - cy
    if ang:
        a = math.radians(ang)
        dx, dy = dx * math.cos(a) + dy * math.sin(a), -dx * math.sin(a) + dy * math.cos(a)
    return np.exp(-0.5 * ((dx / rx) ** 2 + (dy / ry) ** 2))


def suave(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def p(x: float, y: float) -> tuple[float, float]:
    return x * W, y * W


def camada() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    c = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    return c, ImageDraw.Draw(c)


def borra(c: Image.Image, raio: float) -> Image.Image:
    """Desfoque com alfa pré-multiplicado: sem ele, o fundo preto vira halo na pincelada."""
    return c.convert("RGBa").filter(ImageFilter.GaussianBlur(raio)).convert("RGBA")


def volume(k: dict) -> Image.Image:
    """O relevo do rosto: S > 0 clareia, S < 0 escurece."""
    d, ey, ny, by = k["olho_dist"], k["olho_y"], k["nariz_y"], k["boca_y"]
    nw, bw = k["nariz_larg"], k["boca_larg"]
    s = np.zeros((W, W))
    # testa e arco da sobrancelha, com a luz de cima
    s += 0.13 * g(0.5, ey - 0.21, 0.27, 0.10)
    s += 0.05 * g(0.42, ey - 0.25, 0.10, 0.05)
    s -= 0.05 * g(0.5, ey - 0.075, 0.03, 0.035)
    # bochecha, sulco e mandíbula, nos dois lados
    for t in (-1, 1):
        x = 0.5 + t * d
        s += 0.09 * g(x, ey - k["sobr_alt"] - 0.012, 0.105, 0.018)
        s -= 0.30 * g(x, ey + 0.004, 0.112, 0.050)
        s -= 0.17 * g(0.5 + t * (d - 0.088), ey - 0.012, 0.034, 0.042)
        s -= 0.09 * g(x + t * 0.09, ey + 0.012, 0.04, 0.04)
        s += 0.05 * g(x, ey + 0.058, 0.08, 0.012)  # bolsa do olho
        s += 0.10 * g(0.5 + t * 0.265, ey + 0.135, 0.105, 0.055, 12 * t)
        s -= 0.09 * g(0.5 + t * 0.32, by - 0.03, 0.085, 0.13)
        s -= 0.07 * g(0.5 + t * 0.40, ey + 0.04, 0.075, 0.18)
        s -= 0.10 * g(0.5 + t * 0.34, by + 0.14, 0.13, 0.10, -24 * t)
        # lado do nariz, asa e a dobra do nariz à boca
        s -= 0.17 * g(0.5 + t * 0.043, (ey + ny) / 2 + 0.005, 0.017, 0.105)
        s -= 0.15 * g(0.5 + t * nw * 1.12, ny + 0.002, 0.016, 0.018)
        s += 0.07 * g(0.5 + t * nw * 0.82, ny - 0.008, 0.012, 0.012)
        for j in range(13):
            q = j / 12
            s -= 0.055 * g(
                0.5 + t * (nw * 1.25 + (bw + 0.022 - nw * 1.25) * q),
                ny + 0.012 + (by + 0.012 - ny) * q,
                0.009,
                0.013,
            )
        s += 0.06 * g(0.5 + t * (bw * 0.7), (ny + by) / 2 + 0.018, 0.04, 0.022)
        s += 0.04 * g(0.5 + t * 0.016, (ny + by) / 2 + 0.008, 0.005, 0.024)
        s -= 0.20 * g(0.5 + t * (bw + 0.006), by + 0.002, 0.011, 0.011)  # canto da boca
    # ponte, ponta e base do nariz
    s += 0.17 * g(0.5, (ey + ny) / 2 - 0.03, 0.014, 0.105)
    s += 0.22 * g(0.5, ny - 0.018, 0.024, 0.020)
    s -= 0.34 * g(0.5, ny + 0.034, 0.052, 0.011)
    s -= 0.10 * g(0.5, (ny + by) / 2 + 0.008, 0.008, 0.026)  # filtro
    # abaixo da boca, queixo e fundo do rosto
    s -= 0.27 * g(0.5, by + 0.058, 0.078, 0.014)
    s += 0.16 * g(0.5, by + 0.135, 0.078, 0.038)
    s -= 0.14 * suave(0.90, 1.0, V)
    # a borda do decalque não pode marcar a quina da cabeça
    borda = suave(1.0, 0.70, np.sqrt(((U - 0.5) / 0.49) ** 2 + ((V - 0.53) / 0.49) ** 2))
    s *= borda
    # grão de pele, muito fino
    rng = np.random.default_rng(k["semente"])
    grao = rng.normal(0, 1, (W // 2, W // 2))
    grao = np.asarray(
        Image.fromarray(((grao + 3) / 6 * 255).clip(0, 255).astype("uint8")).resize((W, W), 2),
        dtype=float,
    )
    s += (grao / 255 - 0.5) * 0.035 * borda
    alfa = np.where(s < 0, np.clip(-s, 0, 1) * 0.92, np.clip(s, 0, 1) * 0.62)
    rgba = np.zeros((W, W, 4), dtype=np.uint8)
    for c in range(3):
        rgba[..., c] = np.where(s < 0, SOMBRA[c], LUZ[c])
    rgba[..., 3] = (alfa * 255).astype("uint8")
    return Image.fromarray(rgba, "RGBA")


def sujeira(img: Image.Image, k: dict) -> None:
    if k["sujeira"] <= 0:
        return
    r = random.Random(k["semente"] + 1)
    c, d = camada()
    # poeira larga e sem contorno: mancha redonda parecia doença de pele
    for _ in range(7):
        x, y = r.uniform(0.18, 0.82), r.uniform(0.22, 0.92)
        a, b = r.uniform(0.07, 0.15), r.uniform(0.03, 0.07)
        cor = (66, 52, 36, int(44 * k["sujeira"]))
        d.ellipse([*p(x - a, y - b), *p(x + a, y + b)], fill=cor)
    img.alpha_composite(borra(c, SS * 13))


def suor(img: Image.Image, k: dict) -> None:
    """O brilho de pele suada: pontos de luz na testa, no nariz e na maçã."""
    c, d = camada()
    y = k["olho_y"] - 0.20
    d.ellipse([*p(0.5 - 0.15, y - 0.035), *p(0.5 + 0.09, y + 0.035)], fill=(255, 248, 236, 26))
    for t in (-1, 1):
        x, y = 0.5 + t * 0.25, k["olho_y"] + 0.12
        d.ellipse([*p(x - 0.05, y - 0.018), *p(x + 0.05, y + 0.018)], fill=(255, 248, 236, 20))
    img.alpha_composite(borra(c, SS * 9))
    c, d = camada()
    y = k["nariz_y"] - 0.022
    d.ellipse([*p(0.5 - 0.007, y - 0.006), *p(0.5 + 0.007, y + 0.006)], fill=(255, 250, 240, 58))
    img.alpha_composite(borra(c, SS * 2.2))


def olho(img: Image.Image, cx: float, k: dict, t: int) -> None:
    """Olho: branco com sombra, íris com anel e fibras, pupila, reflexo, pálpebra e cílios."""
    cy, w, h = k["olho_y"], k["olho_larg"], k["olho_alt"] * 1.12
    cima, baixo = [], []
    for j in range(49):
        q = j / 48
        x = cx - w + 2 * w * q
        canto = q if t > 0 else 1 - q  # 0 = lado do nariz
        cima.append(p(x, cy - h * math.sin(math.pi * q) ** 0.85 * (1 + 0.16 * (canto - 0.5))))
        baixo.append(p(x, cy + h * 0.72 * math.sin(math.pi * q) ** 1.1))
    forma = cima + baixo[::-1]
    mas = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mas).polygon(forma, fill=255)
    mas = mas.filter(ImageFilter.GaussianBlur(0.8))
    m = np.asarray(mas, dtype=float) / 255
    # branco do olho, mais escuro nos cantos e embaixo da pálpebra
    cor = np.ones((W, W, 3)) * np.array([234.0, 228.0, 218.0])
    fx = (U - cx) / w
    fy = (V - cy) / h
    tom = 1 - 0.34 * np.clip(np.abs(fx), 0, 1) ** 2.2 - 0.34 * suave(0.05, -1.0, fy)
    cor = cor * tom[..., None]
    nariz = cx - t * w * 0.90
    rosa = g(nariz, cy + h * 0.1, 0.012, 0.010)[..., None]
    cor = cor * (1 - rosa) + np.array([206.0, 132.0, 120.0]) * rosa
    # íris
    ri = h * 1.08
    ix, iy = cx, cy + h * 0.02
    rr = np.sqrt((U - ix) ** 2 + (V - iy) ** 2) / ri
    ang = np.arctan2(V - iy, U - ix)
    base = np.array(k["iris"], dtype=float)
    fibra = 1 + 0.15 * np.sin(ang * 31 + k["semente"] % 7) + 0.09 * np.sin(ang * 73)
    miolo = 1 + 0.75 * suave(0.72, 0.30, rr)
    irisc = base[None, None, :] * (fibra * miolo)[..., None]
    anel = suave(0.70, 1.0, rr)[..., None]
    irisc = irisc * (1 - 0.72 * anel)
    dentro = suave(1.03, 0.97, rr)[..., None]
    cor = cor * (1 - dentro) + irisc * dentro
    pupila = suave(0.47, 0.40, rr)[..., None]
    cor = cor * (1 - pupila) + np.array([10.0, 8.0, 7.0]) * pupila
    # sombra da pálpebra de cima sobre o olho
    somb = 1 - 0.62 * suave(-0.15 + k["palpebra"] * 0.5, -1.0, fy)
    cor = cor * somb[..., None]
    # reflexo do céu, igual nos dois olhos: a luz vem do mesmo lado
    rx, ry = ix - ri * 0.34, iy - ri * 0.36
    brilho = suave(0.0036, 0.0020, np.sqrt((U - rx) ** 2 + (V - ry) ** 2))[..., None]
    baixo2 = 0.42 * g(ix + ri * 0.30, iy + ri * 0.42, ri * 0.20, ri * 0.11)[..., None]
    cor = cor * (1 - brilho) + np.array([255.0, 253.0, 246.0]) * brilho
    cor = cor * (1 - baixo2) + np.array([176.0, 196.0, 210.0]) * baixo2
    rgba = np.dstack((cor.clip(0, 255), m * 255)).astype("uint8")
    img.alpha_composite(Image.fromarray(rgba, "RGBA"))
    # dobra da pálpebra, cílios e linha de baixo
    c, d = camada()
    dobra = [(x, y - h * W * 0.42 - 0.002 * W) for x, y in cima[7:-5]]
    d.line(dobra, fill=(*SOMBRA, 74), width=max(2, int(0.0042 * W)))
    d.line(cima, fill=(20, 15, 12, 248), width=max(3, int(0.0085 * W)))
    externo = cima[-14:] if t > 0 else cima[:14]
    d.line(externo, fill=(16, 12, 10, 240), width=max(4, int(0.0115 * W)))
    d.line(baixo[4:-2], fill=(*SOMBRA, 96), width=max(2, int(0.0034 * W)))
    img.alpha_composite(borra(c, 0.7))


def sobrancelha(img: Image.Image, cx: float, k: dict, t: int) -> None:
    """Sobrancelha fio a fio, do lado do nariz para fora."""
    r = random.Random(k["semente"] + 10 + t)
    cy = k["olho_y"] - k["sobr_alt"]
    larg = k["olho_larg"] * 1.27
    ang = math.radians(k["sobr_ang"]) * -t
    c, d = camada()
    base, db = camada()
    pts = []
    for j in range(25):
        q = j / 24
        x = cx + t * (-larg + 2 * larg * q)
        y = cy - 0.014 * math.sin(math.pi * q) - (x - cx) * math.tan(ang) * t * t
        pts.append((x, y, q))
    for x, y, q in pts:
        e = k["sobr_grossa"] * (1 - 0.68 * q) * 0.52
        db.ellipse([*p(x - 0.009, y - e), *p(x + 0.009, y + e)], fill=(*k["cabelo"], 112))
    img.alpha_composite(borra(base, SS * 1.6))
    for _ in range(330):
        x, y, q = pts[r.randrange(len(pts))]
        e = k["sobr_grossa"] * (1 - 0.68 * q) * 0.58
        y0 = y + r.uniform(-e, e)
        incl = math.radians(68 - 62 * min(1, q * 1.6) + r.uniform(-11, 11))
        comp = r.uniform(0.012, 0.024) * (1 - 0.3 * q)
        x1 = x + t * math.cos(incl) * comp
        y1 = y0 - math.sin(incl) * comp
        cor = tuple(max(0, min(255, int(v * r.uniform(0.72, 1.18)))) for v in k["cabelo"])
        d.line([p(x, y0), p(x1, y1)], fill=(*cor, r.randint(135, 235)), width=max(1, SS))
    img.alpha_composite(borra(c, 0.45))


def nariz(img: Image.Image, k: dict) -> None:
    y, w = k["nariz_y"], k["nariz_larg"]
    c, d = camada()
    for t in (-1, 1):
        x = 0.5 + t * w * 0.52
        d.ellipse([*p(x - 0.0135, y + 0.010), *p(x + 0.0135, y + 0.024)], fill=(38, 20, 16, 210))
    img.alpha_composite(borra(c, SS * 0.9))


def boca(img: Image.Image, k: dict) -> None:
    w, y0, cv = k["boca_larg"], k["boca_y"], k["boca_curva"]

    def linha(q: float) -> float:
        return y0 - cv * math.cos(math.pi * (q - 0.5)) * 2 + cv

    n = 40
    meio = [(0.5 - w + 2 * w * j / n, linha(j / n)) for j in range(n + 1)]
    sup = []
    inf = []
    for j in range(n + 1):
        q = j / n
        x = 0.5 - w + 2 * w * q
        arco = math.sin(math.pi * q) ** 0.7
        cupido = 0.0065 * math.exp(-(((q - 0.5) / 0.055) ** 2))
        sup.append((x, linha(q) - 0.0235 * arco + cupido))
        inf.append((x, linha(q) + (0.030 + k["labio"]) * math.sin(math.pi * q) ** 0.9))
    c, d = camada()
    d.polygon([p(*a) for a in sup + meio[::-1]], fill=(112, 48, 44, 150))
    d.polygon([p(*a) for a in meio + inf[::-1]], fill=(150, 76, 68, 112))
    img.alpha_composite(borra(c, SS * 0.9))
    c, d = camada()
    bx, by = 0.5, y0 + (0.030 + k["labio"]) * 0.46
    d.ellipse(
        [*p(bx - w * 0.34, by - 0.0052), *p(bx + w * 0.34, by + 0.0052)], fill=(255, 238, 226, 92)
    )
    img.alpha_composite(borra(c, SS * 1.5))
    c, d = camada()
    d.line([p(*a) for a in meio], fill=(34, 15, 14, 235), width=max(2, int(0.0058 * W)))
    img.alpha_composite(borra(c, 0.8))


def _zona_barba(k: dict) -> np.ndarray:
    """Onde nasce a barba: maxilar, queixo e buço, sem o lábio."""
    by, bw = k["boca_y"], k["boca_larg"]
    z = suave(1.12, 0.62, np.sqrt(((U - 0.5) / 0.37) ** 2 + ((V - 0.80) / 0.235) ** 2))
    z *= suave(k["nariz_y"] + 0.03, k["nariz_y"] + 0.075, V + 0.05 * np.abs(U - 0.5))
    fora = 1 - 0.96 * suave(
        1.25, 0.86, np.sqrt(((U - 0.5) / (bw + 0.018)) ** 2 + ((V - by - 0.004) / 0.040) ** 2)
    )
    z = z * fora
    z *= 1 - 0.72 * g(0.5, by + 0.056, 0.032, 0.013)
    return np.clip(z * suave(0.0, 0.09, 1 - V) * suave(0.0, 0.08, np.minimum(U, 1 - U)), 0, 1)


def barba(img: Image.Image, k: dict) -> None:
    if k["barba"] <= 0:
        return
    z = _zona_barba(k)
    cor = np.array(k["cabelo"], dtype=np.uint8)
    rgba = np.zeros((W, W, 4), dtype=np.uint8)
    rgba[..., :3] = cor
    rgba[..., 3] = (z * (0.15 + 0.34 * k["barba"]) * 255).astype("uint8")
    img.alpha_composite(Image.fromarray(rgba, "RGBA").filter(ImageFilter.GaussianBlur(SS * 2.5)))
    r = random.Random(k["semente"] + 20)
    c, d = camada()
    alvo = int(9000 * k["barba"])
    feitos = tentativas = 0
    while feitos < alvo and tentativas < alvo * 7:
        tentativas += 1
        x, y = r.random(), r.uniform(0.52, 1.0)
        i, j = min(W - 1, int(x * W)), min(W - 1, int(y * W))
        if r.random() > z[j, i]:
            continue
        feitos += 1
        giro = math.radians(88 + (x - 0.5) * -80 + r.uniform(-20, 20))
        comp = r.uniform(0.0035, 0.0085)
        x1, y1 = x + math.cos(giro) * comp, y + math.sin(giro) * comp
        d.line([p(x, y), p(x1, y1)], fill=(*k["cabelo"], r.randint(70, 175)), width=1)
    img.alpha_composite(borra(c, 0.42))


def bigode(img: Image.Image, k: dict) -> None:
    if not k["bigode"]:
        return
    r = random.Random(k["semente"] + 30)
    w, y = k["boca_larg"] * 0.96, k["boca_y"] - 0.034
    b, db = camada()
    pts = []
    for j in range(25):
        q = j / 24
        pts.append(p(0.5 - w + 2 * w * q, y + 0.013 * abs(q - 0.5) * 2 - 0.018))
    for j in range(24, -1, -1):
        q = j / 24
        pts.append(p(0.5 - w + 2 * w * q, y + 0.018 * abs(q - 0.5) * 2 + 0.004))
    db.polygon(pts, fill=(*k["cabelo"], 150))
    img.alpha_composite(borra(b, SS * 1.1))
    c, d = camada()
    for _ in range(640):
        q = r.random()
        x = 0.5 - w + 2 * w * q
        y0 = y + r.uniform(-0.019, 0.004) + 0.016 * abs(q - 0.5) * 2
        lado = -1 if q < 0.5 else 1
        giro = math.radians(90 - lado * (18 + 42 * abs(q - 0.5) * 2) + r.uniform(-9, 9))
        comp = r.uniform(0.012, 0.022)
        x1, y1 = x + math.cos(giro) * comp, y0 + math.sin(giro) * comp
        cor = tuple(max(0, min(255, int(v * r.uniform(0.7, 1.2)))) for v in k["cabelo"])
        d.line([p(x, y0), p(x1, y1)], fill=(*cor, r.randint(130, 225)), width=max(1, SS - 1))
    img.alpha_composite(borra(c, 0.45))


def olheira(img: Image.Image, k: dict) -> None:
    if not k["olheira"]:
        return
    c, d = camada()
    for t in (-1, 1):
        x, y = 0.5 + t * k["olho_dist"], k["olho_y"] + 0.045
        rx = k["olho_larg"] * 0.92
        d.ellipse([*p(x - rx, y - 0.017), *p(x + rx, y + 0.017)], fill=(74, 44, 52, 66))
    img.alpha_composite(borra(c, SS * 3.2))


def cicatriz(img: Image.Image, k: dict) -> None:
    if not k["cicatriz"]:
        return
    x0 = 0.5 + 0.27 * (1 if k["semente"] % 2 else -1)
    a, b = p(x0, 0.515), p(x0 + 0.032, 0.625)
    c, d = camada()
    d.line([a, b], fill=(*SOMBRA, 130), width=int(0.011 * W))
    img.alpha_composite(borra(c, SS * 1.1))
    c, d = camada()
    d.line([a, b], fill=(214, 148, 132, 190), width=max(2, int(0.0048 * W)))
    img.alpha_composite(borra(c, 0.8))


def rosto(lado: str, i: int) -> Image.Image:
    k = v1._parametros(lado, i)
    img = volume(k)
    sujeira(img, k)
    olheira(img, k)
    barba(img, k)
    suor(img, k)
    for t in (-1, 1):
        olho(img, 0.5 + t * k["olho_dist"], k, t)
        sobrancelha(img, 0.5 + t * k["olho_dist"], k, t)
    nariz(img, k)
    boca(img, k)
    bigode(img, k)
    cicatriz(img, k)
    return img.resize((PX, PX), Image.LANCZOS)


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    feitos: dict[str, list[Image.Image]] = {}
    for lado in ("us", "vc"):
        feitos[lado] = []
        for i in range(1, v1.N + 1):
            img = rosto(lado, i)
            img.save(SAIDA / f"rosto_{lado}_{i:02d}.png", optimize=True)
            feitos[lado].append(img)
    t = 192
    prev = Image.new("RGB", (t * 8, t * 6), (34, 34, 34))
    for li, lado in enumerate(("us", "vc")):
        for j, img in enumerate(feitos[lado][:8]):
            peq = img.resize((t, t), Image.LANCZOS)
            for ti, tom in enumerate(v1.PREVIA_PELE[lado]):
                q = Image.new("RGBA", (t, t), (*tom, 255))
                q.alpha_composite(peq)
                prev.paste(q.convert("RGB"), (j * t, (li * 3 + ti) * t))
    prev.save(SAIDA / "previa.png")
    print(f"{2 * v1.N} rostos em {SAIDA}")


if __name__ == "__main__":
    main()
