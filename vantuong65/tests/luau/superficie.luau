--!strict
-- Testes do piso e da granada no chão (D-191; Shared/Superficie e Shared/GrenadePhysics).
-- Uso: lune run tests/luau/superficie.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local S = "../../src/ReplicatedStorage/Shared/"
local Superficie = require(S .. "Superficie") :: any
local GrenadePhysics = luau.load(fs.readFile("src/ReplicatedStorage/Shared/GrenadePhysics.luau"), {
	debugName = "GrenadePhysics",
	environment = {
		Vector3 = roblox.Vector3,
		require = function(_: any): any
			return Superficie
		end,
	},
})() :: any
local Vector3 = roblox.Vector3 :: any

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

test("piso: terreno, peças, arrozal, dique e ponte", function()
	local of = Superficie.of
	assert(of(true, "Grass") == "grass" and of(true, "LeafyGrass") == "grass" and of(true, "Ground") == "grass")
	assert(of(true, "Mud") == "mud" and of(true, "Sand") == "sand" and of(true, "Water") == "water")
	assert(of(true, "Rock") == "stone" and of(true, "Concrete") == "stone")
	assert(of(true, "Algo") == "grass", "terreno desconhecido vira grama")
	assert(of(false, "Wood") == "wood" and of(false, "WoodPlanks") == "wood", "madeira de casa")
	assert(of(false, "Metal") == "metal" and of(false, "DiamondPlate") == "metal", "veículo")
	assert(of(false, "Brick") == "stone" and of(false, "Fabric") == "sand", "tijolo e saco de areia")
	assert(of(false, "SmoothPlastic", "Agua", "PaddyWater") == "paddy", "arrozal do gerador")
	assert(of(false, "SmoothPlastic", "Dike") == "mud", "dique")
	-- a ponte de toras vale mais que o material da peça e que o rio embaixo
	assert(of(false, "Water", "Tora", nil, true) == "wood", "ponte sobre o rio")
	for _, s in { "grass", "mud", "paddy", "water", "sand", "wood", "metal", "stone" } do
		assert(type(Superficie.STEP[s]) == "string", "som de passo: " .. s)
	end
	-- os passos que faltam ficam listados (sem inventar asset)
	local ids = fs.readFile("src/ReplicatedStorage/Shared/AssetIds.luau")
	for _, k in Superficie.MISSING_STEPS do
		assert(not string.find(ids, k .. " =", 1, true), k .. " já existe: tire do PLACEHOLDER")
	end
end)

test("piso: na divisa só troca com duas leituras seguidas", function()
	local st = Superficie.newStable()
	assert(Superficie.stable(st, "grass") == "grass", "primeira leitura vale")
	assert(Superficie.stable(st, "wood") == "grass", "uma leitura de madeira não troca")
	assert(Superficie.stable(st, "grass") == "grass")
	assert(Superficie.stable(st, "wood") == "grass")
	assert(Superficie.stable(st, "wood") == "wood", "duas seguidas trocam")
	assert(Superficie.stable(st, "mud") == "wood")
	assert(Superficie.stable(st, "sand") == "wood", "leituras diferentes não somam")
	assert(Superficie.stable(st, "sand") == "sand")
end)

test("granada: o chão freia conforme o piso; quique nunca acelera", function()
	local D = GrenadePhysics.groundDamp
	assert(D("paddy") < D("mud") and D("mud") < D("sand") and D("sand") < D("grass"), "lama segura")
	assert(D("grass") < D("wood") and D("wood") <= D("metal"), "madeira e metal deixam rolar")
	assert(D("??") == 0.72, "piso desconhecido: o freio de antes")
	for _, s in { "grass", "mud", "paddy", "water", "sand", "wood", "metal", "stone" } do
		local d, e = D(s), GrenadePhysics.restitution(s)
		assert(d > 0 and d < 1 and e >= 0 and e < 1, s)
	end
	-- 6 m/s rolando na grama para em ~1 s (a 0,1 s por freio)
	local v, t = 6, 0
	while v > 0.3 do
		v *= D("grass")
		t += 0.1
	end
	assert(t < 1.2, string.format("grama: para em %.1f s", t))
	-- quique numa parede: volta pela normal, perde energia, a parte ao longo continua
	local n = Vector3.new(-1, 0, 0)
	local vin = Vector3.new(20, -2, 3)
	local out = GrenadePhysics.bounce(vin, n, GrenadePhysics.restitution("stone"))
	assert(out.X < 0, "volta da parede")
	assert(out.Magnitude < vin.Magnitude, "nunca sai mais rápida")
	local same = GrenadePhysics.bounce(Vector3.new(-5, 0, 0), n, 0.5)
	assert(same.X == -5, "já saindo da face: não mexe")
end)

test("granada: o servidor varre o caminho e freia pelo piso; sem metragem na tela", function()
	local fsv = fs.readFile("src/ServerScriptService/Modules/FieldService.luau")
	for _, t in
		{
			"GrenadePhysics.groundDamp(GrenadePhysics.surfaceOf(hit.Instance, hit.Material))",
			"local hit = workspace:Raycast(last, step, params)",
			"GrenadePhysics.bounce(core.AssemblyLinearVelocity, hit.Normal",
		}
	do
		assert(string.find(fsv, t, 1, true), "FieldService: " .. t)
	end
	-- uma explosão: o modelo sai antes do detonate (colisões não detonam de novo)
	local destroy = string.find(fsv, "m:Destroy()\n\t\t\tExplosionService.detonate(", 1, true)
	assert(destroy, "uma detonação por granada")
	local aviso = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/AvisoGranada.client.luau")
	assert(not string.find(aviso, 'string.format("%d m"', 1, true), "o número da distância saiu")
	assert(string.find(aviso, "dist.Visible = false -- D-191: sem metragem", 1, true))
	local audio = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/AudioController.client.luau")
	assert(string.find(audio, 'Superficie.stable(st, s or "grass")', 1, true), "passos com a divisa estável")
	assert(string.find(audio, "if below > AIR_STUDS then", 1, true), "sem passo no ar")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
