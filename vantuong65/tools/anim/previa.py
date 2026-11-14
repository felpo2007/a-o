"""Folha de prévia de um clipe do soldado: o R15 em caixas, de lado e de frente, com o fuzil.

As marcas no chão andam para trás na velocidade natural do clipe: pé apoiado parado em relação a
elas = sem escorregar. Usada pelo retarget.py (opção --previa) e para conferir o JSON gravado:
  uv run python -I tools/anim/previa.py assets/mocap/soldado/trote.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

AQUI = Path(__file__).resolve().parent
if str(AQUI) not in sys.path:
    sys.path.insert(0, str(AQUI))

import r15  # noqa: E402

COR = {"Left": (200, 50, 50), "Right": (50, 70, 200)}
CINZA = (70, 70, 70)
BOX = [
    (0, 1),
    (1, 3),
    (3, 2),
    (2, 0),
    (4, 5),
    (5, 7),
    (7, 6),
    (6, 4),
    (0, 4),
    (1, 5),
    (2, 6),
    (3, 7),
]


def corners(c: np.ndarray, r: np.ndarray, s: tuple[float, float, float]) -> np.ndarray:
    h = np.array(s) / 2
    pts = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) * h
    return c + pts @ r.T


def draw_pose(
    dr: ImageDraw.ImageDraw,
    frames: dict[str, tuple[np.ndarray, np.ndarray]],
    ox: float,
    oy: float,
    scale: float,
    view: str,
    rifle: tuple[np.ndarray, np.ndarray] | None,
) -> None:
    def proj(p: np.ndarray) -> tuple[float, float]:
        if view == "cima":  # de cima: frente (−Z) para cima, direita do soldado à direita
            return ox + p[0] * scale, oy + p[2] * scale
        x = -p[2] if view == "lado" else -p[0]
        return ox + x * scale, oy - p[1] * scale

    for part in r15.PARTS:
        c, r = frames[part]
        cor = next((v for k, v in COR.items() if part.startswith(k)), CINZA)
        q = corners(c, r, r15.size_of(part))
        for i, j in BOX:
            dr.line([proj(q[i]), proj(q[j])], fill=cor, width=1)
    if rifle is not None:
        p, r = rifle
        a = p + r @ np.array([0.0, 0.0, 1.3])
        b = p + r @ np.array([0.0, 0.0, -2.7])
        dr.line([proj(a), proj(b)], fill=(30, 120, 30), width=3)


def sheet(
    poses: list[dict[str, tuple[np.ndarray, np.ndarray]]],
    rifles: list[tuple[np.ndarray, np.ndarray] | None],
    times: list[float],
    speed: float,
    title: str,
    out: Path,
    cols: int = 8,
    deitado: bool = False,
) -> Path:
    """Deitado: vista de lado e de cima, quadros mais largos."""
    n = len(poses)
    if deitado:
        cols = max(cols // 2, 1)
    rows = (n + cols - 1) // cols
    cw, ch, sc = (340, 260, 30.0) if deitado else (170, 260, 34.0)
    views = ("lado", "cima") if deitado else ("lado", "frente")
    img = Image.new("RGB", (cols * cw, rows * ch * 2 + 20), (248, 248, 246))
    dr = ImageDraw.Draw(img)
    dr.text((6, 4), title, fill=(0, 0, 0))
    for k, (fr, rf, t) in enumerate(zip(poses, rifles, times, strict=True)):
        cx = (k % cols) * cw
        for v, view in enumerate(views):
            cy = 20 + (k // cols) * ch * 2 + v * ch
            gy = cy + ch - 16
            if view == "cima":
                draw_pose(dr, fr, cx + cw / 2, cy + ch / 2, sc, view, rf)
                continue
            dr.line([(cx + 4, gy), (cx + cw - 4, gy)], fill=(160, 160, 160))
            if view == "lado" and speed > 0:
                off = (speed * t) % 2.0
                for z in np.arange(-6.0, 6.0, 2.0):
                    x = cx + cw / 2 + (-(z + off)) * sc
                    if cx < x < cx + cw:
                        dr.line([(x, gy), (x, gy + 6)], fill=(90, 90, 90), width=2)
            draw_pose(dr, fr, cx + cw / 2, gy, sc, view, rf)
        dr.text((cx + 4, 22 + (k // cols) * ch * 2), f"{t:.2f}s", fill=(0, 0, 0))
    img.save(out)
    return out


def from_json(path: Path, count: int = 16) -> Path:
    d = json.loads(path.read_text("utf-8"))
    q = d["quadros"]
    idx = np.linspace(0, len(q) - 1, min(count, len(q))).astype(int)
    poses, rifles, times = [], [], []
    for i in idx:
        poses.append({p: (np.array(v[0]), np.array(v[1])) for p, v in q[i]["previa"].items()})
        rf = q[i].get("fuzil")
        rifles.append((np.array(rf[0]), np.array(rf[1])) if rf else None)
        times.append(q[i]["t"])
    out = path.with_suffix(".png")
    title = f"{d['nome']} ({d['postura']}, {d['duracao']:.2f} s, {d.get('velocidade_m_s', 0)} m/s)"
    return sheet(
        poses,
        rifles,
        times,
        d.get("velocidade_studs", 0.0),
        title,
        out,
        deitado=d["postura"] == "prone",
    )


if __name__ == "__main__":
    for a in sys.argv[1:]:
        print(from_json(Path(a)))
