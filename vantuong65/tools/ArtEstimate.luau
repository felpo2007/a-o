--!strict
-- Estimativa offline da arte por setor (F5): instâncias e triângulos que o AssetLoader coloca, com
-- as mesmas regras (ordem, densidade, teto e desbaste das sebes), a partir dos dados do mapa e do
-- ArtBudget. É valor esperado: o sorteio real depende da ordem das peças no Roblox. Não é medição.
local ArtBudget = require("../src/ServerScriptService/Modules/ArtBudget")
local Features = require("../src/ServerStorage/VT65Build/Data/Features") :: any
local Geometry = require("../src/ReplicatedStorage/Shared/Geometry")
local MapConfig = require("../src/ReplicatedStorage/Shared/MapConfig") :: any
local Tunnels = require("../src/ReplicatedStorage/Shared/Tunnels") :: any

export type Sector = { count: number, tris: number, factor: number, demand: number }
export type Result = { sectors: { [number]: Sector }, byKey: { [string]: number } }

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
	-- 4) sebes por último, desbastadas pelo que sobrou do teto do setor
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
	return { sectors = sectors, byKey = byKey }
end
