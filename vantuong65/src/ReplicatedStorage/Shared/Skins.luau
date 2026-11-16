--!strict
-- Skins (pedido do dono, 2026-11-11): acabamento de arma, uniforme e camuflagem de mato (ghillie).
-- Catálogo e regras PUROS (testados no Lune: tests/luau/skins.luau). As funções que mexem em
-- Instance (applyWeapon) e o balanço das folhas (swayAngles, usado pelo cliente) não rodam no teste.
--
-- Compra (decisão do dono): com o dinheiro do jogo ($, Shared/Progression) ou com Robux. Em $ é
-- MUITO caro (dezenas de partidas por skin; a camuflagem é a mais cara); em Robux é barato e na
-- mesma proporção entre os itens. Robux:
--   - arma: Developer Product, um por skin. O recibo grava a posse no perfil (ProcessReceipt
--     idempotente no CommerceService); a posse fica para sempre;
--   - uniforme e camuflagem: Game Pass (posse pelo UserOwnsGamePassAsync, CommerceService).
-- IDs em Skins.IDS: 0 = item ainda não criado no Roblox (o botão de Robux some). O dono cria no
-- Creator Dashboard e cola o número aqui. O preço real em Robux vem do GetProductInfoAsync (Managed
-- Pricing, MONETIZATION.md); `robux` é só a sugestão para criar o item.
--
-- Vantagem: SÓ a camuflagem de mato, e só contra os bots. O personagem ganha o atributo "Camo"
-- (tipo da vegetação) e o BotBrain.camoFactor encurta a distância em que os bots o enxergam quando
-- ele está na vegetação do mesmo tipo. "Vantagem comprada" autorizada pelo dono em 2026-11-11.
-- Arma e uniforme são só visuais.
--
-- No perfil (ProfileSchema.skins): `owned` (comprados com $ ou por Developer Product) e `on`
-- (equipado por lado e por encaixe: id da arma, "uniform" ou "camo").
local Progression = require(script and (script :: any).Parent.Progression or "./Progression") :: any
-- D-178: a textura de cada acabamento (gerada por tools/acabamentos.py: skinId -> id da imagem)
local AcabamentosArte = require(script and (script :: any).Parent.AcabamentosArte or "./AcabamentosArte") :: any

local Skins = {}

-- ===== preço =====
-- Ganho por partida (Shared/Progression; números de design, nenhum medido em partida real):
--   - Warfare de 75 min (Capture.C.warfareMinutes); jogador médio vivo ~2/3 do tempo:
--     tempo em campo 2 $/min x ~50 min = ~100 $;
--   - abates (10), assistências (5), defesa (3 a cada 30 s) e cuidados: ~2 $/min = ~100-150 $
--     (o teto anti-farm é 60 $/min, Progression.CAP);
--   - fim de partida: vitória 60, derrota 25 (média ~40).
--   => ~300 $ por partida. PLACEHOLDER até a telemetria do pós-ação.
-- Uma skin de arma custa 25 a 35 partidas (~31 a 44 h de Warfare); o uniforme, 50; a camuflagem,
-- 100 (é a que dá vantagem). Em Robux, ~1,6 R$ por partida equivalente em todos os níveis. PLACEHOLDER.
Skins.MONEY_PER_MATCH = 300 -- PLACEHOLDER
export type Tier = { matches: number, robux: number }
Skins.TIERS = {
	weapon = { matches = 25, robux = 39 }, -- madeira e aço gasto
	weapon_plus = { matches = 35, robux = 55 }, -- trabalho a mais: fita, oxidação nova, pintura
	uniform = { matches = 50, robux = 79 },
	camo = { matches = 100, robux = 159 },
} :: { [string]: Tier }

function Skins.tierPrice(tier: string): number
	local t = Skins.TIERS[tier]
	return if t then t.matches * Skins.MONEY_PER_MATCH else 0
end

-- ===== Robux: IDs (0 = desligado) =====
-- PRODUCT_* = Developer Product (arma); PASS_* = Game Pass (uniforme e camuflagem).
Skins.IDS = {
	-- armas EUA
	PRODUCT_SKIN_M14_BIRCH = 3730455811,
	PRODUCT_SKIN_M14_TAPE = 3730455823,
	PRODUCT_SKIN_M14_WORN = 3730455835,
	PRODUCT_SKIN_M60_OD = 3730455845,
	PRODUCT_SKIN_M60_WORN = 3730455853,
	PRODUCT_SKIN_M79_WALNUT = 3730455863,
	PRODUCT_SKIN_M79_OD = 3730455879,
	PRODUCT_SKIN_M1911_BLUED = 3730455892,
	-- armas VC
	PRODUCT_SKIN_TYPE56_BIRCH = 3730455912,
	PRODUCT_SKIN_TYPE56_BLUED = 3730455924,
	PRODUCT_SKIN_TYPE56_TAPE = 3730455936,
	PRODUCT_SKIN_SKS_WALNUT = 3730455947,
	PRODUCT_SKIN_SKS_WORN = 3730455956,
	PRODUCT_SKIN_RPD_BIRCH = 3730455967,
	PRODUCT_SKIN_RPD_WORN = 3730455978,
	PRODUCT_SKIN_TYPE54_WORN = 3730455995,
	PRODUCT_SKIN_RPG2_OD = 3730456007,
	-- uniformes
	PASS_SKIN_US_FADED = 2079194499,
	PASS_SKIN_US_TIGER = 2079944452,
	PASS_SKIN_US_DUCK = 2078516472,
	PASS_SKIN_VC_BLACK = 2078786461,
	-- D-131 (lote 17): Game Passes criados no lote 49 (D-164), R$ 79 como os outros uniformes
	PASS_SKIN_US_TADPOLE = 2088220472,
	PASS_SKIN_US_LIZARD = 2088598458,
	PASS_SKIN_VC_BROWN = 2089978461,
	PASS_SKIN_VC_TIGER = 2089438416,
	-- camuflagem de mato
	PASS_CAMO_RICE = 2078852467,
	PASS_CAMO_JUNGLE = 2078126473,
	PASS_CAMO_BAMBOO = 2078756470,
} :: { [string]: number }

-- ===== acabamentos de arma =====
-- Cor por classe de peça. As cores são de olho (PLACEHOLDER: conferir em foto de arma de época).
-- O padrão é o da arma provisória (Shared/GunModel): nogueira média e aço fosfatizado escuro.
Skins.DEFAULT = {
	wood = { 96, 66, 42 },
	handguard = { 96, 66, 42 },
	metal = { 44, 45, 47 },
} :: { [string]: { number } }
local BIRCH = { 170, 128, 80 } -- bétula envernizada: clara e amarelada
local WALNUT = { 66, 42, 28 } -- nogueira escura, oleada
local BLUED = { 30, 34, 46 } -- oxidação azul: preto-azulado
local WORN = { 112, 112, 108 } -- aço gasto: o fosfato saiu e o metal claro aparece
local OD = { 76, 80, 50 } -- verde-oliva pintado (tinta de campo)
local TAPE = { 96, 98, 70 } -- fita de pano verde-oliva enrolada no guarda-mão

export type Finish = {
	wood: { number }?,
	metal: { number }?,
	handguard: { number }?,
	handguardMat: string?, -- material do guarda-mão (só na arma provisória, feita de Part)
}

-- Classe de cada peça pelo nome (sem os números do fim: "Madeira0_0" -> "Madeira").
--   Arte nova (armas refeitas no Blender, com máscara): MeshPart "Madeira", "GuardaMao" e "Metal",
--   cada uma com SurfaceAppearance em AlphaMode TintMask (o alfa do mapa de cor diz onde a cor tinge).
--   Arma provisória (Shared/GunModel): Part com os nomes em inglês abaixo.
Skins.PART_CLASS = {
	Madeira = "wood",
	Coronha = "wood",
	Cabo = "wood",
	GuardaMao = "handguard",
	Metal = "metal",
	Cano = "metal",
	Ferragem = "metal",
	Stock = "wood",
	Grip = "wood",
	Handguard = "handguard",
	Receiver = "metal",
	Barrel = "metal",
	Slide = "metal",
	Magazine = "metal",
	FrontSight = "metal",
	RearSight = "metal",
} :: { [string]: string }

function Skins.partClass(name: string): string?
	local base = string.match(name, "^(%a+)")
	return if base then Skins.PART_CLASS[base] else nil
end

-- ===== catálogo =====
export type Skin = {
	id: string,
	kind: string, -- "weapon" | "uniform" | "camo"
	side: string, -- "US" | "VC" | "both"
	weapon: string?, -- arma (Shared/Weapons) da skin de arma
	name: string,
	desc: string,
	tier: string, -- Skins.TIERS
	price: number, -- em $ (dinheiro do jogo)
	robux: number, -- sugestão em Robux (o preço real é lido ao vivo)
	robuxKey: string, -- chave em Skins.IDS
	robuxKind: string, -- "product" | "pass"
	check: string, -- conferência histórica pendente ("foto", "foto + consultor"...)
	swatch: { { number } }, -- cores da prévia
	finish: Finish?, -- arma
	gearUniform: string?, -- uniforme: variante que o Gear já sabe vestir (ex.: "vc_black")
	shirt: string?, -- uniforme: molde novo (chave em AssetIds.Clothing)
	pants: string?,
	rgb: { shirt: { number }, pants: { number } }?, -- uniforme: cor do corpo sem molde publicado
	pattern: string?, -- uniforme: desenho da prévia ("tiger" | "tadpole" | "lizard" | "duck" | "plain")
	camo: string?, -- camuflagem: "rice" | "jungle" | "bamboo" (atributo "Camo", BotBrain)
	texture: string?, -- camuflagem: chave da textura em AssetIds.Images
	soPasse: boolean?, -- D-176: só pelo conjunto em Game Pass (robuxKey); não se compra com $
	soCaixa: boolean?, -- D-178: só nas caixas e na troca de Fragmentos (robuxKey "CAIXA")
	arte: any?, -- D-178: { receita, cores, alvo } da textura gerada (tools/acabamentos.py)
	universal: boolean?, -- D-179: acabamento que vale em qualquer arma de Skins.ARMAS_UNIVERSAL
	vitrine: string?, -- D-179: arma que mostra o universal nas imagens (caixas, ARQUIVO)
}

local function base(id: string, kind: string, side: string, tier: string, key: string, name: string, desc: string): Skin
	local t = Skins.TIERS[tier]
	return {
		id = id,
		kind = kind,
		side = side,
		name = name,
		desc = desc,
		tier = tier,
		price = Skins.tierPrice(tier),
		robux = t.robux,
		robuxKey = key,
		robuxKind = if string.sub(key, 1, 5) == "PASS_" then "pass" else "product",
		check = "foto",
		swatch = {},
	}
end

-- D-176: item de conjunto em Game Pass (só pelo passe: fora do $ da Intendência e do Mercado)
local function soPasse(s: Skin): Skin
	s.soPasse = true
	return s
end

local function weapon(
	id: string,
	weaponId: string,
	side: string,
	tier: string,
	key: string,
	name: string,
	desc: string,
	finish: Finish
): Skin
	local s = base(id, "weapon", side, tier, key, name, desc)
	s.weapon = weaponId
	s.finish = finish
	local sw = {}
	for _, c in { finish.wood, finish.handguard, finish.metal } do
		if c then
			table.insert(sw, c)
		end
	end
	s.swatch = sw
	return s
end

-- Fidelidade (agosto de 1965), conferir em foto antes do asset final (`check`):
-- - M14: coronha de nogueira ou de bétula (as duas madeiras saíram de fábrica antes da de fibra de
--   vidro); fita no guarda-mão contra barulho e brilho; o fosfato gasta nas arestas no uso.
-- - M60 e M79: peças pintadas de verde-oliva em campo; o M79 tinha coronha de nogueira.
-- - M1911A1: armas comerciais de oxidação azul com talas de nogueira chegavam por compra própria.
-- - Tipo 56 (AK chinês), SKS chinês, RPD e Tipo 54: aço oxidado (azulado) que gasta e clareia;
--   madeiras claras e escuras de várias fábricas; fita de pano no guarda-mão.
-- - RPG-2: tubo pintado.
Skins.CATALOG = {
	-- ===== armas EUA =====
	weapon(
		"skin_m14_birch",
		"m14",
		"US",
		"weapon",
		"PRODUCT_SKIN_M14_BIRCH",
		"M14 · coronha de bétula",
		"Coronha e guarda-mão de bétula clara, envernizada de fábrica.",
		{ wood = BIRCH }
	),
	weapon(
		"skin_m14_tape",
		"m14",
		"US",
		"weapon_plus",
		"PRODUCT_SKIN_M14_TAPE",
		"M14 · fita no guarda-mão",
		"Guarda-mão enrolado em fita de pano verde-oliva: sem brilho e sem barulho na mata.",
		{ handguard = TAPE, handguardMat = "Fabric" }
	),
	weapon(
		"skin_m14_worn",
		"m14",
		"US",
		"weapon",
		"PRODUCT_SKIN_M14_WORN",
		"M14 · aço gasto",
		"Fosfato gasto nas arestas: o metal claro aparece depois de meses de campo.",
		{ metal = WORN }
	),
	weapon(
		"skin_m60_od",
		"m60",
		"US",
		"weapon_plus",
		"PRODUCT_SKIN_M60_OD",
		"M60 · verde-oliva pintado",
		"Coronha, guarda-mão e caixa pintados de verde-oliva com tinta de campo.",
		{ wood = OD, handguard = OD, metal = OD }
	),
	weapon(
		"skin_m60_worn",
		"m60",
		"US",
		"weapon",
		"PRODUCT_SKIN_M60_WORN",
		"M60 · aço gasto",
		"Caixa e cano com o fosfato gasto pelo uso.",
		{ metal = WORN }
	),
	weapon(
		"skin_m79_walnut",
		"m79",
		"US",
		"weapon",
		"PRODUCT_SKIN_M79_WALNUT",
		"M79 · nogueira escura",
		"Coronha de nogueira escura, oleada.",
		{ wood = WALNUT }
	),
	weapon(
		"skin_m79_od",
		"m79",
		"US",
		"weapon_plus",
		"PRODUCT_SKIN_M79_OD",
		"M79 · verde-oliva pintado",
		"Lançador e coronha pintados de verde-oliva em campo.",
		{ wood = OD, handguard = OD, metal = OD }
	),
	weapon(
		"skin_m1911_blued",
		"m1911",
		"US",
		"weapon_plus",
		"PRODUCT_SKIN_M1911_BLUED",
		"M1911A1 · aço azulado e nogueira",
		"Pistola comercial de oxidação azul com talas de nogueira, trazida por conta própria.",
		{ metal = BLUED, wood = WALNUT }
	),
	-- ===== armas VC =====
	weapon(
		"skin_type56_birch",
		"type56",
		"VC",
		"weapon",
		"PRODUCT_SKIN_TYPE56_BIRCH",
		"Tipo 56 · madeira clara",
		"Coronha e guarda-mão de madeira clara (bétula), envernizada.",
		{ wood = BIRCH }
	),
	weapon(
		"skin_type56_blued",
		"type56",
		"VC",
		"weapon_plus",
		"PRODUCT_SKIN_TYPE56_BLUED",
		"Tipo 56 · aço azulado novo",
		"Oxidação azul ainda inteira, de arma recém-chegada pela trilha.",
		{ metal = BLUED }
	),
	weapon(
		"skin_type56_tape",
		"type56",
		"VC",
		"weapon_plus",
		"PRODUCT_SKIN_TYPE56_TAPE",
		"Tipo 56 · fita no guarda-mão",
		"Guarda-mão enrolado em tira de pano verde.",
		{ handguard = TAPE, handguardMat = "Fabric" }
	),
	weapon(
		"skin_sks_walnut",
		"sks",
		"VC",
		"weapon",
		"PRODUCT_SKIN_SKS_WALNUT",
		"SKS · madeira escura",
		"Coronha inteiriça de madeira escura (nogueira), oleada.",
		{ wood = WALNUT }
	),
	weapon(
		"skin_sks_worn",
		"sks",
		"VC",
		"weapon",
		"PRODUCT_SKIN_SKS_WORN",
		"SKS · aço gasto",
		"Oxidação gasta pelo uso: o metal claro aparece.",
		{ metal = WORN }
	),
	weapon(
		"skin_rpd_birch",
		"rpd",
		"VC",
		"weapon",
		"PRODUCT_SKIN_RPD_BIRCH",
		"RPD · madeira clara",
		"Coronha e guarda-mão de madeira clara (bétula).",
		{ wood = BIRCH }
	),
	weapon(
		"skin_rpd_worn",
		"rpd",
		"VC",
		"weapon",
		"PRODUCT_SKIN_RPD_WORN",
		"RPD · aço gasto",
		"Caixa e cano com a oxidação gasta.",
		{ metal = WORN }
	),
	weapon(
		"skin_type54_worn",
		"type54",
		"VC",
		"weapon",
		"PRODUCT_SKIN_TYPE54_WORN",
		"Tipo 54 · aço gasto",
		"Ferrolho e armação com a oxidação gasta pelo coldre.",
		{ metal = WORN }
	),
	weapon(
		"skin_rpg2_od",
		"rpg2",
		"VC",
		"weapon_plus",
		"PRODUCT_SKIN_RPG2_OD",
		"RPG-2 · verde-oliva pintado",
		"Tubo e protetor de madeira pintados de verde.",
		{ wood = OD, handguard = OD, metal = OD }
	),
	-- ===== D-176: conjunto "Personalização de Armas" (Game Pass PASS_SET_ARMAS; só pelo passe) =====
	soPasse(
		weapon(
			"skin_m14_oleada",
			"m14",
			"US",
			"weapon_plus",
			"PASS_SET_ARMAS",
			"M14 · nogueira oleada",
			"Coronha e guarda-mão de nogueira escurecida por anos de óleo de linhaça.",
			{ wood = { 58, 36, 22 }, handguard = { 58, 36, 22 } }
		)
	),
	soPasse(
		weapon(
			"skin_m60_fosfato",
			"m60",
			"US",
			"weapon_plus",
			"PASS_SET_ARMAS",
			"M60 · fosfato novo",
			"Caixa e cano com o fosfato cinza-esverdeado de arma recém-saída do depósito.",
			{ metal = { 58, 62, 56 } }
		)
	),
	soPasse(
		weapon(
			"skin_m1911_marrom",
			"m1911",
			"US",
			"weapon_plus",
			"PASS_SET_ARMAS",
			"M1911A1 · talas de plástico marrom",
			"As talas de plástico marrom do modelo de serviço, com o aço fosfatizado.",
			{ wood = { 92, 56, 36 }, metal = { 52, 54, 50 } }
		)
	),
	soPasse(
		weapon(
			"skin_type56_vermelha",
			"type56",
			"VC",
			"weapon_plus",
			"PASS_SET_ARMAS",
			"Tipo 56 · madeira avermelhada",
			"Coronha e guarda-mão de madeira de fábrica tingida de vermelho-escuro.",
			{ wood = { 118, 60, 38 }, handguard = { 118, 60, 38 } }
		)
	),
	soPasse(
		weapon(
			"skin_sks_clara",
			"sks",
			"VC",
			"weapon_plus",
			"PASS_SET_ARMAS",
			"SKS · madeira clara",
			"Coronha inteiriça de madeira clara, envernizada de fábrica.",
			{ wood = BIRCH }
		)
	),
	soPasse(
		weapon(
			"skin_rpd_azulado",
			"rpd",
			"VC",
			"weapon_plus",
			"PASS_SET_ARMAS",
			"RPD · aço azulado e madeira escura",
			"Oxidação azul inteira e coronha de madeira escura, oleada.",
			{ metal = BLUED, wood = WALNUT }
		)
	),
} :: { Skin }

-- ===== uniformes =====
-- O Commerce já tem o OG-107 padrão e o de mangas arregaçadas (EUA), o cáqui (padrão) e o verde da
-- Força Principal (VC). Aqui só o que não existe lá (sem duplicar).
-- - OG-107 desbotado: o mesmo utilitário de algodão, lavado e queimado de sol.
-- - Tiger stripe: usado pelos assessores americanos junto das unidades sul-vietnamitas em 1965
--   (fuzileiros assessores da VNMC, Rangers, Forças Especiais). Corte de utilitário, sem estêncil.
-- - Duck hunter: padrão comercial de caça, usado por assessores e Forças Especiais no começo da
--   década de 1960 (e o "frogskin" dos fuzileiros no Pacífico, 1943-44). Sem estêncil.
-- - Pijama preto (áo bà ba): a guerrilha local; o molde já existe (vc_black_*_v3, publicado).
-- D-131 (lote 17, dono: "coloque umas camuflagens diferentes tipo tigrado etc"):
-- - Tiger stripe "tadpole": a variante esparsa do começo dos anos 60 (Rangers e assessores).
-- - Lagarto (TAP 47 francês): dos paraquedistas sul-vietnamitas e dos assessores deles.
-- - Áo bà ba marrom: o camponês do Sul tingido de củ nâu, a cor mais comum depois do preto.
-- - Tiger stripe capturado: o do ARVN tomado em combate (raro; conferir com consultor).
local function uniform(
	id: string,
	side: string,
	key: string,
	name: string,
	desc: string,
	swatch: { { number } },
	shirt: string?,
	pants: string?,
	gearUniform: string?,
	pattern: string?
): Skin
	local s = base(id, "uniform", side, "uniform", key, name, desc)
	s.swatch = swatch
	s.shirt = shirt
	s.pants = pants
	s.gearUniform = gearUniform
	s.rgb = { shirt = swatch[1], pants = swatch[1] }
	s.pattern = pattern
	return s
end

for _, s in
	{
		uniform(
			"skin_us_faded",
			"US",
			"PASS_SKIN_US_FADED",
			"OG-107 desbotado",
			"Utilitário de algodão lavado e queimado de sol, com o estêncil do bolso quase sumido.",
			{ { 124, 126, 96 }, { 150, 150, 120 }, { 98, 102, 70 } },
			"us_faded_shirt_v3",
			"us_faded_pants_v3",
			nil
		),
		uniform(
			"skin_us_tiger",
			"US",
			"PASS_SKIN_US_TIGER",
			"Tiger stripe (assessores)",
			"Listras de tigre dos assessores junto das unidades sul-vietnamitas em 1965.",
			{ { 146, 138, 92 }, { 84, 98, 58 }, { 92, 72, 44 }, { 30, 30, 28 } },
			"us_tiger_shirt_v3",
			"us_tiger_pants_v3",
			nil,
			"tiger"
		),
		uniform(
			"skin_us_duck",
			"US",
			"PASS_SKIN_US_DUCK",
			"Duck hunter",
			"Padrão de caça em manchas, dos assessores e Forças Especiais do começo dos anos 60.",
			{ { 164, 150, 110 }, { 102, 108, 68 }, { 110, 86, 58 }, { 58, 48, 36 } },
			"us_duck_shirt_v3",
			"us_duck_pants_v3",
			nil,
			"duck"
		),
		uniform(
			"skin_vc_black",
			"VC",
			"PASS_SKIN_VC_BLACK",
			"Pijama preto (áo bà ba)",
			"O preto da guerrilha local: sem gola, dois bolsos baixos, mangas arregaçadas.",
			{ { 40, 40, 42 }, { 72, 68, 64 } },
			nil,
			nil,
			"vc_black"
		),
		-- D-131 (lote 17)
		uniform(
			"skin_us_tadpole",
			"US",
			"PASS_SKIN_US_TADPOLE",
			"Tiger stripe tadpole",
			"O tigrado esparso do começo dos anos 60: traços finos e curtos, muito fundo claro.",
			{ { 156, 150, 104 }, { 70, 92, 52 }, { 98, 74, 46 }, { 28, 28, 26 } },
			"us_tadpole_shirt_v3",
			"us_tadpole_pants_v3",
			nil,
			"tadpole"
		),
		uniform(
			"skin_us_lizard",
			"US",
			"PASS_SKIN_US_LIZARD",
			"Lagarto (paraquedistas)",
			"Pinceladas verticais verdes e marrons do padrão francês dos paraquedistas sul-vietnamitas.",
			{ { 134, 140, 96 }, { 68, 96, 56 }, { 110, 82, 52 } },
			"us_lizard_shirt_v3",
			"us_lizard_pants_v3",
			nil,
			"lizard"
		),
		uniform(
			"skin_vc_brown",
			"VC",
			"PASS_SKIN_VC_BROWN",
			"Áo bà ba marrom",
			"O camponês do Sul tingido de củ nâu: marrom-avermelhado, mangas arregaçadas, sandália.",
			{ { 92, 62, 44 }, { 128, 96, 72 } },
			"vc_brown_shirt_v3",
			"vc_brown_pants_v3",
			nil,
			"plain"
		),
		uniform(
			"skin_vc_tiger",
			"VC",
			"PASS_SKIN_VC_TIGER",
			"Tiger stripe capturado",
			"Tigrado tomado do ARVN, gasto e encardido, no corte do uniforme do VC.",
			{ { 128, 120, 82 }, { 72, 86, 50 }, { 82, 64, 40 }, { 28, 28, 26 } },
			"vc_tiger_shirt_v3",
			"vc_tiger_pants_v3",
			nil,
			"tiger"
		),
		-- ===== D-176: conjuntos em Game Pass (só pelo passe; cores de olho, `check = "foto"`) =====
		-- "Uniformes Históricos" (PASS_SET_UNIFORMES)
		soPasse(
			uniform(
				"skin_us_hbt",
				"US",
				"PASS_SET_UNIFORMES",
				"HBT verde-sálvia",
				"A sarja espinha de peixe dos utilitários antigos, mais verde e mais clara que o algodão novo.",
				{ { 112, 124, 92 }, { 140, 148, 116 } },
				"us_hbt_shirt_v3",
				"us_hbt_pants_v3",
				nil,
				"plain"
			)
		),
		soPasse(
			uniform(
				"skin_us_goldtiger",
				"US",
				"PASS_SET_UNIFORMES",
				"Tigrado dourado",
				"A variante de fundo amarelado do tiger stripe dos assessores.",
				{ { 176, 152, 96 }, { 96, 104, 60 }, { 112, 82, 46 }, { 34, 32, 28 } },
				"us_goldtiger_shirt_v3",
				"us_goldtiger_pants_v3",
				nil,
				"tiger"
			)
		),
		soPasse(
			uniform(
				"skin_vc_oliva",
				"VC",
				"PASS_SET_UNIFORMES",
				"Áo bà ba verde-oliva",
				"O pano tingido de verde das forças locais, mangas arregaçadas.",
				{ { 84, 92, 62 }, { 118, 124, 92 } },
				"vc_oliva_shirt_v3",
				"vc_oliva_pants_v3",
				nil,
				"plain"
			)
		),
		soPasse(
			uniform(
				"skin_vc_anil",
				"VC",
				"PASS_SET_UNIFORMES",
				"Áo bà ba anil",
				"Tingido de anil, azul muito escuro que desbota para o cinza-azulado.",
				{ { 36, 40, 56 }, { 70, 76, 94 } },
				"vc_anil_shirt_v3",
				"vc_anil_pants_v3",
				nil,
				"plain"
			)
		),
		-- "Fundador STARLITE" (PASS_SET_FUNDADOR)
		soPasse(
			uniform(
				"skin_us_fundador",
				"US",
				"PASS_SET_FUNDADOR",
				"Fundador · EUA",
				"O utilitário de sempre num pano exclusivo, mais escuro: de quem apoiou o jogo no começo.",
				{ { 70, 78, 52 }, { 104, 110, 82 } },
				"us_fundador_shirt_v3",
				"us_fundador_pants_v3",
				nil,
				"plain"
			)
		),
		soPasse(
			uniform(
				"skin_vc_fundador",
				"VC",
				"PASS_SET_FUNDADOR",
				"Fundador · Frente",
				"O uniforme da Força Principal num pano exclusivo, mais escuro: de quem apoiou o jogo no começo.",
				{ { 62, 66, 54 }, { 96, 98, 84 } },
				"vc_fundador_shirt_v3",
				"vc_fundador_pants_v3",
				nil,
				"plain"
			)
		),
	}
do
	table.insert(Skins.CATALOG, s)
end

-- ===== camuflagem de mato =====
-- Feixes de folha e capim presos ao corpo (tools/ghillie.py), como o capim e os galhos que os dois
-- lados prendiam no capacete, nas costas e no equipamento. A textura muda com o tipo; a malha é a
-- mesma. "Camo" no personagem = tipo da vegetação (BotBrain.CAMO).
local function camo(id: string, key: string, kind: string, name: string, desc: string, swatch: { { number } }): Skin
	local s = base(id, "camo", "both", "camo", key, name, desc)
	s.camo = kind
	s.texture = "ghillie_" .. kind
	s.swatch = swatch
	s.check = "foto + consultor"
	return s
end

for _, s in
	{
		camo(
			"camo_rice",
			"PASS_CAMO_RICE",
			"rice",
			"Camuflagem de arrozal",
			"Feixes de arroz verde-claro e palha seca. Os bots só te veem de mais perto no arrozal e no capim; deitado, mais perto ainda.",
			{ { 132, 146, 62 }, { 186, 168, 104 }, { 86, 110, 36 } }
		),
		camo(
			"camo_jungle",
			"PASS_CAMO_JUNGLE",
			"jungle",
			"Camuflagem de selva",
			"Folha larga escura da mata fechada. Os bots só te veem de mais perto na mata; deitado, mais perto ainda.",
			{ { 46, 70, 34 }, { 70, 96, 44 }, { 30, 44, 24 } }
		),
		camo(
			"camo_bamboo",
			"PASS_CAMO_BAMBOO",
			"bamboo",
			"Camuflagem de bambu",
			"Folha estreita verde-amarelada do bambuzal. Os bots só te veem de mais perto no bambu (e um pouco na mata); deitado, mais perto ainda.",
			{ { 150, 160, 70 }, { 112, 132, 52 }, { 182, 170, 96 } }
		),
	}
do
	table.insert(Skins.CATALOG, s)
end

-- ===== D-178: ARSENAL EXTRAVAGANTE (pedido do dono: "100 novas skins e itens ... bem
-- extravagantes"). Só nas caixas e na troca de Fragmentos (`soCaixa`: fora do $ da Intendência e
-- do Mercado). Nomes e desenhos próprios: a inspiração é o estilo de pintura de jogos de tiro, sem
-- copiar nome nem desenho de nenhum. O desenho sai de `arte` (tools/acabamentos.py): a receita do
-- padrão em 3D (contínuo na arma inteira, por cima da sombra e dos detalhes da textura original),
-- as cores e onde pinta ("tudo", "metal" ou "madeira"). `finish` é a cor de reserva da arma
-- provisória (Shared/GunModel). Todos são só visuais.
export type Arte = { receita: string, cores: { { number } }, alvo: string }
local EXTRAVAGANTES: { { any } } = {
	-- id, arma, lado, nome, descrição, receita, cores, alvo
	-- M14
	{
		"skin_m14_tigre_fogo",
		"m14",
		"US",
		"M14 · Tigre de Fogo",
		"Listras de tigre laranja e preto da coronha à boca do cano.",
		"tigre",
		{ { 238, 110, 26 }, { 20, 16, 14 } },
		"tudo",
	},
	{
		"skin_m14_por_do_sol",
		"m14",
		"US",
		"M14 · Pôr do Sol",
		"Degradê do amarelo ao magenta, como o céu de Chu Lai no fim da tarde.",
		"fade",
		{ { 252, 206, 64 }, { 240, 96, 40 }, { 168, 40, 120 } },
		"tudo",
	},
	{
		"skin_m14_damasco_azul",
		"m14",
		"US",
		"M14 · Damasco Azul",
		"Aço damasco em ondas, azulado a fogo.",
		"damasco",
		{ { 120, 150, 196 }, { 22, 30, 52 } },
		"metal",
	},
	{
		"skin_m14_selva_eletrica",
		"m14",
		"US",
		"M14 · Selva Elétrica",
		"Manchas de mata em verde-limão, preto e petróleo.",
		"camo",
		{ { 150, 230, 40 }, { 16, 20, 18 }, { 20, 110, 96 }, { 70, 90, 30 } },
		"tudo",
	},
	{
		"skin_m14_carbono",
		"m14",
		"US",
		"M14 · Trama de Carbono",
		"Trama de carbono preta e cinza no metal.",
		"carbono",
		{ { 18, 18, 20 }, { 74, 76, 82 } },
		"metal",
	},
	{
		"skin_m14_laca_vermelha",
		"m14",
		"US",
		"M14 · Laca Vermelha e Ouro",
		"Coronha em laca vermelha de Huế com flocos de ouro.",
		"laca",
		{ { 150, 22, 24 }, { 236, 190, 80 } },
		"madeira",
	},
	-- M16
	{
		"skin_m16_aurora",
		"m16",
		"US",
		"M16 · Aurora",
		"Do verde ao violeta, como a luz do norte.",
		"fade",
		{ { 60, 240, 150 }, { 40, 170, 220 }, { 140, 60, 210 } },
		"tudo",
	},
	{
		"skin_m16_pixel_neon",
		"m16",
		"US",
		"M16 · Pixel Neon",
		"Quadradinhos magenta, ciano e preto.",
		"digital",
		{ { 240, 40, 170 }, { 30, 220, 230 }, { 14, 14, 20 }, { 90, 30, 140 } },
		"tudo",
	},
	{
		"skin_m16_cromo",
		"m16",
		"US",
		"M16 · Cromo Espelhado",
		"Cromo claro com reflexos frios.",
		"cromo",
		{ { 236, 240, 246 }, { 70, 78, 92 }, { 180, 210, 240 } },
		"tudo",
	},
	{
		"skin_m16_colmeia_neon",
		"m16",
		"US",
		"M16 · Colmeia Neon",
		"Grade de hexágonos ciano sobre preto.",
		"hex",
		{ { 14, 16, 22 }, { 40, 230, 240 } },
		"tudo",
	},
	{
		"skin_m16_artico",
		"m16",
		"US",
		"M16 · Ártico",
		"Manchas de neve, gelo e cinza.",
		"camo",
		{ { 236, 240, 244 }, { 170, 186, 200 }, { 96, 108, 122 }, { 200, 220, 236 } },
		"tudo",
	},
	{
		"skin_m16_zebra",
		"m16",
		"US",
		"M16 · Zebra",
		"Listras pretas e brancas, sem meio-termo.",
		"zebra",
		{ { 240, 240, 236 }, { 16, 16, 16 } },
		"tudo",
	},
	-- M60
	{
		"skin_m60_escamas_rubras",
		"m60",
		"US",
		"M60 · Escamas Rubras",
		"Escamas vermelhas com a borda dourada.",
		"escamas",
		{ { 168, 24, 30 }, { 230, 180, 70 }, { 250, 110, 80 } },
		"tudo",
	},
	{
		"skin_m60_lava_viva",
		"m60",
		"US",
		"M60 · Lava Viva",
		"Rocha negra rachada com o fogo por baixo.",
		"lava",
		{ { 22, 18, 18 }, { 250, 110, 20 }, { 255, 220, 90 } },
		"tudo",
	},
	{
		"skin_m60_noite_urbana",
		"m60",
		"US",
		"M60 · Noite Urbana",
		"Manchas cinza-azuladas de cidade à noite.",
		"camo",
		{ { 52, 60, 76 }, { 24, 28, 36 }, { 110, 118, 132 }, { 74, 84, 104 } },
		"tudo",
	},
	{
		"skin_m60_carbono_vermelho",
		"m60",
		"US",
		"M60 · Carbono Vermelho",
		"Trama de carbono com fio vermelho.",
		"carbono",
		{ { 26, 12, 14 }, { 170, 30, 34 } },
		"metal",
	},
	{
		"skin_m60_tempestade",
		"m60",
		"US",
		"M60 · Tempestade",
		"Relâmpagos azuis cortando o metal escuro.",
		"raio",
		{ { 16, 20, 34 }, { 120, 210, 255 } },
		"tudo",
	},
	-- M1911A1
	{
		"skin_m1911_ouro_polido",
		"m1911",
		"US",
		"M1911A1 · Ouro Polido",
		"A pistola inteira em ouro, com talas de nogueira.",
		"ouro",
		{ { 236, 190, 70 }, { 120, 80, 20 } },
		"metal",
	},
	{
		"skin_m1911_madreperola",
		"m1911",
		"US",
		"M1911A1 · Madrepérola",
		"Laca negra com incrustação de madrepérola.",
		"laca",
		{ { 16, 16, 20 }, { 220, 236, 236 } },
		"tudo",
	},
	{
		"skin_m1911_carrara",
		"m1911",
		"US",
		"M1911A1 · Mármore Carrara",
		"Branco com veios cinza, como pedra polida.",
		"marmore",
		{ { 236, 234, 228 }, { 120, 120, 124 }, { 180, 178, 176 } },
		"tudo",
	},
	{
		"skin_m1911_ouro_rosa",
		"m1911",
		"US",
		"M1911A1 · Ouro Rosa",
		"Aço banhado em ouro rosa escovado.",
		"ouro",
		{ { 232, 150, 130 }, { 120, 60, 50 } },
		"metal",
	},
	{
		"skin_m1911_damasco_cinza",
		"m1911",
		"US",
		"M1911A1 · Damasco Cinza",
		"Ondas de aço damasco claro e escuro.",
		"damasco",
		{ { 190, 192, 196 }, { 46, 48, 52 } },
		"metal",
	},
	-- Winchester M70
	{
		"skin_m70_carta",
		"m70",
		"US",
		"Winchester M70 · Carta Topográfica",
		"As curvas de nível da carta de Van Tuong por todo o fuzil.",
		"topo",
		{ { 222, 210, 172 }, { 150, 104, 60 }, { 70, 110, 150 } },
		"tudo",
	},
	{
		"skin_m70_marmore_negro",
		"m70",
		"US",
		"Winchester M70 · Mármore Negro",
		"Pedra negra com veios de ouro.",
		"marmore",
		{ { 18, 18, 20 }, { 220, 176, 70 }, { 90, 80, 60 } },
		"tudo",
	},
	{
		"skin_m70_bambu",
		"m70",
		"US",
		"Winchester M70 · Bambu Dourado",
		"Coronha em gomos de bambu claro.",
		"bambu",
		{ { 206, 176, 96 }, { 120, 92, 40 } },
		"madeira",
	},
	{
		"skin_m70_deserto_rosa",
		"m70",
		"US",
		"Winchester M70 · Deserto Rosa",
		"Manchas de areia, rosa e terra.",
		"camo",
		{ { 226, 176, 170 }, { 200, 170, 120 }, { 150, 100, 80 }, { 240, 210, 190 } },
		"tudo",
	},
	{
		"skin_m70_nebulosa",
		"m70",
		"US",
		"Winchester M70 · Nebulosa",
		"Nuvens roxas e azuis com estrelas.",
		"galaxia",
		{ { 10, 8, 24 }, { 130, 50, 190 }, { 40, 110, 210 }, { 255, 255, 255 } },
		"tudo",
	},
	-- Winchester 12
	{
		"skin_win12_chamas",
		"win12",
		"US",
		"Winchester 12 · Chamas Clássicas",
		"Chamas laranja e amarelas saindo da culatra, sobre preto.",
		"chamas",
		{ { 18, 16, 16 }, { 240, 90, 20 }, { 255, 210, 60 } },
		"tudo",
	},
	{
		"skin_win12_zebra_vermelha",
		"win12",
		"US",
		"Winchester 12 · Zebra Vermelha",
		"Listras vermelhas e pretas.",
		"zebra",
		{ { 200, 30, 34 }, { 16, 14, 14 } },
		"tudo",
	},
	{
		"skin_win12_outono",
		"win12",
		"US",
		"Winchester 12 · Outono",
		"Manchas de folha seca: laranja, vinho e marrom.",
		"camo",
		{ { 210, 110, 40 }, { 120, 40, 34 }, { 90, 60, 36 }, { 230, 170, 70 } },
		"tudo",
	},
	{
		"skin_win12_titanio",
		"win12",
		"US",
		"Winchester 12 · Titânio Queimado",
		"Aço tratado a fogo: azul, roxo e dourado.",
		"anodizado",
		{ { 60, 80, 200 }, { 150, 60, 170 }, { 230, 180, 80 } },
		"metal",
	},
	{
		"skin_win12_pixel_floresta",
		"win12",
		"US",
		"Winchester 12 · Pixel Floresta",
		"Quadradinhos verdes e marrons.",
		"digital",
		{ { 84, 110, 52 }, { 50, 66, 34 }, { 110, 88, 58 }, { 150, 150, 100 } },
		"tudo",
	},
	-- Tipo 56
	{
		"skin_type56_serpente",
		"type56",
		"VC",
		"Tipo 56 · Escamas de Serpente",
		"Escamas verde-oliva com a borda negra.",
		"escamas",
		{ { 96, 120, 44 }, { 20, 24, 14 }, { 170, 190, 80 } },
		"tudo",
	},
	{
		"skin_type56_furta_cor",
		"type56",
		"VC",
		"Tipo 56 · Furta-cor",
		"Película de óleo que muda de cor com a luz.",
		"oleo",
		{ { 255, 255, 255 } },
		"tudo",
	},
	{
		"skin_type56_jade",
		"type56",
		"VC",
		"Tipo 56 · Jade Imperial",
		"Pedra de jade verde com veios claros.",
		"jade",
		{ { 120, 200, 140 }, { 20, 90, 60 } },
		"tudo",
	},
	{
		"skin_type56_tigre_branco",
		"type56",
		"VC",
		"Tipo 56 · Tigre Branco",
		"Listras pretas sobre branco e cinza.",
		"tigre",
		{ { 230, 230, 226 }, { 20, 20, 22 } },
		"tudo",
	},
	{
		"skin_type56_sangue_ouro",
		"type56",
		"VC",
		"Tipo 56 · Sangue e Ouro",
		"Degradê do vermelho-sangue ao ouro.",
		"fade",
		{ { 120, 10, 16 }, { 200, 40, 30 }, { 240, 190, 70 } },
		"tudo",
	},
	{
		"skin_type56_pixel_oceano",
		"type56",
		"VC",
		"Tipo 56 · Pixel Oceano",
		"Quadradinhos azuis do raso ao fundo.",
		"digital",
		{ { 40, 130, 200 }, { 20, 60, 120 }, { 120, 200, 230 }, { 10, 30, 70 } },
		"tudo",
	},
	-- SKS
	{
		"skin_sks_laca_negra",
		"sks",
		"VC",
		"SKS · Laca Negra e Ouro",
		"Laca negra com folha de ouro, como os painéis de sơn mài.",
		"laca",
		{ { 14, 12, 12 }, { 230, 180, 70 } },
		"madeira",
	},
	{
		"skin_sks_mar_profundo",
		"sks",
		"VC",
		"SKS · Mar Profundo",
		"Degradê do verde-água ao azul-marinho.",
		"fade",
		{ { 60, 200, 190 }, { 20, 110, 150 }, { 10, 30, 80 } },
		"tudo",
	},
	{
		"skin_sks_malaquita",
		"sks",
		"VC",
		"SKS · Malaquita",
		"Faixas verdes em ondas, como a pedra.",
		"malaquita",
		{ { 30, 140, 90 }, { 10, 60, 40 }, { 120, 220, 170 } },
		"tudo",
	},
	{
		"skin_sks_tigre_jade",
		"sks",
		"VC",
		"SKS · Tigre de Jade",
		"Listras negras sobre verde-jade.",
		"tigre",
		{ { 90, 180, 120 }, { 14, 30, 22 } },
		"tudo",
	},
	{
		"skin_sks_chamas_azuis",
		"sks",
		"VC",
		"SKS · Chamas Azuis",
		"Chamas azuis e brancas sobre preto.",
		"chamas",
		{ { 14, 16, 26 }, { 40, 110, 240 }, { 190, 230, 255 } },
		"tudo",
	},
	{
		"skin_sks_carbono",
		"sks",
		"VC",
		"SKS · Trama de Carbono",
		"Trama de carbono no metal.",
		"carbono",
		{ { 18, 18, 20 }, { 74, 76, 82 } },
		"metal",
	},
	-- RPD
	{
		"skin_rpd_gelo",
		"rpd",
		"VC",
		"RPD · Gelo Rachado",
		"Gelo branco-azulado com rachaduras.",
		"lava",
		{ { 220, 236, 248 }, { 60, 120, 200 }, { 150, 200, 240 } },
		"tudo",
	},
	{
		"skin_rpd_escamas_abissais",
		"rpd",
		"VC",
		"RPD · Escamas Abissais",
		"Escamas roxas e verde-água do fundo do mar.",
		"escamas",
		{ { 70, 30, 120 }, { 30, 200, 190 }, { 180, 120, 240 } },
		"tudo",
	},
	{
		"skin_rpd_raio_vermelho",
		"rpd",
		"VC",
		"RPD · Raio Vermelho",
		"Relâmpagos vermelhos no metal escuro.",
		"raio",
		{ { 22, 12, 14 }, { 255, 70, 60 } },
		"tudo",
	},
	{
		"skin_rpd_colmeia_ambar",
		"rpd",
		"VC",
		"RPD · Colmeia Âmbar",
		"Grade de hexágonos âmbar sobre marrom.",
		"hex",
		{ { 40, 26, 14 }, { 240, 160, 40 } },
		"tudo",
	},
	{
		"skin_rpd_via_lactea",
		"rpd",
		"VC",
		"RPD · Via Láctea",
		"Faixa de estrelas sobre o céu escuro.",
		"galaxia",
		{ { 6, 8, 18 }, { 40, 60, 130 }, { 120, 110, 170 }, { 255, 250, 230 } },
		"tudo",
	},
	{
		"skin_rpd_selva_escura",
		"rpd",
		"VC",
		"RPD · Selva Escura",
		"Manchas de mata fechada à noite.",
		"camo",
		{ { 30, 46, 30 }, { 14, 20, 14 }, { 60, 74, 46 }, { 40, 34, 24 } },
		"tudo",
	},
	-- Tipo 54
	{
		"skin_type54_ouro_negro",
		"type54",
		"VC",
		"Tipo 54 · Ouro Negro",
		"Armação negra com o ferrolho em ouro.",
		"ouro",
		{ { 230, 182, 64 }, { 20, 18, 16 } },
		"tudo",
	},
	{
		"skin_type54_damasco_ouro",
		"type54",
		"VC",
		"Tipo 54 · Damasco Ouro",
		"Ondas de damasco em ouro e aço.",
		"damasco",
		{ { 236, 190, 90 }, { 70, 56, 30 } },
		"metal",
	},
	{
		"skin_type54_cromo_azul",
		"type54",
		"VC",
		"Tipo 54 · Cromo Azul",
		"Cromo com o reflexo azul.",
		"cromo",
		{ { 200, 220, 250 }, { 30, 50, 100 }, { 120, 170, 240 } },
		"tudo",
	},
	{
		"skin_type54_carta_noturna",
		"type54",
		"VC",
		"Tipo 54 · Carta Noturna",
		"Curvas de nível verdes brilhando no preto.",
		"topo",
		{ { 10, 16, 12 }, { 50, 200, 90 }, { 140, 255, 160 } },
		"tudo",
	},
	{
		"skin_type54_artico",
		"type54",
		"VC",
		"Tipo 54 · Ártico",
		"Manchas de neve e gelo.",
		"camo",
		{ { 236, 240, 244 }, { 170, 186, 200 }, { 96, 108, 122 }, { 200, 220, 236 } },
		"tudo",
	},
	-- Mosin-Nagant
	{
		"skin_mosin_laca_vermelha",
		"mosin",
		"VC",
		"Mosin-Nagant · Laca Vermelha e Ouro",
		"Coronha longa em laca vermelha com ouro.",
		"laca",
		{ { 150, 22, 24 }, { 236, 190, 80 } },
		"madeira",
	},
	{
		"skin_mosin_bambu_negro",
		"mosin",
		"VC",
		"Mosin-Nagant · Bambu Negro",
		"Gomos de bambu escuro na coronha.",
		"bambu",
		{ { 50, 44, 30 }, { 14, 12, 8 } },
		"madeira",
	},
	{
		"skin_mosin_nebulosa_rubra",
		"mosin",
		"VC",
		"Mosin-Nagant · Nebulosa Rubra",
		"Nuvens vermelhas e laranja com estrelas.",
		"galaxia",
		{ { 14, 6, 10 }, { 190, 40, 50 }, { 240, 130, 40 }, { 255, 240, 220 } },
		"tudo",
	},
	{
		"skin_mosin_selva_eletrica",
		"mosin",
		"VC",
		"Mosin-Nagant · Selva Elétrica",
		"Manchas verde-limão, preto e petróleo.",
		"camo",
		{ { 150, 230, 40 }, { 16, 20, 18 }, { 20, 110, 96 }, { 70, 90, 30 } },
		"tudo",
	},
	{
		"skin_mosin_inverno",
		"mosin",
		"VC",
		"Mosin-Nagant · Inverno",
		"Branco de inverno com a coronha clara.",
		"camo",
		{ { 236, 236, 232 }, { 200, 200, 196 }, { 150, 150, 146 }, { 220, 216, 206 } },
		"tudo",
	},
}
Skins.EXTRAVAGANTES = EXTRAVAGANTES
for _, e in EXTRAVAGANTES do
	local cores = e[7] :: { { number } }
	local s = weapon(e[1], e[2], e[3], "weapon_plus", "CAIXA", e[4], e[5], {
		metal = cores[1],
		wood = cores[2] or cores[1],
		handguard = cores[2] or cores[1],
	})
	s.soCaixa = true
	s.arte = { receita = e[6], cores = cores, alvo = e[8] }
	s.check = "estilo"
	table.insert(Skins.CATALOG, s)
end

-- ===== D-179: ACABAMENTOS UNIVERSAIS (pedido do dono: "faça skins estilo jogo r6 tbm como inverno
-- sombrio, geleiras, entre outras" e "skins das pedras tem q ter relevo"). Um item vale em qualquer
-- arma com arte (Skins.ARMAS_UNIVERSAL), do lado do jogador: escolhe-se a arma ao equipar. Só nas
-- caixas e na troca. A textura de cada arma sai de tools/acabamentos.py (chave "id@arma"), com
-- relevo de verdade (mapa normal) e brilho próprio (metal e aspereza) na SurfaceAppearance.
-- Nomes próprios: nenhum nome de skin de outro jogo.
Skins.ARMAS_UNIVERSAL = { "m14", "m16", "m60", "m1911", "m70", "win12", "type56", "sks", "rpd", "type54", "mosin" }
local ARMA_UNIVERSAL: { [string]: boolean } = {}
for _, w in Skins.ARMAS_UNIVERSAL do
	ARMA_UNIVERSAL[w] = true
end
-- arma do acabamento universal quando o jogador não escolheu (a de fábrica de cada lado)
Skins.ARMA_PADRAO = { US = "m14", VC = "type56" }

local UNIVERSAIS: { { any } } = {
	-- id, nome, descrição, receita, cores, alvo, arma da vitrine
	{
		"uni_cristal_rubro",
		"Cristal Rubro",
		"Facetas de rubi lapidado: cada face pega a luz de um jeito. Vale em qualquer arma.",
		"cristal",
		{ { 196, 14, 28 }, { 255, 130, 130 } },
		"tudo",
		"m16",
	},
	{
		"uni_cristal_ciano",
		"Cristal Ciano",
		"Facetas de pedra ciano que brilham como água rasa. Vale em qualquer arma.",
		"cristal",
		{ { 0, 178, 196 }, { 170, 255, 255 } },
		"tudo",
		"type56",
	},
	{
		"uni_cristal_cobalto",
		"Cristal Cobalto",
		"Facetas azul-cobalto, fundas e frias. Vale em qualquer arma.",
		"cristal",
		{ { 22, 70, 196 }, { 150, 196, 255 } },
		"tudo",
		"m14",
	},
	{
		"uni_cristal_ambar",
		"Cristal Âmbar",
		"Facetas de topázio cor de mel, quentes na luz. Vale em qualquer arma.",
		"cristal",
		{ { 218, 132, 12 }, { 255, 226, 130 } },
		"tudo",
		"sks",
	},
	{
		"uni_cristal_violeta",
		"Cristal Violeta",
		"Facetas de ametista, do lilás ao roxo fundo. Vale em qualquer arma.",
		"cristal",
		{ { 124, 56, 188 }, { 222, 176, 255 } },
		"tudo",
		"m1911",
	},
	{
		"uni_cristal_esmeralda",
		"Cristal Esmeralda",
		"Facetas verde-esmeralda com o brilho claro nas arestas. Vale em qualquer arma.",
		"cristal",
		{ { 8, 136, 70 }, { 146, 255, 186 } },
		"tudo",
		"rpd",
	},
	{
		"uni_quartzo_rosa",
		"Quartzo Rosa",
		"Facetas rosadas e leitosas de quartzo. Vale em qualquer arma.",
		"cristal",
		{ { 226, 138, 168 }, { 255, 222, 232 } },
		"tudo",
		"type54",
	},
	{
		"uni_obsidiana",
		"Obsidiana Lapidada",
		"Vidro vulcânico negro em facetas, com o reflexo roxo. Vale em qualquer arma.",
		"obsidiana",
		{ { 14, 12, 18 }, { 132, 76, 210 } },
		"tudo",
		"m70",
	},
	{
		"uni_ouro_lapidado",
		"Ouro Lapidado",
		"Ouro maciço cortado em facetas que espelham o céu. Vale em qualquer arma.",
		"ouro_lapidado",
		{ { 226, 166, 40 }, { 255, 240, 170 } },
		"tudo",
		"win12",
	},
	{
		"uni_inverno_sombrio",
		"Inverno Sombrio",
		"Azul de noite gelada com geada nas manchas e neve no que fica para cima. Vale em qualquer arma.",
		"inverno",
		{ { 14, 20, 34 }, { 172, 210, 255 }, { 240, 248, 255 } },
		"tudo",
		"m60",
	},
	{
		"uni_geleira_antiga",
		"Geleira Antiga",
		"Gelo em camadas, do branco ao azul fundo, cortado por rachaduras. Vale em qualquer arma.",
		"geleira",
		{ { 226, 240, 252 }, { 120, 186, 236 }, { 24, 78, 150 } },
		"tudo",
		"mosin",
	},
	{
		"uni_onix_polido",
		"Ônix Polido",
		"Pedra polida em faixas pretas e brancas com o relevo das camadas. Vale em qualquer arma.",
		"onix",
		{ { 16, 16, 18 }, { 236, 232, 226 }, { 112, 110, 106 } },
		"tudo",
		"m14",
	},
	-- D-180: mais 12 (pedido do dono: "continue fazendo"), no espírito das imagens que ele mandou:
	-- gemas nevadas, cristal iridescente e polar, ouro derretido, ondas, cerejeira, nuvem desenhada,
	-- rede neon, porcelana de Huế e jade com ouro
	{
		"uni_nevasca_rubra",
		"Nevasca Rubra",
		"Facetas vermelhas lapidadas no meio da geada branca. Vale em qualquer arma.",
		"nevasca",
		{ { 200, 20, 36 }, { 255, 235, 240 } },
		"tudo",
		"m14",
	},
	{
		"uni_nevasca_violeta",
		"Nevasca Violeta",
		"Facetas roxas lapidadas no meio da geada branca. Vale em qualquer arma.",
		"nevasca",
		{ { 120, 40, 200 }, { 245, 235, 255 } },
		"tudo",
		"m16",
	},
	{
		"uni_nevasca_rosa",
		"Nevasca Rosa",
		"Facetas cor-de-rosa lapidadas no meio da geada branca. Vale em qualquer arma.",
		"nevasca",
		{ { 236, 60, 150 }, { 255, 236, 246 } },
		"tudo",
		"sks",
	},
	{
		"uni_cristal_iridescente",
		"Cristal Iridescente",
		"Facetas claras que trocam de cor com a luz: rosa, verde-água e lilás. Vale em qualquer arma.",
		"iridescente",
		{ { 240, 244, 255 }, { 255, 170, 220 }, { 150, 240, 230 }, { 190, 160, 255 } },
		"tudo",
		"m1911",
	},
	{
		"uni_cristal_polar",
		"Cristal Polar",
		"Gelo azul em facetas com a geada branca nas arestas. Vale em qualquer arma.",
		"polar",
		{ { 190, 240, 255 }, { 20, 110, 190 }, { 255, 255, 255 } },
		"tudo",
		"m60",
	},
	{
		"uni_ouro_derretido",
		"Ouro Derretido",
		"Preto lustroso com o ouro escorrendo de cima em pingos. Vale em qualquer arma.",
		"derretido",
		{ { 14, 14, 16 }, { 232, 176, 48 } },
		"tudo",
		"type54",
	},
	{
		"uni_mar_revolto",
		"Mar Revolto",
		"Escamas de onda brancas sobre o azul que escurece até a noite, com espuma nas cristas. Vale em qualquer arma.",
		"ondas",
		{ { 24, 92, 170 }, { 10, 32, 80 }, { 236, 244, 252 } },
		"tudo",
		"rpd",
	},
	{
		"uni_galho_cerejeira",
		"Galho de Cerejeira",
		"Vermelho com galhos escuros e flores brancas de miolo dourado. Vale em qualquer arma.",
		"cerejeira",
		{ { 178, 16, 28 }, { 255, 236, 240 }, { 240, 190, 60 } },
		"tudo",
		"type56",
	},
	{
		"uni_nuvem_rubra",
		"Nuvem Rubra",
		"Preto com nuvens desenhadas em vermelho e fios de ouro. Vale em qualquer arma.",
		"nuvem",
		{ { 12, 12, 16 }, { 210, 30, 36 }, { 230, 180, 60 } },
		"tudo",
		"m70",
	},
	{
		"uni_rede_neon",
		"Rede Neon",
		"Malha de triângulos acesa, do magenta ao ciano, no azul-noite. Vale em qualquer arma.",
		"neon",
		{ { 14, 10, 30 }, { 255, 40, 200 }, { 30, 220, 255 } },
		"tudo",
		"win12",
	},
	{
		"uni_porcelana_hue",
		"Porcelana de Huế",
		"Esmalte branco com flores e ramos azul-cobalto e frisos de ouro. Vale em qualquer arma.",
		"porcelana",
		{ { 244, 246, 250 }, { 28, 64, 170 }, { 214, 160, 60 } },
		"tudo",
		"mosin",
	},
	{
		"uni_jade_ouro",
		"Jade e Ouro",
		"Jade verde com filigrana de ouro em arabescos. Vale em qualquer arma.",
		"jade_ouro",
		{ { 40, 150, 100 }, { 150, 230, 190 }, { 236, 190, 80 } },
		"tudo",
		"m16",
	},
}
for _, e in UNIVERSAIS do
	local cores = e[5] :: { { number } }
	local s = base(e[1], "weapon", "both", "weapon_plus", "CAIXA", e[2], e[3])
	s.finish = { metal = cores[1], wood = cores[1], handguard = cores[1] }
	s.swatch = cores
	s.soCaixa = true
	s.universal = true
	s.vitrine = e[7]
	s.arte = { receita = e[4], cores = cores, alvo = e[6] }
	s.check = "estilo"
	table.insert(Skins.CATALOG, s)
end
Skins.UNIVERSAIS = UNIVERSAIS
-- os lotes, na ordem da lista (as caixas acrescentam cada um na sua vez)
Skins.UNIVERSAIS_D179 = table.move(UNIVERSAIS, 1, 12, 1, {})
Skins.UNIVERSAIS_D180 = table.move(UNIVERSAIS, 13, #UNIVERSAIS, 1, {})

-- arma que aceita acabamento universal
function Skins.armaUniversal(arma: any): boolean
	return type(arma) == "string" and ARMA_UNIVERSAL[arma] == true
end

local byId: { [string]: Skin } = {}
for _, s in Skins.CATALOG do
	byId[s.id] = s
end
-- D-131: o tigrado capturado é raro nas fotos do VC: conferir com consultor antes do Game Pass
byId.skin_vc_tiger.check = "foto + consultor"

-- ===== consulta =====
function Skins.get(id: any): Skin?
	return if type(id) == "string" then byId[id] else nil
end

-- encaixe onde a skin fica equipada: id da arma, "uniform" ou "camo" (o universal, D-179, não
-- tem encaixe fixo: vale na arma escolhida; aqui volta a vitrine)
function Skins.slotOf(s: Skin): string
	return if s.kind == "weapon" then s.weapon or s.vitrine or "?" else s.kind
end

-- A skin cabe neste encaixe? (a de arma na arma dela; o universal em qualquer arma com arte)
function Skins.cabe(s: Skin, slot: string): boolean
	if s.kind ~= "weapon" then
		return s.kind == slot
	end
	return s.weapon == slot or (s.universal == true and Skins.armaUniversal(slot))
end

function Skins.sideOk(s: Skin, faction: string?): boolean
	return s.side == "both" or s.side == faction
end

-- lado em que equipar: o da skin; a de "ambos" vale no lado atual do jogador
function Skins.factionFor(s: Skin, current: string?): string?
	if s.side == "both" then
		return if current == "US" or current == "VC" then current else nil
	end
	return s.side
end

-- kind/faction nil = todos; o lado filtra (as de "ambos" entram)
function Skins.list(kind: string?, faction: string?): { Skin }
	local out = {}
	for _, s in Skins.CATALOG do
		if (kind == nil or s.kind == kind) and (faction == nil or Skins.sideOk(s, faction)) then
			table.insert(out, s)
		end
	end
	return out
end

function Skins.robuxId(s: Skin): number
	return Skins.IDS[s.robuxKey] or 0
end

-- Posse: comprada ($ ou Developer Product, no perfil) ou pelo Game Pass. Devolve o caminho.
function Skins.owns(s: Skin, owned: { [string]: boolean }?, passes: { [string]: boolean }?): (boolean, string?)
	if owned and owned[s.id] then
		return true, "bought"
	elseif s.robuxKind == "pass" and passes and passes[s.robuxKey] then
		return true, "pass"
	end
	return false, nil
end

-- Pode comprar com $? (o servidor confere de novo na hora de descontar)
function Skins.canBuy(
	id: string,
	owned: { [string]: boolean }?,
	passes: { [string]: boolean }?,
	money: number
): (boolean, string?)
	local s = Skins.get(id)
	if not s then
		return false, "skin desconhecida"
	elseif Skins.owns(s, owned, passes) then
		return false, "já é sua"
	elseif s.soPasse then
		return false, "só no conjunto em Game Pass"
	elseif s.soCaixa then
		return false, "só nas caixas"
	elseif money < s.price then
		return false, string.format("faltam %s", Progression.money(s.price - money))
	end
	return true, nil
end

function Skins.canEquip(
	id: string,
	faction: string?,
	owned: { [string]: boolean }?,
	passes: { [string]: boolean }?
): (boolean, string?)
	local s = Skins.get(id)
	if not s then
		return false, "skin desconhecida"
	elseif faction ~= "US" and faction ~= "VC" then
		return false, "escolha um lado primeiro"
	elseif not Skins.sideOk(s, faction) then
		return false, "skin do outro lado"
	elseif not Skins.owns(s, owned, passes) then
		return false, "skin não é sua"
	end
	return true, nil
end

-- O que vale de fato num lado: só skins conhecidas, do lado, no encaixe certo e ainda suas
-- (um Game Pass reembolsado some daqui sem apagar a escolha gravada).
function Skins.equipped(
	on: { [string]: string }?,
	faction: string?,
	owned: { [string]: boolean }?,
	passes: { [string]: boolean }?
): { [string]: string }
	local out: { [string]: string } = {}
	if not on then
		return out
	end
	for slot, id in on do
		local s = Skins.get(id)
		if s and Skins.cabe(s, slot) and Skins.canEquip(id, faction, owned, passes) then
			out[slot] = id
		end
	end
	return out
end

-- Skins de arma de um lado num texto curto (atributo "WeaponSkins" do jogador): "m14=skin_m14_birch;..."
function Skins.encodeWeapons(on: { [string]: string }): string
	local parts = {}
	for slot, id in on do
		local s = Skins.get(id)
		if s and s.kind == "weapon" and Skins.cabe(s, slot) then
			table.insert(parts, slot .. "=" .. id)
		end
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

function Skins.decodeWeapons(text: string?): { [string]: string }
	local out: { [string]: string } = {}
	if type(text) ~= "string" then
		return out
	end
	for slot, id in string.gmatch(text, "([%w_]+)=([%w_]+)") do
		local s = Skins.get(id)
		if s and s.kind == "weapon" and Skins.cabe(s, slot :: string) then
			out[slot :: string] = s.id
		end
	end
	return out
end

function Skins.weaponSkinFrom(text: any, weaponId: string): string?
	return Skins.decodeWeapons(if type(text) == "string" then text else nil)[weaponId]
end

-- ===== Robux: recibo e passe =====
function Skins.skinByProductId(productId: number): string?
	if type(productId) ~= "number" or productId == 0 then
		return nil
	end
	for _, s in Skins.CATALOG do
		if s.robuxKind == "product" and Skins.robuxId(s) == productId then
			return s.id
		end
	end
	return nil
end

function Skins.skinByPassId(passId: number): string?
	if type(passId) ~= "number" or passId == 0 then
		return nil
	end
	for _, s in Skins.CATALOG do
		if s.robuxKind == "pass" and Skins.robuxId(s) == passId then
			return s.id
		end
	end
	return nil
end

function Skins.passKeyById(passId: number): string?
	local id = Skins.skinByPassId(passId)
	local s = if id then Skins.get(id) else nil
	return if s then s.robuxKey else nil
end

-- chaves de todos os Game Passes de skin (o CommerceService confere a posse de cada um)
function Skins.passKeys(): { string }
	local out = {}
	for _, s in Skins.CATALOG do
		if s.robuxKind == "pass" then
			table.insert(out, s.robuxKey)
		end
	end
	return out
end

-- ===== pintura da arma =====
-- Cor (RGB) e material de uma classe de peça com a skin. nil = sem mudança (cor de fábrica). O
-- guarda-mão sem cor própria segue a madeira.
function Skins.paintFor(s: Skin?, cls: string): ({ number }?, string?)
	local f = if s then s.finish else nil
	if not f then
		return nil, nil
	end
	if cls == "handguard" then
		if f.handguard then
			return f.handguard, f.handguardMat
		end
		return f.wood, nil
	elseif cls == "wood" then
		return f.wood, nil
	elseif cls == "metal" then
		return f.metal, nil
	end
	return nil, nil
end

-- Aplica a skin (ou a cor de fábrica, com skinId nil) num modelo de arma: a de 3ª pessoa (servidor,
-- AssetLoader.attachWeapon) e a de 1ª pessoa (cliente: a câmera e a cópia local de
-- ReplicatedStorage.VT65WeaponArt). Pinta só as peças com nome de Skins.PART_CLASS:
--   - MeshPart com SurfaceAppearance: AlphaMode TintMask e MeshPart.Color (a cor tinge onde o alfa
--     do mapa de cor manda). Sem skin, a peça que já veio em TintMask recebe a cor padrão;
--   - Part (arma provisória): Color e, no guarda-mão com fita, o material Fabric.
-- A cor e o material originais ficam em atributos da peça (SkinBase*) para voltar ao tirar a skin.
-- O modelo ganha o atributo "Skin" (id ou nil).
-- D-179: SurfaceAppearance pronta de cada acabamento (o arquivo do place traz; script não muda o
-- ColorMap). nil no Lune ou sem a pasta.
local function saPronta(chave: string): Instance?
	local ok, f = pcall(function(): any
		return (game :: any):GetService("ReplicatedStorage"):FindFirstChild("VT65AcabamentosSA")
	end)
	return if ok and f then f:FindFirstChild(chave) else nil
end

-- weaponId: a arma do modelo (o acabamento universal tem uma textura por arma). Sem ele, o
-- atributo "WeaponId" do modelo ou o nome (as cópias de VT65WeaponArt têm o nome da arma).
function Skins.applyWeapon(model: Instance, skinId: string?, weaponId: string?)
	local found = if skinId then Skins.get(skinId) else nil
	local skin: Skin? = if found and found.kind == "weapon" then found else nil
	local arma = weaponId or model:GetAttribute("WeaponId") or model.Name
	local chave: string? = nil
	if skin then
		chave = if skin.universal then skin.id .. "@" .. tostring(arma) else skin.id
	end
	-- D-178/D-179: a arte das armas é uma malha só com a textura inteira (SurfaceAppearance), sem
	-- as peças Madeira/Metal. O acabamento põe a SurfaceAppearance pronta dele (a cor nova com o
	-- relevo e o material) ou, sem ela, troca o TextureID; a original fica guardada numa pasta da
	-- peça para voltar ao tirar a skin.
	local pronta = if chave then saPronta(chave) else nil
	local tex = if chave then AcabamentosArte[chave] else nil
	local temTex = type(tex) == "number" and tex ~= 0
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			local sa: Instance? = nil
			for _, c in d:GetChildren() do
				if c:IsA("SurfaceAppearance") and c.Name ~= "VT65SkinSAAtiva" then
					sa = c
					break
				end
			end
			local guarda = d:FindFirstChild("VT65SkinSA")
			local ativa = d:FindFirstChild("VT65SkinSAAtiva")
			if ativa then
				ativa:Destroy()
			end
			if d:GetAttribute("SkinBaseTex") == nil then
				d:SetAttribute("SkinBaseTex", d.TextureID)
			end
			local bt = d:GetAttribute("SkinBaseTex")
			local base = if type(bt) == "string" then bt else ""
			if (pronta or temTex) and (sa or guarda) then
				if sa then
					if not guarda then
						local f = Instance.new("Folder")
						f.Name = "VT65SkinSA"
						f.Parent = d
						guarda = f
					end
					sa.Parent = guarda
				end
				if pronta then
					local c = pronta:Clone()
					c.Name = "VT65SkinSAAtiva"
					c.Parent = d
					d.TextureID = base
				else
					d.TextureID = "rbxassetid://" .. tex
				end
			elseif guarda then
				local g = guarda:FindFirstChildOfClass("SurfaceAppearance")
				if g then
					g.Parent = d
				end
				d.TextureID = base
			end
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cls = Skins.partClass(d.Name)
			if cls then
				local sa = d:FindFirstChildOfClass("SurfaceAppearance")
				if d:GetAttribute("SkinBase") == nil then
					d:SetAttribute("SkinBase", d.Color)
					d:SetAttribute("SkinBaseMat", d.Material.Name)
					if sa then
						d:SetAttribute("SkinBaseAlpha", sa.AlphaMode.Name)
					end
				end
				local rgb, mat = Skins.paintFor(skin, cls)
				local tintArt = sa ~= nil and d:GetAttribute("SkinBaseAlpha") == "TintMask"
				if not rgb and tintArt then
					rgb = Skins.DEFAULT[cls]
				end
				if rgb then
					d.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
					if sa then
						sa.AlphaMode = Enum.AlphaMode.TintMask
					elseif mat then
						d.Material = (Enum.Material :: any)[mat]
					else
						local bm = d:GetAttribute("SkinBaseMat")
						if type(bm) == "string" then
							d.Material = (Enum.Material :: any)[bm]
						end
					end
				else
					local bc = d:GetAttribute("SkinBase")
					if typeof(bc) == "Color3" then
						d.Color = bc
					end
					local bm = d:GetAttribute("SkinBaseMat")
					if type(bm) == "string" and not sa then
						d.Material = (Enum.Material :: any)[bm]
					end
					local ba = d:GetAttribute("SkinBaseAlpha")
					if sa and type(ba) == "string" then
						sa.AlphaMode = (Enum.AlphaMode :: any)[ba]
					end
				end
			end
		end
	end
	model:SetAttribute("Skin", if skin then skin.id else nil)
end

-- ===== camuflagem de mato: malha (tools/ghillie.py) =====
-- Uma MeshPart por parte do corpo R15, com o nome "Ghillie_<parte>" no modelo publicado
-- (AssetIds.Accessories.ghillie). A malha foi feita em volta de uma parte de referência (`ref`,
-- studs: largura, altura, profundidade); o Characters escala cada peça pela parte real do soldado
-- (Size da parte / ref, por eixo) e solda com uma Weld (o C0 balança no cliente).
-- `size` e `offset` são a caixa da peça no espaço da parte (x direita, y cima, z costas).
-- O importador do Roblox gira o GLB 180° em Y (D-58): GHILLIE_YAW desfaz. CONFERIR NO STUDIO.
Skins.GHILLIE_YAW = math.pi
Skins.GHILLIE_TRANSPARENCY = 0.02 -- MeshPart com TextureID só recorta pelo alfa com Transparency > 0
Skins.GHILLIE_TAG = "VT65Ghillie" -- pasta "Camuflagem" do personagem (o cliente acha pelo CollectionService)
export type GhilliePart = { size: { number }, offset: { number }, tris: number }
export type GhillieFit = { ref: { [string]: { number } }, parts: { [string]: GhilliePart }, tris: number }

-- BEGIN GHILLIE (gerado por tools/ghillie.py; não edite à mão)
Skins.GHILLIE = {
	ref = {
		Head = { 1.2, 1.2, 1.2 },
		UpperTorso = { 2, 1.75, 1 },
		LowerTorso = { 2, 0.45, 1 },
		RightUpperArm = { 0.85, 1.2, 0.85 },
		LeftUpperArm = { 0.85, 1.2, 0.85 },
		RightLowerArm = { 0.8, 1.1, 0.8 },
		LeftLowerArm = { 0.8, 1.1, 0.8 },
		RightUpperLeg = { 0.95, 1.3, 0.95 },
		LeftUpperLeg = { 0.95, 1.3, 0.95 },
		RightLowerLeg = { 0.85, 1.3, 0.85 },
		LeftLowerLeg = { 0.85, 1.3, 0.85 },
	},
	parts = {
		Head = { size = { 1.978, 1.423, 1.34 }, offset = { -0.049, 0.521, 0.302 }, tris = 36 },
		UpperTorso = { size = { 4.089, 4.179, 3.373 }, offset = { 0.013, 0.081, -0.006 }, tris = 600 },
		LowerTorso = { size = { 3.62, 2.284, 2.732 }, offset = { -0.024, 0.021, -0.015 }, tris = 200 },
		RightUpperArm = { size = { 1.825, 2.37, 1.805 }, offset = { 0.084, 0.158, 0.141 }, tris = 80 },
		LeftUpperArm = { size = { 1.781, 2.061, 1.533 }, offset = { -0.151, 0.206, 0.152 }, tris = 80 },
		RightLowerArm = { size = { 1.177, 1.314, 1.537 }, offset = { 0.287, 0.278, 0.185 }, tris = 32 },
		LeftLowerArm = { size = { 1.164, 1.453, 1.254 }, offset = { -0.302, 0.048, 0.022 }, tris = 32 },
		RightUpperLeg = { size = { 2.538, 2.988, 2.68 }, offset = { 0.102, 0.078, -0.029 }, tris = 240 },
		LeftUpperLeg = { size = { 2.487, 2.818, 2.391 }, offset = { -0.154, -0.078, -0.003 }, tris = 240 },
		RightLowerLeg = { size = { 2.054, 2.592, 2.301 }, offset = { 0.118, -0.072, -0.039 }, tris = 180 },
		LeftLowerLeg = { size = { 2.143, 2.8, 2.314 }, offset = { -0.113, -0.077, 0.031 }, tris = 180 },
	},
	tris = 1900,
} :: GhillieFit
-- END GHILLIE

-- ===== balanço das folhas (cliente) =====
-- Ângulos (rad) de balanço do C0 da solda de uma peça: base parada + vento (workspace.GlobalWind, em
-- studs/s). Dois senos fora de fase por peça. PLACEHOLDER de visual.
Skins.SWAY = { baseDeg = 0.8, windDeg = 3.2, fullWind = 25, freq = 2.1 }
function Skins.swayAngles(t: number, phase: number, wind: number): (number, number)
	local c = Skins.SWAY
	local amp = math.rad(c.baseDeg + c.windDeg * math.clamp(wind / c.fullWind, 0, 1))
	return amp * math.sin(t * c.freq + phase), amp * 0.6 * math.sin(t * c.freq * 1.37 + phase * 1.7)
end

return Skins
