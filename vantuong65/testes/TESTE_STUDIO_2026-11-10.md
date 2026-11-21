# Teste no Studio — Vạn Tường '65 (2026-11-10)

Teste feito pelo MCP do Roblox Studio (servidor `RobloxStudio`, `StudioMCP.exe`), das 00:08 às 00:43, com
`place/VanTuong65.rbxl` aberto no Studio 0.746. Roteiro: PROGRESS.md, "Como testar no Studio", e item 3 do
TODO_USUARIO.md.

**Nada foi salvo no place** (o `.rbxl` continua com data de 09/11 23:58:15). Sem commit e sem push. Tudo o que
mexi para testar ficou dentro da sessão de Play e sumiu no Stop:
- teletransportes;
- 1 bot VC removido;
- levantar e renascer pelos remotes do jogo;
- 1 botão renomeado;
- atributo `MatchMode`.

## Resumo
- **Output: nenhum erro de script do jogo** em ~30 min de Play com 29 bots.
- **fps: 60,0 nos 5 setores**, mas o **p99 fica em 18,4–18,8 ms** em todos (meta ≤ 16,7). O valor é igual parado
  ou em qualquer setor: parece oscilação do teto de 60 do Studio, não carga.
- **"[VT65] arte setor": não aparece.** Os IDs em `AssetIds.luau` estão em 0, então a arte não carrega
  (`[VT65] arte carregada: 0 modelos`). Os critérios de arte da F3 e da F5 continuam sem medição.
- **8 problemas encontrados**, 5 deles com a causa achada no código. Lista abaixo, do mais grave ao menos.

## Bugs encontrados

### 1. Mouse travado no centro no mapa de spawn, na loja e no menu (depois do primeiro spawn)
- `WeaponController.client.luau:427` põe `CameraMode = LockFirstPerson` a cada `CharacterAdded` e nunca volta.
  Nenhuma tela usa `Modal`.
- Com o soldado morto e o mapa de spawn aberto, o motor informa `MouseBehavior = LockCenter`. O mouse do MCP
  ficou em (618, 288), o centro da tela, mesmo depois de `moveTo`. O botão "QG PRONTO" era o objeto do topo
  no ponto e não recebeu nem `MouseEnter`.
- **Efeito:** quem joga com mouse não consegue escolher onde renascer depois de morrer. As telas antes do
  primeiro personagem (lado, squad e papel) não têm o problema.
- Para continuar o teste, renasci pelo mesmo remote do botão: `Spawn_Request("hq")`.
- **Sugestão:** liberar o mouse quando o contexto for `map` ou `menu`. Dá para pôr um `TextButton` com
  `Modal = true` visível nessas telas, ou trocar o `CameraMode` enquanto elas estiverem abertas.

### 2. M abre e fecha o mapa no mesmo quadro
Registro de sinais durante um aperto de M (0,13 s):
```
0.050 UIS began M gp=false
0.050 VT65Menus.Frame.Visible=true      <- o mapa abre
0.051 ctx map=true
0.051 IAS Pressed map/key:M             <- a IAS entrega de novo o M que ainda está apertado
0.051 VT65Menus.Frame.Visible=false     <- map_back fecha
0.051 ctx map=false
0.182 UIS ended M
```
- **Causa:** em `Input.luau`, `applyEvent` chama `releaseAll()` quando o contexto muda. Isso limpa `pressed`, e
  a deduplicação deixa de valer. O contexto `map` liga com o M ainda apertado, a IAS dispara `Pressed`, e o
  `map_back` (também no M) fecha o mapa.
- O mesmo acontece com qualquer tecla que abre um contexto onde ela mesma tem outra ação.
- **Sugestão:** marcar o `map_open` e o `menu_open` com `awaitRelease = true`. Outra saída é guardar as teclas
  apertadas como "consumidas" até soltar, em vez de apagá-las.

### 3. Deitado = HipHeight negativo: o soldado fica em queda livre e desliza ladeira abaixo
- `PostureService`: `HipHeight = BaseHipHeight − DROP.prone` = 2,4 − 4,4 = **−2,0**.
- Com isso o Humanoid fica em `Freefall` para sempre, com `FloorMaterial = Air`, inclusive parado.
- Na Colina 43 (chão plano, 0°), deitado, ele acelerou sozinho até **236 studs/s (~66 m/s)**. Desceu
  1.060 studs e 75 studs de altura em 7 s e parou sempre no mesmo lugar, (−5207, 86, 1870).
- Em pé, no mesmo ponto: `Running`, velocidade 0, sem deslizar.
- Bots em pé estão normais: HipHeight 2,40, `Running`, `FloorMaterial = Mud`.
- **Efeitos prováveis do Freefall permanente:**
  - passos por material errados (o chão vira Air);
  - deitado em encosta vira escorregador;
  - o "parado" do médico, que mede a velocidade, pode falhar.
- **Sugestão:** não usar HipHeight negativo. Por exemplo, HipHeight mínimo de ~0,3 com a pose feita pela
  animação, ou o corpo deitado como `PlatformStand` com colisor próprio.
- O soldado já estava deitado quando o teste começou. As primeiras medidas de fps foram com ele deitado; as da
  tabela abaixo são em pé.

### 4. Mira (botão direito) não aproxima
- Com o botão direito segurado por 1,5 s, o FOV ficou em 70 (o alvo é 55 = 70 × 55/70), e o contexto `aim` não
  ligou.
- A entrada chega ao jogo: `IAS Pressed infantry/key:MouseRightButton`, `UserInputService` com
  `gameProcessed = false`.
- Tiro e recarga pelo mesmo caminho funcionam. **Causa não achada.** Vale conferir o `aimToggle` e o handler
  `Input.on("aim", "press")` em `WeaponController.client.luau:285`.

### 5. Uma sebe tapa a raia do campo de tiro dos EUA
- O alvo de 100 m não leva tiro: o tutorial (Fuzileiro 6/9, "acerte o alvo de 100 m") não avança.
- 4 tiros saíram a 0,10–0,13° do centro do alvo, e o raio reto bate em `Workspace.Map.Hedges.PaddyHedge`
  a 76 studs (21 m) da linha de tiro.
- Posições: linha de tiro em (5821,5; 2464); alvo de 100 m em (5821,5; 2821).
- O VC não foi testado.
- **Sugestão:** o `TrainingService` pode apagar sebes e lâminas no corredor da raia, ou escolher um lado livre.

### 6. O comando do guia para Offensive e Skirmish não funciona pela barra de comando
- O comando do PROGRESS ("Como testar", item 4) e do TODO_USUARIO ("relatório pós-ação") é
  `require(game.ServerScriptService.Modules.MatchService).newMatch("Offensive")`.
- Rodado no servidor pelo MCP, que é o mesmo contexto da barra de comando, o `require` devolve **outra cópia**
  do módulo.
- Efeito: só o atributo `MatchMode` mudou (para Offensive, depois Skirmish). A partida de verdade seguiu como
  Warfare: 22 e 17 mensagens `Match_State` com `mode = Warfare`, relógio correndo e sem relatório pós-ação.
- **Sugestão:** um gancho por atributo que o `MatchService` real lê, por exemplo
  `workspace:SetAttribute("VT65DevMode", "Offensive")` antes do Play. Depois, corrigir o guia.

### 7. Menu P não abriu na primeira tentativa
Na primeira sequência o P não abriu o menu. Na segunda abriu, e o Backspace fechou. Não reproduzi a falha.

### 8. Outras observações
- **Mapa de spawn continuou na tela depois de renascer pelo remote** (personagem vivo, `Running`, 100 de vida).
  Pode ser só porque o renascimento não passou pelo botão; com o bug 1, não deu para testar pelo botão.
- **Output poluído:** 420 das 432 linhas são `[VT65] terreno N/3360 blocos`. Imprimir a cada 10% deixaria o
  Output legível.
- **"Player:Move called, but player currently has no character."** aparece uma vez no início, antes do
  primeiro personagem. É aviso do motor.

## Output completo (sem as 420 linhas de progresso do terreno)
```
[VT65] arte carregada: 0 modelos
[VT65] servidor pronto
Player:Move called, but player currently has no character.
[VT65] terreno pronto: 3360 blocos em 25 s
[VT65] túneis e trincheira escavados: 19 blocos
[VT65] terreno gerado em runtime em 26 s
[VT65] campos de tiro prontos (100, 200 e 300 m ao lado de cada QG)
AnalyticsService: LogFunnelStepEvent event fired.
AssistantCommand:20: invalid argument #2 to 'insert' (number expected, got string)   <- script meu de diagnóstico, não do jogo
```
- **Linhas `[VT65] arte setor N` e `[VT65] sebes setor N`:** nenhuma, porque os IDs estão em 0. Elas dependem do
  item 1 do TODO_USUARIO (upload dos assets).
- **Terreno:** o `.rbxl` não tem terreno (`CountCells = 0`). O servidor gerou o terreno em 26 s no início do
  Play (`TerrainRuntime`). Não rodei o passo 2 do guia (`Build.terrain()` + salvar), porque ele exige salvar o
  place.
- Durante a geração, o heartbeat do servidor caiu a ~19 fps (52 ms) por ~26 s.

## HUD de medição (F3) e fps
Condições de medida:
- Studio em primeiro plano (com outra janela na frente, o Roblox limita a 15 fps);
- notebook na tomada (100%);
- Play solo com 29 bots (14 EUA + 15 VC), Warfare;
- personagem em pé, 15 s por ponto, depois de 6 s de streaming no lugar.

A medida própria conta todos os quadros (`RenderStepped`); o HUD usa os últimos 600 quadros.

| Setor (ponto forte) | Posição (studs) | fps médio | p50 / p95 / p99 (ms) | máx (ms) | quadros > 18,2 ms | HUD: fps / p99 | Soldado (HUD) | Heartbeat do servidor |
|---|---|---|---|---|---|---|---|---|
| S1 Colina 43 | −5911, 159, 2661 | 60,0 | 16,6 / 18,1 / 18,6 | 19,1 | 3,9% | 60,0 / 18,8 ms | 1,63 m | 0,22 ms |
| S2 Nam Yên (4) | −3036, 67, −1679 | 60,0 | 16,7 / 18,1 / 18,6 | 19,2 | 4,3% | 60,0 / 18,6 ms | 1,65 m | 0,18 ms |
| S3 An Cường (2) | −610, 73, −1609 | 60,0 | 16,6 / 18,1 / 18,8 | 19,2 | 4,3% | 60,0 / 18,7 ms | 1,65 m | 0,18 ms |
| S4 An Phước (1) | 1285, 60, 2857 | 59,9 | 16,6 / 18,0 / 18,6 | 19,4 | 3,6% | 60,0 / 18,4 ms | 1,65 m | 0,12 ms |
| S5 An Cường (1) | 4821, 82, 142 | 60,0 | 16,7 / 18,0 / 18,5 | 19,2 | 3,6% | 60,0 / 18,5 ms | 1,65 m | 0,17 ms |
| QG dos EUA (fim do teste) | 5821, 24, 2461 | 60,0 | 16,7 / 18,1 / 18,7 | 19,3 | 4,8% | 60,0 / 18,7 ms | 1,65 m | 0,15 ms |

Exemplo do HUD (S3):
```
VT65 — medição
fps médio 60.0 | p99 18.7 ms (meta <= 16,7)
BS 700928  setor 3  0.00 m/s
-
X -513 Z -1658 studs | soldado 1.70 m (meta 1,75)
Sol: az 76.7° el 1.6° (ajuste 0.00°)
```
Leitura:
- **F1 (99% dos quadros ≥ 60 fps): não passa no Studio.** De 2,8% a 5,7% dos quadros ficam acima de 18,2 ms.
  O padrão é igual em todos os setores, deitado ou em pé, então parece o ritmo do teto de 60 do Studio. Falta
  medir no cliente fora do Studio. Pior quadro do teste: 35,4 ms, em S1, com o soldado deitado deslizando
  (bug 3).
- **Greybox sem arte:** nenhum setor pesa mais que outro. O ajuste de `ArtBudget.SECTOR_MAX` depende da arte
  carregar.
- **Altura do soldado:** 1,63–1,72 m (meta 1,75). Varia com a pose.
- **Sol:**
  - no início, elevação −0,1°, azimute 76,2°;
  - aos 31 min de jogo, elevação 6,4°;
  - erro do ajuste 0,00–0,01°.
- **Servidor:**
  - heartbeat 0,12–0,30 ms;
  - física 1,3–1,7 ms por passo;
  - memória do processo do Studio de 3,6 a 4,5 GB;
  - ~89,6 mil instâncias.

## Roteiro "Como testar" (item 4) — resultado
| Item | Resultado | Evidência |
|---|---|---|
| Lado → squad → papel → spawn | Não passei por essas telas | Quando o teste chegou ao clique (~1 min depois do Play), o jogador já estava como EUA / Alfa / Fuzileiro, com personagem e tutorial em 6/9. Não fui eu. |
| Tiro (clique esquerdo) | OK | 3 `Combat_Fire` no servidor (M14) |
| Mira (direito) | **Falha** | Bug 4 |
| Recarga (R) | OK | `Combat_Reload` no servidor |
| Seletor (V) | OK | Aviso na tela. A M14 do fuzileiro só tem semi (esperado); nada vai ao servidor. |
| Captura: 90 s no ponto central | OK | Ver detalhe abaixo |
| Ferimentos, curativo (G), médico (F) | Não testado | Precisa de 2 jogadores. O MCP só inicia Play solo, sem "Local Server". |
| Morte, espera de 60 s e ondas de 20 s | OK (espera) | Ver detalhe abaixo |
| Loja (L) | OK | Abre e fecha |
| Mapa (M) | **Falha** | Bug 2 |
| Menu do jogo (P) | Parcial | Bug 7 |
| HUD F3 | OK | Tabela acima |
| `[VT65] arte setor` e fração das sebes | Não aparece | IDs em 0 |
| Tutorial | Parcial | Painel aparece ("TUTORIAL — Fuzileiro (6/9)"); a raia dos EUA está bloqueada (bug 5) |
| Offensive pelo `newMatch` | **Falha** | Bug 6 |
| Relatório pós-ação (`newMatch("Skirmish")`) | **Falha** | Bug 6 |

Detalhes:
- **Captura no ponto central (An Cường 2):**
  - sozinho no raio, o S3 foi de −1,00 a 0,00 (neutralizado) em ~90 s e virou Neutral +0,11 aos 101 s, ou seja,
    ~180 s para tomar sozinho;
  - com 1 VC no raio (a 134 studs), ficou parado, como manda a regra de disputa;
  - removi esse bot para medir o tempo.
- **Morte e espera:** o soldado caiu com tiro de bot em S3, depois morreu. O mapa de spawn contou 58 s → PRONTO
  aos 60 s no QG e nas reuniões Vau do riacho e Colina 22. Não deu para distinguir as ondas de 20 s.

## O que não foi testado
- **Local Server com 2–4 jogadores:** o MCP só inicia Play solo. Com isso ficaram de fora ferimentos, curativo
  e médico, e os lados opostos com gente.
- **Travessia leste–oeste a pé:** não rodei. Cálculo: 13.929 studs entre as marcas de 50 m das bordas, a
  11,1 studs/s (WalkSpeed medido em pé, 3,1 m/s), dá ~1.255 s ≈ **21 min** em linha reta. É cálculo, não medida.
- **F4:** veículos, comandante, morteiro e RPG.
- **Parte 12:** controle.
- **Features D-48:** acessibilidade, marcação, arma do inimigo, peso, rádio, pá, medevac e animais.
- **Arte com modelos reais:** IDs em 0.
- **Partida de 60 min.**
- **fps fora do Studio.**

## Como o teste foi feito (para repetir)
- **As ferramentas `mcp__Roblox_Studio__*` não apareceram nesta sessão.** O servidor está configurado em
  `~/.claude.json` só para o projeto `C:/Users/Acer/Documents/VanTuong65` (escopo local), e esta sessão rodou
  em `Documents/Front44`.
- Para tê-las direto: abrir a sessão na pasta `VanTuong65`, ou registrar o servidor com escopo de usuário.
- Aqui usei um cliente stdio próprio para o mesmo `%LOCALAPPDATA%\Roblox\mcp.bat` → `StudioMCP.exe`.
- **Ferramentas que o servidor oferece:** `list_roblox_studios`, `get_studio_state`, `start_stop_play`,
  `execute_luau` (Edit/Server/Client), `get_console_output`, `user_keyboard_input`, `user_mouse_input`,
  `screen_capture`, `character_navigation`, `script_read`/`script_grep`/`multi_edit` e geradores.
- **Armadilhas:**
  - cada processo novo do `StudioMCP.exe` leva alguns segundos até o Studio reconectar: esperar o
    `list_roblox_studios` mostrar o place;
  - `execute_luau` roda em outra VM: `require` de um módulo do jogo devolve uma cópia nova (bug 6). Sinais do
    motor (`OnServerEvent`, `GetPropertyChangedSignal`) funcionam para observar o jogo;
  - o mouse do MCP obedece ao `MouseBehavior` do jogo: com `LockCenter`, o clique cai no centro da tela;
  - `instance_path` do `user_mouse_input` não achou um botão que existia
    (`LocalPlayer.PlayerGui.VT65Menus.Frame.Keep...`);
  - fps só com o Studio em primeiro plano.
