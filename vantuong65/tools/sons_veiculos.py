"""Sons dos veículos (STARLITE: Vietnã 1965): síntese em numpy -> OGG (FFmpeg do Blender).

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/sons_veiculos.py

Laços sem emenda (44,1 kHz, mono): todo componente periódico cabe um número inteiro de vezes no
laço e todo filtro é circular (FFT), então o fim encaixa no começo. OGG Vorbis, e não MP3: o
codificador MP3 põe silêncio no começo e no fim, o que dá um soluço a cada volta do laço.

Saídas em assets/veiculos_sons/ (os WAV de trabalho ficam na pasta temporária do sistema):
- uh34d_rotor.ogg: rotor principal do UH-34D em rotação de voo (220 rpm, 4 pás = 14,67 batidas/s):
  baque grave de cada pá, estalo da pá (slap), sopro modulado pela passagem, zumbido do rotor de
  cauda (1.100 rpm, 4 pás = 73,3 Hz) e um fio do assobio da transmissão. 9 s = 33 voltas.
- uh34d_motor.ogg: motor radial Wright R-1820 (9 cilindros, 4 tempos) a 2.400 rpm: 9 explosões por
  ciclo na ordem 1-3-5-7-9-2-4-6-8, cada cilindro um pouco diferente (o ronco "irregular" do
  radial), ressonância do coletor, válvulas e o assobio do compressor. 6 s = 120 ciclos.
- vento_cabine.ogg: vento pela porta aberta da cabine, com rajadas lentas. 8 s.
- lagarta.ogg: chocalho da lagarta (elos batendo na roda motriz e na guia) a 30 batidas/s, que o
  jogo trata como ~5 m/s (elo de ~0,17 m). 4 s.
- motor_jipe.ogg: 4 cilindros a gasolina (M151, Peugeot 403) a 2.000 rpm. 6 s.
- motor_caminhao.ogg: 6 cilindros em linha (M35) a 1.800 rpm. 6 s.
Todos os números de rotação e de pás são de projeto (PLACEHOLDER), coerentes com VehicleDrive.HELI.
"""

from __future__ import annotations

import math
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
RAIZ = Path(__file__).resolve().parents[1]
SAIDA = RAIZ / "assets" / "veiculos_sons"
TRAB = Path(tempfile.gettempdir()) / "vt65_sons_veiculos"
rng = np.random.default_rng(1965818)  # 18/08/1965, dia 1 da Starlite


# ------------------------------------------------------------------ blocos (circulares)
def amostras(dur: float) -> int:
    return int(round(dur * SR))


def ruido(n: int) -> np.ndarray:
    return rng.standard_normal(n)


def espectro(x: np.ndarray, H: np.ndarray) -> np.ndarray:
    return np.fft.irfft(np.fft.rfft(x) * H, len(x))


def freqs(n: int) -> np.ndarray:
    return np.maximum(np.fft.rfftfreq(n, 1 / SR), 1e-3)


def filtro(
    x: np.ndarray, passa_alta: float | None = None, passa_baixa: float | None = None, ordem: int = 2
) -> np.ndarray:
    """Butterworth de magnitude na FFT (fase zero, circular: não quebra o laço)."""
    f = freqs(len(x))
    H = np.ones_like(f)
    if passa_alta:
        H /= np.sqrt(1 + (passa_alta / f) ** (2 * ordem))
    if passa_baixa:
        H /= np.sqrt(1 + (f / passa_baixa) ** (2 * ordem))
    return espectro(x, H)


def ressonancias(x: np.ndarray, picos: list[tuple[float, float, float]]) -> np.ndarray:
    """Soma de picos (frequência, largura em Hz, ganho linear) sobre o sinal (circular)."""
    f = freqs(len(x))
    H = np.ones_like(f)
    for f0, bw, g in picos:
        H += g / (1 + ((f - f0) / bw) ** 2)
    return espectro(x, H)


def rosa(n: int) -> np.ndarray:
    """Ruído rosa (1/f) circular."""
    f = freqs(n)
    return espectro(ruido(n), 1 / np.sqrt(f / 100))


def trem(n: int, tempos: np.ndarray, amps: np.ndarray) -> np.ndarray:
    """Impulsos nos instantes dados (s), dando a volta no laço."""
    x = np.zeros(n)
    idx = np.round(np.asarray(tempos) * SR).astype(int) % n
    np.add.at(x, idx, amps)
    return x


def convolver(x: np.ndarray, k: np.ndarray) -> np.ndarray:
    """Convolução circular: cada impulso vira o pulso `k` (causal), e a cauda dá a volta."""
    n = len(x)
    kk = np.zeros(n)
    m = min(len(k), n)
    kk[:m] = k[:m]
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(kk), n)


def amortecido(
    dur: float, modos: list[tuple[float, float, float]], fase: float = 0.0
) -> np.ndarray:
    """Pulso de senoides amortecidas: (frequência Hz, decaimento s, amplitude)."""
    t = np.arange(amostras(dur)) / SR
    k = np.zeros_like(t)
    for f0, tau, a in modos:
        k += a * np.exp(-t / tau) * np.sin(2 * np.pi * f0 * t + fase)
    ataque = np.minimum(t / 0.0004, 1.0)  # 0,4 ms de subida: sem clique digital
    return k * ataque


def gauss(dur: float, centro: float, largura: float) -> np.ndarray:
    t = np.arange(amostras(dur)) / SR
    return np.exp(-(((t - centro) / largura) ** 2))


def normalizar(x: np.ndarray, rms_db: float = -17.0, pico_db: float = -1.0) -> np.ndarray:
    """RMS no alvo e o pico domado com saturação suave (amostra a amostra: o laço continua)."""
    x = x - x.mean()
    x = x * (10 ** (rms_db / 20) / np.sqrt(np.mean(x**2)))
    lim = 10 ** (pico_db / 20)
    return lim * np.tanh(x / lim)


# ------------------------------------------------------------------ sons
def uh34d_rotor() -> np.ndarray:
    dur = 9.0
    n = amostras(dur)
    t = np.arange(n) / SR
    volta = 220 / 60  # rev/s (VehicleDrive.HELI.rotorRpm)
    fb = 4 * volta  # 14,667 batidas/s
    nb = int(round(fb * dur))  # 132 passagens no laço
    k = np.arange(nb)
    pa = np.array([1.0, 0.92, 1.06, 0.97])[k % 4]  # pás com trilho e peso um pouco diferentes
    tk = k / fb + rng.normal(0, 0.00035, nb)
    a = pa * (1 + 0.05 * rng.standard_normal(nb))
    # baque: onda em N curta (espessura e carga da pá) sem o grave abaixo de 45 Hz, que alto-falante
    # nenhum toca; é o "wop" audível
    baque_k = -gauss(0.04, 0.010, 0.0024) + 0.75 * gauss(0.04, 0.0148, 0.0034)
    baque = filtro(convolver(trem(n, tk, a), baque_k), 55, None, ordem=3)
    # golpe de ar: ruído médio-grave que sobe e cai em ~25 ms a cada pá (o "chop")
    golpe_env = convolver(trem(n, tk + 0.003, a), gauss(0.08, 0.016, 0.0085))
    golpe = ressonancias(filtro(ruido(n), 110, 1300), [(220, 90, 1.5)]) * golpe_env
    # estalo da pá (interação com a esteira da pá da frente): curto, médio-agudo, varia muito
    estalo_k = amortecido(0.03, [(260, 0.006, 1.0), (640, 0.0035, 0.7), (1450, 0.0018, 0.45)])
    ae = pa * rng.uniform(0.45, 1.0, nb)
    estalo = convolver(trem(n, tk + 0.004, ae), estalo_k)
    # sopro: ruído de banda larga que sobe a cada passagem
    env = convolver(trem(n, tk + 0.006, a), gauss(0.08, 0.03, 0.013)) + 0.22
    sopro = filtro(ruido(n), 350, 3800) * env
    sopro = ressonancias(sopro, [(900, 400, 0.8)])
    # rotor de cauda: 1.100 rpm (VehicleDrive.HELI.tailRpm), 4 pás = 73,3 Hz, zumbido serrilhado
    fc = 4 * 1100 / 60
    nc = int(round(fc * dur))  # 660
    kc = np.arange(nc)
    cauda = convolver(
        trem(n, kc / fc + rng.normal(0, 0.00008, nc), 1 + 0.08 * rng.standard_normal(nc)),
        amortecido(0.02, [(220, 0.004, 1.0), (660, 0.0015, 0.5), (1320, 0.0009, 0.25)]),
    )
    cauda += 0.4 * filtro(ruido(n), 500, 2500) * (0.6 + 0.4 * np.sin(2 * np.pi * fc * t) ** 2)
    # assobio da transmissão: tom fraco com um pouco de vibrato (frequências múltiplas de 1/9 Hz)
    vib = 0.004 * np.sin(2 * np.pi * (2 / 9) * t)
    caixa = np.sin(2 * np.pi * 1040 * t * (1 + vib)) + 0.4 * np.sin(
        2 * np.pi * 2080 * t * (1 + vib)
    )
    # ronco grave do ar empurrado (abaixo de 120 Hz)
    grave = filtro(rosa(n), 25, 120, ordem=3)
    x = (
        1.0 * baque / np.abs(baque).max()
        + 1.0 * golpe / np.abs(golpe).max()
        + 0.70 * estalo / np.abs(estalo).max()
        + 0.25 * sopro / np.abs(sopro).max()
        + 0.15 * cauda / np.abs(cauda).max()
        + 0.018 * caixa
        + 0.12 * grave / np.abs(grave).max()
    )
    x = filtro(np.tanh(1.6 * x), 35, None, ordem=3)  # a pá "achata" o pico como no ar de verdade
    return normalizar(x, -16)


def motor_pistao(
    dur: float,
    rpm: float,
    cilindros: int,
    ordem: list[int],
    coletor: list[tuple[float, float, float]],
    aspereza: float,
    compressor: float | None = None,
) -> np.ndarray:
    """Motor de 4 tempos: cada cilindro explode uma vez a cada 2 voltas, em intervalos iguais."""
    n = amostras(dur)
    t = np.arange(n) / SR
    ciclo = 2 * 60 / rpm  # s por ciclo (2 voltas)
    nciclos = int(round(dur / ciclo))
    assert abs(nciclos * ciclo - dur) < 1e-9, "o laço precisa de ciclos inteiros"
    passo = ciclo / cilindros
    x = np.zeros(n)
    # cada cilindro: amplitude, adianto e pulso próprios (mistura e folgas diferentes)
    for j, cil in enumerate(ordem):
        amp = 1 + aspereza * rng.standard_normal()
        atraso = j * passo + aspereza * 0.03 * passo * rng.standard_normal()
        tk = np.arange(nciclos) * ciclo + atraso + rng.normal(0, 0.00012, nciclos)
        ak = amp * (1 + 0.07 * rng.standard_normal(nciclos))
        modos = [(f * (1 + 0.04 * rng.standard_normal()), tau, a) for f, tau, a in coletor]
        pulso = amortecido(0.06, modos) + 0.35 * amortecido(
            0.06, [(2600 + 300 * cil, 0.0012, 1.0)], fase=rng.uniform(0, math.pi)
        )
        estouro = filtro(ruido(amostras(0.06)), 900, 6000) * gauss(0.06, 0.0015, 0.0012)
        x += convolver(trem(n, tk, ak), pulso + 0.25 * estouro)
    # válvulas: tiques agudos, duas vezes por explosão
    tv = np.arange(nciclos * cilindros * 2) * passo / 2 + 0.3 * passo
    valv = convolver(
        trem(n, tv + rng.normal(0, 0.0001, len(tv)), rng.uniform(0.3, 1.0, len(tv))),
        amortecido(0.006, [(4200, 0.0006, 1.0), (6900, 0.0004, 0.6)]),
    )
    # admissão e sopro do motor, pulsando com as explosões
    pulsar = 0.6 + 0.4 * np.cos(2 * np.pi * (cilindros / ciclo) * t) ** 2
    sopro = filtro(ruido(n), 180, 1600) * pulsar
    y = x / np.abs(x).max() + 0.05 * valv / np.abs(valv).max() + 0.16 * sopro / np.abs(sopro).max()
    if compressor:
        y += 0.012 * np.sin(2 * np.pi * compressor * t)
    y = np.tanh(1.8 * y)
    return normalizar(y, -16)


def uh34d_motor() -> np.ndarray:
    # Wright R-1820: 9 cilindros, ordem 1-3-5-7-9-2-4-6-8; compressor ~7,1:1 com 18 pás (projeto)
    return motor_pistao(
        6.0,
        2400,
        9,
        [1, 3, 5, 7, 9, 2, 4, 6, 8],
        [(92, 0.016, 1.3), (310, 0.006, 0.8), (780, 0.003, 0.5), (1650, 0.0015, 0.25)],
        aspereza=0.14,
        compressor=5140.0,
    )


def motor_jipe() -> np.ndarray:
    return motor_pistao(
        6.0,
        2000,
        4,
        [1, 3, 4, 2],
        [(140, 0.008, 0.8), (420, 0.006, 1.0), (1100, 0.003, 0.6), (2300, 0.0015, 0.3)],
        aspereza=0.08,
    )


def motor_caminhao() -> np.ndarray:
    return motor_pistao(
        6.0,
        1800,
        6,
        [1, 5, 3, 6, 2, 4],
        [(105, 0.011, 0.9), (330, 0.007, 1.0), (900, 0.003, 0.55), (1900, 0.0015, 0.25)],
        aspereza=0.09,
    )


def vento_cabine() -> np.ndarray:
    dur = 8.0
    n = amostras(dur)
    t = np.arange(n) / SR
    base = filtro(rosa(n), 60, 2600)
    base = ressonancias(base, [(170, 60, 1.2), (520, 160, 0.6), (1300, 300, 0.3)])
    # rajadas: soma de senos com períodos que dividem o laço (1/8 Hz, 2/8 Hz...)
    raj = np.zeros(n)
    for h in range(1, 7):
        raj += rng.uniform(0.3, 1.0) / h * np.sin(2 * np.pi * h / dur * t + rng.uniform(0, 6.3))
    raj = 0.75 + 0.25 * raj / np.abs(raj).max()
    # tremido da lona e do vão da porta (13 Hz)
    trem_porta = 1 + 0.08 * np.sin(2 * np.pi * 13 * t) * raj
    assobio = filtro(ruido(n), 2200, 4200) * (raj**3)
    x = base / np.abs(base).max() * raj * trem_porta + 0.06 * assobio / np.abs(assobio).max()
    return normalizar(x, -19)


def lagarta() -> np.ndarray:
    dur = 4.0
    n = amostras(dur)
    taxa = 30.0  # batidas/s (elo de ~0,17 m a ~5 m/s)
    nb = int(round(taxa * dur))
    k = np.arange(nb)
    tk = k / taxa + rng.normal(0, 0.0025, nb)
    x = np.zeros(n)
    # elo batendo no dente: 3 variações de metal (aço com folga, pino gasto, sapata com terra)
    variacoes = [
        [(380, 0.020, 1.0), (1130, 0.012, 0.6), (2350, 0.006, 0.35), (3900, 0.004, 0.2)],
        [(450, 0.016, 1.0), (1290, 0.010, 0.5), (2710, 0.005, 0.3)],
        [(330, 0.024, 1.0), (980, 0.014, 0.7), (2050, 0.007, 0.4), (3300, 0.003, 0.2)],
    ]
    escolha = rng.integers(0, 3, nb)
    for v, modos in enumerate(variacoes):
        sel = escolha == v
        amps = rng.uniform(0.35, 1.0, sel.sum())
        x += convolver(trem(n, tk[sel], amps), amortecido(0.12, modos))
    # a outra lagarta, defasada, e o baque surdo das rodas no elo
    x += 0.7 * np.roll(x, amostras(0.0137))
    baque = convolver(trem(n, tk + 0.002, rng.uniform(0.6, 1.0, nb)), -gauss(0.04, 0.008, 0.004))
    rolar = filtro(rosa(n), 40, 400)
    y = (
        x / np.abs(x).max()
        + 0.45 * baque / np.abs(baque).max()
        + 0.35 * rolar / np.abs(rolar).max()
    )
    return normalizar(np.tanh(1.4 * y), -17)


SONS = {
    "uh34d_rotor": uh34d_rotor,
    "uh34d_motor": uh34d_motor,
    "vento_cabine": vento_cabine,
    "lagarta": lagarta,
    "motor_jipe": motor_jipe,
    "motor_caminhao": motor_caminhao,
}


# ------------------------------------------------------------------ arquivos
def gravar_wav(caminho: Path, x: np.ndarray) -> None:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(caminho), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.round(np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def para_ogg(wav: Path, ogg: Path, n: int) -> None:
    """Mixdown do Blender a 1000 quadros/s: o laço tem ms inteiros, então sai na medida exata."""
    import bpy

    ms = n * 1000 // SR
    assert ms * SR == n * 1000, "duração do laço precisa ser um número inteiro de ms"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    c = bpy.context.scene
    c.render.fps = 1000
    c.render.fps_base = 1.0
    c.frame_start = 1
    c.frame_end = ms
    c.sequence_editor_create().strips.new_sound("som", str(wav), 1, 1)
    ogg.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.sound.mixdown(
        filepath=str(ogg),
        check_existing=False,
        container="OGG",
        codec="VORBIS",
        channels="MONO",
        format="S16",
        mixrate=SR,
        bitrate=160,
    )


def conferir(caminho: Path, original: np.ndarray) -> dict:
    """Relê o OGG: duração, pico, RMS e o salto na emenda (fim -> começo) contra o salto típico."""
    import aud

    d = np.asarray(aud.Sound(str(caminho)).data())
    d = d[:, 0] if d.ndim > 1 else d
    passo = np.abs(np.diff(d))
    emenda = abs(float(d[0] - d[-1]))
    return {
        "dur_s": round(len(d) / SR, 4),
        "amostras_iguais": len(d) == len(original),
        "pico_dbfs": round(20 * math.log10(float(np.abs(d).max())), 2),
        "rms_dbfs": round(10 * math.log10(float(np.mean(d**2))), 2),
        "emenda": round(emenda, 4),
        "salto_p99": round(float(np.percentile(passo, 99)), 4),
        "kb": round(caminho.stat().st_size / 1024, 1),
    }


def referencia() -> None:
    """Nível dos motores já publicados (ForgeGUI), para os novos ficarem na mesma altura."""
    import aud

    for nome in ("motor_tanque", "motor_anfibio"):
        p = RAIZ / "assets" / "forgegui" / "audio" / f"{nome}.mp3"
        if p.exists():
            d = np.asarray(aud.Sound(str(p)).data())
            d = d.mean(axis=1) if d.ndim > 1 else d
            rms = 10 * math.log10(float(np.mean(d**2)))
            print("[REF]", nome, "rms_dbfs", round(rms, 2), "dur_s", round(len(d) / SR, 2))


def main() -> None:
    try:
        referencia()
    except Exception as e:  # sem o aud do Blender
        print("[REF] sem leitura:", e)
    for nome, f in SONS.items():
        x = f()
        wav = TRAB / f"{nome}.wav"
        ogg = SAIDA / f"{nome}.ogg"
        gravar_wav(wav, x)
        emenda_wav = abs(float(x[0] - x[-1]))
        try:
            para_ogg(wav, ogg, len(x))
            info = conferir(ogg, x)
            print("[SOM]", nome, "emenda_wav", round(emenda_wav, 4), info, flush=True)
        except Exception as e:  # sem bpy/FFmpeg: fica o WAV
            print("[SOM]", nome, "OGG falhou:", e, "- WAV em", wav, flush=True)


if __name__ == "__main__":
    main()
