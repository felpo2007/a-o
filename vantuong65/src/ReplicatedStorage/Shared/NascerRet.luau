--!strict
-- D-243 (prompt, seção 11): os conjuntos de nascer dos mapas retangulares. Módulo PURO. Cada conjunto é um lugar
-- pronto do cenário (tools/mapas_ret.py), com duas saídas em direções diferentes. Aqui fica a regra de quais valem
-- agora; quem mede inimigo e visada é o servidor (Modules/NascerRetService). O QG é sempre a reserva.
-- Posições em studs do mundo; distâncias em metros.
local NascerRet = {}

NascerRet.C = {
	-- Linha de Frente: atrás da disputa, a cerca de 20-35 s a pé do setor ativo
	frenteAtrasM = 50,
	frenteMinM = 90, -- medido com caminho real no Studio: abaixo disto, menos de 20 s a pé
	frenteMaxM = 155, -- acima disto, mais de 35 s
	porFlanco = 2,
	-- Comboio: a escolta 60-120 m atrás da referência; a defesa à frente, na lateral da estrada
	escoltaMinM = 60,
	escoltaMaxM = 120,
	defesaMinM = 70, -- medido com caminho real: mais perto, a defesa nasceria quase em cima do comboio
	defesaMaxM = 150,
	-- PROVISÓRIO: margens de segurança do conjunto
	inimigoPertoM = 30,
	inimigoVistaM = 70,
	vagaRaioM = 2.2,
	vagas = 8,
}

export type Conjunto = {
	id: string,
	x: number,
	z: number,
	s: number, -- distância na estrada do comboio (0 na Linha de Frente)
	sx1: number,
	sz1: number,
	sx2: number,
	sz2: number,
}

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- Linha de Frente: os mais perto do setor ativo (ax, az), por flanco, atrás da disputa do lado pedido.
function NascerRet.frente(lista: { Conjunto }, ax: number, az: number, oeste: boolean, M: number): { Conjunto }
	local C = NascerRet.C
	local norte: { { c: Conjunto, d: number } } = {}
	local sul: { { c: Conjunto, d: number } } = {}
	for _, c in lista do
		local atras = (if oeste then ax - c.x else c.x - ax) * M
		local d = dist(c.x, c.z, ax, az) * M
		if atras >= C.frenteAtrasM and d >= C.frenteMinM and d <= C.frenteMaxM then
			table.insert(if c.z < 0 then norte else sul, { c = c, d = d })
		end
	end
	local out: { Conjunto } = {}
	for _, flanco in { norte, sul } do
		table.sort(flanco, function(a, b)
			return if a.d ~= b.d then a.d < b.d else a.c.id < b.c.id
		end)
		for i = 1, math.min(C.porFlanco, #flanco) do
			table.insert(out, flanco[i].c)
		end
	end
	return out
end

-- Comboio: a escolta nasce atrás da referência s e a defesa à frente dela. Além da janela, entra o anterior
-- mais próximo: é o conjunto seguro quando os da janela estão comprometidos ou quando a janela está vazia.
function NascerRet.comboio(lista: { Conjunto }, s: number, escolta: boolean): { Conjunto }
	local C = NascerRet.C
	local out: { Conjunto } = {}
	local anterior: Conjunto? = nil
	local folga = math.huge
	for _, c in lista do
		local d = c.s - s
		local vale = if escolta
			then d <= -C.escoltaMinM and d >= -C.escoltaMaxM
			else d >= C.defesaMinM and d <= C.defesaMaxM
		if vale then
			table.insert(out, c)
		else
			local alem = if escolta then -C.escoltaMaxM - d else d - C.defesaMaxM
			if alem > 0 and alem < folga then
				anterior, folga = c, alem
			end
		end
	end
	if anterior then
		table.insert(out, anterior)
	end
	return out
end

-- Motivo de o conjunto não servir agora (nil = serve). inimigos: lista plana x, z em metros.
-- temVista(ex, ez), em studs: linha livre do conjunto até esse inimigo.
function NascerRet.comprometido(
	c: Conjunto,
	inimigos: { number },
	M: number,
	temVista: ((ex: number, ez: number) -> boolean)?
): string?
	local C = NascerRet.C
	local cx, cz = c.x * M, c.z * M
	local visto = false
	for i = 1, #inimigos - 1, 2 do
		local d = dist(inimigos[i], inimigos[i + 1], cx, cz)
		if d < C.inimigoPertoM then
			return "inimigo próximo"
		elseif not visto and d < C.inimigoVistaM and temVista and temVista(inimigos[i] / M, inimigos[i + 1] / M) then
			visto = true
		end
	end
	return if visto then "inimigo à vista" else nil
end

-- A n-ésima vaga do conjunto: lugar em volta do centro e a saída para onde o soldado olha (alterna as duas).
function NascerRet.vaga(c: Conjunto, n: number, M: number): (number, number, number, number)
	local C = NascerRet.C
	local k = (n - 1) % C.vagas
	local a = k / C.vagas * 2 * math.pi
	local r = C.vagaRaioM / M
	local x, z = c.x + math.cos(a) * r, c.z + math.sin(a) * r
	if k % 2 == 0 then
		return x, z, c.sx1, c.sz1
	end
	return x, z, c.sx2, c.sz2
end

-- A n-ésima vaga do QG (a reserva): espiral dentro do pátio da base.
function NascerRet.vagaBase(hx: number, hz: number, n: number, M: number): (number, number)
	local a = n * 2.399963
	local r = (2.5 + ((n - 1) % 6) * 1.7) / M
	return hx + math.cos(a) * r, hz + math.sin(a) * r
end

return NascerRet
