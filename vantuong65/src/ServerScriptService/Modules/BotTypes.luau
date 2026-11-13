--!strict
-- Tipos dos bots, compartilhados entre o BotService e os módulos que ele usa (D-90):
-- BotLocomotion (pernas), BotSquads (squad), BotTunnels (túneis do VC), BotVehicles (blindados) e
-- BotWorld (mapa). Só tipos e os ganchos que o BotService preenche (evita require circular).
local Rng = require(game:GetService("ReplicatedStorage").Shared.Rng)
local Weapons = require(game:GetService("ReplicatedStorage").Shared.Weapons)

export type Cover = {
	pos: Vector3, -- onde ficar (Y = chão)
	level: number, -- 1 baixo, 2 médio, 3 alto (BotBrain.coverLevel)
	kind: string, -- BotBrain.coverKind
	side: number, -- abrigo alto: lado livre para atirar (-1 ou 1); 0 = cego ou não precisa
	sideDir: Vector3, -- perpendicular à direção do inimigo
}

export type Bot = {
	id: number,
	faction: string,
	role: string,
	weapon: Weapons.Weapon,
	rng: Rng.Rng,
	diff: any, -- BotBrain.Difficulty
	style: any, -- BotBrain.Style
	model: Model?,
	spawning: boolean,
	life: number, -- conta as vidas: tarefa atrasada da vida anterior não mexe na nova
	-- tiro
	mag: number,
	-- D-108: carregadores de sobra (cartuchos na espingarda) e a caixa de munição do Suporte
	spare: number,
	dryAt: number?, -- desde quando está sem munição de sobra (acha 1 carregador em BOT_CATAR_S)
	boxCheckAt: number, -- próxima busca de caixa
	reloadUntil: number,
	nextVolley: number,
	firing: boolean,
	target: Model?,
	reactAt: number,
	trackSince: number, -- D-90: desde quando segue o alvo atual (mira que firma)
	-- percepção (D-90): notar leva tempo
	noticeTarget: Model?,
	noticeAcc: number,
	heardPos: Vector3?, -- de onde veio um tiro ouvido (vira para lá)
	heardAt: number,
	-- memória do inimigo
	lastKnown: Vector3?,
	lastKnownAt: number,
	threatPos: Vector3?,
	threatAt: number,
	inCombat: boolean,
	contactAt: number,
	nextSuppress: number,
	-- corpo
	supp: number,
	lastHealth: number,
	lastThink: number,
	rays: number,
	open: boolean,
	wounded: boolean,
	-- abrigo
	cover: Cover?,
	coverSector: number?,
	mode: string, -- "advance" | "move" | "hide" | "peek" | "hold"
	moveUntil: number,
	nextPeek: number,
	peekUntil: number,
	peekFired: boolean,
	bursts: number,
	burstsMax: number,
	failedPeeks: number,
	exposed: number,
	recheckAt: number,
	searchAt: number,
	avoid: Vector3?,
	resumeAt: number,
	grenades: number,
	nextGrenade: number,
	-- objetivo
	goal: Vector3?,
	goalSector: number?,
	readyAt: number,
	removed: boolean,
	-- D-90: módulos
	loco: any, -- BotLocomotion
	squad: any, -- BotSquads (squad em que está)
	slot: number, -- lugar no squad (0 = líder)
	team: number, -- equipe do lance (1 ou 2)
	crew: any, -- BotVehicles: tripulação ou passageiro de um veículo
	tunnel: any, -- BotTunnels: em trânsito no túnel
	scanAt: number,
	scanSide: number,
	order: string?, -- gancho do Studio: cena forçada
	-- 2026-11-12: avanço e squad de jogador
	stillSince: number?, -- parado (sem andar) desde quando, fora de combate (BotBrain.idleExpired)
	playerSquad: string?, -- SquadId do squad de JOGADOR em que o bot está (atributo no modelo)
	-- D-107: lotação, nível de detalhe e lance de assalto
	nextThink: number, -- quando pensa de novo (BotBrain.LOD pela distância do humano mais perto)
	lod: number, -- 1 perto, 2 meio, 3 longe
	thinkDt: number, -- intervalo do último pensamento (s)
	head: BasePart?, -- cabeça do modelo atual (supressão: sem FindFirstChild a cada bala)
	rushTo: Vector3?, -- lance de assalto em curso: até onde
	rushUntil: number,
	nextRush: number, -- descanso entre lances
	pinnedSince: number?, -- preso pelo fogo desde quando
	fightSince: number, -- parado lutando no mesmo lugar desde quando (chegou ao abrigo, começou o combate)
}

-- Ganchos que o BotService preenche no start (os módulos chamam por aqui)
export type Hooks = {
	setStance: (model: Model, stance: string) -> (),
	throwGrenade: (bot: Bot, at: Vector3) -> boolean,
	objective: (faction: string) -> (Vector3?, number?),
	bots: () -> { Bot },
}

local BotTypes = {}
BotTypes.hooks = ({} :: any) :: Hooks

return BotTypes
