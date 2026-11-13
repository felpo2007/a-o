--!strict
-- Ordens do dia e da semana (plano de volta diária, 2026-11-12, seção 1). Puro, testado no Lune
-- (tests/luau/campanha.luau). Todas as missões são de jogo de verdade: abate, captura, reanimação,
-- tempo vivo num setor, partida com amigo no squad. 3 do dia (renovam à meia-noite UTC) e 3 da
-- semana (segunda 00:00 UTC); uma troca grátis por dia. Recompensa: XP, créditos e estrelas do passe.
-- O sorteio é por jogador e por dia (semente = UserId + dia): o mesmo em qualquer servidor.
-- `text` é o modelo inteiro em português (o cliente faz string.format(text, goal); o dicionário
-- traduz o modelo).
local Calendario = require(script and (script :: any).Parent.Calendario or "./Calendario") :: any

local Missoes = {}

export type Reward = { xp: number, cr: number, stars: number }
export type Def = {
	id: string,
	scope: string, -- "daily" | "weekly"
	event: string, -- evento de jogo que conta (Missoes.EVENTS)
	goal: number,
	text: string,
	reward: Reward,
	kind: string?, -- abate: classe da arma (Weapons.kind)
	sector: number?, -- tempo no setor
	result: string?, -- fim de partida: "win"
	alt: string?, -- outro evento que também conta (tratar: curativo)
}

local DAILY: Reward = { xp = 400, cr = 50, stars = 4 }
local WEEKLY: Reward = { xp = 2000, cr = 250, stars = 15 }

Missoes.POOL = {
	-- ===== do dia =====
	{ id = "d_kills", scope = "daily", event = "kill", goal = 8, text = "Fazer %d abates", reward = DAILY },
	{
		id = "d_kills_rifle",
		scope = "daily",
		event = "kill",
		kind = "rifle",
		goal = 6,
		text = "Fazer %d abates de fuzil",
		reward = DAILY,
	},
	{
		id = "d_kills_mg",
		scope = "daily",
		event = "kill",
		kind = "mg",
		goal = 4,
		text = "Fazer %d abates de metralhadora",
		reward = DAILY,
	},
	{ id = "d_assists", scope = "daily", event = "assist", goal = 5, text = "Fazer %d assistências", reward = DAILY },
	{ id = "d_capture", scope = "daily", event = "capture", goal = 2, text = "Capturar %d setores", reward = DAILY },
	{ id = "d_revive", scope = "daily", event = "revive", goal = 3, text = "Reanimar %d companheiros", reward = DAILY },
	{
		id = "d_treat",
		scope = "daily",
		event = "treat",
		alt = "bandage",
		goal = 4,
		text = "Tratar %d feridos",
		reward = DAILY,
	},
	{
		id = "d_sector",
		scope = "daily",
		event = "sector_time",
		sector = 3,
		goal = 5,
		text = "Ficar %d min vivo no setor S3",
		reward = DAILY,
	},
	{
		id = "d_matches",
		scope = "daily",
		event = "match_end",
		goal = 2,
		text = "Jogar %d partidas até o fim",
		reward = DAILY,
	},
	{
		id = "d_win",
		scope = "daily",
		event = "match_end",
		result = "win",
		goal = 1,
		text = "Vencer uma partida",
		reward = DAILY,
	},
	-- ===== da semana =====
	{ id = "w_kills", scope = "weekly", event = "kill", goal = 60, text = "Fazer %d abates", reward = WEEKLY },
	{ id = "w_capture", scope = "weekly", event = "capture", goal = 12, text = "Capturar %d setores", reward = WEEKLY },
	{
		id = "w_revive",
		scope = "weekly",
		event = "revive",
		goal = 15,
		text = "Reanimar %d companheiros",
		reward = WEEKLY,
	},
	{
		id = "w_wins",
		scope = "weekly",
		event = "match_end",
		result = "win",
		goal = 5,
		text = "Vencer %d partidas",
		reward = WEEKLY,
	},
	{
		id = "w_friend",
		scope = "weekly",
		event = "match_friend",
		goal = 1,
		text = "Jogar uma partida com um amigo no squad",
		reward = WEEKLY,
	},
	{
		id = "w_sector",
		scope = "weekly",
		event = "sector_time",
		sector = 3,
		goal = 30,
		text = "Ficar %d min vivo no setor S3",
		reward = WEEKLY,
	},
	{ id = "w_field", scope = "weekly", event = "time", goal = 120, text = "Passar %d min em campo", reward = WEEKLY },
} :: { Def }

Missoes.PER_SCOPE = 3
Missoes.REROLLS_PER_DAY = 1

-- eventos de jogo aceitos (os que o servidor manda para cá)
Missoes.EVENTS = {
	kill = true,
	assist = true,
	capture = true,
	revive = true,
	treat = true,
	bandage = true,
	sector_time = true,
	match_end = true,
	match_friend = true,
	time = true,
} :: { [string]: boolean }

local byId: { [string]: Def } = {}
for _, d in Missoes.POOL do
	byId[d.id] = d
end

function Missoes.def(id: string): Def?
	return byId[id]
end

-- missão no perfil: id e progresso (em unidades da meta; minutos para tempo)
export type Rec = { id: string, p: number, claimed: boolean }

local function ids(scope: string): { string }
	local out = {}
	for _, d in Missoes.POOL do
		if d.scope == scope then
			table.insert(out, d.id)
		end
	end
	return out
end

-- as missões do período (dia ou semana `key`) para o jogador `seed` (UserId)
function Missoes.fresh(scope: string, key: number, seed: number): { Rec }
	local out: { Rec } = {}
	for _, id in Calendario.pick(ids(scope), Missoes.PER_SCOPE, string.format("%s:%d:%d", scope, key, seed)) do
		table.insert(out, { id = id, p = 0, claimed = false })
	end
	return out
end

local function matches(d: Def, event: string, data: { [string]: any }): boolean
	if d.event ~= event and d.alt ~= event then
		return false
	end
	if d.kind and data.kind ~= d.kind then
		return false
	end
	if d.sector and data.sector ~= d.sector then
		return false
	end
	if d.result and data.result ~= d.result then
		return false
	end
	return true
end

-- quanto o evento soma: 1 por ocorrência; tempo (segundos) vira minutos
local function amount(d: Def, data: { [string]: any }): number
	if d.event == "sector_time" or d.event == "time" then
		return (tonumber(data.seconds) or 60) / 60
	end
	return 1
end

-- conta o evento nas missões; devolve as ids que acabaram de ficar prontas
function Missoes.apply(list: { Rec }, event: string, data: { [string]: any }?): { string }
	local done: { string } = {}
	if not Missoes.EVENTS[event] then
		return done
	end
	local dd = data or {}
	for _, r in list do
		local d = byId[r.id]
		if d and r.p < d.goal and matches(d, event, dd) then
			r.p = math.min(d.goal, r.p + amount(d, dd))
			if r.p >= d.goal then
				table.insert(done, r.id)
			end
		end
	end
	return done
end

-- troca uma missão (não concluída nem recebida) por outra do mesmo período que ainda não está na lista
function Missoes.reroll(list: { Rec }, id: string, scope: string, key: number, seed: number, nth: number): boolean
	local at: number? = nil
	for i, r in list do
		local d = byId[r.id]
		if r.id == id and d and d.scope == scope and not r.claimed and r.p < d.goal then
			at = i
		end
	end
	if not at then
		return false
	end
	local taken: { [string]: boolean } = {}
	for _, r in list do
		taken[r.id] = true
	end
	local options = {}
	for _, cand in ids(scope) do
		if not taken[cand] then
			table.insert(options, cand)
		end
	end
	if #options == 0 then
		return false
	end
	local pick = Calendario.pick(options, 1, string.format("troca:%s:%d:%d:%d", scope, key, seed, nth))[1]
	list[at] = { id = pick, p = 0, claimed = false }
	return true
end

-- pode receber a recompensa?
function Missoes.claimable(r: Rec): boolean
	local d = byId[r.id]
	return d ~= nil and not r.claimed and r.p >= d.goal
end

-- a missão no formato do Campanha_State (contrato)
function Missoes.view(r: Rec): { [string]: any }?
	local d = byId[r.id]
	if not d then
		return nil
	end
	return {
		id = d.id,
		scope = d.scope,
		text = d.text,
		goal = d.goal,
		progress = math.floor(r.p),
		done = r.p >= d.goal,
		claimed = r.claimed,
		reward = { xp = d.reward.xp, cr = d.reward.cr, stars = d.reward.stars },
	}
end

-- lista do perfil saneada (só ids conhecidas do período, progresso dentro da meta)
function Missoes.sanitize(raw: any, scope: string): { Rec }
	local out: { Rec } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, r in raw do
		local d = type(r) == "table" and byId[r.id] or nil
		if d and d.scope == scope and #out < Missoes.PER_SCOPE then
			local p = tonumber(r.p) or 0
			if p ~= p then
				p = 0
			end
			table.insert(out, { id = d.id, p = math.clamp(p, 0, d.goal), claimed = r.claimed == true })
		end
	end
	return out
end

return Missoes
