"""Ícones dourados das entradas do menu principal (D-250). Desenhados por código.

Saída: assets/ui/marca/menu_<nome>.png, 160 x 160, RGBA.

Uso (de vantuong65/): uv run --group arte python tools/marca_icones.py
"""

from __future__ import annotations

import math
import sys
from collections.abc import Callable
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from carreira_icones import LADO, T, anel, caixa, disco, dourado, linha, p  # noqa: E402

SAIDA = Path(__file__).resolve().parents[1] / "assets" / "ui" / "marca"


def estrela(d, x, y, r, fill=255):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        q = r if i % 2 == 0 else r * 0.42
        pts.append(p(x + q * math.cos(a), y + q * math.sin(a)))
    d.polygon(pts, fill=fill)


def arsenal(d):
    im = Image.new("L", (T, T), 0)
    e = ImageDraw.Draw(im)
    # coronha, caixa, cano, alça, carregador e guarda-mão
    e.polygon([p(0.02, 0.4), p(0.24, 0.44), p(0.24, 0.56), p(0.08, 0.62), p(0.02, 0.6)], fill=255)
    e.rectangle((*p(0.22, 0.42), *p(0.56, 0.56)), fill=255)
    e.rectangle((*p(0.54, 0.44), *p(0.8, 0.54)), fill=255)
    e.rectangle((*p(0.78, 0.47), *p(1.0, 0.51)), fill=255)
    e.rectangle((*p(0.3, 0.31), *p(0.5, 0.35)), fill=255)
    e.rectangle((*p(0.3, 0.33), *p(0.34, 0.43)), fill=255)
    e.rectangle((*p(0.47, 0.33), *p(0.5, 0.43)), fill=255)
    e.polygon([p(0.4, 0.55), p(0.5, 0.55), p(0.47, 0.82), p(0.36, 0.8)], fill=255)
    e.polygon([p(0.25, 0.55), p(0.33, 0.55), p(0.31, 0.72), p(0.23, 0.7)], fill=255)
    for x in (0.6, 0.66, 0.72):
        e.rectangle((*p(x, 0.46), *p(x + 0.025, 0.52)), fill=0)
    r = im.rotate(28, resample=Image.BICUBIC, center=p(0.5, 0.52))
    d._image.paste(r, (0, 0), r)


def missoes(d):
    caixa(d, 0.18, 0.14, 0.82, 0.94, 0.06)
    caixa(d, 0.35, 0.05, 0.65, 0.22, 0.03)
    caixa(d, 0.26, 0.26, 0.74, 0.86, 0.02, fill=0)
    for y in (0.36, 0.54, 0.72):
        linha(d, [(0.3, y), (0.35, y + 0.05), (0.42, y - 0.05)], 0.03)
        caixa(d, 0.48, y - 0.02, 0.7, y + 0.03, 0.01)


def carreira(d):
    estrela(d, 0.5, 0.2, 0.16)
    for y in (0.46, 0.63, 0.8):
        linha(d, [(0.14, y + 0.12), (0.5, y - 0.06), (0.86, y + 0.12)], 0.085)


def perfil(d):
    # capacete e ombros de um soldado
    x0, y0 = p(0.2, 0.06)
    x1, y1 = p(0.8, 0.66)
    d.pieslice((x0, y0, x1, y1), 180, 360, fill=255)
    caixa(d, 0.13, 0.34, 0.87, 0.41, 0.02)
    caixa(d, 0.32, 0.42, 0.68, 0.64, 0.05)
    d.polygon(
        [p(0.06, 0.97), p(0.14, 0.76), p(0.36, 0.67), p(0.64, 0.67), p(0.86, 0.76), p(0.94, 0.97)],
        fill=255,
    )


def tutorial(d):
    d.polygon([p(0.05, 0.2), p(0.47, 0.28), p(0.47, 0.9), p(0.05, 0.82)], fill=255)
    d.polygon([p(0.95, 0.2), p(0.53, 0.28), p(0.53, 0.9), p(0.95, 0.82)], fill=255)
    for y in (0.38, 0.5, 0.62):
        linha(d, [(0.13, y - 0.03), (0.39, y + 0.02)], 0.03)
        d.line([p(0.87, y - 0.03), p(0.61, y + 0.02)], fill=0, width=int(0.03 * T))
    for y in (0.38, 0.5, 0.62):
        d.line([p(0.13, y - 0.03), p(0.39, y + 0.02)], fill=0, width=int(0.03 * T))


def loja(d):
    # caixote de madeira: tábuas e travessa em diagonal
    caixa(d, 0.08, 0.14, 0.92, 0.9, 0.03)
    caixa(d, 0.2, 0.26, 0.8, 0.78, 0.01, fill=0)
    d.polygon(
        [p(0.2, 0.7), p(0.72, 0.26), p(0.8, 0.26), p(0.8, 0.34), p(0.28, 0.78), p(0.2, 0.78)],
        fill=255,
    )


def armario(d):
    caixa(d, 0.16, 0.05, 0.84, 0.95, 0.04)
    caixa(d, 0.485, 0.05, 0.515, 0.95, 0.002, fill=0)
    for x in (0.24, 0.56):
        for y in (0.13, 0.19, 0.25):
            caixa(d, x, y, x + 0.2, y + 0.03, 0.008, fill=0)
        caixa(
            d,
            x + 0.14 if x < 0.5 else x,
            0.5,
            x + 0.2 if x < 0.5 else x + 0.06,
            0.62,
            0.012,
            fill=0,
        )


def passe(d):
    d.polygon(
        [
            p(0.05, 0.25),
            p(0.95, 0.25),
            p(0.95, 0.42),
            p(0.87, 0.5),
            p(0.95, 0.58),
            p(0.95, 0.75),
            p(0.05, 0.75),
            p(0.05, 0.58),
            p(0.13, 0.5),
            p(0.05, 0.42),
        ],
        fill=255,
    )
    for y in (0.3, 0.4, 0.5, 0.6, 0.67):
        caixa(d, 0.3, y, 0.33, y + 0.05, 0.004, fill=0)
    estrela(d, 0.62, 0.5, 0.19, fill=0)


def configuracoes(d):
    for i in range(8):
        a = i * math.pi / 4
        c, s = math.cos(a), math.sin(a)
        linha(d, [(0.5 + 0.28 * c, 0.5 + 0.28 * s), (0.5 + 0.41 * c, 0.5 + 0.41 * s)], 0.13)
    disco(d, 0.5, 0.5, 0.33)
    disco(d, 0.5, 0.5, 0.15, fill=0)
    anel(d, 0.5, 0.5, 0.26, 0.015)


ICONES: dict[str, Callable] = {
    "arsenal": arsenal,
    "missoes": missoes,
    "carreira": carreira,
    "perfil": perfil,
    "tutorial": tutorial,
    "loja": loja,
    "armario": armario,
    "passe": passe,
    "configuracoes": configuracoes,
}


def gerar(nome: str, fn: Callable) -> None:
    m = Image.new("L", (T, T), 0)
    fn(ImageDraw.Draw(m))
    m = m.resize((LADO, LADO), Image.LANCZOS)
    corpo = dourado(m)
    sombra = Image.new("RGBA", (LADO, LADO), (0, 0, 0, 0))
    preto = Image.new("RGBA", (LADO, LADO), (10, 7, 3, 215))
    sombra.paste(preto, (0, 3), m.filter(ImageFilter.GaussianBlur(2.2)))
    Image.alpha_composite(sombra, corpo).save(SAIDA / f"menu_{nome}.png", optimize=True)


def principal() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    for nome, fn in ICONES.items():
        gerar(nome, fn)
    print("ok", len(ICONES))


if __name__ == "__main__":
    principal()
