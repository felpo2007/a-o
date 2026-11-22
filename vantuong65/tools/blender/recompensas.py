"""Imagens dos 7 dias da recompensa diária (D-236), em Cycles, fundo transparente.

Pedido do dono: "melhore oq eu apontei nas imagens com imagens melhores feitas com qualidade,
efeitos visuais". No lugar do emoji, cada dia mostra o que paga: as moedas crescem de pilha em pilha
(dias 1, 2, 4, 5 e 6), o dia 3 é um presente com moedas e o dia 7, um baú aberto cheio de ouro. Tudo
é modelado aqui.

Saídas: assets/ui/recompensas/r<dia>.png, 512 x 512, RGBA.

Uso (sempre na CPU: a GPU de 2 GB é do Studio):
    $env:VT65_CPU = "1"; $env:VT65_THREADS = "4"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/recompensas.py -- todas [--amostras 96] [--teste]
"""

from __future__ import annotations

import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import loja as L  # noqa: E402

SAIDA = C.RAIZ / "assets" / "ui" / "recompensas"
ALTURA_MOEDA = 0.098


def mat(nome, cor, metal=0.0, rug=0.5, clear=0.0, emissao=0.0):
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*cor, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rug
    if clear:
        b.inputs["Coat Weight"].default_value = clear
        b.inputs["Coat Roughness"].default_value = 0.12
    if emissao:
        b.inputs["Emission Color"].default_value = (*cor, 1)
        b.inputs["Emission Strength"].default_value = emissao
    return m


def mat_ouro():
    m = mat("Ouro", (1.0, 0.66, 0.16), metal=1.0, rug=0.24)
    n = m.node_tree.nodes
    ln = m.node_tree.links
    b = n["Principled BSDF"]
    t = n.new("ShaderNodeTexNoise")
    t.inputs["Scale"].default_value = 90.0
    t.inputs["Detail"].default_value = 6.0
    r = n.new("ShaderNodeMapRange")
    r.inputs["From Min"].default_value = 0.35
    r.inputs["From Max"].default_value = 0.68
    r.inputs["To Min"].default_value = 0.19
    r.inputs["To Max"].default_value = 0.25
    ln.new(t.outputs[0], r.inputs["Value"])
    ln.new(r.outputs[0], b.inputs["Roughness"])
    return m


def mat_madeira(nome, cor):
    m = mat(nome, cor, rug=0.52, clear=0.25)
    n = m.node_tree.nodes
    ln = m.node_tree.links
    b = n["Principled BSDF"]
    co = n.new("ShaderNodeTexCoord")
    ma = n.new("ShaderNodeMapping")
    ma.inputs["Scale"].default_value = (2.0, 16.0, 2.0)
    w = n.new("ShaderNodeTexNoise")
    w.inputs["Scale"].default_value = 5.0
    w.inputs["Detail"].default_value = 9.0
    w.inputs["Distortion"].default_value = 1.4
    rp = n.new("ShaderNodeValToRGB")
    rp.color_ramp.elements[0].position = 0.34
    rp.color_ramp.elements[0].color = (cor[0] * 0.42, cor[1] * 0.40, cor[2] * 0.38, 1)
    rp.color_ramp.elements[1].position = 0.68
    rp.color_ramp.elements[1].color = (cor[0] * 1.2, cor[1] * 1.16, cor[2] * 1.08, 1)
    ln.new(co.outputs["Object"], ma.inputs["Vector"])
    ln.new(ma.outputs[0], w.inputs["Vector"])
    ln.new(w.outputs[0], rp.inputs[0])
    ln.new(rp.outputs[0], b.inputs["Base Color"])
    return m


def suaviza(o, bevel=0.0, seg=3):
    for p in o.data.polygons:
        p.use_smooth = True
    if bevel:
        b = o.modifiers.new("Chanfro", "BEVEL")
        b.width = bevel
        b.segments = seg
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(35)
    w = o.modifiers.new("Normal", "WEIGHTED_NORMAL")
    w.keep_sharp = True


def malha(nome, bm, material):
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def caixa(nome, dim, centro, material, bevel=0.02):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(dim), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(centro), verts=bm.verts)
    o = malha(nome, bm, material)
    suaviza(o, bevel)
    return o


def estrela_verts(raio, z, pontas=5):
    out = []
    for i in range(pontas * 2):
        r = raio if i % 2 == 0 else raio * 0.42
        a = math.pi / 2 + i * math.pi / pontas
        out.append((r * math.cos(a), r * math.sin(a), z))
    return out


def fator_hex(a: float) -> float:
    """D-246: raio do sextavado de pontas para cima, igual ao de tools/blender/moeda_hex.py."""
    setor = math.pi / 3
    u = (a - math.pi / 2 + setor / 2) % setor - setor / 2
    reto = math.cos(setor / 2) / math.cos(u)
    return reto * 0.94 + 0.06 * math.cos(setor / 2)


def malha_moeda(ouro):
    """A moeda sextavada (D-246): aro alto, sextavado gravado e estrela facetada nas duas faces."""
    bm = bmesh.new()
    h = ALTURA_MOEDA / 2
    # perfil girado: do centro ao aro, em cima; o aro; e de volta embaixo
    perfil = [
        (0.0, h * 0.62),
        (0.355, h * 0.62),
        (0.362, h * 0.76),
        (0.372, h * 0.62),
        (0.425, h * 0.62),
        (0.445, h),
        (0.492, h),
        (0.5, h * 0.72),
        (0.5, -h * 0.72),
        (0.492, -h),
        (0.445, -h),
        (0.425, -h * 0.62),
        (0.0, -h * 0.62),
    ]
    n = 72
    aneis = []
    for i in range(n):
        a = 2 * math.pi * i / n
        k = fator_hex(a)
        aneis.append(
            [bm.verts.new((r * k * math.cos(a), r * k * math.sin(a), z)) for r, z in perfil]
        )
    for i in range(n):
        a, b = aneis[i], aneis[(i + 1) % n]
        for j in range(len(perfil) - 1):
            if perfil[j][0] == 0.0:
                bm.faces.new((a[j], a[j + 1], b[j + 1]))
            elif perfil[j + 1][0] == 0.0:
                bm.faces.new((a[j], a[j + 1], b[j]))
            else:
                bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # estrela de dez facetas, em cima e embaixo
    for sinal in (1, -1):
        base = [bm.verts.new(v) for v in estrela_verts(0.262, sinal * h * 0.62)]
        topo = bm.verts.new((0, 0, sinal * h * 1.5))
        q = len(base)
        for i in range(q):
            f = (base[i], base[(i + 1) % q], topo)
            bm.faces.new(f if sinal > 0 else f[::-1])
    me = bpy.data.meshes.new("Moeda")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(ouro)
    return me


class Cena:
    def __init__(self) -> None:
        C.cena_vazia()
        self.objs = []
        self.ouro = mat_ouro()
        self.me = malha_moeda(self.ouro)
        self.rng = random.Random(65)

    def moeda(self, pos, giro=(0.0, 0.0, 0.0)):
        o = bpy.data.objects.new("Moeda", self.me)
        bpy.context.scene.collection.objects.link(o)
        o.location = Vector(pos)
        o.rotation_euler = Euler(giro)
        self.objs.append(o)
        return o

    def pilha(self, x, y, n, z0=0.0):
        r = self.rng
        for i in range(n):
            self.moeda(
                (
                    x + r.uniform(-0.026, 0.026),
                    y + r.uniform(-0.026, 0.026),
                    z0 + ALTURA_MOEDA * (i + 0.5),
                ),
                (r.uniform(-0.012, 0.012), r.uniform(-0.012, 0.012), r.uniform(0, 6.28)),
            )
        return z0 + ALTURA_MOEDA * n

    def encostada(self, x, y, ang=1.05, giro=0.0):
        """Moeda apoiada no chão, inclinada e virada para a câmera."""
        z = 0.5 * math.sin(ang) + ALTURA_MOEDA / 2 * math.cos(ang)
        return self.moeda((x, y, z), (ang, 0.0, giro))

    def deitada(self, x, y, z=None):
        z = ALTURA_MOEDA / 2 if z is None else z
        return self.moeda((x, y, z), (0.0, 0.0, self.rng.uniform(0, 6.28)))

    def add(self, *objs):
        self.objs.extend(objs)


def d1(c: Cena):
    c.pilha(0.28, 0.2, 3)
    c.deitada(-0.56, 0.08)
    c.encostada(-0.08, -0.46, 1.0, -0.25)


def d2(c: Cena):
    c.pilha(-0.36, 0.25, 6)
    c.pilha(0.62, 0.22, 2)
    c.encostada(0.12, -0.5, 1.05, -0.2)


def presente(c: Cena):
    papel = mat("Papel", (0.46, 0.018, 0.026), rug=0.46, clear=0.12)
    fita = mat("Fita", (1.0, 0.72, 0.2), metal=0.65, rug=0.26, clear=0.4)
    a = 1.18
    c.add(caixa("Corpo", (1.6, 1.6, a), (0.12, 0.32, a / 2), papel, 0.025))
    c.add(caixa("Tampa", (1.72, 1.72, 0.26), (0.12, 0.32, a + 0.1), papel, 0.03))
    for dim, centro in (
        ((0.27, 1.75, 0.285), (0.12, 0.32, a + 0.1)),
        ((1.75, 0.27, 0.285), (0.12, 0.32, a + 0.1)),
        ((0.27, 1.63, a), (0.12, 0.32, a / 2)),
        ((1.63, 0.27, a), (0.12, 0.32, a / 2)),
    ):
        c.add(caixa("Faixa", dim, centro, fita, 0.008))
    topo = a + 0.24
    for sinal in (-1, 1):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=0.3, minor_radius=0.075, major_segments=48, minor_segments=14
        )
        o = bpy.context.active_object
        o.data.materials.append(fita)
        o.location = (0.12 + sinal * 0.32, 0.32, topo + 0.2)
        o.rotation_euler = (math.radians(90), math.radians(sinal * 22), math.radians(sinal * 12))
        o.scale = (1.15, 0.72, 0.8)
        suaviza(o)
        c.add(o)
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.15, segments=32, ring_count=20, location=(0.12, 0.32, topo + 0.1)
    )
    o = bpy.context.active_object
    o.data.materials.append(fita)
    suaviza(o)
    c.add(o)
    c.pilha(-0.95, -0.52, 3)
    c.encostada(0.0, -0.98, 1.08, -0.15)
    c.deitada(0.92, -0.86)


def d4(c: Cena):
    c.pilha(-0.56, 0.24, 8)
    c.pilha(0.42, 0.36, 5)
    c.pilha(0.74, -0.42, 2)
    c.encostada(-0.14, -0.58, 1.05, -0.2)


def d5(c: Cena):
    c.pilha(-0.74, 0.28, 7)
    c.pilha(0.18, 0.48, 10)
    c.pilha(0.92, 0.1, 5)
    c.pilha(-0.2, -0.46, 3)
    c.encostada(0.62, -0.74, 1.05, -0.3)


def d6(c: Cena):
    for x, y, n in (
        (-1.0, 0.4, 7),
        (-0.08, 0.68, 12),
        (0.86, 0.44, 9),
        (-0.52, -0.42, 4),
        (0.42, -0.34, 6),
    ):
        c.pilha(x, y, n)
    c.encostada(-0.08, -1.04, 1.08, -0.1)
    c.encostada(1.08, -0.62, 1.0, -0.48)
    c.deitada(-1.12, -0.74)


def bau(c: Cena):
    w, p, a = 2.5, 1.56, 1.02
    madeira = mat_madeira("Madeira", (0.17, 0.066, 0.026))
    ferro = mat("Ferragem", (0.92, 0.62, 0.17), metal=1.0, rug=0.3)
    escuro = mat("Fundo", (0.03, 0.018, 0.012), rug=0.8)
    # paredes (por dentro fica oco para o ouro aparecer)
    c.add(caixa("Fundo", (w, p, 0.09), (0, 0, 0.045), madeira))
    c.add(caixa("Frente", (w, 0.09, a), (0, -p / 2 + 0.045, a / 2), madeira))
    c.add(caixa("Tras", (w, 0.09, a), (0, p / 2 - 0.045, a / 2), madeira))
    c.add(caixa("Esq", (0.09, p, a), (-w / 2 + 0.045, 0, a / 2), madeira))
    c.add(caixa("Dir", (0.09, p, a), (w / 2 - 0.045, 0, a / 2), madeira))
    c.add(caixa("Miolo", (w - 0.2, p - 0.2, a - 0.2), (0, 0, (a - 0.2) / 2 + 0.03), escuro, 0.0))
    for x in (-w / 2 + 0.3, 0.0, w / 2 - 0.3):
        c.add(caixa("Cinta", (0.17, p + 0.05, 0.1), (x, 0, 0.05), ferro, 0.012))
        c.add(caixa("CintaF", (0.17, 0.05, a + 0.04), (x, -p / 2 - 0.008, a / 2), ferro, 0.012))
    c.add(caixa("Borda", (w + 0.05, 0.08, 0.1), (0, -p / 2 - 0.006, a - 0.03), ferro, 0.012))
    c.add(caixa("Tranca", (0.3, 0.07, 0.36), (0, -p / 2 - 0.035, a - 0.22), ferro, 0.016))
    # tampa aberta, para trás
    tampa = []
    pl = 1.5
    tampa.append(caixa("Tampa", (w, pl, 0.11), (0, pl / 2, 0), madeira))
    for x in (-w / 2 + 0.3, 0.0, w / 2 - 0.3):
        tampa.append(caixa("TampaC", (0.17, pl + 0.03, 0.15), (x, pl / 2, 0), ferro, 0.012))
    piv = bpy.data.objects.new("PivoTampa", None)
    bpy.context.scene.collection.objects.link(piv)
    piv.location = (0, p / 2 - 0.05, a + 0.02)
    piv.rotation_euler = (math.radians(104), 0, 0)
    for o in tampa:
        o.parent = piv
    c.add(*tampa)
    # o monte de ouro
    r = c.rng
    for _ in range(250):
        x = r.uniform(-w / 2 + 0.2, w / 2 - 0.2)
        y = r.uniform(-p / 2 + 0.17, p / 2 - 0.17)
        k = max(0.0, 1 - (x / (w / 2)) ** 2 - (y / (p / 2)) ** 2)
        z = a - 0.13 + 0.56 * k**0.7 + r.uniform(-0.04, 0.03)
        c.moeda((x, y, z), (r.uniform(-0.42, 0.42), r.uniform(-0.42, 0.42), r.uniform(0, 6.28)))
    # o brilho que sai de dentro
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, a + 0.05))
    luz = bpy.context.active_object
    luz.scale = (w * 0.8, p * 0.68, 1)
    luz.data.materials.append(mat("Luz", (1.0, 0.66, 0.2), emissao=5.0))
    luz.visible_camera = False
    c.pilha(-1.5, -1.0, 3)
    c.deitada(1.35, -1.12)
    c.encostada(0.5, -1.28, 1.05, -0.3)


CENAS = {
    "r1": d1,
    "r2": d2,
    "r3": presente,
    "r4": d4,
    "r5": d5,
    "r6": d6,
    "r7": bau,
}  # D-246: a moeda sozinha sai de tools/blender/moeda_hex.py


def rebatedores(centro, raio):
    """Painéis de luz que só o reflexo vê: é deles que o ouro tira o brilho."""
    for nome, pos, tam, forca, cor in (
        ("Teto", (-0.5, -0.5, 3.0), (5.0, 3.0), 0.5, (1.0, 0.95, 0.86)),
        ("Frente", (-0.5, -3.2, 1.3), (4.4, 2.6), 0.85, (1.0, 0.94, 0.84)),
        ("Lado", (-3.2, -1.2, 1.0), (1.2, 4.0), 3.4, (1.0, 0.92, 0.8)),
        ("Frio", (3.2, -1.6, 1.0), (1.6, 3.2), 1.3, (0.74, 0.84, 1.0)),
    ):
        p = centro + Vector(pos) * raio
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=p)
        o = bpy.context.active_object
        o.name = "Rebatedor" + nome
        o.scale = (tam[0] * raio, tam[1] * raio, 1)
        o.rotation_euler = (centro - p).to_track_quat("Z", "Y").to_euler()
        o.data.materials.append(mat("Reb" + nome, cor, emissao=forca))
        o.visible_camera = False
        o.visible_shadow = False
        o.visible_diffuse = False


def render(chave, amostras, teste):
    c = Cena()
    cena = bpy.context.scene
    lado = 256 if teste else 512
    L.configurar(cena, lado, lado, amostras)
    cena.view_settings.view_transform = "Standard"
    try:
        cena.view_settings.look = "None"
    except TypeError:
        pass
    cena.view_settings.exposure = -1.05
    CENAS[chave](c)
    bpy.context.view_layer.update()
    cam, centro, raio = L.camera_para(
        c.objs, lado, lado, direcao=(-0.42, -1.0, 0.72), lente=62.0, folga=1.12
    )
    L.estudio(centro, raio)
    rebatedores(centro, raio)
    SAIDA.mkdir(parents=True, exist_ok=True)
    nome = ("teste_" if teste else "") + chave + ".png"
    cena.render.filepath = str(SAIDA / nome)
    bpy.ops.render.render(write_still=True)
    borda(SAIDA / nome)
    print("ok", nome, flush=True)


def borda(caminho: Path, faixa: float = 0.07) -> None:
    """A sombra no chão chegava à borda do quadro e marcava uma linha reta: ela some antes."""
    im = bpy.data.images.load(str(caminho))
    w, h = im.size
    px = np.empty(w * h * 4, dtype=np.float32)
    im.pixels.foreach_get(px)
    a = px.reshape(h, w, 4)
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum.reduce([xx, w - 1 - xx, yy, h - 1 - yy]) / w
    t = np.clip(d / faixa, 0, 1)
    a[..., 3] *= t * t * (3 - 2 * t)
    im.pixels.foreach_set(a.ravel())
    im.filepath_raw = str(caminho)
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def principal():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    amostras = 96
    if "--amostras" in args:
        amostras = int(args[args.index("--amostras") + 1])
    teste = "--teste" in args
    if "--so-borda" in args:
        for k in CENAS:
            borda(SAIDA / f"{k}.png")
        return
    alvos = [a for a in args if a in CENAS]
    if "todas" in args or not alvos:
        alvos = list(CENAS)
    for k in alvos:
        render(k, amostras, teste)


principal()
