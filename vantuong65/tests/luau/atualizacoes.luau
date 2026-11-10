--!strict
-- Testes das features "Depois" da Parte 11 (atualizações pós-lançamento). Uso:
--   lune run tests/luau/atualizacoes.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Traps = require(S .. "Traps") :: any
local Logistics = require(S .. "Logistics") :: any
local Tutorial = require(S .. "Tutorial") :: any

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

test("armadilhas: só o lado inimigo dispara, e só depois de armada", function()
	assert(Traps.canTrigger("VC", "US", 10, 10) and not Traps.canTrigger("VC", "US", 10, 9.9))
	assert(not Traps.canTrigger("VC", "VC", 0, 100), "o VC não pisa na própria armadilha")
	assert(not Traps.canTrigger("VC", nil, 0, 100))
end)

test("armadilhas: andar com cuidado reduz a chance; detectada não dispara", function()
	assert(Traps.triggerChance(3, false) == 1)
	assert(Traps.triggerChance(0.4, false) == 0.5)
	assert(Traps.triggerChance(0.05, false) == 0)
	assert(Traps.triggerChance(3, true) == 0)
end)

test("armadilhas: só o engenheiro inimigo detecta (perto e devagar) e desarma", function()
	assert(Traps.detects("engineer", "US", "VC", 5, 0.8))
	assert(not Traps.detects("engineer", "US", "VC", 8, 0.8), "longe demais")
	assert(not Traps.detects("engineer", "US", "VC", 5, 3), "correndo não percebe")
	assert(not Traps.detects("rifleman", "US", "VC", 2, 0), "só o engenheiro")
	assert(not Traps.detects("engineer", "VC", "VC", 2, 0), "a própria armadilha não conta")
	assert(Traps.canDisarm("engineer", "US", "VC", true) and not Traps.canDisarm("engineer", "US", "VC", false))
end)

test("armadilhas: só o sapador constrói, com custo e limite", function()
	for _, id in { "punji", "tripwire" } do
		local b = Logistics.BUILDS[id]
		assert(b and b.role.sapper and not b.role.engineer and not b.role.squad_leader, id)
		assert(b.cost > 0 and b.limit > 0 and b.nearSupplyM == nil)
		assert(Traps.KINDS[id], "regra de " .. id)
	end
	local s = Logistics.new()
	local ok = Logistics.canBuild(s, "VC", "sapper", "punji", 0, 100, math.huge)
	assert(ok, "sapador com suprimento e sem inimigo perto deveria construir")
	assert(not Logistics.canBuild(s, "VC", "rifleman", "punji", 0, 100, math.huge))
	assert(not Logistics.canBuild(s, "VC", "sapper", "punji", 0, 10, math.huge), "inimigo a 10 m")
end)

test("tutorial do sapador ensina as armadilhas; o do engenheiro, a detecção", function()
	local function has(role: string, word: string): boolean
		for _, st in Tutorial.steps(role) do
			if string.find(st.text, word, 1, true) then
				return true
			end
		end
		return false
	end
	assert(has("sapper", "armadilhas") and has("engineer", "armadilhas inimigas"))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
