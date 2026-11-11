"""Prévia de pose do animal com esqueleto (D-79): confere os pesos antes de subir.

Importa o GLB com pele, põe uma passada (coxas para a frente e para trás, cabeça baixa pastando)
e renderiza de lado e de 3/4 no Workbench com a textura.
Uso: blender -b --factory-startup -P tools/animais/previa_pose.py -- <glb> <saida.png> <especie>
"""

import math
import sys

import bpy
from mathutils import Euler, Vector

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, DST, ESPECIE = ARGS[0], ARGS[1], ARGS[2]

POSE = {
    "water_buffalo": {
        "CoxaFE": 28,
        "CanelaFE": -20,
        "CoxaFD": -22,
        "CoxaTE": -24,
        "CoxaTD": 26,
        "CanelaTD": 18,
        "Pescoco": -18,
        "Cabeca": -25,
        "Rabo1": 20,
    },
    "chicken": {"CoxaFE": 35, "CanelaFE": -30, "CoxaFD": -30, "Pescoco": -40, "Cabeca": -20},
}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    for nome, graus in POSE[ESPECIE].items():
        pb = arm.pose.bones.get(nome)
        if pb:
            pb.rotation_mode = "XYZ"
            # gira em volta do eixo lateral do mundo (Y no Blender)
            pb.rotation_euler = Euler((math.radians(graus), 0, 0), "XYZ")
    bpy.context.view_layer.update()
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 900, 520
    sc.render.film_transparent = False
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    meshes = [o for o in sc.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    centro = (lo + hi) / 2
    tam = (hi - lo).length
    for i, (az, el) in enumerate(((90, 5), (35, 18))):
        a, e = math.radians(az), math.radians(el)
        cam.location = (
            centro
            + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
            * tam
            * 1.4
        )
        direcao = centro - cam.location
        cam.rotation_euler = direcao.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = DST.replace(".png", f"_{i}.png")
        bpy.ops.render.render(write_still=True)
    print("PREVIA OK", DST)


main()
