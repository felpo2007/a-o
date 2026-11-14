"""Moldes das skins de uniforme (Shared/Skins): OG-107 desbotado, tiger stripe e duck hunter; na
D-131, tiger stripe "tadpole", lagarto (EUA), áo bà ba marrom e tiger stripe capturado (VC).

Mesmo molde clássico de 585 × 559 e a mesma alfaiataria da v3 (`tools/make_clothing_v3.py`):
este script importa a v3 e só troca o tecido de base antes das costuras, bolsos, dobras, sol, suor
e lama. Mãos ficam transparentes como na v3 (o `Characters` põe a cor de pele), por isso as chaves
terminam em `_v3` (é o que o `Gear.uniform` usa para saber disso).

Fidelidade (1965; conferir em foto antes de subir, `check = "foto"` no catálogo):
- **OG-107 desbotado:** o utilitário de algodão sateen da v3, lavado e queimado de sol: tecido mais
  claro e acinzentado, sol mais forte nos ombros e o estêncil do bolso quase sumido.
- **Tiger stripe:** o padrão dos assessores americanos junto das unidades sul-vietnamitas em 1965
  (fuzileiros assessores da VNMC, Rangers, Forças Especiais): listras horizontais de pincel, verde
  e marrom sobre fundo claro, com traços pretos finos. Tecido de tela, corte de utilitário, sem
  estêncil (não era do USMC).
- **Duck hunter:** padrão comercial de caça em manchas (verde, marrom e pontos escuros sobre fundo
  cáqui claro), usado por assessores e Forças Especiais no começo dos anos 60; o "frogskin" dos
  fuzileiros no Pacífico (1943-44) era da mesma família. Sem estêncil.

As cores são de olho (PLACEHOLDER até a foto). O padrão é desenhado no espaço do molde inteiro
(listras horizontais no tronco e em volta dos membros).

Uso: `uv run python tools/make_clothing_skins.py` (moldes em `assets/clothing/skins/`)
     `uv run python tools/make_clothing_skins.py --conferencia` (folha de conferência em
     `testes/conferencia_uniformes_skins.png`, como a da v3).
"""

from __future__ import annotations

import sys
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_clothing_v3 as v3  # noqa: E402

ROOT = v3.ROOT
OUT = ROOT / "assets/clothing/skins"
REVIEW = ROOT / "testes/conferencia_uniformes_skins.png"
SS = v3.SS

Color = tuple[int, int, int]

# OG-107 lavado: mais claro e mais cinza que o OG107 da v3 (98, 102, 70)
FADED = (122, 124, 96)
FADED_PANTS = (118, 120, 92)
FADED_SUN = (156, 154, 126)
FADED_STENCIL = (72, 74, 60)  # tinta do estêncil quase sumida no pano lavado
# tiger stripe: fundo, verde, marrom e preto
TIGER = ((146, 138, 92), (84, 98, 58), (92, 72, 44), (30, 30, 28))
TIGER_SUN = (170, 160, 118)
# duck hunter: fundo cáqui claro, verde, marrom e pontos escuros
DUCK = ((164, 150, 110), (102, 108, 68), (110, 86, 58), (58, 48, 36))
DUCK_SUN = (184, 172, 134)
# D-131 (lote 17, dono: "coloque umas camuflagens diferentes tipo tigrado etc"):
# tiger stripe "tadpole" (o esparso do começo dos anos 60, Rangers e assessores): muito fundo claro
# e traços curtos e finos com "cabeça" (girino)
TADPOLE = ((156, 150, 104), (70, 92, 52), (98, 74, 46), (28, 28, 26))
TADPOLE_SUN = (178, 170, 128)
# lagarto (TAP 47 francês; os paraquedistas sul-vietnamitas e os assessores deles no começo dos anos
# 60): pinceladas verticais curtas, verde e marrom, sobre fundo verde-claro
LIZARD = ((134, 140, 96), (68, 96, 56), (110, 82, 52))
LIZARD_SUN = (160, 162, 122)
# VC: áo bà ba tingido de củ nâu (o tubérculo que dá o marrom-avermelhado do camponês do Sul)
BROWN = (92, 62, 44)
BROWN_SUN = (128, 96, 72)
# VC: tiger stripe capturado do ARVN, gasto e encardido (mais escuro que o dos assessores)
TIGER_WORN = ((128, 120, 82), (72, 86, 50), (82, 64, 40), (28, 28, 26))
TIGER_WORN_SUN = (150, 140, 104)


@dataclass(frozen=True)
class Skin:
    spec: v3.Spec
    pattern: str  # "plain" | "tiger" | "duck" | "tadpole" | "lizard"
    layers: tuple[Color, ...]  # cores por cima do fundo (spec.cloth), na ordem de pintura
    stencil: Color | None  # cor do estêncil USMC (None: sem estêncil)
    sun: float


def _spec(
    kind: str,
    cloth: Color,
    faded: Color,
    weave: str,
    seed: int,
    style: str = "usmc",
    sleeves: str = "down",
) -> v3.Spec:
    if kind == "shirt":
        return v3.Spec("shirt", style, cloth, faded, weave, sleeves, seed)
    return v3.Spec("pants", style, cloth, faded, weave, seed=seed)


# Chaves = nomes em AssetIds.Clothing e em Skins.CATALOG (shirt/pants).
OUTFITS: dict[str, Skin] = {
    "us_faded_shirt_v3": Skin(
        _spec("shirt", FADED, FADED_SUN, "sateen", 5101), "plain", (), FADED_STENCIL, 1.7
    ),
    "us_faded_pants_v3": Skin(
        _spec("pants", FADED_PANTS, FADED_SUN, "sateen", 5102), "plain", (), None, 1.4
    ),
    "us_tiger_shirt_v3": Skin(
        _spec("shirt", TIGER[0], TIGER_SUN, "plain", 5201), "tiger", TIGER[1:], None, 0.7
    ),
    "us_tiger_pants_v3": Skin(
        _spec("pants", TIGER[0], TIGER_SUN, "plain", 5202), "tiger", TIGER[1:], None, 0.7
    ),
    "us_duck_shirt_v3": Skin(
        _spec("shirt", DUCK[0], DUCK_SUN, "plain", 5301), "duck", DUCK[1:], None, 0.7
    ),
    "us_duck_pants_v3": Skin(
        _spec("pants", DUCK[0], DUCK_SUN, "plain", 5302), "duck", DUCK[1:], None, 0.7
    ),
    # D-131 (lote 17)
    "us_tadpole_shirt_v3": Skin(
        _spec("shirt", TADPOLE[0], TADPOLE_SUN, "plain", 5401), "tadpole", TADPOLE[1:], None, 0.7
    ),
    "us_tadpole_pants_v3": Skin(
        _spec("pants", TADPOLE[0], TADPOLE_SUN, "plain", 5402), "tadpole", TADPOLE[1:], None, 0.7
    ),
    "us_lizard_shirt_v3": Skin(
        _spec("shirt", LIZARD[0], LIZARD_SUN, "plain", 5501), "lizard", LIZARD[1:], None, 0.7
    ),
    "us_lizard_pants_v3": Skin(
        _spec("pants", LIZARD[0], LIZARD_SUN, "plain", 5502), "lizard", LIZARD[1:], None, 0.7
    ),
    "vc_brown_shirt_v3": Skin(
        _spec("shirt", BROWN, BROWN_SUN, "plain", 5601, "ao_ba_ba", "forearm"),
        "plain",
        (),
        None,
        1.2,
    ),
    "vc_brown_pants_v3": Skin(
        _spec("pants", (88, 60, 42), BROWN_SUN, "plain", 5602, "ao_ba_ba"), "plain", (), None, 1.0
    ),
    "vc_tiger_shirt_v3": Skin(
        _spec("shirt", TIGER_WORN[0], TIGER_WORN_SUN, "plain", 5701, "vc_uniform"),
        "tiger",
        TIGER_WORN[1:],
        None,
        0.9,
    ),
    "vc_tiger_pants_v3": Skin(
        _spec("pants", TIGER_WORN[0], TIGER_WORN_SUN, "plain", 5702, "vc_uniform"),
        "tiger",
        TIGER_WORN[1:],
        None,
        0.9,
    ),
}
SETS = [
    ("OG-107 desbotado (skin_us_faded)", "us_faded_shirt_v3", "us_faded_pants_v3", "usmc"),
    ("Tiger stripe, assessores (skin_us_tiger)", "us_tiger_shirt_v3", "us_tiger_pants_v3", "usmc"),
    ("Duck hunter (skin_us_duck)", "us_duck_shirt_v3", "us_duck_pants_v3", "usmc"),
    (
        "Tiger stripe tadpole (skin_us_tadpole)",
        "us_tadpole_shirt_v3",
        "us_tadpole_pants_v3",
        "usmc",
    ),
    ("Lagarto, paraquedistas (skin_us_lizard)", "us_lizard_shirt_v3", "us_lizard_pants_v3", "usmc"),
    ("Áo bà ba marrom (skin_vc_brown)", "vc_brown_shirt_v3", "vc_brown_pants_v3", "vc"),
    ("Tiger stripe capturado (skin_vc_tiger)", "vc_tiger_shirt_v3", "vc_tiger_pants_v3", "vc"),
]


# --------------------------------------------------------------------------------------------
# Padrões
# --------------------------------------------------------------------------------------------
def aniso_noise(rng: np.random.Generator, shape: tuple[int, int], cx: int, cy: int) -> np.ndarray:
    """Ruído suave (média 0, desvio ~1) com célula cx × cy: listras quando cx >> cy."""
    h, w = shape
    g = rng.normal(0, 1, (h // cy + 3, w // cx + 3)).astype(np.float32)
    im = Image.fromarray(g, "F").resize((w + 3 * cx, h + 3 * cy), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32)[cy : cy + h, cx : cx + w]


def edge(field: np.ndarray, level: float, soft: float = 0.06) -> np.ndarray:
    """Máscara 0..1 de field > level com borda curta (tinta, não degradê)."""
    return np.clip((field - level) / soft + 0.5, 0, 1)


def pattern_masks(skin: Skin, seed: int) -> list[np.ndarray]:
    rng = np.random.default_rng(seed + 77)
    shape = (v3.H * SS, v3.W * SS)
    rough = aniso_noise(rng, shape, 3 * SS, 3 * SS)  # borda de pincel irregular
    if skin.pattern == "tiger":
        # verde e marrom em faixas largas; preto em traços finos e compridos
        green = aniso_noise(rng, shape, 60 * SS, 8 * SS) + 0.3 * rough
        brown = aniso_noise(rng, shape, 46 * SS, 6 * SS) + 0.3 * rough
        black = aniso_noise(rng, shape, 70 * SS, 4 * SS) + 0.25 * rough
        return [edge(green, 0.25), edge(brown, 0.55), edge(black, 1.05, 0.05)]
    if skin.pattern == "tadpole":
        # D-131: o esparso: traços mais curtos e finos, com mais fundo à mostra; a "cabeça" do
        # girino é uma mancha curta na ponta do traço preto
        green = aniso_noise(rng, shape, 34 * SS, 5 * SS) + 0.3 * rough
        brown = aniso_noise(rng, shape, 28 * SS, 4 * SS) + 0.3 * rough
        black = aniso_noise(rng, shape, 40 * SS, 3 * SS) + 0.25 * rough
        heads = aniso_noise(rng, shape, 9 * SS, 5 * SS) + 0.2 * rough
        return [
            edge(green, 0.7),
            edge(brown, 0.95),
            np.maximum(edge(black, 1.25, 0.05), edge(heads, 1.6, 0.05)),
        ]
    if skin.pattern == "lizard":
        # D-131: pinceladas verticais curtas (célula estreita e alta), o verde por baixo do marrom
        green = aniso_noise(rng, shape, 4 * SS, 26 * SS) + 0.35 * rough
        brown = aniso_noise(rng, shape, 3 * SS, 20 * SS) + 0.35 * rough
        return [edge(green, 0.55), edge(brown, 0.85)]
    # duck hunter: manchas redondas de tamanhos diferentes e pontos escuros
    green = v3.smooth_noise(rng, shape, 14 * SS) + 0.25 * rough
    brown = v3.smooth_noise(rng, shape, 10 * SS) + 0.25 * rough
    dots = v3.smooth_noise(rng, shape, 4 * SS) + 0.2 * rough
    return [edge(green, 0.45), edge(brown, 0.65), edge(dots, 1.25, 0.08)]


def camo_fabric(skin: Skin, rgb: np.ndarray) -> np.ndarray:
    """Pinta o padrão sobre o tecido da v3 sem perder a trama: o desvio do fio em volta da cor de
    base é somado à cor de cada mancha."""
    base = np.asarray(skin.spec.cloth, np.float32)
    weave = rgb - base
    pat = np.broadcast_to(base, rgb.shape).copy()
    for color, m in zip(skin.layers, pattern_masks(skin, skin.spec.seed), strict=True):
        k = m[..., None]
        pat = pat * (1 - k) + np.asarray(color, np.float32) * k
    return pat + weave


def washed(skin: Skin, rgb: np.ndarray) -> np.ndarray:
    """Lavado: manchas largas mais claras e fio puído (OG-107 desbotado)."""
    rng = np.random.default_rng(skin.spec.seed + 13)
    shape = rgb.shape[:2]
    blotch = v3.smooth_noise(rng, shape, 90 * SS)
    lift = (5.0 + 4.0 * blotch)[..., None] * np.array([1.0, 1.0, 1.1], np.float32)
    return rgb + lift


# --------------------------------------------------------------------------------------------
# Montagem (as mesmas etapas do v3.render, com o tecido trocado)
# --------------------------------------------------------------------------------------------
@contextmanager
def patched(**names) -> Iterator[None]:
    """Troca nomes do módulo v3 só durante a pintura (estêncil sem tinta ou desbotado)."""
    old = {k: getattr(v3, k) for k in names}
    for k, v in names.items():
        setattr(v3, k, v)
    try:
        yield
    finally:
        for k, v in old.items():
            setattr(v3, k, v)


def _no_stencil(*_args, **_kwargs) -> None:
    return None


def render(skin: Skin) -> Image.Image:
    spec = skin.spec
    p = v3.Painter(spec)
    if skin.pattern == "plain":
        p.rgb = washed(skin, p.rgb)
    else:
        p.rgb = camo_fabric(skin, p.rgb)
    names: dict = {}
    if skin.stencil is None:
        names["stencil_usmc"] = _no_stencil
    else:
        names["STENCIL"] = skin.stencil
    with patched(**names):
        v3.volume(p)
        if spec.kind == "shirt":
            v3.shirt_torso(p)
            v3.sleeves(p)
            v3.sun(p, skin.sun)
            v3.sweat(p, 1.0)
            for part in ("r", "l"):  # cotovelo encardido
                for f in v3.limb_sides(part):
                    _, v = p.uv(f)
                    m = np.exp(-(((v - v3.ELBOW / 128) / 0.06) ** 2)) * np.clip(
                        0.4 + 0.5 * p.noise(f, 5), 0, 1
                    )
                    p.tint(f, m, v3.MUD_DRY, 0.15)
        else:
            v3.pants_torso(p)
            v3.legs(p)
            v3.sun(p, skin.sun * 0.6)
    return v3.finish(p)


def make(key: str) -> Path:
    img = render(OUTFITS[key])
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{key}.png"
    img.save(path, optimize=True)
    return path


def main(argv: list[str]) -> None:
    paths = {}
    for key in OUTFITS:
        paths[key] = make(key)
        print("ok", paths[key].relative_to(ROOT))
    if "--conferencia" in argv:
        with patched(SETS=SETS, REVIEW=REVIEW):
            print("ok", v3.review(paths).relative_to(ROOT))


if __name__ == "__main__":
    main(sys.argv[1:])
