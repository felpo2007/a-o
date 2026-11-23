"""Sobrados grandes da Vila (D-234). Metros, Z para cima, frente (porta principal) em -Y.

Quatro casas de dois andares, com interior nos dois níveis:
- `exp_sobrado_a` e `exp_sobrado_b`: térreo ABERTO, sobre colunas, e escada de fora até a varanda;
- `exp_sobrado_c` e `exp_sobrado_d`: térreo FECHADO, de alvenaria, e escada por dentro.

O grupo Casa só usa materiais com faixa na trim sheet (`vila_trim.FAIXAS`).
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_comum as E  # noqa: E402
import exp_vila as X  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

Z2 = 3.15  # topo do piso de cima
H_SUP = 2.85  # altura da parede de cima, a partir do pé dela (Z2 - PISO)
VARANDA = 1.8  # fundo da varanda de cima
ESCADA = 4.2  # avanço da escada (subida de ~37°)

ATLAS = {
    "Telhado": {"tex": 1024, "teto": 3600, "amostras_ao": 32},
    "Mobilia": {"tex": 1024, "teto": 6000, "amostras_ao": 32},
    "Casa": {"tex": 256, "teto": 9000, "amostras_ao": 8},
}


def _pilar(rec, nome, x, y, z1, mat, r=0.17):
    """Coluna quadrada de alvenaria, com base e colisão.

    O `local` do `bloco` segue o veio (bom para madeira). Na faixa de parede, V tem que ser a
    altura: sem isso o reboco deita na coluna e vira listras."""
    corpo = V.bloco(nome, (2 * r, 2 * r, z1), (x, y, z1 / 2), mat, chanfro=0.012)
    V.gravar_uv_local(corpo, lambda p: (p.x, p.z, p.y))
    rec.add(corpo, "Casa", "Estrutura")
    base = V.bloco(
        f"{nome}_base", (2 * r + 0.1, 2 * r + 0.1, 0.22), (x, y, 0.11), mat, chanfro=0.015
    )
    V.sem_fundo(base, 0.0)
    V.gravar_uv_local(base, lambda p: (p.x, p.z, p.y))
    rec.add(base, "Casa", "Estrutura")
    rec.caixa(nome, (x, y, z1 / 2), (2 * r, 2 * r, z1), "para", "Concrete")


def _placa_forro(rec, nome, a, b, c, d, mat):
    """Esteira de bambu sob a água, no grupo Casa: no grupo Telhado a redução da malha a engole.

    O `local` é (ao longo do beiral, subindo a água, 0), o que a faixa de parede espera."""
    ob = E.forro(nome, a, b, c, d, mat, baixar=0.125)
    A, B, C, D = Vector(a), Vector(b), Vector(c), Vector(d)
    u = (B - A).normalized()
    v = ((C + D) / 2 - (A + B) / 2).normalized()
    V.gravar_uv_local(ob, lambda p: ((p - A).dot(u), (p - A).dot(v), 0.0))
    rec.add(ob, "Casa", "Estrutura")


def _forro_telhado(rec, nome, L, W, h, hr, beiral, beiral_oitao, forma, mat):
    """Face de baixo das águas, logo abaixo da placa de 0,10 m e na altura dos caibros."""
    s = (hr - (h + 0.05)) / (W / 2)
    ze = hr - s * (W / 2 + beiral)
    if forma == "4aguas":
        X, Y = L / 2 + beiral, W / 2 + beiral
        r = max(0.0, (L - W) / 2)
        planos = [
            ((-X, -Y, ze), (X, -Y, ze), (r, 0, hr), (-r, 0, hr)),
            ((X, Y, ze), (-X, Y, ze), (-r, 0, hr), (r, 0, hr)),
            ((X, -Y, ze), (X, Y, ze), (r, 0.01, hr), (r, -0.01, hr)),
            ((-X, Y, ze), (-X, -Y, ze), (-r, -0.01, hr), (-r, 0.01, hr)),
        ]
    else:
        X, Y = L / 2 + beiral_oitao, W / 2 + beiral
        planos = [
            ((-X, -Y, ze), (X, -Y, ze), (X, 0, hr), (-X, 0, hr)),
            ((X, Y, ze), (-X, Y, ze), (-X, 0, hr), (X, 0, hr)),
        ]
    for k, (a, b, c, d) in enumerate(planos):
        _placa_forro(rec, f"{nome}{k}", a, b, c, d, mat)


def _forro_varanda(rec, x0, x1, y_alto, z_alto, y_baixo, z_baixo, mat, mats: Mats):
    """Forro e caibros de bambu da cobertura da varanda (a água única não traz caibros)."""
    a, b = (x0, y_baixo, z_baixo), (x1, y_baixo, z_baixo)
    c, d = (x1, y_alto, z_alto), (x0, y_alto, z_alto)
    _placa_forro(rec, "tel_var_forro", a, b, c, d, mat)
    n = max(2, int((x1 - x0) / 1.1))
    desce = 0.155
    for i in range(1, n):
        x = x0 + (x1 - x0) * i / n
        rec.add(
            V.tre(
                f"tel_var_caibro{i}",
                (x, y_baixo + 0.12, z_baixo - desce + 0.012),
                (x, y_alto - 0.04, z_alto - desce),
                0.03,
                mats.tre,
                segs=5,
                sem=i * 0.31,
            ),
            "Casa",
            "Estrutura",
        )


def _piso_alto(rec, nome, rets, mats: Mats):
    """Piso de tábuas de cima e os barrotes, em um ou mais retângulos (a escada passa no vão)."""
    for k, (x0, y0, x1, y1) in enumerate(rets):
        E.piso_tabuas(rec, f"{nome}{k}", x0, y0, x1, y1, Z2, mats, largura=0.3, sem=k + 1)
        E.barrotes(rec, f"barrote_{nome}{k}", x0, y0, x1, y1, Z2, mats, passo=1.25)


def _moveis_cima(rec, mats: Mats, L, W, esp, xd, sem):
    """Dois cômodos de cima: quarto (x < xd) e sala com altar (x > xd). Antes de subir o corpo."""
    xi, yi = L / 2 - esp, W / 2 - esp
    V.phan(rec, "phan", (-xi + 1.08, -yi + 0.78), 0, mats)
    V.ruong(rec, "arca", (-xi + 0.36, -yi + 2.15), 90, mats)
    V.potes(rec, "lu_q", [(-xi + 0.4, -yi + 3.05)], mats, alts=(0.58,), sem=sem + 1)
    meio = (xd + xi) / 2
    V.ban_tho(rec, "altar", (meio, yi - 0.36), 0, mats)
    V.ban_thap(rec, "mesa", (meio - 0.2, -0.45), 0, mats)
    V.cho_tre(rec, "cho", (xi - 0.56, 0.75), 90, mats)
    V.potes(rec, "lu_s", [(xi - 0.38, -yi + 0.38), (xi - 0.86, -yi + 0.34)], mats, sem=sem + 2)
    V.nonla_pendurado(rec, "nonla", (xd + 0.7, yi), 0, mats)


def _moveis_aberto(rec, mats: Mats, L, W, sem):
    """Térreo aberto: lugar de trabalho e de comer, com a passagem livre entre as colunas."""
    X._bancada(rec, "bancada", (-L / 2 + 2.0, W / 2 - 0.72), 0, mats, comp=2.5)
    V.ban_thap(rec, "mesa_b", (1.55, 0.05), 0, mats)
    X._banco(rec, "banco_a", (1.55, -0.72), 0, mats, comp=1.5, z=PISO)
    X._banco(rec, "banco_b", (1.55, 0.82), 0, mats, comp=1.5, z=PISO)
    X._lenha(rec, "lenha", L / 2 - 2.5, L / 2 - 0.65, W / 2 - 0.42, mats, z=PISO)
    x, y = -L / 2 + 1.1, -W / 2 + 1.0
    V.sacos(
        rec,
        "sacos_a",
        [(x, y, 8), (x + 0.5, y + 0.02, -12), (x + 0.26, y + 0.42, 84)],
        mats,
        z=PISO + 0.02,
    )
    V.sacos(rec, "sacos_b", [(x + 0.2, y + 0.1, 16)], mats, z=PISO + 0.28)
    rec.caixa("sacos", (x + 0.25, y + 0.2, PISO + 0.26), (1.25, 1.05, 0.52), "para", "Fabric")
    X._cesto(rec, "cesto_a", (x + 1.45, y - 0.25), mats, r=0.32, alt=0.5, z=PISO)
    X._cesto(rec, "cesto_b", (x + 1.45, y + 0.42), mats, r=0.25, alt=0.4, z=PISO)
    X._pote(rec, "pote_a", (L / 2 - 0.95, -W / 2 + 0.72), mats, alt=0.72, r=0.32, z=PISO, sem=sem)
    X._pote(
        rec, "pote_b", (L / 2 - 1.62, -W / 2 + 0.62), mats, alt=0.58, r=0.26, z=PISO, sem=sem + 1
    )
    X._caixote(rec, "caixote", (-0.9, W / 2 - 0.62), 8, mats, z=PISO)


def _moveis_fechado(rec, mats: Mats, L, W, esp, xd, x_escada, sem):
    """Térreo fechado: sala de entrada (com a escada ao fundo) e depósito de trabalho."""
    xi, yi = L / 2 - esp, W / 2 - esp
    V.ban_thap(rec, "mesa_b", (x_escada + 1.8, -0.95), 0, mats)
    X._banco(rec, "banco_a", (x_escada + 1.8, -1.72), 0, mats, comp=1.5, z=PISO)
    X._banco(rec, "banco_b", (x_escada + 1.8, -0.15), 0, mats, comp=1.5, z=PISO)
    X._pote(rec, "pote_a", (-xi + 0.42, -yi + 0.42), mats, alt=0.72, r=0.32, z=PISO, sem=sem)
    X._pote(rec, "pote_b", (-xi + 1.08, -yi + 0.36), mats, alt=0.58, r=0.26, z=PISO, sem=sem + 1)
    X._bancada(rec, "bancada", (xi - 0.42, 0.65), 90, mats, comp=2.3, prof=0.66)
    X._prateleira(rec, "estante", ((xd + xi) / 2 - 0.4, yi - 0.24), 0, mats, comp=1.5, z=PISO)
    # sacos encostados na frente, longe da porta da divisória (junto dela, tapavam a passagem)
    x, y = xd + 2.6, -yi + 0.75
    V.sacos(
        rec,
        "sacos_a",
        [(x, y, 8), (x + 0.5, y + 0.02, -12), (x + 0.26, y + 0.42, 84)],
        mats,
        z=PISO + 0.02,
    )
    V.sacos(rec, "sacos_b", [(x + 0.2, y + 0.1, 16)], mats, z=PISO + 0.28)
    rec.caixa("sacos", (x + 0.25, y + 0.2, PISO + 0.26), (1.25, 1.05, 0.52), "para", "Fabric")
    X._caixote(rec, "caixote_a", (xi - 0.5, -yi + 0.45), 90, mats, z=PISO)
    X._caixote(
        rec, "caixote_b", (xi - 0.5, -yi + 0.48), 82, mats, dim=(0.6, 0.5, 0.42), z=PISO + 0.6
    )


def _sobrado(chave: str) -> V.Receita:
    c = SOBRADOS[chave]
    rec = V.Receita()
    sem = c["sem"]
    mats = Mats(sem)
    L, W, esp = c["L"], c["W"], c["esp"]
    aberto = c["aberto"]
    par = c["parede"]()
    ngoi = V.mat_ngoi("ngoi", *c["telha"])
    yv = -W / 2 - VARANDA
    larg_esc = c.get("escada", 1.1)  # D-243: os mapas novos usam 1,40 m
    # ponta da varanda (no aberto, chega à escada)
    xv = L / 2 + 0.25 + larg_esc if aberto else L / 2 + 0.05

    # escada de dentro (só no fechado): ao longo da parede do fundo
    esp_t = 0.2
    x_esc = -L / 2 + esp_t + 0.65
    y_esc = W / 2 - esp_t - 0.62
    yh = W / 2 - esp_t - 1.22  # frente do vão da escada no piso de cima
    xh0, xh1 = x_esc + 0.78, x_esc + ESCADA + 0.02
    xd = xh1 + 1.55 if not aberto else 0.45  # divisória de cima

    # corpo de cima
    marca = rec.marca()
    VC.casa_ret(
        rec,
        mats,
        "sup",
        L,
        W,
        H_SUP,
        esp,
        par,
        [
            {"lado": "frente", "t": -L * 0.23, "estilo": "folhas"},
            {"lado": "frente", "t": L * 0.27, "estilo": "tabua", "folha": 1},
        ],
        [
            {"lado": "frente", "t": -L * 0.40, "w": 0.9, "estilo": "tre"},
            {"lado": "frente", "t": 0.02 * L, "w": 0.9, "estilo": "tre"},
            {"lado": "frente", "t": L * 0.42, "w": 0.9, "estilo": "tre"},
            {"lado": "fundo", "t": -L * 0.33, "w": 0.9, "estilo": "tre"},
            {"lado": "fundo", "t": L * 0.05, "w": 0.9, "estilo": "tre"},
            {"lado": "fundo", "t": L * 0.36, "w": 0.9, "estilo": "tre"},
            {"lado": "esq", "t": -W * 0.2, "w": 0.8, "estilo": "tre"},
            {"lado": "esq", "t": W * 0.2, "w": 0.8, "estilo": "tre"},
            {"lado": "dir", "t": -W * 0.2, "w": 0.8, "estilo": "tre"},
            {"lado": "dir", "t": W * 0.2, "w": 0.8, "estilo": "tre"},
        ],
        col=c["col"],
        sem=sem,
        nen_rets=[],
    )
    div = V.Lado((xd, -W / 2 + esp), math.pi / 2, W - 2 * esp, 0.08, 1.0)
    V.parede(
        rec,
        "divisoria",
        div,
        0.0,
        H_SUP,
        par,
        [(1.3, 1.12, -1.0, PISO + 2.36)],
        c["col"],
        "para",
        sem=sem + 1,
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H_SUP,
        H_SUP + c["cume"],
        0.6,
        c["forma"],
        "ngoi",
        0.1,
        ngoi,
        mats,
        beiral_oitao=0.5,
        sem=sem,
        tesouras=(-L / 4, 0.0, L / 4),
        mat_oitao=par,
        oitao_esp=esp,
        col_oitao=c["col"],
    )
    m_forro = V.mat_phen("phen_par", "#b19a69", "#7f6f4a", passo=0.045)
    _forro_telhado(rec, "tel_forro", L, W, H_SUP, H_SUP + c["cume"], 0.6, 0.5, c["forma"], m_forro)
    _moveis_cima(rec, mats, L, W, esp, xd, sem + 5)
    rec.transformar(marca, V.lugar((0.0, 0.0, Z2 - PISO)))

    # pisos de cima e varanda
    if aberto:
        rets = [(-L / 2 - 0.05, -W / 2, L / 2 + 0.05, W / 2)]
    else:
        rets = [
            (-L / 2 - 0.05, -W / 2, L / 2 + 0.05, yh),
            (-L / 2 - 0.05, yh, xh0, W / 2),
            (xh1, yh, L / 2 + 0.05, W / 2),
        ]
    _piso_alto(rec, "piso", rets, mats)
    _piso_alto(rec, "varanda", [(-L / 2 - 0.05, yv, xv, -W / 2)], mats)
    E.guarda_corpo(rec, "gc_frente", (-L / 2, yv), (xv, yv), Z2, mats, passo=0.9)
    E.guarda_corpo(rec, "gc_esq", (-L / 2, yv), (-L / 2, -W / 2), Z2, mats, passo=0.7)
    E.guarda_corpo(rec, "gc_dir", (xv, yv), (xv, -W / 2), Z2, mats, passo=0.7)

    # colunas da varanda até a cobertura, e a cobertura
    n = c["vaos"]
    xs = [-L / 2 + i * L / n for i in range(n + 1)]
    xs_var = [*xs, xv - 0.08] if aberto else xs
    for k, x in enumerate(xs_var):
        V.poste(rec, f"poste_v{k}", x, yv + 0.06, Z2 + 2.42, mats.go, r=0.09, base_pedra=mats.pedra)
    rec.add(
        V.viga(
            "frechal_v",
            (-L / 2 - 0.1, yv + 0.06, Z2 + 2.42),
            (xv, yv + 0.06, Z2 + 2.42),
            0.12,
            0.13,
            mats.go,
        ),
        "Casa",
        "Estrutura",
    )
    V.agua_unica(
        rec,
        "tel_var",
        -L / 2 - 0.3,
        xv + 0.22,
        -W / 2 + 0.02,
        Z2 + 2.82,
        yv - 0.45,
        Z2 + 2.46,
        0.1,
        "ngoi",
        ngoi,
        mats,
        sem=sem + 2,
    )
    _forro_varanda(
        rec, -L / 2 - 0.3, xv + 0.22, -W / 2 + 0.02, Z2 + 2.82, yv - 0.45, Z2 + 2.46, m_forro, mats
    )

    if aberto:
        # térreo aberto: chão de terra batida, colunas e madres
        V.nen(rec, "chao", -L / 2 - 0.25, yv - 0.15, L / 2 + 0.12, W / 2 + 0.25, mats)
        for k, (x, y) in enumerate((x, y) for x in xs for y in (-W / 2, 0.0, W / 2)):
            if c["pilar"] == "alvenaria":
                _pilar(rec, f"pilar{k}", x, y, Z2 - 0.14, c["mat_pilar"]())
            else:
                V.poste(
                    rec,
                    f"pilar{k}",
                    x,
                    y,
                    Z2 - 0.14,
                    mats.go_escuro,
                    r=0.14,
                    quadrado=False,
                    base_pedra=mats.pedra,
                )
        V.poste(
            rec,
            "pilar_p",
            xv - 0.08,
            -W / 2,
            Z2 - 0.14,
            mats.go_escuro,
            r=0.1,
            base_pedra=mats.pedra,
        )
        for y, x1 in ((yv + 0.06, xv), (-W / 2, xv), (0.0, L / 2 + 0.1), (W / 2, L / 2 + 0.1)):
            rec.add(
                V.viga(
                    f"madre{int(y * 10)}",
                    (-L / 2 - 0.1, y, Z2 - 0.27),
                    (x1, y, Z2 - 0.27),
                    0.13,
                    0.16,
                    mats.go_escuro,
                ),
                "Casa",
                "Estrutura",
            )
        # escada de fora: sobe ao longo do oitão direito até a ponta da varanda
        xe = L / 2 + 0.15 + larg_esc / 2
        E.escada(
            rec,
            "escada",
            (xe, -W / 2 + ESCADA + 0.02, 0.1),
            (xe, -W / 2 + 0.02, Z2),
            larg_esc,
            mats,
        )
        sol = V.bloco(
            "soleira",
            (larg_esc + 0.2, 0.44, 0.1),
            (xe, -W / 2 + ESCADA + 0.12, 0.05),
            mats.pedra,
            chanfro=0.015,
        )
        V.sem_fundo(sol, 0.0)
        rec.add(sol, "Casa", "Estrutura")
        X._col(
            rec,
            "soleira",
            xe - (larg_esc + 0.2) / 2,
            -W / 2 + ESCADA - 0.1,
            0.0,
            xe + (larg_esc + 0.2) / 2,
            -W / 2 + ESCADA + 0.34,
            0.1,
            "para",
            "Ground",
        )
        _moveis_aberto(rec, mats, L, W, sem + 9)
        VC.camera(rec, (-L / 2 + 1.0, -W / 2 + 0.6, Z2 + 1.55), (L / 4, W / 2 - 1.0, Z2 + 0.75))
    else:
        # térreo fechado de alvenaria, com a escada por dentro
        mat_t = c["mat_terreo"]()
        VC.casa_ret(
            rec,
            mats,
            "ter",
            L,
            W,
            Z2 - PISO,
            esp_t,
            mat_t,
            [
                {"lado": "frente", "t": -L * 0.08, "estilo": "folhas"},
                {"lado": "fundo", "t": L * 0.3, "estilo": "tabua", "folha": 1},
            ],
            [
                {"lado": "frente", "t": -L * 0.34, "w": 1.0, "estilo": "tre"},
                {"lado": "frente", "t": L * 0.16, "w": 1.0, "estilo": "tre"},
                {"lado": "frente", "t": L * 0.38, "w": 1.0, "estilo": "tre"},
                {"lado": "esq", "t": -W * 0.12, "w": 0.9, "estilo": "tre"},
                {"lado": "dir", "t": -W * 0.2, "w": 0.9, "estilo": "tre"},
                {"lado": "dir", "t": W * 0.22, "w": 0.9, "estilo": "tre"},
            ],
            col="Concrete",
            sem=sem + 3,
            nen_rets=[(-L / 2, -W / 2, L / 2, W / 2)],
        )
        V.nen(rec, "alpendre", -L / 2 - 0.25, yv - 0.15, L / 2 + 0.25, -W / 2, mats)
        div_t = V.Lado((xd, -W / 2 + esp_t), math.pi / 2, W - 2 * esp_t, 0.12, 1.0)
        V.parede(
            rec,
            "div_terreo",
            div_t,
            0.0,
            Z2 - PISO,
            mat_t,
            [(1.45, 1.2, -1.0, PISO + 2.36)],
            "Concrete",
            "para",
            sem=sem + 4,
        )
        E.escada(
            rec, "escada", (x_esc, y_esc, PISO + 0.02), (x_esc + ESCADA, y_esc, Z2), 1.05, mats
        )
        # guarda-corpo do vão: a frente e o começo; a saída fica livre, para o lado da sala
        E.guarda_corpo(rec, "gc_vao", (xh0, yh), (xh1, yh), Z2, mats, passo=0.7)
        E.guarda_corpo(rec, "gc_vao2", (xh0, yh), (xh0, W / 2 - esp), Z2, mats, passo=0.6)
        _moveis_fechado(rec, mats, L, W, esp_t, xd, x_esc, sem + 9)
        VC.camera(
            rec, (xd + 0.6, -W / 2 + 0.7, PISO + 1.55), (-L / 2 + 1.5, W / 2 - 1.0, PISO + 1.1)
        )
    return rec


SOBRADOS: dict[str, dict] = {
    "exp_sobrado_a": {
        "sem": 91,
        "L": 12.4,
        "W": 7.2,
        "esp": 0.08,
        "aberto": True,
        "vaos": 4,
        "parede": lambda: V.mat_tabua("van"),
        "col": "Wood",
        "pilar": "madeira",
        "forma": "2aguas",
        "cume": 2.3,
        "telha": ("#94563c", "#6e3d2a", "#ad6c48"),
    },
    "exp_sobrado_b": {
        "sem": 92,
        "L": 13.2,
        "W": 7.6,
        "esp": 0.16,
        "aberto": True,
        "vaos": 4,
        "parede": lambda: V.mat_vach_dat("vach_cal", cal="#d6cdb8", exposta=0.25),
        "col": "Earth",
        "pilar": "alvenaria",
        "mat_pilar": lambda: V.mat_gach("gach"),
        "forma": "4aguas",
        "cume": 2.6,
        "telha": ("#7f4a35", "#573225", "#98604a"),
    },
    "exp_sobrado_c": {
        "sem": 93,
        "L": 12.8,
        "W": 8.0,
        "esp": 0.08,
        "aberto": False,
        "vaos": 4,
        "parede": lambda: V.mat_tabua("van"),
        "mat_terreo": lambda: V.mat_gach("gach"),
        "col": "Wood",
        "forma": "2aguas",
        "cume": 2.5,
        "telha": ("#8e5238", "#663a28", "#a76a4c"),
    },
    "exp_sobrado_d": {
        "sem": 94,
        "L": 14.0,
        "W": 7.8,
        "esp": 0.16,
        "aberto": False,
        "vaos": 5,
        "parede": lambda: V.mat_vach_dat("vach_cal", cal="#d9cfb6", exposta=0.2),
        "mat_terreo": lambda: V.mat_trinh("trinh"),
        "col": "Earth",
        "forma": "4aguas",
        "cume": 2.7,
        "telha": ("#86503a", "#5e3628", "#a2684c"),
    },
}


def receita_exp_sobrado_a():
    return _sobrado("exp_sobrado_a")


def receita_exp_sobrado_b():
    return _sobrado("exp_sobrado_b")


def receita_exp_sobrado_c():
    return _sobrado("exp_sobrado_c")


def receita_exp_sobrado_d():
    return _sobrado("exp_sobrado_d")


CASAS: dict[str, dict] = {
    "exp_sobrado_a": {
        "nome": "sobrado de tábua com térreo aberto",
        "tipo": "colunas de madeira, térreo aberto, 2 cômodos em cima, varanda e escada de fora",
        "fontes": ["navy67", "sggp_qngai"],
        "atlas": ATLAS,
    },
    "exp_sobrado_b": {
        "nome": "sobrado caiado com térreo aberto",
        "tipo": "colunas de alvenaria, térreo aberto, 4 águas de telha, varanda e escada de fora",
        "fontes": ["navy67", "sggp_qngai"],
        "atlas": ATLAS,
    },
    "exp_sobrado_c": {
        "nome": "sobrado de tijolo e tábua",
        "tipo": "térreo fechado de tijolo, andar de tábua, escada por dentro e varanda",
        "fontes": ["navy67", "sggp_qngai"],
        "atlas": ATLAS,
    },
    "exp_sobrado_d": {
        "nome": "sobrado de reboco ocre",
        "tipo": "térreo fechado de reboco, andar caiado, 4 águas, escada por dentro e varanda",
        "fontes": ["navy67", "sggp_qngai"],
        "atlas": ATLAS,
    },
}
