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

## Abrir o jogo
1. Abra `place/VanTuong65.rbxl` no Roblox Studio.
2. Test → Local Server com 2–4 jogadores. Se o place não tiver terreno, o servidor gera um
   (`TerrainRuntime`, alguns segundos com o aviso "Preparando o campo de batalha…").
3. Opcional: para salvar o terreno no arquivo, rode na barra de comando
   `require(game.ServerStorage.VT65Build.Build).terrain()` e salve.

Roteiro de teste em `PROGRESS.md`. **O que depende de você está em [`TODO_USUARIO.md`](TODO_USUARIO.md)**.
Publicação automática: `tools/roblox_cloud.py`.

Controles: **jogável do começo ao fim só com controle de Xbox ou PlayStation** (Parte 12). Layout
completo, equivalentes de teclado e mouse e a auditoria em [`CONTROLE.md`](CONTROLE.md).

| Controle | Infantaria |
|---|---|
| RT / LT | atirar / mirar |
| L3 / R3 | correr / corpo a corpo (mirando, L3 prende a respiração) |
| LB / RB | tocar: último item / marcar; segurar: roda de equipamento / comunicação; mirando: inclinar |
| A / B / X / Y | pular / agachar (segurar: deitar) / recarregar (segurar: interagir) / trocar arma (segurar: baioneta) |
| ↑ ↓ ← → | binóculo / bandagem rápida / seletor (segurar: alça) / canal de rádio |
| View | tocar: mapa; segurar: menu do jogo (configurações, papel, loja) |

Veículos, mapa e menus: tabelas em `CONTROLE.md`. F3, F8 e F9 (HUD e gravador de entradas) são
ferramentas do testador.

Monetização: `MONETIZATION.md`. Assets: `assets/forgegui/` (GLBs em escala real, baixados com
`tools/fetch_forgegui_assets.py`) e `assets/clothing/` (moldes procedurais). Para publicá-los e
preencher `Shared/AssetIds.luau`, use `uv run python tools/roblox_cloud.py upload-assets`.

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
for t in run f2 f3 f4 controle f5; do lune run tests/luau/$t.luau; done
lune run tools/art_estimate.luau            # arte estimada por setor (cálculo, não medição)
# modelos do ForgeGUI (não versionados); os reduzidos localmente precisam de libopengl0
uv run --group arte python tools/fetch_forgegui_assets.py
stylua --check src tests/luau tools
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
