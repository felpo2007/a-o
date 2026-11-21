"""Etapa V (Tarefa C): veículos refeitos e novos, em partes nomeadas para o jogo animar.

Para a chave pedida:
1. a receita (`veic_<chave>.py`, função `receita()`) modela o veículo em metros (nariz em +X, Z
   para cima) com medidas de fonte, em partes (`veic_base.Montagem`): Casco, Torre, Cano,
   Esteira_E/D, Roda_*, Escotilha_*, RotorPrincipal, RotorCauda...;
2. tudo vai para o chão (Z mínimo = 0) e para o centro da caixa em X/Y (pivô na base, como o
   modelo antigo);
3. a malha do jogo de cada parte é a geometria da receita (sem redução), limpa (duplicados,
   faces escondidas dentro da própria parte);
4. por atlas: UV nova e bake das peças da receita (cor, normal, rugosidade, metal e oclusão com o
   veículo inteiro e o chão), como `comum.produzir`, com extrusão uniforme curta (a fonte do bake
   é a mesma superfície + detalhes rasos);
5. GLB em studs, Y para cima: um nó por parte, com o pivô da parte como translação do nó; rodas
   iguais reusam a malha (instância) e a lagarta da direita é o espelho da esquerda (mesma UV).
   O nó "Casco" ganha 2 triângulos minúsculos nos cantos da caixa do veículo inteiro: a caixa da
   maior peça (a que o VehicleService/VehicleFx usam como referencial) fica igual à do modelo;
6. `metricas.json`: medidas e fontes, triângulos por parte, pivôs, a tabela ART nova para o
   `VehicleDrive.ART` (studs, referencial do Roblox: nariz em -X, esquerda em +Z, centro da
   caixa) e a conferência dos assentos e olhos no casco novo.

Uso:
    blender -b --factory-startup -P tools/blender/veiculos.py -- <chave> [--previa] [--tex N]
"""

from __future__ import annotations

import importlib
import math
import sys
import time
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import glb  # noqa: E402
import modelar as M  # noqa: E402

STUD = C.M_POR_STUD
RAMP_L = 1.6  # VehicleService.RAMP_L (studs)

# fichas do jogo (Shared/Vehicles.luau): para conferir os assentos que o VehicleService cria
FICHAS = {
    "m48a3": {
        "L": 9.3,
        "W": 3.65,
        "H": 3.1,
        "tripulacao": ["driver", "gunner", "commander", "loader"],
        "passageiros": 0,
        "tipo": "tracked",
    },
    "ontos": {
        "L": 3.83,
        "W": 2.59,
        "H": 2.13,
        "tripulacao": ["driver", "gunner", "loader"],
        "passageiros": 0,
        "tipo": "tracked",
    },
    "lvtp5": {
        "L": 9.04,
        "W": 3.57,
        "H": 2.92,
        "tripulacao": ["driver", "gunner", "commander"],
        "passageiros": 12,
        "tipo": "amphibious",
    },
    "uh34d": {
        "L": (47 * 12 + 2) * 0.0254,
        "W": 4.0,
        "H": (14 * 12 + 3.5) * 0.0254,
        "tripulacao": ["driver", "copilot", "gunner"],
        "passageiros": 8,
        "tipo": "heli",
    },
}
# ART de hoje (Shared/VehicleDrive.luau, 2026-11-11): caixa e olhos medidos no modelo antigo
ART_ANTIGO = {
    "m48a3": {
        "box": [28.17, 12.67, 13.39],
        "eyes": {
            "driver": [-4.2, 1.8, 2.2],
            "gunner": [-0.8, 4.9, -2.4],
            "commander": [4.6, 6.6, -1.6],
            "loader": [3.2, 6.8, 2.8],
        },
    },
    "ontos": {
        "box": [12.1, 10.26, 7.75],
        "eyes": {"driver": [-4.6, 2.2, 1.6], "gunner": [0.0, 4.8, 0.0], "loader": [3.4, 4.8, 0.0]},
    },
    "lvtp5": {
        "box": [28.41, 12.45, 12.14],
        "eyes": {
            "driver": [-9.6, 5.2, 3.4],
            "gunner": [-6.0, 7.6, 0.1],
            "commander": [-9.6, 5.2, -3.4],
        },
        "riders": {"x0": 0.0, "dx": 2.2, "y": 6.9, "z": 3.0},
    },
    "uh34d": {
        "box": [48.09, 19.76, 47.01],
        "eyes": {
            "driver": [-15.5, 6.3, -1.7],
            "copilot": [-15.5, 6.3, 1.7],
            "gunner": [-6.0, -1.0, -5.4],
        },
        "riders": {"x0": -10.0, "dx": 2.4, "y": -2.2, "z": 5.3},
    },
}


# =============================================================== utilidades
def caixa_objs(objs):
    los, his = zip(*(C.caixa(o) for o in objs), strict=True)
    return np.min(los, axis=0), np.max(his, axis=0)


def mover_tudo(mont, t: Matrix, info: dict) -> None:
    vistos = set()
    for o in mont.todos():
        if o.data.name in vistos:
            continue
        vistos.add(o.data.name)
        o.data.transform(t)
        o.data.update()
    for p in mont.partes.values():
        if p["pivo"] is not None:
            p["pivo"] = t @ p["pivo"]
    for i in mont.instancias:
        i["pivo"] = t @ i["pivo"]

    def tp(v):
        return list(t @ Vector(v))

    for k in ("olhos",):
        if k in info:
            info[k] = {s: tp(v) for s, v in info[k].items()}
    for k in ("escapes", "pontos_extra"):
        if k in info:
            info[k] = [tp(v) for v in info[k]]
    if "lagarta" in info:
        d = t.translation
        info["lagarta"]["circulos"] = [
            (x + d.x, z + d.z, r) for x, z, r in info["lagarta"]["circulos"]
        ]
        info["lagarta"]["y_centro"] += d.y
    for k in ("rotor", "cauda"):
        if k in info:
            x, y, z, r = info[k]
            v = t @ Vector((x, y, z))
            info[k] = (v.x, v.y, v.z, r)
    if "passageiros" in info:
        pa = info["passageiros"]
        d = t.translation
        pa["x0"] += d.x
        pa["z"] += d.z
        pa["y"] += d.y


def juntar_copias(objs, nome):
    cs = [C.copiar(o, f"{nome}_{i}") for i, o in enumerate(objs)]
    if len(cs) == 1:
        cs[0].name = nome
        return cs[0]
    return M.juntar(cs, nome)


def baixo_da_parte(nome, parte) -> bpy.types.Object:
    o = juntar_copias(parte["geo"], f"baixo_{nome}")
    o.data.materials.clear()
    C.triangular(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-6)
    bm.to_mesh(o.data)
    bm.free()
    if parte.get("limpar", True):
        C.limpar(o, escondidas=True, n_dir=64)
    C.triangular(o)
    return o


def marcar_parte(obj, idx: int) -> None:
    me = obj.data
    if "parte" in me.attributes:
        me.attributes.remove(me.attributes["parte"])
    a = me.attributes.new("parte", "INT", "FACE")
    a.data.foreach_set("value", np.full(len(me.polygons), idx, np.int32))


def separar_por_parte(obj, idx: int, nome: str) -> bpy.types.Object:
    o = C.copiar(obj, nome)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    lay = bm.faces.layers.int.get("parte")
    fora = [f for f in bm.faces if f[lay] != idx]
    bmesh.ops.delete(bm, geom=fora, context="FACES")
    soltos = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=soltos, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    return o


def espelhar_y(obj) -> None:
    obj.data.transform(Matrix.Diagonal((1.0, -1.0, 1.0, 1.0)))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:], flip_multires=False)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


# =============================================================== bake de um atlas
def borrar(a: np.ndarray, passes: int = 2) -> np.ndarray:
    """Borrão 3x3 (caixa) repetido: tira o ruído do AO assado com poucas amostras."""
    for _ in range(passes):
        p = np.pad(a, 1, mode="edge")
        a = (
            sum(
                p[1 + dy : p.shape[0] - 1 + dy, 1 + dx : p.shape[1] - 1 + dx]
                for dy in (-1, 0, 1)
                for dx in (-1, 0, 1)
            )
            / 9.0
        )
    return a


def assar_mapas(cena, alvo, altos, tex, margem, ext) -> dict:
    """Cor, normal, rugosidade, metal (tex) e oclusão. Na CPU (VT65_CPU): 1 amostra nos mapas de
    material e a oclusão em meia resolução com 32 amostras, ampliada e borrada (uma oclusão de
    1024 com 96 amostras levava ~3 min na GPU; na CPU de 4 linhas passaria de meia hora)."""
    import os

    # VT65_BAKE_RAPIDO=1: o mesmo bake leve da CPU também na GPU (vários agentes renderizando ao
    # mesmo tempo deixavam a oclusão de um atlas em 20 min)
    cpu = C.so_cpu() or os.environ.get("VT65_BAKE_RAPIDO", "") not in ("", "0")
    am = 1 if cpu else 4
    m = {
        "cor": C.nova_imagem("cor", tex, False),
        "normal": C.nova_imagem("normal", tex, True),
        "rug": C.nova_imagem("rug", tex, True),
        "metal": C.nova_imagem("metal", tex, True),
    }
    t = {}
    kw = {"margem": margem, "cage": None}
    t["cor"] = C.assar_escalar(cena, alvo, altos, "Base Color", m["cor"], ext, amostras=am, **kw)
    t["normal"] = C.assar(cena, alvo, altos, "NORMAL", m["normal"], ext, amostras=am, **kw)
    t["rug"] = C.assar(cena, alvo, altos, "ROUGHNESS", m["rug"], ext, amostras=am, **kw)
    t["metal"] = C.assar_escalar(cena, alvo, altos, "Metallic", m["metal"], ext, amostras=am, **kw)
    lo, _ = C.caixa(alvo)
    piso = C.chao(z=float(lo[2]) - 0.002)
    px_ao = tex // 2 if cpu else tex
    ao = C.nova_imagem("ao", px_ao, True)
    t["ao"] = C.assar(
        cena,
        alvo,
        altos,
        "AO",
        ao,
        ext,
        amostras=32 if cpu else 64,
        margem=max(2, margem // 2),
        cage=None,
    )
    bpy.data.objects.remove(piso)
    if px_ao != tex:
        a = C.pixels(ao)[..., 0]
        a = borrar(a, 1)
        a = np.kron(a, np.ones((2, 2), np.float32))
        a = borrar(a, 1)
        bpy.data.images.remove(ao)
        ao = C.nova_imagem("ao", tex, True)
        full = np.ones((tex, tex, 4), np.float32)
        full[..., 0] = full[..., 1] = full[..., 2] = a
        C.gravar_pixels(ao, full)
    m["ao"] = ao
    m["tempos"] = t
    return m


def assar_atlas(cena, baixo, altos, tex, trab: Path, nome: str, ext: float, forca_ao=0.65):
    """Bake das peças `altos` no `baixo` (todas as partes de um atlas juntas). Devolve a cópia
    separada nas costuras (que vai para o GLB) e os bytes das texturas."""
    margem = max(4, tex // 128)
    alvo = C.dividir_ilhas(baixo, angulo_graus=40.0)
    C._visibilidade(baixo, False)
    baixo.hide_render = True
    C.material_alvo(alvo)
    cobre = C.cobertura_uv(cena, alvo, tex)
    mapas = assar_mapas(cena, alvo, altos, tex, margem, ext)
    tempos = mapas.pop("tempos")
    cor = C.pixels(mapas["cor"])
    ao = C.pixels(mapas["ao"])[..., 0]
    rug = C.pixels(mapas["rug"])[..., 0]
    met = C.pixels(mapas["metal"])[..., 0]
    preto = cor[..., :3].max(axis=2) < 0.004
    vazio = float((preto & cobre).sum() / max(1, cobre.sum()))
    lin = C.srgb_para_linear(cor[..., :3]) * (1 - forca_ao + forca_ao * ao)[..., None]
    cor[..., :3] = C.linear_para_srgb(lin)
    cor[..., 3] = 1.0
    C.gravar_pixels(mapas["cor"], cor)
    rug = np.clip(rug + (1 - ao) * 0.06, 0.0, 1.0)
    meio = tex // 2
    mr = np.zeros((meio, meio, 4), np.float32)
    mr[..., 0] = 1.0
    mr[..., 1] = rug.reshape(meio, 2, meio, 2).mean(axis=(1, 3))
    mr[..., 2] = met.reshape(meio, 2, meio, 2).mean(axis=(1, 3))
    mr[..., 3] = 1.0
    img_mr = C.nova_imagem("mr", meio, True)
    C.gravar_pixels(img_mr, mr)
    texturas = {
        "cor": (C.salvar_imagem(mapas["cor"], trab / f"{nome}_cor.jpg", "JPEG", 90), "image/jpeg"),
        "normal": (
            C.salvar_imagem(mapas["normal"], trab / f"{nome}_normal.png", "PNG"),
            "image/png",
        ),
        "mr": (C.salvar_imagem(img_mr, trab / f"{nome}_metal_rug.png", "PNG"), "image/png"),
    }
    C.salvar_imagem(mapas["ao"], trab / f"{nome}_ao.png", "PNG")
    for k in ("cor", "normal", "ao", "rug", "metal"):
        bpy.data.images.remove(mapas[k])
    bpy.data.images.remove(img_mr)
    C._visibilidade(baixo, True)
    baixo.hide_render = False
    info = {
        "tempos_s": tempos,
        "fracao_texels_sem_cor": round(vazio, 5),
        "cobertura_uv_texels": round(float(cobre.mean()), 4),
        "extrusao_m": ext,
    }
    return alvo, texturas, info


# =============================================================== exportação
def para_glb(p_m: np.ndarray) -> np.ndarray:
    return np.column_stack([p_m[:, 0], p_m[:, 2], -p_m[:, 1]]) / STUD


def exportar(nos, caminho: Path, materiais: dict) -> dict:
    """`nos`: [{nome, obj | de, pivo (m), giro, atlas, ancoras}] -> GLB. `materiais`: atlas ->
    texturas. Devolve triângulos (cena inteira, instâncias contadas) e MB."""
    g = glb.Glb()
    mat_idx = {}
    for atlas, tx in materiais.items():
        ids = {k: g.texture(*v) for k, v in tx.items()}
        mat_idx[atlas] = g.material(
            f"{caminho.stem}_{atlas}", ids.get("cor"), ids.get("normal"), ids.get("mr"), metal=True
        )
    malha_de: dict[str, int] = {}
    tris_no: dict[str, int] = {}
    total = 0
    for no in nos:
        piv = np.array(no["pivo"], np.float64)
        if "obj" in no:
            p, n, t, idx = C.arrays_malha(no["obj"])
            p = p - piv
            if no.get("ancoras") is not None:
                lo, hi = no["ancoras"]
                extra_p, extra_i = [], []
                for c, s in ((np.array(lo) - piv, 1.0), (np.array(hi) - piv, -1.0)):
                    base = len(p) + len(extra_p)
                    e = 0.0015 * s
                    extra_p += [c, c + [e, 0, 0], c + [0, e, 0]]
                    extra_i += [base, base + 1, base + 2]
                p = np.vstack([p, extra_p])
                n = np.vstack([n, [[0, 0, 1.0]] * len(extra_p)])
                t = np.vstack([t, [[0.001, 0.001]] * len(extra_p)])
                idx = np.concatenate([idx.reshape(-1), np.array(extra_i, np.uint32)])
            pg, ng, tg = glb.de_blender(p, n, t)
            g.mesh(no["nome"], pg, ng, tg, idx, mat_idx[no["atlas"]])
            malha_de[no["nome"]] = len(g.js["meshes"]) - 1
            nt = len(np.asarray(idx).reshape(-1)) // 3
            nodo = g.js["nodes"][-1]
        else:
            mi = malha_de[no["de"]]
            g.js["nodes"].append({"name": no["nome"], "mesh": mi})
            g.js["scenes"][0]["nodes"].append(len(g.js["nodes"]) - 1)
            nodo = g.js["nodes"][-1]
            nt = tris_no[no["de"]]
        tr = para_glb(piv.reshape(1, 3))[0]
        if np.abs(tr).max() > 1e-6:
            nodo["translation"] = [float(x) for x in tr]
        if no.get("giro"):
            a = math.radians(no["giro"]) / 2  # giro em Z do Blender = giro em Y do GLB
            nodo["rotation"] = [0.0, math.sin(a), 0.0, math.cos(a)]
        tris_no[no["nome"]] = nt
        total += nt
    caminho.parent.mkdir(parents=True, exist_ok=True)
    data = g.bytes()
    caminho.write_bytes(data)
    return {
        "triangulos": total,
        "por_no": tris_no,
        "mb": round(len(data) / 2**20, 3),
        "malhas_unicas": len(g.js["meshes"]),
    }


# =============================================================== referencial do jogo (ART)
def roblox(v, centro) -> list[float]:
    """Ponto do Blender (m, modelo) -> referencial da MeshPart no Roblox (studs, centro da caixa,
    nariz em -X, esquerda em +Z)."""
    x, y, z = Vector(v) - Vector(centro)
    return [round(-x / STUD, 2), round(z / STUD, 2), round(y / STUD, 2)]


def de_roblox(r, centro) -> Vector:
    return Vector(centro) + Vector((-r[0] * STUD, r[2] * STUD, r[1] * STUD))


def bvh_cena(objs) -> BVHTree:
    bm = bmesh.new()
    for o in objs:
        tmp = o.data.copy()
        tmp.transform(o.matrix_world)
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def dentro(bvh: BVHTree, p: Vector) -> bool:
    """Ponto dentro da malha (paridade dos cruzamentos em 3 direções, maioria)."""
    votos = 0
    for d in (
        Vector((0, 0, 1)),
        Vector((0.31, 0.77, 0.56)).normalized(),
        Vector((-0.6, 0.2, 0.77)).normalized(),
    ):
        n, o = 0, p.copy()
        for _ in range(64):
            hit = bvh.ray_cast(o, d, 100.0)
            if hit[0] is None:
                break
            n += 1
            o = hit[0] + d * 1e-4
        votos += n % 2
    return votos >= 2


def conferir_olho(bvh, p: Vector) -> dict:
    loc, _, _, dist = bvh.find_nearest(p)
    baixo = bvh.ray_cast(p, Vector((0, 0, -1)), 10.0)
    return {
        "dentro_da_malha": dentro(bvh, p),
        "dist_superficie_m": round(dist, 3) if loc is not None else None,
        "altura_sobre_o_casco_m": round(baixo[3], 3) if baixo[0] is not None else None,
    }


def assentos_chassi(chave, info_art, centro, caixa_m, bvh) -> list[dict]:
    """Assentos que o VehicleService cria (topo do chassi invisível), no referencial da malha, e se
    caem em cima do casco novo (raio para baixo acha o veículo)."""
    f = FICHAS.get(chave)
    if not f:
        return []
    L, W, H = f["L"] / STUD, f["W"] / STUD, f["H"] / STUD
    heli = f["tipo"] == "heli"
    box = [round(float(x) / STUD, 3) for x in (caixa_m[0], caixa_m[2], caixa_m[1])]
    length = L * 0.8 if heli else L * 0.75
    hull_c = 0.0
    if not heli and "track" in info_art:
        cs = info_art["track"]["circles"]
        lo = min(c[0] - c[2] for c in cs)
        hi = max(c[0] + c[2] for c in cs)
        length = hi - lo - 2 * RAMP_L
        hull_c = (lo + hi) / 2
    Hc = H * 0.55
    out = []
    n_trip = len(f["tripulacao"])
    pontos = []
    for i in range(1, n_trip + 1):
        pontos.append(
            (
                f["tripulacao"][i - 1],
                ((i - 1) % 2 - 0.5) * W * 0.4,
                -length * 0.3 + (i // 2) * 0.8 / STUD,
            )
        )
    for i in range(1, f["passageiros"] + 1):
        row = (i - 1) // 2
        pontos.append((f"p{i}", ((i - 1) % 2 - 0.5) * W * 0.5, length * 0.05 + row * 0.7 / STUD))
    for nome, X, Z in pontos:
        Y = Hc / 2
        # chassi -> malha: X = -z, Y = -Hc/2 + boxH/2 + y, Z = x - hullCenter
        mz = -X
        my = Y + Hc / 2 - box[1] / 2
        mx = Z + hull_c
        p = de_roblox([mx, my, mz], centro)
        hit = bvh.ray_cast(p + Vector((0, 0, 3.0)), Vector((0, 0, -1)), 10.0)
        sobre = hit[0] is not None
        out.append(
            {
                "assento": nome,
                "malha_studs": [round(mx, 2), round(my, 2), round(mz, 2)],
                "cai_sobre_o_casco": sobre,
                "altura_do_assento_m": round(p.z, 2),
                "topo_do_casco_ali_m": round(hit[0].z, 2) if sobre else None,
            }
        )
    return out


def boneco_glb(caminho: Path, y: float) -> dict:
    """Boneco de blocos de 1,75 m (soldado de referência), em pé ao lado do veículo (em `y`)."""
    pecas = [  # (dim x, y, z), centro z  [m]
        ((0.16, 0.14, 0.8), 0.40, 0.11),
        ((0.16, 0.14, 0.8), 0.40, -0.11),
        ((0.22, 0.42, 0.62), 1.11, 0.0),
        ((0.12, 0.11, 0.6), 1.12, 0.27),
        ((0.12, 0.11, 0.6), 1.12, -0.27),
        ((0.2, 0.2, 0.23), 1.575, 0.0),
    ]
    g = glb.Glb()
    mi = g.material("boneco", None, rugosidade=0.8, cor_fator=(0.12, 0.13, 0.08, 1.0))
    tris = 0
    for dim, zc, dy in pecas:
        o = M.caixa("b", dim, (0.0, y + dy, zc))
        p, n, t, idx = C.arrays_malha(o)
        pg, ng, tg = glb.de_blender(p, n, t)
        g.mesh("Boneco", pg, ng, None, idx, mi)
        tris += len(idx) // 3
        bpy.data.objects.remove(o)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    data = g.bytes()
    caminho.write_bytes(data)
    return {"triangulos": tris, "mb": round(len(data) / 2**20, 3)}


# =============================================================== prévia
def previa(objs, caminho: Path, azimutes=(35.0, 215.0)) -> None:
    if C.so_cpu():
        azimutes = (35.0,)
    """Prévia da peça alta: 2 vistas 3/4 (perspectiva) e lado, topo e frente (ortográficas)."""
    import comparar as K

    cena = bpy.context.scene
    K.configurar(cena, 12 if C.so_cpu() else 24)
    cena.render.resolution_percentage = 70 if C.so_cpu() else 100
    piso = C.chao(z=0.0)
    piso.data.materials.append(K.material_chao())
    pts = np.concatenate([K.pontos([o], 2000) for o in objs])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    for az in azimutes:
        cam, _ = K.camera(lo, hi, az, pts)
        s = K.sol(az + 70.0)
        cena.render.filepath = str(caminho.with_name(f"{caminho.stem}_{int(az)}.png"))
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam)
        bpy.data.objects.remove(s)
    c = (lo + hi) / 2
    cam_d = bpy.data.cameras.new("orto")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = float(max(hi - lo)) * 1.06
    cam_d.clip_end = 500
    cam = bpy.data.objects.new("orto", cam_d)
    cena.collection.objects.link(cam)
    cena.camera = cam
    s = K.sol(20.0)
    vistas = {
        "lado": ((c[0], c[1] + 60, c[2]), (math.pi / 2, 0, math.pi)),
        "topo": ((c[0], c[1], c[2] + 60), (0, 0, -math.pi / 2)),
        "frente": ((c[0] + 60, c[1], c[2]), (math.pi / 2, 0, math.pi / 2)),
    }
    if C.so_cpu():
        vistas.pop("frente")
    for nome, (loc, rot) in vistas.items():
        cam.location = loc
        cam.rotation_euler = rot
        cena.render.filepath = str(caminho.with_name(f"{caminho.stem}_{nome}.png"))
        bpy.ops.render.render(write_still=True)


# =============================================================== principal
def main() -> None:
    a = C.argumentos()
    chave = a[0]
    tex = int(a[a.index("--tex") + 1]) if "--tex" in a else 1024
    t0 = time.time()
    cena = C.cena_vazia()
    C.preparar_bake(cena)
    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    pasta.mkdir(parents=True, exist_ok=True)
    trab.mkdir(parents=True, exist_ok=True)

    mod = importlib.import_module(f"veic_{chave}")
    mont, info = mod.receita()
    geos = [o for p in mont.partes.values() for o in p["geo"]]
    lo, hi = caixa_objs(geos)
    t = Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    mover_tudo(mont, t, info)
    if "--previa" in a:
        extras = []
        for ins in mont.instancias:
            base = mont.partes[ins["de"]]
            m = Matrix.Translation(ins["pivo"])
            if ins["giro"]:
                m = m @ Matrix.Rotation(math.radians(ins["giro"]), 4, "Z")
            m = m @ Matrix.Translation(-base["pivo"])
            for o in base["geo"] + base["det"]:
                c = C.copiar(o, "prev")
                c.data.transform(m)
                extras.append(c)
        for es in mont.espelhos:
            for o in mont.partes[es["de"]]["geo"] + mont.partes[es["de"]]["det"]:
                c = C.copiar(o, "prev")
                c.data.transform(Matrix.Diagonal((1.0, -1.0, 1.0, 1.0)))
                bm = bmesh.new()
                bm.from_mesh(c.data)
                bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
                bm.to_mesh(c.data)
                bm.free()
                extras.append(c)
        previa(geos + extras, trab / "previa_alta.png")
        C.log("ok", chave, "prévia")
        return

    # ---------------------------------------------------------------- malhas do jogo
    nomes = list(mont.partes)
    baixos = {}
    tris_parte = {}
    for i, nome in enumerate(nomes):
        b = baixo_da_parte(nome, mont.partes[nome])
        marcar_parte(b, i)
        baixos[nome] = b
        tris_parte[nome] = C.triangulos(b)
        C.log("parte", nome, tris_parte[nome], "tri")

    # ---------------------------------------------------------------- atlas: UV e bake
    atlases: dict[str, list[str]] = {}
    for nome in nomes:
        atlases.setdefault(mont.partes[nome]["atlas"], []).append(nome)
    # ocluidores extras: altos nas posições das instâncias e espelhos (só para a oclusão)
    extras = []
    for ins in mont.instancias:
        base = mont.partes[ins["de"]]
        piv0 = (
            base["pivo"]
            if base["pivo"] is not None
            else Vector(
                (
                    (
                        np.array(C.caixa(baixos[ins["de"]])[0])
                        + np.array(C.caixa(baixos[ins["de"]])[1])
                    )
                    / 2
                ).tolist()
            )
        )
        m = Matrix.Translation(ins["pivo"])
        if ins["giro"]:
            m = m @ Matrix.Rotation(math.radians(ins["giro"]), 4, "Z")
        m = m @ Matrix.Translation(-piv0)
        for o in base["geo"]:
            c = C.copiar(o, f"ocl_{ins['nome']}")
            c.data.transform(m)
            extras.append(c)
    for es in mont.espelhos:
        for o in mont.partes[es["de"]]["geo"]:
            c = C.copiar(o, f"ocl_{es['nome']}")
            c.data.transform(Matrix.Diagonal((1.0, -1.0, 1.0, 1.0)))
            extras.append(c)
    for b in baixos.values():
        b.hide_render = True
        C._visibilidade(b, False)
    diag = float(np.linalg.norm(hi - lo))
    cena.world.light_settings.distance = float(min(1.5, max(0.3, 0.12 * diag)))
    materiais = {}
    alvos = {}
    info_bake = {}
    uv_info = {}
    for atlas, partes in atlases.items():
        objs = [C.copiar(baixos[n], f"j_{n}") for n in partes]
        junto = M.juntar(objs, f"atlas_{atlas}") if len(objs) > 1 else objs[0]
        junto.hide_render = False
        C._visibilidade(junto, True)
        n_ilhas = C.desdobrar(junto, margem=3 / tex, angulo_graus=55.0, visibilidade=True)
        uv_info[atlas] = {"ilhas": n_ilhas, "uso_uv": C.uso_uv(junto), "partes": partes}
        altos = [o for n in partes for o in mont.partes[n]["geo"] + mont.partes[n]["det"]]
        alvo, texturas, ib = assar_atlas(
            cena, junto, altos, tex, trab, atlas, ext=mont.ext.get(atlas, 0.02)
        )
        materiais[atlas] = texturas
        alvos[atlas] = alvo
        info_bake[atlas] = ib
        junto.hide_render = True
        C._visibilidade(junto, False)
        C.log("atlas", atlas, ib)

    # ---------------------------------------------------------------- nós
    finais = {}
    for atlas, partes in atlases.items():
        for n in partes:
            finais[n] = separar_por_parte(alvos[atlas], nomes.index(n), f"fim_{n}")
    pivos = {}
    for n in nomes:
        piv = mont.partes[n]["pivo"]
        if piv is None:
            l2, h2 = C.caixa(finais[n])
            piv = Vector(((l2 + h2) / 2).tolist())
        pivos[n] = piv
    for es in mont.espelhos:
        o = C.copiar(finais[es["de"]], f"fim_{es['nome']}")
        espelhar_y(o)
        finais[es["nome"]] = o
        pv = pivos[es["de"]]
        pivos[es["nome"]] = Vector((pv.x, -pv.y, pv.z))
    # caixa do veículo inteiro (todas as partes nas posições finais)
    pts = []
    for o in finais.values():
        l2, h2 = C.caixa(o)
        pts += [l2, h2]
    for ins in mont.instancias:
        l2, h2 = C.caixa(finais[ins["de"]])
        c0 = np.array(pivos[ins["de"]])
        for q in (l2, h2):
            d = q - c0
            if ins["giro"]:
                a = math.radians(ins["giro"])
                d = np.array(
                    [
                        d[0] * math.cos(a) - d[1] * math.sin(a),
                        d[0] * math.sin(a) + d[1] * math.cos(a),
                        d[2],
                    ]
                )
            pts.append(np.array(ins["pivo"]) + d)
    pts = np.array(pts)
    lo_v, hi_v = pts.min(axis=0), pts.max(axis=0)
    centro = (lo_v + hi_v) / 2
    nos = []
    for n in list(nomes) + [e["nome"] for e in mont.espelhos]:
        nos.append(
            {
                "nome": n,
                "obj": finais[n],
                "pivo": list(pivos[n]),
                "atlas": mont.partes[n]["atlas"]
                if n in mont.partes
                else mont.partes[next(e["de"] for e in mont.espelhos if e["nome"] == n)]["atlas"],
                "ancoras": (lo_v, hi_v) if n == "Casco" else None,
            }
        )
    for ins in mont.instancias:
        nos.append(
            {
                "nome": ins["nome"],
                "de": ins["de"],
                "pivo": list(ins["pivo"]),
                "giro": ins["giro"],
                "atlas": mont.partes[ins["de"]]["atlas"],
            }
        )
    saida = pasta / f"{chave}.glb"
    exp = exportar(nos, saida, materiais)
    C.log("glb", exp)

    # ---------------------------------------------------------------- conferência e ART
    objs_fim = list(finais.values())
    inst_objs = []
    for ins in mont.instancias:
        c = C.copiar(finais[ins["de"]], f"chk_{ins['nome']}")
        m = Matrix.Translation(ins["pivo"])
        if ins["giro"]:
            m = m @ Matrix.Rotation(math.radians(ins["giro"]), 4, "Z")
        c.data.transform(m @ Matrix.Translation(-pivos[ins["de"]]))
        inst_objs.append(c)
    bvh = bvh_cena(objs_fim + inst_objs)
    caixa_m = hi_v - lo_v
    art: dict = {
        "box": [
            round(float(caixa_m[0]) / STUD, 2),
            round(float(caixa_m[2]) / STUD, 2),
            round(float(caixa_m[1]) / STUD, 2),
        ]
    }
    if "lagarta" in info:
        lg = info["lagarta"]
        cs = []
        for x, z, r in lg["circulos"]:
            rr = roblox((x, 0, z), centro)
            cs.append([rr[0], rr[1], round(r / STUD, 2)])
        cs.sort(key=lambda c: c[0])
        yl = lg["y_centro"] - centro[1]
        art["track"] = {
            "zIn": round((yl - lg["largura"] / 2) / STUD, 2),
            "zOut": round((yl + lg["largura"] / 2) / STUD, 2),
            "circles": cs,
            "bars": int(round(lg["comprimento_laco"] / 0.41)),
        }
    if "escapes" in info:
        art["exhaust"] = [roblox(v, centro) for v in info["escapes"]]
    for k, kk in (("rotor", "rotor"), ("cauda", "tail")):
        if k in info:
            x, y, z, r = info[k]
            rr = roblox((x, y, z), centro)
            art[kk] = {"x": rr[0], "y": rr[1], "z": rr[2], "r": round(r / STUD, 2)}
    olhos = {s: roblox(v, centro) for s, v in info.get("olhos", {}).items()}
    art["eyes"] = olhos
    if "passageiros" in info:
        pa = info["passageiros"]
        r0 = roblox((pa["x0"], pa["y"], pa["z"]), centro)
        art["riders"] = {"x0": r0[0], "dx": round(pa["dx"] / STUD, 2), "y": r0[1], "z": abs(r0[2])}
    conf_olhos = {s: conferir_olho(bvh, Vector(v)) for s, v in info.get("olhos", {}).items()}
    # olhos de hoje (ART antigo) escalados pelo código (Size da malha nova / box antiga)
    conf_antigos = {}
    if chave in ART_ANTIGO:
        old = ART_ANTIGO[chave]
        esc = [art["box"][i] / old["box"][i] for i in range(3)]
        for s, e in old["eyes"].items():
            r = [e[i] * esc[i] for i in range(3)]
            conf_antigos[s] = {
                "escalado_studs": [round(x, 2) for x in r],
                **conferir_olho(bvh, de_roblox(r, centro)),
            }
    assentos = assentos_chassi(chave, art, centro, caixa_m, bvh)
    # soldado de 2,0 m (decisão do dono, 2026-11-11): olho sentado ~0,45 x estatura acima do
    # assento (0,79 m no de 1,75; 0,90 no de 2,0), topo da cabeça ~0,12 m acima do olho, ombros
    # (bideltoide ~0,26 x estatura) 0,53 m
    soldado = {
        "estatura_m": 2.0,
        "olho_sentado_m": 0.90,
        "cabeca_acima_do_olho_m": 0.12,
        "ombros_m": 0.53,
        "olhos": {},
        "escotilhas": {},
    }
    for s, v in info.get("olhos", {}).items():
        p = Vector(v)
        z_ass = info.get("assentos_z", {}).get(s)
        e2 = Vector((p.x, p.y, z_ass + 0.90)) if z_ass is not None else p + Vector((0, 0, 0.11))
        # teto acima do olho de hoje (se a cabeça de 2 m passa do teto, o raio do olho novo não o
        # acharia): folga = teto - topo da cabeça do soldado de 2 m
        cima = bvh.ray_cast(p + Vector((0, 0, 0.005)), Vector((0, 0, 1)), 3.0)
        folga = round(cima[0].z - (e2.z + 0.12), 3) if cima[0] is not None else None
        soldado["olhos"][s] = {
            "olho_2m": roblox(e2, centro),
            "subiu_m": round(e2.z - p.z, 3),
            "folga_cabeca_ao_teto_m": folga,
            "dentro_da_malha": dentro(bvh, e2),
        }
    for nome, (w, comp) in info.get("escotilhas", {}).items():
        soldado["escotilhas"][nome] = {
            "abertura_m": [w, comp],
            "passa_ombros_de_2m": min(w, comp) >= 0.53,
            "folga_m": round(min(w, comp) - 0.53, 3),
        }

    # ---------------------------------------------------------------- métricas
    antigo = None
    arq_antigo = C.MODELOS / f"{chave}_studs.glb"
    if arq_antigo.is_file():
        js = glb.ler_json(arq_antigo)
        antigo = {
            "arquivo_jogo": f"assets/forgegui/models/{arq_antigo.name}",
            "triangulos": glb.triangulos(arq_antigo),
            "mb": round(arq_antigo.stat().st_size / 2**20, 3),
            "texturas_px": {"cor": [2048, 2048]},
            "imagens": len(js.get("images", [])),
            "dim_studs_xyz": ART_ANTIGO.get(chave, {}).get("box"),
        }
        try:
            import struct

            data = arq_antigo.read_bytes()
            img0 = js["images"][0]
            bv = js["bufferViews"][img0["bufferView"]]
            n_json = struct.unpack_from("<I", data, 12)[0]
            ini = 20 + n_json + 8 + bv.get("byteOffset", 0)
            png = data[ini : ini + bv["byteLength"]]
            if png[:4] == b"\x89PNG":
                w, h = struct.unpack(">II", png[16:24])
            else:  # JPEG: procura o SOF0/SOF2
                k = 2
                w = h = 0
                while k < len(png):
                    if png[k] != 0xFF:
                        k += 1
                        continue
                    mk = png[k + 1]
                    if mk in (0xC0, 0xC2):
                        h, w = struct.unpack(">HH", png[k + 5 : k + 9])
                        break
                    k += 2 + struct.unpack(">H", png[k + 2 : k + 4])[0]
            antigo["texturas_px"] = {"cor": [w, h]}
        except Exception as e:  # noqa: BLE001
            C.log("textura antiga:", e)
    metricas = pasta / "metricas.json"
    if metricas.is_file():
        metricas.unlink()
    nos_info = {}
    for no in nos:
        ob = finais[no["de"]] if "de" in no else no["obj"]
        l3, h3 = C.caixa(ob)
        dm = h3 - l3
        nos_info[no["nome"]] = {
            "triangulos": exp["por_no"][no["nome"]],
            "dim_studs": [
                round(float(dm[0]) / STUD, 2),
                round(float(dm[2]) / STUD, 2),
                round(float(dm[1]) / STUD, 2),
            ],
            "pivo_studs_roblox": roblox(no["pivo"], centro),
            "atlas": no["atlas"],
            **(
                {"instancia_de": no["de"], "giro_z_graus": no.get("giro") or 0}
                if "de" in no
                else {}
            ),
        }
    dados = {
        "chave": chave,
        "tipo": "refeito" if antigo else "novo",
        "nome": info["nome"],
        "classe": "hero",
        "meta_triangulos": 20000,
        "faccao": info.get("faccao", "US"),
        "medidas_reais": info["medidas"],
        "novo": {
            "arquivo": f"assets/blender/{chave}/{saida.name}",
            "triangulos": exp["triangulos"],
            "malhas_unicas": exp["malhas_unicas"],
            "texturas_px": {
                "cor": [tex, tex],
                "normal": [tex, tex],
                "metal_rug": [tex // 2, tex // 2],
            },
            "atlas": {k: {**v, **info_bake[k]} for k, v in uv_info.items()},
            "texturas": len(materiais),
            "mb": exp["mb"],
            "dim_m_xyz": [
                round(float(caixa_m[0]), 3),
                round(float(caixa_m[2]), 3),
                round(float(caixa_m[1]), 3),
            ],
            "dim_studs_xyz": art["box"],
            "partes": nos_info,
        },
        "art_novo": art,
        "conferencia": {
            "olhos_novos": conf_olhos,
            "olhos_de_hoje_escalados": conf_antigos,
            "assentos_do_chassi": assentos,
            "soldado_2m": soldado,
        },
        "notas": info.get("notas", []),
        "tempo_total_s": round(time.time() - t0, 1),
    }
    if antigo:
        dados["antigo"] = antigo
    else:
        arq_b = C.TRABALHO / chave / "boneco_175.glb"
        ib = boneco_glb(arq_b, float(-(caixa_m[1] / 2) - 0.7))
        dados["antigo"] = {
            **info.get("antigo_placeholder", {}),
            "arquivo": f"assets/blender/_trabalho/{chave}/boneco_175.glb",
            "triangulos": ib["triangulos"],
            "mb": ib["mb"],
            "fonte": "não existe no jogo: no lugar do antigo, um boneco de 1,75 m (escala)",
        }
    C.gravar_json(metricas, dados)
    C.log(
        "ok", chave, exp["triangulos"], "tri", exp["mb"], "MB em", round(time.time() - t0, 1), "s"
    )


if __name__ == "__main__":
    main()
