"""UH-34D Seahorse dos esquadrões HMM-261/361 (MAG-16), Starlite, agosto de 1965.

Motor radial no nariz (portas em concha), cabine dos pilotos alta, por cima e atrás do motor, com
janelas abertas e forro por dentro (o olho do piloto fica dentro), porão da tropa com a porta de
correr da direita aberta (forro por dentro, bancos de lona e a M60 da porta), cone de cauda que
sobe até a deriva com o rotor de cauda de 4 pás à esquerda, trem principal largo e bequilha.
Partes: Casco (frente), Cauda (cone, deriva e estabilizador), RotorPrincipal (cubo) com as pás
Pa_1..Pa_4 (uma malha, 4 nós girados 90°: soldar no cubo), RotorCauda (cubo e 4 pás), Roda_E,
Roda_D, Roda_Cauda, Escotilha_Porta (porta de correr, aberta para trás).
"""

from __future__ import annotations

import math

import modelar as M
import veic_base as B
from mathutils import Matrix, Vector

FI = "https://www.flugzeuginfo.net/acdata_php/acdata_s58_en.php"
SA = "https://sikorskyarchives.com/?p=4968"
MEDIDAS = {
    "comprimento_fuselagem_m": [
        14.25,
        f"flugzeuginfo e Sikorsky Archives: 46 ft 9 in ({FI}; "
        f"{SA}); a Wikipedia dá 47 ft 2 in (14,38 m)",
    ],
    "rotor_principal_diametro_m": [17.07, f"flugzeuginfo: 56 ft, 4 pás ({FI})"],
    "rotor_cauda_diametro_m": [2.90, f"flugzeuginfo: 9 ft 6 in, 4 pás ({FI})"],
    "altura_m": [4.85, f"flugzeuginfo e Sikorsky: 15 ft 11 in ({FI}); a Wikipedia dá 14 ft 3,5 in"],
    "bitola_trem_m": [
        4.27,
        "NATOPS citado em popasmoke.com/notam/aircraft-38/uh-34d-shipboad-"
        "folded: 14 ft no trem de perna em V (12 ft no de perna curva)",
    ],
    "motor_no_nariz": [
        None,
        "usmcmuseum.com/sikorsky-uh-34d.html: motor baixo no nariz; portas em "
        "concha (Sikorsky Archives)",
    ],
    "porta_e_m60": [
        None,
        "M60 na porta da direita (shootingillustrated.com/articles/2020/10/14/"
        "fightin-iron-how-the-h-34-helicopter-changed-the-face-of-combat); medidas da "
        "porta: PLACEHOLDER",
    ],
    "cor": [
        None,
        "Field Green FS 34097 com letreiro preto: popasmoke.com/notam/aircraft-4/marine-"
        "helicopter-colors (Monogram Color Guide; relato do HMM-161 em 1965: branco "
        "repintado de preto antes de entrar no país). Tom sRGB: aproximação",
    ],
    "marcas": [
        None,
        "'YN' = HMM-361 (en.wikipedia.org/wiki/HMH-361); BuNo 150570 'YN-19' voou "
        "na Starlite (usmcmuseum.com/sikorsky-uh-34d.html). Posição de 'MARINES' no cone: "
        "PLACEHOLDER (sem fonte textual)",
    ],
    "fuselagem_secoes": [
        None,
        "PLACEHOLDER: perfil e larguras do casco desenhados sobre fotos; "
        "só o comprimento, a altura e os rotores têm fonte",
    ],
    "rodas_m": [None, "PLACEHOLDER: roda principal Ø 0,72 m, bequilha Ø 0,40 m"],
}

ESTACOES = [  # (x, topo, base, meia largura, expoente)
    (7.125, 1.85, 1.05, 0.30, 2.0),
    (7.05, 2.10, 0.80, 0.58, 2.2),
    (6.85, 2.28, 0.68, 0.74, 2.5),
    (6.45, 2.40, 0.62, 0.82, 2.8),
    (6.0, 2.52, 0.60, 0.84, 3.2),
    (5.7, 2.75, 0.60, 0.84, 3.4),
    (5.35, 3.24, 0.60, 0.84, 3.4),
    (4.95, 3.50, 0.60, 0.84, 3.6),
    (4.25, 3.54, 0.60, 0.84, 3.8),
    (3.6, 3.50, 0.60, 0.84, 3.8),
    (2.95, 3.44, 0.61, 0.84, 3.8),
    (2.3, 3.15, 0.66, 0.83, 3.6),
    (1.7, 2.85, 0.78, 0.80, 3.4),
    (1.0, 2.70, 0.98, 0.72, 3.0),
]
ESTACOES_CAUDA = [
    (1.0, 2.70, 0.98, 0.72, 3.0),
    (0.2, 2.62, 1.18, 0.60, 2.8),
    (-1.0, 2.56, 1.42, 0.48, 2.6),
    (-2.4, 2.52, 1.66, 0.38, 2.5),
    (-3.8, 2.48, 1.86, 0.31, 2.4),
    (-5.0, 2.45, 2.02, 0.26, 2.4),
    (-5.35, 2.44, 2.08, 0.24, 2.4),
]
HUB = Vector((3.6, 0.0, 4.55))
TAIL = Vector((-6.55, 0.34, 3.40))
R_ROT, R_CAUDA = 17.07 / 2, 2.90 / 2
WHEEL = Vector((4.45, 4.27 / 2, 0.36))
TWHEEL = Vector((-1.65, 0.0, 0.2))
PORTA = (2.95, 4.25)  # x da abertura
PORTA_E = (2.15, 4.25)  # x da abertura da esquerda (v45, liberdade de jogo)


def receita():
    mt = B.Montagem()
    verde = mt.mat("pintura", B.mat_aviao, fuligem=(6.2, 0.85, 1.0, 0.9))
    verde_c = mt.mat("pintura_cauda", B.mat_aviao, z_lama=0.0)
    pa_m = mt.mat("pas", B.mat_aviao, "#4f5134", "#6a6b4c", "#33341f", 3.0, 0.2, 0.25, 0.0)
    interior = mt.mat("interior", B.mat_simples, "#3d4433", 0.85, 0.0)
    painel = mt.mat("painel", B.mat_simples, "#141413", 0.6, 0.0)
    banco = mt.mat("banco", B.mat_lona, "#6a2a1e", "#8a3a28", 0.0)
    vidro = mt.mat("vidro", B.mat_vidro, "#1c2428", 0.1)
    aco = mt.mat("aco", B.mat_aco_sujo, z_lama=0.6, brilho_contato=True)
    aco_esc = mt.mat("aco_escuro", B.mat_simples, "#1e1d1a", 0.5, 0.6)
    borr = mt.mat("borracha", B.mat_borracha, z_lama=0.5)
    preto = mt.mat("letra_preta", B.mat_estencil, "#141412", "#4b5539", 0.3)

    # ================================================================ CASCO (frente)
    P = "Casco"
    fus = B.fuselagem("fuselagem", ESTACOES, 36, True, False)

    def janela_cabine(c, n):
        frente = c.x > 5.25 and c.z > 2.62 and abs(c.y) > 0.07 and n.x > 0.25
        lado = 4.35 < c.x < 5.3 and 2.6 < c.z < 3.25 and abs(n.y) > 0.55
        return frente or lado

    def porta(c, n):
        direita = PORTA[0] < c.x < PORTA[1] and 0.85 < c.z < 2.2 and n.y < -0.5
        # v45 (D-113, pedido do dono): o porão da tropa aberto também à esquerda, para quem vai
        # sentado ver para fora e ser visto (o H-34 real tinha só janelas desse lado)
        esquerda = PORTA_E[0] < c.x < PORTA_E[1] and 0.85 < c.z < 2.2 and n.y > 0.5
        return direita or esquerda

    def reg_cabine(c, n):
        return 4.15 < c.x < 6.1 and c.z > 2.25

    def reg_porao(c, n):
        return 1.95 < c.x < 5.4 and (c.z < 2.62 if c.x < 4.15 else c.z < 2.25)

    forro1 = B.abrir_e_forrar(fus, lambda c, n: reg_cabine(c, n), janela_cabine, 0.012, "forro_cab")
    forro2 = B.abrir_e_forrar(fus, lambda c, n: reg_porao(c, n), porta, 0.012, "forro_porao")
    mt.geo(P, fus, verde, suave=50)
    mt.geo(P, forro1, interior, suave=50)
    mt.geo(P, forro2, interior, suave=50)
    # piso da cabine dos pilotos (= teto do porão na frente), parede de trás da cabine, anteparas
    mt.geo(P, B.caixa("piso_cab", (1.95, 1.62, 0.04), (5.12, 0, 2.25), 0.0), interior)
    mt.geo(P, B.caixa("parede_cab", (0.04, 1.6, 1.25), (4.17, 0, 2.87), 0.0), interior)
    mt.geo(P, B.caixa("teto_porao", (2.3, 1.6, 0.04), (3.07, 0, 2.6), 0.0), interior)
    mt.geo(P, B.caixa("antepara_f", (0.04, 1.6, 1.65), (5.38, 0, 1.43), 0.0), interior)
    mt.geo(P, B.caixa("antepara_t", (0.04, 1.5, 1.6), (1.97, 0, 1.6), 0.0), interior)
    # painel de instrumentos e bancos dos pilotos
    mt.geo(
        P,
        B.caixa("painel", (0.12, 1.3, 0.32), (5.62, 0, 2.62), 0.02, (0, math.radians(-20), 0)),
        painel,
    )
    for s in (1, -1):
        mt.geo(P, B.caixa("assento", (0.45, 0.45, 0.08), (4.75, s * 0.38, 2.36), 0.02), banco)
        mt.geo(
            P,
            B.caixa(
                "encosto",
                (0.08, 0.45, 0.55),
                (4.5, s * 0.38, 2.68),
                0.02,
                (0, math.radians(-12), 0),
            ),
            banco,
        )
        mt.geo(
            P, B.cil("manche", (5.15, s * 0.38, 2.27), (5.05, s * 0.38, 2.75), 0.018, 6), aco_esc
        )
    # banco de lona da tropa (parede da esquerda) e no fundo
    mt.geo(P, B.caixa("banco_tropa", (3.0, 0.32, 0.05), (3.6, 0.6, 1.18), 0.01), banco)
    mt.geo(P, B.caixa("encosto_tropa", (3.0, 0.04, 0.45), (3.6, 0.76, 1.45), 0.005), banco)
    mt.geo(P, B.caixa("banco_fundo", (0.32, 1.2, 0.05), (2.15, 0, 1.18), 0.01), banco)
    # trilho da porta e M60 da porta (pino na borda da frente)
    mt.geo(P, B.caixa("trilho", (2.7, 0.05, 0.05), (2.95, -0.86, 2.24), 0.01), aco)
    mt.geo(P, B.cil("pino_m60", (4.12, -0.72, 0.9), (4.12, -0.72, 1.45), 0.025, 8), aco)
    mt.geo(
        P,
        B.caixa("m60", (0.55, 0.08, 0.1), (4.12, -0.92, 1.5), 0.012, (0, 0, math.radians(90))),
        aco_esc,
    )
    mt.geo(P, B.cil("cano_m60", (4.12, -1.15, 1.52), (4.12, -1.62, 1.52), 0.014, 6), aco_esc)
    mt.geo(P, B.caixa("cunhete", (0.26, 0.11, 0.18), (4.0, -0.66, 1.32), 0.008), verde)
    # carenagem do mastro, mastro e entrada de ar da transmissão
    mt.geo(
        P,
        M.torno(
            "carenagem", [(0.0, 3.38), (0.55, 3.38), (0.48, 3.7), (0.3, 4.05), (0.0, 4.12)], 16
        ),
        verde,
    )
    M.mover(mt.partes[P]["geo"][-1], Matrix.Translation((HUB.x, 0, 0)))
    mt.geo(P, B.cil("mastro", (HUB.x, 0, 4.0), (HUB.x, 0, HUB.z - 0.08), 0.12, 12), aco)
    mt.geo(
        P,
        B.caixa("antena", (0.25, 0.03, 0.22), (2.0, 0, 3.12), 0.008, (0, math.radians(-25), 0)),
        verde,
    )
    # escapamentos do radial (dois de cada lado, embaixo do nariz) e grade do motor
    for s in (1, -1):
        for dx in (0.0, 0.22):
            mt.geo(
                P,
                B.cil("escape", (6.35 - dx, s * 0.8, 1.02), (6.15 - dx, s * 0.92, 0.88), 0.055, 10),
                aco,
            )
        g = B.Lote("veneziana")
        for k in range(7):
            g.caixa((0.05, 0.012, 0.22), Matrix.Translation((6.55 - k * 0.09, s * 0.835, 1.9)))
        mt.det(P, g.objeto(), aco_esc)
        # degraus da esquerda (subida para a cabine)
        if s > 0:
            for zz in (1.2, 1.75, 2.3):
                mt.det(P, B.caixa("degrau", (0.16, 0.012, 0.07), (4.9, 0.845, zz)), aco_esc)
        # janelas do porão (à esquerda o lado agora é aberto: v45)
        for xx in () if s > 0 else (2.25,):
            mt.det(P, B.caixa("janela", (0.32, 0.012, 0.3), (xx, s * 0.842, 1.85)), vidro)
        # trem principal: amortecedor até o lado da fuselagem e o V até a barriga
        roda = Vector((WHEEL.x, s * WHEEL.y, WHEEL.z))
        mt.geo(
            P,
            B.cil("oleo", roda + Vector((0, -s * 0.12, 0.05)), (WHEEL.x, s * 0.84, 1.75), 0.07, 10),
            aco,
        )
        mt.geo(
            P,
            B.cil(
                "oleo_c",
                roda + Vector((0, -s * 0.12, 0.05)),
                roda + Vector((0, -s * 0.5, 0.5)),
                0.09,
                10,
            ),
            verde,
        )
        for xa in (WHEEL.x + 0.55, WHEEL.x - 0.55):
            mt.geo(
                P,
                B.cil("v", roda + Vector((0, -s * 0.12, 0.0)), (xa, s * 0.74, 0.66), 0.045, 8),
                verde,
            )
        mt.geo(
            P,
            B.cil(
                "eixo", roda + Vector((0, -s * 0.16, 0)), roda + Vector((0, -s * 0.02, 0)), 0.05, 8
            ),
            aco,
        )
    # costura das portas em concha do nariz
    mt.det(
        P,
        M.tubo("costura", [(7.13, 0, 1.2), (7.1, 0, 1.6), (7.0, 0, 2.0), (6.8, 0, 2.3)], 0.006, 6),
        aco_esc,
    )
    # número do avião no nariz (YN-19)
    for s, lado in ((1, "+Y"), (-1, "-Y")):
        mt.det(P, B.letreiro("19", 0.28, preto, (6.15, s * 0.846, 1.75), lado), preto)
    mt.det(P, B.letreiro("19", 0.22, preto, (0, 0, 0), "+X"), preto)
    M.mover(
        mt.partes[P]["det"][-1],
        Matrix.Translation((7.07, 0, 1.55)) @ Matrix.Rotation(-0.25, 4, "Y"),
    )
    mt.sem_limpeza(P)
    mt.atlas(P, "casco")

    # ================================================================ CAUDA
    P = "Cauda"
    mt.geo(P, B.fuselagem("cone", ESTACOES_CAUDA, 28, False, True), verde_c, suave=50)
    deriva = [
        (-5.0, 2.10),
        (-5.3, 2.95),
        (-6.25, 3.95),
        (-6.95, 4.05),
        (-7.125, 3.8),
        (-6.8, 2.55),
        (-6.2, 2.08),
    ]
    d = B.prisma("deriva", deriva, "Y", -0.12, 0.12)
    M.chanfrar(d, 0.02, 1, 30.0)
    mt.geo(P, d, verde_c)
    mt.geo(P, B.caixa("estabilizador", (0.55, 0.95, 0.05), (-6.55, -0.6, 2.55), 0.02), verde_c)
    mt.geo(
        P,
        B.cil("cubo_caixa", (TAIL.x, 0.12, TAIL.z), (TAIL.x, TAIL.y - 0.08, TAIL.z), 0.11, 10),
        verde_c,
    )
    mt.geo(P, B.cil("eixo_cauda", (-0.4, 0, 2.66), (-5.2, 0, 2.47), 0.05, 8), verde_c)
    # bequilha: perna e garfo
    mt.geo(
        P, B.cil("perna_bq", (-1.45, 0, 1.47), (TWHEEL.x + 0.05, 0, TWHEEL.z + 0.25), 0.06, 10), aco
    )
    mt.geo(
        P,
        B.caixa("garfo", (0.12, 0.16, 0.12), (TWHEEL.x + 0.02, 0, TWHEEL.z + 0.22), 0.01),
        verde_c,
    )
    for s, lado in ((1, "+Y"), (-1, "-Y")):
        mt.det(P, B.letreiro("MARINES", 0.24, preto, (-2.2, s * 0.385, 2.1), lado), preto)
        mt.det(P, B.letreiro("YN", 0.34, preto, (-6.15, s * 0.124, 3.0), lado), preto)
        mt.det(P, B.letreiro("150570", 0.075, preto, (-6.0, s * 0.124, 2.55), lado), preto)
    mt.atlas(P, "cauda")

    # ======================================================= PORTA (de correr, aberta para trás)
    P = "Escotilha_Porta"
    mt.geo(P, B.caixa("porta", (1.25, 0.035, 1.18), (2.32, -0.875, 1.5), 0.015), verde)
    mt.geo(P, B.caixa("alca", (0.03, 0.03, 0.16), (2.85, -0.9, 1.5), 0.005), aco)
    mt.det(P, B.caixa("janela_p", (0.34, 0.012, 0.3), (2.3, -0.894, 1.82)), vidro)
    mt.atlas(P, "cauda")

    # ================================================================ ROTOR PRINCIPAL: cubo e pás
    P = "RotorPrincipal"
    mt.geo(
        P,
        M.torno("cubo", [(0.0, -0.12), (0.34, -0.12), (0.36, 0.05), (0.2, 0.22), (0.0, 0.3)], 16),
        aco,
    )
    M.mover(mt.partes[P]["geo"][-1], Matrix.Translation(HUB))
    for k in range(4):
        a = math.radians(45 + 90 * k)
        u = Vector((math.cos(a), math.sin(a), 0))
        v = Vector((-math.sin(a), math.cos(a), 0))
        mt.geo(P, B.caixa("punho", (0.62, 0.16, 0.14), HUB + u * 0.55, 0.02, (0, 0, a)), aco)
        mt.geo(
            P,
            B.cil(
                "amortecedor",
                HUB + u * 0.32 + v * 0.16 + Vector((0, 0, 0.08)),
                HUB + u * 0.75 + v * 0.14 + Vector((0, 0, 0.02)),
                0.04,
                8,
            ),
            aco_esc,
        )
    mt.pivo(P, tuple(HUB))
    mt.atlas(P, "cauda")
    P = "Pa_1"
    a = math.radians(45)
    pts = []
    for r in (0.82, 1.2, 2.5, 4.0, 5.5, 7.0, 8.2, R_ROT):
        caido = -0.38 * (r / R_ROT) ** 2
        pts.append(HUB + Vector((math.cos(a) * r, math.sin(a) * r, caido)))
    mt.geo(
        P,
        M.tubo("pa", pts, [0.12, 0.2, 0.205, 0.205, 0.205, 0.205, 0.205, 0.19], 8, True, 0.13),
        pa_m,
    )
    mt.pivo(P, tuple(HUB))
    mt.atlas(P, "cauda")
    for k in (1, 2, 3):
        mt.instancia(f"Pa_{k + 1}", "Pa_1", tuple(HUB), angulo_z=90.0 * k)

    # ================================================================ ROTOR DE CAUDA
    P = "RotorCauda"
    mt.geo(
        P,
        B.torno_eixo(
            "cubo_c",
            [(0.0, -0.05), (0.13, -0.05), (0.13, 0.08), (0.06, 0.16), (0.0, 0.17)],
            "Y",
            tuple(TAIL),
            12,
        ),
        aco,
    )
    for k in range(4):
        a = math.radians(20 + 90 * k)
        u = Vector((math.cos(a), 0, math.sin(a)))
        c = TAIL + u * (0.25 + (R_CAUDA - 0.25) / 2) + Vector((0, 0.06, 0))
        mt.geo(P, B.caixa("pa_c", (R_CAUDA - 0.25, 0.025, 0.17), c, 0.008, (0, -a, 0)), pa_m)
    mt.pivo(P, tuple(TAIL))
    mt.atlas(P, "cauda")

    # ================================================================ RODAS
    P = "Roda_E"
    perf = [
        (0.0, 0.11),
        (0.1, 0.11),
        (0.2, 0.1),
        (0.3, 0.11),
        (0.36, 0.08),
        (0.36, -0.08),
        (0.3, -0.11),
        (0.0, -0.11),
    ]
    o = B.torno_eixo("roda", perf, "Y", tuple(WHEEL), 16)
    M.material(o, borr)
    B.pintar_por(o, lambda c, n: math.hypot(c.x - WHEEL.x, c.z - WHEEL.z) < 0.24, verde)
    mt.geo(P, o, None)
    mt.pivo(P, tuple(WHEEL))
    mt.atlas(P, "cauda")
    mt.instancia("Roda_D", "Roda_E", (WHEEL.x, -WHEEL.y, WHEEL.z), giro_z180=True)
    P = "Roda_Cauda"
    perf = [(0.0, 0.05), (0.08, 0.05), (0.2, 0.04), (0.2, -0.04), (0.08, -0.05), (0.0, -0.05)]
    o = B.torno_eixo("bequilha", perf, "Y", tuple(TWHEEL), 12)
    M.material(o, borr)
    B.pintar_por(o, lambda c, n: math.hypot(c.x - TWHEEL.x, c.z - TWHEEL.z) < 0.12, verde)
    mt.geo(P, o, None)
    mt.pivo(P, tuple(TWHEEL))
    mt.atlas(P, "cauda")

    info = {
        "nome": "UH-34D Seahorse (HMM-361, 1965)",
        "faccao": "US",
        "medidas": MEDIDAS,
        "olhos": {
            "driver": (4.95, -0.38, 3.19),
            "copilot": (4.95, 0.38, 3.19),
            "gunner": (3.75, -1.0, 1.72),
        },
        "passageiros": {"x0": 4.05, "dx": 0.36, "y": 0.78, "z": 1.62},
        "assentos_z": {"driver": 2.40, "copilot": 2.40},
        "escotilhas": {"Escotilha_Porta (vão)": [1.3, 1.1]},
        "rotor": (HUB.x, HUB.y, HUB.z, R_ROT),
        "cauda": (TAIL.x, TAIL.y, TAIL.z, R_CAUDA),
        "notas": [
            "Cabine e porão com janelas e porta abertas e forro por dentro: o olho do piloto e do "
            "copiloto fica DENTRO da cabine (o forro e o painel aparecem; a casca de fora é face "
            "única e some por dentro).",
            "Pás do rotor principal: Pa_1..Pa_4 são a mesma malha em 4 nós (giro de 90° em Y do "
            "GLB); o jogo deve soldar as 4 no RotorPrincipal (cubo) e girar o cubo.",
            "Rotor de cauda no lado esquerdo da deriva (PLACEHOLDER: lado conferido só em foto).",
            "Passageiros: na porta da direita (pernas para fora) e no banco de lona da esquerda.",
            "v45: o porão também é aberto à esquerda (x 2,15 a 4,25 m), liberdade de jogo.",
        ],
    }
    return mt, info
