--!strict
-- Testes dos bots de nível médio (Lune): reação, mira, rajadas, supressão, abrigo, postura pelo
-- lugar, granada, emboscada e orçamento de raios. Tudo no BotBrain (puro).
-- Uso: lune run tests/luau/bots.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local BotBrain = require(S .. "BotBrain") :: any
local Weapons = require(S .. "Weapons") :: any

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

local D = BotBrain.DIFFICULTY.medium
local US, VC = BotBrain.STYLE.US, BotBrain.STYLE.VC
local C = BotBrain.C

-- ===== tabela única =====
test("dificuldade: uma tabela (medium) com reação 0,4-0,8 s e todos os campos", function()
	assert(D.reaction[1] == 0.4 and D.reaction[2] == 0.8, "reação pedida pelo dono")
	for _, k in
		{
			"aimBaseRad",
			"aimRangeM",
			"aimSuppression",
			"recoilRad",
			"volley",
			"hideTime",
			"burstsPerCover",
			"retreatHealth",
			"grenade",
			"rayRate",
			"rayCap",
			"suppTauS",
			"pinnedAt",
		}
	do
		assert(D[k] ~= nil, "falta " .. k)
	end
	assert(D.grenade.minM == 15 and D.grenade.maxM == 35 and D.grenade.perLife == 2)
end)

-- ===== reação =====
test("reação: 0,4 a 0,8 s; em combate mais rápida; suprimido mais lenta", function()
	assert(math.abs(BotBrain.reactionTime(D, 0, 0, false) - 0.4) < 1e-9)
	assert(math.abs(BotBrain.reactionTime(D, 1, 0, false) - 0.8) < 1e-9)
	for i = 0, 20 do
		local t = BotBrain.reactionTime(D, i / 20, 0, false)
		assert(t >= 0.4 and t <= 0.8, "fora da faixa: " .. t)
	end
	assert(BotBrain.reactionTime(D, 0.5, 0, true) < BotBrain.reactionTime(D, 0.5, 0, false))
	assert(BotBrain.reactionTime(D, 0.5, 1, false) > BotBrain.reactionTime(D, 0.5, 0, false))
end)

test("detecção: deitado é visto de mais perto; alvo já seguido não some", function()
	assert(BotBrain.spotFactor(D, "prone", false) < BotBrain.spotFactor(D, "crouch", false))
	assert(BotBrain.spotFactor(D, "crouch", false) < BotBrain.spotFactor(D, "stand", false))
	assert(BotBrain.spotFactor(D, "prone", true) == 1)
end)

-- ===== mira =====
test("mira: acerta bem a 100 m (>= 35% no tronco), mal a 300 m (<= 10%)", function()
	local h = C.torsoHalfM
	local p50 = BotBrain.hitChance(BotBrain.aimError(D, 50), 50, h)
	local p100 = BotBrain.hitChance(BotBrain.aimError(D, 100), 100, h)
	local p200 = BotBrain.hitChance(BotBrain.aimError(D, 200), 200, h)
	local p300 = BotBrain.hitChance(BotBrain.aimError(D, 300), 300, h)
	print(
		string.format(
			"       tronco: 50 m %.0f%%, 100 m %.0f%%, 200 m %.0f%%, 300 m %.0f%%",
			p50 * 100,
			p100 * 100,
			p200 * 100,
			p300 * 100
		)
	)
	assert(p100 >= 0.35 and p100 <= 0.6, "100 m: " .. p100)
	assert(p300 <= 0.10, "300 m: " .. p300)
	assert(p50 > p100 and p100 > p200 and p200 > p300)
end)

test("mira: erro angular cresce com a distância; piora andando, suprimido e com braço ferido", function()
	assert(BotBrain.aimError(D, 300) > BotBrain.aimError(D, 100))
	local base = BotBrain.aimError(D, 100, {})
	assert(BotBrain.aimError(D, 100, { moving = true }) > base)
	assert(BotBrain.aimError(D, 100, { suppression = 0.5 }) > base)
	assert(BotBrain.aimError(D, 100, { suppression = 1 }) > BotBrain.aimError(D, 100, { suppression = 0.5 }))
	assert(BotBrain.aimError(D, 100, { armHurt = true }) > base)
	-- suprimido de vez, a 100 m acerta menos que a metade do normal
	local pS = BotBrain.hitChance(BotBrain.aimError(D, 100, { suppression = 1 }), 100, C.torsoHalfM)
	local p0 = BotBrain.hitChance(base, 100, C.torsoHalfM)
	assert(pS < p0 / 2, string.format("suprimido %.2f vs %.2f", pS, p0))
end)

test("mira: deitado e agachado firmam; recuo abre a rajada até um teto", function()
	local st = BotBrain.aimError(D, 100, { stance = "stand" })
	assert(BotBrain.aimError(D, 100, { stance = "crouch" }) < st)
	assert(BotBrain.aimError(D, 100, { stance = "prone" }) < BotBrain.aimError(D, 100, { stance = "crouch" }))
	local prev = 0
	for shot = 1, 8 do
		local e = BotBrain.aimError(D, 100, { shot = shot, kind = "mg" })
		assert(e >= prev, "recuo diminuiu no tiro " .. shot)
		prev = e
	end
	local cap = math.sqrt(BotBrain.aimError(D, 100) ^ 2 + D.recoilMaxRad ^ 2)
	assert(BotBrain.aimError(D, 100, { shot = 50, kind = "mg" }) <= cap + 1e-12, "recuo sem teto")
	assert(
		BotBrain.aimError(D, 100, { shot = 3, kind = "mg" }) > BotBrain.aimError(D, 100, { shot = 3, kind = "rifle" })
	)
end)

test("compatibilidade F3: aimSigma, burst e shotDelay continuam valendo", function()
	assert(BotBrain.aimSigma(300, false, 0.5) > BotBrain.aimSigma(50, false, 0.5))
	assert(BotBrain.aimSigma(100, true, 0.5) > BotBrain.aimSigma(100, false, 0.5))
	assert(BotBrain.burst("rifle", 0.9) == 1)
	local b = BotBrain.burst("mg", 0.99)
	assert(b >= 4 and b <= 8)
	assert(math.abs(BotBrain.shotDelay("mg", 600, true, 0.5) - 0.1) < 1e-9)
	assert(math.abs(BotBrain.shotDelay("rifle", 725, false, 0) - 0.8) < 1e-9)
end)

-- ===== rajadas =====
test("rajadas curtas: fuzil 2-3 tiros, metralhadora 4-8; cadência nunca acima da arma", function()
	for i = 0, 50 do
		local r = i / 50
		local nr, nm = BotBrain.volleySize(D, "rifle", r), BotBrain.volleySize(D, "mg", r)
		assert(nr >= 2 and nr <= 3, "fuzil " .. nr)
		assert(nm >= 4 and nm <= 8, "mg " .. nm)
	end
	assert(BotBrain.volleySize(D, "mg", 0) == 4 and BotBrain.volleySize(D, "mg", 0.999) == 8)
	local m14, sks, m60 = Weapons.get("m14"), Weapons.get("sks"), Weapons.get("m60")
	assert(math.abs(BotBrain.volleyGap(D, "mg", m60.rpm, 0.5) - 60 / m60.rpm) < 1e-9, "metralhadora na cadência")
	local g = BotBrain.volleyGap(D, "rifle", m14.rpm, 0.5)
	assert(g >= D.aimedGap[1] and g <= D.aimedGap[2], "M14: tiro pensado")
	assert(BotBrain.volleyGap(D, "rifle", sks.rpm, 0) >= 60 / sks.rpm - 1e-9, "SKS não passa da cadência prática")
	local p = BotBrain.pause(D, "rifle", 0.5)
	assert(p >= 0.8 and p <= 1.7, "pausa entre rajadas")
end)

test("abrigo: VC espera mais escondido e dá mais rajadas por abrigo; ferido espera o dobro", function()
	for i = 0, 10 do
		local r = i / 10
		assert(BotBrain.hideTime(D, VC, r, false) > BotBrain.hideTime(D, US, r, false))
		assert(BotBrain.burstsPerCover(D, VC, r, false) >= BotBrain.burstsPerCover(D, US, r, false))
		assert(math.abs(BotBrain.hideTime(D, US, r, true) - 2 * BotBrain.hideTime(D, US, r, false)) < 1e-9)
	end
	assert(BotBrain.burstsPerCover(D, US, 0, false) >= 2 and BotBrain.burstsPerCover(D, US, 0.99, false) <= 4)
	assert(BotBrain.burstsPerCover(D, US, 0.5, true) == math.huge, "ferido não troca de abrigo para avançar")
end)

-- ===== supressão =====
-- simula t segundos em passos de 0,3 s (o pensamento do bot)
local function decay(s: number, t: number): number
	local n = math.floor(t / 0.3 + 0.5)
	for _ = 1, n do
		s = BotBrain.suppressionDecay(D, s, 0.3)
	end
	return s
end

test("supressão: rajada de 5 a 0,5 m prende alguns segundos (2 s sim, 6 s não)", function()
	local s = 0
	for _ = 1, 5 do
		s = BotBrain.suppressionAdd(D, s, 0.5, false)
	end
	assert(BotBrain.pinned(D, s), "deveria prender: " .. s)
	assert(BotBrain.pinned(D, decay(s, 2)), "solto cedo demais")
	assert(not BotBrain.pinned(D, decay(s, 6)), "preso tempo demais")
	assert(BotBrain.underFire(D, decay(s, 6)), "ainda sob fogo aos 6 s")
end)

test("supressão: 1 tiro a 1 m abaixa sem prender; some em ~10 s; a 3,5 m nada", function()
	local s = BotBrain.suppressionAdd(D, 0, 1, false)
	assert(BotBrain.underFire(D, s) and not BotBrain.pinned(D, s))
	assert(BotBrain.underFire(D, decay(s, 2)), "abaixado por alguns segundos")
	assert(not BotBrain.underFire(D, decay(s, 10)))
	assert(BotBrain.suppressionAdd(D, 0, 3.5, false) == 0, "longe demais para assustar")
	assert(
		BotBrain.suppressionAdd(D, 0, 0.2, false) > BotBrain.suppressionAdd(D, 0, 2, false),
		"mais perto, mais susto"
	)
end)

test("supressão: acerto prende; nunca passa de 1", function()
	assert(BotBrain.pinned(D, BotBrain.suppressionAdd(D, 0, 0, true)))
	local s = 0
	for _ = 1, 40 do
		s = BotBrain.suppressionAdd(D, s, 0, false)
	end
	assert(s == 1)
end)

test("bala que passa: distância da linha e quanto à frente", function()
	local miss, along = BotBrain.passBy(0, 0, 0, 1, 0, 0, 50, 2, 0)
	assert(math.abs(miss - 2) < 1e-9 and math.abs(along - 50) < 1e-9)
	local _, behind = BotBrain.passBy(0, 0, 0, 1, 0, 0, -10, 0, 1)
	assert(behind < 0, "atrás de quem atirou")
end)

-- ===== abrigo: tipo, nível e postura =====
test("tipo de abrigo pelo que o raio acertou (nomes do FeatureBuilder e do AssetLoader)", function()
	assert(BotBrain.coverKind("Dike", nil, nil, false) == "dike")
	assert(BotBrain.coverKind("PaddyHedge", nil, "Bamboo", false) == "hedge")
	assert(BotBrain.coverKind("BambooHedge", nil, "Bamboo", false) == "hedge")
	assert(BotBrain.coverKind("Madeira0_0", "ph_island_tree_01", "Wood", false) == "trunk")
	assert(BotBrain.coverKind("Folhas0_0", "ph_island_tree_01", "Bamboo", false) == "brush")
	assert(BotBrain.coverKind("Walls", "HutPlaceholder", "MudWall", false) == "wall")
	assert(BotBrain.coverKind("Roof", "HutPlaceholder", "Thatch", false) == "thatch")
	assert(BotBrain.coverKind("MeshPart", "hut_thatch", nil, false) == "wall")
	assert(BotBrain.coverKind("MeshPart", "sandbags", nil, false) == "sandbags")
	assert(BotBrain.coverKind("MeshPart", "trench_section", nil, false) == "trench")
	assert(BotBrain.coverKind("MeshPart", "vc_bunker", nil, false) == "earth")
	assert(BotBrain.coverKind("MeshPart", "elephant_grass", "Bamboo", false) == "grass")
	assert(BotBrain.coverKind("Terrain", nil, nil, true) == "terrain")
	assert(BotBrain.coverKind("Chassis", "M48A3", nil, false) == "solid")
	-- sebe, moita e capim escondem mas não param bala (CombatService.PASS)
	assert(BotBrain.COVER.dike.solid and BotBrain.COVER.wall.solid and BotBrain.COVER.trunk.solid)
	assert(not BotBrain.COVER.hedge.solid and not BotBrain.COVER.grass.solid and not BotBrain.COVER.brush.solid)
end)

test("nível medido: deitado, agachado e em pé escondidos", function()
	assert(BotBrain.coverLevel(false, false, false) == 0)
	assert(BotBrain.coverLevel(true, false, false) == 1)
	assert(BotBrain.coverLevel(true, true, false) == 2)
	assert(BotBrain.coverLevel(true, true, true) == 3)
	assert(BotBrain.coverLevel(false, true, true) == 3, "parede com vão embaixo")
	assert(BotBrain.coverLevel(false, true, false) == 0)
end)

test("postura pelo abrigo: agacha atrás de dique e sebe, em pé atrás de parede e tronco", function()
	assert(BotBrain.coverStance("dike", nil, false, true, true) == "crouch")
	assert(BotBrain.coverStance("hedge", nil, false, true, true) == "crouch")
	assert(BotBrain.coverStance("sandbags", nil, false, false, false) == "crouch")
	assert(BotBrain.coverStance("wall", nil, true, true, false) == "stand")
	assert(BotBrain.coverStance("trunk", nil, false, false, false) == "stand")
	-- a medida manda: sebe de bambu alta esconde em pé
	assert(BotBrain.coverStance("hedge", 3, false, false, false) == "stand")
	-- dique baixo sob supressão: deita
	assert(BotBrain.coverStance("dike", nil, true, true, true) == "prone")
end)

test("postura sem abrigo: deita no arrozal e no capim sob fogo; na mata, agacha", function()
	assert(BotBrain.coverStance("none", 0, false, true, true) == "prone", "arrozal/capim sob fogo")
	assert(BotBrain.coverStance("none", 0, true, true, true) == "prone")
	assert(BotBrain.coverStance("none", 0, false, true, false) == "crouch", "mata sob fogo")
	assert(BotBrain.coverStance("none", 0, false, false, true) == "crouch", "sem fogo: ajoelha para atirar")
	assert(BotBrain.openGround("paddy", 3, 8))
	assert(BotBrain.openGround("grass", 1, 8), "capim com pouca coisa em volta")
	assert(not BotBrain.openGround("forest", 4, 8), "mata com troncos em volta")
	assert(not BotBrain.openGround("grass", 6, 8))
end)

test("espiar: de trás de tronco/parede sai de lado; de sacos levanta; de dique, agachado", function()
	local s, side = BotBrain.peekStance(3, "stand")
	assert(s == "stand" and side)
	s, side = BotBrain.peekStance(2, "crouch")
	assert(s == "stand" and not side)
	s, side = BotBrain.peekStance(1, "prone")
	assert(s == "crouch" and not side)
end)

test("lugar do abrigo: lado protegido em relação ao inimigo", function()
	-- bot em x=0 olhando +x; obstáculo com face em x=10 (normal -x, para o bot); inimigo em x=100
	local x, z = BotBrain.coverSpot(10, 0, -1, 0, 100, 0, 2, nil)
	assert(x == 8 and z == 0, "atrás da face, do lado do bot")
	-- inimigo do lado do bot (x=-50): sem espessura não serve; com espessura, vai para trás
	local nx = BotBrain.coverSpot(10, 0, -1, 0, -50, 0, 2, nil)
	assert(nx == nil)
	local fx = BotBrain.coverSpot(10, 0, -1, 0, -50, 0, 2, 2.1)
	assert(fx and math.abs(fx - 14.1) < 1e-9, "atrás do dique: " .. tostring(fx))
	-- chão subindo (normal quase vertical) não é abrigo
	assert(BotBrain.coverSpot(10, 0, -0.1, 0, 100, 0, 2, nil) == nil)
end)

local function cand(kind: string, level: number, o: any?): any
	local c = { kind = kind, level = level, distM = 5, enemyM = 60, progressM = 0, awayM = 0, blind = false }
	for k, v in o or {} do
		c[k] = v
	end
	return c
end

test("nota do abrigo: EUA preferem sólido; VC prefere sebe (emboscada)", function()
	local dike, hedge, wall = cand("dike", 1), cand("hedge", 2), cand("wall", 3)
	assert(BotBrain.coverScore(US, dike, false) > BotBrain.coverScore(US, hedge, false), "EUA: dique > sebe")
	assert(BotBrain.coverScore(US, wall, false) > BotBrain.coverScore(US, dike, false))
	assert(BotBrain.coverScore(VC, hedge, false) > BotBrain.coverScore(VC, dike, false), "VC: sebe > dique")
	assert(BotBrain.coverScore(VC, hedge, false) > BotBrain.coverScore(VC, wall, false), "VC: sebe > parede")
	assert(BotBrain.coverScore(US, cand("dike", 0), false) == -math.huge, "nível 0 não é abrigo")
end)

test("nota do abrigo: perto é melhor; colado no inimigo não; EUA avançam; ferido recua", function()
	assert(
		BotBrain.coverScore(US, cand("dike", 1, { distM = 2 }), false)
			> BotBrain.coverScore(US, cand("dike", 1, { distM = 14 }), false)
	)
	assert(
		BotBrain.coverScore(US, cand("wall", 3, { enemyM = 6 }), false)
			< BotBrain.coverScore(US, cand("dike", 1), false)
	)
	local fwd, back = cand("dike", 1, { progressM = 10 }), cand("dike", 1, { progressM = -10 })
	assert(
		BotBrain.coverScore(US, fwd, false) - BotBrain.coverScore(US, back, false)
			> BotBrain.coverScore(VC, fwd, false) - BotBrain.coverScore(VC, back, false),
		"EUA puxam mais para a frente"
	)
	local away, toward = cand("dike", 1, { awayM = 10 }), cand("dike", 1, { awayM = -10 })
	assert(BotBrain.coverScore(US, away, true) > BotBrain.coverScore(US, toward, true), "ferido recua")
	assert(
		BotBrain.coverScore(US, cand("wall", 3, { blind = true }), false)
			< BotBrain.coverScore(US, cand("wall", 3), false)
	)
	assert(BotBrain.shouldRetreat(D, 40) and not BotBrain.shouldRetreat(D, 80))
end)

-- ===== granada =====
local function throw(o: any?): boolean
	local g = {
		distM = 25,
		los = false,
		thrown = 0,
		now = 100,
		nextAt = 0,
		knownAgeS = 2,
		friendlyNear = false,
		pinned = false,
		roll = 0,
	}
	for k, v in o or {} do
		g[k] = v
	end
	return BotBrain.shouldThrow(D, g)
end

test("granada: 15-35 m, sem linha de visada, com recarga e no máximo 2 por vida", function()
	assert(throw(), "caso típico")
	assert(throw({ distM = 15 }) and throw({ distM = 35 }))
	assert(not throw({ distM = 12 }) and not throw({ distM = 40 }), "fora de 15-35 m")
	assert(not throw({ los = true }), "enxerga: atira, não joga")
	assert(not throw({ thrown = 2 }), "no máximo 2 por vida")
	assert(not throw({ nextAt = 120 }), "recarga")
	assert(not throw({ knownAgeS = 30 }), "posição velha")
	assert(not throw({ friendlyNear = true }), "companheiro perto do ponto")
	assert(not throw({ pinned = true }))
	assert(not throw({ roll = 0.99 }), "nem sempre joga na hora")
end)

-- ===== emboscada e orçamento =====
test("emboscada: VC segura o fogo longe, abre perto, sob fogo ou se demorar; EUA não seguram", function()
	assert(BotBrain.holdFire(VC, 150, false, 5))
	assert(not BotBrain.holdFire(VC, 60, false, 5), "perto: abre fogo")
	assert(not BotBrain.holdFire(VC, 150, true, 5), "sob fogo: responde")
	assert(not BotBrain.holdFire(VC, 150, false, 30), "contato longo: abre fogo")
	assert(not BotBrain.holdFire(US, 150, false, 5))
	assert(VC.forgetS > US.forgetS and VC.resumeS[1] > US.resumeS[2], "VC espera escondido mais tempo")
end)

test("orçamento de raios: enche no ritmo, tem teto e cabe uma busca de abrigo", function()
	assert(BotBrain.budgetStep(0, 1, D.rayRate, D.rayCap) == D.rayRate)
	assert(BotBrain.budgetStep(D.rayCap - 1, 10, D.rayRate, D.rayCap) == D.rayCap)
	assert(C.searchCost <= D.rayCap, "uma busca precisa caber no teto")
	-- 30 bots, cada um no máximo rayRate raios de abrigo por segundo
	print(string.format("       abrigo: até %d raios/s por bot, %d para 30 bots", D.rayRate, D.rayRate * 30))
	assert(D.rayRate * 30 <= 600)
	assert(C.thinkS >= 0.2 and C.thinkS <= 0.5, "pensa a cada 0,2-0,5 s")
	-- busca de 26 raios: depois dela, a próxima só ~2 s depois
	local t, tokens = 0, D.rayCap - C.searchCost
	while tokens < C.searchCost do
		tokens = BotBrain.budgetStep(tokens, C.thinkS, D.rayRate, D.rayCap)
		t += C.thinkS
	end
	assert(t >= 1.5, "buscas seguidas demais: " .. t)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
