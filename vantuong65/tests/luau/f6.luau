--!strict
-- Testes da F6 (Lune): modo Offensive, rotação de modos e tutorial.
-- Uso: lune run tests/luau/f6.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Capture = require(S .. "Capture") :: any
local Offensive = require(S .. "Offensive") :: any
local BotBrain = require(S .. "BotBrain") :: any

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

local function at(sector: number, us: number, vc: number): { { US: number, VC: number } }
	local c = {}
	for i = 1, 5 do
		c[i] = { US = 0, VC = 0 }
	end
	c[sector] = { US = us, VC = vc }
	return c
end

-- roda segundo a segundo até a condição (ou o limite) e devolve os eventos
local function run(st: any, counts: any, seconds: number): { any }
	local all = {}
	for _ = 1, seconds do
		for _, ev in Offensive.step(st, counts, 1) do
			table.insert(all, ev)
		end
	end
	return all
end

local function has(evs: { any }, kind: string, sector: number?): boolean
	for _, e in evs do
		if e.kind == kind and (sector == nil or e.sector == sector) then
			return true
		end
	end
	return false
end

test("Offensive: EUA só na praia (S5), VC nos outros 4, só a frente (S4) ativa", function()
	local st = Offensive.new()
	assert(st.capture.owner[5] == "US")
	for i = 1, 4 do
		assert(st.capture.owner[i] == "VC")
	end
	for i = 1, 5 do
		assert(st.capture.active[i] == (i == 4), "ativo errado em S" .. i)
	end
	assert(st.front == 4 and st.deadline == 20 * 60)
end)

test("Offensive: tomar a frente leva 90 s com 5+ atacantes (VC→neutro→EUA) e soma 15 min", function()
	local st = Offensive.new()
	local evs = run(st, at(4, 5, 0), 89)
	assert(not has(evs, "captured", 4), "cedo demais")
	assert(has(evs, "neutralized", 4), "deveria neutralizar no caminho")
	evs = run(st, at(4, 5, 0), 1)
	assert(has(evs, "captured", 4) and has(evs, "advanced", 3), "não tomou S4 aos 90 s")
	assert(st.front == 3 and st.deadline == 35 * 60)
	assert(st.capture.active[3] and not st.capture.active[4])
end)

test("Offensive: setor tomado fica travado; VC sozinho nele não muda nada", function()
	local st = Offensive.new()
	run(st, at(4, 5, 0), 90)
	run(st, at(4, 0, 6), 600)
	assert(st.capture.owner[4] == "US" and st.capture.progress[4] == 1)
end)

test("Offensive: VC retoma a frente neutralizada; disputa congela", function()
	local st = Offensive.new()
	run(st, at(4, 1, 0), 100) -- 1 atacante: neutraliza aos 90 s
	assert(st.capture.owner[4] == "Neutral")
	local p = st.capture.progress[4]
	run(st, at(4, 2, 2), 30)
	assert(st.capture.progress[4] == p, "disputado deveria congelar")
	local evs = run(st, at(4, 0, 4), 120)
	assert(has(evs, "captured", 4) and st.capture.owner[4] == "VC", "VC deveria retomar")
	assert(st.front == 4, "a frente não anda quando o VC retoma")
end)

test("Offensive: EUA vencem ao tomar S1; VC vence quando o relógio zera", function()
	local st = Offensive.new()
	local elapsed = 0
	for s = 4, 1, -1 do
		local evs = run(st, at(s, 6, 0), 90)
		elapsed += 90
		assert(has(evs, "captured", s), "não tomou S" .. s)
		if s == 1 then
			assert(has(evs, "overrun", 1))
		end
	end
	assert(st.front == 0 and Offensive.winner(st, elapsed) == "US")
	assert(#st.captured == 4 and st.deadline == (20 + 4 * 15) * 60)
	local d = Offensive.new()
	assert(Offensive.winner(d, 20 * 60 - 1) == nil)
	assert(Offensive.winner(d, 20 * 60) == "VC")
	assert(Offensive.timeLeft(d, 30 * 60) == 0)
end)

test("Offensive: bots — EUA atacam a frente, VC a defende", function()
	local st = Offensive.new()
	assert(BotBrain.objective(st.capture.owner, st.capture.active, "US") == 4)
	assert(BotBrain.objective(st.capture.owner, st.capture.active, "VC") == 4)
	run(st, at(4, 6, 0), 90)
	assert(BotBrain.objective(st.capture.owner, st.capture.active, "US") == 3)
	assert(BotBrain.objective(st.capture.owner, st.capture.active, "VC") == 3)
end)

test("rotação: servidor público alterna Warfare e Offensive; privado fica no escolhido", function()
	local rot = { "Warfare", "Offensive" }
	assert(Capture.nextMode("Warfare", false, rot) == "Offensive")
	assert(Capture.nextMode("Offensive", false, rot) == "Warfare")
	assert(Capture.nextMode("Skirmish", false, rot) == "Warfare")
	assert(Capture.nextMode("Skirmish", true, rot) == "Skirmish")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
