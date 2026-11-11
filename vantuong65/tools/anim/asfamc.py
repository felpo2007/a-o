"""Leitor de ASF/AMC (formato original da CMU) e cinemática direta.

Convenções (as do visualizador da CMU e do AMCParser):
- eixo de cada osso: C = Rz(az) Ry(ay) Rx(ax) ("axis ... XYZ");
- rotação do quadro: M = Rz(rz) Ry(ry) Rx(rx), graus, na ordem dos "dof";
- rotação de mundo do osso, relativa ao repouso: Q = Q_pai C M C⁻¹ (na raiz, Q = C M C⁻¹);
- fim do osso = fim do pai + comprimento · Q · direção.
Unidade: o ASF da CMU usa "length 0.45" em polegadas; metros = valor · (1/0.45) · 0,0254.
Base: Y para cima, a pessoa de repouso olha para +Z e a esquerda dela é +X.

Só numpy: roda no Python do projeto e no do Blender.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np


def rot_x(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def euler_xyz(deg: np.ndarray) -> np.ndarray:
    """Rz · Ry · Rx (X aplicado primeiro), ângulos em graus."""
    r = np.radians(deg)
    return rot_z(r[2]) @ rot_y(r[1]) @ rot_x(r[0])


@dataclass
class Bone:
    name: str
    direction: np.ndarray
    length: float
    axis: np.ndarray  # graus, ordem XYZ
    dof: list[str]
    parent: str | None = None
    children: list[str] = field(default_factory=list)

    @property
    def C(self) -> np.ndarray:  # noqa: N802 (nome da convenção)
        return euler_xyz(self.axis)


@dataclass
class Skeleton:
    bones: dict[str, Bone]
    order: list[str]  # pais antes dos filhos
    root_order: list[str]
    root_axis: np.ndarray
    scale_m: float  # multiplica comprimento e posição do arquivo para dar metros


def _tokens(line: str) -> list[str]:
    return line.split("#", 1)[0].split()


def parse_asf(path: str | Path) -> Skeleton:
    lines = Path(path).read_text("latin-1").splitlines()
    bones: dict[str, Bone] = {}
    length_unit = 1.0
    root_order: list[str] = []
    root_axis = np.zeros(3)
    section = ""
    cur: dict | None = None
    hierarchy: list[list[str]] = []
    i = 0
    while i < len(lines):
        t = _tokens(lines[i])
        i += 1
        if not t:
            continue
        if t[0].startswith(":"):
            section = t[0][1:]
            continue
        if section == "units" and t[0] == "length":
            length_unit = float(t[1])
        elif section == "root":
            if t[0] == "order":
                root_order = [x.lower() for x in t[1:]]
            elif t[0] == "orientation":
                root_axis = np.array([float(x) for x in t[1:4]])
        elif section == "bonedata":
            if t[0] == "begin":
                cur = {"dof": []}
            elif t[0] == "end" and cur is not None:
                bones[cur["name"]] = Bone(
                    name=cur["name"],
                    direction=np.array(cur["direction"], dtype=float),
                    length=cur["length"],
                    axis=np.array(cur["axis"], dtype=float),
                    dof=cur["dof"],
                )
                cur = None
            elif cur is not None:
                if t[0] == "name":
                    cur["name"] = t[1]
                elif t[0] == "direction":
                    cur["direction"] = [float(x) for x in t[1:4]]
                elif t[0] == "length":
                    cur["length"] = float(t[1])
                elif t[0] == "axis":
                    cur["axis"] = [float(x) for x in t[1:4]]
                    if len(t) > 4 and t[4].upper() != "XYZ":
                        raise ValueError(f"ordem de eixo não suportada: {t[4]}")
                elif t[0] == "dof":
                    cur["dof"] = [x.lower() for x in t[1:]]
        elif section == "hierarchy":
            if t[0] in ("begin", "end"):
                continue
            hierarchy.append(t)
    for row in hierarchy:
        parent = row[0]
        for child in row[1:]:
            bones[child].parent = None if parent == "root" else parent
            if parent != "root":
                bones[parent].children.append(child)
    order: list[str] = []
    pending = [b for b in bones.values() if b.parent is None]
    while pending:
        b = pending.pop(0)
        order.append(b.name)
        pending.extend(bones[c] for c in b.children)
    scale = (1.0 / length_unit) * 0.0254
    return Skeleton(bones, order, root_order, root_axis, scale)


def parse_amc(path: str | Path) -> list[dict[str, list[float]]]:
    frames: list[dict[str, list[float]]] = []
    cur: dict[str, list[float]] | None = None
    for line in Path(path).read_text("latin-1").splitlines():
        t = line.split()
        if not t or t[0].startswith("#") or t[0].startswith(":"):
            continue
        if len(t) == 1 and t[0].isdigit():
            cur = {}
            frames.append(cur)
            continue
        if cur is not None:
            cur[t[0]] = [float(x) for x in t[1:]]
    return frames


@dataclass
class Motion:
    """Cinemática direta de todos os quadros, em metros, na base da CMU."""

    names: list[str]
    root_pos: np.ndarray  # (F, 3)
    root_rot: np.ndarray  # (F, 3, 3) relativo ao repouso
    end: dict[str, np.ndarray]  # nome -> (F, 3): ponta do osso
    rot: dict[str, np.ndarray]  # nome -> (F, 3, 3): rotação de mundo relativa ao repouso
    rest_dir: dict[str, np.ndarray]  # direção de repouso (unitária)
    length: dict[str, float]  # metros
    fps: float


def forward_kinematics(sk: Skeleton, frames: list[dict[str, list[float]]], fps: float) -> Motion:
    n = len(frames)
    root_pos = np.zeros((n, 3))
    root_rot = np.zeros((n, 3, 3))
    end = {b: np.zeros((n, 3)) for b in sk.order}
    rot = {b: np.zeros((n, 3, 3)) for b in sk.order}
    croot = euler_xyz(sk.root_axis)
    croot_inv = croot.T
    cs = {b: sk.bones[b].C for b in sk.order}
    for f, fr in enumerate(frames):
        vals = fr.get("root", [0.0] * 6)
        rv = dict(zip(sk.root_order, vals, strict=False))
        pos = np.array([rv.get("tx", 0.0), rv.get("ty", 0.0), rv.get("tz", 0.0)]) * sk.scale_m
        ang = np.array([rv.get("rx", 0.0), rv.get("ry", 0.0), rv.get("rz", 0.0)])
        q_root = croot @ euler_xyz(ang) @ croot_inv
        root_pos[f] = pos
        root_rot[f] = q_root
        for name in sk.order:
            b = sk.bones[name]
            ang = np.zeros(3)
            for k, d in enumerate(b.dof):
                v = fr.get(name)
                if v is not None and k < len(v):
                    ang["xyz".index(d[1])] = v[k]
            c = cs[name]
            q_parent = rot[b.parent][f] if b.parent else q_root
            q = q_parent @ c @ euler_xyz(ang) @ c.T
            start = end[b.parent][f] if b.parent else pos
            rot[name][f] = q
            end[name][f] = start + q @ b.direction * (b.length * sk.scale_m)
    rest_dir = {b: sk.bones[b].direction / np.linalg.norm(sk.bones[b].direction) for b in sk.order}
    length = {b: sk.bones[b].length * sk.scale_m for b in sk.order}
    return Motion(sk.order, root_pos, root_rot, end, rot, rest_dir, length, fps)


def load(asf: str | Path, amc: str | Path, fps: float) -> Motion:
    return forward_kinematics(parse_asf(asf), parse_amc(amc), fps)
