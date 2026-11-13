"""Caminhão M35 de 2½ t, 6x6, de carga (USMC), em partes para o jogo.

Capô estreito e chato, para-lamas da frente largos com os faróis e a grade com guarda, cabine
aberta com capota de lona e para-brisa de dois vidros, filtro de ar redondo no lado direito,
guincho no para-choque, caçamba de aço com grades de madeira (bancos da tropa) e os arcos sem a
lona, estepe atrás da cabine, eixo da frente com rodas simples e os dois de trás com rodas duplas.
Partes: Casco, Volante, Porta_E (motorista), Porta_D (carona), Tampa_Traseira, Roda_FE, Roda_FD
(simples), Roda_T1E, Roda_T1D (1º eixo de trás), Roda_T2E, Roda_T2D (2º eixo de trás; duplas: as
duas rodas de cada ponta do eixo numa peça). E = esquerda = lado do motorista.
"""

from __future__ import annotations

import math

import modelar as M
import novos as N
import veic_base as B
from mathutils import Matrix, Vector

WK = "https://en.wikipedia.org/wiki/M35_2%C2%BD-ton_cargo_truck"
NF = "https://www.nf6x.net/2006/05/m35a2c-2-5-ton-6x6-cargo-truck/"
MEDIDAS = {
    "comprimento_m": [6.98, f"Wikipedia: 274¾ pol com guincho ({WK})"],
    "largura_m": [2.36, f"Wikipedia: 93 pol ({WK}); M35A2: 96 pol (militarytrader.com)"],
    "altura_cabine_m": [2.82, f"Wikipedia: 111 pol até a cabine ({WK})"],
    "entre_eixos_m": [3.91, f"nf6x: 154 pol ({NF})"],
    "pneus": [
        "9.00-20",
        f"nf6x e Military Trader: duplos atrás ({NF}); diâmetro 0,96 m "
        "calculado do tamanho: PLACEHOLDER",
    ],
    "cacamba_m": [[2.44, 3.66], f"Wikipedia: 8 x 12 pés; tampa de 16 pol ({WK})"],
    "distancia_eixos_traseiros_m": [1.30, "PLACEHOLDER (sem fonte)"],
    "bitola_m": [1.72, "PLACEHOLDER (sem fonte)"],
    "altura_arcos_m": [
        2.85,
        "PLACEHOLDER: o M35A2C tem 112 pol reduzível a 81 (nf6x); arcos sem a lona aqui",
    ],
    "variante": [
        None,
        "sem fonte: qual M35 o USMC usava em 1965 (M35A2 entregue a partir de jun/"
        "1965, fórum). Desenho genérico do M35 a gasolina",
    ],
    "marcas": [
        None,
        "norma USMC de dez/1963 (garbee.net/~cabell/usmcmarkings.htm): 'USMC' + "
        "registro em linha única dos dois lados do capô e no alto da tampa traseira, sem "
        "estrela. Número '351906' e o amarelo: PLACEHOLDER",
    ],
}

XF, XR = 6.98 / 2, -6.98 / 2
X_FA = XF - 1.15
X_T = X_FA - 3.91
X_T1, X_T2 = X_T + 0.65, X_T - 0.65
Y_W, R_W, L_W = 1.72 / 2, 0.48, 0.23
Z_W = R_W
Z_BED = 1.25
X_BED0, X_BED1 = XR, XR + 3.66
X_CAB0, X_CAB1 = X_BED1 + 0.18, X_BED1 + 1.3
VOL = Vector((X_CAB1 - 0.45, 0.45, 1.85))


def receita():
    mt = B.Montagem()
    od = mt.mat("pintura", B.mat_pintura, fundido=0.0, z_lama=1.0, desgaste=0.6)
    lona = mt.mat("lona", B.mat_lona, "#57553b", "#6e6a4c", 0.0)
    madeira = mt.mat("madeira", N.mat_madeira, "#7b6b52", "#4d3f2e", "#6d675c", eixo="X")
    aco = mt.mat("aco", B.mat_aco_sujo, z_lama=0.9)
    aco_esc = mt.mat("aco_escuro", B.mat_simples, "#1e1d1a", 0.5, 0.6)
    borr = mt.mat("borracha", B.mat_borracha, z_lama=0.7)
    vidro = mt.mat("vidro", B.mat_vidro, "#2a3236", 0.08)
    amarelo = mt.mat("estencil", B.mat_estencil, "#d4bd55", "#56583a", 0.4)
    lente_v = mt.mat("lente_vermelha", B.mat_simples, "#5c1712", 0.25, 0.0)
    corda = mt.mat("corda", N.mat_corda, "#7d6e4c")

    P = "Casco"
    # chassi: longarinas e travessas
    for s in (1, -1):
        mt.geo(
            P,
            B.caixa(
                "longarina",
                (XF - XR - 0.3, 0.08, 0.24),
                ((XF + XR) / 2 - 0.1, s * 0.45, 0.95),
                0.01,
            ),
            aco,
        )
    for x in (X_FA + 0.6, X_FA - 1.2, X_T + 0.1, XR + 0.35):
        mt.geo(P, B.caixa("travessa", (0.1, 0.9, 0.12), (x, 0, 0.95), 0.01), aco)
    # eixos e diferenciais
    for xa in (X_FA, X_T1, X_T2):
        mt.geo(P, B.cil("eixo", (xa, -Y_W + 0.2, Z_W), (xa, Y_W - 0.2, Z_W), 0.06, 10), aco)
        mt.geo(
            P,
            M.torno("dif", [(0.0, -0.16), (0.2, -0.16), (0.22, 0.0), (0.2, 0.14), (0.0, 0.16)], 12),
            aco,
        )
        M.mover(
            mt.partes[P]["geo"][-1],
            Matrix.Translation((xa, 0, Z_W)) @ Matrix.Rotation(math.pi / 2, 4, "Y"),
        )
    for s in (1, -1):
        mt.geo(P, B.caixa("feixe", (1.9, 0.09, 0.12), (X_T, s * 0.62, Z_W + 0.2), 0.01), aco)
        mt.geo(P, B.caixa("feixe_f", (1.2, 0.08, 0.1), (X_FA, s * 0.5, Z_W + 0.22), 0.01), aco)
    # capô, grade com guarda e para-lamas
    xg = XF - 0.42
    mt.geo(P, B.caixa("capo", (xg - X_CAB1, 1.12, 0.06), ((xg + X_CAB1) / 2, 0, 1.95), 0.02), od)
    mt.geo(P, B.caixa("cofre", (xg - X_CAB1, 1.06, 0.75), ((xg + X_CAB1) / 2, 0, 1.55), 0.0), od)
    mt.geo(P, B.caixa("grade", (0.05, 1.12, 0.8), (xg + 0.02, 0, 1.55), 0.012), od)
    g = B.Lote("grade_b")
    for k in range(7):
        g.caixa((0.03, 0.025, 0.72), Matrix.Translation((xg + 0.07, -0.42 + k * 0.14, 1.55)))
    for k in range(3):
        g.caixa((0.03, 1.0, 0.025), Matrix.Translation((xg + 0.07, 0, 1.25 + k * 0.3)))
    mt.geo(P, g.objeto(), od)
    for s in (1, -1):
        mt.geo(
            P,
            B.caixa(
                "paralama",
                (xg - X_CAB1 + 0.3, 0.62, 0.04),
                ((xg + X_CAB1) / 2 + 0.1, s * 0.87, 1.36),
                0.012,
            ),
            od,
        )
        mt.geo(
            P,
            B.caixa(
                "paralama_f",
                (0.04, 0.62, 0.3),
                (xg + 0.25, s * 0.87, 1.22),
                0.01,
                (0, math.radians(30), 0),
            ),
            od,
        )
        mt.geo(P, B.caixa("saia", (0.6, 0.03, 0.3), (X_CAB1 + 0.3, s * 0.57, 1.22), 0.008), od)
        xl = xg + 0.12
        mt.geo(
            P, B.cil("farol", (xl - 0.06, s * 0.87, 1.5), (xl + 0.06, s * 0.87, 1.5), 0.11, 14), od
        )
        mt.geo(
            P,
            B.cil("lente", (xl + 0.06, s * 0.87, 1.5), (xl + 0.065, s * 0.87, 1.5), 0.09, 14),
            vidro,
        )
        arco = [
            (
                xl + 0.14,
                s * 0.87 + 0.15 * math.cos(math.pi * k / 6),
                1.38 + 0.25 * math.sin(math.pi * k / 6),
            )
            for k in range(7)
        ]
        mt.geo(P, M.tubo("guarda", arco, 0.012, 6), od)
        mt.geo(P, B.caixa("luz_bo", (0.06, 0.08, 0.06), (xg - 0.05, s * 1.0, 1.42), 0.008), od)
        mt.geo(P, B.caixa("lanterna", (0.04, 0.14, 0.1), (XR + 0.02, s * 1.05, 1.08), 0.008), od)
        mt.det(P, B.caixa("lente_t", (0.01, 0.1, 0.06), (XR - 0.002, s * 1.05, 1.1)), lente_v)
        mt.det(
            P,
            B.letreiro(
                "USMC 351906",
                0.06,
                amarelo,
                ((xg + X_CAB1) / 2, s * 0.532, 1.72),
                "+Y" if s > 0 else "-Y",
            ),
            amarelo,
        )
        # degrau e espelho
        mt.geo(P, B.caixa("degrau", (0.4, 0.22, 0.03), (X_CAB0 + 0.6, s * 1.08, 0.9), 0.006), od)
        mt.geo(
            P,
            B.cil(
                "braco_esp",
                (X_CAB1 + 0.05, s * 1.1, 1.95),
                (X_CAB1 + 0.05, s * 1.3, 2.25),
                0.012,
                6,
            ),
            aco_esc,
        )
        mt.geo(
            P,
            B.caixa("espelho", (0.03, 0.18, 0.26), (X_CAB1 + 0.05, s * 1.32, 2.35), 0.01),
            aco_esc,
        )
    # para-choque com guincho e ganchos
    mt.geo(P, B.caixa("parachoque", (0.14, 2.3, 0.22), (XF - 0.08, 0, 0.82), 0.015), od)
    mt.geo(P, B.cil("guincho", (XF - 0.3, -0.35, 0.95), (XF - 0.3, 0.35, 0.95), 0.14, 14), od)
    mt.geo(P, B.cil("cabo", (XF - 0.3, -0.3, 0.95), (XF - 0.3, 0.3, 0.95), 0.155, 14), aco)
    for s in (1, -1):
        g = M.toro("gancho", 0.06, 0.018, 12, 6)
        M.mover(
            g, Matrix.Translation((XF - 0.02, s * 0.8, 0.82)) @ Matrix.Rotation(math.pi / 2, 4, "X")
        )
        mt.geo(P, g, aco)
    # filtro de ar redondo (lado direito do capô, junto da cabine)
    mt.geo(
        P, B.cil("filtro", (X_CAB1 + 0.25, -0.75, 1.55), (X_CAB1 + 0.25, -0.75, 2.05), 0.16, 14), od
    )
    # cabine aberta: assoalho, painel, porta-baixa, bancos, para-brisa e capota de lona
    mt.geo(
        P,
        B.caixa("assoalho", (X_CAB1 - X_CAB0, 2.0, 0.05), ((X_CAB0 + X_CAB1) / 2, 0, 1.2), 0.0),
        od,
    )
    mt.geo(P, B.caixa("fundo_cab", (0.05, 2.0, 0.85), (X_CAB0, 0, 1.6), 0.01), od)
    for s, nome in ((1, "Porta_E"), (-1, "Porta_D")):
        mt.geo(
            nome,
            B.caixa(
                "porta",
                (X_CAB1 - X_CAB0 - 0.12, 0.05, 0.6),
                ((X_CAB0 + X_CAB1) / 2 - 0.01, s * 1.0, 1.52),
                0.012,
            ),
            od,
        )
        mt.geo(
            nome,
            B.caixa("macaneta", (0.12, 0.03, 0.03), (X_CAB0 + 0.2, s * 1.035, 1.7), 0.006),
            aco_esc,
        )
        mt.pivo(nome, (X_CAB1 - 0.06, s * 1.0, 1.52))  # dobradiça na frente, eixo vertical
        mt.atlas(nome, "a")
    for s in (1, -1):
        mt.geo(P, B.caixa("assento", (0.5, 0.55, 0.1), (X_CAB0 + 0.4, s * 0.45, 1.5), 0.03), lona)
        mt.geo(
            P,
            B.caixa(
                "encosto",
                (0.1, 0.55, 0.55),
                (X_CAB0 + 0.12, s * 0.45, 1.85),
                0.03,
                (0, math.radians(-8), 0),
            ),
            lona,
        )
    mt.geo(P, B.caixa("painel", (0.2, 2.0, 0.25), (X_CAB1 - 0.08, 0, 1.75), 0.012), od)
    mt.geo(P, B.cil("coluna", (X_CAB1 - 0.15, VOL.y, 1.7), tuple(VOL), 0.03, 8), aco_esc)
    fr = Matrix.Translation((X_CAB1, 0, 1.9)) @ Matrix.Rotation(math.radians(-8), 4, "Y")
    for nome, dim, c in (
        ("pb_base", (0.05, 2.0, 0.05), (0, 0, 0.0)),
        ("pb_topo", (0.05, 2.0, 0.05), (0, 0, 0.62)),
        ("pb_l1", (0.05, 0.05, 0.64), (0, 0.98, 0.31)),
        ("pb_l2", (0.05, 0.05, 0.64), (0, -0.98, 0.31)),
        ("pb_meio", (0.05, 0.05, 0.64), (0, 0, 0.31)),
    ):
        o = B.caixa(nome, dim, c, 0.008)
        M.mover(o, fr)
        mt.geo(P, o, od)
    for s in (1, -1):
        o = B.caixa("vidro", (0.012, 0.93, 0.56), (0, s * 0.49, 0.31))
        M.mover(o, fr)
        mt.geo(P, o, vidro)
    capota = B.caixa(
        "capota",
        (X_CAB1 - X_CAB0 + 0.05, 2.04, 0.04),
        ((X_CAB0 + X_CAB1) / 2 - 0.05, 0, 2.79),
        0.015,
    )
    M.deslocar(capota, lambda co, n: 0.012 * M.fbm(co * 4, 3, 61))
    mt.geo(P, capota, lona)
    for s in (1, -1):
        mt.geo(
            P,
            B.cil(
                "pilar_t", (X_CAB0 + 0.02, s * 0.98, 2.0), (X_CAB0 + 0.02, s * 0.98, 2.78), 0.02, 6
            ),
            aco,
        )
    # tanque de combustível (direita, embaixo da cabine) e caixa da bateria (esquerda)
    mt.geo(P, B.caixa("tanque", (0.75, 0.32, 0.36), (X_CAB0 + 0.55, -0.82, 0.92), 0.06), od)
    mt.geo(P, B.caixa("bateria", (0.5, 0.3, 0.3), (X_CAB0 + 0.55, 0.82, 0.92), 0.02), od)
    # estepe vertical atrás da cabine (esquerda)
    perf = [
        (0.0, 0.12),
        (0.15, 0.12),
        (0.3, 0.1),
        (R_W, 0.09),
        (R_W, -0.09),
        (0.3, -0.12),
        (0.0, -0.12),
    ]
    est = B.torno_eixo("estepe", perf, "X", (X_CAB0 - 0.12, 0.5, 1.75), 14)
    M.material(est, borr)
    B.pintar_por(est, lambda c, n: math.hypot(c.y - 0.5, c.z - 1.75) < 0.3, od)
    mt.geo(P, est, None)
    # caçamba de aço: assoalho, laterais, frente e tampa
    mt.geo(
        P,
        B.caixa("cacamba", (X_BED1 - X_BED0, 2.36, 0.06), ((X_BED0 + X_BED1) / 2, 0, Z_BED), 0.01),
        od,
    )
    mt.geo(
        P,
        B.caixa(
            "viga_c", (X_BED1 - X_BED0, 1.1, 0.12), ((X_BED0 + X_BED1) / 2, 0, Z_BED - 0.09), 0.0
        ),
        od,
    )
    for s in (1, -1):
        mt.geo(
            P,
            B.caixa(
                "lateral",
                (X_BED1 - X_BED0, 0.04, 0.5),
                ((X_BED0 + X_BED1) / 2, s * 1.16, Z_BED + 0.25),
                0.01,
            ),
            od,
        )
        # para-lama traseiro (sobre as duplas)
        mt.geo(P, B.caixa("pl_t", (2.5, 0.5, 0.03), (X_T, s * 0.94, Z_BED - 0.08), 0.01), od)
        # grades de madeira (bancos dobrados para cima) e montantes
        for k in range(3):
            mt.geo(
                P,
                B.caixa(
                    "ripa",
                    (X_BED1 - X_BED0 - 0.1, 0.03, 0.09),
                    ((X_BED0 + X_BED1) / 2, s * 1.15, Z_BED + 0.62 + k * 0.2),
                    0.008,
                ),
                madeira,
            )
        for x in (X_BED0 + 0.1, X_BED0 + 1.25, X_BED0 + 2.4, X_BED1 - 0.1):
            mt.geo(
                P, B.caixa("montante", (0.05, 0.05, 0.62), (x, s * 1.16, Z_BED + 0.75), 0.006), od
            )
        mt.det(
            P,
            B.letreiro(
                "USMC 351906",
                0.06,
                amarelo,
                (X_BED0 + 0.5, s * 1.182, Z_BED + 0.3),
                "+Y" if s > 0 else "-Y",
            ),
            amarelo,
        )
    mt.geo(P, B.caixa("frente_c", (0.04, 2.36, 0.5), (X_BED1, 0, Z_BED + 0.25), 0.01), od)
    TT = "Tampa_Traseira"  # abre para baixo na dobradiça de baixo
    mt.geo(TT, B.caixa("tampa", (0.04, 2.2, 0.41), (X_BED0 + 0.02, 0, Z_BED + 0.24), 0.01), od)
    mt.det(
        TT,
        B.letreiro("USMC 351906", 0.07, amarelo, (X_BED0 - 0.002, 0, Z_BED + 0.37), "-X"),
        amarelo,
    )
    mt.pivo(TT, (X_BED0 + 0.02, 0, Z_BED + 0.04))
    mt.atlas(TT, "a")
    # arcos (sem a lona) e a lona enrolada na frente
    for x in (X_BED0 + 0.15, X_BED0 + 1.0, X_BED0 + 1.85, X_BED0 + 2.7, X_BED1 - 0.12):
        arco = (
            [(x, 1.16, Z_BED + 0.5), (x, 1.16, 2.55)]
            + [
                (x, 1.16 * math.cos(math.pi * k / 8), 2.55 + 0.3 * math.sin(math.pi * k / 8))
                for k in range(1, 8)
            ]
            + [(x, -1.16, 2.55), (x, -1.16, Z_BED + 0.5)]
        )
        mt.geo(P, M.tubo("arco", arco, 0.018, 6, False), aco)
    rolo = B.cil("lona_enrolada", (X_BED1 - 0.25, -1.1, 2.72), (X_BED1 - 0.25, 1.1, 2.72), 0.13, 12)
    M.deslocar(rolo, lambda co, n: 0.015 * M.fbm(co * 5, 3, 62))
    mt.geo(P, rolo, lona)
    for y in (-0.7, 0.0, 0.7):
        mt.geo(P, M.toro("amarra", 0.14, 0.012, 12, 5), corda)
        M.mover(
            mt.partes[P]["geo"][-1],
            Matrix.Translation((X_BED1 - 0.25, y, 2.72)) @ Matrix.Rotation(math.pi / 2, 4, "Y"),
        )
    # engate traseiro
    mt.geo(P, B.cil("engate", (XR + 0.2, 0, 0.85), (XR - 0.08, 0, 0.85), 0.05, 10), aco)
    mt.atlas(P, "a")

    P = "Volante"
    v = M.toro("volante", 0.24, 0.016, 22, 6)
    M.mover(v, Matrix.Translation(VOL) @ Matrix.Rotation(math.radians(-50), 4, "Y"))
    mt.geo(P, v, aco_esc)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        p1 = VOL + (
            Matrix.Rotation(math.radians(-50), 3, "Y")
            @ Vector((0.23 * math.cos(a), 0.23 * math.sin(a), 0))
        )
        mt.geo(P, B.cil("raio", tuple(VOL), tuple(p1), 0.012, 6), aco_esc)
    mt.pivo(P, tuple(VOL))
    mt.atlas(P, "a")

    def pneu(x, y, z, dy=0.0):
        perf = [
            (0.0, L_W / 2),
            (0.15, L_W / 2),
            (0.27, L_W / 2),
            (R_W - 0.03, L_W / 2),
            (R_W, L_W / 2 - 0.04),
            (R_W, -L_W / 2 + 0.04),
            (R_W - 0.03, -L_W / 2),
            (0.27, -L_W / 2),
            (0.0, -L_W / 2),
        ]
        o = B.torno_eixo("pneu", perf, "Y", (x, y + dy, z), 18)
        M.material(o, borr)
        B.pintar_por(o, lambda c, n: math.hypot(c.x - x, c.z - z) < 0.29, od)
        return o

    P = "Roda_FE"
    mt.geo(P, pneu(X_FA, Y_W, Z_W), None)
    mt.geo(
        P,
        B.torno_eixo(
            "cubo",
            [(0.0, 0.2), (0.07, 0.2), (0.1, 0.16), (0.14, 0.12), (0.14, 0.1), (0.0, 0.1)],
            "Y",
            (X_FA, Y_W, Z_W),
            12,
        ),
        aco,
    )
    pf = B.Lote("porcas")
    for k in range(10):
        a = 2 * math.pi * k / 10
        pf.cil(
            0.014,
            0.022,
            Matrix.Translation(
                (X_FA + 0.2 * math.cos(a), Y_W + L_W / 2 + 0.008, Z_W + 0.2 * math.sin(a))
            )
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
            6,
        )
    mt.det(P, pf.objeto(), aco)
    mt.pivo(P, (X_FA, Y_W, Z_W))
    mt.atlas(P, "a")
    mt.instancia("Roda_FD", "Roda_FE", (X_FA, -Y_W, Z_W), giro_z180=True)
    P = "Roda_T1E"
    for dy in (0.135, -0.135):
        mt.geo(P, pneu(X_T1, Y_W, Z_W, dy), None)
    mt.geo(
        P,
        B.torno_eixo(
            "cubo_t",
            [(0.0, 0.32), (0.09, 0.32), (0.12, 0.28), (0.12, 0.24), (0.0, 0.24)],
            "Y",
            (X_T1, Y_W, Z_W),
            12,
        ),
        aco,
    )
    mt.pivo(P, (X_T1, Y_W, Z_W))
    mt.atlas(P, "a")
    mt.instancia("Roda_T1D", "Roda_T1E", (X_T1, -Y_W, Z_W), giro_z180=True)
    mt.instancia("Roda_T2E", "Roda_T1E", (X_T2, Y_W, Z_W))
    mt.instancia("Roda_T2D", "Roda_T1E", (X_T2, -Y_W, Z_W), giro_z180=True)

    info = {
        "nome": "M35 2½ t 6x6 de carga (USMC)",
        "faccao": "US",
        "medidas": MEDIDAS,
        "olhos": {
            "driver": (X_CAB0 + 0.35, 0.45, 2.3),
            "passenger": (X_CAB0 + 0.35, -0.45, 2.3),
        },
        "passageiros": {"x0": X_BED1 - 0.4, "dx": 0.55, "y": 0.85, "z": Z_BED + 1.25},
        "assentos_z": {"driver": 1.55, "passenger": 1.55},
        "antigo_placeholder": {"rotulo": "HOJE: não existe no jogo (boneco de 1,75 m p/ escala)"},
        "notas": [
            "Tropa na caçamba: 12 lugares (6 de cada lado, de costas para a grade), "
            "de x0 para trás.",
            "Rodas de trás duplas numa peça só por ponta de eixo (Roda_T1E/T1D/T2E/T2D).",
        ],
    }
    return mt, info
