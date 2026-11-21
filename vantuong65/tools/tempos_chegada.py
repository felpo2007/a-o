"""Tempo de chegada a pé de cada QG a cada objetivo (D-201), com a velocidade do jogo.

Caminho mais rápido na grade do terreno (células de 4,48 m, 8 vizinhos), com as regras do
Shared/Movement: trote de 4,70 m/s (D-188; o VC x 1,12), fator de rampa na direção do passo
(subir 20% -> 78%), chão de mata 0,93, estrada 1,0, tabuleiro 0,62 e riacho/rio com 0,6 m d'água
(0,85 x 0,68). Casas, muros e árvores não entram (o tempo real fica um pouco maior). Fora da área
jogável não passa.

Uso (a partir de vantuong65/):
  uv run python tools/tempos_chegada.py              o mapa da pasta de trabalho
  uv run python tools/tempos_chegada.py --git a633fc5  o mapa de um commit (ex.: a v118)
"""

from __future__ import annotations

import argparse
import heapq
import json
import math
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import crop_world as cw  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
REL = "src/ServerStorage/VT65Build/Data"

# Shared/Movement (D-188): trote = F44.walk (14 studs/s) x 0,28 x 1,2; corrida = 21 studs/s
TROTE_MS = 14 * 0.28 * 1.2
CORRIDA_MS = 21 * 0.28 * 1.2
LADO = {"US": 1.0, "VC": 1.12}
CHAO = {"mata": 0.93, "estrada": 1.0, "tabuleiro": 0.62, "agua": 0.85 * (1 - 0.6 * 0.45 / 0.85)}


def rampa_fator(grade: float) -> float:
    """Movement.slopeFactor"""
    if grade >= 0:
        return max(1 - 1.1 * grade, 0.4)
    return max(1 - 0.5 * max(-grade - 0.2, 0), 0.7)


def leitor(commit: str | None):
    if commit is None:
        return lambda rel: (ROOT / rel).read_text("utf-8")

    def ler(rel: str) -> str:
        r = subprocess.run(
            ["git", "-C", str(ROOT), "show", f"{commit}:./{rel}"], capture_output=True, check=True
        )
        return r.stdout.decode("utf-8")

    return ler


def carrega(commit: str | None) -> dict:
    ler = leitor(commit)
    g = cw.read_grid(lambda nome: ler(f"{REL}/{nome}.luau"))
    feats = ler(f"{REL}/Features.luau")
    body = re.search(r"\bwaters = \{([^}]*)\}", feats).group(1)
    waters = np.array([float(v) for v in body.split(",") if v.strip()], float).reshape(-1, 6)
    roads = []
    for body in re.findall(r"pts = \{([^}]*)\}", ler(f"{REL}/Roads.luau")):
        v = [float(x) for x in body.split(",") if x.strip()]
        roads.append(np.array(v).reshape(-1, 3)[:, :2])
    mc = ler("src/ReplicatedStorage/Shared/MapConfig.luau")
    pts = {
        m.group(1): (float(m.group(2)), float(m.group(3)))
        for m in re.finditer(r'name = "([^"]+)",\s*x = (-?[\d.]+),\s*z = (-?[\d.]+)', mc)
    }
    hq = {
        m.group(1): (float(m.group(2)), float(m.group(3)))
        for m in re.finditer(r"(US|VC) = \{ x = (-?[\d.]+), z = (-?[\d.]+)", mc)
    }
    return {"g": g, "waters": waters, "roads": roads, "pontos": pts, "qg": hq}


def chao(m: dict) -> np.ndarray:
    g = m["g"]
    shape = g["heights"].shape
    rows, cols = np.indices(shape)
    xs = g["ox"] + (cols + 0.5) * g["cell"]
    zs = g["oz"] + (rows + 0.5) * g["cell"]
    f = np.full(shape, CHAO["mata"])
    for x, z, _y, su, sv, a in m["waters"]:
        ca, sa = math.cos(a), math.sin(a)
        dx, dz = xs - x, zs - z
        dentro = (np.abs(dx * ca - dz * sa) <= su / 2) & (np.abs(dx * sa + dz * ca) <= sv / 2)
        f[dentro] = CHAO["tabuleiro"]
    for pts in m["roads"]:
        for (x1, z1), (x2, z2) in zip(pts, pts[1:], strict=False):
            n = max(2, int(math.hypot(x2 - x1, z2 - z1) / g["cell"] * 2) + 2)
            for t in np.linspace(0, 1, n):
                r = int((z1 + (z2 - z1) * t - g["oz"]) / g["cell"])
                c = int((x1 + (x2 - x1) * t - g["ox"]) / g["cell"])
                if 0 <= r < shape[0] and 0 <= c < shape[1]:
                    f[r, c] = CHAO["estrada"]
    f[g["cls"] == 5] = CHAO["agua"]
    xa, xb, za, zb = cw.crop_box(0.0)
    f[(xs < xa) | (xs > xb) | (zs < za) | (zs > zb)] = 0.0
    return f


def tempos(m: dict, fator: np.ndarray, origem: tuple[float, float], v: float) -> np.ndarray:
    """segundos até cada célula (Dijkstra, 8 vizinhos, rampa pela direção do passo)"""
    g = m["g"]
    h = (g["heights"].astype(float) - g["hoff"]) / 100.0
    cm = g["cell"] * cw.STUD_M
    H, W = h.shape
    r0 = int((origem[1] - g["oz"]) / g["cell"])
    c0 = int((origem[0] - g["ox"]) / g["cell"])
    t = np.full((H, W), np.inf)
    t[r0, c0] = 0.0
    fila = [(0.0, r0, c0)]
    viz = [(dr, dc, cm * math.hypot(dr, dc)) for dr in (-1, 0, 1) for dc in (-1, 0, 1) if dr or dc]
    while fila:
        tt, r, c = heapq.heappop(fila)
        if tt > t[r, c]:
            continue
        for dr, dc, d in viz:
            rr, cc = r + dr, c + dc
            if not (0 <= rr < H and 0 <= cc < W):
                continue
            k = min(fator[r, c], fator[rr, cc])
            if k <= 0:
                continue
            vel = v * k * rampa_fator((h[rr, cc] - h[r, c]) / d)
            nt = tt + d / vel
            if nt < t[rr, cc]:
                t[rr, cc] = nt
                heapq.heappush(fila, (nt, rr, cc))
    return t


def mede(commit: str | None) -> dict:
    m = carrega(commit)
    g = m["g"]
    fator = chao(m)
    out = {}
    for lado, (hx, hz) in m["qg"].items():
        tt = tempos(m, fator, (hx, hz), TROTE_MS * LADO[lado])
        linha = {}
        for nome, (x, z) in m["pontos"].items():
            r = int((z - g["oz"]) / g["cell"])
            c = int((x - g["ox"]) / g["cell"])
            reta = math.hypot(x - hx, z - hz) * cw.STUD_M
            linha[nome] = {"reta_m": round(reta), "trote_s": round(float(tt[r, c]))}
        out[lado] = linha
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--git", default=None, help="commit do mapa (sem: a pasta de trabalho)")
    a = ap.parse_args()
    print(json.dumps(mede(a.git), ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
