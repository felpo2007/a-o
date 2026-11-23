"""Construções novas da Vila (D-232). Metros, Z para cima, frente (porta principal) em -Y.

Mesmo caminho das casas da vila: `Receita` com grupos `Telhado`, `Casa` e `Mobilia`; o grupo Casa
só usa materiais com faixa na trim sheet (`vila_trim.FAIXAS`), e o que for diferente (chapa de
zinco, pintura) fica nos atlas próprios de 512.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_comum as E  # noqa: E402
import modelar as M  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from modelar import Mat, rgb  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

ATLAS_512 = {
    "Telhado": {"tex": 512, "amostras_ao": 32},
    "Mobilia": {"tex": 512, "amostras_ao": 32},
    "Casa": {"amostras_ao": 32},
}
# modelos pequenos (teto de 6 mil triângulos no total)
ATLAS_PEQUENO = {
    "Telhado": {"tex": 512, "amostras_ao": 32, "teto": 1300},
    "Mobilia": {"tex": 512, "amostras_ao": 32, "teto": 2000},
    "Casa": {"amostras_ao": 32},
}
# abrigo: a terra de dentro não vê o céu, e sem isto o atlas a encolhia
ATLAS_ABRIGO = {
    "Telhado": {"tex": 512, "amostras_ao": 32, "visibilidade": False},
    "Mobilia": {"tex": 512, "amostras_ao": 32},
    "Casa": {"amostras_ao": 32},
}


# =============================================================== peças desta expansão
def _col(rec, nome, x0, y0, z0, x1, y1, z1, bala="para", material="Wood"):
    """Caixa de colisão pelos dois cantos."""
    rec.caixa(
        nome,
        ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)),
        bala,
        material,
    )


def _abertura(rec, nome, centro, normal, larg, alt):
    """Registra uma abertura passável sem folha (as bocas do abrigo)."""
    rec.extras["portas_m"].append(list(centro))
    rec.extras["portas"].append(
        {
            "nome": nome,
            "largura_livre_m": larg,
            "altura_livre_m": alt,
            "normal_blender": list(normal),
            "interna": False,
        }
    )


def _esteio(rec, nome, x, y, z1, mats: Mats, r=0.1, z0=0.0, pedra=True):
    """Esteio roliço barato (8 lados, sem fundo) com uma laje de pedra no pé."""
    h = z1 - z0
    o = V.cilindro(nome, r, h, (x, y, z0 + h / 2), mats.go_escuro, segs=8)
    V.sem_fundo(o, z0)
    rec.add(o, "Casa", "Estrutura")
    if pedra:
        s = V.bloco(
            f"{nome}_ped",
            (r * 3.0, r * 3.0, 0.09),
            (x, y, z0 + 0.045),
            mats.pedra,
            rot=(0, 0, 0.4 + x * y),
        )
        V.sem_fundo(s, z0)
        rec.add(s, "Casa", "Estrutura")
    rec.caixa(nome, (x, y, z0 + h / 2), (2 * r, 2 * r, h), "para", "Wood")


def _colocar(rec, objs, nome, pos, rot, z, centro, dim, bala="para", material="Wood"):
    """Põe as peças de um móvel no lugar, no grupo Mobilia, com uma caixa de colisão."""
    m = V.lugar((pos[0], pos[1], z), rot)
    for ob in objs:
        M.mover(ob, m)
    rec.addv(objs, "Mobilia", "Mobilia")
    V._col_local(rec, nome, pos, rot, (centro[0], centro[1], z + centro[2]), dim, bala, material)


def _cesto(rec, nome, pos, mats: Mats, r=0.3, alt=0.45, z=0.0):
    perfil = [
        (0.0, 0.0),
        (r * 0.7, 0.0),
        (r * 0.95, alt * 0.3),
        (r, alt * 0.75),
        (r * 0.86, alt),
        (r * 0.74, alt),
        (r * 0.76, alt * 0.8),
        (0.0, alt * 0.12),
    ]
    o = V.torno_local(nome, perfil, 10, mats.esteira)
    M.mover(o, Matrix.Translation((pos[0], pos[1], z)))
    V.sem_fundo(o, z)
    rec.add(o, "Mobilia", "Mobilia")
    rec.caixa(nome, (pos[0], pos[1], z + alt / 2), (1.7 * r, 1.7 * r, alt), "passa", "Bamboo")


def _pote(rec, nome, pos, mats: Mats, alt=0.7, r=0.32, z=0.0, tampa=None, sem=0):
    o = V.chum(nome, pos, mats, alt=alt, r=r, tampa=tampa, sem=sem, z=z)
    rec.addv(o, "Mobilia", "Mobilia")
    rec.caixa(nome, (pos[0], pos[1], z + alt / 2), (1.7 * r, 1.7 * r, alt), "para", "Ceramic")


def _lenha(rec, nome, x0, x1, y, mats: Mats, z=0.0, filas=3):
    """Pilha de lenha ao longo de X."""
    k = 0
    for f in range(filas):
        n = filas - f + 1
        for i in range(n):
            yy = y + (i - (n - 1) / 2) * 0.16
            zz = z + 0.08 + f * 0.135
            dx = 0.05 * math.sin(k * 2.1)
            rec.add(
                V.tre(
                    f"{nome}{k}",
                    (x0 + dx, yy, zz),
                    (x1 + dx * 0.5, yy, zz),
                    0.07 + 0.012 * math.sin(k * 1.7),
                    mats.go,
                    segs=5,
                    sem=k * 0.3,
                ),
                "Mobilia",
                "Mobilia",
            )
            k += 1
    _col(rec, nome, x0, y - (filas + 1) * 0.08, z, x1, y + (filas + 1) * 0.08, z + filas * 0.14)


def _banco(rec, nome, pos, rot, mats: Mats, comp=1.25, larg=0.34, alt=0.44, z=0.0):
    o = [V.bloco(f"{nome}_tampo", (comp, larg, 0.05), (0, 0, alt - 0.025), mats.go, chanfro=0.008)]
    for sx in (-1, 1):
        o.append(
            V.bloco(
                f"{nome}_pe{sx}",
                (0.05, larg - 0.06, alt - 0.05),
                (sx * (comp / 2 - 0.12), 0, (alt - 0.05) / 2),
                mats.go_escuro,
            )
        )
    o.append(V.bloco(f"{nome}_trav", (comp - 0.3, 0.04, 0.06), (0, 0, alt - 0.14), mats.go_escuro))
    _colocar(rec, o, nome, pos, rot, z, (0, 0, alt / 2), (comp, larg, alt))


def _caixote(rec, nome, pos, rot, mats: Mats, dim=(0.85, 0.6, 0.6), z=0.0):
    """Caixote de tábuas com cantoneiras e um X na frente (-Y)."""
    a, b, c = dim
    o = [V.bloco(f"{nome}_corpo", (a - 0.04, b - 0.04, c - 0.04), (0, 0, c / 2), mats.go)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                V.bloco(
                    f"{nome}_can{sx}{sy}",
                    (0.07, 0.07, c),
                    (sx * (a / 2 - 0.035), sy * (b / 2 - 0.035), c / 2),
                    mats.go_escuro,
                )
            )
    for sy in (-1, 1):
        for zz in (0.035, c - 0.035):
            o.append(
                V.bloco(
                    f"{nome}_h{sy}{int(zz * 100)}",
                    (a, 0.03, 0.07),
                    (0, sy * (b / 2 - 0.012), zz),
                    mats.go_escuro,
                )
            )
    for s in (-1, 1):
        o.append(
            V.viga(
                f"{nome}_x{s}",
                (-(a / 2 - 0.07), -b / 2 - 0.006, c / 2 - s * (c / 2 - 0.07)),
                (a / 2 - 0.07, -b / 2 - 0.006, c / 2 + s * (c / 2 - 0.07)),
                0.06,
                0.022,
                mats.go_escuro,
                cima=(0, 1, 0),
            )
        )
    _colocar(rec, o, nome, pos, rot, z, (0, 0, c / 2), dim)


def _prateleira(rec, nome, pos, rot, mats: Mats, comp=1.6, prof=0.38, alt=1.7, z=0.0):
    """Estante de 3 tábuas com potes de barro."""
    o = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                V.bloco(
                    f"{nome}_m{sx}{sy}",
                    (0.06, 0.06, alt),
                    (sx * (comp / 2 - 0.04), sy * (prof / 2 - 0.04), alt / 2),
                    mats.go_escuro,
                )
            )
    niveis = (0.3, 0.92, 1.54)
    for k, zz in enumerate(niveis):
        o.append(V.bloco(f"{nome}_t{k}", (comp, prof, 0.035), (0, 0, zz), mats.go, chanfro=0.004))
    itens = (
        (-0.5, 0, 0.12, 0.28),
        (-0.15, 0, 0.1, 0.22),
        (0.42, 0, 0.13, 0.3),
        (-0.45, 1, 0.11, 0.26),
        (0.2, 1, 0.13, 0.3),
        (0.55, 1, 0.09, 0.2),
        (-0.2, 2, 0.1, 0.22),
        (0.35, 2, 0.09, 0.2),
    )
    for k, (dx, nv, r, h) in enumerate(itens):
        p = V.torno_local(
            f"{nome}_pote{k}",
            [
                (0.0, 0.0),
                (r * 0.65, 0.0),
                (r, h * 0.45),
                (r * 0.8, h * 0.82),
                (r * 0.52, h * 0.92),
                (r * 0.6, h),
                (0.0, h * 0.95),
            ],
            8,
            mats.barro_escuro if k % 3 == 0 else mats.barro,
            sem=float(k),
        )
        M.mover(p, Matrix.Translation((dx, 0.02 * (k % 2), niveis[nv] + 0.0175)))
        o.append(p)
    _colocar(rec, o, nome, pos, rot, z, (0, 0, alt / 2), (comp, prof, alt))


def _lanterna(rec, nome, pos, mats: Mats, sy=-1.0):
    """Lanterna de querosene num braço de ferro preso à parede (`sy` aponta para dentro da sala)."""
    x, y, z = pos
    vidro = V.mat_liso("vidro_lanterna", "#e9c27a", "#c98f45", rug=0.25)
    o = [
        V.viga(
            f"{nome}_braco",
            (x, y, z + 0.24),
            (x, y + sy * 0.16, z + 0.24),
            0.018,
            0.018,
            mats.ferro,
        ),
        V.cilindro(f"{nome}_base", 0.065, 0.05, (x, y + sy * 0.16, z - 0.09), mats.ferro, segs=8),
        V.cilindro(f"{nome}_vidro", 0.05, 0.13, (x, y + sy * 0.16, z), vidro, segs=8),
        V.cilindro(f"{nome}_topo", 0.058, 0.035, (x, y + sy * 0.16, z + 0.083), mats.ferro, segs=8),
        V.tre(
            f"{nome}_alca",
            (x, y + sy * 0.16, z + 0.1),
            (x, y + sy * 0.16, z + 0.24),
            0.006,
            mats.ferro,
            segs=4,
        ),
    ]
    rec.addv(o, "Mobilia", "Mobilia")


def _mat_terra(nome="terra", coord="objeto"):
    """Terra vermelha do monte e dos cortes: torrões e manchas secas, sem capim (o `mat_dat` traz
    um verde fixo que, em área grande, parecia camuflagem). Com `coord="local"`, o ruído segue o
    atributo `local` (a trincheira o grava periódico, para a peça emendar sem costura)."""
    m = Mat(nome, rug=0.96)
    p = m.coord(coord)
    cor = m.rampa(m.ruido(p, 2.0, 6), [(0.3, rgb("#5f3a24")), (0.7, rgb("#8f5a38"))])
    torrao = m.voronoi(p, 9.0, "F1")
    cor = m.misturar(m.faixa(torrao, 0.25, 0.5, 0.0, 0.3), cor, rgb("#3f2818"))
    cor = m.misturar(m.faixa(m.ruido(p, 1.2, 4), 0.5, 0.66, 0.0, 0.35), cor, rgb("#a8744a"))
    m.cor(cor)
    m.relevo(torrao, 0.6, 0.02)
    return m.m


def _pano_terra(rec, nome, a, b, z0, z1, mat, fora, nu=6, nv=4, amp=0.035, sem=0):
    """Parede de terra de `a` a `b` (x, y), de `z0` a `z1` (números ou funções do ponto), com a face
    para `fora` e um relevo leve que some nas bordas (para encostar nos esteios)."""
    pa, pb = Vector((a[0], a[1], 0.0)), Vector((b[0], b[1], 0.0))
    n = Vector(fora).normalized()
    fz0 = z0 if callable(z0) else (lambda _p: z0)
    fz1 = z1 if callable(z1) else (lambda _p: z1)

    def f(u, v):
        p = pa.lerp(pb, u)
        zz = fz0(p) + (fz1(p) - fz0(p)) * v
        q = Vector((p.x, p.y, zz))
        borda = min(1.0, 4 * min(u, 1 - u), 4 * min(v, 1 - v))
        return tuple(q + n * (amp * borda * M.fbm(q * 1.7, 3, sem)))

    o = V.grade(nome, f, nu, nv, fora=n)
    V.gravar_uv_local(o, lambda p: (p.x + p.y, p.z, 0.0))
    M.material(o, mat)
    rec.add(M.suave(o, 60), "Telhado", "Telhado")
    return o


def _tabua_perfil(nome, x, larg, pts, esp, mat):
    """Tábua ao longo de Y com a face de cima na polilinha `pts` [(y, z)]: dobra nas pontas."""
    meia = larg / 2
    n = len(pts)

    def f(u, v):
        i = min(n - 1, round(u * (n - 1)))
        y, z = pts[i]
        return (x - meia + larg * v, y, z)

    topo = V.grade(f"{nome}_topo", f, n - 1, 1, fora=Vector((0, 0, 1)))
    M.solidificar(topo, esp, -1.0)
    V.gravar_uv_local(topo, lambda p: (p.x, p.z, p.y))
    M.material(topo, mat)
    return M.suave(topo, 35)


def receita_exp_palafita_a():
    """Casa de madeira sobre esteios: tábua, telhado de chapa remendado, varanda na frente com
    escada lateral, dois cômodos por dentro e, embaixo, um depósito de sacos, cestos e potes."""
    rec = V.Receita()
    mats = Mats(21)
    Hp = 2.3  # do chão ao referencial da casa; o piso fica em Hp + PISO
    L, W, H, esp = 7.0, 4.8, 2.6, 0.08
    van = V.mat_tabua("van")
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        van,
        [{"lado": "frente", "t": -0.9, "estilo": "van", "folha": -1}],
        [
            {"lado": "frente", "t": 1.9, "estilo": "tre", "aba": True},
            {"lado": "fundo", "t": -1.6, "w": 0.7, "estilo": "tre"},
            {"lado": "fundo", "t": 1.6, "w": 0.7, "estilo": "tre"},
            {"lado": "esq", "t": 0.0, "w": 0.7, "estilo": "tre"},
            {"lado": "dir", "t": 0.0, "w": 0.7, "estilo": "tre"},
        ],
        col="Wood",
        sem=21,
        nen_rets=[],
    )
    # divisória com vão entre a sala e o quarto
    div = V.Lado((0.6, -W / 2 + esp), 1.5707963, W - 2 * esp, 0.06, 1.0)
    V.parede(
        rec,
        "divisoria",
        div,
        0.0,
        H,
        van,
        [(1.1, 1.12, -1.0, PISO + 2.36)],
        "Wood",
        "para",
        sem=22,
    )
    E.oitao_tabuas(rec, "oitao", L, W, H, 4.35, van)
    E.telhado_chapa(rec, "tel", L, W, H, 4.35, 0.55, mats, sem=21, ferrugem=0.9)
    # móveis
    yi = W / 2 - esp
    V.phan(rec, "phan", (2.2, 1.35), 0, mats)
    V.ruong(rec, "arca", (3.0, -1.7), 90, mats)
    V.nonla_pendurado(rec, "nonla", (1.4, yi), 0, mats)
    V.ban_tho(rec, "altar", (-1.7, yi - 0.36), 0, mats)
    V.ban_thap(rec, "mesa", (-1.8, -0.4), 0, mats)
    V.cho_tre(rec, "cho", (-2.75, 0.9), 90, mats)
    V.potes(rec, "lu", [(-3.05, -1.85), (-2.6, -1.95)], mats, sem=23)
    V.rede_pendurada(rec, "rede", (0.75, -1.2), 90, mats, comp=1.4, queda=1.2)
    rec.transformar(marca, V.lugar((0.0, 0.0, Hp)))
    z_piso = Hp + PISO
    yv = -W / 2 - 1.55  # beira da varanda
    E.piso_tabuas(rec, "piso", -L / 2 - 0.05, -W / 2, L / 2 + 0.05, W / 2, z_piso, mats, sem=1)
    E.piso_tabuas(rec, "varanda", -L / 2 - 0.05, yv, L / 2 + 0.05, -W / 2, z_piso, mats, sem=2)
    E.barrotes(rec, "barrote", -L / 2, yv, L / 2, W / 2, z_piso, mats)
    xs = (-L / 2, -L / 6, L / 6, L / 2)
    ys = (yv, -W / 2, 0.0, W / 2)
    E.pilotis(rec, "esteio", [(x, y) for x in xs for y in ys], z_piso - 0.14, mats)
    for y in (yv, -W / 2, 0.0, W / 2):
        rec.add(
            V.viga(
                f"madre{int(y * 10)}",
                (-L / 2 - 0.1, y, z_piso - 0.27),
                (L / 2 + 0.1, y, z_piso - 0.27),
                0.11,
                0.14,
                mats.go_escuro,
            ),
            "Casa",
            "Estrutura",
        )
    # varanda: postes e meia-água de chapa
    for x in (-L / 2, -L / 6, L / 6, L / 2):
        V.poste(rec, f"p_var{int(x * 10)}", x, yv + 0.05, Hp + 2.38, mats.go, r=0.06)
    E.telhado_varanda(
        rec,
        "tel_var",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        -W / 2 + 0.02,
        Hp + 2.72,
        yv - 0.4,
        Hp + 2.36,
        mats,
        21,
    )
    # guarda-corpo com a passagem para a escada do lado esquerdo
    E.guarda_corpo(rec, "gc_frente", (-L / 2 + 1.25, yv), (L / 2, yv), z_piso, mats)
    E.guarda_corpo(rec, "gc_dir", (L / 2, yv), (L / 2, -W / 2), z_piso, mats)
    E.guarda_corpo(rec, "gc_esq", (-L / 2, yv + 1.15), (-L / 2, -W / 2), z_piso, mats)
    # escada: sobe de frente para a varanda, à esquerda
    E.escada(
        rec,
        "escada",
        (-L / 2 + 0.6, yv - 3.3, 0.04),
        (-L / 2 + 0.6, yv + 0.02, z_piso),
        1.05,
        mats,
    )
    # depósito embaixo
    V.sacos(
        rec,
        "sacos_a",
        [(1.1, 1.2, 12), (1.6, 1.2, -8), (2.1, 1.25, 20), (1.35, 1.25, 80), (1.85, 1.3, 95)],
        mats,
        z=0.02,
    )
    V.sacos(rec, "sacos_b", [(1.3, 1.22, 5), (1.8, 1.25, -14)], mats, z=0.28)
    rec.caixa("sacos", (1.6, 1.25, 0.28), (1.6, 0.75, 0.56), "para", "Fabric")
    o = V.chum("jarra_a", (-2.5, 1.5), mats, alt=0.72, r=0.32, tampa="madeira", sem=31, z=0.0)
    rec.addv(o, "Mobilia", "Mobilia")
    rec.caixa("jarra_a", (-2.5, 1.5, 0.36), (0.64, 0.64, 0.72), "para", "Ceramic")
    o = V.chum("jarra_b", (-1.85, 1.75), mats, alt=0.6, r=0.27, tampa="madeira", sem=32, z=0.0)
    rec.addv(o, "Mobilia", "Mobilia")
    rec.caixa("jarra_b", (-1.85, 1.75, 0.3), (0.54, 0.54, 0.6), "para", "Ceramic")
    V.thung_chai(rec, "cesto", (3.15, 0.7), 90, mats, diam=1.5)
    V.ferramentas(rec, "ferr", (0.0, W / 2 - 0.12), 0, mats, itens=("enxada", "ancinho", "foice"))
    VC.camera(rec, (-2.4, -1.5, z_piso + 1.55), (2.2, 1.4, z_piso + 0.7))
    return rec


def receita_exp_palafita_b():
    """Casa menor de bambu e palha sobre esteios: parede de phên, varanda curta com patamar, escada
    lateral encostada no oitão, um cômodo mobiliado e, embaixo, cestos, lenha e um banco."""
    rec = V.Receita()
    mats = Mats(34)
    Hp = 2.5  # a madre mais baixa fica a 2,31 m do chão
    L, W, H, esp = 5.0, 4.0, 2.75, 0.07
    phen = V.mat_phen("phen_par", "#b19a69", "#7f6f4a", passo=0.045)
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
        [{"lado": "frente", "t": -0.75, "estilo": "liep", "folha": 1}],
        [
            {"lado": "frente", "t": 1.55, "w": 0.8, "estilo": "tre", "aba": True},
            {"lado": "fundo", "t": 0.0, "w": 0.7, "estilo": "tre"},
            {"lado": "esq", "t": 0.2, "w": 0.7, "estilo": "tre"},
            {"lado": "dir", "t": 0.9, "w": 0.6, "estilo": "tre"},
        ],
        col="Bamboo",
        bala="passa",
        sem=34,
        postes_tre=True,
        nen_rets=[],
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.45,
        0.5,
        "2aguas",
        "tranh",
        0.26,
        tranh,
        mats,
        beiral_oitao=0.35,
        sem=34,
        tesouras=(0.0,),
        mat_oitao=phen,
        oitao_esp=esp,
        col_oitao="Bamboo",
    )
    xi, yi = L / 2 - esp, W / 2 - esp
    V.phan(rec, "phan", (1.4, yi - 0.68), 0, mats)
    V.ban_tho(rec, "altar", (-1.2, yi - 0.24), 0, mats, comp=0.9, prof=0.42, alt=0.95, painel=False)
    V.ban_thap(rec, "mesa", (-1.85, -0.2), 90, mats)
    V.potes(rec, "lu", [(2.05, -1.55), (1.6, -1.65)], mats, alts=(0.6, 0.52), sem=341)
    V.ruong(rec, "arca", (xi - 0.3, -0.35), 90, mats)
    V.nonla_pendurado(rec, "nonla", (0.1, yi), 0, mats)
    V.rede_pendurada(rec, "rede", (-xi + 0.12, -1.25), 90, mats, comp=1.2, queda=1.2)
    rec.transformar(marca, V.lugar((0.0, 0.0, Hp)))
    z_piso = Hp + PISO
    yv = -W / 2 - 1.35  # beira da varanda
    xp = L / 2 + 1.3  # ponta do patamar da escada
    E.piso_tabuas(
        rec, "piso", -L / 2 - 0.05, -W / 2, L / 2 + 0.05, W / 2, z_piso, mats, largura=0.3, sem=1
    )
    E.piso_tabuas(rec, "varanda", -L / 2 - 0.05, yv, xp, -W / 2, z_piso, mats, largura=0.3, sem=2)
    E.barrotes(rec, "barrote", -L / 2, yv, L / 2, W / 2, z_piso, mats, passo=1.25)
    E.barrotes(rec, "barrote_p", L / 2 + 0.65, yv, xp - 0.04, -W / 2, z_piso, mats, passo=0.6)
    xs = (-L / 2, -L / 6, L / 6, L / 2)
    for k, (x, y) in enumerate((x, y) for x in xs for y in (-W / 2, 0.0, W / 2)):
        _esteio(rec, f"esteio{k}", x, y, z_piso - 0.14, mats)
    for k, y in enumerate((yv + 0.05, -W / 2)):
        _esteio(rec, f"esteio_p{k}", xp - 0.08, y, z_piso - 0.14, mats, r=0.09)
    # a fila da frente sobe do chão até a cobertura da varanda
    for k, x in enumerate((*xs, xp - 0.08)):
        _esteio(rec, f"poste_v{k}", x, yv + 0.05, Hp + 2.5, mats, r=0.085)
    for y, x1 in ((yv + 0.05, xp), (-W / 2, xp), (0.0, L / 2 + 0.1), (W / 2, L / 2 + 0.1)):
        rec.add(
            V.viga(
                f"madre{int(y * 10)}",
                (-L / 2 - 0.1, y, z_piso - 0.27),
                (x1, y, z_piso - 0.27),
                0.11,
                0.14,
                mats.go_escuro,
            ),
            "Casa",
            "Estrutura",
        )
    rec.add(
        V.viga(
            "frechal_v",
            (-L / 2 - 0.1, yv + 0.05, Hp + 2.5),
            (xp, yv + 0.05, Hp + 2.5),
            0.1,
            0.11,
            mats.go,
        ),
        "Casa",
        "Estrutura",
    )
    V.agua_unica(
        rec,
        "tel_var",
        -L / 2 - 0.25,
        xp + 0.12,
        -W / 2 + 0.02,
        Hp + 2.86,
        yv - 0.32,
        Hp + 2.56,
        0.2,
        "tranh",
        tranh,
        mats,
        sem=35,
    )
    for k, x in enumerate((-L / 2, -L / 6, L / 6, L / 2, xp - 0.08)):
        rec.add(
            V.tre(
                f"caibro_v{k}",
                (x, yv - 0.25, Hp + 2.37),
                (x, -W / 2, Hp + 2.62),
                0.03,
                mats.tre,
                segs=5,
            ),
            "Casa",
            "Estrutura",
        )
    E.guarda_corpo(rec, "gc_frente", (-L / 2, yv), (xp, yv), z_piso, mats, passo=0.9)
    E.guarda_corpo(rec, "gc_esq", (-L / 2, yv), (-L / 2, -W / 2), z_piso, mats, passo=0.7)
    E.guarda_corpo(rec, "gc_dir", (xp, yv), (xp, -W / 2), z_piso, mats, passo=0.7)
    # escada lateral: sobe ao longo do oitão, de trás para o patamar
    # o pé da rampa de colisão desce 0,1 m: com a base em 0,10 nada fica abaixo do chão e o modelo
    # não sobe na normalização; a soleira de pedra cobre esses 10 cm
    E.escada(
        rec,
        "escada",
        (L / 2 + 0.68, W / 2 - 0.82, 0.1),
        (L / 2 + 0.68, -W / 2 + 0.02, z_piso),
        1.05,
        mats,
    )
    soleira = V.bloco(
        "soleira", (1.25, 0.4, 0.1), (L / 2 + 0.68, W / 2 - 0.72, 0.05), mats.pedra, chanfro=0.015
    )
    V.sem_fundo(soleira, 0.0)
    rec.add(soleira, "Casa", "Estrutura")
    _col(
        rec,
        "soleira",
        L / 2 + 0.055,
        W / 2 - 0.92,
        0.0,
        L / 2 + 1.305,
        W / 2 - 0.52,
        0.1,
        "para",
        "Ground",
    )
    # embaixo da casa
    _lenha(rec, "lenha", -2.3, -1.05, 1.55, mats)
    _banco(rec, "banco", (-1.65, -1.72), 0, mats)  # encostado na fila de esteios: o vão fica livre
    _cesto(rec, "cesto_a", (1.45, 1.45), mats, r=0.32, alt=0.5)
    _cesto(rec, "cesto_b", (2.0, 1.2), mats, r=0.26, alt=0.42)
    _cesto(rec, "cesto_c", (1.75, 0.72), mats, r=0.22, alt=0.34)
    VC.camera(rec, (-1.55, -1.45, z_piso + 1.5), (1.35, 1.25, z_piso + 0.65))
    return rec


def _bancada(rec, nome, pos, rot, mats: Mats, comp=2.4, prof=0.7, alt=0.92):
    """Bancada de oficina: tampo grosso, pés, prateleira baixa, morsa de madeira e peças soltas."""
    z = PISO
    o = [
        V.bloco(
            f"{nome}_tampo", (comp, prof, 0.08), (0, 0, alt - 0.04), mats.go_escuro, chanfro=0.01
        )
    ]
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                V.bloco(
                    f"{nome}_pe{sx}{sy}",
                    (0.1, 0.1, alt - 0.08),
                    (sx * (comp / 2 - 0.1), sy * (prof / 2 - 0.08), (alt - 0.08) / 2),
                    mats.go,
                )
            )
    o.append(V.bloco(f"{nome}_baixa", (comp - 0.2, prof - 0.1, 0.035), (0, 0, 0.26), mats.go))
    o.append(
        V.bloco(
            f"{nome}_morsa",
            (0.3, 0.14, 0.16),
            (comp / 2 - 0.3, -prof / 2 + 0.05, alt + 0.06),
            mats.go,
        )
    )
    o.append(
        V.bloco(
            f"{nome}_tabua", (0.9, 0.2, 0.03), (-0.3, 0.05, alt + 0.015), mats.go, rot=(0, 0, 0.14)
        )
    )
    o.append(
        V.tre(
            f"{nome}_cabo",
            (0.15, -0.15, alt + 0.02),
            (0.5, -0.05, alt + 0.02),
            0.016,
            mats.tre,
            segs=5,
        )
    )
    o.append(V.bloco(f"{nome}_lamina", (0.16, 0.05, 0.012), (0.58, -0.03, alt + 0.012), mats.ferro))
    _colocar(rec, o, nome, pos, rot, z, (0, 0, alt / 2), (comp, prof, alt))


def receita_exp_casas_ligadas():
    """Residência de barro caiado com telha (altar e catre) e oficina de tábua com chapa (bancada e
    ferramentas), ligadas por uma passagem coberta aberta dos dois lados."""
    rec = V.Receita()
    mats = Mats(42)
    L1, W1, H1, e1 = 4.9, 5.2, 2.8, 0.16
    L2, W2, H2, e2 = 4.3, 4.4, 2.65, 0.08
    cx1, cx2 = -3.25, 3.55
    par = V.mat_vach_dat("vach_cal", cal="#d6cdb8", exposta=0.25)
    ngoi = V.mat_ngoi("ngoi", "#8e5238", "#663a28", "#a76a4c")
    van = V.mat_tabua("van")
    # residência
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "res",
        L1,
        W1,
        H1,
        e1,
        par,
        [
            {"lado": "frente", "t": -0.7, "estilo": "folhas"},
            {"lado": "dir", "t": 0.0, "estilo": "nada"},
        ],
        [
            {"lado": "frente", "t": 1.2, "w": 0.8, "estilo": "grade"},
            {"lado": "fundo", "t": -1.2, "w": 0.7, "estilo": "grade"},
            {"lado": "fundo", "t": 1.2, "w": 0.7, "estilo": "grade"},
            {"lado": "esq", "t": 0.0, "w": 0.8, "estilo": "grade"},
        ],
        col="Earth",
        chanfro=0.02,
        sem=42,
        nen_rets=[(-L1 / 2 - 0.15, -W1 / 2 - 0.2, L1 / 2 + 0.15, W1 / 2 + 0.2)],
    )
    V.telhado(
        rec,
        "res_tel",
        L1,
        W1,
        H1,
        4.6,
        0.42,
        "2aguas",
        "ngoi",
        0.1,
        ngoi,
        mats,
        beiral_oitao=0.26,
        sem=42,
        tesouras=(0.0,),
        mat_oitao=par,
        oitao_esp=e1,
    )
    yi, xi = W1 / 2 - e1, L1 / 2 - e1
    V.ban_tho(rec, "altar", (0.1, yi - 0.34), 0, mats)
    V.cho_tre(rec, "catre", (-1.25, 1.55), 0, mats)
    V.phan(rec, "phan", (1.25, -1.55), 0, mats, comp=1.8, larg=1.1, esteira=True)
    V.ban_thap(rec, "mesa", (-1.85, -0.7), 90, mats, banquinhos=2)  # fora do caminho da porta
    V.potes(rec, "lu", [(1.9, 1.95), (1.5, 2.05)], mats, alts=(0.62, 0.5), sem=421)
    V.ruong(rec, "arca", (-xi + 0.32, 0.25), 90, mats)
    V.nonla_pendurado(rec, "nonla", (-1.2, yi), 0, mats)
    rec.transformar(marca, V.lugar((cx1, 0.0, 0.0)))
    # oficina
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "of",
        L2,
        W2,
        H2,
        e2,
        van,
        [
            {"lado": "frente", "t": 0.75, "estilo": "tabua", "folha": 1},
            {"lado": "esq", "t": 0.0, "estilo": "nada"},
        ],
        [
            {"lado": "frente", "t": -1.05, "w": 0.9, "estilo": "tre", "aba": True},
            {"lado": "fundo", "t": 0.8, "w": 0.9, "estilo": "tre"},
            {"lado": "dir", "t": 0.3, "w": 0.7, "estilo": "tre"},
        ],
        col="Wood",
        sem=43,
        nen_rets=[(-L2 / 2 - 0.15, -W2 / 2 - 0.15, L2 / 2 + 0.15, W2 / 2 + 0.15)],
    )
    E.oitao_tabuas(rec, "of_oitao", L2, W2, H2, 4.05, van)
    E.telhado_chapa(
        rec, "of_tel", L2, W2, H2, 4.05, 0.42, mats, sem=43, ferrugem=0.85, beiral_oitao=0.26
    )
    yi, xi = W2 / 2 - e2, L2 / 2 - e2
    _bancada(rec, "bancada", (-0.35, yi - 0.38), 0, mats)
    V.ferramentas(
        rec, "ferr", (-1.6, yi - 0.02), 0, mats, itens=("enxada", "ancinho", "foice"), z=PISO + 0.45
    )
    _caixote(rec, "cx_a", (xi - 0.5, -1.45), 90, mats, z=PISO)
    _caixote(rec, "cx_b", (xi - 0.5, -1.42), 80, mats, dim=(0.6, 0.5, 0.42), z=PISO + 0.6)
    _lenha(rec, "ripas", xi - 1.05, xi - 0.1, 0.95, mats, z=PISO, filas=2)
    _pote(rec, "tambor", (-xi + 0.35, -1.6), mats, alt=0.72, r=0.3, z=PISO, tampa="madeira", sem=44)
    V.sacos(rec, "sacos", [(-xi + 0.42, 1.0, 10), (-xi + 0.4, 1.4, -14)], mats)
    rec.caixa("sacos", (-xi + 0.42, 1.2, PISO + 0.14), (0.6, 0.85, 0.28), "para", "Fabric")
    rec.transformar(marca, V.lugar((cx2, 0.0, 0.0)))
    # passagem coberta entre as duas portas laterais
    x0, x1 = cx1 + L1 / 2, cx2 - L2 / 2
    xm, comp = (x0 + x1) / 2, x1 - x0
    V.nen(rec, "pass_piso", x0 - 0.1, -1.4, x1 + 0.1, 1.4, mats)
    for sx in (x0 + 0.12, x1 - 0.12):
        for sy in (-1.2, 1.2):
            V.poste(rec, f"pass_p{int(sx * 10)}_{int(sy * 10)}", sx, sy, 2.7, mats.go, r=0.08)
    marca = rec.marca()
    E.telhado_chapa(
        rec, "pass_tel", comp, 2.4, 2.72, 3.32, 0.28, mats, sem=44, ferrugem=0.95, beiral_oitao=0.02
    )
    rec.transformar(marca, V.lugar((xm, 0.0, 0.0)))
    V.jarro_agua(rec, "jarro", (xm + 0.75, -1.85), mats, grupo="Mobilia", no="Mobilia")
    VC.camera(rec, (cx1 + 1.6, -1.6, PISO + 1.55), (cx1 - 0.7, 1.7, PISO + 0.8))
    return rec


def receita_exp_casa_vala():
    """Casa pequena de taipa ocre com palha: porta na frente e no fundo, depósito doméstico por
    dentro e varanda no fundo voltada para uma vala de drenagem (rasa e só visual: não cava)."""
    rec = V.Receita()
    mats = Mats(47)
    L, W, H, esp = 6.2, 4.0, 2.72, 0.16
    cy = -0.78  # o corpo fica para a frente, para sobrar lugar para a varanda e a vala
    par = V.mat_trinh("trinh")
    tranh = V.mat_tranh("tranh", ("#3b3325", "#655a43", "#857757", "#a08f6c"))
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        par,
        [
            {"lado": "frente", "t": -1.25, "estilo": "liep", "folha": 1},
            {"lado": "fundo", "t": 1.2, "estilo": "tabua", "folha": -1},
        ],
        [
            {"lado": "frente", "t": 1.5, "w": 0.7, "estilo": "tre"},
            {"lado": "fundo", "t": -1.4, "w": 0.7, "estilo": "tre"},
            {"lado": "dir", "t": 0.0, "w": 0.65, "estilo": "tre", "aba": True},
        ],
        chanfro=0.02,
        sem=47,
        nen_rets=[(-L / 2 - 0.15, -W / 2 - 0.2, L / 2 + 0.15, W / 2 + 1.42)],
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.55,
        0.42,
        "2aguas",
        "tranh",
        0.26,
        tranh,
        mats,
        beiral_oitao=0.3,
        sem=47,
        tesouras=(-1.0, 1.0),
        mat_oitao=par,
        oitao_esp=esp,
    )
    xi, yi = L / 2 - esp, W / 2 - esp
    # depósito: estante na parede esquerda, sacos, potes, tulha e arca, com o corredor livre
    _prateleira(rec, "estante", (-xi + 0.2, 0.1), 90, mats, comp=1.7, z=PISO)
    V.sacos(
        rec,
        "sacos_a",
        [
            (1.0, -1.45, 8),
            (1.5, -1.42, -12),
            (2.0, -1.45, 20),
            (1.25, -1.05, 85),
            (1.75, -1.05, 95),
        ],
        mats,
    )
    V.sacos(rec, "sacos_b", [(1.25, -1.42, 12), (1.75, -1.4, -6)], mats, z=PISO + 0.25)
    rec.caixa("sacos", (1.5, -1.25, PISO + 0.26), (1.6, 0.8, 0.52), "para", "Fabric")
    V.potes(rec, "lu", [(xi - 0.35, 0.3), (xi - 0.32, 0.85), (xi - 0.75, 0.55)], mats, sem=471)
    V.bo_lua(rec, "tulha", (-xi + 0.52, yi - 0.46), mats, r=0.42, alt=0.95)
    V.ruong(rec, "arca", (-0.6, yi - 0.32), 0, mats)
    _caixote(rec, "cx", (-xi + 0.5, -1.3), 90, mats, dim=(0.75, 0.55, 0.5), z=PISO)
    V.nonla_pendurado(rec, "nonla", (0.35, yi), 0, mats)
    # varanda do fundo, voltada para a vala
    yb = W / 2 + 1.32  # 1,25 m livres entre a parede e os postes
    V.agua_unica(
        rec,
        "tel_var",
        -L / 2 - 0.2,
        L / 2 + 0.2,
        W / 2 - 0.02,
        H + 0.12,
        yb + 0.28,
        2.46,
        0.2,
        "tranh",
        tranh,
        mats,
        sem=48,
    )
    xs = (-L / 2 + 0.1, -1.0, 0.45, 2.05, L / 2 - 0.1)  # nenhum poste na frente da porta (x = 1,2)
    for k, x in enumerate(xs):
        V.poste(rec, f"p_var{k}", x, yb, 2.5, mats.go, r=0.07)
    rec.add(
        V.viga("frechal_v", (-L / 2 - 0.05, yb, 2.5), (L / 2 + 0.05, yb, 2.5), 0.1, 0.11, mats.go),
        "Casa",
        "Estrutura",
    )
    for k, x in enumerate(xs):
        rec.add(
            V.tre(
                f"caibro_v{k}", (x, yb + 0.2, 2.42), (x, W / 2, H - 0.03), 0.028, mats.tre, segs=5
            ),
            "Casa",
            "Estrutura",
        )
    # os móveis da varanda ficam nas pontas: o corredor do meio tem 1,25 m
    _banco(rec, "banco_v", (-2.78, W / 2 + 0.72), 90, mats, comp=1.1, z=PISO)
    _cesto(rec, "cesto_v", (2.78, W / 2 + 0.3), mats, r=0.26, alt=0.42, z=PISO)
    V.jarro_agua(rec, "jarro", (2.72, W / 2 + 0.95), mats, grupo="Mobilia", no="Mobilia", z=PISO)
    rec.transformar(marca, V.lugar((0.0, cy, 0.0)))
    # vala: duas margens baixas e a lâmina d'água entre elas (acima do Z = 0, sem colisão)
    yv0, yv1 = cy + W / 2 + 1.64, cy + W / 2 + 2.08
    agua = V.mat_liso("agua_vala", "#2f3a2c", "#46523c", rug=0.18, escala=2.0, forca=0.5)
    pl = V.bloco("agua", (7.9, yv1 - yv0 + 0.12, 0.02), (0, (yv0 + yv1) / 2, 0.035), agua)
    rec.add(pl, "Mobilia", "Mobilia")
    for lado, (ya, yb2) in enumerate(((yv0 - 0.24, yv0 + 0.02), (yv1 - 0.02, yv1 + 0.2))):
        sinal = -1.0 if lado == 0 else 1.0

        def margem(u, v, ya=ya, yb2=yb2, sinal=sinal, lado=lado):
            x = -3.95 + 7.9 * u
            y = ya + (yb2 - ya) * v
            t = v if sinal < 0 else 1 - v  # 1 na beira da água
            h = 0.16 * math.sin(math.pi * min(1.0, t * 1.15)) + 0.02
            h += 0.03 * math.sin(x * 2.3 + lado * 1.7) * math.sin(math.pi * v)
            return (x, y, h)

        o = V.grade(f"margem{lado}", margem, 16, 4, fora=Vector((0, 0, 1)))
        V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
        M.material(o, mats.dat)
        rec.add(M.suave(o, 60), "Casa", "Anexos")
    for k, x in enumerate((-3.2, -1.7, 0.4, 2.1, 3.4)):
        rec.add(
            V.tre(
                f"estaca{k}",
                (x, yv0 - 0.02, 0.0),
                (x + 0.02, yv0 - 0.03, 0.3),
                0.035,
                mats.go_escuro,
                segs=5,
            ),
            "Casa",
            "Anexos",
        )
    VC.camera(rec, (1.7, cy - 1.45, PISO + 1.55), (-1.9, cy + 0.9, PISO + 0.75))
    return rec


def _roda(rec, nome, c, mats: Mats, R=0.54, n=10):
    """Roda raiada no plano XZ (eixo em Y)."""
    c = Vector(c)
    giro = Matrix.Translation(c) @ Matrix.Rotation(math.pi / 2, 4, "X")
    aro = M.toro(f"{nome}_aro", R, 0.042, 22, 4)
    V.gravar_uv_local(aro, lambda p: (p.x, p.y, p.z))
    M.material(aro, mats.go_escuro)
    M.mover(aro, giro)
    cubo = V.cilindro(f"{nome}_cubo", 0.09, 0.18, (0, 0, 0), mats.go_escuro, segs=8)
    M.mover(cubo, giro)
    o = [M.suave(aro, 45), cubo]
    for k in range(n):
        a = 2 * math.pi * k / n
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        o.append(
            V.viga(
                f"{nome}_raio{k}",
                c + d * 0.07,
                c + d * (R - 0.02),
                0.034,
                0.05,
                mats.go,
                cima=(0, 1, 0),
            )
        )
    rec.addv(o, "Mobilia", "Mobilia")


def _carroca(rec, nome, pos, rot, mats: Mats):
    """Carroça de duas rodas: caixa de tábuas, eixo, rodas raiadas e dois varais apoiados em
    calços. A caixa fica ao longo de X, e os varais saem para +X."""
    marca = rec.marca()
    comp, larg, zf = 2.2, 1.12, 0.66
    o = [V.bloco(f"{nome}_fundo", (comp, larg, 0.05), (0, 0, zf), mats.go_escuro, chanfro=0.005)]
    for sy in (-1, 1):
        for k in range(3):
            o.append(
                V.bloco(
                    f"{nome}_lat{sy}{k}",
                    (comp, 0.035, 0.125),
                    (0, sy * (larg / 2), zf + 0.09 + k * 0.135),
                    mats.go if k % 2 else mats.go_escuro,
                    chanfro=0.004,
                )
            )
        for x in (-comp / 2 + 0.05, 0.0, comp / 2 - 0.05):
            o.append(
                V.bloco(
                    f"{nome}_mont{sy}{int(x * 10)}",
                    (0.07, 0.05, 0.52),
                    (x, sy * (larg / 2 + 0.03), zf + 0.22),
                    mats.go_escuro,
                )
            )
    for sx in (-1, 1):
        for k in range(3):
            o.append(
                V.bloco(
                    f"{nome}_fim{sx}{k}",
                    (0.035, larg, 0.125),
                    (sx * (comp / 2), 0, zf + 0.09 + k * 0.135),
                    mats.go,
                    chanfro=0.004,
                )
            )
    o.append(
        V.tre(f"{nome}_eixo", (0.05, -0.86, 0.54), (0.05, 0.86, 0.54), 0.04, mats.go_escuro, segs=6)
    )
    for sy in (-1, 1):
        o.append(
            V.tre(
                f"{nome}_varal{sy}",
                (-comp / 2 + 0.2, sy * 0.36, zf - 0.06),
                (comp / 2 + 1.0, sy * 0.36, 0.24),
                0.042,
                mats.go,
                segs=6,
            )
        )
    o.append(
        V.bloco(f"{nome}_calco_a", (0.32, 1.0, 0.1), (comp / 2 + 0.9, 0, 0.05), mats.go_escuro)
    )
    o.append(V.bloco(f"{nome}_calco_b", (0.26, 0.86, 0.09), (comp / 2 + 0.9, 0, 0.145), mats.go))
    rec.addv(o, "Mobilia", "Mobilia")
    for sy in (-1, 1):
        _roda(rec, f"{nome}_roda{sy}", (0.05, sy * 0.76, 0.54), mats)
    _col(rec, nome, -comp / 2, -0.82, 0.0, comp / 2, 0.82, 1.1)
    rec.transformar(marca, V.lugar((pos[0], pos[1], 0.05), rot))


def receita_exp_carroca():
    """Telheiro aberto de madeira com telha sobre chão de terra: carroça de duas rodas, jarras
    grandes de barro e cestos. Sem paredes."""
    rec = V.Receita()
    mats = Mats(55)
    L, W, H = 5.6, 3.7, 2.72
    ngoi = V.mat_ngoi("ngoi", "#8e5238", "#663a28", "#a76a4c")
    V.nen(rec, "chao", -3.15, -2.3, 3.15, 2.3, mats, h=0.05)
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        3.85,
        0.62,
        "2aguas",
        "ngoi",
        0.1,
        ngoi,
        mats,
        beiral_oitao=0.5,
        sem=55,
        tesouras=(-1.4, 1.4),
    )
    for x in (-L / 2 + 0.1, 0.0, L / 2 - 0.1):
        for sy in (-1, 1):
            y = sy * (W / 2 - 0.12)
            V.poste(rec, f"p{int(x * 10)}{sy}", x, y, H - 0.1, mats.go_escuro, r=0.1)
            s = V.bloco(f"p{int(x * 10)}{sy}_ped", (0.34, 0.34, 0.1), (x, y, 0.05), mats.pedra)
            V.sem_fundo(s, 0.0)
            rec.add(s, "Casa", "Estrutura")
            for dx in (-1, 1):
                if abs(x + dx * 0.7) > L / 2:
                    continue
                rec.add(
                    V.viga(
                        f"mao{int(x * 10)}{sy}{dx}",
                        (x, y, H - 0.75),
                        (x + dx * 0.62, y, H - 0.13),
                        0.08,
                        0.08,
                        mats.go,
                    ),
                    "Casa",
                    "Estrutura",
                )
    _carroca(rec, "carroca", (-0.1, 0.62), 5, mats)  # para o fundo: 1,3 m livres na frente dela
    # jarras e cestos nas duas pontas: fica um corredor livre na frente da carroça
    _pote(rec, "jarra_a", (-2.3, -0.95), mats, alt=1.05, r=0.48, z=0.05, sem=56)
    _pote(rec, "jarra_b", (-2.4, -0.1), mats, alt=0.78, r=0.38, z=0.05, tampa="madeira", sem=57)
    _pote(rec, "jarra_c", (2.35, 1.05), mats, alt=0.9, r=0.42, z=0.05, sem=59)
    _cesto(rec, "cesto_a", (2.4, -1.05), mats, r=0.36, alt=0.55, z=0.05)
    _cesto(rec, "cesto_b", (2.45, -0.42), mats, r=0.28, alt=0.42, z=0.05)
    _cesto(rec, "cesto_c", (-2.4, 0.85), mats, r=0.3, alt=0.46, z=0.05)
    VC.camera(rec, (-2.6, -1.75, 1.55), (1.4, 0.7, 0.75))
    return rec


def receita_exp_abrigo():
    """Abrigo semienterrado: sala de 4,4 × 2,9 m com o piso 1,3 m abaixo do terreno, paredes de
    terra e tábua com esteios, teto de troncos sob um monte de terra, e uma boca com degraus em
    cada ponta (-X e +X). O terreno precisa ser escavado na sala e nas duas rampas."""
    rec = V.Receita()
    mats = Mats(61)
    Zc, Zv = -1.3, 1.04  # piso e fundo das vigas (2,34 m livres)
    Zl = Zc + 2.45  # fundo da verga das bocas
    XI, YI = 2.2, 1.45  # meia sala
    ML = 0.65  # meia largura livre das bocas
    XF, YC = 3.9, 1.0  # fim das rampas e face de terra do corte
    terra = _mat_terra()
    rec.add(
        V.bloco("piso", (2 * XI + 0.1, 2 * YI + 0.1, 0.1), (0, 0, Zc - 0.05), mats.nen),
        "Casa",
        "Piso",
    )
    _col(rec, "piso", -XI - 0.05, -YI - 0.05, Zc - 0.1, XI + 0.05, YI + 0.05, Zc, "para", "Ground")
    # paredes de terra da sala, com a colisão por trás da face
    for sy in (-1, 1):
        _pano_terra(
            rec,
            f"par_y{sy}",
            (-XI, sy * YI),
            (XI, sy * YI),
            Zc,
            Zv + 0.12,
            terra,
            (0, -sy, 0),
            8,
            4,
            sem=sy + 2,
        )
        y0, y1 = sorted((sy * YI, sy * (YI + 0.2)))
        _col(rec, f"par_y{sy}", -XI - 0.2, y0, Zc - 0.1, XI + 0.2, y1, Zv + 0.3, "para", "Ground")
    for sx in (-1, 1):
        for sy in (-1, 1):
            _pano_terra(
                rec,
                f"par_x{sx}{sy}",
                (sx * XI, sy * ML),
                (sx * XI, sy * YI),
                Zc,
                Zv + 0.12,
                terra,
                (-sx, 0, 0),
                2,
                4,
                sem=sx + sy + 5,
            )
            x0, x1 = sorted((sx * XI, sx * (XI + 0.2)))
            y0, y1 = sorted((sy * ML, sy * (YI + 0.2)))
            _col(rec, f"par_x{sx}{sy}", x0, y0, Zc - 0.1, x1, y1, Zv + 0.3, "para", "Ground")
        x0, x1 = sorted((sx * XI, sx * (XI + 0.2)))
        # a verga fica a 2,45 m do piso: quem desce a rampa ainda está mais alto ao passar por ela
        _col(rec, f"verga{sx}", x0, -ML, Zl, x1, ML, Zl + 0.28, "para", "Wood")
    # esteios, vigas e mãos-francesas
    xp = (-XI + 0.1, -0.75, 0.75, XI - 0.1)
    for sy in (-1, 1):
        y = sy * (YI - 0.09)
        for k, x in enumerate(xp):
            rec.add(
                V.bloco(
                    f"est{sy}{k}",
                    (0.18, 0.18, Zv - Zc + 0.02),
                    (x, y, (Zc + Zv + 0.02) / 2),
                    mats.go_escuro,
                    chanfro=0.012,
                ),
                "Casa",
                "Estrutura",
            )
            rec.caixa(f"est{sy}{k}", (x, y, (Zc + Zv) / 2), (0.18, 0.18, Zv - Zc), "para", "Wood")
            if abs(x) < 1.0:
                for dx in (-1, 1):
                    rec.add(
                        V.viga(
                            f"mao{sy}{k}{dx}",
                            (x, y, Zv - 0.5),
                            (x + dx * 0.45, y, Zv - 0.02),
                            0.09,
                            0.09,
                            mats.go,
                        ),
                        "Casa",
                        "Estrutura",
                    )
        rec.add(
            V.viga(
                f"long{sy}",
                (-XI - 0.05, y, Zv + 0.1),
                (XI + 0.05, y, Zv + 0.1),
                0.16,
                0.2,
                mats.go_escuro,
            ),
            "Casa",
            "Estrutura",
        )
        # tábuas na metade de baixo, entre os esteios
        for a, b in ((-XI + 0.19, -0.84), (-0.66, 0.66), (0.84, XI - 0.19)):
            for j in range(3):
                rec.add(
                    V.bloco(
                        f"tab{sy}{int(a * 10)}{j}",
                        (b - a, 0.035, 0.27),
                        ((a + b) / 2, sy * (YI - 0.03), Zc + 0.15 + j * 0.285),
                        mats.go if (j + int(a * 3)) % 2 else mats.go_escuro,
                        chanfro=0.005,
                    ),
                    "Casa",
                    "Paredes",
                )
    for k, x in enumerate(xp):
        rec.add(
            V.viga(f"trav{k}", (x, -YI, Zv + 0.1), (x, YI, Zv + 0.1), 0.16, 0.2, mats.go_escuro),
            "Casa",
            "Estrutura",
        )
    # teto de troncos
    n = 14
    for k in range(n):
        x = -XI - 0.05 + (k + 0.5) * (2 * XI + 0.1) / n
        r = 0.135 + 0.018 * math.sin(k * 2.7)
        rec.add(
            V.tre(
                f"teto{k}",
                (x, -YI - 0.12, Zv + 0.33),
                (x + 0.02, YI + 0.12, Zv + 0.33),
                r,
                mats.go_escuro if k % 3 else mats.go,
                segs=6,
                sem=k * 0.37,
            ),
            "Casa",
            "Estrutura",
        )
    _col(rec, "teto", -XI + 0.02, -YI - 0.2, Zv + 0.02, XI - 0.02, YI + 0.2, Zv + 0.36)
    # monte de terra: pirâmide truncada (os planos batem com a colisão) cortada nas duas rampas
    XO, YO, XT, YT, Tp = 3.9, 2.95, 2.55, 1.72, 1.62

    def h_base(x, y):
        return max(0.0, Tp * min(1.0, (XO - abs(x)) / (XO - XT), (YO - abs(y)) / (YO - YT)))

    def h_monte(x, y):
        b = h_base(x, y)
        return b + 0.05 * min(1.0, b / 0.4) * M.fbm(Vector((x, y, 0.0)) * 1.5, 3, 7)

    gx = [-3.9, -3.55, -3.15, -2.8, -2.4, -1.5, -0.5, 0.5, 1.5, 2.4, 2.8, 3.15, 3.55, 3.9]
    gy = [-2.95, -2.6, -2.25, -1.9, -1.45, -YC, -0.35, 0.35, YC, 1.45, 1.9, 2.25, 2.6, 2.95]

    def f_monte(u, v):
        x = gx[round(u * (len(gx) - 1))]
        y = gy[round(v * (len(gy) - 1))]
        return (x, y, h_monte(x, y))

    monte = V.grade("monte", f_monte, len(gx) - 1, len(gy) - 1, fora=Vector((0, 0, 1)))
    V.apagar_faces(monte, lambda c, _n: abs(c.x) > 2.4 and abs(c.y) < YC)
    V.gravar_uv_local(monte, lambda p: (p.x, p.y, p.z))
    M.material(monte, terra)
    rec.add(M.suave(monte, 60), "Telhado", "Telhado")
    # colisão do monte: tampa + duas encostas longas + quatro encostas das pontas (nenhuma entra
    # na sala nem nas rampas)
    _col(rec, "monte_topo", -2.4, -YT, Zv + 0.36, 2.4, YT, Tp, "para", "Ground")
    for sy in (-1, 1):
        rec.prisma(
            f"monte_y{sy}",
            [
                (-XO, sy * (YI + 0.2), 0.0),
                (XO, sy * (YI + 0.2), 0.0),
                (-XO, sy * YO, 0.0),
                (XO, sy * YO, 0.0),
                (-XT, sy * (YI + 0.2), Tp),
                (XT, sy * (YI + 0.2), Tp),
                (-XT, sy * YT, Tp),
                (XT, sy * YT, Tp),
            ],
            "para",
            "Ground",
        )
        for sx in (-1, 1):
            rec.prisma(
                f"monte_x{sx}{sy}",
                [
                    (sx * 2.4, sy * YC, 0.0),
                    (sx * 2.4, sy * (YI + 0.2), 0.0),
                    (sx * XO, sy * YC, 0.0),
                    (sx * XO, sy * (YI + 0.2), 0.0),
                    (sx * 2.4, sy * YC, Tp),
                    (sx * 2.4, sy * (YI + 0.2), Tp),
                    (sx * XT, sy * YC, Tp),
                    (sx * XT, sy * (YI + 0.2), Tp),
                ],
                "para",
                "Ground",
            )
    # bocas: pórtico de troncos, degraus com rampa de colisão e o corte revestido
    for sx in (-1, 1):
        xb = sx * (XI + 0.02)
        for sy in (-1, 1):
            y = sy * (ML + 0.14)
            rec.add(
                V.tre(
                    f"port{sx}{sy}", (xb, y, Zc), (xb, y, Zl + 0.28), 0.14, mats.go_escuro, segs=8
                ),
                "Casa",
                "Estrutura",
            )
            rec.caixa(
                f"port{sx}{sy}",
                (xb, y, (Zc + Zl + 0.28) / 2),
                (0.28, 0.28, Zl + 0.28 - Zc),
                "para",
                "Wood",
            )
            # face de terra e toras do corte
            xa, xc = sx * XI, sx * XF
            _pano_terra(
                rec,
                f"corte{sx}{sy}",
                (xa, sy * YC),
                (xc, sy * YC),
                Zc,
                lambda p: h_monte(p.x, p.y) + 0.02,
                terra,
                (0, -sy, 0),
                5,
                4,
                sem=sx + 2 * sy + 9,
            )
            for j in range(8):
                z = Zc + 0.09 + j * 0.172
                rec.add(
                    V.tre(
                        f"tora{sx}{sy}{j}",
                        (xa + sx * 0.14, sy * 0.885, z),
                        (xc, sy * 0.885, z),
                        0.085 + 0.008 * math.sin(j * 2.1 + sx),
                        mats.go if j % 3 else mats.go_escuro,
                        segs=6,
                        sem=j * 0.4,
                    ),
                    "Casa",
                    "Estrutura",
                )
            for j, t in enumerate((0.3, 0.68, 0.98)):
                x = xa + (xc - xa) * t
                topo = Zc + 1.3 * t + 1.25
                rec.add(
                    V.tre(
                        f"estaca{sx}{sy}{j}",
                        (x, sy * 0.73, Zc + 1.3 * t - 0.12),
                        (x, sy * 0.73, min(topo, 0.42)),
                        0.075,
                        mats.go_escuro,
                        segs=6,
                    ),
                    "Casa",
                    "Estrutura",
                )
            x0, x1 = sorted((xa + sx * 0.14, xc))
            y0, y1 = sorted((sy * ML, sy * YC))
            _col(rec, f"corte{sx}{sy}", x0, y0, Zc - 0.1, x1, y1, 0.42, "para", "Ground")
        rec.add(
            V.tre(
                f"verga_log{sx}",
                (xb, -1.08, Zl + 0.14),
                (xb, 1.08, Zl + 0.14),
                0.14,
                mats.go_escuro,
                segs=8,
            ),
            "Casa",
            "Estrutura",
        )
        E.escada(
            rec,
            f"degraus{sx}",
            (sx * (XI - 0.02), 0.0, Zc),
            (sx * XF, 0.0, 0.0),
            1.24,
            mats,
            corrimao=False,
        )

        def rampa(u, v, sx=sx):
            x = sx * (XI - 0.02 + (XF - XI + 0.02) * u)
            return (x, -ML - 0.03 + (2 * ML + 0.06) * v, Zc - 0.05 + 1.3 * u)

        o = V.grade(f"rampa_terra{sx}", rampa, 3, 1, fora=Vector((0, 0, 1)))
        V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
        M.material(o, terra)
        rec.add(M.suave(o, 40), "Telhado", "Telhado")
        _abertura(rec, f"boca{sx}", (sx * XI, 0.0, Zc), (float(sx), 0.0, 0.0), 2 * ML, Zl - Zc)
    # móveis (feitos no nível do chão da sala)
    _caixote(rec, "cx_a", (1.35, 1.0), 180, mats, dim=(0.9, 0.62, 0.66), z=Zc)
    _caixote(rec, "cx_b", (1.42, 1.02), 172, mats, dim=(0.66, 0.5, 0.48), z=Zc + 0.66)
    _caixote(rec, "cx_c", (0.42, 1.08), 180, mats, dim=(0.6, 0.46, 0.44), z=Zc)
    _banco(rec, "banco", (-1.15, 1.13), 0, mats, comp=1.5, larg=0.38, z=Zc)
    enrolada = V.cilindro("esteira_rolo", 0.08, 0.7, (0, 0, 0), mats.esteira, segs=8)
    M.mover(
        enrolada,
        Matrix.Translation((-1.45, 1.13, Zc + 0.52)) @ Matrix.Rotation(math.pi / 2, 4, "Y"),
    )
    rec.add(enrolada, "Mobilia", "Mobilia")
    _prateleira(rec, "estante", (1.2, -1.2), 0, mats, comp=1.5, prof=0.34, alt=1.72, z=Zc)
    rec.add(
        V.bloco("esteira", (1.5, 1.05, 0.014), (-0.95, -0.72, Zc + 0.007), mats.esteira),
        "Mobilia",
        "Mobilia",
    )
    m = rec.marca()
    V.sacos(rec, "sacos", [(-1.85, -1.1, 12), (-1.4, -1.15, -8), (-1.62, -0.85, 80)], mats)
    V.sacos(rec, "sacos2", [(-1.62, -1.1, 6)], mats, z=PISO + 0.24)
    rec.transformar(m, V.lugar((0.0, 0.0, Zc - PISO)))
    rec.caixa("sacos", (-1.62, -1.02, Zc + 0.25), (0.95, 0.68, 0.5), "para", "Fabric")
    _cesto(rec, "cesto", (-0.15, 1.15), mats, r=0.22, alt=0.36, z=Zc)
    _lanterna(rec, "lanterna", (-0.2, YI - 0.04, Zc + 1.72), mats, sy=-1.0)
    VC.camera(rec, (-1.75, -0.45, Zc + 1.6), (1.55, 0.75, Zc + 0.75))
    return rec


def receita_exp_trincheira():
    """Trecho reto de 6 m de trincheira (ao longo de Y), 1,2 m livres, chão em Z = -1,4: troncos
    deitados, estacas e parapeito baixo de terra. As pontas são abertas e iguais (o relevo do
    parapeito é periódico em 6 m), então a peça se repete em linha. Colisão só nas duas paredes;
    o chão de quem anda é o terreno escavado."""
    rec = V.Receita()
    mats = Mats(71)
    Z, Y = -1.4, 3.0
    terra = _mat_terra("terra", coord="local")
    raio = 2 * Y / (2 * math.pi)

    def periodico(o):
        """`local` num círculo de 6 m de perímetro em Y: a textura é igual nas duas pontas."""
        V.gravar_uv_local(
            o,
            lambda p: (
                p.x + 1.3 * p.z,
                raio * math.cos(p.y / raio),
                raio * math.sin(p.y / raio),
            ),
        )
        M.material(o, terra)

    def chao(u, v):
        # 2 cm acima de Z: não briga (z-fighting) com o terreno escavado até -1,4
        return (-0.98 + 1.96 * u, -Y + 2 * Y * v, Z + 0.02)

    o = V.grade("chao", chao, 2, 6, fora=Vector((0, 0, 1)))
    periodico(o)
    rec.add(o, "Telhado", "Telhado")
    for sx in (-1, 1):
        # terra atrás dos troncos
        def fundo(u, v, sx=sx):
            return (sx * 0.97, -Y + 2 * Y * u, Z + 1.42 * v)

        o = V.grade(f"terra{sx}", fundo, 3, 1, fora=Vector((-sx, 0, 0)))
        periodico(o)
        rec.add(o, "Telhado", "Telhado")
        # toras deitadas: mesma altura e raio nas duas pontas, para emendar
        for j in range(8):
            z = Z + 0.086 + j * 0.163
            r = 0.082 + 0.006 * math.sin(j * 2.3 + sx)
            rec.add(
                V.tre(
                    f"tora{sx}_{j}",
                    (sx * 0.86, -Y, z),
                    (sx * 0.86, Y, z),
                    r,
                    mats.go_escuro if (j + (sx > 0)) % 3 == 0 else mats.go,
                    segs=6,
                    sem=j * 0.41 + sx,
                ),
                "Casa",
                "Paredes",
            )
        # estacas por dentro das toras, a cada 1,2 m (o passo continua na emenda)
        for k, y in enumerate((-2.4, -1.2, 0.0, 1.2, 2.4)):
            topo = 0.16 + 0.05 * math.sin(k * 2.4 + sx)
            rec.add(
                V.tre(
                    f"estaca{sx}_{k}",
                    (sx * 0.675, y, Z),
                    (sx * 0.675, y, topo),
                    0.075,
                    mats.go_escuro,
                    segs=6,
                    r1=0.062,
                    sem=k * 0.53,
                ),
                "Casa",
                "Estrutura",
            )

        # parapeito: Z = 0 na borda de fora, para emendar com o terreno
        def lombo(u, v, sx=sx):
            x = 0.76 + 0.44 * u  # começa atrás das estacas: não fica pendurado sobre a vala
            y = -Y + 2 * Y * v
            sino = max(0.0, math.sin(math.pi * min(1.0, 0.18 + u * 0.82))) ** 0.8
            onda = 0.03 * math.sin(2 * math.pi * y / 6 + sx) + 0.018 * math.sin(
                2 * math.pi * y / 2 + 2.1 * sx
            )
            z = (0.2 + onda) * sino
            if u < 1e-6:
                z = -0.12  # desce até as toras: sem fresta entre o parapeito e a parede
            elif u > 1 - 1e-6:
                z = 0.0
            return (sx * x, y, z)

        o = V.grade(f"parapeito{sx}", lombo, 5, 12, fora=Vector((0, 0, 1)))
        periodico(o)
        rec.add(M.suave(o, 60), "Telhado", "Telhado")
        x0, x1 = sorted((sx * 0.6, sx * 0.98))
        _col(rec, f"parede{sx}", x0, -Y, Z, x1, Y, 0.2, "para", "Ground")
    VC.camera(rec, (0.15, -2.7, Z + 1.55), (-0.1, 2.6, Z + 0.55))
    return rec


def receita_exp_prancha():
    """Travessia curta sobre vala: três tábuas grossas (3,4 × 1,2 m, topo em 0,18 m) sobre dois
    troncos, com as pontas dobradas até o chão e uma colisão plana com rampinha nas pontas."""
    rec = V.Receita()
    mats = Mats(77)
    Y, Yt, zt = 1.7, 1.28, 0.18
    for k, y in enumerate((-Yt, Yt)):
        rec.add(
            V.tre(
                f"tronco{k}",
                (-0.6, y, 0.068),
                (0.6, y + 0.02, 0.068),
                0.068,
                mats.go_escuro,
                segs=7,
                sem=k * 0.7,
            ),
            "Casa",
            "Estrutura",
        )
    for k, x in enumerate((-0.4, 0.0, 0.4)):
        recuo = 0.03 * abs(math.sin(k * 2.2))  # as pontas não ficam alinhadas, sem passar de 3,4 m
        pts = [
            (-Y + recuo, 0.05),
            (-Yt - 0.06, zt - 0.012),
            (-0.5, zt),
            (0.5, zt + 0.004 * (k - 1)),
            (Yt + 0.06, zt - 0.012),
            (Y - recuo, 0.05),
        ]
        t = _tabua_perfil(f"tabua{k}", x, 0.385, pts, 0.05, mats.go if k != 1 else mats.go_escuro)
        rec.add(t, "Casa", "Piso")
    for k, y in enumerate((-Yt, Yt)):
        for x in (-0.4, 0.0, 0.4):
            rec.add(
                V.bloco(
                    f"grampo{k}{int(x * 10)}", (0.03, 0.03, 0.012), (x, y, zt + 0.003), mats.ferro
                ),
                "Casa",
                "Estrutura",
            )
    rec.prisma(
        "prancha",
        [
            (sx * 0.6, sy * q, z)
            for sx in (-1, 1)
            for sy in (-1, 1)
            for q, z in ((Y, 0.0), (Y, 0.03), (Yt, zt))  # sem ponto colinear: o fecho convexo falha
        ],
        "para",
        "Wood",
    )
    VC.camera(rec, (-1.6, -2.3, 1.2), (0.0, 0.2, 0.1))
    return rec


CASAS: dict[str, dict] = {
    "exp_palafita_a": {
        "nome": "casa de madeira sobre esteios",
        "tipo": "tábua, chapa remendada, varanda, escada, 2 cômodos e depósito embaixo",
        "fontes": ["navy67", "sggp_qngai"],
        "atlas": ATLAS_512,
    },
    "exp_palafita_b": {
        "nome": "casa de bambu e palha sobre esteios",
        "tipo": "phên, palha, varanda curta, escada lateral, 1 cômodo e lenha embaixo",
        "fontes": ["navy67", "sggp_qngai"],
        "atlas": ATLAS_512,
    },
    "exp_casas_ligadas": {
        "nome": "residência e oficina ligadas",
        "tipo": "barro caiado com telha + tábua com chapa, passagem coberta entre as duas",
        "fontes": ["navy67", "sggp_qngai"],
        "atlas": ATLAS_512,
    },
    "exp_casa_vala": {
        "nome": "casa de taipa junto à vala",
        "tipo": "taipa ocre, palha, porta na frente e no fundo, depósito, varanda sobre a vala",
        "fontes": ["navy67"],
        "atlas": ATLAS_512,
    },
    "exp_carroca": {
        "nome": "telheiro da carroça",
        "tipo": "telheiro aberto de telha, carroça de duas rodas, jarras e cestos",
        "fontes": ["navy67"],
        "atlas": ATLAS_PEQUENO,
    },
    "exp_abrigo": {
        "nome": "abrigo semienterrado",
        "tipo": "sala a 1,3 m abaixo do terreno, teto de troncos, monte de terra, duas bocas",
        "fontes": ["navy67"],
        "atlas": ATLAS_ABRIGO,
    },
    "exp_trincheira": {
        "nome": "trecho de trincheira",
        "tipo": "6 m retos, troncos e estacas, 1,4 m de fundo, pontas encaixáveis",
        "fontes": ["navy67"],
        "atlas": ATLAS_ABRIGO,
    },
    "exp_prancha": {
        "nome": "prancha sobre a vala",
        "tipo": "três tábuas sobre dois troncos, 3,4 × 1,2 m",
        "fontes": ["navy67"],
        "atlas": ATLAS_PEQUENO,
    },
}
