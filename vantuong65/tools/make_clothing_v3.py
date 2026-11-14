"""Moldes clássicos v3 do Roblox (585 × 559 px), por código: mais detalhe e fidelidade (D-30).

Por que por código: os moldes pedidos ao ForgeGUI terminaram em `outcome_unknown` e a regra do
serviço é não regenerar (D-30). A v2 (`tools/make_clothing.py`) continua valendo como reserva: o
`Characters` só usa a v3 quando o ID dela em `AssetIds.Clothing` não for 0.

Fidelidade (agosto de 1965, Operação Starlite):
- **USMC:** utilitário OG-107 de algodão sateen (a USMC trocou o P56 pelo OG-107 do Exército em
  1964). Camisa com 2 bolsos de peito com aba de cantos cortados e botão, carcela de botões de
  plástico, gola aberta sobre a camiseta verde, estêncil preto da águia-globo-âncora com "USMC" no
  bolso esquerdo. Calça de 4 bolsos (2 faca na frente, 2 traseiros com aba): **sem bolso de carga**
  (a calça de carga é a do uniforme de selva, que só chegou aos fuzileiros de 1966 em diante).
  Calça presa por cima da bota preta de couro (bota de selva também é posterior). Mangas abaixadas
  no padrão e arregaçadas acima do cotovelo no cosmético `us_utility_rolled` (Commerce).
- **Força Principal VC (1º Regimento):** uniforme de algodão cáqui ou verde (camisa de gola virada,
  2 bolsos de peito com aba, usada por fora da calça), calça arregaçada à meia canela e sandália
  Ho Chi Minh (sola de pneu, tiras de câmara). **Guerrilha local:** "pijama" preto (áo bà ba),
  sem gola, 2 bolsos baixos, mangas arregaçadas.

Mapeamento (template oficial de 585 × 559, as mesmas coordenadas da v2; o teste confere):
- tronco: 128 px de altura; os 96 de cima vão para o UpperTorso e os 32 de baixo para o LowerTorso;
- braço e perna: 128 px; 64 para a parte de cima, 48 para a de baixo e 16 para mão/pé.
  (Split das diretrizes de UV R15 do DevForum, "Classic Clothing UV Mapping Guidelines [R15]".)
- partes transparentes mostram a cor do corpo: mão, antebraço arregaçado, decote e perna do VC
  ficam com a pele (o `Characters` põe a cor de pele nessas partes quando usa a v3).

Pintura em 2× (supersampling) e redução por média com alfa pré-multiplicado: costuras e letras sem
serrilhado. Sombra/volume, dobras, costuras pespontadas, desgaste, suor com borda de sal, sol nos
ombros e lama com textura suave (sem ruído grosso).

Uso: `uv run python tools/make_clothing_v3.py` (moldes em `assets/clothing/v3/`)
     `uv run python tools/make_clothing_v3.py --conferencia` (também a folha de conferência em
     `testes/conferencia_uniformes_v3.png`, moldes lado a lado e vistas de frente e de costas).
"""

from __future__ import annotations

import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/clothing/v3"
REVIEW = ROOT / "testes/conferencia_uniformes_v3.png"
W, H = 585, 559
SS = 2  # supersampling: pinta em 2× e reduz no fim

# Regiões do molde clássico (x0, y0, x1, y1), iguais às da v2 (tools/make_clothing.py).
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
UPPER_TORSO = 96  # px do tronco no UpperTorso; abaixo é o LowerTorso (cintura/quadril)
ELBOW = 64  # fim do UpperArm/UpperLeg (cotovelo/joelho)
WRIST = 112  # começo da mão/pé

Color = tuple[int, int, int]
Box = tuple[int, int, int, int]

# Cor de pele de referência só para a folha de conferência (no jogo é a cor do corpo).
SKIN_REF: Color = (171, 125, 90)


@dataclass(frozen=True)
class Spec:
    kind: str  # "shirt" | "pants"
    style: str  # "usmc" | "vc_uniform" | "ao_ba_ba"
    cloth: Color
    faded: Color  # cor do tecido queimado de sol
    weave: str  # "sateen" | "plain"
    sleeves: str = "down"  # camisa: "down" | "rolled" | "forearm"
    seed: int = 1965
    patch: bool = False  # calça: remendo no joelho direito


# Chaves = nomes em AssetIds.Clothing e nomes dos arquivos em assets/clothing/v3.
OG107 = (98, 102, 70)
OG107_SUN = (126, 128, 98)
KHAKI = (160, 142, 104)
KHAKI_SUN = (184, 168, 130)
GREEN = (70, 82, 58)
GREEN_SUN = (98, 108, 82)
BLACK = (40, 40, 42)
BLACK_SUN = (72, 68, 64)
OUTFITS: dict[str, Spec] = {
    "us_shirt_v3": Spec("shirt", "usmc", OG107, OG107_SUN, "sateen", "down", 3101),
    "us_shirt_rolled_v3": Spec("shirt", "usmc", OG107, OG107_SUN, "sateen", "rolled", 3102),
    "us_pants_v3": Spec("pants", "usmc", (94, 98, 68), OG107_SUN, "sateen", seed=3103),
    "vc_khaki_shirt_v3": Spec("shirt", "vc_uniform", KHAKI, KHAKI_SUN, "plain", "down", 3201),
    "vc_khaki_pants_v3": Spec(
        "pants", "vc_uniform", (154, 136, 100), KHAKI_SUN, "plain", seed=3202, patch=True
    ),
    "vc_green_shirt_v3": Spec("shirt", "vc_uniform", GREEN, GREEN_SUN, "plain", "down", 3301),
    "vc_green_pants_v3": Spec("pants", "vc_uniform", (66, 78, 55), GREEN_SUN, "plain", seed=3302),
    "vc_black_shirt_v3": Spec("shirt", "ao_ba_ba", BLACK, BLACK_SUN, "plain", "forearm", 3401),
    "vc_black_pants_v3": Spec(
        "pants", "ao_ba_ba", (38, 38, 40), BLACK_SUN, "plain", seed=3402, patch=True
    ),
}
# Conjuntos (camisa, calça) para a folha de conferência.
SETS = [
    ("USMC, mangas abaixadas (padrão)", "us_shirt_v3", "us_pants_v3", "usmc"),
    ("USMC, mangas arregaçadas (us_utility_rolled)", "us_shirt_rolled_v3", "us_pants_v3", "usmc"),
    ("VC Força Principal, cáqui (padrão)", "vc_khaki_shirt_v3", "vc_khaki_pants_v3", "vc"),
    ("VC Força Principal, verde (vc_green)", "vc_green_shirt_v3", "vc_green_pants_v3", "vc"),
    ("Guerrilha local, áo bà ba preto", "vc_black_shirt_v3", "vc_black_pants_v3", "vc"),
]

MUD_WET: Color = (74, 60, 44)
MUD_DRY: Color = (128, 112, 86)
LEATHER: Color = (30, 29, 28)
RUBBER: Color = (24, 24, 24)
STENCIL: Color = (22, 22, 20)
TSHIRT: Color = (62, 68, 48)


# --------------------------------------------------------------------------------------------
# Faces do molde
# --------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Face:
    """Uma face do molde. `side`: front/back/right/left/up/down (tronco) ou F/B/inner/outer/up/down
    (membro). `right`: para onde aponta a borda DIREITA da imagem vista de fora (front, back, outer,
    inner, left ou right do personagem). Ex.: na frente do tronco a direita da imagem é o lado
    esquerdo do personagem (o template é desenhado como se você olhasse o boneco de frente)."""

    part: str  # "torso" | "r" | "l" (membro direito/esquerdo: braço na camisa, perna na calça)
    side: str
    box: Box
    right: str

    @property
    def w(self) -> int:
        return self.box[2] - self.box[0]

    @property
    def h(self) -> int:
        return self.box[3] - self.box[1]

    @property
    def limb(self) -> bool:
        return self.part != "torso"

    def sl(self) -> tuple[slice, slice]:
        x0, y0, x1, y1 = self.box
        return slice(y0 * SS, y1 * SS), slice(x0 * SS, x1 * SS)

    def front_at_left(self) -> bool:
        """Numa face lateral, a frente do corpo fica na borda esquerda da imagem?"""
        return self.right != "front"


def faces() -> list[Face]:
    out = [
        Face("torso", "up", TORSO["up"], "left"),
        Face("torso", "front", TORSO["front"], "left"),
        Face("torso", "right", TORSO["right"], "front"),
        Face("torso", "left", TORSO["left"], "back"),
        Face("torso", "back", TORSO["back"], "right"),
        Face("torso", "down", TORSO["down"], "left"),
        # membro direito: L = interno, R = externo
        Face("r", "up", R_LIMB["up"], "inner"),
        Face("r", "inner", R_LIMB["L"], "back"),
        Face("r", "B", R_LIMB["B"], "outer"),
        Face("r", "outer", R_LIMB["R"], "front"),
        Face("r", "F", R_LIMB["F"], "inner"),
        Face("r", "down", R_LIMB["down"], "inner"),
        # membro esquerdo: L = externo, R = interno
        Face("l", "up", L_LIMB["up"], "outer"),
        Face("l", "F", L_LIMB["F"], "outer"),
        Face("l", "outer", L_LIMB["L"], "back"),
        Face("l", "B", L_LIMB["B"], "inner"),
        Face("l", "inner", L_LIMB["R"], "front"),
        Face("l", "down", L_LIMB["down"], "outer"),
    ]
    return out


FACES = faces()


def face(part: str, side: str) -> Face:
    for f in FACES:
        if f.part == part and f.side == side:
            return f
    raise KeyError((part, side))


def limb_sides(part: str) -> list[Face]:
    return [face(part, s) for s in ("F", "B", "inner", "outer")]


# --------------------------------------------------------------------------------------------
# Desenho em máscaras por face (coordenadas em px 1× locais da face; pintura em 2×)
# --------------------------------------------------------------------------------------------
class D:
    def __init__(self, im: Image.Image) -> None:
        self.d = ImageDraw.Draw(im)

    @staticmethod
    def _p(pts) -> list[tuple[float, float]]:
        return [(x * SS, y * SS) for x, y in pts]

    def line(self, pts, w: float = 1.0, fill: int = 255) -> None:
        self.d.line(self._p(pts), fill=fill, width=max(1, round(w * SS)), joint="curve")

    def poly(self, pts, fill: int = 255) -> None:
        self.d.polygon(self._p(pts), fill=fill)

    def rect(self, x0: float, y0: float, x1: float, y1: float, fill: int = 255) -> None:
        self.d.rectangle((x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1), fill=fill)

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, fill: int = 255) -> None:
        self.d.ellipse(((cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS), fill=fill)


def smooth_noise(rng: np.random.Generator, shape: tuple[int, int], cell: int) -> np.ndarray:
    """Ruído suave (média 0, desvio ~1) por interpolação bicúbica de uma grade grossa."""
    h, w = shape
    g = rng.normal(0, 1, (h // cell + 3, w // cell + 3)).astype(np.float32)
    im = Image.fromarray(g, "F").resize((w + 3 * cell, h + 3 * cell), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32)[cell : cell + h, cell : cell + w]


class Painter:
    def __init__(self, spec: Spec) -> None:
        self.spec = spec
        self.rng = np.random.default_rng(spec.seed)
        self.rgb = fabric(spec.cloth, spec.seed, spec.weave)
        self.a = np.zeros((H * SS, W * SS), dtype=np.float32)
        for f in FACES:
            sy, sx = f.sl()
            self.a[sy, sx] = 1.0

    # máscara desenhada na face (0..1), com desfoque opcional (em px 1×)
    def mask(self, f: Face, draw: Callable[[D], None], blur: float = 0.0) -> np.ndarray:
        im = Image.new("L", (f.w * SS, f.h * SS), 0)
        draw(D(im))
        if blur > 0:
            im = im.filter(ImageFilter.GaussianBlur(blur * SS))
        return np.asarray(im, dtype=np.float32) / 255.0

    def uv(self, f: Face) -> tuple[np.ndarray, np.ndarray]:
        """Coordenadas normalizadas (u da esquerda para a direita, v de cima para baixo)."""
        h, w = f.h * SS, f.w * SS
        v, u = np.mgrid[0:h, 0:w].astype(np.float32)
        return (u + 0.5) / w, (v + 0.5) / h

    def noise(self, f: Face, cell: float) -> np.ndarray:
        return smooth_noise(self.rng, (f.h * SS, f.w * SS), max(2, int(cell * SS)))

    def paint(self, f: Face, m: np.ndarray, color, alpha: float = 1.0) -> None:
        sy, sx = f.sl()
        k = np.clip(m * alpha, 0, 1)[..., None]
        self.rgb[sy, sx] = self.rgb[sy, sx] * (1 - k) + np.asarray(color, np.float32) * k

    def shade(self, f: Face, m: np.ndarray, factor: float) -> None:
        sy, sx = f.sl()
        self.rgb[sy, sx] *= (1 + (factor - 1) * np.clip(m, 0, 1))[..., None]

    def tint(self, f: Face, m: np.ndarray, color, amount: float) -> None:
        """Mistura parcial para uma cor mantendo a textura (luminância relativa)."""
        sy, sx = f.sl()
        cur = self.rgb[sy, sx]
        lum = cur.mean(axis=2, keepdims=True)
        base = np.asarray(self.spec.cloth, np.float32).mean()
        target = np.asarray(color, np.float32) * (lum / max(base, 1.0)) ** 0.5
        k = np.clip(m * amount, 0, 1)[..., None]
        self.rgb[sy, sx] = cur * (1 - k) + target * k

    def clear(self, f: Face, m: np.ndarray) -> None:
        sy, sx = f.sl()
        self.a[sy, sx] *= 1 - np.clip(m, 0, 1)

    def opaque(self, f: Face, m: np.ndarray) -> None:
        sy, sx = f.sl()
        self.a[sy, sx] = np.maximum(self.a[sy, sx], np.clip(m, 0, 1))

    def alpha_set(self, f: Face, m: np.ndarray, value: float) -> None:
        """Alfa = value onde m (para lama sobre a pele: semitransparente)."""
        sy, sx = f.sl()
        k = np.clip(m, 0, 1)
        self.a[sy, sx] = self.a[sy, sx] * (1 - k) + value * k

    # ---- primitivas de alfaiataria ----
    def crease(
        self,
        f: Face,
        pts,
        w: float = 1.6,
        dark: float = 0.2,
        light: float = 0.08,
        off: tuple[float, float] = (0.0, 1.1),
    ) -> None:
        """Dobra: sulco escuro desfocado e, ao lado, a crista iluminada. Desfoque largo de
        propósito: dobra é volume, não traço."""
        m = self.mask(f, lambda d: d.line(pts, w), blur=w * 0.85)
        self.shade(f, m, 1 - dark * 0.85)
        if light > 0:
            ox, oy = off
            shifted = [(x + ox * 1.3, y + oy * 1.3) for x, y in pts]
            ml = self.mask(f, lambda d: d.line(shifted, w * 0.9), blur=w * 0.9)
            self.shade(f, ml * (1 - m), 1 + light)

    def seam(self, f: Face, pts, stitch_side: float = 1.6, double: bool = False) -> None:
        """Costura: vinco escuro, fio de luz e pesponto tracejado do lado."""
        m = self.mask(f, lambda d: d.line(pts, 0.7))
        self.shade(f, m, 0.70)
        hi = [(x + 0.6, y + 0.6) for x, y in pts]
        self.shade(f, self.mask(f, lambda d: d.line(hi, 0.5)) * (1 - m), 1.10)
        for off in (stitch_side, -stitch_side) if double else (stitch_side,):
            self.stitch(f, offset_poly(pts, off))

    def stitch(self, f: Face, pts, dash: float = 1.3, gap: float = 1.0) -> None:
        segs = dashes(pts, dash, gap)
        m = self.mask(f, lambda d: [d.line(s, 0.55) for s in segs])
        thread = np.asarray(self.spec.cloth, np.float32) * 1.22 + 6
        self.paint(f, m, np.clip(thread, 0, 255), 0.55)

    def button(self, f: Face, cx: float, cy: float, r: float, color) -> None:
        self.shade(f, self.mask(f, lambda d: d.ellipse(cx + 0.5, cy + 0.7, r, r), blur=0.6), 0.75)
        self.paint(f, self.mask(f, lambda d: d.ellipse(cx, cy, r, r)), color)
        rim = self.mask(f, lambda d: d.ellipse(cx, cy, r, r)) - self.mask(
            f, lambda d: d.ellipse(cx, cy, r * 0.7, r * 0.7)
        )
        self.shade(f, np.clip(rim, 0, 1), 0.8)
        self.shade(
            f,
            self.mask(f, lambda d: d.ellipse(cx - r * 0.3, cy - r * 0.35, r * 0.3, r * 0.25)),
            1.5,
        )
        for dx in (-0.45, 0.45):  # furos
            self.shade(f, self.mask(f, lambda d, dx=dx: d.ellipse(cx + dx * r, cy, 0.3, 0.3)), 0.55)

    def raised(self, f: Face, poly, lift: float = 1.03, shadow: float = 0.22) -> None:
        """Camada costurada por cima (bolso, aba): sombra embaixo e realce na peça."""
        sh = [(x + 0.5, y + 1.0) for x, y in poly]
        ms = self.mask(f, lambda d: d.poly(sh), blur=0.9)
        mp = self.mask(f, lambda d: d.poly(poly))
        self.shade(f, ms * (1 - mp), 1 - shadow)
        self.shade(f, mp, lift)
        self.seam(f, list(poly) + [poly[0]], stitch_side=-1.2)


def offset_poly(pts, d: float) -> list[tuple[float, float]]:
    """Desloca uma polilinha para o lado (normal de cada segmento)."""
    if len(pts) < 2:
        return list(pts)
    out = []
    p = np.asarray(pts, np.float64)
    for i in range(len(p)):
        a = p[max(i - 1, 0)]
        b = p[min(i + 1, len(p) - 1)]
        t = b - a
        n = np.array([-t[1], t[0]]) / (np.hypot(*t) or 1.0)
        q = p[i] + n * d
        out.append((float(q[0]), float(q[1])))
    return out


def dashes(pts, dash: float, gap: float) -> list[list[tuple[float, float]]]:
    out: list[list[tuple[float, float]]] = []
    carry = 0.0
    on = True
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:], strict=True):
        length = float(np.hypot(x1 - x0, y1 - y0))
        t = -carry
        while t < length:
            seg = dash if on else gap
            a, b = max(t, 0.0), min(t + seg, length)
            if on and b > a:
                out.append(
                    [
                        (x0 + (x1 - x0) * a / length, y0 + (y1 - y0) * a / length),
                        (x0 + (x1 - x0) * b / length, y0 + (y1 - y0) * b / length),
                    ]
                )
            if t + seg > length:
                carry = length - t
                break
            t += seg
            on = not on
        else:
            carry = 0.0
    return out


def fabric(base: Color, seed: int, weave: str) -> np.ndarray:
    """Algodão: fios finos, trama discreta (sateen ou tela), tingimento irregular e desbotamento
    em manchas largas. Amplitudes baixas de propósito: em 4 mm por pixel a trama mal aparece."""
    rng = np.random.default_rng(seed)
    hh, ww = H * SS, W * SS
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    threads = rng.normal(0, 2.2, (hh, ww)).astype(np.float32)
    if weave == "sateen":
        pattern = 1.4 * np.sin((xx + 2.0 * yy) * 0.62) + 0.6 * np.sin((xx - yy) * 0.31)
    else:
        pattern = 1.2 * np.sin(xx * 1.05) * np.sin(yy * 1.05) + 0.5 * np.sin((xx + yy) * 0.4)
    dye = 2.4 * smooth_noise(rng, (hh, ww), 40)
    fade = 3.0 * smooth_noise(rng, (hh, ww), 120)
    img = np.zeros((hh, ww, 3), dtype=np.float32)
    for i in range(3):
        img[..., i] = base[i] + threads + pattern + dye + fade * (1.0 if i < 2 else 0.7)
    return img


# --------------------------------------------------------------------------------------------
# Passos comuns
# --------------------------------------------------------------------------------------------
def volume(p: Painter) -> None:
    """Sombra pintada leve (o motor já ilumina): bordas das faces, lado interno dos membros,
    axila, virilha e as faces de baixo."""
    for f in FACES:
        u, v = p.uv(f)
        if f.side == "up":
            k = np.full_like(u, 1.04)
        elif f.side == "down":
            k = np.full_like(u, 0.74)
        elif f.limb:
            k = 1 - 0.11 * (2 * u - 1) ** 2
            if f.side == "inner":
                k *= 0.92
            if f.side == "B":
                k *= 0.97
        else:
            k = 1 - 0.06 * (2 * u - 1) ** 2
            if f.side in ("right", "left"):
                k *= 0.95
                k *= 1 - 0.10 * np.exp(-(((v - 0.02) / 0.10) ** 2))  # axila
            k *= 1 - 0.04 * v
        sy, sx = f.sl()
        p.rgb[sy, sx] *= k[..., None]


def sun(p: Painter, strength: float = 1.0) -> None:
    """Sol de agosto: ombros, alto das costas e parte de cima dos braços desbotados, em manchas."""
    for f in FACES:
        u, v = p.uv(f)
        if f.side == "up":
            m = np.ones_like(u) * 0.85
        elif f.part == "torso" and f.side in ("front", "back"):
            m = np.clip(1 - v / 0.35, 0, 1) * (0.55 if f.side == "front" else 0.8)
        elif f.limb and f.side in ("outer", "B", "F"):
            m = np.clip(1 - v / 0.5, 0, 1) * 0.45
        else:
            continue
        m = m * np.clip(0.75 + 0.45 * p.noise(f, 14), 0, 1.2)
        p.tint(f, m, p.spec.faded, 0.75 * strength)


def sweat(p: Painter, amount: float = 1.0, salt: float = 1.0) -> None:
    """Suor seco: mancha escura nas axilas e ao longo da coluna, com marcas de sal claras, fracas
    e interrompidas (linha de sal contínua parecia contorno desenhado na primeira conferência)."""
    spots: list[tuple[Face, Callable[[np.ndarray, np.ndarray], np.ndarray]]] = [
        (
            face("torso", "right"),
            lambda u, v: np.exp(-(((u - 0.5) / 0.30) ** 2 + ((v - 0.08) / 0.16) ** 2)),
        ),
        (
            face("torso", "left"),
            lambda u, v: np.exp(-(((u - 0.5) / 0.30) ** 2 + ((v - 0.08) / 0.16) ** 2)),
        ),
        (
            face("torso", "back"),
            lambda u, v: np.exp(-(((u - 0.5) / 0.13) ** 2 + ((v - 0.40) / 0.30) ** 2)),
        ),
    ]
    for f, shape in spots:
        u, v = p.uv(f)
        n = p.noise(f, 14)
        field = shape(u, v) + 0.10 * n
        core = np.clip((field - 0.35) / 0.30, 0, 1)
        p.shade(f, core, 1 - 0.14 * amount)
        breakup = np.clip(p.noise(f, 5) * 0.8 + 0.2, 0, 1)
        for level, wgt in ((0.33, 1.0), (0.22, 0.6)):  # duas marcas de maré
            rim = np.exp(-(((field - level) / 0.035) ** 2)) * (1 - core) * breakup
            p.tint(f, rim * salt, (205, 200, 182), 0.10 * wgt)


def mud_lower_legs(
    p: Painter, top: float, reach: float, amount: float = 1.0, boot_top: float | None = None
) -> None:
    """Lama: sobe da barra em manchas e respingos; molhada embaixo, seca e clara por cima.
    Na bota (abaixo de `boot_top`) entra fraca: o couro preto tem de continuar lendo como bota."""
    for part in ("r", "l"):
        for f in limb_sides(part):
            u, v = p.uv(f)
            n = p.noise(f, 6)
            grad = np.clip((v - top) / max(reach, 1e-3), 0, 1) ** 1.4
            m = np.clip(grad * (0.5 + 0.6 * n), 0, 1) * amount
            if boot_top is not None:
                m = m * np.where(v * 128 >= boot_top, 0.3, 1.0)
            p.tint(f, m, MUD_DRY, 0.45)
            p.tint(f, np.clip(m * 1.4 - 0.7, 0, 1), MUD_WET, 0.5)
            rng = p.rng
            drops = []
            for _ in range(int(7 * amount)):
                cx = float(rng.uniform(2, f.w - 2))
                cy = float(rng.uniform(f.h * (top + 0.15), f.h * 0.82))
                r = float(rng.uniform(0.5, 1.2))
                drops.append((cx, cy, r))
            md = p.mask(
                f, lambda d, drops=drops: [d.ellipse(x, y, r, r * 0.8) for x, y, r in drops], 0.4
            )
            p.tint(f, md, MUD_WET, 0.45)


# --------------------------------------------------------------------------------------------
# Peças: camisa
# --------------------------------------------------------------------------------------------
def pocket(
    p: Painter,
    f: Face,
    x: float,
    y: float,
    w: float,
    h: float,
    flap: float,
    flap_style: str,
    button_color,
    pencil: bool = False,
) -> None:
    """Bolso chapado com aba (cantos cortados, reta ou em V) e botão."""
    body = [
        (x, y),
        (x + w, y),
        (x + w, y + h - 2),
        (x + w - 2, y + h),
        (x + 2, y + h),
        (x, y + h - 2),
    ]
    p.raised(f, body, lift=1.025, shadow=0.20)
    # leve volume (bolso estufado) e gasto na borda
    p.shade(
        f, p.mask(f, lambda d: d.rect(x + 2, y + flap + 2, x + w - 2, y + h - 2), blur=2.0), 1.03
    )
    if flap <= 0:
        return
    if flap_style == "clipped":
        fl = [
            (x - 0.6, y - 0.6),
            (x + w + 0.6, y - 0.6),
            (x + w + 0.6, y + flap - 2.2),
            (x + w - 2.2, y + flap),
            (x + 2.2, y + flap),
            (x - 0.6, y + flap - 2.2),
        ]
    elif flap_style == "v":
        fl = [
            (x - 0.6, y - 0.6),
            (x + w + 0.6, y - 0.6),
            (x + w + 0.6, y + flap - 3),
            (x + w / 2, y + flap + 1.5),
            (x - 0.6, y + flap - 3),
        ]
    else:
        fl = [
            (x - 0.6, y - 0.6),
            (x + w + 0.6, y - 0.6),
            (x + w + 0.6, y + flap),
            (x - 0.6, y + flap),
        ]
    p.raised(f, fl, lift=1.04, shadow=0.30)
    # borda da aba gasta (mais clara)
    edge = p.mask(f, lambda d: d.line(fl[2:] + [fl[-1]], 0.9), blur=0.4)
    p.tint(f, edge, p.spec.faded, 0.5)
    p.button(f, x + w / 2, y + flap - 2.6, 1.55, button_color)
    if pencil:  # fenda da caneta na aba do bolso esquerdo
        px = x + w * 0.22
        p.shade(f, p.mask(f, lambda d: d.line([(px, y + 1.5), (px, y + flap - 2.5)], 0.7)), 0.6)


def stencil_usmc(p: Painter, f: Face, cx: float, top: float) -> None:
    """Estêncil preto: águia-globo-âncora e "USMC" embaixo (bolso esquerdo da camisa)."""

    def ega(d: D) -> None:
        gy = top + 6.2
        # âncora: haste, cepo e braços
        d.line([(cx, top + 0.6), (cx, gy + 6.6)], 0.9)
        d.line([(cx - 2.6, top + 1.6), (cx + 2.6, top + 1.6)], 0.8)
        d.line(
            [
                (cx - 5.2, gy + 3.2),
                (cx - 3.6, gy + 6.0),
                (cx, gy + 7.0),
                (cx + 3.6, gy + 6.0),
                (cx + 5.2, gy + 3.2),
            ],
            0.9,
        )
        # globo: anel e meridianos (com as pontes do estêncil)
        d.ellipse(cx, gy, 4.1, 4.1)
        d.ellipse(cx, gy, 3.1, 3.1, fill=0)
        d.line([(cx - 3.4, gy - 0.8), (cx + 3.4, gy - 0.8)], 0.6)
        d.line([(cx - 3.0, gy + 1.6), (cx + 3.0, gy + 1.6)], 0.6)
        d.ellipse(cx + 0.4, gy + 0.2, 1.4, 3.0)
        d.ellipse(cx + 0.4, gy + 0.2, 0.7, 2.3, fill=0)
        # águia: asas abertas sobre o globo
        d.poly(
            [
                (cx - 4.4, gy - 6.0),
                (cx - 0.6, gy - 3.6),
                (cx, gy - 5.0),
                (cx + 0.6, gy - 3.6),
                (cx + 4.4, gy - 6.0),
                (cx + 2.2, gy - 3.4),
                (cx, gy - 3.0),
                (cx - 2.2, gy - 3.4),
            ]
        )
        # "USMC" (fonte de estêncil 3 × 4,5 px)
        glyphs = {
            "U": [(0, 0), (0, 4.5), (3, 4.5), (3, 0)],
            "S": [(3, 0), (0, 0), (0, 2.2), (3, 2.2), (3, 4.5), (0, 4.5)],
            "M": [(0, 4.5), (0, 0), (1.5, 2.4), (3, 0), (3, 4.5)],
            "C": [(3, 0), (0, 0), (0, 4.5), (3, 4.5)],
        }
        x = cx - 8.0
        ty = gy + 8.6
        for ch in "USMC":
            d.line([(x + gx, ty + gy_) for gx, gy_ in glyphs[ch]], 0.75)
            x += 4.4

    m = p.mask(f, ega, blur=0.25)
    # tinta de spray: densidade irregular
    m = m * np.clip(0.82 + 0.25 * p.noise(f, 3), 0.55, 1.0)
    p.paint(f, m, STENCIL, 0.88)


def shirt_torso(p: Painter) -> None:
    s = p.spec
    usmc = s.style == "usmc"
    aobaba = s.style == "ao_ba_ba"
    fr = face("torso", "front")
    bk = face("torso", "back")
    mid = 64.0
    tuck = UPPER_TORSO + 3 if usmc else 128  # US: camisa por dentro da calça
    btn = (70, 72, 52) if usmc else ((52, 40, 30) if not aobaba else (30, 30, 32))

    # --- decote e gola ---
    if usmc:
        vee = [(mid - 12, 0), (mid, 21), (mid + 12, 0)]
        # camiseta verde no V (malha: listras finas)
        mv = p.mask(fr, lambda d: d.poly(vee))
        p.paint(fr, mv, TSHIRT)
        u, v = p.uv(fr)
        p.shade(fr, mv * (0.5 + 0.5 * np.sin(u * 900)), 0.95)
        p.crease(
            fr, [(mid - 9, 2.2), (mid, 4.5), (mid + 9, 2.2)], 1.4, 0.25, 0.1
        )  # gola da camiseta
        p.shade(fr, mv * np.clip(1 - v * 6, 0, 1), 0.8)
    elif aobaba:
        vee = [(mid - 9, 0), (mid, 11), (mid + 9, 0)]
        p.clear(fr, p.mask(fr, lambda d: d.poly(vee)))
        p.seam(fr, [(mid - 9.5, 0), (mid, 11.8), (mid + 9.5, 0)], stitch_side=1.4)
    else:
        vee = [(mid - 11, 0), (mid, 17), (mid + 11, 0)]
        p.clear(fr, p.mask(fr, lambda d: d.poly(vee)))
    if not aobaba:
        for sgn in (-1, 1):  # folhas da gola virada, abertas sobre o peito
            leaf = [
                (mid + sgn * 30, 0),
                (mid + sgn * 11.5, 0),
                (mid + sgn * 2.5, 19 if usmc else 15),
                (mid + sgn * 19, 21 if usmc else 17),
            ]
            p.opaque(fr, p.mask(fr, lambda d, leaf=leaf: d.poly(leaf)))  # a gola cobre o decote
            p.raised(fr, leaf, lift=1.06, shadow=0.32)
        # carcela
        top = 21 if usmc else 17
        p.raised(
            fr,
            [(mid - 3.5, top), (mid + 3.5, top), (mid + 3.5, tuck), (mid - 3.5, tuck)],
            1.02,
            0.12,
        )
        ys = [30, 46, 62, 78, 94] if usmc else [24, 44, 64, 84, 104]
    else:
        p.seam(fr, [(mid + 2.5, 11), (mid + 2.5, 128)], stitch_side=1.3)
        ys = [20, 40, 60, 80, 100]
    for y in ys:
        if y < tuck - 2:
            p.button(fr, mid, y, 1.6 if not aobaba else 1.3, btn)

    # --- bolsos ---
    if usmc:
        pocket(p, fr, mid - 47, 25, 31, 35, 11, "clipped", btn)  # direito do soldado
        pocket(p, fr, mid + 16, 25, 31, 35, 11, "clipped", btn, pencil=True)  # esquerdo
        stencil_usmc(p, fr, mid + 31.5, 39)
    elif aobaba:
        pocket(p, fr, mid - 50, 86, 29, 27, 0, "none", btn)
        pocket(p, fr, mid + 21, 86, 29, 27, 0, "none", btn)
    else:
        pocket(p, fr, mid - 45, 22, 28, 31, 9, "straight", btn)
        pocket(p, fr, mid + 17, 22, 28, 31, 9, "straight", btn)

    # --- dobras da frente ---
    for sgn in (-1, 1):
        p.crease(
            fr, [(mid + sgn * 62, 14), (mid + sgn * 50, 30), (mid + sgn * 44, 46)], 1.5, 0.16, 0.07
        )
        p.crease(fr, [(mid + sgn * 60, 40), (mid + sgn * 52, 60)], 1.3, 0.12, 0.05)
    if usmc:  # camisa estufada por cima do cós
        for i, y in enumerate((88, 92.5, 96.5)):
            jitter = 3 * np.sin(i * 2.1)
            p.crease(
                fr,
                [(6, y + jitter), (34, y - 1.5), (62, y + 1), (92, y - 1.8), (122, y + jitter)],
                1.6,
                0.18,
                0.08,
            )
    else:  # franzido sob o cinto (o cinto 3D fica no alto do LowerTorso): poucas pregas irregulares
        rng = np.random.default_rng(p.spec.seed + 7)
        for x in (11, 27, 44, 83, 101, 117):
            x = x + float(rng.uniform(-3, 3))
            j = float(rng.uniform(-3, 3))
            p.crease(fr, [(x + j, 84 + rng.uniform(-3, 3)), (x, 99)], 1.6, 0.14, 0.06, off=(1.0, 0))
            p.crease(
                fr,
                [(x, 106), (x + j * 1.5, 116 + rng.uniform(-3, 4))],
                1.6,
                0.12,
                0.05,
                off=(1.0, 0),
            )

    # --- costas ---
    p.raised(
        bk, [(mid - 22, 0), (mid + 22, 0), (mid + 22, 5.5), (mid - 22, 5.5)], 1.05, 0.25
    )  # gola
    yoke = 20 if usmc else 17
    p.seam(bk, [(0, yoke), (128, yoke)], stitch_side=1.4, double=usmc)
    if usmc:
        p.crease(
            bk, [(mid - 2, yoke + 2), (mid - 3, 60), (mid - 1, 92)], 1.3, 0.10, 0.05, off=(1.2, 0)
        )
    for sgn in (-1, 1):
        p.crease(
            bk, [(mid + sgn * 60, 16), (mid + sgn * 36, 40), (mid + sgn * 30, 58)], 1.6, 0.16, 0.07
        )
    if usmc:
        for i, y in enumerate((89, 93.5, 97)):
            jitter = 2.5 * np.cos(i * 1.7)
            p.crease(bk, [(4, y), (40, y + jitter), (86, y - 1.4), (124, y + 0.6)], 1.6, 0.18, 0.08)
    else:
        rng = np.random.default_rng(p.spec.seed + 11)
        for x in (14, 36, 58, 79, 97, 116):
            x = x + float(rng.uniform(-3, 3))
            p.crease(
                bk,
                [(x, 86 + rng.uniform(-3, 3)), (x + rng.uniform(-2, 2), 100)],
                1.6,
                0.13,
                0.05,
                off=(1.0, 0),
            )

    # --- laterais: costura do lado e dobras da axila ---
    for side in ("right", "left"):
        f = face("torso", side)
        p.seam(f, [(32, 4), (32, tuck)], stitch_side=1.4)
        for dx in (-14, -6, 6, 14):
            p.crease(f, [(32 + dx * 0.3, 1), (32 + dx, 18)], 1.2, 0.16, 0.05, off=(1.0, 0))
        if aobaba:  # fenda lateral da barra
            p.shade(f, p.mask(f, lambda d: d.line([(32, 108), (32, 128)], 1.2)), 0.45)
        if not usmc:
            p.seam(f, [(0, 125.5), (64, 125.5)], stitch_side=-1.3)

    # --- topo (ombros) e base ---
    up = face("torso", "up")
    p.raised(up, [(46, 22), (82, 22), (82, 44), (46, 44)], 1.05, 0.3)  # gola em volta do pescoço
    p.shade(up, p.mask(up, lambda d: d.rect(50, 26, 78, 40)), 0.55)
    p.seam(up, [(0, 40), (46, 38)], stitch_side=1.3)
    p.seam(up, [(82, 38), (128, 40)], stitch_side=1.3)
    dn = face("torso", "down")
    if usmc:
        p.clear(dn, np.ones((dn.h * SS, dn.w * SS), np.float32))
    if not usmc:
        p.seam(fr, [(0, 125.5), (128, 125.5)], stitch_side=-1.3)
        p.seam(bk, [(0, 125.5), (128, 125.5)], stitch_side=-1.3)

    # --- camisa por dentro da calça (US): abaixo da cintura é a calça ---
    if usmc:
        for f in (fr, bk, face("torso", "right"), face("torso", "left")):
            u, v = p.uv(f)
            edge = (tuck + 0.6 * p.noise(f, 10)) / 128.0
            p.clear(f, (v > edge).astype(np.float32))
            # sombra da blusa sobre o cós
            p.shade(f, np.exp(-(((v - edge + 0.010) / 0.012) ** 2)), 0.82)


def sleeves(p: Painter) -> None:
    s = p.spec
    usmc = s.style == "usmc"
    btn = (70, 72, 52) if usmc else ((52, 40, 30) if s.style == "vc_uniform" else (30, 30, 32))
    # rolo da manga arregaçada: acima do cotovelo (USMC) ou no meio do antebraço (áo bà ba)
    roll0, roll1 = (42.0, 56.0) if s.sleeves == "rolled" else (76.0, 88.0)
    for part in ("r", "l"):
        upf = face(part, "up")
        p.seam(upf, [(0, 4), (64, 4)], stitch_side=1.3)
        p.seam(upf, [(0, 60), (64, 60)], stitch_side=-1.3)
        dn = face(part, "down")
        p.clear(dn, np.ones((dn.h * SS, dn.w * SS), np.float32))  # palma da mão: pele
        for f in limb_sides(part):
            u, v = p.uv(f)
            # manga montada: costura no ombro
            p.seam(f, [(0, 3.5), (64, 3.5)], stitch_side=1.4)
            if f.side == "inner":  # costura de baixo da manga
                p.seam(f, [(32, 3.5), (32, 112)], stitch_side=1.3)
                for y in (8, 13):  # dobras da axila
                    p.crease(f, [(18, y), (32, y + 3), (46, y)], 1.2, 0.18, 0.06)
            if s.sleeves == "down":
                cuff0 = 101.0
                # dobras do cotovelo: frente e lado de dentro dobram, atrás estica
                if f.side in ("F", "inner"):
                    for i, y in enumerate((56, 61, 66, 71)):
                        a = 3.0 * (1 if i % 2 else -1)
                        p.crease(
                            f, [(4, y + a), (22, y - 2), (42, y + 2), (60, y - a)], 1.3, 0.2, 0.07
                        )
                else:
                    p.crease(f, [(10, 60), (32, 64), (54, 60)], 1.6, 0.08, 0.10)
                # manga franzida antes do punho
                for y in (88, 94):
                    p.crease(f, [(6, y), (30, y + 2), (58, y - 1)], 1.2, 0.14, 0.06)
                # punho
                cuff = [(-1, cuff0), (65, cuff0), (65, WRIST), (-1, WRIST)]
                p.raised(f, cuff, 1.04, 0.28)
                p.shade(f, p.mask(f, lambda d: d.rect(0, WRIST - 1.8, 64, WRIST)), 0.72)
                if f.side == "B":  # carcela e botão do punho
                    p.seam(f, [(20, 86), (20, cuff0)], stitch_side=1.2)
                    p.button(f, 26, (cuff0 + WRIST) / 2, 1.4, btn)
                p.clear(f, (v >= WRIST / 128).astype(np.float32))
            else:
                # manga franzida acima do rolo
                for y in (roll0 - 10, roll0 - 5):
                    p.crease(
                        f, [(4, y), (24, y + 2.4), (44, y - 1.2), (60, y + 1)], 1.3, 0.16, 0.06
                    )
                band = p.mask(f, lambda d: d.rect(-1, roll0, 65, roll1))
                # rolo: avesso menos desbotado, volume de cilindro e camadas
                vv = np.clip((v * 128 - roll0) / (roll1 - roll0), 0, 1)
                p.tint(f, band, s.cloth, 0.6)
                p.shade(f, band, 0.92)
                p.shade(f, band * np.exp(-(((vv - 0.35) / 0.25) ** 2)), 1.12)
                p.crease(
                    f,
                    [(-1, roll0 + (roll1 - roll0) * 0.55), (65, roll0 + (roll1 - roll0) * 0.55)],
                    1.0,
                    0.25,
                    0.0,
                )
                p.shade(
                    f, p.mask(f, lambda d: d.rect(-1, roll0 - 1.5, 65, roll0 + 0.5), blur=0.6), 0.7
                )
                p.shade(f, p.mask(f, lambda d: d.rect(-1, roll1 - 1.2, 65, roll1)), 0.7)
                if f.side in ("F", "inner"):
                    p.crease(f, [(8, roll0 + 3), (12, roll1 - 3)], 1.0, 0.18, 0.0)
                p.clear(f, (v >= roll1 / 128).astype(np.float32))


# --------------------------------------------------------------------------------------------
# Peças: calça
# --------------------------------------------------------------------------------------------
def pants_torso(p: Painter) -> None:
    s = p.spec
    usmc = s.style == "usmc"
    fr = face("torso", "front")
    bk = face("torso", "back")
    w0, w1 = UPPER_TORSO, UPPER_TORSO + 7.5  # cós
    for f in (fr, bk, face("torso", "right"), face("torso", "left")):
        p.raised(f, [(-1, w0), (f.w + 1, w0), (f.w + 1, w1), (-1, w1)], 1.03, 0.25)
        if usmc:  # cinto de calça (cadarço cáqui) passando pelos passadores
            belt = p.mask(f, lambda d, f=f: d.rect(-1, w0 + 1.2, f.w + 1, w1 - 1.0))
            p.paint(f, belt, (126, 112, 82), 0.92)
            p.shade(f, belt * (0.6 + 0.4 * p.noise(f, 2)), 0.94)
            # sombra da camisa estufada por cima do cós
            p.shade(
                f, p.mask(f, lambda d, f=f: d.rect(-1, w0 - 1, f.w + 1, w0 + 3), blur=1.2), 0.75
            )
        loops = (
            [12, 40, 88, 116]
            if f.side == "front"
            else ([16, 64, 112] if f.side == "back" else [32])
        )
        for x in loops:
            p.raised(
                f,
                [(x - 1.6, w0 - 1), (x + 1.6, w0 - 1), (x + 1.6, w1 + 1.5), (x - 1.6, w1 + 1.5)],
                1.06,
                0.3,
            )
    if usmc:  # fivela aberta de latão fosco
        m = p.mask(fr, lambda d: d.rect(58.5, w0 + 0.4, 69.5, w1 - 0.2))
        mi = p.mask(fr, lambda d: d.rect(60, w0 + 1.6, 68, w1 - 1.4))
        p.paint(fr, m * (1 - mi), (142, 122, 72))
        p.shade(fr, p.mask(fr, lambda d: d.line([(59, w0 + 0.8), (69, w0 + 0.8)], 0.5)), 1.35)
    # braguilha: carcela com pesponto em J
    p.seam(fr, [(68, w1), (68, 121), (66, 125.5), (63.5, 127.5)], stitch_side=-1.2)
    p.crease(fr, [(64, w1 + 1), (64, 127)], 1.0, 0.18, 0.0)
    # bolsos faca da frente
    p.seam(fr, [(8, w1), (17, 128)], stitch_side=-1.4)
    p.seam(fr, [(120, w1), (111, 128)], stitch_side=1.4)
    # dobras da virilha
    for sgn in (-1, 1):
        p.crease(fr, [(64 + sgn * 26, 112), (64 + sgn * 8, 126)], 1.4, 0.2, 0.07)
    p.seam(bk, [(64, w1), (64, 128)], stitch_side=1.3)
    for sgn in (-1, 1):
        p.crease(bk, [(64 + sgn * 30, 110), (64 + sgn * 6, 127)], 1.4, 0.18, 0.06)
    for side in ("right", "left"):
        f = face("torso", side)
        p.seam(f, [(32, w1), (32, 128)], stitch_side=1.3)
    dn = face("torso", "down")
    p.seam(dn, [(64, 0), (64, 64)], stitch_side=1.2)
    p.seam(dn, [(0, 32), (128, 32)], stitch_side=1.2)


def legs(p: Painter) -> None:
    s = p.spec
    usmc = s.style == "usmc"
    for part in ("r", "l"):
        upf = face(part, "up")
        p.shade(upf, np.ones((upf.h * SS, upf.w * SS), np.float32), 0.8)
        for f in limb_sides(part):
            u, v = p.uv(f)
            hem = 96.0 if usmc else 86.0  # US: fim da calça (bota); VC: começo do rolo
            # costuras externa e interna
            if f.side in ("outer", "inner"):
                p.seam(f, [(32, 0), (32, hem)], stitch_side=1.4, double=f.side == "outer")
            # bolso faca na frente (continua o do quadril), na borda de fora
            if f.side == "F":
                outer_left = f.right == "inner"
                x0 = 0 if outer_left else 64
                sg = 1 if outer_left else -1
                p.seam(f, [(x0, 0), (x0 + sg * 7, 11)], stitch_side=sg * 1.3)
                # dobras da coxa saindo da virilha
                xi = 64 - x0
                for k, y in enumerate((6, 16, 27)):
                    p.crease(
                        f,
                        [(xi, y), (32 + sg * (6 - 4 * k), y + 9), (x0 + sg * 10, y + 16)],
                        1.4,
                        0.15,
                        0.06,
                    )
            # bolso traseiro com aba (US: calça OG-107 de 4 bolsos)
            if f.side == "B" and usmc:
                pocket(p, f, 15, 3, 34, 24, 9, "straight", (70, 72, 52))
            # joelho: gasto claro, sujeira e dobras
            if f.side == "F":
                kn = np.exp(-(((u - 0.5) / 0.3) ** 2 + ((v - 0.52) / 0.07) ** 2))
                kn = kn * np.clip(0.7 + 0.5 * p.noise(f, 4), 0, 1.2)
                dk = 0.55 if s.style == "ao_ba_ba" else 1.0  # poeira aparece demais no preto
                p.tint(f, kn, s.faded, 0.4 * dk)
                p.tint(f, kn, MUD_DRY, 0.25 * dk)
                for i, y in enumerate((58, 63, 69, 74)):
                    a = 2.5 * (1 if i % 2 else -1)
                    p.crease(
                        f, [(3, y + a), (22, y - 1.5), (42, y + 1.5), (61, y - a)], 1.3, 0.17, 0.07
                    )
            if f.side == "B":
                for y in (62, 66, 70):
                    p.crease(f, [(6, y), (32, y + 2.4), (58, y)], 1.4, 0.22, 0.06)
            if f.side in ("outer", "inner"):
                p.crease(f, [(8, 62), (32, 66), (56, 63)], 1.3, 0.14, 0.06)
            if usmc:
                boots(p, f, u, v)
            else:
                rolled_hem(p, f, u, v)
        if usmc:
            sole_us(p, face(part, "down"))
        else:
            sole_hcm(p, face(part, "down"))
    if usmc:
        mud_lower_legs(p, top=0.45, reach=0.5, amount=0.8, boot_top=96.5)
    else:
        mud_lower_legs(p, top=0.5, reach=0.4, amount=0.5)


def boots(p: Painter, f: Face, u: np.ndarray, v: np.ndarray) -> None:
    """Bota de couro preto (sola moldada) com a calça presa por cima do cano."""
    top = 96.0
    # calça franzida por cima da bota
    for i, y in enumerate((84, 88, 91.5, 94.5)):
        a = 2.0 * np.sin(i * 1.9 + (1 if f.side == "F" else 0))
        p.crease(
            f,
            [(-1, y + a), (16, y - 1.5), (34, y + 1.8), (50, y - 1.2), (65, y + a)],
            1.5,
            0.24,
            0.10,
        )
    p.shade(f, np.exp(-(((v * 128 - top + 0.5) / 1.6) ** 2)), 0.55)  # sombra da barra no cano
    bm = (v * 128 >= top + 0.5).astype(np.float32)
    leather = np.zeros((f.h * SS, f.w * SS, 3), np.float32)
    n = p.noise(f, 3)
    big = p.noise(f, 12)
    for i in range(3):
        leather[..., i] = LEATHER[i] + 3 * n + 3.5 * big
    # volume do couro: brilho no meio da face, mais na biqueira
    leather *= (1 + 0.35 * np.exp(-(((u - 0.5) / 0.22) ** 2)))[..., None]
    sy, sx = f.sl()
    k = bm[..., None]
    p.rgb[sy, sx] = p.rgb[sy, sx] * (1 - k) + leather * k
    if f.side == "F":
        # lingueta e cadarço cruzado com ilhoses
        p.shade(f, p.mask(f, lambda d: d.rect(26, top + 1, 38, 117)), 0.8)
        for y in np.arange(top + 2.5, 117, 3.4):
            for x in (24.5, 39.5):
                p.paint(f, p.mask(f, lambda d, x=x, y=y: d.ellipse(x, y, 0.8, 0.8)), (92, 90, 84))
            p.paint(
                f, p.mask(f, lambda d, y=y: d.line([(24.5, y), (39.5, y + 3.4)], 0.8)), (18, 17, 16)
            )
            p.paint(
                f, p.mask(f, lambda d, y=y: d.line([(39.5, y), (24.5, y + 3.4)], 0.8)), (26, 25, 23)
            )
        # biqueira
        p.shade(f, p.mask(f, lambda d: d.ellipse(32, 125, 22, 6), blur=1.6), 1.6)
        p.shade(f, p.mask(f, lambda d: d.line([(10, 119), (32, 116.5), (54, 119)], 0.8)), 0.6)
    if f.side == "B":
        p.seam(f, [(32, top + 1), (32, 112)], stitch_side=1.2)
        p.shade(f, p.mask(f, lambda d: d.rect(14, 112, 50, 125), blur=1.0), 1.25)  # contraforte
    if f.side in ("outer", "inner"):
        p.crease(f, [(4, 110), (32, 113), (60, 110)], 1.3, 0.3, 0.12)  # dobra do peito do pé
        front_left = f.front_at_left()
        x_toe = 0 if front_left else 64
        p.shade(f, p.mask(f, lambda d: d.ellipse(x_toe, 124, 18, 6), blur=1.4), 1.4)
    # vira costurada e sola de borracha
    p.stitch(f, [(0, 124.6), (64, 124.6)], 1.0, 0.8)
    sole = p.mask(f, lambda d: d.rect(-1, 125.6, 65, 129))
    p.paint(f, sole, RUBBER)
    p.shade(f, p.mask(f, lambda d: d.line([(-1, 125.8), (65, 125.8)], 0.5)), 1.6)
    # couro gasto e lama seca na biqueira e na sola
    scuff = np.clip(p.noise(f, 2) - 0.9, 0, 1) * bm
    p.tint(f, scuff, (92, 88, 80), 0.6)
    dry = np.clip((v * 128 - 119) / 9, 0, 1) * np.clip(0.3 + 0.6 * p.noise(f, 5), 0, 1)
    p.tint(f, dry, MUD_DRY, 0.45)


def sole_us(p: Painter, f: Face) -> None:
    full = np.ones((f.h * SS, f.w * SS), np.float32)
    p.paint(f, full, RUBBER)
    # topo da imagem = frente (bico), embaixo = calcanhar
    for y in np.arange(4, 40, 4.2):
        p.shade(f, p.mask(f, lambda d, y=y: d.line([(8, y), (32, y + 2), (56, y)], 1.4)), 1.7)
    p.shade(f, p.mask(f, lambda d: d.rect(4, 42, 60, 45)), 0.6)  # entressola
    for y in np.arange(48, 62, 4):
        p.shade(f, p.mask(f, lambda d, y=y: d.line([(10, y), (54, y)], 1.4)), 1.7)
    p.tint(f, np.clip(p.noise(f, 5) * 0.6 + 0.2, 0, 1), MUD_DRY, 0.5)


def rolled_hem(p: Painter, f: Face, u: np.ndarray, v: np.ndarray) -> None:
    """VC: calça arregaçada à meia canela, pele embaixo e sandália Ho Chi Minh no pé."""
    s = p.spec
    r0, r1 = 86.0, 95.0
    for y in (78, 82):
        p.crease(f, [(-1, y), (20, y + 2), (44, y - 1.4), (65, y + 1)], 1.4, 0.18, 0.07)
    band = p.mask(f, lambda d: d.rect(-1, r0, 65, r1))
    vv = np.clip((v * 128 - r0) / (r1 - r0), 0, 1)
    p.tint(f, band, s.cloth, 0.5)
    p.shade(f, band * np.exp(-(((vv - 0.35) / 0.3) ** 2)), 1.12)
    p.shade(f, p.mask(f, lambda d: d.rect(-1, r0 - 1.4, 65, r0 + 0.4), blur=0.6), 0.7)
    p.crease(f, [(-1, r0 + 4.8), (65, r0 + 4.4)], 1.0, 0.25, 0.0)
    p.shade(f, p.mask(f, lambda d: d.rect(-1, r1 - 1.2, 65, r1)), 0.7)
    # abaixo do rolo: pele (transparente) ...
    p.clear(f, (v >= r1 / 128).astype(np.float32))
    # ... com terra seca na canela e no pé (semitransparente sobre a pele)
    dirt = np.clip((v * 128 - 110) / 18, 0, 1) * np.clip(0.3 + 0.5 * p.noise(f, 6), 0, 1)
    dirt = dirt * (v * 128 >= r1)
    p.paint(f, (dirt > 0.01).astype(np.float32), MUD_WET)  # cor da terra; a força fica no alfa
    p.alpha_set(f, dirt, 0.35)
    # sandália: tiras de câmara de pneu e sola de pneu
    straps: list[list[tuple[float, float]]] = []
    if f.side == "F":
        straps = [[(9, 126), (40, 114)], [(55, 126), (24, 114)]]
    elif f.side in ("outer", "inner"):
        fl = f.front_at_left()
        xf, xb = (6, 58) if fl else (58, 6)
        straps = [[(xf, 125), ((xf + xb) / 2, 115)], [((xf + xb) / 2, 115), (xb, 117.5)]]
    elif f.side == "B":
        straps = [[(8, 117.5), (56, 117.5)]]
    for st in straps:
        m = p.mask(f, lambda d, st=st: d.line(st, 2.4))
        p.paint(f, m, (30, 30, 30))
        p.opaque(f, m)
        hi = [(x, y - 0.7) for x, y in st]
        p.shade(f, p.mask(f, lambda d, hi=hi: d.line(hi, 0.5)) * m, 1.8)
    sole = p.mask(f, lambda d: d.rect(-1, 125.4, 65, 129))
    p.paint(f, sole, RUBBER)
    p.opaque(f, sole)
    # flanco do pneu: tracinhos
    for x in np.arange(1, 64, 3.0):
        p.shade(f, p.mask(f, lambda d, x=x: d.line([(x, 126.2), (x + 1.2, 126.2)], 0.5)), 1.9)


def sole_hcm(p: Painter, f: Face) -> None:
    full = np.ones((f.h * SS, f.w * SS), np.float32)
    p.paint(f, full, RUBBER)
    p.opaque(f, full)
    # banda de rodagem do pneu (blocos)
    for y in np.arange(3, 62, 6):
        for x in (10, 26, 42):
            p.shade(f, p.mask(f, lambda d, x=x, y=y: d.rect(x, y, x + 11, y + 3.4)), 1.8)
    p.tint(f, np.clip(p.noise(f, 5) * 0.5 + 0.2, 0, 1), MUD_DRY, 0.45)


# --------------------------------------------------------------------------------------------
# Montagem
# --------------------------------------------------------------------------------------------
def render(spec: Spec) -> Image.Image:
    p = Painter(spec)
    volume(p)
    if spec.kind == "shirt":
        shirt_torso(p)
        sleeves(p)
        sun(p, 1.0 if spec.style != "ao_ba_ba" else 1.25)
        sweat(
            p, 1.0 if spec.style == "usmc" else 0.8, salt=1.4 if spec.style == "ao_ba_ba" else 1.0
        )
        dirt_k = 0.55 if spec.style == "ao_ba_ba" else 1.0  # poeira aparece demais no preto
        # cotovelo encardido
        for part in ("r", "l"):
            for f in limb_sides(part):
                u, v = p.uv(f)
                m = np.exp(-(((v - ELBOW / 128) / 0.06) ** 2)) * np.clip(
                    0.4 + 0.5 * p.noise(f, 5), 0, 1
                )
                p.tint(f, m, MUD_DRY, 0.15 * dirt_k)
    else:
        pants_torso(p)
        legs(p)
        sun(p, 0.6)
    if spec.patch:
        knee_patch(p)
    return finish(p)


def knee_patch(p: Painter) -> None:
    """Remendo quadrado no joelho direito (VC cáqui e preto): tecido de outro tom, ponto à mão."""
    f = face("r", "F")
    x0, y0, x1, y1 = 14, 52, 46, 76
    poly = [(x0, y0), (x1, y0 + 1), (x1 - 1, y1), (x0 + 1, y1 - 1)]
    m = p.mask(f, lambda d: d.poly(poly))
    p.tint(f, m, tuple(int(c * 0.86) for c in p.spec.faded), 0.45)
    p.raised(f, poly, 1.02, 0.25)
    p.stitch(f, offset_poly(poly + [poly[0]], -1.4), 1.6, 1.2)


def finish(p: Painter) -> Image.Image:
    """Reduz 2× → 1× com alfa pré-multiplicado e preenche o RGB dos pixels transparentes com a
    cor opaca mais próxima (evita franja escura na filtragem do Roblox)."""
    rgb = np.clip(p.rgb, 0, 255)
    a = np.clip(p.a, 0, 1)
    pre = rgb * a[..., None]
    pre = pre.reshape(H, SS, W, SS, 3).mean(axis=(1, 3))
    al = a.reshape(H, SS, W, SS).mean(axis=(1, 3))
    col = np.where(al[..., None] > 1e-4, pre / np.maximum(al[..., None], 1e-4), 0)
    inside = np.zeros((H, W), bool)
    for f in FACES:
        x0, y0, x1, y1 = f.box
        inside[y0:y1, x0:x1] = True
    solid = al > 0.5
    if solid.any():
        idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
        filled = col[idx[0], idx[1]]
        col = np.where(solid[..., None], col, np.where(al[..., None] > 0.02, col, filled))
    al = np.where(inside, al, 0.0)
    out = np.dstack([np.clip(col, 0, 255), al * 255]).round().astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def make(key: str) -> Path:
    img = render(OUTFITS[key])
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{key}.png"
    img.save(path, optimize=True)
    return path


# --------------------------------------------------------------------------------------------
# Folha de conferência (moldes lado a lado e vistas de frente e de costas num boneco de blocos)
# --------------------------------------------------------------------------------------------
def crop(img: Image.Image, box: Box) -> Image.Image:
    return img.crop(box)


def figure(shirt: Image.Image, pants: Image.Image, view: str, faction: str) -> Image.Image:
    """Boneco R15 em blocos visto de frente ou de costas: cor do corpo embaixo, calça e camisa por
    cima (como o Roblox compõe). Cabeça e mãos na cor de pele de referência."""
    hw = 77
    fig = Image.new("RGBA", (256, hw + 256), (0, 0, 0, 0))
    uni_torso = (90, 94, 64) if faction == "usmc" else SKIN_REF
    legs_col = (90, 94, 64) if faction == "usmc" else SKIN_REF

    def block(color, box_xy, size):
        fig.paste(Image.new("RGBA", size, color + (255,)), box_xy)

    fig.paste(Image.new("RGBA", (hw, hw), SKIN_REF + (255,)), (128 - hw // 2, 0))
    if view == "front":
        arms = [("r", R_LIMB["F"], 0), ("l", L_LIMB["F"], 192)]
        legs_ = [(R_LIMB["F"], 64), (L_LIMB["F"], 128)]
        tor = TORSO["front"]
    else:
        arms = [("l", L_LIMB["B"], 0), ("r", R_LIMB["B"], 192)]
        legs_ = [(L_LIMB["B"], 64), (R_LIMB["B"], 128)]
        tor = TORSO["back"]
    block(uni_torso, (64, hw), (128, 128))
    fig.alpha_composite(crop(pants, tor), (64, hw))
    fig.alpha_composite(crop(shirt, tor), (64, hw))
    for _, box, x in arms:
        block(SKIN_REF, (x, hw), (64, 128))
        fig.alpha_composite(crop(shirt, box), (x, hw))
    for box, x in legs_:
        block(legs_col, (x, hw + 128), (64, 128))
        fig.alpha_composite(crop(pants, box), (x, hw + 128))
    return fig


def review(paths: dict[str, Path]) -> Path:
    zoom = 2
    tw, th = W, H
    fw, fh = 256 * zoom, (77 + 256) * zoom
    pad = 16
    row_h = max(th, fh) + 40
    sheet = Image.new("RGB", (pad * 5 + tw * 2 + fw * 2, pad + row_h * len(SETS)), (54, 56, 52))
    d = ImageDraw.Draw(sheet)
    checker = Image.new("RGB", (tw, th), (120, 120, 120))
    cd = ImageDraw.Draw(checker)
    for y in range(0, th, 16):
        for x in range(0, tw, 16):
            if (x // 16 + y // 16) % 2:
                cd.rectangle((x, y, x + 15, y + 15), fill=(150, 150, 150))
    for i, (title, sk, pk, fac) in enumerate(SETS):
        y = pad + i * row_h
        d.text((pad, y), title, fill=(240, 236, 220))
        shirt = Image.open(paths[sk]).convert("RGBA")
        pants = Image.open(paths[pk]).convert("RGBA")
        x = pad
        for tpl, name in ((shirt, sk), (pants, pk)):
            bg = checker.copy().convert("RGBA")
            bg.alpha_composite(tpl)
            sheet.paste(bg.convert("RGB"), (x, y + 18))
            d.text((x, y + 20 + th), f"{name}.png", fill=(200, 200, 190))
            x += tw + pad
        for view in ("front", "back"):
            fig = figure(shirt, pants, view, fac).resize((fw, fh), Image.NEAREST)
            sheet.paste(fig, (x, y + 18), fig)
            d.text(
                (x, y + 20 + fh), "frente" if view == "front" else "costas", fill=(200, 200, 190)
            )
            x += fw + pad
    REVIEW.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(REVIEW, optimize=True)
    return REVIEW


def main(argv: list[str]) -> None:
    paths = {}
    for key in OUTFITS:
        paths[key] = make(key)
        print("ok", paths[key].relative_to(ROOT))
    if "--conferencia" in argv:
        print("ok", review(paths).relative_to(ROOT))


if __name__ == "__main__":
    main(sys.argv[1:])
