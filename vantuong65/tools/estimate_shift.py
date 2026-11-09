"""Estima o deslocamento sistemático (dx, dy) da carta de 1965 após a troca de datum,
por casamento de chanfro (chamfer matching) em dois sinais independentes:

1. Curvas de nível da carta (traço marrom) contra isolinhas de 10 m do DEM Copernicus.
2. Linha d'água da carta (borda do mar azul) contra a borda de água do Sentinel-2 (NDWI>0),
   só nos trechos rochosos (a praia arenosa mudou em 60 anos e é excluída).

Saída: deslocamento ótimo de cada sinal e superfície de custo (para ver se o mínimo é nítido).
Uso: uv run python tools/estimate_shift.py
"""

from __future__ import annotations

import sys

import numpy as np
import rasterio
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject
from scipy import ndimage

sys.path.insert(0, __file__.rsplit("/", 1)[0])
RES_DIR = __file__.rsplit("/", 2)[0] + "/research/"
from reproj_carta import ING_A_UTM49  # noqa: E402

E0, N0, E1, N1, RES = 264000, 1688500, 273500, 1696500, 5.0
W, H = int((E1 - E0) / RES), int((N1 - N0) / RES)
TR = from_origin(E0, N1, RES, RES)


def warp(
    path: str, crs=None, bands=(1, 2, 3), resampling=Resampling.bilinear, dtype=np.float32
) -> np.ndarray:
    with rasterio.open(path) as src:
        out = np.zeros((len(bands), H, W), dtype=dtype)
        for i, b in enumerate(bands):
            reproject(
                rasterio.band(src, b),
                out[i],
                src_transform=src.transform,
                src_crs=crs or src.crs,
                dst_transform=TR,
                dst_crs="EPSG:32649",
                resampling=resampling,
            )
    return out


def chamfer(src_mask: np.ndarray, dist: np.ndarray, rng: int, step: int) -> tuple:
    ys, xs = np.nonzero(src_mask)
    best, best_s = None, None
    surf = {}
    for dy in range(-rng, rng + 1, step):
        for dx in range(-rng, rng + 1, step):
            x = xs + dx
            y = ys + dy
            ok = (x >= 0) & (x < W) & (y >= 0) & (y < H)
            c = np.median(dist[y[ok], x[ok]])  # mediana: robusta a mudanças reais do terreno
            surf[(dx, dy)] = c
            if best is None or c < best:
                best, best_s = c, (dx, dy)
    return best_s, best, surf


def main() -> None:
    carta = warp(RES_DIR + "carta/carta_area_batalha.tif", crs=ING_A_UTM49).astype(np.int16)
    mx = carta.max(axis=0)
    r, g, b = carta
    brown = (r > b + 50) & (mx < 200) & (g < 150)
    blue = (b > r + 25) & (mx > 120)
    # mar = maior componente azul conectado (após fechar o pontilhado)
    sea = ndimage.binary_closing(blue, iterations=3)
    lab, n = ndimage.label(sea)
    sizes = ndimage.sum(sea, lab, range(1, n + 1))
    sea = lab == (1 + int(np.argmax(sizes)))
    sea = ndimage.binary_fill_holes(sea)

    dem = warp(RES_DIR + "dem/Copernicus_DSM_COG_10_N15_00_E108_00_DEM.tif", bands=(1,))[0]
    lvl = np.floor(dem / 10.0)
    iso = (np.abs(np.diff(lvl, axis=0, prepend=lvl[:1])) > 0) | (
        np.abs(np.diff(lvl, axis=1, prepend=lvl[:, :1])) > 0
    )
    iso &= dem > 8  # ignora a planície (ruído do DSM perto do nível do mar)
    dist_iso = ndimage.distance_transform_edt(~iso) * RES

    ndwi = warp(RES_DIR + "sat/S2C_20250327_NDWI_area.tif", bands=(1,))[0]
    water = ndimage.binary_opening(ndwi > 0.0, iterations=1)
    lab, n = ndimage.label(water)
    sizes = ndimage.sum(water, lab, range(1, n + 1))
    water = lab == (1 + int(np.argmax(sizes)))
    edge_s2 = water ^ ndimage.binary_erosion(water)
    dist_coast = ndimage.distance_transform_edt(~edge_s2) * RES
    edge_map = sea ^ ndimage.binary_erosion(sea)
    # trechos rochosos: costa da carta perto de relevo (DEM > 15 m num raio de 150 m)
    high = ndimage.maximum_filter(dem, size=int(300 / RES)) > 15
    rocky = edge_map & high

    print(f"pixels de curva de nível na carta: {brown.sum()}, costa rochosa: {rocky.sum()}")
    for name, mask, dist in (
        ("curvas de nível x DEM", brown & (dem > 8), dist_iso),
        ("costa rochosa x NDWI", rocky, dist_coast),
    ):
        (dx, dy), c, surf = chamfer(mask, dist, rng=50, step=2)
        c0 = surf[(0, 0)]
        print(
            f"{name}: deslocamento ótimo dE={dx * RES:+.0f} m, dN={-dy * RES:+.0f} m; "
            f"custo mediano {c:.1f} m (sem deslocamento: {c0:.1f} m)"
        )
        # nitidez do mínimo: custo a ±25 m do ótimo
        for ddx, ddy in ((5, 0), (-5, 0), (0, 5), (0, -5)):
            k = (dx + ddx, dy + ddy)
            if k in surf:
                print(f"   custo em ({(k[0]) * RES:+.0f},{-(k[1]) * RES:+.0f}) m: {surf[k]:.1f}")


if __name__ == "__main__":
    main()
