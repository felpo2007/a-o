"""Cena-piloto de escala dos mapas retangulares (D-243, prompt 17.1 e 17.6).

Metros, Z para cima, frente em -Y.
- `ret_manequim`: corpo de exatamente 2,00 m nas proporções do boneco de bloco do jogo, com
  régua de 5 m;
- `ret_piloto_casa`: casa compacta de 10 x 8 m sobre esteios (piso a 1,00 m), varanda de
  2,20 m, duas entradas com vão livre de 1,40 x 2,50 m, quarto de 4,50 x 4,00 m com
  pé-direito de 3,00 m, mesa, banco e cama.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import exp_comum as E  # noqa: E402
import exp_vila as X  # noqa: E402
import vila_casas as VC  # noqa: E402
import vila_comum as V  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

ALTURA_CORPO = 2.0
PE_DIREITO = 3.0
Z_PISO = 1.0  # piso acabado acima do chão
VARANDA = 2.2
ESCADA_L = 1.4
ESCADA_AVANCO = 1.72  # 5 degraus de ~0,19 x 0,34 m

ATLAS = {
    "Telhado": {"tex": 1024, "teto": 3600, "amostras_ao": 16},
    "Mobilia": {"tex": 1024, "teto": 6000, "amostras_ao": 16},
    "Casa": {"tex": 1024, "teto": 9000, "amostras_ao": 8},
}


def receita_ret_manequim() -> V.Receita:
    """R15 de bloco: pernas 2, tronco 2 e cabeça 1,2 de altura; tronco 2 e braços 1 de largura."""
    rec = V.Receita()
    u = ALTURA_CORPO / 5.2
    pele = V.mat_liso("man_pele", "#d8bb94", rug=0.6)
    farda = V.mat_liso("man_farda", "#55613d", rug=0.8)
    calca = V.mat_liso("man_calca", "#46502f", rug=0.8)
    pecas = [
        ("perna_e", (u, u, 2 * u), (-0.5 * u, 0, u), calca),
        ("perna_d", (u, u, 2 * u), (0.5 * u, 0, u), calca),
        ("tronco", (2 * u, u, 2 * u), (0, 0, 3 * u), farda),
        ("braco_e", (u, u, 2 * u), (-1.5 * u, 0, 3 * u), farda),
        ("braco_d", (u, u, 2 * u), (1.5 * u, 0, 3 * u), farda),
        ("cabeca", (1.2 * u, 1.2 * u, 1.2 * u), (0, 0, 4.6 * u), pele),
    ]
    for nome, dim, centro, mat in pecas:
        rec.add(V.bloco(nome, dim, centro, mat, chanfro=0.008), "Mobilia", "Manequim")
    claro = V.mat_liso("regua_clara", "#e9e4d4", rug=0.5)
    escuro = V.mat_liso("regua_escura", "#23211d", rug=0.5)
    for k in range(5):
        m = claro if k % 2 == 0 else escuro
        rec.add(V.bloco(f"regua{k}", (0.1, 0.1, 1.0), (1.3, 0, k + 0.5), m), "Mobilia", "Regua")
    # traço horizontal exatamente nos 2,00 m
    rec.add(V.bloco("regua_2m", (1.3, 0.04, 0.012), (0.65, 0.56, 2.0), escuro), "Mobilia", "Regua")
    VC.camera(rec, (3.6, -5.2, 1.5), (0.4, 0, 1.05))
    return rec


def _mesa(rec, nome, pos, rot, mats: Mats, comp=1.6, larg=0.85, alt=0.88):
    o = [V.bloco(f"{nome}_tampo", (comp, larg, 0.05), (0, 0, alt - 0.025), mats.go, chanfro=0.008)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(
                V.bloco(
                    f"{nome}_pe{sx}{sy}",
                    (0.07, 0.07, alt - 0.05),
                    (sx * (comp / 2 - 0.08), sy * (larg / 2 - 0.08), (alt - 0.05) / 2),
                    mats.go_escuro,
                )
            )
    marca = rec.marca()
    rec.addv(o, "Mobilia", "Mobilia")
    rec.caixa(nome, (0, 0, alt / 2), (comp, larg, alt), "para", "Wood")
    rec.transformar(marca, V.lugar((pos[0], pos[1], PISO), rot))


def receita_ret_piloto_casa() -> V.Receita:
    rec = V.Receita()
    sem = 401
    mats = Mats(sem)
    Hp = Z_PISO - PISO
    L, W, esp = 10.0, 8.0, 0.1
    H = PISO + PE_DIREITO
    hr = H + W / 2 * math.tan(math.radians(27))
    van = V.mat_tabua("van")
    x_porta = -2.6
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
        [
            {"lado": "frente", "t": x_porta, "estilo": "van", "folha": -1},
            {"lado": "fundo", "t": x_porta, "estilo": "van", "folha": 1},
        ],
        [
            {
                "lado": "frente",
                "t": 2.5,
                "w": 1.1,
                "z0": 1.05,
                "z1": 2.05,
                "estilo": "tre",
                "aba": True,
            },
            {"lado": "fundo", "t": 2.2, "w": 1.1, "z0": 1.05, "z1": 2.05, "estilo": "tre"},
            {"lado": "esq", "t": 0.0, "w": 1.1, "z0": 1.05, "z1": 2.05, "estilo": "tre"},
            {"lado": "dir", "t": -1.8, "w": 1.1, "z0": 1.05, "z1": 2.05, "estilo": "tre"},
        ],
        col="Wood",
        sem=sem,
        nen_rets=[],
    )
    # quarto de 4,50 x 4,00 m livres, no canto da frente à direita
    xi, yi = L / 2 - esp, W / 2 - esp
    e_div = 0.06
    xd = xi - 4.5 - e_div / 2
    yd = -yi + 4.0 + e_div / 2
    largura_vao = V.PORTA_LARG + 2 * V.BATENTE
    topo_vao = PISO + V.PORTA_ALT + V.BATENTE
    V.parede(
        rec,
        "div_x",
        V.Lado((xd, -yi), math.pi / 2, 4.0, e_div, 1.0),
        0.0,
        H,
        van,
        [(2.05, largura_vao, -1.0, topo_vao)],
        "Wood",
        "para",
        sem=sem + 1,
    )
    V.parede(
        rec,
        "div_y",
        V.Lado((xd - e_div / 2, yd), 0.0, xi - xd + e_div / 2, e_div, 1.0),
        0.0,
        H,
        van,
        (),
        "Wood",
        "para",
        sem=sem + 2,
    )
    E.oitao_tabuas(rec, "oitao", L, W, H, hr, van)
    E.telhado_chapa(rec, "tel", L, W, H, hr, 0.6, mats, sem=sem, ferrugem=0.8)
    # móveis: a linha entre as duas portas (x = -2,6) fica livre
    V.phan(rec, "cama", (xi - 0.78, -yi + 1.35), 90, mats, comp=2.3, larg=1.4, alt=0.55)
    V.ruong(rec, "arca", (xi - 0.5, -yi + 3.3), 90, mats)
    _mesa(rec, "mesa", (-L / 2 + 1.05, 0.9), 90, mats)
    X._banco(rec, "banco_a", (-L / 2 + 0.42, 0.9), 90, mats, comp=1.5, alt=0.52, z=PISO)
    X._banco(rec, "banco_b", (-L / 2 + 1.72, 0.9), 90, mats, comp=1.5, alt=0.52, z=PISO)
    V.potes(rec, "lu", [(xd - 0.42, -yi + 0.42), (xd - 0.95, -yi + 0.36)], mats, sem=sem + 3)
    X._prateleira(rec, "estante", (1.8, yi - 0.24), 0, mats, comp=1.6, z=PISO)
    rec.transformar(marca, V.lugar((0.0, 0.0, Hp)))

    # pisos, barrotes e esteios
    yv = -W / 2 - VARANDA
    E.piso_tabuas(rec, "piso", -L / 2 - 0.05, -W / 2, L / 2 + 0.05, W / 2, Z_PISO, mats, sem=1)
    E.piso_tabuas(rec, "varanda", -L / 2 - 0.05, yv, L / 2 + 0.05, -W / 2, Z_PISO, mats, sem=2)
    E.barrotes(rec, "barrote", -L / 2, yv, L / 2, W / 2, Z_PISO, mats)
    xs = (-L / 2, -L / 4, 0.0, L / 4, L / 2)
    ys = (yv, -W / 2, 0.0, W / 2)
    E.pilotis(rec, "esteio", [(x, y) for x in xs for y in ys], Z_PISO - 0.14, mats)
    for y in ys:
        rec.add(
            V.viga(
                f"madre{int(y * 10)}",
                (-L / 2 - 0.1, y, Z_PISO - 0.27),
                (L / 2 + 0.1, y, Z_PISO - 0.27),
                0.11,
                0.14,
                mats.go_escuro,
            ),
            "Casa",
            "Estrutura",
        )
    # varanda: viga a 2,62 m do piso
    z_baixo = Z_PISO + 2.62
    z_alto = Hp + H - 0.04
    # a escada abre entre dois postes: um poste no meio do vão travava o boneco na subida
    meia = ESCADA_L / 2 + 0.06
    livres = [x for x in xs if abs(x - x_porta) > meia + 0.3]
    for x in [*livres, x_porta - meia - 0.04, x_porta + meia + 0.04]:
        V.poste(rec, f"p_var{int(x * 10)}", x, yv + 0.05, z_baixo, mats.go, r=0.07)
    E.telhado_varanda(
        rec,
        "tel_var",
        -L / 2 - 0.3,
        L / 2 + 0.3,
        -W / 2 + 0.02,
        z_alto,
        yv - 0.45,
        z_baixo - 0.02,
        mats,
        sem,
    )
    E.guarda_corpo(rec, "gc_f_a", (-L / 2, yv), (x_porta - meia, yv), Z_PISO, mats)
    E.guarda_corpo(rec, "gc_f_b", (x_porta + meia, yv), (L / 2, yv), Z_PISO, mats)
    E.guarda_corpo(rec, "gc_esq", (-L / 2, yv), (-L / 2, -W / 2), Z_PISO, mats)
    E.guarda_corpo(rec, "gc_dir", (L / 2, yv), (L / 2, -W / 2), Z_PISO, mats)
    E.escada(
        rec,
        "escada",
        (x_porta, yv - ESCADA_AVANCO, 0.04),
        (x_porta, yv + 0.02, Z_PISO),
        ESCADA_L,
        mats,
    )
    # segunda entrada: patamar e escada nos fundos
    y_pat = W / 2 + 1.5
    E.piso_tabuas(rec, "patamar", x_porta - 0.9, W / 2, x_porta + 0.9, y_pat, Z_PISO, mats, sem=3)
    E.pilotis(
        rec,
        "esteio_pat",
        [(x_porta - 0.85, y_pat), (x_porta + 0.85, y_pat)],
        Z_PISO - 0.14,
        mats,
    )
    E.escada(
        rec,
        "escada_f",
        (x_porta, y_pat + ESCADA_AVANCO, 0.04),
        (x_porta, y_pat - 0.02, Z_PISO),
        ESCADA_L,
        mats,
    )
    VC.camera(rec, (-4.3, -2.9, Z_PISO + 1.62), (3.2, 2.2, Z_PISO + 0.9))
    return rec


CASAS: dict[str, dict] = {
    "ret_manequim": {
        "nome": "manequim de 2,00 m e régua",
        "tipo": "calibração de escala (prompt 17.1)",
        "fontes": [],
        "atlas": {"Mobilia": {"tex": 256, "teto": 600, "amostras_ao": 4}},
    },
    "ret_piloto_casa": {
        "nome": "casa-piloto sobre esteios",
        "tipo": "10 x 8 m, piso a 1,00 m, varanda de 2,20 m, duas entradas, quarto de 4,5 x 4 m",
        "fontes": [],
        "atlas": ATLAS,
    },
}
