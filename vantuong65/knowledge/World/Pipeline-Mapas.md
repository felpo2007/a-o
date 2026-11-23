---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Pipeline dos mapas

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Pipeline-Mapas`.

- Mapa: os dados em `VT65Build/Data` e o `MapConfig.luau` saem de `tools/crop_world.py`, que
  recorta o mundo gerado (`geo.WORLD_ING`, 4 × 2,4 km) para a área jogável (`geo.PLAY_ING`) com
  150 m de margem. Setores, pontos fortes e QGs ficam nele. Se regerar com `export_roblox.py`, rode
  o `crop_world.py` depois.
  - Cada passo do relevo é feito uma vez e marcado no Grid (`reliefAdded`, `riverCut`,
    `centerLowered`...). D-201: o `centraliza` (baixada do centro, morros, taludes, Arrozais com o
    chão) roda antes do `abre_rio`. Mudou o relevo? Rode o `crop_world.py` duas vezes (a 2ª passada
    das estradas ainda corta feições) e confira que a 3ª não muda nada.
  - Tempo a pé de cada QG a cada objetivo: `uv run python tools/tempos_chegada.py` (`--git <commit>`
    mede um mapa antigo).
  - Mudou o mapa? Refaça a carta e a arte fixa (desligue os conjuntos, recopie do jogo, D-201).
- Expansão da Vila e do Arrozal (D-232): dados em `Modules/Expansao.luau` (`LIGADA = false` tira só ela).
  - Construção: `blender -b --factory-startup -P tools/blender/exp.py -- <chave>` e depois `--trim`
    (`VT65_CPU=1`; receitas em `exp_vila.py` e `exp_arrozal.py`).
  - Planta: `blender -b --factory-startup -P tools/blender/exp_plantas.py -- <chave>` e depois
    `uv run --group arte python tools/expansao_registrar.py plantas` (pé em Y = 0 e cor da folha).
  - Registro: `expansao_registrar.py plano [chaves]`, `upload-assets Models.exp_`,
    `expansao_registrar.py jogo` e `uv run python tools/bases_dados.py`. Modelo refeito: tire a chave
    do `roblox_ids.json` antes de subir.
  - Conferir: `lune run tools/expansao_check.luau` (o antigo igual e nada em cima de captura, nascer,
    estrada ou água). Planta anotada: `tools/expansao_planta.luau` e `.py`.
  - A carta aérea é do tipo Image: depois do `catalogo_imagens.py ids`, copie os IDs novos de
    `Catalogo.aereo_*` para `AssetIds.CartaImages` (o script não atualiza essa tabela).
  - Longe da câmera (D-233): `Shared/ExpansaoLod` diz o que some. Só peça sem colisão: móvel e objeto de
    quintal nunca, para não virar barreira invisível. Rocha nova: `ROCHAS` no `tools/troncos.py`.
  - Sobrados (D-234): receitas em `tools/blender/exp_sobrado.py`. Material de parede em `V.bloco`
    pede regravar o `local` com a altura no 2º eixo; forro de telha fica no grupo Casa.
  - Expansão na arte fixa (D-235): só o visual fica em `assets/estatico/expansao.txt`; a colisão fica
    em `Map.Art.ExpansaoColisao`. Modelo `exp_` refeito ou movido: recopie com `MOLDES = "exp_"` e
    `SO_VISUAL = true` no `estatico_copiar.luau`. O interior fica mais claro; para voltar, tire
    `"expansao"` do `ativos.json`.
- Tamanho das casas (D-236): `lune run tools/casas_escala.luau`. Para rodar de novo, apague antes
  `assets/estatico/ajuste_casas.json` e rode `uv run python tools/estatico.py`; rode o `estatico.py`
  outra vez depois da ferramenta.
- A mata sai de `Modules/Vegetation.luau`, um plano puro que o `tools/ArtEstimate` também usa.
  - O "onde" vem de `VT65Build/Landscape.luau` (D-65): mata, lavoura das vilas, bosque, clareira
    e riacho.
  - O bake usa a mesma paisagem: dique e lâmina d'água só na lavoura.
  - Densidade: `ArtBudget.JUNGLE_DENSITY`.
- Árvores da mata (D-67): prontas do Poly Haven (CC0), com folha em cartão recortado.
  - `uv run python tools/fetch_trees.py` baixa e `uv run --group arte python tools/prep_trees.py`
    prepara (`assets/arvores/<chave>.glb` e uma prévia `_previa.png`);
  - o importador do Open Cloud traz a folha com `AlphaMode = Overlay` e face única; o
    `AssetLoader.template` liga `Transparency` e `DoubleSided` nas peças `Folhas*`;
  - asset grátis de terceiro (Creator Store) não carrega no jogo publicado: só os do dono.
- Tronco que para a bala (D-151): `uv run python tools/troncos.py` mede os caules na malha e grava
  `Modules/TreeTrunks.luau` (cilindros que o `AssetLoader.template` vira peças invisíveis
  `Tronco_N`). Árvore nova da mata: ponha em `ARVORES` no script e rode de novo (o teste da F5
  cobra). `--previa <pasta>` desenha os cilindros sobre a madeira.
- Céu (D-69): `uv run python tools/fetch_sky.py` corta o HDRI em 6 faces (`assets/ceu/`). Os IDs de
  imagem vão no `Sky` do `default.project.json` (resolvidos no Studio, como os do chão). Para conferir
  orientação sem subir, copie as faces para `content\textures` do Studio e use `rbxasset://`.
- Mapas retangulares (D-243): `Shared/MapasRet` (medidas e regras), `uv run --group arte python tools/mapas_ret.py`
  (dados e planta; antes, `lune run tools/trajeto_amostra.luau`), `lune run tools/mapas_check.luau` e, no Blender,
  `tools/blender/ret.py`. Para abrir no Studio: no modo Edit, `workspace:SetAttribute("VT65DevMapa", "frente")`
  (ou `"comboio"`) e dê Play. `MapasRet.LIBERADOS = false` segura os servidores publicados. Script de servidor novo:
  chame `MapaBoot.iniciar()` antes do primeiro `require`. No Comboio, `VT65DevComboio` (Server) = `"dano:<n>"`,
  `"reparo:1"` ou `"reparo:0"` (ponha nil antes de repetir). Conjuntos de nascer: `Shared/NascerRet`. Carta aérea de um
  mapa: `lune run tools/carta_ret.luau <id>` e `uv run --group arte python tools/mapa_aereo.py --mapa <id>`; suba com
  `catalogo_imagens.py`. Votação com os três mapas no Studio: `VT65DevVotoMapas = true` (no Edit).
  Modelo novo dos mapas: receita em `tools/blender/ret_*.py`, `ret.py -- <chave>`, `tools/ret_registrar.py plano`,
  `upload-assets Models.ret_`, `ret_registrar.py jogo` (gera `VT65Build/NosRet`, a colisão por nó) e `mapas_ret.py`.
  No `Bairro`: `miolo` (forçado, pode entrar na captura), `muros` (em trechos, depois das casas), `cais` (base no fundo do
  rio) e `pracas_extra`; `canais` fica no projeto e `NIVEL_DO_PATIO` prende o piso à altura do pátio. O pivô do modelo é o
  centro da caixa: confira a posição pelas colisões do `metricas.json`.
- Lampião das casas (D-241): `Shared/LampiaoInterior` (cor, força, altura), `Modules/InteriorLuz` e
  `Controllers/InteriorVivo`. Chega ao cliente depois do resto da arte, e a luz leva ~15 s para assentar:
  espere antes de fotografar.
- `Terrain.Decoration` (grama animada) só vai no arquivo do place (`tools/bake_place`): script do
  jogo não pode escrever.
- Chão fotográfico: `MaterialVariant` no bake (texturas do Poly Haven via `tools/fetch_textures.py`).
  O `MaterialVariant` usa o ID da imagem: resolva o decal com `InsertService:LoadAsset` no Studio e
  grave em `AssetIds.GroundImages`.
- Relevo: `tools/relevo_dem.py` (DEM Copernicus, cumes calibrados na carta) é do mapa de 2 km
  (D-66); no de 700 m o relevo sai do `crop_world.py` (`mais_relevo` e `centraliza`). Não rode o
  `relevo_dem.py` neste mapa: ele procura cumes que não existem mais.
- Carta tática (D-171): a do jogo é a página de atlas,
  `uv run --group arte python tools/make_carta.py --dados --estilo atlas` (blocos
  `assets/carta/atlas_*.png`). Mudou o mapa? Gere de novo, tire `Carta.nw/ne/sw/se` do
  `roblox_ids.json` e suba com `upload-assets Carta.nw Carta.ne Carta.sw Carta.se`. O
  `CartaService` resolve a imagem do decal ao abrir o servidor.
