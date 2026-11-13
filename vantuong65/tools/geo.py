"""Constantes e conversões compartilhadas do VAN TUONG '65.

Cadeia de coordenadas usada no projeto:
  carta AMS L7014 (Indian 1960 "ING-A" / UTM 49N, grade impressa de 1965)
    -> WGS 84 / UTM 49N   [TR8350.2 3 parâmetros + correção empírica medida no Sentinel-2]
    -> quadro local do jogo (metros, origem no centro da área jogável)
    -> studs do Roblox (1 stud = 0,28 m)
"""

from __future__ import annotations

from pyproj import Transformer

STUD_M = 0.28  # https://create.roblox.com/docs/en-us/physics/units
ING_A_UTM49 = (
    "+proj=utm +zone=49 +a=6377276.345 +rf=300.8017 +towgs84=198,881,317,0,0,0,0 +units=m +no_defs"
)
# Correção empírica (Sentinel-2 menos carta), medida por transectos na Rota 523
# (tools/road_transects.py). Somar às coordenadas WGS 84 vindas da carta.
CORR_DE, CORR_DN = -18.2, +5.3

# Mundo gerado (grade impressa de 1965, ING-A): os 4,0 km (L-O) x 2,4 km (N-S) da D-03, da encosta
# oeste da Colina 43 até o mar na Green Beach. O CENTRO dele é a origem do quadro local (0, 0, 0)
# e não muda, para que as coordenadas de todos os locais, da grade de 1965 e do comandante
# continuem valendo (D-63).
WORLD_ING = (268200.0, 1691200.0, 272200.0, 1693600.0)
# Área JOGÁVEL, em escala 1:1. tools/crop_world.py recorta o mundo para ela.
# - D-63 (2026-11-10): 2 x 2 km da Colina 43 até An Cường (2), E 268,35–270,35 x N 1691,5–1693,5.
# - 2026-11-11 (pedido do dono: "diminuir ainda mais o mapa e fazer ele 1 km x 1 km"): o canto
#   nordeste do recorte anterior, de Nam Yên (4) até o vale do riacho a leste de An Cường (2), com a
#   Colina 30 ao norte. Fica dentro do recorte de 2 x 2 km, então os dados já recortados bastam.
# - 2026-11-13 (pedido do dono: "talvez 500m x 500m"; D-114): de Xóm Gò, no morro do centro, até An
#   Cường (2) com os túneis, E 269,66–270,16 x N 1692,64–1693,14. Fica dentro do de 1 x 1 km.
PLAY_ING = (269660.0, 1692640.0, 270160.0, 1693140.0)

_ing_to_wgsutm = Transformer.from_crs(ING_A_UTM49, "EPSG:32649", always_xy=True)
_wgsutm_to_ll = Transformer.from_crs("EPSG:32649", "EPSG:4326", always_xy=True)


def ing_to_wgs_utm(e: float, n: float, corrected: bool = True) -> tuple[float, float]:
    E, N = _ing_to_wgsutm.transform(e, n)
    if corrected:
        E, N = E + CORR_DE, N + CORR_DN
    return E, N


def wgs_utm_to_lonlat(E: float, N: float) -> tuple[float, float]:
    return _wgsutm_to_ll.transform(E, N)


def play_center_wgs() -> tuple[float, float]:
    """Origem do quadro local: centro do MUNDO gerado (não da área jogável, que é menor; D-63)."""
    e0, n0, e1, n1 = WORLD_ING
    return ing_to_wgs_utm((e0 + e1) / 2, (n0 + n1) / 2)


def wgs_utm_to_local(E: float, N: float) -> tuple[float, float]:
    """Metros no quadro local: x para leste, z para o SUL (convenção Roblox: -Z = norte)."""
    cE, cN = play_center_wgs()
    return E - cE, -(N - cN)


def m_to_studs(m: float) -> float:
    return m / STUD_M


def grid_ref_1965(e: float, n: float, digits: int = 6) -> str:
    """Referência de grade militar no formato de 1965 (quadrado de 100 km 'BS')."""
    if not (200000 <= e < 300000 and 1600000 <= n < 1700000):
        sq = "B" + ("S" if n < 1700000 else "T")
    else:
        sq = "BS"
    k = digits // 2
    ee = int((e % 100000) // 10 ** (5 - k))
    nn = int((n % 100000) // 10 ** (5 - k))
    return f"{sq} {ee:0{k}d}{nn:0{k}d}"
