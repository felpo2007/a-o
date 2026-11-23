---
project: STARLITE
type: system
status: verified
source_paths:
  - src/ServerScriptService/Modules/BotService.luau
  - src/ReplicatedStorage/Shared/BotBrain.luau
  - src/ReplicatedStorage/Shared/BotMove.luau
  - src/ReplicatedStorage/Shared/BotNav.luau
  - src/ServerScriptService/Modules/BotSquads.luau
  - src/ServerScriptService/Modules/BotEscolta.luau
  - src/ServerScriptService/Modules/VehicleService.luau
  - src/ReplicatedStorage/Shared/Vehicles.luau
  - src/ReplicatedStorage/Shared/VehicleDrive.luau
last_verified: 2026-11-22
verified_commit: 5f83094
---
# Bots e Veículos

## Resumo
Bots completam cada time (Combatants comuns, mesmas regras de tiro, dano e nascer por ondas). As decisões e números ficam no BotBrain (puro, testável no Lune); BotService faz raios e Humanoid. Veículos (6 fichas dos EUA mais 1 do VC) são montados pelo VehicleService; o motorista humano simula o próprio veículo e o servidor valida. Valores marcados PLACEHOLDER no código seguem a calibrar. Ver [[Combate]], [[Modos-e-Partida]].

## Responsabilidades
- BotService: lotação (fill), pensar por bot em orçamento por quadro, atirar, abrigo, granada, nascer, restaurar na partida nova.
- BotBrain: constantes e funções puras (CROWD, LOD, BUDGET, FILL, SQUAD, NAV, TUNNEL, VEHICLE, fillWant, modeFill, lodLevel, shouldRush, objective, reactionTime).
- BotMove: movimento tipo jogador (perseguição pura de polilinha, inércia, giro limitado, rastro do líder, detector de preso). Runtime: BotLocomotion.
- BotNav: grade de 16 studs (4,48 m), A* em fatias com custo por perfil (infantaria, lagarta, anfíbio). Runtime: BotWorld.
- BotSquads: squads de até 6 (cabeçalho), líder, coluna ou cunha, lances de avanço. BotEscolta: completa squad de jogador até 4.
- VehicleService: criação (build, spawn, spawnAt), assentos por papel, tiro, dano por zona, destruição, respawn, API para bots. VehicleDrive/Vehicles: física e fichas (Shared).

## Arquivos principais
- Modules/BotService: start, fill, restaurar, think, crowdTick, rebalance; onShot (supressão).
- Shared/BotBrain: BotBrain.CROWD, LOD, BUDGET, FILL, OFFENSIVE.
- Modules/BotSquads: tick, assign, objective, covering, advancing. Modules/BotEscolta: setSquad, start.
- Modules/VehicleService: spawn, spawnAt, restaurar, hitVehicle, destroyVehicle, onFire, onBoard, validate, botBoard, botInput, botFire.
- Shared/Vehicles: SPECS (m48a3, ontos, lvtp5, uh34d, m151, m35, peugeot403), PASSENGERS, boardCheck, penetrates, PEN.
- Outros módulos de bot existentes (não detalhados): BotLocomotion, BotWorld, BotTunnels (túneis do VC), BotVehicles (tripulação de blindado), BotDriver, BotTypes.

## Fluxo
1. Lotação: a cada CROWD.stepS (1 s), crowdTick e rebalance. BotBrain.crowdStep decide add, hold ou drop pelo Heartbeat médio (para em 45 Hz, tira abaixo de 35 Hz, sobe acima de 52 Hz). Teto CROWD.perSide = 30 por lado menos humanos (fillWant); no máximo 2 por lado por passo; o atributo BotFill do ReplicatedStorage pode reduzir. modeFill: nos modos LinhaFrente e Comboio o time começa em 16; no Offensive o VC completa até 2/3 do fill.
2. Pensar: no Heartbeat cada bot pensa na vez dele. Intervalo pelo LOD da distância ao humano mais perto: até 150 m a cada 0,3 s, até 300 m a cada 0,6 s, depois 1,0 s. Orçamento: 2,5 ms e 10 pensamentos por quadro (BUDGET).
3. Rota: BotWorld preenche a grade do BotNav; BotSquads pede a rota ao líder; os outros seguem o rastro (BotMove). Longe de humano, a linha é simples e PathfindingService só entra se empacar (limite de 8 caminhos por segundo).
4. Tiro de bot: BotService chama CombatService.fire direto (sem Gatilho.validate); a munição do bot é bot.mag, no próprio BotService. A dispersão é a do BotBrain (aimError, ou a regra do Front 44 quando useF44).
5. Supressão: BotService.start substitui CombatService.fire por um envoltório que chama o original e depois onShot (supressão dos outros bots); erros dessa conta viram warn.
6. Squad de jogador: BotEscolta confere a cada 2 s; squad humano com menos de 4 membros recebe bots até 4 (BotBrain.fillPlan, um por squad por vez); bots não seguem o líder humano, a marca da carta vale 2 min e 45 s depois de chegar.
7. Veículos: depósitos fixos por base (DEPOTS: 2 LVTP-5, M48A3, Ontos, 2 UH-34D, M151, M35 e o Peugeot 403 do VC). Spawn após TerrainReady. Nos mapas retangulares só os leves (M151, Peugeot 403: LEVES, depotNoMapa).
8. Entrar: remote Vehicle_Board (exit, recover, entrar), com Vehicles.boardCheck (mesmo lado, vivo, perto, papel pelo Roles). Sentar só pelo painel.
9. Dirigir: o motorista tem posse de rede e manda telemetria (Vehicle_Telemetry, 0,1 s, valores em 0 a 1); o servidor valida a cada 0,5 s a velocidade horizontal (limite maxKmh x 1,25 + 3 m/s) e marca "Stuck". Bot motorista roda a física no servidor (botDriveStep).
10. Tiro de veículo: Vehicle_Fire; fireFromSeat. M60 montada (e coaxial do M48A3) pelo CombatService.fire com intervalo mínimo 0,09 s; canhões (gun_90, gun_90_heat, rr_106, pg2, rocket_35) por projétil simulado (shoot) com reloadS da tabela GUNS. Ontos: 6 tubos, recarga de 10 s por tubo só parado.
11. Dano: hitVehicle por zona (Vehicles.zoneFromLocal) e penetração (Vehicles.penetrates); integridade começa em 100; helicóptero ou sem blindagem perde 50 por acerto; blindado perde 40 x razão (1 a 2) se penetrar e fere um tripulante (800 J no tronco). Explosões próximas (ExplosionService.onVehicles) reduzem integridade (alcance 8 m para bomba e naval, 3 m para o resto).
12. Destruição: destroyVehicle mata ou fere quem está dentro, detona "veiculo", escurece o casco, some em 30 s e renasce no depósito em RESPAWN_S = 180 s. VehicleService.restaurar (partida nova) remove tudo, tira os sentados e recria os depósitos.

## Dependências
Shared: Vehicles, VehicleDrive, VeiculoDano, Roles, SpawnRules, MapConfig, MapaAtivo, Weapons. Server: CombatService, ExplosionService, MedicalService, SpawnService, MatchService, ModoComboio, CompraVeiculoService (veículo comprado ao nascer), RodadaService (restaurar). Ver [[Arquitetura]], [[Rede-e-Seguranca]], [[Progressao-e-Economia]].

## Invariantes
- Bots usam as mesmas regras de dano e ferimento dos jogadores; só o disparo ignora Gatilho.validate.
- BotService.restaurar e VehicleService.restaurar entram na lista do RodadaService e rodam também na troca de rodada do Comboio.
- Escala: todas as fichas de veículo são multiplicadas por Vehicles.ESCALA = 1,25 no carregamento do módulo.
- Bot não pilota helicóptero nem os carros (botDrive = false em m151, m35, peugeot403).

## Riscos conhecidos
- BotService.start (envoltório de CombatService.fire): a função nova declara só seis parâmetros (até exceptPlayer) e chama o original com seis; VehicleService.fireFromSeat passa um sétimo, `arma` (boca da torreta, D-237). Com o envoltório ativo a boca se perde, e o clarão sai da arma do soldado em vez da torreta. Efeito visual; não testei no Studio.
- BotService (comentário de cabeçalho): diz que completa até 50 por lado, mas BotBrain.CROWD.perSide é 30 (Roles.TEAM_MAX, D-122). Comentário desatualizado.
- Reparo de veículo: não achei reparo de blindado em VehicleService; só desvirar (recover). O reparo existente é o do caminhão do Comboio (ModoComboio). Confirmar se é intencional.
- Valores de dano de veículo, GUNS (v0 e recarga) e RESPAWN_S estão como PLACEHOLDER ou design.

## Testes
Lune: tests/luau/bots.luau, botsmov.luau, veiculos.luau, torre.luau, rotor.luau, compraveiculo.luau, toque_veiculo.luau, f4.luau. Studio: [[Studio-Ganchos]] (VT65DevBots, VT65DevDrive, VT65DevVeh, VT65SelfTest).

## Pendências
- Bots em carros e helicóptero: não implementado (documentado como D-90).
- Carros com "conferir" nas fichas (massa, potência, velocidade do M151, M35 e Peugeot 403) sem fonte fechada. Ver [[Licoes]].
