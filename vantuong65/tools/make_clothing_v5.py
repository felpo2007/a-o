"""Uniformes v5 (D-249): tecido escuro de campanha, lama, poeira e desgaste sobre os moldes v4.

Pedido do dono: "quero esse estilo igual das imagens de vibe, textura, graficos". Nas imagens o
uniforme é oliva profundo e está sujo: lama nas pernas, joelhos, cotovelos e barra, poeira nos
vincos e pano gasto nas bordas. O desenho (bolsos, estêncil, camuflagem) continua; a semente
depende só da peça, então a lama cai no mesmo lugar em todas as skins.

Entrada: assets/clothing/v4/*_v3.png. Saída: assets/clothing/v5/ (mesmo nome) e v5/previa.png.

Uso (a partir de vantuong65): uv run --group arte python tools/make_clothing_v5.py
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
ENTRADA = ROOT / "assets/clothing/v4"
SAIDA = ROOT / "assets/clothing/v5"

_spec = importlib.util.spec_from_file_location(
    "make_clothing_v3", ROOT / "tools/make_clothing_v3.py"
)
assert _spec and _spec.loader
v3 = importlib.util.module_from_spec(_spec)
sys.modules["make_clothing_v3"] = v3
_spec.loader.exec_module(v3)

PESOS = np.array([0.299, 0.587, 0.114])
LAMA_ESCURA = np.array([36.0, 26.0, 17.0])
LAMA_CLARA = np.array([92.0, 68.0, 44.0])
POEIRA = np.array([176.0, 150.0, 112.0])


def suave(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def fractal(
    w: int, h: int, rng: np.random.Generator, escala: float, oitavas: int = 4
) -> np.ndarray:
    total = np.zeros((h, w), dtype=np.float32)
    amp, soma = 1.0, 0.0
    for i in range(oitavas):
        c = rng.normal(0, 1, (h, w)).astype(np.float32)
        c = ndimage.gaussian_filter(c, max(escala / (2**i), 0.6), mode="wrap")
        c = c / max(float(c.std()), 1e-5)
        total += amp * c
        soma += amp
        amp *= 0.55
    return total / soma


def onde_suja(tipo: str, f, w: int, h: int) -> np.ndarray:
    """Quanto cada ponto da face tende a pegar lama (0 a 1)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v, u = (yy + 0.5) / h, (xx + 0.5) / w
    if f.side == "up":
        return np.full((h, w), 0.16 if f.part != "torso" else 0.05, dtype=np.float32)
    if f.side == "down":
        return np.full((h, w), 0.8 if tipo == "pants" and f.limb else 0.3, dtype=np.float32)
    if f.part == "torso":
        if tipo == "shirt":
            # barra da camisa, ombro e o lado de quem encosta no chão
            baixo = suave(0.52, 1.0, v) * 0.62
            ombro = np.exp(-(((v - 0.05) / 0.10) ** 2)) * 0.26
            lado = np.exp(-(((u - 0.5) / 0.42) ** 8))
            return np.clip(baixo + ombro * lado, 0, 1)
        return np.clip(suave(0.0, 1.0, v) * 0.42 + 0.12, 0, 1)
    if tipo == "shirt":
        # manga: cotovelo e antebraço
        cotovelo = np.exp(-(((v - 0.52) / 0.13) ** 2)) * 0.62
        punho = suave(0.62, 1.0, v) * 0.56
        return np.clip(cotovelo + punho + 0.04, 0, 1)
    # perna: joelho, canela e bota
    joelho = np.exp(-(((v - 0.48) / 0.12) ** 2)) * 0.70
    canela = suave(0.56, 0.9, v) * 0.86
    return np.clip(joelho + canela + 0.06, 0, 1)


def respingos(w: int, h: int, rng: np.random.Generator, peso: np.ndarray, n: int) -> np.ndarray:
    m = Image.new("L", (w * 2, h * 2), 0)
    d = ImageDraw.Draw(m)
    p = peso.ravel() + 1e-4
    p = p / p.sum()
    for idx in rng.choice(p.size, size=n, p=p):
        y, x = np.unravel_index(int(idx), peso.shape)
        r = float(rng.uniform(0.5, 2.6)) ** 1.4
        ex, ey = r * float(rng.uniform(0.7, 1.4)), r * float(rng.uniform(0.7, 1.9))
        cx, cy = 2 * x + float(rng.uniform(-1, 1)), 2 * y + float(rng.uniform(-1, 1))
        d.ellipse((cx - ex, cy - ey, cx + ex, cy + ey), fill=int(rng.integers(150, 255)))
    return np.asarray(m.resize((w, h), Image.BILINEAR), dtype=np.float32) / 255


def _semente(tipo: str, parte: str, lado: str) -> int:
    return sum(ord(c) * (i + 11) for i, c in enumerate(f"v5|{tipo}|{parte}|{lado}"))


def pintar(img: Image.Image, tipo: str) -> Image.Image:
    arr = np.asarray(img.convert("RGBA"), dtype=np.float32)
    rgb, a = arr[..., :3].copy(), arr[..., 3]
    opaco = a > 128
    if opaco.any():
        # pano de campanha: mais escuro, mais contraste, verde profundo e um pouco de calor
        lum = rgb @ PESOS
        media = float(lum[opaco].mean())
        alvo = min(media * 0.70, 78.0) if media > 72 else media * 0.9
        rgb = alvo + (rgb - media) * 1.05
        lum2 = (rgb @ PESOS)[..., None]
        rgb = lum2 + (rgb - lum2) * 0.98
        rgb = rgb * np.array([1.0, 1.0, 0.93])
    for f in v3.FACES:
        x0, y0, x1, y1 = f.box
        w, h = x1 - x0, y1 - y0
        rng = np.random.default_rng(_semente(tipo, f.part, f.side))
        peso = onde_suja(tipo, f, w, h)
        pedaco = rgb[y0:y1, x0:x1]

        # manchas largas de pano gasto e molhado
        largo = fractal(w, h, rng, w * 0.22)
        pedaco = pedaco * (1 + 0.12 * np.clip(largo, -1.6, 1.6)[..., None])

        # trama do tecido
        fino = rng.normal(0, 1, (h, w)).astype(np.float32)
        pedaco = pedaco * (1 + 0.035 * fino[..., None])

        # poeira clara nas partes altas do relevo
        poeira = suave(0.7, 2.0, fractal(w, h, rng, w * 0.07)) * (0.20 + 0.42 * peso)
        pedaco = pedaco * (1 - poeira[..., None] * 0.52) + POEIRA * poeira[..., None] * 0.52

        # lama: mancha de borda rasgada onde a chance é alta
        ruido = fractal(w, h, rng, w * 0.075, 5)
        campo = ruido + 2.5 * peso - 2.0
        lama = suave(0.0, 0.26, campo)
        pingos = respingos(w, h, rng, peso**1.5, int(30 + w * h * 0.012))
        lama = np.clip(lama + pingos * 0.92, 0, 1)
        tom = suave(-1.2, 1.3, fractal(w, h, rng, w * 0.05))[..., None]
        cor = LAMA_ESCURA * (1 - tom) + LAMA_CLARA * tom
        # a lama tem espessura: luz em cima, sombra embaixo
        gy, gx = np.gradient(ndimage.gaussian_filter(lama, 0.8))
        relevo = np.clip(-gy * 1.3 - gx * 0.5, -0.4, 0.5)[..., None]
        cor = cor * (1 + relevo)
        # a borda escurece o pano em volta, como barro úmido
        halo = np.clip(ndimage.gaussian_filter(lama, 1.8) - lama, 0, 1)[..., None]
        pedaco = pedaco * (1 - 0.42 * halo)
        k = (lama * 0.84)[..., None]
        rgb[y0:y1, x0:x1] = pedaco * (1 - k) + cor * k
    saida = np.dstack((rgb.clip(0, 255), a)).round().astype(np.uint8)
    return Image.fromarray(saida, "RGBA")


def previa(pares: list[tuple[str, str]]) -> None:
    linhas = []
    for camisa, calca in pares:
        faccao = "US" if camisa.startswith("us") else "VC"
        blocos = []
        for raiz in (ENTRADA, SAIDA):
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
    tela.convert("RGB").save(SAIDA / "previa.png")


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    n = 0
    for arq in sorted(ENTRADA.glob("*_v3.png")):
        tipo = "shirt" if "shirt" in arq.stem else "pants"
        pintar(Image.open(arq), tipo).save(SAIDA / arq.name, optimize=True)
        n += 1
    previa(
        [
            ("us_shirt_v3", "us_pants_v3"),
            ("vc_khaki_shirt_v3", "vc_khaki_pants_v3"),
            ("us_tiger_shirt_v3", "us_tiger_pants_v3"),
        ]
    )
    print(f"{n} moldes em {SAIDA}")


if __name__ == "__main__":
    main()
