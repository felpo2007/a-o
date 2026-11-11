# Instruções para o Claude: VẠN TƯỜNG '65 (jogo de Roblox)

Esta pasta é o jogo **VẠN TƯỜNG '65**: FPS tático 30 contra 30 no Roblox, na Operação Starlite
(agosto de 1965), mapa 1:1 de 2 × 2 km, da Colina 43 a An Cường (2) (D-63), coberto de mata fechada
com lavoura em volta das vilas (D-65). O `CLAUDE.md` da raiz do repositório é de OUTRO projeto
(estratégias de trade). Aqui vale este arquivo. Responda sempre em português.

## Antes de qualquer coisa
1. Leia `PROGRESS.md` (estado e números medidos), `TODO_USUARIO.md` (o que depende do dono) e as
   decisões recentes em `DESIGN.md` (D-45 em diante).
2. O código está no branch `claude/bold-albattani-67hga9`. Traga as novidades com `git pull`.

## Ferramentas
- Roblox: Rojo 7.4, Lune 0.8, StyLua 2.0, luau-lsp (Luau `--!strict`).
- Python: `uv` (grupo `arte` para reduzir malhas: pymeshlab).
- Construir o place:

  ```
  rojo build default.project.json -o build/VanTuong65_base.rbxl
  lune run tools/bake_place.luau
  ```

  O resultado é `build/VanTuong65_F1.rbxl`; copie para `place/VanTuong65.rbxl`.
- Mapa: os dados em `VT65Build/Data` e o `MapConfig.luau` saem de `tools/crop_world.py`, que
  recorta o mundo gerado (`geo.WORLD_ING`, 4 × 2,4 km) para a área jogável (`geo.PLAY_ING`) com
  150 m de margem. Setores, pontos fortes e QGs ficam nele. Se regerar com `export_roblox.py`, rode
  o `crop_world.py` depois.
- **Não salve o place pelo Studio:** o Studio grava com outra compressão, que o Lune 0.8 não lê
  ("Decompression failed"). Teste mudanças no Studio pelo MCP, mas gere o `.rbxl` pelo pipeline.
- **No PC do dono (Windows):**
  - Rojo 7.4.4, Lune 0.8.9, StyLua 2.0.2 e luau-lsp 1.70.1 portáteis ficam em
    `%LOCALAPPDATA%\Programs\vt65-tools`. As definições do Roblox ficam em
    `vt65-tools\luau-lsp\globalTypes.None.d.luau`;
  - o GitHub CLI fica em `%LOCALAPPDATA%\Programs\gh` e é o login do Git para o push;
  - o checkout tem CRLF, então o `stylua --check` acusa todos os arquivos. Cheque numa cópia LF:
    `git -c core.autocrlf=false worktree add --detach <pasta> HEAD`.
- Os modelos do ForgeGUI não vão para o Git:

  ```
  uv run --group arte python tools/fetch_forgegui_assets.py
  ```

  Ele baixa, confere o sha256 e refaz as reduções locais.

## Testes (rode antes de cada commit)
```
for t in run f2 f3 f4 controle f5 f6 atualizacoes movimento uniformes progressao bots; do lune run tests/luau/$t.luau; done
uv run --group arte pytest -q && uv run ruff check .
stylua --check src tests/luau tools
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=<globalTypes.None.d.luau> --sourcemap=sourcemap.json --ignore "src/ServerStorage/VT65Build/Data/**" src
```
O `sourcemap.json` não vai para o Git.

## Teste no Studio (MCP do Roblox Studio)
- Abra uma cópia de `place/VanTuong65.rbxl` (fora do repositório) e dê Play. O place da nuvem só
  tem o código e os dados da última publicação.
- Na barra de comando, do lado do servidor, use os ganchos (só funcionam no Studio):
  - `workspace:SetAttribute("VT65SelfTest", true)`: autoteste de 12 sistemas. As linhas
    `[VT65 TESTE]` aparecem no Output. "Deitado" e "pá" pedem o jogador em campo pelos EUA: do
    lado do cliente, dispare `VT65Remotes.Team_Choose("US")`,
    `Squad_Action({op="create", unit="infantry"})`, `Role_Choose("rifleman")` e
    `Spawn_Request("hq")`;
  - `workspace:SetAttribute("VT65DevMode", "Offensive")`: troca o modo (Warfare, Offensive ou
    Skirmish);
  - `workspace:SetAttribute("VT65DevEnd", true)`: encerra a partida e mostra o relatório pós-ação;
  - `workspace:SetAttribute("VT65DevRain", 1)`: força a chuva (0 a 1).
- O `execute_luau` do MCP roda em outra VM: `require` de módulo do jogo devolve uma CÓPIA. Use
  os ganchos acima ou observe por atributos e remotes.
- Relatórios de teste ficam em `testes/`.

## Assets no Roblox (publicados em 2026-11-10)
- 82 assets publicados; os IDs estão em `Shared/AssetIds.luau` e `assets/roblox_ids.json`. Faltam
  só `uh34d_loop` e os 4 ícones de passe.
- Para subir mais: ponha no `assets/upload_plan.json` e rode
  `uv run --env-file .env python tools/roblox_cloud.py upload-assets`. O script lê
  `ROBLOX_API_KEY` do ambiente, não do arquivo: sem `--env-file` a resposta é 401. Ele sobe só o
  que falta.
- O importador do Roblox gira cada GLB 180° em Y (D-58). Frente de modelo se confere no Studio,
  não no GLB.
- Todo GLB do gerador vem com mapa de metal: folha, palha e madeira refletem o céu como cromo.
  Modelo que não é de metal passa por `tools/matte_glb.py` antes de subir (D-64).
- A mata sai de `Modules/Vegetation.luau`, um plano puro que o `tools/ArtEstimate` também usa.
  - O "onde" vem de `VT65Build/Landscape.luau` (D-65): mata, lavoura das vilas, bosque, clareira
    e riacho.
  - O bake usa a mesma paisagem: dique e lâmina d'água só na lavoura.
  - Densidade: `ArtBudget.JUNGLE_DENSITY`.
- Modelo novo (D-66: vegetação e props na malha cheia, de 8 a 20 mil triângulos):
  1. gere no ForgeGUI e prepare em studs com `asset_prepare` (pivô na base). O preparo é grátis,
     no máximo 3 de cada vez;
  2. não reduza; só use `tools/decimate_glb.py` se passar de 20 mil (na folhagem, com
     `--soltar-bordas`);
  3. registre no `manifest.json` e no `ArtBudget`;
  4. ponha em `FOSCOS` (e em `COLOR_GAIN` se a textura for escura) no `matte_glb`;
  5. suba com `upload-assets`.
- Árvores da mata (D-67): prontas do Poly Haven (CC0), com folha em cartão recortado.
  - `uv run python tools/fetch_trees.py` baixa e `uv run --group arte python tools/prep_trees.py`
    prepara (`assets/arvores/<chave>.glb` e uma prévia `_previa.png`);
  - o importador do Open Cloud traz a folha com `AlphaMode = Overlay` e face única; o
    `AssetLoader.template` liga `Transparency` e `DoubleSided` nas peças `Folhas*`;
  - asset grátis de terceiro (Creator Store) não carrega no jogo publicado: só os do dono.
- Armas: `tools/armas_parker.py` gera `<arma>_studs_parker.glb` (aço fosco, texturas de 1024) a
  partir do GLB do gerador; é ele que sobe. Rode depois do `fetch_forgegui_assets.py`.
- Mira (D-67): `tools/sight_align.py` mede o centro do anel ou do entalhe e a ponta da massa na
  malha (M14, Type 56, SKS); o `weapon_landmarks.py` usa. `--side` desenha a arma de lado para
  achar as janelas de uma arma nova.
- Céu (D-69): `uv run python tools/fetch_sky.py` corta o HDRI em 6 faces (`assets/ceu/`). Os IDs de
  imagem vão no `Sky` do `default.project.json` (resolvidos no Studio, como os do chão). Para conferir
  orientação sem subir, copie as faces para `content\textures` do Studio e use `rbxasset://`.
- Não dá para testar render pesado no Studio com outro jogo aberto: a GPU de 2 GB do PC do dono
  travou (`DXGI_ERROR_DEVICE_HUNG`) e isso derruba o jogo dele também.
- `Terrain.Decoration` (grama animada) só vai no arquivo do place (`tools/bake_place`): script do
  jogo não pode escrever.
- Chão fotográfico: `MaterialVariant` no bake (texturas do Poly Haven via `tools/fetch_textures.py`).
  O `MaterialVariant` usa o ID da imagem: resolva o decal com `InsertService:LoadAsset` no Studio e
  grave em `AssetIds.GroundImages`.
- Relevo: `tools/relevo_dem.py` (DEM Copernicus, cumes calibrados na carta). Rode depois do
  `crop_world.py`.
- Arma nova: acrescente em `tools/weapon_landmarks.py` (frente e frações das mãos, vistas numa
  captura) e, se tiver alça de anel ou entalhe, as janelas em `tools/sight_align.py`. Rode o
  `weapon_landmarks.py` para regenerar `Shared/WeaponArt.luau`. Depois confira a mira no Studio
  (captura mirando): o anel ou o entalhe e a massa devem aparecer no centro sem nada tapando. Sem
  medida, ajuste `EYE_OFFSET_M` (D-60).
- Captura da mira no Studio: o `execute_luau` não deve mudar o tipo da câmera do jogador (o
  Studio desfaz). Ponha o jogador em campo, faça `Aiming = true` no cliente e capture com a
  câmera do jogo.
- O place da nuvem abre no Studio com
  `roblox-studio:1+task:EditPlace+placeId:125635672454807+universeId:10775697296`.

## Regras
- Nunca invente número: todo valor medido sai de código executado ou do Studio. Diga o que não
  foi testado.
- Não use nome, interface, sons nem layout de Hell Let Loose ou de outro jogo.
- Segredos só no `.env` (no `.gitignore`), nunca no código nem no chat.
- ForgeGUI: nunca regenerar um job em `outcome_unknown`. "failed" com `retryable` pode ser
  retomado com `generation_retry`.
- Mudou regra ou número de design? Registre em `DESIGN.md` (próximo: D-90) e atualize `PROGRESS.md`.
- Metas da Parte 2: vegetação ≤ 3 mil triângulos, props ≤ 5 mil, herói ≤ 20 mil (`ArtBudget`,
  conferido pelo teste da F5).
- Commits no branch acima, com mensagem em português.
