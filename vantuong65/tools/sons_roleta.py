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
D-213 (a abertura da caixa), cada um com a sua semente:
- caixa_pouso.ogg: a caixa caindo no chão, com o tilintar das cantoneiras (450 ms);
- caixa_tremor.ogg: a caixa sacudindo, batidas cada vez mais juntas (1,1 s);
- caixa_estouro.ogg: a trava, o rangido, o sopro e um acorde de luz (1,6 s).
Só alguns: ... -P tools/sons_roleta.py -- caixa_
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


def atrasa(x: np.ndarray, s: float, n: int) -> np.ndarray:
    """`x` começando `s` segundos depois, num buffer de `n` amostras."""
    y = np.zeros(n)
    i = int(s * SR)
    k = min(len(x), n - i)
    if k > 0:
        y[i : i + k] = x[:k]
    return y


# D-213: a abertura da caixa (pedido do dono: "animação perfeita e realista"). Cada som tem o seu
# gerador (semente própria): os cinco de cima não mudam.
def pouso() -> np.ndarray:
    """A caixa de madeira cheia caindo no chão: baque grave, o corpo da tábua e o tilintar das
    cantoneiras (450 ms)."""
    g = np.random.default_rng(21301)
    t = t_de(450)
    n = len(t)
    baque = np.sin(2 * math.pi * 78 * t) * np.exp(-t * 16) + 0.6 * np.sin(
        2 * math.pi * 52 * t
    ) * np.exp(-t * 11)
    tabua = 0.45 * np.sin(2 * math.pi * 190 * t) * np.exp(-t * 30) + 0.3 * np.sin(
        2 * math.pi * 455 * t
    ) * np.exp(-t * 45)
    golpe = passa_faixa(g.normal(0, 1, n), 80, 2500) * np.exp(-t * 55) * 0.9
    metal = np.zeros(n)
    for s, f in ((0.018, 2900), (0.041, 3600), (0.07, 3150)):
        r = t_de(120)
        metal += atrasa(np.sin(2 * math.pi * f * r) * np.exp(-r * 70) * 0.18, s, n)
    return borda(normaliza(baque + tabua + golpe + metal, 0.85), 0.4, 30)


def tremor() -> np.ndarray:
    """A caixa sacudindo antes de abrir: batidas de madeira cada vez mais juntas e o metal das
    cantoneiras chacoalhando (1,1 s)."""
    g = np.random.default_rng(21302)
    t = t_de(1100)
    n = len(t)
    x = np.zeros(n)
    s, passo, k = 0.0, 0.16, 0
    while s < 1.0:
        r = t_de(160)
        f0 = 150 + g.uniform(-25, 25)
        bate = (np.sin(2 * math.pi * f0 * r) + 0.4 * np.sin(2 * math.pi * f0 * 2.7 * r)) * np.exp(
            -r * 38
        )
        bate += passa_faixa(g.normal(0, 1, len(r)), 200, 3000) * np.exp(-r * 70) * 0.5
        chacoalha = passa_faixa(g.normal(0, 1, len(r)), 2500, 8000) * np.exp(-r * 30) * 0.25
        forca = 0.35 + 0.65 * (s / 1.0)
        x += atrasa((bate + chacoalha) * forca, s, n)
        k += 1
        s += passo
        passo = max(0.055, passo * 0.82)
    return borda(normaliza(x, 0.7), 0.5, 40)


def estouro() -> np.ndarray:
    """A tampa saltando: o estalo da trava, o rangido da madeira, o sopro subindo e um acorde de
    luz brilhando por cima (1,6 s)."""
    g = np.random.default_rng(21303)
    t = t_de(1600)
    n = len(t)
    estalo = passa_faixa(g.normal(0, 1, n), 900, 9000) * np.exp(-t * 120) * 1.2
    estalo += np.sin(2 * math.pi * 2400 * t) * np.exp(-t * 90) * 0.4
    rangido = (
        np.sin(2 * math.pi * (210 + 90 * t) * t)
        * np.exp(-t * 9)
        * (0.5 + 0.5 * np.sin(2 * math.pi * 31 * t))
    )
    rangido *= 0.25 * (t < 0.35)
    # o sopro: ruído com o filtro abrindo (soma de faixas que entram uma depois da outra)
    sopro = np.zeros(n)
    for i, (lo, hi) in enumerate(((200, 900), (600, 2400), (1500, 5000), (3000, 9000))):
        env = np.exp(-(((t - 0.12 - 0.07 * i) / 0.16) ** 2))
        sopro += passa_faixa(g.normal(0, 1, n), lo, hi) * env * 0.35
    # o acorde de luz: três sinos suaves com vibrato, entrando devagar
    luz = np.zeros(n)
    for f, a in ((523.25, 1.0), (659.25, 0.7), (1046.5, 0.45)):
        vib = 1 + 0.004 * np.sin(2 * math.pi * 5.5 * t)
        luz += a * np.sin(2 * math.pi * f * vib * t) * (1 - np.exp(-t * 14)) * np.exp(-t * 1.6)
    return borda(normaliza(estalo + rangido + sopro + 0.32 * luz, 0.85), 0.3, 150)


SONS = {
    "roleta_tique": tique,
    "roleta_parada": parada,
    "roleta_revela": revela,
    "roleta_raro": raro,
    "roleta_lendario": lendario,
    "caixa_pouso": pouso,
    "caixa_tremor": tremor,
    "caixa_estouro": estouro,
}


def main() -> None:
    # depois do "--": nomes (ou começos de nome) para gerar só esses; sem nada, todos
    pedidos = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for nome, f in SONS.items():
        if pedidos and not any(nome.startswith(p) for p in pedidos):
            continue
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
