--!strict
-- D-222 (dono: "quero imagens, o jogo tem que ser visual"): as imagens de catálogo renderizadas no
-- Blender (tools/blender/armas_catalogo.py) e as fotos dos lugares do mapa. Os IDs ficam em
-- AssetIds.Catalogo; sem o ID devolve "" e quem desenha mostra o nome.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any

local ArteCatalogo = {}

local function url(chave: string): string
	local id = (AssetIds.Catalogo or {})[chave]
	return if type(id) == "number" and id ~= 0 then string.format("rbxassetid://%d", id) else ""
end

local function capa(nome: string): string
	local id = (AssetIds.Capas or {})[nome]
	return if type(id) == "number" and id ~= 0 then string.format("rbxassetid://%d", id) else ""
end

function ArteCatalogo.arma(id: string): string
	return url("arma_" .. id)
end

function ArteCatalogo.equip(id: string): string
	return url("equip_" .. id)
end

function ArteCatalogo.classe(id: string): string
	return url("classe_" .. id)
end

function ArteCatalogo.time(f: string): string
	return url("time_" .. string.lower(f))
end

-- a imagem do carregador certo para a arma (o item "Carregadores" do equipamento)
ArteCatalogo.MUNICAO = {
	rifle = "mag_rifle",
	mg = "belt_mg",
	pistol = "mag_pistol",
	launcher = "grenade40",
	shotgun = "shells",
} :: { [string]: string }

-- a imagem de cada item do equipamento (Shared/Kit), pelo lado e pelo tipo da arma
function ArteCatalogo.itemKit(item: string, faction: string, kind: string): string
	if item == "mags" then
		return ArteCatalogo.equip(ArteCatalogo.MUNICAO[kind] or "mag_rifle")
	elseif item == "frags" then
		return ArteCatalogo.equip(if faction == "VC" then "frag_vc" else "frag_us")
	elseif item == "smokes" then
		return ArteCatalogo.equip("smoke")
	end
	return ArteCatalogo.equip("bandage")
end

-- D-229: a imagem de um acabamento de arma (tools/blender/skins_catalogo.py). O universal tem uma por
-- arma; sem `arma`, a da vitrine dele
function ArteCatalogo.acabamento(skin: any, arma: string?): string
	if type(skin) ~= "table" or type(skin.id) ~= "string" then
		return ""
	end
	if skin.universal then
		local w = arma or skin.vitrine
		return if type(w) == "string" then url(string.format("acab_%s__%s", skin.id, w)) else ""
	end
	return url("acab_" .. skin.id)
end

-- D-227: a imagem de cada ordem do dia, pelo id sem o prefixo do escopo (d_, w_)
local ORDEM = {
	kills = "arma_m14",
	kills_rifle = "arma_m16",
	kills_mg = "arma_m60",
	assists = "equip_binoculars",
	capture = "premio_bandeira",
	revive = "premio_maleta",
	treat = "equip_bandage",
	sector = "equip_shovel_us",
	matches = "equip_radio",
	win = "premio_medalha",
	wins = "premio_medalha",
	friend = "equip_radio",
	field = "premio_relogio",
} :: { [string]: string }
function ArteCatalogo.ordem(id: string?): string
	local curto = string.gsub(id or "", "^[dw]_", "")
	local img = url(ORDEM[curto] or "equip_radio")
	return if img ~= "" then img else url("equip_radio")
end

-- D-226: a imagem de um prêmio do passe que não é um item de verdade (sem ela, o ItemArte desenha)
local PREMIO = {
	credits = "premio_creditos",
	boost = "premio_reforco",
	music = "premio_disco",
	gesture = "premio_gesto",
	killcard = "premio_cartao",
	stars = "premio_estrelas",
} :: { [string]: string }
function ArteCatalogo.premio(kind: string?): string
	local k = PREMIO[kind or ""]
	return if k then url(k) else ""
end

-- D-239: a imagem de um visual do Armário ou de uma camuflagem (tools/blender/visuais_catalogo.py).
-- "Sem acessório" e "sem cobertura" dividem o cabide vazio; as duas fitas da Reserva, a mesma medalha.
local VISUAL_IGUAL = {
	us_none = "nada",
	vc_none = "nada",
	vc_bare = "nada",
	us_ribbon_reserve = "ribbon",
	vc_ribbon_reserve = "ribbon",
} :: { [string]: string }
function ArteCatalogo.visual(id: string?): string
	if type(id) ~= "string" then
		return ""
	end
	return url("vis_" .. (VISUAL_IGUAL[id] or id))
end

-- D-239: a imagem de cada oferta da loja (antes as vantagens usavam todas o mesmo ícone do passe)
local OFERTA = {
	PASS_PERK_SPEED = "vis_perk_speed",
	PASS_PERK_HEALTH = "vis_perk_health",
	PASS_PERK_BREATH = "vis_perk_breath",
	PASS_PERK_RELOAD = "equip_mag_rifle",
	PASS_PERK_MEDIC = "equip_bandage",
	PASS_PERK_POCKETS = "vis_perk_pockets",
	PASS_PERK_EAGLE = "equip_binoculars",
	PASS_PERK_ALL = "vis_perk_all",
	PASS_UNIT = "premio_bandeira",
	PASS_SUPPORTER = "premio_medalha",
	PASS_KIT_VETERAN = "equip_ammo_box",
	PASS_SEASON_S1 = "premio_estrelas",
	PASS_RECRUIT = "premio_maleta",
	PRODUCT_TIP_SMALL = "premio_creditos",
	PRODUCT_TIP_LARGE = "premio_creditos",
	PRODUCT_RESPAWN_INPLACE = "equip_radio",
	PRODUCT_SEASON_SKIP = "premio_estrelas",
	PRODUCT_BOOST_XP_1H = "premio_reforco",
	PRODUCT_BOOST_XP_24H = "premio_reforco",
	PRODUCT_BOOST_CR_1H = "premio_reforco",
	PRODUCT_CREDITS_500 = "premio_creditos",
	PRODUCT_CREDITS_1200 = "premio_creditos",
	PRODUCT_CREDITS_3000 = "premio_creditos",
	sub = "premio_relogio",
	season = "premio_estrelas",
} :: { [string]: string }
function ArteCatalogo.oferta(chave: string?): string
	local k = OFERTA[chave or ""]
	return if k then url(k) else ""
end

-- A foto de um ponto de nascer, pelo nome do lugar (as capas do jogo)
local LUGAR = {
	{ "arroz", "arrozal" },
	{ "serraria", "bambu" },
	{ "vila", "vila" },
	{ "ponte", "riacho" },
	{ "cais", "riacho" },
	{ "engenho", "chuva" },
	{ "reuni", "trincheira" },
	{ "qg", "posto" },
	{ "base", "posto" },
} :: { { string } }
function ArteCatalogo.lugar(nome: string?): string
	local n = string.lower(nome or "")
	for _, par in LUGAR do
		if string.find(n, par[1], 1, true) then
			return capa(par[2])
		end
	end
	return capa("trincheira")
end

return ArteCatalogo
