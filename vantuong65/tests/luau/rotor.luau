--!strict
-- Helicóptero melhorado (D-199; prompt de jogabilidade, item 18): o rotor pela rotação e pela
-- distância (pás da malha que somem, disco borrado que entra), o UH-34D v3 do Blender (silhueta
-- medida, vidro, interior, rodas onde o desenho mostra), a tabela ART igual à do metricas.json do
-- Blender (cópia versionada em assets/veiculos/uh34d_metricas.json; assets/blender fica fora do Git)
-- e as amarras no código (longe também, vidro transparente, imagem do disco).
-- Uso: lune run tests/luau/rotor.luau
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local S = "../../src/ReplicatedStorage/Shared/"
local RotorVisual = require(S .. "RotorVisual") :: any
local VehicleDrive = require(S .. "VehicleDrive") :: any
local Vehicles = require(S .. "Vehicles") :: any

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

local metricas = serde.decode("json", fs.readFile("assets/veiculos/uh34d_metricas.json")) :: any

test("parado e partindo: pás inteiras e sem disco; na rotação cheia: pás somem e o disco entra", function()
	local p0, d0 = RotorVisual.estado(0, 20)
	assert(p0 == 0 and d0 == 1, "parado")
	local p1, d1 = RotorVisual.estado(0.15, 20)
	assert(p1 == 0 and d1 == 1, "partindo: as pás da malha giram inteiras")
	local p2, d2 = RotorVisual.estado(1, 20)
	assert(p2 == 1, "cheio: pás somem")
	near(d2, 0, 1e-9, "cheio e perto: disco inteiro")
	-- no meio as duas coisas aparecem juntas (sem buraco na troca)
	local pm, dm = RotorVisual.estado(0.5, 20)
	assert(pm > 0 and pm < 1 and dm > 0 and dm < 1, "troca cruzada")
	assert((1 - pm) + (1 - dm) > 0.9, "nada some de uma vez")
	-- monotônico pela rotação
	local lastP, lastD = -1, 2
	for k = 0, 20 do
		local p, d = RotorVisual.estado(k / 20, 50)
		assert(p >= lastP and d <= lastD, "monotônico em " .. k)
		lastP, lastD = p, d
	end
end)

test("longe o disco enfraquece até o mínimo, e nunca some", function()
	local _, perto = RotorVisual.estado(1, 50)
	local _, meio = RotorVisual.estado(1, 300)
	local _, longe = RotorVisual.estado(1, 1500)
	assert(perto < meio and meio < longe, "cai com a distância")
	near(longe, 1 - RotorVisual.LONGE_MIN, 1e-9, "mínimo longe")
	assert(longe < 0.9, "visível longe")
end)

test("o disco gira devagar e só com o rotor girando", function()
	assert(RotorVisual.giro(0) == 0)
	near(RotorVisual.giro(1), RotorVisual.GIRO_HZ * 2 * math.pi, 1e-9)
	-- muito mais devagar que as pás de verdade (a ilusão de borrão, não um estroboscópio)
	assert(RotorVisual.GIRO_HZ < VehicleDrive.HELI.rotorRpm / 60 / 4)
end)

test("UH-34D v3: partes, vidro, teto de triângulos e as rodas onde o desenho mostra", function()
	local partes = metricas.novo.partes
	for _, n in
		{
			"Casco",
			"Interior",
			"Vidro",
			"Cauda",
			"Escotilha_Porta",
			"RotorPrincipal",
			"Pa_1",
			"Pa_2",
			"Pa_3",
			"Pa_4",
			"RotorCauda",
			"Roda_E",
			"Roda_D",
			"Roda_Cauda",
		}
	do
		assert(partes[n], "sem a parte " .. n)
	end
	assert(metricas.novo.triangulos <= 20000, "herói até 20 mil triângulos (D-66)")
	assert(metricas.novo.triangulos > 8000, "mais detalhe que o v2 (4.742)")
	-- referencial do Roblox: nariz em −x. A bequilha bem atrás da roda principal (desenho: 8,95 m)
	local rp, rc = partes.Roda_E.pivo_studs_roblox, partes.Roda_Cauda.pivo_studs_roblox
	near((rc[1] - rp[1]) * 0.28, 8.95, 0.05, "entre-eixos")
	-- a cabine alta (desenho: teto a 3,86 m; no modelo 4,08 m): o olho do piloto a 3,57 m do chão
	-- (3,19 m no v2)
	local eye, box = metricas.art_novo.eyes.driver, metricas.art_novo.box
	local olhoM = (eye[2] + box[2] / 2) * 0.28
	near(olhoM, 3.57, 0.02, "olho do piloto do chão")
	-- o soldado R15 sentado, medido no Studio com 0,38 m de descida (do chão das rodas): quadril
	-- 2,68, pés 2,19 e capacete 3,97 m. Cada metro a mais de descida baixa tudo junto
	local drop = VehicleDrive.ART.uh34d.seatDrop.driver * 0.28
	local d = drop - 0.38
	local quadril, pes, capacete = 2.68 - d, 2.19 - d, 3.97 - d
	assert(quadril >= 2.58 and quadril <= 2.63, "quadril no estofado (topo 2,58 m): " .. quadril)
	assert(pes >= 2.09, "pés acima do fundo do fosso (2,08 m): " .. pes)
	assert(capacete <= 3.92, "capacete sob o teto (4,04 m sobre a cabeça): " .. capacete)
	assert(VehicleDrive.ART.uh34d.seatDrop.copilot == VehicleDrive.ART.uh34d.seatDrop.driver)
	local s2 = metricas.conferencia.soldado_2m.olhos
	for _, seat in { "driver", "copilot" } do
		assert(s2[seat].folga_cabeca_ao_teto_m > 0.1, seat .. ": soldado de 2 m com folga no teto")
		assert(s2[seat].dentro_da_malha == false, seat .. ": olho fora da malha")
	end
end)

test("a tabela ART do jogo é a do metricas.json (box, rotores, olhos, tropa e juntas)", function()
	local a, m = VehicleDrive.ART.uh34d, metricas.art_novo
	for k = 1, 3 do
		near(a.box[k], m.box[k], 1e-6, "box " .. k)
	end
	for _, r in { "rotor", "tail" } do
		for _, c in { "x", "y", "z", "r" } do
			near(a[r][c], m[r][c], 1e-6, r .. "." .. c)
		end
	end
	for seat, e in m.eyes do
		for k = 1, 3 do
			near(a.eyes[seat][k], e[k], 1e-6, "olho " .. seat)
		end
	end
	for _, c in { "x0", "dx", "y", "z" } do
		near(a.riders[c], m.riders[c], 1e-6, "tropa " .. c)
	end
	for _, n in { "RotorPrincipal", "RotorCauda", "Escotilha_Porta" } do
		local p = metricas.novo.partes[n].pivo_studs_roblox
		for k = 1, 3 do
			near(a.pivots[n][k], p[k], 1e-6, "junta " .. n)
		end
	end
	assert(Vehicles.modelKey("uh34d") == "uh34d_v3", "o jogo usa o v3")
end)

test("amarras: longe também, vidro transparente, imagem do disco e o evento", function()
	local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
	local vfx = fs.readFile(C .. "VehicleFx.client.luau")
	for _, t in
		{
			"spinRotors(fx, dt)",
			"drawRotor(fx, dt) -- D-199: longe também",
			"RotorVisual.estado(rotor, fx.dist * M)",
			"RotorDisco.esconder(fx.pas, 0)",
			"setupRotor(novo)",
		}
	do
		assert(string.find(vfx, t, 1, true), "VehicleFx: " .. t)
	end
	-- o rotor gira e desenha antes do corte de "só perto"
	local a = string.find(vfx, "drawRotor(fx, dt) -- D-199", 1, true) :: number
	local b = string.find(vfx, "if not fx.visual then\n\t\t\tcontinue", a, true)
	assert(b and b > a, "drawRotor antes do corte de perto")
	local he = fs.readFile(C .. "HeliEvento.client.luau")
	assert(string.find(he, "RotorVisual.estado(ROTOR,", 1, true) and string.find(he, "RotorDisco.novo(", 1, true))
	local rd = fs.readFile(C .. "RotorDisco.luau")
	assert(string.find(rd, '"Img_rotor_borrao"', 1, true) and string.find(rd, "LocalTransparencyModifier", 1, true))
	assert(string.find(rd, "p.CanQuery = false", 1, true), "o disco não barra raio")
	local al = fs.readFile("src/ServerScriptService/Modules/AssetLoader.luau")
	assert(string.find(al, 'string.sub(d.Name, 1, 5) == "Vidro"', 1, true))
	assert(string.find(al, "d.CanQuery = false", 1, true) and string.find(al, "d.DoubleSided = true", 1, true))
	local iu = fs.readFile("src/ServerScriptService/Modules/ImagensUi.luau")
	assert(string.find(iu, '"rotor_borrao"', 1, true))
	local ids = fs.readFile("src/ReplicatedStorage/Shared/AssetIds.luau")
	assert(string.find(ids, "rotor_borrao = %d+"), "AssetIds.Images.rotor_borrao")
	assert(fs.isFile("assets/rotor/rotor_borrao.png"), "textura do disco")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
