"""Gera as imagens de conferência da F0 em research/previews/ (JPEG leves para o Git):
1. carta L7014 ed. 3 (miolo) com a área jogável proposta e os locais;
2. heightmap v0 em relevo sombreado com a área jogável e os locais;
3. traço da carta sobre o Sentinel-2 (27/03/2025).

Uso: uv run python tools/make_previews.py
"""

from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
from geo import PLAY_ING, ing_to_wgs_utm, play_center_wgs  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
R = ROOT / "research"
OUT = R / "previews"


def locais() -> list[dict]:
    with open(R / "locais.csv", encoding="utf-8") as f:
        return list(csv.DictReader(f))


try:  # fonte com diacríticos vietnamitas; cai para a padrão se não existir
    FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
except OSError:
    FONT = ImageFont.load_default()


def mark(d: ImageDraw.ImageDraw, x: float, y: float, txt: str, col=(255, 0, 255)) -> None:
    d.ellipse([x - 7, y - 7, x + 7, y + 7], outline=col, width=3)
    d.text((x + 10, y - 12), txt, fill=col, font=FONT, stroke_width=2, stroke_fill=(0, 0, 0))


def carta() -> None:
    with rasterio.open(R / "carta/carta_area_batalha.tif") as ds:
        e0, n0, e1, n1 = 267700, 1690800, 272700, 1694100
        win = rasterio.windows.from_bounds(e0, n0, e1, n1, ds.transform)
        win = win.round_offsets().round_lengths()
        a = np.moveaxis(ds.read(window=win), 0, -1)
        inv = ~ds.window_transform(win)
    im = Image.fromarray(a)
    d = ImageDraw.Draw(im)
    pe0, pn0, pe1, pn1 = PLAY_ING
    corners = [inv * c for c in ((pe0, pn0), (pe1, pn0), (pe1, pn1), (pe0, pn1), (pe0, pn0))]
    d.line(corners, fill=(255, 0, 255), width=4)
    for r in locais():
        x, y = inv * (float(r["E_ing"]), float(r["N_ing"]))
        mark(d, x, y, r["nome"])
    im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
    im.save(OUT / "carta_L7014_ed3_area_proposta.jpg", quality=85)


def relevo() -> None:
    z = np.asarray(Image.open(R / "heightmap/heightmap_area_v0.png"), dtype=np.float32)
    import json

    meta = json.loads((R / "heightmap/heightmap_area_v0.json").read_text(encoding="utf-8"))
    zm = meta["altura_min_m"] + z / 65535 * (meta["altura_max_m"] - meta["altura_min_m"])
    res = meta["metros_por_px"]
    gy, gx = np.gradient(zm, res)
    az, alt = np.radians(315), np.radians(40)
    slope = np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    hs = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    base = np.clip(hs * 200 + 30, 0, 255)
    col = np.stack([base * 0.85 + zm, base * 0.9 + zm * 0.6, base * 0.8], -1)
    col[zm < 0.5] = [60, 90, 120]
    im = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    cE, cN = play_center_wgs()
    W, H = meta["tamanho_m"]

    def px(E: float, N: float) -> tuple[float, float]:
        return (E - (cE - W / 2)) / res, ((cN + H / 2) - N) / res

    pe0, pn0, pe1, pn1 = PLAY_ING
    pts = [
        px(*ing_to_wgs_utm(e, n))
        for e, n in ((pe0, pn0), (pe1, pn0), (pe1, pn1), (pe0, pn1), (pe0, pn0))
    ]
    d.line(pts, fill=(255, 0, 255), width=4)
    for r in locais():
        x, y = px(float(r["E_wgs84_utm49"]), float(r["N_wgs84_utm49"]))
        mark(d, x, y, r["nome"], (255, 255, 0))
    im.save(OUT / "heightmap_v0_relevo.jpg", quality=85)


def sobreposicao() -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools/overlay.py"),
            str(R / "carta/carta_area_batalha.tif"),
            str(R / "sat/S2C_20250327_TCI_area.tif"),
            "266500",
            "1690000",
            "272500",
            "1694500",
            str(OUT / "_ov.png"),
            "5",
        ],
        check=True,
    )
    Image.open(OUT / "_ov.png").save(OUT / "carta_L7014_ed3_sobre_sentinel2.jpg", quality=85)
    (OUT / "_ov.png").unlink()


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    carta()
    relevo()
    sobreposicao()
    print(sorted(p.name for p in OUT.iterdir()))
