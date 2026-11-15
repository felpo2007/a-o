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
        out += [f] if "malha" in f else todas(f)
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
    assert len(pecas) == 56
    # 6 malhas visíveis (com textura) e 50 caixas de colisão invisíveis com o Material da bala
    visiveis = [p for p in pecas if "sa" in p]
    colisao = [p for p in pecas if p["nome"].startswith("Colisao_")]
    assert len(visiveis) == 6 and len(colisao) == 50
    assert all("t" in p["marcas"] and p["material"] for p in colisao)
    assert sum(len(todas(m)) for m in modelos) == 61


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


def test_chave_que_depende_do_jogo_e_recusada(tmp_path):
    f = tmp_path / "x.txt"
    f.write_text("M vc_punji 0 0 0 0 1\n", "utf-8")
    with pytest.raises(SystemExit):
        estatico.ler(f)


def test_desligado_por_padrao_e_gerado_bate():
    # D-155: sem o Team Create o SLIM não é gerado; o conjunto fica fora do place até ligar
    ativos = json.loads((ROOT / "assets" / "estatico" / "ativos.json").read_text("utf-8"))
    gerados = sorted((ROOT / "src" / "Workspace" / "Estatico").glob("*.model.json"))
    modulo_arq = ROOT / "src" / "ServerScriptService" / "Modules" / "StaticArt.luau"
    modulo = modulo_arq.read_text("utf-8")
    n_itens = modulo.count("{ key = ")
    esperados = sum(len(estatico.ler(ROOT / "assets" / "estatico" / f"{a}.txt")) for a in ativos)
    assert len(gerados) == n_itens == esperados, "rode tools/estatico.py"
