# VẠN TƯỜNG '65

FPS tático 30v30 para Roblox, ambientado na Batalha de Vạn Tường (Operação Starlite), de 18 a 24 de
agosto de 1965. A área jogável tem **4,0 × 2,4 km em escala 1:1**. Esta pasta é independente do resto
do repositório.

- Estado e como testar: [`PROGRESS.md`](PROGRESS.md)
- Decisões: [`DESIGN.md`](DESIGN.md)
- Assets: [`ASSETS.csv`](ASSETS.csv)
- Pesquisa: [`research/F0_FONTES.md`](research/F0_FONTES.md),
  [`research/F0_GEORREF.md`](research/F0_GEORREF.md),
  [`research/F0_CORONA.md`](research/F0_CORONA.md)

## Abrir o jogo (F1 greybox + F2 loop central + monetização)
1. Abra `place/VanTuong65.rbxl` no Roblox Studio.
2. Barra de comando: `require(game.ServerStorage.VT65Build.Build).terrain()`
3. Espere a mensagem "terreno pronto" e salve.
4. Test → Local Server com 2–4 jogadores. Roteiro completo em `PROGRESS.md`.

Controles (placeholder):

| Tecla | Ação |
|---|---|
| clique esq. | atirar |
| clique dir. | mirar |
| R | recarregar |
| V | seletor de tiro |
| G | curativo |
| T | torniquete |
| F | curar/reanimar aliado |
| H | desistir |
| M | mapa |
| B | loja |
| F3 | HUD de medição |

Monetização: `MONETIZATION.md`. Assets do ForgeGUI: `assets/forgegui/`, a importar no Studio
(modelos com unidade = stud) e com os IDs colados em `src/ReplicatedStorage/Shared/AssetIds.luau`.

## Estrutura
```
src/                          código Luau (Rojo)
  ReplicatedStorage/Shared/   Units, Geometry, MapConfig (gerado)
  ServerStorage/VT65Build/    gerador de mundo: Base64, WorldData, TerrainBuilder, FeatureBuilder,
                              Build, Data/ (gerado)
  ServerScriptService/        MapService (limites da área)
  StarterPlayer/...           BoundaryController, DebugHud
tools/                        pipeline Python/Lune (pesquisa, terreno, exportação, assar o place)
research/                     fontes, georreferência, locais, heightmaps, imagens de conferência
tests/                        pytest (Python) e tests/luau (Lune)
place/                        place pronto para abrir no Studio
```

## Pipeline completo (desenvolvimento)
Requer: `uv`, `pdftoppm` (poppler) e os binários `rojo` 7.4, `lune` 0.8, `stylua` e `luau-lsp`.

```bash
cd vantuong65
uv sync
tools/fetch_sources.sh                      # carta, livreto, DEM, Sentinel-2 (não versionados)
uv run python tools/make_locais.py
uv run python tools/export_roblox.py        # gera src/**/Data e MapConfig
rojo build default.project.json -o build/VanTuong65_base.rbxl
lune run tools/bake_place.luau              # -> build/VanTuong65_F1.rbxl
cp build/VanTuong65_F1.rbxl place/
# verificação
uv run pytest && uv run ruff check .
lune run tests/luau/run.luau
stylua --check src tests/luau tools/bake_place.luau
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.None.d.luau --sourcemap=sourcemap.json \
  --ignore "src/ServerStorage/VT65Build/Data/**" src
```
Para desenvolver ao vivo no Studio: `rojo serve` com o plugin do Rojo.

## Atribuições
- Carta: Defense Mapping Agency, Series L7014, folha 6739 I, ed. 3-DMA (domínio público dos EUA), via
  USGS/NGA.
- Relevo: Copernicus GLO-30, © DLR e.V. 2010-2014 e © Airbus Defence and Space GmbH 2014-2018,
  fornecido pelo programa COPERNICUS da União Europeia e da ESA.
- Imagem: Sentinel-2, dados Copernicus modificados (2025).
- Histórico: Andrew Jr., R. *The First Fight: U.S. Marines in Operation Starlite, August 1965*.
  USMC History Division, 2015.
