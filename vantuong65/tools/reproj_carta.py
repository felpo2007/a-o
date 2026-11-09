"""Reprojeta a carta (EPSG:3149, datum ING-A) para WGS 84 / UTM 49N (EPSG:32649)
usando a transformação de 3 parâmetros do NIMA TR8350.2 para "Indian 1960, Vietnã
(perto de 16°N)": dX=198, dY=881, dZ=317 m (precisão nominal ±25-44 m).

Uso: uv run python tools/reproj_carta.py <carta.tif> <saida.tif> E0 N0 E1 N1 [res_m]
(limites em EPSG:32649)
"""

from __future__ import annotations

import sys

import numpy as np
import rasterio
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject

ING_A_UTM49 = (
    "+proj=utm +zone=49 +a=6377276.345 +rf=300.8017 +towgs84=198,881,317,0,0,0,0 +units=m +no_defs"
)


def main() -> None:
    src_p, out_p = sys.argv[1], sys.argv[2]
    e0, n0, e1, n1 = map(float, sys.argv[3:7])
    res = float(sys.argv[7]) if len(sys.argv) > 7 else 2.5
    w, h = int((e1 - e0) / res), int((n1 - n0) / res)
    dst_tr = from_origin(e0, n1, res, res)
    with rasterio.open(src_p) as src:
        out = np.zeros((src.count, h, w), dtype=np.uint8)
        for b in range(src.count):
            reproject(
                rasterio.band(src, b + 1),
                out[b],
                src_transform=src.transform,
                src_crs=ING_A_UTM49,
                dst_transform=dst_tr,
                dst_crs="EPSG:32649",
                resampling=Resampling.bilinear,
            )
    with rasterio.open(
        out_p,
        "w",
        driver="GTiff",
        width=w,
        height=h,
        count=out.shape[0],
        dtype="uint8",
        crs="EPSG:32649",
        transform=dst_tr,
        compress="deflate",
    ) as dst:
        dst.write(out)
    print(out_p, w, h)


if __name__ == "__main__":
    main()
