"""Ícones dourados da árvore de vantagens (D-247). Desenhados por código, sem imagem de fora.

Saída: assets/ui/carreira/no_<icone>.png, 160 x 160, RGBA.

Uso (de vantuong65/): uv run --group arte python tools/carreira_icones.py
"""

from __future__ import annotations

import math
from collections.abc import Callable
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SAIDA = Path(__file__).resolve().parents[1] / "assets" / "ui" / "carreira"
LADO = 160
K = 4  # desenha maior e reduz, para a borda sair lisa
T = LADO * K


def p(x: float, y: float) -> tuple[float, float]:
    return x * T, y * T


def linha(d, pts, w):
    largura = int(w * T)
    d.line([p(*q) for q in pts], fill=255, width=largura, joint="curve")
    for q in pts:
        x, y = p(*q)
        r = largura / 2
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)


def disco(d, x, y, r, fill=255):
    cx, cy = p(x, y)
    d.ellipse((cx - r * T, cy - r * T, cx + r * T, cy + r * T), fill=fill)


def caixa(d, x0, y0, x1, y1, r=0.03, fill=255):
    d.rounded_rectangle((*p(x0, y0), *p(x1, y1)), radius=int(r * T), fill=fill)


def anel(d, x, y, r, w):
    cx, cy = p(x, y)
    d.ellipse((cx - r * T, cy - r * T, cx + r * T, cy + r * T), outline=255, width=int(w * T))


def corrida(d):
    disco(d, 0.61, 0.17, 0.085)
    linha(d, [(0.55, 0.32), (0.45, 0.55)], 0.1)
    linha(d, [(0.54, 0.34), (0.72, 0.45), (0.86, 0.38)], 0.065)
    linha(d, [(0.52, 0.34), (0.35, 0.36), (0.25, 0.48)], 0.065)
    linha(d, [(0.45, 0.56), (0.63, 0.67), (0.59, 0.88)], 0.08)
    linha(d, [(0.44, 0.57), (0.34, 0.73), (0.14, 0.76)], 0.08)


def municao(d):
    for x in (0.26, 0.5, 0.74):
        d.polygon(
            [p(x - 0.085, 0.4), p(x - 0.06, 0.25), p(x, 0.1), p(x + 0.06, 0.25), p(x + 0.085, 0.4)],
            fill=255,
        )
        caixa(d, x - 0.085, 0.44, x + 0.085, 0.8, 0.012)
        caixa(d, x - 0.1, 0.82, x + 0.1, 0.89, 0.012)


def escudo(d):
    pts = [
        (0.5, 0.08),
        (0.84, 0.2),
        (0.82, 0.52),
        (0.7, 0.74),
        (0.5, 0.92),
        (0.3, 0.74),
        (0.18, 0.52),
        (0.16, 0.2),
    ]
    d.polygon([p(*q) for q in pts], fill=255)
    menor = [(0.5 + (x - 0.5) * 0.66, 0.5 + (y - 0.49) * 0.66) for x, y in pts]
    d.polygon([p(*q) for q in menor], fill=0)
    d.polygon([p(0.5, 0.26), p(0.66, 0.34), p(0.63, 0.55), p(0.5, 0.72)], fill=255)


def vida(d):
    pts = []
    for i in range(60):
        t = 2 * math.pi * i / 60
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append(p(0.5 + x * 0.0245, 0.47 - y * 0.0245))
    d.polygon(pts, fill=255)
    caixa(d, 0.45, 0.28, 0.55, 0.66, 0.012, fill=0)
    caixa(d, 0.31, 0.42, 0.69, 0.52, 0.012, fill=0)


def mira(d):
    anel(d, 0.5, 0.5, 0.31, 0.06)
    disco(d, 0.5, 0.5, 0.055)
    for a, b in (
        ((0.5, 0.06), (0.5, 0.32)),
        ((0.5, 0.68), (0.5, 0.94)),
        ((0.06, 0.5), (0.32, 0.5)),
        ((0.68, 0.5), (0.94, 0.5)),
    ):
        linha(d, [a, b], 0.05)


def mochila(d):
    caixa(d, 0.22, 0.26, 0.78, 0.9, 0.09)
    caixa(d, 0.36, 0.1, 0.64, 0.3, 0.05)
    caixa(d, 0.43, 0.16, 0.57, 0.26, 0.02, fill=0)
    caixa(d, 0.3, 0.56, 0.7, 0.8, 0.03, fill=0)
    caixa(d, 0.34, 0.6, 0.66, 0.76, 0.02)
    caixa(d, 0.3, 0.42, 0.7, 0.47, 0.012, fill=0)
    caixa(d, 0.46, 0.38, 0.54, 0.52, 0.012, fill=0)


def radio(d):
    linha(d, [(0.24, 0.34), (0.72, 0.09)], 0.04)
    caixa(d, 0.1, 0.34, 0.9, 0.88, 0.06)
    caixa(d, 0.17, 0.42, 0.56, 0.58, 0.02, fill=0)
    for y in (0.65, 0.72, 0.79):
        caixa(d, 0.17, y, 0.56, y + 0.035, 0.008, fill=0)
    disco(d, 0.73, 0.52, 0.09, fill=0)
    disco(d, 0.73, 0.52, 0.05)
    disco(d, 0.68, 0.75, 0.04, fill=0)
    disco(d, 0.79, 0.75, 0.04, fill=0)


def binoculo(d):
    for x in (0.28, 0.72):
        caixa(d, x - 0.17, 0.24, x + 0.17, 0.62, 0.06)
        disco(d, x, 0.68, 0.21)
        disco(d, x, 0.68, 0.125, fill=0)
        disco(d, x, 0.68, 0.065)
    caixa(d, 0.42, 0.34, 0.58, 0.54, 0.02)
    caixa(d, 0.18, 0.14, 0.38, 0.22, 0.02)
    caixa(d, 0.62, 0.14, 0.82, 0.22, 0.02)


def garrote(d):
    im = Image.new("L", (T, T), 0)
    e = ImageDraw.Draw(im)
    e.rounded_rectangle((*p(0.08, 0.34), *p(0.92, 0.66)), radius=int(0.15 * T), fill=255)
    e.rectangle((*p(0.36, 0.34), *p(0.64, 0.66)), fill=0)
    e.rounded_rectangle((*p(0.385, 0.365), *p(0.615, 0.635)), radius=int(0.02 * T), fill=255)
    for x in (0.45, 0.55):
        for y in (0.44, 0.56):
            cx, cy = p(x, y)
            r = 0.022 * T
            e.ellipse((cx - r, cy - r, cx + r, cy + r), fill=0)
    r = im.rotate(-42, resample=Image.BICUBIC)
    d._image.paste(r, (0, 0), r)


def recarga(d):
    caixa(d, 0.39, 0.3, 0.61, 0.73, 0.03)
    for y in (0.4, 0.49, 0.58):
        caixa(d, 0.43, y, 0.57, y + 0.035, 0.006, fill=0)
    cx, cy = p(0.5, 0.5)
    r = 0.4 * T
    d.arc((cx - r, cy - r, cx + r, cy + r), start=-70, end=165, fill=255, width=int(0.065 * T))
    d.arc((cx - r, cy - r, cx + r, cy + r), start=205, end=262, fill=255, width=int(0.065 * T))
    d.polygon([p(0.56, 0.0), p(0.74, 0.13), p(0.54, 0.22)], fill=255)


def folego(d):
    for y, x1, gancho in ((0.3, 0.68, 0.11), (0.5, 0.84, 0.12), (0.7, 0.62, 0.1)):
        linha(d, [(0.1, y), (x1, y)], 0.065)
        cx, cy = p(x1, y - gancho if y < 0.6 else y + gancho)
        r = gancho * T
        if y < 0.6:
            d.arc(
                (cx - r, cy - r, cx + r, cy + r), start=-140, end=90, fill=255, width=int(0.065 * T)
            )
        else:
            d.arc(
                (cx - r, cy - r, cx + r, cy + r), start=-90, end=140, fill=255, width=int(0.065 * T)
            )


def socorro(d):
    caixa(d, 0.12, 0.3, 0.88, 0.86, 0.07)
    caixa(d, 0.36, 0.14, 0.64, 0.34, 0.04)
    caixa(d, 0.42, 0.2, 0.58, 0.32, 0.015, fill=0)
    caixa(d, 0.44, 0.42, 0.56, 0.76, 0.012, fill=0)
    caixa(d, 0.33, 0.53, 0.67, 0.65, 0.012, fill=0)


ICONES: dict[str, Callable] = {
    "corrida": corrida,
    "municao": municao,
    "forca": escudo,
    "vida": vida,
    "mira": mira,
    "mochila": mochila,
    "radio": radio,
    "binoculo": binoculo,
    "garrote": garrote,
    "recarga": recarga,
    "folego": folego,
    "socorro": socorro,
}


def dourado(mascara: Image.Image) -> Image.Image:
    a = np.asarray(mascara, dtype=np.float32) / 255
    h, w = a.shape
    v = np.linspace(0, 1, h)[:, None]
    topo, meio, baixo = (
        np.array([255, 240, 176.0]),
        np.array([246, 196, 84.0]),
        np.array([176, 108, 28.0]),
    )
    t1 = np.clip(v / 0.5, 0, 1)
    t2 = np.clip((v - 0.5) / 0.5, 0, 1)
    rgb = (topo * (1 - t1) + meio * t1) * (v < 0.5) + (meio * (1 - t2) + baixo * t2) * (v >= 0.5)
    rgb = np.repeat(rgb[:, None, :], w, axis=1).reshape(h, w, 3)
    # luz na borda de cima de cada traço
    em_cima = np.roll(a, 2, axis=0)
    brilho = np.clip(a - em_cima, 0, 1)[..., None]
    rgb = np.clip(rgb + brilho * 70, 0, 255)
    return Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")


def gerar(nome: str, fn: Callable) -> None:
    m = Image.new("L", (T, T), 0)
    fn(ImageDraw.Draw(m))
    m = m.resize((LADO, LADO), Image.LANCZOS)
    corpo = dourado(m)
    sombra = Image.new("RGBA", (LADO, LADO), (0, 0, 0, 0))
    preto = Image.new("RGBA", (LADO, LADO), (10, 7, 3, 215))
    sombra.paste(preto, (0, 3), m.filter(ImageFilter.GaussianBlur(2.2)))
    Image.alpha_composite(sombra, corpo).save(SAIDA / f"no_{nome}.png", optimize=True)


def principal() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    for nome, fn in ICONES.items():
        gerar(nome, fn)
    print("ok", len(ICONES))


if __name__ == "__main__":
    principal()
