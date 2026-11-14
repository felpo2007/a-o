"""Imagens dos itens da loja (D-124, lote 11: "deixe a loja atrativa com imagens, cores, design
bonito"), em Cycles, com os modelos do próprio jogo: fundo transparente, luz de estúdio de três
pontos (chave quente, enchimento frio e contraluz), sombra suave num apanhador de sombra e a câmera
enquadrada pela caixa dos modelos. Só itens que têm modelo de verdade: a imagem mostra o que o item
dá (nada de tanque na imagem de um passe que não dá tanque).

Saídas (`assets/ui/loja/<chave>.png`, 512 x 384, RGBA):
- `usmc`: capacete M1 com a capa (Uniformes USMC 1965);
- `vc`: capacete de fibra e chapéu de selva (Uniformes da Força Principal 1965);
- `elite`: colete M1955 e a granada de fumaça M18 (Kit de Elite);
- `m151`, `m35`, `peugeot403`: os veículos ao nascer.

Uso:
    blender -b --factory-startup -P tools/blender/loja.py -- medir
    blender -b --factory-startup -P tools/blender/loja.py -- <chave>|todas [--amostras N] [--teste]
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402

RAIZ = C.RAIZ
FG = RAIZ / "assets" / "forgegui" / "models"
BL = RAIZ / "assets" / "blender"
SAIDA = RAIZ / "assets" / "ui" / "loja"

MODELOS = {
    "capacete_m1": FG / "capacete_m1_studs_fosco.glb",
    "capacete_fibra": FG / "capacete_fibra_studs_fosco.glb",
    "colete": FG / "colete_m1955_studs_fosco.glb",
    "m14": FG / "m14_studs_parker.glb",
    "type56": FG / "type56_studs_parker.glb",
    "chapeu_selva": FG / "chapeu_selva_studs_fosco.glb",
    "m18": BL / "smoke_m18" / "smoke_m18.glb",
    "m151": BL / "m151" / "m151.glb",
    "m35": BL / "m35" / "m35.glb",
    "peugeot403": BL / "peugeot403" / "peugeot403.glb",
}


def log(*a):
    print("[VT65]", *a, flush=True)


_cache: dict[str, bpy.types.Object] = {}


def carregar(chave: str) -> bpy.types.Object:
    """GLB do jogo em metros, um objeto só, sem os nós de colisão, com a base no z = 0 e o meio da
    caixa em x = y = 0. Fica escondido: serve de fonte para as cópias."""
    if chave in _cache:
        return _cache[chave]
    caminho = MODELOS[chave]
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(caminho))
    novos = [o for o in bpy.data.objects if o not in antes]
    malhas = [o for o in novos if o.type == "MESH" and not o.name.startswith(("Colisao_", "Zona_"))]
    for o in malhas:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy() if o.data.users > 1 else o.data
        o.data.transform(mw)
        o.matrix_world.identity()
    for o in novos:
        if o not in malhas:
            bpy.data.objects.remove(o)
    obj = malhas[0]
    if len(malhas) > 1:
        C.selecionar_so(obj, malhas)
        with bpy.context.temp_override(active_object=obj, selected_editable_objects=malhas):
            bpy.ops.object.join()
    from mathutils import Matrix

    obj.data.transform(Matrix.Scale(C.M_POR_STUD, 4))
    lo, hi = C.caixa(obj)
    meio = (lo + hi) / 2
    obj.data.transform(Matrix.Translation(Vector((-meio[0], -meio[1], -lo[2]))))
    obj.name = chave
    obj.hide_render = True
    obj.hide_viewport = True
    _cache[chave] = obj
    lo, hi = C.caixa(obj)
    log(
        "carregado",
        chave,
        "dim (m)",
        [round(float(x), 3) for x in hi - lo],
        "tri",
        C.triangulos(obj),
    )
    return obj


def copia(chave: str, pos, rot_graus=(0.0, 0.0, 0.0), escala=1.0) -> bpy.types.Object:
    o = carregar(chave).copy()
    o.hide_render = False
    o.hide_viewport = False
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(pos)
    o.rotation_mode = "XYZ"  # o importador de glTF deixa em quaternion (o Euler era ignorado)
    o.rotation_euler = Euler([math.radians(a) for a in rot_graus])
    o.scale = (escala, escala, escala)
    return o


def caixa_mundo(objs) -> tuple[Vector, Vector]:
    bpy.context.view_layer.update()
    pts = []
    for o in objs:
        for c in o.bound_box:
            pts.append(o.matrix_world @ Vector(c))
    a = np.array([[p.x, p.y, p.z] for p in pts])
    return Vector(a.min(axis=0)), Vector(a.max(axis=0))


# ------------------------------------------------------------------ estúdio
def configurar(cena, larg, alt, amostras):
    cena.render.engine = "CYCLES"
    C.usar_gpu(cena)
    cena.cycles.samples = amostras
    cena.cycles.use_denoising = True
    cena.cycles.max_bounces = 6
    cena.render.resolution_x = larg
    cena.render.resolution_y = alt
    cena.render.resolution_percentage = 100
    cena.render.film_transparent = True
    cena.render.image_settings.file_format = "PNG"
    cena.render.image_settings.color_mode = "RGBA"
    cena.view_settings.view_transform = "AgX"
    for look in ("AgX - Medium High Contrast", "Medium High Contrast", "AgX - Punchy", "Punchy"):
        try:
            cena.view_settings.look = look
            break
        except TypeError:
            continue
    mundo = bpy.data.worlds.new("Mundo")
    cena.world = mundo
    mundo.use_nodes = True
    bg = mundo.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.42, 0.44, 0.40, 1.0)
        bg.inputs["Strength"].default_value = 0.35


def luz_area(nome, pos, alvo, energia, cor, tamanho):
    d = bpy.data.lights.new(nome, "AREA")
    d.energy = energia
    d.color = cor
    d.size = tamanho
    o = bpy.data.objects.new(nome, d)
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(pos)
    o.rotation_euler = (Vector(alvo) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
    return o


def estudio(centro: Vector, raio: float):
    """Chave quente à esquerda, enchimento frio à direita, contraluz por trás e de cima; um chão que
    só recebe sombra (o fundo continua transparente)."""
    r = raio
    k = r * r  # a energia cresce com a distância ao quadrado
    luz_area(
        "Chave",
        centro + Vector((-2.2 * r, -2.4 * r, 2.4 * r)),
        centro,
        260 * k,
        (1.0, 0.9, 0.78),
        1.6 * r,
    )
    luz_area(
        "Enchimento",
        centro + Vector((2.8 * r, -1.6 * r, 1.0 * r)),
        centro,
        70 * k,
        (0.78, 0.86, 1.0),
        2.4 * r,
    )
    luz_area(
        "Contraluz",
        centro + Vector((0.6 * r, 2.8 * r, 2.2 * r)),
        centro,
        240 * k,
        (1.0, 0.95, 0.85),
        1.2 * r,
    )
    bpy.ops.mesh.primitive_plane_add(size=40 * r, location=(centro.x, centro.y, 0.0))
    chao = bpy.context.active_object
    chao.name = "Sombra"
    chao.is_shadow_catcher = True


def camera_para(objs, larg, alt, direcao=(0.55, -1.0, 0.42), lente=60.0, folga=1.12):
    """Câmera na direção dada (da cena para a câmera), enquadrando a caixa dos objetos: a maior
    medida projetada ocupa 1/folga do quadro e o meio dela fica no meio do quadro."""
    from bpy_extras.object_utils import world_to_camera_view

    lo, hi = caixa_mundo(objs)
    centro = (lo + hi) / 2
    raio = (hi - lo).length / 2
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lente
    cd.sensor_width = 36.0
    cd.sensor_fit = "HORIZONTAL"
    cam = bpy.data.objects.new("Cam", cd)
    cena = bpy.context.scene
    cena.collection.objects.link(cam)
    cena.camera = cam
    d = Vector(direcao).normalized()
    meia_h = math.atan(36.0 / 2 / lente)
    meia_v = math.atan(math.tan(meia_h) * alt / larg)
    dist = raio * folga / math.sin(meia_v)
    alvo = centro.copy()
    for _ in range(16):
        cam.location = alvo + d * dist
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        bpy.context.view_layer.update()
        pts = []
        for o in objs:
            for c in o.bound_box:
                p = world_to_camera_view(cena, cam, o.matrix_world @ Vector(c))
                pts.append((p.x, p.y))
        a = np.array(pts)
        ext = max(a[:, 0].max() - a[:, 0].min(), a[:, 1].max() - a[:, 1].min())
        meio = (a.min(axis=0) + a.max(axis=0)) / 2
        R = cam.matrix_world.to_3x3()
        larg_m = 2 * dist * math.tan(meia_h)
        alt_m = 2 * dist * math.tan(meia_v)
        alvo += R @ Vector(((meio[0] - 0.5) * larg_m, (meio[1] - 0.5) * alt_m, 0.0))
        fator = ext * folga
        dist *= fator
        if abs(fator - 1) < 0.005 and abs(meio[0] - 0.5) < 0.003 and abs(meio[1] - 0.5) < 0.003:
            break
    cam.location = alvo + d * dist
    bpy.context.view_layer.update()
    return cam, centro, raio


# ------------------------------------------------------------------ cenas
def cena_usmc():
    # só o que o passe dá: o capacete M1 com a capa (o fuzil é de todos e não entra na imagem)
    return [copia("capacete_m1", (0.0, 0.0, 0.0), (0, 0, 205))]


def cena_vc():
    # o passe dá o capacete de fibra e o chapéu de selva
    cap = copia("capacete_fibra", (-0.17, 0.02, 0.0), (0, 0, 200))
    chapeu = copia("chapeu_selva", (0.19, -0.06, 0.0), (0, 0, 160))
    return [cap, chapeu]


def cena_elite():
    colete = copia("colete", (0.0, 0.0, 0.0), (0, 0, 0))
    fum = copia("m18", (0.24, -0.30, 0.0), (0, 0, 25))
    return [colete, fum]


def cena_veiculo(chave):
    def f():
        return [copia(chave, (0, 0, 0), (0, 0, 0))]

    return f


CENAS = {
    "usmc": cena_usmc,
    "vc": cena_vc,
    "elite": cena_elite,
    "m151": cena_veiculo("m151"),
    "m35": cena_veiculo("m35"),
    "peugeot403": cena_veiculo("peugeot403"),
}


def render(chave: str, amostras: int, teste: bool):
    C.cena_vazia()
    _cache.clear()
    cena = bpy.context.scene
    larg, alt = (256, 192) if teste else (512, 384)
    configurar(cena, larg, alt, amostras)
    objs = CENAS[chave]()
    veiculo = chave in ("m151", "m35", "peugeot403")
    direcao = (0.9, -1.0, 0.45) if veiculo else (0.25, -1.0, 0.45)
    cam, centro, raio = camera_para(
        objs, larg, alt, direcao=direcao, lente=50.0 if veiculo else 60.0
    )
    estudio(centro, raio)
    SAIDA.mkdir(parents=True, exist_ok=True)
    nome = ("teste_" if teste else "") + f"{chave}.png"
    cena.render.filepath = str(SAIDA / nome)
    bpy.ops.render.render(write_still=True)
    log("ok", nome)


def medir():
    C.cena_vazia()
    for k in MODELOS:
        o = carregar(k)
        lo, hi = C.caixa(o)
        log(
            k,
            "x",
            round(float(hi[0] - lo[0]), 3),
            "y",
            round(float(hi[1] - lo[1]), 3),
            "z",
            round(float(hi[2] - lo[2]), 3),
        )


def principal():
    args = C.argumentos()
    if not args:
        raise SystemExit("uso: loja.py -- medir | <chave> | todas [--amostras N] [--teste]")
    if args[0] == "medir":
        medir()
        return
    amostras = 96
    if "--amostras" in args:
        amostras = int(args[args.index("--amostras") + 1])
    teste = "--teste" in args
    chaves = list(CENAS) if args[0] == "todas" else [args[0]]
    for k in chaves:
        render(k, amostras, teste)


if __name__ == "__main__":
    principal()
