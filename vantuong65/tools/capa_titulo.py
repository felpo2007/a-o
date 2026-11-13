"""Título da capa: "STARLITE" grande e "VIETNÃ 1965" menor, em letras de estêncil militar, sobre a
capa com espaço à esquerda (e, se couber legível, sobre o ícone).

Fonte: Oswald Bold (Vernon Adams, Kalapi Gajjar, Cyreal), SIL Open Font License 1.1 — condensada e
forte. O arquivo não vai para o repositório: o script usa a cópia que o Roblox instala em
`%LOCALAPPDATA%\\Roblox\\Versions\\*\\content\\fonts\\Oswald-Bold.ttf` (ou `--fonte <ttf>`). A OFL
permite usar a fonte para fazer imagens; a imagem não fica sob a OFL.

O estêncil é feito aqui, letra a letra, sobre a máscara da Oswald:
- todo miolo fechado (A, R, Ã, 9, 6) ganha uma ponte: corte vertical do miolo até a borda
  mais perto;
- E: corte entre a haste e os braços; T: entre a barra e a haste; V: no vértice de baixo;
  S e 5: um corte que separa as duas metades. O N fica inteiro (com cortes lia como H).
A tinta é creme gasta (falhas por ruído), com sombra escura difusa atrás para ler sobre a foto.

Uso:
    uv run python tools/capa_titulo.py                  # capa_titulo_1920x1080.png
    uv run python tools/capa_titulo.py --icone          # icone_titulo_512.png (+ prévia de 150 px)
"""

from __future__ import annotations

import argparse
import glob
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

RAIZ = Path(__file__).resolve().parents[1]
CAPA = RAIZ / "assets" / "capa"
TINTA = (236, 226, 200)
SOMBRA = (12, 10, 8)


def achar_fonte(arg: str | None) -> Path:
    if arg:
        return Path(arg)
    base = os.environ.get("LOCALAPPDATA", "")
    achados = sorted(
        glob.glob(
            os.path.join(base, "Roblox", "Versions", "*", "content", "fonts", "Oswald-Bold.ttf")
        ),
        key=os.path.getmtime,
    )
    if not achados:
        raise SystemExit("Oswald-Bold.ttf não encontrada; passe --fonte <caminho>")
    return Path(achados[-1])


def glifo(
    fonte: ImageFont.FreeTypeFont, ch: str, esc: int = 1
) -> tuple[np.ndarray, tuple[int, int]]:
    """Máscara (bool) do caractere e o deslocamento (x, y) do canto da caixa."""
    x0, y0, x1, y1 = fonte.getbbox(ch)
    w, h = x1 - x0 + 4, y1 - y0 + 4
    im = Image.new("L", (w, h), 0)
    ImageDraw.Draw(im).text((2 - x0, 2 - y0), ch, font=fonte, fill=255)
    return np.array(im) > 127, (x0 - 2, y0 - 2)


def hastes(m: np.ndarray, limiar=0.82) -> list[tuple[int, int]]:
    """Colunas contínuas cheias em mais de `limiar` da altura do corpo da letra."""
    linhas = np.where(m.any(axis=1))[0]
    alt = linhas.max() - linhas.min() + 1
    frac = m.sum(axis=0) / alt
    cols = np.where(frac > limiar)[0]
    runs = []
    for c in cols:
        if runs and c == runs[-1][1] + 1:
            runs[-1][1] = c
        else:
            runs.append([c, c])
    return [tuple(r) for r in runs]


def estencil(m: np.ndarray, ch: str, g: int) -> np.ndarray:
    """Abre as pontes de estêncil na máscara `m` do caractere `ch` (corte de `g` px)."""
    m = m.copy()
    rows = np.where(m.any(axis=1))[0]
    if len(rows) == 0:
        return m
    top, bot = rows.min(), rows.max()
    alt = bot - top + 1
    # miolos fechados: fundo que não toca a borda
    fundo, n = ndimage.label(~m)
    borda = set(np.unique(np.concatenate([fundo[0], fundo[-1], fundo[:, 0], fundo[:, -1]])))
    for k in range(1, n + 1):
        if k in borda:
            continue
        ys, xs = np.where(fundo == k)
        if len(ys) < 6:
            continue
        cx = int(round(xs.mean()))
        cols = slice(max(0, cx - g // 2), cx - g // 2 + g)
        col = fundo[:, cx] == k
        if not col.any():
            continue
        y_cima, y_baixo = np.where(col)[0].min(), np.where(col)[0].max()
        # espessura do traço até a borda, para cima e para baixo do miolo
        e_cima = 0
        while y_cima - 1 - e_cima >= 0 and m[y_cima - 1 - e_cima, cx]:
            e_cima += 1
        e_baixo = 0
        while y_baixo + 1 + e_baixo < m.shape[0] and m[y_baixo + 1 + e_baixo, cx]:
            e_baixo += 1
        if e_cima <= e_baixo:
            m[y_cima - e_cima : y_cima, cols] = False
        else:
            m[y_baixo + 1 : y_baixo + 1 + e_baixo, cols] = False
    up = ch.upper()
    hs = hastes(m)
    if up == "E" and hs:
        # no L o corte lia como "I." (testado): só o E ganha a ponte entre haste e braços
        a, b = hs[0]
        m[:, b + 1 : b + 1 + max(2, int(g * 0.7))] = False
    elif up == "T" and hs:
        a, b = max(hs, key=lambda r: r[1] - r[0])
        larg = m.shape[1]
        cheias = np.where(m.sum(axis=1) > 0.7 * larg)[0]
        if len(cheias):
            yb = cheias.max()
            m[yb + 1 : yb + 1 + g, a : b + 1] = False
    elif up == "V":
        cx = m.shape[1] // 2
        m[top + int(alt * 0.62) : bot + 1, cx - g // 2 : cx - g // 2 + g] = False
    elif up in ("S", "5"):
        cx = m.shape[1] // 2 + (0 if up == "S" else -m.shape[1] // 6)
        m[top : top + int(alt * 0.36), cx - g // 2 : cx - g // 2 + g] = False
        m[
            top + int(alt * 0.64) : bot + 1,
            cx - g // 2 + (0 if up == "S" else m.shape[1] // 3) : cx
            - g // 2
            + g
            + (0 if up == "S" else m.shape[1] // 3),
        ] = False
    return m


def linha(texto: str, fonte: ImageFont.FreeTypeFont, espaco: float, g: int) -> np.ndarray:
    """Máscara de uma linha de texto (estêncil por letra), com `espaco` × altura entre letras."""
    pecas = []
    for ch in texto:
        if ch == " ":
            pecas.append((None, fonte.getlength(" ")))
            continue
        m, (dx, dy) = glifo(fonte, ch)
        pecas.append(((estencil(m, ch, g), dx, dy), fonte.getlength(ch)))
    asc, desc = fonte.getmetrics()
    alt = asc + desc + 8
    larg = int(sum(av for _, av in pecas) + espaco * asc * (len(texto) - 1) + 20)
    out = np.zeros((alt, larg), bool)
    x = 10.0
    for p, av in pecas:
        if p is not None:
            m, dx, dy = p
            xi, yi = int(round(x + dx)), int(dy) + 4
            h, w = m.shape
            out[yi : yi + h, xi : xi + w] |= m
        x += av + espaco * asc
    ys, xs = np.where(out)
    return out[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]


def gasto(m: np.ndarray, sem: int, forca: float) -> np.ndarray:
    """Tinta gasta: falhas por ruído (manchas maiores e pontinhos), só dentro das letras."""
    rng = np.random.default_rng(sem)
    h, w = m.shape
    r1 = ndimage.gaussian_filter(rng.random((h, w)), max(2.0, h / 40))
    r2 = ndimage.gaussian_filter(rng.random((h, w)), 1.0)
    r1 = (r1 - r1.mean()) / (r1.std() + 1e-6)
    r2 = (r2 - r2.mean()) / (r2.std() + 1e-6)
    falha = (r1 > 2.2 - forca) | (r2 > 2.9 - forca)
    alfa = m.astype(np.float32) * np.where(falha, 0.25, 1.0)
    return alfa


def compor(
    base: Image.Image,
    blocos: list[tuple[np.ndarray, int, int]],
    escurecer_esq: float,
    escurecer_topo: float = 0.0,
) -> Image.Image:
    img = base.convert("RGB").copy()
    W, H = img.size
    arr = np.asarray(img).astype(np.float32) / 255.0
    if escurecer_esq > 0:
        x = np.linspace(0, 1, W)[None, :, None]
        grad = np.clip(1 - x / 0.55, 0, 1) ** 1.5 * escurecer_esq
        arr = arr * (1 - grad)
    if escurecer_topo > 0:
        y = np.linspace(0, 1, H)[:, None, None]
        arr = arr * (1 - np.clip(1 - y / 0.42, 0, 1) ** 1.3 * escurecer_topo)
    sombra = np.zeros((H, W), np.float32)
    tinta = np.zeros((H, W), np.float32)
    for alfa, x0, y0 in blocos:
        h, w = alfa.shape
        tinta[y0 : y0 + h, x0 : x0 + w] = np.maximum(tinta[y0 : y0 + h, x0 : x0 + w], alfa)
        sombra[y0 : y0 + h, x0 : x0 + w] = np.maximum(
            sombra[y0 : y0 + h, x0 : x0 + w], (alfa > 0).astype(np.float32)
        )
    raio = max(2.0, H / 140)
    s = (
        ndimage.gaussian_filter(
            np.roll(np.roll(sombra, int(raio * 0.6), 0), int(raio * 0.4), 1), raio
        )
        * 0.85
    )
    arr = arr * (1 - s[..., None]) + np.array(SOMBRA, np.float32)[None, None] / 255 * s[..., None]
    t = ndimage.gaussian_filter(tinta, 0.6)
    arr = arr * (1 - t[..., None]) + np.array(TINTA, np.float32)[None, None] / 255 * t[..., None]
    return Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8))


def bloco_titulo(fonte_path: Path, larg_alvo: int, sem: int, g_frac=0.055, sub_frac=0.36):
    """Máscaras de "STARLITE" (largura `larg_alvo`) e "VIETNÃ 1965" (mesma largura)."""
    tam = 200
    for _ in range(12):
        f = ImageFont.truetype(str(fonte_path), tam)
        g = max(2, int(tam * g_frac))
        m1 = linha("STARLITE", f, 0.045, g)
        tam = int(tam * larg_alvo / m1.shape[1])
    f = ImageFont.truetype(str(fonte_path), tam)
    m1 = linha("STARLITE", f, 0.045, max(2, int(tam * g_frac)))
    t2 = max(10, int(tam * sub_frac))
    esp = 0.25
    for _ in range(12):
        f2 = ImageFont.truetype(str(fonte_path), t2)
        m2 = linha("VIETNÃ 1965", f2, esp, max(2, int(t2 * g_frac)))
        if abs(m2.shape[1] - m1.shape[1]) < 3:
            break
        esp *= m1.shape[1] / m2.shape[1] * 1.0 + (0.0 if m2.shape[1] < m1.shape[1] else -0.02)
        esp = max(0.02, esp)
    return gasto(m1, sem, 0.35), gasto(m2, sem + 1, 0.25), tam


BRUTO = RAIZ / "assets" / "blender" / "_trabalho" / "capa"


def graduar(img: Image.Image, vinheta=0.28, contraste=0.22, sat=1.12, tons=True) -> Image.Image:
    """Graduação de fim de tarde: curva em S suave, realces puxados para o âmbar e sombras para o
    azul-esverdeado, saturação um pouco maior e vinheta."""
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    s = 0.5 + (a - 0.5) * (1 + contraste) - contraste * 0.5 * np.sin(2 * np.pi * (a - 0.5)) / np.pi
    cinza = (s @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
    s = cinza + (s - cinza) * sat
    alto = np.clip((lum - 0.45) / 0.55, 0, 1)[..., None]
    baixo = np.clip((0.45 - lum) / 0.45, 0, 1)[..., None]
    if tons:
        s = (
            s
            * (1 + alto * np.array([0.05, 0.0, -0.08], np.float32))
            * (1 + baixo * np.array([-0.06, 0.0, 0.05], np.float32))
        )
    H, W = lum.shape
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2) / np.sqrt(2)
    s = s * (1 - vinheta * np.clip(r - 0.35, 0, 1) ** 1.6 / 0.65**1.6)[..., None]
    return Image.fromarray(np.clip(s * 255, 0, 255).astype(np.uint8))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--icone", action="store_true")
    ap.add_argument(
        "--graduar", action="store_true", help="gradua os renders brutos para assets/capa"
    )
    ap.add_argument("--fonte", default=None)
    ap.add_argument(
        "--base", default=None, help="imagem de fundo (padrão: a capa/ícone com espaço)"
    )
    ap.add_argument("--saida", default=None)
    a = ap.parse_args()
    if a.graduar:
        CAPA.mkdir(parents=True, exist_ok=True)
        larga = BRUTO / "capa_larga.png"
        if larga.is_file():
            # render único 2304 x 1080 (capa.py ambas): a capa é o recorte da direita e a versão
            # com espaço para o título é o da esquerda (câmera deslocada 20% do quadro)
            im = graduar(Image.open(larga), vinheta=0.0)
            W, H = im.size
            for nome, x0 in (
                ("capa_1920x1080.png", W - 1920),
                ("capa_espaco_titulo_1920x1080.png", 0),
            ):
                graduar(
                    im.crop((x0, 0, x0 + 1920, H)), vinheta=0.28, contraste=0.0, sat=1.0, tons=False
                ).save(CAPA / nome)
                print("[titulo] recortado e graduado", CAPA / nome)
        for nome in ("capa_1920x1080.png", "capa_espaco_titulo_1920x1080.png", "icone_512.png"):
            src = BRUTO / nome
            if src.is_file():
                graduar(Image.open(src), vinheta=0.2 if "icone" in nome else 0.28).save(CAPA / nome)
                print("[titulo] graduado", CAPA / nome)
        return
    fonte = achar_fonte(a.fonte)
    print("[titulo] fonte:", fonte)
    if not a.icone:
        base = Image.open(a.base or (CAPA / "capa_espaco_titulo_1920x1080.png"))
        W, H = base.size
        m1, m2, tam = bloco_titulo(fonte, int(W * 0.36), 65)
        x0 = int(W * 0.055)
        gap = int(m1.shape[0] * 0.16)
        y0 = int(H * 0.1)
        img = compor(base, [(m1, x0, y0), (m2, x0, y0 + m1.shape[0] + gap)], 0.35)
        saida = Path(a.saida) if a.saida else CAPA / "capa_titulo_1920x1080.png"
        img.save(saida)
        print("[titulo] ok", saida, "corpo", tam, "px")
        return
    base = Image.open(a.base or (CAPA / "icone_512.png"))
    W, H = base.size
    m1, m2, tam = bloco_titulo(fonte, int(W * 0.88), 66, sub_frac=0.5)
    x0 = (W - m1.shape[1]) // 2
    gap = int(m1.shape[0] * 0.12)
    y0 = int(H * 0.035)
    img = compor(base, [(m1, x0, y0), (m2, x0, y0 + m1.shape[0] + gap)], 0.0, escurecer_topo=0.62)
    saida = Path(a.saida) if a.saida else CAPA / "icone_titulo_512.png"
    img.save(saida)
    img.resize((150, 150), Image.LANCZOS).save(
        CAPA.parent / "blender" / "_trabalho" / "icone_titulo_150_conferencia.png"
    )
    print(
        "[titulo] ok",
        saida,
        "corpo",
        tam,
        "px; altura STARLITE",
        m1.shape[0],
        "px; VIETNÃ 1965",
        m2.shape[0],
        "px",
    )


if __name__ == "__main__":
    main()
