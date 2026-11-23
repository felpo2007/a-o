"""Céu de foto (D-69): HDRI "pure sky" do Poly Haven (CC0) cortado nas 6 faces do Sky do Roblox.

Pedido do usuário (2026-11-11): "o céu está bugado pixelando muito e trocando conforme eu olho".
As nuvens dinâmicas saíram (TerrainLook); o céu passa a ser uma foto de céu azul com nuvens.

- baixa o JPG já tonemapeado do Poly Haven (equirretangular, 8k);
- tira o disco do sol da foto (o Roblox desenha o próprio sol, em outra posição);
- gira em Y (YAW_DEG) e corta 6 faces de FACE_PX px (o Roblox reduz textura a 1024);
- grava em assets/ceu/ (fora do Git) e uma folha de conferência.

Uso: uv run python tools/fetch_sky.py
"""

from __future__ import annotations

import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ceu"
HDRI = "kloofendal_48d_partly_cloudy_puresky"
URL = f"https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/{HDRI}.jpg"
FACE_PX = 1024
YAW_DEG = 0.0
UA = {"User-Agent": "vt65-asset-fetch/1.0"}

# Direção (x, y, z) de cada face do Roblox no mundo e os eixos da imagem (direita, cima).
# Conferido no Studio com faces rotuladas (2026-11-11): Ft é visto olhando para −Z, em pé e sem
# espelho; Lf fica em +X e Rt em −X; na Up a direita da imagem aponta para −Z e o topo para +X.
FACES = {
    "ft": ((0, 0, -1), (1, 0, 0), (0, 1, 0)),
    "bk": ((0, 0, 1), (-1, 0, 0), (0, 1, 0)),
    "lf": ((1, 0, 0), (0, 0, 1), (0, 1, 0)),
    "rt": ((-1, 0, 0), (0, 0, -1), (0, 1, 0)),
    "up": ((0, 1, 0), (0, 0, -1), (1, 0, 0)),
    "dn": ((0, -1, 0), (0, 0, -1), (-1, 0, 0)),
}


def baixar() -> Path:
    src = OUT / f"{HDRI}.jpg"
    if not src.exists():
        OUT.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(URL, headers=UA)
        with urllib.request.urlopen(req, timeout=300) as r:
            src.write_bytes(r.read())
    return src


def sem_sol(eq: np.ndarray) -> np.ndarray:
    """Troca o disco do sol (e o halo estourado) pelo céu em volta (convolução normalizada)."""
    lum = eq.mean(axis=2)
    # só a mancha estourada que contém o pixel mais claro (nuvem branca também passa de 235: na
    # primeira versão as nuvens viraram remendos quadrados)
    estourado = lum > 250
    if not estourado.any():
        return eq
    rot, _n = ndimage.label(estourado)
    iy, ix = np.unravel_index(int(np.argmax(np.where(estourado, lum, -1))), lum.shape)
    sol = rot == rot[iy, ix]
    sol = ndimage.binary_dilation(sol, iterations=int(eq.shape[0] * 0.012))
    peso = (~sol).astype(np.float32)
    out = eq.copy()
    sigma = eq.shape[0] * 0.015
    w = ndimage.gaussian_filter(peso, sigma)
    for c in range(3):
        v = ndimage.gaussian_filter(eq[..., c] * peso, sigma) / np.maximum(w, 1e-4)
        out[..., c] = np.where(sol, v, eq[..., c])
    return out


def face(eq: np.ndarray, d, r, u) -> Image.Image:
    h, w = eq.shape[:2]
    t = (np.arange(FACE_PX) + 0.5) / FACE_PX * 2 - 1
    a, b = np.meshgrid(t, -t)  # a: direita, b: cima
    v = (
        np.array(d)[None, None, :]
        + a[..., None] * np.array(r)[None, None, :]
        + b[..., None] * np.array(u)[None, None, :]
    )
    v /= np.linalg.norm(v, axis=2, keepdims=True)
    yaw = np.radians(YAW_DEG)
    x = v[..., 0] * np.cos(yaw) - v[..., 2] * np.sin(yaw)
    z = v[..., 0] * np.sin(yaw) + v[..., 2] * np.cos(yaw)
    y = v[..., 1]
    lon = np.arctan2(x, -z)  # 0 no centro da foto = −Z
    lat = np.arcsin(np.clip(y, -1, 1))
    px = (lon / (2 * np.pi) + 0.5) * (w - 1)
    py = (0.5 - lat / np.pi) * (h - 1)
    out = np.zeros((FACE_PX, FACE_PX, 3), np.float32)
    for c in range(3):
        out[..., c] = ndimage.map_coordinates(eq[..., c], [py, px], order=1, mode="wrap")
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    Image.MAX_IMAGE_PIXELS = None
    src = baixar()
    im = Image.open(src).convert("RGB")
    im = im.resize((4096, 2048), Image.Resampling.LANCZOS)
    eq = sem_sol(np.asarray(im).astype(np.float32))
    folha = Image.new("RGB", (256 * 4, 256 * 3), "black")
    pos = {"up": (1, 0), "lf": (0, 1), "ft": (1, 1), "rt": (2, 1), "bk": (3, 1), "dn": (1, 2)}
    for nome, (d, r, u) in FACES.items():
        f = face(eq, d, r, u)
        f.save(OUT / f"ceu_{nome}.png", optimize=True)
        cx, cy = pos[nome]
        folha.paste(f.resize((256, 256)), (cx * 256, cy * 256))
    folha.save(OUT / "ceu_folha.png")
    print("faces em", OUT)


if __name__ == "__main__":
    main()
