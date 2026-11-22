"""Acabamento da arte dos lados (D-240): sol, raios, fumaça, brasas, cor e vinheta.

    uv run --group arte python tools/bandeiras_pos.py <pasta com os *_base.png> [destino]

O destino padrão é `assets/ui/times`. A saída é `<lado>.png`, 1280 x 720, RGB.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

RAIZ = Path(__file__).resolve().parent.parent
SOL = {"us": (0.76, 0.40), "vc": (0.24, 0.42)}
TINTA = {"us": (1.0, 0.62, 0.30), "vc": (1.0, 0.44, 0.26)}


def fbm(h: int, w: int, semente: int, oitavas: int = 6, base: int = 4) -> np.ndarray:
    rng = np.random.default_rng(semente)
    soma = np.zeros((h, w), np.float32)
    peso, total = 1.0, 0.0
    for o in range(oitavas):
        cel = base * 2**o
        g = rng.random((int(cel * h / w) + 2, cel + 2), np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        soma += np.asarray(im, np.float32) / 255 * peso
        total += peso
        peso *= 0.55
    return soma / total


def raios(brilho: np.ndarray, cx: float, cy: float, passos: int = 34) -> np.ndarray:
    """Luz que escapa do sol e passa pelos recortes (zoom radial acumulado)."""
    h, w = brilho.shape
    im = Image.fromarray((np.clip(brilho, 0, 1) * 255).astype(np.uint8))
    soma = np.zeros((h, w), np.float32)
    px, py = cx * w, cy * h
    for i in range(passos):
        k = 1 + i * 0.022
        caixa = (px - px / k, py - py / k, px + (w - px) / k, py + (h - py) / k)
        q = im.transform((w, h), Image.EXTENT, caixa, Image.BILINEAR)
        soma += np.asarray(q, np.float32) / 255 * (1 - i / passos) ** 1.5
    return soma / passos


def acabar(lado: str, fonte: Path, destino: Path) -> None:
    base = np.asarray(Image.open(fonte / f"{lado}_base.png").convert("RGB"), np.float32) / 255
    h, w = base.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = xx / w, yy / h
    cx, cy = SOL[lado]
    tinta = np.array(TINTA[lado], np.float32)
    img = base.copy()
    # a bandeira fica de fora do brilho do sol, dos raios e da fumaça: as cores têm que ler
    arq_m = fonte / f"{lado}_mask.png"
    m = Image.open(arq_m).convert("L").filter(ImageFilter.GaussianBlur(1.2))
    pano = np.asarray(m.resize((w, h)), np.float32) / 255
    fora = 1 - pano

    # o disco do sol atrás de tudo: só onde o fundo é céu claro
    dist = np.hypot((u - cx) * w / h, v - cy)
    lum = img.mean(axis=2)
    ceu = np.clip((lum - 0.16) / 0.25, 0, 1) * fora
    halo = np.exp(-((dist / 0.34) ** 2)) * 0.62 + np.exp(-((dist / 0.075) ** 2)) * 1.3
    img += (halo * ceu)[..., None] * tinta

    # raios pelos recortes
    fonte_luz = np.exp(-((dist / 0.30) ** 2)) * ceu
    r = raios(fonte_luz, cx, cy)
    img += (r * 0.62)[..., None] * tinta

    # fumaça rente ao chão, subindo pelos lados
    n1 = fbm(h, w, 11 if lado == "us" else 23)
    n2 = fbm(h, w, 12 if lado == "us" else 24, base=9)
    faixa = np.clip((v - 0.40) / 0.40, 0, 1) ** 1.3
    lados = 0.45 + 0.55 * np.abs(u - 0.5) * 2
    fumaca = np.clip((n1 * 0.7 + n2 * 0.3 - 0.44) / 0.24, 0, 1) * faixa * lados * 0.62 * fora
    cor_f = tinta * 0.40 + np.array((0.16, 0.13, 0.13), np.float32)
    img = img * (1 - fumaca[..., None]) + cor_f * fumaca[..., None]

    # brilho geral das partes claras
    claro = np.clip(img - 0.72, 0, None) * fora[..., None]
    bloom = Image.fromarray((np.clip(claro * 2.4, 0, 1) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(16)
    )
    img += np.asarray(bloom, np.float32) / 255 * 0.42

    # brasas subindo
    rng = np.random.default_rng(7 if lado == "us" else 9)
    camada = np.zeros((h, w), np.float32)
    for _ in range(105):
        x = rng.uniform(0, w)
        y = h * rng.uniform(0.18, 1.0) ** 0.8
        i, j = int(y), int(x)
        if 1 <= i < h - 2 and 1 <= j < w - 2:
            camada[i, j] = rng.uniform(0.5, 1.0)
            if rng.random() < 0.42:
                camada[i - 1, j] = camada[i, j] * 0.7
    pontos = Image.fromarray((camada * 255).astype(np.uint8))
    fino = np.asarray(pontos.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255
    largo = np.asarray(pontos.filter(ImageFilter.GaussianBlur(3.2)), np.float32) / 255
    brasa = (fino * 2.4 + largo * 3.2) * (1 - 0.8 * pano)
    img += brasa[..., None] * np.array((1.0, 0.56, 0.20), np.float32)

    # cor de cinema: sombras frias e altas quentes, contraste em S
    img = np.clip(img, 0, 1.4) / 1.4 * 1.22
    img = np.clip(img, 0, 1)
    img = img * img * (3 - 2 * img) * 0.72 + img * 0.28
    lum = img.mean(axis=2, keepdims=True)
    img += (0.5 - lum) * np.array((-0.03, 0.0, 0.05), np.float32) * 0.9
    img = lum + (img - lum) * 1.14

    # vinheta e granulação
    vin = 1 - 0.56 * np.clip(np.hypot((u - 0.5) * 1.05, (v - 0.47) * 1.15) / 0.74, 0, 1) ** 2.4
    img *= vin[..., None]
    img += (np.random.default_rng(3).normal(0, 0.009, (h, w)).astype(np.float32))[..., None]

    destino.mkdir(parents=True, exist_ok=True)
    final = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(final).save(destino / f"{lado}.png", optimize=True)
    print("ok", destino / f"{lado}.png")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("uso: bandeiras_pos.py <pasta> [destino]")
    pasta = Path(sys.argv[1])
    saida = Path(sys.argv[2]) if len(sys.argv) > 2 else RAIZ / "assets" / "ui" / "times"
    for chave in ("us", "vc"):
        acabar(chave, pasta, saida)
