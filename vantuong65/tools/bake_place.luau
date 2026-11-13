--!strict
-- Lune: assa as peças do greybox (FeatureBuilder) no place gerado pelo Rojo.
-- Uso (a partir de vantuong65/):
--   rojo build default.project.json -o build/VanTuong65_base.rbxl
--   lune run tools/bake_place.luau
-- Saída: build/VanTuong65_F1.rbxl (o terreno é gerado depois, no Studio: ver README).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local FeatureBuilder = require("../src/ServerStorage/VT65Build/FeatureBuilder")
local MapConfig = require("../src/ReplicatedStorage/Shared/MapConfig")
local Features = require("../src/ServerStorage/VT65Build/Data/Features")
local WorldData = require("../src/ServerStorage/VT65Build/WorldData")
local Grid = require("../src/ServerStorage/VT65Build/Data/Grid") :: any

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, (require :: any)("../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)

local game = roblox.deserializePlace(fs.readFile("build/VanTuong65_base.rbxl"))
local workspace = game:GetService("Workspace")
local env = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}
local t0 = os.clock()
-- paisagem da D-65 (dique, lâmina e sebe de arrozal só na lavoura das vilas e nas clareiras) pelo
-- plano da arte (2026-11-12): a mesma do servidor, com a vila grande e as lâminas que ficaram; o
-- dique é marcador invisível só onde encosta num tabuleiro (a lombada é do terreno)
local ArtPlan = (require :: any)("../src/ServerScriptService/Modules/ArtPlan")
local ctx = ArtPlan.load(world, {
	features = Features,
	village = (require :: any)("../src/ServerStorage/VT65Build/Data/Village"),
	roads = (require :: any)("../src/ServerStorage/VT65Build/Data/Roads"),
	mapConfig = MapConfig,
})
local stats = FeatureBuilder.build(env, Features, MapConfig, world, workspace, ctx.landscape, function(x1, z1, x2, z2)
	return ArtPlan.dikeKept(ctx.paddies, x1, z1, x2, z2)
end)
local TunnelGeometry = require("../src/ServerStorage/VT65Build/TunnelGeometry")
local Tunnels = require("../src/ReplicatedStorage/Shared/Tunnels")
local cx, cz = 0, 0
for _, l in MapConfig.Locations do
	if l.name == "An Cường (2)" then
		cx, cz = l.x, l.z
	end
end
local boxes = TunnelGeometry.build(env, Tunnels, cx, cz, function(x, z)
	return world:heightAt(x, z)
end)
local nt = FeatureBuilder.tunnels(env, boxes, workspace:FindFirstChild("Map"))
print(string.format("túneis: %d peças, %.0f m de galeria", nt, Tunnels.length()))
print(
	string.format(
		"peças: %d diques, %d lâminas, %d sebes, %d casas, %d marcadores (%.1f s)",
		stats.dikes,
		stats.waters,
		stats.hedges,
		stats.houses,
		stats.markers,
		os.clock() - t0
	)
)
-- Grama animada (D-64): Terrain.Decoration e GrassLength só podem ser escritos por plugin ou no
-- arquivo; o script do jogo leva "lacking capability PluginOrOpenCloud" (teste no Studio, 2026-11-10).
-- O place do Rojo vem sem Terrain (o Studio cria um vazio ao abrir): criamos aqui, com as
-- propriedades, e o servidor gera os voxels em runtime (TerrainRuntime).
local terrain = workspace:FindFirstChildOfClass("Terrain")
if not terrain then
	local ok, t = pcall(function()
		local t = roblox.Instance.new("Terrain")
		t.Name = "Terrain"
		t.Parent = workspace
		return t
	end)
	terrain = if ok then t else nil
end
if terrain then
	local ok, err = pcall(function()
		(terrain :: any).Decoration = true;
		(terrain :: any).GrassLength = 1
	end)
	print(if ok then "terreno: grama animada ligada" else "terreno: sem grama animada (" .. tostring(err) .. ")")
else
	print("terreno: Workspace sem Terrain no place base")
end
-- Chão fotográfico (D-66): texturas PBR do Poly Haven (CC0) como MaterialVariant do terreno, no
-- tamanho real da foto, com padrão "Organic" para disfarçar a repetição. MaterialService troca o
-- material base do terreno pela variante (override por nome).
local AssetIds = require("../src/ReplicatedStorage/Shared/AssetIds") :: any
local GI = AssetIds.GroundImages
local CHAO = {
	{ material = "LeafyGrass", id = "forrest_ground_01", ladoM = 2.0 },
	{ material = "Grass", id = "leafy_grass", ladoM = 2.0 },
	{ material = "Mud", id = "brown_mud_leaves_01", ladoM = 1.3 },
	{ material = "Ground", id = "forest_ground_06", ladoM = 2.11 },
}
local ms = game:GetService("MaterialService")
local nVar, nOverride = 0, 0
for _, c in CHAO do
	local cor, normal, rug = GI[c.id .. "_cor"], GI[c.id .. "_normal"], GI[c.id .. "_rugosidade"]
	if cor and cor ~= 0 then
		local v = roblox.Instance.new("MaterialVariant")
		v.Name = "VT65_" .. c.material
		v.BaseMaterial = (roblox.Enum.Material :: any)[c.material]
		v.ColorMap = "rbxassetid://" .. cor
		v.NormalMap = "rbxassetid://" .. normal
		v.RoughnessMap = "rbxassetid://" .. rug
		v.StudsPerTile = c.ladoM / 0.28
		v.MaterialPattern = roblox.Enum.MaterialPattern.Organic
		v.Parent = ms
		nVar += 1
		local ok = pcall(function()
			(ms :: any)[c.material .. "Name"] = v.Name
		end)
		if ok then
			nOverride += 1
		end
	end
end
print(string.format("chão: %d variantes de material, %d trocas de material base", nVar, nOverride))
fs.writeFile("build/VanTuong65_F1.rbxl", roblox.serializePlace(game))
print("gravado build/VanTuong65_F1.rbxl")
