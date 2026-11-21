"""Georreferencia a carta AMS L7014 6739 I (GeoPDF do USGS/NGA) a partir do LGIDict.

O GeoPDF traz pontos de registro (x, y em pontos PDF -> E, N em metros) no datum
ING-A (Indian 1960, Vietnã ~16°N; elipsoide Everest 1830) e grade UTM zona 49N.
Ajustamos uma afim por mínimos quadrados, reportamos o resíduo e gravamos um GeoTIFF
em EPSG:3149 (Indian 1960 / UTM 49N) a partir do PNG renderizado pelo pdftoppm.

Uso: uv run python tools/georef_carta.py <png> <dpi> <saida.tif> [E0 N0 E1 N1]
"""

from __future__ import annotations

import sys

import numpy as np
import rasterio
from PIL import Image
from rasterio.transform import Affine
from rasterio.windows import Window

Image.MAX_IMAGE_PIXELS = None

PAGE_H_PT = 2087.04
# Pontos de registro do LGIDict "L701467391_003" (x_pt, y_pt, E, N), copiados do PDF.
REG = np.array(
    [
        (55.312561, 2022.539917, 258658.955206, 1714759.063826),
        (1578.188965, 2022.539917, 285484.615582, 1714493.059011),
        (52.875046, 455.413483, 258370.728107, 1687090.903450),
        (1577.251465, 456.163483, 285228.477728, 1686828.773175),
        (561.938049, 977.976501, 267415.752468, 1696222.307043),
        (562.125549, 1500.539429, 267508.261863, 1705444.579657),
        (1069.500977, 978.164001, 276364.783604, 1696134.499325),
    ]
)


def fit_affine(dpi: float) -> tuple[Affine, np.ndarray]:
    s = dpi / 72.0
    px = REG[:, 0] * s
    py = (PAGE_H_PT - REG[:, 1]) * s
    A = np.column_stack([px, py, np.ones_like(px)])
    ce, *_ = np.linalg.lstsq(A, REG[:, 2], rcond=None)
    cn, *_ = np.linalg.lstsq(A, REG[:, 3], rcond=None)
    res = np.hypot(A @ ce - REG[:, 2], A @ cn - REG[:, 3])
    return Affine(ce[0], ce[1], ce[2], cn[0], cn[1], cn[2]), res


def main() -> None:
    png, dpi, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
    tr, res = fit_affine(dpi)
    print(f"afim: {tr}\nresíduos nos 7 pontos de registro (m): {np.round(res, 2)}")
    img = np.asarray(Image.open(png).convert("RGB"))
    h, w, _ = img.shape
    col0, row0, col1, row1 = 0, 0, w, h
    if len(sys.argv) == 8:
        e0, n0, e1, n1 = map(float, sys.argv[4:8])
        inv = ~tr
        cs, rs = zip(*[inv * (e, n) for e in (e0, e1) for n in (n0, n1)], strict=True)
        col0, col1 = max(0, int(min(cs))), min(w, int(max(cs)) + 1)
        row0, row1 = max(0, int(min(rs))), min(h, int(max(rs)) + 1)
    sub = img[row0:row1, col0:col1]
    win_tr = rasterio.windows.transform(Window(col0, row0, col1 - col0, row1 - row0), tr)
    with rasterio.open(
        out,
        "w",
        driver="GTiff",
        width=sub.shape[1],
        height=sub.shape[0],
        count=3,
        dtype="uint8",
        crs="EPSG:3149",
        transform=win_tr,
        compress="deflate",
        tiled=True,
    ) as dst:
        dst.write(np.moveaxis(sub, -1, 0))
    print(f"gravado {out}: {sub.shape[1]}x{sub.shape[0]} px")


if __name__ == "__main__":
    main()
