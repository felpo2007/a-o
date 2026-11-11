"""Recorta o mundo gerado (4 x 2,4 km, D-03) para a área jogável (geo.PLAY_ING).

Recortes: 2 x 2 km (D-63) e, a pedido do dono em 2026-11-11, 1 x 1 km de Nam Yên (4) até o vale
do riacho a leste de An Cường (2), com a Colina 30 ao norte.

Entrada: os dados que tools/export_roblox.py gerou em src/ServerStorage/VT65Build/Data (Grid,
Heights_XX, Features). Não precisa das fontes grandes (DEM, carta, satélite), que ficam fora do Git.
A origem do quadro local continua no centro do mundo gerado (geo.play_center_wgs), então as
coordenadas dos locais, da grade de 1965 e do comandante não mudam.

O que fica:
  - terreno (alturas e uso do solo): área + MARGEM_M, o horizonte em volta;
  - diques, lâminas d'água e sebes: área + FEICOES_M (o arrozal não acaba em linha reta na borda;
    a cortina de árvores de fora começa a 40 m), menos o raio BASE_M do QG dos EUA;
  - casas e locais: só dentro da área (tudo que está fora do recorte some).

Riacho a leste de An Cường (2): a classificação da carta (tools/landcover.py) só pegou trechos
soltos do traço do riacho, ao sul da vila. O leito ("the streambed just east of An Cuong (2)", First
Fight p.29; local BS 702929) é o talvegue do vale no DEM. riacho_talvegue() segue o fundo do vale
do sul para o norte, marca as células como riacho (classe 5) e abre o leito (CANAL_M abaixo do
chão); lâminas d'água e diques que cruzam o leito saem. Feito uma vez: o Grid guarda
streamCarvedCm.

Saída:
  src/ServerStorage/VT65Build/Data/{Grid,Heights_XX,Features}.luau  recortados (área + margem)
  src/ReplicatedStorage/Shared/MapConfig.luau                        limites, setores, pontos fortes
  tests/luau/fixture_heights.json                                    só os pontos dentro do recorte

Rodar de novo sobre dados já recortados não muda nada (o recorte é o mesmo).
Uso (a partir de vantuong65/):
  uv run python tools/crop_world.py             recorta e escreve
  uv run python tools/crop_world.py --analisar  só mostra casas e manchas de vila por setor
"""

from __future__ import annotations

import base64
import csv
import json
import math
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from geo import PLAY_ING, STUD_M, WORLD_ING, ing_to_wgs_utm, play_center_wgs  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "src/ServerStorage/VT65Build/Data"
SHARED = ROOT / "src/ReplicatedStorage/Shared"
FIXTURE = ROOT / "tests/luau/fixture_heights.json"
MARGEM_M = 150.0  # terreno além da borda jogável (horizonte; a mesma margem do export_roblox)
FEICOES_M = 30.0  # diques, lâminas e sebes além da borda (o arrozal não acaba em linha reta)
LOCAIS_TOL_M = 20.0  # local da carta a até isto fora da borda ainda entra (Nam Yên (4) fica nela)
ROWS_PER = 64
HEAD = "--!strict\n-- GERADO por tools/export_roblox.py, recortado por tools/crop_world.py.\n"

# Riacho a leste de An Cường (2): talvegue do vale, do sul (onde a carta já marca o riacho) até o
# norte, onde o vale sobe para a Colina 30. Faixa de busca em E e N (ING-A), passo lateral máximo
# por linha da grade e fundura do leito aberto (o riacho do terreno tem 0,6 m d'água: o espelho
# fica ~0,5 m abaixo da margem).
RIACHO_E = (270080.0, 270330.0)
RIACHO_N = (1692350.0, 1693250.0)
RIACHO_PASSO = 2  # células por linha
CANAL_M = 1.1

# Fronteiras de setor, polilinhas sul -> norte em ING-A (1 x 1 km, 2026-11-11). Faixas de ~200 m de
# Nam Yên (4) (oeste) até o vale do riacho (leste); cada local real fica inteiro num setor.
#  - S1/S2 dobra a oeste ao norte de N 1693,0: o casario de Nam Yên (4) fica no S1 e An Thới (2)
#    no S2 (sem a dobra o S2 não teria nenhum local real);
#  - S2/S3 dobra a oeste ao norte de N 1693,0: o cume do morrote (33,7 m) fica no S3;
#  - S3/S4 a oeste da primeira casa de An Cường (2) e da boca E1 do túnel; S4/S5 a leste da
#    boca E2 e da ponta da trincheira sul.
FRONTEIRAS_ING = [
    [(269590, 1692500), (269590, 1693000), (269500, 1693000), (269500, 1693500)],
    [(269720, 1692500), (269720, 1693000), (269680, 1693000), (269680, 1693500)],
    [(269935, 1692500), (269935, 1693500)],
    [(270145, 1692500), (270145, 1693500)],
]
SETORES = [
    "S1 Nam Yên (4)",
    "S2 An Thới (2)",
    "S3 Morrote do arrozal",
    "S4 An Cường (2)",
    "S5 Riacho",
]
# Pontos fortes: (setor, nome, E, N, real?, observação). Três por setor.
PONTOS_FORTES = [
    # casario leste da vila (8 casas da carta); o rótulo da carta fica na borda oeste do recorte
    (1, "Nam Yên (4)", 269470, 1692790, True, "vila da carta"),
    (1, "Cemitério", 269435, 1692547, True, "símbolo de cemitério da carta"),
    (
        1,
        "Capinzal oeste",
        269420,
        1693070,
        False,
        "capim da carta no flanco do morro noroeste; nome de design",
    ),
    (2, "An Thới (2)", 269545, 1693221, True, "vila da carta"),
    (2, "Arrozal central", 269655, 1692700, False, "diques e sebes do arrozal; elemento de design"),
    (
        2,
        "Encosta norte",
        269630,
        1693070,
        False,
        "flanco noroeste do morrote (capim da carta); nome de design",
    ),
    (3, "Morrote do arrozal", 269765, 1692970, False, "morrote de 34 m no DEM; nome de design"),
    (
        3,
        "Lugarejo a sudoeste de An Cường (2)",
        269876,
        1692609,
        True,
        "mancha de vila/mata da carta",
    ),
    (3, "Arrozal norte", 269830, 1693260, False, "diques e sebes do arrozal; elemento de design"),
    (4, "An Cường (2)", 270030, 1692850, True, "vila fortificada (First Fight p.25)"),
    (4, "Trincheira sul", 270040, 1692640, True, "'wide, deep trench south of the village' (p.23)"),
    (
        4,
        "Arrozal ao norte de An Cường (2)",
        270040,
        1693170,
        False,
        "diques e sebes do arrozal; elemento de design",
    ),
    (5, "Colina 30", 270205, 1693420, True, "First Fight p.29"),
    (
        5,
        "Riacho a leste de An Cường (2)",
        270198,
        1692575,
        True,
        "'the streambed just east of An Cuong (2)' (First Fight p.29)",
    ),
    (
        5,
        "Encosta sul da Colina 30",
        270240,
        1693200,
        False,
        "relevo do DEM (vale do riacho até a Colina 30); nome de design",
    ),
]
# Base dos EUA (pedido do dono: "o QG dos EUA vai virar uma base grande depois; deixe espaço
# plano"): sem diques, lâminas d'água e sebes a até BASE_M do QG. O vale tem desvio de altura de
# 0,6–0,8 m nesse raio; o riacho continua. Os depósitos de veículos ficam a até 136 m do QG
# (VehicleService).
BASE_M = 140.0
QGS = {
    # vale do riacho: o chão mais plano do recorte (desvio de 0,6–0,8 m num raio de 120 m), com
    # espaço para a base crescer de N 1692,6 a 1693,05 dos dois lados do riacho
    "US": (270300, 1692950, "borda leste, no vale do riacho a leste de An Cường (2) (setor S5)"),
    "VC": (269410, 1693430, "morro do noroeste, retaguarda oeste (setor S1)"),
}


def ing_local(e: float, n: float) -> tuple[float, float]:
    """Studs no quadro local (X = leste, Z = sul), origem no centro do mundo gerado."""
    E, N = ing_to_wgs_utm(e, n)
    cE, cN = play_center_wgs()
    return (E - cE) / STUD_M, -(N - cN) / STUD_M


def local_ing(x: float, z: float) -> tuple[float, float]:
    """Inverso aproximado de ing_local (a grade de 1965 é quase alinhada ao quadro local)."""
    e0, n0, e1, n1 = WORLD_ING
    ce, cn = (e0 + e1) / 2, (n0 + n1) / 2
    return ce + x * STUD_M, cn - z * STUD_M


# ---------- leitura dos dados gerados ----------
def read_grid() -> dict:
    s = (DATA / "Grid.luau").read_text("utf-8")

    def num(key: str) -> float:
        m = re.search(rf"\b{key} = (-?[\d.]+)", s)
        assert m, key
        return float(m.group(1))

    chunks = re.findall(r'"(Heights_\d+)"', re.search(r"heightChunks = \{([^}]*)\}", s).group(1))
    names = re.findall(r'"([^"]+)"', re.search(r"classNames = \{([^}]*)\}", s).group(1))
    rle = base64.b64decode(re.search(r'classesRle = "([^"]*)"', s).group(1))
    w, h = int(num("width")), int(num("height"))
    cls = np.zeros((h, w), dtype=np.uint8)
    i = 0
    for r in range(h):
        c = 0
        while c < w:
            cls[r, c : c + rle[i + 1]] = rle[i]
            c += rle[i + 1]
            i += 2
    heights = np.zeros((h, w), dtype="<u2")
    for name in chunks:
        t = (DATA / f"{name}.luau").read_text("utf-8")
        r0 = int(re.search(r"row0 = (\d+)", t).group(1))
        rows = int(re.search(r"rows = (\d+)", t).group(1))
        raw = base64.b64decode(re.search(r'data = "([^"]*)"', t).group(1))
        heights[r0 : r0 + rows] = np.frombuffer(raw, dtype="<u2").reshape(rows, w)
    carved = re.search(r"\bstreamCarvedCm = (\d+)", s)
    return {
        "w": w,
        "h": h,
        "cell": num("cellStuds"),
        "ox": num("originX"),
        "oz": num("originZ"),
        "hoff": int(num("heightOffsetCm")),
        "names": names,
        "cls": cls,
        "heights": heights,
        "chunks": chunks,
        "carved": int(carved.group(1)) if carved else 0,
    }


def read_features() -> dict[str, np.ndarray]:
    s = (DATA / "Features.luau").read_text("utf-8")
    out = {}
    for key, n in (("dikes", 6), ("hedges", 7), ("waters", 6), ("houses", 4)):
        body = re.search(rf"\b{key} = \{{([^}}]*)\}}", s).group(1)
        vals = np.array([float(v) for v in body.split(",") if v.strip()], dtype=float)
        out[key] = vals.reshape(-1, n)
    return out


# ---------- recorte ----------
def crop_box(m: float = MARGEM_M) -> tuple[float, float, float, float]:
    """Caixa local (xmin, xmax, zmin, zmax) da área jogável mais a margem m (metros)."""
    e0, n0, e1, n1 = PLAY_ING
    pts = [ing_local(e, n) for e in (e0 - m, e1 + m) for n in (n0 - m, n1 + m)]
    xs, zs = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), max(xs), min(zs), max(zs)


def crop_grid(g: dict, box) -> dict:
    xmin, xmax, zmin, zmax = box
    c0 = max(0, math.floor((xmin - g["ox"]) / g["cell"]))
    c1 = min(g["w"], math.ceil((xmax - g["ox"]) / g["cell"]))
    r0 = max(0, math.floor((zmin - g["oz"]) / g["cell"]))
    r1 = min(g["h"], math.ceil((zmax - g["oz"]) / g["cell"]))
    out = dict(g)
    out.update(
        w=c1 - c0,
        h=r1 - r0,
        ox=g["ox"] + c0 * g["cell"],
        oz=g["oz"] + r0 * g["cell"],
        cls=g["cls"][r0:r1, c0:c1].copy(),
        heights=g["heights"][r0:r1, c0:c1].copy(),
    )
    return out


def crop_features(f: dict[str, np.ndarray], box, house_box=None) -> dict[str, np.ndarray]:
    """Diques, sebes e lâminas dentro de box; casas dentro de house_box (sem ele, box)."""

    def inside_of(b):
        xmin, xmax, zmin, zmax = b
        return lambda x, z: (x >= xmin) & (x <= xmax) & (z >= zmin) & (z <= zmax)

    inside = inside_of(box)
    inside_h = inside_of(house_box or box)
    seg = lambda a: inside(a[:, 0], a[:, 1]) & inside(a[:, 2], a[:, 3])  # noqa: E731
    return {
        "dikes": f["dikes"][seg(f["dikes"])],
        "hedges": f["hedges"][seg(f["hedges"])],
        "waters": f["waters"][inside(f["waters"][:, 0], f["waters"][:, 1])],
        "houses": f["houses"][inside_h(f["houses"][:, 0], f["houses"][:, 1])],
    }


# ---------- riacho ----------
def riacho_talvegue(g: dict) -> list[tuple[int, int]]:
    """Células (linha, coluna) do leito: o fundo do vale, do sul para o norte.

    Começa na célula de riacho da carta na linha mais ao sul da faixa (ou no ponto mais baixo dela)
    e escolhe, linha a linha para o norte, o caminho de menor soma de alturas, andando até
    RIACHO_PASSO colunas por linha com um pequeno custo por passo de lado (programação dinâmica:
    o fundo do vale inteiro, não só o mais baixo perto da linha anterior). A coluna é suavizada
    (mediana de 5 linhas) e as linhas vizinhas ficam ligadas por lado (sem passar só pela quina),
    para a água ser contínua.
    """
    cell = g["cell"]
    xs = g["ox"] + (np.arange(g["w"]) + 0.5) * cell
    zs = g["oz"] + (np.arange(g["h"]) + 0.5) * cell
    es = np.array([local_ing(x, 0)[0] for x in xs])
    ns = np.array([local_ing(0, z)[1] for z in zs])
    cols_ok = np.nonzero((es >= RIACHO_E[0]) & (es <= RIACHO_E[1]))[0]
    rows = [r for r in range(g["h"] - 1, -1, -1) if RIACHO_N[0] <= ns[r] <= RIACHO_N[1]]
    if len(cols_ok) == 0 or not rows:
        return []
    c0, c1 = int(cols_ok[0]), int(cols_ok[-1])
    hgt = g["heights"].astype(float)
    r_first = rows[0]
    band = hgt[r_first, c0 : c1 + 1]
    marked = np.nonzero(g["cls"][r_first, c0 : c1 + 1] == 5)[0]
    start = int(marked[0] if len(marked) else np.argmin(band))
    nc = c1 - c0 + 1
    lado_cm = 5.0  # custo de um passo de lado (cm de altura)
    cost = np.full(nc, np.inf)
    cost[start] = hgt[r_first, c0 + start]
    back = []
    for r in rows[1:]:
        new = np.full(nc, np.inf)
        arg = np.zeros(nc, dtype=int)
        for c in range(nc):
            a, b = max(0, c - RIACHO_PASSO), min(nc - 1, c + RIACHO_PASSO)
            prev = cost[a : b + 1] + lado_cm * np.abs(np.arange(a, b + 1) - c)
            j = int(np.argmin(prev))
            new[c] = prev[j] + hgt[r, c0 + c]
            arg[c] = a + j
        back.append(arg)
        cost = new
    col = int(np.argmin(cost))
    cols_path = [col]
    for arg in reversed(back):
        col = int(arg[col])
        cols_path.append(col)
    cols_path.reverse()
    path = [(r, c0 + c) for r, c in zip(rows, cols_path, strict=True)]
    cs = np.array([c for _, c in path], dtype=float)
    k = 2
    smooth = [int(np.median(cs[max(0, i - k) : i + k + 1])) for i in range(len(cs))]
    out: list[tuple[int, int]] = []
    prev = None
    for (r, _), c in zip(path, smooth, strict=True):
        if prev is not None and prev[1] != c:
            step = 1 if c > prev[1] else -1
            for cc in range(prev[1] + step, c, step):
                out.append((prev[0], cc))  # anda de lado na linha anterior até a nova coluna
        out.append((r, c))
        prev = (r, c)
    return out


def abre_riacho(g: dict, f: dict[str, np.ndarray]) -> dict:
    """Marca o leito como riacho, abre o canal e tira as lâminas e diques que cruzam o leito."""
    leito = riacho_talvegue(g)
    info = {"celulas": len(leito), "laminas_fora": 0, "diques_fora": 0}
    if not leito:
        return info
    cell = g["cell"]
    if not g["carved"]:
        canal = int(round(CANAL_M * 100))
        for r, c in leito:
            g["cls"][r, c] = 5
        # o canal vale para todo riacho do recorte (os trechos da carta também), uma vez só
        rr, cc = np.nonzero(g["cls"] == 5)
        g["heights"][rr, cc] = np.maximum(g["heights"][rr, cc].astype(int) - canal, 0).astype("<u2")
        # o fundo nunca sobe rio abaixo (do norte para o sul): o TerrainBuilder põe o espelho a
        # 0,6 m do fundo, e um fundo que sobe faria a água subir e descer degraus
        menor = None
        for r, c in reversed(leito):
            v = int(g["heights"][r, c])
            menor = v if menor is None else min(menor, v)
            g["heights"][r, c] = menor
        g["carved"] = canal
    rc = np.argwhere(g["cls"] == 5)
    centros = np.array([(g["ox"] + (c + 0.5) * cell, g["oz"] + (r + 0.5) * cell) for r, c in rc])
    if len(centros) == 0:
        return info
    meia = cell / 2 + 0.3 / STUD_M

    def perto(x, z, raio):
        return bool(np.any(np.hypot(centros[:, 0] - x, centros[:, 1] - z) < raio))

    w = f["waters"]
    keep_w = []
    for x, z, _y, su, sv, ang in w:
        # retângulo girado da lâmina: centros de riacho dentro dele (com meia célula de folga)
        ca, sa = math.cos(ang), math.sin(ang)
        dx, dz = centros[:, 0] - x, centros[:, 1] - z
        lu = dx * ca - dz * sa
        lv = dx * sa + dz * ca
        hit = np.any((np.abs(lu) <= su / 2 + cell / 2) & (np.abs(lv) <= sv / 2 + cell / 2))
        keep_w.append(not hit)
    keep_w = np.array(keep_w, dtype=bool)
    info["laminas_fora"] = int((~keep_w).sum())
    f["waters"] = w[keep_w]
    d = f["dikes"]
    keep_d = []
    for x1, z1, x2, z2, _t, _b in d:
        n = max(2, int(math.hypot(x2 - x1, z2 - z1) / (cell / 2)) + 1)
        hit = any(perto(x1 + (x2 - x1) * t, z1 + (z2 - z1) * t, meia) for t in np.linspace(0, 1, n))
        keep_d.append(not hit)
    keep_d = np.array(keep_d, dtype=bool)
    info["diques_fora"] = int((~keep_d).sum())
    f["dikes"] = d[keep_d]
    return info


# ---------- escrita ----------
def luau_num(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def luau_list(a: np.ndarray) -> str:
    return "{" + ",".join(luau_num(float(v)) for v in a.ravel()) + "}"


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def write_grid(g: dict) -> None:
    head = HEAD
    chunks = []
    for k, r0 in enumerate(range(0, g["h"], ROWS_PER)):
        part = g["heights"][r0 : r0 + ROWS_PER]
        name = f"Heights_{k:02d}"
        chunks.append(name)
        data = base64.b64encode(part.astype("<u2").tobytes()).decode("ascii")
        write(
            DATA / f"{name}.luau",
            head + f'return {{ row0 = {r0}, rows = {part.shape[0]}, data = "{data}" }}\n',
        )
    for old in DATA.glob("Heights_*.luau"):  # blocos que sobraram do mundo maior
        if old.stem not in chunks:
            old.unlink()
    rle = bytearray()
    for row in g["cls"]:
        j = 0
        while j < len(row):
            c, n = int(row[j]), 1
            while j + n < len(row) and row[j + n] == c and n < 255:
                n += 1
            rle += bytes((c, n))
            j += n
    names = ", ".join(f'"{n}"' for n in g["names"])
    chunk_list = ", ".join(f'"{c}"' for c in chunks)
    write(
        DATA / "Grid.luau",
        head + "return {\n"
        f"\twidth = {g['w']}, height = {g['h']}, cellStuds = {int(g['cell'])},\n"
        f"\toriginX = {g['ox']:.2f}, originZ = {g['oz']:.2f}, -- canto NO (borda da célula)\n"
        f"\theightOffsetCm = {g['hoff']},\n"
        + (
            f"\tstreamCarvedCm = {g['carved']}, -- leito do riacho já aberto (crop_world)\n"
            if g.get("carved")
            else ""
        )
        + f"\theightChunks = {{{chunk_list}}}, rowsPerChunk = {ROWS_PER},\n"
        f"\tclassNames = {{{names}}},\n"
        f'\tclassesRle = "{base64.b64encode(bytes(rle)).decode()}",\n'
        "}\n",
    )


def limpa_base(f: dict[str, np.ndarray]) -> dict:
    """Tira diques, lâminas e sebes a até BASE_M do QG dos EUA (espaço plano para a base)."""
    e, n, _ = QGS["US"]
    bx, bz = ing_local(e, n)
    r = BASE_M / STUD_M
    info = {}
    for key in ("dikes", "hedges"):
        a = f[key]
        mx, mz = (a[:, 0] + a[:, 2]) / 2, (a[:, 1] + a[:, 3]) / 2
        perto = (np.hypot(a[:, 0] - bx, a[:, 1] - bz) < r) | (np.hypot(mx - bx, mz - bz) < r)
        perto |= np.hypot(a[:, 2] - bx, a[:, 3] - bz) < r
        info[key] = int(perto.sum())
        f[key] = a[~perto]
    w = f["waters"]
    perto = np.hypot(w[:, 0] - bx, w[:, 1] - bz) < r
    info["waters"] = int(perto.sum())
    f["waters"] = w[~perto]
    return info


def write_features(f: dict[str, np.ndarray]) -> None:
    write(
        DATA / "Features.luau",
        HEAD + "-- Listas planas (studs, radianos):\n"
        "--  dikes  : x1,z1,x2,z2,yTop,yBase\n"
        "--  hedges : x1,z1,x2,z2,yBase,altura,espessura\n"
        "--  waters : x,z,yNivel,tamU,tamV,angulo\n"
        "--  houses : x,z,yChao,angulo\n"
        "return {\n"
        f"\tdikes = {luau_list(f['dikes'])},\n"
        f"\thedges = {luau_list(f['hedges'])},\n"
        f"\twaters = {luau_list(f['waters'])},\n"
        f"\thouses = {luau_list(f['houses'])},\n"
        "}\n",
    )


def write_mapconfig(box) -> None:
    e0, n0, e1, n1 = PLAY_ING
    we0, wn0, we1, wn1 = WORLD_ING
    em, nm = (e0 + e1) / 2, (n0 + n1) / 2

    # Setores e limites são retilíneos no quadro local (a carta do jogo pinta retângulos): cada E da
    # grade vira um X só (medido no meio da área) e cada N um Z só. O giro entre a grade de 1965 e
    # o quadro local é de décimos de stud em 1 km, mas sem isto a mesma fronteira saía com dois X.
    def snap(e: float, n: float) -> tuple[float, float]:
        return round(ing_local(e, nm)[0], 1), round(ing_local(em, n)[1], 1)

    xa, za = snap(e0, n1)  # NO
    xb, zb = snap(e1, n0)  # SE

    def poly(pts):  # lista plana x1, z1, x2, z2, ... (o módulo roda também no Lune)
        return "{" + ", ".join(f"{x:.1f}, {z:.1f}" for x, z in pts) + "}"

    lines = [[(e0, n0), (e0, n1)]] + FRONTEIRAS_ING + [[(e1, n0), (e1, n1)]]
    sec_txt = []
    for k in range(5):
        ring = [snap(*p) for p in lines[k]] + [snap(*p) for p in lines[k + 1]][::-1]
        sec_txt.append(f'\t\t{{ id = {k + 1}, name = "{SETORES[k]}", polygon = {poly(ring)} }},')
    sp_txt = []
    for s, nome, e, n, real, obs in PONTOS_FORTES:
        x, z = ing_local(e, n)
        sp_txt.append(
            f'\t\t{{ sector = {s}, name = "{nome}", x = {x:.1f}, z = {z:.1f}, '
            f'real = {str(real).lower()}, note = "{obs}" }},'
        )
    qg_txt = []
    for fac, (e, n, obs) in QGS.items():
        x, z = ing_local(e, n)
        qg_txt.append(f'\t\t{fac} = {{ x = {x:.1f}, z = {z:.1f}, note = "{obs}" }},')
    xmin, xmax, zmin, zmax = box
    with open(ROOT / "research/locais.csv", encoding="utf-8") as fh:
        locs = [
            r
            for r in csv.DictReader(fh)
            if xmin <= float(r["x_studs"]) <= xmax and zmin <= float(r["z_studs"]) <= zmax
        ]
    lado_km = (e1 - e0) / 1000, (n1 - n0) / 1000
    loc_txt = [
        f'\t\t{{ name = "{r["nome"]}", grid = "{r["grade_1965"]}", x = {float(r["x_studs"]):.1f}, '
        f"z = {float(r['z_studs']):.1f}, e1965 = {r['E_ing']}, n1965 = {r['N_ing']} }},"
        for r in locs
    ]
    write(
        SHARED / "MapConfig.luau",
        "--!strict\n-- GERADO por tools/crop_world.py. Não editar.\n"
        "-- Coordenadas em studs no quadro local: X = leste, Z = sul. A origem é o centro do\n"
        "-- mundo gerado (4 x 2,4 km, D-03), não o da área jogável "
        f"({lado_km[0]:g} x {lado_km[1]:g} km, E {e0 / 1000:g}–{e1 / 1000:g} x "
        f"N {n0 / 1000:g}–{n1 / 1000:g} km na grade de 1965).\n"
        "local MapConfig = {}\n\n"
        f"MapConfig.STUD_M = {STUD_M}\n"
        f"MapConfig.Bounds = {{ minX = {xa:.1f}, maxX = {xb:.1f}, "
        f"minZ = {za:.1f}, maxZ = {zb:.1f} }}\n"
        "-- grade de 1965 (ING-A) da origem local: E = gridE0 + x*0,28 ; N = gridN0 - z*0,28\n"
        f"MapConfig.GridOrigin1965 = {{ e = {(we0 + we1) / 2:.1f}, n = {(wn0 + wn1) / 2:.1f} }}\n"
        "MapConfig.OutOfBoundsKillSeconds = 10\n"
        "MapConfig.CaptureRadiusStuds = 50 / 0.28 -- 50 m (prompt: 40-60 m)\n"
        "MapConfig.Sectors = {\n" + "\n".join(sec_txt) + "\n}\n"
        "MapConfig.Strongpoints = {\n" + "\n".join(sp_txt) + "\n}\n"
        "MapConfig.HQ = {\n" + "\n".join(qg_txt) + "\n}\n"
        "MapConfig.Locations = {\n" + "\n".join(loc_txt) + "\n}\n"
        "-- EUA começam com S4-S5, VC com S1-S2, S3 neutro (prompt, Parte 3)\n"
        'MapConfig.InitialOwner = { "VC", "VC", "Neutral", "US", "US" }\n\n'
        "return MapConfig\n",
    )


def write_fixture(box) -> int:
    xmin, xmax, zmin, zmax = box
    fx = json.loads(FIXTURE.read_text("utf-8"))
    keep = [p for p in fx if xmin <= p["x"] <= xmax and zmin <= p["z"] <= zmax]
    FIXTURE.write_text(json.dumps(keep, ensure_ascii=False, indent=1), encoding="utf-8")
    return len(keep)


# ---------- análise ----------
def analisar(g: dict, f: dict[str, np.ndarray]) -> None:
    """Casas da carta e manchas de vila/mata por faixa de setor, com aglomerados de casas."""
    bounds = [PLAY_ING[0]] + [b[0][0] for b in FRONTEIRAS_ING] + [PLAY_ING[2]]
    houses = [local_ing(x, z) for x, z in f["houses"][:, :2]]
    vila = g["names"].index("vila_mata")
    rr, cc = np.nonzero(g["cls"] == vila)
    vx = g["ox"] + (cc + 0.5) * g["cell"]
    vz = g["oz"] + (rr + 0.5) * g["cell"]
    vil = [local_ing(x, z) for x, z in zip(vx, vz, strict=True)]
    for k in range(5):
        a, b = bounds[k], bounds[k + 1]
        hs = [(e, n) for e, n in houses if a <= e < b and PLAY_ING[1] <= n <= PLAY_ING[3]]
        vs = [(e, n) for e, n in vil if a <= e < b and PLAY_ING[1] <= n <= PLAY_ING[3]]
        print(f"{SETORES[k]} (E {a:.0f}–{b:.0f}): {len(hs)} casas, {len(vs)} células de vila/mata")
        # aglomerados: casas a menos de 120 m umas das outras
        left = list(hs)
        while left:
            seed = left.pop()
            grp = [seed]
            changed = True
            while changed:
                changed = False
                for p in list(left):
                    if any(math.dist(p, q) < 120 for q in grp):
                        grp.append(p)
                        left.remove(p)
                        changed = True
            if len(grp) >= 3:
                ce = sum(p[0] for p in grp) / len(grp)
                cn = sum(p[1] for p in grp) / len(grp)
                print(f"   aglomerado de {len(grp)} casas em E {ce:.0f}, N {cn:.0f}")


def main() -> None:
    box = crop_box()
    g = read_grid()
    f = read_features()
    if "--analisar" in sys.argv:
        analisar(g, f)
        return
    gc = crop_grid(g, box)
    fc = crop_features(f, crop_box(FEICOES_M), crop_box(0.0))
    riacho = abre_riacho(gc, fc)
    base = limpa_base(fc)
    write_grid(gc)
    write_features(fc)
    write_mapconfig(crop_box(LOCAIS_TOL_M))
    n_fx = write_fixture(box)
    print(
        json.dumps(
            {
                "grade_antes": [g["w"], g["h"]],
                "grade_depois": [gc["w"], gc["h"]],
                **{k: [len(f[k]), len(fc[k])] for k in f},
                "riacho": riacho,
                "base_eua_sem": base,
                "pontos_do_fixture": n_fx,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
