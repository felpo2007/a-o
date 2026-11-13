--!strict
-- Decisões puras dos bots que completam o servidor (Parte 11). Sem API do Roblox: testável no Lune.
-- Bots usam as MESMAS regras de tiro, dano e spawn dos jogadores; aqui só se decide o que fazer.
-- Nível médio que se adapta ao terreno (pedido do dono, 2026-11-11: "bots de nível médio que se
-- adaptam ao ambiente"): reação ao avistar, mira que piora com a distância e a supressão, rajadas
-- curtas do abrigo, postura pelo lugar e granada em quem se esconde. O BotService faz os raycasts
-- e chama estas funções. Testes: tests/luau/bots.luau.
-- D-90 (pedido do dono, 2026-11-11: "faça os bots entenderem como utilizar os veículos, os locais do
-- jogo, os túneis, as granadas" e "a movimentação dos bots linear como se fossem jogadores reais"):
-- percepção com tempo para notar e cone de visão, mira que firma no alvo novo, disciplina de fogo,
-- passo pela situação (andar, trote, corrida, agachado, rastejando), squad em coluna ou cunha,
-- túneis do VC, desconfiança dos EUA e blindados com tripulação de bots. TODOS os números novos
-- ficam aqui (MOVE, SQUAD, NAV, TUNNEL, VEHICLE e os campos novos de DIFFICULTY.medium).
-- 2026-11-12 (pedido do dono depois da v36: "bots estão muito fortes", "eles vêm de muito longe; faça
-- eles avançarem mais em vez de ficarem parados", "os bots enxergam de muito longe"): nível médio de
-- verdade (reação maior, mira pior com a distância e firmando devagar, rajadas curtas, mira no
-- tronco), visão pela vegetação (SIGHT: 120 m no aberto, 40 m na mata, 15 m no capim alto) e avanço
-- (PRESS: quem ataca volta a andar sem alvo nem fogo em cima; parado sem contato tem limite).
-- Medida antes/depois em tests/luau/bots.luau (BotBrain.duelHitChance).
local Movement = require(script and (script :: any).Parent.Movement or "./Movement") :: any
local Corpo = require(script and (script :: any).Parent.Corpo or "./Corpo") :: any

local BotBrain = {}

BotBrain.C = {
	senseRangeM = 120, -- teto do alcance de notar (o de cada alvo sai de BotBrain.sightRange); era 300
	objectiveSpreadM = 30, -- espalhamento em volta do ponto forte
	stuckSeconds = 3,
	thinkS = 0.3, -- cada bot pensa a cada 0,3 s (escalonado). PLACEHOLDER de desempenho
	maxLosChecks = 4, -- raios de visada por pensamento: só os inimigos mais próximos. PLACEHOLDER
	-- Altura dos olhos (m) para medir o abrigo: deitado, agachado, em pé. Medidas no soldado de 1,75 m
	-- (0,35 / 1,0 / 1,6 m) levadas ao de 2,0 m pelo Corpo.K (D-98; PostureService.DROP também foi
	-- multiplicado por K). PLACEHOLDER de pose.
	probeM = { 0.35 * Corpo.K, 1.0 * Corpo.K, 1.6 * Corpo.K },
	probeLenM = 4, -- o obstáculo precisa estar a até 4 m do lugar, na direção do inimigo
	scanHeightM = 0.3, -- altura dos raios em volta: pega dique baixo, tronco, parede e moita
	coverRays = 8, -- raios em volta do bot na busca de abrigo
	coverVerify = 2, -- candidatos medidos por busca (além do lugar atual)
	standoffM = 0.7, -- distância do lugar até a face do obstáculo
	peekStepM = 1.4, -- passo de lado para atirar de trás de tronco ou parede
	relocateMinM = 3, -- abrigo novo longe do anterior
	arriveM = 0.8,
	holdRadiusM = 10, -- perto do ponto forte: procura abrigo e espera (emboscada)
	torsoHalfM = 0.25, -- meio tronco (m), alvo da conta de acerto. PLACEHOLDER
	-- mesmo tempo de recarga do jogador (CombatService.RELOAD, PLACEHOLDER lá)
	reloadS = { rifle = 3.0, mg = 7.0, pistol = 2.5, launcher = 3.0 } :: { [string]: number },
	-- custo máximo de uma busca: 1 (chão) + raios em volta + lugar atual (3 + 2) + candidatos (1 + 3 + 2)
	searchCost = 1 + 8 + 5 + 2 * 6,
}

export type Difficulty = {
	reaction: { number }, -- s do avistar ao 1º tiro: mínimo, máximo
	alertedReaction: number, -- quem já está em combate reage mais rápido (multiplica)
	suppReactionS: number, -- s a mais com supressão máxima
	spotStance: { [string]: number }, -- alcance de detecção pela postura do alvo
	aimBaseRad: number, -- erro de mira (1σ, rad) parado, em pé, sem supressão, a 0 m
	aimRangeM: number, -- o erro angular dobra a cada aimRangeM metros (enxerga pior longe)
	aimMoving: number,
	aimSuppression: number, -- supressão máxima multiplica o erro por 1 + isto
	aimStance: { [string]: number },
	aimArmHurt: number,
	recoilRad: { [string]: number }, -- recuo: erro (1σ) somado a cada tiro seguido da rajada
	recoilMaxRad: number,
	volley: { [string]: { number } }, -- tiros por exposição (rajada curta)
	aimedGap: { number }, -- s entre tiros pensados (fuzil semiautomático, pistola)
	openPause: { [string]: { number } }, -- s de pausa entre rajadas sem abrigo
	hideTime: { number }, -- s escondido entre rajadas
	burstsPerCover: { number }, -- rajadas antes de trocar de abrigo
	peekMaxS: number, -- tempo máximo exposto procurando o alvo
	closeM: number, -- inimigo mais perto que isto: luta onde está
	coverSearchM: number, -- raio da busca de abrigo
	searchEveryS: number, -- intervalo mínimo entre buscas
	recheckS: number, -- confere se o abrigo ainda protege (flanco)
	nearMissM: number, -- bala passando a menos disto assusta
	suppPerRound: number,
	suppHit: number,
	suppTauS: number, -- a supressão cai pela metade em ~0,7 x isto
	pinnedAt: number, -- acima disto não levanta a cabeça
	underFireAt: number, -- acima disto se abaixa (deita no aberto)
	retreatHealth: number, -- vida abaixo disto: recua para abrigo
	woundedHideMult: number,
	grenade: {
		minM: number,
		maxM: number,
		cooldownS: number,
		retryS: number,
		perLife: number,
		memoryS: number, -- só joga em quem viu há pouco
		friendlyClearM: number,
		chance: number, -- chance por pensamento, com tudo certo (não joga na hora)
	},
	rayRate: number, -- raios de abrigo por segundo, por bot
	rayCap: number,
	-- D-90: percepção (notar leva tempo; fora do cone da frente, mais ainda; atrás, só ouvindo)
	noticeS: number, -- s para notar alguém de frente, perto, em pé
	noticePer100M: number, -- s a mais a cada 100 m
	noticeStill: number, -- alvo parado e abaixado: multiplica
	noticeFiring: number, -- alvo atirando (clarão, estampido): multiplica
	noticeSide: number, -- fora do cone da frente: multiplica
	fovDeg: number, -- meio ângulo do cone da frente
	rearDeg: number, -- além disto (das costas) não vê; só ouve
	hearShotM: number, -- ouve o tiro do inimigo a esta distância e vira para o rumo
	-- D-90: mira que firma (o 1º tiro num alvo novo é apressado)
	settleS: number, -- s seguindo o alvo até a mira firmar
	settleMult: number, -- erro do tiro no instante em que nota o alvo (multiplica)
	-- D-90: disciplina
	fireMaxM: { [string]: number }, -- não atira além disto (por tipo de arma)
	strafeFireM: number, -- atira andando de lado só até esta distância
	calloutS: { number }, -- s até o squad saber do contato que um viu (aviso de voz)
	suppressS: { number }, -- fogo de supressão na última posição vista: intervalo entre rajadas
	suppressMaxAgeS: number, -- só suprime posição vista há até isto
}

-- Uma tabela por nível. Todos os números são PLACEHOLDER de design (sem fonte), a calibrar em
-- partida no Studio. 2026-11-12 ("bots estão muito fortes"): os valores da v36 ficam no comentário
-- de cada linha; a chance de acertar um jogador parado em 3 s, antes e depois, sai do teste bots.luau.
BotBrain.DIFFICULTY = {
	medium = {
		reaction = { 0.8, 1.4 }, -- era 0,4–0,8 s
		alertedReaction = 0.8, -- era 0,7
		suppReactionS = 0.8, -- era 0,5
		spotStance = { stand = 1, crouch = 0.6, prone = 0.35 }, -- era 1 / 0,75 / 0,5
		-- 3 mrad e dobra a cada 200 m (era 2,2 mrad dobrando a cada 500 m): a mira piora rápido longe.
		-- Tiro firme no tronco: 50 m ~67%, 100 m ~18%, 200 m ~3% (antes 93 / 43 / 10%; teste bots.luau)
		aimBaseRad = 0.003,
		aimRangeM = 200,
		aimMoving = 2.0,
		aimSuppression = 3.0, -- era 2: sob fogo, a mira abre bem mais
		aimStance = { stand = 1, crouch = 0.85, prone = 0.7 },
		aimArmHurt = 1.5,
		recoilRad = { rifle = 0.0015, mg = 0.003, pistol = 0.003, launcher = 0 }, -- era 0,8 / 1,5 / 2 mrad
		recoilMaxRad = 0.012, -- era 6 mrad
		volley = { rifle = { 1, 3 }, mg = { 3, 5 }, pistol = { 1, 2 }, launcher = { 1, 1 } }, -- era 2–3 / 4–8
		aimedGap = { 0.5, 0.9 }, -- era 0,35–0,7 s
		openPause = { rifle = { 1.2, 2.4 }, mg = { 1.0, 2.0 }, pistol = { 0.8, 1.4 }, launcher = { 3, 5 } }, -- era 0,8–1,7 / 0,6–1,4
		hideTime = { 1.5, 3.0 },
		burstsPerCover = { 2, 4 },
		peekMaxS = 2.5,
		closeM = 12,
		coverSearchM = 15,
		searchEveryS = 1.5,
		recheckS = 2,
		nearMissM = 3,
		suppPerRound = 0.22,
		suppHit = 0.7,
		suppTauS = 4,
		pinnedAt = 0.45,
		underFireAt = 0.05,
		retreatHealth = 55,
		woundedHideMult = 2,
		grenade = {
			minM = 15,
			maxM = 35,
			cooldownS = 20,
			retryS = 4,
			perLife = 2,
			memoryS = 8,
			friendlyClearM = 8,
			chance = 0.15,
		},
		rayRate = 12,
		rayCap = 30,
		-- D-90 (PLACEHOLDER): jogador mediano que vê primeiro ganha o 1 x 1; squad organizado dá
		-- trabalho (avisa o contato, suprime, avança em lances e joga granada atrás do dique)
		noticeS = 0.5, -- era 0,25 s
		noticePer100M = 1.0, -- era 0,35 s a cada 100 m
		noticeStill = 2.5, -- era 1,8: agachado ou deitado e parado demora mais a ser notado
		noticeFiring = 0.4,
		noticeSide = 2.5, -- era 2,2
		fovDeg = 50, -- era 60: cone da frente mais estreito
		rearDeg = 100, -- era 125: além de 100° da frente não vê (só ouve)
		hearShotM = 150,
		settleS = 3.0, -- era 1,5 s: a mira firma devagar no mesmo alvo
		settleMult = 3.0,
		fireMaxM = { rifle = 180, mg = 250, pistol = 50, launcher = 0 }, -- era 320 / 450
		strafeFireM = 80,
		calloutS = { 1.0, 2.2 },
		suppressS = { 3, 6 },
		suppressMaxAgeS = 6,
	} :: Difficulty,
}

---------------------------------------------------------------------------------------------
-- D-90: números novos (todos PLACEHOLDER de design, a calibrar no Studio). Velocidades em m/s
-- saem do Shared/Movement (as mesmas âncoras da animação: andar 1,4, trote 3,1, corrida 5,5).
---------------------------------------------------------------------------------------------

-- Movimento de jogador de verdade (BotMove e BotLocomotion)
BotBrain.MOVE = {
	-- giro do corpo (°/s) pelo passo: correndo vira devagar (curva aberta); deitado, quase nada
	turnDegS = { still = 260, ads = 260, walk = 240, jog = 200, sprint = 150, crouch = 180, prone = 45 } :: {
		[string]: number,
	},
	aimTurnDegS = 300, -- virando para mirar
	lookaheadS = 0.6, -- perseguição pura: ponto do caminho ~0,6 s à frente
	lookMinM = 1.2,
	lookMaxM = 4.0,
	arriveM = 0.5,
	stopDecel = 3.0, -- m/s²: freada confortável ao chegar (sem passar do ponto, sem girar no lugar)
	cornerDeg = 55, -- curva mais fechada que isto nos próximos metros: desacelera para o andar
	cornerLookM = 3.0,
	stuckS = 1.5, -- s andando menos que stuckFrac do esperado: preso
	stuckFrac = 0.25,
	legM = 70, -- trecho pedido ao PathfindingService
	prefetchM = 22, -- faltando isto do trecho, já pede o próximo (não para no fim)
	directM = 10, -- até isto vai direto, se o raio do joelho não bate em nada
	sprintThreatM = 150, -- inimigo conhecido a menos disto: atravessa o aberto correndo
	walkCalmM = 60, -- sem contato, a menos disto do objetivo: anda (cauteloso). Era 120 (2026-11-12: avançar)
	crawlMaxM = 4, -- deitado só se arrasta até isto; mais longe, levanta
	crouchMoveMaxM = 8, -- agachado só anda até isto; mais longe, levanta
	pathEveryS = 2, -- intervalo mínimo entre pedidos de caminho do mesmo bot
	pathConcurrent = 2, -- cálculos de caminho ao mesmo tempo no servidor
	scanDeg = 35, -- andando cauteloso, olha ±35° para os lados
	scanS = { 2.5, 5 },
}

-- Squad de bots (BotSquads): segue um líder em coluna (mata, vila) ou cunha (aberto)
BotBrain.SQUAD = {
	size = 6,
	spacingM = 6, -- entre homens
	wedgeSideM = 5, -- afastamento lateral na cunha
	trailStepM = 1.5, -- rastro do líder: um ponto a cada 1,5 m
	trailMaxM = 90,
	catchUpM = 10, -- atrás do lugar mais que isto: trota
	sprintBehindM = 25, -- ...mais que isto: corre
	leaderSlowM = 25, -- o último atrasado mais que isto: o líder anda
	leaderWaitM = 45, -- ...mais que isto: o líder espera
	leaderWaitMaxS = 10, -- 2026-11-12: e espera no máximo isto (depois segue andando; o atrasado alcança)
	boundZoneM = 150, -- 2026-11-12: a até isto do objetivo atacado, com contato recente, o squad vai em lances
	boundPauseS = { 2, 4 }, -- ...parando isto entre um lance e outro (o lance dura boundS)
	boundContactS = 30, -- contato com até isto de idade conta como "recente"
	regroupM = 60, -- longe do líder mais que isto: vai até ele pelo caminho
	deployM = 70, -- a esta distância do objetivo o squad se espalha pelos lugares de cada um
	stagingS = { 4, 8 }, -- parada na base de partida antes do assalto
	boundS = { 6, 10 }, -- duração de cada lance (metade avança, metade cobre)
	boundAdvance = 1.6, -- peso do avanço na nota do abrigo de quem está no lance
	defendArcDeg = 70, -- defesa: arco virado para o inimigo
	defendR = { 14, 36 },
	contactShareM = 250, -- contato de um vale para o squad até esta distância
	routeEveryS = 45, -- refaz a rota estratégica (o objetivo pode ter mudado)
	offRouteM = 45,
}

-- Rota estratégica (BotNav), custo por célula de 16 studs (4,48 m, a grade do terreno). O custo
-- multiplica a distância; 1 = trote em chão firme. Pedido do dono: arrozal alagado caro; dique,
-- trilha e sebe baratos. As trilhas da carta não existem no chão (D-87): o dique é a trilha.
-- 2026-11-12: estradas de terra batida (Data/Roads) com custo próprio (road): o blindado prefere a
-- estrada; no riacho a estrada passa por aterro (o custo do riacho não vale nela).
BotBrain.NAV = {
	weight = 1.3, -- A* com heurística inflada (rota até 30% pior, muito menos nós)
	expandPerFrame = 900, -- nós por quadro (fatia de tempo)
	frameBudgetS = 0.002, -- e no máximo 2 ms por quadro
	simplifyLookCells = 40,
	simplifySlack = 1.06,
	profiles = {
		-- infantaria: 1/velocidade do Movement (mata 0,93; arrozal 0,62) + exposição no aberto
		infantry = {
			forest = 1.08,
			grove = 1.05,
			clear = 1.25,
			farm = 1.15,
			paddy = 2.4,
			dike = 0.85,
			hedge = 0.9,
			house = 3,
			stream = 3.5,
			sea = math.huge,
			trench = 0.8,
			road = 1.0, -- estrada: firme, mas exposta
			maxGrade = 1.2,
			upCost = 1.4,
			downCost = 1.0,
		},
		-- lagarta (M48A3, Ontos): 1/"ride" do VehicleDrive (mata 0,5; capim 0,65; arrozal 0,3);
		-- casa e sebe de bambu param; riacho de 0,6 m: o M48 vadeia (1,2 m), o Ontos não (0,6 m)
		tracked = {
			forest = 2.0,
			grove = 2.4,
			clear = 1.54,
			farm = 1.54,
			paddy = 3.4,
			hedge = math.huge,
			house = math.huge,
			stream = 3,
			sea = math.huge,
			trench = 3, -- trincheira de 1 m: passa devagar
			road = 1.0, -- estrada de terra batida (2026-11-12)
			maxGrade = 0.5,
			upCost = 2,
			downCost = 1,
		},
		-- LVTP-5: como a lagarta, mas boia (11 km/h na água: ~4,4x o tempo em terra)
		amphibious = {
			forest = 2.0,
			grove = 2.4,
			clear = 1.54,
			farm = 1.54,
			paddy = 3.4,
			hedge = math.huge,
			house = math.huge,
			stream = 2.2,
			sea = 4.4,
			trench = 3, -- trincheira de 1 m: passa devagar
			road = 1.0,
			maxGrade = 0.5,
			upCost = 2,
			downCost = 1,
		},
	} :: { [string]: any },
	-- vau de cada lagarta (m): acima disto o riacho de 0,6 m (TerrainBuilder) vira barreira
	fordM = { m48a3 = 1.2, ontos = 0.6, lvtp5 = 99 } :: { [string]: number },
	streamDepthM = 0.6,
}

-- Túneis: só o VC entra (regra do dono, 2026-11-11); os EUA desconfiam das bocas e jogam granada
BotBrain.TUNNEL = {
	useWithinM = 60, -- a entrada fica a até 60 m do bot
	gainM = 80, -- e a saída fica 80 m (ou mais) mais perto do destino que a entrada
	ambushTriggerM = 45, -- emboscada: sai quando o inimigo chega a até 45 m da saída
	ambushMaxS = 150, -- espera no máximo isto lá embaixo
	vanishWithinM = 40, -- ferido ou cercado: some no túnel se a entrada está a até 40 m
	climbS = 1.6, -- s pela escada do poço de 3 m
	exitOffsetM = 2.5, -- sai ao lado do poço (não em cima do buraco)
	spotM = 25, -- os EUA acham a boca camuflada a até 25 m, com visada
	stumbleM = 8, -- ...ou tropeçando nela
	alertM = 120, -- EUA a até 120 m quando um VC entra ou sai: a boca fica conhecida
	grenadeCooldownS = 90, -- por boca, para o time todo
	scareM = 15, -- granada estoura a até 15 m de quem está lá embaixo: ele foge pelo túnel
}

-- Blindados com tripulação de bots (só dos EUA; o carro do VC entra depois e usa a mesma lógica)
BotBrain.VEHICLE = {
	minTeamBots = 8, -- bots do lado para tripular o 1º blindado (o HEAVY_UNLOCK de 16 é dos squads de jogadores)
	perCrewBots = 5, -- mais um blindado a cada 5 bots além disso
	order = { "m48a3", "lvtp5", "ontos" },
	crewSeats = { "driver", "gunner" },
	standoffM = { m48a3 = 220, ontos = 180, lvtp5 = 250 } :: { [string]: number },
	dropM = 180, -- o LVTP-5 desembarca a tropa a esta distância do objetivo
	coverSearchM = 45, -- procura sebe, casa, dique ou crista para parar atrás
	behindM = 9, -- e para a esta distância atrás dela
	arriveM = 7,
	lookM = { 9, 24 }, -- perseguição pura (m), pela velocidade
	pivotDeg = 50, -- erro de rumo maior que isto e devagar: gira no lugar (lagarta)
	steerGain = 2.2, -- volante por radiano de erro
	speedGain = 0.45, -- acelerador por m/s de erro
	cruiseFrac = 0.8, -- fração do teto do chão
	cornerFrac = 0.45, -- teto na curva fechada
	stuckS = 5,
	reverseS = 2.5,
	boardM = 6, -- embarca a esta distância do veículo
	loadWaitS = 60, -- LVTP-5 espera a tropa no depósito
	minLoad = 3,
	gunReaction = { 0.8, 1.6 },
	coaxVolley = { 6, 12 },
	mainMinM = 60, -- canhão (HE) só a partir de 60 m
	mainEveryS = 9,
	aimToleranceDeg = 2.5,
	turretDegS = 24, -- se a ficha não tiver (Vehicles.turretDegS)
}

-- Diferença leve de lado: o VC prefere sebe e emboscada (espera escondido mais tempo); os EUA
-- preferem abrigo sólido e avançam mais. PLACEHOLDER de design.
export type Style = {
	solidBonus: number, -- nota de abrigo que para bala (dique, parede, tronco, sacos)
	concealBonus: number, -- nota de abrigo que só esconde (sebe, moita, capim)
	advanceBias: number, -- quanto vale chegar mais perto do objetivo ao trocar de abrigo
	hideMult: number, -- tempo escondido entre rajadas
	burstsMult: number, -- rajadas por abrigo
	forgetS: number, -- s sem ver nem levar tiro até sair do combate
	resumeS: { number }, -- s parado no abrigo depois do combate antes de voltar a andar
	holdFireM: number?, -- emboscada: só abre fogo com o inimigo mais perto que isto
	holdFireMaxS: number, -- e no máximo por este tempo de contato
}

-- 2026-11-12 ("faça eles avançarem mais em vez de ficarem parados"): menos tempo parado depois do
-- combate e esquecendo o inimigo (valores da v36 no comentário).
BotBrain.STYLE = {
	US = {
		solidBonus = 10,
		concealBonus = 0,
		advanceBias = 0.8, -- era 0,6
		hideMult = 0.8,
		burstsMult = 1,
		forgetS = 6, -- era 8
		resumeS = { 1, 3 }, -- era 2–5 s
		holdFireM = nil,
		holdFireMaxS = 0,
	} :: Style,
	VC = {
		solidBonus = 3,
		concealBonus = 10,
		advanceBias = 0.4, -- era 0,1
		hideMult = 1.2, -- era 1,4
		burstsMult = 1.5,
		forgetS = 10, -- era 20
		resumeS = { 4, 8 }, -- era 20–40 s: o VC ficava quase um minuto parado depois de cada contato
		holdFireM = 80,
		holdFireMaxS = 10, -- era 25 s
	} :: Style,
}

-- Avançar em vez de ficar parado (2026-11-12). PLACEHOLDER de design.
BotBrain.PRESS = {
	afterS = 4, -- quem ataca, sem alvo à vista e sem fogo em cima há 4 s, volta a avançar com o squad
	idleMaxS = 20, -- parado sem contato e fora do ponto mais que isto: sai do lugar
}

-- Volta a avançar? attacking: o squad dele ataca o objetivo; sinceS: desde a última vez que viu o
-- inimigo ou levou tiro. Quem defende o ponto fica (mas reage: só o atacante segue).
function BotBrain.shouldPress(
	attacking: boolean,
	hasTarget: boolean,
	underFire: boolean,
	retreating: boolean,
	sinceS: number
): boolean
	return attacking and not hasTarget and not underFire and not retreating and sinceS >= BotBrain.PRESS.afterS
end

-- Ficou parado demais sem contato? holdingPoint: no lugar dele no objetivo (tomando ou guardando).
function BotBrain.idleExpired(stillS: number, inCombat: boolean, holdingPoint: boolean): boolean
	return not inCombat and not holdingPoint and stillS >= BotBrain.PRESS.idleMaxS
end

---------------------------------------------------------------------------------------------
-- Bots no squad do jogador (decisão do dono, 2026-11-12): squad de humano com menos de 4 membros
-- recebe bots até 4 (nunca passa do tamanho do squad); os bots saem um a um quando entram humanos.
-- Seguem o líder humano a 10–30 m e obedecem à marca do líder na carta. PLACEHOLDER de design.
---------------------------------------------------------------------------------------------
BotBrain.FILL = {
	target = 4, -- membros (humanos + bots) que o squad de jogador deve ter
	everyS = 2, -- de quanto em quanto tempo o servidor confere (entra/sai um bot por squad por vez)
	minM = 10, -- distância do líder: no mínimo 10 m
	maxM = 30, -- e no máximo 30 m
	slotSlackM = 12, -- longe do lugar mais que isto (mesmo dentro de 10–30 m): vai para o lugar
	markReachM = 15, -- chegou na marca do líder
	markTtlS = 180, -- a marca vale no máximo 3 min
	markReleaseM = 60, -- chegou e o líder já está a mais que isto da marca: volta a segui-lo
}

export type FillSquad = { id: string, humans: number, size: number, bots: { number } }

-- Plano de uma conferida: quais bots entram em qual squad e quais saem. Um por squad por vez (entra
-- ou sai), na ordem da lista `free` (o primeiro sai antes). squads: só os que podem ter bot.
function BotBrain.fillPlan(squads: { FillSquad }, free: { number }): ({ { bot: number, squad: string } }, { number })
	local F = BotBrain.FILL
	local add: { { bot: number, squad: string } } = {}
	local remove: { number } = {}
	local pool = table.clone(free)
	for _, s in squads do
		local want = 0
		if s.humans > 0 and s.humans < F.target then
			want = math.max(math.min(F.target, s.size) - s.humans, 0)
		end
		local have = #s.bots
		if have > want then
			table.insert(remove, s.bots[have])
		elseif have < want and #pool > 0 then
			table.insert(add, { bot = table.remove(pool, 1) :: number, squad = s.id })
		end
	end
	return add, remove
end

-- Lugar do bot i (1, 2, ...) atrás do líder, em metros no plano: (dx, dz) a partir dele. lookX/lookZ:
-- para onde o líder olha. Leque atrás dele (0°, ±40°, ±80°), a 14–24 m.
local ESCORT = { { 0, 14 }, { -40, 18 }, { 40, 18 }, { -80, 24 }, { 80, 24 } }
function BotBrain.escortSlot(i: number, lookX: number, lookZ: number): (number, number)
	local len = math.sqrt(lookX * lookX + lookZ * lookZ)
	local bx, bz = 0, 1
	if len > 1e-6 then
		bx, bz = -lookX / len, -lookZ / len
	end
	local e = ESCORT[((i - 1) % #ESCORT) + 1]
	local a = math.rad(e[1])
	local rx, rz = bx * math.cos(a) - bz * math.sin(a), bx * math.sin(a) + bz * math.cos(a)
	return rx * e[2], rz * e[2]
end

-- Fica onde está? A 10–30 m do líder e perto do seu lugar.
function BotBrain.escortHold(toLeaderM: number, toSlotM: number): boolean
	local F = BotBrain.FILL
	return toLeaderM >= F.minM and toLeaderM <= F.maxM and toSlotM <= F.slotSlackM
end

-- A marca do líder ainda manda? Vale até markTtlS; depois de chegar, até o líder se afastar dela.
function BotBrain.markActive(ageS: number, reached: boolean, leaderToMarkM: number): boolean
	local F = BotBrain.FILL
	if ageS > F.markTtlS then
		return false
	end
	return not (reached and leaderToMarkM > F.markReleaseM)
end

-- Lance do squad perto do objetivo atacado, com contato recente.
function BotBrain.squadBounds(attack: boolean, toObjectiveM: number, contactAgeS: number): boolean
	local S = BotBrain.SQUAD
	return attack and toObjectiveM <= S.boundZoneM and contactAgeS <= S.boundContactS
end

local function lerp(r: { number }, t: number): number
	return r[1] + (r[2] - r[1]) * math.clamp(t, 0, 1)
end

-- Setor-alvo: o setor atacável pelo time (vizinho a um setor próprio). Se nenhum, defende a
-- linha de frente (setor próprio vizinho de um não-próprio). owner/active vêm do Capture.
function BotBrain.objective(owner: { string }, active: { boolean }, faction: string): number?
	local n = #owner
	local function own(i: number): boolean
		return owner[i] == faction
	end
	local candidates = {}
	for i = 1, n do
		if active[i] and not own(i) and ((i > 1 and own(i - 1)) or (i < n and own(i + 1))) then
			table.insert(candidates, i)
		end
	end
	-- Skirmish (um setor ativo): ataca o único ativo
	if #candidates == 0 then
		local onlyActive: number? = nil
		local count = 0
		for i = 1, n do
			if active[i] then
				count += 1
				onlyActive = i
			end
		end
		if count == 1 and onlyActive and not own(onlyActive) then
			return onlyActive
		end
	end
	if #candidates > 0 then
		-- EUA avançam para oeste (índice menor); VC para leste (índice maior)
		table.sort(candidates, function(a, b)
			return if faction == "US" then a > b else a < b
		end)
		return candidates[1]
	end
	for i = 1, n do
		if active[i] and own(i) and ((i > 1 and not own(i - 1)) or (i < n and not own(i + 1))) then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Reação e mira
---------------------------------------------------------------------------------------------

-- Tempo do avistar ao primeiro tiro (s). roll em [0, 1). alerted: já está em combate.
function BotBrain.reactionTime(d: Difficulty, roll: number, suppression: number, alerted: boolean): number
	local t = lerp(d.reaction, roll)
	if alerted then
		t *= d.alertedReaction
	end
	return t + d.suppReactionS * math.clamp(suppression, 0, 1)
end

-- Alcance de detecção relativo pela postura do alvo e pela camuflagem de mato (camo: atributo
-- "Camo" do alvo; veg: vegetação onde ele está, BotBrain.vegetation). Alvo que já está sendo
-- seguido não some.
function BotBrain.spotFactor(d: Difficulty, stance: string, tracking: boolean, camo: string?, veg: string?): number
	if tracking then
		return 1
	end
	return (d.spotStance[stance] or 1) * BotBrain.camoFactor(camo, veg, stance)
end

---------------------------------------------------------------------------------------------
-- Camuflagem de mato (Shared/Skins; "vantagem comprada" autorizada pelo dono em 2026-11-11)
---------------------------------------------------------------------------------------------
-- Quem veste a camuflagem do tipo da vegetação em que está é visto a uma fração da distância
-- (match) e, deitado, a uma fração menor ainda (prone, além do spotStance que vale para todos).
-- fit: quanto da vantagem vale em cada vegetação (1 = toda; o bambu parece um pouco com a mata e
-- o capim alto com o arrozal). Fora disso, nenhuma vantagem (nem desvantagem). PLACEHOLDER.
BotBrain.CAMO = {
	match = 0.6, -- PLACEHOLDER: ~60% da distância na vegetação certa
	prone = 0.75, -- PLACEHOLDER: deitado, mais 25% de corte
	fit = {
		rice = { rice = 1, grass = 0.7 },
		jungle = { jungle = 1, bamboo = 0.5 },
		bamboo = { bamboo = 1, jungle = 0.5 },
	} :: { [string]: { [string]: number } },
}

function BotBrain.camoFactor(camo: string?, veg: string?, stance: string): number
	if not camo or not veg then
		return 1
	end
	local f = BotBrain.CAMO.fit[camo]
	local w = if f then f[veg] or 0 else 0
	if w <= 0 then
		return 1
	end
	local k = 1 - (1 - BotBrain.CAMO.match) * w
	if stance == "prone" then
		k *= 1 - (1 - BotBrain.CAMO.prone) * w
	end
	return k
end

-- Alcance de notar (m) pela vegetação onde o alvo está (2026-11-12, "os bots enxergam de muito
-- longe"; o raio de visada passa pelas folhas, que não têm colisão). PLACEHOLDER de design.
BotBrain.SIGHT = {
	open = 120,
	rice = 120,
	jungle = 40,
	bamboo = 40,
	grass = 15, -- capim-elefante
} :: { [string]: number }
BotBrain.SIGHT_FIRING = 1.5 -- quem atirou há pouco (clarão, estampido) é notado até 1,5x mais longe
BotBrain.SIGHT_TRACKING = 1.5 -- o alvo que já está sendo seguido some só a 1,5x (até o teto do aberto)
-- tempo para notar (multiplica) pela vegetação do alvo
BotBrain.NOTICE_VEG = { open = 1, rice = 1, jungle = 1.5, bamboo = 1.5, grass = 1.8 } :: { [string]: number }

-- Até onde o bot nota este alvo (m): vegetação, postura, camuflagem, se está atirando e se já é o
-- alvo seguido. veg nil = aberto.
function BotBrain.sightRange(
	d: Difficulty,
	veg: string?,
	stance: string,
	tracking: boolean,
	camo: string?,
	firing: boolean
): number
	local open = BotBrain.SIGHT.open
	local base = BotBrain.SIGHT[veg or "open"] or open
	if tracking then
		return math.min(base * BotBrain.SIGHT_TRACKING, open)
	end
	local r = base * BotBrain.spotFactor(d, stance, false, camo, veg)
	if firing then
		r = math.max(r, base) * BotBrain.SIGHT_FIRING
	end
	return r
end

-- Onde o bot mira: sempre o meio do tronco, de qualquer postura (antes mirava na cabeça de quem
-- estava abaixado e acertava cabeça em série).
function BotBrain.aimPartName(_stance: string): string
	return "UpperTorso"
end

-- Planta posta pelo AssetLoader (nome do modelo = chave da arte) -> tipo de vegetação.
BotBrain.PLANT = {
	bamboo_clump = "bamboo",
	melaleuca_grove = "bamboo", -- tràm: touceira fina de baixada, junto do bambu
	elephant_grass = "grass",
	rice_patch = "rice",
	shrub = "jungle",
	banana = "jungle",
	taro_fern = "jungle",
	coconut_palm = "jungle",
	hill_tree = "jungle",
	canopy_tree = "jungle",
	vine_tree = "jungle",
} :: { [string]: string }

function BotBrain.plantKind(key: string): string?
	if string.sub(key, 1, 3) == "ph_" then
		return "jungle" -- árvores prontas do Poly Haven (D-67)
	end
	return BotBrain.PLANT[key]
end

-- Contagem de plantas em volta do alvo (raio radiusM) e quantas fazem cada tipo. PLACEHOLDER: a
-- conferir no Studio com o alvo parado em cada paisagem.
BotBrain.VEG = { radiusM = 8, bambooMin = 2, jungleMin = 2, grassMin = 2 }
export type VegCount = { jungle: number, bamboo: number, grass: number, rice: number }

-- surface: chão sob o alvo (BotService: "paddy" = lâmina d'água do arrozal).
-- Devolve "rice" | "bamboo" | "jungle" | "grass" | "open".
function BotBrain.vegetation(surface: string, n: VegCount): string
	local V = BotBrain.VEG
	if surface == "paddy" or n.rice > 0 then
		return "rice"
	elseif n.bamboo >= V.bambooMin and n.bamboo * 2 >= n.jungle then
		return "bamboo"
	elseif n.jungle >= V.jungleMin then
		return "jungle"
	elseif n.grass >= V.grassMin then
		return "grass"
	end
	return "open"
end

export type AimOpts = {
	moving: boolean?,
	suppression: number?,
	stance: string?, -- postura de quem atira
	armHurt: boolean?,
	shot: number?, -- 1 = primeiro tiro da rajada
	kind: string?, -- tipo da arma (recuo)
}

-- Erro de mira (1σ, radianos): cresce com a distância e a supressão, cai deitado, abre com o
-- recuo a cada tiro seguido.
function BotBrain.aimError(d: Difficulty, distM: number, o: AimOpts?): number
	local s = d.aimBaseRad * (1 + math.max(distM, 0) / d.aimRangeM)
	if not o then
		return s
	end
	if o.moving then
		s *= d.aimMoving
	end
	s *= 1 + d.aimSuppression * math.clamp(o.suppression or 0, 0, 1)
	s *= d.aimStance[o.stance or "stand"] or 1
	if o.armHurt then
		s *= d.aimArmHurt
	end
	local k = math.max((o.shot or 1) - 1, 0)
	if k > 0 then
		local r = math.min((d.recoilRad[o.kind or "rifle"] or 0) * k, d.recoilMaxRad)
		s = math.sqrt(s * s + r * r)
	end
	return s
end

-- função erro (Abramowitz e Stegun 7.1.26, erro < 1,5e-7)
local function erf(x: number): number
	local sign = if x < 0 then -1 else 1
	x = math.abs(x)
	local t = 1 / (1 + 0.3275911 * x)
	local poly = ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
	return sign * (1 - poly * math.exp(-x * x))
end

-- Chance de um tiro cair num quadrado de meio lado halfM a distM metros, com erro sigma (rad).
-- Só para calibrar e testar a tabela ("acerta bem a 100 m, mal a 300 m").
function BotBrain.hitChance(sigmaRad: number, distM: number, halfM: number): number
	local lin = math.max(sigmaRad * distM, 1e-9)
	local p = erf(halfM / (lin * math.sqrt(2)))
	return p * p
end

-- Calibração (2026-11-12, "bots estão muito fortes"): chance de o bot acertar pelo menos uma vez um
-- jogador PARADO e em pé, de frente, no aberto, a distM, nos windowS segundos depois que ele aparece.
-- Conta o tempo de notar (noticeTime), a reação, a mira que firma (settleFactor), as rajadas
-- (volleySize, volleyGap, pause) e o recuo; o bot parado e em pé, sem supressão. sightM: além disto
-- não nota (0 de chance). Alvo: o quadrado do tronco (C.torsoHalfM). Média de `trials` sorteios.
function BotBrain.duelHitChance(
	d: Difficulty,
	distM: number,
	windowS: number,
	kind: string,
	rpm: number,
	sightM: number,
	trials: number,
	roll: () -> number
): number
	if distM > sightM then
		return 0
	end
	local sum = 0
	for _ = 1, trials do
		local tNotice = BotBrain.noticeTime(d, distM, "stand", true, false, 0)
		local t = tNotice + BotBrain.reactionTime(d, roll(), 0, false)
		local miss = 1
		while t <= windowS do
			local n = BotBrain.volleySize(d, kind, roll())
			for i = 1, n do
				if t > windowS then
					break
				end
				local s = BotBrain.aimError(d, distM, { shot = i, kind = kind }) * BotBrain.settleFactor(d, t - tNotice)
				miss *= 1 - BotBrain.hitChance(s, distM, BotBrain.C.torsoHalfM)
				if i < n then
					t += BotBrain.volleyGap(d, kind, rpm, roll())
				end
			end
			t += BotBrain.pause(d, kind, roll())
		end
		sum += 1 - miss
	end
	return sum / math.max(trials, 1)
end

-- Compatibilidade (teste da F3): erro de um bot médio em pé, parado ou andando. skill 0,5 = médio.
function BotBrain.aimSigma(distM: number, moving: boolean, skill: number): number
	local s = BotBrain.aimError(BotBrain.DIFFICULTY.medium, distM, { moving = moving })
	return s * (1.6 - math.clamp(skill, 0, 1)) / 1.1
end

---------------------------------------------------------------------------------------------
-- Rajadas
---------------------------------------------------------------------------------------------

-- Tiros numa exposição: fuzil 2-3 tiros pensados, metralhadora 4-8 de uma vez
function BotBrain.volleySize(d: Difficulty, kind: string, roll: number): number
	local r = d.volley[kind] or d.volley.rifle
	local n = r[1] + math.floor(math.clamp(roll, 0, 0.999999) * (r[2] - r[1] + 1))
	return math.min(n, r[2])
end

-- s entre os tiros da mesma rajada: metralhadora na cadência; fuzil e pistola, tiro pensado,
-- nunca mais rápido que a arma (SKS: 1,5 s)
function BotBrain.volleyGap(d: Difficulty, kind: string, rpm: number, roll: number): number
	local mech = 60 / rpm
	if kind == "mg" then
		return mech
	end
	return math.max(mech, lerp(d.aimedGap, roll))
end

-- s de pausa entre rajadas quando não há abrigo
function BotBrain.pause(d: Difficulty, kind: string, roll: number): number
	return lerp(d.openPause[kind] or d.openPause.rifle, roll)
end

-- Compatibilidade (teste da F3): tiros por puxada de gatilho (só a metralhadora dispara rajada)
function BotBrain.burst(kind: string, roll: number): number
	if kind == "mg" then
		return BotBrain.volleySize(BotBrain.DIFFICULTY.medium, "mg", roll)
	end
	return 1
end

-- Compatibilidade (teste da F3): intervalo até o próximo tiro
function BotBrain.shotDelay(kind: string, rpm: number, inBurst: boolean, roll: number): number
	if inBurst then
		return 60 / rpm
	end
	return BotBrain.pause(BotBrain.DIFFICULTY.medium, kind, roll)
end

-- s escondido entre rajadas: o VC espera mais; ferido, o dobro
function BotBrain.hideTime(d: Difficulty, style: Style, roll: number, wounded: boolean): number
	local t = lerp(d.hideTime, roll) * style.hideMult
	return if wounded then t * d.woundedHideMult else t
end

-- rajadas antes de trocar de abrigo; ferido não troca (fica onde está protegido)
function BotBrain.burstsPerCover(d: Difficulty, style: Style, roll: number, wounded: boolean): number
	if wounded then
		return math.huge
	end
	return math.max(1, math.floor(lerp(d.burstsPerCover, roll) * style.burstsMult + 0.5))
end

---------------------------------------------------------------------------------------------
-- Supressão (0..1)
---------------------------------------------------------------------------------------------

-- Bala que passou a missM metros (ou acertou): soma supressão. Mais perto, mais susto.
function BotBrain.suppressionAdd(d: Difficulty, s: number, missM: number, hit: boolean): number
	local add: number
	if hit then
		add = d.suppHit
	else
		local close = 1 - math.clamp(missM / d.nearMissM, 0, 1)
		if close <= 0 then
			return s
		end
		add = d.suppPerRound * (0.25 + 0.75 * close)
	end
	return math.min(1, s + add)
end

-- cai com o tempo (exponencial: alguns segundos depois do último tiro)
function BotBrain.suppressionDecay(d: Difficulty, s: number, dt: number): number
	return s * math.exp(-math.max(dt, 0) / d.suppTauS)
end

function BotBrain.pinned(d: Difficulty, s: number): boolean
	return s >= d.pinnedAt
end

function BotBrain.underFire(d: Difficulty, s: number): boolean
	return s >= d.underFireAt
end

-- Bala reta de o com direção unitária u: a que distância passa do ponto p e quanto à frente
-- (negativo = atrás de quem atirou). Em qualquer unidade.
function BotBrain.passBy(
	ox: number,
	oy: number,
	oz: number,
	ux: number,
	uy: number,
	uz: number,
	px: number,
	py: number,
	pz: number
): (number, number)
	local vx, vy, vz = px - ox, py - oy, pz - oz
	local t = vx * ux + vy * uy + vz * uz
	local cx, cy, cz = vx - ux * t, vy - uy * t, vz - uz * t
	return math.sqrt(cx * cx + cy * cy + cz * cz), t
end

---------------------------------------------------------------------------------------------
-- Abrigo
---------------------------------------------------------------------------------------------

-- solid: para bala. Sebe, moita, capim e palha só escondem (CombatService deixa a bala passar
-- por Bamboo e Thatch). level: altura típica (1 baixo, 2 médio, 3 alto), antes de medir.
BotBrain.COVER = {
	dike = { solid = true, level = 1 }, -- dique de arrozal (~35 cm acima do chão)
	hedge = { solid = false, level = 2 }, -- sebe de arrozal ou de bambu
	brush = { solid = false, level = 2 }, -- moita, touceira, folhagem
	grass = { solid = false, level = 1 }, -- capim alto
	trunk = { solid = true, level = 3 }, -- tronco de árvore
	wall = { solid = true, level = 3 }, -- parede de casa, celeiro, altar
	sandbags = { solid = true, level = 2 },
	trench = { solid = true, level = 2 },
	earth = { solid = true, level = 2 }, -- bunker de toras, toca, túmulo
	terrain = { solid = true, level = 1 }, -- barranco, crista
	thatch = { solid = false, level = 3 }, -- palha (telhado, meda)
	solid = { solid = true, level = 2 }, -- qualquer outra peça sólida
	none = { solid = false, level = 0 },
} :: { [string]: { solid: boolean, level: number } }

local EARTH_MODELS = { vc_bunker = true, spider_hole = true, grave_mound = true } :: { [string]: boolean }
local WALL_MODELS = {
	granary = true,
	shrine = true,
	well = true,
	HutPlaceholder = true,
} :: { [string]: boolean }

-- Tipo do que o raio acertou: nome da peça, nome do modelo de arte (chave do asset: AssetLoader
-- põe m.Name = key) e o atributo Material (FeatureBuilder e AssetLoader).
function BotBrain.coverKind(partName: string, modelName: string?, material: string?, isTerrain: boolean): string
	if isTerrain then
		return "terrain"
	end
	if partName == "Dike" then
		return "dike"
	elseif partName == "PaddyHedge" or partName == "BambooHedge" then
		return "hedge"
	end
	local m = modelName or ""
	if m == "sandbags" then
		return "sandbags"
	elseif m == "trench_section" then
		return "trench"
	elseif EARTH_MODELS[m] then
		return "earth"
	elseif m == "bamboo_fence" then
		return "hedge"
	elseif m == "elephant_grass" then
		return "grass"
	end
	if material == "Wood" or string.sub(partName, 1, 8) == "Madeira0" then
		return "trunk"
	elseif material == "Thatch" then
		return "thatch"
	elseif material == "Bamboo" then
		return "brush"
	elseif material == "MudWall" or partName == "Walls" or WALL_MODELS[m] then
		return "wall"
	elseif string.sub(m, 1, 4) == "hut_" or string.sub(m, 1, 6) == "house_" then
		return "wall"
	elseif string.sub(m, 1, 10) == "vila_casa_" or m == "Vila_chua" or m == "Vila_dinh" then
		return "wall" -- vila grande do centro (2026-11-12): casas únicas, pagode e casa comunal
	elseif m == "us_bunker" or m == "us_armor_revetment" or m == "us_range_berm" then
		return "earth" -- bases (2026-11-13): sacos de areia e barranco de terra
	elseif m == "us_conex" or m == "us_motor_pool" or m == "us_watchtower" then
		return "wall"
	end
	return "solid"
end

-- Nível medido: raios do lugar até o inimigo na altura do deitado, do agachado e do em pé.
-- 0 = não tapa; 1 = só o deitado some; 2 = o agachado some; 3 = em pé some.
function BotBrain.coverLevel(low: boolean, mid: boolean, high: boolean): number
	if low and mid and high then
		return 3
	elseif low and mid then
		return 2
	elseif low then
		return 1
	elseif mid and high then
		return 3 -- parede com vão embaixo, tronco inclinado
	end
	return 0
end

-- Postura escondido. level nil = típico do tipo. Pedido do dono: deitar em arrozal aberto e no
-- capim quando sob fogo; agachar atrás de dique e sebe; em pé atrás de parede e tronco.
function BotBrain.coverStance(kind: string, level: number?, pinned: boolean, underFire: boolean, open: boolean): string
	local lv = level or (BotBrain.COVER[kind] or BotBrain.COVER.solid).level
	if lv >= 3 then
		return "stand"
	elseif lv == 2 then
		return "crouch"
	elseif lv == 1 then
		return if pinned then "prone" else "crouch" -- dique baixo: sob supressão, deita
	end
	-- sem abrigo
	if underFire and open then
		return "prone" -- arrozal aberto, capim
	end
	return "crouch" -- mata, ou sem fogo em cima: ajoelha para atirar melhor
end

-- Postura para atirar do abrigo e se precisa sair de lado (tronco, parede).
function BotBrain.peekStance(level: number, hide: string): (string, boolean)
	if level >= 3 then
		return "stand", true
	elseif level == 2 then
		return "stand", false -- levanta por cima dos sacos ou da sebe
	elseif level == 1 then
		return "crouch", false -- por cima do dique
	end
	return hide, false
end

-- Lugar atrás do obstáculo. O raio do bot acertou a face em (hx, hz) com normal horizontal
-- (nx, nz), que aponta para o bot. Se o inimigo (ex, ez) está do outro lado da face, o lugar fica
-- do lado do bot, a `standoff` da face. Se está do mesmo lado e a espessura é conhecida (dique,
-- sebe: quem chama só passa obstáculo fino), o lugar fica atrás do obstáculo. Face quase deitada
-- (chão subindo) não é abrigo. Qualquer unidade, desde que a mesma em tudo.
function BotBrain.coverSpot(
	hx: number,
	hz: number,
	nx: number,
	nz: number,
	ex: number,
	ez: number,
	standoff: number,
	thickness: number?
): (number?, number?)
	local l = math.sqrt(nx * nx + nz * nz)
	if l < 0.3 then
		return nil, nil
	end
	nx, nz = nx / l, nz / l
	local side = (ex - hx) * nx + (ez - hz) * nz
	if side < 0 then
		return hx + nx * standoff, hz + nz * standoff
	end
	if thickness then
		local back = thickness + standoff
		return hx - nx * back, hz - nz * back
	end
	return nil, nil
end

export type Candidate = {
	kind: string,
	level: number,
	distM: number, -- do bot até o lugar
	enemyM: number, -- do lugar até o inimigo
	progressM: number, -- quanto o lugar aproxima do objetivo (+ avança)
	awayM: number, -- quanto o lugar afasta do inimigo (+ recua)
	blind: boolean, -- abrigo alto sem lado livre para atirar
}

-- Nota de um abrigo (maior = melhor).
function BotBrain.coverScore(style: Style, c: Candidate, retreating: boolean): number
	if c.level <= 0 then
		return -math.huge
	end
	local info = BotBrain.COVER[c.kind] or BotBrain.COVER.solid
	local s = c.level * 6 + (if info.solid then style.solidBonus else style.concealBonus)
	s -= c.distM * 0.5 -- caminho curto: menos tempo exposto
	if c.enemyM < 10 then
		s -= 25 -- colado no inimigo não é abrigo
	end
	if retreating then
		s += math.clamp(c.awayM, -15, 15) + (if info.solid then 4 else 0)
	else
		s += math.clamp(c.progressM, -15, 15) * style.advanceBias
		if c.blind then
			s -= 10
		end
	end
	return s
end

-- Campo aberto (deita sob fogo): arrozal sempre; capim e areia com pouca coisa sólida em volta;
-- mata só se quase nada sólido em volta. solidHits: raios em volta que acharam abrigo de pé.
function BotBrain.openGround(surface: string, solidHits: number, rays: number): boolean
	if surface == "paddy" then
		return true
	end
	local frac = if rays > 0 then solidHits / rays else 0
	if surface == "grass" or surface == "sand" or surface == "mud" then
		return frac < 0.5
	end
	return frac < 0.25
end

---------------------------------------------------------------------------------------------
-- Ferido, granada, emboscada, orçamento
---------------------------------------------------------------------------------------------

function BotBrain.shouldRetreat(d: Difficulty, health: number): boolean
	return health < d.retreatHealth
end

export type ThrowCheck = {
	distM: number, -- até a última posição vista do inimigo
	los: boolean, -- enxerga o inimigo agora
	thrown: number, -- granadas nesta vida
	now: number,
	nextAt: number, -- recarga
	knownAgeS: number, -- há quanto tempo viu
	friendlyNear: boolean, -- companheiro perto do ponto
	pinned: boolean,
	roll: number,
	covered: boolean?, -- D-90: enxerga, mas ele está atrás de dique ou parede (o tiro para no abrigo)
}

-- Granada: inimigo conhecido a 15-35 m, escondido (sem linha de visada) ou atrás de abrigo sólido
-- (D-90: dique, parede), com recarga e no máximo 2 por vida. Não joga perto de companheiro nem
-- preso pelo fogo.
function BotBrain.shouldThrow(d: Difficulty, g: ThrowCheck): boolean
	local G = d.grenade
	return (not g.los or g.covered == true)
		and g.distM >= G.minM
		and g.distM <= G.maxM
		and g.thrown < G.perLife
		and g.now >= g.nextAt
		and g.knownAgeS <= G.memoryS
		and not g.friendlyNear
		and not g.pinned
		and g.roll < G.chance
end

-- Emboscada (VC): no abrigo e sem fogo em cima, segura o tiro até o inimigo chegar perto
-- (ou o contato durar demais).
function BotBrain.holdFire(style: Style, distM: number, underFire: boolean, heldS: number): boolean
	local h = style.holdFireM
	if not h or underFire then
		return false
	end
	return distM > h and heldS < style.holdFireMaxS
end

-- Orçamento de raycasts de abrigo (fichas): enche a `rate` por segundo até `cap`.
function BotBrain.budgetStep(tokens: number, dt: number, rate: number, cap: number): number
	return math.min(cap, tokens + math.max(dt, 0) * rate)
end

---------------------------------------------------------------------------------------------
-- D-90: percepção e mira que firma
---------------------------------------------------------------------------------------------

-- Tempo (s) com o alvo à vista até notar. offDeg: ângulo entre a frente do corpo e o alvo. Atrás
-- (além de rearDeg) não vê, a não ser que ele esteja atirando (ouve e vira).
function BotBrain.noticeTime(
	d: Difficulty,
	distM: number,
	stance: string,
	still: boolean,
	firing: boolean,
	offDeg: number,
	veg: string?
): number
	if offDeg > d.rearDeg and not firing then
		return math.huge
	end
	local t = d.noticeS + d.noticePer100M * math.max(distM, 0) / 100
	t *= BotBrain.NOTICE_VEG[veg or "open"] or 1
	if still and stance ~= "stand" then
		t *= d.noticeStill
	end
	if offDeg > d.fovDeg then
		t *= d.noticeSide
	end
	if firing then
		t *= d.noticeFiring
	end
	return t
end

-- Erro extra (multiplica) de quem pegou o alvo há trackS segundos: settleMult no instante em que
-- notou, caindo em linha até 1 em settleS.
function BotBrain.settleFactor(d: Difficulty, trackS: number): number
	local k = math.clamp(trackS / d.settleS, 0, 1)
	return d.settleMult + (1 - d.settleMult) * k
end

-- Disciplina de fogo: atira nesta distância com este tipo de arma?
function BotBrain.inRange(d: Difficulty, kind: string, distM: number): boolean
	return distM <= (d.fireMaxM[kind] or d.fireMaxM.rifle)
end

---------------------------------------------------------------------------------------------
-- D-90: passo pela situação (velocidades das âncoras do Movement, as mesmas da animação)
---------------------------------------------------------------------------------------------

export type GaitCtx = {
	stance: string, -- postura em que vai andar
	distM: number, -- até o destino
	urgent: boolean, -- sob fogo ou cruzando aberto com inimigo perto: corre
	cautious: boolean, -- perto do objetivo ou de inimigo, sem contato: anda
	aiming: boolean, -- andando de lado, mirando (atira andando)
	behindM: number, -- quanto está atrás do seu lugar no squad
	legImpaired: boolean,
	waterM: number?, -- fundura da água (riacho): acima do joelho não corre
}

-- Nome do passo e velocidade-alvo (m/s) em chão firme e plano.
function BotBrain.gait(c: GaitCtx): (string, number)
	if c.stance == "prone" then
		return "prone", Movement.PRONE
	elseif c.stance == "crouch" then
		return "crouch", Movement.CROUCH
	end
	local S = BotBrain.SQUAD
	local name: string
	if c.aiming then
		name = "ads"
	elseif (c.urgent and c.distM > 3) or c.behindM > S.sprintBehindM then
		name = "sprint"
	elseif c.behindM > S.catchUpM then
		name = "jog"
	elseif c.cautious then
		name = "walk"
	else
		name = "jog"
	end
	if name == "sprint" and (c.waterM or 0) >= Movement.SPRINT_MAX_WATER_M then
		name = "jog"
	end
	local v = if name == "ads"
		then Movement.ADS
		elseif name == "sprint" then Movement.SPRINT
		elseif name == "walk" then Movement.WALK
		else Movement.JOG
	if c.legImpaired and v > Movement.WALK then
		return "walk", Movement.WALK
	end
	return name, v
end

-- Fator do chão como o do jogador (Movement.targetSpeed): superfície, chuva, água e rampa.
function BotBrain.groundFactor(surface: string, rain: number, waterM: number, grade: number): number
	return Movement.surfaceSpeed(surface, rain) * Movement.waterFactor(waterM) * Movement.slopeFactor(grade)
end

---------------------------------------------------------------------------------------------
-- D-90: granada sem acertar o próprio squad
---------------------------------------------------------------------------------------------

-- Ponto de queda livre de companheiro? friends: lista plana x1, z1, x2, z2... (mesma unidade de
-- clear). Conta também quem está a caminho do ponto (destinos no mesmo formato).
function BotBrain.grenadeClear(ix: number, iz: number, friends: { number }, clear: number): boolean
	local c2 = clear * clear
	for i = 1, #friends - 1, 2 do
		local dx, dz = friends[i] - ix, friends[i + 1] - iz
		if dx * dx + dz * dz < c2 then
			return false
		end
	end
	return true
end

-- Ponto de mira da granada em quem está atrás de abrigo: um pouco além do abrigo, do lado dele
-- (a granada que cai na face da frente do dique não pega ninguém). hx, hz: onde o raio bateu no
-- abrigo; ex, ez: o inimigo. beyond: quanto passar do abrigo (mesma unidade).
function BotBrain.grenadeAim(hx: number, hz: number, ex: number, ez: number, beyond: number): (number, number)
	local dx, dz = ex - hx, ez - hz
	local l = math.sqrt(dx * dx + dz * dz)
	if l >= beyond or l < 1e-6 then
		return ex, ez
	end
	return hx + dx / l * beyond, hz + dz / l * beyond
end

---------------------------------------------------------------------------------------------
-- D-90: túneis (só o VC) e blindados
---------------------------------------------------------------------------------------------

-- Vale entrar no túnel? Distâncias em metros: do bot até a entrada, e de cada ponta até o destino.
function BotBrain.tunnelWorth(botToEntryM: number, entryToGoalM: number, exitToGoalM: number): boolean
	local T = BotBrain.TUNNEL
	return botToEntryM <= T.useWithinM and entryToGoalM - exitToGoalM >= T.gainM
end

-- Quantos blindados os bots de um lado tripulam (só lados com blindado: os EUA hoje).
function BotBrain.crewCount(teamBots: number, available: number): number
	local V = BotBrain.VEHICLE
	if teamBots < V.minTeamBots then
		return 0
	end
	return math.min(available, 1 + (teamBots - V.minTeamBots) // V.perCrewBots)
end

return BotBrain
