"""Retarget das capturas da CMU (ASF/AMC) para o R15 do soldado: laço, pés travados e fuzil.

Para cada clipe de CLIPES:
1. lê a tomada (asfamc), passa para a base do Roblox (180° em Y) e escala para a perna do R15;
2. escolhe o trecho do laço (entre apoios do mesmo pé, ou o par de quadros mais parecidos) e
   distribui a emenda pelo clipe inteiro (laço sem salto);
3. tira o deslocamento médio (o HumanoidRootPart anda pelo Humanoid) e trava os pés: no apoio o
   pé fica parado no chão do mundo (no espaço do personagem anda para trás a −v), rolando no
   calcanhar e na ponta como na captura; as pernas saem por IK de dois ossos com o joelho da
   captura como polo;
4. tronco e cabeça vêm das rotações da captura (o giro do peito no passo cai pela metade: as duas
   mãos estão no fuzil); os braços são uma camada por cima: IK até o fuzil preso ao peito na
   mesma pega do PostureController (HOLD_STAND), que é onde o IK do jogo vai pôr as mãos;
5. converte em CFrame de junta do Roblox (Transform da AnimationConstraint: rotação relativa ao
   repouso; só a Root tem translação) e grava assets/mocap/soldado/<clipe>.json para o kfs.luau.

A postura do servidor (PostureService) baixa o HumanoidRootPart (DROP) e, deitado, gira o C0 da
Root (PRONE_ROOT). Os clipes agachados e deitados são gravados RELATIVOS a isso (lidos do código,
não copiados) e o AuthoredHipHeight de cada clipe é o HipHeight da postura: o Animator escala a
translação da Root por HipHeight / AuthoredHipHeight.

Uso (Python do projeto ou do Blender; só numpy):
  uv run python -I tools/anim/retarget.py            # todos
  uv run python -I tools/anim/retarget.py trote      # só um
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

AQUI = Path(__file__).resolve().parent
if str(AQUI) not in sys.path:
    sys.path.insert(0, str(AQUI))

import asfamc  # noqa: E402
import r15  # noqa: E402
from r15 import axis_angle, exp_rot, log_rot, rx, ry, slerp, triad, unit  # noqa: E402

RAIZ = AQUI.parents[1]
MOCAP = RAIZ / "assets" / "mocap" / "cmu"
SAIDA = RAIZ / "assets" / "mocap" / "soldado"
POSTURE = RAIZ / "src" / "ServerScriptService" / "Modules" / "PostureService.luau"

FPS_SAIDA = 30.0
M_CMU = np.diag([-1.0, 1.0, -1.0])  # CMU (frente +Z) -> Roblox (frente −Z): 180° em Y
UP = r15.UP
X = np.array([1.0, 0.0, 0.0])

# ===== medidas do R15 (studs; r15.py, PLACEHOLDER até medir o corpo "Man" no Studio) =====
THIGH, SHIN, ANKLE_H = r15.THIGH, r15.SHIN, r15.ANKLE_H
H0 = r15.LEG  # altura do pivô da Root (meio dos quadris) em pé, sobre a sola
HIP_X = 0.5  # cada quadril a 0,5 stud do pivô (LowerTorso)
WAIST_Y = 0.4 * r15.S  # pivô da Root -> pivô da Waist
UT_Y = 0.8 * r15.S  # pivô da Waist -> centro do UpperTorso
SHOULDER = {
    "Left": np.array([-1.0, 0.563 * r15.S, 0.0]),
    "Right": np.array([1.0, 0.563 * r15.S, 0.0]),
}
UPPER = r15.UPPER_ARM_VEC  # pivô do ombro -> pivô do cotovelo (no braço)
FORE = r15.FOREARM_VEC  # cotovelo -> pulso
HAND_C = r15.HAND_CENTER  # pulso -> centro da mão
SOLE_BALL = np.array([0.0, -ANKLE_H, -0.45])  # bola do pé (no pé, a partir do tornozelo)
SOLE_HEEL = np.array([0.0, -ANKLE_H, 0.35])
SOLE_TOE = np.array([0.0, -ANKLE_H, r15.TOE_Z])

# HumanoidRootPart: HipHeight em pé (medido 2,40 com HeightScale 1,2 -> 2,5 com 1,25; PLACEHOLDER)
BASE_HIP = 2.5

# Pega do fuzil no peito: a MESMA do PostureController (HOLD_STAND), conferida pelo teste anim.luau.
# D-94: a pega antiga (0,2; 0,2; −0,7; 15°; −20°) deixava o antebraço direito 13 cm dentro do
# peito e a coronha 20 cm (simulação do Lune, Shared/ArmIK). A nova, com o tronco de lado (BLADE no
# PostureController), deixa braços e arma fora do corpo em todas as torções e flexões medidas.
HOLD_STAND = (np.array([0.25, 0.8, -1.5]), np.radians(55.0), np.radians(-20.0))
# M14 (fuzileiro dos EUA, Shared/WeaponArt): apoio 0,885 stud à frente do punho e 0,036 acima
SUPPORT_OFF = np.array([0.0, 0.036, -0.885])


# ===== postura do servidor (lida do PostureService.luau) =====
@dataclass
class Postura:
    drop: dict[str, float]
    min_hip: float
    prone_y: float
    prone_pitch: float  # rad

    def hip(self, stance: str) -> float:
        """HipHeight do Humanoid na postura."""
        if stance == "stand":
            return BASE_HIP
        return max(BASE_HIP - self.drop[stance], self.min_hip)

    def drop_eff(self, stance: str) -> float:
        return BASE_HIP - self.hip(stance)

    def k0(self, stance: str) -> np.ndarray:
        """C0 extra da Root na postura (4x4): deitado, CFrame.new(0, y, 0) * Angles(pitch, 0, 0)."""
        m = np.eye(4)
        if stance == "prone":
            m[:3, :3] = rx(self.prone_pitch)
            m[1, 3] = self.prone_y
        return m


def ler_postura(path: Path = POSTURE) -> Postura:
    s = path.read_text("utf-8")
    d = re.search(r"local DROP = \{ crouch = ([\d.]+), prone = ([\d.]+) \}", s)
    h = re.search(r"local MIN_HIP = ([\d.]+)", s)
    p = re.search(
        r"local PRONE_ROOT = CFrame\.new\(0, (-?[\d.]+), 0\) \* "
        r"CFrame\.Angles\(math\.rad\((-?[\d.]+)\)",
        s,
    )
    if not (d and h and p):
        raise SystemExit(f"não achei DROP/MIN_HIP/PRONE_ROOT em {path}")
    return Postura(
        drop={"crouch": float(d[1]), "prone": float(d[2])},
        min_hip=float(h[1]),
        prone_y=float(p[1]),
        prone_pitch=float(np.radians(float(p[2]))),
    )


# ===== utilidades =====
def yaw_mat(a: float) -> np.ndarray:
    return ry(a)


def yaw_of_dir(d: np.ndarray) -> float:
    """Ângulo em Y que leva −Z para a direção horizontal d."""
    return float(np.arctan2(-d[0], -d[2]))


def heading_of(r: np.ndarray) -> float:
    """Guinada de uma rotação (para onde vai o −Z dela, no plano)."""
    f = r @ np.array([0.0, 0.0, -1.0])
    return yaw_of_dir(f)


def mats_log(ws: np.ndarray) -> np.ndarray:
    return np.array([log_rot(w) for w in ws])


def mats_exp(vs: np.ndarray) -> np.ndarray:
    return np.array([exp_rot(v) for v in vs])


def smooth(x: np.ndarray, k: int, cyclic: bool) -> np.ndarray:
    """Média móvel (janela 2k+1), cíclica ou com borda repetida, no eixo 0."""
    if k <= 0:
        return x
    n = len(x)
    if cyclic:
        idx = (np.arange(n)[:, None] + np.arange(-k, k + 1)[None, :]) % n
    else:
        idx = np.clip(np.arange(n)[:, None] + np.arange(-k, k + 1)[None, :], 0, n - 1)
    return x[idx].mean(axis=1)


def smooth_rot(ws: np.ndarray, k: int, cyclic: bool) -> np.ndarray:
    """Suaviza rotações pela média dos vetores de rotação relativos à média."""
    if k <= 0:
        return ws
    ref = ws[len(ws) // 2]
    rel = np.array([log_rot(ref.T @ w) for w in ws])
    return np.array([ref @ exp_rot(v) for v in smooth(rel, k, cyclic)])


def smoothstep(x: np.ndarray | float) -> np.ndarray | float:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


# ===== leitura e base =====
@dataclass
class Take:
    name: str
    fps: float
    n: int
    k: float  # escala CMU (m) -> R15 (studs)
    dy: float  # deslocamento vertical (studs) que leva o tornozelo de repouso ao do R15
    pos: dict[str, np.ndarray]  # pontos (F, 3) em studs, base do Roblox, chão em y = 0
    rot: dict[str, np.ndarray]  # rotações de mundo (F, 3, 3) relativas ao repouso, base do Roblox
    foot_flat_pitch: dict[str, float]  # inclinação tornozelo->bola com o pé chato (rad)


PONTOS = {
    "hipL": "lhipjoint",
    "hipR": "rhipjoint",
    "kneeL": "lfemur",
    "kneeR": "rfemur",
    "ankleL": "ltibia",
    "ankleR": "rtibia",
    "ballL": "lfoot",
    "ballR": "rfoot",
    "toeL": "ltoes",
    "toeR": "rtoes",
    "waist": "lowerback",
    "chest": "thorax",
    "headTop": "head",
    "shoulderL": "lclavicle",
    "shoulderR": "rclavicle",
    "elbowL": "lhumerus",
    "elbowR": "rhumerus",
    "wristL": "lradius",
    "wristR": "rradius",
}


def _rest_heights(sk: asfamc.Skeleton) -> tuple[float, float]:
    """(fêmur + tíbia, altura do tornozelo sobre o ponto mais baixo do pé), em m, no repouso."""
    m = asfamc.forward_kinematics(sk, [{}], 120.0)
    ank = m.end["ltibia"][0, 1]
    low = min(m.end["lfoot"][0, 1], m.end["ltoes"][0, 1])
    leg = (sk.bones["lfemur"].length + sk.bones["ltibia"].length) * sk.scale_m
    return leg, ank - low


def load_take(name: str, fps: float) -> Take:
    subj = name.split("_")[0]
    sk = asfamc.parse_asf(MOCAP / f"{subj}.asf")
    m = asfamc.forward_kinematics(sk, asfamc.parse_amc(MOCAP / f"{name}.amc"), fps)
    leg_m, ank_m = _rest_heights(sk)
    k = (THIGH + SHIN) / (leg_m / r15.STUD_M)  # escala que casa fêmur + tíbia com coxa + canela
    # chão: 3º percentil do ponto mais baixo dos pés
    low = np.minimum.reduce(
        [m.end[b][:, 1] for b in ("lfoot", "rfoot", "ltoes", "rtoes", "ltibia", "rtibia")]
    )
    floor = float(np.percentile(low, 3))
    dy = ANKLE_H - k * ank_m / r15.STUD_M
    pos: dict[str, np.ndarray] = {}
    for key, bone in PONTOS.items():
        p = (m.end[bone] - [0.0, floor, 0.0]) @ M_CMU.T / r15.STUD_M
        pos[key] = np.column_stack([p[:, 0] * k, p[:, 1] * k + dy, p[:, 2] * k])
    pos["pelvis"] = (pos["hipL"] + pos["hipR"]) / 2
    rot = {"root": np.einsum("ij,fjk,kl->fil", M_CMU, m.root_rot, M_CMU)}
    for b in ("lowerback", "upperback", "thorax", "head", "lfoot", "rfoot", "lfemur", "rfemur"):
        rot[b] = np.einsum("ij,fjk,kl->fil", M_CMU, m.rot[b], M_CMU)
    # pé chato de referência: inclinação tornozelo -> bola no repouso do ASF
    flat = {}
    for side, b in (("L", "lfoot"), ("R", "rfoot")):
        d = M_CMU @ (sk.bones[b].direction / np.linalg.norm(sk.bones[b].direction))
        flat[side] = float(np.arctan2(-d[1], np.hypot(d[0], d[2])))
    return Take(name, fps, len(m.root_pos), k, dy, pos, rot, flat)


# ===== pose do R15 =====
PARTS = r15.PARTS


@dataclass
class Clip:
    """Quadros do R15: rotação de mundo de cada peça relativa ao repouso e o pivô da Root, no
    espaço do personagem (chão em y = 0, frente −Z, studs)."""

    name: str
    fps: float
    w: dict[str, np.ndarray]  # (F, 3, 3)
    pivot: np.ndarray  # (F, 3)
    loop: bool
    stance: str
    speed: float = 0.0  # studs/s naturais (anda no chão sem escorregar nessa velocidade)
    meta: dict = field(default_factory=dict)

    @property
    def n(self) -> int:
        return len(self.pivot)

    def frames(self, i: int) -> dict[str, tuple[np.ndarray, np.ndarray]]:
        return r15.fk(self.pivot[i], {p: self.w[p][i] for p in PARTS})


def chest_frame(lower: np.ndarray, upper: np.ndarray, pivot: np.ndarray) -> tuple:
    """Centro do UpperTorso e pivô da Waist."""
    waist = pivot + lower @ np.array([0.0, WAIST_Y, 0.0])
    return waist + upper @ np.array([0.0, UT_Y, 0.0]), waist


def hips(pivot: np.ndarray, lower: np.ndarray) -> dict[str, np.ndarray]:
    return {
        "L": pivot + lower @ np.array([-HIP_X, 0.0, 0.0]),
        "R": pivot + lower @ np.array([HIP_X, 0, 0]),
    }


# ===== pernas =====
def leg_ik(
    hip: np.ndarray, ankle: np.ndarray, pole: np.ndarray, fallback_x: np.ndarray
) -> tuple[np.ndarray, np.ndarray, float]:
    """Rotações de coxa e canela (R15) ligando quadril e tornozelo; polo = ponto à frente do joelho.
    Devolve também a sobra (> 0 quando o tornozelo está fora do alcance)."""
    knee, gap = r15.two_bone(hip, ankle, THIGH, SHIN, pole)
    td = unit(knee - hip)
    sd = unit(ankle - knee)
    c = np.cross(td, sd)
    if np.linalg.norm(c) < 1e-4:
        hx = fallback_x - (fallback_x @ td) * td
    else:
        hx = -c
    hx = unit(hx)
    return triad(r15.DOWN, X, td, hx), triad(r15.DOWN, X, sd, hx), gap


# ===== braços no fuzil =====
def hold_cf(hold: tuple[np.ndarray, float, float]) -> tuple[np.ndarray, np.ndarray]:
    """(posição, rotação) do pivô do fuzil (no punho, boca em −Z) no UpperTorso."""
    p, yaw, pitch = hold
    return p, ry(yaw) @ rx(pitch)


def _hand_rot(rifle: np.ndarray, side: str) -> np.ndarray:
    """Rotação de mundo da mão segurando o fuzil (rifle = rotação do fuzil no mundo).
    Direita no punho: palma para a esquerda do fuzil, dedos para a frente e para baixo.
    Esquerda sob o guarda-mão: palma para cima, dedos para a frente e cruzando para a direita."""
    if side == "Right":
        fingers = rifle @ unit(np.array([0.0, -0.55, -0.85]))
        palm = rifle @ np.array([-1.0, 0.0, 0.0])
        # na mão direita em repouso a palma olha para −X e os dedos para −Y
        return triad(r15.DOWN, np.array([-1.0, 0, 0]), fingers, palm)
    fingers = rifle @ unit(np.array([0.45, 0.15, -0.9]))
    palm = rifle @ np.array([0.0, 1.0, 0.0])
    return triad(r15.DOWN, X, fingers, palm)


def arm_ik(
    shoulder: np.ndarray,
    hand_center: np.ndarray,
    hand_w: np.ndarray,
    pole: np.ndarray,
    side: str,
    outward: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, float]:
    """Braço do R15 até a mão: rotações de mundo do braço e do antebraço, e o erro (studs).
    outward = +X do tronco no mundo (direita do soldado)."""
    wrist = hand_center - hand_w @ HAND_C
    u0 = UPPER[side]
    l1, l2 = float(np.linalg.norm(u0)), float(np.linalg.norm(FORE))
    elbow, gap = r15.two_bone(shoulder, wrist, l1, l2, pole)
    d1 = unit(elbow - shoulder)
    d2 = unit(wrist - elbow)
    # O pivô do ombro do R15 fica na quina de dentro do braço: o osso (pivô -> cotovelo) é
    # diagonal na peça. O giro em torno dele põe o lado de fora da peça para fora do tronco.
    sgn = -1.0 if side == "Left" else 1.0
    w_up = triad(unit(u0), np.array([sgn, 0.0, 0.0]), d1, sgn * outward)
    w_fore = triad(r15.DOWN, X, d2, w_up @ X)
    return w_up, w_fore, gap


def rifle_arms(
    w: dict[str, np.ndarray],
    pivot: np.ndarray,
    grip: tuple[np.ndarray, np.ndarray],
    poles: dict[str, np.ndarray],
) -> dict[str, float]:
    """Põe os dois braços no fuzil (in place em w). grip = (posição, rotação) do pivô do fuzil no
    UpperTorso; poles = polo de cada cotovelo no UpperTorso. Devolve a sobra de alcance."""
    n = len(pivot)
    err = {"Left": 0.0, "Right": 0.0}
    hp, hr = grip
    for i in range(n):
        lo, up = w["LowerTorso"][i], w["UpperTorso"][i]
        ut, _ = chest_frame(lo, up, pivot[i])
        rifle = up @ hr
        grip = ut + up @ hp
        support = grip + rifle @ SUPPORT_OFF
        for side, target in (("Right", grip), ("Left", support)):
            hw = _hand_rot(rifle, side)
            sh = ut + up @ SHOULDER[side]
            wu, wf, gap = arm_ik(sh, target, hw, ut + up @ poles[side], side, up @ X)
            w[f"{side}UpperArm"][i] = wu
            w[f"{side}LowerArm"][i] = wf
            w[f"{side}Hand"][i] = hw
            err[side] = max(err[side], gap)
    return err


# polos dos cotovelos no UpperTorso: os MESMOS do jogo (Shared/ArmIK.POLES.stand, IKControl.Pole)
POLES_STAND = {"Right": np.array([3.2, -2.6, 0.4]), "Left": np.array([-3.0, -3.0, -1.2])}
GRIP = hold_cf(HOLD_STAND)
# pega de recarga: a MESMA do Shared/ArmIK.HOLDS.reload (conferida pelo tests/luau/faca)
HOLD_RELOAD = (np.array([0.2, 1.0, -1.3]), np.radians(60.0), np.radians(-20.0))
GRIP_RELOAD = hold_cf(HOLD_RELOAD)


# ===== laço =====
def close_loop_vec(x: np.ndarray) -> np.ndarray:
    """x[0..n] com x[n] ~ x[0]: distribui a diferença para x[n] == x[0] (devolve n+1 linhas)."""
    n = len(x) - 1
    r = x[n] - x[0]
    a = np.linspace(0.0, 1.0, n + 1)
    shape = (n + 1,) + (1,) * (x.ndim - 1)
    return x - a.reshape(shape) * r


def close_loop_rot(ws: np.ndarray) -> np.ndarray:
    n = len(ws) - 1
    corr = log_rot(ws[n].T @ ws[0])
    return np.array([ws[i] @ exp_rot(corr * (i / n)) for i in range(n + 1)])


def resample(clip: Clip, fps: float) -> Clip:
    """Reamostra para fps; nos laços inclui o último quadro igual ao primeiro."""
    n = clip.n
    dur = (n - 1) / clip.fps
    m = max(int(round(dur * fps)), 1)
    ts = np.linspace(0.0, dur, m + 1)
    src = ts * clip.fps
    i0 = np.clip(np.floor(src).astype(int), 0, n - 1)
    i1 = np.clip(i0 + 1, 0, n - 1)
    a = src - i0
    w = {}
    for p in PARTS:
        ws = clip.w[p]
        w[p] = np.array([slerp(ws[j0], ws[j1], t) for j0, j1, t in zip(i0, i1, a, strict=True)])
    piv = clip.pivot[i0] * (1 - a)[:, None] + clip.pivot[i1] * a[:, None]
    out = Clip(
        clip.name,
        m / dur if dur > 0 else fps,
        w,
        piv,
        clip.loop,
        clip.stance,
        clip.speed,
        dict(clip.meta),
    )
    if clip.loop:
        for p in PARTS:
            out.w[p][-1] = out.w[p][0]
        out.pivot[-1] = out.pivot[0]
    return out


# ===== apoio dos pés =====
def _runs(c: np.ndarray, cyclic: bool) -> list[tuple[int, int]]:
    """Trechos [a, b] (inclusivos) onde c é verdadeiro; cíclicos podem ter b < a (dá a volta)."""
    n = len(c)
    if c.all():
        return [(0, n - 1)]
    out = []
    i = 0
    while i < n:
        if c[i]:
            j = i
            while j + 1 < n and c[j + 1]:
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    if cyclic and len(out) > 1 and out[0][0] == 0 and out[-1][1] == n - 1:
        a, _ = out.pop()
        out[0] = (a, out[0][1])
    return out


def _clean(c: np.ndarray, fps: float, cyclic: bool) -> np.ndarray:
    """Tapa buracos curtos (< 40 ms) e tira apoios curtos (< 60 ms)."""
    c = c.copy()
    gap, short = max(int(0.04 * fps), 1), max(int(0.06 * fps), 2)
    for a, b in _runs(~c, cyclic):
        ln = (b - a) % len(c) + 1
        if ln <= gap:
            for i in range(ln):
                c[(a + i) % len(c)] = True
    for a, b in _runs(c, cyclic):
        ln = (b - a) % len(c) + 1
        if ln < short:
            for i in range(ln):
                c[(a + i) % len(c)] = False
    return c


def detect_contact(
    ank: np.ndarray, ball: np.ndarray, fps: float, ground_speed: np.ndarray, cyclic: bool
) -> np.ndarray:
    """Apoio do pé: ponto mais baixo (tornozelo ou bola) perto do chão e parado no chão do mundo.
    ground_speed: velocidade (studs/s, 3D) do chão no espaço dos pontos (no espaço do personagem
    que anda a v para −Z, o chão vai a +v em Z)."""
    h_ank = ank[:, 1] - ANKLE_H
    h_ball = ball[:, 1] - np.percentile(ball[:, 1], 2)
    low = np.minimum(h_ank, h_ball)
    edge = "wrap" if cyclic else "edge"

    def vel(p: np.ndarray) -> np.ndarray:
        q = np.pad(p, ((1, 1), (0, 0)), mode=edge)
        d = (q[2:] - q[:-2]) * fps / 2 - ground_speed
        return np.hypot(d[:, 0], d[:, 2])

    spd = np.where(h_ank < h_ball, vel(ank), vel(ball))
    vmax = max(1.6, 0.3 * float(np.linalg.norm(ground_speed)))
    return _clean((low < 0.28) & (spd < vmax), fps, cyclic)


def foot_pitch(wf: np.ndarray) -> np.ndarray:
    """Inclinação do pé (rad): > 0 com a ponta para cima."""
    f = np.einsum("fij,j->fi", wf, np.array([0.0, 0.0, -1.0]))
    return np.arctan2(f[:, 1], np.hypot(f[:, 0], f[:, 2]))


def plant_feet(
    ank: np.ndarray,
    wf: np.ndarray,
    contact: np.ndarray,
    fps: float,
    v: float,
    cyclic: bool,
    flat_all: bool = False,
) -> tuple[np.ndarray, np.ndarray, float]:
    """Trava o pé no chão durante o apoio. No espaço do personagem (que anda a v para −Z) o pé
    apoiado anda a +v em Z; rola no calcanhar (ponta para cima) e na bola (calcanhar no ar) com a
    inclinação da captura. Fora do apoio, a trajetória da captura recebe a correção interpolada
    entre o apoio anterior e o seguinte. Devolve tornozelo, rotação do pé e o escorregamento
    máximo (studs) que sobrou no apoio."""
    n = len(ank)
    pitch = foot_pitch(wf)
    runs = _runs(contact, cyclic)
    out_a = ank.copy()
    out_w = wf.copy()
    if not runs:
        return out_a, out_w, 0.0
    flat0 = float(np.median(pitch[contact])) if contact.any() else 0.0
    vel = np.array([0.0, 0.0, v])
    offs: dict[int, tuple[np.ndarray, np.ndarray]] = {}  # quadro -> (desloc., rot. de correção)
    planted = np.zeros(n, dtype=bool)
    for a, b in runs:
        ln = (b - a) % n + 1
        idx = [(a + i) % n for i in range(ln)]
        rel = np.array([pitch[i] - flat0 for i in idx])
        m = idx[int(np.argmin(np.abs(rel)))]
        hd = np.array([heading_of(wf[i]) for i in idx])
        yaw = float(np.arctan2(np.sin(hd).mean(), np.cos(hd).mean()))
        base = ank[m].copy()
        base[1] = ANKLE_H
        for j, i in enumerate(idx):
            dt = (j - idx.index(m)) / fps
            p_flat = base + vel * dt
            th = 0.0 if flat_all else float(np.clip(rel[j], np.radians(-55), np.radians(30)))
            yw = ry(yaw)
            w = yw @ rx(th)
            piv = SOLE_HEEL if th >= 0 else SOLE_BALL
            out_a[i] = p_flat + yw @ piv - w @ piv
            out_w[i] = w
            planted[i] = True
            offs[i] = (out_a[i] - ank[i], w @ wf[i].T)
    # balanço: correção interpolada entre o fim de um apoio e o início do próximo
    order = sorted(runs, key=lambda r: r[0])
    for k, (_, b) in enumerate(order):
        a2 = order[(k + 1) % len(order)][0] if (cyclic or k + 1 < len(order)) else None
        if a2 is None:
            for i in range(b + 1, n):
                out_a[i] = ank[i] + offs[b][0]
                out_w[i] = offs[b][1] @ wf[i]
            continue
        ln = (a2 - b) % n - 1
        if ln <= 0:
            continue
        d0, r0 = offs[b]
        d1, r1 = offs[a2]
        for j in range(1, ln + 1):
            i = (b + j) % n
            u = float(smoothstep(j / (ln + 1)))
            out_a[i] = ank[i] + d0 * (1 - u) + d1 * u
            out_w[i] = slerp(r0, r1, u) @ wf[i]
    if not cyclic and order[0][0] > 0:
        a0 = order[0][0]
        for i in range(a0):
            out_a[i] = ank[i] + offs[a0][0]
            out_w[i] = offs[a0][1] @ wf[i]
    # nada da sola abaixo do chão no balanço
    for i in range(n):
        if planted[i]:
            continue
        low = min((out_w[i] @ s)[1] for s in (SOLE_BALL, SOLE_HEEL, SOLE_TOE))
        if out_a[i][1] + low < 0:
            out_a[i][1] = -low
    # escorregamento que sobrou: ponto mais baixo da sola contra o chão que anda a +v
    slide = 0.0
    for a, b in runs:
        ln = (b - a) % n + 1
        for j in range(ln - 1):
            i0, i1 = (a + j) % n, (a + j + 1) % n
            for s in (SOLE_BALL, SOLE_HEEL):
                p0 = out_a[i0] + out_w[i0] @ s
                p1 = out_a[i1] + out_w[i1] @ s
                if p0[1] < 0.02 and p1[1] < 0.02:
                    d = p1 - p0 - vel / fps
                    slide = max(slide, float(np.hypot(d[0], d[2])))
    return out_a, out_w, slide


# ===== montagem do corpo =====
def legs_from_targets(
    w: dict[str, np.ndarray],
    pivot: np.ndarray,
    ank: dict[str, np.ndarray],
    wfoot: dict[str, np.ndarray],
    knee: dict[str, np.ndarray],
    cyclic: bool,
) -> tuple[np.ndarray, float]:
    """IK das pernas; baixa o quadril onde o pé não alcança. Devolve o pivô e a sobra máxima."""
    n = len(pivot)
    reach = THIGH + SHIN - 1e-3
    drop = np.zeros(n)
    for i in range(n):
        h = hips(pivot[i], w["LowerTorso"][i])
        for s in "LR":
            d = ank[s][i] - h[s]
            c = d @ d - reach * reach
            if c > 0:
                disc = d[1] * d[1] - c
                need = -d[1] - np.sqrt(max(disc, 0.0))
                drop[i] = max(drop[i], need)
    drop = np.maximum(drop, smooth(drop, max(int(0.05 * 120), 1), cyclic))
    piv = pivot - np.outer(drop, UP)
    gap = 0.0
    for i in range(n):
        lo = w["LowerTorso"][i]
        h = hips(piv[i], lo)
        for s, side in (("L", "Left"), ("R", "Right")):
            pole = knee[s][i] + lo @ np.array([0.0, 0.0, -0.6])
            wt, ws, g = leg_ik(h[s], ank[s][i], pole, lo @ X)
            w[f"{side}UpperLeg"][i] = wt
            w[f"{side}LowerLeg"][i] = ws
            w[f"{side}Foot"][i] = wfoot[s][i]
            gap = max(gap, g)
    return piv, gap


def mean_rot(ws: np.ndarray) -> np.ndarray:
    ref = ws[0]
    for _ in range(3):
        d = np.mean([log_rot(ref.T @ w) for w in ws], axis=0)
        ref = ref @ exp_rot(d)
    return ref


def damp_rel(parent: np.ndarray, child: np.ndarray, k: float) -> np.ndarray:
    """Reduz a oscilação da rotação do filho relativa ao pai em torno da média (k = fração que
    fica)."""
    rel = np.einsum("fji,fjk->fik", parent, child)
    ref = mean_rot(rel)
    out = np.array([ref @ exp_rot(log_rot(ref.T @ r) * k) for r in rel])
    return np.einsum("fij,fjk->fik", parent, out)


def gaze(
    w: dict[str, np.ndarray],
    target: np.ndarray,
    amount: float,
    keep: float,
    pitch_down: float = 0.0,
) -> None:
    """Põe o olhar da cabeça na direção alvo (frente do personagem): corrige a média e deixa
    `keep` da oscilação da captura."""
    hd = w["Head"]
    ref = mean_rot(hd)
    f = ref @ np.array([0.0, 0.0, -1.0])
    t = unit(rx(-pitch_down) @ target) if pitch_down else unit(target)
    corr = r15.swing(f, t)
    corr = exp_rot(log_rot(corr) * amount)
    out = []
    for h in hd:
        dev = log_rot(ref.T @ h) * keep
        out.append(corr @ ref @ exp_rot(dev))
    w["Head"] = np.array(out)


def base_w(take: Take, idx: np.ndarray, yaw: float) -> dict[str, np.ndarray]:
    """Pelve, peito e cabeça da captura nos quadros idx, girados por yaw."""
    yr = ry(yaw)
    w = {p: np.repeat(np.eye(3)[None], len(idx), axis=0) for p in PARTS}
    w["LowerTorso"] = np.einsum("ij,fjk->fik", yr, take.rot["root"][idx])
    w["UpperTorso"] = np.einsum("ij,fjk->fik", yr, take.rot["thorax"][idx])
    w["Head"] = np.einsum("ij,fjk->fik", yr, take.rot["head"][idx])
    return w


def take_points(take: Take, idx: np.ndarray, yaw: float) -> dict[str, np.ndarray]:
    yr = ry(yaw)
    return {k: v[idx] @ yr.T for k, v in take.pos.items()}


def foot_w(take: Take, idx: np.ndarray, yaw: float) -> dict[str, np.ndarray]:
    yr = ry(yaw)
    out = {}
    for s, b in (("L", "lfoot"), ("R", "rfoot")):
        out[s] = np.einsum("ij,fjk->fik", yr, take.rot[b][idx])
    return out


def finish_upper(
    w: dict[str, np.ndarray],
    pivot: np.ndarray,
    cyclic: bool,
    chest_keep: float,
    gaze_amount: float = 0.8,
    gaze_keep: float = 0.5,
) -> dict[str, float]:
    w["UpperTorso"] = damp_rel(w["LowerTorso"], w["UpperTorso"], chest_keep)
    gaze(w, np.array([0.0, 0.0, -1.0]), gaze_amount, gaze_keep)
    return rifle_arms(w, pivot, GRIP, POLES_STAND)


# ===== clipes de passada (andar, trote, corrida, agachado andando) =====
def pick_cycle(take: Take, contact_l: np.ndarray, cycles: int, lo: float, hi: float) -> tuple:
    """Escolhe [a, b] entre dois apoios do pé esquerdo, `cycles` ciclos, dentro de [lo, hi] (s),
    com a menor diferença de pose entre a e b (posições relativas à pelve)."""
    starts = [a for a, _ in _runs(contact_l, False) if a > 0]
    best = None
    keys = ("kneeL", "kneeR", "ankleL", "ankleR", "chest", "headTop", "ballL", "ballR")
    for i in range(len(starts) - cycles):
        a, b = starts[i], starts[i + cycles]
        if a / take.fps < lo or b / take.fps > hi:
            continue
        d = 0.0
        for kk in keys:
            pa = take.pos[kk][a] - take.pos["pelvis"][a]
            pb = take.pos[kk][b] - take.pos["pelvis"][b]
            d += float(np.linalg.norm(pa - pb))
        if best is None or d < best[0]:
            best = (d, a, b)
    if best is None:
        raise SystemExit(f"{take.name}: sem {cycles} ciclo(s) em [{lo}, {hi}] s")
    return best[1], best[2]


def gait_clip(
    name: str,
    take: Take,
    cycles: int,
    stance: str,
    lo: float = 0.0,
    hi: float = 1e9,
    extra_drop: float = 0.0,
    chest_keep: float = 0.5,
    lean: float = 0.0,
    stride_k: float = 0.5,
) -> Clip:
    n_all = take.n
    pel = take.pos["pelvis"]
    vb = np.gradient(pel, axis=0) * take.fps
    zero = np.zeros(3)
    cl = detect_contact(take.pos["ankleL"], take.pos["ballL"], take.fps, zero, False)
    a, b = pick_cycle(take, cl, cycles, lo, hi)
    idx = np.arange(a, b + 1)
    d = pel[b] - pel[a]
    d[1] = 0.0
    yaw = -yaw_of_dir(d)  # leva a direção do trajeto para −Z
    T = (b - a) / take.fps
    v = float(np.linalg.norm(d)) / T  # studs/s
    pts = take_points(take, idx, yaw)
    n = len(idx)
    t = np.arange(n) / take.fps
    # espaço do personagem: o HumanoidRootPart anda a v para −Z, centrado na pelve média
    track = np.outer(t - T / 2, np.array([0.0, 0.0, -v]))
    p0 = pts["pelvis"].mean(axis=0) - track.mean(axis=0)
    p0[1] = 0.0
    for kk in pts:
        pts[kk] = pts[kk] - track - p0
    # Passada: as pernas do R15 (0,70 m) são mais curtas que as da captura. Com a escala da perna
    # (k) a passada encolhe e a cadência no jogo dispara; com a passada original, a perna abre
    # demais. Meio-termo: passada na escala k**stride_k (0,5 = raiz).
    f = take.k ** (stride_k - 1.0)
    if abs(f - 1.0) > 1e-6:
        for kk in pts:
            if kk != "pelvis":
                pts[kk][:, 2] = pts["pelvis"][:, 2] + (pts[kk][:, 2] - pts["pelvis"][:, 2]) * f
        v *= f
    w = base_w(take, idx, yaw)
    wf = foot_w(take, idx, yaw)
    # laço: fecha posições e rotações (último quadro == primeiro)
    for kk in pts:
        pts[kk] = close_loop_vec(pts[kk])
    for p in ("LowerTorso", "UpperTorso", "Head"):
        w[p] = close_loop_rot(w[p])
    for s in "LR":
        wf[s] = close_loop_rot(wf[s])
    # trabalha nos n−1 quadros únicos (cíclico) e repete o primeiro no fim
    m = n - 1
    sl = slice(0, m)
    ground = np.array([0.0, 0.0, v])
    ank, wfoot, knee, slide = {}, {}, {}, 0.0
    for s in "LR":
        c = detect_contact(pts[f"ankle{s}"][sl], pts[f"ball{s}"][sl], take.fps, ground, True)
        ank[s], wfoot[s], sd = plant_feet(pts[f"ankle{s}"][sl], wf[s][sl], c, take.fps, v, True)
        knee[s] = pts[f"knee{s}"][sl] + (ank[s] - pts[f"ankle{s}"][sl])
        slide = max(slide, sd)
    wc = {p: w[p][sl].copy() for p in PARTS}
    piv = pts["pelvis"][sl] - np.array([0.0, extra_drop, 0.0])
    if lean:
        lr = rx(-lean)
        wc["UpperTorso"] = np.einsum("fij,jk->fik", wc["UpperTorso"], lr)
    piv, gap = legs_from_targets(wc, piv, ank, wfoot, knee, True)
    err = finish_upper(wc, piv, True, chest_keep)
    clip = Clip(
        name,
        take.fps,
        {p: np.concatenate([wc[p], wc[p][:1]]) for p in PARTS},
        np.concatenate([piv, piv[:1]]),
        True,
        stance,
        v,
    )
    stride_m = v * T / cycles * r15.STUD_M  # ciclo inteiro (dois passos)
    clip.meta = {
        "fonte": f"CMU {take.name}, quadros {a}-{b} a {take.fps:g} qps",
        "ciclos": cycles,
        "velocidade_m_s": round(v * r15.STUD_M, 3),
        "passada_ciclo_m": round(stride_m, 3),
        "cadencia_passos_s": round(2 * cycles / T, 3),
        "escorregamento_max_cm": round(slide * r15.STUD_M * 100, 2),
        "perna_sem_alcance_cm": round(gap * r15.STUD_M * 100, 2),
        "erro_mao_cm": round(max(err.values()) * r15.STUD_M * 100, 2),
        "escala_cmu_r15": round(take.k, 4),
    }
    del vb, n_all
    return clip


# ===== parado (laço sem passada) =====
def pick_still(take: Take, lo: float, hi: float, dmin: float, dmax: float) -> tuple[int, int]:
    """Par (a, b) dentro de [lo, hi] s, com duração entre dmin e dmax, cujas poses (posições
    relativas à pelve e velocidades) mais se parecem: o laço fecha quase sozinho."""
    keys = ("kneeL", "kneeR", "ankleL", "ankleR", "chest", "headTop", "elbowL", "elbowR")
    i0, i1 = int(lo * take.fps), min(int(hi * take.fps), take.n - 1)
    feat = np.concatenate(
        [take.pos[k][i0 : i1 + 1] - take.pos["pelvis"][i0 : i1 + 1] for k in keys]
        + [take.pos["pelvis"][i0 : i1 + 1, 1:2]],
        axis=1,
    )
    vel = np.gradient(feat, axis=0) * take.fps
    best = None
    step = max(int(take.fps / 30), 1)
    for a in range(0, len(feat), step):
        bs = np.arange(a + int(dmin * take.fps), min(a + int(dmax * take.fps), len(feat)), step)
        if len(bs) == 0:
            continue
        d = np.linalg.norm(feat[bs] - feat[a], axis=1) + 0.15 * np.linalg.norm(
            vel[bs] - vel[a], axis=1
        )
        j = int(np.argmin(d))
        if best is None or d[j] < best[0]:
            best = (float(d[j]), a + i0, int(bs[j]) + i0)
    if best is None:
        raise SystemExit(f"{take.name}: trecho parado não encontrado")
    return best[1], best[2]


def still_clip(
    name: str,
    take: Take,
    lo: float,
    hi: float,
    dmin: float,
    dmax: float,
    extra_drop: float = 0.0,
    chest_keep: float = 1.0,
) -> tuple[Clip, dict]:
    """Laço parado de pé: pés travados e chatos na posição média, pernas por IK."""
    a, b = pick_still(take, lo, hi, dmin, dmax)
    idx = np.arange(a, b + 1)
    yaw = -float(
        np.arctan2(
            *np.mean(
                [[np.sin(h), np.cos(h)] for h in [heading_of(r) for r in take.rot["root"][idx]]],
                axis=0,
            )
        )
    )
    pts = take_points(take, idx, yaw)
    w = base_w(take, idx, yaw)
    wf = foot_w(take, idx, yaw)
    c = pts["pelvis"].mean(axis=0)
    c[1] = 0.0
    for kk in pts:
        pts[kk] = close_loop_vec(pts[kk] - c)
    for p in ("LowerTorso", "UpperTorso", "Head"):
        w[p] = close_loop_rot(w[p])
    m = len(idx) - 1
    sl = slice(0, m)
    ank, wfoot, knee = {}, {}, {}
    for s in "LR":
        p = pts[f"ankle{s}"][sl].mean(axis=0)
        p[1] = ANKLE_H
        yw = heading_of(mean_rot(wf[s][sl]))
        ank[s] = np.repeat(p[None], m, axis=0)
        wfoot[s] = np.repeat(ry(yw)[None], m, axis=0)
        knee[s] = pts[f"knee{s}"][sl]
    wc = {p: w[p][sl].copy() for p in PARTS}
    piv = pts["pelvis"][sl] - np.array([0.0, extra_drop, 0.0])
    piv, gap = legs_from_targets(wc, piv, ank, wfoot, knee, True)
    err = finish_upper(wc, piv, True, chest_keep, gaze_amount=0.85, gaze_keep=0.6)
    clip = Clip(
        name,
        take.fps,
        {p: np.concatenate([wc[p], wc[p][:1]]) for p in PARTS},
        np.concatenate([piv, piv[:1]]),
        True,
        "stand",
        0.0,
    )
    clip.meta = {
        "fonte": f"CMU {take.name}, quadros {a}-{b} a {take.fps:g} qps",
        "perna_sem_alcance_cm": round(gap * r15.STUD_M * 100, 2),
        "erro_mao_cm": round(max(err.values()) * r15.STUD_M * 100, 2),
    }
    return clip, {"ank": ank, "wfoot": wfoot}


# ===== agachado parado: de joelho =====
def kneel_clip(name: str, base: Clip) -> Clip:
    """Joelho direito no chão, pé esquerdo à frente, fuzil na pega de sempre. O balanço e a
    respiração (pelve, peito e cabeça) vêm do laço parado da captura (base), em torno da pose."""
    n = base.n
    yaw_fr = np.radians(8.0)
    wfr = ry(yaw_fr) @ rx(np.radians(-62.0))  # pé direito: dedos dobrados no chão
    ball = np.array([0.62, 0.0, 1.55])
    ank_r = ball - wfr @ SOLE_BALL
    kh = 0.38  # pivô do joelho com a frente da canela no chão
    dz = np.sqrt(max(SHIN**2 - (ank_r[1] - kh) ** 2 - 0.05**2, 0.0))
    knee_r = ank_r + np.array([-0.05, kh - ank_r[1], -dz])
    lean_t = 0.22  # coxa direita um pouco para trás do joelho
    hip_r = knee_r + np.array([0.0, np.sqrt(THIGH**2 - lean_t**2), lean_t])
    pel0 = ry(np.radians(10.0)) @ rx(np.radians(-6.0))  # pelve meio de lado, para a frente
    pivot0 = hip_r - pel0 @ np.array([HIP_X, 0.0, 0.0])
    shift = np.array([pivot0[0], 0.0, pivot0[2]])
    pivot0, knee_r, ank_r = pivot0 - shift, knee_r - shift, ank_r - shift
    ank_l = pivot0 + pel0 @ np.array([-HIP_X - 0.1, 0.0, -1.25])
    ank_l[1] = ANKLE_H
    wfl = ry(np.radians(-12.0))
    # balanço da captura em torno da média
    lo_m = mean_rot(base.w["LowerTorso"])
    up_rel = np.einsum("fji,fjk->fik", base.w["LowerTorso"], base.w["UpperTorso"])
    up_m = mean_rot(up_rel)
    w = {p: np.repeat(np.eye(3)[None], n, axis=0) for p in PARTS}
    piv = np.zeros((n, 3))
    pm = base.pivot.mean(axis=0)
    for i in range(n):
        dl = lo_m.T @ base.w["LowerTorso"][i]
        w["LowerTorso"][i] = pel0 @ exp_rot(log_rot(dl) * 0.6)
        du = up_m.T @ up_rel[i]
        w["UpperTorso"][i] = w["LowerTorso"][i] @ rx(np.radians(-4.0)) @ exp_rot(log_rot(du) * 0.8)
        w["Head"][i] = base.w["Head"][i]
        piv[i] = pivot0 + (base.pivot[i] - pm) * np.array([0.5, 0.5, 0.5])
    ank = {"L": np.repeat(ank_l[None], n, axis=0), "R": np.repeat(ank_r[None], n, axis=0)}
    wfoot = {"L": np.repeat(wfl[None], n, axis=0), "R": np.repeat(wfr[None], n, axis=0)}
    knee = {
        "L": piv + np.array([-0.9, 1.2, -1.6]),
        "R": np.repeat((knee_r + np.array([0.1, -0.3, -0.6]))[None], n, axis=0),
    }
    piv, gap = legs_from_targets(w, piv, ank, wfoot, knee, True)
    gaze(w, np.array([0.0, 0.0, -1.0]), 0.9, 0.6)
    err = rifle_arms(w, piv, GRIP, POLES_STAND)
    clip = Clip(name, base.fps, w, piv, True, "crouch", 0.0)
    clip.meta = {
        "fonte": f"pose de joelho (IK) com o balanço de {base.meta.get('fonte', base.name)}",
        "perna_sem_alcance_cm": round(gap * r15.STUD_M * 100, 2),
        "erro_mao_cm": round(max(err.values()) * r15.STUD_M * 100, 2),
    }
    return clip


# ===== deitado =====
POLES_PRONE = {"Right": np.array([2.4, 0.4, -2.2]), "Left": np.array([-2.4, 0.8, -2.2])}


def box_low(frames: dict[str, tuple[np.ndarray, np.ndarray]], parts: tuple[str, ...]) -> float:
    low = np.inf
    for p in parts:
        c, r = frames[p]
        h = np.array(r15.size_of(p)) / 2
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    low = min(low, float((c + r @ (h * [sx, sy, sz]))[1]))
    return low


TRONCO = (
    "LowerTorso",
    "UpperTorso",
    "LeftUpperLeg",
    "RightUpperLeg",
    "LeftLowerLeg",
    "RightLowerLeg",
)


def prone_clip(
    name: str, take: Take, lo: float, hi: float, dmin: float, dmax: float, chest_up: float
) -> tuple[Clip, tuple]:
    """Deitado de bruços parado (laço). O peito sobe nos cotovelos (chest_up, rad), a cabeça olha
    para a frente e o fuzil vai a uma pega de tiro deitado (devolvida: sugestão de HOLD_PRONE)."""
    a, b = pick_still(take, lo, hi, dmin, dmax)
    idx = np.arange(a, b + 1)
    ax = take.pos["chest"][idx] - take.pos["pelvis"][idx]
    yaw = -yaw_of_dir(np.array([ax[:, 0].mean(), 0.0, ax[:, 2].mean()]))
    pts = take_points(take, idx, yaw)
    w = base_w(take, idx, yaw)
    wf = foot_w(take, idx, yaw)
    c = pts["pelvis"].mean(axis=0)
    c[1] = 0.0
    for kk in pts:
        pts[kk] = close_loop_vec(pts[kk] - c)
    for p in ("LowerTorso", "UpperTorso", "Head"):
        w[p] = close_loop_rot(w[p])
    for s in "LR":
        wf[s] = close_loop_rot(wf[s])
    n = len(idx)
    raise_r = rx(chest_up)
    w["UpperTorso"] = np.einsum("ij,fjk->fik", raise_r, w["UpperTorso"])
    piv = pts["pelvis"].copy()
    # pernas: direção quadril -> tornozelo da captura, a partir do quadril do R15
    ank, knee = {}, {}
    for s in "LR":
        hr = np.array([hips(piv[i], w["LowerTorso"][i])[s] for i in range(n)])
        hc = pts[f"hip{s}"]
        ank[s] = hr + (pts[f"ankle{s}"] - hc)
        knee[s] = hr + (pts[f"knee{s}"] - hc) + np.array([0.0, -0.5, 0.0])
    piv, _ = legs_from_targets(w, piv, ank, wf, knee, True)
    # apoia no chão: o ponto mais baixo de tronco e pernas encosta em y = 0
    lows = []
    for i in range(n):
        fr = r15.fk(piv[i], {p: w[p][i] for p in PARTS})
        lows.append(box_low(fr, TRONCO))
    piv[:, 1] -= float(np.mean(lows))
    for s in "LR":
        ank[s][:, 1] -= float(np.mean(lows))
        for i in range(n):
            low = min((wf[s][i] @ q)[1] for q in (SOLE_BALL, SOLE_HEEL, SOLE_TOE))
            ank[s][i][1] = -low + 0.02  # a ponta do pé encosta no chão
        knee[s][:, 1] = 0.0
    piv, gap = legs_from_targets(w, piv, ank, wf, knee, True)
    gaze(w, np.array([0.0, 0.0, -1.0]), 1.0, 0.4)
    # pega de tiro deitado: punho à frente do ombro direito, cano na horizontal para a frente
    up_m = mean_rot(w["UpperTorso"])
    lo_m = mean_rot(w["LowerTorso"])
    piv_m = piv.mean(axis=0)
    ut_m, _ = chest_frame(lo_m, up_m, piv_m)
    sh_r = ut_m + up_m @ SHOULDER["Right"]
    grip = sh_r + np.array([-0.5, 0.0, -0.75])
    grip[1] = 0.95
    rifle_w = ry(np.radians(4.0)) @ rx(np.radians(2.0))
    hold = (up_m.T @ (grip - ut_m), up_m.T @ rifle_w)
    err = rifle_arms(w, piv, hold, POLES_PRONE)
    clip = Clip(name, take.fps, w, piv, True, "prone", 0.0)
    elbows = []
    for i in range(0, n, 4):
        fr = clip.frames(i)
        elbows += [r15.joint_pos(fr, "LeftElbow")[1], r15.joint_pos(fr, "RightElbow")[1]]
    clip.meta = {
        "fonte": f"CMU {take.name}, quadros {a}-{b} a {take.fps:g} qps",
        "perna_sem_alcance_cm": round(gap * r15.STUD_M * 100, 2),
        "erro_mao_cm": round(max(err.values()) * r15.STUD_M * 100, 2),
        "cotovelo_min_cm": round(min(elbows) * r15.STUD_M * 100, 1),
    }
    return clip, hold


def crawl_clip(name: str, base: Clip, hold: tuple, speed_m: float, period: float) -> Clip:
    """Rastejo de bruços (procedural: a CMU não tem rastejo militar). Sobre a pose deitada da
    captura: as pernas empurram alternadas, com o joelho subindo de lado ("de sapo"); no apoio o
    pé fica parado no chão (no espaço do personagem anda para trás a v); a pelve rola para o lado
    que empurra e o peito compensa. O fuzil fica na pega deitada."""
    fps = 60.0
    n = int(round(period * fps))
    v = speed_m / r15.STUD_M
    lo_m = mean_rot(base.w["LowerTorso"])
    up_m = mean_rot(base.w["UpperTorso"])
    hd_m = mean_rot(base.w["Head"])
    piv_m = base.pivot.mean(axis=0)
    f_m = {s: mean_rot(base.w[f"{side}Foot"]) for s, side in (("L", "Left"), ("R", "Right"))}
    stance = 0.6
    push = v * stance * period
    w = {p: np.repeat(np.eye(3)[None], n + 1, axis=0) for p in PARTS}
    piv = np.zeros((n + 1, 3))
    ank = {"L": np.zeros((n + 1, 3)), "R": np.zeros((n + 1, 3))}
    wfoot = {"L": np.zeros((n + 1, 3, 3)), "R": np.zeros((n + 1, 3, 3))}
    knee = {"L": np.zeros((n + 1, 3)), "R": np.zeros((n + 1, 3))}
    hip0 = hips(piv_m, lo_m)
    for i in range(n + 1):
        ph = (i % n) / n
        # pelve: rola para o lado da perna que empurra (esquerda empurra na 1ª metade)
        s2 = np.sin(2 * np.pi * ph)
        roll = np.radians(7.0) * s2
        yawp = np.radians(4.0) * s2
        lo = ry(yawp) @ lo_m @ np.array(axis_angle(np.array([0.0, 1.0, 0.0]), roll))
        w["LowerTorso"][i] = lo
        w["UpperTorso"][i] = (
            ry(-yawp * 0.6) @ up_m @ axis_angle(np.array([0.0, 1.0, 0.0]), -roll * 0.45)
        )
        w["Head"][i] = ry(-yawp * 0.3) @ hd_m
        surge = 0.05 * np.cos(4 * np.pi * ph)
        piv[i] = piv_m + np.array([0.08 * s2, 0.0, surge])
        for s, off in (("L", 0.0), ("R", 0.5)):
            p = (ph + off) % 1.0
            sx = -1.0 if s == "L" else 1.0
            h = hip0[s]
            front = np.array([h[0] + sx * 0.75, 0.0, h[2] + 0.9])
            back = front + np.array([0.0, 0.0, push])
            if p < stance:
                u = p / stance
                pos = front + (back - front) * u
                lift, draw = 0.0, 1.0 - u
            else:
                u = (p - stance) / (1 - stance)
                e = float(smoothstep(u))
                pos = back + (front - back) * e
                pos[0] += sx * 0.25 * np.sin(np.pi * u)
                lift, draw = 0.15 * np.sin(np.pi * u), e
            # pé de lado: rola para fora conforme o joelho sobe
            roll_f = sx * np.radians(70.0) * draw
            wf_i = f_m[s] @ axis_angle(np.array([0.0, 1.0, 0.0]), roll_f)
            low = min((wf_i @ q)[1] for q in (SOLE_BALL, SOLE_HEEL, SOLE_TOE))
            pos[1] = -low + 0.05 + lift
            ank[s][i] = pos
            wfoot[s][i] = wf_i
            knee[s][i] = h + np.array([sx * 2.5, -0.3, 0.6])
    piv, gap = legs_from_targets(w, piv, ank, wfoot, knee, True)
    err = rifle_arms(w, piv, hold, POLES_PRONE)
    clip = Clip(name, fps, w, piv, True, "prone", v)
    # no apoio o pé anda exatamente a +v em Z (parado no chão do mundo) e não anda de lado
    slide = 0.0
    for s, off in (("L", 0.0), ("R", 0.5)):
        for i in range(n):
            p0, p1 = (i / n + off) % 1.0, ((i + 1) / n + off) % 1.0
            if p0 < stance and p1 < stance and p1 > p0:
                d = ank[s][i + 1] - ank[s][i] - np.array([0.0, 0.0, v / fps])
                slide = max(slide, float(np.hypot(d[0], d[2])))
    clip.meta = {
        "escorregamento_max_cm": round(slide * r15.STUD_M * 100, 2),
        "fonte": f"procedural sobre a pose deitada ({base.meta.get('fonte', base.name)})",
        "velocidade_m_s": round(speed_m, 3),
        "passada_ciclo_m": round(speed_m * period, 3),
        "cadencia_passos_s": round(2 / period, 3),
        "perna_sem_alcance_cm": round(gap * r15.STUD_M * 100, 2),
        "erro_mao_cm": round(max(err.values()) * r15.STUD_M * 100, 2),
    }
    return clip


# ===== camadas de cima (só tronco, cabeça e braços) =====
OVERLAY = {p: (1 if p in ("UpperTorso", "Head") or "Arm" in p or "Hand" in p else 0) for p in PARTS}


def _keys(keys: list[tuple[float, np.ndarray]], t: float) -> np.ndarray:
    """Chaves (tempo, valor) com ease in-out (smoothstep) entre elas."""
    ts = [k[0] for k in keys]
    j = int(np.searchsorted(ts, t, side="right")) - 1
    j = min(max(j, 0), len(keys) - 2)
    t0, t1 = ts[j], ts[j + 1]
    u = float(smoothstep((t - t0) / max(t1 - t0, 1e-6)))
    p0, p1 = keys[j][1], keys[j + 1][1]
    return p0 + (p1 - p0) * u


def reload_clip(name: str, base: Clip) -> Clip:
    """Recarregar (procedural: a CMU não tem recarga de fuzil). A mão direita fica no punho; a
    esquerda tira o carregador, vai ao porta-carregador do cinto, encaixa o novo e puxa a alavanca
    de manejo (lado direito da caixa da culatra). A cabeça olha para o encaixe. O tempo é
    reescalado no jogo para a duração da recarga do servidor."""
    fps, dur = 60.0, 2.4
    n = int(dur * fps)
    lo = mean_rot(base.w["LowerTorso"])
    up = mean_rot(base.w["UpperTorso"])
    hd = mean_rot(base.w["Head"])
    piv0 = base.pivot.mean(axis=0)
    # D-94: na recarga o fuzil sobe para a pega de recarga (Shared/ArmIK.HOLDS.reload; o
    # PostureController faz a mesma troca pelo peso deste clipe)
    hp, hr = GRIP_RELOAD
    # tudo no espaço do UpperTorso
    sup = hp + hr @ SUPPORT_OFF
    well = hp + hr @ np.array([0.0, -0.3, -0.32])
    out = well + np.array([0.0, -0.3, -0.05])
    # porta-carregador no cinto, à frente e à esquerda. D-94: era (−0,65; −1,2; −0,7); com a pega
    # nova o braço esquerdo entrava 7,5 cm no tronco (tests/luau/faca). Agora a bolsa fica mais
    # para fora, a mão passa ao lado do corpo ("lado") na ida e na volta, e o cotovelo tem um polo
    # por chave (sobe e abre no trabalho do carregador): 2 cm no pior quadro da simulação.
    pouch = np.array([-1.05, -1.1, -0.9])
    side = np.array([-0.9, -0.4, -1.6])
    below = well + np.array([0.0, -0.28, 0.0])
    # alavanca de manejo: com a pega nova (D-94) a 0,32 a mão esquerda parava 6 cm antes
    op = hp + hr @ np.array([0.2, 0.12, -0.5])
    op_back = hp + hr @ np.array([0.2, 0.12, -0.2])
    st, up_out, wing, back_out = (
        POLES_STAND["Left"],
        np.array([-3.0, 0.0, -1.5]),
        np.array([-3.0, 2.0, 0.0]),
        np.array([-3.2, -1.0, 0.0]),
    )
    # (tempo, alvo da mão, polo do cotovelo)
    keys3 = [
        (0.0, sup, st),
        (0.1, well, up_out),
        (0.18, out, up_out),
        (0.26, side, st),
        (0.36, pouch + [0.05, 0.2, -0.1], st),
        (0.42, pouch, st),
        (0.5, pouch, st),
        (0.58, side, back_out),
        (0.66, below, up_out),
        (0.72, well, up_out),
        (0.77, well, wing),
        (0.85, op, st),
        (0.9, op_back, up_out),
        (1.0, sup, st),
    ]
    keys = [(k[0], k[1]) for k in keys3]
    pole_keys = [(k[0], k[2]) for k in keys3]
    look = [(0.0, 0.0), (0.12, 1.0), (0.82, 1.0), (1.0, 0.0)]
    w = {p: np.repeat(np.eye(3)[None], n + 1, axis=0) for p in PARTS}
    piv = np.repeat(piv0[None], n + 1, axis=0)
    w["LowerTorso"][:] = lo
    w["UpperTorso"][:] = up
    rifle_arms(w, piv, GRIP_RELOAD, POLES_STAND)
    ut, _ = chest_frame(lo, up, piv0)
    rifle = up @ hr
    hw = _hand_rot(rifle, "Left")
    sh = ut + up @ SHOULDER["Left"]
    err = 0.0
    for i in range(n + 1):
        t = i / n
        target = ut + up @ _keys(keys, t)
        # polo: o do jogo no fuzil; indo à bolsa, o cotovelo vai para trás (sem raspar no tronco)
        pole = _keys(pole_keys, t)
        wu, wfo, gap = arm_ik(sh, target, hw, ut + up @ pole, "Left", up @ X)
        w["LeftUpperArm"][i], w["LeftLowerArm"][i], w["LeftHand"][i] = wu, wfo, hw
        err = max(err, gap)
        k = float(_keys([(a, np.array([b])) for a, b in look], t)[0])
        w["Head"][i] = rx(np.radians(-20.0) * k) @ ry(np.radians(8.0) * k) @ hd
    clip = Clip(name, fps, w, piv, False, "stand", 0.0)
    clip.meta = {
        "fonte": "procedural (mão esquerda por IK sobre a pega HOLD_STAND)",
        "erro_mao_cm": round(err * r15.STUD_M * 100, 2),
    }
    return clip


def mirror_take(t: Take) -> Take:
    """Espelha a tomada (esquerda <-> direita): o arremesso da 143 é canhoto."""
    s = np.diag([-1.0, 1.0, 1.0])
    pos = {}
    for k, v in t.pos.items():
        k2 = k[:-1] + {"L": "R", "R": "L"}[k[-1]] if k[-1] in "LR" and k != "pelvis" else k
        pos[k2] = v * [-1.0, 1.0, 1.0]
    rot = {}
    for k, v in t.rot.items():
        k2 = (
            {"l": "r", "r": "l"}[k[0]] + k[1:] if k in ("lfoot", "rfoot", "lfemur", "rfemur") else k
        )
        rot[k2] = np.einsum("ij,fjk,kl->fil", s, v, s)
    return Take(
        t.name + " espelhada",
        t.fps,
        t.n,
        t.k,
        t.dy,
        pos,
        rot,
        {"L": t.foot_flat_pitch["R"], "R": t.foot_flat_pitch["L"]},
    )


def throw_clip(
    name: str, base: Clip, take: Take, lo: float, hi: float, total: float, release: float
) -> Clip:
    """Arremesso de granada por cima (CMU 143_22 espelhada, destro). Só tronco, cabeça e braço
    direito vêm da captura; a mão esquerda fica no fuzil. O tempo é casado com o jogo: a granada
    sai da mão em `release` s (FieldService/WeaponVisuals) num gesto de `total` s."""
    i0, i1 = int(lo * take.fps), int(hi * take.fps)
    wr = take.pos["wristR"][i0:i1]
    sp = np.linalg.norm(np.gradient(wr, axis=0), axis=1) * take.fps
    ir = i0 + int(np.argmax(sp))  # soltura: mão direita mais rápida
    fps = 60.0
    n = int(round(total * fps))
    ts = np.arange(n + 1) / fps
    src = np.where(
        ts <= release,
        i0 + (ir - i0) * ts / release,
        ir + (i1 - ir) * (ts - release) / (total - release),
    )
    idx = np.clip(np.round(src).astype(int), 0, take.n - 1)
    yaw = -heading_of(mean_rot(take.rot["root"][i0:i1]))
    pts = take_points(take, idx, yaw)
    wcap = base_w(take, idx, yaw)
    lo_b = mean_rot(base.w["LowerTorso"])
    piv0 = base.pivot.mean(axis=0)
    w = {p: np.repeat(np.eye(3)[None], n + 1, axis=0) for p in PARTS}
    w["LowerTorso"][:] = lo_b
    # tronco relativo à pelve da captura, posto sobre a pelve do parado; entra e sai suave
    fade = np.minimum(smoothstep(ts / 0.12), smoothstep((total - ts) / 0.15))
    up_b = mean_rot(np.einsum("fji,fjk->fik", base.w["LowerTorso"], base.w["UpperTorso"]))
    hd_b = mean_rot(base.w["Head"])
    for i in range(n + 1):
        rel = wcap["LowerTorso"][i].T @ wcap["UpperTorso"][i]
        w["UpperTorso"][i] = lo_b @ slerp(up_b, rel, float(fade[i]))
        w["Head"][i] = slerp(hd_b, wcap["Head"][i], float(fade[i]) * 0.7)
    piv = np.repeat(piv0[None], n + 1, axis=0)
    rifle_arms(w, piv, GRIP, POLES_STAND)
    # braço direito: direções da captura (ombro -> cotovelo -> pulso) no ombro do R15
    l1, l2 = float(np.linalg.norm(UPPER["Right"])), float(np.linalg.norm(FORE))
    for i in range(n + 1):
        up = w["UpperTorso"][i]
        ut, _ = chest_frame(w["LowerTorso"][i], up, piv[i])
        sh = ut + up @ SHOULDER["Right"]
        d1 = unit(pts["elbowR"][i] - pts["shoulderR"][i])
        d2 = unit(pts["wristR"][i] - pts["elbowR"][i])
        el = sh + d1 * l1
        wrist = el + d2 * l2
        hw = triad(r15.DOWN, np.array([-1.0, 0, 0]), d2, up @ np.array([-1.0, 0, 0]))
        hand = wrist + hw @ HAND_C
        wu, wfo, _ = arm_ik(sh, hand, hw, el + d1 * 0.3, "Right", up @ X)
        f = float(fade[i])
        w["RightUpperArm"][i] = slerp(w["RightUpperArm"][i], wu, f)
        w["RightLowerArm"][i] = slerp(w["RightLowerArm"][i], wfo, f)
        w["RightHand"][i] = slerp(w["RightHand"][i], hw, f)
    clip = Clip(name, fps, w, piv, False, "stand", 0.0)
    clip.meta = {
        "fonte": f"CMU {take.name}, quadros {i0}-{i1} (soltura no {ir}) a "
        f"{take.fps:g} qps, reescalado para {total} s",
        "soltura_s": release,
    }
    return clip


# ===== corpo a corpo (D-94): faca na mão direita e golpe com o fuzil =====
# A faca fica soldada no RightHand com o pivô (punho) em (0, HAND_GRIP_Y, 0), ponta no −Z da mão e
# fio no −Y: o MESMO do Shared/Melee.HAND_GRIP_Y (servidor, MeleeService). Os quadros-chave dão a
# faca no espaço do UpperTorso (pivô, direção da lâmina, direção do fio), a guinada e a arfagem do
# peito e o polo do cotovelo; o braço direito sai por IK, o esquerdo segue no fuzil.
HAND_GRIP_Y = -0.15
POLE_KNIFE = np.array([3.0, -2.4, 1.0])
POLE_CUT = np.array([3.0, 1.0, 0.5])  # golpe de lado: cotovelo para cima e para fora ao armar


def knife_hand(blade: np.ndarray, edge: np.ndarray) -> np.ndarray:
    """Rotação da mão direita (no espaço do peito) com a faca: −Z da mão = lâmina, −Y = fio."""
    b = unit(blade)
    e = unit(edge - (edge @ b) * b)
    return triad(np.array([0.0, 0.0, -1.0]), r15.DOWN, b, e)


def _rifle_grip_knife() -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """A mão direita no punho do fuzil, escrita como pivô/lâmina/fio de uma faca imaginária
    (para o saque partir do fuzil e a guarda voltar a ele)."""
    hp, hr = GRIP
    hw = _hand_rot(hr, "Right")
    return (
        hp + hw @ np.array([0.0, HAND_GRIP_Y, 0.0]),
        hw @ np.array([0.0, 0.0, -1.0]),
        hw @ r15.DOWN,
    )


def _k(t, pos, blade, edge, yaw=0.0, pitch=0.0, pole=POLE_KNIFE):
    return (
        t,
        np.array(pos, float),
        np.array(blade, float),
        np.array(edge, float),
        yaw,
        pitch,
        pole,
    )


_RG = _rifle_grip_knife()
POLE_OUT = np.array([3.2, -1.0, 1.4])  # saque e guarda: o cotovelo por fora, longe da barriga
POLE_ARC = np.array([2.5, 2.5, -2.5])  # fim do golpe de lado: cotovelo alto e à frente
# pose -> (pivô, lâmina, fio, polo). D-94: o caminho direto do punho do fuzil à bainha passava o
# antebraço 7 cm dentro da barriga (tests/luau/faca); a mão sai antes para fora ("fora").
KNIFE_POSES = {
    "fuzil": (_RG[0], _RG[1], _RG[2], POLES_STAND["Right"]),
    "fora": ([1.45, -0.1, -1.45], [0.3, -0.6, -1.0], [0.0, -1.0, 0.0], POLE_OUT),
    "pronta": ([0.85, -0.45, -1.55], [-0.2, 0.3, -1.0], [0.0, -1.0, 0.3], POLE_KNIFE),
    "bainha": ([1.05, -1.3, -0.6], [0.05, -1.0, 0.15], [0.0, 0.0, -1.0], POLE_OUT),
}


def _pose(name: str, t: float, yaw: float = 0.0, pitch: float = 0.0):
    p, b, e, pole = KNIFE_POSES[name]
    return _k(t, p, b, e, yaw, pitch, pole)


# clipe -> (duração, chaves); chave = (tempo, pivô, lâmina, fio, guinada°, arfagem°, polo).
# Tempos do Shared/Melee (DRAW_S 0,28; estocada 0,55; golpe de lado 0,6; SHEATHE_S 0,35)
KNIFE_CLIPS = {
    "faca_saque": (
        0.28,
        [_pose("fuzil", 0.0), _pose("fora", 0.07), _pose("bainha", 0.14), _pose("pronta", 0.28)],
    ),
    "faca_estocada": (
        0.55,
        [
            _pose("pronta", 0.0),
            _k(0.10, [1.1, -0.35, -1.0], [-0.1, 0.45, -1.0], [0.0, -1.0, 0.3], 14, -4),
            _k(0.20, [0.45, 0.05, -1.95], [-0.05, 0.1, -1.0], [0.0, -1.0, 0.1], -12, 12),
            _k(0.30, [0.5, 0.0, -1.85], [-0.05, 0.05, -1.0], [0.0, -1.0, 0.1], -10, 10),
            _pose("pronta", 0.55),
        ],
    ),
    "faca_lado": (
        0.6,
        [
            _pose("pronta", 0.0),
            _k(0.12, [1.55, 0.25, -1.05], [-0.4, 0.3, -1.0], [-1.0, 0.0, 0.0], 22, -2, POLE_CUT),
            _k(0.24, [0.5, -0.1, -1.85], [0.35, 0.0, -1.0], [-1.0, -0.1, -0.35], -8, 6, POLE_ARC),
            _k(0.36, [0.2, -0.2, -1.9], [0.9, 0.0, -0.7], [-0.8, -0.1, -0.5], -14, 8, POLE_ARC),
            _k(0.48, [0.6, -0.25, -1.85], [0.1, 0.1, -1.0], [0.0, -1.0, 0.2], -4, 4),
            _pose("pronta", 0.6),
        ],
    ),
    "faca_guardar": (
        0.35,
        [_pose("pronta", 0.0), _pose("bainha", 0.14), _pose("fora", 0.26), _pose("fuzil", 0.35)],
    ),
}


def _interp(keys: list, t: float, idx: int) -> np.ndarray:
    return _keys([(k[0], np.atleast_1d(np.array(k[idx], float))) for k in keys], t)


def knife_clip(name: str, base: Clip) -> Clip:
    """Faca (procedural; a CMU não tem golpe de faca): peito gira e inclina com o golpe, a cabeça
    segura o olhar, o braço direito leva a faca pelos quadros-chave e o esquerdo fica no fuzil."""
    dur, keys = KNIFE_CLIPS[name]
    fps = 60.0
    n = int(round(dur * fps))
    lo = mean_rot(base.w["LowerTorso"])
    up_rel = mean_rot(np.einsum("fji,fjk->fik", base.w["LowerTorso"], base.w["UpperTorso"]))
    hd = mean_rot(base.w["Head"])
    piv0 = base.pivot.mean(axis=0)
    w = {p: np.repeat(np.eye(3)[None], n + 1, axis=0) for p in PARTS}
    piv = np.repeat(piv0[None], n + 1, axis=0)
    w["LowerTorso"][:] = lo
    for i in range(n + 1):
        t = i / fps
        yaw = float(_interp(keys, t, 4)[0])
        pitch = float(_interp(keys, t, 5)[0])
        w["UpperTorso"][i] = lo @ up_rel @ ry(np.radians(yaw)) @ rx(np.radians(-pitch))
        w["Head"][i] = ry(np.radians(yaw * 0.25)) @ rx(np.radians(-pitch * 0.4)) @ hd
    rifle_arms(w, piv, GRIP, POLES_STAND)
    err = 0.0
    for i in range(n + 1):
        t = i / fps
        up = w["UpperTorso"][i]
        ut, _ = chest_frame(w["LowerTorso"][i], up, piv[i])
        pos = _interp(keys, t, 1)
        hw_ut = knife_hand(_interp(keys, t, 2), _interp(keys, t, 3))
        # polo interpolado entre as chaves (trocar de uma vez virava o cotovelo para dentro)
        pole = _interp(keys, t, 6)
        hw = up @ hw_ut
        hand = ut + up @ (pos - hw_ut @ np.array([0.0, HAND_GRIP_Y, 0.0]))
        sh = ut + up @ SHOULDER["Right"]
        wu, wf, gap = arm_ik(sh, hand, hw, ut + up @ pole, "Right", up @ X)
        w["RightUpperArm"][i], w["RightLowerArm"][i], w["RightHand"][i] = wu, wf, hw
        err = max(err, gap)
    clip = Clip(name, fps, w, piv, False, "stand", 0.0)
    clip.meta = {
        "fonte": "procedural (faca na mão direita por IK; Shared/Melee.HAND_GRIP_Y)",
        "erro_mao_cm": round(err * r15.STUD_M * 100, 2),
    }
    return clip


def rifle_strike_clip(name: str, base: Clip) -> Clip:
    """Estocada de baioneta e coronhada: o peito recua e avança com o passo (a arma anda junto no
    PostureController, pela pega de golpe); as duas mãos seguem no fuzil."""
    fps, dur = 60.0, 0.9
    n = int(round(dur * fps))
    keys = [(0.0, 0.0, 0.0), (0.18, 8.0, -6.0), (0.32, -4.0, 16.0), (0.45, -4.0, 14.0), (0.9, 0, 0)]
    lo = mean_rot(base.w["LowerTorso"])
    up_rel = mean_rot(np.einsum("fji,fjk->fik", base.w["LowerTorso"], base.w["UpperTorso"]))
    hd = mean_rot(base.w["Head"])
    piv0 = base.pivot.mean(axis=0)
    w = {p: np.repeat(np.eye(3)[None], n + 1, axis=0) for p in PARTS}
    piv = np.repeat(piv0[None], n + 1, axis=0)
    w["LowerTorso"][:] = lo
    for i in range(n + 1):
        t = i / fps
        yaw = float(_keys([(a, np.array([b])) for a, b, _ in keys], t)[0])
        pitch = float(_keys([(a, np.array([c])) for a, _, c in keys], t)[0])
        w["UpperTorso"][i] = lo @ up_rel @ ry(np.radians(yaw)) @ rx(np.radians(-pitch))
        w["Head"][i] = ry(np.radians(yaw * 0.3)) @ rx(np.radians(-pitch * 0.5)) @ hd
    err = rifle_arms(w, piv, GRIP, POLES_STAND)
    clip = Clip(name, fps, w, piv, False, "stand", 0.0)
    clip.meta = {
        "fonte": "procedural (peito; a arma anda pela pega de golpe do PostureController)",
        "erro_mao_cm": round(max(err.values()) * r15.STUD_M * 100, 2),
    }
    return clip


# ===== saída =====
def rifle_frames(clip: Clip, grip: tuple) -> list[tuple[np.ndarray, np.ndarray]]:
    hp, hr = grip
    out = []
    for i in range(clip.n):
        up = clip.w["UpperTorso"][i]
        ut, _ = chest_frame(clip.w["LowerTorso"][i], up, clip.pivot[i])
        out.append((ut + up @ hp, up @ hr))
    return out


def _cf(m: np.ndarray, p: np.ndarray) -> list[float]:
    return [round(float(x), 5) for x in (*p, *m.reshape(-1))]


def joint_poses(clip: Clip, i: int, post: Postura) -> dict[str, list[float]]:
    """CFrame (12 números, ordem do CFrame.new) da Pose de cada peça no quadro i."""
    w = {p: clip.w[p][i] for p in PARTS}
    k0 = post.k0(clip.stance)
    rest = np.array([0.0, H0 - post.drop_eff(clip.stance), 0.0])
    t_abs = np.eye(4)
    t_abs[:3, :3] = w["LowerTorso"]
    t_abs[:3, 3] = clip.pivot[i] - rest
    t = np.linalg.inv(k0) @ t_abs
    out = {"LowerTorso": _cf(r15.orthonormalize(t[:3, :3]), t[:3, 3])}
    for p in PARTS[1:]:
        rel = r15.orthonormalize(w[r15.PARENT[p]].T @ w[p])
        out[p] = _cf(rel, np.zeros(3))
    return out


def export(
    clip: Clip,
    post: Postura,
    grip: tuple | None,
    priority: str,
    weights: dict | None = None,
    extra: dict | None = None,
) -> Path:
    """Grava o JSON do clipe (para o kfs.luau e a prévia). weights: peso por peça (0 = a Pose
    fica só como elo da hierarquia e a junta segue as animações de prioridade menor)."""
    SAIDA.mkdir(parents=True, exist_ok=True)
    out = resample(clip, FPS_SAIDA)
    rifles = rifle_frames(out, grip) if grip is not None else [None] * out.n
    quadros = []
    heads = []
    for i in range(out.n):
        fr = out.frames(i)
        heads.append(fr["Head"][0][1])
        q = {
            "t": round(i / out.fps, 5),
            "poses": joint_poses(out, i, post),
            "previa": {p: [c.round(4).tolist(), r.round(5).tolist()] for p, (c, r) in fr.items()},
        }
        if rifles[i] is not None:
            q["fuzil"] = [rifles[i][0].round(4).tolist(), rifles[i][1].round(5).tolist()]
        quadros.append(q)
    dur = (out.n - 1) / out.fps
    d = {
        "nome": clip.name,
        "laco": clip.loop,
        "prioridade": priority,
        "postura": clip.stance,
        "authoredHipHeight": round(post.hip(clip.stance), 4),
        "duracao": round(dur, 4),
        "velocidade_studs": round(clip.speed, 4),
        "velocidade_m_s": round(clip.speed * r15.STUD_M, 4),
        "centro_cabeca_m": round(float(np.mean(heads)) * r15.STUD_M, 3),
        "pesos": weights or {p: 1 for p in PARTS},
        "postura_servidor": {
            "drop": post.drop,
            "min_hip": post.min_hip,
            "prone_root": [post.prone_y, round(float(np.degrees(post.prone_pitch)), 3)],
            "base_hip": BASE_HIP,
            "h0": H0,
        },
        **clip.meta,
        **(extra or {}),
        "quadros": quadros,
    }
    path = SAIDA / f"{clip.name}.json"
    path.write_text(json.dumps(d, ensure_ascii=False, separators=(",", ":")), "utf-8")
    return path


# ===== clipes =====
@dataclass
class Saida:
    clip: Clip
    grip: tuple | None
    priority: str
    weights: dict | None = None
    extra: dict | None = None


_cache: dict[str, Saida] = {}

# Quadros por segundo REAIS das tomadas. A página da CMU diz 120 para os sujeitos 141 e 143, mas
# no voo da corrida a pelve cai a ~−44 m/s² com 120 (−11 com 60): são 60. O 77 é 60 na página.
FPS = {"77": 60.0, "141": 60.0, "143": 60.0}


def take(name: str) -> Take:
    return load_take(name, FPS.get(name.split("_")[0], 120.0))


def build(nome: str, post: Postura) -> Saida:
    if nome in _cache:
        return _cache[nome]
    if nome == "parado":
        # 77_02 "standing": parado de verdade, com o peso trocando de perna. A "ready stance"
        # (77_03) é agachada e olha em volta demais para um soldado parado.
        clip, _ = still_clip("parado", take("77_02"), 1.0, 15.5, 3.0, 4.5, extra_drop=0.06)
        s = Saida(clip, GRIP, "Movement")
    elif nome == "andar":
        s = Saida(gait_clip("andar", take("35_01"), 2, "stand"), GRIP, "Movement")
    elif nome == "trote":
        s = Saida(gait_clip("trote", take("35_17"), 1, "stand"), GRIP, "Movement")
    elif nome == "correr":
        # 127_06: corrida que acelera até ~4,8 m/s; o último ciclo é o mais rápido. Passada
        # quase inteira (k**0,25): na corrida o passo largo é o que vende a força. O tronco
        # inclinado da arrancada volta 20° (o fuzil no peito apontaria para o chão).
        clip = gait_clip(
            "correr",
            take("127_06"),
            1,
            "stand",
            lo=0.5,
            chest_keep=0.6,
            stride_k=0.25,
            lean=np.radians(-20.0),
        )
        s = Saida(clip, GRIP, "Movement")
    elif nome == "agachado":
        s = Saida(kneel_clip("agachado", build("parado", post).clip), GRIP, "Movement")
    elif nome == "agachado_andar":
        # D-94: quadril mais baixo (0,35 -> 0,57 stud) para a cabeça andar na altura da do agachado
        # parado (de joelho): a câmera desce DROP.crouch e fica na cabeça nos dois clipes
        clip = gait_clip(
            "agachado_andar",
            take("136_09"),
            2,
            "crouch",
            lo=2.4,
            extra_drop=0.57,
            lean=np.radians(-18.0),
        )
        s = Saida(clip, GRIP, "Movement")
    elif nome == "deitado":
        clip, hold = prone_clip("deitado", take("77_16"), 0.0, 2.8, 2.0, 2.6, np.radians(14.0))
        p, r = hold
        ang = np.degrees(_euler_xyz(r))
        extra = {
            "hold_prone_sugerido": {
                "posicao": [round(float(x), 3) for x in p],
                "angulos_xyz_graus": [round(float(x), 2) for x in ang],
                "nota": "pega do fuzil no UpperTorso desta pose (CFrame.new(pos) * "
                "CFrame.fromEulerAnglesXYZ(rad(ângulos))) para o PostureController.HOLD_PRONE",
            }
        }
        s = Saida(clip, hold, "Movement", extra=extra)
    elif nome == "rastejar":
        base = build("deitado", post)
        s = Saida(crawl_clip("rastejar", base.clip, base.grip, 0.35, 1.6), base.grip, "Movement")
    elif nome == "recarregar":
        s = Saida(
            reload_clip("recarregar", build("parado", post).clip),
            GRIP_RELOAD,
            "Action",
            weights=OVERLAY,
        )
    elif nome == "granada":
        t = mirror_take(take("143_22"))
        clip = throw_clip("granada", build("parado", post).clip, t, 5.6, 7.3, 0.8, 0.4)
        s = Saida(clip, GRIP, "Action", weights=OVERLAY)
    elif nome in KNIFE_CLIPS:
        s = Saida(knife_clip(nome, build("parado", post).clip), GRIP, "Action", weights=OVERLAY)
    elif nome == "baioneta":
        clip = rifle_strike_clip(nome, build("parado", post).clip)
        s = Saida(clip, GRIP, "Action", weights=OVERLAY)
    else:
        raise SystemExit(f"clipe desconhecido: {nome}")
    _cache[nome] = s
    return s


def _euler_xyz(r: np.ndarray) -> np.ndarray:
    """Ângulos (rad) de CFrame.fromEulerAnglesXYZ: R = Rx(a) Ry(b) Rz(c)."""
    b = np.arcsin(np.clip(r[0, 2], -1.0, 1.0))
    a = np.arctan2(-r[1, 2], r[2, 2])
    c = np.arctan2(-r[0, 1], r[0, 0])
    return np.array([a, b, c])


CLIPES = [
    "parado",
    "andar",
    "trote",
    "correr",
    "agachado",
    "agachado_andar",
    "deitado",
    "rastejar",
    "recarregar",
    "granada",
    "faca_saque",
    "faca_estocada",
    "faca_lado",
    "faca_guardar",
    "baioneta",
]


def main(nomes: list[str]) -> None:
    import previa

    post = ler_postura()
    for nome in nomes or CLIPES:
        s = build(nome, post)
        path = export(s.clip, post, s.grip, s.priority, s.weights, s.extra)
        png = previa.from_json(path)
        print(nome, json.dumps(s.clip.meta, ensure_ascii=False), "->", path.name, png.name)


if __name__ == "__main__":
    main(sys.argv[1:])
