"""Classifica o uso do solo na grade do jogo (16 studs = 4,48 m) a partir da carta L7014
(ed. 3, 1983) e do DEM, e detecta os símbolos de casa e o traçado dos riachos.

Classes (uint8):
  0 mar | 1 areia (praia/duna) | 2 arrozal | 3 vila/mata/sebe (verde da carta)
  4 capim/encosta (aberto, alto ou íngreme) | 5 riacho
A carta é de 1983: o uso do solo é PROVISÓRIO até a conferência com fotos de 1965 (F0 passo 8).

Uso como biblioteca: from landcover import build_grid
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject
from scipy import ndimage
from skimage.morphology import skeletonize

sys.path.insert(0, str(Path(__file__).parent))
from geo import (  # noqa: E402
    CORR_DE,
    CORR_DN,
    ING_A_UTM49,
    PLAY_ING,
    STUD_M,
    ing_to_wgs_utm,
    play_center_wgs,
)
from georef_carta import fit_affine  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
ROOT = Path(__file__).resolve().parent.parent
R = ROOT / "research"
CELL_STUDS = 16
CELL_M = CELL_STUDS * STUD_M  # 4,48 m
MARGEM_M = 500.0

SEA, SAND, PADDY, VILLAGE, GRASS, STREAM = range(6)
NOMES = ["mar", "areia", "arrozal", "vila_mata", "capim", "riacho"]


@dataclass
class Grid:
    w: int
    h: int
    e0: float  # canto NO em WGS84 UTM (borda do pixel)
    n1: float
    height_m: np.ndarray
    cls: np.ndarray
    houses: np.ndarray  # (k, 2) E, N WGS84 UTM
    stream_pts: np.ndarray  # (k, 2) E, N


def extent() -> tuple[float, float, float, float]:
    cE, cN = play_center_wgs()
    e0, n0, e1, n1 = PLAY_ING
    W, H = (e1 - e0) + 2 * MARGEM_M, (n1 - n0) + 2 * MARGEM_M
    return cE - W / 2, cN - H / 2, cE + W / 2, cN + H / 2


def _warp(path, crs, tr, w, h, bands, resampling, dtype, shift=(0.0, 0.0)):
    with rasterio.open(path) as src:
        st = src.transform
        st = rasterio.Affine(st.a, st.b, st.c + shift[0], st.d, st.e, st.f + shift[1])
        out = np.zeros((len(bands), h, w), dtype=dtype)
        for i, b in enumerate(bands):
            reproject(
                rasterio.band(src, b),
                out[i],
                src_transform=st,
                src_crs=crs or src.crs,
                dst_transform=tr,
                dst_crs="EPSG:32649",
                resampling=resampling,
            )
    return out


def detect_houses(png: Path) -> np.ndarray:
    """Símbolos de casa: quadrados pretos cheios de ~4-9 px (a 300 dpi) na carta."""
    a = np.asarray(Image.open(png).convert("RGB"), dtype=np.int16)
    mx, mn = a.max(axis=2), a.min(axis=2)
    black = (mx < 100) & (mx - mn < 40)
    lab, n = ndimage.label(black)
    objs = ndimage.find_objects(lab)
    areas = ndimage.sum(black, lab, range(1, n + 1))
    tr, _ = fit_affine(300)
    pts = []
    for i, sl in enumerate(objs):
        if sl is None:
            continue
        hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        area = areas[i]
        if not (4 <= hh <= 11 and 4 <= ww <= 11):
            continue
        if area / (hh * ww) < 0.72 or max(hh, ww) / min(hh, ww) > 1.6:
            continue
        cy = (sl[0].start + sl[0].stop) / 2
        cx = (sl[1].start + sl[1].stop) / 2
        pts.append(tr * (cx, cy))
    return np.array(pts)


def detect_streams(png: Path, step_px: int = 1) -> np.ndarray:
    """Riachos: traço azul escuro e contínuo da carta (exclui o mar e os símbolos de arrozal),
    esqueletizado; devolve pontos (E, N) na grade ING-A a cada ~step_px pixels."""
    a = np.asarray(Image.open(png).convert("RGB"), dtype=np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(axis=2)
    blue = (b - r >= 22) & (b >= g) & (mx < 190)  # azul-marinho do traço de riacho
    lab, n = ndimage.label(blue, structure=np.ones((3, 3)))
    objs = ndimage.find_objects(lab)
    sizes = ndimage.sum(blue, lab, range(1, n + 1))
    keep = np.zeros(n + 1, dtype=bool)
    for i, sl in enumerate(objs):
        if sl is None:
            continue
        ext = max(sl[0].stop - sl[0].start, sl[1].stop - sl[1].start)
        # linha: comprida (>= 40 px = 170 m) e fina (área pequena para a extensão)
        if ext >= 40 and sizes[i] < ext * 8:
            keep[i + 1] = True
    sk = skeletonize(keep[lab])
    ys, xs = np.nonzero(sk)
    sel = ((ys % step_px) == 0) | ((xs % step_px) == 0)
    tr, _ = fit_affine(300)
    return np.array([tr * (x, y) for x, y in zip(xs[sel], ys[sel], strict=True)])


def build_grid() -> Grid:
    E0, N0, E1, N1 = extent()
    w, h = int(round((E1 - E0) / CELL_M)), int(round((N1 - N0) / CELL_M))
    tr = from_origin(E0, N1, CELL_M, CELL_M)
    dem = _warp(
        R / "dem/Copernicus_DSM_COG_10_N15_00_E108_00_DEM.tif",
        None,
        tr,
        w,
        h,
        (1,),
        Resampling.cubic,
        np.float32,
    )[0]
    k = int(round(70 / CELL_M)) | 1
    hm = ndimage.gaussian_filter(ndimage.grey_opening(dem, size=(k, k)), sigma=15 / CELL_M)
    hm = np.maximum(hm, -3.0)

    # carta reprojetada (correção empírica aplicada como deslocamento da origem)
    m = _warp(
        R / "carta/carta_area_batalha.tif",
        ING_A_UTM49,
        tr,
        w,
        h,
        (1, 2, 3),
        Resampling.nearest,
        np.uint8,
        shift=(0.0, 0.0),
    ).astype(np.int16)
    # aplicar correção: deslocar a imagem da carta em (CORR_DE, CORR_DN)
    m = ndimage.shift(m, (0, -CORR_DN / CELL_M, CORR_DE / CELL_M), order=0, mode="nearest")
    r, g, b = m
    mx = m.max(axis=0)
    green = (g > r + 12) & (g > b + 8) & (mx > 120)
    green = ndimage.binary_opening(ndimage.binary_closing(green, iterations=2), iterations=1)
    green = ndimage.binary_closing(green, iterations=2)
    sea = hm < 0.3
    lab, n = ndimage.label(sea)
    if n:
        sizes = ndimage.sum(sea, lab, range(1, n + 1))
        sea = lab == (1 + int(np.argmax(sizes)))
    dist_sea = ndimage.distance_transform_edt(~sea) * CELL_M
    gy, gx = np.gradient(hm, CELL_M)
    slope = np.hypot(gx, gy)

    # riachos: detectados na resolução nativa da carta e rasterizados na grade
    skel = np.zeros((h, w), dtype=bool)
    for e, n_ in detect_streams(R / "carta/L7014_6739-I_300dpi.png"):
        E, N = ing_to_wgs_utm(e, n_)
        j, i = int((E - E0) / CELL_M), int((N1 - N) / CELL_M)
        if 0 <= i < h and 0 <= j < w:
            skel[i, j] = True
    skel &= ~ndimage.binary_dilation(sea, iterations=2)

    # relevo local: altura acima da base suavizada (janela de 300 m)
    base = ndimage.gaussian_filter(
        ndimage.minimum_filter(hm, size=int(300 / CELL_M) | 1), 100 / CELL_M
    )
    relief = hm - base
    cls = np.full((h, w), PADDY, dtype=np.uint8)
    cls[(relief > 9) | (slope > 0.09)] = GRASS
    cls[green] = VILLAGE
    cls[(dist_sea < 200) & ~green & (hm < 9)] = SAND
    cls[skel] = STREAM
    cls[sea] = SEA

    houses = detect_houses(R / "carta/L7014_6739-I_300dpi.png")
    if len(houses):
        houses = np.array([ing_to_wgs_utm(e, n) for e, n in houses])
        inside = (
            (houses[:, 0] > E0) & (houses[:, 0] < E1) & (houses[:, 1] > N0) & (houses[:, 1] < N1)
        )
        houses = houses[inside]
    ys, xs = np.nonzero(skel)
    stream_pts = np.column_stack([E0 + (xs + 0.5) * CELL_M, N1 - (ys + 0.5) * CELL_M])
    return Grid(w, h, E0, N1, hm.astype(np.float32), cls, houses, stream_pts)


def preview(gd: Grid, out: Path) -> None:
    pal = np.array(
        [
            [60, 90, 130],
            [215, 200, 160],
            [120, 140, 90],
            [40, 90, 40],
            [160, 160, 100],
            [70, 150, 230],
        ],
        dtype=np.uint8,
    )
    img = Image.fromarray(pal[gd.cls])
    from PIL import ImageDraw

    d = ImageDraw.Draw(img)
    for e, n in gd.houses:
        x, y = (e - gd.e0) / CELL_M, (gd.n1 - n) / CELL_M
        d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=(20, 20, 20))
    img.save(out, quality=85)


if __name__ == "__main__":
    gd = build_grid()
    frac = np.bincount(gd.cls.ravel(), minlength=6) / gd.cls.size
    print(
        f"grade {gd.w}x{gd.h} ({CELL_M:.2f} m), casas: {len(gd.houses)}, "
        f"pontos de riacho: {len(gd.stream_pts)}"
    )
    print({NOMES[i]: round(float(f), 3) for i, f in enumerate(frac)})
    preview(gd, Path(sys.argv[1]) if len(sys.argv) > 1 else R / "previews/uso_do_solo_v0.jpg")
