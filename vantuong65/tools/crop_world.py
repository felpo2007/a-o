"""Recorta o mundo gerado (4 x 2,4 km, D-03) para a área jogável (geo.PLAY_ING).

Recortes: 2 x 2 km (D-63); a pedido do dono em 2026-11-11, 1 x 1 km de Nam Yên (4) até o vale
do riacho a leste de An Cường (2), com a Colina 30 ao norte; em 2026-11-13 (D-114), 500 x 500 m de
Xóm Gò, no morro do centro, até An Cường (2) com os túneis.

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

# Fronteiras de setor, polilinhas sul -> norte em ING-A. D-123 (mapa de 700 x 700 m; pedido do
# dono: "as bases bem na ponta central de cada lado do mapa e os objetivos bem distribuídos, um bem
# no centro numa vila maior, outro numa floresta densa e pouco acessível e o outro à sua
# escolha"): três faixas do QG do VC (meio da borda oeste) ao dos EUA (meio da borda leste):
#  - S1 (270 m): a base do VC e a mata fechada a oeste do morro;
#  - S2 (170 m): a vila de Xóm Gò inteira, no morro do centro;
#  - S3 (260 m): a encosta leste, An Cường (2) com os túneis e a base dos EUA.
FRONTEIRAS_ING = [
    [(269750, 1692580), (269750, 1693280)],
    [(269920, 1692580), (269920, 1693280)],
]
# letra do setor no jogo (v41, pedido do dono: "troque os objetivos por A B C D E"; Front.letra)
SETORES = [
    "A Mata fechada",
    "B Xóm Gò",
    "C An Cường (2)",
]
SETOR_VILA = 2  # setor da vila de Xóm Gò (era o 3 no mapa de 1 km)
INICIAL = ["VC", "Neutral", "US"]  # dono de cada setor no começo (D-123: o do meio é neutro)
SEM_ESTRADA = {"Mata fechada", "Picada na mata"}  # pontos da mata fechada: sem estrada até eles
# Vila grande do centro (2026-11-12, tools/vila_estradas.py): o ponto forte fica na praça, que o
# planejamento da vila escolhe no flanco leste do morrote (E e N saem de lá, por isso None aqui)
VILA_PF = (
    SETOR_VILA,
    "Xóm Gò",
    None,
    None,
    False,
    "vila grande de design no morrote do centro (40 a 60 casas); nome de design",
)
VILA_BECOS = (
    SETOR_VILA,
    "Becos de Xóm Gò",
    None,
    None,
    False,
    "travessa e becos da vila de design (a ~56 m da praça); nome de design",
)
# D-114: a outra travessa, do lado oposto ao centro do mapa
VILA_PONTA = (
    SETOR_VILA,
    "Ponta norte de Xóm Gò",
    None,
    None,
    False,
    "travessa da vila de design do lado do pagode (a ~56 m da praça); nome de design",
)
# Pontos fortes: (setor, nome, E, N, real?, observação). Cada partida sorteia um por setor.
# D-123: três objetivos (resposta do dono): a mata fechada (S1), a vila grande do centro (S2) e An
# Cường (2) com os túneis (S3, a escolha: a vila fortificada da batalha de verdade).
PONTOS_FORTES = [
    # S1: mata fechada entre a base do VC e o morro, longe das casas e das estradas
    (1, "Mata fechada", 269650, 1693000, False, "mata cerrada a noroeste do morro; nome de design"),
    (1, "Picada na mata", 269625, 1692790, False, "trilha na mata a sudoeste; nome de design"),
    # S2: a vila de Xóm Gò (praça e as duas travessas)
    VILA_PF,
    VILA_BECOS,
    VILA_PONTA,
    # S3: An Cường (2)
    (3, "An Cường (2)", 269985, 1692870, True, "vila fortificada (First Fight p.25)"),
    (
        3,
        "Sebe ao norte de An Cường (2)",
        269985,
        1692975,
        False,
        "sebe junto da boca E4 do túnel; nome de design",
    ),
    (
        3,
        "Arrozal ao sul de An Cường (2)",
        269990,
        1692780,
        False,
        "arrozal ao sul da vila; nome de design",
    ),
]
# Base dos EUA (pedido do dono: "o QG dos EUA vai virar uma base grande depois; deixe espaço
# plano"): sem diques, lâminas d'água e sebes a até BASE_M do QG. D-114: a base (90 x 122 m) cabe
# num raio de 77 m; eram 140 m no mapa de 1 km, que no de 500 m limpariam An Cường (2).
BASE_M = 80.0
QGS = {
    # D-123: no meio da borda leste (50 m para dentro: a base vai 43 m a leste do QG), a leste de
    # An Cường (2) e a oeste do riacho
    "US": (270130, 1692930, "meio da borda leste, a leste de An Cường (2) (setor S3)"),
    # D-123: no meio da borda oeste (50 m para dentro)
    "VC": (269530, 1692930, "meio da borda oeste, retaguarda do VC (setor S1)"),
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
    moved = re.search(r"\bmoundMoved = (\d+)", s)
    cut = re.search(r"\bpaddyCut = (\d+)", s)
    ham = re.search(r"\bhamletAdded = (\d+)", s)
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
        "moved": int(moved.group(1)) if moved else 0,
        "paddyCut": int(cut.group(1)) if cut else 0,
        "hamletAdded": int(ham.group(1)) if ham else 0,
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
        + (
            "\tmoundMoved = 1, -- morrote levado para perto do centro (crop_world)\n"
            if g.get("moved")
            else ""
        )
        + ("\tpaddyCut = 1, -- arrozal reduzido a 25% (crop_world)\n" if g.get("paddyCut") else "")
        + (
            "\thamletAdded = 1, -- casario de An Cường (2) acrescentado (crop_world, D-115)\n"
            if g.get("hamletAdded")
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
    for k in range(len(SETORES)):
        ring = [snap(*p) for p in lines[k]] + [snap(*p) for p in lines[k + 1]][::-1]
        sec_txt.append(f'\t\t{{ id = {k + 1}, name = "{SETORES[k]}", polygon = {poly(ring)} }},')
    sp_txt = []
    for s, nome, e, n, real, obs in PONTOS_FORTES:
        # vila do centro: E/N None e a praça (studs) em VILA_XZ, escolhida pelo vila_estradas
        x, z = VILA_XZ[nome] if e is None else ing_local(e, n)
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
        "MapConfig.CaptureRadiusStuds = 35 / 0.28 "
        "-- 35 m (D-114: setores de ~100 m; o prompt pedia 40-60 m)\n"
        "MapConfig.Sectors = {\n" + "\n".join(sec_txt) + "\n}\n"
        "MapConfig.Strongpoints = {\n" + "\n".join(sp_txt) + "\n}\n"
        "MapConfig.HQ = {\n" + "\n".join(qg_txt) + "\n}\n"
        "MapConfig.Locations = {\n" + "\n".join(loc_txt) + "\n}\n"
        "-- D-123: o VC começa com o S1, os EUA com o último, o do meio neutro\n"
        "MapConfig.InitialOwner = { " + ", ".join(f'"{o}"' for o in INICIAL) + " }\n\n"
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


VILA_XZ: dict[str, tuple[float, float]] = {}

# ---------- morro e arrozal (pedido do dono, 2026-11-12) ----------
# "transfira a montanha para mais perto do centro do mapa, sem atrapalhar a locomoção": o morrote
# de 34 m (cume em MORRO_DE, D-95) vai para MORRO_PARA, a ~40 m do centro do mapa (E 269,85 /
# N 1693,0). DEFORMAÇÃO do terreno real, decisão de jogabilidade: o relevo do morro (o que passa do
# plano do anel em volta) sai de onde estava e entra no lugar novo, com o uso do solo dele (capim).
# As feições (lâmina, dique, sebe) que ficam no morro novo saem. Feito uma vez: o Grid guarda
# moundMoved.
MORRO_DE = (269741.0, 1692964.0)
MORRO_PARA = (269815.0, 1692990.0)
MORRO_R = 170.0  # m: raio do morro (o capim dele vai de ~E 269,63 a 269,89)
MORRO_NUCLEO = 0.55  # fração do raio com o morro inteiro; daí até o raio, transição suave
# "diminua 75% das plantações de arroz": ficam os tabuleiros mais perto das casas e do riacho
ARROZ_FRACAO = 0.25
# Tabuleiro em ladeira sai (achado na varredura de 2026-11-12: com o fundo plano de cada tabuleiro,
# dois vizinhos ficavam até 1,6 m um acima do outro e a borda até 3 m acima ou abaixo do chão em
# volta, paredões de terra). Fica o de chão quase plano, e dois vizinhos não passam de um degrau
# que a lombada do dique cobre.
ARROZ_DESNIVEL_M = 0.8  # desnível máximo do chão sob a lâmina (5 x 5 pontos)
ARROZ_DEGRAU_M = 0.35  # diferença máxima de fundo entre dois tabuleiros que se encostam


def _peso(d: np.ndarray, r: float) -> np.ndarray:
    """1 até MORRO_NUCLEO*r, 0 a partir de r, suave no meio"""
    t = np.clip((d - MORRO_NUCLEO * r) / ((1 - MORRO_NUCLEO) * r), 0, 1)
    return 1 - t * t * (3 - 2 * t)


def move_morro(g: dict, f: dict[str, np.ndarray]) -> dict:
    if g.get("moved"):
        return {"movido": False}
    cell = g["cell"]
    h = (g["heights"].astype(float) - g["hoff"]) / 100.0
    rows, cols = np.indices(h.shape)
    xs = g["ox"] + (cols + 0.5) * cell
    zs = g["oz"] + (rows + 0.5) * cell
    ox, oz = ing_local(*MORRO_DE)
    nx, nz = ing_local(*MORRO_PARA)
    dx, dz = nx - ox, nz - oz
    r = MORRO_R / STUD_M
    d_old = np.hypot(xs - ox, zs - oz)
    # plano do anel em volta do morro (tira a inclinação geral do terreno)
    anel = (d_old > r) & (d_old < r + 40 / STUD_M)
    A = np.column_stack([xs[anel], zs[anel], np.ones(anel.sum())])
    coef, *_ = np.linalg.lstsq(A, h[anel], rcond=None)
    plano = coef[0] * xs + coef[1] * zs + coef[2]
    bump = np.clip(h - plano, 0, None)
    w_old = _peso(d_old, r)
    h0 = h - w_old * bump
    # o morro no lugar novo: amostra do relevo original deslocada (vizinho mais perto: a grade é a
    # mesma, o deslocamento sai em células inteiras)
    sc, sr = round(dx / cell), round(dz / cell)
    src_r = np.clip(rows - sr, 0, h.shape[0] - 1)
    src_c = np.clip(cols - sc, 0, h.shape[1] - 1)
    d_new = np.hypot(xs - (ox + sc * cell), zs - (oz + sr * cell))
    w_new = _peso(d_new, r)
    novo = h0 + w_new * bump[src_r, src_c]
    cls = g["cls"]
    leva = w_new > 0.5
    novo_cls = cls.copy()
    novo_cls[leva] = cls[src_r[leva], src_c[leva]]
    # riacho e casas não entram no morro (nenhum no raio; conferido)
    novo_cls[cls == 5] = 5
    g["heights"] = np.clip(np.round(novo * 100 + g["hoff"]), 0, 65535).astype("<u2")
    g["cls"] = novo_cls
    g["moved"] = 1
    # feições no morro novo saem
    lim = 0.3

    def fora(x, z):
        return (
            _peso(np.hypot(np.asarray(x) - (ox + sc * cell), np.asarray(z) - (oz + sr * cell)), r)
            < lim
        )

    info = {
        "movido": True,
        "deslocamento_m": [round(sc * cell * STUD_M, 1), round(-sr * cell * STUD_M, 1)],
    }
    for key in ("dikes", "hedges"):
        a = f[key]
        m = fora((a[:, 0] + a[:, 2]) / 2, (a[:, 1] + a[:, 3]) / 2)
        info[f"{key}_no_morro"] = int((~m).sum())
        f[key] = a[m]
    w = f["waters"]
    m = fora(w[:, 0], w[:, 1])
    info["waters_no_morro"] = int((~m).sum())
    f["waters"] = w[m]
    gy, gx = np.gradient(novo, cell * STUD_M)
    info["rampa_max_no_morro"] = round(float(np.hypot(gx, gy)[w_new > 0.05].max()), 3)
    info["cume_m"] = round(float(novo[w_new > 0.5].max()), 1)
    return info


def _fundo_e_desnivel(g: dict, w: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """fundo (m) de cada tabuleiro como o TerrainBuilder.paddySet (mediana de 9 pontos) e o desnível
    do chão sob a lâmina (5 x 5 pontos)"""
    import vila_estradas

    t = vila_estradas.Terreno(g)
    nove = [
        (0, 0),
        (0.35, 0),
        (-0.35, 0),
        (0, 0.35),
        (0, -0.35),
        (0.35, 0.35),
        (-0.35, -0.35),
        (0.35, -0.35),
        (-0.35, 0.35),
    ]
    grade = [(a, b) for a in np.linspace(-0.5, 0.5, 5) for b in np.linspace(-0.5, 0.5, 5)]
    fundo, desnivel = np.zeros(len(w)), np.zeros(len(w))
    for i, (x, z, _y, su, sv, ang) in enumerate(w):
        ca, sa = math.cos(ang), math.sin(ang)

        def pts(offs, x=x, z=z, su=su, sv=sv, ca=ca, sa=sa):
            lu = np.array([o[0] for o in offs]) * su
            lv = np.array([o[1] for o in offs]) * sv
            return x + lu * ca + lv * sa, z - lu * sa + lv * ca

        fundo[i] = np.sort(t.altura(*pts(nove)))[4]
        h = t.altura(*pts(grade))
        desnivel[i] = h.max() - h.min()
    return fundo, desnivel


def _vizinhos(w: np.ndarray) -> list[tuple[int, int]]:
    """pares de tabuleiros que se encostam (o meio entre os centros cai nos dois, folga de 2 m)"""
    pares = []
    folga = 2.0 / STUD_M

    def cobre(r, x, z):
        ca, sa = math.cos(r[5]), math.sin(r[5])
        dx, dz = x - r[0], z - r[1]
        return (
            abs(dx * ca - dz * sa) <= r[3] / 2 + folga
            and abs(dx * sa + dz * ca) <= r[4] / 2 + folga
        )

    for i in range(len(w)):
        for j in range(i + 1, len(w)):
            a, b = w[i], w[j]
            if (
                math.hypot(a[0] - b[0], a[1] - b[1])
                > (math.hypot(a[3], a[4]) + math.hypot(b[3], b[4])) / 2 + folga
            ):
                continue
            mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            if cobre(a, mx, mz) and cobre(b, mx, mz):
                pares.append((i, j))
    return pares


def reduz_arrozal(g: dict, f: dict[str, np.ndarray], casas_xz: np.ndarray) -> dict:
    """fica ARROZ_FRACAO dos tabuleiros, os mais perto das casas e do riacho, só em chão quase plano
    (ARROZ_DESNIVEL_M) e sem degrau maior que ARROZ_DEGRAU_M entre dois que se encostam; os diques
    que não encostam num tabuleiro que ficou saem; as sebes baixas longe dele também"""
    w = f["waters"]
    if len(w) == 0:
        return {}
    cell = g["cell"]
    rr, cc = np.nonzero(g["cls"] == 5)
    rio = np.column_stack([g["ox"] + (cc + 0.5) * cell, g["oz"] + (rr + 0.5) * cell])
    nota = []
    for x, z, *_ in w:
        dc = np.hypot(casas_xz[:, 0] - x, casas_xz[:, 1] - z).min() if len(casas_xz) else 1e9
        dr = np.hypot(rio[:, 0] - x, rio[:, 1] - z).min() if len(rio) else 1e9
        nota.append(min(dc, dr))
    nota = np.array(nota)
    n = max(1, int(round(len(w) * ARROZ_FRACAO)))
    if g.get("paddyCut"):
        n = len(w)  # já reduzido: rodar de novo não tira mais nada
    fundo, desnivel = _fundo_e_desnivel(g, w)
    plano = desnivel <= ARROZ_DESNIVEL_M
    ordem = [i for i in np.argsort(nota, kind="stable") if plano[i]]
    fica = np.zeros(len(w), bool)
    fica[ordem[:n]] = True
    # degrau entre vizinhos: sai o de chão mais inclinado até nenhum par passar do limite
    idx = np.nonzero(fica)[0]
    pares = [(idx[a], idx[b]) for a, b in _vizinhos(w[idx])]
    degrau = 0
    while True:
        ruins = [
            (i, j)
            for i, j in pares
            if fica[i] and fica[j] and abs(fundo[i] - fundo[j]) > ARROZ_DEGRAU_M
        ]
        if not ruins:
            break
        i, j = max(ruins, key=lambda p: abs(fundo[p[0]] - fundo[p[1]]))
        fica[i if desnivel[i] >= desnivel[j] else j] = False
        degrau += 1
    kept = w[fica]
    info = {
        "laminas_antes": int(len(w)),
        "laminas_em_ladeira": int((~plano).sum()),
        "laminas_por_degrau": degrau,
        "laminas_ficam": int(fica.sum()),
    }
    f["waters"] = kept

    def perto(x, z, folga):
        for kx, kz, _y, su, sv, ang in kept:
            ca, sa = math.cos(ang), math.sin(ang)
            ddx, ddz = x - kx, z - kz
            lu = ddx * ca - ddz * sa
            lv = ddx * sa + ddz * ca
            if abs(lu) <= su / 2 + folga and abs(lv) <= sv / 2 + folga:
                return True
        return False

    d = f["dikes"]
    m = np.array([perto((r_[0] + r_[2]) / 2, (r_[1] + r_[3]) / 2, 2.5 / STUD_M) for r_ in d], bool)
    info["diques_antes"], info["diques_ficam"] = int(len(d)), int(m.sum())
    f["dikes"] = d[m]
    hg = f["hedges"]
    alta = hg[:, 5] > 3 / STUD_M
    m = np.array(
        [
            alta[i] or perto((r_[0] + r_[2]) / 2, (r_[1] + r_[3]) / 2, 12 / STUD_M)
            for i, r_ in enumerate(hg)
        ],
        bool,
    )
    info["sebes_antes"], info["sebes_ficam"] = int(len(hg)), int(m.sum())
    f["hedges"] = hg[m]
    g["paddyCut"] = 1
    return info


def _poligono_setor(k: int) -> list[tuple[float, float]]:
    """anel do setor k (0..4) em studs, igual ao do MapConfig"""
    e0, n0, e1, n1 = PLAY_ING
    linhas = [[(e0, n0), (e0, n1)]] + FRONTEIRAS_ING + [[(e1, n0), (e1, n1)]]
    return [ing_local(*p) for p in linhas[k]] + [ing_local(*p) for p in linhas[k + 1]][::-1]


def _dentro(poly: list[tuple[float, float]], x: float, z: float) -> bool:
    dentro = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
            dentro = not dentro
        j = i
    return dentro


# ---------- casario de An Cường (2) (D-115) ----------
# Pedido do dono: "aumente as cabanas de todo jogo e o tamanho das vilas". No recorte de 500 m An
# Cường (2) tinha só as 5 casas da carta. Ganha um casario de design em volta da vila, como os
# xóm do litoral de Quảng Ngãi: casas soltas a ~20 m umas das outras, viradas para o sul ou para o
# norte (com folga de giro), fora das bocas de túnel e da trincheira (Shared/Tunnels, a partir do
# local da carta), da base dos EUA, do mastro dos pontos fortes, do riacho e de chão inclinado.
# Determinístico; feito uma vez (o Grid guarda hamletAdded). PLACEHOLDER de design.
CASARIO_CENTRO = (269995.0, 1692860.0)  # entre o ponto forte e o local da carta (E 270,030)
CASARIO_RAIO_M = 85.0
CASARIO_PASSO_M = 21.0
CASARIO_DIST_M = 20.0  # entre duas casas (centro a centro)
CASARIO_MAX = 18
CASARIO_DESNIVEL_M = 1.6  # sob a pegada de 10 x 10 m
CASARIO_FOLGA_M = {"tunel": 12.0, "trincheira": 12.0, "base": 15.0, "ponto": 12.0, "borda": 30.0}


def _tuneis_ing() -> tuple[list, list]:
    """bocas e trincheira de Shared/Tunnels.luau em studs do mundo (centro = local da carta)"""
    s = (SHARED / "Tunnels.luau").read_text("utf-8")
    with open(ROOT / "research/locais.csv", encoding="utf-8") as fh:
        loc = next(r for r in csv.DictReader(fh) if r["nome"] == "An Cường (2)")
    cx, cz = float(loc["x_studs"]), float(loc["z_studs"])
    bocas = [
        (cx + float(x) / STUD_M, cz + float(z) / STUD_M)
        for x, z in re.findall(r"E\d = \{ x = (-?[\d.]+), z = (-?[\d.]+), entrance = true", s)
    ]
    corpo = re.search(r"Tunnels\.trench = \{(.*)\}\n", s).group(1)
    vala = [
        (cx + float(x) / STUD_M, cz + float(z) / STUD_M)
        for x, z in re.findall(r"\{ (-?[\d.]+), (-?[\d.]+) \}", corpo)
    ]
    return bocas, vala


def casario_an_cuong(g: dict, f: dict[str, np.ndarray]) -> dict:
    if g.get("hamletAdded"):
        return {"acrescentadas": 0, "ja_feito": True}
    import vila_estradas

    t = vila_estradas.Terreno(g)
    bocas, vala = _tuneis_ing()
    base = json.loads((Path(__file__).resolve().parent / "bases_mapa.json").read_text("utf-8"))
    hx, hz = ing_local(*QGS["US"][:2])
    bx0, bx1, bz0, bz1 = base["US"]["area_studs"]
    fb = CASARIO_FOLGA_M["base"] / STUD_M
    caixa_base = (hx + bx0 - fb, hx + bx1 + fb, hz + bz0 - fb, hz + bz1 + fb)
    pontos = [ing_local(e, n) for _s, _nm, e, n, _r, _o in PONTOS_FORTES if e is not None]
    xa, xb, za, zb = crop_box(-CASARIO_FOLGA_M["borda"])
    cx, cz = ing_local(*CASARIO_CENTRO)
    casas = [tuple(p) for p in f["houses"][:, :2]]
    rng = np.random.default_rng(1965)
    passo = CASARIO_PASSO_M / STUD_M
    n = int(CASARIO_RAIO_M // CASARIO_PASSO_M)
    cands = []
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            # grade em ziguezague (linhas alternadas meio passo), com jitter de 4 m
            x = cx + (i + (0.5 if j % 2 else 0.0)) * passo + rng.uniform(-4, 4) / STUD_M
            z = cz + j * passo * 0.87 + rng.uniform(-4, 4) / STUD_M
            d = math.hypot(x - cx, z - cz) * STUD_M
            if d <= CASARIO_RAIO_M:
                cands.append((d, x, z))
    cands.sort()

    def longe(x, z, pts, m):
        return all(math.hypot(x - px, z - pz) * STUD_M >= m for px, pz in pts)

    def longe_vala(x, z, m):
        for (ax, az), (bx, bz) in zip(vala, vala[1:], strict=False):
            dx, dz = bx - ax, bz - az
            tt = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
            if math.hypot(ax + tt * dx - x, az + tt * dz - z) * STUD_M < m:
                return False
        return True

    novas = []
    motivos = {}
    for _d, x, z in cands:
        if len(novas) >= CASARIO_MAX:
            break
        motivo = None
        if not (xa <= x <= xb and za <= z <= zb):
            motivo = "borda"
        elif caixa_base[0] <= x <= caixa_base[1] and caixa_base[2] <= z <= caixa_base[3]:
            motivo = "base"
        elif not longe(x, z, bocas, CASARIO_FOLGA_M["tunel"]):
            motivo = "tunel"
        elif not longe_vala(x, z, CASARIO_FOLGA_M["trincheira"]):
            motivo = "trincheira"
        elif not longe(x, z, pontos, CASARIO_FOLGA_M["ponto"]):
            motivo = "ponto"
        elif not longe(x, z, casas, CASARIO_DIST_M):
            motivo = "casa"
        else:
            p = vila_estradas.pegada(x, z, 0.0, 10.0, 10.0)
            h = t.altura(p[:, 0], p[:, 1])
            if (t.classe(p[:, 0], p[:, 1]) == 5).any():
                motivo = "riacho"
            elif float(h.max() - h.min()) > CASARIO_DESNIVEL_M:
                motivo = "ladeira"
        if motivo:
            motivos[motivo] = motivos.get(motivo, 0) + 1
            continue
        # de frente para o sul ou para o norte, com até 15° de folga
        giro = (0.0 if rng.random() < 0.6 else math.pi) + math.radians(rng.uniform(-15, 15))
        y = float(t.altura(np.array([x]), np.array([z]))[0]) / STUD_M
        novas.append((x, z, y, giro))
        casas.append((x, z))
    if novas:
        f["houses"] = np.vstack([f["houses"], np.array(novas, float)])
    g["hamletAdded"] = 1
    return {"acrescentadas": len(novas), "recusadas": motivos}


def vila_e_estradas(g: dict, f: dict) -> dict:
    """vila grande no setor SETOR_VILA e estradas entre os QGs e os pontos fortes
    (tools/vila_estradas.py)"""
    import vila_estradas

    s3 = _poligono_setor(SETOR_VILA - 1)
    # D-115: meio lote mais 1 m (lotes 30% maiores; eram 12 m fixos para o lote de 14 m)
    margem = (vila_estradas.LOTE_D / 2 + 1.0) / STUD_M

    def setor3(x: float, z: float) -> bool:
        # o lote inteiro no setor: o centro e quatro pontos a 12 m
        return all(
            _dentro(s3, x + dx, z + dz)
            for dx, dz in ((0, 0), (margem, 0), (-margem, 0), (0, margem), (0, -margem))
        )

    nos = {"QG_US": QGS["US"][:2], "QG_VC": QGS["VC"][:2]}
    for _s, nome, e, n, _real, _obs in PONTOS_FORTES:
        # D-123: a mata fechada fica sem estrada (o dono pediu "pouco acessível")
        if e is not None and nome not in SEM_ESTRADA:
            nos[nome] = (e, n)

    def arrozal(vila: dict) -> dict:
        casas = [tuple(p) for p in f["houses"][:, :2]] + [(c["x"], c["z"]) for c in vila["casas"]]
        return {"arrozal": reduz_arrozal(g, f, np.array(casas, float))}

    # bases dos dois lados (tools/bases_dados.py, layouts do Blender): a estrada do mapa chega à
    # entrada de cada base e não entra nela; a via da base entra no Roads
    bases = []
    arq = Path(__file__).resolve().parent / "bases_mapa.json"
    if arq.is_file():
        for fac, b in json.loads(arq.read_text("utf-8")).items():
            hx, hz = ing_local(*QGS[fac][:2])
            x0, x1, z0, z1 = b["area_studs"]
            via = b["via"]
            bases.append(
                {
                    "no": f"QG_{fac}",
                    "entrada": (hx + b["entrada_studs"][0], hz + b["entrada_studs"][1]),
                    "area": (hx + x0, hx + x1, hz + z0, hz + z1),
                    "via": {
                        "kind": via["kind"],
                        "a": (hx + via["a"][0], hz + via["a"][1]),
                        "b": (hx + via["b"][0], hz + via["b"][1]),
                    },
                }
            )
    info, vila = vila_estradas.aplica(g, f, ing_local, nos, setor3, PLAY_ING, HEAD, arrozal, bases)
    VILA_XZ[VILA_PF[1]] = (vila["x"], vila["z"])
    # segundo ponto da vila: o cruzamento da rua com a travessa mais perto do centro do mapa (luta
    # nos becos, longe o bastante da praça para ser outro objetivo)
    cx, cz = ing_local((PLAY_ING[0] + PLAY_ING[2]) / 2, (PLAY_ING[1] + PLAY_ING[3]) / 2)
    pts = []
    for u in vila_estradas.TRAVESSAS:
        dx, dz = vila_estradas.gira(u, 0.0, vila["ang"])
        pts.append((vila["x"] + dx, vila["z"] + dz))
    pts.sort(key=lambda p: math.hypot(p[0] - cx, p[1] - cz))
    VILA_XZ[VILA_BECOS[1]] = pts[0]
    # D-114: a outra travessa vira o terceiro ponto da vila (o "norte" do nome vem conferido aqui)
    VILA_XZ[VILA_PONTA[1]] = pts[-1]
    assert pts[-1][1] < pts[0][1], "a ponta da vila longe do centro devia ficar ao norte (z menor)"
    return info


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
    morro = move_morro(gc, fc)
    casario = casario_an_cuong(gc, fc)
    vila_info = vila_e_estradas(gc, fc)
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
                "morro": morro,
                "casario_an_cuong": casario,
                "vila_e_estradas": vila_info,
                "pontos_do_fixture": n_fx,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
