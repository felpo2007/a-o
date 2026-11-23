"""Búfalo e galinha com esqueleto e pele (D-79), feito no Blender, para o andar realista.

Na D-77 o animal virou peças (corpo, cabeça, pernas) que giram nas juntas: dá passo, mas a
perna gira como peça dura e abre fresta no quadril. Aqui a malha é uma só, presa a um esqueleto
com pesos suaves: coluna que verga, pescoço, cabeça, rabo e pernas em duas partes (coxa e canela).
O cliente (AnimalVisuals) mexe os ossos (Bone.Transform) e a pele acompanha sem emenda.

Pesos: o "heat" automático do Blender falha em malha de gerador (não-manifold). Aqui o peso de
cada vértice vem da distância aos segmentos dos ossos da sua região (perna, corpo, pescoço,
rabo), com mistura nas juntas.

Uso (Blender sem janela):
  blender -b --factory-startup -P tools/animais/esqueleto.py -- <entrada.glb> <saida.glb> <especie>
Coordenadas dos ossos em studs, no espaço glTF (Y para cima). O búfalo olha para +X; a galinha
para +Z. Medidas tiradas das caixas das partes da D-77 (tools/rig_animals.py).
"""

import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, DST, ESPECIE = ARGS[0], ARGS[1], ARGS[2]


def gl(x, y, z):
    """glTF (Y em cima) -> Blender (Z em cima)."""
    return Vector((x, -z, y))


# ossos: nome, cabeça, cauda (glTF, studs), pai, região
BUFALO = [
    ("Raiz", (-1.0, 3.2, 0), (-1.0, 3.9, 0), None, "corpo"),
    ("Quadril", (-3.4, 3.7, 0), (-1.2, 3.95, 0), "Raiz", "corpo"),
    ("Coluna", (-1.2, 3.95, 0), (0.9, 4.05, 0), "Quadril", "corpo"),
    ("Peito", (0.9, 4.05, 0), (2.1, 4.0, 0), "Coluna", "corpo"),
    ("Pescoco", (2.1, 3.85, 0), (3.1, 3.55, 0), "Peito", "cabeca"),
    ("Cabeca", (3.1, 3.55, 0), (4.5, 2.7, 0), "Pescoco", "cabeca"),
    ("Rabo1", (-4.4, 4.2, 0), (-4.55, 2.9, 0), "Quadril", "rabo"),
    ("Rabo2", (-4.55, 2.9, 0), (-4.55, 1.5, 0), "Rabo1", "rabo"),
    ("CoxaFE", (1.27, 2.6, -0.75), (1.3, 1.15, -0.75), "Peito", "PernaFE"),
    ("CanelaFE", (1.3, 1.15, -0.75), (1.32, 0.02, -0.75), "CoxaFE", "PernaFE"),
    ("CoxaFD", (1.35, 2.6, 0.42), (1.38, 1.15, 0.42), "Peito", "PernaFD"),
    ("CanelaFD", (1.38, 1.15, 0.42), (1.4, 0.02, 0.42), "CoxaFD", "PernaFD"),
    ("CoxaTE", (-3.05, 2.8, -0.65), (-2.95, 1.2, -0.65), "Quadril", "PernaTE"),
    ("CanelaTE", (-2.95, 1.2, -0.65), (-3.1, 0.02, -0.65), "CoxaTE", "PernaTE"),
    ("CoxaTD", (-3.2, 2.8, 0.58), (-3.1, 1.2, 0.58), "Quadril", "PernaTD"),
    ("CanelaTD", (-3.1, 1.2, 0.58), (-3.25, 0.02, 0.58), "CoxaTD", "PernaTD"),
]
# galinha: olha para +Z; caixa 0,72 x 1,59 x 1,75 studs
GALINHA = [
    ("Raiz", (0, 0.75, -0.1), (0, 1.0, -0.1), None, "corpo"),
    ("Corpo", (0, 0.85, -0.55), (0, 0.95, 0.35), "Raiz", "corpo"),
    ("Pescoco", (0, 0.95, 0.35), (0, 1.25, 0.55), "Corpo", "cabeca"),
    ("Cabeca", (0, 1.25, 0.55), (0, 1.45, 0.8), "Pescoco", "cabeca"),
    ("Rabo1", (0, 1.0, -0.6), (0, 1.35, -0.85), "Corpo", "rabo"),
    ("CoxaFE", (0.12, 0.62, -0.05), (0.12, 0.32, 0.0), "Corpo", "PernaFE"),
    ("CanelaFE", (0.12, 0.32, 0.0), (0.12, 0.02, 0.05), "CoxaFE", "PernaFE"),
    ("CoxaFD", (-0.12, 0.62, -0.05), (-0.12, 0.32, 0.0), "Corpo", "PernaFD"),
    ("CanelaFD", (-0.12, 0.32, 0.0), (-0.12, 0.02, 0.05), "CoxaFD", "PernaFD"),
]


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length, t


def regiao(p, especie):
    """Região do vértice (coordenadas Blender, studs; glTF z = -Blender y)."""
    x, alto, gz = p.x, p.z, -p.y
    if especie == "water_buffalo":
        # frente +X; lado = glTF z (esquerda negativa, como em rig_animals.py)
        if x > 2.15 and alto > 2.0:
            return "cabeca"
        if x < -4.15 and alto < 4.6:
            return "rabo"
        if alto < 2.35:
            if 0.2 < x < 2.3:
                return "PernaFE" if gz < -0.19 else "PernaFD"
            if -4.3 < x < -2.1:
                return "PernaTE" if gz < 0.0 else "PernaTD"
        return "corpo"
    # galinha: frente = glTF +z; lado = x (esquerda positiva)
    if gz > 0.35 and alto > 0.95:
        return "cabeca"
    if gz < -0.55 and alto > 0.95:
        return "rabo"
    if alto < 0.55:
        return "PernaFE" if x > 0 else "PernaFD"
    return "corpo"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    mesh = bpy.context.view_layer.objects.active
    # tira os pais (nó de escala do GLB preparado) mantendo a transformação e aplica
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    mesh.name = "Corpo"

    ossos = BUFALO if ESPECIE == "water_buffalo" else GALINHA
    arm_data = bpy.data.armatures.new("Esqueleto")
    arm = bpy.data.objects.new("Esqueleto", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for nome, h, t, pai, _ in ossos:
        b = arm_data.edit_bones.new(nome)
        b.head, b.tail = gl(*h), gl(*t)
        if pai:
            b.parent = arm_data.edit_bones[pai]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")

    # pesos por região e distância aos segmentos
    grupos = {nome: mesh.vertex_groups.new(name=nome) for nome, *_ in ossos}
    por_regiao = {}
    for nome, h, t, _, reg in ossos:
        por_regiao.setdefault(reg, []).append((nome, gl(*h), gl(*t)))
    # o corpo também puxa um pouco o topo das pernas e a base do pescoço (sem fresta)
    vizinhos = {
        "corpo": ["corpo"],
        "cabeca": ["cabeca", "corpo"],
        "rabo": ["rabo", "corpo"],
    }
    for v in mesh.data.vertices:
        p = v.co
        reg = regiao(p, ESPECIE)
        cands = []
        for r in vizinhos.get(reg, [reg, "corpo"]):
            cands += por_regiao.get(r, [])
        pesos = []
        for nome, a, b in cands:
            d, _ = seg_dist(p, a, b)
            # perna: o corpo só pesa perto do topo da coxa
            penal = 0.0
            if reg.startswith("Perna") and not nome.startswith(("Coxa", "Canela")):
                penal = 0.8 if p.z < 2.0 * (0.25 if ESPECIE == "chicken" else 1.0) else 0.25
            pesos.append((nome, 1.0 / (d + penal + 0.05) ** 3))
        pesos.sort(key=lambda x: -x[1])
        pesos = pesos[:3]
        tot = sum(w for _, w in pesos)
        for nome, w in pesos:
            if w / tot > 0.02:
                grupos[nome].add([v.index], w / tot, "REPLACE")

    mod = mesh.modifiers.new("Esqueleto", "ARMATURE")
    mod.object = arm
    mesh.parent = arm
    # material: sem metal (gerador vinha com mapa de metal)
    for mat in mesh.data.materials:
        if mat and mat.use_nodes:
            for n in mat.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    n.inputs["Metallic"].default_value = 0.0
                    n.inputs["Roughness"].default_value = 0.9
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=DST,
        export_format="GLB",
        export_yup=True,
        export_skins=True,
        export_animations=False,
        export_apply=False,
        use_selection=True,
    )
    print("OSSOS", len(ossos), "VERTICES", len(mesh.data.vertices), "SAIDA", DST)


main()
