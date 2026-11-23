"""Uniformes v4 (D-236): as dobras, a sombra e o brilho do tecido pintados sobre os moldes v3.

Pedido do dono: "deixe os personagens mais bonitos com iluminação melhor faces uniformes reflexos".
Roupa clássica não tem mapa normal, então o volume vai na própria textura: cada face do molde ganha
um relevo de dobras (axila, cintura, cotovelo, joelho, tornozelo) iluminado de cima, com sombra nos
vincos, brilho de algodão nas cristas e, na bota de couro, um reflexo. O desenho (bolsos, estêncil,
camuflagem) não muda; a semente depende só da peça, então todas as skins têm as mesmas dobras.

Entrada: assets/clothing/v3/*.png e assets/clothing/skins/*.png. Saída: assets/clothing/v4/ (mesmo
nome) e assets/clothing/v4/previa.png (antes e depois).

Uso (a partir de vantuong65): uv run --group arte python tools/make_clothing_v4.py
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
ENTRADAS = [ROOT / "assets/clothing/v3", ROOT / "assets/clothing/skins"]
SAIDA = ROOT / "assets/clothing/v4"

_spec = importlib.util.spec_from_file_location(
    "make_clothing_v3", ROOT / "tools/make_clothing_v3.py"
)
assert _spec and _spec.loader
v3 = importlib.util.module_from_spec(_spec)
sys.modules["make_clothing_v3"] = v3  # as dataclasses do v3 procuram o módulo aqui
_spec.loader.exec_module(v3)

LUZ = np.array([-0.50, -0.72, 0.48])
LUZ = LUZ / np.linalg.norm(LUZ)
Dobra = tuple[float, float, float, float, float, float]  # x0, y0, x1, y1, largura, força


def suave(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def dobras(tipo: str, f, rng: np.random.Generator) -> list[Dobra]:
    def j(a: float = 0.03) -> float:
        return float(rng.uniform(-a, a))

    out: list[Dobra] = []
    if f.side in ("up", "down"):
        return out
    if f.part == "torso" and tipo == "shirt":
        if f.side in ("front", "back"):
            for s in (-1, 1):
                out.append((0.5 + s * 0.52, 0.09 + j(), 0.5 + s * 0.17, 0.43 + j(), 0.050, 1.0))
                out.append((0.5 + s * 0.47, 0.50 + j(), 0.5 + s * 0.15, 0.80 + j(), 0.046, 0.7))
            for x in np.linspace(0.12, 0.88, 5):
                out.append((x + j(), 1.02, x + j(0.06), 0.76 + j(0.06), 0.030, 0.38))
        else:
            out.append((0.08, 0.06, 0.82 + j(), 0.42 + j(), 0.07, 1.0))
            out.append((0.18, 0.52, 0.86 + j(), 0.84 + j(), 0.06, 0.75))
    elif f.part == "torso":
        if f.side in ("front", "back"):
            for s in (-1, 1):
                out.append((0.5 + s * 0.04, 0.97, 0.5 + s * 0.47, 0.50 + j(), 0.05, 1.0))
            for x in np.linspace(0.16, 0.84, 4):
                out.append((x + j(), -0.02, x + j(0.05), 0.17 + j(0.05), 0.026, 0.30))
        else:
            out.append((0.2, 0.05, 0.82 + j(), 0.50 + j(), 0.07, 0.9))
    elif tipo == "shirt":
        for d in (-0.06, 0.0, 0.07):
            y = 0.5 + d + j(0.012)
            out.append((-0.05, y, 1.05, y + float(rng.uniform(-0.05, 0.05)), 0.024, 1.0))
        out.append((-0.05, 0.11 + j(), 1.05, 0.21 + j(), 0.034, 0.75))
        out.append((0.1, 0.63 + j(), 0.92, 0.82 + j(), 0.034, 0.6))
    else:
        for d in (-0.05, 0.015, 0.075):
            y = 0.5 + d + j(0.012)
            out.append((-0.05, y, 1.05, y + float(rng.uniform(-0.04, 0.04)), 0.022, 0.95))
        out.append((-0.05, 0.13 + j(), 1.05, 0.33 + j(), 0.040, 0.8))
        out.append((-0.05, 0.66 + j(), 1.05, 0.74 + j(), 0.032, 0.65))
    return out


def relevo(w: int, h: int, lista: list[Dobra], rng: np.random.Generator) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = (xx + 0.5) / w, (yy + 0.5) / h
    # em unidades da largura, para a dobra não esticar na face alta
    asp = h / w
    # o traço reto vira curva: o espaço é torcido por um ruído largo
    for eixo in range(2):
        tor = ndimage.gaussian_filter(rng.normal(0, 1, (h, w)).astype(np.float32), w * 0.16)
        tor = tor / max(float(np.abs(tor).max()), 1e-5)
        if eixo == 0:
            u = u + 0.075 * tor
        else:
            v = v + 0.055 * tor
    alt = np.zeros((h, w), dtype=np.float32)
    for x0, y0, x1, y1, larg, forca in lista:
        larg = larg * 1.9
        dx, dy = x1 - x0, (y1 - y0) * asp
        l2 = dx * dx + dy * dy
        t = np.clip(((u - x0) * dx + (v - y0) * asp * dy) / l2, 0, 1)
        d = np.sqrt((u - (x0 + t * dx)) ** 2 + ((v - y0) * asp - t * dy) ** 2)
        afina = np.clip(np.sin(np.pi * t), 0, 1) ** 1.3
        alt += (
            forca
            * afina
            * (np.exp(-((d / larg) ** 2)) - 0.22 * np.exp(-(((d - 1.6 * larg) / larg) ** 2)))
        )
    ruido = ndimage.gaussian_filter(rng.normal(0, 1, (h, w)).astype(np.float32), w * 0.05)
    ruido = ruido / max(float(np.abs(ruido).max()), 1e-5)
    return alt + 0.22 * ruido


def pintar(img: Image.Image, tipo: str) -> Image.Image:
    arr = np.asarray(img.convert("RGBA"), dtype=np.float32)
    rgb, a = arr[..., :3].copy(), arr[..., 3]
    # contraste e cor um pouco mais vivos, em volta do tom médio da peça
    opaco = a > 128
    if opaco.any():
        lum = rgb @ np.array([0.299, 0.587, 0.114])
        media = float(lum[opaco].mean())
        rgb = media + (rgb - media) * 1.13
        lum2 = (rgb @ np.array([0.299, 0.587, 0.114]))[..., None]
        rgb = lum2 + (rgb - lum2) * 1.10
    for f in v3.FACES:
        x0, y0, x1, y1 = f.box
        w, h = x1 - x0, y1 - y0
        k = 2
        rng = np.random.default_rng(_semente(tipo, f.part, f.side))
        alt = relevo(w * k, h * k, dobras(tipo, f, rng), rng)
        escala = w * k * 0.034
        hy, hx = np.gradient(alt * escala)
        n = np.dstack((-hx, -hy, np.ones_like(hx)))
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        lamb = (n @ LUZ) / LUZ[2]
        vinco = np.clip(ndimage.gaussian_filter(alt, w * k * 0.05) - alt, 0, 1)
        sombra = np.clip(1 + 0.46 * (lamb - 1), 0.74, 1.17) * (
            1 - 0.16 * np.clip(vinco * 2.0, 0, 1)
        )
        brilho = np.clip(lamb - 1.06, 0, 1) ** 1.4 * 18
        # de 2x para 1x
        sombra = sombra.reshape(h, k, w, k).mean(axis=(1, 3))
        brilho = brilho.reshape(h, k, w, k).mean(axis=(1, 3))
        vv = (np.arange(h, dtype=np.float32) + 0.5) / h
        if f.side not in ("up", "down"):
            sombra = sombra * (1.07 - 0.13 * vv)[:, None]
        pedaco = rgb[y0:y1, x0:x1]
        lum = pedaco @ np.array([0.299, 0.587, 0.114])
        if tipo == "pants" and f.limb and f.side not in ("up", "down"):
            # a bota de couro não dobra como pano: fica lisa, com um reflexo no bico e no cano
            bota = suave(0.80, 0.86, vv)[:, None] * suave(92.0, 60.0, lum)
            sombra = sombra * (1 - bota) + (1.0 + 0.04 * (1 - vv[:, None])) * bota
            brilho = brilho * (1 - bota)
            uu = (np.arange(w, dtype=np.float32) + 0.5) / w
            mancha = (
                np.exp(-(((uu - 0.40) / 0.20) ** 2))[None, :]
                * np.exp(-(((vv - 0.93) / 0.03) ** 2))[:, None]
            )
            cano = (
                np.exp(-(((uu - 0.34) / 0.10) ** 2))[None, :]
                * np.exp(-(((vv - 0.87) / 0.04) ** 2))[:, None]
            )
            brilho = brilho + (mancha * 58 + cano * 22) * bota
        rgb[y0:y1, x0:x1] = pedaco * sombra[..., None] + brilho[..., None] * np.array(
            [1.0, 0.98, 0.92]
        )
    saida = np.dstack((rgb.clip(0, 255), a)).round().astype(np.uint8)
    return Image.fromarray(saida, "RGBA")


def _semente(tipo: str, parte: str, lado: str) -> int:
    return sum(ord(c) * (i + 7) for i, c in enumerate(f"{tipo}|{parte}|{lado}"))


def previa(pares: list[tuple[str, str, str]]) -> None:
    linhas = []
    for pasta, camisa, calca in pares:
        faccao = "US" if camisa.startswith("us") else "VC"
        blocos = []
        for raiz in (ROOT / "assets/clothing" / pasta, SAIDA):
            s = Image.open(raiz / f"{camisa}.png").convert("RGBA")
            c = Image.open(raiz / f"{calca}.png").convert("RGBA")
            blocos.append(v3.figure(s, c, "front", faccao))
            blocos.append(v3.figure(s, c, "back", faccao))
        w = sum(b.width for b in blocos) + 12 * (len(blocos) - 1)
        lin = Image.new("RGBA", (w, max(b.height for b in blocos)), (58, 62, 56, 255))
        x = 0
        for b in blocos:
            lin.alpha_composite(b.convert("RGBA"), (x, 0))
            x += b.width + 12
        linhas.append(lin)
    tela = Image.new(
        "RGBA",
        (max(n.width for n in linhas), sum(n.height + 10 for n in linhas)),
        (58, 62, 56, 255),
    )
    y = 0
    for n in linhas:
        tela.alpha_composite(n, (0, y))
        y += n.height + 10
    ImageDraw.Draw(tela).text(
        (6, 4), "antes (frente, costas) | depois (frente, costas)", fill=(240, 240, 230)
    )
    tela.convert("RGB").save(SAIDA / "previa.png")


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    n = 0
    for pasta in ENTRADAS:
        for arq in sorted(pasta.glob("*_v3.png")):
            tipo = "shirt" if "shirt" in arq.stem else "pants"
            pintar(Image.open(arq), tipo).save(SAIDA / arq.name, optimize=True)
            n += 1
    previa(
        [
            ("v3", "us_shirt_v3", "us_pants_v3"),
            ("v3", "vc_khaki_shirt_v3", "vc_khaki_pants_v3"),
            ("skins", "us_tiger_shirt_v3", "us_tiger_pants_v3"),
        ]
    )
    print(f"{n} moldes em {SAIDA}")


if __name__ == "__main__":
    main()
