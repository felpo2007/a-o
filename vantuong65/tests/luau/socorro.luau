--!strict
-- D-236: quem o soldado socorre e o que a tecla faz. Uso: lune run tests/luau/socorro.luau
local process = require("@lune/process")

local R = require :: any
local Medical = R("../../src/ReplicatedStorage/Shared/Medical")
local Socorro = R("../../src/ReplicatedStorage/Shared/Socorro")
local Weapons = R("../../src/ReplicatedStorage/Shared/Weapons")

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

local function aliado(p: { [string]: any }): any
	return {
		downed = p.downed == true,
		hurt = p.hurt == true,
		bleeding = p.bleeding == true,
		frac = p.frac or 1,
		distM = p.distM or 2,
		angDeg = p.angDeg or 0,
	}
end

test("o mais urgente vem primeiro, mesmo mais longe e fora da mira", function()
	local caido = aliado({ downed = true, distM = 4, angDeg = 60 })
	local sangra = aliado({ bleeding = true, hurt = true, distM = 1, angDeg = 0 })
	local ferido = aliado({ hurt = true, distM = 1, angDeg = 0 })
	assert(Socorro.nota(caido) < Socorro.nota(sangra), "caído antes de quem sangra")
	assert(Socorro.nota(sangra) < Socorro.nota(ferido), "quem sangra antes do ferido")
end)

test("entre dois iguais, vale quem está na mira", function()
	local naMira = aliado({ hurt = true, distM = 3, angDeg = 2 })
	local fora = aliado({ hurt = true, distM = 3, angDeg = 40 })
	assert(Socorro.nota(naMira) < Socorro.nota(fora))
end)

test("o médico reanima e trata; o soldado faz curativo e ouve o motivo do que não pode", function()
	local caido = aliado({ downed = true })
	local ferido = aliado({ hurt = true })
	assert(Socorro.acao(caido, true, 0).op == "revive")
	assert(Socorro.acao(ferido, true, 0).op == "treat")
	assert(Socorro.acao(ferido, false, 2).op == "bandage")
	local nega = Socorro.acao(caido, false, 2)
	assert(nega.op == nil and nega.motivo == "Só o médico reanima")
	local sem = Socorro.acao(ferido, false, 0)
	assert(sem.op == nil and sem.motivo == "Sem curativos")
	assert(Socorro.acao(aliado({}), true, 5) == nil, "quem está inteiro não pede nada")
end)

test("a cruz: caído para todos até 35 m, ferido só para o médico até 70 m", function()
	assert(Socorro.marca(aliado({ downed = true, distM = 30 }), false))
	assert(not Socorro.marca(aliado({ downed = true, distM = 40 }), false))
	assert(Socorro.marca(aliado({ downed = true, distM = 60 }), true))
	assert(not Socorro.marca(aliado({ hurt = true, distM = 5 }), false))
	assert(Socorro.marca(aliado({ hurt = true, distM = 60 }), true))
	assert(not Socorro.marca(aliado({ hurt = true, distM = 80 }), true))
end)

test("cuidar ficou mais rápido e o médico devolve a vida inteira", function()
	local C = Medical.C
	assert(C.bandageOther == 3 and C.medicTreat == 5 and C.reviveTime == 5)
	local s = Medical.new(false)
	s.health = 20
	assert(Medical.treat(s) and s.health == 100, "tratar leva a 100")
	local fraco = Medical.new(false, 0.9)
	fraco.health = 10
	assert(Medical.treat(fraco) and fraco.health <= fraco.maxHealth, "não passa da vida máxima")
end)

test("D-236: a M16 nasce no automático e o seletor passa para semi", function()
	local m16 = Weapons.get("m16")
	assert(m16.modes[1] == "auto" and m16.modes[2] == "semi")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
