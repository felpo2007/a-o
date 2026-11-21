"""UH-34D Seahorse dos esquadrões HMM-261/361 (MAG-16), Starlite, agosto de 1965 (v3, D-199).

Motor radial no nariz (portas em concha e a grade de ar na frente), cabine dos pilotos alta, por
cima e atrás do motor, com para-brisa e janelas de vidro (nó Vidro: o jogo deixa transparente) e
molduras; atrás dela a carenagem da transmissão com o mastro curto e as venezianas descendo para o
teto do porão. Porão da tropa com a porta de correr da direita aberta e o lado esquerdo aberto
(D-113), bancos de lona, cavernas, a M60 da porta. Cone de cauda fundo e estreito que sobe na
deriva inclinada, com o rotor de cauda de 4 pás à esquerda e o estabilizador à direita. Trem
principal com o amortecedor longo até o nariz e o V até a barriga; bequilha bem atrás, sob o cone.

Perfil, planta e frente medidos por código (contorno por coluna de pixels) no desenho de três
vistas do UH-34D em the-blueprints.com (sikorsky_s_58_uh_34d_choctaw-33517), na escala do
comprimento da fuselagem (14,25 m: 0,0559 m por pixel), com o cubo em x = 3,6 m.

Partes: Casco (casca da frente, forros, molduras, trem e detalhes de fora), Interior (cabine,
porão, bancos, painel, comandos, M60), Vidro, Cauda (cone, deriva, estabilizador, bequilha),
RotorPrincipal (cubo, braços, articulações e hastes) com as pás Pa_1..Pa_4 (uma malha, 4 nós
girados 90°: soldar no cubo), RotorCauda (caixa, cubo e 4 pás), Roda_E, Roda_D, Roda_Cauda,
Escotilha_Porta (porta de correr, aberta para trás).
"""

from __future__ import annotations

import math

import bmesh
import modelar as M
import veic_base as B
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

FI = "https://www.flugzeuginfo.net/acdata_php/acdata_s58_en.php"
SA = "https://sikorskyarchives.com/?p=4968"
TB = "https://the-blueprints.com/blueprints/helicopters/sikorsky/33517/view/sikorsky_s-58_uh-34d_choctaw"
MEDIDAS = {
    "comprimento_fuselagem_m": [
        14.25,
        f"flugzeuginfo e Sikorsky Archives: 46 ft 9 in ({FI}; "
        f"{SA}); a Wikipedia dá 47 ft 2 in (14,38 m)",
    ],
    "rotor_principal_diametro_m": [17.07, f"flugzeuginfo: 56 ft, 4 pás ({FI})"],
    "rotor_cauda_diametro_m": [2.90, f"flugzeuginfo: 9 ft 6 in, 4 pás ({FI})"],
    "perfil_pa": [
        None,
        "NACA 0012 nas pás do rotor principal e do de cauda (Army Aviation Magazine, "
        "armyaviationmagazine.com/ch-34-choctaw; Sikorsky Archives). Corda de 0,41 m: "
        "PLACEHOLDER (sem fonte)",
    ],
    "altura_cubo_m": [
        4.53,
        f"topo do cubo medido no desenho ({TB}): 4,53 m; a Wikipedia dá 14 ft 3,5 in "
        "(4,36 m) de altura; flugzeuginfo e Sikorsky, 15 ft 11 in (4,85 m)",
    ],
    "silhueta": [
        None,
        f"perfil (topo e base por coluna), planta e frente medidos por código no desenho de "
        f"três vistas ({TB}), escala do comprimento da fuselagem: cabine alta (teto a 3,86 m; "
        "no modelo 4,08 m, para o soldado R15 sentado caber), "
        "carenagem até o mastro, cone fundo e estreito, deriva inclinada, rotor de cauda a "
        "3,83 m e 0,55 m à esquerda, roda principal em x = 5,03 m (Ø 0,76 m) e bequilha em "
        "x = -3,92 m",
    ],
    "bitola_trem_m": [
        4.27,
        "NATOPS citado em popasmoke.com/notam/aircraft-38/uh-34d-shipboad-"
        "folded: 14 ft no trem de perna em V (12 ft no de perna curva; o desenho mostra ~12 ft)",
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
    "ponta_das_pas": [
        None,
        "faixa laranja-amarela nos 6 in de fora (popasmoke, marine-helicopter-colors, pelo "
        "resumo da busca: a página não abriu). Cor da pá: PLACEHOLDER (escura)",
    ],
    "marcas": [
        None,
        "'YN' = HMM-361 (en.wikipedia.org/wiki/HMH-361); BuNo 150570 'YN-19' voou "
        "na Starlite (usmcmuseum.com/sikorsky-uh-34d.html). Posição de 'MARINES' e da "
        "insígnia nacional no cone: PLACEHOLDER (sem fonte textual)",
    ],
    "rodas_m": [None, "roda principal Ø 0,76 m e bequilha Ø 0,40 m, medidas no desenho"],
}

N_ANEL = 48
# (x, topo, base, meia largura, meia largura no topo, expoente): medidos no desenho (ver MEDIDAS)
ESTACOES = [
    (7.40, 1.88, 1.50, 0.22, 0.20, 2.0),
    (7.35, 1.98, 1.28, 0.42, 0.38, 2.1),
    (7.29, 2.08, 1.20, 0.55, 0.48, 2.2),
    (7.18, 2.25, 1.02, 0.68, 0.58, 2.3),
    (7.04, 2.42, 0.88, 0.77, 0.64, 2.5),
    (6.84, 2.63, 0.78, 0.83, 0.66, 2.7),
    (6.62, 2.79, 0.73, 0.86, 0.65, 2.9),
    (6.35, 2.93, 0.69, 0.88, 0.63, 3.1),
    (6.05, 3.10, 0.67, 0.88, 0.62, 3.5),
    (5.79, 3.35, 0.66, 0.88, 0.62, 4.0),
    # cabine 0,22 m mais alta que o desenho (3,86 m): o soldado R15 sentado tem o capacete 1,6 m
    # acima do assento (Studio, D-199) e não cabia
    (5.56, 3.66, 0.65, 0.88, 0.64, 4.5),
    (5.38, 3.90, 0.65, 0.88, 0.66, 4.5),
    (5.15, 4.04, 0.65, 0.88, 0.66, 4.5),
    (4.75, 4.08, 0.65, 0.88, 0.66, 4.5),
    (4.25, 4.06, 0.65, 0.88, 0.66, 4.5),
    (3.60, 3.92, 0.65, 0.88, 0.65, 4.5),
    (2.95, 3.84, 0.65, 0.88, 0.64, 4.5),
    (2.48, 3.78, 0.66, 0.88, 0.64, 4.5),
    (2.10, 3.66, 0.68, 0.88, 0.62, 4.5),
    (1.70, 3.50, 0.71, 0.88, 0.60, 4.3),
    (1.30, 3.30, 0.74, 0.87, 0.58, 3.8),
    (0.95, 3.04, 0.77, 0.84, 0.55, 3.2),
]
ESTACOES_CAUDA = [
    (0.95, 3.04, 0.77, 0.84, 0.55, 3.2),
    (0.55, 2.90, 0.81, 0.76, 0.52, 2.9),
    (0.10, 2.85, 0.84, 0.64, 0.46, 2.7),
    (-0.50, 2.80, 0.89, 0.50, 0.40, 2.6),
    (-1.20, 2.70, 0.92, 0.42, 0.36, 2.5),
    (-2.20, 2.55, 0.95, 0.36, 0.31, 2.4),
    (-3.20, 2.41, 1.00, 0.32, 0.28, 2.4),
    (-3.90, 2.30, 1.06, 0.29, 0.26, 2.4),
    (-4.40, 2.24, 1.17, 0.28, 0.25, 2.4),
]
# deriva (x, z), sentido anti-horário: raiz, bordo de ataque, topo (caixa do rotor de cauda) e o
# bordo de fuga, que continua a base do cone subindo
DERIVA = [
    (-4.30, 1.12),
    (-4.30, 2.26),
    (-4.60, 2.38),
    (-5.23, 2.91),
    (-5.68, 3.35),
    (-5.95, 3.72),
    (-6.15, 3.98),
    (-6.45, 4.08),
    (-6.80, 4.02),
    (-6.95, 3.78),
    (-6.60, 3.05),
    (-6.30, 2.68),
    (-5.90, 2.35),
    (-5.46, 2.01),
    (-5.01, 1.62),
    (-4.73, 1.34),
    (-4.45, 1.16),
]
HUB = Vector((3.6, 0.0, 4.39))
TAIL = Vector((-6.50, 0.55, 3.83))
R_ROT, R_CAUDA = 17.07 / 2, 2.90 / 2
CORDA, CORDA_C = 0.41, 0.19
WHEEL = Vector((5.03, 4.27 / 2, 0.38))
R_RODA = 0.38
TWHEEL = Vector((-3.92, 0.0, 0.20))
PORTA = (2.95, 4.25)  # x da abertura da direita
PORTA_E = (2.15, 4.25)  # x da abertura da esquerda (v45, liberdade de jogo)
PORTA_Z = (1.00, 2.20)
PISO_CAB = 2.48  # piso da cabine dos pilotos
FOSSO = 2.08  # fundo do fosso dos pedais
TETO_PORAO = 2.82  # teto do porão atrás da cabine
X_ANTEPARA_F, X_ANTEPARA_T, X_PAREDE_CAB = 5.38, 1.45, 4.18
OLHO_PILOTO = (4.85, 0.42, 3.57)
ASSENTO_Z = 2.58


# ================================================================ geometria
def anel(x, top, bot, w, wt, e, n=N_ANEL):
    """Seção superelíptica com a parte de cima mais estreita (a cabine e a carenagem sobre o
    porão): acima do ombro, a largura cai até `wt` no topo."""
    zc, h = (top + bot) / 2, (top - bot) / 2
    z_ombro = zc + 0.2 * h
    out = []
    for k in range(n):
        t = 2 * math.pi * k / n
        c, s = math.cos(t), math.sin(t)
        y = w * math.copysign(abs(c) ** (2 / e), c)
        z = zc + h * math.copysign(abs(s) ** (2 / e), s)
        u = max(0.0, min(1.0, (z - z_ombro) / max(1e-6, top - z_ombro)))
        y *= 1 + (wt / w - 1) * u**1.5
        out.append((x, y, z))
    return out


def fuselagem(nome, estacoes, tampa0, tampa1):
    return B.loft(nome, [anel(*e) for e in estacoes], tampa0, tampa1)


def cortar(obj, planos):
    """Corta a malha nos planos [(ponto, normal, filtro(centro))]: a borda das janelas e das
    portas fica reta. Só as faces do filtro são cortadas."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for co, no, filtro in planos:
        faces = [f for f in bm.faces if filtro(f.calc_center_median())]
        if not faces:
            continue
        geo = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges})
        geo += faces
        bmesh.ops.bisect_plane(bm, geom=geo, plane_co=Vector(co), plane_no=Vector(no), dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def separar(obj, cond, nome):
    """Tira do `obj` as faces cond(centro, normal) e devolve-as num objeto novo."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    sel = [f for f in bm.faces if cond(f.calc_center_median(), f.normal)]
    bm2 = bmesh.new()
    mapa = {}
    for f in sel:
        vs = []
        for v in f.verts:
            if v not in mapa:
                mapa[v] = bm2.verts.new(v.co)
            vs.append(mapa[v])
        bm2.faces.new(vs)
    bmesh.ops.delete(bm, geom=sel, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return B.de_bm(nome, bm2, normais=False)


def moldura(obj, cond, larg, esp, nome):
    """Perfil de moldura nas bordas abertas do casco (janela, porta) em que cond(meio): uma
    barra por aresta, saliente `esp` pela normal da face."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    lote = B.Lote(nome)
    for e in bm.edges:
        if len(e.link_faces) != 1:
            continue
        a, b = e.verts[0].co, e.verts[1].co
        meio = (a + b) / 2
        if not cond(meio):
            continue
        d = b - a
        comp = d.length
        if comp < 1e-4:
            continue
        d.normalize()
        n = e.link_faces[0].normal.copy()
        lado = n.cross(d).normalized()
        n = d.cross(lado).normalized()
        m = B.quadro(meio + n * (esp * 0.3), d, lado, n)
        lote.caixa((comp + larg * 0.6, larg, esp), m)
    bm.free()
    return lote.objeto()


def bvh_de(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def na_pele(bvh, pts, d, afasta=0.008):
    """Projeta os pontos na superfície vindo de fora pela direção `d` (unitária)."""
    out = []
    for p in pts:
        p = Vector(p)
        hit = bvh.ray_cast(p - d * 3.0, d, 6.0)
        if hit[0] is None:
            out.append(p)
        else:
            out.append(hit[0] - d * afasta)
    return out


def aerofolio(nome, estacoes, eixo_u, eixo_v, centro, corda_lado=1.0):
    """Pá com seção NACA 0012. `estacoes` = [(r, corda, esp_rel, z)], ao longo de `eixo_u`
    (radial) a partir de `centro`; a corda fica em `eixo_v` (bordo de ataque para +v), a
    espessura em u x v. Ponta fechada."""
    xs = [0.0, 0.025, 0.08, 0.2, 0.38, 0.6, 0.82, 1.0]

    def meia(x, t):
        return (
            5
            * t
            * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x**2 + 0.2843 * x**3 - 0.1036 * x**4)
        )

    u = Vector(eixo_u).normalized()
    v = Vector(eixo_v).normalized() * corda_lado
    w = u.cross(v).normalized()
    aneis = []
    for r, c, t, dz in estacoes:
        base = Vector(centro) + u * r + Vector((0, 0, dz))
        sec = []
        for x in xs:  # de cima, do ataque ao fuga
            sec.append(base + v * (c * (0.3 - x)) + w * (meia(x, t) * c))
        for x in reversed(xs[1:-1]):  # de baixo, do fuga ao ataque
            sec.append(base + v * (c * (0.3 - x)) - w * (meia(x, t) * c))
        aneis.append(sec)
    return B.loft(nome, aneis, True, True)


def disco_dist(c, centro):
    return math.hypot(c.x - centro.x, c.y - centro.y)


def estacao_em(x, estacoes=ESTACOES):
    for a, b in zip(estacoes, estacoes[1:], strict=False):
        if a[0] >= x >= b[0]:
            t = (a[0] - x) / (a[0] - b[0])
            return (x, *(a[i] + (b[i] - a[i]) * t for i in range(1, 6)))
    raise ValueError(f"x fora das estações: {x}")


def parede(nome, x, z0, z1, esp, folga=0.03):
    """Antepara na seção do casco em `x`, entre z0 e z1 (chapa de espessura `esp`), recolhida
    `folga` m para dentro: não vaza nos cantos arredondados."""
    st = estacao_em(x)
    w = st[3]
    pts = []
    for _, y, z in anel(*st):
        pts.append((y * (1 - folga / w), min(max(z, z0), z1)))
    return B.prisma(nome, pts, "X", x - esp / 2, x + esp / 2)


def colar(obj, bvh, d, afasta):
    """Decalque: leva cada vértice até a pele (raio de fora pela direção `d`), `afasta` m acima."""
    d = Vector(d).normalized()
    for v in obj.data.vertices:
        hit = bvh.ray_cast(v.co - d * 1.5, d, 3.0)
        if hit[0] is not None:
            v.co = hit[0] - d * afasta
    obj.data.update()
    return obj


def chapa(nome, pts, s, centro=None):
    """Chapa plana no plano XZ (y = 0) para colar no lado `s` (+1 esquerda, -1 direita): leque
    a partir de `centro` (x, z) ou um n-gono."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, 0.0, z)) for x, z in pts]
    if centro is not None:
        c = bm.verts.new((centro[0], 0.0, centro[1]))
        for i in range(len(vs)):
            tri = [c, vs[i], vs[(i + 1) % len(vs)]]
            bm.faces.new(tri if s < 0 else list(reversed(tri)))
    else:
        bm.faces.new(vs if s < 0 else list(reversed(vs)))
    return B.de_bm(nome, bm, normais=False)


def ret(nome, x0, x1, z0, z1, s, nx=8, nz=2):
    """Retângulo em grade (para colar acompanhando a curva da pele)."""
    bm = bmesh.new()
    g = [
        [
            bm.verts.new((x0 + (x1 - x0) * i / nx, 0.0, z0 + (z1 - z0) * j / nz))
            for j in range(nz + 1)
        ]
        for i in range(nx + 1)
    ]
    for i in range(nx):
        for j in range(nz):
            q = [g[i][j], g[i + 1][j], g[i + 1][j + 1], g[i][j + 1]]
            bm.faces.new(q if s < 0 else list(reversed(q)))
    return B.de_bm(nome, bm, normais=False)


# ================================================================ receita
def receita():
    mt = B.Montagem()
    verde = mt.mat("pintura", B.mat_aviao, fuligem=(6.3, 0.88, 1.0, 0.9), z_lama=0.55)
    verde_c = mt.mat("pintura_cauda", B.mat_aviao, z_lama=0.0)
    pa_m = mt.mat("pas", B.mat_aviao, "#2e3029", "#3d3f36", "#22231e", 3.0, 0.2, 0.25, 0.0)
    ponta = mt.mat("ponta_pa", B.mat_estencil, "#e0a42a", "#2e3029", 0.25)
    interior = mt.mat("interior", B.mat_simples, "#3d4433", 0.85, 0.0)
    interior_c = mt.mat("interior_claro", B.mat_simples, "#596049", 0.8, 0.0)
    piso = mt.mat("piso", B.mat_aco_sujo, "#3a3a33", z_lama=1.2)
    painel = mt.mat("painel", B.mat_simples, "#141413", 0.6, 0.0)
    mostrador = mt.mat("mostrador", B.mat_simples, "#c9c6b8", 0.4, 0.0)
    banco = mt.mat("banco", B.mat_lona, "#6a2a1e", "#8a3a28", 0.0)
    lona = mt.mat("lona", B.mat_lona, "#5f5d40", "#7d7656", 0.0)
    vidro = mt.mat("vidro", B.mat_vidro, "#2a3438", 0.1)
    aco = mt.mat("aco", B.mat_aco_sujo, z_lama=0.6, brilho_contato=True)
    aco_esc = mt.mat("aco_escuro", B.mat_simples, "#1e1d1a", 0.5, 0.6)
    borr = mt.mat("borracha", B.mat_borracha, z_lama=0.5)
    preto = mt.mat("letra_preta", B.mat_estencil, "#141412", "#4b5539", 0.3)
    branco = mt.mat("branco", B.mat_estencil, "#d8d6cc", "#4b5539", 0.25)
    azul = mt.mat("azul", B.mat_estencil, "#1f2c55", "#4b5539", 0.2)
    vermelho = mt.mat("vermelho", B.mat_estencil, "#9b2a22", "#4b5539", 0.2)
    luz_r = mt.mat("luz_vermelha", B.mat_simples, "#b3241a", 0.3, 0.0)
    luz_v = mt.mat("luz_verde", B.mat_simples, "#2f8a3a", 0.3, 0.0)
    extintor = mt.mat("extintor", B.mat_simples, "#9a2219", 0.5, 0.0)

    # ================================================================ CASCO (frente)
    P = "Casco"
    fus = fuselagem("fuselagem", ESTACOES, True, False)

    def zona_cab(c):
        return 4.1 < c.x < 6.7 and c.z > 2.6

    def zona_porta(c):
        return 1.9 < c.x < 4.5 and 0.6 < c.z < 2.5 and abs(c.y) > 0.4

    cortar(
        fus,
        [
            ((4.30, 0, 0), (1, 0, 0), zona_cab),
            ((5.32, 0, 0), (1, 0, 0), zona_cab),
            ((0, 0, 3.00), (0, 0, 1), zona_cab),
            ((0, 0, 3.86), (0, 0, 1), zona_cab),
            ((0, 0, 2.90), (0, 0, 1), zona_cab),
            ((PORTA[0], 0, 0), (1, 0, 0), zona_porta),
            ((PORTA[1], 0, 0), (1, 0, 0), zona_porta),
            ((PORTA_E[0], 0, 0), (1, 0, 0), zona_porta),
            ((0, 0, PORTA_Z[0]), (0, 0, 1), zona_porta),
            ((0, 0, PORTA_Z[1]), (0, 0, 1), zona_porta),
        ],
    )

    # a pele inteira (antes de abrir vidro e vãos) para projetar detalhes nela
    bvh = bvh_de(fus)

    def parabrisa(c, n):
        return c.x > 5.32 and c.z > 2.9 and n.x > 0.2

    def janela_lado(c, n):
        return 4.30 < c.x < 5.32 and 3.0 < c.z < 3.86 and abs(n.y) > 0.5

    # para-brisa de vidro; as janelas de correr dos pilotos ficam abertas (o vidro correu para
    # trás, por fora): quem está fora vê o piloto (liberdade de jogo)
    vid = separar(fus, parabrisa, "vidro_cab")
    z_porta = (PORTA_Z[0], PORTA_Z[1])

    def porta_d(c, n):
        return PORTA[0] < c.x < PORTA[1] and z_porta[0] < c.z < z_porta[1] and n.y < -0.5

    def porta_e(c, n):
        # v45 (D-113, pedido do dono): o porão da tropa aberto também à esquerda, para quem vai
        # sentado ver para fora e ser visto (o H-34 real tinha só janelas desse lado)
        return PORTA_E[0] < c.x < PORTA_E[1] and z_porta[0] < c.z < z_porta[1] and n.y > 0.5

    # a porta da direita sai do próprio casco: a mesma chapa, correndo para trás por fora
    folha = separar(fus, porta_d, "folha_porta")

    def reg_cabine(c, n):
        return X_PAREDE_CAB - 0.03 < c.x < 6.7 and c.z > PISO_CAB - 0.04

    def reg_porao(c, n):
        teto = TETO_PORAO if c.x < X_PAREDE_CAB else PISO_CAB
        return X_ANTEPARA_T - 0.05 < c.x < X_ANTEPARA_F + 0.04 and c.z < teto + 0.04

    forro1 = B.abrir_e_forrar(fus, reg_cabine, janela_lado, 0.012, "forro_cab")
    forro2 = B.abrir_e_forrar(fus, reg_porao, porta_e, 0.012, "forro_porao")
    # a moldura das janelas e das portas (bordas abertas, depois de tirar vidro e vão)
    mold = moldura(fus, lambda m: zona_cab(m) or zona_porta(m), 0.05, 0.035, "molduras")
    # nariz: a frente vira a grade de ar do motor (escura)
    M.material(fus, verde)
    B.pintar_por(fus, lambda c, n: c.x > 7.385 and n.x > 0.5, aco_esc)
    mt.geo(P, fus, None, suave=50)
    mt.geo(P, forro1, interior, suave=50)
    mt.geo(P, forro2, interior, suave=50)
    mt.geo(P, mold, verde, suave=30)
    # coluna do meio do para-brisa e a divisão da janela de correr dos pilotos
    pts = [(x, 0.0, top + 0.004) for x, top, *_ in ESTACOES if 5.34 < x < 6.34]
    pts = sorted(pts + [(5.32, 0.0, 3.76), (6.36, 0.0, 2.93)], key=lambda p: p[0])
    mt.geo(P, M.tubo("coluna", pts, 0.028, 6, True, 0.7), verde, suave=30)
    # grade do nariz (só textura): barras e anel
    g = B.Lote("grade")
    for k in range(-3, 4):
        g.caixa((0.02, 0.012, 0.3), Matrix.Translation((7.405, k * 0.045, 1.69)))
    for k in range(-3, 4):
        g.caixa((0.02, 0.3, 0.012), Matrix.Translation((7.405, 0, 1.69 + k * 0.045)))
    mt.det(P, g.objeto(), aco)
    mt.det(
        P,
        M.mover(
            M.toro("anel_grade", 0.17, 0.02, 24, 6), M.matriz((7.39, 0, 1.69), (0, math.pi / 2, 0))
        ),
        verde,
    )
    # carenagem do mastro (sobre a da transmissão), mastro e prato cíclico (fixo: só a parte de
    # baixo; as hastes giram com o cubo)
    car = M.torno(
        "carenagem", [(0.0, 3.86), (0.5, 3.86), (0.42, 3.98), (0.24, 4.07), (0.0, 4.1)], 20
    )
    M.mover(car, Matrix.Translation((HUB.x, 0, 0)))
    mt.geo(P, car, verde)
    mt.geo(P, B.cil("mastro", (HUB.x, 0, 4.05), (HUB.x, 0, HUB.z - 0.1), 0.11, 12), aco)
    prato = M.torno(
        "prato", [(0.0, 4.12), (0.27, 4.12), (0.28, 4.16), (0.12, 4.19), (0.0, 4.19)], 16
    )
    M.mover(prato, Matrix.Translation((HUB.x, 0, 0)))
    mt.geo(P, prato, aco)
    # venezianas da rampa atrás da carenagem (saída de ar do motor e do óleo)
    v = B.Lote("venezianas_topo")
    for k in range(9):
        x = 2.30 - k * 0.11
        v.caixa(
            (0.035, 0.75, 0.02),
            Matrix.Translation((x, 0, estacao_em(x)[1] + 0.006)) @ Matrix.Rotation(0.5, 4, "Y"),
        )
    mt.det(P, v.objeto(), aco_esc)
    # farol anticolisão vermelho no topo, antena de lâmina e luzes de posição na cabine
    mt.geo(
        P,
        B.cil(
            "farol",
            (2.55, 0, estacao_em(2.55)[1] - 0.02),
            (2.55, 0, estacao_em(2.55)[1] + 0.08),
            0.07,
            10,
        ),
        luz_r,
    )
    mt.geo(
        P,
        B.caixa(
            "antena_lamina",
            (0.32, 0.025, 0.2),
            (1.35, 0, estacao_em(1.35)[1] + 0.08),
            0.008,
            (0, math.radians(-30), 0),
        ),
        verde,
    )

    def lado(x, z, s, afasta=0.0):
        return na_pele(bvh, [(x, s * 1.5, z)], Vector((0, -s, 0)), afasta)[0]

    for s, mat in ((1, luz_r), (-1, luz_v)):
        p = lado(5.0, 2.62, s)
        mt.geo(
            P,
            B.cil("luz_pos", p - Vector((0, s * 0.02, 0)), p + Vector((0, s * 0.05, 0)), 0.04, 8),
            mat,
        )
    # escapamentos do radial (dois de cada lado, embaixo do nariz) e venezianas do óleo
    for s in (1, -1):
        for dx in (0.0, 0.22):
            p = lado(6.32 - dx, 1.02, s) - Vector((0, s * 0.04, 0))
            mt.geo(P, B.cil("escape", p, p + Vector((-0.2, s * 0.16, -0.15)), 0.055, 10), aco)
        g = B.Lote("veneziana")
        for k in range(7):
            g.caixa((0.05, 0.012, 0.22), Matrix.Translation(lado(6.55 - k * 0.09, 1.9, s, 0.004)))
        mt.det(P, g.objeto(), aco_esc)
        # degraus e alça da esquerda (subida para a cabine)
        if s > 0:
            for zz in (1.25, 1.75, 2.25, 2.75):
                mt.det(
                    P,
                    B.caixa("degrau", (0.16, 0.012, 0.07), tuple(lado(4.6, zz, s, 0.004))),
                    aco_esc,
                )
            a0, a1 = lado(4.45, 2.95, s, -0.01), lado(4.8, 2.95, s, -0.01)
            fora = Vector((0, 0.05, 0))
            mt.geo(
                P,
                M.tubo(
                    "alca",
                    [a0, a0 + fora + Vector((0.05, 0, 0)), a1 + fora - Vector((0.05, 0, 0)), a1],
                    0.012,
                    6,
                ),
                aco,
            )
        # portas em concha do motor: costura da dobradiça de cada lado
        pts = na_pele(
            bvh,
            [(x, s * 1.5, 1.0 + (x - 5.6) * 0.1) for x in (5.6, 6.2, 6.8)],
            Vector((0, -s, 0)),
            0.002,
        )
        mt.det(P, M.tubo("costura_lado", pts, 0.006, 6), aco_esc)
        pts = na_pele(
            bvh, [(5.6, s * 1.5, z) for z in (1.0, 1.6, 2.3, 2.7)], Vector((0, -s, 0)), 0.002
        )
        mt.det(P, M.tubo("costura_tras", pts, 0.006, 6), aco_esc)
        # painel de acesso da transmissão
        p0 = lado(3.0, 2.55, s, 0.003)
        mt.det(P, B.caixa("acesso", (0.45, 0.012, 0.3), tuple(p0)), aco_esc)
        # trem principal: amortecedor até o nariz, o V até a barriga, eixo e freio
        roda = Vector((WHEEL.x, s * WHEEL.y, WHEEL.z))
        cubo = roda + Vector((0, -s * 0.2, 0.02))
        alto = lado(6.10, 2.45, s, -0.04)
        meio = cubo.lerp(alto, 0.42)
        mt.geo(P, B.cil("oleo_baixo", cubo, meio, 0.055, 10), aco)
        mt.geo(
            P, B.cil("oleo_alto", meio - (alto - cubo).normalized() * 0.12, alto, 0.085, 10), verde
        )
        for xa in (WHEEL.x - 0.55, WHEEL.x + 0.5):
            pb = na_pele(bvh, [(xa, s * 0.6, -1.0)], Vector((0, 0, 1)), -0.03)[0]
            mt.geo(P, B.cil("v", cubo, pb, 0.045, 8), verde)
        mt.geo(
            P,
            B.cil(
                "eixo", roda + Vector((0, -s * 0.3, 0)), roda + Vector((0, -s * 0.02, 0)), 0.05, 8
            ),
            aco,
        )
        mt.geo(
            P,
            B.cil(
                "freio", roda + Vector((0, -s * 0.16, 0)), roda + Vector((0, -s * 0.1, 0)), 0.16, 12
            ),
            aco_esc,
        )
    # número do avião no nariz (YN-19), colado na pele
    for s, lado_ in ((1, "+Y"), (-1, "-Y")):
        n19 = B.letreiro("19", 0.28, preto, (6.25, s * 0.9, 1.75), lado_)
        mt.det(P, colar(n19, bvh, (0, -s, 0), 0.002), preto)
    n19 = B.letreiro("19", 0.18, preto, (0, 0, 0), "+X")
    M.mover(n19, Matrix.Translation((7.2, 0, 2.25)) @ Matrix.Rotation(-0.6, 4, "Y"))
    mt.det(P, colar(n19, bvh, (-0.6, 0, -0.8), 0.002), preto)
    mt.sem_limpeza(P)
    mt.atlas(P, "casco")

    # ================================================================ INTERIOR
    P = "Interior"
    # piso da cabine com o fosso dos pedais (as pernas do soldado sentado descem 0,4 m abaixo do
    # piso; o fundo do fosso aparece como um degrau no teto da frente do porão)
    x0f, x1f = 4.88, 5.55
    mt.geo(
        P, B.caixa("piso_cab", (x0f - 4.19, 1.5, 0.04), ((x0f + 4.19) / 2, 0, PISO_CAB), 0.0), piso
    )
    mt.geo(
        P,
        B.caixa("piso_cab_f", (5.89 - x1f, 1.5, 0.04), ((5.89 + x1f) / 2, 0, PISO_CAB), 0.0),
        piso,
    )
    mt.geo(P, B.caixa("fosso", (x1f - x0f, 1.56, 0.03), ((x0f + x1f) / 2, 0, FOSSO), 0.0), piso)
    for xw in (x0f, x1f):
        mt.geo(
            P,
            B.caixa("fosso_p", (0.03, 1.56, PISO_CAB - FOSSO), (xw, 0, (PISO_CAB + FOSSO) / 2)),
            interior,
        )
    for sw in (-1, 1):
        mt.geo(
            P,
            B.caixa(
                "fosso_l",
                (x1f - x0f, 0.03, PISO_CAB - FOSSO),
                ((x0f + x1f) / 2, sw * 0.78, (PISO_CAB + FOSSO) / 2),
            ),
            interior,
        )
    mt.geo(P, parede("parede_cab", X_PAREDE_CAB, PISO_CAB, 4.1, 0.04), interior)
    mt.geo(
        P,
        B.caixa(
            "teto_porao",
            (X_PAREDE_CAB - X_ANTEPARA_T, 1.5, 0.04),
            ((X_PAREDE_CAB + X_ANTEPARA_T) / 2, 0, TETO_PORAO),
            0.0,
        ),
        interior_c,
    )
    mt.geo(P, parede("antepara_f", X_ANTEPARA_F, 0.7, PISO_CAB, 0.04), interior)
    mt.geo(P, parede("antepara_t", X_ANTEPARA_T, 0.76, TETO_PORAO, 0.04), interior)
    mt.geo(
        P,
        B.caixa(
            "piso_porao",
            (X_ANTEPARA_F - X_ANTEPARA_T, 1.1, 0.04),
            ((X_ANTEPARA_F + X_ANTEPARA_T) / 2, 0, 0.78),
            0.0,
        ),
        piso,
    )
    # argolas de amarração no piso e cavernas nas paredes e no teto
    g = B.Lote("argolas")
    for x in (1.8, 2.5, 3.2, 3.9, 4.6):
        for y in (-0.5, 0.5):
            g.caixa((0.08, 0.08, 0.012), Matrix.Translation((x, y, 0.785)))
    mt.det(P, g.objeto(), aco)
    for x in (1.75, 2.45, 4.45, 5.05):
        for s in (1, -1):
            if s > 0 and PORTA_E[0] - 0.05 < x < PORTA_E[1] + 0.05:
                continue
            if s < 0 and PORTA[0] - 0.05 < x < PORTA[1] + 0.05:
                continue
            mt.geo(
                P, B.caixa("caverna", (0.05, 0.035, 1.15), (x, s * 0.83, 1.93), 0.005), interior_c
            )
    for x in (1.9, 2.6, 3.3, 4.0):
        mt.geo(
            P,
            B.caixa("caverna_teto", (0.05, 1.55, 0.04), (x, 0, TETO_PORAO - 0.03), 0.005),
            interior_c,
        )
    # painel, capô do painel, console do eixo e comandos dos pilotos
    pr = M.matriz((5.66, 0, 2.93), (0, math.radians(-15), 0))
    mt.geo(P, M.mover(M.caixa("painel", (0.07, 1.25, 0.34)), pr), painel)
    mt.geo(P, B.caixa("capo_painel", (0.3, 1.25, 0.04), (5.73, 0, 3.12), 0.01), painel)
    g = B.Lote("mostradores")
    gf = B.Lote("vidros_mostr")
    for y in (-0.5, -0.38, -0.26, -0.12, 0.12, 0.26, 0.38, 0.5):
        for zz in (-0.07, 0.07):
            m = pr @ Matrix.Translation((-0.04, y, zz)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
            g.cil(0.045, 0.01, m, 12)
            gf.cil(0.036, 0.012, m @ Matrix.Translation((0, 0, -0.002)), 12)
    mt.det(P, g.objeto(), mostrador)
    mt.det(P, gf.objeto(), painel)
    mt.geo(
        P,
        M.tubo("console", [(5.62, 0, 2.6), (4.9, 0, 2.86), (4.22, 0, 3.1)], 0.13, 8, True, 0.75),
        interior,
    )
    mt.geo(P, B.caixa("console_teto", (0.42, 0.3, 0.06), (4.98, 0, 4.0), 0.01), painel)
    for s in (1, -1):
        y0 = s * OLHO_PILOTO[1]
        mt.geo(
            P, B.caixa("assento", (0.46, 0.46, 0.07), (4.68, y0, ASSENTO_Z - 0.035), 0.02), banco
        )
        mt.geo(
            P,
            B.caixa(
                "encosto",
                (0.07, 0.46, 0.6),
                (4.43, y0, ASSENTO_Z + 0.32),
                0.02,
                (0, math.radians(-12), 0),
            ),
            banco,
        )
        for ds in (-1, 1):
            mt.geo(
                P,
                B.caixa(
                    "blindagem", (0.5, 0.025, 0.42), (4.6, y0 + ds * 0.25, ASSENTO_Z + 0.18), 0.008
                ),
                aco_esc,
            )
        mt.geo(
            P,
            B.cil("pe_banco", (4.68, y0, PISO_CAB), (4.68, y0, ASSENTO_Z - 0.07), 0.05, 8),
            aco_esc,
        )
        mt.geo(P, B.cil("ciclico", (5.04, y0, FOSSO), (4.97, y0, 2.9), 0.016, 6), aco_esc)
        mt.geo(P, B.cil("punho", (4.97, y0, 2.88), (4.95, y0, 2.98), 0.025, 6), borr)
        mt.geo(
            P,
            B.cil(
                "coletivo",
                (4.5, y0 + 0.28, ASSENTO_Z),
                (4.92, y0 + 0.28, ASSENTO_Z + 0.16),
                0.018,
                6,
            ),
            aco_esc,
        )
        for dp in (-0.13, 0.13):
            mt.geo(
                P,
                B.caixa(
                    "pedal",
                    (0.05, 0.09, 0.2),
                    (5.42, y0 + dp, FOSSO + 0.12),
                    0.01,
                    (0, math.radians(-30), 0),
                ),
                aco_esc,
            )
    # tropa: banco de lona da esquerda (sob o vão), da direita atrás da porta e do fundo, com os
    # tubos; extintor e caixa de primeiros socorros no fundo
    bancos = (
        ((2.55, 4.45), 0.64, 1),
        ((1.6, 2.85), -0.64, -1),
    )
    for (x0, x1), y, s in bancos:
        xc, comp = (x0 + x1) / 2, x1 - x0
        mt.geo(P, B.caixa("banco_tropa", (comp, 0.34, 0.05), (xc, y, 1.18), 0.01), lona)
        mt.geo(
            P, B.caixa("encosto_tropa", (comp, 0.03, 0.42), (xc, y + s * 0.19, 1.47), 0.005), lona
        )
        mt.geo(
            P,
            B.cil("tubo_banco", (x0, y - s * 0.16, 1.19), (x1, y - s * 0.16, 1.19), 0.018, 6),
            aco,
        )
        for x in (x0 + 0.1, xc, x1 - 0.1):
            mt.geo(
                P, B.cil("perna", (x, y - s * 0.15, 0.78), (x, y - s * 0.15, 1.17), 0.016, 6), aco
            )
    mt.geo(P, B.caixa("banco_fundo", (0.34, 1.2, 0.05), (1.66, 0, 1.18), 0.01), lona)
    mt.geo(
        P, B.caixa("encosto_fundo", (0.03, 1.2, 0.42), (X_ANTEPARA_T + 0.04, 0, 1.47), 0.005), lona
    )
    mt.geo(P, B.cil("extintor", (1.5, -0.55, 1.75), (1.5, -0.55, 2.2), 0.06, 10), extintor)
    mt.geo(P, B.caixa("socorros", (0.06, 0.32, 0.22), (1.5, 0.45, 2.0), 0.01), branco)
    # trilho da porta e a M60 da porta (pino na borda da frente)
    mt.geo(P, B.cil("pino_m60", (4.12, -0.74, 0.9), (4.12, -0.74, 1.45), 0.025, 8), aco)
    mg = M.matriz((4.12, -1.02, 1.5), (0, 0, math.radians(90)))
    for nome, dim, pos in (
        ("caixa_m60", (0.44, 0.08, 0.1), (0.0, 0, 0)),
        ("coronha", (0.3, 0.05, 0.11), (-0.36, 0, -0.01)),
        ("punho_m60", (0.05, 0.04, 0.12), (-0.12, 0, -0.1)),
        ("tampa_m60", (0.2, 0.07, 0.03), (0.04, 0, 0.065)),
    ):
        mt.geo(P, M.mover(M.caixa(nome, dim, pos), mg), aco_esc)
    mt.geo(P, B.cil("cano_m60", (4.12, -1.24, 1.52), (4.12, -1.82, 1.52), 0.014, 6), aco_esc)
    mt.geo(P, B.cil("guarda_m60", (4.12, -1.24, 1.52), (4.12, -1.45, 1.52), 0.03, 8), aco_esc)
    mt.geo(P, B.cil("bipe_m60", (4.12, -1.45, 1.5), (4.12, -1.5, 1.38), 0.01, 4), aco_esc)
    mt.geo(P, B.caixa("cunhete", (0.26, 0.11, 0.18), (4.0, -0.68, 1.32), 0.008), verde)
    mt.geo(
        P,
        M.tubo(
            "fita", [(4.0, -0.7, 1.42), (4.06, -0.82, 1.5), (4.12, -0.96, 1.5)], 0.02, 4, True, 0.3
        ),
        aco,
    )
    mt.sem_limpeza(P)
    mt.atlas(P, "interior")

    # ================================================================ VIDRO (transparente no jogo)
    P = "Vidro"
    mt.geo(P, vid, vidro, suave=40)
    # o vidro de correr dos pilotos aberto, para trás, por fora
    for s in (1, -1):
        cs = na_pele(
            bvh,
            [(x, s * 1.5, z) for x in (3.86, 4.36) for z in (3.05, 3.8)],
            Vector((0, -s, 0)),
            0.025,
        )
        bm = bmesh.new()
        vs = [bm.verts.new(p) for p in (cs[0], cs[2], cs[3], cs[1])]
        bm.faces.new(vs if s < 0 else list(reversed(vs)))
        o = B.de_bm("vidro_correr", bm, normais=False)
        mt.geo(P, o, vidro, suave=40)
    mt.sem_limpeza(P)
    mt.atlas(P, "interior")

    # ================================================================ CAUDA
    P = "Cauda"
    cone = fuselagem("cone", ESTACOES_CAUDA, False, True)
    bvh_cone = bvh_de(cone)
    mt.geo(P, cone, verde_c, suave=50)
    d = B.prisma("deriva", DERIVA, "Y", -0.24, 0.24)
    for vt in d.data.vertices:
        k = max(0.0, min(1.0, (vt.co.z - 2.3) / (4.08 - 2.3)))
        vt.co.y *= 1 - 0.55 * k
    d.data.update()
    M.chanfrar(d, 0.03, 1, 30.0)
    bvh_der = bvh_de(d)
    mt.geo(P, d, verde_c)
    # estabilizador da direita, no alto da deriva
    est = B.prisma(
        "estabilizador",
        [
            (-5.62, 0.0),
            (-5.70, 0.03),
            (-6.30, 0.025),
            (-6.38, 0.0),
            (-6.30, -0.02),
            (-5.70, -0.025),
        ],
        "Y",
        -1.08,
        -0.08,
    )
    M.mover(est, Matrix.Translation((0, 0, 3.62)))
    mt.geo(P, est, verde_c)
    # caixa do rotor de cauda na esquerda da deriva
    mt.geo(
        P,
        B.torno_eixo(
            "caixa_cauda",
            [(0.0, 0.0), (0.16, 0.0), (0.15, 0.25), (0.09, 0.38), (0.05, 0.47), (0.0, 0.48)],
            "Y",
            (TAIL.x, 0.06, TAIL.z),
            12,
        ),
        verde_c,
    )
    mt.geo(P, B.cil("eixo_cauda", (-0.4, 0, 2.86), (-4.5, 0, 2.30), 0.045, 8), verde_c)
    # bequilha: perna, garfo e o reforço
    mt.geo(
        P, B.cil("perna_bq", (-3.15, 0, 1.0), (TWHEEL.x + 0.04, 0, TWHEEL.z + 0.24), 0.06, 10), aco
    )
    for s in (1, -1):
        mt.geo(
            P,
            B.caixa(
                "garfo",
                (0.24, 0.025, 0.05),
                (TWHEEL.x + 0.06, s * 0.085, TWHEEL.z + 0.12),
                0.006,
                (0, math.radians(-40), 0),
            ),
            verde_c,
        )
    mt.geo(
        P, B.cil("eixo_bq", (TWHEEL.x, -0.1, TWHEEL.z), (TWHEEL.x, 0.1, TWHEEL.z), 0.025, 8), aco
    )
    mt.geo(P, B.cil("antena", (-1.3, 0, 2.70), (-1.75, 0, 3.55), 0.008, 6), aco_esc)
    # marcas: MARINES, insígnia nacional (estrela e barras), YN e o BuNo
    for s, face in ((1, "+Y"), (-1, "-Y")):
        dd = (0, -s, 0)
        t = B.letreiro("MARINES", 0.24, preto, (-2.2, s * 0.4, 1.95), face)
        mt.det(P, colar(t, bvh_cone, dd, 0.002), preto)
        t = B.letreiro("YN", 0.34, preto, (-5.75, s * 0.3, 2.95), face)
        mt.det(P, colar(t, bvh_der, dd, 0.002), preto)
        t = B.letreiro("150570", 0.075, preto, (-5.55, s * 0.3, 2.55), face)
        mt.det(P, colar(t, bvh_der, dd, 0.002), preto)
        # insígnia nacional (estrela e barras, com a faixa vermelha): chapas coladas no cone
        xc, zc = -0.55, 1.85
        circ = [
            (xc + 0.25 * math.cos(2 * math.pi * k / 24), zc + 0.25 * math.sin(2 * math.pi * k / 24))
            for k in range(24)
        ]
        mt.det(P, colar(chapa("ins_disco", circ, s, (xc, zc)), bvh_cone, dd, 0.002), azul)
        for sx in (-1, 1):
            x0 = xc + sx * 0.24
            x1 = xc + sx * 0.62
            x2 = x1 - sx * 0.02
            mt.det(
                P,
                colar(
                    ret("ins_borda", x0, x1, zc - 0.095, zc + 0.095, s * sx), bvh_cone, dd, 0.002
                ),
                azul,
            )
            mt.det(
                P,
                colar(
                    ret("ins_barra", x0, x2, zc - 0.075, zc + 0.075, s * sx), bvh_cone, dd, 0.003
                ),
                branco,
            )
            mt.det(
                P,
                colar(
                    ret("ins_faixa", x0, x2, zc - 0.025, zc + 0.025, s * sx), bvh_cone, dd, 0.004
                ),
                vermelho,
            )
        est5 = []
        for k in range(10):
            a = math.pi / 2 + k * math.pi / 5
            r = 0.23 if k % 2 == 0 else 0.09
            est5.append((xc + math.cos(a) * r, zc + math.sin(a) * r))
        mt.det(P, colar(chapa("ins_estrela", est5, s, (xc, zc)), bvh_cone, dd, 0.005), branco)
    mt.ext["cauda"] = 0.025
    mt.atlas(P, "cauda")

    # ======================================================= PORTA (de correr, aberta para trás)
    P = "Escotilha_Porta"
    # a chapa que saiu do vão, 1,3 m para trás e 4 cm para fora, com espessura e a janelinha
    dx_porta = -(PORTA[1] - PORTA[0])
    folha.data.transform(Matrix.Translation((dx_porta, -0.04, 0)))
    folha.data.update()
    cortar(
        folha,
        [
            ((2.12, 0, 0), (1, 0, 0), lambda c: True),
            ((2.50, 0, 0), (1, 0, 0), lambda c: True),
            ((0, 0, 1.68), (0, 0, 1), lambda c: True),
            ((0, 0, 2.02), (0, 0, 1), lambda c: True),
        ],
    )
    M.solidificar(folha, 0.03, 1.0)
    M.material(folha, verde)
    B.pintar_por(folha, lambda c, n: 2.12 < c.x < 2.50 and 1.68 < c.z < 2.02 and n.y < -0.5, vidro)
    mt.geo(P, folha, None, suave=40)
    pa_ = lado(2.85, 1.55, -1, 0.07)
    mt.geo(P, B.caixa("alca", (0.03, 0.03, 0.16), tuple(pa_), 0.005), aco)
    # trilhos (no casco, por fora)
    for zt in (2.25, 1.02):
        p0, p1 = lado(1.55, zt, -1, 0.02), lado(PORTA[1] + 0.05, zt, -1, 0.02)
        mt.geo(P, B.cil("trilho", p0, p1, 0.022, 6), aco)
    mt.atlas(P, "interior")

    # ================================================================ ROTOR PRINCIPAL: cubo e pás
    P = "RotorPrincipal"
    cubo = M.torno(
        "cubo", [(0.0, -0.14), (0.3, -0.14), (0.32, 0.02), (0.22, 0.12), (0.0, 0.14)], 16
    )
    M.mover(cubo, Matrix.Translation(HUB))
    mt.geo(P, cubo, aco)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        u = Vector((math.cos(a), math.sin(a), 0))
        v = Vector((-math.sin(a), math.cos(a), 0))
        mt.geo(P, B.caixa("braco", (0.36, 0.15, 0.11), HUB + u * 0.46, 0.02, (0, 0, a)), aco)
        mt.geo(
            P,
            B.cil("dobradica", HUB + u * 0.34 - v * 0.1, HUB + u * 0.34 + v * 0.1, 0.06, 10),
            aco_esc,
        )
        mt.geo(
            P,
            B.cil(
                "dobra_arrasto",
                HUB + u * 0.62 + Vector((0, 0, -0.08)),
                HUB + u * 0.62 + Vector((0, 0, 0.08)),
                0.055,
                10,
            ),
            aco_esc,
        )
        mt.geo(
            P, M.tubo("punho", [HUB + u * 0.64, HUB + u * 0.96], [0.08, 0.06], 8, True, 0.75), aco
        )
        mt.geo(
            P,
            B.cil(
                "amortecedor",
                HUB + u * 0.3 + v * 0.17 + Vector((0, 0, 0.07)),
                HUB + u * 0.78 + v * 0.13 + Vector((0, 0, 0.02)),
                0.04,
                8,
            ),
            aco_esc,
        )
        chifre = HUB + u * 0.72 + v * 0.17 + Vector((0, 0, -0.05))
        mt.geo(P, B.caixa("chifre", (0.12, 0.08, 0.03), tuple(chifre), 0.005, (0, 0, a)), aco)
        mt.geo(
            P, B.cil("haste", chifre, Vector((HUB.x, 0, 4.19)) + u * 0.25 + v * 0.17, 0.014, 6), aco
        )
    mt.pivo(P, tuple(HUB))
    mt.atlas(P, "cauda")
    P = "Pa_1"
    a = math.radians(45)
    u = Vector((math.cos(a), math.sin(a), 0))
    v = Vector((-math.sin(a), math.cos(a), 0))
    est = []
    for r, c, t in (
        (0.90, 0.16, 0.55),
        (1.05, 0.26, 0.3),
        (1.40, CORDA, 0.12),
        (2.5, CORDA, 0.12),
        (4.5, CORDA, 0.12),
        (6.5, CORDA, 0.12),
        (R_ROT - 0.16, CORDA, 0.12),
        (R_ROT - 0.03, CORDA, 0.12),
        (R_ROT, CORDA * 0.85, 0.1),
    ):
        est.append((r, c, t, -0.38 * (r / R_ROT) ** 2))
    pa = aerofolio("pa", est, u, v, HUB)
    B.pintar_por(M.material(pa, pa_m), lambda c, n: disco_dist(c, HUB) > R_ROT - 0.155, ponta)
    mt.geo(P, pa, None)
    # aba do bordo de fuga e o peso da ponta (só textura)
    rr = 6.3
    mt.det(
        P,
        B.caixa(
            "aba",
            (0.3, 0.06, 0.004),
            tuple(HUB + u * rr - v * (CORDA * 0.72) + Vector((0, 0, -0.38 * (rr / R_ROT) ** 2))),
            0.0,
            (0, 0, a),
        ),
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
            [(0.0, -0.04), (0.12, -0.04), (0.12, 0.08), (0.06, 0.15), (0.0, 0.16)],
            "Y",
            tuple(TAIL),
            12,
        ),
        aco,
    )
    for k in range(4):
        a = math.radians(20 + 90 * k)
        uu = Vector((math.cos(a), 0, math.sin(a)))
        vv = Vector((-math.sin(a), 0, math.cos(a)))
        c0 = TAIL + Vector((0, 0.07, 0))
        estc = [
            (0.14, 0.09, 0.4, 0.0),
            (0.26, CORDA_C, 0.12, 0.0),
            (0.8, CORDA_C, 0.12, 0.0),
            (R_CAUDA - 0.08, CORDA_C, 0.12, 0.0),
            (R_CAUDA, CORDA_C * 0.85, 0.1, 0.0),
        ]
        pc = aerofolio("pa_c", estc, uu, vv, c0)
        B.pintar_por(
            M.material(pc, pa_m),
            lambda c, n, c0=c0: math.hypot(c.x - c0.x, c.z - c0.z) > R_CAUDA - 0.08,
            ponta,
        )
        mt.geo(P, pc, None)
    mt.pivo(P, tuple(TAIL))
    mt.atlas(P, "cauda")

    # ================================================================ RODAS
    P = "Roda_E"
    rr0 = R_RODA
    perf = [
        (0.0, 0.11),
        (0.12, 0.11),
        (0.22, 0.10),
        (rr0 - 0.07, 0.11),
        (rr0 - 0.02, 0.10),
        (rr0, 0.07),
        (rr0, -0.07),
        (rr0 - 0.02, -0.10),
        (rr0 - 0.07, -0.11),
        (0.22, -0.10),
        (0.12, -0.12),
        (0.0, -0.12),
    ]
    o = B.torno_eixo("roda", perf, "Y", tuple(WHEEL), 20)
    M.material(o, borr)
    B.pintar_por(o, lambda c, n: math.hypot(c.x - WHEEL.x, c.z - WHEEL.z) < 0.25, verde)
    mt.geo(P, o, None)
    # banda de rodagem e parafusos do cubo (só textura)
    g = B.Lote("banda")
    for k in range(28):
        aa = 2 * math.pi * k / 28
        m = Matrix.Translation(
            WHEEL + Vector((math.cos(aa) * rr0, 0, math.sin(aa) * rr0))
        ) @ Matrix.Rotation(-aa, 4, "Y")
        g.caixa((0.012, 0.15, 0.03), m)
    mt.det(P, g.objeto(), borr)
    g = B.Lote("parafusos")
    for k in range(6):
        aa = 2 * math.pi * k / 6
        g.cil(
            0.012,
            0.03,
            Matrix.Translation(WHEEL + Vector((math.cos(aa) * 0.13, 0.115, math.sin(aa) * 0.13)))
            @ Matrix.Rotation(math.pi / 2, 4, "X"),
            6,
        )
    mt.det(P, g.objeto(), aco)
    mt.pivo(P, tuple(WHEEL))
    mt.atlas(P, "cauda")
    mt.instancia("Roda_D", "Roda_E", (WHEEL.x, -WHEEL.y, WHEEL.z), giro_z180=True)
    P = "Roda_Cauda"
    perf = [
        (0.0, 0.05),
        (0.08, 0.05),
        (0.17, 0.05),
        (0.2, 0.03),
        (0.2, -0.03),
        (0.17, -0.05),
        (0.08, -0.05),
        (0.0, -0.05),
    ]
    o = B.torno_eixo("bequilha", perf, "Y", tuple(TWHEEL), 14)
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
            "driver": (OLHO_PILOTO[0], -OLHO_PILOTO[1], OLHO_PILOTO[2]),
            "copilot": OLHO_PILOTO,
            "gunner": (3.75, -1.04, 1.72),
        },
        "passageiros": {"x0": 4.05, "dx": 0.36, "y": 0.80, "z": 1.62},
        "assentos_z": {"driver": ASSENTO_Z, "copilot": ASSENTO_Z},
        "escotilhas": {"Escotilha_Porta (vão)": [PORTA[1] - PORTA[0], PORTA_Z[1] - PORTA_Z[0]]},
        "rotor": (HUB.x, HUB.y, HUB.z, R_ROT),
        "cauda": (TAIL.x, TAIL.y, TAIL.z, R_CAUDA),
        "notas": [
            "v3 (D-199): silhueta medida no desenho de três vistas (cabine alta, mastro curto, "
            "cone fundo, deriva inclinada, trem principal à frente e bequilha atrás).",
            "Vidro: nó próprio; o jogo deixa transparente, nos dois lados e sem colisão.",
            "Cabine e porão com forro por dentro: o olho do piloto e do copiloto fica DENTRO da "
            "cabine (a casca de fora é face única e some por dentro).",
            "Pás do rotor principal: Pa_1..Pa_4 são a mesma malha em 4 nós (giro de 90° em Y do "
            "GLB); o jogo deve soldar as 4 no RotorPrincipal (cubo) e girar o cubo.",
            "Rotor de cauda no lado esquerdo da deriva (0,55 m, medido na planta).",
            "Passageiros: na porta da direita (pernas para fora) e no banco de lona da esquerda.",
            "v45: o porão também é aberto à esquerda (x 2,15 a 4,25 m), liberdade de jogo.",
        ],
    }
    return mt, info
