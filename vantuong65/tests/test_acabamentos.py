"""Gerador das texturas dos acabamentos de arma (tools/acabamentos.py, D-178).

Não precisa dos GLB das armas (fora do Git): as receitas rodam numa nuvem de pontos sintética.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import acabamentos as A  # noqa: E402

SKINS = ROOT / "src" / "ReplicatedStorage" / "Shared" / "Skins.luau"


def receitas_do_catalogo() -> list[tuple[str, str, int]]:
    """(id, receita, nº de cores) de cada acabamento extravagante, lido do Skins.luau."""
    s = SKINS.read_text("utf-8").replace("\r\n", "\n")
    bloco = s[s.index("local EXTRAVAGANTES") : s.index("Skins.EXTRAVAGANTES = EXTRAVAGANTES")]
    out = []
    for m in re.finditer(
        r'\{\n\t\t"(skin_[a-z0-9_]+)",(?:\n\t\t"[^"\n]*",){4}\n\t\t"([a-z]+)",\n\t\t(\{.*?\} \}),',
        bloco,
    ):
        out.append((m.group(1), m.group(2), m.group(3).count("{") - 1))
    return out


def nuvem(n: int = 4000) -> A.Ctx:
    """Pontos na casca de um cilindro de 4 unidades (o comprimento normalizado das armas)."""
    rng = np.random.default_rng(7)
    z = rng.uniform(-2, 2, n)
    a = rng.uniform(0, 2 * np.pi, n)
    q = np.stack([np.cos(a) * 0.3, np.sin(a) * 0.3, z], axis=1).astype(np.float32)
    nrm = np.stack([np.cos(a), np.sin(a), np.zeros(n)], axis=1).astype(np.float32)
    return A.Ctx(q, nrm, (z + 2) / 4, np.full(n, 0.4, np.float32), np.zeros((1, 3), np.float32), 1)


def test_catalogo_tem_60_e_toda_receita_existe():
    cat = receitas_do_catalogo()
    assert len(cat) == 60
    for sid, rec, ncores in cat:
        assert rec in A.RECEITAS, f"{sid}: receita {rec} não existe no gerador"
        assert 1 <= ncores <= 4, sid


def test_cada_receita_pinta_em_0_1_e_varia():
    base = nuvem()
    paleta = np.array([[0.9, 0.3, 0.1], [0.05, 0.05, 0.06], [0.3, 0.7, 0.9], [1, 1, 1]], np.float32)
    for nome in A.RECEITAS:
        for k in (1, 2, 3, 4):
            ctx = A.Ctx(base.q, base.n, base.t, base.lum, paleta[:k], 42)
            cor, emis = A.aplicar(nome, ctx)
            assert cor.shape == (len(base.q), 3), nome
            assert np.isfinite(cor).all() and cor.min() >= -1e-4 and cor.max() <= 1.0001, (nome, k)
            if emis is not None:
                assert emis.shape == (len(base.q),) and emis.min() >= 0 and emis.max() <= 1.0001
        # com duas cores ou mais o desenho aparece (não é uma cor lisa)
        cor, _ = A.aplicar(nome, A.Ctx(base.q, base.n, base.t, base.lum, paleta[:3], 42))
        assert cor.std(axis=0).max() > 0.02, f"{nome} sem desenho"


def test_ruido_deterministico_e_no_intervalo():
    p = np.random.default_rng(3).uniform(-50, 50, (5000, 3))
    a, b = A.fbm(p, 9), A.fbm(p, 9)
    assert np.array_equal(a, b)
    assert a.min() >= 0 and a.max() <= 1
    assert not np.array_equal(a, A.fbm(p, 10))  # outra semente, outro desenho
    f1, f2 = A.worley(p * 0.2, 4)
    assert (f2 >= f1).all() and f1.min() >= 0


def test_triangulo_cobre_a_area():
    r = A._tri_pixels(
        np.array([0.0, 0.0]), np.array([100.0, 0.0]), np.array([0.0, 100.0]), 256, 256
    )
    assert r is not None
    xs, ys, w0, w1, w2 = r
    assert abs(len(xs) - 5000) < 150  # metade de 100 x 100
    assert np.allclose(w0 + w1 + w2, 1)
    assert A._tri_pixels(np.array([0.0, 0]), np.array([1.0, 1]), np.array([2.0, 2]), 8, 8) is None


def test_regioes_pela_cor():
    rgb = np.zeros((64, 64, 3), np.float32)
    rgb[:, :16] = (0.45, 0.25, 0.12)  # madeira
    rgb[:, 16:32] = (0.85, 0.65, 0.2)  # latão
    rgb[:, 32:48] = (0.2, 0.21, 0.22)  # metal
    rgb[:, 48:] = (0.33, 0.33, 0.12)  # pano verde-oliva
    cob = np.ones((64, 64), bool)
    mapa = A.Mapa(cob, np.zeros((64, 64, 3)), np.zeros((64, 64, 3)), np.zeros((64, 64)), {})
    r = A.regioes(rgb, mapa, "m14")
    assert r["madeira"][:, 2:14].all() and r["latao"][:, 18:30].all()
    assert r["metal"][:, 34:46].all() and r["pano"][:, 50:62].all()
    # arma sem bandoleira: o verde-oliva é metal
    assert A.regioes(rgb, mapa, "m60")["metal"][:, 50:62].all()


def test_laca_ouro_fica_ouro_e_perola_fica_clara():
    base = nuvem()
    for inc, quente in (((236, 190, 80), True), ((220, 236, 236), False)):
        c = np.array([(150, 22, 24), inc], np.float32) / 255
        cor, _ = A.aplicar("laca", A.Ctx(base.q, base.n, base.t, base.lum, c, 5))
        lasca = cor[A.lum(cor) > 0.5]
        assert len(lasca) > 50, "sem lascas"
        azul_menor = float((lasca[:, 0] - lasca[:, 2]).mean())
        assert (azul_menor > 0.3) if quente else (azul_menor < 0.15), inc
