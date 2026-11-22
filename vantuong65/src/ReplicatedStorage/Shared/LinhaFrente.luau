--!strict
-- D-243: regras da Linha de Frente (prompt, seção 6). Módulo PURO: o servidor conta quem está na área e chama
-- LinhaFrente.passo. A barra vai de -1 (Leste conquista) a +1 (Oeste conquista); o setor ativo é um índice de
-- 1 (A) a 5 (E). Oeste conquistando anda para leste (+1), Leste conquistando anda para oeste (-1).
local MapasRet = require(script and (script :: any).Parent.MapasRet or "./MapasRet") :: any

local LinhaFrente = {}

local EPS = 1e-9

export type Fase = "disputa" | "transicao" | "final" | "fim"
export type Estado = {
	t: number, -- segundos de partida
	ativo: number,
	barra: number,
	fase: Fase,
	vazio: number, -- segundos com a área vazia
	transicaoAte: number?,
	finalAte: number?,
	relogioEsgotado: boolean,
	vencedor: string?, -- "oeste" | "leste" | "empate"
	motivo: string?, -- "conquista" | "territorio" | "disputa_final" | "empate"
	conquistas: number,
}

function LinhaFrente.novo(regras: any?): Estado
	local _ = regras
	return {
		t = 0,
		ativo = MapasRet.FRENTE.inicio,
		barra = 0,
		fase = "disputa",
		vazio = 0,
		transicaoAte = nil,
		finalAte = nil,
		relogioEsgotado = false,
		vencedor = nil,
		motivo = nil,
		conquistas = 0,
	}
end

-- Segundos do neutro à conquista com n jogadores (n >= 1).
function LinhaFrente.tempoCaptura(n: number, regras: any?): number
	local r = regras or MapasRet.FRENTE.regras
	return r.capturaS[math.clamp(n, 1, #r.capturaS)]
end

local function encerra(s: Estado, quem: string, motivo: string)
	s.fase = "fim"
	s.vencedor = quem
	s.motivo = motivo
	s.transicaoAte, s.finalAte = nil, nil
end

-- O vencedor por território com o índice já registrado (D/E: Oeste; A/B: Leste).
local function porTerritorio(s: Estado)
	encerra(s, if s.ativo > 3 then "oeste" else "leste", "territorio")
end

-- Uma conquista: registra o novo índice ANTES da transição. Devolve true se a partida acabou.
local function conquista(s: Estado, quem: string, r: any): boolean
	s.conquistas += 1
	if s.fase == "final" then
		encerra(s, quem, "disputa_final")
		return true
	end
	local proximo = s.ativo + (if quem == "oeste" then 1 else -1)
	if proximo < 1 or proximo > #MapasRet.FRENTE.setores then
		encerra(s, quem, "conquista")
		return true
	end
	s.ativo = proximo
	s.barra = 0
	s.vazio = 0
	s.fase = "transicao"
	s.transicaoAte = s.t + r.transicaoS
	return false
end

local function moveBarra(s: Estado, dt: number, oeste: number, leste: number, r: any)
	if oeste > 0 and leste > 0 then
		s.vazio = 0 -- congelada, com qualquer número de cada lado
		return
	end
	if oeste == 0 and leste == 0 then
		local antes = s.vazio
		s.vazio += dt
		-- só o tempo depois dos 10 s de área vazia devolve a barra
		local passou = math.max(0, s.vazio - math.max(antes, r.vazioS))
		if passou > 0 then
			local d = passou * r.retornoPorS
			s.barra = if s.barra > 0 then math.max(0, s.barra - d) else math.min(0, s.barra + d)
		end
		return
	end
	s.vazio = 0
	if oeste > 0 then
		s.barra = math.min(1, s.barra + dt / LinhaFrente.tempoCaptura(oeste, r))
	else
		s.barra = math.max(-1, s.barra - dt / LinhaFrente.tempoCaptura(leste, r))
	end
end

-- Um passo de simulação. oeste/leste: combatentes válidos no volume do setor ativo agora.
function LinhaFrente.passo(s: Estado, dt: number, oeste: number, leste: number, regras: any?)
	if s.fase == "fim" then
		return
	end
	local r = regras or MapasRet.FRENTE.regras
	s.t += dt
	-- 1. a captura vem antes do relógio: conquista terminal no último passo tem prioridade
	if s.fase == "disputa" or s.fase == "final" then
		moveBarra(s, dt, oeste, leste, r)
		if s.barra >= 1 - EPS then
			if conquista(s, "oeste", r) then
				return
			end
		elseif s.barra <= -1 + EPS then
			if conquista(s, "leste", r) then
				return
			end
		end
	end
	-- 2. o relógio normal
	if not s.relogioEsgotado and s.t >= r.duracaoS - EPS then
		s.relogioEsgotado = true
		if s.fase == "transicao" then
			if s.ativo ~= 3 then
				porTerritorio(s) -- usa o índice já registrado na conquista
				return
			end
			-- transição para C: termina a transição e só então começam os 90 s, com a barra neutra
		elseif s.ativo == 3 then
			s.fase = "final" -- a barra existente é preservada
			s.finalAte = s.t + r.finalS
		else
			porTerritorio(s)
			return
		end
	end
	-- 3. fim da transição
	if s.fase == "transicao" and s.t >= (s.transicaoAte :: number) - EPS then
		s.transicaoAte = nil
		if s.relogioEsgotado then
			s.fase = "final"
			s.finalAte = s.t + r.finalS
		else
			s.fase = "disputa"
		end
	end
	-- 4. fim da disputa final sem conquista
	if s.fase == "final" and s.t >= (s.finalAte :: number) - EPS then
		encerra(s, "empate", "empate")
	end
end

-- Texto curto da situação para a interface.
function LinhaFrente.setorAtivo(s: Estado): any
	return MapasRet.FRENTE.setores[s.ativo]
end

return LinhaFrente
