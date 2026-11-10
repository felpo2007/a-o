"""Gera os moldes clássicos de roupa do Roblox (585 x 559 px) por código.

Por que por código: os 6 moldes e as 3 texturas de tecido pedidos ao ForgeGUI terminaram todos em
`outcome_unknown` ("worker interruption" aos 15 min), e a regra do serviço é não regenerar. O
molde é 100% sob controle aqui: trama (sarja no OG-107, tela nos uniformes VC), tingimento e
desbotamento, costuras, bolsos, botões, cinto, vincos, suor, sol nos ombros e lama nas pernas, nas
cores de DESIGN.md (D-30). Uso: `uv run python tools/make_clothing.py`.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/clothing"
W, H = 585, 559

# Regiões do molde clássico (x0, y0, x1, y1), iguais para camisa e calça.
TORSO = {
    "up": (231, 8, 359, 72),
    "front": (231, 74, 359, 202),
    "right": (165, 74, 229, 202),
    "left": (361, 74, 425, 202),
    "back": (427, 74, 555, 202),
    "down": (231, 204, 359, 268),
}
R_LIMB = {
    "up": (217, 289, 281, 353),
    "L": (19, 355, 83, 483),
    "B": (85, 355, 149, 483),
    "R": (151, 355, 215, 483),
    "F": (217, 355, 281, 483),
    "down": (217, 485, 281, 549),
}
L_LIMB = {
    "up": (308, 289, 372, 353),
    "F": (308, 355, 372, 483),
    "L": (374, 355, 438, 483),
    "B": (440, 355, 504, 483),
    "R": (506, 355, 570, 483),
    "down": (308, 485, 372, 549),
}

# Cores (RGB): OG-107 desbotado; cáqui e verde-escuro da Força Principal; cintos.
UNIFORMS = {
    "us_shirt": {
        "cloth": (104, 108, 74),
        "kind": "shirt",
        "belt": None,
        "pockets": "flap",
        "weave": "twill",
    },
    "us_pants": {
        "cloth": (98, 102, 70),
        "kind": "pants",
        "belt": (84, 88, 58),
        "cargo": True,
        "weave": "twill",
    },
    "vc_khaki_shirt": {"cloth": (170, 150, 108), "kind": "shirt", "belt": None, "pockets": "flap"},
    "vc_khaki_pants": {"cloth": (164, 144, 104), "kind": "pants", "belt": (112, 84, 52)},
    "vc_green_shirt": {"cloth": (64, 76, 54), "kind": "shirt", "belt": None, "pockets": "flap"},
    "vc_green_pants": {"cloth": (60, 72, 51), "kind": "pants", "belt": (112, 84, 52)},
}


def shade(c: tuple[int, int, int], f: float) -> tuple[int, int, int]:
    return tuple(int(max(0, min(255, v * f))) for v in c)  # type: ignore[return-value]


def smooth(rng: np.random.Generator, cell: int) -> np.ndarray:
    """Ruído suave (0 de média, ~1 de desvio) por interpolação bicúbica de uma grade grossa."""
    g = rng.normal(0, 1, (H // cell + 3, W // cell + 3)).astype(np.float32)
    im = Image.fromarray(g, "F").resize((W + 3 * cell, H + 3 * cell), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32)[cell : cell + H, cell : cell + W]


def fabric(base: tuple[int, int, int], seed: int, weave: str = "plain") -> np.ndarray:
    """Algodão: fios (ruído fino), trama (sarja diagonal no OG-107; tela nos uniformes VC),
    variação de tingimento e desbotamento em manchas largas."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    threads = rng.normal(0, 4.5, (H, W))
    if weave == "twill":
        pattern = 5 * np.sin((2 * xx + yy) * 1.15) + 2 * np.sin((xx - 2 * yy) * 0.6)
    else:
        pattern = 3.5 * np.sin(xx * 2.3) * np.sin(yy * 2.3) + 1.5 * np.sin((xx + yy) * 0.9)
    dye = 3.5 * smooth(rng, 24)
    fade = 3.5 * smooth(rng, 64)
    img = np.zeros((H, W, 3), dtype=np.float32)
    for i in range(3):
        img[..., i] = base[i] + threads + pattern + dye + fade * (1.0 if i < 2 else 0.6)
    return np.clip(img, 0, 255).astype(np.uint8)


def blend(arr: np.ndarray, mask: np.ndarray, color: tuple[int, int, int], alpha: float) -> None:
    m = np.clip(mask, 0, 1)[..., None] * alpha
    arr[...] = arr * (1 - m) + np.array(color, dtype=np.float32) * m


def weather(img: Image.Image, spec: dict, seed: int) -> Image.Image:
    """Uso de campo: vincos em cotovelos/joelhos, suor (camisa), sol nos ombros, lama nas pernas."""
    rng = np.random.default_rng(seed + 100)
    arr = np.asarray(img.convert("RGB"), dtype=np.float32).copy()
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    limbs = [*R_LIMB.items(), *L_LIMB.items()]
    # vincos: faixas escuras/claras no meio do membro (cotovelo / joelho)
    for face, (x0, y0, x1, y1) in limbs:
        if face in ("up", "down"):
            continue
        mid = y0 + (y1 - y0) * 0.5
        band = np.exp(-(((yy - mid) / 6) ** 2)) * (np.sin(xx * 0.35 + yy * 0.2) * 0.5 + 0.5)
        region = (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
        arr[region] *= (1 - 0.18 * band[region])[..., None]
    if spec["kind"] == "shirt":
        # sol: ombros e alto das costas mais claros; suor: costas e axilas mais escuros
        x0, y0, x1, y1 = TORSO["up"]
        arr[y0:y1, x0:x1] *= 1.08
        sweat = np.clip(smooth(rng, 40) * 0.6 + 0.4, 0, 1)
        for name in ("back", "left", "right"):
            x0, y0, x1, y1 = TORSO[name]
            m = np.zeros((H, W), dtype=np.float32)
            m[y0:y1, x0:x1] = sweat[y0:y1, x0:x1] * np.linspace(0.9, 0.2, y1 - y0)[:, None]
            blend(arr, m, (40, 40, 30), 0.22)
    else:
        # lama: sobe da barra até o joelho em manchas; respingos
        mud = smooth(rng, 18)
        for face, (x0, y0, x1, y1) in limbs:
            if face in ("up", "down"):
                continue
            h = y1 - y0
            grad = np.clip((yy - (y0 + 0.55 * h)) / (0.45 * h), 0, 1)
            knee = np.exp(-(((yy - (y0 + 0.5 * h)) / 8) ** 2)) * 0.6
            m = np.zeros((H, W), dtype=np.float32)
            sel = (slice(y0, y1), slice(x0, x1))
            m[sel] = np.clip((grad[sel] + knee[sel]) * (0.55 + 0.45 * mud[sel]), 0, 1)
            blend(arr, m, (98, 74, 46), 0.62)
            for _ in range(18):  # respingos
                cx, cy = rng.integers(x0, x1), rng.integers(y0 + h // 3, y1)
                r = float(rng.uniform(1.0, 2.6))
                dot = ((xx - cx) ** 2 + (yy - cy) ** 2) <= r * r
                blend(arr, dot.astype(np.float32), (84, 64, 40), 0.85)
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    return out


def seams(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], c) -> None:
    x0, y0, x1, y1 = box
    dark = shade(c, 0.72)
    d.rectangle((x0, y0, x1 - 1, y1 - 1), outline=dark)
    for x in range(x0 + 3, x1 - 3, 4):  # pesponto
        d.point((x, y0 + 2), fill=shade(c, 0.8))
        d.point((x, y1 - 3), fill=shade(c, 0.8))


def pocket(d: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, c, flap: bool) -> None:
    d.rectangle((x, y, x + w, y + h), outline=shade(c, 0.65), fill=shade(c, 0.96))
    if flap:
        flap_box = (x - 1, y - 2, x + w + 1, y + h // 3)
        d.rectangle(flap_box, outline=shade(c, 0.6), fill=shade(c, 0.9))
        bx = x + w // 2
        d.ellipse((bx - 2, y + h // 3 - 4, bx + 2, y + h // 3), fill=shade(c, 0.5))


def draw_shirt(img: Image.Image, spec: dict) -> None:
    c = spec["cloth"]
    d = ImageDraw.Draw(img)
    for box in list(TORSO.values()) + list(R_LIMB.values()) + list(L_LIMB.values()):
        seams(d, box, c)
    fx0, fy0, fx1, fy1 = TORSO["front"]
    mid = (fx0 + fx1) // 2
    # carcela e botões
    d.line((mid, fy0, mid, fy1), fill=shade(c, 0.6), width=2)
    for y in range(fy0 + 14, fy1 - 4, 22):
        d.ellipse((mid + 3, y - 2, mid + 7, y + 2), fill=shade(c, 0.45))
    # gola em V
    d.polygon([(mid - 22, fy0), (mid, fy0 + 26), (mid + 22, fy0)], fill=shade(c, 0.78))
    d.line((mid - 22, fy0, mid, fy0 + 26, mid + 22, fy0), fill=shade(c, 0.55), width=2)
    # dois bolsos de peito com aba
    pocket(d, fx0 + 14, fy0 + 30, 34, 38, c, spec.get("pockets") == "flap")
    pocket(d, fx1 - 48, fy0 + 30, 34, 38, c, spec.get("pockets") == "flap")
    # costas: pala
    bx0, by0, bx1, _ = TORSO["back"]
    d.line((bx0, by0 + 26, bx1, by0 + 26), fill=shade(c, 0.7), width=2)
    # mangas arregaçadas (dobra escura no meio do braço)
    for limb in (R_LIMB, L_LIMB):
        for face in ("L", "B", "R", "F"):
            x0, y0, x1, _ = limb[face]
            d.rectangle((x0, y0 + 58, x1 - 1, y0 + 70), fill=shade(c, 0.82))
            d.line((x0, y0 + 70, x1 - 1, y0 + 70), fill=shade(c, 0.6), width=2)


def draw_pants(img: Image.Image, spec: dict) -> None:
    c = spec["cloth"]
    d = ImageDraw.Draw(img)
    for box in list(TORSO.values()) + list(R_LIMB.values()) + list(L_LIMB.values()):
        seams(d, box, c)
    belt = spec.get("belt")
    if belt:
        for face in ("front", "right", "left", "back"):
            x0, _, x1, y1 = TORSO[face]
            d.rectangle((x0, y1 - 22, x1 - 1, y1 - 10), fill=belt, outline=shade(belt, 0.7))
        fx0, _, fx1, fy1 = TORSO["front"]
        mid = (fx0 + fx1) // 2
        d.rectangle((mid - 8, fy1 - 24, mid + 8, fy1 - 8), outline=(150, 140, 110), width=2)
    # braguilha
    fx0, _, fx1, fy1 = TORSO["front"]
    mid = (fx0 + fx1) // 2
    d.line((mid, fy1 - 8, mid, fy1), fill=shade(c, 0.55), width=2)
    # bolsos laterais na coxa (calça do USMC) ou só costura
    for limb, face in ((R_LIMB, "L"), (L_LIMB, "R")):
        x0, y0, x1, _ = limb[face]
        if spec.get("cargo"):
            pocket(d, x0 + 10, y0 + 22, x1 - x0 - 20, 34, c, True)
        d.line(((x0 + x1) // 2, y0, (x0 + x1) // 2, y0 + 128), fill=shade(c, 0.75))
    # barra dobrada / lama nas pernas
    for limb in (R_LIMB, L_LIMB):
        for face in ("L", "B", "R", "F"):
            x0, _, x1, y1 = limb[face]
            mud = Image.new("RGB", (x1 - x0, 26), (92, 74, 50))
            mask = Image.linear_gradient("L").resize((x1 - x0, 26)).point(lambda v: int(v * 0.55))
            img.paste(mud, (x0, y1 - 26), mask)
            d.line((x0, y1 - 6, x1 - 1, y1 - 6), fill=shade(c, 0.6), width=2)


def make(name: str, spec: dict, seed: int) -> Path:
    arr = fabric(spec["cloth"], seed, spec.get("weave", "plain"))
    img = Image.fromarray(arr, "RGB")
    if spec["kind"] == "shirt":
        draw_shirt(img, spec)
    else:
        draw_pants(img, spec)
    img = weather(img, spec, seed)
    # fora das regiões úteis: transparente (o Roblox ignora, mas deixa o arquivo limpo)
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    for box in list(TORSO.values()) + list(R_LIMB.values()) + list(L_LIMB.values()):
        md.rectangle((box[0], box[1], box[2] - 1, box[3] - 1), fill=255)
    img.putalpha(mask)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.png"
    img.save(path, optimize=True)
    return path


def main() -> None:
    for i, (name, spec) in enumerate(UNIFORMS.items()):
        p = make(name, spec, 1965 + i)
        print("ok", p.relative_to(ROOT))


if __name__ == "__main__":
    main()
