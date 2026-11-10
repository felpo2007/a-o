--!strict
-- Chuva tropical súbita (Parte 11, "Depois"): uma pancada no meio da partida reduz a visão, abafa
-- os passos e enlameia o chão. Módulo puro: sorteio (semente da partida), intensidade no tempo e
-- efeitos. Ressalva histórica: a Operação Starlite (18–24/08/1965) foi marcada por calor extremo,
-- com muitas baixas por exaustão; em agosto a costa de Quảng Ngãi ainda tem pancadas de tarde,
-- então a chuva entra como evento pouco frequente, não como regra (números PLACEHOLDER).
local Weather = {}

Weather.CHANCE = 0.25 -- partidas com pancada
Weather.RAMP_UP_S = 60
Weather.RAMP_DOWN_S = 90
Weather.MIN_HOLD_S = 6 * 60
Weather.MAX_HOLD_S = 15 * 60
Weather.EARLIEST_S = 10 * 60 -- nunca nos primeiros 10 min

export type Shower = { start: number, peakAt: number, endAt: number, finishAt: number }

-- Sorteio da pancada para uma partida de `duration` s. rolls: números em [0,1).
function Weather.schedule(duration: number, rolls: () -> number): Shower?
	if rolls() >= Weather.CHANCE then
		return nil
	end
	local hold = Weather.MIN_HOLD_S + rolls() * (Weather.MAX_HOLD_S - Weather.MIN_HOLD_S)
	local total = Weather.RAMP_UP_S + hold + Weather.RAMP_DOWN_S
	local latest = duration - total
	if latest <= Weather.EARLIEST_S then
		return nil -- partida curta demais (ex.: Skirmish)
	end
	local start = Weather.EARLIEST_S + rolls() * (latest - Weather.EARLIEST_S)
	local peakAt = start + Weather.RAMP_UP_S
	local endAt = peakAt + hold
	return { start = start, peakAt = peakAt, endAt = endAt, finishAt = endAt + Weather.RAMP_DOWN_S }
end

-- Intensidade 0..1 no instante t (s desde o início da partida)
function Weather.intensity(sh: Shower?, t: number): number
	if not sh or t <= sh.start or t >= sh.finishAt then
		return 0
	end
	if t < sh.peakAt then
		return (t - sh.start) / Weather.RAMP_UP_S
	elseif t <= sh.endAt then
		return 1
	end
	return 1 - (t - sh.endAt) / Weather.RAMP_DOWN_S
end

-- Efeitos de uma intensidade i (0..1)
function Weather.sightFactor(i: number): number
	return 1 - 0.5 * i -- bots enxergam até metade da distância na chuva forte
end

function Weather.footstepVolume(i: number): number
	return 1 - 0.6 * i -- a chuva cobre os passos
end

function Weather.mudSpeed(i: number): number
	return 1 - 0.1 * i -- lama: até 10% mais devagar
end

return Weather
