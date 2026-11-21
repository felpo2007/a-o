"""Receitas das 10 casas únicas da vila (`vila_casa_01` … `vila_casa_10`) e o catálogo com as
fontes do estilo, as medidas e os atlas.

Roda dentro do Python do Blender (importa `vila_comum`). Tudo em metros, Z para cima, frente
(porta principal) em -Y. A `vila.py` monta a receita, assa os atlas e grava o GLB.

Estilo (casas rurais do litoral do centro do Vietnã, 1965), com as fontes em `FONTES`:
- cobertura de palha de arroz/capim (tranh, rạ) ou de folha de nipa (lá dừa nước); telha
  (ngói) nas casas de quem tinha mais; zinco começava a aparecer (navy67);
- paredes de barro batido sobre trama de bambu (vách đất), bambu trançado (phên), tijolo
  rebocado, taipa (tường trình) ou tábuas (nhà rường);
- 1 ou 3 vãos (gian) e alas (chái); 4 águas comum do Quảng Bình para o sul (vjol2024);
- altar dos ancestrais no vão do meio, de frente para a porta (navy67, plo_3gian);
- cozinha separada ou num puxado (chái bếp) (plo_3gian, sggp_nho);
- abrigo antiaéreo da família (hầm chữ A) junto da casa (hamA, schell68).
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vila_comum as V  # noqa: E402
from vila_comum import PISO, Mats  # noqa: E402

FONTES = {
    "navy67": "U.S. Navy, Chaplains Division, 'The Religions of South Vietnam in Faith and Fact' "
    "(1967), cap. sobre a casa e o altar (sacred-texts.com/asia/rsv/rsv18.htm): telhado de palha "
    "ou "
    "de folha de palmeira, telha ou zinco nas outras; barro batido sobre bambu trançado; casa de "
    "3 a "
    "5 cômodos; altar dos ancestrais no lugar de honra do cômodo principal",
    "vjol2024": "Tạp chí Viện Kiến trúc (vjol.info.vn/VIENKIENTRUCVN, art. 99557, 2024; lido no "
    "resumo da busca, o PDF não abriu): casa tradicional do centro curta, de 1 ou 3 vãos; do Quảng "
    "Bình para o sul é comum a casa de 4 águas (sobretudo 'mái nửa chỏm')",
    "plo_3gian": "Báo Pháp Luật (plo.vn), 'Nhà 3 gian của gia chủ ở Quảng Nam': os 3 vãos do meio "
    "para receber, cultuar e descansar; as 2 alas (chái) para cozinha, depósito ou quarto",
    "sggp_qngai": "SGGP (sggp.org.vn), casas antigas de um colecionador: no centro, e em Quảng "
    "Ngãi, "
    "pilares e tesouras de madeira grossos contra tufão e enchente",
    "sggp_nho": "SGGP (sggp.org.vn), 'Những nhớ nhung ngày cũ': casa de palha do centro, capim "
    "tranh "
    "tirado das encostas, cozinha de puxado enegrecida de fumaça, phên de bambu",
    "goco": "Báo Văn hóa (baovanhoa.vn), 'Về Gò Cỏ ngủ nhà tranh': casa de palha com parede de "
    "barro, catre de bambu, feita de bambu, argila e palha",
    "hamA": "Báo Văn hóa (baovanhoa.vn), 'Trải nghiệm hầm chữ A': abrigo em A da guerra contra os "
    "EUA, cova de 1 a 1,2 m de fundo, 1 m de largura e 1,5 m de comprimento, armação de bambu e "
    "madeira em A",
    "schell68": "J. Schell, 'The Military Half' (1968), sobre Quảng Ngãi e Quảng Tin em 1967: "
    "abrigos antiaéreos de família nas vilas, junto das casas",
    "dtic_ducpho": "DTIC AD0683375 (túneis e esconderijos em Đức Phổ–Mộ Đức, Quảng Ngãi): "
    "entradas na "
    "beira de touceiras de bambu",
    "water_jar": "assets/blender/water_jar/metricas.json: pote de 0,59 a 0,75 m (anúncios de "
    "antiquário de jarras vietnamitas)",
    "conical_hat": "assets/blender/conical_hat/metricas.json: nón lá de Ø 0,40 × 0,19 m",
    "dono": "decisão do dono (soldado do jogo de 2,0 m): porta com vão livre de 1,00 × 2,30 m",
}

# medidas comuns a todas as casas
MEDIDAS_COMUNS = {
    "porta_vao_livre_m": [[1.0, 2.3], FONTES["dono"]],
    "piso_terra_batida_m": [PISO, "PLACEHOLDER (nền elevado; sem fonte de altura)"],
    "altura_parede_m": [
        None,
        "PLACEHOLDER: puxada para cima pela porta de 2,3 m (casas reais "
        "tinham beiral baixo, perto de 1,8 m, sem fonte medida)",
    ],
    "abrigo_hầm_chữ_A_m": [
        [1.5, 1.0, 1.1],
        f"{FONTES['hamA']}; a cova não foi modelada (precisa "
        "cavar o terreno): o monte de terra (PLACEHOLDER) e a boca em A ficam "
        "acima do chão",
    ],
    "pote_m": [0.7, FONTES["water_jar"]],
    "nón_lá_m": [[0.4, 0.19], FONTES["conical_hat"]],
    "moveis": [
        None,
        "PLACEHOLDER: catre, phản, mesa baixa, altar, tulha, fogão e ferramentas sem "
        "medida publicada; tamanhos de uso comum",
    ],
}

# `fracoes`: alvos tentados (fração do teto). Os atlas de peças pequenas só tentam perto do teto:
# com 40% do teto a redução apagava xícaras e varas sem passar da tolerância (que é relativa à
# diagonal do atlas inteiro, ~10 m).
ATLAS_PADRAO = {
    "Telhado": {"tex": 1024, "teto": 2200, "visibilidade": True, "suave": 70, "amostras_ao": 64},
    "Casa": {
        "tex": 1024,
        "teto": 3200,
        "visibilidade": False,
        "suave": 40,
        "fracoes": (0.8, 1.0),
        "forca_ao": 0.4,
        "amostras_ao": 64,
    },
    "Mobilia": {
        "tex": 1024,
        "teto": 3600,
        "visibilidade": False,
        "suave": 50,
        "fracoes": (0.85, 1.0),
        "forca_ao": 0.35,
        "amostras_ao": 64,
    },
}


# =============================================================== peças compostas
def casa_ret(
    rec,
    mats: Mats,
    nome,
    L,
    W,
    H,
    esp,
    mat_par,
    portas=(),
    janelas=(),
    col="Earth",
    bala="para",
    chanfro=0.0,
    cx=0.0,
    cy=0.0,
    lados_usar=("frente", "fundo", "esq", "dir"),
    nen_rets=None,
    vaos_extra=None,
    z0=0.0,
    sem=0,
    postes_tre=False,
):
    """Retângulo de paredes L × W com portas [{lado, t, estilo, folha, registrar}] e janelas
    [{lado, t, w, z0, z1, estilo, aba}], o piso (nền) com 0,25 m de beirada (ou `nen_rets`) e,
    com `postes_tre`, os postes de bambu por fora (parede de phên)."""
    rec.extras.setdefault("corpos", []).append(
        {"nome": nome, "L": L, "W": W, "parede": H, "espessura": esp}
    )
    lados = V.lados_ret(cx, cy, L, W, esp)
    vaos = {k: [] for k in lados}
    for p in portas:
        vaos[p["lado"]].append(V.vao_porta(p["t"], lados[p["lado"]]))
    for j in janelas:
        vaos[j["lado"]].append(
            V.vao_janela(
                j["t"], lados[j["lado"]], j.get("w", 0.75), j.get("z0", 1.05), j.get("z1", 1.75)
            )
        )
    for k, v in (vaos_extra or {}).items():
        vaos[k] += v
    m = 0.25
    for i, r in enumerate(
        nen_rets
        if nen_rets is not None
        else [(cx - L / 2 - m, cy - W / 2 - m, cx + L / 2 + m, cy + W / 2 + m)]
    ):
        V.nen(rec, f"{nome}_nen{i}", *r, mats)
    for k in lados_usar:
        V.parede(
            rec,
            f"{nome}_{k}",
            lados[k],
            z0,
            H,
            mat_par,
            vaos[k],
            col,
            bala,
            chanfro=chanfro,
            sem=sem,
        )
        if postes_tre:
            V.postes_parede(rec, f"{nome}_{k}_postes", lados[k], H, mats, vaos[k])
    for i, p in enumerate(portas):
        V.porta(
            rec,
            f"{nome}_porta{i}",
            lados[p["lado"]],
            p["t"],
            mats,
            p.get("estilo", "liep"),
            lado_folha=p.get("folha", 1),
            registrar=p.get("registrar", True),
        )
    for i, j in enumerate(janelas):
        V.janela(
            rec,
            f"{nome}_jan{i}",
            lados[j["lado"]],
            j["t"],
            mats,
            j.get("w", 0.75),
            j.get("z0", 1.05),
            j.get("z1", 1.75),
            j.get("estilo", "grade"),
            j.get("aba", False),
        )
    return lados, vaos


def cozinha(
    rec,
    mats: Mats,
    nome,
    pos,
    rot,
    mat_par,
    mat_tel,
    tipo_tel,
    col="Earth",
    bala="para",
    L=2.8,
    W=2.4,
    H=2.65,
    hr=3.9,
    esp=0.12,
    phen=False,
    sem=0,
    ferr=False,
):
    """Nhà bếp: cozinha separada de 1 vão (porta na frente, telhado de 2 águas), com fogão de
    barro, lenha, pote d'água e, com `ferr`, as ferramentas."""
    marca = rec.marca()
    casa_ret(
        rec,
        mats,
        nome,
        L,
        W,
        H,
        esp,
        mat_par,
        [{"lado": "frente", "t": 0.25, "estilo": "nada"}],
        [],
        col,
        bala,
        sem=sem,
        postes_tre=phen,
        nen_rets=[(-L / 2 - 0.12, -W / 2 - 0.12, L / 2 + 0.12, W / 2 + 0.12)],
    )
    V.telhado(
        rec,
        f"{nome}_tel",
        L,
        W,
        H,
        hr,
        0.4,
        "2aguas",
        tipo_tel,
        0.22 if tipo_tel != "ngoi" else 0.1,
        mat_tel,
        mats,
        beiral_oitao=0.3,
        sem=sem,
        mat_oitao=mat_par,
        oitao_esp=esp,
        col_oitao=col,
    )
    V.bep(rec, f"{nome}_bep", (-0.55, 0.45), 0, mats)
    o = V.chum(f"{nome}_pote", (0.95, 0.7), mats, alt=0.66, r=0.28, tampa="madeira", sem=sem + 5)
    rec.addv(o, "Mobilia", "Mobilia")
    rec.caixa(f"{nome}_pote", (0.95, 0.7, PISO + 0.33), (0.56, 0.56, 0.66), "para", "Ceramic")
    if ferr:
        V.ferramentas(
            rec, f"{nome}_ferr", (-L / 2 + esp, -0.95), 90, mats, itens=("enxada", "ancinho")
        )
    rec.transformar(marca, V.lugar((pos[0], pos[1], 0.0), rot))


def camera(rec, pos, alvo):
    rec.extras["camera_dentro_m"] = [list(pos), list(alvo)]


# =============================================================== casas
# Limite do mapa (agente do mapa, vila central Xóm Gò): cada casa, com beirais e anexos, cabe num
# quadrado de LIMITE_PEGADA m; porta com vão livre de pelo menos 2,1 m (aqui 2,3 m, do dono).
LIMITE_PEGADA = 8.5


def receita_vila_casa_01():
    """Nhà tranh vách đất ba gian: lavrador. 3 vãos, 4 águas de palha de arroz, barro sobre
    bambu, janelas de grade de bambu com aba escorada, fogão de barro no vão da direita e abrigo
    em A no terreiro da frente."""
    rec = V.Receita()
    mats = Mats(1)
    L, W, H, esp = 6.6, 4.4, 2.75, 0.18
    par = V.mat_vach_dat("vach_dat", exposta=0.4)
    tranh = V.mat_tranh("tranh")
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        par,
        [{"lado": "frente", "t": 0.0, "estilo": "liep", "folha": -1}],
        [
            {"lado": "frente", "t": -2.2, "estilo": "tre", "aba": True},
            {"lado": "frente", "t": 2.2, "estilo": "tre", "aba": True},
            {"lado": "fundo", "t": 1.8, "w": 0.6, "estilo": "tre"},
            {"lado": "esq", "t": 0.0, "w": 0.6, "estilo": "tre"},
        ],
        chanfro=0.02,
        sem=1,
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.6,
        0.45,
        "4aguas",
        "tranh",
        0.3,
        tranh,
        mats,
        sem=1,
        tesouras=(-1.1, 1.1),
    )
    xi, yi = L / 2 - esp, W / 2 - esp
    V.ban_tho(rec, "altar", (0.0, yi - 0.36), 0, mats)
    V.phan(rec, "phan", (-2.05, 1.2), 0, mats)
    V.cho_tre(rec, "cho", (2.1, 1.35), 0, mats)
    V.ban_thap(rec, "mesa", (-1.6, -0.6), 0, mats)
    V.bep(rec, "bep", (2.35, -1.35), 180, mats)
    V.potes(rec, "lu", [(1.35, -1.7), (0.92, -1.78)], mats, sem=11)
    V.ferramentas(
        rec, "ferr", (-xi, -1.6), 90, mats, arado=True, itens=("enxada", "ancinho", "nia", "foice")
    )
    V.rede_pendurada(rec, "rede", (xi - 0.12, -0.05), 90, mats, comp=1.5, queda=1.3)
    V.nonla_pendurado(rec, "nonla", (-1.0, yi), 0, mats)
    V.ham_chu_a(rec, "abrigo", (-1.9, -4.3), 180, mats)
    V.jarro_agua(rec, "jarro", (1.0, -2.85), mats)
    camera(rec, (0.5, -1.5, PISO + 1.6), (-0.6, 1.6, PISO + 0.95))
    return rec


def receita_vila_casa_02():
    """Nhà lá dừa nước: pescador. Paredes de bambu trançado (phên) em postes de bambu, 2 águas
    de nipa com oitões de phên, varanda de nipa na frente, redes, nơm, cesto-barco (thúng chai)
    encostado no oitão e varal de redes no terreiro; fogão dentro de casa."""
    rec = V.Receita()
    mats = Mats(2)
    L, W, H, esp = 6.0, 4.0, 3.0, 0.08
    phen = V.mat_phen("phen_par", "#b19a69", "#7f6f4a", passo=0.045)
    la = V.mat_la("la")
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        phen,
        [{"lado": "frente", "t": 0.0, "estilo": "liep"}],
        [
            {"lado": "esq", "t": 0.3, "w": 0.7, "estilo": "tre", "aba": True},
            {"lado": "dir", "t": -0.4, "w": 0.7, "estilo": "tre", "aba": True},
        ],
        col="Bamboo",
        bala="passa",
        sem=2,
        postes_tre=True,
        nen_rets=[(-L / 2 - 0.2, -W / 2 - 1.55, L / 2 + 0.2, W / 2 + 0.2)],
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.7,
        0.4,
        "2aguas",
        "la",
        0.2,
        la,
        mats,
        beiral_oitao=0.3,
        sem=2,
        tesouras=(-1.0, 1.0),
        mat_oitao=phen,
        oitao_esp=esp,
        col_oitao="Bamboo",
    )
    V.agua_unica(
        rec,
        "var",
        -L / 2 - 0.25,
        L / 2 + 0.25,
        -W / 2 - 0.3,
        2.64,
        -W / 2 - 1.55,
        2.38,
        0.16,
        "la",
        la,
        mats,
        sem=21,
        postes=(-2.6, -0.9, 0.9, 2.6),
    )
    yi, xi = W / 2 - esp, L / 2 - esp
    V.ban_tho(rec, "altar", (0.0, yi - 0.3), 0, mats, comp=1.0, prof=0.5, alt=0.95)
    V.cho_tre(rec, "cho", (-1.85, 1.35), 0, mats)
    V.ban_thap(rec, "mesa", (-1.45, -0.5), 0, mats, banquinhos=2)
    V.bep(rec, "bep", (2.2, 1.4), 180, mats)
    V.rede_monte(rec, "rede_m", (2.2, -0.75), 10, mats, sem=3)
    V.rede_pendurada(rec, "rede", (-xi + 0.12, -0.85), 90, mats, comp=1.3, queda=1.25)
    V.nom(rec, "nom1", (0.95, -1.6), mats)
    V.nom(rec, "nom2", (2.55, -1.6), mats)
    rec.addv(
        V.chum("lu", (1.7, -1.62), mats, alt=0.6, r=0.27, tampa="palha", sem=6),
        "Mobilia",
        "Mobilia",
    )
    rec.caixa("lu", (1.7, -1.62, PISO + 0.3), (0.5, 0.5, 0.6), "para", "Ceramic")
    V.nonla_pendurado(rec, "nonla", (-0.95, yi), 0, mats)
    # varanda e terreiro
    V.rede_monte(
        rec,
        "rede_var",
        (-1.8, -2.9),
        -15,
        mats,
        larg=1.2,
        prof=0.8,
        sem=5,
        grupo="Casa",
        no="Anexos",
        z=PISO,
    )
    V.varal_redes(rec, "varal", (0.3, -4.55), 2, mats, comp=3.0)
    V.thung_chai(rec, "thung", (-L / 2 - 0.75, 0.3), -90, mats)
    V.jarro_agua(rec, "jarro", (1.2, -2.8), mats, z=PISO)
    V.nom(rec, "nom3", (2.2, -3.0), mats, grupo="Casa", no="Anexos", deitado=True)
    camera(rec, (0.45, -1.55, PISO + 1.6), (-0.6, 1.5, PISO + 0.85))
    return rec


def receita_vila_casa_03():
    """Nhà ngói: família de mais posses. Tijolo rebocado, 4 águas de telha, 3 portas de folhas de
    madeira, varanda de telha em colunas de madeira, armário-altar, mesa de chá com cadeiras,
    phản, catre, arca, tulha e potes."""
    rec = V.Receita()
    mats = Mats(3)
    L, W, H, esp = 7.2, 4.6, 3.1, 0.25
    gach = V.mat_gach("gach", exposto=0.25)
    ngoi = V.mat_ngoi("ngoi")
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        gach,
        [
            {"lado": "frente", "t": 0.0, "estilo": "folhas"},
            {"lado": "frente", "t": -2.4, "estilo": "folhas"},
            {"lado": "frente", "t": 2.4, "estilo": "folhas"},
        ],
        [
            {"lado": "fundo", "t": -1.8},
            {"lado": "fundo", "t": 1.8},
            {"lado": "esq", "t": 0.0, "w": 0.6},
            {"lado": "dir", "t": 0.0, "w": 0.6},
        ],
        col="Brick",
        sem=3,
        nen_rets=[(-L / 2 - 0.25, -W / 2 - 1.5, L / 2 + 0.25, W / 2 + 0.25)],
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.85,
        0.5,
        "4aguas",
        "ngoi",
        0.12,
        ngoi,
        mats,
        sem=3,
        tesouras=(-1.2, 1.2),
    )
    V.agua_unica(
        rec,
        "var",
        -L / 2 - 0.15,
        L / 2 + 0.15,
        -W / 2 - 0.3,
        2.76,
        -W / 2 - 1.5,
        2.44,
        0.1,
        "ngoi",
        ngoi,
        mats,
        sem=31,
        postes=(-3.3, -1.2, 1.2, 3.3),
        mat_poste=mats.go_escuro,
    )
    yi = W / 2 - esp
    V.ban_tho(rec, "altar", (0.0, yi - 0.86), 0, mats, rico=True)
    V.cadeiras_mesa(rec, "cha", (0.0, 0.05), 0, mats)
    V.phan(rec, "phan", (-2.35, 1.2), 0, mats)
    V.cho_tre(rec, "cho", (2.4, 1.35), 0, mats)
    V.ruong(rec, "ruong", (-3.05, -0.55), 90, mats)
    V.bo_lua(rec, "bolua", (3.0, -0.45), mats, r=0.38)
    V.potes(rec, "lu", [(3.05, 0.42)], mats, alts=(0.5,), sem=31)
    V.nonla_pendurado(rec, "nonla", (-2.2, yi), 0, mats)
    V.jarro_agua(rec, "jarro", (3.4, -3.3), mats, z=PISO)
    camera(rec, (0.9, -1.65, PISO + 1.6), (-0.2, 1.8, PISO + 1.15))
    return rec


def receita_vila_casa_04():
    """Nhà tường trình chữ L: taipa de terra socada (0,35 m), planta em L (corpo de 3 vãos + ala
    de trás com cozinha e depósito), 2 águas de palha com oitões de taipa e cumeeira cruzada na
    ala, que tem porta própria para o terreiro."""
    rec = V.Receita()
    mats = Mats(4)
    L, W, H, esp = 6.4, 4.2, 2.75, 0.35
    trinh = V.mat_trinh("trinh")
    tranh = V.mat_tranh("tranh", ("#3a3122", "#665a42", "#857656", "#9f8d68"))
    xa, Lw, y1 = 1.8, 2.8, 4.75  # ala: centro x, largura, fundo
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        trinh,
        [
            {"lado": "frente", "t": -0.8, "estilo": "tabua", "folha": 1},
            {"lado": "fundo", "t": xa, "estilo": "nada", "registrar": False},
        ],
        [{"lado": "frente", "t": 1.7, "w": 0.7}, {"lado": "esq", "t": 0.0, "w": 0.6}],
        sem=4,
        nen_rets=[
            (-L / 2 - 0.25, -W / 2 - 0.25, L / 2 + 0.25, W / 2 + 0.25),
            (xa - Lw / 2 - 0.2, W / 2 - 0.1, xa + Lw / 2 + 0.2, y1 + 0.2),
        ],
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.55,
        0.45,
        "2aguas",
        "tranh",
        0.3,
        tranh,
        mats,
        beiral_oitao=0.35,
        sem=4,
        tesouras=(-1.05, 1.05),
        mat_oitao=trinh,
        oitao_esp=esp,
    )
    y0 = W / 2 - esp
    casa_ret(
        rec,
        mats,
        "ala",
        Lw,
        y1 - y0,
        H,
        esp,
        trinh,
        [{"lado": "dir", "t": -0.4, "estilo": "tabua", "folha": -1}],
        [{"lado": "fundo", "t": 0.0, "w": 0.5}],
        cx=xa,
        cy=(y0 + y1) / 2,
        lados_usar=("fundo", "esq", "dir"),
        sem=5,
        nen_rets=[],
    )
    V.telhado(
        rec,
        "tel_ala",
        y1 - W / 2,
        Lw,
        H,
        4.15,
        0.4,
        "2aguas",
        "tranh",
        0.28,
        tranh,
        mats,
        beiral_oitao=0.3,
        sem=5,
        mat_oitao=trinh,
        oitao_esp=esp,
        m_lugar=V.lugar((xa, (W / 2 + y1) / 2, 0.0), 90),
    )
    yi = W / 2 - esp
    V.ban_tho(rec, "altar", (-0.8, yi - 0.36), 0, mats)
    V.phan(rec, "phan", (-2.15, 0.0), 90, mats)
    V.cho_tre(rec, "cho", (1.6, -1.15), 0, mats)
    V.ban_thap(rec, "mesa", (0.55, 0.25), 15, mats)
    V.potes(rec, "lu", [(2.5, 0.3), (2.45, -0.3)], mats, alts=(0.6, 0.5), sem=41)
    V.nonla_pendurado(rec, "nonla", (0.6, -yi), 180, mats)
    # ala: cozinha e depósito
    V.bep(rec, "bep", (xa - 0.55, y1 - esp - 0.55), 0, mats)
    V.bo_lua(rec, "bolua", (xa + 0.65, y1 - esp - 0.45), mats, r=0.33, alt=0.9)
    V.ferramentas(
        rec, "ferr", (xa - Lw / 2 + esp, W / 2 + 0.05), 90, mats, itens=("enxada", "ancinho")
    )
    V.jarro_agua(rec, "jarro", (0.4, -2.75), mats)
    camera(rec, (1.2, -1.1, PISO + 1.6), (-1.0, 1.5, PISO + 0.9))
    return rec


def receita_vila_casa_05():
    """Nhà một gian: casa pobre de um cômodo. Barro gasto mostrando a trama de bambu, 2 águas
    de palha, fogão dentro, catre de bambu e altar pequeno, cerca baixa com passagem e abrigo em A
    atrás."""
    rec = V.Receita()
    mats = Mats(5)
    L, W, H, esp = 4.6, 3.8, 2.7, 0.14
    par = V.mat_vach_dat("vach_dat", "#7f6447", "#55402c", "#9a7d5a", exposta=0.85)
    tranh = V.mat_tranh("tranh", ("#3b3325", "#5f5541", "#7a6e55", "#93856a"))
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        par,
        [{"lado": "frente", "t": -0.6, "estilo": "liep", "folha": 1}],
        [{"lado": "dir", "t": 0.2, "w": 0.55, "estilo": "tre", "aba": True}],
        chanfro=0.02,
        sem=5,
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.3,
        0.45,
        "2aguas",
        "tranh",
        0.28,
        tranh,
        mats,
        beiral_oitao=0.3,
        sem=5,
        mat_oitao=par,
        oitao_esp=esp,
    )
    yi, xi = W / 2 - esp, L / 2 - esp
    V.cho_tre(rec, "cho", (-1.05, yi - 0.55), 0, mats)
    V.ban_tho(rec, "altar", (1.05, yi - 0.24), 0, mats, comp=0.8, prof=0.42, alt=0.95, painel=False)
    V.bep(rec, "bep", (1.55, -0.85), 90, mats)
    V.potes(rec, "lu", [(1.95, 0.45), (1.95, 0.95)], mats, alts=(0.55, 0.5), sem=51)
    V.ferramentas(rec, "ferr", (-xi, -1.65), 90, mats, itens=("enxada", "nia", "foice"))
    V.nonla_pendurado(rec, "nonla", (-1.2, yi), 0, mats, z=1.75)
    V.ham_chu_a(rec, "abrigo", (0.6, 3.95), 0, mats)
    V.cerca(
        rec,
        "cerca",
        [(-2.4, -2.95), (-1.2, -2.95), (0.0, -2.95), (2.4, -2.95)],
        mats,
        alt=1.0,
        portao=1,
    )
    V.jarro_agua(rec, "jarro", (0.75, -2.45), mats)
    camera(rec, (-0.55, -1.3, PISO + 1.55), (0.7, 1.4, PISO + 0.9))
    return rec


def receita_vila_casa_06():
    """Nhà rường: casa de madeira de família de posses. Paredes de tábuas em armação de postes,
    4 águas de telha com beiral largo, 3 portas, 4 colunas redondas por dentro com tesouras,
    armário-altar, mesa e cadeiras, dois phản, arca, tulha e potes."""
    rec = V.Receita()
    mats = Mats(6)
    L, W, H, esp = 7.2, 5.2, 3.0, 0.1
    van = V.mat_tabua("van")
    ngoi = V.mat_ngoi("ngoi", "#8a5038", "#643826", "#a4664a")
    arm = casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        van,
        [
            {"lado": "frente", "t": 0.0, "estilo": "folhas"},
            {"lado": "frente", "t": -2.3, "estilo": "folhas"},
            {"lado": "frente", "t": 2.3, "estilo": "tabua", "folha": -1},
        ],
        [
            {"lado": "fundo", "t": -2.0},
            {"lado": "fundo", "t": 2.0},
            {"lado": "esq", "t": 0.0, "w": 0.8},
            {"lado": "dir", "t": 0.0, "w": 0.8},
        ],
        col="Wood",
        sem=6,
        nen_rets=[(-L / 2 - 0.3, -W / 2 - 0.45, L / 2 + 0.3, W / 2 + 0.3)],
    )
    # armação: postes nas paredes (aparentes por dentro e por fora), fora dos vãos
    lados, vaos = arm
    for k, lado in lados.items():
        n = max(2, round(lado.comp / 1.5))
        for i in range(n + 1):
            u = lado.comp * i / n
            if any(abs(u - c) < w_ / 2 + 0.1 for c, w_, _, _ in vaos[k]):
                continue
            p = lado.ponto(u)
            rec.add(
                V.bloco(
                    f"arm_{k}{i}", (0.16, 0.16, H), (p.x, p.y, H / 2), mats.go_escuro, chanfro=0.012
                ),
                "Casa",
                "Estrutura",
            )
        a, b = lado.ponto(0.0, 0.0, H - 0.05), lado.ponto(lado.comp, 0.0, H - 0.05)
        rec.add(V.viga(f"travessa_{k}", a, b, 0.16, 0.1, mats.go_escuro), "Casa", "Estrutura")
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        5.0,
        0.55,
        "4aguas",
        "ngoi",
        0.12,
        ngoi,
        mats,
        sem=6,
        tesouras=(-1.2, 1.2),
    )
    for x in (-1.2, 1.2):
        for y in (-1.0, 1.0):
            V.poste(
                rec,
                f"col{x}{y}",
                x,
                y,
                H - 0.08,
                mats.go_escuro,
                r=0.1,
                quadrado=False,
                base_pedra=mats.pedra,
            )
    yi = W / 2 - esp
    V.ban_tho(rec, "altar", (0.0, yi - 0.86), 0, mats, rico=True)
    V.cadeiras_mesa(rec, "cha", (0.0, 0.15), 0, mats)
    V.phan(rec, "phan1", (-2.5, 1.75), 0, mats)
    V.phan(rec, "phan2", (-2.55, -0.8), 0, mats, esteira=False)
    V.ruong(rec, "ruong", (2.95, 2.1), 0, mats)
    V.bo_lua(rec, "bolua", (2.9, 0.75), mats)
    V.potes(rec, "lu", [(3.1, -0.55), (2.6, -0.7)], mats, sem=61)
    V.sacos(rec, "saco", [(2.15, 1.75, 30), (2.25, 2.15, -10)], mats)
    V.jarro_agua(rec, "jarro", (3.3, -3.3), mats)
    camera(rec, (0.25, -2.0, PISO + 1.6), (0.0, 2.1, PISO + 1.25))
    return rec


def receita_vila_casa_07():
    """Nhà tranh có hầm trong nhà: barro caiado, 2 águas de palha com varanda de palha na frente
    toda, e o abrigo da família DENTRO de casa (monte de terra com a boca em A no vão da
    esquerda), redes e ferramentas na varanda."""
    rec = V.Receita()
    mats = Mats(7)
    L, W, H, esp = 7.0, 4.6, 3.0, 0.18
    par = V.mat_vach_dat("vach_cal", cal="#d6cdb8", exposta=0.25)
    tranh = V.mat_tranh("tranh", ("#40372a", "#6f6249", "#928160", "#ad9a72"))
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        par,
        [{"lado": "frente", "t": 0.0, "estilo": "liep", "folha": -1}],
        [
            {"lado": "frente", "t": -2.3, "estilo": "tre", "aba": True},
            {"lado": "frente", "t": 2.3, "estilo": "tre", "aba": True},
            {"lado": "fundo", "t": -1.8, "w": 0.6, "estilo": "tre"},
        ],
        chanfro=0.02,
        sem=7,
        nen_rets=[(-L / 2 - 0.2, -W / 2 - 1.45, L / 2 + 0.2, W / 2 + 0.2)],
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.8,
        0.45,
        "2aguas",
        "tranh",
        0.3,
        tranh,
        mats,
        beiral_oitao=0.3,
        sem=7,
        tesouras=(-1.15, 1.15),
        mat_oitao=par,
        oitao_esp=esp,
    )
    V.agua_unica(
        rec,
        "var",
        -L / 2 - 0.25,
        L / 2 + 0.25,
        -W / 2 - 0.35,
        2.62,
        -W / 2 - 1.45,
        2.32,
        0.22,
        "tranh",
        tranh,
        mats,
        sem=71,
        postes=(-3.1, -1.1, 1.1, 3.1),
    )
    yi = W / 2 - esp
    V.ham_chu_a(
        rec,
        "abrigo",
        (-2.15, 0.45),
        90,
        mats,
        comp=1.3,
        larg=0.9,
        alt_monte=0.85,
        grupo="Mobilia",
        no="Mobilia",
        z=PISO,
    )
    V.cho_tre(rec, "cho", (-2.3, -1.6), 0, mats)
    V.ban_tho(rec, "altar", (0.2, yi - 0.36), 0, mats)
    V.phan(rec, "phan", (2.3, 1.45), 0, mats)
    V.ban_thap(rec, "mesa", (1.3, -0.8), 0, mats)
    V.potes(rec, "lu", [(3.0, -1.75), (2.45, -1.8)], mats, sem=71)
    V.nonla_pendurado(rec, "nonla", (1.0, yi), 0, mats)
    # varanda
    V.ferramentas(rec, "ferr", (0.75, -W / 2), 0, mats, arado=False)
    V.rede_pendurada(
        rec, "rede", (-2.2, -3.3), 0, mats, comp=1.8, queda=1.25, grupo="Casa", no="Anexos"
    )
    V.jarro_agua(rec, "jarro", (-0.95, -2.95), mats, z=PISO)
    camera(rec, (0.9, -1.7, PISO + 1.6), (-2.0, 0.9, PISO + 0.6))
    return rec


def receita_vila_casa_08():
    """Nhà nửa gạch nửa tre: meia parede de tijolo rebocado e o resto de bambu trançado, 4 águas
    de nipa, puxado de cozinha (chái bếp) do lado esquerdo com fogão, divisória de phên para o
    quarto e chiqueiro atrás."""
    rec = V.Receita()
    mats = Mats(8)
    L, W, H = 5.8, 4.6, 3.0
    gach = V.mat_gach("gach", "#cfc6b0", "#9d9481", exposto=0.45)
    phen = V.mat_phen("phen_par", "#ad9767", "#7b6c48", passo=0.045)
    la = V.mat_la("la", ("#4a3f2e", "#6f6046", "#8d7d5e", "#a19274"))
    portas = [
        {"lado": "frente", "t": -0.4, "estilo": "liep", "folha": 1},
        {"lado": "esq", "t": 0.7, "estilo": "tabua", "folha": 1, "registrar": False},
    ]
    janelas = [
        {"lado": "frente", "t": -2.0, "w": 0.6, "estilo": "tre", "aba": True},
        {"lado": "fundo", "t": 1.9, "w": 0.6, "estilo": "tre"},
        {"lado": "dir", "t": 0.0, "w": 0.6, "estilo": "tre"},
    ]
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        1.0,
        0.22,
        gach,
        portas,
        [],
        col="Brick",
        sem=8,
        nen_rets=[(-L / 2 - 1.85, -W / 2 - 0.25, L / 2 + 0.25, W / 2 + 0.25)],
    )
    lados = V.lados_ret(0, 0, L, W, 0.08)
    vaos = {k: [] for k in lados}
    for p in portas:
        vaos[p["lado"]].append(V.vao_porta(p["t"], lados[p["lado"]]))
    for j in janelas:
        vaos[j["lado"]].append(V.vao_janela(j["t"], lados[j["lado"]], j.get("w", 0.75)))
    for k, lado in lados.items():
        V.parede(rec, f"cima_{k}", lado, 1.0, H, phen, vaos[k], "Bamboo", "passa", sem=8)
        V.postes_parede(rec, f"cima_{k}_p", lado, H, mats, vaos[k], passo=1.85)
    for i, j in enumerate(janelas):
        V.janela(
            rec,
            f"jan{i}",
            lados[j["lado"]],
            j["t"],
            mats,
            j.get("w", 0.75),
            estilo=j["estilo"],
            aba=j.get("aba", False),
        )
    V.telhado(
        rec, "tel", L, W, H, 4.65, 0.5, "4aguas", "la", 0.2, la, mats, sem=8, tesouras=(-0.95, 1.0)
    )
    # puxado da cozinha (x de -4,75 a -2,9): água única caindo para -X, meia-parede de phên no fundo
    marca = rec.marca()
    V.agua_unica(
        rec,
        "chai",
        -2.25,
        2.25,
        0.0,
        2.6,
        -1.85,
        2.2,
        0.18,
        "la",
        la,
        mats,
        sem=81,
        postes=(-1.9, 1.9),
    )
    lado_fundo = V.Lado((-1.9, -1.6), math.pi / 2, 1.6, 0.06, 1.0)
    V.parede(rec, "chai_par", lado_fundo, 0.0, 1.4, phen, (), "Bamboo", "passa", sem=81)
    rec.transformar(marca, V.lugar((-L / 2, 0.15, 0.0), -90))
    V.bep(rec, "bep", (-3.85, -0.6), -90, mats)
    V.potes(rec, "lu_chai", [(-4.2, 1.6), (-4.25, 1.05)], mats, alts=(0.7, 0.6), sem=83)
    # divisória do quarto (phên, 2,3 m) em x = 1,0 com passagem
    div = V.Lado((1.0, -W / 2 + 0.22), math.pi / 2, W - 0.44, 0.05, 1.0)
    V.parede(
        rec,
        "div",
        div,
        PISO,
        PISO + 2.3,
        phen,
        [V.vao_porta(-0.75, div)],
        "Bamboo",
        "passa",
        sem=82,
    )
    yi = W / 2 - 0.22
    V.phan(rec, "phan", (1.85, 1.0), 90, mats)
    V.ruong(rec, "ruong", (2.25, -1.6), 90, mats)
    V.ban_tho(rec, "altar", (-0.85, yi - 0.36), 0, mats)
    V.ban_thap(rec, "mesa", (-1.7, -0.55), 0, mats)
    V.potes(rec, "lu", [(-2.3, 1.75), (-2.35, 1.15)], mats, sem=85)
    V.rede_monte(rec, "rede_m", (0.5, 0.9), 0, mats, larg=0.85, prof=0.7, sem=8)
    V.nonla_pendurado(rec, "nonla", (0.4, yi), 0, mats)
    V.chuong_heo(rec, "heo", (0.8, 3.85), 180, mats, V.mat_tranh("tranh_heo"))
    V.jarro_agua(rec, "jarro", (1.5, -2.95), mats)
    camera(rec, (0.2, -1.55, PISO + 1.6), (-1.3, 1.6, PISO + 0.9))
    return rec


def receita_vila_casa_09():
    """Nhà tranh có gác lửng: 2 águas de palha alta, porta no oitão, jirau (gác) de bambu sobre a
    metade direita com escada e sacos de arroz, e abrigo em A no terreiro da frente."""
    rec = V.Receita()
    mats = Mats(9)
    L, W, H, esp = 6.0, 4.6, 2.75, 0.16
    par = V.mat_vach_dat("vach_dat", "#8a6646", "#5a4029", "#a3825c", exposta=0.45)
    tranh = V.mat_tranh("tranh")
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        par,
        [{"lado": "esq", "t": -0.5, "estilo": "liep", "folha": 1}],
        [
            {"lado": "frente", "t": -1.2, "estilo": "tre", "aba": True},
            {"lado": "fundo", "t": -1.5, "w": 0.6, "estilo": "tre"},
        ],
        chanfro=0.02,
        sem=9,
    )
    xg = 0.4  # borda do jirau
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        5.1,
        0.45,
        "2aguas",
        "tranh",
        0.32,
        tranh,
        mats,
        beiral_oitao=0.3,
        sem=9,
        tesouras=(xg,),
        mat_oitao=par,
        oitao_esp=esp,
    )
    xi, yi = L / 2 - esp, W / 2 - esp
    # jirau de bambu (fundo a PISO + 2,32 m) de x = xg até a parede da direita
    zg = PISO + 2.34
    rec.add(
        V.viga("gac_viga", (xg, -yi, zg - 0.08), (xg, yi, zg - 0.08), 0.12, 0.14, mats.go),
        "Casa",
        "Estrutura",
    )
    for k, y in enumerate([-yi + 0.3 + i * 0.62 for i in range(8)]):
        if y > yi - 0.2:
            break
        rec.add(
            V.tre(
                f"gac_barrote{k}",
                (xg - 0.05, y, zg),
                (xi, y, zg),
                0.04,
                mats.tre,
                segs=6,
                sem=k * 0.3,
            ),
            "Casa",
            "Estrutura",
        )
    o = V.bloco(
        "gac_piso",
        (xi - xg, 2 * yi, 0.035),
        ((xg + xi) / 2, 0.0, zg + 0.055),
        mats.esteira,
        local=False,
    )
    V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
    rec.add(o, "Casa", "Estrutura")
    rec.caixa(
        "gac",
        ((xg + xi) / 2, 0.0, zg + 0.03),
        (xi - xg, 2 * yi, 0.12),
        "passa",
        "Bamboo",
        "jirau: o Humanoid não sobe pela escada visual (precisa de TrussPart invisível)",
    )
    for sy in (-1, 1):
        rec.add(
            V.tre(
                f"escada_lat{sy}",
                (xg - 0.65, -1.4 + sy * 0.22, PISO),
                (xg + 0.15, -1.4 + sy * 0.22, zg + 0.5),
                0.03,
                mats.tre,
                segs=6,
            ),
            "Mobilia",
            "Mobilia",
        )
    for k in range(7):
        t = (k + 0.5) / 7
        x = xg - 0.65 + 0.8 * t
        z = PISO + (zg + 0.5 - PISO) * t
        rec.add(
            V.tre(f"escada_deg{k}", (x, -1.62, z), (x, -1.18, z), 0.02, mats.tre, segs=5),
            "Mobilia",
            "Mobilia",
        )
    V.sacos(
        rec,
        "saco_gac",
        [(1.3, 1.5, 10), (1.7, 1.2, -20), (2.2, 1.6, 80), (1.5, 1.45, 5)],
        mats,
        z=zg + 0.07,
    )
    for k, (x, y) in enumerate(((2.3, -1.3), (1.8, -1.7))):
        c = V.torno_local(
            f"gac_cesto{k}",
            [
                (0.0, 0.0),
                (0.2, 0.0),
                (0.26, 0.1),
                (0.27, 0.32),
                (0.24, 0.32),
                (0.23, 0.1),
                (0.0, 0.02),
            ],
            12,
            mats.phen,
        )
        V.M.mover(c, V.Matrix.Translation((x, y, zg + 0.07)))
        rec.add(c, "Mobilia", "Mobilia")
    V.ban_tho(rec, "altar", (xi - 0.32, 0.0), -90, mats)
    V.phan(rec, "phan", (1.6, -1.45), 0, mats)
    V.cho_tre(rec, "cho", (-1.6, 1.6), 0, mats)
    V.ban_thap(rec, "mesa", (-0.95, -0.4), 0, mats)
    V.potes(rec, "lu", [(2.45, 1.75), (1.9, 1.85)], mats, sem=91)
    V.rede_monte(rec, "rede_m", (-2.2, -1.55), 0, mats, larg=1.0, prof=0.75, sem=9)
    V.nonla_pendurado(rec, "nonla", (-xi, 1.0), 90, mats)
    V.ham_chu_a(rec, "abrigo", (-1.2, -4.3), 180, mats)
    V.jarro_agua(rec, "jarro", (-3.6, 0.8), mats)
    camera(rec, (-2.3, -0.5, PISO + 1.6), (2.4, 0.2, PISO + 1.4))
    return rec


def receita_vila_casa_10():
    """Nhà vách đất mái ngói có sân: barro caiado com 2 águas de telha e oitões de tijolo,
    terreiro de tijolo fechado por muro baixo com portão aberto, biombo (bình phong) liso entre o
    portão e a porta e tanque de água de chuva."""
    rec = V.Receita()
    mats = Mats(10)
    L, W, H, esp = 6.8, 4.4, 2.75, 0.2
    par = V.mat_vach_dat("vach_cal", "#8b6c4c", "#5e4732", "#a38663", cal="#dcd4c2", exposta=0.2)
    gach = V.mat_gach("gach", exposto=0.35)
    ngoi = V.mat_ngoi("ngoi", "#9b5a3e", "#6f3e2b", "#b27050")
    casa_ret(
        rec,
        mats,
        "c",
        L,
        W,
        H,
        esp,
        par,
        [{"lado": "frente", "t": 0.0, "estilo": "folhas"}],
        [
            {"lado": "frente", "t": -2.3},
            {"lado": "frente", "t": 2.3},
            {"lado": "fundo", "t": 0.0, "w": 0.6},
        ],
        chanfro=0.02,
        sem=10,
    )
    V.telhado(
        rec,
        "tel",
        L,
        W,
        H,
        4.3,
        0.45,
        "2aguas",
        "ngoi",
        0.12,
        ngoi,
        mats,
        beiral_oitao=0.2,
        sem=10,
        tesouras=(-1.15, 1.15),
        mat_oitao=gach,
        oitao_esp=esp + 0.02,
        col_oitao="Brick",
    )
    yi, xi = W / 2 - esp, L / 2 - esp
    V.ban_tho(rec, "altar", (0.0, yi - 0.36), 0, mats)
    V.phan(rec, "phan1", (-2.15, 1.2), 0, mats)
    V.phan(rec, "phan2", (2.15, 1.3), 0, mats, larg=1.1)
    V.ban_thap(rec, "mesa", (-1.6, -0.7), 0, mats)
    V.ruong(rec, "ruong", (1.9, -1.65), 0, mats)
    V.bo_lua(rec, "bolua", (-2.8, -1.55), mats, r=0.36)
    V.ferramentas(rec, "ferr", (xi, 0.55), -90, mats, itens=("enxada", "ancinho", "nia"))
    V.potes(rec, "lu", [(-0.95, 1.72), (0.95, 1.72)], mats, alts=(0.5, 0.5), sem=101)
    # terreiro: piso de tijolo, muro baixo com portão, biombo e tanque
    yf = -W / 2 - 3.2  # face de dentro do muro da frente
    san = V.mat_gach("san", reboco="#8f877a", escuro="#6f685d", exposto=3.0)
    o = V.bloco(
        "san",
        (7.9, -W / 2 - 0.25 - yf, 0.05),
        (0.0, (yf - W / 2 - 0.25) / 2, 0.025),
        san,
        local=False,
    )
    V.gravar_uv_local(o, lambda p: (p.x, p.y, p.z))
    V.sem_fundo(o, 0.0)
    rec.add(o, "Casa", "Piso")
    muro = V.mat_gach("muro", "#cfc7b2", "#9c937f", exposto=0.5)
    xm = 4.05
    frente = V.Lado((-xm, yf - 0.11), 0.0, 2 * xm, 0.22, 1.0)
    V.parede(
        rec,
        "muro_f",
        frente,
        0.0,
        1.1,
        muro,
        [(xm, 1.4, -1.0, 9.0)],
        "Brick",
        "para",
        chanfro=0.03,
        sem=11,
    )
    for sx in (-1, 1):
        lado = V.Lado((sx * xm, yf), math.pi / 2, (-W / 2 - 0.3) - yf, 0.22, 1.0)
        V.parede(
            rec, f"muro_l{sx}", lado, 0.0, 1.1, muro, (), "Brick", "para", chanfro=0.03, sem=12
        )
        p = V.bloco(
            f"pilar{sx}", (0.34, 0.34, 1.6), (sx * 0.87, yf - 0.11, 0.8), muro, chanfro=0.02
        )
        V.gravar_uv_local(p, lambda q: (q.x + q.y, q.z, 0.0))
        rec.add(p, "Casa", "Paredes")
        rec.caixa(f"pilar{sx}", (sx * 0.87, yf - 0.11, 0.8), (0.34, 0.34, 1.6), "para", "Brick")
    bp = V.Lado((-0.9, yf + 1.2), 0.0, 1.8, 0.28, 1.0)
    V.parede(rec, "binh_phong", bp, 0.0, 1.6, muro, (), "Brick", "para", chanfro=0.03, sem=13)
    rec.add(
        V.bloco("binh_topo", (2.0, 0.4, 0.08), (0.0, yf + 1.2, 1.64), muro, chanfro=0.02),
        "Casa",
        "Paredes",
    )
    rec.add(
        V.bloco("binh_pe", (2.1, 0.46, 0.14), (0.0, yf + 1.2, 0.07), muro, chanfro=0.02),
        "Casa",
        "Paredes",
    )
    tq = V.bloco("tanque", (1.0, 0.8, 0.85), (3.15, -W / 2 - 1.05, 0.425), gach, chanfro=0.03)
    rec.add(tq, "Casa", "Anexos")
    rec.add(
        V.bloco(
            "tanque_agua", (0.84, 0.64, 0.02), (3.15, -W / 2 - 1.05, 0.78), mats.cinza, local=False
        ),
        "Casa",
        "Anexos",
    )
    rec.caixa("tanque", (3.15, -W / 2 - 1.05, 0.425), (1.0, 0.8, 0.85), "para", "Brick")
    V.jarro_agua(rec, "jarro", (-3.15, -W / 2 - 0.95), mats)
    camera(rec, (-0.3, -1.6, PISO + 1.6), (0.0, 1.8, PISO + 1.2))
    return rec


# =============================================================== catálogo
CASAS: dict[str, dict] = {
    "vila_casa_01": {
        "nome": "nhà tranh vách đất ba gian (lavrador)",
        "tipo": "3 vãos, 4 águas de palha de arroz, barro sobre bambu, fogão dentro, abrigo em A",
        "fontes": ["navy67", "vjol2024", "plo_3gian", "sggp_nho", "hamA", "schell68"],
    },
    "vila_casa_02": {
        "nome": "nhà lá dừa nước (pescador)",
        "tipo": "phên de bambu, 2 águas de nipa com varanda, redes, nơm, thúng chai e varal",
        "fontes": ["navy67", "sggp_nho", "goco"],
    },
    "vila_casa_03": {
        "nome": "nhà ngói (família de posses)",
        "tipo": "tijolo rebocado, 4 águas de telha, 3 portas, varanda de colunas, armário-altar",
        "fontes": ["navy67", "plo_3gian", "sggp_qngai", "vjol2024"],
    },
    "vila_casa_04": {
        "nome": "nhà tường trình chữ L",
        "tipo": "taipa socada, planta em L com ala de cozinha, 2 águas de palha cruzadas",
        "fontes": ["navy67", "plo_3gian", "goco"],
    },
    "vila_casa_05": {
        "nome": "nhà một gian (casa pobre)",
        "tipo": "1 cômodo, barro gasto na trama, 2 águas de palha, fogão dentro, cerca, abrigo",
        "fontes": ["navy67", "goco", "hamA", "schell68"],
    },
    "vila_casa_06": {
        "nome": "nhà rường gỗ (casa de madeira)",
        "tipo": "tábuas em armação de postes, 4 águas de telha, colunas e tesouras, armário-altar",
        "fontes": ["sggp_qngai", "navy67", "vjol2024"],
    },
    "vila_casa_07": {
        "nome": "nhà tranh có hầm trong nhà",
        "tipo": "barro caiado, 2 águas de palha com varanda, abrigo de família dentro de casa",
        "fontes": ["navy67", "hamA", "schell68", "dtic_ducpho"],
    },
    "vila_casa_08": {
        "nome": "nhà nửa gạch nửa tre",
        "tipo": "meia parede de tijolo + phên, 4 águas de nipa, puxado de cozinha, divisória, "
        "chiqueiro",
        "fontes": ["navy67", "plo_3gian", "sggp_nho"],
    },
    "vila_casa_09": {
        "nome": "nhà tranh có gác lửng",
        "tipo": "2 águas de palha alta, porta no oitão, jirau de bambu com escada, abrigo em A",
        "fontes": ["navy67", "goco", "sggp_nho", "hamA"],
    },
    "vila_casa_10": {
        "nome": "nhà vách đất mái ngói có sân",
        "tipo": "barro caiado, 2 águas de telha com oitões de tijolo, terreiro murado, biombo, "
        "tanque",
        "fontes": ["navy67", "sggp_qngai", "plo_3gian"],
    },
}
