# Instruções para o Claude: VẠN TƯỜNG '65 (jogo de Roblox)

Esta pasta é o jogo **VẠN TƯỜNG '65**: FPS tático 30 contra 30 no Roblox (D-122), na Operação
Starlite (agosto de 1965), mapa 1:1 de 700 × 700 m com cinco objetivos, um em cada canto e a vila de
Xóm Gò no morro do centro (D-128, D-140): A Arrozais, B Serraria (mata fechada), C Xóm Gò (vila em
meio círculo, D-148), D Ponte e Cais (rio do sul) e E Engenho. O mapa é coberto de mata fechada com
lavoura em volta das vilas (D-65). O `CLAUDE.md` da raiz do
repositório é de OUTRO projeto (estratégias de trade). Aqui vale este arquivo. Responda sempre em português.

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
  O XML (`.rbxlx`) do Studio também não serve: o Lune 0.8 não lê o `Content` novo (`<uri>`) nem
  conhece o `LevelOfDetail = SLIM` (D-154).
- Trim sheet da vila (D-159), no jogo desde a v86. As 10 casas dividem 3 folhas de 1024 (M, W e O)
  e o piso de 512:
  - `blender -b --factory-startup -P tools/blender/vila_trim.py -- folhas` assa as faixas e gera o
    portador `assets/blender/trim_vila/vila_trim.glb`;
  - `... -- vila_casa_NN [--sem-previa]` gera `<casa>_trim.glb`. Nele, o grupo Casa vira os nós
    `Trim_M/W/O/P`, sem textura, e o `metricas.json` aponta para ele;
  - rodou o `vila.py` de uma casa? Rode o `vila_trim.py` dela depois;
  - material novo no grupo Casa pede uma faixa em `FAIXAS` ou uma troca em `TROCA`;
  - o telhado fica no atlas de cada casa: na trim sheet ele custou ~35 MB a mais de textura
    (D-165). Antes de passar outro grupo para a trim, meça sem bots, como na D-165;
  - o `AssetLoader` clona a SurfaceAppearance do portador (`AssetIds.Models.vila_trim`) nas peças
    `Trim_*`.
- Arte fixa no place, para o SLIM (D-155; ligada desde a v91, com o Team Create, D-167):
  - copie o conjunto do jogo rodando com `tools/estatico_copiar.luau` (Server, pelo MCP) para
    `assets/estatico/<conjunto>.txt`. Recopie quando o modelo mudar (a cópia guarda malhas e
    texturas). Para conferir o texto, use FNV-1a com a multiplicação dividida
    (`h*403 + ((h*256) % 65536) * 65536`): no Luau, `h * 16777619` perde precisão;
  - ligue-o em `assets/estatico/ativos.json` e rode `uv run python tools/estatico.py` (gera
    `src/Workspace/Estatico` e `Modules/StaticArt`).
  - Construção de peças do `MapLife` (D-168): use `PREFIXO = "Vila_"` no copiador; as peças comuns
    saem em linhas `B` com o CFrame inteiro, e o pivô é o centro da base.
  - Casa que se repete (D-169): `MOLDES = "vila_casa_"` dá um molde por chave e `I` para as outras.
  - Construção nova no `ArtPlan` (D-172): ponha numa passada depois de tudo o que é fixo, com
    folga, e confira no Lune se as construções de antes têm chave, posição, giro e base iguais.
    Peça fixa que muda de lugar fica duplicada, com o aviso "o plano não bateu".
  - Texto grande do Studio (D-169): devolva em pedaços que começam com `VT65COPIA <nome> i/n` e
    grave com `uv run python tools/copia_da_conversa.py <registro.jsonl> <nome> <saida>` (o registro
    da conversa fica em `~/.claude/projects/<projeto>/<sessão>.jsonl`). Nada de transcrever à mão.
- Custo teórico de textura por modelo (D-168): `uv run python tools/textura_custo.py`. Serve para
  escolher o alvo da trim sheet; o custo de verdade se mede no Studio, sem bots (D-165).
  - Medido (D-168): na vista do QG dos EUA, toda a textura de modelo custa ~23 MB de ~133 MB, e a
    base dos EUA ~6 MB. Trim sheet nova só com medida que mostre ganho grande.
  - Para medir, troque a SurfaceAppearance pela `Trim_P` numa cópia; não a apague (sem ela, a
    peça usa a textura do material do Roblox e a memória dobra).
  - No `.model.json`, o Rojo 7.4 quer:
    - o `CFrame` tipado; sem ele, o erro enganoso "no project file was found";
    - os atributos tipados dentro de `Properties`; no topo, ele ignora em silêncio.
  - Peça feita assim não tem a colisão calculada: colide em caixa, e a luz não faz a sombra de
    dentro.
  - Conferir o SLIM (D-167): ele só é gerado no place da nuvem (Play no Studio dele ou no jogo
    publicado), nunca numa cópia local. Não há API do estado: só a cor de depuração (F9 →
    DebugVisualizations → SlimTintMode, ou o menu de visualização do Studio). No cliente,
    `Stats.PerformanceStats.Memory.PlaceMemory.GraphicsSlimModels` mede a memória dos SLIM
    carregados. No Play do Studio, a 1.434 studs da casa, nada saiu do streaming em 6 min (o
    `Opportunistic` quase não libera com memória sobrando), e essa memória ficou em 0.
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
    `Spawn_Request("hq")`. Deixe os bots ligados (sem `BotFill` 0): 5 testes dependem deles
    (D-158). Leva ~2 min; um pedido feito enquanto ele roda não é atendido;
  - `workspace:SetAttribute("VT65DevMode", "Offensive")`: troca o modo (Warfare, Offensive ou
    Skirmish);
  - `workspace:SetAttribute("VT65DevEnd", true)`: encerra a partida e mostra o relatório pós-ação;
  - `workspace:SetAttribute("VT65DevRain", 1)`: força a chuva (0 a 1);
  - `workspace:SetAttribute("VT65DevDrive", "m48a3")`: senta o jogador no motorista do veículo mais
    perto dessa ficha ("sair" tira). Com o Studio atrás de outra janela, o W do MCP não chega:
    para andar, mexa no `DriveVelocity` e no `DriveAttitude` do chassi pelo servidor (D-157);
  - `workspace:SetAttribute("VT65DevBots", "distancias")`: de que distância os bots atiraram, quantas
    rajadas de cobertura, quantos flancos, lances no duelo e fumaças desde a última vez (D-147,
    D-166). A partida (e a marcha dos bots)
    só começa com um jogador em campo.
  - Equilíbrio dos bots (D-162):
    - ponha o soldado em campo;
    - `VT65DevBots = "squad0"` tira os bots do squad dele;
    - `VT65DevMode = "Warfare"` fixa o modo;
    - leia o relatório pós-ação (`VT65AfterAction`) e a faixa da frente (reforços) no cliente.
    - `"depurar"` mostra o rótulo de cada bot (o líder com o atraso do squad).
- O `execute_luau` do MCP roda em outra VM: `require` de módulo do jogo devolve uma CÓPIA. Use
  os ganchos acima ou observe por atributos e remotes.
- Relatórios de teste ficam em `testes/`.
- No Studio pelo MCP (D-149), o cliente às vezes acha que há um controle (glifos de controle na
  tela) e troca de arma e abre a carta sozinho. Nessas sessões nenhum ProximityPrompt aparece (o
  cartão de entrar no veículo não sai): confira o painel no jogo publicado ou pelos testes.
- O teleporte do jogador tem que ser feito do lado do cliente (`Character:PivotTo` no Client): o
  cliente é dono da física do personagem e desfaz o do servidor.
- Captura longe do soldado (D-125): a arte chega ao cliente por distância; antes, peça
  `LocalPlayer:RequestStreamAroundAsync(pos)` no cliente, senão a foto sai vazia.
- Depois do autoteste, a câmera pode ficar em Scriptable longe do soldado (o MCP desfaz a troca de
  tipo). Aí o servidor recusa tiros por "origem": é do teste, não do jogo.
- Medir fps (D-126):
  - o Studio atrás de outra janela limita o jogo a 15 fps. Traga-o para a frente antes:
    `(New-Object -ComObject WScript.Shell).AppActivate(<pid do RobloxStudioBeta>)`;
  - os bots do servidor dividem a CPU com o cliente. `ReplicatedStorage:SetAttribute("BotFill", 0)`
    tira os bots (`nil` devolve);
  - leia também `Stats.RenderCPUFrameTime` e `RenderGPUFrameTime`;
  - com o dono usando o computador, não roube o foco: compare por chamadas de desenho e triângulos
    (`Stats.SceneDrawcallCount`, `ShadowsDrawcallCount`, `SceneTriangleCount`), com a qualidade
    fixa no cliente (`settings().Rendering.QualityLevel = Enum.QualityLevel.Level10`; com o Studio
    atrás, o automático baixa sozinho) e A/B na mesma vista (D-152,
    `testes/DESEMPENHO_2026-11-15.md`).

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
- Modelo novo (props na malha cheia, até 20 mil triângulos, D-66; vegetação até 6 mil, D-135):
  1. gere no ForgeGUI e prepare em studs com `asset_prepare` (pivô na base). O preparo é grátis,
     no máximo 3 de cada vez;
  2. planta: reduza a 6 mil com `tools/vegetacao_6k.py` (põe a `reducao_local` no manifest);
     prop: só use `tools/decimate_glb.py` se passar de 20 mil (na folhagem, com
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
- Tronco que para a bala (D-151): `uv run python tools/troncos.py` mede os caules na malha e grava
  `Modules/TreeTrunks.luau` (cilindros que o `AssetLoader.template` vira peças invisíveis
  `Tronco_N`). Árvore nova da mata: ponha em `ARVORES` no script e rode de novo (o teste da F5
  cobra). `--previa <pasta>` desenha os cilindros sobre a madeira.
- Armas: `tools/armas_parker.py` gera `<arma>_studs_parker.glb` (aço fosco, texturas de 1024) a
  partir do GLB do gerador; é ele que sobe. Rode depois do `fetch_forgegui_assets.py`.
- Armas do Blender (D-146): M70 e Mosin (`tools/blender/armas.py`), Escopeta 12 (`espingarda.py`),
  M16 (`m16.py`) e SKS (`sks.py`, no lugar da do gerador). Rode com
  `blender -b --factory-startup -P tools/blender/<arquivo>.py -- <chave>` (`--montar` para só a
  forma); os pontos saem em `assets/blender/arma_<chave>/pontos.json` e o `weapon_landmarks.py`
  os lê.
- Mira (D-67): `tools/sight_align.py` mede o centro do anel ou do entalhe e a ponta da massa na
  malha (M14, Type 56, RPD, M60; na M60 o modo "topo", D-119; a SKS agora é do Blender, D-146); o
  `weapon_landmarks.py` usa. `--side` desenha a arma de lado para
  achar as janelas de uma arma nova.
- Céu (D-69): `uv run python tools/fetch_sky.py` corta o HDRI em 6 faces (`assets/ceu/`). Os IDs de
  imagem vão no `Sky` do `default.project.json` (resolvidos no Studio, como os do chão). Para conferir
  orientação sem subir, copie as faces para `content\textures` do Studio e use `rbxasset://`.
- Imagens da loja (D-124): a imagem mostra só o que o item dá.
  1. `blender -b --factory-startup -P tools/blender/loja.py -- todas` (Blender 5.3 em
     `C:\Program Files\Blender Foundation`);
  2. `uv run --group arte python tools/loja_sombra.py` (tira o véu de alfa da sombra) e
     `tools/loja_banner.py` (faixa da capa para o destaque);
  3. suba com `upload-assets Loja.`, resolva o ID da imagem de cada decal no Studio (InsertService)
     e grave em `AssetIds.LojaImages`.
- Não dá para testar render pesado no Studio com outro jogo aberto: a GPU de 2 GB do PC do dono
  travou (`DXGI_ERROR_DEVICE_HUNG`) e isso derruba o jogo dele também.
- `Terrain.Decoration` (grama animada) só vai no arquivo do place (`tools/bake_place`): script do
  jogo não pode escrever.
- Chão fotográfico: `MaterialVariant` no bake (texturas do Poly Haven via `tools/fetch_textures.py`).
  O `MaterialVariant` usa o ID da imagem: resolva o decal com `InsertService:LoadAsset` no Studio e
  grave em `AssetIds.GroundImages`.
- Relevo: `tools/relevo_dem.py` (DEM Copernicus, cumes calibrados na carta). Rode depois do
  `crop_world.py`.
- Carta tática (D-171): a do jogo é a página de atlas,
  `uv run --group arte python tools/make_carta.py --dados --estilo atlas` (blocos
  `assets/carta/atlas_*.png`). Mudou o mapa? Gere de novo, tire `Carta.nw/ne/sw/se` do
  `roblox_ids.json` e suba com `upload-assets Carta.nw Carta.ne Carta.sw Carta.se`. O
  `CartaService` resolve a imagem do decal ao abrir o servidor.
- Testar uma tela sem o fluxo do menu: monte o módulo (cópia do `require` no Client) numa
  `ScreenGui` de teste com `ZIndexBehavior = Sibling`. No padrão Global, o fundo da folha
  cobre os blocos.
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
- Mudou regra ou número de design? Registre em `DESIGN.md` (próximo: D-173) e atualize `PROGRESS.md`.
- Tetos de triângulos por modelo: vegetação ≤ 6 mil (D-135), props e herói ≤ 20 mil (`ArtBudget`,
  conferido pelo teste da F5).
- Commits no branch acima, com mensagem em português.
