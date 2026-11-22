--!strict
-- Aparência do terreno e do céu (D-64): cores dos materiais, grama animada, água dos riachos e
-- nuvens. Antes o terreno usava as cores padrão do Roblox. Valores de arte, ajustados por captura
-- no Studio contra fotos de Quảng Ngãi (arrozal verde em agosto, laterita marrom-avermelhada).
local TerrainLook = {}

-- cor multiplica a textura do material; tons medidos a olho nas capturas, não em foto calibrada
TerrainLook.COLORS = {
	-- D-127 (escolha do dono, lote 13): mais claro. Com (72, 92, 42) a textura leafy_grass (média
	-- 151, 131, 89) saía perto de (43, 47, 15), verde quase preto e chapado, e o relevo sumia; este dá
	-- ~(59, 70, 26) e os diques aparecem (testes/lote12, capturas 05 e 06). Antes: "mais claro parecia
	-- gramado".
	Grass = Color3.fromRGB(100, 134, 74), -- arroz e capim de agosto
	LeafyGrass = Color3.fromRGB(92, 90, 54), -- chão de mata: folhas secas sobre capim
	-- D-123 (dono: "conserte o solo"): o terreno multiplica a textura pela cor. A terra batida (dirt_floor,
	-- D-115) tem média (182, 140, 100), alaranjada; com (108, 86, 60) as ruas saíam vermelho-escuro
	-- (~77, 47, 23). Com (150, 168, 200) saíam ~(107, 92, 78), cinza; sem a foto (aparelho fraco, foto
	-- ainda carregando) a cor azulada sobre o Ground padrão do Roblox dava estrada cinza-azulada. D-148
	-- (dono: "as estradas não estão feitas de terra"): tom levemente quente, marrom nos dois casos:
	-- com a foto ~(136, 94, 58), terra de laterita (no Studio, v78: rua e praça marrom-alaranjadas).
	-- D-237 (dono: "o chão de alguns lugares ainda está branco"): quando a foto não carrega sobra só a
	-- cor do terreno, e (190, 172, 148) era um bege quase branco. A foto agora é neutra (média 200) e a
	-- cor mora aqui: com a foto continua ~(136, 94, 58); sem ela, laterita (173, 120, 74).
	-- D-241: menos laranja com a luz nova (a grama fica como o dono escolheu na D-127)
	-- D-251 (imagens do dono): na luz de fim de tarde (D-248) a laterita saía vermelha e chapada; este
	-- tom dá o marrom de barro das referências
	Ground = Color3.fromRGB(134, 110, 84), -- terra batida das ruas, becos, praça e quintais
	Mud = Color3.fromRGB(90, 80, 64), -- barranco de riacho (D-123: menos vermelho)
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
