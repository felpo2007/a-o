"""Carta topográfica do mapa tático, no estilo das cartas do AMS (série L7014, 1:50.000, 1965).

Desenha a área jogável (2 x 2 km, D-63) a partir dos dados do próprio jogo, exportados pelo Lune
(tools/carta_dados.luau, que usa WorldData, Landscape, Vegetation e o filtro do FeatureBuilder):
  - sombreado de relevo e curvas de nível com cota;
  - mata (com as manchas de cipó), bosque de vila, baixada com bambu e tràm, clareiras;
  - arrozal da vila com as lâminas d'água e o traçado dos diques que existem no place;
  - casas, sebes de bambu, riacho, trincheira sul de An Cường (2) e cemitério;
  - trilhas entre as vilas (traçado de DESIGN: caminho de menor custo pelo terreno, sem marca no
    chão do jogo) e a nota da Rota 523, que passa ao sul, fora da área;
  - grade militar de 1 km (quadrado BS) com os números, marcas de 100 m nas bordas, nomes das
    vilas e colinas, cotas, rosa dos ventos e escala gráfica.
Saída: assets/carta/carta_2048.png (prévia inteira) e 4 blocos de 1024 px (limite de imagem do
Roblox): carta_0_0.png (NO), carta_0_1.png (NE), carta_1_0.png (SO), carta_1_1.png (SE).

Uso (a partir de vantuong65/):
  uv run python tools/make_carta.py            # roda o Lune se faltar assets/carta/dados
  uv run python tools/make_carta.py --dados    # força a exportação pelo Lune antes
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage
from skimage.graph import MCP_Geometric
from skimage.measure import find_contours

ROOT = Path(__file__).resolve().parent.parent
DADOS = ROOT / "assets/carta/dados"
SAIDA = ROOT / "assets/carta"

LADO = 2048  # px da carta inteira (2 x 2 blocos de 1024)
SS = 2  # superamostragem: desenha em 4096 e reduz (traço e texto suaves)
N = LADO * SS

# ---------- cores (tinta de carta impressa em papel envelhecido) ----------
PAPEL = (236, 229, 206)
MATA = (196, 214, 166)
MATA_DENSA = (178, 201, 148)
BOSQUE = (166, 194, 140)
LAVOURA = (240, 235, 214)
CLAREIRA = (233, 224, 192)
AGUA = (176, 205, 218)
AGUA_TRACO = (52, 108, 160)
VERDE_SIMB = (74, 118, 62)
VERDE_ESCURO = (48, 86, 44)
ARROZ = (96, 138, 82)
DIQUE = (122, 104, 74)
CURVA = (168, 104, 52)
CURVA_MESTRA = (150, 86, 38)
PRETO = (34, 31, 27)
GRADE = (30, 30, 34)
GRADE_FINA = (92, 104, 118)


@dataclass
class Dados:
    info: dict
    w: int
    h: int
    cell: float
    ox: float
    oz: float
    alturas: np.ndarray  # m, (h, w)
    paisagem: np.ndarray  # u8
    baixada: np.ndarray  # 0..1
    cipo: np.ndarray  # 0..1


def acha_lune() -> str | None:
    if os.environ.get("LUNE"):
        return os.environ["LUNE"]
    p = shutil.which("lune")
    if p:
        return p
    base = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/vt65-tools/lune"
    for nome in ("lune.exe", "lune"):
        if (base / nome).exists():
            return str(base / nome)
    return None


def exporta_dados() -> None:
    lune = acha_lune()
    if not lune:
        sys.exit("Lune não encontrado: defina LUNE ou rode antes `lune run tools/carta_dados.luau`")
    subprocess.run([lune, "run", "tools/carta_dados.luau"], cwd=ROOT, check=True)


def carrega() -> Dados:
    info = json.loads((DADOS / "dados.json").read_text("utf-8"))
    g = info["grid"]
    w, h = int(g["width"]), int(g["height"])
    alt = np.fromfile(DADOS / "alturas.bin", dtype="<u2").reshape(h, w).astype(np.float32)
    alt = (alt - float(g["heightOffsetCm"])) / 100.0

    def u8(nome: str) -> np.ndarray:
        return np.fromfile(DADOS / nome, dtype=np.uint8).reshape(h, w)

    return Dados(
        info=info,
        w=w,
        h=h,
        cell=float(g["cellStuds"]),
        ox=float(g["originX"]),
        oz=float(g["originZ"]),
        alturas=alt,
        paisagem=u8("paisagem.bin"),
        baixada=u8("baixada.bin").astype(np.float32) / 255,
        cipo=u8("cipo.bin").astype(np.float32) / 255,
    )


# ---------- geometria: studs do jogo -> pixel da carta (N x N) ----------
class Quadro:
    def __init__(self, d: Dados):
        b = d.info["bounds"]
        self.x0, self.x1 = float(b["minX"]), float(b["maxX"])
        self.z0, self.z1 = float(b["minZ"]), float(b["maxZ"])
        self.k = N / (self.x1 - self.x0)  # px por stud (a área é quadrada)
        self.m = d.info["studM"]
        self.d = d
        self.g = d.info["gridOrigin1965"]

    def px(self, x: float, z: float) -> tuple[float, float]:
        return (x - self.x0) * self.k, (z - self.z0) * self.k

    def px_m(self, metros: float) -> float:
        return metros / self.m * self.k

    def celula(self, x: np.ndarray, z: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """studs -> índice fracionário da grade (linha, coluna), centro da célula em .0"""
        d = self.d
        return (z - d.oz) / d.cell - 0.5, (x - d.ox) / d.cell - 0.5

    def amostra(self, grade: np.ndarray, n: int, ordem: int = 1) -> np.ndarray:
        """reamostra uma grade do jogo para n x n px cobrindo a área jogável"""
        t = (np.arange(n, dtype=np.float64) + 0.5) / n
        xs = self.x0 + t * (self.x1 - self.x0)
        zs = self.z0 + t * (self.z1 - self.z0)
        r, c = self.celula(xs, zs)
        rr, cc = np.meshgrid(r, c, indexing="ij")
        return ndimage.map_coordinates(grade, [rr, cc], order=ordem, mode="nearest").astype(
            np.float32
        )

    def de_celula(self, r: float, c: float) -> tuple[float, float]:
        d = self.d
        return self.px(d.ox + (c + 0.5) * d.cell, d.oz + (r + 0.5) * d.cell)

    def E(self, x: float) -> float:
        return self.g["e"] + x * self.m

    def Nn(self, z: float) -> float:
        return self.g["n"] - z * self.m

    def x_de_E(self, e: float) -> float:
        return (e - self.g["e"]) / self.m

    def z_de_N(self, n: float) -> float:
        return (self.g["n"] - n) / self.m


# ---------- fontes (Windows; DejaVu no Linux) ----------
DIRS_FONTE = [
    Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts",
    Path("/usr/share/fonts/truetype/dejavu"),
    Path("/usr/share/fonts/TTF"),
]


def fonte(nomes: list[str], tam: int) -> ImageFont.FreeTypeFont:
    for n in nomes:
        for d in DIRS_FONTE:
            if (d / n).exists():
                return ImageFont.truetype(str(d / n), tam)
    return ImageFont.load_default(tam)  # type: ignore[return-value]


def F_SANS(t: int) -> ImageFont.FreeTypeFont:
    return fonte(["arial.ttf", "DejaVuSans.ttf"], t)


def F_SANS_B(t: int) -> ImageFont.FreeTypeFont:
    return fonte(["arialbd.ttf", "DejaVuSans-Bold.ttf"], t)


def F_ESTREITA(t: int) -> ImageFont.FreeTypeFont:
    return fonte(["ARIALN.TTF", "arialn.ttf", "DejaVuSansCondensed.ttf"], t)


def F_ESTREITA_B(t: int) -> ImageFont.FreeTypeFont:
    return fonte(["ARIALNB.TTF", "arialnb.ttf", "DejaVuSansCondensed-Bold.ttf"], t)


def F_ITALICO(t: int) -> ImageFont.FreeTypeFont:
    return fonte(["timesi.ttf", "DejaVuSerif-Italic.ttf"], t)


def F_SERIF_B(t: int) -> ImageFont.FreeTypeFont:
    return fonte(["timesbd.ttf", "DejaVuSerif-Bold.ttf"], t)


def texto_img(txt: str, f: ImageFont.FreeTypeFont, cor, halo=None, halo_w: int = 0) -> Image.Image:
    esq, t, r, b = f.getbbox(txt, stroke_width=halo_w)
    im = Image.new("RGBA", (r - esq + 6, b - t + 6), (0, 0, 0, 0))
    ImageDraw.Draw(im).text(
        (3 - esq, 3 - t), txt, font=f, fill=cor, stroke_width=halo_w, stroke_fill=halo
    )
    return im


def cola(camada: Image.Image, im: Image.Image, cx: float, cy: float, ang: float = 0.0) -> None:
    """compõe im centrado em (cx, cy), girado ang graus (anti-horário), recortando nas bordas"""
    if ang:
        im = im.rotate(ang, resample=Image.Resampling.BICUBIC, expand=True)
    x, y = int(round(cx - im.width / 2)), int(round(cy - im.height / 2))
    sx, sy = max(0, -x), max(0, -y)
    x, y = max(0, x), max(0, y)
    if sx >= im.width or sy >= im.height or x >= camada.width or y >= camada.height:
        return
    camada.alpha_composite(im, (x, y), (sx, sy))


def caixa_rot(cx: float, cy: float, w: float, h: float, ang: float) -> list[tuple[float, float]]:
    a = math.radians(-ang)
    ux, uy = math.cos(a), math.sin(a)
    vx, vy = -uy, ux
    pts = []
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        pts.append((cx + sx * w / 2 * ux + sy * h / 2 * vx, cy + sx * w / 2 * uy + sy * h / 2 * vy))
    return pts


# ---------- camadas ----------
def papel(rng: np.random.Generator) -> np.ndarray:
    base = np.empty((N, N, 3), np.float32)
    base[:] = PAPEL
    manchas = ndimage.gaussian_filter(rng.standard_normal((N // 16, N // 16)), 3)
    manchas = ndimage.zoom(manchas / (manchas.std() + 1e-6), 16, order=1)[:N, :N]
    fibra = ndimage.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), 0.8)
    fibra /= fibra.std() + 1e-6
    base += (manchas * 3.0 + fibra * 1.6)[..., None]
    return base


def tintas(q: Quadro, d: Dados) -> tuple[np.ndarray, dict[int, np.ndarray]]:
    """cor de fundo por paisagem (bordas orgânicas: máscaras suavizadas antes de reamostrar)"""
    L = d.info["landscape"]
    mascaras = {}
    for k in (L["forest"], L["grove"], L["farm"], L["clear"], L["stream"]):
        m = ndimage.gaussian_filter((d.paisagem == k).astype(np.float32), 0.9)
        mascaras[k] = q.amostra(m, N)
    soma = sum(mascaras.values()) + 1e-6
    for k in mascaras:
        mascaras[k] = mascaras[k] / soma
    cipo = q.amostra(ndimage.gaussian_filter(d.cipo, 1.0), N)
    densa = np.clip((cipo - 0.52) / 0.12, 0, 1)[..., None]
    mata = np.array(MATA, np.float32) * (1 - densa) + np.array(MATA_DENSA, np.float32) * densa
    cor = (
        mascaras[L["forest"]][..., None] * mata
        + mascaras[L["grove"]][..., None] * np.array(BOSQUE, np.float32)
        + mascaras[L["farm"]][..., None] * np.array(LAVOURA, np.float32)
        + mascaras[L["clear"]][..., None] * np.array(CLAREIRA, np.float32)
        + mascaras[L["stream"]][..., None] * np.array(MATA, np.float32)
    )
    return cor, mascaras


def sombreado(q: Quadro, d: Dados) -> np.ndarray:
    """relevo sombreado (luz de NO a 45°), exagero vertical de 2,5x: o relevo vai de 8 a 50 m.
    Suavização de ~18 m: os patamares de 12 cm dos quadros de arroz (export_roblox) e os degraus do
    DEM viravam faixas na sombra."""
    z = ndimage.gaussian_filter(d.alturas, 4.0) * 2.5
    passo = d.cell * q.m
    gy, gx = np.gradient(z, passo)
    az, alt = math.radians(315), math.radians(45)
    lx, ly, lz = math.sin(az) * math.cos(alt), -math.cos(az) * math.cos(alt), math.sin(alt)
    # linhas = sul (gy > 0 sobe para o sul); a luz vem do NO
    nx, ny, nz = -gx, -gy, np.ones_like(gx)
    nrm = np.sqrt(nx * nx + ny * ny + nz * nz)
    s = (nx * lx + ny * ly + nz * lz) / nrm
    plano = lz
    f = 1.0 + 0.6 * (s - plano)
    return np.clip(q.amostra(f.astype(np.float32), N, ordem=3), 0.7, 1.08)


def poligonos_agua(q: Quadro, dr: ImageDraw.ImageDraw, d: Dados) -> None:
    for x, z, u, v, a in d.info["waters"]:
        ca, sa = math.cos(a), math.sin(a)
        pts = []
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            px = x + su * u / 2 * ca + sv * v / 2 * sa
            pz = z - su * u / 2 * sa + sv * v / 2 * ca
            pts.append(q.px(px, pz))
        dr.polygon(pts, fill=(*AGUA, 92))


def simbolos_area(
    q: Quadro, cam: Image.Image, mascaras: dict[int, np.ndarray], d: Dados, rng
) -> None:
    """arroz (tufos), bambu e tràm na baixada, árvores do bosque de vila"""
    L = d.info["landscape"]
    dr = ImageDraw.Draw(cam)
    s = SS
    baixada = q.amostra(d.baixada, N // 4)

    def em(m: np.ndarray, x: float, y: float, escala: int = 1) -> float:
        i = min(int(y / escala), m.shape[0] - 1)
        j = min(int(x / escala), m.shape[1] - 1)
        return float(m[i, j])

    # tufos de arroz em fileiras desencontradas (a cada 17 m)
    passo = 17 * s
    for lin, y in enumerate(range(passo // 2, N, passo)):
        off = (passo // 2) if lin % 2 else 0
        for x in range(passo // 2 + off, N, passo):
            if em(mascaras[L["farm"]], x, y) < 0.55:
                continue
            jx, jy = rng.uniform(-2, 2) * s, rng.uniform(-2, 2) * s
            cx, cy = x + jx, y + jy
            for dx, t in ((-2.2, -0.5), (0, 0), (2.2, 0.5)):
                dr.line(
                    [(cx + dx * s, cy), (cx + (dx + t * 2) * s, cy - 4.2 * s)],
                    fill=(*ARROZ, 175),
                    width=s,
                )
            dr.line(
                [(cx - 3 * s, cy + 0.6 * s), (cx + 3 * s, cy + 0.6 * s)],
                fill=(*ARROZ, 130),
                width=s,
            )
    # baixada: touceiras de bambu e tràm (o ruído do plano da mata, só onde ele é forte: lá a
    # densidade de bambu e tràm passa de 2x a do resto da mata)
    passo = 25 * s
    for lin, y in enumerate(range(passo // 2, N, passo)):
        off = (passo // 2) if lin % 2 else 0
        for x in range(passo // 2 + off, N, passo):
            if em(mascaras[L["forest"]], x, y) < 0.6 or em(baixada, x, y, 4) < 0.7:
                continue
            cx, cy = x + rng.uniform(-5, 5) * s, y + rng.uniform(-5, 5) * s
            for bx in (-2.6, 0.0, 2.6):
                for ang in (-34, -12, 12, 34):
                    a = math.radians(ang - 90)
                    r = rng.uniform(3.6, 5.6) * s
                    p0 = (cx + bx * s, cy)
                    dr.line(
                        [p0, (p0[0] + math.cos(a) * r, p0[1] + math.sin(a) * r)],
                        fill=(*VERDE_ESCURO, 200),
                        width=s,
                    )
            dr.line(
                [(cx - 4.5 * s, cy + 0.5 * s), (cx + 4.5 * s, cy + 0.5 * s)],
                fill=(*VERDE_ESCURO, 200),
                width=s,
            )
    # bosque de vila: copas redondas
    passo = 13 * s
    for lin, y in enumerate(range(passo // 2, N, passo)):
        off = (passo // 2) if lin % 2 else 0
        for x in range(passo // 2 + off, N, passo):
            if em(mascaras[L["grove"]], x, y) < 0.55:
                continue
            cx, cy = x + rng.uniform(-2, 2) * s, y + rng.uniform(-2, 2) * s
            r = rng.uniform(2.2, 3.0) * s
            dr.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(*VERDE_SIMB, 220), width=s)


def diques(q: Quadro, dr: ImageDraw.ImageDraw, d: Dados) -> None:
    for x1, z1, x2, z2 in d.info["dikes"]:
        dr.line([q.px(x1, z1), q.px(x2, z2)], fill=(*DIQUE, 190), width=max(1, int(0.9 * SS)))


def riachos(q: Quadro, cam: Image.Image, d: Dados) -> None:
    """riacho: as células de classe riacho ligadas pelos vizinhos, em linha azul"""
    L = d.info["landscape"]
    m = d.paisagem == L["stream"]
    dr = ImageDraw.Draw(cam)
    ys, xs = np.nonzero(m)
    pts = set(zip(ys.tolist(), xs.tolist(), strict=True))
    largura = int(3.2 * SS)
    for r, c in pts:
        p = q.de_celula(r, c)
        for dr_, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
            if (r + dr_, c + dc) in pts:
                # diagonal só se não houver o caminho reto (evita triângulos)
                if dr_ and dc and ((r + dr_, c) in pts or (r, c + dc) in pts):
                    continue
                dr.line([p, q.de_celula(r + dr_, c + dc)], fill=(*AGUA_TRACO, 255), width=largura)
        dr.ellipse(
            [p[0] - largura / 2, p[1] - largura / 2, p[0] + largura / 2, p[1] + largura / 2],
            fill=(*AGUA_TRACO, 255),
        )


Rotulo = tuple[float, float, float, float, float]  # cx, cy, largura, altura, ângulo


def curvas(q: Quadro, cam: Image.Image, d: Dados) -> list[Rotulo]:
    """curvas de nível a cada 5 m (mestra a cada 25 m, com cota). Devolve as caixas dos rótulos."""
    z = ndimage.gaussian_filter(d.alturas, 1.6)
    z2 = ndimage.zoom(z, 2, order=3)  # meia célula: curva mais lisa
    dr = ImageDraw.Draw(cam)
    rotulos: list[Rotulo] = []
    f_cota = F_ESTREITA_B(int(11 * SS))
    for nivel in range(5, 80, 5):
        if nivel < float(z.min()) or nivel > float(z.max()):
            continue
        mestra = nivel % 25 == 0
        cor = CURVA_MESTRA if mestra else CURVA
        larg = int((1.9 if mestra else 1.0) * SS)
        for c in find_contours(z2, nivel):
            if len(c) < 6:
                continue
            pts = [q.de_celula(r / 2 - 0.25, cc / 2 - 0.25) for r, cc in c]
            dr.line(pts, fill=(*cor, 235), width=larg, joint="curve")
            # cota: na mestra a cada ~700 px; nas outras só em curvas longas
            comp = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
            if not mestra and comp < 900 * SS / 2:
                continue
            passo = (700 if mestra else 1300) * SS / 2
            alvo, acum = passo * 0.5, 0.0
            for i in range(len(pts) - 1):
                seg = math.dist(pts[i], pts[i + 1])
                acum += seg
                if acum < alvo:
                    continue
                alvo += passo
                j = min(i + 6, len(pts) - 1)
                i0 = max(i - 6, 0)
                (ax, ay), (bx, by) = pts[i0], pts[j]
                cx, cy = pts[i]
                if not (60 * SS < cx < N - 60 * SS and 60 * SS < cy < N - 60 * SS):
                    continue
                ang = math.degrees(math.atan2(-(by - ay), bx - ax))
                if ang > 90:
                    ang -= 180
                elif ang < -90:
                    ang += 180
                im = texto_img(str(nivel), f_cota, (*cor, 255))
                rotulos.append((cx, cy, im.width + 6 * SS, im.height, ang))
    return rotulos  # desenhados depois de recortar a curva


def sebes(q: Quadro, dr: ImageDraw.ImageDraw, d: Dados) -> None:
    """sebe de bambu (alta): fileira de bolinhas; sebe baixa do arrozal: pontilhado fino"""
    for x1, z1, x2, z2, altura in d.info["hedges"]:
        a, b = q.px(x1, z1), q.px(x2, z2)
        comp = math.dist(a, b)
        if comp < 1:
            continue
        alta = altura > 3.0
        passo = (5.0 if alta else 4.0) * SS
        n = max(1, int(comp / passo))
        for i in range(n + 1):
            t = i / n
            x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            r = (1.7 if alta else 0.9) * SS
            if alta:
                dr.ellipse([x - r, y - r, x + r, y + r], fill=(*VERDE_ESCURO, 230))
            else:
                dr.ellipse([x - r, y - r, x + r, y + r], fill=(*VERDE_SIMB, 200))


def casas(q: Quadro, dr: ImageDraw.ImageDraw, d: Dados) -> None:
    """casa de 7 x 4,5 m (FeatureBuilder), desenhada 30% maior para ler na escala"""
    L, W = 7 / q.m * 1.3, 4.5 / q.m * 1.3
    for x, z, a in d.info["houses"]:
        ca, sa = math.cos(a), math.sin(a)
        pts = []
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            px = x + su * L / 2 * ca + sv * W / 2 * sa
            pz = z - su * L / 2 * sa + sv * W / 2 * ca
            pts.append(q.px(px, pz))
        dr.polygon(pts, fill=(*PRETO, 255))


def trincheira(q: Quadro, dr: ImageDraw.ImageDraw, d: Dados) -> None:
    pts = [q.px(x, z) for x, z in d.info["trench"]]
    dr.line(pts, fill=(*PRETO, 255), width=int(1.6 * SS), joint="curve")
    # dentes do símbolo de trincheira, do lado da vila (norte)
    for i in range(len(pts) - 1):
        (ax, ay), (bx, by) = pts[i], pts[i + 1]
        comp = math.dist((ax, ay), (bx, by))
        ux, uy = (bx - ax) / comp, (by - ay) / comp
        nx, ny = uy, -ux
        if ny > 0:
            nx, ny = -nx, -ny
        k = 0.0
        while k < comp:
            x, y = ax + ux * k, ay + uy * k
            dr.line([(x, y), (x + nx * 3.4 * SS, y + ny * 3.4 * SS)], fill=(*PRETO, 255), width=SS)
            k += 4.5 * SS


def cemiterio(q: Quadro, cam: Image.Image, d: Dados) -> None:
    for sp in d.info["strongpoints"]:
        if sp["name"] == "Cemitério":
            cx, cy = q.px(sp["x"], sp["z"])
            dr = ImageDraw.Draw(cam)
            r = 9 * SS
            dr.rectangle(
                [cx - r, cy - r * 0.75, cx + r, cy + r * 0.75], outline=(*PRETO, 255), width=SS
            )
            for dx in (-4.5, 0, 4.5):
                x = cx + dx * SS
                dr.line([(x, cy - 3.6 * SS), (x, cy + 3.6 * SS)], fill=(*PRETO, 255), width=SS)
                dr.line(
                    [(x - 2 * SS, cy - 1.4 * SS), (x + 2 * SS, cy - 1.4 * SS)],
                    fill=(*PRETO, 255),
                    width=SS,
                )
            cola(
                cam,
                texto_img("Cem", F_ITALICO(int(12 * SS)), (*PRETO, 255), (*PAPEL, 230), SS),
                cx + 22 * SS,
                cy,
            )


def campo(q: Quadro, cam: Image.Image, d: Dados) -> None:
    """Athletic field: retângulo tracejado da carta (o tamanho é o da clareira do jogo, 70 m)"""
    for loc in d.info["locations"]:
        if loc["name"] == "Athletic field":
            cx, cy = q.px(loc["x"], loc["z"])
            hw, hh = q.px_m(50), q.px_m(32)
            dr = ImageDraw.Draw(cam)
            pts = [(cx - hw, cy - hh), (cx + hw, cy - hh), (cx + hw, cy + hh), (cx - hw, cy + hh)]
            for i in range(4):
                tracejado(
                    dr, pts[i], pts[(i + 1) % 4], (*PRETO, 230), int(1.1 * SS), 6 * SS, 4 * SS
                )
            cola(
                cam,
                texto_img(
                    "Athletic field", F_ITALICO(int(12 * SS)), (*PRETO, 255), (*PAPEL, 220), SS
                ),
                cx,
                cy + hh + 11 * SS,
            )


def tracejado(dr, a, b, cor, larg: int, traco: float, vao: float) -> None:
    comp = math.dist(a, b)
    if comp < 1e-6:
        return
    ux, uy = (b[0] - a[0]) / comp, (b[1] - a[1]) / comp
    t = 0.0
    while t < comp:
        e = min(t + traco, comp)
        dr.line(
            [(a[0] + ux * t, a[1] + uy * t), (a[0] + ux * e, a[1] + uy * e)], fill=cor, width=larg
        )
        t = e + vao


def tracejado_linha(dr, pts, cor, larg: int, traco: float, vao: float) -> None:
    """tracejado contínuo ao longo de uma polilinha"""
    resto, desenhando = traco, True
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        comp = math.dist(a, b)
        if comp < 1e-6:
            continue
        ux, uy = (b[0] - a[0]) / comp, (b[1] - a[1]) / comp
        t = 0.0
        while t < comp:
            e = min(t + resto, comp)
            if desenhando:
                dr.line(
                    [(a[0] + ux * t, a[1] + uy * t), (a[0] + ux * e, a[1] + uy * e)],
                    fill=cor,
                    width=larg,
                )
            resto -= e - t
            t = e
            if resto <= 1e-6:
                desenhando = not desenhando
                resto = traco if desenhando else vao


# ---------- trilhas (DESIGN) ----------
def vilas(d: Dados, raio_m: float = 120.0) -> list[tuple[float, float, int]]:
    """agrupa as casas em vilas (casas a menos de raio_m de outra); devolve (x, z, nº de casas)"""
    hs = np.array([(x, z) for x, z, _ in d.info["houses"]], dtype=float)
    n = len(hs)
    pai = list(range(n))

    def raiz(i: int) -> int:
        while pai[i] != i:
            pai[i] = pai[pai[i]]
            i = pai[i]
        return i

    lim = raio_m / d.info["studM"]
    for i in range(n):
        for j in range(i + 1, n):
            if np.hypot(*(hs[i] - hs[j])) < lim:
                pai[raiz(i)] = raiz(j)
    grupos: dict[int, list[int]] = {}
    for i in range(n):
        grupos.setdefault(raiz(i), []).append(i)
    return [(float(hs[g, 0].mean()), float(hs[g, 1].mean()), len(g)) for g in grupos.values()]


def trilhas(q: Quadro, d: Dados) -> list[list[tuple[float, float]]]:
    """caminho de menor custo entre as vilas e os QGs (lavoura e clareira baratas, mata cara)"""
    L = d.info["landscape"]
    custo = np.full(d.paisagem.shape, 5.0, np.float64)
    custo[d.paisagem == L["farm"]] = 1.0
    custo[d.paisagem == L["clear"]] = 1.0
    custo[d.paisagem == L["grove"]] = 1.6
    custo[d.paisagem == L["stream"]] = 25.0
    gy, gx = np.gradient(ndimage.gaussian_filter(d.alturas, 1.0), d.cell * q.m)
    custo *= 1.0 + 14.0 * np.hypot(gx, gy)
    b = d.info["bounds"]
    nos = [(x, z) for x, z, n in vilas(d) if n >= 3]
    for hq in d.info["hq"].values():
        nos.append((hq["x"], hq["z"]))
    for loc in d.info["locations"]:
        if loc["name"] in ("Athletic field", "LZ Blue"):
            nos.append((loc["x"], loc["z"]))
    dentro = [
        (x, z)
        for x, z in nos
        if b["minX"] - 50 <= x <= b["maxX"] + 50 and b["minZ"] - 300 <= z <= b["maxZ"] + 300
    ]
    # árvore geradora mínima (Prim) + a 2ª ligação mais curta de cada nó: rede com alguns laços
    n = len(dentro)
    dist = np.array([[math.dist(a, c) for c in dentro] for a in dentro])
    usados, arestas = {0}, set()
    while len(usados) < n:
        best = None
        for i in usados:
            for j in range(n):
                if j not in usados and (best is None or dist[i, j] < dist[best[0], best[1]]):
                    best = (i, j)
        assert best
        usados.add(best[1])
        arestas.add(tuple(sorted(best)))
    for i in range(n):
        ordem = np.argsort(dist[i])
        if len(ordem) > 2:
            j = int(ordem[2])
            if dist[i, j] < 900 / q.m:
                arestas.add(tuple(sorted((i, j))))

    def cel(x: float, z: float) -> tuple[int, int]:
        r, c = q.celula(np.array(x), np.array(z))
        return int(np.clip(round(float(r)), 0, d.h - 1)), int(np.clip(round(float(c)), 0, d.w - 1))

    caminhos: list[list[tuple[float, float]]] = []
    caminhos_cel: list[list[tuple[int, int]]] = []
    trilha = np.zeros(d.paisagem.shape, bool)
    # as mais curtas primeiro; trilha já traçada fica barata, e a seguinte se junta a ela em vez de
    # correr paralela a poucos metros
    for i, j in sorted(arestas, key=lambda e: dist[e[0], e[1]]):
        a, c = cel(*dentro[i]), cel(*dentro[j])
        mcp = MCP_Geometric(custo, fully_connected=True)
        mcp.find_costs([a], [c])
        rota = mcp.traceback(c)
        if len(rota) < 4:
            continue
        # só os trechos novos (o que já é trilha não se desenha de novo)
        trechos: list[list[tuple[int, int]]] = [[]]
        for r, cc in rota:
            if trilha[r, cc]:
                if trechos[-1]:
                    trechos[-1].append((r, cc))
                    trechos.append([])
            else:
                trechos[-1].append((r, cc))
        for r, cc in rota:
            custo[r, cc] = min(custo[r, cc], 0.35)
            trilha[r, cc] = True
        for t in trechos:
            if len(t) >= 4:
                caminhos_cel.append(t)
    for t in caminhos_cel:
        pts = np.array([q.de_celula(r, cc) for r, cc in t], dtype=float)
        # suaviza (média móvel) e simplifica
        k = 7
        if len(pts) > k:
            ker = np.ones(k) / k
            sx = np.convolve(np.pad(pts[:, 0], k // 2, mode="edge"), ker, mode="valid")
            sy = np.convolve(np.pad(pts[:, 1], k // 2, mode="edge"), ker, mode="valid")
            pts = np.column_stack([sx, sy])
        caminhos.append([tuple(p) for p in pts[::2]] + [tuple(pts[-1])])
    return caminhos


# ---------- grade militar ----------
def grade(q: Quadro, cam: Image.Image) -> None:
    dr = ImageDraw.Draw(cam)
    e0, e1 = q.E(q.x0), q.E(q.x1)
    n0, n1 = q.Nn(q.z1), q.Nn(q.z0)  # sul, norte
    # 100 m: linhas finas (leitura da grade de 6 algarismos, "BS 693 928")
    for e in range(int(math.ceil(e0 / 100)) * 100, int(e1) + 1, 100):
        if e % 1000 == 0:
            continue
        x, _ = q.px(q.x_de_E(e), 0)
        dr.line([(x, 0), (x, N)], fill=(*GRADE_FINA, 46), width=SS)
    for n in range(int(math.ceil(n0 / 100)) * 100, int(n1) + 1, 100):
        if n % 1000 == 0:
            continue
        _, y = q.px(0, q.z_de_N(n))
        dr.line([(0, y), (N, y)], fill=(*GRADE_FINA, 46), width=SS)
    # 1 km: linhas da quadrícula da carta
    es = [e for e in range(int(math.ceil(e0 / 1000)) * 1000, int(e1) + 1, 1000)]
    ns = [n for n in range(int(math.ceil(n0 / 1000)) * 1000, int(n1) + 1, 1000)]
    for e in es:
        x, _ = q.px(q.x_de_E(e), 0)
        dr.line([(x, 0), (x, N)], fill=(*GRADE, 230), width=int(1.5 * SS))
    for n in ns:
        _, y = q.px(0, q.z_de_N(n))
        dr.line([(0, y), (N, y)], fill=(*GRADE, 230), width=int(1.5 * SS))
    # números: algarismos principais grandes ("69"), o resto pequeno (²69⁰⁰⁰ᵐE.)
    grande, pequeno = F_SANS_B(int(26 * SS)), F_SANS_B(int(13 * SS))
    halo = (*PAPEL, 235)

    def rotulo(principal: str, antes: str, depois: str, cx: float, cy: float) -> None:
        g = texto_img(principal, grande, (*GRADE, 255), halo, 3 * SS)
        partes = [g]
        if antes:
            partes.insert(0, texto_img(antes, pequeno, (*GRADE, 255), halo, 2 * SS))
        if depois:
            partes.append(texto_img(depois, pequeno, (*GRADE, 255), halo, 2 * SS))
        w = sum(p.width for p in partes) - 4 * (len(partes) - 1)
        h = max(p.height for p in partes)
        im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        x = 0
        for p in partes:
            y = 0 if p is not g else h - p.height
            im.alpha_composite(p, (x, y))
            x += p.width - 4
        cola(cam, im, cx, cy)

    margem = 26 * SS
    for i, e in enumerate(es):
        x, _ = q.px(q.x_de_E(e), 0)
        s = f"{e // 1000:03d}"
        cheio = i == 0
        for y in (margem, N - margem):
            rotulo(s[1:], s[0] if cheio else "", "000m.E." if cheio else "", x + 4 * SS, y)
    for i, n in enumerate(ns):
        _, y = q.px(0, q.z_de_N(n))
        s = f"{n // 1000:04d}"
        cheio = i == 0
        for x in (margem * 2.2, N - margem * 2.2):
            rotulo(s[2:], s[:2] if cheio else "", "000m.N." if cheio else "", x, y - 3 * SS)
    # marcas de 100 m nas quatro bordas, com o algarismo da centena
    f = F_SANS(int(10 * SS))
    for e in range(int(math.ceil(e0 / 100)) * 100, int(e1) + 1, 100):
        if e % 1000 == 0:
            continue
        x, _ = q.px(q.x_de_E(e), 0)
        for y0, y1, ty in ((0, 9 * SS, 16 * SS), (N, N - 9 * SS, N - 16 * SS)):
            dr.line([(x, y0), (x, y1)], fill=(*GRADE, 255), width=SS)
            cola(cam, texto_img(str((e // 100) % 10), f, (*GRADE, 255), halo, SS), x, ty)
    for n in range(int(math.ceil(n0 / 100)) * 100, int(n1) + 1, 100):
        if n % 1000 == 0:
            continue
        _, y = q.px(0, q.z_de_N(n))
        for x0, x1, tx in ((0, 9 * SS, 16 * SS), (N, N - 9 * SS, N - 16 * SS)):
            dr.line([(x0, y), (x1, y)], fill=(*GRADE, 255), width=SS)
            cola(cam, texto_img(str((n // 100) % 10), f, (*GRADE, 255), halo, SS), tx, y)


# ---------- nomes e cotas ----------
VILAS = ("Nam Yên (3)", "Nam Yên (4)", "An Cường (2)", "An Thới (2)", "Lạc Sơn (1)")


def cotas(q: Quadro, d: Dados) -> list[tuple[float, float, int]]:
    """topos: máximos locais com ~6 m de proeminência na janela de ~180 m"""
    z = ndimage.gaussian_filter(d.alturas, 1.2)
    mx = ndimage.maximum_filter(z, size=41)
    mn = ndimage.minimum_filter(z, size=41)
    rr, cc = np.nonzero((z == mx) & (mx - mn > 6.0))
    out = []
    b = d.info["bounds"]
    for r, c in zip(rr.tolist(), cc.tolist(), strict=True):
        x, zz = d.ox + (c + 0.5) * d.cell, d.oz + (r + 0.5) * d.cell
        if not (b["minX"] + 120 < x < b["maxX"] - 120 and b["minZ"] + 120 < zz < b["maxZ"] - 120):
            continue
        out.append((x, zz, int(round(float(d.alturas[r, c])))))
    out.sort(key=lambda t: -t[2])
    return out[:9]


def nomes(q: Quadro, cam: Image.Image, d: Dados, caixas: list) -> None:
    halo = (*PAPEL, 235)
    f_vila = F_SANS_B(int(24 * SS))
    for loc in d.info["locations"]:
        if loc["name"] not in VILAS:
            continue
        x, z = loc["x"], loc["z"]
        b = d.info["bounds"]
        dy = -40 * SS  # acima das casas (o centro da vila é o meio das casas)
        if z > b["maxZ"] - 300:
            # Lạc Sơn (1) fica 20 m ao sul da borda: o nome entra na carta, a nordeste das casas
            x, z, dy = x + 420, b["maxZ"] - 330, 0
        cx, cy = q.px(x, z)
        im = texto_img(loc["name"], f_vila, (*PRETO, 255), halo, 3 * SS)
        cola(cam, im, cx, cy + dy)
        caixas.append((cx, cy + dy, im.width, im.height))
    # colinas: cota com ponto e o nome usado no jogo
    dr = ImageDraw.Draw(cam)
    f_cota = F_ESTREITA_B(int(18 * SS))
    f_colina = F_ESTREITA_B(int(17 * SS))
    feitas: list[tuple[float, float]] = []
    for loc in d.info["locations"]:
        if not loc["name"].startswith("Colina"):
            continue
        r, c = q.celula(np.array(loc["x"]), np.array(loc["z"]))
        h = float(ndimage.map_coordinates(d.alturas, [[float(r)], [float(c)]], order=1)[0])
        cx, cy = q.px(loc["x"], loc["z"])
        dr.ellipse([cx - 3 * SS, cy - 3 * SS, cx + 3 * SS, cy + 3 * SS], fill=(*PRETO, 255))
        cola(
            cam,
            texto_img(str(int(round(h))), f_cota, (*PRETO, 255), halo, 2 * SS),
            cx + 18 * SS,
            cy,
        )
        nome = loc["name"].replace(" (cume)", "").upper()
        cola(cam, texto_img(nome, f_colina, (*CURVA_MESTRA, 255), halo, 2 * SS), cx, cy + 24 * SS)
        feitas.append((cx, cy))
    for x, z, h in cotas(q, d):
        cx, cy = q.px(x, z)
        if any(math.dist((cx, cy), p) < 160 * SS for p in feitas):
            continue
        feitas.append((cx, cy))
        dr.ellipse([cx - 2.5 * SS, cy - 2.5 * SS, cx + 2.5 * SS, cy + 2.5 * SS], fill=(*PRETO, 255))
        cola(cam, texto_img(str(h), f_cota, (*PRETO, 255), halo, 2 * SS), cx + 15 * SS, cy)
    # riacho a leste de An Cường (2)
    for loc in d.info["locations"]:
        if loc["name"].startswith("Riacho"):
            cx, cy = q.px(loc["x"], loc["z"])
            im = texto_img("Suối", F_ITALICO(int(15 * SS)), (*AGUA_TRACO, 255), halo, 2 * SS)
            cola(cam, im, cx + 26 * SS, cy - 10 * SS, 70)


# ---------- rosa dos ventos, escala e notas ----------
def rosa_e_escala(q: Quadro, cam: Image.Image) -> None:
    dr = ImageDraw.Draw(cam)
    x0, y0, w, h = 58 * SS, 74 * SS, 252 * SS, 292 * SS
    sombra = Image.new("RGBA", (int(w), int(h)), (0, 0, 0, 0))
    ImageDraw.Draw(sombra).rectangle([0, 0, w, h], fill=(0, 0, 0, 60))
    cam.alpha_composite(
        sombra.filter(ImageFilter.GaussianBlur(4 * SS)), (int(x0 + 3 * SS), int(y0 + 4 * SS))
    )
    dr.rectangle(
        [x0, y0, x0 + w, y0 + h], fill=(*PAPEL, 255), outline=(*PRETO, 255), width=int(1.4 * SS)
    )
    dr.rectangle(
        [x0 + 4 * SS, y0 + 4 * SS, x0 + w - 4 * SS, y0 + h - 4 * SS],
        outline=(*PRETO, 255),
        width=SS,
    )
    # rosa de 8 pontas, alinhada ao norte da quadrícula
    cx, cy, R = x0 + w / 2, y0 + 108 * SS, 66 * SS
    dr.ellipse(
        [cx - R * 0.78, cy - R * 0.78, cx + R * 0.78, cy + R * 0.78],
        outline=(*PRETO, 255),
        width=SS,
    )
    dr.ellipse(
        [cx - R * 0.70, cy - R * 0.70, cx + R * 0.70, cy + R * 0.70],
        outline=(*PRETO, 160),
        width=SS,
    )
    for k in range(72):
        a = math.radians(k * 5)
        r0 = R * (0.70 if k % 2 else 0.66)
        dr.line(
            [
                (cx + math.sin(a) * r0, cy - math.cos(a) * r0),
                (cx + math.sin(a) * R * 0.78, cy - math.cos(a) * R * 0.78),
            ],
            fill=(*PRETO, 200),
            width=SS,
        )
    for k in range(8):
        a = math.radians(k * 45)
        longa = k % 2 == 0
        r = R * (1.0 if longa else 0.55)
        lado = R * (0.13 if longa else 0.09)
        ponta = (cx + math.sin(a) * r, cy - math.cos(a) * r)
        esq = (cx + math.sin(a - math.pi / 2) * lado, cy - math.cos(a - math.pi / 2) * lado)
        dir_ = (cx + math.sin(a + math.pi / 2) * lado, cy - math.cos(a + math.pi / 2) * lado)
        dr.polygon([ponta, esq, (cx, cy)], fill=(*PRETO, 255))
        dr.polygon([ponta, dir_, (cx, cy)], fill=(*PAPEL, 255), outline=(*PRETO, 255))
    f = F_SERIF_B(int(17 * SS))
    for txt, a in (("N", 0), ("L", 90), ("S", 180), ("O", 270)):
        r = R * 1.16
        cola(
            cam,
            texto_img(txt, f, (*PRETO, 255)),
            cx + math.sin(math.radians(a)) * r,
            cy - math.cos(math.radians(a)) * r,
        )
    cola(
        cam,
        texto_img("NORTE DA QUADRÍCULA", F_ESTREITA(int(10 * SS)), (*PRETO, 255)),
        cx,
        y0 + 18 * SS,
    )
    # escala gráfica: metros e jardas (como nas cartas do AMS), no tamanho real desta carta
    f_esc = F_ESTREITA(int(10 * SS))
    bx = x0 + 20 * SS
    for linha, (unid, total, divs, por) in enumerate(
        (("METROS", 200, 4, 1.0), ("JARDAS", 200, 4, 0.9144))
    ):
        y = y0 + 208 * SS + linha * 36 * SS
        comp = q.px_m(total * por)
        assert comp <= w - 30 * SS, "a escala gráfica não cabe no quadro"
        for i in range(divs):
            xa = bx + comp * i / divs
            xb = bx + comp * (i + 1) / divs
            dr.rectangle(
                [xa, y, xb, y + 5 * SS],
                fill=(*PRETO, 255) if i % 2 == 0 else (*PAPEL, 255),
                outline=(*PRETO, 255),
                width=SS,
            )
        for i in (0, divs):
            v = int(total * i / divs)
            cola(cam, texto_img(str(v), f_esc, (*PRETO, 255)), bx + comp * i / divs, y + 13 * SS)
        cola(cam, texto_img(unid, f_esc, (*PRETO, 255)), bx + comp / 2, y + 13 * SS)
    cola(
        cam,
        texto_img("CURVAS A CADA 5 METROS", F_ESTREITA(int(10 * SS)), (*PRETO, 255)),
        cx,
        y0 + h - 14 * SS,
    )


def notas(q: Quadro, cam: Image.Image, d: Dados) -> None:
    """notas de margem: a Rota 523 passa ao sul, fora da área (marco da Rota 523, BS 686911)"""
    halo = (*PAPEL, 235)
    f = F_ESTREITA_B(int(12 * SS))
    e_marco, n_marco = 268600, 1691133
    x = q.x_de_E(e_marco)
    km = (q.Nn(q.z1) - n_marco) / 1000
    cx, _ = q.px(x, 0)
    im = texto_img(f"ROTA 523 \u2193 {km:.1f} km".replace(".", ","), f, (*PRETO, 255), halo, 2 * SS)
    cola(cam, im, cx + im.width / 2, N - 34 * SS)


def envelhece(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """leve desbotado da tinta e manchas largas de papel guardado"""
    h = img.shape[0]
    yy, xx = np.mgrid[0:h, 0:h].astype(np.float32) / h
    borda = np.minimum.reduce([xx, yy, 1 - xx, 1 - yy])
    vinheta = 1 - 0.05 * np.clip(1 - borda / 0.12, 0, 1)
    manchas = ndimage.zoom(
        ndimage.gaussian_filter(rng.standard_normal((32, 32)), 2), h / 32, order=1
    )
    manchas = (manchas[:h, :h] / (np.abs(manchas).max() + 1e-6)).astype(np.float32)
    out = img * vinheta[..., None] * (1 - 0.02 * manchas[..., None])
    cinza = out.mean(axis=2, keepdims=True)
    return out * 0.92 + cinza * 0.08 + np.array([4, 2, -4], np.float32) * 0.6


def compoe(rgb: np.ndarray, cam: Image.Image) -> np.ndarray:
    a = np.asarray(cam, dtype=np.float32) / 255.0
    return rgb * (1 - a[..., 3:4]) + a[..., :3] * 255 * a[..., 3:4]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dados", action="store_true", help="exporta os dados pelo Lune antes")
    args = ap.parse_args()
    if args.dados or not (DADOS / "dados.json").exists():
        exporta_dados()
    d = carrega()
    q = Quadro(d)
    rng = np.random.default_rng(1965)

    rgb = papel(rng)
    cor, mascaras = tintas(q, d)
    rgb = rgb * 0.25 + cor * 0.75 + (rgb - np.array(PAPEL, np.float32)) * 0.75

    agua = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    poligonos_agua(q, ImageDraw.Draw(agua), d)
    rgb = compoe(rgb, agua)
    rgb *= sombreado(q, d)[..., None]

    simb = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    simbolos_area(q, simb, mascaras, d, rng)
    diques(q, ImageDraw.Draw(simb), d)
    rgb = compoe(rgb, simb)

    linhas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    rotulos = curvas(q, linhas, d)
    # cota da curva: recorta a curva embaixo do número e escreve no vão
    dl = ImageDraw.Draw(linhas)
    f_cota = F_ESTREITA_B(int(11 * SS))
    for cx, cy, w, h, ang in rotulos:
        dl.polygon(caixa_rot(cx, cy, w, h * 0.8, ang), fill=(0, 0, 0, 0))
    rgb = compoe(rgb, linhas)

    topo = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    riachos(q, topo, d)
    dt = ImageDraw.Draw(topo)
    sebes(q, dt, d)
    for caminho in trilhas(q, d):
        tracejado_linha(dt, caminho, (*PRETO, 225), int(1.3 * SS), 9 * SS, 5 * SS)
    casas(q, dt, d)
    trincheira(q, dt, d)
    cemiterio(q, topo, d)
    campo(q, topo, d)
    rgb = compoe(rgb, topo)

    # números das curvas (no vão recortado)
    num = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    zs = ndimage.gaussian_filter(d.alturas, 1.6)
    for cx, cy, _w, _h, ang in rotulos:
        x = q.x0 + cx / q.k
        z = q.z0 + cy / q.k
        r, c = q.celula(np.array(x), np.array(z))
        hv = float(ndimage.map_coordinates(zs, [[float(r)], [float(c)]], order=1)[0])
        nivel = int(round(hv / 5) * 5)
        cor_n = CURVA_MESTRA if nivel % 25 == 0 else CURVA
        cola(num, texto_img(str(nivel), f_cota, (*cor_n, 255)), cx, cy, ang)
    rgb = compoe(rgb, num)

    marg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    grade(q, marg)
    caixas: list = []
    nomes(q, marg, d, caixas)
    notas(q, marg, d)
    rosa_e_escala(q, marg)
    ImageDraw.Draw(marg).rectangle([0, 0, N - 1, N - 1], outline=(*PRETO, 255), width=int(2.5 * SS))
    rgb = compoe(rgb, marg)

    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    img = img.resize((LADO, LADO), Image.Resampling.LANCZOS)
    arr = envelhece(np.asarray(img, dtype=np.float32), rng)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")

    SAIDA.mkdir(parents=True, exist_ok=True)
    img.save(SAIDA / "carta_2048.png", optimize=True)
    meio = LADO // 2
    for lin in range(2):
        for col in range(2):
            bloco = img.crop((col * meio, lin * meio, (col + 1) * meio, (lin + 1) * meio))
            bloco.save(SAIDA / f"carta_{lin}_{col}.png", optimize=True)
    print(f"carta: {SAIDA / 'carta_2048.png'} e 4 blocos de {meio} px")


if __name__ == "__main__":
    main()
