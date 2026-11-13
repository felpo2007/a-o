--!strict
-- Testes do movimento, da rota, do motorista e dos túneis dos bots (D-90), no Lune. Tudo puro:
-- BotMove, BotNav, BotDriver e TunnelLinks. Uso, a partir de vantuong65/:
--   lune run tests/luau/botsmov.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local B = "../../src/ServerStorage/VT65Build/"
local BotBrain = require(S .. "BotBrain") :: any
local BotMove = require(S .. "BotMove") :: any
local BotNav = require(S .. "BotNav") :: any
local BotDriver = require(S .. "BotDriver") :: any
local TunnelLinks = require(S .. "TunnelLinks") :: any
local Tunnels = require(S .. "Tunnels") :: any
local Movement = require(S .. "Movement") :: any
local SoldierAnims = require(S .. "SoldierAnims") :: any
local VehicleDrive = require(S .. "VehicleDrive") :: any
local Vehicles = require(S .. "Vehicles") :: any
local MapConfig = require(S .. "MapConfig") :: any

local STUD = 0.28
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

-- ===== passo e corpo =====
test("passo: as velocidades são as âncoras do Movement e da animação (andar, trote, corrida)", function()
	local base = { stance = "stand", distM = 50, urgent = false, cautious = false, aiming = false, behindM = 0 }
	local function g(o: any): (string, number)
		local c = table.clone(base)
		for k, v in o do
			c[k] = v
		end
		c.legImpaired = c.legImpaired == true
		return BotBrain.gait(c)
	end
	local n, v = g({})
	assert(n == "jog" and v == Movement.JOG and v == SoldierAnims.ANCHOR.trote, "trote")
	n, v = g({ cautious = true })
	assert(n == "walk" and v == Movement.WALK and v == SoldierAnims.ANCHOR.andar, "andar")
	n, v = g({ urgent = true })
	assert(n == "sprint" and v == Movement.SPRINT and v == SoldierAnims.ANCHOR.correr, "corrida")
	n, v = g({ urgent = true, waterM = 0.6 })
	assert(n == "jog", "água acima do joelho não corre")
	n, v = g({ aiming = true })
	assert(n == "ads" and v == Movement.ADS, "andando de lado mirando")
	n, v = g({ stance = "crouch" })
	assert(v == Movement.CROUCH and n == "crouch")
	n, v = g({ stance = "prone" })
	assert(v == Movement.PRONE and n == "prone")
	n, v = g({ behindM = 30 })
	assert(n == "sprint", "atrasado no squad corre")
	n, v = g({ urgent = true, legImpaired = true })
	assert(v == Movement.WALK, "perna ferida anda")
	-- arrozal e rampa como o jogador
	assert(BotBrain.groundFactor("paddy", 0, 0, 0) < BotBrain.groundFactor("forest", 0, 0, 0))
	assert(BotBrain.groundFactor("firm", 0, 0, 0.3) < BotBrain.groundFactor("firm", 0, 0, 0))
end)

test("corpo: acelera e freia como o jogador; vira com velocidade limitada; parado não gira", function()
	local b = { vx = 0, vz = 0, yaw = 0 }
	local d = { dirX = 0, dirZ = -1, speed = Movement.JOG, turn = BotMove.turnRate("jog", false), grip = 1 }
	local t = 0
	while math.sqrt(b.vx ^ 2 + b.vz ^ 2) < Movement.JOG - 1e-6 and t < 5 do
		BotMove.step(b, d, 1 / 30)
		t += 1 / 30
	end
	print(string.format("       parado -> trote em %.2f s", t))
	assert(t > 0.3 and t < 0.7, "aceleração humana (Movement.ACCEL)")
	-- vira 180°: o corpo leva tempo (sem girar de uma vez)
	local d2 = { dirX = 0, dirZ = 1, speed = Movement.JOG, turn = BotMove.turnRate("jog", false), grip = 1 }
	local maxStep = 0
	local prev = b.yaw
	for _ = 1, 60 do
		BotMove.step(b, d2, 1 / 30)
		maxStep = math.max(maxStep, math.abs(BotMove.wrap(b.yaw - prev)))
		prev = b.yaw
	end
	assert(maxStep <= math.rad(BotBrain.MOVE.turnDegS.jog) / 30 + 1e-9, "giro acima do limite")
	near(math.abs(BotMove.wrap(b.yaw - math.pi)), 0, 0.05, "virou para trás")
	-- freia até parar e não gira parado
	local stop = { dirX = 0, dirZ = 0, speed = 0, turn = 10, grip = 1 }
	t = 0
	while math.sqrt(b.vx ^ 2 + b.vz ^ 2) > 1e-6 and t < 5 do
		BotMove.step(b, stop, 1 / 30)
		t += 1 / 30
	end
	assert(t <= 0.4, "freada: " .. t)
	local y0 = b.yaw
	for _ = 1, 30 do
		BotMove.step(b, stop, 1 / 30)
	end
	assert(b.yaw == y0, "parado sem mira não gira")
	-- mirando: o corpo olha o alvo enquanto anda de lado
	local aim =
		{ dirX = 1, dirZ = 0, speed = Movement.ADS, faceYaw = 0, turn = BotMove.turnRate("ads", true), grip = 1 }
	for _ = 1, 60 do
		BotMove.step(b, aim, 1 / 30)
	end
	near(BotMove.wrap(b.yaw), 0, 1e-6, "olha o alvo")
	assert(b.vx > Movement.ADS * 0.95, "anda de lado")
end)

-- Simula um bot seguindo um caminho com o controle do runtime (BotMove.follow + BotMove.step)
local function simulate(pts: { any }, want: number): any
	local p = BotMove.path(BotMove.simplify(pts, 4, 1))
	local f = BotMove.newFollow()
	local b = { vx = 0, vz = 0, yaw = BotMove.yawTo(pts[2].x - pts[1].x, pts[2].z - pts[1].z) }
	local x, z = pts[1].x, pts[1].z
	local dt = 1 / 30
	local out = { maxOff = 0, stops = 0, yawFlips = 0, t = 0, endM = 0, minMid = math.huge, overshoot = false }
	local lastRate = 0
	local moving = false
	for _ = 1, 30 * 120 do
		local sp = math.sqrt(b.vx ^ 2 + b.vz ^ 2)
		local dx, dz, speed, left = BotMove.follow(f, p, x, z, sp, want, true)
		if f.done then
			break
		end
		local y0 = b.yaw
		BotMove.step(b, { dirX = dx, dirZ = dz, speed = speed, turn = BotMove.turnRate("jog", false), grip = 1 }, dt)
		x += b.vx / STUD * dt
		z += b.vz / STUD * dt
		local rate = BotMove.wrap(b.yaw - y0)
		if math.abs(rate) > 1e-4 and math.abs(lastRate) > 1e-4 and (rate > 0) ~= (lastRate > 0) then
			out.yawFlips += 1
		end
		if math.abs(rate) > 1e-4 then
			lastRate = rate
		end
		local nsp = math.sqrt(b.vx ^ 2 + b.vz ^ 2)
		if moving and nsp < 0.05 and left > 1 then
			out.stops += 1
		end
		moving = nsp > 0.5
		if left > 3 and out.t > 1 then
			out.minMid = math.min(out.minMid, nsp)
		end
		local _, _, off = BotMove.project(p, x, z, f.seg)
		out.maxOff = math.max(out.maxOff, off * STUD)
		out.t += dt
	end
	local ex, ez = pts[#pts].x, pts[#pts].z
	out.endM = math.sqrt((ex - x) ^ 2 + (ez - z) ^ 2) * STUD
	return out
end

test("caminho: segue sem zigue-zague, sem parar no meio e para no ponto (sem girar no lugar)", function()
	-- caminho do PathfindingService: pontos a cada 6 studs, com duas curvas de 45° e uma de 90°
	local pts = {}
	local x, z = 0, 0
	local function seg(dx: number, dz: number, n: number)
		for _ = 1, n do
			x += dx
			z += dz
			table.insert(pts, { x = x, z = z })
		end
	end
	table.insert(pts, { x = 0, z = 0 })
	seg(0, -6, 10)
	seg(4.24, -4.24, 6)
	seg(6, 0, 10)
	seg(0, 6, 8)
	local r = simulate(pts, Movement.JOG)
	print(
		string.format(
			"       %.1f s, desvio máx %.2f m, paradas %d, inversões do giro %d, menor velocidade no meio %.2f m/s, fim a %.2f m",
			r.t,
			r.maxOff,
			r.stops,
			r.yawFlips,
			r.minMid,
			r.endM
		)
	)
	assert(r.stops == 0, "anda e para")
	assert(r.yawFlips <= 3, "zigue-zague")
	assert(r.maxOff < 1.5, "saiu do caminho")
	assert(r.minMid >= Movement.WALK * 0.9, "freou demais no meio")
	assert(r.endM <= BotBrain.MOVE.arriveM + 0.1, "não chegou")
end)

test("caminho: trecho de passagem (não final) passa do fim reto, sem meia-volta nem freada", function()
	local p = BotMove.path({ { x = 0, z = 0 }, { x = 0, z = -40 } })
	local f = BotMove.newFollow()
	local b = { vx = 0, vz = -Movement.JOG, yaw = 0 }
	local x, z = 0, -30
	local minVz = -math.huge -- a velocidade para o norte nunca cai
	for _ = 1, 90 do
		local dx, dz, speed = BotMove.follow(f, p, x, z, Movement.JOG, Movement.JOG, false)
		BotMove.step(
			b,
			{ dirX = dx, dirZ = dz, speed = speed, turn = BotMove.turnRate("jog", false), grip = 1 },
			1 / 30
		)
		x += b.vx / STUD / 30
		z += b.vz / STUD / 30
		minVz = math.max(minVz, b.vz)
	end
	assert(not f.done, "trecho de passagem não termina sozinho")
	local _, _, _, left = BotMove.follow(f, p, x, z, Movement.JOG, Movement.JOG, false)
	assert(left == 0, "depois do fim falta 0 (o próximo trecho é pedido)")
	assert(z < -40 - 10, "passou do fim: " .. z)
	assert(minVz < -Movement.JOG * 0.95, "não freou nem voltou")
	near(x, 0, 0.01, "seguiu reto")
end)

test("caminho: perto da chegada freia suave; curva fechada cai para o andar", function()
	local M = BotBrain.MOVE
	assert(BotMove.speedCap(Movement.SPRINT, 30, 0, true) == Movement.SPRINT)
	assert(BotMove.speedCap(Movement.SPRINT, 1, 0, true) < Movement.JOG)
	assert(BotMove.speedCap(Movement.JOG, 0.2, 0, true) == 0)
	assert(BotMove.speedCap(Movement.SPRINT, 30, math.rad(M.cornerDeg + 10), true) <= Movement.SPRINT * 0.5 + 1e-9)
	assert(BotMove.speedCap(Movement.JOG, 30, math.rad(90), false) >= Movement.WALK, "nunca abaixo do andar na curva")
	-- simplificação tira pontos em linha e mantém o pulo
	local pts =
		{ { x = 0, z = 0 }, { x = 0, z = -6 }, { x = 0, z = -12, jump = true }, { x = 0, z = -18 }, { x = 6, z = -18 } }
	local sp = BotMove.simplify(pts, 4, 1)
	assert(#sp == 4 and sp[2].jump == true, "simplificação: " .. #sp)
	local p = BotMove.path(sp)
	assert(BotMove.jumpAhead(p, 0, 13) and not BotMove.jumpAhead(p, 13, 3))
end)

test("preso: anda menos de 25% do pedido em 1,5 s", function()
	local s = BotMove.newStuck()
	local stuck = false
	for _ = 1, 50 do
		stuck = BotMove.stuckStep(s, 1 / 30, Movement.JOG / 30, 0.1 / 30) or stuck
	end
	assert(stuck, "deveria acusar")
	local s2 = BotMove.newStuck()
	local any = false
	for _ = 1, 100 do
		any = BotMove.stuckStep(s2, 1 / 30, Movement.JOG / 30, Movement.JOG * 0.8 / 30) or any
	end
	assert(not any, "andando não está preso")
	assert(not BotMove.stuckStep(BotMove.newStuck(), 5, 0, 0), "parado de propósito não está preso")
end)

test("squad: rastro do líder, coluna na mata, cunha no aberto e arco de defesa", function()
	local t = BotMove.newTrail(1.5 / STUD, 90 / STUD)
	for k = 0, 100 do
		BotMove.trailPush(t, 0, -k * 2 / STUD) -- líder andando para o norte (-Z)
	end
	local hx, hz = 0, -100 * 2 / STUD
	local x, z, dx, dz = BotMove.trailBehind(t, hx, hz, 12 / STUD)
	near(x, 0, 1e-6)
	near((z - hz) * STUD, 12, 0.01, "12 m atrás")
	near(dz, -1, 1e-6, "rumo de marcha")
	local b1, s1 = BotMove.slot("file", 3)
	assert(s1 == 0 and b1 == 3 * BotBrain.SQUAD.spacingM)
	local _, w1 = BotMove.slot("wedge", 1)
	local _, w2 = BotMove.slot("wedge", 2)
	assert(w1 > 0 and w2 < 0, "cunha alterna os lados")
	assert(BotMove.formationFor(true) == "wedge" and BotMove.formationFor(false) == "file")
	local ax, az = BotMove.defendSlot(1, 5, 0, 0.5)
	local bx, bz = BotMove.defendSlot(5, 5, 0, 0.5)
	assert(math.abs(ax - bx) > 10 / STUD, "espalhados no arco")
	assert(az < 0 and bz < 0, "virados para o inimigo (rumo 0 = -Z)")
	local _ = dx
end)

-- ===== rota (BotNav) =====
local function synth(): any
	-- 60 x 40 células de 16 studs: arrozal alagado no meio, dique em volta, sebe em x = 40
	local g = BotNav.new(60, 40, 16, 0, 0)
	for r = 0, 39 do
		for c = 0, 59 do
			local i = r * 60 + c
			local f = 0
			if c >= 10 and c <= 30 and r >= 5 and r <= 34 then
				f = BotNav.F.PADDY
			end
			BotNav.setCell(g, i, 3, 0, f)
		end
	end
	-- dique em volta do arrozal (linha de células baratas)
	BotNav.markSegment(g, 9.5 * 16, 4.5 * 16, 31.5 * 16, 4.5 * 16, BotNav.F.DIKE)
	BotNav.markSegment(g, 9.5 * 16, 35.5 * 16, 31.5 * 16, 35.5 * 16, BotNav.F.DIKE)
	-- sebe de bambu em c = 40 com uma passagem em r = 2
	for r = 4, 39 do
		BotNav.markPoint(g, 40.5 * 16, (r + 0.5) * 16, BotNav.F.HEDGE)
	end
	return g
end

-- fração do percurso em células com `bit` (e sem `unless`)
local function frac(g: any, pts: { any }, bit: number, unless: number?): number
	local hit, n = 0, 0
	for k = 2, #pts do
		local a, b = pts[k - 1], pts[k]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local steps = math.max(1, math.ceil(len / 8))
		for s = 1, steps do
			local t = s / steps
			local f = BotNav.flagsAt(g, a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t)
			n += 1
			if bit32.btest(f, bit) and not (unless and bit32.btest(f, unless)) then
				hit += 1
			end
		end
	end
	return hit / math.max(n, 1)
end

test("rota: a infantaria contorna o arrozal alagado pelo dique (custo menor que a reta)", function()
	local g = synth()
	local p = BotNav.profile("infantry")
	local s = BotNav.search(g, p, 2 * 16, 20 * 16, 37 * 16, 20 * 16)
	local guard = 0
	while BotNav.run(s, 50) == "running" do
		guard += 1
	end
	assert(s.status == "done", s.status)
	assert(guard > 3, "rodou em fatias")
	local pts = BotNav.waypoints(s)
	local pad = frac(g, pts, BotNav.F.PADDY)
	print(string.format("       %d pontos, %.0f%% no arrozal alagado, %d nós", #pts, pad * 100, s.expanded))
	assert(pad < 0.35, "atravessou o arrozal")
	-- mesma busca de uma vez dá a mesma rota
	local s2 = BotNav.search(g, p, 2 * 16, 20 * 16, 37 * 16, 20 * 16)
	BotNav.run(s2, 1e9)
	assert(#BotNav.waypoints(s2) == #pts, "fatias mudaram a rota")
end)

test("rota: sebe de bambu para a lagarta (passa pela abertura); a infantaria margeia", function()
	local g = synth()
	local tr = BotNav.profile("tracked", "m48a3")
	local s = BotNav.search(g, tr, 35 * 16, 30 * 16, 50 * 16, 30 * 16)
	BotNav.run(s, 1e9)
	assert(s.status == "done")
	local pts = BotNav.waypoints(s)
	assert(frac(g, pts, BotNav.F.HEDGE) == 0, "lagarta atravessou a sebe")
	local minZ = math.huge
	for _, q in pts do
		minZ = math.min(minZ, q.z)
	end
	assert(minZ < 4 * 16, "deu a volta pela abertura")
	assert(BotNav.cost(g, BotNav.index(g, 40.5 * 16, 20 * 16), BotNav.profile("infantry")) < 1, "sebe barata a pé")
end)

test("rota: o M48 vadeia o riacho de 0,6 m; o Ontos não; o LVTP-5 boia no mar", function()
	local g = BotNav.new(30, 10, 16, 0, 0)
	for i = 0, 299 do
		BotNav.setCell(g, i, 1, 0, 0)
	end
	for r = 0, 9 do
		BotNav.markPoint(g, 15.5 * 16, (r + 0.5) * 16, BotNav.F.STREAM)
	end
	local function go(kind: string, spec: string): string
		local s = BotNav.search(g, BotNav.profile(kind, spec), 2 * 16, 5 * 16, 28 * 16, 5 * 16)
		return BotNav.run(s, 1e9)
	end
	assert(go("tracked", "m48a3") == "done")
	assert(go("tracked", "ontos") == "fail", "Ontos não vadeia")
	assert(go("amphibious", "lvtp5") == "done")
	local sea = BotNav.new(10, 3, 16, 0, 0)
	for i = 0, 29 do
		BotNav.setCell(sea, i, 0, -5, BotNav.F.SEA)
	end
	local s = BotNav.search(sea, BotNav.profile("infantry"), 8, 24, 150, 24)
	assert(BotNav.run(s, 1e9) == "fail", "infantaria não nada no mar")
	local s2 = BotNav.search(sea, BotNav.profile("amphibious", "lvtp5"), 8, 24, 150, 24)
	assert(BotNav.run(s2, 1e9) == "done", "LVTP-5 boia")
end)

-- Grade do mapa de verdade (como o BotWorld monta): terreno, paisagem e feições do bake
local realGrid: any = nil
local function buildReal(): any
	if realGrid then
		return realGrid
	end
	local WorldData = require(B .. "WorldData") :: any
	local Landscape = require(B .. "Landscape") :: any
	local Grid = require(B .. "Data/Grid") :: any
	local Features = require(B .. "Data/Features") :: any
	local chunks = {}
	for _, name in Grid.heightChunks do
		table.insert(chunks, (require :: any)(B .. "Data/" .. name))
	end
	local world = WorldData.load(Grid, chunks)
	local housesXZ = {}
	for i = 1, #Features.houses, 4 do
		table.insert(housesXZ, Features.houses[i])
		table.insert(housesXZ, Features.houses[i + 1])
	end
	local land = Landscape.new(world, MapConfig, housesXZ)
	local g = BotNav.forWorld(world)
	local t0 = os.clock()
	BotNav.fillRows(g, world, function(x: number, z: number): number
		return land:kindAt(x, z)
	end, MapConfig.Bounds, 0, g.h)
	local function forest(x: number, z: number): boolean
		return land:kindAt(x, z) == 1
	end
	local d = Features.dikes
	for i = 1, #d, 6 do
		if not (forest(d[i], d[i + 1]) and forest(d[i + 2], d[i + 3])) then
			BotNav.markSegment(g, d[i], d[i + 1], d[i + 2], d[i + 3], BotNav.F.DIKE)
		end
	end
	local w = Features.waters
	for i = 1, #w, 6 do
		if not forest(w[i], w[i + 1]) then
			BotNav.markBox(g, w[i], w[i + 1], w[i + 3], w[i + 4], w[i + 5], BotNav.F.PADDY)
		end
	end
	local hg = Features.hedges
	for i = 1, #hg, 7 do
		if not forest((hg[i] + hg[i + 2]) / 2, (hg[i + 1] + hg[i + 3]) / 2) then
			BotNav.markSegment(g, hg[i], hg[i + 1], hg[i + 2], hg[i + 3], BotNav.F.HEDGE)
		end
	end
	for i = 1, #Features.houses, 4 do
		BotNav.markBox(
			g,
			Features.houses[i],
			Features.houses[i + 1],
			7 / STUD,
			4.5 / STUD,
			Features.houses[i + 3],
			BotNav.F.HOUSE
		)
	end
	print(string.format("       grade %d x %d montada em %.2f s", g.w, g.h, os.clock() - t0))
	realGrid = g
	return g
end

local function strongpoint(name: string): any
	for _, sp in MapConfig.Strongpoints do
		if sp.name == name then
			return sp
		end
	end
	error("sem " .. name)
end

local function realRoute(fromName: string, toName: string, ox: number, oz: number)
	local g = buildReal()
	local a, b = strongpoint(fromName), strongpoint(toName)
	local p = BotNav.profile("infantry")
	local t0 = os.clock()
	local s = BotNav.search(g, p, a.x + ox, a.z + oz, b.x, b.z)
	local slices = 1
	while BotNav.run(s, BotBrain.NAV.expandPerFrame) == "running" do
		slices += 1
	end
	local dt = os.clock() - t0
	assert(s.status == "done", s.status)
	local pts = BotNav.waypoints(s)
	local straight = { { x = a.x + ox, z = a.z + oz }, { x = b.x, z = b.z } }
	local F = BotNav.F
	-- arrozal alagado sem dique (com dique o bot anda em cima dele)
	local padR, padS = frac(g, pts, F.PADDY, F.DIKE), frac(g, straight, F.PADDY, F.DIKE)
	local dikeR, dikeS = frac(g, pts, F.DIKE), frac(g, straight, F.DIKE)
	local lenR, lenS = BotNav.pathLength(pts), BotNav.pathLength(straight)
	print(
		string.format(
			"       %s -> %s: %.0f m (reta %.0f m), %d pontos; alagado sem dique %.0f%% (reta %.0f%%), dique %.0f%% (reta %.0f%%); %d nós, %d fatias, %.0f ms",
			fromName,
			toName,
			lenR * STUD,
			lenS * STUD,
			#pts,
			padR * 100,
			padS * 100,
			dikeR * 100,
			dikeS * 100,
			s.expanded,
			slices,
			dt * 1000
		)
	)
	assert(padR <= padS + 1e-9, "mais arrozal alagado que a reta")
	assert(lenR <= lenS * 1.6, "volta grande demais")
	assert(frac(g, pts, F.HOUSE) <= 0.02, "passa por casa")
end

-- mapa de 1 x 1 km (2026-11-11): rotas pelo arrozal entre An Cường (2) (S4), o S3 e Nam Yên (4)
-- (S1/S2). 2026-11-12: o ponto forte do S3 é a vila grande Xóm Gò, no morrote levado para o centro
-- D-114 (mapa de 500 m): de An Cường (2) e do casario (S4/S5) até a vila de Xóm Gò (S2) e o capim
-- ao pé do morro (S1)
test("rota no mapa real: infantaria do S4 ao S2 foge do arrozal alagado e usa o dique", function()
	realRoute("Sebe ao norte de An Cường (2)", "Xóm Gò", 0, 0)
	realRoute("Arrozal ao sul de An Cường (2)", "Xóm Gò", 0, 0)
	realRoute("Casario sudeste de An Cường (2)", "Capinzal oeste", 0, 0)
end)

test("rota no mapa real: M48A3 da saída da base até o pé do morro sem atravessar casa nem sebe", function()
	local g = buildReal()
	local hq = MapConfig.HQ.US
	local b = strongpoint("Xóm Gò")
	local p = BotNav.profile("tracked", "m48a3")
	-- D-114 (mapa de 500 m): da entrada da base dos EUA (a oeste do QG, tools/bases_mapa.json: -48 m)
	-- até o pé leste do morro, 90 m a leste da praça de Xóm Gò (no de 1 km o alvo ficava 150 m a leste
	-- do morrote, a ~400 m do QG; agora a praça fica a ~280 m dele)
	local s = BotNav.search(g, p, hq.x - 55 / STUD, hq.z, b.x + 90 / STUD, b.z)
	local t0 = os.clock()
	BotNav.run(s, 1e9)
	print(string.format("       M48: %s, %d nós, %.0f ms", s.status, s.expanded, (os.clock() - t0) * 1000))
	assert(s.status == "done", s.status)
	local pts = BotNav.waypoints(s)
	assert(frac(g, pts, BotNav.F.HOUSE) == 0 and frac(g, pts, BotNav.F.HEDGE) == 0, "lagarta em casa ou sebe")
	print(string.format("       rota de %.0f m em %d pontos", BotNav.pathLength(pts) * STUD, #pts))
end)

-- ===== motorista =====
test("motorista: o M48 com a física do VehicleDrive chega ao ponto, gira no lugar e respeita o teto", function()
	local spec = Vehicles.SPECS.m48a3
	local st = VehicleDrive.newState()
	local caps = BotDriver.caps(spec.kind)
	local x, z, yaw = 0, 0, 0 -- olhando para -Z
	local dt = 1 / 30
	-- 1º alvo atrás: tem que girar no lugar antes de andar
	local tx, tz = 0, 60 / STUD
	local pivoted = false
	local top = VehicleDrive.topSpeed(spec, "grass")
	local maxV = 0
	local t = 0
	while t < 90 do
		local dist = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2) * STUD
		if dist < BotBrain.VEHICLE.arriveM and math.abs(st.v) < 0.5 then
			break
		end
		local want = BotDriver.desiredSpeed(top, dist, 0, 1.5)
		local thr, steer = BotDriver.control(yaw, st.v, x, z, tx, tz, want, caps)
		if math.abs(st.v) < 0.5 and math.abs(steer) > 0.9 and thr == 0 then
			pivoted = true
		end
		VehicleDrive.step(spec, st, { throttle = thr, steer = steer }, { ground = "grass" }, dt)
		yaw += st.yawRate * dt
		local lx, lz = -math.sin(yaw), -math.cos(yaw)
		x += lx * st.v / STUD * dt
		z += lz * st.v / STUD * dt
		maxV = math.max(maxV, st.v)
		t += dt
	end
	local dist = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2) * STUD
	print(string.format("       60 m atrás: %.1f s, máx %.1f km/h, parou a %.1f m", t, maxV * 3.6, dist))
	assert(pivoted, "não girou no lugar")
	assert(dist < BotBrain.VEHICLE.arriveM + 1, "não chegou")
	assert(maxV <= top + 0.1, "passou do teto do chão")
end)

test("motorista: carro com rodas (sem giro no lugar) manobra de ré; atirador escolhe a arma", function()
	local caps = BotDriver.caps("wheeled")
	assert(not caps.pivot and BotDriver.caps("tracked").pivot and BotDriver.caps("amphibious").pivot)
	local thr, steer = BotDriver.control(0, 0, 0, 0, 0, 50, 5, caps)
	assert(thr < 0 and steer ~= 0, "alvo atrás: ré")
	local thr2, steer2 = BotDriver.control(0, 5, 0, 0, -10, -50, 5, caps)
	assert(thr2 >= 0 and steer2 < 0, "alvo à frente e à esquerda: volante para a esquerda (< 0)")
	assert(BotDriver.gunFor("gun_90", 150, 3, false, true, 0) == "main", "grupo: canhão")
	assert(BotDriver.gunFor("gun_90", 150, 1, false, true, 0) == "coax", "um só: coaxial")
	assert(BotDriver.gunFor("gun_90", 40, 3, true, true, 0) == "coax", "perto demais para o canhão")
	assert(BotDriver.gunFor("rr_106", 150, 1, false, true, 6) == nil, "Ontos guarda os tubos")
	assert(BotDriver.gunFor("rr_106", 150, 1, true, true, 6) == "main", "Ontos na casa")
	assert(BotDriver.gunFor("m60", 300, 0, false, false, 0) == "m60")
end)

-- ===== túneis =====
test("túneis: cada entrada leva às outras; a ligação passa pelas junções; entrada fechada some", function()
	local links = TunnelLinks.links()
	local ents = TunnelLinks.entrances()
	assert(#ents == 5, "5 entradas")
	for _, e in ents do
		assert(#links[e.id] == 4, e.id .. " leva a " .. #links[e.id])
	end
	local e1e2 = links.E1[1]
	assert(e1e2.to == "E2", "E1 leva primeiro a E2: " .. e1e2.to)
	local n = Tunnels.nodes
	local expect = math.sqrt((n.E1.x - n.J1.x) ^ 2 + (n.E1.z - n.J1.z) ^ 2)
		+ math.sqrt((n.J1.x - n.E2.x) ^ 2 + (n.J1.z - n.E2.z) ^ 2)
	near(e1e2.lengthM, expect, 1e-6, "comprimento")
	assert(e1e2.via[1] == "E1" and e1e2.via[2] == "J1" and e1e2.via[3] == "E2")
	local closed = TunnelLinks.links({ E2 = true })
	assert(#closed.E2 == 0 and #closed.E1 == 3, "entrada destruída fora")
	local via = TunnelLinks.path("E1", "E3", { J1 = true })
	assert(via == nil, "sem J1 não há caminho de E1 a E3")
	local w = TunnelLinks.toWorld({ "E1" }, 100, 200)
	near(w[1].x, 100 + n.E1.x / STUD, 1e-6)
	print(string.format("       E1 -> E3: %.0f m", select(2, TunnelLinks.path("E1", "E3"))))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
