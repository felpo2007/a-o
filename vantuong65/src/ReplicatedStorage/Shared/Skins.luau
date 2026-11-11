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
	PRODUCT_SKIN_M14_BIRCH = 0,
	PRODUCT_SKIN_M14_TAPE = 0,
	PRODUCT_SKIN_M14_WORN = 0,
	PRODUCT_SKIN_M60_OD = 0,
	PRODUCT_SKIN_M60_WORN = 0,
	PRODUCT_SKIN_M79_WALNUT = 0,
	PRODUCT_SKIN_M79_OD = 0,
	PRODUCT_SKIN_M1911_BLUED = 0,
	-- armas VC
	PRODUCT_SKIN_TYPE56_BIRCH = 0,
	PRODUCT_SKIN_TYPE56_BLUED = 0,
	PRODUCT_SKIN_TYPE56_TAPE = 0,
	PRODUCT_SKIN_SKS_WALNUT = 0,
	PRODUCT_SKIN_SKS_WORN = 0,
	PRODUCT_SKIN_RPD_BIRCH = 0,
	PRODUCT_SKIN_RPD_WORN = 0,
	PRODUCT_SKIN_TYPE54_WORN = 0,
	PRODUCT_SKIN_RPG2_OD = 0,
	-- uniformes
	PASS_SKIN_US_FADED = 0,
	PASS_SKIN_US_TIGER = 0,
	PASS_SKIN_US_DUCK = 0,
	PASS_SKIN_VC_BLACK = 0,
	-- camuflagem de mato
	PASS_CAMO_RICE = 0,
	PASS_CAMO_JUNGLE = 0,
	PASS_CAMO_BAMBOO = 0,
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
	camo: string?, -- camuflagem: "rice" | "jungle" | "bamboo" (atributo "Camo", BotBrain)
	texture: string?, -- camuflagem: chave da textura em AssetIds.Images
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
local function uniform(
	id: string,
	side: string,
	key: string,
	name: string,
	desc: string,
	swatch: { { number } },
	shirt: string?,
	pants: string?,
	gearUniform: string?
): Skin
	local s = base(id, "uniform", side, "uniform", key, name, desc)
	s.swatch = swatch
	s.shirt = shirt
	s.pants = pants
	s.gearUniform = gearUniform
	s.rgb = { shirt = swatch[1], pants = swatch[1] }
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
			nil
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
			nil
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

local byId: { [string]: Skin } = {}
for _, s in Skins.CATALOG do
	byId[s.id] = s
end

-- ===== consulta =====
function Skins.get(id: any): Skin?
	return if type(id) == "string" then byId[id] else nil
end

-- encaixe onde a skin fica equipada: id da arma, "uniform" ou "camo"
function Skins.slotOf(s: Skin): string
	return if s.kind == "weapon" then s.weapon or "?" else s.kind
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
	elseif money < s.price then
		return false, "faltam " .. Progression.money(s.price - money)
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
		if s and Skins.slotOf(s) == slot and Skins.canEquip(id, faction, owned, passes) then
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
		if s and s.kind == "weapon" and s.weapon == slot then
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
		if s and s.kind == "weapon" and s.weapon == slot then
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
function Skins.applyWeapon(model: Instance, skinId: string?)
	local found = if skinId then Skins.get(skinId) else nil
	local skin: Skin? = if found and found.kind == "weapon" then found else nil
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
