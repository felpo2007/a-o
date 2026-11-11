--!strict
-- Aparência do terreno e do céu (D-64): cores dos materiais, grama animada, água dos riachos e
-- nuvens. Antes o terreno usava as cores padrão do Roblox. Valores de arte, ajustados por captura
-- no Studio contra fotos de Quảng Ngãi (arrozal verde em agosto, laterita marrom-avermelhada).
local TerrainLook = {}

-- cor multiplica a textura do material; tons medidos a olho nas capturas, não em foto calibrada
TerrainLook.COLORS = {
	Grass = Color3.fromRGB(72, 92, 42), -- arroz e capim de agosto; mais claro parecia gramado
	LeafyGrass = Color3.fromRGB(92, 90, 54), -- chão de mata: folhas secas sobre capim
	Ground = Color3.fromRGB(108, 86, 60), -- chão de mata e de vila, folhas secas
	Mud = Color3.fromRGB(96, 76, 54), -- barranco de riacho
	Sand = Color3.fromRGB(188, 168, 126),
	Rock = Color3.fromRGB(112, 104, 92),
}

-- Atribui sem quebrar se a propriedade não existir ou não puder ser escrita por script.
local function set(obj: Instance, prop: string, value: any)
	local ok, err = pcall(function()
		(obj :: any)[prop] = value
	end)
	if not ok then
		warn("[VT65] aparência do terreno:", prop, err)
	end
end

function TerrainLook.apply()
	local terrain = workspace.Terrain
	for name, color in TerrainLook.COLORS do
		local mat = (Enum.Material :: any)[name]
		pcall(function()
			terrain:SetMaterialColor(mat, color)
		end)
	end
	-- A grama animada (Decoration, GrassLength) vem ligada no arquivo do place (tools/bake_place):
	-- script do jogo não pode escrever essas propriedades.
	-- riacho barrento e quase parado
	set(terrain, "WaterColor", Color3.fromRGB(62, 70, 46))
	set(terrain, "WaterTransparency", 0.55)
	set(terrain, "WaterReflectance", 0.7)
	set(terrain, "WaterWaveSize", 0.04)
	set(terrain, "WaterWaveSpeed", 3)
	-- Sem nuvens dinâmicas (D-69): o usuário viu o céu "pixelando muito e trocando conforme eu
	-- olho". As nuvens volumétricas do Roblox são desenhadas em baixa resolução, com ruído que
	-- muda com o giro da câmera; com a névoa da Atmosphere ficava pior. As nuvens vêm do Sky.
	for _, c in terrain:GetChildren() do
		if c:IsA("Clouds") then
			c:Destroy()
		end
	end
end

return TerrainLook
