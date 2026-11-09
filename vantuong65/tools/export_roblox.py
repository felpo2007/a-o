"""Exporta os dados do mundo (F1 — greybox) para módulos Luau consumidos pelo Rojo.

Gera, a partir da carta L7014 (ed. 3), do DEM e das decisões do DESIGN.md:
  src/ServerStorage/VT65Build/Data/Heights_XX.luau  alturas em cm (uint16 LE, base64), 16 studs
  src/ServerStorage/VT65Build/Data/Classes.luau     uso do solo (RLE por linha, base64)
  src/ServerStorage/VT65Build/Data/Features.luau    quadros de arrozal, diques, sebes, casas
  src/ReplicatedStorage/Shared/MapConfig.luau       limites, setores, pontos fortes, QGs, locais

Sistema de coordenadas do jogo: X = leste, Z = sul, Y = altura; 1 stud = 0,28 m; origem no centro
da área jogável (geo.play_center_wgs). Tudo determinístico (semente fixa).
Uso: uv run python tools/export_roblox.py
"""

from __future__ import annotations

import base64
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np
from scipy import ndimage
from skimage.draw import polygon as draw_polygon
from skimage.measure import find_contours

sys.path.insert(0, str(Path(__file__).parent))
from geo import PLAY_ING, STUD_M, ing_to_wgs_utm, play_center_wgs  # noqa: E402
from landcover import (  # noqa: E402
    CELL_M,
    CELL_STUDS,
    GRASS,
    NOMES,
    PADDY,
    SAND,
    SEA,
    STREAM,
    VILLAGE,
    build_grid,  # noqa: E402
)

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DATA = SRC / "ServerStorage/VT65Build/Data"
SHARED = SRC / "ReplicatedStorage/Shared"
SEED = 1965
H_OFFSET_CM = 1000  # altura armazenada = (h_m * 100) + 1000  (cobre -10 m .. 645 m)

# Cotas da carta usadas para calibrar o relevo (E, N em ING-A; altura em m)
COTAS = [
    ("Colina 43", 268545, 1691655, 43.0),
    ("cota trig. 22", 271630, 1692740, 22.0),
    ("cota 22 An Cuong 1", 271570, 1692400, 22.0),
    ("cota trig. 10", 272132, 1691394, 10.0),
    ("cota trig. 45", 272057, 1693790, 45.0),
]

# Fronteiras de setor (DESIGN D-08), polilinhas sul -> norte em ING-A
FRONTEIRAS_ING = [
    [(269300, 1691200), (269300, 1692450), (269050, 1692450), (269050, 1693600)],
    [(269800, 1691200), (269800, 1693600)],
    [(270420, 1691200), (270420, 1692400), (270500, 1692400), (270500, 1693600)],
    [(271250, 1691200), (271250, 1693600)],
]
SETORES = ["S1 Colina 43", "S2 Nam Yên", "S3 An Cường (2)", "S4 An Phước", "S5 Green Beach"]
# Pontos fortes candidatos: (setor, nome, E, N, real?, observação)
PONTOS_FORTES = [
    (1, "Colina 43", 268545, 1691655, True, "cota 43 da carta"),
    (1, "LZ Blue / Nam Yên (3)", 268900, 1692050, True, "First Fight PDF p.29"),
    (1, "Athletic field", 268400, 1692170, True, "retângulo tracejado da carta"),
    (2, "Nam Yên (4)", 269350, 1692870, True, "vila da carta"),
    (2, "An Thới (2)", 269530, 1693200, True, "vila da carta"),
    (2, "Cemitério", 269435, 1692547, True, "símbolo de cemitério da carta"),
    (3, "An Cường (2)", 270030, 1692850, True, "vila fortificada (First Fight p.25)"),
    (3, "Trincheira sul", 270040, 1692640, True, "'wide, deep trench south of the village' (p.23)"),
    (3, "Colina 30", 270205, 1693420, True, "First Fight p.29"),
    (4, "An Phước (1)", 270560, 1691600, True, "vila da carta"),
    (4, "Vau do riacho", 270730, 1692015, True, "riacho real; ponto do vau é de design"),
    (4, "Túmulos da várzea", 270950, 1692900, False, "elemento de design (confirmar em foto)"),
    (5, "An Cường (1)", 271550, 1692360, True, "vila de pescadores (First Fight p.21)"),
    (5, "Colina 22", 271630, 1692740, True, "Hill 22 (First Fight p.21) = cota trig. 22"),
    (5, "Green Beach (dunas)", 271800, 1692500, True, "praia do desembarque, 06:30"),
]
QGS = {
    "US": (271830, 1691750, "Green Beach sul (setor S5)"),
    "VC": (268280, 1692900, "retaguarda oeste (setor S1)"),
}


def to_local(E: float, N: float) -> tuple[float, float]:
    cE, cN = play_center_wgs()
    return (E - cE) / STUD_M, -(N - cN) / STUD_M


def ing_local(e: float, n: float) -> tuple[float, float]:
    return to_local(*ing_to_wgs_utm(e, n))


def b64(arr: np.ndarray) -> str:
    return base64.b64encode(arr.tobytes()).decode("ascii")


def luau_num(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def luau_list(vals) -> str:
    return "{" + ",".join(luau_num(float(v)) for v in vals) + "}"


def calibrate(gd, h: np.ndarray) -> list[tuple[str, float, float]]:
    """Soma bolhas gaussianas (sigma 60 m) para o relevo bater com as cotas da carta."""
    out = []
    yy, xx = np.mgrid[0 : gd.h, 0 : gd.w]
    for nome, e, n, z in COTAS:
        E, N = ing_to_wgs_utm(e, n)
        fx, fy = (E - gd.e0) / CELL_M - 0.5, (gd.n1 - N) / CELL_M - 0.5
        cur = float(ndimage.map_coordinates(h, [[fy], [fx]], order=1)[0])
        dz = z - cur
        s = 60.0 / CELL_M
        h += dz * np.exp(-((xx - fx) ** 2 + (yy - fy) ** 2) / (2 * s * s))
        out.append((nome, cur, z))
    return out


def gen_paddies(gd, h: np.ndarray, cls: np.ndarray, rng: np.random.Generator):
    """Quadros de arrozal irregulares (20-60 m) numa grade girada e com jitter; terraços."""
    e0, n0, e1, n1 = PLAY_ING
    m = 150.0
    corners = [ing_to_wgs_utm(e, n) for e, n in ((e0 - m, n0 - m), (e1 + m, n1 + m))]
    (Ea, Na), (Eb, Nb) = corners
    cx, cy = (Ea + Eb) / 2, (Na + Nb) / 2
    theta = math.radians(9.0)
    ux, uy = math.cos(theta), math.sin(theta)
    vx, vy = -uy, ux
    half = math.hypot(Eb - Ea, Nb - Na) / 2 + 60
    us = [-half]
    while us[-1] < half:
        us.append(us[-1] + rng.uniform(25, 55))
    vs = [-half]
    while vs[-1] < half:
        vs.append(vs[-1] + rng.uniform(20, 45))
    nu, nv = len(us), len(vs)
    jit = rng.uniform(-3.0, 3.0, size=(nu, nv, 2))
    P = np.zeros((nu, nv, 2))
    for i, u in enumerate(us):
        for j, v in enumerate(vs):
            P[i, j] = (cx + u * ux + v * vx + jit[i, j, 0], cy + u * uy + v * vy + jit[i, j, 1])
    hedge_u = set(np.nonzero(rng.random(nu) < 0.15)[0].tolist())  # linhas com sebe
    hedge_v = set(np.nonzero(rng.random(nv) < 0.15)[0].tolist())

    def grid_px(pts):
        xs = (pts[:, 0] - gd.e0) / CELL_M - 0.5
        ys = (gd.n1 - pts[:, 1]) / CELL_M - 0.5
        return ys, xs

    plots = []  # (quad 4x2 WGS, level, cells)
    edges: dict[tuple, dict] = {}

    def add_edge(a, b, key, level, hedge):
        k = tuple(sorted([key[0], key[1]]))
        d = edges.setdefault(k, {"a": a, "b": b, "levels": [], "hedge": hedge})
        d["levels"].append(level)

    for i in range(nu - 1):
        for j in range(nv - 1):
            q = np.array([P[i, j], P[i + 1, j], P[i + 1, j + 1], P[i, j + 1]])
            keys = [("P", i, j), ("P", i + 1, j), ("P", i + 1, j + 1), ("P", i, j + 1)]
            quads = [(q, keys)]
            if rng.random() < 0.25:  # divide o quadro em dois (irregularidade)
                t = rng.uniform(0.4, 0.6)
                if np.linalg.norm(q[1] - q[0]) > np.linalg.norm(q[3] - q[0]):
                    a, b = q[0] + t * (q[1] - q[0]), q[3] + t * (q[2] - q[3])
                    ka, kb = ("S", i, j, 0), ("S", i, j, 1)
                    quads = [
                        (np.array([q[0], a, b, q[3]]), [keys[0], ka, kb, keys[3]]),
                        (np.array([a, q[1], q[2], b]), [ka, keys[1], keys[2], kb]),
                    ]
                else:
                    a, b = q[0] + t * (q[3] - q[0]), q[1] + t * (q[2] - q[1])
                    ka, kb = ("S", i, j, 2), ("S", i, j, 3)
                    quads = [
                        (np.array([q[0], q[1], b, a]), [keys[0], keys[1], kb, ka]),
                        (np.array([a, b, q[2], q[3]]), [ka, kb, keys[2], keys[3]]),
                    ]
            for qq, kk in quads:
                ys, xs = grid_px(qq)
                rr, cc = draw_polygon(ys, xs, shape=cls.shape)
                if len(rr) < 4:
                    continue
                if np.mean(cls[rr, cc] == PADDY) < 0.6:
                    continue
                level = float(np.percentile(h[rr, cc], 30))
                plots.append((qq, level, (rr, cc)))
                for a_i in range(4):
                    b_i = (a_i + 1) % 4
                    ka, kb = kk[a_i], kk[b_i]
                    on_hedge = (
                        ka[0] == "P"
                        and kb[0] == "P"
                        and (
                            (ka[1] == kb[1] and ka[1] in hedge_u)
                            or (ka[2] == kb[2] and ka[2] in hedge_v)
                        )
                    )
                    add_edge(qq[a_i], qq[b_i], (ka, kb), level, on_hedge)
    # terraços: chão do quadro 12 cm abaixo do nível da água
    for _q, level, (rr, cc) in plots:
        h[rr, cc] = level - 0.12
    return plots, edges


def village_hedges(gd, cls: np.ndarray, rng: np.random.Generator):
    """Touceiras de bambu no contorno das manchas verdes da carta (vilas e matas)."""
    mask = ndimage.gaussian_filter((cls == VILLAGE).astype(float), 1.0)
    segs = []
    for c in find_contours(mask, 0.5):
        if len(c) < 8:
            continue
        pts = np.column_stack([gd.e0 + (c[:, 1] + 0.5) * CELL_M, gd.n1 - (c[:, 0] + 0.5) * CELL_M])
        d = np.r_[0, np.cumsum(np.hypot(*np.diff(pts, axis=0).T))]
        if d[-1] < 30:
            continue
        s = np.arange(0, d[-1], 8.0)
        x = np.interp(s, d, pts[:, 0])
        y = np.interp(s, d, pts[:, 1])
        for k in range(len(s) - 1):
            if rng.random() < 0.15:  # brechas naturais na sebe
                continue
            segs.append((x[k], y[k], x[k + 1], y[k + 1], rng.uniform(4.0, 7.0)))
    return segs


def in_play(E: float, N: float, margin: float = 150.0) -> bool:
    e0, n0, e1, n1 = PLAY_ING
    a = ing_to_wgs_utm(e0 - margin, n0 - margin)
    b = ing_to_wgs_utm(e1 + margin, n1 + margin)
    return a[0] <= E <= b[0] and a[1] <= N <= b[1]


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main() -> None:
    rng = np.random.default_rng(SEED)
    gd = build_grid()
    h = gd.height_m.copy()
    cls = gd.cls.copy()
    cal = calibrate(gd, h)
    plots, edges = gen_paddies(gd, h, cls, rng)
    # riachos: leito 1,0 m abaixo do mínimo da vizinhança 3x3
    st = cls == STREAM
    h[st] = ndimage.minimum_filter(h, size=3)[st] - 1.0
    hedges_v = village_hedges(gd, cls, rng)

    # ---------- alturas ----------
    hc = np.clip(np.round(h * 100) + H_OFFSET_CM, 0, 65535).astype("<u2")
    rows_per = 64
    chunks = []
    for k, r0 in enumerate(range(0, gd.h, rows_per)):
        part = hc[r0 : r0 + rows_per]
        name = f"Heights_{k:02d}"
        chunks.append(name)
        write(
            DATA / f"{name}.luau",
            "--!strict\n-- GERADO por tools/export_roblox.py. Não editar à mão.\n"
            f'return {{ row0 = {r0}, rows = {part.shape[0]}, data = "{b64(part)}" }}\n',
        )
    # ---------- classes (RLE por linha: pares classe, comprimento<=255) ----------
    rle = bytearray()
    for row in cls:
        j = 0
        while j < len(row):
            c = int(row[j])
            n = 1
            while j + n < len(row) and row[j + n] == c and n < 255:
                n += 1
            rle += bytes((c, n))
            j += n
    nw_x, nw_z = to_local(gd.e0, gd.n1)
    write(
        DATA / "Grid.luau",
        "--!strict\n-- GERADO por tools/export_roblox.py. Não editar à mão.\n"
        "return {\n"
        f"\twidth = {gd.w}, height = {gd.h}, cellStuds = {CELL_STUDS},\n"
        f"\toriginX = {nw_x:.2f}, originZ = {nw_z:.2f}, -- canto NO (borda da célula)\n"
        f"\theightOffsetCm = {H_OFFSET_CM},\n"
        f"\theightChunks = {{{', '.join(repr(c) for c in chunks)}}}, rowsPerChunk = {rows_per},\n"
        f"\tclassNames = {{{', '.join(repr(n) for n in NOMES)}}},\n"
        f'\tclassesRle = "{base64.b64encode(bytes(rle)).decode()}",\n'
        "}\n".replace("'", '"'),
    )

    # ---------- feições ----------
    dikes, hedges = [], []
    for d in edges.values():
        (Ea, Na), (Eb, Nb) = d["a"], d["b"]
        if not (in_play(Ea, Na) and in_play(Eb, Nb)):
            continue
        top = max(d["levels"]) + float(rng.uniform(0.5, 0.8))
        base = min(d["levels"]) - 0.6
        xa, za = to_local(Ea, Na)
        xb, zb = to_local(Eb, Nb)
        dikes += [xa, za, xb, zb, top / STUD_M, base / STUD_M]
        if d["hedge"]:
            hedges += [
                xa,
                za,
                xb,
                zb,
                top / STUD_M,
                float(rng.uniform(1.8, 2.4)) / STUD_M,
                1.2 / STUD_M,
            ]
    waters = []
    for q, level, _cells in plots:
        c = q.mean(axis=0)
        if not in_play(*c):
            continue
        uvec = ((q[1] - q[0]) + (q[2] - q[3])) / 2
        vvec = ((q[3] - q[0]) + (q[2] - q[1])) / 2
        lu, lv = np.linalg.norm(uvec), np.linalg.norm(vvec)
        ang = math.atan2(uvec[1], uvec[0])  # ângulo no plano E-N
        x, z = to_local(*c)
        # no quadro local Z aponta para o sul: rotação em Y = +ang (ver FeatureBuilder)
        waters += [x, z, level / STUD_M, (lu - 0.8) / STUD_M, (lv - 0.8) / STUD_M, ang]
    for xa, ya, xb, yb, hh in hedges_v:
        if not (in_play(xa, ya) and in_play(xb, yb)):
            continue
        ia = ((gd.n1 - ya) / CELL_M, (xa - gd.e0) / CELL_M)
        g = float(ndimage.map_coordinates(h, [[ia[0] - 0.5], [ia[1] - 0.5]], order=1)[0])
        p, q2 = to_local(xa, ya), to_local(xb, yb)
        hedges += [p[0], p[1], q2[0], q2[1], g / STUD_M, hh / STUD_M, 2.5 / STUD_M]
    houses = []
    for E, N in gd.houses:
        if not in_play(E, N):
            continue
        i, j = (gd.n1 - N) / CELL_M - 0.5, (E - gd.e0) / CELL_M - 0.5
        g = float(ndimage.map_coordinates(h, [[i], [j]], order=1)[0])
        x, z = to_local(E, N)
        houses += [x, z, g / STUD_M, float(rng.uniform(0, math.pi))]
    feats = (
        "--!strict\n-- GERADO por tools/export_roblox.py. Não editar à mão.\n"
        "-- Listas planas (studs, radianos):\n"
        "--  dikes  : x1,z1,x2,z2,yTop,yBase\n"
        "--  hedges : x1,z1,x2,z2,yBase,altura,espessura\n"
        "--  waters : x,z,yNivel,tamU,tamV,angulo\n"
        "--  houses : x,z,yChao,angulo\n"
        "return {\n"
        f"\tdikes = {luau_list(dikes)},\n"
        f"\thedges = {luau_list(hedges)},\n"
        f"\twaters = {luau_list(waters)},\n"
        f"\thouses = {luau_list(houses)},\n"
        "}\n"
    )
    write(DATA / "Features.luau", feats)

    # ---------- MapConfig (replicado) ----------
    e0, n0, e1, n1 = PLAY_ING
    ing0 = ((e0 + e1) / 2, (n0 + n1) / 2)  # o centro da área é a origem local por construção
    xa, za = ing_local(e0, n1)  # NO
    xb, zb = ing_local(e1, n0)  # SE

    def poly(pts):  # lista plana x1, z1, x2, z2, ... (sem Vector2: o módulo roda também no Lune)
        return "{" + ", ".join(f"{x:.1f}, {z:.1f}" for x, z in pts) + "}"

    bounds_w = [(e0, n0), (e0, n1)]
    bounds_e = [(e1, n0), (e1, n1)]
    lines = [bounds_w] + FRONTEIRAS_ING + [bounds_e]
    sec_txt = []
    for k in range(5):
        west = [ing_local(*p) for p in lines[k]]
        east = [ing_local(*p) for p in lines[k + 1]]
        ring = west + east[::-1]
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
    with open(ROOT / "research/locais.csv", encoding="utf-8") as f:
        locs = list(csv.DictReader(f))
    loc_txt = [
        f'\t\t{{ name = "{r["nome"]}", grid = "{r["grade_1965"]}", x = {float(r["x_studs"]):.1f}, '
        f"z = {float(r['z_studs']):.1f}, e1965 = {r['E_ing']}, n1965 = {r['N_ing']} }},"
        for r in locs
    ]
    cfg = (
        "--!strict\n-- GERADO por tools/export_roblox.py (DESIGN.md D-03, D-08). Não editar.\n"
        "-- Coordenadas em studs no quadro local: X = leste, Z = sul, origem no centro da área.\n"
        "local MapConfig = {}\n\n"
        f"MapConfig.STUD_M = {STUD_M}\n"
        f"MapConfig.Bounds = {{ minX = {xa:.1f}, maxX = {xb:.1f}, "
        f"minZ = {za:.1f}, maxZ = {zb:.1f} }}\n"
        f"-- grade de 1965 (ING-A) da origem local: E = gridE0 + x*0,28 ; N = gridN0 - z*0,28\n"
        f"MapConfig.GridOrigin1965 = {{ e = {ing0[0]:.1f}, n = {ing0[1]:.1f} }}\n"
        "MapConfig.OutOfBoundsKillSeconds = 10\n"
        "MapConfig.CaptureRadiusStuds = 50 / 0.28 -- 50 m (prompt: 40-60 m)\n"
        "MapConfig.Sectors = {\n" + "\n".join(sec_txt) + "\n}\n"
        "MapConfig.Strongpoints = {\n" + "\n".join(sp_txt) + "\n}\n"
        "MapConfig.HQ = {\n" + "\n".join(qg_txt) + "\n}\n"
        "MapConfig.Locations = {\n" + "\n".join(loc_txt) + "\n}\n"
        "-- EUA começam com S4-S5, VC com S1-S2, S3 neutro (prompt, Parte 3)\n"
        'MapConfig.InitialOwner = { "VC", "VC", "Neutral", "US", "US" }\n\n'
        "return MapConfig\n"
    )
    write(SHARED / "MapConfig.luau", cfg)

    fx = []
    for nome, e, n, _z in COTAS + [
        ("Nam Yen 3", 268950, 1692150, 0.0),
        ("An Cuong 2", 270030, 1692850, 0.0),
    ]:
        E, N = ing_to_wgs_utm(e, n)
        x, z = to_local(E, N)
        i, j = (gd.n1 - N) / CELL_M - 0.5, (E - gd.e0) / CELL_M - 0.5
        hq = (np.round(h * 100)) / 100  # mesma quantização do arquivo
        hv = float(ndimage.map_coordinates(hq, [[i], [j]], order=1)[0])
        fx.append({"name": nome, "x": x, "z": z, "h_studs": hv / STUD_M})
    write(ROOT / "tests/luau/fixture_heights.json", json.dumps(fx, ensure_ascii=False, indent=1))

    rep = {
        "grade": [gd.w, gd.h, CELL_M],
        "calibracao_cotas": [(n, round(c, 1), z) for n, c, z in cal],
        "quadros_arrozal": len(plots),
        "agua_parts": len(waters) // 6,
        "diques": len(dikes) // 6,
        "sebes": len(hedges) // 7,
        "casas": len(houses) // 4,
        "classes": {
            NOMES[i]: round(float(f), 3)
            for i, f in enumerate(np.bincount(cls.ravel(), minlength=6) / cls.size)
        },
        "altura_m": [round(float(h.min()), 2), round(float(h.max()), 2)],
    }
    write(ROOT / "research/export_report.json", json.dumps(rep, ensure_ascii=False, indent=1))
    print(json.dumps(rep, ensure_ascii=False))
    _ = (GRASS, SAND, SEA)  # classes usadas no builder Luau


if __name__ == "__main__":
    main()
