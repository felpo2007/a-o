"""Sons das facas (VẠN TƯỜNG '65): síntese procedural em numpy -> WAV -> MP3 (FFmpeg do Blender).

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/faca/sons.py

Saídas (44,1 kHz, mono, pico -3 dBFS):
- assets/facas/sons/faca_saque.mp3: botão de pressão abrindo, a lâmina correndo no couro da
  bainha (atrito com trancos de "gruda-solta") e o tilintar curto quando a ponta sai da boca;
- faca_corte.mp3: silvo no ar (ruído com filtro passa-faixa que sobe e desce);
- faca_impacto.mp3: baque abafado em pano/corpo (grave com queda de tom + sopro de pano);
- baioneta_encaixe.mp3: clique metálico duplo (trava e encaixe) com modos de ressonância.
Os WAV ficam em assets/facas/_trabalho/sons/. O MP3 sai do `bpy.ops.sound.mixdown` (faixa de
som no sequenciador, cena a 1000 quadros/s) e é conferido relendo o arquivo com o `aud`.
O codificador MP3 põe ~25 ms de silêncio no começo (atraso do codificador).
"""

from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np

SR = 44100
PICO_DB = -3.0
RAIZ = Path(__file__).resolve().parents[2]
SAIDA = RAIZ / "assets" / "facas" / "sons"
TRAB = RAIZ / "assets" / "facas" / "_trabalho" / "sons"
rng = np.random.default_rng(1965)


# ------------------------------------------------------------------ blocos
def tempo(dur: float) -> np.ndarray:
    return np.arange(int(round(dur * SR))) / SR


def ruido(n: int) -> np.ndarray:
    return rng.standard_normal(n)


def filtro(
    x: np.ndarray, passa_alta: float | None = None, passa_baixa: float | None = None, ordem: int = 2
) -> np.ndarray:
    """Filtro de Butterworth de magnitude aplicado na FFT (fase zero)."""
    X = np.fft.rfft(x)
    f = np.maximum(np.fft.rfftfreq(len(x), 1 / SR), 1e-3)
    H = np.ones_like(f)
    if passa_alta:
        H /= np.sqrt(1 + (passa_alta / f) ** (2 * ordem))
    if passa_baixa:
        H /= np.sqrt(1 + (f / passa_baixa) ** (2 * ordem))
    return np.fft.irfft(X * H, len(x))


def faixa_variavel(x: np.ndarray, fc, q: float) -> np.ndarray:
    """Passa-faixa de estado variável (Chamberlin) com frequência central variando no tempo."""
    fc = np.broadcast_to(np.asarray(fc, float), x.shape)
    f = 2 * np.sin(np.pi * np.minimum(fc, SR / 6) / SR)
    amort = 1.0 / q
    baixo = faixa = 0.0
    out = np.empty_like(x)
    for i in range(len(x)):
        alto = x[i] - baixo - amort * faixa
        faixa += f[i] * alto
        baixo += f[i] * faixa
        out[i] = faixa
    return out


def envelope(t: np.ndarray, t0: float, ataque: float, decai: float) -> np.ndarray:
    u = t - t0
    e = np.where(u < 0, 0.0, np.where(u < ataque, u / max(ataque, 1e-6), 1.0))
    return e * np.exp(-np.maximum(u - ataque, 0.0) / decai)


def modos(t: np.ndarray, t0: float, freqs, taus, amps) -> np.ndarray:
    """Ressonâncias amortecidas (metal) começando em t0."""
    u = np.maximum(t - t0, 0.0)
    on = (t >= t0).astype(float)
    out = np.zeros_like(t)
    for f, tau, a in zip(freqs, taus, amps, strict=True):
        fase = rng.uniform(0, 2 * math.pi)
        out += a * np.exp(-u / tau) * np.sin(2 * math.pi * f * u + fase)
    return out * on


def clique(t: np.ndarray, t0: float, dur: float, passa_alta: float, amp: float) -> np.ndarray:
    x = filtro(ruido(len(t)), passa_alta=passa_alta)
    return amp * x * envelope(t, t0, 0.0003, dur)


def finalizar(x: np.ndarray, fade_ms: float = 6.0) -> np.ndarray:
    x = x - x.mean()
    n = int(fade_ms / 1000 * SR)
    x[-n:] *= np.linspace(1, 0, n) ** 2
    x[: int(0.0015 * SR)] *= np.linspace(0, 1, int(0.0015 * SR))
    return x / np.abs(x).max() * 10 ** (PICO_DB / 20)


# ------------------------------------------------------------------ sons
def faca_saque() -> np.ndarray:
    t = tempo(0.38)
    n = len(t)
    # botão de pressão abrindo
    x = clique(t, 0.004, 0.004, 2500, 0.5)
    x += modos(t, 0.004, (1900, 3400, 5600), (0.008, 0.006, 0.004), (0.25, 0.18, 0.1))
    # lâmina correndo no couro: ruído na faixa que sobe, com "gruda-solta"
    corre = (t > 0.035) & (t < 0.30)
    u = np.clip((t - 0.035) / (0.30 - 0.035), 0, 1)
    janela = np.sin(np.pi * u) ** 0.7 * (0.55 + 0.45 * u) * corre
    grao = np.abs(filtro(ruido(n), passa_baixa=90.0))
    grao = 0.45 + 1.1 * grao / grao.max()
    fc = 900 + 1900 * u**1.3
    atrito = faixa_variavel(ruido(n), fc, 0.9)
    atrito = filtro(atrito, passa_alta=350, passa_baixa=6500)
    x += 0.9 * atrito / np.abs(atrito).max() * janela * grao
    # rangido do couro: trancos curtos e esparsos
    trancos = np.zeros(n)
    idx = np.where(rng.random(n) < 160 / SR * corre)[0]
    trancos[idx] = rng.uniform(0.3, 1.0, len(idx))
    kern = np.exp(-np.arange(int(0.004 * SR)) / (0.0012 * SR)) * np.sin(
        2 * math.pi * 650 * np.arange(int(0.004 * SR)) / SR
    )
    x += 0.35 * np.convolve(trancos, kern)[:n]
    # a ponta sai da boca: raspada curta e tilintar
    x += clique(t, 0.288, 0.012, 3200, 0.35)
    x += modos(
        t, 0.29, (2730, 4310, 6120, 8240), (0.07, 0.05, 0.035, 0.02), (0.22, 0.16, 0.1, 0.06)
    )
    return finalizar(x)


def faca_corte() -> np.ndarray:
    t = tempo(0.25)
    n = len(t)
    pico = 0.105
    larg = np.where(t < pico, 0.038, 0.06)
    sino = np.exp(-(((t - pico) / larg) ** 2))
    fc = 480 + 2300 * sino**1.2
    silvo = faixa_variavel(ruido(n), fc, 1.4)
    silvo /= np.abs(silvo).max()
    corpo = filtro(ruido(n), passa_alta=140, passa_baixa=650)
    corpo /= np.abs(corpo).max()
    x = (0.85 * silvo + 0.45 * corpo) * sino
    return finalizar(filtro(x, passa_alta=90))


def faca_impacto() -> np.ndarray:
    t = tempo(0.2)
    n = len(t)
    t0 = 0.003
    f = 55 + 80 * np.exp(-np.maximum(t - t0, 0) / 0.022)
    fase = 2 * math.pi * np.cumsum(f) / SR
    x = 1.0 * np.sin(fase) * envelope(t, t0, 0.0025, 0.045)
    x += 0.32 * np.sin(2 * math.pi * 165 * t) * envelope(t, t0, 0.0015, 0.02)
    sopro = filtro(ruido(n), passa_alta=120, passa_baixa=1400)
    x += 0.75 * sopro / np.abs(sopro).max() * envelope(t, t0, 0.001, 0.022)
    pano = filtro(ruido(n), passa_alta=1500, passa_baixa=4200)
    x += 0.12 * pano / np.abs(pano).max() * envelope(t, 0.012, 0.004, 0.04)
    return finalizar(filtro(x, passa_baixa=4500))


def baioneta_encaixe() -> np.ndarray:
    t = tempo(0.15)
    x = clique(t, 0.006, 0.0015, 3000, 0.45)
    x += modos(
        t, 0.006, (3150, 4920, 7340, 9600), (0.025, 0.018, 0.012, 0.008), (0.3, 0.22, 0.14, 0.08)
    )
    t1 = 0.046
    x += clique(t, t1, 0.002, 1500, 0.8)
    x += modos(t, t1, (2380, 3810, 6150, 8420), (0.045, 0.03, 0.02, 0.012), (0.5, 0.36, 0.22, 0.12))
    x += modos(t, t1, (520, 180), (0.025, 0.03), (0.35, 0.2))
    return finalizar(x)


SONS = {
    "faca_saque": faca_saque,
    "faca_corte": faca_corte,
    "faca_impacto": faca_impacto,
    "baioneta_encaixe": baioneta_encaixe,
}


# ------------------------------------------------------------------ arquivos
def gravar_wav(caminho: Path, x: np.ndarray) -> None:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(caminho), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.round(x * 32767).astype(np.int16).tobytes())


def para_mp3(wav: Path, mp3: Path, dur: float) -> None:
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    c = bpy.context.scene
    c.render.fps = 1000
    c.render.fps_base = 1.0
    c.frame_start = 1
    c.frame_end = int(math.ceil(dur * 1000)) + 1
    c.sequence_editor_create().strips.new_sound("som", str(wav), 1, 1)
    mp3.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.sound.mixdown(
        filepath=str(mp3),
        check_existing=False,
        container="MP3",
        codec="MP3",
        channels="MONO",
        format="S16",
        mixrate=SR,
        bitrate=192,
    )


def conferir(caminho: Path) -> dict:
    import aud

    s = aud.Sound(str(caminho))
    d = s.data()
    rate = s.specs[0]
    pico = float(np.abs(d).max())
    return {
        "amostras_hz": int(rate),
        "canais": int(d.shape[1]) if d.ndim > 1 else 1,
        "dur_s": round(len(d) / rate, 3),
        "pico_dbfs": round(20 * math.log10(pico), 2),
        "kb": round(caminho.stat().st_size / 1024, 1),
    }


def main() -> None:
    for nome, f in SONS.items():
        x = f()
        wav = TRAB / f"{nome}.wav"
        mp3 = SAIDA / f"{nome}.mp3"
        try:
            # o MP3 corta os agudos e muda o pico: uma passada de correção de ganho
            for _ in range(2):
                gravar_wav(wav, x)
                para_mp3(wav, mp3, len(x) / SR)
                info = conferir(mp3)
                ganho = 10 ** ((PICO_DB - info["pico_dbfs"]) / 20)
                if abs(info["pico_dbfs"] - PICO_DB) < 0.15 or np.abs(x).max() * ganho > 0.98:
                    break
                x = x * ganho
            print("[SOM]", nome, "wav", round(len(x) / SR, 3), "s ->", mp3.name, info, flush=True)
        except Exception as e:  # sem bpy/FFmpeg: fica o WAV
            gravar_wav(wav, x)
            print("[SOM]", nome, "MP3 falhou:", e, "- WAV em", wav, flush=True)


if __name__ == "__main__":
    main()
