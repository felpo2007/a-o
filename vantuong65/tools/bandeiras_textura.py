"""Texturas das bandeiras da escolha de lado (lote 19, D-133; pedido do dono: "para escolher o lado
quero a bandeira de cada país esticada sobre a mesa, bem detalhadas e texturizadas").

Uso: `uv run --group arte python tools/bandeiras_textura.py`
Saídas em `assets/bandeiras/`: `bandeira_eua.png` (1023 x 522: 1,9:1 mais a lona do mastro) e
`bandeira_frente.png` (1024 x 683, 3:2), desenhadas a 2x e reduzidas (borda limpa). O Roblox
reduz imagem a 1024 px de lado; por isso este tamanho. Também `testes/conferencia_bandeiras.png`,
as duas lado a lado.

Geometria:
- EUA (Executive Order 10834, 1959, a bandeira de 1965): altura 1, comprimento 1,9; 13 listras
  (7 vermelhas, começando e acabando no vermelho); cantão de 7/13 da altura e 0,76 de comprimento;
  50 estrelas de diâmetro 0,0616 em 9 fileiras alternadas de 6 e 5 (espaços E = cantão/10 e
  H = 0,76/12). Cores Old Glory (vermelho 178,34,52; azul 60,59,110).
- Frente Nacional de Libertação do Vietnã do Sul (1960): 2:3, metade de cima vermelha, de baixo
  azul, estrela amarela de cinco pontas no meio com o raio do círculo de 3/10 da altura (a mesma
  proporção da estrela da bandeira do Vietnã).

Pano (o que dá a "textura"):
- trama de algodão (fio cruzado fino) e grão de fibra;
- listras e metades costuradas: costura escura entre elas; estrelas bordadas (borda em relevo);
- vincos da bandeira guardada dobrada (uma grade de dobras, com sombra e brilho de cada lado);
- bainha nas bordas; nos EUA, a tira de lona do lado do mastro com dois ilhoses de latão;
- desgaste leve: manchas de poeira e o sol desbotando um pouco.
Cores e desgaste são de olho (PLACEHOLDER até a foto).
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RAIZ = Path(__file__).resolve().parents[1]
SAIDA = RAIZ / "assets" / "bandeiras"
CONF = RAIZ / "testes" / "conferencia_bandeiras.png"
K = 2  # supersample
rng = np.random.default_rng(1965818)

US_RED = (178, 34, 52)
US_WHITE = (238, 234, 222)  # algodão, não branco puro
US_BLUE = (60, 59, 110)
NLF_RED = (206, 38, 30)
NLF_BLUE = (20, 140, 205)
NLF_STAR = (250, 214, 30)


def estrela(cx: float, cy: float, r: float, rot: float = -math.pi / 2) -> list[tuple[float, float]]:
    """Polígono de estrela de cinco pontas (ponta para cima), raio de fora r."""
    ri = r * math.sin(math.radians(18)) / math.sin(math.radians(54))  # 0,382 r
    pts = []
    for i in range(10):
        a = rot + i * math.pi / 5
        rr = r if i % 2 == 0 else ri
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def ruido_suave(h: int, w: int, celula: int, seed: int) -> np.ndarray:
    g = (
        np.random.default_rng(seed)
        .normal(0, 1, (h // celula + 3, w // celula + 3))
        .astype(np.float32)
    )
    im = Image.fromarray(g, "F").resize((w + 3 * celula, h + 3 * celula), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32)[celula : celula + h, celula : celula + w]


def pano(img: Image.Image, dobras: tuple[int, int], seed: int, borda_mastro: bool) -> Image.Image:
    """Trama, vincos da dobra, bainha, poeira e sol sobre a arte lisa."""
    a = np.asarray(img, dtype=np.float32) / 255
    h, w = a.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    # trama: fio cruzado (período ~3 px na imagem final) e grão de fibra
    per = 3.0 * K
    trama = 0.035 * np.sin(2 * np.pi * x / per) * np.sin(2 * np.pi * y / per)
    trama += 0.025 * np.random.default_rng(seed).normal(0, 1, (h, w)).astype(np.float32)
    trama += 0.02 * ruido_suave(h, w, 2 * K, seed + 1)
    luz = 1 + trama
    # vincos: grade de dobras (nx colunas, ny linhas); cada um, um vale escuro com brilho ao lado
    nx, ny = dobras
    largura = 5.0 * K
    for i in range(1, nx):
        cx = w * i / nx + ruido_suave(h, 1, 40 * K, seed + 10 + i)[:, 0:1] * 3 * K
        d = (x - cx) / largura
        luz -= 0.10 * np.exp(-(d**2)) - 0.05 * np.exp(-((d - 1.4) ** 2))
    for j in range(1, ny):
        cy = h * j / ny + ruido_suave(1, w, 40 * K, seed + 20 + j)[0:1, :] * 3 * K
        d = (y - cy) / largura
        luz -= 0.08 * np.exp(-(d**2)) - 0.04 * np.exp(-((d - 1.4) ** 2))
    # ondulação leve do pano esticado
    luz += 0.035 * ruido_suave(h, w, 90 * K, seed + 3)
    # bainha: faixa de 1,2% nas bordas, costurada (mais escura e com o pesponto)
    b = int(0.012 * h)
    hem = np.zeros((h, w), np.float32)
    hem[:b, :] = hem[-b:, :] = 1
    hem[:, -b:] = 1
    if not borda_mastro:
        hem[:, :b] = 1
    luz -= 0.07 * hem
    # poeira e sol: manchas largas mais claras e acinzentadas
    poeira = np.clip(ruido_suave(h, w, 140 * K, seed + 4), 0, None)
    out = a * luz[..., None]
    cinza = out.mean(axis=2, keepdims=True)
    k = (0.12 + 0.18 * poeira)[..., None]
    out = out * (1 - k) + (cinza * 0.9 + 0.08) * k
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGB")


def costura(
    d: ImageDraw.ImageDraw, pts: list[tuple[float, float]], cor: tuple[int, int, int], larg: float
):
    d.line(pts, fill=cor, width=max(1, int(larg)))


def bandeira_eua() -> Image.Image:
    H = 522 * K  # com a lona, 1.023 px de largura (o Roblox reduz acima de 1.024)
    W = int(round(H * 1.9))
    lona = int(0.06 * H)  # tira de lona do mastro (fora da proporção da bandeira)
    img = Image.new("RGB", (W + lona, H), US_WHITE)
    d = ImageDraw.Draw(img)
    x0 = lona
    faixa = H / 13
    for i in range(13):
        if i % 2 == 0:
            d.rectangle([x0, i * faixa, x0 + W, (i + 1) * faixa], fill=US_RED)
    # costura entre as listras
    for i in range(1, 13):
        costura(d, [(x0, i * faixa), (x0 + W, i * faixa)], (120, 30, 38), 1.2 * K)
    ch, cw = 7 * faixa, 0.76 * H
    d.rectangle([x0, 0, x0 + cw, ch], fill=US_BLUE)
    costura(d, [(x0 + cw, 0), (x0 + cw, ch), (x0, ch)], (40, 38, 70), 1.2 * K)
    # 50 estrelas (bordadas: sombra fina embaixo à direita e o corpo claro)
    E, Hs = ch / 10, cw / 12
    r = 0.0616 * H / 2
    for row in range(1, 10):
        seis = row % 2 == 1
        for k in range(1, (6 if seis else 5) + 1):
            col = 2 * k - 1 if seis else 2 * k
            cx, cy = x0 + col * Hs, row * E
            d.polygon(estrela(cx + 0.6 * K, cy + 0.8 * K, r), fill=(36, 34, 64))
            d.polygon(estrela(cx, cy, r), fill=(232, 228, 214))
    # lona do mastro com dois ilhoses de latão
    d.rectangle([0, 0, lona, H], fill=(196, 186, 156))
    costura(d, [(lona, 0), (lona, H)], (120, 110, 88), 1.5 * K)
    for fy in (0.08, 0.92):
        cy = fy * H
        rr = 0.018 * H
        d.ellipse([lona / 2 - rr, cy - rr, lona / 2 + rr, cy + rr], fill=(150, 120, 60))
        d.ellipse(
            [lona / 2 - rr * 0.5, cy - rr * 0.5, lona / 2 + rr * 0.5, cy + rr * 0.5],
            fill=(40, 34, 26),
        )
    img = pano(img, (4, 2), 501, True)
    return img.resize(((W + lona) // K, H // K), Image.LANCZOS)


def bandeira_frente() -> Image.Image:
    H = 683 * K
    W = int(round(H * 1.5))
    img = Image.new("RGB", (W, H), NLF_RED)
    d = ImageDraw.Draw(img)
    d.rectangle([0, H / 2, W, H], fill=NLF_BLUE)
    costura(d, [(0, H / 2), (W, H / 2)], (60, 40, 60), 1.4 * K)
    r = 0.3 * H
    cx, cy = W / 2, H / 2
    # estrela aplicada: sombra, corpo e o pesponto da borda
    d.polygon(estrela(cx + 1.5 * K, cy + 2 * K, r), fill=(90, 40, 30))
    d.polygon(estrela(cx, cy, r), fill=NLF_STAR)
    pts = estrela(cx, cy, r * 0.965)
    pts.append(pts[0])
    d.line(pts, fill=(196, 156, 20), width=int(1.2 * K))
    img = img.filter(ImageFilter.GaussianBlur(0.4 * K))  # a borda do pano não é vetor
    img = pano(img, (3, 2), 777, False)
    return img.resize((W // K, H // K), Image.LANCZOS)


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    eua, frente = bandeira_eua(), bandeira_frente()
    eua.save(SAIDA / "bandeira_eua.png", optimize=True)
    frente.save(SAIDA / "bandeira_frente.png", optimize=True)
    print("ok", SAIDA / "bandeira_eua.png", eua.size)
    print("ok", SAIDA / "bandeira_frente.png", frente.size)
    pad = 24
    conf = Image.new(
        "RGB",
        (eua.width + frente.width + 3 * pad, max(eua.height, frente.height) + 2 * pad),
        (40, 42, 36),
    )
    conf.paste(eua, (pad, pad))
    conf.paste(frente, (eua.width + 2 * pad, pad))
    conf.save(CONF, optimize=True)
    print("ok", CONF)


if __name__ == "__main__":
    main()
