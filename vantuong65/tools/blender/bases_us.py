"""Receitas da base dos EUA (USMC em Chu Lai, agosto de 1965). Catálogo, medidas e fontes em
`bases.py`; peças e materiais em `bases_comum.py`. Metros, Z para cima, frente em -Y."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bases_comum as B  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
from bases_comum import Receita, bloco, corda, grade, vara, viga  # noqa: E402

# GP Medium e GP Large (MIL-T-1712T; TM 10-8340-211-13): planta e caimento do telhado da fonte.
# Parede (beiral) de 2,35 m em vez de 1,68 m: o soldado do jogo tem 2,0 m e porta e barraca pedem
# vão livre de 2,3 m (decisão do dono, 2026-11-11). A cumeeira sobe junto (mesma inclinação).
PAREDE_JOGO = 2.35
GPM = {"L": 9.96, "W": 4.88, "hw": PAREDE_JOGO, "hr": PAREDE_JOGO + (3.05 - 1.68), "mastros": 2}
GPL = {"L": 15.85, "W": 5.49, "hw": PAREDE_JOGO, "hr": PAREDE_JOGO + (3.73 - 1.68), "mastros": 4}
PORTA_ALT = 2.4  # a fonte dá 6 pés (1,83 m); o jogo pede vão livre ≥ 2,3 m
PORTA_LARG = 1.2  # PLACEHOLDER (≥ 1,0 m de passagem)


# =============================================================== barraca GP
def barraca_gp(
    r: Receita,
    L,
    W,
    hw,
    hr,
    n_mastros,
    *,
    z0=0.0,
    portas=(True, True),
    lados_enrolados=False,
    mastros=True,
    paus_parede=True,
    cordas=True,
    sem=0,
    grupo="Lona",
    grupo_est="Interior",
    ov=0.10,
    res=0.12,
    res_baixo=0.35,
    colisao=True,
):
    """Barraca GP (de 4 águas, mastros centrais e cumeeira) com o comprido em Y e as portas nas
    cabeceiras (-Y = frente, +Y = fundo). Lona com barriga entre beiral e cumeeira, paredes de
    pé com o pé esticado pelas estacas, portas com as abas enroladas e amarradas, cordas do beiral
    até estacas a 1,5 m (PLACEHOLDER). Cumeeira = L - W (águas de mesma inclinação: derivado)."""
    ml = B.mat_lona(f"lona_gp_{sem}")
    mw = N.mat_madeira(f"mastro_{sem}", "#8d7656", "#5e4a33", "#7f776a", eixo="Y")
    mc = N.mat_corda(f"corda_{sem}", "#a29270")
    rid = L - W
    slant = math.hypot(W / 2, hr - hw)
    t0 = -ov / (W / 2)
    n_vaos = max(3, round(L / 1.65))

    def lona(res_):
        """Telhado e paredes de lona numa grade de `res_` m (a alta e a baixa usam a mesma
        forma: a baixa recebe o detalhe da alta no bake)."""
        nt = max(6, round(slant * (1 - t0) / res_))

        def deformar(P, n, a, t):
            k = math.sin(math.pi * a) ** 0.5 if 0.0 < a < 1.0 else 0.0
            if t >= 0:
                s = 0.05 * math.sin(math.pi * t) * k
                s += 0.008 * k * math.sin(math.pi * t) * M.fbm(P * 2.5, 3, sem)
            else:
                s = 0.02 * (t / t0) * k
            return P - n * s

        def lado(sx):
            n = Vector((sx * (hr - hw), 0, W / 2)).normalized()

            def f(a, b):
                t = t0 + b * (1 - t0)
                E = Vector((sx * W / 2, -L / 2 + a * L, z0 + hw))
                R = Vector((0, -rid / 2 + a * rid, z0 + hr))
                return deformar(E + (R - E) * t, n, a, t)

            return grade("telhado_lado", f, max(8, round(L / res_)), nt, fora=n)

        def ponta(sy):
            n = Vector((0, sy * (hr - hw), W / 2)).normalized()
            A = Vector((0, sy * rid / 2, z0 + hr))

            def f(a, b):
                t = t0 + b * (1 - t0)
                aa = a if sy < 0 else 1 - a
                E = Vector((-W / 2 + aa * W, sy * L / 2, z0 + hw))
                return deformar(E + (A - E) * t, n, a, t)

            return grade("telhado_ponta", f, max(6, round(W / res_)), nt, fora=n)

        telhado = M.juntar([lado(1), lado(-1), ponta(-1), ponta(1)], "telhado")
        B.fundir(telhado, 0.003)
        for sy, aberta in zip((-1, 1), portas, strict=True):
            if aberta:
                B.apagar_faces(
                    telhado,
                    lambda c, sy=sy: (
                        c.y * sy > L / 2 - 0.4
                        and abs(c.x) < PORTA_LARG / 2
                        and c.z < z0 + PORTA_ALT
                    ),
                )
        M.solidificar(telhado, 0.012, -1.0)

        def parede_lado(sx):
            def f(a, b):
                borda = math.sin(math.pi * a) ** 0.3
                bojo = (0.03 * (1 - b) ** 3 + 0.012 * abs(math.sin(math.pi * a * n_vaos))) * borda
                bojo *= 1 - b**4
                return (sx * (W / 2 + bojo), -L / 2 + a * L, z0 + 0.015 + b * (hw - 0.015))

            return grade(
                "parede_lado", f, max(8, round(L / res_)), max(5, round(hw / res_)), fora=(sx, 0, 0)
            )

        def parede_ponta(sy, aberta):
            def f(a, b):
                borda = math.sin(math.pi * a) ** 0.3
                bojo = 0.03 * (1 - b) ** 3 * borda * (1 - b**4)
                return (-W / 2 + a * W, sy * (L / 2 + bojo), z0 + 0.015 + b * (hw - 0.015))

            o = grade(
                "parede_ponta",
                f,
                max(6, round(W / res_)),
                max(5, round(hw / res_)),
                fora=(0, sy, 0),
            )
            if aberta:
                B.apagar_faces(o, lambda c: abs(c.x) < PORTA_LARG / 2)
            return o

        paredes = [parede_ponta(-1, portas[0]), parede_ponta(1, portas[1])]
        if not lados_enrolados:
            paredes += [parede_lado(1), parede_lado(-1)]
        pw = M.juntar(paredes, "paredes")
        M.deslocar(
            pw, lambda co, n: 0.006 * M.fbm(co * 3.0, 3, sem + 1) * (1 if co.z > z0 + 0.05 else 0)
        )
        M.solidificar(pw, 0.01, -1.0)
        return [M.material(M.suave(telhado, 45), ml), M.material(M.suave(pw, 45), ml)]

    for o in r.substituir(lona(res)):
        r.add(o, grupo)
    for o in lona(res_baixo):
        r.baixo(o, grupo)

    # abas das portas enroladas e amarradas
    for sy, aberta in zip((-1, 1), portas, strict=True):
        if not aberta:
            continue
        for sx in (-1, 1):
            x = sx * (PORTA_LARG / 2 + 0.07)
            y = sy * (L / 2 + 0.06)
            rolo = vara(
                "rolo_porta", (x, y, z0 + 0.3), (x, y, z0 + PORTA_ALT - 0.05), 0.07, 0.06, ml, 10, 6
            )
            M.deslocar(rolo, lambda co, n: 0.01 * M.fbm(co * 8, 2, sem + 2))
            r.add(rolo, grupo)
            for z in (z0 + 0.7, z0 + 1.4):
                laco = M.toro("laco", 0.072, 0.006, 16, 5)
                M.mover(laco, Matrix.Translation((x, y, z)))
                r.add(M.material(laco, mc), grupo_est)
    if lados_enrolados:
        for sx in (-1, 1):
            x = sx * (W / 2 + 0.07)
            rolo = vara(
                "rolo_lado",
                (x, -L / 2 + 0.1, z0 + hw - 0.1),
                (x, L / 2 - 0.1, z0 + hw - 0.1),
                0.085,
                0.08,
                ml,
                10,
                24,
            )
            M.deslocar(rolo, lambda co, n: 0.012 * M.fbm(co * 5, 2, sem + 3))
            r.add(rolo, grupo)
            for y in np.linspace(-L / 2 + 0.8, L / 2 - 0.8, max(3, round(L / 2.0))):
                laco = M.toro("laco", 0.09, 0.006, 16, 5)
                M.mover(
                    laco,
                    Matrix.Translation((x, float(y), z0 + hw - 0.1))
                    @ Matrix.Rotation(math.pi / 2, 4, "X"),
                )
                r.add(M.material(laco, mc), grupo_est)

    # mastros centrais e cumeeira
    if mastros:
        ys = [-rid / 2 + k * rid / (n_mastros - 1) for k in range(n_mastros)]
        for y in ys:
            r.add(
                vara("mastro", (0, y, z0), (0, y, z0 + hr - 0.04), 0.045, 0.04, mw, 10), grupo_est
            )
            if colisao:
                r.caixa(
                    f"Mastro{len(r.colisao)}",
                    (0, y, z0 + hr / 2),
                    (0.12, 0.12, hr),
                    "passa",
                    "Wood",
                )
        r.add(
            vara(
                "cumeeira",
                (0, -rid / 2 - 0.05, z0 + hr - 0.09),
                (0, rid / 2 + 0.05, z0 + hr - 0.09),
                0.04,
                mat=mw,
            ),
            grupo_est,
        )
    if paus_parede:
        for k in range(n_vaos + 1):
            y = -L / 2 + k * L / n_vaos
            for sx in (-1, 1):
                x = sx * (W / 2 - 0.04)
                r.add(
                    vara("pau_parede", (x, y, z0), (x, y, z0 + hw + 0.03), 0.022, mat=mw, segs=8),
                    grupo_est,
                )
    if cordas:
        for k in range(n_vaos + 1):
            y = -L / 2 + k * L / n_vaos
            for sx in (-1, 1):
                a = (sx * (W / 2 + ov * 0.9), y, z0 + hw - 0.04)
                b = (sx * (W / 2 + 1.5), y, 0.05)
                r.add(corda("corda", a, b, 0.02, 0.005, mc, 6, 4), grupo_est)
                r.add(
                    bloco(
                        "estaca",
                        (0.035, 0.025, 0.32),
                        (b[0] + sx * 0.03, y, 0.12),
                        mw,
                        rot=(0, -sx * 0.35, 0),
                    ),
                    grupo_est,
                )
        for sy in (-1, 1):
            for x in (-W / 2 + 0.6, W / 2 - 0.6):
                a = (x, sy * (L / 2 + ov * 0.9), z0 + hw - 0.04)
                b = (x, sy * (L / 2 + 1.5), 0.05)
                r.add(corda("corda", a, b, 0.02, 0.005, mc, 6, 4), grupo_est)
                r.add(
                    bloco(
                        "estaca",
                        (0.025, 0.035, 0.32),
                        (x, b[1] + sy * 0.03, 0.12),
                        mw,
                        rot=(sy * 0.35, 0, 0),
                    ),
                    grupo_est,
                )

    if colisao:
        if not lados_enrolados:
            for sx in (-1, 1):
                r.caixa(
                    f"Parede{'Dir' if sx > 0 else 'Esq'}",
                    (sx * W / 2, 0, z0 + hw / 2),
                    (0.12, L, hw),
                    "passa",
                    "Canvas",
                )
        for sy, aberta, nome in ((-1, portas[0], "Frente"), (1, portas[1], "Fundo")):
            if aberta:
                lx = (W - PORTA_LARG) / 2
                for sx in (-1, 1):
                    r.caixa(
                        f"{nome}{'Dir' if sx > 0 else 'Esq'}",
                        (sx * (PORTA_LARG / 2 + lx / 2), sy * L / 2, z0 + hw / 2),
                        (lx, 0.12, hw),
                        "passa",
                        "Canvas",
                    )
            else:
                r.caixa(nome, (0, sy * L / 2, z0 + hw / 2), (W, 0.12, hw), "passa", "Canvas")
    return {"mw": mw, "ml": ml, "mc": mc}


def catres(r, posicoes, grupo="Interior", sem=0, cobertor=True, sacos=True, z0=0.0, baus=False):
    """Catres em (x, y, rot_z) sobre o piso em z0; manta dobrada nos pés, saco de lona ao lado e,
    com `baus`, baú de madeira entre um catre e o seguinte (PLACEHOLDER)."""
    mw = N.mat_madeira("catre_madeira", "#9b8058", "#6d5538", "#8b7f6a")
    mlc = B.mat_lona("catre_lona", "#5b5d40", "#6f6c52")
    manta = N.mat_pano("manta_od", "#4a4b33", "#5f5d45")
    saco_m = B.mat_lona("saco_lona", "#5d5e43", "#77745a")
    bau = N.mat_caixote("bau", "#4f5533")
    rng = np.random.default_rng(sem)
    for i, (x, y, rz) in enumerate(posicoes):
        pecas = B.catre(f"catre{i}", mat_madeira=mw, mat_lona_=mlc)
        if cobertor:
            pecas.append(B.manta_dobrada("manta", (0.55, 0.42, 0.07), (0, 0.62, 0.47), manta, i))
        rot = Matrix.Translation((x, y, z0)) @ Matrix.Rotation(rz, 4, "Z")
        for o in pecas:
            M.mover(o, rot)
            r.add(o, grupo)
        transversal = abs(math.sin(rz)) > 0.5
        dim = (1.9, 0.7) if transversal else (0.7, 1.9)
        r.caixa(f"Catre{i}", (x, y, z0 + 0.23), (*dim, 0.46), "passa", "Wood")
        if baus:
            yb = y + 0.78
            r.add(bloco("bau", (0.8, 0.4, 0.33), (x, yb, z0 + 0.165), bau, 0.01), grupo)
            r.caixa(f"Bau{i}", (x, yb, z0 + 0.165), (0.8, 0.4, 0.33), "para", "Wood")
        elif sacos and rng.random() < 0.7:
            lado = 1 if rng.random() < 0.5 else -1
            off = rot @ Vector((lado * 0.55, -0.3, 0.14))
            r.add(
                B.saco_de_lona("saco", 0.85, 0.17, off, rz + rng.uniform(-0.2, 0.2), saco_m, i),
                grupo,
            )


# =============================================================== barracas
def receita_us_tent_gp_medium():
    """GP Medium de alojamento no chão: 6 catres ao longo das paredes (corredor central de 3,4 m,
    acima de 1,0 m para o soldado de 2,0 m), mantas e sacos."""
    r = Receita()
    g = GPM
    barraca_gp(r, g["L"], g["W"], g["hw"], g["hr"], g["mastros"], sem=1)
    pos = []
    for sx in (-1, 1):
        for y in (-3.2, 0.0, 3.2):
            pos.append((sx * (g["W"] / 2 - 0.05 - 0.34), y, 0.0 if sx > 0 else math.pi))
    catres(r, pos, sem=1)
    return r


def receita_us_tent_gp_large():
    """GP Large sobre strongback (piso de tábuas elevado, caibros e montantes de madeira por
    dentro), com 12 catres e baús. Strongback em Chu Lai a partir de julho de 1965 (NMCB 10)."""
    r = Receita()
    g = GPL
    L, W, hw, hr = g["L"], g["W"], g["hw"], g["hr"]
    z0 = 0.30
    barraca_gp(
        r,
        L,
        W,
        hw,
        hr,
        g["mastros"],
        z0=z0,
        mastros=False,
        paus_parede=False,
        sem=2,
        res_baixo=0.4,
    )
    mw = N.mat_madeira("strongback", "#a88a62", "#76603f", "#8f8775", largura_tabua=0.15, eixo="Y")
    mwx = N.mat_madeira("strongback_x", "#a88a62", "#76603f", "#8f8775", eixo="X")
    # piso e estrado
    r.add(bloco("piso", (W + 0.3, L + 0.3, 0.05), (0, 0, z0 - 0.025), mw, 0.004), "Interior")
    for sx in (-1, 0, 1):
        r.add(
            bloco(
                "viga_piso",
                (0.1, L + 0.2, z0 - 0.05),
                (sx * (W / 2 - 0.05), 0, (z0 - 0.05) / 2),
                mwx,
                0.003,
            ),
            "Interior",
        )
    for sy in (-1, 1):
        r.add(
            bloco(
                "testeira",
                (W + 0.3, 0.05, z0 - 0.05),
                (0, sy * (L / 2 + 0.125), (z0 - 0.05) / 2),
                mwx,
                0.003,
            ),
            "Interior",
        )
        for k, (dy, h) in enumerate(((0.35, 0.10), (0.7, 0.20))):
            r.add(
                bloco(
                    "degrau",
                    (1.4, 0.36, h),
                    (0, sy * (L / 2 + 0.15 + dy - 0.18 * (k + 1) + 0.18), h / 2),
                    mw,
                    0.004,
                ),
                "Interior",
            )
            r.caixa(
                f"Degrau{'F' if sy < 0 else 'T'}{k}",
                (0, sy * (L / 2 + 0.15 + dy - 0.18 * k), h / 2),
                (1.4, 0.36, h),
                "para",
                "Wood",
            )
    r.caixa("Piso", (0, 0, z0 / 2), (W + 0.3, L + 0.3, z0), "para", "Wood")
    # estrutura: montantes nas paredes, caibros e cumeeira a cada 1,22 m (PLACEHOLDER)
    n = round(L / 1.22)
    rid = L - W
    for k in range(n + 1):
        y = -L / 2 + k * L / n
        for sx in (-1, 1):
            x = sx * (W / 2 - 0.06)
            r.add(viga("montante", (x, y, z0), (x, y, z0 + hw), 0.05, 0.09, mwx), "Interior")
            yc = max(-rid / 2, min(rid / 2, y))
            topo = (0, yc, z0 + hr - 0.1) if abs(y) <= rid / 2 + 1e-6 else None
            if topo is not None:
                r.add(viga("caibro", (x, y, z0 + hw - 0.04), topo, 0.05, 0.1, mwx), "Interior")
    r.add(
        viga(
            "cumeeira", (0, -rid / 2, z0 + hr - 0.12), (0, rid / 2, z0 + hr - 0.12), 0.05, 0.14, mwx
        ),
        "Interior",
    )
    for sy in (-1, 1):
        for sx in (-1, 1):
            r.add(
                viga(
                    "espigao",
                    (sx * (W / 2 - 0.06), sy * (L / 2 - 0.06), z0 + hw - 0.04),
                    (0, sy * rid / 2, z0 + hr - 0.1),
                    0.05,
                    0.1,
                    mwx,
                ),
                "Interior",
            )
    # 12 catres de cabeceira na parede, baú entre um catre e o seguinte
    pos = []
    for sx in (-1, 1):
        for k in range(6):
            y = -6.0 + k * 2.24
            pos.append((sx * (W / 2 - 0.12 - 0.95), y, math.pi / 2 if sx > 0 else -math.pi / 2))
    catres(r, pos, sem=2, z0=z0, baus=True)
    return r


def receita_us_command_tent():
    """Barraca de comando (COC): GP Medium com porta só na frente, mureta de sacos de areia em
    volta, mesa de mapa sobre cavaletes, escrivaninha de campanha com rádios AN/PRC-10 e telefones
    de campanha, quadro de mapa, e duas antenas RC-292 nos cantos do fundo."""
    r = Receita()
    g = GPM
    L, W = g["L"], g["W"]
    barraca_gp(r, L, W, g["hw"], g["hr"], g["mastros"], portas=(True, False), sem=3)
    # mureta de sacos (8 fiadas ~ 0,96 m) a 0,45 m das paredes, aberta na porta
    juta = N.mat_juta("juta_coc", "#a3916a", "#6c5c40", "#5a4a33", z_sujo=0.35)
    xo, yo = W / 2 + 0.45, L / 2 + 0.45
    gap = 0.9
    sacos = []
    sacos += B.sacos_linha((-xo, -yo), (-gap, -yo), 0, 8, sem=31)
    sacos += B.sacos_linha((gap, -yo), (xo, -yo), 0, 8, sem=32)
    sacos += B.sacos_linha((-xo, yo), (xo, yo), 0, 8, sem=33)
    sacos += B.sacos_linha((-xo, -yo + 0.25), (-xo, yo - 0.25), 0, 8, sem=34)
    sacos += B.sacos_linha((xo, -yo + 0.25), (xo, yo - 0.25), 0, 8, sem=35)
    r.substituir([r.add(B.sacos_juntar(sacos, "mureta", juta), "Sacos")])
    h = 0.045 + 0.115 * 8
    ht = 0.045 + 0.115 * 7 + 0.074  # topo dos sacos da última fiada
    r.baixo_caixas(
        [
            ((-xo - 0.14, -yo - 0.14, 0), (-gap + 0.02, -yo + 0.14, ht)),
            ((gap - 0.02, -yo - 0.14, 0), (xo + 0.14, -yo + 0.14, ht)),
            ((-xo - 0.14, yo - 0.14, 0), (xo + 0.14, yo + 0.14, ht)),
            ((-xo - 0.14, -yo + 0.14, 0), (-xo + 0.14, yo - 0.14, ht)),
            ((xo - 0.14, -yo + 0.14, 0), (xo + 0.14, yo - 0.14, ht)),
        ],
        "Sacos",
    )
    for nome, lo, hi in (
        ("SacosFrenteEsq", (-xo - 0.15, -yo - 0.15, 0), (-gap + 0.05, -yo + 0.15, h)),
        ("SacosFrenteDir", (gap - 0.05, -yo - 0.15, 0), (xo + 0.15, -yo + 0.15, h)),
        ("SacosFundo", (-xo - 0.15, yo - 0.15, 0), (xo + 0.15, yo + 0.15, h)),
        ("SacosEsq", (-xo - 0.15, -yo, 0), (-xo + 0.15, yo, h)),
        ("SacosDir", (xo - 0.15, -yo, 0), (xo + 0.15, yo, h)),
    ):
        r.caixa_lim(nome, lo, hi, bala="para", material="Sandbag")
    # mesa de mapa: compensado de 2,4 x 1,2 m (8 x 4 pés) sobre cavaletes, a 0,9 m
    comp = B.mat_compensado("compensado")
    mw = N.mat_madeira("cavalete", "#9b8058", "#6d5538", "#8b7f6a")
    r.add(bloco("tampo", (1.2, 2.4, 0.02), (0, 0, 0.9), comp, 0.003), "Interior")
    for y in (-0.85, 0.85):
        r.add(bloco("trave", (1.0, 0.09, 0.09), (0, y, 0.845), mw, 0.003), "Interior")
        for sx in (-1, 1):
            for sy in (-1, 1):
                r.add(
                    viga(
                        "perna",
                        (sx * 0.42, y, 0.82),
                        (sx * 0.5, y + sy * 0.18, 0.0),
                        0.05,
                        0.05,
                        mw,
                    ),
                    "Interior",
                )
    r.add(bloco("mapa", (1.0, 1.6, 0.002), (0.02, 0.1, 0.912), B.mat_mapa("mapa")), "Interior")
    r.add(
        bloco(
            "acetato",
            (0.7, 0.9, 0.001),
            (-0.12, -0.2, 0.9135),
            B.mat_tinta_lisa("acetato", "#c9c8bd", 0.2, 0.05),
        ),
        "Interior",
    )
    r.caixa("Mesa", (0, 0, 0.46), (1.2, 2.4, 0.92), "passa", "Wood")
    # escrivaninha de campanha e mesa dos rádios no fundo
    od = N.mat_tinta("radio_od", "#4f5434", desgaste=0.4, escala=200.0)
    r.add(
        bloco(
            "escrivaninha",
            (0.9, 0.55, 0.76),
            (1.45, 3.7, 0.38),
            N.mat_caixote("escrivaninha", "#53593a"),
            0.01,
        ),
        "Interior",
    )
    r.add(bloco("mesa_radio", (1.8, 0.7, 0.03), (-1.2, 3.6, 0.76), comp, 0.003), "Interior")
    for x in (-2.0, -0.4):
        for y in (3.3, 3.9):
            r.add(bloco("perna_r", (0.05, 0.05, 0.75), (x, y, 0.375), mw, 0.002), "Interior")
    for i, x in enumerate((-1.75, -1.25)):
        r.add(bloco("prc10", (0.27, 0.12, 0.40), (x, 3.65, 0.975), od, 0.012), "Interior")
        r.add(
            vara(
                "antena_prc10",
                (x + 0.08, 3.65, 1.17),
                (x + 0.1, 3.62, 2.2),
                0.004,
                0.003,
                B.mat_tinta_lisa(f"antena{i}", "#2c2c28"),
                6,
            ),
            "Interior",
        )
    fone = N.mat_tinta("ee8", "#5b4a33", desgaste=0.3, escala=200.0)
    for x in (-0.75, 1.3):
        r.add(
            bloco(
                "ee8",
                (0.27, 0.12, 0.22),
                (x, 3.62 if x < 0 else 3.65, 0.885 if x < 0 else 0.87),
                fone,
                0.015,
            ),
            "Interior",
        )
    r.caixa("Radios", (-1.2, 3.6, 0.4), (1.8, 0.7, 0.8), "passa", "Wood")
    r.caixa("Escrivaninha", (1.45, 3.7, 0.38), (0.9, 0.55, 0.76), "passa", "Wood")
    # quadro de mapa em cavalete
    r.add(
        bloco("quadro", (1.2, 0.02, 0.9), (1.5, 1.6, 1.35), comp, 0.003, rot=(0.15, 0, 0)),
        "Interior",
    )
    r.add(
        bloco(
            "mapa2", (1.1, 0.002, 0.8), (1.5, 1.588, 1.35), B.mat_mapa("mapa2"), rot=(0.15, 0, 0)
        ),
        "Interior",
    )
    for x in (1.0, 2.0):
        r.add(viga("pe_quadro", (x, 1.68, 1.85), (x, 1.5, 0.0), 0.04, 0.04, mw), "Interior")
    r.add(viga("pe_quadro_t", (1.5, 1.7, 1.75), (1.5, 2.2, 0.0), 0.04, 0.04, mw), "Interior")
    # antenas RC-292 nos cantos do fundo (TM 11-5820-348-15: mastro de 30 pés em 12 seções)
    aco = N.mat_tinta("mastro_rc292", "#4e5233", desgaste=0.5, escala=120.0)
    fio = B.mat_tinta_lisa("elemento", "#8b8b84", 0.35)
    mc = N.mat_corda("estai", "#9a8a66")
    for sx in (-1, 1):
        ax, ay = sx * (W / 2 + 1.0), L / 2 + 1.0
        topo = 9.14
        r.add(vara("mastro", (ax, ay, 0.0), (ax, ay, topo), 0.022, 0.02, aco, 10), "Antenas")
        for k in range(1, 12):
            z = k * topo / 12
            r.add(B.cilindro("luva", 0.026, 0.05, (ax, ay, z), aco, 10), "Antenas")
        r.add(B.cilindro("base_ant", 0.08, 0.06, (ax, ay, topo + 0.03), aco, 12), "Antenas")
        r.add(
            vara(
                "radiador", (ax, ay, topo + 0.06), (ax, ay, topo + 0.06 + 1.9), 0.007, 0.004, fio, 6
            ),
            "Antenas",
        )
        for k in range(3):
            ang = math.radians(90 + sx * 30 + k * 120)
            d = Vector((math.cos(ang), math.sin(ang), 0)) * math.sin(math.radians(140))
            d.z = math.cos(math.radians(140))
            p0 = Vector((ax, ay, topo + 0.04))
            r.add(vara("radial", p0, p0 + d * 1.9, 0.006, 0.004, fio, 6), "Antenas")
        for k in range(3):
            ang = math.radians(45 if sx > 0 else 135) + k * 2 * math.pi / 3
            b = (ax + 4.0 * math.cos(ang), ay + 4.0 * math.sin(ang), 0.05)
            r.add(corda("estai", (ax, ay, 4.57), b, 0.05, 0.004, mc, 8, 4), "Antenas")
            r.add(bloco("estaca_ant", (0.04, 0.04, 0.35), (b[0], b[1], 0.12), mw), "Antenas")
        r.caixa(
            f"Mastro{'Dir' if sx > 0 else 'Esq'}",
            (ax, ay, topo / 2),
            (0.1, 0.1, topo),
            "passa",
            "Metal",
        )
    return r


def receita_us_mess_tent():
    """Refeitório de campanha: GP Large com as paredes laterais enroladas no beiral, mesas e bancos
    de campanha, linha de servir com fogões M-59 e caldeirões, e lavagem de marmitas fora (3 latas
    de 32 galões com aquecedor de imersão)."""
    r = Receita()
    g = GPL
    L, W = g["L"], g["W"]
    barraca_gp(r, L, W, g["hw"], g["hr"], g["mastros"], lados_enrolados=True, sem=4, res_baixo=0.4)
    mw = N.mat_madeira("mesa_campanha", "#a58a62", "#755c3e", "#8f8775", largura_tabua=0.15)
    pe = N.mat_madeira("pe_mesa", "#8d7656", "#5e4a33", "#7f776a", eixo="Y")
    for sx in (-1, 1):
        xm = sx * 1.35
        for k, y in enumerate((-5.0, -2.5, 0.0)):
            r.add(bloco("mesa", (0.75, 1.8, 0.04), (xm, y, 0.74), mw, 0.004), "Interior")
            for dx in (-0.3, 0.3):
                for dy in (-0.75, 0.75):
                    r.add(
                        bloco("perna", (0.045, 0.045, 0.72), (xm + dx, y + dy, 0.36), pe, 0.002),
                        "Interior",
                    )
            r.caixa(f"Mesa{sx}{k}", (xm, y, 0.38), (0.75, 1.8, 0.76), "passa", "Wood")
            for db in (-0.6, 0.6):
                r.add(bloco("banco", (0.25, 1.8, 0.04), (xm + db, y, 0.44), mw, 0.003), "Interior")
                for dy in (-0.75, 0.75):
                    r.add(
                        bloco("pe_banco", (0.18, 0.04, 0.42), (xm + db, y + dy, 0.21), pe, 0.002),
                        "Interior",
                    )
                r.caixa(
                    f"Banco{sx}{k}{'a' if db < 0 else 'b'}",
                    (xm + db, y, 0.23),
                    (0.25, 1.8, 0.46),
                    "passa",
                    "Wood",
                )
    # linha de servir: mesa com caldeirões e 2 fogões M-59 atrás (gabinete 42 x 24 x 27 pol,
    # TM 10-7360-204-13&P, só trecho de busca: medida parcial)
    r.add(bloco("mesa_servir", (2.6, 0.75, 0.04), (0, 3.6, 0.86), mw, 0.004), "Interior")
    for x in (-1.2, 1.2):
        for y in (3.3, 3.9):
            r.add(bloco("perna_s", (0.05, 0.05, 0.84), (x, y, 0.42), pe, 0.002), "Interior")
    r.caixa("MesaServir", (0, 3.6, 0.44), (2.6, 0.75, 0.88), "passa", "Wood")
    lata = N.mat_aco("caldeirao", "#a4a6a3", 0.35, 120.0)
    for x in (-0.85, 0.0, 0.85):
        r.add(B.cilindro("caldeirao", 0.18, 0.36, (x, 3.6, 1.06), lata, 24), "Interior")
        r.add(B.cilindro("tampa_c", 0.185, 0.02, (x, 3.6, 1.25), lata, 24), "Interior")
    fogao = N.mat_tinta("m59", "#4b4f34", desgaste=0.6, escala=150.0)
    for x in (-0.75, 0.75):
        r.add(bloco("m59", (1.07, 0.61, 0.69), (x, 5.35, 0.345), fogao, 0.01), "Interior")
        r.add(B.cilindro("panela", 0.2, 0.3, (x - 0.2, 5.35, 0.84), lata, 20), "Interior")
        r.add(
            bloco(
                "chapa",
                (0.4, 0.5, 0.02),
                (x + 0.3, 5.35, 0.70),
                N.mat_aco("chapa", "#3b3a36", 0.6, 150.0),
            ),
            "Interior",
        )
        r.caixa(
            f"Fogao{'E' if x < 0 else 'D'}", (x, 5.35, 0.35), (1.07, 0.61, 0.7), "para", "Metal"
        )
    # lavagem de marmitas: 3 latas de 32 galões (PLACEHOLDER Ø 0,54 x 0,68 m) com aquecedor
    gi = N.mat_aco("lata_gi", "#8e908c", 0.45, 80.0)
    aq = N.mat_tinta("aquecedor", "#4b4f34", desgaste=0.6, escala=150.0)
    xs = -(W / 2 + 1.2)
    for k, y in enumerate((-5.6, -4.6, -3.6)):
        perfil = [(0.0, 0.0), (0.25, 0.0), (0.27, 0.02)]
        for z in (0.17, 0.34, 0.51):
            perfil += [(0.27, z - 0.02), (0.278, z), (0.27, z + 0.02)]
        perfil += [(0.27, 0.66), (0.275, 0.68), (0.262, 0.68), (0.262, 0.6), (0.0, 0.6)]
        r.add(
            M.material(
                M.suave(M.mover(M.torno("lata", perfil, 32), Matrix.Translation((xs, y, 0))), 45),
                gi,
            ),
            "Interior",
        )
        r.add(B.cilindro("agua", 0.255, 0.01, (xs, y, 0.6), N.mat_oleo("agua_suja")), "Interior")
        r.add(B.cilindro("aquecedor", 0.07, 0.75, (xs + 0.12, y, 0.55), aq, 14), "Interior")
        r.add(B.cilindro("tanque_aq", 0.09, 0.2, (xs + 0.12, y + 0.2, 0.92), aq, 14), "Interior")
        r.add(
            vara("chamine", (xs + 0.12, y, 0.9), (xs + 0.12, y, 1.25), 0.04, 0.035, aq, 10),
            "Interior",
        )
        r.caixa(f"LataGI{k}", (xs, y, 0.4), (0.6, 0.6, 0.8), "para", "Metal")
    return r


# =============================================================== bunker e torre
def receita_us_bunker():
    """Bunker de sacos de areia: paredes de 2 sacos de espessura, seteira na frente, teto de
    toras com 2 camadas de sacos, porta no fundo protegida por um anteparo em L. Medidas de
    projeto (PLACEHOLDER): 3,8 x 3,8 m por fora, pé-direito de 2,35 m e porta de 1,25 m (o
    soldado do jogo tem 2,0 m: vão ≥ 2,3 m e passagem ≥ 1,0 m), seteira de 1,50 a 1,72 m."""
    r = Receita()
    juta = N.mat_juta("juta_bunker", "#a3916a", "#6c5c40", "#5a4a33", z_sujo=0.4)
    tora = N.mat_madeira("tora", "#7a6448", "#4f3e2b", "#6f6658", eixo="Z")
    E = 1.9
    esp = 0.56
    fi = 20
    hp = 0.045 + 0.115 * fi  # ~2,345 m
    p0, p1 = -0.15, 1.1  # vão da porta (interseção das fiadas pares e ímpares)
    s0_, s1_ = 1.50, 1.725  # seteira (fiadas 13 e 14)
    sacos = []

    def seteira(s0, s1, z, r_):
        return 1.5 < z < 1.7 and s1 - E > -0.6 and s0 - E < 0.6

    def porta(s0, s1, z, r_):
        return s1 - E > 0.0 + 1e-3 and s0 - E < 1.1 - 1e-3

    sacos += B.sacos_linha(
        (-E, -E + 0.28), (E, -E + 0.28), 0, fi, fileiras=2, sem=41, pular=seteira
    )
    sacos += B.sacos_linha((-E, E - 0.28), (E, E - 0.28), 0, fi, fileiras=2, sem=42, pular=porta)
    for sx in (-1, 1):
        sacos += B.sacos_linha(
            (sx * (E - 0.28), -E + esp), (sx * (E - 0.28), E - esp), 0, fi, fileiras=2, sem=43 + sx
        )
    # anteparo em L atrás da porta (1,4 m), com passagem de 1,1 m entre ele e a parede
    ya = E + 1.3
    sacos += B.sacos_linha((-0.7, ya), (1.85, ya), 0, 12, fileiras=1, sem=47)
    sacos += B.sacos_linha((1.85, E + 0.1), (1.85, ya - 0.14), 0, 12, fileiras=1, sem=48)
    # teto: toras (Ø 0,2 m) e 2 camadas de sacos
    zt = hp + 0.1
    for k in range(15):
        y = -E + 0.15 + k * (2 * E - 0.3) / 14
        r.add(
            vara("tora", (-E - 0.05, y, zt), (E + 0.05, y, zt), 0.1, 0.095, tora, 10), "Estrutura"
        )
    sacos += B.sacos_linha((-E, 0), (E, 0), zt + 0.08, 2, fileiras=14, sem=49)
    r.substituir([r.add(B.sacos_juntar(sacos, "sacos", juta), "Sacos")])
    topo = 0.045 + 0.115 * (fi - 1) + 0.074  # topo dos sacos da última fiada
    ha_ = 0.045 + 0.115 * 11 + 0.074
    r.baixo_caixas(
        [
            ((-E, -E, 0), (E, -E + esp, s0_)),
            ((-E, -E, s1_), (E, -E + esp, topo)),
            ((-E, -E, s0_), (-0.65, -E + esp, s1_)),
            ((0.65, -E, s0_), (E, -E + esp, s1_)),
            ((-E, E - esp, 0), (p0, E, topo)),
            ((p1, E - esp, 0), (E, E, topo)),
            ((-E, -E + esp, 0), (-E + esp, E - esp, topo)),
            ((E - esp, -E + esp, 0), (E, E - esp, topo)),
            ((-E, -E, zt + 0.08), (E, E, zt + 0.31)),
            ((-0.7, ya - 0.14, 0), (1.99, ya + 0.14, ha_)),
            ((1.71, E + 0.05, 0), (1.99, ya - 0.14, ha_)),
        ],
        "Sacos",
    )
    # batentes da porta e prateleira de tiro (logo abaixo da seteira)
    for x in (p0 - 0.06, p1 + 0.06):
        r.add(
            bloco("batente", (0.12, 0.12, hp), (x, E - esp - 0.06, hp / 2), tora, 0.01),
            "Estrutura",
        )
    r.add(
        bloco("prateleira", (1.4, 0.3, 0.04), (0, -E + esp + 0.15, 1.4), tora, 0.004), "Estrutura"
    )
    for x in (-0.6, 0.6):
        r.add(
            bloco("pe_prat", (0.08, 0.08, 1.38), (x, -E + esp + 0.15, 0.69), tora, 0.004),
            "Estrutura",
        )
    # colisão
    fy0, fy1 = -E - 0.05, -E + esp
    r.caixa_lim("FrenteBaixo", (-E, fy0, 0), (E, fy1, s0_), material="Sandbag")
    r.caixa_lim("FrenteAlto", (-E, fy0, s1_), (E, fy1, hp), material="Sandbag")
    r.caixa_lim("SeteiraEsq", (-E, fy0, s0_), (-0.65, fy1, s1_), material="Sandbag")
    r.caixa_lim("SeteiraDir", (0.65, fy0, s0_), (E, fy1, s1_), material="Sandbag")
    r.caixa_lim("FundoEsq", (-E, E - esp, 0), (p0, E + 0.05, hp), material="Sandbag")
    r.caixa_lim("FundoDir", (p1, E - esp, 0), (E, E + 0.05, hp), material="Sandbag")
    r.caixa_lim("LadoEsq", (-E - 0.05, -E + esp, 0), (-E + esp, E - esp, hp), material="Sandbag")
    r.caixa_lim("LadoDir", (E - esp, -E + esp, 0), (E + 0.05, E - esp, hp), material="Sandbag")
    r.caixa_lim(
        "Teto", (-E - 0.05, -E - 0.05, hp), (E + 0.05, E + 0.05, zt + 0.35), material="Sandbag"
    )
    ha = 0.045 + 0.115 * 12
    r.caixa_lim("Anteparo", (-0.7, ya - 0.14, 0), (1.99, ya + 0.14, ha), material="Sandbag")
    r.caixa_lim("AnteparoLado", (1.71, E + 0.05, 0), (1.99, ya - 0.14, ha), material="Sandbag")
    r.caixa("Prateleira", (0, -E + esp + 0.15, 0.71), (1.4, 0.3, 1.42), "passa", "Wood")
    return r


def receita_us_watchtower():
    """Torre de vigia de madeira (PLACEHOLDER: plataforma a 4,5 m, 2,4 x 2,4 m): 4 pernas de
    15 x 15 cm, contraventamento em X, piso de tábuas, parapeito de sacos, escada de mão no fundo
    e telhado de chapa ondulada."""
    r = Receita()
    mw = N.mat_madeira("torre", "#8a7356", "#5c4934", "#7d7466", eixo="Z")
    mwx = N.mat_madeira("torre_x", "#8a7356", "#5c4934", "#7d7466", eixo="X", largura_tabua=0.15)
    zinco = B.mat_zinco("zinco_torre", 0.5)
    juta = N.mat_juta("juta_torre", "#a3916a", "#6c5c40", "#5a4a33", z_sujo=0.1)
    a = 1.1
    zp = 4.5
    alto = {(-1, -1): 7.25, (1, -1): 7.25, (-1, 1): 7.0, (1, 1): 7.0}
    for (sx, sy), h in alto.items():
        r.add(bloco("perna", (0.15, 0.15, h), (sx * a, sy * a, h / 2), mw, 0.006), "Estrutura")
        r.caixa(f"Perna{sx}{sy}", (sx * a, sy * a, h / 2), (0.16, 0.16, h), "para", "Wood")
    for z0, z1 in ((0.3, 2.3), (2.3, 4.3)):
        for sy in (-1, 1):
            r.add(
                viga("x", (-a, sy * (a + 0.09), z0), (a, sy * (a + 0.09), z1), 0.04, 0.14, mwx),
                "Estrutura",
            )
            r.add(
                viga("x", (a, sy * (a + 0.11), z0), (-a, sy * (a + 0.11), z1), 0.04, 0.14, mwx),
                "Estrutura",
            )
        for sx in (-1, 1):
            r.add(
                viga("x", (sx * (a + 0.09), -a, z0), (sx * (a + 0.09), a, z1), 0.04, 0.14, mwx),
                "Estrutura",
            )
            r.add(
                viga("x", (sx * (a + 0.11), a, z0), (sx * (a + 0.11), -a, z1), 0.04, 0.14, mwx),
                "Estrutura",
            )
        for sy in (-1, 1):
            r.add(
                bloco(
                    "travessa",
                    (2 * a + 0.3, 0.05, 0.14),
                    (0, sy * (a + 0.1), z1 + 0.05),
                    mwx,
                    0.003,
                ),
                "Estrutura",
            )
        for sx in (-1, 1):
            r.add(
                bloco(
                    "travessa",
                    (0.05, 2 * a + 0.3, 0.14),
                    (sx * (a + 0.1), 0, z1 + 0.05),
                    mwx,
                    0.003,
                ),
                "Estrutura",
            )
    # piso
    for k in range(5):
        r.add(
            bloco("barrote", (2.6, 0.05, 0.2), (0, -1.0 + k * 0.5, zp - 0.1), mwx, 0.003),
            "Estrutura",
        )
    r.add(bloco("piso", (2.6, 2.6, 0.05), (0, 0, zp + 0.025), mwx, 0.004), "Estrutura")
    r.caixa_lim("Piso", (-1.3, -1.3, zp - 0.2), (1.3, 1.3, zp + 0.05), "para", "Wood")
    # parapeito de sacos (7 fiadas), aberto no fundo para a escada
    zs = zp + 0.05
    sacos = []
    sacos += B.sacos_linha((-1.3, -1.16), (1.3, -1.16), zs, 7, sem=51)
    sacos += B.sacos_linha((-1.16, -0.9), (-1.16, 1.3), zs, 7, sem=52)
    sacos += B.sacos_linha((1.16, -0.9), (1.16, 1.3), zs, 7, sem=53)
    sacos += B.sacos_linha((-1.02, 1.16), (-0.5, 1.16), zs, 7, sem=54)
    sacos += B.sacos_linha((0.5, 1.16), (1.02, 1.16), zs, 7, sem=55)
    r.add(B.sacos_juntar(sacos, "parapeito", juta), "Sacos")
    hs = 0.045 + 0.115 * 7
    r.caixa_lim("ParapeitoFrente", (-1.3, -1.3, zs), (1.3, -1.02, zs + hs), material="Sandbag")
    r.caixa_lim("ParapeitoEsq", (-1.3, -1.02, zs), (-1.02, 1.3, zs + hs), material="Sandbag")
    r.caixa_lim("ParapeitoDir", (1.02, -1.02, zs), (1.3, 1.3, zs + hs), material="Sandbag")
    r.caixa_lim("ParapeitoFundoEsq", (-1.02, 1.02, zs), (-0.5, 1.3, zs + hs), material="Sandbag")
    r.caixa_lim("ParapeitoFundoDir", (0.5, 1.02, zs), (1.02, 1.3, zs + hs), material="Sandbag")
    # telhado de chapa caindo para o fundo
    for sy, z in ((-1, 7.25), (1, 7.0)):
        r.add(bloco("terca", (2.7, 0.08, 0.12), (0, sy * a, z + 0.06), mwx, 0.003), "Estrutura")
    ang = math.atan2(0.25, 2 * a)
    tg = math.tan(ang)
    z_f = 7.37 + (1.45 - a) * tg + 0.008  # em cima das terças (topo 7,37 na frente e 7,12 atrás)
    o = Vector((-1.45, -1.45, z_f))
    u = Vector((1, 0, 0))
    v = Vector((0, math.cos(ang), -math.sin(ang)))
    r.fixo(
        B.chapa_ondulada("telhado", o, u, v, 2.9, 2.9 / math.cos(ang), mat=zinco, sem=5), "Telhado"
    )
    z_t = z_f - 2.9 * tg
    r.prisma(
        "Telhado",
        [
            (-1.45, -1.45, z_f - 0.06),
            (1.45, -1.45, z_f - 0.06),
            (-1.45, 1.45, z_t - 0.06),
            (1.45, 1.45, z_t - 0.06),
            (-1.45, -1.45, z_f + 0.04),
            (1.45, -1.45, z_f + 0.04),
            (-1.45, 1.45, z_t + 0.04),
            (1.45, 1.45, z_t + 0.04),
        ],
        "para",
        "Metal",
    )
    # escada de mão no fundo: pé a 1,25 m da torre, degraus a cada 0,30 m (PLACEHOLDER)
    yb, yt = a + 1.3, a + 0.08
    for sx in (-1, 1):
        r.add(
            viga("banzo", (sx * 0.25, yb, 0.0), (sx * 0.25, yt, zp + 0.9), 0.05, 0.1, mw),
            "Estrutura",
        )
    n = int((zp + 0.05) / 0.30)
    for k in range(1, n + 1):
        z = k * 0.30
        y = yb + (yt - yb) * z / (zp + 0.9)
        r.add(vara("degrau", (-0.24, y, z), (0.24, y, z), 0.02, mat=mw, segs=8), "Estrutura")
        r.caixa(
            f"Degrau{k:02d}",
            (0, y, z),
            (0.5, 0.06, 0.06),
            "passa",
            "Wood",
            obs="escada: degraus a 0,30 m; se o Humanoid não subir, trocar por TrussPart",
        )
    return r


# =============================================================== perímetro
def receita_us_concertina():
    """Concertina tripla padrão (FM 5-15, 1968): dois rolos de Ø 0,9 m na base, um em cima;
    piquetes longos a cada 3,8 m (5 passos) na frente e atrás (0,9 m). Módulo de 7,6 m que emenda
    com o vizinho. Espiras a cada 0,38 m e altura do piquete: PLACEHOLDER."""
    r = Receita()
    arame = N.mat_tinta(
        "arame", "#6d6a62", desgaste=0.9, rug_tinta=0.55, ferrugem=True, escala=300.0
    )
    piq = N.mat_tinta("piquete", "#4b4f34", desgaste=0.7, ferrugem=True, escala=120.0)
    Lm = 7.6
    R = 0.45
    p = 0.38
    rng = np.random.default_rng(65)
    rolos = [(-0.45, R), (0.45, R), (0.0, R + math.sqrt((2 * R) ** 2 - R**2))]
    for c, (yc, zc) in enumerate(rolos):
        n = round(Lm / p)
        for k in range(n):
            xk = -Lm / 2 + p / 2 + k * p
            sinal = 1 if (k + c) % 2 else -1
            pts = []
            nseg = 20
            fase = rng.uniform(0, 0.3)
            for i in range(nseg + 1):
                th = 2 * math.pi * i / nseg + fase
                x = xk + sinal * (p / 2) * 0.92 * math.cos(3 * th)
                rr = R * (1 + rng.uniform(-0.03, 0.03) if i < nseg else 1)
                pts.append((x, yc + rr * math.cos(th), zc + rr * math.sin(th)))
            pts[-1] = pts[0]
            o = M.tubo("espira", pts, 0.004, 3, tampar=False)
            r.add(M.material(o, arame), "Arame")
    for x, y in ((-1.9, -0.45), (1.9, -0.45), (0.0, 0.45), (-3.8, 0.45)):
        r.add(bloco("piquete_a", (0.05, 0.005, 1.2), (x, y, 0.6), piq), "Arame")
        r.add(bloco("piquete_b", (0.005, 0.05, 1.2), (x - 0.0225, y + 0.0225, 0.6), piq), "Arame")
    r.caixa_lim(
        "Concertina",
        (-Lm / 2, -0.9, 0),
        (Lm / 2, 0.9, 1.68),
        "passa",
        "Wire",
        obs="impede a passagem; a bala passa (CanQuery=false)",
    )
    return r


def painel_com_vaos(nome, o, u, L, H, esp, vaos, mat, n_dir):
    """Parede de chapa (compensado) de L x H a partir do canto `o` ao longo de `u`, espessura para
    o lado `n_dir`, com vãos [(s0, s1, z0, z1)]. Feita de faixas retangulares."""
    o, u, nd = Vector(o), Vector(u).normalized(), Vector(n_dir).normalized()
    cortes = sorted({0.0, L, *[v[0] for v in vaos], *[v[1] for v in vaos]})
    pecas = []
    for s0, s1 in zip(cortes[:-1], cortes[1:], strict=True):
        if s1 - s0 < 1e-4:
            continue
        zs = [0.0, H]
        for v in vaos:
            if v[0] <= s0 + 1e-6 and v[1] >= s1 - 1e-6:
                zs += [v[2], v[3]]
        zs = sorted(zs)
        cheio = True
        for z0, z1 in zip(zs[:-1], zs[1:], strict=True):
            if cheio and z1 - z0 > 1e-4:
                c = o + u * ((s0 + s1) / 2) + nd * (esp / 2) + Vector((0, 0, (z0 + z1) / 2))
                dim = Vector((0, 0, 0))
                dim_u, dim_n = s1 - s0, esp
                if abs(u.x) > 0.5:
                    dim = (dim_u, dim_n, z1 - z0)
                else:
                    dim = (dim_n, dim_u, z1 - z0)
                pecas.append(bloco(nome, dim, c, mat, 0.003))
            cheio = not cheio
    return pecas


def receita_us_gate():
    """Portão principal: guarita de compensado com telhado de chapa e sacos na frente, cancela de
    poste com contrapeso (nó `Cancela`, gira em volta do pino) e placa "7TH MARINES / CHU LAI" (a
    7ª de Fuzileiros chegou a Chu Lai em agosto de 1965; o desenho da placa é PLACEHOLDER)."""
    r = Receita()
    comp = B.mat_madeira_pintada("guarita", "#7d7a5c", 0.6)
    mw = N.mat_madeira("portao", "#8a7356", "#5c4934", "#7d7466", eixo="Z")
    zinco = B.mat_zinco("zinco_portao", 0.4)
    juta = N.mat_juta("juta_portao", "#a3916a", "#6c5c40", "#5a4a33", z_sujo=0.35)
    # guarita 2 x 2 m de 2,3 m, de x 3,1 a 5,1
    x0, x1, y0, y1, H = 3.1, 5.1, -1.0, 1.0, 2.6  # porta de 1,0 x 2,35 m (soldado de 2,0 m)
    pecas = []
    pecas += painel_com_vaos(
        "parede_f", (x0, y0, 0), (1, 0, 0), 2.0, H, 0.02, [(0.5, 1.5, 1.25, 1.9)], comp, (0, 1, 0)
    )
    pecas += painel_com_vaos(
        "parede_t", (x0, y1 - 0.02, 0), (1, 0, 0), 2.0, H, 0.02, [], comp, (0, 1, 0)
    )
    pecas += painel_com_vaos(
        "parede_e", (x0, y0, 0), (0, 1, 0), 2.0, H, 0.02, [(0.4, 1.6, 1.25, 1.9)], comp, (1, 0, 0)
    )
    pecas += painel_com_vaos(
        "parede_d",
        (x1 - 0.02, y0, 0),
        (0, 1, 0),
        2.0,
        H,
        0.02,
        [(0.8, 1.8, 0.0, 2.35)],
        comp,
        (1, 0, 0),
    )
    for p_ in pecas:
        r.add(p_, "Guarita")
    for x in (x0 + 0.05, x1 - 0.05):
        for y in (y0 + 0.05, y1 - 0.05):
            r.add(bloco("montante", (0.09, 0.09, H), (x, y, H / 2), mw, 0.003), "Guarita")
    r.add(bloco("prateleira", (0.3, 0.9, 0.03), (x0 + 0.2, 0.0, 1.05), mw, 0.003), "Guarita")
    r.add(
        bloco(
            "telefone",
            (0.27, 0.12, 0.22),
            (x0 + 0.2, -0.1, 1.18),
            N.mat_tinta("ee8_g", "#5b4a33", desgaste=0.3, escala=200.0),
            0.015,
        ),
        "Guarita",
    )
    ang = math.atan2(0.2, 2.4)
    r.fixo(
        B.chapa_ondulada(
            "telhado",
            (x0 - 0.2, y0 - 0.2, H + 0.25),
            (1, 0, 0),
            (0, math.cos(ang), -math.sin(ang)),
            2.4,
            2.4 / math.cos(ang),
            mat=zinco,
            sem=7,
        ),
        "Guarita",
    )
    for y in (y0 - 0.1, y1 + 0.1):
        r.add(
            bloco(
                "caibro_g",
                (2.4, 0.06, 0.08),
                (x0 + 1.0, y, H + 0.22 - (y - y0 + 0.1) * math.tan(ang)),
                mw,
                0.003,
            ),
            "Guarita",
        )
    sacos = B.sacos_linha((x0 - 0.2, -1.45), (x1 + 0.4, -1.45), 0, 9, sem=61)
    r.add(B.sacos_juntar(sacos, "sacos_g", juta), "Guarita")
    hs = 0.045 + 0.115 * 9
    r.caixa_lim("Sacos", (x0 - 0.2, -1.6, 0), (x1 + 0.4, -1.3, hs), material="Sandbag")
    r.caixa_lim("GuaritaFrente", (x0, y0, 0), (x1, y0 + 0.08, H), material="Wood")
    r.caixa_lim("GuaritaFundo", (x0, y1 - 0.08, 0), (x1, y1, H), material="Wood")
    r.caixa_lim("GuaritaEstrada", (x0, y0, 0), (x0 + 0.08, y1, H), material="Wood")
    r.caixa_lim("GuaritaPortaA", (x1 - 0.08, y0, 0), (x1, y0 + 0.8, H), material="Wood")
    r.caixa_lim("GuaritaPortaB", (x1 - 0.08, y0 + 1.8, 0), (x1, y1, H), material="Wood")
    r.caixa_lim(
        "GuaritaTeto", (x0 - 0.2, y0 - 0.2, H), (x1 + 0.2, y1 + 0.2, H + 0.3), material="Metal"
    )
    # cancela: pino em (2,35; 0; 1,0), vara de 5 m para -X apoiada num garfo em x = -2,4
    listra = B.Mat("cancela_listras", rug=0.6)
    po = listra.coord("objeto")
    xx = listra.separar(po)[0]
    faixa = listra.conta(
        "GREATER_THAN", listra.conta("FRACT", listra.conta("MULTIPLY", xx, 1 / 0.6)), 0.5
    )
    listra.cor(listra.misturar(faixa, B.rgb("#e2ddd0"), B.rgb("#a8262b")))
    listra.relevo(listra.ruido(po, 80.0, 3), 0.1, 0.0004)
    px, pz = 2.35, 1.0
    r.add(
        bloco("pilar_cancela", (0.16, 0.16, pz + 0.1), (px, 0.0, (pz + 0.1) / 2), mw, 0.006),
        "Cancela",
        "Pilar",
    )
    r.add(
        vara("vara_cancela", (px + 0.35, 0.0, pz), (-2.6, 0.0, pz), 0.055, 0.045, listra.m, 12, 2),
        "Cancela",
    )
    r.add(
        bloco(
            "contrapeso",
            (0.3, 0.2, 0.22),
            (px + 0.45, 0.0, pz),
            N.mat_tinta("contrapeso", "#3a3a35", desgaste=0.5, escala=150.0),
            0.01,
        ),
        "Cancela",
    )
    r.add(
        vara(
            "pino", (px, -0.12, pz), (px, 0.12, pz), 0.02, mat=N.mat_aco("pino_c", "#77766f", 0.4)
        ),
        "Cancela",
    )
    r.add(bloco("garfo_poste", (0.12, 0.12, 0.9), (-2.4, 0.0, 0.45), mw, 0.004), "Cancela", "Pilar")
    for s in (-1, 1):
        r.add(
            viga("garfo", (-2.4, 0.0, 0.88), (-2.4, s * 0.1, 1.06), 0.04, 0.04, mw),
            "Cancela",
            "Pilar",
        )
    r.caixa("Pilar", (px, 0, (pz + 0.1) / 2), (0.18, 0.18, pz + 0.1), "para", "Wood")
    r.caixa("Garfo", (-2.4, 0, 0.5), (0.14, 0.14, 1.0), "para", "Wood")
    r.caixa_lim(
        "Cancela",
        (-2.65, -0.06, pz - 0.06),
        (px + 0.6, 0.06, pz + 0.06),
        "passa",
        "Wood",
        obs="gira com o nó Cancela em volta do pino",
    )
    r.extras["cancela_pivo_m"] = [px, 0.0, pz]
    r.extras["cancela_eixo_blender"] = "Y"
    # placa
    tinta = B.mat_madeira_pintada("placa_portao", "#8e1d24", 0.5)
    ouro = N.mat_estencil("letra_ouro", "#d6a632", "#8e1d24", gasto=0.15, escala=120.0)
    xp = -4.9
    for x in (xp - 1.2, xp + 1.2):
        r.add(bloco("poste_placa", (0.15, 0.15, 2.75), (x, 0.0, 1.375), mw, 0.006), "Placa")
        r.caixa(
            f"PostePlaca{'E' if x < xp else 'D'}", (x, 0, 1.375), (0.16, 0.16, 2.75), "para", "Wood"
        )
    r.add(bloco("placa", (2.6, 0.05, 1.05), (xp, -0.1, 2.1), tinta, 0.008), "Placa")
    r.add(bloco("moldura", (2.7, 0.06, 0.06), (xp, -0.1, 2.66), mw, 0.004), "Placa")
    yf = -0.1 - 0.025 - 0.0006
    r.add(B.letreiro("7TH MARINES", 0.26, ouro, (xp, yf, 2.33), "-Y", B.FONTE_NEGRITO), "Placa")
    r.add(B.letreiro("CHU LAI", 0.18, ouro, (xp, yf, 1.97), "-Y", B.FONTE_NEGRITO), "Placa")
    r.add(B.letreiro("U.S. MARINE CORPS", 0.09, ouro, (xp, yf, 1.70), "-Y", B.FONTE_PLACA), "Placa")
    r.caixa("Placa", (xp, -0.1, 2.1), (2.6, 0.08, 1.05), "para", "Wood")
    return r


def receita_us_flagpole():
    """Mastros com a bandeira dos EUA (50 estrelas; proporções da Executive Order 10834) e a do
    USMC (escarlate com o emblema; 52 x 62 pol). Mastros de madeira pintada de branco com pomo,
    roldana e adriça; círculo de pedras caiadas na base. Alturas e tamanho da bandeira dos EUA:
    PLACEHOLDER; o emblema do USMC é simplificado."""
    r = Receita()
    branco = B.mat_madeira_pintada("mastro_branco", "#e5e1d6", 0.4)
    ouro_m = N.mat_tinta("pomo", "#c79a35", desgaste=0.3, escala=200.0)
    mc = N.mat_corda("adrica", "#c9c0a8")
    pedra = B.mat_tinta_lisa("pedra_caiada", "#d9d5c9", 0.9, 0.3)
    mastros = {"EUA": (-1.75, 9.0), "USMC": (1.75, 7.0)}
    rng = np.random.default_rng(7)
    for nome, (x, h) in mastros.items():
        r.add(vara(f"mastro_{nome}", (x, 0, 0), (x, 0, h), 0.075, 0.045, branco, 14, 3), "Mastros")
        r.add(
            M.material(
                M.mover(
                    M.torno(
                        "pomo",
                        [(0.0, 0.0), (0.05, 0.01), (0.075, 0.07), (0.05, 0.13), (0.0, 0.14)],
                        16,
                    ),
                    Matrix.Translation((x, 0, h)),
                ),
                ouro_m,
            ),
            "Mastros",
        )
        r.add(
            B.cilindro("roldana", 0.04, 0.02, (x + 0.07, 0, h - 0.08), ouro_m, 12, "Y"), "Mastros"
        )
        r.add(
            corda("adrica", (x + 0.1, 0, h - 0.08), (x + 0.08, 0, 1.2), 0.0, 0.004, mc, 3, 4),
            "Mastros",
        )
        r.add(bloco("cunho", (0.04, 0.03, 0.16), (x + 0.06, 0, 1.2), ouro_m, 0.004), "Mastros")
        for k in range(14):
            a = 2 * math.pi * k / 14 + rng.uniform(-0.1, 0.1)
            pe = M.superelipsoide("pedra", 0.13, 0.1, 0.08, 0.6, 0.6, 12, 6)
            M.deslocar(pe, lambda co, n, k=k: 0.012 * M.fbm(co * 12, 2, k))
            M.mover(pe, M.matriz((x + 0.65 * math.cos(a), 0.65 * math.sin(a), 0.05), (0, 0, a)))
            r.add(M.material(M.suave(pe, 60), pedra), "Mastros")
        r.caixa(f"Mastro{nome}", (x, 0, h / 2), (0.16, 0.16, h), "para", "Wood")

    # bandeiras: pano no plano XZ, deformado pela onda; estrelas e emblema colados (só no bake)
    def onda(F, H, x0, zb, amp=0.16, lam=1.3, cai=0.10):
        def f(v: Vector) -> Vector:
            s = v.x - x0
            t = v.z - zb
            q = max(0.0, s) / F
            y = (amp * q**0.9 + 0.015) * math.sin(2 * math.pi * (s / lam - 0.15 * t / H) + 0.6)
            return Vector((x0 + 0.97 * s, v.y + y, zb + t - cai * q * q))

        return f

    def pano(nome, F, H, x0, zb, mat, res=0.09):
        def g(a, b):
            return (x0 + a * F, 0.0, zb + b * H)

        o = grade(nome, g, max(4, round(F / res)), max(4, round(H / res)), fora=(0, -1, 0))
        B.gravar_uv_local(o, lambda p: (p.x - x0, 0.0, p.z - zb))
        M.solidificar(o, 0.003, 0.0)
        return M.material(M.suave(o, 50), mat)

    # EUA: 1,52 x 2,89 m (razão 1,9; tamanho PLACEHOLDER)
    xe, he = mastros["EUA"]
    H, F = 1.52, 2.89
    x0, zb = xe + 0.08, he - 0.12 - H
    deform = onda(F, H, x0, zb)
    pano_e = pano("bandeira_eua", F, H, x0, zb, B.mat_bandeira_eua("bandeira_eua", H, F))
    branca = B.mat_estrela()
    estrelas = []
    frente = Matrix.Rotation(math.pi / 2, 4, "X")  # texto do plano XY para o XZ, olhando -Y
    verso = Matrix.Rotation(math.pi, 4, "Z") @ frente  # olhando +Y, de pé
    for i in range(9):
        cols = range(1, 12, 2) if i % 2 == 0 else range(2, 11, 2)
        for j in cols:
            s = 0.063 * H * j
            t = H - 0.054 * H * (i + 1)
            for lado, rot in ((-1, frente), (1, verso)):
                m = Matrix.Translation((x0 + s, lado * 0.003, zb + t)) @ rot
                estrelas.append(B.estrela(0.0616 * H, branca, m))
    for o in [pano_e, *estrelas]:
        M.deslocar(o, lambda co, n: deform(co) - co)
        r.add(o, "Bandeiras")
    # USMC: 1,32 x 1,57 m (Wikipedia: 52 x 62 pol)
    xu, hu = mastros["USMC"]
    H2, F2 = 1.32, 1.57
    x2, zb2 = xu + 0.08, hu - 0.12 - H2
    deform2 = onda(F2, H2, x2, zb2, amp=0.12, lam=1.1, cai=0.08)
    pano_u = pano("bandeira_usmc", F2, H2, x2, zb2, B.mat_bandeira_usmc("bandeira_usmc"))
    ouro = B.mat_tinta_lisa("emblema_ouro", "#d4a83c", 0.5, 0.1)
    cinza = B.mat_tinta_lisa("emblema_cinza", "#a6a59f", 0.5, 0.1)
    emb = []
    cx, cz = x2 + F2 / 2, zb2 + H2 * 0.56
    for lado, rot in ((-1, frente), (1, verso)):
        y = lado * 0.0032

        def plano(obj, dx, dz, y=y, rot=rot):
            M.mover(obj, Matrix.Translation((cx + dx, y, cz + dz)) @ rot)
            return N.so_bake(obj)

        globo = M.torno("globo", [(0.0, 0.0), (0.2, 0.0), (0.2, 0.001), (0.0, 0.001)], 40)
        emb.append(M.material(plano(globo, 0, 0), cinza))
        for k, (rr, sx_) in enumerate(((0.2, 1.0), (0.2, 0.55), (0.2, 0.15))):
            mer = M.toro("meridiano", rr, 0.008, 40, 4)
            M.mover(mer, Matrix.Diagonal((sx_, 1.0, 0.05, 1.0)))
            emb.append(M.material(plano(mer, 0, 0), ouro))
            del k
        for dz in (-0.1, 0.0, 0.1):
            w = math.sqrt(0.2**2 - dz**2)
            emb.append(M.material(plano(M.caixa("paralelo", (2 * w, 0.016, 0.001)), 0, dz), ouro))
        emb.append(M.material(plano(M.caixa("haste", (0.04, 0.62, 0.001)), 0, -0.02), ouro))
        emb.append(M.material(plano(M.caixa("cepo", (0.26, 0.035, 0.001)), 0, 0.24), ouro))
        braco = M.toro("braco", 0.2, 0.017, 24, 4, arco=(math.radians(200), math.radians(340)))
        M.mover(braco, Matrix.Diagonal((1.0, 1.0, 0.05, 1.0)))
        emb.append(M.material(plano(braco, 0, 0.0), ouro))
        for s in (-1, 1):
            asa = M.caixa("asa", (0.22, 0.07, 0.001))
            M.mover(asa, Matrix.Rotation(s * 0.45, 4, "Z") @ Matrix.Translation((s * 0.11, 0, 0)))
            emb.append(M.material(plano(asa, 0, 0.27), ouro))
        corpo = M.superelipsoide("aguia", 0.045, 0.07, 0.001, 0.8, 0.8, 16, 6)
        emb.append(M.material(plano(corpo, 0, 0.27), ouro))
        txt = M.texto_malha("UNITED STATES MARINE CORPS", 0.055, B.FONTE_NEGRITO)
        M.mover(txt, Matrix.Translation((cx, y, zb2 + 0.13)) @ rot)
        emb.append(M.material(N.so_bake(txt), ouro))
    for o in [pano_u, *emb]:
        M.deslocar(o, lambda co, n: deform2(co) - co)
        r.add(o, "Bandeiras")
    return r


# =============================================================== estande de tiro
def receita_us_range_bench():
    """Bancada de tiro de tábuas com banco e saco de areia de apoio (PLACEHOLDER: o USMC de 1965
    atirava deitado na linha de tiro; a bancada é pedido do dono)."""
    r = Receita()
    mw = N.mat_madeira("bancada", "#a58a62", "#755c3e", "#8f8775", largura_tabua=0.15)
    pe = N.mat_madeira("pe_bancada", "#8d7656", "#5e4a33", "#7f776a", eixo="Y")
    juta = N.mat_juta("juta_banca", "#a3916a", "#6c5c40", "#5a4a33", z_sujo=0.0)
    r.add(bloco("tampo", (1.2, 0.62, 0.045), (0, 0, 0.8), mw, 0.004))
    for sx in (-1, 1):
        for sy in (-1, 1):
            r.add(
                viga(
                    "perna", (sx * 0.5, sy * 0.25, 0.78), (sx * 0.55, sy * 0.3, 0.0), 0.08, 0.08, pe
                )
            )
        r.add(bloco("trava", (0.05, 0.55, 0.08), (sx * 0.52, 0, 0.3), pe, 0.003))
    r.add(bloco("assento", (1.2, 0.28, 0.04), (0, 0.65, 0.45), mw, 0.004))
    for sx in (-1, 1):
        r.add(bloco("pe_assento", (0.06, 0.24, 0.43), (sx * 0.5, 0.65, 0.215), pe, 0.003))
    s = N.saco("apoio", 0.48, 0.27, 0.16, 71, pescoco=0.03, seg=(32, 16))
    M.mover(s, M.matriz((0.0, -0.18, 0.86), (0, 0, 0.05)))
    r.add(M.material(M.suave(s, 80), juta))
    r.caixa("Bancada", (0, 0, 0.42), (1.2, 0.62, 0.84), "para", "Wood")
    r.caixa("Assento", (0, 0.65, 0.235), (1.2, 0.28, 0.47), "para", "Wood")
    return r


def silhueta_e():
    """Contorno da silhueta tipo E (de joelhos), 0,495 x 1,016 m (19,5 x 40 pol): cabeça redonda,
    pescoço, ombros arredondados e corpo reto. Pontos (x, z) no sentido anti-horário."""
    meia = [(0.0, 0.0), (0.2475, 0.0), (0.2475, 0.6)]
    for k in range(1, 7):
        a = math.radians(90 * k / 6)
        meia.append((0.1675 + 0.08 * math.cos(a), 0.6 + 0.08 * math.sin(a)))
    meia += [(0.11, 0.69), (0.075, 0.74), (0.072, 0.78)]
    for k in range(1, 10):
        a = math.radians(-35 + 125 * k / 9)
        meia.append((0.095 * math.cos(a), 0.921 + 0.095 * math.sin(a)))
    meia.append((0.0, 1.016))
    direita = meia
    esquerda = [(-x, z) for x, z in reversed(direita[1:-1])]
    return direita + esquerda


def receita_us_range_target():
    """Alvo de silhueta tipo E em papelão (19,5 x 40 pol) num suporte de sarrafos, com o centro a
    1,2 m do chão (o mesmo do TrainingService). Nó `Silhueta` separado (é ele que leva o
    RangeTarget). Cor verde-oliva: PLACEHOLDER."""
    import bmesh

    r = Receita()
    pts = silhueta_e()
    bm = bmesh.new()
    zc = 1.2 - 0.508
    vs = [bm.verts.new((x, -0.032, zc + z)) for x, z in pts]
    face = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    novos_v = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0.004, 0)), verts=novos_v)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="EAR_CLIP")
    sil = M.de_bmesh("silhueta", bm)
    pap = B.Mat("papelao_e", rug=0.9)
    po = pap.coord("objeto")
    base = pap.misturar(
        pap.faixa(pap.ruido(po, 6.0, 4), 0.3, 0.7, 0.0, 0.3), B.rgb("#76804f"), B.rgb("#5d6640")
    )
    furo = pap.faixa(pap.voronoi(po, 18.0), 0.035, 0.02)
    furo = pap.conta("MULTIPLY", furo, pap.faixa(pap.ruido(po, 3.0), 0.5, 0.6))
    remendo = pap.conta(
        "MULTIPLY",
        pap.faixa(pap.voronoi(po, 9.0), 0.07, 0.05),
        pap.faixa(pap.ruido(po, 2.0, 2), 0.62, 0.66),
    )
    cor = pap.misturar(remendo, base, B.rgb("#c9c2a6"))
    pap.cor(pap.misturar(furo, cor, B.rgb("#141310")))
    pap.relevo(pap.ruido(po, 40.0, 3), 0.1, 0.0006)
    r.add(M.material(M.suave(sil, 30), pap.m), "Alvo", "Silhueta")
    mw = N.mat_madeira("sarrafo", "#a58a62", "#755c3e", "#8f8775", eixo="Z")
    r.add(bloco("estaca", (0.045, 0.045, 1.75), (0, 0.0, 0.875), mw, 0.003), "Alvo", "Suporte")
    for z in (zc + 0.15, zc + 0.85):
        r.add(bloco("ripa", (0.56, 0.02, 0.045), (0, -0.016, z), mw, 0.002), "Alvo", "Suporte")
    r.caixa("Estaca", (0, 0, 0.875), (0.06, 0.06, 1.75), "para", "Wood")
    return r


def receita_us_range_berm():
    """Barranco de proteção atrás dos alvos: tronco de pirâmide de terra de 16 x 7,2 m na base,
    3 m de altura e crista de 1,2 m (taludes de 45°): PLACEHOLDER."""
    r = Receita()
    Lx, Ly, H, crista = 16.0, 7.2, 3.0, 1.2
    s = H / ((Ly - crista) / 2)
    rng = np.random.default_rng(81)
    fase = Vector(rng.uniform(0, 50, 3).tolist())

    def f(a, b):
        x = -Lx / 2 + a * Lx
        y = -Ly / 2 + b * Ly
        d = min(Lx / 2 - abs(x), Ly / 2 - abs(y))
        z = min(H, s * d)
        q = Vector((x, y, 0)) * 0.6 + fase
        z += (
            (0.12 * M.fbm(q, 4, 1) + 0.03 * M.ruido(q * 6, 2))
            * min(1.0, z / 0.4)
            * (1 if z < H - 0.02 else 0.6)
        )
        return (x, y, max(0.0, z))

    o = grade("barranco", f, round(Lx / 0.16), round(Ly / 0.16), fora=(0, 0, 1))
    B.apagar_faces(o, lambda c: c.z < 0.004)
    r.add(
        M.material(M.suave(o, 60), B.mat_terra("terra_barranco", "#a8916a", "#6f5a3e", 0.3)),
        "Barranco",
    )
    r.prisma(
        "Barranco",
        [
            (-Lx / 2, -Ly / 2, 0),
            (Lx / 2, -Ly / 2, 0),
            (-Lx / 2, Ly / 2, 0),
            (Lx / 2, Ly / 2, 0),
            (-Lx / 2 + H / s, -crista / 2, H),
            (Lx / 2 - H / s, -crista / 2, H),
            (-Lx / 2 + H / s, crista / 2, H),
            (Lx / 2 - H / s, crista / 2, H),
        ],
        "para",
        "Earth",
    )
    return r


def receita_us_range_sign():
    """Placas de distância (25, 100, 200 e 300 m): tábua branca com número preto numa estaca.
    Quatro nós no mesmo lugar (`Placa25`...`Placa300`); o código deixa só o da distância.
    Desenho: PLACEHOLDER."""
    r = Receita()
    tinta = B.mat_madeira_pintada("placa_dist", "#e3dfd2", 0.5)
    mw = N.mat_madeira("estaca_placa", "#8d7656", "#5e4a33", "#7f776a", eixo="Z")
    preto = N.mat_estencil("numero", "#1d1c19", "#e3dfd2", gasto=0.15, escala=150.0)
    for i, d in enumerate((25, 100, 200, 300)):
        x = i * 1.0
        no = f"Placa{d}"
        r.add(bloco("estaca", (0.06, 0.06, 1.38), (x, 0.03, 0.69), mw, 0.003), "Placas", no)
        r.add(bloco("tabua", (0.62, 0.03, 0.42), (x, 0.0, 1.12), tinta, 0.005), "Placas", no)
        r.add(
            B.letreiro(str(d), 0.25, preto, (x, -0.0156, 1.12), "-Y", B.FONTE_NEGRITO), "Placas", no
        )
    r.caixa("Placa", (0, 0.015, 0.7), (0.62, 0.1, 1.4), "para", "Wood")
    r.extras["mesmo_lugar"] = True
    return r


# =============================================================== motor pool
def receita_us_motor_pool():
    """Garagem e oficina (motor pool): galpão de postes de 12 x 12 m com telhado de duas águas de
    chapa de aço galvanizado ondulada (zinco), fundo e meia lateral fechados de chapa, 2 boxes para
    M48A3 ou LVTP-5 (9,3 x 3,65 x 3,1 e 9,04 x 3,57 x 2,92 m), talha de corrente numa viga, bancada
    com morsa e caixa de ferramentas. Medidas do galpão: PLACEHOLDER (cabem os veículos)."""
    r = Receita()
    mw = N.mat_madeira("galpao", "#8a7356", "#5c4934", "#7d7466", eixo="Z")
    mwx = N.mat_madeira("galpao_x", "#8a7356", "#5c4934", "#7d7466", eixo="X")
    mwy = N.mat_madeira("galpao_y", "#8a7356", "#5c4934", "#7d7466", eixo="Y")
    zinco = B.mat_zinco("zinco_galpao", 0.5)
    he, hr = 4.2, 5.0
    ov = 0.3

    def z_tel(x):
        """Plano de baixo da chapa do telhado (em cima das terças)."""
        return he + 0.2 + (hr - he) * (1 - abs(x) / 6.0)

    for x in (-6.0, 0.0, 6.0):
        for y in (-6.0, 0.0, 6.0):
            h = hr if x == 0 else he
            r.add(bloco("poste", (0.2, 0.2, h), (x, y, h / 2), mw, 0.006), "Estrutura")
            r.caixa(f"Poste{int(x)}{int(y)}", (x, y, h / 2), (0.22, 0.22, h), "para", "Wood")
    for x in (-6.0, 6.0):
        r.add(bloco("frechal", (0.12, 12.6, 0.25), (x, 0, he - 0.125), mwy, 0.004), "Estrutura")
    r.add(bloco("cumeeira", (0.14, 12.6, 0.28), (0, 0, hr - 0.14), mwy, 0.004), "Estrutura")
    for y in (-6.0, -3.0, 0.0, 3.0, 6.0):
        r.add(bloco("tirante", (12.2, 0.08, 0.2), (0, y, he - 0.3), mwx, 0.003), "Estrutura")
        for sx in (-1, 1):
            xe = sx * (6.0 + ov)
            r.add(
                viga("asna", (xe, y, z_tel(xe) - 0.22), (0, y, z_tel(0) - 0.22), 0.08, 0.2, mwx),
                "Estrutura",
            )
            r.add(
                viga(
                    "escora",
                    (sx * 3.0, y, he - 0.2),
                    (sx * 1.5, y, z_tel(1.5) - 0.3),
                    0.08,
                    0.12,
                    mwx,
                ),
                "Estrutura",
            )
    for sx in (-1, 1):
        for k in range(5):
            x = sx * (0.2 + (6.15 - 0.2) * k / 4)
            r.add(
                bloco("terca", (0.08, 12.6, 0.12), (x, 0, z_tel(x) - 0.06), mwy, 0.003), "Estrutura"
            )
    # telhado de chapa (uma chapa por água) e capa da cumeeira
    for sx in (-1, 1):
        xe = sx * (6.0 + ov)
        o = Vector((xe, -6.3, z_tel(xe) + 0.008))
        topo = Vector((0, -6.3, z_tel(0) + 0.008))
        v = (topo - o).normalized()
        r.add(
            B.chapa_ondulada(
                "telhado", o, (0, 1, 0), v, 12.6, (topo - o).length, mat=zinco, sem=11 + sx
            ),
            "Telhado",
        )
        r.add(
            viga(
                "capa",
                (sx * 0.15, -6.3, z_tel(0) + 0.02),
                (sx * 0.15, 6.3, z_tel(0) + 0.02),
                0.32,
                0.004,
                zinco,
                0.0,
                cima=(sx * 0.13, 0, 1),
            ),
            "Telhado",
        )
        r.prisma(
            f"Telhado{'Dir' if sx > 0 else 'Esq'}",
            [
                (xe, -6.3, z_tel(xe) - 0.1),
                (xe, 6.3, z_tel(xe) - 0.1),
                (0, -6.3, z_tel(0) - 0.1),
                (0, 6.3, z_tel(0) - 0.1),
                (xe, -6.3, z_tel(xe) + 0.05),
                (xe, 6.3, z_tel(xe) + 0.05),
                (0, -6.3, z_tel(0) + 0.05),
                (0, 6.3, z_tel(0) + 0.05),
            ],
            "para",
            "Metal",
        )
    # fundo de chapa e oitão (vão até o telhado), lateral direita (metade do fundo cheia, metade
    # da frente só no alto)
    for z in (1.0, 2.6, he - 0.4):
        r.add(bloco("travessa_f", (12.0, 0.08, 0.12), (0, 6.06, z), mwx, 0.003), "Estrutura")

    def parede_chapa(*args, **kw):
        """Parede de chapa ondulada: a alta (ondas) vai para o mapa de normais de uma baixa lisa
        de 4 mm (a redução automática furava a chapa fina)."""
        r.substituir([r.add(B.chapa_ondulada(*args, **kw), "Estrutura")])
        lisa = {**kw, "passo": 0.6, "prof": 0.0, "esp": 0.004}
        r.baixo(B.chapa_ondulada(*args, **lisa), "Estrutura")

    zz = (0, 0, 1)
    parede_chapa("fundo", (-6.05, 6.14, 0.15), (1, 0, 0), zz, 12.1, he - 0.15, mat=zinco, sem=21)
    parede_chapa(
        "oitao",
        (-6.05, 6.14, he),
        (1, 0, 0),
        zz,
        12.1,
        1.0,
        mat=zinco,
        sem=24,
        comp_v=lambda a: max(0.02, z_tel(-6.05 + a * 12.1) - he - 0.03),
    )
    for z in (1.0, 2.6, he - 0.4):
        r.add(bloco("travessa_l", (0.08, 12.0, 0.12), (6.06, 0, z), mwy, 0.003), "Estrutura")
    parede_chapa("lado_fundo", (6.14, 0.0, 0.15), (0, 1, 0), zz, 6.05, he - 0.15, mat=zinco, sem=22)
    parede_chapa("lado_alto", (6.14, -6.05, 2.2), (0, 1, 0), zz, 6.05, he - 2.2, mat=zinco, sem=23)
    r.caixa_lim("Fundo", (-6.1, 6.0, 0), (6.1, 6.2, he), material="Metal")
    r.caixa_lim("LadoDirFundo", (6.0, 0.0, 0), (6.2, 6.1, he), material="Metal")
    r.caixa_lim("LadoDirAlto", (6.0, -6.1, 2.2), (6.2, 0.0, he), material="Metal")
    # oficina no canto direito do fundo
    banc = N.mat_madeira("bancada_of", "#8f7553", "#5f4b33", "#7f776a", largura_tabua=0.12)
    r.add(bloco("bancada", (0.75, 2.6, 0.06), (5.5, 3.6, 0.9), banc, 0.004), "Oficina")
    for y in (2.4, 4.8):
        for x in (5.2, 5.8):
            r.add(bloco("pe_banc", (0.08, 0.08, 0.87), (x, y, 0.435), banc, 0.003), "Oficina")
    r.add(bloco("prat_banc", (0.7, 2.5, 0.03), (5.5, 3.6, 0.25), banc, 0.003), "Oficina")
    aco = N.mat_tinta("morsa", "#3f4a55", desgaste=0.6, escala=200.0)
    r.add(bloco("morsa_base", (0.16, 0.22, 0.08), (5.3, 2.6, 0.97), aco, 0.006), "Oficina")
    r.add(bloco("morsa_mord", (0.2, 0.08, 0.12), (5.3, 2.52, 1.07), aco, 0.006), "Oficina")
    r.add(
        vara(
            "morsa_fuso",
            (5.3, 2.2, 1.05),
            (5.3, 2.5, 1.05),
            0.012,
            mat=N.mat_aco("fuso", "#7d7c76", 0.4),
        ),
        "Oficina",
    )
    r.add(bloco("quadro_ferr", (0.03, 2.0, 0.9), (6.0, 3.6, 1.55), banc, 0.003), "Oficina")
    chave = N.mat_aco("ferramenta", "#8a8984", 0.4, 200.0)
    for k in range(9):
        y = 2.8 + k * 0.2
        r.add(
            bloco("chave", (0.015, 0.03, 0.18 + 0.02 * (k % 4)), (5.98, y, 1.5), chave, 0.003),
            "Oficina",
        )
    caixa_f = N.mat_tinta("caixa_ferr", "#4b4f34", desgaste=0.6, escala=200.0)
    r.add(bloco("caixa_ferr", (0.6, 0.45, 0.9), (5.55, 5.5, 0.45), caixa_f, 0.01), "Oficina")
    r.caixa("Bancada", (5.5, 3.6, 0.47), (0.75, 2.6, 0.94), "para", "Wood")
    r.caixa("CaixaFerr", (5.55, 5.5, 0.45), (0.6, 0.45, 0.9), "para", "Metal")
    # talha de corrente na linha de postes do meio (y = 0), sobre o boxe esquerdo
    r.add(
        bloco(
            "viga_talha",
            (6.0, 0.14, 0.2),
            (-3.0, 0.0, he - 0.55),
            N.mat_tinta("viga_i", "#4b4f34", desgaste=0.6, escala=120.0),
            0.004,
        ),
        "Oficina",
    )
    r.add(bloco("talha", (0.22, 0.14, 0.3), (-3.2, 0.0, he - 0.85), aco, 0.01), "Oficina")
    elo = N.mat_aco("corrente", "#5a5853", 0.5, 300.0)
    for k in range(18):
        z = he - 1.02 - k * 0.07
        el = M.toro("elo", 0.022, 0.005, 10, 4)
        M.mover(
            el,
            Matrix.Translation((-3.2, 0.0, z))
            @ Matrix.Rotation(math.pi / 2 * (k % 2), 4, "Z")
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        r.add(M.material(el, elo), "Oficina")
    gancho = M.toro("gancho", 0.05, 0.012, 16, 6, arco=(0.0, 4.4))
    M.mover(
        gancho, Matrix.Translation((-3.2, 0.0, he - 2.35)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    )
    r.add(M.material(gancho, elo), "Oficina")
    # pneus e tambores de óleo
    borracha = B.mat_borracha("pneu")
    for k in range(3):
        pn = M.toro("pneu", 0.33, 0.12, 28, 10)
        M.mover(pn, Matrix.Diagonal((1, 1, 0.85, 1)))
        M.mover(pn, Matrix.Translation((4.3, 5.3, 0.1 + k * 0.205)))
        r.add(M.material(M.suave(pn, 50), borracha), "Oficina")
    r.caixa("Pneus", (4.3, 5.3, 0.31), (0.92, 0.92, 0.62), "para", "Rubber")
    tinta_t = N.mat_tinta("tambor_oleo", "#4e5233", desgaste=0.6, escala=150.0)
    for k, (x, y) in enumerate(((4.6, 1.2), (5.25, 1.1))):
        r.addv(B.tambor(f"tambor{k}", (x, y, 0.0), tinta_t, sem=k), "Oficina")
    r.caixa("Tambores", (4.92, 1.15, 0.44), (1.3, 0.7, 0.9), "para", "Metal")
    return r


# =============================================================== heliponto e blindados
def receita_us_helipad():
    """Módulo de heliponto de esteira AM-2 (12 x 2 pés x 1,5 pol = 3,658 x 0,610 x 0,038 m por
    placa; Blazich, 'SATS and Chu Lai'). 4 placas x 24 fiadas em amarração = 14,63 x 14,64 m. O
    heliponto do MAG-36 em Ky Ha (set/1965) era AM-2 sobre laterita (foto oficial do USMC)."""
    r = Receita()
    am2 = B.mat_am2("am2")
    Lp, Wp, Hp = 3.658, 0.610, 0.038
    n_f = 24
    total_x = 4 * Lp
    for j in range(n_f):
        y = -n_f * Wp / 2 + Wp / 2 + j * Wp
        if j % 2 == 0:
            segs = [(-total_x / 2 + i * Lp, Lp) for i in range(4)]
        else:
            segs = (
                [(-total_x / 2, Lp / 2)]
                + [(-total_x / 2 + Lp / 2 + i * Lp, Lp) for i in range(3)]
                + [(total_x / 2 - Lp / 2, Lp / 2)]
            )
        for x0, comp in segs:
            r.add(
                bloco(
                    "am2", (comp - 0.006, Wp - 0.006, Hp), (x0 + comp / 2, y, Hp / 2), am2, 0.005
                ),
                "Esteira",
            )
    r.caixa("Esteira", (0, 0, Hp / 2), (total_x, n_f * Wp, Hp), "para", "Metal")
    return r


def receita_us_armor_revetment():
    """Área dos blindados: baia em U de terra (laterita) empurrada, 1,5 m de altura e taludes de
    45°, com piso de esteira de aço M8A1 (22 x 144 pol = 0,559 x 3,658 m por placa; Wikipedia,
    Marston Mat). Baia de 5,59 x 10,97 m: cabe o M48A3 (9,3 x 3,65 m) e o LVTP-5 (9,04 x 3,57 m).
    Medidas da baia e do talude: PLACEHOLDER; o M8A1 nos pátios de Chu Lai é de Blazich."""
    r = Receita()
    bx, by = 5.59 / 2, 10.97 / 2
    H, crista = 1.5, 0.8
    base = crista + 2 * H
    berm = [
        (-bx - base, -bx, -by, by + base),
        (bx, bx + base, -by, by + base),
        (-bx - base, bx + base, by, by + base),
    ]

    def alt(x, y):
        z = 0.0
        for x0, x1, y0, y1 in berm:
            if x0 <= x <= x1 and y0 <= y <= y1:
                d = min(x - x0, x1 - x, y - y0, y1 - y)
                z = max(z, min(H, d * H / H))
        return z

    rng = np.random.default_rng(91)
    fase = Vector(rng.uniform(0, 50, 3).tolist())
    X0, X1, Y0, Y1 = -bx - base, bx + base, -by, by + base

    def f(a, b):
        x = X0 + a * (X1 - X0)
        y = Y0 + b * (Y1 - Y0)
        z = alt(x, y)
        q = Vector((x, y, 0)) * 0.7 + fase
        z += (0.08 * M.fbm(q, 4, 2) + 0.02 * M.ruido(q * 7, 3)) * min(1.0, z / 0.3)
        return (x, y, max(0.0, z))

    o = grade("baia", f, round((X1 - X0) / 0.18), round((Y1 - Y0) / 0.18), fora=(0, 0, 1))
    B.apagar_faces(o, lambda c: c.z < 0.004)
    r.add(M.material(M.suave(o, 60), B.mat_terra("laterita", "#9a7a5a", "#685038", 0.3)), "Baia")
    for i, (x0, x1, y0, y1) in enumerate(berm):
        cx0, cx1 = x0 + H, x1 - H
        cy0, cy1 = y0 + H, y1 - H
        r.prisma(
            f"Talude{i}",
            [
                (x0, y0, 0),
                (x1, y0, 0),
                (x0, y1, 0),
                (x1, y1, 0),
                (cx0, cy0, H),
                (cx1, cy0, H),
                (cx0, cy1, H),
                (cx1, cy1, H),
            ],
            "para",
            "Earth",
        )
    # piso de M8A1: 10 colunas de 0,559 m ao longo de Y, 3 placas por coluna em amarração
    m8 = B.mat_aco_ferrugem("m8a1", "#77705f", 0.5)
    Lp, Wp, Hp = 3.658, 0.559, 0.03
    for i in range(10):
        x = -bx + Wp / 2 + i * Wp
        if i % 2 == 0:
            segs = [(-by + k * Lp, Lp) for k in range(3)]
        else:
            segs = [(-by, Lp / 2), (-by + Lp / 2, Lp), (-by + 1.5 * Lp, Lp), (by - Lp / 2, Lp / 2)]
        for y0, comp in segs:
            r.add(
                bloco(
                    "m8a1", (Wp - 0.008, comp - 0.008, Hp), (x, y0 + comp / 2, Hp / 2), m8, 0.004
                ),
                "Piso",
            )
    r.caixa("Piso", (0, 0, Hp / 2), (2 * bx, 2 * by, Hp), "para", "Metal")
    return r


# =============================================================== combustível, água e carga
def receita_us_fuel_drums():
    """Ponto de combustível: 4 tambores de 55 galões em pé sobre dormentes, 2 deitados com calços
    e bomba manual rotativa num deles. Tambor: Ø 0,584 x 0,876 m (Wikipedia). Cor e estêncil
    (MOGAS, AVGAS 115/145): PLACEHOLDER."""
    r = Receita()
    tinta = N.mat_tinta("tambor_od", "#4e5233", desgaste=0.6, escala=150.0)
    est = N.mat_estencil("estencil_tambor", "#d9d2b6", "#4e5233", gasto=0.35, escala=150.0)
    mw = N.mat_madeira("dormente", "#6e5a42", "#4a3b2a", "#6b6458", eixo="X")
    for y in (-0.22, 0.22):
        r.add(bloco("dormente", (2.7, 0.15, 0.15), (0, y, 0.075), mw, 0.006))
    textos = ["MOGAS", "MOGAS", "AVGAS", "AVGAS"]
    for k, x in enumerate((-0.95, -0.32, 0.32, 0.95)):
        objs = B.tambor(f"tambor{k}", (0, 0, 0), tinta, sem=k)
        t = M.texto_malha(textos[k], 0.075, B.FONTE_ESTENCIL)
        M.enrolar(t, lambda z: 0.292, 0.5, ang0=-math.pi / 2, folga=0.0006)
        objs.append(N.so_bake(M.material(t, est)))
        if textos[k] == "AVGAS":
            t2 = M.texto_malha("115/145", 0.05, B.FONTE_ESTENCIL)
            M.enrolar(t2, lambda z: 0.292, 0.39, ang0=-math.pi / 2, folga=0.0006)
            objs.append(N.so_bake(M.material(t2, est)))
        B.mover_todos(objs, (x, 0, 0.15))
        r.addv(objs)
    for k, x in enumerate((-0.48, 0.48)):
        r.addv(B.tambor(f"deitado{k}", (x, 0.95, 0.0), tinta, deitado=True, sem=10 + k))
        for s in (-1, 1):
            r.add(
                bloco(
                    "calco",
                    (0.12, 0.1, 0.08),
                    (x + s * 0.3, 0.95 - 0.26, 0.04),
                    mw,
                    0.004,
                    rot=(0, 0, 0),
                )
            )
            r.add(bloco("calco", (0.12, 0.1, 0.08), (x + s * 0.3, 0.95 + 0.26, 0.04), mw, 0.004))
    # bomba manual no 2º tambor
    bomba = N.mat_tinta("bomba", "#5a2d22", desgaste=0.6, escala=200.0)
    xb = -0.32 + 0.17
    ztop = 0.15 + 0.876
    r.add(vara("tubo_bomba", (xb, 0, ztop), (xb, 0, ztop + 0.32), 0.022, mat=bomba))
    r.add(bloco("corpo_bomba", (0.14, 0.12, 0.14), (xb, 0, ztop + 0.4), bomba, 0.01))
    r.add(
        viga(
            "manivela",
            (xb + 0.07, 0, ztop + 0.4),
            (xb + 0.07, -0.2, ztop + 0.52),
            0.02,
            0.02,
            bomba,
        )
    )
    r.add(vara("bico", (xb, 0.06, ztop + 0.42), (xb, 0.25, ztop + 0.36), 0.015, mat=bomba))
    r.caixa("TamboresEmPe", (0, 0, 0.53), (2.6, 0.62, 1.06), "para", "Metal")
    r.caixa("TamboresDeitados", (0, 0.95, 0.3), (1.9, 0.62, 0.6), "para", "Metal")
    return r


def receita_us_water_trailer():
    """Reboque-pipa de 400 galões tipo M107 (TM 9-2330-213-14&P: 4,14 x 2,09 m, 1,95 m até a
    tampa). Tanque, chassi, eixo com 2 rodas, para-lamas, cambão com olhal, pé de apoio e 4
    torneiras atrás. Desenho do tanque e rodas: PLACEHOLDER dentro das medidas do TM."""
    r = Receita()
    od = N.mat_tinta("pipa_od", "#4c5032", desgaste=0.55, escala=120.0)
    est = N.mat_estencil("estencil_pipa", "#d9d2b6", "#4c5032", gasto=0.3, escala=120.0)
    aco = N.mat_aco("torneira", "#8e8c84", 0.4, 300.0)
    pneu = B.mat_borracha("pneu_pipa")
    # tanque elíptico de 2,4 m (eixo Y), 1,25 x 0,95 m, apoiado a 0,95 m
    a, b = 0.625, 0.475
    zc = 0.95 + b
    perfil = [
        (0.0, -1.2),
        (0.32, -1.19),
        (0.52, -1.14),
        (0.6, -1.06),
        (a, -0.95),
        (a, 0.95),
        (0.6, 1.06),
        (0.52, 1.14),
        (0.32, 1.19),
        (0.0, 1.2),
    ]
    tanque = M.torno("tanque", perfil, segs=40, fatiar=0.15)
    M.mover(tanque, Matrix.Rotation(math.pi / 2, 4, "X"))
    M.mover(tanque, Matrix.Diagonal((1.0, 1.0, b / a, 1.0)))
    M.mover(tanque, Matrix.Translation((0, 0.2, zc)))
    r.add(M.material(M.suave(tanque, 50), od))
    for y in (-0.55, 0.2, 0.95):
        aro = M.toro("cinta", a + 0.004, 0.012, 40, 6)
        M.mover(
            aro,
            Matrix.Translation((0, y, zc))
            @ Matrix.Diagonal((1.0, 1.0, b / a, 1.0))
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        r.add(M.material(aro, od))
    r.add(B.cilindro("boca", 0.2, 0.06, (0, -0.2, zc + b + 0.0), od, 24))
    r.add(B.cilindro("tampa", 0.215, 0.03, (0, -0.2, zc + b + 0.045), od, 24))
    for s in (-1, 1):
        r.add(
            vara(
                "passadico",
                (s * 0.18, -0.9, zc + b - 0.02),
                (s * 0.18, 1.2, zc + b - 0.02),
                0.012,
                mat=od,
                segs=6,
            )
        )
    for lado in (-1, 1):
        t = M.texto_malha("WATER", 0.16, B.FONTE_ESTENCIL)
        rot = Matrix.Rotation(lado * math.pi / 2, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X")
        M.mover(t, Matrix.Translation((lado * a, -0.25, zc)) @ rot)

        def colar(co, n, lado=lado):
            q = max(-0.99, min(0.99, (co.z - zc) / b))
            x = lado * (a * math.sqrt(1 - q * q) + 0.0015)
            return Vector((x - co.x, 0.0, 0.0))

        M.deslocar(t, colar)
        r.add(N.so_bake(M.material(t, est)))
    # chassi
    for s in (-1, 1):
        r.add(bloco("longarina", (0.08, 3.0, 0.15), (s * 0.45, 0.15, 0.85), od, 0.004))
    for y in (-1.2, -0.2, 0.8, 1.55):
        r.add(bloco("travessa", (1.0, 0.08, 0.1), (0, y, 0.82), od, 0.004))
    r.add(bloco("para_choque", (1.6, 0.1, 0.14), (0, 1.68, 0.72), od, 0.006))
    # eixo e rodas (pneu Ø 0,86 m: PLACEHOLDER)
    R = 0.43
    r.add(vara("eixo", (-0.85, 0.2, R), (0.85, 0.2, R), 0.04, mat=od))
    for s in (-1, 1):
        pn = M.torno(
            "pneu",
            [
                (0.2, -0.11),
                (0.33, -0.12),
                (0.41, -0.1),
                (R, -0.06),
                (R, 0.06),
                (0.41, 0.1),
                (0.33, 0.12),
                (0.2, 0.11),
            ],
            segs=36,
        )
        M.mover(pn, Matrix.Translation((s * 0.88, 0.2, R)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
        r.add(M.material(M.suave(pn, 45), pneu))
        cubo = M.torno("aro", [(0.0, -0.08), (0.21, -0.09), (0.21, 0.09), (0.0, 0.08)], segs=24)
        M.mover(cubo, Matrix.Translation((s * 0.88, 0.2, R)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
        r.add(M.material(M.suave(cubo, 40), od))
        para = M.torno(
            "paralama", [(0.5, -0.13), (0.52, -0.13), (0.52, 0.13), (0.5, 0.13)], segs=32
        )
        B.apagar_faces(para, lambda c: c.x > -0.02)
        M.mover(para, Matrix.Translation((s * 0.88, 0.2, R)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
        M.solidificar(para, 0.004, 0.0)
        r.add(M.material(M.suave(para, 40), od))
    # cambão em A com olhal e pé de apoio
    for s in (-1, 1):
        r.add(viga("cambao", (s * 0.45, -1.2, 0.82), (0, -2.0, 0.62), 0.07, 0.09, od))
    r.add(bloco("cambao_ponta", (0.08, 0.2, 0.08), (0, -2.08, 0.6), od, 0.004))
    olhal = M.toro("olhal", 0.06, 0.016, 16, 6)
    M.mover(olhal, Matrix.Translation((0, -2.2, 0.6)))
    r.add(M.material(olhal, aco))
    r.add(vara("pe_apoio", (0, -1.6, 0.72), (0, -1.62, 0.0), 0.035, mat=od))
    r.add(bloco("sapata", (0.16, 0.16, 0.02), (0, -1.62, 0.01), od, 0.003))
    # torneiras atrás (4)
    r.add(vara("coletor", (-0.35, 1.45, 1.02), (0.35, 1.45, 1.02), 0.03, mat=od))
    for k in range(4):
        x = -0.3 + k * 0.2
        r.add(vara("torneira", (x, 1.47, 1.02), (x, 1.56, 0.98), 0.014, mat=aco, segs=8))
        r.add(bloco("registro", (0.05, 0.02, 0.02), (x, 1.5, 1.06), aco, 0.003))
    for s in (-1, 1):
        r.add(
            bloco(
                "lanterna",
                (0.12, 0.05, 0.08),
                (s * 0.68, 1.72, 0.8),
                B.mat_tinta_lisa(f"lanterna{s}", "#6d1d1a", 0.3),
                0.006,
            )
        )
    r.caixa("Tanque", (0, 0.2, zc), (1.3, 2.45, 2 * b), "para", "Metal")
    r.caixa("Rodas", (0, 0.2, R), (2.09, 0.9, 2 * R), "para", "Rubber")
    r.caixa("Chassi", (0, 0.15, 0.82), (1.0, 3.2, 0.2), "para", "Metal")
    return r


def receita_us_generator():
    """Gerador de campanha de 10 kW a gasolina sobre skid: 1,45 x 0,74 x 0,73 m (MEP-018A,
    TM 5-6115-275-14, 1977). O modelo em uso em ago/1965 não foi achado: PLACEHOLDER."""
    r = Receita()
    od = N.mat_tinta("gerador_od", "#4c5032", desgaste=0.6, escala=200.0)
    aco = N.mat_aco("gerador_aco", "#5d5b55", 0.5, 200.0)
    preto = N.mat_tinta("motor", "#2c2c29", desgaste=0.5, escala=250.0)
    for s in (-1, 1):
        r.add(bloco("skid", (0.06, 1.45, 0.1), (s * 0.32, 0, 0.05), od, 0.004))
    for y in (-0.6, 0.0, 0.6):
        r.add(bloco("travessa", (0.7, 0.06, 0.05), (0, y, 0.09), od, 0.003))
    r.add(bloco("motor", (0.42, 0.45, 0.38), (0, -0.35, 0.31), preto, 0.02))
    for k in range(6):
        r.add(bloco("aleta", (0.46, 0.012, 0.16), (0, -0.52 + k * 0.035, 0.42), preto, 0.002))
    r.add(B.cilindro("gerador", 0.2, 0.48, (0, 0.18, 0.33), od, 28, "Y"))
    r.add(bloco("painel", (0.5, 0.12, 0.34), (0, 0.55, 0.36), od, 0.01))
    for k, x in enumerate((-0.15, 0.0, 0.15)):
        r.add(
            B.cilindro(
                "relogio",
                0.035,
                0.012,
                (x, 0.618, 0.44),
                B.mat_tinta_lisa(f"mostrador{k}", "#d9d4c4", 0.3),
                16,
                "Y",
            )
        )
    r.add(bloco("tanque", (0.5, 0.55, 0.14), (0, 0.05, 0.62), od, 0.03))
    r.add(B.cilindro("bocal", 0.04, 0.05, (0.15, -0.1, 0.71), aco, 12))
    r.add(B.cilindro("abafador", 0.07, 0.3, (0.27, -0.45, 0.45), aco, 16, "Y"))
    r.add(vara("escape", (0.27, -0.6, 0.45), (0.27, -0.72, 0.52), 0.025, mat=aco))
    for s in (-1, 1):
        r.add(vara("quadro", (s * 0.33, -0.7, 0.1), (s * 0.33, -0.7, 0.72), 0.016, mat=od, segs=8))
        r.add(vara("quadro", (s * 0.33, 0.7, 0.1), (s * 0.33, 0.7, 0.72), 0.016, mat=od, segs=8))
        r.add(vara("quadro", (s * 0.33, -0.7, 0.72), (s * 0.33, 0.7, 0.72), 0.016, mat=od, segs=8))
    est = N.mat_estencil("estencil_ger", "#d9d2b6", "#4c5032", gasto=0.3, escala=200.0)
    r.add(B.letreiro("10 KW", 0.05, est, (-0.2012, 0.18, 0.33), "-X"))
    r.caixa("Gerador", (0, 0, 0.37), (0.74, 1.45, 0.74), "para", "Metal")
    return r


def receita_us_conex():
    """Contêiner CONEX: 2,59 x 1,91 x 2,10 m (8 pés 6 pol x 6 pés 3 pol x 6 pés 10,5 pol;
    Wikipedia, Conex box). Paredes de aço nervurado, porta dupla numa cabeceira com barras de
    trava, base com skids, olhais de içamento. Nervuras, cor e estêncil: PLACEHOLDER."""
    r = Receita()
    od = N.mat_tinta("conex_od", "#4f5434", desgaste=0.5, escala=100.0)
    est = N.mat_estencil("estencil_conex", "#d9d2b6", "#4f5434", gasto=0.35, escala=100.0)
    aco = N.mat_aco("conex_aco", "#5d5b55", 0.5, 200.0)
    Lc, Wc, Hc = 2.59, 1.91, 2.10
    hb = 0.12
    r.add(
        bloco("corpo", (Wc - 0.04, Lc - 0.04, Hc - hb - 0.04), (0, 0, hb + (Hc - hb) / 2), od, 0.01)
    )
    for s in (-1, 1):
        for k in range(8):
            y = -Lc / 2 + 0.25 + k * (Lc - 0.5) / 7
            r.add(
                bloco(
                    "nervura",
                    (0.03, 0.08, Hc - hb - 0.2),
                    (s * (Wc / 2 - 0.01), y, hb + (Hc - hb) / 2),
                    od,
                    0.004,
                )
            )
    for k in range(6):
        x = -Wc / 2 + 0.25 + k * (Wc - 0.5) / 5
        r.add(
            bloco(
                "nervura_f",
                (0.08, 0.03, Hc - hb - 0.2),
                (x, Lc / 2 - 0.01, hb + (Hc - hb) / 2),
                od,
                0.004,
            )
        )
    for sx in (-1, 1):
        for sy in (-1, 1):
            r.add(
                bloco(
                    "canto",
                    (0.1, 0.1, Hc),
                    (sx * (Wc / 2 - 0.05), sy * (Lc / 2 - 0.05), Hc / 2),
                    od,
                    0.006,
                )
            )
            olhal = M.toro("olhal", 0.04, 0.01, 12, 5)
            M.mover(
                olhal,
                Matrix.Translation((sx * (Wc / 2 - 0.08), sy * (Lc / 2 - 0.08), Hc + 0.03))
                @ Matrix.Rotation(math.pi / 2, 4, "X"),
            )
            r.add(M.material(olhal, aco))
    for s in (-1, 1):
        r.add(bloco("skid", (0.12, Lc, hb), (s * (Wc / 2 - 0.15), 0, hb / 2), od, 0.005))
    # porta dupla na frente (-Y)
    for s in (-1, 1):
        r.add(
            bloco(
                "folha",
                (Wc / 2 - 0.1, 0.03, Hc - hb - 0.16),
                (s * (Wc / 4 - 0.01), -Lc / 2 - 0.005, hb + (Hc - hb) / 2),
                od,
                0.006,
            )
        )
        for x in (s * 0.2, s * 0.65):
            r.add(
                vara(
                    "barra",
                    (x, -Lc / 2 - 0.04, hb + 0.05),
                    (x, -Lc / 2 - 0.04, Hc - 0.05),
                    0.014,
                    mat=aco,
                    segs=8,
                )
            )
            r.add(bloco("manopla", (0.03, 0.06, 0.2), (x, -Lc / 2 - 0.07, hb + 0.95), aco, 0.004))
        for z in (hb + 0.3, Hc - 0.3):
            r.add(
                bloco(
                    "dobradica",
                    (0.08, 0.04, 0.12),
                    (s * (Wc / 2 - 0.08), -Lc / 2 - 0.03, z),
                    aco,
                    0.004,
                )
            )
    yf = -Lc / 2 - 0.021
    r.add(B.letreiro("CONEX", 0.12, est, (-Wc / 4, yf, 1.6), "-Y"))
    r.add(B.letreiro("U.S.", 0.12, est, (Wc / 4, yf, 1.6), "-Y"))
    for s, normal in ((-1, "-X"), (1, "+X")):
        r.add(B.letreiro("USMC", 0.16, est, (s * (Wc / 2 + 0.032), 0.0, 1.3), normal))
    r.caixa("Conex", (0, 0, Hc / 2), (Wc, Lc, Hc), "para", "Metal")
    return r


def receita_us_jerrycans():
    """Galões de 5 galões (combustível e água): 0,33 x 0,168 x ~0,46 m (TM 10-7200-200-13, trecho
    com OCR ruim: medida parcial). 3 de combustível e 1 de água (tampa larga), com o X estampado
    dos lados. Marcas: PLACEHOLDER."""
    r = Receita()
    od = N.mat_tinta("galao_od", "#4c5032", desgaste=0.65, escala=250.0)
    est = N.mat_estencil("estencil_galao", "#d9d2b6", "#4c5032", gasto=0.3, escala=250.0)
    W_, D_, H_ = 0.33, 0.168, 0.46
    pos = [
        (-0.36, 0.0, 0.0, False),
        (0.0, 0.0, 0.05, False),
        (0.36, 0.0, -0.04, True),
        (0.0, 0.42, 0.0, False),
    ]
    for k, (x, y, rz, agua) in enumerate(pos):
        # sem o X estampado: deformar a caixa deixava quadrados pretos depois da redução; no lugar,
        # a costura soldada em volta do meio
        corpo = M.caixa("galao", (W_, D_, H_ - 0.04), (0, 0, (H_ - 0.04) / 2), cortes=1)
        M.chanfrar(corpo, 0.012, 2)
        objs = [M.material(M.suave(corpo, 35), od)]
        costura = M.caixa("costura", (W_ + 0.008, 0.006, H_ - 0.05), (0, 0, (H_ - 0.04) / 2))
        objs.append(M.material(costura, od))
        for dx in (-0.09, 0.0, 0.09):
            al = vara("alca", (dx, -0.04, H_ - 0.04), (dx, 0.04, H_ - 0.04), 0.01, mat=od, segs=6)
            objs.append(al)
            objs.append(
                vara(
                    "alca_p", (dx, -0.04, H_ - 0.06), (dx, -0.04, H_ - 0.01), 0.008, mat=od, segs=6
                )
            )
            objs.append(
                vara("alca_p", (dx, 0.04, H_ - 0.06), (dx, 0.04, H_ - 0.01), 0.008, mat=od, segs=6)
            )
        rb = 0.035 if agua else 0.022
        objs.append(B.cilindro("bocal", rb, 0.04, (W_ / 2 - 0.06, 0, H_ - 0.03), od, 16))
        t = M.texto_malha("WATER" if agua else "MOGAS", 0.05, B.FONTE_ESTENCIL)
        M.mover(
            t,
            Matrix.Translation((0, -D_ / 2 - 0.0012, 0.24)) @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        objs.append(N.so_bake(M.material(t, est)))
        if k == 3:
            m = (
                Matrix.Translation((x, y, D_ / 2))
                @ Matrix.Rotation(rz, 4, "Z")
                @ Matrix.Rotation(-math.pi / 2, 4, "X")
            )
        else:
            m = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(rz, 4, "Z")
        for o in objs:
            M.mover(o, m)
        r.addv(objs)
    r.caixa("Galoes", (0, 0.15, 0.23), (1.1, 0.75, 0.46), "para", "Metal")
    return r
