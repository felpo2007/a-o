"""Rostos no estilo Roblox (D-237; substituem os pintados da D-236).

Pedido do dono: "retire esse rosto" e "quero rostos estilo roblox". Olhos pretos ovais com um
ponto de luz, sobrancelha simples e boca de um traço, sem sombra nem pele. O PNG é transparente e
a cor vem da cabeça (Corpo.PELE). São 12 expressões de soldado, as mesmas para os dois lados.

Saídas: assets/rostos/v3/rosto_NN.png (512 x 512) e assets/rostos/v3/previa.png.

Uso (a partir de vantuong65): uv run --group arte python tools/rostos/make_rostos3.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

RAIZ = Path(__file__).resolve().parents[2]
SAIDA = RAIZ / "assets" / "rostos" / "v3"
PX = 512
SS = 4
W = PX * SS
PRETO = (24, 22, 20, 255)
TONS = [(238, 206, 178), (204, 158, 120), (116, 80, 56)]

# olho: meia altura; sob: giro da sobrancelha em graus (+ = bravo), alt: distância ao olho;
# boca: "reta", "sorriso", "canto", "serio", "dentes", "aberta"
ROSTOS = [
    {"olho": 0.062, "sob": 0, "alt": 0.105, "boca": "reta"},
    {"olho": 0.062, "sob": 14, "alt": 0.095, "boca": "serio"},
    {"olho": 0.058, "sob": 8, "alt": 0.100, "boca": "canto"},
    {"olho": 0.066, "sob": -6, "alt": 0.115, "boca": "sorriso"},
    {"olho": 0.050, "sob": 18, "alt": 0.082, "boca": "reta"},
    {"olho": 0.062, "sob": 10, "alt": 0.098, "boca": "dentes"},
    {"olho": 0.058, "sob": 0, "alt": 0.105, "boca": "serio", "cicatriz": True},
    {"olho": 0.062, "sob": 12, "alt": 0.098, "boca": "reta", "bigode": True},
    {"olho": 0.054, "sob": 16, "alt": 0.088, "boca": "serio"},
    {"olho": 0.066, "sob": 4, "alt": 0.110, "boca": "aberta"},
    {"olho": 0.060, "sob": 0, "alt": 0.105, "boca": "reta", "bigode": True},
    {"olho": 0.056, "sob": 14, "alt": 0.092, "boca": "dentes", "cicatriz": True},
]


def p(x: float, y: float) -> tuple[float, float]:
    return x * W, y * W


def traco(d: ImageDraw.ImageDraw, pts: list[tuple[float, float]], e: float, cor=PRETO) -> None:
    """Linha grossa com as pontas redondas."""
    q = [p(*a) for a in pts]
    lg = int(e * W)
    d.line(q, fill=cor, width=lg, joint="curve")
    r = lg / 2
    for x, y in (q[0], q[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=cor)


def curva(w: float, y: float, f: float, inc: float = 0.0, n: int = 28) -> list[tuple[float, float]]:
    """Arco da boca: `f` > 0 sorri, `inc` levanta um canto."""
    out = []
    for i in range(n + 1):
        t = i / n * 2 - 1
        out.append((0.5 + t * w, y + f * (1 - t * t) - f + inc * t))
    return out


def boca(d: ImageDraw.ImageDraw, tipo: str) -> None:
    y, e = 0.665, 0.017
    if tipo == "reta":
        traco(d, [(0.43, y), (0.57, y)], e)
    elif tipo == "serio":
        traco(d, curva(0.075, y + 0.008, -0.018), e)
    elif tipo == "canto":
        traco(d, curva(0.075, y, 0.012, -0.016), e)
    elif tipo == "sorriso":
        traco(d, curva(0.095, y - 0.012, 0.04), e)
    elif tipo == "aberta":
        d.ellipse([*p(0.46, y - 0.032), *p(0.54, y + 0.040)], fill=PRETO)
    elif tipo == "dentes":
        forma = [p(*a) for a in curva(0.095, y - 0.022, 0.012)]
        forma += [p(*a) for a in reversed(curva(0.08, y + 0.03, 0.03))]
        d.polygon(forma, fill=PRETO)
        branco = [p(*a) for a in curva(0.08, y - 0.012, 0.010)]
        branco += [p(*a) for a in reversed(curva(0.074, y + 0.008, 0.012))]
        d.polygon(branco, fill=(244, 242, 236, 255))


def rosto(k: dict) -> Image.Image:
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dist, y = 0.135, 0.455
    h = k["olho"]
    for s in (-1, 1):
        cx = 0.5 + s * dist
        d.ellipse([*p(cx - 0.036, y - h), *p(cx + 0.036, y + h)], fill=PRETO)
        # o ponto de luz fica do mesmo lado nos dois olhos
        luz_y = y - h * 0.62
        d.ellipse([*p(cx - 0.020, luz_y), *p(cx - 0.002, luz_y + 0.026)], fill=(255,) * 4)
        a = math.radians(k["sob"]) * -s
        yb = y - h - k["alt"] + 0.058
        m = 0.058
        traco(
            d,
            [
                (cx - m * math.cos(a), yb + m * math.sin(a)),
                (cx + m * math.cos(a), yb - m * math.sin(a)),
            ],
            0.021,
        )
    boca(d, k["boca"])
    if k.get("bigode"):
        for s in (-1, 1):
            traco(d, [(0.5, 0.606), (0.5 + s * 0.05, 0.610), (0.5 + s * 0.082, 0.630)], 0.024)
    if k.get("cicatriz"):
        cor = (150, 74, 66, 255)
        traco(d, [(0.705, 0.385), (0.655, 0.535)], 0.010, cor)
        for t in (0.25, 0.5, 0.75):
            x, yy = 0.705 - 0.05 * t, 0.385 + 0.15 * t
            traco(d, [(x - 0.016, yy - 0.004), (x + 0.016, yy + 0.004)], 0.006, cor)
    return img.resize((PX, PX), Image.LANCZOS)


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    feitos = []
    for i, k in enumerate(ROSTOS, 1):
        im = rosto(k)
        im.save(SAIDA / f"rosto_{i:02d}.png", optimize=True)
        feitos.append(im)
    t = 160
    prev = Image.new("RGB", (t * 6, t * 2), (30, 30, 30))
    for i, im in enumerate(feitos):
        q = Image.new("RGBA", (t, t), (*TONS[i % 3], 255))
        q.alpha_composite(im.resize((t, t), Image.LANCZOS))
        prev.paste(q.convert("RGB"), ((i % 6) * t, (i // 6) * t))
    prev.save(SAIDA / "previa.png")
    print(f"{len(feitos)} rostos em {SAIDA}")


if __name__ == "__main__":
    main()
