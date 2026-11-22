---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Arte fixa, SLIM e texturas

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Arte-Fixa-e-Texturas`.

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
