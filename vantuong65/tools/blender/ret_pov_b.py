"""Povoado da Vila (D-255): residências, agricultura e lugares comunitários.

Metros, Z para cima, frente em -Y. Portas de 1,40 x 2,50 m e soldado de 2,00 m. A pedra laterítica
é a referência histórica de Vạn Tường: casas e muros desse material com mais de cem anos.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_arrozal as A  # noqa: E402
import exp_vila as X  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
import ret_comboio as RC  # noqa: E402
import ret_pov_kit as K  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from ret_pov_kit import B, T, Vg  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402


def _moita(rec, nome, x, y, z, a, b, h, mat, sem):
    """Massa de folhagem baixa e irregular, parada."""
    o = M.superelipsoide(nome, a, b, h, 0.8, 0.85, 9, 5)
    M.deslocar(o, lambda co, n, k=sem: 0.09 * M.fbm(co * 3.1, 3, k))
    V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z), float(sem))
    M.mover(o, Matrix.Translation((x, y, z)))
    M.material(o, mat)
    K._mob(rec, M.suave(o, 60))


def _folhagem():
    return V.mat_liso("mato", "#46562c", "#2c3a1e", rug=0.8, escala=14.0, forca=0.65)


# =============================================================== 8. casa laterítica
def receita_ret_pov_laterita():
    """Casa antiga de pedra laterítica, telha, varanda e quintal com muro baixo."""
    rec = V.Receita()
    sem = 921
    mats = Mats(sem)
    L, W, H = 8.8, 5.6, 2.95
    lat = K.parede("laterita")
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "laterita",
        [
            {"lado": "frente", "t": -1.9, "estilo": "folhas"},
            {"lado": "fundo", "t": 2.6, "estilo": "tabua", "folha": -1},
        ],
        K.janelas("frente", (1.9,)) + K.janelas("esq", (0.0,), 0.9) + K.janelas("dir", (0.0,), 0.9),
        tel="ngoi",
        forma="4aguas",
        alto=2.3,
        beiral=0.75,
        esp=0.3,
    )
    yv = K.varanda(rec, mats, sem, L, W, prof=1.8, tel="ngoi")
    xd = 0.9
    div = V.Lado((xd, -W / 2 + 0.3), math.pi / 2, W - 0.6, 0.14, 1.0)
    V.parede(rec, "div", div, 0.0, H, lat, [(1.7, 1.4, -1.0, PISO + 2.5)], "Brick", sem=sem + 1)
    V.ban_tho(rec, "altar", (-2.1, yi - 0.3), 0, mats, comp=1.25, prof=0.5, alt=1.0, rico=True)
    V.cadeiras_mesa(rec, "mesa", (-2.0, -0.2), 90, mats)
    V.phan(rec, "phan", (xi - 1.05, yi - 0.72), 0, mats)
    V.ruong(rec, "arca", (xi - 0.3, -0.75), 90, mats)
    V.potes(rec, "lu", [(-xi + 0.42, -yi + 0.45), (-xi + 0.42, 0.9)], mats, sem=sem)
    # quintal com muro baixo de laterita e passagem
    yq = yv - 3.0
    for nome, p, q in (
        ("mq_f1", (-L / 2 - 0.6, yq), (-1.0, yq)),
        ("mq_f2", (1.0, yq), (L / 2 + 0.6, yq)),
        ("mq_e", (-L / 2 - 0.6, yq), (-L / 2 - 0.6, -W / 2)),
        ("mq_d1", (L / 2 + 0.6, yq), (L / 2 + 0.6, yq + 2.1)),
        ("mq_d2", (L / 2 + 0.6, yq + 3.6), (L / 2 + 0.6, -W / 2)),
    ):
        K.muro(rec, mats, nome, p, q, 1.05, lat, esp=0.3)
    V.potes(
        rec,
        "lu_q",
        [(-L / 2 + 0.2, yq + 0.6), (-L / 2 + 0.75, yq + 0.55)],
        mats,
        sem=sem + 3,
        dentro=False,
    )
    VC.camera(rec, (-L / 2 + 0.7, -W / 2 + 0.8, PISO + 1.55), (1.6, W / 2 - 0.9, PISO + 0.8))
    return rec


# =============================================================== 9. casa com pátio
def receita_ret_pov_patio():
    """Casa em U de laterita: corpo no fundo, cozinha e depósito nas alas e pátio interno."""
    rec = V.Receita()
    sem = 922
    mats = Mats(sem)
    lat = K.parede("laterita")
    ngoi = K.telha("#8f5238", "#623827", "#aa6a4a")
    L, W, H = 11.0, 4.8, 2.9
    cy = 3.6
    marca = rec.marca()
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "laterita",
        [
            {"lado": "frente", "t": 0.0, "estilo": "folhas"},
            {"lado": "fundo", "t": -3.6, "estilo": "tabua", "folha": 1},
        ],
        K.janelas("frente", (-3.3, 3.3)) + K.janelas("fundo", (2.4,)),
        tel="ngoi",
        forma="4aguas",
        alto=2.2,
        beiral=0.7,
        esp=0.3,
    )
    V.ban_tho(rec, "altar", (0.0, yi - 0.3), 0, mats, comp=1.4, prof=0.5, alt=1.0, rico=True)
    V.cadeiras_mesa(rec, "mesa", (0.0, -0.45), 0, mats)
    V.phan(rec, "phan_a", (-xi + 1.05, yi - 0.72), 0, mats)
    V.phan(rec, "phan_b", (xi - 1.05, yi - 0.72), 0, mats)
    rec.transformar(marca, V.lugar((0.0, cy, 0.0)))
    # as duas alas abertas para o pátio
    VC.cozinha(
        rec,
        mats,
        "coz",
        (-4.2, -1.6),
        90,
        lat,
        ngoi,
        "ngoi",
        col="Brick",
        L=4.0,
        W=2.7,
        sem=sem + 2,
        ferr=True,
    )
    VC.cozinha(
        rec,
        mats,
        "dep",
        (4.2, -1.6),
        -90,
        lat,
        ngoi,
        "ngoi",
        col="Brick",
        L=4.0,
        W=2.7,
        sem=sem + 3,
    )
    K.fardos(rec, "sacos", 4.5, -2.6, mats, colunas=3, linhas=2)
    # o muro da frente, com portão, e o pátio
    yf = -4.6
    K.muro(rec, mats, "mf1", (-5.7, yf), (-1.4, yf), 1.5, lat)
    K.muro(rec, mats, "mf2", (1.4, yf), (5.7, yf), 1.5, lat)
    K.muro(rec, mats, "me", (-5.7, yf), (-5.7, -3.4), 1.5, lat)
    K.muro(rec, mats, "md", (5.7, yf), (5.7, -3.4), 1.5, lat)
    K.portal(rec, mats, sem + 4, "portao", 0.0, yf, 2.5, 2.7, lat)
    V.bo_lua(rec, "tulha", (-1.7, 0.2), mats, r=0.5, alt=1.1)
    V.potes(rec, "lu_p", [(1.5, 0.3), (2.05, 0.15), (1.7, -0.3)], mats, sem=sem + 5, dentro=False)
    V.nen(rec, "caminho", -0.8, yf + 0.2, 0.8, cy - W / 2, mats)
    VC.camera(rec, (-0.6, yf + 0.7, 1.6), (0.0, cy, 1.2))
    return rec


# =============================================================== 11. abandonada
def receita_ret_pov_abandonada():
    """Casa largada: telhado afundado de um lado, mato entrando, móveis virados."""
    rec = V.Receita()
    sem = 923
    mats = Mats(sem)
    L, W, H = 8.2, 5.2, 2.75
    vach = K.parede("vach_dat")
    tranh = V.mat_la("la")
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        0.14,
        vach,
        [
            {"lado": "frente", "t": -1.8, "estilo": "nada"},
            {"lado": "fundo", "t": 2.2, "estilo": "nada"},
        ],
        K.janelas("frente", (1.9,)) + K.janelas("esq", (0.0,), 0.9),
        col="Earth",
        sem=sem,
    )
    hr = H + 2.1
    for k in range(7):
        x = -L / 2 + k * L / 6
        for s in (-1, 1):
            afunda = 0.4 if (s < 0 and x > 0.3) else 0.0
            T(
                rec,
                f"cai{k}{s}",
                (x, s * (W / 2 + 0.5), H - 0.1),
                (x, 0, hr - afunda),
                0.04,
                mats.tre,
                est=True,
            )
    Vg(rec, "cumeeira", (-L / 2 - 0.2, 0, hr), (0.4, 0, hr), 0.12, 0.14, mats.go_escuro)
    Vg(rec, "cumeeira_b", (0.4, 0, hr), (L / 2 + 0.2, 0, hr - 0.42), 0.12, 0.14, mats.go_escuro)
    V.agua_unica(
        rec,
        "tel_t",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        0.0,
        hr + 0.02,
        W / 2 + 0.55,
        H - 0.2,
        0.2,
        "la",
        tranh,
        mats,
        sem=sem + 1,
    )
    V.agua_unica(
        rec,
        "tel_f",
        -L / 2 - 0.3,
        -0.4,
        0.0,
        hr + 0.02,
        -W / 2 - 0.55,
        H - 0.2,
        0.2,
        "la",
        tranh,
        mats,
        sem=sem + 2,
    )
    mato = _folhagem()
    for k, (x, y, a, b, h) in enumerate(
        (
            (2.4, -0.9, 1.1, 0.85, 0.65),
            (3.2, 1.2, 0.8, 0.8, 0.55),
            (-3.4, 1.7, 0.7, 0.6, 0.45),
            (-L / 2 - 0.4, -1.5, 0.6, 0.9, 0.85),
            (L / 2 + 0.35, 1.2, 0.55, 1.1, 1.1),
            (0.6, -W / 2 - 0.45, 1.4, 0.45, 0.6),
        )
    ):
        _moita(
            rec,
            f"moita{k}",
            x,
            y,
            0.0 if abs(x) > L / 2 or y < -W / 2 else PISO,
            a,
            b,
            h,
            mato,
            k + 9,
        )
    # mesa virada e cesto caído
    o = V.bloco(
        "tampo", (1.2, 0.7, 0.04), (-1.2, 0.55, PISO + 0.38), mats.go_escuro, rot=(1.2, 0.0, 0.35)
    )
    K._mob(rec, o)
    rec.caixa("tampo", (-1.2, 0.55, PISO + 0.35), (1.2, 0.3, 0.7), "para", "Wood", rot_z=0.35)
    X._cesto(rec, "cesto", (-2.9, -1.3), mats, r=0.3, alt=0.42, z=PISO)
    V.potes(rec, "lu", [(-3.3, -1.75)], mats, sem=sem)
    VC.camera(rec, (-L / 2 + 0.6, -W / 2 + 0.6, PISO + 1.55), (2.4, W / 2 - 1.0, PISO + 0.6))
    return rec


# =============================================================== 21. armazém de arroz
def receita_ret_pov_armazem():
    """Kho lúa: três compartimentos ligados por vãos, portões largos e tulhas por dentro."""
    rec = V.Receita()
    sem = 924
    mats = Mats(sem)
    L, W, H = 15.0, 8.0, 3.5
    van = K.parede("van")
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "van",
        [
            {"lado": "frente", "t": -4.6, "estilo": "folhas"},
            {"lado": "frente", "t": 4.6, "estilo": "folhas"},
            {"lado": "fundo", "t": 0.0, "estilo": "folhas"},
            {"lado": "esq", "t": 0.0, "estilo": "tabua", "folha": 1},
            {"lado": "dir", "t": 1.2, "estilo": "tabua", "folha": -1},
        ],
        K.janelas("fundo", (-4.6, 4.6), 1.3),
        tel="ngoi",
        forma="2aguas",
        alto=2.5,
        beiral=0.8,
        esp=0.12,
        vaos_extra={"frente": [(L / 2, 4.6, -1.0, PISO + 2.85)]},
    )
    for k, xd in enumerate((-2.5, 2.5)):
        div = V.Lado((xd, -W / 2 + 0.12), math.pi / 2, W - 0.24, 0.16, 1.0)
        c = 2.0 if k == 0 else W - 2.24
        V.parede(
            rec,
            f"div{k}",
            div,
            0.0,
            H - 0.3,
            van,
            [(c, 1.6, -1.0, PISO + 2.5)],
            "Wood",
            sem=sem + k,
        )
    K.letreiro(rec, "placa", "KHO LÚA", (0.0, -W / 2 - 0.05, H - 0.2), larg=2.4, alt=0.46)
    A.registrar_porta(rec, "portao", (0.0, -W / 2, PISO), 4.6, 2.85, (0, -1, 0))
    for s in (-1, 1):
        K.fardos(rec, f"fora{s}", s * 3.1, -W / 2 - 0.42, mats, z=0.0, colunas=2, linhas=2)
    # compartimento 1: sacos até a altura do peito
    for j in range(3):
        K.fardos(rec, f"f1_{j}", -5.4, yi - 0.34 - j * 0.62, mats, colunas=5, linhas=3 - (j > 1))
    K.fardos(rec, "f1b", -6.0, -2.4, mats, colunas=3, linhas=2)
    # compartimento 2: as tulhas redondas
    for k, (x, y) in enumerate(((-1.3, 2.4), (0.0, 2.6), (1.3, 2.4), (-1.3, -2.6), (1.3, -2.6))):
        V.bo_lua(rec, f"tulha{k}", (x, y), mats, r=0.55, alt=1.3)
    # compartimento 3: balança, cestos e monte de arroz
    monte = M.superelipsoide("monte", 1.5, 1.2, 0.72, 0.9, 0.9, 12, 6)
    V.apagar_faces(monte, lambda c, n: c.z < -0.02)
    V.gravar_uv_local(monte, lambda p: (p.x, p.y, p.z))
    M.mover(monte, Matrix.Translation((5.2, yi - 1.7, PISO)))
    M.material(monte, mats.arroz)
    K._mob(rec, M.suave(monte, 60))
    rec.caixa("monte", (5.2, yi - 1.7, PISO + 0.3), (2.6, 2.0, 0.6), "para", "Fabric")
    for k, (x, y) in enumerate(((3.7, -2.9), (4.4, -3.1), (6.3, -2.9))):
        X._cesto(rec, f"ces{k}", (x, y), mats, r=0.34, alt=0.5, z=PISO)
    T(rec, "bal_h", (6.2, -0.8, PISO), (6.2, -0.8, PISO + 1.9), 0.05, mats.go_escuro, segs=6)
    T(rec, "bal_b", (5.4, -0.8, PISO + 1.85), (7.0, -0.8, PISO + 1.85), 0.03, mats.go)
    rec.caixa("balanca", (6.2, -0.8, PISO + 0.95), (0.2, 0.2, 1.9), "passa", "Wood")
    VC.camera(rec, (-6.6, -3.2, 1.6), (0.0, 2.2, 1.0))
    return rec


# =============================================================== 22. búfalos
def receita_ret_pov_bufalos():
    """Abrigo dos búfalos: telheiro de palha, cocho de tronco, feno e arado."""
    rec = V.Receita()
    sem = 925
    mats = Mats(sem)
    L, W, H = 7.4, 4.6, 2.5
    tranh = V.mat_tranh("tranh")
    V.nen(rec, "nen", -L / 2 - 0.1, -W / 2 - 0.1, L / 2 + 0.1, W / 2 + 0.1, mats)
    for k in range(4):
        x = -L / 2 + k * L / 3
        for s in (-1, 1):
            V.poste(
                rec,
                f"p{k}{s}",
                x,
                s * W / 2,
                H if s > 0 else H - 0.4,
                mats.go_escuro,
                r=0.11,
                base_pedra=mats.pedra,
            )
    V.agua_unica(
        rec,
        "tel",
        -L / 2 - 0.4,
        L / 2 + 0.4,
        W / 2 + 0.3,
        H + 0.3,
        -W / 2 - 0.45,
        H - 0.65,
        0.24,
        "tranh",
        tranh,
        mats,
        sem=sem,
    )
    Vg(rec, "fre_a", (-L / 2, W / 2, H), (L / 2, W / 2, H), 0.12, 0.14, mats.go)
    Vg(rec, "fre_b", (-L / 2, -W / 2, H - 0.4), (L / 2, -W / 2, H - 0.4), 0.12, 0.14, mats.go)
    # meias-paredes de varas nos fundos e nos lados, aberto na frente
    for z in (0.45, 0.9, 1.35):
        T(rec, f"tf{int(z * 100)}", (-L / 2, W / 2, z), (L / 2, W / 2, z), 0.05, mats.tre, est=True)
        for s in (-1, 1):
            T(
                rec,
                f"tl{s}{int(z * 100)}",
                (s * L / 2, -W / 2, z),
                (s * L / 2, W / 2, z),
                0.05,
                mats.tre,
                est=True,
            )
    rec.caixa("cf", (0, W / 2, 0.75), (L, 0.12, 1.5), "passa", "Bamboo")
    for s in (-1, 1):
        rec.caixa(f"cl{s}", (s * L / 2, 0, 0.75), (0.12, W, 1.5), "passa", "Bamboo")
    T(
        rec,
        "cocho",
        (-1.1, W / 2 - 0.55, 0.3),
        (1.7, W / 2 - 0.55, 0.3),
        0.3,
        RC._mat_tora(),
        segs=8,
    )
    rec.caixa("cocho", (0.3, W / 2 - 0.55, 0.3), (2.8, 0.62, 0.6), "para", "Wood")
    for k, (x, y, a) in enumerate(((2.6, 1.3, 0.75), (-2.6, 1.3, 0.62), (2.9, -0.1, 0.5))):
        feno = M.superelipsoide(f"feno{k}", a, a * 0.8, a * 0.65, 0.9, 0.9, 9, 5)
        M.deslocar(feno, lambda co, n, q=k: 0.05 * M.fbm(co * 5.0, 2, q))
        V.apagar_faces(feno, lambda c, n: c.z < -0.02)
        V.gravar_uv_local(feno, lambda p: (p.x, p.y, p.z), float(k))
        M.mover(feno, Matrix.Translation((x, y, 0.1)))
        M.material(feno, tranh)
        K._mob(rec, M.suave(feno, 60))
        rec.caixa(f"feno{k}", (x, y, 0.3), (1.7 * a, 1.4 * a, 0.6), "passa", "Fabric")
    V.ferramentas(rec, "ferr", (-1.3, -W / 2 + 0.55), 0, mats, arado=True, itens=("enxada",), z=0.1)
    VC.camera(rec, (-2.9, -3.2, 1.5), (0.6, 1.2, 0.7))
    return rec


# =============================================================== 24. galinheiro e chiqueiro
def receita_ret_pov_galinheiro():
    """Galinheiro de bambu sobre pés, chiqueiro baixo e cercadinho de ciscar."""
    rec = V.Receita()
    sem = 926
    mats = Mats(sem)
    tranh = V.mat_tranh("tranh")
    V.chuong_heo(rec, "heo", (2.0, 0.6), 0, mats, tranh, larg=3.0, prof=2.4)
    x0, y0 = -2.2, 0.6
    for sx in (-1, 1):
        for sy in (-1, 1):
            T(
                rec,
                f"gp{sx}{sy}",
                (x0 + sx * 1.2, y0 + sy * 0.8, 0),
                (x0 + sx * 1.2, y0 + sy * 0.8, 1.72),
                0.05,
                mats.tre,
                est=True,
            )
    B(rec, "g_piso", (2.5, 1.7, 0.05), (x0, y0, 0.72), mats.esteira)
    for s in (-1, 1):
        B(rec, f"g_y{s}", (2.5, 0.04, 0.72), (x0, y0 + s * 0.84, 1.1), mats.esteira)
        B(rec, f"g_x{s}", (0.04, 1.7, 0.72), (x0 + s * 1.24, y0, 1.1), mats.esteira)
    V.agua_unica(
        rec,
        "g_tel",
        x0 - 1.55,
        x0 + 1.55,
        y0 + 1.05,
        2.02,
        y0 - 1.1,
        1.62,
        0.2,
        "tranh",
        tranh,
        mats,
        sem=sem,
    )
    T(rec, "rampa", (x0 + 0.2, y0 - 1.65, 0.0), (x0 + 0.2, y0 - 0.85, 0.72), 0.08, mats.tre)
    rec.caixa("galinheiro", (x0, y0, 0.86), (2.5, 1.7, 1.72), "passa", "Bamboo")
    V.cerca(
        rec,
        "cerca",
        [(-4.2, -0.9), (-4.2, -3.3), (3.9, -3.3), (3.9, -0.8)],
        mats,
        alt=0.85,
        portao=1,
    )
    for k, (x, y) in enumerate(((-2.8, -2.2), (0.4, -1.9), (2.8, -2.4))):
        X._cesto(rec, f"ces{k}", (x, y), mats, r=0.24, alt=0.28)
    VC.camera(rec, (-4.0, -4.6, 1.7), (0.0, 0.5, 0.7))
    return rec


# =============================================================== 26. cestos
def receita_ret_pov_cestos():
    """Oficina de cestos: telheiro de bambu, feixes de varas, tiras e cestos prontos."""
    rec = V.Receita()
    sem = 927
    mats = Mats(sem)
    L, W, H = 6.6, 4.6, 2.65
    la = V.mat_la("la")
    V.nen(rec, "nen", -L / 2 - 0.1, -W / 2 - 0.1, L / 2 + 0.1, W / 2 + 0.1, mats)
    for k in range(4):
        x = -L / 2 + k * L / 3
        for s in (-1, 1):
            V.poste(rec, f"p{k}{s}", x, s * W / 2, H, mats.tre, r=0.08)
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        H + 1.65,
        0.65,
        "2aguas",
        "la",
        0.22,
        la,
        mats,
        beiral_oitao=0.5,
        sem=sem,
        tesouras=(0.0,),
        mat_oitao=K.parede("phen_par"),
        oitao_esp=0.05,
        col_oitao="Bamboo",
    )
    # parede de esteira no fundo, onde os cestos ficam pendurados
    for k in range(3):
        B(
            rec,
            f"est{k}",
            (L / 3 - 0.05, 0.04, 1.9),
            (-L / 3 + k * L / 3, W / 2 - 0.06, 1.05),
            mats.esteira,
        )
    rec.caixa("est_f", (0, W / 2 - 0.06, 1.05), (L, 0.08, 2.1), "passa", "Bamboo")
    for k in range(7):
        X._cesto(
            rec,
            f"pend{k}",
            (-2.6 + k * 0.86, W / 2 - 0.34),
            mats,
            r=0.24 + (k % 3) * 0.04,
            alt=0.3,
            z=1.12 + (k % 2) * 0.34,
        )
    # pilhas de cestos prontos
    for k, (x, y, n) in enumerate(((2.5, 1.1, 4), (1.7, 1.2, 3), (2.6, 0.2, 3))):
        for j in range(n):
            X._cesto(
                rec, f"pil{k}{j}", (x, y), mats, r=0.38 - j * 0.015, alt=0.34, z=PISO + j * 0.15
            )
    # feixes de bambu e o trabalho em andamento
    for k in range(9):
        y = -1.8 + (k % 3) * 0.11
        T(
            rec,
            f"feixe{k}",
            (-3.0, y, PISO + 0.06 + (k // 3) * 0.1),
            (0.6, y + 0.1, PISO + 0.07 + (k // 3) * 0.1),
            0.05,
            mats.tre,
        )
    rec.caixa("feixe", (-1.2, -1.7, PISO + 0.17), (3.6, 0.4, 0.34), "passa", "Bamboo")
    for k, (x, y) in enumerate(((-1.0, 0.1), (0.4, -0.3))):
        X._banco(rec, f"banq{k}", (x, y), 25 * k, mats, comp=0.5, larg=0.3, alt=0.26, z=PISO)
    tira = V.grade(
        "tiras",
        lambda u, v: (-1.6 + u * 1.3, 0.55 + v * 0.8, PISO + 0.02 + 0.006 * math.sin(u * 30)),
        2,
        1,
        fora=(0, 0, 1),
    )
    V.gravar_uv_local(tira, lambda p: (p.x, p.y, p.z))
    M.material(tira, mats.esteira)
    K._mob(rec, tira)
    X._cesto(rec, "meio", (-0.3, 0.75), mats, r=0.42, alt=0.3, z=PISO)
    VC.camera(rec, (-2.9, -2.9, 1.5), (0.7, 1.0, 0.8))
    return rec


# =============================================================== 27. moinho
def _coi_xay(rec, nome, x, y, mats):
    """Cối xay: moinho de arroz de duas mós trançadas, com a alavanca suspensa."""
    o = [
        V.torno_local(
            f"{nome}_b",
            [(0, 0), (0.62, 0), (0.66, 0.1), (0.58, 0.14), (0.42, 0.42), (0, 0.42)],
            12,
            mats.barro_escuro,
        ),
        V.torno_local(
            f"{nome}_m",
            [(0, 0.44), (0.42, 0.44), (0.46, 0.8), (0.34, 0.86), (0.2, 0.74), (0, 0.72)],
            12,
            mats.esteira,
        ),
    ]
    o.append(V.viga(f"{nome}_br", (0.0, 0.0, 0.62), (0.82, 0.0, 0.62), 0.06, 0.06, mats.go))
    for ob in o:
        M.mover(ob, Matrix.Translation((x, y, PISO)))
        K._mob(rec, ob)
    rec.caixa(nome, (x, y, PISO + 0.42), (1.3, 1.3, 0.86), "para", "Earth")
    T(
        rec,
        f"{nome}_alav",
        (x + 0.8, y, PISO + 0.64),
        (x + 2.2, y + 0.1, PISO + 0.98),
        0.03,
        mats.tre,
    )
    T(
        rec,
        f"{nome}_cab",
        (x + 2.2, y - 0.3, PISO + 0.98),
        (x + 2.2, y + 0.5, PISO + 0.98),
        0.025,
        mats.tre,
    )
    T(
        rec,
        f"{nome}_co",
        (x + 2.2, y + 0.1, PISO + 0.98),
        (x + 2.2, y + 0.1, 2.5),
        0.008,
        mats.corda,
        segs=3,
    )


def _pilao(rec, nome, x, y, mats):
    """Cối giã chày đạp: pilão de pé, uma gangorra de madeira sobre o almofariz."""
    o = [
        V.torno_local(
            f"{nome}_al",
            [(0, 0), (0.3, 0), (0.34, 0.34), (0.3, 0.44), (0.18, 0.44), (0.12, 0.2), (0, 0.18)],
            10,
            RC._mat_tora(),
        ),
        V.viga(f"{nome}_br", (-0.05, 0.0, 0.92), (2.5, 0.0, 0.42), 0.14, 0.12, mats.go),
        V.viga(f"{nome}_ma", (0.08, 0.0, 0.24), (0.08, 0.0, 1.0), 0.13, 0.13, mats.go_escuro),
    ]
    for s in (-1, 1):
        o.append(
            V.viga(
                f"{nome}_ap{s}",
                (1.55, s * 0.2, 0.0),
                (1.55, s * 0.2, 0.78),
                0.09,
                0.09,
                mats.go_escuro,
            )
        )
    o.append(V.tre(f"{nome}_ei", (1.55, -0.26, 0.68), (1.55, 0.26, 0.68), 0.03, mats.go_escuro))
    for ob in o:
        M.mover(ob, V.lugar((x, y, PISO), 0))
        K._mob(rec, ob)
    rec.caixa(nome, (x + 1.15, y, PISO + 0.5), (2.9, 0.62, 1.0), "para", "Wood")


def receita_ret_pov_moinho():
    """Descascador de arroz: telheiro com moinho de mó e pilão de pé, sacos e peneiras."""
    rec = V.Receita()
    sem = 928
    mats = Mats(sem)
    L, W, H = 7.6, 5.2, 2.8
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "vach_dat",
        [{"lado": "fundo", "t": 2.6, "estilo": "tabua", "folha": -1}],
        K.janelas("dir", (0.0,), 1.0),
        tel="tranh",
        forma="2aguas",
        alto=2.0,
        beiral=0.7,
        lados=("fundo", "esq", "dir"),
    )
    for k in range(4):
        x = -L / 2 + 0.1 + k * (L - 0.2) / 3
        V.poste(rec, f"pil{k}", x, -W / 2 + 0.05, H, mats.go, r=0.1, base_pedra=mats.pedra)
    Vg(rec, "frechal", (-L / 2, -W / 2 + 0.05, H), (L / 2, -W / 2 + 0.05, H), 0.13, 0.15, mats.go)
    _coi_xay(rec, "coi", -2.2, 0.7, mats)
    _pilao(rec, "pilao", 0.4, -1.1, mats)
    K.fardos(rec, "sacos", 2.3, yi - 0.34, mats, colunas=4, linhas=3)
    V.bo_lua(rec, "tulha", (-xi + 0.6, yi - 0.65), mats, r=0.5, alt=1.1)
    for k, (x, z) in enumerate(((-0.7, 1.62), (-0.1, 1.5), (0.5, 1.64))):
        ne = V.torno_local(
            f"nia{k}",
            [(0, 0), (0.3, 0.015), (0.34, 0.05), (0.3, 0.035), (0, 0.022)],
            12,
            mats.esteira,
        )
        M.mover(ne, Matrix.Translation((x, yi - 0.05, z)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        K._mob(rec, ne)
    VC.camera(rec, (-3.0, -2.8, 1.5), (0.8, 1.2, 0.7))
    return rec


# =============================================================== 28. posto médico
def receita_ret_pov_medico():
    """Trạm xá: caiado, dois leitos, armário, mesa de curativo e cortina entre as salas."""
    rec = V.Receita()
    sem = 929
    mats = Mats(sem)
    L, W, H = 8.0, 5.2, 3.0
    xi, yi = K.corpo(
        rec,
        mats,
        sem,
        L,
        W,
        H,
        "vach_cal",
        [
            {"lado": "frente", "t": -2.2, "estilo": "tabua", "folha": 1},
            {"lado": "fundo", "t": 2.4, "estilo": "tabua", "folha": -1},
        ],
        K.janelas("frente", (1.4,)) + K.janelas("esq", (0.0,), 0.9) + K.janelas("dir", (0.0,), 0.9),
        tel="ngoi",
        forma="4aguas",
        alto=2.1,
    )
    yv = K.varanda(rec, mats, sem, L, W, prof=1.5, tel="ngoi")
    K.letreiro(
        rec,
        "placa",
        "TRẠM XÁ",
        (0.0, -W / 2 - 0.06, 2.72),
        larg=2.2,
        alt=0.4,
        fundo="#d9d3c2",
        letra="#2c2a26",
    )
    X._banco(rec, "espera", (1.6, yv + 0.5), 0, mats, comp=2.2)
    for k, x in enumerate((0.9, 2.7)):
        V.cho_tre(rec, f"leito{k}", (x, yi - 1.0), 90, mats, comp=1.9, larg=0.85, alt=0.5)
    cortina = N.mat_pano("cortina", cor="#c7c0ad", desbotado="#a59e8c")

    def f(u, v):
        return (0.0 + 0.03 * math.sin(u * 16), -0.5 + u * 2.9, 2.3 - v * 1.9)

    o = V.grade("cort", f, 8, 2, fora=(-1, 0, 0))
    M.solidificar(o, 0.01, 0.0)
    V.gravar_uv_local(o, lambda p: (p.y, p.z, p.x))
    M.material(o, cortina)
    K._mob(rec, M.suave(o, 60))
    T(rec, "cort_v", (0.0, -0.6, 2.32), (0.0, 2.5, 2.32), 0.014, mats.ferro)
    X._prateleira(rec, "armario", (-2.4, yi - 0.22), 0, mats, comp=1.8, alt=2.0, z=PISO)
    K.balcao(rec, "curativo", -2.9, -0.6, 1.6, mats, prof=0.72, alt=0.86, rot=90)
    X._caixote(rec, "cx", (-xi + 0.5, 1.0), 90, mats, z=PISO)
    vidros = V.mat_liso("frasco", "#7f9391", "#3e4f4c", rug=0.2, escala=4.0, forca=0.2)
    for k in range(5):
        fr = V.torno_local(
            f"fr{k}",
            [(0, 0), (0.04, 0), (0.045, 0.1), (0.016, 0.14), (0.016, 0.18), (0, 0.18)],
            6,
            vidros,
        )
        M.mover(fr, Matrix.Translation((-2.95, -1.15 + k * 0.22, PISO + 0.86)))
        K._mob(rec, fr)
    VC.camera(rec, (-L / 2 + 0.6, -W / 2 + 0.6, PISO + 1.55), (1.8, W / 2 - 1.0, PISO + 0.7))
    return rec


# =============================================================== 30. santuário
def receita_ret_pov_santuario():
    """Miếu dos antepassados: nicho de telha sobre pedestal, mesa de oferendas e mureta."""
    rec = V.Receita()
    sem = 930
    mats = Mats(sem)
    lat = K.parede("laterita")
    B(rec, "ped_a", (2.5, 2.1, 0.32), (0, 0.5, 0.16), mats.pedra, est=True)
    B(rec, "ped_b", (1.8, 1.5, 0.74), (0, 0.6, 0.69), lat, est=True)
    rec.caixa("pedestal", (0, 0.55, 0.53), (2.0, 1.7, 1.06), "para", "Brick")
    B(rec, "n_fundo", (1.45, 0.12, 1.08), (0, 1.15, 1.6), lat, est=True)
    for s in (-1, 1):
        B(rec, f"n_l{s}", (0.12, 1.0, 1.08), (s * 0.68, 0.68, 1.6), lat, est=True)
    marca = rec.marca()
    V.telhado(
        rec,
        "tel",
        1.6,
        1.3,
        2.14,
        2.86,
        0.42,
        "4aguas",
        "ngoi",
        0.07,
        K.telha(),
        mats,
        beiral_oitao=0.42,
        sem=sem,
        estrutura=False,
    )
    rec.transformar(marca, V.lugar((0.0, 0.65, 0.0)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.dao(
                rec,
                f"dao{sx}{sy}",
                sx * 1.2,
                0.65 + sy * 1.05,
                K.z_beiral(2.14, 2.86, 1.3, 0.42),
                math.atan2(sy, sx),
                K.telha(),
                comp=0.32,
            )
    K.incensario(rec, "inc", 0.0, 0.5, mats, z=1.06, e=0.34)
    B(rec, "tabuleta", (0.34, 0.05, 0.58), (0, 1.05, 1.36), mats.laca)
    for s in (-1, 1):
        B(rec, f"vela{s}", (0.05, 0.05, 0.2), (s * 0.34, 0.6, 1.16), mats.pano_verm)
    V.ban_thap(
        rec, "of", (0.0, -1.05), 0, mats, comp=1.2, larg=0.6, alt=0.5, cha=True, banquinhos=0
    )
    K.muro(rec, mats, "m_e", (-2.4, -2.2), (-2.4, 1.9), 0.8, lat, esp=0.26)
    K.muro(rec, mats, "m_d", (2.4, -2.2), (2.4, 1.9), 0.8, lat, esp=0.26)
    K.muro(rec, mats, "m_f", (-2.4, 1.9), (2.4, 1.9), 0.8, lat, esp=0.26)
    VC.camera(rec, (-1.4, -3.4, 1.5), (0.0, 0.7, 1.2))
    return rec


# =============================================================== 31. poço
def receita_ret_pov_poco():
    """Poço comunitário: boca de pedra, roldana, cobertura de telha e laje de lavar."""
    rec = V.Receita()
    sem = 931
    mats = Mats(sem)
    lat = K.parede("laterita")
    V.nen(rec, "laje", -2.3, -2.0, 2.3, 2.0, mats)
    boca = V.torno_local(
        "boca",
        [(0.62, 0), (0.72, 0), (0.74, 0.76), (0.66, 0.8), (0.56, 0.78), (0.54, 0.12), (0, 0.1)],
        16,
        lat,
    )
    M.mover(boca, Matrix.Translation((0, 0, PISO)))
    rec.add(boca, "Casa", "Paredes")
    agua = V.mat_liso("agua_poco", "#242a26", "#101512", rug=0.06, escala=2.0, forca=0.2)
    disco = V.cilindro("agua", 0.54, 0.01, (0, 0, PISO + 0.14), agua, segs=14)
    K._mob(rec, disco)
    rec.caixa("boca", (0, 0, PISO + 0.4), (1.3, 1.3, 0.8), "para", "Brick")
    for sx in (-1, 1):
        for sy in (-1, 1):
            V.poste(
                rec,
                f"p{sx}{sy}",
                sx * 1.25,
                sy * 1.25,
                2.55,
                mats.go_escuro,
                r=0.09,
                base_pedra=mats.pedra,
            )
    marca = rec.marca()
    V.telhado(
        rec,
        "tel",
        2.5,
        2.5,
        2.55,
        3.55,
        0.5,
        "4aguas",
        "ngoi",
        0.08,
        K.telha(),
        mats,
        beiral_oitao=0.5,
        sem=sem,
    )
    rec.transformar(marca, V.lugar((0, 0, 0)))
    T(rec, "eixo", (-1.25, 0, 2.2), (1.25, 0, 2.2), 0.05, mats.go, segs=6)
    roda = M.toro("roda", 0.22, 0.03, 12, 4)
    V.gravar_uv_local(roda, lambda p: (p.x, p.y, p.z))
    M.material(roda, mats.go_escuro)
    M.mover(roda, Matrix.Translation((0.2, 0, 2.2)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    K._mob(rec, roda)
    T(rec, "corda", (0.2, -0.2, 2.2), (0.2, -0.2, PISO + 0.95), 0.009, mats.corda, segs=3)
    balde = V.torno_local(
        "balde",
        [(0, 0), (0.13, 0), (0.16, 0.24), (0.14, 0.24), (0.11, 0.03), (0, 0.03)],
        8,
        mats.go,
    )
    M.mover(balde, Matrix.Translation((0.2, -0.2, PISO + 0.72)))
    K._mob(rec, balde)
    V.potes(rec, "lu", [(1.75, -1.3), (1.7, -0.7), (-1.75, 1.2)], mats, sem=sem)
    B(rec, "pedra_a", (1.1, 0.55, 0.12), (-1.5, -1.4, PISO + 0.06), mats.pedra, chanfro=0.02)
    X._cesto(rec, "cesto", (-1.75, 0.3), mats, r=0.3, alt=0.36, z=PISO)
    VC.camera(rec, (-3.2, -3.0, 1.6), (0.0, 0.0, 1.3))
    return rec


# =============================================================== 32. cemitério
def _tumulo(rec, nome, x, y, rot, tipo, mats, lat):
    m = V.lugar((x, y, 0.0), rot)
    o = []
    if tipo == 0:  # monte de terra com estela
        mt = M.superelipsoide(f"{nome}_m", 0.7, 1.05, 0.46, 0.9, 0.9, 9, 5)
        V.apagar_faces(mt, lambda c, n: c.z < -0.02)
        V.gravar_uv_local(mt, lambda p: (p.x, p.y, p.z))
        M.material(mt, mats.dat)
        o.append(M.suave(mt, 60))
        o.append(V.bloco(f"{nome}_e", (0.5, 0.08, 0.62), (0, 1.1, 0.31), mats.pedra, chanfro=0.02))
    elif tipo == 1:  # túmulo baixo de laterita
        o.append(V.bloco(f"{nome}_b", (1.3, 2.2, 0.22), (0, 0, 0.11), lat))
        o.append(V.bloco(f"{nome}_t", (0.95, 1.8, 0.28), (0, 0, 0.36), lat, chanfro=0.05))
        o.append(V.bloco(f"{nome}_e", (1.05, 0.16, 0.92), (0, 1.0, 0.46), mats.pedra, chanfro=0.03))
    else:  # lápide com telhadinho
        o.append(V.bloco(f"{nome}_b", (1.0, 1.7, 0.16), (0, 0, 0.08), mats.pedra))
        o.append(V.bloco(f"{nome}_e", (0.72, 0.14, 0.86), (0, 0.72, 0.43), lat))
        o.append(V.bloco(f"{nome}_c", (0.95, 0.34, 0.08), (0, 0.72, 0.9), mats.pedra, chanfro=0.02))
    for ob in o:
        M.mover(ob, m)
        K._mob(rec, ob)
    V._col_local(rec, nome, (x, y), rot, (x, y, 0.32), (1.2, 2.1, 0.64), "para", "Brick")


def receita_ret_pov_cemiterio():
    """Cemitério da família: muro baixo de laterita, túmulos desencontrados e um incensário."""
    rec = V.Receita()
    sem = 932
    mats = Mats(sem)
    lat = K.parede("laterita")
    a, b = 6.2, 4.8
    for nome, p, q in (
        ("m_f1", (-a, -b), (-1.1, -b)),
        ("m_f2", (1.1, -b), (a, -b)),
        ("m_t", (-a, b), (a, b)),
        ("m_e1", (-a, -b), (-a, 0.4)),
        ("m_e2", (-a, 2.2), (-a, b)),
        ("m_d", (a, -b), (a, b)),
    ):
        K.muro(rec, mats, nome, p, q, 0.7, lat, esp=0.26)
    pts = (
        (-4.4, 2.6, 8, 1),
        (-2.1, 2.9, -6, 0),
        (0.2, 2.5, 4, 2),
        (2.5, 2.8, -9, 0),
        (4.6, 2.5, 7, 1),
        (-4.6, -1.3, -4, 0),
        (-2.4, -1.0, 9, 2),
        (2.2, -1.2, -7, 1),
        (4.5, -1.4, 5, 0),
    )
    for k, (x, y, r, t) in enumerate(pts):
        _tumulo(rec, f"tum{k}", x, y, r, t, mats, lat)
    K.incensario(rec, "inc", 0.0, -1.6, mats, e=0.72)
    VC.camera(rec, (-0.6, -6.6, 1.7), (0.3, 1.8, 0.5))
    return rec


# =============================================================== 33. lavagem
def receita_ret_pov_lavagem():
    """Bến giặt: tanque raso de pedra com degraus, lajes de bater roupa e varal parado."""
    rec = V.Receita()
    sem = 933
    mats = Mats(sem)
    lat = K.parede("laterita")
    L, W = 7.6, 3.8
    for nome, c, d in (
        ("b_f", (0, -W / 2, 0.22), (L + 0.4, 0.34, 0.44)),
        ("b_t", (0, W / 2, 0.22), (L + 0.4, 0.34, 0.44)),
        ("b_e", (-L / 2, 0, 0.22), (0.34, W, 0.44)),
        ("b_d", (L / 2, 0, 0.22), (0.34, W, 0.44)),
    ):
        B(rec, nome, d, c, lat, est=True)
        rec.caixa(nome, c, d, "para", "Brick")
    agua = V.mat_liso("agua_tanque", "#3b4a3f", "#212c25", rug=0.05, escala=2.5, forca=0.25)
    B(rec, "agua", (L - 0.3, W - 0.3, 0.02), (0, 0, 0.3), agua)
    for k, x in enumerate((-2.4, -0.6, 1.2, 2.9)):
        B(rec, f"laje{k}", (1.25, 0.72, 0.1), (x, -W / 2 - 0.78, 0.32), mats.pedra, chanfro=0.02)
        B(rec, f"laje_p{k}", (1.0, 0.5, 0.28), (x, -W / 2 - 0.78, 0.14), lat)
        rec.caixa(f"laje{k}", (x, -W / 2 - 0.78, 0.18), (1.25, 0.72, 0.37), "para", "Brick")
    for k in range(3):
        B(
            rec,
            f"deg{k}",
            (1.5, 0.3, 0.12),
            (-L / 2 - 0.42 - k * 0.3, 0.0, 0.34 - k * 0.12),
            mats.pedra,
        )
    rec.caixa("degraus", (-L / 2 - 0.72, 0, 0.17), (0.9, 1.5, 0.34), "para", "Brick")
    tons = (("#7d3c34", "#a56a5c"), ("#c7c0ad", "#a59e8c"), ("#3f5f6f", "#6b8894"))
    panos = [N.mat_pano(f"rp{k}", cor=a, desbotado=b) for k, (a, b) in enumerate(tons)]
    yr = W / 2 + 1.15
    for s in (-1, 1):
        T(rec, f"varal_p{s}", (s * 3.2, yr, 0), (s * 3.2, yr, 2.1), 0.05, mats.tre, est=True)
        rec.caixa(f"varal_p{s}", (s * 3.2, yr, 1.05), (0.1, 0.1, 2.1), "passa", "Bamboo")
    T(rec, "varal", (-3.2, yr, 2.02), (3.2, yr, 2.02), 0.012, mats.corda, segs=3)
    for k in range(6):
        x = -2.6 + k * 1.02

        def f(u, v, x0=x, n0=k):
            return (
                x0 - 0.36 + u * 0.72,
                yr + 0.018 * math.sin(u * 8 + n0),
                2.0 - v * (0.9 + (n0 % 3) * 0.14),
            )

        o = V.grade(f"roupa{k}", f, 3, 2, fora=(0, -1, 0))
        M.solidificar(o, 0.008, 0.0)
        V.gravar_uv_local(o, lambda p: (p.x, p.z, p.y), k * 0.8)
        M.material(o, panos[k % 3])
        K._mob(rec, M.suave(o, 60))
    for k, x in enumerate((-3.0, 1.9, 3.5)):
        X._cesto(rec, f"ces{k}", (x, -W / 2 - 1.6), mats, r=0.3, alt=0.4)
    VC.camera(rec, (-4.5, -4.2, 1.6), (0.6, 0.6, 0.5))
    return rec


VC.FONTES["laterita_qngai"] = (
    "quangngai.gov.vn, indicado pelo dono: casas e muros de laterita em Vạn Tường"
)

CASAS: dict[str, dict] = {
    "ret_pov_laterita": {
        "nome": "casa de pedra laterítica",
        "tipo": "laterita, telha, varanda, altar, quintal com muro baixo",
        "fontes": ["laterita_qngai"],
        "atlas": K.ATLAS_LAT,
    },
    "ret_pov_patio": {
        "nome": "casa com pátio interno",
        "tipo": "laterita em U, cozinha externa, depósito, portão e pátio",
        "fontes": [],
        "atlas": K.ATLAS_LAT,
    },
    "ret_pov_abandonada": {
        "nome": "residência abandonada",
        "tipo": "taipa, telhado afundado, mato entrando e móveis virados",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_armazem": {
        "nome": "armazém de arroz",
        "tipo": "taipa e telha, três compartimentos ligados, tulhas, sacos, múltiplas entradas",
        "fontes": [],
        "atlas": K.ATLAS_G,
    },
    "ret_pov_bufalos": {
        "nome": "abrigo de búfalos",
        "tipo": "telheiro de palha, cocho, feno e arado",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_galinheiro": {
        "nome": "galinheiro e chiqueiro",
        "tipo": "bambu sobre pés, chiqueiro baixo e cercado",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_cestos": {
        "nome": "oficina de cestos",
        "tipo": "telheiro de nipa, feixes de bambu, cestos prontos",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_moinho": {
        "nome": "descascador de arroz",
        "tipo": "moinho de mó, pilão de pé, sacos e peneiras",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_medico": {
        "nome": "posto de atendimento",
        "tipo": "caiado e telha, leitos, armário, curativos e cortina",
        "fontes": [],
        "atlas": K.ATLAS_M,
    },
    "ret_pov_santuario": {
        "nome": "santuário de antepassados",
        "tipo": "nicho de telha sobre pedestal, oferendas e mureta",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_poco": {
        "nome": "poço comunitário",
        "tipo": "boca de laterita, roldana, cobertura de telha",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_cemiterio": {
        "nome": "cemitério tradicional",
        "tipo": "muro baixo e nove túmulos de três tipos",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
    "ret_pov_lavagem": {
        "nome": "lavagem de roupa",
        "tipo": "tanque de pedra, lajes de bater roupa e varal parado",
        "fontes": [],
        "atlas": K.ATLAS_P,
    },
}
