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
-- Mapa de 1 x 1 km (2026-11-11): o plano inteiro cabe com folga (ver tools/ArtEstimate).
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
	-- árvores prontas do Poly Haven (D-67)
	ph_island_tree_01 = "veg",
	ph_island_tree_02 = "veg",
	ph_island_tree_03 = "veg",
	ph_tree_small_02 = "veg",
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
	-- arrozal em cartões (D-74): fora do teto do setor, o cliente põe só em volta da câmera
	rice_tile_hi = "veg",
	rice_tile_lo = "veg",
	-- animais em partes para o andar (D-77): só o cliente põe, no lugar do modelo do servidor
	water_buffalo_rig = "prop",
	chicken_rig = "prop",
	-- com esqueleto e pele (Blender, D-79)
	water_buffalo_skin = "prop",
	chicken_skin = "prop",
	-- objetos novos do Blender (assets/blender, 2026-11-11): vila e câmaras dos túneis (MapLife)
	water_jar = "prop",
	straw_stack = "prop",
	ammo_crate = "prop",
	rice_sack = "prop",
	sandbag_wall = "prop", -- muro de sacos (o ponto de combustível da base dos EUA)
	conical_hat = "prop",
	bamboo_clothesline = "prop",
	-- caixas de munição do suporte (tools/blender/caixa_municao.py, 2026-11-13)
	caixa_municao_us = "prop",
	caixa_municao_vc = "prop",
	-- bases dos dois lados (Blender, 2026-11-13; Data/Bases): assets/blender/<chave>/metricas.json
	us_tent_gp_medium = "prop",
	us_tent_gp_large = "prop",
	us_command_tent = "prop",
	us_mess_tent = "prop",
	us_motor_pool = "prop",
	us_bunker = "prop",
	us_watchtower = "prop",
	us_gate = "prop",
	us_flagpole = "prop",
	us_concertina = "prop",
	us_helipad = "prop",
	us_armor_revetment = "prop",
	us_range_bench = "prop",
	us_range_berm = "prop",
	us_range_sign = "prop",
	us_range_target = "prop",
	us_fuel_drums = "prop",
	us_water_trailer = "prop",
	us_generator = "prop",
	us_conex = "prop",
	us_jerrycans = "prop",
	vc_lean_to = "prop",
	vc_hoang_cam_kitchen = "prop",
	vc_car_shelter = "prop",
	vc_hammock = "prop",
	vc_weapon_rack = "prop",
	vc_range_target = "prop",
	vc_range_rest = "prop",
	vc_punji = "prop",
	-- casas únicas da vila Xóm Gò (Blender, 2026-11-13; 11 e 12 ainda sem modelo)
	vila_casa_01 = "prop",
	vila_casa_02 = "prop",
	vila_casa_03 = "prop",
	vila_casa_04 = "prop",
	vila_casa_05 = "prop",
	vila_casa_06 = "prop",
	vila_casa_07 = "prop",
	vila_casa_08 = "prop",
	vila_casa_09 = "prop",
	vila_casa_10 = "prop",
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
	-- veículos refeitos no Blender na medida real, em peças (lote dos _v2, 2026-11-12); as chaves
	-- antigas continuam com os modelos do ForgeGUI
	m48a3_v2 = "hero",
	ontos_v2 = "hero",
	lvtp5_v2 = "hero",
	uh34d_v2 = "hero",
	m151 = "hero",
	m35 = "hero",
	peugeot403 = "hero",
} :: { [string]: string }

-- triângulos medidos (manifest.json, campo "triangulos"): remesh do ForgeGUI ou, quando ele terminou
-- em outcome_unknown, redução local (tools/decimate_glb.py)
ArtBudget.TRIS = {
	-- vegetação na malha cheia do gerador (D-66; antes, remesh de 1,9–2,8 mil). bamboo_clump: o GLB
	-- do gerador sem o disco marrom da base (Blender, 2026-11-12; o ID antigo ficou como
	-- bamboo_clump_disco): 11.428 (eram 11.456)
	bamboo_clump = 11428,
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
	-- árvores prontas (tools/prep_trees.py, D-67): madeira reduzida + folha em cartão (2 por folha)
	ph_island_tree_01 = 13599,
	ph_island_tree_02 = 12599,
	ph_island_tree_03 = 12554,
	ph_tree_small_02 = 13736,
	-- props refeitos no Blender (assets/blender/<chave>/metricas.json, "novo"; publicados em
	-- 2026-11-11, commit 6ea6bfd): a mesma forma com ~1/3 dos triângulos. Antes, a malha cheia do
	-- gerador (D-66): 13.030, 13.249, 13.483, 14.938, 14.106, 13.615, 13.489, 14.278, 13.576,
	-- 11.287, 17.067, 9.602 e 15.388.
	hut_thatch = 4399,
	hut_veranda = 3200,
	hut_kitchen = 5999,
	house_tile = 4399,
	granary = 6000,
	well = 4999,
	shrine = 2750,
	grave_mound = 2749,
	tunnel_entrance = 3750,
	vc_bunker = 4400,
	sandbags = 5000,
	spider_hole = 4999,
	log_bridge = 4399,
	-- ficaram os do gerador (o Blender perdeu na comparação, RELATORIO.md)
	trench_section = 12072,
	bamboo_fence = 16418,
	-- objetos novos do Blender (metricas.json)
	water_jar = 2000,
	straw_stack = 5000,
	ammo_crate = 2000,
	rice_sack = 1500,
	sandbag_wall = 7999,
	conical_hat = 825,
	bamboo_clothesline = 2749,
	caixa_municao_us = 4800,
	caixa_municao_vc = 3600,
	-- bases dos dois lados (metricas.json, "novo"; tools/bases_dados.py imprime a lista)
	us_armor_revetment = 3539,
	us_bunker = 1744,
	us_command_tent = 8212,
	us_concertina = 7296,
	us_conex = 1000,
	us_flagpole = 4720,
	us_fuel_drums = 3750,
	us_gate = 3142,
	us_generator = 1212,
	us_helipad = 4752,
	us_jerrycans = 1440,
	us_mess_tent = 8408,
	us_motor_pool = 9352,
	us_range_bench = 1200,
	us_range_berm = 1600,
	us_range_sign = 352,
	us_range_target = 284,
	us_tent_gp_large = 10178,
	us_tent_gp_medium = 8024,
	us_watchtower = 4497,
	us_water_trailer = 2000,
	vc_car_shelter = 6999,
	vc_hammock = 2780,
	vc_hoang_cam_kitchen = 5499,
	vc_lean_to = 4500,
	vc_punji = 2188,
	vc_range_rest = 600,
	vc_range_target = 1500,
	vc_weapon_rack = 1500,
	vila_casa_01 = 8201,
	vila_casa_02 = 7818,
	vila_casa_03 = 7328,
	vila_casa_04 = 7084,
	vila_casa_05 = 6853,
	vila_casa_06 = 8548,
	vila_casa_07 = 7819,
	vila_casa_08 = 7856,
	vila_casa_09 = 7561,
	vila_casa_10 = 7788,
	us_m1_helmet = 3000,
	us_m1955_vest = 3999,
	vc_pith_helmet = 2999,
	vc_jungle_hat = 2447,
	-- D-74: redução local (tools/decimate_glb.py) para pôr manadas e mais galinhas
	water_buffalo = 4999,
	chicken = 3000,
	-- ladrilho de 4,5 x 4,5 m (tools/make_rice.py): perto 96 cartões, longe 24 (2 faces cada)
	rice_tile_hi = 384,
	rice_tile_lo = 96,
	-- os mesmos triângulos do modelo reduzido, divididos em partes (tools/rig_animals.py)
	water_buffalo_rig = 4999,
	chicken_rig = 3000,
	water_buffalo_skin = 4999,
	chicken_skin = 3000,
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
	-- assets/blender/<chave>/metricas.json ("novo", instâncias de roda e pá contadas)
	m48a3_v2 = 14358,
	ontos_v2 = 9938,
	lvtp5_v2 = 14009,
	uh34d_v2 = 4742,
	m151 = 3338,
	m35 = 8000,
	peugeot403 = 4639,
} :: { [string]: number }

-- Acima da meta, com o motivo. O teste falha se um modelo passar da meta sem estar aqui, ou se
-- uma exceção ficar velha (o modelo já cabe na meta).
ArtBudget.EXCEPTIONS = {} :: { [string]: string }
-- abaixo do mínimo de 8 mil (D-66), com o motivo
-- (o mínimo vale para a vegetação; os props refeitos no Blender ficam abaixo de 8 mil de propósito)
ArtBudget.BELOW_MIN = {
	elephant_grass = "a malha cheia do gerador tem 7.978; não há versão maior",
	rice_tile_hi = "ladrilho de cartões: ~1.200 em volta da câmera (D-74)",
	rice_tile_lo = "ladrilho de cartões: ~1.200 em volta da câmera (D-74)",
} :: { [string]: string }

-- variantes sorteadas para as casas (o teste exige que todas caibam na meta)
ArtBudget.HOUSE_VARIANTS = { "hut_thatch", "hut_veranda", "hut_thatch", "hut_kitchen", "house_tile" }

function ArtBudget.tris(key: string): number
	return ArtBudget.TRIS[key] or ArtBudget.DEFAULT
end

-- Caixa de cada modelo na escala 1 (studs X, Y, Z), medida no GLB preparado: manifest do ForgeGUI
-- (dim_studs_xyz) e metricas.json do Blender (novo). O plano da arte (ArtPlan) usa para a pegada:
-- assentar no chão, abrir o patamar no terreno e não pôr uma coisa dentro da outra, antes de o
-- modelo carregar. O teste da F5 confere com os arquivos.
ArtBudget.DIMS = {
	hut_thatch = { 20.49, 18.55, 24.98 },
	hut_veranda = { 28.58, 21.92, 28.49 },
	hut_kitchen = { 14.27, 11.92, 12.59 },
	house_tile = { 21.86, 17.72, 24.83 },
	granary = { 11.11, 12.56, 10.41 },
	well = { 5.36, 4.26, 5.36 },
	shrine = { 4.31, 6.07, 3.98 },
	grave_mound = { 8.75, 3.91, 6.62 },
	vc_bunker = { 14.48, 4.35, 12.8 },
	sandbags = { 1.66, 2.4, 7.11 },
	bamboo_fence = { 1.19, 6.51, 10.72 },
	spider_hole = { 3.18, 2.31, 3.18 },
	tunnel_entrance = { 3.58, 3.56, 3.56 },
	trench_section = { 14.2, 3.99, 7.02 },
	log_bridge = { 21.24, 5.47, 3.22 },
	rice_patch = { 7.14, 1.59, 5.17 },
	water_jar = { 2.72, 2.83, 2.14 },
	straw_stack = { 7.33, 10.14, 7.28 },
	ammo_crate = { 2.25, 1.17, 1.22 },
	rice_sack = { 1.69, 0.7, 1.27 },
	sandbag_wall = { 7.4, 5.3, 2.28 },
	conical_hat = { 1.45, 0.68, 1.45 },
	bamboo_clothesline = { 11.58, 7.18, 2.68 },
	caixa_municao_us = { 2.66, 1.93, 1.62 },
	caixa_municao_vc = { 2.52, 1.53, 1.64 },
	-- bases dos dois lados (metricas.json "dim_studs_xyz"; com cordas e estais das barracas)
	us_armor_revetment = { 47.14, 5.67, 52.77 },
	us_bunker = { 14.07, 9.84, 18.71 },
	us_command_tent = { 44.92, 39.84, 55.03 },
	us_concertina = { 27.19, 6.11, 6.54 },
	us_conex = { 6.85, 7.79, 9.61 },
	us_flagpole = { 21.0, 32.76, 5.53 },
	us_fuel_drums = { 9.63, 5.56, 5.56 },
	us_gate = { 41.93, 10.22, 10.01 },
	us_generator = { 2.5, 2.63, 5.2 },
	us_helipad = { 52.24, 0.14, 52.26 },
	us_jerrycans = { 3.78, 1.61, 3.43 },
	us_mess_tent = { 31.05, 15.84, 68.05 },
	us_motor_pool = { 45.08, 18.72, 45.0 },
	us_range_bench = { 4.29, 3.35, 4.04 },
	us_range_berm = { 57.17, 10.94, 25.75 },
	us_range_sign = { 2.21, 4.93, 0.27 },
	us_range_target = { 2.0, 6.25, 0.19 },
	us_tent_gp_large = { 31.05, 16.92, 68.05 },
	us_tent_gp_medium = { 28.87, 13.42, 47.01 },
	us_watchtower = { 10.36, 26.55, 13.92 },
	us_water_trailer = { 7.23, 7.0, 14.35 },
	vc_car_shelter = { 15.4, 14.79, 23.78 },
	vc_hammock = { 12.0, 6.97, 11.51 },
	vc_hoang_cam_kitchen = { 17.14, 10.86, 47.59 },
	vc_lean_to = { 16.73, 11.25, 10.27 },
	vc_punji = { 7.5, 1.55, 3.93 },
	vc_range_rest = { 12.14, 2.86, 0.32 },
	vc_range_target = { 2.43, 6.36, 0.96 },
	vc_weapon_rack = { 8.21, 4.43, 2.9 },
	vila_casa_01 = { 27.53, 16.86, 29.68 },
	vila_casa_02 = { 28.17, 17.23, 27.05 },
	vila_casa_03 = { 29.72, 17.45, 23.78 },
	vila_casa_04 = { 25.66, 16.65, 28.84 },
	vila_casa_05 = { 20.2, 15.86, 29.29 },
	vila_casa_06 = { 30.04, 17.98, 24.21 },
	vila_casa_07 = { 27.2, 17.55, 23.61 },
	vila_casa_08 = { 29.58, 16.97, 29.7 },
	vila_casa_09 = { 26.16, 18.7, 29.91 },
	vila_casa_10 = { 29.71, 15.61, 29.81 },
} :: { [string]: { number } }

-- Raio do pé de cada planta no chão (studs, escala 1): o tronco das árvores, a touceira do bambu e o
-- tufo do arbusto e do capim. É o que não pode cair na lâmina d'água, no dique, na estrada, no leito
-- do riacho nem dentro de construção. Estimado pela caixa (dim_studs_xyz) e pelas prévias: a copa é
-- bem mais larga que o pé.
ArtBudget.BASE_R = {
	ph_island_tree_01 = 0.8,
	ph_island_tree_02 = 0.8,
	ph_island_tree_03 = 0.7,
	ph_tree_small_02 = 0.5,
	hill_tree = 1.8,
	canopy_tree = 2,
	vine_tree = 1.8,
	coconut_palm = 1.2,
	banana = 1.4,
	bamboo_clump = 4,
	melaleuca_grove = 5,
	shrub = 2.2,
	elephant_grass = 2,
	taro_fern = 2.2,
	rice_patch = 1.5,
} :: { [string]: number }

-- Pé enterrado além do PLANT_SINK_M do plano (fração da altura do modelo, studs na escala 1), para
-- modelo com base de terra à mostra. Vazio desde 2026-11-13: o bamboo_clump (o único, 8% da altura)
-- foi republicado sem o disco marrom.
ArtBudget.BASE_SINK = {} :: { [string]: { frac: number, height: number } }

-- Casas da vila grande (2026-11-12, Data/Village): modelos únicos do Blender, com interior e porta de
-- pelo menos 2,1 m (7,5 studs) para o soldado de 2,0 m. Com o ID em 0, a vila usa as casas de hoje
-- variando giro, escala, cor e anexos.
ArtBudget.VILLAGE_HOUSES = {
	"vila_casa_01",
	"vila_casa_02",
	"vila_casa_03",
	"vila_casa_04",
	"vila_casa_05",
	"vila_casa_06",
	"vila_casa_07",
	"vila_casa_08",
	"vila_casa_09",
	"vila_casa_10",
	"vila_casa_11",
	"vila_casa_12",
}

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
