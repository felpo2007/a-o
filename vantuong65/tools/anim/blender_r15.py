"""Retarget no Blender: roda o retarget.py no Python do Blender e monta o soldado R15 animado.

  "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b --factory-startup ^
      -P tools/anim/blender_r15.py -- [clipe ...] [--sem-retarget] [--render] [--fbx]

- refaz os clipes (retarget.build + export: o mesmo código do CLI, só numpy) e grava os JSON;
- monta uma armadura com os NOMES e o REPOUSO do R15 (um osso por peça, cabeça do osso no pivô da
  junta, peças em caixa presas aos ossos) e uma Action por clipe, quadro a quadro;
- --render: imagens de conferência (Workbench) em assets/mocap/soldado/blender_<clipe>_<q>.png;
- --fbx: soldado.fbx com as Actions (alternativa para o importador de animação do Studio; a
  conversão de eixos do importador NÃO foi conferida);
- salva assets/mocap/soldado/soldado.blend.
Base: Roblox (x, y, z) -> Blender (x, −z, y); o soldado olha para +Y do Blender.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

AQUI = Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))

import r15  # noqa: E402
import retarget  # noqa: E402

C = np.array([[1.0, 0, 0], [0, 0, -1.0], [0, 1.0, 0]])  # Roblox -> Blender


def to_b(v: np.ndarray) -> Vector:
    return Vector(C @ np.asarray(v, dtype=float))


def rot_b(r: np.ndarray) -> Matrix:
    m = C @ np.asarray(r, dtype=float) @ C.T
    return Matrix([list(row) for row in m])


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def pivot_of(part: str, center: np.ndarray, rot: np.ndarray) -> np.ndarray:
    """Pivô da junta da peça (ponto do Attachment1) a partir do centro e da rotação."""
    c1 = r15.JOINTS[r15.JOINT_OF[part]][3]
    return center + rot @ c1


def build_rig() -> bpy.types.Object:
    rest = r15.fk(np.array([0.0, retarget.H0, 0.0]), {p: np.eye(3) for p in r15.PARTS})
    arm = bpy.data.armatures.new("R15")
    obj = bpy.data.objects.new("Soldado_R15", arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for part in r15.PARTS:
        c, r = rest[part]
        head = pivot_of(part, c, r)
        b = arm.edit_bones.new(part)
        b.head = to_b(head)
        # cauda: da junta para o centro da peça e além (direção do comprimento da peça)
        tail = head + (c - head) * 2.0
        if np.linalg.norm(tail - head) < 0.2:
            tail = head + np.array([0.0, 0.4, 0.0])
        b.tail = to_b(tail)
        b.roll = 0.0
    for part in r15.PARTS:
        parent = r15.PARENT.get(part)
        if parent and parent in arm.edit_bones:
            arm.edit_bones[part].parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    # caixas presas aos ossos
    for part in r15.PARTS:
        c, r = rest[part]
        sx, sy, sz = r15.size_of(part)
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        box = bpy.context.active_object
        box.name = f"caixa_{part}"
        box.scale = (sx, sz, sy)
        box.location = to_b(c)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        box.parent = obj
        box.parent_type = "BONE"
        box.parent_bone = part
        box.matrix_world = Matrix.Translation(to_b(c))
    return obj


def apply_clip(obj: bpy.types.Object, path: Path) -> bpy.types.Action:
    d = json.loads(path.read_text("utf-8"))
    act = bpy.data.actions.new(d["nome"])
    obj.animation_data_create()
    obj.animation_data.action = act
    fps = 30
    bpy.context.scene.render.fps = fps
    rest_m = {b.name: b.matrix_local.copy() for b in obj.data.bones}
    for i, q in enumerate(d["quadros"]):
        frame = round(q["t"] * fps) + 1
        for part in r15.PARTS:  # pais antes dos filhos
            c, r = (np.array(x) for x in q["previa"][part])
            pb = obj.pose.bones[part]
            m_rest = rest_m[part]
            world = Matrix.Translation(to_b(pivot_of(part, c, r))) @ rot_b(r).to_4x4()
            pb.matrix = world @ Matrix.Translation(-m_rest.translation) @ m_rest
            bpy.context.view_layer.update()
            pb.keyframe_insert("location", frame=frame)
            pb.rotation_mode = "QUATERNION"
            pb.keyframe_insert("rotation_quaternion", frame=frame)
        del i
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = round(d["duracao"] * fps) + 1
    return act


def render(obj: bpy.types.Object, name: str, frames: list[int]) -> list[str]:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = 720, 540
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "SINGLE"
    if "camera" not in bpy.data.objects:
        cam = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
        scene.collection.objects.link(cam)
        cam.location = (11.0, 9.0, 5.0)  # à frente e à direita do soldado
        direction = Vector((0.0, 0.0, 2.8)) - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        bpy.ops.mesh.primitive_plane_add(size=30.0, location=(0, 0, 0))
    out = []
    for f in frames:
        scene.frame_set(f)
        p = retarget.SAIDA / f"blender_{name}_{f:03d}.png"
        scene.render.filepath = str(p)
        bpy.ops.render.render(write_still=True)
        out.append(p.name)
    del obj
    return out


def main(argv: list[str]) -> None:
    flags = {a for a in argv if a.startswith("--")}
    nomes = [a for a in argv if not a.startswith("--")] or retarget.CLIPES
    if "--sem-retarget" not in flags:
        post = retarget.ler_postura()
        for n in nomes:
            s = retarget.build(n, post)
            retarget.export(s.clip, post, s.grip, s.priority, s.weights, s.extra)
            print("retarget no Blender:", n, json.dumps(s.clip.meta, ensure_ascii=False))
    clear_scene()
    obj = build_rig()
    for n in nomes:
        act = apply_clip(obj, retarget.SAIDA / f"{n}.json")
        act.use_fake_user = True
        if "--render" in flags:
            end = bpy.context.scene.frame_end
            print(n, render(obj, n, [1, max(end // 3, 1), max(2 * end // 3, 1)]))
    if "--fbx" in flags:
        bpy.ops.export_scene.fbx(
            filepath=str(retarget.SAIDA / "soldado.fbx"),
            use_selection=False,
            object_types={"ARMATURE", "MESH"},
            bake_anim=True,
            bake_anim_use_all_actions=True,
            add_leaf_bones=False,
        )
    bpy.ops.wm.save_as_mainfile(filepath=str(retarget.SAIDA / "soldado.blend"))
    print("ok:", retarget.SAIDA / "soldado.blend")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
