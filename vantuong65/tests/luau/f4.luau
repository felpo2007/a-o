--!strict
-- Testes da F4 (Lune): morteiro, grade e correção, dispersão, explosivos, veículos, logística,
-- helicóptero. Uso: lune run tests/luau/f4.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Explosive = require(S .. "Explosive")
local FireSupport = require(S .. "FireSupport")
local HeliModel = require(S .. "HeliModel")
local Logistics = require(S .. "Logistics")
local Mortar = require(S .. "Mortar")
local Rng = require(S .. "Rng")
local Vehicles = require(S .. "Vehicles")

local ORIGIN = { e = 270200.0, n = 1692400.0 }
local M = 0.28

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

test("morteiro: k calibrado reproduz o alcance máximo da fonte (82-BM-37: 3.040 m)", function()
	for _, id in { "vc_82", "us_81" } do
		local s = Mortar.spec(id)
		assert(s, id)
		local r = Mortar.maxRange(s.v0, s.k :: number)
		near(r, s.maxRangeM, s.maxRangeM * 0.01, id)
		print(
			string.format(
				"       %s: v0 %d m/s, k = %.3e 1/m, alcance máx. calculado %.0f m",
				id,
				s.v0,
				s.k :: number,
				r
			)
		)
	end
end)

test("morteiro: ramo alto, menor carga que alcança, tempo de voo cresce com a distância", function()
	local lastTof = 0
	for _, r in { 300, 800, 1500, 2500 } do
		local elev, tof, charge = Mortar.solve("vc_82", r)
		assert(elev and tof and charge, "sem solução a " .. r)
		assert(elev >= Mortar.MIN_ELEV - 1e-6 and elev <= Mortar.MAX_ELEV + 1e-6, "fora do ramo alto")
		local sp = Mortar.spec("vc_82") :: any
		local check = Mortar.simulate(sp.v0 * Mortar.CHARGES[charge], elev, sp.k)
		near(check, r, 2, "alcance resolvido")
		print(
			string.format("       82 mm a %d m: carga %d, %.0f mils, voo %.1f s", r, charge, Mortar.toMils(elev), tof)
		)
		lastTof = tof
	end
	assert(lastTof > 10, "voo longo a 2,5 km")
	assert(Mortar.solve("vc_82", 3500) == nil, "além do alcance máximo")
	assert(Mortar.solve("vc_82", 50) == nil, "aquém do mínimo")
end)

test("grade: 'BS 700928' = An Cường (2) e ida e volta local↔grade", function()
	local e, n, p = FireSupport.parseGrid("BS 700928")
	assert(e == 270000 and n == 1692800 and p == 100)
	local x, z = FireSupport.gridToLocal("BS 7003 9285", ORIGIN, M)
	assert(x and z)
	-- célula de 10 m: centro E 270035, N 1692855 → x = -165/0,28, z = -455/0,28
	near(x, -165 / M, 0.01)
	near(z, -455 / M, 0.01)
	assert(FireSupport.localToGrid(x, z, ORIGIN, M, 8) == "BS 7003 9285")
	assert(FireSupport.parseGrid("BS 70092") == nil, "número ímpar de algarismos")
end)

test("correção do observador: 'mais 100, direita 50' no eixo OT", function()
	local along, right = FireSupport.parseCorrection("Mais 100, direita 50")
	assert(along == 100 and right == 50)
	local a2, r2 = FireSupport.parseCorrection("drop 50 left 25")
	assert(a2 == -50 and r2 == -25)
	-- observador ao sul do alvo, olhando para o norte (-z): mais = norte, direita = leste
	local x, z = FireSupport.adjust(0, 0, 0, 1000, 100, 50)
	near(x, 50, 1e-9)
	near(z, -100, 1e-9)
	-- observador a oeste olhando para leste: direita = sul (+z)
	local x2, z2 = FireSupport.adjust(0, 0, -1000, 0, 0, 30)
	near(x2, 0, 1e-9)
	near(z2, 30, 1e-9)
end)

test("dispersão: ~50% dos impactos dentro do CEP (10.000 sorteios)", function()
	local rnd = Rng.new(1965)
	local inside = 0
	for _ = 1, 10000 do
		local dx, dz = FireSupport.dispersion(rnd:next(), rnd:next(), 40)
		if math.sqrt(dx * dx + dz * dz) <= 40 then
			inside += 1
		end
	end
	near(inside / 10000, 0.5, 0.02, "fração dentro do CEP")
end)

test("habilidades: papel, facção, recarga e suprimento", function()
	local cd = {}
	assert(FireSupport.canUse("us_naval_5in", "US", "commander", 200, cd, 0))
	assert(not FireSupport.canUse("us_naval_5in", "VC", "commander", 200, cd, 0))
	assert(not FireSupport.canUse("us_naval_5in", "US", "rifleman", 200, cd, 0))
	assert(not FireSupport.canUse("us_naval_5in", "US", "commander", 10, cd, 0))
	cd.us_naval_5in = 100
	local ok, why = FireSupport.canUse("us_naval_5in", "US", "commander", 200, cd, 50)
	assert(not ok and why and string.find(why, "recarga"))
	local pts = FireSupport.impacts(FireSupport.ABILITIES.us_air_strike, 0, 0, 0, M, function()
		return 0
	end)
	assert(#pts == 4)
	-- rumo norte: a 1ª bomba cai mais ao sul (+z) e a última 120 m ao norte
	near(pts[1].z - pts[4].z, 120 / M, 1e-6, "linha de 120 m rumo norte")
end)

test("explosivo: letal perto, ferimento cai com a distância, cobertura protege", function()
	assert(Explosive.effect("mortar_81", 3, 1, 0.99) == "lethal")
	assert(Explosive.effect("mortar_81", 40, 1, 0) == nil)
	local hitsOpen, hitsCover = 0, 0
	for i = 0, 999 do
		local u = i / 1000
		if Explosive.effect("mortar_81", 15, 1, u) then
			hitsOpen += 1
		end
		if Explosive.effect("mortar_81", 15, Explosive.COVERED, u) then
			hitsCover += 1
		end
	end
	assert(hitsOpen > hitsCover * 3, "cobertura reduz baixas")
	local b = Explosive.newBudget(3)
	assert(Explosive.allowCrater(b, 0) and Explosive.allowCrater(b, 1) and Explosive.allowCrater(b, 2))
	assert(not Explosive.allowCrater(b, 3), "orçamento por minuto")
	assert(Explosive.allowCrater(b, 61), "libera depois de 60 s")
end)

test("veículos: velocidade máxima por chão, M48 não entra na água, LVTP-5 navega a 11 km/h", function()
	local function run(id: string, surface: string, secs: number): number
		local st = { v = 0 }
		for _ = 1, secs * 20 do
			Vehicles.drive(Vehicles.SPECS[id], st, 1, surface, 0.05)
		end
		return st.v * 3.6
	end
	near(run("m48a3", "road", 120), 48, 0.5, "M48 na estrada")
	assert(run("m48a3", "paddy", 120) < 48 * 0.36, "lama do arrozal")
	near(run("lvtp5", "water", 300), 11, 0.5, "LVTP-5 na água")
	assert(run("m48a3", "water", 30) < 0.1, "M48 não navega")
	-- relação peso/potência: Ontos (16,9 hp/t) e M48 (16,7 hp/t) aceleram parecido; ambos < 48 km/h em 5 s
	local t5o, t5m = run("ontos", "road", 5), run("m48a3", "road", 5)
	print(string.format("       0–5 s na estrada: Ontos %.1f km/h, M48A3 %.1f km/h", t5o, t5m))
	assert(t5o < 48 and t5m < 48)
end)

test("blindagem: glacis do M48 (110 mm a 60° = 220 mm efetivos) vs. PG-2 e 106 mm", function()
	local glacis = (Vehicles.SPECS.m48a3.armor :: any).front
	near(Vehicles.effectiveMm(glacis.mm, glacis.slopeDeg), 220, 0.5, "linha de visada")
	assert(not Vehicles.penetrates(Vehicles.PEN.pg2, glacis, 0, 0.5), "PG-2 não fura o glacis")
	assert(Vehicles.penetrates(Vehicles.PEN.heat_106, glacis, 0, 0.5), "106 mm fura")
	assert(Vehicles.penetrates(Vehicles.PEN.pg2, (Vehicles.SPECS.m48a3.armor :: any).side, 0, 0.5), "lado")
	assert(Vehicles.zoneFromLocal(0, 0, 1) == "front" and Vehicles.zoneFromLocal(1, 0, 0) == "side")
	assert(Vehicles.zoneFromLocal(0, -0.9, 0.1) == "top")
end)

test("logística: renda por minuto, gasto e validação de construção", function()
	local s = Logistics.new()
	for _ = 1, 600 do
		Logistics.tick(s, 0.1, { US = 2, VC = 1 })
	end
	near(s.supply.US, Logistics.START + 20 + 12, 1, "1 min de renda EUA")
	near(s.supply.VC, Logistics.START + 16 + 8, 1, "1 min de renda VC")
	assert(Logistics.spend(s, "US", 50))
	assert(not Logistics.spend(s, "US", 10000))
	assert(Logistics.canBuild(s, "US", "squad_leader", "garrison", 0, 300, 20))
	local ok, why = Logistics.canBuild(s, "US", "squad_leader", "garrison", 0, 100, 20)
	assert(not ok and why == "inimigos perto demais")
	assert(not Logistics.canBuild(s, "US", "rifleman", "garrison", 0, 300, 20))
	assert(not Logistics.canBuild(s, "US", "squad_leader", "garrison", 0, 300, 80), "sem caixote")
end)

test("UH-34D: calibração reproduz os tetos de pairar e a velocidade máxima da ficha", function()
	local h = HeliModel.SPEC
	local function isa(ft: number)
		local m = ft * 0.3048
		return HeliModel.atmosphere(15 - 0.0065 * m, m)
	end
	near(HeliModel.maxHoverKg(1000, isa(h.hoverOGEft)), h.grossKg, 5, "teto OGE 5.500 ft")
	near(HeliModel.maxHoverKg(h.igeZ, isa(h.hoverIGEft)), h.grossKg, 5, "teto IGE 9.600 ft")
	local sl = isa(0)
	near(HeliModel.powerRequired(h.grossKg, h.maxSpeedMs, 1000, sl), HeliModel.powerAvailable(sl), 500, "122 mph")
	near(HeliModel.climbRate(HeliModel.powerAvailable(sl), h.grossKg, 0, 1000, sl), h.vClimbMs, 0.01, "600 ft/min")
	local c = HeliModel.calibration()
	print(
		string.format("       calibrado: expoente de perda %.2f, perfil %.0f hp, f = %.2f m²", c.n, c.p0 / 745.7, c.f)
	)
end)

test("UH-34D: efeito solo, sustentação de translação, calor e carga (modelo de momento)", function()
	local h = HeliModel.SPEC
	local hot = HeliModel.atmosphere(35)
	local cool = HeliModel.atmosphere(15)
	local mtow = h.maxKg
	local pOGE = HeliModel.powerRequired(mtow, 0, 1000, hot)
	local pIGE = HeliModel.powerRequired(mtow, 0, h.igeZ, hot)
	local pETL = HeliModel.powerRequired(mtow, 20, 1000, hot)
	assert(pIGE < pOGE, "efeito solo reduz a potência")
	assert(pETL < pOGE, "sustentação de translação a 20 m/s")
	assert(HeliModel.powerAvailable(hot) < HeliModel.powerAvailable(cool), "calor tira potência")
	assert(HeliModel.powerRequired(h.emptyKg + 800, 0, 1000, hot) < pOGE, "menos carga, menos potência")
	print(
		string.format(
			"       MTOW a 35 °C: pairar fora do efeito solo %.0f hp, no efeito solo %.0f hp, a 20 m/s %.0f hp; disponível %.0f hp",
			pOGE / 745.7,
			pIGE / 745.7,
			pETL / 745.7,
			HeliModel.powerAvailable(hot) / 745.7
		)
	)
	print(
		string.format(
			"       peso máx. para pairar a 35 °C: fora do efeito solo %.0f kg; no efeito solo %.0f kg",
			HeliModel.maxHoverKg(1000, hot),
			HeliModel.maxHoverKg(h.igeZ, hot)
		)
	)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
