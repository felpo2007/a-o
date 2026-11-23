"""Caveira do abate (pedido do dono, 2026-11-11: "faça uma caveira bem feita quando você mata...").

Estêncil militar dos anos 60, pintado a pistola: a caveira de frente, com as pontes do estêncil
(os vãos finos que seguram as ilhas da chapa: arco zigomático, do nariz até o queixo e a linha da
mordida), olhos e nariz vazados, um reflexo em arco no crânio e a tinta com névoa de spray na borda,
densidade irregular e respingos. Sem texto na imagem (D-84: o texto vai na tela, para traduzir).

Saída: assets/ui/caveira_abate.png, 1024 x 1024, branca com alfa (o jogo tinge pela ImageColor3).
A geometria é desenhada a 4096 px e reduzida (borda lisa); a textura de spray é feita a 1024.
Mostrada a ~10% da altura da tela: ~110 px em 1080p e ~220 px em 4K, sempre reduzida.

Uso (de vantuong65/):
    uv run python tools/make_caveira.py                 # grava o PNG
    uv run python tools/make_caveira.py --previa X.png  # e uma prévia sobre fundo escuro e claro
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui" / "caveira_abate.png"

SIZE = 1024  # lado da imagem final (o Roblox não guarda mais que isso)
SUPER = 4  # supersampling da geometria
SEED = 1965

Pt = tuple[float, float]

# ===== geometria (unidades da tela: x de 0 a 1, centro em 0,5; y de cima para baixo) =====
# Meio contorno direito (x a partir do centro), do alto do crânio ao queixo; o esquerdo é o espelho.
# Crânio largo, têmpora que entra, maçã do rosto saliente, a face que afunda sob ela (o rosto
# magro de caveira de verdade) e a mandíbula com o ângulo marcado.
OUTLINE_RIGHT: list[Pt] = [
    (0.000, 0.084),
    (0.112, 0.094),
    (0.204, 0.128),
    (0.268, 0.186),
    (0.304, 0.256),
    (0.317, 0.334),  # o mais largo do crânio
    (0.314, 0.398),
    (0.300, 0.446),
    (0.287, 0.482),  # têmpora
    (0.298, 0.522),
    (0.309, 0.556),  # maçã do rosto
    (0.294, 0.590),
    (0.252, 0.612),  # a face afunda sob o osso
    (0.214, 0.630),
    (0.200, 0.668),  # maxila
    (0.204, 0.722),
    (0.214, 0.782),  # ângulo da mandíbula
    (0.204, 0.838),
    (0.164, 0.884),
    (0.100, 0.912),
    (0.044, 0.922),
    (0.000, 0.924),  # queixo
]

# órbita direita (fechada): o canto de dentro desce até a ponte do nariz e a sobrancelha pesa sobre
# o olho (o olhar duro do estêncil, não o redondo do desenho animado)
EYE_RIGHT: list[Pt] = [
    (0.036, 0.474),
    (0.074, 0.436),
    (0.134, 0.408),
    (0.194, 0.404),
    (0.226, 0.430),
    (0.232, 0.474),
    (0.214, 0.518),
    (0.166, 0.546),
    (0.104, 0.548),
    (0.058, 0.526),
    (0.038, 0.500),
]

# cavidade nasal: coração invertido com o septo embaixo (metade direita, do topo ao septo)
NOSE_RIGHT: list[Pt] = [
    (0.000, 0.548),
    (0.016, 0.574),
    (0.036, 0.606),
    (0.050, 0.634),
    (0.044, 0.652),
    (0.024, 0.656),
    (0.008, 0.644),
    (0.000, 0.634),
]

GAP = 0.0135  # largura das pontes do estêncil
TEETH_X = (0.0, 0.034, 0.068, 0.102)  # vãos entre os dentes (e o espelho)
TEETH_TOP, BITE, TEETH_BOTTOM = 0.676, 0.750, 0.822
TEETH_W = 0.136  # meia largura da fileira de dentes


def catmull(points: list[Pt], closed: bool, n: int = 14) -> list[Pt]:
    """Curva lisa (Catmull-Rom) pelos pontos."""
    out: list[Pt] = []
    m = len(points)
    last = m if closed else m - 1
    for i in range(last):
        p0 = points[(i - 1) % m] if closed or i > 0 else points[0]
        p1 = points[i]
        p2 = points[(i + 1) % m]
        p3 = points[(i + 2) % m] if closed or i + 2 < m else points[-1]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(
                tuple(
                    0.5
                    * (
                        2 * p1[j]
                        + (-p0[j] + p2[j]) * t
                        + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                        + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3
                    )
                    for j in range(2)
                )  # type: ignore[misc]
            )
    if not closed:
        out.append(points[-1])
    return out


def mirror(half: list[Pt]) -> list[Pt]:
    """Meio contorno (x a partir do centro) -> contorno fechado inteiro em coordenadas de tela."""
    right = [(0.5 + x, y) for x, y in half]
    left = [(0.5 - x, y) for x, y in reversed(half[1:-1])]
    return right + left


def side(points: list[Pt], s: int) -> list[Pt]:
    """Pontos de um lado (s = 1 direita, -1 esquerda) em coordenadas de tela."""
    return [(0.5 + s * x, y) for x, y in points]


def to_px(points: list[Pt], scale: float) -> list[tuple[float, float]]:
    return [(x * scale, y * scale) for x, y in points]


def stroke(d: ImageDraw.ImageDraw, pts: list[Pt], w0: float, w1: float, scale: float) -> None:
    """Traço de largura variável (w0 no começo, w1 no fim) apagando a máscara: a ponte afina."""
    n = len(pts)
    for i in range(n - 1):
        t = i / max(n - 2, 1)
        w = (w0 + (w1 - w0) * t) * scale
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        d.line((x0 * scale, y0 * scale, x1 * scale, y1 * scale), fill=0, width=max(1, round(w)))
        r = w / 2
        d.ellipse((x1 * scale - r, y1 * scale - r, x1 * scale + r, y1 * scale + r), fill=0)
    x, y = pts[0]
    r = w0 * scale / 2
    d.ellipse((x * scale - r, y * scale - r, x * scale + r, y * scale + r), fill=0)


def geometry() -> Image.Image:
    """Máscara da caveira (L, 0..255) a SIZE * SUPER, reduzida para SIZE."""
    big = SIZE * SUPER
    im = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(im)
    d.polygon(to_px(catmull(mirror(OUTLINE_RIGHT), closed=True), big), fill=255)
    # olhos e nariz vazados
    for s in (1, -1):
        d.polygon(to_px(catmull(side(EYE_RIGHT, s), closed=True), big), fill=0)
    nose = catmull(NOSE_RIGHT, closed=False)
    d.polygon(to_px(side(nose, 1) + list(reversed(side(nose, -1))), big), fill=0)
    # pontes do estêncil e os cortes que dão o volume
    for s in (1, -1):
        # arco zigomático: da órbita, por baixo, até a borda da face (afina para fora)
        arc = catmull(
            side([(0.196, 0.516), (0.236, 0.536), (0.272, 0.548), (0.320, 0.552)], s),
            closed=False,
        )
        stroke(d, arc, GAP * 1.1, GAP * 0.7, big)
        # arco da sobrancelha: corte fino acima da órbita, o osso da testa fica pesado
        brow = catmull(
            side([(0.046, 0.420), (0.118, 0.380), (0.196, 0.374), (0.248, 0.404)], s), False
        )
        stroke(d, brow, GAP * 0.45, GAP * 0.7, big)
        # fossa temporal: meia-lua na lateral do crânio
        temple = catmull(
            side([(0.262, 0.290), (0.282, 0.360), (0.276, 0.420), (0.258, 0.462)], s), False
        )
        stroke(d, temple, GAP * 0.35, GAP * 0.8, big)
        # sulco sob a maçã do rosto, da asa do nariz para fora
        cheek = catmull(side([(0.070, 0.612), (0.120, 0.618), (0.168, 0.612)], s), False)
        stroke(d, cheek, GAP * 0.4, GAP * 0.55, big)
        # linha da mordida: dos dentes até o ângulo da mandíbula (a mandíbula fica solta da maxila)
        bite = catmull(
            side([(0.0, BITE), (0.130, BITE), (0.176, BITE - 0.006), (0.230, BITE - 0.022)], s),
            closed=False,
        )
        stroke(d, bite, GAP, GAP * 0.6, big)
        # gengiva de cima e de baixo: os dentes viram blocos
        gum = catmull(
            side([(0.0, TEETH_TOP), (0.090, TEETH_TOP - 0.002), (TEETH_W, TEETH_TOP - 0.010)], s),
            False,
        )
        stroke(d, gum, GAP * 0.7, GAP * 0.55, big)
        low = catmull(
            side(
                [
                    (0.0, TEETH_BOTTOM),
                    (0.090, TEETH_BOTTOM - 0.003),
                    (TEETH_W - 0.012, TEETH_BOTTOM - 0.014),
                ],
                s,
            ),
            False,
        )
        stroke(d, low, GAP * 0.7, GAP * 0.55, big)
        # vãos entre os dentes; cada dente arredonda na ponta (o vão abre um pouco na mordida)
        for x in TEETH_X[1:]:
            tooth = [(0.5 + s * x, TEETH_TOP), (0.5 + s * x, TEETH_BOTTOM - 0.004)]
            stroke(d, tooth, GAP * 0.8, GAP * 0.8, big)
            r = GAP * 0.95 * big
            cx, cy = (0.5 + s * x) * big, BITE * big
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=0)
        # cantos da boca: os dentes de fora fecham em curva
        corner = catmull(
            side(
                [
                    (TEETH_W - 0.012, TEETH_TOP - 0.006),
                    (TEETH_W + 0.006, BITE),
                    (TEETH_W - 0.020, TEETH_BOTTOM - 0.012),
                ],
                s,
            ),
            closed=False,
        )
        stroke(d, corner, GAP * 0.8, GAP * 0.8, big)
    # a ponte do meio: do septo do nariz até o pé dos dentes
    stroke(d, [(0.5, 0.636), (0.5, TEETH_BOTTOM)], GAP, GAP * 0.8, big)
    r = GAP * 0.95 * big
    d.ellipse((0.5 * big - r, BITE * big - r, 0.5 * big + r, BITE * big + r), fill=0)
    # reflexo no crânio (alto à esquerda): arco fino que afina nas pontas
    hi = catmull([(0.304, 0.262), (0.342, 0.194), (0.400, 0.152), (0.458, 0.136)], closed=False)
    n = len(hi)
    for i in range(n - 1):
        t = i / (n - 2)
        w = GAP * (0.35 + 0.85 * math.sin(math.pi * t)) * big
        (x0, y0), (x1, y1) = hi[i], hi[i + 1]
        d.line((x0 * big, y0 * big, x1 * big, y1 * big), fill=0, width=max(1, round(w)))
    return im.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


# ===== tinta de spray =====
def noise(rng: np.random.Generator, size: int, blur: float) -> np.ndarray:
    """Ruído suave em 0..1 (ruído branco borrado e normalizado)."""
    raw = Image.fromarray((rng.random((size, size)) * 255).astype(np.uint8), "L")
    soft = np.asarray(raw.filter(ImageFilter.GaussianBlur(blur)), dtype=np.float32)
    lo, hi = float(soft.min()), float(soft.max())
    return (soft - lo) / max(hi - lo, 1e-6)


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def paint(mask: Image.Image, seed: int = SEED) -> Image.Image:
    rng = np.random.default_rng(seed)
    m = np.asarray(mask, dtype=np.float32) / 255.0
    # borda de tinta: a máscara borrada cortada num limiar que varia um pouco (a chapa nunca veda
    # igual em todo lugar); a borda continua firme, só deixa de ser régua
    soft = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.6)), dtype=np.float32) / 255.0
    wobble = noise(rng, SIZE, 3.0) - 0.5
    edge = smoothstep(0.38, 0.62, soft + wobble * 0.16)
    # névoa do spray fora da chapa: halo fraco e respingos finos perto da borda
    halo = np.asarray(mask.filter(ImageFilter.GaussianBlur(7.0)), dtype=np.float32) / 255.0
    near = np.clip(halo * 3.0, 0.0, 1.0) * (1.0 - edge)
    speck = (rng.random((SIZE, SIZE)) < 0.022 * near).astype(np.float32) * rng.uniform(
        0.25, 0.7, (SIZE, SIZE)
    )
    mist = halo * 0.16
    # densidade da tinta: manchas largas (passada da lata) e grão fino
    passes = 0.84 + 0.16 * noise(rng, SIZE, 38.0)
    grain = 0.9 + 0.1 * rng.random((SIZE, SIZE)).astype(np.float32)
    alpha = np.maximum(edge * passes * grain, np.maximum(mist, speck))
    alpha = np.clip(alpha, 0.0, 1.0)
    # o que a geometria não pintou (olhos, pontes) também recebe só névoa, nunca tinta cheia
    alpha = np.where(m < 0.02, np.minimum(alpha, 0.3), alpha)
    rgba = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (alpha * 255 + 0.5).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def build(seed: int = SEED) -> Image.Image:
    return paint(geometry(), seed)


def preview(img: Image.Image, path: Path) -> None:
    """Prévia: a caveira tingida de osso sobre oliva escuro e sobre céu claro, em 3 tamanhos."""
    bone = (234, 226, 200)
    half = 920
    sheet = Image.new("RGB", (2 * half, 560), (20, 22, 16))
    sheet.paste((176, 190, 196), (half, 0, 2 * half, 560))
    tinted = Image.new("RGBA", img.size, bone + (0,))
    tinted.putalpha(img.getchannel("A"))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.putalpha(img.getchannel("A").point(lambda a: int(a * 0.55)))
    for bx in (0, half):
        x = 20
        for size in (520, 220, 110):
            sh = shadow.resize((size, size), Image.Resampling.LANCZOS)
            sk = tinted.resize((size, size), Image.Resampling.LANCZOS)
            y = 20 + (520 - size) // 2
            sheet.paste(sh, (bx + x + 3, y + 4), sh)
            sheet.paste(sk, (bx + x, y), sk)
            x += size + 20
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print("prévia", path)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--saida", type=Path, default=OUT)
    ap.add_argument("--previa", type=Path, default=None)
    a = ap.parse_args()
    img = build()
    a.saida.parent.mkdir(parents=True, exist_ok=True)
    img.save(a.saida, optimize=True)
    print("gravado", a.saida, img.size)
    if a.previa:
        preview(img, a.previa)


if __name__ == "__main__":
    main()
