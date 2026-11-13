"""M151 "MUTT" de 1/4 t (USMC), em partes para o jogo.

Caçamba de chapa plana, capô chato com a grade de fendas verticais e os faróis embutidos,
para-lamas da frente chatos, para-brisa de dois vidros (levantado), bancos de lona, estepe na
traseira, para-choque da frente reto e para-choquinhos atrás com o registro (norma do USMC).
Partes: Casco, Volante, ParaBrisa (rebate na dobradiça da base), Roda_FE (frente esquerda =
lado do motorista), Roda_FD, Roda_TE, Roda_TD. O M151 não tem portas.
"""

from __future__ import annotations

import math

import modelar as M
import veic_base as B
from mathutils import Matrix, Vector

HD = "https://warwheels.net/images/M151DataSheet.pdf"
WK = "https://en.wikipedia.org/wiki/M151_MUTT"
MEDIDAS = {
    "comprimento_m": [3.353, f"ficha de Haugh: 132 pol ({HD}); Wikipedia: 3,37 m ({WK})"],
    "largura_m": [1.60, f"ficha: 63 pol ({HD}); Wikipedia: 1,63 m"],
    "altura_m": [1.803, f"ficha: 71 pol com o para-brisa levantado ({HD})"],
    "entre_eixos_m": [2.159, f"ficha: 85 pol ({HD})"],
    "bitola_m": [1.346, f"ficha: 53 pol ({HD})"],
    "vao_livre_m": [0.239, f"ficha: 9,4 pol ({HD})"],
    "pneu": [
        "7.00-16",
        f"ficha ({HD}); diâmetro externo 0,74 m calculado do tamanho "
        "(aro 16 pol + 2 x ~7 pol): PLACEHOLDER",
    ],
    "uso_em_1965": [
        None,
        "sem fonte: não achei se o USMC já usava o M151 em agosto de 1965 (o "
        "M38A1 e o M422 eram os jipes do USMC; o M151A1 começou em 1964). Feito "
        "porque o pedido nomeia o M151",
    ],
    "marcas": [
        None,
        "norma USMC de dez/1963 (garbee.net/~cabell/usmcmarkings.htm): nos jipes, o "
        "registro vai nos para-choquinhos de trás, nada no da frente, sem estrela. "
        "Número '211734' e o amarelo: PLACEHOLDER",
    ],
    "carroceria": [None, "PLACEHOLDER: alturas de capô, caçamba e bancos desenhadas sobre fotos"],
}

XF, XR = 3.353 / 2, -3.353 / 2
X_FA, X_RA = 1.10, 1.10 - 2.159
Y_W, R_W, L_W = 1.346 / 2, 0.37, 0.18
Z_W = R_W
Y_TUB, Z_FLOOR, Z_TUB = 0.78, 0.42, 1.0
X_COWL = 0.62
VOL = Vector((0.36, 0.36, 1.08))


def receita():
    mt = B.Montagem()
    od = mt.mat("pintura", B.mat_pintura, fundido=0.0, z_lama=0.75, desgaste=0.7, escala=1.5)
    lona = mt.mat("lona", B.mat_lona, "#55543a", "#6d6a4c", 0.0)
    aco = mt.mat("aco", B.mat_aco_sujo, z_lama=0.5)
    aco_esc = mt.mat("aco_escuro", B.mat_simples, "#1e1d1a", 0.5, 0.6)
    borr = mt.mat("borracha", B.mat_borracha, z_lama=0.45)
    vidro = mt.mat("vidro", B.mat_vidro, "#2a3236", 0.08)
    amarelo = mt.mat("estencil", B.mat_estencil, "#d4bd55", "#56583a", 0.4)
    lente_v = mt.mat("lente_vermelha", B.mat_simples, "#5c1712", 0.25, 0.0)

    P = "Casco"
    # caçamba: lados com o recorte da roda de trás
    lado = B.perfil_com_arcos(
        [
            (XR + 0.06, Z_FLOOR),
            (X_COWL + 0.02, Z_FLOOR),
            (X_COWL + 0.02, Z_TUB),
            (XR + 0.06, Z_TUB),
        ],
        [(X_RA, Z_W, R_W + 0.07)],
        10,
    )
    for s in (1, -1):
        mt.geo(P, B.prisma("lado", lado, "Y", s * (Y_TUB - 0.03), s * Y_TUB), od)
        mt.geo(
            P,
            B.caixa(
                "borda",
                (X_COWL - XR - 0.08, 0.06, 0.035),
                ((X_COWL + XR) / 2 - 0.01, s * (Y_TUB - 0.01), Z_TUB + 0.012),
                0.01,
            ),
            od,
        )
    mt.geo(
        P,
        B.caixa(
            "piso",
            (X_COWL - XR - 0.1, 2 * Y_TUB - 0.04, 0.03),
            ((X_COWL + XR) / 2, 0, Z_FLOOR + 0.015),
        ),
        od,
    )
    mt.geo(
        P,
        B.caixa(
            "traseira",
            (0.035, 2 * Y_TUB, Z_TUB - Z_FLOOR + 0.05),
            (XR + 0.075, 0, (Z_TUB + Z_FLOOR) / 2),
            0.01,
        ),
        od,
    )
    mt.geo(P, B.caixa("tunel", (1.7, 0.3, 0.16), (-0.25, 0, Z_FLOOR + 0.08), 0.03), od)
    # capô, grade e para-lamas da frente
    mt.geo(
        P,
        B.caixa(
            "capo",
            (XF - X_COWL - 0.08, 1.16, 0.06),
            ((XF + X_COWL) / 2 - 0.04, 0, 1.02),
            0.02,
            (0, math.radians(1.5), 0),
        ),
        od,
    )
    mt.geo(
        P,
        B.caixa("cofre", (XF - X_COWL - 0.1, 1.1, 0.45), ((XF + X_COWL) / 2 - 0.05, 0, 0.77), 0.0),
        od,
    )
    mt.geo(P, B.caixa("grade", (0.04, 1.26, 0.52), (XF - 0.09, 0, 0.74), 0.012), od)
    g = B.Lote("fendas")
    for k in range(9):
        g.caixa((0.012, 0.035, 0.26), Matrix.Translation((XF - 0.07, -0.24 + k * 0.06, 0.74)))
    mt.det(P, g.objeto(), aco_esc)
    for s in (1, -1):
        mt.geo(
            P,
            B.caixa(
                "paralama",
                (XF - X_COWL - 0.02, 0.22, 0.03),
                ((XF + X_COWL) / 2, s * 0.69, 0.96),
                0.01,
            ),
            od,
        )
        mt.geo(P, B.caixa("saia", (0.5, 0.025, 0.2), (X_COWL + 0.17, s * 0.79, 0.86), 0.006), od)
        mt.geo(
            P,
            B.cil("farol", (XF - 0.06, s * 0.43, 0.84), (XF - 0.1, s * 0.43, 0.84), 0.095, 14),
            aco_esc,
        )
        mt.geo(
            P,
            B.cil("lente", (XF - 0.058, s * 0.43, 0.84), (XF - 0.062, s * 0.43, 0.84), 0.08, 14),
            vidro,
        )
        mt.geo(P, B.caixa("luz_bo", (0.06, 0.08, 0.06), (XF - 0.2, s * 0.7, 0.99), 0.008), od)
        mt.geo(P, B.caixa("lanterna", (0.04, 0.12, 0.09), (XR + 0.05, s * 0.62, 0.88), 0.008), od)
        mt.det(P, B.caixa("lente_t", (0.01, 0.08, 0.05), (XR + 0.025, s * 0.62, 0.9)), lente_v)
        # para-choquinho de trás com o registro
        mt.geo(P, B.caixa("pchoquinho", (0.08, 0.22, 0.1), (XR + 0.04, s * 0.6, 0.55), 0.01), od)
        mt.det(
            P,
            B.letreiro(
                "USMC" if s > 0 else "211734", 0.03, amarelo, (XR - 0.002, s * 0.6, 0.55), "-X"
            ),
            amarelo,
        )
        # dobradiças do capô e ganchos
        g = M.toro("gancho", 0.04, 0.012, 10, 5)
        M.mover(
            g, Matrix.Translation((XF + 0.02, s * 0.5, 0.5)) @ Matrix.Rotation(math.pi / 2, 4, "X")
        )
        mt.geo(P, g, aco)
    mt.geo(P, B.caixa("parachoque", (0.1, 1.62, 0.12), (XF - 0.04, 0, 0.5), 0.012), od)
    # para-brisa levantado (moldura e dois vidros)
    incl = math.radians(-12)
    fr = Matrix.Translation((X_COWL + 0.02, 0, Z_TUB + 0.02)) @ Matrix.Rotation(incl, 4, "Y")
    mt.geo(
        P, B.caixa("pb_dobradica", (0.05, 1.42, 0.04), (X_COWL + 0.02, 0, Z_TUB + 0.0), 0.008), od
    )
    PB = "ParaBrisa"  # rebate para a frente sobre o capô (dobradiça na base)
    for nome, dim, c in (
        ("pb_base", (0.05, 1.42, 0.05), (0, 0, 0.03)),
        ("pb_topo", (0.04, 1.42, 0.04), (0, 0, 0.76)),
        ("pb_l1", (0.04, 0.04, 0.74), (0, 0.69, 0.4)),
        ("pb_l2", (0.04, 0.04, 0.74), (0, -0.69, 0.4)),
        ("pb_meio", (0.04, 0.04, 0.74), (0, 0, 0.4)),
    ):
        o = B.caixa(nome, dim, c, 0.008)
        M.mover(o, fr)
        mt.geo(PB, o, od)
    for s in (1, -1):
        o = B.caixa("vidro_pb", (0.012, 0.64, 0.66), (0, s * 0.345, 0.4))
        M.mover(o, fr)
        mt.geo(PB, o, vidro)
    mt.pivo(PB, (X_COWL + 0.02, 0, Z_TUB + 0.02))
    mt.atlas(PB, "a")
    mt.geo(P, B.caixa("painel", (0.14, 1.4, 0.16), (X_COWL - 0.05, 0, 0.9), 0.01), od)
    mt.geo(P, B.cil("coluna", (X_COWL - 0.1, VOL.y, 0.88), tuple(VOL), 0.022, 8), aco_esc)
    # bancos de lona (dois na frente e o banco de trás)
    for s in (1, -1):
        mt.geo(P, B.caixa("assento", (0.46, 0.42, 0.1), (-0.05, s * 0.36, 0.72), 0.025), lona)
        mt.geo(
            P,
            B.caixa(
                "encosto",
                (0.09, 0.42, 0.5),
                (-0.32, s * 0.36, 1.0),
                0.025,
                (0, math.radians(-10), 0),
            ),
            lona,
        )
        mt.geo(P, B.caixa("base_banco", (0.4, 0.36, 0.24), (-0.05, s * 0.36, 0.55), 0.01), od)
    mt.geo(P, B.caixa("banco_tras", (0.42, 1.2, 0.1), (-1.02, 0, 0.74), 0.025), lona)
    mt.geo(
        P,
        B.caixa(
            "encosto_tras", (0.09, 1.2, 0.42), (-1.3, 0, 0.98), 0.025, (0, math.radians(-8), 0)
        ),
        lona,
    )
    mt.geo(
        P,
        B.caixa("alavanca", (0.02, 0.02, 0.3), (0.15, 0.0, 0.66), 0.004, (0, math.radians(-15), 0)),
        aco_esc,
    )
    # estepe na traseira (direita)
    perf = [
        (0.0, 0.09),
        (0.12, 0.09),
        (0.26, 0.08),
        (R_W, 0.07),
        (R_W, -0.07),
        (0.26, -0.09),
        (0.0, -0.09),
    ]
    est = B.torno_eixo("estepe", perf, "X", (XR - 0.03, -0.3, 0.84), 14)
    M.material(est, borr)
    B.pintar_por(est, lambda c, n: math.hypot(c.y + 0.3, c.z - 0.84) < 0.25, od)
    mt.geo(P, est, None)
    # eixos e diferenciais embaixo
    for xa in (X_FA, X_RA):
        mt.geo(P, B.cil("eixo", (xa, -Y_W + 0.09, Z_W), (xa, Y_W - 0.09, Z_W), 0.035, 8), aco)
        mt.geo(
            P,
            M.torno("dif", [(0.0, -0.1), (0.12, -0.1), (0.13, 0.0), (0.12, 0.1), (0.0, 0.1)], 10),
            aco,
        )
        M.mover(
            mt.partes[P]["geo"][-1],
            Matrix.Translation((xa, 0, Z_W)) @ Matrix.Rotation(math.pi / 2, 4, "X"),
        )
    # marcação no capô (lados): registro (estilo dos caminhões; PLACEHOLDER para jipe)
    mt.atlas(P, "a")

    P = "Volante"
    v = M.toro("volante", 0.2, 0.014, 20, 6)
    M.mover(v, Matrix.Translation(VOL) @ Matrix.Rotation(math.radians(-58), 4, "Y"))
    mt.geo(P, v, aco_esc)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        p1 = VOL + (
            Matrix.Rotation(math.radians(-58), 3, "Y")
            @ Vector((0.19 * math.cos(a), 0.19 * math.sin(a), 0))
        )
        mt.geo(P, B.cil("raio", tuple(VOL), tuple(p1), 0.01, 6), aco_esc)
    mt.pivo(P, tuple(VOL))
    mt.atlas(P, "a")

    def roda(x, y):
        perf = [
            (0.0, L_W / 2 + 0.01),
            (0.07, L_W / 2 + 0.01),
            (0.2, L_W / 2),
            (0.26, L_W / 2 + 0.005),
            (R_W - 0.02, L_W / 2),
            (R_W, L_W / 2 - 0.03),
            (R_W, -L_W / 2 + 0.03),
            (R_W - 0.02, -L_W / 2),
            (0.2, -L_W / 2),
            (0.0, -L_W / 2),
        ]
        o = B.torno_eixo("roda", perf, "Y", (x, y, Z_W), 18)
        M.material(o, borr)
        B.pintar_por(o, lambda c, n: math.hypot(c.x - x, c.z - Z_W) < 0.25, od)
        return o

    P = "Roda_FE"
    mt.geo(P, roda(X_FA, Y_W), None)
    pf = B.Lote("porcas")
    for k in range(5):
        a = 2 * math.pi * k / 5
        pf.cil(
            0.012,
            0.02,
            Matrix.Translation(
                (X_FA + 0.09 * math.cos(a), Y_W + L_W / 2 + 0.008, Z_W + 0.09 * math.sin(a))
            )
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
            6,
        )
    mt.det(P, pf.objeto(), aco)
    mt.pivo(P, (X_FA, Y_W, Z_W))
    mt.atlas(P, "a")
    mt.instancia("Roda_FD", "Roda_FE", (X_FA, -Y_W, Z_W), giro_z180=True)
    mt.instancia("Roda_TE", "Roda_FE", (X_RA, Y_W, Z_W))
    mt.instancia("Roda_TD", "Roda_FE", (X_RA, -Y_W, Z_W), giro_z180=True)

    info = {
        "nome": "M151 MUTT 1/4 t (USMC)",
        "faccao": "US",
        "medidas": MEDIDAS,
        "olhos": {
            "driver": (-0.08, 0.36, 1.48),
            "passenger": (-0.08, -0.36, 1.48),
        },
        "passageiros": {"x0": -1.0, "dx": 0.5, "y": 0.36, "z": 1.5},
        "assentos_z": {"driver": 0.77, "passenger": 0.77},
        "rodas": {"Roda_FE": (X_FA, Y_W, Z_W, R_W), "Roda_TE": (X_RA, Y_W, Z_W, R_W)},
        "antigo_placeholder": {"rotulo": "HOJE: não existe no jogo (boneco de 1,75 m p/ escala)"},
        "notas": [
            "Motorista à esquerda (y +), carona à direita; 2 lugares atrás (p1, p2).",
            "Volante separado (pivô no cubo, eixo da coluna inclinado 58° da horizontal).",
            "Rodas da frente esterçam em volta do eixo vertical pelo centro da roda (pivô).",
        ],
    }
    return mt, info
