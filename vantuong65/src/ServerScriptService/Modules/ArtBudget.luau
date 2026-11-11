--!strict
-- Orçamento de triângulos da arte (Parte 2). Módulo puro: o AssetLoader usa, o teste da F5 confere
-- cada número contra assets/forgegui/manifest.json (triângulos medidos no GLB preparado).
-- Metas da Parte 2: vegetação ≤ 3.000, props ≤ 5.000, herói (arma, veículo) ≤ 20.000.
local ArtBudget = {}

-- D-66 (pedido do usuário): vegetação e props com no mínimo 8 mil triângulos, na malha cheia do
-- gerador. O teto vira o limite do Roblox por malha (20 mil). Antes: veg ≤ 3 mil e props ≤ 5 mil.
ArtBudget.MAX = { veg = 20000, prop = 20000, hero = 20000 } :: { [string]: number }
ArtBudget.MIN_VEG = 8000
-- teto de arte por setor; PLACEHOLDER até medir fps no Studio com a mata (D-45, D-64, D-65). A
-- mata fechada da D-65 pede até 35,6 milhões no setor 5 (tools/ArtEstimate, sem teto); o cliente
-- só carrega o raio de streaming (430 m), não o mapa inteiro.
-- D-66: com a vegetação de 8 mil+ triângulos o plano inteiro soma ~617 milhões (setor 5: 155 mi);
-- o teto cabe o plano todo. O cliente carrega só o raio de streaming, com o LOD automático do Roblox.
ArtBudget.SECTOR_MAX = 160000000
-- multiplica a densidade da mata (Vegetation.plan); 1 = valores de projeto da D-64
ArtBudget.JUNGLE_DENSITY = 1
-- chave sem número medido: assume um modelo não reduzido (o pior caso do manifest é ~15,8k)
ArtBudget.DEFAULT = 16000

ArtBudget.KIND = {
	bamboo_clump = "veg",
	shrub = "veg",
	elephant_grass = "veg",
	banana = "veg",
	coconut_palm = "veg",
	hill_tree = "veg",
	rice_patch = "veg",
	-- mata fechada (D-65)
	canopy_tree = "veg",
	vine_tree = "veg",
	melaleuca_grove = "veg",
	taro_fern = "veg",
	hut_thatch = "prop",
	hut_veranda = "prop",
	hut_kitchen = "prop",
	house_tile = "prop",
	granary = "prop",
	well = "prop",
	shrine = "prop",
	grave_mound = "prop",
	tunnel_entrance = "prop",
	vc_bunker = "prop",
	trench_section = "prop",
	bamboo_fence = "prop",
	sandbags = "prop",
	spider_hole = "prop",
	log_bridge = "prop",
	-- equipamento vestido: 60 jogadores, então conta como prop
	us_m1_helmet = "prop",
	us_m1955_vest = "prop",
	vc_pith_helmet = "prop",
	vc_jungle_hat = "prop",
	-- animais da vila (Parte 11)
	water_buffalo = "prop",
	chicken = "prop",
	m60 = "hero",
	rpd = "hero",
	sks = "hero",
	m1911 = "hero",
	type54 = "hero",
	m79 = "hero",
	rpg2 = "hero",
	mortar_81 = "hero",
	mortar_82 = "hero",
	uh34d = "hero",
	m48a3 = "hero",
	lvtp5 = "hero",
	ontos = "hero",
} :: { [string]: string }

-- triângulos medidos (manifest.json, campo "triangulos"): remesh do ForgeGUI ou, quando ele terminou
-- em outcome_unknown, redução local (tools/decimate_glb.py)
ArtBudget.TRIS = {
	-- vegetação na malha cheia do gerador (D-66; antes, remesh de 1,9–2,8 mil)
	bamboo_clump = 11456,
	shrub = 10515,
	elephant_grass = 7978,
	banana = 12686,
	coconut_palm = 13261,
	hill_tree = 13215,
	rice_patch = 13066,
	canopy_tree = 13636,
	melaleuca_grove = 10995,
	taro_fern = 8397,
	vine_tree = 13215, -- sem modelo (outcome_unknown): o substituto é a hill_tree
	-- props na malha cheia do gerador (D-66; antes, remesh de 2,8–4,9 mil)
	hut_thatch = 13030,
	hut_veranda = 13249,
	hut_kitchen = 13483,
	house_tile = 14938,
	granary = 14106,
	well = 13615,
	shrine = 13489,
	grave_mound = 14278,
	tunnel_entrance = 13576,
	vc_bunker = 11287,
	trench_section = 12072,
	bamboo_fence = 16418,
	sandbags = 17067,
	spider_hole = 9602,
	log_bridge = 15388,
	us_m1_helmet = 3000,
	us_m1955_vest = 3999,
	vc_pith_helmet = 2999,
	vc_jungle_hat = 2447,
	water_buffalo = 14459,
	chicken = 16688,
	m60 = 14933,
	rpd = 15735,
	sks = 14683,
	m1911 = 15340,
	type54 = 15316,
	m79 = 14756,
	rpg2 = 15826,
	mortar_81 = 2884,
	mortar_82 = 14959,
	uh34d = 15061,
	m48a3 = 14684,
	lvtp5 = 13970,
	ontos = 13093,
} :: { [string]: number }

-- Acima da meta, com o motivo. O teste falha se um modelo passar da meta sem estar aqui, ou se
-- uma exceção ficar velha (o modelo já cabe na meta).
ArtBudget.EXCEPTIONS = {} :: { [string]: string }
-- abaixo do mínimo de 8 mil (D-66), com o motivo
ArtBudget.BELOW_MIN = {
	elephant_grass = "a malha cheia do gerador tem 7.978; não há versão maior",
} :: { [string]: string }

-- variantes sorteadas para as casas (o teste exige que todas caibam na meta)
ArtBudget.HOUSE_VARIANTS = { "hut_thatch", "hut_veranda", "hut_thatch", "hut_kitchen", "house_tile" }

function ArtBudget.tris(key: string): number
	return ArtBudget.TRIS[key] or ArtBudget.DEFAULT
end

-- Touceiras ao longo de uma sebe de lenM metros: bambu a cada 7 m (touceira de ~7,7 m, contínua);
-- sebe de arrozal a cada 3 m (arbusto/capim de ~1,8 m).
function ArtBudget.hedgeClumps(lenM: number, tall: boolean): number
	return math.max(1, math.floor(lenM / (if tall then 7 else 3)))
end

-- Fração da vegetação de sebe que cabe no que sobrou do teto do setor (1 = toda, 0 = nenhuma).
function ArtBudget.factor(used: number, demand: number, cap: number?): number
	if demand <= 0 then
		return 1
	end
	return math.clamp(((cap or ArtBudget.SECTOR_MAX) - used) / demand, 0, 1)
end

function ArtBudget.within(key: string): boolean
	local kind = ArtBudget.KIND[key]
	local tris = ArtBudget.TRIS[key]
	return kind ~= nil and tris ~= nil and tris <= ArtBudget.MAX[kind]
end

return ArtBudget
