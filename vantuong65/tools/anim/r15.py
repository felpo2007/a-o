"""Rig R15 do soldado (nomes e repouso das juntas do Roblox) e utilidades de rotação.

Base do Roblox: X para a direita, Y para cima, o personagem olha para −Z. Posições em studs.
No repouso do R15 todas as peças ficam alinhadas com o HumanoidRootPart (braços caídos ao lado do
corpo, pernas retas), e os Attachments das juntas não têm rotação. Por isso a rotação de mundo de
cada peça relativa ao repouso (W) dá direto o Transform da junta: T = W_pai⁻¹ · W_filho.

Medidas: as juntas do R15 em bloco do Studio (`content/avatar/characterR15.rbxm`, lido com o Lune em
2026-11-11: Root C1 (0, −0,2), quadris (±0,5, −0,2), joelho −0,401/0,379, tornozelo −0,547/0,102,
ombro (∓1, 0,563)/(±0,5, 0,394), cotovelo −0,334/0,259, pulso −0,501/0,125, Waist 0,2/−0,8,
Neck 0,8/−0,5) com HeightScale 1,25 no eixo Y (Characters.luau). O corpo "Man" (pacote 238) NÃO foi
medido: as distâncias abaixo são PLACEHOLDER até despejar as juntas de um soldado no Studio. O
comprimento da perna (quadril até a sola, 2,0 × 1,25 = 2,5 studs) bate com o HipHeight medido em
jogo (2,40 com escala 1,2).
"""

from __future__ import annotations

import numpy as np

STUD_M = 0.28
HEIGHT_SCALE = 1.25
S = HEIGHT_SCALE

# HumanoidRootPart: 2 × 2 × 1 escalado
HRP_SIZE = np.array([2.0, 2.0 * S, 1.0])

# junta -> (peça pai, peça filha, posição no pai (C0), posição no filho (C1)), em studs
_L = {
    "Root": ("HumanoidRootPart", "LowerTorso", None, (0.0, -0.2 * S, 0.0)),
    "Waist": ("LowerTorso", "UpperTorso", (0.0, 0.2 * S, 0.0), (0.0, -0.8 * S, 0.0)),
    "Neck": ("UpperTorso", "Head", (0.0, 0.8 * S, 0.0), (0.0, -0.5, 0.0)),
    "LeftShoulder": ("UpperTorso", "LeftUpperArm", (-1.0, 0.563 * S, 0.0), (0.5, 0.394 * S, 0.0)),
    "LeftElbow": ("LeftUpperArm", "LeftLowerArm", (0.0, -0.334 * S, 0.0), (0.0, 0.259 * S, 0.0)),
    "LeftWrist": ("LeftLowerArm", "LeftHand", (0.0, -0.501 * S, 0.0), (0.0, 0.125 * S, 0.0)),
    "LeftHip": ("LowerTorso", "LeftUpperLeg", (-0.5, -0.2 * S, 0.0), (0.0, 0.421 * S, 0.0)),
    "LeftKnee": ("LeftUpperLeg", "LeftLowerLeg", (0.0, -0.401 * S, 0.0), (0.0, 0.379 * S, 0.0)),
    "LeftAnkle": ("LeftLowerLeg", "LeftFoot", (0.0, -0.547 * S, 0.0), (0.0, 0.102 * S, 0.0)),
}


def _mirror(name: str) -> str:
    return name.replace("Left", "Right")


JOINTS: dict[str, tuple[str, str, np.ndarray | None, np.ndarray]] = {}
for _j, (_p0, _p1, _c0, _c1) in _L.items():
    JOINTS[_j] = (_p0, _p1, None if _c0 is None else np.array(_c0), np.array(_c1))
    if _j.startswith("Left"):
        m0 = None if _c0 is None else np.array([-_c0[0], _c0[1], _c0[2]])
        m1 = np.array([-_c1[0], _c1[1], _c1[2]])
        JOINTS[_mirror(_j)] = (_mirror(_p0), _mirror(_p1), m0, m1)

# junta de cada peça (a peça é a Part1 da junta)
JOINT_OF = {v[1]: k for k, v in JOINTS.items()}
PARENT = {v[1]: v[0] for v in JOINTS.values()}
PARTS = [
    "LowerTorso",
    "UpperTorso",
    "Head",
    "LeftUpperArm",
    "LeftLowerArm",
    "LeftHand",
    "RightUpperArm",
    "RightLowerArm",
    "RightHand",
    "LeftUpperLeg",
    "LeftLowerLeg",
    "LeftFoot",
    "RightUpperLeg",
    "RightLowerLeg",
    "RightFoot",
]

# tamanhos só para a prévia no Blender (corpo "Man" aproximado, PLACEHOLDER visual)
SIZES = {
    "LowerTorso": (1.67, 0.63 * S, 1.04),
    "UpperTorso": (1.84, 1.6 * S, 1.07),
    "Head": (1.0, 1.2, 1.1),
    "UpperArm": (0.6, 1.1 * S, 0.75),
    "LowerArm": (0.6, 0.95 * S, 0.62),
    "Hand": (0.5, 0.45 * S, 0.6),
    "UpperLeg": (0.78, 1.15 * S, 0.85),
    "LowerLeg": (0.72, 1.2 * S, 0.85),
    "Foot": (0.72, 0.3 * S, 1.24),
}


def size_of(part: str) -> tuple[float, float, float]:
    for k, v in SIZES.items():
        if part.endswith(k):
            return v
    raise KeyError(part)


# perna: quadril -> joelho -> tornozelo -> sola (studs)
THIGH = 0.822 * S
SHIN = 0.926 * S
ANKLE_H = (0.102 + 0.15) * S  # do pivô do tornozelo até a sola
LEG = THIGH + SHIN + ANKLE_H  # 2,5 studs = 0,70 m: altura do quadril em pé
TOE_Z, HEEL_Z = -0.75, 0.40  # ponta e calcanhar no espaço do pé, a partir do tornozelo

# braço: o pivô do ombro fica na quina de dentro do braço (o braço pende 0,5 stud para fora)
UPPER_ARM_VEC = {
    "Left": np.array([-0.5, -0.728 * S, 0.0]),
    "Right": np.array([0.5, -0.728 * S, 0.0]),
}
FOREARM_VEC = np.array([0.0, -0.76 * S, 0.0])
HAND_CENTER = np.array([0.0, -0.125 * S, 0.0])  # centro da mão a partir do pulso

UP = np.array([0.0, 1.0, 0.0])
DOWN = np.array([0.0, -1.0, 0.0])
FWD = np.array([0.0, 0.0, -1.0])


# ===== rotações =====
def rx(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def unit(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def axis_angle(axis: np.ndarray, ang: float) -> np.ndarray:
    a = unit(axis)
    k = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + np.sin(ang) * k + (1 - np.cos(ang)) * (k @ k)


def swing(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Menor rotação que leva a direção a até b."""
    a, b = unit(a), unit(b)
    c = float(np.clip(a @ b, -1.0, 1.0))
    ax = np.cross(a, b)
    if np.linalg.norm(ax) < 1e-9:
        if c > 0:
            return np.eye(3)
        perp = np.cross(a, [1.0, 0, 0])
        if np.linalg.norm(perp) < 1e-6:
            perp = np.cross(a, [0, 1.0, 0])
        return axis_angle(perp, np.pi)
    return axis_angle(ax, np.arccos(c))


def mat_to_quat(m: np.ndarray) -> np.ndarray:
    """(w, x, y, z), w >= 0."""
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = np.array(
            [0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
        )
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = np.array(
            [(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
        )
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = np.array(
            [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s]
        )
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = np.array(
            [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s]
        )
    q = q / np.linalg.norm(q)
    return q if q[0] >= 0 else -q


def quat_to_mat(q: np.ndarray) -> np.ndarray:
    w, x, y, z = q / np.linalg.norm(q)
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def log_rot(m: np.ndarray) -> np.ndarray:
    """Vetor de rotação (eixo · ângulo)."""
    q = mat_to_quat(m)
    v = q[1:]
    n = np.linalg.norm(v)
    if n < 1e-12:
        return np.zeros(3)
    return v / n * 2 * np.arctan2(n, q[0])


def exp_rot(v: np.ndarray) -> np.ndarray:
    a = np.linalg.norm(v)
    if a < 1e-12:
        return np.eye(3)
    return axis_angle(v / a, a)


def slerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    return a @ exp_rot(log_rot(a.T @ b) * t)


def orthonormalize(m: np.ndarray) -> np.ndarray:
    u, _, vt = np.linalg.svd(m)
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    return r


def triad(a1: np.ndarray, a2: np.ndarray, b1: np.ndarray, b2: np.ndarray) -> np.ndarray:
    """Rotação que leva a1 exatamente para b1 e a2 o mais perto possível de b2."""

    def frame(p: np.ndarray, q: np.ndarray) -> np.ndarray:
        e1 = unit(p)
        e2 = unit(q - (q @ e1) * e1)
        return np.column_stack([e1, e2, np.cross(e1, e2)])

    return frame(b1, b2) @ frame(a1, a2).T


def yaw_of(direction: np.ndarray) -> np.ndarray:
    """Rotação só em Y que leva −Z (frente do HumanoidRootPart) para a direção horizontal dada."""
    d = np.array([direction[0], 0.0, direction[2]])
    d = unit(d)
    return ry(np.arctan2(-d[0], -d[2]))


# ===== cinemática do R15 =====
def fk(pivot: np.ndarray, w: dict[str, np.ndarray]) -> dict[str, tuple[np.ndarray, np.ndarray]]:
    """Centro e rotação de mundo de cada peça. pivot = ponto da junta Root (meio da linha dos
    quadris), w = rotação de mundo de cada peça relativa ao repouso."""
    out: dict[str, tuple[np.ndarray, np.ndarray]] = {}
    c1 = JOINTS["Root"][3]
    out["LowerTorso"] = (pivot - w["LowerTorso"] @ c1, w["LowerTorso"])
    for part in PARTS[1:]:
        p0, _, c0, c1 = JOINTS[JOINT_OF[part]]
        pc, pr = out[p0]
        j = pc + pr @ c0
        out[part] = (j - w[part] @ c1, w[part])
    return out


def joint_pos(frames: dict[str, tuple[np.ndarray, np.ndarray]], joint: str) -> np.ndarray:
    p0, _, c0, _ = JOINTS[joint]
    pc, pr = frames[p0]
    return pc + pr @ c0


def two_bone(
    root: np.ndarray, target: np.ndarray, l1: float, l2: float, pole: np.ndarray
) -> tuple[np.ndarray, float]:
    """Posição do joelho/cotovelo para ligar root a target com segmentos l1 e l2, no plano que
    contém o polo. Devolve (meio, sobra): sobra > 0 quando o alvo está fora do alcance."""
    d = target - root
    dist = np.linalg.norm(d)
    reach = l1 + l2 - 1e-4
    gap = 0.0
    if dist > reach:
        gap = dist - reach
        dist = reach
    dist = max(dist, abs(l1 - l2) + 1e-4)
    u = unit(d)
    p = pole - root
    p = unit(p - (p @ u) * u)
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = np.sqrt(max(l1 * l1 - a * a, 0.0))
    return root + u * a + p * h, gap
