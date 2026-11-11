"""Recorta o mundo gerado (4 x 2,4 km, D-03) para a área jogável de 2 x 2 km (D-63).

Entrada: os dados que tools/export_roblox.py gerou em src/ServerStorage/VT65Build/Data (Grid,
Heights_XX, Features). Não precisa das fontes grandes (DEM, carta, satélite), que ficam fora do Git.
A origem do quadro local continua no centro do mundo gerado (geo.play_center_wgs), então as
coordenadas dos locais, da grade de 1965 e do comandante não mudam.

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
MARGEM_M = 150.0  # feições e terreno além da borda jogável (a mesma margem do export_roblox)
ROWS_PER = 64
HEAD = (
    "--!strict\n-- GERADO por tools/export_roblox.py, recortado por tools/crop_world.py (D-63).\n"
)

# Fronteiras de setor (D-63), polilinhas sul -> norte em ING-A. Faixas de ~400 m da Colina 43
# (oeste) até An Cường (2) (leste); cada local real fica inteiro dentro de um setor.
FRONTEIRAS_ING = [
    [(268750, 1691500), (268750, 1693500)],
    [(269150, 1691500), (269150, 1693500)],
    # dobra ao norte para An Thới (2) cair no S4, que sem ela não teria nenhum local real
    [(269600, 1691500), (269600, 1693000), (269450, 1693000), (269450, 1693500)],
    [(269850, 1691500), (269850, 1693500)],
]
SETORES = ["S1 Colina 43", "S2 LZ Blue", "S3 Nam Yên (4)", "S4 Arrozais", "S5 An Cường (2)"]
# Pontos fortes: (setor, nome, E, N, real?, observação). Três por setor.
PONTOS_FORTES = [
    (1, "Colina 43", 268545, 1691655, True, "cota 43 da carta"),
    (1, "Athletic field", 268420, 1692170, True, "retângulo tracejado da carta"),
    (
        1,
        "Lugarejo da Colina 43",
        268655,
        1691597,
        True,
        "5 casas da carta ao pé da colina, sem nome",
    ),
    (2, "LZ Blue", 268850, 1691950, True, "First Fight p.26 + mapa p.25"),
    (2, "Nam Yên (3)", 268950, 1692150, True, "vila da carta"),
    (
        2,
        "Encosta norte",
        268900,
        1693250,
        False,
        "relevo do DEM (sobe a ~50 m na borda norte); nome de design",
    ),
    (3, "Nam Yên (4)", 269350, 1692870, True, "vila da carta"),
    (3, "Cemitério", 269435, 1692547, True, "símbolo de cemitério da carta"),
    (3, "Bosque ao sul de Nam Yên (4)", 269271, 1692006, True, "mancha de vila/mata da carta"),
    (4, "An Thới (2)", 269530, 1693200, True, "vila da carta"),
    (4, "Morrote do arrozal", 269741, 1692964, False, "morrote de 34 m no DEM; nome de design"),
    (4, "Arrozal central", 269725, 1692300, False, "diques e sebes do arrozal; elemento de design"),
    (5, "An Cường (2)", 270030, 1692850, True, "vila fortificada (First Fight p.25)"),
    (5, "Trincheira sul", 270040, 1692640, True, "'wide, deep trench south of the village' (p.23)"),
    (5, "Colina 30", 270205, 1693420, True, "First Fight p.29"),
]
QGS = {
    "US": (270300, 1691750, "borda leste, ao sul de An Cường (2) (setor S5)"),
    "VC": (268420, 1692900, "retaguarda oeste, ao norte do Athletic field (setor S1)"),
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
def crop_box() -> tuple[float, float, float, float]:
    """Caixa local (xmin, xmax, zmin, zmax) da área jogável mais a margem."""
    e0, n0, e1, n1 = PLAY_ING
    m = MARGEM_M
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


def crop_features(f: dict[str, np.ndarray], box) -> dict[str, np.ndarray]:
    xmin, xmax, zmin, zmax = box

    def inside(x, z):
        return (x >= xmin) & (x <= xmax) & (z >= zmin) & (z <= zmax)

    seg = lambda a: inside(a[:, 0], a[:, 1]) & inside(a[:, 2], a[:, 3])  # noqa: E731
    return {
        "dikes": f["dikes"][seg(f["dikes"])],
        "hedges": f["hedges"][seg(f["hedges"])],
        "waters": f["waters"][inside(f["waters"][:, 0], f["waters"][:, 1])],
        "houses": f["houses"][inside(f["houses"][:, 0], f["houses"][:, 1])],
    }


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
        f"\theightChunks = {{{chunk_list}}}, rowsPerChunk = {ROWS_PER},\n"
        f"\tclassNames = {{{names}}},\n"
        f'\tclassesRle = "{base64.b64encode(bytes(rle)).decode()}",\n'
        "}\n",
    )


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
    xa, za = ing_local(e0, n1)  # NO
    xb, zb = ing_local(e1, n0)  # SE

    def poly(pts):  # lista plana x1, z1, x2, z2, ... (o módulo roda também no Lune)
        return "{" + ", ".join(f"{x:.1f}, {z:.1f}" for x, z in pts) + "}"

    lines = [[(e0, n0), (e0, n1)]] + FRONTEIRAS_ING + [[(e1, n0), (e1, n1)]]
    sec_txt = []
    for k in range(5):
        ring = [ing_local(*p) for p in lines[k]] + [ing_local(*p) for p in lines[k + 1]][::-1]
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
    loc_txt = [
        f'\t\t{{ name = "{r["nome"]}", grid = "{r["grade_1965"]}", x = {float(r["x_studs"]):.1f}, '
        f"z = {float(r['z_studs']):.1f}, e1965 = {r['E_ing']}, n1965 = {r['N_ing']} }},"
        for r in locs
    ]
    write(
        SHARED / "MapConfig.luau",
        "--!strict\n-- GERADO por tools/crop_world.py (DESIGN.md D-63). Não editar.\n"
        "-- Coordenadas em studs no quadro local: X = leste, Z = sul. A origem é o centro do\n"
        "-- mundo gerado (4 x 2,4 km, D-03), não o da área jogável (2 x 2 km, a oeste).\n"
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
    fc = crop_features(f, box)
    write_grid(gc)
    write_features(fc)
    write_mapconfig(box)
    n_fx = write_fixture(box)
    print(
        json.dumps(
            {
                "grade_antes": [g["w"], g["h"]],
                "grade_depois": [gc["w"], gc["h"]],
                **{k: [len(f[k]), len(fc[k])] for k in f},
                "pontos_do_fixture": n_fx,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
