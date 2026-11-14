"""Etapa 2: imagem de comparação lado a lado (antigo × novo) em Cycles e silhueta.

Lê `assets/blender/<chave>/metricas.json` (gravado pela etapa 1) para saber o par:
- asset refeito: antigo = o GLB que o jogo usa (`*_fosco.glb`), com as texturas reduzidas a
  1024 px como o Roblox faz; novo = `assets/blender/<chave>/<chave>.glb`;
- asset novo: antigo = a versão "peças" (aproximação das peças do Roblox de MapLife/GrenadeArt,
  cor lisa) gravada pela etapa 1 em `_trabalho/<chave>/<chave>_pecas.glb`, ou o GLB do jogo
  indicado em `comparar_com`.

Os dois GLB entram pelo importador glTF do Blender (o que se vê é o que foi exportado), com face
única (fundo transparente atrás, como o Roblox: MeshPart sem DoubleSided), na mesma luz: céu do
jogo (HDRI do Poly Haven em `assets/ceu`) e um sol de 45°. São 2 ângulos (frente-esquerda e
trás-direita, 22° de elevação), com a câmera enquadrando o antigo. Saída: `comparacao.png`
(linha = ângulo, coluna = antigo | novo) e, no metricas.json, a sobreposição das silhuetas
(IoU, 1 = idênticas) em cada ângulo.

Uso:
    blender -b --factory-startup -P tools/blender/comparar.py -- <chave> [--amostras N]
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402

LARG, ALT = 960, 720
AZIMUTES = (40.0, 220.0)
ELEVACAO = 22.0
LENTE_MM = 50.0


def configurar(cena: bpy.types.Scene, amostras: int) -> None:
    cena.render.engine = "CYCLES"
    cena.cycles.samples = amostras
    cena.cycles.use_denoising = True
    try:
        cena.cycles.denoiser = "OPENIMAGEDENOISE" if C.so_cpu() else "OPTIX"
    except TypeError:
        cena.cycles.denoiser = "OPENIMAGEDENOISE"
    C.usar_gpu(cena)  # repõe CPU/linhas (VT65_CPU) depois de mexer na cena
    cena.cycles.max_bounces = 6
    cena.render.resolution_x = LARG
    cena.render.resolution_y = ALT
    cena.render.resolution_percentage = 100
    cena.render.image_settings.file_format = "PNG"
    cena.view_settings.view_transform = "AgX"
    for look in ("AgX - Medium High Contrast", "Medium High Contrast"):
        try:
            cena.view_settings.look = look
            break
        except TypeError:
            continue
    mundo = bpy.data.worlds.new("Ceu")
    cena.world = mundo
    nt = mundo.node_tree
    fundo = next(n for n in nt.nodes if n.type == "BACKGROUND")
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(str(C.CEU))
    nt.links.new(env.outputs["Color"], fundo.inputs["Color"])
    fundo.inputs["Strength"].default_value = 0.9


def sol(azimute: float) -> bpy.types.Object:
    luz = bpy.data.lights.new("Sol", "SUN")
    luz.energy = 3.2
    luz.angle = math.radians(1.5)
    luz.color = (1.0, 0.95, 0.88)
    o = bpy.data.objects.new("Sol", luz)
    bpy.context.scene.collection.objects.link(o)
    o.rotation_euler = (math.radians(45), 0.0, math.radians(azimute))
    return o


def material_chao() -> bpy.types.Material:
    m = C.novo_material("Chao")
    pr = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    pr.inputs["Base Color"].default_value = (0.16, 0.135, 0.105, 1.0)
    pr.inputs["Roughness"].default_value = 1.0
    return m


def face_unica(obj: bpy.types.Object) -> None:
    """Costas da face transparentes (o Roblox não desenha o verso de MeshPart sem DoubleSided)."""
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or mat.get("vt65_face_unica"):
            continue
        nt = mat.node_tree
        saida = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        if not saida.inputs["Surface"].is_linked:
            continue
        shader = saida.inputs["Surface"].links[0].from_socket
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(geo.outputs["Backfacing"], mix.inputs["Fac"])
        nt.links.new(shader, mix.inputs[1])
        nt.links.new(tr.outputs["BSDF"], mix.inputs[2])
        nt.links.new(mix.outputs["Shader"], saida.inputs["Surface"])
        mat["vt65_face_unica"] = True


def limitar_texturas(imagens, px: int = 1024) -> list:
    """Reduz as imagens maiores que `px` (o Roblox usa no máximo 1024)."""
    feitas = []
    for img in imagens:
        w, h = img.size
        if max(w, h) > px:
            img.scale(px, px)
            feitas.append([w, h])
    return feitas


def texto(cam, corpo: str, x: float, y: float, dist: float, tam: float) -> list:
    """Rótulo na frente da câmera (emissão, sem sombra), com faixa escura atrás."""
    curva = bpy.data.curves.new("rotulo", "FONT")
    curva.body = corpo
    fonte = Path("C:/Windows/Fonts/bahnschrift.ttf")
    if fonte.is_file():
        curva.font = bpy.data.fonts.load(str(fonte), check_existing=True)
    curva.size = tam
    t = bpy.data.objects.new("rotulo", curva)
    bpy.context.scene.collection.objects.link(t)
    m = C.novo_material("rotulo")
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    em.inputs["Strength"].default_value = 4.0
    saida = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    nt.links.new(em.outputs["Emission"], saida.inputs["Surface"])
    curva.materials.append(m)
    t.parent = cam
    t.location = (x, y, -dist)
    faixa_me = bpy.data.meshes.new("faixa")
    w = dist * 36 / LENTE_MM
    h = tam * 1.9
    x0, y0 = -w / 2, y - tam * 0.45
    faixa_me.from_pydata(
        [(x0, y0, 0), (x0 + w, y0, 0), (x0 + w, y0 + h, 0), (x0, y0 + h, 0)], [], [(0, 1, 2, 3)]
    )
    mf = C.novo_material("faixa")
    ntf = mf.node_tree
    prf = next(n for n in ntf.nodes if n.type == "BSDF_PRINCIPLED")
    ntf.nodes.remove(prf)
    emf = ntf.nodes.new("ShaderNodeEmission")
    emf.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    saidaf = next(n for n in ntf.nodes if n.type == "OUTPUT_MATERIAL")
    nt_tr = ntf.nodes.new("ShaderNodeBsdfTransparent")
    mix = ntf.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = 0.35
    ntf.links.new(emf.outputs["Emission"], mix.inputs[1])
    ntf.links.new(nt_tr.outputs["BSDF"], mix.inputs[2])
    ntf.links.new(mix.outputs["Shader"], saidaf.inputs["Surface"])
    faixa_me.materials.append(mf)
    f = bpy.data.objects.new("faixa", faixa_me)
    bpy.context.scene.collection.objects.link(f)
    f.parent = cam
    f.location = (0, 0, -dist * 1.001)
    for o in (t, f):
        for k in ("visible_diffuse", "visible_glossy", "visible_shadow", "visible_transmission"):
            setattr(o, k, False)
    return [t, f]


def pontos(objs, maximo: int = 6000) -> np.ndarray:
    """Vértices dos objetos (m), sorteados até `maximo`, para enquadrar pela silhueta."""
    todos = []
    for o in objs:
        co = np.empty(len(o.data.vertices) * 3, np.float64)
        o.data.vertices.foreach_get("co", co)
        todos.append(co.reshape(-1, 3))
    p = np.concatenate(todos)
    if len(p) > maximo:
        p = p[np.random.default_rng(65).choice(len(p), maximo, replace=False)]
    return p


def camera(lo, hi, azimute: float, pts: np.ndarray) -> tuple[bpy.types.Object, float]:
    """Câmera olhando o centro da caixa; a distância é a menor em que os vértices dos dois
    modelos cabem em 84% do quadro (a faixa do rótulo ocupa o alto). Enquadrar pelos vértices,
    e não pelos 8 cantos da caixa, deixa o modelo maior na imagem."""
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = LENTE_MM
    cam_d.sensor_width = 36
    cam_d.sensor_fit = "HORIZONTAL"
    cam = bpy.data.objects.new("Cam", cam_d)
    bpy.context.scene.collection.objects.link(cam)
    centro = Vector(((lo + hi) / 2).tolist())
    az, el = math.radians(azimute), math.radians(ELEVACAO)
    d = Vector((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az), math.sin(el)))
    rot = (-d).to_track_quat("-Z", "Y")
    rinv = np.array(rot.to_matrix().transposed())
    tan_h = 18 / LENTE_MM
    tan_v = tan_h * ALT / LARG
    c0 = np.array(centro)
    dv = np.array(d)

    def ocupa(dist: float) -> float:
        p = (pts - (c0 + dv * dist)) @ rinv.T
        z = -p[:, 2]
        if (z <= 1e-6).any():
            return 1e9
        # o alto do quadro tem a faixa do rótulo: o modelo fica abaixo dela (80% da meia altura)
        u = p[:, 1] / z / tan_v
        return float(
            max((np.abs(p[:, 0]) / z / tan_h).max() / 0.86, u.max() / 0.76, -u.min() / 0.92)
        )

    a, b = 1e-3, float(np.linalg.norm(hi - lo)) * 20
    for _ in range(60):
        m = (a + b) / 2
        if ocupa(m) > 1.0:
            a = m
        else:
            b = m
    dist = b
    cam.location = centro + d * dist
    cam.rotation_euler = rot.to_euler()
    cam_d.clip_start = max(0.001, dist * 0.005)
    cam_d.clip_end = dist * 50
    bpy.context.scene.camera = cam
    return cam, dist


def renderizar(caminho: Path) -> np.ndarray:
    cena = bpy.context.scene
    cena.render.filepath = str(caminho)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(caminho))
    a = C.pixels(img).copy()
    bpy.data.images.remove(img)
    return a


def main() -> None:
    a = C.argumentos()
    chave = a[0]
    amostras = int(a[a.index("--amostras") + 1]) if "--amostras" in a else 64
    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    trab.mkdir(parents=True, exist_ok=True)
    met = json.loads((pasta / "metricas.json").read_text("utf-8"))
    if met["tipo"] == "refeito":
        caminho_antigo = C.RAIZ / met["antigo"]["arquivo_jogo"]
        nome_antigo = "ANTIGO (jogo)"
    else:
        caminho_antigo = C.RAIZ / met["antigo"]["arquivo"]
        nome_antigo = met["antigo"].get("rotulo", "PEÇAS (Roblox)")
    caminho_novo = C.RAIZ / met["novo"]["arquivo"]

    cena = C.cena_vazia()
    configurar(cena, amostras)
    piso = C.chao(z=0.0)
    piso.data.materials.append(material_chao())
    antes = set(bpy.data.images)
    antigo = C.importar_glb(caminho_antigo)
    imgs_antigas = set(bpy.data.images)
    reduzidas = limitar_texturas(imgs_antigas - antes, 1024)
    novo = C.importar_glb(caminho_novo)
    novas = [i for i in bpy.data.images if i not in imgs_antigas]
    for o in (antigo, novo):
        face_unica(o)
    lo1, hi1 = C.caixa(antigo)
    lo2, hi2 = C.caixa(novo)
    lo, hi = np.minimum(lo1, lo2), np.maximum(hi1, hi2)

    def rot(m: dict) -> str:
        tex = m.get("texturas_px") or {}
        cor = tex.get("cor")
        tx = f"{cor[0]} px" if cor else "cor lisa"
        if m is met["antigo"] and met["tipo"] == "refeito":
            tx = f"{cor[0]} px (Roblox usa 1024)"
        pecas = f"{m['pecas']} peças · " if m.get("pecas") else ""
        return f"{m['triangulos']:,} tri · {pecas}{tx} · {m['mb']:.2f} MB".replace(",", ".")

    paineis = []
    ious = []
    pts = pontos([antigo, novo])
    for k, az in enumerate(AZIMUTES):
        cam, dist = camera(lo, hi, az, pts)
        s = sol(az + 70.0)
        d_txt = min(dist * 0.4, 1.0)
        tam = d_txt * 0.024
        x_txt = -d_txt * 36 / LENTE_MM / 2 + tam * 0.6
        y_txt = d_txt * 36 * ALT / LARG / LENTE_MM / 2 - tam * 1.6
        linha = []
        for nome, obj, m in (
            (nome_antigo, antigo, met["antigo"]),
            ("NOVO (Blender)", novo, met["novo"]),
        ):
            objs_txt = texto(cam, f"{nome} — {rot(m)}", x_txt, y_txt, d_txt, tam)
            antigo.hide_render = obj is not antigo
            novo.hide_render = obj is not novo
            linha.append(renderizar(trab / f"render_{k}_{'a' if obj is antigo else 'n'}.png"))
            for o in objs_txt:
                bpy.data.objects.remove(o)
        # silhuetas (alfa, sem chão)
        cena.render.film_transparent = True
        piso.hide_render = True
        cena.cycles.samples = 1
        cena.cycles.use_denoising = False
        cena.render.resolution_percentage = 50
        mascaras = []
        for obj in (antigo, novo):
            antigo.hide_render = obj is not antigo
            novo.hide_render = obj is not novo
            mascaras.append(renderizar(trab / f"mascara_{k}.png")[..., 3] > 0.5)
        inter = np.logical_and(*mascaras).sum()
        uniao = np.logical_or(*mascaras).sum()
        ious.append(round(float(inter / max(1, uniao)), 4))
        cena.render.film_transparent = False
        piso.hide_render = False
        cena.cycles.samples = amostras
        cena.cycles.use_denoising = True
        cena.render.resolution_percentage = 100
        bpy.data.objects.remove(cam)
        bpy.data.objects.remove(s)
        paineis.append(linha)

    sep = 6
    h, w = ALT, LARG
    total = np.ones((2 * h + sep, 2 * w + sep, 4), np.float32)
    total[..., :3] = 0.08
    for i, linha in enumerate(paineis):
        for j, p in enumerate(linha):
            # pixels do Blender começam embaixo: a linha 0 (ângulo 1) vai em cima
            y0 = (1 - i) * (h + sep)
            x0 = j * (w + sep)
            total[y0 : y0 + h, x0 : x0 + w] = p
    out = bpy.data.images.new("comparacao", total.shape[1], total.shape[0], alpha=False)
    C.gravar_pixels(out, total)
    C.salvar_imagem(out, pasta / "comparacao.png", "PNG")
    C.gravar_json(
        pasta / "metricas.json",
        {
            "comparacao": {
                "imagem": f"assets/blender/{chave}/comparacao.png",
                "silhueta_iou": ious,
                "angulos_azimute_graus": list(AZIMUTES),
                "elevacao_graus": ELEVACAO,
                "amostras_cycles": amostras,
                "texturas_antigas_reduzidas_de": reduzidas,
                "texturas_novas_px": [list(i.size) for i in novas],
            }
        },
    )
    C.log("ok", chave, "iou", ious)


if __name__ == "__main__":
    main()
