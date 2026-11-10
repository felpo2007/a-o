--!strict
-- Se o place foi publicado sem terreno (ex.: via Open Cloud, sem passar pelo Studio), o servidor
-- gera o terreno ao iniciar (mesmo código do Build.terrain) e só então libera o spawn.
-- Atributo ReplicatedStorage.TerrainReady avisa clientes, SpawnService e bots.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TerrainRuntime = {}

local function hasTerrain(): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	-- amostra 5 pontos da área: se nenhum tem terreno, consideramos vazio
	for _, p in { { 0, 0 }, { 3000, 1000 }, { -3000, -1000 }, { 5000, 2000 }, { -5000, 3000 } } do
		if workspace:Raycast(Vector3.new(p[1], 1500, p[2]), Vector3.new(0, -3000, 0), params) then
			return true
		end
	end
	return false
end

function TerrainRuntime.ready(): boolean
	return ReplicatedStorage:GetAttribute("TerrainReady") == true
end

function TerrainRuntime.start()
	if hasTerrain() then
		ReplicatedStorage:SetAttribute("TerrainReady", true)
		return
	end
	ReplicatedStorage:SetAttribute("TerrainReady", false)
	local Build = require(ServerStorage:WaitForChild("VT65Build"):WaitForChild("Build")) :: any
	local t0 = os.clock()
	local ok, err = pcall(Build.terrain)
	if not ok then
		warn("[VT65] falha ao gerar terreno:", err)
	end
	print(string.format("[VT65] terreno gerado em runtime em %.0f s", os.clock() - t0))
	ReplicatedStorage:SetAttribute("TerrainReady", true)
end

return TerrainRuntime
