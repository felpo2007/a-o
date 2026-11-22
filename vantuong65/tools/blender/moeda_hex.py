"""Moeda sextavada do jogo (D-246), em Cycles, com fundo transparente.

Pedido do dono: "mude o formato das moedas". Sextavada, de ouro, com aro alto, sextavado interno
gravado e a estrela facetada em relevo. Saída: assets/ui/recompensas/moeda.png, 512 x 512, RGBA.

    $env:VT65_CPU = "1"; $env:VT65_THREADS = "3"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/moeda_hex.py -- [--amostras 128]
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import loja as L  # noqa: E402

SAIDA = C.RAIZ / "assets" / "ui" / "recompensas" / "moeda.png"
ESPESSURA = 0.13
SEGMENTOS = 96


def material(nome, cor, metal=0.0, rug=0.5, emissao=0.0):
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*cor, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rug
    if emissao:
        b.inputs["Emission Color"].default_value = (*cor, 1)
        b.inputs["Emission Strength"].default_value = emissao
    return m


def ouro():
    m = material("Ouro", (1.0, 0.66, 0.16), metal=1.0, rug=0.24)
    n, ln = m.node_tree.nodes, m.node_tree.links
    b = n["Principled BSDF"]
    t = n.new("ShaderNodeTexNoise")
    t.inputs["Scale"].default_value = 160.0
    t.inputs["Detail"].default_value = 5.0
    r = n.new("ShaderNodeMapRange")
    r.inputs["From Min"].default_value = 0.34
    r.inputs["From Max"].default_value = 0.68
    r.inputs["To Min"].default_value = 0.2
    r.inputs["To Max"].default_value = 0.27
    ln.new(t.outputs[0], r.inputs["Value"])
    ln.new(r.outputs[0], b.inputs["Roughness"])
    return m


def fator_hex(a: float) -> float:
    """Raio do sextavado de pontas para cima, com os cantos levemente arredondados."""
    setor = math.pi / 3
    u = (a - math.pi / 2 + setor / 2) % setor - setor / 2
    reto = math.cos(setor / 2) / math.cos(u)
    return reto * 0.94 + 0.06 * math.cos(setor / 2)


def moeda(mat):
    bm = bmesh.new()
    h = ESPESSURA / 2
    # (fração do raio, altura): fundo, sextavado gravado, campo, aro alto e borda, nas duas faces
    meio = [
        (0.0, 0.58),
        (0.60, 0.58),
        (0.615, 0.72),
        (0.645, 0.72),
        (0.66, 0.58),
        (0.80, 0.58),
        (0.835, 1.0),
        (0.965, 1.0),
        (1.0, 0.7),
    ]
    perfil = [(r, z * h) for r, z in meio] + [(r, -z * h) for r, z in reversed(meio)]
    aneis = []
    for i in range(SEGMENTOS):
        a = 2 * math.pi * i / SEGMENTOS
        k = fator_hex(a) * 0.5
        aneis.append(
            [bm.verts.new((r * k * math.cos(a), r * k * math.sin(a), z)) for r, z in perfil]
        )
    for i in range(SEGMENTOS):
        x, y = aneis[i], aneis[(i + 1) % SEGMENTOS]
        for j in range(len(perfil) - 1):
            if perfil[j][0] == 0.0:
                bm.faces.new((x[j], x[j + 1], y[j + 1]))
            elif perfil[j + 1][0] == 0.0:
                bm.faces.new((x[j], x[j + 1], y[j]))
            else:
                bm.faces.new((x[j], x[j + 1], y[j + 1], y[j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Estrela de dez facetas: cada ponta tem uma aresta viva do centro à ponta, que pega a luz
    for sinal in (1, -1):
        topo = bm.verts.new((0, 0, sinal * 1.5 * h))
        pts = []
        for i in range(10):
            r = 0.262 if i % 2 == 0 else 0.262 * 0.42
            q = math.pi / 2 + i * math.pi / 5
            pts.append(bm.verts.new((r * math.cos(q), r * math.sin(q), sinal * 0.6 * h)))
        for i in range(10):
            f = (pts[i], pts[(i + 1) % 10], topo)
            bm.faces.new(f if sinal > 0 else f[::-1])
    me = bpy.data.meshes.new("MoedaHex")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new("MoedaHex", me)
    bpy.context.scene.collection.objects.link(o)
    o.rotation_euler = (math.radians(90), 0, 0)
    return o


def rebatedores(centro: Vector, raio: float) -> None:
    for nome, pos, tam, forca, cor in (
        ("Teto", (-0.4, -1.6, 3.0), (5.0, 3.0), 2.0, (1.0, 0.95, 0.84)),
        ("Frente", (-0.6, -3.4, 0.5), (4.0, 2.4), 1.5, (1.0, 0.93, 0.8)),
        ("Lado", (-3.2, -1.4, 0.6), (1.1, 4.0), 5.0, (1.0, 0.9, 0.72)),
        ("Frio", (3.2, -1.6, 0.2), (1.2, 3.2), 1.2, (0.72, 0.82, 1.0)),
    ):
        p = centro + Vector(pos) * raio
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=p)
        o = bpy.context.active_object
        o.name = "Rebatedor" + nome
        o.scale = (tam[0] * raio, tam[1] * raio, 1)
        o.rotation_euler = (centro - p).to_track_quat("Z", "Y").to_euler()
        o.data.materials.append(material("Reb" + nome, cor, emissao=forca))
        o.visible_camera = False
        o.visible_shadow = False
        o.visible_diffuse = False


def principal() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    amostras = int(args[args.index("--amostras") + 1]) if "--amostras" in args else 128
    C.cena_vazia()
    cena = bpy.context.scene
    L.configurar(cena, 512, 512, amostras)
    cena.view_settings.view_transform = "Standard"
    try:
        cena.view_settings.look = "None"
    except TypeError:
        pass
    cena.view_settings.exposure = -0.15
    o = moeda(ouro())
    bpy.context.view_layer.update()
    _cam, centro, raio = L.camera_para(
        [o], 512, 512, direcao=(-0.2, -1.0, 0.17), lente=85.0, folga=1.04
    )
    rebatedores(centro, raio)
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    cena.render.filepath = str(SAIDA)
    bpy.ops.render.render(write_still=True)
    print("ok", SAIDA.name, flush=True)


principal()
