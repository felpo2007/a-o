"""Som do ataque aéreo (lote 18, D-132; pedido do dono: "o ataque aéreo deve ter um som específico
quando vai acontecer"): o A-4 Skyhawk chegando em mergulho sobre o objetivo, passando e indo embora.

Síntese em numpy -> OGG (o FFmpeg do Blender, como em `tools/sons_veiculos.py`):

    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/som_ataque_aereo.py

Saída: `assets/veiculos_sons/a4_mergulho.ogg`, 12 s, mono, 44,1 kHz. Não é laço: toca uma vez.

Modelo (números de projeto, PLACEHOLDER):
- o avião voa em linha reta a 200 m/s e passa a 250 m do ouvinte (que está no objetivo) aos 9,0 s:
  é quando as bombas saem; o jogo põe o primeiro impacto aos 10 s do aviso;
- turbojato J52 (o motor do A-4): rugido largo (ruído) e o assobio do compressor e da turbina
  (tons de 620, 1.240, 2.480 e 3.700 Hz) com o efeito Doppler da passagem (mais agudo chegando,
  mais grave indo embora);
- a distância abafa: o agudo some de longe (absorção do ar), o volume segue 1/distância;
- reflexo no chão (atraso de alguns ms) dá o "rasgado" do avião baixo.
A posição no jogo (de onde vem e para onde vai) é do cliente (AudioController): o som anda pelo
céu na mesma reta, com o Doppler já gravado aqui.
"""

from __future__ import annotations

import math
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sons_veiculos as sv  # noqa: E402

SR = sv.SR
DUR = 12.0
T_PASSA = 9.0  # passagem mais perto (s)
V = 200.0  # m/s
H = 250.0  # m (distância na passagem)
C_SOM = 343.0
SAIDA = sv.SAIDA / "a4_mergulho.ogg"
TRAB = Path(tempfile.gettempdir()) / "vt65_som_ataque_aereo"
rng = np.random.default_rng(1965818)


def trajetoria(t: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Distância ao ouvinte (m) e velocidade radial (m/s, negativa chegando)."""
    x = V * (t - T_PASSA)
    r = np.sqrt(x * x + H * H)
    return r, V * x / r


def passa_baixa_variavel(x: np.ndarray, corte: np.ndarray) -> np.ndarray:
    """Um polo com o corte mudando amostra a amostra (a absorção do ar com a distância)."""
    a = np.exp(-2 * np.pi * corte / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = a[i] * acc + (1 - a[i]) * x[i]
        y[i] = acc
    return y


def sintetizar() -> np.ndarray:
    n = int(round(DUR * SR))
    t = np.arange(n) / SR
    # o som que chega agora saiu antes (atraso de propagação): avalia a fonte no tempo de emissão
    r0, _ = trajetoria(t)
    te = t - r0 / C_SOM
    r, vr = trajetoria(te)
    doppler = C_SOM / (C_SOM + vr)
    ganho = H / r  # 1 na passagem
    perto = np.clip(H / r, 0, 1)
    # rugido: ruído largo, mais agudo de perto; sobe rápido na chegada (o motor a toda)
    rugido = sv.filtro(rng.standard_normal(n), passa_alta=60, passa_baixa=5000)
    corte = 250 + 7000 * perto**2
    # dois polos em cascata (12 dB/oitava): de longe só o ronco grave chega
    rugido = passa_baixa_variavel(passa_baixa_variavel(rugido, corte), corte)
    # assobio: tons do compressor e da turbina com Doppler (fase integrada)
    assobio = np.zeros(n)
    for f0, amp in ((620, 0.5), (1240, 0.35), (2480, 0.22), (3700, 0.12)):
        jitter = 1 + 0.004 * sv.filtro(rng.standard_normal(n), passa_baixa=3)
        fase = 2 * np.pi * np.cumsum(f0 * doppler * jitter) / SR
        assobio += amp * np.sin(fase)
    assobio *= perto**1.3  # o assobio cresce com a chegada
    rugido = rugido / (np.std(rugido) + 1e-9)
    sinal = (0.75 * rugido + 0.9 * assobio) * ganho
    # reflexo no chão: o avião baixo "rasga"
    atraso = int(0.004 * SR)
    sinal = sinal + 0.3 * np.concatenate([np.zeros(atraso), sinal[:-atraso]])
    # entrada e saída suaves; o pico fica na passagem
    env = np.clip(t / 1.2, 0, 1) * np.clip((DUR - t) / 1.5, 0, 1)
    sinal *= env
    return 0.89 * sinal / (np.abs(sinal).max() + 1e-9)


def main() -> None:
    x = sintetizar()
    TRAB.mkdir(parents=True, exist_ok=True)
    wav = TRAB / "a4_mergulho.wav"
    sv.gravar_wav(wav, x)
    try:
        sv.para_ogg(wav, SAIDA, len(x))
        print("[SOM] a4_mergulho", sv.conferir(SAIDA, x), flush=True)
    except Exception as e:  # sem bpy/FFmpeg: fica o WAV
        print("[SOM] a4_mergulho OGG falhou:", e, "- WAV em", wav, flush=True)
    passa = int(T_PASSA * SR)
    # brilho (centroide do espectro) em alguns instantes: sobe na chegada e cai depois da passagem
    for ts in (1.0, 4.0, 7.0, 8.8, 10.0, 11.0):
        i = int(ts * SR)
        seg = x[i : i + 4096] * np.hanning(4096)
        s = np.abs(np.fft.rfft(seg))
        f = np.fft.rfftfreq(4096, 1 / SR)
        print(f"[SOM] t={ts:4.1f} s centroide {float((s * f).sum() / (s.sum() + 1e-9)):6.0f} Hz")
    print(
        "[SOM] pico na passagem:",
        round(20 * math.log10(float(np.abs(x[passa - SR // 4 : passa + SR // 4]).max())), 2),
        "dBFS; início:",
        round(20 * math.log10(float(np.abs(x[:SR]).max()) + 1e-9), 2),
        "dBFS",
    )


if __name__ == "__main__":
    main()
