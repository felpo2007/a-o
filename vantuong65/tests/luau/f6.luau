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
local Accessibility = require(S .. "Accessibility") :: any
local AfterAction = require(S .. "AfterAction") :: any
local Comms = require(S .. "Comms") :: any
local Animals = require(S .. "Animals") :: any
local Egrets = require(S .. "Egrets") :: any
local RiceField = require(S .. "RiceField") :: any
local Rng = require(S .. "Rng") :: any
local Pickup = require(S .. "Pickup") :: any
local Weapons = require(S .. "Weapons") :: any
local Kit = require(S .. "Kit") :: any
local Radio = require(S .. "Radio") :: any
local FieldWork = require(S .. "FieldWork") :: any
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

test("tutorial: campo de tiro (50/100/150 m, D-114) só para quem usa fuzil", function()
	for id in Roles.roles do
		local ranges = {}
		for _, st in Tutorial.steps(id) do
			if st.range then
				table.insert(ranges, st.range)
			end
		end
		if Tutorial.RIFLE_ROLES[id] then
			assert(#ranges == 3 and ranges[1] == 50 and ranges[2] == 100 and ranges[3] == 150, id)
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
	assert(Tutorial.done(st[6], "range", 50) and not Tutorial.done(st[6], "range", 100))
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
	assert(d.schema == ProfileSchema.VERSION and d.settings == nil and next(d.tutorial) == nil)
end)

-- ===== acessibilidade (Parte 11) =====
test("daltonismo: vermelho x verde histórico some na deuteranopia; a paleta de cada modo separa", function()
	local h = Accessibility.TRACER.off
	local bad = Accessibility.deltaE(h.US, h.VC, "deutan")
	assert(bad < 30, string.format("esperava confusão (ΔE < 30), veio %.1f", bad))
	for _, mode in Accessibility.MODES do
		local pal = Accessibility.TRACER[mode]
		local sim = if mode == "off" then "off" else mode
		local d = Accessibility.deltaE(pal.US, pal.VC, sim)
		local normal = Accessibility.deltaE(pal.US, pal.VC, "off")
		assert(d >= 75 and normal >= 75, string.format("%s: ΔE %.1f (simulado) / %.1f (normal)", mode, d, normal))
		print(string.format("       %-7s ΔE simulado %.0f, visão típica %.0f", mode, d, normal))
	end
end)

test("acessibilidade: campo de visão, modo daltônico e legendas saneados", function()
	local s = InputMap.validate({ fov = 200, colorblind = "roxo", captions = "sim" })
	assert(s.fov == 90 and s.colorblind == "off" and s.captions == false)
	s = InputMap.validate({ fov = 75, colorblind = "deutan", captions = true })
	assert(s.fov == 75 and s.colorblind == "deutan" and s.captions == true)
	assert(InputMap.validate(nil).fov == Accessibility.FOV_DEFAULT)
end)

test("legendas: direção e distância arredondada", function()
	assert(Accessibility.direction(0, -100) == "norte" and Accessibility.direction(100, 0) == "leste")
	assert(Accessibility.direction(0, 100) == "sul" and Accessibility.direction(-70, -70) == "noroeste")
	assert(Accessibility.caption("Explosão", 5, 5) == "[Explosão, perto]")
	assert(Accessibility.caption("Tiro de M14", 0, -312) == "[Tiro de M14, ~300 m a norte]")
	assert(Accessibility.caption("Tiro naval ao longe", 2600, 0) == "[Tiro naval ao longe, ~2500 m a leste]")
end)

-- ===== relatório pós-ação (Parte 11) =====
test("relatório: grupo data-hora de 1965 (fuso H = UTC+8) e virada do dia", function()
	local r = AfterAction.new("Offensive", 6.5)
	assert(AfterAction.dtg(r, 0) == "180630H AUG 65")
	assert(AfterAction.dtg(r, 61) == "180631H AUG 65")
	local n = AfterAction.new("Warfare", 23.5)
	assert(AfterAction.dtg(n, 45 * 60) == "190015H AUG 65", AfterAction.dtg(n, 45 * 60))
end)

test("relatório: linha do tempo, baixas por setor e resultado", function()
	local r = AfterAction.new("Offensive", 6.5)
	AfterAction.event(r, 95, "neutralized", 4, "VC", "Túmulos da várzea")
	AfterAction.event(r, 180, "captured", 4, "US", "Túmulos da várzea")
	AfterAction.event(r, 180, "advanced", 3, "US", "An Cường (2)")
	for _ = 1, 7 do
		AfterAction.casualty(r, "VC", 4)
	end
	AfterAction.casualty(r, "US", 4)
	AfterAction.casualty(r, "US", nil)
	AfterAction.finish(r, "US", 3600, { "VC", "VC", "VC", "US", "US" })
	local txt = table.concat(AfterAction.lines(r), "\n")
	assert(string.find(txt, "180631H AUG 65  VC perde o controle de D %(Túmulos da várzea%)"), txt)
	assert(string.find(txt, "180633H AUG 65  USMC toma D"), txt)
	assert(string.find(txt, "a frente passa para C %(An Cường %(2%)%)"), txt)
	assert(string.find(txt, "USMC: 2    VC: 7"), txt)
	assert(string.find(txt, "Combate mais pesado: D %(8 mortos%)"), txt)
	assert(string.find(txt, "Vitória do USMC%. Duração: 60 min%."), txt)
	assert(string.find(txt, "C VC · D USMC"), txt)
end)

test("relatório: cabe numa tela (linha do tempo limitada, com aviso)", function()
	local r = AfterAction.new("Warfare", 12)
	for i = 1, 100 do
		AfterAction.event(r, i * 10, "captured", 3, if i % 2 == 0 then "US" else "VC")
	end
	local lines = AfterAction.lines(r)
	assert(#lines <= AfterAction.MAX_ENTRIES + 20, "relatório longo demais: " .. #lines)
	assert(string.find(table.concat(lines, "\n"), "40 registros anteriores omitidos"))
end)

-- ===== marcação imperfeita e animais (Parte 11) =====
test("marcação imperfeita: erro cresce com a distância, alvo real dentro da área, envelhece", function()
	assert(Comms.markError(50) == 10 and Comms.markError(400) == 40 and Comms.markError(5000) == 100)
	local rng = Rng.new(7)
	for _ = 1, 2000 do
		local r = 40
		local ox, oz = Comms.markOffset(r, rng:next(), rng:next())
		assert(math.sqrt(ox * ox + oz * oz) <= r + 1e-9, "alvo fora da área")
	end
	assert(Comms.markAlpha(0) == 1 and Comms.markAlpha(30) == 0.5 and Comms.markAlpha(90) == 0)
end)

test("animais: fogem para longe do tiro, na velocidade da espécie; explosão assusta mais longe", function()
	local b = Animals.new("water_buffalo", 100, 0)
	assert(Animals.noise(b, 0, 0, false, 0), "búfalo a 100 m deveria ouvir o tiro")
	Animals.step(b, 1, 0.5, 0.3)
	assert(math.abs(b.x - 106) < 1e-9 and b.z == 0, "fuga de 6 m/s para longe do tiro")
	local c = Animals.new("chicken", 100, 0)
	assert(not Animals.noise(c, 0, 0, false, 0), "galinha a 100 m não ouve o tiro (60 m)")
	assert(Animals.noise(c, 0, 0, true, 0), "mas ouve a explosão (180 m)")
	assert(Animals.fleeing(c, 3.9) and not Animals.fleeing(c, 4.1))
end)

test("arrozal e garças (D-74, D-76): estados dos tabuleiros, grade sem sobra, bando e voo", function()
	-- estados: ~60% arroz em pé, ~25% muda, ~15% pousio, sempre iguais para a mesma posição
	local count = { mature = 0, young = 0, fallow = 0 }
	local flocks, inMature = 0, 0
	for i = 1, 2000 do
		local x, z = i * 37.3 - 3000, (i * 91.7) % 6000 - 3000
		local k = RiceField.kind(x, z)
		count[k] += 1
		assert(RiceField.kind(x, z) == k, "estado do tabuleiro mudou na 2ª consulta")
		local n = Egrets.flockSize(x, z)
		if n > 0 then
			flocks += 1
			assert(n >= 2 and n <= 5, "bando de 2 a 5 garças: " .. n)
			if k == "mature" then
				inMature += 1
			end
		end
	end
	assert(count.mature > 1000 and count.mature < 1400, "arroz em pé ~60%: " .. count.mature)
	assert(count.fallow > 200 and count.fallow < 400, "pousio ~15%: " .. count.fallow)
	assert(inMature == 0, "garça no arroz alto some: não tem bando lá")
	assert(flocks > 150 and flocks < 330, "bando em ~30% dos tabuleiros alagados: " .. flocks)
	-- grade: cobre o tabuleiro sem sobra, ladrilho entre 2/3 e 4/3 do nominal
	for _, s in { { 117.7, 85.5 }, { 20, 20 }, { 300, 9 } } do
		local nx, nz, tw, tz = RiceField.grid(s[1], s[2])
		assert(math.abs(nx * tw - s[1]) < 1e-6 and math.abs(nz * tz - s[2]) < 1e-6, "grade com sobra")
		assert(nx == 1 or (tw >= 16 * 2 / 3 and tw <= 16 * 4 / 3), "ladrilho fora da faixa: " .. tw)
	end
	assert(RiceField.lod(10) == "hi" and RiceField.lod(150) == "lo" and RiceField.lod(400) == nil)
	-- voo: sobe até o cruzeiro e segue reto; contínuo na troca de fase
	local a0, h0 = Egrets.flight(0)
	assert(a0 == 0 and h0 == 0, "decola do chão")
	local a1, h1 = Egrets.flight(Egrets.CLIMB_S - 1e-6)
	local a2, h2 = Egrets.flight(Egrets.CLIMB_S + 1e-6)
	assert(math.abs(a1 - a2) < 0.01 and math.abs(h1 - h2) < 0.01, "voo pula na troca de fase")
	local aEnd, hEnd = Egrets.flight(Egrets.FLIGHT_S)
	assert(math.abs(hEnd - Egrets.CLIMB_M) < 1e-6, "altura de cruzeiro")
	assert(aEnd > 100 and aEnd < 160, "some a 100–160 m de onde estava: " .. aEnd)
	-- ouve: tiro a 120 m, explosão a 300 m
	assert(Egrets.hears(0, 0, 100, 0, false) and not Egrets.hears(0, 0, 130, 0, false))
	assert(Egrets.hears(0, 0, 250, 0, true) and not Egrets.hears(0, 0, 320, 0, true))
end)

test("animais: calmos ficam perto de casa; nascem em parte dos quintais", function()
	local c = Animals.new("chicken", 0, 0)
	local rng = Rng.new(3)
	for t = 1, 3600 do
		Animals.step(c, 1, t, rng:next())
		assert(math.sqrt(c.x ^ 2 + c.z ^ 2) <= Animals.SPECIES.chicken.leashM + 1, "galinha fugiu de casa sem susto")
	end
	-- D-77: o búfalo calmo passa a maior parte do tempo parado pastando; o andar sai certo
	local b = Animals.new("water_buffalo", 0, 0)
	local still = 0
	for t = 1, 3600 do
		local moved = Animals.step(b, 1, t, rng:next())
		if not moved then
			still += 1
			assert(Animals.gait(b, t, moved) == "idle", "parado = idle")
		else
			assert(Animals.gait(b, t, moved) == "walk", "andando calmo = walk")
		end
		assert(math.sqrt(b.x ^ 2 + b.z ^ 2) <= Animals.SPECIES.water_buffalo.leashM + 1, "búfalo saiu do pasto")
	end
	assert(still > 3600 * 0.55, "búfalo calmo parado a maior parte do tempo: " .. still .. " s de 3600")
	Animals.noise(b, b.x + 10, b.z, false, 4000)
	assert(Animals.step(b, 0.1, 4000.1, 0.5) and Animals.gait(b, 4000.1, true) == "run", "assustado = run")
	local houses = {}
	for i = 1, 60 do
		table.insert(houses, i * 50)
		table.insert(houses, 0)
	end
	local r2 = Rng.new(11)
	local list = Animals.spawns(houses, function()
		return r2:next()
	end)
	local nb, nc = 0, 0
	for _, a in list do
		if a.species == "water_buffalo" then
			nb += 1
		else
			nc += 1
		end
	end
	assert(nb == 12, "1 búfalo a cada 5 casas (D-74): " .. nb)
	assert(nc >= 36 and nc <= 108 and nc % 3 == 0, "galinhas em bando de 3 em ~2/5 dos quintais: " .. nc)
	-- manada (D-74): 2 adultos e 1 bezerro no arrozal; sem arrozal, nenhuma
	local r3 = Rng.new(5)
	local herd = Animals.herd(0, 0, function()
		return r3:next()
	end, function(x: number, _z: number)
		return x > 40
	end)
	assert(#herd == 3, "manada de 3: " .. #herd)
	local calves = 0
	for _, b in herd do
		assert(b.species == "water_buffalo" and b.x > 30, "búfalo da manada fora do arrozal")
		if b.scale < 1 then
			calves += 1
		end
	end
	assert(calves == 1, "um bezerro por manada")
	assert(#Animals.herd(0, 0, function()
		return r3:next()
	end, function()
		return false
	end) == 0, "sem arrozal não há manada")
end)

test("arma do inimigo: cai só com o carregador; troca deixa a sua no chão; caixa não reabastece", function()
	local d = Pickup.dropOnDeath({ weapon = "type56", mag = 17, spare = 3 })
	assert(d and d.weapon == "type56" and d.mag == 17 and d.spare == 0, "sobressalentes não caem")
	assert(Pickup.dropOnDeath({ weapon = "m14", mag = 0, spare = 4 }) == nil, "arma vazia não cai")
	local new, dropped = Pickup.swap({ weapon = "m14", mag = 12, spare = 4 }, d)
	assert(new.weapon == "type56" and new.mag == 17 and new.spare == 0)
	assert(dropped and dropped.weapon == "m14" and dropped.mag == 12 and dropped.spare == 4)
	local ak = Weapons.get("type56")
	assert(ak and not Pickup.canRefill(ak.faction, "US") and Pickup.canRefill(ak.faction, "VC"))
end)

test("equipamento por peso: padrão cabe; trocar item por item; passar do limite é cortado", function()
	for _, kind in { "rifle", "mg", "pistol", "launcher" } do
		local d = Kit.defaults(kind)
		local v = Kit.validate(d, kind)
		assert(v.mags == d.mags and v.frags == d.frags, kind .. ": o padrão deveria passar intacto")
		assert(math.abs(Kit.limit(kind) - Kit.weight(d, kind) - 1) < 1e-9)
	end
	-- fuzil: tirar 1 granada e a fumaça (0,99 kg) libera 2 carregadores a mais (1,5 kg) com a margem
	local k = Kit.validate({ mags = 8, frags = 1, smokes = 0, bandages = 2 }, "rifle")
	assert(k.mags == 8 and k.frags == 1 and k.smokes == 0)
	-- tudo no máximo: o servidor corta fumaça, granadas e curativos até caber
	local big = Kit.validate({ mags = 10, frags = 4, smokes = 3, bandages = 6 }, "rifle")
	assert(Kit.weight(big, "rifle") <= Kit.limit("rifle") + 1e-9, "acima do limite")
	-- 11,52 kg pedidos; limite 7,14 kg: sai fumaça, granadas, um curativo e 1 carregador (6,85 kg)
	assert(big.mags == 9 and big.frags == 0 and big.smokes == 0 and big.bandages == 1)
	local junk = Kit.validate({ mags = -5, frags = 1 / 0 * 0, bandages = "x" }, "rifle")
	assert(junk.mags == 1 and junk.frags == 2 and junk.bandages == 2)
end)

test("rádio: só o rádio do squad fala com o comandante; caído, só o mesmo lado pega", function()
	-- D-108: o líder nasce com o rádio (o operador de rádio e a equipe de morteiro saíram)
	assert(Radio.canTalkToCommand("commander", false) and not Radio.canTalkToCommand("mortar", false))
	assert(not Radio.canTalkToCommand("squad_leader", false), "líder que perdeu o rádio não fala com o comando")
	assert(Radio.canTalkToCommand("rifleman", true), "quem pegou o rádio fala")
	assert(Radio.startsWithRadio("squad_leader") and not Radio.startsWithRadio("rifleman"))
	assert(Radio.canPickUp("US", "US", true) and not Radio.canPickUp("US", "VC", true))
	assert(not Radio.canPickUp("US", "US", false), "caído não pega")
	assert(not Radio.squadLinked({ { carries = false }, { carries = false } }))
	assert(Radio.squadLinked({ { carries = false }, { carries = true } }))
	assert(Roles.roles[Radio.ROLE].unit == "infantry" and Roles.loadout.US[Radio.ROLE] and Roles.loadout.VC[Radio.ROLE])
end)

test("pá: só em setor próprio, fora da água, 1 por minuto e com teto no mapa", function()
	assert(FieldWork.canDig("US", "US", false, nil, 0, 0))
	local ok, why = FieldWork.canDig("VC", "US", false, nil, 0, 0)
	assert(not ok and why == "só em setor do seu lado")
	assert(not FieldWork.canDig("Neutral", "US", false, nil, 0, 0), "neutro não")
	assert(select(2, FieldWork.canDig("US", "US", true, nil, 0, 0)) == "não dá para cavar na água")
	assert(not FieldWork.canDig("US", "US", false, 100, 159, 0) and FieldWork.canDig("US", "US", false, 100, 160, 0))
	assert(not FieldWork.canDig("US", "US", false, nil, 0, FieldWork.DIG.maxTotal))
end)

test("medevac: só com o UH-34D parado e pousado; 5 s junto do helicóptero", function()
	assert(FieldWork.heliReady(0.3, 0.5, false))
	assert(not FieldWork.heliReady(3, 0.5, false), "em movimento não")
	assert(not FieldWork.heliReady(0.2, 6, false), "pairando alto não")
	assert(not FieldWork.heliReady(0, 0, true), "destruído não")
	local tt, done = 0, false
	for _ = 1, 4 do
		tt, done = FieldWork.boarding(tt, true, 1)
	end
	assert(not done)
	tt, done = FieldWork.boarding(tt, false, 1)
	assert(tt == 0 and not done, "afastou: recomeça")
	for _ = 1, 5 do
		tt, done = FieldWork.boarding(tt, true, 1)
	end
	assert(done)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
