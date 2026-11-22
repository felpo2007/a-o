---
project: STARLITE
type: system
status: verified
source_paths:
  - src/ReplicatedStorage/Shared/Net.luau
  - src/ServerScriptService/Modules/CombatService.luau
  - src/ReplicatedStorage/Shared/Gatilho.luau
  - src/ServerScriptService/Modules/CommerceService.luau
  - src/ServerScriptService/Modules/ProgressionService.luau
  - src/ServerScriptService/Modules/CaixaService.luau
  - src/ServerScriptService/Modules/SpawnService.luau
  - src/ServerScriptService/Modules/TeamService.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Rede e Segurança

## Resumo
Todos os remotes vêm de listas em Shared/Net.luau e são criados uma vez pelo servidor. O servidor é a autoridade: valida tipo dos argumentos, estado do jogador e, nos sensíveis, limita a taxa. O padrão de limite é local a cada serviço, não central. Boot em [[Arquitetura]].

## Responsabilidades
- Net.Events (RemoteEvent, 67), Net.Unreliable (UnreliableRemoteEvent, 5: Combat_Tracer, Fire_Impact, Fire_Incoming, Fire_Launch, Lancador_Fim) e Net.Functions (RemoteFunction, 13), segundo `tools/kb.py remote`. Total 85. Direção só está em comentários (c->s, s->c); não há checagem de direção em código.
- Outros remotes são criados fora do Net: Vehicle_Telemetry (VehicleService) e os SquadRally_* (FrontService, função `remote`).
- Cada serviço de servidor liga seus próprios OnServerEvent e OnServerInvoke.

## Arquivos principais
- Shared/Net.luau: `Net.server` (cria a pasta VT65Remotes em ReplicatedStorage; devolve a existente se houver), `Net.event`, `Net.unreliable`, `Net.func` (WaitForChild).
- Modules/CombatService.luau: Combat_Fire, Combat_Claim, Combat_Reload, Combat_Ammo.
- Shared/Gatilho.luau: `validate` do tiro.
- Modules/CommerceService, ProgressionService, CaixaService, CampanhaService: posse, compra e moeda.
- Modules/SpawnService, TeamService: nascer, lado, squad, papel.

## Fluxo
Tiro (Combat_Fire, CombatService): exige tabela, cabeça e Humanoid vivos e não Downed; busca o registro de munição pela arma pedida (arma fora do equipamento é recusada); converte origem, direção, relógio e semente com num, clockOf e seedOf e recusa se algo for inválido; roda `Gatilho.validate` (arma, modo, sem munição, recarregando, origem a certa distância da cabeça, lugar fechado, fora do ângulo, cadência; o assento também entra). Se a origem está longe da cabeça e há parede no meio, o tiro sai da cabeça. A munição é descontada no servidor.
Acerto (Combat_Claim): só vale se a semente é de um tiro guardado do próprio jogador, ainda não usado e dentro da janela Hitbox.CLAIM_S; alvo precisa ser um combatente real, peça com zona conhecida, não o próprio atirador; ponto dentro de Hitbox.PATH_TOL da trajetória e dentro da tolerância ao redor da peça; a energia vem da balística no servidor.
Recarga (Combat_Reload): estado e tempo no servidor (reloadUntil), com a vantagem lida do servidor.
Compra e moeda:
- Gear_Buy (ProgressionService): id string, intervalo mínimo de 0,5 s por jogador, depois `Progression.canBuyGear` com posto, passes, equipamento e créditos lidos do perfil. O preço vem da tabela do servidor; o saldo é descontado no servidor e o perfil é salvo.
- Gear_Equip: tipos validados; para skin, o servidor confere posse e lado.
- Commerce_Equip: tipos string; só equipa se `Commerce.canEquip` com a posse do servidor.
- Suprimento_Abrir, Suprimento_Trocar, Suprimento_Loja, Suprimento_Equipar, Arquivo_Resgatar (CaixaService, RemoteFunction): tipo do id validado, caixa gratuita conferida, `guard` com trava busy e intervalo MIN_GAP, gravação por `PlayerData.transact`. Caixa paga só abre pelo recibo do Roblox (`CommerceService.crateReceipt`).
- Campanha_Action (CampanhaService.onAction): op string, mínimo de 0,25 s entre pedidos, perfil obrigatório.
- Recibos: PlayerData.applyReceipt grava por PurchaseId de forma atômica (comentário do módulo).
Nascer (Spawn_Request, SpawnService): recusa após o fim da partida; exige a rodada atual (MatchService.rodada); lado e papel definidos; jogador não vivo; trava `inf.busy` contra pedido repetido; terreno pronto; posto mínimo do papel; id do ponto cortado a 64 caracteres. O CompraVeiculoService também escuta o remote e só anota o ponto (id string com menos de 80 caracteres).
Posse de equipe e papel (TeamService): Team_Choose confere "US" ou "VC", balanceamento e lotação; Role_Choose confere lado e papel pelo Squads; Arma_Escolher confere lado, papel e que a arma está na lista do papel, com intervalo de 0,15 s; Comemoracao_Equipar limita o id a 32 caracteres, com 0,15 s.
Servidor privado: PrivateServer_SetOptions só vale do dono (PrivateServerOwnerId) e passa por validate.

## Dependências
Net, PlayerData (perfil e transact), Combatants, Hitbox, Gatilho, Weapons, Progression, MatchService. Ver [[Combate]], [[Progressao-e-Economia]], [[Modos-e-Partida]].

## Invariantes
- Saldo, posse, munição e dano nunca vêm do cliente; o cliente manda intenção.
- Todo handler visto começa com `type()` nos argumentos; numéricos passam por filtro de finitude (num, finite).
- Limite de taxa existe por serviço, com tabela por jogador limpa na saída: Combat_Ammo (0,2 s), Gear_Buy (0,5 s), Campanha_Action (0,25 s), Vehicle_Order (0,25 s), Vehicle_Telemetry (0,1 s), Settings_Save (1 s), Input_Type (2 s), Kit_Set (0,5 s), Tutorial_Done (2 s), Radio (radioMinGapS), cadência do tiro no Gatilho, Combat_Claim (um uso por tiro).
- Sem perfil (`PlayerData.get` nulo) o handler retorna.

## Riscos conhecidos
- Modules/CommerceService.luau, handler de Commerce_Track: sem limite de taxa; o campo item aceita string de qualquer tamanho e vai para AnalyticsService (dentro de pcall). Só o passo é validado contra a lista Commerce.FunnelSteps. Baixo.
- Modules/TeamService.luau, handlers de Team_Choose e Squad_Action: sem limite de taxa visto. Team_Choose zera a vida do soldado e faz pushSquads para os dois lados a cada troca aceita. Médio-baixo (spam de broadcast e de mortes).
- Modules/CaixaService.luau, handler de Suprimento_Comprar (RemoteEvent): chama `CaixaService.comprar` sem o `guard`; cada pedido dispara um PromptProductPurchase. Só abre o aviso de compra, sem cobrança sem o jogador. Baixo.
- Modules/VehicleService.luau, `onReload` (Vehicle_Reload com op ammo): troca HE/HEAT sem intervalo visto. Só atrasa o próprio disparo. Baixo.
- Não verificado (sem limite visto nas primeiras linhas): MedicalService (Medical_Action), LogisticsService.handleBuild, CommanderService.handle, FieldWorkService.onDig (usa FieldWork.canDig com lastDig), LancadorService; o limite pode estar nas regras internas.

## Testes
Os testes Lune de tests/luau (combate, controle, f2 a f6, nascer, caixas, campanha) cobrem regras puras; não verifiquei se algum chama os handlers de remote. Rodar: `lune run tests/luau/<nome>.luau`.

## Pendências
- Confirmar limites internos dos handlers marcados como não verificados.
- Avaliar um limitador central em Net para os remotes sem taxa (decisão de design, não aplicada).
