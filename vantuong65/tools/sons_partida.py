"""Sons do começo da partida (D-203): síntese em numpy -> OGG (FFmpeg do Blender), como a roleta.

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/sons_partida.py

Sons curtos e leves (44,1 kHz, mono), de campo, sem música:
- contagem_tique.ogg: um toque seco de madeira e metal, um por segundo nos 5 últimos da contagem
  (90 ms).
- partida_apito.ogg: o apito de bola de oficial, dois toques curtos e um longo, quando a partida
  começa (1,5 s). A bola de cortiça dentro do apito bate a ~28 Hz: a altura e o volume tremem nesse
  ritmo (o trinado do apito de campo).
Saídas em assets/partida_sons/. As durações são inteiras em ms (o mixdown do Blender sai exato).
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
SAIDA = RAIZ / "assets" / "partida_sons"
TRAB = Path(tempfile.gettempdir()) / "vt65_sons_partida"
rng = np.random.default_rng(1965818)


def t_de(ms: int) -> np.ndarray:
    return np.arange(SR * ms // 1000) / SR


def passa_faixa(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec = np.fft.rfft(x)
    spec[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(spec, len(x))


def normaliza(x: np.ndarray, pico: float) -> np.ndarray:
    m = float(np.abs(x).max())
    return x * (pico / m) if m > 0 else x


def borda(x: np.ndarray, ms_in: float = 1.0, ms_out: float = 4.0) -> np.ndarray:
    """Rampa curta no começo e no fim: sem estalo de corte."""
    n_in, n_out = int(SR * ms_in / 1000), int(SR * ms_out / 1000)
    y = x.copy()
    y[:n_in] *= np.linspace(0, 1, n_in)
    y[-n_out:] *= np.linspace(1, 0, n_out)
    return y


def tique() -> np.ndarray:
    t = t_de(90)
    madeira = np.sin(2 * math.pi * 820 * t) * np.exp(-t * 70) + 0.45 * np.sin(
        2 * math.pi * 1930 * t
    ) * np.exp(-t * 110)
    golpe = passa_faixa(rng.normal(0, 1, len(t)), 900, 6000) * np.exp(-t * 320) * 0.7
    return borda(normaliza(madeira + golpe, 0.6), 0.3, 10)


def toque(ms: int, f0: float) -> np.ndarray:
    """Um sopro do apito: tom de ~3 kHz com o trinado da bola, harmônico fraco e ar."""
    t = t_de(ms)
    trin = 27.5 + 2.0 * np.sin(2 * math.pi * 1.3 * t)  # a bola não bate num ritmo fixo
    fase_trin = 2 * math.pi * np.cumsum(trin) / SR
    f = f0 + 140 * np.sin(fase_trin)
    fase = 2 * math.pi * np.cumsum(f) / SR
    am = 1 - 0.32 * (0.5 + 0.5 * np.sin(fase_trin + 0.6))
    tom = (np.sin(fase) + 0.12 * np.sin(2 * fase) + 0.04 * np.sin(3 * fase)) * am
    ar = passa_faixa(rng.normal(0, 1, len(t)), 2200, 7500) * 0.09
    sopro = np.minimum(1, t / 0.018) * np.minimum(1, (t[-1] - t) / 0.035)  # ataque e soltura
    return (tom + ar) * sopro


def apito() -> np.ndarray:
    pausa = lambda ms: np.zeros(SR * ms // 1000)  # noqa: E731
    x = np.concatenate(
        [
            toque(170, 3050),
            pausa(80),
            toque(170, 3050),
            pausa(110),
            toque(780, 3000),
            pausa(190),
        ]
    )
    return borda(normaliza(x, 0.6), 0.5, 20)


SONS = {
    "contagem_tique": tique,
    "partida_apito": apito,
}


def main() -> None:
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
