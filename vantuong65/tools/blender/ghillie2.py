"""Comparação da camuflagem de mato: v1 (`assets/ghillie/ghillie.glb`) x v2
(`assets/blender/ghillie/ghillie.glb`, de `tools/ghillie2.py`) vestidas num manequim R15 de
blocos (as medidas de referência do `tools/ghillie.py`), na luz da comparação dos outros assets.

Saídas em `assets/blender/ghillie/`:
- `comparacao.png`: linha = ângulo (frente 3/4 e costas 3/4), esquerda = v1, direita = v2;
- `variantes.png`: a v2 com as 3 texturas (arrozal, mata, bambu), mesma malha;
- `primeira_pessoa.png`: câmera de 1ª pessoa no centro da cabeça (FOV 70°), corpo escondido
  (como o Roblox faz em 1ª pessoa) e a camuflagem visível: v1 | v2.

Uso: blender -b --factory-startup -P tools/blender/ghillie2.py -- ghillie [--amostras N]
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

AQUI = Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(AQUI.parent))
import comparar as K  # noqa: E402
import comum as C  # noqa: E402
import ghillie as G1  # noqa: E402

STUD = C.M_POR_STUD
PASTA = C.SAIDA / "ghillie"


def bl(v) -> Vector:
    """Roblox (studs, x direita, y cima, z costas) -> Blender (m, Z cima, frente em -Y)."""
    return Vector((v[0] * STUD, -v[2] * STUD, v[1] * STUD))


def manequim(nome_conj: str) -> list:
    farda = C.novo_material("farda")
    pr = next(n for n in farda.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    pr.inputs["Base Color"].default_value = (0.035, 0.04, 0.025, 1)
    pr.inputs["Roughness"].default_value = 0.9
    pele = C.novo_material("pele")
    pr = next(n for n in pele.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    pr.inputs["Base Color"].default_value = (0.3, 0.17, 0.1, 1)
    out = []
    for nome, ref, centro in [(p.nome, p.ref, p.centro) for p in G1.PARTES] + list(G1.MAOS_PES):
        me = bpy.data.meshes.new(nome)
        import bmesh

        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(
            bm, vec=Vector((ref[0] * STUD, ref[2] * STUD, ref[1] * STUD)), verts=bm.verts[:]
        )
        bmesh.ops.translate(bm, vec=bl(centro), verts=bm.verts[:])
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(f"{nome_conj}_{nome}", me)
        bpy.context.scene.collection.objects.link(o)
        me.materials.append(pele if nome in ("Head", "RightHand", "LeftHand") else farda)
        out.append(o)
    return out


def vestir(caminho: Path, rotulo: str) -> list:
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(caminho))
    novos = [o for o in bpy.data.objects if o not in antes]
    centro = {p.nome: p.centro for p in G1.PARTES}
    out = []
    for o in novos:
        if o.type != "MESH":
            continue
        parte = o.name.split(".")[0].replace("Ghillie_", "")
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy()
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
        o.data.transform(Matrix.Translation(bl(centro[parte])) @ Matrix.Scale(STUD, 4))
        o.name = f"{rotulo}_{parte}"
        out.append(o)
    for o in novos:
        if o.type != "MESH" and o.name in bpy.data.objects:
            bpy.data.objects.remove(o)
    return out


def trocar_textura(objs, png: Path) -> None:
    img = bpy.data.images.load(str(png), check_existing=True)
    for o in objs:
        for s in o.material_slots:
            for n in s.material.node_tree.nodes:
                if n.type == "TEX_IMAGE":
                    n.image = img


def mostrar(grupos: dict, ligado: str) -> None:
    for nome, objs in grupos.items():
        for o in objs:
            o.hide_render = nome != ligado


def main() -> None:
    a = C.argumentos()
    amostras = (
        int(a[a.index("--amostras") + 1]) if "--amostras" in a else (24 if C.so_cpu() else 64)
    )
    cena = C.cena_vazia()
    K.configurar(cena, amostras)
    cena.cycles.transparent_max_bounces = 128
    piso = C.chao(z=0.0)
    piso.data.materials.append(K.material_chao())
    corpo_v1 = manequim("m1")
    corpo_v2 = manequim("m2")
    v1 = vestir(C.RAIZ / "assets" / "ghillie" / "ghillie.glb", "v1")
    v2 = vestir(PASTA / "ghillie.glb", "v2")
    grupos = {"v1": v1 + corpo_v1, "v2": v2 + corpo_v2}
    met = json.loads((PASTA / "metricas.json").read_text("utf-8"))
    pts = np.concatenate([K.pontos([o], 400) for o in v1 + v2 + corpo_v2])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    trab = C.TRABALHO / "ghillie"
    trab.mkdir(parents=True, exist_ok=True)

    def rot(m):
        tri = f"{m['triangulos']:,}".replace(",", ".")
        return f"{tri} tri · textura {m['texturas_px']['cor'][0]} px · {m['mb']:.2f} MB"

    paineis = []
    for k, az in enumerate((200.0, 20.0)):  # frente 3/4 (o soldado olha para -Y) e costas 3/4
        cam, dist = K.camera(lo, hi, az, pts)
        s = K.sol(az + 70.0)
        d_txt = min(dist * 0.4, 1.0)
        tam = d_txt * 0.024
        x_txt = -d_txt * 36 / K.LENTE_MM / 2 + tam * 0.6
        y_txt = d_txt * 36 * K.ALT / K.LARG / K.LENTE_MM / 2 - tam * 1.6
        linha = []
        for nome, m, rot_txt in (
            ("v1", met["antigo"], "ANTIGO (v1)"),
            ("v2", met["novo"], "NOVO (v2)"),
        ):
            objs_txt = K.texto(cam, f"{rot_txt} — {rot(m)}", x_txt, y_txt, d_txt, tam)
            mostrar(grupos, nome)
            linha.append(K.renderizar(trab / f"render_{k}_{nome}.png"))
            for o in objs_txt:
                bpy.data.objects.remove(o)
        bpy.data.objects.remove(cam)
        bpy.data.objects.remove(s)
        paineis.append(linha)
    sep, h, w = 6, K.ALT, K.LARG
    total = np.ones((2 * h + sep, 2 * w + sep, 4), np.float32)
    total[..., :3] = 0.08
    for i, linha in enumerate(paineis):
        for j, p in enumerate(linha):
            y0 = (1 - i) * (h + sep)
            total[y0 : y0 + h, j * (w + sep) : j * (w + sep) + w] = p
    out = bpy.data.images.new("comparacao", total.shape[1], total.shape[0], alpha=False)
    C.gravar_pixels(out, total)
    C.salvar_imagem(out, PASTA / "comparacao.png", "PNG")

    # as 3 variantes (mesma malha), frente 3/4
    cam, dist = K.camera(lo, hi, 215.0, pts)
    s = K.sol(285.0)
    mostrar(grupos, "v2")
    var = []
    for nome, png in (
        ("ARROZAL", "ghillie2_arroz.png"),
        ("MATA", "ghillie2_selva.png"),
        ("BAMBU", "ghillie2_bambu.png"),
    ):
        trocar_textura(v2, C.RAIZ / "assets" / "ghillie" / png)
        d_txt = min(dist * 0.4, 1.0)
        tam = d_txt * 0.024
        objs_txt = K.texto(
            cam,
            f"v2 — {nome}",
            -d_txt * 36 / K.LENTE_MM / 2 + tam * 0.6,
            d_txt * 36 * K.ALT / K.LARG / K.LENTE_MM / 2 - tam * 1.6,
            d_txt,
            tam,
        )
        var.append(K.renderizar(trab / f"variante_{nome}.png"))
        for o in objs_txt:
            bpy.data.objects.remove(o)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(s)
    tot = np.ones((h, 3 * w + 2 * sep, 4), np.float32)
    tot[..., :3] = 0.08
    for j, p in enumerate(var):
        tot[:, j * (w + sep) : j * (w + sep) + w] = p
    out = bpy.data.images.new("variantes", tot.shape[1], tot.shape[0], alpha=False)
    C.gravar_pixels(out, tot)
    C.salvar_imagem(out, PASTA / "variantes.png", "PNG")
    trocar_textura(v2, C.RAIZ / "assets" / "ghillie" / "ghillie2_arroz.png")

    # 1ª pessoa: câmera no centro da cabeça, olhando para a frente (-Y), corpo escondido
    cam_d = bpy.data.cameras.new("fp")
    cam_d.sensor_fit = "VERTICAL"
    cam_d.angle_y = math.radians(70)
    cam_d.clip_start = 0.01
    cam = bpy.data.objects.new("fp", cam_d)
    cena.collection.objects.link(cam)
    cena.camera = cam
    head = next(p for p in G1.PARTES if p.nome == "Head")
    cam.location = bl(head.centro)
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)  # X 90°: olha para +Y (a frente do soldado)
    s = K.sol(200.0)
    fp = []
    for nome in ("v1", "v2"):
        mostrar(grupos, nome)
        for o in corpo_v1 + corpo_v2:
            o.hide_render = True
        fp.append(K.renderizar(trab / f"fp_{nome}.png"))
    tot = np.ones((h, 2 * w + sep, 4), np.float32)
    tot[..., :3] = 0.08
    for j, p in enumerate(fp):
        tot[:, j * (w + sep) : j * (w + sep) + w] = p
    out = bpy.data.images.new("fp", tot.shape[1], tot.shape[0], alpha=False)
    C.gravar_pixels(out, tot)
    C.salvar_imagem(out, PASTA / "primeira_pessoa.png", "PNG")
    C.gravar_json(
        PASTA / "metricas.json",
        {
            "comparacao": {
                "imagem": "assets/blender/ghillie/comparacao.png",
                "variantes": "assets/blender/ghillie/variantes.png",
                "primeira_pessoa": "assets/blender/ghillie/primeira_pessoa.png",
                "amostras_cycles": amostras,
            }
        },
    )
    C.log("ok", "ghillie")


if __name__ == "__main__":
    main()
