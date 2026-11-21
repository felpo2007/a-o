"""Funções comuns da linha de produção de assets no Blender (VẠN TƯỜNG '65).

Roda DENTRO do Python do Blender (importa bpy, bmesh e mathutils). Os scripts de etapa
(`refazer.py`, `novos.py`, `comparar.py`) põem esta pasta no sys.path e importam daqui.

Convenções:
- o trabalho é em METROS, Z para cima (Blender); a exportação (`exportar_glb`) converte para
  studs (1 stud = 0,28 m), Y para cima, com o escritor de `glb.py` (mesma convenção do
  tools/prep_trees.py);
- base no chão (Z mínimo = 0) e pivô no centro da base (origem), como os modelos preparados;
- sem metal em material que não é metal: a textura de metal/rugosidade leva B = 0;
- texturas de até 1024 px (512 para objeto pequeno).

Etapas de malha: `limpar` (vértices duplicados e soltos, faces degeneradas, duplicadas, internas e
escondidas), `reduzir` (dissolução planar + colapso), `desvio` (distância entre superfícies),
`desdobrar` (UV nova) e o bake (`assar`): cor, normal, oclusão ambiente, rugosidade e metal.
"""

from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glb  # noqa: E402

RAIZ = Path(__file__).resolve().parents[2]
MODELOS = RAIZ / "assets" / "forgegui" / "models"
SAIDA = RAIZ / "assets" / "blender"
TRABALHO = SAIDA / "_trabalho"
CEU = RAIZ / "assets" / "ceu" / "kloofendal_48d_partly_cloudy_puresky.jpg"
M_POR_STUD = glb.M_POR_STUD

# metas do dono (triângulos por malha) e resolução da textura por classe
CLASSES = {
    "pequeno": {"teto": 1500, "tex": 512},
    "prop": {"teto": 5000, "tex": 1024},
    "construcao": {"teto": 8000, "tex": 1024},
    "animal": {"teto": 5000, "tex": 1024},
}


# ---------------------------------------------------------------- argumentos e cena
def argumentos() -> list[str]:
    """Argumentos depois do `--` na linha do Blender."""
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def log(*a) -> None:
    print("[VT65]", *a, flush=True)


def cena_vazia() -> bpy.types.Scene:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cena = bpy.context.scene
    cena.render.engine = "CYCLES"
    cena.unit_settings.system = "METRIC"
    usar_gpu(cena)
    return cena


def so_cpu() -> bool:
    """VT65_CPU=1 no ambiente: nada na GPU (o dono está jogando no mesmo PC). Cycles na CPU com
    no máximo VT65_THREADS linhas (padrão 4)."""
    import os

    return os.environ.get("VT65_CPU", "") not in ("", "0")


def usar_gpu(cena: bpy.types.Scene) -> str:
    """Liga a GPU no Cycles (OptiX, senão CUDA, senão CPU). Com VT65_CPU=1, só CPU e 4 linhas."""
    if so_cpu():
        import os

        cena.cycles.device = "CPU"
        cena.render.threads_mode = "FIXED"
        cena.render.threads = int(os.environ.get("VT65_THREADS", "4"))
        return "CPU"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for tipo in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = tipo
        except TypeError:
            continue
        prefs.get_devices()
        dispositivos = [d for d in prefs.devices if d.type == tipo]
        if dispositivos:
            for d in prefs.devices:
                d.use = d.type == tipo
            cena.cycles.device = "GPU"
            return tipo
    cena.cycles.device = "CPU"
    return "CPU"


def nova_colecao_objeto(obj: bpy.types.Object) -> bpy.types.Object:
    bpy.context.scene.collection.objects.link(obj)
    return obj


def selecionar_so(obj: bpy.types.Object | None, extras=()) -> None:
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in extras:
        o.select_set(True)
    if obj is not None:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj


def novo_material(nome: str) -> bpy.types.Material:
    mat = bpy.data.materials.new(nome)
    if hasattr(mat, "use_nodes") and not mat.use_nodes:
        mat.use_nodes = True
    return mat


# ---------------------------------------------------------------- importação
def importar_glb(caminho: Path, em_metros: bool = True) -> bpy.types.Object:
    """Importa um GLB e devolve UM objeto de malha com as transformações aplicadas.

    O GLB do jogo está em studs; com `em_metros` a malha é escalada para metros (x 0,28)."""
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(caminho))
    novos = [o for o in bpy.data.objects if o not in antes]
    malhas = [o for o in novos if o.type == "MESH"]
    if not malhas:
        raise RuntimeError(f"{caminho}: sem malha")
    for o in malhas:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy() if o.data.users > 1 else o.data
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in novos:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    obj = malhas[0]
    if len(malhas) > 1:
        selecionar_so(obj, malhas)
        bpy.ops.object.join()
    if em_metros:
        obj.data.transform(Matrix.Scale(M_POR_STUD, 4))
    obj.name = caminho.stem
    return obj


# ---------------------------------------------------------------- malha
def triangulos(obj: bpy.types.Object) -> int:
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def caixa(obj: bpy.types.Object) -> tuple[np.ndarray, np.ndarray]:
    co = np.empty(len(obj.data.vertices) * 3, np.float64)
    obj.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    return co.min(axis=0), co.max(axis=0)


def diagonal(obj: bpy.types.Object) -> float:
    lo, hi = caixa(obj)
    return float(np.linalg.norm(hi - lo))


def aplicar_modificadores(obj: bpy.types.Object) -> None:
    """Aplica a pilha de modificadores sem depender do contexto da interface."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    velho = obj.data
    obj.modifiers.clear()
    obj.data = me
    if velho.users == 0:
        bpy.data.meshes.remove(velho)


def triangular(obj: bpy.types.Object) -> None:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def copiar(obj: bpy.types.Object, nome: str) -> bpy.types.Object:
    o = obj.copy()
    o.data = obj.data.copy()
    o.name = nome
    o.modifiers.clear()
    return nova_colecao_objeto(o)


def direcoes_esfera(n: int) -> list[Vector]:
    """n direções quase uniformes (espiral de Fibonacci)."""
    out = []
    ouro = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        y = 1 - (i + 0.5) / n * 2
        r = math.sqrt(max(0.0, 1 - y * y))
        t = ouro * i
        out.append(Vector((math.cos(t) * r, math.sin(t) * r, y)))
    return out


def limpar(obj: bpy.types.Object, escondidas: bool = True, n_dir: int = 320) -> dict:
    """Limpeza: funde vértices duplicados, tira soltos, faces degeneradas, duplicadas, internas
    (todas as arestas com mais de 2 faces) e, com `escondidas`, faces que não enxergam o lado de
    fora em nenhuma de `n_dir` direções, saindo do centro e de dois anéis de pontos até perto
    dos cantos (casca escondida dentro do modelo). Com menos direções e pontos, faces vistas só
    por uma fresta (o forro da cozinha, visto pelo vão do telhado) saíam por engano."""
    diag = diagonal(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    v0, f0 = len(bm.verts), len(bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=max(1e-5, diag * 2e-5))
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=max(1e-6, diag * 1e-6))
    vistos: dict[frozenset, int] = {}
    dup = []
    for f in bm.faces:
        k = frozenset(v.index for v in f.verts)
        if k in vistos:
            dup.append(f)
        else:
            vistos[k] = f.index
    bmesh.ops.delete(bm, geom=dup, context="FACES")
    internas = [f for f in bm.faces if all(len(e.link_faces) > 2 for e in f.edges)]
    bmesh.ops.delete(bm, geom=internas, context="FACES")
    n_esc = 0
    if escondidas:
        bm.faces.ensure_lookup_table()
        bvh = BVHTree.FromBMesh(bm)
        dirs = direcoes_esfera(n_dir)
        alcance = diag * 3
        eps = diag * 2e-4
        esc = []
        for f in bm.faces:
            n = f.normal
            if n.length < 0.5:
                continue
            c = f.calc_center_median()
            pontos = [c] + [c.lerp(v.co, t) for t in (0.5, 0.92) for v in f.verts]
            ve = False
            for p in pontos:
                o = p + n * eps
                for d in dirs:
                    if d.dot(n) <= 0.02:
                        continue
                    if bvh.ray_cast(o, d, alcance)[0] is None:
                        ve = True
                        break
                if ve:
                    break
            if not ve:
                esc.append(f)
        n_esc = len(esc)
        bmesh.ops.delete(bm, geom=esc, context="FACES")
    soltas_e = [e for e in bm.edges if not e.link_faces]
    bmesh.ops.delete(bm, geom=soltas_e, context="EDGES")
    soltos_v = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=soltos_v, context="VERTS")
    v1, f1 = len(bm.verts), len(bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return {
        "vertices_antes": v0,
        "vertices_depois": v1,
        "faces_antes": f0,
        "faces_duplicadas": len(dup),
        "faces_internas": len(internas),
        "faces_escondidas": n_esc,
        "faces_depois": f1,
    }


def tirar_normais_custom(obj: bpy.types.Object) -> None:
    """Tira as normais de canto importadas (o sombreamento passa a vir do ângulo das faces)."""
    me = obj.data
    if not me.has_custom_normals:
        return
    if "custom_normal" in me.attributes:
        me.attributes.remove(me.attributes["custom_normal"])
    if me.has_custom_normals:
        selecionar_so(obj)
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.mesh.customdata_custom_splitnormals_clear()


def reduzir(obj: bpy.types.Object, alvo: int, planar_graus: float = 1.0) -> int:
    """Redução: dissolução planar (faces quase coplanares viram uma) e colapso de arestas
    (quádricas) até `alvo` triângulos. A UV e os materiais saem antes (a UV é refeita)."""
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    tirar_normais_custom(obj)
    m = obj.modifiers.new("planar", "DECIMATE")
    m.decimate_type = "DISSOLVE"
    m.angle_limit = math.radians(planar_graus)
    m.use_dissolve_boundaries = False
    aplicar_modificadores(obj)
    triangular(obj)
    n = triangulos(obj)
    for _ in range(4):
        if n <= alvo * 1.01:
            break
        m = obj.modifiers.new("colapso", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = max(0.01, alvo / n)
        m.use_collapse_triangulate = True
        aplicar_modificadores(obj)
        triangular(obj)
        n = triangulos(obj)
    return n


def normais_para_fora(obj: bpy.types.Object) -> None:
    """Refaz a orientação das faces para fora (só para malha fechada: os assets novos). O colapso
    às vezes vira triângulos em dobras finas (orelha do saco) e, com face única, eles somem."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def suavizar(obj: bpy.types.Object, angulo_graus: float = 60.0) -> None:
    """Sombreamento suave com aresta dura acima do ângulo (casa com as costuras da UV)."""
    me = obj.data
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(angulo_graus))


def amostrar_superficie(obj: bpy.types.Object, n: int, rng) -> np.ndarray:
    me = obj.data
    me.calc_loop_triangles()
    co = np.empty(len(me.vertices) * 3, np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    tv = np.empty(len(me.loop_triangles) * 3, np.int64)
    me.loop_triangles.foreach_get("vertices", tv)
    tv = tv.reshape(-1, 3)
    a, b, c = co[tv[:, 0]], co[tv[:, 1]], co[tv[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    i = rng.choice(len(tv), n, p=area / area.sum())
    r1, r2 = rng.random(n), rng.random(n)
    s = np.sqrt(r1)
    u, v, w = 1 - s, s * (1 - r2), s * r2
    return a[i] * u[:, None] + b[i] * v[:, None] + c[i] * w[:, None]


def bvh_de(obj: bpy.types.Object) -> BVHTree:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def desvio(a: bpy.types.Object, b: bpy.types.Object, n: int = 15000, seed: int = 65) -> dict:
    """Desvio geométrico entre superfícies (m), nos dois sentidos: pontos sorteados por área
    em A até a superfície de B e vice-versa. `max` ~ distância de Hausdorff."""
    rng = np.random.default_rng(seed)
    ta, tb = bvh_de(a), bvh_de(b)

    def dist(pts, t):
        return np.array([t.find_nearest(Vector(p))[3] for p in pts], np.float64)

    d_ab = dist(amostrar_superficie(a, n, rng), tb)
    d_ba = dist(amostrar_superficie(b, n, rng), ta)
    d = np.concatenate([d_ab, d_ba])
    return {
        "media_m": round(float(d.mean()), 5),
        "p95_m": round(float(np.percentile(d, 95)), 5),
        "p99_m": round(float(np.percentile(d, 99)), 5),
        "max_m": round(float(d.max()), 5),
        "novo_ao_antigo_p99_m": round(float(np.percentile(d_ba, 99)), 5),
    }


def ilhas_uv(bm: bmesh.types.BMesh, uvl) -> list[list]:
    """Ilhas de UV: faces ligadas por arestas com a mesma UV nos dois lados."""
    vistos: set = set()
    out = []
    for f in bm.faces:
        if f in vistos:
            continue
        ilha = []
        pilha = [f]
        while pilha:
            g = pilha.pop()
            if g in vistos:
                continue
            vistos.add(g)
            ilha.append(g)
            for lp in g.loops:
                h_lp = lp.link_loop_radial_next
                h = h_lp.face
                if h is g or h in vistos:
                    continue
                # mesma aresta vista pelas duas faces: compara a UV de cada vértice
                a1, b1 = lp[uvl].uv, lp.link_loop_next[uvl].uv
                if h_lp.vert is lp.vert:
                    a2, b2 = h_lp[uvl].uv, h_lp.link_loop_next[uvl].uv
                else:
                    a2, b2 = h_lp.link_loop_next[uvl].uv, h_lp[uvl].uv
                if (a1 - a2).length < 1e-6 and (b1 - b2).length < 1e-6:
                    pilha.append(h)
        out.append(ilha)
    return out


def abertura_faces(obj: bpy.types.Object, n_dir: int = 48, z_chao: float | None = 0.0):
    """Fração do hemisfério de cada face que enxerga o céu (0 = fechada, 1 = toda aberta).

    Raios para baixo batem no chão em `z_chao` (None = sem chão). Serve para dar menos textura ao
    que quase não aparece (frestas, contato entre sacos, pé encostado no chão)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    bvh = BVHTree.FromBMesh(bm)
    diag = diagonal(obj)
    alcance = diag * 3
    eps = diag * 2e-4
    dirs = direcoes_esfera(n_dir)
    out = np.zeros(len(bm.faces), np.float64)
    for f in bm.faces:
        n = f.normal
        if n.length < 0.5:
            continue
        o = f.calc_center_median() + n * eps
        ok = tot = 0
        for d in dirs:
            if d.dot(n) <= 0.05:
                continue
            tot += 1
            if z_chao is not None and d.z < -0.02:
                continue
            if bvh.ray_cast(o, d, alcance)[0] is None:
                ok += 1
        out[f.index] = ok / max(1, tot)
    bm.free()
    return out


def desdobrar(
    obj: bpy.types.Object,
    margem: float = 0.004,
    angulo_graus: float = 66.0,
    base_escala: float = 0.3,
    visibilidade: bool = True,
    abertura_cheia: float = 0.25,
    escala_min: float = 0.6,
) -> int:
    """UV nova: projeção inteligente (ilhas por ângulo) e empacotamento côncavo com rotação.

    Antes do empacotamento cada ilha muda de tamanho conforme o quanto aparece:
    - ilhas só de faces viradas para baixo, no pé do modelo (escondidas no chão): `base_escala`;
    - com `visibilidade`, ilhas com abertura média (céu visto) abaixo de `abertura_cheia`
      encolhem até `escala_min` (raiz da abertura): frestas e contatos ganham menos texels e o
      que aparece ganha mais. Devolve o número de ilhas."""
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    selecionar_so(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(
        angle_limit=math.radians(angulo_graus),
        margin_method="FRACTION",
        island_margin=margem,
        area_weight=0.0,
        correct_aspect=True,
        scale_to_bounds=False,
    )
    bpy.ops.object.mode_set(mode="OBJECT")
    lo, hi = caixa(obj)
    abert = abertura_faces(obj, z_chao=float(lo[2])) if visibilidade else None
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    ilhas = ilhas_uv(bm, uvl)
    z_pe = lo[2] + 0.1 * (hi[2] - lo[2])
    for ilha in ilhas:
        par = [(f, f.calc_area()) for f in ilha]
        area = sum(a for _, a in par) or 1.0
        nz = sum(f.normal.z * a for f, a in par) / area
        zc = sum(f.calc_center_median().z * a for f, a in par) / area
        s = 1.0
        if abert is not None:
            ab = sum(abert[f.index] * a for f, a in par) / area
            s = float(np.clip(math.sqrt(ab / abertura_cheia), escala_min, 1.0))
        if nz < -0.6 and zc < z_pe:
            s = min(s, base_escala)
        if s < 0.999:
            uvs = [lp[uvl] for f in ilha for lp in f.loops]
            c = sum((u.uv for u in uvs), Vector((0.0, 0.0))) / len(uvs)
            for u in uvs:
                u.uv = c + (u.uv - c) * s
    bm.to_mesh(me)
    bm.free()
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(
        rotate=True, margin_method="FRACTION", margin=margem, shape_method="CONCAVE"
    )
    bpy.ops.object.mode_set(mode="OBJECT")
    return len(ilhas)


def uso_uv(obj: bpy.types.Object) -> float:
    """Fração do quadrado de UV coberta por triângulos (eficiência do empacotamento)."""
    me = obj.data
    me.calc_loop_triangles()
    uv = np.empty(len(me.loops) * 2, np.float64)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    tl = np.empty(len(me.loop_triangles) * 3, np.int64)
    me.loop_triangles.foreach_get("loops", tl)
    t = uv[tl.reshape(-1, 3)]
    a = 0.5 * np.abs(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]))
    return round(float(a.sum()), 3)


def chao(tamanho: float = 200.0, z: float = 0.0, nome: str = "Chao") -> bpy.types.Object:
    me = bpy.data.meshes.new(nome)
    s = tamanho / 2
    me.from_pydata([(-s, -s, z), (s, -s, z), (s, s, z), (-s, s, z)], [], [(0, 1, 2, 3)])
    return nova_colecao_objeto(bpy.data.objects.new(nome, me))


# ---------------------------------------------------------------- imagens
def nova_imagem(nome: str, px: int, dados: bool) -> bpy.types.Image:
    img = bpy.data.images.new(nome, px, px, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if dados else "sRGB"
    return img


def pixels(img: bpy.types.Image) -> np.ndarray:
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)


def gravar_pixels(img: bpy.types.Image, a: np.ndarray) -> None:
    img.pixels.foreach_set(np.ascontiguousarray(a, np.float32).reshape(-1))
    img.update()


def srgb_para_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_para_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def salvar_imagem(img: bpy.types.Image, caminho: Path, formato: str, qualidade: int = 90) -> bytes:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    img.file_format = formato
    img.save(filepath=str(caminho), quality=qualidade)
    return caminho.read_bytes()


# ---------------------------------------------------------------- bake
def preparar_bake(cena: bpy.types.Scene) -> None:
    cena.render.engine = "CYCLES"
    cena.cycles.use_denoising = False
    if cena.world is None:
        cena.world = bpy.data.worlds.new("Mundo")
    if hasattr(cena.world, "use_nodes") and not cena.world.use_nodes:
        cena.world.use_nodes = True


def material_alvo(obj: bpy.types.Object) -> bpy.types.Node:
    """Material do objeto baixo com um nó de imagem 'alvo' (onde o bake escreve)."""
    mat = novo_material(f"{obj.name}_bake")
    nt = mat.node_tree
    no = nt.nodes.new("ShaderNodeTexImage")
    no.name = "alvo"
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return no


def _visibilidade(obj: bpy.types.Object, ligada: bool) -> None:
    for k in (
        "visible_camera",
        "visible_diffuse",
        "visible_glossy",
        "visible_transmission",
        "visible_volume_scatter",
        "visible_shadow",
    ):
        setattr(obj, k, ligada)


def gaiola(
    baixo: bpy.types.Object,
    altos: list[bpy.types.Object],
    fator: float = 1.3,
) -> tuple[bpy.types.Object, dict]:
    """Gaiola do bake: cópia do baixo com cada vértice empurrado pela normal o tanto que a
    superfície alta se afasta dali (vértice, centro e meios das faces vizinhas) x `fator`, mais
    uma folga. Com extrusão uniforme, nas frestas entre peças (sacos encostados, beiral) o raio
    nascia do lado de fora da peça vizinha e pegava a cor dela (traços escuros na textura)."""
    bm_alto = bmesh.new()
    for o in altos:
        tmp = o.data.copy()
        tmp.transform(o.matrix_world)
        bm_alto.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    bvh = BVHTree.FromBMesh(bm_alto)
    bm_alto.free()
    diag = diagonal(baixo)
    bm = bmesh.new()
    bm.from_mesh(baixo.data)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    d = np.zeros(len(bm.verts), np.float64)
    for v in bm.verts:
        r = bvh.find_nearest(v.co)
        d[v.index] = r[3] if r[0] is not None else 0.0
    for f in bm.faces:
        c = f.calc_center_median()
        m = 0.0
        for p in [c] + [(c + v.co) / 2 for v in f.verts]:
            r = bvh.find_nearest(p)
            if r[0] is not None:
                m = max(m, r[3])
        for v in f.verts:
            d[v.index] = max(d[v.index], m)
    folga = max(0.0005, 0.0008 * diag)
    teto = 0.04 * diag
    e = np.clip(fator * d + folga, folga, teto)
    for v in bm.verts:
        v.co += v.normal * float(e[v.index])
    me = bpy.data.meshes.new("gaiola")
    bm.to_mesh(me)
    bm.free()
    g = nova_colecao_objeto(bpy.data.objects.new("gaiola", me))
    _visibilidade(g, False)
    info = {
        "folga_m": round(folga, 4),
        "extrusao_media_m": round(float(e.mean()), 4),
        "extrusao_max_m": round(float(e.max()), 4),
    }
    return g, info


def assar(
    cena: bpy.types.Scene,
    baixo: bpy.types.Object,
    altos: list[bpy.types.Object],
    tipo: str,
    img: bpy.types.Image,
    extrusao: float,
    raio: float = 0.0,
    amostras: int = 4,
    margem: int = 8,
    filtro: set[str] | None = None,
    cage: bpy.types.Object | None = None,
) -> float:
    """Bake do(s) objeto(s) alto(s) para o baixo (selecionado -> ativo). Com `cage`, os raios
    saem da gaiola (extrusão por vértice) em vez da extrusão uniforme. Devolve o tempo (s)."""
    t0 = time.time()
    nt = baixo.active_material.node_tree
    no = nt.nodes["alvo"]
    no.image = img
    for n in nt.nodes:
        n.select = False
    no.select = True
    nt.nodes.active = no
    cena.cycles.samples = amostras
    selecionar_so(baixo, altos)
    _visibilidade(baixo, False)
    kw = {
        "type": tipo,
        "use_selected_to_active": True,
        "cage_extrusion": extrusao,
        "max_ray_distance": raio,
        "margin": margem,
        "margin_type": "EXTEND",
        "use_clear": True,
        "target": "IMAGE_TEXTURES",
    }
    if tipo == "NORMAL":
        kw.update(normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y", normal_b="POS_Z")
    if filtro:
        kw["pass_filter"] = filtro
    if cage is not None:
        kw.update(use_cage=True, cage_object=cage.name)
    bpy.ops.object.bake(**kw)
    _visibilidade(baixo, True)
    return round(time.time() - t0, 1)


def cobertura_uv(cena, baixo, px: int) -> np.ndarray:
    """Máscara (h, w) dos texels cobertos pela UV do objeto baixo: bake EMIT branco dele mesmo,
    sem margem. Serve para contar os texels que o bake do alto não achou (ficaram pretos)."""
    img = nova_imagem("cobertura", px, True)
    nt = baixo.active_material.node_tree
    saida = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    sup = saida.inputs["Surface"]
    antigo = sup.links[0].from_socket if sup.is_linked else None
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    nt.links.new(em.outputs["Emission"], saida.inputs["Surface"])
    no = nt.nodes["alvo"]
    no.image = img
    nt.nodes.active = no
    selecionar_so(baixo)
    cena.cycles.samples = 1
    bpy.ops.object.bake(type="EMIT", use_selected_to_active=False, margin=0, use_clear=True)
    nt.nodes.remove(em)
    if antigo is not None:
        nt.links.new(antigo, saida.inputs["Surface"])
    m = pixels(img)[..., 0] > 0.5
    bpy.data.images.remove(img)
    return m


def assar_escalar(
    cena,
    baixo,
    altos,
    entrada: str,
    img,
    extrusao: float,
    raio: float = 0.0,
    margem: int = 8,
    cage=None,
    amostras: int = 4,
) -> float:
    """Bake de uma entrada do Principled (ex.: 'Metallic' ou 'Base Color') como emissão: liga o
    que entra nela (ou o valor fixo) numa Emissão ligada à saída, faz o bake EMIT e desfaz."""
    desfazer = []
    vistos: set = set()
    for o in altos:
        for slot in o.material_slots:
            mat = slot.material
            if mat is None or mat.name in vistos:
                continue
            vistos.add(mat.name)
            nt = mat.node_tree
            pr = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            saida = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
            if pr is None or saida is None:
                continue
            em = nt.nodes.new("ShaderNodeEmission")
            em.inputs["Strength"].default_value = 1.0
            sock = pr.inputs[entrada]
            if sock.is_linked:
                nt.links.new(sock.links[0].from_socket, em.inputs["Color"])
            else:
                v = sock.default_value
                if isinstance(v, float):
                    em.inputs["Color"].default_value = (v, v, v, 1.0)
                else:
                    em.inputs["Color"].default_value = (v[0], v[1], v[2], 1.0)
            antigo = saida.inputs["Surface"].links[0].from_socket
            nt.links.new(em.outputs["Emission"], saida.inputs["Surface"])
            desfazer.append((nt, em, antigo, saida))
    t = assar(
        cena, baixo, altos, "EMIT", img, extrusao, raio, amostras=amostras, margem=margem, cage=cage
    )
    for nt, em, antigo, saida in desfazer:
        nt.links.new(antigo, saida.inputs["Surface"])
        nt.nodes.remove(em)
    return t


# ---------------------------------------------------------------- alvo de triângulos
# tentativas de alvo, em fração do teto da classe; tolerâncias em fração da diagonal da caixa.
# 1ª versão: média 0,15% e p95 0,5% (a casa de palha caía para 2 mil triângulos e as varas finas
# do telhado quebravam). 2ª: média 0,1%, p95 0,3%, p99 0,6% e alvo desde 20% do teto: o altar
# (1,5 mil) e o túmulo (1 mil) passaram com telhas quebradas e frestas pretas. Gráfico é o
# critério principal do dono: agora o alvo começa em 40% do teto e a tolerância é a metade.
FRACOES = (0.4, 0.55, 0.75, 1.0)
TOLERANCIA = {"media": 0.0005, "p95": 0.0015, "p99": 0.003}


def escolher_alvo(
    alto: bpy.types.Object,
    teto: int,
    forcado: int | None = None,
    fracoes=FRACOES,
    tol: dict | None = None,
) -> tuple[bpy.types.Object, list]:
    """Reduz cópias de `alto` para alvos crescentes e fica com a 1ª dentro da tolerância de
    desvio (média, p95 e p99 em fração da diagonal). Sem nenhuma dentro, fica o teto."""
    tol = tol or TOLERANCIA
    diag = diagonal(alto)
    n_alto = triangulos(alto)
    alvos = [forcado] if forcado else sorted({min(n_alto, int(teto * f)) for f in fracoes})
    tentativas = []
    escolhido = None
    for alvo in alvos:
        baixo = copiar(alto, "baixo")
        n = reduzir(baixo, alvo)
        d = desvio(baixo, alto, n=6000)
        ok = (
            d["media_m"] <= tol["media"] * diag
            and d["p95_m"] <= tol["p95"] * diag
            and d["p99_m"] <= tol["p99"] * diag
        )
        tentativas.append({"alvo": alvo, "tris": n, **d, "ok": ok})
        log("tentativa", tentativas[-1])
        if ok or alvo == alvos[-1]:
            escolhido = baixo
            break
        bpy.data.objects.remove(baixo)
    return escolhido, tentativas


# ---------------------------------------------------------------- bake + exportação
def filtrar_costas(altos, baixo, alcance: float, limite: float = -0.3) -> int:
    """Tira das peças altas as faces de costas para o baixo: face alta a menos de `alcance` da
    superfície baixa e com a normal contrária à dela (produto < `limite`).

    O Roblox não desenha o verso (MeshPart sem DoubleSided), mas o bake acha a primeira face no
    caminho do raio, de frente ou de costas. Na casa de telha há, por fora da parede branca, uma
    face virada para dentro com textura escura: invisível no jogo, ela saía no bake e a parede
    comprida ficava preta. Devolve quantas faces saíram."""
    bvh = bvh_de(baixo)
    tirou = 0
    for o in altos:
        mw = o.matrix_world
        rot = mw.to_3x3()
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.normal_update()
        fora = []
        for f in bm.faces:
            c = mw @ f.calc_center_median()
            loc, n_b, _, dist = bvh.find_nearest(c)
            if loc is None or dist > alcance:
                continue
            if (rot @ f.normal).normalized().dot(n_b) < limite:
                fora.append(f)
        if fora:
            bmesh.ops.delete(bm, geom=fora, context="FACES")
            bm.to_mesh(o.data)
            o.data.update()
            tirou += len(fora)
        bm.free()
    return tirou


def dividir_ilhas(baixo: bpy.types.Object, angulo_graus: float = 45.0) -> bpy.types.Object:
    """Cópia do baixo para receber o bake, separada nas costuras da UV e nas arestas vivas.

    A gaiola e a extrusão do Blender empurram cada vértice pela normal MÉDIA das faces em volta.
    Numa parede fina (face de fora, topo e face de dentro no mesmo vértice) essa média aponta
    para cima ou para o lado, e o raio do bake corria rente à parede e achava o lado de dentro:
    a parede comprida da casa de telha saía preta. Separadas, cada ilha tem a sua normal. A UV é
    a mesma, então a textura serve para o baixo original (que é o que vai para o GLB)."""
    o = copiar(baixo, "alvo_bake")
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    uvl = bm.loops.layers.uv.active
    lim = math.radians(angulo_graus)
    cortar = []
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        f1, f2 = e.link_faces
        if f1.normal.length > 0.5 and f2.normal.length > 0.5 and f1.normal.angle(f2.normal) > lim:
            cortar.append(e)
            continue
        if uvl is None:
            continue
        a, b = e.link_loops[0], e.link_loops[1]
        ua = {a.vert: a[uvl].uv, a.link_loop_next.vert: a.link_loop_next[uvl].uv}
        ub = {b.vert: b[uvl].uv, b.link_loop_next.vert: b.link_loop_next[uvl].uv}
        if any((ua[v] - ub[v]).length > 1e-6 for v in e.verts):
            cortar.append(e)
    bmesh.ops.split_edges(bm, edges=cortar)
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    return o


def _assar_mapas(cena, baixo, altos, tex, margem, cage, ext, metal, amostras_ao) -> dict:
    """Os 4 (ou 5, com metal) mapas de uma vez, com gaiola (`cage`) ou extrusão uniforme."""
    m: dict = {
        "cor": nova_imagem("cor", tex, False),
        "normal": nova_imagem("normal", tex, True),
        "ao": nova_imagem("ao", tex, True),
        "rug": nova_imagem("rug", tex, True),
    }
    t = {}
    kw = {"margem": margem, "cage": cage}
    t["cor"] = assar_escalar(cena, baixo, altos, "Base Color", m["cor"], ext, **kw)
    t["normal"] = assar(cena, baixo, altos, "NORMAL", m["normal"], ext, **kw)
    t["rug"] = assar(cena, baixo, altos, "ROUGHNESS", m["rug"], ext, **kw)
    if metal:
        m["metal"] = nova_imagem("metal", tex, True)
        t["metal"] = assar_escalar(cena, baixo, altos, "Metallic", m["metal"], ext, **kw)
    lo, _ = caixa(baixo)
    piso = chao(z=float(lo[2]) - 0.002)
    t["ao"] = assar(cena, baixo, altos, "AO", m["ao"], ext, amostras=amostras_ao, **kw)
    bpy.data.objects.remove(piso)
    m["tempos"] = t
    return m


def produzir(
    cena: bpy.types.Scene,
    baixo: bpy.types.Object,
    altos: list[bpy.types.Object],
    tex: int,
    trab: Path,
    saida: Path,
    nome_no: str,
    forca_ao: float = 0.6,
    fresta_rug: float = 0.08,
    metal: bool = False,
    amostras_ao: int = 128,
) -> dict:
    """Bake do(s) alto(s) no baixo e GLB.

    - cor: a entrada Base Color de cada material alto, assada como emissão (o valor exato, mesmo
      onde o material é metal);
    - normal (tangente, OpenGL), rugosidade e, com `metal`, o metal (canal B);
    - oclusão ambiente com o chão; escurece a cor (`forca_ao`: o Roblox não tem canal de oclusão)
      e sobe a rugosidade nas frestas (`fresta_rug`).
    Os raios saem da gaiola por vértice (`gaiola`). Onde o baixo tem camadas sobrepostas (parede
    dupla da casa de telha), a normal de vértice pode apontar para dentro e a gaiola nasce entre
    as camadas: o bake pega o lado de dentro (oclusão quase 0, parede preta). Por isso, se mais de
    2% dos texels saem com oclusão < 0,08, o bake é refeito com extrusão uniforme e fica a versão
    com menos texels escuros.

    O bake e o GLB usam a cópia separada em ilhas (`dividir_ilhas`): mesmos triângulos e mesma
    UV, com aresta viva nas costuras (a normal de tangente só vale para as normais com que foi
    assada). Devolve as métricas do bake e do GLB."""
    diag = diagonal(baixo)
    margem = max(4, tex // 128)
    alvo = dividir_ilhas(baixo)
    _visibilidade(baixo, False)  # só a cópia recebe o bake; o baixo não pode tapar a oclusão
    baixo.hide_render = True
    material_alvo(alvo)
    cobre = cobertura_uv(cena, alvo, tex)
    cena.world.light_settings.distance = float(min(1.2, max(0.03, 0.12 * diag)))
    costas = filtrar_costas(altos, baixo, 0.03 * diag)
    log("faces de costas tiradas do bake:", costas)
    cage, info_gaiola = gaiola(alvo, altos)
    info_gaiola["faces_de_costas_tiradas"] = costas
    mapas = _assar_mapas(
        cena, alvo, altos, tex, margem, cage, info_gaiola["extrusao_max_m"], metal, amostras_ao
    )
    bpy.data.objects.remove(cage)
    escuro = float((pixels(mapas["ao"])[..., 0] < 0.08)[cobre].mean())
    info_gaiola["fracao_ao_escura"] = round(escuro, 4)
    escolha = "gaiola"
    if escuro > 0.02:
        ext_u = float(
            min(0.04 * diag, max(2 * info_gaiola["folga_m"], info_gaiola["extrusao_media_m"]))
        )
        alt = _assar_mapas(cena, alvo, altos, tex, margem, None, ext_u, metal, amostras_ao)
        escuro_u = float((pixels(alt["ao"])[..., 0] < 0.08)[cobre].mean())
        info_gaiola["uniforme"] = {
            "extrusao_m": round(ext_u, 4),
            "fracao_ao_escura": round(escuro_u, 4),
        }
        log("bake: gaiola", escuro, "uniforme", escuro_u)
        if escuro_u < escuro:
            mapas, alt = alt, mapas
            escolha = "uniforme"
        for img in alt.values():
            if isinstance(img, bpy.types.Image):
                bpy.data.images.remove(img)
    info_gaiola["usada"] = escolha
    tempos = mapas.pop("tempos")
    img_cor, img_nrm, img_ao, img_rug = mapas["cor"], mapas["normal"], mapas["ao"], mapas["rug"]
    img_met = mapas.get("metal")

    cor = pixels(img_cor)
    ao = pixels(img_ao)[..., 0]
    rug = pixels(img_rug)[..., 0]
    preto = cor[..., :3].max(axis=2) < 0.004
    vazio = float((preto & cobre).sum() / max(1, cobre.sum()))
    lin = srgb_para_linear(cor[..., :3]) * (1 - forca_ao + forca_ao * ao)[..., None]
    cor[..., :3] = linear_para_srgb(lin)
    cor[..., 3] = 1.0
    gravar_pixels(img_cor, cor)
    rug = np.clip(rug + (1 - ao) * fresta_rug, 0.0, 1.0)
    meio = tex // 2
    rug2 = rug.reshape(meio, 2, meio, 2).mean(axis=(1, 3))
    img_mr = nova_imagem("mr", meio, True)
    mr = np.zeros((meio, meio, 4), np.float32)
    mr[..., 0] = 1.0
    mr[..., 1] = rug2
    if img_met is not None:
        met = pixels(img_met)[..., 0]
        mr[..., 2] = met.reshape(meio, 2, meio, 2).mean(axis=(1, 3))
    mr[..., 3] = 1.0
    gravar_pixels(img_mr, mr)
    texturas = {
        "cor": (salvar_imagem(img_cor, trab / "cor.jpg", "JPEG", 90), "image/jpeg"),
        "normal": (salvar_imagem(img_nrm, trab / "normal.png", "PNG"), "image/png"),
        "mr": (salvar_imagem(img_mr, trab / "metal_rug.png", "PNG"), "image/png"),
    }
    salvar_imagem(img_ao, trab / "ao.png", "PNG")
    exp = exportar_glb([(nome_no, alvo)], saida, texturas, metal=metal)
    bpy.data.objects.remove(alvo)
    _visibilidade(baixo, True)
    baixo.hide_render = False
    return {
        "exportacao": exp,
        "texturas_px": {"cor": [tex, tex], "normal": [tex, tex], "metal_rug": [meio, meio]},
        "bake": {
            "gaiola": info_gaiola,
            "ao_distancia_m": round(cena.world.light_settings.distance, 3),
            "fracao_texels_sem_cor": round(vazio, 5),
            "cobertura_uv_texels": round(float(cobre.mean()), 4),
            "tempos_s": tempos,
            "forca_ao_na_cor": forca_ao,
            "metal": bool(metal),
        },
    }


# ---------------------------------------------------------------- exportação
def arrays_malha(obj: bpy.types.Object):
    """Posições (m), normais de canto e UV por vértice único, e índices dos triângulos."""
    me = obj.data
    me.calc_loop_triangles()
    nv, nl = len(me.vertices), len(me.loops)
    co = np.empty(nv * 3, np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    vi = np.empty(nl, np.int64)
    me.loops.foreach_get("vertex_index", vi)
    nrm = np.empty(nl * 3, np.float64)
    me.corner_normals.foreach_get("vector", nrm)
    nrm = nrm.reshape(-1, 3)
    if me.uv_layers:
        uv = np.empty(nl * 2, np.float64)
        me.uv_layers.active.data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2)
    else:
        uv = np.zeros((nl, 2))
    tl = np.empty(len(me.loop_triangles) * 3, np.int64)
    me.loop_triangles.foreach_get("loops", tl)
    chave = np.column_stack([co[vi], nrm, uv]).round(6)
    _, primeiro, inv = np.unique(chave, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    return co[vi][primeiro], nrm[primeiro], uv[primeiro], inv[tl].astype(np.uint32)


def exportar_glb(
    partes: list[tuple[str, bpy.types.Object]],
    caminho: Path,
    texturas: dict[str, tuple[bytes, str]] | None,
    metal: bool = False,
    rugosidade: float = 0.9,
    cor_fator=None,
) -> dict:
    """Escreve o GLB em studs, Y para cima. `partes` = [(nome do nó, objeto)], todas com o mesmo
    material (atlas único). `texturas`: {'cor'|'normal'|'mr': (bytes, mime)}."""
    g = glb.Glb()
    tex = texturas or {}
    ids = {k: g.texture(*v) for k, v in tex.items()}
    mi = g.material(
        caminho.stem,
        ids.get("cor"),
        ids.get("normal"),
        ids.get("mr"),
        metal=metal,
        rugosidade=rugosidade,
        cor_fator=cor_fator,
    )
    tris = 0
    for nome, obj in partes:
        p, n, t, idx = arrays_malha(obj)
        p, n, t = glb.de_blender(p, n, t)
        g.mesh(nome, p, n, t if obj.data.uv_layers else None, idx, mi)
        tris += len(idx) // 3
    caminho.parent.mkdir(parents=True, exist_ok=True)
    data = g.bytes()
    caminho.write_bytes(data)
    return {"triangulos": tris, "mb": round(len(data) / 2**20, 3)}


def medidas(obj: bpy.types.Object) -> dict:
    """Caixa em m e studs, Z mínimo (base) e centro da caixa no chão (pivô)."""
    lo, hi = caixa(obj)
    dim = hi - lo
    centro = (lo + hi) / 2
    return {
        "dim_m_xyz": [round(float(x), 3) for x in (dim[0], dim[2], dim[1])],
        "dim_studs_xyz": [round(float(x) / M_POR_STUD, 2) for x in (dim[0], dim[2], dim[1])],
        "base_z_m": round(float(lo[2]), 4),
        "centro_base_m_xz": [round(float(centro[0]), 3), round(float(-centro[1]), 3)],
    }


def gravar_json(caminho: Path, dados: dict) -> None:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    velho = json.loads(caminho.read_text("utf-8")) if caminho.is_file() else {}
    velho.update(dados)
    caminho.write_text(json.dumps(velho, ensure_ascii=False, indent=1) + "\n", "utf-8")
