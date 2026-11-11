--!strict
-- Progressão (pedido do dono, 2026-11-11: "ranks para subir", "comprar itens da melhor qualidade",
-- "pagar e renascer no mesmo lugar"). Módulo PURO: testado no Lune (tests/luau/progressao.luau); o
-- servidor é Modules/ProgressionService e Modules/SpawnService.
--
-- O que tem aqui:
--   - postos de época por facção e a curva de XP (um só XP: o posto vale nos dois lados, porque o
--     TeamService troca o jogador de lado para equilibrar os times);
--   - XP e CRÉDITOS DE INTENDÊNCIA (CI) por ação e por partida, com teto por minuto (anti-farm);
--   - equipamento melhor em dois níveis ("Kit Veterano" e "Kit de Elite"), liberado de forma
--     permanente por QUALQUER um destes caminhos: posto alto (grátis), créditos (item a item) ou
--     Game Pass em Robux (o nível inteiro; decisão do dono em 2026-11-11);
--   - o renascer onde caiu: regras do servidor e os dois meios de pagamento (CI com preço que sobe
--     na partida, ou o Developer Product em Robux, que vira um "renascer guardado").
--
-- Nome da moeda: "créditos de intendência" (CI). Intendência é o serviço de suprimento dos dois
-- exércitos (Quartermaster dos Marines, hậu cần da Frente), cabe no dossiê datilografado do lobby e
-- não se confunde com o "suprimento" do time (Logistics), que paga construções e é de todos.
--
-- Todos os números são de DESIGN (PLACEHOLDER até o playtest); nenhum foi medido.
local Kit = require(script and (script :: any).Parent.Kit or "./Kit") :: any
local Roles = require(script and (script :: any).Parent.Roles or "./Roles") :: any

local Progression = {}

-- ===== moeda =====
Progression.CURRENCY = "créditos de intendência"
Progression.CUR = "CI"
Progression.START_CREDITS = 300 -- verba inicial: dá para o 1º item do Kit Veterano já no começo
Progression.MAX_CREDITS = 1000000000

-- ===== postos =====
-- Fontes (consultadas em 2026-11-11):
--   EUA: escala de praças e oficiais do USMC (military.com, "Marine Corps Ranks"); o Lance Corporal
--     (E-3) virou posto em 1958 (BCNR, decisão 3803-21, "In March 1958, the rank of Lance Corporal
--     was established"). A insígnia segue a do USMC: divisas com fuzis cruzados a partir do LCpl,
--     "rockers" no SSgt e no GySgt; barras, folha de carvalho e águia nos oficiais.
--   VC (Quân Giải phóng): a força usava designações por FUNÇÃO, não postos com insígnia (VWAM,
--     "History of the NVA and NLF": "used the functional rank designations of the PLAF"); os
--     soldados ficavam em células de 3 ("All soldiers were grouped into 3-man cells", "three cells to
--     a squad", Wikipedia, "NLF and PAVN strategy, organization and structure"). Por isso a
--     escada do VC é de funções (tổ → tiểu đội → trung đội → đại đội → tiểu đoàn → trung đoàn) e a
--     "insígnia" é a bandeira da Frente, sem divisas inventadas.
export type Insignia = {
	chevrons: number?,
	rockers: number?,
	rifles: boolean?,
	bars: number?,
	metal: string?, -- "gold" | "silver"
	leaf: boolean?,
	eagle: boolean?,
	flag: boolean?,
}
export type RankDef = { name: string, short: string, pt: string, insignia: Insignia }

local function us(name: string, short: string, pt: string, ins: Insignia): RankDef
	return { name = name, short = short, pt = pt, insignia = ins }
end
local function vc(name: string, short: string, pt: string): RankDef
	return { name = name, short = short, pt = pt, insignia = { flag = true } }
end

Progression.RANKS = {
	US = {
		us("Private", "Pvt", "soldado", {}),
		us("Private First Class", "PFC", "soldado de 1ª classe", { chevrons = 1 }),
		us("Lance Corporal", "LCpl", "cabo de esquadra", { chevrons = 1, rifles = true }),
		us("Corporal", "Cpl", "cabo, chefe de esquadra de tiro", { chevrons = 2, rifles = true }),
		us("Sergeant", "Sgt", "sargento, líder de squad", { chevrons = 3, rifles = true }),
		us("Staff Sergeant", "SSgt", "sargento de pelotão", { chevrons = 3, rockers = 1, rifles = true }),
		us("Gunnery Sergeant", "GySgt", "sargento da companhia", { chevrons = 3, rockers = 2, rifles = true }),
		us("Second Lieutenant", "2ndLt", "2º tenente, comandante de pelotão", { bars = 1, metal = "gold" }),
		us("First Lieutenant", "1stLt", "1º tenente", { bars = 1, metal = "silver" }),
		us("Captain", "Capt", "capitão, comandante de companhia", { bars = 2, metal = "silver" }),
		us("Major", "Maj", "major", { leaf = true, metal = "gold" }),
		us(
			"Lieutenant Colonel",
			"LtCol",
			"tenente-coronel, comandante de batalhão",
			{ leaf = true, metal = "silver" }
		),
		us("Colonel", "Col", "coronel, comandante de regimento", { eagle = true, metal = "silver" }),
	},
	VC = {
		vc("Tân binh", "TB", "recruta"),
		vc("Chiến sĩ", "CS", "combatente"),
		vc("Tổ trưởng", "TổT", "chefe da célula de três"),
		vc("Tiểu đội phó", "TĐP", "subchefe de esquadra"),
		vc("Tiểu đội trưởng", "TĐT", "chefe de esquadra (squad)"),
		vc("Trung đội phó", "TrĐP", "subcomandante de pelotão"),
		vc("Trung đội trưởng", "TrĐT", "comandante de pelotão"),
		vc("Đại đội phó", "ĐĐP", "subcomandante de companhia"),
		vc("Đại đội trưởng", "ĐĐT", "comandante de companhia"),
		vc("Tiểu đoàn phó", "TđP", "subcomandante de batalhão"),
		vc("Tiểu đoàn trưởng", "TđT", "comandante de batalhão"),
		vc("Trung đoàn phó", "TrđP", "subcomandante de regimento"),
		vc("Trung đoàn trưởng", "TrđT", "comandante de regimento"),
	},
} :: { [string]: { RankDef } }
Progression.MAX_RANK = 13

-- XP de um posto ao seguinte: os primeiros saem rápido (o 2º em ~1 partida), os últimos pedem dezenas
-- de partidas. Total do posto 13: 75.700 XP.
Progression.STEPS = { 600, 900, 1500, 2200, 3000, 4000, 5500, 7000, 9000, 11000, 14000, 17000 }
Progression.THRESHOLD = {} :: { number } -- XP total para chegar ao posto i
do
	local t = 0
	Progression.THRESHOLD[1] = 0
	for i, s in Progression.STEPS do
		t += s
		Progression.THRESHOLD[i + 1] = t
	end
end

function Progression.rankFor(xp: number): number
	local r = 1
	for i = 2, Progression.MAX_RANK do
		if xp >= Progression.THRESHOLD[i] then
			r = i
		else
			break
		end
	end
	return r
end

-- posto, XP dentro do posto e XP que o posto pede (0 no último)
function Progression.progress(xp: number): (number, number, number)
	local r = Progression.rankFor(xp)
	if r >= Progression.MAX_RANK then
		return r, xp - Progression.THRESHOLD[r], 0
	end
	return r, xp - Progression.THRESHOLD[r], Progression.THRESHOLD[r + 1] - Progression.THRESHOLD[r]
end

function Progression.rankDef(faction: string?, rank: number): RankDef
	local list = Progression.RANKS[faction or "US"] or Progression.RANKS.US
	return list[math.clamp(math.floor(rank), 1, #list)]
end

-- nome do posto no lado do jogador; sem lado, "Posto N"
function Progression.rankName(faction: string?, rank: number): string
	if faction ~= "US" and faction ~= "VC" then
		return "Posto " .. math.clamp(math.floor(rank), 1, Progression.MAX_RANK)
	end
	return Progression.rankDef(faction, rank).name
end

-- papel com posto mínimo (Roles.MIN_RANK)
function Progression.roleUnlocked(roleId: string, rank: number): boolean
	return rank >= Roles.minRank(roleId)
end

-- ===== recompensas =====
export type Reward = { xp: number, cr: number, label: string }
Progression.REWARDS = {
	kill = { xp = 100, cr = 10, label = "Abate" },
	assist = { xp = 50, cr = 5, label = "Assistência" },
	capture = { xp = 200, cr = 20, label = "Captura de ponto forte" },
	neutralize = { xp = 100, cr = 10, label = "Ponto forte neutralizado" },
	defend = { xp = 25, cr = 3, label = "Defesa de ponto forte (30 s)" },
	revive = { xp = 75, cr = 8, label = "Reanimação" },
	treat = { xp = 40, cr = 4, label = "Tratamento médico" },
	bandage = { xp = 15, cr = 1, label = "Curativo num companheiro" },
	resupply = { xp = 40, cr = 4, label = "Reabastecimento" },
	time = { xp = 10, cr = 2, label = "Tempo em campo (1 min)" },
} :: { [string]: Reward }
-- fim de partida (vitória vale mais), proporcional ao tempo no time; menos de 3 min não conta
Progression.MATCH = {
	win = { xp = 500, cr = 60, label = "Vitória" },
	draw = { xp = 300, cr = 40, label = "Empate" },
	loss = { xp = 200, cr = 25, label = "Derrota" },
} :: { [string]: Reward }
Progression.MATCH_MIN_S = 180
-- teto anti-farm: o que vem de AÇÕES numa janela deslizante de 60 s (o fim de partida fica fora)
Progression.CAP = { windowS = 60, xp = 800, cr = 60 }
-- o mesmo par (quem ajuda, quem é ajudado) só rende de novo depois disto (s)
Progression.PAIR_COOLDOWN = { revive = 300, treat = 120, bandage = 60, resupply = 120 } :: { [string]: number }
Progression.KILL_WINDOW_S = 120 -- último acerto até a morte (cobre caído + sangrando)
Progression.ASSIST_WINDOW_S = 60
Progression.DEFEND_EVERY_S = 30
Progression.TIME_EVERY_S = 60
Progression.RANKUP_CREDITS = 25 -- soldo de promoção: 25 CI x o posto novo

export type Window = { t: { number }, xp: { number }, cr: { number } }

function Progression.newWindow(): Window
	return { t = {}, xp = {}, cr = {} }
end

-- Concede até o teto da janela. Devolve o que foi concedido (XP, CI).
function Progression.grant(w: Window, now: number, xp: number, cr: number): (number, number)
	local cutoff = now - Progression.CAP.windowS
	while #w.t > 0 and w.t[1] <= cutoff do
		table.remove(w.t, 1)
		table.remove(w.xp, 1)
		table.remove(w.cr, 1)
	end
	local usedXp, usedCr = 0, 0
	for i = 1, #w.t do
		usedXp += w.xp[i]
		usedCr += w.cr[i]
	end
	local gx = math.clamp(math.floor(xp), 0, math.max(Progression.CAP.xp - usedXp, 0))
	local gc = math.clamp(math.floor(cr), 0, math.max(Progression.CAP.cr - usedCr, 0))
	if gx > 0 or gc > 0 then
		table.insert(w.t, now)
		table.insert(w.xp, gx)
		table.insert(w.cr, gc)
	end
	return gx, gc
end

-- result: "win" | "draw" | "loss"
function Progression.matchReward(result: string, secondsOnTeam: number, matchSeconds: number): (number, number)
	local r = Progression.MATCH[result]
	if not r or secondsOnTeam < Progression.MATCH_MIN_S then
		return 0, 0
	end
	local part = math.clamp(secondsOnTeam / math.max(matchSeconds, 1), 0, 1)
	return math.floor(r.xp * part + 0.5), math.floor(r.cr * part + 0.5)
end

-- O par (chave) já pode render de novo? Se puder, marca o instante.
function Progression.pairReady(last: { [string]: number }, key: string, now: number, cooldown: number): boolean
	local t = last[key]
	if t and now - t < cooldown then
		return false
	end
	last[key] = now
	return true
end

function Progression.rankUpCredits(fromRank: number, toRank: number): number
	local n = 0
	for r = fromRank + 1, toRank do
		n += Progression.RANKUP_CREDITS * r
	end
	return n
end

-- ===== equipamento melhor =====
-- Todo papel nasce com o kit padrão de 1965 (Kit + Roles). Os kits SOMAM a isso. Dois níveis; o
-- Game Pass do nível 2 inclui o nível 1. Passes valem nos dois lados (o servidor troca o jogador de
-- lado para equilibrar): cada lado recebe os itens do seu exército.
export type Tier = { tier: number, key: string, name: string, rank: number }
Progression.TIERS = {
	{ tier = 1, key = "PASS_KIT_VETERAN", name = "Kit Veterano", rank = 5 }, -- Sergeant / Tiểu đội trưởng
	{ tier = 2, key = "PASS_KIT_ELITE", name = "Kit de Elite", rank = 7 }, -- Gunnery Sergeant / Trung đội trưởng
} :: { Tier }

export type Gear = {
	id: string,
	faction: string,
	tier: number,
	name: string,
	effect: string,
	kg: number, -- peso fixo do item (os de consumo pesam pelo Kit: carregador, fumaça, curativo)
	price: number, -- em CI (compra permanente)
	buyRank: number, -- posto mínimo para comprar com CI
	mags: { [string]: number }?, -- carregadores a mais por tipo de arma (Kit.MAG_KG)
	frags: number?,
	smokes: number?,
	bandages: number?,
	tourniquets: number?,
	fragFactor: number?, -- energia de estilhaço/explosão no tronco x fator (colete)
	stamina: number?, -- recuperação do fôlego x fator (cantil)
}

-- Fontes do equipamento (consultadas em 2026-11-11):
--   bandoleira M2 de algodão: 6 bolsos, 60 cartuchos de 7,62 mm em clipes; no Vietnã também levava
--     carregadores de M14 (vietnamgear.com, "M2 Bandoleer");
--   colete M-1955 do USMC: náilon balístico + placas de Doron, ~10 lb (~4,5 kg), contra estilhaço, não
--     contra bala de fuzil (military.com, "Vietnam Flak Vests"; Wikipedia, "Flak jacket");
--   peitoral chinês Tipo 56: para o SKS (10 bolsos de clipes) ou o AK (3 carregadores), usado por
--     VC e NVA (fontes de colecionador: datas e unidades não confirmadas);
--   cantil de 1 quarto (~0,95 L) cheio: ~1,2 kg com a capa.
local MAGS_BANDOLEER = { rifle = 2, mg = 1, pistol = 2, launcher = 6 }

Progression.GEAR = {
	us_bandoleer = {
		id = "us_bandoleer",
		faction = "US",
		tier = 1,
		name = "Bandoleira M2 de algodão",
		effect = "+2 carregadores (MG: +1 cinta; M79: +6 granadas)",
		kg = 0.1,
		price = 300,
		buyRank = 1,
		mags = MAGS_BANDOLEER,
	},
	us_canteen = {
		id = "us_canteen",
		faction = "US",
		tier = 1,
		name = "3º cantil (1 quarto)",
		effect = "fôlego volta 15% mais rápido",
		kg = 1.2,
		price = 150,
		buyRank = 1,
		stamina = 1.15,
	},
	us_firstaid = {
		id = "us_firstaid",
		faction = "US",
		tier = 1,
		name = "Estojo de primeiros socorros reforçado",
		effect = "+2 curativos e +1 torniquete",
		kg = 0.15,
		price = 250,
		buyRank = 1,
		bandages = 2,
		tourniquets = 1,
	},
	us_vest = {
		id = "us_vest",
		faction = "US",
		tier = 2,
		name = "Colete M1955 (antiestilhaço)",
		effect = "estilhaço e explosão no tronco: −40% de energia. Não para bala",
		kg = 4.5,
		price = 900,
		buyRank = 3,
		fragFactor = 0.6,
	},
	us_smoke = {
		id = "us_smoke",
		faction = "US",
		tier = 2,
		name = "Granada de fumaça M18 extra",
		effect = "+1 fumaça",
		kg = 0,
		price = 400,
		buyRank = 3,
		smokes = 1,
	},
	vc_chestrig = {
		id = "vc_chestrig",
		faction = "VC",
		tier = 1,
		name = "Peitoral de lona (padrão chinês Tipo 56)",
		effect = "+2 carregadores (RPD: +1 tambor)",
		kg = 0.3,
		price = 300,
		buyRank = 1,
		mags = MAGS_BANDOLEER,
	},
	vc_canteen = {
		id = "vc_canteen",
		faction = "VC",
		tier = 1,
		name = "Bi đông extra (cantil)",
		effect = "fôlego volta 15% mais rápido",
		kg = 1.2,
		price = 150,
		buyRank = 1,
		stamina = 1.15,
	},
	vc_firstaid = {
		id = "vc_firstaid",
		faction = "VC",
		tier = 1,
		name = "Túi cứu thương (bolsa de socorro)",
		effect = "+2 curativos e +1 garrote",
		kg = 0.15,
		price = 250,
		buyRank = 1,
		bandages = 2,
		tourniquets = 1,
	},
	-- o VC não usava colete: o nível 2 dele é mais granada (e ele carrega menos peso)
	vc_grenade = {
		id = "vc_grenade",
		faction = "VC",
		tier = 2,
		name = "Granada de cabo extra",
		effect = "+1 granada",
		kg = 0,
		price = 700,
		buyRank = 3,
		frags = 1,
	},
	vc_smoke = {
		id = "vc_smoke",
		faction = "VC",
		tier = 2,
		name = "Granada de fumaça extra",
		effect = "+1 fumaça",
		kg = 0,
		price = 400,
		buyRank = 3,
		smokes = 1,
	},
} :: { [string]: Gear }
Progression.GEAR_ORDER = {
	"us_bandoleer",
	"us_canteen",
	"us_firstaid",
	"us_vest",
	"us_smoke",
	"vc_chestrig",
	"vc_canteen",
	"vc_firstaid",
	"vc_grenade",
	"vc_smoke",
}

function Progression.gearList(faction: string): { Gear }
	local out = {}
	for _, id in Progression.GEAR_ORDER do
		local g = Progression.GEAR[id]
		if g and g.faction == faction then
			table.insert(out, g)
		end
	end
	return out
end

-- maior nível liberado por Game Pass (o de Elite inclui o Veterano)
function Progression.passTier(passes: { [string]: boolean }?): number
	local best = 0
	if passes then
		for _, t in Progression.TIERS do
			if passes[t.key] then
				best = math.max(best, t.tier)
			end
		end
	end
	return best
end

-- maior nível liberado de graça pelo posto
function Progression.rankTier(rank: number): number
	local best = 0
	for _, t in Progression.TIERS do
		if rank >= t.rank then
			best = math.max(best, t.tier)
		end
	end
	return best
end

function Progression.unlockedTier(rank: number, passes: { [string]: boolean }?): number
	return math.max(Progression.passTier(passes), Progression.rankTier(rank))
end

-- Item liberado? Qualquer caminho vale. Devolve também o caminho: "rank" | "pass" | "bought".
function Progression.gearUnlocked(
	id: string,
	rank: number,
	passes: { [string]: boolean }?,
	bought: { [string]: boolean }?
): (boolean, string?)
	local g = Progression.GEAR[id]
	if not g then
		return false, nil
	end
	if Progression.rankTier(rank) >= g.tier then
		return true, "rank"
	elseif Progression.passTier(passes) >= g.tier then
		return true, "pass"
	elseif bought and bought[id] then
		return true, "bought"
	end
	return false, nil
end

-- Pode comprar com CI? (o servidor confere tudo de novo dentro da gravação atômica)
function Progression.canBuyGear(
	id: string,
	faction: string?,
	rank: number,
	passes: { [string]: boolean }?,
	bought: { [string]: boolean }?,
	credits: number
): (boolean, string?)
	local g = Progression.GEAR[id]
	if not g then
		return false, "item desconhecido"
	elseif g.faction ~= faction then
		return false, "item do outro lado"
	elseif Progression.gearUnlocked(id, rank, passes, bought) then
		return false, "já liberado"
	elseif rank < g.buyRank then
		return false, "posto " .. g.buyRank .. " para comprar"
	elseif credits < g.price then
		return false, string.format("faltam %d %s", g.price - credits, Progression.CUR)
	end
	return true, nil
end

-- ids que vão no próximo spawn: liberados, do lado do jogador e não desmarcados (gearOn[id] == false)
function Progression.equipped(
	faction: string,
	rank: number,
	passes: { [string]: boolean }?,
	bought: { [string]: boolean }?,
	gearOn: { [string]: boolean }?
): { string }
	local out = {}
	for _, g in Progression.gearList(faction) do
		if Progression.gearUnlocked(g.id, rank, passes, bought) and not (gearOn and gearOn[g.id] == false) then
			table.insert(out, g.id)
		end
	end
	return out
end

export type Bonus = {
	mags: number,
	frags: number,
	smokes: number,
	bandages: number,
	tourniquets: number,
	kg: number, -- peso fixo (colete, cantil...)
	fragFactor: number,
	stamina: number,
}

function Progression.gearBonus(ids: { string }, kind: string): Bonus
	local b: Bonus =
		{ mags = 0, frags = 0, smokes = 0, bandages = 0, tourniquets = 0, kg = 0, fragFactor = 1, stamina = 1 }
	for _, id in ids do
		local g = Progression.GEAR[id]
		if g then
			local m = g.mags
			b.mags += if m then (m[kind] or 0) else 0
			b.frags += g.frags or 0
			b.smokes += g.smokes or 0
			b.bandages += g.bandages or 0
			b.tourniquets += g.tourniquets or 0
			b.kg += g.kg
			b.fragFactor *= g.fragFactor or 1
			b.stamina *= g.stamina or 1
		end
	end
	return b
end

-- peso total acrescentado pelo equipamento (fixo + consumo pelos pesos do Kit), em kg
function Progression.extraKg(ids: { string }, kind: string): number
	local b = Progression.gearBonus(ids, kind)
	return b.kg + Kit.weight({ mags = b.mags, frags = b.frags, smokes = b.smokes, bandages = b.bandages }, kind)
end

-- ===== renascer onde caiu =====
-- Regras (as mesmas para os dois meios de pagamento; o servidor confere ANTES de cobrar):
--   - só depois de morrer (ou de desistir caído), no ponto da queda, e não se foi evacuado (medevac);
--   - nunca antes da espera normal (a mesma onda de um posto de reunião, mínimo de 60 s): o que se
--     paga é o LUGAR, nunca tempo de spawn;
--   - nenhum inimigo ativo a menos de 100 m (o posto de reunião usa 75 m);
--   - nem em área inimiga travada (setor do inimigo que o seu lado não pode atacar), nem a menos de
--     250 m do QG inimigo, nem com o ponto forte do setor em disputa, nem na água, nem fora do mapa;
--   - no máximo 3 por partida.
-- Pagamento: créditos (60, 100 e 160 CI: sobe a cada uso na partida) ou o Developer Product em
-- Robux (preço fixo, definido no Roblox). O recibo do produto SEMPRE vira um "renascer guardado" no
-- perfil, gasto só quando o renascer acontece: se ficar impossível, ele espera a próxima queda.
Progression.INPLACE = {
	prices = { 60, 100, 160 },
	maxPerMatch = 3,
	enemyM = 100,
	enemyHqM = 250,
	minWaitS = 60,
	buyTimeoutS = 120, -- s que o servidor espera o recibo para renascer na hora
}

function Progression.inPlacePrice(uses: number): number?
	return Progression.INPLACE.prices[uses + 1]
end

export type InPlaceCtx = {
	matchOver: boolean,
	hasDeath: boolean, -- há ponto de queda nesta partida (morreu ou desistiu; não evacuado)
	uses: number, -- renasceres no lugar já usados nesta partida
	roleLocked: boolean,
	now: number,
	deathT: number,
	regularReadyAt: number, -- quando um posto de reunião ficaria pronto (SpawnRules)
	inBounds: boolean,
	inWater: boolean,
	enemyHqM: number,
	sectorLocked: boolean,
	contested: boolean,
	x: number, -- m
	z: number,
	enemies: { number }, -- x1, z1, x2, z2... em m (inimigos ativos)
}

-- Devolve o motivo do bloqueio (nil = permitido) e a espera em s.
function Progression.inPlaceCheck(c: InPlaceCtx): (string?, number)
	local I = Progression.INPLACE
	local wait = math.max(c.regularReadyAt, c.deathT + I.minWaitS) - c.now
	wait = math.max(0, wait)
	if c.matchOver then
		return "partida encerrada", wait
	elseif not c.hasDeath then
		return "sem ponto de queda", wait
	elseif c.uses >= I.maxPerMatch then
		return string.format("limite de %d por partida", I.maxPerMatch), wait
	elseif c.roleLocked then
		return "papel acima do seu posto", wait
	elseif not c.inBounds then
		return "fora da área de operação", wait
	elseif c.inWater then
		return "caiu na água", wait
	elseif c.enemyHqM < I.enemyHqM then
		return "perto do QG inimigo", wait
	elseif c.sectorLocked then
		return "área inimiga travada", wait
	elseif c.contested then
		return "setor em disputa", wait
	end
	local r2 = I.enemyM * I.enemyM
	for i = 1, #c.enemies, 2 do
		local dx, dz = c.enemies[i] - c.x, c.enemies[i + 1] - c.z
		if dx * dx + dz * dz < r2 then
			return string.format("inimigo a menos de %d m", I.enemyM), wait
		end
	end
	return nil, wait
end

-- Meio de pagamento: "ci" (créditos), "credit" (renascer guardado) ou "robux" (abre a compra).
-- Devolve se pode, o motivo e o preço em CI (só para "ci").
function Progression.inPlacePay(
	method: string,
	uses: number,
	credits: number,
	respawnCredits: number,
	productOn: boolean
): (boolean, string?, number?)
	if method == "credit" then
		if respawnCredits >= 1 then
			return true, nil, nil
		end
		return false, "nenhum renascer guardado", nil
	elseif method == "ci" then
		local price = Progression.inPlacePrice(uses)
		if not price then
			return false, "limite da partida", nil
		elseif credits < price then
			return false, string.format("faltam %d %s", price - credits, Progression.CUR), price
		end
		return true, nil, price
	elseif method == "robux" then
		if productOn then
			return true, nil, nil
		end
		return false, "compra em Robux indisponível", nil
	end
	return false, "pagamento desconhecido", nil
end

-- Meio escolhido pelo atalho da carta: guardado > créditos > Robux.
function Progression.inPlaceAuto(uses: number, credits: number, respawnCredits: number, productOn: boolean): string?
	for _, m in { "credit", "ci", "robux" } do
		if Progression.inPlacePay(m, uses, credits, respawnCredits, productOn) then
			return m
		end
	end
	return nil
end

return Progression
