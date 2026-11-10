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
SIGHT_BACK_U = 0.15  # olho: a alça traseira fica ~15% do comprimento à frente da mão direita
SIGHT_U = {"rpg2": 0.31}  # RPG-2: o olho fica no próprio poste de mira
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
    p = load_points(MODELS / f"{key}_studs.glb")
    fwd = FORWARD[key]
    ax = 0 if fwd[1] == "X" else 2
    lat = 2 - ax  # eixo lateral (o outro horizontal)
    lo, hi = p[:, ax].min(), p[:, ax].max()
    length = hi - lo
    sign = 1 if fwd[0] == "+" else -1
    muzzle_end = hi if sign > 0 else lo
    u = (muzzle_end - p[:, ax]) * sign / length  # 0 na boca, 1 na coronha

    def along(uu: float) -> float:
        return float(muzzle_end - sign * uu * length)

    def at(uu: float, y: float, lateral: float) -> list[float]:
        v = [0.0, y, 0.0]
        v[ax] = along(uu)
        v[lat] = lateral
        return [round(c, 3) for c in v]

    # linha do cano: vértices da boca (1,5% do comprimento); o plano lateral do cano vale para
    # todos os pontos (a caixa nem sempre é simétrica: bipé aberto, argola de fiel na pistola)
    q = p[u < 0.015]
    bore_y, bore_lat = float(np.median(q[:, 1])), float(np.median(q[:, lat]))
    muzzle = at(0.0, bore_y, bore_lat)
    w0, w1 = SIGHT_WINDOW.get(key, SIGHT_WINDOW_DEFAULT)
    sight_y = float(p[(u >= w0) & (u <= w1), 1].max())
    gu = GRIP_U[key]
    pistol = SUPPORT_U[key] == gu
    sight_u = SIGHT_U.get(key, gu if pistol else gu - SIGHT_BACK_U)
    sight = at(sight_u, sight_y, bore_lat)
    grip = at(gu, bore_y - GRIP_DROP_M.get(key, GRIP_DROP_DEFAULT) / M, bore_lat)
    support_drop = SUPPORT_DROP_M.get(key, SUPPORT_DROP_DEFAULT)
    support = grip if pistol else at(SUPPORT_U[key], bore_y - support_drop / M, bore_lat)
    # caixa no referencial da arma (punho na origem, boca em −Z): só o X mínimo é usado (arma
    # caída de lado no chão)
    rel = p - np.array(grip)
    wx = rel[:, 0] if ax == 2 else rel[:, 2]
    if fwd == "+Z":
        wx = -wx  # 180° em Y
    elif fwd == "-X":
        wx = -rel[:, 2]  # −90° em Y: x' = −z
    elif fwd == "+X":
        wx = rel[:, 2]
    # comprimento real (m) para conferir a escala do ForgeGUI
    return {
        "forward": fwd,
        "muzzle": muzzle,
        "sight": sight,
        "grip": grip,
        "support": support,
        "lowX": round(float(wx.min()), 3),
        "lengthM": round(float(length * M), 3),
    }


def vec(v: list[float]) -> str:
    return f"Vector3.new({v[0]}, {v[1]}, {v[2]})"


def main() -> None:
    lines = [
        "--!strict",
        "-- GERADO por tools/weapon_landmarks.py a partir dos GLB das armas. Não editar à mão.",
        "-- Pontos no espaço da MeshPart publicada (studs, centro da caixa na origem).",
        "-- forward = eixo que aponta para a boca. lowX = menor X da malha com o punho na",
        "-- origem e a boca em −Z (arma caída de lado). lengthM = comprimento da malha (m).",
        "export type Art = {",
        "\tforward: string,",
        "\tmuzzle: Vector3,",
        "\tsight: Vector3,",
        "\tgrip: Vector3,",
        "\tsupport: Vector3,",
        "\tlowX: number,",
        "\tlengthM: number,",
        "}",
        "local WeaponArt: { [string]: Art } = {",
    ]
    for key in FORWARD:
        d = landmarks(key)
        print(key, d)
        lines += [
            f"\t{key} = {{",
            f'\t\tforward = "{d["forward"]}",',
            f"\t\tmuzzle = {vec(d['muzzle'])},",
            f"\t\tsight = {vec(d['sight'])},",
            f"\t\tgrip = {vec(d['grip'])},",
            f"\t\tsupport = {vec(d['support'])},",
            f"\t\tlowX = {d['lowX']},",
            f"\t\tlengthM = {d['lengthM']},",
            "\t},",
        ]
    lines += ["}", "", "return WeaponArt", ""]
    OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print("escrito", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
