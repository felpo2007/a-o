--!strict
-- Torre dos blindados (D-196; prompt de jogabilidade, item 15): o que gira com a torre, o passo do
-- giro (o mesmo no servidor e nos clientes), o mínimo do cano por giro e as amarras no código.
-- Uso: lune run tests/luau/torre.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local VehicleDrive = require("../../src/ReplicatedStorage/Shared/VehicleDrive") :: any

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

test("na torre: atirador, comandante e municiador do M48; o motorista fica no casco", function()
	for _, s in { "gunner", "commander", "loader", "Escotilha_Comandante", "Escotilha_Municiador" } do
		assert(VehicleDrive.naTorre("m48a3", s), "m48a3 " .. s)
	end
	assert(not VehicleDrive.naTorre("m48a3", "driver") and not VehicleDrive.naTorre("m48a3", "Escotilha_Motorista"))
	assert(VehicleDrive.naTorre("ontos", "gunner") and VehicleDrive.naTorre("ontos", "Escotilha_Torre"))
	assert(not VehicleDrive.naTorre("ontos", "loader"), "o municiador do Ontos carrega por trás, no casco")
	assert(VehicleDrive.naTorre("lvtp5", "gunner") and not VehicleDrive.naTorre("lvtp5", "commander"))
	assert(not VehicleDrive.naTorre("m151", "passenger") and not VehicleDrive.naTorre("nada", "gunner"))
	-- toda peça da torre tem junta (o VehicleService a prende na Torre)
	for id, art in VehicleDrive.ART do
		local t = art.torre
		if t then
			assert(art.pivots and art.pivots.Torre, id .. ": torre sem junta")
			for _, p in t.pecas do
				assert(art.pivots[p], id .. ": " .. p .. " sem junta")
			end
			for _, s in t.lugares do
				assert(art.eyes and art.eyes[s], id .. ": " .. s .. " sem olho")
			end
			assert(art.aim and table.find(t.lugares, art.aim.seat), id .. ": quem aponta fica na torre")
		end
	end
end)

test("giro: pelo caminho mais curto, no máximo a velocidade da ficha por segundo", function()
	local y = 0
	for _ = 1, 30 do
		y = VehicleDrive.torreGira(y, math.rad(90), 24, 1 / 30)
	end
	near(math.deg(y), 24, 1e-6, "24°/s do M48 em 1 s")
	-- de 170° para −170°: 20° pelo lado curto (não 340°)
	local a = VehicleDrive.torreGira(math.rad(170), math.rad(-170), 24, 1)
	near(math.deg(a), 190, 1e-6, "atravessa os 180°")
	-- chega e para
	near(VehicleDrive.torreGira(0.1, 0.11, 24, 1), 0.11, 1e-9)
end)

test("cano: os limites da ficha e o mínimo por giro, interpolado em volta", function()
	local d, u = VehicleDrive.limiteCano("m48a3", 0)
	assert(d <= -9 + 1e-9 or d >= -9, "")
	local t = VehicleDrive.ART.m48a3.torre
	local antes = t.minPitch
	t.minPitch = { { 0, -9 }, { 150, -9 }, { 180, 2 }, { 210, -9 } }
	local ok, err = pcall(function()
		near((VehicleDrive.limiteCano("m48a3", 0)), -9, 1e-9, "frente")
		near((VehicleDrive.limiteCano("m48a3", math.rad(180))), 2, 1e-9, "atrás, por cima do motor")
		near((VehicleDrive.limiteCano("m48a3", math.rad(165))), -3.5, 1e-9, "no meio")
		near((VehicleDrive.limiteCano("m48a3", math.rad(-180))), 2, 1e-9, "giro negativo dá a volta")
		local dd, uu = VehicleDrive.limiteCano("m48a3", math.rad(180))
		assert(uu >= dd and uu == 19, "a elevação máxima da ficha")
		-- volta de 210° a 360° = 0°
		near((VehicleDrive.limiteCano("m48a3", math.rad(300))), -9, 1e-9, "entre o último e o primeiro")
	end)
	t.minPitch = antes
	assert(ok, err)
	-- a tabela medida no Studio: por cima do motor (180°) o cano não desce além de −4°; à frente, −9°
	near((VehicleDrive.limiteCano("m48a3", math.rad(180))), -4, 1e-9, "medido atrás")
	near((VehicleDrive.limiteCano("m48a3", 0)), -9, 1e-9, "frente livre")
	near((VehicleDrive.limiteCano("m48a3", math.rad(90))), -9, 1e-9, "lado livre")
	near((VehicleDrive.limiteCano("ontos", math.rad(180))), -10, 1e-9, "Ontos livre (medido)")
	d, u = VehicleDrive.limiteCano("lvtp5", 1)
	assert(u == 45, "lvtp5 até 45°")
	local d2, u2 = VehicleDrive.limiteCano("m151", 0)
	assert(d2 == -90 and u2 == 90, "sem torre: livre")
end)

test("servidor e clientes: torre girando nos dois, lugares soldados nela, câmera pelo assento", function()
	local vs = fs.readFile("src/ServerScriptService/Modules/VehicleService.luau")
	for _, t in
		{
			'local onTorre = name == "Cano" or VehicleDrive.naTorre(specId, name)',
			"w.Part0, w.Part1 = torre or mount, s",
			"registrarTorre(model, specId) -- D-196",
			'local yaw = VehicleDrive.torreGira(st.yaw, if type(ay) == "number" then ay else 0, st.degS, dt)',
			"st.m6.Transform = CFrame.Angles(0, yaw, 0)",
			"local down = VehicleDrive.limiteCano(specId, yaw)",
		}
	do
		assert(string.find(vs, t, 1, true), "VehicleService: " .. t)
	end
	local fx = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/VehicleFx.client.luau")
	assert(string.find(fx, "fx.aimYaw = VehicleDrive.torreGira(fx.aimYaw, wantYaw, degS, dt)", 1, true))
	assert(string.find(fx, "VehicleDrive.limiteCano(", 1, true))
	local vc = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/VehicleController.client.luau")
	assert(string.find(vc, "eye = (seat.CFrame * CFrame.new(0, VehicleDrive.EYE_ABOVE_SEAT, 0)).Position", 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
