"""Limpa a sombra das imagens da loja (D-124), depois do `tools/blender/loja.py`.

O apanhador de sombra do Cycles deixa um véu fraco de alfa na imagem inteira (luz de área grande e
o céu): sobre o fundo colorido do cartão, ele desenhava um retângulo escuro (Studio, v56). Aqui:
- o objeto (alfa >= 0,98) fica como está;
- na sombra, o véu abaixo de 12% some e o resto vai a no máximo 70%;
- perto das bordas da imagem (8%), a sombra desce até zero.

Uso:
    uv run --group arte python tools/loja_sombra.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

PASTA = Path(__file__).resolve().parents[1] / "assets" / "ui" / "loja"
NOMES = ("usmc", "vc", "elite", "m151", "m35", "peugeot403")
VEU = 0.12
MAX_SOMBRA = 0.70
BORDA = 0.08


def suave(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def limpar(caminho: Path) -> dict:
    im = np.asarray(Image.open(caminho).convert("RGBA")).astype(np.float64) / 255.0
    a = im[:, :, 3]
    h, w = a.shape
    objeto = a >= 0.98
    s = np.clip((a - VEU) / (1 - VEU), 0, 1) * MAX_SOMBRA
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    borda = suave(np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y)) / BORDA)
    novo = np.where(objeto, a, s * borda)
    im[:, :, 3] = novo
    Image.fromarray((im * 255 + 0.5).astype(np.uint8), "RGBA").save(caminho, optimize=True)
    return {
        "arquivo": caminho.name,
        "meio_antes": int(((a > 0.01) & (a < 0.98)).sum()),
        "meio_depois": int(((novo > 0.01) & (novo < 0.98)).sum()),
        "borda_max": float(max(novo[0].max(), novo[-1].max(), novo[:, 0].max(), novo[:, -1].max())),
    }


def main() -> None:
    for n in NOMES:
        print(limpar(PASTA / f"{n}.png"))


if __name__ == "__main__":
    main()
