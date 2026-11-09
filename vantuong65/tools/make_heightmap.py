"""Gera o heightmap 16-bit (PNG) da área jogável + margem, e o do horizonte, a partir do
Copernicus GLO-30 (DSM, 30 m), no quadro local do jogo (origem no centro, norte para cima).

ATENÇÃO: GLO-30 é modelo de SUPERFÍCIE (copas e telhados entram na altura). Aplicamos uma
abertura morfológica de 70 m (remove copas e casas isoladas sem achatar colinas de
~400 m como a Colina 43) e suavização gaussiana. É um heightmap v0 para o greybox: o DTM
definitivo virá das curvas de nível de 1965 vetorizadas (research/F0_GEORREF.md, passo 6).

Uso: uv run python tools/make_heightmap.py
Saídas em research/heightmap/: *.png (16-bit, cinza) + *.json (escala e alturas).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
from geo import PLAY_ING, STUD_M, ing_to_wgs_utm, play_center_wgs  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DEM = ROOT / "research/dem/Copernicus_DSM_COG_10_N15_00_E108_00_DEM.tif"
OUT = ROOT / "research/heightmap"


def warp_dem(cE: float, cN: float, w_m: float, h_m: float, res: float) -> np.ndarray:
    w, h = int(round(w_m / res)), int(round(h_m / res))
    tr = from_origin(cE - w_m / 2, cN + h_m / 2, res, res)
    out = np.full((h, w), np.nan, dtype=np.float32)
    with rasterio.open(DEM) as src:
        reproject(
            rasterio.band(src, 1),
            out,
            src_transform=src.transform,
            src_crs=src.crs,
            dst_transform=tr,
            dst_crs="EPSG:32649",
            resampling=Resampling.cubic,
            dst_nodata=np.nan,
        )
    return out


def to_png16(z: np.ndarray, name: str, meta: dict) -> None:
    zmin, zmax = float(np.nanmin(z)), float(np.nanmax(z))
    q = np.round((z - zmin) / (zmax - zmin) * 65535).astype(np.uint16)
    Image.fromarray(q).save(OUT / f"{name}.png")  # uint16 -> PNG cinza 16-bit
    meta.update(
        {
            "arquivo": f"{name}.png",
            "bits": 16,
            "largura_px": int(z.shape[1]),
            "altura_px": int(z.shape[0]),
            "altura_min_m": round(zmin, 2),
            "altura_max_m": round(zmax, 2),
            "altura_min_studs": round(zmin / STUD_M, 1),
            "altura_max_studs": round(zmax / STUD_M, 1),
            "valor_0": "altura_min",
            "valor_65535": "altura_max",
            "orientacao": "norte para cima (-Z no Roblox), leste para a direita (+X)",
        }
    )
    (OUT / f"{name}.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    print(name, z.shape, f"{zmin:.1f}..{zmax:.1f} m")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    cE, cN = play_center_wgs()
    e0, n0, e1, n1 = PLAY_ING
    w_play, h_play = e1 - e0, n1 - n0
    margem = 500.0
    res = 8 * STUD_M  # 1 pixel = 8 studs = 2,24 m (2 voxels de terreno)
    z = warp_dem(cE, cN, w_play + 2 * margem, h_play + 2 * margem, res)
    # supressão de copas/casas e suavização
    k = int(round(70 / res)) | 1
    z = ndimage.grey_opening(z, size=(k, k))
    z = ndimage.gaussian_filter(z, sigma=15 / res)
    z = np.maximum(z, -3.0)  # fundo do mar raso; a água do mar é água de terreno
    to_png16(
        z,
        "heightmap_area_v0",
        {
            "fonte": "Copernicus GLO-30 DSM (tile N15 E108), (c) DLR e.V. 2010-2014 e (c) Airbus"
            " Defence and Space GmbH 2014-2018, Copernicus/ESA",
            "processamento": "reprojeção cúbica p/ WGS84 UTM49N; abertura 70 m;"
            " gauss 15 m; min -3 m",
            "centro_wgs84_utm49": [round(cE, 1), round(cN, 1)],
            "area_jogavel_m": [w_play, h_play],
            "margem_m": margem,
            "tamanho_m": [w_play + 2 * margem, h_play + 2 * margem],
            "tamanho_studs": [
                round((w_play + 2 * margem) / STUD_M),
                round((h_play + 2 * margem) / STUD_M),
            ],
            "metros_por_px": res,
            "studs_por_px": 8,
            "datum_vertical": "EGM2008 (nível médio do mar ~0 m)",
            "status": "v0 provisório (DSM); substituir pelo DTM das curvas de 1965",
        },
    )
    hz = warp_dem(cE, cN, 14000, 14000, 30.0)
    hz = np.maximum(ndimage.gaussian_filter(hz, 1.0), -3.0)
    to_png16(
        hz,
        "heightmap_horizonte_v0",
        {
            "fonte": "Copernicus GLO-30 DSM",
            "centro_wgs84_utm49": [round(cE, 1), round(cN, 1)],
            "tamanho_m": [14000, 14000],
            "tamanho_studs": [round(14000 / STUD_M)] * 2,
            "metros_por_px": 30.0,
            "studs_por_px": round(30 / STUD_M, 2),
            "uso": "anel de terreno distante em baixa resolução (fora da área jogável)",
        },
    )
    # conferência: a área jogável no heightmap, em pixels
    E0, N0 = ing_to_wgs_utm(e0, n0)
    print(f"canto SW da área jogável em WGS84 UTM: ({E0:.0f},{N0:.0f}); centro ({cE:.0f},{cN:.0f})")


if __name__ == "__main__":
    main()
