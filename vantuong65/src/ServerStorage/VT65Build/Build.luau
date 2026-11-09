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

function Build.terrain()
	local TerrainBuilder = require(VT65Build.TerrainBuilder)
	workspace.Terrain:Clear()
	TerrainBuilder.build(Build.world())
end

function Build.features()
	local FeatureBuilder = require(VT65Build.FeatureBuilder) :: any
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local env = { Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum }
	local mapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
	local stats = FeatureBuilder.build(env, require(Data.Features), mapConfig, Build.world(), workspace)
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
