"""Peças comuns do povoado da Vila (D-255). Metros, Z para cima, frente em -Y.

Paredes que vão para a trim sheet usam os nomes das faixas (`vach_dat`, `vach_cal`, `gach`, `trinh`,
`phen_par`, `van`). A pedra laterítica tem material próprio: o modelo que a usa sai sem `--trim`.
Tudo parado: nenhum pano, folha ou corda tem animação (sem vento, D-253).
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_comum as E  # noqa: E402
import exp_vila as X  # noqa: E402
import modelar as M  # noqa: E402
import ret_comboio as RC  # noqa: E402
import ret_frente as RF  # noqa: E402
import ret_mercado as RM  # noqa: E402
import ret_vila as RV  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from modelar import Mat, rgb  # noqa: E402
from vila_comum import PISO  # noqa: E402

_est, _mob = RC._est, RC._mob

# Na conversão para a trim sheet, o grupo Casa não usa o atlas: ele fica pequeno de propósito
ATLAS_G = {
    "Telhado": {"tex": 1024, "teto": 3600, "amostras_ao": 8},
    "Mobilia": {"tex": 1024, "teto": 6200, "amostras_ao": 8},
    "Casa": {"tex": 512, "teto": 9000, "amostras_ao": 4},
}
ATLAS_LAT = {
    "Telhado": {"tex": 1024, "teto": 3600, "amostras_ao": 8},
    "Mobilia": {"tex": 512, "teto": 4200, "amostras_ao": 8},
    "Casa": {"tex": 1024, "teto": 9000, "amostras_ao": 8},
}
ATLAS_M = {
    "Telhado": {"tex": 512, "teto": 2400, "amostras_ao": 8},
    "Mobilia": {"tex": 512, "teto": 3600, "amostras_ao": 8},
    "Casa": {"tex": 256, "teto": 5000, "amostras_ao": 4},
}
ATLAS_P = {
    "Telhado": {"tex": 256, "teto": 1000, "amostras_ao": 4},
    "Mobilia": {"tex": 512, "teto": 2200, "amostras_ao": 4},
    "Casa": {"tex": 256, "teto": 2200, "amostras_ao": 4},
}


def mat_laterita(nome="laterita"):
    """Blocos de pedra laterítica de Quảng Ngãi: ocre-avermelhados, porosos, com musgo no pé."""
    m = Mat(nome, rug=0.96)
    p = m.coord("local")
    u, z, _ = m.separar(p)
    fila = m.conta("FLOOR", m.conta("MULTIPLY", z, 1 / 0.31))
    fz = m.conta("FRACT", m.conta("MULTIPLY", z, 1 / 0.31))
    desl = m.conta("MULTIPLY", m.conta("MODULO", m.conta("ADD", fila, 400.0), 2.0), 0.5)
    uu = m.conta("ADD", m.conta("MULTIPLY", u, 1 / 0.62), desl)
    fu = m.conta("FRACT", uu)
    junta = m.conta(
        "MAXIMUM",
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fz, 0.5)), 0.43, 0.49),
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fu, 0.5)), 0.455, 0.495),
    )
    tom = m.ruido(m.juntar_xyz(m.conta("FLOOR", uu), m.conta("MULTIPLY", fila, 0.7), 0), 1.0, 1)
    cor = m.rampa(tom, [(0.25, rgb("#7a4529")), (0.55, rgb("#9c5f38")), (0.8, rgb("#b57a4a"))])
    poro = m.faixa(m.ruido(p, 34.0, 3), 0.6, 0.72)
    cor = m.misturar(poro, cor, rgb("#4a2a1b"))
    musgo = m.conta(
        "MULTIPLY", m.faixa(z, 0.7, 0.05), m.faixa(m.ruido(p, 2.4, 4), 0.46, 0.66, 0.0, 0.6)
    )
    cor = m.misturar(musgo, cor, rgb("#4b5232"))
    cor = m.misturar(junta, cor, rgb("#5d4433"))
    m.cor(cor)
    m.relevo(m.conta("SUBTRACT", 1.0, junta), 1.0, 0.02)
    m.relevo(m.conta("SUBTRACT", 1.0, poro), 0.4, 0.004)
    return m.m


def parede(tipo: str):
    if tipo == "vach_dat":
        return V.mat_vach_dat("vach_dat")
    if tipo == "vach_cal":
        return V.mat_vach_dat("vach_cal", cal="#d6cdb8", exposta=0.25)
    if tipo == "gach":
        return V.mat_gach("gach")
    if tipo == "trinh":
        return V.mat_trinh("trinh")
    if tipo == "van":
        return V.mat_tabua("van")
    if tipo == "phen_par":
        return RV._phen()
    if tipo == "laterita":
        return bpy.data.materials.get("laterita") or mat_laterita()
    raise ValueError(tipo)


COL = {
    "vach_dat": "Earth",
    "vach_cal": "Earth",
    "gach": "Brick",
    "trinh": "Earth",
    "van": "Wood",
    "phen_par": "Bamboo",
    "laterita": "Brick",
}


def B(rec, nome, dim, c, mat, est=False, chanfro=0.0, rot=None):
    o = V.bloco(nome, dim, c, mat, chanfro=chanfro, rot=rot)
    (_est if est else _mob)(rec, o)
    return o


def T(rec, nome, a, b, r, mat, est=False, segs=5):
    o = V.tre(nome, a, b, r, mat, segs=segs)
    (_est if est else _mob)(rec, o)
    return o


def Vg(rec, nome, a, b, larg, alt, mat, est=True):
    o = V.viga(nome, a, b, larg, alt, mat)
    (_est if est else _mob)(rec, o)
    return o


def janelas(lado, ts, w=1.1):
    return [
        {"lado": lado, "t": t, "w": w, "z0": 1.05, "z1": 2.1, "estilo": "aberta", "aba": True}
        for t in ts
    ]


def telha(a="#94563c", b="#6e3d2a", c="#ad6c48"):
    return RF._ngoi(a, b, c)


def cobertura(
    rec, mats, sem, L, W, H, tel="tranh", forma="2aguas", alto=2.2, beiral=0.65, par=None, esp=0.14
):
    """Telhado sobre o corpo: palha, nipa, telha ou chapa remendada."""
    hr = H + alto
    if tel == "chapa":
        E.oitao_tabuas(rec, "oitao", L, W, H, hr, par or parede("van"))
        E.telhado_chapa(rec, "tel", L, W, H, hr, beiral, mats, sem=sem, ferrugem=0.5)
        return hr
    mt = {"tranh": V.mat_tranh, "la": V.mat_la}.get(tel)
    material = mt(tel) if mt else telha()
    extra = {}
    if forma == "2aguas":
        extra = {"mat_oitao": par, "oitao_esp": esp, "col_oitao": "Earth"}
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        hr,
        beiral,
        forma,
        tel,
        0.1 if tel == "ngoi" else 0.26,
        material,
        mats,
        beiral_oitao=beiral * 0.8,
        sem=sem,
        tesouras=(-L / 4, L / 4) if L > 5 else (0.0,),
        **extra,
    )
    return hr


def corpo(
    rec,
    mats,
    sem,
    L,
    W,
    H,
    tipo,
    portas,
    jans,
    tel="tranh",
    forma="2aguas",
    alto=2.2,
    beiral=0.65,
    esp=0.14,
    lados=("frente", "fundo", "esq", "dir"),
    vaos_extra=None,
):
    """Paredes, piso e telhado. Devolve os limites internos (xi, yi)."""
    par = parede(tipo)
    bala = "passa" if tipo == "phen_par" else "para"
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        par,
        portas,
        jans,
        col=COL[tipo],
        bala=bala,
        sem=sem,
        lados_usar=lados,
        postes_tre=tipo == "phen_par",
        vaos_extra=vaos_extra,
    )
    cobertura(rec, mats, sem, L, W, H, tel, forma, alto, beiral, par, esp)
    return L / 2 - esp, W / 2 - esp


def varanda(rec, mats, sem, L, W, prof=1.7, alt=2.5, topo=2.95, tel="tranh", n=4):
    """Varanda na frente, com postes, frechal e água única."""
    yv = -W / 2 - prof
    V.nen(rec, "nen_v", -L / 2 - 0.15, yv - 0.15, L / 2 + 0.15, -W / 2, mats)
    xs = [-L / 2 + k * L / n for k in range(n + 1)]
    for k, x in enumerate(xs):
        V.poste(rec, f"pv{k}", x, yv + 0.05, alt, mats.go, r=0.09, base_pedra=mats.pedra)
    Vg(
        rec,
        "fre_v",
        (-L / 2 - 0.1, yv + 0.05, alt),
        (L / 2 + 0.1, yv + 0.05, alt),
        0.11,
        0.13,
        mats.go,
    )
    mt = {"tranh": V.mat_tranh, "la": V.mat_la}.get(tel)
    material = mt(tel) if mt else telha()
    V.agua_unica(
        rec,
        "tel_v",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        -W / 2 + 0.02,
        topo,
        yv - 0.42,
        alt + 0.02,
        0.1 if tel == "ngoi" else 0.2,
        tel,
        material,
        mats,
        sem=sem + 5,
    )
    return yv


def letreiro(rec, nome, texto, c, larg=2.2, alt=0.52, fundo="#5c1f17", letra="#e6c877", tam=None):
    """Tabuleta de madeira pintada com texto vietnamita de verdade, virada para -Y."""
    tab = V.mat_liso(f"placa_{nome}", fundo, "#2f120e", rug=0.6, escala=5.0, forca=0.3)
    cor = V.mat_liso(f"letra_{nome}", letra, "#9a8650", rug=0.5)
    B(rec, f"{nome}_tab", (larg, 0.05, alt), c, tab, chanfro=0.008)
    RV._letreiro(rec, f"{nome}_txt", texto, (c[0], c[1] - 0.032, c[2]), tam or alt * 0.56, cor)


def muro(rec, mats, nome, a, b, h, mat, esp=0.34, col="Brick", capa=True):
    """Muro reto de a a b (x, y), com capa de pedra. O grupo é Casa."""
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    comp = math.hypot(b[0] - a[0], b[1] - a[1])
    lado = V.Lado(a, ang, comp, esp, 1.0)
    V.parede(rec, nome, lado, 0.0, h, mat, (), col, "para")
    if capa:
        c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, h + 0.035)
        B(
            rec,
            f"{nome}_capa",
            (comp + 0.06, esp + 0.09, 0.07),
            c,
            mats.pedra,
            est=True,
            rot=(0, 0, ang),
        )


def portal(rec, mats, sem, nome, x, y, larg, alt, mat_col):
    """Portal de duas colunas com telhadinho de telha, passagem no eixo Y."""
    for s in (-1, 1):
        B(rec, f"{nome}_col{s}", (0.5, 0.5, alt), (x + s * larg / 2, y, alt / 2), mat_col, est=True)
        B(
            rec,
            f"{nome}_cap{s}",
            (0.6, 0.6, 0.08),
            (x + s * larg / 2, y, alt + 0.04),
            mats.pedra,
            est=True,
        )
        rec.caixa(
            f"{nome}_col{s}", (x + s * larg / 2, y, alt / 2), (0.5, 0.5, alt), "para", "Brick"
        )
    Vg(
        rec,
        f"{nome}_viga",
        (x - larg / 2, y, alt + 0.14),
        (x + larg / 2, y, alt + 0.14),
        0.22,
        0.2,
        mats.go_escuro,
    )
    marca = rec.marca()
    V.telhado(
        rec,
        f"{nome}_tel",
        larg + 0.4,
        0.9,
        alt + 0.25,
        alt + 1.05,
        0.34,
        "2aguas",
        "ngoi",
        0.08,
        telha("#8a4f36", "#603725", "#a4674a"),
        mats,
        beiral_oitao=0.3,
        sem=sem,
        estrutura=False,
        mat_oitao=mats.go_escuro,
        oitao_esp=0.08,
        col_oitao="Wood",
    )
    rec.transformar(marca, V.lugar((x, y, 0.0)))
    rec.extras["portas_m"].append([x, y, PISO])
    rec.extras["portas"].append(
        {
            "nome": nome,
            "largura_livre_m": larg - 0.5,
            "altura_livre_m": alt,
            "normal_blender": [0, -1, 0],
            "interna": False,
        }
    )


def z_beiral(h, hr, W, beiral):
    """Altura da quina do beiral: a água continua descendo depois do topo da parede."""
    return h + 0.05 - (hr - h) / (W / 2) * beiral


def dao(rec, nome, x, y, z, ang, mat, comp=1.05):
    """A ponta curva do beiral (đao), levantada."""
    ca, sa = math.cos(ang), math.sin(ang)
    pts = []
    for k in range(5):
        t = k / 4
        pts.append((x + ca * comp * t, y + sa * comp * t, z + 0.62 * comp * t * t))
    o = V.tubo_local(nome, pts, [0.13, 0.115, 0.09, 0.06, 0.025], mat, segs=5)
    M.material(o, mat)
    rec.add(o, "Telhado", "Telhado")


def buda(rec, nome, x, y, z, e, mat):
    """Imagem sentada sobre o lótus, em torno: corpo, cabeça e coque."""
    o = [
        V.torno_local(
            f"{nome}_lotus",
            [(0, 0), (0.56, 0), (0.62, 0.08), (0.52, 0.17), (0.46, 0.2), (0, 0.2)],
            12,
            mat,
        ),
        V.torno_local(
            f"{nome}_corpo",
            [
                (0, 0.2),
                (0.48, 0.2),
                (0.5, 0.32),
                (0.34, 0.48),
                (0.27, 0.72),
                (0.21, 0.94),
                (0.1, 1.02),
                (0, 1.04),
            ],
            10,
            mat,
        ),
        RM._bola(f"{nome}_cabeca", (0, 0, 1.2), 0.19, mat),
        RM._bola(f"{nome}_coque", (0, 0, 1.42), 0.07, mat),
    ]
    m = Matrix.Translation((x, y, z)) @ Matrix.Scale(e, 4)
    for ob in o:
        M.mover(ob, m)
        _mob(rec, ob)
    rec.caixa(nome, (x, y, z + 0.72 * e), (1.2 * e, 1.2 * e, 1.44 * e), "para", "Metal")


def incensario(rec, nome, x, y, mats, z=0.0, e=1.0):
    """Đỉnh: incensário de bronze de três pés, com tampa."""
    o = [
        V.torno_local(
            f"{nome}_c",
            [
                (0, 0.3),
                (0.28, 0.3),
                (0.36, 0.46),
                (0.34, 0.62),
                (0.26, 0.68),
                (0.3, 0.72),
                (0.14, 0.86),
                (0.05, 1.0),
                (0, 1.02),
            ],
            10,
            mats.bronze,
        )
    ]
    for k in range(3):
        a = k * 2 * math.pi / 3
        o.append(
            V.tre(
                f"{nome}_p{k}",
                (0.26 * math.cos(a), 0.26 * math.sin(a), 0.0),
                (0.2 * math.cos(a), 0.2 * math.sin(a), 0.34),
                0.035,
                mats.bronze,
                segs=4,
            )
        )
    m = Matrix.Translation((x, y, z)) @ Matrix.Scale(e, 4)
    for ob in o:
        M.mover(ob, m)
        _mob(rec, ob)
    rec.caixa(nome, (x, y, z + 0.5 * e), (0.7 * e, 0.7 * e, e), "para", "Metal")


def prefixar(rec, marca, prefixo):
    """Nomes de colisão únicos quando a mesma peça entra várias vezes no mesmo modelo."""
    for c in rec.colisao[marca[1] :]:
        c["nome"] = f"{prefixo}_{c['nome']}"


def balcao(rec, nome, x, y, comp, mats, prof=0.7, alt=0.92, rot=0):
    X._bancada(rec, nome, (x, y), rot, mats, comp=comp, prof=prof, alt=alt)


def fardos(rec, nome, x, y, mats, z=PISO, colunas=3, linhas=2):
    """Sacos de juta empilhados, com uma caixa de colisão só."""
    pts = [
        (x + (i - (colunas - 1) / 2) * 0.5, y + j * 0.04, (i * 37 + j * 11) % 23 - 11)
        for j in range(linhas)
        for i in range(colunas - j)
    ]
    k = 0
    for j in range(linhas):
        n = colunas - j
        V.sacos(rec, f"{nome}_{j}", pts[k : k + n], mats, z=z + j * 0.25)
        k += n
    alt = 0.27 + (linhas - 1) * 0.25
    rec.caixa(nome, (x, y, z + alt / 2), (colunas * 0.5, 0.42, alt), "para", "Fabric")


def leao(rec, nome, x, y, rot, mats, mat, e=1.0):
    """Nghê: leão de guarda de pedra, sentado sobre a base e olhando para -Y."""
    o = [V.bloco(f"{nome}_base", (0.9, 1.25, 0.46), (0, 0, 0.23), mats.pedra, chanfro=0.03)]
    for parte, a, b, h, c in (
        ("corpo", 0.3, 0.47, 0.36, (0, 0.14, 0.8)),
        ("peito", 0.27, 0.26, 0.42, (0, -0.16, 1.02)),
        ("juba", 0.31, 0.27, 0.3, (0, -0.2, 1.46)),
    ):
        s = M.superelipsoide(f"{nome}_{parte}", a, b, h, 0.75, 0.8, 8, 5)
        V.gravar_uv_local(s, lambda p: (p.x, p.y, p.z))
        M.mover(s, Matrix.Translation(c))
        M.material(s, mat)
        o.append(M.suave(s, 60))
    o.append(RM._bola(f"{nome}_cabeca", (0, -0.36, 1.48), 0.2, mat))
    o.append(V.bloco(f"{nome}_foc", (0.2, 0.14, 0.12), (0, -0.55, 1.42), mat, chanfro=0.03))
    for s in (-1, 1):
        o.append(
            V.tre(f"{nome}_pa{s}", (s * 0.17, -0.36, 0.46), (s * 0.15, -0.26, 1.0), 0.075, mat)
        )
        o.append(RM._bola(f"{nome}_ore{s}", (s * 0.2, -0.26, 1.68), 0.07, mat))
    m = V.lugar((x, y, 0.0), rot) @ Matrix.Scale(e, 4)
    for ob in o:
        M.mover(ob, m)
        _mob(rec, ob)
    V._col_local(
        rec, nome, (x, y), rot, (x, y, 0.85 * e), (0.9 * e, 1.25 * e, 1.7 * e), "para", "Brick"
    )


def _daos(rec, nome, x, y, z, hx, hy, mat, comp):
    for sx in (-1, 1):
        for sy in (-1, 1):
            dao(
                rec,
                f"{nome}{sx}{sy}",
                x + sx * hx,
                y + sy * hy,
                z,
                math.atan2(sy, sx),
                mat,
                comp=comp,
            )


def torre_chua(rec, mats, sem, nome, x, y, lat, ngoi):
    """Torrezinha de dois telhados ao lado do salão: base de laterita e loja de madeira."""
    S = 2.1
    B(rec, f"{nome}_base", (S, S, 2.3), (x, y, 1.15), lat, est=True)
    B(rec, f"{nome}_porta", (0.74, 0.03, 1.5), (x, y - S / 2 - 0.012, 0.75), mats.laca)
    rec.caixa(f"{nome}_base", (x, y, 1.15), (S, S, 2.3), "para", "Brick")
    B(rec, f"{nome}_loja", (1.5, 1.5, 1.08), (x, y, 2.86), mats.go_escuro, est=True)
    marca = rec.marca()
    for k, (lg, h, hr) in enumerate(((S, 2.32, 3.0), (1.5, 3.4, 4.35))):
        V.telhado(
            rec,
            f"{nome}_t{k}",
            lg,
            lg,
            h,
            hr,
            0.42,
            "4aguas",
            "ngoi",
            0.07,
            ngoi,
            mats,
            beiral_oitao=0.42,
            sem=sem + k,
            estrutura=False,
        )
    rec.transformar(marca, V.lugar((x, y, 0.0)))
    _daos(
        rec, f"{nome}_da", x, y, z_beiral(2.32, 3.0, S, 0.42), S / 2 + 0.42, S / 2 + 0.42, ngoi, 0.5
    )
    _daos(rec, f"{nome}_db", x, y, z_beiral(3.4, 4.35, 1.5, 0.42), 1.17, 1.17, ngoi, 0.42)


def tam_quan(rec, mats, sem, nome, x, y, lat, ngoi, ouro):
    """Tam quan: portal de três vãos, o do meio mais alto, com painéis vermelhos e tabuleta."""
    for s in (-1, 1):
        for parte, px, dim in (("c", 1.65, (0.7, 0.8, 3.5)), ("l", 3.6, (0.6, 0.7, 2.75))):
            c = (x + s * px, y, dim[2] / 2)
            B(rec, f"{nome}_p{parte}{s}", dim, c, lat, est=True)
            rec.caixa(f"{nome}_p{parte}{s}", c, dim, "para", "Brick")
        B(rec, f"{nome}_o{s}", (0.42, 0.02, 2.05), (x + s * 1.65, y - 0.41, 1.75), ouro)
        B(rec, f"{nome}_v{s}", (0.34, 0.03, 1.92), (x + s * 1.65, y - 0.425, 1.75), mats.laca)
        c = (x + s * 2.62, y, 2.5)
        B(rec, f"{nome}_vs{s}", (1.36, 0.52, 0.5), c, lat, est=True)
        rec.caixa(f"{nome}_vs{s}", c, (1.36, 0.52, 0.5), "para", "Brick")
    B(rec, f"{nome}_vc", (2.72, 0.62, 0.64), (x, y, 3.2), lat, est=True)
    rec.caixa(f"{nome}_vc", (x, y, 3.2), (2.72, 0.62, 0.64), "para", "Brick")
    letreiro(rec, f"{nome}_pl", "CHÙA VẠN AN", (x, y - 0.34, 3.2), larg=2.2, alt=0.42)
    marca = rec.marca()
    V.telhado(
        rec,
        f"{nome}_tc",
        4.3,
        1.5,
        3.52,
        4.62,
        0.46,
        "4aguas",
        "ngoi",
        0.08,
        ngoi,
        mats,
        beiral_oitao=0.46,
        sem=sem,
        estrutura=False,
    )
    rec.transformar(marca, V.lugar((x, y, 0.0)))
    _daos(rec, f"{nome}_dc", x, y, z_beiral(3.52, 4.62, 1.5, 0.46), 2.6, 1.2, ngoi, 0.62)
    for s in (-1, 1):
        marca = rec.marca()
        V.telhado(
            rec,
            f"{nome}_tl{s}",
            2.3,
            1.2,
            2.77,
            3.36,
            0.34,
            "4aguas",
            "ngoi",
            0.07,
            ngoi,
            mats,
            beiral_oitao=0.34,
            sem=sem + 1 + s,
            estrutura=False,
        )
        rec.transformar(marca, V.lugar((x + s * 3.0, y, 0.0)))
    rec.extras["portas_m"].append([x, y, PISO])
    rec.extras["portas"].append(
        {
            "nome": nome,
            "largura_livre_m": 2.6,
            "altura_livre_m": 2.85,
            "normal_blender": [0, -1, 0],
            "interna": False,
        }
    )
