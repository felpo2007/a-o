"""Logo e fundo do lobby a partir do key art do dono (D-250).

- assets/ui/marca/logo.png: o título STARLITE VIETNÃ 1965 do key art, com fundo transparente;
- assets/ui/marca/fundo_{nw,ne,sw,se}.png: a cena sem o título, em 16:9 (2048 x 1152, em 4 blocos).

Uso (a partir de vantuong65):
    uv run --group arte python tools/marca_lobby.py <key_art.jpg>
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter
from scipy import ndimage

SAIDA = Path(__file__).resolve().parents[1] / "assets" / "ui" / "marca"


def logo(arte: Image.Image) -> Image.Image:
    corte = arte.crop((70, 800, 1210, 1200))
    k = 2
    grande = corte.resize((corte.width * k, corte.height * k), Image.LANCZOS)
    a = np.asarray(grande, dtype=np.float32)
    lum = a @ np.array([0.299, 0.587, 0.114])
    sat = (a.max(axis=2) - a.min(axis=2)) / np.maximum(a.max(axis=2), 1)
    # letra: clara e pouco saturada; a folhagem é verde e o sol, saturado
    m = np.clip((lum - 118) / 58, 0, 1) * np.clip((0.62 - sat) / 0.2, 0, 1)
    base = m > 0.45
    # fecha as rachaduras da tinta e fica só com os blocos grandes (as letras e os filetes)
    fechado = ndimage.binary_closing(base, iterations=5)
    rotulos, n = ndimage.label(fechado)
    tam = ndimage.sum(fechado, rotulos, range(1, n + 1))
    caixas = ndimage.find_objects(rotulos)
    fica = np.zeros(n + 1, dtype=bool)
    for i, (t, c) in enumerate(zip(tam, caixas, strict=True), 1):
        alto, largo = c[0].stop - c[0].start, c[1].stop - c[1].start
        if t >= 900 and (alto >= 60 or largo >= 200):
            fica[i] = True
    # o til do Ã é pequeno: entra se estiver logo acima de uma letra da segunda linha
    meio = fechado.shape[0] * 0.55
    letras = [c for i, c in enumerate(caixas, 1) if fica[i] and c[0].start > meio]
    for i, (t, c) in enumerate(zip(tam, caixas, strict=True), 1):
        if fica[i] or t < 60 or c[0].stop < meio * 0.9:
            continue
        cx = (c[1].start + c[1].stop) / 2
        if any(
            ln[1].start <= cx <= ln[1].stop and 0 <= ln[0].start - c[0].stop <= 34 for ln in letras
        ):
            fica[i] = True
    area = ndimage.binary_dilation(fica[rotulos], iterations=3)
    alfa = ndimage.gaussian_filter(np.clip(m * 1.5, 0, 1) * area, 0.8)
    # cor das letras: creme de tinta velha, com o desgaste original
    cor = a.copy()
    cor[alfa < 0.5] = (255, 240, 205)
    saida = np.dstack((cor, alfa * 255)).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(saida, "RGBA")
    caixa = im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    im = im.crop(caixa)
    w = 1000
    return im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)


def fundo(arte: Image.Image) -> Image.Image:
    W, H = 2048, 1152
    # a cena acima do título
    cena = arte.crop((0, 0, 1254, 792))
    alt = H
    larg = round(cena.width * alt / cena.height)
    meio = cena.resize((larg, alt), Image.LANCZOS)
    tela = cena.resize((W, round(W * cena.height / cena.width)), Image.LANCZOS)
    tela = tela.crop((0, (tela.height - H) // 2, W, (tela.height - H) // 2 + H))
    tela = tela.filter(ImageFilter.GaussianBlur(38))
    tela = ImageEnhance.Brightness(tela).enhance(0.72)
    masc = np.ones((alt, larg), dtype=np.float32)
    faixa = 150
    x = np.minimum(np.arange(larg), np.arange(larg)[::-1]) / faixa
    masc *= np.clip(x, 0, 1) ** 1.3
    tela.paste(meio, ((W - larg) // 2, 0), Image.fromarray((masc * 255).astype(np.uint8), "L"))
    return ImageEnhance.Color(tela).enhance(1.06)


def principal() -> None:
    arte = Image.open(sys.argv[1]).convert("RGB")
    SAIDA.mkdir(parents=True, exist_ok=True)
    lg = logo(arte)
    lg.save(SAIDA / "logo.png", optimize=True)
    f = fundo(arte)
    f.convert("RGB").save(SAIDA / "fundo_previa.jpg", quality=88)
    for nome, x, y in (("nw", 0, 0), ("ne", 1024, 0), ("sw", 0, 576), ("se", 1024, 576)):
        f.crop((x, y, x + 1024, y + 576)).save(SAIDA / f"fundo_{nome}.png", optimize=True)
    print("ok", lg.size, f.size)


if __name__ == "__main__":
    principal()
