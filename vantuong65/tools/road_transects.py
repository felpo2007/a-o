"""Mede o deslocamento perpendicular entre estradas da carta de 1965 (já no WGS 84 pela
troca de datum ING-A) e as mesmas estradas no Sentinel-2, por transectos.

Para cada trecho reto: transectos a cada 10 m, ±60 m, passo de 1 m. Na carta, o centro da
estrada é o centróide do traço escuro do símbolo (casco duplo + preenchimento); no
Sentinel-2, o centróide do excesso de brilho sobre a vizinhança. A diferença projetada na
normal do trecho é o erro perpendicular naquele ponto de controle.

Uso: uv run python tools/road_transects.py
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

E0, N0, E1, N1, RES = 266800, 1690300, 269500, 1692600, 1.0
W, H = int((E1 - E0) / RES), int((N1 - N0) / RES)
TR = from_origin(E0, N1, RES, RES)

# Trechos (WGS 84 / UTM 49N) da Rota 523 e do ramal até ela, lidos na sobreposição.
SEGMENTS = {
    "523 SE (NW-SE)": ((268180, 1691440), (268980, 1690810)),
    "523 NW (NW-SE)": ((267340, 1691840), (267640, 1691460)),
    "ramal ENE": ((267760, 1691402), (267980, 1691454)),
}


def warp(path: str, crs=None, bands=(1, 2, 3)) -> np.ndarray:
    with rasterio.open(path) as src:
        out = np.zeros((len(bands), H, W), dtype=np.float32)
        for i, b in enumerate(bands):
            reproject(
                rasterio.band(src, b),
                out[i],
                src_transform=src.transform,
                src_crs=crs or src.crs,
                dst_transform=TR,
                dst_crs="EPSG:32649",
                resampling=Resampling.bilinear,
            )
    return out


def sample(img: np.ndarray, e: np.ndarray, n: np.ndarray) -> np.ndarray:
    col = (e - E0) / RES - 0.5
    row = (N1 - n) / RES - 0.5
    return ndimage.map_coordinates(img, [row, col], order=1, mode="nearest")


def centroid(p: np.ndarray, off: np.ndarray, core: np.ndarray) -> float:
    """Centróide do excesso sobre o percentil 30, restrito ao núcleo do transecto."""
    q = p - np.percentile(p[core], 30)
    q[~core] = 0
    q[q < 0] = 0
    return float((off * q).sum() / q.sum())


def main() -> None:
    m = warp(RES_DIR + "carta/carta_area_batalha.tif", crs=ING_A_UTM49)
    s = warp(RES_DIR + "sat/S2C_20250327_TCI_area.tif").mean(axis=0)
    # "tinta" da estrada na carta: tudo que não é papel claro nem azul/verde de fundo
    r, g, b = m
    ink = ((r + g + b) / 3 < 200) & ~(b > r + 25) & ~((g > r + 10) & (g > b + 10))
    ink = ink.astype(np.float32)
    off = np.arange(-60, 61, 1.0)
    rows = []
    for name, (p0, p1) in SEGMENTS.items():
        p0, p1 = np.array(p0, float), np.array(p1, float)
        L = np.linalg.norm(p1 - p0)
        t = (p1 - p0) / L
        nrm = np.array([-t[1], t[0]])
        prof_m, prof_s = [], []
        for d in np.arange(10, L - 10, 10):
            c = p0 + t * d
            e = c[0] + off * nrm[0]
            n = c[1] + off * nrm[1]
            prof_m.append(sample(ink, e, n))
            prof_s.append(sample(s, e, n))
        pm, ps = np.mean(prof_m, axis=0), np.mean(prof_s, axis=0)
        core = np.abs(off) <= 30

        cm, cs = centroid(pm, off, core), centroid(ps, off, core)
        rows.append((name, nrm, cs - cm))
        print(
            f"{name}: comprimento {L:.0f} m, {len(prof_m)} transectos; centro carta {cm:+.1f} m,"
            f" centro S2 {cs:+.1f} m -> erro perpendicular {cs - cm:+.1f} m"
            f" (normal {nrm.round(2)})"
        )
    A = np.array([r[1] for r in rows])
    y = np.array([r[2] for r in rows])
    sol, *_ = np.linalg.lstsq(A, y, rcond=None)
    print(
        f"deslocamento 2D estimado (S2 - carta): dE {sol[0]:+.1f} m, dN {sol[1]:+.1f} m;"
        f" resíduos {np.round(A @ sol - y, 1)}"
    )


if __name__ == "__main__":
    main()
