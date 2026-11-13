"""Caixas de munição do suporte (2026-11-13, pedido do dono: "faça a caixa de munições bonita e que
seja possível ver onde ele coloca no chão").

Duas chaves, uma por lado, pelo mesmo caminho das bases (`bases.py`: peça alta em metros com
material procedural, redução pela tolerância de desvio, UV nova, bake de cor, normal, rugosidade,
metal e oclusão, GLB em studs com o nó visual e a colisão `Colisao_*`):
- `caixa_municao_us`: caixote de madeira verde-oliva de 1965, tampa de dobradiça aberta para trás,
  6 latas M19A1 em pé (duas abertas com carregadores de M14 à vista), duas granadas M26 por cima,
  alças de corda e estêncil amarelo e branco (7.62 MM, AMMUNITION, lote);
- `caixa_municao_vc`: caixote chinês de madeira clara com marcas em chinês (e "ĐẠN 7,62" a
  pincel), tampa arrancada e encostada atrás, uma lata de 720 aberta com os pacotes de papel,
  carregadores curvos do Tipo 56 e duas granadas de cabo.

Convenções (as das bases): frente em -Y no Blender = +Z no GLB = -Z (LookVector) no Roblox depois
do giro de 180° do importador (D-58); pivô no centro da caixa, base no chão (Z = 0). O metricas.json
traz `extras.icone_studs` (ponto do ícone, acima da caixa) e `extras.pegada_studs` (X e Z da pegada
no chão, para a prévia de colocação).

Uso (a partir de vantuong65, PowerShell; sempre na CPU: a GPU de 2 GB é do Studio):
    $env:VT65_CPU = "1"; $env:VT65_THREADS = "6"
    & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup `
        -P tools/blender/caixa_municao.py -- caixa_municao_us --cpu-todos
    ... -- caixa_municao_us --previa 30   (só a peça alta, _trabalho/<chave>/previa_alta_30.png)
    ... -- caixa_municao_us --previa-final     (render do GLB: assets/blender/<chave>/_previa.png)

Medidas: as com fonte estão em `MEDIDAS`; o resto é PLACEHOLDER.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bases  # noqa: E402
import bases_comum as B  # noqa: E402
import comum as C  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402

STUD = C.M_POR_STUD
FONTE_CHINES = Path("C:/Windows/Fonts/msyhbd.ttc")  # Microsoft YaHei negrito (tem os ideogramas)
FONTE_VIET = Path("C:/Windows/Fonts/arialbd.ttf")  # tem Đ e Ạ (o STENCIL.TTF não tem)

MEDIDAS_US = {
    "lata_m19a1_m": [
        [0.095, 0.273, 0.18],
        "~3,5-3,75 x 10-11 x 7 pol por fora (vendedores de excedente: skycraftsurplus.com, "
        "luckygunner.com; o 11 x 4 x 7 inclui a tampa)",
    ],
    "caixote_m": [
        [0.629, 0.323, 0.226],
        "PLACEHOLDER: caixote para 6 latas M19A1 em pé (sem fonte de caixote de 1965; o tamanho "
        "de jogo pedido é 0,6-0,8 m)",
    ],
    "carregador_m14_m": [[0.075, 0.025, 0.13], "PLACEHOLDER (20 tiros; de fotos)"],
    "granada_m26": [None, "a mesma receita do grenade_m26 (novos.py)"],
    "estencil": [
        None,
        "PLACEHOLDER: 'CARTRIDGE 7.62 MM / BALL M80 / LINKED M13', 'LOT LC-47-65' (Lake City, "
        "1965) e 'AMMUNITION'; cores amarelo e branco pedidas pelo dono",
    ],
}
MEDIDAS_VC = {
    "caixote_m": [
        [0.588, 0.344, 0.218],
        "PLACEHOLDER: caixote chinês de 2 latas de 720 cartuchos 7,62 x 39 (1.440); o "
        "ammo_crate antigo usava 0,56 x 0,336 x 0,29 também sem fonte",
    ],
    "lata_m": [[0.265, 0.292, 0.17], "PLACEHOLDER (lata soldada de 720, 36 pacotes de 20)"],
    "carregador_tipo56_m": [
        [0.205, 0.062, 0.026],
        "PLACEHOLDER (30 tiros, curvo; comprimento ao longo da curva)",
    ],
    "granada_cabo": [None, "a mesma receita do grenade_stick (novos.py)"],
    "marcas": [
        None,
        "PLACEHOLDER: '56式 7.62 普通弹' (cartucho comum Tipo 56), '1440发' (1.440 tiros), "
        "'311-65' (fábrica e ano, sem fonte) e 'ĐẠN 7,62' a pincel vermelho",
    ],
}

CAIXAS: dict[str, dict] = {
    "caixa_municao_us": {
        "nome": "caixa de munição do suporte (EUA): caixote com 6 latas M19A1, carregadores e "
        "granadas",
        "base": "US",
        "classe": "prop",
        "grupos": {"Principal": {"teto": 4800, "tex": 1024, "metal": True}},
        "casca": [],
        "medidas": MEDIDAS_US,
    },
    "caixa_municao_vc": {
        "nome": "caixa de munição do suporte (VC): caixote chinês, lata aberta, carregadores e "
        "granadas de cabo",
        "base": "VC",
        "classe": "prop",
        "grupos": {"Principal": {"teto": 4800, "tex": 1024, "metal": True}},
        "casca": [],
        "medidas": MEDIDAS_VC,
    },
}

USO = (
    "Caixa do suporte (classes): o modelo inteiro vai no chão com o LookVector (frente, -Z) virado "
    "para quem colocou, pivô na base (centro da caixa no chão). Prévia de colocação: a mesma malha "
    "(nó Caixa) clonada, sem SurfaceAppearance, Transparency 0,5 e cor verde (pode) ou vermelha "
    "(não pode), mais um retângulo no chão do tamanho de extras.pegada_studs (X, Z). O ícone fica "
    "em extras.icone_studs (acima da caixa)."
)


# =============================================================== peças
def tabua(nome, dim, centro, mat, chanfro=0.0025, sem=0):
    """Tábua com chanfro e um leve empeno (ruído de 0,6 mm)."""
    b = M.caixa(nome, dim, centro, cortes=1)
    M.chanfrar(b, chanfro, 2)
    M.deslocar(b, lambda co, n: 0.0006 * M.ruido(co * 40, sem))
    return M.material(M.suave(b, 35), mat)


def letreiro_z(corpo, altura, mat, matriz, fonte=M.FONTE_ESTENCIL):
    """Texto no plano XY (normal +Z, leitura em +X, alto em +Y) levado por `matriz`."""
    t = M.texto_malha(corpo, altura, fonte)
    M.mover(t, matriz)
    M.material(t, mat)
    return N.so_bake(t)


def caixa_aberta(nome, dim, centro, mat, chanfro=0.003, parede=0.0012):
    """Caixa de chapa sem a tampa (lata aberta): chanfro, topo apagado e parede para dentro."""
    o = M.caixa(nome, dim, (0, 0, 0))
    M.chanfrar(o, chanfro, 2)
    h = dim[2] / 2
    B.apagar_faces(o, lambda c: c.z > h - 1e-5)
    M.solidificar(o, parede, -1.0)
    M.mover(o, Matrix.Translation(Vector(centro)))
    return M.material(M.suave(o, 35), mat)


def loft_curvo(nome, caminho, meia_larg, meia_alt, mat, n_exp=4.0, k=16):
    """Sólido de seção superelíptica (meia largura no eixo lateral X, meia altura na normal da
    curva) ao longo de uma polilinha no plano YZ, com tampas."""
    pts = [Vector(p) for p in caminho]
    bm = bmesh.new()
    aneis = []
    lat = Vector((1, 0, 0))
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nrm = lat.cross(t).normalized()
        anel = []
        for j in range(k):
            a = 2 * math.pi * j / k
            c, s = math.cos(a), math.sin(a)
            x = meia_larg * math.copysign(abs(c) ** (2 / n_exp), c)
            y = meia_alt * math.copysign(abs(s) ** (2 / n_exp), s)
            anel.append(bm.verts.new(p + lat * x + nrm * y))
        aneis.append(anel)
    for a, b in zip(aneis[:-1], aneis[1:], strict=True):
        for j in range(k):
            jj = (j + 1) % k
            bm.faces.new((a[j], a[jj], b[jj], b[j]))
    bm.faces.new(list(reversed(aneis[0])))
    bm.faces.new(aneis[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = M.de_bmesh(nome, bm)
    return M.material(M.suave(o, 40), mat)


def mover_todos(objs, m):
    for o in objs:
        M.mover(o, m)
    return objs


def corda_alca(x_face, sinal, z, meia, mat):
    """Alça de corda numa cabeceira: entra pelos dois sarrafos e pende no meio."""
    pts = []
    for t in np.linspace(-1.0, 1.0, 21):
        curva = 1 - t * t
        pts.append((x_face + sinal * (0.012 + 0.018 * curva), meia * t, z - 0.055 * curva))
    return M.material(M.suave(M.tubo("alca", pts, 0.0065, 8), 60), mat)


def cartucho_762(nome, mats, eixo_x=True, comp_estojo=0.051, r=0.006, bala=0.022):
    """Cartucho deitado ao longo de X (ponta em -X): estojo de latão e bala de cobre."""
    estojo = M.torno(
        nome,
        [
            (0.0, 0.0),
            (r, 0.0),
            (r, comp_estojo * 0.82),
            (r * 0.72, comp_estojo),
            (0.0, comp_estojo),
        ],
        segs=10,
    )
    ponta = M.torno(
        nome + "_b",
        [
            (0.0, comp_estojo - 0.002),
            (r * 0.66, comp_estojo - 0.002),
            (r * 0.62, comp_estojo + bala * 0.45),
            (r * 0.25, comp_estojo + bala * 0.92),
            (0.0, comp_estojo + bala),
        ],
        segs=10,
    )
    M.material(M.suave(estojo, 45), mats["latao"])
    M.material(M.suave(ponta, 45), mats["cobre"])
    objs = [estojo, ponta]
    if eixo_x:
        mover_todos(objs, Matrix.Rotation(-math.pi / 2, 4, "Y"))
    return objs


def mat_papel(nome: str, cor="#9c8158"):
    """Papel pardo dos pacotes de 20 (sem metal)."""
    m = M.Mat(nome, rug=0.9)
    p = m.coord("objeto")
    v = m.ruido(p, 40.0, 4)
    m.cor(m.misturar(m.faixa(v, 0.3, 0.7, 0.0, 0.35), M.rgb(cor), M.rgb("#6e5a3c")))
    m.relevo(m.ruido(p, 300.0, 3), 0.15, 0.0005)
    return m.m


def mats_metal():
    return {
        "latao": N.mat_aco("latao", "#b08d4a", 0.36, 600.0),
        "cobre": N.mat_aco("cobre", "#a0603a", 0.38, 600.0),
    }


# =============================================================== EUA
def receita_caixa_municao_us():
    """Caixote verde-oliva aberto com 6 latas M19A1, 2 abertas com carregadores de M14, 2 M26."""
    r = B.Receita()
    od = N.mat_caixote("caixa_us_od", tinta="#4e5535")
    corda = N.mat_corda("caixa_us_corda", "#8f7f58")
    ferragem = N.mat_tinta("caixa_us_ferragem", "#4a4f33", desgaste=0.7, escala=400.0)
    lata = N.mat_tinta("lata_m19a1", "#4b5133", desgaste=0.55, escala=500.0)
    pente = N.mat_aco("carregador_m14", "#3b3c38", 0.55, 500.0)
    met = mats_metal()
    amarelo = N.mat_estencil("estencil_amarelo", "#d2ac34", "#4e5535", gasto=0.3, escala=220.0)
    branco = N.mat_estencil("estencil_branco", "#ddd6bd", "#4e5535", gasto=0.35, escala=220.0)
    amarelo_lata = N.mat_estencil("estencil_lata", "#cda935", "#4b5133", gasto=0.25, escala=400.0)

    T = 0.019  # tábua de 3/4 pol
    LW, LL, LH = 0.095, 0.273, 0.18  # lata M19A1 (X, Y, Z)
    n_latas, folga = 6, 0.003
    ix = n_latas * LW + (n_latas + 1) * folga
    iy = LL + 2 * 0.006
    Lx, Ly = ix + 2 * T, iy + 2 * T
    z0 = 0.022  # dois barrotes por baixo (o caixote não encosta no chão molhado)
    zf = z0 + T  # fundo de dentro
    Hc = T + LH + 0.005  # altura das paredes (a lata fica 5 mm abaixo da borda)
    zt = z0 + Hc  # borda de cima
    objs = []
    # barrotes, fundo, lados (2 tábuas) e cabeceiras
    for s in (-1, 1):
        objs.append(tabua("barrote", (0.05, Ly, z0), (s * (Lx / 2 - 0.07), 0, z0 / 2), od, sem=1))
    objs.append(tabua("fundo", (Lx, Ly, T), (0, 0, z0 + T / 2), od, sem=2))
    for s in (-1, 1):
        y = s * (Ly / 2 - T / 2)
        meia = (Hc - T) / 2
        for k in range(2):
            zc = zf + meia * (k + 0.5)
            objs.append(tabua(f"lado{s}{k}", (Lx, T, meia - 0.002), (0, y, zc), od, sem=3 + k))
        x = s * (Lx / 2 - T / 2)
        objs.append(tabua(f"cab{s}", (T, Ly - 2 * T, Hc - T), (x, 0, zf + (Hc - T) / 2), od, 0.002))
        # sarrafos de cabeceira (por fora) e a alça de corda que passa por eles
        for t in (-1, 1):
            objs.append(
                tabua(
                    f"sarrafo{s}{t}",
                    (0.022, 0.05, Hc + 0.012),
                    (s * (Lx / 2 + 0.011), t * 0.095, z0 + (Hc + 0.012) / 2 - 0.006),
                    od,
                    sem=7,
                )
            )
        objs.append(corda_alca(s * (Lx / 2 + 0.022), s, zt - 0.06, 0.095, corda))
    # cintas de aço nas pontas dos lados (cantoneiras) e as fechaduras (aldrabas) na frente
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(
                B.bloco(
                    "cantoneira",
                    (0.03, 0.003, Hc - 0.02),
                    (sx * (Lx / 2 - 0.03), sy * (Ly / 2 + 0.0015), z0 + Hc / 2),
                    ferragem,
                    chanfro=0.0008,
                )
            )
        objs.append(
            B.bloco(
                "aldraba",
                (0.03, 0.004, 0.055),
                (sx * 0.2, -Ly / 2 - 0.002, zt - 0.02),
                ferragem,
                chanfro=0.001,
            )
        )
        objs.append(
            B.vara(
                "argola",
                (sx * 0.2, -Ly / 2 - 0.004, zt - 0.045),
                (sx * 0.2, -Ly / 2 - 0.012, zt - 0.045),
                0.005,
                mat=ferragem,
                segs=8,
            )
        )
    # estêncil: frente (amarelo, o calibre grande) e lote (branco); cabeceiras
    yf = -Ly / 2 - 0.0004
    objs.append(N.letreiro_plano("AMMUNITION", 0.024, amarelo, (0, yf, zt - 0.03), "-Y"))
    objs.append(N.letreiro_plano("7.62 MM", 0.05, amarelo, (0, yf, zt - 0.085), "-Y"))
    objs.append(
        N.letreiro_plano("CARTRIDGE BALL M80  LINKED M13", 0.014, amarelo, (0, yf, zf + 0.05), "-Y")
    )
    objs.append(N.letreiro_plano("LOT LC-47-65", 0.016, branco, (0, yf, zf + 0.025), "-Y"))
    for s, nrm in ((-1, "-X"), (1, "+X")):
        x = s * (Lx / 2 + 0.0004)
        objs.append(N.letreiro_plano("7.62", 0.04, amarelo, (x, 0, zt - 0.05), nrm))
        objs.append(N.letreiro_plano("6 CANS", 0.016, branco, (x, 0, zf + 0.04), nrm))
    # tampa: 3 tábuas e 2 travessas por fora; fechada em cima e girada 105° na dobradiça de trás
    tampa = []
    zt0 = zt + 0.001
    for k in range(3):
        y = -Ly / 2 + Ly / 6 + k * Ly / 3
        tampa.append(
            tabua(f"tampa{k}", (Lx, Ly / 3 - 0.003, T), (0, y, zt0 + T / 2), od, sem=10 + k)
        )
    for s in (-1, 1):
        tampa.append(
            tabua(
                f"travessa{s}", (0.05, Ly - 0.01, 0.016), (s * 0.2, 0, zt0 + T + 0.008), od, sem=14
            )
        )
    rot_tampa = math.pi  # texto de cima com o alto para a frente: em pé, fica direito por trás
    tampa.append(
        letreiro_z(
            "AMMUNITION",
            0.03,
            amarelo,
            Matrix.Translation((0, -0.075, zt0 + T + 0.0004)) @ Matrix.Rotation(rot_tampa, 4, "Z"),
        )
    )
    tampa.append(
        letreiro_z(
            "7.62 MM",
            0.05,
            amarelo,
            Matrix.Translation((0, 0.005, zt0 + T + 0.0004)) @ Matrix.Rotation(rot_tampa, 4, "Z"),
        )
    )
    # por dentro (madeira à vista quando aberta): a lista de embarque em branco
    for txt, y, h in (
        ("1200 CTGS  7.62 MM  M80", -0.035, 0.018),
        ("LOT LC-47-65", 0.0, 0.018),
        ("INSPECTED  9-65", 0.035, 0.014),
    ):
        tampa.append(
            letreiro_z(
                txt,
                h,
                branco,
                Matrix.Translation((0, y, zt0 - 0.0004)) @ Matrix.Rotation(math.pi, 4, "X"),
            )
        )
    # dobradiças (por fora, atrás)
    for s in (-1, 1):
        tampa.append(
            B.bloco(
                "dobradica_t",
                (0.04, 0.07, 0.003),
                (s * 0.2, Ly / 2 - 0.035, zt0 + T + 0.0015),
                ferragem,
            )
        )
        objs.append(
            B.bloco(
                "dobradica_c", (0.04, 0.003, 0.05), (s * 0.2, Ly / 2 + 0.0015, zt - 0.025), ferragem
            )
        )
        objs.append(
            B.vara(
                "pino",
                (s * 0.2 - 0.02, Ly / 2 + 0.003, zt + 0.002),
                (s * 0.2 + 0.02, Ly / 2 + 0.003, zt + 0.002),
                0.004,
                mat=ferragem,
                segs=8,
            )
        )
    eixo_y, eixo_z = Ly / 2 + 0.003, zt + 0.002
    giro = (
        Matrix.Translation((0, eixo_y, eixo_z))
        @ Matrix.Rotation(math.radians(-105), 4, "X")
        @ Matrix.Translation((0, -eixo_y, -eixo_z))
    )
    mover_todos(tampa, giro)
    objs += tampa
    # latas M19A1: em pé, comprido em Y; a 2 e a 5 abertas (tampa virada 180° na dobradiça do lado
    # +X, deitada sobre a vizinha) com 8 carregadores de M14 cada
    x0 = -ix / 2 + folga + LW / 2
    abertas = (1, 4)
    for i in range(n_latas):
        x = x0 + i * (LW + folga)
        corpo_h = LH - 0.012
        if i in abertas:
            objs.append(caixa_aberta("lata", (LW, LL, corpo_h), (x, 0, zf + corpo_h / 2), lata))
            for j in range(8):
                y = -0.108 + j * 0.031
                zc = zf + 0.07 + 0.065 + 0.004 * ((j * 37) % 3)
                objs.append(
                    B.bloco("carregador", (0.075, 0.025, 0.13), (x, y, zc), pente, chanfro=0.0018)
                )
                objs.append(
                    B.bloco(
                        "labio",
                        (0.06, 0.016, 0.006),
                        (x - 0.004, y, zc + 0.068),
                        pente,
                        chanfro=0.001,
                    )
                )
                cart = cartucho_762("cart", met)
                mover_todos(cart, Matrix.Translation((x + 0.034, y, zc + 0.065 + 0.006)))
                objs += cart
        else:
            objs.append(
                B.bloco(
                    "lata", (LW, LL, corpo_h), (x, 0, zf + corpo_h / 2), lata, chanfro=0.004, segs=2
                )
            )
        # tampa: fechada em cima ou virada sobre a vizinha
        tp = [
            B.bloco(
                "tampa_lata",
                (LW + 0.003, LL + 0.003, 0.022),
                (x, 0, zf + LH - 0.011),
                lata,
                chanfro=0.004,
                segs=2,
            )
        ]
        tp.append(
            B.bloco("alca_lata", (0.014, 0.12, 0.004), (x, 0, zf + LH + 0.002), lata, chanfro=0.001)
        )
        tp.append(
            B.bloco(
                "trava",
                (0.045, 0.006, 0.05),
                (x, -LL / 2 - 0.004, zf + LH - 0.03),
                lata,
                chanfro=0.0015,
            )
        )
        tp.append(
            letreiro_z(
                "7.62MM",
                0.016,
                amarelo_lata,
                Matrix.Translation((x, -0.06, zf + LH + 0.0005))
                @ Matrix.Rotation(math.pi / 2, 4, "Z"),
            )
        )
        tp.append(
            letreiro_z(
                "M19A1",
                0.012,
                amarelo_lata,
                Matrix.Translation((x, 0.07, zf + LH + 0.0005))
                @ Matrix.Rotation(math.pi / 2, 4, "Z"),
            )
        )
        if i in abertas:
            hx, hz = x + LW / 2 + folga / 2, zf + LH
            vira = (
                Matrix.Translation((hx, 0, hz + 0.0092))
                @ Matrix.Rotation(math.radians(178), 4, "Y")
                @ Matrix.Translation((-hx, 0, -hz))
            )
            mover_todos(tp, vira)
        objs += tp
    # duas M26 deitadas nas latas fechadas 1 e 4 (alavanca para cima)
    for i, ang in ((0, 0.25), (3, -0.35)):
        x = x0 + i * (LW + folga)
        g = N.receita_grenade_m26()
        # em pé no eixo Z com a alavanca em +X: gira -90° em Z (alavanca em -Y) e deita em X
        # (o eixo vai para +Y e a alavanca para cima)
        mover_todos(
            g,
            Matrix.Translation((x, -0.02, zf + LH + 0.0045 + 0.0285))
            @ Matrix.Rotation(ang, 4, "Z")
            @ Matrix.Rotation(-math.pi / 2, 4, "X")
            @ Matrix.Rotation(-math.pi / 2, 4, "Z")
            @ Matrix.Translation((0, 0, -0.05)),
        )
        objs += g
    for o in objs:
        r.add(o, "Principal", "Caixa")
    # colisão: o corpo do caixote até o topo do que está dentro (a tampa aberta fica de fora)
    r.caixa_lim(
        "Caixa",
        (-Lx / 2 - 0.035, -Ly / 2, 0.0),
        (Lx / 2 + 0.035, Ly / 2, zt + 0.03),
        "para",
        "Wood",
    )
    r.extras["icone_m"] = [0.0, 0.0, zt + 0.55]
    r.extras["pegada_studs"] = [round((Lx + 0.07) / STUD, 2), round((Ly + 0.12) / STUD, 2)]
    return r


# =============================================================== VC
def carregador_56(mat, met):
    """Carregador curvo do Tipo 56 deitado de lado (curva no plano YZ antes de deitar), com o
    cartucho de cima."""
    R, comp = 0.36, 0.205
    ang = comp / R
    caminho = []
    for k in range(13):
        a = -ang / 2 + ang * k / 12
        caminho.append((0.0, R * math.sin(a), R - R * math.cos(a)))
    corpo = loft_curvo("pente56", caminho, 0.013, 0.031, mat, n_exp=5.0, k=16)
    # nervuras de reforço dos lados
    nerv = []
    for s in (-1, 1):
        nerv.append(loft_curvo("nervura", caminho[1:-1], 0.0025, 0.012, mat, n_exp=3.0, k=10))
        M.mover(nerv[-1], Matrix.Translation((s * 0.0125, 0, 0)))
    # o cartucho de cima (na ponta y > 0), atravessado na boca (ao longo da normal da curva)
    pa = Vector(caminho[-1])
    a_fim = ang / 2
    tang = Vector((0, math.cos(a_fim), math.sin(a_fim)))
    cart = cartucho_762("cart56", met, comp_estojo=0.039, r=0.0056, bala=0.020)
    mover_todos(
        cart,
        Matrix.Translation(pa + tang * 0.0045)
        @ Matrix.Rotation(a_fim, 4, "X")
        @ Matrix.Rotation(math.pi / 2, 4, "Y")
        @ Matrix.Translation((0.0295, 0, 0)),
    )
    pecas = [corpo, *nerv, *cart]
    # deitado de lado: o eixo lateral X vira Z
    mover_todos(pecas, Matrix.Rotation(math.pi / 2, 4, "Y"))
    return pecas


def receita_caixa_municao_vc():
    """Caixote chinês de madeira clara, tampa encostada atrás, lata aberta, carregadores e
    granadas de cabo."""
    r = B.Receita()
    pinho_x = N.mat_madeira("caixa_vc_pinho_x", "#cdb388", "#a2825a", "#a59c88", eixo="X", rug=0.8)
    pinho_y = N.mat_madeira("caixa_vc_pinho_y", "#cdb388", "#a2825a", "#a59c88", eixo="Y", rug=0.8)
    corda = N.mat_corda("caixa_vc_corda", "#a08e63")
    zinco = N.mat_aco("lata_zinco", "#767873", 0.5, 400.0)
    papel = mat_papel("pacote_papel")
    pente = N.mat_aco("carregador_56", "#33363b", 0.55, 500.0)
    met = mats_metal()
    preto = N.mat_estencil("estencil_preto", "#1d1b18", "#c0a57b", gasto=0.3, escala=220.0)
    vermelho = N.mat_estencil("pincel_vermelho", "#8e2a1e", "#c0a57b", gasto=0.45, escala=160.0)
    papel_tinta = N.mat_estencil("pacote_tinta", "#3a2e22", "#9c8158", gasto=0.2, escala=400.0)

    T = 0.02
    TW, TL, TH = 0.265, 0.292, 0.17  # lata (X, Y, Z)
    folga = 0.006
    ix = 2 * TW + 3 * folga
    iy = TL + 2 * folga
    Lx, Ly = ix + 2 * T, iy + 2 * T
    Hc = T + TH + 0.008
    zf = T
    zt = Hc
    objs = []
    objs.append(tabua("fundo", (Lx, Ly, T), (0, 0, T / 2), pinho_x, sem=21))
    for s in (-1, 1):
        y = s * (Ly / 2 - T / 2)
        meia = (Hc - T) / 2
        for k in range(2):
            objs.append(
                tabua(
                    f"lado{s}{k}",
                    (Lx, T, meia - 0.002),
                    (0, y, zf + meia * (k + 0.5)),
                    pinho_x,
                    sem=22 + k,
                )
            )
        x = s * (Lx / 2 - T / 2)
        objs.append(
            tabua(
                f"cab{s}",
                (T, Ly - 2 * T, Hc - T),
                (x, 0, zf + (Hc - T) / 2),
                pinho_y,
                0.002,
                sem=25,
            )
        )
        for t in (-1, 1):
            objs.append(
                tabua(
                    f"sarrafo{s}{t}",
                    (0.022, 0.05, Hc - 0.004),
                    (s * (Lx / 2 + 0.011), t * 0.1, Hc / 2),
                    pinho_y,
                    sem=26,
                )
            )
        objs.append(corda_alca(s * (Lx / 2 + 0.022), s, zt - 0.05, 0.1, corda))
    # pregos das tábuas da frente e de trás
    prego = N.mat_aco("prego_vc", "#3a3833", 0.6, 400.0)
    for s in (-1, 1):
        for x in (-Lx / 2 + 0.01, Lx / 2 - 0.01):
            for z in (0.06, 0.15):
                pg = M.torno(
                    "prego", [(0.0, 0.0), (0.0022, 0.0), (0.0022, 0.0006), (0.0, 0.0009)], segs=8
                )
                M.mover(
                    pg,
                    Matrix.Translation((x, s * (Ly / 2), z))
                    @ Matrix.Rotation(-s * math.pi / 2, 4, "X"),
                )
                objs.append(M.material(pg, prego))
    # marcas: frente em chinês (preto), cabeceiras "ĐẠN 7,62" a pincel
    yf = -Ly / 2 - 0.0004
    objs.append(
        N.letreiro_plano(
            "56式 7.62 普通弹", 0.03, preto, (0, yf, zt - 0.04), "-Y", fonte=FONTE_CHINES
        )
    )
    objs.append(
        N.letreiro_plano("1440发", 0.045, preto, (0, yf, zt - 0.1), "-Y", fonte=FONTE_CHINES)
    )
    objs.append(N.letreiro_plano("311 - 65", 0.02, preto, (0, yf, zf + 0.025), "-Y"))
    for s, nrm in ((-1, "-X"), (1, "+X")):
        objs.append(
            N.letreiro_plano(
                "ĐẠN 7,62",
                0.026,
                vermelho,
                (s * (Lx / 2 + 0.023), 0, zt - 0.12),
                nrm,
                fonte=FONTE_VIET,
            )
        )
    # tampa arrancada, encostada atrás (outra face com as marcas para trás)
    tampa = []
    for k in range(3):
        y = -Ly / 2 + Ly / 6 + k * Ly / 3
        tampa.append(
            tabua(f"tampa{k}", (Lx, Ly / 3 - 0.003, T), (0, y, T / 2), pinho_x, sem=30 + k)
        )
    for s in (-1, 1):
        tampa.append(
            tabua(
                f"travessa{s}", (0.05, Ly - 0.01, 0.018), (s * 0.2, 0, T + 0.009), pinho_y, sem=34
            )
        )
    tampa.append(
        letreiro_z(
            "1440发",
            0.05,
            preto,
            Matrix.Translation((0, 0, T + 0.0004)) @ Matrix.Rotation(math.pi, 4, "Z"),
            FONTE_CHINES,
        )
    )
    # em pé atrás, encostada na borda de trás: a face de dentro (z = 0) no plano que passa pela
    # quina de cima da parede de trás; a de fora (marcas) vira para +Y, 22° para trás do vertical
    incl = math.radians(22)
    y_pe = Ly / 2 + zt * math.tan(incl) + 0.002
    mover_todos(
        tampa,
        Matrix.Translation((0, y_pe - (Ly / 2) * math.sin(incl), (Ly / 2) * math.cos(incl)))
        @ Matrix.Rotation(-(math.pi / 2 - incl), 4, "X"),
    )
    objs += tampa
    # latas: a da esquerda aberta (tampa cortada e dobrada para cima, para o lado de fora) com os
    # pacotes de papel
    xa = -TW / 2 - folga / 2
    xb = -xa
    objs.append(
        caixa_aberta(
            "lata_a", (TW, TL, TH), (xa, 0, zf + TH / 2), zinco, chanfro=0.002, parede=0.0008
        )
    )
    for i in range(5):
        for j in range(5):
            px = xa - TW / 2 + 0.03 + i * 0.051
            py = -TL / 2 + 0.034 + j * 0.056
            dz = 0.003 * ((i + 2 * j) % 3)
            objs.append(
                B.bloco(
                    "pacote",
                    (0.047, 0.052, 0.032),
                    (px, py, zf + TH - 0.022 + dz),
                    papel,
                    chanfro=0.003,
                )
            )
            if (i + j) % 2 == 0:
                objs.append(
                    letreiro_z(
                        "7.62",
                        0.008,
                        papel_tinta,
                        Matrix.Translation((px, py, zf + TH - 0.0055 + dz)),
                    )
                )
    aba = B.bloco("aba", (TW - 0.01, TL - 0.06, 0.0012), (0, 0, 0), zinco)
    hx, hz = xa - TW / 2 + 0.008, zf + TH
    M.mover(
        aba,
        Matrix.Translation((hx, 0, hz))
        @ Matrix.Rotation(math.radians(-110), 4, "Y")
        @ Matrix.Translation(((TW - 0.01) / 2, 0, 0)),
    )
    objs.append(aba)
    # lata fechada com a alça de arame (atrás, longe dos carregadores)
    objs.append(B.bloco("lata_b", (TW, TL, TH), (xb, 0, zf + TH / 2), zinco, chanfro=0.002))
    objs.append(
        B.bloco(
            "costura",
            (TW + 0.002, TL + 0.002, 0.004),
            (xb, 0, zf + TH - 0.01),
            zinco,
            chanfro=0.001,
        )
    )
    ya = TL / 2 - 0.02
    al = M.tubo(
        "alca_arame",
        [
            (xb - 0.05, ya, zf + TH),
            (xb - 0.04, ya, zf + TH + 0.006),
            (xb + 0.04, ya, zf + TH + 0.006),
            (xb + 0.05, ya, zf + TH),
        ],
        0.002,
        6,
    )
    objs.append(M.material(al, zinco))
    # 3 carregadores deitados lado a lado na lata fechada; uma granada de cabo em cima deles e
    # outra nos pacotes da lata aberta
    for k, (dx, dy, rz) in enumerate(
        ((-0.08, -0.03, 0.06), (0.0, -0.02, -0.04), (0.08, -0.035, 0.08))
    ):
        pc = carregador_56(pente, met)
        mover_todos(
            pc,
            Matrix.Translation((xb + dx, dy, zf + TH + 0.0152 + 0.001 * k))
            @ Matrix.Rotation(rz, 4, "Z"),
        )
        objs += pc
    for x, y, rz, z in ((xa, -0.07, 0.15, zf + TH + 0.029), (xb, -0.095, -0.12, zf + TH + 0.059)):
        g = N.receita_grenade_stick()
        mover_todos(
            g,
            Matrix.Translation((x, y, z))
            @ Matrix.Rotation(rz, 4, "Z")
            @ Matrix.Translation((-0.105, 0, 0)),
        )
        objs += g
    for o in objs:
        r.add(o, "Principal", "Caixa")
    r.caixa_lim(
        "Caixa",
        (-Lx / 2 - 0.035, -Ly / 2, 0.0),
        (Lx / 2 + 0.035, Ly / 2, zt + 0.04),
        "para",
        "Wood",
    )
    r.extras["icone_m"] = [0.0, 0.0, zt + 0.6]
    r.extras["pegada_studs"] = [round((Lx + 0.07) / STUD, 2), round((Ly + 0.2) / STUD, 2)]
    return r


RECEITAS = {
    "caixa_municao_us": receita_caixa_municao_us,
    "caixa_municao_vc": receita_caixa_municao_vc,
}


# =============================================================== prévia do GLB
def previa_final(chave: str) -> None:
    """`_previa.png`: o GLB (só o nó visual, face única) de perto em 2 ângulos e, embaixo, como
    aparece a 15 m numa tela de 1920 px com 70° de campo (recorte ampliado 4x)."""
    import json

    import apresentar as A
    import comparar as K

    pasta = C.SAIDA / chave
    trab = C.TRABALHO / chave
    trab.mkdir(parents=True, exist_ok=True)
    met = json.loads((pasta / "metricas.json").read_text("utf-8"))
    cena = C.cena_vazia()
    K.configurar(cena, 48)
    cena.cycles.device = "CPU"
    cena.cycles.denoiser = "OPENIMAGEDENOISE"
    piso = C.chao(tamanho=200.0, z=0.0)
    piso.data.materials.append(A.chao_leve())
    nos = A.importar_nos(C.RAIZ / met["novo"]["arquivo"])
    vis = [o for n, o in nos.items() if not n.startswith(("Colisao", "Zona"))]
    for n, o in nos.items():
        if n.startswith(("Colisao", "Zona")):
            bpy.data.objects.remove(o)
    for o in vis:
        K.face_unica(o)
    pts = K.pontos(vis, 8000)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    paineis = []
    for az in (25.0, 205.0):
        cam, _ = K.camera(lo, hi, az, pts)
        s = K.sol(az + 70.0)
        paineis.append(K.renderizar(trab / f"previa_{int(az)}.png"))
        bpy.data.objects.remove(cam)
        bpy.data.objects.remove(s)
    # longe: 15 m, olho a 1,6 m, 1920 x 1080 com 70° de campo horizontal; só o recorte em volta
    cena.render.resolution_x, cena.render.resolution_y = 1920, 1080
    cd = bpy.data.cameras.new("Longe")
    cd.sensor_fit = "HORIZONTAL"
    cd.angle = math.radians(70)
    cam = bpy.data.objects.new("Longe", cd)
    cena.collection.objects.link(cam)
    alvo = Vector((0, 0, 0.15))
    pos = Vector((0.45 * 15, -0.89 * 15, 1.6))
    cam.location = pos
    cam.rotation_euler = (alvo - pos).to_track_quat("-Z", "Y").to_euler()
    cena.camera = cam
    s = K.sol(25.0 + 70.0)
    lado = 240  # recorte de 240 x 180 px em volta do centro
    cena.render.use_border = True
    cena.render.use_crop_to_border = True
    cena.render.border_min_x = 0.5 - lado / 2 / 1920
    cena.render.border_max_x = 0.5 + lado / 2 / 1920
    cena.render.border_min_y = 0.5 - 90 / 1080
    cena.render.border_max_y = 0.5 + 90 / 1080
    longe = K.renderizar(trab / "previa_15m.png")
    cena.render.use_border = False
    h, w = K.ALT, K.LARG
    ampl = np.repeat(np.repeat(longe, 4, axis=0), 4, axis=1)  # vizinho mais próximo
    sep = 6
    total = np.ones((h + ampl.shape[0] + sep, 2 * w + sep, 4), np.float32)
    total[..., :3] = 0.08
    topo = ampl.shape[0] + sep
    total[topo : topo + h, 0:w] = paineis[0]
    total[topo : topo + h, w + sep : 2 * w + sep] = paineis[1]
    x0 = (2 * w + sep - ampl.shape[1]) // 2
    total[0 : ampl.shape[0], x0 : x0 + ampl.shape[1]] = ampl
    out = bpy.data.images.new("previa", total.shape[1], total.shape[0], alpha=False)
    C.gravar_pixels(out, total)
    C.salvar_imagem(out, pasta / "_previa.png", "PNG")
    C.log("ok", chave, "prévia final", pasta / "_previa.png")


# =============================================================== entrada
def montar(chave: str):
    if chave in RECEITAS:
        r = RECEITAS[chave]()
        return r, bases.normalizar(r)
    return _montar_bases(chave)


_montar_bases = bases.montar


def main() -> None:
    a = C.argumentos()
    chave = a[0]
    if "--previa-final" in a:
        previa_final(chave)
        return
    bases.BASES.update(CAIXAS)
    bases.USO.update({k: USO for k in CAIXAS})
    bases.montar = montar  # o bases.main chama montar() pelo nome global do módulo
    bases.main()


if __name__ == "__main__":
    main()
