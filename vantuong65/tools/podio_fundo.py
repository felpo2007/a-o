"""O cenário pintado atrás do pódio (D-221): pôr do sol sobre a mata, com serras em camadas, neblina
e coqueiros em silhueta. Feito aqui, por código (nada de terceiro). O sol fica no meio: atrás do 1º.

Saídas: `assets/ui/podio/fundo.png`, 1024 x 576, RGB, e, com `--horarios` (D-224), a mesma paisagem
em cada hora votável: `assets/ui/horarios/<id>.png`, 768 x 432.

Uso:
    uv run --group arte python tools/podio_fundo.py [--horarios]
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "assets" / "ui" / "podio" / "fundo.png"
L, A = 2048, 1152
SAIDA_HORAS = RAIZ / "assets" / "ui" / "horarios"

POR_DO_SOL = {
    "ceu": [
        (0.00, (7, 10, 28)),
        (0.30, (22, 24, 58)),
        (0.46, (62, 40, 76)),
        (0.57, (150, 66, 70)),
        (0.65, (240, 128, 62)),
        (0.71, (255, 190, 104)),
        (1.00, (255, 190, 104)),
    ],
    "sol": (0.5, 0.645),
    "nuvem": [(0, (30, 26, 58)), (0.55, (120, 56, 80)), (1, (255, 150, 86))],
    "halo": ((255, 150, 70), 0.75, (255, 214, 150), 0.65),
    "disco": ((255, 240, 206), 0.062),
    "estrelas": 150,
    "serras": [(176, 92, 76), (118, 62, 66), (70, 40, 54), (38, 26, 38)],
    "nevoa": (236, 142, 92),
    "copa": (15, 13, 21),
    "coq": [(30, 22, 32), (10, 9, 15)],
}
TEMAS = {
    "manha": {
        "ceu": [
            (0.00, (66, 120, 186)),
            (0.34, (126, 176, 222)),
            (0.54, (206, 216, 214)),
            (0.66, (255, 222, 176)),
            (1.00, (255, 226, 186)),
        ],
        "sol": (0.74, 0.585),
        "nuvem": [(0, (214, 224, 238)), (0.6, (255, 236, 214)), (1, (255, 206, 160))],
        "halo": ((255, 214, 150), 0.5, (255, 246, 220), 0.6),
        "disco": ((255, 252, 236), 0.05),
        "estrelas": 0,
        "serras": [(150, 182, 188), (108, 150, 150), (70, 118, 104), (40, 86, 66)],
        "nevoa": (240, 236, 214),
        "copa": (20, 48, 30),
        "coq": [(28, 62, 40), (14, 34, 22)],
    },
    "meiodia": {
        "ceu": [
            (0.00, (28, 86, 170)),
            (0.36, (62, 138, 216)),
            (0.60, (150, 204, 236)),
            (0.72, (214, 236, 240)),
            (1.00, (214, 236, 240)),
        ],
        "sol": (0.64, 0.1),
        "nuvem": [(0, (232, 240, 248)), (0.6, (255, 255, 255)), (1, (240, 246, 248))],
        "halo": ((255, 248, 220), 0.4, (255, 255, 244), 0.75),
        "disco": ((255, 255, 250), 0.05),
        "estrelas": 0,
        "serras": [(136, 182, 196), (92, 152, 148), (58, 124, 90), (36, 98, 56)],
        "nevoa": (214, 236, 226),
        "copa": (22, 62, 30),
        "coq": [(30, 80, 40), (16, 46, 24)],
    },
    "tarde": POR_DO_SOL,
    "noite": {
        "ceu": [
            (0.00, (4, 6, 18)),
            (0.40, (10, 16, 42)),
            (0.62, (24, 38, 78)),
            (0.72, (44, 62, 108)),
            (1.00, (44, 62, 108)),
        ],
        "sol": (0.7, 0.2),
        "nuvem": [(0, (12, 16, 36)), (0.6, (30, 40, 74)), (1, (58, 74, 118))],
        "halo": ((120, 150, 220), 0.32, (214, 226, 250), 0.5),
        "disco": ((236, 240, 250), 0.045),
        "estrelas": 230,
        "serras": [(42, 58, 102), (30, 42, 80), (20, 30, 60), (12, 20, 42)],
        "nevoa": (86, 108, 160),
        "copa": (6, 9, 20),
        "coq": [(10, 14, 30), (4, 6, 14)],
    },
}
T = POR_DO_SOL


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
    img = rampa(np.broadcast_to(y, (A, L)), T["ceu"]).astype(np.float32)
    # estrelas só no alto
    est = rng.random((A, L)) > 0.9994
    img[est] += (T["estrelas"] * np.clip(0.42 - y, 0, 0.42) / 0.42 * np.ones((A, L)))[est][:, None]
    # nuvens compridas: acesas por baixo perto do horizonte, roxas no alto
    n = ruido(rng, L, A, 5, 9, 6)
    m = np.clip((n - 0.53) / 0.2, 0, 1) ** 1.4
    m *= np.clip((0.72 - y) / 0.12, 0, 1) * np.clip((y - 0.06) / 0.2, 0, 1)
    luz = np.clip((y - 0.2) / 0.46, 0, 1)
    cor = rampa(luz, T["nuvem"])
    img = img * (1 - 0.85 * m[..., None]) + cor * 0.85 * m[..., None]
    # sol e o brilho em volta
    asp = L / A
    sol = T["sol"]
    c1, f1, c2, f2 = T["halo"]
    cor_d, raio = T["disco"]
    d = np.sqrt(((x - sol[0]) * asp) ** 2 + (y - sol[1]) ** 2)
    img += np.array(c1, np.float32) * (f1 * np.exp(-d / 0.17))[..., None]
    img += np.array(c2, np.float32) * (f2 * np.exp(-((d / 0.07) ** 2)))[..., None]
    disco = np.clip((raio - d) / 0.004, 0, 1)
    return img * (1 - disco[..., None]) + np.array(cor_d, np.float32) * disco[..., None]


def serras(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    s = T["serras"]
    camadas = [
        (0.625, 0.055, 5, s[0]),
        (0.665, 0.06, 7, s[1]),
        (0.71, 0.05, 11, s[2]),
        (0.755, 0.038, 18, s[3]),
    ]
    yy = np.arange(A, dtype=np.float32)[:, None] / A
    for base, amp, ondas, cor in camadas:
        topo = (base + amp * 2.2 * perfil(rng, L, ondas, 6))[None, :]
        masc = np.clip((yy - topo) * A / 2.5, 0, 1)
        c = np.array(cor, np.float32)
        # a neblina clareia o pé de cada serra
        nevoa = np.clip((yy - topo) / 0.075, 0, 1)
        tinta = c[None, None, :] * (1 - 0.34 * nevoa[..., None]) + np.array(
            T["nevoa"], np.float32
        ) * (0.34 * nevoa[..., None])
        img = img * (1 - masc[..., None]) + tinta * masc[..., None]
    # a copa da mata na frente
    x = np.arange(L, dtype=np.float32)
    copa = 0.815 + 0.018 * 2.2 * perfil(rng, L, 26, 5)
    copa -= 0.013 * np.abs(np.sin(x * 0.021 + 3 * perfil(rng, L, 9, 3)))
    copa -= 0.006 * np.abs(np.sin(x * 0.073 + 5 * perfil(rng, L, 21, 2)))
    masc = np.clip((yy - copa[None, :]) * A / 2.0, 0, 1)
    return img * (1 - masc[..., None]) + np.array(T["copa"], np.float32) * masc[..., None]


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
            T["coq"][0],
            [(0.08, 0.86, 0.3, 0.12), (0.27, 0.84, 0.24, -0.1), (0.76, 0.85, 0.26, 0.1)],
        ),
        (
            T["coq"][1],
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


def pinta(tema: dict, saida: Path, tam: tuple[int, int]):
    global T
    T = tema
    rng = np.random.default_rng(1965)
    img = coqueiros(serras(ceu(rng), rng), rng)
    # grão fino: o degradê do céu não vira faixas depois da compressão
    img = img + rng.normal(0, 1.3, img.shape[:2])[..., None]
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    saida.parent.mkdir(parents=True, exist_ok=True)
    im.resize(tam, Image.LANCZOS).save(saida, optimize=True)
    print("gravado", saida.relative_to(RAIZ), saida.stat().st_size, "bytes")


def principal():
    if "--horarios" in sys.argv:
        for nome, tema in TEMAS.items():
            pinta(tema, SAIDA_HORAS / f"{nome}.png", (768, 432))
        return
    pinta(POR_DO_SOL, SAIDA, (1024, 576))


if __name__ == "__main__":
    principal()
