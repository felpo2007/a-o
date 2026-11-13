"""Casas únicas da vila (`vila_casa_01` … `vila_casa_10`): modelagem, bake, GLB, métricas e prévia.

Mesmo caminho das bases (`bases.py`), com o que as casas pedem:
- 3 atlas por casa (`Telhado`, `Casa` = paredes, piso, estrutura e anexos, `Mobilia` = interior),
  cada um com textura de 1024 e teto de triângulos (`vila_casas.ATLAS_PADRAO`); atlas que já
  cabe no teto não é reduzido (só limpeza);
- nós do GLB (= MeshParts no Roblox) separados por função: `Paredes`, `Piso`, `Estrutura`,
  `Telhado`, `Mobilia`, `Anexos`; a colisão vem à parte, em sólidos convexos `Colisao_*`
  (paredes em caixas, uma por pedaço entre os vãos; móveis grandes em caixas baixas);
- portas registradas pela receita (centro no piso, normal para fora, vão livre de 1,00 × 2,30 m),
  gravadas no metricas.json no referencial do GLB e no do Roblox (depois do giro de 180° em Y do
  importador, D-58);
- prévia pequena (`--previa`): o GLB final pelo importador glTF, face única como no Roblox, 2
  ângulos de fora e 1 de dentro (Cycles, poucas amostras).

Uso:
    blender -b --factory-startup -P tools/blender/vila.py -- <chave>
    blender -b --factory-startup -P tools/blender/vila.py -- <chave> --so-montar
    blender -b --factory-startup -P tools/blender/vila.py -- <chave> --previa-alta [azimute]
    blender -b --factory-startup -P tools/blender/vila.py -- <chave> --previa
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
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import glb  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402

PRE_REDUCAO = 60000
STUD = C.M_POR_STUD

USO = (
    "Pivô: centro da caixa (visual + colisão) no chão (Y = 0 no GLB); pôr o modelo com a base no "
    "terreno plano. Nós visuais (Paredes, Piso, Estrutura, Telhado, Mobilia, Anexos): "
    "CanCollide=false, CanQuery=false, CanTouch=false. Nós Colisao_*: Transparency=1, "
    "CanCollide=true, CastShadow=false, CanQuery=true se 'bala' = 'para' (se 'passa', "
    "CanQuery=false ou o atributo Material no PASS do CombatService: Thatch/Bamboo), atributo "
    "Material = o 'material' da lista. Portas: o vão entre as caixas de colisão tem 1,00 × 2,30 m "
    "livres a partir do piso (PISO); o piso de terra batida fica 0,15 m acima do chão (degrau "
    "de 0,54 stud). Frente (porta principal) em -Z do modelo no Roblox depois do giro de 180° do "
    "importador (D-58): conferir no Studio."
)


# =============================================================== montagem
def normalizar(r) -> list[float]:
    """Centro da caixa (visual + colisão) em X/Y na origem e Z mínimo = 0."""
    los, his = [], []
    for o in r.objs:
        lo, hi = C.caixa(o)
        los.append(lo)
        his.append(hi)
    for c in r.colisao:
        p = np.array(c["pontos"])
        los.append(p.min(axis=0))
        his.append(p.max(axis=0))
    lo, hi = np.min(los, axis=0), np.max(his, axis=0)
    t = np.array([-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]])
    m = Matrix.Translation(Vector(t.tolist()))
    for o in r.objs:
        M.mover(o, m)
    for c in r.colisao:
        c["pontos"] = [tuple((np.array(p) + t).tolist()) for p in c["pontos"]]
    for k, v in list(r.extras.items()):
        if k.endswith("_m") and isinstance(v, list) and v:
            if isinstance(v[0], list):
                r.extras[k] = [[a + b for a, b in zip(p, t, strict=True)] for p in v]
            elif len(v) == 3:
                r.extras[k] = [a + b for a, b in zip(v, t, strict=True)]
    return t.tolist()


def montar(chave: str):
    r = getattr(VC, f"receita_{chave}")()
    desl = normalizar(r)
    return r, desl


def marcar_no(obj, idx: int) -> None:
    me = obj.data
    if "vt65_no" in me.attributes:
        me.attributes.remove(me.attributes["vt65_no"])
    a = me.attributes.new("vt65_no", "INT", "FACE")
    a.data.foreach_set("value", np.full(len(me.polygons), idx, np.int32))


def arrays_por_no(obj):
    """Como `comum.arrays_malha`, separando os triângulos pelo atributo de face `vt65_no`."""
    me = obj.data
    me.calc_loop_triangles()
    nv, nl = len(me.vertices), len(me.loops)
    co = np.empty(nv * 3, np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    vi = np.empty(nl, np.int64)
    me.loops.foreach_get("vertex_index", vi)
    nrm = np.empty(nl * 3, np.float64)
    me.corner_normals.foreach_get("vector", nrm)
    nrm = nrm.reshape(-1, 3)
    uv = np.zeros((nl, 2))
    if me.uv_layers:
        u = np.empty(nl * 2, np.float64)
        me.uv_layers.active.data.foreach_get("uv", u)
        uv = u.reshape(-1, 2)
    nt = len(me.loop_triangles)
    tl = np.empty(nt * 3, np.int64)
    me.loop_triangles.foreach_get("loops", tl)
    tl = tl.reshape(-1, 3)
    tp = np.empty(nt, np.int64)
    me.loop_triangles.foreach_get("polygon_index", tp)
    no_poly = np.zeros(len(me.polygons), np.int32)
    if "vt65_no" in me.attributes:
        me.attributes["vt65_no"].data.foreach_get("value", no_poly)
    no_tri = no_poly[tp]
    chave = np.column_stack([co[vi], nrm, uv]).round(6)
    _, primeiro, inv = np.unique(chave, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    P, Nn, T = co[vi][primeiro], nrm[primeiro], uv[primeiro]
    idx = inv[tl]
    saida = []
    for k in np.unique(no_tri):
        sel = idx[no_tri == k]
        usados = np.unique(sel)
        mapa = np.full(len(P), -1, np.int64)
        mapa[usados] = np.arange(len(usados))
        saida.append(
            (int(k), P[usados], Nn[usados], T[usados], mapa[sel].reshape(-1).astype(np.uint32))
        )
    return saida


def malha_convexa(pontos):
    """Fecho convexo dos pontos (m): posições, normais de face e índices."""
    bm = bmesh.new()
    for p in pontos:
        bm.verts.new(Vector(p))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    lixo = [
        g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)
    ]
    bmesh.ops.delete(bm, geom=lixo, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    centro = sum((v.co for v in bm.verts), Vector()) / max(1, len(bm.verts))
    pos, nrm, idx = [], [], []
    for f in bm.faces:
        n = f.normal.copy()
        vs = list(f.verts)
        if n.dot(f.calc_center_median() - centro) < 0:
            n = -n
            vs = vs[::-1]
        for v in vs:
            idx.append(len(pos))
            pos.append(tuple(v.co))
            nrm.append(tuple(n))
    bm.free()
    return np.array(pos, np.float64), np.array(nrm, np.float64), np.array(idx, np.uint32)


def para_roblox(p) -> list[float]:
    """Ponto do Blender (m) -> modelo no Roblox depois do giro de 180° em Y: (-x, z, y) / 0,28."""
    return [round(-p[0] / STUD, 3), round(p[2] / STUD, 3), round(p[1] / STUD, 3)]


def para_glb(p) -> list[float]:
    return [round(p[0] / STUD, 3), round(p[2] / STUD, 3), round(-p[1] / STUD, 3)]


def gpu_cuda(cena) -> str:
    """O driver deste PC é velho para o OptiX (o Cycles avisa e cai na CPU, sem erro): sem
    VT65_CPU, força CUDA. Com VT65_CPU=1, fica o que `comum.usar_gpu` pôs (CPU, 4 linhas)."""
    if C.so_cpu():
        return "CPU"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "CUDA"
        prefs.get_devices()
        cuda = [d for d in prefs.devices if d.type == "CUDA"]
        for d in prefs.devices:
            d.use = d.type == "CUDA"
        if cuda:
            cena.cycles.device = "GPU"
            return "CUDA"
    except TypeError:
        pass
    cena.cycles.device = "CPU"
    return "CPU"


_primeiro_bake: dict = {}
_original_assar_mapas = C._assar_mapas


def _assar_mapas_uma_vez(cena, baixo, altos, tex, margem, cage, ext, metal, amostras_ao):
    """O `comum.produzir` refaz o bake com extrusão uniforme quando mais de 2% dos texels saem com
    oclusão < 0,08. Numa casa isso sempre acontece (cômodo fechado, peças encostadas: 16 a 43% na
    vila_casa_01) e as duas versões deram quase o mesmo (diferença < 1%), dobrando o tempo. Aqui
    a 2ª passada devolve cópias da 1ª, e o `produzir` fica com a gaiola."""
    if cage is None and _primeiro_bake.get("m") is not None:
        m = _primeiro_bake.pop("m")
        return {k: (v.copy() if isinstance(v, bpy.types.Image) else dict(v)) for k, v in m.items()}
    m = _original_assar_mapas(cena, baixo, altos, tex, margem, cage, ext, metal, amostras_ao)
    _primeiro_bake["m"] = m
    return m


C._assar_mapas = _assar_mapas_uma_vez

_original_assar = C.assar


def _assar_supersample(cena, baixo, altos, tipo, img, extrusao, raio=0.0, amostras=4, **kw):
    """Cor, normal e rugosidade com 16 amostras por texel (o padrão é 4): a trama de bambu de 3 cm
    numa parede de 1024 px para a casa inteira (~80 px/m) dava moiré em listras."""
    if tipo != "AO" and amostras == 4:
        amostras = 16
    return _original_assar(cena, baixo, altos, tipo, img, extrusao, raio, amostras=amostras, **kw)


C.assar = _assar_supersample


def atlas_cfg(chave: str) -> dict:
    cfg = {k: dict(v) for k, v in VC.ATLAS_PADRAO.items()}
    for k, v in VC.CASAS[chave].get("atlas", {}).items():
        cfg[k].update(v)
    return cfg


# =============================================================== principal
def main() -> None:
    a = C.argumentos()
    chave = a[0]
    if "--previa" in a:
        previa(chave)
        return
    cfg_casa = VC.CASAS[chave]
    grupos = atlas_cfg(chave)
    t0 = time.time()
    cena = C.cena_vazia()
    C.preparar_bake(cena)
    C.log("dispositivo", gpu_cuda(cena))
    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    pasta.mkdir(parents=True, exist_ok=True)
    trab.mkdir(parents=True, exist_ok=True)
    r, _ = montar(chave)
    nos: list[str] = []
    for o in r.objs:
        if o["no"] not in nos:
            nos.append(o["no"])
    resumo = {
        g: {
            "objetos": sum(1 for o in r.objs if o["grupo"] == g),
            "triangulos": sum(
                C.triangulos(o) for o in r.objs if o["grupo"] == g and not o.get("so_bake")
            ),
        }
        for g in grupos
    }
    C.log(
        "montado",
        chave,
        resumo,
        "colisão",
        len(r.colisao),
        "nós",
        nos,
        "portas",
        len(r.extras["portas"]),
    )
    los, his = zip(*(C.caixa(o) for o in r.objs), strict=True)
    peg = np.max(his, axis=0) - np.min(los, axis=0)
    C.log(
        "pegada_m",
        [round(float(peg[0]), 2), round(float(peg[1]), 2)],
        "limite",
        VC.LIMITE_PEGADA,
        "OK" if max(peg[0], peg[1]) <= VC.LIMITE_PEGADA else "PASSOU",
    )
    if "--so-montar" in a:
        C.log("ok", chave, "só montagem")
        return
    if "--previa-alta" in a:
        i = a.index("--previa-alta")
        az = float(a[i + 1]) if len(a) > i + 1 else 40.0
        N.previa_alta(r.objs, trab / f"previa_alta_{int(az)}.png", az)
        C.log("ok", chave, "prévia da alta")
        return
    for o in r.objs:
        marcar_no(o, nos.index(o["no"]))
    # junta as peças de cada atlas num objeto só (o nó de cada face fica no atributo vt65_no): o
    # bake 'selected to active' do Blender lança os raios objeto por objeto, e com as 142 peças da
    # mobília da vila_casa_01 só a cor levou 150 s (5 s num asset de poucas peças)
    juntos = []
    por_atlas: dict[str, list] = {}
    for o in r.objs:
        por_atlas.setdefault(o["grupo"], []).append(o)
    for atlas in grupos:
        objs = por_atlas.get(atlas, [])
        if not objs:
            continue
        j = M.juntar(objs, f"alto_{atlas}_junto") if len(objs) > 1 else objs[0]
        j["grupo"] = atlas
        juntos.append(j)
    r.objs = juntos

    capturas: list[dict] = []

    def captura(partes, caminho, texturas, metal=False, rugosidade=0.9, cor_fator=None):
        for nome, obj in partes:
            capturas.append(
                {"grupo": nome, "malhas": arrays_por_no(obj), "texturas": texturas, "metal": metal}
            )
        tris = sum(len(m[4]) // 3 for m in capturas[-1]["malhas"])
        return {"triangulos": tris, "mb": 0.0}

    original = C.exportar_glb
    C.exportar_glb = captura
    info_grupos = {}
    try:
        for atlas, gcfg in grupos.items():
            tex = gcfg["tex"]
            altos = [o for o in r.objs if o["grupo"] == atlas]
            if not altos:
                continue
            geo = [o for o in altos if not o.get("so_bake")]
            alto_ref = N.juntar_copias(geo, f"alto_{atlas}")
            tris_alto = C.triangulos(alto_ref)
            base = C.copiar(alto_ref, f"base_{atlas}")
            reduzir = tris_alto > gcfg["teto"]
            if reduzir and tris_alto > PRE_REDUCAO:
                C.reduzir(base, PRE_REDUCAO, planar_graus=0.5)
            limpeza = C.limpar(base, escondidas=False, n_dir=96)
            C.log(atlas, "alta", tris_alto, "limpeza", limpeza)
            if reduzir:
                baixo, tentativas = C.escolher_alvo(
                    base, gcfg["teto"], fracoes=gcfg.get("fracoes", C.FRACOES)
                )
                C.normais_para_fora(baixo)
            else:
                baixo = C.copiar(base, f"baixo_{atlas}")
                C.triangular(baixo)
                tentativas = [
                    {"alvo": None, "tris": C.triangulos(baixo), "obs": "cabe no teto: sem redução"}
                ]
            C.suavizar(baixo, gcfg.get("suave", 50))
            n_ilhas = C.desdobrar(
                baixo, margem=4 / tex, visibilidade=gcfg.get("visibilidade", False)
            )
            d = C.desvio(baixo, base, n=12000)
            C.log(atlas, "desvio", d)
            bpy.data.objects.remove(base)
            bpy.data.objects.remove(alto_ref)
            res = C.produzir(
                cena,
                baixo,
                altos,
                tex,
                trab / atlas,
                trab / f"{atlas}.glb",
                atlas,
                forca_ao=gcfg.get("forca_ao", 0.5),
                amostras_ao=gcfg.get("amostras_ao", 96),
            )
            baixo.hide_render = True
            gai = res["bake"]["gaiola"]
            if "uniforme" in gai:
                gai["uniforme"] = {
                    "obs": "2ª passada (extrusão uniforme) pulada: _assar_mapas_uma_vez"
                }
                gai["usada"] = "gaiola"
            info_grupos[atlas] = {
                "triangulos_alta": tris_alto,
                "triangulos": res["exportacao"]["triangulos"],
                "teto": gcfg["teto"],
                "reduzido": reduzir,
                "texturas_px": res["texturas_px"],
                "uso_uv": C.uso_uv(baixo),
                "ilhas_uv": n_ilhas,
                "desvio_m": d,
                "tentativas": tentativas,
                "limpeza": limpeza,
                "bake": res["bake"],
            }
    finally:
        C.exportar_glb = original

    # GLB final: um material por atlas, um nó por `no`, depois a colisão
    g = glb.Glb()
    todos_pts = []
    tris_vis = 0
    nos_saida = []
    for cap in capturas:
        ids = {k: g.texture(*v) for k, v in cap["texturas"].items()}
        mi = g.material(
            f"{chave}_{cap['grupo']}", ids.get("cor"), ids.get("normal"), ids.get("mr"), metal=False
        )
        for k, p, n, t, idx in cap["malhas"]:
            nome = nos[k]
            P, Nn, T = glb.de_blender(p, n, t)
            g.mesh(nome, P, Nn, T, idx, mi)
            todos_pts.append(p)
            tris_vis += len(idx) // 3
            nos_saida.append({"no": nome, "atlas": cap["grupo"], "triangulos": len(idx) // 3})
    mc = g.material("Colisao", None, rugosidade=1.0, cor_fator=(0.8, 0.05, 0.05, 1.0))
    col_saida = []
    tris_col = 0
    for c in r.colisao:
        p, n, idx = malha_convexa(c["pontos"])
        P, Nn, _ = glb.de_blender(p, n, np.zeros((len(p), 2)))
        nome = f"Colisao_{c['nome']}"
        g.mesh(nome, P, Nn, None, idx, mc)
        tris_col += len(idx) // 3
        rb = np.array([para_roblox(q) for q in c["pontos"]])
        lo, hi = rb.min(axis=0), rb.max(axis=0)
        item = {
            "no": nome,
            "tipo": c["tipo"],
            "centro_studs_roblox": [round(float(x), 3) for x in (lo + hi) / 2],
            "tamanho_studs_roblox": [round(float(x), 3) for x in hi - lo],
            "bala": c["bala"],
            "material": c["material"],
        }
        if c["obs"]:
            item["obs"] = c["obs"]
        col_saida.append(item)
    saida = pasta / f"{chave}.glb"
    dados = g.bytes()
    saida.write_bytes(dados)
    allp = np.concatenate(todos_pts)
    lo, hi = allp.min(axis=0), allp.max(axis=0)
    dim = hi - lo
    portas = []
    for pm, info in zip(r.extras["portas_m"], r.extras["portas"], strict=True):
        nb = info["normal_blender"]
        portas.append(
            {
                "nome": info["nome"],
                "interna": info["interna"],
                "centro_no_piso_studs_glb": para_glb(pm),
                "centro_no_piso_studs_roblox": para_roblox(pm),
                "normal_para_fora_roblox": [round(-nb[0], 3), round(nb[2], 3), round(nb[1], 3)],
                "vao_livre_m": [info["largura_livre_m"], info["altura_livre_m"]],
                "vao_livre_studs": [
                    round(info["largura_livre_m"] / STUD, 2),
                    round(info["altura_livre_m"] / STUD, 2),
                ],
            }
        )
    medidas = dict(VC.MEDIDAS_COMUNS)
    for k, corpo in enumerate(r.extras.get("corpos", [])):
        medidas[f"corpo{k}_m"] = [
            corpo,
            "PLACEHOLDER: planta, pé-direito e espessura escolhidos (sem medida "
            "de uma casa real); 1 ou 3 vãos como em vjol2024/plo_3gian",
        ]
    for k, tel in enumerate(r.extras.get("telhados", [])):
        medidas[f"telhado{k}_m"] = [
            tel,
            "PLACEHOLDER: cumeeira e beiral escolhidos; forma (2 ou 4 águas) e "
            "material pelas fontes do estilo",
        ]
    metricas = pasta / "metricas.json"
    if metricas.is_file():
        metricas.unlink()
    teto = sum(gc["teto"] for gc in grupos.values())
    C.gravar_json(
        metricas,
        {
            "chave": chave,
            "tipo": "casa",
            "nome": cfg_casa["nome"],
            "estilo": cfg_casa["tipo"],
            "classe_artbudget": "prop",
            "meta_triangulos": teto,
            "fontes_estilo": {k: VC.FONTES[k] for k in cfg_casa["fontes"]},
            "medidas_reais": medidas,
            "frente": "-Y no Blender = +Z no GLB; no Roblox, depois do giro de 180° do "
            "importador (D-58), "
            "a frente fica em -Z (LookVector). Conferir no Studio.",
            "pivo": "centro da caixa (visual + colisão) no chão",
            "pegada_m": [round(float(dim[0]), 2), round(float(dim[1]), 2)],
            "pegada_studs": [round(float(dim[0]) / STUD, 1), round(float(dim[1]) / STUD, 1)],
            "limite_pegada_m": VC.LIMITE_PEGADA,
            "cabe_no_limite": bool(max(dim[0], dim[1]) <= VC.LIMITE_PEGADA),
            "obs_limite": "limite do agente do mapa (vila central Xóm Gò): casa com beirais e "
            "anexos num "
            "quadrado de 8,5 m; porta com pelo menos 2,1 m de vão livre (aqui 2,3 m, decisão do "
            "dono)",
            "altura_m": round(float(dim[2]), 2),
            "piso_m": V.PISO,
            "piso_studs": round(V.PISO / STUD, 3),
            "portas": portas,
            "novo": {
                "arquivo": f"assets/blender/{chave}/{saida.name}",
                "triangulos": tris_vis,
                "triangulos_colisao": tris_col,
                "triangulos_glb": glb.triangulos(saida),
                "atlas": len(info_grupos),
                "texturas_px": {k: v["texturas_px"] for k, v in info_grupos.items()},
                "mb": round(len(dados) / 2**20, 3),
                "dim_m_xyz": [round(float(x), 3) for x in (dim[0], dim[2], dim[1])],
                "dim_studs_xyz": [round(float(x) / STUD, 2) for x in (dim[0], dim[2], dim[1])],
                "nos": nos_saida,
            },
            "grupos": info_grupos,
            "colisao": col_saida,
            "previa": {"camera_dentro_m": r.extras.get("camera_dentro_m")},
            "uso": USO,
            "tempo_total_s": round(time.time() - t0, 1),
        },
    )
    C.log(
        "ok",
        chave,
        {"tri": tris_vis, "col": tris_col, "mb": round(len(dados) / 2**20, 2)},
        "em",
        round(time.time() - t0, 1),
        "s",
    )


# =============================================================== prévia
LARG, ALT = 640, 400


def importar_visual(caminho: Path) -> list:
    """GLB pelo importador glTF, sem os nós de colisão, em metros (o GLB está em studs)."""
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(caminho))
    novos = [o for o in bpy.data.objects if o not in antes]
    malhas = []
    for o in novos:
        if o.type != "MESH" or o.name.startswith(("Colisao_", "Zona_")):
            continue
        malhas.append(o)
    for o in malhas:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy() if o.data.users > 1 else o.data
        o.data.transform(Matrix.Scale(STUD, 4) @ mw)
        o.matrix_world = Matrix.Identity(4)
    for o in novos:
        if o not in malhas:
            bpy.data.objects.remove(o)
    return malhas


def previa(chave: str) -> None:
    import comparar as K

    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    trab.mkdir(parents=True, exist_ok=True)
    met = json.loads((pasta / "metricas.json").read_text("utf-8"))
    amostras = 40
    cena = C.cena_vazia()
    K.configurar(cena, amostras)
    C.log("dispositivo", gpu_cuda(cena))
    try:
        cena.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    K.LARG, K.ALT = LARG, ALT
    cena.render.resolution_x, cena.render.resolution_y = LARG, ALT
    piso = C.chao(z=0.0, tamanho=400.0)
    piso.data.materials.append(K.material_chao())
    objs = importar_visual(C.RAIZ / met["novo"]["arquivo"])
    for o in objs:
        K.face_unica(o)
    pts = K.pontos(objs, 8000)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    paineis = []
    for k, az in enumerate((35.0, 215.0)):
        cam, _ = K.camera(lo, hi, az, pts)
        s = K.sol(az + 70.0)
        paineis.append(K.renderizar(trab / f"previa_{k}.png"))
        bpy.data.objects.remove(cam)
        bpy.data.objects.remove(s)
    # dentro: câmera da receita, sol entrando pela porta principal e exposição maior
    cd = met["previa"]["camera_dentro_m"]
    pos, alvo = Vector(cd[0]), Vector(cd[1])
    cam_d = bpy.data.cameras.new("CamDentro")
    cam_d.lens = 14.0
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
        nr = porta["normal_para_fora_roblox"]  # (-nx, nz, ny) do Blender
        nx, ny = -nr[0], nr[2]
        az = math.degrees(math.atan2(nx, -ny))
    luz = bpy.data.lights.new("SolDentro", "SUN")
    luz.energy = 3.4
    luz.angle = math.radians(2.0)
    luz.color = (1.0, 0.93, 0.84)
    s = bpy.data.objects.new("SolDentro", luz)
    cena.collection.objects.link(s)
    s.rotation_euler = (math.radians(62), 0.0, math.radians(az + 20))
    # luz de preenchimento só da prévia (faz o papel da luz ambiente do jogo): área larga e fraca
    # sob o telhado, no meio do cômodo
    area = bpy.data.lights.new("Preenche", "AREA")
    area.shape = "DISK"
    area.size = 3.0
    area.energy = 260.0
    area.color = (1.0, 0.9, 0.78)
    ao = bpy.data.objects.new("Preenche", area)
    cena.collection.objects.link(ao)
    meio = (pos + alvo) / 2
    ao.location = (meio.x, meio.y, V.PISO + 2.45)
    cam_d.lens = 17.0
    cena.view_settings.exposure = 1.0
    cena.cycles.samples = amostras + 24
    paineis.append(K.renderizar(trab / "previa_dentro.png"))
    sep = 6
    total = np.ones((ALT, 3 * LARG + 2 * sep, 4), np.float32)
    total[..., :3] = 0.08
    for j, p in enumerate(paineis):
        x0 = j * (LARG + sep)
        total[:, x0 : x0 + LARG] = p
    out = bpy.data.images.new("previa", total.shape[1], total.shape[0], alpha=False)
    C.gravar_pixels(out, total)
    C.salvar_imagem(out, pasta / "previa.png", "PNG")
    C.gravar_json(
        pasta / "metricas.json",
        {
            "previa": {
                "imagem": f"assets/blender/{chave}/previa.png",
                "paineis": [
                    "fora, azimute 35°",
                    "fora, azimute 215°",
                    "dentro (câmera da receita)",
                ],
                "camera_dentro_m": cd,
                "amostras_cycles": amostras,
                "px": [LARG, ALT],
                "obs": "GLB final pelo importador glTF, face única (como MeshPart sem "
                "DoubleSided); "
                "a prévia de dentro tem uma luz de área fraca sob o telhado (faz o papel da luz "
                "ambiente do jogo) e exposição +1",
            }
        },
    )
    C.log("ok", chave, "prévia")


if __name__ == "__main__":
    main()
