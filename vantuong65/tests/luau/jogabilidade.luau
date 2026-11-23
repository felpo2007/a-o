--!strict
-- Lote 103 (D-231): corrida, câmera, avisos e limite do mapa (o relatório do dono, §2 a §4).
-- Uso, a partir de vantuong65/:  lune run tests/luau/jogabilidade.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local Geometry = require("../../src/ReplicatedStorage/Shared/Geometry") :: any
local Movement = require("../../src/ReplicatedStorage/Shared/Movement") :: any

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
local function ler(p: string): string
	return (string.gsub(fs.readFile(p), "\r\n", "\n"))
end
local function has(src: string, s: string): boolean
	return string.find(src, s, 1, true) ~= nil
end
local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"

test("limite do mapa: o ponto de volta fica dentro da área, com a margem", function()
	local b = { minX = 0, maxX = 100, minZ = 0, maxZ = 100 }
	local x, z, d = Geometry.voltaParaArea(b, 130, 50, 10)
	assert(x == 90 and z == 50 and d == 40, "saiu pelo leste")
	x, z, d = Geometry.voltaParaArea(b, -30, -40, 0)
	assert(x == 0 and z == 0 and d == 50, "saiu pelo canto")
	x, z, d = Geometry.voltaParaArea(b, 50, 50, 10)
	assert(x == 50 and z == 50 and d == 0, "já dentro")
end)

test("limite do mapa: o aviso diz o que houve, o tempo e para onde ir", function()
	local s = ler(C .. "BoundaryController.client.luau")
	assert(has(s, '"FORA DA ÁREA"') and has(s, "Geometry.voltaParaArea(MapConfig.Bounds"), "seta")
	assert(has(s, "Volte: siga a seta · %d m"), "rumo e distância")
	assert(has(s, "if n <= 3 then V.RED_HI"), "fim da contagem")
end)

test("corrida: tomar tiro não desliga (só fôlego, parar, mirar, atirar, postura e caído)", function()
	for _, f in { "Modules/CombatService.luau", "Modules/MedicalService.luau" } do
		local s = ler("src/ServerScriptService/" .. f)
		assert(not has(s, 'SetAttribute("Sprinting", false)'), f .. " desliga a corrida")
	end
	local i = ler(C .. "InfantryController.client.luau")
	assert(not has(i, "HealthChanged"), "o cliente não pode parar a corrida pelo dano")
end)

test("câmera: a mesma direção, transição curta, arma junto e movimento reduzido", function()
	assert(Movement.VIEW_TIME.toggle <= 0.3, "transição curta")
	local s = ler(C .. "ThirdPerson.client.luau")
	assert(has(s, "camera.CFrame = CFrame.new(camPos) * rot"), "a rotação não muda")
	assert(has(s, "UiKit.Estilo.reduzMovimento()"), "reduzir movimento")
	local w = ler(C .. "WeaponVisuals.client.luau")
	assert(has(w, "smooth(ViewMode.alpha / Movement.VIEW_THRESHOLD)"), "a arma desce com a câmera")
	-- mirando sempre volta à 1ª pessoa, e caído ou no veículo também: nada fica preso
	local base = {
		want = true,
		allowed = true,
		alive = true,
		customCamera = true,
		seated = false,
		downed = false,
		aiming = false,
		binoculars = false,
	}
	assert(Movement.viewTarget(base, false) == 1)
	for _, k in { "aiming", "seated", "downed", "binoculars" } do
		local c = table.clone(base) :: any
		c[k] = true
		assert(Movement.viewTarget(c, false) == 0, k)
	end
end)

test("avisos: sob fogo, no máximo dois e ganhos curtos", function()
	local s = ler(C .. "Toast.luau")
	assert(has(s, "local MAX_SOB_FOGO = 2") and has(s, "if sobFogo() then MAX_SOB_FOGO else MAX"), "teto")
	assert(has(s, "if sobFogo() then LIFE_SOB_FOGO"), "ganhos")
end)

test("zonas de captura: nada de superfície translúcida no mundo", function()
	local s = ler(C .. "Marcadores.luau")
	assert(has(s, "v41: sem o disco da área no chão"), "sem disco")
	assert(not has(s, "ForceField"), "sem parede de campo de força")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
