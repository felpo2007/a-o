"""As 4 facas do jogo (Váº N TÆ¯á»œNG '65) e suas bainhas, em mm no referencial do Blender.

Numpy puro (usa `malha` e `lamina`). OrientaÃ§Ã£o: lÃ¢mina para -Y (ponta em -Y), fio para -Z,
faces planas para Â±X; a face da frente da guarda fica em y = 0 e o cabo em +Y. A bainha estÃ¡ na
mesma orientaÃ§Ã£o, com a faca dentro (o cabo, a guarda e o pomo entram tambÃ©m no nÃ³ Bainha:
`cabo_para_fora`). A presilha de cinto fica no lado -X do Blender (+X da MeshPart no Roblox).

Fontes das medidas (o resto Ã© PLACEHOLDER, marcado no comentÃ¡rio):
- KA-BAR USMC Mark 2 (1219C2): comprimento total 11 7/8 pol. (301,6 mm), lÃ¢mina 7 pol.
  (177,8 mm), espessura 0,165 pol. (4,2 mm) (especificaÃ§Ã£o do fabricante);
- baioneta M6 (M14): lÃ¢mina 6 3/4 pol. (171 mm), comprimento total 11 1/2 pol. (292 mm);
- espigÃ£o do Tipo 56 e dao/rá»±a do VC: sem fonte aqui, tudo PLACEHOLDER.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import lamina as lm
import numpy as np
from malha import Malha, anel_xz, estacoes, ret_arred, simplificar, suave, superelipse


@dataclass
class Modelo:
    chave: str
    malha: Malha
    pontos: dict  # {"Faca": {...}, "Bainha": {...}} em mm, referencial do Blender
    info: dict = field(default_factory=dict)


def _lerp(a, b, t):
    return a + (b - a) * t


def _clip01(x):
    return min(1.0, max(0.0, x))


def perfil_fita(esp: float, larg: float, recuo: float | None = None):
    """SeÃ§Ã£o de fita (couro ou lona): (n, b) com n na espessura e b na largura; pontos nas
    linhas de costura (recuo da borda) e no meio, nas duas faces. Devolve (pontos, atravÃ©s)."""
    h, w = esp / 2, larg / 2
    r = recuo if recuo is not None else w * 0.5
    bs = [-w, -(w - r), 0.0, w - r, w]
    pts = np.array([(h, b) for b in bs] + [(-h, b) for b in bs[::-1]])
    atr = np.abs(np.abs(pts[:, 1]) - (w - r)) if recuo is not None else np.full(len(pts), 99.0)
    return pts, atr


def costura_tubo(caminho, atr):
    """UV de costura de um tubo: ao longo = caminho percorrido; atravÃ©s = por ponto do perfil."""
    c = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(caminho, axis=0), axis=1))])
    out = np.zeros((len(caminho), len(atr), 2))
    out[..., 0] = c[:, None]
    out[..., 1] = np.asarray(atr)[None, :]
    return out


def arco_pts(c, r, a0, a1, n, plano="xy"):
    """Arco de cÃ­rculo no plano dado (c = centro 3D), de a0 a a1 graus."""
    out = []
    for i in range(n):
        a = math.radians(_lerp(a0, a1, i / (n - 1)))
        d = (math.cos(a) * r, math.sin(a) * r)
        p = np.array(c, float).copy()
        if plano == "xy":
            p[0] += d[0]
            p[1] += d[1]
        elif plano == "xz":
            p[0] += d[0]
            p[2] += d[1]
        else:  # yz
            p[1] += d[0]
            p[2] += d[1]
        out.append(p)
    return out


def caminho_suave(pts, passo: float = 2.0) -> np.ndarray:
    """Catmull-Rom pelos pontos de controle, reamostrado a cada `passo` mm (aprox.)."""
    P = np.asarray(pts, float)
    P = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        n = max(2, int(math.ceil(np.linalg.norm(p2 - p1) / passo)))
        for k in range(n):
            t = k / n
            out.append(
                0.5
                * (
                    2 * p1
                    + (-p0 + p2) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t**3
                )
            )
    out.append(P[-2])
    return np.array(out)


def tira_retencao(
    m: Malha,
    y: float,
    bx: float,
    az: float,
    larg: float,
    esp: float,
    x_tras: float,
    mat: str,
    mat_botao: str,
    cz: float = 0.0,
) -> dict:
    """Tira de retenÃ§Ã£o em volta do cabo (laÃ§o fechado no plano x-z em `y`), presa atrÃ¡s (-X, em
    `x_tras`) e com a lingueta e o botÃ£o de pressÃ£o do lado +X."""
    n = 36
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    c, s = np.cos(t), np.sin(t)
    rx = np.where(c >= 0, bx, x_tras)
    cam = np.column_stack([rx * c, np.full(n, y), az * s + cz])
    perfil = ret_arred(esp / 2, larg / 2, 0.5, 2)
    m.tubo(cam, perfil, mat, normal0=(1.0, 0.0, 0.0), ciclo=True, peso=0.5)
    # lingueta por cima, do lado +X (de -45 a +55 graus)
    ang = np.radians(np.linspace(-45, 55, 11))
    cam2 = np.column_stack(
        [(bx + esp) * np.cos(ang), np.full(len(ang), y), (az + esp) * np.sin(ang) + cz]
    )
    perfil2 = ret_arred(esp / 2, larg / 2 - 0.6, 0.6, 2)
    m.tubo(cam2, perfil2, mat, normal0=(1.0, 0.0, 0.0), peso=0.5, peso_tampa=0.3)
    xb = bx + esp * 1.5
    m.domo(
        (xb - 0.2, y, cz),
        (1, 0, 0),
        mat_botao,
        raio=larg * 0.36,
        altura=2.4,
        n=14,
        perfil=[
            (larg * 0.37, -0.3),
            (larg * 0.36, 0.9),
            (larg * 0.3, 1.9),
            (larg * 0.17, 2.35),
            (0.0, 2.45),
        ],
        peso=0.6,
    )
    return {"botao": (xb + 2.4, y, cz)}


# =================================================================== KA-BAR
def kabar() -> Modelo:
    m = Malha()
    L = 177.8  # lÃ¢mina 7 pol. (fabricante)
    TOT = 301.6  # total 11 7/8 pol. (fabricante)
    T0 = 4.2  # espessura 0,165 pol. (fabricante)
    Z_DORSO, Z_FIO = 14.5, -15.5  # largura ~30 mm (1,15-1,2 pol. citado) PLACEHOLDER
    S_CLIP = L - 64.0  # comeÃ§o do clip PLACEHOLDER
    S_BARRIGA = L - 58.0  # comeÃ§o da curva do fio PLACEHOLDER
    Z_PONTA = 4.0  # ponta um pouco acima do eixo PLACEHOLDER

    def topo(s):
        if s <= S_CLIP:
            return Z_DORSO
        t = (s - S_CLIP) / (L - S_CLIP)
        return Z_DORSO - (Z_DORSO - Z_PONTA) * (1 - (1 - t) ** 1.3)

    def fio(s):
        if s <= S_BARRIGA:
            return Z_FIO
        t = (s - S_BARRIGA) / (L - S_BARRIGA)
        return Z_FIO + (Z_PONTA - Z_FIO) * t**2.0

    def esp(s):  # afilamento distal PLACEHOLDER
        if s < 100:
            return T0
        return _lerp(T0, 0.7, ((s - 100) / (L - 100)) ** 1.2)

    def plunge(s):  # ricasso sem fio atÃ© 6 mm, curva do chanfro atÃ© 16 mm PLACEHOLDER
        return float(suave(s, 6.0, 16.0))

    lam = lm.Lamina(
        L=L,
        topo=topo,
        fio=fio,
        esp=esp,
        bisel=lambda s: _lerp(1.0, 13.0, plunge(s) ** 0.7),  # chanfro plano ~13 mm PLACEHOLDER
        e_fio=lambda s: _lerp(T0 - 0.6, 0.55, plunge(s)),
        micro=0.9,  # microbisel PLACEHOLDER
        chanfro=0.35,
        ponta_z=Z_PONTA,
        afiado=lambda s: float(suave(s, 7.0, 12.0)),
        falso=lambda s: 4.5 * _clip01((s - S_CLIP - 3.0) / 12.0),  # falso fio do clip
        falso_esp=0.3,
        sulco={"s0": 17.0, "s1": 112.0, "zc": lambda s: 6.5, "w": 6.5, "prof": 0.75},  # PH
    )
    bl = lm.construir(m, lam, "aco_lamina", fixas=[S_CLIP, S_BARRIGA, 6.0, 16.0])

    # ---- guarda reta de aÃ§o com pontas ovais (8 x 4,8 x 62,5 mm) PLACEHOLDER
    Y_G = 4.8
    zg0, zg1 = -32.0, 30.5
    zc, meia = (zg0 + zg1) / 2, (zg1 - zg0) / 2

    def anel_guarda(z):
        u = abs(z - zc) / meia
        hx = 3.6 + 0.7 * u**4
        hy = Y_G / 2
        d = meia - abs(z - zc)
        if d < 5.0:
            f = math.sqrt(max(0.0, 1 - ((5.0 - d) / 5.0) ** 2))
            hx *= max(f, 0.24)
            hy *= 0.55 + 0.45 * f
        xy = ret_arred(hx, hy, min(0.9, 0.6 * min(hx, hy)), 3)
        return np.column_stack([xy[:, 0], xy[:, 1] + Y_G / 2, np.full(len(xy), z)])

    zs = estacoes(anel_guarda, np.linspace(zg0, zg1, 600), 0.03, fixas=[zg0, zg1])
    m.dup_atual = 1  # guarda, cabo e pomo tambÃ©m vÃ£o na Bainha (faca embainhada)
    m.loft([anel_guarda(z) for z in zs], "aco", tampa0=True, tampa1=True, peso=0.9, peso_tampa=0.3)

    # ---- cabo de arruelas de couro com os anÃ©is da Ka-Bar (7 gomos) PLACEHOLDER
    Y_C0, Y_C1 = 4.6, 110.6
    yr0, yr1 = Y_G + 1.0, 110.0 - 1.0
    per = (yr1 - yr0) / 7
    gd = 1.6

    def cabo_ab(y):
        u = _clip01((y - Y_G) / (110.0 - Y_G))
        a0 = 13.2 + 2.2 * math.sin(math.pi * u) ** 0.9
        g = 0.0
        if yr0 <= y <= yr1:
            g = -gd * (1 - abs(math.sin(math.pi * (y - yr0) / per)) ** 0.55)
        else:
            g = -gd
        return a0 + g, 0.8 * a0 + 0.9 * g

    def anel_cabo(y):
        a, b = cabo_ab(y)
        return anel_xz(y, superelipse(a, b, 20, 2.3))

    ys = estacoes(anel_cabo, np.arange(Y_C0, Y_C1 + 1e-6, 0.2), 0.06, fixas=[Y_C0, Y_C1])
    m.loft(
        [anel_cabo(y) for y in ys],
        "couro_cabo",
        tampa0=True,
        tampa1=True,
        peso=1.0,
        peso_tampa=0.05,
    )

    # ---- pomo de aÃ§o oval com a espiga rebitada
    pom = [  # (y, a, b, expoente) PLACEHOLDER
        (109.6, 13.6, 10.9, 2.3),
        (110.2, 14.6, 11.7, 2.3),
        (110.9, 15.2, 12.2, 2.4),
        (112.0, 15.4, 12.4, 2.4),
        (117.0, 15.4, 12.4, 2.4),
        (119.0, 15.0, 12.0, 2.4),
        (120.4, 14.1, 11.2, 2.4),
        (121.3, 12.4, 9.8, 2.4),
        (121.8, 9.6, 7.6, 2.4),
        (122.05, 6.2, 3.8, 3.0),
        (122.25, 5.4, 3.0, 3.5),
        (122.9, 5.1, 2.8, 3.5),
        (123.4, 4.2, 2.1, 3.0),
    ]
    y_pomo = TOT - L - 0.2
    an = [anel_xz(y, superelipse(a, b, 20, e)) for y, a, b, e in pom]
    m.loft(
        an,
        "aco",
        ponta1=(0.0, y_pomo, 0.0),
        tampa0=True,
        ilhas=[
            {"k": (0, 6), "peso": 0.9},
            {"k": (6, len(an) - 1), "modo": "plano", "eu": (1, 0, 0), "ev": (0, 0, 1), "peso": 0.9},
        ],
        peso_tampa=0.3,
    )
    m.dup_atual = 0

    # ---- bainha USMC de couro marrom: bolso dobrado no dorso, aba costurada no lado do fio
    m.no_atual = 1
    SB = 204.0  # comprimento da bainha abaixo da guarda PLACEHOLDER
    Z_TB = -4.0

    def b_topo(s):
        if s <= 118:
            return 19.0
        return 19.0 - (19.0 - Z_TB) * ((s - 118) / (SB - 118)) ** 1.7

    def b_baixo(s):
        if s <= 130:
            return -30.0
        return -30.0 + (30.0 + Z_TB) * ((s - 130) / (SB - 130)) ** 1.5

    def b_xh(s):
        return _lerp(5.4, 3.2, s / SB)

    def b_lado(s):
        top, bot = b_topo(s), b_baixo(s)
        h = top - bot
        xh = b_xh(s)
        xf = min(4.4, 0.82 * xh)
        rf = min(xh, 0.2 * h)
        hf = min(11.0, 0.36 * h)
        ft = bot + hf
        zs = bot + 0.4 * hf
        parede = top - rf - ft
        pts = [
            (xh * math.sin(math.radians(30)), top - rf * (1 - math.cos(math.radians(30)))),
            (xh * math.sin(math.radians(62)), top - rf * (1 - math.cos(math.radians(62)))),
            (xh, top - rf),
            (xh + 0.35, ft + 0.55 * parede),
            (xh, ft + min(2.2, 0.2 * parede)),
            (xf + 0.25, ft + min(0.4, 0.04 * parede)),
            (xf, ft - 0.03 * hf),
            (xf, zs + 0.08 * hf),
            (xf - 0.35, zs),
            (xf, zs - 0.08 * hf),
            (xf, bot + 0.12 * hf),
            (0.55 * xf, bot + 0.02 * hf),
        ]
        return pts, top, bot, zs, hf

    def anel_bainha(s):
        sd, top, bot, _, _ = b_lado(s)
        xz = [(0.0, top)] + sd + [(0.0, bot)] + [(-x, z) for x, z in reversed(sd)]
        return anel_xz(-s, xz)

    ss = estacoes(anel_bainha, np.arange(0.4, SB - 1.0, 0.5), 0.08, fixas=[0.4, SB - 1.0])
    an = np.array([anel_bainha(s) for s in ss])
    cs = np.zeros(an.shape[:2] + (2,))
    for k, s in enumerate(ss):
        zs_k = b_lado(s)[3]
        cs[k, :, 0] = s
        cs[k, :, 1] = an[k, :, 2] - zs_k
    N = an.shape[1]
    m.loft(
        an,
        "couro_bainha",
        ponta1=(0.0, -SB, Z_TB),
        tampa0=True,
        ilhas=[{"j": (0, N // 2), "peso": 0.5}, {"j": (N // 2, N), "peso": 0.5}],
        peso_tampa=0.3,
        costura=cs,
        vivas_j=[N // 2],
    )
    # rebites na aba (dos dois lados)
    for s in (14.0, 50.0, 88.0, 126.0, 160.0):
        _, top, bot, zs, hf = b_lado(s)
        xf = min(4.4, 0.82 * b_xh(s))
        z = bot + 0.73 * hf
        for sx in (1, -1):
            m.domo((sx * xf, -s, z), (sx, 0, 0), "rebite", raio=2.2, altura=1.1, peso=0.35)

    # presilha de cinto (fita de couro dobrada atrÃ¡s do cabo)
    xa = -6.6
    xi = -17.6
    xo = xi - 3.2 - 4.2
    yt = 86.0
    ctrl = [
        (xa, -52.0),
        (xa, -6.0),
        (xa - 0.9, -1.0),
        (-11.5, 3.0),
        (-15.5, 7.0),
        (xi + 0.4, 11.0),
        (xi, 16.0),
        (xi, yt - 4.0),
    ]
    zl = -1.0  # a fita (34 mm) fica escondida atrás do bolso, sem passar do dorso
    cam = [np.array([x, y, zl]) for x, y in ctrl]
    cam += arco_pts(((xi + xo) / 2, yt, zl), (xi - xo) / 2, 0, 180, 9, "xy")
    cam += [
        np.array([xo, yt - 4.0, zl]),
        np.array([xo, 26.0, zl]),
        np.array([xo + 1.6, 20.0, zl]),
        np.array([xi - 1.7, 16.5, zl]),
    ]
    cam = simplificar(caminho_suave(cam, 1.0), 0.06)
    perfil, atr = perfil_fita(3.2, 34.0, recuo=3.5)
    m.tubo(
        cam,
        perfil,
        "couro_bainha",
        normal0=(1.0, 0.0, 0.0),
        peso=0.25,
        peso_tampa=0.15,
        costura=costura_tubo(cam, atr),
    )
    # rebites que fecham a presilha embaixo do cinto (na perna de fora, onde ela volta)
    volta = cam[len(cam) // 2 :]
    pv = volta[np.argmin(np.abs(volta[:, 1] - 19.5))]
    for z in (zl - 10.0, zl + 10.0):
        m.domo((pv[0] - 1.5, pv[1], z), (-1, 0, 0), "rebite", raio=2.4, altura=1.2, peso=0.3)
        m.domo((xa - 1.6, -40.0, z), (-1, 0, 0), "rebite", raio=2.2, altura=1.0, peso=0.2)
    # tira de retenÃ§Ã£o com botÃ£o de pressÃ£o em volta do cabo (y 14..28)
    yb = 21.0
    a_r = max(cabo_ab(y)[0] for y in np.linspace(yb - 7, yb + 7, 60))
    b_r = max(cabo_ab(y)[1] for y in np.linspace(yb - 7, yb + 7, 60))
    tr = tira_retencao(
        m, yb, b_r + 1.45, a_r + 1.45, 14.0, 2.5, -xi - 1.6 - 1.25 + 0.8, "couro_bainha", "botao"
    )
    m.no_atual = 0

    meio_cabo = (Y_G + 110.0) / 2
    pontos = {
        "Faca": {
            "punho": (0.0, meio_cabo, 0.0),
            "guarda": (0.0, 0.0, (Z_DORSO + Z_FIO) / 2),
            "ponta": bl["ponta"],
            "pomo": (0.0, y_pomo, 0.0),
            "fio": (0.0, 0.0, -1.0),
            "comprimento_mm": y_pomo + L,
            "lamina_mm": L,
        },
        "Bainha": {
            "boca": (0.0, -0.4, 0.0),
            "presilha": ((xi + xo) / 2, yt - 28.5, zl),
            "ponta": (0.0, -SB, Z_TB),
            "botao": tr["botao"],
        },
    }
    info = {
        "estacoes_lamina": len(bl["estacoes"]),
        "anel_lamina": bl["n_anel"],
        "estacoes_cabo": len(ys),
    }
    return Modelo("kabar", m, pontos, info)


# =================================================================== M6 + bainha M8A1
def m6() -> Modelo:
    m = Malha()
    L = 171.45  # lÃ¢mina 6 3/4 pol.
    TOT = 292.1  # total 11 1/2 pol.
    T0 = 4.8  # espessura PLACEHOLDER
    ZD, ZF = 10.5, -12.0  # largura 22,5 mm PLACEHOLDER
    S_FALSO = L - 76.0  # falso fio parcial no dorso, ~3 pol. PLACEHOLDER
    S_B = L - 50.0
    ZP = -0.5  # ponta de lanÃ§a no eixo da lÃ¢mina

    def topo(s):
        if s <= S_FALSO:
            return ZD
        return ZD - (ZD - ZP) * ((s - S_FALSO) / (L - S_FALSO)) ** 1.5

    def fio(s):
        if s <= S_B:
            return ZF
        return ZF + (ZP - ZF) * ((s - S_B) / (L - S_B)) ** 1.8

    def esp(s):
        if s < 110:
            return T0
        return _lerp(T0, 0.9, ((s - 110) / (L - 110)) ** 1.1)

    def plunge(s):
        return float(suave(s, 9.0, 18.0))

    lam = lm.Lamina(
        L=L,
        topo=topo,
        fio=fio,
        esp=esp,
        bisel=lambda s: _lerp(1.0, 8.5, plunge(s) ** 0.7),  # chanfro plano PLACEHOLDER
        e_fio=lambda s: _lerp(T0 - 0.7, 0.6, plunge(s)),
        micro=0.8,
        chanfro=0.45,
        ponta_z=ZP,
        afiado=lambda s: float(suave(s, 10.0, 15.0)),
        falso=lambda s: 3.2 * _clip01((s - S_FALSO - 4.0) / 10.0),
        falso_esp=0.6,
    )
    bl = lm.construir(m, lam, "aco_lamina", fixas=[S_FALSO, S_B, 9.0, 18.0])

    m.dup_atual = 1
    # ---- anel de boca (encaixa no quebra-chamas da M14) PLACEHOLDER: diÃ¢metro interno 22 mm
    ZA, RI, RE = 26.0, 11.0, 14.5
    perfil = [
        (RI, -0.6),
        (RI + 0.5, -1.1),
        (RE - 0.5, -1.1),
        (RE, -0.6),
        (RE, 6.6),
        (RE - 0.5, 7.1),
        (RI + 0.5, 7.1),
        (RI, 6.6),
    ]
    m.torno(
        perfil,
        "aco",
        centro=(0.0, 0.0, ZA),
        eixo=(0, 1, 0),
        ref=(0, 0, 1),
        n=28,
        ciclo=True,
        peso=0.8,
    )

    # ---- guarda: placa de 6 mm do anel atÃ© o quilhÃ£o de baixo PLACEHOLDER
    zg0, zg1 = -22.0, 13.5

    def anel_gm(z):
        hx = 3.9 + 3.0 * float(suave(z, 4.0, 13.5))
        hy = 3.0
        d = z - zg0
        if d < 4.0:
            f = math.sqrt(max(0.0, 1 - ((4.0 - d) / 4.0) ** 2))
            hx *= max(f, 0.25)
            hy *= 0.6 + 0.4 * f
        xy = ret_arred(hx, hy, min(1.0, 0.6 * min(hx, hy)), 3)
        return np.column_stack([xy[:, 0], xy[:, 1] + 3.0, np.full(len(xy), z)])

    zs = estacoes(anel_gm, np.linspace(zg0, zg1, 400), 0.03, fixas=[zg0, zg1])
    m.loft([anel_gm(z) for z in zs], "aco", tampa0=True, tampa1=True, peso=0.9, peso_tampa=0.3)

    # ---- espiga/armaÃ§Ã£o do cabo (aÃ§o) e placas pretas quadriculadas
    CZ = 0.4
    arm = ret_arred(3.1, 12.2, 1.2, 3)
    m.loft(
        [anel_xz(5.8, arm, CZ), anel_xz(96.4, arm, CZ)],
        "aco",
        tampa0=True,
        tampa1=True,
        peso=0.6,
        peso_tampa=0.1,
    )
    PL = [
        (3.0, -10.6),
        (4.3, -10.6),
        (6.3, -9.9),
        (7.5, -7.6),
        (8.1, -3.6),
        (8.25, 0.4),
        (8.1, 4.4),
        (7.5, 8.4),
        (6.3, 10.7),
        (4.3, 11.4),
        (3.0, 11.4),
    ]
    xad_p = np.array([0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0], float)
    est = [
        (6.4, 0.75, 0),
        (7.0, 0.93, 0),
        (7.8, 1.0, 0),
        (9.8, 1.0, 1),
        (92.4, 1.0, 1),
        (94.4, 1.0, 0),
        (95.2, 0.93, 0),
        (95.8, 0.75, 0),
    ]  # PLACEHOLDER
    for sx in (1, -1):
        an, xad = [], []
        for y, q, xs in est:
            xz = [(sx * (3.0 + (x - 3.0) * q), CZ + (z - CZ) * (0.9 + 0.1 * q)) for x, z in PL]
            an.append(anel_xz(y, xz))
            xad.append(xad_p * xs)
        m.loft(
            an,
            "plastico",
            fechado=True,
            tampa0=True,
            tampa1=True,
            ilhas=[{"j": (0, 10), "peso": 1.0}, {"j": (10, 11), "peso": 0.05}],
            peso_tampa=0.3,
            attrs={"xadrez": xad},
        )
        m.domo((sx * 8.2, 51.0, CZ), (sx, 0, 0), "aco", raio=3.6, altura=0.8, n=12, peso=0.5)

    # ---- pomo com a ranhura do ressalto (aberta atrÃ¡s) e a trava PLACEHOLDER
    y_pomo = TOT - L

    def pomo_xz(q):
        hx, z0, z1, r = 7.4, -12.2, 13.0, 2.5
        sw, sd = 3.3, 5.2
        dir_ = [(0.0, z0)]
        for a in (-90, -45, 0):
            t = math.radians(a)
            dir_.append((hx - r + r * math.cos(t), z0 + r + r * math.sin(t)))
        for a in (0, 45, 90):
            t = math.radians(a)
            dir_.append((hx - r + r * math.cos(t), z1 - r + r * math.sin(t)))
        dir_ += [
            (sw + 0.6, z1),
            (sw, z1 - 0.5),
            (sw, z1 - sd + 0.6),
            (sw - 0.6, z1 - sd),
            (0.0, z1 - sd),
        ]
        esq = [(-x, z) for x, z in dir_[1:-1]][::-1]
        pts = np.array(dir_ + esq)
        pts[:, 0] *= q
        pts[:, 1] = CZ + (pts[:, 1] - CZ) * q
        return pts

    an = [
        anel_xz(y, pomo_xz(q))
        for y, q in ((95.6, 0.97), (96.4, 1.0), (119.5, 1.0), (120.2, 0.97), (y_pomo, 0.9))
    ]
    m.loft(an, "aco", tampa0=True, tampa1=True, peso=0.8, peso_tampa=0.4)
    trava = ret_arred(1.0, 4.5, 0.8, 3)
    an = []
    for y, q in ((99.0, 0.55), (99.8, 1.0), (116.2, 1.0), (117.0, 0.55)):
        xz = np.column_stack([8.2 + trava[:, 0], -1.5 + trava[:, 1] * q])
        an.append(anel_xz(y, xz))
    m.loft(an, "aco", tampa0=True, tampa1=True, peso=0.5, peso_tampa=0.2)
    m.domo((9.2, 101.4, -1.5), (1, 0, 0), "aco", raio=1.4, altura=0.5, n=8, peso=0.3)
    m.dup_atual = 0

    # ---- bainha M8A1: boca de aÃ§o, corpo de fibra verde-oliva, suspensÃ³rio de lona
    m.no_atual = 1
    CZB = -0.75
    rr = []
    for y, s in ((-34.0, 0.93), (-33.0, 1.0), (-3.6, 1.0), (-3.0, 1.05), (-1.9, 1.05), (-1.5, 1.0)):
        rr.append(anel_xz(y, ret_arred(9.0 * s, 18.6 * s, 4.0 * s, 4), CZB))
    rr.append(anel_xz(-1.5, ret_arred(3.4, 14.5, 1.5, 4), CZB))
    rr.append(anel_xz(-5.0, ret_arred(3.4, 14.5, 1.5, 4), CZB))
    m.loft(
        rr,
        "aco",
        tampa0=True,
        tampa1=True,
        ilhas=[
            {"k": (0, 5), "peso": 0.5},
            {"k": (5, 6), "modo": "plano", "eu": (1, 0, 0), "ev": (0, 0, 1), "peso": 0.4},
            {"k": (6, 7), "peso": 0.2},
        ],
        peso_tampa=0.1,
    )
    SB = 206.0  # PLACEHOLDER

    def corpo(s):
        t = (s - 31.0) / (SB - 31.0)
        a = _lerp(17.8, 10.0, t**1.2)
        b = _lerp(8.2, 5.6, t)
        cz = _lerp(CZB, -1.5, t)
        f = 1.0
        if s > SB - 9.0:
            f = math.sqrt(max(0.0, 1 - ((s - (SB - 9.0)) / 9.0) ** 2))
        return anel_xz(-s, superelipse(a * max(f, 0.12), b * max(f, 0.12), 20, 2.8), cz)

    ss = estacoes(corpo, np.arange(31.0, SB - 0.3, 0.5), 0.06, fixas=[31.0, SB - 0.3])
    m.loft(
        [corpo(s) for s in ss],
        "fibra",
        ponta1=(0.0, -SB, -1.5),
        tampa0=True,
        ilhas=[{"j": (0, 10), "peso": 0.45}, {"j": (10, 20), "peso": 0.45}],
        peso_tampa=0.05,
    )
    # faixa de lona em volta da boca
    cam = ret_arred(10.0, 19.6, 5.0, 5)
    cam = np.column_stack([cam[:, 0], np.full(len(cam), -18.0), cam[:, 1] + CZB])
    perfil, atr = perfil_fita(2.0, 22.0, recuo=2.0)
    m.tubo(cam, perfil, "lona", normal0=(0.0, 0.0, -1.0), ciclo=True, peso=0.4)
    # suspensÃ³rio: sobe por trÃ¡s do cabo e dobra na barra do gancho
    xbar, ybar = -14.0, 80.0
    ctrl = [(-11.0, -28.0), (-11.0, -8.0), (-11.4, 0.0), (-11.6, 10.0), (-11.6, 76.0)]
    cam = [np.array([x, y, 0.0]) for x, y in ctrl]
    cam += arco_pts((xbar, ybar, 0.0), 2.6, 0, 180, 9, "xy")
    cam += [np.array([xbar - 2.6, 76.0, 0.0]), np.array([xbar - 2.6, 58.0, 0.0])]
    cam = simplificar(caminho_suave(cam, 1.0), 0.06)
    perfil, atr = perfil_fita(1.8, 30.0, recuo=2.0)
    m.tubo(
        cam,
        perfil,
        "lona",
        normal0=(1.0, 0.0, 0.0),
        peso=0.4,
        peso_tampa=0.2,
        costura=costura_tubo(cam, atr),
    )
    # gancho duplo de arame (tipo M1910)
    zh = 10.0
    ctrl = [
        (-20.0, 86.0, -zh),
        (-20.0, 93.0, -zh),
        (-18.6, 97.6, -zh),
        (-15.4, 97.6, -zh),
        (-14.0, 93.0, -zh),
        (-14.0, 83.0, -zh),
        (-14.0, 80.4, -zh + 1.0),
        (-14.0, 80.0, -zh + 4.0),
        (-14.0, 80.0, zh - 4.0),
        (-14.0, 80.4, zh - 1.0),
        (-14.0, 83.0, zh),
        (-14.0, 93.0, zh),
        (-15.4, 97.6, zh),
        (-18.6, 97.6, zh),
        (-20.0, 93.0, zh),
        (-20.0, 86.0, zh),
    ]
    gancho = simplificar(caminho_suave(ctrl, 0.8), 0.05)
    t = 2 * math.pi * np.arange(8) / 8
    m.tubo(
        gancho,
        np.column_stack([1.5 * np.cos(t), 1.5 * np.sin(t)]),
        "arame",
        normal0=(0.0, 0.0, 1.0),
        peso=0.35,
        peso_tampa=0.1,
    )
    topo_g = gancho[:, 1].max()
    # tira de retenÃ§Ã£o com botÃ£o em volta das placas do cabo
    tr = tira_retencao(m, 22.0, 9.45, 13.9, 16.0, 1.8, 10.1, "lona", "botao", cz=CZ)
    m.no_atual = 0

    pontos = {
        "Faca": {
            "punho": (0.0, (6.0 + 96.0) / 2, CZ),
            "guarda": (0.0, 0.0, (ZD + ZF) / 2),
            "ponta": bl["ponta"],
            "pomo": (0.0, y_pomo, CZ),
            "fio": (0.0, 0.0, -1.0),
            "anel": (0.0, 3.0, ZA),
            "anel_diametro_mm": 2 * RI,
            "comprimento_mm": TOT,
            "lamina_mm": L,
        },
        "Bainha": {
            "boca": (0.0, -1.5, CZB),
            "presilha": (-17.0, float(topo_g) - 1.5, 0.0),
            "ponta": (0.0, -SB, -1.5),
            "botao": tr["botao"],
        },
    }
    return Modelo("m6", m, pontos, {"estacoes_lamina": len(bl["estacoes"])})


# =================================================================== Tipo 56 (espigÃ£o)
def type56() -> Modelo:
    m = Malha()
    YP, RP = 14.0, 8.0  # eixo do pino da articulaÃ§Ã£o PLACEHOLDER
    S_LUVA0, S_LUVA1 = 3.0, 30.0  # luva de trava PLACEHOLDER
    S_ESP0, S_ESP1 = 34.0, 44.0  # transiÃ§Ã£o haste redonda -> espigÃ£o triangular
    S_PONTA = 267.0  # espigÃ£o de ~22,3 cm (S_PONTA - S_ESP1) PLACEHOLDER
    R_HASTE, R_ESP = 6.0, 7.6

    # ---- base articulada (bloco com a ponta traseira redonda em volta do pino)
    def anel_base(y):
        hz, hx = 8.0, 6.0
        if y > YP:
            hz = max(1.4, math.sqrt(max(0.0, RP**2 - (y - YP) ** 2)))
        return anel_xz(y, ret_arred(hx, hz, min(2.2, 0.6 * min(hx, hz)), 3))

    y_fim = YP + RP - 0.4
    ys = estacoes(anel_base, np.linspace(-1.0, y_fim, 300), 0.03, fixas=[-1.0, y_fim])
    m.loft(
        [anel_base(y) for y in ys], "aco_azul", tampa0=True, tampa1=True, peso=0.8, peso_tampa=0.3
    )
    for sx in (1, -1):
        m.domo((sx * 6.0, YP, 0.0), (sx, 0, 0), "aco_azul", raio=3.0, altura=0.9, n=12, peso=0.4)

    # ---- haste redonda que vira espigÃ£o de seÃ§Ã£o triangular com faces cÃ´ncavas
    n_face = 8
    ang_c = np.radians([-90.0, 30.0, 150.0])

    def tri(R):
        C = np.column_stack([np.cos(ang_c), np.sin(ang_c)]) * R
        pts = []
        for i in range(3):
            a, b = C[i], C[(i + 1) % 3]
            meio = (a + b) / 2
            dentro = -meio / max(np.linalg.norm(meio), 1e-9)
            for k in range(n_face):
                t = k / n_face
                p = a * (1 - t) + b * t + dentro * (0.13 * R) * math.sin(math.pi * t)
                pts.append(p)
        return np.array(pts)

    angs = np.arctan2(tri(1.0)[:, 1], tri(1.0)[:, 0])
    circ = np.column_stack([np.cos(angs), np.sin(angs)])

    def anel_esp(s):
        if s <= S_ESP0:
            xz = circ * R_HASTE
        else:
            u = (s - S_ESP1) / (S_PONTA - S_ESP1)
            R = R_ESP * (1 - max(0.0, u)) ** 0.9
            beta = float(suave(s, S_ESP0, S_ESP1))
            xz = circ * R_HASTE * (1 - beta) + tri(R) * beta
        return anel_xz(-s, xz)

    ss = estacoes(
        anel_esp,
        np.arange(-0.5, S_PONTA - 1.0, 0.5),
        0.04,
        fixas=[-0.5, S_ESP0, S_ESP1, S_PONTA - 1.0],
    )
    k_esp = int(np.searchsorted(ss, S_ESP1))
    nn = 3 * n_face
    m.loft(
        [anel_esp(s) for s in ss],
        "aco_azul",
        ponta1=(0.0, -S_PONTA, 0.0),
        tampa0=True,
        ilhas=[
            {"j": (0, n_face), "peso": 1.0},
            {"j": (n_face, 2 * n_face), "peso": 1.0},
            {"j": (2 * n_face, nn), "peso": 1.0},
        ],
        peso_tampa=0.05,
        vivas_j=[(j, k_esp, len(ss) - 1) for j in (0, n_face, 2 * n_face)],
    )

    # ---- luva de trava (com dois sulcos de pega) PLACEHOLDER
    a0, a1 = S_LUVA0, S_LUVA1
    perfil = [
        (R_HASTE, a0),
        (7.1, a0),
        (7.5, a0 + 0.4),
        (7.5, 9.4),
        (7.0, 9.9),
        (7.0, 10.9),
        (7.5, 11.4),
        (7.5, 20.4),
        (7.0, 20.9),
        (7.0, 21.9),
        (7.5, 22.4),
        (7.5, a1 - 0.4),
        (7.1, a1),
        (R_HASTE, a1),
    ]
    m.torno(
        perfil,
        "aco_azul",
        centro=(0, 0, 0),
        eixo=(0, -1, 0),
        ref=(0, 0, 1),
        n=24,
        ciclo=True,
        peso=0.9,
    )

    pontos = {
        "Faca": {
            "punho": (0.0, -(a0 + a1) / 2, 0.0),
            "guarda": (0.0, -S_ESP1, 0.0),
            "ponta": (0.0, -S_PONTA, 0.0),
            "pomo": (0.0, y_fim, 0.0),
            "fio": (0.0, 0.0, -1.0),
            "base": (0.0, YP, 0.0),
            "luva": (0.0, -(a0 + a1) / 2, 0.0),
            "comprimento_mm": y_fim + S_PONTA,
            "lamina_mm": S_PONTA - S_ESP1,
        },
    }
    return Modelo("type56", m, pontos, {})


# =================================================================== dao / rá»±a do VC
def dao() -> Modelo:
    m = Malha()
    L = 330.0  # PLACEHOLDER (30-35 cm)
    ZP = 2.0

    def topo(s):
        if s <= 290:
            return 9.0
        return 9.0 - 7.0 * ((s - 290) / (L - 290)) ** 1.6

    def fio(s):
        if s < 40:
            return _lerp(-13.0, -31.0, float(suave(s, 0.0, 40.0)))  # pescoÃ§o
        if s < 280:
            return -31.0 - 15.0 * ((s - 40) / 240) ** 1.15
        return -46.0 + (ZP + 46.0) * ((s - 280) / (L - 280)) ** 2.2

    def plunge(s):
        return float(suave(s, 30.0, 48.0))

    lam = lm.Lamina(
        L=L,
        topo=topo,
        fio=fio,
        esp=lambda s: _lerp(5.5, 3.0, max(0.0, s) / L),  # PLACEHOLDER
        bisel=lambda s: _lerp(1.2, 0.42 * (topo(s) - fio(s)), plunge(s)),
        e_fio=lambda s: _lerp(4.6, 0.8, plunge(s)),
        micro=1.6,
        chanfro=0.6,
        ponta_z=ZP,
        afiado=lambda s: float(suave(s, 32.0, 40.0)),
        meio=0.25,
        s_ini=-1.4,
    )
    bl = lm.construir(m, lam, "aco_forjado", passo=0.6, tol=0.05, fixas=[40.0, 280.0, 290.0])

    m.dup_atual = 1
    # ---- virola de ferro
    perfil = [
        (11.5, -1.5),
        (14.4, -1.5),
        (15.1, -0.9),
        (15.1, 1.2),
        (14.6, 2.0),
        (14.6, 21.0),
        (15.0, 21.6),
        (15.0, 23.4),
        (14.5, 24.0),
        (11.5, 24.0),
    ]
    m.torno(perfil, "ferro", eixo=(0, 1, 0), ref=(0, 0, 1), n=24, ciclo=True, peso=0.8)

    # ---- cabo de madeira (oval, engrossa para trÃ¡s, ponta arredondada) PLACEHOLDER 155 mm
    Y_FIM = 178.5

    def cabo_a(y):
        if y < 23.0:
            return 11.6
        if y < 168.0:
            return 14.4 + 1.4 * ((y - 23.0) / 145.0) ** 1.5
        f = math.sqrt(max(0.0, 1 - ((y - 168.0) / (Y_FIM - 168.0)) ** 2))
        return 15.8 * max(f, 0.05)

    def anel_cabo(y):
        a = cabo_a(y)
        b = a if y < 23.0 else 0.9 * a
        return anel_xz(y, superelipse(a, b, 22, 2.0))

    ys = estacoes(
        anel_cabo,
        np.concatenate([np.arange(-1.0, 22.9, 1.0), np.arange(23.0, Y_FIM - 0.3, 0.3)]),
        0.05,
        fixas=[-1.0, 22.0, 23.0, Y_FIM - 0.3],
    )
    k_bunda = int(np.searchsorted(ys, 174.0))
    m.loft(
        [anel_cabo(y) for y in ys],
        "madeira_cabo",
        ponta1=(0.0, Y_FIM, 0.0),
        tampa0=True,
        ilhas=[
            {"k": (0, k_bunda), "peso": 1.0},
            {
                "k": (k_bunda, len(ys) - 1),
                "modo": "plano",
                "eu": (1, 0, 0),
                "ev": (0, 0, 1),
                "peso": 0.8,
            },
        ],
        peso_tampa=0.3,
    )
    # ---- voltas de rotim (anÃ©is) no cabo PLACEHOLDER
    for y0, y1 in ((36.0, 52.0), (92.0, 104.0), (146.0, 162.0)):
        yc = (y0 + y1) / 2
        a = max(cabo_a(y) for y in np.linspace(y0, y1, 20))
        cam = anel_xz(yc, superelipse(a + 0.6, 0.9 * a + 0.6, 26, 2.0))
        m.tubo(
            cam,
            ret_arred(1.0, (y1 - y0) / 2, 0.8, 3),
            "rotim",
            normal0=(0.0, 0.0, -1.0),
            ciclo=True,
            peso=0.8,
        )
    m.dup_atual = 0

    # ---- bainha de madeira em duas metades com anÃ©is de rotim e alÃ§a de cordÃ£o
    m.no_atual = 1
    SB = 352.0  # PLACEHOLDER
    ZT = -14.0
    Y_BOCA = -2.0

    def b_top(s):
        return 16.0 if s <= 300 else 16.0 - (16.0 - ZT) * ((s - 300) / (SB - 300)) ** 1.8

    def b_bot(s):
        return -53.0 if s <= 280 else -53.0 + (53.0 - abs(ZT)) * ((s - 280) / (SB - 280)) ** 1.6

    def b_xh(s):
        return _lerp(8.4, 6.6, s / SB)

    def secao(top, bot, xh):
        h = top - bot
        r = min(1.6, 0.25 * h, 0.4 * xh)
        g = min(0.7, 0.1 * h)
        sd = [
            (0.55, top),
            (xh - r, top),
            (xh - 0.28 * r, top - 0.28 * r),
            (xh, top - r),
            (xh + 0.4, (top + bot) / 2),
            (xh, bot + r),
            (xh - 0.28 * r, bot + 0.28 * r),
            (xh - r, bot),
            (0.55, bot),
        ]
        return [(0.0, top - g)] + sd + [(0.0, bot + g)] + [(-x, z) for x, z in reversed(sd)]

    def anel_b(s):
        return anel_xz(Y_BOCA - s, secao(b_top(s), b_bot(s), b_xh(s)))

    ss = estacoes(anel_b, np.arange(0.0, SB - 0.5, 0.5), 0.08, fixas=[0.0, SB - 0.5])[::-1]
    an = [anel_b(s) for s in ss]
    k_boca = len(an) - 1
    an.append(anel_xz(Y_BOCA, secao(b_top(0) - 4.0, b_bot(0) + 4.0, 3.0)))
    an.append(anel_xz(Y_BOCA - 10.0, secao(b_top(0) - 4.0, b_bot(0) + 4.0, 3.0)))
    nb = len(an[0])
    m.loft(
        an,
        "madeira_bainha",
        ponta0=(0.0, Y_BOCA - SB, ZT),
        tampa1=True,
        ilhas=[
            {"k": (0, k_boca), "j": (0, nb // 2), "peso": 0.45},
            {"k": (0, k_boca), "j": (nb // 2, nb), "peso": 0.45},
            {
                "k": (k_boca, k_boca + 1),
                "modo": "plano",
                "eu": (1, 0, 0),
                "ev": (0, 0, 1),
                "peso": 0.35,
            },
            {"k": (k_boca + 1, k_boca + 2), "peso": 0.1},
        ],
        peso_tampa=0.05,
    )
    aneis_b = (28.0, 118.0, 208.0, 298.0)
    for s in aneis_b:
        top, bot, xh = b_top(s), b_bot(s), b_xh(s)
        cam = ret_arred(xh + 1.0, (top - bot) / 2 + 1.0, 3.0, 5)
        cam = np.column_stack(
            [cam[:, 0], np.full(len(cam), Y_BOCA - s), cam[:, 1] + (top + bot) / 2]
        )
        m.tubo(
            cam,
            ret_arred(1.1, 6.0, 0.8, 2),
            "rotim",
            normal0=(0.0, 0.0, -1.0),
            ciclo=True,
            peso=0.45,
        )
    # alÃ§a de cordÃ£o entre o 1Âº e o 2Âº anel, por trÃ¡s (-X)
    zc = (b_top(0) + b_bot(0)) / 2
    xb = -b_xh(60.0)
    ctrl = [
        (xb - 0.3, Y_BOCA - 26.0),
        (xb - 5.5, Y_BOCA - 33.0),
        (xb - 8.2, Y_BOCA - 48.0),
        (xb - 8.2, Y_BOCA - 98.0),
        (xb - 5.5, Y_BOCA - 113.0),
        (xb - 0.3, Y_BOCA - 120.0),
    ]
    cam = simplificar(caminho_suave([(x, y, zc) for x, y in ctrl], 1.0), 0.06)
    t = 2 * math.pi * np.arange(8) / 8
    m.tubo(
        cam,
        np.column_stack([2.3 * np.cos(t), 2.3 * np.sin(t)]),
        "cordao",
        normal0=(0.0, 0.0, 1.0),
        peso=0.4,
        peso_tampa=0.1,
    )
    m.no_atual = 0

    pontos = {
        "Faca": {
            "punho": (0.0, 100.0, 0.0),
            "guarda": (0.0, 0.0, (topo(0) + fio(0)) / 2),
            "ponta": bl["ponta"],
            "pomo": (0.0, Y_FIM, 0.0),
            "fio": (0.0, 0.0, -1.0),
            "comprimento_mm": Y_FIM + L,
            "lamina_mm": L,
        },
        "Bainha": {
            "boca": (0.0, Y_BOCA, zc),
            "presilha": (xb - 4.1, Y_BOCA - 73.0, zc),
            "ponta": (0.0, Y_BOCA - SB, ZT),
        },
    }
    return Modelo("dao", m, pontos, {"estacoes_lamina": len(bl["estacoes"])})


MODELOS = {"kabar": kabar, "m6": m6, "type56": type56, "dao": dao}
