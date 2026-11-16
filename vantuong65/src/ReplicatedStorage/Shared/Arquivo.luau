--!strict
-- ARQUIVO MILITAR STARLITE (D-175, pedido do dono no prompt master definitivo, item 10): o álbum de
-- todos os cosméticos e as coleções temáticas com recompensa garantida. PURO (Lune:
-- tests/luau/arquivo.luau). O servidor confere a posse e entrega o prêmio
-- (CaixaRegras.resgatarColecao); a tela é Controllers/ArquivoTela.client.
-- Regras do pedido:
--   - cada item mostra nome, modelo, raridade, origem, como conseguir, se o jogador tem, se há
--     compra direta e se dá para conseguir de graça;
--   - nenhuma coleção exige caixa paga: todo item tem um caminho grátis (caixa grátis, troca de
--     Fragmentos, compra direta ou Intendência com os créditos ganhos jogando). O teste cobra;
--   - jogador grátis completa conjuntos próprios e ganha prêmio de verdade: o prêmio de cada coleção
--     é um cosmético EXCLUSIVO (`exclusivo = "arquivo"`: fora das caixas, da troca e da compra),
--     mais Fragmentos e créditos.
-- Categorias do pedido sem item no jogo (capacetes, mochilas, animações de inspeção) não aparecem:
-- nada de vitrine vazia nem item inventado. "Itens históricos de temporada" é a marca de origem da
-- caixa de temporada, não uma categoria.
local Caixas = require(script and (script :: any).Parent.Caixas or "./Caixas") :: any
local Cosmeticos = require(script and (script :: any).Parent.Cosmeticos or "./Cosmeticos") :: any
local Skins = require(script and (script :: any).Parent.Skins or "./Skins") :: any

local Arquivo = {}

Arquivo.MARCO = "arquivo:" -- prefixo do resgate em caixas.marcos (cada coleção resgata uma vez)

export type Categoria = { id: string, nome: string, nomeEn: string }
Arquivo.CATEGORIAS = {
	{ id = "uniformes", nome = "Uniformes", nomeEn = "Uniforms" },
	{ id = "acabamentos", nome = "Acabamentos de arma", nomeEn = "Weapon finishes" },
	{ id = "insignias", nome = "Insígnias", nomeEn = "Insignia" },
	{ id = "plaquetas", nome = "Plaquetas (dog tags)", nomeEn = "Dog tags" },
	{ id = "molduras", nome = "Molduras do cartão", nomeEn = "Card frames" },
} :: { Categoria }

export type Premio = { item: string, fragmentos: number, creditos: number }
export type Colecao = {
	id: string,
	nome: string,
	nomeEn: string,
	desc: string,
	itens: { string }, -- itens que o jogador precisa ter
	colecoes: { string }?, -- ou: coleções que precisam estar completas (a do arquivo inteiro)
	premio: Premio,
}

-- Valores de design (PLACEHOLDER até a telemetria): o prêmio cresce com o tamanho e o custo da
-- coleção. ~300 $ por partida (Skins.MONEY_PER_MATCH).
Arquivo.COLECOES = {
	{
		id = "objetivos",
		nome = "Objetivos da Operação",
		nomeEn = "Objectives of the Operation",
		desc = "Os emblemas dos cinco objetivos do mapa.",
		itens = { "emb_arrozais", "emb_serraria", "emb_xomgo", "emb_ponte", "emb_engenho" },
		premio = { item = "tag_carta", fragmentos = 100, creditos = 0 },
	},
	{
		id = "operacao",
		nome = "Operação Starlite",
		nomeEn = "Operation Starlite",
		desc = "A data, a base, a carta e a moldura da operação.",
		itens = { "emb_starlite", "emb_chulai", "mol_mapa", "mol_starlite" },
		premio = { item = "emb_operacao", fragmentos = 150, creditos = 0 },
	},
	{
		id = "plaquetas",
		nome = "Plaquetas de Identificação",
		nomeEn = "Identification Tags",
		desc = "As seis plaquetas do cartão.",
		itens = { "tag_aco", "tag_aluminio", "tag_borracha", "tag_corrente", "tag_latao", "tag_gravada" },
		premio = { item = "mol_identidade", fragmentos = 150, creditos = 0 },
	},
	{
		id = "molduras",
		nome = "Molduras do Cartão",
		nomeEn = "Card Frames",
		desc = "As seis molduras do cartão.",
		itens = { "mol_lona", "mol_caixote", "mol_mapa", "mol_latao", "mol_noite", "mol_starlite" },
		premio = { item = "emb_arquivo", fragmentos = 150, creditos = 0 },
	},
	{
		id = "arsenal_us",
		nome = "Arsenal dos Fuzileiros",
		nomeEn = "Marines' Armory",
		desc = "Os oito acabamentos das armas dos EUA.",
		itens = {
			"skin_m14_birch",
			"skin_m14_tape",
			"skin_m14_worn",
			"skin_m60_od",
			"skin_m60_worn",
			"skin_m79_walnut",
			"skin_m79_od",
			"skin_m1911_blued",
		},
		premio = { item = "mol_arsenal_us", fragmentos = 300, creditos = 3000 },
	},
	{
		id = "arsenal_vc",
		nome = "Arsenal da Frente",
		nomeEn = "Front's Armory",
		desc = "Os nove acabamentos das armas da Frente.",
		itens = {
			"skin_type56_birch",
			"skin_type56_blued",
			"skin_type56_tape",
			"skin_sks_walnut",
			"skin_sks_worn",
			"skin_rpd_birch",
			"skin_rpd_worn",
			"skin_type54_worn",
			"skin_rpg2_od",
		},
		premio = { item = "mol_arsenal_vc", fragmentos = 300, creditos = 3000 },
	},
	{
		id = "fardas_us",
		nome = "Fardas dos Fuzileiros",
		nomeEn = "Marines' Uniforms",
		desc = "Os cinco uniformes dos EUA.",
		itens = { "skin_us_faded", "skin_us_duck", "skin_us_tadpole", "skin_us_lizard", "skin_us_tiger" },
		premio = { item = "tag_fardas_us", fragmentos = 500, creditos = 5000 },
	},
	{
		id = "fardas_vc",
		nome = "Fardas da Frente",
		nomeEn = "Front's Uniforms",
		desc = "Os três uniformes da Frente.",
		itens = { "skin_vc_black", "skin_vc_brown", "skin_vc_tiger" },
		premio = { item = "tag_fardas_vc", fragmentos = 300, creditos = 3000 },
	},
	{
		id = "arquivo",
		nome = "Arquivo Completo",
		nomeEn = "Complete Archive",
		desc = "Todas as outras coleções completas.",
		itens = {},
		colecoes = {
			"objetivos",
			"operacao",
			"plaquetas",
			"molduras",
			"arsenal_us",
			"arsenal_vc",
			"fardas_us",
			"fardas_vc",
		},
		premio = { item = "mol_arquivo", fragmentos = 1000, creditos = 10000 },
	},
} :: { Colecao }

local byCol: { [string]: Colecao } = {}
for _, c in Arquivo.COLECOES do
	byCol[c.id] = c
end

function Arquivo.colecao(id: any): Colecao?
	return if type(id) == "string" then byCol[id] else nil
end

-- ===== catálogo =====
-- categoria de um item do álbum (nil = não entra: prêmio de saldo, camuflagem de mato, desconhecido)
function Arquivo.categoria(id: string): string?
	local info = Cosmeticos.info(id)
	if not info or info.vantagem then
		return nil
	end
	if info.kind == "emblema" then
		return "insignias"
	elseif info.kind == "plaqueta" then
		return "plaquetas"
	elseif info.kind == "moldura" then
		return "molduras"
	elseif info.kind == "skin" then
		local s = Skins.get(id)
		if s and s.kind == "weapon" then
			return "acabamentos"
		elseif s and s.kind == "uniform" then
			return "uniformes"
		end
	end
	return nil
end

-- todos os itens do álbum, na ordem: categoria, raridade, nome
local ORDEM_RAR: { [string]: number } = {}
for i, r in Caixas.RARIDADES do
	ORDEM_RAR[r.id] = i
end
local ORDEM_CAT: { [string]: number } = {}
for i, c in Arquivo.CATEGORIAS do
	ORDEM_CAT[c.id] = i
end
local cacheItens: { string }? = nil
function Arquivo.itens(): { string }
	if cacheItens then
		return cacheItens
	end
	local out: { string } = {}
	for _, it in Cosmeticos.ITENS do
		if Arquivo.categoria(it.id) then
			table.insert(out, it.id)
		end
	end
	for _, s in Skins.CATALOG do
		if Arquivo.categoria(s.id) then
			table.insert(out, s.id)
		end
	end
	table.sort(out, function(a, b)
		local ca, cb = ORDEM_CAT[Arquivo.categoria(a) :: string], ORDEM_CAT[Arquivo.categoria(b) :: string]
		if ca ~= cb then
			return ca < cb
		end
		local ra, rb = ORDEM_RAR[Cosmeticos.info(a).raridade] or 0, ORDEM_RAR[Cosmeticos.info(b).raridade] or 0
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	cacheItens = out
	return out
end

-- ===== origens (de onde o item sai) =====
-- tipo: "caixa" (caixa = id, paga = bool, temporada = bool), "troca" (custo em Fragmentos),
-- "compra_direta" (preco em $, aba CAIXAS), "intendencia" (preco em $), "robux" (Developer Product
-- ou Game Pass, compra direta em Robux) e "colecao" (colecao = id: prêmio exclusivo).
export type Origem = {
	tipo: string,
	caixa: string?,
	paga: boolean?,
	temporada: boolean?,
	custo: number?,
	preco: number?,
	colecao: string?,
}

-- preço da compra direta com créditos (o mesmo do CaixaRegras.precoCreditos; o teste confere)
function Arquivo.precoDireto(id: string): number?
	local info = Cosmeticos.info(id)
	if
		not info
		or info.exclusivo
		or (info.kind ~= "emblema" and info.kind ~= "plaqueta" and info.kind ~= "moldura")
	then
		return nil
	end
	local r = Caixas.raridade(info.raridade)
	return r and r.creditos
end

function Arquivo.origens(id: string): { Origem }
	local out: { Origem } = {}
	local info = Cosmeticos.info(id)
	if not info then
		return out
	end
	local emCaixa = false
	for _, c in Caixas.CAIXAS do
		for _, e in c.itens do
			if e.item == id then
				emCaixa = true
				table.insert(
					out,
					{ tipo = "caixa", caixa = c.id, paga = c.tipo == "paga", temporada = c.temporada ~= nil }
				)
				break
			end
		end
	end
	local r = Caixas.raridade(info.raridade)
	if emCaixa and r and info.kind ~= "creditos" and info.kind ~= "fragmentos" then
		table.insert(out, { tipo = "troca", custo = r.custo })
	end
	local pd = Arquivo.precoDireto(id)
	if pd then
		table.insert(out, { tipo = "compra_direta", preco = pd })
	end
	local s = Skins.get(id)
	if s then
		local preco = Skins.tierPrice(s.tier)
		if preco > 0 then
			table.insert(out, { tipo = "intendencia", preco = preco })
		end
		if Skins.robuxId(s) ~= 0 then
			table.insert(out, { tipo = "robux" })
		end
	end
	for _, c in Arquivo.COLECOES do
		if c.premio.item == id then
			table.insert(out, { tipo = "colecao", colecao = c.id })
		end
	end
	return out
end

-- dá para conseguir sem Robux? (caixa grátis, troca, compra direta, Intendência ou coleção)
function Arquivo.gratis(id: string): boolean
	for _, o in Arquivo.origens(id) do
		if (o.tipo == "caixa" and not o.paga) or o.tipo ~= "caixa" and o.tipo ~= "robux" then
			return true
		end
	end
	return false
end

function Arquivo.compraDireta(id: string): boolean
	for _, o in Arquivo.origens(id) do
		if o.tipo == "compra_direta" or o.tipo == "intendencia" or o.tipo == "robux" then
			return true
		end
	end
	return false
end

-- ===== progresso =====
-- `possui(id)`: a posse do jogador; `completa(colId)`: para a coleção de coleções
function Arquivo.progresso(c: Colecao, possui: (string) -> boolean): (number, number)
	if c.colecoes then
		local tem = 0
		for _, sub in c.colecoes do
			local sc = byCol[sub]
			if sc then
				local t, n = Arquivo.progresso(sc, possui)
				if t >= n then
					tem += 1
				end
			end
		end
		return tem, #c.colecoes
	end
	local tem = 0
	for _, id in c.itens do
		if possui(id) then
			tem += 1
		end
	end
	return tem, #c.itens
end

function Arquivo.completa(c: Colecao, possui: (string) -> boolean): boolean
	local t, n = Arquivo.progresso(c, possui)
	return n > 0 and t >= n
end

-- ===== validação (o teste e o servidor chamam) =====
function Arquivo.validar(): { string }
	local erros: { string } = {}
	local premios: { [string]: string } = {}
	for _, c in Arquivo.COLECOES do
		if c.colecoes then
			for _, sub in c.colecoes do
				if not byCol[sub] or sub == c.id then
					table.insert(erros, c.id .. ": coleção desconhecida " .. sub)
				end
			end
		elseif #c.itens < 2 then
			table.insert(erros, c.id .. ": coleção com menos de 2 itens")
		end
		local vistos: { [string]: boolean } = {}
		for _, id in c.itens do
			if vistos[id] then
				table.insert(erros, c.id .. ": item repetido " .. id)
			end
			vistos[id] = true
			if not Arquivo.categoria(id) then
				table.insert(erros, c.id .. ": item fora do álbum " .. id)
			elseif not Arquivo.gratis(id) then
				table.insert(erros, c.id .. ": item sem caminho grátis " .. id)
			end
			local info = Cosmeticos.info(id)
			if info and info.exclusivo then
				table.insert(erros, c.id .. ": prêmio exclusivo dentro de coleção " .. id)
			end
		end
		local p = c.premio
		local pi = Cosmeticos.info(p.item)
		if not pi or pi.exclusivo ~= "arquivo" then
			table.insert(erros, c.id .. ": o prêmio precisa ser exclusivo do Arquivo")
		end
		if premios[p.item] then
			table.insert(erros, c.id .. ": prêmio repetido com " .. premios[p.item])
		end
		premios[p.item] = c.id
		if p.fragmentos < 0 or p.creditos < 0 or p.fragmentos ~= math.floor(p.fragmentos) then
			table.insert(erros, c.id .. ": prêmio com número ruim")
		end
	end
	-- todo exclusivo do Arquivo é prêmio de alguma coleção (nada preso fora do jogo)
	for _, it in Cosmeticos.ITENS do
		if it.exclusivo == "arquivo" and not premios[it.id] then
			table.insert(erros, it.id .. ": exclusivo sem coleção")
		end
	end
	return erros
end

return Arquivo
