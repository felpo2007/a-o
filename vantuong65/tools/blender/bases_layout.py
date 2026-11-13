"""Layout sugerido das bases iniciais: `assets/blender/bases/layout_us.json` e `layout_vc.json`.

Roda fora do Blender (só a biblioteca padrão):
    uv run python tools/blender/bases_layout.py

As posições são escritas aqui em metros (x = leste, z = sul, origem no centro da base) e saem em
studs (1 stud = 0,28 m). A pegada de cada asset vem do `metricas.json` dele (caixa do GLB); o
script confere sobreposição entre pegadas (retângulos girados) e calcula a área ocupada. Peças
que ficam de propósito dentro de outra (sacos de arroz sob o abrigo, caixotes na barraca) levam
`dentro_de`.

Convenção de rumo: graus a partir do norte, sentido horário, para onde a FRENTE do asset olha
(porta, boca da baia, face da placa). No Roblox o norte é -Z (MapConfig: N = gridN0 - z*0,28) e,
depois do giro de 180° do importador (D-58), a frente do modelo é -Z; então
yaw = -rumo (CFrame.Angles(0, math.rad(-rumo), 0)). Conferir uma vez no Studio.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
SAIDA = RAIZ / "assets" / "blender"
MAPCONFIG = RAIZ / "src" / "ReplicatedStorage" / "Shared" / "MapConfig.luau"
STUD = 0.28
RAIO_PLANO_US_M = 140.0  # coordenador (2026-11-11): 140 m de raio planos em volta do QG dos EUA


def mapa() -> dict:
    """QGs, limites e origem da grade lidos do MapConfig.luau (só leitura)."""
    txt = MAPCONFIG.read_text("utf-8")
    num = r"(-?\d+(?:\.\d+)?)"
    b = re.search(rf"Bounds = \{{ minX = {num}, maxX = {num}, minZ = {num}, maxZ = {num} \}}", txt)
    g = re.search(rf"GridOrigin1965 = \{{ e = {num}, n = {num} \}}", txt)
    hq = {}
    for f in ("US", "VC"):
        m = re.search(rf"{f} = \{{ x = {num}, z = {num}", txt)
        hq[f] = (float(m.group(1)), float(m.group(2)))
    return {
        "bounds": [float(b.group(i)) for i in range(1, 5)],
        "grade": (float(g.group(1)), float(g.group(2))),
        "hq": hq,
    }


def ancorar(dados: dict, faccao: str, mp: dict) -> None:
    """Põe o centro da base no QG do MapConfig: posições absolutas, folga até as bordas do mapa e
    o raio máximo ocupado (para o raio plano)."""
    hx, hz = mp["hq"][faccao]
    e0, n0 = mp["grade"]
    min_x, max_x, min_z, max_z = mp["bounds"]
    for it in dados["itens"]:
        it["x_abs_studs"] = round(hx + it["x_studs"], 2)
        it["z_abs_studs"] = round(hz + it["z_studs"], 2)
    for k in ("pontos_de_spawn_studs",):
        dados[k + "_abs"] = [[round(hx + x, 2), round(hz + z, 2)] for x, z in dados[k]]
    raio = 0.0
    for it in dados["itens"]:
        for x, z in cantos(it):
            raio = max(raio, math.hypot(x, z))
    a = dados["area"]
    dados["ancora"] = {
        "fonte": f"MapConfig.HQ.{faccao} (o centro da base vai no QG)",
        "x_studs": hx,
        "z_studs": hz,
        "grade_1965": f"E {(e0 + hx * STUD) / 1000:.2f} / N {(n0 - hz * STUD) / 1000:.2f} "
        "(km, grade BS)",
        "folga_ate_as_bordas_m": {
            "leste": round((max_x - hx) * STUD - a["x_max_m"], 1),
            "oeste": round(a["x_min_m"] - (min_x - hx) * STUD, 1),
            "norte": round(a["z_min_m"] - (min_z - hz) * STUD, 1),
            "sul": round((max_z - hz) * STUD - a["z_max_m"], 1),
        },
        "raio_max_ocupado_m": round(raio, 1),
    }
    if faccao == "US":
        dados["ancora"]["raio_plano_m"] = RAIO_PLANO_US_M
        dados["ancora"]["cabe_no_raio_plano"] = raio <= RAIO_PLANO_US_M


def pegada(chave: str) -> tuple[float, float, float]:
    """(largura X, profundidade Z, altura) em metros, do metricas.json."""
    m = json.loads((SAIDA / chave / "metricas.json").read_text("utf-8"))
    d = m["novo"]["dim_m_xyz"]
    return float(d[0]), float(d[2]), float(d[1])


def item(chave, x, z, rumo, papel, obs="", dentro_de=None, no=None, ident=None):
    return {
        "chave": chave,
        "id": ident,
        "x_m": x,
        "z_m": z,
        "rumo_graus": rumo % 360,
        "papel": papel,
        "obs": obs,
        "dentro_de": dentro_de,
        "no": no,
    }


def cantos(it):
    w, d, _ = it["pegada_m"]
    a = math.radians(-it["rumo_graus"])
    c, s = math.cos(a), math.sin(a)
    pts = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        lx, lz = sx * w / 2, sz * d / 2
        # rotação do Roblox em Y: x' = x cos + z sin ; z' = -x sin + z cos
        pts.append((it["x_m"] + lx * c + lz * s, it["z_m"] - lx * s + lz * c))
    return pts


def sobrepoe(a, b, folga=0.05) -> bool:
    """Teste de eixos separadores entre dois retângulos girados (com folga)."""
    pa, pb = cantos(a), cantos(b)
    for poly in (pa, pb):
        for i in range(4):
            x1, z1 = poly[i]
            x2, z2 = poly[(i + 1) % 4]
            nx, nz = z1 - z2, x2 - x1
            n = math.hypot(nx, nz) or 1.0
            nx, nz = nx / n, nz / n
            ra = [p[0] * nx + p[1] * nz for p in pa]
            rb = [p[0] * nx + p[1] * nz for p in pb]
            if max(ra) - folga <= min(rb) or max(rb) - folga <= min(ra):
                return False
    return True


def fechar(base: str, itens: list[dict], meta: dict) -> dict:
    ids: dict[str, int] = {}
    for it in itens:
        it["pegada_m"] = [round(v, 2) for v in pegada(it["chave"])]
        if it["id"] is None:
            ids[it["chave"]] = ids.get(it["chave"], 0) + 1
            it["id"] = f"{it['chave']}_{ids[it['chave']]}"
        it["x_studs"] = round(it["x_m"] / STUD, 2)
        it["z_studs"] = round(it["z_m"] / STUD, 2)
        it["yaw_graus"] = (-it["rumo_graus"]) % 360
    choques = []
    for i, a in enumerate(itens):
        for b in itens[i + 1 :]:
            if a.get("dentro_de") == b["id"] or b.get("dentro_de") == a["id"]:
                continue
            if a["chave"] == b["chave"] == "us_concertina":
                continue
            if sobrepoe(a, b):
                choques.append([a["id"], b["id"]])
    xs = [p[0] for it in itens for p in cantos(it)]
    zs = [p[1] for it in itens for p in cantos(it)]
    lo_x, hi_x, lo_z, hi_z = min(xs), max(xs), min(zs), max(zs)
    tris = 0
    for it in itens:
        arq = SAIDA / it["chave"] / "metricas.json"
        if arq.is_file():
            tris += int(json.loads(arq.read_text("utf-8"))["novo"]["triangulos"])
    saida = {
        "base": base,
        **meta,
        "convencao": {
            "unidade": "studs (1 stud = 0,28 m); x_m/z_m são as mesmas posições em metros",
            "origem": "centro da base (o centro da caixa de cada asset vai no ponto)",
            "eixos": "+X = leste, +Z = sul (Roblox; o norte é -Z, como no MapConfig)",
            "rumo_graus": "para onde a frente do asset olha (0 = norte, 90 = leste), horário",
            "yaw_graus": "CFrame.Angles(0, math.rad(yaw_graus), 0) = -rumo, com a frente do "
            "modelo em -Z depois do importador (D-58); conferir no Studio",
            "altura": "a base de cada asset vai no chão (AssetLoader.place); casas e barracas "
            "com patamar (PLATFORM)",
            "pegada_m": "[largura X, profundidade Z, altura] do GLB (inclui cordas e estais)",
        },
        "area": {
            "x_min_m": round(lo_x, 1),
            "x_max_m": round(hi_x, 1),
            "z_min_m": round(lo_z, 1),
            "z_max_m": round(hi_z, 1),
            "leste_oeste_m": round(hi_x - lo_x, 1),
            "norte_sul_m": round(hi_z - lo_z, 1),
            "m2": round((hi_x - lo_x) * (hi_z - lo_z)),
            "studs": [round((hi_x - lo_x) / STUD, 1), round((hi_z - lo_z) / STUD, 1)],
        },
        "triangulos_total": tris,
        "itens_total": len(itens),
        "sobreposicoes": choques,
        "itens": itens,
    }
    return saida


def em_studs(pts):
    return [[round(x / STUD, 2), round(z / STUD, 2)] for x, z in pts]


# =============================================================== EUA
def layout_us() -> dict:
    it: list[dict] = []
    # perímetro: portão a oeste (estrada para o interior), concertina em W, N e S; o lado do mar
    # (leste) fica aberto para os anfíbios
    it.append(item("us_gate", -44.0, 0.0, 270, "portão (estrada para oeste)", ident="portao"))
    for k in range(7):
        for s in (-1, 1):
            it.append(item("us_concertina", -46.5, s * (9.8 + 7.6 * k), 270, "perímetro oeste"))
    for k in range(11):
        for s in (-1, 1):
            it.append(
                item(
                    "us_concertina",
                    -42.2 + 7.6 * k,
                    s * 60.0,
                    0 if s < 0 else 180,
                    "perímetro norte/sul",
                )
            )
    for x, z, rumo in ((-41.5, -56.0, 270), (-41.5, 56.0, 270), (41.0, -57.0, 90)):
        it.append(item("us_watchtower", x, z, rumo, "torre de vigia"))
    for x, z, rumo in ((-41.0, -24.0, 270), (-41.0, 24.0, 270), (0.0, 56.0, 180), (40.0, 42.0, 90)):
        it.append(item("us_bunker", x, z, rumo, "bunker do perímetro"))
    # QG: bandeiras, barraca de comando, gerador e contêineres
    it.append(item("us_flagpole", -37.0, -8.0, 270, "mastros diante do portão", ident="mastros"))
    it.append(item("us_command_tent", -27.0, -14.0, 180, "QG / posto de comando", ident="coc"))
    it.append(item("us_generator", -27.0, -25.5, 180, "gerador do QG"))
    it.append(item("us_conex", -18.5, -25.5, 180, "carga do QG"))
    it.append(item("us_conex", -15.8, -25.5, 180, "carga do QG"))
    it.append(item("us_jerrycans", -21.5, -25.0, 180, "combustível do gerador"))
    for k, (x, z) in enumerate(((-25.3, -10.0), (-25.3, -10.7), (-25.3, -11.4))):
        it.append(
            item("ammo_crate", x, z, 90, "munição do QG", dentro_de="coc", ident=f"caixote_qg_{k}")
        )
    # blindados (2 LVTP-5, 1 M48A3, 1 Ontos: D-37) e garagem/oficina no norte
    for k, (x, papel) in enumerate(
        ((-29.0, "LVTP-5"), (-15.0, "LVTP-5"), (-1.0, "M48A3"), (13.0, "Ontos"))
    ):
        it.append(
            item(
                "us_armor_revetment",
                x,
                -50.0,
                180,
                f"baia de blindado: {papel}",
                ident=f"baia_{k + 1}",
            )
        )
    it.append(
        item(
            "us_motor_pool",
            28.0,
            -48.0,
            180,
            "garagem e oficina (jipes e caminhões)",
            ident="garagem",
        )
    )
    it.append(item("us_jerrycans", 21.0, -40.5, 180, "galões da oficina"))
    # helipontos perto da praia (2 UH-34D) e combustível
    it.append(item("us_helipad", 34.0, -30.0, 270, "heliponto 1 (UH-34D)", ident="heliponto_1"))
    it.append(item("us_helipad", 34.0, -5.0, 270, "heliponto 2 (UH-34D)", ident="heliponto_2"))
    it.append(
        item("us_fuel_drums", 42.5, -42.5, 270, "ponto de combustível (helicópteros e viaturas)")
    )
    it.append(item("sandbag_wall", 40.6, -43.6, 270, "proteção do combustível"))
    it.append(item("sandbag_wall", 40.6, -41.5, 270, "proteção do combustível"))
    # alojamentos, refeitório e água (sudoeste)
    for k, x in enumerate((-33.0, -24.0, -15.0)):
        it.append(
            item(
                "us_tent_gp_medium",
                x,
                15.0,
                0,
                "alojamento (porta para a estrada)",
                ident=f"gp_medium_{k + 1}",
            )
        )
    for k, x in enumerate((-33.0, -23.5)):
        it.append(
            item(
                "us_tent_gp_large",
                x,
                39.0,
                0,
                "alojamento de pelotão (strongback)",
                ident=f"gp_large_{k + 1}",
            )
        )
    it.append(item("us_mess_tent", -10.5, 39.0, 0, "refeitório", ident="refeitorio"))
    it.append(item("us_water_trailer", -3.0, 31.5, 0, "água do refeitório"))
    it.append(item("us_jerrycans", -3.0, 46.0, 0, "galões de água"))
    for k, (x, z) in enumerate(((-41.4, 23.5), (-41.4, 24.5))):
        it.append(
            item(
                "ammo_crate",
                x,
                z,
                0,
                "munição do bunker",
                dentro_de="us_bunker_2",
                ident=f"caixote_bunker_{k}",
            )
        )
    # estande de tiro (sudeste): linha a z = 20 atirando para o sul, alvos a 25 m, barranco atrás
    for k, x in enumerate((16.0, 20.0, 24.0, 28.0)):
        it.append(
            item(
                "us_range_bench", x, 20.0, 180, "bancada da linha de tiro", ident=f"bancada_{k + 1}"
            )
        )
        it.append(item("us_range_target", x, 45.0, 0, "alvo tipo E a 25 m", ident=f"alvo_{k + 1}"))
    it.append(item("us_range_berm", 22.0, 50.0, 0, "barranco de proteção", ident="barranco"))
    it.append(item("us_range_sign", 12.0, 45.0, 0, "placa de 25 m", no="Placa25", ident="placa_25"))
    it.append(
        item(
            "us_range_sign",
            12.0,
            21.0,
            0,
            "placa da linha (100/200/300 ficam no campo longo)",
            no="Placa100",
            ident="placa_linha",
        )
    )
    spawn = [(4.0, 6.0), (8.0, 6.0), (4.0, 10.0), (8.0, 10.0), (-6.0, 6.0), (-6.0, 10.0)]
    meta = {
        "descricao": "Base do USMC em Chu Lai (praia), agosto de 1965. Portão a oeste; mar a "
        "leste (lado aberto para os anfíbios); estrada leste-oeste em z = 0.",
        "posicao_no_mapa": "centro da base no QG dos EUA (MapConfig.HQ.US: E 270,30 / N 1692,95), "
        "a 50 m da borda leste do mapa de 1 x 1 km, dentro dos 140 m de raio planos; o lado "
        "+X (leste) é o do mar",
        "pontos_de_spawn_studs": em_studs(spawn),
        "veiculos_studs": {
            "lvtp5": em_studs([(-29.0, -50.0), (-15.0, -50.0)]),
            "m48a3": em_studs([(-1.0, -50.0)]),
            "ontos": em_studs([(13.0, -50.0)]),
            "uh34d": em_studs([(34.0, -30.0), (34.0, -5.0)]),
            "carros_na_garagem": em_studs([(25.0, -48.0), (31.0, -48.0)]),
            "obs": "rumo de saída dos blindados e carros: 180 (sul, para a estrada)",
        },
        "estrada": {
            "de_studs": em_studs([(-48.0, 0.0)])[0],
            "ate_studs": em_studs([(24.0, 0.0)])[0],
            "largura_m": 6.0,
            "obs": "terra batida; o código pode pintar o terreno (Ground/Mud) e tirar a mata",
        },
        "campo_de_tiro": {
            "linha_studs": em_studs([(14.0, 20.0), (30.0, 20.0)]),
            "direcao": "sul (+Z)",
            "alvos_25m": "us_range_target alvo_1..4 (nó Silhueta com RangeTarget = 25)",
            "campo_longo": "100/200/300 m continuam no TrainingService (fora da base); as placas "
            "100/200/300 do us_range_sign vão junto dos alvos de lá",
        },
        "reaproveitados": ["sandbag_wall", "ammo_crate"],
    }
    return fechar("US", it, meta)


# =============================================================== VC
def layout_vc() -> dict:
    it: list[dict] = []
    # abrigos de dormir no lado oeste (retaguarda), de frente para o centro (leste)
    for k, z in enumerate((-14.0, -8.0, -2.0, 4.0)):
        it.append(item("vc_lean_to", -19.0, z, 90, "abrigo de dormir", ident=f"abrigo_{k + 1}"))
    # depósito de arroz: abrigo com sacos embaixo
    it.append(item("vc_lean_to", -6.0, -15.5, 180, "depósito de arroz", ident="deposito_arroz"))
    for k in range(8):
        x = -7.5 + (k % 4) * 0.55
        z = -15.9 + (k // 4) * 0.45
        it.append(
            item(
                "rice_sack",
                x,
                z,
                180,
                "saco de arroz",
                dentro_de="deposito_arroz",
                ident=f"arroz_{k + 1}",
            )
        )
    # cozinha Hoàng Cầm com o duto para o sul (fumaça longe dos abrigos)
    it.append(
        item("vc_hoang_cam_kitchen", -12.0, 12.5, 0, "cozinha (fogão sem fumaça)", ident="cozinha")
    )
    it.append(item("water_jar", -8.6, 7.0, 0, "água da cozinha"))
    # redes e armeiros no meio
    for k, (x, z, rumo) in enumerate(((-12.0, -7.5, 90), (-12.0, -1.5, 90), (-4.0, -8.0, 0))):
        it.append(item("vc_hammock", x, z, rumo, "rede", ident=f"rede_{k + 1}"))
    for k, z in enumerate((-3.0, 0.5)):
        it.append(item("vc_weapon_rack", -4.0, z, 90, "armeiro", ident=f"armeiro_{k + 1}"))
    it.append(item("bamboo_clothesline", -12.5, 4.0, 0, "varal"))
    # estande de tiro: apoio a x = -1, atirando para leste, alvos a ~23 m
    it.append(
        item("vc_range_rest", -1.0, 13.0, 90, "linha de tiro (de joelho)", ident="linha_tiro")
    )
    for k, z in enumerate((11.5, 13.0, 14.5)):
        it.append(
            item("vc_range_target", 22.0, z, 270, "alvo de palha a ~23 m", ident=f"alvo_{k + 1}")
        )
    # abrigo do carro na trilha que entra pelo leste
    it.append(
        item(
            "vc_car_shelter",
            17.0,
            -12.0,
            90,
            "abrigo do carro (trilha para leste)",
            ident="abrigo_carro",
        )
    )
    # estacas punji nas entradas e túneis de fuga
    for k, (x, z, rumo) in enumerate(
        (
            (23.5, -3.0, 90),
            (23.5, 3.0, 90),
            (6.0, -19.0, 0),
            (14.0, 19.0, 180),
            (-2.0, 19.0, 180),
            (23.5, 7.5, 90),
        )
    ):
        it.append(
            item("vc_punji", x, z, rumo, "estacas punji na aproximação", ident=f"punji_{k + 1}")
        )
    it.append(item("tunnel_entrance", -22.5, 17.5, 0, "túnel de fuga (oeste)", ident="tunel_1"))
    it.append(item("tunnel_entrance", 8.0, -16.0, 0, "túnel (norte)", ident="tunel_2"))
    spawn = [(-8.0, 0.0), (-8.0, 4.0), (0.0, -4.0), (4.0, 0.0), (0.0, 4.0), (-8.0, -4.0)]
    meta = {
        "descricao": "Acampamento do VC na mata (bem mais simples que a base dos EUA: sem "
        "helicópteros nem blindados, só o abrigo do carro). Retaguarda a oeste, entradas a leste.",
        "posicao_no_mapa": "centro da base no QG do VC (MapConfig.HQ.VC: E 269,41 / N 1693,43), "
        "no morro do noroeste, sob a mata (o código tira só as árvores dentro das pegadas e "
        "deixa a copa em volta; em ladeira, cada peça assenta no chão como no AssetLoader)",
        "pontos_de_spawn_studs": em_studs(spawn),
        "veiculos_studs": {
            "carro": em_studs([(17.0, -12.0)]),
            "obs": "o carro entra de ré ou de frente pelo leste (rumo 90); cabe GAZ-69, "
            "Traction Avant, Willys M38 e Peugeot 403",
        },
        "campo_de_tiro": {
            "linha_studs": em_studs([(-1.0, 11.3), (-1.0, 14.7)]),
            "direcao": "leste (+X)",
            "alvos": "vc_range_target alvo_1..3 (nó Silhueta com RangeTarget = 23)",
        },
        "trilha": {
            "de_studs": em_studs([(26.0, -12.0)])[0],
            "ate_studs": em_studs([(21.0, -12.0)])[0],
            "obs": "trilha de terra até a borda (largura 3 m)",
        },
        "fumaca_cozinha": "3 saídas do duto (metricas.json de vc_hoang_cam_kitchen, extras)",
        "reaproveitados": ["rice_sack", "tunnel_entrance", "water_jar", "bamboo_clothesline"],
    }
    return fechar("VC", it, meta)


def main() -> None:
    pasta = SAIDA / "bases"
    pasta.mkdir(parents=True, exist_ok=True)
    mp = mapa()
    for nome, f, faccao in (
        ("layout_us.json", layout_us, "US"),
        ("layout_vc.json", layout_vc, "VC"),
    ):
        dados = f()
        ancorar(dados, faccao, mp)
        (pasta / nome).write_text(json.dumps(dados, ensure_ascii=False, indent=1) + "\n", "utf-8")
        a = dados["area"]
        an = dados["ancora"]
        print(
            f"{nome}: {dados['itens_total']} itens, {a['leste_oeste_m']} x {a['norte_sul_m']} m, "
            f"{dados['triangulos_total']} tri; sobreposições: {dados['sobreposicoes'] or 'nenhuma'}"
            f"; âncora {an['grade_1965']}; folga às bordas {an['folga_ate_as_bordas_m']}; "
            f"raio ocupado {an['raio_max_ocupado_m']} m"
        )


if __name__ == "__main__":
    main()
