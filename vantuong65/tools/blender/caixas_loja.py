"""Imagens das caixas de suprimentos para a loja (D-212, pedido do dono de 20/11: "imagens
brilhantes e realistas", "modifique as imagens das caixas"), em Cycles, fundo transparente.

Cada caixa é modelada aqui (nada de terceiro):
- o corpo e a tampa com chanfro, as ripas e os montantes (madeira) ou as nervuras (metal);
- as cantoneiras de aço ou latão, as alças laterais e as cintas;
- o nome em estêncil na frente (fonte Stencil do Windows) e, nas de patente, a estrela no lado;
- a luz da raridade vazando pela fresta da tampa (emissão) e um halo atrás, na cor da caixa.

A luz é a do estúdio do `loja.py` (chave quente, enchimento frio e contraluz) mais um contraluz na
cor da caixa; a câmera enquadra pela caixa dos objetos.

Saídas: `assets/ui/caixas/<id>.png`, 768 x 768, RGBA. Os ids são os do Shared/Caixas.

Uso (sempre na CPU: a GPU de 2 GB é do Studio):
    $env:VT65_CPU = "1"; $env:VT65_THREADS = "6"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/caixas_loja.py -- todas [--amostras 64] [--teste]
    ... -- <id>            (uma caixa)
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import loja as L  # noqa: E402

SAIDA = C.RAIZ / "assets" / "ui" / "caixas"
FONTE = Path("C:/Windows/Fonts/STENCIL.TTF")
FONTE_RESERVA = Path("C:/Windows/Fonts/arialbd.ttf")

# corpo: "madeira" (tábuas e ripas), "pintada" (madeira pintada), "metal" (baú de chapa)
# cores em RGB linear aproximado (0 a 1); "acento" é a luz da raridade e o halo
CAIXAS = {
    "gratuita": {
        "nome": "RECOMPENSA",
        "corpo": "pintada",
        "cor": (0.20, 0.21, 0.09),
        "estencil": (0.95, 0.72, 0.12),
        "canto": "aco",
        "cinta": None,
        "acento": (1.0, 0.62, 0.12),
        "brilho": 4.0,
        "estrela": False,
    },
    "recruta": {
        "nome": "RECRUTA",
        "corpo": "madeira",
        "cor": (0.55, 0.36, 0.17),
        "estencil": (0.05, 0.05, 0.04),
        "canto": "aco",
        "cinta": None,
        "acento": (0.45, 0.95, 0.35),
        "brilho": 3.0,
        "estrela": False,
    },
    "servico": {
        "nome": "SERVIÇO",
        "corpo": "pintada",
        "cor": (0.13, 0.16, 0.07),
        "estencil": (0.92, 0.92, 0.86),
        "canto": "aco",
        "cinta": (0.30, 0.28, 0.14),
        "acento": (0.55, 1.0, 0.55),
        "brilho": 3.5,
        "estrela": False,
    },
    "batalhao": {
        "nome": "BATALHÃO",
        "corpo": "metal",
        "cor": (0.05, 0.10, 0.06),
        "estencil": (0.95, 0.95, 0.9),
        "canto": "latao",
        "cinta": None,
        "acento": (0.35, 0.6, 1.0),
        "brilho": 5.0,
        "estrela": True,
    },
    "campanha": {
        "nome": "CAMPANHA",
        "corpo": "madeira",
        "cor": (0.42, 0.27, 0.12),
        "estencil": (0.95, 0.93, 0.85),
        "canto": "aco",
        "cinta": (0.55, 0.45, 0.25),
        "acento": (0.25, 0.95, 0.85),
        "brilho": 5.0,
        "estrela": False,
    },
    "veterano": {
        "nome": "VETERANO",
        "corpo": "madeira",
        "cor": (0.16, 0.08, 0.035),
        "estencil": (0.95, 0.78, 0.35),
        "canto": "latao",
        "cinta": None,
        "acento": (1.0, 0.78, 0.25),
        "brilho": 7.0,
        "estrela": True,
    },
    "suprimentos": {
        "nome": "SUPRIMENTOS",
        "corpo": "pintada",
        "cor": (0.16, 0.18, 0.08),
        "estencil": (0.95, 0.92, 0.82),
        "canto": "aco",
        "cinta": (0.95, 0.65, 0.05),
        "acento": (1.0, 0.5, 0.12),
        "brilho": 6.0,
        "estrela": False,
    },
    "especiais": {
        "nome": "ESPECIAIS",
        "corpo": "metal",
        "cor": (0.02, 0.025, 0.03),
        "estencil": (0.25, 0.95, 1.0),
        "canto": "aco",
        "cinta": None,
        "acento": (0.15, 0.85, 1.0),
        "brilho": 8.0,
        "estrela": False,
    },
    "elite": {
        "nome": "ELITE",
        "corpo": "metal",
        "cor": (0.015, 0.015, 0.018),
        "estencil": (1.0, 0.78, 0.28),
        "canto": "latao",
        "cinta": (0.85, 0.62, 0.18),
        "acento": (1.0, 0.72, 0.18),
        "brilho": 11.0,
        "estrela": True,
    },
    "historica": {
        "nome": "COLEÇÃO",
        "corpo": "laca",
        "cor": (0.38, 0.03, 0.025),
        "estencil": (1.0, 0.8, 0.35),
        "canto": "latao",
        "cinta": None,
        "acento": (1.0, 0.32, 0.2),
        "brilho": 8.0,
        "estrela": True,
    },
}

# medidas da caixa (m)
CX, CY, CZ = 1.0, 0.62, 0.50  # corpo
TZ = 0.09  # altura da tampa
FRESTA = 0.022  # fresta entre o corpo e a tampa (a luz sai por ela)


def log(*a):
    print("[VT65]", *a, flush=True)


# ------------------------------------------------------------------ materiais
def lin(c):
    """As cores de superfície da tabela estão em sRGB (como se escolhe uma cor); o Blender quer
    linear. A luz (acento) já está em linear."""
    return tuple(x**2.2 for x in c)


def desgaste(m, forca=0.06, escala=38.0):
    """Relevo fino de uso (ruído no Bump) e a rugosidade variando um pouco: tira o ar de
    plástico."""
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    ruido = nt.nodes.new("ShaderNodeTexNoise")
    ruido.inputs["Scale"].default_value = escala
    ruido.inputs["Detail"].default_value = 8.0
    nt.links.new(coord.outputs["Object"], ruido.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = forca
    nt.links.new(ruido.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    rug = b.inputs["Roughness"].default_value
    faixa = nt.nodes.new("ShaderNodeMapRange")
    faixa.inputs["To Min"].default_value = max(0.05, rug - 0.12)
    faixa.inputs["To Max"].default_value = min(1.0, rug + 0.12)
    nt.links.new(ruido.outputs["Fac"], faixa.inputs["Value"])
    nt.links.new(faixa.outputs["Result"], b.inputs["Roughness"])


def mat_principled(nome, cor, metal=0.0, rug=0.5, clear=0.0, gasto=True):
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*lin(cor), 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rug
    if clear > 0:
        for k in ("Coat Weight", "Clearcoat"):
            if k in b.inputs:
                b.inputs[k].default_value = clear
                break
    if gasto:
        desgaste(m)
    return m


def mat_madeira(nome, cor, pintada=False):
    """Madeira procedural: veios (Wave) e manchas (Noise) entre dois tons da cor; a pintada tem os
    veios bem fracos (a tinta cobre) e um desgaste claro nas manchas."""
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    onda = nt.nodes.new("ShaderNodeTexWave")
    onda.inputs["Scale"].default_value = 3.0
    onda.inputs["Distortion"].default_value = 7.0
    onda.inputs["Detail"].default_value = 3.0
    ruido = nt.nodes.new("ShaderNodeTexNoise")
    ruido.inputs["Scale"].default_value = 9.0
    nt.links.new(coord.outputs["Object"], onda.inputs["Vector"])
    nt.links.new(coord.outputs["Object"], ruido.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMath")
    mix.operation = "MULTIPLY_ADD"
    mix.inputs[1].default_value = 0.6
    nt.links.new(onda.outputs["Fac"], mix.inputs[0])
    nt.links.new(ruido.outputs["Fac"], mix.inputs[2])
    rampa = nt.nodes.new("ShaderNodeValToRGB")
    escuro = lin(tuple(c * (0.8 if pintada else 0.62) for c in cor))
    claro = lin(tuple(min(1.0, c * (1.1 if pintada else 1.25)) for c in cor))
    rampa.color_ramp.elements[0].color = (*escuro, 1.0)
    rampa.color_ramp.elements[1].color = (*claro, 1.0)
    nt.links.new(mix.outputs[0], rampa.inputs["Fac"])
    nt.links.new(rampa.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.55 if pintada else 0.62
    return m


def mat_emissao(nome, cor, forca):
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (*cor, 1.0)
    e.inputs["Strength"].default_value = forca
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    return m


def mat_halo(nome, cor, forca):
    """Halo atrás da caixa: emissão com o alfa caindo do centro para a borda (gradiente
    esférico)."""
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    mapa = nt.nodes.new("ShaderNodeMapping")
    mapa.inputs["Scale"].default_value = (1.0, 1.0, 1.0)
    nt.links.new(coord.outputs["Object"], mapa.inputs["Vector"])
    nt.links.new(mapa.outputs["Vector"], grad.inputs["Vector"])
    curva = nt.nodes.new("ShaderNodeMath")
    curva.operation = "POWER"
    curva.inputs[1].default_value = 2.2
    nt.links.new(grad.outputs["Fac"], curva.inputs[0])
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (*cor, 1.0)
    e.inputs["Strength"].default_value = forca
    t = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(curva.outputs[0], mix.inputs["Fac"])
    nt.links.new(t.outputs[0], mix.inputs[1])
    nt.links.new(e.outputs[0], mix.inputs[2])
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], o.inputs["Surface"])
    return m


# ------------------------------------------------------------------ peças
def bloco(nome, dim, centro, mat, chanfro=0.006):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centro)
    o = bpy.context.active_object
    o.name = nome
    o.scale = (dim[0], dim[1], dim[2])
    bpy.ops.object.transform_apply(scale=True)
    if chanfro > 0:
        b = o.modifiers.new("Chanfro", "BEVEL")
        b.width = chanfro
        b.segments = 3
        b.limit_method = "ANGLE"
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def texto(corpo, mat, centro, altura, rot, espessura=0.002):
    fonte = FONTE if FONTE.exists() else FONTE_RESERVA
    cur = bpy.data.curves.new("Estencil", "FONT")
    cur.body = corpo
    cur.font = bpy.data.fonts.load(str(fonte), check_existing=True)
    cur.align_x = "CENTER"
    cur.align_y = "CENTER"
    cur.size = altura
    cur.extrude = espessura
    o = bpy.data.objects.new("Estencil", cur)
    bpy.context.scene.collection.objects.link(o)
    o.location = centro
    o.rotation_euler = rot
    o.data.materials.append(mat)
    return o


def estrela(nome, raio, centro, rot, mat, pontas=5, espessura=0.004):
    import bmesh

    me = bpy.data.meshes.new(nome)
    bm = bmesh.new()
    vs = []
    for i in range(pontas * 2):
        r = raio if i % 2 == 0 else raio * 0.42
        a = math.pi / 2 + i * math.pi / pontas
        vs.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += espessura
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = centro
    o.rotation_euler = rot
    o.data.materials.append(mat)
    return o


def alca(lado, mat):
    """Alça lateral de metal: meio anel no meio do lado (x = ±)."""
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.07, minor_radius=0.011, location=(lado * (CX / 2 + 0.012), 0.0, CZ * 0.62)
    )
    o = bpy.context.active_object
    o.name = "Alca"
    o.rotation_euler = (0.0, math.radians(90), 0.0)
    o.scale = (1.0, 1.0, 0.55)
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def montar(spec) -> list:
    objs = []
    corpo_tipo = spec["corpo"]
    if corpo_tipo in ("madeira", "pintada"):
        m_corpo = mat_madeira("Corpo", spec["cor"], pintada=corpo_tipo == "pintada")
    elif corpo_tipo == "laca":
        m_corpo = mat_principled("Corpo", spec["cor"], rug=0.18, clear=1.0)
    else:
        m_corpo = mat_principled("Corpo", spec["cor"], metal=0.75, rug=0.32)
    m_canto = (
        mat_principled("Latao", (0.93, 0.76, 0.42), metal=1.0, rug=0.24)
        if spec["canto"] == "latao"
        else mat_principled("Aco", (0.66, 0.67, 0.66), metal=1.0, rug=0.36)
    )
    m_est = mat_principled("Tinta", spec["estencil"], rug=0.55)
    m_luz = mat_emissao("Fresta", spec["acento"], spec["brilho"] * 1.2)
    # corpo e tampa (a fresta entre eles brilha)
    objs.append(bloco("Corpo", (CX, CY, CZ), (0, 0, CZ / 2), m_corpo, 0.01))
    objs.append(bloco("Luz", (CX - 0.03, CY - 0.03, FRESTA), (0, 0, CZ + FRESTA / 2), m_luz, 0.0))
    objs.append(
        bloco("Tampa", (CX + 0.02, CY + 0.02, TZ), (0, 0, CZ + FRESTA + TZ / 2), m_corpo, 0.012)
    )
    if corpo_tipo in ("madeira", "pintada"):
        # ripas horizontais na frente e atrás e montantes nas quinas (o caixote clássico)
        for y in (-1, 1):
            for z in (0.12, 0.38):
                objs.append(
                    bloco(
                        "Ripa",
                        (CX - 0.16, 0.022, 0.07),
                        (0, y * (CY / 2 + 0.011), z),
                        m_corpo,
                        0.004,
                    )
                )
        for x in (-1, 1):
            for y in (-1, 1):
                objs.append(
                    bloco(
                        "Montante",
                        (0.07, 0.07, CZ),
                        (x * (CX / 2 - 0.02), y * (CY / 2 - 0.02), CZ / 2),
                        m_corpo,
                        0.005,
                    )
                )
    else:
        # nervuras de chapa (metal e laca): dois frisos em volta
        for z in (0.1, 0.4):
            objs.append(
                bloco(
                    "Friso",
                    (CX + 0.012, CY + 0.012, 0.025),
                    (0, 0, z),
                    m_canto if corpo_tipo == "laca" else m_corpo,
                    0.004,
                )
            )
    # cantoneiras nas 8 quinas
    for x in (-1, 1):
        for y in (-1, 1):
            for z, h in ((0.05, 0.1), (CZ + FRESTA + TZ - 0.05, 0.1)):
                objs.append(
                    bloco(
                        "Canto",
                        (0.09, 0.09, h),
                        (x * (CX / 2 + 0.002), y * (CY / 2 + 0.002), z),
                        m_canto,
                        0.006,
                    )
                )
    # alças
    objs.append(alca(1, m_canto))
    objs.append(alca(-1, m_canto))
    # cintas (passam pela frente, por cima e por trás)
    if spec["cinta"]:
        m_cinta = mat_principled("Cinta", spec["cinta"], rug=0.75)
        for x in (-0.405, 0.405):  # perto das quinas: o nome fica livre no meio
            objs.append(
                bloco(
                    "CintaF",
                    (0.07, 0.006, CZ + TZ + FRESTA),
                    (x, -(CY / 2 + 0.026), (CZ + TZ + FRESTA) / 2),
                    m_cinta,
                    0.0,
                )
            )
            objs.append(
                bloco(
                    "CintaT",
                    (0.07, CY + 0.06, 0.006),
                    (x, 0, CZ + FRESTA + TZ + 0.003),
                    m_cinta,
                    0.0,
                )
            )
            objs.append(
                bloco(
                    "CintaA",
                    (0.07, 0.006, CZ + TZ + FRESTA),
                    (x, CY / 2 + 0.026, (CZ + TZ + FRESTA) / 2),
                    m_cinta,
                    0.0,
                )
            )
    # o nome na frente (a frente é -Y) e a estrela no lado esquerdo (o que a câmera vê)
    frente_y = -(CY / 2 + (0.024 if corpo_tipo in ("madeira", "pintada") else 0.002)) - 0.001
    tam = 0.13 if len(spec["nome"]) <= 9 else 0.105
    if spec["cinta"]:
        tam *= 0.86 if len(spec["nome"]) <= 9 else 0.8
    objs.append(texto(spec["nome"], m_est, (0, frente_y, 0.25), tam, (math.radians(90), 0, 0)))
    if spec["estrela"]:
        objs.append(
            estrela(
                "Estrela",
                0.1,
                (-(CX / 2 + 0.003), 0, 0.27),
                (math.radians(90), 0, math.radians(-90)),
                m_est,
            )
        )
    return objs


def halo(spec, centro: Vector, raio: float):
    """Disco de luz atrás da caixa, voltado para a câmera, na cor da raridade."""
    cam = bpy.context.scene.camera
    d = (cam.location - centro).normalized()
    bpy.ops.mesh.primitive_plane_add(
        size=2.0, location=centro - d * raio * 1.6 + Vector((0, 0, 0.15 * raio))
    )
    o = bpy.context.active_object
    o.name = "Halo"
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    # o gradiente esférico vai de 1 no meio a 0 a 1 m: a escala põe a borda do halo a 1,9 raio
    o.scale = (raio * 1.9, raio * 1.9, 1.0)
    o.data.materials.append(mat_halo("Halo", spec["acento"], 0.35 + spec["brilho"] * 0.09))
    o.visible_shadow = False
    return o


def mat_feixe(nome, cor, forca):
    """Cartão de luz (D-213): emissão com o alfa caindo para cima e para os lados (coordenadas
    geradas do plano), o truque de efeito para o facho que sai da caixa aberta."""
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])

    def op(tipo, a, b=None):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = tipo
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                nt.links.new(v, n.inputs[i])
        return n.outputs[0]

    # vertical: 1 embaixo, 0 em cima, caindo depressa; lateral: sino em u
    v = op("POWER", op("SUBTRACT", 1.0, sep.outputs["Y"]), 1.5)
    u = op("SUBTRACT", op("MULTIPLY", sep.outputs["X"], 2.0), 1.0)
    sino = op("POWER", op("SUBTRACT", 1.0, op("MULTIPLY", u, u)), 2.0)
    fac = op("MULTIPLY", v, sino)
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (*cor, 1.0)
    e.inputs["Strength"].default_value = forca
    t = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(fac, mix.inputs["Fac"])
    nt.links.new(t.outputs[0], mix.inputs[1])
    nt.links.new(e.outputs[0], mix.inputs[2])
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], o.inputs["Surface"])
    return m


def da_tampa(o) -> bool:
    n = o.name
    if n.startswith("Tampa") or n.startswith("CintaT"):
        return True
    return n.startswith("Canto") and meio_z(o) > CZ


def meio_z(o) -> float:
    """Altura do meio da peça no mundo (o `bloco` aplica a posição na malha: a origem fica em 0)."""
    zs = [(o.matrix_world @ Vector(c)).z for c in o.bound_box]
    return (min(zs) + max(zs)) / 2


def abrir(spec, objs, camada: str, centro: Vector, raio: float):
    """D-213: a caixa aberta em duas camadas com o mesmo enquadramento da fechada: "corpo" (oco,
    sem a tampa, com a luz lá dentro e o facho saindo) e "tampa" (só ela, iluminada por baixo). A
    tela da abertura põe uma sobre a outra e faz a tampa voar."""
    corpo = next(o for o in objs if o.name == "Corpo")
    m_corpo = corpo.data.materials[0]
    for o in objs:
        tampa = da_tampa(o)
        if o.name.startswith("Luz"):
            o.hide_render = True
        elif camada == "corpo":
            o.hide_render = tampa
            if o.name.startswith("CintaF") or o.name.startswith("CintaA"):
                # a cinta vai de 0 à tampa; encolhe em volta do chão (origem em 0) até a borda
                o.scale.z = CZ / (CZ + TZ + FRESTA)
        else:
            o.hide_render = not tampa
    a = spec["acento"]
    # o miolo brilhante (bem mais fraco que a força cheia: no Standard a cor estoura para o branco)
    m_dentro = mat_emissao("Dentro", a, min(3.0, 1.0 + spec["brilho"] * 0.25))
    if camada == "tampa":
        dentro = bloco("Dentro", (CX - 0.07, CY - 0.07, 0.004), (0, 0, CZ - 0.02), m_dentro, 0.0)
        dentro.visible_camera = False  # só ilumina a tampa por baixo
        return
    # corpo oco: o bloco cheio sai e entram o fundo e as quatro paredes
    corpo.hide_render = True
    e = 0.035
    bloco("Fundo", (CX, CY, e), (0, 0, e / 2), m_corpo, 0.004)
    for y in (-1, 1):
        bloco("Parede", (CX, e, CZ), (0, y * (CY / 2 - e / 2), CZ / 2), m_corpo, 0.006)
    for x in (-1, 1):
        bloco("Parede", (e, CY - 2 * e, CZ), (x * (CX / 2 - e / 2), 0, CZ / 2), m_corpo, 0.006)
    bloco("Dentro", (CX - 2 * e, CY - 2 * e, 0.004), (0, 0, CZ * 0.42), m_dentro, 0.0)
    # luz de dentro: pinta as paredes de dentro na cor da raridade
    lz = bpy.data.lights.new("DeDentro", "POINT")
    lz.energy = 25.0 + spec["brilho"] * 6.0
    lz.color = a
    lz.shadow_soft_size = 0.12
    lo = bpy.data.objects.new("DeDentro", lz)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = (0, 0, CZ * 0.6)
    # o facho: três cartões de luz de pé, de frente para a câmera (um largo e dois finos tortos)
    cam = bpy.context.scene.camera
    d = (cam.location - centro).normalized()
    d.z = 0.0
    d.normalize()
    giro_z = math.atan2(d.y, d.x) + math.radians(90)  # o giro em X põe a normal em -Y
    forca = 1.6 + spec["brilho"] * 0.3
    for nome, larg, alt, tombo, f in (
        ("Feixe", CX * 1.0, 1.15, 0.0, forca),
        ("Raio", CX * 0.32, 1.3, 9.0, forca * 1.3),
        ("Raio", CX * 0.26, 1.2, -11.0, forca * 1.3),
    ):
        bpy.ops.mesh.primitive_plane_add(size=1.0)
        p = bpy.context.active_object
        p.name = nome
        p.scale = (larg, alt, 1.0)
        # a base no miolo; o tombo inclina o cartão no próprio plano (o raio abre em leque)
        t = math.radians(tombo)
        p.rotation_euler = (math.radians(90), t, giro_z)
        base = Vector((0, 0, CZ * 0.45))
        sobe = Vector((math.sin(t) * alt / 2, 0, math.cos(t) * alt / 2))  # Ry(t) de (0, 0, 1)
        sobe.rotate(Euler((0, 0, giro_z)))
        p.location = base + sobe
        p.data.materials.append(mat_feixe(nome, a, f))
        p.visible_shadow = False


def topo_suave(caminho: Path, margem: float = 0.16):
    """D-213: o facho da caixa aberta passa do alto do quadro; no jogo, a borda reta aparecia. O
    alfa cai a zero na faixa de cima (`margem` da altura), com a curva suave."""
    import numpy as np

    im = bpy.data.images.load(str(caminho))
    w, h = im.size
    px = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    # as linhas do Blender vão de baixo para cima: a última é o topo da imagem
    d = np.clip((h - 0.5 - np.arange(h)) / (h * margem), 0, 1)
    px[..., 3] *= (d * d * (3 - 2 * d))[:, None]
    im.pixels.foreach_set(px.ravel())
    im.filepath_raw = str(caminho)
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def render(chave: str, amostras: int, teste: bool, camada: str | None = None):
    spec = CAIXAS[chave]
    C.cena_vazia()
    cena = bpy.context.scene
    lado = 256 if teste else 768
    L.configurar(cena, lado, lado, amostras)
    # cores saturadas (o AgX do loja.py lava a luz da raridade para o branco e desbota a madeira)
    cena.view_settings.view_transform = "Standard"
    try:
        cena.view_settings.look = "None"
    except TypeError:
        pass
    cena.view_settings.exposure = -0.6
    objs = montar(spec)
    cam, centro, raio = L.camera_para(
        objs, lado, lado, direcao=(-0.62, -1.0, 0.55), lente=55.0, folga=1.18
    )
    L.estudio(centro, raio)
    # contraluz na cor da caixa (o brilho de cima da tampa) e o halo atrás
    r = raio
    L.luz_area(
        "Raridade",
        centro + Vector((0.4 * r, 2.4 * r, 2.6 * r)),
        centro,
        300 * r * r,
        spec["acento"],
        1.4 * r,
    )
    if camada != "tampa":
        halo(spec, centro, raio)
    if camada:
        abrir(spec, objs, camada, centro, raio)
    SAIDA.mkdir(parents=True, exist_ok=True)
    nome = ("teste_" if teste else "") + chave + (f"_{camada}" if camada else "") + ".png"
    cena.render.filepath = str(SAIDA / nome)
    bpy.ops.render.render(write_still=True)
    if camada == "corpo":
        topo_suave(SAIDA / nome)
    log("ok", nome)


def principal():
    args = C.argumentos()
    if not args:
        raise SystemExit("uso: caixas_loja.py -- <id> | todas [--amostras N] [--teste]")
    amostras = 64
    if "--amostras" in args:
        amostras = int(args[args.index("--amostras") + 1])
    teste = "--teste" in args
    chaves = list(CAIXAS) if args[0] == "todas" else [args[0]]
    # --aberta: só as duas camadas da caixa aberta (D-213); sem ela, só a fechada
    camadas = ["corpo", "tampa"] if "--aberta" in args else [None]
    if "--so-topo" in args:  # só o degradê do alto nos corpos já renderizados (sem render)
        for k in chaves:
            topo_suave(SAIDA / f"{k}_corpo.png")
            log("topo", k)
        return
    for k in chaves:
        for camada in camadas:
            render(k, amostras, teste, camada)


if __name__ == "__main__":
    principal()
