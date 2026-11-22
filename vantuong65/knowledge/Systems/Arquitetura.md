---
project: STARLITE
type: system
status: verified
source_paths:
  - default.project.json
  - src/ServerScriptService/Services/Main.server.luau
  - src/ServerScriptService/Modules/MapaBoot.luau
  - src/ReplicatedStorage/Shared/MapaAtivo.luau
  - src/ReplicatedStorage/Shared/Net.luau
  - src/ReplicatedFirst/LoadingScreen.client.luau
  - tests/luau/run.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Arquitetura

## Resumo
Jogo Rojo (Luau strict) com servidor autoritativo. O `default.project.json` monta o DataModel; um script principal sobe os serviços, quatro scripts menores ligam sistemas à parte, e o cliente é um conjunto de controllers independentes. Regras e números ficam em módulos puros de Shared, testados no Lune. Rede em [[Rede-e-Seguranca]].

## Responsabilidades
- Árvore Rojo: ReplicatedFirst (src/ReplicatedFirst), ReplicatedStorage.Shared e VT65AcabamentosSA (modelo), ServerStorage.VT65Build, ServerScriptService.Services e Modules, StarterPlayerScripts.Controllers, Workspace.Estatico (arte fixa). Propriedades de Workspace: StreamingEnabled ligado, StreamingMinRadius 384, StreamingTargetRadius 1280, StreamOutBehavior Opportunistic.
- Services: 5 scripts de servidor (Main, MapService, Comunicacao, Eventos, Itens). Modules: 76 arquivos (serviços e regras de servidor). Shared: 117 arquivos. Controllers: 129 arquivos (os `.client.luau` rodam sozinhos; os demais são módulos que eles requerem).
- Contagens obtidas por listagem de pasta em 2026-11-22; mudam com o tempo.

## Arquivos principais
- Services/Main.server.luau: sobe o servidor.
- Modules/MapaBoot.luau e Shared/MapaAtivo.luau: escolha do mapa (D-243).
- Shared/Net.luau: cria e entrega os remotes.
- ReplicatedFirst/LoadingScreen.client.luau (mais Cortina, Idioma, Acabamento): tela de entrada.
- Services/MapService.server.luau: limites da área e atributo Sector.

## Fluxo
Servidor, em Main.server:
1. `MapaBoot.iniciar()` na primeira linha, antes de qualquer módulo ler o MapConfig.
2. `Net.server()` cria a pasta VT65Remotes.
3. require de todos os módulos (via WaitForChild em Modules).
4. `TerrainRuntime.start` em task.spawn; depois PlayerData.start e CommerceService.start.
5. CaixaService.start dentro de pcall: erro nas caixas só gera aviso e não para o boot.
6. Em ordem: DailyRewardService, TeamService, MatchService, MedicalService, ProgressionService (comentado como "depois dos ganchos"), SpawnService, NascerRetService.iniciar (recebe SpawnService, MatchService e ModoComboio), CombatService, LightingService, PostureService, TunnelService.
7. AssetLoader.start e PreviewService.start em task.spawn; depois BotService, TrapService (comentado: antes da logística, que as arma), LogisticsService, CommanderService, VehicleService, LancadorService, FieldService, TrainingService, AnimalService, RadioService, FieldWorkService, SelfTest, PrivateServer.
8. Imprime "servidor pronto".
Os outros quatro scripts: MapService (tick de 0,25 s; fora dos limites, morte após MapConfig.OutOfBoundsKillSeconds), Comunicacao (Comunicacao.start), Eventos (ContatoService e EventosService), Itens (ArmaNaMao). Todos esperam os remotes com Net.event, que usa WaitForChild.

MapaBoot: cada um dos 5 scripts chama `iniciar()` na primeira linha. O primeiro a chegar monta o mapa (estado novo, montando, pronto); os demais ficam em espera até "pronto". Se o mapa é o padrão (`vantuong`), só grava o atributo VT65Mapa no workspace. Nos retangulares, troca as pastas Data e Data_<id> em VT65Build, chama `Build.features()` e `MapaPontes.montar`. No Studio vale o atributo VT65DevMapa; fora dele só vale o TeleportData de servidor reservado e só com `MapasRet.LIBERADOS` verdadeiro, senão cai no padrão. Se a montagem falha, o erro é relançado depois de marcar "pronto".

Cliente: LoadingScreen.client (ReplicatedFirst) espera game.Loaded, a pasta VT65Remotes (aviso aos 60 s e continua esperando), a interface, a ficha do jogador e o atributo TerrainReady, e libera o CONTINUAR com o essencial. Depois cada Controller em StarterPlayerScripts roda por conta própria e pega remotes com Net.event, Net.func ou Net.unreliable.

## Dependências
- Net, MapConfig, MapaAtivo, MapasRet, Geometry (Shared) usados pelo boot e pelo MapService.
- PlayerData é a base de perfil: Commerce, Caixa, Progression, Campanha dependem dele.
- ProgressionService requer CampanhaService sob demanda (comentário: evita ciclo no carregamento).
- Mapas: [[Map-Index]]. Modos e partida: [[Modos-e-Partida]]. Combate: [[Combate]]. Bots e veículos: [[Bots-e-Veiculos]]. Economia: [[Progressao-e-Economia]]. UI: [[UI-Arquitetura]].

## Invariantes
- Nenhum módulo que leia o MapConfig pode ser requerido antes do `MapaBoot.iniciar()` do script dele.
- `Net.server()` roda antes de qualquer `Net.event` no servidor; é idempotente (devolve a pasta se já existe).
- Script novo de servidor deve chamar `MapaBoot.iniciar()` antes do primeiro require (regra do CLAUDE.md do jogo).
- Shared não depende de Roblox no que é regra pura, para o Lune carregar.
- O place gerado pelo pipeline (Rojo e Lune) é o que vale; salvar pelo Studio quebra a leitura no Lune (CLAUDE.md do jogo, não conferido em código).

## Riscos conhecidos
- Pacote Main.server é uma lista longa e ordenada à mão; dependência de ordem só documentada em comentários (ProgressionService depois dos ganchos, TrapService antes da logística). Não verificado se algum teste cobra a ordem.

## Testes
tests/luau tem 73 arquivos Lune (anim, combate, f2 a f6, nascer, rodada, etc.). O run.luau requer os módulos de Shared e dados de VT65Build para o mundo; o f2.luau requer Rng, Ballistics, Medical, SpawnRules. Rodar, segundo o CLAUDE.md do jogo, é um loop de `lune run tests/luau/<nome>.luau`. Não rodei nesta nota.

## Pendências
- Mapear quais Controllers requerem quais módulos de Controllers não-cliente (não verificado).
- Conferir se o ArtPlan e a ordem do Build são cobertos por teste (não verificado).
