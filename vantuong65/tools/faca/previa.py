"""Prévias das facas a partir do GLB exportado (o que vai para o Roblox, com as texturas assadas).

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/faca/previa.py -- kabar m6 type56 dao [--amostras 128]

Saídas: assets/facas/<chave>_previa.png (faca fora da bainha + bainha, 1600 x 900) e
assets/facas/<chave>_close.png (close da lâmina com a guarda e o cabo). Cycles na CPU com OIDN,
luz de estúdio (caixas de luz) e o HDRI do céu só nos reflexos; fundo neutro escuro.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
SAIDA = RAIZ / "assets" / "facas"
CEU = RAIZ / "assets" / "ceu" / "kloofendal_48d_partly_cloudy_puresky.jpg"
M_POR_STUD = 0.28


def args() -> tuple[list[str], int]:
    a = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    amostras = 128
    if "--amostras" in a:
        i = a.index("--amostras")
        amostras = int(a[i + 1])
        del a[i : i + 2]
    return a or ["kabar", "m6", "type56", "dao"], amostras


def cena_nova(amostras: int) -> bpy.types.Scene:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    c = bpy.context.scene
    c.render.engine = "CYCLES"
    c.cycles.device = "CPU"
    c.cycles.samples = amostras
    c.cycles.use_adaptive_sampling = True
    c.cycles.adaptive_threshold = 0.015
    c.cycles.use_denoising = True
    c.cycles.denoiser = "OPENIMAGEDENOISE"
    c.cycles.max_bounces = 8
    c.render.resolution_x, c.render.resolution_y = 1600, 900
    c.render.resolution_percentage = 100
    c.view_settings.view_transform = "AgX"
    c.view_settings.look = "AgX - Medium High Contrast"
    c.render.image_settings.file_format = "PNG"
    mundo(c)
    return c


def mundo(c) -> None:
    w = bpy.data.worlds.new("Estudio")
    c.world = w
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    mix = nt.nodes.new("ShaderNodeMixShader")
    lp = nt.nodes.new("ShaderNodeLightPath")
    fundo = nt.nodes.new("ShaderNodeBackground")
    fundo.inputs["Color"].default_value = (0.012, 0.012, 0.013, 1)
    fundo.inputs["Strength"].default_value = 1.0
    ceu = nt.nodes.new("ShaderNodeBackground")
    ceu.inputs["Strength"].default_value = 0.35
    if CEU.is_file():
        tex = nt.nodes.new("ShaderNodeTexEnvironment")
        tex.image = bpy.data.images.load(str(CEU))
        nt.links.new(tex.outputs["Color"], ceu.inputs["Color"])
    else:
        ceu.inputs["Color"].default_value = (0.5, 0.55, 0.6, 1)
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(ceu.outputs[0], mix.inputs[1])
    nt.links.new(fundo.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def luz(nome, pos, alvo, energia, tam, cor=(1, 1, 1)) -> None:
    ld = bpy.data.lights.new(nome, "AREA")
    ld.shape = "RECTANGLE"
    ld.size, ld.size_y = tam
    ld.energy = energia
    ld.color = cor
    o = bpy.data.objects.new(nome, ld)
    bpy.context.scene.collection.objects.link(o)
    o.location = pos
    olhar(o, alvo)


def olhar(o, alvo) -> None:
    d = Vector(alvo) - o.location
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def importar(chave: str) -> dict:
    bpy.ops.import_scene.gltf(filepath=str(SAIDA / f"{chave}.glb"))
    out = {}
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            continue
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
        o.data.transform(Matrix.Scale(M_POR_STUD, 4))  # studs -> m
        out[o.name.split(".")[0]] = o
    return out


def camera(pos, alvo, foco_mm=85.0, dof=None):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = foco_mm
    cd.clip_start = 0.01
    if dof:
        cd.dof.use_dof = True
        cd.dof.focus_distance = dof[0]
        cd.dof.aperture_fstop = dof[1]
    o = bpy.data.objects.new("Cam", cd)
    bpy.context.scene.collection.objects.link(o)
    o.location = pos
    olhar(o, alvo)
    bpy.context.scene.camera = o
    return o


def caixa(objs):
    """Caixa no mundo pelos vértices (o bound_box fica velho depois de mexer na malha)."""
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def estudio(centro: Vector, raio: float) -> None:
    c = centro
    luz("Chave", c + Vector((1.2, -0.5, 1.0)) * raio * 2.2, c, 150 * raio**2, (raio * 1.6, raio))
    luz(
        "Rebatedor",
        c + Vector((1.4, 1.2, -0.3)) * raio * 2.2,
        c,
        35 * raio**2,
        (raio * 1.5, raio * 1.5),
        (0.95, 0.97, 1.0),
    )
    luz(
        "Recorte",
        c + Vector((-1.3, 0.4, 1.1)) * raio * 2.2,
        c,
        300 * raio**2,
        (raio * 2.2, raio * 0.25),
        (1.0, 0.96, 0.9),
    )
    luz("Topo", c + Vector((0.4, 0.0, 1.6)) * raio * 2.2, c, 70 * raio**2, (raio * 2.5, raio * 0.6))
    luz(
        "Chao",
        c + Vector((0.9, 0.0, -1.2)) * raio * 2.2,
        c,
        45 * raio**2,
        (raio * 3.0, raio),
        (1.0, 0.97, 0.92),
    )


def renderizar(caminho: Path) -> None:
    bpy.context.scene.render.filepath = str(caminho)
    bpy.ops.render.render(write_still=True)
    print("[PREVIA]", caminho, flush=True)


def previa(chave: str, amostras: int) -> None:
    cena_nova(amostras)
    objs = importar(chave)
    faca = objs["Faca"]
    bainha = objs.get("Bainha")
    # ---- prévia geral: faca em cima, bainha embaixo; ponta para a esquerda (câmera em +X)
    for o in objs.values():
        o.rotation_euler = (0.0, math.radians(14), 0.0)
    if bainha:
        lo, hi = caixa([faca])
        bainha.location = (0.0, 0.035, -(hi.z - lo.z) - 0.025)
    bpy.context.view_layer.update()
    lo, hi = caixa(list(objs.values()))
    centro = (lo + hi) / 2
    raio = max((hi - lo).length / 2, 0.05)
    # enquadra o comprimento (Y) na largura do quadro com folga de 12%
    larg = max(hi.y - lo.y, (hi.z - lo.z) * 16 / 9) * 1.12
    dist = larg / 2 / math.tan(math.atan(36 / 2 / 85.0)) * 1.0
    cam = camera(centro + Vector((dist, 0.0, dist * 0.28)), centro, 85.0)
    estudio(centro, raio)
    renderizar(SAIDA / f"{chave}_previa.png")
    # ---- close: junção lâmina/guarda/cabo, de 3/4, como na mão em 1ª pessoa
    if bainha:
        bainha.hide_render = True
    for o in objs.values():
        o.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    lo, hi = caixa([faca])
    comp = hi.y - lo.y
    alvo = Vector((0.0, -0.01 - comp * 0.05, (lo.z + hi.z) / 2 * 0.3))
    d = 0.2 + comp * 0.15
    bpy.data.objects.remove(cam)
    camera(alvo + Vector((d * 0.72, d * 0.55, d * 0.42)), alvo, 70.0, dof=(d * 0.97, 16.0))
    for o in [o for o in bpy.context.scene.objects if o.type == "LIGHT"]:
        bpy.data.objects.remove(o)
    estudio(alvo, 0.12)
    renderizar(SAIDA / f"{chave}_close.png")


def main() -> None:
    chaves, amostras = args()
    for k in chaves:
        previa(k, amostras)


if __name__ == "__main__":
    main()
