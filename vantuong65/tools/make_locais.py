"""Gera research/locais.csv e research/locais.geojson com os locais reais medidos na carta
AMS L7014 6739 I (ed. 003) e convertidos para WGS 84 e para o quadro local do jogo.

As coordenadas "ING-A" foram lidas na carta georreferenciada com quadrícula de 100 m
(tools/grid_crop.py). "precisao_m" é a incerteza de leitura/identificação, não da carta.
Uso: uv run python tools/make_locais.py
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from geo import (  # noqa: E402
    PLAY_ING,
    grid_ref_1965,
    ing_to_wgs_utm,
    m_to_studs,
    wgs_utm_to_local,
    wgs_utm_to_lonlat,
)

FF = "The First Fight (USMC History Division, 2015), p."
CARTA = "AMS L7014 6739 I ed.003"
# nome, tipo, E, N (ING-A), precisão (m), fonte, observação
LOCAIS = [
    (
        "Colina 43 (cume)",
        "colina",
        268545,
        1691655,
        15,
        CARTA,
        "cota 43; FF p.26: 'small knoll... ~400 m SW' da LZ Blue",
    ),
    (
        "LZ Blue",
        "lz",
        268850,
        1691950,
        120,
        f"{FF}26 + mapa p.25",
        "estimada: Nam Yên (3) 100-200 m ao N e Colina 43 ~400 m a SW (FF p.26)",
    ),
    ("Nam Yên (3)", "vila", 268950, 1692150, 80, CARTA, "bloco de casas a NE da LZ Blue"),
    ("Athletic field", "campo", 268400, 1692170, 30, CARTA, "retângulo tracejado 'Athletic field'"),
    (
        "Lạc Sơn (1)",
        "vila",
        268420,
        1691480,
        80,
        CARTA,
        "casas em arco na encosta S/SW da Colina 43",
    ),
    ("Nam Yên (4)", "vila", 269350, 1692870, 80, CARTA, ""),
    (
        "An Cường (2)",
        "vila",
        270030,
        1692850,
        60,
        CARTA,
        "FF: 'heavily wooded village fortified with trench lines'",
    ),
    (
        "Riacho a leste de An Cường (2)",
        "riacho",
        270260,
        1692900,
        30,
        CARTA,
        "FF p.29: 'the streambed just east of An Cuong (2)'",
    ),
    (
        "Colina 30 (cume)",
        "colina",
        270205,
        1693420,
        30,
        CARTA,
        "anel interno da curva 30; FF p.26: 'Hill 30, just north of An Cuong (2)'",
    ),
    ("An Thới (2)", "vila", 269530, 1693200, 80, CARTA, ""),
    ("An Thới (1)", "vila", 270050, 1693690, 100, CARTA, ""),
    ("An Phước (1)", "vila", 270560, 1691600, 80, CARTA, ""),
    ("An Cường (1)", "vila", 271550, 1692360, 60, CARTA, "vila de pescadores junto à praia"),
    (
        "Green Beach (centro provisório)",
        "praia",
        271800,
        1692500,
        200,
        f"{CARTA} + {FF}25",
        "FF: desembarque em 'Green Beach at An Cuong (2)' [sic] / tanques na praia de An Cuong (1);"
        " extensão exata pendente do AAR do RLT-7",
    ),
    ("Cota trigonométrica 22", "controle", 271630, 1692740, 10, CARTA, "△22 ao N de An Cường (1)"),
    ("Cota trigonométrica 10", "controle", 272132, 1691394, 10, CARTA, "△10 ao S da praia"),
    (
        "Cota trigonométrica 45 (Núi Đầm Tre)",
        "controle",
        272057,
        1693790,
        10,
        CARTA,
        "fora da área",
    ),
    ("Marco da Rota 523", "estrada", 268600, 1691133, 20, CARTA, "círculo '523'"),
    (
        "Vạn Tường (1)",
        "vila",
        270200,
        1695700,
        150,
        CARTA,
        "fora da área proposta; referência para a trincheira VC (HistoryNet)",
    ),
]


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "research"
    rows, feats = [], []
    e0, n0, e1, n1 = PLAY_ING
    for nome, tipo, e, n, prec, fonte, obs in LOCAIS:
        E, N = ing_to_wgs_utm(e, n)
        lon, lat = wgs_utm_to_lonlat(E, N)
        x, z = wgs_utm_to_local(E, N)
        dentro = e0 <= e <= e1 and n0 <= n <= n1
        row = {
            "nome": nome,
            "tipo": tipo,
            "grade_1965": grid_ref_1965(e, n),
            "E_ing": e,
            "N_ing": n,
            "lat": round(lat, 6),
            "lon": round(lon, 6),
            "E_wgs84_utm49": round(E, 1),
            "N_wgs84_utm49": round(N, 1),
            "x_local_m": round(x, 1),
            "z_local_m": round(z, 1),
            "x_studs": round(m_to_studs(x), 1),
            "z_studs": round(m_to_studs(z), 1),
            "na_area_jogavel": dentro,
            "precisao_m": prec,
            "fonte": fonte,
            "obs": obs,
        }
        rows.append(row)
        feats.append(
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
                "properties": row,
            }
        )
    with open(out / "locais.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    (out / "locais.geojson").write_text(
        json.dumps({"type": "FeatureCollection", "features": feats}, ensure_ascii=False, indent=1),
        encoding="utf-8",
    )
    for r in rows:
        print(
            f"{r['nome']:<38} {r['grade_1965']:<10} {r['lat']:.5f},{r['lon']:.5f}"
            f"  local ({r['x_local_m']:+7.0f},{r['z_local_m']:+7.0f}) m"
            f"  dentro={r['na_area_jogavel']}"
        )


if __name__ == "__main__":
    main()
