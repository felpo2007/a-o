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
	kind: string, -- "emblema" | "plaqueta" | "moldura" | "skin" | "creditos" | "fragmentos"
	raridade: string,
	nome: string,
	nomeEn: string,
	desc: string,
	cor: { number }?, -- cor principal (emblema: fundo; plaqueta: metal; moldura: borda)
	cor2: { number }?, -- cor de detalhe (emblema: letras; plaqueta: borda; moldura: faixa)
	sigla: string?, -- emblema: até 2 letras desenhadas
	vantagem: boolean?,
	quantidade: number?, -- "creditos" / "fragmentos": quanto entra
	exclusivo: string?, -- D-175: "arquivo" = só pela coleção completa (fora das caixas e da compra)
	-- D-176: "passe" = só pelo conjunto em Game Pass `passe` (Shared/Conjuntos)
	passe: string?,
}

-- D-174: prêmios que não são cosméticos (só nas caixas grátis): créditos ($) e Fragmentos.
-- Nunca contam como repetidos e não entram na troca nem na compra direta.
local PREMIOS: { Item } = {
	{
		id = "cr_500",
		kind = "creditos",
		raridade = "comum",
		nome = "$ 500 em créditos",
		nomeEn = "$500 in credits",
		desc = "Créditos ganhos jogando, para compras garantidas.",
		quantidade = 500,
	},
	{
		id = "cr_1500",
		kind = "creditos",
		raridade = "incomum",
		nome = "$ 1.500 em créditos",
		nomeEn = "$1,500 in credits",
		desc = "Créditos ganhos jogando, para compras garantidas.",
		quantidade = 1500,
	},
	{
		id = "frag_100",
		kind = "fragmentos",
		raridade = "raro",
		nome = "100 Fragmentos de Arsenal",
		nomeEn = "100 Arsenal Fragments",
		desc = "Trocam por item garantido.",
		quantidade = 100,
	},
	{
		id = "frag_250",
		kind = "fragmentos",
		raridade = "raro",
		nome = "250 Fragmentos de Arsenal",
		nomeEn = "250 Arsenal Fragments",
		desc = "Trocam por item garantido.",
		quantidade = 250,
	},
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
	-- ===== D-175: exclusivos do ARQUIVO MILITAR (só pela coleção completa; Shared/Arquivo) =====
	{
		id = "tag_carta",
		kind = "plaqueta",
		raridade = "raro",
		nome = "Plaqueta: carta dos objetivos",
		nomeEn = "Dog tag: objectives map",
		desc = "Papel de carta plastificado com as cinco letras dos objetivos.",
		cor = { 214, 202, 168 },
		cor2 = { 70, 96, 140 },
		exclusivo = "arquivo",
	},
	{
		id = "emb_operacao",
		kind = "emblema",
		raridade = "epico",
		nome = "Emblema: Operação",
		nomeEn = "Emblem: Operation",
		desc = "A seta do desembarque na praia de Van Tuong.",
		cor = { 54, 72, 60 },
		cor2 = { 226, 200, 130 },
		sigla = "OP",
		exclusivo = "arquivo",
	},
	{
		id = "mol_identidade",
		kind = "moldura",
		raridade = "epico",
		nome = "Moldura: identidade",
		nomeEn = "Frame: identity",
		desc = "Corrente de bolinhas nos quatro cantos.",
		cor = { 150, 152, 148 },
		cor2 = { 226, 188, 96 },
		exclusivo = "arquivo",
	},
	{
		id = "emb_arquivo",
		kind = "emblema",
		raridade = "epico",
		nome = "Emblema: Arquivo",
		nomeEn = "Emblem: Archive",
		desc = "O carimbo vermelho do arquivo militar.",
		cor = { 120, 40, 34 },
		cor2 = { 236, 220, 180 },
		sigla = "AQ",
		exclusivo = "arquivo",
	},
	{
		id = "mol_arsenal_us",
		kind = "moldura",
		raridade = "epico",
		nome = "Moldura: arsenal dos fuzileiros",
		nomeEn = "Frame: Marines' armory",
		desc = "Madeira de coronha com a faixa azul dos EUA.",
		cor = { 92, 74, 52 },
		cor2 = { 86, 120, 186 },
		exclusivo = "arquivo",
	},
	{
		id = "mol_arsenal_vc",
		kind = "moldura",
		raridade = "epico",
		nome = "Moldura: arsenal da Frente",
		nomeEn = "Frame: Front's armory",
		desc = "Aço oxidado com a faixa vermelha da Frente.",
		cor = { 66, 62, 58 },
		cor2 = { 190, 64, 48 },
		exclusivo = "arquivo",
	},
	{
		id = "tag_fardas_us",
		kind = "plaqueta",
		raridade = "lendario",
		nome = "Plaqueta: fardas dos fuzileiros",
		nomeEn = "Dog tag: Marines' uniforms",
		desc = "Latão com a borda em verde-oliva de campo.",
		cor = { 204, 172, 100 },
		cor2 = { 64, 80, 52 },
		exclusivo = "arquivo",
	},
	{
		id = "tag_fardas_vc",
		kind = "plaqueta",
		raridade = "lendario",
		nome = "Plaqueta: fardas da Frente",
		nomeEn = "Dog tag: Front's uniforms",
		desc = "Alumínio com a borda preta do pijama de campo.",
		cor = { 200, 202, 200 },
		cor2 = { 30, 30, 30 },
		exclusivo = "arquivo",
	},
	{
		id = "mol_arquivo",
		kind = "moldura",
		raridade = "lendario",
		nome = "Moldura: Arquivo Militar",
		nomeEn = "Frame: Military Archive",
		desc = "A pasta do arquivo com o carimbo vermelho: todas as coleções completas.",
		cor = { 196, 170, 120 },
		cor2 = { 150, 40, 34 },
		exclusivo = "arquivo",
	},
	-- ===== D-176: conjunto "Identidade Militar" (Game Pass PASS_SET_IDENTIDADE) =====
	{
		id = "tag_cobre",
		kind = "plaqueta",
		raridade = "raro",
		nome = "Plaqueta: cobre",
		nomeEn = "Dog tag: copper",
		desc = "Cobre batido, escurecido nas bordas.",
		cor = { 184, 116, 74 },
		cor2 = { 118, 70, 42 },
		exclusivo = "passe",
		passe = "PASS_SET_IDENTIDADE",
	},
	{
		id = "tag_enegrecida",
		kind = "plaqueta",
		raridade = "raro",
		nome = "Plaqueta: aço enegrecido",
		nomeEn = "Dog tag: blackened steel",
		desc = "Aço escurecido para não brilhar na patrulha noturna.",
		cor = { 62, 64, 66 },
		cor2 = { 150, 152, 150 },
		exclusivo = "passe",
		passe = "PASS_SET_IDENTIDADE",
	},
	{
		id = "emb_bussola",
		kind = "emblema",
		raridade = "raro",
		nome = "Emblema: Bússola",
		nomeEn = "Emblem: Compass",
		desc = "O norte da carta de campanha.",
		cor = { 46, 70, 84 },
		cor2 = { 226, 214, 170 },
		sigla = "N",
		exclusivo = "passe",
		passe = "PASS_SET_IDENTIDADE",
	},
	{
		id = "emb_sinalizador",
		kind = "emblema",
		raridade = "epico",
		nome = "Emblema: Sinalizador",
		nomeEn = "Emblem: Flare",
		desc = "A luz do sinalizador sobre a mata à noite.",
		cor = { 90, 40, 30 },
		cor2 = { 240, 190, 90 },
		sigla = "SN",
		exclusivo = "passe",
		passe = "PASS_SET_IDENTIDADE",
	},
	{
		id = "mol_cordao",
		kind = "moldura",
		raridade = "raro",
		nome = "Moldura: cordão de paraquedas",
		nomeEn = "Frame: parachute cord",
		desc = "Cordão trançado verde-oliva nas bordas.",
		cor = { 110, 106, 80 },
		cor2 = { 200, 190, 150 },
		exclusivo = "passe",
		passe = "PASS_SET_IDENTIDADE",
	},
	{
		id = "mol_carimbo",
		kind = "moldura",
		raridade = "epico",
		nome = "Moldura: carimbo de serviço",
		nomeEn = "Frame: service stamp",
		desc = "Papel da ficha de serviço com o carimbo vermelho no canto.",
		cor = { 200, 186, 150 },
		cor2 = { 120, 40, 34 },
		exclusivo = "passe",
		passe = "PASS_SET_IDENTIDADE",
	},
	-- ===== D-176: conjunto "Fundador STARLITE" (Game Pass PASS_SET_FUNDADOR) =====
	{
		id = "emb_fundador",
		kind = "emblema",
		raridade = "lendario",
		nome = "Insígnia de Fundador",
		nomeEn = "Founder Insignia",
		desc = "De quem apoiou o STARLITE no começo. Permanente.",
		cor = { 34, 34, 30 },
		cor2 = { 226, 188, 96 },
		sigla = "FS",
		exclusivo = "passe",
		passe = "PASS_SET_FUNDADOR",
	},
	{
		id = "emb_fundador_65",
		kind = "emblema",
		raridade = "lendario",
		nome = "Emblema: Fundador 1965",
		nomeEn = "Emblem: Founder 1965",
		desc = "O ano da operação em latão sobre o verde-escuro.",
		cor = { 54, 66, 46 },
		cor2 = { 226, 188, 96 },
		sigla = "65",
		exclusivo = "passe",
		passe = "PASS_SET_FUNDADOR",
	},
	{
		id = "tag_fundador",
		kind = "plaqueta",
		raridade = "lendario",
		nome = "Plaqueta: comemorativa de fundador",
		nomeEn = "Dog tag: founder commemorative",
		desc = "Latão polido com a borda escura, só dos fundadores.",
		cor = { 226, 188, 96 },
		cor2 = { 34, 34, 30 },
		exclusivo = "passe",
		passe = "PASS_SET_FUNDADOR",
	},
	{
		id = "mol_fundador",
		kind = "moldura",
		raridade = "lendario",
		nome = "Moldura: Fundador STARLITE",
		nomeEn = "Frame: STARLITE Founder",
		desc = "O cartão exclusivo dos fundadores: preto com a faixa de latão.",
		cor = { 34, 34, 30 },
		cor2 = { 226, 188, 96 },
		exclusivo = "passe",
		passe = "PASS_SET_FUNDADOR",
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
	-- D-176: conjuntos em Game Pass (só pelo passe)
	skin_m14_oleada = "raro",
	skin_m60_fosfato = "raro",
	skin_m1911_marrom = "raro",
	skin_type56_vermelha = "raro",
	skin_sks_clara = "raro",
	skin_rpd_azulado = "epico",
	skin_us_hbt = "epico",
	skin_us_goldtiger = "epico",
	skin_vc_oliva = "epico",
	skin_vc_anil = "epico",
	skin_us_fundador = "lendario",
	skin_vc_fundador = "lendario",
} :: { [string]: string }

local byId: { [string]: Item } = {}
for _, it in ITENS do
	byId[it.id] = it
end
local premios: { [string]: Item } = {}
for _, it in PREMIOS do
	premios[it.id] = it
end
Cosmeticos.PREMIOS = PREMIOS
Cosmeticos.ITENS = ITENS

-- Item de caixa (cosmético ou skin); nil se não existe ou não pode entrar em caixa
function Cosmeticos.info(id: any): Item?
	if type(id) ~= "string" then
		return nil
	end
	local it = byId[id] or premios[id]
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
	if premios[id] then
		return false -- prêmio de quantidade: nunca é repetido
	end
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
	local pr = premios[id]
	if pr then
		if pr.kind == "creditos" then
			p.credits = math.min(p.credits + (pr.quantidade or 0), 1000000000)
		else
			p.caixas.fragmentos = math.min(p.caixas.fragmentos + (pr.quantidade or 0), 1000000)
		end
	elseif byId[id] then
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
