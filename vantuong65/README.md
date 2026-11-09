# VẠN TƯỜNG '65

FPS tático 30v30 para Roblox, ambientado na Batalha de Vạn Tường (Operação Starlite), de 18 a 24 de
agosto de 1965, em escala 1:1. Esta pasta é independente do resto do repositório e tem ambiente
Python próprio.

- Estado do projeto: [`PROGRESS.md`](PROGRESS.md)
- Decisões e motivos: [`DESIGN.md`](DESIGN.md)
- Assets: [`ASSETS.csv`](ASSETS.csv)
- Fontes da F0: [`research/F0_FONTES.md`](research/F0_FONTES.md)
- Georreferenciamento: [`research/F0_GEORREF.md`](research/F0_GEORREF.md)

## Ferramentas (F0)

```bash
cd vantuong65
uv sync                        # numpy, pyproj, rasterio, scipy, pillow
tools/fetch_sources.sh         # baixa carta, livreto, DEM e Sentinel-2 (não versionados)
uv run python tools/make_locais.py
uv run python tools/make_heightmap.py
uv run python tools/make_previews.py
uv run python tools/road_transects.py   # mede o erro nos pontos de controle
uv run pytest && uv run ruff check .
```

Também é preciso ter `pdftoppm` (poppler-utils) instalado.

## Atribuições
- Carta: Defense Mapping Agency, Series L7014, folha 6739 I, ed. 3-DMA (domínio público dos EUA), via
  USGS/NGA.
- Relevo: Copernicus GLO-30, © DLR e.V. 2010-2014 e © Airbus Defence and Space GmbH 2014-2018,
  fornecido pelo programa COPERNICUS da União Europeia e da ESA.
- Imagem: Sentinel-2, dados Copernicus modificados (2025).
- Histórico: Andrew Jr., R. *The First Fight: U.S. Marines in Operation Starlite, August 1965*.
  USMC History Division, 2015.
