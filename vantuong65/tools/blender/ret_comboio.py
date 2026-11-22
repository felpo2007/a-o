"""Marcos da Estrada do Bambu (D-251, prompt 18.4). Metros, Z para cima, frente em -Y.

- Arrozais das Comportas: `ret_comp_bomba` (bomba, canaleta e comporta) e `ret_comp_celeiro`;
- Vila do Sino Baixo: `ret_sino_salao` (salão com sineira) e `ret_sino_loja_a/b` (varandas fundas);
- Ponte do Canal Torto: `ret_canal_ponte` (só arte; colide no MapaPontes) e `ret_canal_oficina`;
- Serraria: `ret_serra_galpao`, `ret_serra_portico`, `ret_serra_toras` e `ret_serra_secagem`;
- Engenho do Espigão: `ret_esp_armazem` e `ret_esp_chamine`.

Janelas sem grade (pedido do dono, D-246): estilo "aberta".
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
import ret_frente as RF  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

PONTE_L, PONTE_W, PONTE_Z = 33.2, 9.0, 3.4  # comprimento, largura e altura do deck no modelo


# =============================================================== peças
def _jan(lado, ts, w=1.2, z0=1.05, z1=2.1):
    return [{"lado": lado, "t": t, "w": w, "z0": z0, "z1": z1, "estilo": "aberta"} for t in ts]


def _est(rec, obj):
    return rec.add(obj, "Casa", "Estrutura")


def _mob(rec, obj):
    return rec.add(obj, "Mobilia", "Mobilia")


def _mat_tora():
    return V.mat_go("tora", "#7a5c3e", "#46331f", "#6d6455", gasto=0.7, rug=0.92)


def _mat_serrada():
    return V.mat_tabua("serrada", "#c29a66", "#94703f", "#a89a7c", largura=0.2, gasto=0.3)


def _tesouras(rec, nome, L, W, H, hr, n, mats, esp=0.2):
    """Tesouras de madeira aparentes: linha, pernas, pendural e diagonais."""
    for k in range(1, n):
        x = -L / 2 + k * L / n
        yi = W / 2 - esp
        _est(rec, V.viga(f"{nome}_l{k}", (x, -yi, H), (x, yi, H), 0.16, 0.2, mats.go_escuro))
        _est(rec, V.viga(f"{nome}_r{k}", (x, 0, H), (x, 0, hr - 0.16), 0.1, 0.1, mats.go))
        for s in (-1, 1):
            _est(
                rec,
                V.viga(
                    f"{nome}_p{k}{s}", (x, s * yi, H), (x, 0, hr - 0.14), 0.15, 0.19, mats.go_escuro
                ),
            )
            _est(
                rec,
                V.viga(
                    f"{nome}_d{k}{s}",
                    (x, 0, H + 0.04),
                    (x, s * W / 4, (H + hr) / 2 - 0.08),
                    0.08,
                    0.09,
                    mats.go,
                ),
            )


def _volante(rec, nome, c, r, mats, eixo="Y"):
    aro = M.toro(f"{nome}_aro", r, 0.03, 18, 5)
    V.gravar_uv_local(aro, lambda p: (p.x, p.y, p.z))
    M.material(aro, mats.ferro)
    rot = Matrix.Rotation(math.pi / 2, 4, "X" if eixo == "Y" else "Y")
    M.mover(aro, Matrix.Translation(c) @ rot)
    _mob(rec, M.suave(aro, 45))
    for j in range(3):
        a = j * math.pi / 3
        dx, dz = math.cos(a) * r, math.sin(a) * r
        if eixo == "Y":
            p0, p1 = (c[0] - dx, c[1], c[2] - dz), (c[0] + dx, c[1], c[2] + dz)
        else:
            p0, p1 = (c[0], c[1] - dx, c[2] - dz), (c[0], c[1] + dx, c[2] + dz)
        _mob(rec, V.tre(f"{nome}_raio{j}", p0, p1, 0.016, mats.ferro, segs=4))


def _toras(rec, nome, x, y, comp, base, r, mat, z=0.0, ang=0.0, sem=0.0):
    """Pilha triangular de toras ao longo de X, com pontas desencontradas."""
    ca, sa = math.cos(ang), math.sin(ang)
    k = 0
    for fila in range(base):
        n = base - fila
        for i in range(n):
            v = (i - (n - 1) / 2) * r * 2.02
            h = z + r + fila * r * 1.74
            d = ((k * 37 + int(sem * 10)) % 7 - 3) * 0.05
            ax, bx = -comp / 2 + d, comp / 2 + d
            raio = r * (0.9 + ((k * 13) % 5) * 0.04)
            p0 = (x + ax * ca - v * sa, y + ax * sa + v * ca, h)
            p1 = (x + bx * ca - v * sa, y + bx * sa + v * ca, h)
            _mob(rec, V.tre(f"{nome}_{k}", p0, p1, raio, mat, segs=7, sem=sem + k * 0.31))
            k += 1
    larg = base * r * 2.02
    alto = 2 * r + (base - 1) * r * 1.74
    rec.caixa(nome, (x, y, z + alto / 2), (comp, larg, alto), "para", "Wood", rot_z=ang)


def _tabuas(rec, nome, cx, cy, z, comp, larg, camadas, mat, mats, ang=0.0):
    """Pilha de madeira serrada em secagem: camadas separadas por sarrafos."""
    ca, sa = math.cos(ang), math.sin(ang)
    esp = 0.05
    h = z
    for c in range(camadas):
        n = max(2, int(larg / 0.24))
        for i in range(n):
            v = -larg / 2 + (i + 0.5) * larg / n
            _mob(
                rec,
                V.bloco(
                    f"{nome}_t{c}{i}",
                    (comp, larg / n - 0.025, esp),
                    (cx - v * sa, cy + v * ca, h + esp / 2),
                    mat,
                    rot=(0.0, 0.0, ang),
                ),
            )
        h += esp
        for u in (-comp / 2 + 0.2, 0.0, comp / 2 - 0.2):
            _mob(
                rec,
                V.bloco(
                    f"{nome}_s{c}{int(u * 10)}",
                    (0.05, larg, 0.04),
                    (cx + u * ca, cy + u * sa, h + 0.02),
                    mats.go_escuro,
                    rot=(0.0, 0.0, ang),
                ),
            )
        h += 0.04
    rec.caixa(nome, (cx, cy, (z + h) / 2), (comp, larg, h - z), "para", "Wood", rot_z=ang)
    return h


def _barril(rec, nome, x, y, mats, z=0.0, r=0.3, alt=0.9):
    o = V.torno_local(
        f"{nome}_b",
        [
            (0.0, 0.0),
            (r * 0.86, 0.0),
            (r, alt * 0.5),
            (r * 0.86, alt),
            (r * 0.78, alt - 0.02),
            (0.0, alt - 0.04),
        ],
        10,
        mats.ferro,
    )
    M.mover(o, Matrix.Translation((x, y, z)))
    _mob(rec, o)
    rec.caixa(nome, (x, y, z + alt / 2), (2 * r, 2 * r, alt), "para", "Metal")


def _trilho(rec, nome, x0, x1, y, mats, z=PISO):
    for s in (-0.42, 0.42):
        _mob(
            rec,
            V.bloco(
                f"{nome}_r{int(s * 100)}",
                (x1 - x0, 0.07, 0.07),
                ((x0 + x1) / 2, y + s, z + 0.1),
                mats.ferro,
            ),
        )
    n = int((x1 - x0) / 0.7)
    for k in range(n + 1):
        x = x0 + k * (x1 - x0) / max(n, 1)
        _mob(rec, V.bloco(f"{nome}_d{k}", (0.16, 1.2, 0.07), (x, y, z + 0.035), mats.go_escuro))


def _serra(rec, nome, x, y, mats, z=PISO):
    """Bancada de serra circular com volante e correia."""
    rec.add(
        V.bloco(f"{nome}_mesa", (3.2, 1.1, 0.12), (x, y, z + 0.92), mats.go, chanfro=0.012),
        "Mobilia",
        "Mobilia",
    )
    for sx in (-1, 1):
        for sy in (-1, 1):
            _mob(
                rec,
                V.bloco(
                    f"{nome}_p{sx}{sy}",
                    (0.14, 0.14, 0.88),
                    (x + sx * 1.42, y + sy * 0.42, z + 0.44),
                    mats.go_escuro,
                ),
            )
    aco = V.mat_liso("aco_serra", "#8d8a82", "#5c5448", rug=0.34, escala=9.0, forca=0.3)
    disco = V.cilindro(f"{nome}_disco", 0.62, 0.012, (0, 0, 0), aco, segs=24)
    M.mover(disco, Matrix.Translation((x, y, z + 1.08)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    _mob(rec, disco)
    _mob(rec, V.bloco(f"{nome}_cap", (0.5, 0.2, 0.14), (x, y, z + 1.72), mats.ferro))
    _volante(rec, f"{nome}_vol", (x + 1.9, y + 0.62, z + 0.72), 0.46, mats, "Y")
    _mob(
        rec,
        V.tre(
            f"{nome}_cor",
            (x + 0.1, y + 0.56, z + 0.98),
            (x + 1.9, y + 0.62, z + 1.18),
            0.02,
            mats.pano_escuro,
        ),
    )
    _mob(
        rec,
        V.tre(
            f"{nome}_cor2",
            (x + 0.1, y + 0.56, z + 0.82),
            (x + 1.9, y + 0.62, z + 0.26),
            0.02,
            mats.pano_escuro,
        ),
    )
    rec.caixa(nome, (x + 0.3, y, z + 0.6), (3.9, 1.3, 1.2), "para", "Wood")


# =============================================================== Arrozais das Comportas
def receita_ret_comp_bomba():
    rec = V.Receita()
    sem = 711
    mats = Mats(sem)
    L, W, H, esp = 6.6, 4.8, 3.0, 0.18
    hr = H + 1.5
    par = RF._reboco("reb_bomba", "#cdbf9e", 0.42)
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
            {"lado": "frente", "t": -1.5, "estilo": "tabua", "folha": 1},
            {"lado": "fundo", "t": 1.6, "estilo": "tabua", "folha": -1},
        ],
        _jan("frente", (1.5,)) + _jan("esq", (0.0,)) + _jan("dir", (0.0,)) + _jan("fundo", (-1.5,)),
        col="Concrete",
        sem=sem,
    )
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, V.mat_tabua("van"))
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.62, mats, sem=sem, ferrugem=0.95)
    # a bomba: corpo, volante e o cano que sai pela parede até a canaleta
    aco = V.mat_liso("aco_bomba", "#54584f", "#3c3a33", rug=0.55, escala=6.0, forca=0.35)
    _mob(
        rec, V.bloco("b_base", (2.2, 1.1, 0.34), (0.6, 0.7, PISO + 0.17), mats.pedra, chanfro=0.02)
    )
    corpo = V.cilindro("b_corpo", 0.38, 1.3, (0, 0, 0), aco, segs=14)
    M.mover(
        corpo, Matrix.Translation((0.6, 0.7, PISO + 0.82)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    )
    _mob(rec, corpo)
    _volante(rec, "b_vol", (1.6, 0.7, PISO + 0.86), 0.5, mats, "X")
    _mob(
        rec,
        V.tre(
            "b_cano", (0.2, 0.7, PISO + 0.82), (0.2, -W / 2 - 2.9, PISO + 0.82), 0.1, aco, segs=8
        ),
    )
    rec.caixa("bomba", (0.8, 0.7, PISO + 0.6), (2.5, 1.2, 1.2), "para", "Metal")
    X._prateleira(rec, "est", (-2.0, W / 2 - esp - 0.26), 0, mats, comp=1.6, z=PISO)
    X._caixote(rec, "cx", (-2.5, 1.2), 12, mats, z=PISO)
    _barril(rec, "barril", 2.6, -1.6, mats, PISO)
    # a canaleta de pedra na frente, com a comporta de tábuas e o volante de manobra
    yc = -W / 2 - 2.9
    for s in (-1, 1):
        rec.add(
            V.bloco(
                f"can_m{s}",
                (L + 1.0, 0.34, 0.62),
                (0.0, yc + s * 0.78, 0.31),
                mats.pedra,
                chanfro=0.02,
            ),
            "Casa",
            "Paredes",
        )
        rec.caixa(
            f"can_m{s}", (0.0, yc + s * 0.78, 0.31), (L + 1.0, 0.34, 0.62), "para", "Concrete"
        )
    _est(rec, V.bloco("can_fundo", (L + 1.0, 1.3, 0.1), (0.0, yc, 0.05), mats.dat))
    agua = V.mat_liso("agua_can", "#39504a", "#22332f", rug=0.08, escala=4.0, forca=0.2)
    _est(rec, V.bloco("can_agua", (L + 0.9, 1.24, 0.03), (0.0, yc, 0.34), agua))
    xc = 1.6
    for s in (-1, 1):
        V.poste(rec, f"com_p{s}", xc, yc + s * 0.98, 2.3, mats.go_escuro, r=0.12)
    _est(
        rec, V.viga("com_v", (xc, yc - 1.12, 2.3), (xc, yc + 1.12, 2.3), 0.18, 0.2, mats.go_escuro)
    )
    _est(rec, V.bloco("com_tab", (0.1, 1.3, 0.9), (xc, yc, 0.76), V.mat_tabua("com")))
    _mob(rec, V.tre("com_fuso", (xc, yc, 1.2), (xc, yc, 2.75), 0.035, mats.ferro, segs=6))
    _volante(rec, "com_vol", (xc, yc, 2.62), 0.34, mats, "Y")
    E.piso_tabuas(rec, "deck", -L / 2, yc + 0.98, xc - 0.5, -W / 2, 0.66, mats)
    rec.caixa(
        "deck_b",
        ((-L / 2 + xc - 0.5) / 2, (yc + 0.98 - W / 2) / 2, 0.3),
        (xc - 0.5 + L / 2, -W / 2 - yc - 0.98, 0.6),
        "para",
        "Wood",
    )
    E.escada(
        rec,
        "deck_e",
        (-L / 2 - 1.1, (yc + 0.98 - W / 2) / 2, 0.02),
        (-L / 2 + 0.02, (yc + 0.98 - W / 2) / 2, 0.66),
        1.2,
        mats,
        corrimao=False,
    )
    E.guarda_corpo(
        rec, "deck_g", (-L / 2 + 0.2, yc + 1.0), (xc - 0.55, yc + 1.0), 0.66, mats, passo=0.9
    )
    VC.camera(rec, (-6.5, -9.2, 2.3), (0.4, -1.0, 1.4))
    return rec


def receita_ret_comp_celeiro():
    rec = V.Receita()
    sem = 712
    mats = Mats(sem)
    L, W, H, esp = 11.0, 6.4, 3.0, 0.08
    hr = H + 2.1
    van = V.mat_tabua("van_cel", "#8d7253", "#5a4630", "#8a8273")
    # atravessa de lado a lado: entra pela estrada e sai no dique
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        van,
        [
            {"lado": "frente", "t": -1.6, "estilo": "folhas"},
            {"lado": "fundo", "t": 1.6, "estilo": "folhas"},
            {"lado": "dir", "t": 0.0, "estilo": "tabua", "folha": 1},
        ],
        _jan("frente", (2.6,), 1.1) + _jan("fundo", (-3.0,), 1.1) + _jan("esq", (0.0,), 1.1),
        col="Wood",
        sem=sem,
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        hr,
        0.75,
        "2aguas",
        "tranh",
        0.14,
        V.mat_tranh("tranh_cel"),
        mats,
        beiral_oitao=0.5,
        sem=sem,
        tesouras=(-L / 4, 0.0, L / 4),
        mat_oitao=van,
        oitao_esp=0.08,
        col_oitao="Wood",
    )
    yi = W / 2 - esp
    for k, x in enumerate((-4.4, -3.2, 3.4, 4.4)):
        V.sacos(
            rec,
            f"sa{k}",
            [(x, yi - 0.6, 6), (x + 0.5, yi - 0.58, -8), (x + 0.2, yi - 1.0, 84)],
            mats,
            z=PISO + 0.02,
        )
        V.sacos(rec, f"sb{k}", [(x + 0.16, yi - 0.66, 14)], mats, z=PISO + 0.28)
        rec.caixa(f"sa{k}", (x + 0.25, yi - 0.8, PISO + 0.3), (1.2, 1.05, 0.6), "para", "Fabric")
    V.bo_lua(rec, "bolua", (-4.0, -1.9), mats)
    X._cesto(rec, "ce_a", (3.9, -2.2), mats, r=0.36, alt=0.5, z=PISO)
    X._cesto(rec, "ce_b", (4.5, -1.7), mats, r=0.3, alt=0.42, z=PISO)
    X._bancada(rec, "banc", (-0.2, yi - 0.42), 0, mats, comp=2.2)
    V.ferramentas(rec, "ferr", (-2.1, -W / 2 + esp + 0.08), 0, mats)
    VC.camera(rec, (-4.9, -2.6, PISO + 1.6), (3.8, 2.0, PISO + 1.0))
    return rec


# =============================================================== Vila do Sino Baixo
def _sino(rec, x, y, mats):
    """Sineira de madeira, com escala de sino de vila (0,7 m de boca)."""
    ALT = 4.4
    for sx in (-1, 1):
        for sy in (-1, 1):
            V.poste(
                rec,
                f"sin_p{sx}{sy}",
                x + sx * 0.82,
                y + sy * 0.82,
                ALT,
                mats.go_escuro,
                r=0.11,
                base_pedra=mats.pedra,
            )
    for z in (1.5, 3.0):
        for s in (-1, 1):
            _est(
                rec,
                V.viga(
                    f"sin_x{int(z)}{s}",
                    (x - 0.9, y + s * 0.82, z),
                    (x + 0.9, y + s * 0.82, z),
                    0.09,
                    0.11,
                    mats.go,
                ),
            )
            _est(
                rec,
                V.viga(
                    f"sin_y{int(z)}{s}",
                    (x + s * 0.82, y - 0.9, z),
                    (x + s * 0.82, y + 0.9, z),
                    0.09,
                    0.11,
                    mats.go,
                ),
            )
    for s in (-1, 1):
        _est(
            rec,
            V.viga(
                f"sin_d{s}",
                (x + s * 0.82, y - 0.82, 1.5),
                (x + s * 0.82, y + 0.82, 3.0),
                0.07,
                0.08,
                mats.go,
            ),
        )
    _est(
        rec,
        V.viga(
            "sin_eixo",
            (x - 0.95, y, ALT - 0.2),
            (x + 0.95, y, ALT - 0.2),
            0.14,
            0.16,
            mats.go_escuro,
        ),
    )
    bronze = V.mat_liso("bronze_sino", "#6b5a32", "#3f4f42", rug=0.42, escala=5.0, forca=0.45)
    sino = V.torno_local(
        "sin_sino",
        [
            (0.36, 0.0),
            (0.38, 0.03),
            (0.3, 0.14),
            (0.22, 0.34),
            (0.19, 0.52),
            (0.12, 0.62),
            (0.0, 0.66),
            (0.0, 0.6),
            (0.1, 0.55),
            (0.16, 0.48),
            (0.2, 0.3),
            (0.28, 0.12),
            (0.33, 0.0),
        ],
        16,
        bronze,
    )
    M.mover(sino, Matrix.Translation((x, y, ALT - 0.95)))
    _mob(rec, sino)
    _mob(rec, V.tre("sin_bad", (x, y, ALT - 0.4), (x, y, ALT - 1.02), 0.022, mats.ferro, segs=5))
    _mob(
        rec,
        V.tre(
            "sin_corda",
            (x, y + 0.02, ALT - 1.02),
            (x + 0.4, y - 0.55, 1.1),
            0.012,
            mats.corda,
            segs=4,
        ),
    )
    marca = rec.marca()
    V.telhado(
        rec,
        "sin_tel",
        2.0,
        2.0,
        ALT,
        ALT + 1.05,
        0.34,
        "4aguas",
        "ngoi",
        0.08,
        RF._ngoi("#8a4f36", "#603725", "#a4674a"),
        mats,
        beiral_oitao=0.34,
        sem=733,
        estrutura=False,
    )
    rec.transformar(marca, V.lugar((x, y, 0.0)))


def receita_ret_sino_salao():
    rec = V.Receita()
    sem = 721
    mats = Mats(sem)
    L, W, H, esp = 15.0, 8.6, 3.5, 0.18
    hr = H + 2.9
    par = RF._reboco("reb_salao", "#dfd5ba", 0.3)
    # frente toda aberta em colunas; fundo e empenas fechados, com porta para o pátio lateral
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
            {"lado": "fundo", "t": -3.6, "estilo": "folhas"},
            {"lado": "dir", "t": 0.0, "estilo": "folhas"},
            {"lado": "esq", "t": 1.2, "estilo": "tabua", "folha": 1},
        ],
        _jan("fundo", (0.0, 3.6, 6.0), 1.5, 1.1, 2.5) + _jan("esq", (-1.8,), 1.3, 1.1, 2.4),
        col="Concrete",
        sem=sem,
        lados_usar=("fundo", "esq", "dir"),
    )
    n = 6
    for k in range(n + 1):
        x = -L / 2 + 0.12 + k * (L - 0.24) / n
        V.poste(rec, f"col{k}", x, -W / 2 + 0.12, H, mats.go_escuro, r=0.14, base_pedra=mats.pedra)
    _est(
        rec,
        V.viga(
            "frechal", (-L / 2, -W / 2 + 0.12, H), (L / 2, -W / 2 + 0.12, H), 0.17, 0.2, mats.go
        ),
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        hr,
        1.05,
        "4aguas",
        "ngoi",
        0.1,
        RF._ngoi("#90533a", "#673a28", "#ab6c4c"),
        mats,
        beiral_oitao=1.05,
        sem=sem,
        tesouras=(),
    )
    _tesouras(rec, "tes", L, W, H, hr, 6, mats)
    # bancos em fila, a mesa da frente e o altar da vila
    for j, y in enumerate((-2.0, -0.6, 0.8)):
        for s in (-1, 1):
            X._banco(rec, f"bn{j}{s}", (s * 3.0, y), 0, mats, comp=3.6, z=PISO)
    V.ban_tho(rec, "altar", (0.0, W / 2 - esp - 0.4), 180, mats, comp=1.8, rico=True)
    V.ban_thap(rec, "mesa", (0.0, 2.2), 0, mats, comp=2.2, larg=0.9, alt=0.76, banquinhos=0)
    X._lanterna(rec, "lan_a", (-4.0, -W / 2 + 0.16, H - 0.25), mats)
    X._lanterna(rec, "lan_b", (4.0, -W / 2 + 0.16, H - 0.25), mats)
    X._pote(rec, "pote_a", (-L / 2 + 0.7, W / 2 - 0.7), mats, alt=0.7, r=0.3, z=PISO, sem=sem)
    _sino(rec, L / 2 + 2.3, -W / 2 + 1.1, mats)
    VC.camera(rec, (-6.8, -7.8, 1.9), (3.6, 2.2, 2.0))
    return rec


def _loja_varanda(sem, cal, telha, vira=1):
    rec = V.Receita()
    mats = Mats(sem)
    L, W, H, esp, V_P = 9.4, 5.8, 3.1, 0.16, 2.5
    hr = H + 1.9
    par = RF._reboco(f"reb_loja{sem}", cal, 0.32)
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
            {"lado": "frente", "t": -vira * 2.5, "estilo": "folhas"},
            {"lado": "fundo", "t": vira * 2.4, "estilo": "tabua", "folha": 1},
        ],
        _jan("frente", (vira * 0.4, vira * 3.0), 1.5, 0.95, 2.25)
        + _jan("fundo", (-vira * 2.2,), 1.1)
        + _jan("esq", (0.0,), 1.1)
        + _jan("dir", (0.8,), 1.1),
        col="Concrete",
        sem=sem,
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        hr,
        0.6,
        "2aguas",
        "ngoi",
        0.1,
        RF._ngoi(*telha),
        mats,
        beiral_oitao=0.32,
        sem=sem,
        tesouras=(0.0,),
        mat_oitao=par,
        oitao_esp=esp,
        col_oitao="Earth",
    )
    # a varanda funda da rua
    yv = -W / 2 - V_P
    E.piso_tabuas(rec, "piso_v", -L / 2, yv, L / 2, -W / 2, 0.34, mats)
    rec.caixa("piso_vb", (0.0, (yv - W / 2) / 2, 0.15), (L, V_P, 0.3), "para", "Wood")
    for k in range(5):
        x = -L / 2 + 0.12 + k * (L - 0.24) / 4
        V.poste(rec, f"var{k}", x, yv + 0.12, 2.75, mats.go, r=0.1, base_pedra=mats.pedra)
    _est(
        rec,
        V.viga("var_fre", (-L / 2, yv + 0.12, 2.75), (L / 2, yv + 0.12, 2.75), 0.13, 0.16, mats.go),
    )
    E.telhado_varanda(
        rec,
        "tel_v",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        -W / 2 + 0.02,
        H + 0.02,
        yv - 0.5,
        2.62,
        mats,
        sem,
        ferrugem=0.85,
    )
    E.escada(
        rec,
        "esc_v",
        (-vira * 2.5, yv - 0.8, 0.02),
        (-vira * 2.5, yv + 0.02, 0.34),
        1.8,
        mats,
        corrimao=False,
    )
    # o que a loja vende, na varanda e no balcão
    X._banco(rec, "banco_v", (vira * 3.0, -W / 2 - 0.42), 0, mats, comp=2.0, z=0.34)
    X._cesto(rec, "ce_v", (vira * 0.2, yv + 0.65), mats, r=0.3, alt=0.42, z=0.34)
    X._pote(rec, "pote_v", (vira * 1.0, yv + 0.55), mats, alt=0.62, r=0.26, z=0.34, sem=sem)
    X._caixote(rec, "cx_v", (-vira * 4.0, -W / 2 - 0.5), 8, mats, z=0.34)
    X._bancada(rec, "balcao", (vira * 0.9, -0.9), 0, mats, comp=3.2)
    X._prateleira(rec, "est_a", (vira * 1.0, W / 2 - esp - 0.26), 0, mats, comp=2.4, z=PISO)
    V.phan(rec, "phan", (-vira * 3.0, 1.3), 90, mats)
    V.ban_thap(rec, "mesa", (-vira * 2.8, -1.1), 0, mats)
    X._pote(rec, "pote_i", (vira * 4.0, W / 2 - 0.6), mats, alt=0.7, r=0.3, z=PISO, sem=sem + 1)
    VC.camera(rec, (-vira * 5.8, -8.6, 2.1), (vira * 0.6, -1.2, 1.5))
    return rec


def receita_ret_sino_loja_a():
    return _loja_varanda(722, "#d8c070", ("#8e5238", "#663a28", "#a76a4c"), 1)


def receita_ret_sino_loja_b():
    return _loja_varanda(723, "#b9c6ac", ("#7f4a34", "#5b3424", "#9a6246"), -1)


# =============================================================== Ponte do Canal Torto
def receita_ret_canal_ponte():
    """Só a arte: quem segura o comboio é o tabuleiro do MapaPontes, na altura do deck."""
    rec = V.Receita()
    sem = 731
    mats = Mats(sem)
    L, Z = PONTE_L, PONTE_Z
    yr = 4.12  # as treliças ficam por fora da faixa de 8 m do tabuleiro
    tab = V.mat_tabua("deck_ponte", "#7c6448", "#4f3d2b", "#77705f", largura=0.3, gasto=0.75)
    n = int(L / 0.32)
    for k in range(n):
        x = -L / 2 + (k + 0.5) * L / n
        d = ((k * 7) % 5 - 2) * 0.03
        rec.add(
            V.bloco(f"pr{k}", (L / n - 0.018, 8.5 + d, 0.08), (x, d / 2, Z - 0.04), tab),
            "Casa",
            "Piso",
        )
    for j, y in enumerate((-3.4, -1.7, 0.0, 1.7, 3.4)):
        _est(
            rec,
            V.viga(
                f"long{j}", (-L / 2, y, Z - 0.2), (L / 2, y, Z - 0.2), 0.24, 0.26, mats.go_escuro
            ),
        )
    # cavaletes: quatro no leito e um encontro de pedra em cada margem
    xs = (-9.6, -3.2, 3.2, 9.6)
    for i, x in enumerate(xs):
        for y in (-3.6, -1.2, 1.2, 3.6):
            _est(
                rec,
                V.tre(
                    f"cav{i}{int(y * 10)}",
                    (x, y * 1.08, 0.0),
                    (x, y, Z - 0.32),
                    0.17,
                    mats.go_escuro,
                    segs=7,
                    sem=i + y,
                ),
            )
        _est(rec, V.viga(f"cav_t{i}", (x, -4.2, Z - 0.34), (x, 4.2, Z - 0.34), 0.28, 0.26, mats.go))
        _est(rec, V.viga(f"cav_a{i}", (x, -3.9, 0.7), (x, 3.9, Z - 0.5), 0.09, 0.14, mats.go))
        _est(rec, V.viga(f"cav_b{i}", (x, 3.9, 0.7), (x, -3.9, Z - 0.5), 0.09, 0.14, mats.go))
        rec.caixa(f"cav{i}", (x, 0.0, (Z - 0.5) / 2), (0.5, 8.4, Z - 0.5), "para", "Wood")
    for s in (-1, 1):
        x = s * (L / 2 - 1.5)
        rec.add(
            V.bloco(
                f"enc{s}", (3.0, 9.2, Z - 0.1), (x, 0.0, (Z - 0.1) / 2), mats.pedra, chanfro=0.05
            ),
            "Casa",
            "Paredes",
        )
        for y in (-4.5, 4.5):
            _mob(
                rec,
                V.bloco(
                    f"enc_al{s}{int(y)}",
                    (3.4, 0.5, 0.5),
                    (x, y, Z + 0.15),
                    mats.pedra,
                    chanfro=0.04,
                ),
            )
    # as duas treliças laterais, em tramos de 4 m, com cruzes e tirantes de ferro
    nt = 8
    alt = 2.1
    x0 = -nt * 2.0
    for s in (-1, 1):
        y = s * yr
        _est(
            rec,
            V.viga(f"tr_b{s}", (x0, y, Z + 0.12), (-x0, y, Z + 0.12), 0.2, 0.24, mats.go_escuro),
        )
        _est(
            rec,
            V.viga(
                f"tr_t{s}", (x0 + 4, y, Z + alt), (-x0 - 4, y, Z + alt), 0.18, 0.2, mats.go_escuro
            ),
        )
        _est(rec, V.viga(f"tr_i{s}", (x0, y, Z + 0.12), (x0 + 4, y, Z + alt), 0.17, 0.2, mats.go))
        _est(rec, V.viga(f"tr_f{s}", (-x0, y, Z + 0.12), (-x0 - 4, y, Z + alt), 0.17, 0.2, mats.go))
        for k in range(1, nt):
            x = x0 + k * 4.0
            _est(rec, V.viga(f"tr_m{s}{k}", (x, y, Z + 0.12), (x, y, Z + alt), 0.14, 0.17, mats.go))
            if 1 <= k < nt - 1:
                a, b = (x, y, Z + 0.14), (x + 4.0, y, Z + alt - 0.02)
                if k >= nt / 2:
                    a, b = (x + 4.0, y, Z + 0.14), (x, y, Z + alt - 0.02)
                _est(rec, V.viga(f"tr_d{s}{k}", a, b, 0.1, 0.13, mats.go))
                _mob(
                    rec,
                    V.tre(
                        f"tr_tir{s}{k}",
                        (x + 2.0, y, Z + 0.1),
                        (x + 2.0, y, Z + alt),
                        0.02,
                        mats.ferro,
                        segs=4,
                    ),
                )
    VC.camera(rec, (-20.0, -11.0, Z + 2.2), (2.0, 0.0, Z + 0.4))
    return rec


def receita_ret_canal_oficina():
    rec = V.Receita()
    sem = 732
    mats = Mats(sem)
    L, W, H, esp = 13.0, 8.0, 3.8, 0.12
    hr = H + 1.9
    van = V.mat_tabua("van_of", "#75644e", "#4b3d2c", "#7b7567")
    lados = V.lados_ret(0.0, 0.0, L, W, esp)
    # o portão grande de frente para a rua e um segundo vão para o pátio
    extra = {"frente": [(lados["frente"].comp / 2 - 1.6, 4.6, -1.0, 3.4)]}
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        van,
        [
            {"lado": "fundo", "t": 3.2, "estilo": "tabua", "folha": 1},
            {"lado": "dir", "t": 0.5, "estilo": "tabua", "folha": -1},
        ],
        _jan("frente", (4.6,), 1.5, 1.2, 2.5)
        + _jan("fundo", (-3.4, 0.0), 1.6, 1.25, 2.55)
        + _jan("esq", (0.0,), 1.5, 1.2, 2.5),
        col="Wood",
        sem=sem,
        vaos_extra=extra,
    )
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, van)
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.72, mats, sem=sem, ferrugem=0.98, beiral_oitao=0.4)
    _tesouras(rec, "tes", L, W, H, hr, 5, mats, esp)
    # as folhas do portão, abertas e encostadas na parede
    chapa = E.mat_chapa("chapa_of", 0.5)
    for k, xf in enumerate((-4.6, 1.5)):
        _est(rec, V.bloco(f"folha{k}", (2.4, 0.06, 3.3), (xf, -W / 2 - 0.1, 1.68), chapa))
    _est(
        rec,
        V.viga(
            "trilho_port",
            (-5.9, -W / 2 - 0.16, 3.46),
            (2.8, -W / 2 - 0.16, 3.46),
            0.08,
            0.12,
            mats.ferro,
        ),
    )
    yi = W / 2 - esp
    X._bancada(rec, "banc_a", (-3.2, yi - 0.42), 0, mats, comp=3.4)
    X._bancada(rec, "banc_b", (1.6, yi - 0.42), 0, mats, comp=2.4)
    X._prateleira(rec, "est", (-L / 2 + esp + 0.26, 1.8), 90, mats, comp=2.2, z=PISO)
    V.ferramentas(rec, "ferr", (5.2, yi - 0.06), 180, mats)
    # o motor no cavalete e o que sobrou de uma caixa de câmbio
    aco = V.mat_liso("aco_of", "#4f4e47", "#35322c", rug=0.5, escala=6.0, forca=0.4)
    _mob(
        rec,
        V.bloco(
            "mot_cav", (1.6, 0.9, 0.62), (-1.0, 0.5, PISO + 0.31), mats.go_escuro, chanfro=0.015
        ),
    )
    _mob(rec, V.bloco("mot_bl", (1.1, 0.62, 0.62), (-1.0, 0.5, PISO + 0.93), aco, chanfro=0.03))
    _mob(
        rec,
        V.bloco("mot_ca", (0.92, 0.4, 0.18), (-1.0, 0.5, PISO + 1.32), mats.ferro, chanfro=0.015),
    )
    _volante(rec, "mot_vol", (-0.28, 0.5, PISO + 0.93), 0.3, mats, "X")
    rec.caixa("motor", (-1.0, 0.5, PISO + 0.7), (1.7, 1.0, 1.4), "para", "Metal")
    for k, (x, y) in enumerate(((4.9, -2.9), (5.6, -2.3), (5.0, -1.7))):
        _barril(rec, f"bar{k}", x, y, mats, PISO)
    for k, (x, z) in enumerate(((3.2, 0.46), (3.95, 0.46), (3.55, 0.98))):
        pneu = M.toro(f"pneu{k}", 0.34, 0.14, 16, 6)
        V.gravar_uv_local(pneu, lambda p: (p.x, p.y, p.z))
        M.material(pneu, mats.pano_escuro)
        M.mover(pneu, Matrix.Translation((x, 1.5, PISO + z)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        _mob(rec, M.suave(pneu, 45))
    rec.caixa("pneus", (3.55, 1.5, PISO + 0.65), (1.6, 0.42, 1.3), "para", "Rubber")
    VC.camera(rec, (-5.8, -6.5, 2.2), (2.6, 2.3, 1.2))
    return rec


# =============================================================== Serraria
def receita_ret_serra_galpao():
    rec = V.Receita()
    sem = 741
    mats = Mats(sem)
    L, W, H, esp = 21.0, 9.6, 4.3, 0.1
    hr = H + 2.2
    van = V.mat_tabua("van_serra", "#806a4d", "#54422f", "#7f796a")
    tora = _mat_tora()
    serrada = _mat_serrada()
    # fundo de tábuas com dois vãos; frente aberta em pórticos, para se ver a profundidade
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        van,
        [
            {"lado": "fundo", "t": -6.0, "estilo": "tabua", "folha": 1},
            {"lado": "fundo", "t": 6.5, "estilo": "tabua", "folha": -1},
        ],
        _jan("fundo", (-2.5, 2.5), 1.8, 1.4, 2.8),
        col="Wood",
        sem=sem,
        lados_usar=("fundo",),
    )
    for k in range(8):
        x = -L / 2 + 0.14 + k * (L - 0.28) / 7
        V.poste(rec, f"col{k}", x, -W / 2 + 0.14, H, mats.go_escuro, r=0.16, base_pedra=mats.pedra)
        for s in (-1, 1):
            if (k == 0 and s == -1) or (k == 7 and s == 1):
                continue
            xm = x + s * 0.72
            _est(
                rec,
                V.viga(
                    f"mao{k}{s}",
                    (x, -W / 2 + 0.14, H - 0.75),
                    (xm, -W / 2 + 0.14, H - 0.04),
                    0.09,
                    0.11,
                    mats.go,
                ),
            )
    for s in (-1, 1):
        V.poste(
            rec,
            f"cab{s}",
            s * (L / 2 - 0.14),
            0.0,
            H,
            mats.go_escuro,
            r=0.14,
            base_pedra=mats.pedra,
        )
    _est(
        rec,
        V.viga(
            "frechal",
            (-L / 2, -W / 2 + 0.14, H),
            (L / 2, -W / 2 + 0.14, H),
            0.2,
            0.24,
            mats.go_escuro,
        ),
    )
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.9, mats, sem=sem, ferrugem=0.97, beiral_oitao=0.5)
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, van)
    _tesouras(rec, "tes", L, W, H, hr, 7, mats, esp)
    # trilho no eixo do galpão, com a tora no carrinho indo para a serra
    yt = -1.15
    _trilho(rec, "tri", -L / 2 - 0.2, 4.2, yt, mats)
    _serra(rec, "serra", 0.6, yt, mats)
    _mob(rec, V.bloco("car", (3.4, 1.05, 0.14), (-5.0, yt, PISO + 0.46), mats.go, chanfro=0.01))
    for sx in (-1, 1):
        for sy in (-1, 1):
            roda = V.cilindro(f"car_r{sx}{sy}", 0.17, 0.08, (0, 0, 0), mats.ferro, segs=10)
            M.mover(
                roda,
                Matrix.Translation((-5.0 + sx * 1.2, yt + sy * 0.42, PISO + 0.26))
                @ Matrix.Rotation(math.pi / 2, 4, "X"),
            )
            _mob(rec, roda)
    _mob(
        rec,
        V.tre(
            "car_tora",
            (-7.2, yt, PISO + 0.86),
            (-2.0, yt, PISO + 0.86),
            0.33,
            tora,
            segs=9,
            sem=4.0,
        ),
    )
    rec.caixa("carro", (-4.6, yt, PISO + 0.6), (5.2, 1.1, 1.2), "para", "Wood")
    # o que sai da serra: pranchas, pó e refugo
    _tabuas(rec, "ped_a", 5.4, yt, PISO, 3.2, 1.1, 4, serrada, mats)
    po = V.torno_local(
        "po",
        [(0.0, 0.46), (0.5, 0.36), (1.0, 0.14), (1.26, 0.0), (0.0, 0.0)],
        12,
        V.mat_liso("po_serra", "#c9a877", "#9a7c52", rug=0.96, escala=26.0, forca=0.55),
    )
    M.mover(po, Matrix.Translation((1.8, 0.3, PISO)))
    _mob(rec, po)
    yb = W / 2 - esp
    X._bancada(rec, "banc", (-1.0, yb - 0.42), 0, mats, comp=3.2)
    _tabuas(rec, "ped_b", 7.4, yb - 0.9, PISO, 3.6, 1.2, 7, serrada, mats)
    _tabuas(rec, "ped_c", -7.6, yb - 0.9, PISO, 3.4, 1.2, 6, serrada, mats)
    X._prateleira(rec, "est", (3.2, yb - 0.26), 0, mats, comp=2.0, z=PISO)
    VC.camera(rec, (-11.2, -8.8, 2.4), (3.2, 1.2, 1.4))
    return rec


def receita_ret_serra_portico():
    rec = V.Receita()
    sem = 742
    mats = Mats(sem)
    tora = _mat_tora()
    S, Y, ALT = 5.2, 1.7, 6.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            _est(
                rec,
                V.viga(
                    f"per{sx}{sy}",
                    (sx * S, sy * Y, 0.0),
                    (sx * S, sy * 0.22, ALT - 0.2),
                    0.24,
                    0.26,
                    mats.go_escuro,
                ),
            )
            rec.caixa(
                f"per{sx}{sy}",
                (sx * S, sy * (Y + 0.22) / 2, (ALT - 0.2) / 2),
                (0.34, Y - 0.1, ALT - 0.2),
                "para",
                "Wood",
            )
        for z, y in ((2.1, 1.14), (4.2, 0.62)):
            _est(
                rec,
                V.viga(f"trav{sx}{int(z)}", (sx * S, -y, z), (sx * S, y, z), 0.14, 0.16, mats.go),
            )
        _est(
            rec,
            V.bloco(f"sapata{sx}", (0.7, 2 * Y + 0.8, 0.22), (sx * S, 0.0, 0.11), mats.go_escuro),
        )
    _est(rec, V.viga("viga", (-S - 0.5, 0.0, ALT), (S + 0.5, 0.0, ALT), 0.34, 0.42, mats.go_escuro))
    for sx in (-1, 1):
        _est(
            rec,
            V.viga(
                f"mao{sx}",
                (sx * S, 0.0, ALT - 1.5),
                (sx * (S - 1.6), 0.0, ALT - 0.2),
                0.14,
                0.17,
                mats.go,
            ),
        )
    # a talha com a tora suspensa
    xt = 1.1
    _mob(rec, V.bloco("tal_car", (0.5, 0.44, 0.2), (xt, 0.0, ALT - 0.31), mats.ferro))
    _volante(rec, "tal_vol", (xt, 0.0, ALT - 0.74), 0.2, mats, "Y")
    for s in (-1, 1):
        _mob(
            rec,
            V.tre(
                f"tal_c{s}",
                (xt, 0.0, ALT - 0.8),
                (xt + s * 0.95, 0.0, 2.72),
                0.016,
                mats.ferro,
                segs=4,
            ),
        )
    _mob(
        rec,
        V.tre("tal_tora", (xt - 2.3, 0.0, 2.6), (xt + 2.3, 0.0, 2.6), 0.31, tora, segs=9, sem=2.0),
    )
    _toras(rec, "pilha_a", -2.6, 0.0, 4.2, 3, 0.25, tora, sem=1.0)
    _trilho(rec, "tri", -S + 0.6, S - 0.6, 1.3, mats, z=0.0)
    VC.camera(rec, (-9.0, -8.5, 2.6), (0.5, 0.0, 2.8))
    return rec


def receita_ret_serra_toras():
    rec = V.Receita()
    mats = Mats(743)
    tora = _mat_tora()
    _toras(rec, "pil_a", -1.7, -0.75, 6.4, 3, 0.29, tora, sem=1.0)
    _toras(rec, "pil_b", 1.5, 0.82, 6.0, 3, 0.26, tora, sem=3.0, ang=0.03)
    for s in (-1, 1):
        _est(
            rec,
            V.tre(
                f"cal{s}", (s * 2.6, -1.8, 0.09), (s * 2.6, 1.9, 0.09), 0.09, mats.go_escuro, segs=6
            ),
        )
    VC.camera(rec, (-5.5, -4.6, 1.8), (0.4, 0.0, 0.6))
    return rec


def receita_ret_serra_secagem():
    rec = V.Receita()
    sem = 744
    mats = Mats(sem)
    serrada = _mat_serrada()
    L, W, H = 9.2, 3.8, 2.75
    for sx in (-1, 0, 1):
        for sy in (-1, 1):
            V.poste(
                rec,
                f"pos{sx}{sy}",
                sx * (L / 2 - 0.12),
                sy * (W / 2 - 0.12),
                H - 0.1 if sy < 0 else H + 0.36,
                mats.go,
                r=0.1,
                base_pedra=mats.pedra,
            )
    for sy, z in ((-1, H - 0.1), (1, H + 0.36)):
        _est(
            rec,
            V.viga(
                f"fre{sy}",
                (-L / 2, sy * (W / 2 - 0.12), z),
                (L / 2, sy * (W / 2 - 0.12), z),
                0.12,
                0.15,
                mats.go,
            ),
        )
    E.telhado_varanda(
        rec,
        "tel",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        W / 2 + 0.4,
        H + 0.46,
        -W / 2 - 0.4,
        H - 0.02,
        mats,
        sem,
        ferrugem=0.92,
    )
    for k, x in enumerate((-2.9, 0.15, 3.0)):
        _tabuas(rec, f"pil{k}", x, 0.0, 0.14, 2.6, 2.4, 5 + (k * 2) % 3, serrada, mats)
    VC.camera(rec, (-6.2, -5.4, 1.9), (0.6, 0.0, 1.1))
    return rec


# =============================================================== Engenho do Espigão
def receita_ret_esp_armazem():
    rec = V.Receita()
    sem = 751
    mats = Mats(sem)
    L, W, H, esp = 27.0, 12.0, 5.2, 0.2
    hr = H + 2.9
    par = RF._reboco("reb_arm", "#d4b878", 0.36)
    lados = V.lados_ret(0.0, 0.0, L, W, esp)
    extra = {
        "frente": [
            (lados["frente"].comp / 2 - 7.0, 4.8, -1.0, 4.0),
            (lados["frente"].comp / 2 + 7.0, 4.8, -1.0, 4.0),
        ],
        "fundo": [(lados["fundo"].comp / 2, 4.2, -1.0, 3.8)],
        "esq": [(lados["esq"].comp / 2, 3.6, -1.0, 3.5)],
    }
    jan = (
        _jan("frente", (0.0,), 2.0, 2.6, 4.2)
        + _jan("fundo", (-9.0, -4.8, 4.8, 9.0), 1.7, 2.6, 4.1)
        + _jan("dir", (-3.0, 3.0), 1.5, 2.6, 4.0)
    )
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        par,
        [{"lado": "dir", "t": 0.0, "estilo": "folhas"}],
        jan,
        col="Concrete",
        sem=sem,
        vaos_extra=extra,
    )
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, par)
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.85, mats, sem=sem, ferrugem=0.97, beiral_oitao=0.5)
    _tesouras(rec, "tes", L, W, H, hr, 9, mats, esp)
    # lanternim: a segunda altura de telhado que marca a silhueta
    for s in (-1, 1):
        _est(
            rec,
            V.viga(
                f"lan_b{s}",
                (-6.0, s * 1.3, hr - 0.72),
                (6.0, s * 1.3, hr - 0.72),
                0.12,
                0.14,
                mats.go,
            ),
        )
        for k in range(7):
            x = -6.0 + k * 2.0
            _est(
                rec,
                V.viga(
                    f"lan_m{s}{k}",
                    (x, s * 1.3, hr - 0.72),
                    (x, s * 1.3, hr + 0.28),
                    0.1,
                    0.1,
                    mats.go,
                ),
            )
    marca = rec.marca()
    E.telhado_chapa(
        rec,
        "tel_lan",
        12.4,
        3.2,
        hr + 0.28,
        hr + 0.98,
        0.32,
        mats,
        sem=sem + 2,
        ferrugem=0.9,
        beiral_oitao=0.3,
    )
    rec.transformar(marca, V.lugar((0.0, 0.0, 0.0)))
    # compartimentos de carga, com divisórias que cortam a visão de ponta a ponta
    vao = 2.6
    for k, x in enumerate((-6.5, 6.5)):
        lado = V.Lado((x, -W / 2 + esp), math.pi / 2, W - 2 * esp, 0.12, 1.0)
        c = 2.4 if k == 0 else W - 3.0
        V.parede(
            rec,
            f"div{k}",
            lado,
            0.0,
            3.2,
            V.mat_tabua("van_div"),
            [(c, vao, -1.0, 2.9)],
            "Wood",
            "para",
            sem=sem + k,
        )
    yi = W / 2 - esp
    # mezanino de carga no fundo: o segundo nível do armazém
    zm = 2.75
    x0, x1 = -12.4, -7.0
    E.piso_tabuas(rec, "mez", x0, yi - 3.0, x1, yi - 0.02, zm, mats)
    E.barrotes(rec, "mez_b", x0, yi - 3.0, x1, yi - 0.02, zm - 0.06, mats)
    for k, x in enumerate((x0 + 0.12, (x0 + x1) / 2, x1 - 0.12)):
        V.poste(rec, f"mez_p{k}", x, yi - 2.9, zm - 0.1, mats.go_escuro, r=0.1)
    E.guarda_corpo(rec, "mez_g", (x0, yi - 2.98), (x1 - 1.6, yi - 2.98), zm, mats, passo=0.9)
    E.guarda_corpo(rec, "mez_g2", (x1, yi - 2.98), (x1, yi - 0.04), zm, mats, passo=0.8)
    E.escada(rec, "mez_e", (x1 - 0.8, yi - 6.5, PISO + 0.01), (x1 - 0.8, yi - 2.96, zm), 1.35, mats)
    for k, x in enumerate((x0 + 0.8, x0 + 2.4)):
        V.sacos(
            rec,
            f"mez_s{k}",
            [(x, yi - 0.7, 8), (x + 0.56, yi - 0.68, -8), (x + 0.28, yi - 1.1, 84)],
            mats,
            z=zm + 0.01,
        )
        rec.caixa(
            f"mez_s{k}", (x + 0.3, yi - 0.88, zm + 0.28), (1.35, 1.05, 0.56), "para", "Fabric"
        )
    # carga no piso de baixo
    for k, (x, y) in enumerate(
        ((-11.2, -3.6), (-9.1, -4.2), (9.2, 3.6), (11.0, 2.6), (10.6, -3.8))
    ):
        V.sacos(
            rec,
            f"sa{k}",
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
            rec, f"sb{k}", [(x + 0.2, y + 0.1, 16), (x + 0.75, y + 0.1, -6)], mats, z=PISO + 0.28
        )
        rec.caixa(f"sa{k}", (x + 0.55, y + 0.2, PISO + 0.36), (1.9, 1.05, 0.72), "para", "Fabric")
    RF._tremonha(rec, "trem", 1.4, 3.2, mats)
    for k, (x, y, r) in enumerate(
        ((-2.4, 3.6, 12), (-3.5, 3.1, -8), (3.9, -3.9, 30), (5.0, -3.2, -16))
    ):
        X._caixote(rec, f"cx{k}", (x, y), r, mats, dim=(1.15, 0.85, 0.8), z=PISO)
    _barril(rec, "bar_a", 9.6, -1.1, mats, PISO)
    _barril(rec, "bar_b", 10.2, -0.5, mats, PISO)
    X._bancada(rec, "banc", (4.4, yi - 0.42), 0, mats, comp=3.2)
    # plataforma de carga na frente, na altura da carroceria dos caminhões
    yp = -W / 2 - 3.2
    xa, xb = -L / 2 + 1.0, L / 2 - 1.0
    E.piso_tabuas(rec, "plat", xa, yp, xb, -W / 2, 0.92, mats)
    rec.caixa(
        "plat_b",
        ((xa + xb) / 2, (yp - W / 2) / 2, 0.45),
        (xb - xa, -W / 2 - yp, 0.9),
        "para",
        "Concrete",
    )
    _est(
        rec,
        V.bloco(
            "plat_mu",
            (xb - xa, 0.3, 0.9),
            ((xa + xb) / 2, yp + 0.15, 0.45),
            mats.pedra,
            chanfro=0.02,
        ),
    )
    k = 0
    x = xa
    while x <= xb + 0.01:
        V.poste(rec, f"alp{k}", x, yp + 0.1, 3.95, mats.go, r=0.1, base_pedra=None)
        x += (xb - xa) / 6
        k += 1
    _est(
        rec,
        V.viga(
            "alp_fre", (xa - 0.1, yp + 0.1, 3.95), (xb + 0.1, yp + 0.1, 3.95), 0.14, 0.17, mats.go
        ),
    )
    E.telhado_varanda(
        rec,
        "tel_alp",
        xa - 0.4,
        xb + 0.4,
        -W / 2 + 0.02,
        H + 0.05,
        yp - 0.5,
        3.86,
        mats,
        sem,
        ferrugem=0.95,
    )
    for k, xs in enumerate((xa + 3.0, 0.0, xb - 3.0)):
        E.escada(
            rec, f"esc_p{k}", (xs, yp - 1.7, 0.02), (xs, yp + 0.02, 0.92), 2.0, mats, corrimao=False
        )
    for k, x in enumerate((xa + 5.6, xb - 6.4)):
        V.sacos(
            rec,
            f"sp{k}",
            [(x, yp + 1.2, 7), (x + 0.56, yp + 1.22, -10), (x + 0.28, yp + 1.6, 84)],
            mats,
            z=0.92,
        )
        rec.caixa(f"sp{k}", (x + 0.3, yp + 1.4, 1.18), (1.35, 1.05, 0.52), "para", "Fabric")
    VC.camera(rec, (-12.6, -5.0, PISO + 1.8), (5.0, 3.2, PISO + 2.2))
    return rec


def receita_ret_esp_chamine():
    rec = V.Receita()
    sem = 752
    mats = Mats(sem)
    L, W, H, esp = 8.0, 5.8, 3.3, 0.22
    hr = H + 1.5
    # tijolo escurecido pela fuligem: o laranja cheio estourava na luz de fim de tarde
    tij = RF._mat_tijolo("tijolo_cham", "#4f2c20", "#74422f", "#8b5340")
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        tij,
        [
            {"lado": "frente", "t": -1.6, "estilo": "folhas"},
            {"lado": "esq", "t": 0.0, "estilo": "tabua", "folha": 1},
        ],
        _jan("frente", (1.9,), 1.4, 1.2, 2.4) + _jan("fundo", (-1.8, 1.0), 1.3, 1.2, 2.4),
        col="Concrete",
        sem=sem,
    )
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, V.mat_tabua("van"))
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.55, mats, sem=sem, ferrugem=0.98)
    # a caldeira deitada, com a boca da fornalha virada para a porta
    aco = V.mat_liso("aco_cald", "#4a4740", "#2e2a25", rug=0.5, escala=6.0, forca=0.45)
    corpo = V.cilindro("cald", 0.82, 3.4, (0, 0, 0), aco, segs=16)
    M.mover(
        corpo, Matrix.Translation((0.9, 0.7, PISO + 1.16)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    )
    _mob(rec, corpo)
    for x in (-0.3, 0.9, 2.1):
        anel = M.toro(f"cald_an{x}", 0.84, 0.03, 18, 4)
        V.gravar_uv_local(anel, lambda p: (p.x, p.y, p.z))
        M.material(anel, mats.ferro)
        M.mover(
            anel, Matrix.Translation((x, 0.7, PISO + 1.16)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
        )
        _mob(rec, M.suave(anel, 45))
    _mob(
        rec,
        V.bloco("cald_base", (3.7, 1.7, 0.42), (0.9, 0.7, PISO + 0.21), RF._tijolo("tijolo_base")),
    )
    _mob(rec, V.tre("cald_cano", (2.4, 0.7, PISO + 1.9), (3.05, 1.4, H + 0.7), 0.16, aco, segs=8))
    rec.caixa("caldeira", (0.9, 0.7, PISO + 1.0), (3.8, 1.8, 2.0), "para", "Metal")
    X._lenha(rec, "lenha", -3.4, -1.4, W / 2 - esp - 0.4, mats, z=PISO)
    # a chaminé de tijolo: o marco que se vê da estrada inteira
    Hc = 19.5
    xc, yc = L / 2 + 1.25, W / 2 - 1.25
    base = V.bloco(
        "cham_base",
        (2.5, 2.5, 2.4),
        (xc, yc, 1.2),
        RF._mat_tijolo("tijolo_bc", "#4a291e", "#6e3f2d", "#85503c"),
        chanfro=0.03,
    )
    rec.add(base, "Casa", "Paredes")
    fuste = V.torno_local(
        "cham_fuste",
        [
            (1.02, 2.3),
            (0.98, 3.0),
            (0.62, Hc - 1.1),
            (0.76, Hc - 0.95),
            (0.8, Hc - 0.5),
            (0.7, Hc - 0.4),
            (0.7, Hc),
            (0.5, Hc),
            (0.5, Hc - 0.5),
        ],
        14,
        RF._mat_tijolo("tijolo_cf", "#46271c", "#6a3c2b", "#805039"),
    )
    # as fiadas dão a volta na chaminé; a emenda fica no lado do telhado
    V.gravar_uv_local(fuste, lambda p: (math.atan2(p.y, p.x) * 0.85, p.z, 0.0))
    M.mover(fuste, Matrix.Translation((xc, yc, 0.0)))
    rec.add(fuste, "Casa", "Paredes")
    for k, z in enumerate((5.0, 8.0, 11.0, 14.0)):
        r = 1.02 + (0.62 - 1.02) * (z - 3.0) / (Hc - 4.1) + 0.015
        anel = M.toro(f"cham_an{k}", r, 0.035, 18, 4)
        V.gravar_uv_local(anel, lambda p: (p.x, p.y, p.z))
        M.material(anel, mats.ferro)
        M.mover(anel, Matrix.Translation((xc, yc, z)))
        _mob(rec, M.suave(anel, 45))
    rec.caixa("cham", (xc, yc, Hc / 2), (2.3, 2.3, Hc), "para", "Concrete")
    VC.camera(rec, (-9.0, -12.0, 4.8), (2.2, 1.0, 7.5))
    return rec


CASAS: dict[str, dict] = {
    "ret_comp_bomba": {
        "nome": "casa de bomba e comporta",
        "tipo": "casa de alvenaria com bomba, canaleta de pedra, comporta de tábuas e deck",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
    "ret_comp_celeiro": {
        "nome": "celeiro das comportas",
        "tipo": "celeiro de tábuas com palha, que liga a estrada ao dique",
        "fontes": [],
        "atlas": RF.ATLAS_M,
    },
    "ret_sino_salao": {
        "nome": "salão do sino",
        "tipo": "salão comunitário aberto em colunas, tesouras aparentes e sineira",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
    "ret_sino_loja_a": {
        "nome": "loja da varanda (amarela)",
        "tipo": "casa de comércio com varanda funda, balcão e quintal",
        "fontes": [],
        "atlas": RF.ATLAS_M,
    },
    "ret_sino_loja_b": {
        "nome": "loja da varanda (verde)",
        "tipo": "casa de comércio com varanda funda, balcão e quintal",
        "fontes": [],
        "atlas": RF.ATLAS_M,
    },
    "ret_canal_ponte": {
        "nome": "ponte do canal torto",
        "tipo": "ponte de madeira com treliças, cavaletes e encontros de pedra",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
    "ret_canal_oficina": {
        "nome": "oficina do canal",
        "tipo": "oficina com portão grande, bancadas, motor, pneus e tambores",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
    "ret_serra_galpao": {
        "nome": "galpão da serraria",
        "tipo": "galpão aberto com trilho, carrinho de tora, serra circular e pranchas",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
    "ret_serra_portico": {
        "nome": "pórtico da serraria",
        "tipo": "pórtico de madeira com talha, tora suspensa e trilho",
        "fontes": [],
        "atlas": RF.ATLAS_P,
    },
    "ret_serra_toras": {
        "nome": "pilhas de toras",
        "tipo": "duas pilhas de toras, proteção baixa do pátio",
        "fontes": [],
        "atlas": RF.ATLAS_P,
    },
    "ret_serra_secagem": {
        "nome": "secagem de madeira",
        "tipo": "telheiro com pilhas de pranchas em secagem",
        "fontes": [],
        "atlas": RF.ATLAS_P,
    },
    "ret_esp_armazem": {
        "nome": "armazém do Espigão",
        "tipo": "armazém em dois níveis, tesouras grandes, lanternim e plataforma de carga",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
    "ret_esp_chamine": {
        "nome": "casa da caldeira e chaminé",
        "tipo": "casa de tijolo com caldeira e chaminé de 19,5 m",
        "fontes": [],
        "atlas": RF.ATLAS_G,
    },
}
