"""Síntese dos sons das armas (D-204, tools/sons_armas.py): nível, bordas, identidade e variação."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import sons_armas as S  # noqa: E402


@pytest.fixture(scope="module")
def tiros() -> dict[str, dict[str, list[np.ndarray]]]:
    return {
        a: {"p": [S.tiro(a, "p", v) for v in (1, 2)], "e": [S.tiro(a, "e", 1)]} for a in S.ARMAS
    }


def test_sem_clipar_e_bordas_em_zero(tiros):
    for arma, t in tiros.items():
        for x in t["p"] + t["e"]:
            assert np.abs(x).max() <= 10 ** (-1.0 / 20) + 1e-9, arma
            assert abs(x[0]) < 1e-6 and abs(x[-1]) < 1e-6, arma
            assert abs(float(x.mean())) < 2e-3, f"{arma}: desvio de DC"


def test_identidade_pelo_calibre(tiros):
    c = {a: S.centroide(t["p"][0]) for a, t in tiros.items()}
    # o 40 mm é o mais grave e a 12 vem logo; as pistolas, as mais claras;
    # a 5,56 mais clara que a 7,62
    assert c["m79"] < c["win12"] < min(c["m14"], c["m70"], c["mosin"], c["m60"])
    assert c["m16"] > c["m14"] and c["type54"] > c["m1911"]
    assert min(c["m1911"], c["type54"]) > max(c["m70"], c["mosin"], c["m14"])


def test_terceira_pessoa_mais_clara_que_a_primeira(tiros):
    for arma, t in tiros.items():
        assert S.centroide(t["e"][0]) > S.centroide(t["p"][0]), arma


def test_variacoes_diferentes_sem_mudar_o_carater(tiros):
    for arma, t in tiros.items():
        a, b = t["p"]
        assert not np.allclose(a, b), arma
        ca, cb = S.centroide(a), S.centroide(b)
        assert abs(ca - cb) / ca < 0.15, f"{arma}: {ca:.0f} x {cb:.0f} Hz"


def test_montar_em_10_ms_e_com_silencio():
    x = np.ones(1000) * 0.1
    y, seg = S.montar([("a", x, 0.0), ("b", x, 0.01)])
    assert len(y) % (S.SR // 100) == 0
    assert seg["b"][0] - (seg["a"][0] + seg["a"][1]) >= S.GAP_S - 1e-6
    assert seg["b"][2] == 0.01


def test_partes_da_recarga_existem_para_cada_tipo():
    for arma, p in S.ARMAS.items():
        for nome in S.RECARGA_PARTES[p["recarga"]]:
            x, anc = S.parte(nome, arma)
            assert 0 <= anc < len(x) / S.SR, f"{arma}/{nome}"
            assert np.abs(x).max() > 0.1, f"{arma}/{nome} mudo"
