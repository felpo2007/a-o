"""Bandeiras de pano da escolha de idioma (D-246), em Cycles, com fundo transparente.

Pedido do dono: "estava falando de mudar as bandeiras na escolha da lingua". Cada bandeira é
desenhada por geometria (sem imagem de fora), vira a textura de um pano ondulado e sai em
480 x 320, RGBA, em
assets/ui/idiomas/<código>.png. "auto" é um globo de latão.

    $env:VT65_CPU = "1"; $env:VT65_THREADS = "3"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/bandeiras_idioma.py -- [--amostras 64] [--so pt,en]
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import loja as L  # noqa: E402

SAIDA = C.RAIZ / "assets" / "ui" / "idiomas"
W, H = 900, 600
LARGURA, ALTURA = 480, 320
CODIGOS = ("pt", "en", "es", "vi", "auto")


def cor(hexa: str) -> np.ndarray:
    return np.array([int(hexa[i : i + 2], 16) / 255 for i in (0, 2, 4)])


def grade() -> tuple[np.ndarray, np.ndarray]:
    """Coordenadas em alturas da bandeira: x de 0 a 1,5 e y de 0 a 1, com y para cima."""
    y, x = np.mgrid[0:H, 0:W]
    return (x + 0.5) / H, (y + 0.5) / H


def estrela(x, y, cx: float, cy: float, r: float) -> np.ndarray:
    """Máscara de uma estrela de cinco pontas com uma ponta para cima."""
    dx, dy = x - cx, y - cy
    rho = np.hypot(dx, dy)
    passo = 2 * math.pi / 5
    t = np.abs((np.arctan2(dx, dy) + passo / 2) % passo - passo / 2)
    px, py = rho * np.sin(t), rho * np.cos(t)
    ri = r * 0.382
    ix, iy = ri * math.sin(passo / 2), ri * math.cos(passo / 2)
    return ix * (py - r) - (iy - r) * px < 0


def pinta(img: np.ndarray, mascara: np.ndarray, c: np.ndarray) -> None:
    img[mascara] = c


def brasil() -> np.ndarray:
    x, y = grade()
    img = np.ones((H, W, 3)) * cor("009C3B")
    # módulos da lei: 20 x 14
    mx, my = x / 1.5 * 20, y * 14
    pinta(img, np.abs(mx - 10) / 8.3 + np.abs(my - 7) / 5.3 <= 1, cor("FFDF00"))
    azul = np.hypot(mx - 10, my - 7) <= 3.5
    pinta(img, azul, cor("002776"))
    d = np.hypot(mx - 8, my)
    pinta(img, azul & (d >= 8.0) & (d <= 8.5), cor("F4F4EE"))
    for cx, cy, r in (
        (9.0, 5.6, 0.2),
        (10.2, 5.0, 0.24),
        (11.3, 5.7, 0.18),
        (8.3, 6.5, 0.15),
        (11.9, 6.6, 0.15),
        (10.1, 6.1, 0.14),
        (10.7, 8.6, 0.2),
    ):
        pinta(img, estrela(mx, my, cx, cy, r), cor("F4F4EE"))
    return img


def eua() -> np.ndarray:
    x, y = grade()
    img = np.ones((H, W, 3)) * cor("F4F2EA")
    pinta(img, np.floor((1 - y) * 13).astype(int) % 2 == 0, cor("B22234"))
    cw, ch = 0.6, 7 / 13
    pinta(img, (x <= cw) & (y >= 1 - ch), cor("2B3A78"))
    for linha in range(1, 10):
        yy = 1 - ch * linha / 10
        n = 6 if linha % 2 else 5
        for j in range(n):
            k = 2 * j + 1 if linha % 2 else 2 * j + 2
            pinta(img, estrela(x, y, cw * k / 12, yy, 0.0285), cor("F4F2EA"))
    return img


def espanha() -> np.ndarray:
    _x, y = grade()
    img = np.ones((H, W, 3)) * cor("AA151B")
    pinta(img, (y >= 0.25) & (y <= 0.75), cor("F1BF00"))
    return img


def vietna() -> np.ndarray:
    x, y = grade()
    img = np.ones((H, W, 3)) * cor("DA251D")
    pinta(img, estrela(x, y, 0.75, 0.49, 0.335), cor("FFDD00"))
    return img


DESENHOS = {"pt": brasil, "en": eua, "es": espanha, "vi": vietna}


def imagem(nome: str, rgb: np.ndarray):
    im = bpy.data.images.new(nome, W, H, alpha=True)
    rgba = np.concatenate([rgb, np.ones((H, W, 1))], axis=2).astype(np.float32)
    im.pixels.foreach_set(rgba.ravel())
    im.update()
    im.pack()
    return im


def mat_pano(im):
    m = bpy.data.materials.new("Pano")
    m.use_nodes = True
    n, ln = m.node_tree.nodes, m.node_tree.links
    b = n["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.66
    b.inputs["Sheen Weight"].default_value = 0.55
    t = n.new("ShaderNodeTexImage")
    t.image = im
    t.interpolation = "Cubic"
    ln.new(t.outputs["Color"], b.inputs["Base Color"])
    trama = n.new("ShaderNodeTexWave")
    trama.inputs["Scale"].default_value = 340.0
    trama.inputs["Distortion"].default_value = 0.6
    relevo = n.new("ShaderNodeBump")
    relevo.inputs["Strength"].default_value = 0.1
    relevo.inputs["Distance"].default_value = 0.004
    ln.new(trama.outputs[0], relevo.inputs["Height"])
    ln.new(relevo.outputs[0], b.inputs["Normal"])
    return m


def pano(mat):
    nx, ny = 150, 100
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    vs = []
    for j in range(ny + 1):
        v = j / ny
        for i in range(nx + 1):
            u = i / nx
            a = 0.05 + 0.16 * u
            f1 = math.sin(2 * math.pi * (1.45 * u + 0.2 * v) + 0.5)
            f2 = math.sin(2 * math.pi * (3.1 * u - 0.35 * v) + 1.4)
            vs.append(
                bm.verts.new(
                    (
                        (u - 0.5) * 3.0 - 0.05 * u * (f1 + 0.5),
                        a * (f1 + 0.36 * f2),
                        (v - 0.5) * 2.0 + 0.25 * a * math.cos(2 * math.pi * (1.45 * u) + 0.5),
                    )
                )
            )
    for j in range(ny):
        for i in range(nx):
            q = j * (nx + 1) + i
            f = bm.faces.new((vs[q], vs[q + 1], vs[q + nx + 2], vs[q + nx + 1]))
            f.smooth = True
            cantos = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            for lo, (a, b) in zip(f.loops, cantos, strict=True):
                lo[uv].uv = (a / nx, b / ny)
    me = bpy.data.meshes.new("Pano")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new("Pano", me)
    bpy.context.scene.collection.objects.link(o)
    return o


def globo():
    y, x = np.mgrid[0:H, 0:W]
    u, v = (x + 0.5) / W, (y + 0.5) / H
    rgb = np.ones((H, W, 3)) * cor("1E3A5C")
    linha = (np.abs((u * 12) % 1 - 0.5) > 0.47) | (np.abs((v * 8) % 1 - 0.5) > 0.46)
    rgb[linha] = cor("F0C860")
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=40, radius=0.9)
    esfera = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    esfera.rotation_euler = (math.radians(14), math.radians(-18), 0)
    m = mat_pano(imagem("Globo", rgb))
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.38
    esfera.data.materials.append(m)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.99, minor_radius=0.038)
    aro = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    aro.rotation_euler = (math.radians(90), math.radians(24), 0)
    lat = bpy.data.materials.new("Latao")
    lat.use_nodes = True
    b = lat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (1.0, 0.68, 0.22, 1)
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = 0.28
    aro.data.materials.append(lat)


def luz_e_camera() -> None:
    cena = bpy.context.scene
    mundo = bpy.data.worlds.new("Mundo")
    mundo.use_nodes = True
    fundo = mundo.node_tree.nodes["Background"]
    fundo.inputs["Color"].default_value = (1.0, 0.86, 0.68, 1)
    fundo.inputs["Strength"].default_value = 0.58
    cena.world = mundo
    sol = bpy.data.lights.new("Sol", "SUN")
    sol.energy = 2.9
    sol.color = (1.0, 0.86, 0.66)
    sol.angle = math.radians(14)
    o = bpy.data.objects.new("Sol", sol)
    o.rotation_euler = (math.radians(68), math.radians(-30), math.radians(-22))
    cena.collection.objects.link(o)
    cam = bpy.data.cameras.new("Camera")
    cam.type = "ORTHO"
    cam.ortho_scale = 3.18
    oc = bpy.data.objects.new("Camera", cam)
    oc.location = (0, -6, 0)
    oc.rotation_euler = (math.pi / 2, 0, 0)
    cena.collection.objects.link(oc)
    cena.camera = oc


def render(codigo: str, amostras: int) -> None:
    C.cena_vazia()
    cena = bpy.context.scene
    L.configurar(cena, LARGURA, ALTURA, amostras)
    cena.view_settings.view_transform = "Standard"
    try:
        cena.view_settings.look = "None"
    except TypeError:
        pass
    luz_e_camera()
    if codigo == "auto":
        globo()
    else:
        pano(mat_pano(imagem("Bandeira", DESENHOS[codigo]())))
    SAIDA.mkdir(parents=True, exist_ok=True)
    cena.render.filepath = str(SAIDA / f"{codigo}.png")
    bpy.ops.render.render(write_still=True)
    print("ok", codigo, flush=True)


def principal() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    amostras = int(args[args.index("--amostras") + 1]) if "--amostras" in args else 64
    so = args[args.index("--so") + 1].split(",") if "--so" in args else CODIGOS
    for codigo in so:
        render(codigo, amostras)


principal()
