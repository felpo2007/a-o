--!strict
-- Regras das caixas sobre o perfil (D-173). PURO: o CaixaService chama cada função DENTRO de um
-- UpdateAsync (PlayerData.transact), sobre o perfil gravado; o sorteio `n` vem do Random do
-- servidor. Testado no Lune (tests/luau/caixas.luau).
--
-- Bloco `caixas` do perfil (só muda por transação atômica; o salvamento comum nunca o sobrescreve):
--   bilhetes, fragmentos: saldos (inteiros, nunca negativos);
--   abertas[caixa], pity[caixa]: contadores (o pity só conta com Caixas.PITY.enabled);
--   hist: os últimos HIST resultados (mais novo no fim);
--   recibos[PurchaseId]: o resultado de cada caixa paga (o mesmo recibo devolve o mesmo resultado);
--   dia, hoje: dia UTC e bilhetes ganhos nele (teto TETO_DIA, contra farm em servidor privado);
--   on: plaqueta e moldura escolhidas.
local Caixas = require(
	if script
		then (game :: any):GetService("ReplicatedStorage").Shared.Caixas
		else "../../ReplicatedStorage/Shared/Caixas"
) :: any
local Cosmeticos = require(
	if script
		then (game :: any):GetService("ReplicatedStorage").Shared.Cosmeticos
		else "../../ReplicatedStorage/Shared/Cosmeticos"
) :: any

local CaixaRegras = {}

CaixaRegras.HIST = 100
CaixaRegras.MAX_RECIBOS = 200
CaixaRegras.TETO_DIA = 4 -- bilhetes ganhos por dia UTC
CaixaRegras.MAX_SALDO = 1000000
-- jogador restrito pelo PolicyService (ArePaidRandomItemsRestricted) que mesmo assim chegou a um
-- recibo de caixa paga (prompt aberto pelo próprio cliente): recebe Fragmentos fixos, sem sorteio
CaixaRegras.FIXO_RESTRITO = { suprimentos = 100, especiais = 200, elite = 300, historica = 200 }

export type Resultado = {
	caixa: string,
	versao: number,
	item: string?,
	raridade: string?,
	repetido: boolean,
	fragmentos: number,
	origem: string, -- "bilhete" | "recibo" | "restrito" | "troca"
	t: number,
	id: string?, -- PurchaseId (caixa paga)
}

export type Dados = {
	bilhetes: number,
	fragmentos: number,
	abertas: { [string]: number },
	pity: { [string]: number },
	hist: { Resultado },
	recibos: { [string]: Resultado },
	dia: number,
	hoje: number,
	boasVindas: boolean,
	on: { tag: string?, mol: string? },
}

function CaixaRegras.padrao(): Dados
	return {
		bilhetes = 0,
		fragmentos = 0,
		abertas = {},
		pity = {},
		hist = {},
		recibos = {},
		dia = -1,
		hoje = 0,
		boasVindas = false,
		on = {},
	}
end

local function num(v: any, lo: number, hi: number, def: number): number
	if type(v) ~= "number" or v ~= v then
		return def
	end
	return math.clamp(math.floor(v), lo, hi)
end

local function resultado(raw: any): Resultado?
	if type(raw) ~= "table" or type(raw.caixa) ~= "string" then
		return nil
	end
	return {
		caixa = raw.caixa,
		versao = num(raw.versao, 0, 1e6, 0),
		item = if type(raw.item) == "string" then raw.item else nil,
		raridade = if type(raw.raridade) == "string" then raw.raridade else nil,
		repetido = raw.repetido == true,
		fragmentos = num(raw.fragmentos, 0, CaixaRegras.MAX_SALDO, 0),
		origem = if type(raw.origem) == "string" then raw.origem else "?",
		t = num(raw.t, 0, 1e11, 0),
		id = if type(raw.id) == "string" then raw.id else nil,
	}
end

-- perfil salvo (qualquer forma) -> bloco válido
function CaixaRegras.sanear(raw: any): Dados
	local d = CaixaRegras.padrao()
	if type(raw) ~= "table" then
		return d
	end
	d.bilhetes = num(raw.bilhetes, 0, CaixaRegras.MAX_SALDO, 0)
	d.fragmentos = num(raw.fragmentos, 0, CaixaRegras.MAX_SALDO, 0)
	for _, campo in { "abertas", "pity" } do
		local src = raw[campo]
		if type(src) == "table" then
			for k, v in src do
				if type(k) == "string" and Caixas.get(k) then
					(d :: any)[campo][k] = num(v, 0, 1e9, 0)
				end
			end
		end
	end
	if type(raw.hist) == "table" then
		for _, r in raw.hist do
			local ok = resultado(r)
			if ok then
				table.insert(d.hist, ok)
			end
		end
		while #d.hist > CaixaRegras.HIST do
			table.remove(d.hist, 1)
		end
	end
	if type(raw.recibos) == "table" then
		for id, r in raw.recibos do
			local ok = resultado(r)
			if type(id) == "string" and ok then
				d.recibos[id] = ok
			end
		end
	end
	d.dia = num(raw.dia, -1, 1e7, -1)
	d.hoje = num(raw.hoje, 0, 1000, 0)
	d.boasVindas = raw.boasVindas == true
	if type(raw.on) == "table" then
		for _, k in { "tag", "mol" } do
			local v = raw.on[k]
			if type(v) == "string" and #v < 48 then
				(d.on :: any)[k] = v
			end
		end
	end
	return d
end

local function guardaRecibos(d: Dados)
	local list = {}
	for id, r in d.recibos do
		table.insert(list, { id = id, t = r.t })
	end
	if #list <= CaixaRegras.MAX_RECIBOS then
		return
	end
	table.sort(list, function(a, b)
		return a.t > b.t
	end)
	for i = CaixaRegras.MAX_RECIBOS + 1, #list do
		d.recibos[list[i].id] = nil
	end
end

local function registra(d: Dados, r: Resultado)
	table.insert(d.hist, r)
	while #d.hist > CaixaRegras.HIST do
		table.remove(d.hist, 1)
	end
end

-- posse do item no perfil `p` (passes: Game Passes de skin que o jogador tem)
function CaixaRegras.possui(p: any, item: string, passes: { [string]: boolean }?): boolean
	return Cosmeticos.possui(item, p.campaign.owned, p.skins.owned, passes)
end

-- chances finais deste jogador (o que a tela mostra antes de comprar ou abrir)
function CaixaRegras.odds(p: any, caixaId: string, passes: { [string]: boolean }?): { any }?
	local c = Caixas.get(caixaId)
	if not c then
		return nil
	end
	local contador = if Caixas.PITY.enabled then p.caixas.pity[caixaId] or 0 else nil
	return Caixas.odds(c, Cosmeticos.info, function(item: string): boolean
		return CaixaRegras.possui(p, item, passes)
	end, contador)
end

-- Sorteia e aplica UM resultado no perfil `p`. `n` = inteiro uniforme em [0, Caixas.ESCALA) do
-- servidor. Não confere bilhete nem recibo (quem chama confere). Devolve o resultado.
function CaixaRegras.aplicar(
	p: any,
	caixaId: string,
	n: number,
	now: number,
	origem: string,
	passes: { [string]: boolean }?,
	recibo: string?
): Resultado
	local c = Caixas.get(caixaId)
	assert(c, "caixa desconhecida")
	local d: Dados = p.caixas
	local contador = if Caixas.PITY.enabled then d.pity[caixaId] or 0 else nil
	local pesos = Caixas.pesosEfetivos(c, Cosmeticos.info, contador)
	local e = Caixas.escolher(pesos, n)
	local info = Cosmeticos.info(e.item)
	assert(info, "item sem cadastro")
	local rar = Caixas.raridade(info.raridade)
	assert(rar, "raridade")
	local dup = CaixaRegras.possui(p, e.item, passes)
	local frag = 0
	if dup then
		frag = rar.fragmentos
		d.fragmentos = math.min(CaixaRegras.MAX_SALDO, d.fragmentos + frag)
	else
		Cosmeticos.conceder(p, e.item)
	end
	d.abertas[caixaId] = (d.abertas[caixaId] or 0) + 1
	if Caixas.PITY.enabled then
		d.pity[caixaId] = Caixas.proximoContador(d.pity[caixaId] or 0, info.raridade)
	end
	local r: Resultado = {
		caixa = caixaId,
		versao = c.versao,
		item = e.item,
		raridade = info.raridade,
		repetido = dup,
		fragmentos = frag,
		origem = origem,
		t = now,
		id = recibo,
	}
	registra(d, r)
	if recibo then
		d.recibos[recibo] = r
		guardaRecibos(d)
	end
	return r
end

-- Caixa gratuita com bilhete. Devolve (resultado, nil) ou (nil, motivo).
function CaixaRegras.abrirGratuita(
	p: any,
	caixaId: string,
	n: number,
	now: number,
	passes: { [string]: boolean }?
): (Resultado?, string?)
	local c = Caixas.get(caixaId)
	if not c or c.tipo ~= "gratuita" then
		return nil, "caixa"
	end
	local custo = c.bilhetes or 1
	if p.caixas.bilhetes < custo then
		return nil, "bilhetes"
	end
	p.caixas.bilhetes -= custo
	return CaixaRegras.aplicar(p, caixaId, n, now, "bilhete", passes, nil), nil
end

-- Recibo de caixa paga. Idempotente: o mesmo PurchaseId devolve o resultado já gravado (sem novo
-- sorteio). `restrito`: o PolicyService não libera itens aleatórios pagos para o jogador (ou não
-- respondeu): Fragmentos fixos, sem sorteio. Devolve (resultado, novo).
function CaixaRegras.recibo(
	p: any,
	caixaId: string,
	purchaseId: string,
	n: number,
	now: number,
	restrito: boolean,
	passes: { [string]: boolean }?
): (Resultado, boolean)
	local d: Dados = p.caixas
	local antes = d.recibos[purchaseId]
	if antes then
		return antes, false
	end
	local c = Caixas.get(caixaId)
	assert(c and c.tipo == "paga", "caixa paga desconhecida")
	if restrito then
		local frag = CaixaRegras.FIXO_RESTRITO[caixaId] or 100
		d.fragmentos = math.min(CaixaRegras.MAX_SALDO, d.fragmentos + frag)
		local r: Resultado = {
			caixa = caixaId,
			versao = c.versao,
			item = nil,
			raridade = nil,
			repetido = false,
			fragmentos = frag,
			origem = "restrito",
			t = now,
			id = purchaseId,
		}
		registra(d, r)
		d.recibos[purchaseId] = r
		guardaRecibos(d)
		return r, true
	end
	return CaixaRegras.aplicar(p, caixaId, n, now, "recibo", passes, purchaseId), true
end

-- itens da troca (todos os que saem em alguma caixa), com o custo da raridade
function CaixaRegras.troca(): { { item: string, raridade: string, custo: number } }
	local seen: { [string]: boolean } = {}
	local out = {}
	for _, c in Caixas.CAIXAS do
		for _, e in c.itens do
			if not seen[e.item] then
				seen[e.item] = true
				local info = Cosmeticos.info(e.item)
				local rar = info and Caixas.raridade(info.raridade)
				if info and rar then
					table.insert(out, { item = e.item, raridade = info.raridade, custo = rar.custo })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.custo ~= b.custo then
			return a.custo < b.custo
		end
		return a.item < b.item
	end)
	return out
end

-- Troca Fragmentos por um item garantido. Devolve (resultado, nil) ou (nil, motivo).
function CaixaRegras.trocar(p: any, item: string, now: number, passes: { [string]: boolean }?): (Resultado?, string?)
	local custo: number? = nil
	local rar: string? = nil
	for _, t in CaixaRegras.troca() do
		if t.item == item then
			custo, rar = t.custo, t.raridade
		end
	end
	if not custo then
		return nil, "item"
	end
	if CaixaRegras.possui(p, item, passes) then
		return nil, "possui"
	end
	if p.caixas.fragmentos < custo then
		return nil, "fragmentos"
	end
	p.caixas.fragmentos -= custo
	Cosmeticos.conceder(p, item)
	local r: Resultado = {
		caixa = "troca",
		versao = 0,
		item = item,
		raridade = rar,
		repetido = false,
		fragmentos = -custo,
		origem = "troca",
		t = now,
		id = nil,
	}
	registra(p.caixas, r)
	return r, nil
end

-- Bilhetes ganhos jogando (missão cumprida, boas-vindas). Teto por dia UTC. Devolve quantos entraram.
function CaixaRegras.ganhar(p: any, n: number, dia: number, motivo: string): number
	local d: Dados = p.caixas
	if motivo == "boas_vindas" then
		if d.boasVindas then
			return 0
		end
		d.boasVindas = true
		d.bilhetes += n
		return n
	end
	if d.dia ~= dia then
		d.dia, d.hoje = dia, 0
	end
	local dar = math.clamp(math.min(n, CaixaRegras.TETO_DIA - d.hoje), 0, n)
	d.hoje += dar
	d.bilhetes = math.min(CaixaRegras.MAX_SALDO, d.bilhetes + dar)
	return dar
end

-- plaqueta ou moldura escolhida (só o que tem; "" tira)
function CaixaRegras.equipar(p: any, slot: string, item: string): boolean
	if slot ~= "tag" and slot ~= "mol" then
		return false
	end
	if item == "" then
		(p.caixas.on :: any)[slot] = nil
		return true
	end
	local info = Cosmeticos.info(item)
	local kind = if slot == "tag" then "plaqueta" else "moldura"
	if not info or info.kind ~= kind or not p.campaign.owned[item] then
		return false
	end
	(p.caixas.on :: any)[slot] = item
	return true
end

return CaixaRegras
