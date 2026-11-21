"""O cenário pintado atrás do pódio (D-221): pôr do sol sobre a mata, com serras em camadas, neblina
e coqueiros em silhueta. Feito aqui, por código (nada de terceiro). O sol fica no meio: atrás do 1º.

Saída: `assets/ui/podio/fundo.png`, 1024 x 576, RGB.

Uso:
    uv run --group arte python tools/podio_fundo.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "assets" / "ui" / "podio" / "fundo.png"
L, A = 2048, 1152
SOL = (0.5, 0.645)

CEU = [
    (0.00, (7, 10, 28)),
    (0.30, (22, 24, 58)),
    (0.46, (62, 40, 76)),
    (0.57, (150, 66, 70)),
    (0.65, (240, 128, 62)),
    (0.71, (255, 190, 104)),
    (1.00, (255, 190, 104)),
]


def rampa(v: np.ndarray, paradas) -> np.ndarray:
    xs = [p[0] for p in paradas]
    return np.stack([np.interp(v, xs, [p[1][c] for p in paradas]) for c in range(3)], axis=-1)


def ruido(rng: np.random.Generator, w: int, h: int, cx: int, cy: int, oitavas: int) -> np.ndarray:
    """Ruído fractal de 0 a 1: grades aleatórias ampliadas e somadas."""
    soma = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    for o in range(oitavas):
        g = rng.random((max(2, cy * 2**o), max(2, cx * 2**o)), np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        soma += np.asarray(im, np.float32) / 255 * amp
        total += amp
        amp *= 0.5
    soma /= total
    return (soma - soma.min()) / (soma.max() - soma.min())


def perfil(rng: np.random.Generator, n: int, ondas: int, oitavas: int) -> np.ndarray:
    return ruido(rng, n, 1, ondas, 1, oitavas)[0] - 0.5


def ceu(rng: np.random.Generator) -> np.ndarray:
    y = np.linspace(0, 1, A, dtype=np.float32)[:, None]
    x = np.linspace(0, 1, L, dtype=np.float32)[None, :]
    img = rampa(np.broadcast_to(y, (A, L)), CEU).astype(np.float32)
    # estrelas só no alto
    est = rng.random((A, L)) > 0.9994
    img[est] += (150 * np.clip(0.42 - y, 0, 0.42) / 0.42 * np.ones((A, L)))[est][:, None]
    # nuvens compridas: acesas por baixo perto do horizonte, roxas no alto
    n = ruido(rng, L, A, 5, 9, 6)
    m = np.clip((n - 0.53) / 0.2, 0, 1) ** 1.4
    m *= np.clip((0.72 - y) / 0.12, 0, 1) * np.clip((y - 0.06) / 0.2, 0, 1)
    luz = np.clip((y - 0.2) / 0.46, 0, 1)
    cor = rampa(luz, [(0, (30, 26, 58)), (0.55, (120, 56, 80)), (1, (255, 150, 86))])
    img = img * (1 - 0.85 * m[..., None]) + cor * 0.85 * m[..., None]
    # sol e o brilho em volta
    asp = L / A
    d = np.sqrt(((x - SOL[0]) * asp) ** 2 + (y - SOL[1]) ** 2)
    img += np.array([255, 150, 70], np.float32) * (0.75 * np.exp(-d / 0.17))[..., None]
    img += np.array([255, 214, 150], np.float32) * (0.65 * np.exp(-((d / 0.07) ** 2)))[..., None]
    disco = np.clip((0.062 - d) / 0.004, 0, 1)
    return img * (1 - disco[..., None]) + np.array([255, 240, 206], np.float32) * disco[..., None]


def serras(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    camadas = [
        (0.625, 0.055, 5, (176, 92, 76)),
        (0.665, 0.06, 7, (118, 62, 66)),
        (0.71, 0.05, 11, (70, 40, 54)),
        (0.755, 0.038, 18, (38, 26, 38)),
    ]
    yy = np.arange(A, dtype=np.float32)[:, None] / A
    for base, amp, ondas, cor in camadas:
        topo = (base + amp * 2.2 * perfil(rng, L, ondas, 6))[None, :]
        masc = np.clip((yy - topo) * A / 2.5, 0, 1)
        c = np.array(cor, np.float32)
        # a neblina clareia o pé de cada serra
        nevoa = np.clip((yy - topo) / 0.075, 0, 1)
        tinta = c[None, None, :] * (1 - 0.34 * nevoa[..., None]) + np.array(
            [236, 142, 92], np.float32
        ) * (0.34 * nevoa[..., None])
        img = img * (1 - masc[..., None]) + tinta * masc[..., None]
    # a copa da mata na frente
    x = np.arange(L, dtype=np.float32)
    copa = 0.815 + 0.018 * 2.2 * perfil(rng, L, 26, 5)
    copa -= 0.013 * np.abs(np.sin(x * 0.021 + 3 * perfil(rng, L, 9, 3)))
    copa -= 0.006 * np.abs(np.sin(x * 0.073 + 5 * perfil(rng, L, 21, 2)))
    masc = np.clip((yy - copa[None, :]) * A / 2.0, 0, 1)
    return img * (1 - masc[..., None]) + np.array([15, 13, 21], np.float32) * masc[..., None]


def folha(base, ang, comp, curva, largura):
    """A palma: arco afinando na ponta, com o lado de baixo serrilhado."""
    cima, baixo = [], []
    n = 26
    for i in range(n + 1):
        u = i / n
        a = ang + curva * u * u
        p = (
            base[0] + comp * u * np.cos(ang + curva * u * u * 0.55),
            base[1] + comp * u * np.sin(ang + curva * u * u * 0.55),
        )
        w = largura * np.sin(np.pi * min(1, u * 1.04)) ** 0.7
        nx, ny = -np.sin(a), np.cos(a)
        dente = 1.9 if i % 2 == 0 else 0.7
        cima.append((p[0] - nx * w * 0.18, p[1] - ny * w * 0.18))
        baixo.append((p[0] + nx * w * dente, p[1] + ny * w * dente))
    return cima + baixo[::-1]


def coqueiro(d: ImageDraw.ImageDraw, x, base, alt, inclina, cor, rng):
    pts = []
    for i in range(25):
        u = i / 24
        pts.append((x + inclina * alt * u * u, base - alt * u))
    for i in range(len(pts) - 1):
        u = i / 24
        e = alt * (0.024 - 0.012 * u)
        (a, b), (c, f) = pts[i], pts[i + 1]
        d.polygon([(a - e, b), (a + e, b), (c + e, f), (c - e, f)], fill=cor)
    topo = pts[-1]
    n = 11
    for k in range(n):
        a = -np.pi + (k + 0.5) * np.pi / n * 1.0 + rng.uniform(-0.1, 0.1)
        lado = 1 if np.cos(a) >= 0 else -1
        comp = alt * rng.uniform(0.34, 0.47)
        d.polygon(folha(topo, a, comp, lado * 1.25, alt * 0.021), fill=cor)
    for k in range(4):
        a = np.pi * (0.16 + 0.22 * k)
        lado = 1 if np.cos(a) >= 0 else -1
        d.polygon(folha(topo, a, alt * 0.25, lado * -0.5, alt * 0.015), fill=cor)


def coqueiros(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    # longe do meio: o 1º fica na frente do sol
    planos = [
        (
            (30, 22, 32),
            [(0.08, 0.86, 0.3, 0.12), (0.27, 0.84, 0.24, -0.1), (0.76, 0.85, 0.26, 0.1)],
        ),
        (
            (10, 9, 15),
            [
                (0.015, 1.0, 0.62, 0.2),
                (0.17, 0.97, 0.45, -0.16),
                (0.86, 0.99, 0.5, 0.14),
                (0.975, 1.0, 0.68, -0.2),
            ],
        ),
    ]
    saida = img
    for cor, lista in planos:
        m = Image.new("L", (L, A), 0)
        d = ImageDraw.Draw(m)
        for fx, fb, fa, inc in lista:
            coqueiro(d, fx * L, fb * A, fa * A, inc, 255, rng)
        a = np.asarray(m.filter(ImageFilter.GaussianBlur(0.9)), np.float32)[..., None] / 255
        saida = saida * (1 - a) + np.array(cor, np.float32) * a
    return saida


def principal():
    rng = np.random.default_rng(1965)
    img = coqueiros(serras(ceu(rng), rng), rng)
    # grão fino: o degradê do céu não vira faixas depois da compressão
    img = img + rng.normal(0, 1.3, img.shape[:2])[..., None]
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    im.resize((1024, 576), Image.LANCZOS).save(SAIDA, optimize=True)
    print("gravado", SAIDA.relative_to(RAIZ), SAIDA.stat().st_size, "bytes")


if __name__ == "__main__":
    principal()
