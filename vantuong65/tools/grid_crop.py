"""Recorta um GeoTIFF e desenha quadrícula métrica rotulada, para ler coordenadas à vista.

Uso: uv run python tools/grid_crop.py <tif> <E0> <N0> <E1> <N1> <passo_m> <saida.png> [escala]
As coordenadas estão no CRS do próprio GeoTIFF.
"""

from __future__ import annotations

import sys

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from rasterio.windows import Window, from_bounds


def main() -> None:
    tif = sys.argv[1]
    e0, n0, e1, n1, step = map(float, sys.argv[2:7])
    out = sys.argv[7]
    scale = float(sys.argv[8]) if len(sys.argv) > 8 else 1.0
    with rasterio.open(tif) as ds:
        # janela inteira e leitura sem "boundless": a leitura boundless do rasterio desloca
        # imagens com transformação rotacionada (a carta tem ~0,5° de convergência).
        win = from_bounds(e0, n0, e1, n1, ds.transform).round_offsets().round_lengths()
        win = win.intersection(Window(0, 0, ds.width, ds.height))
        a = ds.read(window=win)
        tr = ds.window_transform(win)
    img = Image.fromarray(np.moveaxis(a[:3], 0, -1)).convert("RGB")
    if scale != 1.0:
        img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
        tr = tr * tr.scale(1 / scale, 1 / scale)
    d = ImageDraw.Draw(img)
    inv = ~tr
    e = np.ceil(e0 / step) * step
    while e <= e1:
        x0, y0 = inv * (e, n1)
        x1, y1 = inv * (e, n0)
        d.line([(x0, y0), (x1, y1)], fill=(255, 0, 255), width=1)
        d.text((x0 + 2, 2), f"{e / 1000:.1f}", fill=(200, 0, 200))
        e += step
    n = np.ceil(n0 / step) * step
    while n <= n1:
        x0, y0 = inv * (e0, n)
        x1, y1 = inv * (e1, n)
        d.line([(x0, y0), (x1, y1)], fill=(255, 0, 255), width=1)
        d.text((2, y0 + 2), f"{n / 1000:.1f}", fill=(200, 0, 200))
        n += step
    img.save(out)
    print(out, img.size)


if __name__ == "__main__":
    main()
