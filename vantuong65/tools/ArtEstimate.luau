--!strict
-- Estimativa offline da arte por setor (F5): instâncias e triângulos que o AssetLoader coloca, com
-- as mesmas regras (ordem, densidade, teto e desbaste das sebes), a partir dos dados do mapa e do
-- ArtBudget. É valor esperado: o sorteio real depende da ordem das peças no Roblox. Não é medição.
local ArtBudget = require("../src/ServerScriptService/Modules/ArtBudget")
local Animals = require("../src/ReplicatedStorage/Shared/Animals")
local Rng = require("../src/ReplicatedStorage/Shared/Rng") :: any
local Features = require("../src/ServerStorage/VT65Build/Data/Features") :: any
local Geometry = require("../src/ReplicatedStorage/Shared/Geometry")
local MapConfig = require("../src/ReplicatedStorage/Shared/MapConfig") :: any
local Tunnels = require("../src/ReplicatedStorage/Shared/Tunnels") :: any
local Tutorial = require("../src/ReplicatedStorage/Shared/Tutorial") :: any
local Vegetation = require("../src/ServerScriptService/Modules/Vegetation")
local WorldData = require("../src/ServerStorage/VT65Build/WorldData")
local Grid = require("../src/ServerStorage/VT65Build/Data/Grid") :: any

export type Sector = { count: number, tris: number, factor: number, demand: number }
export type Result = {
	sectors: { [number]: Sector },
	byKey: { [string]: number },
	jungle: { [number]: { planned: number, factor: number } },
}

local M = 0.28
local SLICE = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }

return function(): Result
	local sectors: { [number]: Sector } = {}
	local byKey: { [string]: number } = {}
	local function sec(s: number): Sector
		local r = sectors[s]
		if not r then
			r = { count = 0, tris = 0, factor = 1, demand = 0 }
			sectors[s] = r
		end
		return r
	end
	local function add(key: string, s: number, n: number)
		local r = sec(s)
		r.count += n
		r.tris += n * ArtBudget.tris(key)
		byKey[key] = (byKey[key] or 0) + n
	end
	local function at(x: number, z: number): number
		return Geometry.sectorAt(MapConfig.Sectors, x, z) or 0
	end

	-- 1) casas: variante sorteada + quintal (35% coqueiro, 30% bananeira)
	local hs = Features.houses
	local v = ArtBudget.HOUSE_VARIANTS
	for i = 1, #hs, 4 do
		local s = at(hs[i], hs[i + 1])
		for _, key in v do
			add(key, s, 1 / #v)
		end
		add("coconut_palm", s, 0.35)
		add("banana", s, 0.3)
	end
	-- 2) An Cường (2): túneis, bunkers, trincheira (a cada 4 m), altar, poço; cemitério; vau
	local cx, cz = 0, 0
	for _, l in MapConfig.Locations do
		if l.name == "An Cường (2)" then
			cx, cz = l.x, l.z
		end
	end
	for id, n in Tunnels.nodes do
		if n.entrance then
			local s = at(Tunnels.toWorld(cx, cz, n.x, n.z))
			add("tunnel_entrance", s, 1)
			if id == "E1" or id == "E2" or id == "E4" then
				add("vc_bunker", s, 1)
			end
		end
	end
	for i = 1, #Tunnels.trench - 1 do
		local a, b = Tunnels.trench[i], Tunnels.trench[i + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		add("trench_section", at(Tunnels.toWorld(cx, cz, a[1], a[2])), math.floor(len / 4))
	end
	add("shrine", at(cx, cz), 1)
	add("well", at(cx, cz), 1)
	for _, sp in MapConfig.Strongpoints do
		if sp.name == "Cemitério" then
			add("grave_mound", at(sp.x, sp.z), 6)
		elseif sp.name == "Vau do riacho" then
			add("log_bridge", at(sp.x, sp.z), 1)
		end
	end
	-- 3) bosques das colinas
	for _, l in MapConfig.Locations do
		if string.find(l.name, "Colina") then
			add("hill_tree", at(l.x, l.z), 60)
		end
	end
	-- 4) animais da vila (antes das sebes, como no AssetLoader); sorteio com semente fixa
	local housesM = {}
	for i = 1, #hs, 4 do
		table.insert(housesM, hs[i] * M)
		table.insert(housesM, hs[i + 1] * M)
	end
	local rng = Rng.new(1)
	for _, a in
		Animals.spawns(housesM, function()
			return rng:next()
		end)
	do
		add(a.species, at(a.x / M, a.z / M), 1)
	end
	-- 5) sebes por último, desbastadas pelo que sobrou do teto do setor
	type Job = { s: number, tall: boolean, n: number }
	local jobs: { Job } = {}
	local hg = Features.hedges
	for i = 1, #hg, 7 do
		local x1, z1, x2, z2, hh, th = hg[i], hg[i + 1], hg[i + 2], hg[i + 3], hg[i + 5], hg[i + 6]
		local s = at((x1 + x2) / 2, (z1 + z2) / 2)
		if SLICE[s] then
			local tall = hh > 3 / M
			local lenM = (math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) + th * 0.5) * M
			local n = ArtBudget.hedgeClumps(lenM, tall)
			table.insert(jobs, { s = s, tall = tall, n = n })
			sec(s).demand += n * (if tall
				then ArtBudget.tris("bamboo_clump")
				else (ArtBudget.tris("shrub") + ArtBudget.tris("elephant_grass")) / 2)
		end
	end
	for s, r in sectors do
		r.factor = ArtBudget.factor(r.tris, r.demand)
	end
	for _, j in jobs do
		local f = sectors[j.s].factor
		if j.tall then
			add("bamboo_clump", j.s, j.n * f)
		else
			add("shrub", j.s, j.n * f / 2)
			add("elephant_grass", j.s, j.n * f / 2)
		end
	end
	-- 6) QGs, quintais, tocas e canteiros de arroz (D-64): valores esperados do AssetLoader
	add("sandbags", at(MapConfig.HQ.US.x, MapConfig.HQ.US.z), 8)
	add("bamboo_fence", at(MapConfig.HQ.VC.x, MapConfig.HQ.VC.z), 12)
	add("granary", at(MapConfig.HQ.VC.x, MapConfig.HQ.VC.z), 2)
	add("vc_bunker", at(MapConfig.HQ.VC.x, MapConfig.HQ.VC.z), 1)
	for i = 1, #hs, 4 do
		local s = at(hs[i], hs[i + 1])
		add("granary", s, 0.15)
		add("bamboo_fence", s, 0.3 * 3)
	end
	for _, sp in MapConfig.Strongpoints do
		if sp.sector <= 3 then
			add("spider_hole", sp.sector, 3)
		end
	end
	for _, l in MapConfig.Locations do
		if l.name == "An Cường (2)" or l.name == "Nam Yên (4)" or l.name == "An Thới (2)" then
			add("rice_patch", at(l.x, l.z), 8)
		end
	end
	-- 7) mata por uso do solo, por último, desbastada pelo que sobrou do teto (mesmo plano do jogo)
	local chunks = {}
	for _, name in Grid.heightChunks do
		table.insert(chunks, (require :: any)("../src/ServerStorage/VT65Build/Data/" .. name))
	end
	local world = WorldData.load(Grid, chunks)
	local housesXZ, tunnelXZ = {}, {}
	for i = 1, #hs, 4 do
		table.insert(housesXZ, hs[i])
		table.insert(housesXZ, hs[i + 1])
	end
	for _, n in Tunnels.nodes do
		local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
		table.insert(tunnelXZ, x)
		table.insert(tunnelXZ, z)
	end
	-- raias: a direção preferida (no jogo, a escolhida pelo TrainingService), 330 m a partir do QG
	local corridors = {}
	for f, hq in MapConfig.HQ do
		local lane = Tutorial.RANGE_LANE[f]
		if lane then
			local x2, z2 = hq.x + lane.dir[1] * 330 / M, hq.z + lane.dir[2] * 330 / M
			table.insert(corridors, { x1 = hq.x, z1 = hq.z, x2 = x2, z2 = z2, w = 10 / M })
		end
	end
	local plan = Vegetation.plan({
		classAt = function(x: number, z: number): number
			return world:classAt(x, z)
		end,
		bounds = MapConfig.Bounds,
		cell = Grid.cellStuds,
		exclude = Vegetation.exclusions(MapConfig, housesXZ, tunnelXZ),
		corridors = corridors,
		density = ArtBudget.JUNGLE_DENSITY,
		seed = 1965,
		rng = Rng.new(19650818 + 64),
	})
	local demand: { [number]: number } = {}
	local planned: { [number]: { [string]: number } } = {}
	for _, it in plan do
		local s = at(it.x, it.z)
		demand[s] = (demand[s] or 0) + ArtBudget.tris(it.key)
		planned[s] = planned[s] or {}
		planned[s][it.key] = (planned[s][it.key] or 0) + 1
	end
	local jungle: { [number]: { planned: number, factor: number } } = {}
	for s, d in demand do
		local f = ArtBudget.factor(sec(s).tris, d)
		local n = 0
		for key, c in planned[s] do
			add(key, s, c * f)
			n += c
		end
		jungle[s] = { planned = n, factor = f }
	end
	return { sectors = sectors, byKey = byKey, jungle = jungle }
end
