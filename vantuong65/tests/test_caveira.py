"""Caveira do abate (tools/make_caveira.py): tamanho, alfa, simetria e as pontes do estêncil."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import make_caveira  # noqa: E402


def test_imagem_1024_rgba_branca_com_alfa():
    im = make_caveira.build()
    assert im.size == (1024, 1024)
    assert im.mode == "RGBA"
    a = np.asarray(im.getchannel("A"), dtype=np.float32) / 255
    rgb = np.asarray(im.convert("RGB"))
    assert rgb.min() == 255  # branca: o jogo tinge pela ImageColor3
    cover = float((a > 0.5).mean())
    assert 0.2 < cover < 0.5, cover  # caveira cheia, com margem para a névoa do spray
    # as bordas da imagem ficam vazias (nada cortado no quadrado)
    assert a[:8].max() < 0.05 and a[-8:].max() < 0.05
    assert a[:, :8].max() < 0.05 and a[:, -8:].max() < 0.05


def test_olhos_e_nariz_vazados_e_dentes_com_vaos():
    m = np.asarray(make_caveira.geometry(), dtype=np.float32) / 255
    s = 1024

    def at(x: float, y: float) -> float:
        return float(m[int(y * s), int(x * s)])

    assert at(0.5, 0.25) > 0.9  # testa
    for side in (1, -1):
        assert at(0.5 + side * 0.135, 0.47) < 0.1  # órbita
    assert at(0.5, 0.6) < 0.1  # nariz
    # fileira de dentes: alterna osso e vão (pontes do estêncil)
    row = m[int(0.71 * s), int(0.40 * s) : int(0.60 * s)]
    changes = int(np.count_nonzero(np.diff((row > 0.5).astype(np.int8))))
    assert changes >= 8, changes


def test_simetrica_menos_o_reflexo():
    m = np.asarray(make_caveira.geometry(), dtype=np.float32) / 255
    s = 1024
    # o reflexo fica no alto à esquerda (y < 0,3): compara só o resto
    low = m[int(0.32 * s) :, :]
    diff = np.abs(low - low[:, ::-1]).mean()
    assert diff < 0.01, diff
