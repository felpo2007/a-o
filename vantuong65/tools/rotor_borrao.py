"""Textura do disco do rotor girando (D-199): 4 pás borradas e a faixa da ponta, com alfa.

O jogo cola esta imagem (Decal) num disco invisível no cubo do rotor principal e no de cauda e
gira o disco devagar; as pás de verdade somem com a rotação (Shared/RotorVisual). O borrão de
cada pá é simétrico (gaussiano no ângulo): o mesmo decal serve visto de cima e de baixo, e o
sentido de giro não importa.

- opacidade de cada pá cai com o raio (a pá cobre uma fração menor do círculo lá fora);
- a faixa laranja-amarela da ponta (os 6 in de fora, ~1,8% do raio) vira um anel fraco;
- um véu leve no disco todo marca o plano do rotor entre as pás;
- o centro (cubo) fica vazio: a malha do cubo aparece.

Uso:
    uv run python tools/rotor_borrao.py
Saída: assets/rotor/rotor_borrao.png (1024 px, RGBA) e rotor_borrao_previa.png (sobre um fundo).
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image

RAIZ = Path(__file__).resolve().parents[1]
SAIDA = RAIZ / "assets" / "rotor"
PX = 1024
PAS = 4
COR_PA = np.array([46, 48, 41], np.float64)  # #2e3029, a pá escura do modelo
COR_PONTA = np.array([224, 164, 42], np.float64)  # faixa laranja-amarela
LARGURA_GRAUS = 12.0  # desvio do gaussiano de cada pá
FURO = 0.075  # raio do cubo / raio do rotor (0,62 m de 8,5 m)
PONTA = 1.0 - 0.155 / 8.535


def suave(a: np.ndarray, b: float, c: float) -> np.ndarray:
    t = np.clip((a - b) / (c - b), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def gerar() -> np.ndarray:
    ys, xs = np.mgrid[0:PX, 0:PX].astype(np.float64)
    c = (PX - 1) / 2
    dx, dy = (xs - c) / c, (c - ys) / c
    rho = np.hypot(dx, dy)
    th = np.arctan2(dy, dx)
    # distância angular à pá mais perto (4 pás a 90°)
    passo = 2 * math.pi / PAS
    phi = np.abs((th + passo / 2) % passo - passo / 2)
    sig = math.radians(LARGURA_GRAUS)
    banda = np.exp(-0.5 * (phi / sig) ** 2)
    forca = 0.85 * (0.3 / np.maximum(rho, 0.3)) ** 0.5
    a_pa = forca * banda
    # faixa da ponta: anel com um piso (a cor aparece mesmo entre as pás)
    anel = suave(rho, PONTA - 0.006, PONTA) * (1 - suave(rho, 0.992, 0.999))
    a_ponta = anel * (0.06 + 0.22 * banda)
    veu = 0.04 * suave(rho, FURO, FURO + 0.05)
    a = np.maximum(np.maximum(a_pa, veu), a_ponta)
    # sem o cubo no meio e borda lisa
    a *= suave(rho, FURO, FURO + 0.04) * (1 - suave(rho, 0.993, 1.0))
    mistura = np.where(a > 0, a_ponta / np.maximum(a, 1e-6), 0.0)[..., None]
    cor = COR_PA * (1 - mistura) + COR_PONTA * mistura
    img = np.zeros((PX, PX, 4), np.float64)
    img[..., :3] = cor
    img[..., 3] = np.clip(a, 0, 1) * 255
    return img


def previa(img: np.ndarray) -> Image.Image:
    """O disco sobre um fundo de céu e mato, a 100% e a 60% (o jogo deixa mais fraco longe)."""
    h = PX
    fundo = np.zeros((h, 2 * PX, 3), np.float64)
    for y in range(h):
        k = y / h
        fundo[y] = np.array([150, 170, 190]) * (1 - k) + np.array([82, 96, 60]) * k
    out = fundo.copy()
    for i, f in enumerate((1.0, 0.6)):
        a = img[..., 3:4] / 255 * f
        bloco = out[:, i * PX : (i + 1) * PX]
        out[:, i * PX : (i + 1) * PX] = bloco * (1 - a) + img[..., :3] * a
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    img = gerar()
    Image.fromarray(img.clip(0, 255).astype(np.uint8), "RGBA").save(SAIDA / "rotor_borrao.png")
    previa(img).resize((PX, PX // 2)).save(SAIDA / "rotor_borrao_previa.png")
    a = img[..., 3] / 255
    print(
        f"rotor_borrao.png: {PX} px, alfa médio {a.mean():.3f}, máximo {a.max():.3f};"
        f" prévia em {SAIDA.relative_to(RAIZ)}"
    )


if __name__ == "__main__":
    main()
