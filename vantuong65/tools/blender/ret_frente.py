"""Marcos do Vale das Cinco Passagens (D-243, prompt 18.3). Metros, Z para cima, frente em -Y.

- Mercado: `ret_merc_fachadas` (lojas estreitas na margem) e `ret_merc_cais` (cais e barcos);
- Olaria: `ret_olaria_fornos`, `ret_olaria_galpao` e `ret_olaria_secagem`;
- Escola: `ret_escola_principal` e `ret_escola_ala`, que formam o U em volta do pátio;
- Engenho: `ret_engenho_galpao`, com treliças, máquinas, passarela e plataforma de carga;
- Vila dos Esteios: `ret_esteio_comunal`, a casa comunal de cobertura ampla.
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
import ret_mercado as RM  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from modelar import Mat, rgb  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

ATLAS_G = {
    "Telhado": {"tex": 1024, "teto": 3600, "amostras_ao": 16},
    "Mobilia": {"tex": 1024, "teto": 7000, "amostras_ao": 16},
    "Casa": {"tex": 1024, "teto": 9000, "amostras_ao": 8},
}
ATLAS_M = {
    "Telhado": {"tex": 512, "teto": 2200, "amostras_ao": 8},
    "Mobilia": {"tex": 1024, "teto": 5000, "amostras_ao": 8},
    "Casa": {"tex": 1024, "teto": 5000, "amostras_ao": 8},
}
ATLAS_P = {
    "Mobilia": {"tex": 512, "teto": 4200, "amostras_ao": 8},
    "Casa": {"tex": 512, "teto": 3200, "amostras_ao": 8},
}


def _tom(cor: str, f: float) -> str:
    r, g, b = (int(cor[i : i + 2], 16) for i in (1, 3, 5))
    return "#{:02x}{:02x}{:02x}".format(*(min(255, round(c * f)) for c in (r, g, b)))


def _reboco(nome, cal, exposta=0.25):
    """Reboco caiado gasto sobre tijolo: tom irregular, escorridos, pé úmido e poucas falhas."""
    m = Mat(nome, rug=0.9)
    p = m.coord("local")
    u, z, _ = m.separar(p)
    manchas = m.ruido(p, 1.1, 4, 0.55)
    cor = m.rampa(
        manchas,
        [(0.3, rgb(_tom(cal, 0.86))), (0.55, rgb(cal)), (0.8, rgb(_tom(cal, 1.05)))],
    )
    grao = m.ruido(p, 26.0, 3)
    cor = m.misturar(m.faixa(grao, 0.5, 0.75, 0.0, 0.1), cor, rgb(_tom(cal, 0.74)))
    # escorridos que descem do beiral
    escorre = m.faixa(m.ruido(m.mapear(p, (11, 0.5, 11)), 1.0, 3), 0.52, 0.72, 0.0, 0.34)
    escorre = m.conta("MULTIPLY", escorre, m.faixa(z, 0.7, 2.7))
    cor = m.misturar(escorre, cor, rgb("#5f5647"))
    # pé úmido, de respingo da chuva
    pe = m.conta(
        "MULTIPLY", m.faixa(z, 0.62, 0.08), m.faixa(m.ruido(p, 3.2, 3), 0.3, 0.6, 0.3, 0.72)
    )
    cor = m.misturar(pe, cor, rgb("#6a5a44"))
    # as falhas: pequenas, com o tijolo de verdade por baixo
    fila = m.conta("FLOOR", m.conta("MULTIPLY", z, 1 / 0.09))
    fz = m.conta("FRACT", m.conta("MULTIPLY", z, 1 / 0.09))
    desl = m.conta("MULTIPLY", m.conta("MODULO", m.conta("ADD", fila, 400.0), 2.0), 0.5)
    uu = m.conta("ADD", m.conta("MULTIPLY", u, 1 / 0.24), desl)
    fu = m.conta("FRACT", uu)
    junta = m.conta(
        "MAXIMUM",
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fz, 0.5)), 0.39, 0.46),
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fu, 0.5)), 0.45, 0.48),
    )
    tom = m.ruido(m.juntar_xyz(m.conta("FLOOR", uu), m.conta("MULTIPLY", fila, 0.7), 0), 1.0, 1)
    tij = m.rampa(tom, [(0.25, rgb("#74402c")), (0.55, rgb("#9a583e")), (0.8, rgb("#b27450"))])
    tij = m.misturar(junta, tij, rgb("#8a8071"))
    lim = 0.71 - 0.14 * exposta
    falha_n = m.ruido(m.mapear(p, (1, 1, 1), (3.1, 0, 0)), 1.5, 5, 0.6)
    borda = m.faixa(falha_n, lim - 0.022, lim, 0.0, 0.5)
    cor = m.misturar(borda, cor, rgb("#6f6452"))
    falha = m.faixa(falha_n, lim, lim + 0.008)
    cor = m.misturar(falha, cor, tij)
    m.cor(cor)
    m.relevo(m.conta("SUBTRACT", 1.0, falha), 0.55, 0.006)
    m.relevo(grao, 0.2, 0.001)
    return m.m


def _mat_tijolo(nome, escuro="#6e3a28", base="#9a553b", claro="#b4744e", junta="#8d8373"):
    """Tijolo à vista em amarração, sem reboco: fiada de 9 cm e tijolo de 24 cm."""
    m = Mat(nome, rug=0.88)
    p = m.coord("local")
    u, z, _ = m.separar(p)
    fila = m.conta("FLOOR", m.conta("MULTIPLY", z, 1 / 0.09))
    fz = m.conta("FRACT", m.conta("MULTIPLY", z, 1 / 0.09))
    desl = m.conta("MULTIPLY", m.conta("MODULO", m.conta("ADD", fila, 400.0), 2.0), 0.5)
    uu = m.conta("ADD", m.conta("MULTIPLY", u, 1 / 0.24), desl)
    fu = m.conta("FRACT", uu)
    j = m.conta(
        "MAXIMUM",
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fz, 0.5)), 0.39, 0.46),
        m.faixa(m.conta("ABSOLUTE", m.conta("SUBTRACT", fu, 0.5)), 0.45, 0.48),
    )
    tom = m.ruido(m.juntar_xyz(m.conta("FLOOR", uu), m.conta("MULTIPLY", fila, 0.7), 0), 1.0, 1)
    cor = m.rampa(tom, [(0.25, rgb(escuro)), (0.55, rgb(base)), (0.8, rgb(claro))])
    # fuligem em manchas largas: o forno trabalha
    fuligem = m.faixa(m.ruido(p, 1.4, 4), 0.56, 0.74, 0.0, 0.42)
    cor = m.misturar(fuligem, cor, rgb("#2f2622"))
    cor = m.misturar(j, cor, rgb(junta))
    m.cor(cor)
    m.relevo(m.conta("SUBTRACT", 1.0, j), 0.6, 0.008)
    m.relevo(m.ruido(p, 60.0, 3), 0.15, 0.001)
    return m.m


def _tijolo(nome="tijolo"):
    return _mat_tijolo(nome)


def _cru(nome="tijolo_cru"):
    return _mat_tijolo(nome, "#7d5e42", "#a9835e", "#c09a72", "#8f7a60")


def _ngoi(a="#94563c", b="#6e3d2a", c="#ad6c48"):
    return V.mat_ngoi("ngoi", a, b, c)


# =============================================================== Mercado: a margem
def _loja_estreita(rec, nome, cx, L, W, H, par, mats, sem, chapa=False):
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        nome,
        L,
        W,
        H,
        0.14,
        par,
        [
            {"lado": "frente", "t": -L * 0.18, "estilo": "folhas"},
            {"lado": "fundo", "t": L * 0.18, "estilo": "tabua", "folha": 1},
        ],
        [
            {"lado": "frente", "t": L * 0.32, "w": 0.7, "z0": 1.05, "z1": 2.05, "estilo": "tre"},
            {"lado": "fundo", "t": -L * 0.28, "w": 0.7, "z0": 1.05, "z1": 2.05, "estilo": "tre"},
        ],
        col="Earth",
        sem=sem,
    )
    if chapa:
        E.oitao_tabuas(rec, f"{nome}_oitao", L, W, H, H + 1.35, V.mat_tabua("van"))
        E.telhado_chapa(rec, f"{nome}_tel", L, W, H, H + 1.35, 0.5, mats, sem=sem, ferrugem=0.96)
    else:
        V.telhado(
            rec,
            f"{nome}_tel",
            L,
            W,
            H,
            H + 1.6,
            0.5,
            "2aguas",
            "ngoi",
            0.1,
            _ngoi(),
            mats,
            beiral_oitao=0.28,
            sem=sem,
            tesouras=(0.0,),
            mat_oitao=par,
            oitao_esp=0.14,
            col_oitao="Earth",
        )
    X._prateleira(
        rec, f"{nome}_est", (-L * 0.1, W / 2 - 0.38), 0, mats, comp=min(L - 1.9, 1.7), z=PISO
    )
    X._pote(
        rec, f"{nome}_pote", (L / 2 - 0.5, -W / 2 + 0.55), mats, alt=0.6, r=0.25, z=PISO, sem=sem
    )
    rec.transformar(marca, V.lugar((cx, 0.0, 0.0)))


def receita_ret_merc_fachadas():
    rec = V.Receita()
    mats = Mats(561)
    W = 5.6
    casas = (
        ("a", -4.25, 4.1, 3.05, _reboco("reb_a", "#d6b25f"), False, RM.LONA),
        ("b", 0.0, 4.4, 3.6, _reboco("reb_b", "#b9c0a2"), True, RM.LONA_VERDE),
        ("c", 4.3, 4.2, 3.2, _reboco("reb_c", "#d9cfb6"), False, RM.LONA_OCRE),
    )
    for k, (n, cx, L, H, par, chapa, lona) in enumerate(casas):
        _loja_estreita(rec, f"l{n}", cx, L, W, H, par, mats, 561 + k, chapa)
        RM._toldo(
            rec,
            f"toldo_{n}",
            cx - L / 2 + 0.08,
            cx + L / 2 - 0.08,
            -W / 2 + 0.02,
            min(H, 3.05) - 0.12,
            -W / 2 - 1.25,
            2.46,
            RM._panos(561 + k, lona),
        )
    X._cesto(rec, "cesto_a", (-5.4, -W / 2 - 0.5), mats, r=0.28, alt=0.42)
    X._caixote(rec, "cx_a", (3.3, -W / 2 - 0.45), 6, mats, dim=(0.75, 0.5, 0.48))
    VC.camera(rec, (-5.2, -1.6, PISO + 1.6), (-3.2, 2.0, PISO + 0.9))
    return rec


def _barco(rec, nome, pos, rot, mats: Mats, comp=4.6, boca=1.15, z=0.0):
    def f(a, b):
        x = (a - 0.5) * comp
        afina = max(0.0, 1 - abs(2 * a - 1) ** 2.4)
        y = (b * 2 - 1) * boca / 2 * afina
        fundo = 0.05 + 0.22 * (2 * b - 1) ** 2
        ponta = 0.22 * abs(2 * a - 1) ** 3
        return (x, y, fundo * 1.5 + ponta)

    casco = V.grade(f"{nome}_casco", f, 16, 6, fora=(0, 0, -1))
    M.solidificar(casco, 0.03, 0.0)
    V.gravar_uv_local(casco, lambda p: (p.x, p.y, p.z))
    M.material(casco, mats.go_escuro)
    o = [M.suave(casco, 50)]
    for k, x in enumerate((-1.1, 0.0, 1.05)):
        lg = boca * max(0.25, 1 - abs(2 * (x / comp)) ** 2.4)
        o.append(V.bloco(f"{nome}_b{k}", (0.2, lg - 0.06, 0.03), (x, 0, 0.3), mats.go))
    X._colocar(rec, o, nome, pos, rot, z, (0, 0, 0.2), (comp * 0.92, boca, 0.4), "passa", "Wood")


def receita_ret_merc_cais():
    """Cais de pedra: z = 0 fica no fundo do rio; o topo encontra o chão da margem."""
    rec = V.Receita()
    mats = Mats(571)
    L, H = 22.0, 2.9
    pedras = (
        mats.pedra,
        V.mat_liso("pedra_b", "#6f6a5f", "#55524a", rug=0.9, escala=7.0, forca=0.55),
        V.mat_liso("pedra_c", "#8a8476", "#68645a", rug=0.85, escala=6.0, forca=0.5),
    )
    fiadas = 5
    h = H / fiadas
    k = 0
    for f in range(fiadas):
        x = -L / 2 - (0.0 if f % 2 == 0 else 0.42)
        while x < L / 2 - 0.05:
            w = 0.74 + 0.22 * math.sin(k * 2.7)
            xb = min(x + w, L / 2)
            xa = max(x, -L / 2)
            if xb - xa > 0.1:
                rec.add(
                    V.bloco(
                        f"pedra{k}",
                        (xb - xa - 0.025, 0.34, h - 0.025),
                        ((xa + xb) / 2, -0.28 + 0.012 * math.sin(k * 1.3), (f + 0.5) * h),
                        pedras[k % 3],
                        chanfro=0.018,
                    ),
                    "Casa",
                    "Estrutura",
                )
            x += w
            k += 1
    rec.add(
        V.bloco("miolo", (L, 1.2, H - 0.06), (0, 0.45, (H - 0.06) / 2), mats.pedra),
        "Casa",
        "Estrutura",
    )
    rec.caixa("muro", (0, 0.42, H / 2), (L, 1.32, H), "para", "Concrete")
    E.piso_tabuas(rec, "deck", -L / 2, -0.46, L / 2, 2.0, H + 0.04, mats)
    rec.caixa("deck_b", (0, 1.55, H / 2), (L, 0.9, H), "para", "Concrete")
    x_esc = -3.6
    meia = 0.86
    E.guarda_corpo(rec, "gc_a", (-L / 2, -0.42), (x_esc - meia, -0.42), H + 0.04, mats, passo=1.3)
    E.guarda_corpo(rec, "gc_b", (x_esc + meia, -0.42), (L / 2, -0.42), H + 0.04, mats, passo=1.3)
    E.escada(rec, "escada", (x_esc, -3.05, 0.62), (x_esc, -0.44, H + 0.04), 1.5, mats)
    for k, x in enumerate((-8.6, 1.4, 8.8)):
        rec.add(
            V.cilindro(f"amarra{k}", 0.13, 0.62, (x, 0.05, H + 0.34), mats.go_escuro, segs=8),
            "Mobilia",
            "Mobilia",
        )
        rec.caixa(f"amarra{k}", (x, 0.05, H + 0.34), (0.26, 0.26, 0.62), "para", "Wood")
    _barco(rec, "barco_a", (3.6, -1.35), 2, mats, z=0.62)
    _barco(rec, "barco_b", (-8.6, -1.45), -3, mats, comp=3.9, boca=1.0, z=0.62)
    zc = H + 0.04
    V.sacos(
        rec,
        "sacos",
        [(5.4, 0.9, 8), (5.95, 0.92, -9), (5.65, 1.32, 84)],
        mats,
        z=zc,
    )
    rec.caixa("sacos", (5.68, 1.12, zc + 0.26), (1.3, 1.0, 0.52), "para", "Fabric")
    X._caixote(rec, "cx_a", (-6.6, 1.2), 12, mats, z=zc)
    X._cesto(rec, "cesto_a", (-1.3, 1.25), mats, r=0.3, alt=0.46, z=zc)
    X._cesto(rec, "cesto_b", (-0.6, 1.4), mats, r=0.24, alt=0.38, z=zc)
    VC.camera(rec, (-9.0, 1.3, zc + 1.6), (6.0, -1.0, zc + 0.4))
    return rec


# =============================================================== Olaria do Barranco
def _forno(rec, nome, cx, cy, r, alt, tij, mats: Mats, boca=-1):
    perfil = [
        (0.0, 0.0),
        (r, 0.0),
        (r * 1.02, alt * 0.13),
        (r * 0.99, alt * 0.34),
        (r * 0.89, alt * 0.55),
        (r * 0.71, alt * 0.74),
        (r * 0.45, alt * 0.89),
        (r * 0.2, alt * 0.97),
        (r * 0.16, alt),
        (r * 0.1, alt),
        (0.0, alt * 0.94),
    ]
    o = V.torno_local(f"{nome}_cupula", perfil, 22, tij)
    # o tijolo corre em volta da cúpula; a emenda fica nas costas, longe da boca
    V.gravar_uv_local(
        o, lambda q: (math.atan2(-q.x, -q.y * boca * -1) * r, q.z, math.hypot(q.x, q.y))
    )
    M.mover(o, Matrix.Translation((cx, cy, 0.0)))
    V.sem_fundo(o, 0.0)
    rec.add(o, "Casa", "Estrutura")
    # cintas de ferro, a boca escura com arco de tijolo e o aviso de que não se entra
    for k, z in enumerate((alt * 0.2, alt * 0.48)):
        rr = r * (1.03 if k == 0 else 0.97)
        cinta = M.toro(f"{nome}_cinta{k}", rr, 0.028, 26, 4)
        V.gravar_uv_local(cinta, lambda p: (p.x, p.y, p.z))
        M.material(cinta, mats.ferro)
        M.mover(cinta, Matrix.Translation((cx, cy, z)))
        rec.add(M.suave(cinta, 45), "Casa", "Estrutura")
    yb = cy + boca * r * 0.985
    negro = V.mat_liso("forno_negro", "#14100d", "#2a1c14", rug=0.95)
    rec.add(
        V.bloco(f"{nome}_boca", (1.05, 0.08, 0.72), (cx, yb + boca * 0.015, 0.4), negro),
        "Casa",
        "Estrutura",
    )
    disco = V.cilindro(f"{nome}_bocad", 0.525, 0.08, (0, 0, 0), negro, segs=14)
    M.mover(
        disco,
        Matrix.Translation((cx, yb + boca * 0.015, 0.76)) @ Matrix.Rotation(math.pi / 2, 4, "X"),
    )
    rec.add(disco, "Casa", "Estrutura")
    for k in range(11):
        a = math.pi * k / 10
        c = (cx + math.cos(a) * 0.62, yb + boca * 0.09, 0.76 + math.sin(a) * 0.62)
        rec.add(
            V.bloco(
                f"{nome}_arco{k}",
                (0.24, 0.2, 0.15),
                c,
                tij,
                chanfro=0.012,
                rot=(0, -a + math.pi / 2, 0),
            ),
            "Casa",
            "Estrutura",
        )
    for s in (-1, 1):
        rec.add(
            V.bloco(
                f"{nome}_ombro{s}",
                (0.26, 0.24, 0.8),
                (cx + s * 0.64, yb + boca * 0.09, 0.4),
                tij,
                chanfro=0.012,
            ),
            "Casa",
            "Estrutura",
        )
    # grade de ferro: a cavidade tem profundidade visual, mas não é um caminho
    for k in range(5):
        x = cx - 0.4 + k * 0.2
        rec.add(
            V.tre(
                f"{nome}_grade{k}",
                (x, yb + boca * 0.05, 0.03),
                (x, yb + boca * 0.05, 1.05),
                0.012,
                mats.ferro,
                segs=4,
            ),
            "Casa",
            "Estrutura",
        )
    for gr in (0.0, math.pi / 4):
        rec.caixa(
            f"{nome}_b{int(gr * 10)}",
            (cx, cy, alt * 0.3),
            (r * 1.72, r * 1.72, alt * 0.6),
            "para",
            "Brick",
            rot_z=gr,
        )
    rec.caixa(f"{nome}_t", (cx, cy, alt * 0.75), (r * 1.15, r * 1.15, alt * 0.5), "para", "Brick")


def _fiadas(rec, nome, cx, cy, z, comp, prof, n, tij, seca=False):
    """Blocos de tijolo empilhados: cada camada é uma peça só, com a textura das juntas."""
    for k in range(n):
        dx = 0.02 * math.sin(k * 2.4)
        o = V.bloco(
            f"{nome}{k}",
            (comp, prof, 0.098),
            (cx + dx, cy, z + 0.05 + k * 0.102),
            tij,
            chanfro=0.008,
        )
        rec.add(o, "Mobilia", "Mobilia")
    rec.caixa(
        nome,
        (cx, cy, z + n * 0.051),
        (comp, prof, n * 0.102),
        "para",
        "Brick" if not seca else "Earth",
    )


def receita_ret_olaria_fornos():
    rec = V.Receita()
    mats = Mats(601)
    tij = _tijolo("tijolo_forno")
    _forno(rec, "f_a", -3.6, 0.0, 3.2, 5.3, tij, mats)
    _forno(
        rec,
        "f_b",
        3.4,
        0.7,
        2.7,
        4.5,
        _mat_tijolo("tijolo_b", "#5f3425", "#8a4c35", "#a4674a"),
        mats,
    )
    X._lenha(rec, "lenha_a", -7.4, -5.6, -3.0, mats, filas=4)
    X._lenha(rec, "lenha_b", 0.7, 2.3, -2.7, mats, filas=3)
    cru = _cru()
    _fiadas(rec, "pilha_a", -1.0, -3.1, 0.0, 1.5, 0.7, 7, tij)
    _fiadas(rec, "pilha_b", 6.2, -2.3, 0.0, 1.3, 0.7, 5, cru, seca=True)
    VC.camera(rec, (-1.0, -7.5, 1.7), (-1.5, 0.0, 1.4))
    return rec


def receita_ret_olaria_galpao():
    rec = V.Receita()
    mats = Mats(611)
    L, W, H = 12.0, 7.4, 3.25
    van = V.mat_tabua("van")
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        0.07,
        van,
        [{"lado": "fundo", "t": -3.6, "estilo": "tabua", "folha": 1}],
        [
            {"lado": "fundo", "t": 2.2, "w": 1.5, "z0": 1.2, "z1": 2.2, "estilo": "tre"},
            {"lado": "esq", "t": -1.2, "w": 1.2, "z0": 1.1, "z1": 2.1, "estilo": "tre"},
        ],
        col="Wood",
        sem=611,
        lados_usar=("fundo", "esq"),
    )
    hr = H + 1.55
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, van)
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.8, mats, sem=611, ferrugem=0.96)
    n = 4
    for k in range(n + 1):
        V.poste(
            rec,
            f"col{k}",
            -L / 2 + 0.1 + k * (L - 0.2) / n,
            -W / 2 + 0.08,
            H,
            mats.go,
            r=0.11,
            base_pedra=mats.pedra,
        )
    for k in range(1, 3):
        V.poste(
            rec,
            f"col_d{k}",
            L / 2 - 0.08,
            -W / 2 + k * W / 3,
            H,
            mats.go,
            r=0.1,
            base_pedra=mats.pedra,
        )
    rec.add(
        V.viga(
            "frechal", (-L / 2, -W / 2 + 0.08, H), (L / 2, -W / 2 + 0.08, H), 0.14, 0.16, mats.go
        ),
        "Casa",
        "Estrutura",
    )
    for k in range(5):
        x = -L / 2 + (k + 0.5) * L / 5
        rec.add(
            V.viga(f"tes{k}", (x, -W / 2, H), (x, W / 2, H), 0.1, 0.13, mats.go_escuro),
            "Casa",
            "Estrutura",
        )
        rec.add(
            V.viga(f"pend{k}", (x, 0, H), (x, 0, hr - 0.08), 0.08, 0.08, mats.go_escuro),
            "Casa",
            "Estrutura",
        )
    yi = W / 2 - 0.07
    X._prateleira(rec, "est_a", (0.4, yi - 0.26), 0, mats, comp=2.4, z=PISO)
    X._prateleira(rec, "est_b", (3.2, yi - 0.26), 0, mats, comp=2.4, z=PISO)
    X._prateleira(rec, "est_c", (-L / 2 + 0.34, 1.6), 90, mats, comp=2.2, z=PISO)
    X._bancada(rec, "bancada_a", (-2.6, 0.4), 0, mats, comp=2.8, prof=0.85)
    X._bancada(rec, "bancada_b", (2.4, -0.2), 0, mats, comp=2.8, prof=0.85)
    tij = _tijolo("tijolo_g")
    cru = _cru()
    for k, x in enumerate((-3.3, -2.6, -1.9)):
        rec.add(
            V.bloco(
                f"molde{k}",
                (0.5, 0.26, 0.09),
                (x, 0.42, PISO + 0.96),
                mats.go_escuro,
                chanfro=0.008,
            ),
            "Mobilia",
            "Mobilia",
        )
    _fiadas(rec, "bloco_a", 2.0, -0.2, PISO + 0.92, 1.1, 0.45, 2, cru, seca=True)
    _fiadas(rec, "pilha_a", 5.1, -2.2, PISO, 1.2, 0.7, 6, tij)
    _fiadas(rec, "pilha_b", -4.9, -2.3, PISO, 1.2, 0.7, 4, cru, seca=True)
    X._pote(rec, "pote_a", (5.2, 0.6), mats, alt=0.72, r=0.3, z=PISO, sem=611)
    X._pote(rec, "pote_b", (5.2, 1.4), mats, alt=0.6, r=0.26, z=PISO, sem=612)
    VC.camera(rec, (-5.0, -4.6, 1.65), (2.4, 2.2, 1.2))
    return rec


def receita_ret_olaria_secagem():
    """Fileiras de tijolo cru secando e o tanque de barro, com muro baixo."""
    rec = V.Receita()
    mats = Mats(621)
    tij = _tijolo("tijolo_s")
    cru = _cru()
    for f, y in enumerate((-1.5, 0.0, 1.5)):
        for k, x in enumerate((-3.0, -1.0, 1.0, 3.0)):
            n = 4 + (k + f) % 3
            _fiadas(
                rec,
                f"fila{f}_{k}",
                x,
                y,
                0.0,
                1.55,
                0.62,
                n,
                cru if (k + f) % 3 else tij,
                seca=True,
            )
    # tanque de barro vermelho, com muro de tijolo
    barro = V.mat_liso("barro_vivo", "#7d4a33", "#5e3525", rug=0.5, escala=5.0, forca=0.4)
    cx, cy = 7.0, 0.0
    a, b = 3.0, 3.6
    rec.add(V.bloco("barro", (a, b, 0.08), (cx, cy, 0.34), barro), "Mobilia", "Mobilia")
    for k, (dx, dy, la, lb) in enumerate(
        (
            (0, -b / 2, a + 0.28, 0.14),
            (0, b / 2, a + 0.28, 0.14),
            (-a / 2, 0, 0.14, b),
            (a / 2, 0, 0.14, b),
        )
    ):
        rec.add(
            V.bloco(f"muro{k}", (la, lb, 0.56), (cx + dx, cy + dy, 0.28), tij, chanfro=0.012),
            "Casa",
            "Estrutura",
        )
        rec.caixa(f"muro{k}", (cx + dx, cy + dy, 0.28), (la, lb, 0.56), "para", "Brick")
    rec.caixa("tanque", (cx, cy, 0.19), (a, b, 0.38), "para", "Earth")
    X._carroca(rec, "carroca", (-6.8, 0.2), 80, mats)
    VC.camera(rec, (-2.5, -5.2, 1.6), (3.0, 0.5, 0.4))
    return rec


def receita_ret_olaria_cobertura():
    """Cobertura de secagem: esteira sobre postes, estante de potes e mureta de tijolo."""
    rec = V.Receita()
    mats = Mats(641)
    L, W = 6.4, 3.8
    z_alto, z_baixo = 2.95, 2.45
    for k, (x, y, h) in enumerate(
        (
            (-L / 2 + 0.1, W / 2 - 0.1, z_alto),
            (0.0, W / 2 - 0.1, z_alto),
            (L / 2 - 0.1, W / 2 - 0.1, z_alto),
            (-L / 2 + 0.1, -W / 2 + 0.1, z_baixo),
            (0.0, -W / 2 + 0.1, z_baixo),
            (L / 2 - 0.1, -W / 2 + 0.1, z_baixo),
        )
    ):
        V.poste(rec, f"col{k}", x, y, h, mats.go, r=0.08, base_pedra=mats.pedra)
    for y, z in ((W / 2 - 0.1, z_alto), (-W / 2 + 0.1, z_baixo)):
        rec.add(
            V.viga(f"fre{k}_{y:.1f}", (-L / 2, y, z), (L / 2, y, z), 0.09, 0.1, mats.go),
            "Casa",
            "Estrutura",
        )
    for k, x in enumerate((-L / 2 + 0.1, -L / 4, 0.0, L / 4, L / 2 - 0.1)):
        rec.add(
            V.viga(
                f"cai{k}",
                (x, W / 2 - 0.1, z_alto + 0.05),
                (x, -W / 2 + 0.1, z_baixo + 0.05),
                0.06,
                0.07,
                mats.go_escuro,
            ),
            "Casa",
            "Estrutura",
        )
    palha = (("#b69a62", "#8f784b"), ("#a98d58", "#7f6a43"), ("#c2a770", "#98814f"))
    RM._toldo(
        rec,
        "esteira",
        -L / 2 - 0.25,
        L / 2 + 0.25,
        W / 2 + 0.2,
        z_alto + 0.12,
        -W / 2 - 0.3,
        z_baixo + 0.08,
        RM._panos(641, palha),
        queda=0.02,
        largura=0.5,
    )
    tij = _tijolo("tijolo_c")
    rec.add(
        V.bloco("mureta", (L - 0.3, 0.24, 0.95), (0, W / 2 - 0.12, 0.475), tij, chanfro=0.012),
        "Casa",
        "Estrutura",
    )
    rec.caixa("mureta", (0, W / 2 - 0.12, 0.475), (L - 0.3, 0.24, 0.95), "para", "Brick")
    X._prateleira(rec, "est_a", (-1.6, W / 2 - 0.5), 0, mats, comp=2.5)
    X._lenha(rec, "lenha", 0.5, 2.7, W / 2 - 0.5, mats, filas=3)
    X._banco(rec, "banco", (-1.7, -0.5), 0, mats, comp=1.5)
    for k, (x, y, a, r) in enumerate(
        ((1.2, -0.7, 0.72, 0.3), (1.9, -0.4, 0.6, 0.26), (2.5, -0.9, 0.5, 0.22))
    ):
        X._pote(rec, f"pote{k}", (x, y), mats, alt=a, r=r, sem=641 + k)
    cru = _cru()
    _fiadas(rec, "fiada_a", -2.3, 0.45, 0.0, 1.2, 0.5, 5, cru, seca=True)
    _fiadas(rec, "fiada_b", -0.7, 0.5, 0.0, 1.2, 0.5, 3, cru, seca=True)
    VC.camera(rec, (-4.6, -3.6, 1.65), (0.6, 0.6, 0.9))
    return rec


def receita_ret_olaria_pilhas():
    """Pilhas de tijolo na altura da cintura: a cobertura do pátio de captura."""
    rec = V.Receita()
    mats = Mats(631)
    tij = _tijolo("tijolo_p")
    cru = _cru()
    pilhas = (
        (-1.62, 0.0, 12, False),
        (0.0, 0.0, 10, True),
        (1.62, 0.0, 12, False),
        (-0.85, 0.72, 8, True),
        (0.85, 0.72, 6, False),
    )
    for k, (x, y, n, seca) in enumerate(pilhas):
        _fiadas(rec, f"p{k}", x, y, 0.0, 1.55, 0.66, n, cru if seca else tij, seca=seca)
    VC.camera(rec, (-3.0, -3.2, 1.4), (0.2, 0.2, 0.5))
    _ = mats
    return rec


# =============================================================== Escola do Pomar
def _carteira(rec, nome, x, y, mats: Mats):
    o = [V.bloco(f"{nome}_tampo", (1.15, 0.46, 0.04), (0, 0, 0.74), mats.go, chanfro=0.006)]
    for sx in (-1, 1):
        o.append(V.bloco(f"{nome}_pe{sx}", (0.05, 0.38, 0.72), (sx * 0.5, 0, 0.36), mats.go_escuro))
    o.append(V.bloco(f"{nome}_banco", (1.1, 0.24, 0.04), (0, 0.5, 0.44), mats.go))
    for sx in (-1, 1):
        o.append(
            V.bloco(f"{nome}_pb{sx}", (0.05, 0.2, 0.42), (sx * 0.46, 0.5, 0.21), mats.go_escuro)
        )
    X._colocar(rec, o, nome, (x, y), 0, PISO, (0, 0.2, 0.39), (1.2, 0.86, 0.78))


def _quadro(rec, nome, x, y, mats: Mats, comp=2.6):
    negro = V.mat_liso("lousa", "#26392f", "#3a4e43", rug=0.7, escala=4.0, forca=0.35)
    rec.add(
        V.bloco(f"{nome}_lousa", (comp, 0.03, 1.1), (x, y, PISO + 1.55), negro),
        "Mobilia",
        "Mobilia",
    )
    for sz, z in ((1, 2.13), (-1, 0.97)):
        rec.add(
            V.bloco(f"{nome}_m{sz}", (comp + 0.1, 0.05, 0.06), (x, y, PISO + z), mats.go),
            "Mobilia",
            "Mobilia",
        )
    for sx in (-1, 1):
        rec.add(
            V.bloco(
                f"{nome}_l{sx}",
                (0.06, 0.05, 1.2),
                (x + sx * (comp / 2 + 0.02), y, PISO + 1.55),
                mats.go,
            ),
            "Mobilia",
            "Mobilia",
        )
    giz = V.mat_liso("giz", "#d9d6c8", "#b5b2a4", rug=0.8)
    for k in range(4):
        a = -comp * 0.34 + k * comp * 0.2
        rec.add(
            V.bloco(
                f"{nome}_g{k}",
                (comp * 0.14, 0.006, 0.018),
                (x + a, y - 0.018, PISO + 1.78 - k * 0.14),
                giz,
            ),
            "Mobilia",
            "Mobilia",
        )


def _ala(chave, L, W, salas, sem, cal="#ded4b6"):
    rec = V.Receita()
    mats = Mats(sem)
    H, esp, VAR = 3.2, 0.18, 2.5
    par = _reboco("cal_escola", cal, 0.16)
    ngoi = _ngoi("#99593d", "#6f3e2b", "#b4714d")
    passo = L / salas
    xs = [-L / 2 + (i + 0.5) * passo for i in range(salas)]
    portas = [{"lado": "frente", "t": x - passo * 0.24, "estilo": "tabua", "folha": 1} for x in xs]
    portas += [{"lado": "fundo", "t": xs[0] - passo * 0.24, "estilo": "tabua", "folha": -1}]
    janelas = [
        {
            "lado": "frente",
            "t": x + passo * 0.2,
            "w": 1.15,
            "z0": 1.0,
            "z1": 2.15,
            "estilo": "tre",
            "aba": False,
        }
        for x in xs
    ]
    janelas += [
        {"lado": "fundo", "t": x + passo * 0.16, "w": 1.2, "z0": 1.05, "z1": 2.15, "estilo": "tre"}
        for x in xs
    ]
    janelas += [
        {"lado": "esq", "t": 0.0, "w": 1.0, "z0": 1.05, "z1": 2.1, "estilo": "tre"},
        {"lado": "dir", "t": 0.0, "w": 1.0, "z0": 1.05, "z1": 2.1, "estilo": "tre"},
    ]
    VC.casa_ret(rec, mats, "c", L, W, H, esp, par, portas, janelas, col="Concrete", sem=sem)
    vao = V.PORTA_LARG + 2 * V.BATENTE
    topo = PISO + V.PORTA_ALT + V.BATENTE
    for k in range(1, salas):
        x = -L / 2 + k * passo
        lado = V.Lado((x, -W / 2 + esp), math.pi / 2, W - 2 * esp, 0.12, 1.0)
        V.parede(
            rec,
            f"div{k}",
            lado,
            0.0,
            H,
            par,
            [(W / 2 + 0.6, vao, -1.0, topo)],
            "Concrete",
            "para",
            sem=sem + k,
        )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        H + 2.15,
        0.55,
        "2aguas",
        "ngoi",
        0.1,
        ngoi,
        mats,
        beiral_oitao=0.45,
        sem=sem,
        tesouras=tuple(-L / 2 + (i + 1) * passo for i in range(salas - 1)),
        mat_oitao=par,
        oitao_esp=esp,
        col_oitao="Concrete",
    )
    yv = -W / 2 - VAR
    V.nen(rec, "varanda", -L / 2 - 0.2, yv - 0.18, L / 2 + 0.2, -W / 2, mats)
    n = max(4, round(L / 2.8))
    zc = 2.92
    gesso = V.mat_liso("pilar_cal", "#d9cfb2", "#b4a98d", rug=0.85, escala=3.0, forca=0.4)
    for k in range(n + 1):
        x = -L / 2 + k * L / n
        rec.add(
            V.bloco(f"pil{k}", (0.3, 0.3, zc), (x, yv + 0.1, zc / 2), gesso, chanfro=0.02),
            "Casa",
            "Estrutura",
        )
        rec.caixa(f"pil{k}", (x, yv + 0.1, zc / 2), (0.3, 0.3, zc), "para", "Concrete")
    rec.add(
        V.viga(
            "frechal",
            (-L / 2 - 0.15, yv + 0.1, zc),
            (L / 2 + 0.15, yv + 0.1, zc),
            0.16,
            0.16,
            mats.go,
        ),
        "Casa",
        "Estrutura",
    )
    V.agua_unica(
        rec,
        "tel_var",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        -W / 2 + 0.02,
        H + 0.68,
        yv - 0.48,
        zc + 0.08,
        0.1,
        "ngoi",
        ngoi,
        mats,
        sem=sem + 2,
    )
    yi = W / 2 - esp
    for i, x in enumerate(xs):
        _quadro(rec, f"quadro{i}", x + passo * 0.05, yi - 0.03, mats, comp=min(passo - 1.3, 2.7))
        for f, yy in enumerate((-1.25, 0.15)):
            for c, dx in enumerate((-passo * 0.24, passo * 0.24)):
                _carteira(rec, f"cart{i}_{f}{c}", x + dx, yy, mats)
        X._prateleira(
            rec,
            f"arm{i}",
            (x - passo / 2 + 0.75, -W / 2 + 0.42),
            0,
            mats,
            comp=1.05,
            prof=0.34,
            z=PISO,
        )
    X._banco(rec, "banco_var", (xs[0] + passo * 0.25, -W / 2 - 0.34), 0, mats, comp=1.5)
    VC.camera(
        rec,
        (xs[0] - passo * 0.36, -W / 2 + 0.8, PISO + 1.6),
        (xs[0] + passo * 0.4, W / 2 - 0.5, PISO + 1.2),
    )
    return rec


def receita_ret_escola_principal():
    return _ala("ret_escola_principal", 24.0, 7.0, 3, 631)


def receita_ret_escola_ala():
    return _ala("ret_escola_ala", 15.0, 6.6, 2, 641)


# =============================================================== Engenho do Canal
def _tremonha(rec, nome, x, y, mats: Mats):
    aco = V.mat_liso("aco_velho", "#6b6253", "#4d4539", rug=0.62, escala=5.0, forca=0.4)
    o = V.torno_local(
        f"{nome}_funil",
        [
            (0.08, 0.0),
            (0.12, 0.0),
            (0.88, 0.95),
            (0.92, 1.45),
            (0.84, 1.48),
            (0.1, 0.1),
            (0.0, 0.08),
        ],
        12,
        aco,
    )
    M.mover(o, Matrix.Translation((x, y, 1.05)))
    rec.add(o, "Mobilia", "Mobilia")
    for sx in (-1, 1):
        for sy in (-1, 1):
            rec.add(
                V.bloco(
                    f"{nome}_p{sx}{sy}",
                    (0.1, 0.1, 2.15),
                    (x + sx * 0.62, y + sy * 0.62, 1.07),
                    mats.go_escuro,
                ),
                "Mobilia",
                "Mobilia",
            )
    rec.add(
        V.bloco(f"{nome}_base", (1.7, 1.2, 0.72), (x, y, 0.36), mats.go, chanfro=0.015),
        "Mobilia",
        "Mobilia",
    )
    roda = M.toro(f"{nome}_roda", 0.56, 0.05, 20, 5)
    V.gravar_uv_local(roda, lambda p: (p.x, p.y, p.z))
    M.material(roda, mats.ferro)
    M.mover(roda, Matrix.Translation((x + 1.14, y, 0.72)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    rec.add(M.suave(roda, 45), "Mobilia", "Mobilia")
    rec.caixa(nome, (x, y, 1.25), (1.7, 1.45, 2.5), "para", "Metal")


def receita_ret_engenho_galpao():
    rec = V.Receita()
    sem = 651
    mats = Mats(sem)
    L, W, H, esp = 28.0, 11.0, 4.4, 0.2
    hr = H + 2.5
    par = _reboco("reb_engenho", "#d0ad60", 0.3)
    janelas = []
    for x in (-10.5, -5.5, 0.5, 5.5, 10.5):
        janelas.append({"lado": "fundo", "t": x, "w": 1.5, "z0": 2.3, "z1": 3.3, "estilo": "tre"})
    for x in (-5.5, 5.5, 10.5):
        janelas.append({"lado": "frente", "t": x, "w": 1.5, "z0": 2.3, "z1": 3.3, "estilo": "tre"})
    portas = [
        {"lado": "frente", "t": 1.6, "estilo": "folhas"},
        {"lado": "fundo", "t": -2.4, "estilo": "tabua", "folha": 1},
    ]
    # o grande vão da empena oeste e o vão de carga na frente
    lados = V.lados_ret(0.0, 0.0, L, W, esp)
    extra = {
        "esq": [(lados["esq"].comp / 2, 4.6, -1.0, 3.7)],
        "frente": [(L / 2 - 10.0, 5.4, -1.0, 3.5)],
    }
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
        janelas,
        col="Concrete",
        sem=sem,
        vaos_extra=extra,
    )
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, par)
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.7, mats, sem=sem, ferrugem=0.96, beiral_oitao=0.4)
    # treliças aparentes: o ritmo que se vê de dentro
    n = 8
    for k in range(1, n):
        x = -L / 2 + k * L / n
        for s in (-1, 1):
            rec.add(
                V.viga(
                    f"tes_p{k}{s}",
                    (x, s * (W / 2 - esp), H),
                    (x, 0, hr - 0.14),
                    0.14,
                    0.18,
                    mats.go_escuro,
                ),
                "Casa",
                "Estrutura",
            )
            rec.add(
                V.viga(f"tes_d{k}{s}", (x, s * W / 4, H), (x, 0, H + 0.02), 0.07, 0.09, mats.go),
                "Casa",
                "Estrutura",
            )
            rec.add(
                V.viga(
                    f"tes_e{k}{s}",
                    (x, s * W / 4, H),
                    (x, s * W / 4, (H + hr) / 2 - 0.1),
                    0.07,
                    0.07,
                    mats.go,
                ),
                "Casa",
                "Estrutura",
            )
        rec.add(
            V.viga(
                f"tes_l{k}", (x, -(W / 2 - esp), H), (x, W / 2 - esp, H), 0.15, 0.18, mats.go_escuro
            ),
            "Casa",
            "Estrutura",
        )
        rec.add(
            V.viga(f"tes_r{k}", (x, 0, H), (x, 0, hr - 0.16), 0.09, 0.09, mats.go),
            "Casa",
            "Estrutura",
        )
    # divisórias que repartem a visão, com vão de passagem
    vao = 2.4
    for k, x in enumerate((-4.0, 6.0)):
        lado = V.Lado((x, -W / 2 + esp), math.pi / 2, W - 2 * esp, 0.1, 1.0)
        c = 2.0 if k == 0 else W - 2.6
        V.parede(
            rec,
            f"div{k}",
            lado,
            0.0,
            3.0,
            V.mat_tabua("van"),
            [(c, vao, -1.0, 2.9)],
            "Wood",
            "para",
            sem=sem + k,
        )
    _tremonha(rec, "trem_a", -8.6, 2.2, mats)
    _tremonha(rec, "trem_b", 1.0, 2.8, mats)
    yi = W / 2 - esp
    for k, (x, y) in enumerate(((-11.6, -3.4), (10.6, 3.6), (11.4, -3.6))):
        V.sacos(
            rec,
            f"sacos{k}",
            [
                (x, y, 7),
                (x + 0.56, y + 0.02, -10),
                (x + 0.28, y + 0.42, 84),
                (x + 1.08, y + 0.2, 4),
            ],
            mats,
            z=PISO + 0.02,
        )
        V.sacos(
            rec,
            f"sacos_c{k}",
            [(x + 0.2, y + 0.1, 16), (x + 0.75, y + 0.1, -6)],
            mats,
            z=PISO + 0.28,
        )
        rec.caixa(
            f"sacos{k}", (x + 0.55, y + 0.2, PISO + 0.36), (1.9, 1.05, 0.72), "para", "Fabric"
        )
    X._bancada(rec, "bancada", (8.2, yi - 0.42), 0, mats, comp=2.8)
    X._prateleira(rec, "estante", (-1.5, yi - 0.26), 0, mats, comp=2.2, z=PISO)
    # passarela de manutenção ao longo do fundo: a escada desce para oeste, longe da divisória,
    # e a cabeça do soldado (2,07 m) passa sob a linha da treliça (4,4 m)
    z_p = 2.25
    x0, x1 = -9.6, -4.5
    E.piso_tabuas(rec, "passarela", x0, yi - 1.5, x1, yi - 0.02, z_p, mats)
    for k, x in enumerate((x0 + 0.1, (x0 + x1) / 2, x1 - 0.1)):
        V.poste(rec, f"pas_p{k}", x, yi - 1.42, z_p - 0.08, mats.go, r=0.07)
    E.guarda_corpo(rec, "pas_g", (x0, yi - 1.48), (x1, yi - 1.48), z_p, mats, passo=0.9)
    E.guarda_corpo(rec, "pas_g2", (x1, yi - 1.48), (x1, yi - 0.04), z_p, mats, passo=0.7)
    E.escada(
        rec, "pas_esc", (x0 - 2.85, yi - 0.78, PISO + 0.01), (x0 + 0.02, yi - 0.78, z_p), 1.35, mats
    )
    # alpendre de carga na frente, com a plataforma
    yp = -W / 2 - 3.4
    xa, xb = L / 2 - 14.2, L / 2 - 2.0
    E.piso_tabuas(rec, "plataforma", xa, yp, xb, -W / 2, 0.62, mats)
    rec.caixa(
        "plataforma_b",
        ((xa + xb) / 2, (yp - W / 2) / 2, 0.3),
        (xb - xa, -W / 2 - yp, 0.6),
        "para",
        "Wood",
    )
    k = 0
    x = xa
    while x <= xb + 0.01:
        V.poste(rec, f"alp{k}", x, yp + 0.08, 3.25, mats.go, r=0.09, base_pedra=mats.pedra)
        x += (xb - xa) / 4
        k += 1
    rec.add(
        V.viga(
            "alp_fre", (xa - 0.1, yp + 0.08, 3.25), (xb + 0.1, yp + 0.08, 3.25), 0.13, 0.15, mats.go
        ),
        "Casa",
        "Estrutura",
    )
    E.telhado_varanda(
        rec,
        "tel_alp",
        xa - 0.35,
        xb + 0.35,
        -W / 2 + 0.02,
        H + 0.05,
        yp - 0.5,
        3.2,
        mats,
        sem,
        ferrugem=0.96,
    )
    E.escada(
        rec,
        "esc_alp",
        (xa + 2.0, yp - 1.25, 0.02),
        (xa + 2.0, yp + 0.02, 0.62),
        1.6,
        mats,
        corrimao=False,
    )
    E.escada(
        rec,
        "esc_alp2",
        (xb - 2.0, yp - 1.25, 0.02),
        (xb - 2.0, yp + 0.02, 0.62),
        1.6,
        mats,
        corrimao=False,
    )
    for k, x in enumerate((xa + 4.6, xa + 7.0)):
        V.sacos(
            rec,
            f"sacos_p{k}",
            [(x, yp + 1.1, 7), (x + 0.56, yp + 1.12, -10), (x + 0.28, yp + 1.5, 84)],
            mats,
            z=0.62,
        )
        rec.caixa(f"sacos_p{k}", (x + 0.3, yp + 1.3, 0.88), (1.35, 1.05, 0.52), "para", "Fabric")
    VC.camera(rec, (-12.4, -3.8, PISO + 1.7), (6.0, 2.5, PISO + 1.6))
    return rec


# =============================================================== Vila dos Esteios
def receita_ret_esteio_comunal():
    rec = V.Receita()
    sem = 661
    mats = Mats(sem)
    L, W, Z = 15.0, 9.6, 0.62
    H = Z + 2.85
    ngoi = _ngoi("#8e5238", "#663a28", "#a76a4c")
    E.piso_tabuas(rec, "piso", -L / 2, -W / 2, L / 2, W / 2, Z, mats)
    E.barrotes(rec, "barrote", -L / 2, -W / 2, L / 2, W / 2, Z, mats)
    nx, ny = 5, 3
    pontos = [
        (-L / 2 + i * L / nx, -W / 2 + j * W / ny) for i in range(nx + 1) for j in range(ny + 1)
    ]
    E.pilotis(rec, "esteio", pontos, Z - 0.14, mats, r=0.13)
    externos = [p for p in pontos if abs(abs(p[0]) - L / 2) < 0.01 or abs(abs(p[1]) - W / 2) < 0.01]
    for k, (x, y) in enumerate(externos):
        rec.add(V.tre(f"col{k}", (x, y, Z), (x, y, H), 0.115, mats.go, segs=8), "Casa", "Estrutura")
        rec.caixa(f"col{k}", (x, y, (Z + H) / 2), (0.23, 0.23, H - Z), "para", "Wood")
    for s in (-1, 1):
        rec.add(
            V.viga(
                f"fre_x{s}",
                (-L / 2 - 0.1, s * W / 2, H),
                (L / 2 + 0.1, s * W / 2, H),
                0.14,
                0.17,
                mats.go,
            ),
            "Casa",
            "Estrutura",
        )
        rec.add(
            V.viga(
                f"fre_y{s}",
                (s * L / 2, -W / 2 - 0.1, H),
                (s * L / 2, W / 2 + 0.1, H),
                0.14,
                0.17,
                mats.go,
            ),
            "Casa",
            "Estrutura",
        )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        H + 3.0,
        1.0,
        "4aguas",
        "ngoi",
        0.1,
        ngoi,
        mats,
        beiral_oitao=1.0,
        sem=sem,
        tesouras=(-L / 8, L / 8),
    )
    meio = 1.0
    E.guarda_corpo(rec, "g_f_a", (-L / 2, -W / 2), (-meio, -W / 2), Z, mats, alt=0.78, passo=1.2)
    E.guarda_corpo(rec, "g_f_b", (meio, -W / 2), (L / 2, -W / 2), Z, mats, alt=0.78, passo=1.2)
    E.guarda_corpo(
        rec, "g_t_a", (-L / 2, W / 2), (L / 2 - 3.2, W / 2), Z, mats, alt=0.78, passo=1.2
    )
    E.guarda_corpo(rec, "g_e", (-L / 2, -W / 2), (-L / 2, W / 2), Z, mats, alt=0.78, passo=1.2)
    E.guarda_corpo(rec, "g_d_a", (L / 2, -W / 2), (L / 2, -meio), Z, mats, alt=0.78, passo=1.2)
    E.guarda_corpo(rec, "g_d_b", (L / 2, meio), (L / 2, W / 2), Z, mats, alt=0.78, passo=1.2)
    E.escada(rec, "esc_f", (0.0, -W / 2 - 1.1, 0.02), (0.0, -W / 2 + 0.02, Z), 1.7, mats)
    E.escada(rec, "esc_d", (L / 2 + 1.1, 0.0, 0.02), (L / 2 - 0.02, 0.0, Z), 1.7, mats)
    E.escada(
        rec, "esc_t", (L / 2 - 1.6, W / 2 + 1.1, 0.02), (L / 2 - 1.6, W / 2 - 0.02, Z), 1.7, mats
    )
    for k, x in enumerate((-4.6, 4.2)):
        # a mesa do kit nasce no piso térreo: sobe até o piso de tábuas
        marca = rec.marca()
        V.ban_thap(rec, f"mesa{k}", (x, 0.2), 0, mats, comp=2.2, larg=0.95, alt=0.76, banquinhos=0)
        rec.transformar(marca, V.lugar((0.0, 0.0, Z - PISO)))
        X._banco(rec, f"banco_a{k}", (x, -0.72), 0, mats, comp=2.1, z=Z)
        X._banco(rec, f"banco_b{k}", (x, 1.12), 0, mats, comp=2.1, z=Z)
    X._banco(rec, "banco_lat", (-L / 2 + 0.45, 2.4), 90, mats, comp=2.6, z=Z)
    X._pote(rec, "pote_a", (-L / 2 + 0.6, -W / 2 + 0.6), mats, alt=0.7, r=0.3, z=Z, sem=sem)
    X._cesto(rec, "cesto_a", (L / 2 - 0.65, W / 2 - 0.6), mats, r=0.3, alt=0.46, z=Z)
    VC.camera(rec, (-6.4, -3.9, Z + 1.6), (4.6, 2.8, Z + 0.9))
    return rec


CASAS: dict[str, dict] = {
    "ret_merc_fachadas": {
        "nome": "lojas estreitas da margem",
        "tipo": "três fachadas de alturas e telhados diferentes, com porta na frente e nos fundos",
        "fontes": [],
        "atlas": ATLAS_G,
    },
    "ret_merc_cais": {
        "nome": "cais de pedra",
        "tipo": "muro de pedra até o fundo do rio, deck, escada para a água e dois barcos",
        "fontes": [],
        "atlas": ATLAS_M,
    },
    "ret_olaria_fornos": {
        "nome": "fornos da olaria",
        "tipo": "dois fornos de tijolo em cúpula, com boca gradeada, lenha e pilhas",
        "fontes": [],
        "atlas": ATLAS_M,
    },
    "ret_olaria_galpao": {
        "nome": "galpão de moldagem",
        "tipo": "galpão aberto, bancadas, moldes, prateleiras de potes e tijolos",
        "fontes": [],
        "atlas": ATLAS_M,
    },
    "ret_olaria_secagem": {
        "nome": "pátio de secagem",
        "tipo": "fileiras de tijolo secando, tanque de barro e carroça",
        "fontes": [],
        "atlas": ATLAS_P,
    },
    "ret_olaria_cobertura": {
        "nome": "cobertura de secagem",
        "tipo": "esteira sobre postes, estante de potes, lenha e mureta de tijolo",
        "fontes": [],
        "atlas": ATLAS_P,
    },
    "ret_olaria_pilhas": {
        "nome": "pilhas de tijolo",
        "tipo": "tijolo queimado e cru empilhado na altura da cintura",
        "fontes": [],
        "atlas": ATLAS_P,
    },
    "ret_escola_principal": {
        "nome": "ala principal da escola",
        "tipo": "três salas ligadas por dentro, varanda de pilares, lousas e carteiras",
        "fontes": [],
        "atlas": ATLAS_G,
    },
    "ret_escola_ala": {
        "nome": "ala lateral da escola",
        "tipo": "duas salas ligadas por dentro, varanda de pilares, lousas e carteiras",
        "fontes": [],
        "atlas": ATLAS_G,
    },
    "ret_engenho_galpao": {
        "nome": "galpão do engenho",
        "tipo": "salão de treliças, tremonhas, sacaria, passarela e plataforma de carga",
        "fontes": [],
        "atlas": ATLAS_G,
    },
    "ret_esteio_comunal": {
        "nome": "casa comunal",
        "tipo": "piso elevado, cobertura de quatro águas, três escadas, mesas e bancos",
        "fontes": [],
        "atlas": ATLAS_M,
    },
}
