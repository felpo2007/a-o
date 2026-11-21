--!strict
-- Pedido de nascer (D-209; prompt de interface §8). Puro, testado no Lune (tests/luau/nascer.luau).
--   - o estado de cada ponto da carta como o servidor mandou (Spawn_State): pronto, espera, bloqueado;
--   - o painel do ponto escolhido e o botão NASCER (texto, ativo, a linha do motivo), iguais no mouse,
--     no controle e no toque: a carta, o painel e a faixa de baixo mostram o mesmo destino;
--   - o ponto escolhido continua escolhido enquanto existir; se sumir ou travar, a alternativa é o
--     ponto pronto mais perto dele;
--   - os motivos de recusa do servidor (Spawn_Result) em texto para o jogador.
-- O cliente manda só o id do ponto e a rodada (ReplicatedStorage "VT65Rodada"). O servidor
-- (SpawnService) confere tudo de novo e escolhe o lugar de verdade: coordenada do cliente não entra.
local NascerPedido = {}

-- Sem resposta do servidor nem corpo novo neste tempo, o botão volta (a SpawnTransition tem os
-- limites dela, que somam menos que isto).
NascerPedido.ESPERA_S = 12

-- Motivos da recusa (código do servidor -> texto). "bloqueado" leva o motivo do ponto (o `why`).
NascerPedido.MOTIVO = {
	rodada = "A partida mudou: escolha o ponto de novo",
	fim = "A partida acabou",
	terreno = "O campo ainda está sendo preparado",
	papel = "Papel acima do seu posto",
	sem_lado = "Escolha o lado e o papel antes",
	em_campo = "Você já está em campo",
	ponto = "Este ponto não está mais disponível",
	espera = "O ponto ainda está em espera",
	bloqueado = "Ponto bloqueado",
	sem_lugar = "Sem lugar livre perto do companheiro",
	pagamento = "Sem créditos para renascer onde caiu",
	falhou = "O nascer falhou: tente de novo",
} :: { [string]: string }

-- texto da recusa (o código desconhecido vira o genérico)
function NascerPedido.motivo(cod: any, why: any): string
	if cod == "bloqueado" and type(why) == "string" and why ~= "" then
		return why
	end
	return NascerPedido.MOTIVO[if type(cod) == "string" then cod else ""] or NascerPedido.MOTIVO.falhou
end

export type Estado = "pronto" | "espera" | "bloqueado" | "nenhum"

-- o estado do ponto como o servidor mandou
function NascerPedido.estado(pt: any): Estado
	if type(pt) ~= "table" then
		return "nenhum"
	elseif pt.blocked then
		return "bloqueado"
	elseif (type(pt.wait) == "number" and pt.wait > 0) or pt.ready == false then
		return "espera"
	end
	return "pronto"
end

-- O tipo do ponto em palavras (o painel). Os ids com prefixo vêm do SpawnService, do FrontService e do
-- EventosService; o kind "squad" é o companheiro do squad.
function NascerPedido.tipo(pt: any): string
	if type(pt) ~= "table" then
		return ""
	end
	local id = if type(pt.id) == "string" then pt.id else ""
	if pt.kind == "squad" then
		return "Companheiro do squad"
	elseif id == "inplace" then
		return "Onde você caiu"
	elseif string.sub(id, 1, 3) == "lz:" then
		return "Zona de pouso"
	elseif string.sub(id, 1, 8) == "forward:" then
		return "Reunião avançada"
	elseif string.sub(id, 1, 6) == "squad:" then
		return "Reunião do squad"
	elseif string.sub(id, 1, 7) == "tunnel:" then
		return "Boca de túnel"
	elseif pt.kind == "hq" then
		return "QG do lado"
	elseif pt.kind == "garrison" then
		return "Posto fortificado"
	end
	return "Ponto de reunião"
end

export type Painel = {
	estado: string, -- um Estado ou "pedido" (o pedido mandado, esperando a resposta)
	botao: string, -- texto do botão NASCER
	ativo: boolean, -- o botão aceita confirmar
	linha: string, -- a linha do estado no painel (o motivo do bloqueio, a espera, "pronto")
	tag: string, -- a etiqueta curta (com o símbolo do estado)
}

-- O painel e o botão. pt: o ponto escolhido (nil: nenhum); pendente: o pedido já foi mandado.
function NascerPedido.painel(pt: any, pendente: boolean): Painel
	if pendente then
		return {
			estado = "pedido",
			botao = "NASCENDO…",
			ativo = false,
			linha = "Pedido enviado ao comando",
			tag = "… PEDIDO", -- no Arimo o "◷" vira um quadrado (Studio, lote 94)
		}
	end
	local e = NascerPedido.estado(pt)
	if e == "nenhum" then
		return { estado = e, botao = "NASCER", ativo = false, linha = "Escolha um ponto na carta", tag = "" }
	elseif e == "bloqueado" then
		local why = if type(pt.why) == "string" and pt.why ~= "" then pt.why else "bloqueado"
		return { estado = e, botao = "BLOQUEADO", ativo = false, linha = why, tag = "× BLOQUEADO" }
	elseif e == "espera" then
		if type(pt.wait) == "number" and pt.wait > 0 then
			local s = math.ceil(pt.wait)
			return {
				estado = e,
				botao = string.format("ESPERA %d s", s),
				ativo = false,
				linha = string.format("Libera em %d s", s),
				tag = "⏳ AGUARDANDO",
			}
		end
		local why = if type(pt.why) == "string" and pt.why ~= "" then pt.why else "espere"
		return { estado = e, botao = "ESPERE", ativo = false, linha = why, tag = "⏳ AGUARDANDO" }
	end
	return { estado = e, botao = "NASCER", ativo = true, linha = "Pronto para nascer", tag = "● PRONTO" }
end

-- o ponto da lista com este id (ou nil)
function NascerPedido.acha(lista: { any }, id: string?): any
	if not id then
		return nil
	end
	for _, pt in lista do
		if tostring(pt.id) == id then
			return pt
		end
	end
	return nil
end

-- Alternativa ao escolhido que sumiu ou travou: o ponto pronto mais perto dele (sem o "onde caiu",
-- que custa). x, z: onde o escolhido estava.
function NascerPedido.alternativa(lista: { any }, x: number?, z: number?, semId: string?): any
	local best, bestD = nil, math.huge
	for _, pt in lista do
		local id = tostring(pt.id)
		if id ~= semId and id ~= "inplace" and NascerPedido.estado(pt) == "pronto" then
			local d = if x
					and z
					and type(pt.x) == "number"
					and type(pt.z) == "number"
				then (pt.x - x) ^ 2 + (pt.z - z) ^ 2
				else 0
			if d < bestD then
				best, bestD = pt, d
			end
		end
	end
	return best
end

-- O pedido ainda conta como em curso? (mandado há menos de ESPERA_S e sem resposta)
function NascerPedido.emCurso(mandadoEm: number?, agora: number): boolean
	return mandadoEm ~= nil and agora - mandadoEm < NascerPedido.ESPERA_S
end

return NascerPedido
