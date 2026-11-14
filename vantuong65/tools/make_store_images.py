"""Imagens da página do jogo no formato do Roblox (F6), a partir da arte do ForgeGUI.

- Ícone 512x512: os ícones gerados vieram com cantos arredondados brancos embutidos (~50 px na
  diagonal, raio ~171 px em 1024). O Roblox arredonda o ícone sozinho, então o branco viraria
  borda. Recorte de 56 px por lado tira todo o branco (calculado: a 52 px já não há branco).
- Miniatura 16:9: a key art tem 1376x768 (1,792:1). Recorte central para 1365x768 (16:9 exato),
  sem ampliar: ampliar não cria detalhe.

Uso: uv run python tools/make_store_images.py   (a partir de vantuong65/)
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

MKT = Path(__file__).resolve().parent.parent / "assets/forgegui/marketing"
OUT = MKT / "roblox"
ICON_INSET = 56


def icon(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    im = im.crop((ICON_INSET, ICON_INSET, w - ICON_INSET, h - ICON_INSET))
    im = im.resize((512, 512), Image.Resampling.LANCZOS)
    a = np.asarray(im)
    corners = [a[0, 0], a[0, -1], a[-1, 0], a[-1, -1]]
    assert all(c.min() < 248 for c in corners), "sobrou canto branco"
    im.save(dst, optimize=True)


def thumbnail(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    tw = round(h * 16 / 9)
    assert tw <= w, "a key art é mais estreita que 16:9"
    x0 = (w - tw) // 2
    im.crop((x0, 0, x0 + tw, h)).save(dst, quality=92, optimize=True)


def main() -> None:
    OUT.mkdir(exist_ok=True)
    icon(MKT / "icone_jogo_a.jpg", OUT / "icone_512.png")
    icon(MKT / "icone_jogo_b.jpg", OUT / "icone_512_alternativo.png")
    thumbnail(MKT / "capa_keyart.jpg", OUT / "miniatura_1_16x9.jpg")
    for f in sorted(OUT.iterdir()):
        print(f.name, Image.open(f).size)


if __name__ == "__main__":
    main()
