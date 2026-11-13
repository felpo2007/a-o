--!strict
-- Passe de Campanha (plano de volta diária, 2026-11-12, seção 2): "Operação Starlite: Temporada 1",
-- 6 semanas, 50 níveis. As estrelas vêm de partidas, missões, do selo diário e das ordens do
-- comandante. Duas trilhas: grátis (créditos, emblemas, 3 pares de acabamento de arma, títulos) e
-- Veterano (Game Pass da temporada: uniformes, acabamentos, cartões de abate, gestos, música do menu
-- e 10% a mais de créditos). Quem compra o Veterano no meio recebe tudo o que já passou. Pular
-- nível: Developer Product (Commerce). Puro, testado no Lune (tests/luau/campanha.luau).
-- PLACEHOLDER: datas, estrelas por nível e recompensas, a ajustar com a telemetria.
-- Gestos, cartões de abate e música do menu ficam guardados no perfil (campaign.owned); o efeito
-- de cada um é de quem fizer esses sistemas (a tela mostra a posse).
local Temporada = {}

Temporada.SEASON = {
	id = "S1",
	name = "Operação Starlite: Temporada 1",
	startsAt = 1794441600, -- 2026-11-12 00:00 UTC
	endsAt = 1798070400, -- 2026-12-24 00:00 UTC (6 semanas)
	maxLevel = 50,
	starsPerLevel = 15,
}
Temporada.VET_CREDIT_BONUS = 0.10 -- Veterano: 10% a mais de créditos

-- estrelas por fonte (as missões trazem as delas)
Temporada.STARS = {
	match_win = 4,
	match_draw = 3,
	match_loss = 2,
	daily_seal = 2,
	daily_seal_rare = 5, -- dias 3 e 7 da caderneta
	order = 3, -- ordem do comandante cumprida
} :: { [string]: number }

-- kind: "credits" | "emblem" | "title" | "camo" | "uniform" | "killcard" | "gesture" | "music" | "boost"
-- camo e uniform: `ids` = skins do Shared/Skins (vão para a posse do perfil); boost: `id` = "xp" ou
-- "cr" e `amount` em segundos
export type Reward = { kind: string, id: string?, ids: { string }?, name: string, amount: number? }

local function credits(n: number): Reward
	return { kind = "credits", name = "Créditos", amount = n }
end

local FREE_MILESTONES: { [number]: Reward } = {
	[1] = { kind = "emblem", id = "emb_s1", name = "Emblema da Temporada 1" },
	[5] = { kind = "title", id = "tit_recruta_campanha", name = "Recruta de Campanha" },
	[10] = {
		kind = "camo",
		ids = { "skin_m14_worn", "skin_type56_tape" },
		name = "Acabamentos de campanha I",
	},
	[15] = { kind = "emblem", id = "emb_capacete", name = "Emblema: capacete M1" },
	[20] = { kind = "title", id = "tit_soldado_campanha", name = "Soldado de Campanha" },
	[25] = {
		kind = "camo",
		ids = { "skin_m60_worn", "skin_sks_worn" },
		name = "Acabamentos de campanha II",
	},
	[30] = { kind = "emblem", id = "emb_bambu", name = "Emblema: bambu" },
	[35] = { kind = "title", id = "tit_cabo_campanha", name = "Cabo de Campanha" },
	[40] = {
		kind = "camo",
		ids = { "skin_m79_od", "skin_rpd_worn" },
		name = "Acabamentos de campanha III",
	},
	[45] = { kind = "emblem", id = "emb_estrela", name = "Emblema: estrela de bronze" },
	[50] = { kind = "title", id = "tit_heroi_starlite", name = "Herói de Starlite" },
}

local VET_MILESTONES: { [number]: Reward } = {
	[1] = { kind = "boost", id = "xp", name = "XP dobrado por 1 h", amount = 3600 },
	[2] = { kind = "killcard", id = "kc_starlite", name = "Cartão de abate: Starlite" },
	[5] = { kind = "uniform", ids = { "skin_us_faded" }, name = "Uniforme de temporada (EUA)" },
	[10] = {
		kind = "camo",
		ids = { "skin_m14_birch", "skin_type56_birch" },
		name = "Acabamentos Veterano I",
	},
	[12] = { kind = "gesture", id = "ges_continencia", name = "Gesto: continência" },
	[15] = { kind = "killcard", id = "kc_dique", name = "Cartão de abate: dique" },
	[18] = { kind = "music", id = "mus_radio_1965", name = "Música do menu: rádio de 1965" },
	[20] = { kind = "uniform", ids = { "skin_vc_black" }, name = "Uniforme de temporada (VC)" },
	[22] = { kind = "gesture", id = "ges_mapa", name = "Gesto: conferir o mapa" },
	[25] = {
		kind = "camo",
		ids = { "skin_m60_od", "skin_type56_blued" },
		name = "Acabamentos Veterano II",
	},
	[28] = { kind = "killcard", id = "kc_arrozal", name = "Cartão de abate: arrozal" },
	[30] = { kind = "uniform", ids = { "skin_us_tiger" }, name = "Uniforme de temporada (EUA, tigrado)" },
	[32] = { kind = "music", id = "mus_patrulha", name = "Música do menu: patrulha" },
	[35] = {
		kind = "camo",
		ids = { "skin_m1911_blued", "skin_type54_worn" },
		name = "Acabamentos Veterano III",
	},
	[38] = { kind = "gesture", id = "ges_cantil", name = "Gesto: gole do cantil" },
	[40] = { kind = "uniform", ids = { "skin_us_duck" }, name = "Uniforme de temporada (EUA, duck hunter)" },
	[42] = { kind = "killcard", id = "kc_colina", name = "Cartão de abate: Colina 43" },
	[45] = {
		kind = "camo",
		ids = { "skin_m79_walnut", "skin_rpg2_od" },
		name = "Acabamentos Veterano IV",
	},
	[48] = { kind = "music", id = "mus_vitoria", name = "Música do menu: depois da batalha" },
	[50] = { kind = "emblem", id = "emb_veterano_ouro", name = "Emblema dourado de Veterano" },
}

Temporada.FREE = {} :: { [number]: Reward }
Temporada.VET = {} :: { [number]: Reward }
for lvl = 1, Temporada.SEASON.maxLevel do
	Temporada.FREE[lvl] = FREE_MILESTONES[lvl] or credits(if lvl < 25 then 50 else 75)
	Temporada.VET[lvl] = VET_MILESTONES[lvl]
		or (
			if lvl % 5 == 3
				then { kind = "boost", id = "xp", name = "XP dobrado por 1 h", amount = 3600 }
				else credits(100)
		)
end

function Temporada.active(now: number): boolean
	local s = Temporada.SEASON
	return now >= s.startsAt and now < s.endsAt
end

-- nível alcançado com as estrelas (0 antes do 1º) e as estrelas dentro do nível
function Temporada.levelOf(stars: number): (number, number)
	local s = Temporada.SEASON
	local lvl = math.min(s.maxLevel, math.floor(math.max(stars, 0) / s.starsPerLevel))
	local inLevel = if lvl >= s.maxLevel then s.starsPerLevel else math.max(stars, 0) % s.starsPerLevel
	return lvl, inLevel
end

-- estrelas que faltam para o próximo nível (pular nível); 0 no máximo
function Temporada.skipStars(stars: number): number
	local lvl = Temporada.levelOf(stars)
	if lvl >= Temporada.SEASON.maxLevel then
		return 0
	end
	return (lvl + 1) * Temporada.SEASON.starsPerLevel - math.max(stars, 0)
end

function Temporada.reward(track: string, level: number): Reward?
	return if track == "free" then Temporada.FREE[level] elseif track == "vet" then Temporada.VET[level] else nil
end

-- pode receber o nível da trilha? (Veterano só com o passe; nível alcançado; não recebido)
function Temporada.claimable(
	track: string,
	level: number,
	stars: number,
	veteran: boolean,
	claimed: { [string]: boolean }
): boolean
	if Temporada.reward(track, level) == nil or claimed[tostring(level)] then
		return false
	end
	if track == "vet" and not veteran then
		return false
	end
	return level <= (Temporada.levelOf(stars))
end

-- comprou o Veterano no meio: os níveis já alcançados da trilha Veterano ainda não recebidos
function Temporada.owedOnPurchase(stars: number, claimedVet: { [string]: boolean }): { number }
	local out = {}
	local lvl = Temporada.levelOf(stars)
	for l = 1, lvl do
		if not claimedVet[tostring(l)] then
			table.insert(out, l)
		end
	end
	return out
end

-- trilha inteira para a tela (contrato: [level] = Reward)
function Temporada.track(track: string): { [number]: Reward }
	return if track == "vet" then Temporada.VET else Temporada.FREE
end

return Temporada
