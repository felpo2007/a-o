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


def test_mundo_gerado_contem_colina43_e_praia():
    # a coluna na_area_jogavel é da pesquisa (área antiga de 4 x 2,4 km = WORLD_ING); a área
    # jogável de 2 x 2 km (D-63) deixa a praia e An Cường (1) de fora
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


def test_mapconfig_gerado_tem_area_de_700_por_700_m():
    """D-123 (2026-11-14): 700 x 700 m centrados em Xóm Gò, com An Cường (2) e os túneis a leste;
    origem no centro do mundo gerado (não mudou desde a D-63)."""
    assert geo.PLAY_ING == (269480.0, 1692580.0, 270180.0, 1693280.0)
    txt = (ROOT / "src/ReplicatedStorage/Shared/MapConfig.luau").read_text("utf-8")
    assert "minX = -2571.4, maxX = -71.4" in txt
    assert "minZ = -3142.9, maxZ = -642.9" in txt
    assert "GridOrigin1965 = { e = 270200.0, n = 1692400.0 }" in txt  # origem não mudou


def test_recorte_dentro_dos_dados_de_2_por_2_km():
    """O recorte de 1 km (com a margem de 150 m) cabe nos dados já recortados para 2 x 2 km (D-63):
    o crop_world não precisa das fontes grandes (DEM, carta) para refazer."""
    e0, n0, e1, n1 = geo.PLAY_ING
    m = 150
    assert e0 - m >= 268350 - 150 and e1 + m <= 270350 + 150
    assert n0 - m >= 1691500 - 150 and n1 + m <= 1693500 + 150
