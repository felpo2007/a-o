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
		hut_thatch = 91784099076626,
		hut_veranda = 108704894302101,
		hut_kitchen = 119583768283690,
		house_tile = 83099837864172,
		shrine = 110189814903587,
		well = 132977007908383,
		granary = 88437533572898,
		grave_mound = 127693041320018,
		bamboo_fence = 77189674420385,
		log_bridge = 105484640465096,
		tunnel_entrance = 74044607029430,
		trench_section = 123503081864935,
		spider_hole = 129845165905645,
		sandbags = 89770024840711,
		vc_bunker = 93291203743799,
		bamboo_clump = 122081516623030,
		coconut_palm = 102968030425425,
		banana = 100002712193200,
		shrub = 131409897086783,
		elephant_grass = 123073879703433,
		hill_tree = 121233640900450,
		rice_patch = 134482555063796, -- canteiro 2 x 1,45 m (só 3 canteiros perto das vilas, D-64)
		-- mata fechada (D-65)
		canopy_tree = 73770095205881, -- emergente de 24 m
		melaleuca_grove = 130702304212118, -- tràm, grupo de 5 troncos de 13 m
		taro_fern = 94455365060774, -- taioba e samambaia de 1,8 m
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
		water_buffalo = 92959897148651,
		chicken = 95559003974876,
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
}
