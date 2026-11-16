--!strict
-- Caixas de suprimentos (D-173, pedido do dono: "monetização completa, loot boxes, economia e
-- conformidade Roblox"). Catálogo e regras PUROS (testados no Lune: tests/luau/caixas.luau).
--
-- Regras (política "Paid Random Items" do Roblox, lida em 2026-11-15):
--   - o sorteio é SÓ no servidor (CaixaService), com o gerador do servidor; o cliente nunca manda
--     número, peso nem resultado;
--   - cada caixa tem uma tabela própria, com versão. Os pesos são inteiros na base ESCALA (100.000:
--     1 = 0,001%) e somam exatamente ESCALA, então as chances mostradas são exatas e somam 100%;
--   - as chances são as mesmas para todo jogador: nada muda com gasto, idade, saldo ou histórico.
--     O que muda por jogador é só o RESULTADO FINAL de um item que ele já tem: vira Fragmentos de
--     Arsenal (a quantidade da raridade). `Caixas.odds` devolve os resultados finais dele;
--   - a garantia progressiva (pity) existe na tabela, mas DESLIGADA (`Caixas.PITY.enabled`). Ligada,
--     `Caixas.odds` já devolve as chances efetivas do próximo sorteio com o contador do jogador;
--   - caixa paga: Developer Product; o resultado é sorteado depois do recibo e gravado com o
--     PurchaseId (o mesmo recibo de novo devolve o mesmo resultado, nunca sorteia outra vez).
--     Só para quem o PolicyService libera (ArePaidRandomItemsRestricted falso) e só com
--     `Caixas.PAGAS_LIGADAS` (desligado até o dono atualizar o questionário de classificação:
--     itens aleatórios pagos mudam as respostas, e a política manda reenviar);
--   - caixa gratuita: só com Bilhetes de Recompensa, ganhos jogando (nunca vendidos, nunca por
--     Robux, assinatura ou pacote pago).
local Caixas = {}

Caixas.ESCALA = 100000 -- peso inteiro: 1 = 0,001%
Caixas.PAGAS_LIGADAS = false -- D-173: o dono liga depois de reenviar o questionário de classificação

export type Raridade = {
	id: string,
	nome: string,
	nomeEn: string,
	cor: { number },
	fragmentos: number, -- o que uma repetida desta raridade vira
	custo: number, -- preço na troca de Fragmentos (item garantido, escolhido pelo jogador)
}

-- cinco raridades; a cor só classifica (não é valor em dinheiro)
Caixas.RARIDADES = {
	{ id = "comum", nome = "Comum", nomeEn = "Common", cor = { 158, 158, 150 }, fragmentos = 10, custo = 100 },
	{ id = "incomum", nome = "Incomum", nomeEn = "Uncommon", cor = { 96, 168, 76 }, fragmentos = 25, custo = 250 },
	{ id = "raro", nome = "Raro", nomeEn = "Rare", cor = { 72, 128, 210 }, fragmentos = 60, custo = 600 },
	{ id = "epico", nome = "Épico", nomeEn = "Epic", cor = { 150, 86, 200 }, fragmentos = 150, custo = 1500 },
	{
		id = "lendario",
		nome = "Lendário",
		nomeEn = "Legendary",
		cor = { 214, 172, 64 },
		fragmentos = 400,
		custo = 4000,
	},
} :: { Raridade }

local BY_RARITY: { [string]: Raridade } = {}
for i, r in Caixas.RARIDADES do
	BY_RARITY[r.id] = r;
	(r :: any).ordem = i
end

function Caixas.raridade(id: string): Raridade?
	return BY_RARITY[id]
end

export type Entrada = { item: string, peso: number }
export type Caixa = {
	id: string,
	nome: string,
	nomeEn: string,
	desc: string,
	tipo: string, -- "paga" | "gratuita"
	versao: number, -- sobe a cada mudança na tabela (vai no registro de cada sorteio)
	sorteios: number, -- resultados por abertura
	robux: number?, -- preço de REFERÊNCIA (o mostrado vem do GetProductInfoAsync)
	produto: string?, -- chave do Developer Product em Commerce.IDS
	bilhetes: number?, -- custo em Bilhetes de Recompensa (só a gratuita)
	temporada: string?, -- só aberta na temporada (Temporada.atual)
	modelo: string, -- caixa 3D (AssetIds.Models)
	itens: { Entrada },
}

-- ===== garantia progressiva (pity): DESLIGADA =====
-- Ligada: a partir de `depois` aberturas sem `raridade` ou melhor, cada abertura soma `passo` (na
-- ESCALA) ao total da raridade, tirado proporcionalmente das menores; na abertura `garantia` a
-- raridade vem com certeza. O contador é por caixa e volta a zero quando a raridade sai.
Caixas.PITY = { enabled = false, raridade = "epico", depois = 30, passo = 1000, garantia = 50 }

-- ===== tabelas =====
-- Itens: Cosmeticos (plaquetas, insígnias, molduras) e Skins (acabamentos de arma e uniformes). A
-- camuflagem de mato NUNCA entra (dá vantagem contra os bots).
Caixas.CAIXAS = {
	{
		id = "gratuita",
		nome = "Caixa de Recompensa",
		nomeEn = "Reward Crate",
		desc = "Ganha jogando: desafios, objetivos e marcos. Abre com 1 Bilhete de Recompensa.",
		tipo = "gratuita",
		versao = 1,
		sorteios = 1,
		bilhetes = 1,
		modelo = "caixa_municao_us",
		itens = {
			{ item = "tag_aco", peso = 9000 },
			{ item = "tag_aluminio", peso = 9000 },
			{ item = "tag_borracha", peso = 9000 },
			{ item = "tag_corrente", peso = 9000 },
			{ item = "emb_arrozais", peso = 8000 },
			{ item = "emb_serraria", peso = 8000 },
			{ item = "emb_ponte", peso = 8000 },
			{ item = "emb_engenho", peso = 8000 },
			{ item = "mol_lona", peso = 7000 },
			{ item = "mol_caixote", peso = 7000 },
			{ item = "mol_mapa", peso = 7000 },
			{ item = "mol_latao", peso = 3000 },
			{ item = "emb_xomgo", peso = 3000 },
			{ item = "tag_latao", peso = 3000 },
			{ item = "mol_noite", peso = 1000 },
			{ item = "tag_gravada", peso = 1000 },
		},
	},
	{
		id = "suprimentos",
		nome = "Caixa de Suprimentos",
		nomeEn = "Supply Crate",
		desc = "Plaquetas, insígnias, molduras e acabamentos de arma.",
		tipo = "paga",
		versao = 1,
		sorteios = 1,
		robux = 49,
		produto = "PRODUCT_CRATE_SUPPLY",
		modelo = "caixa_municao_us",
		itens = {
			-- comum: 10 x 6% = 60%
			{ item = "tag_aco", peso = 6000 },
			{ item = "tag_aluminio", peso = 6000 },
			{ item = "tag_borracha", peso = 6000 },
			{ item = "tag_corrente", peso = 6000 },
			{ item = "emb_arrozais", peso = 6000 },
			{ item = "emb_serraria", peso = 6000 },
			{ item = "emb_ponte", peso = 6000 },
			{ item = "emb_engenho", peso = 6000 },
			{ item = "mol_lona", peso = 6000 },
			{ item = "mol_caixote", peso = 6000 },
			-- incomum: 5 x 5% = 25%
			{ item = "mol_mapa", peso = 5000 },
			{ item = "tag_latao", peso = 5000 },
			{ item = "emb_xomgo", peso = 5000 },
			{ item = "skin_m14_birch", peso = 5000 },
			{ item = "skin_type56_birch", peso = 5000 },
			-- raro: 5 x 2% = 10%
			{ item = "mol_latao", peso = 2000 },
			{ item = "skin_m14_worn", peso = 2000 },
			{ item = "skin_sks_walnut", peso = 2000 },
			{ item = "skin_m1911_blued", peso = 2000 },
			{ item = "skin_type54_worn", peso = 2000 },
			-- épico: 4 x 1% = 4%
			{ item = "mol_noite", peso = 1000 },
			{ item = "skin_m60_od", peso = 1000 },
			{ item = "skin_rpd_birch", peso = 1000 },
			{ item = "emb_chulai", peso = 1000 },
			-- lendário: 2 x 0,5% = 1%
			{ item = "tag_gravada", peso = 500 },
			{ item = "mol_starlite", peso = 500 },
		},
	},
	{
		id = "especiais",
		nome = "Caixa de Equipamentos Especiais",
		nomeEn = "Special Equipment Crate",
		desc = "Acabamentos de arma e uniformes de época, com mais chance de raro.",
		tipo = "paga",
		versao = 1,
		sorteios = 1,
		robux = 99,
		produto = "PRODUCT_CRATE_SPECIAL",
		modelo = "caixa_municao_vc",
		itens = {
			-- incomum: 6 x 7,5% = 45%
			{ item = "skin_m14_birch", peso = 7500 },
			{ item = "skin_type56_birch", peso = 7500 },
			{ item = "skin_m79_walnut", peso = 7500 },
			{ item = "skin_rpd_worn", peso = 7500 },
			{ item = "skin_m60_worn", peso = 7500 },
			{ item = "skin_sks_worn", peso = 7500 },
			-- raro: 6 x 6% = 36%
			{ item = "skin_m14_tape", peso = 6000 },
			{ item = "skin_type56_tape", peso = 6000 },
			{ item = "skin_m79_od", peso = 6000 },
			{ item = "skin_type56_blued", peso = 6000 },
			{ item = "skin_rpg2_od", peso = 6000 },
			{ item = "mol_latao", peso = 6000 },
			-- épico: 4 x 4% = 16%
			{ item = "skin_us_faded", peso = 4000 },
			{ item = "skin_vc_black", peso = 4000 },
			{ item = "mol_noite", peso = 4000 },
			{ item = "emb_chulai", peso = 4000 },
			-- lendário: 2 x 1,5% = 3%
			{ item = "skin_us_tiger", peso = 1500 },
			{ item = "skin_vc_tiger", peso = 1500 },
		},
	},
	{
		id = "elite",
		nome = "Caixa de Arsenal de Elite",
		nomeEn = "Elite Arsenal Crate",
		desc = "Uniformes de época e as plaquetas e molduras mais raras.",
		tipo = "paga",
		versao = 1,
		sorteios = 1,
		robux = 149,
		produto = "PRODUCT_CRATE_ELITE",
		modelo = "caixa_municao_us",
		itens = {
			-- raro: 4 x 10% = 40%
			{ item = "skin_m14_tape", peso = 10000 },
			{ item = "skin_type56_tape", peso = 10000 },
			{ item = "skin_rpg2_od", peso = 10000 },
			{ item = "mol_latao", peso = 10000 },
			-- épico: 6 x 8% = 48%
			{ item = "skin_us_faded", peso = 8000 },
			{ item = "skin_us_duck", peso = 8000 },
			{ item = "skin_vc_black", peso = 8000 },
			{ item = "skin_vc_brown", peso = 8000 },
			{ item = "mol_noite", peso = 8000 },
			{ item = "emb_chulai", peso = 8000 },
			-- lendário: 4 x 3% = 12%
			{ item = "skin_us_tiger", peso = 3000 },
			{ item = "skin_vc_tiger", peso = 3000 },
			{ item = "tag_gravada", peso = 3000 },
			{ item = "mol_starlite", peso = 3000 },
		},
	},
	{
		id = "historica",
		nome = "Caixa de Operações Históricas",
		nomeEn = "Historical Operations Crate",
		desc = "Só nesta campanha: a Operação Starlite, agosto de 1965.",
		tipo = "paga",
		versao = 1,
		sorteios = 1,
		robux = 99,
		produto = "PRODUCT_CRATE_HISTORIC",
		temporada = "S1",
		modelo = "caixa_municao_vc",
		itens = {
			-- incomum: 4 x 12,5% = 50%
			{ item = "emb_xomgo", peso = 12500 },
			{ item = "mol_mapa", peso = 12500 },
			{ item = "tag_latao", peso = 12500 },
			{ item = "skin_m60_worn", peso = 12500 },
			-- raro: 3 x 10% = 30%
			{ item = "emb_starlite", peso = 10000 },
			{ item = "mol_latao", peso = 10000 },
			{ item = "skin_m79_od", peso = 10000 },
			-- épico: 3 x 5% = 15%
			{ item = "skin_us_tadpole", peso = 5000 },
			{ item = "skin_vc_brown", peso = 5000 },
			{ item = "emb_chulai", peso = 5000 },
			-- lendário: 1 x 5% = 5%
			{ item = "mol_starlite", peso = 5000 },
		},
	},
} :: { Caixa }

local BY_ID: { [string]: Caixa } = {}
for _, c in Caixas.CAIXAS do
	BY_ID[c.id] = c
end

function Caixas.get(id: any): Caixa?
	return if type(id) == "string" then BY_ID[id] else nil
end

-- a caixa do Developer Product `key` (Commerce.IDS), ou nil
function Caixas.porProduto(key: string?): Caixa?
	if not key then
		return nil
	end
	for _, c in Caixas.CAIXAS do
		if c.produto == key then
			return c
		end
	end
	return nil
end

-- caixa de temporada: só aberta entre o início e o fim da temporada `c.temporada` (`season` =
-- Temporada.SEASON); as outras, sempre
function Caixas.disponivel(c: Caixa, now: number, season: { id: string, startsAt: number, endsAt: number }): boolean
	if not c.temporada then
		return true
	end
	return season.id == c.temporada and now >= season.startsAt and now < season.endsAt
end

-- ===== validação =====
-- `itemInfo(id)` devolve { raridade = "comum".., kind = .. } ou nil. Erros em texto (vazio = ok).
function Caixas.validar(c: Caixa, itemInfo: (string) -> any): { string }
	local erros = {}
	local soma = 0
	local vistos: { [string]: boolean } = {}
	if type(c.versao) ~= "number" or c.versao < 1 then
		table.insert(erros, c.id .. ": versão inválida")
	end
	if c.sorteios ~= 1 then
		table.insert(erros, c.id .. ": só 1 resultado por abertura nesta versão")
	end
	if #c.itens == 0 then
		table.insert(erros, c.id .. ": sem itens")
	end
	for _, e in c.itens do
		local p = e.peso
		if type(p) ~= "number" or p ~= p or p <= 0 or p ~= math.floor(p) then
			table.insert(erros, string.format("%s: peso inválido em %s", c.id, tostring(e.item)))
		else
			soma += p
		end
		if vistos[e.item] then
			table.insert(erros, c.id .. ": item repetido " .. e.item)
		end
		vistos[e.item] = true
		local info = itemInfo(e.item)
		if not info then
			table.insert(erros, c.id .. ": item desconhecido " .. e.item)
		elseif not BY_RARITY[info.raridade] then
			table.insert(erros, c.id .. ": raridade inválida em " .. e.item)
		elseif info.vantagem then
			table.insert(erros, c.id .. ": item com vantagem de jogo " .. e.item)
		end
	end
	if soma ~= Caixas.ESCALA then
		table.insert(erros, string.format("%s: os pesos somam %d (precisa de %d)", c.id, soma, Caixas.ESCALA))
	end
	if c.tipo == "paga" and not c.produto then
		table.insert(erros, c.id .. ": caixa paga sem produto")
	end
	if c.tipo == "gratuita" and (c.produto or c.robux) then
		table.insert(erros, c.id .. ": caixa gratuita não pode ter preço nem produto")
	end
	return erros
end

-- percentual exato de um peso, em texto ("6%", "0,5%", "12,5%")
function Caixas.pct(peso: number): string
	local milesimos = math.floor(peso * 100000 / Caixas.ESCALA + 0.5) -- em 0,001%
	local inteiro = milesimos // 1000
	local frac = milesimos % 1000
	if frac == 0 then
		return string.format("%d%%", inteiro)
	end
	local s = string.format("%03d", frac):gsub("0+$", "")
	return string.format("%d,%s%%", inteiro, s)
end

-- ===== pity (só com Caixas.PITY.enabled) =====
-- pesos efetivos do próximo sorteio com `contador` aberturas sem a raridade do pity
function Caixas.pesosEfetivos(c: Caixa, itemInfo: (string) -> any, contador: number?): { Entrada }
	local P = Caixas.PITY
	local out: { Entrada } = {}
	for _, e in c.itens do
		table.insert(out, { item = e.item, peso = e.peso })
	end
	if not P.enabled or not contador or contador < P.depois then
		return out
	end
	local alvo = BY_RARITY[P.raridade]
	local ordemAlvo = (alvo :: any).ordem
	local alto, baixo = 0, 0
	for _, e in out do
		local r = BY_RARITY[itemInfo(e.item).raridade] :: any
		if r.ordem >= ordemAlvo then
			alto += e.peso
		else
			baixo += e.peso
		end
	end
	if alto == 0 or baixo == 0 then
		return out
	end
	local novoAlto = if contador + 1 >= P.garantia
		then Caixas.ESCALA
		else math.min(Caixas.ESCALA, alto + (contador - P.depois + 1) * P.passo)
	-- reparte os novos totais proporcionalmente, em inteiros que somam ESCALA
	local function reparte(lista: { Entrada }, total: number, novo: number)
		local acc, resto = 0, 0
		for i, e in lista do
			if i == #lista then
				e.peso = novo - acc
			else
				local v = e.peso * novo + resto
				e.peso = v // total
				resto = v % total
				acc += e.peso
			end
		end
	end
	local altos, baixos = {}, {}
	for _, e in out do
		local r = BY_RARITY[itemInfo(e.item).raridade] :: any
		table.insert(if r.ordem >= ordemAlvo then altos else baixos, e)
	end
	reparte(altos, alto, novoAlto)
	reparte(baixos, baixo, Caixas.ESCALA - novoAlto)
	return out
end

-- ===== resultados finais do jogador (o que a tela mostra antes da compra) =====
export type Resultado = {
	item: string,
	peso: number, -- na ESCALA
	pct: string,
	raridade: string,
	repetido: boolean, -- já tem: o resultado final é `fragmentos`
	fragmentos: number,
}
-- `possui(item)`: o jogador já tem o item. Soma sempre ESCALA (100%).
function Caixas.odds(c: Caixa, itemInfo: (string) -> any, possui: (string) -> boolean, contador: number?): { Resultado }
	local out: { Resultado } = {}
	for _, e in Caixas.pesosEfetivos(c, itemInfo, contador) do
		local info = itemInfo(e.item)
		local r = BY_RARITY[info.raridade]
		local dup = possui(e.item)
		table.insert(out, {
			item = e.item,
			peso = e.peso,
			pct = Caixas.pct(e.peso),
			raridade = r.id,
			repetido = dup,
			fragmentos = if dup then r.fragmentos else 0,
		})
	end
	return out
end

-- chance por raridade (na ESCALA), na ordem de Caixas.RARIDADES
function Caixas.porRaridade(c: Caixa, itemInfo: (string) -> any, contador: number?): { [string]: number }
	local t: { [string]: number } = {}
	for _, r in Caixas.RARIDADES do
		t[r.id] = 0
	end
	for _, e in Caixas.pesosEfetivos(c, itemInfo, contador) do
		local id = itemInfo(e.item).raridade
		t[id] += e.peso
	end
	return t
end

-- ===== sorteio =====
-- `n` é um inteiro uniforme em [0, ESCALA) tirado pelo SERVIDOR (Random:NextInteger). Devolve a
-- entrada sorteada. Nada aqui lê o cliente.
function Caixas.escolher(pesos: { Entrada }, n: number): Entrada
	assert(n >= 0 and n < Caixas.ESCALA and n == math.floor(n), "sorteio fora da faixa")
	local acc = 0
	for _, e in pesos do
		acc += e.peso
		if n < acc then
			return e
		end
	end
	error("pesos não somam a ESCALA")
end

-- ===== pity: próximo contador depois de um resultado =====
function Caixas.proximoContador(contador: number, raridadeSaida: string): number
	local P = Caixas.PITY
	local alvo = BY_RARITY[P.raridade] :: any
	local saiu = BY_RARITY[raridadeSaida] :: any
	if saiu and alvo and saiu.ordem >= alvo.ordem then
		return 0
	end
	return contador + 1
end

-- texto das regras mostrado com a lista (antes da compra)
Caixas.REGRAS = {
	"1 resultado por abertura. As chances abaixo são exatas e somam 100%.",
	"Item que você já tem vira Fragmentos de Arsenal: Comum 10, Incomum 25, Raro 60, Épico 150, Lendário 400.",
	"Fragmentos trocam por qualquer item da troca, garantido. Não viram Robux nem dinheiro.",
	"As chances são as mesmas para todos e não mudam com o que você gasta.",
	"Itens só visuais, presos à sua conta: não dão vantagem e não podem ser trocados.",
}
Caixas.REGRAS_EN = {
	"1 result per opening. The odds below are exact and add up to 100%.",
	"An item you already own becomes Arsenal Fragments: Common 10, Uncommon 25, Rare 60, Epic 150, Legendary 400.",
	"Fragments trade for any item in the exchange, guaranteed. They never become Robux or money.",
	"The odds are the same for everyone and never change with how much you spend.",
	"Cosmetic only, bound to your account: no gameplay advantage and no trading.",
}

return Caixas
