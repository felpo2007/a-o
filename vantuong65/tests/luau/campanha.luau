--!strict
-- Testes da campanha (plano de volta diária, 2026-11-12): calendário, missões, passe, mercado,
-- reforços, medalhas, vantagens, catálogo e perfil v4. Uso, a partir de vantuong65/:
--   lune run tests/luau/campanha.luau
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local S = "../../src/ReplicatedStorage/Shared/"
local Calendario = require(S .. "Calendario") :: any
local Missoes = require(S .. "Missoes") :: any
local Temporada = require(S .. "Temporada") :: any
local Mercado = require(S .. "Mercado") :: any
local Reforcos = require(S .. "Reforcos") :: any
local Medalhas = require(S .. "Medalhas") :: any
local Vantagens = require(S .. "Vantagens") :: any
local Commerce = require(S .. "Commerce") :: any
local Skins = require(S .. "Skins") :: any
local ProfileSchema = require("../../src/ServerScriptService/Modules/ProfileSchema") :: any

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FALHA " .. name .. ": " .. tostring(err))
	end
end

local T0 = 1794441600 -- 2026-11-12 00:00 UTC (quinta)
local DAY = 86400

-- ===== calendário =====
test("calendário: data UTC, semana começa na segunda, sorteio igual em todo lugar", function()
	assert(
		Calendario.dateString(Calendario.dayIndex(T0)) == "2026-11-12",
		Calendario.dateString(Calendario.dayIndex(T0))
	)
	assert(Calendario.dateString(Calendario.dayIndex(0)) == "1970-01-01")
	assert(Calendario.dateString(Calendario.dayIndex(951782400)) == "2000-02-29", "bissexto")
	assert(Calendario.weekday(T0) == 4, "quinta")
	-- segunda 2026-11-16 00:00 UTC abre a semana nova
	local monday = T0 + 4 * DAY
	assert(Calendario.weekIndex(monday) == Calendario.weekIndex(T0) + 1)
	assert(Calendario.weekIndex(monday - 1) == Calendario.weekIndex(T0))
	assert(Calendario.nextWeek(T0) == monday)
	assert(Calendario.nextDay(T0 + 5) == T0 + DAY)
	local a = Calendario.pick({ 1, 2, 3, 4, 5, 6, 7 }, 3, "x")
	local b = Calendario.pick({ 1, 2, 3, 4, 5, 6, 7 }, 3, "x")
	assert(#a == 3 and a[1] == b[1] and a[2] == b[2] and a[3] == b[3], "determinístico")
	assert(a[1] ~= a[2] and a[2] ~= a[3] and a[1] ~= a[3], "sem repetir")
end)

-- ===== missões =====
test("missões: 3 do dia e 3 da semana, por jogador e por dia, sem repetir", function()
	local d = Missoes.fresh("daily", 100, 555)
	local again = Missoes.fresh("daily", 100, 555)
	assert(#d == 3 and d[1].id == again[1].id and d[3].id == again[3].id)
	local seen = {}
	for _, r in d do
		assert(not seen[r.id] and Missoes.def(r.id).scope == "daily")
		seen[r.id] = true
	end
	local w = Missoes.fresh("weekly", 7, 555)
	assert(#w == 3 and Missoes.def(w[1].id).scope == "weekly")
	-- outro dia ou outro jogador: em geral muda (num punhado de dias, pelo menos uma vez)
	local differs = false
	for day = 101, 110 do
		if Missoes.fresh("daily", day, 555)[1].id ~= d[1].id then
			differs = true
		end
	end
	assert(differs, "as ordens mudam com o dia")
end)

test("missões: o evento conta só no que casa (classe da arma, setor, vitória) e para na meta", function()
	local list = {
		{ id = "d_kills_mg", p = 0, claimed = false },
		{ id = "d_sector", p = 0, claimed = false },
		{ id = "d_win", p = 0, claimed = false },
	}
	Missoes.apply(list, "kill", { kind = "rifle" })
	assert(list[1].p == 0, "fuzil não conta na metralhadora")
	for _ = 1, 6 do
		Missoes.apply(list, "kill", { kind = "mg" })
	end
	assert(list[1].p == 4 and Missoes.claimable(list[1]), "parou na meta")
	Missoes.apply(list, "sector_time", { sector = 2, seconds = 600 })
	assert(list[2].p == 0, "outro setor")
	local done = Missoes.apply(list, "sector_time", { sector = 3, seconds = 300 })
	assert(list[2].p == 5 and done[1] == "d_sector", "5 min no S3")
	Missoes.apply(list, "match_end", { result = "loss" })
	assert(list[3].p == 0)
	Missoes.apply(list, "match_end", { result = "win" })
	assert(Missoes.claimable(list[3]))
	local v = Missoes.view(list[3])
	assert(v.done and v.reward.stars > 0 and v.text == "Vencer uma partida")
	assert(#Missoes.apply(list, "inventado", {}) == 0)
end)

test("missões: troca grátis troca uma não concluída por outra fora da lista", function()
	local list = Missoes.fresh("daily", 200, 9)
	local before = list[2].id
	assert(Missoes.reroll(list, before, "daily", 200, 9, 1))
	assert(list[2].id ~= before and list[2].p == 0)
	assert(list[1].id ~= list[2].id and list[3].id ~= list[2].id)
	-- concluída não troca
	local d = Missoes.def(list[1].id)
	list[1].p = d.goal
	assert(not Missoes.reroll(list, list[1].id, "daily", 200, 9, 2))
	-- saneamento: id desconhecido sai, progresso fica dentro da meta
	local s = Missoes.sanitize({ { id = "hack", p = 9 }, { id = "d_kills", p = 999, claimed = true } }, "daily")
	assert(#s == 1 and s[1].p == 8 and s[1].claimed)
end)

-- ===== passe =====
test("passe: 50 níveis nas duas trilhas, skins de verdade, estrelas por nível", function()
	local S1 = Temporada.SEASON
	assert(S1.maxLevel == 50 and S1.endsAt - S1.startsAt == 42 * DAY, "6 semanas")
	local camoFree = 0
	for lvl = 1, 50 do
		for _, tr in { "free", "vet" } do
			local rw = Temporada.reward(tr, lvl)
			assert(rw and type(rw.name) == "string", tr .. lvl)
			for _, id in rw.ids or {} do
				assert(Skins.get(id), "skin inexistente " .. id)
			end
			if tr == "free" and rw.kind == "camo" then
				camoFree += 1
			end
		end
	end
	assert(camoFree == 3, "3 acabamentos de arma na trilha grátis")
	assert(Temporada.levelOf(0) == 0 and Temporada.levelOf(14) == 0 and Temporada.levelOf(15) == 1)
	local lvl, inL = Temporada.levelOf(10 * 15 + 7)
	assert(lvl == 10 and inL == 7)
	assert(Temporada.levelOf(99999) == 50)
	assert(Temporada.skipStars(152) == 13 and Temporada.skipStars(50 * 15) == 0)
end)

test("passe: Veterano só com o passe; quem compra no meio recebe o que passou", function()
	local stars = 6 * 15 + 3 -- nível 6
	assert(Temporada.claimable("free", 6, stars, false, {}))
	assert(not Temporada.claimable("free", 7, stars, false, {}), "nível não alcançado")
	assert(not Temporada.claimable("vet", 2, stars, false, {}), "sem o passe")
	assert(Temporada.claimable("vet", 2, stars, true, {}))
	assert(not Temporada.claimable("vet", 2, stars, true, { ["2"] = true }), "já recebido")
	local owed = Temporada.owedOnPurchase(stars, { ["1"] = true })
	assert(#owed == 5 and owed[1] == 2 and owed[5] == 6)
	assert(Temporada.STARS.match_win > Temporada.STARS.match_loss)
end)

-- ===== mercado =====
test("mercado: 4 do dia iguais em todo servidor, sem a camuflagem de mato, desconto honesto", function()
	local day = Calendario.dayIndex(T0)
	local a, b = Mercado.rotation(day), Mercado.rotation(day)
	assert(#a == 4)
	local ids = {}
	local robux = 0
	for i, it in a do
		assert(it.id == b[i].id and it.price == b[i].price, "determinístico")
		assert(not ids[it.id], "sem repetir")
		ids[it.id] = true
		local s = Skins.get(it.id)
		assert(s and s.kind ~= "camo", "camuflagem de mato fora da vitrine")
		if it.currency == "robux" then
			robux += 1
			assert(it.productKey == s.robuxKey)
		else
			assert(it.price < s.price and it.price > 0, "desconto em $")
		end
	end
	assert(robux == 1, "um item com Robux")
	local changes = false
	for d = day + 1, day + 7 do
		if Mercado.rotation(d)[1].id ~= a[1].id then
			changes = true
		end
	end
	assert(changes, "muda com o dia")
	local f = Mercado.featured(Calendario.weekIndex(T0))
	assert(f and Skins.get(f.id).kind == "uniform")
	local cr = nil
	for _, it in a do
		if it.currency == "cr" then
			cr = it
		end
	end
	assert(Mercado.priceToday(cr.id, day, Calendario.weekIndex(T0)) == cr.price)
end)

-- ===== reforços =====
test("reforços: fim de semana de Brasília, hora de fim que acumula, bônus que somam", function()
	-- sexta 2026-11-13: 18h de Brasília = 21:00 UTC
	local fri = T0 + DAY
	assert(not Reforcos.weekend(fri + 20 * 3600 + 59 * 60), "sexta 17h59 BRT")
	local on, ends = Reforcos.weekend(fri + 21 * 3600)
	assert(on, "sexta 18h BRT")
	-- acaba na segunda 00:00 de Brasília = segunda 03:00 UTC
	assert(ends == T0 + 4 * DAY + 3 * 3600, tostring(ends))
	assert(Reforcos.weekend(ends - 1) and not Reforcos.weekend(ends))
	assert(not Reforcos.weekend(T0 + 12 * 3600), "quinta")
	local b = { xpUntil = 0, crUntil = 0 }
	Reforcos.extend(b, "xp", 3600, T0)
	Reforcos.extend(b, "xp", 3600, T0 + 600)
	assert(b.xpUntil == T0 + 7200, "soma ao fim atual")
	Reforcos.extend(b, "xp", 999 * DAY, T0)
	assert(b.xpUntil == T0 + 30 * DAY, "teto de 30 dias")
	local xm, cm = Reforcos.mult(b, T0 + 100, true, true)
	assert(math.abs(xm - 2.1) < 1e-9 and math.abs(cm - 1.1) < 1e-9, string.format("%f %f", xm, cm))
	local xm2 = Reforcos.mult(b, fri + 22 * 3600, false, false)
	assert(xm2 == 3, "reforço + fim de semana somam")
	assert(Reforcos.mult({ xpUntil = 0, crUntil = 0 }, T0, false, false) == 1)
end)

-- ===== medalhas e cartão =====
test("medalhas: condição de jogo; cartão só com o que a pessoa tem", function()
	local got = Medalhas.earned({ kills = 100, wasRevived = 1 }, {})
	assert(table.find(got, "bronze_star") and table.find(got, "purple_heart"))
	assert(#Medalhas.earned({ kills = 100 }, { bronze_star = 1 }) == 0)
	local owned = { emb_s1 = true, tit_heroi_starlite = true }
	local medals = { bronze_star = 1, purple_heart = 2, navy_cross = 3, socorro = 4 }
	local c = Medalhas.validCard({
		emblem = "emb_s1",
		title = "tit_heroi_starlite",
		medals = { "bronze_star", "x", "bronze_star", "purple_heart", "navy_cross", "socorro" },
	}, owned, medals)
	assert(c and #c.medals == 3 and c.medals[1] == "bronze_star" and c.medals[2] == "purple_heart")
	assert(Medalhas.validCard({ emblem = "emb_hack", title = "tit_soldado" }, owned, medals) == nil)
	assert(
		Medalhas.validCard({ emblem = "tit_soldado", title = "tit_soldado" }, owned, medals) == nil,
		"título no lugar do emblema"
	)
	assert(Medalhas.validCard({ emblem = "emb_padrao", title = "tit_soldado" }, {}, {}), "o de todo mundo")
end)

-- ===== vantagens =====
test("vantagens: teto de +12% em combate somando passes e kits; números exatos", function()
	local function near(a: number?, b: number): boolean
		return a ~= nil and math.abs(a - b) < 1e-9
	end
	local one = Vantagens.compute({ PASS_PERK_SPEED = true })
	assert(near(one.speed, 1.06) and one.health == nil)
	local all = Vantagens.compute({ PASS_PERK_ALL = true })
	assert(near(all.speed, 1.06) and near(all.health, 1.12) and near(all.reload, 0.88))
	assert(near(all.sway, 0.88), "balanço cortado pelo teto")
	assert(
		near(all.breath, 1.6) and near(all.bandage, 0.74) and near(all.bleed, 0.8) and near(all.mark, 1.5),
		"apoio: número do plano"
	)
	assert(all.mags == 1 and all.grenades == 1, "contagem soma com os kits")
	for k, v in all do
		local d = Vantagens.KEYS[k]
		if d.combat then
			assert(v <= 1.12 + 1e-9 and v >= 0.88 - 1e-9, k)
		end
	end
	-- um kit que já desse +8% de vida deixaria só +3,7% para a vantagem (total 1,12)
	local withKit = Vantagens.compute({ PASS_PERK_HEALTH = true }, { health = 1.08 })
	assert(math.abs(withKit.health * 1.08 - 1.12) < 1e-9)
	assert(Vantagens.display("speed", 1.06) == "+6%" and Vantagens.display("reload", 0.88) == "-12%")
	assert(Vantagens.display("mags", 1) == "+1")
	-- leitura no jogador: sempre com o teto, mesmo com valor errado no atributo
	local p = roblox.Instance.new("Folder")
	assert(Vantagens.mult(p, "health") == 1 and Vantagens.extra(p, "mags") == 0, "sem passe")
	p:SetAttribute("Vant_health", 1.5)
	p:SetAttribute("Vant_mags", 9)
	assert(near(Vantagens.mult(p, "health"), 1.12) and Vantagens.extra(p, "mags") == 2)
end)

-- ===== catálogo =====
-- os itens já foram criados no Roblox (create-store, 2026-11-12): o ID é número (0 = ainda não criado)
test("catálogo: passes e produtos novos com ID, preço proposto e sem caixa-surpresa", function()
	local keys = {}
	for _, p in Commerce.CampaignPasses do
		assert(type(Commerce.IDS[p.key]) == "number", p.key)
		assert(p.suggestedRobux > 0 and #p.description > 10, p.key)
		keys[p.key] = true
	end
	for _, perk in Vantagens.PERKS do
		assert(keys[perk.key], "vantagem sem passe " .. perk.key)
	end
	assert(keys[Vantagens.BUNDLE] and keys.PASS_SEASON_S1 and keys.PASS_RECRUIT)
	local okGrants = { season_skip = true, boost_xp = true, boost_cr = true, credits = true }
	for _, p in Commerce.CampaignProducts do
		assert(type(Commerce.IDS[p.key]) == "number", p.key)
		assert(okGrants[p.grants], "entrega fechada (nada de sorteio): " .. p.key)
		assert(p.suggestedRobux > 0, p.key)
		assert(Commerce.campaignProduct(p.key) == p)
	end
	-- o pacote é mais barato que as 7 separadas
	local sum = 0
	for _, p in Commerce.CampaignPasses do
		if p.kind == "perk" then
			sum += p.suggestedRobux
		end
	end
	assert(Commerce.campaignPass("PASS_PERK_ALL").suggestedRobux < sum)
	-- as listas antigas (guardadas pela F2) não mudaram de tamanho
	assert(#Commerce.Passes == 6 and #Commerce.Products == 3)
end)

-- ===== perfil v4 =====
test("perfil v4: perfil antigo ganha a campanha zerada; nada se perde", function()
	assert(ProfileSchema.VERSION == 4)
	local p =
		ProfileSchema.migrate({ schema = 3, xp = 500, credits = 900, skins = { owned = { skin_m14_tape = true } } })
	assert(p.schema == 4 and p.xp == 500 and p.credits == 900 and p.skins.owned.skin_m14_tape)
	local c = p.campaign
	assert(c.season.id == Temporada.SEASON.id and c.season.stars == 0 and c.boosts.xpUntil == 0)
	assert(c.card.emblem == Medalhas.DEFAULT_EMBLEM and #c.missions.daily == 0)
	local bad = ProfileSchema.migrate({
		campaign = {
			season = { id = "S0", stars = 999 },
			boosts = { xpUntil = 0 / 0, crUntil = "x" },
			stats = { kills = -5, inventado = 3 },
			medals = { bronze_star = 10, hack = 1 },
			owned = { emb_s1 = true, [5] = true },
			card = { emblem = "emb_hack", title = "tit_soldado" },
		},
	}).campaign
	assert(bad.season.stars == 0, "temporada antiga começa do zero")
	assert(bad.boosts.xpUntil == 0 and bad.boosts.crUntil == 0)
	assert(bad.stats.kills == 0 and bad.stats.inventado == nil)
	assert(bad.medals.bronze_star == 10 and bad.medals.hack == nil)
	assert(bad.owned.emb_s1 and bad.card.emblem == Medalhas.DEFAULT_EMBLEM)
	local twice = ProfileSchema.migrate(ProfileSchema.migrate({ campaign = { season = { id = "S1", stars = 40 } } }))
	assert(twice.campaign.season.stars == 40)
end)

test("perfil v4: entre servidores, máximo e união (recibo aplicado nos dois não dobra)", function()
	local stored = ProfileSchema.migrate({ xp = 100, credits = 100 })
	local mem = ProfileSchema.migrate({ xp = 100, credits = 100 })
	stored.campaign.season.stars = 30 -- recibo de pular nível gravado direto (15 -> 30)
	mem.campaign.season.stars = 45 -- a sessão jogou e também recebeu o recibo
	stored.campaign.boosts.xpUntil = T0 + 3600
	mem.campaign.boosts.xpUntil = T0 + 3600
	stored.campaign.medals.bronze_star = 5
	mem.campaign.owned.emb_s1 = true
	stored.campaign.season.claimedFree["3"] = true
	mem.campaign.season.claimedFree["1"] = true
	mem.campaign.card = { emblem = "emb_s1", title = "tit_soldado", medals = {} }
	local rec = table.clone(stored)
	ProfileSchema.applySession(rec, stored, mem, ProfileSchema.synced(stored))
	local c = rec.campaign
	assert(c.season.stars == 45 and c.boosts.xpUntil == T0 + 3600, "máximo")
	assert(c.medals.bronze_star == 5 and c.owned.emb_s1, "união")
	assert(c.season.claimedFree["1"] and c.season.claimedFree["3"])
	assert(c.card.emblem == "emb_s1", "escolha da sessão")
	-- missões: o dia mais novo vence
	stored.campaign.missions.day = 20
	stored.campaign.missions.daily = { { id = "d_kills", p = 3, claimed = false } }
	mem.campaign.missions.day = 19
	local c2 = ProfileSchema.mergeCampaign(stored.campaign, mem.campaign)
	assert(c2.missions.day == 20 and c2.missions.daily[1].p == 3)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
