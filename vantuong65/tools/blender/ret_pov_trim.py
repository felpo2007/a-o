"""Folha comum do setor piloto da Vila (D-255): a grade da trim sheet, com paredes velhas.

As casas `ret_pov_*` e `ret_vila_*` usam a UV de `vila_trim`, então basta trocar o portador: nenhuma
malha é refeita e as casas do resto do mapa continuam com a folha publicada.

Saída: assets/blender/ret_pov_trim/ret_pov_trim.glb e metricas.json.
Uso: blender -b --factory-startup -P tools/blender/ret_pov_trim.py
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comum as C  # noqa: E402
import vila_comum as V  # noqa: E402
import vila_trim as VT  # noqa: E402
from vila_comum import Mat, rgb  # noqa: E402

CHAVE = "ret_pov_trim"


def mat_cal_velha(nome, cal="#c8b896", sombra="#9f8e6a", claro="#d9ccab"):
    """Cal antiga sobre barro: sujeira larga, escorrido de chuva, pé úmido e reboco caído só onde a
    água trabalha (junto ao chão e em poucas falhas). `local` = (u ao longo da parede, z, w)."""
    m = Mat(nome, rug=0.94)
    p = m.coord("local")
    _, z, _ = m.separar(p)
    largo = m.ruido(p, 0.55, 4, 0.55)
    medio = m.ruido(m.mapear(p, (1, 1, 1), (2.3, 0, 0)), 2.1, 5, 0.58)
    fino = m.ruido(p, 46.0, 3, 0.55)
    cor = m.rampa(largo, [(0.3, rgb(sombra)), (0.52, rgb(cal)), (0.78, rgb(claro))])
    cor = m.misturar(m.faixa(medio, 0.56, 0.78, 0.0, 0.42), cor, rgb("#8d7c5b"))
    cor = m.misturar(m.faixa(fino, 0.52, 0.86, 0.0, 0.2), cor, rgb("#75664c"))
    # escorrido: riscos finos e verticais que descem do beiral
    risco = m.ruido(m.mapear(p, (15, 0.55, 15)), 1.0, 3)
    escorre = m.conta("MULTIPLY", m.faixa(risco, 0.54, 0.72), m.faixa(z, 1.2, 3.0))
    cor = m.misturar(m.conta("MULTIPLY", escorre, 0.5), cor, rgb("#695a43"))
    # a umidade sobe do chão com a borda irregular
    nivel = m.conta("ADD", z, m.conta("MULTIPLY", m.conta("SUBTRACT", medio, 0.5), 0.9))
    pe = m.faixa(nivel, 0.95, 0.2)
    cor = m.misturar(m.conta("MULTIPLY", pe, 0.78), cor, rgb("#574632"))
    # reboco caído: mais perto do chão, com a beira escura e o barro por baixo
    falha = m.ruido(m.mapear(p, (1, 1.5, 1), (7.1, 0, 0)), 1.7, 5, 0.6)
    perto = m.faixa(z, 1.5, 0.15, 0.0, 0.17)
    soma = m.conta("ADD", falha, perto)
    caido = m.faixa(soma, 0.72, 0.745)
    beira = m.conta("SUBTRACT", m.faixa(soma, 0.69, 0.72), caido)
    cor = m.misturar(m.conta("MULTIPLY", beira, 0.55), cor, rgb("#4b3a29"))
    barro = m.rampa(medio, [(0.3, rgb("#5f4731")), (0.7, rgb("#86684a"))])
    cor = m.misturar(caido, cor, barro)
    m.cor(cor)
    m.rug(0.94)
    altura = m.conta(
        "SUBTRACT",
        m.conta("ADD", m.conta("MULTIPLY", largo, 0.35), m.conta("MULTIPLY", medio, 0.3)),
        m.conta("MULTIPLY", caido, 0.9),
    )
    m.relevo(altura, 0.65, 0.012)
    m.relevo(fino, 0.22, 0.002)
    return m.m


def materiais() -> dict:
    base = ORIGINAL()
    base["vach_cal"] = mat_cal_velha("p_vach_cal")
    base["gach"] = V.mat_gach(
        "p_gach", reboco="#bfb092", escuro="#8e7f62", tijolo="#8a4c35", exposto=0.22
    )
    return base


ORIGINAL = VT.materiais_folha


def principal() -> None:
    saida = C.SAIDA / CHAVE
    saida.mkdir(parents=True, exist_ok=True)
    VT.SAIDA = saida
    VT.TESTES = Path(tempfile.mkdtemp(prefix="vt65_trim_"))  # a prévia da folha publicada fica
    VT.materiais_folha = materiais
    VT.cmd_folhas()
    (saida / "vila_trim.glb").replace(saida / f"{CHAVE}.glb")
    arq = saida / f"{CHAVE}.glb"
    met = {
        "chave": CHAVE,
        "novo": {
            "arquivo": f"assets/blender/{CHAVE}/{CHAVE}.glb",
            "triangulos": 48,
            "dim_m_xyz": [1.96, 0.28, 0.28],
            "dim_studs_xyz": [7.0, 1.0, 1.0],
            "atlas": 4,
            "mb": round(arq.stat().st_size / 2**20, 3),
        },
        "colisao": [],
    }
    (saida / "metricas.json").write_text(json.dumps(met, ensure_ascii=False, indent=1), "utf-8")
    print("ok", CHAVE, met["novo"]["mb"], "MB")


if __name__ == "__main__":
    principal()
