"""Rostos de época dos soldados de bloco (D-102, formato do Front 44).

Pedido do dono: "faça os personagens do mesmo formato do Front 44". O Front 44 hoje usa o boneco de
bloco do R15, com o rosto em decalque na cabeça de bloco; para os soldados realistas dele
(desligados desde a 0.28.0) o tools/make_faces.py pintava variações (barba, sobrancelha, sujeira,
cicatriz) sobre a textura do rosto. Aqui o mesmo espírito para a cabeça de bloco: cada rosto é um
PNG transparente (o tom da pele vem da cor da cabeça, Corpo.PELE) com olhos, sobrancelhas, nariz,
boca e, em alguns, barba por fazer, bigode, olheira, sujeira de campo ou cicatriz.

Respeito: os dois lados usam a MESMA geometria de olho, nariz e boca (variações naturais de qualquer
rosto: formato do olho, distância, sobrancelha, boca). Nada de caricatura. O que muda entre os
lados é o que a época mostra: fuzileiros de 1965 de todas as origens (cabelo e olhos de várias
cores, alguns com bigode e barba por fazer de campanha) e guerrilheiros do VC jovens, quase sempre
sem barba, cabelo e olhos escuros.

Saídas: assets/rostos/rosto_us_NN.png e rosto_vc_NN.png (512 x 512, decalque da frente da cabeça),
assets/rostos/previa.png (cada rosto em três tons de pele). Os ids publicados vão em
Shared/Corpo.ROSTOS na mesma ordem.

Uso (a partir de vantuong65): uv run python tools/rostos/make_rostos.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

RAIZ = Path(__file__).resolve().parents[2]
SAIDA = RAIZ / "assets" / "rostos"
PX = 512
N = 12  # rostos por lado (Corpo.ROSTOS)
SS = 4  # superamostragem (bordas lisas)

# tons de pele da prévia (Corpo.PELE: claro, médio, escuro)
PREVIA_PELE = {
    "us": [(238, 206, 178), (204, 158, 120), (116, 80, 56)],
    "vc": [(226, 184, 146), (196, 150, 110), (178, 132, 96)],
}
CABELO = {
    "us": [(34, 26, 20), (58, 42, 30), (92, 66, 44), (126, 92, 58), (150, 84, 46), (170, 140, 96)],
    "vc": [(20, 18, 16), (28, 24, 20), (36, 30, 24)],
}
IRIS = {
    "us": [(58, 38, 24), (84, 58, 36), (96, 88, 56), (70, 96, 120), (88, 110, 92)],
    "vc": [(40, 28, 20), (52, 36, 24), (62, 44, 30)],
}


def _rng(lado: str, i: int) -> random.Random:
    return random.Random(f"vt65-rosto-{lado}-{i}")


def _parametros(lado: str, i: int) -> dict:
    r = _rng(lado, i)
    us = lado == "us"
    return {
        "olho_larg": r.uniform(0.085, 0.105),  # meia-largura do olho (fração da face)
        "olho_alt": r.uniform(0.028, 0.040),
        "olho_dist": r.uniform(0.165, 0.19),  # do centro até o centro do olho
        "olho_y": r.uniform(0.40, 0.43),
        "palpebra": r.uniform(
            0.15, 0.45
        ),  # pálpebra de cima cobrindo a íris (cansaço, olhar sério)
        "iris": r.choice(IRIS[lado]),
        "sobr_grossa": r.uniform(0.018, 0.034),
        "sobr_ang": r.uniform(-6, 10),  # graus: positivo = sério (pontas de dentro mais baixas)
        "sobr_alt": r.uniform(0.075, 0.095),
        "cabelo": r.choice(CABELO[lado]),
        "nariz_larg": r.uniform(0.05, 0.075),
        "nariz_y": r.uniform(0.58, 0.62),
        "boca_larg": r.uniform(0.10, 0.14),
        "boca_y": r.uniform(0.71, 0.75),
        "boca_curva": r.uniform(-0.012, 0.006),  # negativo = cantos para baixo (sério)
        "labio": r.uniform(0.008, 0.014),
        "barba": (r.random() < (0.55 if us else 0.12)) and r.uniform(0.25, 0.75) or 0.0,
        "bigode": r.random() < (0.25 if us else 0.12),
        "olheira": r.random() < 0.45,
        "sujeira": r.random() < 0.5 and r.uniform(0.15, 0.45) or 0.0,
        "cicatriz": r.random() < 0.15,
        "semente": r.randint(0, 1 << 30),
    }


def _p(x: float, y: float) -> tuple[float, float]:
    return x * PX * SS, y * PX * SS


def _elipse(d: ImageDraw.ImageDraw, cx: float, cy: float, rx: float, ry: float, fill) -> None:
    a, b = _p(cx - rx, cy - ry)
    c, e = _p(cx + rx, cy + ry)
    d.ellipse([a, b, c, e], fill=fill)


def _olho(img: Image.Image, cx: float, cy: float, k: dict, lado_olho: int) -> None:
    """Olho em amêndoa: branco, íris, pupila, brilho, pálpebra de cima e linha de baixo."""
    w, h = k["olho_larg"], k["olho_alt"]
    camada = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(camada)
    # amêndoa: polígono pelas duas curvas
    pts = []
    for j in range(41):
        t = j / 40
        x = cx - w + 2 * w * t
        y = cy - h * math.sin(math.pi * t) * (1.0 + 0.15 * (t - 0.5) * lado_olho)
        pts.append(_p(x, y))
    for j in range(40, -1, -1):
        t = j / 40
        x = cx - w + 2 * w * t
        y = cy + h * 0.8 * math.sin(math.pi * t)
        pts.append(_p(x, y))
    d.polygon(pts, fill=(236, 230, 220, 255))
    mascara = Image.new("L", img.size, 0)
    ImageDraw.Draw(mascara).polygon(pts, fill=255)
    iris = Image.new("RGBA", img.size, (0, 0, 0, 0))
    di = ImageDraw.Draw(iris)
    ri = h * 1.05
    _elipse(di, cx, cy + h * 0.05, ri, ri, (*k["iris"], 255))
    _elipse(di, cx, cy + h * 0.05, ri * 0.45, ri * 0.45, (14, 12, 10, 255))
    _elipse(di, cx + ri * 0.35, cy - ri * 0.3, ri * 0.18, ri * 0.18, (250, 250, 245, 230))
    camada.paste(
        iris, (0, 0), Image.composite(iris, Image.new("RGBA", img.size), mascara).split()[3]
    )
    # pálpebra de cima (sombra da pele sobre a íris) e o contorno
    dl = ImageDraw.Draw(camada)
    topo = [p for p in pts[:41]]
    cobre = []
    for j in range(41):
        t = j / 40
        x = cx - w + 2 * w * t
        y = cy - h * math.sin(math.pi * t) + 2 * h * k["palpebra"] * math.sin(math.pi * t)
        cobre.append(_p(x, y))
    dl.polygon(topo + cobre[::-1], fill=(60, 40, 30, 90))
    dl.line(topo, fill=(30, 22, 18, 235), width=int(0.008 * PX * SS))
    dl.line(pts[41:], fill=(70, 50, 40, 110), width=int(0.004 * PX * SS))
    img.alpha_composite(camada)


def _sobrancelha(d: ImageDraw.ImageDraw, cx: float, cy: float, k: dict, s: int) -> None:
    w = k["olho_larg"] * 1.25
    ang = math.radians(k["sobr_ang"]) * s
    cor = (*k["cabelo"], 235)
    for j in range(24):
        t = j / 23
        x = cx - w + 2 * w * t
        arco = -0.012 * math.sin(math.pi * t)
        y = cy + arco + (x - cx) * math.tan(ang)
        g = k["sobr_grossa"] * (1.0 - 0.55 * (t if s > 0 else 1 - t))
        _elipse(d, x, y, 0.012, g / 2, cor)


def _boca(d: ImageDraw.ImageDraw, k: dict) -> None:
    w, y0, c = k["boca_larg"], k["boca_y"], k["boca_curva"]
    linha = []
    for j in range(33):
        t = j / 32
        x = 0.5 - w + 2 * w * t
        y = y0 - c * math.cos(math.pi * (t - 0.5)) * 2 + c
        linha.append(_p(x, y))
    d.line(linha, fill=(60, 34, 30, 220), width=int(0.009 * PX * SS))
    # lábio de baixo: sombra curta
    lab = []
    for j in range(21):
        t = j / 20
        x = 0.5 - w * 0.6 + 1.2 * w * t
        y = y0 + k["labio"] + 0.012 * math.sin(math.pi * t)
        lab.append(_p(x, y))
    d.line(lab, fill=(90, 50, 44, 90), width=int(0.012 * PX * SS))


def _nariz(d: ImageDraw.ImageDraw, k: dict) -> None:
    y, w = k["nariz_y"], k["nariz_larg"]
    for s in (-1, 1):
        _elipse(d, 0.5 + s * w * 0.55, y, 0.012, 0.008, (70, 44, 36, 170))
        lado = [
            _p(0.5 + s * w * 0.25, y - 0.12),
            _p(0.5 + s * w * 0.5, y - 0.03),
            _p(0.5 + s * w, y + 0.005),
        ]
        d.line(lado, fill=(90, 60, 50, 70), width=int(0.006 * PX * SS))
    d.line(
        [_p(0.5 - w * 0.4, y + 0.022), _p(0.5 + w * 0.4, y + 0.022)],
        fill=(90, 60, 50, 60),
        width=int(0.006 * PX * SS),
    )


def _barba(img: Image.Image, k: dict) -> None:
    """Barba por fazer: pontos finos na mandíbula, no queixo e acima da boca."""
    r = random.Random(k["semente"])
    camada = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(camada)
    cor = k["cabelo"]
    n = int(9000 * k["barba"])
    for _ in range(n):
        x = r.uniform(0.18, 0.82)
        y = r.uniform(0.62, 0.98)
        # região: mandíbula e queixo, sem as bochechas altas nem o centro do lábio
        dx = abs(x - 0.5)
        # queixo e mandíbula: elipse baixa, mais rala na borda; fora do lábio
        e = ((x - 0.5) / 0.3) ** 2 + ((y - 0.84) / 0.2) ** 2
        if e > 1 or y < 0.64 or (abs(y - k["boca_y"]) < 0.015 and dx < k["boca_larg"]):
            continue
        if r.random() < e * 0.8:
            continue
        a = int(r.uniform(25, 75))
        _elipse(d, x, y, 0.0025, 0.0035, (*cor, a))
    img.alpha_composite(camada.filter(ImageFilter.GaussianBlur(SS * 1.2)))


def _bigode(d: ImageDraw.ImageDraw, k: dict) -> None:
    w, y = k["boca_larg"] * 0.95, k["boca_y"] - 0.035
    pts = []
    for j in range(21):
        t = j / 20
        x = 0.5 - w + 2 * w * t
        pts.append(_p(x, y + 0.012 * abs(t - 0.5) * 2))
    for j in range(20, -1, -1):
        t = j / 20
        x = 0.5 - w + 2 * w * t
        pts.append(_p(x, y - 0.018 + 0.016 * abs(t - 0.5) * 2))
    d.polygon(pts, fill=(*k["cabelo"], 215))


def rosto(lado: str, i: int) -> Image.Image:
    k = _parametros(lado, i)
    img = Image.new("RGBA", (PX * SS, PX * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if k["olheira"]:
        for s in (-1, 1):
            _elipse(
                d,
                0.5 + s * k["olho_dist"],
                k["olho_y"] + 0.045,
                k["olho_larg"] * 0.9,
                0.018,
                (90, 60, 60, 45),
            )
    if k["sujeira"] > 0:
        r = random.Random(k["semente"] + 1)
        suj = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ds = ImageDraw.Draw(suj)
        for _ in range(6):
            _elipse(
                ds,
                r.uniform(0.15, 0.85),
                r.uniform(0.2, 0.95),
                r.uniform(0.04, 0.1),
                r.uniform(0.02, 0.06),
                (70, 56, 40, int(55 * k["sujeira"])),
            )
        img.alpha_composite(suj.filter(ImageFilter.GaussianBlur(SS * 10)))
    if k["barba"] > 0:
        _barba(img, k)
    d = ImageDraw.Draw(img)
    for s in (-1, 1):
        _olho(img, 0.5 + s * k["olho_dist"], k["olho_y"], k, s)
    d = ImageDraw.Draw(img)
    for s in (-1, 1):
        _sobrancelha(d, 0.5 + s * k["olho_dist"], k["olho_y"] - k["sobr_alt"], k, s)
    _nariz(d, k)
    if k["bigode"]:
        _bigode(d, k)
    _boca(d, k)
    if k["cicatriz"]:
        x0 = 0.5 + 0.27 * (1 if k["semente"] % 2 else -1)
        d.line(
            [_p(x0, 0.52), _p(x0 + 0.03, 0.62)], fill=(150, 90, 80, 150), width=int(0.007 * PX * SS)
        )
    return img.resize((PX, PX), Image.LANCZOS)


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    feitos: dict[str, list[Image.Image]] = {}
    for lado in ("us", "vc"):
        feitos[lado] = []
        for i in range(1, N + 1):
            img = rosto(lado, i)
            img.save(SAIDA / f"rosto_{lado}_{i:02d}.png")
            feitos[lado].append(img)
    # prévia: cada rosto num quadrado da cor da pele (como na cabeça de bloco), três tons
    t = 128
    prev = Image.new("RGB", (t * N, t * 6), (40, 40, 40))
    for li, lado in enumerate(("us", "vc")):
        for j, img in enumerate(feitos[lado]):
            peq = img.resize((t, t), Image.LANCZOS)
            for ti, tom in enumerate(PREVIA_PELE[lado]):
                q = Image.new("RGBA", (t, t), (*tom, 255))
                q.alpha_composite(peq)
                prev.paste(q.convert("RGB"), (j * t, (li * 3 + ti) * t))
    prev.save(SAIDA / "previa.png")
    print(f"{2 * N} rostos em {SAIDA}")


if __name__ == "__main__":
    main()
