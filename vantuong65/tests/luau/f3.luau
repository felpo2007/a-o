--!strict
-- Testes da F3 e dos bots (Lune). Uso: lune run tests/luau/f3.luau
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local S = "../../src/ReplicatedStorage/Shared/"
local BotBrain = require(S .. "BotBrain")
local SolarPosition = require(S .. "SolarPosition")
local Tunnels = require(S .. "Tunnels")
local TunnelGeometry = require("../../src/ServerStorage/VT65Build/TunnelGeometry")

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
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f", msg or "", a, b))
end

test("Sol: caso de referência NOAA (Greenwich, 21/06/2010 12:00 UTC) ~61,96°", function()
	local _, el = SolarPosition.compute(2010, 6, 21, 12, 0, 51.48, 0)
	near(el, 61.96, 0.1)
end)

test("Sol em 18/08/1965 (UTC+8): nasce perto das 06:30 a leste; meio-dia solar quase a pino", function()
	local az, el = SolarPosition.compute(1965, 8, 18, 6.5, 8, 15.30, 108.85)
	assert(az > 70 and az < 80, "azimute leste-nordeste")
	assert(math.abs(el) < 2, "no horizonte")
	local _, elNoon = SolarPosition.compute(1965, 8, 18, 12.8, 8, 15.30, 108.85)
	assert(elNoon > 85, "quase a pino")
end)

test("ajuste ClockTime/latitude reproduz a direção num modelo de sol simulado", function()
	-- modelo simulado: sol gira em torno de um eixo inclinado pela latitude (declinação 0)
	local function mockDir(c: number, l: number): (number, number, number)
		local h = (c - 12) / 24 * 2 * math.pi
		local lat = math.rad(l)
		local x = -math.sin(h)
		local y0, z0 = math.cos(h), 0
		-- inclinação em torno de X (norte = -Z)
		local y = y0 * math.cos(lat) - z0 * math.sin(lat)
		local z = y0 * math.sin(lat) + z0 * math.cos(lat)
		return -x, y, z
	end
	local tx, ty, tz = mockDir(9.3, 20)
	local c, l, err = SolarPosition.fit(tx, ty, tz, mockDir, 6.5, 0)
	assert(err < 0.2, "erro " .. err)
	local x, y, z = mockDir(c, l)
	near(x * tx + y * ty + z * tz, 1, 1e-4)
end)

test("bots: objetivo = setor atacável vizinho; EUA vão para oeste, VC para leste", function()
	local owner = { "VC", "VC", "Neutral", "US", "US" }
	local active = { true, true, true, true, true }
	assert(BotBrain.objective(owner, active, "US") == 3)
	assert(BotBrain.objective(owner, active, "VC") == 3)
	local o2 = { "VC", "Neutral", "US", "US", "US" }
	assert(BotBrain.objective(o2, active, "US") == 2)
	assert(BotBrain.objective(o2, active, "VC") == 2)
	assert(BotBrain.objective({ "US", "US", "US", "US", "US" }, active, "US") == nil)
	assert(BotBrain.objective({ "VC", "VC", "Neutral", "VC", "VC" }, { false, false, true, false, false }, "US") == 3)
end)

test("bots: erro de mira cresce com distância e movimento; rajadas só em metralhadora", function()
	assert(BotBrain.aimSigma(300, false, 0.5) > BotBrain.aimSigma(50, false, 0.5))
	assert(BotBrain.aimSigma(100, true, 0.5) > BotBrain.aimSigma(100, false, 0.5))
	assert(BotBrain.burst("rifle", 0.9) == 1)
	local b = BotBrain.burst("mg", 0.99)
	assert(b >= 4 and b <= 8)
	near(BotBrain.shotDelay("mg", 600, true, 0.5), 0.1, 1e-9)
end)

test("túneis: 1,0 x 1,2 m, ~454 m, 5 entradas, caixas de escavação e forro coerentes", function()
	local n = 0
	for _, node in Tunnels.nodes do
		if node.entrance then
			n += 1
		end
	end
	assert(n == 5)
	near(Tunnels.length(), 454, 5) -- D-115: a boca E5 20 m mais perto (era ~474 m)
	local env = { Vector3 = roblox.Vector3, CFrame = roblox.CFrame }
	local boxes = TunnelGeometry.build(env, Tunnels, 0, 0, function()
		return 50
	end)
	local kinds = {}
	for _, b in boxes do
		kinds[b.kind] = (kinds[b.kind] or 0) + 1
		if b.kind == "floor" and string.sub(b.name, 1, 6) == "Tunnel" then
			-- piso a ~3 m abaixo do chão (50 studs - 3/0,28 - meia espessura)
			assert(math.abs(b.cf.Position.Y - (50 - 3 / 0.28 - 0.5)) < 1.5, "profundidade do piso")
		end
	end
	assert(kinds.carve == #Tunnels.edges + 8 + (#Tunnels.trench - 1), "escavações")
	assert(kinds.entrance == 5 and kinds.truss == 5 and kinds.shaftwall == 20)
	assert(kinds.wall == 2 * #Tunnels.edges)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
