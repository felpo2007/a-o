--!strict
-- Cosméticos das caixas e da troca de Fragmentos (D-173). PURO (testado no Lune: caixas.luau).
--   - emblema (emb_*): o do cartão do jogador (Medalhas/CartaoJogador); vai para campaign.owned;
--   - plaqueta (tag_*): a plaqueta de identificação no cartão, com o nome do jogador gravado;
--   - moldura (mol_*): a borda e a faixa do cartão;
--   - skins (skin_*): acabamentos de arma e uniformes de Shared/Skins (posse em skins.owned ou
--     Game Pass). A camuflagem de mato NUNCA entra: dá vantagem contra os bots.
-- Tudo só visual. Desenhos originais, a partir dos lugares do mapa (nada de insígnia real de
-- unidade militar).
-- A raridade é do ITEM (a mesma em toda caixa e na troca).
local Skins = require(script and (script :: any).Parent.Skins or "./Skins") :: any

local Cosmeticos = {}

export type Item = {
	id: string,
	kind: string, -- "emblema" | "plaqueta" | "moldura" | "skin"
	raridade: string,
	nome: string,
	nomeEn: string,
	desc: string,
	cor: { number }?, -- cor principal (emblema: fundo; plaqueta: metal; moldura: borda)
	cor2: { number }?, -- cor de detalhe (emblema: letras; plaqueta: borda; moldura: faixa)
	sigla: string?, -- emblema: até 2 letras desenhadas
	vantagem: boolean?,
}

local ITENS: { Item } = {
	-- ===== emblemas =====
	{
		id = "emb_arrozais",
		kind = "emblema",
		raridade = "comum",
		nome = "Emblema: Arrozais",
		nomeEn = "Emblem: Rice Paddies",
		desc = "Os diques do objetivo A.",
		cor = { 92, 120, 64 },
		cor2 = { 230, 220, 170 },
		sigla = "A",
	},
	{
		id = "emb_serraria",
		kind = "emblema",
		raridade = "comum",
		nome = "Emblema: Serraria",
		nomeEn = "Emblem: Sawmill",
		desc = "O galpão na mata fechada, objetivo B.",
		cor = { 110, 80, 52 },
		cor2 = { 236, 214, 170 },
		sigla = "B",
	},
	{
		id = "emb_ponte",
		kind = "emblema",
		raridade = "comum",
		nome = "Emblema: Ponte e Cais",
		nomeEn = "Emblem: Bridge and Pier",
		desc = "A ponte do rio do sul, objetivo D.",
		cor = { 62, 96, 130 },
		cor2 = { 226, 230, 220 },
		sigla = "D",
	},
	{
		id = "emb_engenho",
		kind = "emblema",
		raridade = "comum",
		nome = "Emblema: Engenho",
		nomeEn = "Emblem: Sugar Mill",
		desc = "A moenda do objetivo E.",
		cor = { 128, 96, 60 },
		cor2 = { 240, 226, 190 },
		sigla = "E",
	},
	{
		id = "emb_xomgo",
		kind = "emblema",
		raridade = "incomum",
		nome = "Emblema: Xóm Gò",
		nomeEn = "Emblem: Xóm Gò",
		desc = "A vila no morro do centro, objetivo C.",
		cor = { 150, 64, 48 },
		cor2 = { 244, 226, 196 },
		sigla = "XG",
	},
	{
		id = "emb_starlite",
		kind = "emblema",
		raridade = "raro",
		nome = "Emblema: Starlite",
		nomeEn = "Emblem: Starlite",
		desc = "18 de agosto de 1965: o primeiro dia da operação.",
		cor = { 40, 52, 70 },
		cor2 = { 214, 190, 120 },
		sigla = "18",
	},
	{
		id = "emb_chulai",
		kind = "emblema",
		raridade = "epico",
		nome = "Emblema: Chu Lai",
		nomeEn = "Emblem: Chu Lai",
		desc = "A base de onde a operação partiu.",
		cor = { 70, 46, 96 },
		cor2 = { 230, 200, 140 },
		sigla = "CL",
	},
	-- ===== plaquetas =====
	{
		id = "tag_aco",
		kind = "plaqueta",
		raridade = "comum",
		nome = "Plaqueta: aço",
		nomeEn = "Dog tag: steel",
		desc = "Aço inoxidável, cantos arredondados.",
		cor = { 176, 180, 182 },
		cor2 = { 96, 100, 104 },
	},
	{
		id = "tag_aluminio",
		kind = "plaqueta",
		raridade = "comum",
		nome = "Plaqueta: alumínio",
		nomeEn = "Dog tag: aluminium",
		desc = "Leve e fosca.",
		cor = { 196, 198, 196 },
		cor2 = { 132, 134, 132 },
	},
	{
		id = "tag_borracha",
		kind = "plaqueta",
		raridade = "comum",
		nome = "Plaqueta: com silenciador",
		nomeEn = "Dog tag: with silencer",
		desc = "A borda de borracha preta que não tilinta na patrulha.",
		cor = { 168, 170, 170 },
		cor2 = { 28, 28, 28 },
	},
	{
		id = "tag_corrente",
		kind = "plaqueta",
		raridade = "comum",
		nome = "Plaqueta: corrente de bolinhas",
		nomeEn = "Dog tag: ball chain",
		desc = "Na corrente de bolinhas, escurecida pelo uso.",
		cor = { 150, 152, 148 },
		cor2 = { 70, 72, 70 },
	},
	{
		id = "tag_latao",
		kind = "plaqueta",
		raridade = "incomum",
		nome = "Plaqueta: latão",
		nomeEn = "Dog tag: brass",
		desc = "Latão escovado.",
		cor = { 196, 160, 88 },
		cor2 = { 120, 92, 44 },
	},
	{
		id = "tag_gravada",
		kind = "plaqueta",
		raridade = "lendario",
		nome = "Plaqueta: latão polido gravado",
		nomeEn = "Dog tag: engraved polished brass",
		desc = "Latão polido com o nome gravado à mão e o contorno em relevo.",
		cor = { 226, 188, 96 },
		cor2 = { 150, 110, 40 },
	},
	-- ===== molduras do cartão =====
	{
		id = "mol_lona",
		kind = "moldura",
		raridade = "comum",
		nome = "Moldura: lona",
		nomeEn = "Frame: canvas",
		desc = "Lona verde-oliva com costura.",
		cor = { 96, 104, 70 },
		cor2 = { 132, 140, 98 },
	},
	{
		id = "mol_caixote",
		kind = "moldura",
		raridade = "comum",
		nome = "Moldura: caixote",
		nomeEn = "Frame: supply crate",
		desc = "Madeira de caixote de munição.",
		cor = { 120, 92, 60 },
		cor2 = { 160, 128, 84 },
	},
	{
		id = "mol_mapa",
		kind = "moldura",
		raridade = "incomum",
		nome = "Moldura: carta de operações",
		nomeEn = "Frame: operations map",
		desc = "O papel da carta com a quadrícula azul.",
		cor = { 214, 202, 168 },
		cor2 = { 70, 96, 140 },
	},
	{
		id = "mol_latao",
		kind = "moldura",
		raridade = "raro",
		nome = "Moldura: latão",
		nomeEn = "Frame: brass",
		desc = "Cantoneiras de latão escovado.",
		cor = { 190, 156, 86 },
		cor2 = { 120, 94, 50 },
	},
	{
		id = "mol_noite",
		kind = "moldura",
		raridade = "epico",
		nome = "Moldura: patrulha noturna",
		nomeEn = "Frame: night patrol",
		desc = "Azul-noite com o brilho do sinalizador.",
		cor = { 44, 52, 86 },
		cor2 = { 214, 120, 60 },
	},
	{
		id = "mol_starlite",
		kind = "moldura",
		raridade = "lendario",
		nome = "Moldura: Starlite",
		nomeEn = "Frame: Starlite",
		desc = "Aço escovado com as cinco letras dos objetivos em latão.",
		cor = { 150, 156, 160 },
		cor2 = { 214, 172, 64 },
	},
}

-- raridade dos acabamentos e uniformes (a camuflagem de mato fica de fora: vantagem)
Cosmeticos.RARIDADE_SKIN = {
	skin_m14_birch = "incomum",
	skin_type56_birch = "incomum",
	skin_m79_walnut = "incomum",
	skin_rpd_worn = "incomum",
	skin_m60_worn = "incomum",
	skin_sks_worn = "incomum",
	skin_m14_worn = "raro",
	skin_sks_walnut = "raro",
	skin_m1911_blued = "raro",
	skin_type54_worn = "raro",
	skin_m14_tape = "raro",
	skin_type56_tape = "raro",
	skin_m79_od = "raro",
	skin_type56_blued = "raro",
	skin_rpg2_od = "raro",
	skin_m60_od = "epico",
	skin_rpd_birch = "epico",
	skin_us_faded = "epico",
	skin_us_duck = "epico",
	skin_vc_black = "epico",
	skin_vc_brown = "epico",
	skin_us_tadpole = "epico",
	skin_us_lizard = "epico",
	skin_us_tiger = "lendario",
	skin_vc_tiger = "lendario",
} :: { [string]: string }

local byId: { [string]: Item } = {}
for _, it in ITENS do
	byId[it.id] = it
end
Cosmeticos.ITENS = ITENS

-- Item de caixa (cosmético ou skin); nil se não existe ou não pode entrar em caixa
function Cosmeticos.info(id: any): Item?
	if type(id) ~= "string" then
		return nil
	end
	local it = byId[id]
	if it then
		return it
	end
	local r = Cosmeticos.RARIDADE_SKIN[id]
	local s = Skins.get(id)
	if r and s then
		return {
			id = id,
			kind = "skin",
			raridade = r,
			nome = s.name,
			nomeEn = s.name,
			desc = s.desc,
			vantagem = s.kind == "camo",
		}
	end
	return nil
end

-- Posse: cosméticos em campaign.owned; skins em skins.owned ou por Game Pass (`passes`: chave do
-- Skins.IDS -> true)
function Cosmeticos.possui(
	id: string,
	campaignOwned: { [string]: boolean }?,
	skinsOwned: { [string]: boolean }?,
	passes: { [string]: boolean }?
): boolean
	if byId[id] then
		return campaignOwned ~= nil and campaignOwned[id] == true
	end
	local s = Skins.get(id)
	if s then
		local ok = Skins.owns(s, skinsOwned, passes)
		return ok == true
	end
	return false
end

-- concede (no perfil já carregado): cosmético em campaign.owned, skin em skins.owned
function Cosmeticos.conceder(p: any, id: string)
	if byId[id] then
		p.campaign.owned[id] = true
	elseif Skins.get(id) then
		p.skins.owned[id] = true
	else
		error("item desconhecido " .. id)
	end
end

-- nomes para o cartão (Medalhas.NAMES / CartaoJogador)
function Cosmeticos.nomes(): { [string]: string }
	local t = {}
	for _, it in ITENS do
		t[it.id] = it.nome
	end
	return t
end

return Cosmeticos
