--!strict
-- IDs de assets do Roblox gerados no ForgeGUI. 0 = ainda não publicado: o jogo usa o placeholder.
-- `tools/roblox_cloud.py upload-assets` sobe os arquivos de assets/upload_plan.json pelo Open Cloud
-- e reescreve os zeros abaixo. Origem: assets/forgegui/manifest.json, assets/clothing e ASSETS.csv.
return {
	Sounds = {
		shot_m14 = 0,
		shot_type56 = 0,
		shot_mid = 0, -- tiro a ~150 m (camada média)
		shot_distant = 0, -- tiro a ~500 m (camada longe)
		burst_m60 = 0,
		burst_rpd = 0,
		crack = 0, -- estalo supersônico
		step_paddy = 0,
		step_mud = 0,
		step_sand = 0,
		step_grass = 0,
		step_wood = 0,
		impact_water = 0,
		impact_earth = 0,
		impact_wood = 0,
		impact_thatch = 0,
		reload_m14 = 0,
		reload_type56 = 0,
		dry_click = 0,
		bandage = 0,
		ambience_paddy_morning = 0,
		ambience_village = 0,
		ambience_beach = 0,
		ambience_tunnel = 0,
		uh34d_loop = 0,
	},
	-- Modelos publicados como "Model" (InsertService:LoadAsset no servidor)
	Models = {
		hut_thatch = 0,
		hut_veranda = 0,
		hut_kitchen = 0,
		house_tile = 0,
		shrine = 0,
		well = 0,
		granary = 0,
		grave_mound = 0,
		bamboo_fence = 0,
		log_bridge = 0,
		tunnel_entrance = 0,
		trench_section = 0,
		spider_hole = 0,
		sandbags = 0,
		vc_bunker = 0,
		bamboo_clump = 0,
		coconut_palm = 0,
		banana = 0,
		shrub = 0,
		elephant_grass = 0,
		hill_tree = 0,
		rice_patch = 0, -- canteiro 2 x 1,45 m (reservado: denso demais para o arrozal inteiro)
		m14 = 0,
		type56 = 0,
		sks = 0,
		m60 = 0,
		rpd = 0,
		m1911 = 0,
		type54 = 0,
		m79 = 0,
		rpg2 = 0,
		uh34d = 0,
	},
	-- Roupas: IMAGENS dos moldes clássicos (aplicadas em Shirt.ShirtTemplate / Pants.PantsTemplate)
	Clothing = {
		us_shirt = 0,
		us_pants = 0,
		vc_khaki_shirt = 0,
		vc_khaki_pants = 0,
		vc_green_shirt = 0,
		vc_green_pants = 0,
	},
	-- Equipamento: MODELOS (GLB) soldados à cabeça/tronco em runtime (Characters.dress)
	Accessories = {
		us_m1_helmet = 0,
		us_m1955_vest = 0,
		vc_pith_helmet = 0,
		vc_jungle_hat = 0,
	},
	Images = {
		gamepass_usmc_1965 = 0,
		gamepass_vc_1965 = 0,
		gamepass_unit = 0,
		gamepass_supporter = 0,
	},
}
