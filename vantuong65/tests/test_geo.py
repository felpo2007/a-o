"""Testes da cadeia de coordenadas e dos parâmetros travados da F0."""

from __future__ import annotations

import csv
import json
import math
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import geo  # noqa: E402
from georef_carta import fit_affine  # noqa: E402


def test_stud_e_028_m():
    assert geo.STUD_M == 0.28
    assert round(geo.m_to_studs(2000)) == 7143  # 2 km = 7.143 studs (Parte 2 do prompt)
    assert round(geo.m_to_studs(1.75), 2) == 6.25


def test_registro_do_geopdf_tem_residuo_pequeno():
    _, res = fit_affine(300)
    assert res.max() < 10.0


def test_troca_de_datum_ing_a_na_area():
    # deslocamento ING-A -> WGS 84 sem a correção empírica: ~(-502, +336) m
    E, N = geo.ing_to_wgs_utm(270000, 1692000, corrected=False)
    assert E - 270000 == pytest.approx(-501.8, abs=0.5)
    assert N - 1692000 == pytest.approx(336.1, abs=0.5)


def test_correcao_empirica_abaixo_de_25_m():
    assert math.hypot(geo.CORR_DE, geo.CORR_DN) < 25.0


def test_grade_1965():
    assert geo.grid_ref_1965(270260, 1692900) == "BS 702929"
    assert geo.grid_ref_1965(268545, 1691655) == "BS 685916"


def test_quadro_local_centro_e_orientacao():
    cE, cN = geo.play_center_wgs()
    assert geo.wgs_utm_to_local(cE, cN) == (0.0, 0.0)
    x, z = geo.wgs_utm_to_local(cE + 100, cN + 100)  # 100 m a NE
    assert x == pytest.approx(100) and z == pytest.approx(-100)  # norte = -Z


def test_area_jogavel_contem_colina43_e_praia():
    with open(ROOT / "research/locais.csv", encoding="utf-8") as f:
        rows = {r["nome"]: r for r in csv.DictReader(f)}
    for nome in (
        "Colina 43 (cume)",
        "LZ Blue",
        "An Cường (2)",
        "Colina 30 (cume)",
        "An Cường (1)",
        "Green Beach (centro provisório)",
    ):
        assert rows[nome]["na_area_jogavel"] == "True", nome


def test_heightmap_metadados():
    meta = json.loads((ROOT / "research/heightmap/heightmap_area_v0.json").read_text("utf-8"))
    assert meta["bits"] == 16 and meta["studs_por_px"] == 8
    assert meta["area_jogavel_m"] == [4000.0, 2400.0]


def test_export_roblox_relatorio():
    rep = json.loads((ROOT / "research/export_report.json").read_text("utf-8"))
    # relevo calibrado nas cotas da carta: a Colina 43 tem de existir no terreno
    assert [c[0] for c in rep["calibracao_cotas"]][0] == "Colina 43"
    assert rep["casas"] > 100 and rep["diques"] > 10000
    # orçamento de peças do greybox (D-14): alerta se passar de 40 mil
    total = rep["diques"] + rep["agua_parts"] + rep["sebes"] + 3 * rep["casas"]
    assert total < 40000


def test_mapconfig_gerado_tem_area_de_4_por_2_4_km():
    txt = (ROOT / "src/ReplicatedStorage/Shared/MapConfig.luau").read_text("utf-8")
    assert "minX = -7142.9, maxX = 7142.9" in txt
    assert "minZ = -4285.7, maxZ = 4285.7" in txt
