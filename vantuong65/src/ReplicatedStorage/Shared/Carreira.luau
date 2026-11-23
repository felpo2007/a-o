--!strict
-- D-247 (dono: "criar sistema de progressao e de vantagens", com a imagem de medalhas, árvore, nível e
-- prestígio). Módulo puro, testado no Lune (tests/luau/carreira.luau); quem aplica é o CarreiraService.
--
-- O NÍVEL DO SOLDADO (1 a 55) é uma trilha separada da patente. Ele sai de `xp - base`, então:
--   - prestigiar só move a `base` para o XP de agora: patente, créditos, armas e skins não mudam;
--   - nenhum contador novo de XP entra no salvamento (o XP segue pelo delta da sessão).
-- A cada 4 níveis vem 1 ponto para a árvore. Quem já prestigiou tem pontos para a árvore inteira.
-- Os efeitos passam pelo mesmo teto de combate das vantagens compradas (Vantagens.CAP, 12%).
-- Números de design: PLACEHOLDER até o teste com jogadores.
local Medalhas = require(script and (script :: any).Parent.Medalhas or "./Medalhas") :: any

local Carreira = {}

Carreira.NIVEL_MAX = 55
Carreira.PRESTIGIO_MAX = 10
Carreira.NIVEIS_POR_PONTO = 4
Carreira.BONUS_XP_POR_PRESTIGIO = 0.02

-- XP total para chegar a cada nível: passo de 300 + 40 por nível (o 55 fica em 73.440 XP, perto dos
-- 75.700 da última patente)
Carreira.XP_NIVEL = {} :: { number }
do
	local total = 0
	Carreira.XP_NIVEL[1] = 0
	for n = 2, Carreira.NIVEL_MAX do
		total += 300 + 40 * (n - 2)
		Carreira.XP_NIVEL[n] = total
	end
end

export type No = {
	id: string,
	nome: string,
	desc: string,
	icone: string,
	linha: number,
	coluna: number,
	requer: string?,
	efeitos: { [string]: number },
}

-- 3 linhas de 4: cada nó pede o anterior; a primeira coluna desce a partir do primeiro nó
Carreira.ARVORE = {
	{
		id = "passo",
		nome = "Movimento Ágil",
		desc = "+2% de velocidade no trote e na corrida.",
		icone = "corrida",
		linha = 1,
		coluna = 1,
		efeitos = { speed = 1.02 },
	},
	{
		id = "cartucheira",
		nome = "Cartucheira",
		desc = "+1 carregador ao nascer.",
		icone = "municao",
		linha = 1,
		coluna = 2,
		requer = "passo",
		efeitos = { mags = 1 },
	},
	{
		id = "couro",
		nome = "Couro Curtido",
		desc = "+3% de vida máxima.",
		icone = "forca",
		linha = 1,
		coluna = 3,
		requer = "cartucheira",
		efeitos = { health = 1.03 },
	},
	{
		id = "resistencia",
		nome = "Resistência",
		desc = "Mais +3% de vida máxima.",
		icone = "vida",
		linha = 1,
		coluna = 4,
		requer = "couro",
		efeitos = { health = 1.03 },
	},
	{
		id = "mira",
		nome = "Mira Firme",
		desc = "A mira da luneta balança 4% menos.",
		icone = "mira",
		linha = 2,
		coluna = 1,
		requer = "passo",
		efeitos = { sway = 0.96 },
	},
	{
		id = "mochila",
		nome = "Mochila de Assalto",
		desc = "+1 granada ao nascer.",
		icone = "mochila",
		linha = 2,
		coluna = 2,
		requer = "mira",
		efeitos = { grenades = 1 },
	},
	{
		id = "radio",
		nome = "Rádio de Campanha",
		desc = "O inimigo marcado fica 25% mais tempo marcado.",
		icone = "radio",
		linha = 2,
		coluna = 3,
		requer = "mochila",
		efeitos = { mark = 1.25 },
	},
	{
		id = "binoculo",
		nome = "Binóculo",
		desc = "Mais 20% de tempo na marca do inimigo.",
		icone = "binoculo",
		linha = 2,
		coluna = 4,
		requer = "radio",
		efeitos = { mark = 1.2 },
	},
	{
		id = "garrote",
		nome = "Garrote",
		desc = "O sangramento corre 10% mais devagar.",
		icone = "garrote",
		linha = 3,
		coluna = 1,
		requer = "mira",
		efeitos = { bleed = 0.9 },
	},
	{
		id = "maos",
		nome = "Mãos Treinadas",
		desc = "Recarga 3% mais rápida.",
		icone = "recarga",
		linha = 3,
		coluna = 2,
		requer = "garrote",
		efeitos = { reload = 0.97 },
	},
	{
		id = "folego",
		nome = "Fôlego Longo",
		desc = "Prende a respiração por +20% do tempo.",
		icone = "folego",
		linha = 3,
		coluna = 3,
		requer = "maos",
		efeitos = { breath = 1.2 },
	},
	{
		id = "socorro",
		nome = "Socorro de Campo",
		desc = "Bandagem e torniquete 12% mais rápidos.",
		icone = "socorro",
		linha = 3,
		coluna = 4,
		requer = "folego",
		efeitos = { bandage = 0.88 },
	},
} :: { No }

local porId: { [string]: No } = {}
for _, n in Carreira.ARVORE do
	porId[n.id] = n
end

function Carreira.no(id: string): No?
	return porId[id]
end

-- categorias da vitrine de medalhas (Shared/Medalhas)
Carreira.CATEGORIAS = { "combate", "objetivos", "suporte", "especiais" }
Carreira.CATEGORIA_MEDALHA = {
	bronze_star = "combate",
	combat_action = "combate",
	purple_heart = "combate",
	navy_cross = "objetivos",
	unit_citation = "objetivos",
	heroi_libertacao = "objetivos",
	socorro = "suporte",
	irmaos = "suporte",
	ordem_cumprida = "suporte",
	top10 = "especiais",
} :: { [string]: string }

export type Estado = {
	base: number, -- XP total no último prestígio
	prestigio: number,
	pago: number, -- último nível já recompensado neste prestígio
	nos: { [string]: boolean },
}

function Carreira.padrao(): Estado
	return { base = 0, prestigio = 0, pago = 1, nos = {} }
end

-- nível, XP dentro do nível e XP do nível inteiro (0 no nível máximo)
function Carreira.nivel(xp: number, base: number): (number, number, number)
	local x = math.max(xp - base, 0)
	local n = 1
	for i = 2, Carreira.NIVEL_MAX do
		if x >= Carreira.XP_NIVEL[i] then
			n = i
		else
			break
		end
	end
	if n >= Carreira.NIVEL_MAX then
		return n, x - Carreira.XP_NIVEL[n], 0
	end
	return n, x - Carreira.XP_NIVEL[n], Carreira.XP_NIVEL[n + 1] - Carreira.XP_NIVEL[n]
end

local function inteiro(v: any, min: number, max: number, padrao: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return padrao
	end
	return math.clamp(math.floor(v), min, max)
end

-- Dado salvo -> estado válido. Quem ainda não tinha carreira começa no nível do XP que já juntou, sem
-- receber de uma vez a recompensa dos níveis passados.
function Carreira.sanear(raw: any, xp: number): Estado
	if type(raw) ~= "table" then
		local e = Carreira.padrao()
		e.pago = (Carreira.nivel(xp, 0))
		return e
	end
	local e: Estado = {
		base = inteiro(raw.base, 0, math.max(xp, 0), 0),
		prestigio = inteiro(raw.prestigio, 0, Carreira.PRESTIGIO_MAX, 0),
		pago = inteiro(raw.pago, 1, Carreira.NIVEL_MAX, 1),
		nos = {},
	}
	if type(raw.nos) == "table" then
		for id, v in raw.nos do
			if type(id) == "string" and porId[id] and v == true then
				e.nos[id] = true
			end
		end
	end
	-- um nó sem o anterior não vale
	local mudou = true
	while mudou do
		mudou = false
		for id in e.nos do
			local r = porId[id].requer
			if r and not e.nos[r] then
				e.nos[id] = nil
				mudou = true
			end
		end
	end
	return e
end

-- Entre servidores: vale o prestígio maior; no mesmo prestígio, a escolha da sessão
function Carreira.mesclar(gravado: Estado, sessao: Estado): Estado
	local fonte = if gravado.prestigio > sessao.prestigio then gravado else sessao
	local base = fonte.base
	if gravado.prestigio == sessao.prestigio then
		base = math.max(gravado.base, sessao.base)
	end
	return {
		base = base,
		prestigio = fonte.prestigio,
		pago = if gravado.prestigio == sessao.prestigio then math.max(gravado.pago, sessao.pago) else fonte.pago,
		nos = table.clone(fonte.nos),
	}
end

function Carreira.pontosTotal(nivel: number, prestigio: number): number
	local ganhos = math.floor((nivel - 1) / Carreira.NIVEIS_POR_PONTO)
	if prestigio > 0 then
		ganhos += prestigio * #Carreira.ARVORE
	end
	return math.min(ganhos, #Carreira.ARVORE)
end

function Carreira.usados(e: Estado): number
	local n = 0
	for _ in e.nos do
		n += 1
	end
	return n
end

function Carreira.pontosLivres(e: Estado, xp: number): number
	local nivel = Carreira.nivel(xp, e.base)
	return math.max(Carreira.pontosTotal(nivel, e.prestigio) - Carreira.usados(e), 0)
end

function Carreira.podeAtivar(e: Estado, id: any, xp: number): (boolean, string)
	local n = if type(id) == "string" then porId[id] else nil
	if not n then
		return false, "inexistente"
	elseif e.nos[n.id] then
		return false, "ativa"
	elseif n.requer and not e.nos[n.requer] then
		return false, "bloqueada"
	elseif Carreira.pontosLivres(e, xp) <= 0 then
		return false, "sem pontos"
	end
	return true, "ok"
end

function Carreira.limpar(e: Estado)
	table.clear(e.nos)
end

-- efeitos somados dos nós ativos, nas chaves de Shared/Vantagens
function Carreira.efeitos(nos: { [string]: boolean }?): { [string]: number }
	local out: { [string]: number } = {}
	for _, n in Carreira.ARVORE do
		if nos and nos[n.id] then
			for k, v in n.efeitos do
				if k == "mags" or k == "grenades" then
					out[k] = (out[k] or 0) + v
				else
					out[k] = (out[k] or 1) * v
				end
			end
		end
	end
	return out
end

function Carreira.podePrestigiar(e: Estado, xp: number): (boolean, string)
	if e.prestigio >= Carreira.PRESTIGIO_MAX then
		return false, "prestigio maximo"
	elseif (Carreira.nivel(xp, e.base)) < Carreira.NIVEL_MAX then
		return false, "nivel"
	end
	return true, "ok"
end

-- Prestigia: o nível volta a 1 e a árvore fica como está. Patente, créditos e itens não mudam.
function Carreira.prestigiar(e: Estado, xp: number): boolean
	if not Carreira.podePrestigiar(e, xp) then
		return false
	end
	e.base = xp
	e.prestigio += 1
	e.pago = 1
	return true
end

function Carreira.multXp(prestigio: number): number
	return 1 + Carreira.BONUS_XP_POR_PRESTIGIO * math.clamp(prestigio, 0, Carreira.PRESTIGIO_MAX)
end

export type Recompensa = { nivel: number, creditos: number, caixa: boolean, ponto: boolean }

function Carreira.recompensa(n: number): Recompensa
	return {
		nivel = n,
		creditos = 20 + 4 * n,
		caixa = n % 10 == 0,
		ponto = (n - 1) % Carreira.NIVEIS_POR_PONTO == 0,
	}
end

-- níveis alcançados e ainda não pagos; marca como pagos
function Carreira.receber(e: Estado, xp: number): { Recompensa }
	local nivel = Carreira.nivel(xp, e.base)
	local out: { Recompensa } = {}
	for n = e.pago + 1, nivel do
		table.insert(out, Carreira.recompensa(n))
	end
	e.pago = math.max(e.pago, nivel)
	return out
end

-- a vitrine de medalhas: progresso de cada uma pelos contadores do perfil
function Carreira.vitrine(stats: { [string]: number }?, ganhas: { [string]: number }?): { { [string]: any } }
	local out = {}
	for _, m in Medalhas.LIST do
		local atual = math.min((stats and stats[m.stat]) or 0, m.goal)
		table.insert(out, {
			id = m.id,
			nome = m.name,
			desc = m.desc,
			atual = atual,
			meta = m.goal,
			ganha = (ganhas and ganhas[m.id] ~= nil) or false,
			categoria = Carreira.CATEGORIA_MEDALHA[m.id] or "especiais",
		})
	end
	return out
end

return Carreira
