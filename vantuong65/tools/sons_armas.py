"""Sons das armas e do campo (D-204; prompt de jogabilidade, §9): síntese própria em numpy.

Uso (a partir de vantuong65, PowerShell):
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/sons_armas.py                    # gera os kits (OGG) e o Shared/SomKits.luau
    uv run --group arte python tools/sons_armas.py --medir   # números e espectrogramas (sem OGG)

Antes, cada arma tocava o disparo da sua classe (5 gravações de biblioteca para 12 armas) com o tom
trocado e um "corpo" uma oitava abaixo. Agora cada arma tem um KIT próprio, um arquivo com trechos
separados por silêncio, que o jogo toca pelo PlaybackRegion (Shared/SomKits, gerado aqui):
- p1..p4: o próprio tiro em 1ª pessoa (a mecânica da arma no ouvido, o grave forte, o estalo da bala
  fraco, o reflexo do chão a ~8 ms);
- e1..e3: o tiro de outro soldado perto (o sopro da boca e o estalo da bala na frente, a mecânica
  quase some, o reflexo do chão a <1 ms);
- seco: o gatilho sem munição (cão ou percussor da arma);
- as peças da recarga do tipo da arma (carregador, fita, clipe, cartucho a cartucho, lançador);
- ciclo: o ferrolho manual ou a bomba entre os tiros;
- estojo1, estojo2: o estojo caindo (latão de fuzil ou de pistola, plástico, alumínio).
Cada tiro é feito de camadas com nome: o pulso de pressão (Friedlander), o sopro dos gases com a
"voz" da boca (picos), o estrondo grave que cai de tom, o estalo supersônico (onda N), a mecânica
(modos amortecidos de aço) e o reflexo do chão. A identidade de cada arma sai dos parâmetros
(calibre, cano, sistema de ação, material); as variações mudam pouco (±2,5% no tom do grave, ±6%
nos decaimentos, ±1,5 ms na mecânica), sem mexer no caráter.
Kits de fora das armas: caudas (o lugar de quem ouve: aberto, mata, fechado, túnel), distância
(médio e longe), balas (estalo, zunido e o marcador de acerto), passos (5 chãos x 6), impactos
(terra, água, madeira, palha, carne x 4), explosões e pazadas (4 variações do D-183).
Saídas: assets/armas_sons/<kit>.ogg, src/ReplicatedStorage/Shared/SomKits.luau e, com --medir,
assets/armas_sons/medidas.json e as imagens na pasta temporária (vt65_sons_armas/previas).
"""

from __future__ import annotations

import json
import math
import sys
import tempfile
import zlib
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sons_veiculos as base  # noqa: E402

SR = base.SR
RAIZ = base.RAIZ
SAIDA = RAIZ / "assets" / "armas_sons"
TRAB = Path(tempfile.gettempdir()) / "vt65_sons_armas"
LUAU = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "SomKits.luau"
GAP_S = 0.06  # silêncio entre trechos (múltiplo de 10 ms: o mixdown sai na medida)
PRE_S = 0.004  # silêncio antes do ataque de cada tiro


# ------------------------------------------------------------------ blocos
def rng_de(*partes: object) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32("/".join(map(str, partes)).encode()))


def n_de(dur: float) -> int:
    return int(round(dur * SR))


def _tam(n: int) -> int:
    return 1 << int(math.ceil(math.log2(max(2 * n, 2))))


def filtrar(x: np.ndarray, ganho) -> np.ndarray:
    """Filtro de magnitude na FFT, com folga de zeros (sem dar a volta)."""
    n = len(x)
    N = _tam(n)
    f = np.maximum(np.fft.rfftfreq(N, 1 / SR), 1e-3)
    return np.fft.irfft(np.fft.rfft(x, N) * ganho(f), N)[:n]


def banda(
    x: np.ndarray, lo: float | None = None, hi: float | None = None, ordem: int = 2
) -> np.ndarray:
    def g(f: np.ndarray) -> np.ndarray:
        h = np.ones_like(f)
        if lo:
            h = h / np.sqrt(1 + (lo / f) ** (2 * ordem))
        if hi:
            h = h / np.sqrt(1 + (f / hi) ** (2 * ordem))
        return h

    return filtrar(x, g)


def picos(x: np.ndarray, lista: list[tuple[float, float, float]]) -> np.ndarray:
    """Ressonâncias (frequência, largura em Hz, ganho linear) somadas ao sinal."""

    def g(f: np.ndarray) -> np.ndarray:
        h = np.ones_like(f)
        for f0, w, a in lista:
            h = h + a / (1 + ((f - f0) / w) ** 2)
        return h

    return filtrar(x, g)


def prateleira(x: np.ndarray, f0: float, db: float) -> np.ndarray:
    """Prateleira de agudos: acima de f0 ganha `db`."""
    k = 10 ** (db / 20)
    return filtrar(x, lambda f: 1 + (k - 1) / (1 + (f0 / f) ** 2))


def atrasa(x: np.ndarray, s: float) -> np.ndarray:
    d = int(round(s * SR))
    y = np.zeros_like(x)
    if 0 <= d < len(x):
        y[d:] = x[: len(x) - d]
    return y


def modo(
    t: np.ndarray, at: float, f: float, tau: float, a: float, fase: float = 0.0, vib: float = 0.0
) -> np.ndarray:
    """Senoide amortecida a partir de `at` (aço, madeira); `vib` treme o tom (mola)."""
    u = t - at
    m = u >= 0
    y = np.zeros_like(t)
    uu = u[m]
    if vib:
        ff = f * (1 + vib * np.sin(2 * np.pi * 7 * uu))
        ph = 2 * np.pi * np.cumsum(ff) / SR
    else:
        ph = 2 * np.pi * f * uu
    y[m] = a * np.exp(-uu / tau) * np.sin(ph + fase) * np.minimum(uu / 0.0002, 1)
    return y


def estalo(
    t: np.ndarray, at: float, r: np.random.Generator, lo: float, hi: float, tau: float, a: float
) -> np.ndarray:
    """Ruído curto filtrado (o clique de uma peça, o golpe)."""
    u = t - at
    m = u >= 0
    x = np.zeros_like(t)
    x[m] = r.standard_normal(int(m.sum())) * np.exp(-u[m] / tau) * np.minimum(u[m] / 0.0001, 1)
    return banda(x, lo, hi) * a


def raspa(
    t: np.ndarray,
    at: float,
    dur: float,
    r: np.random.Generator,
    lo: float,
    hi: float,
    a: float,
    aspereza: float = 0.5,
) -> np.ndarray:
    """Atrito (peça deslizando): ruído filtrado com o tremor da aspereza, em arco."""
    u = (t - at) / dur
    m = (u >= 0) & (u <= 1)
    env = np.zeros_like(t)
    env[m] = np.sin(np.pi * u[m]) ** 0.7
    trem = np.abs(banda(r.standard_normal(len(t)), None, 80))
    trem = 1 - aspereza + aspereza * trem / (trem.max() + 1e-12)
    return banda(r.standard_normal(len(t)), lo, hi) * env * trem * a


def graos(
    t: np.ndarray,
    t0: float,
    dur: float,
    taxa: float,
    r: np.random.Generator,
    lo: float,
    hi: float,
    a: float,
) -> np.ndarray:
    """Chuva de estalinhos (terra, capim, areia): mais no começo."""
    x = np.zeros_like(t)
    n = r.poisson(taxa * dur)
    for _ in range(n):
        ti = t0 + dur * r.random() ** 1.7
        i = int(ti * SR)
        k = int(SR * r.uniform(0.0008, 0.004))
        if i < 0 or i + k >= len(t):
            continue
        x[i : i + k] += (
            r.standard_normal(k) * np.exp(-np.arange(k) / (k / 3)) * r.uniform(0.15, 1.0)
        )
    return banda(x, lo, hi) * a


def friedlander(t: np.ndarray, t0: float, T: float, b: float = 1.6) -> np.ndarray:
    """Pulso de pressão de uma explosão: sobe na hora, cai e passa do zero em T."""
    u = t - t0
    return np.where(u >= 0, (1 - u / T) * np.exp(-b * np.maximum(u, 0) / T), 0.0)


OITAVAS = (63, 125, 250, 500, 1000, 2000, 4000, 8000)


def difuso(
    n: int,
    r: np.random.Generator,
    taus: list[float],
    ganhos: list[float],
    inicio: float,
    ataque: float,
) -> np.ndarray:
    """Cauda difusa: cada oitava decai no seu tempo (o agudo morre antes, o som escurece)."""
    t = np.arange(n) / SR
    u = t - inicio
    x = np.zeros(n)
    for fc, tau, g in zip(OITAVAS, taus, ganhos, strict=True):
        b = banda(r.standard_normal(n), fc / 1.41, fc * 1.41, 2)
        b /= np.std(b) + 1e-12
        env = np.where(
            u >= 0, (1 - np.exp(-np.maximum(u, 0) / ataque)) * np.exp(-np.maximum(u, 0) / tau), 0.0
        )
        x += b * env * g
    return x


def tapas(
    n: int, r: np.random.Generator, tempos: list[float], ganhos: list[float], agudo
) -> np.ndarray:
    """Reflexos que voltam (a linha de árvores, o morro): cada um mais escuro que o anterior."""
    x = np.zeros(n)
    k = int(0.07 * SR)
    for ti, g in zip(tempos, ganhos, strict=True):
        i = int(ti * SR)
        if i + k >= n:
            continue
        burst = r.standard_normal(k) * np.exp(-np.arange(k) / (0.008 * SR))
        x[i : i + k] += banda(burst, 70, agudo(ti)) * g
    return x


def nivel_pico(x: np.ndarray, db: float) -> np.ndarray:
    m = float(np.abs(x).max())
    return x * (10 ** (db / 20) / m) if m > 0 else x


def nivel_rms(x: np.ndarray, db: float, i0: int = 0, i1: int | None = None) -> np.ndarray:
    seg = x[i0:i1]
    rms = float(np.sqrt(np.mean(seg**2))) + 1e-12
    return x * (10 ** (db / 20) / rms)


def limita(x: np.ndarray, pico_db: float = -1.0) -> np.ndarray:
    lim = 10 ** (pico_db / 20)
    return lim * np.tanh(x / lim)


def bordas(x: np.ndarray, ms_in: float = 0.5, ms_out: float = 15.0) -> np.ndarray:
    y = x.copy()
    a, b = int(SR * ms_in / 1000), int(SR * ms_out / 1000)
    if a > 0:
        y[:a] *= np.linspace(0, 1, a)
    if b > 0:
        y[-b:] *= np.linspace(1, 0, b)
    return y


# ------------------------------------------------------------------ armas
# Tupla da mecânica: (ms depois do tiro, [(Hz, tau ms, amplitude)], ruído, (Hz baixo, Hz alto),
# tau ms do ruído)
ARMAS: dict[str, dict] = {
    # 7,62x51, cano de 22", ferrolho rotativo com haste de operação (o "clanc" do aço)
    "m14": dict(
        T=1.6,
        fr=1.0,
        lo=180,
        hi=9000,
        bark=[(900, 300, 1.2), (2400, 700, 0.6)],
        sopro=0.7,
        tf=4,
        ts=30,
        slow=0.35,
        boom=(130, 62, 90, 0.9),
        sub=0.4,
        crack=0.5,
        L=0.45,
        mec=[
            (3, [(4200, 4, 0.25), (6100, 3, 0.15)], 0.15, (3000, 9000), 2),
            (32, [(1250, 22, 0.55), (2550, 14, 0.35), (3900, 8, 0.2)], 0.3, (800, 6000), 6),
            (68, [(950, 26, 0.6), (2100, 16, 0.4), (4300, 7, 0.2)], 0.35, (700, 7000), 5),
        ],
        ganho=-0.5,
        dur=0.62,
        mat="aco",
        recarga="caixa",
        estojo="fuzil",
        familia="fuzil",
    ),
    # 5,56x45, cano de 20", gás direto: mais seco e agudo, a mola do amortecedor que canta
    "m16": dict(
        T=1.1,
        fr=1.0,
        lo=250,
        hi=11000,
        bark=[(1500, 450, 1.0), (3300, 900, 0.8)],
        sopro=0.75,
        tf=3,
        ts=22,
        slow=0.3,
        boom=(160, 75, 65, 0.6),
        sub=0.25,
        crack=0.75,
        L=0.32,
        mec=[
            (3, [(4800, 3, 0.25)], 0.15, (3500, 10000), 1.5),
            (36, [(620, 20, 0.4), (1700, 12, 0.3)], 0.25, (600, 5000), 5),
            (74, [(3300, 9, 0.35), (1150, 15, 0.3)], 0.3, (1000, 8000), 4),
        ],
        mola=(2850, 90, 0.18, 36),
        ganho=-1.5,
        dur=0.58,
        mat="aluminio",
        recarga="caixa",
        estojo="fuzil_leve",
        familia="fuzil",
    ),
    # 7,62x39, cano de 16", pistão longo: a boca "late" mais e o transportador bate pesado
    "type56": dict(
        T=1.4,
        fr=1.0,
        lo=160,
        hi=8500,
        bark=[(700, 250, 1.6), (1450, 450, 0.9), (3000, 900, 0.4)],
        sopro=0.85,
        tf=4.5,
        ts=34,
        slow=0.45,
        boom=(120, 66, 80, 0.8),
        sub=0.35,
        crack=0.55,
        L=0.4,
        mec=[
            (4, [(720, 28, 0.75), (1600, 18, 0.5), (3100, 9, 0.25)], 0.4, (500, 5000), 7),
            (62, [(600, 30, 0.8), (1350, 20, 0.55), (2900, 10, 0.3)], 0.45, (500, 6000), 6),
        ],
        ganho=-1.0,
        dur=0.62,
        mat="estampado",
        recarga="caixa",
        estojo="fuzil",
        familia="fuzil",
    ),
    # 7,62x39, cano de 20", pistão curto: o "ping" do pistão e um ferrolho mais leve
    "sks": dict(
        T=1.5,
        fr=1.0,
        lo=170,
        hi=9500,
        bark=[(800, 280, 1.1), (1900, 600, 0.7)],
        sopro=0.75,
        tf=4,
        ts=30,
        slow=0.35,
        boom=(125, 64, 85, 0.8),
        sub=0.35,
        crack=0.55,
        L=0.42,
        mec=[
            (3, [(2650, 15, 0.45), (5200, 6, 0.2)], 0.15, (2000, 9000), 2),
            (46, [(1050, 22, 0.5), (2300, 14, 0.35)], 0.3, (700, 6000), 5),
        ],
        ganho=-1.0,
        dur=0.6,
        mat="aco",
        recarga="clipe",
        estojo="fuzil",
        familia="fuzil",
    ),
    # 7,62x39 em fita, ferrolho aberto: o ferrolho preso atrás e a fita chacoalhando
    "rpd": dict(
        T=1.4,
        fr=1.0,
        lo=160,
        hi=8500,
        bark=[(650, 240, 1.5), (1350, 420, 0.9)],
        sopro=0.85,
        tf=4.5,
        ts=36,
        slow=0.45,
        boom=(118, 64, 85, 0.85),
        sub=0.4,
        crack=0.5,
        L=0.4,
        mec=[
            (40, [(520, 34, 0.85), (1150, 22, 0.55), (2600, 10, 0.25)], 0.45, (400, 5000), 8),
            (55, [], 0.35, (2500, 8000), 14),
            (75, [], 0.25, (3000, 8000), 10),
        ],
        ganho=-1.0,
        dur=0.62,
        mat="estampado",
        recarga="fita",
        estojo="fuzil",
        familia="fuzil",
    ),
    # 7,62x51 em fita, ferrolho aberto e pesado: o grave mais fundo das automáticas
    "m60": dict(
        T=1.7,
        fr=1.0,
        lo=150,
        hi=8500,
        bark=[(600, 220, 1.3), (1250, 400, 0.8), (2700, 800, 0.4)],
        sopro=0.8,
        tf=5,
        ts=38,
        slow=0.45,
        boom=(110, 58, 100, 1.0),
        sub=0.45,
        crack=0.5,
        L=0.45,
        mec=[
            (38, [(460, 38, 0.9), (980, 24, 0.6), (2300, 11, 0.3)], 0.45, (350, 4500), 9),
            (55, [], 0.35, (2500, 8000), 14),
            (78, [], 0.25, (3000, 8000), 10),
        ],
        ganho=-0.5,
        dur=0.66,
        mat="pesado",
        recarga="fita",
        estojo="fuzil",
        familia="fuzil",
    ),
    # .45 ACP subsônica, cano de 5": o "pou" grave de pistola, sem estalo, e o ferrolho de aço
    "m1911": dict(
        T=0.9,
        fr=1.0,
        lo=220,
        hi=8000,
        bark=[(1100, 350, 0.9), (2600, 800, 0.5)],
        sopro=0.85,
        tf=2.5,
        ts=16,
        slow=0.25,
        boom=(175, 95, 38, 0.55),
        sub=0.2,
        crack=0.0,
        L=0.3,
        mec=[
            (2, [(3800, 4, 0.25)], 0.15, (3000, 9000), 1.5),
            (24, [(1500, 16, 0.5), (3200, 9, 0.35)], 0.3, (1000, 7000), 4),
            (48, [(1250, 18, 0.45), (2750, 10, 0.3)], 0.3, (900, 7000), 4),
        ],
        ganho=-3.5,
        dur=0.42,
        mat="pistola",
        recarga="pistola",
        estojo="pistola",
        familia="pistola",
    ),
    # 7,62x25 supersônica: o estalo seco e agudo do Tokarev
    "type54": dict(
        T=0.7,
        fr=1.0,
        lo=300,
        hi=10000,
        bark=[(1400, 400, 1.0), (3200, 900, 0.7)],
        sopro=0.9,
        tf=2.2,
        ts=14,
        slow=0.22,
        boom=(200, 110, 32, 0.45),
        sub=0.15,
        crack=0.35,
        L=0.25,
        mec=[
            (2, [(4300, 3, 0.25)], 0.15, (3500, 10000), 1.5),
            (20, [(1800, 13, 0.5), (3800, 8, 0.3)], 0.3, (1200, 8000), 3.5),
            (42, [(1550, 15, 0.45), (3300, 9, 0.3)], 0.3, (1100, 8000), 3.5),
        ],
        ganho=-4.0,
        dur=0.4,
        mat="pistola_leve",
        recarga="pistola",
        estojo="pistola",
        familia="pistola",
    ),
    # .30-06, cano de 24", ferrolho manual: o tiro mais cheio; só o percussor antes
    "m70": dict(
        T=1.9,
        fr=1.0,
        lo=150,
        hi=9000,
        bark=[(800, 260, 1.0), (2100, 650, 0.6)],
        sopro=0.75,
        tf=5,
        ts=40,
        slow=0.45,
        boom=(120, 55, 120, 1.05),
        sub=0.5,
        crack=0.6,
        L=0.5,
        mec=[],
        pre=(2300, 6, 0.12),
        ganho=0.0,
        dur=0.75,
        mat="madeira_aco",
        recarga="manual",
        estojo=None,
        familia="fuzil",
        ciclo="ferrolho",
    ),
    # 7,62x54R, cano de 29": mais fundo e redondo; o percussor do Mosin bate mais forte
    "mosin": dict(
        T=2.0,
        fr=1.0,
        lo=140,
        hi=8500,
        bark=[(700, 240, 1.2), (1750, 520, 0.7)],
        sopro=0.8,
        tf=5.5,
        ts=44,
        slow=0.5,
        boom=(112, 52, 130, 1.1),
        sub=0.55,
        crack=0.6,
        L=0.55,
        mec=[],
        pre=(2000, 7, 0.16),
        ganho=0.0,
        dur=0.78,
        mat="madeira_aco_grave",
        recarga="manual",
        estojo=None,
        familia="fuzil",
        ciclo="ferrolho",
    ),
    # calibre 12 (00), cano de 20": o "bum" largo e grave, quase sem estalo
    "win12": dict(
        T=2.4,
        fr=1.0,
        lo=100,
        hi=6500,
        bark=[(450, 200, 1.0), (1100, 400, 0.6)],
        sopro=0.9,
        tf=6,
        ts=55,
        slow=0.6,
        boom=(95, 48, 140, 1.2),
        sub=0.7,
        crack=0.15,
        L=0.6,
        mec=[],
        ganho=0.0,
        dur=0.85,
        mat="aco_grave",
        recarga="tubo",
        estojo="plastico",
        familia="pesado",
        ciclo="bomba",
    ),
    # 40 mm de baixa pressão: o "tum" oco do tubo, sem estalo
    "m79": dict(
        T=3.5,
        fr=1.0,
        lo=80,
        hi=3500,
        bark=[(320, 90, 1.6), (650, 140, 0.9), (1300, 300, 0.3)],
        sopro=0.6,
        tf=8,
        ts=45,
        slow=0.5,
        boom=(140, 90, 70, 0.9),
        sub=0.5,
        crack=0.0,
        L=0.3,
        mec=[(1, [(1200, 10, 0.15)], 0.05, (800, 4000), 3)],
        ganho=-5.0,
        dur=0.6,
        mat="tubo",
        recarga="lancador",
        estojo=None,
        familia="pesado",
    ),
}

# 1ª pessoa (o próprio tiro) e 3ª pessoa perto (outro soldado atirando)
PERSP = {
    "p": dict(
        blast=1.0,
        boom=1.15,
        crack=0.35,
        mec=0.4,
        agudo_db=-3.0,
        chao=0.32,
        chao_ms=8.5,
        chao_hi=1800,
        drive=1.6,
        incl=0.55,
    ),
    "e": dict(
        blast=1.0,
        boom=0.45,
        crack=1.0,
        mec=0.06,
        agudo_db=2.0,
        chao=0.4,
        chao_ms=0.7,
        chao_hi=3500,
        drive=1.25,
        incl=0.35,
    ),
}


def inclina(x: np.ndarray, k: float, f0: float = 1000.0) -> np.ndarray:
    """Agudos caindo acima de f0 (k = 0,5: -3 dB/oitava); tiro de verdade é mais grave que ruído."""
    return filtrar(x, lambda f: np.where(f > f0, (f / f0) ** (-k), 1.0))


def tiro(nome: str, persp: str, var: int) -> np.ndarray:
    p = ARMAS[nome]
    pp = PERSP[persp]
    r = rng_de(nome, persp, var)

    def j(k: float) -> float:
        return 1 + (r.random() * 2 - 1) * k

    n = n_de(p["dur"])
    t = np.arange(n) / SR
    t0 = PRE_S
    u = t - t0
    on = u >= 0
    uu = np.where(on, u, 0.0)
    # 1) pulso de pressão
    T = p["T"] / 1000 * j(0.06)
    fr = banda(friedlander(t, t0, T), 30, 12000)
    # 2) sopro dos gases com a voz da boca
    tf, ts = p["tf"] / 1000 * j(0.06), p["ts"] / 1000 * j(0.06)
    env = np.where(on, np.exp(-uu / tf) + p["slow"] * np.exp(-uu / ts), 0.0) * np.minimum(
        uu / 0.00015, 1
    )
    sop = banda(r.standard_normal(n) * env, p["lo"], p["hi"])
    sop = picos(sop, [(f * j(0.03), w, a) for f, w, a in p["bark"]])
    sop = prateleira(sop, 3500, pp["agudo_db"])
    # pela energia, não pelo pico (o pico do ruído é sorteado: mudava o timbre entre as variações)
    i0, i30 = int(t0 * SR), int((t0 + 0.03) * SR)
    sop /= 4 * float(np.sqrt(np.mean(sop[i0:i30] ** 2))) + 1e-12
    # 3) estrondo grave que cai de tom e o grave de ruído
    f0, f1, tb_ms, a_boom = p["boom"]
    f0, f1, tb = f0 * j(0.025), f1 * j(0.025), tb_ms / 1000 * j(0.06)
    fi = np.where(on, f1 + (f0 - f1) * np.exp(-uu / 0.014), 0.0)
    boom = np.sin(2 * np.pi * np.cumsum(fi) / SR) * np.where(
        on, (1 - np.exp(-uu / 0.0012)) * np.exp(-uu / tb), 0.0
    )
    sub = banda(r.standard_normal(n) * np.where(on, np.exp(-uu / (tb * 0.7)), 0.0), 25, 230, 3)
    sub /= 4 * float(np.sqrt(np.mean(sub[i0 : i0 + int(0.1 * SR)] ** 2))) + 1e-12
    # 4) estalo supersônico (onda N)
    crack = np.zeros(n)
    if p["crack"] > 0:
        L = p["L"] / 1000 * j(0.05)
        k = (u >= 0.0002) & (u < 0.0002 + L)
        crack[k] = 1 - 2 * (u[k] - 0.0002) / L
        crack = banda(crack, 900, 16000)
        crack /= np.abs(crack).max() + 1e-12
    # 5) mecânica
    mec = np.zeros(n)
    for ms, modos, ra, (lo, hi), rtau in p["mec"]:
        at = t0 + ms / 1000 + (r.random() - 0.5) * 0.003
        ga = j(0.15)
        for f, tau, a in modos:
            mec += modo(t, at, f * j(0.02), tau / 1000, a * ga, r.random() * 6.28)
        if ra > 0:
            mec += estalo(t, at, r, lo, hi, rtau / 1000, ra * ga)
    if p.get("mola"):
        f, tau, a, at_ms = p["mola"]
        mec += modo(t, t0 + at_ms / 1000, f * j(0.01), tau / 1000, a * j(0.15), vib=0.004)
    if p.get("pre"):
        f, tau, a = p["pre"]
        mec += modo(t, 0.0005, f, tau / 1000, a)
    x = (
        (fr * p["fr"] * 0.9 + sop * p["sopro"] * 0.7) * pp["blast"]
        + boom * a_boom * pp["boom"]
        + sub * p["sub"] * pp["boom"]
        + crack * p["crack"] * pp["crack"]
        + mec * pp["mec"]
    )
    # 6) reflexo do chão (no ouvido do atirador ~8 ms; de longe, quase junto) e os agudos inclinados
    x = x + banda(atrasa(x, pp["chao_ms"] / 1000), None, pp["chao_hi"]) * pp["chao"]
    x = inclina(x, pp["incl"])
    # 7) saturação suave (o ouvido e o microfone no limite) e o nível da arma. A entrada da
    # saturação vai pela energia dos primeiros 60 ms (estável entre variações), não pelo pico
    x = x / (8 * float(np.sqrt(np.mean(x[i0 : i0 + int(0.06 * SR)] ** 2))) + 1e-12)
    x = np.tanh(x * pp["drive"]) / np.tanh(pp["drive"])
    x = banda(x, 20, None, 2)  # sem desvio de DC (a saturação de um pulso assimétrico)
    x = nivel_pico(x, -1.0 + p["ganho"])
    return bordas(x, 0.3, 15)


# ------------------------------------------------------------------ mecânica e recarga
MAT = {
    "aco": dict(
        clk=[(1800, 18, 0.5), (3600, 10, 0.35), (5400, 6, 0.2)],
        grave=(260, 30, 0.35),
        raspa=(1200, 7000),
    ),
    "aco_grave": dict(
        clk=[(1500, 20, 0.5), (3100, 11, 0.35), (4700, 7, 0.2)],
        grave=(220, 32, 0.4),
        raspa=(1000, 6500),
    ),
    "aluminio": dict(
        clk=[(2400, 12, 0.45), (4300, 8, 0.35), (7100, 5, 0.2)],
        grave=(320, 20, 0.25),
        raspa=(1800, 9000),
    ),
    "estampado": dict(
        clk=[(1300, 26, 0.6), (2700, 16, 0.4), (4100, 9, 0.25)],
        grave=(220, 35, 0.4),
        raspa=(900, 6500),
    ),
    "pistola": dict(
        clk=[(2600, 10, 0.45), (4800, 7, 0.3)], grave=(380, 18, 0.2), raspa=(1500, 8000)
    ),
    "pistola_leve": dict(
        clk=[(2900, 9, 0.45), (5400, 6, 0.3)], grave=(420, 16, 0.18), raspa=(1700, 9000)
    ),
    "pesado": dict(
        clk=[(900, 40, 0.7), (1900, 24, 0.5), (3300, 12, 0.3)],
        grave=(150, 45, 0.5),
        raspa=(700, 5500),
    ),
    "madeira_aco": dict(
        clk=[(2100, 14, 0.45), (3900, 9, 0.3)], grave=(240, 25, 0.25), raspa=(1400, 7500)
    ),
    "madeira_aco_grave": dict(
        clk=[(1850, 16, 0.45), (3500, 10, 0.3)], grave=(210, 28, 0.3), raspa=(1200, 7000)
    ),
    "tubo": dict(clk=[(1100, 30, 0.5), (2300, 18, 0.35)], grave=(180, 40, 0.4), raspa=(800, 5000)),
}


def clac(
    t: np.ndarray, at: float, mat: dict, r: np.random.Generator, a: float, k: float = 1.0
) -> np.ndarray:
    """Peça de metal batendo: os modos do material, o estalo e o grave do corpo da arma."""
    y = np.zeros_like(t)
    for f, tau, g in mat["clk"]:
        y += modo(t, at, f * k * (1 + (r.random() - 0.5) * 0.03), tau / 1000, g, r.random() * 6.28)
    f, tau, g = mat["grave"]
    y += modo(t, at, f * k, tau / 1000, g)
    y += estalo(t, at, r, 1500 * k, 12000, 0.0012, 0.35)
    return y * a


def parte(nome: str, arma: str, var: int = 1) -> tuple[np.ndarray, float]:
    """Uma peça de foley da arma. Devolve (som, âncora em s: o instante que casa com a animação)."""
    p = ARMAS[arma]
    mat = MAT[p["mat"]]
    r = rng_de(arma, nome, var)
    lo, hi = mat["raspa"]
    ancora = 0.01

    def tt(d: float) -> np.ndarray:
        return np.arange(n_de(d)) / SR

    if nome == "solta":
        t = tt(0.12)
        x = clac(t, 0.01, mat, r, 0.5, 1.3)
    elif nome == "sai":
        t = tt(0.22)
        x = raspa(t, 0.0, 0.13, r, lo, hi, 0.45) + clac(t, 0.125, mat, r, 0.3, 1.1)
        ancora = 0.0
    elif nome == "cai":  # o carregador vazio batendo na terra
        t = tt(0.25)
        x = estalo(t, 0.01, r, 80, 900, 0.02, 0.6) + modo(t, 0.01, mat["grave"][0] * 0.6, 0.03, 0.3)
        x += clac(t, 0.012, mat, r, 0.12, 0.9)
    elif nome == "entra":
        t = tt(0.24)
        x = raspa(t, 0.0, 0.07, r, lo, hi, 0.4) + clac(t, 0.075, mat, r, 1.0)
        ancora = 0.075
    elif nome == "tapa":  # a palma no fundo do carregador
        t = tt(0.18)
        x = estalo(t, 0.004, r, 150, 1500, 0.01, 0.8) + modo(t, 0.004, 210, 0.025, 0.4)
        x += clac(t, 0.006, mat, r, 0.25)
        ancora = 0.004
    elif nome == "ferrolho":  # puxa a alavanca de manejo (mola) e solta: o ferrolho fecha
        t = tt(0.4)
        x = raspa(t, 0.0, 0.11, r, lo * 0.8, hi, 0.45, 0.6)
        x += modo(t, 0.01, mat["clk"][0][0] * 1.4, 0.08, 0.08, vib=0.006)
        x += clac(t, 0.11, mat, r, 0.45, 1.1) + clac(t, 0.17, mat, r, 1.1, 0.95)
        ancora = 0.0
    elif nome == "slide":  # o ferrolho da pistola volta para a frente
        t = tt(0.16)
        x = clac(t, 0.005, mat, r, 1.0)
        ancora = 0.005
    elif nome == "tampa_abre":  # tampa da caixa da metralhadora
        t = tt(0.25)
        x = clac(t, 0.01, mat, r, 0.8) + modo(t, 0.012, 1100, 0.06, 0.12, vib=0.01)
    elif nome == "fita":  # elos da fita chacoalhando
        t = tt(0.42)
        x = raspa(t, 0.02, 0.3, r, 1500, 8000, 0.15)
        for _ in range(12):
            x += estalo(t, 0.03 + 0.3 * r.random(), r, 2000, 8000, 0.0015, r.uniform(0.25, 0.5))
        ancora = 0.03
    elif nome == "tampa_fecha":
        t = tt(0.22)
        x = clac(t, 0.01, mat, r, 1.1, 0.9)
    elif nome == "abre":  # ferrolho manual: levanta e puxa
        t = tt(0.26)
        x = (
            clac(t, 0.01, mat, r, 0.6, 1.2)
            + raspa(t, 0.05, 0.12, r, lo, hi, 0.4)
            + clac(t, 0.17, mat, r, 0.5)
        )
    elif nome == "cartucho":  # um cartucho entrando (depósito ou tubo)
        t = tt(0.12)
        x = (
            clac(t, 0.005, mat, r, 0.45, 1.25)
            + raspa(t, 0.01, 0.05, r, lo, hi, 0.3)
            + clac(t, 0.06, mat, r, 0.35, 1.4)
        )
        ancora = 0.005
    elif nome == "fecha":  # ferrolho manual: empurra e baixa a alavanca
        t = tt(0.26)
        x = (
            raspa(t, 0.0, 0.1, r, lo, hi, 0.4)
            + clac(t, 0.1, mat, r, 0.6)
            + clac(t, 0.16, mat, r, 0.8, 1.15)
        )
        ancora = 0.1
    elif nome == "clipe":  # o clipe da SKS na guia
        t = tt(0.14)
        x = clac(t, 0.01, mat, r, 0.5, 1.3) + modo(t, 0.012, 3500, 0.04, 0.1)
    elif nome == "desce":  # os 10 cartuchos descendo do clipe
        t = tt(0.48)
        x = raspa(t, 0.04, 0.38, r, lo, hi, 0.2)
        for i in range(10):
            x += clac(t, 0.05 + i * 0.035 + (r.random() - 0.5) * 0.008, mat, r, 0.32, 1.35)
        ancora = 0.05
    elif nome == "clipe_sai":  # o clipe vazio voando
        t = tt(0.2)
        x = (
            modo(t, 0.01, 3200, 0.06, 0.3)
            + modo(t, 0.01, 5100, 0.03, 0.15)
            + estalo(t, 0.01, r, 2000, 9000, 0.002, 0.3)
        )
    elif nome == "estojo_sai":  # o estojo de alumínio do 40 mm deslizando para fora
        t = tt(0.22)
        x = (
            raspa(t, 0.0, 0.08, r, 800, 5000, 0.3)
            + modo(t, 0.09, 1700, 0.03, 0.4)
            + modo(t, 0.09, 4100, 0.02, 0.2)
        )
        ancora = 0.09
    elif nome == "granada":  # a granada de 40 mm entrando no tubo
        t = tt(0.24)
        x = (
            raspa(t, 0.0, 0.1, r, 600, 4000, 0.35)
            + modo(t, 0.1, 300, 0.025, 0.6)
            + modo(t, 0.1, 900, 0.02, 0.3)
        )
        ancora = 0.1
    elif (
        nome == "bomba"
    ):  # a telha da espingarda, para trás e para a frente (0,7 s, Ferrolho.pumpCurve)
        t = tt(0.7)
        x = raspa(t, 0.05, 0.15, r, lo, hi, 0.45) + clac(t, 0.21, mat, r, 0.8)
        x += estalo(t, 0.25, r, 600, 3000, 0.01, 0.25)  # o cartucho vazio saindo
        x += raspa(t, 0.3, 0.16, r, lo, hi, 0.45) + clac(t, 0.47, mat, r, 1.0, 1.1)
        ancora = 0.0
    elif nome == "ferrolho_ciclo":  # manobra entre tiros (1,0 s, Ferrolho.curve)
        t = tt(1.0)
        x = clac(t, 0.2, mat, r, 0.55, 1.2)  # a alavanca sobe
        x += raspa(t, 0.3, 0.16, r, lo, hi, 0.45) + clac(t, 0.46, mat, r, 0.5)  # recua
        x += modo(t, 0.47, 3000, 0.03, 0.25) + modo(t, 0.47, 4700, 0.02, 0.12)  # o estojo pula
        x += raspa(t, 0.5, 0.14, r, lo, hi, 0.45) + clac(t, 0.65, mat, r, 0.55)  # volta
        x += clac(t, 0.8, mat, r, 0.85, 1.15)  # baixa e trava
        ancora = 0.0
    else:
        raise ValueError(nome)
    x = nivel_pico(x, -4.0)
    return bordas(x, 0.3, 8), ancora


def seco(arma: str) -> np.ndarray:
    """Gatilho sem munição: o gatilho e o cão (ou o percussor) caindo."""
    p = ARMAS[arma]
    mat = MAT[p["mat"]]
    r = rng_de(arma, "seco")
    t = np.arange(n_de(0.15)) / SR
    x = clac(t, 0.002, mat, r, 0.2, 1.6) + clac(t, 0.012, mat, r, 0.6, 1.1)
    return bordas(nivel_pico(x, -6.0), 0.3, 8)


ESTOJO = {
    "fuzil": dict(modos=[(3300, 25, 1.0), (5200, 18, 0.6), (7900, 10, 0.3)], baque=0.4),
    "fuzil_leve": dict(modos=[(3900, 22, 1.0), (6100, 15, 0.6), (8800, 9, 0.3)], baque=0.35),
    "pistola": dict(modos=[(4200, 20, 1.0), (6800, 14, 0.5)], baque=0.3),
    "plastico": dict(modos=[(900, 12, 0.8), (2100, 8, 0.4)], baque=0.6),
}


def estojo(arma: str, var: int) -> np.ndarray:
    """O estojo vazio batendo no chão: três quiques, cada vez mais fracos."""
    e = ESTOJO[ARMAS[arma]["estojo"]]
    r = rng_de(arma, "estojo", var)
    t = np.arange(n_de(0.35)) / SR
    x = np.zeros_like(t)
    tempos = [0.005, 0.07 + r.random() * 0.03, 0.12 + r.random() * 0.04]
    for i, at in enumerate(tempos):
        g = 0.5**i
        for f, tau, a in e["modos"]:
            x += modo(
                t, at, f * (1 + (r.random() - 0.5) * 0.06), tau / 1000, a * g, r.random() * 6.28
            )
        x += estalo(t, at, r, 200, 2500, 0.004, e["baque"] * g)
    return bordas(nivel_pico(x, -9.0), 0.3, 10)


RECARGA_PARTES = {
    "caixa": ["solta", "sai", "cai", "entra", "tapa", "ferrolho"],
    "pistola": ["solta", "sai", "cai", "entra", "slide"],
    "fita": ["tampa_abre", "fita", "tampa_fecha", "ferrolho"],
    "clipe": ["abre", "clipe", "desce", "clipe_sai", "fecha"],
    "manual": ["abre", "cartucho", "fecha"],
    "tubo": ["cartucho"],
    "lancador": ["abre", "estojo_sai", "granada", "fecha"],
}


def kit_arma(arma: str) -> list[tuple[str, np.ndarray, float]]:
    p = ARMAS[arma]
    out: list[tuple[str, np.ndarray, float]] = []
    for v in range(1, 5):
        out.append((f"p{v}", tiro(arma, "p", v), PRE_S))
    for v in range(1, 4):
        out.append((f"e{v}", tiro(arma, "e", v), PRE_S))
    out.append(("seco", seco(arma), 0.012))
    for nome in RECARGA_PARTES[p["recarga"]]:
        x, anc = parte(nome, arma)
        out.append((nome, x, anc))
    if p.get("ciclo") == "ferrolho":
        x, anc = parte("ferrolho_ciclo", arma)
        out.append(("ciclo", x, anc))
    elif p.get("ciclo") == "bomba":
        x, anc = parte("bomba", arma)
        out.append(("ciclo", x, anc))
    if p.get("estojo"):
        out.append(("estojo1", estojo(arma, 1), 0.005))
        out.append(("estojo2", estojo(arma, 2), 0.005))
    return out


# ------------------------------------------------------------------ cauda pelo lugar de quem ouve
FAMILIA = {
    "pistola": dict(db=-4.0, tk=0.8, grave=0.7),
    "fuzil": dict(db=0.0, tk=1.0, grave=1.0),
    "pesado": dict(db=1.5, tk=1.15, grave=1.35),
}
LUGAR = {
    # campo aberto: as árvores e os morros devolvem o tiro em batidas que rolam e escurecem
    "aberto": dict(
        dur=2.2,
        taus=[0.9, 0.85, 0.75, 0.6, 0.45, 0.3, 0.18, 0.1],
        ganhos=[0.5, 0.8, 1.0, 0.9, 0.6, 0.35, 0.15, 0.05],
        inicio=0.05,
        ataque=0.08,
        tapas=(7, 0.18, 1.4),
        nivel=-26.0,
    ),
    # mata: muitas folhas e troncos perto: cauda curta, densa e abafada
    "mata": dict(
        dur=1.0,
        taus=[0.35, 0.35, 0.32, 0.28, 0.2, 0.12, 0.06, 0.03],
        ganhos=[0.4, 0.7, 1.0, 1.0, 0.7, 0.35, 0.12, 0.04],
        inicio=0.008,
        ataque=0.02,
        tapas=(14, 0.01, 0.16),
        nivel=-27.0,
    ),
    # dentro da vila (paredes e telhados): reflexos cedo e reverberação curta e clara
    "fechado": dict(
        dur=0.8,
        taus=[0.3, 0.3, 0.28, 0.26, 0.24, 0.2, 0.14, 0.08],
        ganhos=[0.4, 0.7, 0.9, 1.0, 1.0, 0.8, 0.5, 0.25],
        inicio=0.004,
        ataque=0.006,
        tapas=(8, 0.004, 0.035),
        nivel=-22.0,
    ),
    # túnel: o tubo de terra ressoa grave e devolve batidas seguidas
    "tunel": dict(
        dur=2.0,
        taus=[0.9, 0.85, 0.7, 0.5, 0.35, 0.22, 0.12, 0.06],
        ganhos=[0.9, 1.0, 1.0, 0.8, 0.5, 0.3, 0.12, 0.05],
        inicio=0.006,
        ataque=0.01,
        tapas=(18, 0.006, 0.12),
        nivel=-19.0,
    ),
}


def cauda(familia: str, lugar: str, var: int) -> np.ndarray:
    F, L = FAMILIA[familia], LUGAR[lugar]
    r = rng_de("cauda", familia, lugar, var)
    n = n_de(L["dur"])
    taus = [tau * F["tk"] for tau in L["taus"]]
    ganhos = [g * (F["grave"] if i < 3 else 1.0) for i, g in enumerate(L["ganhos"])]
    x = difuso(n, r, taus, ganhos, L["inicio"], L["ataque"])
    k, t_ini, t_fim = L["tapas"]
    tempos = sorted(t_ini + (t_fim - t_ini) * r.random() for _ in range(k))
    if lugar == "tunel":  # batidas regulares (o tubo): ~12 ms entre elas
        tempos = [t_ini + 0.012 * i * (1 + (r.random() - 0.5) * 0.1) for i in range(k)]
    ganhos_t = [math.exp(-ti / (0.6 * F["tk"])) * r.uniform(0.6, 1.0) for ti in tempos]
    x = (
        x / (np.std(x[: n_de(0.5)]) + 1e-12)
        + tapas(n, r, tempos, ganhos_t, lambda ti: max(600.0, 3500 * math.exp(-ti / 0.8))) * 1.5
    )
    if lugar == "tunel":
        x += banda(x, 70, 130, 2) * 0.8
    x = nivel_rms(x, L["nivel"] + F["db"], 0, n_de(0.5))
    x = limita(x, -3.0)
    return bordas(x, 0.3, 30)


# ------------------------------------------------------------------ distância (outros, longe)
def distante(familia: str, faixa: str, var: int) -> np.ndarray:
    F = FAMILIA[familia]
    r = rng_de("dist", familia, faixa, var)
    dur = 1.6 if faixa == "medio" else 2.4
    n = n_de(dur)
    t = np.arange(n) / SR
    agudo = {"pistola": 2800, "fuzil": 2200, "pesado": 1600}[familia] * (
        1.0 if faixa == "medio" else 0.3
    )
    T = (3.0 if faixa == "medio" else 6.0) / 1000 * (1 + (r.random() - 0.5) * 0.1)
    pulso = (
        friedlander(t, PRE_S, T)
        + banda(
            r.standard_normal(n)
            * np.exp(-np.maximum(t - PRE_S, 0) / (0.012 if faixa == "medio" else 0.025))
            * (t >= PRE_S),
            60,
            None,
        )
        * 0.6
    )
    pulso = banda(pulso, 50, agudo, 3)
    u = np.maximum(t - PRE_S, 0)
    boom = (
        np.sin(2 * np.pi * (45 + 25 * np.exp(-u / 0.02)) * u)
        * np.exp(-u / (0.12 * F["tk"]))
        * (t >= PRE_S)
    )
    taus = (
        [1.0, 0.95, 0.85, 0.7, 0.5, 0.3, 0.15, 0.08]
        if faixa == "medio"
        else [1.6, 1.5, 1.3, 1.0, 0.6, 0.3, 0.15, 0.08]
    )
    gan = (
        [0.7, 1.0, 1.0, 0.8, 0.5, 0.25, 0.08, 0.02]
        if faixa == "medio"
        else [1.0, 1.0, 0.8, 0.45, 0.15, 0.04, 0.0, 0.0]
    )
    rolo = difuso(n, r, [x * F["tk"] for x in taus], gan, 0.03, 0.12 if faixa == "medio" else 0.25)
    rolo /= np.std(rolo[: n_de(0.6)]) + 1e-12
    k = 3 if faixa == "medio" else 4
    tempos = sorted(0.2 + r.random() * (dur - 0.6) for _ in range(k))
    tap = tapas(n, r, tempos, [r.uniform(0.3, 0.6) for _ in tempos], lambda ti: agudo * 0.6)
    x = nivel_pico(pulso, 1.0) + boom * 0.5 * F["grave"] + rolo * 0.12 + tap * 0.8
    x = nivel_pico(x, -3.0 + F["db"] * 0.5)
    return bordas(x, 0.3, 40)


# ------------------------------------------------------------------ bala e acerto
def bala(nome: str, var: int) -> np.ndarray:
    r = rng_de("bala", nome, var)
    if nome == "estalo":  # a onda N da bala supersônica passando perto
        t = np.arange(n_de(0.16)) / SR
        L = (0.3 + 0.1 * r.random()) / 1000
        x = np.zeros_like(t)
        k = (t >= 0.004) & (t < 0.004 + L)
        x[k] = 1 - 2 * (t[k] - 0.004) / L
        x = banda(x, 700, 16000)
        x = x / np.abs(x).max() + modo(t, 0.004, 5200 * (1 + (r.random() - 0.5) * 0.1), 0.004, 0.15)
        x += (
            banda(
                r.standard_normal(len(t))
                * np.exp(-np.maximum(t - 0.006, 0) / 0.025)
                * (t >= 0.006),
                1500,
                6000,
            )
            * 0.12
        )
        return bordas(nivel_pico(x, -2.0), 0.3, 10)
    if nome == "zunido":  # a bala lenta (ou de raspão) cortando o ar: o tom cai (Doppler)
        dur = 0.32
        t = np.arange(n_de(dur)) / SR
        f0, f1 = 2800 * (1 + (r.random() - 0.5) * 0.15), 900 * (1 + (r.random() - 0.5) * 0.15)
        fc = f1 + (f0 - f1) / (1 + np.exp((t - 0.12) / 0.025))
        x = banda(r.standard_normal(len(t)), None, 450) * np.sin(2 * np.pi * np.cumsum(fc) / SR)
        env = np.exp(-(((t - 0.12) / 0.07) ** 2))
        return bordas(nivel_pico(x * env, -4.0), 0.3, 20)
    t = np.arange(n_de(0.3)) / SR
    if nome == "acerto_corpo":  # leve e surdo: só para quem atirou
        x = (
            modo(t, 0.002, 900, 0.025, 1.0)
            + modo(t, 0.002, 1850, 0.012, 0.5)
            + estalo(t, 0.002, r, 600, 4000, 0.002, 0.3)
        )
        return bordas(nivel_pico(x[: n_de(0.12)], -10.0), 0.3, 10)
    if nome == "acerto_cabeca":  # mais claro: o "tim" metálico do capacete
        x = (
            modo(t, 0.002, 1400, 0.02, 0.8)
            + modo(t, 0.002, 3300, 0.03, 0.6)
            + modo(t, 0.002, 900, 0.02, 0.5)
        )
        return bordas(nivel_pico(x[: n_de(0.18)], -9.0), 0.3, 10)
    if nome == "acerto_abate":  # dois toques graves e um anel curto
        x = (
            modo(t, 0.002, 650, 0.03, 1.0)
            + modo(t, 0.072, 650, 0.03, 0.9)
            + modo(t, 0.072, 1950, 0.08, 0.3)
        )
        return bordas(nivel_pico(x, -9.0), 0.3, 15)
    raise ValueError(nome)


# ------------------------------------------------------------------ passos, impactos, explosões
def passo(chao: str, var: int) -> np.ndarray:
    r = rng_de("passo", chao, var)
    t = np.arange(n_de(0.45 if chao == "arrozal" else 0.38 if chao == "lama" else 0.32)) / SR
    calc = estalo(t, 0.01, r, 40, 350, 0.014, 0.8)  # o calcanhar da bota
    if chao == "grama":
        x = (
            calc
            + graos(t, 0.012, 0.14, 260, r, 1500, 8000, 0.7)
            + raspa(t, 0.02, 0.16, r, 2000, 7000, 0.12)
        )
    elif chao == "lama":
        f = 450 + 550 * np.clip((t - 0.03) / 0.2, 0, 1)
        sq = banda(r.standard_normal(len(t)), 150, 1500) * np.exp(-(((t - 0.12) / 0.07) ** 2))
        sq = sq * (1 + 0.6 * np.sin(2 * np.pi * np.cumsum(f) / SR))
        x = estalo(t, 0.01, r, 40, 250, 0.025, 0.8) + sq * 0.5
        for _ in range(2 + int(r.integers(0, 3))):
            x += modo(t, 0.15 + 0.15 * r.random(), r.uniform(1200, 2600), 0.006, 0.25)
    elif chao == "arrozal":
        x = estalo(t, 0.01, r, 300, 6000, 0.06, 0.7) + estalo(t, 0.012, r, 80, 600, 0.12, 0.5)
        for _ in range(6 + int(r.integers(0, 7))):
            at = 0.02 + 0.28 * r.random()
            f0 = r.uniform(500, 1500)
            u = np.maximum(t - at, 0)
            x += (
                np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.6 * np.minimum(u / 0.02, 1))) / SR)
                * np.exp(-u / r.uniform(0.01, 0.02))
                * (t >= at)
                * r.uniform(0.15, 0.4)
            )
    elif chao == "areia":
        x = (
            calc * 0.6
            + graos(t, 0.01, 0.12, 420, r, 2500, 10000, 0.8)
            + raspa(t, 0.015, 0.12, r, 3000, 9000, 0.1)
        )
    elif chao == "madeira":
        x = sum(
            modo(t, 0.01, f * (1 + (r.random() - 0.5) * 0.04), tau, a)
            for f, tau, a in (
                (165, 0.04, 0.6),
                (390, 0.03, 0.45),
                (820, 0.022, 0.3),
                (1550, 0.012, 0.15),
            )
        )
        x = x + estalo(t, 0.008, r, 1000, 6000, 0.002, 0.3)
        if var == 2:  # uma tábua que range
            u = np.maximum(t - 0.05, 0)
            x += (
                np.sin(2 * np.pi * np.cumsum(300 + 120 * u / 0.2) / SR)
                * np.exp(-(((t - 0.15) / 0.06) ** 2))
                * 0.06
            )
    else:
        raise ValueError(chao)
    return bordas(nivel_pico(x, -4.0 - r.random() * 1.5), 0.3, 15)


def impacto(mat: str, var: int) -> np.ndarray:
    r = rng_de("impacto", mat, var)
    t = np.arange(n_de(0.45 if mat == "agua" else 0.4 if mat == "terra" else 0.3)) / SR
    if mat == "terra":
        x = estalo(t, 0.004, r, 50, 500, 0.018, 1.0) + graos(t, 0.006, 0.25, 300, r, 600, 5000, 0.6)
    elif mat == "agua":
        u = np.maximum(t - 0.004, 0)
        x = (
            np.sin(2 * np.pi * np.cumsum(300 + 600 * np.minimum(u / 0.03, 1)) / SR)
            * np.exp(-u / 0.025)
            * (t >= 0.004)
        )
        x = x + estalo(t, 0.004, r, 500, 7000, 0.07, 0.6)
        for _ in range(5):
            at = 0.03 + 0.25 * r.random()
            x += modo(t, at, r.uniform(700, 1800), 0.012, r.uniform(0.1, 0.3))
    elif mat == "madeira":
        x = estalo(t, 0.004, r, 1500, 10000, 0.0012, 1.0)
        x += (
            modo(t, 0.004, 620 * (1 + (r.random() - 0.5) * 0.08), 0.03, 0.6)
            + modo(t, 0.004, 1350, 0.018, 0.4)
            + modo(t, 0.004, 2800, 0.009, 0.3)
        )
        x += graos(t, 0.006, 0.12, 200, r, 2000, 8000, 0.3)
    elif mat == "palha":
        x = graos(t, 0.005, 0.15, 500, r, 1500, 8000, 0.8) + estalo(t, 0.004, r, 60, 500, 0.01, 0.4)
    elif mat == "carne":
        x = (
            estalo(t, 0.004, r, 90, 700, 0.02, 1.0)
            + estalo(t, 0.004, r, 600, 3500, 0.003, 0.5)
            + estalo(t, 0.006, r, 300, 1500, 0.035, 0.2)
        )
    else:
        raise ValueError(mat)
    return bordas(nivel_pico(x, -3.0 - r.random()), 0.3, 15)


def explosao(tipo: str, var: int) -> np.ndarray:
    r = rng_de("explosao", tipo, var)
    if tipo == "eco":  # o estrondo rolando pelo vale, de longe
        dur = 3.0
        n = n_de(dur)
        x = difuso(
            n,
            r,
            [1.6, 1.5, 1.3, 1.0, 0.6, 0.3, 0.15, 0.08],
            [1.0, 1.0, 0.8, 0.5, 0.2, 0.05, 0.0, 0.0],
            0.05,
            0.3,
        )
        x = x / (np.std(x) + 1e-12)
        tempos = sorted(0.4 + r.random() * 2.1 for _ in range(4))
        x += tapas(n, r, tempos, [r.uniform(1.0, 2.0) for _ in tempos], lambda ti: 700)
        return bordas(nivel_pico(banda(x, 30, 900), -3.0), 0.3, 60)
    pesada = tipo == "pesada"
    dur = 4.0 if pesada else 3.0
    n = n_de(dur)
    t = np.arange(n) / SR
    t0 = PRE_S
    u = np.maximum(t - t0, 0)
    on = t >= t0
    T = (12 if pesada else 7) / 1000 * (1 + (r.random() - 0.5) * 0.1)
    fr = banda(friedlander(t, t0, T), 20, 12000)
    blast = banda(
        r.standard_normal(n) * (np.exp(-u / 0.015) + 0.4 * np.exp(-u / 0.12)) * on, 60, 8000
    )
    f0, f1, tb = (48, 24, 0.5) if pesada else (62, 32, 0.28)
    boom = (
        np.sin(2 * np.pi * np.cumsum((f1 + (f0 - f1) * np.exp(-u / 0.05)) * on) / SR)
        * np.exp(-u / tb)
        * on
    )
    sub = banda(r.standard_normal(n) * np.exp(-u / (tb * 1.4)) * on, 20, 150, 3)
    sub /= np.abs(sub).max() + 1e-12
    terra = graos(t, 0.25, 1.6 if pesada else 1.3, 90, r, 400, 4000, 0.25)
    rolo = difuso(
        n,
        r,
        [1.3, 1.2, 1.0, 0.8, 0.55, 0.35, 0.2, 0.1],
        [0.8, 1.0, 1.0, 0.8, 0.5, 0.25, 0.1, 0.03],
        0.05,
        0.1,
    )
    rolo /= np.std(rolo) + 1e-12
    x = (
        nivel_pico(fr, 1.0)
        + nivel_pico(blast, 0.8)
        + boom * 1.2
        + sub * (0.9 if pesada else 0.6)
        + terra
        + rolo * 0.08
    )
    x = x / (np.abs(x).max() + 1e-12)
    x = np.tanh(x * 1.4) / np.tanh(1.4)
    return bordas(nivel_pico(x, -1.0), 0.3, 80)


def pazadas() -> list[tuple[str, np.ndarray, float]]:
    """Quatro pazadas do D-183 com outras sementes: a terra cai diferente, o golpe é o mesmo."""
    import sons_pa

    out = []
    for k in range(1, 5):
        sons_pa.rng = np.random.default_rng(1943 + 101 * k)
        out.append((f"pazada{k}", sons_pa.pa_cavar(), 0.35))
    return out


# ------------------------------------------------------------------ kits
CHAOS = ("grama", "lama", "arrozal", "areia", "madeira")
IMPACTOS = ("terra", "agua", "madeira", "palha", "carne")


def kits() -> dict[str, list[tuple[str, np.ndarray, float]]]:
    out: dict[str, list[tuple[str, np.ndarray, float]]] = {}
    for arma in ARMAS:
        out[f"kit_{arma}"] = kit_arma(arma)
    out["kit_caudas"] = [
        (f"{fam}_{lug}_{v}", cauda(fam, lug, v), 0.0)
        for fam in FAMILIA
        for lug in LUGAR
        for v in (1, 2)
    ]
    out["kit_distancia"] = [
        (f"{fam}_{fx}_{v}", distante(fam, fx, v), PRE_S)
        for fam in FAMILIA
        for fx in ("medio", "longe")
        for v in (1, 2, 3)
    ]
    out["kit_balas"] = [(f"estalo{v}", bala("estalo", v), 0.004) for v in (1, 2, 3)]
    out["kit_balas"] += [(f"zunido{v}", bala("zunido", v), 0.12) for v in (1, 2, 3)]
    out["kit_balas"] += [
        (k, bala(k, 1), 0.002) for k in ("acerto_corpo", "acerto_cabeca", "acerto_abate")
    ]
    out["kit_passos"] = [(f"{c}{v}", passo(c, v), 0.01) for c in CHAOS for v in range(1, 7)]
    out["kit_impactos"] = [(f"{m}{v}", impacto(m, v), 0.004) for m in IMPACTOS for v in range(1, 5)]
    out["kit_explosoes"] = [(f"granada{v}", explosao("granada", v), PRE_S) for v in (1, 2, 3)]
    out["kit_explosoes"] += [(f"pesada{v}", explosao("pesada", v), PRE_S) for v in (1, 2)]
    out["kit_explosoes"] += [(f"eco{v}", explosao("eco", v), 0.05) for v in (1, 2)]
    out["kit_campo"] = pazadas()
    return out


def montar(
    trechos: list[tuple[str, np.ndarray, float]],
) -> tuple[np.ndarray, dict[str, tuple[float, float, float]]]:
    """Junta os trechos com silêncio entre eles; cada um começa num múltiplo de 10 ms."""
    partes: list[np.ndarray] = []
    seg: dict[str, tuple[float, float, float]] = {}
    pos = 0
    passo10 = SR // 100
    gap = np.zeros(n_de(GAP_S))
    for nome, x, anc in trechos:
        assert nome not in seg, nome
        n10 = int(math.ceil(len(x) / passo10)) * passo10
        y = np.zeros(n10)
        y[: len(x)] = x
        seg[nome] = (round(pos / SR, 4), round(len(x) / SR, 4), round(anc, 4))
        partes += [y, gap]
        pos += n10 + len(gap)
    return np.concatenate(partes), seg


def escrever_luau(tabela: dict[str, dict]) -> None:
    linhas = [
        "--!strict",
        "-- GERADO por tools/sons_armas.py (D-204): não edite à mão. Os trechos de cada kit",
        "-- de som (um arquivo OGG por kit, AssetIds.Sounds.<kit>):",
        "--   [nome] = { início (s), duração (s), âncora (s) }.",
        "-- A âncora é o instante dentro do trecho que casa com a animação (o carregador",
        "-- encaixando, o ataque do tiro). Quem toca é o Controllers/Som (PlaybackRegion).",
        "export type Trecho = { number }",
        "export type Kit = { dur: number, seg: { [string]: Trecho } }",
        "local SomKits: { [string]: Kit } = {",
    ]
    for kit, info in tabela.items():
        linhas.append(f"\t{kit} = {{")
        linhas.append(f"\t\tdur = {info['dur']},")
        linhas.append("\t\tseg = {")
        for nome, (a, b, c) in info["seg"].items():
            linhas.append(f"\t\t\t{nome} = {{ {a}, {b}, {c} }},")
        linhas.append("\t\t},")
        linhas.append("\t},")
    linhas += ["}", "", "return SomKits", ""]
    LUAU.write_text("\n".join(linhas), "utf-8", newline="\n")


# ------------------------------------------------------------------ medidas (sem o Blender)
def centroide(x: np.ndarray) -> float:
    X = np.abs(np.fft.rfft(x))
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return float((X * f).sum() / (X.sum() + 1e-12))


def grave(x: np.ndarray) -> float:
    """Fração da energia abaixo de 200 Hz."""
    X = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return float(X[f < 200].sum() / (X.sum() + 1e-12))


def queda40(x: np.ndarray) -> float:
    """Até quando (s) o envelope fica acima de -40 dB do pico."""
    env = np.abs(x)
    lim = env.max() * 10 ** (-40 / 20)
    idx = np.nonzero(env > lim)[0]
    return float(idx[-1] / SR) if len(idx) else 0.0


def medir(tudo: dict[str, list[tuple[str, np.ndarray, float]]]) -> dict:
    med: dict = {"armas": {}, "kits": {}}
    for arma in ARMAS:
        trechos = {k: x for k, x, _ in tudo[f"kit_{arma}"]}
        p = [trechos[f"p{v}"] for v in range(1, 5)]
        e = [trechos[f"e{v}"] for v in range(1, 4)]

        # semelhança entre variações: correlação dos envelopes (1 = iguais)
        def env(x: np.ndarray) -> np.ndarray:
            k = SR // 1000
            return np.abs(x[: len(x) // k * k]).reshape(-1, k).max(axis=1)

        cor = [float(np.corrcoef(env(p[0]), env(p[i]))[0, 1]) for i in (1, 2, 3)]
        med["armas"][arma] = {
            "centroide_hz_p": round(float(np.mean([centroide(x) for x in p]))),
            "centroide_hz_e": round(float(np.mean([centroide(x) for x in e]))),
            "grave_p": round(float(np.mean([grave(x) for x in p])), 3),
            "grave_e": round(float(np.mean([grave(x) for x in e])), 3),
            "ate_40db_s_p": round(float(np.mean([queda40(x) for x in p])), 3),
            "pico_dbfs_max": round(20 * math.log10(max(float(np.abs(x).max()) for x in p + e)), 2),
            "borda_max": round(max(max(abs(float(x[0])), abs(float(x[-1]))) for x in p + e), 5),
            "env_correl_variacoes": [round(c, 3) for c in cor],
        }
    for kit, trechos in tudo.items():
        picos_ = [float(np.abs(x).max()) for _, x, _ in trechos]
        med["kits"][kit] = {
            "trechos": len(trechos),
            "pico_dbfs_max": round(20 * math.log10(max(picos_)), 2),
            "borda_max": round(
                max(max(abs(float(x[0])), abs(float(x[-1]))) for _, x, _ in trechos), 5
            ),
        }
    return med


def espectrograma(x: np.ndarray, caminho: Path, titulo: str) -> None:
    from PIL import Image, ImageDraw

    janela, passo_ = 1024, 256
    if len(x) < janela:
        x = np.pad(x, (0, janela - len(x)))
    w = np.hanning(janela)
    quadros = [
        np.abs(np.fft.rfft(x[i : i + janela] * w)) for i in range(0, len(x) - janela, passo_)
    ]
    S = 20 * np.log10(np.array(quadros).T + 1e-9)
    S = np.clip((S - S.max() + 80) / 80, 0, 1)
    f = np.fft.rfftfreq(janela, 1 / SR)
    # eixo de frequência em log (50 Hz a 16 kHz), 200 linhas
    linhas = np.geomspace(50, 16000, 200)
    idx = np.searchsorted(f, linhas).clip(0, len(f) - 1)
    img = (S[idx][::-1] * 255).astype(np.uint8)
    im = Image.fromarray(img).resize((max(img.shape[1] * 2, 200), 200))
    canvas = Image.new("L", (im.width, 220), 0)
    canvas.paste(im, (0, 20))
    ImageDraw.Draw(canvas).text((4, 3), titulo, fill=255)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(caminho)


def main() -> None:
    medindo = "--medir" in sys.argv
    tudo = kits()
    tabela: dict[str, dict] = {}
    for kit, trechos in tudo.items():
        x, seg = montar(trechos)
        tabela[kit] = {"dur": round(len(x) / SR, 2), "seg": seg}
        if medindo:
            continue
        wav = TRAB / f"{kit}.wav"
        ogg = SAIDA / f"{kit}.ogg"
        base.gravar_wav(wav, x)
        try:
            base.para_ogg(wav, ogg, len(x))
            print("[SOM]", kit, len(trechos), "trechos", base.conferir(ogg, x), flush=True)
        except Exception as e:  # sem bpy/FFmpeg: fica o WAV
            print("[SOM]", kit, "OGG falhou:", e, "- WAV em", wav, flush=True)
    if medindo:
        med = medir(tudo)
        SAIDA.mkdir(parents=True, exist_ok=True)
        (SAIDA / "medidas.json").write_text(json.dumps(med, indent=1, ensure_ascii=False), "utf-8")
        prev = TRAB / "previas"
        for arma in ARMAS:
            x = {k: y for k, y, _ in tudo[f"kit_{arma}"]}
            espectrograma(
                np.concatenate([x["p1"], np.zeros(2000), x["e1"]]),
                prev / f"{arma}.png",
                f"{arma}: p1 | e1",
            )
        for kit in ("kit_caudas", "kit_explosoes", "kit_passos"):
            xs = [y for _, y, _ in tudo[kit]][:8]
            espectrograma(
                np.concatenate([np.concatenate([y, np.zeros(1500)]) for y in xs]),
                prev / f"{kit}.png",
                kit,
            )
        print(json.dumps(med["armas"], indent=1))
    else:
        escrever_luau(tabela)
        print(
            "[LUAU]",
            LUAU.name,
            sum(len(v["seg"]) for v in tabela.values()),
            "trechos em",
            len(tabela),
            "kits",
        )


if __name__ == "__main__":
    main()
