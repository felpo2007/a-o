--!strict
-- IDs de assets do Roblox gerados no ForgeGUI. 0 = ainda não publicado: o jogo usa o placeholder.
-- `tools/roblox_cloud.py upload-assets` sobe os arquivos de assets/upload_plan.json pelo Open Cloud
-- e reescreve os zeros abaixo. Origem: assets/forgegui/manifest.json, assets/clothing e ASSETS.csv.
return {
	Sounds = {
		shot_m14 = 115514991960057,
		shot_type56 = 88541025090577,
		shot_mid = 128124799917228, -- tiro a ~150 m (camada média)
		shot_distant = 125633964725306, -- tiro a ~500 m (camada longe)
		burst_m60 = 91461028573420,
		burst_rpd = 124046979784290,
		crack = 82820665250248, -- estalo supersônico
		step_paddy = 96893114954894,
		step_mud = 77316529471870,
		step_sand = 79055865207717,
		step_grass = 122684965369495,
		step_wood = 101150632880752,
		impact_water = 133407527476206,
		impact_earth = 99807736016672,
		impact_wood = 136338673266128,
		impact_thatch = 73134560787629,
		reload_m14 = 137955051261456,
		reload_type56 = 120304340562053,
		dry_click = 127055820532189,
		bandage = 98203499734569,
		ambience_paddy_morning = 79123848469999,
		ambience_village = 102127943356580,
		ambience_beach = 87445401006028,
		ambience_tunnel = 102752417889249,
		uh34d_loop = 0,
		engine_tank = 86120587573251,
		engine_amtrac = 136841561608456,
		gun_90 = 122293822682317,
		rr_106 = 111700184968285,
		mortar_launch = 107258939071090,
		explosion = 108327124183058,
		incoming = 76773493975605,
		naval_distant = 84327200976853,
		radio_squelch = 117911075807959,
	},
	-- Modelos publicados como "Model" (InsertService:LoadAsset no servidor)
	Models = {
		hut_thatch = 123372127409887,
		hut_veranda = 92945315831272,
		hut_kitchen = 137424366497472,
		house_tile = 120593440110273,
		shrine = 70871952568587,
		well = 112064523509360,
		granary = 120173432796541,
		grave_mound = 127298435495212,
		bamboo_fence = 118272877596797,
		log_bridge = 126447968922363,
		tunnel_entrance = 139514064636040,
		trench_section = 76350589057613,
		spider_hole = 128957989425207,
		sandbags = 73930638417719,
		vc_bunker = 83599657179313,
		bamboo_clump = 110447738024754,
		coconut_palm = 103008299707252,
		banana = 84461382552866,
		shrub = 114005886274948,
		elephant_grass = 98482841074326,
		hill_tree = 117136388691741,
		rice_patch = 134482555063796, -- canteiro 2 x 1,45 m (só 3 canteiros perto das vilas, D-64)
		-- mata fechada (D-65)
		canopy_tree = 75652285495122, -- emergente de 24 m
		melaleuca_grove = 95774589766161, -- tràm, grupo de 5 troncos de 13 m
		taro_fern = 131679866372706, -- taioba e samambaia de 1,8 m
		vine_tree = 0, -- copa tomada de cipó: geração em outcome_unknown (não regerar); usa o substituto
		-- árvores prontas do Poly Haven (CC0), folha em cartão recortado (tools/prep_trees.py, D-67)
		ph_island_tree_01 = 129507217098430,
		ph_island_tree_02 = 94197688304927,
		ph_island_tree_03 = 94525275658839,
		ph_tree_small_02 = 86317806051129,
		m14 = 89317219190262,
		type56 = 130417403055419,
		sks = 97318124582467,
		m60 = 78397702456512,
		rpd = 97742986087778,
		m1911 = 72933851519050,
		type54 = 89276790728567,
		m79 = 115974893628870,
		rpg2 = 115951819927247,
		uh34d = 104404673955740,
		m48a3 = 83880316083319,
		ontos = 116051447339407,
		lvtp5 = 73612719536592,
		mortar_81 = 102314699611785,
		mortar_82 = 134024579408686,
		-- animais da vila (Parte 11): estavam no manifest mas fora do plano de upload até o teste com
		-- a arte publicada (2026-11-10); sem eles o AnimalService não tinha o que mover
		water_buffalo = 88948304033404,
		chicken = 121576862821828,
	},
	-- Roupas: IMAGENS dos moldes clássicos (aplicadas em Shirt.ShirtTemplate / Pants.PantsTemplate)
	Clothing = {
		us_shirt = 114148157332275,
		us_pants = 140064926407222,
		vc_khaki_shirt = 75221746633608,
		vc_khaki_pants = 77430835589563,
		vc_green_shirt = 82261531108188,
		vc_green_pants = 134078542980416,
		-- moldes v3 (tools/make_clothing_v3.py, D-70); 0 = cai no v2 acima
		us_shirt_v3 = 94642390838308,
		us_shirt_rolled_v3 = 126361357269017,
		us_pants_v3 = 91522016319564,
		vc_khaki_shirt_v3 = 137934326333552,
		vc_khaki_pants_v3 = 77338277185056,
		vc_green_shirt_v3 = 104958149803032,
		vc_green_pants_v3 = 136585753172189,
		vc_black_shirt_v3 = 87527564693316,
		vc_black_pants_v3 = 135154812229650,
	},
	-- Equipamento: MODELOS (GLB) soldados à cabeça/tronco em runtime (Characters.dress)
	Accessories = {
		us_m1_helmet = 74793570804591,
		us_m1955_vest = 101251968560886,
		vc_pith_helmet = 140572292985058,
		vc_jungle_hat = 99413247149061,
	},
	Images = {
		gamepass_usmc_1965 = 0,
		gamepass_vc_1965 = 0,
		gamepass_unit = 0,
		gamepass_supporter = 0,
	},
	-- Texturas do chão (D-66; Poly Haven, CC0): IDs de DECAL devolvidos pelo Open Cloud. O
	-- MaterialVariant precisa do ID da IMAGEM de cada decal: fica em GroundImages (resolvido no Studio).
	Ground = {
		forrest_ground_01_cor = 73410451748634,
		forrest_ground_01_normal = 75953669132422,
		forrest_ground_01_rugosidade = 133696072684495,
		leafy_grass_cor = 84262456504835,
		leafy_grass_normal = 122524698568074,
		leafy_grass_rugosidade = 107138023014777,
		brown_mud_leaves_01_cor = 84904337801864,
		brown_mud_leaves_01_normal = 138220549210340,
		brown_mud_leaves_01_rugosidade = 86185017846727,
		forest_ground_06_cor = 70592474113049,
		forest_ground_06_normal = 103100751913983,
		forest_ground_06_rugosidade = 80664182036978,
	},
	-- Céu de foto (D-69; Poly Haven kloofendal_48d_partly_cloudy_puresky, CC0; tools/fetch_sky.py):
	-- IDs de DECAL do Open Cloud; o Sky precisa do ID da IMAGEM (SkyImages, resolvido no Studio).
	Sky = {
		ft = 119511350491403,
		bk = 111158168134738,
		lf = 136525023485486,
		rt = 128382971413174,
		up = 140458538027287,
		dn = 79041152014310,
	},
	SkyImages = {
		ft = 0,
		bk = 0,
		lf = 0,
		rt = 0,
		up = 0,
		dn = 0,
	},
	GroundImages = {
		forrest_ground_01_cor = 83248274685054,
		forrest_ground_01_normal = 139783933313957,
		forrest_ground_01_rugosidade = 135131185669577,
		leafy_grass_cor = 125918048123863,
		leafy_grass_normal = 119938912212224,
		leafy_grass_rugosidade = 76644537789593,
		brown_mud_leaves_01_cor = 89006167378554,
		brown_mud_leaves_01_normal = 78270531709445,
		brown_mud_leaves_01_rugosidade = 90256973643298,
		forest_ground_06_cor = 74088955875898,
		forest_ground_06_normal = 80878862384855,
		forest_ground_06_rugosidade = 96554687561752,
	},
}
