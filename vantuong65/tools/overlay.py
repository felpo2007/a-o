"""Sobrepõe o traço da carta de 1965 (pixels escuros e coloridos) ao Sentinel-2.

Uso: uv run python tools/overlay.py <carta_utm.tif> <s2.tif> E0 N0 E1 N1 <saida.png> [res] [dx dy]
dx, dy: deslocamento (m) aplicado à carta antes de sobrepor (teste de correção).
"""

from __future__ import annotations

import sys

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from reproj_carta import ING_A_UTM49  # noqa: E402


def load(path: str, tr, w: int, h: int, dx: float = 0.0, dy: float = 0.0) -> np.ndarray:
    with rasterio.open(path) as src:
        out = np.zeros((3, h, w), dtype=np.uint8)
        st = src.transform
        # EPSG:3149 sozinho deixa o PROJ escolher a transformação de datum; forçamos ING-A
        crs = ING_A_UTM49 if src.crs and src.crs.to_epsg() == 3149 else src.crs
        st = rasterio.Affine(st.a, st.b, st.c + dx, st.d, st.e, st.f + dy)
        for b in range(3):
            reproject(
                rasterio.band(src, b + 1),
                out[b],
                src_transform=st,
                src_crs=crs,
                dst_transform=tr,
                dst_crs="EPSG:32649",
                resampling=Resampling.bilinear,
            )
    return np.moveaxis(out, 0, -1)


def main() -> None:
    carta, s2 = sys.argv[1], sys.argv[2]
    e0, n0, e1, n1 = map(float, sys.argv[3:7])
    out = sys.argv[7]
    res = float(sys.argv[8]) if len(sys.argv) > 8 else 2.5
    dx = float(sys.argv[9]) if len(sys.argv) > 9 else 0.0
    dy = float(sys.argv[10]) if len(sys.argv) > 10 else 0.0
    w, h = int((e1 - e0) / res), int((n1 - n0) / res)
    tr = from_origin(e0, n1, res, res)
    m = load(carta, tr, w, h, dx, dy).astype(np.int16)
    s = load(s2, tr, w, h).astype(np.float32)
    # realce do Sentinel-2 (TCI é escuro)
    s = np.clip((s - 20) * 2.2, 0, 255)
    mx, mn = m.max(axis=2), m.min(axis=2)
    black = (mx < 110) & (mx - mn < 45)  # quadrícula, casas, trilhas
    blue = (m[..., 2] > m[..., 0] + 40) & (m[..., 2] > 120) & (mx < 230)  # água
    brown = (m[..., 0] > m[..., 2] + 50) & (mx < 200) & (m[..., 1] < 150)  # curvas de nível
    img = s.copy()
    img[black] = [255, 40, 40]
    img[blue] = [40, 200, 255]
    img[brown] = [255, 200, 0]
    im = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(im)
    step = 500
    for e in np.arange(np.ceil(e0 / step) * step, e1 + 1, step):
        x = (e - e0) / res
        d.line([(x, 0), (x, h)], fill=(255, 255, 255), width=1)
        d.text((x + 2, 2), f"{e / 1000:.1f}", fill=(255, 255, 255))
    for n in np.arange(np.ceil(n0 / step) * step, n1 + 1, step):
        y = (n1 - n) / res
        d.line([(0, y), (w, y)], fill=(255, 255, 255), width=1)
        d.text((2, y + 2), f"{n / 1000:.1f}", fill=(255, 255, 255))
    im.save(out)
    print(out, im.size)


if __name__ == "__main__":
    main()
