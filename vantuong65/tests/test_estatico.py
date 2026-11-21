"""Arte fixa para o SLIM (tools/estatico.py, D-155): leitura da cópia e o modelo do Rojo."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import estatico  # noqa: E402

CASAS = ROOT / "assets" / "estatico" / "vila_casas.txt"


def todas(no: dict) -> list[dict]:
    out = []
    for f in no["filhos"]:
        out += [f] if estatico.folha(f) else todas(f)
    return out


def molde_03() -> dict:
    # D-167 era a cópia de uma casa só (vila_casa_03_xomgo); D-201: a vila foi recopiada inteira e
    # essa casa é o molde da vila_casa_03 no vila_casas
    return next(
        m for m in estatico.ler(CASAS) if m["chave"] == "vila_casa_03" and not m.get("instancia")
    )


def test_molde_da_casa_03():
    casa = molde_03()
    pecas = todas(casa)
    assert len(pecas) == 55
    # D-167: 5 malhas visíveis com textura (Mobilia, Telhado e o grupo Casa nas folhas comuns da
    # trim sheet, D-159) e 50 caixas de colisão invisíveis com o Material da bala
    visiveis = [p for p in pecas if "sa" in p]
    colisao = [p for p in pecas if p["nome"].startswith("Colisao_")]
    assert len(visiveis) == 5 and len(colisao) == 50
    assert sorted(p["nome"] for p in visiveis if p["nome"].startswith("Trim_")) == [
        "Trim_M",
        "Trim_P",
        "Trim_W",
    ]
    assert all("t" in p["marcas"] and p["material"] for p in colisao)


def test_modelo_do_rojo_slim_e_tamanho_da_malha():
    casa = molde_03()
    j = estatico.rojo_modelo(casa)
    props = j["Properties"]
    assert props["LevelOfDetail"] == {"Enum": estatico.SLIM} and estatico.SLIM == 4
    assert props["ModelStreamingMode"] == "Atomic"
    # atributos tipados dentro de Properties: no topo do .model.json o Rojo 7.4 ignora
    assert "Attributes" not in j
    attrs = props["Attributes"]["Attributes"]
    assert attrs["VT65Chave"] == {"String": "vila_casa_03"}
    assert attrs["VT65Estatico"] == {"Bool": True}
    p = estatico.rojo_peca(todas(casa)[0])
    s, i = p["Properties"]["Size"], p["Properties"]["InitialSize"]
    for a, b in zip(s, i, strict=True):
        assert b == pytest.approx(a / casa["escala"], abs=1e-3)
    # sem colisão calculada fora do Studio: o que colide vai em caixa
    assert p["Properties"]["CollisionFidelity"] == "Box"
    # giro só em Y
    o = p["Properties"]["CFrame"]["CFrame"]["orientation"]
    assert o[1] == [0, 1, 0] and o[0][1] == 0 and abs(o[0][0] ** 2 + o[0][2] ** 2 - 1) < 1e-5


def test_construcao_de_pecas_linha_b(tmp_path):
    # D-168: o alpendre inclinado (-8° em X) e uma tora (cilindro), como o MapLife monta
    f = tmp_path / "vila.txt"
    f.write_text(
        "M Vila_teste 10.000 5.000 20.000 30.000 1.000\n"
        "B WedgePart - Alpendre 10.000 6.000 20.000 1.000000 0.000000 0.000000 0.000000 0.990268"
        " 0.139173 0.000000 -0.139173 0.990268 4.000 1.000 3.000 cqs Thatch Grass"
        " 0.6118,0.5412,0.3529\n"
        "B Part Cylinder Tora 0.000 2.000 0.000 1.000000 0.000000 0.000000 0.000000 1.000000"
        " 0.000000 0.000000 0.000000 1.000000 8.000 1.500 1.500 cqs Wood Wood"
        " 0.3608,0.2745,0.1882\n",
        "utf-8",
    )
    (m,) = estatico.ler(f)
    assert m["chave"] == "Vila_teste" and estatico.pecas(m) == 2
    cunha, tora = m["filhos"]
    j = estatico.rojo_bloco(cunha)
    assert j["ClassName"] == "WedgePart" and "Shape" not in j["Properties"]
    # as linhas da matriz vão como linhas (conferido no Rojo 7.4 e lido de volta no Lune)
    assert j["Properties"]["CFrame"]["CFrame"]["orientation"][1] == [0.0, 0.990268, 0.139173]
    assert j["Properties"]["Material"] == "Grass"
    assert j["Properties"]["Attributes"]["Attributes"]["Material"] == {"String": "Thatch"}
    t = estatico.rojo_bloco(tora)
    assert t["ClassName"] == "Part" and t["Properties"]["Shape"] == "Cylinder"
    assert t["Properties"]["Color"] == [0.3608, 0.2745, 0.1882]
    assert t["Properties"]["CanCollide"] and t["Properties"]["CastShadow"]
    # o modelo inteiro sai com as duas peças
    assert [c["Name"] for c in estatico.rojo_modelo(m)["Children"]] == ["Alpendre", "Tora"]


def test_instancia_de_molde(tmp_path):
    # D-169: a casa repetida vem do molde (mesma chave), levada ao pivô, ao giro e à escala dela
    f = tmp_path / "casas.txt"
    f.write_text(
        "M vila_casa_01 100.000 10.000 200.000 30.000 1.300\n"
        "N Trim_M_Node\n"
        "P Trim_M 111 110.000 15.000 200.000 30.000 13.000 6.500 2.600 s -\n"
        "S 1 2 3 4 Overlay 1.0000,1.0000,1.0000\n"
        "I vila_casa_01 100.000 10.000 200.000 30.000 1.300\n"
        "I vila_casa_01 0.000 20.000 0.000 120.000 2.600\n",
        "utf-8",
    )
    lidos = estatico.ler(f)
    assert [m.get("instancia", False) for m in lidos] == [False, True, True]
    molde, igual, girada = estatico.instanciar(lidos, estatico.moldes_de([f]))
    p0, p1, p2 = (todas(m)[0] for m in (molde, igual, girada))
    # no mesmo pivô, a mesma peça
    assert p1["pos"] == pytest.approx(p0["pos"]) and p1["giro"] == pytest.approx(p0["giro"])
    assert p1["tamanho"] == pytest.approx(p0["tamanho"]) and p1["sa"] == p0["sa"]
    # giro +90° e escala 2x: a peça a 10 studs do pivô do molde vai a 20 studs do pivô da
    # instância, girada 90° em volta dele, e 5 × 2 = 10 acima
    assert estatico._girar(10, 0, 0) == pytest.approx((10, 0))
    assert estatico._girar(10, 0, 90) == pytest.approx((0, -10), abs=1e-9)  # CFrame.Angles(0, 90°)
    l0x, l0z = estatico._girar(10.0, 0.0, -30)
    wx, wz = estatico._girar(l0x * 2, l0z * 2, 120)
    assert p2["pos"] == pytest.approx([wx, 20 + 5 * 2, wz], abs=1e-3)
    assert math.hypot(p2["pos"][0], p2["pos"][2]) == pytest.approx(20, abs=1e-3)
    assert p2["giro"] == pytest.approx(120) and p2["tamanho"] == pytest.approx([26, 13, 5.2])
    # o InitialSize da malha não muda com a escala da instância
    a = estatico.rojo_peca(p0)["Properties"]["InitialSize"]
    b = estatico.rojo_peca(p2)["Properties"]["InitialSize"]
    assert a == pytest.approx(b)
    # instância sem molde é recusada
    g = tmp_path / "sozinha.txt"
    g.write_text("I vila_casa_02 0 0 0 0 1\n", "utf-8")
    with pytest.raises(SystemExit):
        estatico.instanciar(estatico.ler(g), estatico.moldes_de([g]))


def test_linha_b_incompleta_e_classe_estranha_recusadas(tmp_path):
    f = tmp_path / "x.txt"
    f.write_text("M Vila_teste 0 0 0 0 1\nB Part Block Parede 0 0 0 1 0 0\n", "utf-8")
    with pytest.raises(SystemExit):
        estatico.ler(f)
    g = tmp_path / "y.txt"
    linha = "B TrussPart - Escada" + " 0" * 15 + " cqs - Plastic 1,1,1\n"
    g.write_text("M Vila_teste 0 0 0 0 1\n" + linha, "utf-8")
    with pytest.raises(SystemExit):
        estatico.ler(g)


def test_chave_que_depende_do_jogo_e_recusada(tmp_path):
    f = tmp_path / "x.txt"
    f.write_text("M vc_punji 0 0 0 0 1\n", "utf-8")
    with pytest.raises(SystemExit):
        estatico.ler(f)


def test_expansao_so_com_o_visual():
    # D-235: 31 construções (22 moldes e 9 repetidas). A colisão fica no modelo do jogo: fora do
    # Studio ela viraria caixa cheia, e a escada e o andar de cima dos sobrados deixariam de existir
    modelos = estatico.ler(ROOT / "assets" / "estatico" / "expansao.txt")
    moldes = [m for m in modelos if not m.get("instancia")]
    assert len(modelos) == 31 and len(moldes) == 22
    assert all(m["chave"].startswith("exp_") for m in modelos)
    # o piso que some de longe (Shared/ExpansaoLod) também fica no jogo: o modelo fixo não muda
    piso_no_jogo = {
        "exp_abrigo",
        "exp_casa_vala",
        "exp_casa_verde",
        "exp_casas_ligadas",
        "exp_celeiro",
        "exp_sobrado_a",
        "exp_sobrado_b",
        "exp_sobrado_c",
        "exp_sobrado_d",
    }
    for m in moldes:
        pecas = todas(m)
        assert pecas, m["chave"]
        for p in pecas:
            assert "malha" in p and "sa" in p, f"{m['chave']}/{p['nome']}"
            assert not p["nome"].startswith(("Colisao_", "Zona_")), f"{m['chave']}/{p['nome']}"
            assert not set(p["marcas"]) & set("cqh"), f"{m['chave']}/{p['nome']} interage"
        if m["chave"] in piso_no_jogo:
            assert "Trim_P" not in [p["nome"] for p in pecas], m["chave"]


def test_ligados_e_gerado_bate():
    # D-155: o SLIM só é gerado com o Team Create; D-167: ligado, a casa de Xóm Gò vai no place;
    # D-168: e as construções de peças do MapLife. D-201 (objetivos e vila no lugar novo):
    # recopiadas do jogo, 24 construções (eram 19: entram as 4 de peças da D-172 e uma horta a mais
    # da vila nova) e a vila inteira no vila_casas
    ativos = json.loads((ROOT / "assets" / "estatico" / "ativos.json").read_text("utf-8"))
    assert ativos == ["vila_construcoes", "vila_casas", "expansao"]  # D-235: a expansão
    construcoes = estatico.ler(ROOT / "assets" / "estatico" / "vila_construcoes.txt")
    assert len(construcoes) == 24 and all(m["chave"].startswith("Vila_") for m in construcoes)
    assert sum(estatico.pecas(m) for m in construcoes) == 301
    # D-169: as casas únicas da vila, 9 moldes e as instâncias (a vila_casa_09 fica com o jogo);
    # D-201: 26 instâncias (35 casas fixas, as 3 casas grandes dos objetivos entre elas)
    casas = estatico.ler(ROOT / "assets" / "estatico" / "vila_casas.txt")
    assert sum(1 for m in casas if not m.get("instancia")) == 9
    assert sum(1 for m in casas if m.get("instancia")) == 26
    assert not any(m["chave"] == "vila_casa_09" for m in casas)
    gerados = sorted((ROOT / "src" / "Workspace" / "Estatico").glob("*.model.json"))
    modulo_arq = ROOT / "src" / "ServerScriptService" / "Modules" / "StaticArt.luau"
    modulo = modulo_arq.read_text("utf-8")
    n_itens = modulo.count("{ key = ")
    esperados = sum(len(estatico.ler(ROOT / "assets" / "estatico" / f"{a}.txt")) for a in ativos)
    # D-236: anexo que ficou sem lugar ao lado de uma casa maior sai da arte fixa
    ajuste = json.loads((ROOT / "assets" / "estatico" / "ajuste_casas.json").read_text("utf-8"))
    esperados -= sum(1 for a in ajuste.values() if a.get("fora"))
    assert len(gerados) == n_itens == esperados, "rode tools/estatico.py"
