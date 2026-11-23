"""Detecta as linhas da quadrícula UTM impressa na carta (render 300 dpi) e ajusta
pixel -> (E, N) da grade impressa. Compara com a afim do LGIDict do GeoPDF.

Uso: uv run python tools/detect_grid.py <png_300dpi>
"""

from __future__ import annotations

import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from georef_carta import fit_affine  # noqa: E402

Image.MAX_IMAGE_PIXELS = None


def dark_mask(path: str) -> np.ndarray:
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    # preto da quadrícula: os três canais escuros e próximos entre si
    return (a.max(axis=2) < 110) & ((a.max(axis=2) - a.min(axis=2)) < 45)


def refine(profile: np.ndarray, guess: float, win: int = 70) -> float | None:
    lo, hi = int(guess - win), int(guess + win)
    if lo < 0 or hi >= len(profile):
        return None
    seg = profile[lo:hi]
    k = int(np.argmax(seg))
    if seg[k] < 0.6:  # linha contínua deve escurecer >= 60% da faixa
        return None
    # centróide ao redor do pico
    s = slice(max(0, k - 3), k + 4)
    idx = np.arange(lo, hi)[s]
    w = seg[s]
    return float((idx * w).sum() / w.sum())


def main() -> None:
    m = dark_mask(sys.argv[1])
    tr, _ = fit_affine(300)
    inv = ~tr
    pts = []  # (px, py, E, N)
    band = 120
    # interior da folha principal (evita margem e encarte)
    for E in range(260000, 285001, 1000):
        for N in range(1688000, 1714001, 1000):
            gx, gy = inv * (E, N)
            # linha vertical E: perfil por colunas numa faixa de linhas centrada em gy+150
            y0 = int(gy + 150)
            if y0 - band // 2 < 0 or y0 + band // 2 >= m.shape[0]:
                continue
            pv = m[y0 - band // 2 : y0 + band // 2].mean(axis=0)
            x0 = int(gx + 150)
            if x0 - band // 2 < 0 or x0 + band // 2 >= m.shape[1]:
                continue
            ph = m[:, x0 - band // 2 : x0 + band // 2].mean(axis=1)
            # a linha é levemente inclinada; ajusta pelo deslocamento de 150 px
            vx = refine(pv, gx + 150 * tr.b / tr.a * 0 + (inv * (E, N - 150 * 4.24))[0] - gx)
            hy = refine(ph, gy + (inv * (E + 150 * 4.23, N))[1] - gy)
            if vx is None or hy is None:
                continue
            pts.append((vx, y0, hy, x0, E, N))
    pts = np.array(pts)
    print(f"interseções detectadas: {len(pts)}")
    # cada detecção dá um ponto da linha vertical (vx, y0) com E conhecido e um ponto da
    # horizontal (x0, hy) com N conhecido. Ajuste: E = a*x + b*y + c ; N = d*x + e*y + f
    Av = np.column_stack([pts[:, 0], pts[:, 1], np.ones(len(pts))])
    Ah = np.column_stack([pts[:, 3], pts[:, 2], np.ones(len(pts))])
    ce, *_ = np.linalg.lstsq(Av, pts[:, 4], rcond=None)
    cn, *_ = np.linalg.lstsq(Ah, pts[:, 5], rcond=None)
    re = Av @ ce - pts[:, 4]
    rn = Ah @ cn - pts[:, 5]
    print(f"grade impressa: E = {ce[0]:.5f} x + {ce[1]:.5f} y + {ce[2]:.2f}")
    print(f"                N = {cn[0]:.5f} x + {cn[1]:.5f} y + {cn[2]:.2f}")
    print(f"resíduo E: rms {np.sqrt((re**2).mean()):.2f} m, máx {abs(re).max():.2f} m")
    print(f"resíduo N: rms {np.sqrt((rn**2).mean()):.2f} m, máx {abs(rn).max():.2f} m")
    # diferença entre grade impressa e afim do LGIDict em pontos da área de batalha
    for x, y in [(inv * (268600, 1691700)), (inv * (271800, 1692000)), (inv * (262000, 1710000))]:
        E1, N1 = tr * (x, y)
        E2 = ce[0] * x + ce[1] * y + ce[2]
        N2 = cn[0] * x + cn[1] * y + cn[2]
        print(
            f"px ({x:.0f},{y:.0f}): LGIDict ({E1:.0f},{N1:.0f})"
            f" vs grade impressa ({E2:.0f},{N2:.0f})"
            f" -> dE {E2 - E1:+.1f} dN {N2 - N1:+.1f}"
        )
    np.save(sys.argv[1].rsplit(".", 1)[0] + "_grid_coef.npy", np.vstack([ce, cn]))


if __name__ == "__main__":
    main()
