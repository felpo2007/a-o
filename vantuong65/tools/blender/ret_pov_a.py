"""Povoado da Vila (D-255): marcos e comércio. Metros, Z para cima, frente em -Y.

Cada construção tem identidade e função no combate: o templo dá um pátio cercado com várias
entradas; o mercado, corredores estreitos e cobertura; as lojas, fundos ligados ao quintal.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_comum as E  # noqa: E402
import exp_vila as X  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
import ret_comboio as RC  # noqa: E402
import ret_mercado as RM  # noqa: E402
import ret_pov_kit as K  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from ret_pov_kit import B, T, Vg  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

# toldos de cor, como no mercado da referência
AZUL = (("#3f6785", "#6f94ad"), ("#456c89", "#7498b0"))
VERMELHO = (("#8f3b2e", "#b06a55"), ("#963f31", "#b5705a"))
CRU = (("#b9ad8f", "#d6ccb2"), ("#b2a689", "#cfc5ab"))
OCRE = (("#b08a45", "#cfae70"), ("#a98342", "#c9a86a"))
VERDE = (("#5c7a6c", "#88a091"), ("#607e70", "#8ba394"))


# =============================================================== 1. pagode
def receita_ret_pov_chua():
    """Chùa: salão de dois telhados, altar com três imagens, pátio murado, sino e estátua."""
    rec = V.Receita()
    sem = 901
    mats = Mats(sem)
    LC, WC = 23.0, 19.0
    lat = K.parede("laterita")
    Lh, Wh, H = 12.0, 7.6, 3.4
    cy = 3.6
    ngoi = K.telha("#8f5238", "#623827", "#aa6a4a")
    # o salão, montado na origem e levado para o fundo do pátio
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "c",
        Lh,
        Wh,
        H,
        0.22,
        lat,
        [
            {"lado": "frente", "t": 0.0, "estilo": "folhas"},
            {"lado": "frente", "t": -3.6, "estilo": "folhas"},
            {"lado": "frente", "t": 3.6, "estilo": "folhas"},
            {"lado": "fundo", "t": 4.3, "estilo": "tabua", "folha": -1},
        ],
        K.janelas("esq", (-1.4, 1.4)) + K.janelas("dir", (-1.4, 1.4)),
        col="Brick",
        sem=sem,
    )
    V.telhado(
        rec,
        "tel",
        Lh,
        Wh,
        H,
        H + 2.3,
        1.0,
        "4aguas",
        "ngoi",
        0.1,
        ngoi,
        mats,
        beiral_oitao=1.0,
        sem=sem,
        tesouras=(-3.0, 3.0),
    )
    # o segundo telhado, sobre uma lanterna de madeira
    zl0, zl1 = H + 1.5, H + 2.85
    B(rec, "lanterna", (5.4, 2.7, zl1 - zl0), (0, 0, (zl0 + zl1) / 2), mats.go_escuro, est=True)
    V.telhado(
        rec,
        "tel2",
        5.4,
        2.7,
        zl1,
        zl1 + 1.45,
        0.75,
        "4aguas",
        "ngoi",
        0.09,
        ngoi,
        mats,
        beiral_oitao=0.75,
        sem=sem + 1,
        estrutura=False,
    )
    dourado = V.mat_liso("dourado", "#b58f3f", "#6e5423", rug=0.38, escala=6.0, forca=0.35)
    # pontas curvas dos dois telhados e o ornamento da cumeeira
    for sx in (-1, 1):
        for sy in (-1, 1):
            ang = math.atan2(sy, sx)
            K.dao(
                rec,
                f"dao_a{sx}{sy}",
                sx * (Lh / 2 + 0.95),
                sy * (Wh / 2 + 0.95),
                K.z_beiral(H, H + 2.3, Wh, 1.0),
                ang,
                ngoi,
            )
            K.dao(
                rec,
                f"dao_b{sx}{sy}",
                sx * 3.4,
                sy * 2.05,
                K.z_beiral(zl1, zl1 + 1.45, 2.7, 0.75),
                ang,
                ngoi,
                comp=0.8,
            )
    zc = zl1 + 1.45
    for s in (-1, 1):
        pts = [
            (s * 1.32, 0, zc + 0.04),
            (s * 1.55, 0, zc + 0.14),
            (s * 1.72, 0, zc + 0.36),
            (s * 1.66, 0, zc + 0.52),
        ]
        o = V.tubo_local(f"rabo{s}", pts, [0.1, 0.09, 0.07, 0.03], dourado, segs=5)
        rec.add(o, "Telhado", "Telhado")
    rec.add(RM._bola("perola", (0, 0, zc + 0.3), 0.2, dourado), "Telhado", "Telhado")
    T(rec, "perola_p", (0, 0, zc), (0, 0, zc + 0.14), 0.05, dourado)
    # colunas vermelhas da frente
    yv = -Wh / 2 - 1.9
    V.nen(rec, "nen_v", -Lh / 2 - 0.2, yv - 0.2, Lh / 2 + 0.2, -Wh / 2, mats)
    for k, x in enumerate((-Lh / 2, -2.0, 2.0, Lh / 2)):
        T(rec, f"col_v{k}", (x, yv + 0.1, PISO), (x, yv + 0.1, 2.75), 0.14, mats.laca, segs=8)
        B(rec, f"bcol{k}", (0.42, 0.42, 0.14), (x, yv + 0.1, PISO + 0.07), mats.pedra)
        rec.caixa(f"col_v{k}", (x, yv + 0.1, 1.4), (0.3, 0.3, 2.8), "para", "Wood")
    Vg(
        rec,
        "fre_v",
        (-Lh / 2 - 0.1, yv + 0.1, 2.78),
        (Lh / 2 + 0.1, yv + 0.1, 2.78),
        0.14,
        0.16,
        mats.go_escuro,
    )
    V.agua_unica(
        rec,
        "tel_v",
        -Lh / 2 - 0.4,
        Lh / 2 + 0.4,
        -Wh / 2 + 0.02,
        3.5,
        yv - 0.5,
        2.84,
        0.1,
        "ngoi",
        ngoi,
        mats,
        sem=sem + 5,
    )
    K.letreiro(rec, "placa", "CHÁNH ĐIỆN", (0.0, -Wh / 2 - 0.05, 3.05), larg=3.0, alt=0.5)
    # o altar em degraus, com as três imagens
    yi = Wh / 2 - 0.22
    for k, (lg, pf, zz) in enumerate(((7.0, 1.9, 0.5), (5.4, 1.3, 1.0), (3.6, 0.8, 1.45))):
        y = yi - pf / 2
        B(rec, f"deg{k}", (lg, pf, zz), (0, y, PISO + zz / 2), mats.laca, chanfro=0.02)
    rec.caixa("altar", (0, yi - 0.95, PISO + 0.72), (7.0, 1.9, 1.45), "para", "Wood")
    K.buda(rec, "buda_c", 0.0, yi - 0.42, PISO + 1.45, 0.95, dourado)
    for s in (-1, 1):
        K.buda(rec, f"buda{s}", s * 1.75, yi - 0.65, PISO + 1.0, 0.72, dourado)
        K.incensario(rec, f"inc{s}", s * 2.9, yi - 1.35, mats, z=PISO + 0.5, e=0.42)
    V.ban_tho(
        rec,
        "mesa_of",
        (0.0, yi - 2.6),
        0,
        mats,
        comp=2.2,
        prof=0.6,
        alt=1.0,
        rico=True,
        painel=False,
    )
    for k, (x, y) in enumerate(((-4.7, 0.9), (4.7, 0.9), (-4.7, -2.5), (4.7, -2.5))):
        T(rec, f"col_i{k}", (x, y, PISO), (x, y, H), 0.15, mats.laca, segs=8)
        rec.caixa(f"col_i{k}", (x, y, H / 2), (0.3, 0.3, H), "para", "Wood")
    rec.transformar(marca, V.lugar((0.0, cy, 0.0)))
    # o muro do pátio, com o portão e duas entradas laterais
    a, b = LC / 2, WC / 2
    for nome, p, q in (
        ("m_f1", (-a, -b), (-4.0, -b)),
        ("m_f2", (4.0, -b), (a, -b)),
        ("m_e1", (-a, -b), (-a, -3.2)),
        ("m_e2", (-a, -1.1), (-a, b)),
        ("m_d1", (a, -b), (a, -3.2)),
        ("m_d2", (a, -1.1), (a, b)),
        ("m_t1", (-a, b), (5.0, b)),
        ("m_t2", (6.9, b), (a, b)),
    ):
        K.muro(rec, mats, nome, p, q, 1.45, lat)
    K.tam_quan(rec, mats, sem + 2, "portao", 0.0, -b, lat, ngoi, dourado)
    # caminho, incensário, estátua e sino
    V.nen(rec, "caminho", -1.2, -b + 0.2, 1.2, cy - Wh / 2 - 2.1, mats)
    K.incensario(rec, "dinh", 0.0, -3.0, mats, e=1.25)
    B(rec, "base_est", (1.5, 1.5, 0.7), (-7.6, -4.8, 0.35), mats.pedra, chanfro=0.04)
    rec.caixa("base_est", (-7.6, -4.8, 0.35), (1.5, 1.5, 0.7), "para", "Brick")
    cal = V.mat_liso("marmore", "#cfc9b7", "#938d7c", rug=0.6, escala=7.0, forca=0.3)
    K.buda(rec, "quan_am", -7.6, -4.8, 0.7, 1.05, cal)
    RC._sino(rec, 8.2, -5.0, mats)
    K.torre_chua(rec, mats, sem + 6, "torre_e", -9.3, 2.0, lat, ngoi)
    K.torre_chua(rec, mats, sem + 8, "torre_d", 9.3, 2.0, lat, ngoi)
    for s in (-1, 1):
        K.leao(rec, f"leao{s}", s * 2.75, -b - 1.05, 0, mats, cal, e=0.95)
    VC.camera(rec, (-4.6, cy - 1.5, PISO + 1.6), (0.0, cy + 3.0, PISO + 1.6))
    return rec


# =============================================================== 3. mercado
def _bancas_dentro(rec, mats, L):
    """Bancadas nas duas fileiras, com corredores estreitos entre elas."""
    frutas = (
        V.mat_liso("fruta_manga", "#c79a35", "#8a7a2b", rug=0.55),
        V.mat_liso("fruta_verde", "#6f8a3a", "#4c6a2c", rug=0.6),
        V.mat_liso("fruta_verm", "#a8452f", "#7b2f22", rug=0.5),
    )
    n = 3
    passo = (L - 1.2) / n
    for f, y in enumerate((-2.6, 2.6)):
        for i in range(n):
            x = -L / 2 + 0.6 + passo * (i + 0.5)
            RM._balcao(rec, f"bal{f}{i}", x, y, passo - 1.0, 1.05, 0.84, mats)
            for j in range(3):
                dx = (j - 1) * (passo - 1.5) / 3
                RM._tabuleiro(rec, f"tb{f}{i}{j}", x + dx, y, 0.84, 0.72, 0.62, mats)
                RM._monte(
                    rec,
                    f"mt{f}{i}{j}",
                    x + dx,
                    y,
                    0.865,
                    0.6,
                    0.5,
                    frutas[(i + j + f) % 3],
                    r=0.065,
                    filas=2,
                    sem=i + j + 1.0,
                )
            X._cesto(rec, f"ces{f}{i}", (x - passo / 2 + 0.6, y + (0.95 if y > 0 else -0.95)), mats)


def receita_ret_pov_mercado():
    """Chợ: pavilhão aberto de madeira e palha, com duas fileiras de bancas e corredor no meio."""
    rec = V.Receita()
    sem = 902
    mats = Mats(sem)
    L, W, H = 15.0, 9.2, 3.0
    V.nen(rec, "nen", -L / 2 - 0.2, -W / 2 - 0.2, L / 2 + 0.2, W / 2 + 0.2, mats)
    nx = 5
    for i in range(nx + 1):
        x = -L / 2 + i * L / nx
        for j, y in enumerate((-W / 2, 0.0, W / 2)):
            if j == 1 and i not in (0, nx):
                continue
            V.poste(rec, f"p{i}{j}", x, y, H, mats.go_escuro, r=0.12, base_pedra=mats.pedra)
    for s in (-1, 1):
        y = s * W / 2
        Vg(rec, f"fre{s}", (-L / 2 - 0.1, y, H), (L / 2 + 0.1, y, H), 0.16, 0.18, mats.go)
    cume = H + 1.3
    T(
        rec,
        "cume",
        (-L / 2 - 0.2, 0, cume),
        (L / 2 + 0.2, 0, cume),
        0.07,
        mats.go_escuro,
        est=True,
        segs=6,
    )
    for i in range(nx + 1):
        x = -L / 2 + i * L / nx
        T(rec, f"pend{i}", (x, 0, H), (x, 0, cume), 0.07, mats.go, est=True, segs=6)
        Vg(rec, f"linha{i}", (x, -W / 2, H), (x, W / 2, H), 0.12, 0.14, mats.go)
        for s in (-1, 1):
            T(
                rec,
                f"caibro{i}{s}",
                (x, s * (W / 2 + 0.4), H - 0.15),
                (x, 0, cume),
                0.05,
                mats.tre,
                est=True,
            )
    paletas = (AZUL, CRU, VERMELHO, OCRE, VERDE)
    for i in range(nx):
        x0 = -L / 2 + i * L / nx
        panos = RM._panos(sem + 20 + i, paletas[i % len(paletas)])
        for s in (-1, 1):
            RM._toldo(
                rec,
                f"lona{i}{'a' if s < 0 else 'b'}",
                x0 + 0.02,
                x0 + L / nx - 0.02,
                0.0,
                cume + 0.06,
                s * (W / 2 + 0.55),
                H - 0.2,
                panos,
                queda=0.07,
            )
    rec.caixa("lona", (0, 0, H + 0.75), (L + 0.6, W + 0.9, 0.1), "passa", "Fabric")
    _bancas_dentro(rec, mats, L)
    # panos pendurados nas vigas e cestos no corredor
    tons = (("#7d3c34", "#a56a5c"), ("#3f5f6f", "#6b8894"), ("#a8843f", "#c9ad70"))
    panos = [N.mat_pano(f"tec{k}", cor=a, desbotado=b) for k, (a, b) in enumerate(tons)]
    for k, x in enumerate((-5.9, -5.2, 4.9, 5.7)):

        def f(u, v, x0=x, n0=k):
            return (
                x0 - 0.3 + u * 0.6,
                -W / 2 + 0.08 + 0.02 * math.sin(u * 9.0 + n0),
                2.85 - v * 1.5,
            )

        o = V.grade(f"pano{k}", f, 3, 2, fora=(0, -1, 0))
        M.solidificar(o, 0.01, 0.0)
        V.gravar_uv_local(o, lambda p: (p.x, p.z, p.y), k * 0.6)
        M.material(o, panos[k % len(panos)])
        rec.add(M.suave(o, 60), "Mobilia", "Mobilia")
    for k, (x, y) in enumerate(((-6.8, -0.9), (6.7, 0.8), (-0.4, 4.2))):
        X._pote(rec, f"pote{k}", (x, y), mats, alt=0.62, r=0.26, sem=k + 3)
    K.letreiro(rec, "placa", "CHỢ VẠN TƯỜNG", (0.0, -W / 2 - 0.06, H - 0.32), larg=3.6, alt=0.5)
    VC.camera(rec, (-6.6, -0.4, 1.65), (5.0, 0.2, 1.1))
    return rec


def _banca(sem, panos, miolo):
    rec = V.Receita()
    mats = Mats(sem)
    L, W = 3.9, 2.7
    z_frente, z_fundo = 2.48, 2.86
    RM._armacao(rec, L, W, z_frente, z_fundo, mats)
    RM._toldo(
        rec,
        "toldo",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        W / 2 + 0.25,
        z_fundo + 0.1,
        -W / 2 - 0.5,
        z_frente - 0.14,
        RM._panos(sem, panos),
    )
    miolo(rec, mats, L, W)
    VC.camera(rec, (-1.6, -3.4, 1.6), (0.3, 0.2, 0.95))
    return rec


def _miolo_peixe(rec, mats, L, W):
    """Peixe seco em esteiras e molho de peixe (nước mắm) em potes."""
    RM._balcao(rec, "balcao", 0.0, -0.3, L - 0.5, 1.05, 0.84, mats)
    prata = V.mat_liso("peixe", "#8f8a7a", "#5f5b4c", rug=0.42)
    for k, dx in enumerate((-1.1, 0.0, 1.1)):
        RM._tabuleiro(rec, f"tab{k}", dx, -0.3, 0.84, 0.92, 0.8, mats)
        for j in range(7):
            x = dx - 0.33 + (j % 4) * 0.21
            y = -0.56 + (j // 2) * 0.16 + (k % 2) * 0.03
            o = V.torno_local(
                f"pe{k}{j}", [(0.0, -0.13), (0.035, -0.04), (0.04, 0.05), (0.0, 0.14)], 5, prata
            )
            M.mover(o, Matrix.Translation((x, y, 0.9)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
            K._mob(rec, o)
    for k, x in enumerate((-1.3, -0.65, 0.0, 0.7)):
        X._pote(
            rec, f"pote{k}", (x, W / 2 - 0.42), mats, alt=0.66, r=0.28, tampa="madeira", sem=k + 4
        )
    for k, x in enumerate((-1.3, -0.45, 0.45, 1.3)):
        T(rec, f"fio{k}", (x, -W / 2, 2.42), (x, -W / 2, 2.0), 0.006, mats.corda, segs=3)
        o = V.torno_local(
            f"seco{k}", [(0.0, -0.17), (0.05, -0.05), (0.05, 0.08), (0.0, 0.17)], 5, prata
        )
        M.mover(o, Matrix.Translation((x, -W / 2, 1.84)))
        K._mob(rec, o)


def _miolo_grao(rec, mats, L, W):
    """Arroz, feijão e especiarias em sacos abertos e cestos largos."""
    arroz = mats.arroz
    verm = V.mat_liso("feijao", "#7a3b2c", "#4f261d", rug=0.8, escala=30.0, forca=0.4)
    amarelo = V.mat_liso("curcuma", "#c79a3a", "#916c25", rug=0.85, escala=30.0, forca=0.4)
    RM._balcao(rec, "balcao", 0.0, W / 2 - 0.55, L - 0.4, 0.8, 0.74, mats)
    for k, (x, m) in enumerate(((-1.1, arroz), (0.0, verm), (1.1, amarelo))):
        X._cesto(rec, f"cesto{k}", (x, -0.72), mats, r=0.42, alt=0.42)
        o = V.torno_local(f"grao{k}", [(0.0, 0.42), (0.28, 0.38), (0.36, 0.33), (0.0, 0.3)], 10, m)
        M.mover(o, Matrix.Translation((x, -0.72, 0.0)))
        K._mob(rec, o)
    K.fardos(rec, "sacos", 0.0, 0.1, mats, z=0.0, colunas=4, linhas=2)
    for k, x in enumerate((-1.2, -0.4, 0.4, 1.2)):
        X._cesto(rec, f"cima{k}", (x, W / 2 - 0.5), mats, r=0.2, alt=0.3, z=0.74)


def receita_ret_pov_banca_d():
    return _banca(903, AZUL, _miolo_peixe)


def receita_ret_pov_banca_e():
    return _banca(904, VERMELHO, _miolo_grao)


def receita_ret_pov_banca_f():
    return _banca(912, VERMELHO, RM._banca_frutas)


def receita_ret_pov_banca_g():
    return _banca(913, AZUL, RM._banca_tecidos)


# a escola da referência: reboco amarelo desbotado e telha
def receita_ret_pov_escola():
    return K.RF._ala("ret_pov_escola", 24.0, 7.0, 3, 914, cal="#d9bd6e")


def receita_ret_pov_escola_ala():
    return K.RF._ala("ret_pov_escola_ala", 15.0, 6.6, 2, 915, cal="#d9bd6e")


# =============================================================== lojas
def _loja(sem, L, W, H, tipo, tel, placa, jans=(), porta_fundo=True, forma="2aguas", alto=1.9):
    """Loja de frente aberta: colunas, viga, tabuleta e porta dos fundos para o quintal."""
    rec = V.Receita()
    mats = Mats(sem)
    portas = (
        [{"lado": "fundo", "t": L * 0.28, "estilo": "tabua", "folha": 1}] if porta_fundo else []
    )
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        tipo,
        portas,
        list(jans),
        tel=tel,
        forma=forma,
        alto=alto,
        lados=("fundo", "esq", "dir"),
    )
    n = max(2, round(L / 2.6))
    for k in range(n + 1):
        x = -L / 2 + 0.1 + k * (L - 0.2) / n
        V.poste(rec, f"pil{k}", x, -W / 2 + 0.05, H, mats.go, r=0.1, base_pedra=mats.pedra)
    Vg(rec, "frechal", (-L / 2, -W / 2 + 0.05, H), (L / 2, -W / 2 + 0.05, H), 0.14, 0.16, mats.go)
    K.letreiro(
        rec, "placa", placa, (0.0, -W / 2 - 0.05, H - 0.32), larg=min(L - 0.8, 3.4), alt=0.46
    )
    return rec, mats, xi, yi


def receita_ret_pov_mercearia():
    """Tạp hóa: prateleiras até o teto, balcão, sacos e chapéus pendurados."""
    rec, mats, xi, yi = _loja(
        905, 7.2, 5.4, 3.1, "gach", "tranh", "TẠP HÓA", K.janelas("dir", (0.3,))
    )
    for k, x in enumerate((-2.2, -0.4)):
        X._prateleira(rec, f"est{k}", (x, yi - 0.22), 0, mats, comp=1.7, alt=2.2, z=PISO)
    X._prateleira(rec, "est_e", (-xi + 0.22, 0.3), 90, mats, comp=2.0, alt=2.2, z=PISO)
    K.balcao(rec, "balcao", 0.3, -1.1, 3.0, mats)
    K.fardos(rec, "sacos", 2.3, 1.5, mats, colunas=3, linhas=3)
    for k, (x, y) in enumerate(((-2.8, -1.8), (2.7, -1.7), (2.9, -0.6))):
        X._cesto(rec, f"ces{k}", (x, y), mats, r=0.28, alt=0.42, z=PISO)
    V.potes(rec, "lu", [(-2.9, -0.8), (-2.35, -0.72)], mats, sem=905)
    for k, x in enumerate((-1.1, -0.3, 0.5, 1.3)):
        V.nonla_pendurado(rec, f"non{k}", (x, -2.45), 180, mats, z=2.35)
    VC.camera(rec, (-2.6, -2.5, 1.6), (1.6, 1.8, 1.1))
    return rec


def receita_ret_pov_cha():
    """Quán trà: varanda baixa com mesinhas, bule no fogão e bancos para quem espera."""
    rec = V.Receita()
    sem = 906
    mats = Mats(sem)
    L, W, H = 7.4, 4.6, 2.9
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "phen_par",
        [
            {"lado": "frente", "t": -1.6, "estilo": "liep", "folha": 1},
            {"lado": "fundo", "t": 2.0, "estilo": "liep", "folha": -1},
        ],
        K.janelas("frente", (1.8,)) + K.janelas("esq", (0.0,), 0.9),
        tel="la",
        forma="4aguas",
        alto=2.1,
        esp=0.07,
    )
    yv = K.varanda(rec, mats, sem, L, W, prof=2.5, tel="la")
    K.letreiro(rec, "placa", "QUÁN TRÀ", (0.0, yv + 0.0, 2.32), larg=2.2, alt=0.42)
    for k, x in enumerate((-2.4, 0.2, 2.6)):
        V.ban_thap(
            rec,
            f"mesa{k}",
            (x, yv + 1.2),
            0,
            mats,
            comp=1.1,
            larg=0.7,
            alt=0.42,
            cha=True,
            banquinhos=2,
        )
    V.bep(rec, "bep", (2.6, yi - 0.5), 0, mats)
    V.cho_tre(rec, "cho", (-xi + 0.62, 0.3), 90, mats)
    X._prateleira(rec, "est", (0.2, yi - 0.22), 0, mats, comp=1.5, z=PISO)
    V.potes(rec, "lu", [(xi - 0.4, -yi + 0.45)], mats, sem=906)
    VC.camera(rec, (-L / 2 + 0.3, yv + 0.4, 1.5), (2.6, -W / 2 + 0.2, 0.8))
    return rec


def receita_ret_pov_pho():
    """Quán phở: caldeirão, balcão de tigelas, mesas compridas e bancos, aberto para a rua."""
    rec, mats, xi, yi = _loja(
        907, 8.2, 5.8, 3.1, "vach_cal", "ngoi", "QUÁN PHỞ", K.janelas("esq", (0.2,))
    )
    V.bep(rec, "bep_a", (-2.6, yi - 0.52), 0, mats)
    V.bep(rec, "bep_b", (-1.2, yi - 0.52), 0, mats)
    caldeirao = V.torno_local(
        "caldeirao",
        [
            (0, 0),
            (0.32, 0),
            (0.42, 0.14),
            (0.44, 0.46),
            (0.42, 0.5),
            (0.38, 0.5),
            (0.38, 0.1),
            (0, 0.06),
        ],
        14,
        mats.ferro,
    )
    M.mover(caldeirao, Matrix.Translation((-2.55, yi - 0.52, PISO + 0.24)))
    K._mob(rec, caldeirao)
    rec.caixa("caldeirao", (-2.55, yi - 0.52, PISO + 0.5), (0.9, 0.9, 0.56), "para", "Metal")
    K.balcao(rec, "balcao", 1.6, yi - 0.42, 3.4, mats)
    for k in range(8):
        x = 0.3 + k * 0.36
        o = V.torno_local(
            f"tigela{k}",
            [(0, 0), (0.05, 0), (0.1, 0.05), (0.09, 0.05), (0.04, 0.012), (0, 0.012)],
            8,
            mats.louca,
        )
        M.mover(o, Matrix.Translation((x, yi - 0.42, PISO + 0.93 + (k % 2) * 0.04)))
        K._mob(rec, o)
    for k, x in enumerate((-2.2, 1.0)):
        K.balcao(rec, f"mesa{k}", x, -0.9, 2.3, mats, prof=0.76, alt=0.76)
        X._banco(rec, f"bc_a{k}", (x, -1.62), 0, mats, comp=2.1, z=PISO)
        X._banco(rec, f"bc_b{k}", (x, -0.18), 0, mats, comp=2.1, z=PISO)
    V.potes(rec, "lu", [(xi - 0.45, 0.6), (xi - 0.42, 1.25)], mats, sem=907)
    X._lenha(rec, "lenha", -xi + 0.25, -xi + 1.7, -2.1, mats, z=PISO)
    VC.camera(rec, (3.4, -2.6, 1.6), (-2.2, 1.8, 0.9))
    return rec


def _maquina(rec, nome, x, y, rot, mats):
    """Máquina de costura de pedal sobre mesinha de madeira."""
    m = V.lugar((x, y, PISO), rot)
    o = [V.bloco(f"{nome}_t", (1.0, 0.52, 0.035), (0, 0, 0.76), mats.go, chanfro=0.005)]
    for sx in (-1, 1):
        o.append(V.bloco(f"{nome}_p{sx}", (0.04, 0.46, 0.74), (sx * 0.44, 0, 0.37), mats.ferro))
    o.append(V.bloco(f"{nome}_ped", (0.4, 0.26, 0.025), (0, -0.08, 0.1), mats.ferro))
    o.append(V.bloco(f"{nome}_b", (0.42, 0.13, 0.11), (0.0, 0.04, 0.84), mats.laca, chanfro=0.02))
    o.append(V.bloco(f"{nome}_br", (0.1, 0.12, 0.22), (0.17, 0.04, 0.95), mats.laca, chanfro=0.02))
    o.append(V.bloco(f"{nome}_br2", (0.42, 0.1, 0.08), (0.0, 0.04, 1.04), mats.laca, chanfro=0.02))
    o.append(V.bloco(f"{nome}_ag", (0.08, 0.08, 0.2), (-0.19, 0.04, 0.93), mats.laca))
    for ob in o:
        M.mover(ob, m)
        K._mob(rec, ob)
    V._col_local(rec, nome, (x, y), rot, (x, y, PISO + 0.5), (1.0, 0.52, 1.0), "para", "Wood")


def _manequim(rec, nome, x, y, mats, cor):
    """Busto de costura com a camisa em prova."""
    o = [
        V.tre(f"{nome}_h", (0, 0, 0.05), (0, 0, 0.92), 0.022, mats.go_escuro, segs=5),
        V.torno_local(
            f"{nome}_b",
            [
                (0, 0.82),
                (0.17, 0.86),
                (0.2, 1.08),
                (0.22, 1.3),
                (0.16, 1.42),
                (0.05, 1.46),
                (0, 1.46),
            ],
            8,
            cor,
        ),
        V.bloco(f"{nome}_pe", (0.4, 0.4, 0.04), (0, 0, 0.02), mats.go_escuro),
    ]
    for ob in o:
        M.mover(ob, Matrix.Translation((x, y, PISO)))
        K._mob(rec, ob)
    rec.caixa(nome, (x, y, PISO + 0.74), (0.42, 0.42, 1.46), "passa", "Fabric")


def receita_ret_pov_alfaiate():
    """Tiệm may: duas máquinas, peças de tecido nas prateleiras, bustos e roupas penduradas."""
    rec, mats, xi, yi = _loja(
        908, 6.6, 5.2, 3.1, "van", "tranh", "TIỆM MAY", K.janelas("dir", (0.0,))
    )
    tons = (
        ("#7d3c34", "#a56a5c"),
        ("#3f5f6f", "#6b8894"),
        ("#a8843f", "#c9ad70"),
        ("#56683f", "#82926a"),
        ("#2d2c33", "#55525a"),
    )
    panos = [N.mat_pano(f"tec{k}", cor=a, desbotado=b) for k, (a, b) in enumerate(tons)]
    _maquina(rec, "maq_a", -1.6, -0.4, 10, mats)
    _maquina(rec, "maq_b", 0.5, -0.6, -6, mats)
    _manequim(rec, "bus_a", 2.5, -1.7, mats, panos[0])
    _manequim(rec, "bus_b", -2.8, -1.8, mats, panos[1])
    # estante de rolos no fundo
    for sx in (-1, 1):
        B(
            rec,
            f"est_l{sx}",
            (0.05, 0.45, 2.2),
            (-0.9 + sx * 1.5, yi - 0.25, PISO + 1.1),
            mats.go_escuro,
        )
    for j, z in enumerate((0.45, 1.05, 1.65, 2.2)):
        B(rec, f"est_t{j}", (3.1, 0.45, 0.035), (-0.9, yi - 0.25, PISO + z), mats.go)
        if j == 3:
            continue
        for k in range(7):
            x = -2.25 + k * 0.45
            T(
                rec,
                f"rolo{j}{k}",
                (x, yi - 0.44, PISO + z + 0.11),
                (x, yi - 0.06, PISO + z + 0.11),
                0.11,
                panos[(j + k) % 5],
                segs=7,
            )
    rec.caixa("estante", (-0.9, yi - 0.25, PISO + 1.1), (3.1, 0.45, 2.2), "para", "Wood")
    # camisas numa vara
    T(rec, "vara", (xi - 0.2, -1.4, 2.25), (xi - 0.2, 1.5, 2.25), 0.015, mats.tre)
    for k in range(5):
        y = -1.15 + k * 0.6

        def f(u, v, y0=y, n0=k):
            return (xi - 0.2 + 0.018 * math.sin(u * 7 + n0), y0 - 0.24 + u * 0.48, 2.2 - v * 0.95)

        o = V.grade(f"cam{k}", f, 3, 2, fora=(-1, 0, 0))
        M.solidificar(o, 0.008, 0.0)
        V.gravar_uv_local(o, lambda p: (p.y, p.z, p.x), k * 0.8)
        M.material(o, panos[(k + 2) % 5])
        rec.add(M.suave(o, 60), "Mobilia", "Mobilia")
    VC.camera(rec, (2.6, -2.5, 1.6), (-1.6, 1.8, 1.0))
    return rec


def receita_ret_pov_barbearia():
    """Hớt tóc: cadeira, espelho na parede, bacia e banco de espera. Pequena e estreita."""
    rec, mats, xi, yi = _loja(
        909, 4.4, 4.2, 3.0, "vach_cal", "tranh", "HỚT TÓC", porta_fundo=False, alto=1.6
    )
    vidro = V.mat_liso("espelho", "#9fb0b4", "#59686c", rug=0.08, escala=3.0, forca=0.15)
    B(rec, "esp_m", (1.26, 0.04, 1.02), (0.0, yi - 0.03, PISO + 1.62), mats.go_escuro)
    B(rec, "esp_v", (1.1, 0.012, 0.86), (0.0, yi - 0.06, PISO + 1.62), vidro)
    B(rec, "bancada", (1.7, 0.42, 0.06), (0.0, yi - 0.22, PISO + 0.88), mats.go)
    for sx in (-1, 1):
        B(
            rec,
            f"banc_p{sx}",
            (0.06, 0.36, 0.86),
            (sx * 0.78, yi - 0.22, PISO + 0.43),
            mats.go_escuro,
        )
    rec.caixa("bancada", (0.0, yi - 0.22, PISO + 0.46), (1.7, 0.42, 0.92), "para", "Wood")
    # a cadeira do barbeiro
    a = [
        V.torno_local(
            "cad_pe",
            [(0, 0), (0.26, 0), (0.28, 0.03), (0.05, 0.09), (0.05, 0.4), (0, 0.4)],
            10,
            mats.ferro,
        ),
        V.bloco("cad_as", (0.52, 0.5, 0.1), (0, 0, 0.46), mats.pano_escuro, chanfro=0.03),
        V.bloco("cad_co", (0.5, 0.09, 0.62), (0, 0.28, 0.82), mats.pano_escuro, chanfro=0.03),
        V.bloco("cad_ca", (0.22, 0.08, 0.17), (0, 0.3, 1.24), mats.pano_escuro, chanfro=0.03),
    ]
    for s in (-1, 1):
        a.append(
            V.bloco(f"cad_b{s}", (0.07, 0.5, 0.05), (s * 0.3, 0.02, 0.68), mats.go, chanfro=0.012)
        )
        a.append(V.bloco(f"cad_bp{s}", (0.04, 0.04, 0.2), (s * 0.3, -0.18, 0.58), mats.go_escuro))
    for ob in a:
        M.mover(ob, V.lugar((0.0, 0.1, PISO), 180))
        K._mob(rec, ob)
    rec.caixa("cadeira", (0.0, 0.1, PISO + 0.55), (0.7, 0.7, 1.1), "para", "Wood")
    bacia = V.torno_local(
        "bacia",
        [(0, 0), (0.12, 0), (0.2, 0.08), (0.18, 0.08), (0.1, 0.02), (0, 0.02)],
        10,
        mats.louca,
    )
    M.mover(bacia, Matrix.Translation((-0.62, yi - 0.22, PISO + 0.91)))
    K._mob(rec, bacia)
    X._banco(rec, "espera", (-xi + 0.24, -0.35), 90, mats, comp=1.8, z=PISO)
    V.potes(rec, "lu", [(xi - 0.36, -1.45)], mats, sem=909)
    VC.camera(rec, (1.5, -1.8, 1.6), (-0.4, 1.6, 1.1))
    return rec


def _cavalete(rec, nome, x, y, rot, mats):
    m = V.lugar((x, y, 0.0), rot)
    o = [V.bloco(f"{nome}_t", (1.3, 0.1, 0.08), (0, 0, 0.76), mats.go)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                V.viga(
                    f"{nome}_p{sx}{sy}",
                    (sx * 0.5, sy * 0.05, 0.74),
                    (sx * 0.58, sy * 0.28, 0.0),
                    0.05,
                    0.05,
                    mats.go_escuro,
                )
            )
    for ob in o:
        M.mover(ob, m)
        K._mob(rec, ob)
    V._col_local(rec, nome, (x, y), rot, (x, y, 0.4), (1.3, 0.56, 0.8), "para", "Wood")


def receita_ret_pov_carpintaria():
    """Xưởng mộc: galpão aberto com bancadas, móvel pela metade e pátio de trabalho com toras."""
    rec = V.Receita()
    sem = 910
    mats = Mats(sem)
    L, W, H = 10.4, 6.4, 3.1
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "van",
        [{"lado": "fundo", "t": 3.2, "estilo": "tabua", "folha": 1}],
        K.janelas("fundo", (-2.8, 0.2)) + K.janelas("dir", (0.0,)),
        tel="ngoi",
        alto=1.5,
        beiral=0.6,
        esp=0.08,
        lados=("fundo", "esq", "dir"),
    )
    for k in range(5):
        x = -L / 2 + 0.1 + k * (L - 0.2) / 4
        V.poste(rec, f"pil{k}", x, -W / 2 + 0.05, H, mats.go, r=0.11, base_pedra=mats.pedra)
    Vg(rec, "frechal", (-L / 2, -W / 2 + 0.05, H), (L / 2, -W / 2 + 0.05, H), 0.14, 0.16, mats.go)
    K.letreiro(rec, "placa", "XƯỞNG MỘC", (0.0, -W / 2 - 0.05, H - 0.32), larg=2.8, alt=0.46)
    serrada = RC._mat_serrada()
    tora = RC._mat_tora()
    K.balcao(rec, "banc_a", -2.6, yi - 0.45, 3.4, mats)
    K.balcao(rec, "banc_b", 2.0, yi - 0.45, 2.6, mats)
    V.ferramentas(rec, "ferr", (-xi + 0.1, 0.2), 90, mats, itens=("enxada", "ancinho"))
    # a mesa e o armário pela metade
    for sx in (-1, 1):
        for sy in (-1, 1):
            B(
                rec,
                f"arm_p{sx}{sy}",
                (0.08, 0.08, 1.7),
                (1.4 + sx * 0.6, -0.5 + sy * 0.3, PISO + 0.85),
                serrada,
            )
    for z in (0.3, 1.0, 1.7):
        B(rec, f"arm_t{int(z * 10)}", (1.3, 0.68, 0.03), (1.4, -0.5, PISO + z), serrada)
    rec.caixa("armario", (1.4, -0.5, PISO + 0.87), (1.3, 0.68, 1.74), "para", "Wood")
    _cavalete(rec, "cav_a", -2.8, -0.8, 8, mats)
    _cavalete(rec, "cav_b", -1.0, -1.0, -5, mats)
    RC._tabuas(rec, "tabuas_d", -1.9, -0.9, 0.84, 2.4, 0.5, 2, serrada, mats)
    # o pátio de trabalho, na frente
    RC._toras(rec, "toras", -2.9, -W / 2 - 2.3, 3.8, 3, 0.2, tora, ang=0.1, sem=1.0)
    RC._tabuas(rec, "tabuas_p", 2.5, -W / 2 - 2.0, 0.0, 3.0, 1.1, 4, serrada, mats, ang=-0.06)
    _cavalete(rec, "cav_c", 0.2, -W / 2 - 3.0, 90, mats)
    X._caixote(rec, "cx", (4.4, -W / 2 - 1.0), 12, mats)
    # tábuas encostadas no pilar
    for k in range(7):
        x = -4.6 + k * 0.24
        B(rec, f"enc{k}", (0.2, 0.035, 2.7), (x, -W / 2 - 0.42, 1.3), serrada, rot=(-0.3, 0, 0))
    rec.caixa("encostadas", (-3.9, -W / 2 - 0.42, 1.3), (1.75, 0.8, 2.6), "para", "Wood")
    VC.camera(rec, (3.6, -W / 2 - 3.6, 1.6), (-1.6, 1.6, 1.0))
    return rec


def receita_ret_pov_ferraria():
    """Lò rèn: forja de barro com coifa, bigorna, tina de têmpera e ferramentas."""
    rec = V.Receita()
    sem = 911
    mats = Mats(sem)
    L, W, H = 7.0, 5.6, 3.0
    tij = RF_tijolo()
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "gach",
        [{"lado": "fundo", "t": -2.1, "estilo": "tabua", "folha": -1}],
        K.janelas("dir", (0.0,)),
        tel="chapa",
        alto=1.4,
        beiral=0.55,
        lados=("fundo", "esq", "dir"),
    )
    for k in range(3):
        x = -L / 2 + 0.1 + k * (L - 0.2) / 2
        V.poste(rec, f"pil{k}", x, -W / 2 + 0.05, H, mats.go_escuro, r=0.11, base_pedra=mats.pedra)
    Vg(
        rec,
        "frechal",
        (-L / 2, -W / 2 + 0.05, H),
        (L / 2, -W / 2 + 0.05, H),
        0.14,
        0.16,
        mats.go_escuro,
    )
    K.letreiro(
        rec, "placa", "LÒ RÈN", (0.0, -W / 2 - 0.05, H - 0.32), larg=2.2, alt=0.46, fundo="#2b2723"
    )
    # forja
    fx, fy = 1.5, yi - 0.75
    B(rec, "forja", (1.9, 1.4, 0.82), (fx, fy, PISO + 0.41), tij, chanfro=0.03)
    B(rec, "brasa", (1.15, 0.8, 0.03), (fx, fy - 0.05, PISO + 0.83), mats.cinza)
    rec.caixa("forja", (fx, fy, PISO + 0.41), (1.9, 1.4, 0.82), "para", "Brick")
    coifa = V.grade(
        "coifa",
        lambda u, v: (
            fx + (u - 0.5) * (2.1 - 1.5 * v),
            fy + (v * 0.3) + (0.5 - u) * 0.0 - 0.1 + (u * 0.0),
            PISO + 1.55 + v * 1.2,
        ),
        1,
        1,
        fora=(0, -1, 0.3),
    )
    M.solidificar(coifa, 0.03, 0.0)
    V.gravar_uv_local(coifa, lambda p: (p.x, p.z, p.y))
    M.material(coifa, mats.ferro)
    K._mob(rec, M.suave(coifa, 30))
    T(
        rec,
        "chamine",
        (fx, fy + 0.25, PISO + 2.7),
        (fx, fy + 0.25, H + 2.1),
        0.2,
        mats.ferro,
        segs=8,
    )
    # fole de couro
    fole = M.superelipsoide("fole", 0.55, 0.3, 0.2, 0.6, 0.7, 10, 5)
    V.gravar_uv_local(fole, lambda p: (p.x, p.y, p.z))
    M.mover(fole, Matrix.Translation((fx - 1.55, fy, PISO + 0.55)) @ Matrix.Rotation(0.2, 4, "Y"))
    M.material(fole, mats.pano_escuro)
    K._mob(rec, M.suave(fole, 60))
    rec.caixa("fole", (fx - 1.55, fy, PISO + 0.55), (1.1, 0.6, 0.5), "para", "Fabric")
    # bigorna sobre o toco
    o = [
        V.cilindro("toco", 0.3, 0.55, (0, 0, 0.275), RC._mat_tora(), segs=9),
        V.bloco("big_b", (0.22, 0.2, 0.1), (0, 0, 0.6), mats.ferro),
        V.bloco("big_c", (0.14, 0.13, 0.08), (0, 0, 0.69), mats.ferro),
        V.bloco("big_t", (0.48, 0.17, 0.09), (0.02, 0, 0.77), mats.ferro, chanfro=0.015),
    ]
    ponta = V.torno_local("big_p", [(0.0, 0.0), (0.075, 0.0), (0.0, 0.2)], 6, mats.ferro)
    M.mover(ponta, Matrix.Translation((0.26, 0, 0.77)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    o.append(ponta)
    X._colocar(
        rec, o, "bigorna", (0.2, -0.5), 25, PISO, (0, 0, 0.41), (0.64, 0.62, 0.82), "para", "Metal"
    )
    RC._barril(rec, "tina", 1.9, -1.3, mats, z=PISO, r=0.34, alt=0.62)
    # tenazes e martelos na parede
    for k in range(6):
        x = -2.8 + k * 0.34
        comp = 0.5 + 0.1 * (k % 3)
        B(rec, f"tenaz{k}", (0.035, 0.02, comp), (x, yi - 0.03, PISO + 1.75 - comp / 2), mats.ferro)
    B(rec, "pendurador", (2.2, 0.03, 0.05), (-2.0, yi - 0.03, PISO + 1.78), mats.go_escuro)
    X._lenha(rec, "carvao", -xi + 0.25, -xi + 1.5, -1.8, mats, z=PISO)
    X._caixote(rec, "cx", (-xi + 0.55, 0.3), 90, mats, z=PISO)
    VC.camera(rec, (-2.4, -2.6, 1.6), (1.4, 1.5, 0.9))
    return rec


def RF_tijolo():
    import ret_frente as RF

    return RF._tijolo("tijolo")


CASAS: dict[str, dict] = {
    "ret_pov_chua": {
        "nome": "pagode (chùa)",
        "tipo": "salão de dois telhados, altar com três imagens, pátio murado, sino e estátua",
        "fontes": [],
        "atlas": K.ATLAS_LAT,
    },
    "ret_pov_mercado": {
        "nome": "pavilhão do mercado",
        "tipo": "aberto, de madeira e palha, duas fileiras de bancas e corredor no meio",
        "fontes": [],
        "atlas": K.ATLAS_G,
    },
    "ret_pov_banca_d": {
        "nome": "banca de peixe seco",
        "tipo": "toldo, tabuleiros, nước mắm em potes",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_banca_e": {
        "nome": "banca de grãos",
        "tipo": "toldo, sacos e cestos de arroz, feijão e açafrão",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_banca_f": {
        "nome": "banca de frutas",
        "tipo": "toldo vermelho, tabuleiros e cachos",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_banca_g": {
        "nome": "banca de tecidos",
        "tipo": "toldo azul, pilhas e panos pendurados",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_escola": {
        "nome": "escola da vila",
        "tipo": "reboco amarelo, telha, três salas com lousas e carteiras",
        "fontes": [],
        "atlas": K.ATLAS_LAT,
    },
    "ret_pov_escola_ala": {
        "nome": "ala da escola",
        "tipo": "reboco amarelo, telha, duas salas",
        "fontes": [],
        "atlas": K.ATLAS_LAT,
    },
    "ret_pov_mercearia": {
        "nome": "mercearia",
        "tipo": "tijolo e telha, prateleiras, balcão e sacos",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_cha": {
        "nome": "casa de chá",
        "tipo": "bambu e nipa, varanda com mesinhas",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_pho": {
        "nome": "restaurante de phở",
        "tipo": "caiado e telha, caldeirão, tigelas, mesas compridas",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_alfaiate": {
        "nome": "alfaiataria",
        "tipo": "tábua e telha, máquinas de costura, rolos de tecido, bustos",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_barbearia": {
        "nome": "barbearia",
        "tipo": "caiada e palha, cadeira, espelho e banco de espera",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_carpintaria": {
        "nome": "carpintaria",
        "tipo": "galpão aberto de tábua e chapa, bancadas e pátio de trabalho com toras",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_ferraria": {
        "nome": "ferraria",
        "tipo": "tijolo e chapa, forja com coifa, fole, bigorna e têmpera",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
}

_ = (E, Matrix)  # usados por receitas futuras e pelo kit
