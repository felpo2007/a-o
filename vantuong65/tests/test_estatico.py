"""Arte fixa para o SLIM (tools/estatico.py, D-155): leitura da cópia e o modelo do Rojo."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import estatico  # noqa: E402

CASA = ROOT / "assets" / "estatico" / "vila_casa_03_xomgo.txt"


def todas(no: dict) -> list[dict]:
    out = []
    for f in no["filhos"]:
        out += [f] if estatico.folha(f) else todas(f)
    return out


def test_copia_da_casa_de_xom_go():
    modelos = estatico.ler(CASA)
    chaves = [m["chave"] for m in modelos]
    assert chaves == [
        "vila_casa_03",
        "water_jar",
        "hut_kitchen",
        "granary",
        "bamboo_fence",
        "bamboo_fence",
    ]
    casa = modelos[0]
    pecas = todas(casa)
    assert len(pecas) == 55
    # D-167 (cópia da v90): 5 malhas visíveis com textura (Mobilia, Telhado e o grupo Casa nas
    # folhas comuns da trim sheet, D-159) e 50 caixas de colisão invisíveis com o Material da bala
    visiveis = [p for p in pecas if "sa" in p]
    colisao = [p for p in pecas if p["nome"].startswith("Colisao_")]
    assert len(visiveis) == 5 and len(colisao) == 50
    assert sorted(p["nome"] for p in visiveis if p["nome"].startswith("Trim_")) == [
        "Trim_M",
        "Trim_P",
        "Trim_W",
    ]
    assert all("t" in p["marcas"] and p["material"] for p in colisao)
    assert sum(len(todas(m)) for m in modelos) == 60


def test_modelo_do_rojo_slim_e_tamanho_da_malha():
    casa = estatico.ler(CASA)[0]
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
    # giro de 32,659° em Y
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


def test_ligados_e_gerado_bate():
    # D-155: o SLIM só é gerado com o Team Create; D-167: ligado, a casa de Xóm Gò vai no place
    ativos = json.loads((ROOT / "assets" / "estatico" / "ativos.json").read_text("utf-8"))
    assert ativos == ["vila_casa_03_xomgo"]
    gerados = sorted((ROOT / "src" / "Workspace" / "Estatico").glob("*.model.json"))
    modulo_arq = ROOT / "src" / "ServerScriptService" / "Modules" / "StaticArt.luau"
    modulo = modulo_arq.read_text("utf-8")
    n_itens = modulo.count("{ key = ")
    esperados = sum(len(estatico.ler(ROOT / "assets" / "estatico" / f"{a}.txt")) for a in ativos)
    assert len(gerados) == n_itens == esperados, "rode tools/estatico.py"
