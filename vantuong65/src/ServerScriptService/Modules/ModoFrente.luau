--!strict
-- D-243: a Linha de Frente na partida. As regras são do Shared/LinhaFrente; aqui fica o que depende do jogo:
-- quem conta na área, a tradução para o estado de captura que o HUD, os bots e o nascer já leem e os eventos.
-- O Oeste é o VC e o Leste os EUA. No estado de captura, +1 = EUA e -1 = VC; na barra da frente, +1 = Oeste.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LinhaFrente = require(ReplicatedStorage.Shared.LinhaFrente)
local MapasRet = require(ReplicatedStorage.Shared.MapasRet) :: any
local Combatants = require(script.Parent.Combatants)

local ModoFrente = {}

local M = MapasRet.M_POR_STUD
local R = MapasRet.FRENTE.regras

-- O estado de captura espelha a frente: atrás do setor ativo, cada lado é dono do seu território.
function ModoFrente.sincroniza(st: any, f: LinhaFrente.Estado)
	for i = 1, #st.owner do
		st.active[i] = i == f.ativo and f.fase ~= "fim"
		if i < f.ativo then
			st.owner[i], st.progress[i] = "VC", -1
		elseif i > f.ativo then
			st.owner[i], st.progress[i] = "US", 1
		else
			st.owner[i], st.progress[i] = "Neutral", -f.barra
		end
	end
end

-- Quem conta no setor ativo: vivo, apto, a pé e dentro do volume (fora do telhado e de sob o piso).
function ModoFrente.conta(sp: any, pisoY: number, raio: number): { US: number, VC: number }
	local c = { US = 0, VC = 0 }
	local r2 = raio * raio
	for _, e in Combatants.list() do
		local root = Combatants.root(e)
		local hum = Combatants.humanoid(e)
		if (e.faction == "US" or e.faction == "VC") and root and hum and Combatants.active(e) and not hum.SeatPart then
			local p = root.Position
			local dx, dz = p.X - sp.x, p.Z - sp.z
			local dy = p.Y - pisoY
			if dx * dx + dz * dz <= r2 and dy >= -0.5 / M and dy <= (R.alturaCapturaM + 1.1) / M then
				local k = e.faction :: string;
				(c :: any)[k] += 1
			end
		end
	end
	return c
end

-- Um passo. Devolve os eventos no formato do Capture.step e o vencedor ("US", "VC", "draw" ou nil).
function ModoFrente.passo(st: any, f: LinhaFrente.Estado, c: { US: number, VC: number }, dt: number): ({ any }, string?)
	local antes, conquistas = f.ativo, f.conquistas
	LinhaFrente.passo(f, dt, c.VC, c.US)
	local eventos = {}
	if f.conquistas > conquistas then
		local quem = if f.fase == "fim"
			then (if f.vencedor == "oeste" then "VC" else "US")
			elseif f.ativo > antes then "VC"
			else "US"
		table.insert(eventos, { kind = "captured", sector = antes, team = quem })
		if f.fase ~= "fim" then
			table.insert(eventos, { kind = "advanced", sector = f.ativo, team = quem })
		end
	end
	ModoFrente.sincroniza(st, f)
	if f.fase == "fim" then
		return eventos, if f.vencedor == "oeste" then "VC" elseif f.vencedor == "leste" then "US" else "draw"
	end
	return eventos, nil
end

-- O tempo-limite que o relógio do HUD mostra (segundos de partida).
function ModoFrente.limite(f: LinhaFrente.Estado): number
	if f.finalAte then
		return f.finalAte
	elseif f.relogioEsgotado and f.transicaoAte then
		return f.transicaoAte
	end
	return R.duracaoS
end

-- O que o cliente precisa para desenhar A-B-C-D-E, a direção do avanço e a transição.
function ModoFrente.publica(f: LinhaFrente.Estado): any
	return {
		ativo = f.ativo,
		fase = f.fase,
		barra = f.barra,
		transicaoS = if f.transicaoAte then math.max(0, f.transicaoAte - f.t) else 0,
		finalS = if f.finalAte then math.max(0, f.finalAte - f.t) else 0,
		motivo = f.motivo,
	}
end

return ModoFrente
