--!strict
-- Testes dos eventos da partida (pedido do dono, 2026-11-12). Uso: lune run tests/luau/eventos.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Eventos = require(S .. "Eventos") :: any
local Explosive = require(S .. "Explosive") :: any
local Rng = require(S .. "Rng") :: any
local MapConfig = require(S .. "MapConfig") :: any

local M = MapConfig.STUD_M

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

local ALL = { naval = true, air = true, heli = true, mortar = true, medevac = true, depot = true }

test("os sete eventos têm fonte, recompensa, lado e tipo", function()
	for _, id in { "naval", "air", "heli", "mortar", "medevac", "depot", "counter" } do
		local d = Eventos.DEFS[id]
		assert(d, id)
		assert(type(d.source) == "string" and #d.source > 20, id .. ": sem fonte")
		assert(d.reward.xp > 0 and d.reward.cr > 0 and d.rewardOther.xp > 0, id .. ": recompensa")
		assert(d.side == "US" or d.side == "VC" or d.side == "any", id .. ": lado")
		if d.kind == "barrage" then
			assert(d.warnS >= 8 and d.warnS <= 10, id .. ": aviso fora de 8–10 s")
			assert(Explosive.TYPES[d.explosive], id .. ": explosivo inexistente")
		end
	end
	local r = Eventos.rewards()
	assert(r.evento_naval and r.evento_naval_outro and r.evento_counter, "chaves de recompensa")
	assert(not Eventos.DEFS.counter.rotation, "contra-ataque é reação, não entra no sorteio")
end)

test("ritmo: 2 a 3 min entre eventos; o primeiro no minuto 1", function()
	near(Eventos.gap(0), 120, 1e-9)
	near(Eventos.gap(1), 180, 1e-9)
	near(Eventos.gap(0.5), 150, 1e-9)
	assert(Eventos.C.firstAtS == 60)
end)

test("sorteio: nunca dois iguais seguidos e lados equilibrados em 10.000 eventos", function()
	local rng = Rng.new(1965)
	local last, lastSide = nil, nil
	local counts = { US = 0, VC = 0 }
	local seen: { [string]: number } = {}
	for _ = 1, 10000 do
		local id, side = Eventos.pick(last, lastSide, counts, ALL, rng:next())
		assert(id and side, "sem evento com tudo disponível")
		assert(id ~= last, "repetiu " .. tostring(id))
		counts[side] += 1
		seen[id] = (seen[id] or 0) + 1
		last, lastSide = id, side
		assert(math.abs(counts.US - counts.VC) <= 1, "desequilíbrio " .. counts.US .. " x " .. counts.VC)
	end
	for id in ALL do
		assert((seen[id] or 0) > 500, id .. " quase nunca sai: " .. tostring(seen[id]))
	end
	-- só um evento disponível igual ao último: nada (não repete)
	local id = Eventos.pick("naval", "US", counts, { naval = true }, 0.3)
	assert(id == nil, "repetiu o único disponível")
	-- lado da vez sem evento próprio: cai para o outro, sem repetir
	local id2, side2 = Eventos.pick("mortar", "VC", { US = 3, VC = 3 }, { mortar = true, depot = true }, 0)
	assert(id2 == "depot" and side2 == "VC", tostring(id2))
end)

test("barragem: aviso de 8–10 s antes do primeiro impacto e todos os impactos no tempo", function()
	for _, id in { "naval", "air", "mortar" } do
		local d = Eventos.DEFS[id]
		local rng = Rng.new(7)
		local imps = Eventos.impacts(d, 0, 0, 0, M, function()
			return rng:next()
		end)
		assert(#imps == d.rounds, id .. ": rodadas")
		local first = math.huge
		for _, imp in imps do
			first = math.min(first, imp.t)
		end
		near(first, d.warnS, 1e-9, id .. ": primeiro impacto")
		assert(Eventos.barrageS(d) >= d.warnS + Eventos.C.assaultS)
	end
end)

test("barragem: impactos perto do centro (3 CEP + meia linha) em 2.000 sorteios", function()
	for _, id in { "naval", "air", "mortar" } do
		local d = Eventos.DEFS[id]
		local rng = Rng.new(11)
		local worst, out = 0, 0
		local n = 0
		for _ = 1, 500 do
			for _, imp in
				Eventos.impacts(d, 100, -200, 1.1, M, function()
					return rng:next()
				end)
			do
				local dm = math.sqrt((imp.x - 100) ^ 2 + (imp.z + 200) ^ 2) * M
				worst = math.max(worst, dm)
				n += 1
				if dm > 3 * d.cepM + (if d.line then 60 else 0) then
					out += 1
				end
			end
		end
		-- círculo normal: P(r > 3 CEP) = 0,5^9 ≈ 0,2 %
		assert(out / n < 0.01, string.format("%s: %.2f%% fora do alcance previsto", id, 100 * out / n))
		print(
			string.format(
				"       (%s: alcance de dano %.0f m; impacto mais longe do centro %.0f m)",
				id,
				Eventos.reachM(d, Explosive.TYPES[d.explosive].casualtyM),
				worst
			)
		)
	end
end)

test("centro seguro: recua para longe dos amigos, nunca a menos de 200 m de um QG", function()
	local hqs = { { x = 10000 / M, z = 0 }, { x = -10000 / M, z = 0 } }
	-- amigo a 50 m do ponto: recua até ficar a >= 100 m dele
	local x, z = Eventos.safeCenter(0, 0, 1, 0, { { x = -50 / M, z = 0 } }, 100, hqs, M)
	assert(x and z, "devia achar lugar")
	assert((x - -50 / M) * M >= 100 - 1e-6, string.format("ficou a %.1f m do amigo", (x + 50 / M) * M))
	assert(x * M <= Eventos.C.maxShiftM + 1e-6, "recuou demais")
	-- amigo em cima do ponto e recuo máximo curto demais: sem barragem
	local nx = Eventos.safeCenter(0, 0, 1, 0, { { x = 0, z = 0 } }, 150, hqs, M)
	assert(nx == nil, "barragem em cima de amigos")
	-- QG a 100 m: sem barragem
	local hx = Eventos.safeCenter(0, 0, 0, 1, {}, 100, { { x = 100 / M, z = 0 } }, M)
	assert(hx == nil, "barragem perto do QG")
end)

test("LZ: a 140 m do alvo, do lado de quem chega, dentro da área", function()
	local b = MapConfig.Bounds
	local sp = MapConfig.Strongpoints[8]
	local hq = MapConfig.HQ.US
	local x, z = Eventos.towards(sp.x, sp.z, hq.x, hq.z, Eventos.C.lzFromTargetM, M, b, 30)
	near(math.sqrt((x - sp.x) ^ 2 + (z - sp.z) ^ 2) * M, 140, 1, "distância do alvo")
	assert((x - sp.x) * (hq.x - sp.x) + (z - sp.z) * (hq.z - sp.z) > 0, "do lado do QG")
	assert(x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ)
end)

test("contra-ataque: só quem perdeu um setor que era seu", function()
	local l = Eventos.losses({ "VC", "VC", "Neutral", "US", "US" }, { "VC", "VC", "US", "VC", "US" })
	assert(#l == 1 and l[1].sector == 4 and l[1].loser == "US" and l[1].holder == "VC")
	local n = Eventos.losses({ "VC", "Neutral" }, { "Neutral", "VC" })
	assert(#n == 1 and n[1].loser == "VC" and n[1].holder == "Neutral", "neutralizado também é perda")
end)

test("métrica: tiro num inimigo a até 150 m e 8°; resumo com mediana e fração em 3 min", function()
	assert(Eventos.inCone(0, 0, 1, 0, 100 / M, 5 / M, 150, 8, M), "a 2,9° e 100 m")
	assert(not Eventos.inCone(0, 0, 1, 0, 100 / M, 20 / M, 150, 8, M), "a 11° não")
	assert(not Eventos.inCone(0, 0, 1, 0, 151 / M, 0, 150, 8, M), "a 151 m não")
	assert(not Eventos.inCone(0, 0, 1, 0, -50 / M, 0, 150, 8, M), "atrás não")
	local m = Eventos.newMetric()
	for _, s in { 40, 90, 200, 120 } do
		Eventos.addContact(m, s)
	end
	local s = Eventos.summary(m, 1)
	assert(s.n == 4 and s.median == 105 and s.worst == 200)
	near(s.mean, 112.5, 1e-9)
	near(s.within, 3 / 5, 1e-9, "3 em até 180 s de 5 (1 sem contato há mais de 3 min)")
	assert(Eventos.summary(Eventos.newMetric(), 0).within == 0)
end)

test("servidor: avisos pelo remote, marcador por atributo e nenhum nascimento dentro da barragem", function()
	local src = fs.readFile("src/ServerScriptService/Modules/EventosService.luau")
	assert(string.find(src, 'Net.event("Evento_Aviso")', 1, true), "aviso")
	assert(string.find(src, "SpawnService.addBlocker", 1, true), "bloqueio de nascimento")
	assert(string.find(src, "ExplosionService.detonate", 1, true), "dano pelas regras de explosão")
	for _, attr in { "Evento", "Nome", "Lado", "Alvo", "X", "Z", "RaioM", "Setor", "Fase", "Inicio", "Fim", "Grade" } do
		assert(string.find(src, "\t\t\t" .. attr .. " = ", 1, true), "atributo do marcador " .. attr)
	end
	local cli = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/Eventos.client.luau")
	assert(string.find(cli, "Toast.show", 1, true), "o cliente só chama o Toast")
	local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(net, '"Evento_Aviso"', 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
