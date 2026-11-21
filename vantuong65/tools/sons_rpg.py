"""Sons do lançador RPG-2 (D-200): síntese em numpy -> OGG (FFmpeg do Blender), como a pá.

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/sons_rpg.py

- rpg2_disparo.ogg (1,8 s): a carga de pólvora do PG-2 (sem motor de foguete): o estampido curto e
  largo, o baque grave do tubo aberto, o sopro da pólvora para trás e a cauda.
- rpg2_voo.ogg (1,0 s, laço): a granada passando, o vento nas aletas que vibram (um zumbido
  modulado) e o assobio fraco. Emenda sem estalo.
- rpg2_recarga.ogg (2,4 s): a granada sai da bolsa de lona, raspa na boca do tubo, desliza e trava.
Saída em assets/rpg_sons/. Os tempos da recarga casam com a animação (WeaponVisuals: a mão na bolsa
de 26% a 36% e a granada entrando de 54% a 66% dos 6 s).
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
SAIDA = RAIZ / "assets" / "rpg_sons"
TRAB = Path(tempfile.gettempdir()) / "vt65_sons_rpg"
rng = np.random.default_rng(1965)


def passa_faixa(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec = np.fft.rfft(x)
    spec[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(spec, len(x))


def depois(t: np.ndarray, t0: float) -> np.ndarray:
    return np.maximum(t - t0, 0.0) * (t >= t0)


def rpg2_disparo() -> np.ndarray:
    t = np.arange(int(SR * 1.8)) / SR
    u = depois(t, 0.02)
    on = (t >= 0.02).astype(float)
    # estampido: ruído largo muito curto
    estampido = rng.normal(0, 1, len(t)) * np.exp(-u * 90) * on
    # baque grave do tubo aberto (cai de tom)
    tom = 2 * math.pi * (55 + 70 * np.exp(-u * 18)) * u
    baque = np.sin(tom) * np.exp(-u * 7) * on
    # sopro da pólvora: ruído médio que dura mais
    sopro = passa_faixa(rng.normal(0, 1, len(t)), 250, 3200) * np.exp(-u * 5.5) * on
    # cauda (eco no mato): ruído grave filtrado e lento
    cauda = (
        passa_faixa(rng.normal(0, 1, len(t)), 60, 600)
        * np.exp(-depois(t, 0.12) * 2.6)
        * (t >= 0.12)
    )
    x = estampido * 1.0 + baque * 1.4 + sopro * 0.55 + cauda * 0.35
    x = x / float(np.abs(x).max()) * 0.9
    n_out = int(SR * 0.15)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    x[: int(SR * 0.001)] *= np.linspace(0, 1, int(SR * 0.001))
    return x


def rpg2_voo() -> np.ndarray:
    n = SR  # 1,0 s exato: laço
    k = int(SR * 0.05)
    t = np.arange(n + k) / SR
    vento = passa_faixa(rng.normal(0, 1, n + k), 300, 2400)
    # aletas vibrando: modulação de 30 Hz e assobio em frequências inteiras (periódicos em 1 s)
    mod = 0.6 + 0.4 * np.sin(2 * math.pi * 30 * t)
    assobio = np.sin(2 * math.pi * 1180 * t) * 0.12 + np.sin(2 * math.pi * 1770 * t) * 0.05
    x = vento * mod + assobio
    # laço: o começo cruza com o que viria depois do fim (x[n:n+k]); y[n-1] -> y[0] = x[n-1] -> x[n]
    y = x[:n].copy()
    r = np.linspace(0, 1, k)
    y[:k] = x[:k] * r + x[n : n + k] * (1 - r)
    return y / float(np.abs(y).max()) * 0.7


def rpg2_recarga() -> np.ndarray:
    t = np.arange(int(SR * 2.4)) / SR
    # 1) a mão na bolsa de lona (0,0–0,5 s): esfrega de pano
    pano = passa_faixa(rng.normal(0, 1, len(t)), 800, 6000)
    pano *= np.exp(-((t - 0.25) ** 2) / 0.02) * 0.35
    # 2) a granada raspa na boca do tubo (1,25 s) e desliza (1,25–1,6 s)
    u = depois(t, 1.25)
    raspa = passa_faixa(rng.normal(0, 1, len(t)), 1800, 7000) * np.exp(-u * 9) * (t >= 1.25) * 0.4
    aco = (np.sin(2 * math.pi * 2350 * u) + 0.6 * np.sin(2 * math.pi * 3710 * u)) * np.exp(-u * 40)
    desliza = (
        passa_faixa(rng.normal(0, 1, len(t)), 500, 2500) * np.exp(-((t - 1.45) ** 2) / 0.008) * 0.3
    )
    # 3) trava (1,6 s): clique metálico seco e o baque da granada assentando
    v = depois(t, 1.6)
    clique = rng.normal(0, 1, len(t)) * np.exp(-v * 260) * (t >= 1.6)
    trava = np.sin(2 * math.pi * 160 * v) * np.exp(-v * 35) * (t >= 1.6)
    x = pano + raspa + aco * (t >= 1.25) * 0.15 + desliza + clique * 0.9 + trava * 0.6
    x = x / float(np.abs(x).max()) * 0.85
    n_out = int(SR * 0.08)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


SONS = {"rpg2_disparo": rpg2_disparo, "rpg2_voo": rpg2_voo, "rpg2_recarga": rpg2_recarga}


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
