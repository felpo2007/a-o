--!strict
-- Testes do modo de jogo, da carta tática e da tela de baixa (pedido do dono, 2026-11-11).
-- Uso: lune run tests/luau/modo.luau
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Capture = require(S .. "Capture") :: any
local Offensive = require(S .. "Offensive") :: any
local Front = require(S .. "Front") :: any
local Casualty = require(S .. "Casualty") :: any
local Carta = require(S .. "Carta") :: any
local Geometry = require(S .. "Geometry") :: any
local SpawnRules = require(S .. "SpawnRules") :: any
local BotBrain = require(S .. "BotBrain") :: any
local Rng = require(S .. "Rng") :: any
local MapConfig = require(S .. "MapConfig") :: any

local M = MapConfig.STUD_M
local JOG = 3.1 -- m/s (Units.Speed.jog)

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
local function near(a: number, b: number, tol: number, msg: string?)
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f (tol %.4f)", msg or "", a, b, tol))
end

local INIT = { "VC", "VC", "Neutral", "US", "US" }
local ALL = { true, true, true, true, true }

local function at(sector: number, us: number, vc: number): { { US: number, VC: number } }
	local c = {}
	for i = 1, 5 do
		c[i] = { US = 0, VC = 0 }
	end
	c[sector] = { US = us, VC = vc }
	return c
end

-- ===== atrito =====
test("atrito: começa com os reforços de projeto; morte gasta 1 e nunca passa de zero", function()
	local sc = Capture.newScore()
	assert(sc.US == Capture.C.reinforcements and sc.VC == Capture.C.reinforcements)
	Capture.casualty(sc, "US")
	assert(sc.US == Capture.C.reinforcements - 1 and sc.VC == Capture.C.reinforcements)
	local z = Capture.newScore(1)
	Capture.casualty(z, "VC")
	Capture.casualty(z, "VC")
	assert(z.VC == 0)
end)

test("atrito: setor de vantagem sangra bleedPerMinute por minuto; empate em setores não sangra", function()
	local st = Capture.new(INIT)
	local sc = Capture.newScore()
	for _ = 1, 60 do
		assert(Capture.bleed(sc, st, 1) == nil)
	end
	assert(sc.US == sc.VC)
	st.owner[3] = "US" -- EUA com 3 setores contra 2
	for _ = 1, 60 do
		Capture.bleed(sc, st, 1)
	end
	assert(sc.VC == Capture.C.reinforcements - Capture.C.bleedPerMinute, "VC sangrou " .. sc.VC)
	assert(sc.US == Capture.C.reinforcements)
	st.owner[2] = "US" -- 4 contra 1: vantagem de 3
	for _ = 1, 60 do
		Capture.bleed(sc, st, 1)
	end
	assert(sc.VC == Capture.C.reinforcements - 4 * Capture.C.bleedPerMinute, "VC " .. sc.VC)
	-- medido: com 4 x 1 desde o início, quanto tempo até zerar
	local min = Capture.C.reinforcements / (3 * Capture.C.bleedPerMinute)
	print(
		string.format(
			"       (4 setores x 1: reforços de %d zeram em %.0f min só pela sangria)",
			Capture.C.reinforcements,
			min
		)
	)
end)

test("atrito: reforço zerado perde na hora; fim do tempo empatado em setores vai para mais reforços", function()
	local st = Capture.new(INIT)
	local sc = Capture.newScore(5)
	sc.VC = 0
	assert(Capture.winner(st, 10, 4500, sc) == "US")
	local sc2 = Capture.newScore(50)
	sc2.US = 40
	assert(Capture.winner(st, 4500, 4500, sc2) == "VC")
	assert(Capture.winner(st, 4499, 4500, sc2) == nil)
	sc2.US = 50
	assert(Capture.winner(st, 4500, 4500, sc2) == "draw")
	-- sem atrito (Offensive, Skirmish, testes antigos) nada muda
	assert(Capture.winner(st, 4500, 4500) == "draw")
end)

test("HUD: quem está tomando cada setor e a disputa (Capture.activity)", function()
	local st = Capture.new(INIT)
	local cap, con = Capture.activity(st, at(3, 2, 0))
	assert(cap[3] == "US" and not con[3])
	cap, con = Capture.activity(st, at(3, 2, 1))
	assert(con[3] and cap[3] == nil)
	-- EUA no S2 (não atacável sem S3): não está tomando
	cap = Capture.activity(st, at(2, 3, 0))
	assert(cap[2] == nil)
	-- VC defendendo o próprio setor cheio: nada a mostrar
	cap = Capture.activity(st, at(1, 0, 2))
	assert(cap[1] == nil)
end)

-- ===== frente =====
local bySector: { [number]: { any } } = {}
for _, sp in MapConfig.Strongpoints do
	bySector[sp.sector] = bySector[sp.sector] or {}
	table.insert(bySector[sp.sector], sp)
end
local function sectorAt(x: number, z: number): number?
	return Geometry.sectorAt(MapConfig.Sectors, x, z)
end
local function distM(a: any, b: any): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) * M
end

test("sorteio dos pontos fortes: 1 por setor, no setor certo, e a frente fica mais compacta", function()
	local rng = Rng.new(7)
	local sumNew, sumOld, n = 0, 0, 2000
	for _ = 1, n do
		local p = Front.pickStrongpoints(bySector, 5, Front.firstSector("Warfare", 5), function()
			return rng:next()
		end)
		for s = 1, 5 do
			assert(p[s] and p[s].sector == s, "setor " .. s)
		end
		sumNew += distM(p[2], p[3]) + distM(p[4], p[3])
		-- sorteio solto (antes): média exata das distâncias
	end
	for _, a in bySector[3] do
		for _, b in bySector[2] do
			sumOld += distM(a, b) / (3 * 3)
		end
		for _, b in bySector[4] do
			sumOld += distM(a, b) / (3 * 3)
		end
	end
	local avgNew = sumNew / n
	print(string.format("       (S2+S4 até o S3: %.0f m em média antes, %.0f m agora)", sumOld, avgNew))
	assert(avgNew < sumOld, "a cadeia deveria aproximar os pontos")
	assert(Front.firstSector("Offensive", 5) == 5 and Front.firstSector("Warfare", 5) == 3)
end)

test("reunião avançada: dentro do setor próprio, a >= 250 m do alvo, e encurta a marcha", function()
	local worstOld, worstNew = 0, 0
	local sumOld, sumNew, k = 0, 0, 0
	for _, t in bySector[3] do
		for _, pair in { { own = 2, f = "VC" }, { own = 4, f = "US" } } do
			for _, own in bySector[pair.own] do
				local x, z = Front.forwardRally(pair.own, own, t, M, sectorAt)
				assert(x and z, "sem lugar para a reunião avançada")
				assert(sectorAt(x, z) == pair.own, "fora do setor próprio")
				local d = distM({ x = x, z = z }, t)
				assert(d >= Front.C.forwardM - 1, string.format("perto demais: %.0f m", d))
				-- antes: o ponto livre mais perto do alvo era a reunião 100 m atrás do ponto forte ou o QG
				local rx, rz = SpawnRules.rallyPosition(own.x, own.z, pair.f, M)
				local hq = MapConfig.HQ[pair.f]
				local old = math.min(distM({ x = rx, z = rz }, t), distM(hq, t))
				local new = math.min(old, d)
				worstOld, worstNew = math.max(worstOld, old), math.max(worstNew, new)
				sumOld += old
				sumNew += new
				k += 1
			end
		end
	end
	print(
		string.format(
			"       (marcha até o S3 em corrida leve: média %.0f s -> %.0f s; pior caso %.0f s -> %.0f s)",
			sumOld / k / JOG,
			sumNew / k / JOG,
			worstOld / JOG,
			worstNew / JOG
		)
	)
	assert(worstNew / JOG <= 150, "a meta da Parte 4 é contato em 90–150 s depois de nascer")
end)

test("Offensive: a reunião avançada dos EUA no S5 deixa o S4 a <= 150 s de marcha", function()
	local worstOld, worstNew = 0, 0
	for _, t in bySector[4] do
		for _, own in bySector[5] do
			local x, z = Front.forwardRally(5, own, t, M, sectorAt)
			assert(x and z and sectorAt(x, z) == 5)
			local rx, rz = SpawnRules.rallyPosition(own.x, own.z, "US", M)
			local old = math.min(distM({ x = rx, z = rz }, t), distM(MapConfig.HQ.US, t))
			worstOld = math.max(worstOld, old)
			worstNew = math.max(worstNew, math.min(old, distM({ x = x, z = z }, t)))
		end
	end
	print(
		string.format(
			"       (EUA até o S4 no Offensive, pior caso: %.0f s -> %.0f s)",
			worstOld / JOG,
			worstNew / JOG
		)
	)
	assert(worstNew / JOG <= 150)
end)

test("reunião avançada: pares do Warfare inicial e do Offensive", function()
	local w = Front.forwardPairs(INIT, ALL, "US")
	assert(#w == 1 and w[1].own == 4 and w[1].target == 3)
	local v = Front.forwardPairs(INIT, ALL, "VC")
	assert(#v == 1 and v[1].own == 2 and v[1].target == 3)
	local o = Offensive.new()
	local us = Front.forwardPairs(o.capture.owner, o.capture.active, "US")
	assert(#us == 1 and us[1].own == 5 and us[1].target == 4)
	assert(#Front.forwardPairs(o.capture.owner, o.capture.active, "VC") == 0, "o VC defende: usa a reunião do S4")
end)

test("objetivo do time no HUD segue o dos bots e vira defesa quando atacam o nosso", function()
	for _, f in { "US", "VC" } do
		local role, s = Front.objective(INIT, ALL, f, nil)
		assert(role == "attack" and s == BotBrain.objective(INIT, ALL, f), f)
	end
	local o = Offensive.new()
	local r1, s1 = Front.objective(o.capture.owner, o.capture.active, "US", nil)
	local r2, s2 = Front.objective(o.capture.owner, o.capture.active, "VC", nil)
	assert(r1 == "attack" and s1 == 4 and r2 == "defend" and s2 == 4)
	local r3, s3 = Front.objective(INIT, ALL, "US", { [4] = "VC" })
	assert(r3 == "defend" and s3 == 4)
end)

test("reunião do squad: só o líder, longe do inimigo, do objetivo e do QG, com recarga", function()
	local base = {
		leader = true,
		alive = true,
		inBounds = true,
		inWater = false,
		nearestEnemyM = 300,
		nearestObjectiveM = 300,
		enemyHqM = 900,
		now = 1000,
		lastPlacedAt = nil,
	}
	assert(Front.squadRallyCheck(base) == nil)
	local function with(k: string, v: any): string?
		local c = table.clone(base) :: any
		c[k] = v
		return Front.squadRallyCheck(c)
	end
	assert(with("leader", false))
	assert(with("alive", false))
	assert(with("inWater", true))
	assert(with("inBounds", false))
	assert(with("nearestEnemyM", 60))
	assert(with("nearestObjectiveM", 100))
	assert(with("enemyHqM", 200))
	assert(with("lastPlacedAt", 950))
	assert(with("lastPlacedAt", 1000 - Front.C.squadRallyCooldownS) == nil)
end)

-- ===== tela de baixa =====
test("baixa: rumo em 8 setores (X = leste, Z = sul) e distância de ouvido", function()
	assert(Casualty.bearing(0, -10) == "norte")
	assert(Casualty.bearing(10, -10) == "nordeste")
	assert(Casualty.bearing(10, 0) == "leste")
	assert(Casualty.bearing(0, 10) == "sul")
	assert(Casualty.bearing(-10, 10) == "sudoeste")
	assert(Casualty.bearing(-10, -1) == "oeste")
	assert(Casualty.roundDistance(12) == 10 and Casualty.roundDistance(2) == 5)
	assert(Casualty.roundDistance(117) == 120)
	assert(Casualty.roundDistance(333) == 325)
	assert(Casualty.roundDistance(777) == 800)
end)

test("baixa: frase da causa sem quem atirou (Parte 9.5)", function()
	-- 120 m a nordeste: 84,85 m de cada lado
	local d = 84.85 / M
	local c = { kind = "shot", weaponKind = "rifle", dx = d, dz = -d, studM = M }
	assert(Casualty.text(c) == "Abatido por fuzil, ~120 m a nordeste", Casualty.text(c))
	assert(Casualty.text(c, true) == "Ferido por fuzil, ~120 m a nordeste")
	local mg = { kind = "shot", weaponKind = "mg", dx = 0, dz = 300 / M, studM = M }
	assert(Casualty.text(mg) == "Abatido por metralhadora, ~300 m a sul", Casualty.text(mg))
	local boom = { kind = "explosion", explosive = "mortar_82", dx = -12 / M, dz = 0, studM = M }
	assert(Casualty.text(boom) == "Estilhaços de morteiro, ~10 m a oeste", Casualty.text(boom))
	local close = { kind = "explosion", explosive = "grenade_vc", dx = 1, dz = 1, studM = M }
	assert(string.find(Casualty.text(close), "a poucos metros", 1, true))
	assert(string.find(Casualty.text(nil), "origem não identificada", 1, true))
	-- nada de nome: a causa só tem tipo de arma, distância e rumo
	assert(c.from == nil)
end)

test("baixa: grupo data-hora de 1965, tempo em campo e pulso de quem sangra", function()
	assert(Casualty.dtg(6.5) == "180630H AUG 65")
	assert(Casualty.dtg(14 + 32 / 60) == "181432H AUG 65")
	assert(Casualty.duration(42) == "42 s" and Casualty.duration(192) == "3 min 12 s")
	assert(Casualty.pulse(0) == 110 and Casualty.pulse(1) == 150 and Casualty.pulse(2) == 150)
end)

-- ===== carta =====
test("carta: setores viram retângulos que cobrem o polígono sem sobra (amostra de 25 m)", function()
	local b = MapConfig.Bounds
	for _, s in MapConfig.Sectors do
		local rects = Carta.rects(s.polygon)
		assert(#rects >= 1)
		local step = 25 / M
		local x = b.minX + step / 2
		while x < b.maxX do
			local z = b.minZ + step / 2
			while z < b.maxZ do
				local inPoly = Geometry.pointInPolygon(s.polygon, x, z)
				local hits = 0
				for _, r in rects do
					if x > r.x0 and x < r.x1 and z > r.z0 and z < r.z1 then
						hits += 1
					end
				end
				assert((hits == 1) == inPoly and hits <= 1, string.format("S%d (%.0f, %.0f)", s.id, x, z))
				z += step
			end
			x += step
		end
	end
end)

test("carta: fronteira S3/S4 tem a dobra (3 trechos) e S1/S2 é uma reta", function()
	assert(#Carta.boundary(MapConfig.Sectors, 3, 4) == 3)
	assert(#Carta.boundary(MapConfig.Sectors, 1, 2) == 1)
	assert(#Carta.boundary(MapConfig.Sectors, 1, 3) == 0)
end)

test("carta: zoom no ponteiro mantém o ponto parado; a folha nunca sai da janela", function()
	local W, H = 940, 620
	local u, v, z = 0.5, 0.5, 1
	local au, av = Carta.pick(u, v, z, W, H, 700, 200)
	local u2, v2 = Carta.zoomAbout(u, v, z, 3, au, av)
	local bu, bv = Carta.pick(u2, v2, 3, W, H, 700, 200)
	near(bu, au, 1e-9, "u")
	near(bv, av, 1e-9, "v")
	-- zoom 1: a folha (quadrada) cabe na altura e fica centrada
	local cu, cv = Carta.clampCenter(0.1, 0.9, 1, W, H)
	assert(cu == 0.5 and cv == 0.5)
	local x0, y0, size = Carta.layout(cu, cv, 1, W, H)
	assert(size == H and y0 == 0 and x0 == (W - H) / 2)
	-- zoom 4: o centro fica preso para a borda da folha não entrar na janela
	local ku, kv = Carta.clampCenter(0, 1, 4, W, H)
	local lx, ly, ls = Carta.layout(ku, kv, 4, W, H)
	assert(lx <= 0 and ly <= 0 and lx + ls >= W and ly + ls >= H)
	local m, px = Carta.scaleBar(2000 / 620, 140)
	assert(m == 200 and px <= 140)
end)

test("carta: 4 blocos no plano de upload e grupos novos em AssetIds (valor 0 até subir)", function()
	local plan = net.jsonDecode(fs.readFile("assets/upload_plan.json"))
	local keys = {}
	for _, it in plan do
		if string.sub(it.key, 1, 6) == "Carta." then
			keys[it.key] = it
			assert(it.assetType == "Decal", it.key)
		end
	end
	for _, t in Carta.TILES do
		local it = keys["Carta." .. t.key]
		assert(it, "falta Carta." .. t.key)
		assert(it.file == string.format("assets/carta/carta_%d_%d.png", t.row, t.col), it.file)
	end
	local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds") :: any
	for _, t in Carta.TILES do
		assert(type(AssetIds.Carta[t.key]) == "number" and type(AssetIds.CartaImages[t.key]) == "number")
	end
	if fs.isFile("assets/carta/carta_0_0.png") then
		print("       (blocos gerados em assets/carta: rode tools/make_carta.py de novo se o mapa mudar)")
	else
		print("       (blocos ainda não gerados: uv run python tools/make_carta.py)")
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
