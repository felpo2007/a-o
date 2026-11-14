"""Mãos de 1ª pessoa do VẠN TƯỜNG '65 (D-99): malha no Blender e GLB por lado.

Pedido do dono (com foto): em 1ª pessoa as mãos da pistola eram "duas bolas laranjas".

Uso (a partir de vantuong65, PowerShell):
    lune run tools/maos/exportar.luau
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/maos/produzir.py

1. Lê assets/blender/maos_1p/capsulas.json (Shared/MaosPose: cápsulas e caixas de cada pega, em
   metros, no espaço da arma: x direita, y cima, z para trás);
2. cada pega de cada mão (MaoD_grip, MaoE_support, MaoE_cup, MaoD_flat...) vira esferas, troncos
   de cone e caixas que o remesh por voxel funde numa mão só (dedos, palma, polegar, pulso); depois
   suaviza e reduz;
3. manga do uniforme ("Manga"): tronco de cone de 0,20 m no eixo X (punho em −X, cotovelo em +X);
   a dos EUA (OG-107) com a dobra da manga arregaçada, a do VC lisa;
4. GLB em studs (tools/blender/glb.py), um por lado: assets/blender/maos_1p/maos_us_1p.glb e
   maos_vc_1p.glb; prévia em PNG;
5. src/ReplicatedStorage/Shared/MaosArte.luau (gerado): tamanho de cada MeshPart e onde fica o ponto
   da mão nela (o importador do Roblox gira o GLB 180° em Y e centra a malha na caixa).
A cor vem do jogo (pele da cabeça do soldado, manga do lado): o GLB não leva textura.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
sys.path.insert(0, str(RAIZ / "tools" / "blender"))
import comum  # noqa: E402

SAIDA = RAIZ / "assets" / "blender" / "maos_1p"
ARTE = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "MaosArte.luau"
M_POR_STUD = 0.28
VOXEL = 0.0011  # m
ALVO_MAO = 2600  # triângulos por mão
MANGA_M = 0.20


def log(*a) -> None:
    print("[MAOS]", *a, flush=True)


def bl(p) -> Vector:
    """Espaço da arma (x direita, y cima, z para trás) -> Blender (o glb.py e o importador do
    Roblox, que gira 180° em Y, devolvem o mesmo x, y, z no espaço da MeshPart)."""
    return Vector((-p[0], p[2], p[1]))


def capsula(bm: bmesh.types.BMesh, a, b, ra: float, rb: float) -> None:
    pa, pb = bl(a), bl(b)
    d = pb - pa
    comp = d.length
    for p, r in ((pa, ra), (pb, rb)):
        bmesh.ops.create_uvsphere(
            bm, u_segments=20, v_segments=12, radius=r, matrix=Matrix.Translation(p)
        )
    if comp > 1e-5:
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        mat = Matrix.Translation((pa + pb) / 2) @ rot
        bmesh.ops.create_cone(
            bm, cap_ends=True, segments=20, radius1=ra, radius2=rb, depth=comp, matrix=mat
        )


def caixa(bm: bmesh.types.BMesh, c, s) -> None:
    """Palma: caixa com as quinas arredondadas (bisel de 1/3 da menor medida)."""
    centro = bl(c)
    esc = Matrix.Diagonal((s[0], s[2], s[1], 1.0))  # x, z, y no Blender
    novo = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(centro) @ esc)
    vs = set(novo["verts"])
    arestas = [e for e in bm.edges if e.verts[0] in vs and e.verts[1] in vs]
    bmesh.ops.bevel(
        bm, geom=list(vs) + arestas, offset=min(s) * 0.45, segments=4, affect="EDGES", profile=0.5
    )


def objeto(nome: str, bm: bmesh.types.BMesh) -> bpy.types.Object:
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(nome, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def fundir(obj: bpy.types.Object, alvo: int) -> None:
    """Remesh por voxel (une as peças), suaviza e reduz."""
    rm = obj.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = VOXEL
    rm.use_smooth_shade = True
    sm = obj.modifiers.new("suave", "SMOOTH")  # arredonda as emendas entre dedos e palma
    sm.factor = 0.5
    sm.iterations = 6
    comum.aplicar_modificadores(obj)
    tri = comum.triangulos(obj)
    if tri > alvo:
        dec = obj.modifiers.new("reduz", "DECIMATE")
        dec.ratio = alvo / tri
        comum.aplicar_modificadores(obj)
    comum.triangular(obj)
    for f in obj.data.polygons:
        f.use_smooth = True


def mao(nome: str, forma: dict) -> bpy.types.Object:
    bm = bmesh.new()
    for ch in forma["chains"]:
        pts = ch["pts"]
        n = len(pts)
        raios = [ch["r"] * (1 - 0.14 * i / max(n - 1, 1)) for i in range(n)]
        for i in range(n - 1):
            capsula(bm, pts[i], pts[i + 1], raios[i], raios[i + 1])
        if n == 1:
            capsula(bm, pts[0], pts[0], raios[0], raios[0])
    for bx in forma["boxes"]:
        caixa(bm, bx["c"], bx["s"])
    obj = objeto(nome, bm)
    fundir(obj, ALVO_MAO)
    return obj


def manga(nome: str, sl: dict) -> bpy.types.Object:
    bm = bmesh.new()
    a, b = (-MANGA_M / 2, 0, 0), (MANGA_M / 2, 0, 0)
    capsula(bm, a, b, sl["r0"], sl["r1"])
    if sl["cuff"] > 0:
        c0 = (-MANGA_M / 2, 0, 0)
        c1 = (-MANGA_M / 2 + sl["cuffLen"], 0, 0)
        capsula(bm, c0, c1, sl["cuff"], sl["cuff"] * 0.97)
    obj = objeto(nome, bm)
    fundir(obj, 900)
    return obj


def pontos(obj: bpy.types.Object) -> dict:
    """Tamanho (studs) e o ponto da mão (origem do espaço da arma) no espaço da MeshPart."""
    v = np.array([(o.co.x, o.co.y, o.co.z) for o in obj.data.vertices])
    # Blender -> espaço da arma: x = −bx, y = bz, z = by
    roblox = np.column_stack([-v[:, 0], v[:, 2], v[:, 1]]) / M_POR_STUD
    lo, hi = roblox.min(axis=0), roblox.max(axis=0)
    centro = (lo + hi) / 2
    return {
        "size": [round(float(x), 4) for x in hi - lo],
        "pivot": [round(float(x), 4) for x in -centro],
    }


def previa(objs: list[bpy.types.Object], caminho: Path) -> None:
    """Grade de 5 x 2, vista de trás (como o jogador vê as próprias mãos), Cycles leve."""
    cena = bpy.context.scene
    cena.render.engine = "CYCLES"
    comum.usar_gpu(cena)
    cena.cycles.samples = 24
    cena.cycles.use_denoising = False
    cena.render.resolution_x, cena.render.resolution_y = 1500, 640
    mat = bpy.data.materials.new("pele")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.62, 0.38, 0.26, 1)
    mundo = cena.world or bpy.data.worlds.new("mundo")
    cena.world = mundo
    mundo.use_nodes = True
    mundo.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.62, 0.65, 1)
    for o in bpy.context.scene.objects:  # as originais ficam na origem: fora da foto
        o.hide_render = True
    copias = []
    for i, o in enumerate(objs):
        c = o.copy()
        c.data = o.data.copy()
        c.data.materials.clear()
        c.data.materials.append(mat)
        cena.collection.objects.link(c)
        lo, hi = comum.caixa(o)
        meio = Vector(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2))
        c.hide_render = False
        c.location = Vector(((i % 5) * 0.2 - 0.4, 0, -(i // 5) * 0.2 + 0.1)) - meio
        copias.append(c)
    luz = bpy.data.objects.new("luz", bpy.data.lights.new("luz", "SUN"))
    luz.data.energy = 3.0
    luz.rotation_euler = (math.radians(50), math.radians(20), math.radians(160))
    cena.collection.objects.link(luz)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cena.collection.objects.link(cam)
    cam.location = Vector((0.0, 1.0, 0.0))  # atrás das mãos (+z do espaço da arma = +Y aqui)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.05
    cena.camera = cam
    cena.render.filepath = str(caminho)
    bpy.ops.render.render(write_still=True)
    for c in copias:
        bpy.data.objects.remove(c)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(luz)


def main() -> None:
    dados = json.loads((SAIDA / "capsulas.json").read_text("utf-8"))
    comum.cena_vazia()
    maos: list[tuple[str, bpy.types.Object]] = []
    for nome in sorted(dados["poses"]):
        obj = mao(nome, dados["poses"][nome])
        maos.append((nome, obj))
        log(nome, comum.triangulos(obj), "triângulos")
    arte = {}
    for lado in ("US", "VC"):
        sl = dados["sleeve"][lado]
        mg = manga("Manga_" + lado, sl)
        partes = [*maos, ("Manga", mg)]
        caminho = SAIDA / f"maos_{lado.lower()}_1p.glb"
        info = comum.exportar_glb(partes, caminho, None, metal=False, rugosidade=0.8)
        log(caminho.name, info)
        arte[lado] = {nome: pontos(o) for nome, o in partes}
        previa([o for _, o in partes], SAIDA / f"maos_{lado.lower()}_1p.png")
    linhas = [
        "--!strict",
        "-- GERADO por tools/maos/produzir.py (D-99): não edite à mão. Tamanho (studs) de cada",
        "-- MeshPart das mãos de 1ª pessoa e onde fica nela o ponto da mão (origem do espaço da",
        "-- arma do Shared/MaosPose), por lado. Usado pelo Controllers/Maos1P (arte publicada).",
        "return {",
    ]
    for lado in ("US", "VC"):
        linhas.append(f"\t{lado} = {{")
        for nome in sorted(arte[lado]):
            p = arte[lado][nome]
            s, v = p["size"], p["pivot"]
            linhas.append(
                f"\t\t{nome} = {{ size = {{ {s[0]}, {s[1]}, {s[2]} }}, "
                f"pivot = {{ {v[0]}, {v[1]}, {v[2]} }} }},"
            )
        linhas.append("\t},")
    linhas.append("}")
    ARTE.write_text("\n".join(linhas) + "\n", "utf-8", newline="\n")
    (SAIDA / "pontos.json").write_text(json.dumps(arte, indent=1), "utf-8")
    log("pontos gravados em", ARTE.name, "e pontos.json")


if __name__ == "__main__":
    main()
