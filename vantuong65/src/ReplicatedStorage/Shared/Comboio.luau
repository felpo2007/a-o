--!strict
-- D-243: regras do Comboio (prompt, seções 9 e 10). Módulo PURO: uma unidade lógica com a distância `s` do ponto
-- médio. Os caminhões são só a imagem dela, em s - 9 e s + 9. O servidor conta quem escolta, contesta e repara.
local MapasRet = require(script and (script :: any).Parent.MapasRet or "./MapasRet") :: any

local Comboio = {}

local EPS = 1e-9

export type Corrida = {
	t: number,
	s: number,
	comprimento: number,
	cps: { number }, -- distância de cada checkpoint; o último é a entrega
	cp: number, -- próximo checkpoint
	naParada: boolean,
	cpProg: number, -- segundos acumulados na parada atual
	integridade: number,
	protegidoAte: number,
	imobilizadoAte: number?,
	imobNoTrecho: number,
	reparo: number, -- pessoa-segundos
	danoPendente: number,
	janelaDano: { { t: number, v: number } }, -- dano aplicado no último segundo
	vistos: { [any]: number },
	entregue: boolean,
	tEntrega: number?,
}

export type Presenca = { escolta: number, defesa: number, reparadores: number }

function Comboio.nova(cps: { number }, comprimento: number, regras: any?): Corrida
	local r = regras or MapasRet.COMBOIO.regras
	return {
		t = 0,
		s = 0,
		comprimento = comprimento,
		cps = cps,
		cp = 1,
		naParada = false,
		cpProg = 0,
		integridade = r.integridade,
		protegidoAte = -math.huge,
		imobilizadoAte = nil,
		imobNoTrecho = 0,
		reparo = 0,
		danoPendente = 0,
		janelaDano = {},
		vistos = {},
		entregue = false,
		tEntrega = nil,
	}
end

-- Registra um evento de dano. `id` é único por evento: atingir os dois caminhões não conta duas vezes.
function Comboio.dano(c: Corrida, id: any, valor: number)
	if c.entregue or valor <= 0 or c.vistos[id] then
		return
	end
	c.vistos[id] = c.t
	if c.t < c.protegidoAte or c.imobilizadoAte then
		return
	end
	c.danoPendente += valor
end

-- O teto vale em qualquer janela de 1 s, seja qual for o passo do servidor; o que passa dele se perde.
local function aplicaDano(c: Corrida, r: any)
	local usado = 0
	for i = #c.janelaDano, 1, -1 do
		local q = c.janelaDano[i]
		if q.t <= c.t - 1 + EPS then
			table.remove(c.janelaDano, i)
		else
			usado += q.v
		end
	end
	local efetivo = math.min(c.danoPendente, math.max(0, r.danoPorS - usado))
	c.danoPendente = 0
	for id, quando in c.vistos do
		if c.t - quando > 5 then
			c.vistos[id] = nil
		end
	end
	if efetivo <= 0 or c.t < c.protegidoAte or c.imobilizadoAte then
		return
	end
	table.insert(c.janelaDano, { t = c.t, v = efetivo })
	local resta = c.integridade - efetivo
	if resta > EPS then
		c.integridade = resta
	elseif c.imobNoTrecho >= r.imobilizacoesPorTrecho then
		-- no limite do trecho o dano não provoca outra parada
		c.integridade = math.min(c.integridade, r.integridadeNoLimite)
	else
		c.integridade = 0
		c.imobilizadoAte = c.t + r.imobilizadoS
		c.imobNoTrecho += 1
		c.reparo = 0
	end
end

local function recupera(c: Corrida, r: any)
	c.imobilizadoAte = nil
	c.reparo = 0
	c.integridade = r.recuperaIntegridade
	c.protegidoAte = c.t + r.protecaoS
end

-- Avança a corrida. e = presença válida neste passo.
function Comboio.passo(c: Corrida, dt: number, e: Presenca, regras: any?)
	if c.entregue then
		return
	end
	local r = regras or MapasRet.COMBOIO.regras
	aplicaDano(c, r)
	local pode = e.escolta > 0 and e.defesa == 0
	local resta = dt
	while resta > EPS and not c.entregue do
		local u = resta
		if c.imobilizadoAte then
			local taxa = math.min(e.reparadores, r.reparadoresMax)
			if e.defesa > 0 and not r.reparoContestado then
				taxa = 0
			end
			local ate = c.imobilizadoAte :: number
			u = math.min(u, ate - c.t)
			if taxa > 0 then
				u = math.min(u, (r.reparoPessoaS - c.reparo) / taxa)
			elseif not r.reparoRetido then
				c.reparo = 0
			end
			u = math.max(u, 0)
			c.reparo += taxa * u
			c.t += u
			if c.reparo >= r.reparoPessoaS - EPS or c.t >= ate - EPS then
				recupera(c, r)
			end
		elseif c.naParada then
			if pode then
				u = math.min(u, r.checkpointS - c.cpProg)
				c.cpProg += u
			end
			c.t += u
			if pode and c.cpProg >= r.checkpointS - EPS then
				c.cpProg = 0
				c.naParada = false
				c.imobNoTrecho = 0 -- integridade e proteção ficam como estão
				if c.cp >= #c.cps then
					c.entregue = true
					c.tEntrega = c.t
				else
					c.cp += 1
				end
			end
		elseif pode then
			local alvo = c.cps[c.cp]
			u = math.min(u, (alvo - c.s) / r.velocidadeMS)
			c.s += r.velocidadeMS * u
			c.t += u
			if c.s >= alvo - EPS then
				c.s = alvo
				c.naParada = true
			end
		else
			c.t += u
		end
		resta -= u
	end
end

-- O estado real, com os nomes que a interface mostra.
Comboio.TEXTOS = {
	aguardando = "Aguardando escolta",
	avancando = "Avançando",
	contestado = "Contestado",
	imobilizado = "Imobilizado",
	reparando = "Reparando",
	checkpoint = "Concluindo checkpoint",
	entregue = "Entregue",
}

function Comboio.estado(c: Corrida, e: Presenca): string
	if c.entregue then
		return "entregue"
	elseif c.imobilizadoAte then
		return if e.reparadores > 0 then "reparando" else "imobilizado"
	elseif e.defesa > 0 then
		return "contestado"
	elseif e.escolta == 0 then
		return "aguardando"
	elseif c.naParada then
		return "checkpoint"
	end
	return "avancando"
end

-- Centros dos dois caminhões na trajetória: a unidade lógica fica no meio deles.
function Comboio.centros(s: number, regras: any?): (number, number)
	local r = regras or MapasRet.COMBOIO.regras
	return s - r.separacaoM / 2, s + r.separacaoM / 2
end

-- Compara as duas rodadas. Devolve 1, 2 ou 0 (empate) e o critério usado.
function Comboio.resultado(a: Corrida, b: Corrida): (number, string)
	if a.entregue ~= b.entregue then
		return if a.entregue then 1 else 2, "entrega"
	end
	if a.entregue then
		local ta, tb = a.tEntrega :: number, b.tEntrega :: number
		if ta ~= tb then
			return if ta < tb then 1 else 2, "tempo"
		end
		return 0, "tempo"
	end
	if a.s ~= b.s then
		return if a.s > b.s then 1 else 2, "distancia"
	end
	if a.cp == b.cp and a.cpProg ~= b.cpProg then
		return if a.cpProg > b.cpProg then 1 else 2, "captura"
	end
	return 0, "empate"
end

return Comboio
