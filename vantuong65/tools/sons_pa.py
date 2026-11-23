"""Som da pá de trincheira (D-183): síntese em numpy -> OGG (FFmpeg do Blender), como a roleta.

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/sons_pa.py

- pa_cavar.ogg (1,4 s, mono, 44,1 kHz): uma pazada inteira, no tempo do laço da animação
  (Shared/ItemAnim, shovel: de 0,6 a 2,0 s). O servidor toca em laço no buraco enquanto cava.
  - 0,35 s: a lâmina crava na terra (baque grave, terra esfarelando e o aço raspando);
  - 0,65 s: a alavanca solta o torrão (estalos de terra rasgando);
  - 1,0 s: o sopro da pá jogando a terra e, logo depois, a terra caindo (chuva de grãos e torrões).
  O fim é silencioso, para o laço emendar sem estalo.
Saída em assets/pa_sons/.
"""

from __future__ import annotations

import math
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sons_veiculos as base  # noqa: E402

SR = base.SR
RAIZ = base.RAIZ
SAIDA = RAIZ / "assets" / "pa_sons"
TRAB = Path(tempfile.gettempdir()) / "vt65_sons_pa"
rng = np.random.default_rng(1943)
DUR_MS = 1400


def passa_faixa(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec = np.fft.rfft(x)
    spec[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(spec, len(x))


def depois(t: np.ndarray, t0: float) -> np.ndarray:
    return np.maximum(t - t0, 0.0) * (t >= t0)


def graos(t: np.ndarray, t0: float, dur: float, n: int, lo: float, hi: float) -> np.ndarray:
    """Chuva de grãos: estalos curtos espalhados (mais no começo), cada um filtrado."""
    x = np.zeros_like(t)
    for _ in range(n):
        ti = t0 + dur * rng.random() ** 1.8
        i = int(ti * SR)
        if i >= len(t) - 400:
            continue
        k = int(SR * rng.uniform(0.003, 0.012))
        env = np.exp(-np.arange(k) / (k / 4))
        x[i : i + k] += rng.normal(0, 1, k) * env * rng.uniform(0.2, 1.0)
    return passa_faixa(x, lo, hi)


def pa_cavar() -> np.ndarray:
    t = np.arange(SR * DUR_MS // 1000) / SR
    # 1) crava: baque grave que cai de tom, terra esfarelando e o aço raspando
    u = depois(t, 0.35)
    tom = 2 * math.pi * (70 + 60 * np.exp(-u * 30)) * u
    baque = np.sin(tom) * np.exp(-u * 22) * (t >= 0.35)
    esfarela = graos(t, 0.35, 0.16, 70, 400, 4200) * 0.9
    raspa = passa_faixa(rng.normal(0, 1, len(t)), 1500, 5200) * np.exp(-u * 35) * (t >= 0.35)
    aco = (np.sin(2 * math.pi * 1870 * u) + 0.5 * np.sin(2 * math.pi * 2960 * u)) * np.exp(-u * 60)
    crava = baque * 1.0 + esfarela + raspa * 0.25 + aco * (t >= 0.35) * 0.06
    # 2) alavanca: terra rasgando (estalos graves) e um rangido curto do cabo
    rasga = graos(t, 0.62, 0.2, 55, 150, 1800) * 0.8
    v = depois(t, 0.64)
    range_ = np.sin(2 * math.pi * (240 + 90 * v) * v) * np.exp(-((v - 0.06) ** 2) / 0.0012)
    alavanca = rasga + range_ * (t >= 0.64) * 0.08
    # 3) joga: sopro da lâmina no ar e a terra caindo espalhada
    w = depois(t, 0.98)
    sopro = passa_faixa(rng.normal(0, 1, len(t)), 300, 2500) * np.exp(-((w - 0.06) ** 2) / 0.002)
    cai = graos(t, 1.10, 0.24, 140, 250, 3600) * 0.85
    baque2 = np.sin(2 * math.pi * 95 * depois(t, 1.1)) * np.exp(-depois(t, 1.1) * 30) * (t >= 1.1)
    joga = sopro * (t >= 0.98) * 0.3 + cai + baque2 * 0.35
    x = crava + alavanca + joga
    x = x / float(np.abs(x).max()) * 0.85
    # fim silencioso para o laço emendar
    n_out = int(SR * 0.08)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    x[: int(SR * 0.002)] *= np.linspace(0, 1, int(SR * 0.002))
    return x


SONS = {"pa_cavar": pa_cavar}


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    TRAB.mkdir(parents=True, exist_ok=True)
    for nome, f in SONS.items():
        x = f()
        wav = TRAB / f"{nome}.wav"
        ogg = SAIDA / f"{nome}.ogg"
        base.gravar_wav(wav, x)
        try:
            base.para_ogg(wav, ogg, len(x))
            print("[SOM]", nome, base.conferir(ogg, x), flush=True)
        except Exception as e:  # sem bpy/FFmpeg: fica o WAV
            print("[SOM]", nome, "OGG falhou:", e, "- WAV em", wav, flush=True)


if __name__ == "__main__":
    main()
