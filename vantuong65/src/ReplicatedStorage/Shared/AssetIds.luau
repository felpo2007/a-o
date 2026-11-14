--!strict
-- IDs de assets do Roblox gerados no ForgeGUI. 0 = ainda não publicado: o jogo usa o placeholder.
-- `tools/roblox_cloud.py upload-assets` sobe os arquivos de assets/upload_plan.json pelo Open Cloud
-- e reescreve os zeros abaixo. Origem: assets/forgegui/manifest.json, assets/clothing e ASSETS.csv.
return {
	Sounds = {
		-- música de fundo do menu (D-91): "Ancient Grounds underscore", APM Music, biblioteca licenciada
		-- pela Roblox (APMOfficial, grátis para experiências)
		music_menu = 9045929119,
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
		uh34d_loop = 0, -- ForgeGUI em outcome_unknown (não regerar); o UH-34D usa uh34d_rotor/uh34d_motor
		engine_tank = 86120587573251,
		engine_amtrac = 136841561608456,
		-- veículos em laço sem emenda, síntese própria (tools/sons_veiculos.py; 0 = sem som)
		uh34d_rotor = 81421007464402,
		uh34d_motor = 127235938186878,
		vento_cabine = 109349699010800,
		lagarta = 110839071218227,
		motor_jipe = 76157418267165,
		motor_caminhao = 83596451612531,
		gun_90 = 122293822682317,
		rr_106 = 111700184968285,
		mortar_launch = 107258939071090,
		explosion = 108327124183058,
		incoming = 76773493975605,
		naval_distant = 84327200976853,
		radio_squelch = 117911075807959,
		-- corpo a corpo (D-94; tools/faca/sons.py). 0 = usa um substituto (curativo, impacto na terra)
		faca_saque = 111901564575957,
		faca_corte = 101889458600810,
		faca_impacto = 103935391429233,
		baioneta_encaixe = 75358128019094,
	},
	-- Modelos publicados como "Model" (InsertService:LoadAsset no servidor)
	Models = {
		hut_thatch = 79009291000422,
		hut_veranda = 119745592595472,
		hut_kitchen = 124310927991967,
		house_tile = 93665757730652,
		shrine = 139998355051185,
		well = 91389243957728,
		granary = 109767359675365,
		grave_mound = 125612119974664,
		bamboo_fence = 118272877596797,
		log_bridge = 113813163572493,
		tunnel_entrance = 98656470342711,
		trench_section = 76350589057613,
		spider_hole = 127802021928282,
		sandbags = 81076281447670,
		vc_bunker = 124630957324366,
		bamboo_clump = 81521268867622,
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
		-- fuzis de precisão feitos no Blender (tools/blender/armas.py, 2026-11-12); 0 = arma provisória
		m70 = 94218979828986,
		mosin = 70519343236093,
		-- espingarda Winchester Model 12 Trench Gun (tools/blender/espingarda.py, 2026-11-13): nós
		-- Arma, Telha, Culatra, Gatilho e Cartucho; 0 = arma provisória
		win12 = 90884195431925,
		-- caixas de munição do suporte (tools/blender/caixa_municao.py, 2026-11-13): nó Caixa e
		-- Colisao_Caixa; 0 = o CaixaMunicaoService usa o ammo_crate ou a caixa em peças
		caixa_municao_us = 128489958854272,
		caixa_municao_vc = 70550239273438,
		uh34d = 104404673955740,
		m48a3 = 83880316083319,
		ontos = 116051447339407,
		lvtp5 = 73612719536592,
		mortar_81 = 102314699611785,
		mortar_82 = 134024579408686,
		-- animais da vila (Parte 11): estavam no manifest mas fora do plano de upload até o teste com
		-- a arte publicada (2026-11-10); sem eles o AnimalService não tinha o que mover.
		-- D-74: reduzidos para 5 mil e 3 mil triângulos (eram 14,5 e 16,7 mil) e republicados
		water_buffalo = 83644982452765,
		chicken = 108410985778270,
		-- arrozal em cartões (tools/make_rice.py, D-74): o cliente põe em volta da câmera (RiceField)
		rice_tile_hi = 120451731988908,
		rice_tile_lo = 137999556221661,
		-- animais em partes (corpo, pernas, cabeça) para o andar no cliente (tools/rig_animals.py, D-77)
		water_buffalo_rig = 115492603708245,
		chicken_rig = 103660036877609,
		-- animais com esqueleto e pele feitos no Blender (tools/animais/esqueleto.py, D-79)
		water_buffalo_skin = 109421966021264,
		chicken_skin = 89649386620898,
		-- facas e baionetas de 1965 feitas no Blender (tools/faca, D-94): nós "Faca" e "Bainha"
		faca_kabar = 82895615799153,
		faca_m6 = 81588565737736,
		faca_type56 = 105729096442492,
		faca_dao = 84372706569103,
		-- objetos modelados no Blender (tools/blender/novos.py; assets/blender/RELATORIO.md); 0 = o
		-- jogo continua com a versão em peças (MapLife, GrenadeArt)
		water_jar = 90887023595576,
		straw_stack = 133241341995925,
		grenade_m26 = 111219650212365,
		grenade_stick = 80416129198116,
		smoke_m18 = 123590847061332,
		ammo_crate = 133538432186624,
		rice_sack = 78539576024383,
		clay_lamp = 93656401875800,
		sandbag_wall = 106761576075393,
		conical_hat = 102164592744402,
		bamboo_clothesline = 135761829841967,
		-- bases dos dois lados (Blender, tools/blender/bases.py; layouts em Data/Bases). IDs copiados
		-- de assets/roblox_ids.json (2026-11-13: o upload gravou lá, mas as chaves não estavam aqui)
		us_armor_revetment = 75028209207549,
		us_bunker = 89844472988022,
		us_command_tent = 80260599396065,
		us_concertina = 76709126961863,
		us_conex = 99435720647314,
		us_flagpole = 89142696219339,
		us_fuel_drums = 86893324957411,
		us_gate = 110411401748956,
		us_generator = 75290084586956,
		us_helipad = 88865123083263,
		us_jerrycans = 119877644935117,
		us_mess_tent = 71335880718215,
		us_motor_pool = 74220289599453,
		us_range_bench = 101623419193215,
		us_range_berm = 76198734769874,
		us_range_sign = 98255694286865,
		us_range_target = 119850040899518,
		us_tent_gp_large = 125086359475647,
		us_tent_gp_medium = 112322580019645,
		us_watchtower = 94686415084010,
		us_water_trailer = 139583787308295,
		vc_car_shelter = 80899750738468,
		vc_hammock = 74493503211085,
		vc_hoang_cam_kitchen = 91798442275991,
		vc_lean_to = 104859488176925,
		vc_punji = 122582546326486,
		vc_range_rest = 117982367319162,
		vc_range_target = 125319538960803,
		vc_weapon_rack = 114071799935669,
		-- casas únicas da vila central, com interior (Blender, D-98); 0 = o mapa usa as casas atuais
		-- com variação de rotação, escala e anexos
		vila_casa_01 = 72684660796291,
		vila_casa_02 = 136089034449244,
		vila_casa_03 = 113751446463487,
		vila_casa_04 = 119710549816229,
		vila_casa_05 = 104160358918966,
		vila_casa_06 = 132424774897092,
		vila_casa_07 = 131443479826708,
		vila_casa_08 = 137464951033207,
		vila_casa_09 = 129525265817076,
		vila_casa_10 = 111410077996768,
		vila_casa_11 = 0,
		vila_casa_12 = 0,
		-- mãos de 1ª pessoa (tools/maos, D-99); 0 = mãos montadas com peças
		-- veículos na medida real feitos no Blender (assets/blender/RELATORIO.md); o código troca para
		-- estas chaves junto com a tabela VehicleDrive.ART nova. Carros: 0 = substituto em peças
		m48a3_v2 = 85708217037052,
		ontos_v2 = 140388448545182,
		lvtp5_v2 = 106956293397124,
		uh34d_v2 = 110115617078484,
		m151 = 105050207488338,
		m35 = 105676392589052,
		peugeot403 = 124703224666199,
		maos_us_1p = 115253980298678,
		maos_vc_1p = 138339736774045,
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
		-- skins de uniforme (Shared/Skins; tools/make_clothing_skins.py); 0 = cai no molde normal
		us_faded_shirt_v3 = 111316643679745,
		us_faded_pants_v3 = 97616181097331,
		us_tiger_shirt_v3 = 98702392122528,
		us_tiger_pants_v3 = 99148306008988,
		us_duck_shirt_v3 = 128390642890074,
		us_duck_pants_v3 = 125772966200340,
	},
	-- Equipamento: MODELOS (GLB) soldados à cabeça/tronco em runtime (Characters.dress)
	Accessories = {
		us_m1_helmet = 74793570804591,
		us_m1955_vest = 101251968560886,
		vc_pith_helmet = 140572292985058,
		vc_jungle_hat = 99413247149061,
		-- camuflagem de mato das skins (tools/ghillie.py): MeshParts "Ghillie_<parte do corpo>"
		ghillie = 113038502171788,
	},
	Images = {
		gamepass_usmc_1965 = 0,
		gamepass_vc_1965 = 0,
		gamepass_unit = 0,
		gamepass_supporter = 0,
		-- texturas da camuflagem de mato (TextureID das peças; tools/ghillie.py)
		ghillie_rice = 124012833307485,
		ghillie_jungle = 139263756734280,
		ghillie_bamboo = 74047548891682,
		-- caveira do abate (tools/make_caveira.py): ID do DECAL; o servidor resolve a imagem no início
		-- (Modules/ImagensUi, atributo "Img_caveira_abate"). Com 0, a caveira é desenhada com frames.
		caveira_abate = 131470182680103,
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
		dirt_floor_cor = 133674721891264,
		dirt_floor_normal = 81507668993389,
		dirt_floor_rugosidade = 129686912768261,
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
	-- Carta topográfica do mapa tático (tools/make_carta.py; 2048 px em 4 blocos de 1024: nw, ne, sw,
	-- se). IDs de DECAL do Open Cloud; a ImageLabel precisa do ID da IMAGEM (CartaImages). Com a
	-- imagem em 0 e o decal publicado, o servidor resolve a imagem no início (CartaService); com os
	-- dois em 0, o mapa tático usa o desenho simples de antes.
	Carta = {
		nw = 103550551496533,
		ne = 118375191387311,
		sw = 94288570292198,
		se = 73429230339166,
	},
	CartaImages = {
		nw = 0,
		ne = 0,
		sw = 0,
		se = 0,
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
		dirt_floor_cor = 76029631233105,
		dirt_floor_normal = 109768166470823,
		dirt_floor_rugosidade = 75775835318235,
	},
}
