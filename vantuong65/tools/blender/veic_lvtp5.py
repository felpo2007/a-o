"""LVTP-5A1 (amtrac dos fuzileiros, Vietnã 1965), em partes para o jogo.

Caixa de chapa com rampa de proa, cúpula G-1 com a .30 na frente entre o motorista (esquerda) e o
comandante (direita), 1 escotilha grande e 2 menores sobre a tropa, a caixa de admissão do A1 no
teto de trás, lagarta com garras invertidas (propulsão na água) sobre 9 rodas duplas por lado,
roda-guia alta na proa e motriz atrás. Partes: Casco, Torre (cúpula G-1), Escotilha_Rampa,
Escotilha_Motorista, Escotilha_Comandante, Escotilha_Tropa, Escotilha_TropaE/D, Esteira_E/D,
Roda_E1..E9 / Roda_D1..D9, Roda_EG/DG, Roda_EM/DM.
"""

from __future__ import annotations

import math

import modelar as M
import veic_base as B
from mathutils import Matrix, Vector

AF = "https://afvdatabase.com/usa/lvtp5.html"
WK = "https://en.wikipedia.org/wiki/LVTP-5"
MEDIDAS = {
    "comprimento_m": [9.04, f"afvdatabase: 356 pol ({AF}); Wikipedia: 9,04 m ({WK})"],
    "largura_m": [3.569, f"afvdatabase: 140,5 pol ({AF}); Wikipedia: 3,57 m"],
    "altura_cupula_m": [
        3.061,
        f"afvdatabase: 120,5 pol sobre a cúpula ({AF}); Wikipedia dá 2,92 m (sem a cúpula?)",
    ],
    "rodas": [
        9,
        f"afvdatabase: 9 pares duplos por lado, um com pneu maciço e o outro com aro de "
        f"aço; 5 roletes de retorno duplos; Torsilastic ({AF})",
    ],
    "motriz_guia": [None, f"afvdatabase: motriz atrás (17 dentes), guia na frente ({AF})"],
    "lagarta": [
        0.527,
        f"afvdatabase: 20,75 pol, passo 5 pol, 134 sapatas com guia central e "
        f"garras invertidas ({AF})",
    ],
    "bitola_m": [2.964, f"afvdatabase: 116,7 pol ({AF})"],
    "contato_solo_m": [5.823, f"afvdatabase: 229,25 pol ({AF})"],
    "vao_livre_m": [0.46, f"afvdatabase: 18 pol no centro, 11 pol nos lados ({AF})"],
    "cupula": [
        None,
        f"afvdatabase: G-1 com .30 M1919A4 na frente, entre o motorista (esq.) e o "
        f"comandante (dir.); escotilhas: 1 grande e 2 menores sobre a tropa, 2 do motor; "
        f"A1: caixa grande no teto de trás ({AF})",
    ],
    "rampa": [None, "PLACEHOLDER: dimensões da rampa de proa sem fonte"],
    "roda_diametro_m": [0.42, "PLACEHOLDER (sem fonte)"],
    "cor_e_marcas": [
        None,
        "PLACEHOLDER: olive drab; 'USMC' + registro e número tático 'A12' sem "
        "fonte (Starlite: pelotão do 1st Amphibian Tractor Bn, The First Fight, "
        "USMC History Division, p.34)",
    ],
}

XF, XR = 9.04 / 2, -9.04 / 2
Y_TR, W_TR, T_TR, G_TR = 2.964 / 2, 0.527, 0.045, 0.035
R_RW, Z_RW = 0.21, 0.21 + 0.045
X_RW = [2.55 - 0.70 * k for k in range(9)]  # da frente para trás
X_SP, Z_SP, R_SP = XR + 0.55, 0.95, 0.344
X_ID, Z_ID, R_ID = 3.85, 1.25, 0.32
Z_SPON, Z_ROOF = 1.68, 2.62
Y_HULL, Y_LOW = 3.569 / 2, Y_TR - W_TR / 2 - 0.02
CUP = Vector((3.0, 0.0, Z_ROOF))


def x_proa(z):
    """x da frente do casco na altura z: proa de baixo (scow) até a dobradiça, depois a rampa."""
    if z <= 1.2:
        t = (z - 0.46) / (1.2 - 0.46)
        return 3.05 + (4.45 - 3.05) * t
    t = (z - 1.2) / (Z_ROOF - 1.2)
    return 4.45 + (3.42 - 4.45) * t


def receita():
    mt = B.Montagem()
    od = mt.mat(
        "pintura", B.mat_pintura, fundido=0.0, z_lama=1.4, desgaste=0.55, oleo=(-3.4, 0.0, 0.6)
    )
    od_t = mt.mat(
        "pintura_cupula", B.mat_pintura, fundido=0.0, z_lama=0.0, lama_forca=0.0, poeira_forca=0.8
    )
    aco = mt.mat("aco", B.mat_aco_sujo, z_lama=1.4, brilho_contato=True)
    aco_esc = mt.mat("aco_escuro", B.mat_simples, "#1e1d1a", 0.5, 0.6)
    borr = mt.mat("borracha", B.mat_borracha, z_lama=0.6)
    vidro = mt.mat("vidro", B.mat_vidro)
    amarelo = mt.mat("estencil", B.mat_estencil, "#d4bd55", "#56583a", 0.5)
    lente_v = mt.mat("lente_vermelha", B.mat_simples, "#5c1712", 0.25, 0.0)

    # ================================================================ CASCO
    P = "Casco"
    # casco de baixo (entre as lagartas)
    aneis = []
    for z in (0.46, 0.8, 1.2, Z_SPON + 0.01):
        aneis.append(B.planta(z, XR + 0.12, x_proa(z) - 0.02, Y_LOW, 0.2, 6, 4.0))
    mt.geo(P, B.loft("casco_baixo", aneis), od)
    # casco de cima (largura toda, sobre as lagartas), proa com a rampa inclinada
    aneis = []
    for z in (Z_SPON, 2.0, 2.35, Z_ROOF):
        aneis.append(
            B.planta(z, XR + 0.04, x_proa(z) - 0.05, Y_HULL - 0.004 * (z - Z_SPON), 0.25, 6, 3.5)
        )
    mt.geo(P, B.loft("casco_cima", aneis), od)
    # caixa de admissão do A1 no teto de trás e grades do motor
    mt.geo(P, B.caixa("caixa_a1", (1.0, 1.9, 0.34), (XR + 0.75, 0, Z_ROOF + 0.17), 0.04), od)
    g = B.Lote("grade_a1")
    for k in range(10):
        g.caixa((0.04, 1.7, 0.012), Matrix.Translation((XR + 0.33 + k * 0.085, 0, Z_ROOF + 0.345)))
    mt.det(P, g.objeto(), aco_esc)
    for s in (1, -1):
        g = B.Lote("grade_lado")
        for k in range(6):
            g.caixa(
                (0.6, 0.012, 0.03),
                Matrix.Translation((XR + 0.75, s * 0.952, Z_ROOF + 0.05 + k * 0.045)),
            )
        mt.det(P, g.objeto(), aco_esc)
    for xc in (-2.6, -3.3):
        mt.geo(P, B.caixa("escot_motor", (0.55, 0.55, 0.04), (xc, 0.6, Z_ROOF + 0.02), 0.01), od)
    # aros das escotilhas da tropa
    mt.geo(P, B.caixa("aro_tropa", (1.7, 1.3, 0.05), (0.2, 0, Z_ROOF + 0.02), 0.012), od)
    for s in (1, -1):
        mt.geo(P, B.caixa("aro_peq", (0.8, 0.8, 0.05), (-1.45, s * 0.8, Z_ROOF + 0.02), 0.012), od)
    # cúpulas pequenas do motorista e do comandante (aro com blocos de visão)
    for s in (1, -1):
        c = Vector((3.05, s * 0.95, Z_ROOF))
        mt.geo(
            P,
            M.torno(
                "cup_mot",
                [
                    (0.0, Z_ROOF - 0.02),
                    (0.36, Z_ROOF - 0.02),
                    (0.36, Z_ROOF + 0.12),
                    (0.31, Z_ROOF + 0.17),
                    (0.0, Z_ROOF + 0.17),
                ],
                16,
            ),
            od,
        )
        M.mover(mt.partes[P]["geo"][-1], Matrix.Translation((c.x, c.y, 0)))
        for k in range(5):
            a = math.radians(-60 + 30 * k)
            p = Vector((c.x + 0.355 * math.cos(a), c.y + 0.355 * math.sin(a), Z_ROOF + 0.07))
            bl = B.Lote("bloco")
            bl.caixa(
                (0.02, 0.1, 0.05),
                B.quadro(
                    p, (math.cos(a), math.sin(a), 0), (-math.sin(a), math.cos(a), 0), (0, 0, 1)
                ),
            )
            mt.det(P, bl.objeto(), vidro)
    # base da cúpula G-1
    mt.geo(P, B.cil("aro_g1", (CUP.x, 0, Z_ROOF - 0.02), (CUP.x, 0, Z_ROOF + 0.06), 0.5, 16), od)
    # laterais: friso, olhais, luzes, cabo de reboque
    for s, lado in ((1, "+Y"), (-1, "-Y")):
        mt.geo(
            P,
            B.caixa("friso", (8.4, 0.05, 0.06), (-0.1, s * (Y_HULL + 0.02), Z_SPON + 0.06), 0.01),
            od,
        )
        for xe in (-3.6, 2.7):
            g = M.toro("olhal", 0.07, 0.02, 12, 6)
            M.mover(
                g,
                Matrix.Translation((xe, s * (Y_HULL - 0.12), Z_ROOF + 0.07))
                @ Matrix.Rotation(math.pi / 2, 4, "X"),
            )
            mt.geo(P, g, aco)
        mt.geo(
            P, B.caixa("farol", (0.12, 0.16, 0.12), (x_proa(2.3) - 0.04, s * 1.5, 2.3), 0.012), od
        )
        mt.det(
            P,
            B.cil(
                "lente",
                (x_proa(2.3) + 0.02, s * 1.5, 2.3),
                (x_proa(2.3) + 0.025, s * 1.5, 2.3),
                0.045,
                10,
            ),
            vidro,
        )
        mt.geo(P, B.caixa("lanterna", (0.06, 0.14, 0.12), (XR + 0.01, s * 1.55, 2.2), 0.01), od)
        mt.det(P, B.caixa("lente_t", (0.01, 0.06, 0.05), (XR - 0.022, s * 1.55, 2.22)), lente_v)
        cabo = [
            (xx, s * (Y_HULL + 0.035), 2.3 - 0.05 * math.sin(math.pi * (xx + 3.2) / 2.4) ** 2)
            for xx in (-3.2, -2.6, -2.0, -1.4, -0.8)
        ]
        mt.geo(P, M.tubo("cabo", cabo, 0.016, 6, True), aco)
        for xx in (-3.2, -0.8):
            mt.geo(
                P,
                B.caixa("presilha", (0.06, 0.05, 0.08), (xx, s * (Y_HULL + 0.02), 2.3), 0.008),
                od,
            )

        # roletes de retorno e braços
        def z_topo(x):
            return (Z_SP + R_SP) + (x - X_SP) / (X_ID - X_SP) * ((Z_ID + R_ID) - (Z_SP + R_SP))

        for xr in (-3.0, -1.6, -0.2, 1.2, 2.6):
            zr = z_topo(xr) - 0.085
            mt.geo(
                P,
                B.torno_eixo(
                    "rolete",
                    [(0.0, -0.2), (0.09, -0.2), (0.09, 0.2), (0.0, 0.2)],
                    "Y",
                    (xr, s * Y_TR, zr),
                    10,
                ),
                aco,
            )
            mt.geo(
                P,
                B.cil("eixo_r", (xr, s * (Y_LOW - 0.02), zr), (xr, s * (Y_TR - 0.2), zr), 0.04, 8),
                od,
            )
        for xw in X_RW:
            mt.geo(
                P,
                B.caixa(
                    "braco",
                    (0.3, 0.07, 0.08),
                    (xw - 0.13, s * (Y_LOW + 0.04), Z_RW + 0.06),
                    0.008,
                    (0, math.radians(20), 0),
                ),
                aco,
            )
        mt.geo(
            P,
            B.cil(
                "cubo_motriz",
                (X_SP, s * (Y_LOW - 0.02), Z_SP),
                (X_SP, s * (Y_TR - 0.2), Z_SP),
                0.15,
                12,
            ),
            od,
        )
        mt.geo(
            P,
            B.cil(
                "cubo_guia",
                (X_ID, s * (Y_LOW - 0.02), Z_ID),
                (X_ID, s * (Y_TR - 0.2), Z_ID),
                0.08,
                10,
            ),
            od,
        )
        # marcações (PLACEHOLDER)
        mt.det(
            P, B.letreiro("A12", 0.32, amarelo, (1.5, s * (Y_HULL + 0.002), 2.15), lado), amarelo
        )
        mt.det(
            P,
            B.letreiro("USMC 230418", 0.08, amarelo, (-2.2, s * (Y_HULL + 0.002), 2.42), lado),
            amarelo,
        )
        # parafusos do friso
        pf = B.Lote("parafusos")
        for k in range(30):
            pf.cil(
                0.011,
                0.012,
                Matrix.Translation((-4.2 + k * 0.28, s * (Y_HULL + 0.046), Z_SPON + 0.06))
                @ Matrix.Rotation(math.pi / 2, 4, "X"),
                6,
            )
        mt.det(P, pf.objeto(), od)
        # solda das quinas
        mt.det(
            P,
            M.tubo(
                "solda",
                [
                    (XR + 0.05, s * (Y_HULL - 0.002), Z_ROOF - 0.002),
                    (3.4, s * (Y_HULL - 0.002), Z_ROOF - 0.002),
                ],
                0.008,
                6,
            ),
            od,
        )
    # ganchos de reboque e dobradiças da rampa
    for s in (1, -1):
        g = M.toro("gancho", 0.07, 0.022, 12, 6)
        M.mover(
            g,
            Matrix.Translation((x_proa(0.85) + 0.02, s * 0.8, 0.85))
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        mt.geo(P, g, aco)
        g = M.toro("gancho_t", 0.07, 0.022, 12, 6)
        M.mover(
            g, Matrix.Translation((XR + 0.08, s * 0.8, 0.9)) @ Matrix.Rotation(math.pi / 2, 4, "X")
        )
        mt.geo(P, g, aco)
        mt.geo(P, B.cil("dobradica", (4.43, s * 0.7, 1.2), (4.43, s * 1.05, 1.2), 0.05, 10), aco)
    mt.geo(P, B.caixa("porta_tras", (0.04, 1.1, 0.9), (XR + 0.02, 0, 1.5), 0.012), od)
    mt.atlas(P, "casco")

    # ================================================================ RAMPA (proa)
    P = "Escotilha_Rampa"
    p0 = Vector((x_proa(1.22), 0, 1.22))
    p1 = Vector((x_proa(2.5), 0, 2.5))
    d = p1 - p0
    ang = math.atan2(d.x, d.z)
    meio = (p0 + p1) / 2
    n = Vector((d.z, 0, -d.x)).normalized()
    mt.geo(P, B.caixa("rampa", (0.08, 2.3, d.length), meio + n * 0.03, 0.015, (0, ang, 0)), od)
    rb = B.Lote("reforcos")
    for dy in (-0.8, -0.27, 0.27, 0.8):
        rb.caixa(
            (0.04, 0.08, d.length - 0.1),
            B.quadro(
                meio + n * 0.09 + Vector((0, dy, 0)),
                (math.cos(ang), 0, -math.sin(ang)),
                (0, 1, 0),
                (math.sin(ang), 0, math.cos(ang)),
            ),
        )
    mt.geo(P, rb.objeto(), od)
    mt.pivo(P, tuple(p0 + n * 0.03))
    mt.atlas(P, "casco")

    # ================================================================ ESCOTILHAS DO TETO
    for nome, c, dim, piv in (
        ("Escotilha_Tropa", (0.2, 0, Z_ROOF + 0.06), (1.6, 1.2, 0.045), (0.2, 0.6, Z_ROOF + 0.07)),
        (
            "Escotilha_TropaE",
            (-1.45, 0.8, Z_ROOF + 0.06),
            (0.72, 0.72, 0.04),
            (-1.45, 1.16, Z_ROOF + 0.07),
        ),
        (
            "Escotilha_TropaD",
            (-1.45, -0.8, Z_ROOF + 0.06),
            (0.72, 0.72, 0.04),
            (-1.45, -1.16, Z_ROOF + 0.07),
        ),
    ):
        mt.geo(nome, B.caixa("tampa", dim, c, 0.012), od)
        mt.geo(nome, B.caixa("alca", (0.18, 0.03, 0.03), (c[0], c[1], c[2] + 0.04), 0.006), aco)
        mt.pivo(nome, piv)
        mt.atlas(nome, "casco")
    for nome, s in (("Escotilha_Motorista", 1), ("Escotilha_Comandante", -1)):
        mt.geo(
            nome,
            B.cil(
                "tampa_c", (3.05, s * 0.95, Z_ROOF + 0.17), (3.05, s * 0.95, Z_ROOF + 0.22), 0.3, 14
            ),
            od,
        )
        mt.pivo(nome, (2.76, s * 0.95, Z_ROOF + 0.2))
        mt.atlas(nome, "casco")

    # ================================================================ TORRE (cúpula G-1 com a .30)
    P = "Torre"
    perfil = [(0.0, 0.0), (0.46, 0.0), (0.46, 0.06), (0.43, 0.3), (0.36, 0.42), (0.0, 0.44)]
    cup = M.torno("g1", [(r, CUP.z + 0.04 + h) for r, h in perfil], 16)
    M.mover(cup, Matrix.Translation((CUP.x, 0, 0)))
    mt.geo(P, cup, od_t)
    mt.geo(P, B.caixa("fenda", (0.2, 0.28, 0.14), (CUP.x + 0.36, 0, CUP.z + 0.24), 0.02), od_t)
    mt.geo(
        P,
        B.cil(
            "cano_30", (CUP.x + 0.45, 0, CUP.z + 0.24), (CUP.x + 1.05, 0, CUP.z + 0.24), 0.022, 8
        ),
        aco_esc,
    )
    mt.geo(
        P,
        B.cil("luva_30", (CUP.x + 0.45, 0, CUP.z + 0.24), (CUP.x + 0.7, 0, CUP.z + 0.24), 0.032, 8),
        aco_esc,
    )
    for k in range(6):
        a = math.radians(60 + 48 * k)
        p = Vector((CUP.x + 0.445 * math.cos(a), 0.445 * math.sin(a), CUP.z + 0.25))
        bl = B.Lote("bloco_g1")
        bl.caixa(
            (0.02, 0.12, 0.05),
            B.quadro(p, (math.cos(a), math.sin(a), 0), (-math.sin(a), math.cos(a), 0), (0, 0, 1)),
        )
        mt.det(P, bl.objeto(), vidro)
    mt.geo(
        P,
        B.cil(
            "tampa_g1", (CUP.x - 0.05, 0, CUP.z + 0.44), (CUP.x - 0.05, 0, CUP.z + 0.48), 0.26, 14
        ),
        od_t,
    )
    mt.pivo(P, tuple(CUP))
    mt.atlas(P, "casco")

    # ================================================================ RODAGEM
    circ = [(X_ID, Z_ID, R_ID)] + [(x, Z_RW, R_RW) for x in X_RW] + [(X_SP, Z_SP, R_SP)]
    pts, tang, nrm, comp = B.laco(circ, 268, sag=0.0)
    P = "Esteira_E"
    a = [(0.0, -W_TR / 2), (0.0, W_TR / 2), (T_TR, W_TR / 2), (T_TR, -W_TR / 2)]
    b = [
        (0.0, -W_TR / 2),
        (0.0, W_TR / 2),
        (T_TR + G_TR, W_TR / 2 - 0.03),
        (T_TR + G_TR, -W_TR / 2 + 0.03),
    ]
    mt.geo(P, B.faixa_alternada("esteira", pts, nrm, [a, b], Y_TR), aco)
    guias = B.Lote("guias")
    for i in range(0, len(pts), 2):
        (x, z), (tx, tz), (nx, nz) = pts[i], tang[i], nrm[i]
        ex, ey, ez = Vector((tx, 0, tz)), Vector((0, 1, 0)), Vector((nx, 0, nz))
        guias.caixa((0.05, 0.05, 0.02), B.quadro(Vector((x, Y_TR, z)) - ez * 0.009, ex, ey, ez))
    mt.det(P, guias.objeto(), aco)
    mt.atlas(P, "rodagem")
    mt.sem_limpeza(P)
    mt.espelho("Esteira_D", P)

    def roda(nome, x, z, r, larg=0.2):
        perfil = [
            (0.0, larg + 0.025),
            (0.05, larg + 0.025),
            (r - 0.05, larg),
            (r, larg),
            (r, 0.03),
            (r - 0.07, 0.03),
            (r - 0.07, -0.03),
            (r, -0.03),
            (r, -larg),
            (0.0, -larg),
        ]
        o = B.torno_eixo(nome, perfil, "Y", (x, Y_TR, z), 12)
        M.material(o, od)
        # par duplo: o de fora com pneu maciço de borracha, o de dentro com aro de aço
        B.pintar_por(o, lambda c, n: math.hypot(c.x - x, c.z - z) > r - 0.035 and c.y > Y_TR, borr)
        return o

    P = "Roda_E1"
    mt.geo(P, roda("roda", X_RW[0], Z_RW, R_RW), None)
    mt.pivo(P, (X_RW[0], Y_TR, Z_RW))
    mt.atlas(P, "rodagem")
    for i, x in enumerate(X_RW):
        if i > 0:
            mt.instancia(f"Roda_E{i + 1}", "Roda_E1", (x, Y_TR, Z_RW))
        mt.instancia(f"Roda_D{i + 1}", "Roda_E1", (x, -Y_TR, Z_RW), giro_z180=True)
    P = "Roda_EG"
    mt.geo(P, roda("guia", X_ID, Z_ID, R_ID, 0.2), None)
    mt.pivo(P, (X_ID, Y_TR, Z_ID))
    mt.atlas(P, "rodagem")
    mt.instancia("Roda_DG", "Roda_EG", (X_ID, -Y_TR, Z_ID), giro_z180=True)
    P = "Roda_EM"
    for y0, y1 in ((Y_TR + 0.13, Y_TR + 0.18), (Y_TR - 0.18, Y_TR - 0.13)):
        mt.geo(P, B.engrenagem("coroa", 0.315, 0.385, 17, y0, y1, (X_SP, Z_SP)), aco)
    mt.geo(
        P,
        B.torno_eixo(
            "cubo_m",
            [(0.0, 0.26), (0.1, 0.26), (0.13, 0.23), (0.27, 0.2), (0.27, -0.14), (0.0, -0.14)],
            "Y",
            (X_SP, Y_TR, Z_SP),
            14,
        ),
        od,
    )
    mt.pivo(P, (X_SP, Y_TR, Z_SP))
    mt.atlas(P, "rodagem")
    mt.instancia("Roda_DM", "Roda_EM", (X_SP, -Y_TR, Z_SP), giro_z180=True)
    mt.ext["rodagem"] = 0.03

    info = {
        "nome": "LVTP-5A1 (USMC, 1965)",
        "faccao": "US",
        "medidas": MEDIDAS,
        "olhos": {
            "driver": (3.0, 0.95, Z_ROOF + 0.55),
            "gunner": (CUP.x - 0.1, 0.0, CUP.z + 0.72),
            "commander": (3.0, -0.95, Z_ROOF + 0.55),
        },
        "passageiros": {"x0": 1.4, "dx": 0.62, "y": 1.0, "z": Z_ROOF + 0.85},
        "escotilhas": {
            "Escotilha_Motorista": [0.6, 0.6],
            "Escotilha_Comandante": [0.6, 0.6],
            "Escotilha_Tropa": [1.6, 1.2],
            "Escotilha_TropaE": [0.72, 0.72],
            "Escotilha_TropaD": [0.72, 0.72],
            "Escotilha_Rampa": [2.3, 1.6],
        },
        "lagarta": {
            "circulos": [
                (X_ID, Z_ID, R_ID + T_TR),
                (X_RW[0], Z_RW, R_RW + T_TR),
                (X_RW[-1], Z_RW, R_RW + T_TR),
                (X_SP, Z_SP, R_SP + T_TR),
            ],
            "y_centro": Y_TR,
            "largura": W_TR,
            "comprimento_laco": comp,
        },
        "escapes": [(XR + 0.75, 0.96, Z_ROOF + 0.15), (XR + 0.75, -0.96, Z_ROOF + 0.15)],
        "notas": [
            "Passageiros sentados no teto (como no Vietnã, por causa das minas): 6 fileiras de 2, "
            "de x0 para trás, a 1 m do eixo, olho a 0,85 m sobre o teto.",
            "Escapamento: grades laterais da caixa do A1 no teto de trás (PLACEHOLDER de posição).",
        ],
    }
    return mt, info
