--!strict
-- Bot motorista e atirador de veículo de chão (D-90). Módulo PURO, testado no Lune
-- (tests/luau/botsmov.luau). Gera só acelerador e volante (-1..1), as mesmas entradas do jogador:
-- a física é a do Shared/VehicleDrive no VehicleService. Genérico de propósito: a lagarta gira no
-- lugar (caps.pivot); um carro com rodas (o do VC, que vem depois) não gira e manobra de ré.
-- Sinais (VehicleDrive): steer > 0 vira para a direita (o rumo do Roblox diminui).
local BotBrain = require(script and (script :: any).Parent.BotBrain or "./BotBrain") :: any
local BotMove = require(script and (script :: any).Parent.BotMove or "./BotMove") :: any

local BotDriver = {}

export type Caps = { pivot: boolean } -- gira no lugar?

-- Lagarta e anfíbio giram no lugar; qualquer outro tipo (rodas) não.
function BotDriver.caps(kind: string): Caps
	return { pivot = kind == "tracked" or kind == "amphibious" }
end

-- Velocidade desejada (m/s): fração do teto do chão, menor na curva fechada e para parar no ponto.
function BotDriver.desiredSpeed(topMs: number, distStopM: number, cornerRad: number, decel: number): number
	local V = BotBrain.VEHICLE
	local v = topMs * V.cruiseFrac
	if cornerRad > math.rad(35) then
		v = math.min(v, topMs * V.cornerFrac)
	end
	v = math.min(v, math.sqrt(2 * decel * math.max(distStopM - V.arriveM * 0.5, 0)))
	return v
end

-- Acelerador e volante para ir de (x, z) com rumo yaw e velocidade v (m/s, + à frente) até
-- (tx, tz) a wantV m/s. Devolve também o erro de rumo (rad, + = o alvo está à esquerda).
function BotDriver.control(
	yaw: number,
	v: number,
	x: number,
	z: number,
	tx: number,
	tz: number,
	wantV: number,
	caps: Caps
): (number, number, number)
	local V = BotBrain.VEHICLE
	local dx, dz = tx - x, tz - z
	if dx * dx + dz * dz < 1e-6 then
		return if v > 0.3 then -1 else 0, 0, 0
	end
	local err = BotMove.wrap(BotMove.yawTo(dx, dz) - yaw)
	local aerr = math.abs(err)
	-- lagarta devagar com o alvo de lado ou atrás: para e gira no lugar
	if caps.pivot and aerr > math.rad(V.pivotDeg) and math.abs(v) < 2 then
		local thr = if v > 0.3 then -1 elseif v < -0.3 then 1 else 0
		return thr, if err > 0 then -1 else 1, err
	end
	-- rodas com o alvo atrás: manobra de ré (de ré a traseira vai para o lado do comando)
	if not caps.pivot and aerr > math.rad(110) and wantV > 0 then
		return -0.6, if err > 0 then 1 else -1, err
	end
	local steer = math.clamp(-V.steerGain * err, -1, 1)
	local target = wantV * math.max(0.2, math.cos(math.min(aerr, math.pi / 2)))
	local thr: number
	if target < 0.05 then
		thr = if v > 0.3 then -1 else 0
	else
		thr = math.clamp((target - v) * V.speedGain + 0.15, -1, 1)
	end
	return thr, steer, err
end

-- Torre ou reparo girando para o alvo (rad), limitado pela ficha (°/s).
function BotDriver.turret(cur: number, want: number, degS: number, dt: number): number
	return BotMove.yawStep(cur, want, math.rad(degS), dt)
end

-- Que arma o atirador usa: "m60" (reparo), "coax" (metralhadora do M48), "main" (canhão de 90 mm
-- ou o 106 do Ontos) ou nil (segura o fogo). near: inimigos a até 6 m do alvo; covered: o alvo
-- está atrás de parede ou dique; mainReady: canhão carregado; tubes: tubos do Ontos.
function BotDriver.gunFor(
	weapon: string,
	distM: number,
	near: number,
	covered: boolean,
	mainReady: boolean,
	tubes: number
): string?
	local V = BotBrain.VEHICLE
	if weapon == "m60" then
		return "m60"
	elseif weapon == "gun_90" then
		if mainReady and distM >= V.mainMinM and (near >= 2 or covered) then
			return "main"
		end
		return "coax"
	elseif weapon == "rr_106" then
		if mainReady and tubes > 1 and distM >= V.mainMinM and (near >= 2 or covered) then
			return "main"
		end
		return nil
	end
	return nil
end

return BotDriver
