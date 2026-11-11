"""Facas do VẠN TƯỜNG '65: modela, assa as texturas PBR e exporta o GLB de cada chave.

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/faca/produzir.py -- kabar m6 type56 dao

Por chave:
1. malha procedural (`modelos.py`, mm) -> Blender (m), com as UVs "local" e "costura", os
   atributos e as arestas vivas (normais divididas nas quinas, suaves no resto);
2. atlas único 1024 x 1024: ilhas com a densidade de texels pedida por peça (lâmina e cabo com
   mais texels que a bainha) e empacotamento côncavo com rotação;
3. bake na própria malha (Cycles, CPU): cor e (rugosidade, metal) como emissão, normal em espaço
   tangente (OpenGL, Y+) com o relevo procedural e oclusão ambiente. A bainha é afastada 0,25 m
   durante o bake, com uma cópia do cabo dentro dela só para a oclusão (a tira e a presilha
   escurecem onde encostam no cabo);
4. a oclusão multiplica a cor (o Roblox não tem canal de oclusão) e sobe a rugosidade nas frestas;
   metal/rugosidade: R = 1, G = rugosidade, B = metal;
5. GLB em studs, Y para cima, nós `Faca` e `Bainha` (a bainha leva o cabo da faca embainhada);
6. `pontos.json`: pontos no referencial local da MeshPart, medidos relendo o GLB.

Saídas: assets/facas/<chave>.glb, assets/facas/pontos.json e as texturas em
assets/facas/_trabalho/<chave>/.
"""

from __future__ import annotations

import json
import math
import struct
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(RAIZ / "tools" / "blender"))
import comum  # noqa: E402
import materiais  # noqa: E402
import modelos  # noqa: E402
from malha import LONGE  # noqa: E402

SAIDA = RAIZ / "assets" / "facas"
TRAB = SAIDA / "_trabalho"
M_POR_STUD = 0.28
TEX = 1024
AFASTA = 0.25  # m: bainha longe da faca durante o bake
FORCA_AO = 0.55
ANGULO_VIVO = 55.0  # graus: acima disso a aresta também fica dura


def log(*a) -> None:
    print("[FACA]", *a, flush=True)


# ------------------------------------------------------------------ cena
def cena_cpu() -> bpy.types.Scene:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cena = bpy.context.scene
    cena.render.engine = "CYCLES"
    cena.cycles.device = "CPU"  # a GPU de 2 GB do PC do dono já travou com render pesado
    cena.cycles.use_denoising = False
    if cena.world is None:
        cena.world = bpy.data.worlds.new("Mundo")
    return cena


# ------------------------------------------------------------------ malha -> Blender
def partir_ilhas(m, fracao: float = 0.45) -> np.ndarray:
    """Ilha por face, partindo as ilhas mais compridas que `fracao` do lado do atlas (raiz da
    área total ponderada): uma lâmina ou um espigão inteiro numa ilha só deixa o atlas com uma
    faixa usada. A UV local continua a mesma; cada pedaço vira ilha separada no empacotamento."""
    ilha = np.array(m.ilha)
    peso = np.array(m.pesos)[ilha]
    cent, area = [], []
    for uvs, w in zip(m.uv, peso, strict=True):
        a = np.array(uvs) * w
        cent.append(a.mean(axis=0))
        x, y = a[:, 0], a[:, 1]
        area.append(0.5 * abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))))
    cent = np.array(cent)
    lmax = fracao * math.sqrt(sum(area))
    out = ilha.copy()
    prox = int(ilha.max()) + 1
    for iid in np.unique(ilha):
        fs = np.where(ilha == iid)[0]
        pts = np.vstack([np.array(m.uv[i]) * m.pesos[iid] for i in fs])
        ext = pts.max(axis=0) - pts.min(axis=0)
        eixo = int(np.argmax(ext))
        n = math.ceil(ext[eixo] / lmax)
        if n <= 1:
            continue
        c = cent[fs, eixo]
        b = np.clip(((c - pts[:, eixo].min()) / ext[eixo] * n).astype(int), 0, n - 1)
        for k in range(1, n):
            out[fs[b == k]] = prox
            prox += 1
    return out


def para_blender(m, nome: str) -> bpy.types.Object:
    V = np.array(m.v) * 0.001
    me = bpy.data.meshes.new(nome)
    me.from_pydata(V.tolist(), [], m.f)
    me.update(calc_edges=True)
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    if len(me.polygons) != len(m.f) or not np.array_equal(lv, np.concatenate(m.f)):
        raise RuntimeError(f"{nome}: o Blender mudou as faces")
    ilha_f = partir_ilhas(m)
    ilha_l = np.repeat(ilha_f, [len(f) for f in m.f])
    loc = np.array([uv for f in m.uv for uv in f])
    cs = np.array([c for f in m.cs for c in f])
    peso = np.repeat(np.array(m.pesos)[np.array(m.ilha)], [len(f) for f in m.f])
    atlas = loc * peso[:, None] + np.column_stack([ilha_l * 4000.0, np.zeros(len(ilha_l))])
    for nm, arr in (("UVMap", atlas), ("local", loc), ("costura", cs)):
        camada = me.uv_layers.new(name=nm)
        camada.data.foreach_set("uv", arr.astype(np.float32).ravel())
    me.uv_layers.active = me.uv_layers["UVMap"]
    me.uv_layers["UVMap"].active_render = True
    me.polygons.foreach_set("material_index", np.array(m.mat, np.int32))
    for nm, arr in (("no", m.no), ("dup", m.dup), ("ilha", m.ilha)):
        a = me.attributes.new(nm, "INT", "FACE")
        a.data.foreach_set("value", np.array(arr, np.int32))
    for nm, d in m.attr.items():
        vals = np.full(len(V), LONGE, np.float32)
        for k, v in d.items():
            vals[k] = v
        a = me.attributes.new(nm, "FLOAT", "POINT")
        a.data.foreach_set("value", vals)
    obj = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def triangular_e_vivas(obj: bpy.types.Object, vivas: set) -> int:
    """Triangula (as tangentes do bake e do Roblox saem dos mesmos triângulos) e marca as
    arestas duras: ângulo > ANGULO_VIVO e as vivas da construção."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(me)
    bm.free()
    me.update()
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(ANGULO_VIVO))
    ev = np.empty(len(me.edges) * 2, np.int64)
    me.edges.foreach_get("vertices", ev)
    ev = np.sort(ev.reshape(-1, 2), axis=1)
    attr = me.attributes.get("sharp_edge") or me.attributes.new("sharp_edge", "BOOLEAN", "EDGE")
    duro = np.zeros(len(me.edges), bool)
    attr.data.foreach_get("value", duro)
    chave = ev[:, 0] * 10_000_000 + ev[:, 1]
    vv = np.array(sorted(vivas), np.int64) if vivas else np.zeros((0, 2), np.int64)
    if len(vv):
        duro |= np.isin(chave, vv[:, 0] * 10_000_000 + vv[:, 1])
    attr.data.foreach_set("value", duro)
    me.update()
    return int(duro.sum())


def empacotar(obj: bpy.types.Object) -> float:
    comum.selecionar_so(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(
        rotate=True, scale=True, margin_method="FRACTION", margin=0.006, shape_method="CONCAVE"
    )
    bpy.ops.object.mode_set(mode="OBJECT")
    return comum.uso_uv(obj)


def extrair(obj: bpy.types.Object, nome: str, filtro) -> bpy.types.Object | None:
    """Cópia só com as faces em que filtro(no, dup) é verdadeiro."""
    o = obj.copy()
    o.data = obj.data.copy()
    o.name = nome
    o.data.name = nome
    bm = bmesh.new()
    bm.from_mesh(o.data)
    ln = bm.faces.layers.int.get("no")
    ld = bm.faces.layers.int.get("dup")
    fora = [f for f in bm.faces if not filtro(f[ln], f[ld])]
    if len(fora) == len(bm.faces):
        bm.free()
        return None
    bmesh.ops.delete(bm, geom=fora, context="FACES")
    soltos = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=soltos, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    bpy.context.scene.collection.objects.link(o)
    return o


# ------------------------------------------------------------------ bake
def imagem(nome: str, dados: bool) -> bpy.types.Image:
    img = bpy.data.images.new(nome, TEX, TEX, alpha=True, float_buffer=True)
    img.generated_color = (0.0, 0.0, 0.0, 0.0)
    img.colorspace_settings.name = "Non-Color" if dados else "Linear Rec.709"
    return img


def assar(cena, alvos, mats: dict) -> dict:
    """Passes cor, rm, normal e AO nos objetos `alvos` (selecionados), para o mesmo atlas."""
    imgs = {k: imagem(k, k != "cor") for k in ("cor", "rm", "nrm", "ao")}
    nos_alvo = {}
    for nome, (mat, _) in mats.items():
        nt = mat.node_tree
        no = nt.nodes.new("ShaderNodeTexImage")
        no.name = "alvo"
        nos_alvo[nome] = no
    tempos = {}
    for passe, tipo, saida, amostras in (
        ("cor", "EMIT", "cor", 16),
        ("rm", "EMIT", "rm", 16),
        ("nrm", "NORMAL", "bsdf", 16),
        ("ao", "AO", "liso", 64),
    ):
        t0 = time.time()
        for nome, (mat, s) in mats.items():
            mat.node_tree.links.new(s[saida], s["saida"].inputs["Surface"])
            no = nos_alvo[nome]
            no.image = imgs[passe]
            for n in mat.node_tree.nodes:
                n.select = False
            no.select = True
            mat.node_tree.nodes.active = no
        cena.cycles.samples = amostras
        comum.selecionar_so(alvos[0], alvos[1:])
        kw = {
            "type": tipo,
            "use_selected_to_active": False,
            "margin": 12,
            "margin_type": "EXTEND",
            "use_clear": True,
            "target": "IMAGE_TEXTURES",
            "uv_layer": "UVMap",
        }
        if tipo == "NORMAL":
            kw.update(normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y", normal_b="POS_Z")
        bpy.ops.object.bake(**kw)
        tempos[passe] = round(time.time() - t0, 1)
        log("bake", passe, tempos[passe], "s")
    for mat, s in mats.values():
        mat.node_tree.links.new(s["bsdf"], s["saida"].inputs["Surface"])
    return {"imgs": imgs, "tempos": tempos}


def px(img) -> np.ndarray:
    return comum.pixels(img).copy()


def salvar_byte(nome: str, arr: np.ndarray, caminho: Path, formato: str, dados: bool) -> bytes:
    img = bpy.data.images.new(nome, TEX, TEX, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if dados else "sRGB"
    a = np.ones((TEX, TEX, 4), np.float32)
    a[..., :3] = np.clip(arr, 0.0, 1.0)
    comum.gravar_pixels(img, a)
    return comum.salvar_imagem(img, caminho, formato, 92)


def compor(imgs: dict, trab: Path) -> tuple[dict, dict]:
    cor = px(imgs["cor"])
    rm = px(imgs["rm"])
    nrm = px(imgs["nrm"])
    ao = px(imgs["ao"])[..., 0]
    cob = cor[..., 3] > 0.5
    info = {"cobertura": round(float(cob.mean()), 4)}
    lin = cor[..., :3] * (1 - FORCA_AO + FORCA_AO * ao)[..., None]
    lin[~cob] = lin[cob].mean(axis=0)
    rug = np.clip(rm[..., 0] + (1 - ao) * 0.06, 0.04, 1.0)
    met = np.clip(rm[..., 1], 0.0, 1.0)
    rug[~cob] = rug[cob].mean()
    met[~cob] = 0.0
    n3 = nrm[..., :3].copy()
    n3[~cob] = (0.5, 0.5, 1.0)
    mr = np.stack([np.ones_like(rug), rug, met], axis=-1)
    trab.mkdir(parents=True, exist_ok=True)
    texturas = {
        "cor": (
            salvar_byte("t_cor", comum.linear_para_srgb(lin), trab / "cor.jpg", "JPEG", False),
            "image/jpeg",
        ),
        "normal": (salvar_byte("t_nrm", n3, trab / "normal.png", "PNG", True), "image/png"),
        "mr": (salvar_byte("t_mr", mr, trab / "metal_rug.png", "PNG", True), "image/png"),
    }
    salvar_byte("t_ao", np.repeat(ao[..., None], 3, axis=2), trab / "ao.png", "PNG", True)
    info["ao_media"] = round(float(ao[cob].mean()), 3)
    info["metal_medio"] = round(float(met[cob].mean()), 3)
    info["rug_media"] = round(float(rug[cob].mean()), 3)
    return texturas, info


# ------------------------------------------------------------------ GLB e pontos
def ler_nos(caminho: Path) -> dict[str, np.ndarray]:
    """Posições (studs, glTF) de cada nó com malha, relendo o GLB."""
    data = caminho.read_bytes()
    n, _ = struct.unpack_from("<I4s", data, 12)
    js = json.loads(data[20 : 20 + n])
    off = 20 + n
    nb, _ = struct.unpack_from("<I4s", data, off)
    binb = data[off + 8 : off + 8 + nb]
    out = {}
    for no in js["nodes"]:
        if "mesh" not in no:
            continue
        if any(k in no for k in ("matrix", "translation", "rotation", "scale")):
            raise RuntimeError(f"{caminho.name}: nó {no['name']} com transformação")
        pts = []
        for prim in js["meshes"][no["mesh"]]["primitives"]:
            acc = js["accessors"][prim["attributes"]["POSITION"]]
            bv = js["bufferViews"][acc["bufferView"]]
            ini = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            pts.append(np.frombuffer(binb, np.float32, acc["count"] * 3, ini).reshape(-1, 3))
        out[no["name"]] = np.vstack(pts).astype(np.float64)
    return out


def para_roblox(p_mm, c: np.ndarray) -> list[float]:
    """mm do Blender -> studs no referencial local da MeshPart (180° em Y, centro da caixa)."""
    x, y, z = p_mm
    g = np.array([x, z, -y]) * 0.001 / M_POR_STUD  # glTF
    r = np.array([-g[0], g[1], -g[2]]) - c
    return [round(float(v), 4) for v in r]


def medir(mo, caminho: Path) -> dict:
    nos = ler_nos(caminho)
    out: dict = {}
    for nome, pts in nos.items():
        R = pts * np.array([-1.0, 1.0, -1.0])
        lo, hi = R.min(axis=0), R.max(axis=0)
        c = (lo + hi) / 2
        d: dict = {"tamanho": [round(float(v), 4) for v in hi - lo]}
        conf = {}
        for k, v in mo.pontos[nome].items():
            if k.endswith("_mm"):
                d[k[:-3] + "_m"] = round(v / 1000, 4)
            elif k == "fio":
                d["fio"] = [round(float(-v[0]), 4), round(float(v[2]), 4), round(float(v[1]), 4)]
            else:
                d[k] = para_roblox(v, c)
        # conferência contra os vértices do GLB
        conf["ponta_vs_vertice_mais_a_frente"] = round(d["ponta"][2] - float(lo[2] - c[2]), 4)
        if nome == "Faca":
            conf["pomo_vs_vertice_mais_atras"] = round(d["pomo"][2] - float(hi[2] - c[2]), 4)
            conf["comprimento_glb_m"] = round(float(hi[2] - lo[2]) * M_POR_STUD, 4)
        if nome == "Bainha":
            d["cabo_para_fora"] = True
        d["_conferencia"] = conf
        out[nome] = d
    return out


def produzir(chave: str) -> dict:
    t0 = time.time()
    cena = cena_cpu()
    mo = modelos.MODELOS[chave]()
    m = mo.malha
    log(chave, "triângulos: Faca", m.n_tris(0), "Bainha", m.n_tris(1))
    obj = para_blender(m, chave)
    mats = {nome: materiais.criar(nome) for nome in m.materiais}
    for nome in m.materiais:
        obj.data.materials.append(mats[nome][0])
    nv = triangular_e_vivas(obj, m.vivas)
    uso = empacotar(obj)
    log("arestas duras", nv, "uso da UV", uso)
    faca = extrair(obj, "Faca", lambda no, dup: no == 0)
    corpo = extrair(obj, "BainhaCorpo", lambda no, dup: no == 1)
    ocl = extrair(obj, "Oclusor", lambda no, dup: dup == 1) if corpo else None
    bpy.data.objects.remove(obj)
    alvos = [faca]
    if corpo:
        corpo.location.x += AFASTA
        ocl.location.x += AFASTA
        alvos.append(corpo)
    cena.world.light_settings.distance = 0.012
    bk = assar(cena, alvos, mats)
    texturas, info_tex = compor(bk["imgs"], TRAB / chave)
    partes = [("Faca", faca)]
    if corpo:
        corpo.location.x = 0.0
        ocl.location.x = 0.0
        comum.selecionar_so(corpo, [ocl])
        bpy.ops.object.join()
        corpo.name = "Bainha"
        partes.append(("Bainha", corpo))
    caminho = SAIDA / f"{chave}.glb"
    exp = comum.exportar_glb(partes, caminho, texturas, metal=True)
    tris = {nome: len(comum.arrays_malha(o)[3]) // 3 for nome, o in partes}
    pts = medir(mo, caminho)
    res = {**pts, "triangulos": tris, "texturas_px": TEX, "mb": exp["mb"]}
    log(chave, json.dumps(res, ensure_ascii=False))
    log(
        chave,
        "texturas",
        info_tex,
        "bake",
        bk["tempos"],
        "uso_uv",
        uso,
        "info",
        mo.info,
        f"total {time.time() - t0:.0f} s",
    )
    return res


def main() -> None:
    args = comum.argumentos() or list(modelos.MODELOS)
    caminho = SAIDA / "pontos.json"
    todos = json.loads(caminho.read_text("utf-8")) if caminho.is_file() else {}
    todos["_leia"] = (
        "Studs no referencial local de cada MeshPart (o importador gira o GLB 180° em Y e centra "
        "a peça na caixa dos vértices do nó): ponta para -Z, fio para -Y. Faca: punho (centro da "
        "pega), guarda (junção lâmina/guarda), ponta, pomo, fio (vetor unitário dorso->fio). "
        "Bainha: boca, presilha (onde pendura no cinto), ponta. _conferencia: diferença (studs) "
        "para os vértices extremos do GLB relido."
    )
    for chave in args:
        todos[chave] = produzir(chave)
        SAIDA.mkdir(parents=True, exist_ok=True)
        caminho.write_text(json.dumps(todos, ensure_ascii=False, indent=1) + "\n", "utf-8")
    log("pontos.json gravado", caminho)


if __name__ == "__main__":
    main()
