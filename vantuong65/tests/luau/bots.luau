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
-- 2026-11-12 ("bots estão muito fortes"): reação de 0,8 a 1,4 s (era 0,4–0,8)
test("dificuldade: uma tabela (medium) com reação 0,8-1,4 s e todos os campos", function()
	assert(D.reaction[1] == 0.8 and D.reaction[2] == 1.4, "reação de nível médio")
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
test("reação: 0,8 a 1,4 s; em combate mais rápida; suprimido mais lenta", function()
	assert(math.abs(BotBrain.reactionTime(D, 0, 0, false) - 0.8) < 1e-9)
	assert(math.abs(BotBrain.reactionTime(D, 1, 0, false) - 1.4) < 1e-9)
	for i = 0, 20 do
		local t = BotBrain.reactionTime(D, i / 20, 0, false)
		assert(t >= 0.8 and t <= 1.4, "fora da faixa: " .. t)
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
-- 2026-11-12: tiro firme (mira já assentada) no tronco: bom a 50 m, fraco a 100 m, quase nada a 200 m
test("mira: tiro firme acerta razoável a 50 m (50–80%), pouco a 100 m (10–30%), quase nada a 200 m", function()
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
	assert(p50 >= 0.5 and p50 <= 0.8, "50 m: " .. p50)
	assert(p100 >= 0.1 and p100 <= 0.3, "100 m: " .. p100)
	assert(p200 <= 0.05, "200 m: " .. p200)
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
	assert(b >= D.volley.mg[1] and b <= D.volley.mg[2])
	assert(math.abs(BotBrain.shotDelay("mg", 600, true, 0.5) - 0.1) < 1e-9)
	assert(math.abs(BotBrain.shotDelay("rifle", 725, false, 0) - D.openPause.rifle[1]) < 1e-9)
end)

-- ===== rajadas =====
-- 2026-11-12: rajadas mais curtas (eram fuzil 2–3 e metralhadora 4–8)
test("rajadas curtas: fuzil 1-3 tiros, metralhadora 3-5; cadência nunca acima da arma", function()
	for i = 0, 50 do
		local r = i / 50
		local nr, nm = BotBrain.volleySize(D, "rifle", r), BotBrain.volleySize(D, "mg", r)
		assert(nr >= 1 and nr <= 3, "fuzil " .. nr)
		assert(nm >= 3 and nm <= 5, "mg " .. nm)
	end
	assert(BotBrain.volleySize(D, "mg", 0) == 3 and BotBrain.volleySize(D, "mg", 0.999) == 5)
	local m14, sks, m60 = Weapons.get("m14"), Weapons.get("sks"), Weapons.get("m60")
	assert(math.abs(BotBrain.volleyGap(D, "mg", m60.rpm, 0.5) - 60 / m60.rpm) < 1e-9, "metralhadora na cadência")
	local g = BotBrain.volleyGap(D, "rifle", m14.rpm, 0.5)
	assert(g >= D.aimedGap[1] and g <= D.aimedGap[2], "M14: tiro pensado")
	assert(BotBrain.volleyGap(D, "rifle", sks.rpm, 0) >= 60 / sks.rpm - 1e-9, "SKS não passa da cadência prática")
	local p = BotBrain.pause(D, "rifle", 0.5)
	assert(p >= 1.2 and p <= 2.4, "pausa entre rajadas")
end)

test("abrigo: VC espera mais escondido e dá mais rajadas por abrigo; ferido espera o dobro", function()
	for i = 0, 10 do
		local r = i / 10
		assert(BotBrain.hideTime(D, VC, r, false) > BotBrain.hideTime(D, US, r, false))
		assert(BotBrain.burstsPerCover(D, VC, r, false) >= BotBrain.burstsPerCover(D, US, r, false))
		assert(math.abs(BotBrain.hideTime(D, US, r, true) - 2 * BotBrain.hideTime(D, US, r, false)) < 1e-9)
	end
	-- D-107 ("mais fast paced"): 1 a 3 rajadas por abrigo (eram 2 a 4)
	assert(BotBrain.burstsPerCover(D, US, 0, false) >= 1 and BotBrain.burstsPerCover(D, US, 0.99, false) <= 3)
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

-- ===== D-90: percepção, mira que firma, disciplina =====
test("notar: de frente e perto é rápido; longe, parado e abaixado demora; de costas não vê", function()
	local t50 = BotBrain.noticeTime(D, 50, "stand", false, false, 0)
	local t200 = BotBrain.noticeTime(D, 200, "stand", false, false, 0)
	assert(t50 < t200, "longe demora mais")
	assert(BotBrain.noticeTime(D, 50, "crouch", true, false, 0) > t50, "parado e agachado demora mais")
	assert(BotBrain.noticeTime(D, 50, "stand", false, false, 90) > t50, "de lado demora mais")
	assert(BotBrain.noticeTime(D, 50, "stand", false, false, 170) == math.huge, "de costas não vê")
	assert(BotBrain.noticeTime(D, 50, "stand", false, true, 170) < math.huge, "atirando: ouve e vê")
	assert(BotBrain.noticeTime(D, 50, "stand", false, true, 0) < t50, "o clarão denuncia")
	print(string.format("       notar: 50 m %.2f s, 200 m %.2f s", t50, t200))
end)

test("mira que firma: o 1º tiro num alvo novo é apressado; firma em settleS", function()
	assert(BotBrain.settleFactor(D, 0) == D.settleMult)
	assert(BotBrain.settleFactor(D, D.settleS) == 1 and BotBrain.settleFactor(D, 10) == 1)
	assert(BotBrain.settleFactor(D, D.settleS / 2) < D.settleMult and BotBrain.settleFactor(D, D.settleS / 2) > 1)
	-- 1 x 1 a 50 m, de frente: tempo até o 1º acerto do bot (Monte Carlo com as próprias regras)
	local Rng = require("../../src/ReplicatedStorage/Shared/Rng") :: any
	local rng = Rng.new(1965)
	local function firstHit(distM: number): number
		local notice = BotBrain.noticeTime(D, distM, "stand", false, false, 0)
		local t = notice + BotBrain.reactionTime(D, rng:next(), 0, false)
		local track = t - notice
		for _ = 1, 40 do
			local n = BotBrain.volleySize(D, "rifle", rng:next())
			for shot = 1, n do
				local s = BotBrain.aimError(D, distM, { shot = shot, kind = "rifle" }) * BotBrain.settleFactor(D, track)
				if rng:next() < BotBrain.hitChance(s, distM, C.torsoHalfM) then
					return t
				end
				local gap = BotBrain.volleyGap(D, "rifle", 725, rng:next())
				t += gap
				track += gap
			end
			local p = BotBrain.pause(D, "rifle", rng:next())
			t += p
			track += p
		end
		return t
	end
	local function median(distM: number): number
		local xs = {}
		for k = 1, 2001 do
			xs[k] = firstHit(distM)
		end
		table.sort(xs)
		return xs[1001]
	end
	local m50, m100 = median(50), median(100)
	print(
		string.format(
			"       bot de frente, em pé: 1º acerto (mediana) a 50 m em %.2f s, a 100 m em %.2f s",
			m50,
			m100
		)
	)
	-- piso de projeto (PLACEHOLDER): o jogador que vê primeiro tem mais de 1 s a 50 m
	assert(m50 >= 1.0, "bot rápido demais a 50 m: " .. m50)
	assert(m100 > m50)
end)

test("disciplina: não atira além do alcance; granada atrás do dique mesmo vendo a cabeça", function()
	-- 2026-11-12: fuzil até 180 m e metralhadora até 250 m (eram 320 e 450; a visão vai a 120 m)
	assert(BotBrain.inRange(D, "rifle", 170) and not BotBrain.inRange(D, "rifle", 200))
	assert(
		not BotBrain.inRange(D, "pistol", 80) and BotBrain.inRange(D, "mg", 240) and not BotBrain.inRange(D, "mg", 260)
	)
	assert(not throw({ los = true }), "vendo sem abrigo: atira")
	assert(throw({ los = true, covered = true }), "vendo, mas atrás do dique: granada")
	-- ponto de mira passa do abrigo e cai do lado dele
	local ax, az = BotBrain.grenadeAim(0, 0, 0.5, 0, 2)
	assert(ax == 2 and az == 0, "passa do dique")
	local bx = BotBrain.grenadeAim(0, 0, 5, 0, 2)
	assert(bx == 5, "longe do dique: no inimigo")
	-- não cai no próprio squad (nem em quem vai para lá)
	assert(BotBrain.grenadeClear(0, 0, { 20, 0, 0, 20 }, 8))
	assert(not BotBrain.grenadeClear(0, 0, { 20, 0, 5, 5 }, 8))
end)

test("túnel: vale entrar quando a saída ganha caminho; blindado: um a partir de 8 bots", function()
	local T = BotBrain.TUNNEL
	assert(BotBrain.tunnelWorth(30, 300, 150))
	assert(not BotBrain.tunnelWorth(30, 300, 260), "ganho pequeno")
	assert(not BotBrain.tunnelWorth(T.useWithinM + 1, 300, 100), "entrada longe")
	assert(BotBrain.crewCount(7, 3) == 0 and BotBrain.crewCount(8, 3) == 1)
	assert(BotBrain.crewCount(15, 3) == 2 and BotBrain.crewCount(30, 3) == 3 and BotBrain.crewCount(30, 1) == 1)
end)

-- ===== 2026-11-12: bots menos fortes, visão curta e avanço =====
-- A tabela da v36 (antes), só os campos que mudaram; o resto é o de hoje.
local V36 = table.clone(D)
V36.reaction, V36.alertedReaction, V36.suppReactionS = { 0.4, 0.8 }, 0.7, 0.5
V36.spotStance = { stand = 1, crouch = 0.75, prone = 0.5 }
V36.aimBaseRad, V36.aimRangeM, V36.aimSuppression = 0.0022, 500, 2.0
V36.recoilRad = { rifle = 0.0008, mg = 0.0015, pistol = 0.002, launcher = 0 }
V36.recoilMaxRad = 0.006
V36.volley = { rifle = { 2, 3 }, mg = { 4, 8 }, pistol = { 1, 2 }, launcher = { 1, 1 } }
V36.aimedGap = { 0.35, 0.7 }
V36.openPause = { rifle = { 0.8, 1.7 }, mg = { 0.6, 1.4 }, pistol = { 0.5, 1.1 }, launcher = { 3, 5 } }
V36.noticeS, V36.noticePer100M, V36.noticeStill, V36.noticeSide = 0.25, 0.35, 1.8, 2.2
V36.fovDeg, V36.rearDeg, V36.settleS, V36.settleMult = 60, 125, 1.5, 3.0
V36.fireMaxM = { rifle = 320, mg = 450, pistol = 50, launcher = 0 }

test("duelo: chance de o bot acertar um jogador parado em 3 s, antes (v36) e depois", function()
	local Rng = require("../../src/ReplicatedStorage/Shared/Rng") :: any
	local m14 = Weapons.get("m14")
	local function chance(diff: any, distM: number, sightM: number): number
		local rng = Rng.new(1965)
		return BotBrain.duelHitChance(diff, distM, 3, "rifle", m14.rpm, sightM, 4000, function()
			return rng:next()
		end)
	end
	local sightNow = BotBrain.sightRange(D, "open", "stand", false, nil, false)
	local rows = {}
	for _, dist in { 50, 100, 200 } do
		local before = chance(V36, dist, 300) -- v36: notava a até 300 m em qualquer lugar
		local after = chance(D, dist, sightNow)
		table.insert(rows, string.format("%d m: %.0f%% -> %.0f%%", dist, before * 100, after * 100))
		assert(after < before, string.format("%d m não ficou mais fraco", dist))
		if dist == 50 then
			assert(after >= 0.15 and after <= 0.6, "50 m fora do nível médio: " .. after)
		elseif dist == 100 then
			assert(after <= 0.2, "100 m forte demais: " .. after)
		else
			assert(after == 0, "200 m: além do que o bot nota no aberto")
		end
	end
	print("       jogador parado, em pé, no aberto, 3 s de exposição (fuzil): " .. table.concat(rows, "; "))
end)

test("visão: 120 m no aberto, 40 m na mata, 15 m no capim; abaixado e camuflado mais perto", function()
	assert(BotBrain.sightRange(D, "open", "stand", false, nil, false) == 120)
	assert(BotBrain.sightRange(D, "rice", "stand", false, nil, false) == 120)
	assert(BotBrain.sightRange(D, "jungle", "stand", false, nil, false) == 40)
	assert(BotBrain.sightRange(D, "bamboo", "stand", false, nil, false) == 40)
	assert(BotBrain.sightRange(D, "grass", "stand", false, nil, false) == 15)
	assert(BotBrain.sightRange(D, "open", "crouch", false, nil, false) < 120)
	assert(
		BotBrain.sightRange(D, "open", "prone", false, nil, false)
			< BotBrain.sightRange(D, "open", "crouch", false, nil, false)
	)
	assert(BotBrain.sightRange(D, "jungle", "stand", false, "jungle", false) < 40, "camuflagem da mata na mata")
	assert(BotBrain.sightRange(D, "jungle", "stand", false, nil, true) == 60, "atirando: 1,5x")
	assert(BotBrain.sightRange(D, "jungle", "stand", true, nil, false) == 60, "seguido: 1,5x")
	assert(BotBrain.sightRange(D, "open", "stand", true, nil, false) == 120, "seguido não passa do teto")
	assert(C.senseRangeM == 120)
	-- notar: mais longe, na vegetação e parado abaixado demora mais; cone mais estreito
	local base = BotBrain.noticeTime(D, 40, "stand", false, false, 0, "open")
	assert(BotBrain.noticeTime(D, 40, "stand", false, false, 0, "jungle") > base)
	assert(
		BotBrain.noticeTime(D, 40, "stand", false, false, 0, "grass")
			> BotBrain.noticeTime(D, 40, "stand", false, false, 0, "jungle")
	)
	assert(
		BotBrain.noticeTime(D, 40, "prone", true, false, 0, "open")
			> BotBrain.noticeTime(D, 40, "prone", false, false, 0, "open")
	)
	assert(BotBrain.noticeTime(D, 40, "stand", false, false, 110, "open") == math.huge, "além de 100° não vê")
	print(
		string.format(
			"       notar em pé no aberto: 50 m %.2f s (v36 %.2f), 100 m %.2f s (v36 %.2f); deitado parado na mata a 30 m %.2f s",
			BotBrain.noticeTime(D, 50, "stand", false, false, 0, "open"),
			BotBrain.noticeTime(V36, 50, "stand", false, false, 0),
			BotBrain.noticeTime(D, 100, "stand", false, false, 0, "open"),
			BotBrain.noticeTime(V36, 100, "stand", false, false, 0),
			BotBrain.noticeTime(D, 30, "prone", true, false, 0, "jungle")
		)
	)
end)

test("mira no tronco em qualquer postura (nada de cabeça em série)", function()
	for _, st in { "stand", "crouch", "prone" } do
		assert(BotBrain.aimPartName(st) == "UpperTorso", st)
	end
	-- chance de um tiro firme a 50 m cair na cabeça (caixa de 0,24 m, centro 0,55 m acima do ponto
	-- mirado) de quem está agachado: antes o bot mirava na cabeça
	local s = BotBrain.aimError(D, 50)
	local lin = s * 50
	local function erf(x: number): number
		local t = 1 / (1 + 0.3275911 * math.abs(x))
		local y = 1
			- (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592)
				* t
				* math.exp(-x * x)
		return if x >= 0 then y else -y
	end
	local function band(lo: number, hi: number): number
		return 0.5 * (erf(hi / (lin * math.sqrt(2))) - erf(lo / (lin * math.sqrt(2))))
	end
	local headNow = band(-0.12, 0.12) * band(0.55 - 0.12, 0.55 + 0.12)
	local headV36 = BotBrain.hitChance(BotBrain.aimError(V36, 50), 50, 0.12)
	print(
		string.format(
			"       tiro na cabeça de quem está agachado a 50 m: %.0f%% (v36) -> %.0f%%",
			headV36 * 100,
			headNow * 100
		)
	)
	assert(headNow < headV36 / 4)
end)

test("avançar: atacante sem alvo nem fogo volta a andar; defensor fica; parado tem limite", function()
	assert(BotBrain.shouldPress(true, false, false, false, 5), "atacante calmo há 5 s avança")
	assert(not BotBrain.shouldPress(true, false, false, false, 2), "espera um pouco")
	assert(not BotBrain.shouldPress(true, true, false, false, 9), "vendo alguém, luta")
	assert(not BotBrain.shouldPress(true, false, true, false, 9), "sob fogo, abriga")
	assert(not BotBrain.shouldPress(false, false, false, false, 9), "defensor fica no ponto")
	assert(not BotBrain.shouldPress(true, false, false, true, 9), "ferido recua")
	-- D-107: parado sem contato fora do ponto, no máximo 10 s (era 20)
	assert(BotBrain.idleExpired(11, false, false) and not BotBrain.idleExpired(11, false, true))
	assert(not BotBrain.idleExpired(21, true, false) and not BotBrain.idleExpired(8, false, false))
	assert(BotBrain.squadBounds(true, 120, 10) and not BotBrain.squadBounds(true, 200, 10))
	assert(not BotBrain.squadBounds(true, 120, 60) and not BotBrain.squadBounds(false, 120, 10))
	-- menos tempo parado depois do contato (v36: EUA 2–5 s, VC 20–40 s)
	assert(US.resumeS[2] <= 3 and VC.resumeS[2] <= 8 and VC.forgetS <= 10)
	assert(BotBrain.SQUAD.leaderWaitMaxS <= 10)
	-- aproximação dos últimos 125 m (da reunião avançada ao ponto), sem contato: trota até walkCalmM
	-- do objetivo e anda o resto (v36: andava os últimos 120 m)
	local Movement = require(S .. "Movement") :: any
	local function approach(walkM: number): number
		local walk = math.min(walkM, 125)
		return (125 - walk) / Movement.JOG + walk / Movement.WALK
	end
	local before, after = approach(120), approach(BotBrain.MOVE.walkCalmM)
	-- e com contato recente, em lances: trota boundS e para boundPauseS (média)
	local Sq = BotBrain.SQUAD
	local mv, ps = (Sq.boundS[1] + Sq.boundS[2]) / 2, (Sq.boundPauseS[1] + Sq.boundPauseS[2]) / 2
	local bounds = 125 / (Movement.JOG * mv / (mv + ps))
	print(
		string.format(
			"       últimos 125 m até o ponto: %.0f s (v36) -> %.0f s; em lances com contato: %.0f s",
			before,
			after,
			bounds
		)
	)
	assert(after < before)
end)

-- ===== 2026-11-12: bots completam o squad do jogador (decisão do dono) =====
test("squad de jogador: com menos de 4, recebe bots até 4, um por vez, sem passar do tamanho", function()
	local F = BotBrain.FILL
	assert(F.target == 4)
	-- 1 humano num squad de infantaria (6): 3 bots, um a cada conferida, na ordem dos livres
	local sq = { id = "US:Alfa", humans = 1, size = 6, bots = {} }
	local free = { 11, 12, 13, 14 }
	for tick = 1, 5 do
		local add, remove = BotBrain.fillPlan({ sq }, free)
		assert(#remove == 0, "tirou na conferida " .. tick)
		if tick <= 3 then
			assert(#add == 1 and add[1].squad == "US:Alfa", "um por vez")
			table.insert(sq.bots, add[1].bot)
			table.remove(free, table.find(free, add[1].bot) :: number)
		else
			assert(#add == 0, "passou de 4 membros")
		end
	end
	assert(#sq.bots == 3 and sq.bots[1] == 11, "1 humano + 3 bots, o primeiro livre entra antes")
	-- entram humanos: os bots saem um a um
	sq.humans = 3
	local _, rm = BotBrain.fillPlan({ sq }, free)
	assert(#rm == 1, "sai um por vez")
	sq.bots = { 11 }
	_, rm = BotBrain.fillPlan({ sq }, free)
	assert(#rm == 0, "3 humanos + 1 bot = 4")
	sq.humans = 4
	_, rm = BotBrain.fillPlan({ sq }, free)
	assert(#rm == 1 and rm[1] == 11, "com 4 humanos, nenhum bot")
	-- squad pequeno (recon, 2): nunca passa do tamanho
	local recon = { id = "US:Recon", humans = 1, size = 2, bots = { 20 } }
	local add2 = BotBrain.fillPlan({ recon }, { 21 })
	assert(#add2 == 0, "recon de 2 já está cheio")
	-- sem humano: não recebe; sem bot livre: não inventa bot (BotFill não cresce)
	local empty = { id = "US:Bravo", humans = 0, size = 6, bots = {} }
	assert(#BotBrain.fillPlan({ empty }, { 30 }) == 0)
	local a, b = { id = "A", humans = 1, size = 6, bots = {} }, { id = "B", humans = 1, size = 6, bots = {} }
	local add3 = BotBrain.fillPlan({ a, b }, { 40 })
	assert(#add3 == 1, "um bot livre só vai para um squad")
end)

-- D-107 ("bots não precisam seguir o líder"): sem leque atrás do humano; a marca dele é ordem com prazo
test("squad de jogador: não segue mais o líder; a marca vale 2 min e 45 s depois de chegar", function()
	local F = BotBrain.FILL
	assert(BotBrain.escortSlot == nil and BotBrain.escortHold == nil, "o leque atrás do líder humano saiu")
	assert(F.markTtlS == 120 and F.markHoldS == 45)
	assert(BotBrain.markActive(10, nil), "marca nova manda")
	assert(BotBrain.markActive(F.markTtlS - 1, nil), "ainda indo para ela")
	assert(not BotBrain.markActive(F.markTtlS + 1, nil), "marca velha")
	assert(BotBrain.markActive(30, 20), "chegou há 20 s: fica")
	assert(not BotBrain.markActive(80, F.markHoldS + 1), "chegou há mais de 45 s: volta ao objetivo")
end)

-- ===== D-107: 50 por lado (D-114: 40), desempenho, papel na frente e lance de assalto =====
test("lotação: completa até 30 por lado menos os humanos, 2 por vez; sai na hora", function()
	local K = BotBrain.CROWD
	local Roles = require("../../src/ReplicatedStorage/Shared/Roles") :: any
	assert(K.perSide == 30 and Roles.TEAM_MAX == 30, "30 por lado (Roles.TEAM_MAX, D-122)")
	assert(BotBrain.fillWant(50, 0, 50, 50) == 50, "sem humano: 50 bots")
	assert(BotBrain.fillWant(50, 3, 50, 50) == 47, "3 humanos: 47 bots")
	assert(BotBrain.fillWant(50, 60, 50, 50) == 0, "time cheio de humanos: nenhum")
	assert(BotBrain.fillWant(50, 3, 50, 30) == 30, "o teto pelo desempenho manda")
	assert(BotBrain.fillWant(10, 0, 50, 50) == 10, "BotFill menor vale")
	assert(BotBrain.fillStep(0, 50, K.addPerStep) == 2, "entram 2 por vez")
	assert(BotBrain.fillStep(49, 50, K.addPerStep) == 1)
	assert(BotBrain.fillStep(50, 47, K.addPerStep) == -3, "entrou gente: saem na hora")
	-- tempo para encher os dois lados (as duas filas andam juntas)
	local have, t = 0, 0
	while have < 50 do
		have += BotBrain.fillStep(have, 50, K.addPerStep)
		t += K.stepS
	end
	print(
		string.format("       lotação: 50 por lado em %.0f s (%d por lado a cada %.0f s)", t, K.addPerStep, K.stepS)
	)
	assert(t <= 30, "demora demais para encher: " .. t)
end)

test("teto pelo Heartbeat: para abaixo de 45 Hz, tira abaixo de 35 Hz, volta acima de 52 Hz", function()
	local K = BotBrain.CROWD
	local c = BotBrain.newCrowd()
	assert(c.cap == K.perSide)
	assert(BotBrain.crowdStep(c, 60, 1, 20) == "add", "servidor folgado: entra gente")
	-- 45 Hz > x >= 35 Hz: o teto para onde está
	assert(BotBrain.crowdStep(c, 40, 1, 30) == "hold" and c.cap == 30, "parou em 30")
	-- abaixo de 35 Hz por dropS: sai dropStep
	local out = ""
	for _ = 1, K.dropS do
		out = BotBrain.crowdStep(c, 30, 1, 30)
	end
	assert(out == "drop" and c.cap == 30 - K.dropStep, "tirou " .. K.dropStep .. ": " .. c.cap)
	-- muito tempo ruim: nunca abaixo de minPerSide
	for _ = 1, 200 do
		BotBrain.crowdStep(c, 20, 1, c.cap)
	end
	assert(c.cap == K.minPerSide, "piso de " .. K.minPerSide)
	-- volta a subir devagar com o servidor folgado
	local t = 0
	while c.cap < K.perSide do
		BotBrain.crowdStep(c, 60, 1, c.cap)
		t += 1
	end
	print(string.format("       teto: de %d a %d por lado em %d s com o servidor a 60 Hz", K.minPerSide, K.perSide, t))
	-- oscilação entre 45 e 52 Hz não sobe nem desce
	local before = c.cap
	for i = 1, 30 do
		BotBrain.crowdStep(c, if i % 2 == 0 then 46 else 51, 1, c.cap)
	end
	assert(c.cap == before)
end)

test("nível de detalhe: 100 bots cabem no orçamento (pensamentos, passos, raios de visada)", function()
	local L, B = BotBrain.LOD, BotBrain.BUDGET
	assert(BotBrain.lodLevel(50) == 1 and BotBrain.lodLevel(200) == 2 and BotBrain.lodLevel(400) == 3)
	assert(BotBrain.lodLevel(math.huge) == 3, "sem humano em campo: longe")
	assert(L.thinkS[1] == C.thinkS, "perto de humano, pensa como antes")
	-- sem nível de detalhe (antes): 100 bots pensando a cada 0,3 s e com as pernas a cada quadro
	local before = { thinks = 100 / C.thinkS, steps = 100 * 60, los = 100 / C.thinkS * C.maxLosChecks }
	local worst = BotBrain.botLoad({ 100, 0, 0 }) -- todos perto de humanos
	local typical = BotBrain.botLoad({ 15, 25, 60 }) -- alguns humanos perto da frente
	local solo = BotBrain.botLoad({ 8, 12, 80 }) -- um humano
	local function row(name: string, l: any): string
		return string.format(
			"%s %.0f pens./s (%.1f por quadro), %.0f passos/s, %.0f raios/s",
			name,
			l.thinks,
			l.thinks / 60,
			l.steps,
			l.los
		)
	end
	print("       " .. row("antes:", before))
	print("       " .. row("todos perto:", worst))
	print("       " .. row("típico 15/25/60:", typical))
	print("       " .. row("1 humano 8/12/80:", solo))
	assert(math.abs(worst.thinks - before.thinks) < 1e-6, "perto de humano, nada muda")
	assert(worst.thinks / 60 <= B.maxPerFrame, "pior caso cabe no teto de pensamentos por quadro")
	assert(typical.thinks <= before.thinks * 0.6 and typical.steps <= before.steps * 0.6, "típico: 40% a menos")
	assert(solo.thinks <= before.thinks * 0.45 and solo.los <= before.los * 0.35)
	-- PathfindingService: teto do servidor todo (antes não tinha teto por segundo)
	assert(B.pathPerS <= 10 and BotBrain.MOVE.pathConcurrent <= 2)
end)

test("papel na frente: a maioria ataca, uma parte guarda; com inimigo no ponto, contra-ataque", function()
	local ALL = { true, true, true, true, true }
	local INIT = { "VC", "VC", "Neutral", "US", "US" }
	-- início: os dois atacam o S3 neutro; ninguém tem setor ameaçado
	assert(BotBrain.defendSector(INIT, ALL, "US") == nil and BotBrain.defendSector(INIT, ALL, "VC") == nil)
	-- EUA tomaram o S3: os EUA atacam o S2 e guardam o S3; o VC ataca o S3 e guarda o S2
	local after = { "VC", "VC", "US", "US", "US" }
	assert(BotBrain.objective(after, ALL, "US") == 2 and BotBrain.defendSector(after, ALL, "US") == 3)
	assert(BotBrain.objective(after, ALL, "VC") == 3 and BotBrain.defendSector(after, ALL, "VC") == 2)
	-- Offensive: o VC só guarda o S4
	local off = { "VC", "VC", "VC", "VC", "US" }
	local act = { false, false, false, true, false }
	local vcA, vcD = BotBrain.objective(off, act, "VC"), BotBrain.defendSector(off, act, "VC")
	assert(vcD == 4 and BotBrain.squadSector(vcA, vcD, false, 0.9) == 4)
	-- divisão pelos squads (roll fixo de cada squad: id x 0,618 mod 1)
	local function share(threatened: boolean): number
		local def = 0
		for id = 1, 16 do
			local _, attack = BotBrain.squadSector(2, 3, threatened, (id * 0.618034) % 1)
			if not attack then
				def += 1
			end
		end
		return def / 16
	end
	local calmShare, hotShare = share(false), share(true)
	print(
		string.format("       16 squads: %.0f%% guardam; com inimigo no ponto, %.0f%%", calmShare * 100, hotShare * 100)
	)
	assert(math.abs(calmShare - BotBrain.TASK.defendShare) <= 0.07)
	assert(math.abs(hotShare - BotBrain.TASK.counterShare) <= 0.07)
	-- sem setor ameaçado, todos atacam; sem ataque, todos guardam
	assert(select(2, BotBrain.squadSector(2, nil, true, 0.1)) == true)
	assert(BotBrain.squadSector(nil, 3, false, 0.9) == 3)
end)

test("lance de assalto: a equipe da vez avança em vez de trocar tiro de longe ou ficar presa", function()
	local P = BotBrain.PUSH
	local function ctx(o: any?): any
		local c = {
			attacking = true,
			myBound = true,
			ready = true,
			wounded = false,
			targetM = nil,
			toPointM = 150,
			zoneM = 50,
			pinnedS = 0,
			stillS = 0,
		}
		for k, v in o or {} do
			c[k] = v
		end
		return c
	end
	assert(BotBrain.shouldRush(ctx()), "sem alvo à vista: avança")
	assert(BotBrain.shouldRush(ctx({ targetM = 120 })), "alvo a 120 m (bot acerta ~4%): avança")
	assert(not BotBrain.shouldRush(ctx({ targetM = 60 })), "alvo a 60 m: luta um pouco")
	assert(BotBrain.shouldRush(ctx({ targetM = 60, stillS = P.coverMaxS })), "...e avança depois de coverMaxS")
	assert(not BotBrain.shouldRush(ctx({ targetM = 20, stillS = 30 })), "alvo perto: luta onde está")
	assert(not BotBrain.shouldRush(ctx({ myBound = false })), "a outra equipe cobre")
	assert(BotBrain.shouldRush(ctx({ myBound = false, stillS = P.coverHardMaxS })), "ninguém fica para sempre")
	assert(BotBrain.shouldRush(ctx({ myBound = false, pinnedS = P.pinnedMaxS })), "preso demais: levanta e vai")
	assert(not BotBrain.shouldRush(ctx({ attacking = false })), "quem guarda fica")
	assert(not BotBrain.shouldRush(ctx({ wounded = true })), "ferido recua")
	assert(not BotBrain.shouldRush(ctx({ ready = false })), "descansa entre lances")
	assert(not BotBrain.shouldRush(ctx({ toPointM = 25 })), "dentro do ponto: fica e luta")
	-- ritmo sob fogo: cada equipe avança boundM a cada 2 lances do squad
	local Movement = require(S .. "Movement") :: any
	local Sq = BotBrain.SQUAD
	local bound = (P.boundM[1] + P.boundM[2]) / 2
	local window = (Sq.boundS[1] + Sq.boundS[2]) / 2
	local pace = bound / (2 * window)
	print(
		string.format(
			"       sob fogo: lance de %.0f m em %.1f s correndo; o squad anda ~%.1f m/s; 150 m em ~%.0f s",
			bound,
			bound / Movement.SPRINT,
			pace,
			150 / pace
		)
	)
	assert(bound / Movement.SPRINT <= P.rushMaxS, "o lance cabe no tempo máximo")
	assert(150 / pace <= 180, "150 m sob fogo em até 3 min")
end)

test("primeiro tiroteio em até 3 min no Warfare (estimativa com o mapa real)", function()
	local MapConfig = require(S .. "MapConfig") :: any
	local Front = require(S .. "Front") :: any
	local Geometry = require(S .. "Geometry") :: any
	local Movement = require(S .. "Movement") :: any
	local M = MapConfig.STUD_M
	local function sectorAt(x: number, z: number): number?
		return Geometry.sectorAt(MapConfig.Sectors, x, z)
	end
	local by: { [number]: { any } } = {}
	for _, sp in MapConfig.Strongpoints do
		by[sp.sector] = by[sp.sector] or {}
		table.insert(by[sp.sector], sp)
	end
	-- terreno pronto no Studio (D-101: 29 s); o 1º squad de cada lado entra em 3 s (2 por segundo)
	local TERRAIN_S = 29
	local entryS = 6 / BotBrain.CROWD.addPerStep * BotBrain.CROWD.stepS
	local zoneM = MapConfig.CaptureRadiusStuds * M
	local worst = 0
	-- D-123: o setor do meio (o 2 no mapa de 3 setores; era o 3 de 5), atacado dos dois vizinhos
	local mid = math.ceil(#MapConfig.Sectors / 2)
	for _, t in by[mid] do
		local slow = 0
		for _, pair in { { own = mid - 1 }, { own = mid + 1 } } do
			local best = math.huge
			for _, own in by[pair.own] do
				local x, z = Front.forwardRally(pair.own, own, t, M, sectorAt, MapConfig.Bounds)
				if x and z then
					best = math.min(best, math.sqrt((x - t.x) ^ 2 + (z - t.z) ^ 2) * M)
				end
			end
			-- o squad trota até a borda do ponto (a visão é de 40 m na mata a 120 m no aberto: o contato
			-- vem antes disso quando os dois chegam juntos)
			slow = math.max(slow, (best - zoneM) / Movement.JOG)
		end
		worst = math.max(worst, TERRAIN_S + entryS + slow)
	end
	print(string.format("       pior caso: %.0f s de partida até os dois lados na borda do S%d", worst, mid))
	assert(worst <= 180, string.format("primeiro contato estimado em %.0f s", worst))
end)

test("soldado de 2 m: olhos do abrigo levados pelo Corpo.K", function()
	local Corpo = require(S .. "Corpo") :: any
	local old = { 0.35, 1.0, 1.6 }
	for i = 1, 3 do
		assert(math.abs(C.probeM[i] - old[i] * Corpo.K) < 1e-9, "probe " .. i)
	end
	assert(math.abs(C.probeM[3] - 1.829) < 0.01, "olho em pé ~1,83 m")
end)

-- v41 ("copie exatamente os bots do Front 44"): os números do Config.Bots e do Bots.luau de lá
test("v41: combate do Front 44 (visão, reação, mira, rajadas, movimento) com os números de lá", function()
	local F = BotBrain.F44
	assert(F.on == true, "ligado")
	assert(F.STUD_M == 0.28 and F.sightStuds == 160 and F.coneDeg == 130 and F.nearStuds == 22)
	assert(F.reactionS == 0.45 and F.reactionK[1] == 0.8 and F.reactionK[2] == 1.3)
	assert(F.aimStartDeg == 4.5 and F.aimEndDeg == 1.1 and F.aimSettleS == 1.2 and F.aimPerStudDeg == 0.008)
	assert(F.headChance == 0.18 and F.leadK == 0.85 and F.aimMovingK == 1.5)
	assert(F.burst[1] == 3 and F.burst[2] == 7 and F.burstPauseS[1] == 0.25 and F.burstPauseS[2] == 0.7)
	assert(F.strafeStuds == 9 and F.farStuds == 70 and F.retreatHealth == 0.35 and F.retreatS == 3.5)
	assert(F.investigateS == 8 and F.hearStuds == 110 and F.grenadeChance == 0.25 and F.grenadeEveryS == 12)
	-- visão: 160 studs (44,8 m) ou menos, se a vegetação tapa antes
	assert(math.abs(BotBrain.f44SightM(120) - 44.8) < 1e-9 and BotBrain.f44SightM(15) == 15)
	assert(BotBrain.f44Sees(64, 40) and not BotBrain.f44Sees(70, 40) and BotBrain.f44Sees(170, 6))
	-- reação 0,36–0,585 s; mira 4,5° → 1,1° em 1,2 s, +0,008° por stud
	assert(math.abs(BotBrain.f44Reaction(0) - 0.36) < 1e-9 and math.abs(BotBrain.f44Reaction(1) - 0.585) < 1e-9)
	assert(math.abs(BotBrain.f44AimDeg(0, false, 0) - 4.5) < 1e-9)
	assert(math.abs(BotBrain.f44AimDeg(5, false, 28) - (1.1 + 0.8)) < 1e-9, "100 studs: +0,8°")
	assert(math.abs(BotBrain.f44AimDeg(5, true, 0) - 1.65) < 1e-9, "andando ×1,5")
	-- rajadas 3–7 na automática; tiro a tiro no resto; pausa
	for _, r in { 0, 0.3, 0.6, 0.99 } do
		local b = BotBrain.f44Burst(true, r)
		assert(b >= 3 and b <= 7, "rajada " .. b)
		assert(BotBrain.f44Burst(false, r) == 1)
	end
	assert(BotBrain.f44Pause(false, 1.5, 0) == 1.5, "ferrolho: a cadência manda")
	assert(math.abs(BotBrain.f44Pause(true, 0.1, 1) - 0.7) < 1e-9)
	assert(
		BotBrain.f44TooFar("shotgun", 12)
			and not BotBrain.f44TooFar("shotgun", 10)
			and not BotBrain.f44TooFar("rifle", 44)
	)
	-- disco dentro do quadrado: perto, tudo; longe, área ÷ área
	assert(BotBrain.f44ShotChance(1.1, 5, 0.25) == 1)
	local far = BotBrain.f44ShotChance(2, 40, 0.25)
	assert(far > 0 and far < 0.2, "40 m: " .. far)
	-- medida (sem número inventado): chance de acertar ao menos 1 vez um jogador parado em 3 s
	local seed = 1
	local function roll(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local line = {}
	for _, dm in { 10, 25, 40, 50 } do
		local auto = BotBrain.f44DuelHitChance(dm, 3, true, 600, 2000, roll)
		local semi = BotBrain.f44DuelHitChance(dm, 3, false, 600, 2000, roll)
		table.insert(line, string.format("%d m: auto %.0f%%, semi %.0f%%", dm, auto * 100, semi * 100))
		if dm == 50 then
			assert(auto == 0 and semi == 0, "além de 44,8 m não vê")
		end
	end
	print("       Front 44 em 3 s: " .. table.concat(line, "; "))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
