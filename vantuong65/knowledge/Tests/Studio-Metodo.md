---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Método de teste no Studio

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Studio-Metodo`.

- **Não salve o place pelo Studio:** o Studio grava com outra compressão, que o Lune 0.8 não lê
  ("Decompression failed"). Teste mudanças no Studio pelo MCP, mas gere o `.rbxl` pelo pipeline.
  O XML (`.rbxlx`) do Studio também não serve: o Lune 0.8 não lê o `Content` novo (`<uri>`) nem
  conhece o `LevelOfDetail = SLIM` (D-154).
- Abra uma cópia de `place/VanTuong65.rbxl` (fora do repositório) e dê Play. O place da nuvem só
  tem o código e os dados da última publicação.
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
- Efeitos (D-198):
  - para ver uma explosão sem dano, dispare do servidor
    `VT65Remotes.Fire_Impact:FireAllClients({ id, x, y, z })`;
  - para a foto, prenda a câmera do cliente num ponto com `RunService:BindToRenderStep(..., Camera + 20)`
    (a troca de tipo da câmera o MCP desfaz; o `camera_position` da captura não vale no Play);
  - desligue a grama animada só no cliente com `workspace.Terrain.Decoration = false` e evite a copa
    da mata, que esconde as partículas;
  - partícula: a `smoke_main.dds` some com cor escura; para fumaça escura use a
    `explosion01_smoke_main.dds` com cor clara.
- Depois do autoteste, a câmera pode ficar em Scriptable longe do soldado (o MCP desfaz a troca de
  tipo). Aí o servidor recusa tiros por "origem": é do teste, não do jogo.
  - Lote 89: para testar tiro e munição assim, prenda a câmera à cabeça no cliente com
    `RunService:BindToRenderStep(nome, Enum.RenderPriority.Camera.Value + 20, ...)`. Senão o
    servidor corrige a munição do cliente e parece recarga de graça.
  - O teste com servidor e dois clientes só abre pela interface do Studio (Test › Clients and
    Servers). Pela linha de comando (`-task StartServer`) ele não sobe.
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
- Não dá para testar render pesado no Studio com outro jogo aberto: a GPU de 2 GB do PC do dono
  travou (`DXGI_ERROR_DEVICE_HUNG`) e isso derruba o jogo dele também.
- Testar uma tela sem o fluxo do menu: monte o módulo (cópia do `require` no Client) numa
  `ScreenGui` de teste com `ZIndexBehavior = Sibling`. No padrão Global, o fundo da folha
  cobre os blocos.
- Captura da mira no Studio: o `execute_luau` não deve mudar o tipo da câmera do jogador (o
  Studio desfaz). Ponha o jogador em campo, faça `Aiming = true` no cliente e capture com a
  câmera do jogo.
- O place da nuvem abre no Studio com
  `roblox-studio:1+task:EditPlace+placeId:125635672454807+universeId:10775697296`.
