---
project: STARLITE
type: procedure
status: stale
source_paths:
origem: CLAUDE.md até o commit 5f83094
---
# Ganchos de teste no Studio

Receitas herdadas do `CLAUDE.md`, no texto original. Funcionaram quando foram escritas; confira no
código antes de confiar. Depois de usar e confirmar, rode `uv run python tools/kb.py confere Studio-Ganchos`.

- `VT65DevSemControle = true` (Client, logo depois do Play) ignora o controle fantasma do MCP.
- Na barra de comando, do lado do servidor, use os ganchos (só funcionam no Studio):
  - `workspace:SetAttribute("VT65SelfTest", true)`: autoteste de 12 sistemas. As linhas
    `[VT65 TESTE]` aparecem no Output. "Deitado" e "pá" pedem o jogador em campo pelos EUA: do
    lado do cliente, dispare `VT65Remotes.Team_Choose("US")`,
    `Squad_Action({op="create", unit="infantry"})`, `Role_Choose("rifleman")` e
    `Spawn_Request("hq", nil, ReplicatedStorage:GetAttribute("VT65Rodada"))` (D-209: sem a rodada o
    servidor recusa; a resposta chega no `Spawn_Result`). Deixe os bots ligados (sem `BotFill` 0): 5 testes dependem deles
    (D-158). Leva ~2 min; um pedido feito enquanto ele roda não é atendido;
  - `workspace:SetAttribute("VT65DevMode", "Offensive")`: troca o modo (Warfare, Offensive ou
    Skirmish);
  - `workspace:SetAttribute("VT65DevEnd", true)`: encerra a partida e mostra o relatório pós-ação;
    D-202: a comemoração dura 12 s. Para olhar com calma, com a partida rodando, ponha à mão (Server)
    o `VT65Podio` (JSON com `vencedor` e `linhas`; ids sem jogador viram o manequim do lado), o
    `VT65FaseAte` minutos à frente e `VT65Fase = "comemoracao"`. Não guarde captura com o nome da
    conta nos cartões (use nomes de teste);
  - D-215: as trocas grandes de tela passam pela `ReplicatedFirst/Cortina` (`Cortina.passar(fn,
    titulo, sub)`; a conta em `CortinaCurva`). Para ver no Studio, mude o `VT65Fase` (Server) entre
    "comemoracao", "votacao" e "restauracao": cada troca passa coberta.
  - D-214: no `VT65Podio` cada linha tem `com` (a comemoração; o 1º faz a dele quando a câmera chega,
    ~5,6 s). A comemoração do jogador sai do remote `Comemoracao_Equipar(id)` (só as que ele tem) e
    vai para os atributos `Comemoracao` e `ComemoracoesTem`. O roteiro (chegada, câmera, troca) está
    no `Shared/Comemoracao.PODIO`.
    - Antes de olhar ViewportFrame no Studio, confira se o RobloxPlayerBeta do dono está ocioso
      (~150 MB). Com o jogo dele aberto (2,3 GB), os ViewportFrames pararam de desenhar.
  - D-203: a contagem sai de `VT65InicioEm` (ReplicatedStorage, relógio do servidor). Para medir, anote
    no cliente a hora (`GetServerTimeNow`) em que o texto de `VT65Contagem.Contagem` muda e os sons
    `VT65Contagem_*` do SoundService. Guarde o medidor no ReplicatedStorage, não no PlayerGui: a
    restauração dá corpo novo e o PlayerGui some. O posto do perfil do Studio é 1, e o comandante
    pede o posto 3;
  - `workspace:SetAttribute("VT65DevRain", 1)`: força a chuva (0 a 1);
  - Componentes da interface (D-205, do lado do CLIENTE):
    - `VT65DevTela = "componentes"` abre a vitrine (abas, estados do cartão e do botão);
      `"componentes:fechar"` fecha; `"aba:+1"`/`"aba:-1"` passam a aba pelo caminho do LB/RB;
    - `"confirma"` abre uma confirmação, e a resposta vai para `VT65DevConfirma` ("confirmou" ou
      "voltou");
    - as preferências: `VT65DevMovimento` (true), `VT65DevTransparencia` (0 a 1) e `VT65DevTexto`
      ("Large", "Larger", "Largest"). Valem para o que for desenhado depois.
    - Não feche a confirmação destruindo a janela: a pilha de telas fica com ela por cima, e o
      menu de baixo para de responder. Feche pelo VOLTAR.
  - Lobby (D-206, do lado do CLIENTE):
    - `VT65DevPalco` = "US" ou "VC" troca o acampamento;
    - `VT65DevNome` troca o nome do rodapé (capturas sem o nome da conta);
    - o soldado próprio chega em `PlayerGui.VT65MeuSoldado.Soldado` (atributos Faction, Weapon,
      Parts);
    - as entradas do menu ficam em `VT65MenuPrincipal.Palco.Conteudo.<ARSENAL|MISSOES|PERFIL|
      TUTORIAL|LOJA|ARMARIO|PASSE|CONFIGURACOES>`; o JOGAR continua em `...Conteudo.JOGAR`;
    - D-211: a arma do papel se escolhe pelo pedido do cartão do ARMÁRIO,
      `Arma_Escolher:FireServer("US", "rifleman", "m16")` (fica no perfil, atributo
      `ArmasPreferidas`);
    - na janela estreita do Studio (839 × 656) a coluna da direita fica grande: o enquadramento
      certo de 16:9 só se vê numa tela cheia.
  - Loja (D-207): os códigos se testam pelo mesmo pedido do botão, do lado do cliente:
    `VT65Remotes.Campanha_Action:FireServer({ op = "code_redeem", code = "..." })`. A resposta
    aparece em `VT65Shop.Painel.Conteudo.Codigos.Resgatar.Resposta`. O clique do MCP dentro do
    painel da loja (com escala) não chegou aos botões das páginas que rolam; os das abas chegam.
    As abas têm o nome do id (`loja`, `codigos`...), dentro de um quadro sem nome único: dê um nome
    antes de clicar.
  - Carta de nascer (D-209, do lado do CLIENTE):
    - o painel fica em `VT65Menus.Stage.Carta.Nascer` (`BotaoNascer`, `Alternativa`, `Nome`,
      `Estado`, `Motivo`);
    - os pontos são os `Ponto` de `Carta.Folha.pontos` (o símbolo no TextLabel filho): dê nome único
      antes de clicar;
    - para ver as recusas, ouça o `Spawn_Result` no cliente;
    - na 1ª vez de um perfil, a escolha de idioma (`VT65Idioma.EscolhaDeIdioma.Cartao.pt`) abre por
      cima da carta.
  - HUD de infantaria (D-210, do lado do CLIENTE):
    - `VT65DevTela = "hud_infantaria"` mostra por 8 s os arcos de dano, os estados, os abates, o XP e
      um esquadrão de exemplo (sozinho no servidor não há companheiro);
    - `"hud"` acende o cartão da arma;
    - para o caminho real, do servidor: o `Combat_Hit:FireClient` e o `Combat_Feed:FireAllClients`;
      e a vida pelo `Humanoid.Health`.
  - Celular (D-216): antes do Play, no Edit, `StudioDeviceSimulatorService:SetDeviceAsync` com o
    Galaxy A06 (800 × 360, o pior caso); no fim, `StopSimulationAsync`. O clique do MCP não aciona os
    botões de toque: para inclinar use `VT65DevInclinar` = "ciclo", "esquerda" ou "direita" (Client,
    mirando com `VT65DevGranada = "mirar:9"`) e leia a rolagem da câmera.
  - D-191/D-190 (só Studio): `VT65DevGranada = "6"` lança uma granada a 6 m/s do primeiro
    jogador; `VT65DevTela = "3p"` liga a 3ª pessoa (o teclado do MCP não chega com o Studio
    atrás); `VT65DevTela = "roda_equip:<n>"` abre a roda de equipamento com a ficha n;
  - D-194, postos do lado do CLIENTE (do servidor, o `VT65DevGranada` lança uma granada): o
    `VT65DevGranada` aceita `"vaga:N"` (a tecla N), `"recarga"` e `"mirar:<s>"` (aperta a mira e
    solta depois de s). Para repetir o mesmo valor, ponha nil antes.
    - Altura da arma de 1ª pessoa: o Model da câmera com o atributo `VT65Escala`, no espaço da câmera.
    - Pose baixa de 3ª pessoa sem trocar: o atributo local `VT65Troca` do personagem com
      `"<agora no relógio do servidor>;1;0;99;zzz;n"`.
  - Pá (D-195), do lado do cliente: `"vaga:8"` pega a pá; cada `VT65DevRajada = 0.05` é um aperto
    (uma pazada). O servidor marca a pazada em `VT65PazadaT` e avisa "Buraco: k/6" pelo
    `Logistics_State`. Teste a pá num chão de terra longe do QG (o teleporte do cliente).
  - tela de entrada (D-186): os segundos de cada etapa em atributos `T_<etapa>` do
    `ReplicatedFirst.LoadingScreen`; o botão é `VT65Loading.Fundo.Palco.Continuar`;
  - `workspace:SetAttribute("VT65DevDrive", "m48a3")`: senta o jogador no motorista do veículo mais
    perto dessa ficha ("sair" tira). Com o Studio atrás de outra janela, o W do MCP não chega:
    para andar, mexa no `DriveVelocity` e no `DriveAttitude` do chassi pelo servidor (D-157);
  - `VT65DevVeh` (servidor): `"m151"` (ou outra ficha) cria o veículo à frente do jogador;
    `"destruir"` destrói o mais perto pelo caminho do jogo (D-197). Para sentar num lugar certo, o
    cliente manda `Vehicle_Board { v = modelo, seat = "passenger" }` de perto;
  - `VT65DevRajada` com o lançador na mão (D-200, cliente): aperta o gatilho (tiro, ou recarga com o
    tubo vazio) e escreve `[VT65 LANÇADOR]`. Para repor granadas no teste, ponha `Rockets` e
    `RocketLoaded` no jogador pelo servidor;
  - `VT65DevRotor` (D-199, do lado do CLIENTE): 0 a 1 fixa a rotação vista dos helicópteros (pás
    e disco borrado); `nil` devolve;
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
  - D-231 (Client): `VT65DevLimite` = segundos mostra o aviso de limite (`nil` apaga).
  - Lote 102: `VT65DevHora` (Server) = "manha", "meiodia", "tarde" ou "noite". `VT65DevTela = "armario"`
    abre o armário e `VT65DevArmario = "<categoria>"` troca a categoria (Client; o clique do MCP não
    acerta dentro da loja com escala). A preparação fica em `VT65Menus.Stage.Deploy` (`PaginaTime`,
    `PaginaGrupo.Grupos`, `PaginaClasse`, `BarraBaixo.Principal`, `BarraBaixo.BotaoNascer`).
  - Caixas (D-173): `VT65DevCaixa` = `"bilhetes"` (+5), `"fragmentos"` (+1000), `"pagas"` (liga
    a venda nesta sessão), `"restrito"` / `"falha"` (simulam o PolicyService), `"normal"`,
    `"recibo:<caixa>"` (recibo simulado, sem Robux, e o mesmo recibo de novo). D-174:
    `"creditos"` (+5.000), `"marco:<caixa>"` (guarda uma caixa de marco) e `"partidas:<n>"`
    (marcos de partidas). A aba abre com `VT65DevTela = "caixas"`; feche antes a recompensa
    diária, que abre por cima.
  - Abertura da caixa (D-213, do lado do CLIENTE): `VT65DevAbrir = "<caixa grátis>"` abre pelo
    mesmo caminho do botão ABRIR (guarde antes com `VT65DevCaixa = "marco:<caixa>"`).
    - O painel `PainelRoleta` grava `Abertura_<fase>` (s), `Abertura_PiorQuadroMs`,
      `Abertura_EsperaMs` e `Abertura_Camadas`.
    - Grave com o `video_capture` do MCP e tire os quadros do MP4 com PyAV
      (`uv run --no-project --with av`).
    - O controle fantasma (D-149) aperta o PULAR e o VOLTAR: zere o `GuiService.SelectedObject` a
      cada quadro (RenderStepped) durante a gravação.
  - Roleta das caixas (D-177): no fim da rolagem, a tela grava `RoletaIndice`, `RoletaItem`,
    `RoletaServidor` e `RoletaDesvioPx` no ScreenGui `VT65CaixaAbertura`; confira contra o
    `hist[1]` do `Suprimento_Get`. O PULAR fica em `VT65CaixaAbertura.PainelRoleta.Pular`.
  - Conjuntos em Game Pass (D-176): no Studio o dono tem os 4 passes. Imagem de passe nova:
    monte no cliente com o `ItemArte` (cópia do `require`), troque o nome do jogador e recorte
    a captura. Molde de roupa no cliente só pelo id de imagem resolvido no servidor.
  - ARQUIVO MILITAR (D-175): `VT65DevCaixa = "colecao:<id>"` dá os itens de uma coleção;
    `VT65DevTela = "arquivo"` abre a aba. No Studio o dono tem os Game Passes de uniforme.
  - Clicar na tela pelo MCP: o `user_mouse_input` com `instance_path` funciona mesmo com o Studio
    atrás. Antes, dê nome único ao botão e aos pais (há muitos `Frame` e `Botao` iguais).
  - Lote 119: `VT65DevMenuPC = true` (workspace, no Edit antes do Play) mostra o menu no arranjo de PC. Não aperte Return no menu: ele aciona o JOGAR.
