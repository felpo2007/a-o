--!strict
-- Testes das features "Depois" da Parte 11 (atualizações pós-lançamento). Uso:
--   lune run tests/luau/atualizacoes.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Traps = require(S .. "Traps") :: any
local Logistics = require(S .. "Logistics") :: any
local Tutorial = require(S .. "Tutorial") :: any
local Weather = require(S .. "Weather") :: any
local Rng = require(S .. "Rng") :: any

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

test("chuva: ~1 partida em 4, nunca nos primeiros 10 min, cabe na partida", function()
	local rng = Rng.new(42)
	local roll = function()
		return rng:next()
	end
	local n, total = 0, 4000
	for _ = 1, total do
		local sh = Weather.schedule(75 * 60, roll)
		if sh then
			n += 1
			assert(sh.start >= Weather.EARLIEST_S and sh.finishAt <= 75 * 60, "fora da partida")
			assert(sh.endAt - sh.peakAt >= Weather.MIN_HOLD_S - 1e-9)
		end
	end
	local frac = n / total
	assert(frac > 0.22 and frac < 0.28, string.format("fração com chuva %.3f", frac))
	local always = function()
		return 0
	end
	assert(Weather.schedule(12 * 60, always) == nil, "partida de 12 min não comporta a pancada mínima")
	assert(
		Weather.schedule(20 * 60, always) ~= nil,
		"20 min comportam (o Skirmish fica sem chuva por decisão do MatchService)"
	)
end)

test("chuva: sobe em 60 s, segura, desce em 90 s; efeitos limitados", function()
	local sh = { start = 600, peakAt = 660, endAt = 1200, finishAt = 1290 }
	assert(Weather.intensity(sh, 600) == 0 and Weather.intensity(sh, 630) == 0.5)
	assert(Weather.intensity(sh, 900) == 1 and math.abs(Weather.intensity(sh, 1245) - 0.5) < 1e-9)
	assert(Weather.intensity(sh, 1290) == 0 and Weather.intensity(nil, 900) == 0)
	assert(Weather.sightFactor(1) == 0.5 and Weather.sightFactor(0) == 1)
	assert(math.abs(Weather.footstepVolume(1) - 0.4) < 1e-9 and Weather.mudSpeed(1) == 0.9)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
