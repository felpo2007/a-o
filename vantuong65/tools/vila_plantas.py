"""Coqueiros e árvores do setor piloto da Vila (D-255), em cartões recortados por alfa.

A copa fina vem da textura, não da malha: cada folha de coqueiro é uma tira dobrada e cada
massa de folhas é um cartão com a normal apontada para fora da copa. Nada se move (D-253).
O nó se chama `Folhas`: o AssetLoader liga as duas faces e o recorte por alfa.

Saída: assets/blender/<chave>/<chave>.glb e metricas.json (lidos por tools/ret_registrar.py).
Uso (de vantuong65/): uv run --group arte python tools/vila_plantas.py
"""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from vila_decais import RAIZ, M, grava_malha, liso

LADO = 1024
TRONCOS: dict[str, list] = {}


# ---------------------------------------------------------------- texturas
def _ruido(rng: np.random.Generator, n: int, beta: float = 2.2) -> np.ndarray:
    f = np.fft.fft2(rng.normal(size=(n, n)))
    fx, fy = np.fft.fftfreq(n)[:, None], np.fft.fftfreq(n)[None, :]
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1
    r = np.fft.ifft2(f / k ** (beta / 2)).real
    return (r - r.min()) / (r.max() - r.min())


def _folha_coqueiro(rng, w: int, h: int) -> Image.Image:
    """Uma folha de coqueiro: a nervura no meio e os folíolos para os dois lados, base embaixo."""
    esc = 2
    img = Image.new("RGBA", (w * esc, h * esc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = w * esc / 2
    verdes = [(54, 84, 36), (68, 100, 40), (82, 114, 46), (60, 92, 40), (100, 124, 52)]
    secos = [(124, 112, 58), (142, 122, 66)]
    n = 62
    for lado in (-1, 1):
        for i in range(n):
            t = (i + rng.uniform(0, 0.7)) / n
            y0 = (1 - t * 0.97) * h * esc
            comp = (0.47 * np.sin(np.pi * min(1.0, t * 0.92 + 0.1)) ** 0.62 + 0.03) * w * esc
            comp *= rng.uniform(0.86, 1.04)
            sobe = comp * rng.uniform(0.62, 0.86)
            larg = rng.uniform(4.2, 7.0) * esc * (1.05 - 0.45 * t)
            base = secos if rng.random() < 0.07 else verdes
            cor = np.array(base[rng.integers(len(base))], float) * rng.uniform(0.86, 1.14)
            pts_a, pts_b = [], []
            for k in range(7):
                f = k / 6
                x = cx + lado * comp * f
                y = y0 - sobe * f + comp * 0.16 * f * f
                m = larg * (1 - f) ** 0.7 / 2
                pts_a.append((x, y - m))
                pts_b.append((x, y + m))
            d.polygon(pts_a + pts_b[::-1], fill=(*(int(np.clip(c, 0, 255)) for c in cor), 255))
    d.line([(cx, h * esc), (cx, h * esc * 0.02)], fill=(142, 130, 76, 255), width=5 * esc)
    return img.resize((w, h), Image.LANCZOS)


def _casca(rng, w: int, h: int) -> np.ndarray:
    """Casca do coqueiro: anéis das folhas caídas sobre cinza quente."""
    n = _ruido(rng, max(w, h))[:h, :w]
    y = np.arange(h, dtype=np.float32)[:, None]
    deslize = (n - 0.5) * 16
    anel = 0.5 + 0.5 * np.sin((y + deslize) / h * 2 * np.pi * 62)
    anel = liso(0.55, 0.95, anel)
    tom = 0.8 + 0.36 * n - 0.15 * anel
    a = np.zeros((h, w, 4), np.float32)
    a[..., 0], a[..., 1], a[..., 2] = 122 * tom, 106 * tom, 86 * tom
    a[..., 3] = 255
    return a


def textura_coqueiro(rng) -> np.ndarray:
    """Atlas de 1024: duas folhas (0..0,75) e a casca com o coco (0,75..1)."""
    img = Image.new("RGBA", (LADO, LADO), (0, 0, 0, 0))
    meia = int(LADO * 0.375)
    img.alpha_composite(_folha_coqueiro(rng, meia, LADO), (0, 0))
    img.alpha_composite(_folha_coqueiro(rng, meia, LADO), (meia, 0))
    a = np.asarray(img, np.float32).copy()
    x0 = int(LADO * 0.75)
    a[int(LADO * 0.2) :, x0:] = _casca(rng, LADO - x0, LADO - int(LADO * 0.2))
    # o coco: um verde-oliva com a ponta mais escura
    v = (np.arange(int(LADO * 0.2)) + 0.5) / (LADO * 0.2)
    coco = a[: int(LADO * 0.2), x0:]
    coco[..., 0] = (92 - 34 * v)[:, None]
    coco[..., 1] = (98 - 34 * v)[:, None]
    coco[..., 2] = (44 - 14 * v)[:, None]
    coco[..., 3] = 255
    return a


def _massa_folhas(rng, n: int, tons) -> np.ndarray:
    """Massa de folhas largas, recortada: miolo escuro e folhas claras por cima."""
    esc = 2
    img = Image.new("RGBA", (n * esc, n * esc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n * esc / 2
    for k in range(360):
        f = k / 360
        ang = rng.uniform(0, 2 * np.pi)
        r = c * 0.9 * np.sqrt(rng.random()) * (0.62 + 0.38 * f)
        x, y = c + r * np.cos(ang), c + r * np.sin(ang)
        giro = rng.uniform(0, 2 * np.pi)
        comp = rng.uniform(12, 22) * esc * (n / 512)
        larg = comp * rng.uniform(0.34, 0.46)
        luz = 0.6 + 0.56 * f - 0.1 * r / c
        cor = np.array(tons[rng.integers(len(tons))], float) * luz * rng.uniform(0.9, 1.12)
        pts = []
        for j in range(10):
            th = j / 10 * 2 * np.pi
            u, v = comp * np.cos(th), larg * np.sin(th) * (1 - 0.32 * np.cos(th))
            pts.append(
                (x + u * np.cos(giro) - v * np.sin(giro), y + u * np.sin(giro) + v * np.cos(giro))
            )
        d.polygon(pts, fill=(*(int(np.clip(q, 0, 255)) for q in cor), 255))
    return np.asarray(img.resize((n, n), Image.LANCZOS), np.float32).copy()


def textura_arvore(rng, tons) -> np.ndarray:
    """Atlas de 1024: quatro massas de folhas e, na faixa da direita, a casca."""
    n = int(LADO * 0.42)
    a = np.zeros((LADO, LADO, 4), np.float32)
    for i in range(2):
        for j in range(2):
            m = _massa_folhas(rng, n, tons)
            y, x = i * (LADO // 2), j * n
            a[y : y + n, x : x + n] = m
    x0 = int(LADO * 0.86)
    q = _ruido(rng, LADO)[:, : LADO - x0]
    fibra = ndimage.gaussian_filter(_ruido(rng, LADO, 1.2)[:, : LADO - x0], (14, 0.7))
    tom = 0.6 + 0.5 * q + 1.1 * (fibra - fibra.mean())
    a[:, x0:, 0], a[:, x0:, 1], a[:, x0:, 2] = 92 * tom, 76 * tom, 58 * tom
    a[:, x0:, 3] = 255
    return a


# ---------------------------------------------------------------- malha
class Malha:
    def __init__(self) -> None:
        self.p: list = []
        self.n: list = []
        self.uv: list = []
        self.i: list = []
        self.troncos: list = []
        self.duas_faces: list = []  # (início, fim) dos triângulos de folha fina

    def vert(self, p, n, uv) -> int:
        self.p.append(tuple(float(v) / M for v in p))
        q = np.asarray(n, float)
        self.n.append(tuple(q / (np.linalg.norm(q) + 1e-9)))
        self.uv.append((float(uv[0]), float(uv[1])))
        return len(self.p) - 1

    def tri(self, a, b, c) -> None:
        self.i += [a, b, c]

    def quad(self, a, b, c, d) -> None:
        self.i += [a, b, c, a, c, d]

    def fecha_duas_faces(self) -> None:
        """Repete as folhas finas com a normal invertida. Com DoubleSided o motor usa a normal da
        frente nos dois lados, e a folha vista por baixo, contra o sol, estourava em branco."""
        for ini, fim in self.duas_faces:
            mapa: dict[int, int] = {}
            for k in range(ini, fim, 3):
                tri = self.i[k : k + 3]
                novos = []
                for v in tri:
                    if v not in mapa:
                        self.p.append(self.p[v])
                        self.n.append(tuple(-q for q in self.n[v]))
                        self.uv.append(self.uv[v])
                        mapa[v] = len(self.p) - 1
                    novos.append(mapa[v])
                self.i += [novos[0], novos[2], novos[1]]
        self.duas_faces = []

    def grava(self, chave: str, tex: np.ndarray, rug: float) -> None:
        self.fecha_duas_faces()
        p = np.array(self.p, np.float32)
        y0 = float(p[:, 1].min())
        p[:, 1] -= y0
        cx, cz = (p[:, 0].max() + p[:, 0].min()) / 2, (p[:, 2].max() + p[:, 2].min()) / 2
        TRONCOS[chave] = [
            (
                (a[0] / M - cx, a[1] / M - y0, a[2] / M - cz),
                (b[0] / M - cx, b[1] / M - y0, b[2] / M - cz),
                r / M,
            )
            for a, b, r in self.troncos
        ]
        dim = (p.max(0) - p.min(0)) * M
        grava_malha(
            chave,
            p,
            np.array(self.n, np.float32),
            np.array(self.uv, np.float32),
            np.array(self.i, np.uint16),
            tex,
            rug,
            tuple(dim),
        )
        tam = f"{dim[0]:.1f} x {dim[1]:.1f} x {dim[2]:.1f} m"
        print(f"  {chave}: {len(self.i) // 3} triângulos, {tam}")


def tubo(m: Malha, eixo, raio, u0, u1, lados: int = 8, v_rep: float = 1.0) -> None:
    """Tubo por uma lista de pontos, com a UV dentro da faixa u0..u1 da textura."""
    pts = [np.asarray(q, float) for q in eixo]
    anel = []
    for k, c in enumerate(pts):
        t = pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]
        t /= np.linalg.norm(t) + 1e-9
        a = np.cross(t, (0.0, 0.0, 1.0))
        if np.linalg.norm(a) < 0.1:
            a = np.cross(t, (1.0, 0.0, 0.0))
        a /= np.linalg.norm(a)
        b = np.cross(t, a)
        f = k / max(1, len(pts) - 1)
        linha = []
        for s in range(lados + 1):
            th = s / lados * 2 * np.pi
            nr = a * np.cos(th) + b * np.sin(th)
            v = 0.21 + 0.78 * (f * v_rep % 1.0 if v_rep != 1.0 else f)
            linha.append(m.vert(c + nr * raio[k], nr, (u0 + (u1 - u0) * s / lados, 1 - v)))
        anel.append(linha)
    for k in range(len(anel) - 1):
        for s in range(lados):
            m.quad(anel[k][s], anel[k][s + 1], anel[k + 1][s + 1], anel[k + 1][s])


def folha_coqueiro(m: Malha, topo, ang, sobe, comp, larg, u0, u1, rng, partes: int = 7) -> None:
    """Tira em V: a nervura arqueia para fora e cai na ponta."""
    d = np.array((np.cos(ang), 0.0, np.sin(ang)))
    lado = np.array((-np.sin(ang), 0.0, np.cos(ang)))
    cai = rng.uniform(0.85, 1.25)
    linhas = []
    for k in range(partes + 1):
        f = k / partes
        h = sobe * f * comp - cai * comp * 0.72 * f * f * f - 0.18 * comp * f * f
        c = np.asarray(topo) + d * comp * f * (1 - 0.12 * f) + np.array((0.0, h, 0.0))
        w = larg * (0.42 + 0.58 * np.sin(np.pi * min(1.0, f * 0.92 + 0.1)) ** 0.7)
        desce = 0.26 * w * (0.45 + 0.55 * f)
        tg = d * (1 - 0.3 * f) + np.array((0.0, sobe - 2.4 * cai * f * f, 0.0))
        nr = np.cross(lado, tg)
        if nr[1] < 0:
            nr = -nr
        nr = nr + np.array((0.0, 0.8, 0.0))
        um = (u0 + u1) / 2
        v = 1 - f * 0.98
        linhas.append(
            (
                m.vert(c + lado * w - (0, desce, 0), nr + lado * 0.5, (u1, v)),
                m.vert(c, nr, (um, v)),
                m.vert(c - lado * w - (0, desce, 0), nr - lado * 0.5, (u0, v)),
            )
        )
    for k in range(partes):
        a, b = linhas[k], linhas[k + 1]
        # a frente olha para cima, como a normal: invertida, a folha estourava contra o sol
        m.quad(b[0], b[1], a[1], a[0])
        m.quad(b[1], b[2], a[2], a[1])


def coco(m: Malha, c, r) -> None:
    """Coco de 8 faces (usa a faixa de cor do coco no atlas)."""
    eixos = [np.array(v, float) for v in ((1, 0, 0), (0, 0, 1), (-1, 0, 0), (0, 0, -1))]
    ci = np.asarray(c, float)
    topo = m.vert(ci + (0, r * 1.05, 0), (0, 1, 0), (0.86, 0.01))
    fundo = m.vert(ci - (0, r * 1.2, 0), (0, -1, 0), (0.86, 0.19))
    meio = [m.vert(ci + e * r, e, (0.8 + 0.05 * k, 0.1)) for k, e in enumerate(eixos)]
    for k in range(4):
        a, b = meio[k], meio[(k + 1) % 4]
        m.tri(topo, b, a)
        m.tri(fundo, a, b)


def coqueiro(chave: str, sem: int, altura: float, curva: float, nf: int) -> None:
    rng = np.random.default_rng(sem)
    m = Malha()
    ang_c = rng.uniform(0, 2 * np.pi)
    dx, dz = np.cos(ang_c), np.sin(ang_c)
    eixo, raio = [], []
    n = 11
    for k in range(n + 1):
        f = k / n
        # curva em S: o topo volta para perto da vertical da base (o modelo é posto pelo centro)
        off = curva * (np.sin(f * np.pi * 1.25) * 0.9 - 0.25 * f)
        eixo.append((dx * off, altura * f, dz * off))
        raio.append(0.14 + 0.09 * (1 - f) ** 1.3 + 0.17 * np.exp(-f * 16))
    tubo(m, eixo, raio, 0.76, 0.99, lados=8)
    for a, b in ((0, 4), (4, 8), (8, n)):
        m.troncos.append((eixo[a], eixo[b], (raio[a] + raio[b]) / 2))
    topo = np.array(eixo[-1])
    ini_folhas = len(m.i)
    for k in range(nf):
        anel = k / nf
        ang = k * 2.39996 + rng.uniform(-0.2, 0.2)
        sobe = 0.95 - 1.18 * anel + rng.uniform(-0.1, 0.1)
        comp = rng.uniform(3.7, 4.7) * (1.0 - 0.1 * abs(anel - 0.45))
        larg = rng.uniform(0.82, 1.02)
        u0, u1 = (0.0, 0.375) if rng.random() < 0.5 else (0.375, 0.75)
        folha_coqueiro(m, topo + (0, -0.12 * anel, 0), ang, sobe, comp, larg, u0, u1, rng)
    m.duas_faces.append((ini_folhas, len(m.i)))
    for _ in range(rng.integers(5, 9)):
        ang = rng.uniform(0, 2 * np.pi)
        coco(m, topo + (np.cos(ang) * 0.26, -0.3 - rng.uniform(0, 0.16), np.sin(ang) * 0.26), 0.14)
    m.grava(chave, textura_coqueiro(rng), 0.85)


def arvore(chave: str, sem: int, alt_tronco: float, raio_copa: float, tons, cartoes: int) -> None:
    rng = np.random.default_rng(sem)
    m = Malha()
    r0 = 0.3 + 0.03 * alt_tronco
    tubo(
        m,
        [(0, -0.1, 0), (0.05, alt_tronco * 0.4, 0.04), (0.02, alt_tronco, -0.03)],
        [r0 * 1.3, r0 * 0.92, r0 * 0.75],
        0.87,
        0.995,
        lados=8,
    )
    m.troncos.append(((0.0, 0.0, 0.0), (0.02, alt_tronco, -0.03), r0))
    lobos = []
    for k in range(7):
        ang = k * 2.39996 + rng.uniform(-0.4, 0.4)
        d = raio_copa * rng.uniform(0.38, 0.78) if k else 0.0
        c = np.array(
            (
                np.cos(ang) * d,
                alt_tronco + raio_copa * rng.uniform(0.3, 0.7),
                np.sin(ang) * d,
            )
        )
        r = raio_copa * (0.66 if k == 0 else rng.uniform(0.42, 0.6))
        lobos.append((c, r))
        if k:
            tubo(
                m,
                [
                    (0.02, alt_tronco * 0.88, -0.02),
                    (c[0] * 0.5, (alt_tronco + c[1]) / 2 - 0.2, c[2] * 0.5),
                    tuple(c),
                ],
                [r0 * 0.5, r0 * 0.32, r0 * 0.12],
                0.87,
                0.995,
                lados=5,
            )
    pesos = np.array([r**2 for _, r in lobos])
    pesos = pesos / pesos.sum()
    for _ in range(cartoes):
        c, r = lobos[int(rng.choice(len(lobos), p=pesos))]
        v = rng.normal(size=3)
        v /= np.linalg.norm(v)
        if v[1] < -0.45:
            v[1] = -v[1] * 0.5
            v /= np.linalg.norm(v)
        q = c + v * r * rng.uniform(0.62, 1.05) * np.array((1.0, 0.74, 1.0))
        a = np.cross(v, rng.normal(size=3))
        a /= np.linalg.norm(a)
        b = np.cross(v, a)
        t = rng.uniform(0.95, 1.5) * (raio_copa / 4.6) ** 0.5
        i, j = int(rng.integers(2)), int(rng.integers(2))
        u0, u1 = j * 0.42, (j + 1) * 0.42
        v_t0 = i * 0.5
        v0, v1 = 1 - v_t0 - 0.42, 1 - v_t0
        nr = v + np.array((0.0, 0.42, 0.0))
        ids = [
            m.vert(q - a * t - b * t, nr - (a + b) * 0.28, (u0, v0)),
            m.vert(q + a * t - b * t, nr + (a - b) * 0.28, (u1, v0)),
            m.vert(q + a * t + b * t, nr + (a + b) * 0.28, (u1, v1)),
            m.vert(q - a * t + b * t, nr + (b - a) * 0.28, (u0, v1)),
        ]
        m.quad(*ids)
    m.grava(chave, textura_arvore(rng, tons), 1.0)


def arbusto(chave: str, sem: int, raio: float, tons, cartoes: int) -> None:
    """Moita baixa: só a massa de folhas, sem tronco."""
    rng = np.random.default_rng(sem)
    m = Malha()
    for _ in range(cartoes):
        v = rng.normal(size=3)
        v /= np.linalg.norm(v)
        if v[1] < -0.15:
            v[1] = -v[1] * 0.4
            v /= np.linalg.norm(v)
        q = np.array((0.0, raio * 0.62, 0.0)) + v * raio * rng.uniform(0.45, 1.0) * np.array(
            (1.0, 0.72, 1.0)
        )
        a = np.cross(v, rng.normal(size=3))
        a /= np.linalg.norm(a)
        b = np.cross(v, a)
        t = rng.uniform(0.38, 0.62) * raio**0.5
        i, j = int(rng.integers(2)), int(rng.integers(2))
        u0, u1 = j * 0.42, (j + 1) * 0.42
        v1 = 1 - i * 0.5
        v0 = v1 - 0.42
        nr = v + np.array((0.0, 0.5, 0.0))
        ids = [
            m.vert(q - a * t - b * t, nr - (a + b) * 0.28, (u0, v0)),
            m.vert(q + a * t - b * t, nr + (a - b) * 0.28, (u1, v0)),
            m.vert(q + a * t + b * t, nr + (a + b) * 0.28, (u1, v1)),
            m.vert(q - a * t + b * t, nr + (b - a) * 0.28, (u0, v1)),
        ]
        m.quad(*ids)
    m.grava(chave, textura_arvore(rng, tons), 1.0)


def pedras(chave: str, sem: int) -> None:
    """Punhado de pedras de laterita meio enterradas (a beira da rua deixa de ser uma linha)."""
    rng = np.random.default_rng(sem)
    m = Malha()
    for _ in range(11):
        ang, d = rng.uniform(0, 2 * np.pi), 0.62 * np.sqrt(rng.random())
        c = np.array((np.cos(ang) * d, 0.0, np.sin(ang) * d))
        r = rng.uniform(0.05, 0.17)
        lados = 6
        giro = rng.uniform(0, 2 * np.pi)
        anel = []
        for s in range(lados):
            th = giro + s / lados * 2 * np.pi
            q = r * rng.uniform(0.78, 1.18)
            nr = np.array((np.cos(th), 0.5, np.sin(th)))
            anel.append(
                m.vert(c + (np.cos(th) * q, r * 0.22, np.sin(th) * q), nr, (s / lados, 0.6))
            )
        topo = m.vert(c + (0.0, r * rng.uniform(0.6, 0.9), 0.0), (0, 1, 0), (0.5, 0.05))
        fundo = [
            m.vert(
                c
                + (
                    np.cos(giro + s / lados * 2 * np.pi) * r,
                    -0.04,
                    np.sin(giro + s / lados * 2 * np.pi) * r,
                ),
                (np.cos(giro + s / lados * 2 * np.pi), 0.1, np.sin(giro + s / lados * 2 * np.pi)),
                (s / lados, 0.95),
            )
            for s in range(lados)
        ]
        for s in range(lados):
            k = (s + 1) % lados
            m.tri(topo, anel[k], anel[s])
            m.quad(anel[s], anel[k], fundo[k], fundo[s])
    n = _ruido(rng, 256, 1.7)
    tex = np.zeros((256, 256, 4), np.float32)
    tex[..., 0], tex[..., 1], tex[..., 2] = 96 + 72 * n, 74 + 54 * n, 56 + 40 * n
    tex[..., 3] = 255
    m.grava(chave, tex, 0.92)


def principal() -> None:
    coqueiro("ret_pov_p_coqueiro_a", 1965, 10.4, 0.62, 22)
    coqueiro("ret_pov_p_coqueiro_b", 1966, 7.6, 0.42, 20)
    mangueira = [(46, 74, 34), (58, 88, 38), (40, 66, 32), (72, 98, 42), (54, 80, 30)]
    jaca = [(62, 88, 36), (76, 102, 42), (52, 78, 32), (90, 110, 46), (66, 90, 34)]
    arvore("ret_pov_p_arvore_a", 1967, 3.6, 5.0, mangueira, 400)
    arvore("ret_pov_p_arvore_b", 1968, 2.6, 3.7, jaca, 280)
    pedras("ret_pov_p_pedras", 1969)
    arbusto("ret_pov_p_arbusto_a", 1970, 1.15, mangueira, 46)
    arbusto("ret_pov_p_arbusto_b", 1971, 0.8, jaca, 30)
    linhas = [
        "--!strict",
        "-- GERADO por tools/vila_plantas.py. Não editar. Cilindros (a, b, r) em studs,",
        "-- a partir do pé da caixa do modelo: o tronco que para a bala e o soldado.",
        "return {",
    ]
    for k, cs in sorted(TRONCOS.items()):
        linhas.append(f"\t{k} = {{")
        for a, b, r in cs:
            fa = ", ".join(f"{v:.3f}" for v in a)
            fb = ", ".join(f"{v:.3f}" for v in b)
            linhas.append(f"\t\t{{ a = {{ {fa} }}, b = {{ {fb} }}, r = {r:.3f} }},")
        linhas.append("\t},")
    linhas.append("}")
    arq = RAIZ / "src/ServerScriptService/Modules/TroncosPov.luau"
    arq.write_text("\n".join(linhas) + "\n", "utf-8", newline="\n")


if __name__ == "__main__":
    principal()
