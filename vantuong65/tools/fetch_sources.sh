#!/usr/bin/env bash
# Baixa de novo as fontes grandes da F0 (não versionadas). Rode a partir de vantuong65/.
# Requer acesso de rede a store.usgs.gov, permanent.fdlp.gov e aos buckets públicos da AWS.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p research/src research/dem research/carta research/sat
UA="Mozilla/5.0"
curl -sSfL -A "$UA" -o research/src/L7014_6739-I_BinhSon_geo.pdf \
  https://store.usgs.gov/assets/yimages/NGA/L701467391_geo.pdf
curl -sSfL -A "$UA" -o research/src/Starlite_TheFirstFight.pdf \
  https://permanent.fdlp.gov/gpo62355/Starlite_TheFirstFight2.pdf
T=Copernicus_DSM_COG_10_N15_00_E108_00_DEM
curl -sSfL -o "research/dem/$T.tif" "https://copernicus-dem-30m.s3.amazonaws.com/$T/$T.tif"
pdftoppm -r 300 -png -singlefile research/src/L7014_6739-I_BinhSon_geo.pdf research/carta/L7014_6739-I_300dpi
uv run python tools/georef_carta.py research/carta/L7014_6739-I_300dpi.png 300 \
  research/carta/carta_area_batalha.tif 262000 1686800 286000 1700000
uv run python tools/fetch_sentinel2.py
