"""M48A3 Patton dos fuzileiros (3rd Tank Battalion, Vietnã 1965), em partes para o jogo.

Medidas (metros; nariz em +X, esquerda em +Y, chão em Z = 0) com a fonte em `MEDIDAS`. Partes:
Casco (com os roletes de retorno e os braços), Torre (com a cúpula M1 e a .50), Cano (mantelete,
capa de lona, tubo de 90 mm e holofote), Escotilha_Motorista, Escotilha_Comandante,
Escotilha_Municiador, Esteira_E/D, Roda_E1..E6 / Roda_D1..D6 (rodas de apoio duplas), Roda_EG/DG
(roda-guia) e Roda_EM/DM (roda motriz de 11 dentes).
"""

from __future__ import annotations

import math

import modelar as M
import novos as N
import veic_base as B
from mathutils import Matrix, Vector

AF = "https://afvdatabase.com/usa/m48patton.html"
MEDIDAS = {
    "comprimento_casco_m": [6.871, f"afvdatabase M48A3: 270,5 pol ({AF})"],
    "projecao_do_canhao_m": [
        1.81,
        f"afvdatabase: o tubo passa 71,3 pol da frente ({AF}); "
        "a Wikipedia dá 9,3 m no total, que não bate com casco + projeção",
    ],
    "largura_m": [3.632, f"afvdatabase: 143,0 pol sobre os para-lamas ({AF})"],
    "altura_cupula_m": [3.284, f"afvdatabase: 129,3 pol até o periscópio da cúpula ({AF})"],
    "vao_livre_m": [0.419, f"afvdatabase: 16,5 pol ({AF})"],
    "lagarta_largura_m": [0.71, f"afvdatabase: T97E2, 28 pol, 79 sapatas, passo 6,94 pol ({AF})"],
    "bitola_m": [2.921, f"afvdatabase: 115,0 pol entre centros das lagartas ({AF})"],
    "contato_solo_m": [4.001, f"afvdatabase: 157,5 pol ({AF})"],
    "rodas_de_apoio": [6, f"afvdatabase: 6 duplas por lado ({AF})"],
    "roletes_de_retorno": [
        5,
        "afvdatabase dá 5 no M48A3; historyofwar e inetres dão 3 nos "
        "posteriores; o 'Mod A' de 1963 (refeito do M48A1) manteve 5 "
        "(fórum kitmaker). Escolhido 5: as fontes conflitam",
    ],
    "anel_da_torre_m": [2.16, f"afvdatabase: 85,0 pol ({AF})"],
    "roda_de_apoio_diametro_m": [
        0.66,
        "PLACEHOLDER: 26 pol, citado num TM (só no resultado de busca, sem confirmar o veículo)",
    ],
    "roda_motriz": [
        11,
        f"afvdatabase: 11 dentes, atrás ({AF}); diâmetro do passo calculado "
        "pelas 11 sapatas de 6,94 pol (0,62 m)",
    ],
    "roda_guia_diametro_m": [0.72, "PLACEHOLDER (sem fonte; medida da foto/modelo antigo)"],
    "altura_conves_m": [1.86, "PLACEHOLDER: deduzida da altura total e da torre"],
    "torre_altura_m": [0.86, "PLACEHOLDER: deduzida da altura até a cúpula"],
    "holofote": [
        None,
        "Crouse-Hinds de 18 pol (46 cm) sem IR: foto do 3rd Tank Bn em 1967 "
        "(mikesresearch.com/2020/11/29/patton-tanks-in-vietnam); numa foto da própria "
        "Starlite aparece o holofote redondo antigo (fórum kitmaker). O AN/VSS-1 em "
        "ago/1965 não foi confirmado",
    ],
    "cor": [
        None,
        "PLACEHOLDER: olive drab fosco (pedido); fórum kitmaker sugere 'forest green' "
        "em 1965, sem fonte primária",
    ],
    "marcacoes": [
        None,
        "'A34' na torre: pelotão 3 da Cia A, 3rd Tank Bn, que esteve na "
        "Starlite (Batailles & Blindés, via usmcvta.org/french-magazine-batailles-"
        "blindes: A33, A34, A35). 'USMC' + nº de registro amarelo, sem estrela: norma "
        "USMC de dez/1963 (garbee.net/~cabell/usmcmarkings.htm, escrita para "
        "caminhões). O número '108452' e a cor amarela são PLACEHOLDER",
    ],
}

# ---------------------------------------------------------------- layout (m)
XF, XR = 6.871 / 2, -6.871 / 2
Y_TR, W_TR, T_TR = 2.921 / 2, 0.71, 0.075
Z_BOT = 0.419
R_RW, Z_RW = 0.33, 0.33 + 0.075
X_SP, Z_SP, R_SP = XR + 0.42, 0.88, 0.31
X_RW = [X_SP + 0.63 + 0.80 * k for k in range(6)]  # de trás para a frente
X_ID, Z_ID, R_ID = X_RW[-1] + 0.84, 0.80, 0.36
X_RR = [-2.1, -1.1, -0.1, 0.9, 1.75]
Z_RR, R_RR = 1.10, 0.08
Z_FEND, Z_DECK = 1.40, 1.78
Y_HULL, Y_LOW = 1.45, 1.075
X_T, Z_ROOF = 0.25, 2.72
TRUN = Vector((X_T + 0.95, 0.0, 2.25))
X_MUZ = XF + 1.81
CUP = Vector((X_T - 0.50, -0.58, 2.66))
LOAD = Vector((X_T - 0.45, 0.56, 2.68))
DRV = Vector((1.60, 0.0, Z_DECK))


def glacis(t):
    """Ponto no meio do glacis superior (t de 0 embaixo a 1 em cima) e a normal."""
    p = Vector((XF - 0.25 - 1.35 * t, 0.0, 1.0 + 0.78 * t))
    n = Vector((0.5, 0.0, 0.866))
    return p, n


def anel_torre(z, s, n=40):
    """Contorno da torre fundida na altura z, escala s (1 = maior largura): ovo com o nariz
    largo e arredondado e o cesto (bustle) mais estreito atrás."""
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        c, sn = math.cos(t), math.sin(t)
        if c >= 0:
            a, ss = 1.22, s
        else:
            a, ss = 1.78, 1 - (1 - s) * 0.55
        b = 1.42 - (0.30 * (-c) if c < 0 else 0.0)
        e = 2.25
        x = X_T + ss * a * math.copysign(abs(c) ** (2 / e), c)
        y = s * b * math.copysign(abs(sn) ** (2 / e), sn)
        pts.append((x, y, z))
    return pts


NIVEIS_TORRE = [
    (1.795, 0.86),
    (1.87, 0.95),
    (2.02, 1.0),
    (2.25, 0.995),
    (2.43, 0.95),
    (2.57, 0.86),
    (2.67, 0.72),
    (2.72, 0.52),
]


def meia_largura_torre(x, z):
    """Meia largura da torre (y) na altura z e no x dado (interpolando os níveis)."""
    zs = [a for a, _ in NIVEIS_TORRE]
    ss = [b for _, b in NIVEIS_TORRE]
    s = float(__import__("numpy").interp(z, zs, ss))
    melhor = 0.0
    for px, py, _ in anel_torre(z, s, 160):
        if abs(px - x) < 0.04:
            melhor = max(melhor, abs(py))
    return melhor


def receita():
    mt = B.Montagem()
    od = mt.mat("pintura_casco", B.mat_pintura, fundido=1.0, z_lama=1.15, oleo=(-2.4, 0.3, 0.5))
    od_t = mt.mat(
        "pintura_torre", B.mat_pintura, fundido=1.3, z_lama=0.0, lama_forca=0.0, poeira_forca=0.8
    )
    chapa = mt.mat("pintura_chapa", B.mat_pintura, fundido=0.0, z_lama=1.2, desgaste=0.7)
    cano_m = mt.mat(
        "pintura_cano",
        B.mat_pintura,
        fundido=0.0,
        z_lama=0.0,
        lama_forca=0.0,
        poeira_forca=0.5,
        desgaste=0.35,
    )
    aco = mt.mat("aco", B.mat_aco_sujo, z_lama=1.3, brilho_contato=True)
    aco_esc = mt.mat("aco_escuro", B.mat_simples, "#1e1d1a", 0.5, 0.6)
    borr = mt.mat("borracha", B.mat_borracha, z_lama=0.75)
    lona = mt.mat("lona", B.mat_lona, z_lama=0.0)
    vidro = mt.mat("vidro", B.mat_vidro)
    amarelo = mt.mat("estencil", B.mat_estencil, "#d4bd55", "#56583a", 0.5)
    madeira = mt.mat("madeira", N.mat_madeira, "#8a7458", "#5a4532", "#7d766a", eixo="X")
    juta = mt.mat("juta", N.mat_juta, "#8c7a56", "#5e4f37", "#5a4a33", z_sujo=2.0)
    lente_v = mt.mat("lente_vermelha", B.mat_simples, "#5c1712", 0.25, 0.0)

    # ================================================================ CASCO
    P = "Casco"
    # casco de baixo (entre as lagartas): anéis em planta, frente inclinada (glacis inferior)
    aneis = []
    for z, xf in (
        (Z_BOT, XF - 0.95),
        (0.7, XF - 0.55),
        (0.88, XF - 0.33),
        (1.0, XF - 0.25),
        (1.2, XF - 0.6),
        (Z_FEND + 0.01, XF - 0.94),
    ):
        aneis.append(
            B.planta(z, XR + 0.16 - 0.1 * min(1.0, (z - Z_BOT) / 0.5), xf, Y_LOW, 0.55, 8, 2.6)
        )
    mt.geo(P, B.loft("casco_baixo", aneis), od)
    # casco de cima (sobre as lagartas): glacis de 60°, nariz arredondado de fundição
    aneis = []
    for t in (0.0, 0.3, 0.65, 0.88, 1.0):
        z = Z_FEND + (Z_DECK - Z_FEND) * t
        xf = XF - 0.94 - 0.66 * t
        meia = Y_HULL - 0.05 * t
        nariz = 0.75 - 0.2 * t
        aneis.append(B.planta(z, XR + 0.05, xf, meia, nariz, 12, 2.3))
    mt.geo(P, B.loft("casco_cima", aneis), od)
    # convés do motor: tampas com grade (moldura em relevo) e a grade como detalhe
    for xc in (-1.75, -2.75):
        for yc in (-0.62, 0.62):
            mt.geo(
                P, B.caixa("tampa_motor", (0.9, 1.05, 0.03), (xc, yc, Z_DECK + 0.012), 0.008), chapa
            )
            g = B.Lote("grade")
            for k in range(14):
                g.caixa(
                    (0.035, 0.9, 0.012),
                    Matrix.Translation((xc - 0.39 + k * 0.06, yc, Z_DECK + 0.03)),
                )
            mt.det(P, g.objeto(), aco_esc)
    # grade da traseira (portas de grade do M48A3, com o escapamento)
    mt.geo(P, B.caixa("moldura_tras", (0.05, 2.3, 0.55), (XR + 0.035, 0, 1.42), 0.01), chapa)
    g = B.Lote("grade_tras")
    for k in range(9):
        g.caixa((0.02, 2.1, 0.03), Matrix.Translation((XR + 0.005, 0, 1.2 + k * 0.055)))
    mt.det(P, g.objeto(), aco_esc)
    # para-lamas (chapa sobre a lagarta), com a ponta da frente caída
    for s in (1, -1):
        ym = s * (Y_HULL + 1.816) / 2
        lg = 1.816 - Y_HULL + 0.02
        mt.geo(
            P,
            B.caixa(
                "paralama",
                (XF - XR - 0.05, lg, 0.014),
                ((XF + XR) / 2 - 0.02, ym, Z_FEND + 0.007),
                0.004,
            ),
            chapa,
        )
        mt.geo(
            P,
            B.caixa(
                "paralama_borda",
                (XF - XR - 0.1, 0.012, 0.09),
                ((XF + XR) / 2, s * 1.81, Z_FEND - 0.035),
                0.003,
            ),
            chapa,
        )
        # faróis com guarda (Mod A/1963: guardas redondas)
        xl, yl = XF - 0.28, s * 1.6
        mt.geo(P, B.caixa("base_farol", (0.2, 0.26, 0.09), (xl, yl, Z_FEND + 0.06), 0.012), chapa)
        for dy in (-0.07, 0.07):
            mt.geo(
                P,
                B.cil(
                    "farol",
                    (xl - 0.02, yl + dy, Z_FEND + 0.16),
                    (xl + 0.07, yl + dy, Z_FEND + 0.16),
                    0.055,
                    12,
                ),
                chapa,
            )
            mt.geo(
                P,
                B.cil(
                    "lente",
                    (xl + 0.07, yl + dy, Z_FEND + 0.16),
                    (xl + 0.075, yl + dy, Z_FEND + 0.16),
                    0.045,
                    12,
                ),
                vidro,
            )
        arco = []
        for k in range(9):
            a = math.pi * k / 8
            arco.append((xl + 0.13, yl + 0.19 * math.cos(a), Z_FEND + 0.02 + 0.27 * math.sin(a)))
        mt.geo(P, M.tubo("guarda", arco, 0.012, 6), chapa)
        for dy in (-0.19, 0.19):
            mt.geo(
                P,
                M.tubo(
                    "guarda_l",
                    [(xl + 0.13, yl + dy, Z_FEND + 0.02), (xl - 0.08, yl + dy, Z_FEND + 0.015)],
                    0.011,
                    6,
                ),
                chapa,
            )
        # lanterna traseira
        mt.geo(
            P,
            B.caixa("lanterna", (0.08, 0.16, 0.12), (XR + 0.08, s * 1.6, Z_FEND + 0.075), 0.01),
            chapa,
        )
        mt.det(
            P,
            B.caixa("lente_t", (0.012, 0.06, 0.05), (XR + 0.036, s * 1.58, Z_FEND + 0.09)),
            lente_v,
        )
        # caixas de estiva nos para-lamas
        for xc in (-0.55, -1.25) if s < 0 else (-0.85, -1.55):
            mt.geo(
                P,
                B.caixa("caixa_estiva", (0.6, 0.3, 0.3), (xc, s * 1.64, Z_FEND + 0.165), 0.015),
                chapa,
            )
            mt.det(P, B.caixa("trinco", (0.05, 0.02, 0.05), (xc, s * 1.795, Z_FEND + 0.25)), aco)
        # roletes de retorno e braços (ficam no casco)
        for xr in X_RR:
            mt.geo(
                P,
                B.torno_eixo(
                    "rolete",
                    [(0.0, -0.24), (R_RR, -0.24), (R_RR, 0.24), (0.0, 0.24)],
                    "Y",
                    (xr, s * Y_TR, Z_RR),
                    10,
                ),
                aco,
            )
            mt.geo(
                P,
                B.cil(
                    "eixo_rolete",
                    (xr, s * (Y_LOW - 0.02), Z_RR),
                    (xr, s * (Y_TR - 0.24), Z_RR),
                    0.04,
                    8,
                ),
                od,
            )
        for xw in X_RW:
            mt.geo(
                P,
                B.caixa(
                    "braco",
                    (0.42, 0.09, 0.1),
                    (xw + 0.2, s * (Y_LOW + 0.05), Z_RW + 0.08),
                    0.01,
                    (0, math.radians(-18), 0),
                ),
                aco,
            )
        # cubo da roda-guia e da motriz no casco
        mt.geo(
            P,
            B.cil(
                "cubo_guia",
                (X_ID, s * (Y_LOW - 0.02), Z_ID),
                (X_ID, s * (Y_TR - 0.25), Z_ID),
                0.07,
                10,
            ),
            od,
        )
        mt.geo(
            P,
            B.cil(
                "cubo_motriz",
                (X_SP, s * (Y_LOW - 0.02), Z_SP),
                (X_SP, s * (Y_TR - 0.24), Z_SP),
                0.16,
                12,
            ),
            od,
        )
        # solda da junção casco/para-lama
        mt.det(
            P,
            M.tubo(
                "solda",
                [
                    (XR + 0.1, s * (Y_HULL - 0.003), Z_FEND + 0.016),
                    (XF - 0.4, s * (Y_HULL - 0.003), Z_FEND + 0.016),
                ],
                0.008,
                6,
            ),
            od,
        )
        # parafusos na borda do para-lama
        pf = B.Lote("parafusos")
        for k in range(26):
            x = XR + 0.2 + k * 0.25
            pf.cil(0.012, 0.012, Matrix.Translation((x, s * 1.79, Z_FEND + 0.018)), 6)
        mt.det(P, pf.objeto(), chapa)
    # ganchos de reboque da frente e da traseira
    for s in (1, -1):
        g = M.toro("gancho", 0.075, 0.022, 14, 6)
        M.mover(
            g,
            Matrix.Translation((XF - 0.36, s * 0.72, 0.85)) @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        mt.geo(P, g, aco)
        mt.geo(P, B.caixa("orelha", (0.12, 0.05, 0.14), (XF - 0.44, s * 0.72, 0.85), 0.01), od)
        g = M.toro("gancho_t", 0.07, 0.02, 14, 6)
        M.mover(
            g,
            Matrix.Translation((XR + 0.06, s * 0.72, 0.85)) @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        mt.geo(P, g, aco)
    mt.geo(P, B.cil("engate", (XR + 0.15, 0, 0.78), (XR - 0.05, 0, 0.78), 0.06, 10), aco)
    # carga nos para-lamas de trás: galões (direita) e lona enrolada (esquerda)
    for k in range(2):
        mt.geo(
            P,
            B.caixa(
                "galao", (0.35, 0.16, 0.47), (XR + 0.45 + k * 0.4, -1.62, Z_FEND + 0.25), 0.025
            ),
            chapa,
        )
    rolo = B.cil(
        "lona_f", (XR + 0.3, 1.63, Z_FEND + 0.13), (XR + 1.5, 1.63, Z_FEND + 0.13), 0.12, 12
    )
    M.deslocar(rolo, lambda co, n: 0.012 * M.fbm(co * 7, 3, 34))
    mt.geo(P, rolo, lona)
    # caixa do telefone de infantaria (traseira direita)
    mt.geo(
        P, B.caixa("telefone", (0.18, 0.24, 0.28), (XR + 0.1, -1.5, Z_FEND + 0.15), 0.012), chapa
    )
    # sapatas de reserva no glacis (comum no Vietnã)
    for t in (0.32, 0.5, 0.68):
        p, n = glacis(t)
        ang = math.atan2(n.x, n.z)
        mt.geo(
            P,
            B.caixa("sapata_reserva", (0.17, 0.66, 0.045), p + n * 0.024, 0.006, (0, ang, 0)),
            aco,
        )
    # escotilha do motorista: periscópios na frente dela
    for dy in (-0.2, 0.0, 0.2):
        mt.geo(
            P,
            B.caixa("periscopio", (0.08, 0.14, 0.07), (DRV.x + 0.2, dy, Z_DECK + 0.03), 0.008),
            od,
        )
        mt.det(
            P, B.caixa("vidro_p", (0.01, 0.11, 0.035), (DRV.x + 0.242, dy, Z_DECK + 0.04)), vidro
        )
    mt.geo(P, B.cil("aro_mot", (DRV.x, 0, Z_DECK - 0.02), (DRV.x, 0, Z_DECK + 0.03), 0.32, 16), od)
    # trava de viagem do canhão no convés traseiro
    mt.geo(P, B.caixa("trava_base", (0.12, 0.3, 0.06), (-2.95, 0, Z_DECK + 0.03), 0.01), chapa)
    mt.geo(
        P,
        B.caixa(
            "trava_braco",
            (0.06, 0.06, 0.5),
            (-2.9, 0, Z_DECK + 0.08),
            0.01,
            (0, math.radians(-70), 0),
        ),
        chapa,
    )
    # ferramentas no para-lama da esquerda: picareta e pá (cabos de madeira)
    mt.geo(
        P,
        B.cil("cabo_pa", (0.2, 1.62, Z_FEND + 0.04), (1.3, 1.62, Z_FEND + 0.04), 0.02, 6),
        madeira,
    )
    mt.geo(P, B.caixa("pa", (0.28, 0.2, 0.02), (1.42, 1.62, Z_FEND + 0.035), 0.004), chapa)
    mt.geo(
        P,
        B.cil("cabo_pic", (0.1, 1.73, Z_FEND + 0.04), (1.0, 1.73, Z_FEND + 0.04), 0.02, 6),
        madeira,
    )
    mt.geo(P, B.caixa("picareta", (0.06, 0.3, 0.04), (0.08, 1.64, Z_FEND + 0.05), 0.006), aco)
    # marcações: 'USMC' + registro nos lados da frente do casco (amarelo, sem estrela)
    for s, lado in ((1, "+Y"), (-1, "-Y")):
        mt.det(
            P,
            B.letreiro("USMC 108452", 0.075, amarelo, (0.9, s * (Y_HULL - 0.02), 1.6), lado),
            amarelo,
        )
    p, n = glacis(0.12)
    t = B.letreiro("USMC 108452", 0.07, amarelo, (0, 0, 0), "+Z")
    M.mover(
        t,
        Matrix.Translation(p + n * 0.003)
        @ Matrix.Rotation(math.atan2(n.x, n.z), 4, "Y")
        @ Matrix.Rotation(math.pi, 4, "Z"),
    )
    mt.det(P, t, amarelo)

    # ================================================================ ESCOTILHA DO MOTORISTA
    P = "Escotilha_Motorista"
    h = B.cil("tampa_mot", (DRV.x, 0, Z_DECK + 0.03), (DRV.x, 0, Z_DECK + 0.085), 0.29, 16)
    M.mover(
        h,
        Matrix.Translation(DRV) @ Matrix.Diagonal((1.0, 0.85, 1.0, 1.0)) @ Matrix.Translation(-DRV),
    )
    mt.geo(P, h, od)
    mt.geo(P, B.caixa("alca_mot", (0.16, 0.03, 0.03), (DRV.x - 0.05, 0, Z_DECK + 0.1), 0.006), aco)
    mt.pivo(P, (DRV.x, 0.27, Z_DECK + 0.06))
    mt.atlas(P, "casco")
    mt.atlas("Casco", "casco")

    # ================================================================ TORRE
    P = "Torre"
    aneis = [anel_torre(z, s) for z, s in NIVEIS_TORRE]
    mt.geo(P, B.loft("torre", aneis), od_t)
    # orelhas do telêmetro (estereoscópico) nos dois lados da frente
    for s in (1, -1):
        y = s * (meia_largura_torre(X_T + 0.45, 2.4) - 0.04)
        o = M.torno(
            "orelha", [(0.0, -0.08), (0.12, -0.08), (0.15, 0.0), (0.12, 0.06), (0.0, 0.08)], 12
        )
        M.mover(
            o, Matrix.Translation((X_T + 0.45, y, 2.42)) @ Matrix.Rotation(-s * math.pi / 2, 4, "X")
        )
        mt.geo(P, o, od_t)
        mt.det(
            P,
            B.cil(
                "janela_tel",
                (X_T + 0.45, y + s * 0.075, 2.42),
                (X_T + 0.45, y + s * 0.083, 2.42),
                0.05,
                10,
            ),
            vidro,
        )
        # olhais de içamento
        for xe, ze in ((X_T + 0.75, 2.6), (X_T - 1.1, 2.62)):
            ye = s * (meia_largura_torre(xe, ze) - 0.12)
            g = M.toro("olhal", 0.055, 0.016, 12, 5)
            M.mover(
                g, Matrix.Translation((xe, ye, ze + 0.06)) @ Matrix.Rotation(math.pi / 2, 4, "X")
            )
            mt.geo(P, g, aco)
        # número tático da Cia A, 3º pelotão, carro 4 (Starlite)
        x_n = X_T - 0.55
        y_n = s * (meia_largura_torre(x_n, 2.32) + 0.004)
        mt.det(
            P, B.letreiro("A34", 0.2, amarelo, (x_n, y_n, 2.32), "+Y" if s > 0 else "-Y"), amarelo
        )
    # cúpula M1 do comandante (direita, atrás) com a .50 saindo pela frente
    perfil = [
        (0.0, 0.0),
        (0.46, 0.0),
        (0.47, 0.07),
        (0.45, 0.3),
        (0.41, 0.36),
        (0.36, 0.38),
        (0.0, 0.38),
    ]
    cup = M.torno("cupula", [(r, CUP.z + h) for r, h in perfil], 16)
    M.mover(cup, Matrix.Translation((CUP.x, CUP.y, 0)))
    mt.geo(P, cup, od_t)
    for k in range(5):
        a = math.radians(-60 + 30 * k) + math.pi
        a = math.radians(140 + 40 * k)
        c = Vector((CUP.x + 0.455 * math.cos(a), CUP.y + 0.455 * math.sin(a), CUP.z + 0.2))
        m = B.quadro(c, (math.cos(a), math.sin(a), 0), (-math.sin(a), math.cos(a), 0), (0, 0, 1))
        bl = B.Lote("bloco")
        bl.caixa((0.02, 0.13, 0.06), m)
        mt.det(P, bl.objeto(), vidro)
    # .50 M2: caixa da arma no lado da cúpula e o cano para a frente
    mt.geo(
        P,
        B.caixa("caixa_m2", (0.5, 0.2, 0.2), (CUP.x + 0.25, CUP.y + 0.3, CUP.z + 0.22), 0.02),
        od_t,
    )
    mt.geo(
        P,
        B.cil(
            "cano_m2",
            (CUP.x + 0.48, CUP.y + 0.3, CUP.z + 0.24),
            (CUP.x + 1.38, CUP.y + 0.3, CUP.z + 0.24),
            0.022,
            8,
        ),
        aco_esc,
    )
    mt.geo(
        P,
        B.cil(
            "luva_m2",
            (CUP.x + 0.48, CUP.y + 0.3, CUP.z + 0.24),
            (CUP.x + 0.9, CUP.y + 0.3, CUP.z + 0.24),
            0.034,
            8,
        ),
        aco_esc,
    )
    mt.geo(
        P,
        B.caixa("cunhete", (0.28, 0.12, 0.2), (CUP.x - 0.05, CUP.y + 0.42, CUP.z + 0.16), 0.01),
        chapa,
    )
    # aro da escotilha do municiador (esquerda) e ventilador
    mt.geo(
        P,
        B.cil(
            "aro_mun", (LOAD.x, LOAD.y, LOAD.z - 0.04), (LOAD.x, LOAD.y, LOAD.z + 0.04), 0.36, 16
        ),
        od_t,
    )
    mt.geo(
        P,
        M.torno(
            "vent",
            [
                (0.0, Z_ROOF - 0.03),
                (0.17, Z_ROOF - 0.03),
                (0.15, Z_ROOF + 0.06),
                (0.0, Z_ROOF + 0.09),
            ],
            12,
        ),
        od_t,
    )
    M.mover(mt.partes[P]["geo"][-1], Matrix.Translation((X_T - 1.15, 0.0, 0.0)))
    # mira do atirador (periscópio no teto, frente direita)
    mt.geo(P, B.caixa("mira", (0.22, 0.16, 0.14), (X_T + 0.62, -0.6, Z_ROOF - 0.02), 0.015), od_t)
    mt.det(P, B.caixa("mira_v", (0.01, 0.12, 0.06), (X_T + 0.735, -0.6, Z_ROOF + 0.0)), vidro)
    # cesto da torre (bustle rack) com bolsas, cunhetes e galão
    x0, x1 = X_T - 1.5, X_T - 2.12
    for s in (1, -1):
        mt.geo(
            P,
            M.tubo(
                "cesto_l",
                [
                    (x0 + 0.2, s * 1.12, 2.45),
                    (x1, s * 1.05, 2.45),
                    (x1, s * 1.05, 2.02),
                    (x0 + 0.2, s * 1.12, 2.02),
                ],
                0.016,
                6,
            ),
            chapa,
        )
    mt.geo(P, M.tubo("cesto_t", [(x1, -1.05, 2.45), (x1, 1.05, 2.45)], 0.016, 6), chapa)
    mt.geo(P, M.tubo("cesto_b", [(x1, -1.05, 2.02), (x1, 1.05, 2.02)], 0.016, 6), chapa)
    mt.geo(P, B.caixa("cesto_fundo", (0.62, 2.1, 0.02), ((x0 + x1) / 2, 0, 2.02), 0.0), chapa)
    tela = B.Lote("tela")
    for k in range(12):
        tela.caixa((0.008, 0.008, 0.42), Matrix.Translation((x1 - 0.005, -1.0 + k * 0.18, 2.235)))
    for k in range(3):
        tela.caixa((0.008, 2.08, 0.008), Matrix.Translation((x1 - 0.005, 0, 2.1 + k * 0.12)))
    mt.geo(P, tela.objeto(), chapa)
    for i, (yc, dim) in enumerate(((-0.55, (0.5, 0.75, 0.32)), (0.35, (0.5, 0.65, 0.3)))):
        sc = M.superelipsoide("bolsa", dim[0] / 2, dim[1] / 2, dim[2] / 2, 0.6, 0.45, 16, 8)
        M.deslocar(sc, lambda co, n, i=i: 0.015 * M.fbm(co * 6, 3, 30 + i))
        M.mover(sc, Matrix.Translation(((x0 + x1) / 2, yc, 2.03 + dim[2] / 2)))
        mt.geo(P, sc, lona)
    for k, yc in enumerate((0.85, 0.85)):
        mt.geo(
            P,
            B.caixa(
                "cunhete_b", (0.28, 0.16, 0.2), ((x0 + x1) / 2 - 0.1 + k * 0.3, yc, 2.13), 0.008
            ),
            chapa,
        )
    # mais carga no cesto: lona enrolada por cima, galão, mochilas
    rolo = B.cil(
        "lona_rolo", ((x0 + x1) / 2 - 0.05, -1.0, 2.5), ((x0 + x1) / 2 - 0.05, 1.0, 2.5), 0.13, 12
    )
    M.deslocar(rolo, lambda co, n: 0.012 * M.fbm(co * 7, 3, 33))
    mt.geo(P, rolo, lona)
    for yy in (-0.85, 0.85):
        mt.geo(P, M.toro("amarra", 0.14, 0.012, 12, 5), lona)
        M.mover(
            mt.partes[P]["geo"][-1],
            Matrix.Translation(((x0 + x1) / 2 - 0.05, yy, 2.5))
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
    mt.geo(P, B.caixa("galao", (0.16, 0.35, 0.47), (x1 + 0.12, -0.05, 2.27), 0.025), chapa)
    for i, yc in enumerate((-0.15, 0.6)):
        mo = M.superelipsoide("mochila", 0.14, 0.17, 0.2, 0.55, 0.4, 12, 6)
        M.deslocar(mo, lambda co, n, i=i: 0.01 * M.fbm(co * 9, 3, 40 + i))
        M.mover(mo, Matrix.Translation((x0 - 0.05, yc, 2.24)))
        mt.geo(P, mo, lona)
    # sacos de areia no teto da frente (proteção improvisada)
    sb = M.superelipsoide("saco", 0.24, 0.14, 0.06, 0.5, 0.3, 12, 6)
    M.gravar_local(sb, 7.0)
    M.mover(sb, Matrix.Translation((X_T - 1.25, 0.6, Z_ROOF - 0.01)) @ Matrix.Rotation(0.4, 4, "Z"))
    mt.geo(P, sb, juta)
    mt.pivo(P, (X_T, 0.0, Z_DECK))
    mt.atlas(P, "torre")

    # ================================================================ CANO
    P = "Cano"
    xm0 = X_T + 1.02
    mt.geo(
        P, B.caixa("mantelete", (0.42, 1.0, 0.62), (xm0 + 0.08, 0, TRUN.z), 0.09, segs=2), cano_m
    )
    capa = M.torno(
        "capa",
        [(0.30, 0.0), (0.33, 0.06), (0.26, 0.16), (0.18, 0.24), (0.115, 0.30), (0.10, 0.36)],
        14,
    )
    M.deslocar(capa, lambda co, n: 0.018 * M.fbm(co * 9, 3, 41))
    M.mover(
        capa, Matrix.Translation((xm0 + 0.29, 0, TRUN.z)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    )
    mt.geo(P, capa, lona)
    L = X_MUZ - (xm0 + 0.6)
    perfil = [
        (0.0, 0.0),
        (0.098, 0.0),
        (0.09, 0.15),
        (0.082, 0.9),
        (0.075, 1.55),
        (0.075, 1.72),
        (0.105, 1.8),
        (0.108, 2.18),
        (0.075, 2.27),
        (0.068, 2.9),
        (0.066, L - 0.34),
        (0.094, L - 0.32),
        (0.094, L),
        (0.042, L),
        (0.042, L - 0.12),
        (0.0, L - 0.12),
    ]
    tubo = M.torno("tubo", perfil, 14)
    M.mover(tubo, Matrix.Translation((xm0 + 0.6, 0, TRUN.z)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    mt.geo(P, tubo, cano_m)
    for s in (1, -1):
        mt.geo(
            P,
            B.caixa("defletor", (0.24, 0.13, 0.13), (X_MUZ - 0.17, s * 0.13, TRUN.z), 0.012),
            cano_m,
        )
        mt.det(
            P, B.caixa("furo_def", (0.12, 0.01, 0.07), (X_MUZ - 0.17, s * 0.196, TRUN.z)), aco_esc
        )
    # holofote Crouse-Hinds de 18 pol sobre o mantelete
    xh, zh = xm0 + 0.02, TRUN.z + 0.31 + 0.23
    mt.geo(P, B.caixa("suporte_h", (0.22, 0.2, 0.1), (xh, 0, TRUN.z + 0.33), 0.012), cano_m)
    hol = M.torno(
        "holofote",
        [(0.0, -0.18), (0.2, -0.18), (0.235, -0.1), (0.235, 0.16), (0.215, 0.18), (0.0, 0.18)],
        16,
    )
    M.mover(hol, Matrix.Translation((xh, 0, zh)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    mt.geo(P, hol, cano_m)
    mt.det(P, B.cil("lente_h", (xh + 0.18, 0, zh), (xh + 0.19, 0, zh), 0.2, 16), vidro)
    gr = B.Lote("grade_h")
    for k in range(5):
        gr.caixa((0.01, 0.4, 0.012), Matrix.Translation((xh + 0.195, 0, zh - 0.16 + k * 0.08)))
    mt.det(P, gr.objeto(), cano_m)
    mt.pivo(P, tuple(TRUN))
    mt.atlas(P, "torre")

    # ================================================================ ESCOTILHAS DA TORRE
    P = "Escotilha_Comandante"
    tampa = M.torno(
        "tampa_cup", [(0.0, 0.0), (0.37, 0.0), (0.36, 0.05), (0.28, 0.1), (0.0, 0.12)], 16
    )
    M.mover(tampa, Matrix.Translation((CUP.x, CUP.y, CUP.z + 0.38)))
    mt.geo(P, tampa, od_t)
    mt.geo(
        P,
        B.caixa("periscopio_c", (0.14, 0.16, 0.1), (CUP.x + 0.12, CUP.y, CUP.z + 0.53), 0.01),
        od_t,
    )
    mt.det(P, B.caixa("vidro_c", (0.01, 0.12, 0.05), (CUP.x + 0.193, CUP.y, CUP.z + 0.54)), vidro)
    mt.pivo(P, (CUP.x - 0.34, CUP.y, CUP.z + 0.4))
    mt.atlas(P, "torre")
    P = "Escotilha_Municiador"
    mt.geo(
        P,
        B.cil(
            "tampa_mun", (LOAD.x, LOAD.y, LOAD.z + 0.04), (LOAD.x, LOAD.y, LOAD.z + 0.09), 0.31, 16
        ),
        od_t,
    )
    mt.geo(P, B.caixa("alca_mun", (0.16, 0.03, 0.03), (LOAD.x, LOAD.y, LOAD.z + 0.11), 0.006), aco)
    mt.pivo(P, (LOAD.x - 0.3, LOAD.y, LOAD.z + 0.06))
    mt.atlas(P, "torre")

    # ================================================================ RODAGEM (lado esquerdo)
    # lagarta: laço por dentro em volta da roda-guia, rodas, motriz e roletes
    circ = [(X_ID, Z_ID, R_ID)] + [(x, Z_RW, R_RW) for x in X_RW] + [(X_SP, Z_SP, R_SP)]
    circ += [(x, Z_RR, R_RR) for x in X_RR]
    pts, tang, nrm, comp = B.laco(circ, 158, sag=0.012, z_sag=Z_RR)
    P = "Esteira_E"
    # 2 anéis por sapata: a junta (fina) e a almofada (grossa): a silhueta mostra as sapatas
    sec_j = [(0.0, -W_TR / 2), (0.0, W_TR / 2), (T_TR - 0.012, W_TR / 2), (T_TR - 0.012, -W_TR / 2)]
    sec_a = [
        (0.0, -W_TR / 2),
        (0.0, W_TR / 2),
        (T_TR + 0.01, W_TR / 2 - 0.02),
        (T_TR + 0.01, -W_TR / 2 + 0.02),
    ]
    mt.geo(P, B.faixa_alternada("esteira", pts, nrm, [sec_j, sec_a], Y_TR), aco)
    pts, tang, nrm = pts[1::2], tang[1::2], nrm[1::2]
    almof, conec, guia = B.Lote("almofadas"), B.Lote("conectores"), B.Lote("guias")
    for (x, z), (tx, tz), (nx, nz) in zip(pts, tang, nrm, strict=True):
        ex, ey, ez = Vector((tx, 0, tz)), Vector((0, 1, 0)), Vector((nx, 0, nz))
        o = Vector((x, Y_TR, z))
        for dy in (-0.19, 0.19):
            almof.caixa((0.12, 0.25, 0.02), B.quadro(o + ez * (T_TR + 0.008) + ey * dy, ex, ey, ez))
        for dy in (-0.335, 0.335):
            conec.caixa((0.07, 0.05, 0.03), B.quadro(o + ez * (T_TR * 0.5) + ey * dy, ex, ey, ez))
        guia.caixa((0.08, 0.07, 0.016), B.quadro(o - ez * 0.007, ex, ey, ez))
    mt.det(P, almof.objeto(), borr)
    mt.det(P, conec.objeto(), aco)
    mt.det(P, guia.objeto(), aco)
    mt.atlas(P, "rodagem")
    mt.sem_limpeza(P)
    mt.espelho("Esteira_D", P)

    # roda de apoio dupla (pneu de borracha maciça), base na 1ª da frente; as outras são instâncias
    def roda(nome, x, z, r, larg=0.255):
        perfil = [
            (0.0, larg + 0.045),
            (0.075, larg + 0.045),
            (r - 0.09, larg),
            (r, larg),
            (r, 0.05),
            (r - 0.13, 0.05),
            (r - 0.13, -0.05),
            (r, -0.05),
            (r, -larg),
            (0.0, -larg),
        ]
        o = B.torno_eixo(nome, perfil, "Y", (x, Y_TR, z), 14)
        M.material(o, od)
        B.pintar_por(o, lambda c, n: math.hypot(c.x - x, c.z - z) > r - 0.06, borr)
        return o

    P = "Roda_E1"
    o = roda("roda", X_RW[-1], Z_RW, R_RW)
    mt.geo(P, o, None)
    pf = B.Lote("porcas")
    for k in range(8):
        a = 2 * math.pi * k / 8
        pf.cil(
            0.012,
            0.02,
            Matrix.Translation(
                (X_RW[-1] + 0.05 * math.cos(a), Y_TR + 0.3, Z_RW + 0.05 * math.sin(a))
            )
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
            6,
        )
    mt.det(P, pf.objeto(), aco)
    mt.pivo(P, (X_RW[-1], Y_TR, Z_RW))
    mt.atlas(P, "rodagem")
    for i, x in enumerate(reversed(X_RW)):
        if i > 0:
            mt.instancia(f"Roda_E{i + 1}", "Roda_E1", (x, Y_TR, Z_RW))
        mt.instancia(f"Roda_D{i + 1}", "Roda_E1", (x, -Y_TR, Z_RW), giro_z180=True)
    # roda-guia (frente)
    P = "Roda_EG"
    mt.geo(P, roda("guia", X_ID, Z_ID, R_ID, 0.25), None)
    mt.pivo(P, (X_ID, Y_TR, Z_ID))
    mt.atlas(P, "rodagem")
    mt.instancia("Roda_DG", "Roda_EG", (X_ID, -Y_TR, Z_ID), giro_z180=True)
    # roda motriz de 11 dentes (atrás): duas coroas e o cubo
    P = "Roda_EM"
    for y0, y1 in ((Y_TR + 0.17, Y_TR + 0.23), (Y_TR - 0.23, Y_TR - 0.17)):
        mt.geo(P, B.engrenagem("coroa", 0.285, 0.36, 11, y0, y1, (X_SP, Z_SP)), aco)
    mt.geo(
        P,
        B.torno_eixo(
            "cubo_m",
            [(0.0, 0.33), (0.1, 0.33), (0.13, 0.29), (0.24, 0.26), (0.24, -0.17), (0.0, -0.17)],
            "Y",
            (X_SP, Y_TR, Z_SP),
            14,
        ),
        od,
    )
    mt.pivo(P, (X_SP, Y_TR, Z_SP))
    mt.atlas(P, "rodagem")
    mt.instancia("Roda_DM", "Roda_EM", (X_SP, -Y_TR, Z_SP), giro_z180=True)
    mt.ext["rodagem"] = 0.032

    info = {
        "nome": "M48A3 Patton (USMC, 1965)",
        "faccao": "US",
        "medidas": MEDIDAS,
        "olhos": {
            "driver": (DRV.x - 0.02, 0.33, Z_DECK + 0.4),
            "gunner": (X_T + 0.62, -0.6, Z_ROOF + 0.22),
            "commander": (CUP.x, CUP.y, CUP.z + 0.75),
            "loader": (LOAD.x, LOAD.y, LOAD.z + 0.5),
        },
        "lagarta": {
            "circulos": [
                (X_ID, Z_ID, R_ID + T_TR),
                (X_RW[-1], Z_RW, R_RW + T_TR),
                (X_RW[0], Z_RW, R_RW + T_TR),
                (X_SP, Z_SP, R_SP + T_TR),
            ],
            "y_centro": Y_TR,
            "largura": W_TR,
            "comprimento_laco": comp,
        },
        "escapes": [(XR - 0.01, 0.75, 1.45), (XR - 0.01, -0.75, 1.45)],
        "escotilhas": {
            "Escotilha_Motorista": [0.58, 0.49],
            "Escotilha_Comandante": [0.72, 0.72],
            "Escotilha_Municiador": [0.62, 0.62],
        },
        "notas": [
            "Cúpula M1 com a .50 por dentro e o cano saindo pela frente (configuração de "
            "fábrica); a .50 por cima da cúpula foi modificação de campo mais tarde (sem fonte "
            "para a Starlite).",
            "Olho do motorista: cabeça fora da escotilha, 0,33 m à esquerda do tubo (o canhão "
            "passa por cima da escotilha).",
        ],
    }
    return mt, info
