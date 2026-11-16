--!strict
-- Conjuntos em Game Pass (D-176, prompt master definitivo, item 19): quatro passes de compra única,
-- cada um com itens NOVOS e exclusivos, todos só visuais (nenhum muda combate). PURO (Lune:
-- tests/luau/conjuntos.luau).
--   - itens de cartão (emblema, plaqueta, moldura) e o título: o servidor grava a posse no perfil
--     quando vê o passe (CaixaService.conjuntos), para o cartão, o álbum e a escolha verem igual;
--   - skins (uniforme, acabamento): a posse é o próprio passe (Skins.owns, robuxKey = chave do
--     conjunto; `soPasse` tira o $ da Intendência e o Mercado).
-- O pedido também cita capacetes, mochilas, gravações e animações de inspeção: não existem no jogo e
-- não entraram (nada é vendido sem existir).
-- IDs em Commerce.IDS (0 = ainda não criado: o botão some). O preço real vem do Roblox
-- (GetProductInfoAsync); `robux` é a referência do pedido para criar o passe.
local Conjuntos = {}

export type Conjunto = {
	key: string,
	nome: string,
	nomeEn: string,
	desc: string,
	robux: number,
	itens: { string }, -- ids (Cosmeticos, Skins) e títulos ("tit_*")
}

Conjuntos.LISTA = {
	{
		key = "PASS_SET_IDENTIDADE",
		nome = "Identidade Militar",
		nomeEn = "Military Identity",
		desc = "2 plaquetas, 2 emblemas e 2 molduras para o cartão. Só visual, permanente.",
		robux = 49,
		itens = { "tag_cobre", "tag_enegrecida", "emb_bussola", "emb_sinalizador", "mol_cordao", "mol_carimbo" },
	},
	{
		key = "PASS_SET_UNIFORMES",
		nome = "Uniformes Históricos",
		nomeEn = "Historical Uniforms",
		desc = "4 uniformes novos: HBT verde-sálvia e tigrado dourado (EUA), áo bà ba verde-oliva e anil (Frente). Só visual, permanente.",
		robux = 99,
		itens = { "skin_us_hbt", "skin_us_goldtiger", "skin_vc_oliva", "skin_vc_anil" },
	},
	{
		key = "PASS_SET_ARMAS",
		nome = "Personalização de Armas",
		nomeEn = "Weapon Customization",
		desc = "6 acabamentos novos: M14, M60, M1911A1, Tipo 56, SKS e RPD. Só visual, permanente.",
		robux = 149,
		itens = {
			"skin_m14_oleada",
			"skin_m60_fosfato",
			"skin_m1911_marrom",
			"skin_type56_vermelha",
			"skin_sks_clara",
			"skin_rpd_azulado",
		},
	},
	{
		key = "PASS_SET_FUNDADOR",
		nome = "Fundador STARLITE",
		nomeEn = "STARLITE Founder",
		desc = "Uniforme de fundador nos dois lados, insígnia e emblema, plaqueta comemorativa, cartão exclusivo e o título Fundador no perfil. Só visual, permanente.",
		robux = 499,
		itens = {
			"skin_us_fundador",
			"skin_vc_fundador",
			"emb_fundador",
			"emb_fundador_65",
			"tag_fundador",
			"mol_fundador",
			"tit_fundador",
		},
	},
} :: { Conjunto }

Conjuntos.TITULOS = { tit_fundador = "Fundador STARLITE" } :: { [string]: string }

local byKey: { [string]: Conjunto } = {}
local byItem: { [string]: string } = {}
for _, c in Conjuntos.LISTA do
	byKey[c.key] = c
	for _, id in c.itens do
		byItem[id] = c.key
	end
end

function Conjuntos.get(key: any): Conjunto?
	return if type(key) == "string" then byKey[key] else nil
end

-- o conjunto (chave do Game Pass) de um item, ou nil
function Conjuntos.doItem(id: any): string?
	return if type(id) == "string" then byItem[id] else nil
end

-- itens que o servidor grava no perfil (campaign.owned) para quem tem o passe: os do cartão e os
-- títulos; as skins valem pelo passe
function Conjuntos.paraGravar(key: string): { string }
	local c = byKey[key]
	local out = {}
	if c then
		for _, id in c.itens do
			local pre = string.sub(id, 1, 4)
			if pre == "emb_" or pre == "tag_" or pre == "mol_" or pre == "tit_" then
				table.insert(out, id)
			end
		end
	end
	return out
end

return Conjuntos
