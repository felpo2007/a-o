"""Imagens de catálogo da tela de classe e equipamento, em Cycles (dono: "genérico, sem imagens,
coloque imagens no equipamento"; "quero o mesmo nível de esforço" das caixas).

Quatro grupos:
- `armas`: perfil lateral idêntico (boca para a direita, lado direito da arma para a câmera),
  câmera ortográfica, estúdio com contraluz e sombra suave. `assets/ui/armas/<id>.png`, 768 x 384,
  RGBA. Os modelos são os do jogo; a M20 dos EUA não tem arte no jogo e é modelada aqui.
- `equip`: três quartos, mesma luz. Granadas e pás vêm dos GLB do jogo (peças altas, se houver); o
  resto é modelado aqui. `assets/ui/equip/<id>.png`, 512 x 512, RGBA.
- `classes`: insígnias no acabamento de `emblemas.py` (usa as funções dele, sem alterar o arquivo).
  `assets/ui/classes/<id>.png`, 512 x 512, RGBA.
- `times`: natureza-morta sem pessoas, luz quente de fim de tarde, lado esquerdo escuro para o
  texto do cartão. `assets/ui/times/<us|vc>.png`, 1280 x 720, RGB.
- `premios`: 10 objetos do passe e das ordens do dia, sem nenhum texto, mesma luz.
  `assets/ui/premios/<id>.png`, 512 x 512, RGBA.

Uso (sempre na CPU: a GPU de 2 GB é do Studio):
    $env:VT65_CPU = "1"; $env:VT65_THREADS = "3"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/armas_catalogo.py -- armas|equip|classes|times|premios|todas [ids...] `
        [--teste] [--amostras N] [--saida PASTA]

Com `--teste` sai em metade do tamanho, com poucas amostras, numa pasta temporária (ou `--saida`).
"""

from __future__ import annotations

import math
import random
import re
import sys
import tempfile
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import caixas_loja as K  # noqa: E402
import comum as C  # noqa: E402
import emblemas as E  # noqa: E402
import loja as L  # noqa: E402

RAIZ = C.RAIZ
FG = RAIZ / "assets" / "forgegui" / "models"
BL = RAIZ / "assets" / "blender"
FC = RAIZ / "assets" / "facas"
UI = RAIZ / "assets" / "ui"
BANDEIRAS = RAIZ / "assets" / "bandeiras"
CARTA = RAIZ / "assets" / "carta" / "atlas_2048.png"
WEAPON_ART = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "WeaponArt.luau"

ARMAS = {
    "m14": FG / "m14_studs_parker.glb",
    "m16": BL / "arma_m16" / "arma_m16.glb",
    "m60": BL / "arma_m60" / "arma_m60.glb",
    "m1911": FG / "m1911_studs_parker.glb",
    "m79": FG / "m79_studs_parker.glb",
    "type56": FG / "type56_studs_parker.glb",
    "sks": BL / "arma_sks" / "arma_sks.glb",
    "rpd": FG / "rpd_studs_parker.glb",
    "type54": FG / "type54_studs_parker.glb",
    "rpg2": FG / "rpg2_studs_parker.glb",
    "m70": BL / "arma_m70_unertl" / "arma_m70_unertl.glb",
    "mosin": BL / "arma_mosin_pu" / "arma_mosin_pu.glb",
    "win12": BL / "arma_win12" / "arma_win12.glb",
    "kabar": FC / "kabar.glb",
    "m6": FC / "m6.glb",
    "dao": FC / "dao.glb",
    "m20": None,  # sem GLB no jogo: `modelo_m20`
}
# as facas não estão no WeaponArt: sentido da ponta no Y do Blender (conferido na imagem)
FACAS = {"kabar": "+Y", "m6": "+Y", "dao": "+Y"}
# a boca no Blender, a partir do `forward` da MeshPart (o Roblox gira o GLB 180° em Y)
DIRECAO = {"+Z": "+Y", "-Z": "-Y", "+X": "-X", "-X": "+X"}
GIRO = {"+X": 0.0, "-X": 180.0, "+Y": -90.0, "-Y": 90.0}


def log(*a):
    print("[VT65]", *a, flush=True)


# ------------------------------------------------------------------ importação
def importar(caminho: Path, nos=None) -> bpy.types.Object:
    """GLB do jogo em metros, um objeto só, sem colisão; com `nos`, só os nós com esses nomes."""
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(caminho))
    novos = [o for o in bpy.data.objects if o not in antes]
    malhas = [o for o in novos if o.type == "MESH" and not o.name.startswith(("Colisao", "Zona_"))]
    if nos:
        malhas = [o for o in malhas if o.name.split(".")[0] in nos]
    if not malhas:
        raise RuntimeError(f"{caminho}: sem malha")
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
    obj.data.transform(Matrix.Scale(C.M_POR_STUD, 4))
    obj.name = caminho.stem
    return obj


def frente_das_armas() -> dict:
    """`forward` e `yaw` de cada arma, lidos do Shared/WeaponArt."""
    txt = WEAPON_ART.read_text("utf-8")
    pad = re.compile(r'(\w+) = \{\s*forward = "([+-][XYZ])",\s*yaw = ([-\d.]+)')
    return {m.group(1): (m.group(2), float(m.group(3))) for m in pad.finditer(txt)}


def largura_y(obj) -> float:
    lo, hi = C.caixa(obj)
    return float(hi[1] - lo[1])


def arma_canonica(chave: str) -> bpy.types.Object:
    """A arma com a boca em +X, topo em +Z e o meio da caixa na origem."""
    nos = ("Faca",) if chave in FACAS else None
    obj = importar(ARMAS[chave], nos)
    if chave in FACAS:
        sentido, yaw = FACAS[chave], 0.0
    else:
        frente, yaw = frente_das_armas()[chave]
        sentido = DIRECAO[frente]
    obj.data.transform(Matrix.Rotation(math.radians(GIRO[sentido]), 4, "Z"))
    if abs(yaw) > 1e-4:
        # modelo gerado torto: fica o sinal que deixa a arma mais fina vista de cima
        obj.data.transform(Matrix.Rotation(yaw, 4, "Z"))
        fino = largura_y(obj)
        obj.data.transform(Matrix.Rotation(-2 * yaw, 4, "Z"))
        if fino < largura_y(obj):
            obj.data.transform(Matrix.Rotation(2 * yaw, 4, "Z"))
    lo, hi = C.caixa(obj)
    meio = (lo + hi) / 2
    obj.data.transform(Matrix.Translation(Vector((-meio[0], -meio[1], -meio[2]))))
    return obj


def peca_do_jogo(pasta: str) -> bpy.types.Object:
    """Modelo final do jogo, com a base no z = 0 (o `_pecas.glb` é só o bloco, sem textura)."""
    obj = importar(BL / pasta / f"{pasta}.glb")
    lo, hi = C.caixa(obj)
    meio = (lo + hi) / 2
    obj.data.transform(Matrix.Translation(Vector((-meio[0], -meio[1], -lo[2]))))
    return obj


# ------------------------------------------------------------------ materiais
def mat(nome, cor, metal=0.0, rug=0.5, clear=0.0, escala=320.0, forca=0.03):
    m = K.mat_principled(nome, cor, metal=metal, rug=rug, clear=clear, gasto=False)
    if forca > 0:
        K.desgaste(m, forca=forca, escala=escala)
    return m


def pintado(nome, cor, rug=0.52, escala=420.0, aco=(0.60, 0.60, 0.58), raio=0.0022):
    """Tinta sobre metal: as quinas gastas (nó Bevel, que não depende da malha) mostram o aço, com
    lascas finas e um pouco de variação de tom. Com pointiness, a malha esparsa virava
    camuflagem."""
    m = mat(nome, cor, rug=rug, forca=0.025, escala=escala)
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")

    def faixa(sock, a, c, d=0.0, e=1.0):
        f = nt.nodes.new("ShaderNodeMapRange")
        f.inputs["From Min"].default_value = a
        f.inputs["From Max"].default_value = c
        f.inputs["To Min"].default_value = d
        f.inputs["To Max"].default_value = e
        nt.links.new(sock, f.inputs["Value"])
        return f.outputs["Result"]

    def op(tipo, x, y):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = tipo
        n.use_clamp = True
        nt.links.new(x, n.inputs[0])
        nt.links.new(y, n.inputs[1])
        return n.outputs[0]

    geo = nt.nodes.new("ShaderNodeNewGeometry")
    chanfro = nt.nodes.new("ShaderNodeBevel")
    chanfro.samples = 4
    chanfro.inputs["Radius"].default_value = raio
    ponto = nt.nodes.new("ShaderNodeVectorMath")
    ponto.operation = "DOT_PRODUCT"
    nt.links.new(geo.outputs["Normal"], ponto.inputs[0])
    nt.links.new(chanfro.outputs["Normal"], ponto.inputs[1])
    quina = faixa(ponto.outputs["Value"], 0.985, 0.88)
    coord = nt.nodes.new("ShaderNodeTexCoord")

    def ruido(k):
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = k
        n.inputs["Detail"].default_value = 9.0
        nt.links.new(coord.outputs["Object"], n.inputs["Vector"])
        return n.outputs["Fac"]

    gasto = op("MULTIPLY", quina, faixa(ruido(escala * 0.45), 0.38, 0.56))
    lascas = faixa(ruido(escala * 1.7), 0.73, 0.77)
    junta = op("MAXIMUM", gasto, lascas)
    rampa = nt.nodes.new("ShaderNodeValToRGB")
    rampa.color_ramp.elements[0].color = (*K.lin(cor), 1.0)
    rampa.color_ramp.elements[1].position = 0.6
    rampa.color_ramp.elements[1].color = (*K.lin(aco), 1.0)
    nt.links.new(junta, rampa.inputs["Fac"])
    tom = nt.nodes.new("ShaderNodeVectorMath")
    tom.operation = "SCALE"
    nt.links.new(rampa.outputs["Color"], tom.inputs[0])
    nt.links.new(faixa(ruido(escala * 0.035), 0.32, 0.68, 0.80, 1.10), tom.inputs["Scale"])
    nt.links.new(tom.outputs[0], b.inputs["Base Color"])
    nt.links.new(junta, b.inputs["Metallic"])
    return m


def mat_vidro(nome, cor=(0.10, 0.08, 0.22)):
    m = mat(nome, cor, rug=0.04, clear=1.0, forca=0.0)
    return m


def mat_tecido(nome, cor, rug=0.86, escala=900.0):
    """Trama de pano: duas ondas cruzadas no relevo."""
    m = mat(nome, cor, rug=rug, forca=0.0)
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    a1 = nt.nodes.new("ShaderNodeTexWave")
    a1.bands_direction = "X"
    a1.inputs["Scale"].default_value = escala
    a2 = nt.nodes.new("ShaderNodeTexWave")
    a2.bands_direction = "Y"
    a2.inputs["Scale"].default_value = escala
    nt.links.new(coord.outputs["Object"], a1.inputs["Vector"])
    nt.links.new(coord.outputs["Object"], a2.inputs["Vector"])
    soma = nt.nodes.new("ShaderNodeMath")
    nt.links.new(a1.outputs["Fac"], soma.inputs[0])
    nt.links.new(a2.outputs["Fac"], soma.inputs[1])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.22
    bump.inputs["Distance"].default_value = 0.0006
    nt.links.new(soma.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_tabua(nome, cor, escala=1.0):
    """Madeira de tábua: veio correndo em X, com variação por tábua (Object Info)."""
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    info = nt.nodes.new("ShaderNodeObjectInfo")
    soma = nt.nodes.new("ShaderNodeVectorMath")
    soma.operation = "ADD"
    escalar = nt.nodes.new("ShaderNodeVectorMath")
    escalar.operation = "SCALE"
    escalar.inputs["Scale"].default_value = 37.0
    nt.links.new(info.outputs["Random"], escalar.inputs[0])
    nt.links.new(coord.outputs["Object"], soma.inputs[0])
    nt.links.new(escalar.outputs[0], soma.inputs[1])
    mapa = nt.nodes.new("ShaderNodeMapping")
    mapa.inputs["Scale"].default_value = (1.1 * escala, 26.0 * escala, 26.0 * escala)
    nt.links.new(soma.outputs[0], mapa.inputs["Vector"])
    onda = nt.nodes.new("ShaderNodeTexWave")
    onda.bands_direction = "Y"
    onda.inputs["Scale"].default_value = 1.6
    onda.inputs["Distortion"].default_value = 9.0
    onda.inputs["Detail"].default_value = 5.0
    onda.inputs["Detail Scale"].default_value = 1.4
    nt.links.new(mapa.outputs[0], onda.inputs["Vector"])
    ruido = nt.nodes.new("ShaderNodeTexNoise")
    ruido.inputs["Scale"].default_value = 2.2
    ruido.inputs["Detail"].default_value = 8.0
    nt.links.new(mapa.outputs[0], ruido.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMath")
    mix.operation = "MULTIPLY_ADD"
    mix.inputs[1].default_value = 0.55
    nt.links.new(onda.outputs["Fac"], mix.inputs[0])
    nt.links.new(ruido.outputs["Fac"], mix.inputs[2])
    rampa = nt.nodes.new("ShaderNodeValToRGB")
    rampa.color_ramp.elements[0].position = 0.28
    rampa.color_ramp.elements[0].color = (*K.lin(tuple(c * 0.42 for c in cor)), 1.0)
    rampa.color_ramp.elements[1].position = 0.86
    rampa.color_ramp.elements[1].color = (*K.lin(cor), 1.0)
    nt.links.new(mix.outputs[0], rampa.inputs["Fac"])
    nt.links.new(rampa.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.62
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.002
    nt.links.new(mix.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_imagem(nome, caminho: Path, rug=0.85, ganho=1.0):
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    no = nt.nodes.new("ShaderNodeTexImage")
    no.image = bpy.data.images.load(str(caminho), check_existing=True)
    no.extension = "EXTEND"
    saida = no.outputs["Color"]
    if ganho != 1.0:
        escala = nt.nodes.new("ShaderNodeVectorMath")
        escala.operation = "SCALE"
        escala.inputs["Scale"].default_value = ganho
        nt.links.new(saida, escala.inputs[0])
        saida = escala.outputs[0]
    nt.links.new(saida, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rug
    return m


# ------------------------------------------------------------------ geometria
def ligar(nome, me, material=None, pos=(0, 0, 0), rot=(0, 0, 0), escala=1.0):
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(pos)
    o.rotation_mode = "XYZ"
    o.rotation_euler = [math.radians(a) for a in rot]
    o.scale = (escala, escala, escala)
    if material is not None and not me.materials:
        me.materials.append(material)
    return o


def malha_torno(nome, perfil, n=64, deforma=None, angulo=34.0):
    """Sólido de revolução em Z a partir de (raio, z). `deforma(x, y, z)` mexe em cada vértice."""
    m = len(perfil)
    vs, fs = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        for r, z in perfil:
            p = (r * math.cos(a), r * math.sin(a), z)
            vs.append(deforma(*p) if deforma else p)
    for i in range(n):
        j = (i + 1) % n
        for k in range(m - 1):
            fs.append((i * m + k, j * m + k, j * m + k + 1, i * m + k + 1))
    me = bpy.data.meshes.new(nome)
    me.from_pydata(vs, [], fs)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-7)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-8)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(angulo))
    return me


def torno(nome, perfil, material, pos=(0, 0, 0), rot=(0, 0, 0), n=64, deforma=None, angulo=34.0):
    return ligar(nome, malha_torno(nome, perfil, n, deforma, angulo), material, pos, rot)


def malha_toro(nome, R, r, n=40, m=12):
    bm = bmesh.new()
    vs = []
    for i in range(n):
        a = 2 * math.pi * i / n
        for j in range(m):
            b = 2 * math.pi * j / m
            q = R + r * math.cos(b)
            vs.append(bm.verts.new((q * math.cos(a), q * math.sin(a), r * math.sin(b))))
    for i in range(n):
        for j in range(m):
            ii, jj = (i + 1) % n, (j + 1) % m
            bm.faces.new((vs[i * m + j], vs[ii * m + j], vs[ii * m + jj], vs[i * m + jj]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    return me


def toro(nome, R, r, material, pos=(0, 0, 0), rot=(0, 0, 0)):
    return ligar(nome, malha_toro(nome, R, r), material, pos, rot)


def chanfrar(o, largura, segmentos=3, angulo=40.0):
    if largura <= 0:
        return o
    b = o.modifiers.new("Chanfro", "BEVEL")
    b.width = largura
    b.segments = segmentos
    b.limit_method = "ANGLE"
    b.angle_limit = math.radians(angulo)
    b.harden_normals = True
    o.data.shade_smooth()
    return o


def bloco(nome, dim, centro, material, chanfro=0.002, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(dim), verts=bm.verts)
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    return chanfrar(ligar(nome, me, material, centro, rot), chanfro)


def prisma(nome, pts, h, material, pos=(0, 0, 0), rot=(0, 0, 0), chanfro=0.001):
    """Contorno 2D (XY) extrudado de z = 0 a z = h, com chanfro."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0.0)) for x, y in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]:
        v.co.z += h
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    return chanfrar(ligar(nome, me, material, pos, rot), chanfro)


def tubo(nome, pontos, raio, material, ordem=3, fechado=False, resolucao=6):
    """Tubo por uma linha 3D suave (NURBS): alças, fios, tiras."""
    cu = bpy.data.curves.new(nome, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = raio
    cu.bevel_resolution = 3
    cu.resolution_u = resolucao
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pontos) - 1)
    for i, p in enumerate(pontos):
        sp.points[i].co = (p[0], p[1], p[2], 1.0)
    sp.order_u = min(ordem + 1, len(pontos))
    sp.use_endpoint_u = not fechado
    sp.use_cyclic_u = fechado
    cu.materials.append(material)
    o = bpy.data.objects.new(nome, cu)
    bpy.context.scene.collection.objects.link(o)
    return o


def grupo(objs, pos=(0, 0, 0), rot=(0, 0, 0)):
    p = bpy.data.objects.new("Grupo", None)
    bpy.context.scene.collection.objects.link(p)
    p.location = Vector(pos)
    p.rotation_mode = "XYZ"
    p.rotation_euler = [math.radians(a) for a in rot]
    for o in objs:
        # peça de um subgrupo: quem entra é a raiz dele, para ele não perder a própria posição
        raiz = o
        while raiz.parent is not None:
            raiz = raiz.parent
        if raiz is not p:
            raiz.parent = p
    return list(objs)


def estencil(corpo, material, pos, altura, rot=(90, 0, 0)):
    return K.texto(
        corpo, material, Vector(pos), altura, tuple(math.radians(a) for a in rot), 0.00012
    )


def estencil_cil(corpo, material, raio, z, altura, angulo=0.0, pos=(0, 0, 0)):
    """Estêncil enrolado num cilindro de raio `raio` em volta de Z, centrado na direção -Y girada
    de `angulo` graus."""
    cur = K.texto(corpo, material, Vector((0, 0, 0)), altura, (0, 0, 0), 0.0)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(cur)
    bpy.data.objects.remove(cur)
    a0 = math.radians(angulo)
    for v in me.vertices:
        t = v.co.x / raio + a0
        v.co = Vector((raio * math.sin(t), -raio * math.cos(t), v.co.y + z))
    me.materials.clear()
    me.materials.append(material)
    return ligar("Estencil", me, None, pos)


# ------------------------------------------------------------------ luz e câmera do catálogo
def mundo_estudio(cena, baixo=0.03, alto=0.40):
    """Céu de estúdio escuro embaixo e claro em cima: dá o que refletir no metal."""
    w = bpy.data.worlds.new("Estudio")
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes.get("Background")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    faixa = nt.nodes.new("ShaderNodeMapRange")
    faixa.inputs["From Min"].default_value = -0.15
    faixa.inputs["From Max"].default_value = 0.9
    faixa.inputs["To Min"].default_value = baixo
    faixa.inputs["To Max"].default_value = alto
    nt.links.new(sep.outputs["Z"], faixa.inputs["Value"])
    nt.links.new(faixa.outputs["Result"], bg.inputs["Strength"])
    bg.inputs["Color"].default_value = (0.84, 0.85, 0.88, 1.0)
    cena.world = w


def faixa_luz(nome, pos, alvo, energia, cor, larg, alt):
    o = L.luz_area(nome, pos, alvo, energia, cor, larg)
    o.data.shape = "RECTANGLE"
    o.data.size = larg
    o.data.size_y = alt
    return o


def luzes_catalogo(centro: Vector, r: float):
    """Chave quente (alto à esquerda), enchimento frio, duas faixas de contraluz e uma de cima."""
    k = r * r
    v = Vector
    faixa_luz(
        "Chave",
        centro + v((-1.1 * r, -2.5 * r, 2.0 * r)),
        centro,
        150 * k,
        (1.0, 0.91, 0.78),
        3.0 * r,
        1.3 * r,
    )
    faixa_luz(
        "Enche",
        centro + v((2.4 * r, -2.2 * r, -0.2 * r)),
        centro,
        40 * k,
        (0.72, 0.82, 1.0),
        2.4 * r,
        2.0 * r,
    )
    # contraluz largo e fraco: forte e fino, ele desenhava um fio branco em volta da arma
    faixa_luz(
        "ContraA",
        centro + v((-0.8 * r, 2.2 * r, 1.7 * r)),
        centro,
        95 * k,
        (1.0, 0.84, 0.62),
        3.6 * r,
        1.0 * r,
    )
    faixa_luz(
        "ContraB",
        centro + v((1.2 * r, 2.0 * r, -1.1 * r)),
        centro,
        26 * k,
        (0.62, 0.76, 1.0),
        3.0 * r,
        0.9 * r,
    )
    faixa_luz(
        "Cima",
        centro + v((0.0, -0.3 * r, 2.8 * r)),
        centro,
        60 * k,
        (1.0, 0.97, 0.92),
        3.6 * r,
        0.8 * r,
    )
    # painel atrás da câmera: é o que a face lateral reflete (o aço preto ganha forma)
    faixa_luz(
        "Frente",
        centro + v((0.3 * r, -3.6 * r, 1.0 * r)),
        centro,
        36 * k,
        (1.0, 0.96, 0.90),
        4.6 * r,
        2.4 * r,
    )


def apanha_sombra(pos, normal, tamanho):
    bpy.ops.mesh.primitive_plane_add(size=tamanho, location=pos)
    o = bpy.context.active_object
    o.name = "Sombra"
    o.rotation_euler = Vector(normal).to_track_quat("Z", "Y").to_euler()
    o.is_shadow_catcher = True
    o.visible_shadow = False
    o.visible_glossy = False
    o.visible_diffuse = False
    return o


def camera_orto(centro, larg_m, alt_m, larg, alt):
    """Câmera de frente para +Y; a arma ocupa até 90% da largura ou 76% da altura."""
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = max(larg_m / 0.92, alt_m / 0.76 * larg / alt)
    cd.clip_end = 1000.0
    cam = bpy.data.objects.new("Cam", cd)
    cena = bpy.context.scene
    cena.collection.objects.link(cam)
    cena.camera = cam
    cam.location = (centro.x, centro.y - max(larg_m, 1.0) * 6, centro.z)
    cam.rotation_euler = (math.pi / 2, 0.0, 0.0)
    return cam


def acabar(cena):
    cena.cycles.max_bounces = 8
    cena.cycles.glossy_bounces = 5
    cena.cycles.transparent_max_bounces = 8
    cena.cycles.use_adaptive_sampling = True
    cena.cycles.adaptive_threshold = 0.02


# ------------------------------------------------------------------ 1. armas
# As armas feitas no Blender têm a textura lisa, feita para o jogo: no catálogo, a madeira ganha
# veio e o aço fica acetinado. A máscara de madeira sai da própria cor (matiz e saturação).
REALCE = {"m16", "m60", "m70", "mosin", "sks", "win12"}


def realcar(obj, metal=0.62):
    for slot in obj.material_slots:
        if slot.material is not None and slot.material.use_nodes:
            realcar_material(slot.material, metal)


def realcar_material(m, metal):
    nt = m.node_tree
    b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None or not b.inputs["Base Color"].is_linked:
        return
    cor = b.inputs["Base Color"].links[0].from_socket
    hsv = nt.nodes.new("ShaderNodeSeparateColor")
    hsv.mode = "HSV"
    nt.links.new(cor, hsv.inputs[0])

    def faixa(sock, a, b_, c=0.0, d=1.0):
        f = nt.nodes.new("ShaderNodeMapRange")
        f.interpolation_type = "SMOOTHSTEP"
        f.inputs["From Min"].default_value = a
        f.inputs["From Max"].default_value = b_
        f.inputs["To Min"].default_value = c
        f.inputs["To Max"].default_value = d
        nt.links.new(sock, f.inputs["Value"])
        return f.outputs["Result"]

    def op(tipo, x, y):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = tipo
        for i, v in enumerate((x, y)):
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                nt.links.new(v, n.inputs[i])
        return n.outputs[0]

    madeira = op(
        "MULTIPLY",
        faixa(hsv.outputs[1], 0.26, 0.42),
        op(
            "MULTIPLY",
            faixa(hsv.outputs[0], 0.015, 0.04),
            faixa(hsv.outputs[0], 0.11, 0.15, 1.0, 0.0),
        ),
    )
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapa = nt.nodes.new("ShaderNodeMapping")
    # período de ~9 mm (6 px no quadro final): mais fino que isso vira moiré
    mapa.inputs["Scale"].default_value = (1.6, 34.0, 34.0)
    nt.links.new(coord.outputs["Object"], mapa.inputs["Vector"])
    onda = nt.nodes.new("ShaderNodeTexWave")
    onda.bands_direction = "Z"
    onda.inputs["Scale"].default_value = 1.0
    onda.inputs["Distortion"].default_value = 7.0
    onda.inputs["Detail"].default_value = 5.0
    onda.inputs["Detail Scale"].default_value = 1.6
    nt.links.new(mapa.outputs[0], onda.inputs["Vector"])
    veio = faixa(onda.outputs["Fac"], 0.15, 0.85, 0.70, 1.16)
    # aço: o que não é madeira e é escuro e pouco saturado
    aco = op(
        "MULTIPLY",
        op("SUBTRACT", 1.0, madeira),
        faixa(hsv.outputs[1], 0.16, 0.34, 1.0, 0.0),
    )
    # o preto da textura clareia um pouco, senão a arma vira só silhueta
    ganho = op(
        "ADD",
        op("ADD", op("MULTIPLY", madeira, op("SUBTRACT", veio, 1.0)), 1.0),
        op("MULTIPLY", aco, 0.9),
    )
    mult = nt.nodes.new("ShaderNodeVectorMath")
    mult.operation = "SCALE"
    nt.links.new(cor, mult.inputs[0])
    nt.links.new(ganho, mult.inputs["Scale"])
    nt.links.new(mult.outputs[0], b.inputs["Base Color"])
    ent_m = b.inputs["Metallic"]
    antes_m = ent_m.links[0].from_socket if ent_m.is_linked else ent_m.default_value
    nt.links.new(op("MAXIMUM", antes_m, op("MULTIPLY", aco, metal)), ent_m)
    ent_r = b.inputs["Roughness"]
    antes_r = ent_r.links[0].from_socket if ent_r.is_linked else ent_r.default_value
    k = op("SUBTRACT", 1.0, op("ADD", op("MULTIPLY", aco, 0.36), op("MULTIPLY", madeira, 0.24)))
    nt.links.new(op("MULTIPLY", antes_r, k), ent_r)
    # micro-relevo: poro na madeira, lixa fina no aço
    ruido = nt.nodes.new("ShaderNodeTexNoise")
    ruido.inputs["Scale"].default_value = 1500.0
    ruido.inputs["Detail"].default_value = 6.0
    nt.links.new(coord.outputs["Object"], ruido.inputs["Vector"])
    altura = op(
        "ADD",
        op("MULTIPLY", madeira, onda.outputs["Fac"]),
        op("MULTIPLY", ruido.outputs["Fac"], 0.25),
    )
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.16
    bump.inputs["Distance"].default_value = 0.0012
    nt.links.new(altura, bump.inputs["Height"])
    ent_n = b.inputs["Normal"]
    if ent_n.is_linked:
        nt.links.new(ent_n.links[0].from_socket, bump.inputs["Normal"])
    nt.links.new(bump.outputs["Normal"], ent_n)


def apagar_bordas(caminho: Path, faixa=0.045, faixa_y=None):
    """A sombra some antes da borda: no cartão do jogo, ela não pode terminar num corte reto."""
    img = bpy.data.images.load(str(caminho), check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    mx = max(1, int(w * faixa))
    my = max(1, int(h * (faixa_y if faixa_y is not None else faixa * 2)))

    def rampa(n, m):
        a = np.minimum(np.arange(n), np.arange(n)[::-1]) / m
        a = np.clip(a, 0.0, 1.0)
        return a * a * (3 - 2 * a)

    px[..., 3] *= rampa(h, my)[:, None] * rampa(w, mx)[None, :]
    img.pixels.foreach_set(px.reshape(-1))
    img.filepath_raw = str(caminho)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def modelo_m20(p):
    """Bazuca M20 de 3,5 pol. (1,52 m; o jogo não tem arte dela): tubo de duas partes com o colar
    de união, punho e gatilho, coronha de ombro, mira, trava de contato e o fio do disparo. Boca
    em +X, topo em +Z, como as outras armas."""
    verde = pintado("TuboM20", (0.31, 0.34, 0.20), rug=0.44, escala=190, raio=0.004)
    escuro = pintado("FerragemM20", (0.20, 0.22, 0.14), rug=0.42, escala=420, raio=0.002)
    aco, preto = p["aco"], p["preto"]
    R, RI = 0.0465, 0.0445
    eixo = (0, 90, 0)  # o eixo do torno vira +X: a boca fica à direita
    objs = [
        torno(
            "TuboTras",
            [
                (RI, -0.762),
                (R + 0.0035, -0.762),
                (R + 0.0035, -0.745),
                (R, -0.738),
                (R, -0.012),
                (RI, -0.012),
            ],
            verde,
            rot=eixo,
            n=72,
        ),
        torno(
            "TuboFrente",
            [
                (RI, 0.012),
                (R, 0.012),
                (R, 0.738),
                (R + 0.0035, 0.746),
                (R + 0.0035, 0.762),
                (RI, 0.762),
            ],
            verde,
            rot=eixo,
            n=72,
        ),
        torno(
            "Colar",
            [
                (R, -0.046),
                (R + 0.0068, -0.042),
                (R + 0.0068, -0.017),
                (R + 0.0044, -0.013),
                (R + 0.0044, 0.013),
                (R + 0.0068, 0.017),
                (R + 0.0068, 0.042),
                (R, 0.046),
            ],
            escuro,
            rot=eixo,
            n=72,
        ),
    ]
    for x in (-0.60, -0.26, 0.30, 0.60):
        objs.append(
            torno(
                "Cinta",
                [(R, x - 0.009), (R + 0.0024, x - 0.007), (R + 0.0024, x + 0.007), (R, x + 0.009)],
                escuro,
                rot=eixo,
                n=72,
            )
        )
    # alavanca do colar, do lado que a câmera vê
    objs.append(bloco("Alavanca", (0.074, 0.008, 0.015), (0.0, -R - 0.010, 0.010), aco, 0.002))
    objs.append(bloco("Pega", (0.016, 0.012, 0.022), (0.036, -R - 0.012, 0.010), preto, 0.003))
    # caixa do disparo, punho e gatilho
    z0 = -R
    caixa_d = [
        (-0.165, z0 + 0.006),
        (0.030, z0 + 0.006),
        (0.030, z0 - 0.016),
        (0.006, z0 - 0.030),
        (-0.150, z0 - 0.030),
        (-0.165, z0 - 0.018),
    ]
    objs.append(prisma("CaixaDisparo", caixa_d, 0.040, escuro, (0, 0.020, 0), (90, 0, 0), 0.0028))
    punho = [
        (-0.128, z0 - 0.026),
        (-0.076, z0 - 0.026),
        (-0.088, z0 - 0.072),
        (-0.098, z0 - 0.128),
        (-0.112, z0 - 0.140),
        (-0.150, z0 - 0.136),
        (-0.156, z0 - 0.122),
        (-0.140, z0 - 0.070),
    ]
    objs.append(prisma("Punho", punho, 0.032, preto, (0, 0.016, 0), (90, 0, 0), 0.0042))
    for i in range(6):
        z = z0 - 0.050 - i * 0.014
        x = -0.102 - i * 0.0035
        objs.append(bloco("Estria", (0.050, 0.0012, 0.0028), (x, -0.0164, z), p["borr"], 0.0004))
    objs.append(toro("Guarda", 0.0235, 0.0028, aco, (-0.043, 0, z0 - 0.052), (90, 0, 0)))
    gatilho = [
        (-0.050, z0 - 0.030),
        (-0.040, z0 - 0.030),
        (-0.046, z0 - 0.052),
        (-0.056, z0 - 0.060),
        (-0.060, z0 - 0.056),
        (-0.052, z0 - 0.046),
    ]
    objs.append(prisma("Gatilho", gatilho, 0.006, aco, (0, 0.003, 0), (90, 0, 0), 0.0008))
    # coronha de ombro: armação de tubo e a chapa curva
    for y in (-0.014, 0.014):
        objs.append(
            tubo(
                "Armacao",
                [
                    (-0.205, y, z0 + 0.004),
                    (-0.262, y, z0 - 0.040),
                    (-0.340, y, z0 - 0.078),
                    (-0.430, y, z0 - 0.086),
                    (-0.500, y, z0 - 0.050),
                    (-0.535, y, z0 + 0.004),
                ],
                0.0066,
                escuro,
            )
        )
    for x, topo in ((-0.300, 0.058), (-0.455, 0.072)):
        objs.append(bloco("Trava", (0.010, 0.036, 0.008), (x, 0.0, z0 - topo), escuro, 0.002))
    chapa = [
        (-0.452, z0 - 0.078),
        (-0.350, z0 - 0.072),
        (-0.335, z0 - 0.090),
        (-0.372, z0 - 0.106),
        (-0.420, z0 - 0.112),
        (-0.468, z0 - 0.100),
    ]
    objs.append(prisma("Chapa", chapa, 0.052, escuro, (0, 0.026, 0), (90, 0, 0), 0.0045))
    almofada_o = [
        (-0.470, z0 - 0.098),
        (-0.420, z0 - 0.110),
        (-0.372, z0 - 0.104),
        (-0.368, z0 - 0.112),
        (-0.420, z0 - 0.120),
        (-0.476, z0 - 0.106),
    ]
    objs.append(prisma("Almofada", almofada_o, 0.056, p["borr"], (0, 0.028, 0), (90, 0, 0), 0.003))
    # mira: base, caixa do refletor, ocular e a massa lá na frente
    objs.append(bloco("BaseMira", (0.140, 0.034, 0.008), (-0.100, 0.006, R + 0.004), escuro, 0.002))
    objs.append(bloco("CaixaMira", (0.104, 0.032, 0.040), (-0.104, 0.008, R + 0.028), verde, 0.005))
    objs.append(
        torno(
            "Ocular",
            [(0.0, -0.176), (0.0105, -0.176), (0.0118, -0.170), (0.0118, -0.150), (0.0, -0.150)],
            p["borr"],
            (0.0, 0.008, R + 0.030),
            eixo,
            n=32,
        )
    )
    objs.append(
        torno(
            "Objetiva",
            [(0.0, -0.054), (0.0128, -0.054), (0.0128, -0.040), (0.0, -0.040)],
            aco,
            (0.0, 0.008, R + 0.030),
            eixo,
            n=32,
        )
    )
    objs.append(bloco("Regulagem", (0.024, 0.006, 0.016), (-0.096, -0.010, R + 0.030), aco, 0.0014))
    objs.append(bloco("PeMassa", (0.026, 0.016, 0.010), (0.380, 0.0, R + 0.004), escuro, 0.002))
    massa = [(0.372, R + 0.006), (0.388, R + 0.006), (0.383, R + 0.044), (0.377, R + 0.044)]
    objs.append(prisma("Massa", massa, 0.004, aco, (0, 0.002, 0), (90, 0, 0), 0.0006))
    # trava de contato atrás, com a mola, e o fio do disparo por baixo do tubo
    objs.append(bloco("Contato", (0.052, 0.024, 0.014), (-0.664, 0.0, R + 0.006), escuro, 0.0024))
    objs.append(
        tubo(
            "Mola",
            [
                (-0.640, 0.0, R + 0.012),
                (-0.668, 0.0, R + 0.026),
                (-0.700, 0.0, R + 0.022),
                (-0.722, 0.0, R + 0.006),
            ],
            0.0022,
            aco,
        )
    )
    fio = [(-0.165, -0.022, z0 + 0.002)]
    for x in (-0.22, -0.32, -0.42, -0.52, -0.60):
        fio.append((x, -R * 0.60, -R * 0.84))
    fio += [
        (-0.645, -R * 0.92, -R * 0.42),
        (-0.662, -R * 0.96, R * 0.28),
        (-0.664, -0.014, R + 0.004),
    ]
    objs.append(tubo("Fio", fio, 0.0020, preto))
    for x in (-0.34, -0.50):
        objs.append(bloco("Grampo", (0.006, 0.010, 0.005), (x, -R * 0.60, -R * 0.86), aco, 0.001))
    return objs


def render_arma(chave, amostras, teste, saida):
    C.cena_vazia()
    cena = bpy.context.scene
    larg, alt = (384, 192) if teste else (768, 384)
    L.configurar(cena, larg, alt, amostras)
    acabar(cena)
    mundo_estudio(cena)
    if chave == "m20":
        objs = modelo_m20(paleta())
        a, b_ = L.caixa_mundo(objs)
        lo, hi = np.array(a), np.array(b_)
    else:
        obj = arma_canonica(chave)
        if chave in REALCE:
            realcar(obj)
        lo, hi = C.caixa(obj)
    tam = hi - lo
    centro = Vector(((lo + hi) / 2).tolist())
    # o quadro e a luz seguem o tamanho da arma: a pistola sai com a mesma luz do fuzil
    r = float(max(tam[0], tam[2] * 2)) / 2
    camera_orto(centro, float(tam[0]), float(tam[2]), larg, alt)
    luzes_catalogo(centro, r)
    apanha_sombra((centro.x, float(hi[1]) + 0.15 * r, centro.z), (0, -1, 0), 40 * r)
    saida.mkdir(parents=True, exist_ok=True)
    arquivo = saida / f"{chave}.png"
    cena.render.filepath = str(arquivo)
    bpy.ops.render.render(write_still=True)
    apagar_bordas(arquivo)
    log("ok arma", chave, "dim", [round(float(x), 3) for x in tam])


# ------------------------------------------------------------------ 2. equipamento
def paleta():
    return {
        "od": pintado("OD", (0.33, 0.36, 0.20)),
        "od2": pintado("OD2", (0.25, 0.28, 0.16)),
        "aco": mat("Aco", (0.66, 0.66, 0.64), metal=1.0, rug=0.32, escala=900),
        "preto": mat("Preto", (0.05, 0.05, 0.055), rug=0.42, escala=900),
        "borr": mat("Borracha", (0.035, 0.035, 0.035), rug=0.72, escala=1400, forca=0.08),
        "latao": mat("Latao", (0.86, 0.68, 0.34), metal=1.0, rug=0.24, escala=1400, forca=0.012),
        "cobre": mat("Cobre", (0.78, 0.44, 0.28), metal=1.0, rug=0.26, escala=1400, forca=0.012),
        "alum": mat("Aluminio", (0.80, 0.81, 0.80), metal=1.0, rug=0.38, escala=1200),
        "amarelo": mat("Amarelo", (0.92, 0.76, 0.18), rug=0.55, forca=0.0),
        "branco": mat("Branco", (0.90, 0.88, 0.80), rug=0.6, forca=0.0),
        "tinta": mat("TintaAmarela", (0.93, 0.80, 0.30), rug=0.6, forca=0.0),
    }


def malhas_cartucho(p):
    estojo = malha_torno(
        "Estojo",
        [
            (0.0, 0.0),
            (0.0058, 0.0),
            (0.0060, 0.0004),
            (0.0060, 0.0012),
            (0.0052, 0.0017),
            (0.0052, 0.0031),
            (0.0059, 0.0037),
            (0.0058, 0.039),
            (0.0051, 0.0432),
            (0.0041, 0.0462),
            (0.0041, 0.0512),
            (0.0038, 0.0515),
            (0.0, 0.0515),
        ],
        n=28,
    )
    estojo.materials.append(p["latao"])
    bala = malha_torno(
        "Bala",
        [
            (0.0, 0.05),
            (0.0039, 0.05),
            (0.0039, 0.0565),
            (0.0034, 0.0622),
            (0.0021, 0.0672),
            (0.0007, 0.0705),
            (0.0, 0.0712),
        ],
        n=24,
    )
    bala.materials.append(p["cobre"])
    return estojo, bala


def cartucho(malhas, pos, rot):
    return [
        ligar("Estojo", malhas[0], None, pos, rot),
        ligar("Bala", malhas[1], None, pos, rot),
    ]


def eq_frag_us(_p):
    return [peca_do_jogo("grenade_m26")]


def eq_frag_vc(_p):
    o = peca_do_jogo("grenade_stick")
    return [o]


def eq_smoke(_p):
    return [peca_do_jogo("smoke_m18")]


def eq_shovel_us(_p):
    o = peca_do_jogo("shovel_us")
    return [o]


def eq_shovel_vc(_p):
    o = peca_do_jogo("shovel_vc")
    return [o]


def eq_bandage(p):
    """Curativo de campanha: o pacote de papel OD com estêncil e o rolo de gaze ao lado."""
    papel = pintado("Papel", (0.36, 0.34, 0.22), rug=0.78, escala=620, aco=(0.55, 0.50, 0.36))
    gaze = mat_tecido("Gaze", (0.90, 0.87, 0.78), escala=2600)
    fita = mat_tecido("Tira", (0.84, 0.80, 0.70), escala=2200)
    pacote = [bloco("Pacote", (0.122, 0.082, 0.027), (0, 0, 0.0145), papel, 0.0085)]
    for lado in (-1, 1):
        pacote.append(
            bloco("Dobra", (0.012, 0.072, 0.0022), (lado * 0.0655, 0, 0.0125), papel, 0.0006)
        )
        for i in range(9):
            pacote.append(
                bloco(
                    "Serrilha",
                    (0.0105, 0.0009, 0.0003),
                    (lado * 0.0655, -0.032 + i * 0.008, 0.0138),
                    p["od2"],
                    0,
                )
            )
    for txt, h, y in (
        ("FIRST AID", 0.0125, 0.017),
        ("DRESSING, FIELD", 0.0078, -0.001),
        ("U.S. ARMY", 0.0066, -0.016),
    ):
        pacote.append(estencil(txt, p["preto"], (0, y, 0.02815), h, (0, 0, 0)))
    objs = grupo(pacote, (-0.032, 0.012, 0.0), (0, 0, -9))
    # o rolo de gaze em pé, com a volta solta
    rolo = torno(
        "Rolo",
        [
            (0.0, 0.0),
            (0.024, 0.0),
            (0.0255, 0.0015),
            (0.0255, 0.058),
            (0.024, 0.0595),
            (0.0, 0.0595),
        ],
        gaze,
        (0.062, -0.048, 0.0),
        n=56,
        angulo=50,
    )
    objs.append(rolo)
    for i in range(1, 6):
        objs.append(toro("Volta", 0.0255 * i / 6 + 0.002, 0.00035, fita, (0.062, -0.048, 0.0597)))
    ponta = [
        (0.0865, -0.056, 0.002),
        (0.106, -0.070, 0.0015),
        (0.118, -0.098, 0.0015),
        (0.100, -0.120, 0.0015),
        (0.074, -0.118, 0.0015),
    ]
    tira = tubo("Tira", ponta, 0.012, fita)
    tira.data.bevel_depth = 0.0
    tira.data.extrude = 0.012
    tira.data.twist_mode = "Z_UP"
    tira.data.dimensions = "3D"
    objs.append(tira)
    return objs


def eq_mag_rifle(p):
    """Carregador de 20 tiros da M14: corpo com nervuras, lábios, base e a munição no topo."""
    objs = []
    perfil = [
        (-0.044, 0.0),
        (0.040, 0.0),
        (0.048, 0.060),
        (0.052, 0.116),
        (0.052, 0.150),
        (-0.036, 0.150),
        (-0.040, 0.116),
        (-0.042, 0.060),
    ]
    e = 0.026
    objs.append(prisma("Corpo", perfil, e, p["od"], (0, e / 2, 0), (90, 0, 0), 0.0016))
    objs.append(bloco("Base", (0.096, 0.031, 0.006), (-0.002, 0, 0.001), p["aco"], 0.0012))
    objs.append(bloco("Trava", (0.012, 0.031, 0.014), (-0.040, 0, 0.012), p["aco"], 0.001))
    for dz, c in ((0.030, 0.076), (0.066, 0.082), (0.102, 0.086)):
        for lado in (-1, 1):
            objs.append(
                bloco(
                    "Nervura",
                    (c, 0.0012, 0.009),
                    (0.003 + dz * 0.04, lado * (e / 2 + 0.0002), dz),
                    p["od2"],
                    0.0005,
                )
            )
    for lado in (-1, 1):
        objs.append(
            bloco(
                "Labio", (0.052, 0.0024, 0.007), (-0.002, lado * 0.0130, 0.1525), p["aco"], 0.0008
            )
        )
    objs.append(bloco("Seguidor", (0.08, 0.021, 0.003), (0.007, 0, 0.1485), p["preto"], 0.0006))
    m = malhas_cartucho(p)
    objs += cartucho(m, (-0.026, 0.0, 0.1635), (0, 90, 0))
    objs += cartucho(m, (-0.033, 0.0066, 0.1555), (0, 90, 0))
    objs += cartucho(m, (-0.033, -0.0066, 0.1555), (0, 90, 0))
    objs.append(estencil("7.62MM", p["tinta"], (0.004, -e / 2 - 0.0008, 0.0485), 0.0105))
    return grupo(objs, (0, 0, 0.012), (0, 11, 0))


def eq_mag_pistol(p):
    """Carregador de M1911: chapa fina, janelas de contagem, base e o cartucho .45 no topo."""
    objs = []
    perfil = [(-0.0165, 0.0), (0.0165, 0.0), (0.0170, 0.112), (-0.0160, 0.112)]
    e = 0.0128
    objs.append(prisma("Corpo", perfil, e, p["preto"], (0, e / 2, 0), (90, 0, 0), 0.0010))
    aco = mat("Oxidado", (0.54, 0.54, 0.58), metal=1.0, rug=0.46, escala=1400)
    objs[0].data.materials.clear()
    objs[0].data.materials.append(aco)
    objs.append(bloco("Base", (0.039, 0.0165, 0.0045), (0.0006, 0, -0.0015), aco, 0.0009))
    for i in range(7):
        objs.append(
            torno(
                "Janela",
                [(0.0, 0.0), (0.0021, 0.0), (0.0021, 0.0004), (0.0, 0.0004)],
                p["preto"],
                (-0.009, -e / 2 - 0.0002, 0.014 + i * 0.0125),
                (90, 0, 0),
                n=18,
            )
        )
    for lado in (-1, 1):
        objs.append(
            bloco("Labio", (0.03, 0.0015, 0.007), (0.002, lado * 0.0063, 0.1145), aco, 0.0005)
        )
    estojo = torno(
        "Estojo45",
        [
            (0.0, 0.0),
            (0.0058, 0.0),
            (0.0060, 0.0005),
            (0.0060, 0.0012),
            (0.0054, 0.0018),
            (0.0058, 0.0028),
            (0.0060, 0.0228),
            (0.0, 0.0228),
        ],
        p["latao"],
        (-0.0115, 0, 0.1205),
        (0, 90, 0),
        n=28,
    )
    bala = torno(
        "Bala45",
        [
            (0.0, 0.0225),
            (0.0057, 0.0225),
            (0.0057, 0.027),
            (0.0048, 0.0310),
            (0.0030, 0.0335),
            (0.0, 0.0345),
        ],
        p["cobre"],
        (-0.0115, 0, 0.1205),
        (0, 90, 0),
        n=28,
    )
    objs += [estojo, bala]
    return grupo(objs, (0, 0, 0.012), (0, 11, 0))


def eq_belt(p):
    """Fita de elos M13 em S, com os cartuchos de 7,62 deitados."""
    m = malhas_cartucho(p)
    elo = mat("Elo", (0.34, 0.34, 0.33), metal=1.0, rug=0.42, escala=1200)
    anel = malha_toro("Anel", 0.0066, 0.0011, 24, 8)
    anel.materials.append(elo)
    ponte = bpy.data.meshes.new("Ponte")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((0.0165, 0.0052, 0.0014)), verts=bm.verts)
    bm.to_mesh(ponte)
    bm.free()
    ponte.materials.append(elo)
    objs = []
    n = 9
    passo = 0.0172
    for i in range(n):
        u = (i - (n - 1) / 2) * passo
        y = 0.010 * math.sin(u * 26.0)
        inc = math.degrees(math.atan(0.010 * 26.0 * math.cos(u * 26.0)))
        z = 0.0062
        grupo_i = []
        grupo_i += cartucho(m, (0, -0.024, 0), (-90, 0, 0))
        for dy in (-0.019, 0.003):
            grupo_i.append(ligar("Anel", anel, None, (0, dy, 0), (90, 0, 0)))
            grupo_i.append(ligar("Ponte", ponte, None, (0.0086, dy, 0.0060), (0, 8, 0)))
        objs += grupo(grupo_i, (u, y, z), (0, 0, inc))
    return grupo(objs, (0, 0, 0), (0, 0, 34))


def eq_shells(p):
    """Cartuchos de 12: base de latão, tubo de papel encerado e o fecho em estrela."""
    papel = mat("PapelCartucho", (0.42, 0.13, 0.10), rug=0.46, clear=0.25, escala=1200, forca=0.02)

    def fecho(x, y, z):
        if z < 0.0595:
            return (x, y, z)
        r = math.hypot(x, y)
        t = math.atan2(y, x)
        return (x, y, z - 0.0012 * (1 - r / 0.0097) * (1 + math.cos(6 * t)))

    perfil_cabeca = [
        (0.0, 0.0),
        (0.0108, 0.0),
        (0.0112, 0.0005),
        (0.0112, 0.0016),
        (0.0101, 0.0021),
        (0.0101, 0.0165),
        (0.0, 0.0165),
    ]
    perfil_tubo = [
        (0.0, 0.015),
        (0.0097, 0.015),
        (0.0097, 0.0585),
        (0.0092, 0.0612),
        (0.0074, 0.0622),
        (0.0040, 0.0622),
        (0.0020, 0.0615),
        (0.0, 0.061),
    ]
    me_c = malha_torno("Cabeca", perfil_cabeca, 48)
    me_c.materials.append(p["latao"])
    me_t = malha_torno("Tubo", perfil_tubo, 72, fecho)
    me_t.materials.append(papel)
    objs = []
    for pos, rot in (
        ((-0.018, 0.016, 0.0), (0, 0, 0)),
        ((0.012, 0.024, 0.0), (0, 0, 40)),
        ((-0.012, -0.024, 0.0112), (90, 0, 60)),
        ((0.036, -0.010, 0.0112), (90, 0, 118)),
    ):
        objs.append(ligar("Cabeca", me_c, None, pos, rot))
        objs.append(ligar("Tubo", me_t, None, pos, rot))
    return objs


def eq_grenade40(p):
    """Granada de 40 mm (M406): estojo de alumínio, cinta de cobre, corpo OD e ogiva dourada."""
    verde = pintado("Corpo40", (0.25, 0.29, 0.16), rug=0.48, escala=700)
    ouro = mat("Ogiva", (0.84, 0.66, 0.26), metal=1.0, rug=0.3, escala=1200, forca=0.01)

    def rodada(pos, rot):
        partes = [
            torno(
                "Estojo40",
                [
                    (0.0, 0.0),
                    (0.0208, 0.0),
                    (0.0212, 0.0008),
                    (0.0212, 0.0024),
                    (0.0200, 0.0030),
                    (0.0200, 0.0440),
                    (0.0196, 0.0456),
                    (0.0, 0.0456),
                ],
                p["alum"],
                n=64,
            ),
            torno(
                "Cinta40",
                [(0.0, 0.0448), (0.0204, 0.0448), (0.0204, 0.0512), (0.0, 0.0512)],
                p["cobre"],
                n=64,
            ),
            torno(
                "Corpo40",
                [(0.0, 0.051), (0.0198, 0.051), (0.0198, 0.0720), (0.0186, 0.0795), (0.0, 0.0795)],
                verde,
                n=64,
            ),
            torno(
                "Ogiva40",
                [
                    (0.0, 0.0792),
                    (0.0186, 0.0792),
                    (0.0170, 0.0852),
                    (0.0128, 0.0918),
                    (0.0078, 0.0962),
                    (0.0054, 0.0978),
                    (0.0054, 0.1012),
                    (0.0, 0.1016),
                ],
                ouro,
                n=64,
                angulo=48,
            ),
        ]
        partes.append(estencil_cil("40MM", p["tinta"], 0.01985, 0.0602, 0.0072, 12.0))
        partes.append(estencil_cil("HE M406", p["tinta"], 0.01985, 0.0535, 0.0048, 12.0))
        return grupo(partes, pos, rot)

    return rodada((-0.016, 0.022, 0.0), (0, 0, 0)) + rodada((0.046, -0.022, 0.0212), (0, 90, -32))


def eq_radio(p):
    """Rádio AN/PRC-10: caixa com tampa, painel de cima, botões, antena de fita e monofone."""
    objs = []
    W, D, H = 0.25, 0.115, 0.30
    objs.append(bloco("Caixa", (W, D, H), (0, 0, H / 2), p["od"], 0.005))
    objs.append(bloco("Tampo", (W + 0.008, D + 0.008, 0.038), (0, 0, H - 0.019), p["od2"], 0.004))
    objs.append(bloco("Faixa", (W + 0.004, D + 0.004, 0.006), (0, 0, 0.098), p["od2"], 0.0012))
    for x in (-1, 1):
        for z in (0.013, H - 0.052):
            objs.append(
                torno(
                    "Parafuso",
                    [(0.0, 0.0), (0.0042, 0.0), (0.0042, 0.002), (0.0028, 0.0028), (0.0, 0.0028)],
                    p["aco"],
                    (x * (W / 2 - 0.012), -D / 2 - 0.0005, z + 0.008),
                    (90, 0, 0),
                    n=18,
                )
            )
    objs.append(estencil("RADIO SET", p["tinta"], (0.0, -D / 2 - 0.0006, 0.190), 0.024))
    objs.append(estencil("AN/PRC-10", p["tinta"], (0.0, -D / 2 - 0.0006, 0.157), 0.024))
    objs.append(estencil("U.S. MARINE CORPS", p["tinta"], (0.0, -D / 2 - 0.0006, 0.128), 0.0105))
    z0 = H + 0.0005

    def botao(x, y, r, h, serrilha=24):
        def corta(px, py, pz):
            q = math.hypot(px, py)
            if q < r * 0.8 or pz > h * 0.92:
                return (px, py, pz)
            t = math.atan2(py, px)
            k = 1 + 0.035 * math.cos(serrilha * t)
            return (px * k, py * k, pz)

        perfil = [
            (0.0, 0.0),
            (r * 1.08, 0.0),
            (r * 1.08, h * 0.14),
            (r, h * 0.2),
            (r, h * 0.86),
            (r * 0.9, h),
            (0.0, h),
        ]
        k = torno("Botao", perfil, p["preto"], (x, y, z0), n=96, deforma=corta, angulo=42)
        marca = bloco(
            "Marca", (r * 0.14, r * 0.8, 0.0006), (x, y - r * 0.42, z0 + h), p["branco"], 0
        )
        return [k, marca]

    objs += botao(-0.074, 0.002, 0.024, 0.021, 30)
    objs += botao(0.012, 0.016, 0.0145, 0.016, 20)
    objs += botao(0.056, 0.016, 0.0115, 0.016, 18)
    # janela da frequência com a escala
    objs.append(
        bloco("Moldura", (0.062, 0.030, 0.004), (0.036, -0.030, z0 + 0.0015), p["aco"], 0.001)
    )
    objs.append(
        bloco("Escala", (0.054, 0.022, 0.0012), (0.036, -0.030, z0 + 0.0032), p["branco"], 0)
    )
    for i in range(13):
        h = 0.012 if i % 4 == 0 else 0.007
        objs.append(
            bloco(
                "Traco",
                (0.0007, h, 0.0003),
                (0.0125 + i * 0.0039, -0.033 + h / 2 - 0.004, z0 + 0.0040),
                p["preto"],
                0,
            )
        )
    objs.append(
        bloco(
            "Agulha",
            (0.0009, 0.021, 0.0004),
            (0.041, -0.030, z0 + 0.0044),
            mat("Agulha", (0.8, 0.14, 0.08), rug=0.4, forca=0.0),
            0,
        )
    )
    # conector e base da antena
    objs.append(
        torno(
            "Conector",
            [
                (0.0, 0.0),
                (0.0105, 0.0),
                (0.0105, 0.016),
                (0.0075, 0.018),
                (0.0075, 0.03),
                (0.0, 0.03),
            ],
            p["aco"],
            (0.096, -0.028, z0),
            n=32,
        )
    )
    objs.append(
        torno(
            "BaseAntena",
            [
                (0.0, 0.0),
                (0.012, 0.0),
                (0.012, 0.01),
                (0.0062, 0.017),
                (0.0052, 0.034),
                (0.0, 0.034),
            ],
            p["aco"],
            (0.098, 0.030, z0),
            n=32,
        )
    )
    # antena de fita, curvada para caber no quadro
    fita = [
        (0.098, 0.030, z0 + 0.03),
        (0.099, 0.032, z0 + 0.065),
        (0.104, 0.036, z0 + 0.098),
        (0.118, 0.040, z0 + 0.122),
        (0.140, 0.043, z0 + 0.134),
        (0.166, 0.045, z0 + 0.136),
    ]
    a = tubo("Antena", fita, 0.0024, mat("Antena", (0.14, 0.15, 0.10), metal=0.4, rug=0.42))
    objs.append(a)
    # alças de lona na frente
    lona = mat_tecido("Lona", (0.34, 0.36, 0.20), escala=1500)
    for x in (-0.088, 0.088):
        objs.append(
            bloco("Alca", (0.026, 0.0034, 0.214), (x, -D / 2 - 0.0016, 0.122), lona, 0.0006)
        )
        objs.append(
            bloco("Fivela", (0.032, 0.0044, 0.010), (x, -D / 2 - 0.0032, 0.052), p["aco"], 0.001)
        )
    # monofone encostado à direita
    fone = []
    for z, r_c in ((0.0, 0.033), (0.148, 0.030)):
        fone.append(
            torno(
                "Copo",
                [
                    (0.0, -0.016),
                    (r_c * 0.9, -0.016),
                    (r_c, -0.012),
                    (r_c, 0.008),
                    (r_c * 0.84, 0.016),
                    (r_c * 0.35, 0.018),
                    (0.0, 0.018),
                ],
                p["preto"],
                (0.0, 0.0, z),
                (90, 0, 0),
                n=48,
                angulo=48,
            )
        )
    fone.append(bloco("Cabo", (0.026, 0.024, 0.15), (0.0, 0.0, 0.074), p["preto"], 0.007))
    fone.append(bloco("Tecla", (0.014, 0.008, 0.034), (0.0, -0.014, 0.078), p["aco"], 0.002))
    objs += grupo(fone, (0.168, -0.042, 0.050), (0, -10, 12))
    espiral = []
    for i in range(140):
        t = i / 139
        ang = t * 2 * math.pi * 11
        espiral.append(
            (
                0.158 + 0.0065 * math.cos(ang) - 0.048 * t,
                -0.042 + 0.0065 * math.sin(ang) - 0.034 * t,
                0.034 - 0.022 * t + 0.016 * math.sin(t * math.pi),
            )
        )
    objs.append(tubo("Fio", espiral, 0.0011, p["borr"], resolucao=3))
    return grupo(objs, (-0.03, 0, 0), (0, 0, 0))


def eq_binoculos(p):
    """Binóculo Porro 7x50 (M17): corpo de couro, ocular de borracha e lentes com tratamento."""
    couro = mat("Couro", (0.075, 0.075, 0.07), rug=0.62, escala=2200, forca=0.14)
    metal = mat("Metal", (0.12, 0.12, 0.13), metal=1.0, rug=0.33, escala=1600)
    vidro = mat_vidro("Vidro", (0.05, 0.06, 0.13))
    objs = []
    for lado in (-1, 1):
        x_ob, x_oc = lado * 0.054, lado * 0.0355
        objs.append(
            torno(
                "Objetiva",
                [
                    (0.0, 0.0),
                    (0.0272, 0.0),
                    (0.0272, 0.012),
                    (0.0297, 0.016),
                    (0.0297, 0.058),
                    (0.0322, 0.061),
                    (0.0322, 0.072),
                    (0.0294, 0.0735),
                    (0.0266, 0.0705),
                    (0.0, 0.0705),
                ],
                couro,
                (x_ob, -0.002, 0.042),
                (90, 0, 0),
                n=72,
                angulo=45,
            )
        )
        objs.append(
            torno(
                "Anel",
                [(0.0, 0.058), (0.0325, 0.058), (0.0325, 0.0735), (0.0, 0.0735)],
                metal,
                (x_ob, -0.002, 0.042),
                (90, 0, 0),
                n=72,
            )
        )
        objs.append(
            torno(
                "Lente",
                [(0.0, 0.0725), (0.0262, 0.0725), (0.0262, 0.0738), (0.012, 0.0752), (0.0, 0.0755)],
                vidro,
                (x_ob, -0.002, 0.042),
                (90, 0, 0),
                n=56,
                angulo=60,
            )
        )
        objs.append(
            bloco(
                "Prisma",
                (0.070, 0.070, 0.056),
                (lado * 0.046, 0.030, 0.042),
                couro,
                0.012,
                (0, lado * -6, 0),
            )
        )
        objs.append(
            bloco("Tampo", (0.05, 0.028, 0.004), (lado * 0.046, 0.030, 0.071), metal, 0.0014)
        )
        objs.append(
            torno(
                "Ocular",
                [
                    (0.0, 0.0),
                    (0.0185, 0.0),
                    (0.0185, 0.012),
                    (0.0165, 0.016),
                    (0.0165, 0.030),
                    (0.0, 0.030),
                ],
                metal,
                (x_oc, 0.058, 0.042),
                (-90, 0, 0),
                n=56,
            )
        )
        objs.append(
            torno(
                "Copa",
                [
                    (0.0115, 0.0255),
                    (0.0182, 0.0255),
                    (0.0202, 0.040),
                    (0.0212, 0.051),
                    (0.0188, 0.0535),
                    (0.0145, 0.044),
                    (0.0115, 0.040),
                ],
                p["borr"],
                (x_oc, 0.058, 0.042),
                (-90, 0, 0),
                n=56,
                angulo=70,
            )
        )
        objs.append(
            torno(
                "VidroOc",
                [(0.0, 0.036), (0.0118, 0.036), (0.0118, 0.0372), (0.0, 0.0378)],
                vidro,
                (x_oc, 0.058, 0.042),
                (-90, 0, 0),
                n=40,
            )
        )
    objs.append(
        torno(
            "Eixo",
            [
                (0.0, -0.05),
                (0.0088, -0.05),
                (0.0092, -0.046),
                (0.0092, 0.046),
                (0.0088, 0.05),
                (0.0, 0.05),
            ],
            metal,
            (0, 0.030, 0.068),
            (90, 0, 0),
            n=40,
        )
    )
    objs.append(
        torno(
            "Foco",
            [(0.0, -0.011), (0.0132, -0.011), (0.0132, 0.011), (0.0, 0.011)],
            p["borr"],
            (0, 0.048, 0.068),
            (90, 0, 0),
            n=48,
        )
    )
    return grupo(objs, (0, 0, 0.0115), (0, 0, 28))


def eq_ammo_box(p):
    """Lata de munição M19A1: tampa com vedação, dobradiça, trava lateral, alça e estêncil."""
    W, D, H = 0.280, 0.152, 0.182
    verde = pintado("Lata", (0.29, 0.33, 0.18), rug=0.46, escala=320)
    objs = [bloco("Corpo", (W, D, H), (0, 0, H / 2), verde, 0.003)]
    tampa_h = 0.042
    objs.append(
        bloco(
            "Tampa", (W + 0.008, D + 0.008, tampa_h), (0, 0, H + tampa_h / 2 - 0.008), verde, 0.004
        )
    )
    objs.append(
        bloco("Topo", (W - 0.018, D - 0.016, 0.004), (0, 0, H + tampa_h - 0.007), verde, 0.0016)
    )
    # nervuras prensadas no lado comprido e no curto
    for z in (0.038, H - 0.050):
        objs.append(
            bloco("FrisoF", (W - 0.030, 0.0022, 0.009), (0, -D / 2 - 0.0005, z), verde, 0.0009)
        )
    for y in (-0.040, 0.040):
        objs.append(
            bloco(
                "FrisoL",
                (0.0022, 0.016, H - 0.070),
                (W / 2 + 0.0005, y, H / 2 - 0.008),
                verde,
                0.0009,
            )
        )
    # dobradiça atrás
    objs.append(
        torno(
            "Dobradica",
            [(0.0, -0.11), (0.0036, -0.11), (0.0036, 0.11), (0.0, 0.11)],
            p["aco"],
            (0, D / 2 + 0.005, H + 0.004),
            (0, 90, 0),
            n=18,
        )
    )
    # trava no lado direito: braço, pino e a alavanca
    objs.append(bloco("Trava", (0.006, 0.044, 0.070), (W / 2 + 0.006, 0, H + 0.002), verde, 0.0016))
    objs.append(
        torno(
            "Pino",
            [(0.0, 0.0), (0.0055, 0.0), (0.0055, 0.004), (0.0, 0.004)],
            p["aco"],
            (W / 2 + 0.008, 0, H + 0.026),
            (0, 90, 0),
            n=20,
        )
    )
    # alça dobrada sobre a tampa
    z_a = H + tampa_h - 0.0035
    pts = [
        (-0.062, 0.0, z_a - 0.003),
        (-0.060, 0.0, z_a + 0.006),
        (-0.050, 0.0, z_a + 0.009),
        (0.050, 0.0, z_a + 0.009),
        (0.060, 0.0, z_a + 0.006),
        (0.062, 0.0, z_a - 0.003),
    ]
    objs.append(tubo("Alca", pts, 0.0044, p["aco"]))
    for x in (-0.062, 0.062):
        objs.append(bloco("Olhal", (0.016, 0.012, 0.005), (x, 0.0, z_a - 0.001), verde, 0.0012))
    y = -D / 2 - 0.0013
    objs.append(estencil("200 CARTRIDGES", p["tinta"], (0, y, 0.116), 0.0196))
    objs.append(estencil("7.62MM NATO BALL M80", p["tinta"], (0, y, 0.092), 0.0138))
    objs.append(estencil("LINKED M13 - LOT LC-65", p["tinta"], (0, y, 0.066), 0.0108))
    return objs


EQUIP = {
    "frag_us": (eq_frag_us, (0.75, -1.0, 0.45)),
    "frag_vc": (eq_frag_vc, (0.55, -1.0, 0.75)),
    "smoke": (eq_smoke, (0.75, -1.0, 0.55)),
    "bandage": (eq_bandage, (0.5, -1.0, 0.85)),
    "mag_rifle": (eq_mag_rifle, (0.55, -1.0, 0.38)),
    "mag_pistol": (eq_mag_pistol, (0.55, -1.0, 0.38)),
    "belt_mg": (eq_belt, (0.35, -1.0, 0.95)),
    "shells": (eq_shells, (0.5, -1.0, 0.72)),
    "grenade40": (eq_grenade40, (0.55, -1.0, 0.48)),
    "shovel_us": (eq_shovel_us, (0.4, -1.0, 1.05)),
    "shovel_vc": (eq_shovel_vc, (0.4, -1.0, 1.05)),
    "radio": (eq_radio, (0.62, -1.0, 0.52)),
    "binoculars": (eq_binoculos, (0.5, -1.0, 0.62)),
    "ammo_box": (eq_ammo_box, (0.62, -1.0, 0.55)),
}


def render_equip(chave, amostras, teste, saida):
    C.cena_vazia()
    cena = bpy.context.scene
    lado = 256 if teste else 512
    L.configurar(cena, lado, lado, amostras)
    acabar(cena)
    mundo_estudio(cena)
    fn, direcao = EQUIP[chave]
    objs = fn(paleta())
    bpy.context.view_layer.update()
    vis = [o for o in objs if o.type in ("MESH", "CURVE", "FONT")]
    cam, centro, raio = L.camera_para(vis, lado, lado, direcao=direcao, lente=85.0, folga=1.16)
    cam.data.clip_start = 0.01
    luzes_catalogo(centro, raio * 1.05)
    lo, _ = L.caixa_mundo(vis)
    bpy.ops.mesh.primitive_plane_add(size=40 * raio, location=(centro.x, centro.y, float(lo.z)))
    chao = bpy.context.active_object
    chao.name = "Sombra"
    chao.is_shadow_catcher = True
    chao.visible_glossy = False
    chao.visible_shadow = False
    saida.mkdir(parents=True, exist_ok=True)
    arquivo = saida / f"{chave}.png"
    cena.render.filepath = str(arquivo)
    bpy.ops.render.render(write_still=True)
    apagar_bordas(arquivo, 0.04, 0.04)
    log("ok equip", chave)


# ------------------------------------------------------------------ 3. insígnias das classes
FUZIL = [
    (-0.68, -0.055),
    (-0.66, 0.040),
    (-0.34, 0.040),
    (-0.24, 0.058),
    (0.06, 0.058),
    (0.12, 0.034),
    (0.68, 0.034),
    (0.68, 0.006),
    (0.32, 0.004),
    (0.24, -0.034),
    (0.06, -0.034),
    (0.02, -0.095),
    (-0.05, -0.095),
    (-0.06, -0.038),
    (-0.30, -0.044),
    (-0.42, -0.104),
    (-0.66, -0.128),
]


def s_commander():
    return [
        (E.louro(0.60, 8), "m", 0.0),
        ([E.estrela(5, 0.31, 0.128, 90, 0, 0.17)], "c", 0.016),
        (
            [
                E.estrela(5, 0.175, 0.072, 90, -0.27, -0.24),
                E.estrela(5, 0.175, 0.072, 90, 0.27, -0.24),
            ],
            "c",
            0.016,
        ),
    ]


def s_squad_leader():
    def divisa(y, w=0.54, alto=0.27, grossa=0.135):
        return [
            (-w, y - alto),
            (0.0, y + alto * 0.62),
            (w, y - alto),
            (w, y - alto - grossa),
            (0.0, y + alto * 0.62 - grossa * 1.24),
            (-w, y - alto - grossa),
        ]

    return [
        ([divisa(0.42), divisa(0.13), divisa(-0.16)], "m", 0.0),
        ([E.estrela(5, 0.115, 0.048, 90, 0, -0.50)], "c", 0.012),
    ]


def s_rifleman():
    grosso = [(x, y * 1.55) for x, y in FUZIL]
    a = E.gira(grosso, 42)
    b = E.espelha(E.gira(grosso, 42))
    return [
        ([a], "m", 0.0),
        ([b], "b", 0.02),
        ([E.circulo(0, 0.0, 0.05, 20)], "c", 0.04),
    ]


def s_medic():
    braco = 0.17
    cruz = [
        (-braco, 0.58),
        (braco, 0.58),
        (braco, braco),
        (0.58, braco),
        (0.58, -braco),
        (braco, -braco),
        (braco, -0.58),
        (-braco, -0.58),
        (-braco, -braco),
        (-0.58, -braco),
        (-0.58, braco),
        (-braco, braco),
    ]
    haste = [(-0.022, 0.50), (0.022, 0.50), (0.022, -0.50), (-0.022, -0.50)]
    linha = E.curva_s((0.0, -0.44), (0.0, 0.36), 0.085, 2.25, 72)
    cobra = E.fita(linha, [0.018 + 0.03 * min(1.0, i / 12) for i in range(73)])
    cabeca = E.elipse(linha[-1][0] + 0.012, linha[-1][1] + 0.024, 0.042, 0.03, 30, 18)
    return [
        ([cruz], "b", 0.0),
        ([haste], "e", 0.02),
        ([cobra, cabeca], "c", 0.03),
    ]


def s_support():
    chave_ing = [
        (-0.60, -0.052),
        (0.24, -0.052),
        (0.31, -0.13),
        (0.50, -0.16),
        (0.62, -0.08),
        (0.46, -0.07),
        (0.40, 0.0),
        (0.46, 0.07),
        (0.62, 0.08),
        (0.50, 0.16),
        (0.31, 0.13),
        (0.24, 0.052),
        (-0.60, 0.052),
        (-0.64, 0.0),
    ]
    martelo = [
        (-0.62, -0.046),
        (0.30, -0.046),
        (0.30, -0.23),
        (0.50, -0.23),
        (0.50, 0.10),
        (0.43, 0.21),
        (0.30, 0.13),
        (0.30, 0.046),
        (-0.62, 0.046),
    ]
    return [
        ([E.gira(chave_ing, 45)], "m", 0.0),
        ([E.gira(martelo, 135)], "b", 0.02),
        ([E.circulo(0, 0, 0.055, 20)], "c", 0.04),
    ]


def s_machine_gunner():
    corpo = [
        (-0.66, 0.02),
        (-0.63, 0.17),
        (-0.40, 0.14),
        (-0.28, 0.17),
        (0.05, 0.17),
        (0.08, 0.135),
        (0.42, 0.125),
        (0.42, 0.155),
        (0.48, 0.155),
        (0.48, 0.125),
        (0.68, 0.125),
        (0.68, 0.08),
        (0.42, 0.08),
        (0.08, 0.06),
        (0.02, 0.0),
        (-0.09, 0.0),
        (-0.11, -0.10),
        (-0.18, -0.10),
        (-0.17, 0.0),
        (-0.40, 0.0),
        (-0.52, -0.03),
    ]
    corpo = [(x, y * 1.22 + 0.10) for x, y in corpo]
    perna_a = E.fita([(0.34, 0.20), (0.48, -0.40)], 0.05)
    perna_b = E.fita([(0.34, 0.20), (0.20, -0.40)], 0.05)
    # a fita saindo da caixa: cinco cartuchos separados, em arco
    balas = []
    for i in range(5):
        t = i / 4
        x = -0.02 - 0.40 * t
        y = -0.20 - 0.24 * t**1.4
        bala = [
            (-0.034, -0.105),
            (0.034, -0.105),
            (0.034, 0.03),
            (0.0, 0.105),
            (-0.034, 0.03),
        ]
        balas.append(E.move(E.gira(bala, 14 * t), x, y))
    return [
        ([perna_a, perna_b], "b", 0.0),
        ([corpo], "m", 0.012),
        (balas, "c", 0.016),
    ]


def s_anti_tank():
    foguete = [
        (0.66, 0.0),
        (0.54, 0.075),
        (0.34, 0.135),
        (0.14, 0.135),
        (0.06, 0.055),
        (-0.30, 0.055),
        (-0.46, 0.16),
        (-0.52, 0.16),
        (-0.42, 0.03),
        (-0.46, 0.0),
        (-0.42, -0.03),
        (-0.52, -0.16),
        (-0.46, -0.16),
        (-0.30, -0.055),
        (0.06, -0.055),
        (0.14, -0.135),
        (0.34, -0.135),
        (0.54, -0.075),
    ]
    faixa = [(0.25, 0.135), (0.31, 0.135), (0.31, -0.135), (0.25, -0.135)]
    fogo = [
        E.pena(-0.45, 0.0, 0.30, 0.055, 180),
        E.pena(-0.45, 0.05, 0.20, 0.035, 158),
        E.pena(-0.45, -0.05, 0.20, 0.035, 202),
    ]
    return [
        ([E.gira(p, 45) for p in fogo], "c", 0.0),
        ([E.gira(foguete, 45)], "m", 0.012),
        ([E.gira(faixa, 45)], "c", 0.03),
    ]


def s_sniper():
    aro = [E.circulo(0, 0, 0.57, 72), E.circulo(0, 0, 0.47, 72)]
    fios = []
    for a in (0, 90, 180, 270):
        fios.append(E.gira([(0.12, -0.016), (0.66, -0.016), (0.66, 0.016), (0.12, 0.016)], a))
    tracos = []
    for a in (0, 90, 180, 270):
        for d in (0.22, 0.32):
            tracos.append(
                E.gira(
                    [(d - 0.012, -0.05), (d + 0.012, -0.05), (d + 0.012, 0.05), (d - 0.012, 0.05)],
                    a,
                )
            )
    return [
        (aro, "m", 0.0),
        (fios, "b", 0.012),
        (tracos, "b", 0.012),
        ([E.circulo(0, 0, 0.055, 24)], "c", 0.03),
    ]


# (cor do esmalte, cor do detalhe, símbolo)
CLASSES = {
    "commander": ((34, 48, 96), (240, 204, 104), s_commander),
    "squad_leader": ((104, 32, 28), (240, 204, 104), s_squad_leader),
    "rifleman": ((50, 66, 38), (232, 214, 150), s_rifleman),
    # sem o emblema da Cruz Vermelha (protegido): cruz branca sobre verde
    "medic": ((26, 88, 58), (24, 92, 62), s_medic),
    "support": ((106, 72, 28), (232, 196, 110), s_support),
    "machine_gunner": ((60, 38, 34), (226, 170, 80), s_machine_gunner),
    "anti_tank": ((122, 58, 20), (250, 210, 96), s_anti_tank),
    "sniper": ((24, 38, 44), (210, 46, 34), s_sniper),
}
_contorno_original = E.contorno


def contorno_classe(raridade):
    """A família das classes: escudo militar de latão (o resto continua como no emblemas.py)."""
    if raridade != "classe":
        return _contorno_original(raridade)
    fora = E.mir(
        [
            (0.0, 1.0),
            (0.30, 0.93),
            (0.62, 0.95),
            (0.90, 0.84),
            (0.89, 0.20),
            (0.76, -0.30),
            (0.44, -0.72),
            (0.0, -1.0),
        ]
    )
    dentro = E.mir(
        [
            (0.0, 0.85),
            (0.27, 0.79),
            (0.55, 0.81),
            (0.76, 0.72),
            (0.75, 0.17),
            (0.64, -0.25),
            (0.37, -0.61),
            (0.0, -0.84),
        ]
    )
    return fora, dentro


ESCALA_CLASSE = {"rifleman": 1.04, "machine_gunner": 1.0, "anti_tank": 1.0, "support": 1.0}
_esmalte_original = E.mat_esmalte


def esmalte_classe(nome, cor):
    """Esmalte acetinado: no brilhante, o painel de luz cortava o campo em dois tons."""
    m = _esmalte_original(nome, cor)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Roughness"].default_value = 0.40
    b.inputs["Specular IOR Level"].default_value = 0.32
    b.inputs["Coat Weight"].default_value = 0.35
    b.inputs["Coat Roughness"].default_value = 0.34
    return m


def render_classe(chave, amostras, teste, saida):
    E.contorno = contorno_classe
    E.mat_esmalte = esmalte_classe
    E.CHAPAS["classe"] = ((176, 138, 72), (238, 208, 142))
    E.SAIDA = saida
    cor, cor2, simbolo = CLASSES[chave]
    id_ = f"cls_{chave}"
    E.SIMBOLOS[id_] = simbolo
    E.ESCALA[id_] = ESCALA_CLASSE.get(chave, 0.92)
    try:
        E.render(id_, "classe", cor, cor2, amostras, 256 if teste else 512, f"{chave}.png")
    finally:
        E.mat_esmalte = _esmalte_original


# ------------------------------------------------------------------ 4. times
def tampo_de_tabuas(cor):
    """Mesa de tábuas largas, correndo em X."""
    m = mat_tabua("Tabua", cor)
    objs = []
    random.seed(65)
    for i in range(10):
        y = -1.15 + i * 0.235
        z = -0.019 + random.uniform(-0.0012, 0.0012)
        objs.append(bloco("Tabua", (4.2, 0.229, 0.038), (0.2, y, z), m, 0.0014))
    # o vão entre as tábuas é escuro
    fundo = mat("VaoMesa", (0.015, 0.012, 0.01), rug=0.9, forca=0.0)
    objs.append(bloco("Vao", (4.3, 2.6, 0.01), (0.2, -0.1, -0.034), fundo, 0.0))
    return objs


def fundo_escuro():
    """Pano de fundo: sem ele, o céu azul aparecia em volta da parede."""
    m = mat("FundoCena", (0.075, 0.060, 0.048), rug=0.9, forca=0.0)
    return bloco("Fundo", (9.0, 0.05, 5.0), (0.3, 2.3, 1.2), m, 0.0)


def bandeira_pano(caminho, larg, alt, pos, rot, n=120, amp=0.036):
    """Bandeira pendurada com dobras (mesma malha para as duas)."""
    m_x, m_y = n, int(n * alt / larg)
    vs, uv, fs = [], [], []
    for j in range(m_y + 1):
        v = j / m_y
        for i in range(m_x + 1):
            u = i / m_x
            cai = (1 - v) ** 1.4
            y = (
                amp
                * (
                    math.sin(u * 9.2 + 0.5 + 0.9 * v)
                    + 0.55 * math.sin(u * 19.0 + 2.1 * v + 1.2)
                    + 0.2 * math.sin(u * 37.0 + 3.0 * v)
                )
                * (0.45 + 0.75 * cai)
            )
            vs.append(((u - 0.5) * larg, y, (v - 1.0) * alt))
            uv.append((u, v))
    for j in range(m_y):
        for i in range(m_x):
            a = j * (m_x + 1) + i
            fs.append((a, a + 1, a + m_x + 2, a + m_x + 1))
    me = bpy.data.meshes.new("Bandeira")
    me.from_pydata(vs, [], fs)
    camada = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        camada.data[lp.index].uv = uv[lp.vertex_index]
    me.shade_smooth()
    pano = ligar("Bandeira", me, mat_imagem("BandeiraTex", caminho, ganho=0.66), pos, rot)
    # a vara de onde ela pende, com as amarras
    vara_m = mat_tabua("Vara", (0.46, 0.35, 0.22), escala=2.4)
    corda = mat_tecido("Amarra", (0.52, 0.46, 0.32), escala=1800)
    meia = larg / 2 + 0.10
    pecas = [
        torno(
            "Vara",
            [(0.0, -meia), (0.014, -meia), (0.014, meia), (0.0, meia)],
            vara_m,
            (0, 0, 0.006),
            (0, 90, 0),
            n=20,
            angulo=50,
        )
    ]
    for x in (-larg / 2 + 0.03, 0.0, larg / 2 - 0.03):
        for dx in (-0.006, 0.0, 0.006):
            pecas.append(toro("Amarra", 0.0155, 0.0028, corda, (x + dx, 0, 0.006), (0, 90, 0)))
    for o in pecas:
        o.parent = pano
    return pano


def folha_de_carta(pos, rot_z, larg=0.46, alt=0.34):
    """A carta tática do jogo sobre a mesa, com a dobra do meio e a ponta levantada."""
    n = 40
    vs, uv, fs = [], [], []
    for j in range(n + 1):
        v = j / n
        for i in range(n + 1):
            u = i / n
            z = 0.0016 + 0.0035 * abs(math.sin(u * math.pi * 2)) * 0.5
            z += 0.018 * max(0.0, u - 0.82) ** 1.4 * max(0.0, 0.3 - v) * 22
            vs.append(((u - 0.5) * larg, (v - 0.5) * alt, z))
            uv.append((0.08 + u * 0.72, 0.1 + v * 0.72))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            fs.append((a, a + 1, a + n + 2, a + n + 1))
    me = bpy.data.meshes.new("Carta")
    me.from_pydata(vs, [], fs)
    camada = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        camada.data[lp.index].uv = uv[lp.vertex_index]
    me.shade_smooth()
    return ligar("Carta", me, mat_imagem("CartaTex", CARTA, rug=0.72), pos, (0, 0, rot_z))


def lapis(pos, rot_z):
    corpo = mat("Lapis", (0.86, 0.60, 0.14), rug=0.4, forca=0.0)
    ponta = mat("Ponta", (0.80, 0.66, 0.46), rug=0.7, forca=0.0)
    grafite = mat("Grafite", (0.08, 0.08, 0.09), rug=0.35, forca=0.0)
    partes = [
        torno("Lapis", [(0.0, 0.0), (0.0038, 0.0), (0.0038, 0.15), (0.0, 0.15)], corpo, n=6),
        torno("Madeira", [(0.0, 0.15), (0.0038, 0.15), (0.0012, 0.166), (0.0, 0.166)], ponta, n=24),
        torno("Grafite", [(0.0, 0.1655), (0.0012, 0.1655), (0.0, 0.172)], grafite, n=16),
    ]
    return grupo(partes, pos, (0, 90, rot_z))


def krama(pos, rot_z, larg=0.40, prof=0.26):
    """O pano xadrez (khăn rằn), dobrado solto sobre a mesa."""
    m = bpy.data.materials.new("Krama")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    xadrez = nt.nodes.new("ShaderNodeTexChecker")
    xadrez.inputs["Scale"].default_value = 34.0
    xadrez.inputs["Color1"].default_value = (*K.lin((0.66, 0.62, 0.50)), 1.0)
    xadrez.inputs["Color2"].default_value = (*K.lin((0.13, 0.13, 0.15)), 1.0)
    nt.links.new(coord.outputs["Object"], xadrez.inputs["Vector"])
    nt.links.new(xadrez.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.92
    n = 90
    vs, fs = [], []
    for j in range(n + 1):
        v = j / n
        for i in range(n + 1):
            u = i / n
            z = 0.012 + 0.012 * math.sin(u * 7.3 + v * 3.1) * math.sin(v * 5.4 + 0.6)
            z += 0.016 * math.exp(-(((u - 0.6) * 5) ** 2)) * (0.6 + 0.4 * math.sin(v * 9.0))
            z += 0.006 * math.sin(u * 23.0 + v * 11.0)
            vs.append(((u - 0.5) * larg, (v - 0.5) * prof, max(0.0015, z)))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            fs.append((a, a + 1, a + n + 2, a + n + 1))
    me = bpy.data.meshes.new("Krama")
    me.from_pydata(vs, [], fs)
    me.shade_smooth()
    return ligar("Krama", me, m, pos, (0, 0, rot_z))


def sandalia(pos, rot_z, borracha, tira, lado=1):
    """Sandália de pneu (dép lốp): sola com banda de rodagem e as tiras de câmara."""
    pe = [
        (-0.125, -0.025),
        (-0.128, 0.015),
        (-0.105, 0.040),
        (-0.060, 0.046),
        (-0.005, 0.050),
        (0.052, 0.056),
        (0.094, 0.052),
        (0.122, 0.030),
        (0.130, 0.002),
        (0.118, -0.028),
        (0.082, -0.042),
        (0.030, -0.038),
        (-0.030, -0.034),
        (-0.090, -0.042),
    ]
    pe = [(x, y * lado) for x, y in pe]
    if lado < 0:
        pe = list(reversed(pe))
    objs = [prisma("Sola", pe, 0.014, borracha, (0, 0, 0), (0, 0, 0), 0.002)]
    for i in range(14):
        x = -0.11 + i * 0.0172
        meia = 0.034 if abs(x) < 0.09 else 0.022
        objs.append(
            bloco("Sulco", (0.0034, meia * 1.8, 0.001), (x, 0.005 * lado, 0.0142), tira, 0.0)
        )
    z = 0.014
    for y0, y1, x0, x1, topo in (
        (-0.036, 0.046, 0.050, 0.074, 0.026),
        (-0.034, 0.042, -0.074, -0.040, 0.034),
    ):
        pts = [
            (x0, y0 * lado, z),
            (x0 + (x1 - x0) * 0.2, (y0 + 0.012) * lado, z + topo * 0.7),
            ((x0 + x1) / 2, (y0 + y1) / 2 * lado, z + topo),
            (x1 - (x1 - x0) * 0.2, (y1 - 0.012) * lado, z + topo * 0.7),
            (x1, y1 * lado, z),
        ]
        t = tubo("Tira", pts, 0.0058, tira)
        t.data.bevel_depth = 0.0052
        objs.append(t)
    return grupo(objs, pos, (0, 0, rot_z))


def gradiente_esquerda(cam, forca=0.97):
    """Filtro degradê diante da lente: o lado esquerdo fica escuro e limpo para o texto."""
    m = bpy.data.materials.new("Degrade")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["UV"], sep.inputs[0])
    faixa = nt.nodes.new("ShaderNodeMapRange")
    faixa.interpolation_type = "SMOOTHSTEP"
    faixa.inputs["From Min"].default_value = 0.24
    faixa.inputs["From Max"].default_value = 0.56
    faixa.inputs["To Min"].default_value = forca
    faixa.inputs["To Max"].default_value = 0.0
    nt.links.new(sep.outputs["X"], faixa.inputs["Value"])
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    preto = nt.nodes.new("ShaderNodeEmission")
    preto.inputs["Color"].default_value = (0.006, 0.005, 0.004, 1.0)
    preto.inputs["Strength"].default_value = 1.0
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(faixa.outputs["Result"], mix.inputs[0])
    nt.links.new(transp.outputs[0], mix.inputs[1])
    nt.links.new(preto.outputs[0], mix.inputs[2])
    saida = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], saida.inputs["Surface"])
    dist = 0.25
    t = math.tan(math.atan(cam.data.sensor_width / 2 / cam.data.lens))
    meia_l = dist * t
    meia_a = meia_l * 9 / 16
    # o cartão passa do quadro (o desfoque da lente mostrava a borda dele); a UV 0..1 é o quadro
    k = 1.8
    me = bpy.data.meshes.new("Degrade")
    me.from_pydata(
        [
            (-meia_l * k, -meia_a * k, -dist),
            (meia_l * k, -meia_a * k, -dist),
            (meia_l * k, meia_a * k, -dist),
            (-meia_l * k, meia_a * k, -dist),
        ],
        [],
        [(0, 1, 2, 3)],
    )
    uv = me.uv_layers.new(name="UVMap")
    u0, u1 = 0.5 - k / 2, 0.5 + k / 2
    for lp, c in zip(me.loops, ((u0, u0), (u1, u0), (u1, u1), (u0, u1)), strict=True):
        uv.data[lp.index].uv = c
    o = ligar("Degrade", me, m)
    o.parent = cam
    o.visible_shadow = False
    o.visible_diffuse = False
    o.visible_glossy = False
    o.visible_transmission = False
    return o


def luz_de_tarde(cena, alvo: Vector):
    """Sol baixo e quente vindo da direita, céu fraco e frio enchendo as sombras."""
    d = bpy.data.lights.new("Sol", "SUN")
    d.energy = 6.0
    d.color = (1.0, 0.72, 0.44)
    d.angle = math.radians(5.0)
    s = bpy.data.objects.new("Sol", d)
    cena.collection.objects.link(s)
    pos = alvo + Vector((3.2, -1.5, 1.05))
    s.location = pos
    s.rotation_euler = (alvo - pos).to_track_quat("-Z", "Y").to_euler()
    L.luz_area("Rebate", alvo + Vector((-0.2, -1.8, 1.2)), alvo, 16, (1.0, 0.82, 0.62), 1.6)
    L.luz_area("Recorte", alvo + Vector((1.2, 1.2, 1.0)), alvo, 26, (1.0, 0.72, 0.46), 0.8)
    w = bpy.data.worlds.new("Tarde")
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.34, 0.40, 0.56, 1.0)
    bg.inputs["Strength"].default_value = 0.12
    cena.world = w


def fundo_sacos(cena):
    """Parede de sacos de areia do jogo, atrás da mesa."""
    o = importar(BL / "sandbag_wall" / "sandbag_wall.glb")
    lo, hi = C.caixa(o)
    meio = (lo + hi) / 2
    o.data.transform(Matrix.Translation(Vector((-meio[0], -meio[1], -lo[2]))))
    return o, hi - lo


def camera_time(cena, pos, alvo, lente=42.0, foco=None, fstop=3.2):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lente
    cd.sensor_width = 36.0
    cd.dof.use_dof = True
    cd.dof.aperture_fstop = fstop
    cam = bpy.data.objects.new("Cam", cd)
    cena.collection.objects.link(cam)
    cena.camera = cam
    cam.location = Vector(pos)
    d = Vector(alvo) - Vector(pos)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cd.dof.focus_distance = foco if foco else d.length
    bpy.context.view_layer.update()
    return cam


def posar(o, pos, rot):
    o.location = Vector(pos)
    o.rotation_mode = "XYZ"
    o.rotation_euler = [math.radians(a) for a in rot]
    return o


def base_no_zero(o):
    lo, hi = C.caixa(o)
    meio = (lo + hi) / 2
    o.data.transform(Matrix.Translation(Vector((-meio[0], -meio[1], -lo[2]))))
    return o


def assentar(o):
    """Põe a aba do capacete no z = 0: a jugular, que pende abaixo dela, passa sob a mesa."""
    n = len(o.data.vertices)
    co = np.empty(n * 3, np.float64)
    o.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    raio = np.hypot(co[:, 0], co[:, 1])
    aba = float(co[raio >= raio.max() * 0.82, 2].min())
    o.data.transform(Matrix.Translation(Vector((0.0, 0.0, -aba))))
    return o


CAM_TIME = ((-0.20, -2.05, 0.56), (0.36, 0.12, 0.24))


def cena_time_us(cena):
    tampo_de_tabuas((0.47, 0.35, 0.25))
    fundo_escuro()
    parede, dim = fundo_sacos(cena)
    k = 2.6 / max(float(dim[0]), 0.01)
    posar(parede, (0.35, 1.42, -0.02), (0, 0, 0))
    parede.scale = (k, k, k)
    bandeira_pano(BANDEIRAS / "bandeira_eua.png", 1.16, 0.70, (0.60, 0.94, 0.82), (3, 0, -3))
    capacete = assentar(base_no_zero(importar(FG / "capacete_m1_studs_fosco.glb")))
    posar(capacete, (0.52, 0.10, 0.0), (0, 0, 205))
    colete = base_no_zero(importar(FG / "colete_m1955_studs_fosco.glb"))
    posar(colete, (1.02, 0.36, 0.0), (0, 0, 205))
    m14 = arma_canonica("m14")
    posar(m14, (0.40, -0.36, 0.046), (90, 0, 11))
    folha_de_carta((0.16, -0.02, 0.0), 10)
    lapis((0.22, -0.07, 0.006), 24)
    return CAM_TIME


def cena_time_vc(cena):
    tampo_de_tabuas((0.38, 0.28, 0.19))
    fundo_escuro()
    cerca = importar(BL / "bamboo_fence" / "bamboo_fence.glb")
    lo, hi = C.caixa(cerca)
    k = 3.0 / max(float(hi[0] - lo[0]), float(hi[1] - lo[1]))
    meio = (lo + hi) / 2
    cerca.data.transform(Matrix.Translation(Vector((-meio[0], -meio[1], -lo[2]))))
    if float(hi[1] - lo[1]) > float(hi[0] - lo[0]):
        cerca.data.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
    posar(cerca, (0.35, 0.86, -0.04), (0, 0, 0))
    cerca.scale = (k, k, k * 0.92)
    bandeira_pano(BANDEIRAS / "bandeira_frente.png", 1.16, 0.70, (0.60, 0.68, 0.82), (3, 0, -3))
    capacete = assentar(base_no_zero(importar(FG / "capacete_fibra_studs_fosco.glb")))
    posar(capacete, (0.50, 0.14, 0.0), (0, 0, 160))
    t56 = arma_canonica("type56")
    posar(t56, (0.40, -0.38, 0.042), (90, 0, 10))
    krama((0.94, 0.24, 0.0), -14)
    borr = mat("Pneu", (0.10, 0.10, 0.10), rug=0.72, escala=800, forca=0.12)
    camara = mat("Camara", (0.16, 0.16, 0.16), rug=0.5, escala=1200, forca=0.04)
    sandalia((0.80, -0.08, 0.0), 28, borr, camara, 1)
    sandalia((0.98, -0.02, 0.0), 12, borr, camara, -1)
    return CAM_TIME


TIMES = {"us": cena_time_us, "vc": cena_time_vc}


def render_time(chave, amostras, teste, saida):
    C.cena_vazia()
    cena = bpy.context.scene
    larg, alt = (640, 360) if teste else (1280, 720)
    L.configurar(cena, larg, alt, amostras)
    acabar(cena)
    cena.render.film_transparent = False
    cena.render.image_settings.color_mode = "RGB"
    pos, alvo = TIMES[chave](cena)
    cam = camera_time(cena, pos, alvo)
    luz_de_tarde(cena, Vector(alvo))
    gradiente_esquerda(cam)
    saida.mkdir(parents=True, exist_ok=True)
    cena.render.filepath = str(saida / f"{chave}.png")
    bpy.ops.render.render(write_still=True)
    log("ok time", chave)


# ------------------------------------------------------------------ 5. prêmios (passe e ordens)
# Nenhum deles leva texto, número, insígnia nacional ou emblema protegido.
def imagem_de(nome, rgba):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(nome, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(rgba, np.float32).reshape(-1))
    img.update()
    img.pack()
    return img


def mat_de_imagem(nome, img, rug=0.8, alfa=False):
    m = bpy.data.materials.new(nome)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    no = nt.nodes.new("ShaderNodeTexImage")
    no.image = img
    no.extension = "EXTEND"
    nt.links.new(no.outputs["Color"], b.inputs["Base Color"])
    if alfa:
        nt.links.new(no.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = rug
    return m


def ruido2d(h, w, celulas, semente):
    """Ruído suave de 0 a 1 (grade sorteada com interpolação bilinear)."""
    g = np.random.default_rng(semente).random((celulas + 2, celulas + 2))
    y = np.linspace(0, celulas, h)
    x = np.linspace(0, celulas, w)
    yi, xi = np.floor(y).astype(int), np.floor(x).astype(int)
    fy, fx = (y - yi)[:, None], (x - xi)[None, :]
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = g[np.ix_(yi, xi)]
    b = g[np.ix_(yi, xi + 1)]
    c = g[np.ix_(yi + 1, xi)]
    d = g[np.ix_(yi + 1, xi + 1)]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def almofada(nome, dim, pos, material, rot=(0, 0, 0)):
    """Bloco de pano com as quinas bem redondas (a subdivisão de um cubo virava um ovo)."""
    o = bloco(nome, dim, pos, material, min(dim) * 0.26, rot)
    o.modifiers["Chanfro"].segments = 5
    return o


def fita_3d(nome, pts, larg, esp, material):
    """Tira chata que segue uma linha no plano XZ, com a largura em Y."""
    n = len(pts)
    vs, fs = [], []
    for i, (x, z) in enumerate(pts):
        ax, az = pts[max(i - 1, 0)]
        bx, bz = pts[min(i + 1, n - 1)]
        q = math.hypot(bx - ax, bz - az) or 1.0
        nx, nz = -(bz - az) / q, (bx - ax) / q
        for s, e in ((-1, 1), (1, 1), (1, -1), (-1, -1)):
            vs.append((x + nx * e * esp / 2, s * larg / 2, z + nz * e * esp / 2))
    for i in range(n - 1):
        for j in range(4):
            k = (j + 1) % 4
            fs.append((i * 4 + j, i * 4 + k, (i + 1) * 4 + k, (i + 1) * 4 + j))
    fs += [(0, 1, 2, 3), tuple((n - 1) * 4 + j for j in (3, 2, 1, 0))]
    me = bpy.data.meshes.new(nome)
    me.from_pydata(vs, [], fs)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(50))
    return ligar(nome, me, material)


def malha_estrela(R, r, h, base=0.14):
    """Estrela de cinco pontas facetada, com a aresta viva de cada braço."""
    vs = [(0.0, 0.0, h)]
    for z in (h * base, 0.0):
        for i in range(10):
            q = R if i % 2 == 0 else r
            a = math.pi / 2 + i * math.pi / 5
            vs.append((q * math.cos(a), q * math.sin(a), z))
    fs = [(0, 1 + i, 1 + (i + 1) % 10) for i in range(10)]
    fs += [(1 + i, 11 + i, 11 + (i + 1) % 10, 1 + (i + 1) % 10) for i in range(10)]
    fs.append(tuple(11 + i for i in reversed(range(10))))
    me = bpy.data.meshes.new("Estrela")
    me.from_pydata(vs, [], fs)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    return me


def textura_cedula():
    """Cédula genérica: guilhochê, moldura e medalhão, sem letra nem número."""
    h, w = 216, 512
    y, x = np.mgrid[0:h, 0:w]
    u, v = (x + 0.5) / w, (y + 0.5) / h
    base = np.stack([0.60 + 0 * u, 0.66 + 0 * u, 0.50 + 0 * u], axis=-1)
    linhas = 0.5 + 0.5 * np.sin(u * 150 + 5 * np.sin(v * 18))
    linhas2 = 0.5 + 0.5 * np.sin(v * 110 + 4 * np.sin(u * 21))
    tinta = np.array([0.17, 0.27, 0.20])
    m = 0.20 * linhas * linhas2
    bx, by = np.minimum(u, 1 - u), np.minimum(v, 1 - v) * h / w
    m = np.maximum(m, 0.82 * ((bx > 0.022) & (bx < 0.034) | (by > 0.022) & (by < 0.030)))
    d = np.hypot((u - 0.5) * w / h, v - 0.5)
    m = np.where(d < 0.33, 0.10, m)
    m = np.maximum(m, 0.85 * ((d > 0.31) & (d < 0.335)))
    rad_ = 0.5 + 0.5 * np.cos(np.arctan2(v - 0.5, (u - 0.5) * w / h) * 24)
    m = np.maximum(m, 0.55 * (d < 0.20) * rad_)
    for cx in (0.13, 0.87):
        dc = np.hypot((u - cx) * w / h, v - 0.5)
        m = np.maximum(m, 0.7 * ((dc > 0.13) & (dc < 0.155)))
        m = np.maximum(m, 0.4 * (dc < 0.09))
    cor = base * (1 - m[..., None]) + tinta * m[..., None]
    cor *= (0.92 + 0.12 * ruido2d(h, w, 14, 5))[..., None]
    return np.dstack([np.clip(cor, 0, 1), np.ones((h, w))])


def textura_carta():
    """Ás de espadas gasto, só com os naipes: papel amarelado, vincos e tinta falhada."""
    h, w = 616, 440
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)

    def naipe(cx, cy, s, vira=False):
        nx, ny = (x - cx) / s, (y - cy) / s
        if vira:
            ny = -ny
        X, Y = nx * 1.12, -(ny - 0.14) * 1.12
        coracao = (X * X + Y * Y - 1) ** 3 - X * X * Y**3 <= 0
        t = np.clip((-0.28 - ny) / 0.86, 0.0, 1.0)
        haste = (ny < -0.28) & (ny > -1.14) & (np.abs(nx) < 0.05 + 0.30 * t**2.2)
        return coracao | haste

    tinta = naipe(w / 2, h / 2, 118) | naipe(52, h - 62, 25) | naipe(w - 52, 62, 25, True)
    falha = ruido2d(h, w, 90, 3) * 0.6 + ruido2d(h, w, 22, 4) * 0.4
    papel = np.stack([0.84 + 0 * x, 0.78 + 0 * x, 0.61 + 0 * x], axis=-1)
    mancha = ruido2d(h, w, 7, 8)
    papel = papel * (0.70 + 0.42 * mancha)[..., None]
    borda = np.minimum.reduce([x, w - 1 - x, y, h - 1 - y]) / 46
    papel = papel * (0.62 + 0.38 * np.clip(borda, 0, 1))[..., None]
    for a, b, c in ((0.82, 0.57, -300.0), (-0.42, 0.91, -330.0), (0.98, -0.2, -250.0)):
        vinco = np.exp(-(((a * x + b * y + c) / 1.5) ** 2))
        papel = papel * (1 + 0.20 * vinco)[..., None]
    k = (tinta & (falha < 0.82))[..., None]
    cor = np.where(k, np.array([0.075, 0.07, 0.07]), papel)
    raio = 34.0
    qx = np.maximum(np.abs(x - (w - 1) / 2) - ((w - 1) / 2 - raio), 0.0)
    qy = np.maximum(np.abs(y - (h - 1) / 2) - ((h - 1) / 2 - raio), 0.0)
    alfa = np.clip(raio - np.hypot(qx, qy) + 0.5, 0.0, 1.0)
    return np.dstack([np.clip(cor, 0, 1), alfa])


def pr_creditos(p):
    objs = []
    moeda = malha_torno(
        "Moeda",
        [
            (0.0, 0.0),
            (0.0128, 0.0),
            (0.0132, 0.0003),
            (0.0132, 0.0022),
            (0.0128, 0.0025),
            (0.0116, 0.0025),
            (0.0112, 0.0021),
            (0.0072, 0.0021),
            (0.0070, 0.0024),
            (0.0064, 0.0024),
            (0.0062, 0.0021),
            (0.0, 0.0021),
        ],
        n=120,
        deforma=lambda x, y, z: (
            (x * (1 + 0.012 * math.cos(72 * math.atan2(y, x))) if math.hypot(x, y) > 0.0130 else x),
            (y * (1 + 0.012 * math.cos(72 * math.atan2(y, x))) if math.hypot(x, y) > 0.0130 else y),
            z,
        ),
        angulo=50,
    )
    moeda.materials.append(p["latao"])
    estrela = malha_estrela(0.0058, 0.0024, 0.0007)
    estrela.materials.append(p["latao"])
    random.seed(11)
    # moedas grandes de propósito: na escala real, viravam pontinhos ao lado do maço
    km = 1.8
    passo = 0.00252 * km
    for cx, cy, n in ((0.040, 0.020, 13), (0.083, -0.012, 8), (0.030, -0.040, 4)):
        for i in range(n):
            folga = 0.0016 * km
            pos = (
                cx + random.uniform(-folga, folga),
                cy + random.uniform(-folga, folga),
                i * passo,
            )
            giro = random.uniform(0, 360)
            objs.append(ligar("Moeda", moeda, None, pos, (0, 0, giro), km))
        objs.append(
            ligar("Marca", estrela, None, (pos[0], pos[1], n * passo - 0.0007), (0, 0, giro), km)
        )
    objs.append(ligar("Moeda", moeda, None, (0.112, 0.030, 0.0212), (0, 62, 24), km))
    img = imagem_de("Cedula", textura_cedula())
    face = mat_de_imagem("Cedula", img, rug=0.72)
    folhas = mat("Folhas", (0.66, 0.68, 0.54), rug=0.82, forca=0.0)
    cinta = mat_tecido("Cinta", (0.62, 0.50, 0.33), escala=1800)
    L_, A_, H_ = 0.128, 0.056, 0.019
    maco = [bloco("Maco", (L_, A_, H_), (0, 0, H_ / 2), folhas, 0.0005)]
    for i in range(1, 9):
        maco.append(
            bloco(
                "Fresta", (L_ + 0.0001, A_ + 0.0001, 0.00016), (0, 0, H_ * i / 9), p["preto"], 0.0
            )
        )
    me = bpy.data.meshes.new("Topo")
    s, t = L_ / 2, A_ / 2
    me.from_pydata([(-s, -t, 0), (s, -t, 0), (s, t, 0), (-s, t, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for lp, c in zip(me.loops, ((0, 0), (1, 0), (1, 1), (0, 1)), strict=True):
        uv.data[lp.index].uv = c
    maco.append(ligar("Topo", me, face, (0, 0, H_ + 0.00012)))
    maco.append(bloco("Cinta", (0.024, A_ + 0.0014, H_ + 0.0012), (0, 0, H_ / 2), cinta, 0.0005))
    objs += grupo(maco, (-0.060, 0.016, 0.0), (0, 0, 16))
    return objs


def pr_reforco(p):
    W, D, H = 0.26, 0.19, 0.14
    tabua = mat_tabua("TabuaCaixa", (0.58, 0.46, 0.26), escala=1.8)
    objs = []
    for i in range(4):
        z = 0.018 + i * (H - 0.008) / 4
        objs.append(
            bloco("RipaF", (W, 0.010, H / 4 - 0.003), (0, -D / 2, z + 0.012), tabua, 0.0014)
        )
        objs.append(bloco("RipaT", (W, 0.010, H / 4 - 0.003), (0, D / 2, z + 0.012), tabua, 0.0014))
        objs.append(
            bloco(
                "RipaL",
                (0.010, D, H / 4 - 0.003),
                (W / 2, 0, z + 0.012),
                tabua,
                0.0014,
            )
        )
        objs.append(
            bloco("RipaE", (0.010, D, H / 4 - 0.003), (-W / 2, 0, z + 0.012), tabua, 0.0014)
        )
    objs.append(bloco("Miolo", (W - 0.01, D - 0.01, H), (0, 0, H / 2 + 0.006), p["preto"], 0.0))
    for j in range(5):
        y = -D / 2 + 0.018 + j * (D - 0.036) / 4
        objs.append(
            bloco(
                "Tampa",
                (W + 0.016, (D + 0.012) / 5 - 0.0024, 0.012),
                (0, y, H + 0.018),
                tabua,
                0.0015,
            )
        )
    for x in (-1, 1):
        objs.append(
            bloco("Trava", (0.024, D + 0.018, 0.015), (x * 0.098, 0, H + 0.0285), tabua, 0.0018)
        )
    aco = p["aco"]
    for x in (-1, 1):
        for y in (-1, 1):
            for z in (0.022, H + 0.008):
                objs.append(
                    bloco(
                        "Canto",
                        (0.030, 0.030, 0.032),
                        (x * (W / 2 + 0.0015), y * (D / 2 + 0.0015), z),
                        aco,
                        0.0016,
                    )
                )
    for x in (-1, 1):
        objs.append(
            toro("Argola", 0.020, 0.0023, aco, (x * (W / 2 + 0.008), 0, H * 0.58), (90, 0, 90))
        )

    def divisa(y0):
        w, a, g = 0.066, 0.032, 0.019
        return [
            (-w, y0 - a),
            (0.0, y0 + a),
            (w, y0 - a),
            (w, y0 - a - g),
            (0.0, y0 + a - g * 1.25),
            (-w, y0 - a - g),
        ]

    brilho = mat("LataoPolido", (0.92, 0.72, 0.34), metal=1.0, rug=0.16, escala=1400, forca=0.006)
    z = H + 0.0362
    for y0 in (0.052, 0.018, -0.016):
        objs.append(prisma("Divisa", divisa(y0), 0.0034, brilho, (0, 0, z), (0, 0, 0), 0.0009))
    return objs


def mat_vinil():
    m = mat("Vinil", (0.012, 0.012, 0.014), rug=0.30, forca=0.0)
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    # reflexo baixo: com o normal, o painel de luz deixava o disco cinza
    b.inputs["Specular IOR Level"].default_value = 0.22
    coord = nt.nodes.new("ShaderNodeTexCoord")
    ondas = nt.nodes.new("ShaderNodeTexWave")
    ondas.wave_type = "RINGS"
    ondas.rings_direction = "Z"
    ondas.inputs["Scale"].default_value = 6.0
    ondas.inputs["Distortion"].default_value = 0.0
    ondas.inputs["Detail"].default_value = 0.0
    nt.links.new(coord.outputs["Object"], ondas.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.10
    bump.inputs["Distance"].default_value = 0.0002
    nt.links.new(ondas.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Anisotropic"].default_value = 0.88
    tg = nt.nodes.new("ShaderNodeTangent")
    tg.direction_type = "RADIAL"
    tg.axis = "Z"
    nt.links.new(tg.outputs["Tangent"], b.inputs["Tangent"])
    return m


def pr_disco(p):
    lado = 0.315
    papelao = mat("Papelao", (0.62, 0.50, 0.34), rug=0.84, escala=1100, forca=0.06)
    objs = [
        bloco("Frente", (lado, lado, 0.0012), (0, lado / 2, 0.0024), papelao, 0.0004),
        bloco("Verso", (lado, lado, 0.0012), (0, lado / 2, -0.0024), papelao, 0.0004),
        bloco("Lombada", (0.003, lado, 0.006), (-lado / 2, lado / 2, 0), papelao, 0.0006),
        bloco("Base", (lado, 0.003, 0.006), (0, 0.0015, 0), papelao, 0.0006),
        bloco("Topo", (lado, 0.003, 0.006), (0, lado - 0.0015, 0), papelao, 0.0006),
    ]
    cx, cy = 0.160, lado / 2
    disco = torno(
        "Disco",
        [
            (0.0037, -0.0007),
            (0.1500, -0.0007),
            (0.1512, -0.0003),
            (0.1512, 0.0003),
            (0.1500, 0.0007),
            (0.0037, 0.0007),
            (0.0037, -0.0007),
        ],
        mat_vinil(),
        (cx, cy, 0.0),
        n=192,
        angulo=60,
    )
    selo = mat("Selo", (0.72, 0.60, 0.34), rug=0.5, forca=0.0)
    objs += [
        disco,
        torno(
            "Selo",
            [(0.0037, 0.0007), (0.050, 0.0007), (0.050, 0.00085), (0.0037, 0.00085)],
            selo,
            (cx, cy, 0.0),
            n=96,
        ),
        torno(
            "Selo2",
            [(0.0037, -0.00085), (0.050, -0.00085), (0.050, -0.0007), (0.0037, -0.0007)],
            selo,
            (cx, cy, 0.0),
            n=96,
        ),
        toro("Friso", 0.040, 0.0005, p["preto"], (cx, cy, 0.00088)),
    ]
    return grupo(objs, (-0.02, 0.0, 0.003), (74, 0, 0))


def pr_gesto(p):
    latao = mat("LataoApito", (0.90, 0.71, 0.36), metal=1.0, rug=0.2, escala=1500, forca=0.01)
    corda = mat_tecido("Cordao", (0.42, 0.42, 0.25), escala=3200)
    R = 0.0135
    z = R + 0.0005
    objs = [
        torno(
            "Camara",
            [
                (0.0, -0.0125),
                (R * 0.92, -0.0125),
                (R, -0.0115),
                (R, 0.0115),
                (R * 0.92, 0.0125),
                (0.0, 0.0125),
            ],
            latao,
            (0, 0, z),
            (90, 0, 0),
            n=72,
        ),
        torno(
            "Tampa",
            [(0.0, -0.0132), (0.0088, -0.0132), (0.0088, -0.0124), (0.0, -0.0124)],
            p["aco"],
            (0, 0, z),
            (90, 0, 0),
            n=40,
        ),
    ]
    boca = [(0.002, R), (0.046, R * 0.86), (0.048, R * 0.60), (0.046, R * 0.42), (0.008, R * 0.28)]
    objs.append(prisma("Bocal", boca, 0.0154, latao, (0, 0.0077, z - R), (90, 0, 0), 0.0012))
    objs.append(
        bloco("Janela", (0.0098, 0.0118, 0.0007), (0.0028, 0, z + R * 0.985), p["preto"], 0)
    )
    objs.append(bloco("Labio", (0.0024, 0.0132, 0.0024), (0.0088, 0, z + R * 0.98), latao, 0.0006))
    objs.append(toro("Olhal", 0.0052, 0.0011, latao, (-R - 0.0040, 0, z), (90, 0, 0)))
    objs.append(toro("Argola", 0.0092, 0.0010, p["aco"], (-R - 0.0126, 0, z - 0.002), (8, 0, 0)))
    pts = []
    for i in range(46):
        t = i / 45
        a = t * 2 * math.pi * 1.04 + 0.2
        q = 0.034 + 0.010 * math.sin(a * 2.0 + 0.7)
        pts.append(
            (
                -0.056 + q * math.cos(a) * 1.15,
                0.006 + q * math.sin(a) * 0.86,
                0.0026 + 0.0022 * max(0, math.sin(a * 3.0)),
            )
        )
    pts[0] = (-R - 0.0212, 0.0, z - 0.003)
    pts[-1] = (-R - 0.0212, 0.0015, z - 0.003)
    objs.append(tubo("Cordao", pts, 0.0021, corda, resolucao=8))
    objs.append(toro("No", 0.0034, 0.0024, corda, (-R - 0.0228, 0.0006, z - 0.003), (0, 90, 0)))
    return grupo(objs, (0.02, 0, 0), (0, 0, 16))


def pr_cartao(p):
    cap = base_no_zero(importar(FG / "capacete_m1_studs_fosco.glb"))
    arvore = C.bvh_de(cap)

    def raio_em(theta, z):
        o = Vector((0.5 * math.cos(theta), 0.5 * math.sin(theta), z))
        d = Vector((-math.cos(theta), -math.sin(theta), 0.0))
        hit = arvore.ray_cast(o, d, 1.0)[0]
        return math.hypot(hit.x, hit.y) if hit is not None else None

    lo, hi = C.caixa(cap)
    alt = float(hi[2] - lo[2])
    z0 = alt * 0.40
    faixa_h = 0.026
    verde = mat_tecido("Tira", (0.17, 0.19, 0.12), rug=0.88, escala=1500)
    n, vs, fs = 180, [], []
    for i in range(n):
        t = 2 * math.pi * i / n
        for dz in (-faixa_h / 2, -faixa_h / 6, faixa_h / 6, faixa_h / 2):
            r = raio_em(t, z0 + dz) or 0.13
            vs.append(((r + 0.0026) * math.cos(t), (r + 0.0026) * math.sin(t), z0 + dz))
    for i in range(n):
        j = (i + 1) % n
        for k in range(3):
            fs.append((i * 4 + k, j * 4 + k, j * 4 + k + 1, i * 4 + k + 1))
    me = bpy.data.meshes.new("Tira")
    me.from_pydata(vs, [], fs)
    me.shade_smooth()
    tira = ligar("Tira", me, verde)
    sol = tira.modifiers.new("Espessura", "SOLIDIFY")
    sol.thickness = 0.0016
    th0 = math.atan2(-1.0, 0.38)
    img = imagem_de("Carta", textura_carta())
    carta_m = mat_de_imagem("CartaAs", img, rug=0.58, alfa=True)
    # um pouco maior que a carta real, para o naipe ler no cartão pequeno da interface
    cl, ca = 0.088, 0.1232
    giro = math.radians(-11)
    r_ref = raio_em(th0, z0 + 0.03) or 0.13
    gx, gy = 26, 36
    vs, fs, uvs = [], [], []
    for j in range(gy + 1):
        v = j / gy
        for i in range(gx + 1):
            u = i / gx
            sx, sy = (u - 0.5) * cl, (v - 0.5) * ca
            qx = sx * math.cos(giro) - sy * math.sin(giro)
            qy = sx * math.sin(giro) + sy * math.cos(giro)
            t = th0 + qx / r_ref
            z = z0 + 0.060 + qy  # o pé da carta fica todo atrás da tira
            r = raio_em(t, z) or r_ref
            folga = 0.0013 + 0.0016 * max(0.0, v - 0.55)
            vs.append(((r + folga) * math.cos(t), (r + folga) * math.sin(t), z))
            uvs.append((u, v))
    for j in range(gy):
        for i in range(gx):
            a = j * (gx + 1) + i
            fs.append((a, a + 1, a + gx + 2, a + gx + 1))
    mc = bpy.data.meshes.new("Carta")
    mc.from_pydata(vs, [], fs)
    uvl = mc.uv_layers.new(name="UVMap")
    for lp in mc.loops:
        uvl.data[lp.index].uv = uvs[lp.vertex_index]
    mc.shade_smooth()
    carta = ligar("Carta", mc, carta_m)
    return [cap, tira, carta]


def pr_estrelas(p):
    brilho = mat("LataoEspelho", (0.95, 0.75, 0.36), metal=1.0, rug=0.13, escala=1800, forca=0.004)
    objs = []
    for R, pos, rot in (
        (0.074, (0.0, 0.016, 0.092), (72, 0, 8)),
        (0.052, (-0.116, -0.022, 0.064), (70, 8, -16)),
        (0.052, (0.118, -0.022, 0.064), (70, -8, 26)),
    ):
        me = malha_estrela(R, R * 0.42, R * 0.26)
        me.materials.append(brilho)
        o = ligar("Estrela", me, None, pos, rot)
        b = o.modifiers.new("Chanfro", "BEVEL")
        b.width = R * 0.012
        b.segments = 2
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(18)
        objs.append(o)
    return objs


def pr_bandeira(p):
    base = importar(BL / "sandbags" / "sandbags.glb")
    lo, hi = C.caixa(base)
    if float(hi[1] - lo[1]) > float(hi[0] - lo[0]):
        base.data.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
    base_no_zero(base)
    lo, hi = C.caixa(base)
    k = 1.30 / float(hi[0] - lo[0])
    base.scale = (k, k, k)
    topo = float(hi[2] - lo[2]) * k
    madeira = mat_tabua("Mastro", (0.50, 0.37, 0.23), escala=2.2)
    h = 1.36
    mastro = torno(
        "Mastro",
        [(0.0, 0.0), (0.026, 0.0), (0.024, h - 0.02), (0.016, h), (0.0, h + 0.004)],
        madeira,
        (-0.30, 0.0, topo * 0.45),
        n=28,
        angulo=50,
    )
    z_topo = topo * 0.45 + h - 0.05
    FL, FA = 0.92, 0.60
    gx, gy = 320, 210
    falha = ruido2d(gy + 1, gx + 1, 16, 21) * 0.55 + ruido2d(gy + 1, gx + 1, 54, 22) * 0.45
    fino = ruido2d(gy + 1, gx + 1, 120, 23)
    vs, uvs = [], []
    for j in range(gy + 1):
        v = j / gy
        for i in range(gx + 1):
            u = i / gx
            d = 0.055 * math.sin(u * 8.2 + 1.0 + v * 1.3) * (0.15 + u)
            d += 0.020 * math.sin(u * 19.0 + v * 4.0)
            cai = 0.13 * u**1.5 * (1 - v * 0.5)
            vs.append((-0.280 + u * FL * 0.97, d, z_topo - FA + v * FA - cai))
            uvs.append((u, v))
    fs = []
    for j in range(gy):
        for i in range(gx):
            u, v = (i + 0.5) / gx, (j + 0.5) / gy
            q = falha[j, i] + 0.12 * fino[j, i]
            rasgo = u + (q - 0.55) * 0.44 > 0.86
            baixo = v < 0.05 + 0.23 * u**2 * (q + 0.35) and u > 0.2
            furo = (u - 0.56) ** 2 / 0.0030 + (v - 0.42) ** 2 / 0.0052 < 0.6 + 2.4 * (q - 0.5)
            furo2 = (u - 0.30) ** 2 / 0.0009 + (v - 0.70) ** 2 / 0.0014 < 0.5 + 2.0 * (q - 0.5)
            if not (rasgo or baixo or furo or furo2):
                a = j * (gx + 1) + i
                fs.append((a, a + 1, a + gx + 2, a + gx + 1))
    me = bpy.data.meshes.new("Pano")
    me.from_pydata(vs, [], fs)
    uvl = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        uvl.data[lp.index].uv = uvs[lp.vertex_index]
    me.shade_smooth()
    tex = ruido2d(256, 384, 9, 31)[..., None]
    cor = np.array([0.40, 0.44, 0.24]) * (0.70 + 0.48 * tex)
    borda_suja = ruido2d(256, 384, 40, 32)[..., None]
    cor = cor * (0.86 + 0.24 * borda_suja)
    pano_m = mat_de_imagem(
        "Pano",
        imagem_de("PanoTex", np.dstack([np.clip(cor, 0, 1), np.ones((256, 384))])),
        rug=0.9,
    )
    pano = ligar("Pano", me, pano_m)
    sol = pano.modifiers.new("Espessura", "SOLIDIFY")
    sol.thickness = 0.0022
    return [base, mastro, pano]


def pr_medalha(_p):
    """Desenho próprio: rosa dos ventos em coroa de louros sobre uma fita oliva e ferrugem."""
    bronze = E.mat_metal("Bronze", (168, 112, 66), 0.3)
    claro = E.mat_metal("BronzeClaro", (214, 160, 108), 0.2)
    escuro = E.mat_esmalte("Fundo", (44, 34, 24))
    objs = [E.curva("Disco", [E.circulo(0, 0, 1.0, 120)], bronze, 0.0, ext=0.05, bev=0.024)]
    aro = [E.circulo(0, 0, 0.98, 120), E.circulo(0, 0, 0.84, 120)]
    objs.append(E.curva("Aro", aro, claro, 0.08, ext=0.012, bev=0.012))
    objs.append(E.curva("Campo", [E.circulo(0, 0, 0.85, 96)], escuro, 0.074, ext=0.004, bev=0.0))
    for i in range(44):
        a = i * 360 / 44
        c = (0.91 * math.cos(math.radians(a)), 0.91 * math.sin(math.radians(a)))
        objs.append(
            E.curva(
                "Conta", [E.circulo(c[0], c[1], 0.034, 10)], bronze, 0.104, ext=0.004, bev=0.012
            )
        )
    for n, poly in enumerate(E.louro(0.70, 9)):
        objs.append(E.curva("Louro", [poly], claro, 0.092 + n * 0.0008, ext=0.008, bev=0.006))
    mats = {"m": claro, "c": bronze, "e": escuro, "b": claro}
    for polys, qual, dz in E.s_bussola():
        polys = [[(x * 0.84, y * 0.84) for x, y in q] for q in polys]
        for n, g in enumerate(E.grupos(polys)):
            objs.append(E.curva("Rosa", g, mats[qual], 0.106 + dz + n * 0.0012))
    objs.append(toro("Olhal", 0.10, 0.032, claro, (0, 1.06, 0.05), (0, 90, 0)))
    objs.append(toro("Argola", 0.17, 0.032, bronze, (0, 1.27, 0.05), (0, 0, 0)))
    objs.append(bloco("Barra", (1.72, 0.14, 0.09), (0, 3.48, 0.06), claro, 0.03))
    objs.append(bloco("Passador", (1.60, 0.08, 0.06), (0, 1.43, 0.05), bronze, 0.022))
    h, w = 64, 256
    u = (np.arange(w) + 0.5) / w
    cores = np.zeros((w, 3))
    for a, b, c in (
        (0.0, 1.0, (0.24, 0.27, 0.13)),
        (0.10, 0.16, (0.78, 0.70, 0.48)),
        (0.84, 0.90, (0.78, 0.70, 0.48)),
        (0.30, 0.70, (0.45, 0.17, 0.09)),
        (0.46, 0.54, (0.78, 0.70, 0.48)),
    ):
        cores[(u >= a) & (u < b)] = c
    tex = np.repeat(cores[None, :, :], h, axis=0)
    tex = tex * (0.86 + 0.2 * ruido2d(h, w, 40, 41))[..., None]
    fita_m = mat_de_imagem(
        "Fita", imagem_de("FitaTex", np.dstack([np.clip(tex, 0, 1), np.ones((h, w))])), 0.58
    )
    gx, gy = 40, 90
    vs, fs, uvs = [], [], []
    for j in range(gy + 1):
        v = j / gy
        for i in range(gx + 1):
            q = i / gx
            x = (q - 0.5) * 1.62
            y = 1.43 + v * 2.05
            z = 0.04 + 0.026 * math.sin(q * 11.0 + v * 2.0) * (0.3 + v) + 0.018 * math.sin(v * 13)
            vs.append((x, y, z))
            uvs.append((q, v))
    for j in range(gy):
        for i in range(gx):
            a = j * (gx + 1) + i
            fs.append((a, a + 1, a + gx + 2, a + gx + 1))
    me = bpy.data.meshes.new("Fita")
    me.from_pydata(vs, [], fs)
    uvl = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        uvl.data[lp.index].uv = uvs[lp.vertex_index]
    me.shade_smooth()
    objs.append(ligar("Fita", me, fita_m))
    return grupo(objs, (0, -1.2, 0.04), (0, 0, -7))


def pr_maleta(p):
    lona = mat_tecido("LonaBolsa", (0.33, 0.36, 0.20), escala=820)
    lona2 = mat_tecido("LonaEscura", (0.25, 0.28, 0.15), escala=820)
    branco = mat("Quadrado", (0.90, 0.89, 0.83), rug=0.74, escala=900, forca=0.02)
    W, D, H = 0.31, 0.15, 0.22
    objs = [
        almofada("Corpo", (W, D, H), (0, 0, H / 2), lona),
        almofada("Aba", (W + 0.012, D + 0.016, 0.046), (0, 0, H + 0.008), lona2),
        almofada("Frente", (W - 0.014, 0.018, 0.126), (0, -D / 2 - 0.004, H - 0.056), lona2),
        almofada("BolsoE", (0.066, 0.052, 0.120), (W / 2 + 0.018, 0, 0.078), lona),
        almofada("BolsoEA", (0.070, 0.056, 0.030), (W / 2 + 0.018, 0, 0.138), lona2),
        bloco("Quadrado", (0.088, 0.0016, 0.088), (0, -D / 2 - 0.0142, H - 0.056), branco, 0.0005),
    ]
    aco = p["aco"]
    for x in (-0.106, 0.106):
        objs.append(
            bloco("Correia", (0.024, 0.004, 0.17), (x, -D / 2 - 0.0150, H - 0.046), lona, 0.0009)
        )
        objs.append(
            bloco("Fivela", (0.032, 0.005, 0.026), (x, -D / 2 - 0.0172, 0.080), aco, 0.0012)
        )
        objs.append(
            bloco("Lingueta", (0.0042, 0.006, 0.030), (x, -D / 2 - 0.0194, 0.080), lona2, 0.0006)
        )
    for i in range(30):
        x = -W / 2 + 0.02 + i * (W - 0.04) / 29
        objs.append(
            bloco("Ponto", (0.0058, 0.001, 0.0011), (x, -D / 2 - 0.0132, H - 0.116), p["branco"], 0)
        )
    pts = [
        (-0.066, 0.0, H + 0.024),
        (-0.060, 0.0, H + 0.058),
        (-0.030, 0.0, H + 0.076),
        (0.030, 0.0, H + 0.076),
        (0.060, 0.0, H + 0.058),
        (0.066, 0.0, H + 0.024),
    ]
    alca = tubo("Alca", pts, 0.0072, lona2)
    alca.data.bevel_resolution = 2
    objs.append(alca)
    for x in (-0.066, 0.066):
        objs.append(toro("Argola", 0.0098, 0.0017, aco, (x, 0, H + 0.030), (90, 0, 0)))
    return objs


def pr_relogio(p):
    aco = mat("AcoRelogio", (0.72, 0.72, 0.70), metal=1.0, rug=0.24, escala=2400, forca=0.006)
    lona = mat_tecido("Pulseira", (0.31, 0.33, 0.18), escala=2400)
    preto = mat("Mostrador", (0.025, 0.026, 0.028), rug=0.46, forca=0.0)
    luz = mat("Tritio", (0.86, 0.87, 0.70), rug=0.45, forca=0.0)
    vidro = bpy.data.materials.new("Cristal")
    vidro.use_nodes = True
    bv = vidro.node_tree.nodes.get("Principled BSDF")
    # cristal por alfa: com vidro de verdade, o reflexo do painel apagava o mostrador
    bv.inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1.0)
    bv.inputs["Roughness"].default_value = 0.05
    bv.inputs["Alpha"].default_value = 0.10
    rx, rz = 0.040, 0.034
    z_c = rz + 0.002
    pts = []
    for i in range(72):
        a = math.radians(70 - i * (320 / 71))
        pts.append((rx * math.cos(a), z_c + rz * math.sin(a)))
    objs = [fita_3d("Pulseira", pts, 0.018, 0.0017, lona)]
    z = z_c + rz + 0.0005
    caixa_p = [
        (0.0, 0.0),
        (0.0172, 0.0),
        (0.0192, 0.0014),
        (0.0196, 0.0048),
        (0.0186, 0.0072),
        (0.0176, 0.0078),
        (0.0176, 0.0090),
        (0.0162, 0.0096),
        (0.0150, 0.0086),
        (0.0150, 0.0070),
        (0.0, 0.0070),
    ]
    objs.append(torno("Caixa", caixa_p, aco, (0, 0, z), n=96, angulo=38))
    objs.append(
        torno(
            "Mostrador",
            [(0.0, 0.0074), (0.0152, 0.0074), (0.0152, 0.0078), (0.0, 0.0078)],
            preto,
            (0, 0, z),
            n=72,
        )
    )
    for i in range(12):
        a = math.radians(90 - i * 30)
        grande = i % 3 == 0
        c = 0.0126 if grande else 0.0132
        objs.append(
            bloco(
                "Marca",
                (0.0040 if grande else 0.0026, 0.0014 if grande else 0.0009, 0.00035),
                (c * math.cos(a), c * math.sin(a), z + 0.0080),
                luz,
                0,
                (0, 0, math.degrees(a)),
            )
        )
    for i in range(60):
        if i % 5 == 0:
            continue
        a = math.radians(90 - i * 6)
        objs.append(
            bloco(
                "Min",
                (0.0011, 0.00028, 0.0002),
                (0.0145 * math.cos(a), 0.0145 * math.sin(a), z + 0.0079),
                luz,
                0,
                (0, 0, math.degrees(a)),
            )
        )
    for ang, comp, larg, dz in ((128, 0.0074, 0.0015, 0.0084), (28, 0.0112, 0.0010, 0.0087)):
        a = math.radians(ang)
        objs.append(
            bloco(
                "Ponteiro",
                (comp, larg, 0.0003),
                (comp / 2 * math.cos(a), comp / 2 * math.sin(a), z + dz),
                luz,
                0,
                (0, 0, ang),
            )
        )
    a = math.radians(-62)
    objs.append(
        bloco(
            "Segundos",
            (0.0138, 0.00028, 0.00018),
            (0.0048 * math.cos(a), 0.0048 * math.sin(a), z + 0.0090),
            mat("Vermelho", (0.74, 0.16, 0.10), rug=0.4, forca=0.0),
            0,
            (0, 0, -62),
        )
    )
    objs.append(
        torno(
            "Eixo",
            [(0.0, 0.0078), (0.0011, 0.0078), (0.0011, 0.0093), (0.0, 0.0095)],
            aco,
            (0, 0, z),
            n=20,
        )
    )
    objs.append(
        torno(
            "Cristal",
            [(0.0, 0.0094), (0.0150, 0.0094), (0.0150, 0.0104), (0.009, 0.0114), (0.0, 0.0117)],
            vidro,
            (0, 0, z),
            n=72,
            angulo=55,
        )
    )
    objs.append(
        torno(
            "Coroa",
            [(0.0, 0.0), (0.0030, 0.0), (0.0030, 0.0048), (0.0, 0.0048)],
            aco,
            (0.0190, 0, z + 0.0040),
            (0, 90, 0),
            n=20,
        )
    )
    for lado in (-1, 1):
        for y in (-0.0098, 0.0098):
            objs.append(
                bloco("Alca", (0.0074, 0.0024, 0.0040), (lado * 0.0190, y, z + 0.0015), aco, 0.0007)
            )
        objs.append(
            torno(
                "Barra",
                [(0.0, -0.0098), (0.0008, -0.0098), (0.0008, 0.0098), (0.0, 0.0098)],
                aco,
                (lado * 0.0212, 0, z + 0.0004),
                (90, 0, 0),
                n=10,
            )
        )
    # fivela na parte de baixo da volta
    a = math.radians(-58)
    fx, fz = rx * math.cos(a), z_c + rz * math.sin(a)
    objs.append(
        toro("Fivela", 0.0110, 0.0012, aco, (fx, 0, fz - 0.0012), (0, math.degrees(a) + 90, 0))
    )
    return grupo(objs, (0, 0, 0.002), (24, 0, 18))


PREMIOS = {
    "creditos": (pr_creditos, (0.42, -1.0, 0.72)),
    "reforco": (pr_reforco, (0.62, -1.0, 0.66)),
    "disco": (pr_disco, (0.45, -1.0, 0.34)),
    "gesto": (pr_gesto, (0.32, -1.0, 1.05)),
    "cartao": (pr_cartao, (0.38, -1.0, 0.40)),
    "estrelas": (pr_estrelas, (0.16, -1.0, 0.42)),
    "bandeira": (pr_bandeira, (0.42, -1.0, 0.26)),
    "medalha": (pr_medalha, (0.12, -0.42, 1.0)),
    "maleta": (pr_maleta, (0.58, -1.0, 0.46)),
    "relogio": (pr_relogio, (0.26, -1.0, 0.72)),
}


def render_premio(chave, amostras, teste, saida):
    C.cena_vazia()
    cena = bpy.context.scene
    lado = 256 if teste else 512
    L.configurar(cena, lado, lado, amostras)
    acabar(cena)
    mundo_estudio(cena)
    fn, direcao = PREMIOS[chave]
    objs = fn(paleta())
    bpy.context.view_layer.update()
    vis = [o for o in objs if o.type in ("MESH", "CURVE", "FONT")]
    cam, centro, raio = L.camera_para(vis, lado, lado, direcao=direcao, lente=85.0, folga=1.16)
    cam.data.clip_start = 0.005
    luzes_catalogo(centro, raio * 1.05)
    lo, _ = L.caixa_mundo(vis)
    bpy.ops.mesh.primitive_plane_add(size=40 * raio, location=(centro.x, centro.y, float(lo.z)))
    chao = bpy.context.active_object
    chao.name = "Sombra"
    chao.is_shadow_catcher = True
    chao.visible_glossy = False
    chao.visible_shadow = False
    saida.mkdir(parents=True, exist_ok=True)
    arquivo = saida / f"{chave}.png"
    cena.render.filepath = str(arquivo)
    bpy.ops.render.render(write_still=True)
    apagar_bordas(arquivo, 0.04, 0.04)
    log("ok premio", chave)


# ------------------------------------------------------------------ principal
GRUPOS = {
    "armas": (list(ARMAS), render_arma, UI / "armas", 48, 24),
    "equip": (list(EQUIP), render_equip, UI / "equip", 48, 24),
    "classes": (list(CLASSES), render_classe, UI / "classes", 48, 16),
    "times": (list(TIMES), render_time, UI / "times", 96, 32),
    "premios": (list(PREMIOS), render_premio, UI / "premios", 48, 24),
}


def principal():
    args = C.argumentos()
    if not args:
        raise SystemExit(
            "uso: armas_catalogo.py -- armas|equip|classes|times|premios|todas [ids...] "
            "[--teste] [--amostras N] [--saida PASTA]"
        )
    teste = "--teste" in args
    amostras = int(args[args.index("--amostras") + 1]) if "--amostras" in args else None
    pasta = Path(args[args.index("--saida") + 1]) if "--saida" in args else None
    pulos = {args.index(k) + 1 for k in ("--amostras", "--saida") if k in args}
    resto = [a for i, a in enumerate(args) if i not in pulos and not a.startswith("--")]
    alvo = resto[0]
    ids = resto[1:]
    grupos = list(GRUPOS) if alvo == "todas" else [alvo]
    t0 = time.time()
    for g in grupos:
        chaves, fn, destino, am_final, am_teste = GRUPOS[g]
        am = amostras or (am_teste if teste else am_final)
        base = pasta or (Path(tempfile.gettempdir()) / "vt65_catalogo" if teste else destino.parent)
        saida = (base / destino.name) if (teste or pasta) else destino
        for k in ids or chaves:
            if k not in chaves:
                continue
            t1 = time.time()
            fn(k, am, teste, saida)
            log("tempo", g, k, round(time.time() - t1, 1), "s")
    log("total", round(time.time() - t0, 1), "s")


if __name__ == "__main__":
    principal()
