"""Texturas dos efeitos de interface (D-213, pedido do dono de 20/11: "animação perfeita e realista
com efeitos visuais para a loja e para a abertura das caixas").

Brancas com o alfa desenhado; a tela pinta cada uma com `ImageColor3` (a cor da caixa ou da
raridade). Todas saem de fórmulas aqui (nada de terceiro):
- brilho.png (128): luz redonda e macia (gaussiana), para o halo e o miolo das faíscas;
- faisca.png (128 x 32): rastro de faísca, cabeça forte à direita e cauda sumindo à esquerda;
- raio.png (512 x 128): raio de luz em cunha, forte no meio e sumindo para as pontas (gira em volta
  do meio: cada imagem dá dois raios opostos);
- anel.png (256): anel macio da onda de choque;
- cintila.png (128): cintilação de quatro pontas (o brilho que pisca no metal).

Saída: assets/ui/efeitos/<nome>.png. Uso: uv run --group arte python tools/efeitos_ui.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

RAIZ = Path(__file__).resolve().parents[1]
SAIDA = RAIZ / "assets" / "ui" / "efeitos"


def grade(w: int, h: int) -> tuple[np.ndarray, np.ndarray]:
    """Coordenadas de -1 a 1 no centro de cada pixel."""
    x = (np.arange(w) + 0.5) / w * 2 - 1
    y = (np.arange(h) + 0.5) / h * 2 - 1
    return np.meshgrid(x, y)


def grava(nome: str, alfa: np.ndarray) -> Path:
    a = np.clip(alfa, 0, 1)
    rgba = np.zeros((*a.shape, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(a * 255).astype(np.uint8)
    SAIDA.mkdir(parents=True, exist_ok=True)
    p = SAIDA / f"{nome}.png"
    Image.fromarray(rgba, "RGBA").save(p)
    return p


def brilho() -> np.ndarray:
    x, y = grade(128, 128)
    r2 = x * x + y * y
    # gaussiana com a borda indo a zero (sem degrau no quadrado)
    return np.exp(-r2 * 4.5) * np.clip(1 - r2, 0, 1)


def faisca() -> np.ndarray:
    x, y = grade(128, 32)
    u = (x + 1) / 2  # 0 na cauda, 1 na cabeça
    largura = 0.12 + 0.55 * u**2
    corpo = np.exp(-((y / largura) ** 2) * 2.2) * u**1.6
    cabeca = np.exp(-(((x - 0.82) / 0.16) ** 2 + (y / 0.55) ** 2) * 2.0)
    return np.maximum(corpo, cabeca) * np.clip((1 - x) * 12, 0, 1)


def raio() -> np.ndarray:
    x, y = grade(512, 128)
    ax = np.abs(x)
    largura = 0.06 + 0.9 * ax  # cunha: fina no meio, larga nas pontas
    perfil = np.exp(-((y / largura) ** 2) * 2.5)
    return perfil * (1 - ax) ** 1.6 * np.clip(ax * 6, 0, 1) ** 0.5


def anel() -> np.ndarray:
    x, y = grade(256, 256)
    r = np.sqrt(x * x + y * y)
    return np.exp(-(((r - 0.84) / 0.07) ** 2)) + 0.25 * np.exp(-(((r - 0.78) / 0.16) ** 2))


def cintila() -> np.ndarray:
    x, y = grade(128, 128)
    bracos = np.maximum(
        np.exp(-((x / 0.035) ** 2) - (y / 0.75) ** 2 * 3),
        np.exp(-((y / 0.035) ** 2) - (x / 0.75) ** 2 * 3),
    )
    miolo = np.exp(-(x * x + y * y) * 30)
    halo = 0.35 * np.exp(-(x * x + y * y) * 7)
    return (bracos + miolo + halo) * np.clip(1 - (x * x + y * y), 0, 1)


EFEITOS = {"brilho": brilho, "faisca": faisca, "raio": raio, "anel": anel, "cintila": cintila}


def main() -> None:
    for nome, f in EFEITOS.items():
        a = f()
        p = grava(nome, a)
        tam = f"{a.shape[1]}x{a.shape[0]}"
        print(f"[EFEITO] {nome}: {tam}, alfa máx {a.max():.2f}, {p.stat().st_size} B")


if __name__ == "__main__":
    main()
