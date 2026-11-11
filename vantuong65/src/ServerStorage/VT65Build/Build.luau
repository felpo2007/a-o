--!strict
-- Ponto de entrada no Studio (barra de comando, modo de edição):
--   require(game.ServerStorage.VT65Build.Build).terrain()   -- gera o terreno (minutos)
--   require(game.ServerStorage.VT65Build.Build).features()  -- recria as peças (já vêm no .rbxl)
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VT65Build = script.Parent
local WorldData = require(VT65Build.WorldData)
local Data = VT65Build.Data

local Build = {}

function Build.world(): WorldData.World
	local grid = require(Data.Grid) :: any
	local chunks = {}
	for _, name in grid.heightChunks do
		table.insert(chunks, require(Data:FindFirstChild(name) :: ModuleScript) :: any)
	end
	return WorldData.load(grid, chunks)
end

local function tunnelBoxes(world: any): { any }
	local TunnelGeometry = require(VT65Build.TunnelGeometry) :: any
	local Tunnels = require(ReplicatedStorage.Shared.Tunnels) :: any
	local mapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
	local cx, cz = 0, 0
	for _, l in mapConfig.Locations do
		if l.name == "An Cường (2)" then
			cx, cz = l.x, l.z
		end
	end
	local env = { Vector3 = Vector3, CFrame = CFrame }
	return TunnelGeometry.build(env, Tunnels, cx, cz, function(x, z)
		return world:heightAt(x, z)
	end)
end

function Build.terrain()
	local TerrainBuilder = require(VT65Build.TerrainBuilder)
	workspace.Terrain:Clear()
	local world = Build.world()
	TerrainBuilder.build(world)
	local n = TerrainBuilder.carve(tunnelBoxes(world))
	print("[VT65] túneis e trincheira escavados:", n, "blocos")
end

function Build.features()
	local FeatureBuilder = require(VT65Build.FeatureBuilder) :: any
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local env = { Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum }
	local mapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
	local world = Build.world()
	local features = require(Data.Features) :: any
	local housesXZ = {}
	for i = 1, #features.houses, 4 do
		table.insert(housesXZ, features.houses[i])
		table.insert(housesXZ, features.houses[i + 1])
	end
	local landscape = require(VT65Build.Landscape).new(world, mapConfig, housesXZ)
	local stats = FeatureBuilder.build(env, features, mapConfig, world, workspace, landscape)
	FeatureBuilder.tunnels(env, tunnelBoxes(world), workspace:FindFirstChild("Map"))
	print(
		"[VT65] peças:",
		stats.dikes,
		"diques,",
		stats.waters,
		"lâminas,",
		stats.hedges,
		"sebes,",
		stats.houses,
		"casas"
	)
end

local _ = ServerStorage
return Build
