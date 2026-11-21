"""Peças das construções da expansão (D-232): palafita, escada, guarda-corpo, piso de tábuas e
telhado de chapa remendado. Metros, Z para cima, frente em -Y (como `vila_comum`).

Regras de colisão usadas aqui:
- escada: os degraus são só visuais; a colisão é UMA rampa (o personagem sobe sem tropeçar);
- guarda-corpo: uma caixa fina até 1,0 m, com os vãos de passagem abertos;
- piso elevado: uma caixa por piso, com o vão da escada aberto quando pedido.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bases_comum as B  # noqa: E402
import modelar as M  # noqa: E402
import vila_comum as V  # noqa: E402
from modelar import Mat, rgb  # noqa: E402
from vila_comum import Mats  # noqa: E402


def mat_chapa(nome, ferrugem=0.7):
    """Chapa velha: zinco cinza com manchas grandes de ferrugem vermelha (0 = quase nova)."""
    m = Mat(nome, rug=0.72)
    p = m.coord("objeto")
    base = m.misturar(m.faixa(m.ruido(p, 0.8, 4), 0.35, 0.65), rgb("#6f7271"), rgb("#8a8b85"))
    verm = m.misturar(m.faixa(m.ruido(p, 9.0, 4), 0.35, 0.7), rgb("#6e3620"), rgb("#a4552c"))
    mancha = m.faixa(m.ruido(p, 1.6, 5, 0.6), 0.62 - 0.3 * ferrugem, 0.7 - 0.24 * ferrugem)
    m.cor(m.misturar(mancha, base, verm))
    m.relevo(m.ruido(p, 40.0, 3), 0.1, 0.0008)
    return m.m


def piso_tabuas(rec, nome, x0, y0, x1, y1, z_topo, mats: Mats, esp=0.06, largura=0.24, sem=0):
    """Piso de tábuas ao longo de X, com o topo em `z_topo` e uma caixa de colisão."""
    n = max(1, round((y1 - y0) / largura))
    passo = (y1 - y0) / n
    for k in range(n):
        y = y0 + (k + 0.5) * passo
        desl = 0.012 * math.sin(k * 2.3 + sem)
        t = V.bloco(
            f"{nome}_t{k}",
            (x1 - x0 + desl, passo - 0.008, esp),
            ((x0 + x1) / 2 + desl / 2, y, z_topo - esp / 2),
            mats.go if (k + sem) % 3 else mats.go_escuro,
            chanfro=0.006,
        )
        rec.add(t, "Casa", "Piso")
    rec.caixa(
        nome,
        ((x0 + x1) / 2, (y0 + y1) / 2, z_topo - esp / 2),
        (x1 - x0, y1 - y0, esp),
        "para",
        "Wood",
    )


def barrotes(rec, nome, x0, y0, x1, y1, z_topo, mats: Mats, passo=0.9):
    """Vigas sob o piso (ao longo de Y), visíveis de baixo."""
    n = max(2, round((x1 - x0) / passo) + 1)
    for k in range(n):
        x = x0 + (x1 - x0) * k / (n - 1)
        rec.add(
            V.viga(
                f"{nome}_{k}", (x, y0, z_topo - 0.13), (x, y1, z_topo - 0.13), 0.09, 0.14, mats.go
            ),
            "Casa",
            "Estrutura",
        )


def pilotis(rec, nome, pontos, z1, mats: Mats, r=0.11):
    """Esteios roliços com sapata de pedra, do chão até `z1`."""
    for k, (x, y) in enumerate(pontos):
        V.poste(
            rec, f"{nome}{k}", x, y, z1, mats.go_escuro, r=r, quadrado=False, base_pedra=mats.pedra
        )


def escada(rec, nome, base, topo, larg, mats: Mats, corrimao=True):
    """Escada reta de `base` (x, y, z) a `topo` (x, y, z): banzos, degraus de ~0,2 m, corrimão e
    uma rampa de colisão."""
    a, b = Vector(base), Vector(topo)
    d = b - a
    plano = Vector((d.x, d.y, 0.0))
    u = plano.normalized()
    s = Vector((-u.y, u.x, 0.0))
    n = max(3, round(d.z / 0.2))
    for lado in (-1, 1):
        off = s * (lado * larg / 2)
        rec.add(
            V.viga(f"{nome}_banzo{lado}", a + off, b + off, 0.06, 0.2, mats.go_escuro),
            "Casa",
            "Estrutura",
        )
        if corrimao:
            alto = Vector((0, 0, 0.95))
            rec.add(
                V.tre(f"{nome}_corr{lado}", a + off + alto, b + off + alto, 0.03, mats.tre),
                "Casa",
                "Estrutura",
            )
            for t in (0.0, 0.5, 1.0):
                p = a + d * t + off
                rec.add(
                    V.tre(f"{nome}_mont{lado}_{int(t * 2)}", p, p + alto, 0.025, mats.tre),
                    "Casa",
                    "Estrutura",
                )
    ang = math.atan2(u.y, u.x)
    for k in range(1, n):
        c = a + d * (k / n)
        rec.add(
            V.bloco(
                f"{nome}_deg{k}",
                (0.3, larg, 0.04),
                (c.x, c.y, c.z),
                mats.go,
                chanfro=0.006,
                rot=(0, 0, ang),
            ),
            "Casa",
            "Estrutura",
        )
    meio = s * (larg / 2)
    baixo = Vector((0, 0, -0.1))
    rec.prisma(
        f"{nome}_rampa",
        [
            tuple(a - meio),
            tuple(a + meio),
            tuple(b - meio),
            tuple(b + meio),
            tuple(a - meio + baixo),
            tuple(a + meio + baixo),
            tuple(b - meio + baixo),
            tuple(b + meio + baixo),
        ],
        "para",
        "Wood",
    )


def guarda_corpo(rec, nome, p0, p1, z, mats: Mats, alt=0.92, passo=0.6):
    """Guarda-corpo de p0 a p1 (x, y) no nível z: travessas de madeira, montantes de bambu e uma
    caixa fina de colisão."""
    a = Vector((p0[0], p0[1], z))
    b = Vector((p1[0], p1[1], z))
    d = b - a
    comp = d.length
    n = max(1, round(comp / passo))
    for k in range(n + 1):
        p = a + d * (k / n)
        rec.add(
            V.viga(
                f"{nome}_m{k}",
                p,
                p + Vector((0, 0, alt)),
                0.05,
                0.05,
                mats.go_escuro,
                chanfro=0.006,
            ),
            "Casa",
            "Estrutura",
        )
    for h, r in ((alt, 0.035), (alt * 0.55, 0.022)):
        q = Vector((0, 0, h))
        rec.add(V.tre(f"{nome}_tr{int(h * 100)}", a + q, b + q, r, mats.tre), "Casa", "Estrutura")
    c = (a + b) / 2
    rec.caixa(
        nome,
        (c.x, c.y, z + 0.5),
        (comp, 0.08, 1.0),
        "passa",
        "Bamboo",
        rot_z=math.atan2(d.y, d.x),
    )


def placa_lisa(nome, a, b, c, d, mat, baixar=0.022, esp=0.02):
    """Placa fina e lisa sob a chapa ondulada: é a malha que vai para o jogo. As ondas (`so_bake`)
    só passam para o mapa normal, e a placa tem as duas faces (o telhado visto de dentro)."""
    pa, pb, pc, pd = Vector(a), Vector(b), Vector(c), Vector(d)
    n = (pb - pa).cross(pd - pa).normalized()
    if n.z < 0:
        n = -n
    desce = n * -baixar

    def f(u, v):
        p = pa.lerp(pb, u).lerp(pd.lerp(pc, u), v)
        return tuple(p + desce)

    ob = V.grade(nome, f, 1, 1, fora=n)
    M.solidificar(ob, esp, 0.0)
    M.material(ob, mat)
    return ob


def mat_forro(nome):
    """A chapa vista de dentro: zinco velho e escuro, sem a ferrugem viva da face de cima."""
    m = Mat(nome, rug=0.86)
    p = m.coord("objeto")
    m.cor(m.misturar(m.faixa(m.ruido(p, 1.3, 4), 0.35, 0.7), rgb("#3a3833"), rgb("#55514a")))
    m.relevo(m.ruido(p, 34.0, 3), 0.1, 0.0005)
    return m.m


def forro(nome, a, b, c, d, mat, baixar=0.05):
    """Face de baixo do telhado de chapa: placa virada para dentro, logo abaixo da placa lisa."""
    pa, pb, pc, pd = Vector(a), Vector(b), Vector(c), Vector(d)
    n = (pb - pa).cross(pd - pa).normalized()
    if n.z < 0:
        n = -n
    desce = n * -baixar

    def f(u, v):
        p = pa.lerp(pb, u).lerp(pd.lerp(pc, u), v)
        return tuple(p + desce)

    ob = V.grade(nome, f, 1, 1, fora=-n)
    M.material(ob, mat)
    return ob


def telhado_chapa(
    rec,
    nome,
    L,
    W,
    h,
    hr,
    beiral,
    mats: Mats,
    sem=0,
    ferrugem=0.6,
    beiral_oitao=0.35,
    m_lugar: Matrix | None = None,
):
    """Telhado de 2 águas de chapa ondulada, remendado: cada água são 3 a 5 chapas com tons de
    ferrugem diferentes e pequenos desvios. Cumeeira ao longo de X, centrado na origem; `h` é o
    topo da parede e `hr` a cumeeira."""
    marca = rec.marca()
    m1 = mat_chapa(f"chapa_{nome}_a", ferrugem)
    m2 = mat_chapa(f"chapa_{nome}_b", max(0.0, ferrugem - 0.6))  # o remendo mais novo
    m_forro = mat_forro(f"forro_{nome}")
    X = L / 2 + beiral_oitao
    Y = W / 2 + beiral
    s = (hr - (h + 0.05)) / (W / 2)
    ze = hr - s * Y
    largura = 1.1
    for lado in (-1, 1):
        n = max(2, round(2 * X / largura))
        passo = 2 * X / n
        for k in range(n):
            x0 = -X + k * passo - 0.03
            torto = 0.012 * math.sin(k * 1.9 + sem + lado)
            o = (x0, lado * Y, ze + 0.005 * (k % 2) + torto)
            fim = Vector((x0, 0.02 * lado, hr + 0.005 * (k % 2) + torto))
            v = (fim - Vector(o)).normalized()
            comp = (fim - Vector(o)).length
            mat = m2 if (k * 3 + sem + (lado > 0)) % 4 == 0 else m1
            ob = B.chapa_ondulada(
                f"{nome}_ch{lado}_{k}",
                o,
                (1, 0, 0),
                tuple(v),
                passo + 0.06,
                comp,
                passo=0.11,
                prof=0.022,
                esp=0.004,
                mat=mat,
                sem=sem + k,
            )
            ob["so_bake"] = True  # a onda vai para o mapa normal da placa lisa
            rec.add(ob, "Telhado", "Telhado")
        rec.add(
            placa_lisa(
                f"{nome}_placa{lado}",
                (-X, lado * Y, ze),
                (X, lado * Y, ze),
                (X, 0.0, hr),
                (-X, 0.0, hr),
                m1,
            ),
            "Telhado",
            "Telhado",
        )
        rec.add(
            forro(
                f"{nome}_forro{lado}",
                (-X, lado * Y, ze),
                (X, lado * Y, ze),
                (X, 0.0, hr),
                (-X, 0.0, hr),
                m_forro,
            ),
            "Telhado",
            "Telhado",
        )
        rec.prisma(
            f"{nome}_agua{lado}",
            [
                (-X, lado * Y, ze + 0.02),
                (X, lado * Y, ze + 0.02),
                (-X, 0, hr + 0.02),
                (X, 0, hr + 0.02),
                (-X, lado * Y, ze + 0.08),
                (X, lado * Y, ze + 0.08),
                (-X, 0, hr + 0.08),
                (X, 0, hr + 0.08),
            ],
            "para",
            "Metal",
        )
        # terças e caibros aparentes por dentro
        for t in (0.15, 0.5, 0.85):
            yy = lado * Y * (1 - t)
            zz = ze + (hr - ze) * t - 0.06
            rec.add(
                V.viga(
                    f"{nome}_terca{lado}_{int(t * 100)}",
                    (-X, yy, zz),
                    (X, yy, zz),
                    0.07,
                    0.08,
                    mats.go,
                ),
                "Casa",
                "Estrutura",
            )
    rec.add(
        V.viga(
            f"{nome}_cumeeira", (-X, 0, hr - 0.07), (X, 0, hr - 0.07), 0.1, 0.12, mats.go_escuro
        ),
        "Casa",
        "Estrutura",
    )
    capa = V.bloco(f"{nome}_capa", (2 * X + 0.04, 0.26, 0.018), (0, 0, hr + 0.03), m1, local=False)
    rec.add(capa, "Telhado", "Telhado")
    for sx in (-1, 1):
        x = sx * (L / 2 - 0.1)
        for lado in (-1, 1):
            rec.add(
                V.viga(
                    f"{nome}_tes{sx}_{lado}",
                    (x, lado * (W / 2), h),
                    (x, 0, hr - 0.08),
                    0.08,
                    0.11,
                    mats.go,
                ),
                "Casa",
                "Estrutura",
            )
    if m_lugar is not None:
        rec.transformar(marca, m_lugar)


def telhado_varanda(rec, nome, x0, x1, y_alto, z_alto, y_baixo, z_baixo, mats: Mats, sem=0):
    """Meia-água de chapa encostada na parede (de y_alto/z_alto ao beiral y_baixo/z_baixo)."""
    m1 = mat_chapa(f"chapa_{nome}_a", 0.75)
    m2 = mat_chapa(f"chapa_{nome}_b", 0.15)
    n = max(2, round((x1 - x0) / 1.1))
    passo = (x1 - x0) / n
    o0 = Vector((0.0, y_baixo, z_baixo))
    fim = Vector((0.0, y_alto, z_alto))
    v = (fim - o0).normalized()
    comp = (fim - o0).length
    for k in range(n):
        o = (x0 + k * passo - 0.03, y_baixo, z_baixo + 0.004 * (k % 2))
        ob = B.chapa_ondulada(
            f"{nome}_ch{k}",
            o,
            (1, 0, 0),
            tuple(v),
            passo + 0.06,
            comp,
            passo=0.11,
            prof=0.022,
            esp=0.004,
            mat=m2 if (k + sem) % 3 == 0 else m1,
            sem=sem + k,
        )
        ob["so_bake"] = True
        rec.add(ob, "Telhado", "Telhado")
    rec.add(
        placa_lisa(
            f"{nome}_placa",
            (x0, y_baixo, z_baixo),
            (x1, y_baixo, z_baixo),
            (x1, y_alto, z_alto),
            (x0, y_alto, z_alto),
            m1,
        ),
        "Telhado",
        "Telhado",
    )
    rec.add(
        forro(
            f"{nome}_forro",
            (x0, y_baixo, z_baixo),
            (x1, y_baixo, z_baixo),
            (x1, y_alto, z_alto),
            (x0, y_alto, z_alto),
            mat_forro(f"forro_{nome}"),
        ),
        "Telhado",
        "Telhado",
    )
    for t in (0.1, 0.9):
        p = o0 + (fim - o0) * t
        rec.add(
            V.viga(
                f"{nome}_terca{int(t * 10)}",
                (x0, p.y, p.z - 0.06),
                (x1, p.y, p.z - 0.06),
                0.07,
                0.08,
                mats.go,
            ),
            "Casa",
            "Estrutura",
        )
    rec.prisma(
        f"{nome}_agua",
        [
            (x0, y_baixo, z_baixo + 0.02),
            (x1, y_baixo, z_baixo + 0.02),
            (x0, y_alto, z_alto + 0.02),
            (x1, y_alto, z_alto + 0.02),
            (x0, y_baixo, z_baixo + 0.08),
            (x1, y_baixo, z_baixo + 0.08),
            (x0, y_alto, z_alto + 0.08),
            (x1, y_alto, z_alto + 0.08),
        ],
        "para",
        "Metal",
    )


def oitao_tabuas(rec, nome, L, W, h, hr, mat, esp=0.05):
    """Fecha os triângulos das empenas (±X) com tábua, colisão em prisma."""
    for sx in (-1, 1):
        x = sx * (L / 2 - esp / 2)
        pts = [(-W / 2, h), (W / 2, h), (0, hr)]

        def f(u, v, x=x):
            meia = W / 2 * (1 - v)
            return (x, -meia + 2 * meia * u, h + (hr - h) * v)

        me = V.grade(f"{nome}{sx}", f, 8, 4, fora=Vector((sx, 0, 0)))
        M.solidificar(me, esp, 0.0)  # as duas faces: a empena também é vista de dentro
        V.gravar_uv_local(me, lambda p: (p.y, p.z, p.x))
        me.data.materials.append(mat)
        rec.add(me, "Casa", "Paredes")
        rec.prisma(
            f"{nome}{sx}",
            [(x + d, y, z) for d in (-esp / 2, esp / 2) for y, z in pts],
            "para",
            "Wood",
        )
