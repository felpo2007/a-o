"""Moldes clássicos de roupa: tamanho do Roblox, regiões opacas e fundo transparente."""

from pathlib import Path

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FILES = sorted((ROOT / "assets/clothing").glob("*.png"))


def test_seis_moldes():
    assert len(FILES) == 6


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_molde(path):
    im = Image.open(path)
    assert im.size == (585, 559)
    assert im.mode == "RGBA"
    alpha = im.getchannel("A")
    assert alpha.getpixel((295, 138)) == 255  # frente do tronco
    assert alpha.getpixel((10, 10)) == 0  # fora das regiões
