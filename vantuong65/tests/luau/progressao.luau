--!strict
-- Testes da progressão (D-72): postos e XP, teto anti-farm, equipamento (posto, créditos ou passe),
-- renascer onde caiu (regras e pagamento) e o perfil v3 (migração e delta da sessão).
-- Uso: lune run tests/luau/progressao.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Progression = require(S .. "Progression")
local Commerce = require(S .. "Commerce")
local Roles = require(S .. "Roles")
local ProfileSchema = require("../../src/ServerScriptService/Modules/ProfileSchema")

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

test("postos: 13 por lado, curva crescente, posto pelo XP", function()
	assert(#Progression.RANKS.US == Progression.MAX_RANK and #Progression.RANKS.VC == Progression.MAX_RANK)
	for i = 2, #Progression.STEPS do
		assert(Progression.STEPS[i] > Progression.STEPS[i - 1], "degrau não cresce em " .. i)
	end
	assert(Progression.rankFor(0) == 1)
	assert(Progression.rankFor(599) == 1 and Progression.rankFor(600) == 2)
	assert(Progression.rankFor(10 ^ 9) == Progression.MAX_RANK)
	local r, inRank, need = Progression.progress(700)
	assert(r == 2 and inRank == 100 and need == 900, string.format("%d %d %d", r, inRank, need))
	assert(Progression.rankName("US", 5) == "Sergeant")
	assert(Progression.rankName(nil, 3) == "Posto 3")
end)

test("teto anti-farm: no máximo 800 XP e 60 CI por minuto de ações", function()
	local w = Progression.newWindow()
	local tx, tc = 0, 0
	for i = 1, 50 do
		local gx, gc = Progression.grant(w, i * 0.5, 100, 10) -- 50 abates em 25 s
		tx += gx
		tc += gc
	end
	assert(tx == Progression.CAP.xp and tc == Progression.CAP.cr, tx .. " " .. tc)
	-- passada a janela, volta a render
	local gx = Progression.grant(w, 200, 100, 10)
	assert(gx == 100)
end)

test("par ajudante/ajudado: reanimar o mesmo companheiro só rende de novo depois da espera", function()
	local last = {}
	assert(Progression.pairReady(last, "revive:1", 0, 300))
	assert(not Progression.pairReady(last, "revive:1", 100, 300))
	assert(Progression.pairReady(last, "revive:2", 100, 300))
	assert(Progression.pairReady(last, "revive:1", 301, 300))
end)

test("fim de partida: vitória > empate > derrota, proporcional e nada com menos de 3 min", function()
	local w = Progression.matchReward("win", 3600, 3600)
	local d = Progression.matchReward("draw", 3600, 3600)
	local l = Progression.matchReward("loss", 3600, 3600)
	assert(w > d and d > l)
	assert(Progression.matchReward("win", 1800, 3600) == math.floor(w / 2 + 0.5))
	assert(Progression.matchReward("win", 100, 3600) == 0)
	assert(Progression.rankUpCredits(4, 6) == Progression.RANKUP_CREDITS * (5 + 6))
end)

test("equipamento: libera por posto, passe ou compra; compra exige posto e saldo", function()
	local id = "us_vest" -- nível 2
	assert(not Progression.gearUnlocked(id, 1, {}, {}))
	local ok, how = Progression.gearUnlocked(id, 7, {}, {})
	assert(ok and how == "rank")
	ok, how = Progression.gearUnlocked(id, 1, { PASS_KIT_ELITE = true }, {})
	assert(ok and how == "pass")
	assert(not Progression.gearUnlocked(id, 1, { PASS_KIT_VETERAN = true }, {}), "o Veterano não libera o nível 2")
	ok, how = Progression.gearUnlocked("us_canteen", 1, { PASS_KIT_ELITE = true }, {})
	assert(ok and how == "pass", "o Elite inclui o Veterano")
	ok, how = Progression.gearUnlocked(id, 1, {}, { us_vest = true })
	assert(ok and how == "bought")
	local can, why = Progression.canBuyGear(id, "US", 1, {}, {}, 99999)
	assert(not can and why and string.find(why, "posto"), tostring(why))
	can = Progression.canBuyGear(id, "US", 3, {}, {}, 10)
	assert(not can)
	can = Progression.canBuyGear(id, "US", 3, {}, {}, 900)
	assert(can)
	can = Progression.canBuyGear(id, "VC", 3, {}, {}, 900)
	assert(not can, "item do outro lado")
end)

test("equipamento: bônus e peso somam; desmarcado não vai", function()
	local ids = Progression.equipped("US", 7, {}, {}, { us_smoke = false })
	assert(table.find(ids, "us_vest") and not table.find(ids, "us_smoke"))
	local b = Progression.gearBonus(ids, "rifle")
	assert(b.mags == 2 and b.bandages == 2 and b.tourniquets == 1, string.format("%d %d", b.mags, b.bandages))
	assert(math.abs(b.fragFactor - 0.6) < 1e-6 and math.abs(b.stamina - 1.15) < 1e-6)
	assert(Progression.extraKg(ids, "rifle") > 5.7, "colete 4,5 kg + cantil + carregadores")
end)

test("renascer onde caiu: regras na ordem e espera mínima", function()
	local base = {
		matchOver = false,
		hasDeath = true,
		uses = 0,
		roleLocked = false,
		now = 100,
		deathT = 90,
		regularReadyAt = 95,
		inBounds = true,
		inWater = false,
		enemyHqM = 900,
		sectorLocked = false,
		contested = false,
		x = 0,
		z = 0,
		enemies = { 500, 0 },
	}
	local why, wait = Progression.inPlaceCheck(base)
	assert(why == nil and math.abs(wait - 50) < 1e-6, tostring(why) .. " " .. wait) -- mínimo de 60 s após a queda
	local c = table.clone(base)
	c.enemies = { 80, 30 }
	assert(Progression.inPlaceCheck(c) ~= nil, "inimigo a menos de 100 m")
	c = table.clone(base)
	c.uses = Progression.INPLACE.maxPerMatch
	assert(Progression.inPlaceCheck(c) ~= nil)
	c = table.clone(base)
	c.enemyHqM = 200
	assert(Progression.inPlaceCheck(c) ~= nil)
	c = table.clone(base)
	c.sectorLocked = true
	assert(Progression.inPlaceCheck(c) ~= nil)
end)

test("renascer onde caiu: pagamento por CI sobe, guardado vem antes, Robux só com produto", function()
	assert(Progression.inPlacePrice(0) == 60 and Progression.inPlacePrice(2) == 160)
	assert(Progression.inPlacePrice(3) == nil)
	assert(Progression.inPlaceAuto(0, 1000, 1, true) == "credit")
	assert(Progression.inPlaceAuto(0, 1000, 0, true) == "ci")
	assert(Progression.inPlaceAuto(0, 10, 0, true) == "robux")
	assert(Progression.inPlaceAuto(0, 10, 0, false) == nil)
	local ok, _, price = Progression.inPlacePay("ci", 1, 100, 0, false)
	assert(ok and price == 100)
end)

test("catálogo: os itens de jogo à venda são só os da lista do dono", function()
	for _, p in Commerce.Passes do
		if p.kind == "kit" then
			assert(Commerce.GAMEPLAY[p.key] == "kit", p.key)
		end
	end
	assert(Commerce.productGrants("PRODUCT_RESPAWN_INPLACE") == "respawn")
	for _, t in Progression.TIERS do
		assert(Commerce.GAMEPLAY[t.key] == "kit", t.key)
	end
end)

test("papéis de especialista pedem posto; infantaria e líder não", function()
	assert(Roles.minRank("rifleman") == 1 and Roles.minRank("squad_leader") == 1)
	assert(Roles.minRank("commander") >= 2)
	assert(Progression.roleUnlocked("commander", Roles.minRank("commander")))
	assert(not Progression.roleUnlocked("commander", 1))
end)

test("perfil v3: migração da v2 dá a verba inicial uma vez; lixo vira seguro", function()
	local p = ProfileSchema.migrate({ schema = 2, daily = { run = 2, lastDay = 10, total = 5 } })
	assert(p.schema == 3 and p.xp == 0 and p.credits == Progression.START_CREDITS and p.respawnCredits == 0)
	p = ProfileSchema.migrate({ xp = "x", credits = "y", gear = { us_vest = true, hack = true }, respawnCredits = -5 })
	assert(p.xp == 0 and p.credits == 0 and p.gear.us_vest == true and p.gear.hack == nil and p.respawnCredits == 0)
end)

test("perfil v3: delta da sessão nunca apaga o ganho de outro servidor", function()
	local stored = ProfileSchema.migrate({ xp = 1000, credits = 500, respawnCredits = 1 })
	local base = { xp = 800, credits = 400, respawnCredits = 1 } -- o que esta sessão viu no load
	local mem = ProfileSchema.migrate({ xp = 900, credits = 350, respawnCredits = 0, gear = { us_vest = true } })
	local rec = table.clone(stored)
	local wrote = ProfileSchema.applySession(rec, stored, mem, base)
	-- outro servidor somou +200 XP e +100 CI; esta sessão +100 XP, −50 CI e gastou 1 renascer
	assert(
		wrote.xp == 1100 and wrote.credits == 450 and wrote.respawnCredits == 0,
		string.format("%d %d %d", wrote.xp, wrote.credits, wrote.respawnCredits)
	)
	assert(rec.gear.us_vest == true)
	local nb = ProfileSchema.afterWrite(mem, { xp = 900, credits = 350, respawnCredits = 0 }, wrote)
	assert(nb.xp == 1100 and mem.xp == 1100 and mem.credits == 450)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
