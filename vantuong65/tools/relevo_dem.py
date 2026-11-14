"""Relevo mais fiel ao real (D-66), a partir do mesmo DEM de satélite (Copernicus GLO-30).

O relevo do jogo veio do Copernicus GLO-30 (DSM de 30 m) com abertura de 70 m (tira copas e casas)
e suavização gaussiana de 15 m (make_heightmap.py), calibrado nas cotas da carta de 1965. A
gaussiana de 15 m apaga encostas e grotas reais. Aqui:

1. O DEM é reprojetado na grade do jogo (UTM 49N, 4,48 m por célula).
2. Com a mesma abertura de 70 m, calcula-se o DEM com gaussiana de 5 m e o de 15 m. A diferença
   (detalhe real que a suavização tirou, limitado a ±DETALHE_MAX_M) é somada ao relevo do jogo.
3. Perto das vilas (lavoura: diques e lâminas d'água com altura fixa) o detalhe vai a zero, numa
   rampa de 115 a 160 m das casas (e de 135 a 175 m dos pontos fortes de arrozal).
4. Cada cume nomeado é calibrado na cota da carta com uma correção radial suave: Colina 43 = 43 m,
   Colina 30 = 30 m (o nome é a cota; no jogo estava a 34,8 m).

Também atualiza tests/luau/fixture_heights.json. Rodar a partir de vantuong65/:
    uv run python tools/relevo_dem.py            # aplica
    uv run python tools/relevo_dem.py --analisar # só mostra os números
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

import numpy as np
import rasterio
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
from crop_world import (  # noqa: E402
    FIXTURE,
    PONTOS_FORTES,
    ing_local,
    read_features,
    read_grid,
    write_grid,
)
from geo import STUD_M, play_center_wgs  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
TILE = "Copernicus_DSM_COG_10_N15_00_E108_00_DEM"
DEM = ROOT / f"research/dem/{TILE}.tif"
DEM_URL = f"https://copernicus-dem-30m.s3.amazonaws.com/{TILE}/{TILE}.tif"

ABERTURA_M = 70.0  # igual ao make_heightmap: tira copas e casas isoladas
SIGMA_ANTES_M = 15.0  # suavização usada no relevo atual
SIGMA_NOVO_M = 5.0  # mantém encostas e grotas de ~15 m para cima
DETALHE_MAX_M = 4.0
VILA_M = (115.0, 160.0)  # rampa do detalhe a partir das casas
ARROZAL_M = (135.0, 175.0)  # rampa a partir dos pontos fortes de arrozal
# cumes da carta: (nome no PONTOS_FORTES, cota em m, raio da correção em m)
CUMES = [("Colina 43", 43.0, 140.0), ("Colina 30", 30.0, 140.0)]


def baixar_dem() -> None:
    if DEM.exists():
        return
    DEM.parent.mkdir(parents=True, exist_ok=True)
    print("baixando", DEM_URL)
    req = urllib.request.Request(DEM_URL, headers={"User-Agent": "vt65-asset-tool"})
    with urllib.request.urlopen(req, timeout=300) as r:
        DEM.write_bytes(r.read())


def dem_na_grade(g: dict) -> np.ndarray:
    """DEM (m) reprojetado para a grade do jogo: célula de g['cell'] studs, linha 0 ao norte."""
    cE, cN = play_center_wgs()
    res = g["cell"] * STUD_M
    west = cE + g["ox"] * STUD_M
    north = cN - g["oz"] * STUD_M
    out = np.full((g["h"], g["w"]), np.nan, dtype=np.float32)
    with rasterio.open(DEM) as src:
        reproject(
            rasterio.band(src, 1),
            out,
            src_transform=src.transform,
            src_crs=src.crs,
            dst_transform=from_origin(west, north, res, res),
            dst_crs="EPSG:32649",
            resampling=Resampling.cubic,
            dst_nodata=np.nan,
        )
    assert not np.isnan(out).any(), "DEM sem dado em parte da grade"
    return out


def rampa(d: np.ndarray, d0: float, d1: float) -> np.ndarray:
    t = np.clip((d - d0) / (d1 - d0), 0, 1)
    return t * t * (3 - 2 * t)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--analisar", action="store_true")
    args = ap.parse_args()
    baixar_dem()
    g = read_grid()
    f = read_features()
    res = g["cell"] * STUD_M
    hoff = g["hoff"]
    atual_m = (g["heights"].astype(np.float64) - hoff) / 100.0

    dem = dem_na_grade(g).astype(np.float64)
    k = max(3, int(round(ABERTURA_M / res)) | 1)
    aberto = ndimage.grey_opening(dem, size=(k, k))
    antes = ndimage.gaussian_filter(aberto, SIGMA_ANTES_M / res)
    novo = ndimage.gaussian_filter(aberto, SIGMA_NOVO_M / res)
    detalhe = np.clip(novo - antes, -DETALHE_MAX_M, DETALHE_MAX_M)

    # centros das células em studs
    xs = g["ox"] + (np.arange(g["w"]) + 0.5) * g["cell"]
    zs = g["oz"] + (np.arange(g["h"]) + 0.5) * g["cell"]
    X, Z = np.meshgrid(xs, zs)
    d_casa = np.full(X.shape, np.inf)
    for hx, hz in f["houses"][:, :2]:
        d_casa = np.minimum(d_casa, np.hypot(X - hx, Z - hz) * STUD_M)
    peso = rampa(d_casa, *VILA_M)
    for sp in PONTOS_FORTES:
        nome, e, n = sp[1], sp[2], sp[3]
        if "arrozal" in nome.lower():
            sx, sz = ing_local(e, n)
            peso = np.minimum(peso, rampa(np.hypot(X - sx, Z - sz) * STUD_M, *ARROZAL_M))
    novo_m = atual_m + detalhe * peso

    # cumes da carta: correção radial suave para a cota exata
    pf = {sp[1]: ing_local(sp[2], sp[3]) for sp in PONTOS_FORTES}
    for nome, cota, raio in CUMES:
        sx, sz = pf[nome]
        d = np.hypot(X - sx, Z - sz) * STUD_M
        perto = d < 40
        w = np.exp(-0.5 * (d / (raio / 2)) ** 2)
        topo0 = float(novo_m[perto].max())
        for _ in range(8):  # o pico não fica no centro exato do ponto: algumas passadas
            topo = float(novo_m[perto].max())
            if abs(topo - cota) < 0.1:
                break
            novo_m = novo_m + (cota - topo) * w
        topo1 = float(novo_m[perto].max())
        print(f"{nome}: cume {topo0:.1f} m -> {topo1:.1f} m (carta: {cota:.0f} m)")

    mudou = np.abs(novo_m - atual_m)
    print(
        f"detalhe somado: média {float(np.abs(detalhe * peso).mean()):.2f} m, "
        f"máx {float(mudou.max()):.2f} m; células com mudança > 0,5 m: {int((mudou > 0.5).sum())} "
        f"de {mudou.size}"
    )
    if args.analisar:
        return
    g["heights"] = np.clip(np.round(novo_m * 100.0 + hoff), 0, 65535).astype("<u2")
    write_grid(g)

    # fixture do teste Luau: mesma interpolação bilinear do WorldData
    def altura_studs(x: float, z: float) -> float:
        fx = (x - g["ox"]) / g["cell"] - 0.5
        fz = (z - g["oz"]) / g["cell"] - 0.5
        c0, r0 = int(np.floor(fx)), int(np.floor(fz))
        tx, tz = fx - c0, fz - r0

        def cell(c: int, r: int) -> float:
            c = min(max(c, 0), g["w"] - 1)
            r = min(max(r, 0), g["h"] - 1)
            return (int(g["heights"][r, c]) - hoff) / 100.0 / STUD_M

        top = cell(c0, r0) * (1 - tx) + cell(c0 + 1, r0) * tx
        bot = cell(c0, r0 + 1) * (1 - tx) + cell(c0 + 1, r0 + 1) * tx
        return top * (1 - tz) + bot * tz

    fx = json.loads(FIXTURE.read_text("utf-8"))
    for p in fx:
        p["h_studs"] = round(altura_studs(p["x"], p["z"]), 3)
    FIXTURE.write_text(json.dumps(fx, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"gravado: Grid/Heights e {len(fx)} pontos do fixture")


if __name__ == "__main__":
    main()
