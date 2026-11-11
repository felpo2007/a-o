"""Pontos de cada arma publicada (boca do cano, linha de visada, mão direita, mão esquerda).

Lê os GLB das armas (assets/forgegui/models/<chave>_studs.glb) e gera
src/ReplicatedStorage/Shared/WeaponArt.luau, usado por Shared/GunModel.fit.

Por que existe: o modelo publicado chega centrado na caixa e sem pontos de mão nem de boca. Sem
isto a arma real ficava atravessada na mão e sem clarão, traçante, mira ou IK (teste com a arte
publicada no Studio, 2026-11-10).

Conferido no Studio em 2026-11-10:
- o importador do Roblox gira o GLB 180° em Y: no MeshPart, x e z trocam de sinal (a coronha do
  RPG-2 e o punho das pistolas estão do lado oposto ao do GLB; o tamanho é o mesmo);
- o lado da boca de cada arma (FORWARD) foi visto em captura de tela, com uma marca em −Z.

GRIP_U e SUPPORT_U são frações do comprimento contadas a partir da boca, medidas nas mesmas
capturas (mão direita no punho ou no delgado da coronha; esquerda no guarda-mão, no máximo a
~0,25 m da direita, que é o alcance do braço do avatar).

Uso (a partir de vantuong65/): uv run python tools/weapon_landmarks.py
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "assets/forgegui/models"
OUT = ROOT / "src/ReplicatedStorage/Shared/WeaponArt.luau"
M = 0.28  # metros por stud

# eixo da MeshPart (já no Roblox) que aponta para a boca do cano
FORWARD = {
    "m14": "+Z",
    "type56": "+Z",
    "sks": "+Z",
    "m60": "-Z",
    "rpd": "+Z",
    "m79": "+Z",
    "m1911": "-Z",
    "type54": "-Z",
    "rpg2": "-X",
}
GRIP_U = {
    "m14": 0.74,
    "type56": 0.67,
    "sks": 0.74,
    "m60": 0.69,
    "rpd": 0.70,
    "m79": 0.58,
    "m1911": 0.78,
    "type54": 0.78,
    "rpg2": 0.40,
}
SUPPORT_U = {
    "m14": 0.52,
    "type56": 0.45,
    "sks": 0.52,
    "m60": 0.47,
    "rpd": 0.46,
    "m79": 0.36,
    "m1911": 0.78,  # pistola: as duas mãos no punho
    "type54": 0.78,
    "rpg2": 0.55,  # RPG-2: a esquerda apoia o tubo no protetor de madeira, atrás do punho
}
# janela (frações a partir da boca) onde está o topo da alça de mira dianteira; a linha de visada
# passa por ali. M79: só a boca (a alça de escada levantada fica logo atrás e é mais alta).
# RPD: a massa de mira fica a ~7% da boca. RPG-2: a alça é o poste de mira sobre o tubo.
SIGHT_WINDOW = {"m79": (0.0, 0.04), "rpd": (0.0, 0.12), "rpg2": (0.25, 0.36)}
SIGHT_WINDOW_DEFAULT = (0.0, 0.08)
# o topo da massa é o ponto mais alto a até 2 mm do plano do cano: na M14 as orelhas que protegem a
# massa ficam 40 mm acima do cano e a massa só 15 mm; com o topo geral, a massa aparecia ~2° abaixo
# do centro da tela, e o tiro (que sai do centro) iria alto (Studio, 2026-11-10)
SIGHT_POST_BAND_M = 0.002
# olho (m atrás do ponto Sight). Fuzis, metralhadoras e M79: o ponto Sight fica 9 cm à frente da
# mão direita, então o olho fica sobre o punho (rosto na coronha). Com o olho 7 cm mais à frente,
# a caixa da culatra tomava a metade de baixo da tela. Pistolas: braço estendido.
EYE_M = {"m1911": 0.45, "type54": 0.45}
EYE_DEFAULT_M = 0.09
SIGHT_U = {"rpg2": 0.39}  # RPG-2: o ponto Sight fica 9 cm atrás do poste de mira (sobre o punho)
# Linha de visada: do ponto Sight (perto do olho) ao topo da massa (SightFront); a arma em primeira
# pessoa gira um pouco para essa linha cair no centro da tela, que é para onde o tiro vai. Sem
# deslocamento, a linha é paralela ao cano. Nas malhas geradas a alça traseira não é zerada com a
# massa e às vezes tapa a vista: o ponto Sight é deslocado (m, no referencial da arma: direita,
# acima, para trás), escolhido olhando a captura da mira no Studio (2026-11-10).
EYE_OFFSET_M: dict[str, tuple[float, float, float]] = {
    "m14": (0.0, 0.008, 0.0),  # massa no centro da janela da alça de dioptro
    "m60": (0.030, 0.032, 0.10),  # por cima da tampa da caixa; a alça de transporte fica à esquerda
    "m1911": (0.0, 0.002, 0.0),  # a massa aparece por cima da alça traseira
    "type54": (0.0, 0.002, 0.0),
}
# M79: a escada de mira levantada fica na frente da massa e a tapa; a referência é o meio da janela
# aberta da escada (fração a partir da boca, altura acima do cano em m), conferido na captura
FRONT_OVERRIDE = {"m79": (0.075, 0.105)}
# Modelos gerados tortos em guinada (eixo principal dos vértices, PCA no plano XZ): a Type 54 veio
# ~27° girada e a RPD ~7° (na RPD o cano por fatias dá o mesmo). Corrige acima de 0,5°.
YAW_MIN_DEG = 0.5


def ry(a: float) -> np.ndarray:
    """Giro em Y na convenção do Roblox (CFrame.Angles(0, a, 0))."""
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


TURN_Y = {"-Z": 0.0, "+Z": np.pi, "-X": -np.pi / 2, "+X": np.pi / 2}  # igual ao GunModel.TURN


def yaw_fix(p: np.ndarray, fwd: str) -> float:
    """Ângulo (rad) que leva o eixo principal dos vértices ao eixo nomeado em FORWARD."""
    xz = p[:, [0, 2]] - p[:, [0, 2]].mean(0)
    w, v = np.linalg.eigh(xz.T @ xz)
    vx, vz = v[:, np.argmax(w)]
    phi = np.degrees(np.arctan2(vx, vz))  # a partir de +Z rumo a +X
    target = 0.0 if fwd[1] == "Z" else 90.0
    a = (target - phi + 90) % 180 - 90  # menor giro (o sinal do eixo vem de FORWARD)
    return float(np.radians(a)) if abs(a) >= YAW_MIN_DEG else 0.0


# centro da mão abaixo da linha do cano (m). Estatística de vértices não serve aqui: bandoleira,
# bipé e tambor puxam a média, e o meio de um tubo reto nem tem vértice (RPG-2). A arma provisória
# tinha o punho 2,5 cm abaixo do cano; aqui a mão desce até o punho de pistola ou o delgado.
GRIP_DROP_M = {"m1911": 0.06, "type54": 0.06, "rpg2": 0.09}
GRIP_DROP_DEFAULT = 0.05
SUPPORT_DROP_M = {"rpg2": 0.05}
SUPPORT_DROP_DEFAULT = 0.04


def load_points(path: Path) -> np.ndarray:
    data = path.read_bytes()
    off = 12
    js: dict | None = None
    binb = b""
    while off < len(data):
        ln, typ = struct.unpack_from("<II", data, off)
        chunk = data[off + 8 : off + 8 + ln]
        if typ == 0x4E4F534A:
            js = json.loads(chunk)
        else:
            binb = chunk
        off += 8 + ln
    assert js is not None
    pts: list[np.ndarray] = []

    def walk(idx: int, parent: np.ndarray) -> None:
        n = js["nodes"][idx]
        m = np.eye(4)
        if "matrix" in n:
            m = np.array(n["matrix"]).reshape(4, 4).T
        else:
            x, y, z, w = n.get("rotation", [0, 0, 0, 1])
            r = np.array(
                [
                    [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                    [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                    [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
                ]
            )
            m[:3, :3] = r * np.array(n.get("scale", [1, 1, 1]))
            m[:3, 3] = n.get("translation", [0, 0, 0])
        world = parent @ m
        if "mesh" in n:
            for prim in js["meshes"][n["mesh"]]["primitives"]:
                acc = js["accessors"][prim["attributes"]["POSITION"]]
                bv = js["bufferViews"][acc["bufferView"]]
                if bv.get("byteStride", 12) != 12:
                    raise SystemExit(f"{path.name}: byteStride inesperado")
                start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
                cnt = acc["count"]
                arr = np.frombuffer(binb, np.float32, cnt * 3, start).reshape(cnt, 3)
                pts.append((np.c_[arr, np.ones(cnt)] @ world.T)[:, :3])
        for c in n.get("children", []):
            walk(c, world)

    for r in js["scenes"][js.get("scene", 0)]["nodes"]:
        walk(r, np.eye(4))
    p = np.vstack(pts)
    p[:, 0] *= -1  # importador do Roblox: 180° em Y
    p[:, 2] *= -1
    return p - (p.min(0) + p.max(0)) / 2  # a MeshPart fica centrada na caixa


def landmarks(key: str) -> dict:
    fwd = FORWARD[key]
    mesh = load_points(MODELS / f"{key}_studs.glb")
    yaw = yaw_fix(mesh, fwd)
    rot = ry(yaw)  # malha → "alinhada" (eixo longo exato); os pontos voltam à malha no fim
    p = mesh @ rot.T
    ax = 0 if fwd[1] == "X" else 2
    lat = 2 - ax  # eixo lateral (o outro horizontal)
    lo, hi = p[:, ax].min(), p[:, ax].max()
    length = hi - lo
    sign = 1 if fwd[0] == "+" else -1
    muzzle_end = hi if sign > 0 else lo
    u = (muzzle_end - p[:, ax]) * sign / length  # 0 na boca, 1 na coronha

    def along(uu: float) -> float:
        return float(muzzle_end - sign * uu * length)

    def at(uu: float, y: float, lateral: float) -> np.ndarray:
        v = np.zeros(3)
        v[1] = y
        v[ax] = along(uu)
        v[lat] = lateral
        return v

    turn = ry(TURN_Y[fwd])  # alinhada → referencial da arma (boca em −Z)

    def out(v: np.ndarray) -> list[float]:  # alinhada → espaço da malha
        return [round(float(c), 3) for c in rot.T @ v]

    # linha do cano: vértices da boca (1,5% do comprimento); o plano lateral do cano vale para
    # todos os pontos (a caixa nem sempre é simétrica: bipé aberto, argola de fiel na pistola)
    q = p[u < 0.015]
    bore_y, bore_lat = float(np.median(q[:, 1])), float(np.median(q[:, lat]))
    muzzle = at(0.0, bore_y, bore_lat)
    w0, w1 = SIGHT_WINDOW.get(key, SIGHT_WINDOW_DEFAULT)
    in_win = (u >= w0) & (u <= w1)
    post = in_win & (np.abs(p[:, lat] - bore_lat) < SIGHT_POST_BAND_M / M)
    cand = post if post.any() else in_win
    i_tip = int(np.argmax(np.where(cand, p[:, 1], -np.inf)))
    if key in FRONT_OVERRIDE:
        fu, fh = FRONT_OVERRIDE[key]
        front = at(fu, bore_y + fh / M, bore_lat)
    else:
        front = at(float(u[i_tip]), float(p[i_tip, 1]), bore_lat)  # topo da massa de mira
    gu = GRIP_U[key]
    pistol = SUPPORT_U[key] == gu
    eye_m = EYE_M.get(key, EYE_DEFAULT_M)
    sight_u = SIGHT_U.get(key, gu if pistol else gu - EYE_DEFAULT_M / (length * M))
    off = np.array(EYE_OFFSET_M.get(key, (0.0, 0.0, 0.0))) / M  # referencial da arma
    sight = at(sight_u, float(front[1]), bore_lat) + turn.T @ off
    sight_out, front_out = out(sight), out(front)
    # D-67: alça e massa medidas na malha (tools/sight_align.py): o anel ou o entalhe e a ponta da
    # massa caem no centro da tela. Entalhe: olho sobre o punho (rosto na coronha). Anel: olho a
    # EYE_ANEL_M (com 6,5 cm o anel de 5,5 mm da M14 ficava pequeno e a base da alça tomava o meio
    # da tela; Studio, 2026-11-11).
    # sightKind/sightMm (D-69): a arma em 1ª pessoa desenha alça e massa em geometria limpa por
    # cima da malha (a textura da alça, de poucos texels, aparecia pixelada)
    sight_kind, sight_mm = "", 0.0
    if key in MEDIDAS:
        med = MEDIDAS[key]
        sight_out, front_out = med["sight"], med["front"]
        if "furo_mm" in med:
            eye_m = EYE_ANEL_M
            sight_kind, sight_mm = "anel", float(med["furo_mm"])
        else:
            eye_m = round(float(max(0.06, (gu - med["rear_u"]) * length * M)), 3)
            sight_kind, sight_mm = "entalhe", float(med["entalhe_mm"])
    grip = at(gu, bore_y - GRIP_DROP_M.get(key, GRIP_DROP_DEFAULT) / M, bore_lat)
    support_drop = SUPPORT_DROP_M.get(key, SUPPORT_DROP_DEFAULT)
    support = grip if pistol else at(SUPPORT_U[key], bore_y - support_drop / M, bore_lat)
    # caixa no referencial da arma (punho na origem, boca em −Z): só o X mínimo é usado (arma
    # caída de lado no chão)
    wx = ((p - grip) @ turn.T)[:, 0]
    return {
        "forward": fwd,
        "yaw": round(yaw, 4),
        "muzzle": out(muzzle),
        "sight": sight_out,
        "front": front_out,
        "grip": out(grip),
        "support": out(support),
        "lowX": round(float(wx.min()), 3),
        "lengthM": round(float(length * M), 3),  # para conferir a escala do ForgeGUI
        "eyeM": eye_m,
        "sightKind": sight_kind,
        "sightMm": round(sight_mm, 2),
    }


def vec(v: list[float]) -> str:
    return f"Vector3.new({v[0]}, {v[1]}, {v[2]})"


MEDIDAS: dict[str, dict] = {}
EYE_ANEL_M = 0.045


def main() -> None:
    import sys

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from sight_align import CFG, medir  # importa este módulo: só aqui, para não virar ciclo

    for k, cfg in CFG.items():
        try:
            MEDIDAS[k] = medir(k, cfg)
        except SystemExit as e:  # alça não achada: fica a linha de visada da D-60
            print("sem medida:", e)
    lines = [
        "--!strict",
        "-- GERADO por tools/weapon_landmarks.py a partir dos GLB das armas. Não editar à mão.",
        "-- Pontos no espaço da MeshPart publicada (studs, centro da caixa na origem).",
        "-- forward = eixo que aponta para a boca. lowX = menor X da malha com o punho na",
        "-- origem e a boca em −Z (arma caída de lado). lengthM = comprimento da malha (m).",
        "-- eyeM = distância (m) do olho ao ponto sight, mirando. yaw = giro extra em Y (rad) de",
        "-- modelo gerado torto; o referencial da arma é TURN[forward] * CFrame.Angles(0, yaw, 0).",
        '-- sightKind = "anel" ou "entalhe" medido na malha (tools/sight_align.py; "" = sem',
        "-- medida) e sightMm = diâmetro do furo ou fundura do entalhe (mm).",
        "export type Art = {",
        "\tforward: string,",
        "\tyaw: number,",
        "\tmuzzle: Vector3,",
        "\tsight: Vector3,",
        "\tfront: Vector3,",
        "\tgrip: Vector3,",
        "\tsupport: Vector3,",
        "\tlowX: number,",
        "\tlengthM: number,",
        "\teyeM: number,",
        "\tsightKind: string,",
        "\tsightMm: number,",
        "}",
        "local WeaponArt: { [string]: Art } = {",
    ]
    for key in FORWARD:
        d = landmarks(key)
        print(key, d)
        lines += [
            f"\t{key} = {{",
            f'\t\tforward = "{d["forward"]}",',
            f"\t\tyaw = {d['yaw']},",
            f"\t\tmuzzle = {vec(d['muzzle'])},",
            f"\t\tsight = {vec(d['sight'])},",
            f"\t\tfront = {vec(d['front'])},",
            f"\t\tgrip = {vec(d['grip'])},",
            f"\t\tsupport = {vec(d['support'])},",
            f"\t\tlowX = {d['lowX']},",
            f"\t\tlengthM = {d['lengthM']},",
            f"\t\teyeM = {d['eyeM']},",
            f'\t\tsightKind = "{d["sightKind"]}",',
            f"\t\tsightMm = {d['sightMm']},",
            "\t},",
        ]
    lines += ["}", "", "return WeaponArt", ""]
    OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print("escrito", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
