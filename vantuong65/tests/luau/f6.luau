--!strict
-- Testes da F6 (Lune): modo Offensive, rotação de modos e tutorial.
-- Uso: lune run tests/luau/f6.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Capture = require(S .. "Capture") :: any
local Offensive = require(S .. "Offensive") :: any
local BotBrain = require(S .. "BotBrain") :: any
local InputMap = require(S .. "InputMap") :: any
local Logistics = require(S .. "Logistics") :: any
local Roles = require(S .. "Roles") :: any
local Tutorial = require(S .. "Tutorial") :: any
local ProfileSchema = require("../../src/ServerScriptService/Modules/ProfileSchema") :: any

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

-- ===== tutorial =====
local ACTION: { [string]: any } = {}
for _, a in InputMap.ACTIONS do
	ACTION[a.id] = ACTION[a.id] or a
end

test("tutorial: todo papel tem passos curtos (3 a 12)", function()
	for id in Roles.roles do
		local n = #Tutorial.steps(id)
		assert(n >= 3 and n <= 12, id .. " com " .. n .. " passos")
	end
end)

test("tutorial: toda ação citada existe no InputMap (passo e texto)", function()
	for id in Roles.roles do
		for _, st in Tutorial.steps(id) do
			if st.action then
				assert(ACTION[st.action], id .. ": ação inexistente " .. st.action)
			end
			for _, a in Tutorial.placeholders(st) do
				assert(ACTION[a], id .. ": texto cita ação inexistente " .. a)
			end
			assert(st.action or st.range, id .. ": passo sem ação nem alvo")
		end
	end
end)

test("tutorial: 'Construir' só para papéis que constroem algo na logística", function()
	for id in Roles.roles do
		for _, st in Tutorial.steps(id) do
			if string.find(st.text, "Construir") then
				local any = false
				for _, b in Logistics.BUILDS do
					any = any or b.role[id] == true
				end
				assert(any, id .. " não constrói nada, mas o tutorial diz Construir")
			end
		end
	end
end)

test("tutorial: campo de tiro (100/200/300 m) só para quem usa fuzil", function()
	for id in Roles.roles do
		local ranges = {}
		for _, st in Tutorial.steps(id) do
			if st.range then
				table.insert(ranges, st.range)
			end
		end
		if Tutorial.RIFLE_ROLES[id] then
			assert(#ranges == 3 and ranges[1] == 100 and ranges[2] == 200 and ranges[3] == 300, id)
		else
			assert(#ranges == 0, id .. " não usa fuzil e foi ao campo de tiro")
		end
	end
end)

test("tutorial: texto final troca os botões; avanço por ação ou alvo; perfil saneado", function()
	local st = Tutorial.steps("rifleman")
	local glyph = function(a: string): string
		return if ACTION[a].padPress == "hold" then "[" .. a .. "] (segurar)" else "[" .. a .. "]"
	end
	for _, s in st do
		local t = Tutorial.render(s, glyph)
		assert(not string.find(t, "{"), "sobrou marcador: " .. t)
	end
	assert(string.find(Tutorial.render(st[4], glyph), "%(segurar%)"), "deitar é segurar no controle")
	assert(Tutorial.done(st[1], "action", "aim") and not Tutorial.done(st[1], "action", "fire"))
	assert(Tutorial.done(st[6], "range", 100) and not Tutorial.done(st[6], "range", 200))
	local clean = Tutorial.sanitize({ rifleman = true, medic = "sim", hacker = true, [1] = true }, Roles.roles)
	assert(clean.rifleman and not clean.medic and not clean.hacker)
end)

test("perfil: configurações e tutorial sobrevivem ao load (antes as configurações sumiam)", function()
	local raw = {
		schema = 1,
		tips = 3,
		purchases = { a = 1 },
		settings = { invertY = true, lookInner = 0.2 },
		tutorial = { rifleman = true, medic = 1, hacker = true },
	}
	local p = ProfileSchema.migrate(raw)
	assert(p.settings and p.settings.invertY == true and p.settings.lookInner == 0.2, "settings perdido")
	assert(p.tutorial.rifleman and not p.tutorial.medic and not p.tutorial.hacker)
	assert(p.tips == 3 and p.purchases.a == 1)
	local again = ProfileSchema.migrate(p)
	assert(again.settings.invertY == true and again.tutorial.rifleman, "migrar duas vezes perde dados")
	local d = ProfileSchema.migrate("lixo")
	assert(d.schema == 1 and d.settings == nil and next(d.tutorial) == nil)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
