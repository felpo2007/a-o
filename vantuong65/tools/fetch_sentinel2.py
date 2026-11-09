"""Baixa os recortes do Sentinel-2 L2A (cena S2C_49PBS_20250327, nuvens 0,95%) usados no controle:
TCI (cor verdadeira) e NDWI (B03/B08). COGs públicos do bucket sentinel-cogs (AWS).

Uso: uv run python tools/fetch_sentinel2.py   (a partir de vantuong65/)
"""

from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import rasterio
from rasterio.windows import from_bounds

BASE = (
    "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/49/P/BS/2025/3/"
    "S2C_49PBS_20250327_0_L2A/"
)
BOUNDS = (264000, 1688500, 273500, 1696500)  # EPSG:32649
OUT = Path(__file__).resolve().parent.parent / "research/sat"


def read(name: str):
    with rasterio.open(BASE + name) as ds:
        w = from_bounds(*BOUNDS, ds.transform)
        return ds.read(window=w), ds.window_transform(w)


def write(path: Path, a: np.ndarray, tr) -> None:
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        width=a.shape[2],
        height=a.shape[1],
        count=a.shape[0],
        dtype=a.dtype,
        crs="EPSG:32649",
        transform=tr,
        compress="deflate",
    ) as o:
        o.write(a)


def main() -> None:
    os.environ.setdefault("CURL_CA_BUNDLE", "/etc/ssl/certs/ca-certificates.crt")
    OUT.mkdir(parents=True, exist_ok=True)
    tci, tr = read("TCI.tif")
    write(OUT / "S2C_20250327_TCI_area.tif", tci, tr)
    b3, _ = read("B03.tif")
    b8, _ = read("B08.tif")
    b3, b8 = b3.astype(np.float32), b8.astype(np.float32)
    write(OUT / "S2C_20250327_NDWI_area.tif", (b3 - b8) / (b3 + b8 + 1e-6), tr)
    print("ok", tci.shape)


if __name__ == "__main__":
    main()
