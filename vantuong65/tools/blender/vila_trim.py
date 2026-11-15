"""Trim sheet da vila (D-156): prova no Blender, sem mexer no jogo.

O texto do dono pede trim sheets: uma folha de materiais dividida por muitos objetos. Hoje cada casa
da vila tem 3 atlas próprios de 1024 (Telhado, Casa e Mobília), assados de uma versão detalhada
(`vila.py`). O grupo Casa (paredes, piso, estrutura e anexos) da vila_casa_03 já é leve (2.194
triângulos) e usa 6 materiais procedurais com o atributo `local` em metros (ao longo, altura,
através), o que serve de mapa para uma folha:
- cada material das paredes, da estrutura e dos anexos é assado UMA vez numa faixa que repete na
  horizontal (a costura sai por mistura das pontas); 5 faixas numa folha de 1024;
- o piso vira uma textura de 512 que repete nos dois sentidos;
- as faces da casa vão para a faixa do seu material pelo `local`: parede com V = altura; madeira,
  bambu e barro com U ao longo do veio (o maior lado) e V através.
Telhado e mobília ficam com os atlas de hoje. A prévia mostra a casa original (GLB de hoje) e a
convertida com as mesmas câmeras.

Uso: blender -b --factory-startup -P tools/blender/vila_trim.py -- vila_casa_03
"""

from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comparar as K  # noqa: E402
import comum as C  # noqa: E402
import vila  # noqa: E402
import vila_comum as V  # noqa: E402

FOLHA_PX = 1024
SLOT_PX = 204  # 5 faixas de 204 px (sobra 4 no alto)
BORDA_PX = 6  # repete a linha da beira (o mipmap não mistura faixas vizinhas tão cedo)
FAIXA_PX = SLOT_PX - 2 * BORDA_PX  # 192 px de conteúdo
PISO_PX = 512
EXTRA = 0.25  # assa 25% a mais na horizontal para a costura
# material -> (modo, altura da faixa em m). Parede: V = altura (o pé molhado e o escorrido ficam no
# lugar); veio: U ao longo do maior lado, V através
PAREDE = {"gach", "vach_dat", "phen", "trinh", "vach"}
H_PAREDE = 3.2
H_VEIO = 0.8
PISO_M = 4.0  # o piso repete a cada 4 m
SAIDA = C.SAIDA / "trim_vila"


def plano(nome: str, larg: float, alt: float, y: float = 0.0) -> bpy.types.Object:
    """Quadrado vertical no plano XZ, de frente para -Y, com UV 0..1."""
    me = bpy.data.meshes.new(nome)
    me.from_pydata([(0, y, 0), (larg, y, 0), (larg, y, alt), (0, y, alt)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for li, (u, v) in zip(range(4), ((0, 0), (1, 0), (1, 1), (0, 1)), strict=True):
        uv.data[li].uv = (u, v)
    obj = bpy.data.objects.new(nome, me)
    C.nova_colecao_objeto(obj)
    return obj


def imagem(nome: str, w: int, h: int, dados: bool) -> bpy.types.Image:
    img = bpy.data.images.new(nome, w, h, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if dados else "sRGB"
    return img


def assar_plano(cena, mat, larg: float, alt: float, w: int, h: int, local) -> dict:
    """Cor, normal e rugosidade do material num plano larg x alt (m), em imagens w x h."""
    alto = plano("alto", larg, alt)
    alto.data.materials.append(mat)
    V.gravar_uv_local(alto, local)
    baixo = plano("baixo", larg, alt, y=-0.01)
    C.material_alvo(baixo)
    imgs = {"cor": imagem("cor", w, h, False), "normal": imagem("n", w, h, True)}
    imgs["rug"] = imagem("rug", w, h, True)
    C.assar_escalar(cena, baixo, [alto], "Base Color", imgs["cor"], 0.03, margem=0)
    C.assar(cena, baixo, [alto], "NORMAL", imgs["normal"], 0.03, margem=0)
    C.assar(cena, baixo, [alto], "ROUGHNESS", imgs["rug"], 0.03, margem=0)
    out = {k: C.pixels(img).copy() for k, img in imgs.items()}
    for img in imgs.values():
        bpy.data.images.remove(img)
    for o in (alto, baixo):
        bpy.data.objects.remove(o)
    return out


def costura(a: np.ndarray, w: int, eixo: int, normal: bool) -> np.ndarray:
    """Corta em `w` px no eixo (1 = horizontal, 0 = vertical) misturando o trecho a mais com o
    começo: a ponta final continua no começo (repete sem costura)."""
    o = a.shape[eixo] - w
    if eixo == 1:
        out = a[:, :w].copy()
        t = (np.arange(o) / o)[None, :, None]
        out[:, :o] = t * a[:, :o] + (1 - t) * a[:, w : w + o]
    else:
        out = a[:w].copy()
        t = (np.arange(o) / o)[:, None, None]
        out[:o] = t * a[:o] + (1 - t) * a[w : w + o]
    if normal:
        n = out[..., :3] * 2 - 1
        n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-8
        out[..., :3] = (n + 1) / 2
    return out


def materiais_casa(r) -> tuple[list[str], str | None]:
    faixas, piso = [], None
    for o in r.objs:
        if o["grupo"] != "Casa" or o.get("so_bake") or not o.active_material:
            continue
        nome = o.active_material.name
        if o["no"] == "Piso":
            piso = nome
        elif nome not in faixas:
            faixas.append(nome)
    return faixas, piso


def montar_folha(cena, faixas: list[str]) -> tuple[dict, dict]:
    assert len(faixas) * SLOT_PX <= FOLHA_PX, f"{len(faixas)} faixas não cabem na folha"
    folha = {
        "cor": np.zeros((FOLHA_PX, FOLHA_PX, 4), np.float32),
        "normal": np.zeros((FOLHA_PX, FOLHA_PX, 4), np.float32),
        "rug": np.ones((FOLHA_PX, FOLHA_PX, 4), np.float32),
    }
    folha["normal"][..., :] = (0.5, 0.5, 1.0, 1.0)
    folha["cor"][..., 3] = 1.0
    layout = {}
    w_extra = int(round(FOLHA_PX * (1 + EXTRA)))
    for i, nome in enumerate(faixas):
        h_m = H_PAREDE if nome in PAREDE else H_VEIO
        comp_m = FOLHA_PX * h_m / FAIXA_PX  # mesma densidade nos dois sentidos
        t0 = time.time()
        m = assar_plano(
            cena,
            bpy.data.materials[nome],
            comp_m * (1 + EXTRA),
            h_m,
            w_extra,
            FAIXA_PX,
            lambda p: (p.x, p.z, 0.0),
        )
        s0 = i * SLOT_PX
        for k, a in m.items():
            b = costura(a, FOLHA_PX, 1, k == "normal")
            folha[k][s0 + BORDA_PX : s0 + BORDA_PX + FAIXA_PX] = b
            folha[k][s0 : s0 + BORDA_PX] = b[0]
            folha[k][s0 + BORDA_PX + FAIXA_PX : s0 + SLOT_PX] = b[-1]
        layout[nome] = {
            "faixa": i,
            "modo": "parede" if nome in PAREDE else "veio",
            "altura_m": h_m,
            "comprimento_m": round(comp_m, 3),
            "px_por_m": round(FAIXA_PX / h_m, 1),
            "s": round(time.time() - t0, 1),
        }
        C.log("faixa", nome, layout[nome])
    return folha, layout


def montar_piso(cena, nome: str, chao_local) -> dict:
    lado = PISO_M * (1 + EXTRA)
    px = int(round(PISO_PX * (1 + EXTRA)))
    m = assar_plano(cena, bpy.data.materials[nome], lado, lado, px, px, chao_local)
    return {
        k: costura(costura(a, PISO_PX, 1, k == "normal"), PISO_PX, 0, k == "normal")
        for k, a in m.items()
    }


def locais(obj) -> np.ndarray:
    a = obj.data.attributes["local"].data
    v = np.empty(len(a) * 3, np.float32)
    a.foreach_get("vector", v)
    return v.reshape(-1, 3).astype(np.float64)


def uv_folha(obj, info: dict) -> None:
    """UV 'trim' na faixa do material, pelo `local` de cada vértice."""
    loc = locais(obj)
    me = obj.data
    uv = me.uv_layers.new(name="trim")
    h_m, comp = info["altura_m"], info["comprimento_m"]
    v0 = (info["faixa"] * SLOT_PX + BORDA_PX) / FOLHA_PX
    dv = FAIXA_PX / FOLHA_PX
    lo, hi = loc.min(axis=0), loc.max(axis=0)
    for poly in me.polygons:
        vs = [me.loops[li].vertex_index for li in poly.loop_indices]
        c = loc[vs]
        span = c.max(axis=0) - c.min(axis=0)
        if info["modo"] == "parede":
            vax = 1
            uax = 0 if span[0] >= span[2] else 2
            base, alcance = 0.0, max(hi[1], h_m)
        else:
            ordem = np.argsort(-span)
            uax, vax = int(ordem[0]), int(ordem[1])
            base, alcance = lo[vax], max(hi[vax] - lo[vax], 1e-6)
        esc = min(1.0, h_m / alcance) if alcance > h_m else 1.0
        for li, vi in zip(poly.loop_indices, vs, strict=True):
            vv = np.clip((loc[vi, vax] - base) * esc, 0.0, h_m)
            uv.data[li].uv = (loc[vi, uax] / comp, v0 + vv / h_m * dv)
    me.uv_layers.active = uv


def uv_piso(obj, eixos: tuple[int, int]) -> None:
    loc = locais(obj)
    me = obj.data
    uv = me.uv_layers.new(name="trim")
    for li, lp in enumerate(me.loops):
        p = loc[lp.vertex_index]
        uv.data[li].uv = (p[eixos[0]] / PISO_M, p[eixos[1]] / PISO_M)
    me.uv_layers.active = uv


def material_imagens(nome: str, mapas: dict, px: int) -> bpy.types.Material:
    mat = C.novo_material(nome)
    nt = mat.node_tree
    pr = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "trim"
    for k, entrada in (("cor", "Base Color"), ("rug", "Roughness"), ("normal", None)):
        img = imagem(f"{nome}_{k}", px, px, k != "cor")
        C.gravar_pixels(img, mapas[k])
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = img
        nt.links.new(uvn.outputs["UV"], tx.inputs["Vector"])
        if entrada == "Roughness":
            nt.links.new(tx.outputs["Color"], pr.inputs["Roughness"])
        elif entrada:
            nt.links.new(tx.outputs["Color"], pr.inputs[entrada])
        else:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.uv_map = "trim"
            nt.links.new(tx.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], pr.inputs["Normal"])
    return mat


def salvar(mapas: dict, prefixo: str, px: int) -> None:
    for k, a in mapas.items():
        img = imagem(f"salvar_{prefixo}_{k}", px, px, k != "cor")
        C.gravar_pixels(img, a)
        C.salvar_imagem(img, SAIDA / f"{prefixo}_{k}.png", "PNG")
        bpy.data.images.remove(img)


def renderizar_paineis(objs: list, met: dict, pasta: Path, nome: str) -> list[np.ndarray]:
    """As 3 vistas do `vila.previa` (fora a 35° e 215°, dentro pela câmera da receita)."""
    cena = bpy.context.scene
    pts = K.pontos(objs, 8000)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    paineis = []
    cena.view_settings.exposure = 0.0
    for k, az in enumerate((35.0, 215.0)):
        cam, _ = K.camera(lo, hi, az, pts)
        s = K.sol(az + 70.0)
        paineis.append(K.renderizar(pasta / f"{nome}_{k}.png"))
        bpy.data.objects.remove(cam)
        bpy.data.objects.remove(s)
    cd = met["previa"]["camera_dentro_m"]
    pos, alvo = Vector(cd[0]), Vector(cd[1])
    cam_d = bpy.data.cameras.new("CamDentro")
    cam_d.lens = 17.0
    cam_d.sensor_width = 36
    cam_d.clip_start = 0.05
    cam = bpy.data.objects.new("CamDentro", cam_d)
    cena.collection.objects.link(cam)
    cam.location = pos
    cam.rotation_euler = (alvo - pos).to_track_quat("-Z", "Y").to_euler()
    cena.camera = cam
    porta = next((p for p in met["portas"] if not p["interna"]), None)
    az = 0.0
    if porta is not None:
        nr = porta["normal_para_fora_roblox"]
        az = math.degrees(math.atan2(-nr[0], -nr[2]))
    luz = bpy.data.lights.new("SolDentro", "SUN")
    luz.energy = 3.4
    luz.angle = math.radians(2.0)
    s = bpy.data.objects.new("SolDentro", luz)
    cena.collection.objects.link(s)
    s.rotation_euler = (math.radians(62), 0.0, math.radians(az + 20))
    area = bpy.data.lights.new("Preenche", "AREA")
    area.shape = "DISK"
    area.size = 3.0
    area.energy = 260.0
    ao = bpy.data.objects.new("Preenche", area)
    cena.collection.objects.link(ao)
    meio = (pos + alvo) / 2
    ao.location = (meio.x, meio.y, V.PISO + 2.45)
    cena.view_settings.exposure = 1.0
    paineis.append(K.renderizar(pasta / f"{nome}_dentro.png"))
    for o in (cam, s, ao):
        bpy.data.objects.remove(o)
    return paineis


def main() -> None:
    chave = C.argumentos()[0]
    t0 = time.time()
    SAIDA.mkdir(parents=True, exist_ok=True)
    trab = C.TRABALHO / f"trim_{chave}"
    trab.mkdir(parents=True, exist_ok=True)
    met = json.loads((C.SAIDA / chave / "metricas.json").read_text("utf-8"))
    cena = C.cena_vazia()
    C.preparar_bake(cena)
    C.log("dispositivo", vila.gpu_cuda(cena))
    r, _ = vila.montar(chave)
    faixas, piso = materiais_casa(r)
    C.log("faixas", faixas, "piso", piso)
    folha, layout = montar_folha(cena, faixas)
    chao = next(o for o in r.objs if o["grupo"] == "Casa" and o["no"] == "Piso")
    loc = locais(chao)
    span = loc.max(axis=0) - loc.min(axis=0)
    eixos = tuple(int(i) for i in np.argsort(-span)[:2])
    fixo = int(np.argsort(-span)[2])
    valor_fixo = float(np.median(loc[:, fixo]))

    def chao_local(p):
        out = [0.0, 0.0, 0.0]
        out[eixos[0]], out[eixos[1]], out[fixo] = p.x, p.z, valor_fixo
        return tuple(out)

    mapas_piso = montar_piso(cena, piso, chao_local)
    salvar(folha, "folha", FOLHA_PX)
    salvar(mapas_piso, "piso", PISO_PX)
    mat_folha = material_imagens("trim_folha", folha, FOLHA_PX)
    mat_piso = material_imagens("trim_piso", mapas_piso, PISO_PX)
    # casa convertida: as peças do grupo Casa (sem as só de bake) com a UV da folha
    convertidas = []
    for o in r.objs:
        if o["grupo"] != "Casa" or o.get("so_bake"):
            o.hide_render = True
            continue
        nome = o.active_material.name
        if o["no"] == "Piso":
            uv_piso(o, eixos)
            o.data.materials.clear()
            o.data.materials.append(mat_piso)
        else:
            uv_folha(o, layout[nome])
            o.data.materials.clear()
            o.data.materials.append(mat_folha)
        convertidas.append(o)
    # prévia: o GLB de hoje inteiro x o GLB de hoje sem as peças do grupo Casa + as convertidas
    K.configurar(cena, 40)
    try:
        cena.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    cena.render.resolution_x, cena.render.resolution_y = vila.LARG, vila.ALT
    K.LARG, K.ALT = vila.LARG, vila.ALT
    piso_cena = C.chao(z=0.0, tamanho=400.0)
    piso_cena.data.materials.append(K.material_chao())
    originais = vila.importar_visual(C.RAIZ / met["novo"]["arquivo"])
    for o in originais + convertidas:
        K.face_unica(o)
    casa_nos = {"Paredes", "Piso", "Estrutura", "Anexos"}
    for o in convertidas:
        o.hide_render = True
    antes = renderizar_paineis(originais, met, trab, "antes")
    for o in originais:
        if o.name.split(".")[0] in casa_nos:
            o.hide_render = True
    for o in convertidas:
        o.hide_render = False
    visiveis = [o for o in originais if not o.hide_render] + convertidas
    depois = renderizar_paineis(visiveis, met, trab, "depois")
    alt, larg, sep = vila.ALT, vila.LARG, 6
    total = np.ones((2 * alt + sep, 3 * larg + 2 * sep, 4), np.float32)
    total[..., :3] = 0.08
    for j in range(3):
        x0 = j * (larg + sep)
        total[alt + sep :, x0 : x0 + larg] = antes[j]  # linha de cima (a imagem cresce para cima)
        total[:alt, x0 : x0 + larg] = depois[j]
    out = bpy.data.images.new("previa_trim", total.shape[1], total.shape[0], alpha=False)
    C.gravar_pixels(out, total)
    C.salvar_imagem(out, SAIDA / f"previa_{chave}.png", "PNG")
    tris = sum(C.triangulos(o) for o in convertidas)
    C.gravar_json(
        SAIDA / "medidas.json",
        {
            "chave": chave,
            "faixas": layout,
            "piso": {"material": piso, "repete_m": PISO_M, "px": PISO_PX},
            "folha_px": FOLHA_PX,
            "pecas_convertidas": len(convertidas),
            "triangulos_convertidos": tris,
            "previa": f"assets/blender/trim_vila/previa_{chave}.png",
            "previa_obs": "linha de cima: GLB de hoje (atlas próprio); de baixo: grupo Casa com a "
            "folha (paredes, estrutura e anexos) e o piso repetido. Telhado e mobília iguais.",
            "tempo_s": round(time.time() - t0, 1),
        },
    )
    C.log(
        "ok",
        chave,
        "convertidas",
        len(convertidas),
        "tris",
        tris,
        "em",
        round(time.time() - t0, 1),
        "s",
    )


if __name__ == "__main__":
    main()
