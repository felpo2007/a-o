"""Fundo estático do lobby: paisagem do Vietnã em 1965 na hora dourada, sem nenhuma pessoa.

Arrozais em terraços com lâmina d'água, diques, vila, coqueiros, bananeiras, bambuzais, mata, serras
em camadas com névoa e um posto discreto (sacos de areia, caixotes e um M151). A coluna esquerda
(~40% da largura) fica mais escura e calma, porque os botões do menu ficam ali.

- os modelos são os do jogo; a vegetação entra por instâncias (Geometry Nodes), sem copiar malha;
- o céu é pintado em numpy: só o FORMATO das nuvens vem do HDRI (Poly Haven, CC0);
- a névoa é feita no material (distância e altura), sem volume: não tem ruído e aparece no reflexo;
- o render sai em EXR linear e a revelação (bloom, curva, coluna escura) é feita aqui, em numpy.

Uso:
    blender -b --factory-startup -P tools/blender/lobby_fundo.py -- [--teste] [--amostras N]
        [--saida arquivo.png] [--so-pos] [--troca-ceu]

`--so-pos` refaz só a revelação a partir do último EXR. `--troca-ceu` troca só o céu do último EXR
(o céu antigo em `ceu_velho.exr`), sem refazer a luz da cena. Saída: `assets/ui/lobby/fundo.png`.
"""

from __future__ import annotations

import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import loja as L  # noqa: E402

RAIZ = C.RAIZ
FG = RAIZ / "assets" / "forgegui" / "models"
BL = RAIZ / "assets" / "blender"
TEX = RAIZ / "assets" / "texturas"
HDRI = RAIZ / "assets" / "ceu" / "kloofendal_48d_partly_cloudy_puresky.jpg"
SAIDA = RAIZ / "assets" / "ui" / "lobby" / "fundo.png"
TRABALHO = C.TRABALHO / "lobby_fundo"

LARGURA, ALTURA = 2048, 1152
CAM = Vector((0.0, 0.0, 12.5))
LENTE = 32.0
HORIZONTE = 0.43  # fração da altura do quadro, de cima para baixo

# o sol que se vê no céu e o que ilumina a cena: o de luz fica mais alto e mais de lado para dar
# relevo às casas e às palmeiras (com 4,5 graus o chão não receberia quase nada)
SOL_CEU = (22.0, 4.5)
SOL_LUZ = (40.0, 15.0)

CEU_AZ = 75.0
CEU_EL = (-4.0, 46.0)
CEU_PX_GRAU = 26

GIRO_NUVENS = 44.0
ZOOM_NUVENS = 3.5

for _k in (
    "casa_palha",
    "casa_telha",
    "casa_varanda",
    "celeiro",
    "coqueiro",
    "bananeira",
    "bambu_touceira",
    "arvore_dossel",
    "arvore_colina",
    "arbusto",
    "capim_elefante",
    "tram_bosque",
    "taioba_samambaia",
    "cerca_bambu",
    "bufalo",
):
    L.MODELOS[_k] = FG / f"{_k}_studs_fosco.glb"
for _k in ("sandbag_wall", "caixa_municao_us", "water_jar", "straw_stack"):
    L.MODELOS[_k] = BL / _k / f"{_k}.glb"
for _n in range(1, 11):
    _k = f"vila_casa_{_n:02d}"
    L.MODELOS[_k] = BL / _k / f"{_k}.glb"


def log(*a):
    print("[VT65]", *a, flush=True)


def direcao(az_graus: float, el_graus: float) -> Vector:
    az, el = math.radians(az_graus), math.radians(el_graus)
    return Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))


# ------------------------------------------------------------------ ruído e relevo
_rng_tabela = np.random.default_rng(65)
_P = np.concatenate([_rng_tabela.permutation(256)] * 2)
_V = _rng_tabela.random(512)


def ruido(x, y):
    xi, yi = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    fx, fy = x - xi, y - yi
    u, v = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)

    def h(a, b):
        return _V[_P[a & 255] + (b & 255)]

    a = h(xi, yi) * (1 - u) + h(xi + 1, yi) * u
    b = h(xi, yi + 1) * (1 - u) + h(xi + 1, yi + 1) * u
    return a * (1 - v) + b * v


def fbm(x, y, oitavas=4, ganho=0.5):
    soma, amp, norma = 0.0, 1.0, 0.0
    for i in range(oitavas):
        soma = soma + amp * ruido(x * 2**i + i * 13.7, y * 2**i - i * 7.3)
        norma += amp
        amp *= ganho
    return soma / norma


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def smax(a, b, k):
    h = np.clip(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
    return b + (a - b) * h + k * h * (1 - h)


def estrada_x(y):
    return 7.0 + 0.33 * y + 4.0 * np.sin(y / 24.0)


# (distância, meia-largura, altura mínima, altura máxima, frequência no ângulo, semente)
SERRAS = (
    (620.0, 130.0, 10.0, 18.0, 5.5, 3.1),
    (1150.0, 240.0, 45.0, 78.0, 4.2, 8.4),
    (2300.0, 460.0, 130.0, 220.0, 3.1, 15.2),
    (4300.0, 800.0, 300.0, 510.0, 2.3, 23.9),
)


def morros(x, y):
    r = np.hypot(x, y)
    a = np.arctan2(x, y)
    alto = np.zeros_like(r)
    for d, w, h0, h1, f, s in SERRAS:
        p = fbm(a * f + s, s * 0.7, 4)
        crista = 1 - np.abs(2 * fbm(a * f * 1.7 + s * 2, s, 3) - 1)
        perfil = np.clip(0.55 * p + 0.45 * crista, 0, 1)
        h = h0 + (h1 - h0) * sstep(0.25, 0.8, perfil)
        h = h * (1 + 0.32 * sstep(-0.05, -0.55, a))  # mais alto à esquerda
        h = h * (1 - 0.28 * np.exp(-(((a - 0.38) / 0.24) ** 2)))  # abre um vale sob o sol
        rr = d + 0.12 * d * (fbm(a * 2.3 + s, 1.3, 2) - 0.5) * 2
        alto = np.maximum(alto, h * np.exp(-(((r - rr) / w) ** 2)))
    return alto * (1 + 0.09 * (fbm(x * 0.028 + 9, y * 0.028 + 2, 4) - 0.5) * 2)


def mascara_arrozal(x, y):
    d = ((x + 10) / 235) ** 2 + ((y - 145) / 135) ** 2 + 0.16 * (fbm(x * 0.02, y * 0.02, 3) - 0.5)
    return 1 - sstep(0.84, 1.06, d)


def altura(x, y):
    """Altura do chão (m). Dentro do arrozal fica abaixo dos terraços, que têm malha própria."""
    x, y = np.asarray(x, np.float64), np.asarray(y, np.float64)
    base = 2.4 + 1.6 * (fbm(x * 0.011 + 3, y * 0.011 + 7, 4) - 0.5) * 2
    m = mascara_arrozal(x, y)
    z = base * (1 - m) - 1.4 * m
    # o -4 mantém a fusão suave longe do nível da água (com k = 5 o chão subia e cobria a lâmina)
    z = smax(z, morros(x, y) - 4.0, 4.0)
    # plataforma da vila
    v = np.exp(-(((x - 42) / 56) ** 2 + ((y - 150) / 50) ** 2))
    zv = -2.0 + (4.35 + 0.35 * (fbm(x * 0.05, y * 0.05, 3) - 0.5)) * sstep(0.34, 0.6, v)
    z = smax(z, zv, 0.5)
    # estrada de terra até a vila
    dx = np.abs(x - estrada_x(y))
    janela = sstep(-4, 4, y) * (1 - sstep(118, 132, y))
    zr = -2.4 + (3.55 + 0.1 * fbm(x * 0.2, y * 0.2, 2)) * (1 - sstep(1.7, 4.4, dx)) * janela
    z = smax(z, zr, 0.5)
    # elevação em primeiro plano, de onde a câmera olha
    g = y - (23.0 + 0.006 * x * x + 1.1 * np.sin(x * 0.19) - 0.09 * x)
    k = 1 - sstep(-2.5, 5.0, g)
    topo = 6.4 + 0.55 * (fbm(x * 0.09, y * 0.09, 3) - 0.5) * 2
    topo = topo + 1.6 * np.exp(-((x + 13) ** 2 / 70 + (y - 18) ** 2 / 50))
    z = smax(z, -2.2 + (topo + 2.2) * k, 0.7)
    return z + 0.1 * (fbm(x * 0.7, y * 0.7, 3) - 0.5) * (1 - m)


# ------------------------------------------------------------------ malhas
def malha_grade(nome, X, Y, Z, atributos=None, material=None, suave=True):
    """Objeto com uma grade H x W de quadriláteros (arrays numpy)."""
    h, w = X.shape
    co = np.column_stack([X.ravel(), Y.ravel(), Z.ravel()])
    i = np.arange((h - 1) * (w - 1))
    linha, coluna = i // (w - 1), i % (w - 1)
    a = linha * w + coluna
    quad = np.column_stack([a, a + 1, a + w + 1, a + w])
    return malha_arrays(nome, co, quad, atributos, material, suave)


def malha_arrays(nome, co, quad, atributos=None, material=None, suave=True):
    me = bpy.data.meshes.new(nome)
    me.vertices.add(len(co))
    me.vertices.foreach_set("co", co.astype(np.float32).ravel())
    me.loops.add(quad.size)
    me.polygons.add(len(quad))
    me.loops.foreach_set("vertex_index", quad.astype(np.int32).ravel())
    me.polygons.foreach_set("loop_start", np.arange(len(quad), dtype=np.int32) * 4)
    me.update(calc_edges=True)
    for chave, valores in (atributos or {}).items():
        at = me.attributes.new(chave, "FLOAT", "POINT")
        at.data.foreach_set("value", np.asarray(valores, np.float32).ravel())
    if suave:
        me.shade_smooth()
    if material is not None:
        me.materials.append(material)
    ob = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tufo(nome, folhas, alt, larg, material, semente):
    """Tufo de folhas finas e curvas (arroz e capim do dique)."""
    rng = np.random.default_rng(semente)
    co, quad = [], []
    for _ in range(folhas):
        ang = rng.random() * math.tau
        h = alt * (0.55 + 0.45 * rng.random())
        curva = 0.25 + 0.55 * rng.random()
        base = rng.random(2) * alt * 0.07
        dirx, diry = math.cos(ang), math.sin(ang)
        i0 = len(co)
        for s in range(5):
            t = s / 4
            meio_l = larg * (1 - t) ** 0.8 * 0.5 + 0.001
            cx = base[0] + dirx * h * curva * t * t
            cy = base[1] + diry * h * curva * t * t
            z = h * (t - 0.28 * curva * t * t)
            co.append((cx - diry * meio_l, cy + dirx * meio_l, z))
            co.append((cx + diry * meio_l, cy - dirx * meio_l, z))
        for s in range(4):
            a = i0 + s * 2
            quad.append((a, a + 1, a + 3, a + 2))
    ob = malha_arrays(nome, np.array(co), np.array(quad), material=material)
    ob.hide_render = True
    ob.hide_viewport = True
    return ob


# ------------------------------------------------------------------ nós de material
def ligar(nt, sock, v):
    if isinstance(v, bpy.types.NodeSocket):
        nt.links.new(v, sock)
    else:
        sock.default_value = v


def no_math(nt, op, a, b=None, limitar=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = limitar
    ligar(nt, n.inputs[0], a)
    if b is not None:
        ligar(nt, n.inputs[1], b)
    return n.outputs[0]


def no_mix(nt, fac, a, b):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    ligar(nt, n.inputs[0], fac)
    ligar(nt, next(s for s in n.inputs if s.name == "A" and s.type == "RGBA"), a)
    ligar(nt, next(s for s in n.inputs if s.name == "B" and s.type == "RGBA"), b)
    return next(s for s in n.outputs if s.type == "RGBA")


def no_faixa(nt, valor, a, b, de=0.0, para=1.0):
    n = nt.nodes.new("ShaderNodeMapRange")
    n.interpolation_type = "SMOOTHSTEP"
    ligar(nt, n.inputs["Value"], valor)
    n.inputs["From Min"].default_value = a
    n.inputs["From Max"].default_value = b
    n.inputs["To Min"].default_value = de
    n.inputs["To Max"].default_value = para
    return n.outputs[0]


def no_ruido(nt, vetor, escala, detalhe=4.0, aspereza=0.55):
    n = nt.nodes.new("ShaderNodeTexNoise")
    ligar(nt, n.inputs["Vector"], vetor)
    n.inputs["Scale"].default_value = escala
    n.inputs["Detail"].default_value = detalhe
    n.inputs["Roughness"].default_value = aspereza
    return n.outputs[0]


def no_imagem(nt, arquivo, vetor, escala, dados=False):
    v = nt.nodes.new("ShaderNodeVectorMath")
    v.operation = "SCALE"
    ligar(nt, v.inputs[0], vetor)
    v.inputs["Scale"].default_value = escala
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(str(TEX / arquivo), check_existing=True)
    if dados:
        n.image.colorspace_settings.name = "Non-Color"
    nt.links.new(v.outputs[0], n.inputs["Vector"])
    return n.outputs["Color"]


def base_material(nome):
    mat = C.novo_material(nome)
    nt = mat.node_tree
    nt.nodes.clear()
    saida = nt.nodes.new("ShaderNodeOutputMaterial")
    pr = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(pr.outputs[0], saida.inputs["Surface"])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    return mat, nt, pr, geo.outputs["Position"]


def mat_chao():
    mat, nt, pr, P = base_material("Chao")
    grama = no_imagem(nt, "leafy_grass_cor.jpg", P, 1 / 3.4)
    mata = no_imagem(nt, "forest_ground_06_cor.jpg", P, 1 / 5.1)
    terra = no_imagem(nt, "dirt_floor_cor.jpg", P, 1 / 2.9)
    terra = no_mix(nt, 0.35, terra, (0.075, 0.058, 0.042, 1))
    grossa = no_faixa(nt, no_ruido(nt, P, 0.55, 5.0, 0.6), 0.34, 0.66)
    terra = no_mix(nt, no_math(nt, "MULTIPLY", grossa, 0.62), terra, (0.022, 0.018, 0.014, 1))
    mancha = no_faixa(nt, no_ruido(nt, P, 0.09), 0.38, 0.62)
    perto = no_mix(nt, mancha, grama, mata)
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "estrada"
    falha = no_faixa(nt, no_ruido(nt, P, 1.5, 4.0, 0.6), 0.34, 0.56)
    invade = no_math(nt, "MULTIPLY", at.outputs[2], falha)
    invade = no_math(nt, "MULTIPLY", invade, 1.7, limitar=True)
    perto = no_mix(nt, invade, perto, terra)
    v = nt.nodes.new("ShaderNodeVectorMath")
    v.operation = "SUBTRACT"
    ligar(nt, v.inputs[0], P)
    v.inputs[1].default_value = CAM
    dist = nt.nodes.new("ShaderNodeVectorMath")
    dist.operation = "LENGTH"
    nt.links.new(v.outputs[0], dist.inputs[0])
    d = dist.outputs["Value"]
    longe = no_mix(
        nt,
        no_faixa(nt, no_ruido(nt, P, 0.012, 6.0, 0.62), 0.36, 0.66),
        (0.012, 0.03, 0.014, 1),
        (0.05, 0.085, 0.03, 1),
    )
    cor = no_mix(nt, no_faixa(nt, d, 70.0, 300.0), perto, longe)
    nt.links.new(cor, pr.inputs["Base Color"])
    pr.inputs["Roughness"].default_value = 0.92
    pr.inputs["Specular IOR Level"].default_value = 0.25
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.8
    bump.inputs["Distance"].default_value = 0.1
    ligar(nt, bump.inputs["Height"], no_ruido(nt, P, 2.4, 6.0, 0.6))
    nt.links.new(bump.outputs[0], pr.inputs["Normal"])
    return mat


def mat_dique():
    mat, nt, pr, P = base_material("Dique")
    grama = no_imagem(nt, "leafy_grass_cor.jpg", P, 1 / 2.6)
    grama = no_mix(nt, 0.18, grama, (0.05, 0.11, 0.025, 1))
    lama = no_imagem(nt, "brown_mud_leaves_01_cor.jpg", P, 1 / 2.2)
    lama = no_mix(nt, 0.3, lama, (0.05, 0.04, 0.025, 1))
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "dique"
    mancha = no_ruido(nt, P, 0.8)
    fac = no_math(nt, "MULTIPLY", at.outputs[2], no_faixa(nt, mancha, 0.3, 0.55, 0.45, 1.0))
    nt.links.new(no_mix(nt, fac, lama, grama), pr.inputs["Base Color"])
    pr.inputs["Roughness"].default_value = 0.88
    pr.inputs["Specular IOR Level"].default_value = 0.3
    return mat


def mat_agua():
    mat, nt, pr, P = base_material("Agua")
    pr.inputs["Base Color"].default_value = (0.80, 0.83, 0.82, 1)
    pr.inputs["Metallic"].default_value = 1.0
    pr.inputs["Roughness"].default_value = 0.03
    ond = nt.nodes.new("ShaderNodeVectorMath")
    ond.operation = "MULTIPLY"
    ligar(nt, ond.inputs[0], P)
    ond.inputs[1].default_value = (0.5, 1.5, 1.0)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.035
    bump.inputs["Distance"].default_value = 0.05
    ligar(nt, bump.inputs["Height"], no_ruido(nt, ond.outputs[0], 3.2, 3.0, 0.5))
    nt.links.new(bump.outputs[0], pr.inputs["Normal"])
    return mat


def mat_folha(nome, c1, c2):
    mat = C.novo_material(nome)
    nt = mat.node_tree
    nt.nodes.clear()
    saida = nt.nodes.new("ShaderNodeOutputMaterial")
    info = nt.nodes.new("ShaderNodeObjectInfo")
    cor = no_mix(nt, info.outputs["Random"], c1, c2)
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    nt.links.new(cor, dif.inputs["Color"])
    tra = nt.nodes.new("ShaderNodeBsdfTranslucent")
    nt.links.new(cor, tra.inputs["Color"])
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs[0].default_value = 0.35
    nt.links.new(dif.outputs[0], mix.inputs[1])
    nt.links.new(tra.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], saida.inputs["Surface"])
    return mat


def grupo_nevoa():
    """Fator e cor da névoa pela distância à câmera e pela altura (mais densa no fundo do vale)."""
    g = bpy.data.node_groups.new("Nevoa", "ShaderNodeTree")
    g.interface.new_socket("Fac", in_out="OUTPUT", socket_type="NodeSocketFloat")
    g.interface.new_socket("Cor", in_out="OUTPUT", socket_type="NodeSocketColor")
    saida = g.nodes.new("NodeGroupOutput")
    geo = g.nodes.new("ShaderNodeNewGeometry")
    P = geo.outputs["Position"]
    v = g.nodes.new("ShaderNodeVectorMath")
    v.operation = "SUBTRACT"
    g.links.new(P, v.inputs[0])
    v.inputs[1].default_value = CAM
    comp = g.nodes.new("ShaderNodeVectorMath")
    comp.operation = "LENGTH"
    g.links.new(v.outputs[0], comp.inputs[0])
    d = comp.outputs["Value"]
    sep = g.nodes.new("ShaderNodeSeparateXYZ")
    g.links.new(P, sep.inputs[0])
    z = no_math(g, "MAXIMUM", no_math(g, "SUBTRACT", sep.outputs["Z"], 1.0), 0.0)
    baixa = no_math(g, "EXPONENT", no_math(g, "DIVIDE", no_math(g, "MULTIPLY", z, -1.0), 30.0))
    n = no_faixa(g, no_ruido(g, P, 0.0035, 4.0, 0.55), 0.3, 0.7, 0.3, 1.7)
    dens = no_math(
        g, "ADD", 1 / 10500, no_math(g, "MULTIPLY", 1 / 2100, no_math(g, "MULTIPLY", baixa, n))
    )
    expo = no_math(g, "EXPONENT", no_math(g, "MULTIPLY", no_math(g, "MULTIPLY", d, dens), -1.0))
    fac = no_math(g, "SUBTRACT", 1.0, expo, limitar=True)
    norm = g.nodes.new("ShaderNodeVectorMath")
    norm.operation = "NORMALIZE"
    g.links.new(v.outputs[0], norm.inputs[0])
    prod = g.nodes.new("ShaderNodeVectorMath")
    prod.operation = "DOT_PRODUCT"
    g.links.new(norm.outputs[0], prod.inputs[0])
    prod.inputs[1].default_value = direcao(*SOL_CEU)
    quente = no_math(g, "POWER", no_math(g, "MAXIMUM", prod.outputs["Value"], 0.0), 12.0)
    cor = no_mix(g, quente, (0.46, 0.33, 0.47, 1), (1.12, 0.62, 0.40, 1))
    g.links.new(fac, saida.inputs["Fac"])
    g.links.new(cor, saida.inputs["Cor"])
    return g


def vestir_nevoa(mat, grupo):
    if mat is None or mat.node_tree is None:
        return
    nt = mat.node_tree
    saida = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
    if saida is None:
        saida = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
    if saida is None or not saida.inputs["Surface"].is_linked:
        return
    fonte = saida.inputs["Surface"].links[0].from_socket
    no = nt.nodes.new("ShaderNodeGroup")
    no.node_tree = grupo
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(no.outputs["Cor"], em.inputs["Color"])
    fac = no.outputs["Fac"]
    pr = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if pr is not None and pr.inputs["Alpha"].is_linked:
        # a névoa não pode acender o recorte transparente da folha
        fac = no_math(nt, "MULTIPLY", fac, pr.inputs["Alpha"].links[0].from_socket)
    mix = nt.nodes.new("ShaderNodeMixShader")
    ligar(nt, mix.inputs[0], fac)
    nt.links.new(fonte, mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], saida.inputs["Surface"])


# ------------------------------------------------------------------ céu
def pintar_ceu() -> Path:
    """Céu do entardecer em EXR: recorte de az/el à frente da câmera. As nuvens saem do HDRI (só a
    máscara e o volume); a cor é toda daqui."""
    caminho = TRABALHO / "ceu.exr"
    if caminho.is_file() and caminho.stat().st_mtime > Path(__file__).stat().st_mtime:
        return caminho
    t0 = time.time()
    img = bpy.data.images.load(str(HDRI))
    img.scale(4096, 2048)
    fonte = np.empty(4096 * 2048 * 4, np.float32)
    img.pixels.foreach_get(fonte)
    bpy.data.images.remove(img)
    fonte = fonte.reshape(2048, 4096, 4)[::-1, :, :3]

    w = int(2 * CEU_AZ * CEU_PX_GRAU)
    h = int((CEU_EL[1] - CEU_EL[0]) * CEU_PX_GRAU)
    az = np.linspace(-CEU_AZ, CEU_AZ, w, dtype=np.float32)
    el = np.linspace(CEU_EL[1], CEU_EL[0], h, dtype=np.float32)
    AZ, EL = np.meshgrid(az, el)

    # as nuvens grandes do HDRI são trazidas para perto do horizonte (zoom)
    fu = (0.5 + (AZ * ZOOM_NUVENS + GIRO_NUVENS) / 360.0) % 1.0
    el_f = 2.0 + np.maximum(EL, 0) * ZOOM_NUVENS
    fv = np.clip((90.0 - el_f) / 180.0, 0, 0.999)
    px, py = fu * 4095, fv * 2047
    x0, y0 = px.astype(np.int32), py.astype(np.int32)
    tx, ty = (px - x0)[..., None], (py - y0)[..., None]
    x1, y1 = (x0 + 1) % 4096, np.minimum(y0 + 1, 2047)
    amostra = (fonte[y0, x0] * (1 - tx) + fonte[y0, x1] * tx) * (1 - ty) + (
        fonte[y1, x0] * (1 - tx) + fonte[y1, x1] * tx
    ) * ty
    del fonte
    r, b = amostra[..., 0], amostra[..., 2]
    nuvem = sstep(0.54, 0.80, r / np.maximum(b, 1e-3)) * sstep(0.2, 2.2, EL)
    volume = sstep(0.60, 0.98, amostra.mean(axis=2)) ** 1.7
    del amostra

    razel, razaz = np.radians(EL), np.radians(AZ)
    d = np.stack(
        [np.sin(razaz) * np.cos(razel), np.cos(razaz) * np.cos(razel), np.sin(razel)], axis=-1
    )
    s = np.array(direcao(*SOL_CEU), np.float32)
    ang = np.degrees(np.arccos(np.clip((d * s).sum(axis=2), -1, 1)))

    paradas = np.array([-4, 0, 3, 8, 16, 32, 46], np.float32)
    cores = np.array(
        [
            (1.05, 0.52, 0.20),
            (1.05, 0.55, 0.22),
            (0.92, 0.46, 0.22),
            (0.60, 0.33, 0.23),
            (0.30, 0.23, 0.25),
            (0.12, 0.13, 0.21),
            (0.055, 0.07, 0.15),
        ],
        np.float32,
    )
    ceu = np.stack([np.interp(EL, paradas, cores[:, i]) for i in range(3)], axis=-1)
    lado = 0.62 + 0.30 * sstep(70, 8, ang)
    ceu = ceu * lado[..., None]
    brilho = np.exp(-((ang / 10.0) ** 2))[..., None] * np.array((0.62, 0.30, 0.11), np.float32)
    nucleo = np.exp(-((ang / 2.6) ** 2))[..., None] * np.array((3.6, 2.3, 1.05), np.float32)
    disco = sstep(0.75, 0.55, ang)[..., None] * np.array((9.0, 6.4, 3.4), np.float32)

    perto = (0.08 + 0.55 * np.exp(-((ang / 24.0) ** 2)))[..., None]
    sombra = np.array((0.19, 0.13, 0.15), np.float32)
    meio = np.array((0.70, 0.37, 0.25), np.float32)
    luz = np.array((1.35, 0.76, 0.35), np.float32)
    v = volume[..., None]
    corpo = 0.25 + 0.55 * v
    cor_nuvem = sombra * (1 - corpo) + meio * corpo
    macia = desfocar(nuvem.astype(np.float32), 7)
    desloc = np.roll(np.roll(macia, -16, axis=1), 9, axis=0)
    borda = np.clip((macia - desloc) * 2.4, 0, 1)[..., None]
    cor_nuvem = cor_nuvem * (1 - 0.9 * borda) + luz * (0.5 + 1.1 * perto) * borda
    m = nuvem[..., None]
    final = (
        (ceu + brilho) * (1 - m)
        + (cor_nuvem + 0.35 * brilho) * m
        + (nucleo + disco) * (1 - 0.72 * m)
    )

    rgba = np.concatenate([final[::-1], np.ones((h, w, 1), np.float32)], axis=2)
    saida = bpy.data.images.new("ceu_exr", w, h, alpha=False, float_buffer=True)
    saida.pixels.foreach_set(rgba.astype(np.float32).ravel())
    TRABALHO.mkdir(parents=True, exist_ok=True)
    saida.filepath_raw = str(caminho)
    saida.file_format = "OPEN_EXR"
    saida.save()
    bpy.data.images.remove(saida)
    log("céu pintado", w, h, round(time.time() - t0, 1), "s")
    return caminho


def montar_mundo(cena, caminho: Path):
    mundo = bpy.data.worlds.new("Entardecer")
    cena.world = mundo
    mundo.use_nodes = True
    nt = mundo.node_tree
    nt.nodes.clear()
    saida = nt.nodes.new("ShaderNodeOutputWorld")
    fundo = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    norm = nt.nodes.new("ShaderNodeVectorMath")
    norm.operation = "NORMALIZE"
    nt.links.new(tc.outputs["Generated"], norm.inputs[0])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(norm.outputs[0], sep.inputs[0])
    az = no_math(nt, "ARCTAN2", sep.outputs["X"], sep.outputs["Y"])
    el = no_math(nt, "ARCSINE", sep.outputs["Z"])
    meia = math.radians(CEU_AZ)
    e0, e1 = math.radians(CEU_EL[0]), math.radians(CEU_EL[1])
    u = no_math(nt, "DIVIDE", no_math(nt, "ADD", az, meia), 2 * meia)
    v = no_math(nt, "DIVIDE", no_math(nt, "SUBTRACT", el, e0), e1 - e0)
    junta = nt.nodes.new("ShaderNodeCombineXYZ")
    ligar(nt, junta.inputs[0], u)
    ligar(nt, junta.inputs[1], v)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(caminho), check_existing=True)
    tex.extension = "EXTEND"
    nt.links.new(junta.outputs[0], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], fundo.inputs["Color"])
    fundo.inputs["Strength"].default_value = 1.0
    nt.links.new(fundo.outputs[0], saida.inputs["Surface"])


# ------------------------------------------------------------------ instâncias
_grupos: dict[str, bpy.types.NodeTree] = {}


def grupo_instancia(fonte: bpy.types.Object) -> bpy.types.NodeTree:
    if fonte.name in _grupos:
        return _grupos[fonte.name]
    g = bpy.data.node_groups.new(f"Inst_{fonte.name}", "GeometryNodeTree")
    g.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    g.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    ent = g.nodes.new("NodeGroupInput")
    sai = g.nodes.new("NodeGroupOutput")
    info = g.nodes.new("GeometryNodeObjectInfo")
    info.inputs["Object"].default_value = fonte
    info.inputs["As Instance"].default_value = True
    inst = g.nodes.new("GeometryNodeInstanceOnPoints")
    giro = g.nodes.new("GeometryNodeInputNamedAttribute")
    giro.data_type = "FLOAT_VECTOR"
    giro.inputs["Name"].default_value = "giro"
    esc = g.nodes.new("GeometryNodeInputNamedAttribute")
    esc.data_type = "FLOAT_VECTOR"
    esc.inputs["Name"].default_value = "esc"
    g.links.new(ent.outputs[0], inst.inputs["Points"])
    g.links.new(info.outputs["Geometry"], inst.inputs["Instance"])
    g.links.new(giro.outputs["Attribute"], inst.inputs["Rotation"])
    g.links.new(esc.outputs["Attribute"], inst.inputs["Scale"])
    g.links.new(inst.outputs[0], sai.inputs[0])
    _grupos[fonte.name] = g
    return g


def espalhar(nome, fonte, pos, esc, rng, inclina=0.05, alongar=1.0):
    n = len(pos)
    if n == 0:
        return None
    me = bpy.data.meshes.new(nome)
    me.vertices.add(n)
    me.vertices.foreach_set("co", np.asarray(pos, np.float32).ravel())
    giro = np.column_stack(
        [rng.normal(0, inclina, n), rng.normal(0, inclina, n), rng.random(n) * math.tau]
    )
    me.attributes.new("giro", "FLOAT_VECTOR", "POINT").data.foreach_set(
        "vector", giro.astype(np.float32).ravel()
    )
    e = np.asarray(esc, np.float32)
    me.attributes.new("esc", "FLOAT_VECTOR", "POINT").data.foreach_set(
        "vector", np.column_stack([e, e, e * alongar]).astype(np.float32).ravel()
    )
    me.update()
    ob = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.modifiers.new("inst", "NODES").node_group = grupo_instancia(fonte)
    log("instâncias", nome, n)
    return ob


def sortear(rng, n, r0, r1, amax_graus):
    r = np.sqrt(rng.random(n) * (r1 * r1 - r0 * r0) + r0 * r0)
    a = np.radians((rng.random(n) * 2 - 1) * amax_graus)
    return r * np.sin(a), r * np.cos(a)


def fora_da_vila(x, y, folga=0.0):
    return ((x - 42) / (47 + folga)) ** 2 + ((y - 150) / (40 + folga)) ** 2 > 1


def fora_da_estrada(x, y, folga=3.6):
    return (np.abs(x - estrada_x(y)) > folga) | (y > 128)


# ------------------------------------------------------------------ cenário
def construir_chao(material):
    na, nr = 760, 720
    a = np.radians(np.linspace(-62, 62, na))
    r = np.geomspace(2.2, 6200.0, nr)
    R, A = np.meshgrid(r, a, indexing="ij")
    X, Y = R * np.sin(A), R * np.cos(A)
    Z = altura(X, Y)
    dx = np.abs(X - estrada_x(Y))
    estrada = (1 - sstep(0.9, 1.9, dx)) * sstep(-2, 4, Y) * (1 - sstep(116, 130, Y))
    # a grade vai do centro para fora; esta ordem deixa as normais para cima
    return malha_grade("Chao", X, Y, Z, {"estrada": estrada}, material)


def construir_terracos(m_dique, m_agua, m_arroz, m_capim, rng):
    n_lin = 18
    larg = 5.5 + 1.5 * np.arange(n_lin) + rng.uniform(-0.8, 0.8, n_lin)
    b0 = 5.0 + np.concatenate([[0.0], np.cumsum(larg)])
    niveis = 0.075 * np.arange(n_lin + 1) + 0.03 * np.sin(np.arange(n_lin + 1) * 1.7)
    xs = np.linspace(-250, 230, 1700)

    def borda(k, x):
        y0 = b0[k]
        # a onda é medida em ângulo (x / distância): cada dique faz a mesma curva na tela
        u = x / (y0 + 25.0)
        return (
            y0
            + (0.42 + 0.0005 * y0) * x
            + 0.18 * y0 * np.sin(3.2 * u + 0.6 + y0 * 0.004)
            + 0.07 * y0 * np.sin(7.1 * u + 1.7 + y0 * 0.012)
            + 0.5 * np.sin(x / 6.1 + y0 * 0.05)
        )

    def crista(k, x):
        return niveis[k] + 0.30 + 0.05 * (fbm(x * 0.08, np.full_like(x, k * 3.1), 3) - 0.5) * 2

    ys, zs, ds = [], [], []
    for k in range(n_lin):
        y_a, y_b = borda(k, xs), borda(k + 1, xs)
        w = y_b - y_a
        z = niveis[k]
        ca, cb = crista(k, xs), crista(k + 1, xs)
        perfil = (
            (y_a, ca, 1.0),
            (y_a + 0.32, ca - 0.03, 1.0),
            (y_a + 0.62, z + 0.05, 0.6),
            (y_a + 0.90, z - 0.06, 0.0),
            (y_a + w * 0.5, z - 0.10, 0.0),
            (y_b - 0.90, z - 0.06, 0.0),
            (y_b - 0.62, z + 0.08, 0.6),
            (y_b - 0.32, cb - 0.03, 1.0),
        )
        for py, pz, pd in perfil:
            ys.append(py)
            zs.append(pz if isinstance(pz, np.ndarray) else np.full_like(xs, pz))
            ds.append(np.full_like(xs, pd))
    ys.append(borda(n_lin, xs))
    zs.append(crista(n_lin, xs))
    ds.append(np.ones_like(xs))
    Y, Z, D = np.array(ys), np.array(zs), np.array(ds)
    X = np.broadcast_to(xs, Y.shape).copy()
    terraco = malha_grade("Terracos", X, Y, Z, {"dique": D}, m_dique)

    # diques transversais
    cos, quads, dqs = [], [], []
    capim_transv = []
    base = 0
    perfil_t = (
        (-0.78, -0.13, 0.0),
        (-0.42, 0.14, 0.8),
        (-0.16, 0.20, 1.0),
        (0.16, 0.20, 1.0),
        (0.42, 0.14, 0.8),
        (0.78, -0.13, 0.0),
    )
    for k in range(n_lin):
        centro = np.linspace(-170, 165, rng.integers(3, 7)) + rng.uniform(-14, 14)
        for x0 in centro:
            desvio = rng.uniform(-3, 3)
            pts = 18
            for j in range(pts):
                t = j / (pts - 1)
                xc = x0 + desvio * t
                ya = borda(k, np.array([xc]))[0]
                yb = borda(k + 1, np.array([xc]))[0]
                yc = ya + (yb - ya) * t
                ruga = 0.04 * math.sin(j * 1.9 + x0)
                for _ in range(3):
                    capim_transv.append(
                        (xc + rng.normal(0, 0.28), yc + rng.normal(0, 0.35), niveis[k] + 0.14)
                    )
                for off, dz, dq in perfil_t:
                    cos.append((xc + off, yc, niveis[k] + dz + ruga))
                    dqs.append(dq)
            for j in range(pts - 1):
                for c in range(5):
                    a = base + j * 6 + c
                    quads.append((a, a + 1, a + 7, a + 6))
            base += pts * 6
    transv = malha_arrays(
        "DiquesTransversais",
        np.array(cos),
        np.array(quads),
        {"dique": np.array(dqs)},
        m_dique,
    )

    # lâmina d'água: uma tira plana por terraço
    cos_a, quads_a = [], []
    nx = len(xs)
    for k in range(n_lin):
        y_a, y_b = borda(k, xs) + 0.75, borda(k + 1, xs) - 0.75
        i0 = len(cos_a) * nx
        cos_a.append(np.column_stack([xs, y_a, np.full_like(xs, niveis[k])]))
        cos_a.append(np.column_stack([xs, y_b, np.full_like(xs, niveis[k])]))
        a = np.arange(nx - 1) + i0
        quads_a.append(np.column_stack([a, a + 1, a + nx + 1, a + nx]))
    agua = malha_arrays("Agua", np.vstack(cos_a), np.vstack(quads_a), None, m_agua, suave=False)

    # arroz: em fileiras, com canteiros mais cheios e outros quase só de água
    f_arroz = tufo("tufo_arroz", 9, 0.42, 0.018, m_arroz, 11)
    f_capim = tufo("tufo_capim", 16, 0.9, 0.03, m_capim, 12)
    pos, esc = [], []
    for k in range(n_lin):
        dens = rng.choice((0.06, 0.14, 0.30, 0.55))
        passo_x = 0.46
        for x in np.arange(-215, 205, passo_x):
            ya = borda(k, np.array([x]))[0] + 1.0
            yb = borda(k + 1, np.array([x]))[0] - 1.0
            if yb <= ya:
                continue
            meio = (ya + yb) / 2
            if abs(x) > 0.74 * meio + 3:
                continue
            yy = np.arange(ya, yb, 0.5)
            mancha = fbm(np.full_like(yy, x * 0.05), yy * 0.05 + k, 3)
            ok = rng.random(len(yy)) < dens * sstep(0.32, 0.6, mancha) * 1.9
            for y in yy[ok]:
                pos.append((x + rng.normal(0, 0.07), y + rng.normal(0, 0.07), niveis[k] - 0.02))
                esc.append((0.62 + rng.random() * 0.42) * (1 + y / 130))
    espalhar("Arroz", f_arroz, np.array(pos), np.array(esc), rng, 0.12)

    pos, esc = [], []
    for k in range(n_lin + 1):
        for x in np.arange(-215, 205, 0.17):
            y = borda(k, np.array([x]))[0]
            if abs(x) > 0.74 * y + 3 or rng.random() < 0.25:
                continue
            pos.append(
                (x + rng.normal(0, 0.14), y + rng.normal(0, 0.22), niveis[min(k, n_lin)] + 0.26)
            )
            esc.append((0.55 + rng.random() * 0.85) * (1 + y / 130))
    for x, y, z in capim_transv:
        if abs(x) <= 0.74 * y + 3:
            pos.append((x, y, z))
            esc.append((0.4 + rng.random() * 0.6) * (1 + y / 130))
    espalhar("CapimDique", f_capim, np.array(pos), np.array(esc), rng, 0.16)
    return terraco, transv, agua, f_capim


def no_chao(x, y, z_extra=0.0):
    return float(altura(np.array([x]), np.array([y]))[0]) + z_extra


def colocar(chave, x, y, giro, escala=1.0, afunda=0.04):
    return L.copia(chave, (x, y, no_chao(x, y) - afunda), (0, 0, giro), escala)


def na_vila(x, y):
    """Da planta da vila (em torno de 30, 100) para o lugar dela no quadro."""
    return x * 1.4, y + 50.0


_esguio: list[bpy.types.Object] = []


def coqueiro_esguio() -> bpy.types.Object:
    """Variante do coqueiro para a paisagem: tronco 3 x mais alto, copa achatada e leve curva."""
    if _esguio:
        return _esguio[0]
    fonte = L.carregar("coqueiro")
    me = fonte.data.copy()
    co = np.empty(len(me.vertices) * 3, np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    z, corte = co[:, 2], 4.2
    copa = z >= corte
    novo = np.where(copa, corte * 3.0 + (z - corte) * 0.62, z * 3.0)
    co[copa, :2] *= 1.12
    co[:, 0] += 0.0055 * novo * novo
    co[:, 2] = novo
    me.vertices.foreach_set("co", co.astype(np.float32).ravel())
    me.update()
    ob = bpy.data.objects.new("coqueiro_esguio", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.hide_render = True
    ob.hide_viewport = True
    _esguio.append(ob)
    return ob


def construir_vila(rng):
    casas = (
        ("vila_casa_01", 15.5, 77.0, 196),
        ("vila_casa_03", 26.0, 83.0, 168),
        ("vila_casa_06", 36.0, 90.0, 205),
        ("vila_casa_02", 20.0, 99.0, 182),
        ("vila_casa_08", 39.0, 108.0, 160),
        ("vila_casa_05", 9.0, 95.0, 215),
        ("vila_casa_09", 50.0, 97.0, 190),
        ("vila_casa_04", 29.0, 116.0, 175),
        ("casa_telha", 56.0, 114.0, 200),
        ("casa_varanda", 13.0, 118.0, 188),
        ("casa_palha", 44.0, 126.0, 172),
    )
    for chave, x, y, g in casas:
        colocar(chave, *na_vila(x, y), g, 1.22)
    colocar("celeiro", *na_vila(21.0, 88.0), 40)
    colocar("straw_stack", *na_vila(11.0, 84.5), 10)
    colocar("straw_stack", *na_vila(32.5, 77.5), 80, 0.9)
    colocar("water_jar", *na_vila(18.8, 72.6), 0)
    colocar("water_jar", *na_vila(19.8, 73.0), 60, 0.85)
    colocar("bufalo", *na_vila(3.5, 83.0), 62)
    for i in range(12):
        x, y = na_vila(4.0 + i * 2.15, 70.6 + 0.35 * math.sin(i))
        colocar("cerca_bambu", x, y, 88 + 3 * math.sin(i * 2))

    coqueiros = (
        (6.0, 86.0, 0.78),
        (9.5, 90.0, 1.05),
        (33.0, 97.0, 0.88),
        (45.5, 81.0, 0.62),
        (56.0, 92.0, 1.12),
        (59.5, 86.5, 0.72),
        (18.0, 112.0, 0.95),
        (68.0, 118.0, 0.85),
        (-5.0, 106.0, 0.7),
        (-13.0, 128.0, 1.02),
    )
    coqueiros = [(*na_vila(x, y), e) for x, y, e in coqueiros]
    p = np.array([(x, y, no_chao(x, y) - 0.1) for x, y, _ in coqueiros])
    espalhar(
        "CoqueirosVila",
        coqueiro_esguio(),
        p,
        np.array([e for _, _, e in coqueiros]),
        rng,
        0.05,
    )
    x = rng.uniform(-10, 100, 230)
    y = rng.uniform(114, 190, 230)
    ok = ((x - 42) / 50) ** 2 + ((y - 152) / 37) ** 2 < 1
    x, y = x[ok], y[ok]
    n = len(x)
    corte = n // 2
    espalhar(
        "BananeirasVila",
        L.carregar("bananeira"),
        np.column_stack([x[:corte], y[:corte], altura(x[:corte], y[:corte]) - 0.05]),
        rng.uniform(0.9, 1.5, corte),
        rng,
    )
    espalhar(
        "ArbustosVila",
        L.carregar("arbusto"),
        np.column_stack([x[corte:], y[corte:], altura(x[corte:], y[corte:]) - 0.05]),
        rng.uniform(0.9, 1.8, n - corte),
        rng,
    )
    bambu = np.array(
        [
            (2.0, 74.0),
            (40.0, 74.5),
            (58.0, 80.0),
            (-6.0, 92.0),
            (70.0, 108.0),
            (25.0, 131.0),
            (-14.0, 112.0),
        ]
    ) * np.array((1.4, 1.0)) + np.array((0.0, 50.0))
    espalhar(
        "BambuVila",
        L.carregar("bambu_touceira"),
        np.column_stack([bambu, altura(bambu[:, 0], bambu[:, 1]) - 0.1]),
        rng.uniform(0.9, 1.3, len(bambu)),
        rng,
    )


def construir_posto():
    """Posto discreto: sacos de areia e caixotes no alto, à direita, e o M151 parado na estrada."""
    colocar("sandbag_wall", 6.9, 19.9, 196, 0.86)
    colocar("sandbag_wall", 8.55, 20.4, 172, 0.86)
    colocar("caixa_municao_us", 5.0, 18.6, 28)
    colocar("caixa_municao_us", 5.2, 18.0, 62, 0.92)
    b = L.copia("caixa_municao_us", (0, 0, 0), (0, 0, 40), 0.9)
    b.location = (5.1, 18.35, no_chao(5.1, 18.35) + 0.46)
    x = float(estrada_x(np.array([76.0]))[0])
    colocar("m151", x - 0.15, 76.0, 118)


def construir_mata(rng):
    fontes = {k: L.carregar(k) for k in ("arvore_dossel", "tram_bosque", "arvore_colina")}
    # orla da mata atrás do arrozal
    x, y = sortear(rng, 6500, 130, 620, 56)
    z = altura(x, y)
    ok = (z > 0.9) & (mascara_arrozal(x, y) < 0.28) & fora_da_vila(x, y, 2) & fora_da_estrada(x, y)
    x, y, z = x[ok], y[ok], z[ok]
    grupos = np.array_split(rng.permutation(len(x)), 3)
    for g, chave, e0, e1 in zip(
        grupos,
        ("arvore_dossel", "tram_bosque", "arvore_colina"),
        (0.72, 1.0, 1.25),
        (1.2, 1.7, 2.2),
        strict=True,
    ):
        e = rng.uniform(e0, e1, len(g))
        afunda = {"arvore_dossel": 6.5, "tram_bosque": 2.6}.get(chave, 0.3) * e
        espalhar(
            f"Orla_{chave}",
            fontes[chave],
            np.column_stack([x[g], y[g], z[g] - afunda]),
            e,
            rng,
        )
    x, y = sortear(rng, 8200, 130, 620, 56)
    z = altura(x, y)
    ok = (z > 0.9) & (mascara_arrozal(x, y) < 0.3) & fora_da_vila(x, y, 2) & fora_da_estrada(x, y)
    idx = rng.permutation(np.flatnonzero(ok))
    n = len(idx)
    for g, chave, e0, e1 in (
        (idx[: int(n * 0.65)], "arvore_colina", 0.5, 1.05),
        (idx[int(n * 0.65) : int(n * 0.85)], "bambu_touceira", 1.0, 1.7),
        (idx[int(n * 0.85) :], "arbusto", 3.0, 5.5),
    ):
        espalhar(
            f"SubBosque_{chave}",
            L.carregar(chave),
            np.column_stack([x[g], y[g], z[g] - 0.2]),
            rng.uniform(e0, e1, len(g)),
            rng,
        )
    # encostas das serras próximas
    x, y = sortear(rng, 10000, 520, 1500, 58)
    z = altura(x, y)
    ok = z > 3.0
    espalhar(
        "Encosta",
        fontes["arvore_colina"],
        np.column_stack([x[ok], y[ok], z[ok] - 0.8]),
        rng.uniform(1.25, 2.1, int(ok.sum())) * (1 + np.hypot(x[ok], y[ok]) / 1600),
        rng,
    )
    # coqueiros soltos ao longo do arrozal e na orla
    x, y = sortear(rng, 520, 80, 420, 50)
    z = altura(x, y)
    m = mascara_arrozal(x, y)
    ok = (z > 0.9) & (m < 0.6) & fora_da_vila(x, y) & fora_da_estrada(x, y)
    espalhar(
        "CoqueirosOrla",
        coqueiro_esguio(),
        np.column_stack([x[ok], y[ok], z[ok] - 0.15]),
        rng.uniform(0.62, 1.12, int(ok.sum())),
        rng,
    )
    x, y = sortear(rng, 1500, 60, 360, 54)
    z = altura(x, y)
    ok = (z > 0.8) & (mascara_arrozal(x, y) < 0.72) & fora_da_vila(x, y) & fora_da_estrada(x, y)
    idx = np.flatnonzero(ok)
    a, b = np.array_split(rng.permutation(idx), 2)
    espalhar(
        "BananeirasOrla",
        L.carregar("bananeira"),
        np.column_stack([x[a], y[a], z[a] - 0.05]),
        rng.uniform(1.0, 1.7, len(a)),
        rng,
    )
    espalhar(
        "ArbustosOrla",
        L.carregar("arbusto"),
        np.column_stack([x[b], y[b], z[b] - 0.05]),
        rng.uniform(1.2, 2.6, len(b)),
        rng,
    )


def construir_margens(f_capim, rng):
    """Capim nas margens da estrada: sem ele a terra termina numa borda reta."""
    y = np.arange(26.0, 126.0, 0.075)
    lado = rng.choice((-1.0, 1.0), len(y))
    x = estrada_x(y) + lado * (1.0 + 2.6 * rng.random(len(y)) ** 1.4)
    z = altura(x, y)
    ok = z > 0.25
    espalhar(
        "CapimEstrada",
        f_capim,
        np.column_stack([x[ok], y[ok], z[ok] - 0.03]),
        rng.uniform(0.55, 1.35, int(ok.sum())),
        rng,
        0.16,
    )


def construir_primeiro_plano(f_capim, rng):
    # capim no alto de onde a câmera olha
    x, y = sortear(rng, 30000, 9.0, 32, 42)
    z = altura(x, y)
    longe_posto = ((x - 6.8) / 3.6) ** 2 + ((y - 19.3) / 2.0) ** 2 > 1
    ok = (z > 1.0) & longe_posto
    espalhar(
        "CapimPerto",
        f_capim,
        np.column_stack([x[ok], y[ok], z[ok] - 0.03]),
        rng.uniform(0.5, 1.05, int(ok.sum())),
        rng,
        0.14,
    )
    # plantas maiores só nas laterais: o meio fica aberto para o arrozal
    x, y = sortear(rng, 320, 11.0, 31, 42)
    z = altura(x, y)
    longe_posto = ((x - 6.8) / 4.0) ** 2 + ((y - 19.3) / 2.5) ** 2 > 1
    ok = (z > 2.2) & longe_posto & ((x < -2.2) | (x > 9.0))
    idx = np.flatnonzero(ok)
    a, b = np.array_split(rng.permutation(idx), 2)
    espalhar(
        "SamambaiaPerto",
        L.carregar("taioba_samambaia"),
        np.column_stack([x[a], y[a], z[a] - 0.04]),
        rng.uniform(0.7, 1.4, len(a)),
        rng,
    )
    espalhar(
        "CapimAltoPerto",
        L.carregar("capim_elefante"),
        np.column_stack([x[b], y[b], z[b] - 0.04]),
        rng.uniform(0.6, 1.05, len(b)),
        rng,
    )
    # moldura escura à esquerda: bananeiras e copa de árvore
    for xb, yb, gi, e in (
        (-5.6, 13.6, 20, 1.3),
        (-7.6, 16.8, 130, 1.55),
        (-4.2, 18.2, 250, 1.1),
        (-10.8, 19.6, 60, 1.7),
    ):
        colocar("bananeira", xb, yb, gi, e, afunda=0.1)
    colocar("arvore_colina", -17.0, 26.0, 30, 2.1, afunda=0.25)
    colocar("arvore_dossel", -29.0, 37.0, 200, 1.15, afunda=0.25)
    colocar("arvore_dossel", -44.0, 66.0, 70, 1.25, afunda=0.25)


def construir_bruma(grupo):
    mat = C.novo_material("Bruma")
    nt = mat.node_tree
    nt.nodes.clear()
    saida = nt.nodes.new("ShaderNodeOutputMaterial")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    no = nt.nodes.new("ShaderNodeGroup")
    no.node_tree = grupo
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(no.outputs["Cor"], em.inputs["Color"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    esticar = nt.nodes.new("ShaderNodeVectorMath")
    esticar.operation = "MULTIPLY"
    ligar(nt, esticar.inputs[0], geo.outputs["Position"])
    esticar.inputs[1].default_value = (0.010, 0.010, 0.075)
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "faixa"
    forma = no_math(nt, "SINE", no_math(nt, "MULTIPLY", at.outputs[2], math.pi))
    forma = no_math(nt, "POWER", no_math(nt, "MAXIMUM", forma, 0.0), 1.6)
    trama = no_faixa(nt, no_ruido(nt, esticar.outputs[0], 1.0, 5.0, 0.55), 0.40, 0.68)
    at2 = nt.nodes.new("ShaderNodeAttribute")
    at2.attribute_name = "forca"
    fac = no_math(nt, "MULTIPLY", no_math(nt, "MULTIPLY", forma, trama), at2.outputs[2])
    mix = nt.nodes.new("ShaderNodeMixShader")
    ligar(nt, mix.inputs[0], fac)
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], saida.inputs["Surface"])
    # (distância, base, altura, força)
    for i, (d, z0, alt, forca) in enumerate(
        (
            (300.0, -2.0, 26.0, 0.42),
            (560.0, 0.0, 46.0, 0.55),
            (980.0, 4.0, 80.0, 0.46),
            (1750.0, 10.0, 150.0, 0.5),
            (3100.0, 30.0, 260.0, 0.5),
        )
    ):
        xs = np.linspace(-1.05 * d, 1.05 * d, 40)
        vs = np.linspace(0.0, 1.0, 17)
        X, V = np.meshgrid(xs, vs)
        Y = d + 0.08 * X * X / d + 0.02 * d * np.sin(X / d * 5 + i)
        Z = z0 + alt * V
        ob = malha_grade(f"Bruma{i}", X, Y, Z, {"faixa": V, "forca": np.full_like(V, forca)}, mat)
        for k in ("visible_shadow", "visible_diffuse", "visible_transmission"):
            setattr(ob, k, False)


# ------------------------------------------------------------------ câmera, luz e render
def montar_camera(cena):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = LENTE
    cd.sensor_width = 36.0
    cd.sensor_fit = "HORIZONTAL"
    cd.clip_start = 0.1
    cd.clip_end = 12000.0
    cd.shift_y = -(0.5 - HORIZONTE) * ALTURA / LARGURA
    cam = bpy.data.objects.new("Cam", cd)
    cena.collection.objects.link(cam)
    cam.location = CAM
    cam.rotation_euler = (math.pi / 2, 0.0, 0.0)
    cena.camera = cam


def montar_sol(cena):
    d = bpy.data.lights.new("Sol", "SUN")
    d.energy = 5.2
    d.color = (1.0, 0.60, 0.33)
    d.angle = math.radians(3.0)
    o = bpy.data.objects.new("Sol", d)
    cena.collection.objects.link(o)
    o.rotation_euler = (-direcao(*SOL_LUZ)).to_track_quat("-Z", "Y").to_euler()
    o.visible_camera = False
    o.visible_glossy = False
    d2 = bpy.data.lights.new("Preenchimento", "SUN")
    d2.energy = 0.75
    d2.color = (0.80, 0.66, 0.78)
    d2.angle = math.radians(40.0)
    o2 = bpy.data.objects.new("Preenchimento", d2)
    cena.collection.objects.link(o2)
    o2.rotation_euler = (-direcao(165.0, 24.0)).to_track_quat("-Z", "Y").to_euler()
    o2.visible_camera = False
    o2.visible_glossy = False


def configurar(cena, larg, alt, amostras):
    cena.render.engine = "CYCLES"
    C.usar_gpu(cena)
    cy = cena.cycles
    cy.samples = amostras
    cy.use_adaptive_sampling = True
    cy.adaptive_threshold = 0.025
    cy.use_denoising = True
    cy.denoiser = "OPENIMAGEDENOISE"
    cy.denoising_input_passes = "RGB_ALBEDO_NORMAL"
    cy.denoising_prefilter = "ACCURATE"
    cy.max_bounces = 6
    cy.diffuse_bounces = 2
    cy.glossy_bounces = 3
    cy.transmission_bounces = 2
    cy.volume_bounces = 0
    cy.transparent_max_bounces = 16
    cy.caustics_reflective = False
    cy.caustics_refractive = False
    cy.sample_clamp_indirect = 6.0
    cy.blur_glossy = 0.4
    cy.texture_limit_render = "1024"
    cena.render.use_simplify = True
    cena.render.simplify_subdivision_render = 0
    cena.render.resolution_x = larg
    cena.render.resolution_y = alt
    cena.render.resolution_percentage = 100
    cena.render.film_transparent = False
    cena.render.image_settings.file_format = "OPEN_EXR"
    cena.render.image_settings.color_mode = "RGB"
    cena.render.image_settings.color_depth = "32"
    cena.view_settings.view_transform = "Standard"
    cena.view_settings.look = "None"


# ------------------------------------------------------------------ revelação
def caixa_1d(a, raio, eixo):
    n = a.shape[eixo]
    borda = [(0, 0)] * a.ndim
    borda[eixo] = (raio + 1, raio)
    p = np.pad(a, borda, mode="edge")
    c = np.cumsum(p, axis=eixo)
    fim = np.take(c, np.arange(2 * raio + 1, n + 2 * raio + 1), axis=eixo)
    ini = np.take(c, np.arange(0, n), axis=eixo)
    return (fim - ini) / (2 * raio + 1)


def desfocar(a, raio):
    for _ in range(3):
        a = caixa_1d(caixa_1d(a, raio, 0), raio, 1)
    return a


def ampliar(a, h, w):
    y = np.linspace(0, a.shape[0] - 1, h)
    x = np.linspace(0, a.shape[1] - 1, w)
    y0, x0 = y.astype(np.int32), x.astype(np.int32)
    y1, x1 = np.minimum(y0 + 1, a.shape[0] - 1), np.minimum(x0 + 1, a.shape[1] - 1)
    ty, tx = (y - y0)[:, None, None], (x - x0)[None, :, None]
    return (a[y0][:, x0] * (1 - tx) + a[y0][:, x1] * tx) * (1 - ty) + (
        a[y1][:, x0] * (1 - tx) + a[y1][:, x1] * tx
    ) * ty


def aces(x):
    return np.clip((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0, 1)


def revelar(lin: np.ndarray) -> np.ndarray:
    """Linear (de cima para baixo) -> sRGB [0, 1], com a coluna do menu mais escura."""
    h, w = lin.shape[:2]
    escala = w / LARGURA
    lin = np.nan_to_num(np.clip(lin, 0, 40), posinf=40)
    # bloom em dois raios, calculado em 1/4 da resolução
    q = max(1, int(round(4 * escala)))
    hq, wq = h // q, w // q
    pequeno = lin[: hq * q, : wq * q].reshape(hq, q, wq, q, 3).mean(axis=(1, 3))
    forte = np.maximum(pequeno - 1.15, 0)
    b1 = desfocar(forte, max(1, int(5 * escala)))
    b2 = desfocar(forte, max(2, int(22 * escala)))
    lin = lin + ampliar(0.16 * b1 + 0.20 * b2, h, w) * np.array((1.0, 0.82, 0.62), np.float32)

    lin = lin * 0.92 * np.array((1.03, 0.995, 0.96), np.float32)
    srgb = C.linear_para_srgb(aces(lin))

    # curva suave e saturação
    srgb = srgb + 0.10 * (srgb - 0.5) * (1 - np.abs(2 * srgb - 1))
    cinza = (srgb * np.array((0.2126, 0.7152, 0.0722), np.float32)).sum(axis=2, keepdims=True)
    srgb = np.clip(cinza + (srgb - cinza) * 1.10, 0, 1)

    # coluna do menu: escurece até ~40% da largura, sem borda visível
    u = np.linspace(0, 1, w, dtype=np.float32)[None, :]
    v = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    coluna = 0.30 + 0.70 * sstep(0.10, 0.50, u + 0.035 * np.sin(v * 5.0))
    vinheta = 1 - 0.20 * sstep(0.45, 1.05, np.hypot((u - 0.58) * 1.05, (v - 0.48) * 0.85) * 1.6)
    baixo = 1 - 0.14 * sstep(0.84, 1.0, v)
    fator = (coluna * vinheta * baixo)[..., None]
    azul = np.array((0.92, 0.94, 1.02), np.float32)
    srgb = srgb * fator * (azul + (1 - azul) * sstep(0.2, 0.55, u)[..., None])

    # pontilhado de 1/2 nível: evita faixas no degradê do céu (é fixo, não treme)
    rng = np.random.default_rng(65)
    srgb = srgb + (rng.random((h, w, 1), np.float32) - 0.5) / 255
    return np.clip(srgb, 0, 1)


def gravar_png(srgb: np.ndarray, caminho: Path):
    h, w = srgb.shape[:2]
    img = bpy.data.images.new("fundo_lobby", w, h, alpha=False)
    rgba = np.concatenate([srgb[::-1], np.ones((h, w, 1), np.float32)], axis=2)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.update()
    caminho.parent.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(caminho)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def pos(exr: Path, saida: Path):
    img = bpy.data.images.load(str(exr))
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    lin = a.reshape(h, w, 4)[::-1, :, :3].copy()
    gravar_png(revelar(lin), saida)
    log("revelado", saida, w, h)


def _ler_exr(caminho: Path) -> np.ndarray:
    img = bpy.data.images.load(str(caminho), check_existing=False)
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)


def tira_roxo(lin: np.ndarray) -> np.ndarray:
    """O reflexo da água traz o céu antigo: o roxo vai para o rosa-âmbar, só abaixo da serra."""
    h = lin.shape[0]
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    soma = np.maximum(r + g + b, 1e-4)
    peso = np.clip(np.minimum(r - g, b - g) / soma * 9.0, 0, 1)
    peso = peso * sstep(0.30, 0.38, np.linspace(0, 1, h, dtype=np.float32)[:, None])
    g2 = g + peso * 0.42 * (np.minimum(r, b) - g)
    b2 = b - peso * 0.62 * (b - g2)
    return np.stack([r, g2, b2], axis=2)


def troca_ceu(cena, saida: Path):
    """Céu novo sem refazer a luz: render + (1 - alfa) x (céu novo - céu velho)."""
    velho = TRABALHO / "ceu_velho.exr"
    cy = cena.cycles
    cy.use_denoising = False
    cy.use_adaptive_sampling = False
    cy.max_bounces = 0
    cy.diffuse_bounces = 0
    cy.glossy_bounces = 0
    cena.render.image_settings.color_mode = "RGBA"
    cy.samples = 16
    cena.render.film_transparent = True
    alfa_exr = TRABALHO / "alfa.exr"
    cena.render.filepath = str(alfa_exr)
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    log("alfa", round(time.time() - t0, 1), "s")
    cena.render.film_transparent = False
    for o in cena.objects:
        if o.type != "CAMERA":
            o.hide_render = True
    cy.samples = 1
    novo_exr, velho_exr = TRABALHO / "ceu_vista_novo.exr", TRABALHO / "ceu_vista_velho.exr"
    cena.render.filepath = str(novo_exr)
    bpy.ops.render.render(write_still=True)
    tex = next(n for n in cena.world.node_tree.nodes if n.type == "TEX_IMAGE")
    tex.image = bpy.data.images.load(str(velho), check_existing=False)
    cena.render.filepath = str(velho_exr)
    bpy.ops.render.render(write_still=True)
    base = _ler_exr(TRABALHO / "final.exr")[..., :3]
    alfa = np.clip(_ler_exr(alfa_exr)[..., 3:4], 0, 1)
    novo, ant = _ler_exr(novo_exr)[..., :3], _ler_exr(velho_exr)[..., :3]
    lin = np.maximum(base + (1 - alfa) * (novo - ant), 0)[::-1].copy()
    gravar_png(revelar(tira_roxo(lin)), saida)
    log("céu trocado", saida)


def construir(cena, larg, alt, amostras):
    configurar(cena, larg, alt, amostras)
    rng = np.random.default_rng(1965)
    t0 = time.time()
    montar_mundo(cena, pintar_ceu())
    montar_camera(cena)
    montar_sol(cena)
    m_arroz = mat_folha("Arroz", (0.09, 0.27, 0.035, 1), (0.22, 0.42, 0.05, 1))
    m_capim = mat_folha("Capim", (0.045, 0.13, 0.025, 1), (0.16, 0.25, 0.05, 1))
    construir_chao(mat_chao())
    log("chão", round(time.time() - t0, 1), "s")
    _, _, _, f_capim = construir_terracos(mat_dique(), mat_agua(), m_arroz, m_capim, rng)
    log("terraços", round(time.time() - t0, 1), "s")
    construir_vila(rng)
    construir_posto()
    construir_mata(rng)
    construir_margens(f_capim, rng)
    construir_primeiro_plano(f_capim, rng)
    grupo = grupo_nevoa()
    for mat in bpy.data.materials:
        vestir_nevoa(mat, grupo)
    construir_bruma(grupo)
    log("cena pronta", round(time.time() - t0, 1), "s")


def principal():
    args = C.argumentos()
    teste = "--teste" in args
    amostras = int(args[args.index("--amostras") + 1]) if "--amostras" in args else 0
    amostras = amostras or (16 if teste else 160)
    saida = Path(args[args.index("--saida") + 1]) if "--saida" in args else SAIDA
    larg, alt = (640, 360) if teste else (LARGURA, ALTURA)
    if "--largura" in args:
        larg = int(args[args.index("--largura") + 1])
        alt = larg * 9 // 16
    TRABALHO.mkdir(parents=True, exist_ok=True)
    exr = TRABALHO / ("teste.exr" if teste else "final.exr")
    if "--so-pos" in args:
        pos(exr, saida)
        return
    C.cena_vazia()
    cena = bpy.context.scene
    construir(cena, larg, alt, amostras)
    if "--recorte" in args:
        # frações do quadro, com y de cima para baixo: confere um detalhe na resolução final
        i = args.index("--recorte")
        x0, y0, x1, y1 = (float(v) for v in args[i + 1 : i + 5])
        cena.render.use_border = True
        cena.render.use_crop_to_border = True
        cena.render.border_min_x, cena.render.border_max_x = x0, x1
        cena.render.border_min_y, cena.render.border_max_y = 1 - y1, 1 - y0
    if "--troca-ceu" in args:
        troca_ceu(cena, saida)
        return
    cena.render.filepath = str(exr)
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    log("render", round(time.time() - t0, 1), "s", larg, alt, amostras, "amostras")
    pos(exr, saida)


if __name__ == "__main__":
    principal()
