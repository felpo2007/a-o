"""Área piloto da Vila, Objetivo C (D-254, prompt V5 §11 e §19). Metros, Z para cima, frente em -Y.

Construções: `ret_vila_palafita_a/b` (casas sobre esteios, com dois cômodos),
`ret_vila_terra` (casa de taipa com cozinha), `ret_vila_dinh` (salão comunal) e
`ret_vila_torre` (torre de vigia).
Peças repetidas, feitas para instanciar: `ret_vila_posto`, `ret_vila_sacos`, `ret_vila_carga`,
`ret_vila_cerca`, `ret_vila_passarela` e `ret_vila_poca`.

Tudo parado: nenhum tecido, folha ou corda tem animação (sem vento, D-253). O grupo Casa usa
só materiais que têm faixa na trim sheet da vila (`vila_trim.FAIXAS`); as casas saem com
`ret.py <chave> --trim`.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_comum as E  # noqa: E402
import exp_vila as X  # noqa: E402
import modelar as M  # noqa: E402
import ret_comboio as RC  # noqa: E402
import ret_frente as RF  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

_est, _mob = RC._est, RC._mob


def _phen():
    return V.mat_phen("phen_par", "#b19a69", "#7f6f4a", passo=0.045)


def _jan(lado, ts, w=1.0):
    return [
        {"lado": lado, "t": t, "w": w, "z0": 1.05, "z1": 2.0, "estilo": "aberta", "aba": True}
        for t in ts
    ]


def _leque(nome, centro, borda):
    """Polígono plano em leque (a estrela da faixa)."""
    bm = bmesh.new()
    c = bm.verts.new(centro)
    vs = [bm.verts.new(p) for p in borda]
    for i, v in enumerate(vs):
        bm.faces.new((c, vs[(i + 1) % len(vs)], v))
    bm.normal_update()
    return M.de_bmesh(nome, bm)


def _letreiro(rec, nome, texto, centro, tam, mat, costas=False):
    """Texto de verdade em malha (a Arial tem as letras do vietnamita)."""
    cu = bpy.data.curves.new(nome, "FONT")
    cu.body = texto
    cu.font = bpy.data.fonts.load(r"C:\Windows\Fonts\arialbd.ttf", check_existing=True)
    cu.size = tam
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    cu.extrude = 0.004
    cu.resolution_u = 2
    temp = bpy.data.objects.new(nome, cu)
    bpy.context.scene.collection.objects.link(temp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(temp.evaluated_get(dg))
    bpy.data.objects.remove(temp)
    o = bpy.data.objects.new(f"{nome}_m", me)
    bpy.context.scene.collection.objects.link(o)
    V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
    giro = Matrix.Rotation(math.pi / 2, 4, "X")
    if costas:
        giro = Matrix.Rotation(math.pi, 4, "Z") @ giro
    M.mover(o, Matrix.Translation(centro) @ giro)
    M.material(o, mat)
    _mob(rec, o)


def _saco(rec, nome, x, y, z, rz, mats, k):
    """Saco de areia leve (cerca de 80 triângulos), para parede de cobertura."""
    s = M.superelipsoide(nome, 0.25, 0.17, 0.125, 0.35, 0.4, 8, 5)
    M.deslocar(s, lambda co, n, k=k: 0.012 * M.fbm(co * 8.0, 2, k))
    V.gravar_uv_local(s, lambda p: (p.x, p.y, p.z), float(k))
    M.mover(s, Matrix.Translation((x, y, z + 0.12)) @ Matrix.Rotation(math.radians(rz), 4, "Z"))
    M.material(s, mats.juta)
    _mob(rec, M.suave(s, 70))


def _parede_sacos(rec, nome, x0, x1, y, fiadas, mats, z=0.0):
    n = max(2, int((x1 - x0) / 0.47))
    passo = (x1 - x0) / n
    k = 0
    for f in range(fiadas):
        d = passo / 2 if f % 2 else 0.0
        for i in range(n - (f % 2)):
            rz = ((k * 37) % 11 - 5) * 1.2
            yy = y + ((k * 13) % 5 - 2) * 0.008
            _saco(
                rec, f"{nome}_{k}", x0 + passo / 2 + i * passo + d, yy, z + f * 0.215, rz, mats, k
            )
            k += 1
    alto = 0.26 + (fiadas - 1) * 0.215
    rec.caixa(nome, ((x0 + x1) / 2, y, z + alto / 2), (x1 - x0, 0.38, alto), "para", "Fabric")


def _tambor(rec, nome, x, y, mats, z=0.0, deitado=False):
    tinta = V.mat_liso("tambor", "#4d5636", "#2e3522", rug=0.55, escala=4.0, forca=0.45)
    r, h = 0.29, 0.88
    o = V.torno_local(
        f"{nome}_c",
        [
            (0.0, 0.0),
            (r - 0.015, 0.0),
            (r, 0.02),
            (r, h * 0.33),
            (r + 0.012, h * 0.34),
            (r, h * 0.35),
            (r, h * 0.66),
            (r + 0.012, h * 0.67),
            (r, h * 0.68),
            (r, h - 0.02),
            (r - 0.015, h),
            (0.0, h - 0.01),
        ],
        12,
        tinta,
    )
    if deitado:
        M.mover(o, Matrix.Translation((x - h / 2, y, z + r)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
        rec.caixa(nome, (x, y, z + r), (h, 2 * r, 2 * r), "para", "Metal")
    else:
        M.mover(o, Matrix.Translation((x, y, z)))
        rec.caixa(nome, (x, y, z + h / 2), (2 * r, 2 * r, h), "para", "Metal")
    _mob(rec, o)


def _deposito_baixo(rec, L, W, mats, sem):
    """O que fica guardado embaixo da casa, junto dos esteios, com o vão livre no meio."""
    X._lenha(rec, "lenha", -L / 2 + 0.5, -L / 2 + 2.0, W / 2 - 0.3, mats)
    pts = [
        (L / 2 - 1.9, W / 2 - 0.55, 12),
        (L / 2 - 1.4, W / 2 - 0.52, -8),
        (L / 2 - 0.9, W / 2 - 0.5, 20),
    ]
    V.sacos(rec, "sacos_a", pts, mats, z=0.02)
    V.sacos(
        rec,
        "sacos_b",
        [(L / 2 - 1.65, W / 2 - 0.52, 5), (L / 2 - 1.15, W / 2 - 0.5, -14)],
        mats,
        z=0.28,
    )
    rec.caixa("sacos", (L / 2 - 1.4, W / 2 - 0.52, 0.28), (1.6, 0.75, 0.56), "para", "Fabric")
    for k, (x, a, r) in enumerate(((-0.7, 0.72, 0.32), (-0.05, 0.6, 0.27))):
        o = V.chum(
            f"jarra{k}", (x, W / 2 - 0.45), mats, alt=a, r=r, tampa="madeira", sem=sem + k, z=0.0
        )
        rec.addv(o, "Mobilia", "Mobilia")
        rec.caixa(f"jarra{k}", (x, W / 2 - 0.45, a / 2), (2 * r, 2 * r, a), "para", "Ceramic")
    X._cesto(rec, "cesto_a", (L / 2 - 0.5, -0.5), mats, r=0.32, alt=0.5)
    X._cesto(rec, "cesto_b", (L / 2 - 0.55, 0.15), mats, r=0.26, alt=0.42)
    V.ferramentas(rec, "ferr", (0.9, W / 2 - 0.12), 0, mats, itens=("enxada", "ancinho", "foice"))


def _palafita(sem, L, W, Hp, quatro_aguas):
    """Casa de bambu e palha sobre esteios: varanda com escada, dois cômodos e depósito embaixo."""
    rec = V.Receita()
    mats = Mats(sem)
    H, esp = 2.8, 0.07
    phen = _phen()
    tranh = V.mat_tranh("tranh")
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        phen,
        [
            {"lado": "frente", "t": -L * 0.16, "estilo": "liep", "folha": 1},
            {"lado": "fundo", "t": L * 0.26, "estilo": "liep", "folha": -1},
        ],
        _jan("frente", (L * 0.28,))
        + _jan("fundo", (-L * 0.26,))
        + _jan("esq", (0.0,), 0.9)
        + _jan("dir", (0.0,), 0.9),
        col="Bamboo",
        bala="passa",
        sem=sem,
        postes_tre=True,
        nen_rets=[],
    )
    # a divisória entre a sala e o quarto, com vão de passagem
    xd = L * 0.12
    div = V.Lado((xd, -W / 2 + esp), math.pi / 2, W - 2 * esp, 0.06, 1.0)
    V.parede(
        rec,
        "div",
        div,
        0.0,
        H,
        phen,
        [(W * 0.3, 1.3, -1.0, PISO + 2.42)],
        "Bamboo",
        "passa",
        sem=sem + 1,
    )
    if quatro_aguas:
        V.telhado(
            rec,
            "tel",
            L,
            W,
            H,
            H + 2.65,
            0.75,
            "4aguas",
            "tranh",
            0.26,
            tranh,
            mats,
            beiral_oitao=0.7,
            sem=sem,
            tesouras=(-L / 4, L / 4),
        )
    else:
        V.telhado(
            rec,
            "tel",
            L,
            W,
            H,
            H + 2.2,
            0.6,
            "2aguas",
            "tranh",
            0.26,
            tranh,
            mats,
            beiral_oitao=0.45,
            sem=sem,
            tesouras=(0.0,),
            mat_oitao=phen,
            oitao_esp=esp,
            col_oitao="Bamboo",
        )
    xi, yi = L / 2 - esp, W / 2 - esp
    # o quarto (à direita da divisória)
    V.phan(rec, "phan", (xi - 1.05, yi - 0.72), 0, mats)
    V.ruong(rec, "arca", (xi - 0.3, -0.55), 90, mats)
    V.nonla_pendurado(rec, "nonla", (xd + 0.7, yi), 0, mats)
    X._cesto(rec, "ces_q", (xd + 0.5, -yi + 0.4), mats, r=0.28, alt=0.42, z=PISO)
    # a sala
    V.ban_tho(
        rec, "altar", (-L * 0.2, yi - 0.28), 0, mats, comp=1.1, prof=0.45, alt=0.98, painel=False
    )
    V.ban_thap(rec, "mesa", (-L * 0.24, -0.15), 90, mats)
    V.cho_tre(rec, "cho", (-xi + 0.62, 0.75), 90, mats)
    V.potes(rec, "lu", [(-xi + 0.42, -yi + 0.45), (-xi + 0.95, -yi + 0.38)], mats, sem=sem + 2)
    X._prateleira(rec, "est", (xd - 0.25, 1.15), 90, mats, comp=1.4, z=PISO)
    V.rede_pendurada(rec, "rede", (-xi + 0.12, -0.2), 90, mats, comp=1.2, queda=1.2)
    rec.transformar(marca, V.lugar((0.0, 0.0, Hp)))

    z_piso = Hp + PISO
    yv = -W / 2 - 1.9
    E.piso_tabuas(
        rec, "piso", -L / 2 - 0.05, -W / 2, L / 2 + 0.05, W / 2, z_piso, mats, largura=0.3, sem=1
    )
    E.piso_tabuas(
        rec, "varanda", -L / 2 - 0.05, yv, L / 2 + 0.05, -W / 2, z_piso, mats, largura=0.3, sem=2
    )
    E.barrotes(rec, "barrote", -L / 2, yv, L / 2, W / 2, z_piso, mats, passo=1.1)
    n = max(3, round(L / 2.4))
    xs = [-L / 2 + k * L / n for k in range(n + 1)]
    for k, (x, y) in enumerate((x, y) for x in xs for y in (-W / 2, 0.0, W / 2)):
        X._esteio(rec, f"esteio{k}", x, y, z_piso - 0.14, mats)
    for k, x in enumerate(xs):
        X._esteio(rec, f"poste_v{k}", x, yv + 0.05, Hp + 2.5, mats, r=0.085)
    for y in (yv + 0.05, -W / 2, 0.0, W / 2):
        _est(
            rec,
            V.viga(
                f"madre{int(y * 10)}",
                (-L / 2 - 0.1, y, z_piso - 0.27),
                (L / 2 + 0.1, y, z_piso - 0.27),
                0.11,
                0.14,
                mats.go_escuro,
            ),
        )
    _est(
        rec,
        V.viga(
            "frechal_v",
            (-L / 2 - 0.1, yv + 0.05, Hp + 2.5),
            (L / 2 + 0.1, yv + 0.05, Hp + 2.5),
            0.1,
            0.11,
            mats.go,
        ),
    )
    V.agua_unica(
        rec,
        "tel_var",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        -W / 2 + 0.02,
        Hp + 2.9,
        yv - 0.42,
        Hp + 2.55,
        0.2,
        "tranh",
        tranh,
        mats,
        sem=sem + 5,
    )
    for k, x in enumerate(xs):
        _est(
            rec,
            V.tre(
                f"caibro_v{k}",
                (x, yv - 0.25, Hp + 2.42),
                (x, -W / 2, Hp + 2.68),
                0.03,
                mats.tre,
                segs=5,
            ),
        )
    # guarda-corpo, com a passagem da escada à esquerda
    xe = -L / 2 + 1.0
    E.guarda_corpo(rec, "gc_frente", (xe + 0.75, yv), (L / 2, yv), z_piso, mats, passo=0.8)
    E.guarda_corpo(rec, "gc_canto", (-L / 2, yv), (xe - 0.75, yv), z_piso, mats, passo=0.6)
    E.guarda_corpo(rec, "gc_esq", (-L / 2, yv), (-L / 2, -W / 2), z_piso, mats, passo=0.7)
    E.guarda_corpo(rec, "gc_dir", (L / 2, yv), (L / 2, -W / 2), z_piso, mats, passo=0.7)
    E.escada(rec, "escada", (xe, yv - 3.2, 0.1), (xe, yv + 0.02, z_piso), 1.25, mats)
    soleira = V.bloco(
        "soleira", (1.45, 0.42, 0.1), (xe, yv - 3.28, 0.05), mats.pedra, chanfro=0.015
    )
    V.sem_fundo(soleira, 0.0)
    _est(rec, soleira)
    rec.caixa("soleira", (xe, yv - 3.28, 0.05), (1.45, 0.42, 0.1), "para", "Ground")
    _deposito_baixo(rec, L, W, mats, sem + 7)
    VC.camera(
        rec, (-L / 2 + 0.7, -W / 2 + 0.7, z_piso + 1.55), (L * 0.2, W / 2 - 0.8, z_piso + 0.7)
    )
    return rec


def receita_ret_vila_palafita_a():
    return _palafita(801, 10.4, 6.2, 2.5, True)


def receita_ret_vila_palafita_b():
    return _palafita(802, 7.8, 5.4, 2.4, False)


def receita_ret_vila_terra():
    """Casa térrea de taipa e palha, com varanda baixa e cozinha encostada."""
    rec = V.Receita()
    sem = 803
    mats = Mats(sem)
    L, W, H, esp = 9.4, 5.8, 2.75, 0.16
    vach = V.mat_vach_dat("vach_dat")
    tranh = V.mat_tranh("tranh")
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        vach,
        [
            {"lado": "frente", "t": -1.6, "estilo": "liep", "folha": 1},
            {"lado": "fundo", "t": 2.4, "estilo": "liep", "folha": -1},
        ],
        _jan("frente", (2.3,)) + _jan("fundo", (-2.4,)) + _jan("esq", (0.0,), 0.9),
        col="Earth",
        sem=sem,
    )
    xd = 1.0
    div = V.Lado((xd, -W / 2 + esp), math.pi / 2, W - 2 * esp, 0.08, 1.0)
    V.parede(rec, "div", div, 0.0, H, vach, [(1.7, 1.3, -1.0, PISO + 2.42)], "Earth", sem=sem + 1)
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        H + 2.5,
        0.75,
        "4aguas",
        "tranh",
        0.26,
        tranh,
        mats,
        beiral_oitao=0.7,
        sem=sem,
        tesouras=(-L / 4, L / 4),
    )
    yv = -W / 2 - 1.8
    V.nen(rec, "nen_v", -L / 2 - 0.15, yv - 0.15, L / 2 + 0.15, -W / 2, mats)
    xs = [-L / 2 + k * L / 4 for k in range(5)]
    for k, x in enumerate(xs):
        V.poste(rec, f"pv{k}", x, yv + 0.05, 2.4, mats.go, r=0.09, base_pedra=mats.pedra)
    _est(
        rec,
        V.viga(
            "fre_v",
            (-L / 2 - 0.1, yv + 0.05, 2.4),
            (L / 2 + 0.1, yv + 0.05, 2.4),
            0.11,
            0.13,
            mats.go,
        ),
    )
    V.agua_unica(
        rec,
        "tel_v",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        -W / 2 + 0.02,
        2.82,
        yv - 0.42,
        2.42,
        0.2,
        "tranh",
        tranh,
        mats,
        sem=sem + 5,
    )
    VC.cozinha(rec, mats, "coz", (L / 2 + 1.6, 0.7), 90, vach, tranh, "tranh", sem=sem + 6)
    xi, yi = L / 2 - esp, W / 2 - esp
    V.phan(rec, "phan", (xi - 1.05, yi - 0.72), 0, mats)
    V.ruong(rec, "arca", (xi - 0.3, -0.7), 90, mats)
    V.ban_tho(rec, "altar", (-2.0, yi - 0.28), 0, mats, comp=1.1, prof=0.45, alt=0.98, painel=False)
    V.ban_thap(rec, "mesa", (-2.3, -0.2), 90, mats)
    V.cho_tre(rec, "cho", (-xi + 0.62, 0.8), 90, mats)
    V.potes(rec, "lu", [(-xi + 0.42, -yi + 0.45), (-xi + 0.95, -yi + 0.38)], mats, sem=sem + 2)
    X._prateleira(rec, "est", (xd - 0.25, 1.2), 90, mats, comp=1.4, z=PISO)
    X._banco(rec, "banco_v", (2.6, -W / 2 - 0.42), 0, mats, comp=2.0, z=PISO)
    X._cesto(rec, "ces_v", (-3.6, yv + 0.6), mats, r=0.3, alt=0.42, z=PISO)
    VC.camera(rec, (-L / 2 + 0.7, -W / 2 + 0.7, PISO + 1.55), (2.0, W / 2 - 0.8, PISO + 0.7))
    return rec


def receita_ret_vila_dinh():
    """Salão comunal da vila: piso elevado, colunas de madeira e a grande cobertura de palha."""
    rec = V.Receita()
    sem = 804
    mats = Mats(sem)
    L, W, Z = 19.0, 10.8, 0.72
    H = Z + 3.05
    tranh = V.mat_tranh("tranh")
    E.piso_tabuas(rec, "piso", -L / 2, -W / 2, L / 2, W / 2, Z, mats)
    E.barrotes(rec, "barrote", -L / 2, -W / 2, L / 2, W / 2, Z, mats)
    nx, ny = 6, 3
    pontos = [
        (-L / 2 + i * L / nx, -W / 2 + j * W / ny) for i in range(nx + 1) for j in range(ny + 1)
    ]
    E.pilotis(rec, "esteio", pontos, Z - 0.14, mats, r=0.14)
    for k, (x, y) in enumerate(pontos):
        _est(rec, V.tre(f"col{k}", (x, y, Z), (x, y, H), 0.125, mats.go, segs=8))
        rec.caixa(f"col{k}", (x, y, (Z + H) / 2), (0.25, 0.25, H - Z), "para", "Wood")
    for s in (-1, 1):
        _est(
            rec,
            V.viga(
                f"fre_x{s}",
                (-L / 2 - 0.1, s * W / 2, H),
                (L / 2 + 0.1, s * W / 2, H),
                0.15,
                0.18,
                mats.go,
            ),
        )
        _est(
            rec,
            V.viga(
                f"fre_y{s}",
                (s * L / 2, -W / 2 - 0.1, H),
                (s * L / 2, W / 2 + 0.1, H),
                0.15,
                0.18,
                mats.go,
            ),
        )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        H + 3.5,
        1.15,
        "4aguas",
        "tranh",
        0.3,
        tranh,
        mats,
        beiral_oitao=1.15,
        sem=sem,
        tesouras=(),
    )
    RC._tesouras(rec, "tes", L, W, H, H + 3.5, 6, mats)
    meio = 1.1
    E.guarda_corpo(rec, "g_f_a", (-L / 2, -W / 2), (-meio, -W / 2), Z, mats, alt=0.78, passo=1.3)
    E.guarda_corpo(rec, "g_f_b", (meio, -W / 2), (L / 2, -W / 2), Z, mats, alt=0.78, passo=1.3)
    E.guarda_corpo(
        rec, "g_t_a", (-L / 2, W / 2), (L / 2 - 3.4, W / 2), Z, mats, alt=0.78, passo=1.3
    )
    E.guarda_corpo(rec, "g_e_a", (-L / 2, -W / 2), (-L / 2, W / 2), Z, mats, alt=0.78, passo=1.3)
    E.guarda_corpo(rec, "g_d_a", (L / 2, -W / 2), (L / 2, -meio), Z, mats, alt=0.78, passo=1.3)
    E.guarda_corpo(rec, "g_d_b", (L / 2, meio), (L / 2, W / 2), Z, mats, alt=0.78, passo=1.3)
    E.escada(rec, "esc_f", (0.0, -W / 2 - 1.25, 0.02), (0.0, -W / 2 + 0.02, Z), 1.9, mats)
    E.escada(rec, "esc_d", (L / 2 + 1.25, 0.0, 0.02), (L / 2 - 0.02, 0.0, Z), 1.9, mats)
    E.escada(
        rec, "esc_t", (L / 2 - 1.7, W / 2 + 1.25, 0.02), (L / 2 - 1.7, W / 2 - 0.02, Z), 1.9, mats
    )
    for k, x in enumerate((-5.6, 5.0)):
        marca = rec.marca()
        V.ban_thap(rec, f"mesa{k}", (x, 0.2), 0, mats, comp=2.6, larg=1.0, alt=0.76, banquinhos=0)
        rec.transformar(marca, V.lugar((0.0, 0.0, Z - PISO)))
        X._banco(rec, f"banco_a{k}", (x, -0.8), 0, mats, comp=2.4, z=Z)
        X._banco(rec, f"banco_b{k}", (x, 1.2), 0, mats, comp=2.4, z=Z)
    X._pote(rec, "pote_a", (-L / 2 + 0.7, -W / 2 + 0.7), mats, alt=0.7, r=0.3, z=Z, sem=sem)
    X._cesto(rec, "cesto_a", (L / 2 - 0.7, W / 2 - 0.7), mats, r=0.3, alt=0.46, z=Z)
    VC.camera(rec, (-8.2, -4.4, Z + 1.6), (5.0, 3.0, Z + 1.0))
    return rec


def receita_ret_vila_torre():
    """Torre de vigia de madeira, com escada, plataforma com sacos e cobertura de palha."""
    rec = V.Receita()
    sem = 805
    mats = Mats(sem)
    S, Zp = 1.7, 5.6
    tranh = V.mat_tranh("tranh")
    for sx in (-1, 1):
        for sy in (-1, 1):
            base = (sx * (S + 0.3), sy * (S + 0.3), 0.0)
            topo = (sx * S, sy * S, Zp + 2.55)
            _est(rec, V.tre(f"pe{sx}{sy}", base, topo, 0.16, mats.go_escuro, segs=8))
            meio = ((base[0] + topo[0]) / 2, (base[1] + topo[1]) / 2, (Zp + 2.55) / 2)
            rec.caixa(f"pe{sx}{sy}", meio, (0.34, 0.34, Zp + 2.55), "para", "Wood")
    for z0, z1 in ((0.45, 2.7), (2.7, 5.15)):
        for s in (-1, 1):
            k = 0.3 * (1 - z0 / (Zp + 2.55))
            k1 = 0.3 * (1 - z1 / (Zp + 2.55))
            for a, b in (((-S - k, z0), (S + k1, z1)), ((S + k, z0), (-S - k1, z1))):
                _est(
                    rec,
                    V.viga(
                        f"xa{int(z0)}{s}{a[0]:.1f}",
                        (a[0], s * S, a[1]),
                        (b[0], s * S, b[1]),
                        0.1,
                        0.12,
                        mats.go,
                    ),
                )
                _est(
                    rec,
                    V.viga(
                        f"xb{int(z0)}{s}{a[0]:.1f}",
                        (s * S, a[0], a[1]),
                        (s * S, b[0], b[1]),
                        0.1,
                        0.12,
                        mats.go,
                    ),
                )
    for z in (2.7, 5.15):
        for s in (-1, 1):
            _est(
                rec,
                V.viga(
                    f"anel_x{int(z)}{s}",
                    (-S - 0.2, s * S, z),
                    (S + 0.2, s * S, z),
                    0.12,
                    0.14,
                    mats.go_escuro,
                ),
            )
            _est(
                rec,
                V.viga(
                    f"anel_y{int(z)}{s}",
                    (s * S, -S - 0.2, z),
                    (s * S, S + 0.2, z),
                    0.12,
                    0.14,
                    mats.go_escuro,
                ),
            )
    P = S + 0.55
    E.piso_tabuas(rec, "plat", -P, -P, P, P, Zp, mats)
    E.barrotes(rec, "plat_b", -P, -P, P, P, Zp, mats, passo=0.7)
    for lado, (a, b) in enumerate((((-P, P), (P, P)), ((P, -P), (P, P)), ((-P, -P), (-P, P)))):
        E.guarda_corpo(rec, f"gc{lado}", a, b, Zp, mats, alt=1.0, passo=0.7)
    E.guarda_corpo(rec, "gc3", (0.2, -P), (P, -P), Zp, mats, alt=1.0, passo=0.7)
    _parede_sacos(rec, "sacos_p", -P + 0.1, P - 0.1, P - 0.3, 3, mats, z=Zp)
    marca = rec.marca()
    V.telhado(
        rec,
        "tel",
        2 * S + 0.1,
        2 * S + 0.1,
        Zp + 2.55,
        Zp + 3.75,
        0.7,
        "4aguas",
        "tranh",
        0.2,
        tranh,
        mats,
        beiral_oitao=0.7,
        sem=sem,
    )
    rec.transformar(marca, V.lugar((0.0, 0.0, 0.0)))
    E.escada(rec, "escada", (-0.9, -P - 5.0, 0.04), (-0.9, -P + 0.02, Zp), 1.1, mats)
    X._lanterna(rec, "lan", (0.0, 0.0, Zp + 2.25), mats)
    _tambor(rec, "tam", S + 0.15, -S - 0.2, mats, z=0.0)
    VC.camera(rec, (-1.0, -P + 0.5, Zp + 1.65), (1.2, P, Zp + 1.2))
    return rec


def receita_ret_vila_posto():
    """Posto de controle na entrada da vila: pórtico com faixa, cancela erguida, guarita e sacos."""
    rec = V.Receita()
    sem = 806
    mats = Mats(sem)
    A = 4.9  # o vão livre passa o comboio e o tanque
    Hp = 5.0
    for s in (-1, 1):
        _est(
            rec,
            V.tre(
                f"pilar{s}", (s * A, 0.0, 0.0), (s * A, 0.0, Hp + 0.3), 0.19, mats.go_escuro, segs=8
            ),
        )
        rec.caixa(f"pilar{s}", (s * A, 0.0, (Hp + 0.3) / 2), (0.4, 0.4, Hp + 0.3), "para", "Wood")
        for y in (-1, 1):
            _est(
                rec,
                V.viga(
                    f"escora{s}{y}", (s * A, y * 1.1, 0.0), (s * A, 0.0, 2.2), 0.11, 0.12, mats.go
                ),
            )
    for z in (Hp, Hp - 1.05):
        _est(
            rec,
            V.viga(
                f"trave{int(z * 10)}",
                (-A - 0.5, 0.0, z),
                (A + 0.5, 0.0, z),
                0.17,
                0.2,
                mats.go_escuro,
            ),
        )
    faixa = V.bloco("faixa", (6.4, 0.04, 0.82), (0.0, -0.12, Hp - 0.52), mats.pano_verm)
    _mob(rec, faixa)
    ouro = V.mat_liso("ouro_faixa", "#c79a3a", "#8c6a24", rug=0.6, escala=6.0, forca=0.3)
    for sx in (-1, 1):
        pts = []
        for i in range(10):
            a = math.pi / 2 + i * math.pi / 5
            r = 0.3 if i % 2 == 0 else 0.125
            pts.append((sx * 2.55 + r * math.cos(a), -0.15, Hp - 0.52 + r * math.sin(a)))
        est = _leque(f"estrela{sx}", (sx * 2.55, -0.15, Hp - 0.52), pts)
        V.gravar_uv_local(est, lambda p: (p.x, p.z, p.y))
        M.material(est, ouro)
        _mob(rec, est)
    _letreiro(rec, "placa_f", "TRẠM KIỂM SOÁT", (0.0, -0.15, Hp - 0.56), 0.5, ouro)
    _letreiro(rec, "placa_c", "TRẠM KIỂM SOÁT", (0.0, -0.09, Hp - 0.56), 0.5, ouro, costas=True)
    # a cancela erguida, listrada de vermelho e branco, encostada no pilar
    branco = V.mat_liso("cancela_br", "#c9c2ae", "#918a78", rug=0.75, escala=5.0, forca=0.3)
    vermelho = V.mat_liso("cancela_vm", "#8a2f25", "#5a1f18", rug=0.75, escala=5.0, forca=0.3)
    x0, z0 = -A + 0.25, 1.05
    ang = math.radians(74)
    n = 8
    comp = 5.6
    for k in range(n):
        a = comp * k / n
        b = comp * (k + 1) / n
        p0 = (x0 + a * math.cos(ang), -0.42, z0 + a * math.sin(ang))
        p1 = (x0 + b * math.cos(ang), -0.42, z0 + b * math.sin(ang))
        _mob(rec, V.viga(f"cancela{k}", p0, p1, 0.09, 0.09, branco if k % 2 else vermelho))
    _mob(
        rec,
        V.bloco(
            "contrapeso", (0.6, 0.2, 0.26), (x0 - 0.2, -0.42, z0 - 0.3), mats.pedra, chanfro=0.02
        ),
    )
    # guarita do lado direito, fora da pista
    xg = A + 2.2
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "g",
        2.6,
        2.4,
        2.45,
        0.07,
        _phen(),
        [{"lado": "frente", "t": -0.4, "estilo": "liep", "folha": 1}],
        _jan("esq", (0.0,), 0.9),
        col="Bamboo",
        bala="passa",
        sem=sem,
        postes_tre=True,
    )
    V.telhado(
        rec,
        "tel_g",
        2.6,
        2.4,
        2.45,
        3.75,
        0.45,
        "4aguas",
        "tranh",
        0.2,
        V.mat_tranh("tranh"),
        mats,
        beiral_oitao=0.45,
        sem=sem,
    )
    V.cadeiras_mesa(rec, "mesa_g", (0.45, 0.45), 0, mats)
    rec.transformar(marca, V.lugar((xg, 1.1, 0.0)))
    _parede_sacos(rec, "sacos_a", A + 0.7, A + 4.0, -1.2, 4, mats)
    _parede_sacos(rec, "sacos_b", -A - 3.6, -A - 0.5, -1.2, 4, mats)
    _tambor(rec, "tam_a", -A - 1.2, 0.5, mats)
    _tambor(rec, "tam_b", -A - 1.85, 0.72, mats)
    VC.camera(rec, (-1.5, -8.5, 1.7), (0.0, 0.0, 2.6))
    return rec


def receita_ret_vila_sacos():
    rec = V.Receita()
    mats = Mats(807)
    _parede_sacos(rec, "fr", -2.4, 2.4, -0.2, 4, mats)
    _parede_sacos(rec, "tr", -2.2, 2.2, 0.17, 3, mats)
    VC.camera(rec, (-3.2, -3.6, 1.3), (0.2, 0.0, 0.5))
    return rec


def receita_ret_vila_carga():
    rec = V.Receita()
    mats = Mats(808)
    X._caixote(rec, "cx_a", (-0.75, 0.15), 8, mats, dim=(1.2, 0.85, 0.8))
    X._caixote(rec, "cx_b", (0.55, 0.3), -6, mats, dim=(1.2, 0.85, 0.8))
    X._caixote(rec, "cx_c", (-0.3, 0.2), 14, mats, dim=(1.0, 0.75, 0.62), z=0.8)
    _tambor(rec, "t_a", 1.75, -0.2, mats)
    _tambor(rec, "t_b", 1.55, 0.45, mats)
    _tambor(rec, "t_c", -1.9, -0.25, mats, deitado=True)
    VC.camera(rec, (-2.8, -3.4, 1.4), (0.2, 0.1, 0.6))
    return rec


def receita_ret_vila_cerca():
    rec = V.Receita()
    mats = Mats(809)
    L = 4.0
    for k in range(3):
        x = -L / 2 + 0.06 + k * (L - 0.12) / 2
        _est(
            rec,
            V.tre(f"p{k}", (x, 0.0, 0.0), (x, 0.0, 1.22 + (k % 2) * 0.05), 0.055, mats.tre, segs=5),
        )
    for j, z in enumerate((0.42, 0.78, 1.1)):
        d = ((j * 7) % 3 - 1) * 0.012
        _est(
            rec,
            V.tre(
                f"t{j}",
                (-L / 2, 0.05, z),
                (L / 2, 0.05, z + d),
                0.028,
                mats.tre,
                segs=4,
                sem=j + 1.0,
            ),
        )
    rec.caixa("cerca", (0.0, 0.02, 0.62), (L, 0.16, 1.24), "passa", "Bamboo")
    VC.camera(rec, (-2.6, -3.2, 1.3), (0.2, 0.0, 0.6))
    return rec


def receita_ret_vila_passarela():
    rec = V.Receita()
    mats = Mats(810)
    L, W, Z = 6.0, 1.4, 0.46
    E.piso_tabuas(rec, "piso", -L / 2, -W / 2, L / 2, W / 2, Z, mats, largura=0.28)
    for s in (-1, 1):
        _est(
            rec,
            V.viga(
                f"long{s}",
                (-L / 2, s * 0.55, Z - 0.13),
                (L / 2, s * 0.55, Z - 0.13),
                0.12,
                0.14,
                mats.go_escuro,
            ),
        )
    for k in range(4):
        x = -L / 2 + 0.2 + k * (L - 0.4) / 3
        for s in (-1, 1):
            _est(
                rec,
                V.tre(
                    f"p{k}{s}",
                    (x, s * 0.6, 0.0),
                    (x, s * 0.6, Z - 0.12),
                    0.08,
                    mats.go_escuro,
                    segs=6,
                ),
            )
    VC.camera(rec, (-4.2, -2.8, 1.3), (0.4, 0.0, 0.4))
    return rec


def receita_ret_vila_poca():
    """Poça de lama, plana e lisa: reflete o céu. Sem colisão (o jogo tira)."""
    rec = V.Receita()
    agua = V.mat_liso("agua_poca", "#312d22", "#1a1812", rug=0.06, escala=2.0, forca=0.2)

    def f(u, v):
        a = 2 * math.pi * v
        r = u * 1.5 * (1 + 0.22 * math.sin(3 * a + 1.0) + 0.12 * math.sin(7 * a + 0.4))
        return (r * math.cos(a) * 1.35, r * math.sin(a), 0.02)

    o = V.grade("poca", f, 4, 26, fora=(0, 0, 1))
    V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
    M.material(o, agua)
    _mob(rec, M.suave(o, 60))
    VC.camera(rec, (-2.4, -2.6, 1.6), (0.0, 0.0, 0.0))
    return rec


CASAS: dict[str, dict] = {
    "ret_vila_palafita_a": {
        "nome": "casa sobre esteios (grande)",
        "tipo": "bambu e palha em quatro águas, varanda, dois cômodos e depósito embaixo",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
    "ret_vila_palafita_b": {
        "nome": "casa sobre esteios (pequena)",
        "tipo": "bambu e palha em duas águas, varanda, dois cômodos e depósito embaixo",
        "fontes": [],
        "atlas": RF.ATLAS_M,
    },
    "ret_vila_terra": {
        "nome": "casa de taipa",
        "tipo": "taipa e palha, varanda baixa, dois cômodos e cozinha encostada",
        "fontes": [],
        "atlas": RF.ATLAS_M,
    },
    "ret_vila_dinh": {
        "nome": "salão comunal da vila",
        "tipo": "piso elevado, colunas de madeira e grande cobertura de palha",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
    "ret_vila_torre": {
        "nome": "torre de vigia",
        "tipo": "torre de madeira com escada, plataforma, sacos de areia e palha",
        "fontes": [],
        "atlas": RF.ATLAS_M,
    },
    "ret_vila_posto": {
        "nome": "posto de controle",
        "tipo": "pórtico com faixa, cancela erguida, guarita e sacos de areia",
        "fontes": [],
        "atlas": RF.ATLAS_M,
    },
    "ret_vila_sacos": {
        "nome": "parede de sacos de areia",
        "tipo": "cobertura baixa, feita para repetir",
        "fontes": [],
        "atlas": RF.ATLAS_P,
    },
    "ret_vila_carga": {
        "nome": "caixas e tambores",
        "tipo": "conjunto de carga, feito para repetir",
        "fontes": [],
        "atlas": RF.ATLAS_P,
    },
    "ret_vila_cerca": {
        "nome": "cerca de bambu",
        "tipo": "trecho de 4 m, leve, feito para repetir",
        "fontes": [],
        "atlas": RF.ATLAS_P,
    },
    "ret_vila_passarela": {
        "nome": "passarela de tábuas",
        "tipo": "trecho de 6 m sobre a lama",
        "fontes": [],
        "atlas": RF.ATLAS_P,
    },
    "ret_vila_poca": {
        "nome": "poça de lama",
        "tipo": "espelho d'água plano, sem colisão",
        "fontes": [],
        "atlas": RF.ATLAS_P,
    },
}
