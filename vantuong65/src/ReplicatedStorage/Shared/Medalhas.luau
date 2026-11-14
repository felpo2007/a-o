--!strict
-- Medalhas históricas e cartão do jogador (plano de volta diária, 2026-11-12, seção 4). Cada
-- medalha tem uma condição de jogo sobre os contadores do perfil (campaign.stats). Aparecem no
-- cartão do jogador (até 3), no lobby e no relatório. Nomes históricos de 1965: as dos EUA são
-- condecorações reais; as do lado vietnamita seguem as ordens do Exército de Libertação (nomes em
-- português, com o original na descrição). Puro, testado no Lune (tests/luau/campanha.luau).
local Medalhas = {}

export type Def = {
	id: string,
	name: string,
	desc: string, -- condição, frase inteira
	stat: string, -- contador em campaign.stats
	goal: number,
}

Medalhas.LIST = {
	{
		id = "purple_heart",
		name = "Purple Heart",
		desc = "Ferido em combate, reanimado e de volta à luta.",
		stat = "wasRevived",
		goal = 1,
	},
	{
		id = "combat_action",
		name = "Fita de Ação de Combate",
		desc = "Jogar 10 partidas até o fim.",
		stat = "matches",
		goal = 10,
	},
	{
		id = "bronze_star",
		name = "Bronze Star",
		desc = "100 abates.",
		stat = "kills",
		goal = 100,
	},
	{
		id = "navy_cross",
		name = "Navy Cross",
		desc = "Capturar 25 setores.",
		stat = "captures",
		goal = 25,
	},
	{
		id = "socorro",
		name = "Medalha de Socorro",
		desc = "Reanimar 25 companheiros.",
		stat = "revives",
		goal = 25,
	},
	{
		id = "heroi_libertacao",
		name = "Medalha de Herói (VC)",
		desc = "Vencer 10 partidas pelo VC (Huân chương Chiến sĩ Giải phóng).",
		stat = "winsVC",
		goal = 10,
	},
	{
		id = "unit_citation",
		name = "Citação de Unidade (EUA)",
		desc = "Vencer 10 partidas pelos EUA.",
		stat = "winsUS",
		goal = 10,
	},
	{
		id = "irmaos",
		name = "Irmãos de Armas",
		desc = "Jogar 5 partidas com um amigo no squad.",
		stat = "friendMatches",
		goal = 5,
	},
	{
		id = "ordem_cumprida",
		name = "Ordem Cumprida",
		desc = "Cumprir 10 ordens do comandante com o squad.",
		stat = "orders",
		goal = 10,
	},
	{
		id = "top10",
		name = "Placar da Semana",
		desc = "Terminar uma semana entre os 10 melhores do placar.",
		stat = "top10",
		goal = 1,
	},
} :: { Def }

-- contadores que o servidor soma (campaign.stats)
Medalhas.STATS = {
	"kills",
	"assists",
	"captures",
	"revives",
	"wasRevived",
	"matches",
	"wins",
	"winsUS",
	"winsVC",
	"friendMatches",
	"orders",
	"top10",
}

local byId: { [string]: Def } = {}
for _, m in Medalhas.LIST do
	byId[m.id] = m
end

function Medalhas.get(id: string): Def?
	return byId[id]
end

-- medalhas que os contadores já merecem e que ainda não estão em `have`
function Medalhas.earned(stats: { [string]: number }, have: { [string]: number }): { string }
	local out = {}
	for _, m in Medalhas.LIST do
		if not have[m.id] and (stats[m.stat] or 0) >= m.goal then
			table.insert(out, m.id)
		end
	end
	return out
end

-- ===== cartão do jogador =====
Medalhas.DEFAULT_EMBLEM = "emb_padrao"
Medalhas.DEFAULT_TITLE = "tit_soldado"
-- emblemas e títulos de todo mundo (os outros vêm do passe e do placar: campaign.owned)
Medalhas.BASE_OWNED = { emb_padrao = true, tit_soldado = true } :: { [string]: boolean }
Medalhas.NAMES = {
	emb_padrao = "Emblema: Operação Starlite",
	tit_soldado = "Soldado",
	emb_top10 = "Emblema: Placar da Semana",
} :: { [string]: string }

export type Card = { emblem: string, title: string, medals: { string } }

-- confere um pedido de cartão: só o que a pessoa tem (emblema e título em owned, até 3 medalhas
-- ganhas, sem repetir)
function Medalhas.validCard(c: any, owned: { [string]: boolean }, medals: { [string]: number }): Card?
	if type(c) ~= "table" then
		return nil
	end
	local emblem, title = c.emblem, c.title
	if type(emblem) ~= "string" or not (owned[emblem] or Medalhas.BASE_OWNED[emblem]) then
		return nil
	end
	if string.sub(emblem, 1, 4) ~= "emb_" then
		return nil
	end
	if type(title) ~= "string" or not (owned[title] or Medalhas.BASE_OWNED[title]) then
		return nil
	end
	if string.sub(title, 1, 4) ~= "tit_" then
		return nil
	end
	local list: { string } = {}
	if type(c.medals) == "table" then
		for _, id in c.medals do
			if type(id) == "string" and medals[id] and not table.find(list, id) and #list < 3 then
				table.insert(list, id)
			end
		end
	end
	return { emblem = emblem, title = title, medals = list }
end

return Medalhas
