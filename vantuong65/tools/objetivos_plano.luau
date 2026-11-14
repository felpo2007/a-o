--!strict
-- Lune: confere as construções dos objetivos do plano da arte (lote 26b, D-141): quantas peças cada
-- objetivo ganhou, onde (m do mastro), giro, base e o chão sob cada uma. A ponte e o cais mostram o
-- espelho d'água do rio e as margens.
-- Uso (a partir de vantuong65/): lune run tools/objetivos_plano.luau
local Landscape = require("../src/ServerStorage/VT65Build/Landscape")
local WorldData = require("../src/ServerStorage/VT65Build/WorldData")
local Site = require("../src/ServerStorage/VT65Build/Site") :: any
local Features = require("../src/ServerStorage/VT65Build/Data/Features") :: any
local Village = require("../src/ServerStorage/VT65Build/Data/Village") :: any
local Roads = require("../src/ServerStorage/VT65Build/Data/Roads") :: any
local Grid = require("../src/ServerStorage/VT65Build/Data/Grid") :: any
local Bases = require("../src/ServerStorage/VT65Build/Data/Bases") :: any
local MapConfig = require("../src/ReplicatedStorage/Shared/MapConfig") :: any
local AssetIds = require("../src/ReplicatedStorage/Shared/AssetIds") :: any
local ArtPlan = require("../src/ServerScriptService/Modules/ArtPlan") :: any
local _ = Landscape

local M = 0.28
local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, (require :: any)("../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)
local ctx =
	ArtPlan.load(world, { features = Features, village = Village, roads = Roads, bases = Bases, mapConfig = MapConfig })
local structures = ArtPlan.structures(ctx, function(k: string): boolean
	local id = AssetIds.Models[k]
	return type(id) == "number" and id ~= 0
end)

local flags: { [string]: any } = {}
for _, sp in MapConfig.Strongpoints do
	flags[sp.name] = sp
end
for name, n in ctx.objectiveCount or {} do
	print(string.format("%s: %d peças", name, n))
end
for _, it in structures do
	if it.objective then
		local sp = flags[it.objective]
		local d = math.sqrt((it.x - sp.x) ^ 2 + (it.z - sp.z) ^ 2) * M
		local lo, hi = ArtPlan.footprint(ctx, it.x, it.z, it.yaw, it.hx, it.hz)
		local _, wl = Site.column(ctx.site, it.x, it.z)
		print(
			string.format(
				"  %-14s %-16s a %5.1f m do mastro  giro %6.1f°  %4.1f x %4.1f m  base %6.2f m  chão %6.2f..%6.2f m%s%s",
				it.objective,
				it.key,
				d,
				math.deg(it.yaw) % 360,
				it.hx * 2 * M,
				it.hz * 2 * M,
				it.base * M,
				lo * M,
				hi * M,
				if wl > -math.huge then string.format("  água %.2f m", wl * M) else "",
				if it.afloat then "  (no rio)" else ""
			)
		)
	end
end
