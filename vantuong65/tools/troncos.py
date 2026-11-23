"""Tronco que para a bala (D-151): cilindros invisíveis medidos na malha de cada árvore.

Pedido do dono (2026-11-15): "as árvores devem tancar os tiros". A bala só para em peça com
colisão. Até a v80 isso era a peça Madeira0 das árvores prontas, com a colisão automática do
Roblox (um casco aproximado do tronco com os galhos grossos). Na ph_tree_small_02 a Madeira0 é a
galhada lá em cima: o tronco de verdade (Madeira1) deixava a bala passar, e o coqueiro inteiro
também (nenhuma peça sólida, conferido no Studio).

Aqui a malha de madeira é cortada em fatias horizontais. Em cada fatia, cada contorno fechado é
um caule; os caules são ligados de uma fatia para a outra, do pé para cima, até a altura
escolhida ou até o caule se abrir em galhos (o contorno cresce de repente). Galho grosso que sai
de um caule também conta (menos no coqueiro, onde lá em cima é a copa). Os caules viram até
MAX_CILINDROS cilindros retos por árvore, gravados em `Modules/TreeTrunks.luau` no espaço do
modelo do Roblox: studs na escala 1, pivô no pé e o giro de 180° em Y do importador (D-58: x e z
trocam de sinal).

Uso: uv run python tools/troncos.py [--previa <pasta>]  (a prévia precisa do grupo "arte")
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from decimate_glb import accessor, read_glb  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "src" / "ServerScriptService" / "Modules" / "TreeTrunks.luau"
M_POR_STUD = 0.28

# chave do modelo -> glb: o que subiu; malha: trecho do nome da malha de madeira (None = a malha
# toda); escala: típica na mata (Vegetation, o meio das faixas s0..s1; os limiares são em metros);
# altura: até onde (m) o tronco conta; pe: a primeira fatia (m), acima da raiz espalhada no chão;
# galhos: galho grosso que sai do tronco também conta (no coqueiro, não: lá em cima é a copa)
ARVORES: dict[str, dict] = {
    "ph_island_tree_01": {"glb": "assets/arvores/ph_island_tree_01.glb", "escala": 2.8},
    "ph_island_tree_02": {"glb": "assets/arvores/ph_island_tree_02.glb", "escala": 2.7},
    # caules finos e tortos: acima de 1 m têm raio de 6 cm ou menos e não contam (só o pé para)
    "ph_island_tree_03": {"glb": "assets/arvores/ph_island_tree_03.glb", "escala": 2.0},
    "ph_tree_small_02": {"glb": "assets/arvores/ph_tree_small_02.glb", "escala": 4.1},
    "coconut_palm": {
        "glb": "assets/forgegui/models/coqueiro_studs_fosco.glb",
        "malha": None,
        "escala": 1.1,
        "altura": 9.0,
        "galhos": False,
    },
    # D-232: árvores do Blender (as raízes ficam na malha Raizes0, fora da medida)
    "exp_figueira": {
        "glb": "assets/blender/exp_figueira/exp_figueira.glb",
        "escala": 1.0,
        "pe": 1.65,
        "altura": 4.4,
    },
    "exp_arvore_a": {
        "glb": "assets/blender/exp_arvore_a/exp_arvore_a.glb",
        "escala": 1.0,
        "pe": 0.8,
        "altura": 2.3,
    },
    "exp_arvore_b": {
        "glb": "assets/blender/exp_arvore_b/exp_arvore_b.glb",
        "escala": 1.0,
        "pe": 0.8,
        "altura": 2.3,
    },
}
PADRAO = {"malha": "Madeira", "altura": 5.0, "pe": 0.3, "galhos": True}
# D-233: pedra da mata: um cilindro baixo no miolo, para ela parar a bala e o soldado
ROCHAS = {"exp_rocha": "assets/blender/exp_rocha/exp_rocha.glb"}

PASSO_M = 0.25  # distância entre as fatias, na escala típica
RAIO_MIN_M = 0.06  # caule mais fino que isto (raio) não para a bala
SALTO = 1.45  # o contorno cresce mais que isto de uma vez: o caule se abriu em galhos
MAX_CILINDROS = 6  # por árvore
POR_CAULE = 3
DESVIO = 0.3  # fração do raio que o eixo pode se afastar da reta do cilindro


def matriz(n: dict) -> np.ndarray:
    if "matrix" in n:
        return np.array(n["matrix"], dtype=np.float64).reshape(4, 4).T
    t = np.array(n.get("translation", [0, 0, 0]), dtype=np.float64)
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    r = np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )
    m = np.eye(4)
    m[:3, :3] = r * np.array(n.get("scale", [1, 1, 1]), dtype=np.float64)
    m[:3, 3] = t
    return m


def madeira(caminho: Path, filtro: str | None) -> tuple[np.ndarray, np.ndarray]:
    """Vértices (studs, espaço do GLB) e triângulos das malhas de madeira, com os nós aplicados."""
    js, blob = read_glb(caminho)
    vs: list[np.ndarray] = []
    fs: list[np.ndarray] = []
    base = 0

    def walk(i: int, pai: np.ndarray) -> None:
        nonlocal base
        n = js["nodes"][i]
        m = pai @ matriz(n)
        if "mesh" in n:
            mesh = js["meshes"][n["mesh"]]
            if filtro is None or filtro in mesh.get("name", n.get("name", "")):
                for pr in mesh["primitives"]:
                    p = accessor(js, blob, pr["attributes"]["POSITION"]).astype(np.float64)
                    p = p @ m[:3, :3].T + m[:3, 3]
                    f = accessor(js, blob, pr["indices"]).astype(np.int64).reshape(-1, 3)
                    vs.append(p)
                    fs.append(f + base)
                    base += len(p)
        for c in n.get("children", []):
            walk(c, m)

    for raiz in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(raiz, np.eye(4))
    return np.concatenate(vs), np.concatenate(fs)


def contornos(v: np.ndarray, f: np.ndarray, y: float) -> list[tuple[float, float, float]]:
    """Contornos do corte horizontal em y: (x, z, raio) de cada um.

    Cada triângulo que cruza o plano liga as duas arestas cortadas; as arestas ligadas formam um
    contorno (um caule). O raio é a média das meias larguras da caixa do contorno.
    """
    lados = []
    pts = []
    for a, b in ((0, 1), (1, 2), (2, 0)):
        pa, pb = v[f[:, a]], v[f[:, b]]
        ya, yb = pa[:, 1] - y, pb[:, 1] - y
        sel = (ya * yb) < 0
        t = np.where(sel, ya / np.where(sel, ya - yb, 1.0), 0.0)
        pts.append((pa + (pb - pa) * t[:, None])[:, [0, 2]])
        aresta = np.sort(np.stack([f[:, a], f[:, b]], axis=1), axis=1)
        lados.append((sel, aresta))
    corta = np.stack([s for s, _ in lados], axis=1)  # (n, 3)
    tri = np.nonzero(corta.sum(axis=1) == 2)[0]
    if len(tri) == 0:
        return []
    ids: dict[tuple[int, int], int] = {}
    pos: list[np.ndarray] = []
    pares = []
    for i in tri:
        ns = []
        for k in range(3):
            if corta[i, k]:
                chave = (int(lados[k][1][i, 0]), int(lados[k][1][i, 1]))
                if chave not in ids:
                    ids[chave] = len(pos)
                    pos.append(pts[k][i])
                ns.append(ids[chave])
        pares.append(ns)
    pai = list(range(len(pos)))

    def raiz(i: int) -> int:
        while pai[i] != i:
            pai[i] = pai[pai[i]]
            i = pai[i]
        return i

    for a, b in pares:
        pai[raiz(a)] = raiz(b)
    grupos: dict[int, list[int]] = {}
    for i in range(len(pos)):
        grupos.setdefault(raiz(i), []).append(i)
    P = np.array(pos)
    caixas = []
    for g in grupos.values():
        q = P[g]
        caixas.append([*q.min(axis=0), *q.max(axis=0)])
    # cascas sobrepostas (um galho que entra no tronco) viram um contorno só
    juntou = True
    while juntou:
        juntou = False
        for i in range(len(caixas)):
            for j in range(i + 1, len(caixas)):
                a, b = caixas[i], caixas[j]
                if a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]:
                    caixas[i] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
                    del caixas[j]
                    juntou = True
                    break
            if juntou:
                break
    return [
        ((c[0] + c[2]) / 2, (c[1] + c[3]) / 2, ((c[2] - c[0]) + (c[3] - c[1])) / 4) for c in caixas
    ]


def hastes(
    v: np.ndarray, f: np.ndarray, cfg: dict
) -> list[list[tuple[float, float, float, float]]]:
    """Caules grossos: listas de (y, x, z, raio) do pé até cfg["altura"] (ou até o caule acabar)."""
    s = cfg["escala"]
    y0 = float(v[:, 1].min())
    passo = PASSO_M / M_POR_STUD / s
    r_min = RAIO_MIN_M / M_POR_STUD / s
    pe = cfg["pe"] / M_POR_STUD / s
    topo = min(float(v[:, 1].max()), y0 + cfg["altura"] / M_POR_STUD / s)
    abertas: list[list[tuple[float, float, float, float]]] = []
    fechadas: list[list[tuple[float, float, float, float]]] = []
    y = y0 + pe
    while y <= topo:
        cs = [c for c in contornos(v, f, y) if c[2] >= r_min]
        usadas: set[int] = set()
        novas = []
        for h in abertas:
            _, hx, hz, hr = h[-1]
            melhor, dmin = -1, np.inf
            for i, (x, z, r) in enumerate(cs):
                d = float(np.hypot(x - hx, z - hz))
                if i not in usadas and d < max(hr, r) + passo and d < dmin:
                    melhor, dmin = i, d
            if melhor >= 0:
                usadas.add(melhor)
                x, z, r = cs[melhor]
                # o caule que se abre em galhos (o contorno cresce de repente) acaba aqui
                if r > SALTO * min(p[3] for p in h[-6:]) and len(h) >= 3:
                    fechadas.append(h)
                    continue
                h.append((y, x, z, r))
                novas.append(h)
            else:
                fechadas.append(h)
        # contorno sem caule: no pé, é um caule novo; acima, um galho grosso que sai de um caule
        # (aberto ou que acabou de se abrir nas 3 fatias de baixo) e começa no topo dele
        no_pe = y <= y0 + 2 * pe
        for i, (x, z, r) in enumerate(cs):
            if i in usadas:
                continue
            if no_pe:
                novas.append([(y, x, z, r)])
                continue
            if not cfg["galhos"]:
                continue
            mae, dmin = None, np.inf
            for h in abertas + fechadas:
                hy, hx, hz, hr = h[-1]
                d = float(np.hypot(x - hx, z - hz))
                if y - hy <= 3.5 * passo and d < max(hr, r) + 2 * passo and d < dmin:
                    mae, dmin = h, d
            if mae is not None:
                novas.append([mae[-1], (y, x, z, r)])
        abertas = novas
        y += passo
    fechadas += abertas
    return [h for h in fechadas if len(h) >= 3]


def cilindros(
    eixo: list[tuple[float, float, float, float]], y_pe: float | None, maximo: int
) -> list[dict]:
    """Junta os pontos do eixo de um caule em até `maximo` retas (a, b, r)."""
    pts = np.array([[x, y, z] for y, x, z, _ in eixo])
    rs = np.array([r for *_, r in eixo])
    if y_pe is not None:
        # o caule que nasce no pé desce até o chão
        pts = np.vstack([[pts[0, 0], y_pe, pts[0, 2]], pts])
        rs = np.concatenate([[rs[0]], rs])
    cortes = [0]
    i = 0
    while i < len(pts) - 1:
        j = i + 2
        while j < len(pts):
            a, b = pts[i], pts[j]
            u = (b - a) / np.linalg.norm(b - a)
            meio = pts[i + 1 : j]
            d = np.linalg.norm(np.cross(meio - a, u), axis=1)
            if np.any(d > DESVIO * np.median(rs[i : j + 1])):
                break
            j += 1
        i = j - 1
        cortes.append(i)
    # funde os trechos mais curtos até caber em `maximo`
    while len(cortes) - 1 > maximo:
        comp = [cortes[k + 1] - cortes[k] for k in range(len(cortes) - 1)]
        k = int(np.argmin(comp))
        del cortes[k + 1 if k + 1 < len(cortes) - 1 else k]
    out = []
    for k in range(len(cortes) - 1):
        a, b = pts[cortes[k]], pts[cortes[k + 1]]
        r = float(np.median(rs[cortes[k] : cortes[k + 1] + 1]))
        out.append({"a": a, "b": b, "r": r})
    if y_pe is not None:
        # nada abaixo do pé: a ponta de baixo de um cilindro inclinado desce r·sen(inclinação)
        a, b, r = out[0]["a"], out[0]["b"], out[0]["r"]
        u = (b - a) / np.linalg.norm(b - a)
        out[0]["a"] = a + u * (r * np.sqrt(max(0.0, 1 - u[1] ** 2)) / max(u[1], 0.2))
    return out


def roblox(p: np.ndarray) -> list[float]:
    """Espaço do GLB -> espaço do modelo no Roblox (giro de 180° em Y do importador, D-58)."""
    return [round(float(-p[0]), 3), round(float(p[1]), 3), round(float(-p[2]), 3)]


def medir(chave: str) -> dict:
    cfg = {**PADRAO, **ARVORES[chave]}
    escala = cfg["escala"]
    v, f = madeira(RAIZ / cfg["glb"], cfg["malha"])
    y_pe = float(v[:, 1].min())
    hs = hastes(v, f, cfg)
    # os caules mais grossos e compridos primeiro, até o teto de cilindros da árvore
    hs.sort(key=lambda h: -float(np.mean([p[3] for p in h])) * (h[-1][0] - h[0][0]))
    cil: list[dict] = []
    pe_ate = y_pe + 2 * cfg["pe"] / M_POR_STUD / escala
    for h in hs:
        livre = MAX_CILINDROS - len(cil)
        if livre <= 0:
            break
        cil += cilindros(h, y_pe if h[0][0] <= pe_ate else None, min(livre, POR_CAULE))
    return {"v": v, "f": f, "hastes": hs, "cil": cil, "y_pe": y_pe, "escala": escala}


def medir_rocha(chave: str) -> dict:
    """Cilindro em pé no miolo da pedra (85% da menor meia largura a 40% da altura), até 85%."""
    v, f = madeira(RAIZ / ROCHAS[chave], None)
    y0, y1 = float(v[:, 1].min()), float(v[:, 1].max())
    faixa = v[np.abs(v[:, 1] - (y0 + 0.4 * (y1 - y0))) < 0.08 * (y1 - y0)]
    cx, cz = (faixa[:, [0, 2]].max(axis=0) + faixa[:, [0, 2]].min(axis=0)) / 2
    meia = (faixa[:, [0, 2]].max(axis=0) - faixa[:, [0, 2]].min(axis=0)) / 2
    r = 0.85 * float(meia.min())
    cil = [
        {
            "a": np.array([cx, y0 + 0.02, cz]),
            "b": np.array([cx, y0 + 0.85 * (y1 - y0), cz]),
            "r": r,
        }
    ]
    return {"v": v, "f": f, "hastes": [[]], "cil": cil, "y_pe": y0, "escala": 1.0}


def luau(medidas: dict[str, dict]) -> str:
    ls = [
        "--!strict",
        "-- GERADO por tools/troncos.py (D-151). Não edite à mão: rode o script de novo.",
        "-- Tronco que para a bala e o soldado: cilindros (a -> b, raio r) no espaço do modelo",
        "-- (studs na escala 1, pivô no pé). AssetLoader.template põe uma peça invisível por",
        "-- cilindro (Tronco_1, Tronco_2...).",
        "",
        "export type Cyl = { a: { number }, b: { number }, r: number }",
        "",
        "local T: { [string]: { Cyl } } = {",
    ]
    for chave in sorted(medidas):
        ls.append(f"\t{chave} = {{")
        for c in medidas[chave]["cil"]:
            a, b = roblox(c["a"]), roblox(c["b"])
            ls.append(
                f"\t\t{{ a = {{ {a[0]}, {a[1]}, {a[2]} }}, b = {{ {b[0]}, {b[1]}, {b[2]} }}, "
                f"r = {round(c['r'], 3)} }},"
            )
        ls.append("\t},")
    ls += ["}", "", "return T", ""]
    return "\n".join(ls)


def previa(chave: str, med: dict, pasta: Path, px: int = 520) -> None:
    """Madeira de frente (x) e de lado (z), com o contorno dos cilindros em vermelho."""
    from PIL import Image, ImageDraw

    v = med["v"]
    lo, hi = v.min(axis=0), v.max(axis=0)
    k = (px - 20) / max(hi - lo)
    img = Image.new("RGB", (2 * px, px), "white")
    dr = ImageDraw.Draw(img)
    for painel, i in enumerate((0, 2)):

        def xy(h: float, y: float, painel: int = painel, i: int = i) -> tuple[float, float]:
            return (painel * px + 10 + (h - lo[i]) * k, px - 10 - (y - lo[1]) * k)

        for tri in med["f"][:: max(1, len(med["f"]) // 8000)]:
            dr.polygon([xy(v[t, i], v[t, 1]) for t in tri], outline=(150, 120, 90))
        for c in med["cil"]:
            a, b, r = c["a"], c["b"], c["r"]
            d = np.array([b[i] - a[i], b[1] - a[1]])
            n = np.array([-d[1], d[0]]) / np.linalg.norm(d)
            for s in (-1, 1):
                dr.line(
                    [
                        xy(a[i] + s * r * n[0], a[1] + s * r * n[1]),
                        xy(b[i] + s * r * n[0], b[1] + s * r * n[1]),
                    ],
                    fill=(210, 30, 30),
                    width=2,
                )
        dr.text((painel * px + 10, 10), f"{chave} ({'xz'[painel]})", fill="black")
    img.save(pasta / f"tronco_{chave}.png")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--previa", type=Path, help="pasta para os desenhos de conferência")
    args = ap.parse_args()
    medidas = {}
    for chave in [*ARVORES, *ROCHAS]:
        med = medir_rocha(chave) if chave in ROCHAS else medir(chave)
        medidas[chave] = med
        s = med["escala"]
        alto = max(max(c["a"][1], c["b"][1]) for c in med["cil"]) - med["y_pe"]
        rs = [round(c["r"] * M_POR_STUD * s, 2) for c in med["cil"]]
        print(
            f"{chave} (escala {s}): {len(med['hastes'])} caules, {len(med['cil'])} cilindros até"
            f" {alto * M_POR_STUD * s:.1f} m, raios (m) {rs}"
        )
        if args.previa:
            args.previa.mkdir(parents=True, exist_ok=True)
            previa(chave, med, args.previa)
    SAIDA.write_text(luau(medidas), encoding="utf-8", newline="\n")
    print(f"gravado {SAIDA.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
