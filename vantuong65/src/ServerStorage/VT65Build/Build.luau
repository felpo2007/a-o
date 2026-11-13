--!strict
-- Ponto de entrada no Studio (barra de comando, modo de edição):
--   require(game.ServerStorage.VT65Build.Build).terrain()   -- gera o terreno (minutos)
--   require(game.ServerStorage.VT65Build.Build).features()  -- recria as peças (já vêm no .rbxl)
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

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

-- Dados do mapa para o plano da arte (ArtPlan.load): feições, vila grande e estradas (2026-11-12)
function Build.data(): any
	local function opt(name: string): any
		local m = Data:FindFirstChild(name)
		return if m then require(m :: ModuleScript) :: any else nil
	end
	return {
		features = require(Data.Features) :: any,
		village = opt("Village"),
		roads = opt("Roads"),
		mapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any,
	}
end

-- Modelo publicado (AssetIds.Models diferente de 0)
function Build.has(key: string): boolean
	local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
	local id = AssetIds.Models[key]
	return type(id) == "number" and id ~= 0
end

-- Plano do chão e das construções (ArtPlan): o mesmo no terreno e no AssetLoader. Devolve o contexto
-- (com os patamares das construções já no Site) e a lista de construções.
function Build.plan(world: any): (any, { any })
	local ArtPlan = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ArtPlan")) :: any
	local ctx = ArtPlan.load(world, Build.data())
	local structures = ArtPlan.structures(ctx, Build.has)
	return ctx, structures
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

-- Tabuleiros do arrozal que existem no place (o mesmo filtro do plano da arte).
function Build.paddySet(world: WorldData.World): any
	local ctx = Build.plan(world)
	return ctx.paddies
end

-- 2026-11-12: a coluna do terreno sai do plano da arte (ArtPlan.column: riacho, tabuleiros, diques
-- em lombada, patamares das construções, estradas, becos e a roça seca). O atributo SitePlan diz ao
-- AssetLoader que pode assentar cada coisa pela altura do plano.
function Build.terrain()
	local TerrainBuilder = require(VT65Build.TerrainBuilder)
	local ArtPlan = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ArtPlan")) :: any
	workspace.Terrain:Clear()
	local world = Build.world()
	local ctx = Build.plan(world)
	TerrainBuilder.build(world, nil, {
		column = function(x: number, z: number): (number, number, number, string?)
			return ArtPlan.column(ctx, x, z)
		end,
	})
	workspace.Terrain:SetAttribute("PaddiesFlat", true)
	workspace.Terrain:SetAttribute("SitePlan", ArtPlan.VERSION)
	local n = TerrainBuilder.carve(tunnelBoxes(world))
	print("[VT65] túneis e trincheira escavados:", n, "blocos")
end

function Build.features()
	local FeatureBuilder = require(VT65Build.FeatureBuilder) :: any
	local ArtPlan = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ArtPlan")) :: any
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local env = { Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum }
	local world = Build.world()
	local data = Build.data()
	local ctx = ArtPlan.load(world, data)
	local stats = FeatureBuilder.build(
		env,
		data.features,
		data.mapConfig,
		world,
		workspace,
		ctx.landscape,
		function(x1: number, z1: number, x2: number, z2: number): boolean
			return ArtPlan.dikeKept(ctx.paddies, x1, z1, x2, z2)
		end
	)
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
