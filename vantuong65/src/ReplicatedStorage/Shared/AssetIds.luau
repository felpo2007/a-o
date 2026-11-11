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
		m14 = 88428577780253,
		type56 = 92378317190418,
		sks = 130539342920510,
		m60 = 91094226063538,
		rpd = 105834324536160,
		m1911 = 111652541303464,
		type54 = 118978127433037,
		m79 = 115075736344105,
		rpg2 = 86123225979315,
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
	},
	-- Equipamento: MODELOS (GLB) soldados à cabeça/tronco em runtime (Characters.dress)
	Accessories = {
		us_m1_helmet = 79958913450723,
		us_m1955_vest = 92851024413374,
		vc_pith_helmet = 92224071886927,
		vc_jungle_hat = 99421757488229,
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
