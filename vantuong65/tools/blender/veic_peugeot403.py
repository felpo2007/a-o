"""Peugeot 403 camionnette bâchée (picape com lona) requisitada pelo Vietcong, em partes.

Carroceria "pontão" de linhas arredondadas, grade oval e faróis redondos nos para-lamas,
para-choques cromados foscos, cabine de 2 lugares, caçamba com lona sobre os arcos (aba de trás
enrolada) e folhas de palmeira por cima (camuflagem). Pintura civil desbotada, poeira, ferrugem.
Partes: Casco, Volante, Porta_E (motorista, volante à esquerda), Porta_D (carona), Tampa_Traseira,
Roda_FE, Roda_FD, Roda_TE, Roda_TD (F/T = frente/trás, E/D = esquerda/direita).
"""

from __future__ import annotations

import math

import bmesh
import modelar as M
import novos as N
import veic_base as B
from mathutils import Matrix, Vector
from modelar import Mat, rgb

WKE = "https://en.wikipedia.org/wiki/Peugeot_403"
WKF = "https://fr.wikipedia.org/wiki/Peugeot_403"
MEDIDAS = {
    "escolha": [
        None,
        "Peugeot 403: em produção em 1965 e com picape (camionnette bâchée) desde "
        f"out/1956 ({WKF}); um 403 do Museu da Cidade de Ho Chi Minh 'levava líderes "
        "comunistas em Saigon e províncias vizinhas de 1962 a 1970' (saigontr.blogspot.com/"
        "2014/04/historic-vehicles-of-saigon.html). Uso no Quảng Ngãi em 1965 e "
        "requisição pelo VC: sem fonte (o VC usava carregadores, bicicletas e sampanas; a "
        "CIA cita 'ocasionalmente veículos modernos')",
    ],
    "comprimento_m": [
        4.61,
        f"perua/familiale ({WKE}); as medidas da picape não foram achadas: PLACEHOLDER",
    ],
    "entre_eixos_m": [2.90, f"perua/familiale ({WKE}); PLACEHOLDER para a picape"],
    "largura_m": [1.67, f"berlina ({WKE})"],
    "altura_cabine_m": [1.51, f"berlina ({WKE})"],
    "altura_lona_m": [1.80, "PLACEHOLDER"],
    "pneu_diametro_m": [0.64, "PLACEHOLDER (sem fonte)"],
    "bitola_m": [1.35, "PLACEHOLDER (sem fonte)"],
    "cor": [
        None,
        "PLACEHOLDER: cinza-azulado civil desbotado; folhas de palmeira por cima da lona "
        "(camuflagem contra avião) sem fonte",
    ],
}

XF, XR = 4.61 / 2, -4.61 / 2
X_FA = XF - 0.75
X_RA = X_FA - 2.90
Y_W, R_W, L_W = 1.35 / 2, 0.32, 0.165
Z_W = R_W
YB = 1.67 / 2
Z_SILL, Z_BELT = 0.34, 0.93
X_CAB0, X_COWL = -0.28, 0.86
VOL = Vector((0.42, 0.38, 1.0))


def lona(nome, x0, x1, meia, z0, h, arcos, n=14, folga=0.0):
    """Lona da caçamba: arcos (meia superelipse) de x0 a x1, caída entre eles; frente fechada."""
    xs = sorted(
        set(
            [x0, x1]
            + list(arcos)
            + [(a + b) / 2 for a, b in zip(sorted(arcos)[:-1], sorted(arcos)[1:], strict=True)]
        )
    )
    bm = bmesh.new()
    aneis = []
    for x in xs:
        sag = 0.0 if any(abs(x - a) < 1e-6 for a in arcos) or x in (x0, x1) else 0.035
        anel = []
        for k in range(n + 1):
            t = math.pi * k / n
            c, s = math.cos(t), math.sin(t)
            y = (meia - folga) * math.copysign(abs(c) ** (2 / 3.2), c)
            z = z0 + (h - folga) * abs(s) ** (2 / 3.2)
            fator = 1 - sag * min(1.0, s * 1.4)
            anel.append(bm.verts.new((x, y * (1 - sag * 0.4 * s), z0 + (z - z0) * fator)))
        aneis.append(anel)
    for a, b in zip(aneis[:-1], aneis[1:], strict=True):
        for k in range(n):
            bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
    ifr = max(range(len(xs)), key=lambda i: xs[i])
    c = bm.verts.new((xs[ifr], 0.0, z0))
    for k in range(n):
        bm.faces.new((aneis[ifr][k], aneis[ifr][k + 1], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return B.de_bm(nome, bm, normais=False)


def receita():
    mt = B.Montagem()
    tinta = mt.mat(
        "pintura",
        B.mat_pintura,
        "#8c9597",
        "#b5bab5",
        "#a38a68",
        "#6e4a32",
        0.75,
        1.0,
        0.85,
        0.0,
        1.4,
        1.3,
        None,
        0.5,
    )
    cromo = mt.mat("cromo", B.mat_aco_sujo, "#9c9a92", "#6e4a32", 0.5, 0.32, True)
    lona_m = mt.mat("lona", B.mat_lona, "#837a56", "#a19670", 0.7)
    interior = mt.mat("interior", B.mat_simples, "#3b3a34", 0.8, 0.0)
    banco = mt.mat("banco", B.mat_simples, "#5a4634", 0.7, 0.0)
    vidro = mt.mat("vidro", B.mat_vidro, "#26303a", 0.06)
    borr = mt.mat("borracha", B.mat_borracha, z_lama=0.45)
    aco = mt.mat("aco", B.mat_aco_sujo, z_lama=0.6)
    lente_v = mt.mat("lente_vermelha", B.mat_simples, "#6a1e14", 0.25, 0.0)
    corda = mt.mat("corda", N.mat_corda, "#8d7c56")
    folha = Mat("folha_palmeira", rug=0.7)
    p = folha.coord("objeto")
    folha.cor(
        folha.misturar(
            folha.faixa(folha.ruido(p, 3.0, 4), 0.35, 0.7), rgb("#5d6b2c"), rgb("#9a8d4a")
        )
    )
    folha.relevo(folha.onda(p, 2 * math.pi / (20 * 0.01), "X"), 0.2, 0.001)
    folha = folha.m

    P = "Casco"
    # corpo de baixo (frente e cabine) com os recortes das rodas da frente, cantos arredondados
    perfil = [
        (X_CAB0, Z_SILL),
        (XF - 0.08, Z_SILL),
        (XF, 0.5),
        (XF - 0.03, 0.72),
        (XF - 0.2, 0.86),
        (X_COWL, Z_BELT),
        (X_CAB0, Z_BELT),
    ]
    perfil = B.perfil_com_arcos(perfil, [(X_FA, Z_W, R_W + 0.06)], 10)
    corpo = B.prisma("corpo", perfil, "Y", -YB, YB)
    M.chanfrar(corpo, 0.07, 3, 30.0)
    mt.geo(P, corpo, tinta, suave=40)
    # cabine (vidros pintados de vidro): para-brisa inclinado e caimento dos lados
    cab = B.prisma(
        "cabine",
        [
            (X_CAB0, Z_BELT - 0.01),
            (X_COWL, Z_BELT - 0.01),
            (0.5, 1.44),
            (-0.12, 1.49),
            (X_CAB0, 1.44),
        ],
        "Y",
        -YB + 0.03,
        YB - 0.03,
    )
    B.afinar(cab, Z_BELT, 0.2)
    M.chanfrar(cab, 0.05, 3, 30.0)
    M.material(cab, tinta)

    def janela(c, n):
        lado = abs(n.y) > 0.6 and 1.0 < c.z < 1.4 and -0.2 < c.x < 0.62
        frente = n.x > 0.45 and c.z > 0.99 and abs(c.y) < 0.68
        tras = n.x < -0.6 and c.z > 1.05 and abs(c.y) < 0.5
        return lado or frente or tras

    B.pintar_por(cab, janela, vidro)
    mt.geo(P, cab, None, suave=40)
    # interior visto pelos vidros (de dentro a cabine some: face única)
    mt.geo(P, B.caixa("painel", (0.25, 1.4, 0.18), (X_COWL - 0.15, 0, 0.98), 0.03), interior)
    mt.geo(P, B.caixa("banco", (0.5, 1.3, 0.14), (0.05, 0, 0.47), 0.04), banco)
    mt.geo(
        P,
        B.caixa("encosto", (0.12, 1.3, 0.5), (-0.18, 0, 0.9), 0.04, (0, math.radians(-12), 0)),
        banco,
    )
    mt.geo(P, B.cil("coluna", (X_COWL - 0.2, VOL.y, 0.92), tuple(VOL), 0.02, 8), interior)
    # caçamba: assoalho, laterais (com o recorte da roda de trás) e tampa
    mt.geo(
        P,
        B.caixa(
            "assoalho", (X_CAB0 - XR - 0.05, 2 * YB - 0.04, 0.04), ((X_CAB0 + XR) / 2, 0, 0.55), 0.0
        ),
        tinta,
    )
    lado_c = B.perfil_com_arcos(
        [(XR + 0.02, 0.4), (X_CAB0, 0.4), (X_CAB0, Z_BELT), (XR + 0.02, Z_BELT)],
        [(X_RA, Z_W, R_W + 0.06)],
        10,
    )
    for s in (1, -1):
        lc = B.prisma("lateral", lado_c, "Y", s * (YB - 0.035), s * YB)
        M.chanfrar(lc, 0.012, 1, 30.0)
        mt.geo(P, lc, tinta)
        mt.geo(
            P,
            B.cil("farol", (XF - 0.12, s * 0.6, 0.74), (XF - 0.02, s * 0.6, 0.74), 0.09, 14),
            cromo,
        )
        mt.geo(
            P,
            B.cil("lente", (XF - 0.02, s * 0.6, 0.74), (XF - 0.012, s * 0.6, 0.74), 0.075, 14),
            vidro,
        )
        mt.geo(P, B.caixa("lanterna", (0.04, 0.1, 0.12), (XR + 0.03, s * 0.72, 0.8), 0.01), cromo)
        mt.det(P, B.caixa("lente_t", (0.01, 0.07, 0.08), (XR + 0.008, s * 0.72, 0.8)), lente_v)
        mt.geo(P, B.caixa("garra", (0.06, 0.06, 0.16), (XF + 0.02, s * 0.35, 0.44), 0.015), cromo)
        mt.geo(
            P,
            B.caixa("espelho", (0.04, 0.12, 0.08), (X_COWL - 0.05, s * (YB + 0.06), 1.07), 0.01),
            cromo,
        )
        # porta (chapa de baixo; a janela fica na cabine): dobradiça na frente, eixo vertical
        nome = "Porta_E" if s > 0 else "Porta_D"
        porta = B.caixa("porta", (1.0, 0.03, 0.44), (0.31, s * (YB + 0.013), 0.645), 0.012)
        mt.geo(nome, porta, tinta)
        mt.geo(
            nome,
            B.caixa("macaneta", (0.1, 0.02, 0.025), (-0.1, s * (YB + 0.035), 0.82), 0.004),
            cromo,
        )
        mt.pivo(nome, (0.81, s * (YB + 0.013), 0.645))
        mt.atlas(nome, "a")
    mt.geo(
        "Tampa_Traseira",
        B.caixa("tampa", (0.035, 2 * YB - 0.06, 0.4), (XR + 0.02, 0, 0.73), 0.01),
        tinta,
    )
    mt.pivo("Tampa_Traseira", (XR + 0.02, 0, 0.55))  # abre para baixo
    mt.atlas("Tampa_Traseira", "a")
    # grade oval, para-choques
    grade = M.toro("grade", 0.3, 0.035, 20, 6)
    M.mover(
        grade,
        Matrix.Translation((XF - 0.02, 0, 0.6))
        @ Matrix.Diagonal((1.0, 1.0, 0.35, 1.0))
        @ Matrix.Rotation(math.pi / 2, 4, "Y"),
    )
    mt.geo(P, grade, cromo)
    g = B.Lote("barras")
    for k in range(4):
        g.caixa((0.02, 0.56, 0.018), Matrix.Translation((XF - 0.035, 0, 0.55 + k * 0.035)))
    mt.det(P, g.objeto(), cromo)
    mt.geo(P, B.caixa("parachoque", (0.08, 1.72, 0.1), (XF + 0.03, 0, 0.42), 0.035, segs=2), cromo)
    mt.geo(P, B.caixa("parachoque_t", (0.08, 1.7, 0.1), (XR - 0.02, 0, 0.45), 0.035, segs=2), cromo)
    mt.geo(P, B.caixa("placa", (0.01, 0.42, 0.11), (XF + 0.075, 0, 0.42), 0.0), interior)
    # lona da caçamba (dupla: por dentro também, a aba de trás aberta) e a aba enrolada
    arcos = [X_CAB0 - 0.08, -1.0, -1.65, XR + 0.08]
    for nome, folga in (("lona", 0.0), ("lona_dentro", 0.012)):
        o = lona(nome, XR + 0.06, X_CAB0 - 0.03, YB - 0.01, Z_BELT, 0.88, arcos, 16, folga)
        if folga:
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
            bm.to_mesh(o.data)
            bm.free()
        else:
            M.deslocar(o, lambda co, n: 0.01 * M.fbm(co * 5, 3, 81))
        mt.geo(P, o, lona_m, suave=60)
    rolo = B.cil(
        "aba",
        (XR + 0.08, -YB + 0.05, Z_BELT + 0.82),
        (XR + 0.08, YB - 0.05, Z_BELT + 0.82),
        0.07,
        10,
    )
    M.deslocar(rolo, lambda co, n: 0.01 * M.fbm(co * 6, 3, 82))
    mt.geo(P, rolo, lona_m)
    for s in (1, -1):
        cordao = [(xx, s * (YB + 0.005), Z_BELT + 0.03) for xx in (XR + 0.1, -1.3, X_CAB0 - 0.05)]
        mt.det(P, M.tubo("cordao", cordao, 0.008, 4, False), corda)
    # folhas de palmeira por cima (uma face, virada para cima: com duas camadas coladas o bake de
    # uma achava a outra e as folhas saíam pretas)
    for i, (x0, ang) in enumerate(
        ((-0.9, 0.1), (-1.7, -0.08), (-0.6, 3.05))
    ):  # dentro da largura (o centro da caixa fica no eixo do carro)
        bm = bmesh.new()
        eixo = Vector((math.cos(ang), math.sin(ang), 0))
        lado = Vector((-math.sin(ang), math.cos(ang), 0))
        base = Vector((x0, -0.3 + 0.25 * i, Z_BELT + 0.9))
        for k in range(10):
            t = k / 10
            c = base + eixo * (0.15 + t * 1.3) + Vector((0, 0, -0.25 * t * t))
            for sg in (1, -1):
                ponta = c + lado * sg * (0.35 * (1 - t * 0.6)) + eixo * 0.12 + Vector((0, 0, -0.12))
                v = [bm.verts.new(c), bm.verts.new(c + eixo * 0.07), bm.verts.new(ponta)]
                f = bm.faces.new(v)
                f.normal_update()
                if f.normal.z < 0:
                    f.normal_flip()
        o = B.de_bm(f"palma{i}", bm, normais=False)
        mt.geo(P, o, folha, suave=70)
        mt.geo(
            P,
            B.cil("talo", tuple(base), tuple(base + eixo * 1.5 + Vector((0, 0, -0.35))), 0.012, 5),
            folha,
        )
    # eixos e escapamento
    for xa in (X_FA, X_RA):
        mt.geo(P, B.cil("eixo", (xa, -Y_W + 0.08, Z_W), (xa, Y_W - 0.08, Z_W), 0.03, 8), aco)
    mt.geo(P, B.cil("escape", (0.6, -0.4, 0.25), (XR + 0.05, -0.45, 0.28), 0.025, 6), aco)
    mt.sem_limpeza(P)
    mt.atlas(P, "a")

    P = "Volante"
    v = M.toro("volante", 0.2, 0.012, 20, 6)
    M.mover(v, Matrix.Translation(VOL) @ Matrix.Rotation(math.radians(-55), 4, "Y"))
    mt.geo(P, v, interior)
    for k in range(2):
        a = math.radians(180 * k)
        p1 = VOL + (
            Matrix.Rotation(math.radians(-55), 3, "Y")
            @ Vector((0.19 * math.cos(a), 0.19 * math.sin(a), 0))
        )
        mt.geo(P, B.cil("raio", tuple(VOL), tuple(p1), 0.009, 6), interior)
    mt.pivo(P, tuple(VOL))
    mt.atlas(P, "a")

    P = "Roda_FE"
    perf = [
        (0.0, L_W / 2 + 0.01),
        (0.1, L_W / 2 + 0.015),
        (0.18, L_W / 2),
        (R_W - 0.03, L_W / 2),
        (R_W, L_W / 2 - 0.035),
        (R_W, -L_W / 2 + 0.035),
        (R_W - 0.03, -L_W / 2),
        (0.18, -L_W / 2),
        (0.0, -L_W / 2),
    ]
    o = B.torno_eixo("roda", perf, "Y", (X_FA, Y_W, Z_W), 18)
    M.material(o, borr)
    B.pintar_por(o, lambda c, n: math.hypot(c.x - X_FA, c.z - Z_W) < 0.12, cromo)
    B.pintar_por(o, lambda c, n: 0.12 <= math.hypot(c.x - X_FA, c.z - Z_W) < 0.2, tinta)
    mt.geo(P, o, None)
    mt.pivo(P, (X_FA, Y_W, Z_W))
    mt.atlas(P, "a")
    mt.instancia("Roda_FD", "Roda_FE", (X_FA, -Y_W, Z_W), giro_z180=True)
    mt.instancia("Roda_TE", "Roda_FE", (X_RA, Y_W, Z_W))
    mt.instancia("Roda_TD", "Roda_FE", (X_RA, -Y_W, Z_W), giro_z180=True)

    info = {
        "nome": "Peugeot 403 camionnette bâchée (VC, requisitada)",
        "faccao": "VC",
        "medidas": MEDIDAS,
        "olhos": {"driver": (0.12, 0.38, 1.33), "passenger": (0.12, -0.38, 1.33)},
        "assentos_z": {"driver": 0.54, "passenger": 0.54},
        "passageiros": {"x0": -0.75, "dx": 0.5, "y": 0.5, "z": 1.42},
        "antigo_placeholder": {"rotulo": "HOJE: não existe no jogo (boneco de 1,75 m p/ escala)"},
        "notas": [
            "Volante à esquerda (carro francês). 6 lugares na caçamba, sob a lona "
            "(3 de cada lado).",
            "A cabine é casca de face única: de dentro, o motorista vê o painel, o volante "
            "e o capô.",
        ],
    }
    return mt, info
