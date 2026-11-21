--!strict
-- D-191 (dono: "adaptação dos sons e efeitos ao material diretamente sob o personagem"): o piso de um
-- raio para baixo, em uma palavra, para os passos (AudioController) e a granada (FieldService,
-- GrenadePhysics). Módulo PURO (tests/luau/superficie.luau): quem chama passa os nomes.
--   - "grass" terra seca, grama e mato; "mud" lama, dique e terra molhada; "paddy" arrozal (água rasa
--     sobre lama); "water" água; "sand" areia, cascalho e sacos de areia; "wood" madeira de casas,
--     pontes e barcos; "metal" veículos e plataformas; "stone" pedra, tijolo e concreto.
-- O piso logo embaixo vale mais que o lugar: numa ponte de madeira sobre o rio o raio para na ponte.
-- Divisas: Superficie.stable só troca depois de STABLE_HITS leituras seguidas do piso novo.
local Superficie = {}

local TERRAIN: { [string]: string } = {
	Water = "water",
	Mud = "mud",
	Sand = "sand",
	Grass = "grass",
	LeafyGrass = "grass",
	Ground = "grass",
	Rock = "stone",
	Slate = "stone",
	Basalt = "stone",
	Limestone = "stone",
	Granite = "stone",
	Sandstone = "stone",
	Concrete = "stone",
	Pavement = "stone",
	Cobblestone = "stone",
	Asphalt = "stone",
	Brick = "stone",
	CrackedLava = "stone",
	Salt = "sand",
	Snow = "grass",
	Glacier = "stone",
}

local PART: { [string]: string } = {
	Wood = "wood",
	WoodPlanks = "wood",
	Metal = "metal",
	DiamondPlate = "metal",
	CorrodedMetal = "metal",
	Foil = "metal",
	Concrete = "stone",
	Brick = "stone",
	Cobblestone = "stone",
	Slate = "stone",
	Granite = "stone",
	Marble = "stone",
	Pebble = "sand",
	Rock = "stone",
	Basalt = "stone",
	Limestone = "stone",
	Pavement = "stone",
	Asphalt = "stone",
	Sand = "sand",
	Fabric = "sand", -- sacos de areia (Logistics) e lona
	Mud = "mud",
	Ground = "mud",
	Grass = "grass",
	LeafyGrass = "grass",
	Water = "water",
}

-- terrain: o raio parou no Terrain; materialName: o Enum.Material.Name do ponto; partName e attr: o
-- nome da peça e o atributo "Material" dela (o arrozal e o dique do gerador); bridge: a peça é de
-- uma ponte de toras ("log_bridge").
function Superficie.of(
	terrain: boolean,
	materialName: string?,
	partName: string?,
	attr: string?,
	bridge: boolean?
): string
	if terrain then
		return TERRAIN[materialName or ""] or "grass"
	end
	if attr == "PaddyWater" then
		return "paddy"
	elseif partName == "Dike" then
		return "mud"
	elseif bridge then
		return "wood"
	end
	return PART[materialName or ""] or "grass"
end

-- Som de passo de cada piso. Faltam no jogo os passos em metal e em pedra (sem asset próprio):
-- PLACEHOLDER com o da madeira (oco) e o da areia (áspero) até eles existirem.
Superficie.STEP = {
	grass = "step_grass",
	mud = "step_mud",
	paddy = "step_paddy",
	water = "step_paddy",
	sand = "step_sand",
	wood = "step_wood",
	metal = "step_wood",
	stone = "step_sand",
} :: { [string]: string }
Superficie.MISSING_STEPS = { "step_metal", "step_stone" }

-- Divisas sem pisca-pisca: o piso só troca depois de STABLE_HITS leituras seguidas do novo.
Superficie.STABLE_HITS = 2
export type Stable = { cur: string?, cand: string?, n: number }
function Superficie.newStable(): Stable
	return { cur = nil, cand = nil, n = 0 }
end
function Superficie.stable(s: Stable, read: string): string
	if s.cur == nil or read == s.cur then
		s.cur, s.cand, s.n = read, nil, 0
		return read
	end
	if read == s.cand then
		s.n += 1
	else
		s.cand, s.n = read, 1
	end
	if s.n >= Superficie.STABLE_HITS then
		s.cur, s.cand, s.n = read, nil, 0
	end
	return s.cur :: string
end

return Superficie
