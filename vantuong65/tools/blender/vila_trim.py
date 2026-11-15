"""Trim sheet da vila (D-156, D-159): as 10 casas únicas dividem 3 folhas e um piso.

Hoje cada casa traz 3 atlas próprios de 1024 (Telhado, Casa e Mobília), assados de uma versão
detalhada (`vila.py`). O grupo Casa (paredes, piso, estrutura e anexos) é leve e usa materiais
procedurais com o atributo `local` em metros, o que serve de mapa para uma folha comum:
- cada material é assado UMA vez numa faixa que repete na horizontal (costura por mistura);
- três folhas de 1024: M (madeira, bambu, esteira e o pote), W (as paredes de barro, cal,
  tijolo e taipa) e O (esteira e tábua de parede, mais faixas pela metade para terra, rede,
  ferro, pedra, resina e o tijolo do terreiro); o piso é uma textura de 512 que repete nos dois
  sentidos;
- as faces de cada casa vão para a faixa do seu material: parede com V = altura; madeira e
  bambu com U ao longo do veio; o pote com V = altura do pote; o piso de tijolo cortado em
  fileiras.

Saídas (assets/blender, fora do Git):
- `trim_vila/`: as folhas, `layout.json`, `vila_trim.glb` (o "portador": um cubo por folha com a
  textura, de onde o jogo clona a SurfaceAppearance) e as prévias;
- `<casa>/<casa>_trim.glb`: o GLB da casa com Telhado, Mobília e colisão iguais e o grupo Casa
  trocado pelos nós `Trim_M`, `Trim_W`, `Trim_O` e `Trim_P`, sem textura (só a cor média, caso o
  portador falte). O `metricas.json` da casa passa a apontar para ele (o de antes fica em
  `antes_trim`).

Uso:
    blender -b --factory-startup -P tools/blender/vila_trim.py -- folhas
    blender -b --factory-startup -P tools/blender/vila_trim.py -- vila_casa_03 [--sem-previa]
"""

from __future__ import annotations

import json
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comparar as K  # noqa: E402
import comum as C  # noqa: E402
import glb  # noqa: E402
import vila  # noqa: E402
import vila_comum as V  # noqa: E402

FOLHA_PX = 1024
BORDA_PX = 6  # repete a linha da beira (o mipmap não mistura faixas vizinhas tão cedo)
PISO_PX = 512
PISO_M = 4.0  # o piso repete a cada 4 m
EXTRA = 0.25  # assa 25% a mais na horizontal para a costura
H_PAREDE = 3.2
H_VEIO = 0.8
SAIDA = C.SAIDA / "trim_vila"
TESTES = C.RAIZ / "testes" / "trim"
FOLHAS = ("M", "W", "O")
NO_PISO = "Trim_P"

# (faixa, folha, modo de UV na casa, mapa do bake, px de conteúdo)
# modo: "parede" (V = altura do `local`), "veio" (U ao longo do maior lado), "pote" (V = altura
# do objeto). Bake: "uz" = local (x, z, 0); "veio" = (z, 0, x), o veio do `local` (3º) ao longo
# de U; "trama" = (x, z + 1, 0), a esteira sem o pé escurecido de parede.
FAIXAS = (
    ("go", "M", "veio", "veio", 192),
    ("go_escuro", "M", "veio", "veio", 192),
    ("tre", "M", "veio", "veio", 192),
    ("phen", "M", "veio", "trama", 192),
    ("barro_escuro", "M", "pote", "uz", 192),
    ("vach_dat", "W", "parede", "uz", 192),
    ("vach_dat_exposta", "W", "parede", "uz", 192),
    ("vach_cal", "W", "parede", "uz", 192),
    ("gach", "W", "parede", "uz", 192),
    ("trinh", "W", "parede", "uz", 192),
    ("phen_par", "O", "parede", "uz", 192),
    ("van", "O", "parede", "uz", 192),
    ("dat", "O", "veio", "uz", 90),
    ("luoi", "O", "veio", "uz", 90),
    ("ferro", "O", "veio", "uz", 90),
    ("pedra", "O", "veio", "uz", 90),
    ("resina", "O", "veio", "trama", 90),
    ("san", "O", "ladrilho", "uz", 90),
)
# piso de tijolo do terreiro (vila_casa_10): a peça é cortada em fileiras de 0,78 m (6 pares de
# fiadas de 0,065 m) e cada fileira começa no pé da faixa; a amarração continua na emenda
LADRILHO_M = 0.78
# material da casa -> faixa, quando o nome não é o da faixa. A cor de cada casa variava pouco
# (±6% no catálogo, `Mats`); muro e reboco de tijolo ficam no mesmo tijolo (exposto 0,35)
TROCA = {"muro": "gach", "cinza": "ferro", "esteira": "phen"}
TROCA_CASA = {"vila_casa_05": {"vach_dat": "vach_dat_exposta"}}
CASAS = tuple(f"vila_casa_{k:02d}" for k in range(1, 11))


def materiais_folha() -> dict[str, bpy.types.Material]:
    """Os materiais de cada faixa (o catálogo da vila_casa_03 e as paredes de cada casa)."""
    ms = V.Mats(3)
    return {
        "san": V.mat_gach("f_san", reboco="#8f877a", escuro="#6f685d", exposto=3.0),
        "go": ms.go,
        "go_escuro": ms.go_escuro,
        "tre": ms.tre,
        "phen": ms.phen,
        "barro_escuro": ms.barro_escuro,
        "vach_dat": V.mat_vach_dat("f_vach_dat", exposta=0.4),
        "vach_dat_exposta": V.mat_vach_dat(
            "f_vach_dat_exposta", "#7f6447", "#55402c", "#9a7d5a", exposta=0.85
        ),
        "vach_cal": V.mat_vach_dat("f_vach_cal", cal="#d6cdb8", exposta=0.25),
        "gach": V.mat_gach("f_gach", exposto=0.35),
        "trinh": V.mat_trinh("f_trinh"),
        "phen_par": V.mat_phen("f_phen_par", "#b19a69", "#7f6f4a", passo=0.045),
        "van": V.mat_tabua("f_van"),
        "dat": ms.dat,
        "luoi": ms.luoi,
        "ferro": ms.ferro,
        "pedra": ms.pedra,
        "resina": ms.resina,
        "nen": ms.nen,
    }


def layout_faixas() -> dict[str, dict]:
    """Onde cada faixa fica na sua folha (px de baixo para cima, como a UV do Blender)."""
    topo = {f: 0 for f in FOLHAS}
    out = {}
    for nome, folha, modo, bake, px in FAIXAS:
        h_m = H_PAREDE if modo == "parede" else H_VEIO
        s0 = topo[folha]
        out[nome] = {
            "folha": folha,
            "modo": modo,
            "bake": bake,
            "slot_px": [s0, s0 + px + 2 * BORDA_PX],
            "v0": (s0 + BORDA_PX) / FOLHA_PX,
            "dv": px / FOLHA_PX,
            "px": px,
            "altura_m": h_m,
            "comprimento_m": round(FOLHA_PX * h_m / px, 4),  # mesma densidade nos dois sentidos
            "px_por_m": round(px / h_m, 1),
        }
        topo[folha] = s0 + px + 2 * BORDA_PX
    for f, t in topo.items():
        assert t <= FOLHA_PX, f"folha {f}: {t} px não cabem"
    return out


def faixa_de(chave: str, material: str) -> str:
    base = material.split(".")[0]
    base = TROCA_CASA.get(chave, {}).get(base, base)
    return TROCA.get(base, base)


# =============================================================== bake das folhas
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


BAKE = {
    "uz": lambda p: (p.x, p.z, 0.0),
    "veio": lambda p: (p.z, 0.0, p.x),
    "trama": lambda p: (p.x, p.z + 1.0, 0.0),
}


def montar_folhas(cena, mats: dict, lay: dict) -> tuple[dict, dict]:
    folhas = {}
    for f in FOLHAS:
        fl = {
            "cor": np.zeros((FOLHA_PX, FOLHA_PX, 4), np.float32),
            "normal": np.zeros((FOLHA_PX, FOLHA_PX, 4), np.float32),
            "rug": np.ones((FOLHA_PX, FOLHA_PX, 4), np.float32),
        }
        fl["normal"][..., :] = (0.5, 0.5, 1.0, 1.0)
        fl["cor"][..., 3] = 1.0
        folhas[f] = fl
    tempos = {}
    w_extra = int(round(FOLHA_PX * (1 + EXTRA)))
    for nome, info in lay.items():
        t0 = time.time()
        m = assar_plano(
            cena,
            mats[nome],
            info["comprimento_m"] * (1 + EXTRA),
            info["altura_m"],
            w_extra,
            info["px"],
            BAKE[info["bake"]],
        )
        fl = folhas[info["folha"]]
        s0, s1 = info["slot_px"]
        for k, a in m.items():
            b = costura(a, FOLHA_PX, 1, k == "normal")
            fl[k][s0 + BORDA_PX : s1 - BORDA_PX] = b
            fl[k][s0 : s0 + BORDA_PX] = b[0]
            fl[k][s1 - BORDA_PX : s1] = b[-1]
        tempos[nome] = round(time.time() - t0, 1)
        C.log("faixa", nome, info["folha"], info["slot_px"], tempos[nome], "s")
    return folhas, tempos


def montar_piso(cena, mat) -> dict:
    lado = PISO_M * (1 + EXTRA)
    px = int(round(PISO_PX * (1 + EXTRA)))
    m = assar_plano(cena, mat, lado, lado, px, px, BAKE["uz"])
    return {
        k: costura(costura(a, PISO_PX, 1, k == "normal"), PISO_PX, 0, k == "normal")
        for k, a in m.items()
    }


def salvar_mapas(mapas: dict, prefixo: str, px: int) -> dict[str, tuple[bytes, str]]:
    """Grava cor (JPEG), normal (PNG) e metal/rugosidade (PNG, metade do tamanho, como o
    `comum.produzir`) e devolve os bytes para o GLB."""
    out = {}
    cor = mapas["cor"].copy()
    cor[..., 3] = 1.0
    meio = px // 2
    rug = mapas["rug"][..., 0].reshape(meio, 2, meio, 2).mean(axis=(1, 3))
    mr = np.zeros((meio, meio, 4), np.float32)
    mr[..., 0] = 1.0
    mr[..., 1] = rug
    mr[..., 3] = 1.0
    for k, a, tam, fmt, ext, mime in (
        ("cor", cor, px, "JPEG", "jpg", "image/jpeg"),
        ("normal", mapas["normal"], px, "PNG", "png", "image/png"),
        ("mr", mr, meio, "PNG", "png", "image/png"),
    ):
        img = imagem(f"salvar_{prefixo}_{k}", tam, tam, k != "cor")
        C.gravar_pixels(img, a)
        out[k] = (C.salvar_imagem(img, SAIDA / f"{prefixo}_{k}.{ext}", fmt, 92), mime)
        bpy.data.images.remove(img)
    return out


def cor_media_linear(cor: np.ndarray) -> tuple[float, float, float, float]:
    c = C.srgb_para_linear(cor[..., :3].reshape(-1, 3).mean(axis=0))
    return (float(c[0]), float(c[1]), float(c[2]), 1.0)


def cubo(lado: float, x0: float):
    """Cubo (studs) com UV 0..1 em cada face: o nó do portador (o importador não gosta de malha
    chata). Devolve posições, normais, UV e índices já no referencial do GLB."""
    P, N, T, idx = [], [], [], []
    faces = (
        ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
        ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
        ((0, 1, 0), (1, 0, 0), (0, 0, -1)),
        ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
        ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
        ((0, 0, -1), (-1, 0, 0), (0, 1, 0)),
    )
    c = np.array([x0, lado / 2, 0.0])
    for n, u, v in faces:
        n, u, v = np.array(n, float), np.array(u, float), np.array(v, float)
        base = len(P)
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            P.append(c + (n + su * u + sv * v) * lado / 2)
            N.append(n)
            T.append(((su + 1) / 2, 1 - (sv + 1) / 2))
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    return (
        np.array(P, np.float32),
        np.array(N, np.float32),
        np.array(T, np.float32),
        np.array(idx, np.uint32),
    )


def cmd_folhas() -> None:
    t0 = time.time()
    SAIDA.mkdir(parents=True, exist_ok=True)
    cena = C.cena_vazia()
    C.preparar_bake(cena)
    C.log("dispositivo", vila.gpu_cuda(cena))
    mats = materiais_folha()
    lay = layout_faixas()
    folhas, tempos = montar_folhas(cena, mats, lay)
    piso = montar_piso(cena, mats["nen"])
    g = glb.Glb(repetir=True)
    medias = {}
    for i, (f, mapas, px) in enumerate(
        [(f, folhas[f], FOLHA_PX) for f in FOLHAS] + [("P", piso, PISO_PX)]
    ):
        tex = salvar_mapas(mapas, f"folha_{f}", px)
        ids = {k: g.texture(*v) for k, v in tex.items()}
        medias[f] = cor_media_linear(mapas["cor"])
        mi = g.material(f"Trim_{f}", ids["cor"], ids["normal"], ids["mr"], metal=False)
        P, Nn, T, idx = cubo(1.0, 2.0 * i)
        g.mesh(f"Trim_{f}", P, Nn, T, idx, mi)
    (SAIDA / "vila_trim.glb").write_bytes(g.bytes())
    # prévia das folhas para o Git (testes/trim): as 3 de 1024 lado a lado, a 512
    TESTES.mkdir(parents=True, exist_ok=True)
    lado = []
    for f in FOLHAS:
        a = folhas[f]["cor"][::2, ::2].copy()
        lado.append(a)
        lado.append(np.full((512, 8, 4), (0.08, 0.08, 0.08, 1.0), np.float32))
    junto = np.concatenate(lado[:-1], axis=1)
    img = imagem("previa_folhas", junto.shape[1], junto.shape[0], False)
    C.gravar_pixels(img, junto)
    C.salvar_imagem(img, TESTES / "folhas_vila.jpg", "JPEG", 85)
    C.gravar_json(
        SAIDA / "layout.json",
        {
            "folha_px": FOLHA_PX,
            "borda_px": BORDA_PX,
            "piso": {"px": PISO_PX, "repete_m": PISO_M, "no": NO_PISO},
            "faixas": lay,
            "troca": TROCA,
            "troca_casa": TROCA_CASA,
            "cor_media_linear": medias,
            "tempos_s": tempos,
            "portador": "assets/blender/trim_vila/vila_trim.glb",
            "tempo_total_s": round(time.time() - t0, 1),
        },
    )
    C.log("ok folhas", round(time.time() - t0, 1), "s")


# =============================================================== conversão de uma casa
def locais(obj, modo: str) -> np.ndarray:
    """O `local` de cada vértice; sem ele, as coordenadas da malha (altura no 2º para parede)."""
    me = obj.data
    if "local" in me.attributes:
        a = me.attributes["local"].data
        v = np.empty(len(a) * 3, np.float32)
        a.foreach_get("vector", v)
        return v.reshape(-1, 3).astype(np.float64)
    co = np.empty(len(me.vertices) * 3, np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    return co[:, (0, 2, 1)] if modo == "parede" else co


def coords(obj) -> np.ndarray:
    me = obj.data
    co = np.empty(len(me.vertices) * 3, np.float64)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def uv_ladrilho(obj, info: dict) -> None:
    """Piso de tijolo: corta a peça em fileiras de LADRILHO_M ao longo de Y; U = X e V = Y desde o
    começo da fileira (a fiada e a amarração continuam na emenda)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    ys = [v.co.y for v in bm.verts]
    k = math.floor(min(ys) / LADRILHO_M) + 1
    while k * LADRILHO_M < max(ys) - 1e-4:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, k * LADRILHO_M, 0), plane_no=(0, 1, 0))
        k += 1
    bm.to_mesh(obj.data)
    bm.free()
    me = obj.data
    co = coords(obj)
    uv = me.uv_layers.new(name="trim")
    h_m, comp, v0, dv = info["altura_m"], info["comprimento_m"], info["v0"], info["dv"]
    for poly in me.polygons:
        fila = math.floor(poly.center.y / LADRILHO_M + 1e-6)
        for li in poly.loop_indices:
            p = co[me.loops[li].vertex_index]
            vv = np.clip(p[1] - fila * LADRILHO_M, 0.0, h_m)
            uv.data[li].uv = (p[0] / comp, v0 + vv / h_m * dv)
    me.uv_layers.active = uv


def uv_faixa(obj, info: dict) -> None:
    """UV 'trim' na faixa do material (D-156): parede com V = altura; veio com U ao longo do
    maior lado do polígono; pote com V = altura do objeto e U na horizontal."""
    if info["modo"] == "ladrilho":
        uv_ladrilho(obj, info)
        return
    modo, h_m, comp = info["modo"], info["altura_m"], info["comprimento_m"]
    loc = coords(obj) if modo == "pote" else locais(obj, modo)
    me = obj.data
    uv = me.uv_layers.new(name="trim")
    v0, dv = info["v0"], info["dv"]
    lo, hi = loc.min(axis=0), loc.max(axis=0)
    for poly in me.polygons:
        vs = [me.loops[li].vertex_index for li in poly.loop_indices]
        c = loc[vs]
        span = c.max(axis=0) - c.min(axis=0)
        if modo == "parede":
            vax = 1
            uax = 0 if span[0] >= span[2] else 2
            base, alcance = 0.0, max(hi[1], h_m)
        elif modo == "pote":
            vax = 2
            uax = 0 if span[0] >= span[1] else 1
            base, alcance = lo[2], max(hi[2] - lo[2], 1e-6)
        else:
            ordem = np.argsort(-span)
            uax, vax = int(ordem[0]), int(ordem[1])
            base, alcance = lo[vax], max(hi[vax] - lo[vax], 1e-6)
        esc = min(1.0, h_m / alcance) if alcance > h_m else 1.0
        for li, vi in zip(poly.loop_indices, vs, strict=True):
            vv = np.clip((loc[vi, vax] - base) * esc, 0.0, h_m)
            uv.data[li].uv = (loc[vi, uax] / comp, v0 + vv / h_m * dv)
    me.uv_layers.active = uv


def uv_piso(obj) -> None:
    co = coords(obj)
    me = obj.data
    uv = me.uv_layers.new(name="trim")
    for li, lp in enumerate(me.loops):
        p = co[lp.vertex_index]
        uv.data[li].uv = (p[0] / PISO_M, p[1] / PISO_M)
    me.uv_layers.active = uv


def arrays(objs) -> tuple:
    """Posições, normais, UV e índices de vários objetos juntos (metros, Blender)."""
    P, Nn, T, ids = [], [], [], []
    n = 0
    for o in objs:
        for _k, p, nr, t, idx in vila.arrays_por_no(o):
            P.append(p)
            Nn.append(nr)
            T.append(t)
            ids.append(idx.astype(np.int64) + n)
            n += len(p)
    return np.concatenate(P), np.concatenate(Nn), np.concatenate(T), np.concatenate(ids)


def material_trim(nome: str, arquivos: dict) -> bpy.types.Material:
    """Material da prévia: as imagens da folha na UV 'trim'."""
    mat = C.novo_material(nome)
    nt = mat.node_tree
    pr = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "trim"
    for k, caminho in arquivos.items():
        img = bpy.data.images.load(str(caminho))
        img.colorspace_settings.name = "sRGB" if k == "cor" else "Non-Color"
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = img
        nt.links.new(uvn.outputs["UV"], tx.inputs["Vector"])
        if k == "cor":
            nt.links.new(tx.outputs["Color"], pr.inputs["Base Color"])
        elif k == "mr":
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(tx.outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], pr.inputs["Roughness"])
        else:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.uv_map = "trim"
            nt.links.new(tx.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], pr.inputs["Normal"])
    return mat


def montar_glb(original: Path, trims: list[tuple], saida: Path) -> list[dict]:
    """O GLB de hoje sem os nós do atlas Casa, com os nós Trim_* no lugar deles."""
    js, binario = glb.ler(original)
    g = glb.Glb()
    texs: dict[int, int] = {}
    mats: dict[int, int] = {}
    nos = []
    postos = False

    def textura(i: int) -> int:
        if i not in texs:
            data, mime = glb.imagem(js, binario, js["textures"][i]["source"])
            texs[i] = g.texture(data, mime)
        return texs[i]

    for ni in js["scenes"][js.get("scene", 0)]["nodes"]:
        no = js["nodes"][ni]
        prims = js["meshes"][no["mesh"]]["primitives"]
        assert len(prims) == 1, f"{no['name']}: mais de uma primitiva"
        prim = prims[0]
        mat = js["materials"][prim["material"]]
        if mat["name"].endswith("_Casa"):
            if not postos:
                for nome, P, Nn, T, idx, cor in trims:
                    mi = g.material(nome, None, rugosidade=0.85, cor_fator=cor)
                    p, n, t = glb.de_blender(P, Nn, T)
                    g.mesh(nome, p, n, t, idx, mi)
                    nos.append({"no": nome, "atlas": "trim", "triangulos": len(idx) // 3})
                postos = True
            continue
        mi = prim["material"]
        if mi not in mats:
            usados = {}
            pbr = mat.get("pbrMetallicRoughness", {})
            for t in (pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture")):
                if t is not None:
                    usados[t["index"]] = textura(t["index"])
            if "normalTexture" in mat:
                usados[mat["normalTexture"]["index"]] = textura(mat["normalTexture"]["index"])
            mats[mi] = g.material_copia(mat, usados)
        at = prim["attributes"]
        P = glb.acessor(js, binario, at["POSITION"])
        Nn = glb.acessor(js, binario, at["NORMAL"])
        T = glb.acessor(js, binario, at["TEXCOORD_0"]) if "TEXCOORD_0" in at else None
        idx = glb.acessor(js, binario, prim["indices"])
        g.mesh(no["name"], P, Nn, T, idx, mats[mi])
        if not no["name"].startswith("Colisao_"):
            nos.append(
                {"no": no["name"], "atlas": mat["name"].split("_")[-1], "triangulos": len(idx) // 3}
            )
    assert postos, f"{original}: sem nós do atlas Casa"
    saida.write_bytes(g.bytes())
    return nos


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


def previa(chave: str, met: dict, original: Path, convertidas: list, trab: Path) -> None:
    cena = bpy.context.scene
    K.configurar(cena, 40)
    try:
        cena.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    cena.render.resolution_x, cena.render.resolution_y = vila.LARG, vila.ALT
    K.LARG, K.ALT = vila.LARG, vila.ALT
    piso_cena = C.chao(z=0.0, tamanho=400.0)
    piso_cena.data.materials.append(K.material_chao())
    originais = vila.importar_visual(original)
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
    TESTES.mkdir(parents=True, exist_ok=True)
    C.salvar_imagem(out, TESTES / f"previa_{chave}.jpg", "JPEG", 80)


def cmd_casa(chave: str, com_previa: bool) -> None:
    t0 = time.time()
    lay = json.loads((SAIDA / "layout.json").read_text("utf-8"))
    faixas = lay["faixas"]
    pasta = C.SAIDA / chave
    met = json.loads((pasta / "metricas.json").read_text("utf-8"))
    antes = met.get("antes_trim") or met["novo"]
    original = C.RAIZ / antes["arquivo"]
    trab = C.TRABALHO / f"trim_{chave}"
    trab.mkdir(parents=True, exist_ok=True)
    cena = C.cena_vazia()
    C.preparar_bake(cena)
    r, _ = vila.montar(chave)
    por_folha: dict[str, list] = {f: [] for f in (*FOLHAS, "P")}
    uso: dict[str, int] = {}
    convertidas = []
    for o in r.objs:
        if o["grupo"] != "Casa" or o.get("so_bake"):
            o.hide_render = True
            continue
        nome = o.active_material.name if o.active_material else "?"
        if nome.split(".")[0] == "nen":
            uv_piso(o)
            por_folha["P"].append(o)
            fx = "nen"
        else:
            fx = faixa_de(chave, nome)
            if fx not in faixas:
                raise RuntimeError(f"{chave}: material {nome} sem faixa (peça {o.name})")
            uv_faixa(o, faixas[fx])
            por_folha[faixas[fx]["folha"]].append(o)
        uso[fx] = uso.get(fx, 0) + C.triangulos(o)
        convertidas.append(o)
    trims = []
    for f, objs in por_folha.items():
        if not objs:
            continue
        P, Nn, T, idx = arrays(objs)
        trims.append((f"Trim_{f}", P, Nn, T, idx, tuple(lay["cor_media_linear"][f])))
    saida = pasta / f"{chave}_trim.glb"
    nos = montar_glb(original, trims, saida)
    tris = sum(n["triangulos"] for n in nos)
    tris_casa = sum(n["triangulos"] for n in nos if n["atlas"] == "trim")
    C.gravar_json(
        pasta / "metricas.json",
        {
            "antes_trim": antes,
            "novo": {
                **antes,
                "arquivo": f"assets/blender/{chave}/{saida.name}",
                "triangulos": tris,
                "triangulos_glb": glb.triangulos(saida),
                "atlas": antes["atlas"] - 1,
                "mb": round(saida.stat().st_size / 2**20, 3),
                "nos": nos,
            },
            "trim": {
                "folhas": sorted(f for f, o in por_folha.items() if o),
                "faixas_triangulos": uso,
                "triangulos_casa": tris_casa,
                "triangulos_casa_antes": sum(
                    n["triangulos"] for n in antes["nos"] if n["atlas"] == "Casa"
                ),
                "obs": "grupo Casa nas folhas comuns (D-159): Trim_M/W/O/P sem textura; o jogo "
                "põe a SurfaceAppearance do portador vila_trim (AssetLoader)",
            },
        },
    )
    C.log("glb", saida.name, "tris", tris, "casa", tris_casa, "folhas", sorted(uso))
    if com_previa:
        mats = {}
        for f, px in [(f, FOLHA_PX) for f in FOLHAS] + [("P", PISO_PX)]:
            arq = {
                "cor": SAIDA / f"folha_{f}_cor.jpg",
                "normal": SAIDA / f"folha_{f}_normal.png",
                "mr": SAIDA / f"folha_{f}_mr.png",
            }
            mats[f] = material_trim(f"trim_{f}_{px}", arq)
        for f, objs in por_folha.items():
            for o in objs:
                o.data.materials.clear()
                o.data.materials.append(mats[f])
        previa(chave, met, original, convertidas, trab)
    C.log("ok", chave, round(time.time() - t0, 1), "s")


def main() -> None:
    a = C.argumentos()
    if not a:
        raise SystemExit("uso: -- folhas | -- <vila_casa_NN> [--sem-previa]")
    if a[0] == "folhas":
        cmd_folhas()
    else:
        assert a[0] in CASAS, f"casa desconhecida: {a[0]}"
        cmd_casa(a[0], "--sem-previa" not in a)


if __name__ == "__main__":
    main()
