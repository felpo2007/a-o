"""Vista aérea ilustrada do mapa real do jogo, para a tela "onde nascer".

Pintor procedural (numpy, Pillow e scipy; sem IA e sem imagem de terceiro). A geografia sai dos
mesmos dados da carta (`tools/make_carta.py`) e o enquadramento é o de `Quadro.px`, então os pinos
do jogo caem no mesmo lugar. Só o terreno: sem texto, grade, legenda, pinos ou tinta de facção.

Saída em assets/carta: aereo_nw/ne/sw/se.png (1024 x 1024, a divisão dos atlas_*) e a prévia
aereo_previa.jpg.

Uso (a partir de vantuong65/):
  uv run --group arte python tools/mapa_aereo.py
  lune run tools/carta_ret.luau frente
  uv run --group arte python tools/mapa_aereo.py --mapa frente   # D-243: aereo_frente_*.png
"""

from __future__ import annotations

import argparse
import io
import math
import os
import time
from dataclasses import dataclass

for _var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[_var] = "3"

import numpy as np  # noqa: E402
from make_carta import (  # noqa: E402
    DADOS,
    LADO,
    SAIDA,
    Dados,
    N,
    Quadro,
    _ret,
    carrega,
    exporta_dados,
)
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402
from scipy import ndimage  # noqa: E402

SEMENTE = 1965
F4 = np.float32
MEIO = N // 2  # resolução das máscaras suaves e do chão
P = 1024  # resolução das contas de plantio
LIMITE_PNG = 1_500_000  # bytes por bloco

# luz de fim de manhã, vinda do noroeste (x para a direita, y para baixo, z para cima)
_sol = np.array([-0.60, -0.50, 0.62], F4)
SX, SY, SZ = (_sol / np.linalg.norm(_sol)).tolist()
SOMBRA_X, SOMBRA_Y = 0.66, 0.54  # px de sombra por px de altura
COR_SOMBRA = (7, 22, 22)

Cor = tuple[int, int, int]

# rampas das copas: sombra, meio, luz, brilho
TINTAS: list[list[Cor]] = [
    [(12, 34, 28), (30, 72, 42), (70, 112, 52), (132, 156, 82)],
    [(10, 32, 32), (24, 66, 48), (52, 102, 60), (108, 146, 84)],
    [(16, 38, 22), (42, 82, 36), (90, 122, 48), (150, 166, 82)],
    [(14, 36, 24), (36, 76, 38), (80, 112, 48), (140, 148, 76)],
    [(9, 28, 25), (20, 58, 38), (42, 90, 48), (88, 128, 66)],
    [(18, 40, 24), (52, 92, 40), (108, 136, 54), (170, 178, 92)],
]
TINTA_COCO: list[list[Cor]] = [
    [(20, 50, 28), (58, 108, 44), (120, 160, 62), (198, 206, 112)],
    [(24, 52, 24), (72, 114, 42), (140, 168, 62), (216, 212, 118)],
    [(18, 48, 32), (48, 102, 52), (102, 152, 72), (178, 200, 112)],
]
TINTA_BANANA: list[list[Cor]] = [
    [(24, 62, 24), (66, 130, 40), (130, 186, 60), (210, 228, 120)],
    [(22, 58, 28), (56, 122, 46), (112, 176, 70), (190, 222, 124)],
]
TINTA_BAMBU: list[list[Cor]] = [
    [(26, 58, 24), (78, 124, 44), (146, 176, 66), (214, 220, 122)],
    [(22, 54, 26), (66, 116, 48), (128, 168, 70), (198, 214, 120)],
]
TINTA_ARBUSTO: list[list[Cor]] = [
    [(20, 48, 24), (54, 100, 38), (106, 146, 52), (168, 188, 82)],
    [(24, 50, 22), (70, 106, 36), (128, 150, 52), (186, 190, 88)],
]

# rampas dos telhados e materiais: sombra, meio, luz, brilho
MATERIAIS: dict[str, list[Cor]] = {
    "palha": [(74, 54, 34), (140, 110, 70), (186, 156, 104), (216, 196, 148)],
    "palha2": [(66, 52, 36), (122, 100, 68), (166, 142, 100), (200, 180, 136)],
    "palha3": [(80, 60, 34), (152, 118, 68), (196, 162, 100), (224, 200, 142)],
    "telha": [(70, 38, 30), (132, 70, 50), (172, 98, 68), (204, 140, 104)],
    "telha2": [(60, 36, 30), (112, 62, 48), (148, 86, 62), (184, 124, 92)],
    "zinco": [(62, 62, 60), (118, 116, 108), (164, 160, 146), (208, 204, 186)],
    "zinco2": [(70, 54, 44), (128, 100, 80), (162, 134, 108), (196, 172, 146)],
    "lona": [(38, 44, 26), (76, 84, 44), (106, 114, 62), (142, 148, 88)],
    "lona2": [(44, 46, 28), (88, 90, 52), (120, 122, 72), (156, 156, 100)],
    "conex": [(44, 50, 40), (84, 94, 70), (116, 126, 94), (150, 158, 124)],
    "saco": [(72, 60, 40), (134, 114, 80), (170, 150, 108), (198, 180, 136)],
    "madeira": [(50, 34, 22), (104, 74, 46), (146, 110, 70), (180, 144, 98)],
    "tabua": [(66, 46, 28), (134, 98, 60), (178, 140, 90), (210, 176, 124)],
    "pedra": [(70, 70, 64), (128, 126, 114), (168, 164, 148), (206, 202, 186)],
    "terra": [(92, 72, 46), (150, 122, 82), (182, 154, 108), (208, 184, 140)],
    "pano": [(92, 84, 68), (164, 152, 122), (204, 194, 162), (232, 224, 196)],
}

# kind/key -> (material, forma, altura em m)
TIPOS: dict[str, tuple[str, str, float]] = {
    "hut_thatch": ("palha", "quatro", 3.6),
    "hut_kitchen": ("palha2", "quatro", 2.8),
    "hut_veranda": ("palha3", "quatro", 3.6),
    "vila_casa_04": ("palha", "quatro", 3.6),
    "vila_casa_06": ("palha3", "quatro", 3.6),
    "vila_casa_08": ("palha2", "quatro", 3.6),
    "house_tile": ("telha", "quatro", 4.0),
    "chua": ("telha", "pagode", 6.5),
    "dinh": ("telha2", "pagode", 5.5),
    "granary": ("palha2", "redondo", 3.0),
    "serraria": ("zinco", "duas", 4.8),
    "caldeira": ("zinco2", "duas", 3.8),
    "moenda": ("madeira", "redondo", 2.0),
    "straw_stack": ("palha3", "redondo", 2.0),
    "banca": ("pano", "duas", 2.0),
    "toras": ("madeira", "toras", 1.2),
    "tabuas": ("tabua", "tabuas", 0.8),
    "well": ("pedra", "poco", 0.6),
    "rice_sack": ("saco", "plano", 0.4),
    "vc_lean_to": ("palha2", "duas", 2.0),
    "vc_car_shelter": ("palha2", "duas", 2.6),
    "vc_hoang_cam_kitchen": ("palha", "duas", 2.2),
    "vc_weapon_rack": ("madeira", "plano", 0.6),
    "bamboo_clothesline": ("tabua", "plano", 0.3),
    "us_tent_gp_large": ("lona", "duas", 3.6),
    "us_tent_gp_medium": ("lona2", "duas", 3.2),
    "us_mess_tent": ("lona2", "duas", 3.6),
    "us_command_tent": ("lona", "duas", 3.8),
    "us_conex": ("conex", "plano", 2.4),
    "us_generator": ("conex", "plano", 1.4),
    "us_water_trailer": ("conex", "plano", 1.6),
    "us_fuel_drums": ("pedra", "plano", 1.0),
    "us_bunker": ("saco", "quatro", 1.8),
    "sandbag_wall": ("saco", "plano", 1.0),
    "us_watchtower": ("madeira", "quatro", 6.0),
    "us_gate": ("madeira", "plano", 1.4),
    "us_motor_pool": ("zinco", "duas", 3.4),
    "us_helipad": ("terra", "pad", 0.0),
    "us_armor_revetment": ("terra", "berma", 1.4),
    "us_range_berm": ("terra", "quatro", 1.6),
    # D-232: expansão da Vila e do Arrozal
    "exp_palafita_a": ("zinco2", "duas", 5.0),
    "exp_palafita_b": ("palha", "duas", 5.0),
    "exp_casas_ligadas": ("telha", "duas", 3.6),
    "exp_casa_vala": ("palha2", "duas", 3.4),
    "exp_carroca": ("telha", "duas", 2.6),
    "exp_abrigo": ("terra", "quatro", 1.2),
    "exp_trincheira": ("terra", "plano", 0.2),
    "exp_prancha": ("tabua", "plano", 0.2),
    "exp_celeiro": ("zinco", "duas", 5.0),
    "exp_galpao": ("zinco2", "duas", 3.2),
    "exp_deposito": ("palha2", "quatro", 4.0),
    "exp_casa_verde": ("telha2", "duas", 4.0),
    "exp_ruina": ("madeira", "plano", 1.5),
    "exp_comporta": ("pedra", "duas", 3.4),
    "exp_telheiro": ("zinco2", "duas", 2.6),
    "exp_patio": ("terra", "plano", 0.1),
    "exp_passarela": ("tabua", "plano", 0.4),
    "exp_muro": ("pedra", "plano", 0.5),
    # D-234: sobrados grandes
    "exp_sobrado_a": ("telha", "duas", 8.6),
    "exp_sobrado_b": ("telha2", "quatro", 8.9),
    "exp_sobrado_c": ("telha", "duas", 8.8),
    "exp_sobrado_d": ("telha2", "quatro", 9.0),
}
SEM_DESENHO = {"us_flagpole", "us_range_bench", "vc_punji", "vc_range_rest", "vc_hammock"}


@dataclass
class Obra:
    x: float
    z: float
    yaw: float
    w: float
    d: float
    kind: str
    material: str
    forma: str
    alt: float  # m


@dataclass
class Campos:
    mata: np.ndarray
    bosque: np.ndarray
    lavoura: np.ndarray
    clareira: np.ndarray
    roca: np.ndarray
    cipo: np.ndarray
    baixada: np.ndarray


def suave(v, a: float, b: float):
    t = np.clip((v - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def cor(c) -> np.ndarray:
    return np.array(c, F4)


def mistura(a, b, t):
    if isinstance(t, np.ndarray) and t.ndim == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def rampa(tom: np.ndarray, pontos: list[Cor]) -> np.ndarray:
    xs = np.linspace(0, 1, len(pontos))
    t = np.clip(tom, 0, 1)
    return np.stack([np.interp(t, xs, [p[i] for p in pontos]) for i in range(3)], -1).astype(F4)


def ruido(rng: np.random.Generator, forma: tuple[int, int], celula: float) -> np.ndarray:
    h, w = forma
    mh, mw = max(3, int(h / celula) + 3), max(3, int(w / celula) + 3)
    base = rng.random((mh, mw), dtype=F4)
    im = Image.fromarray(base).resize((w, h), Image.Resampling.BICUBIC, box=(1, 1, mw - 2, mh - 2))
    return np.asarray(im, F4) - 0.5


def fbm(
    rng: np.random.Generator,
    forma: tuple[int, int],
    celula: float,
    oitavas: int = 4,
    ganho: float = 0.55,
) -> np.ndarray:
    s = np.zeros(forma, F4)
    a = 1.0
    for _ in range(oitavas):
        s += a * ruido(rng, forma, celula)
        a *= ganho
        celula = max(celula / 2, 2.0)
    return (s - s.mean()) / (s.std() + 1e-6)


def reduz(m: np.ndarray, p: int) -> np.ndarray:
    return np.asarray(
        Image.fromarray(m.astype(F4)).resize((p, p), Image.Resampling.BOX),
        F4,
    )


def amplia(m: np.ndarray, n: int) -> np.ndarray:
    return np.asarray(
        Image.fromarray(m.astype(F4)).resize((n, n), Image.Resampling.BILINEAR),
        F4,
    )


# ---------- paisagem ----------
def campos(q: Quadro, d: Dados, rng: np.random.Generator) -> Campos:
    """máscaras de paisagem com a borda orgânica: a grade do jogo tem 4,5 m e o terreiro central
    é um losango; a borda anda até ~14 m para não aparecer a figura da grade"""
    n = MEIO
    t = (np.arange(n, dtype=np.float64) + 0.5) / n
    r, c = q.celula(q.x0 + t * (q.x1 - q.x0), q.z0 + t * (q.z1 - q.z0))
    rr, cc = np.meshgrid(r.astype(F4), c.astype(F4), indexing="ij")
    wr = fbm(rng, (n, n), 190, 4) * 1.7 + fbm(rng, (n, n), 36, 3) * 0.55
    wc = fbm(rng, (n, n), 190, 4) * 1.7 + fbm(rng, (n, n), 36, 3) * 0.55
    rr += wr
    cc += wc
    borda = fbm(rng, (n, n), 54, 4)
    L = d.info["landscape"]

    def classe(k: int, sigma: float) -> np.ndarray:
        g = ndimage.gaussian_filter((d.paisagem == k).astype(F4), sigma)
        return ndimage.map_coordinates(g, [rr, cc], order=1, mode="nearest").astype(F4)

    mata = classe(L["forest"], 2.0) + classe(L["stream"], 1.0) * 0.8
    bosque = classe(L["grove"], 1.2)
    lavoura = classe(L["farm"], 0.7)
    clareira = classe(L["clear"], 3.0)
    roca = classe(L["roca"], 1.5)
    mata = np.clip(mata + borda * 0.17, 0, None)
    clareira = np.clip(clareira - borda * 0.16, 0, None)
    soma = mata + bosque + lavoura + clareira + roca + 1e-6
    cipo = ndimage.map_coordinates(
        ndimage.gaussian_filter(d.cipo, 1.0), [rr, cc], order=1, mode="nearest"
    ).astype(F4)
    baixada = ndimage.map_coordinates(
        ndimage.gaussian_filter(d.baixada, 1.0), [rr, cc], order=1, mode="nearest"
    ).astype(F4)
    return Campos(
        mata=mata / soma,
        bosque=bosque / soma,
        lavoura=lavoura / soma,
        clareira=clareira / soma,
        roca=roca / soma,
        cipo=cipo,
        baixada=baixada,
    )


def talhoes_secos(
    xx: np.ndarray, yy: np.ndarray, px_m: float, f: np.ndarray, grao: np.ndarray
) -> np.ndarray:
    """roça: colcha de lotes com fileiras, cada um numa cultura"""
    ang = 0.2
    ca, sa = math.cos(ang), math.sin(ang)
    u = (xx * ca + yy * sa) / px_m + f * 2.0
    v = (-xx * sa + yy * ca) / px_m + f * 1.5
    lu, lv = 30.0, 17.0
    iu = np.floor(u / lu)
    v2 = v + (iu % 2) * 6.7
    iv = np.floor(v2 / lv)
    h = (iu.astype(np.int32) * 73 + iv.astype(np.int32) * 179 + 100_003) % 97
    paleta = cor(
        [
            (150, 118, 76),
            (178, 156, 92),
            (124, 150, 64),
            (112, 134, 62),
            (92, 130, 54),
            (190, 172, 96),
            (140, 142, 70),
            (166, 128, 82),
        ]
    )
    base = paleta[h % len(paleta)]
    eixo = np.where(h % 2 == 0, u, v2)
    linhas = np.sin(2 * np.pi * eixo / 1.9)
    base = base * (1 + (linhas * 0.075 + grao * 0.045))[..., None]
    fu, fv = u / lu - iu, v2 / lv - iv
    dist = np.minimum(np.minimum(fu, 1 - fu) * lu, np.minimum(fv, 1 - fv) * lv)
    return mistura(base, cor((120, 106, 70)), np.exp(-((dist / 0.55) ** 2)) * 0.75)


def chao(q: Quadro, c: Campos, rng: np.random.Generator) -> np.ndarray:
    """cor do chão em MEIO x MEIO px"""
    n = MEIO
    px_m = n / ((q.x1 - q.x0) * q.m)
    yy, xx = np.mgrid[0:n, 0:n].astype(F4)
    f1 = fbm(rng, (n, n), 240, 5)
    f2 = fbm(rng, (n, n), 56, 4)
    f3 = fbm(rng, (n, n), 12, 3)
    grao = ndimage.gaussian_filter(rng.standard_normal((n, n)).astype(F4), 0.6)
    grao /= grao.std()

    capim = mistura(cor((112, 142, 60)), cor((150, 164, 78)), suave(f1, -1.2, 1.2))
    capim = mistura(capim, cor((84, 124, 52)), suave(f2, 0.1, 1.5) * 0.65)
    capim = mistura(capim, cor((170, 142, 94)), suave(f2 + f3 * 0.45, 1.05, 1.8) * 0.8)
    touceira = suave(f3 + grao * 0.35, 0.75, 1.5)
    capim = mistura(capim, cor((72, 104, 46)), touceira * 0.5)
    capim = capim * (1 + (f3 * 0.05 + grao * 0.05))[..., None]

    mata = mistura(cor((18, 42, 28)), cor((30, 58, 34)), suave(f2, -1, 1))
    bosque = mistura(cor((54, 88, 42)), cor((88, 112, 54)), suave(f2 + f3 * 0.4, -1, 1))
    bosque = bosque * (1 + grao[..., None] * 0.05)
    lavoura = mistura(cor((98, 134, 58)), cor((132, 154, 70)), suave(f2, -1, 1))
    lavoura = lavoura * (1 + (f3 * 0.04 + grao * 0.05))[..., None]
    roca = talhoes_secos(xx, yy, px_m, f1, grao)

    g = (
        c.mata[..., None] * mata
        + c.bosque[..., None] * bosque
        + c.lavoura[..., None] * lavoura
        + c.clareira[..., None] * capim
        + c.roca[..., None] * roca
    )
    return g.astype(F4)


# ---------- caminhos ----------
def catmull(pts: list, passos: int = 6) -> np.ndarray:
    a = np.asarray(pts, np.float64)
    if len(a) < 3:
        return a
    p = np.vstack([2 * a[0] - a[1], a, 2 * a[-1] - a[-2]])
    saida = []
    ts = np.linspace(0, 1, passos, endpoint=False)[:, None]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        saida.append(
            0.5
            * (
                2 * p1
                + (p2 - p0) * ts
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * ts**2
                + (3 * p1 - p0 - 3 * p2 + p3) * ts**3
            )
        )
    saida.append(a[-1:])
    return np.vstack(saida)


def paralela(pts: np.ndarray, off: float) -> list[tuple[float, float]]:
    if len(pts) < 2:
        return [tuple(p) for p in pts]
    t = np.gradient(pts, axis=0)
    n = np.hypot(t[:, 0], t[:, 1])
    n[n == 0] = 1
    return list(
        zip(
            (pts[:, 0] - t[:, 1] / n * off).tolist(),
            (pts[:, 1] + t[:, 0] / n * off).tolist(),
            strict=True,
        )
    )


def linha(dr: ImageDraw.ImageDraw, pts, largura: float, valor: int = 255) -> None:
    lista = [tuple(p) for p in pts]
    w = max(1, int(round(largura)))
    dr.line(lista, fill=valor, width=w, joint="curve")
    r = w / 2
    for x, y in (lista[0], lista[-1]):
        dr.ellipse([x - r, y - r, x + r, y + r], fill=valor)


def mascaras_estrada(q: Quadro, d: Dados) -> dict[str, np.ndarray]:
    k = q.px_m(1.0)
    camadas = {nome: Image.new("L", (N, N), 0) for nome in ("borda", "leito", "sulco", "miolo")}
    dr = {nome: ImageDraw.Draw(im) for nome, im in camadas.items()}
    for a, b in d.info.get("lanes", []):
        pts = np.array([q.px(*a), q.px(*b)])
        linha(dr["borda"], pts, 2.2 * k, 120)
        linha(dr["leito"], pts, 1.2 * k, 170)
    ordem = {"trilha": 0, "secundaria": 1, "rua": 2, "principal": 3}
    for r in sorted(d.info.get("roads", []), key=lambda e: ordem[e["kind"]]):
        pts = catmull([q.px(x, z) for x, z in r["pts"]])
        w = r["w"] * k
        linha(dr["borda"], pts, w * 1.42, 255)
        linha(dr["leito"], pts, w * (0.72 if r["kind"] == "trilha" else 0.92), 255)
        if r["kind"] != "trilha":
            for lado in (-1, 1):
                dr["sulco"].line(
                    paralela(pts, lado * w * 0.22),
                    fill=235,
                    width=max(2, int(w * 0.11)),
                    joint="curve",
                )
        if r["kind"] == "secundaria":
            dr["miolo"].line([tuple(p) for p in pts], fill=255, width=max(2, int(w * 0.13)))
    return {
        "borda": np.asarray(camadas["borda"].filter(ImageFilter.GaussianBlur(7)), F4) / 255,
        "leito": np.asarray(camadas["leito"].filter(ImageFilter.GaussianBlur(2.4)), F4) / 255,
        "sulco": np.asarray(camadas["sulco"].filter(ImageFilter.GaussianBlur(1.5)), F4) / 255,
        "miolo": np.asarray(camadas["miolo"].filter(ImageFilter.GaussianBlur(2.5)), F4) / 255,
    }


def pinta_estradas(tela: np.ndarray, m: dict[str, np.ndarray], rng: np.random.Generator) -> None:
    f = amplia(fbm(rng, (MEIO, MEIO), 26, 4), N)
    g = amplia(fbm(rng, (MEIO, MEIO), 7, 2), N)
    tela[:] = mistura(tela, cor((116, 96, 56)), m["borda"] * 0.78)
    terra = mistura(cor((214, 174, 118)), cor((184, 136, 88)), suave(f, -0.7, 1.1))
    terra = terra * (1 + g * 0.045)[..., None]
    tela[:] = mistura(tela, terra, m["leito"])
    tela[:] = mistura(tela, cor((142, 104, 68)), m["sulco"] * m["leito"] * 0.58)
    tela[:] = mistura(tela, cor((142, 148, 78)), m["miolo"] * m["leito"] * 0.42)
    poca = suave(f + g * 0.3, 1.75, 2.1) * m["leito"]
    tela[:] = mistura(tela, cor((110, 92, 66)), poca * 0.55)


# ---------- água ----------
def mascaras_agua(q: Quadro, d: Dados) -> tuple[np.ndarray, np.ndarray]:
    """o rio com o mesmo corte da carta (make_carta.riachos) e os riachos sem a escada da grade"""
    L = d.info["landscape"]
    m = d.paisagem == L["stream"]
    largo = ndimage.binary_opening(m, structure=np.ones((2, 2), bool))
    fundo = ndimage.gaussian_filter(largo.astype(F4), 1.0)
    rio = q.amostra(fundo, N, ordem=3) > 0.45
    rio = ndimage.gaussian_filter(rio.astype(F4), 5.0) > 0.5
    fino = m & ~ndimage.binary_dilation(largo)
    im = Image.new("L", (N, N), 0)
    dr = ImageDraw.Draw(im)
    ys, xs = np.nonzero(fino)
    pts = set(zip(ys.tolist(), xs.tolist(), strict=True))
    for r, c in pts:
        p = q.de_celula(r, c)
        for dr_, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
            if (r + dr_, c + dc) in pts:
                if dr_ and dc and ((r + dr_, c) in pts or (r, c + dc) in pts):
                    continue
                dr.line([p, q.de_celula(r + dr_, c + dc)], fill=255, width=22)
    # D-232: a vala e o canal da expansão
    for a in d.info.get("aguasExp", []):
        dr.line([q.px(x, z) for x, z in a["pts"]], fill=255, width=22, joint="curve")
    riacho = np.asarray(im.filter(ImageFilter.GaussianBlur(12)), F4) / 255 > 0.42
    return rio, riacho & ~rio


def _caixa(m: np.ndarray, margem: int) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(m)
    return (
        max(0, int(ys.min()) - margem),
        min(N, int(ys.max()) + margem + 1),
        max(0, int(xs.min()) - margem),
        min(N, int(xs.max()) + margem + 1),
    )


def pinta_rio(
    tela: np.ndarray,
    rio: np.ndarray,
    leito_estrada: np.ndarray,
    rng: np.random.Generator,
) -> None:
    if not rio.any():
        return
    y0, y1, x0, x1 = _caixa(rio, 70)
    sub = tela[y0:y1, x0:x1]
    dentro = rio[y0:y1, x0:x1]
    forma = dentro.shape
    din = ndimage.distance_transform_edt(dentro).astype(F4)
    dfo = ndimage.distance_transform_edt(~dentro).astype(F4)
    f1 = fbm(rng, forma, 150, 4)
    f2 = fbm(rng, forma, 26, 3)
    fino = ndimage.gaussian_filter(rng.standard_normal(forma).astype(F4), 0.8)
    fino /= fino.std()

    # margem: lama molhada junto da água, areia, e o capim voltando
    alcance = 34 + f2 * 8
    margem = np.clip(1 - dfo / alcance, 0, 1) ** 1.25
    areia = mistura(cor((192, 168, 116)), cor((150, 124, 82)), suave(f2 + fino * 0.2, -0.8, 0.9))
    sub[:] = mistura(sub, areia, margem * (~dentro))
    lama = np.exp(-((dfo / 7.0) ** 2)) * (~dentro)
    sub[:] = mistura(sub, cor((96, 80, 54)), lama * 0.75)

    prof = suave(din + f2 * 2.5, 0, 36)
    agua = rampa(prof, [(142, 170, 124), (86, 142, 116), (46, 110, 102), (30, 86, 86)])
    corrente = np.sin(din * 0.24 + f2 * 3.0 + f1 * 2.0)
    agua = agua * (1 + corrente * (0.035 + 0.035 * prof))[..., None]
    ceu = suave(f1 + f2 * 0.3, 0.5, 1.8) * 0.3
    agua = mistura(agua, cor((172, 212, 204)), ceu)
    espuma = np.exp(-(((din - 3.5) / 2.4) ** 2)) * suave(f2 + fino * 0.5, -0.3, 1.0)
    agua = mistura(agua, cor((206, 220, 196)), espuma * 0.55)
    brilho = np.clip(fino - 2.55, 0, 0.6) / 0.6 * suave(din, 6, 16)
    agua = mistura(agua, cor((240, 248, 238)), brilho * 0.85)

    # a margem do noroeste faz sombra na água
    desl = ndimage.shift(dentro.astype(F4), (9, 11), order=0, mode="nearest")
    sombra = ndimage.gaussian_filter(np.clip(dentro.astype(F4) - desl, 0, 1), 3.0)
    agua = agua * (1 - sombra * 0.48)[..., None]

    vau = leito_estrada[y0:y1, x0:x1] * 0.46
    alfa = ndimage.gaussian_filter(dentro.astype(F4), 1.2) * (1 - vau)
    sub[:] = mistura(sub, agua, alfa)


def pinta_riacho(tela: np.ndarray, riacho: np.ndarray, rng: np.random.Generator) -> None:
    if not riacho.any():
        return
    y0, y1, x0, x1 = _caixa(riacho, 40)
    sub = tela[y0:y1, x0:x1]
    dentro = riacho[y0:y1, x0:x1]
    forma = dentro.shape
    din = ndimage.distance_transform_edt(dentro).astype(F4)
    dfo = ndimage.distance_transform_edt(~dentro).astype(F4)
    f = fbm(rng, forma, 22, 3)
    margem = np.clip(1 - dfo / (15 + f * 3), 0, 1) * (~dentro)
    sub[:] = mistura(sub, cor((112, 98, 62)), margem * 0.8)
    prof = suave(din, 0, 9)
    agua = rampa(prof + f * 0.08, [(130, 164, 124), (70, 128, 112), (38, 98, 96)])
    agua = mistura(agua, cor((186, 216, 204)), suave(f, 1.0, 1.9) * 0.4)
    alfa = ndimage.gaussian_filter(dentro.astype(F4), 1.0)
    sub[:] = mistura(sub, agua, alfa)


# ---------- arrozais ----------
def quadro_local(q: Quadro, x: float, z: float, yaw: float, w: float, dd: float, margem: int = 3):
    """caixa em px e as coordenadas locais (studs) de cada pixel dela"""
    cx, cy = q.px(x, z)
    ca, sa = math.cos(yaw), math.sin(yaw)
    raio = math.hypot(w, dd) / 2 * q.k + margem
    x0, y0 = max(0, int(cx - raio)), max(0, int(cy - raio))
    x1, y1 = min(N, int(cx + raio) + 1), min(N, int(cy + raio) + 1)
    if x1 <= x0 or y1 <= y0:
        return None
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(F4)
    dx, dz = (xx + 0.5 - cx) / q.k, (yy + 0.5 - cy) / q.k
    return (x0, y0, x1, y1), dx * ca - dz * sa, dx * sa + dz * ca


def pinta_arrozais(tela: np.ndarray, q: Quadro, d: Dados, rng: np.random.Generator) -> None:
    """cada lâmina d'água do jogo vira um talhão com canteiros, fileiras de arroz e céu refletido"""
    verdes = [
        ((104, 150, 58), 0.94),
        ((126, 164, 66), 0.92),
        ((86, 136, 60), 0.9),
        ((150, 170, 76), 0.86),
        ((112, 154, 66), 0.9),
        ((94, 146, 76), 0.62),
        ((116, 156, 86), 0.42),
    ]
    pesos = np.array([0.24, 0.22, 0.2, 0.1, 0.12, 0.08, 0.04])
    for x, z, u, v, a in d.info["waters"]:
        loc = quadro_local(q, x, z, a, u, v)
        if loc is None:
            continue
        (x0, y0, x1, y1), lu, lv = loc
        forma = lu.shape
        nu, nv = max(1, round(u / 46)), max(1, round(v / 46))
        cu = np.linspace(-u / 2, u / 2, nu + 1)
        cv = np.linspace(-v / 2, v / 2, nv + 1)
        if nu > 1:
            cu[1:-1] += rng.uniform(-3, 3, nu - 1)
        if nv > 1:
            cv[1:-1] += rng.uniform(-3, 3, nv - 1)
        iu = np.clip(np.searchsorted(cu, lu) - 1, 0, nu - 1)
        iv = np.clip(np.searchsorted(cv, lv) - 1, 0, nv - 1)
        escolha = rng.choice(len(verdes), (nu, nv), p=pesos)
        tons = cor([verdes[i][0] for i in escolha.ravel()]).reshape(nu, nv, 3)
        dens = np.array([verdes[i][1] for i in escolha.ravel()], F4).reshape(nu, nv)
        sentido = rng.integers(0, 2, (nu, nv))
        planta = tons[iu, iv]
        densidade = dens[iu, iv]
        eixo = np.where(sentido[iu, iv] == 0, lu, lv)
        fileira = 0.5 + 0.5 * np.cos(2 * np.pi * eixo / 3.5)
        n1 = fbm(rng, forma, 42, 3)
        n2 = ndimage.gaussian_filter(rng.standard_normal(forma).astype(F4), 0.8)
        n2 /= n2.std()
        ceu = mistura(cor((92, 142, 132)), cor((184, 214, 206)), suave(n1, -0.6, 1.6))
        cobertura = np.clip(densidade * (0.62 + 0.5 * fileira) + n1 * 0.07, 0, 1)
        talhao = mistura(ceu, planta * (0.88 + 0.18 * fileira)[..., None], cobertura)
        talhao = talhao * (1 + n2 * 0.05)[..., None]
        brilho = np.clip(n2 - 2.3, 0, 0.7) / 0.7 * (1 - cobertura)
        talhao = mistura(talhao, cor((240, 248, 240)), brilho)

        du = np.minimum(np.abs(lu - cu[iu]), np.abs(cu[iu + 1] - lu))
        dv = np.minimum(np.abs(lv - cv[iv]), np.abs(cv[iv + 1] - lv))
        interno = np.minimum(
            np.where((iu == 0) & (lu < 0), 99, du) if nu > 1 else 99,
            np.where((iv == 0) & (lv < 0), 99, dv) if nv > 1 else 99,
        )
        talhao = mistura(talhao, cor((150, 132, 88)), suave(-interno, -1.1, -0.45) * 0.85)
        borda = np.minimum(u / 2 - np.abs(lu), v / 2 - np.abs(lv))
        alfa = np.clip(borda * q.k + 0.5, 0, 1)
        sub = tela[y0:y1, x0:x1]
        sub[:] = mistura(sub, talhao, alfa)


def pinta_diques(tela: np.ndarray, q: Quadro, d: Dados) -> None:
    im = Image.new("L", (N, N), 0)
    dr = ImageDraw.Draw(im)
    largura = max(4, round(q.px_m(1.15)))
    for x1, z1, x2, z2 in d.info["dikes"]:
        linha(dr, [q.px(x1, z1), q.px(x2, z2)], largura)
    for x, z, u, v, a in d.info["waters"]:
        p = _ret(q, x, z, a, u, v)
        linha(dr, [*p, p[0]], largura)
    m = np.asarray(im.filter(ImageFilter.GaussianBlur(1.5)), F4) / 255
    y0, y1, x0, x1 = _caixa(m > 0.02, 8)
    sub = tela[y0:y1, x0:x1]
    mm = m[y0:y1, x0:x1]
    gy, gx = np.gradient(ndimage.gaussian_filter(mm, 1.0))
    luz = np.clip(0.5 + (gx * -SX + gy * -SY) * 3.0, 0, 1)
    terra = rampa(luz, [(96, 78, 50), (160, 136, 92), (214, 192, 140)])
    sub[:] = mistura(sub, terra, mm)


# ---------- construções ----------
def lista_obras(q: Quadro, d: Dados) -> list[Obra]:
    obras: list[Obra] = []
    largura, fundo = 7 / q.m * 1.3, 4.5 / q.m * 1.3
    rng = np.random.default_rng([SEMENTE, 7])
    palhas = ("palha", "palha2", "palha3")
    for x, z, a in d.info["houses"]:
        m = palhas[int(rng.integers(0, 3))]
        obras.append(Obra(x, z, a, largura, fundo, "casa", m, "quatro", 3.4))
    v = d.info.get("village") or {"houses": [], "specials": []}
    for x, z, yaw, w, dd in v["houses"]:
        m = palhas[int(rng.integers(0, 3))]
        obras.append(Obra(x, z, yaw, w * 1.08, dd * 1.08, "casa", m, "quatro", 3.8))
    for s in v["specials"]:
        k = s["kind"]
        if k in ("ponte", "cais", "barco"):
            obras.append(Obra(s["x"], s["z"], s["yaw"], s["w"], s["d"], k, "tabua", k, 1.2))
        elif k in TIPOS:
            m, f, h = TIPOS[k]
            obras.append(Obra(s["x"], s["z"], s["yaw"], s["w"], s["d"], k, m, f, h))
    for b in d.info.get("bases", []):
        k = b["key"]
        if k in SEM_DESENHO:
            continue
        if k == "us_concertina":
            obras.append(Obra(b["x"], b["z"], b["yaw"], b["w"], 3.0, k, "pedra", "arame", 0.5))
        elif k in TIPOS:
            m, f, h = TIPOS[k]
            obras.append(Obra(b["x"], b["z"], b["yaw"], b["w"], b["d"], k, m, f, h))
    return obras


def cabeceiras(q: Quadro, o: Obra) -> list[tuple[float, float]]:
    """as duas pontas da ponte, em px"""
    ca, sa = math.cos(o.yaw), math.sin(o.yaw)
    return [q.px(o.x + s * o.w / 2 * ca, o.z - s * o.w / 2 * sa) for s in (-1, 1)]


def pinta_terreiros(
    tela: np.ndarray, q: Quadro, obras: list[Obra], rng: np.random.Generator
) -> None:
    """chão batido em volta de cada construção"""
    im = Image.new("L", (MEIO, MEIO), 0)
    dr = ImageDraw.Draw(im)
    for o in obras:
        if o.forma == "ponte":
            r = q.px_m(5.5) / 2
            for px, py in cabeceiras(q, o):
                dr.ellipse([px / 2 - r, py / 2 - r, px / 2 + r, py / 2 + r], fill=255)
        if o.forma in ("ponte", "cais", "barco", "arame"):
            continue
        cx, cy = q.px(o.x, o.z)
        cx, cy = cx / 2, cy / 2
        pequeno = o.w < 18 and o.d < 18
        folga = (3 if pequeno else 7) / q.m * q.k / 2
        rx = o.w * q.k / 4 + folga
        ry = o.d * q.k / 4 + folga
        r = max(rx, ry) if o.forma == "redondo" else (rx + ry) / 2
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    m = np.asarray(im.filter(ImageFilter.GaussianBlur(10)), F4) / 255
    f = fbm(rng, (MEIO, MEIO), 22, 4)
    m = suave(m + f * 0.17, 0.32, 0.72)
    terra = mistura(cor((176, 146, 98)), cor((146, 118, 74)), suave(f, -0.9, 1.1))
    g = mistura(np.zeros_like(terra), terra, m)
    ampliado = np.stack(
        [amplia(g[..., i], N) for i in range(3)],
        -1,
    )
    alfa = amplia(m, N) * 0.62
    tela[:] = (
        tela * (1 - alfa[..., None])
        + ampliado / np.maximum(amplia(m, N), 0.02)[..., None] * alfa[..., None]
    )


def pinta_sombras_obras(im: Image.Image, q: Quadro, obras: list[Obra]) -> None:
    s = Image.new("L", (N, N), 0)
    dr = ImageDraw.Draw(s)
    for o in obras:
        if o.alt <= 0 or o.forma == "arame":
            continue
        pts = _ret(q, o.x, o.z, o.yaw, o.w, o.d)
        h = q.px_m(o.alt)
        for t in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0):
            dr.polygon([(x + h * t * SOMBRA_X, y + h * t * SOMBRA_Y) for x, y in pts], fill=178)
    im.paste(COR_SOMBRA, (0, 0), s.filter(ImageFilter.GaussianBlur(2.2)))


def pinta_obra(im: Image.Image, q: Quadro, o: Obra, rng: np.random.Generator) -> None:
    w, dd = max(o.w, 3.0), max(o.d, 2.0)
    loc = quadro_local(q, o.x, o.z, o.yaw, w, dd)
    if loc is None:
        return
    (x0, y0, x1, y1), lu, lv = loc
    k = q.k
    eu, ev = w / 2 - np.abs(lu), dd / 2 - np.abs(lv)
    dentro = np.minimum(eu, ev)
    forma = o.forma
    grao = ndimage.gaussian_filter(rng.standard_normal(lu.shape).astype(F4), 0.7)
    grao /= grao.std() + 1e-6
    tom_extra = np.zeros_like(lu)

    if forma in ("redondo", "poco"):
        r = min(w, dd) / 2
        dentro = r - np.hypot(lu, lv)
        h = np.clip(dentro, 0, None) * 0.8
    elif forma == "quatro":
        # quatro águas com cumeeira: a casa quase quadrada não vira pirâmide
        if abs(w - dd) < 0.16 * max(w, dd):
            ao_longo_u = int(abs(o.x) * 7 + abs(o.z) * 3) % 2 == 0
        else:
            ao_longo_u = w >= dd
        h = np.minimum(ev, eu * 1.8) if ao_longo_u else np.minimum(eu, ev * 1.8)
        h = np.clip(h, 0, None) * 0.74
        cume = np.abs(lv) if ao_longo_u else np.abs(lu)
        ponta = eu if ao_longo_u else ev
        meia = (dd if ao_longo_u else w) / 2
        tom_extra += 0.12 * np.exp(-((cume * k / 1.6) ** 2)) * (ponta > meia / 1.8)
    elif forma == "duas":
        h = np.clip(ev if w >= dd else eu, 0, None) * 0.8
    elif forma == "pagode":
        passo = min(w, dd) * 0.26
        h = np.where(dentro > passo, (dentro - passo) * 0.8 + passo * 0.62, dentro * 0.62)
        h = np.clip(h, 0, None)
        tom_extra -= 0.16 * np.exp(-(((dentro - passo) * k / 2.0) ** 2))
    elif forma == "barco":
        dentro = (1 - (lu / (w / 2)) ** 2 - (lv / (dd / 2)) ** 2) * min(w, dd) / 2
        h = np.clip(dentro, 0, None) * 0.5
        tom_extra -= 0.34 * suave(dentro, dd * 0.14, dd * 0.24)
    elif forma == "berma":
        # baia de blindado: talude em U, aberto para um lado, com o chão à vista no meio
        esp = min(w, dd) * 0.2
        parede = (dentro < esp) & ~((lv > 0) & (eu > esp))
        h = np.where(parede, np.clip(np.minimum(dentro, esp - dentro), 0, None) * 0.9, 0.0)
        dentro = np.where(parede, np.minimum(dentro, (esp - dentro) + 0.6), -1.0)
    else:
        h = np.zeros_like(lu)

    gy, gx = np.gradient(ndimage.gaussian_filter(h * k, 0.7))
    nrm = np.sqrt(gx * gx + gy * gy + 1)
    lamb = (-gx * SX - gy * SY + SZ) / nrm
    tom = 0.52 + 0.62 * (lamb - SZ) + tom_extra

    mat = o.material
    if mat.startswith("palha"):
        cursos = np.sin(np.clip(dentro, 0, None) * k * 0.58 + grao * 0.5)
        fibra = np.sin((lu + lv) * k * 1.7 + grao * 2.2)
        tom = tom + cursos * 0.06 + fibra * 0.025 + grao * 0.045
    elif mat.startswith("telha"):
        carreira = np.sin(np.clip(dentro, 0, None) * k * 0.72)
        tom = tom + np.sign(carreira) * 0.035 + grao * 0.03
    elif mat.startswith("zinco"):
        vinco = np.where(ev < eu, lu, lv)
        tom = tom + np.sin(vinco * k * 1.25) * 0.055 + grao * 0.018
        placa = (np.floor(lu / 9) + np.floor(lv / 7)) % 3 == 0
        tom = tom + placa * 0.035
    elif mat.startswith("lona"):
        tom = tom + np.sin(lu * k * 0.34) * 0.025 + grao * 0.03
    elif forma == "tabuas" or forma == "cais" or forma == "ponte":
        tom = tom + np.sin(lu * k * 1.45) * 0.09 + grao * 0.07
    elif forma == "toras":
        tom = 0.5 + 0.34 * np.cos(lv * k * 0.62) + grao * 0.05
    elif forma == "pad":
        tom = 0.56 + grao * 0.04
        tom = tom - 0.14 * np.exp(-((dentro * k / 3.2) ** 2))
        anel = np.hypot(lu, lv) - min(w, dd) * 0.32
        tom = tom + 0.17 * np.exp(-((anel * k / 2.6) ** 2))
    elif forma == "arame":
        laco = np.sin(lu * k * 0.85)
        tom = 0.58 + laco * 0.3
        dentro = np.where(np.abs(laco) > 0.25, dentro, -1.0)
    else:
        tom = tom + grao * 0.05

    if forma == "ponte":
        tom = tom - 0.3 * np.exp(-((ev * k / 3.0) ** 2))
    if forma == "cais":
        tom = tom - 0.22 * np.exp(-((dentro * k / 2.0) ** 2))
    if forma == "poco":
        tom = tom - 0.42 * suave(dentro, 0.45, 1.05)

    rgb = rampa(tom, MATERIAIS[mat])
    if forma not in ("pad", "arame"):
        rgb = rgb * (0.68 + 0.32 * np.clip(dentro * k / 2.4, 0, 1))[..., None]
    alfa = np.clip(dentro * k + 0.5, 0, 1)
    if forma == "pad":
        alfa = alfa * 0.85
    if forma == "arame":
        alfa = alfa * 0.55
    fundo = np.asarray(im.crop((x0, y0, x1, y1)), F4)
    saida = mistura(fundo, rgb, alfa)
    im.paste(Image.fromarray(np.clip(saida + 0.5, 0, 255).astype(np.uint8)), (x0, y0))


def pinta_trincheira(im: Image.Image, q: Quadro, d: Dados) -> None:
    pts = catmull([q.px(x, z) for x, z in d.info.get("trench", [])], 4)
    if len(pts) < 2:
        return
    k = q.px_m(1.0)
    for valor, larg in (((150, 124, 84), 2.3), ((40, 34, 26), 1.05)):
        m = Image.new("L", (N, N), 0)
        linha(ImageDraw.Draw(m), pts, larg * k)
        im.paste(valor, (0, 0), m.filter(ImageFilter.GaussianBlur(1.2)))


def pinta_cemiterio(im: Image.Image, q: Quadro, d: Dados, rng: np.random.Generator) -> None:
    c = d.info.get("cemetery")
    if not c:
        return
    cx, cy = q.px(c["x"], c["z"])
    k = q.px_m(1.0)
    sombra = Image.new("L", im.size, 0)
    ds = ImageDraw.Draw(sombra)
    claro = ImageDraw.Draw(im)
    tumulos = []
    for lin in range(-2, 3):
        for col in range(-2, 3):
            if rng.random() < 0.28:
                continue
            x = cx + (col * 3.1 + rng.uniform(-0.5, 0.5)) * k
            y = cy + (lin * 3.4 + rng.uniform(-0.5, 0.5)) * k
            r = rng.uniform(0.75, 1.05) * k
            tumulos.append((x, y, r))
            ds.ellipse([x - r + 3, y - r + 3, x + r + 5, y + r + 5], fill=150)
    im.paste(COR_SOMBRA, (0, 0), sombra.filter(ImageFilter.GaussianBlur(1.6)))
    for x, y, r in tumulos:
        claro.ellipse([x - r, y - r, x + r, y + r], fill=(178, 158, 116))
        claro.ellipse([x - r * 0.6, y - r * 0.65, x + r * 0.2, y + r * 0.15], fill=(214, 198, 158))


# ---------- plantas ----------
def molde_copa(rng: np.random.Generator, d: int) -> tuple[np.ndarray, np.ndarray]:
    """copa redonda em lóbulos: altura -> normal -> tom"""
    s = d + 8
    c = (s - 1) / 2
    yy, xx = np.mgrid[0:s, 0:s].astype(F4)
    r = d / 2
    h = np.zeros((s, s), F4)
    for _ in range(int(14 + r * 0.7)):
        ang = rng.uniform(0, math.tau)
        rr = r * 0.8 * math.sqrt(rng.random())
        cx, cy = c + rr * math.cos(ang), c + rr * math.sin(ang)
        rl = r * rng.uniform(0.18, 0.36)
        q2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / rl**2
        topo = (1 - (rr / r) ** 2) * r * 0.42
        h = np.maximum(h, np.where(q2 < 1, np.sqrt(np.clip(1 - q2, 0, 1)) * rl + topo, 0))
    alfa = ndimage.gaussian_filter((h > 0).astype(F4), 0.7)
    folha = ndimage.gaussian_filter(rng.standard_normal((s, s)).astype(F4), 0.75)
    folha /= folha.std()
    hh = ndimage.gaussian_filter(h, 0.8) + folha * 0.42
    gy, gx = np.gradient(hh)
    nrm = np.sqrt(gx * gx + gy * gy + 1)
    lamb = (-gx * SX - gy * SY + SZ) / nrm
    prega = hh - ndimage.gaussian_filter(hh, max(1.0, r * 0.24))
    lado = ((xx - c) * SX + (yy - c) * SY) / (r * 0.8)
    tom = 0.45 + 0.46 * (lamb - SZ) + prega / r * 0.9 + lado * 0.13 + folha * 0.05
    return np.clip(tom, 0, 1).astype(F4), np.clip(alfa, 0, 1).astype(F4)


def molde_folhas(
    rng: np.random.Generator,
    d: int,
    n_folhas: int,
    largura: float,
    folhinha: bool,
) -> tuple[np.ndarray, np.ndarray]:
    """coqueiro, bananeira ou bambu vistos de cima: folhas saindo do centro"""
    esc = 3
    s = (d + 8) * esc
    c = s / 2
    r = d / 2 * esc
    tom = Image.new("L", (s, s), 0)
    alf = Image.new("L", (s, s), 0)
    dt, da = ImageDraw.Draw(tom), ImageDraw.Draw(alf)
    ang_sol = math.atan2(SY, SX)
    base = rng.uniform(0, math.tau)
    ordem = list(range(n_folhas))
    rng.shuffle(ordem)
    for i in ordem:
        a = base + i / n_folhas * math.tau + rng.uniform(-0.2, 0.2)
        comp = r * rng.uniform(0.76, 1.0)
        curva = rng.uniform(-0.42, 0.42)
        luz = 0.53 + 0.2 * math.cos(a - ang_sol) + rng.uniform(-0.07, 0.07)
        espinha = []
        for t in np.linspace(0, 1, 16):
            ar = a + curva * t * t
            espinha.append((c + comp * t * math.cos(ar), c + comp * t * math.sin(ar), ar, t))
        if folhinha:
            for px, py, ar, t in espinha[1:]:
                meia = comp * largura * math.sin(math.pi * min(t * 1.05, 1.0)) ** 0.7
                for lado in (-1, 1):
                    al = ar + lado * (1.05 - 0.42 * t)
                    fim = (px + meia * math.cos(al), py + meia * math.sin(al))
                    v = luz + (0.08 if lado * math.sin(ar - ang_sol) < 0 else -0.09)
                    v += float(rng.uniform(-0.05, 0.05))
                    da.line([(px, py), fim], fill=255, width=esc + 1)
                    dt.line([(px, py), fim], fill=int(np.clip(v, 0, 1) * 255), width=esc + 1)
        else:
            esq, dir_ = [], []
            for px, py, ar, t in espinha:
                meia = comp * largura * math.sin(math.pi * min(t * 0.98 + 0.03, 1.0)) ** 0.8
                esq.append((px - meia * math.sin(ar), py + meia * math.cos(ar)))
                dir_.append((px + meia * math.sin(ar), py - meia * math.cos(ar)))
            da.polygon(esq + dir_[::-1], fill=255)
            meio = [(p[0], p[1]) for p in espinha]
            dt.polygon(esq + meio[::-1], fill=int(np.clip(luz + 0.1, 0, 1) * 255))
            dt.polygon(dir_ + meio[::-1], fill=int(np.clip(luz - 0.1, 0, 1) * 255))
        dt.line(
            [(p[0], p[1]) for p in espinha],
            fill=int(np.clip(luz + 0.28, 0, 1) * 255),
            width=max(1, esc // 2),
        )
    miolo = r * 0.09
    da.ellipse([c - miolo, c - miolo, c + miolo, c + miolo], fill=255)
    dt.ellipse([c - miolo, c - miolo, c + miolo, c + miolo], fill=52)
    a8 = np.asarray(alf, F4) / 255
    t8 = np.asarray(tom, F4) / 255
    t_pre = Image.fromarray(t8 * a8).resize((d + 8, d + 8), Image.Resampling.BOX)
    a_red = Image.fromarray(a8).resize((d + 8, d + 8), Image.Resampling.BOX)
    aa = np.asarray(a_red, F4)
    return np.clip(np.asarray(t_pre, F4) / np.maximum(aa, 0.02), 0, 1), np.clip(aa, 0, 1)


ESPECIES = ("copa", "sub", "coco", "banana", "bambu", "arbusto")
COPA, SUB, COCO, BANANA, BAMBU, ARBUSTO = range(6)
TAMANHOS = np.array([12, 16, 22, 28, 36, 44, 54, 64, 76, 90, 106, 124])
FORMAS = 6


class Viveiro:
    """moldes (tom + alfa) e carimbos prontos (cor + alfa + sombra)"""

    def __init__(self) -> None:
        self.moldes: dict[tuple[int, int, int], tuple[np.ndarray, np.ndarray]] = {}
        self.carimbos: dict[tuple[int, int, int, int], tuple] = {}

    def molde(self, esp: int, d: int, forma: int) -> tuple[np.ndarray, np.ndarray]:
        ch = (esp, d, forma)
        if ch not in self.moldes:
            rng = np.random.default_rng([SEMENTE, 11, esp, d, forma])
            if esp in (COPA, SUB, ARBUSTO):
                self.moldes[ch] = molde_copa(rng, d)
            elif esp == COCO:
                self.moldes[ch] = molde_folhas(rng, d, int(rng.integers(11, 16)), 0.2, True)
            elif esp == BANANA:
                self.moldes[ch] = molde_folhas(rng, d, int(rng.integers(6, 9)), 0.12, False)
            else:
                self.moldes[ch] = molde_folhas(rng, d, int(rng.integers(24, 34)), 0.07, True)
        return self.moldes[ch]

    def carimbo(self, esp: int, d: int, forma: int, tinta: int) -> tuple:
        ch = (esp, d, forma, tinta)
        if ch not in self.carimbos:
            tom, alfa = self.molde(esp, d, forma)
            if esp == COCO:
                r = TINTA_COCO[tinta % len(TINTA_COCO)]
            elif esp == BANANA:
                r = TINTA_BANANA[tinta % len(TINTA_BANANA)]
            elif esp == BAMBU:
                r = TINTA_BAMBU[tinta % len(TINTA_BAMBU)]
            elif esp == ARBUSTO:
                r = TINTA_ARBUSTO[tinta % len(TINTA_ARBUSTO)]
            else:
                r = TINTAS[tinta % len(TINTAS)]
            t = tom * 0.8 if esp == SUB else tom
            rgb = Image.fromarray(np.clip(rampa(t, r) + 0.5, 0, 255).astype(np.uint8))
            mask = Image.fromarray((alfa * 255 + 0.5).astype(np.uint8))
            sigma = max(0.8, d * 0.035)
            forca = 0.62 if esp in (COCO, BANANA, BAMBU) else 0.58
            somb = ndimage.gaussian_filter(alfa, sigma) * forca
            sombra = Image.fromarray((somb * 255 + 0.5).astype(np.uint8))
            self.carimbos[ch] = (rgb, mask, sombra, rgb.width)
        return self.carimbos[ch]


def semeia(
    rng: np.random.Generator, prob: np.ndarray, passo_m: float, px_m: float
) -> tuple[np.ndarray, np.ndarray]:
    passo = passo_m * px_m
    n = int(N / passo) + 1
    gy, gx = np.mgrid[0:n, 0:n].astype(F4)
    x = ((gx + 0.5 + rng.uniform(-0.48, 0.48, gx.shape).astype(F4)) * passo).ravel()
    y = ((gy + 0.5 + rng.uniform(-0.48, 0.48, gy.shape).astype(F4)) * passo).ravel()
    dentro = (x >= 0) & (x < N) & (y >= 0) & (y < N)
    x, y = x[dentro], y[dentro]
    ix = np.clip((x * P / N).astype(np.int32), 0, P - 1)
    iy = np.clip((y * P / N).astype(np.int32), 0, P - 1)
    vivo = rng.random(x.shape, dtype=F4) < prob[iy, ix]
    return x[vivo], y[vivo]


@dataclass
class Plantas:
    x: list
    y: list
    d: list  # diâmetro (px)
    esp: list
    tinta: list
    alt: list  # distância da sombra (px)
    ordem: list

    def poe(self, x, y, d, esp, tinta, alt, ordem) -> None:
        n = len(x)
        if n == 0:
            return
        self.x.append(np.asarray(x, F4))
        self.y.append(np.asarray(y, F4))
        self.d.append(np.broadcast_to(np.asarray(d, F4), (n,)).copy())
        self.esp.append(np.full(n, esp, np.int16) if np.isscalar(esp) else esp.astype(np.int16))
        self.tinta.append(np.broadcast_to(np.asarray(tinta, np.int16), (n,)).copy())
        self.alt.append(np.broadcast_to(np.asarray(alt, F4), (n,)).copy())
        self.ordem.append(np.broadcast_to(np.asarray(ordem, F4), (n,)).copy())


def plantio(
    q: Quadro,
    d: Dados,
    c: Campos,
    obstaculo: np.ndarray,
    rio: np.ndarray,
    obras: list[Obra],
    rng: np.random.Generator,
) -> Plantas:
    px_m = q.px_m(1.0)
    mata = suave(reduz(c.mata, P), 0.42, 0.64)
    bosque = suave(reduz(c.bosque, P), 0.34, 0.62)
    clareira = suave(reduz(c.clareira, P), 0.38, 0.68)
    roca = suave(reduz(c.roca, P), 0.4, 0.7)
    lavoura = suave(reduz(c.lavoura, P), 0.4, 0.7)
    cipo = reduz(c.cipo, P)
    baixada = reduz(c.baixada, P)
    m_por_p = (q.x1 - q.x0) * q.m / P
    folga = ndimage.distance_transform_edt(obstaculo < 0.5).astype(F4) * m_por_p
    perto_rio = ndimage.distance_transform_edt(reduz(rio, P) < 0.5).astype(F4) * m_por_p
    # a orla: a mata não acaba numa linha, sobra árvore solta para fora dela
    orla = ndimage.gaussian_filter(mata, 13.0 / m_por_p)
    orla = suave(orla, 0.06, 0.34) * (1 - mata)

    casas = Image.new("L", (P, P), 0)
    dc = ImageDraw.Draw(casas)
    for o in obras:
        if o.forma in ("quatro", "redondo", "pagode"):
            x, y = q.px(o.x, o.z)
            x, y = x * P / N, y * P / N
            dc.ellipse([x - 2, y - 2, x + 2, y + 2], fill=255)
    perto_casa = ndimage.distance_transform_edt(np.asarray(casas) == 0).astype(F4) * m_por_p

    aglomera = fbm(rng, (P, P), 46, 4)
    especie_campo = fbm(rng, (P, P), 58, 3)
    pl = Plantas([], [], [], [], [], [], [])

    def idx(x, y):
        return (
            np.clip((y * P / N).astype(np.int32), 0, P - 1),
            np.clip((x * P / N).astype(np.int32), 0, P - 1),
        )

    def tintas_copa(x, y):
        iy, ix = idx(x, y)
        v = (especie_campo[iy, ix] * 0.5 + 0.5) * 1.6 + rng.normal(0, 0.42, x.shape)
        t = np.clip(((v + 0.45) * 2.0).astype(np.int32), 0, 5)
        escuro = cipo[iy, ix] > 0.58
        t = np.where(escuro & (rng.random(x.shape) < 0.55), 4, t)
        t = np.where((baixada[iy, ix] > 0.7) & (rng.random(x.shape) < 0.45), 1, t)
        return t

    def semear(prob, passo, dmin, dmax, invade=0.42):
        """pontos com diâmetro; a copa só invade estrada, rio e casa até `invade` do diâmetro"""
        x, y = semeia(rng, prob, passo, px_m)
        dm = rng.uniform(dmin, dmax, x.shape).astype(F4)
        ok = folga[idx(x, y)] > dm * (0.5 - invade) + 0.5
        return x[ok], y[ok], dm[ok] * px_m

    def ordem(a, b, x):
        return rng.uniform(a, b, x.shape)

    def coqueiros(prob, passo, dmin=8.2, dmax=12.0):
        x, y, dm = semear(prob, passo, dmin, dmax, 0.22)
        pl.poe(x, y, dm, COCO, rng.integers(0, 3, x.shape), dm * 0.74, ordem(6, 8, x))

    # 1. fundo da mata: copas baixas e escuras, cobrem o chão
    x, y, dm = semear(mata, 3.3, 3.8, 6.0, 0.3)
    pl.poe(x, y, dm, SUB, tintas_copa(x, y), dm * 0.2, ordem(0, 1, x))

    # 2. dossel
    x, y, dm = semear(mata * 0.97, 5.1, 5.4, 9.0, 0.2)
    pl.poe(x, y, dm, COPA, tintas_copa(x, y), dm * 0.34, ordem(2, 4, x))

    # 3. árvores que furam o dossel
    x, y, dm = semear(mata * 0.6, 15.0, 9.0, 13.5, 0.16)
    t = np.where(rng.random(x.shape) < 0.5, 2, 5)
    pl.poe(x, y, dm, COPA, t, dm * 0.46, ordem(5, 6, x))

    # 4. coqueiros e bambu dentro da mata, mais na beirada
    beirada = np.clip(1 - ndimage.gaussian_filter(mata, 22.0 / m_por_p), 0, 1)
    coqueiros(mata * (0.045 + 0.62 * suave(beirada, 0.05, 0.36)), 12.0, 6.8, 10.0)
    prob = mata * suave(baixada, 0.58, 0.82) * 0.72
    x, y, dm = semear(prob, 8.0, 5.0, 7.6, 0.3)
    pl.poe(x, y, dm, BAMBU, rng.integers(0, 2, x.shape), dm * 0.5, ordem(4, 5, x))

    # 5. orla: fruteiras, moitas e coqueiros soltos para fora da mata
    x, y, dm = semear(orla * 0.5, 7.0, 4.6, 8.0, 0.3)
    pl.poe(x, y, dm, COPA, tintas_copa(x, y), dm * 0.34, ordem(2, 4, x))
    coqueiros(orla * 0.62, 10.0)
    x, y, dm = semear(orla * 0.7, 4.6, 1.8, 3.4, 0.4)
    pl.poe(x, y, dm, ARBUSTO, rng.integers(0, 2, x.shape), dm * 0.32, ordem(0, 1, x))

    # 6. bosque de vila: coqueiro, bananeira e fruteira
    coqueiros(bosque * 0.9, 7.6)
    x, y, dm = semear(bosque * 0.72, 6.2, 3.6, 5.6, 0.4)
    pl.poe(x, y, dm, BANANA, rng.integers(0, 2, x.shape), dm * 0.42, ordem(1, 2, x))
    x, y, dm = semear(bosque * 0.48, 9.0, 5.0, 8.0, 0.3)
    pl.poe(x, y, dm, COPA, tintas_copa(x, y), dm * 0.34, ordem(2, 4, x))

    # 7. clareira: moitas, fruteiras e coqueiros em grupos, mais perto das casas
    grupo = suave(aglomera, 0.05, 1.1)
    casa_f = np.exp(-perto_casa / 13.0)
    coqueiros(clareira * (0.12 + 0.74 * grupo + 0.32 * casa_f), 10.0)
    x, y, dm = semear(clareira * (0.05 + 0.5 * grupo), 10.5, 4.8, 8.2, 0.3)
    pl.poe(x, y, dm, COPA, tintas_copa(x, y), dm * 0.34, ordem(2, 4, x))
    x, y, dm = semear(clareira * (0.08 + 0.46 * grupo + 0.42 * casa_f), 5.0, 2.0, 3.8, 0.42)
    t = rng.integers(0, 2, x.shape)
    esp = np.where(rng.random(x.shape) < 0.3 + 0.35 * casa_f[idx(x, y)], BANANA, ARBUSTO)
    pl.poe(x, y, dm, esp, t, dm * 0.34, ordem(0, 1, x))

    # 8. roça e lavoura: moitas e um coqueiro ou outro
    aberto = np.maximum(roca, lavoura)
    x, y, dm = semear(aberto * (0.02 + 0.2 * suave(aglomera, 0.6, 1.6)), 7.5, 2.0, 3.8, 0.42)
    pl.poe(x, y, dm, ARBUSTO, rng.integers(0, 2, x.shape), dm * 0.34, ordem(0, 1, x))
    coqueiros(aberto * 0.14 * suave(aglomera, 0.2, 1.3), 17.0)

    # 9. beira do rio: coqueiros e bambu acompanhando a água
    beira = suave(perto_rio, 3.0, 5.0) * (1 - suave(perto_rio, 9.0, 15.0))
    x, y, dm = semear(beira * 0.56, 7.4, 7.0, 10.4, 0.3)
    esp = np.where(rng.random(x.shape) < 0.66, COCO, BAMBU)
    pl.poe(x, y, dm, esp, rng.integers(0, 2, x.shape), dm * 0.66, ordem(6, 8, x))

    # 10. sebes reais do jogo: bambu alto e moita baixa nos diques
    xs, ys, ds, es, al = [], [], [], [], []
    for x1, z1, x2, z2, h in d.info["hedges"]:
        a, b = np.array(q.px(x1, z1)), np.array(q.px(x2, z2))
        comp = float(np.hypot(*(b - a)))
        alta = h > 3.0
        passo = (2.7 if alta else 2.5) * px_m
        n = max(1, int(comp / passo))
        for i in range(n + 1):
            if not alta and rng.random() < 0.34:
                continue
            p = a + (b - a) * (i / n) + rng.normal(0, 0.28 * px_m, 2)
            xs.append(p[0])
            ys.append(p[1])
            if alta:
                dd = float(rng.uniform(3.8, 5.6)) * px_m
                ds.append(dd)
                es.append(BAMBU)
                al.append(dd * 0.56)
            else:
                dd = float(rng.uniform(1.5, 2.4)) * px_m
                ds.append(dd)
                es.append(ARBUSTO)
                al.append(dd * 0.28)
    if xs:
        vx, vy = np.array(xs, F4), np.array(ys, F4)
        seco = perto_rio[idx(vx, vy)] > 1.5  # sebe do jogo que cruza o rio não nasce na água
        pl.poe(
            vx[seco],
            vy[seco],
            np.array(ds, F4)[seco],
            np.array(es)[seco],
            rng.integers(0, 2, vx.shape)[seco],
            np.array(al, F4)[seco],
            rng.uniform(1, 2, vx.shape)[seco],
        )
    return pl


def planta_tudo(im: Image.Image, pl: Plantas, rng: np.random.Generator) -> int:
    x = np.concatenate(pl.x)
    y = np.concatenate(pl.y)
    diam = np.concatenate(pl.d)
    esp = np.concatenate(pl.esp)
    tinta = np.concatenate(pl.tinta)
    alt = np.concatenate(pl.alt)
    ordem = np.concatenate(pl.ordem)
    idx_d = np.clip(np.searchsorted(TAMANHOS, diam), 0, len(TAMANHOS) - 1)
    formas = rng.integers(0, FORMAS, x.shape)
    viv = Viveiro()
    for i in np.argsort(ordem, kind="stable").tolist():
        d = int(TAMANHOS[idx_d[i]])
        rgb, mask, sombra, lado = viv.carimbo(int(esp[i]), d, int(formas[i]), int(tinta[i]))
        px0, py0 = int(x[i]) - lado // 2, int(y[i]) - lado // 2
        sx, sy = px0 + int(alt[i] * SOMBRA_X), py0 + int(alt[i] * SOMBRA_Y)
        im.paste(COR_SOMBRA, (sx, sy, sx + lado, sy + lado), sombra)
        im.paste(rgb, (px0, py0), mask)
    return len(x)


# ---------- acabamento ----------
def relevo(q: Quadro, d: Dados) -> np.ndarray:
    z = ndimage.gaussian_filter(d.alturas, 3.2) * 3.4
    passo = d.cell * q.m
    gy, gx = np.gradient(z, passo)
    nrm = np.sqrt(gx * gx + gy * gy + 1)
    s = (-gx * SX - gy * SY + SZ) / nrm
    largo = ndimage.gaussian_filter(d.alturas, 11.0)
    cota = (largo - largo.mean()) / (largo.std() + 1e-6)
    f = 1.0 + 0.62 * (s - SZ) + np.clip(cota, -1.6, 1.6) * 0.035
    return np.clip(q.amostra(f.astype(F4), LADO, ordem=3), 0.74, 1.16)


def acabamento(img: Image.Image, q: Quadro, d: Dados) -> np.ndarray:
    a = np.asarray(img, F4) / 255
    a = a * relevo(q, d)[..., None]
    lum = (a * [0.3, 0.59, 0.11]).sum(-1, keepdims=True)
    a = lum + (a - lum) * 1.02
    a = np.clip(a, 0, 1)
    a = a * a * (3 - 2 * a) * 0.42 + a * 0.58
    lum = (a * [0.3, 0.59, 0.11]).sum(-1, keepdims=True)
    quente = np.array([1.05, 1.0, 0.9], F4)
    frio = np.array([0.93, 1.0, 1.05], F4)
    t = np.clip(lum / 0.5, 0, 1)
    a = a * (frio * (1 - t) + quente * t)
    borrado = ndimage.gaussian_filter(a, (1.1, 1.1, 0))
    a = a + (a - borrado) * 0.42
    return np.clip(a * 255, 0, 255).astype(np.uint8)


def png_bytes(arr: np.ndarray) -> bytes:
    b = io.BytesIO()
    Image.fromarray(arr, "RGB").save(b, "PNG", optimize=True, compress_level=9)
    return b.getvalue()


def reduz_png(arr: np.ndarray) -> tuple[bytes, int]:
    """reduz bits só o necessário para o bloco caber no limite"""
    dados = png_bytes(arr)
    if len(dados) <= LIMITE_PNG:
        return dados, 1
    # medido nos blocos: reduzir em RGB perde menos (40,7 dB a 1,46 MB) que YCbCr ou paleta
    for passo in (2, 3, 4, 5, 6, 7, 8, 9, 10):
        q = np.clip(np.round(arr.astype(F4) / passo) * passo, 0, 255).astype(np.uint8)
        dados = png_bytes(q)
        if len(dados) <= LIMITE_PNG:
            return dados, passo
    return dados, 10


def fora_da_area(arr: np.ndarray, q: Quadro, d: Dados) -> np.ndarray:
    """D-243: escurece o que fica fora da faixa jogável, com a borda da área bem marcada"""
    a = d.info["area"]
    k = LADO / (q.x1 - q.x0)
    y0, y1 = (a["minZ"] - q.z0) * k, (a["maxZ"] - q.z0) * k
    linhas = np.arange(LADO, dtype=F4) + 0.5
    dentro = suave(linhas, y0 - 1.5, y0 + 1.5) * (1 - suave(linhas, y1 - 1.5, y1 + 1.5))
    m = dentro[:, None, None]
    v = arr.astype(F4)
    cinza = (v * [0.3, 0.59, 0.11]).sum(-1, keepdims=True)
    apagado = (cinza * 0.6 + v * 0.4) * 0.34
    saida = v * m + apagado * (1 - m)
    for yb in (y0, y1):
        i0 = int(round(yb)) - 1
        saida[max(i0, 0) : i0 + 2] = (216, 196, 142)
    return np.clip(saida, 0, 255).astype(np.uint8)


def salva(arr: np.ndarray, prefixo: str = "aereo") -> None:
    meio = LADO // 2
    SAIDA.mkdir(parents=True, exist_ok=True)
    for nome, lin, col in (("nw", 0, 0), ("ne", 0, 1), ("sw", 1, 0), ("se", 1, 1)):
        bloco = arr[lin * meio : (lin + 1) * meio, col * meio : (col + 1) * meio]
        dados, passo = reduz_png(bloco)
        (SAIDA / f"{prefixo}_{nome}.png").write_bytes(dados)
        print(f"{prefixo}_{nome}.png: {len(dados) / 1e6:.2f} MB (passo de cor {passo})")
    Image.fromarray(arr, "RGB").resize((1600, 1600), Image.Resampling.LANCZOS).save(
        SAIDA / f"{prefixo}_previa.jpg", quality=90, subsampling=0
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mapa", choices=("frente", "comboio"), default=None)
    mapa = ap.parse_args().mapa
    t0 = time.perf_counter()
    if mapa:
        d = carrega(SAIDA / f"dados_{mapa}")
    elif not (DADOS / "dados.json").exists():
        exporta_dados()
        d = carrega()
    else:
        d = carrega()
    q = Quadro(d)

    def filho(i: int) -> np.random.Generator:
        return np.random.default_rng([SEMENTE, i])

    c = campos(q, d, filho(1))
    g = chao(q, c, filho(2))
    tela = np.stack([amplia(g[..., i], N) for i in range(3)], -1)
    del g
    print(f"chão: {time.perf_counter() - t0:.1f} s")

    obras = lista_obras(q, d)
    pinta_terreiros(tela, q, obras, filho(3))
    me = mascaras_estrada(q, d)
    pinta_estradas(tela, me, filho(4))
    pinta_arrozais(tela, q, d, filho(5))
    pinta_diques(tela, q, d)
    rio, riacho = mascaras_agua(q, d)
    pinta_rio(tela, rio, me["leito"], filho(6))
    pinta_riacho(tela, riacho, filho(7))
    print(f"chão pintado: {time.perf_counter() - t0:.1f} s")

    # onde não nasce árvore
    bloqueio = Image.new("L", (N, N), 0)
    db = ImageDraw.Draw(bloqueio)
    for x, z, u, v, a in d.info["waters"]:
        db.polygon(_ret(q, x, z, a, u, v), fill=255)
    for o in obras:
        if o.forma != "arame":
            db.polygon(_ret(q, o.x, o.z, o.yaw, o.w, o.d), fill=255)
        if o.forma == "ponte":
            r = q.px_m(4.5)
            for px, py in cabeceiras(q, o):
                db.ellipse([px - r, py - r, px + r, py + r], fill=255)
    obst = np.maximum(np.asarray(bloqueio, F4) / 255, me["leito"])
    obst = np.maximum(obst, np.maximum(rio, riacho).astype(F4))
    obst_p = reduz(obst, P)
    del obst, bloqueio

    im = Image.fromarray(np.clip(tela + 0.5, 0, 255).astype(np.uint8), "RGB")
    del tela
    pl = plantio(q, d, c, obst_p, rio, obras, filho(8))
    n = planta_tudo(im, pl, filho(9))
    print(f"plantas: {n} em {time.perf_counter() - t0:.1f} s")

    pinta_trincheira(im, q, d)
    pinta_cemiterio(im, q, d, filho(10))
    pinta_sombras_obras(im, q, obras)
    r = filho(11)
    for o in sorted(obras, key=lambda e: e.alt):
        pinta_obra(im, q, o, r)
    print(f"obras: {len(obras)} em {time.perf_counter() - t0:.1f} s")

    final = im.resize((LADO, LADO), Image.Resampling.LANCZOS)
    arr = acabamento(final, q, d)
    if mapa:
        salva(fora_da_area(arr, q, d), f"aereo_{mapa}")
    else:
        salva(arr)
    print(f"total: {time.perf_counter() - t0:.1f} s")


if __name__ == "__main__":
    main()
