"""Mercado das Duas Margens (D-243, prompt 18.3): o trecho de qualidade do Vale das Cinco Passagens.

Metros, Z para cima, frente em -Y. Portas de 1,40 x 2,50 m e soldado de 2,00 m.
- `ret_merc_sobrado`: casa de comércio amarela, loja aberta embaixo e varanda em cima;
- `ret_merc_galeria`: três lojas estreitas ligadas por dentro, com galeria coberta na frente;
- `ret_merc_banca_a/b/c`: bancas de bambu com toldo (frutas, potes e cestos, tecidos);
- `ret_merc_oficina`: oficina de bicicletas de chapa e tábua, aberta na frente;
- `ret_merc_cozinha`: cozinha de rua coberta de palha, com fogão, panelas e mesa.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_comum as E  # noqa: E402
import exp_sobrado as S  # noqa: E402
import exp_vila as X  # noqa: E402
import modelar as M  # noqa: E402
import novos as N  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

ATLAS_GRANDE = {
    "Telhado": {"tex": 1024, "teto": 3600, "amostras_ao": 16},
    "Mobilia": {"tex": 1024, "teto": 7000, "amostras_ao": 16},
    "Casa": {"tex": 1024, "teto": 9000, "amostras_ao": 8},
}
ATLAS_BANCA = {
    "Mobilia": {"tex": 512, "teto": 4200, "amostras_ao": 8},
    "Casa": {"tex": 256, "teto": 1200, "amostras_ao": 4},
}
ATLAS_OFICINA = {
    "Telhado": {"tex": 512, "teto": 1800, "amostras_ao": 8},
    "Mobilia": {"tex": 1024, "teto": 6000, "amostras_ao": 8},
    "Casa": {"tex": 512, "teto": 4000, "amostras_ao": 8},
}


# =============================================================== peças do mercado
def _panos(sem: int, cores: tuple[tuple[str, str], ...]) -> list:
    return [N.mat_pano(f"toldo_{sem}_{k}", cor=a, desbotado=b) for k, (a, b) in enumerate(cores)]


LONA = (("#b5a483", "#d3c6a6"), ("#8f5a44", "#b08770"))
LONA_VERDE = (("#a99c7d", "#cfc4a6"), ("#5c7a6c", "#88a091"))
LONA_OCRE = (("#b8a27a", "#d6c8a4"), ("#a97f3f", "#c9a86c"))


def _toldo(rec, nome, x0, x1, ya, za, yb, zb, panos, queda=0.05, largura=0.62):
    """Toldo em faixas de pano desbotado, da borda alta (ya, za) à borda baixa (yb, zb)."""
    n = max(2, round((x1 - x0) / largura))
    passo = (x1 - x0) / n
    for k in range(n):
        xa = x0 + k * passo

        def f(u, v, x0=xa):
            x = x0 + u * passo
            y = ya + v * (yb - ya)
            z = za + v * (zb - za) - queda * math.sin(math.pi * v)
            z -= 0.022 * math.sin(math.pi * u) * (0.4 + v)
            if v > 0.99:
                z -= 0.05 * math.sin(math.pi * u)  # a barra recortada
            return (x, y, z)

        o = V.grade(f"{nome}{k}", f, 2, 4, fora=(0, 0, 1))
        M.solidificar(o, 0.012, 0.0)
        V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z), k * 0.7)
        M.material(o, panos[k % len(panos)])
        rec.add(M.suave(o, 60), "Mobilia", "Mobilia")


def _bola(nome, c, r, mat, achata=1.0):
    perfil = [
        (0.0, -r * achata),
        (r * 0.72, -r * 0.72 * achata),
        (r, 0.0),
        (r * 0.72, r * 0.72 * achata),
        (0.0, r * achata),
    ]
    o = V.torno_local(nome, perfil, 6, mat)
    M.mover(o, Matrix.Translation(c))
    return o


def _monte(rec, nome, cx, cy, z, larg, prof, mat, r=0.055, filas=2, sem=1.0):
    """Monte de frutas num tabuleiro: camadas que encolhem para o topo."""
    k = 0
    for f in range(filas):
        nx = max(1, int((larg - f * r * 2) / (r * 2.05)))
        ny = max(1, int((prof - f * r * 2) / (r * 2.05)))
        for i in range(nx):
            for j in range(ny):
                dx = (i - (nx - 1) / 2) * r * 2.05 + 0.008 * math.sin(k * sem * 2.3)
                dy = (j - (ny - 1) / 2) * r * 2.05 + 0.008 * math.cos(k * sem * 1.7)
                c = (cx + dx, cy + dy, z + r * 0.9 + f * r * 1.55)
                rec.add(_bola(f"{nome}{k}", c, r, mat), "Mobilia", "Mobilia")
                k += 1


def _tabuleiro(rec, nome, cx, cy, z, larg, prof, mats: Mats):
    o = V.bloco(f"{nome}_fundo", (larg, prof, 0.025), (cx, cy, z + 0.0125), mats.esteira)
    rec.add(o, "Mobilia", "Mobilia")
    for s in (-1, 1):
        rec.add(
            V.bloco(
                f"{nome}_b{s}", (larg, 0.025, 0.05), (cx, cy + s * prof / 2, z + 0.03), mats.tre
            ),
            "Mobilia",
            "Mobilia",
        )
        rec.add(
            V.bloco(
                f"{nome}_c{s}", (0.025, prof, 0.05), (cx + s * larg / 2, cy, z + 0.03), mats.tre
            ),
            "Mobilia",
            "Mobilia",
        )


def _balcao(rec, nome, cx, cy, comp, prof, alt, mats: Mats):
    """Balcão de tábua sobre cavaletes, com a colisão de uma caixa só."""
    rec.add(
        V.bloco(
            f"{nome}_tampo", (comp, prof, 0.045), (cx, cy, alt - 0.0225), mats.go, chanfro=0.006
        ),
        "Mobilia",
        "Mobilia",
    )
    for sx in (-1, 0, 1):
        x = cx + sx * (comp / 2 - 0.12)
        for sy in (-1, 1):
            rec.add(
                V.bloco(
                    f"{nome}_p{sx}{sy}",
                    (0.05, 0.05, alt - 0.045),
                    (x, cy + sy * (prof / 2 - 0.05), (alt - 0.045) / 2),
                    mats.go_escuro,
                ),
                "Mobilia",
                "Mobilia",
            )
    rec.add(
        V.bloco(f"{nome}_baixa", (comp - 0.16, prof - 0.1, 0.025), (cx, cy, 0.3), mats.go),
        "Mobilia",
        "Mobilia",
    )
    rec.caixa(nome, (cx, cy, alt / 2), (comp, prof, alt), "para", "Wood")


def _armacao(rec, L, W, z_frente, z_fundo, mats: Mats, r=0.055):
    """Quatro postes de bambu amarrados por varas: a armação de uma banca."""
    cantos = ((-L / 2, -W / 2), (L / 2, -W / 2), (-L / 2, W / 2), (L / 2, W / 2))
    for i, (x, y) in enumerate(cantos):
        zt = z_frente if y < 0 else z_fundo
        rec.add(
            V.tre(f"poste{i}", (x, y, 0.0), (x, y, zt + 0.1), r, mats.tre, segs=6),
            "Casa",
            "Estrutura",
        )
        rec.caixa(f"poste{i}", (x, y, zt / 2), (0.13, 0.13, zt), "passa", "Bamboo")
    for s, z in ((-1, z_frente), (1, z_fundo)):
        rec.add(
            V.tre(
                f"vara_x{s}",
                (-L / 2 - 0.22, s * W / 2, z),
                (L / 2 + 0.22, s * W / 2, z),
                0.04,
                mats.tre,
                segs=5,
            ),
            "Casa",
            "Estrutura",
        )
    for s in (-1, 1):
        rec.add(
            V.tre(
                f"vara_y{s}",
                (s * L / 2, -W / 2 - 0.2, z_frente - 0.03),
                (s * L / 2, W / 2 + 0.2, z_fundo + 0.04),
                0.035,
                mats.tre,
                segs=5,
            ),
            "Casa",
            "Estrutura",
        )


# =============================================================== bancas
def _banca_frutas(rec, mats: Mats, L, W):
    cores = (
        V.mat_liso("fruta_manga", "#c79a35", "#8a7a2b", rug=0.55),
        V.mat_liso("fruta_verde", "#6f8a3a", "#4c6a2c", rug=0.6),
        V.mat_liso("fruta_verm", "#a8452f", "#7b2f22", rug=0.5),
        V.mat_liso("fruta_laranja", "#cf8233", "#a55f24", rug=0.6),
    )
    _balcao(rec, "balcao", 0.0, -0.3, L - 0.5, 1.05, 0.86, mats)
    for k, (dx, dy, cor, r) in enumerate(
        (
            (-1.1, -0.52, 0, 0.06),
            (-0.4, -0.52, 1, 0.055),
            (0.35, -0.52, 2, 0.05),
            (1.1, -0.52, 3, 0.058),
            (-0.75, -0.06, 3, 0.05),
            (0.75, -0.06, 1, 0.06),
        )
    ):
        _tabuleiro(rec, f"tab{k}", dx, dy, 0.86, 0.62, 0.42, mats)
        _monte(rec, f"fruta{k}", dx, dy, 0.885, 0.52, 0.32, cores[cor], r=r, sem=k + 1.0)
    # cachos pendurados na vara da frente
    for k, x in enumerate((-1.25, -0.5, 0.45, 1.2)):
        z0 = 2.1
        rec.add(
            V.tre(f"fio{k}", (x, -W / 2, 2.42), (x, -W / 2, z0), 0.006, mats.corda, segs=3),
            "Mobilia",
            "Mobilia",
        )
        for j in range(6):
            a = j * 1.05
            c = (x + 0.05 * math.cos(a), -W / 2 + 0.05 * math.sin(a), z0 - 0.03 * j)
            rec.add(
                _bola(f"cacho{k}_{j}", c, 0.042, cores[k % 2], achata=1.7), "Mobilia", "Mobilia"
            )
    X._cesto(rec, "cesto_a", (-L / 2 + 0.35, W / 2 - 0.45), mats, r=0.3, alt=0.46)
    X._cesto(rec, "cesto_b", (0.1, W / 2 - 0.4), mats, r=0.26, alt=0.4)
    X._caixote(rec, "caixote", (L / 2 - 0.55, W / 2 - 0.45), 12, mats, dim=(0.75, 0.55, 0.5))


def _banca_potes(rec, mats: Mats, L, W):
    _balcao(rec, "balcao", 0.0, W / 2 - 0.55, L - 0.4, 0.8, 0.74, mats)
    for k, (x, alt, r) in enumerate(
        (
            (-1.25, 0.34, 0.15),
            (-0.7, 0.42, 0.18),
            (-0.1, 0.3, 0.14),
            (0.5, 0.4, 0.17),
            (1.15, 0.34, 0.15),
        )
    ):
        X._pote(rec, f"pote_alto{k}", (x, W / 2 - 0.55), mats, alt=alt, r=r, z=0.74, sem=k + 2)
    for k, (x, y, alt, r) in enumerate(
        (
            (-1.35, -0.72, 0.72, 0.31),
            (-0.62, -0.86, 0.6, 0.27),
            (0.75, -0.84, 0.66, 0.29),
            (1.42, -0.62, 0.52, 0.24),
        )
    ):
        X._pote(rec, f"pote{k}", (x, y), mats, alt=alt, r=r, sem=k + 9)
    for k, (x, y, r, alt) in enumerate(
        (
            (-0.95, 0.1, 0.34, 0.52),
            (-0.2, -0.05, 0.28, 0.44),
            (0.42, 0.14, 0.31, 0.5),
            (1.15, 0.05, 0.26, 0.42),
        )
    ):
        X._cesto(rec, f"cesto{k}", (x, y), mats, r=r, alt=alt)
    for k, x in enumerate((-1.2, 0.0, 1.2)):
        X._cesto(rec, f"cesto_cima{k}", (x, W / 2 - 0.22), mats, r=0.17, alt=0.26, z=0.74)


def _banca_tecidos(rec, mats: Mats, L, W):
    tons = (
        ("#7d3c34", "#a56a5c"),
        ("#3f5f6f", "#6b8894"),
        ("#a8843f", "#c9ad70"),
        ("#56683f", "#82926a"),
        ("#6a4a68", "#8f7690"),
    )
    panos = [N.mat_pano(f"tecido{k}", cor=a, desbotado=b) for k, (a, b) in enumerate(tons)]
    _balcao(rec, "balcao", 0.0, -0.35, L - 0.55, 1.0, 0.8, mats)
    for k, x in enumerate((-1.2, -0.72, -0.24, 0.24, 0.72, 1.2)):
        for j in range(3):
            rec.add(
                V.bloco(
                    f"pilha{k}_{j}",
                    (0.42, 0.74, 0.07),
                    (x + 0.012 * math.sin(j * 2.0 + k), -0.35, 0.8 + 0.035 + j * 0.072),
                    panos[(k + j) % len(panos)],
                    chanfro=0.012,
                ),
                "Mobilia",
                "Mobilia",
            )
    # panos pendurados na vara do fundo
    for k, x in enumerate((-1.4, -0.82, -0.24, 0.34, 0.92, 1.45)):

        def f(u, v, x0=x, n0=k):
            return (
                x0 - 0.23 + u * 0.46,
                W / 2 - 0.02 + 0.025 * math.sin(u * 9.0 + n0),
                2.72 - v * (1.5 + 0.18 * math.sin(n0 * 1.7)),
            )

        o = V.grade(f"pano{k}", f, 4, 3, fora=(0, -1, 0))
        M.solidificar(o, 0.01, 0.0)
        V.gravar_uv_local(o, lambda p: (p.x, p.z, p.y), k * 0.6)
        M.material(o, panos[k % len(panos)])
        rec.add(M.suave(o, 60), "Mobilia", "Mobilia")
    rec.caixa("panos", (0.0, W / 2 - 0.02, 1.9), (3.3, 0.08, 1.6), "passa", "Fabric")


BANCAS = {
    "ret_merc_banca_a": {"sem": 511, "panos": LONA, "miolo": _banca_frutas},
    "ret_merc_banca_b": {"sem": 512, "panos": LONA_OCRE, "miolo": _banca_potes},
    "ret_merc_banca_c": {"sem": 513, "panos": LONA_VERDE, "miolo": _banca_tecidos},
}


def _banca(chave: str) -> V.Receita:
    c = BANCAS[chave]
    rec = V.Receita()
    mats = Mats(c["sem"])
    L, W = 3.9, 2.7
    z_frente, z_fundo = 2.48, 2.86
    _armacao(rec, L, W, z_frente, z_fundo, mats)
    _toldo(
        rec,
        "toldo",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        W / 2 + 0.25,
        z_fundo + 0.1,
        -W / 2 - 0.5,
        z_frente - 0.14,
        _panos(c["sem"], c["panos"]),
    )
    c["miolo"](rec, mats, L, W)
    VC.camera(rec, (-1.6, -3.4, 1.6), (0.3, 0.2, 0.95))
    return rec


def receita_ret_merc_banca_a():
    return _banca("ret_merc_banca_a")


def receita_ret_merc_banca_b():
    return _banca("ret_merc_banca_b")


def receita_ret_merc_banca_c():
    return _banca("ret_merc_banca_c")


# =============================================================== sobrado de comércio
def _reboco_amarelo():
    return V.mat_vach_dat(
        "vach_amarelo", "#8d7247", "#65492f", "#a98a5a", cal="#d6b25f", exposta=0.22
    )


def receita_ret_merc_sobrado():
    S.SOBRADOS["ret_merc_sobrado"] = {
        "sem": 521,
        "L": 13.0,
        "W": 7.6,
        "esp": 0.16,
        "aberto": True,
        "vaos": 4,
        "escada": 1.4,
        "parede": _reboco_amarelo,
        "col": "Earth",
        "pilar": "alvenaria",
        "mat_pilar": lambda: V.mat_gach("gach_amarelo", "#d2b264", "#a58a4c", "#94523a", 0.2),
        "forma": "2aguas",
        "cume": 2.5,
        "telha": ("#9a5a3e", "#6f3e2b", "#b5724d"),
    }
    rec = S._sobrado("ret_merc_sobrado")
    mats = Mats(528)
    L, W = 13.0, 7.6
    yv = -W / 2 - S.VARANDA
    # toldo da loja, preso sob a varanda, e as mercadorias da frente
    _toldo(
        rec,
        "toldo_loja",
        -L / 2 + 0.2,
        L / 2 - 0.2,
        yv + 0.1,
        2.86,
        yv - 1.5,
        2.46,
        _panos(521, LONA),
    )
    for k, x in enumerate((-4.6, 4.2)):
        _balcao(rec, f"balcao{k}", x, yv + 0.55, 2.3, 0.72, 0.84, mats)
        X._cesto(rec, f"cesto_b{k}", (x - 0.6, yv + 0.55), mats, r=0.24, alt=0.34, z=0.84)
        X._cesto(rec, f"cesto_c{k}", (x + 0.55, yv + 0.55), mats, r=0.22, alt=0.3, z=0.84)
    return rec


# =============================================================== galeria de três lojas
def receita_ret_merc_galeria():
    rec = V.Receita()
    sem = 531
    mats = Mats(sem)
    L, W, H, esp = 14.4, 6.0, 3.25, 0.16
    GAL = 3.0  # fundo da galeria
    xs = (-4.8, 0.0, 4.8)
    par = V.mat_vach_dat("vach_verde", "#7f7f62", "#585c48", "#9a9a7c", cal="#b9c0a2", exposta=0.25)
    ngoi = V.mat_ngoi("ngoi", "#8c5238", "#633827", "#a56a4b")
    portas = [{"lado": "frente", "t": x, "estilo": "folhas"} for x in xs]
    portas += [
        {"lado": "fundo", "t": xs[0], "estilo": "tabua", "folha": 1},
        {"lado": "fundo", "t": xs[2], "estilo": "tabua", "folha": -1},
    ]
    janelas = [
        {"lado": "frente", "t": x + 1.55, "w": 0.8, "z0": 1.05, "z1": 2.05, "estilo": "tre"}
        for x in (xs[0], xs[1])
    ]
    janelas += [
        {"lado": "fundo", "t": xs[1], "w": 1.0, "z0": 1.1, "z1": 2.05, "estilo": "tre"},
        {"lado": "esq", "t": 0.0, "w": 0.9, "z0": 1.05, "z1": 2.05, "estilo": "tre"},
        {"lado": "dir", "t": 0.0, "w": 0.9, "z0": 1.05, "z1": 2.05, "estilo": "tre"},
    ]
    VC.casa_ret(rec, mats, "c", L, W, H, esp, par, portas, janelas, col="Earth", sem=sem)
    # as três lojas se ligam por dentro
    vao = V.PORTA_LARG + 2 * V.BATENTE
    topo = PISO + V.PORTA_ALT + V.BATENTE
    for k, x in enumerate((-2.4, 2.4)):
        lado = V.Lado((x, -W / 2 + esp), math.pi / 2, W - 2 * esp, 0.1, 1.0)
        V.parede(
            rec,
            f"div{k}",
            lado,
            0.0,
            H,
            par,
            [(1.5, vao, -1.0, topo)],
            "Earth",
            "para",
            sem=sem + k,
        )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        H + 2.0,
        0.5,
        "2aguas",
        "ngoi",
        0.1,
        ngoi,
        mats,
        beiral_oitao=0.45,
        sem=sem,
        tesouras=(-L / 3, 0.0, L / 3),
        mat_oitao=par,
        oitao_esp=esp,
        col_oitao="Earth",
    )
    # a galeria: chão, colunas, frechal, meia-água de telha e toldos entre as colunas
    yg = -W / 2 - GAL
    V.nen(rec, "galeria", -L / 2 - 0.2, yg - 0.15, L / 2 + 0.2, -W / 2, mats)
    z_col = 2.95
    n = 6
    for k in range(n + 1):
        x = -L / 2 + k * L / n
        V.poste(rec, f"col{k}", x, yg + 0.05, z_col, mats.go, r=0.1, base_pedra=mats.pedra)
    rec.add(
        V.viga(
            "frechal",
            (-L / 2 - 0.15, yg + 0.05, z_col),
            (L / 2 + 0.15, yg + 0.05, z_col),
            0.13,
            0.15,
            mats.go,
        ),
        "Casa",
        "Estrutura",
    )
    V.agua_unica(
        rec,
        "tel_gal",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        -W / 2 + 0.02,
        H + 0.62,
        yg - 0.5,
        z_col + 0.05,
        0.1,
        "ngoi",
        ngoi,
        mats,
        sem=sem + 2,
    )
    for k, (i0, i1, panos) in enumerate(((0, 2, LONA), (3, 4, LONA_VERDE), (5, 6, LONA_OCRE))):
        x0, x1 = -L / 2 + i0 * L / n + 0.12, -L / 2 + i1 * L / n - 0.12
        _toldo(
            rec,
            f"toldo{k}",
            x0,
            x1,
            yg - 0.02,
            z_col - 0.06,
            yg - 1.05,
            2.5,
            _panos(sem + k, panos),
        )
    # loja 1: grãos; loja 2: potes; loja 3: ferragens
    xi = L / 2 - esp
    yi = W / 2 - esp
    X._prateleira(rec, "est_a", (xs[0] - 0.9, yi - 0.24), 0, mats, comp=2.2, z=PISO)
    V.sacos(
        rec,
        "sacos_a",
        [
            (xs[0] + 0.7, yi - 0.65, 6),
            (xs[0] + 1.25, yi - 0.62, -10),
            (xs[0] + 0.95, yi - 0.25, 86),
        ],
        mats,
        z=PISO + 0.02,
    )
    rec.caixa("sacos", (xs[0] + 0.98, yi - 0.45, PISO + 0.26), (1.35, 1.0, 0.52), "para", "Fabric")
    _balcao(rec, "balcao_a", xs[0] - 1.0, -0.1, 1.9, 0.62, PISO + 0.88, mats)
    X._prateleira(rec, "est_b", (xs[1] - 0.2, yi - 0.24), 0, mats, comp=2.6, z=PISO)
    X._pote(rec, "pote_a", (xs[1] + 1.55, -yi + 0.5), mats, alt=0.72, r=0.3, z=PISO, sem=sem)
    X._pote(rec, "pote_b", (xs[1] - 1.5, -yi + 0.5), mats, alt=0.6, r=0.26, z=PISO, sem=sem + 1)
    X._prateleira(rec, "est_c", (xi - 0.24, 0.8), 90, mats, comp=2.0, z=PISO)
    X._bancada(rec, "bancada", (xs[2] - 0.75, yi - 0.42), 0, mats, comp=2.1, prof=0.66)
    X._caixote(rec, "caixote", (xs[2] + 1.55, -yi + 0.45), 6, mats, z=PISO)
    # mercadoria na galeria, encostada na parede, longe das portas
    X._cesto(rec, "cesto_a", (xs[0] + 1.6, -W / 2 - 0.42), mats, r=0.3, alt=0.46)
    X._cesto(rec, "cesto_b", (xs[1] + 1.6, -W / 2 - 0.42), mats, r=0.28, alt=0.42)
    X._caixote(rec, "cx_g", (xs[2] - 1.6, -W / 2 - 0.5), 8, mats, dim=(0.8, 0.55, 0.52))
    VC.camera(rec, (xs[0] - 1.2, -yi + 0.5, PISO + 1.6), (xs[1] + 1.5, yi - 0.8, PISO + 0.9))
    return rec


# =============================================================== oficina de bicicletas
def _bicicleta(rec, nome, pos, rot, mats: Mats, z=0.0):
    """Bicicleta de carga em pé: duas rodas, quadro em losango, selim e guidão."""
    R = 0.34
    o = []
    for k, x in enumerate((-0.52, 0.52)):
        aro = M.toro(f"{nome}_aro{k}", R, 0.018, 18, 4)
        V.gravar_uv_local(aro, lambda p: (p.x, p.y, p.z))
        M.material(aro, mats.ferro)
        M.mover(aro, Matrix.Translation((x, 0, R)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        o.append(M.suave(aro, 45))
        for j in range(5):
            a = j / 5 * math.pi
            d = Vector((math.cos(a), 0, math.sin(a))) * R
            c = Vector((x, 0, R))
            o.append(V.tre(f"{nome}_raio{k}{j}", c - d, c + d, 0.003, mats.ferro, segs=3))
    pts = {
        "pedal": Vector((-0.05, 0, 0.26)),
        "selim": Vector((-0.22, 0, 0.78)),
        "guidao": Vector((0.38, 0, 0.82)),
        "tras": Vector((-0.52, 0, R)),
        "frente": Vector((0.52, 0, R)),
    }
    for a, b in (
        ("pedal", "selim"),
        ("pedal", "guidao"),
        ("selim", "guidao"),
        ("pedal", "tras"),
        ("selim", "tras"),
        ("guidao", "frente"),
    ):
        o.append(V.tre(f"{nome}_q{a}{b}", pts[a], pts[b], 0.013, mats.ferro, segs=5))
    o.append(
        V.bloco(
            f"{nome}_selim", (0.22, 0.09, 0.04), (-0.23, 0, 0.82), mats.pano_escuro, chanfro=0.012
        )
    )
    o.append(
        V.tre(f"{nome}_guidao", (0.4, -0.25, 0.92), (0.4, 0.25, 0.92), 0.012, mats.ferro, segs=5)
    )
    o.append(V.tre(f"{nome}_haste", (0.38, 0, 0.82), (0.4, 0, 0.92), 0.013, mats.ferro, segs=5))
    X._colocar(rec, o, nome, pos, rot, z, (0, 0, 0.48), (1.72, 0.5, 0.96), "passa", "Metal")


def receita_ret_merc_oficina():
    rec = V.Receita()
    sem = 541
    mats = Mats(sem)
    L, W, H, esp = 8.0, 5.6, 3.1, 0.07
    van = V.mat_tabua("van")
    marca = rec.marca()
    # três paredes de tábua; a frente é toda aberta, com dois pilares
    VC.casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        van,
        [{"lado": "fundo", "t": 2.4, "estilo": "tabua", "folha": 1}],
        [
            {"lado": "esq", "t": -0.4, "w": 1.1, "z0": 1.1, "z1": 2.05, "estilo": "tre"},
            {"lado": "dir", "t": 0.3, "w": 1.1, "z0": 1.1, "z1": 2.05, "estilo": "tre"},
        ],
        col="Wood",
        sem=sem,
        lados_usar=("fundo", "esq", "dir"),
    )
    hr = H + 1.3
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, van)
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.7, mats, sem=sem, ferrugem=0.85)
    rec.transformar(marca, V.lugar((0.0, 0.0, 0.0)))
    for k, x in enumerate((-L / 2 + 0.1, -L / 6, L / 6, L / 2 - 0.1)):
        V.poste(rec, f"pil{k}", x, -W / 2 + 0.05, H, mats.go, r=0.1, base_pedra=mats.pedra)
    rec.add(
        V.viga(
            "frechal", (-L / 2, -W / 2 + 0.05, H), (L / 2, -W / 2 + 0.05, H), 0.13, 0.15, mats.go
        ),
        "Casa",
        "Estrutura",
    )
    yi = W / 2 - esp
    xi = L / 2 - esp
    X._bancada(rec, "bancada", (-1.5, yi - 0.42), 0, mats, comp=3.0, prof=0.7)
    # rodas e aros pendurados na parede do fundo
    for k, (x, z, r) in enumerate(
        ((-3.0, 2.25, 0.34), (-2.2, 2.3, 0.34), (-1.4, 2.25, 0.3), (-0.6, 2.32, 0.34))
    ):
        aro = M.toro(f"roda_par{k}", r, 0.018, 18, 4)
        V.gravar_uv_local(aro, lambda p: (p.x, p.y, p.z))
        M.material(aro, mats.ferro)
        M.mover(aro, Matrix.Translation((x, yi - 0.05, z)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        rec.add(M.suave(aro, 45), "Mobilia", "Mobilia")
        for j in range(4):
            a = j / 4 * math.pi
            d = Vector((math.cos(a), 0, math.sin(a))) * r
            c = Vector((x, yi - 0.05, z))
            rec.add(
                V.tre(f"roda_raio{k}{j}", c - d, c + d, 0.003, mats.ferro, segs=3),
                "Mobilia",
                "Mobilia",
            )
    # quadro de ferramentas
    rec.add(
        V.bloco("quadro", (1.5, 0.03, 0.8), (1.0 - 1.9, yi - 0.03, 1.55), mats.go_escuro),
        "Mobilia",
        "Mobilia",
    )
    for k in range(7):
        x = -1.5 + k * 0.2
        comp = 0.3 + 0.08 * (k % 3)
        rec.add(
            V.bloco(f"ferr{k}", (0.035, 0.018, comp), (x, yi - 0.055, 1.72 - comp / 2), mats.ferro),
            "Mobilia",
            "Mobilia",
        )
    _bicicleta(rec, "bici_a", (1.2, -0.7), 18, mats, z=PISO)
    _bicicleta(rec, "bici_b", (2.75, 0.75), -74, mats, z=PISO)
    X._prateleira(rec, "estante", (xi - 0.24, 0.35), 90, mats, comp=1.9, z=PISO)
    X._caixote(rec, "caixote", (-xi + 0.55, -0.6), 6, mats, z=PISO)
    X._banco(rec, "banco", (-2.1, -0.55), 12, mats, comp=1.1, z=PISO)
    VC.camera(rec, (2.6, -3.6, 1.6), (-1.2, 2.0, 1.1))
    return rec


# =============================================================== cozinha de rua
def receita_ret_merc_cozinha():
    rec = V.Receita()
    sem = 551
    mats = Mats(sem)
    L, W = 5.0, 3.8
    z_f, z_c = 2.42, 3.25
    tranh = V.mat_tranh("tranh")
    for k, (x, y) in enumerate(
        (
            (-L / 2, -W / 2),
            (L / 2, -W / 2),
            (-L / 2, W / 2),
            (L / 2, W / 2),
            (0.0, -W / 2),
            (0.0, W / 2),
        )
    ):
        V.poste(rec, f"pos{k}", x, y, z_f, mats.go, r=0.075, quadrado=False, base_pedra=mats.pedra)
    for s in (-1, 1):
        rec.add(
            V.viga(
                f"frechal{s}",
                (-L / 2 - 0.1, s * W / 2, z_f),
                (L / 2 + 0.1, s * W / 2, z_f),
                0.09,
                0.1,
                mats.go,
            ),
            "Casa",
            "Estrutura",
        )
    rec.add(
        V.tre("cume", (-L / 2 - 0.25, 0, z_c), (L / 2 + 0.25, 0, z_c), 0.05, mats.tre, segs=5),
        "Casa",
        "Estrutura",
    )
    for s in (-1, 1):
        V.agua_unica(
            rec,
            f"agua{s}",
            -L / 2 - 0.35,
            L / 2 + 0.35,
            0.0,
            z_c,
            s * (W / 2 + 0.45),
            z_f - 0.12,
            0.14,
            "tranh",
            tranh,
            mats,
            sem=sem + s,
        )
    # fogão de tijolo com duas bocas e panelas
    fogao = V.mat_gach("gach_fogao", "#8a7a68", "#5e5245", "#7f4a34", 0.6)
    rec.add(
        V.bloco("fogao", (1.9, 0.85, 0.72), (-1.2, W / 2 - 0.55, 0.36), fogao, chanfro=0.02),
        "Mobilia",
        "Mobilia",
    )
    rec.caixa("fogao", (-1.2, W / 2 - 0.55, 0.36), (1.9, 0.85, 0.72), "para", "Brick")
    for k, x in enumerate((-1.68, -0.72)):
        rec.add(
            V.cilindro(f"boca{k}", 0.25, 0.03, (x, W / 2 - 0.55, 0.73), mats.cinza, segs=10),
            "Mobilia",
            "Mobilia",
        )
        p = V.torno_local(
            f"panela{k}",
            [(0.0, 0.0), (0.17, 0.0), (0.23, 0.08), (0.24, 0.2), (0.22, 0.22), (0.0, 0.2)],
            12,
            mats.ferro,
        )
        M.mover(p, Matrix.Translation((x, W / 2 - 0.55, 0.745)))
        rec.add(p, "Mobilia", "Mobilia")
    _balcao(rec, "balcao", 1.1, W / 2 - 0.5, 2.1, 0.68, 0.84, mats)
    for k, x in enumerate((0.45, 0.95, 1.5)):
        t = V.torno_local(
            f"tigela{k}",
            [(0.0, 0.0), (0.05, 0.0), (0.09, 0.04), (0.1, 0.07), (0.08, 0.06), (0.0, 0.02)],
            10,
            mats.louca,
        )
        M.mover(t, Matrix.Translation((x, W / 2 - 0.5, 0.84)))
        rec.add(t, "Mobilia", "Mobilia")
    X._pote(rec, "pote", (L / 2 - 0.35, W / 2 - 0.35), mats, alt=0.66, r=0.28, sem=sem)
    X._lenha(rec, "lenha", -L / 2 + 0.15, -L / 2 + 1.3, W / 2 + 0.28, mats)
    # mesa do freguês, longe do fogão, com a passagem livre no meio
    V.ban_thap(rec, "mesa", (0.6, -0.95), 0, mats, comp=1.5, larg=0.8, alt=0.72, banquinhos=0)
    X._banco(rec, "banco_a", (0.6, -1.62), 0, mats, comp=1.4)
    X._banco(rec, "banco_b", (0.6, -0.28), 0, mats, comp=1.4)
    VC.camera(rec, (-2.2, -3.6, 1.6), (0.2, 0.9, 0.95))
    return rec


CASAS: dict[str, dict] = {
    "ret_merc_sobrado": {
        "nome": "casa de comércio do mercado",
        "tipo": "dois andares amarelos, loja aberta, varanda, escada de 1,40 m e toldo",
        "fontes": [],
        "atlas": ATLAS_GRANDE,
    },
    "ret_merc_galeria": {
        "nome": "galeria de três lojas",
        "tipo": "lojas estreitas ligadas por dentro, galeria coberta e toldos",
        "fontes": [],
        "atlas": ATLAS_GRANDE,
    },
    "ret_merc_banca_a": {
        "nome": "banca de frutas",
        "tipo": "armação de bambu, toldo e tabuleiros",
        "fontes": [],
        "atlas": ATLAS_BANCA,
    },
    "ret_merc_banca_b": {
        "nome": "banca de potes e cestos",
        "tipo": "armação de bambu, toldo, potes e cestos",
        "fontes": [],
        "atlas": ATLAS_BANCA,
    },
    "ret_merc_banca_c": {
        "nome": "banca de tecidos",
        "tipo": "armação de bambu, toldo, pilhas e panos pendurados",
        "fontes": [],
        "atlas": ATLAS_BANCA,
    },
    "ret_merc_oficina": {
        "nome": "oficina de bicicletas",
        "tipo": "tábua e chapa, frente aberta, bancada, rodas e duas bicicletas",
        "fontes": [],
        "atlas": ATLAS_OFICINA,
    },
    "ret_merc_cozinha": {
        "nome": "cozinha de rua",
        "tipo": "cobertura de palha, fogão de tijolo, panelas, balcão e mesa",
        "fontes": [],
        "atlas": ATLAS_OFICINA,
    },
}
