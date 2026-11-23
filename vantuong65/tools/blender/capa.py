"""Capa e ícone do jogo (thumbnail do Roblox 1920 × 1080 e ícone 512 × 512), em Cycles, com os
assets do próprio projeto: as casas da vila (`assets/blender/vila_casa_*` e as refeitas), coqueiros,
bambu e bananeiras do ForgeGUI, árvores do Poly Haven (`assets/arvores`), o arrozal (cartões de
`assets/arroz` e o `rice_patch`), os helicópteros UH-34D, o M48A3, e soldados em silhueta (o R15 de
`assets/mocap/soldado/soldado.blend` com as caixas arredondadas, o capacete M1 e o M14 do jogo).

Fim de tarde (sol a ~6° de altura, por trás da vila, a câmera contra a luz), névoa baixa e fumaça.
Sem texto na imagem (o título entra depois, por `tools/capa_titulo.py`). Sem bandeira nem
insígnia em destaque: helicópteros e tanque ficam contra a luz.

Saídas (`assets/capa/`):
- `capa_1920x1080.png` (composição cheia);
- `capa_espaco_titulo_1920x1080.png` (câmera virada: a vila à direita, o terço esquerdo livre);
- `icone_512.png` (capacete M1 numa estaca do dique, contra o pôr do sol, arrozal desfocado).

Uso:
    blender -b --factory-startup -P tools/blender/capa.py -- capa [--amostras N] [--teste]
    blender -b --factory-startup -P tools/blender/capa.py -- titulo [--amostras N] [--teste]
    blender -b --factory-startup -P tools/blender/capa.py -- icone [--amostras N] [--teste]
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import modelar as M  # noqa: E402
import vila_comum as V  # noqa: E402
from modelar import Mat, rgb  # noqa: E402

RAIZ = C.RAIZ
FG = RAIZ / "assets" / "forgegui" / "models"
BL = RAIZ / "assets" / "blender"
SAIDA = RAIZ / "assets" / "capa"
BRUTO = RAIZ / "assets" / "blender" / "_trabalho" / "capa"
STUD = C.M_POR_STUD
SOL_ELEV = 6.0  # graus
SOL_AZ = -14.0  # graus a partir de +Y (o sol fica atrás da vila, um pouco à esquerda)


def log(*a):
    print("[VT65]", *a, flush=True)


def primeiro(*caminhos: Path) -> Path | None:
    for c in caminhos:
        if c.is_file():
            return c
    return None


# =============================================================== importação
_cache: dict[str, bpy.types.Object] = {}


def carregar(caminho: Path, nome: str | None = None) -> bpy.types.Object:
    """GLB do jogo (studs) em metros, sem os nós de colisão, juntado num objeto (materiais
    mantidos). O original fica escondido e serve de fonte para as instâncias."""
    chave = str(caminho)
    if chave in _cache:
        return _cache[chave]
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(caminho))
    novos = [o for o in bpy.data.objects if o not in antes]
    malhas = [o for o in novos if o.type == "MESH" and not o.name.startswith(("Colisao_", "Zona_"))]
    for o in malhas:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy() if o.data.users > 1 else o.data
        o.data.transform(Matrix.Scale(STUD, 4) @ mw)
        o.matrix_world = Matrix.Identity(4)
    for o in novos:
        if o not in malhas:
            bpy.data.objects.remove(o)
    obj = malhas[0]
    if len(malhas) > 1:
        C.selecionar_so(obj, malhas)
        with bpy.context.temp_override(active_object=obj, selected_editable_objects=malhas):
            bpy.ops.object.join()
    obj.name = nome or caminho.stem
    obj.hide_render = True
    obj.hide_viewport = True
    _cache[chave] = obj
    lo, hi = C.caixa(obj)
    log(
        "carregado",
        caminho.name,
        "dim",
        [round(float(x), 2) for x in hi - lo],
        "tri",
        C.triangulos(obj),
    )
    return obj


def instancia(fonte, pos, rot_z=0.0, escala=1.0, rot=None) -> bpy.types.Object:
    o = fonte.copy()
    o.hide_render = False
    o.hide_viewport = False
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(pos)
    o.rotation_euler = Euler(rot) if rot is not None else Euler((0.0, 0.0, math.radians(rot_z)))
    o.scale = (escala, escala, escala) if isinstance(escala, int | float) else escala
    return o


# =============================================================== materiais
def mat_agua():
    """Água rasa e barrenta do arrozal: escura, quase espelho (reflete o céu do fim de tarde),
    com ondinhas de vento e manchas de lodo e lentilha."""
    m = Mat("agua_arrozal", rug=0.06)
    p = m.coord("objeto")
    lodo = m.faixa(m.ruido(p, 0.08, 4), 0.55, 0.7)
    cor = m.misturar(lodo, rgb("#1d1c16"), rgb("#3b3a26"))
    m.cor(cor)
    m.rug(m.misturar_valor(lodo, 0.04, 0.45))
    ond = m.ruido(m.mapear(p, (1.0, 2.5, 1.0)), 6.0, 3, 0.5)
    m.relevo(ond, 0.08, 0.01)
    m.pr.inputs["IOR"].default_value = 1.33
    return m.m


def mat_terra_campo():
    m = Mat("terra_campo", rug=0.95)
    p = m.coord("objeto")
    cor = m.rampa(m.ruido(p, 0.25, 5), [(0.3, rgb("#3d3423")), (0.7, rgb("#5a5233"))])
    capim = m.faixa(m.ruido(p, 0.6, 4), 0.45, 0.6)
    cor = m.misturar(capim, cor, rgb("#4c5a2c"))
    m.cor(cor)
    m.relevo(m.ruido(p, 8.0, 4), 0.4, 0.05)
    return m.m


def mat_fumaca(densidade=0.35, cor="#5e5953"):
    """Fumaça de queimada: volume com densidade por ruído, mais rala em cima e nas bordas."""
    mat = bpy.data.materials.new("fumaca")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    saida = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = rgb(cor)
    vol.inputs["Anisotropy"].default_value = 0.55
    tc = nt.nodes.new("ShaderNodeTexCoord")
    ru = nt.nodes.new("ShaderNodeTexNoise")
    ru.inputs["Scale"].default_value = 2.2
    ru.inputs["Detail"].default_value = 8.0
    ru.inputs["Roughness"].default_value = 0.6
    ru.inputs["Distortion"].default_value = 0.6
    nt.links.new(tc.outputs["Generated"], ru.inputs["Vector"])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    # raio a partir do eixo (x, y em 0..1, centro 0,5) e altura z
    cx = nt.nodes.new("ShaderNodeMath")
    cx.operation = "SUBTRACT"
    nt.links.new(sep.outputs["X"], cx.inputs[0])
    cx.inputs[1].default_value = 0.5
    cy = nt.nodes.new("ShaderNodeMath")
    cy.operation = "SUBTRACT"
    nt.links.new(sep.outputs["Y"], cy.inputs[0])
    cy.inputs[1].default_value = 0.5
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(cx.outputs[0], comb.inputs["X"])
    nt.links.new(cy.outputs[0], comb.inputs["Y"])
    comp = nt.nodes.new("ShaderNodeVectorMath")
    comp.operation = "LENGTH"
    nt.links.new(comb.outputs["Vector"], comp.inputs[0])
    borda = nt.nodes.new("ShaderNodeMapRange")
    borda.inputs["From Min"].default_value = 0.5
    borda.inputs["From Max"].default_value = 0.12
    nt.links.new(comp.outputs["Value"], borda.inputs["Value"])
    alto = nt.nodes.new("ShaderNodeMapRange")
    alto.inputs["From Min"].default_value = 1.0
    alto.inputs["From Max"].default_value = 0.2
    nt.links.new(sep.outputs["Z"], alto.inputs["Value"])
    nuvem = nt.nodes.new("ShaderNodeMapRange")
    nuvem.inputs["From Min"].default_value = 0.42
    nuvem.inputs["From Max"].default_value = 0.72
    nt.links.new(ru.outputs["Factor"], nuvem.inputs["Value"])
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    nt.links.new(borda.outputs["Result"], m1.inputs[0])
    nt.links.new(alto.outputs["Result"], m1.inputs[1])
    m2 = nt.nodes.new("ShaderNodeMath")
    m2.operation = "MULTIPLY"
    nt.links.new(m1.outputs[0], m2.inputs[0])
    nt.links.new(nuvem.outputs["Result"], m2.inputs[1])
    m3 = nt.nodes.new("ShaderNodeMath")
    m3.operation = "MULTIPLY"
    nt.links.new(m2.outputs[0], m3.inputs[0])
    m3.inputs[1].default_value = densidade
    nt.links.new(m3.outputs[0], vol.inputs["Density"])
    nt.links.new(vol.outputs["Volume"], saida.inputs["Volume"])
    return mat


def mat_nevoa(densidade=0.012):
    """Névoa baixa sobre o arrozal (volume uniforme que rareia com a altura)."""
    mat = bpy.data.materials.new("nevoa")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    saida = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = rgb("#d9c4a6")
    vol.inputs["Anisotropy"].default_value = 0.7
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = 1.0
    mr.inputs["To Min"].default_value = densidade
    mr.inputs["To Max"].default_value = densidade * 0.15
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], vol.inputs["Density"])
    nt.links.new(vol.outputs["Volume"], saida.inputs["Volume"])
    return mat


def mat_disco_rotor():
    """Disco de borrão do rotor: escuro e bem transparente, mais denso na ponta das pás."""
    mat = bpy.data.materials.new("disco_rotor")
    mat.use_nodes = True
    nt = mat.node_tree
    pr = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    pr.inputs["Base Color"].default_value = rgb("#1b1b19")
    pr.inputs["Roughness"].default_value = 0.6
    tc = nt.nodes.new("ShaderNodeTexCoord")
    gr = nt.nodes.new("ShaderNodeTexGradient")
    gr.gradient_type = "SPHERICAL"
    nt.links.new(tc.outputs["Object"], gr.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = 0.25
    mr.inputs["To Min"].default_value = 0.16
    mr.inputs["To Max"].default_value = 0.05
    nt.links.new(gr.outputs["Factor"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], pr.inputs["Alpha"])
    return mat


# =============================================================== mundo e luz
def ceu_e_sol(cena, forca_ceu=1.0):
    """Céu físico do Blender (sol a SOL_ELEV graus) e um sol de luz quente na mesma direção."""
    mundo = bpy.data.worlds.new("Ceu")
    cena.world = mundo
    nt = mundo.node_tree
    fundo = next(n for n in nt.nodes if n.type == "BACKGROUND")
    sky = nt.nodes.new("ShaderNodeTexSky")
    for tipo in ("MULTIPLE_SCATTERING", "NISHITA", "SINGLE_SCATTERING"):
        try:
            sky.sky_type = tipo
            break
        except TypeError:
            continue
    # sun_rotation: 0 = sol em +Y, cresce para +X (conferido num panorama do céu)
    for k, v in (
        ("sun_elevation", math.radians(SOL_ELEV)),
        ("sun_rotation", math.radians(SOL_AZ) % (2 * math.pi)),
        ("altitude", 30.0),
        ("air_density", 1.4),
        ("aerosol_density", 4.0),
        ("ozone_density", 1.0),
        ("sun_disc", True),
        ("sun_size", math.radians(1.6)),
        ("sun_intensity", 0.5),
    ):
        if hasattr(sky, k):
            try:
                setattr(sky, k, v)
            except (TypeError, AttributeError):
                pass
    # tom de fim de tarde: o céu físico a 3-6° ainda sai azul-claro em cima; puxa para o laranja
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.75
    ent = [s for s in mix.inputs if s.type == "RGBA"]
    nt.links.new(sky.outputs["Color"], ent[0])
    ent[1].default_value = (1.0, 0.62, 0.40, 1.0)
    nt.links.new(next(s for s in mix.outputs if s.type == "RGBA"), fundo.inputs["Color"])
    fundo.inputs["Strength"].default_value = forca_ceu
    luz = bpy.data.lights.new("Sol", "SUN")
    luz.energy = 3.6
    luz.angle = math.radians(1.5)
    luz.color = (1.0, 0.52, 0.27)
    sol = bpy.data.objects.new("Sol", luz)
    cena.collection.objects.link(sol)
    el, az = math.radians(SOL_ELEV), math.radians(SOL_AZ)
    para_sol = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
    sol.rotation_euler = (-para_sol).to_track_quat("-Z", "Y").to_euler()
    log("sky_type", getattr(sky, "sky_type", "?"))
    return sol


def configurar(cena, larg, alt, amostras):
    cena.render.engine = "CYCLES"
    C.usar_gpu(cena)
    if not C.so_cpu():
        # o driver deste PC é velho para o OptiX (o Cycles cai na CPU sem erro): força CUDA
        prefs = bpy.context.preferences.addons["cycles"].preferences
        try:
            prefs.compute_device_type = "CUDA"
            prefs.get_devices()
            for d in prefs.devices:
                d.use = d.type == "CUDA"
            cena.cycles.device = "GPU"
        except TypeError:
            cena.cycles.device = "CPU"
    log("dispositivo", cena.cycles.device)
    cena.cycles.samples = amostras
    cena.cycles.use_denoising = True
    try:
        cena.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        cena.cycles.denoiser = "OPENIMAGEDENOISE"
    cena.cycles.max_bounces = 8
    cena.cycles.volume_bounces = 1
    cena.cycles.volume_step_rate = 4.0
    cena.render.resolution_x = larg
    cena.render.resolution_y = alt
    cena.render.resolution_percentage = 100
    cena.render.image_settings.file_format = "PNG"
    cena.view_settings.view_transform = "AgX"
    for look in ("AgX - Punchy", "AgX - Medium High Contrast", "Punchy", "Medium High Contrast"):
        try:
            cena.view_settings.look = look
            break
        except TypeError:
            continue


def camera(cena, pos, alvo, lente=35.0, shift_x=0.0, foco=None, f_stop=None, sensor=36.0):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lente
    cd.sensor_width = sensor
    cd.sensor_fit = "HORIZONTAL"
    cd.shift_x = shift_x
    cd.clip_start = 0.05
    cd.clip_end = 3000
    if foco is not None:
        cd.dof.use_dof = True
        cd.dof.focus_distance = foco
        cd.dof.aperture_fstop = f_stop or 2.8
    cam = bpy.data.objects.new("Cam", cd)
    cena.collection.objects.link(cam)
    cam.location = Vector(pos)
    cam.rotation_euler = (Vector(alvo) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
    cena.camera = cam
    return cam


# =============================================================== cenário
def mat_dique():
    """Barro do dique (bờ ruộng): lama escura e molhada no pé, terra no meio, capim em cima."""
    m = Mat("dique", rug=0.9)
    p = m.coord("objeto")
    nz = m.separar(m.no("ShaderNodeNewGeometry").outputs["Normal"])[2]
    _, _, z = m.separar(p)
    cor = m.rampa(m.ruido(p, 1.5, 5), [(0.3, rgb("#2f271d")), (0.7, rgb("#4f402d"))])
    fios = m.ruido(m.mapear(p, (30, 30, 4)), 1.0, 4)
    capim = m.conta("MULTIPLY", m.faixa(nz, 0.75, 0.95), m.faixa(m.ruido(p, 2.5, 3), 0.3, 0.55))
    cor = m.misturar(
        capim, cor, m.misturar(m.faixa(fios, 0.3, 0.7), rgb("#3e4a22"), rgb("#6a6b34"))
    )
    molhado = m.faixa(z, 0.16, 0.06)
    cor = m.misturar(molhado, cor, rgb("#1e1912"))
    m.cor(cor)
    m.rug(m.misturar_valor(molhado, 0.92, 0.35))
    m.relevo(m.conta("ADD", m.ruido(p, 12.0, 4), m.conta("MULTIPLY", fios, capim)), 0.5, 0.02)
    return m.m


def dique(nome, pontos, mat, topo=0.55, base=1.35, alt=0.34, sem=0, z0=0.0):
    """Bờ ruộng: dique de terra de seção trapezoidal, levemente torto, com bordas comidas."""
    rng = np.random.default_rng(sem)
    pts = []
    for a, b in zip(pontos[:-1], pontos[1:], strict=True):
        a, b = Vector(a), Vector(b)
        n = max(2, int((b - a).length / 1.2))
        for i in range(n):
            pts.append(a.lerp(b, i / n))
    pts.append(Vector(pontos[-1]))
    desv = np.cumsum(rng.normal(0, 0.05, len(pts)))
    perfil = [
        (-base / 2, 0.0),
        (-base / 2 + 0.12, alt * 0.45),
        (-topo / 2, alt),
        (0.0, alt * 1.04),
        (topo / 2, alt),
        (base / 2 - 0.12, alt * 0.45),
        (base / 2, 0.0),
    ]

    def f(u, v):
        i = min(len(pts) - 2, int(u * (len(pts) - 1)))
        t = u * (len(pts) - 1) - i
        p = pts[i].lerp(pts[i + 1], t)
        d = (pts[i + 1] - pts[i]).normalized()
        lado = Vector((-d.y, d.x, 0.0))
        k = v * (len(perfil) - 1)
        j = min(len(perfil) - 2, int(k))
        s = k - j
        w = perfil[j][0] * (1 - s) + perfil[j + 1][0] * s
        h = perfil[j][1] * (1 - s) + perfil[j + 1][1] * s
        off = desv[min(len(desv) - 1, i)]
        q = p + lado * (w + off)
        q.z = z0 + h * (0.85 + 0.15 * M.ruido(q * 0.7, sem))
        return q

    o = V.grade(nome, f, max(4, (len(pts) - 1) * 3), (len(perfil) - 1) * 2, fora=(0, 0, 1))
    M.deslocar(o, lambda co, nn: 0.035 * M.fbm(co * 1.3, 3, sem) * max(0.0, nn.z))
    M.material(o, mat)
    M.suave(o, 70)
    return o


def plano(nome, x0, y0, x1, y1, z, mat):
    me = bpy.data.meshes.new(nome)
    me.from_pydata([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    return o


def volume_caixa(nome, centro, dim, mat):
    o = M.caixa(nome, dim, (0, 0, 0))
    o.location = Vector(centro)
    M.material(o, mat)
    return o


def soldados(cena, posicoes):
    """Soldados do jogo em silhueta: o R15 (soldado.blend) num quadro do trote, com as caixas
    trocadas por caixas arredondadas (silhueta menos quadrada), o capacete M1 e o M14 do jogo.
    `posicoes` = [(pos, rot_z, quadro)]."""
    caminho = RAIZ / "assets" / "mocap" / "soldado" / "soldado.blend"
    if not caminho.is_file():
        log("sem soldado.blend")
        return []
    with bpy.data.libraries.load(str(caminho), link=False) as (de, para):
        para.objects = [n for n in de.objects if n.startswith(("caixa_", "Soldado_R15"))]
        para.actions = list(de.actions)
    arm = next(o for o in para.objects if o.type == "ARMATURE")
    caixas = [o for o in para.objects if o.type == "MESH"]
    capacete = carregar(
        primeiro(FG / "capacete_m1_studs_fosco.glb", FG / "capacete_m1_studs.glb"), "capacete"
    )
    fuzil = carregar(primeiro(FG / "m14_studs_parker.glb", FG / "m14_studs.glb"), "m14")
    pano = Mat("farda", rug=0.9)
    pano.cor(rgb("#363a29"))
    acao = bpy.data.actions.get("trote")
    saida = []
    for k, (pos, rot_z, quadro) in enumerate(posicoes):
        a = arm.copy()
        a.data = arm.data.copy()
        cena.collection.objects.link(a)
        a.animation_data_create()
        a.animation_data.action = acao
        try:
            if acao.slots:
                a.animation_data.action_slot = acao.slots[0]
        except AttributeError:
            pass
        filhos = []
        for cx in caixas:
            c = cx.copy()
            dim = Vector(cx.dimensions)
            if "Head" in cx.name:
                dim *= 0.78
            elif "Torso" not in cx.name:
                dim = Vector((dim.x * 0.8, dim.y * 0.8, dim.z))
            tmp = M.superelipsoide(f"s{k}_{cx.name}", 0.5, 0.5, 0.5, 0.4, 0.4, 16, 10)
            me = tmp.data
            bpy.data.objects.remove(tmp)
            lo, hi = C.caixa(cx)
            centro = (Vector(lo.tolist()) + Vector(hi.tolist())) / 2
            me.transform(Matrix.Translation(centro) @ Matrix.Diagonal((*dim, 1.0)))
            c.data = me
            c.data.materials.clear()
            c.data.materials.append(pano.m)
            c.parent = a
            cena.collection.objects.link(c)
            filhos.append(c)
        esc = 1.85 / 5.9
        a.location = Vector(pos)
        a.rotation_euler = (0.0, 0.0, math.radians(rot_z))
        a.scale = (esc, esc, esc)
        cena.frame_set(quadro)
        bpy.context.view_layer.update()
        cabeca = next((c for c in filhos if "Head" in c.name), None)
        if cabeca is not None:
            bb = [cabeca.matrix_world @ Vector(v) for v in cabeca.bound_box]
            zs = [v.z for v in bb]
            cen = sum(bb, Vector()) / 8
            h = instancia(
                capacete, (cen.x, cen.y, min(zs) + (max(zs) - min(zs)) * 0.38), rot_z + 180, 1.35
            )
            saida.append(h)
        mao = next((c for c in filhos if "RightHand" in c.name), None)
        if mao is not None:
            p = sum((mao.matrix_world @ Vector(v) for v in mao.bound_box), Vector()) / 8
            f = instancia(
                fuzil, p, rot=(math.radians(-40), math.radians(10), math.radians(rot_z + 90))
            )
            saida.append(f)
        saida += [a, *filhos]
    for o in para.objects:
        bpy.data.objects.remove(o)
    return saida


LUGARES_CASAS = {
    # (x, y, giro): a vila numa faixa de 20 a 70 m, de frente para o arrozal; o dique do caminho
    # leva à vila_casa_03 (a de telha, com varanda)
    "vila_casa_05": (-27.0, 21.0, 9),
    "vila_casa_01": (-9.0, 23.0, -5),
    "vila_casa_03": (11.0, 25.0, 4),
    "vila_casa_07": (30.0, 23.0, -9),
    "vila_casa_02": (47.0, 26.0, 12),
    "vila_casa_09": (-19.0, 43.0, 14),
    "vila_casa_06": (1.0, 46.0, -6),
    "vila_casa_10": (20.0, 45.0, 8),
    "vila_casa_04": (38.0, 45.0, -12),
    "vila_casa_08": (56.0, 47.0, 5),
    "hut_thatch": (-34.0, 64.0, 20),
    "house_tile": (-12.0, 66.0, -10),
    "hut_veranda": (10.0, 68.0, 6),
    "granary": (30.0, 64.0, -15),
    "straw_stack": (-4.0, 34.0, 0),
    "shrine": (22.0, 34.5, 180),
    "well": (-17.0, 32.0, 0),
}


def montar_cena(cena, teste=False):
    """Arrozal com diques em primeiro plano, a vila com as casas no meio, coqueiros e bambu entre
    elas, a mata e os morros atrás, helicópteros e tanque contra a luz e fumaça."""
    rng = np.random.default_rng(65)
    terra = mat_terra_campo()
    agua = mat_agua()
    md = mat_dique()
    plano("chao", -600, -300, 600, 900, 0.0, terra)
    plano("agua", -260, -70, 200, 14.0, 0.07, agua)
    ys = (-70.0, -48.0, -33.0, -21.0, -10.0, 1.0, 14.0)
    xs = (-260.0, -170.0, -120.0, -80.0, -48.0, -26.0, 16.0, 36.0, 62.0, 96.0, 140.0, 200.0)
    for k, y in enumerate(ys[1:]):
        dique(f"dq_x{k}", [(-260, y, 0), (200, y + rng.normal(0, 0.6), 0)], md, sem=k)
    for k, x in enumerate(xs[1:-1]):
        dique(
            f"dq_y{k}",
            [(x, -70, 0), (x + rng.normal(0, 1.2), 14, 0)],
            md,
            topo=0.45,
            base=1.1,
            sem=20 + k,
        )
    dique(
        "dq_caminho",
        [(-2.6, -50.0, 0), (-1.2, -30.0, 0), (1.5, -12.0, 0), (5.0, 0.0, 0), (8.0, 14.0, 0)],
        md,
        topo=0.9,
        base=1.9,
        alt=0.42,
        sem=99,
    )
    # arroz: perto, touceiras 3D (rice_patch); longe, ladrilhos de cartões; algumas quadras só água
    patch = carregar(BL / "rice_patch" / "rice_patch.glb", "rice_patch")
    tile = carregar(RAIZ / "assets" / "arroz" / "arroz_alto.glb", "arroz_alto")
    lo, hi = C.caixa(tile)
    passo = float(max(hi[0] - lo[0], hi[1] - lo[1])) * 0.9
    n_p = n_t = 0
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            x0, x1 = xs[i] + 0.9, xs[i + 1] - 0.9
            y0, y1 = ys[j] + 0.9, ys[j + 1] - 0.9
            if x1 < -140 or x0 > 160:
                continue
            sorte = rng.random()
            perto = y1 < -8 and -60 < x0 < 50 and x1 > -60
            caminho = x0 < 0.0 < x1  # quadra cortada pelo dique do caminho
            if sorte < (0.5 if perto else 0.3) and not caminho:
                continue  # quadra alagada: espelho d'água
            if perto:
                dens = 0.55 if sorte < 0.65 and not caminho else 1.0
                for x in np.arange(x0 + 0.6, x1 - 0.6, 1.5):
                    for y in np.arange(y0 + 0.5, y1 - 0.5, 1.05):
                        # à esquerda do caminho fica a água (espelho); arroz só à direita
                        x_cam = -2.6 + (y + 50.0) * (4.1 / 38.0)
                        if caminho and x < x_cam + 1.3:
                            continue
                        if rng.random() > dens or (teste and rng.random() < 0.5):
                            continue
                        instancia(
                            patch,
                            (x + rng.normal(0, 0.12), y + rng.normal(0, 0.1), 0.05),
                            rng.uniform(-12, 12),
                            (1.0, 1.0, rng.uniform(0.8, 1.15)),
                        )
                        n_p += 1
            else:
                alt = rng.uniform(0.75, 1.05)
                for x in np.arange(x0, x1 - passo * 0.5, passo):
                    for y in np.arange(y0, y1 - passo * 0.5, passo):
                        if teste and rng.random() < 0.5:
                            continue
                        instancia(
                            tile,
                            (x + passo / 2, y + passo / 2, 0.05),
                            rng.uniform(0, 360),
                            (1.12, 1.12, alt),
                        )
                        n_t += 1
    log("arroz: touceiras", n_p, "ladrilhos", n_t)
    # vila
    usados = []
    n_novas = 0
    for chave, (x, y, r) in LUGARES_CASAS.items():
        arq = BL / chave / f"{chave}.glb"
        if not arq.is_file():
            continue
        fonte = carregar(arq)
        instancia(fonte, (x, y, 0.0), r)
        lo, hi = C.caixa(fonte)
        usados.append((x, y, float(np.linalg.norm((hi - lo)[:2])) * 0.45))
        n_novas += chave.startswith("vila_casa")
    log("casas na vila", len(usados), "novas", n_novas)
    coqueiro = carregar(
        primeiro(FG / "coqueiro_studs_fosco.glb", FG / "coqueiro_studs.glb"), "coqueiro"
    )
    bambu = carregar(
        primeiro(FG / "bambu_touceira_studs_fosco.glb", FG / "bambu_touceira_studs.glb"), "bambu"
    )
    banana = carregar(
        primeiro(FG / "bananeira_studs_fosco.glb", FG / "bananeira_studs.glb"), "bananeira"
    )
    arvores = [
        carregar(RAIZ / "assets" / "arvores" / f"{n}.glb")
        for n in ("ph_island_tree_01", "ph_island_tree_02", "ph_island_tree_03", "ph_tree_small_02")
    ]

    def livre(x, y, r=2.5):
        return all((x - a) ** 2 + (y - b) ** 2 > (r + ra) ** 2 for a, b, ra in usados)

    n = 0
    while n < 30:
        x, y = rng.uniform(-50, 70), rng.uniform(28, 85)
        if livre(x, y):
            instancia(coqueiro, (x, y, 0), rng.uniform(0, 360), rng.uniform(0.9, 1.35))
            n += 1
    for _ in range(14):
        x, y = rng.uniform(-55, 75), rng.uniform(30, 80)
        if livre(x, y, 3.5):
            instancia(bambu, (x, y, 0), rng.uniform(0, 360), rng.uniform(1.0, 1.4))
    for _ in range(16):
        x, y = rng.uniform(-40, 60), rng.uniform(26, 70)
        if livre(x, y, 2.0):
            instancia(banana, (x, y, 0), rng.uniform(0, 360), rng.uniform(0.8, 1.1))
    for k in range(80 if not teste else 30):
        instancia(
            arvores[k % len(arvores)],
            (rng.uniform(-280, 280), rng.uniform(80, 230), 0),
            rng.uniform(0, 360),
            rng.uniform(2.0, 3.2),
        )
    for x, y in ((-70, 14.5), (-55, 1.2), (-96, 14.0), (78, 14.5), (60, 1.5), (-130, 14.2)):
        instancia(coqueiro, (x, y, 0.25), rng.uniform(0, 360), rng.uniform(1.05, 1.35))
    for k, (x, y, sx, sz) in enumerate(
        ((-200, 560, 280, 80), (70, 640, 320, 110), (300, 520, 220, 60))
    ):
        mo = M.superelipsoide(f"morro{k}", sx, 90, sz, 0.9, 1.0, 48, 16)
        M.deslocar(mo, lambda co, nn, k=k: 6.0 * M.fbm(co * 0.02, 4, k))
        mo.location = (x, y, -sz * 0.15)
        M.material(mo, terra)
    # helicópteros (contra o céu), tanque e Ontos num dique
    heli = primeiro(BL / "uh34d" / "uh34d.glb", FG / "uh34d_studs.glb")
    disco = mat_disco_rotor()
    if heli is not None:
        h = carregar(heli, "uh34d")
        lo, hi = C.caixa(h)
        for pos, rz, inc, rol in (
            ((21.0, 30.0, 15.0), -70, 7, -6),
            ((46.0, 56.0, 25.0), -76, 5, -4),
        ):
            instancia(h, pos, rot=(math.radians(inc), math.radians(rol), math.radians(rz)))
            r = 8.5  # rotor de ~17 m (o GLB tem 17,7 m de ponta a ponta)
            d = M.torno("disco", [(0.0, 0.0), (r, 0.0), (r, 0.01), (0.0, 0.01)], segs=48)
            M.material(d, disco)
            d.location = Vector(pos) + Vector((0, 0, float(hi[2] - lo[2]) * 0.93))
            d.rotation_euler = (math.radians(inc), math.radians(rol), 0.0)
    tanque = primeiro(BL / "m48a3" / "m48a3.glb", FG / "m48a3_studs.glb")
    if tanque is not None:
        instancia(carregar(tanque, "m48a3"), (19.5, 1.6, 0.36), -140)
    ontos = primeiro(BL / "ontos" / "ontos.glb")
    if ontos is not None:
        instancia(carregar(ontos, "ontos"), (33.0, 14.6, 0.34), -100)
    # fumaça (queimada atrás da vila) e névoa rasa
    for k, (x, y, h, r, dens) in enumerate(
        ((14, 66, 48, 8, 0.5), (36, 72, 60, 10, 0.6), (-22, 70, 34, 6, 0.4))
    ):
        f = volume_caixa(
            f"fumaca{k}",
            (x + h * 0.22, y, h / 2),
            (r * 2 + h * 0.45, r * 2, h),
            mat_fumaca(dens, "#4a4540"),
        )
        f.rotation_euler = (0.0, math.radians(-10), 0.0)
    volume_caixa("nevoa", (0, 210, 2.5), (900, 480, 5), mat_nevoa(0.0025))


def principal():
    a = C.argumentos()
    modo = a[0] if a else "capa"
    amostras = int(a[a.index("--amostras") + 1]) if "--amostras" in a else 160
    teste = "--teste" in a
    SAIDA.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cena = bpy.context.scene
    if modo == "icone":
        return icone(cena, amostras, teste)
    larg, alt = (960, 540) if teste else (1920, 1080)
    if modo == "ambas":
        # uma imagem 20% mais larga cobre os dois enquadramentos (capa e capa com espaço para o
        # título, que é a mesma câmera com o quadro deslocado 20% para a esquerda); o
        # tools/capa_titulo.py --graduar recorta as duas. Mesmo ângulo por pixel: sensor x 1,2.
        larg = int(larg * 1.2)
    configurar(cena, larg, alt, amostras)
    global SOL_ELEV, SOL_AZ
    SOL_ELEV, SOL_AZ = 5.2, -3.0
    ceu_e_sol(cena, 1.15)
    montar_cena(cena, teste)
    # dois soldados de costas no dique do caminho, andando para a vila (contra o sol)
    soldados(cena, [((-1.5, -33.5, 0.44), 180, 5), ((3.2, -21.0, 0.36), 150, 14)])
    if modo == "ambas":
        camera(
            cena,
            (-2.35, -49.0, 1.72),
            (6.5, 30.0, 5.5),
            lente=30.0,
            shift_x=-0.1 / 1.2,
            sensor=36.0 * 1.2,
        )
        nome = "capa_larga.png"
    elif modo == "capa":
        camera(cena, (-2.35, -49.0, 1.72), (6.5, 30.0, 5.5), lente=30.0)
        nome = "capa_1920x1080.png"
    else:
        camera(cena, (-2.35, -49.0, 1.72), (6.5, 30.0, 5.5), lente=30.0, shift_x=-0.2)
        nome = "capa_espaco_titulo_1920x1080.png"
    if teste:
        nome = "teste_" + nome
    # render bruto: a graduação de cor final (curva, vinheta) é do tools/capa_titulo.py --graduar
    BRUTO.mkdir(parents=True, exist_ok=True)
    cena.render.filepath = str(BRUTO / nome)
    bpy.ops.render.render(write_still=True)
    log("ok", nome)


def icone(cena, amostras, teste):
    """Ícone: capacete M1 numa estaca de bambu no dique, contra o pôr do sol, com o arrozal, a vila
    e um helicóptero desfocados atrás (lê-se pequeno: silhueta forte e céu laranja)."""
    px = 256 if teste else 512
    configurar(cena, px, px, amostras)
    global SOL_ELEV, SOL_AZ
    SOL_ELEV, SOL_AZ = 6.0, -12.0
    ceu_e_sol(cena, 1.2)
    terra = mat_terra_campo()
    agua = mat_agua()
    md = mat_dique()
    plano("chao", -600, -300, 600, 900, 0.0, terra)
    plano("agua", -200, -20, 200, 60, 0.07, agua)
    dique(
        "dq",
        [(-0.4, -6.0, 0), (0.0, 0.0, 0), (1.5, 30.0, 0)],
        md,
        topo=0.9,
        base=1.9,
        alt=0.42,
        sem=3,
    )
    dique("dq2", [(-200, 16, 0), (200, 16.5, 0)], md, sem=4)
    tile = carregar(RAIZ / "assets" / "arroz" / "arroz_alto.glb", "arroz_alto")
    patch = carregar(BL / "rice_patch" / "rice_patch.glb", "rice_patch")
    rng = np.random.default_rng(5)
    for x in np.arange(-6, 6, 1.5):
        for y in np.arange(0.8, 7.0, 1.05):
            if abs(x) < 1.3:
                continue
            instancia(patch, (x, y, 0.05), rng.uniform(-10, 10))
    lo, hi = C.caixa(tile)
    passo = float(max(hi[0] - lo[0], hi[1] - lo[1])) * 0.9
    for x in np.arange(-60, 60, passo):
        for y in np.arange(7.5, 15.0, passo):
            instancia(tile, (x, y, 0.05), rng.uniform(0, 360), (1.12, 1.12, 1.0))
    coqueiro = carregar(
        primeiro(FG / "coqueiro_studs_fosco.glb", FG / "coqueiro_studs.glb"), "coqueiro"
    )
    for x, y in ((-10, 30), (13, 36), (-26, 44), (32, 50), (4, 58)):
        instancia(coqueiro, (x, y, 0.2), 30.0 * x, 1.25)
    casa = primeiro(BL / "vila_casa_01" / "vila_casa_01.glb", BL / "hut_thatch" / "hut_thatch.glb")
    if casa is not None:
        instancia(carregar(casa), (-5.0, 34.0, 0.0), 10)
    heli = primeiro(BL / "uh34d" / "uh34d.glb", FG / "uh34d_studs.glb")
    if heli is not None:
        instancia(
            carregar(heli, "uh34d"),
            (-4.0, 58.0, 19.0),
            rot=(math.radians(6), math.radians(-8), math.radians(-70)),
        )
    estaca = V.tre(
        "estaca", (0.05, 0.0, 0.3), (0.075, 0.0, 1.2), 0.028, V.mat_tre("tre_estaca"), segs=10
    )
    estaca.hide_render = False
    cap = carregar(
        primeiro(FG / "capacete_m1_studs_fosco.glb", FG / "capacete_m1_studs.glb"), "capacete"
    )
    lo, hi = C.caixa(cap)
    instancia(
        cap,
        (0.08, 0.0, 1.32 - float(hi[2] - lo[2]) * 0.62),
        rot=(math.radians(7), math.radians(-5), math.radians(200)),
        escala=1.0,
    )
    volume_caixa("nevoa", (0, 120, 2.5), (600, 220, 5), mat_nevoa(0.006))
    camera(cena, (0.44, -1.12, 1.03), (0.07, 0.0, 1.19), lente=70.0, foco=1.18, f_stop=2.2)
    nome = ("teste_" if teste else "") + "icone_512.png"
    BRUTO.mkdir(parents=True, exist_ok=True)
    cena.render.filepath = str(BRUTO / nome)
    bpy.ops.render.render(write_still=True)
    log("ok", nome)


if __name__ == "__main__":
    principal()
