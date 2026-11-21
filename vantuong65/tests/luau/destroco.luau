--!strict
-- Explosão e destroço dos veículos (D-197; prompt de jogabilidade, item 16): porte, estágios do dano,
-- quem está dentro, a queima do destroço e as amarras no código. Uso: lune run tests/luau/destroco.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local VeiculoDano = require(S .. "VeiculoDano") :: any
local Vehicles = require(S .. "Vehicles") :: any
local Medical = require(S .. "Medical") :: any

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

test("porte pela massa: jipe e carro leves, caminhão e Ontos médios, M48 e LVTP-5 pesados", function()
	local want = {
		m151 = "leve",
		peugeot403 = "leve",
		m35 = "medio",
		ontos = "medio",
		uh34d = "medio",
		m48a3 = "pesado",
		lvtp5 = "pesado",
	}
	for id, p in want do
		local spec = Vehicles.SPECS[id]
		assert(spec, id)
		assert(
			VeiculoDano.porte(spec.massKg) == p,
			string.format("%s (%d kg): %s", id, spec.massKg, VeiculoDano.porte(spec.massKg))
		)
	end
	-- maior o veículo, maior a explosão, mais pedaços, som mais grave e destroço fumegando mais
	local L, Me, P = VeiculoDano.EXPLOSAO.leve, VeiculoDano.EXPLOSAO.medio, VeiculoDano.EXPLOSAO.pesado
	assert(L.escala < Me.escala and Me.escala < P.escala)
	assert(L.fragmentos < Me.fragmentos and Me.fragmentos < P.fragmentos and P.fragmentos <= 12, "pedaços limitados")
	assert(L.tom > Me.tom and Me.tom > P.tom)
	assert(P.fumacaS < 30, "o destroço some aos 30 s no servidor")
end)

test("estágios: inteiro, fumaça (≤ 60), fogo (≤ 25) e destroço", function()
	assert(VeiculoDano.estagio(100, false) == "inteiro" and VeiculoDano.estagio(nil, false) == "inteiro")
	assert(VeiculoDano.estagio(60, false) == "fumaca" and VeiculoDano.estagio(26, false) == "fumaca")
	assert(VeiculoDano.estagio(25, false) == "fogo" and VeiculoDano.estagio(-10, false) == "fogo")
	assert(VeiculoDano.estagio(100, true) == "destroco", "destruído vale mais que a integridade")
end)

test("quem está dentro: fechado morre; aberto se fere sem cair e sai", function()
	local C = Medical.C
	local fechado = VeiculoDano.ferimento(false, false)
	assert(fechado.mata and fechado.zona == "head" and fechado.energiaJ >= C.headKillJ, "fechado")
	local s = Medical.new()
	assert(Medical.applyHit(s, fechado.zona, fechado.energiaJ, 0.5, 0) == "killed", "a regra médica mata")
	local aberto = VeiculoDano.ferimento(true, false)
	assert(not aberto.mata and aberto.zona == "torso" and aberto.energiaJ < C.torsoDownJ, "aberto")
	local s2 = Medical.new()
	local r = Medical.applyHit(s2, aberto.zona, aberto.energiaJ, 0.5, 0)
	assert(r == "wounded" and s2.health > 0, "ferido de pé: " .. r)
	-- helicóptero: ninguém sobra (a queda)
	assert(VeiculoDano.ferimento(true, true).mata)
	-- os 3000 J no tronco de antes só derrubavam (o ferido ficava sentado no destroço)
	assert(Medical.applyHit(Medical.new(), "torso", 3000, 0.5, 0) == "downed")
end)

test("destroço: a fumaça fica, o fogo some antes, tudo acaba no fim", function()
	local f0, g0 = VeiculoDano.queima(0, 25)
	assert(f0 == 1 and g0 == 1)
	local f1, g1 = VeiculoDano.queima(16, 25)
	assert(g1 == 0 and f1 > 0.5, string.format("fumaça %.2f fogo %.2f aos 16 s", f1, g1))
	local f2, g2 = VeiculoDano.queima(25, 25)
	assert(f2 == 0 and g2 == 0)
	local last = 2
	for t = 0, 25, 1 do
		local f = VeiculoDano.queima(t, 25)
		assert(f <= last, "só diminui")
		last = f
	end
end)

test("servidor: destruição uma vez, propulsão parada, sobreviventes fora, sem juntas quebradas", function()
	local vs = fs.readFile("src/ServerScriptService/Modules/VehicleService.luau")
	local a = string.find(vs, "local function destroyVehicle(model: Model)", 1, true)
	assert(a, "destroyVehicle")
	local body = string.sub(vs, a, string.find(vs, "\nend\n", a, true) :: number)
	for _, t in
		{
			'if model:GetAttribute("Destroyed") then',
			'model:SetAttribute("Destroyed", true)',
			'for _, n in { "DriveVelocity", "DriveAttitude" } do',
			'local f = VeiculoDano.ferimento(s:GetAttribute("Open") == true, heli)',
			"hum.Sit = false",
			"(VehicleService :: any).botLeave(hum.Parent)",
			-- o assento antes da peça (Seat é BasePart: antes nunca era desligado)
			'if d:IsA("Seat") then\n\t\t\td.Disabled = true',
			'ExplosionService.detonate("veiculo", chassis.Position)',
		}
	do
		assert(string.find(body, t, 1, true), "destroyVehicle: " .. t)
	end
	-- o dano das explosões é próprio (sem o Explosion do Roblox, que quebra juntas em volta)
	local ex = fs.readFile("src/ServerScriptService/Modules/ExplosionService.luau")
	assert(not string.find(ex, 'Instance.new("Explosion")', 1, true))
	assert(string.find(vs, 'if want == "destruir" then', 1, true), "gancho do Studio")
	-- o efeito é do cliente, pelo atributo
	local cl = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/VeiculoDano.client.luau")
	for _, t in
		{
			'model:GetAttributeChangedSignal("Destroyed"):Connect(function()',
			"explode(model, chassis)",
			"for _ = 1, E.fragmentos do",
			"VeiculoDano.queima(os.clock() - t0, w.fumacaS)",
		}
	do
		assert(string.find(cl, t, 1, true), "VeiculoDano.client: " .. t)
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
