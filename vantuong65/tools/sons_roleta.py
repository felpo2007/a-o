"""Sons da roleta das caixas (D-177): síntese em numpy -> OGG (FFmpeg do Blender), como os veículos.

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/sons_roleta.py

Sons curtos e leves (44,1 kHz, mono), de material de campanha, não de cassino:
- roleta_tique.ogg: o estalo de uma lingueta de metal passando num dente (30 ms). A roleta toca um
  por cartão que passa no marcador, mais baixo quando vai rápido.
- roleta_parada.ogg: a trava da caixa de munição fechando: baque de madeira com o clique do metal
  (300 ms).
- roleta_revela.ogg: um sino pequeno e seco (comum, incomum) (700 ms).
- roleta_raro.ogg: sino de latão com mais corpo (raro) (1,4 s).
- roleta_lendario.ogg: dois sinos em quinta, com brilho (épico, lendário) (2,2 s).
Saídas em assets/roleta_sons/. As durações são inteiras em ms (o mixdown do Blender sai exato).
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
SAIDA = RAIZ / "assets" / "roleta_sons"
TRAB = Path(tempfile.gettempdir()) / "vt65_sons_roleta"
rng = np.random.default_rng(1965819)


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
    t = t_de(30)
    ruido = passa_faixa(rng.normal(0, 1, len(t)), 1800, 7000) * np.exp(-t * 260)
    ressoa = np.sin(2 * math.pi * 2650 * t) * np.exp(-t * 180) * 0.6
    return borda(normaliza(ruido + ressoa, 0.5), 0.3, 3)


def parada() -> np.ndarray:
    t = t_de(300)
    madeira = (
        np.sin(2 * math.pi * 165 * t) * np.exp(-t * 28)
        + 0.55 * np.sin(2 * math.pi * 410 * t) * np.exp(-t * 40)
        + 0.25 * np.sin(2 * math.pi * 930 * t) * np.exp(-t * 60)
    )
    golpe = passa_faixa(rng.normal(0, 1, len(t)), 300, 4000) * np.exp(-t * 90) * 0.8
    clique = np.zeros_like(t)
    i = int(0.012 * SR)
    resto = t[: len(t) - i]
    clique[i:] = np.sin(2 * math.pi * 3100 * resto) * np.exp(-resto * 240) * 0.5
    return borda(normaliza(madeira + golpe + clique, 0.75), 0.5, 20)


def sino(f0: float, ms: int, decai: float, brilho: float) -> np.ndarray:
    """Sino de metal: parciais inarmônicas de sino pequeno, cada uma com o seu decaimento."""
    t = t_de(ms)
    parciais = (
        (1.0, 1.0),
        (2.0, 0.55),
        (2.76, 0.42 * brilho),
        (5.40, 0.22 * brilho),
        (8.93, 0.1 * brilho),
    )
    x = np.zeros_like(t)
    for k, a in parciais:
        x += a * np.sin(2 * math.pi * f0 * k * t) * np.exp(-t * decai * (1 + 0.6 * k))
    ataque = passa_faixa(rng.normal(0, 1, len(t)), 2000, 9000) * np.exp(-t * 400) * 0.15
    return x + ataque


def revela() -> np.ndarray:
    return borda(normaliza(sino(880, 700, 5.5, 0.6), 0.55), 0.5, 40)


def raro() -> np.ndarray:
    return borda(normaliza(sino(660, 1400, 2.6, 1.0), 0.65), 0.5, 80)


def lendario() -> np.ndarray:
    a = sino(523.25, 2200, 1.7, 1.2)
    b = sino(783.99, 2200, 1.9, 1.0)
    atraso = int(0.09 * SR)
    b = np.concatenate([np.zeros(atraso), b[: len(b) - atraso]])
    return borda(normaliza(a + 0.8 * b, 0.75), 0.5, 120)


SONS = {
    "roleta_tique": tique,
    "roleta_parada": parada,
    "roleta_revela": revela,
    "roleta_raro": raro,
    "roleta_lendario": lendario,
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
