"""M50A1 Ontos (3rd Anti-Tank Battalion, USMC, 1965), em partes para o jogo.

Casco em pirâmide (chapas de 0,5 pol), torre pequena no meio-trás com 6 fuzis sem recuo M40A1C
(3 de cada lado, numa coluna: cima, meio e baixo), 4 fuzis de pontaria .50 M8C nos de cima e do
meio, .30 M1919A4 no teto da torre, motorista na frente à esquerda e porta dupla atrás. Lagarta
de banda T123 com 4 rodas duplas por lado (a de trás é a roda-guia) e a motriz na frente.
Partes: Casco, Torre, Cano (os 6 fuzis elevam juntos no reparo T149E5), Escotilha_Motorista,
Escotilha_Torre, Escotilha_TraseiraE/D, Esteira_E/D, Roda_E1..E4 / Roda_D1..D4, Roda_EM/DM.
"""

from __future__ import annotations

import math

import modelar as M
import veic_base as B
from mathutils import Matrix, Vector

AF = "https://afvdatabase.com/usa/m50ontos.html"
WK = "https://en.wikipedia.org/wiki/M50_Ontos"
MEDIDAS = {
    "comprimento_m": [3.83, f"afvdatabase: 150,8 pol (383 cm) ({AF}); Wikipedia: 3,83 m ({WK})"],
    "largura_m": [2.598, f"afvdatabase: 102,3 pol sobre os para-lamas ({AF})"],
    "altura_m": [2.13, f"afvdatabase: 83,9 pol (213 cm) ({AF})"],
    "altura_de_tiro_m": [1.98, f"afvdatabase: ~78 pol nos fuzis de cima ({AF})"],
    "vao_livre_m": [0.371, f"afvdatabase: 14,6 pol ({AF})"],
    "lagarta": [0.51, f"afvdatabase: T123 de banda, 20 pol, 75 travessas de 4 pol ({AF})"],
    "bitola_m": [1.85, f"afvdatabase: 73,0 pol ({AF})"],
    "contato_solo_m": [2.39, f"afvdatabase: 94,2 pol ({AF})"],
    "rodas": [
        4,
        f"afvdatabase: 4 duplas por lado, a de trás é a roda-guia; motriz na frente "
        f"de 15 dentes ({AF})",
    ],
    "anel_da_torre_m": [0.805, f"afvdatabase: 31,7 pol ({AF})"],
    "fuzis": [
        6,
        f"afvdatabase: 6 M40A1C, 3 por lado, numerados de baixo à esquerda (vistos de "
        f"trás); 4 M8C .50 nos de cima; .30 no meio do teto da torre ({AF})",
    ],
    "fuzil_comprimento_m": [3.404, "Wikipedia, M40 recoilless rifle: 3,404 m"],
    "chapas": [
        None,
        f"afvdatabase: frente de cima a 71°, de baixo a 45°, lados de cima a 42°, "
        f"traseira de cima a 27° ({AF})",
    ],
    "roda_diametro_m": [0.56, "PLACEHOLDER (sem fonte)"],
    "cor_e_marcas": [
        None,
        "PLACEHOLDER: olive drab; 'C33' (Cia C, 3º pelotão, carro 3) é de uma "
        "foto em Da Nang, 1965 (mikesresearch.com/2025/09/30/m56-scorpion-and-m50-"
        "ontos-in-combat), não da Starlite; lonas nas culatras: mesma foto",
    ],
}

XF, XR = 3.83 / 2, -3.83 / 2
Y_TR, W_TR, T_TR = 1.85 / 2, 0.51, 0.04
Z_BOT = 0.371
R_RW, Z_RW = 0.28, 0.28 + 0.04
X_RW = [XR + 0.36 + 0.735 * k for k in range(4)]  # de trás para a frente; a de trás é a guia
X_SP, Z_SP, R_SP = XF - 0.42, 0.62, 0.243
Z_SPON, Z_ROOF = 0.95, 1.50
X_T = -0.62
Z_TR = 1.92  # teto da torre
TRUN = Vector((X_T + 0.1, 0.0, 1.80))
RIFLES = [(0.66, 2.00), (0.66, 1.80), (0.74, 1.595)]  # (|y|, z) cima, meio, baixo
X_BREECH, X_MUZ = XR + 0.35, XR + 0.35 + 3.404
DRV = Vector((0.66, 0.42, 1.30))


def casco_cima_pontos(t):
    z = Z_SPON + (Z_ROOF - Z_SPON) * t
    meia = 1.299 - 0.50 * t
    xf = XF - 0.04 - 1.58 * t
    xr = XR + 0.06 + 0.30 * t
    return B.planta(z, xr, xf, meia, 0.10, 4, 6.0)


def receita():
    mt = B.Montagem()
    od = mt.mat("pintura", B.mat_pintura, fundido=0.0, z_lama=0.95, desgaste=0.6)
    od_t = mt.mat(
        "pintura_torre", B.mat_pintura, fundido=0.0, z_lama=0.0, lama_forca=0.0, poeira_forca=0.8
    )
    od_f = mt.mat(
        "pintura_fuzis",
        B.mat_pintura,
        fundido=0.0,
        z_lama=0.0,
        lama_forca=0.0,
        poeira_forca=0.5,
        desgaste=0.45,
    )
    aco = mt.mat("aco", B.mat_aco_sujo, z_lama=1.0, brilho_contato=True)
    aco_esc = mt.mat("aco_escuro", B.mat_simples, "#1e1d1a", 0.5, 0.6)
    borr = mt.mat("borracha", B.mat_borracha, z_lama=0.6)
    banda = mt.mat("banda", B.mat_borracha, "#1f1e1c", "#7d6448", 1.0)
    lona = mt.mat("lona", B.mat_lona, z_lama=0.0)
    vidro = mt.mat("vidro", B.mat_vidro)
    amarelo = mt.mat("estencil", B.mat_estencil, "#d4bd55", "#56583a", 0.5)
    lente_v = mt.mat("lente_vermelha", B.mat_simples, "#5c1712", 0.25, 0.0)

    # ================================================================ CASCO
    P = "Casco"
    # casco de baixo, entre as lagartas: frente de baixo a 45°, laterais retas
    aneis = []
    for z, xf in (
        (Z_BOT, XF - 0.62),
        (0.55, XF - 0.42),
        (0.78, XF - 0.17),
        (Z_SPON + 0.01, XF - 0.04),
    ):
        aneis.append(B.planta(z, XR + 0.08, xf, 0.62, 0.08, 4, 6.0))
    mt.geo(P, B.loft("casco_baixo", aneis), od)
    # casco de cima: pirâmide (laterais a 42°, frente a 71°, traseira a 27°)
    mt.geo(P, B.loft("casco_cima", [casco_cima_pontos(t) for t in (0.0, 0.5, 1.0)]), od)
    # para-lamas da frente e de trás (ponta sobre a lagarta) e para-barro
    for s in (1, -1):
        mt.geo(
            P,
            B.caixa(
                "pl_frente",
                (0.22, W_TR + 0.12, 0.012),
                (XF + 0.02, s * Y_TR, Z_SPON + 0.006),
                0.003,
            ),
            od,
        )
        mt.geo(
            P,
            B.caixa(
                "pl_tras", (0.12, W_TR + 0.12, 0.012), (XR - 0.02, s * Y_TR, Z_SPON + 0.006), 0.003
            ),
            od,
        )
        mt.geo(
            P,
            B.caixa(
                "barro", (0.012, W_TR + 0.06, 0.22), (XR - 0.075, s * Y_TR, Z_SPON - 0.11), 0.003
            ),
            borr,
        )
        # faróis com guarda na frente
        xl, yl = XF - 0.05, s * 1.0
        mt.geo(P, B.caixa("base_farol", (0.12, 0.2, 0.08), (xl, yl, Z_SPON + 0.05), 0.01), od)
        for dy in (-0.05, 0.05):
            mt.geo(
                P,
                B.cil(
                    "farol",
                    (xl - 0.02, yl + dy, Z_SPON + 0.13),
                    (xl + 0.05, yl + dy, Z_SPON + 0.13),
                    0.04,
                    10,
                ),
                od,
            )
            mt.det(
                P,
                B.cil(
                    "lente",
                    (xl + 0.05, yl + dy, Z_SPON + 0.13),
                    (xl + 0.054, yl + dy, Z_SPON + 0.13),
                    0.032,
                    10,
                ),
                vidro,
            )
        arco = [
            (
                xl + 0.08,
                yl + 0.14 * math.cos(math.pi * k / 6),
                Z_SPON + 0.02 + 0.2 * math.sin(math.pi * k / 6),
            )
            for k in range(7)
        ]
        mt.geo(P, M.tubo("guarda", arco, 0.01, 6), od)
        mt.geo(
            P,
            B.caixa("lanterna", (0.06, 0.12, 0.1), (XR + 0.04, s * 1.05, Z_SPON + 0.06), 0.008),
            od,
        )
        mt.det(
            P,
            B.caixa("lente_t", (0.01, 0.05, 0.04), (XR + 0.006, s * 1.05, Z_SPON + 0.07)),
            lente_v,
        )
        # ganchos de reboque
        g = M.toro("gancho", 0.06, 0.018, 12, 6)
        M.mover(
            g,
            Matrix.Translation((XF - 0.22, s * 0.42, 0.62)) @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        mt.geo(P, g, aco)
        g = M.toro("gancho_t", 0.06, 0.018, 12, 6)
        M.mover(
            g,
            Matrix.Translation((XR + 0.02, s * 0.42, 0.62)) @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
        mt.geo(P, g, aco)
        # parafusos na borda do casco de cima
        pf = B.Lote("parafusos")
        for k in range(14):
            pf.cil(
                0.01,
                0.012,
                Matrix.Translation((XR + 0.2 + k * 0.25, s * 1.29, Z_SPON + 0.02))
                @ Matrix.Rotation(math.pi / 2, 4, "X"),
                6,
            )
        mt.det(P, pf.objeto(), od)
        # solda das chapas
        mt.det(
            P,
            M.tubo(
                "solda", [(XR + 0.06, s * 1.299, Z_SPON), (XF - 0.04, s * 1.299, Z_SPON)], 0.008, 6
            ),
            od,
        )
        # caixa de estiva no lado
        mt.geo(
            P,
            B.caixa(
                "caixa",
                (0.55, 0.12, 0.22),
                (XR + 0.85, s * 1.15, Z_SPON + 0.2),
                0.01,
                (math.radians(s * 42), 0, 0),
            ),
            od,
        )
    # sapatas de reserva na frente
    for k in range(3):
        x = XF - 0.35 - k * 0.24
        t = (XF - 0.04 - x) / 1.58
        z = Z_SPON + (Z_ROOF - Z_SPON) * t
        ang = math.radians(90 - 71)
        mt.geo(
            P, B.caixa("barra", (0.06, 0.62, 0.03), (x, -0.25, z + 0.02), 0.005, (0, -ang, 0)), aco
        )
    # porta dupla atrás: moldura e dobradiças
    mt.geo(P, B.caixa("moldura_porta", (0.03, 1.02, 0.5), (XR + 0.09, 0, 1.18), 0.008), od)
    # periscópios do motorista
    for dy in (-0.12, 0.0, 0.12):
        x = DRV.x + 0.26
        t = (XF - 0.04 - x) / 1.58
        z = Z_SPON + (Z_ROOF - Z_SPON) * t
        mt.geo(P, B.caixa("periscopio", (0.08, 0.09, 0.07), (x, DRV.y + dy, z + 0.03), 0.008), od)
        mt.det(P, B.caixa("vidro_p", (0.01, 0.07, 0.03), (x + 0.042, DRV.y + dy, z + 0.04)), vidro)
    # aro da torre e grade do motor (frente direita: motor ao lado do motorista)
    mt.geo(P, B.cil("aro_torre", (X_T, 0, Z_ROOF - 0.02), (X_T, 0, Z_ROOF + 0.04), 0.48, 16), od)
    g = B.Lote("grade")
    for k in range(8):
        x = 0.2 + k * 0.07
        t = (XF - 0.04 - x) / 1.58
        z = Z_SPON + (Z_ROOF - Z_SPON) * t
        g.caixa(
            (0.03, 0.42, 0.01),
            Matrix.Translation((x, -0.42, z + 0.004)) @ Matrix.Rotation(-math.radians(19), 4, "Y"),
        )
    mt.det(P, g.objeto(), aco_esc)
    # marcações
    for s, lado in ((1, "+Y"), (-1, "-Y")):
        t = B.letreiro("USMC 113067", 0.05, amarelo, (0, 0, 0), lado)
        incl = math.radians(42)
        M.mover(
            t,
            Matrix.Translation((-0.3, s * 1.06, 1.22))
            @ Matrix.Rotation(s * incl, 4, "X")
            @ Matrix.Translation((0, 0, 0)),
        )
        mt.det(P, t, amarelo)
    mt.atlas(P, "casco")

    # ================================================================ ESCOTILHAS DO CASCO
    P = "Escotilha_Motorista"
    t = (XF - 0.04 - DRV.x) / 1.58
    z = Z_SPON + (Z_ROOF - Z_SPON) * t
    h = B.caixa(
        "tampa_mot", (0.42, 0.42, 0.04), (DRV.x, DRV.y, z + 0.025), 0.012, (0, -math.radians(19), 0)
    )
    mt.geo(P, h, od)
    mt.geo(
        P,
        B.caixa(
            "alca", (0.03, 0.14, 0.025), (DRV.x, DRV.y, z + 0.06), 0.005, (0, -math.radians(19), 0)
        ),
        aco,
    )
    mt.pivo(P, (DRV.x - 0.21, DRV.y, z + 0.08))
    mt.atlas(P, "casco")
    for nome, s in (("Escotilha_TraseiraE", 1), ("Escotilha_TraseiraD", -1)):
        mt.geo(nome, B.caixa("porta", (0.04, 0.48, 0.44), (XR + 0.115, s * 0.25, 1.18), 0.01), od)
        mt.geo(nome, B.caixa("alca_p", (0.03, 0.025, 0.12), (XR + 0.08, s * 0.08, 1.2), 0.005), aco)
        for zz in (1.02, 1.34):
            mt.geo(
                nome,
                B.cil(
                    "dobradica",
                    (XR + 0.1, s * 0.49, zz - 0.04),
                    (XR + 0.1, s * 0.49, zz + 0.04),
                    0.022,
                    8,
                ),
                aco,
            )
        mt.pivo(nome, (XR + 0.1, s * 0.49, 1.18))
        mt.atlas(nome, "casco")

    # ================================================================ TORRE
    P = "Torre"
    aneis = []
    for z, s in ((Z_ROOF + 0.02, 1.0), (1.78, 0.95), (Z_TR, 0.78)):
        aneis.append(B.planta(z, X_T - 0.42 * s, X_T + 0.42 * s, 0.4 * s, 0.14 * s, 4, 4.0))
    mt.geo(P, B.loft("torre", aneis), od_t)
    # braços do reparo (fora da torre, seguram as colunas de fuzis)
    for s in (1, -1):
        mt.geo(P, B.caixa("munhao", (0.18, 0.2, 0.18), (TRUN.x, s * 0.47, TRUN.z), 0.02), od_t)
    # .30 M1919A4 no teto
    mt.geo(P, B.cil("pino", (X_T + 0.1, 0, Z_TR), (X_T + 0.1, 0, Z_TR + 0.12), 0.025, 8), aco)
    mt.geo(P, B.caixa("caixa_30", (0.3, 0.08, 0.1), (X_T + 0.18, 0, Z_TR + 0.17), 0.01), aco_esc)
    mt.geo(
        P,
        B.cil("cano_30", (X_T + 0.33, 0, Z_TR + 0.18), (X_T + 0.95, 0, Z_TR + 0.18), 0.022, 8),
        aco_esc,
    )
    mt.geo(
        P, B.caixa("cunhete_30", (0.18, 0.06, 0.14), (X_T + 0.15, 0.08, Z_TR + 0.13), 0.008), od_t
    )
    mt.geo(
        P,
        B.cil("aro_esc", (X_T - 0.15, 0, Z_TR - 0.01), (X_T - 0.15, 0, Z_TR + 0.03), 0.24, 14),
        od_t,
    )
    for s in (1, -1):
        t = B.letreiro("C33", 0.09, amarelo, (X_T - 0.15, s * 0.37, 1.72), "+Y" if s > 0 else "-Y")
        mt.det(P, t, amarelo)
    mt.pivo(P, (X_T, 0, Z_ROOF))
    mt.atlas(P, "torre")
    P = "Escotilha_Torre"
    mt.geo(
        P,
        B.cil("tampa_t", (X_T - 0.15, 0, Z_TR + 0.03), (X_T - 0.15, 0, Z_TR + 0.07), 0.22, 14),
        od_t,
    )
    mt.pivo(P, (X_T - 0.37, 0, Z_TR + 0.05))
    mt.atlas(P, "torre")

    # ================================================================ CANO (os 6 fuzis)
    P = "Cano"
    L = X_MUZ - X_BREECH
    perfil = [
        (0.0, 0.0),
        (0.09, 0.0),
        (0.11, 0.05),
        (0.11, 0.3),
        (0.085, 0.34),
        (0.125, 0.42),
        (0.125, 0.78),
        (0.09, 0.85),
        (0.078, 1.0),
        (0.072, L - 0.05),
        (0.078, L),
        (0.055, L),
        (0.055, L - 0.06),
        (0.0, L - 0.06),
    ]
    for s in (1, -1):
        for i, (yy, zz) in enumerate(RIFLES):
            y = s * yy
            tubo = M.torno("fuzil", perfil, 12)
            M.mover(
                tubo, Matrix.Translation((X_BREECH, y, zz)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
            )
            mt.geo(P, tubo, od_f)
            # abraçadeiras do reparo
            for xa in (TRUN.x - 0.2, TRUN.x + 0.35):
                mt.geo(P, B.cil("abrac", (xa, y, zz), (xa + 0.06, y, zz), 0.09, 10), od_f)
            # lona sobre a culatra
            capa = M.superelipsoide("capa", 0.2, 0.13, 0.13, 0.7, 0.6, 12, 6)
            M.deslocar(capa, lambda co, n, i=i, s=s: 0.012 * M.fbm(co * 10, 3, 50 + i + s))
            M.mover(capa, Matrix.Translation((X_BREECH + 0.17, y, zz)))
            mt.geo(P, capa, lona)
            # pontaria .50 M8C: sobre o de cima e ao lado (de fora) do do meio
            if i == 0:
                py, pz = y, zz + 0.105
            elif i == 1:
                py, pz = y + s * 0.11, zz + 0.02
            else:
                continue
            mt.geo(
                P, B.cil("m8c", (TRUN.x - 0.45, py, pz), (TRUN.x + 0.85, py, pz), 0.02, 8), aco_esc
            )
            mt.geo(
                P, B.caixa("m8c_caixa", (0.25, 0.05, 0.06), (TRUN.x - 0.35, py, pz), 0.006), aco_esc
            )
        # placa do reparo que junta a coluna
        mt.geo(P, B.caixa("placa", (0.6, 0.05, 0.52), (TRUN.x + 0.05, s * 0.6, 1.8), 0.012), od_f)
        mt.geo(P, B.caixa("eixo", (0.12, 0.2, 0.12), (TRUN.x, s * 0.5, TRUN.z), 0.012), od_f)
    mt.pivo(P, tuple(TRUN))
    mt.atlas(P, "torre")

    # ================================================================ RODAGEM
    circ = [(x, Z_RW, R_RW) for x in X_RW] + [(X_SP, Z_SP, R_SP)]
    pts, tang, nrm, comp = B.laco(circ, 75, sag=0.03, z_sag=Z_RW + 0.1)
    P = "Esteira_E"
    sec = [(0.0, -W_TR / 2), (0.0, W_TR / 2), (T_TR, W_TR / 2), (T_TR, -W_TR / 2)]
    mt.geo(P, B.faixa("esteira", pts, nrm, sec, Y_TR), banda)
    barras, guias = B.Lote("travessas"), B.Lote("guias")
    for (x, z), (tx, tz), (nx, nz) in zip(pts, tang, nrm, strict=True):
        ex, ey, ez = Vector((tx, 0, tz)), Vector((0, 1, 0)), Vector((nx, 0, nz))
        o = Vector((x, Y_TR, z))
        barras.caixa((0.035, W_TR - 0.04, 0.016), B.quadro(o + ez * (T_TR + 0.006), ex, ey, ez))
        for dy in (-0.235, 0.0, 0.235):
            guias.caixa((0.05, 0.03, 0.022), B.quadro(o - ez * 0.009 + ey * dy, ex, ey, ez))
    mt.det(P, barras.objeto(), aco)
    mt.det(P, guias.objeto(), aco)
    mt.atlas(P, "rodagem")
    mt.sem_limpeza(P)
    mt.espelho("Esteira_D", P)

    def roda(nome, x, z, r, larg=0.2):
        perfil = [
            (0.0, larg + 0.03),
            (0.06, larg + 0.03),
            (r - 0.08, larg),
            (r, larg),
            (r, 0.035),
            (r - 0.1, 0.035),
            (r - 0.1, -0.035),
            (r, -0.035),
            (r, -larg),
            (0.0, -larg),
        ]
        o = B.torno_eixo(nome, perfil, "Y", (x, Y_TR, z), 14)
        M.material(o, od)
        B.pintar_por(o, lambda c, n: math.hypot(c.x - x, c.z - z) > r - 0.05, borr)
        return o

    P = "Roda_E1"
    mt.geo(P, roda("roda", X_RW[-1], Z_RW, R_RW), None)
    pf = B.Lote("porcas")
    for k in range(6):
        a = 2 * math.pi * k / 6
        pf.cil(
            0.01,
            0.018,
            Matrix.Translation(
                (X_RW[-1] + 0.04 * math.cos(a), Y_TR + 0.232, Z_RW + 0.04 * math.sin(a))
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
    P = "Roda_EM"
    for y0, y1 in ((Y_TR + 0.12, Y_TR + 0.17), (Y_TR - 0.17, Y_TR - 0.12)):
        mt.geo(P, B.engrenagem("coroa", 0.22, 0.275, 15, y0, y1, (X_SP, Z_SP)), aco)
    mt.geo(
        P,
        B.torno_eixo(
            "cubo_m",
            [(0.0, 0.25), (0.08, 0.25), (0.1, 0.22), (0.18, 0.2), (0.18, -0.13), (0.0, -0.13)],
            "Y",
            (X_SP, Y_TR, Z_SP),
            14,
        ),
        od,
    )
    mt.pivo(P, (X_SP, Y_TR, Z_SP))
    mt.atlas(P, "rodagem")
    mt.instancia("Roda_DM", "Roda_EM", (X_SP, -Y_TR, Z_SP), giro_z180=True)
    # cubo da motriz e braços das rodas (no casco)
    for s in (1, -1):
        mt.geo(
            "Casco",
            B.cil("cubo_motriz", (X_SP, s * 0.6, Z_SP), (X_SP, s * (Y_TR - 0.13), Z_SP), 0.11, 10),
            od,
        )
        for x in X_RW:
            mt.geo(
                "Casco",
                B.caixa(
                    "braco",
                    (0.32, 0.07, 0.08),
                    (x + 0.14, s * 0.66, Z_RW + 0.07),
                    0.008,
                    (0, math.radians(-20), 0),
                ),
                aco,
            )
    mt.ext["rodagem"] = 0.03

    olho_mot = (DRV.x - 0.05, DRV.y, 1.78)
    info = {
        "nome": "M50A1 Ontos (USMC, 1965)",
        "faccao": "US",
        "medidas": MEDIDAS,
        "olhos": {
            "driver": olho_mot,
            "gunner": (X_T - 0.15, 0.0, Z_TR + 0.45),
            "loader": (X_T - 0.85, 0.0, Z_ROOF + 0.5),
        },
        "lagarta": {
            "circulos": [
                (X_SP, Z_SP, R_SP + T_TR),
                (X_RW[-1], Z_RW, R_RW + T_TR),
                (X_RW[1], Z_RW, R_RW + T_TR),
                (X_RW[0], Z_RW, R_RW + T_TR),
            ],
            "y_centro": Y_TR,
            "largura": W_TR,
            "comprimento_laco": comp,
        },
        "escapes": [(XR + 0.4, -0.95, 1.05)],
        "escotilhas": {
            "Escotilha_Motorista": [0.42, 0.42],
            "Escotilha_Torre": [0.44, 0.44],
            "Escotilha_TraseiraE+D": [0.96, 0.44],
        },
        "notas": [
            "A roda motriz é a da frente e a de trás faz de roda-guia: os 4 'circles' do ART são "
            "motriz, 1ª roda, 3ª roda e a última (guia), na ordem que o VehicleFx espera.",
            "Olho do municiador: atrás da torre (ele recarrega por fora, pela porta dupla).",
        ],
    }
    return mt, info
