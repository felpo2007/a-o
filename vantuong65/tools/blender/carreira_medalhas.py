"""Medalhas e emblema de prestígio da tela de carreira (D-247), em Cycles, com fundo transparente.

Saída: assets/ui/carreira/med_<id>.png (320 x 320) e prestigio.png (512 x 512).

    $env:VT65_CPU = "1"; $env:VT65_THREADS = "3"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/carreira_medalhas.py -- [--amostras 64] [--so bronze_star,prestigio]
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import loja as L  # noqa: E402

SAIDA = C.RAIZ / "assets" / "ui" / "carreira"

METAIS = {
    "ouro": ((1.0, 0.64, 0.15), 0.25),
    "bronze": ((0.72, 0.38, 0.16), 0.32),
    "prata": ((0.86, 0.87, 0.9), 0.24),
}

# forma, metal, esmalte e listras da fita (cor, largura), da borda ao centro, espelhadas
MEDALHAS = {
    "purple_heart": ("coracao", "ouro", (0.2, 0.03, 0.34), [("5A1E8C", 5), ("F2EEE2", 1)]),
    "combat_action": (
        "disco",
        "bronze",
        None,
        [("E9C33A", 1), ("1F4E9C", 2), ("F2EEE2", 1), ("B3202C", 2)],
    ),
    "bronze_star": ("estrela", "bronze", None, [("B3202C", 3), ("F2EEE2", 1), ("1F3F86", 2)]),
    "navy_cross": ("cruz", "bronze", None, [("14285C", 4), ("F2EEE2", 2)]),
    "socorro": (
        "cruz_grega",
        "prata",
        (0.02, 0.2, 0.09),
        [("2E6B3C", 3), ("F2EEE2", 2), ("2E6B3C", 1)],
    ),
    "heroi_libertacao": ("estrela", "ouro", None, [("C8201E", 4), ("F2C230", 2)]),
    "unit_citation": (
        "escudo",
        "ouro",
        (0.03, 0.09, 0.3),
        [("1F4E9C", 4), ("E9C33A", 1), ("1F4E9C", 1)],
    ),
    "irmaos": ("disco", "prata", None, [("56613A", 3), ("D8B24A", 1), ("56613A", 2)]),
    "ordem_cumprida": ("coroa", "ouro", None, [("B3202C", 2), ("F2EEE2", 1), ("B3202C", 3)]),
    "top10": (
        "coroa_estrela",
        "ouro",
        None,
        [("14120C", 2), ("E2B23A", 2), ("14120C", 1), ("E2B23A", 1)],
    ),
}


def rgb(h: str):
    return [(int(h[i : i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4)]


def mat_metal(nome):
    cor, rug = METAIS[nome]
    m = bpy.data.materials.new("Metal" + nome)
    m.use_nodes = True
    n, ln = m.node_tree.nodes, m.node_tree.links
    b = n["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*cor, 1)
    b.inputs["Metallic"].default_value = 1.0
    t = n.new("ShaderNodeTexNoise")
    t.inputs["Scale"].default_value = 90.0
    t.inputs["Detail"].default_value = 6.0
    r = n.new("ShaderNodeMapRange")
    r.inputs["From Min"].default_value = 0.34
    r.inputs["From Max"].default_value = 0.68
    r.inputs["To Min"].default_value = rug - 0.05
    r.inputs["To Max"].default_value = rug + 0.09
    ln.new(t.outputs[0], r.inputs["Value"])
    ln.new(r.outputs[0], b.inputs["Roughness"])
    return m


def mat_esmalte(cor):
    m = bpy.data.materials.new("Esmalte")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*cor, 1)
    b.inputs["Roughness"].default_value = 0.16
    b.inputs["Coat Weight"].default_value = 1.0
    return m


def mat_fita(listras):
    seq = listras + listras[-2::-1]
    total = sum(w for _, w in seq)
    largura = 256
    px = np.zeros((4, largura, 4), dtype=np.float32)
    x = 0.0
    for h, w in seq:
        a, b = int(x / total * largura), int((x + w) / total * largura)
        px[:, a:b, :3] = rgb(h)
        x += w
    px[..., 3] = 1
    im = bpy.data.images.new("Fita", largura, 4, alpha=True, float_buffer=True)
    im.pixels.foreach_set(px.ravel())
    im.pack()
    m = bpy.data.materials.new("Fita")
    m.use_nodes = True
    n, ln = m.node_tree.nodes, m.node_tree.links
    b = n["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.62
    b.inputs["Sheen Weight"].default_value = 0.8
    t = n.new("ShaderNodeTexImage")
    t.image = im
    t.interpolation = "Closest"
    ln.new(t.outputs["Color"], b.inputs["Base Color"])
    tr = n.new("ShaderNodeTexWave")
    tr.inputs["Scale"].default_value = 90.0
    bu = n.new("ShaderNodeBump")
    bu.inputs["Strength"].default_value = 0.14
    ln.new(tr.outputs[0], bu.inputs["Height"])
    ln.new(bu.outputs[0], b.inputs["Normal"])
    return m


def prisma(nome, pts, z0, z1, mat, chanfro=0.018, centro=(0.0, 0.0)):
    """Polígono extrudado de frente para a câmera (-Y), com chanfro."""
    bm = bmesh.new()
    a = [bm.verts.new((x + centro[0], -z0, y + centro[1])) for x, y in pts]
    b = [bm.verts.new((x + centro[0], -z1, y + centro[1])) for x, y in pts]
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    if chanfro:
        md = o.modifiers.new("Chanfro", "BEVEL")
        md.width = chanfro
        md.segments = 2
        md.limit_method = "ANGLE"
        md.angle_limit = math.radians(35)
    return o


def estrela_pts(r, ri=0.42, pontas=5, giro=math.pi / 2):
    return [
        (
            (r if i % 2 == 0 else r * ri) * math.cos(giro + i * math.pi / pontas),
            (r if i % 2 == 0 else r * ri) * math.sin(giro + i * math.pi / pontas),
        )
        for i in range(pontas * 2)
    ]


def circulo(r, n=72):
    return [
        (r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)
    ]


def estrela_facetada(nome, r, z, mat, centro=(0.0, 0.0)):
    bm = bmesh.new()
    cx, cy = centro
    topo = bm.verts.new((cx, -(z + r * 0.34), cy))
    anel = [bm.verts.new((x + cx, -z, y + cy)) for x, y in estrela_pts(r)]
    for i in range(10):
        bm.faces.new((anel[(i + 1) % 10], anel[i], topo))
    bm.faces.new(anel)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def coracao_pts(r, n=64):
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        out.append((x / 17 * r, (y + 2.5) / 15 * r))
    return out


def cruz_pts(r, braco=0.3, patee=True):
    b = r * braco
    f = r * (0.62 if patee else braco)
    q = [(b, b), (f, r), (-f, r), (-b, b)]
    out = []
    for k in range(4):
        c, s = math.cos(k * math.pi / 2), math.sin(k * math.pi / 2)
        out += [(x * c - y * s, x * s + y * c) for x, y in q]
    return out


def escudo_pts(r):
    out = [(-r * 0.82, r * 0.86), (r * 0.82, r * 0.86)]
    for i in range(1, 25):
        t = i / 25
        out.append((r * 0.82 * math.cos(t * math.pi / 2) ** 0.7, r * (0.86 - 1.9 * t**1.5)))
    out.append((0.0, -r * 1.04))
    for i in range(24, 0, -1):
        t = i / 25
        out.append((-r * 0.82 * math.cos(t * math.pi / 2) ** 0.7, r * (0.86 - 1.9 * t**1.5)))
    return out


def fundo_escudo(x, r, dy):
    """Altura da borda de baixo do escudo em x (a mesma curva de escudo_pts)."""
    c = min(abs(x) / (0.82 * r), 1.0) ** (1 / 0.7)
    t = math.acos(c) * 2 / math.pi
    return dy + r * (0.86 - 1.9 * t**1.5)


def listra_pts(x, meia, r, dy, topo):
    """Listra vertical que termina na borda do escudo."""
    n = 6
    baixo = [
        (x - meia + 2 * meia * k / n, fundo_escudo(x - meia + 2 * meia * k / n, r, dy) + 0.012)
        for k in range(n + 1)
    ]
    return [*baixo, (x + meia, topo), (x - meia, topo)]


def louro(metal, r=0.78, z=0.03):
    """Coroa de folhas nos dois lados."""
    for lado in (-1, 1):
        for i in range(16):
            a = math.radians(-74 + i * 9.2)
            cx, cy = lado * r * math.cos(a), r * math.sin(a)
            # a folha acompanha o arco, com a ponta um pouco para fora
            base = a + math.radians(68)
            giro = base if lado > 0 else math.pi - base
            folha = []
            for k in range(14):
                t = 2 * math.pi * k / 14
                x, y = 0.115 * math.cos(t), 0.044 * math.sin(t) * (1 - 0.35 * math.cos(t))
                folha.append(
                    (
                        x * math.cos(giro) - y * math.sin(giro),
                        x * math.sin(giro) + y * math.cos(giro),
                    )
                )
            prisma(f"Folha{lado}_{i}", folha, z, z + 0.05, metal, 0.012, (cx, cy))


def corpo(forma, metal, esmalte):
    if forma == "estrela":
        prisma("Disco", circulo(0.62), 0.0, 0.05, metal, 0.022)
        prisma("Campo", circulo(0.5), 0.05, 0.062, metal, 0.008)
        estrela_facetada("Estrela", 0.92, 0.07, metal)
        prisma("EstrelaBase", estrela_pts(0.92), 0.0, 0.075, metal, 0.016)
    elif forma == "disco":
        prisma("Disco", circulo(0.86), 0.0, 0.07, metal, 0.03)
        prisma("Aro", circulo(0.68), 0.07, 0.08, metal, 0.008)
        estrela_facetada("Estrela", 0.56, 0.085, metal)
    elif forma == "coracao":
        prisma("Coracao", coracao_pts(0.92), 0.0, 0.07, metal, 0.024)
        prisma("Esmalte", coracao_pts(0.74), 0.07, 0.09, esmalte, 0.012)
        estrela_facetada("Estrela", 0.26, 0.095, metal, (0.0, 0.08))
    elif forma == "cruz":
        prisma("Cruz", cruz_pts(0.94), 0.0, 0.075, metal, 0.024)
        prisma("Miolo", circulo(0.3), 0.075, 0.1, metal, 0.016)
        estrela_facetada("Estrela", 0.24, 0.105, metal)
    elif forma == "cruz_grega":
        prisma("Cruz", cruz_pts(0.9, 0.34, False), 0.0, 0.07, metal, 0.024)
        prisma("Esmalte", cruz_pts(0.72, 0.31, False), 0.07, 0.09, esmalte, 0.01)
    elif forma == "escudo":
        prisma("Escudo", escudo_pts(0.86), 0.0, 0.07, metal, 0.024)
        prisma("Esmalte", escudo_pts(0.68), 0.07, 0.09, esmalte, 0.01)
        estrela_facetada("Estrela", 0.4, 0.095, metal, (0.0, 0.05))
    elif forma == "coroa":
        louro(metal)
        prisma("Disco", circulo(0.55), 0.0, 0.07, metal, 0.024)
        estrela_facetada("Estrela", 0.42, 0.075, metal)
    elif forma == "coroa_estrela":
        louro(metal)
        prisma("Disco", circulo(0.46), 0.0, 0.06, metal, 0.02)
        prisma("EstrelaBase", estrela_pts(0.8), 0.06, 0.1, metal, 0.016)
        estrela_facetada("Estrela", 0.8, 0.1, metal)


def fita(listras):
    m = mat_fita(listras)
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=24, y_subdivisions=8, size=1.0)
    o = bpy.context.active_object
    o.rotation_euler = (math.pi / 2, 0, 0)
    o.scale = (0.98, 0.66, 1)
    o.location = (0, 0.05, 1.42)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for v in o.data.vertices:
        v.co.y += 0.02 * math.sin(v.co.x * 7.5 + v.co.z * 2.2)
        v.co.x *= 1 - 0.12 * max(1.08 - v.co.z, 0)
    uv = o.data.uv_layers.active or o.data.uv_layers.new()
    for lp in o.data.loops:
        co = o.data.vertices[lp.vertex_index].co
        uv.data[lp.index].uv = (co.x / 0.98 + 0.5, 0.5)
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()


def argola(metal):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.12, minor_radius=0.032, location=(0, 0.02, 1.03)
    )
    o = bpy.context.active_object
    o.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.shade_smooth()
    o.data.materials.append(metal)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.03, 1.12))
    b = bpy.context.active_object
    b.scale = (0.56, 0.05, 0.06)
    b.data.materials.append(metal)


def estudio():
    cena = bpy.context.scene
    mundo = bpy.data.worlds.new("Mundo")
    mundo.use_nodes = True
    f = mundo.node_tree.nodes["Background"]
    f.inputs["Color"].default_value = (1.0, 0.9, 0.76, 1)
    f.inputs["Strength"].default_value = 0.34
    cena.world = mundo
    for nome, pos, tam, forca, cor in (
        ("Teto", (-1.2, -4.0, 4.6), (7.0, 4.0), 7.0, (1.0, 0.94, 0.82)),
        ("Lado", (-5.0, -2.6, 0.4), (2.0, 6.0), 9.0, (1.0, 0.88, 0.7)),
        ("Frio", (5.0, -3.0, 1.0), (2.0, 5.0), 3.0, (0.72, 0.82, 1.0)),
        ("Baixo", (0.6, -4.0, -3.4), (5.0, 1.6), 3.2, (1.0, 0.78, 0.52)),
    ):
        p = Vector(pos)
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=p)
        o = bpy.context.active_object
        o.name = "Reb" + nome
        o.scale = (tam[0], tam[1], 1)
        o.rotation_euler = (Vector((0, 0, 0.3)) - p).to_track_quat("Z", "Y").to_euler()
        m = bpy.data.materials.new("Reb" + nome)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (0, 0, 0, 1)
        b.inputs["Emission Color"].default_value = (*cor, 1)
        b.inputs["Emission Strength"].default_value = forca
        o.data.materials.append(m)
        o.visible_camera = False
        o.visible_shadow = False


def camera(escala, z):
    cena = bpy.context.scene
    cam = bpy.data.cameras.new("Camera")
    cam.type = "ORTHO"
    cam.ortho_scale = escala
    o = bpy.data.objects.new("Camera", cam)
    d = Vector((-0.2, -1.0, 0.1)).normalized()
    alvo = Vector((0, 0, z))
    o.location = alvo + d * 8
    o.rotation_euler = (alvo - o.location).to_track_quat("-Z", "Y").to_euler()
    cena.collection.objects.link(o)
    cena.camera = o


def preparar(lado, amostras):
    C.cena_vazia()
    cena = bpy.context.scene
    L.configurar(cena, lado, lado, amostras)
    cena.view_settings.view_transform = "Standard"
    try:
        cena.view_settings.look = "None"
    except TypeError:
        pass
    cena.view_settings.exposure = -0.75
    return cena


def medalha(chave, amostras):
    forma, metal, esmalte, listras = MEDALHAS[chave]
    cena = preparar(320, amostras)
    m = mat_metal(metal)
    corpo(forma, m, mat_esmalte(esmalte) if esmalte else None)
    argola(m)
    fita(listras)
    estudio()
    camera(2.98, 0.42)
    SAIDA.mkdir(parents=True, exist_ok=True)
    cena.render.filepath = str(SAIDA / f"med_{chave}.png")
    bpy.ops.render.render(write_still=True)
    print("ok", chave, flush=True)


def asa(lado, metal):
    for fila, (n, r0, comp) in enumerate(((7, 0.5, 0.56), (6, 0.46, 0.4), (5, 0.42, 0.27))):
        for i in range(n):
            a = math.radians(8 + i * (62 / max(n - 1, 1)))
            cx = lado * (r0 + 0.04 * i + comp * 0.5 * math.cos(a))
            cy = 0.1 + fila * -0.02 + (r0 * 0.28 + comp * 0.5) * math.sin(a)
            g = a if lado > 0 else math.pi - a
            pena = []
            for k in range(12):
                t = 2 * math.pi * k / 12
                x, y = comp * 0.56 * math.cos(t), 0.058 * math.sin(t)
                pena.append((x * math.cos(g) - y * math.sin(g), x * math.sin(g) + y * math.cos(g)))
            prisma(
                f"Pena{lado}{fila}{i}",
                pena,
                0.0 + fila * 0.018,
                0.04 + fila * 0.018,
                metal,
                0.01,
                (cx, cy),
            )


def prestigio(amostras):
    cena = preparar(512, amostras)
    ouro = mat_metal("ouro")
    azul = mat_esmalte((0.02, 0.05, 0.2))
    verm = mat_esmalte((0.5, 0.02, 0.03))
    louro(ouro, 0.92, 0.0)
    asa(1, ouro)
    asa(-1, ouro)
    prisma("Escudo", escudo_pts(0.56), 0.05, 0.12, ouro, 0.02, (0.0, -0.06))
    prisma("Campo", escudo_pts(0.46), 0.12, 0.135, azul, 0.006, (0.0, -0.06))
    for i in range(-2, 3):
        x = i * 0.13
        prisma(
            f"Listra{i}",
            listra_pts(x, 0.04, 0.46, -0.06, 0.02),
            0.135,
            0.145,
            verm,
            0.0,
        )
    estrela_facetada("Estrela", 0.21, 0.15, ouro, (0.0, 0.2))
    estrela_facetada("Topo", 0.17, 0.05, ouro, (0.0, 0.9))
    estudio()
    camera(2.5, 0.08)
    SAIDA.mkdir(parents=True, exist_ok=True)
    cena.render.filepath = str(SAIDA / "prestigio.png")
    bpy.ops.render.render(write_still=True)
    print("ok prestigio", flush=True)


def principal():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    amostras = int(args[args.index("--amostras") + 1]) if "--amostras" in args else 64
    so = args[args.index("--so") + 1].split(",") if "--so" in args else [*MEDALHAS, "prestigio"]
    for k in so:
        if k == "prestigio":
            prestigio(amostras)
        else:
            medalha(k, amostras)


principal()
