"""Arte dos dois lados na escolha de time (D-240): a bandeira ao vento no pôr do sol da frente.

Dono: "melhore as bandeiras, faça imagens incríveis". Sai a cena de mesa: a bandeira enche o
cartão, com contraluz, palmeiras em silhueta e a linha de sacos de areia. O acabamento (névoa,
raios, brasas e vinheta) vem depois, no `tools/bandeiras_pos.py`.

    $env:VT65_CPU = "1"; $env:VT65_THREADS = "4"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/bandeiras_epicas.py -- us vc --saida PASTA [--teste] [--amostras N]
"""

from __future__ import annotations

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import armas_catalogo as A  # noqa: E402
import caixas_loja as K  # noqa: E402
import comum as C  # noqa: E402
import loja as L  # noqa: E402

RAIZ = C.RAIZ
FLAGS = RAIZ / "assets" / "bandeiras"

LADOS = {
    "us": {
        "img": FLAGS / "bandeira_eua.png",
        "aspecto": 1.9,
        "ceu": ((1.0, 0.50, 0.16), (0.78, 0.26, 0.15), (0.10, 0.13, 0.25)),
        "fase": 0.15,
    },
    "vc": {
        "img": FLAGS / "bandeira_frente.png",
        "aspecto": 1.667,
        "ceu": ((1.0, 0.36, 0.14), (0.62, 0.14, 0.20), (0.09, 0.07, 0.20)),
        "fase": 0.62,
    },
}


def ceu(cena, cores):
    """Pôr do sol com nuvens rasgadas: laranja no horizonte, noite em cima."""
    w = bpy.data.worlds.new("Ceu")
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes.get("Background")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    alto = nt.nodes.new("ShaderNodeValToRGB")
    alto.color_ramp.elements[0].position = 0.0
    alto.color_ramp.elements[0].color = (*K.lin(cores[0]), 1.0)
    meio = alto.color_ramp.elements.new(0.20)
    meio.color = (*K.lin(cores[1]), 1.0)
    alto.color_ramp.elements[1].position = 0.62
    alto.color_ramp.elements[1].color = (*K.lin(cores[2]), 1.0)
    nt.links.new(sep.outputs["Z"], alto.inputs["Fac"])
    mapa = nt.nodes.new("ShaderNodeMapping")
    mapa.inputs["Scale"].default_value = (1.4, 1.4, 4.2)
    nt.links.new(coord.outputs["Generated"], mapa.inputs["Vector"])
    ruido = nt.nodes.new("ShaderNodeTexNoise")
    ruido.inputs["Scale"].default_value = 3.1
    ruido.inputs["Detail"].default_value = 11.0
    ruido.inputs["Roughness"].default_value = 0.58
    nt.links.new(mapa.outputs[0], ruido.inputs["Vector"])
    corte = nt.nodes.new("ShaderNodeMapRange")
    corte.inputs["From Min"].default_value = 0.50
    corte.inputs["From Max"].default_value = 0.68
    corte.inputs["To Min"].default_value = 0.0
    corte.inputs["To Max"].default_value = 0.82
    nt.links.new(ruido.outputs["Fac"], corte.inputs["Value"])
    mistura = nt.nodes.new("ShaderNodeMix")
    mistura.data_type = "RGBA"
    nt.links.new(corte.outputs["Result"], mistura.inputs["Factor"])
    nt.links.new(alto.outputs["Color"], mistura.inputs["A"])
    mistura.inputs["B"].default_value = (*K.lin((0.13, 0.07, 0.09)), 1.0)
    nt.links.new(mistura.outputs["Result"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.15
    cena.world = w


def pano(lado, largura):
    d = LADOS[lado]
    alt = largura / d["aspecto"]
    fase = d["fase"]
    nx, ny = 260, int(260 / d["aspecto"])
    vs, uv, fs = [], [], []
    for j in range(ny + 1):
        v = j / ny
        for i in range(nx + 1):
            u = i / nx
            amp = 0.05 + 0.46 * u**0.9
            y = amp * (
                math.sin(2 * math.pi * (1.35 * u - 0.20 * v + fase))
                + 0.45 * math.sin(2 * math.pi * (2.9 * u + 0.35 * v + 1.1 + fase))
                + 0.17 * math.sin(2 * math.pi * (6.1 * u - 0.5 * v + 0.4))
            )
            x = u * largura * (1 - 0.07 * u)
            z = (v - 1) * alt - 0.26 * u * u * (1 - 0.4 * v)
            z += 0.05 * u * math.sin(2 * math.pi * (2.2 * u + fase))
            vs.append((x, y, z))
            uv.append((u, v))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            fs.append((a, a + 1, a + nx + 2, a + nx + 1))
    me = bpy.data.meshes.new("Bandeira")
    me.from_pydata(vs, [], fs)
    camada = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        camada.data[lp.index].uv = uv[lp.vertex_index]
    me.shade_smooth()
    m = bpy.data.materials.new("Pano")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    saida = nt.nodes.get("Material Output")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(d["img"]), check_existing=True)
    tex.extension = "EXTEND"
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.66
    b.inputs["Sheen Weight"].default_value = 0.8
    trama = nt.nodes.new("ShaderNodeTexWave")
    trama.inputs["Scale"].default_value = 620.0
    relevo = nt.nodes.new("ShaderNodeBump")
    relevo.inputs["Strength"].default_value = 0.16
    relevo.inputs["Distance"].default_value = 0.002
    nt.links.new(trama.outputs["Fac"], relevo.inputs["Height"])
    nt.links.new(relevo.outputs["Normal"], b.inputs["Normal"])
    # a luz atravessa o pano no contraluz
    trans = nt.nodes.new("ShaderNodeBsdfTranslucent")
    nt.links.new(tex.outputs["Color"], trans.inputs["Color"])
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs[0].default_value = 0.16
    nt.links.new(b.outputs[0], mix.inputs[1])
    nt.links.new(trans.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], saida.inputs["Surface"])
    return A.ligar("Bandeira", me, m), alt


def folha_palmeira(nome, base, rumo, comp, material, rng):
    n = 16
    vs, fs = [], []
    lado = Vector((-rumo.y, rumo.x, 0)).normalized()
    queda = rng.uniform(0.75, 1.15)
    for i in range(n + 1):
        s = i / n
        centro = base + rumo * (s * comp) + Vector((0, 0, comp * (0.34 * s - queda * s * s)))
        meia = 0.34 * math.sin(math.pi * s**0.62) * (0.86 if i % 2 else 1.0)
        vs.append(tuple(centro - lado * meia))
        vs.append(tuple(centro))
        vs.append(tuple(centro + lado * meia))
    for i in range(n):
        a = i * 3
        fs.append((a, a + 1, a + 4, a + 3))
        fs.append((a + 1, a + 2, a + 5, a + 4))
    me = bpy.data.meshes.new(nome)
    me.from_pydata(vs, [], fs)
    me.shade_smooth()
    return A.ligar(nome, me, material)


def palmeira(x, y, h, curva, escuro, rng):
    topo = Vector((x + curva, y, h))
    pts = [
        (x, y, -0.3),
        (x + curva * 0.12, y, h * 0.35),
        (x + curva * 0.5, y, h * 0.72),
        tuple(topo),
    ]
    objs = [A.tubo("Tronco", pts, 0.16, escuro, resolucao=12)]
    for i in range(11):
        a = i * 2 * math.pi / 11 + rng.uniform(-0.2, 0.2)
        rumo = Vector((math.cos(a), math.sin(a), 0))
        objs.append(folha_palmeira("Folha", topo, rumo, rng.uniform(2.0, 2.9), escuro, rng))
    return objs


def bambu(x, y, h, inclina, escuro):
    objs = []
    pts = [(x, y, -0.2), (x + inclina * 0.4, y, h * 0.5), (x + inclina, y, h)]
    objs.append(A.tubo("Bambu", pts, 0.075, escuro, resolucao=10))
    for k in range(1, 9):
        t = k / 9
        px_ = x + inclina * t * t * 0.6 + inclina * t * 0.4
        objs.append(A.toro("No", 0.08, 0.016, escuro, (px_, y, t * h)))
    return objs


def morro(escuro):
    n = 140
    vs, fs = [], []
    for j in range(61):
        yy = -8 + j * 0.8
        for i in range(n + 1):
            xx = -26 + i * 52 / n
            z = 0.24 * math.sin(xx * 0.33 + yy * 0.2) + 0.11 * math.sin(xx * 1.1 + 1.0)
            z += 0.06 * yy + 0.02 * yy * math.sin(xx * 0.21)
            vs.append((xx, yy, z))
    for j in range(60):
        for i in range(n):
            a = j * (n + 1) + i
            fs.append((a, a + 1, a + n + 2, a + n + 1))
    me = bpy.data.meshes.new("Morro")
    me.from_pydata(vs, [], fs)
    me.shade_smooth()
    return A.ligar("Morro", me, escuro)


def sacos(rng):
    lona = A.mat_tecido("Saco", (0.20, 0.17, 0.12), rug=0.95, escala=160)
    objs = []
    for fila in range(3):
        desloc = 0.42 if fila % 2 else 0.0
        for i in range(-11, 12):
            x = i * 0.86 + desloc + rng.uniform(-0.03, 0.03)
            objs.append(
                A.almofada(
                    "Saco",
                    (0.84, 0.46, 0.30),
                    (x, -6.0 + rng.uniform(-0.03, 0.03), 0.62 + fila * 0.27),
                    lona,
                    (rng.uniform(-3, 3), rng.uniform(-3, 3), rng.uniform(-4, 4)),
                )
            )
    return objs


def cena(lado, amostras, teste, saida):
    C.cena_vazia()
    c = bpy.context.scene
    larg, alt = (640, 360) if teste else (1280, 720)
    L.configurar(c, larg, alt, amostras)
    A.acabar(c)
    c.render.film_transparent = False
    ceu(c, LADOS[lado]["ceu"])
    rng = random.Random(65 if lado == "us" else 75)
    escuro = A.mat("Silhueta", (0.022, 0.018, 0.016), rug=0.8, forca=0.0)
    morro(escuro)
    sacos(rng)
    # mastro e bandeira no meio do cartão
    largura = 5.9
    x0, z0 = -3.05, 7.0
    aco = A.mat("Mastro", (0.30, 0.24, 0.17), metal=0.2, rug=0.5, forca=0.0)
    A.torno(
        "Mastro",
        [(0, -0.2), (0.058, -0.2), (0.05, z0 + 0.25), (0, z0 + 0.25)],
        aco,
        (x0, 0, 0),
        n=24,
    )
    A.torno(
        "Ponta",
        [(0, 0), (0.10, 0.02), (0.13, 0.09), (0.09, 0.18), (0, 0.24)],
        A.mat("Latao", (0.90, 0.70, 0.32), metal=1.0, rug=0.26, forca=0.0),
        (x0, 0, z0 + 0.24),
        n=28,
    )
    flag, _ = pano(lado, largura)
    flag.location = (x0 + 0.05, 0, z0)
    # palmeiras e bambus nas bordas do quadro
    for x, y, h, q in (
        (-9.2, 7, 8.4, 0.9),
        (-6.6, 12, 7.2, -0.6),
        (8.8, 8, 8.8, -1.0),
        (6.4, 14, 7.0, 0.7),
    ):
        palmeira(x, y, h, q, escuro, rng)
    if lado == "vc":
        for k in range(16):
            s = -1 if k % 2 else 1
            bambu(
                s * (5.0 + k * 0.42),
                5.0 + (k % 5) * 1.3,
                rng.uniform(6.5, 10.0),
                s * rng.uniform(-0.8, 0.2),
                escuro,
            )
    # câmera baixa, olhando a bandeira de baixo para cima
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 35.0
    cd.dof.use_dof = False
    cam = bpy.data.objects.new("Cam", cd)
    c.collection.objects.link(cam)
    c.camera = cam
    cam.location = (0.0, -12.0, 1.5)
    alvo = Vector((0.0, 0.0, 3.75))
    cam.rotation_euler = (alvo - cam.location).to_track_quat("-Z", "Y").to_euler()
    # luz: o sol baixo por trás, à esquerda, e o reflexo quente que mostra as cores do pano
    sol = bpy.data.lights.new("Sol", "SUN")
    sol.energy = 3.2
    sol.color = (1.0, 0.62, 0.32)
    sol.angle = math.radians(3)
    o = bpy.data.objects.new("Sol", sol)
    c.collection.objects.link(o)
    o.rotation_euler = (math.radians(100), math.radians(-28), math.radians(-34))
    L.luz_area("Frente", (-3.0, -11.0, 5.2), (0.0, 0.0, 5.0), 620, (1.0, 0.90, 0.78), 8.0)
    L.luz_area("Lado", (9.0, -7.0, 3.0), (0.0, 0.0, 5.0), 120, (0.60, 0.70, 1.0), 6.0)
    saida.mkdir(parents=True, exist_ok=True)
    c.render.image_settings.color_mode = "RGB"
    c.render.filepath = str(saida / f"{lado}_base.png")
    bpy.ops.render.render(write_still=True)
    # a máscara do pano: o acabamento não pode lavar as cores da bandeira com o brilho do sol
    branco = bpy.data.materials.new("Mascara")
    branco.use_nodes = True
    nt = branco.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    em.inputs["Strength"].default_value = 1.0
    sai = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], sai.inputs["Surface"])
    preto = bpy.data.materials.new("Fora")
    preto.use_nodes = True
    nt2 = preto.node_tree
    nt2.nodes.clear()
    em2 = nt2.nodes.new("ShaderNodeEmission")
    em2.inputs["Color"].default_value = (0, 0, 0, 1)
    sai2 = nt2.nodes.new("ShaderNodeOutputMaterial")
    nt2.links.new(em2.outputs[0], sai2.inputs["Surface"])
    for ob in c.objects:
        if ob.type in ("MESH", "CURVE"):
            alvo_m = branco if ob.name == "Bandeira" else preto
            ob.data.materials.clear()
            ob.data.materials.append(alvo_m)
        elif ob.type == "LIGHT":
            ob.hide_render = True
    c.world.node_tree.nodes.get("Background").inputs["Strength"].default_value = 0.0
    c.cycles.samples = 8
    c.cycles.use_denoising = False
    c.view_settings.view_transform = "Standard"
    c.view_settings.look = "None"
    c.render.filepath = str(saida / f"{lado}_mask.png")
    bpy.ops.render.render(write_still=True)
    C.log("ok", lado)


def principal():
    args = C.argumentos()
    teste = "--teste" in args
    amostras = (
        int(args[args.index("--amostras") + 1]) if "--amostras" in args else (16 if teste else 96)
    )
    saida = Path(args[args.index("--saida") + 1])
    pulos = {args.index(k) + 1 for k in ("--amostras", "--saida") if k in args}
    ids = [a for i, a in enumerate(args) if i not in pulos and not a.startswith("--")]
    for k in ids or list(LADOS):
        cena(k, amostras, teste, saida)


if __name__ == "__main__":
    principal()
