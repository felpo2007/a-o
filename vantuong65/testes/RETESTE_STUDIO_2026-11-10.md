# Reteste no Studio — Vạn Tường '65 (2026-11-10, 01:22–01:34)

Reteste dos 8 bugs de `TESTE_STUDIO_2026-11-10.md` e primeira rodada do autoteste no motor
(`SelfTest.luau`). Feito pelo MCP do Roblox Studio, com o Studio 0.746.0.7461269 e o place do commit
`679dbd7` (`place/VanTuong65.rbxl`). Play solo com 29 bots (14 EUA, 15 VC), greybox (IDs de arte em 0).

**Nada foi salvo no place:** o `.rbxl` continua com 2.815.246 bytes e data de 01:14:20 (a do `git pull`).
Teletransporte, morte do soldado, troca de modo e fim de partida ficaram dentro do Play e sumiram no Stop.

## Resumo
| # | Bug | Resultado |
|---|---|---|
| 1 | Mouse preso nas telas | **Corrigido** no mapa (M), menu (P), loja (L) e mapa de spawn depois de morrer |
| 2 | M e P fechando o que abriam | **Corrigido** |
| 3 | Deitado escorregando | **Escorregão corrigido. O corpo não deita** (problema novo, ver A) |
| 4 | Mira com botão direito | **Corrigido** |
| 5 | Raia do campo de tiro | **Parcial:** EUA 100 m acerta; EUA 200/300 m e VC 100 m param no terreno; VC 200/300 m erram o alvo |
| 6 | Comandos de teste | **Corrigido** (`VT65DevMode`, `VT65DevEnd`) |
| 7 | Mapa de spawn após renascer | **Corrigido** |
| 8 | Output poluído | **Corrigido** |

Autoteste: **6 ok, 4 falhas, 1 pulado.** As 4 falhas: campo de tiro, deitado, pá e medevac.

## Autoteste (`workspace:SetAttribute("VT65SelfTest", true)`)
Rodado às 01:25:19, do lado do servidor, com o jogador como EUA / Alfa / Fuzileiro, vivo no QG. Linhas
exatas do Output:
```
[VT65 TESTE] início
[VT65 TESTE] ok terreno: TerrainReady
[VT65 TESTE] ok bots: 14 bots EUA, 15 bots VC
[VT65 TESTE] FALHA campo de tiro (raia e balística): US 100 5; US 200 5 (parou em Workspace.Terrain); US 300 5 (parou em Workspace.Terrain); VC 100 5 (parou em Workspace.Terrain); VC 200 5 (parou em Workspace.Terrain); VC 300 5 (parou em Workspace.Terrain)
[VT65 TESTE] FALHA deitado sem queda livre: HipHeight 0.20, estado Running, deslizando 0.00 m/s, corpo deitado no servidor: false
[VT65 TESTE] ok arma caída de bot: arma caída com prompt
[VT65 TESTE] ok rádio do squad: papel rifleman sem rádio (esperado)
[VT65 TESTE] pulado animais da vila: sem modelos publicados (AssetIds em 0)
[VT65 TESTE] ok chuva: Rain=1: true; névoa 0.45 → 0.70
[VT65 TESTE] FALHA pá de trincheira: chão à frente desceu 0.48 m (esperado ~1,2 m; a recusa aparece no aviso do jogador)
[VT65 TESTE] FALHA medevac: evacuado=false, suprimento 231 → 236
[VT65 TESTE] ok Offensive + relatório pós-ação: frente S3, prazo 35 min, fim=true, relatório com a captura
[VT65 TESTE] resumo: 6 ok, 4 falhas, 1 pulados
```

**A linha do campo de tiro saiu truncada.** O código imprime `"US 100 m: 5/5"`, mas o Output do Roblox
apaga trechos como ` m: 5/`. Conferi com um `print` de teste: `"US 100 m: 3/5 (x)"` saiu
`"US 100 5 (x)"`, igual no `LogService`. O número de acertos some da linha. Refiz a conta da raia com
o mesmo código do autoteste (tabela no bug 5).

## Os 8 bugs

### 1. Mouse preso nas telas — corrigido
- **Método:** mouse virtual do MCP, com o Studio em primeiro plano. Fora de foco, o Roblox não prende
  o mouse, e o teste não vale (ver "Como repetir").
- **Controle:** vivo, sem tela aberta, `moveTo(200,150)` → o mouse fica em (618, 288), o centro.
- **Com tela aberta** (`VT65MouseFree` visível), o mouse vai aonde foi mandado:

  | Tela | Mouse lido pelo jogo |
  |---|---|
  | Mapa (M) | (300, 358) |
  | Menu do jogo (P) | (400, 258) |
  | Loja (L) | (450, 278) |
  | Mapa de spawn, morto | (1033, 412), em cima do botão do QG; `MouseEnter` disparou |

- **Renascer pelo mapa com o mouse:** com o QG em "PRONTO" (39 s depois de abrir o mapa), o clique deu
  `MB1Down` → `Activated` → `CharacterAdded`. Antes, o botão não recebia nem `MouseEnter`.
- **Antes do primeiro spawn** (lado → squad → papel → QG), os cliques também funcionaram: EUA, "Criar:
  infantry" (squad Alfa), Fuzileiro, QG.
- O `UserInputService.MouseBehavior` continua dizendo `LockCenter` com a tela aberta. Quem solta o
  mouse é o botão `Modal`, não a propriedade.

### 2. M e P fechando o que abriam — corrigido
- **M:** o mapa abre e fica aberto. O segundo M fecha.
  ```
  900.696 UIS began M gp=false
  900.696 VT65Menus.Frame2.Visible=true
  900.896 UIS ended M          <- o mapa continua aberto
  916.297 UIS began M gp=false
  916.298 VT65Menus.Frame2.Visible=false
  ```
  Repeti com a tecla M do teclado real: abriu e ficou.
- **P:** abre na primeira tentativa e fica aberto. O Backspace fecha.
- **Observação:** um segundo P **não** fecha o menu. O contexto "menu" não inclui a camada "global",
  onde está o `game_menu`. O handler faz `setOpen(not gui.Enabled)`, o que sugere que P deveria
  alternar. Decida se P deve fechar o menu.

### 3. Deitado escorregando — escorregão corrigido, corpo não deita
- **Teste:** encosta de 14° em grama a oeste da Colina 43 (−6111, 124, 2461), deitado pela tecla real
  (C segurado), 7 s de medição no servidor:
  - deslocamento **0,00 m**, velocidade máxima 0,00 m/s;
  - estado `Running` nas 28 amostras;
  - `FloorMaterial = Grass` (antes era `Air`);
  - HipHeight 0,20.
- **Problema novo (A):** o corpo não deita. Medido no servidor com o soldado "deitado":
  - cabeça 0,90 m acima do chão;
  - tronco a 2° da vertical;
  - pés 0,59 m abaixo do chão.

  O soldado fica em pé, afundado até a cintura. No cliente o tronco também fica a 2°. A câmera desce
  certo (`CameraOffset` −1,6). Por isso o autoteste deu FALHA ("corpo deitado no servidor: false").

### 4. Mira com botão direito — corrigida
Botão direito segurado: o FOV foi de 70 a **55,2** em ~1 s (alvo 55). Ao soltar, voltou a 69,8.

### 5. Raia do campo de tiro — parcial
O servidor diz no início:
```
[VT65] raia US: 3 peças removidas; 18 raios barrados pelo terreno
[VT65] raia VC: 4 peças removidas; 15 raios barrados pelo terreno
```
Refiz o tiro do autoteste (mesma balística, zeragem, sementes 1–5, atravessando sebe e palha):

| Raia | Acertos | Onde o tiro parou |
|---|---|---|
| EUA 100 m | **5 de 5** | no alvo |
| EUA 200 m | 0 de 5 | terreno a 67–68 m da linha (y ≈ 27) |
| EUA 300 m | 0 de 5 | terreno a 67–68 m da linha |
| VC 100 m | 0 de 5 | terreno a 57–58 m da linha (y ≈ 119) |
| VC 200 m | 0 de 5 | passa pelo alvo e cai no terreno a 214–218 m |
| VC 300 m | 0 de 5 | passa pelo alvo e cai a 539 m (4 no terreno, 1 num dique) |

- **Corrigido:** o passo do tutorial dos EUA ("acerte o alvo de 100 m") tem caminho livre. A sebe
  saiu.
- **Falta:**
  - uma elevação do terreno a ~67 m bloqueia os alvos de 200 e 300 m dos EUA;
  - outra, a ~57 m, bloqueia o de 100 m do VC. O tutorial do fuzileiro VC continua travado;
  - no VC, 200 e 300 m erram sem obstáculo. A causa não foi investigada (zeragem, altura do alvo ou
    aclive).
- **Sugestão:** escolher a direção da raia pela linha de visada livre do terreno (o servidor já conta
  os raios barrados), ou rebaixar o terreno no corredor.

### 6. Comandos de teste — corrigidos
Na barra de comando, do lado do servidor, observando o `Match_State` no cliente:
- `workspace:SetAttribute("VT65DevMode", "Skirmish")`: `mode=Offensive` → `mode=Skirmish`.
- `workspace:SetAttribute("VT65DevEnd", true)`: `ended=true`, e o `VT65AfterAction` abriu com
  "RELATÓRIO PÓS-AÇÃO — OPERAÇÃO STARLITE (VẠN TƯỜNG) / Modo: Skirmish…".
- O autoteste usou o mesmo `VT65DevEnd` no Offensive e passou ("relatório com a captura").

### 7. Mapa de spawn após renascer — corrigido
Renascendo pelo botão do mapa, o mapa e o painel lateral fecharam 38 ms depois do `CharacterAdded`:
```
235.634 QG Activated (QG PRONTO)
235.750 CharacterAdded
235.788 VT65Menus.Frame1.Visible=false
235.788 VT65Menus.Frame2.Visible=false
```

### 8. Output poluído — corrigido
- O Output da sessão tinha **34 linhas** ao fim do autoteste, contando o próprio autoteste e 1 linha
  minha de diagnóstico.
- Do terreno são 12 linhas, contra 420 antes: 10% a 100%, "terreno pronto" e "gerado em runtime".
- O jogo não gerou avisos nem erros.
- Continua 1 aviso do motor, "Player:Move called, but player currently has no character.", antes do
  primeiro personagem.

## Problemas novos
- **A. Juntas do avatar como `AnimationConstraint` (o mais grave):**
  - neste Studio, todas as juntas dos personagens vêm como `AnimationConstraint`, não `Motor6D`: 15 no
    jogador e 15 em cada bot conferido (`Bot_VC_23`, `Bot_US_07`). É a atualização de juntas do avatar
    do Roblox;
  - o `PostureService.setProneJoint` e o `PostureController.motor` só mexem em `Motor6D`. Com isso,
    nenhum personagem deita no servidor nem no cliente;
  - pelo mesmo código, a pose de agachar (joelhos) e a de inclinar (cintura) também não devem
    aparecer. **Não medi** essas duas;
  - **Caminhos:**
    - posar pela `AnimationConstraint` (o `CFrame` dos `Attachment0/1`);
    - usar animações de deitar e agachar;
    - ou desligar a atualização de juntas nas propriedades do Workspace, se o Roblox ainda deixar.

    Não verifiquei qual opção o Studio 0.746 oferece.
- **B. Raia:** elevação do terreno e erros do VC. Ver bug 5.
- **C. Output apaga ` m: N/`:** a linha do autoteste perde o número de acertos. Basta trocar o
  formato, por exemplo `"US 100 m — 5 de 5"`.
- **D. Pá (autoteste FALHA): o chão desceu 0,48 m, e o esperado era ~1,2 m.**
  - Hipótese, **não confirmada**: o buraco tem 0,6 m de largura (2,1 studs), menos que o voxel do
    terreno (4 studs = 1,12 m). O `FillBlock` com Air numa caixa mais estreita que o voxel só reduz a
    ocupação, e sai uma depressão rasa.
  - Valores: `FieldWork.DIG` = 1,8 × 0,6 × 1,2 m.
- **E. Medevac (autoteste FALHA): o bot não foi evacuado.**
  - O suprimento de 231 → 236 é a renda normal, não o +25 do medevac.
  - Os dois UH-34D dos depósitos estavam pousados e "prontos" pela regra: altitude 0,01 e 0,42 m,
    velocidade 0.
  - Hipótese, **não confirmada**: o autoteste cria um segundo UH-34D no depósito 1, onde já há um, e
    a física dos dois sobrepostos pode tirá-lo de "pronto". Ou o bot cai fora do raio de 15 m.
- **F. Depois do autoteste, a partida ficou em Offensive.** O autoteste termina com
  `newMatch("Warfare")`, mas o mapa mostrava "Offensive — 19:20 — frente: S4". Provavelmente a
  rotação depois do `VT65DevEnd` venceu. Não investigado.
- **G. Terreno em 62 s.** Antes eram 26 s. Neste teste havia duas janelas do Studio abertas e o MCP
  ativo, então não compare os dois números sem repetir.

## Como repetir (lições deste teste)
- **MCP com escopo de usuário:** o `Roblox_Studio` já estava em `~/.claude.json` no nível de usuário
  (`mcpServers` do topo), além da entrada antiga do projeto. As ferramentas aparecem em qualquer pasta.
- **Place aberto antes do `git pull` é a versão velha.** Feche com "Não salvar" e reabra. Salvar
  gravaria o place antigo por cima do novo.
- **Coordenadas do `user_mouse_input`:** iguais à `AbsolutePosition` da interface do jogo (as telas
  usam `IgnoreGuiInset`). O `GetMouseLocation` soma 58 px da barra do topo.
- **Trava do mouse:** o Roblox só prende o mouse com o Studio em primeiro plano. Para testar o bug 1,
  traga o Studio para a frente antes. Fora de foco, o mouse do MCP anda livre mesmo sem tela.
- **Mouse real (computer-use):** o jogo não lê o movimento do cursor feito assim, nem em câmera
  Classic. Use o `user_mouse_input` do MCP.
- **`execute_luau` do cliente:** serve para registrar sinais (`Visible`, `Activated`, `Match_State`) e
  ler o resultado depois de cada ação.

## O que não foi testado
- Local Server com 2–4 jogadores (o MCP só inicia Play solo).
- fps (não medi de novo; o greybox não mudou).
- Raia VC na prática (só a conta do autoteste) e o tutorial do VC.
- Pose de agachar e inclinar (ver A).
- F4 (veículos), controle, arte real (IDs em 0) e partida de 60 min.
