--!strict
-- Simulação da métrica do dono (2026-11-12): "nos primeiros 3 minutos de gameplay, já tenha tido pelo
-- menos uma troca de tiros". Uso: lune run tests/luau/contato.luau
--
-- Modelo (de design; os números do Studio vêm do ContatoService):
--   - mapa de 1 x 1 km do MapConfig, pontos fortes sorteados como o MatchService (Front.pickStrongpoints);
--   - pontos de nascimento como o SpawnService/FrontService: QG, reunião atrás de cada ponto forte do
--     lado (SpawnRules.rallyPosition + Front.clampInside) e reunião avançada (Front.forwardRally). Sem
--     túneis do VC nem reunião de squad (dependem do jogo rodando);
--   - todo mundo nasce em t = 0 (começo da partida, o pior caso) e marcha em linha reta até o objetivo
--     do lado (Front.objective) a 1,9 m/s; de cada ponto do inimigo sai um grupo para o objetivo dele;
--   - contato: um inimigo a até 150 m (a definição da métrica) e, para comparar, a até 75 m (mata
--     fechada). Linha reta: o caminho de verdade (diques, sebes, mata) é mais longo.
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Front = require(S .. "Front") :: any
local Geometry = require(S .. "Geometry") :: any
local MapConfig = require(S .. "MapConfig") :: any
local Offensive = require(S .. "Offensive") :: any
local Rng = require(S .. "Rng") :: any
local SpawnRules = require(S .. "SpawnRules") :: any
local Eventos = require(S .. "Eventos") :: any
local Tunnels = require(S .. "Tunnels") :: any

local M = MapConfig.STUD_M
local V = 1.9 -- m/s: marcha média com equipamento (pedido do coordenador)
local GOAL = Eventos.C.goalS
local DRAWS = 300
local MAX_T = 900

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

local bySector: { [number]: { any } } = {}
for _, sp in MapConfig.Strongpoints do
	bySector[sp.sector] = bySector[sp.sector] or {}
	table.insert(bySector[sp.sector], sp)
end
local N = #MapConfig.Sectors
local function sectorAt(x: number, z: number): number?
	return Geometry.sectorAt(MapConfig.Sectors, x, z)
end
local function dM(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) * M
end

type Spot = { kind: string, x: number, z: number }

local function setup(mode: string, rng: any): (any, { string }, { boolean })
	local picked = Front.pickStrongpoints(bySector, N, Front.firstSector(mode, N), function()
		return rng:next()
	end)
	if mode == "Offensive" then
		local o = Offensive.new(N)
		return picked, o.capture.owner, o.capture.active
	end
	return picked, table.clone(MapConfig.InitialOwner), { true, true, true, true, true }
end

-- Bocas dos túneis do VC no quadro do jogo (como o TunnelService.entrances: centro em An Cường (2))
local MOUTHS: { any } = {}
do
	local cx, cz = 0, 0
	for _, l in MapConfig.Locations do
		if l.name == "An Cường (2)" then
			cx, cz = l.x, l.z
		end
	end
	for id, n in Tunnels.nodes do
		if n.entrance then
			local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
			table.insert(MOUTHS, { id = id, x = x, z = z, sector = sectorAt(x, z), open = true })
		end
	end
	table.sort(MOUTHS, function(a, b)
		return a.id < b.id
	end)
end

-- Variante do teste: túneis de guarnição do VC (já existiam) e o túnel avançado (2026-11-12)
type Variant = { name: string, tunnels: boolean, forward: boolean }
local variant: Variant = { name = "depois", tunnels = true, forward = true }

local function spawnsOf(f: string, picked: any, owner: { string }, active: { boolean }): { Spot }
	local out: { Spot } = { { kind = "QG", x = MapConfig.HQ[f].x, z = MapConfig.HQ[f].z } }
	if f == "VC" and variant.tunnels then
		for _, m in MOUTHS do
			if m.sector and owner[m.sector] == "VC" then
				table.insert(out, { kind = "túnel (guarnição)", x = m.x, z = m.z })
			end
		end
	end
	if f == "VC" and variant.forward then
		local _, goal = Front.objective(owner, active, "VC")
		local gsp = if goal then picked[goal] else nil
		if gsp then
			local us, vc = MapConfig.HQ.US, MapConfig.HQ.VC
			local m, fx, fz = SpawnRules.vcForward(MOUTHS, owner, gsp.x, gsp.z, us.x, us.z, vc.x, vc.z, M)
			if m then
				table.insert(out, { kind = "túnel avançado", x = fx, z = fz })
			end
		end
	end
	for s, sp in picked do
		if owner[s] == f then
			local x, z = SpawnRules.rallyPosition(sp.x, sp.z, f, M)
			x, z = Front.clampInside(MapConfig.Bounds, x, z, Front.C.rallyInsetM / M)
			table.insert(out, { kind = "reunião", x = x, z = z })
		end
	end
	for _, pair in Front.forwardPairs(owner, active, f) do
		local own, t = picked[pair.own], picked[pair.target]
		if own and t then
			local x, z = Front.forwardRally(pair.own, own, t, M, sectorAt, MapConfig.Bounds)
			if x and z then
				table.insert(out, { kind = "reunião avançada", x = x, z = z })
			end
		end
	end
	return out
end

local function targetOf(f: string, picked: any, owner: { string }, active: { boolean }): any
	local _, s = Front.objective(owner, active, f)
	return if s then picked[s] else nil
end

-- posição de quem sai de (x, z) para (tx, tz) a V m/s, t segundos depois
local function walk(x: number, z: number, tx: number, tz: number, t: number): (number, number)
	local d = dM(x, z, tx, tz)
	if d < 1e-6 then
		return x, z
	end
	local k = math.min(V * t / d, 1)
	return x + (tx - x) * k, z + (tz - z) * k
end

-- primeiro instante (s, depois de nascer em `born`) com um grupo inimigo a até rM
local function contact(me: Spot, myT: any, foes: { Spot }, foeT: any, rM: number, born: number): number
	for t = 0, MAX_T do
		local mx, mz = walk(me.x, me.z, myT.x, myT.z, t)
		for _, f in foes do
			local fx, fz = walk(f.x, f.z, foeT.x, foeT.z, born + t)
			if dM(mx, mz, fx, fz) <= rM then
				return t
			end
		end
	end
	return math.huge
end

type Row = { sum: number, n: number, inside: number }
local results: { [string]: Row } = {}
local order: { string } = {}
local function add(key: string, t: number)
	local r = results[key]
	if not r then
		r = { sum = 0, n = 0, inside = 0 }
		results[key] = r
		table.insert(order, key)
	end
	local row = r :: Row
	row.n += 1
	row.sum += math.min(t, MAX_T)
	if t <= GOAL then
		row.inside += 1
	end
end

-- chave: variante|alcance|modo|lado|ponto
local function key(rM: number, mode: string, f: string, kind: string): string
	return string.format("%s|%d m|%s|%s|%s", variant.name, rM, mode, f, kind)
end

local function run(rM: number)
	local rng = Rng.new(19650818)
	for _, mode in { "Warfare", "Offensive" } do
		for _ = 1, DRAWS do
			local picked, owner, active = setup(mode, rng)
			for _, f in { "US", "VC" } do
				local foe = if f == "US" then "VC" else "US"
				local myT, foeT = targetOf(f, picked, owner, active), targetOf(foe, picked, owner, active)
				if not (myT and foeT) then
					continue
				end
				local foes = spawnsOf(foe, picked, owner, active)
				local best = math.huge
				for _, sp in spawnsOf(f, picked, owner, active) do
					local t = contact(sp, myT, foes, foeT, rM, 0)
					add(key(rM, mode, f, sp.kind), t)
					add(key(rM, mode, f, "todos os pontos"), t) -- quem escolhe um ponto qualquer
					best = math.min(best, t)
				end
				add(key(rM, mode, f, "melhor ponto"), best)
				-- evento de abertura (minuto 1): a LZ pousa 140 m antes do alvo dos EUA em t = 66 s;
				-- quem nasce nela conta da entrada (o grupo inimigo já marchou 66 s)
				if f == "US" then
					local hq = MapConfig.HQ.US
					local lx, lz =
						Eventos.towards(myT.x, myT.z, hq.x, hq.z, Eventos.C.lzFromTargetM, M, MapConfig.Bounds, 30)
					local t = contact({ kind = "LZ", x = lx, z = lz }, myT, foes, foeT, rM, Eventos.C.firstAtS + 6)
					add(key(rM, mode, "US", "LZ do minuto 1"), t)
				end
			end
		end
	end
end

local function line(k: string): string
	local r = results[k]
	local parts = string.split(k, "|")
	return string.format(
		"       %-6s %-9s %-3s %-18s média %4.0f s   em até 3 min: %3.0f%%",
		parts[2],
		parts[3],
		parts[4],
		parts[5],
		r.sum / r.n,
		100 * r.inside / r.n
	)
end

local VARIANTS: { Variant } = {
	{ name = "sem túneis", tunnels = false, forward = false }, -- a simulação anterior
	{ name = "guarnições", tunnels = true, forward = false }, -- os túneis de guarnição que o jogo já tinha
	{ name = "depois", tunnels = true, forward = true }, -- + túnel avançado do VC (2026-11-12)
}

test("simulação: tempo até a primeira troca de tiros saindo de cada ponto de nascimento", function()
	for _, v in VARIANTS do
		variant = v
		run(150)
	end
	run(75) -- a variante final também com a mata fechada
	for _, k in order do
		if string.sub(k, 1, 7) == "depois|" then
			print(line(k))
		end
	end
	assert(#order > 0)
end)

test("túnel avançado do VC: antes e depois (inimigo a 150 m)", function()
	for _, mode in { "Offensive", "Warfare" } do
		for _, kind in { "QG", "túnel avançado", "melhor ponto", "todos os pontos" } do
			local parts = {}
			for _, v in VARIANTS do
				local r = results[string.format("%s|150 m|%s|VC|%s", v.name, mode, kind)]
				table.insert(
					parts,
					if r
						then string.format("%s %3.0f s (%3.0f%%)", v.name, r.sum / r.n, 100 * r.inside / r.n)
						else string.format("%s    -", v.name)
				)
			end
			print(string.format("       VC %-9s %-16s %s", mode, kind, table.concat(parts, " | ")))
		end
	end
	-- no Offensive o VC ganha um ponto perto do objetivo dele em toda partida
	local fwd = results["depois|150 m|Offensive|VC|túnel avançado"]
	assert(fwd and fwd.n == DRAWS, "o túnel avançado devia existir em toda partida do Offensive")
	assert(fwd.inside / fwd.n >= 0.9, string.format("túnel avançado: %.0f%%", 100 * fwd.inside / fwd.n))
	local before = results["guarnições|150 m|Offensive|VC|todos os pontos"]
	local after = results["depois|150 m|Offensive|VC|todos os pontos"]
	assert(after.inside / after.n >= before.inside / before.n, "média de todos os pontos não pode piorar")
	-- nunca para os EUA
	assert(results["depois|150 m|Offensive|US|túnel avançado"] == nil)
end)

-- O que dá para garantir com o mapa de hoje: quem escolhe o ponto mais perto do objetivo chega ao
-- contato (150 m) dentro da meta na maior parte das partidas, e a LZ do minuto 1 também.
test("meta de 3 min: o ponto mais perto do objetivo e a LZ do minuto 1 (inimigo a 150 m)", function()
	for _, mode in { "Warfare", "Offensive" } do
		for _, f in { "US", "VC" } do
			local r = results[string.format("depois|150 m|%s|%s|melhor ponto", mode, f)]
			assert(
				r and r.inside / r.n >= 0.9,
				string.format("%s %s: %.0f%%", mode, f, if r then 100 * r.inside / r.n else 0)
			)
		end
		local lz = results[string.format("depois|150 m|%s|US|LZ do minuto 1", mode)]
		assert(lz and lz.inside / lz.n >= 0.9, mode .. ": LZ do minuto 1")
	end
end)

test("túnel avançado: regra pura (boca do lado do VC, fora do ponto e de setor dos EUA)", function()
	local mouths = {
		{ id = "A", x = -100, z = 0, sector = 4, open = true }, -- do lado do VC, a 28 m: dentro do ponto
		{ id = "B", x = -300, z = 0, sector = 4, open = true }, -- do lado do VC, a 84 m
		{ id = "C", x = 300, z = 0, sector = 4, open = true }, -- do lado dos EUA
		{ id = "D", x = -250, z = 0, sector = 5, open = true }, -- setor dos EUA
		{ id = "E", x = -260, z = 0, sector = 4, open = false }, -- destruída
	}
	local owner = { "VC", "VC", "VC", "VC", "US" }
	local m, fx = SpawnRules.vcForward(mouths, owner, 0, 0, 5000, 0, -5000, 0, M)
	assert(m and m.id == "B", "escolheu " .. tostring(m and m.id))
	assert(fx < -300, "nasce ao lado da boca, do lado do QG do VC")
	-- sem boca do lado do VC (fora do ponto), vale a do outro lado; setor dos EUA e destruída, nunca
	local c = SpawnRules.vcForward({ mouths[1], mouths[3], mouths[4] }, owner, 0, 0, 5000, 0, -5000, 0, M)
	assert(c and c.id == "C", "sem opção do lado do VC: a de qualquer lado")
	assert(SpawnRules.vcForward({ mouths[1], mouths[4], mouths[5] }, owner, 0, 0, 5000, 0, -5000, 0, M) == nil)
	-- bloqueio próprio: inimigo a 49 m bloqueia, a 51 m não (o raio comum é 60 m: D-114)
	local R = SpawnRules.VC_FORWARD.blockM
	assert(SpawnRules.blocked(0, 0, { R - 1, 0 }, false, nil, 0, R))
	assert(not SpawnRules.blocked(0, 0, { R + 1, 0 }, false, nil, 0, R))
	assert(R < SpawnRules.C.blockRadiusM, "o raio do túnel é menor que o comum")
	assert(SpawnRules.blocked(0, 0, { R + 1, 0 }, false, nil, 0), "sem raio próprio vale o comum")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
