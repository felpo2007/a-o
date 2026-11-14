"""Prepara as árvores prontas do Poly Haven (CC0) para o Roblox (D-67).

O modelo original tem cada folha modelada (24 triângulos por folha, ~30 mil folhas) e galhos
finos: 1 a 2 milhões de triângulos. Aqui ele vira uma árvore de jogo, sem perder a copa:
- folha → cartão: um quadrado (2 triângulos) por folha, no plano dela, com a mesma região da
  textura. A transparência do cartão é o contorno da folha, desenhado a partir das UVs das folhas
  originais (a textura do Poly Haven é JPEG, sem canal alfa);
- ralear: fica uma fração das folhas, cada uma maior, para a copa cobrir o mesmo volume;
- normais da folha meio voltadas para fora da copa (a copa ganha volume na luz);
- madeira: galhos finos demais (escondidos na copa) saem; o resto é reduzido por quádricas
  (tools/decimate_glb.py), com a escala da textura (KHR_texture_transform) aplicada nas UVs;
- base do tronco na origem, em studs (1 stud = 0,28 m), Y para cima;
- cada peça com até 19 mil triângulos (limite de malha do Roblox: 20 mil);
- sem metal (metallicFactor 0); folha com alphaMode MASK e dupla face.

Entrada: assets/arvores_src/<id>/ (tools/fetch_trees.py). Saída: assets/arvores/<chave>.glb e
uma prévia de lado em assets/arvores/<chave>_previa.png (fora do Git).

Uso: uv run --group arte python tools/prep_trees.py [chave ...]
"""

from __future__ import annotations

import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

sys.path.insert(0, str(Path(__file__).resolve().parent))
from decimate_glb import decimate  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
FONTE = RAIZ / "assets" / "arvores_src"
SAIDA = RAIZ / "assets" / "arvores"
M_POR_STUD = 0.28
MAX_TRIS_PECA = 19000
TEX_PX = 1024

# chave -> id do Poly Haven, nos (trecho do nome do nó; sem = todos), folhas que ficam (cartões),
# triângulos de madeira, galho_m (galho menor que isso, em m de diagonal, sai) e soltar (redução
# com a borda solta). O jacarandá (24 m) ficou de fora: a redução dos 1,2 milhão de triângulos de
# galho parava em 167 mil.
ESPECIES: dict[str, dict] = {
    "ph_island_tree_01": {"id": "island_tree_01", "folhas": 5200, "madeira": 3200, "galho_m": 0.5},
    "ph_island_tree_02": {"id": "island_tree_02", "folhas": 4800, "madeira": 3000, "galho_m": 0.45},
    "ph_island_tree_03": {"id": "island_tree_03", "folhas": 4800, "madeira": 3000, "galho_m": 0.45},
    "ph_tree_small_02": {"id": "tree_small_02", "folhas": 5200, "madeira": 2800, "galho_m": 0.4},
}

CT = {
    5120: np.int8,
    5121: np.uint8,
    5122: np.int16,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


# ---------- leitura do glTF ----------
class Gltf:
    def __init__(self, path: Path):
        self.path = path
        self.js = json.loads(path.read_text("utf-8"))
        self.bins = [(path.parent / b["uri"]).read_bytes() for b in self.js["buffers"]]

    def acc(self, i: int) -> np.ndarray:
        a = self.js["accessors"][i]
        bv = self.js["bufferViews"][a["bufferView"]]
        k = NC[a["type"]]
        dt = np.dtype(CT[a["componentType"]])
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride") or k * dt.itemsize
        raw = np.frombuffer(self.bins[bv["buffer"]], np.uint8)
        if stride == k * dt.itemsize:
            arr = np.frombuffer(raw, dt, a["count"] * k, off)
        else:
            rows = np.lib.stride_tricks.as_strided(raw[off:], (a["count"], stride), (stride, 1))
            arr = rows[:, : k * dt.itemsize].copy().view(dt).reshape(-1)
        if a.get("normalized") and dt.kind in "iu":
            arr = arr.astype(np.float32) / np.iinfo(dt).max
        return arr.reshape(a["count"], k) if k > 1 else arr

    def image_bytes(self, tex_index: int) -> bytes:
        src = self.js["textures"][tex_index]["source"]
        img = self.js["images"][src]
        if "uri" in img:
            return (self.path.parent / img["uri"]).read_bytes()
        bv = self.js["bufferViews"][img["bufferView"]]
        s = bv.get("byteOffset", 0)
        return self.bins[bv["buffer"]][s : s + bv["byteLength"]]


def node_matrix(n: dict) -> np.ndarray:
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
    s = np.array(n.get("scale", [1, 1, 1]), dtype=np.float64)
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


def primitivas(g: Gltf, filtro: str | None):
    """(material, pos[m], uv, idx) de cada primitiva dos nós escolhidos, já no espaço do mundo."""
    js = g.js
    out = []

    def walk(i: int, parent: np.ndarray):
        n = js["nodes"][i]
        m = parent @ node_matrix(n)
        if "mesh" in n and (filtro is None or filtro in n.get("name", "")):
            for pr in js["meshes"][n["mesh"]]["primitives"]:
                mat = js["materials"][pr["material"]]
                bct = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture", {})
                tc = bct.get("texCoord", 0)
                pos = g.acc(pr["attributes"]["POSITION"]).astype(np.float64)
                pos = pos @ m[:3, :3].T + m[:3, 3]
                uv = g.acc(pr["attributes"][f"TEXCOORD_{tc}"]).astype(np.float64)
                tr = bct.get("extensions", {}).get("KHR_texture_transform")
                if tr:
                    sc = np.array(tr.get("scale", [1, 1]))
                    off = np.array(tr.get("offset", [0, 0]))
                    rot = tr.get("rotation", 0.0)
                    c, s = np.cos(rot), np.sin(rot)
                    uv = (uv * sc) @ np.array([[c, s], [-s, c]]) + off
                idx = g.acc(pr["indices"]).astype(np.int64).reshape(-1, 3)
                out.append((mat, pos, uv, idx))
        for c in n.get("children", []):
            walk(c, m)

    for root in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(root, np.eye(4))
    return out


def eh_folha(mat: dict) -> bool:
    nome = mat.get("name", "").lower()
    return "lea" in nome or "foli" in nome or mat.get("alphaMode") in ("BLEND", "MASK")


def componentes(idx: np.ndarray, n: int) -> tuple[int, np.ndarray]:
    a = np.concatenate([idx[:, 0], idx[:, 1], idx[:, 2]])
    b = np.concatenate([idx[:, 1], idx[:, 2], idx[:, 0]])
    adj = coo_matrix((np.ones(len(a)), (a, b)), shape=(n, n))
    return connected_components(adj, directed=False)


# ---------- folhas ----------
def cartoes(pos, uv, idx, manter: int, rng: np.random.Generator):
    """Uma folha (componente conexo) → um cartão no plano dela, com a caixa de UV da folha."""
    nc, lab = componentes(idx, len(pos))
    ordem = np.argsort(lab, kind="stable")
    cortes = np.searchsorted(lab[ordem], np.arange(nc + 1))
    escolha = np.arange(nc) if nc <= manter else np.sort(rng.choice(nc, manter, replace=False))
    escala = max(1.0, float(np.sqrt(nc / max(1, len(escolha))))) * 1.0
    centro_copa = pos.mean(axis=0)
    quads_p, quads_uv, quads_n = [], [], []
    for c in escolha:
        vs = ordem[cortes[c] : cortes[c + 1]]
        if len(vs) < 3:
            continue
        p, t = pos[vs], uv[vs]
        a = np.column_stack([t, np.ones(len(t))])
        x, _res, rank, _sv = np.linalg.lstsq(a, p, rcond=None)
        if rank < 3:
            continue
        lo, hi = t.min(axis=0), t.max(axis=0)
        pad = (hi - lo) * 0.03
        lo, hi = lo - pad, hi + pad
        cuv = np.array([[lo[0], lo[1]], [hi[0], lo[1]], [hi[0], hi[1]], [lo[0], hi[1]]])
        cp = np.column_stack([cuv, np.ones(4)]) @ x
        meio = cp.mean(axis=0)
        cp = meio + (cp - meio) * escala
        nrm = np.cross(cp[1] - cp[0], cp[3] - cp[0])
        ln = np.linalg.norm(nrm)
        if ln < 1e-12:
            continue
        nrm /= ln
        fora = meio - centro_copa
        fora[1] *= 0.6
        fora /= max(np.linalg.norm(fora), 1e-9)
        if nrm @ fora < 0:
            nrm = -nrm
        nv = nrm * 0.4 + fora * 0.6
        nv /= max(np.linalg.norm(nv), 1e-9)
        quads_p.append(cp)
        quads_uv.append(cuv)
        quads_n.append(np.repeat(nv[None, :], 4, axis=0))
    qp = np.concatenate(quads_p)
    quv = np.concatenate(quads_uv)
    qn = np.concatenate(quads_n)
    base = np.arange(len(quads_p)) * 4
    qi = np.column_stack([base, base + 1, base + 2, base, base + 2, base + 3]).reshape(-1, 3)
    return qp, quv, qn, qi, nc, escala


def textura_folha(diff: bytes, uv: np.ndarray, idx: np.ndarray) -> bytes:
    """Cor da folha com alfa = contorno das folhas (UVs das folhas originais) e borda sangrada."""
    big = TEX_PX * 2
    mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(mask)
    tri = uv[idx] * big
    vistos = set()
    for t in tri:
        k = tuple(np.round(t, 1).ravel())
        if k in vistos:
            continue
        vistos.add(k)
        d.polygon([tuple(map(float, q)) for q in t], fill=255)
    mask = mask.resize((TEX_PX, TEX_PX), Image.Resampling.LANCZOS)
    cor = (
        Image.open(io.BytesIO(diff))
        .convert("RGB")
        .resize((TEX_PX, TEX_PX), Image.Resampling.LANCZOS)
    )
    a = np.asarray(mask).astype(np.float64)
    rgb = np.asarray(cor).copy()
    # O fundo da textura do Poly Haven é preto e o contorno das UVs passa um pouco dele: no Studio
    # cada folha saiu com contorno escuro (2026-11-11). O alfa também exige cor (luminância acima
    # do fundo).
    lum = rgb.astype(np.float64).mean(axis=2)
    a = a * np.clip((lum - 8.0) / 14.0, 0.0, 1.0)
    a = ndimage.grey_erosion(a, size=(2, 2)).astype(np.uint8)
    # sangria: cada pixel transparente recebe a cor do pixel de folha mais próximo (sem halo escuro)
    _, (iy, ix) = ndimage.distance_transform_edt(a < 160, return_indices=True)
    rgb = rgb[iy, ix]
    out = Image.fromarray(np.dstack([rgb, a]).astype(np.uint8), "RGBA")
    buf = io.BytesIO()
    out.save(buf, "PNG", optimize=True)
    return buf.getvalue()


# ---------- madeira ----------
def madeira(pos, uv, idx, alvo: int, galho_m: float, soltar: bool = False):
    nc, lab = componentes(idx, len(pos))
    if galho_m > 0 and nc > 1:
        lo = np.full((nc, 3), np.inf)
        hi = np.full((nc, 3), -np.inf)
        np.minimum.at(lo, lab, pos)
        np.maximum.at(hi, lab, pos)
        diag = np.linalg.norm(hi - lo, axis=1)
        fica = diag >= galho_m
        fica[np.argmax(diag)] = True
        sel = fica[lab[idx[:, 0]]]
        idx = idx[sel]
    usados = np.unique(idx)
    novo = np.full(len(pos), -1)
    novo[usados] = np.arange(len(usados))
    pos, uv, idx = pos[usados], uv[usados], novo[idx]
    if len(idx) <= alvo:
        nrm = normais(pos, idx)
        return pos.astype(np.float32), nrm, uv.astype(np.float32), idx.reshape(-1).astype(np.uint32)
    # galho fino é tubo aberto: com a borda presa a redução para longe do alvo (jacarandá)
    return decimate(pos, uv, idx, alvo, soltar)


def normais(pos, idx):
    n = np.zeros_like(pos)
    f = np.cross(pos[idx[:, 1]] - pos[idx[:, 0]], pos[idx[:, 2]] - pos[idx[:, 0]])
    for k in range(3):
        np.add.at(n, idx[:, k], f)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    return n.astype(np.float32)


# ---------- escrita do GLB ----------
class Glb:
    def __init__(self):
        self.js: dict = {
            "asset": {"version": "2.0", "generator": "VT65 prep_trees (D-67)"},
            "scene": 0,
            "scenes": [{"nodes": []}],
            "nodes": [],
            "meshes": [],
            "materials": [],
            "textures": [],
            "images": [],
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
            "accessors": [],
            "bufferViews": [],
            "buffers": [],
        }
        self.chunks: list[bytes] = []
        self.size = 0

    def view(self, data: bytes, target: int | None = None) -> int:
        pad = (-self.size) % 4
        if pad:
            self.chunks.append(b"\x00" * pad)
            self.size += pad
        v = {"buffer": 0, "byteOffset": self.size, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.chunks.append(data)
        self.size += len(data)
        self.js["bufferViews"].append(v)
        return len(self.js["bufferViews"]) - 1

    def accessor(self, arr: np.ndarray, ctype: int, typ: str, target: int, minmax=False) -> int:
        a = {
            "bufferView": self.view(arr.tobytes(), target),
            "componentType": ctype,
            "count": int(arr.shape[0]),
            "type": typ,
        }
        if minmax:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        self.js["accessors"].append(a)
        return len(self.js["accessors"]) - 1

    def texture(self, data: bytes, mime: str) -> int:
        self.js["images"].append({"bufferView": self.view(data), "mimeType": mime})
        self.js["textures"].append({"sampler": 0, "source": len(self.js["images"]) - 1})
        return len(self.js["textures"]) - 1

    def material(self, nome: str, cor: int, normal: int | None, folha: bool) -> int:
        m: dict = {
            "name": nome,
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": cor},
                "metallicFactor": 0.0,
                "roughnessFactor": 0.85,
            },
            "doubleSided": folha,
        }
        if normal is not None:
            m["normalTexture"] = {"index": normal}
        if folha:
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = 0.5
        self.js["materials"].append(m)
        return len(self.js["materials"]) - 1

    def mesh(self, nome: str, pos, nrm, uv, idx, mat: int) -> None:
        idx = np.asarray(idx).reshape(-1)
        use16 = len(pos) < 65536
        prim = {
            "attributes": {
                "POSITION": self.accessor(np.asarray(pos, np.float32), 5126, "VEC3", 34962, True),
                "NORMAL": self.accessor(np.asarray(nrm, np.float32), 5126, "VEC3", 34962),
                "TEXCOORD_0": self.accessor(np.asarray(uv, np.float32), 5126, "VEC2", 34962),
            },
            "indices": self.accessor(
                idx.astype(np.uint16 if use16 else np.uint32),
                5123 if use16 else 5125,
                "SCALAR",
                34963,
            ),
            "material": mat,
        }
        self.js["meshes"].append({"name": nome, "primitives": [prim]})
        self.js["nodes"].append({"name": nome, "mesh": len(self.js["meshes"]) - 1})
        self.js["scenes"][0]["nodes"].append(len(self.js["nodes"]) - 1)

    def bytes(self) -> bytes:
        body = b"".join(self.chunks)
        body += b"\x00" * ((-len(body)) % 4)
        self.js["buffers"] = [{"byteLength": len(body)}]
        jb = json.dumps(self.js, separators=(",", ":")).encode()
        jb += b" " * ((-len(jb)) % 4)
        total = 12 + 8 + len(jb) + 8 + len(body)
        return (
            struct.pack("<4sII", b"glTF", 2, total)
            + struct.pack("<I4s", len(jb), b"JSON")
            + jb
            + struct.pack("<I4s", len(body), b"BIN\x00")
            + body
        )


def partes(pos, nrm, uv, idx, limite: int):
    """Divide uma malha em pedaços de até `limite` triângulos (por faixa de altura)."""
    tri = idx.reshape(-1, 3)
    if len(tri) <= limite:
        return [(pos, nrm, uv, tri.reshape(-1))]
    alt = pos[tri].mean(axis=1)[:, 1]
    ordem = np.argsort(alt)
    out = []
    for k in range(0, len(ordem), limite):
        t = tri[ordem[k : k + limite]]
        usados, inv = np.unique(t.reshape(-1), return_inverse=True)
        out.append((pos[usados], nrm[usados], uv[usados], inv.astype(np.uint32)))
    return out


def textura_bytes(g: Gltf, mat: dict, chave: str) -> bytes | None:
    t = (
        mat.get(chave)
        if chave == "normalTexture"
        else mat.get("pbrMetallicRoughness", {}).get(chave)
    )
    if not t:
        return None
    return g.image_bytes(t["index"])


def normal_compativel(mat: dict) -> bool:
    """O normal só vai junto se usa as mesmas UVs da cor (o Roblox lê um canal de UV)."""
    n = mat.get("normalTexture")
    c = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture", {})
    if not n:
        return False
    return n.get("texCoord", 0) == c.get("texCoord", 0) and n.get("extensions") == c.get(
        "extensions"
    )


def jpeg_1k(data: bytes) -> bytes:
    im = Image.open(io.BytesIO(data)).convert("RGB")
    if max(im.size) > TEX_PX:
        im = im.resize((TEX_PX, TEX_PX), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=92)
    return buf.getvalue()


def previa(pecas, caminho: Path, w: int = 720) -> None:
    """Vista de lado (X por Y) com textura, recorte da folha e luz simples (rasterizador em
    numpy, z-buffer): para conferir a copa antes de subir. Não é o render do Roblox."""
    todos = np.concatenate([p[1] for p in pecas])
    lo, hi = todos.min(axis=0), todos.max(axis=0)
    esc = (w - 20) / max(hi[0] - lo[0], hi[1] - lo[1])
    cor = np.zeros((w, w, 3))
    cor[:] = (226, 222, 210)
    zb = np.full((w, w), -np.inf)
    luz = np.array([0.45, 0.75, 0.5])
    luz /= np.linalg.norm(luz)
    for _nome, pos, nrm, uv, idx, tex in pecas:
        th, tw = tex.shape[:2]
        sx = 10 + (pos[:, 0] - lo[0]) * esc
        sy = w - 10 - (pos[:, 1] - lo[1]) * esc
        for t in idx.reshape(-1, 3):
            x, y, z = sx[t], sy[t], pos[t, 2]
            x0, x1 = int(max(0, np.floor(x.min()))), int(min(w - 1, np.ceil(x.max())))
            y0, y1 = int(max(0, np.floor(y.min()))), int(min(w - 1, np.ceil(y.max())))
            if x1 < x0 or y1 < y0:
                continue
            den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
            if abs(den) < 1e-9:
                continue
            px, py = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            a = ((y[1] - y[2]) * (px - x[2]) + (x[2] - x[1]) * (py - y[2])) / den
            b = ((y[2] - y[0]) * (px - x[2]) + (x[0] - x[2]) * (py - y[2])) / den
            c = 1 - a - b
            dentro = (a >= 0) & (b >= 0) & (c >= 0)
            if not dentro.any():
                continue
            u = a * uv[t[0], 0] + b * uv[t[1], 0] + c * uv[t[2], 0]
            v = a * uv[t[0], 1] + b * uv[t[1], 1] + c * uv[t[2], 1]
            tx = (np.mod(u, 1.0) * (tw - 1)).astype(int)
            ty = (np.mod(v, 1.0) * (th - 1)).astype(int)
            amostra = tex[ty, tx]
            zz = a * z[0] + b * z[1] + c * z[2]
            ok = dentro & (amostra[..., 3] > 127) & (zz > zb[y0 : y1 + 1, x0 : x1 + 1])
            if not ok.any():
                continue
            n = nrm[t].mean(axis=0)
            sh = 0.45 + 0.55 * abs(float(n @ luz))
            reg = cor[y0 : y1 + 1, x0 : x1 + 1]
            reg[ok] = amostra[..., :3][ok] * sh
            zb[y0 : y1 + 1, x0 : x1 + 1][ok] = zz[ok]
    Image.fromarray(np.clip(cor, 0, 255).astype(np.uint8)).save(caminho)


def tex_array(data: bytes) -> np.ndarray:
    return np.asarray(Image.open(io.BytesIO(data)).convert("RGBA").resize((256, 256))).astype(
        np.float64
    )


def preparar(chave: str, cfg: dict) -> dict:
    src = FONTE / cfg["id"] / f"{cfg['id']}.gltf"
    g = Gltf(src)
    prims = primitivas(g, cfg.get("nos"))
    rng = np.random.default_rng(65)
    madeiras = [p for p in prims if not eh_folha(p[0])]
    folhas = [p for p in prims if eh_folha(p[0])]
    # base do tronco: menor Y da madeira; centro XZ dos vértices até 20 cm acima dela
    wpos = np.concatenate([p[1] for p in madeiras])
    y0 = wpos[:, 1].min()
    pe = wpos[wpos[:, 1] < y0 + 0.2]
    origem = np.array([pe[:, 0].mean(), y0, pe[:, 2].mean()])

    glb = Glb()
    pecas_previa = []
    info: dict = {"chave": chave, "fonte": cfg["id"], "pecas": []}

    # tronco (material sem "branch"/"twig") fica com 55% da madeira: proporcional à malha original
    # ele ia a ~360 triângulos e virava um funil
    def eh_galho(m: dict) -> bool:
        nome = m.get("name", "").lower()
        return "branch" in nome or "twig" in nome

    n_galho = sum(1 for p in madeiras if eh_galho(p[0]))
    n_tronco = len(madeiras) - n_galho
    for k, (mat, pos, uv, idx) in enumerate(madeiras):
        if n_galho == 0 or n_tronco == 0:
            alvo = cfg["madeira"] // len(madeiras)
        elif eh_galho(mat):
            alvo = int(cfg["madeira"] * 0.45 / n_galho)
        else:
            alvo = int(cfg["madeira"] * 0.55 / n_tronco)
        p, n, t, i = madeira(pos, uv, idx, alvo, cfg.get("galho_m", 0.0), cfg.get("soltar", False))
        p = (p - origem) / M_POR_STUD
        cor = jpeg_1k(textura_bytes(g, mat, "baseColorTexture"))
        nor = textura_bytes(g, mat, "normalTexture") if normal_compativel(mat) else None
        mi = glb.material(
            f"Madeira{k}",
            glb.texture(cor, "image/jpeg"),
            glb.texture(jpeg_1k(nor), "image/jpeg") if nor else None,
            False,
        )
        for j, (pp, nn, tt, ii) in enumerate(partes(p, n, t, i, MAX_TRIS_PECA)):
            nome = f"Madeira{k}_{j}"
            glb.mesh(nome, pp, nn, tt, ii, mi)
            pecas_previa.append((nome, pp, nn, tt, ii, tex_array(cor)))
            info["pecas"].append({"nome": nome, "tris": int(len(ii) // 3)})
    for k, (mat, pos, uv, idx) in enumerate(folhas):
        manter = int(cfg["folhas"] * len(idx) / max(1, sum(len(f[3]) for f in folhas)))
        qp, quv, qn, qi, n_orig, escala = cartoes(pos, uv, idx, manter, rng)
        qp = (qp - origem) / M_POR_STUD
        png = textura_folha(textura_bytes(g, mat, "baseColorTexture"), uv, idx)
        nor = textura_bytes(g, mat, "normalTexture") if normal_compativel(mat) else None
        mi = glb.material(
            f"Folha{k}",
            glb.texture(png, "image/png"),
            glb.texture(jpeg_1k(nor), "image/jpeg") if nor else None,
            True,
        )
        info["folhas_originais"] = int(n_orig)
        info["escala_folha"] = round(escala, 2)
        for j, (pp, nn, tt, ii) in enumerate(partes(qp, qn, quv, qi.reshape(-1), MAX_TRIS_PECA)):
            nome = f"Folhas{k}_{j}"
            glb.mesh(nome, pp, nn, tt, ii, mi)
            pecas_previa.append((nome, pp, nn, tt, ii, tex_array(png)))
            info["pecas"].append({"nome": nome, "tris": int(len(ii) // 3)})
    SAIDA.mkdir(parents=True, exist_ok=True)
    data = glb.bytes()
    (SAIDA / f"{chave}.glb").write_bytes(data)
    previa(pecas_previa, SAIDA / f"{chave}_previa.png")
    todos = np.concatenate([p[1] for p in pecas_previa])
    dim = (todos.max(axis=0) - todos.min(axis=0)) * M_POR_STUD
    info["tris"] = sum(p["tris"] for p in info["pecas"])
    info["dim_m_xyz"] = [round(float(x), 2) for x in dim]
    info["mb"] = round(len(data) / 2**20, 2)
    return info


def main() -> None:
    chaves = sys.argv[1:] or list(ESPECIES)
    for c in chaves:
        print(json.dumps(preparar(c, ESPECIES[c]), ensure_ascii=False))


if __name__ == "__main__":
    main()
