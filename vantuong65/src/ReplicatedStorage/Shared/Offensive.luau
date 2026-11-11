--!strict
-- Modo Offensive (Parte 4): os EUA partem do setor 5 (leste, An Cường (2); D-63) e atacam para oeste; o VC
-- defende os 4 setores restantes em sequência. Só o setor da frente fica ativo: setor tomado pelos
-- EUA fica travado (não volta). Cada captura soma tempo ao relógio. Os EUA vencem ao tomar o
-- setor 1; o VC vence se o relógio zerar. A captura em si é a mesma do Warfare (Capture).
local Capture = require(script and (script :: any).Parent.Capture or "./Capture") :: any

local Offensive = {}

Offensive.C = {
	firstMinutes = 20, -- PLACEHOLDER (D-46): tempo para tomar o 1º setor
	bonusMinutes = 15, -- PLACEHOLDER (D-46): somados a cada setor tomado
}

export type State = {
	capture: any, -- Capture.State
	front: number, -- setor em disputa (0 = os EUA tomaram tudo)
	deadline: number, -- s desde o início da partida
	captured: { number }, -- setores tomados pelos EUA, em ordem
}
export type Event = { kind: string, sector: number, team: string }

function Offensive.new(n: number?): State
	local count = n or 5
	local owner, active = {}, {}
	for i = 1, count do
		owner[i] = if i == count then "US" else "VC"
		active[i] = i == count - 1
	end
	return {
		capture = Capture.new(owner, active),
		front = count - 1,
		deadline = Offensive.C.firstMinutes * 60,
		captured = {},
	}
end

-- Avança a captura do setor da frente. Devolve os eventos do Capture e, quando os EUA tomam a
-- frente, "advanced" (nova frente) ou "overrun" (tomaram o último setor).
function Offensive.step(st: State, counts: { { US: number, VC: number } }, dt: number): { Event }
	local out: { Event } = {}
	if st.front < 1 then
		return out
	end
	for _, ev in Capture.step(st.capture, counts, dt) do
		table.insert(out, ev)
		if ev.kind == "captured" and ev.team == "US" and ev.sector == st.front then
			st.capture.active[st.front] = false
			table.insert(st.captured, st.front)
			st.deadline += Offensive.C.bonusMinutes * 60
			st.front -= 1
			if st.front >= 1 then
				st.capture.active[st.front] = true
				table.insert(out, { kind = "advanced", sector = st.front, team = "US" })
			else
				table.insert(out, { kind = "overrun", sector = ev.sector, team = "US" })
			end
		end
	end
	return out
end

function Offensive.winner(st: State, elapsed: number): string?
	if st.front < 1 then
		return "US"
	end
	if elapsed >= st.deadline then
		return "VC"
	end
	return nil
end

function Offensive.timeLeft(st: State, elapsed: number): number
	return math.max(0, st.deadline - elapsed)
end

return Offensive
