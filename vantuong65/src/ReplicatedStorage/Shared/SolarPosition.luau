--!strict
-- Posição real do Sol (algoritmo da NOAA, precisão ~0,01° para 1800-2100).
-- Parte 9.6: o Roblox não considera a data; calculamos a direção real em 18/08/1965 no mapa e
-- depois ajustamos ClockTime e GeographicLatitude para o Roblox reproduzir essa direção.
local SolarPosition = {}

local rad, deg = math.rad, math.deg

-- dia juliano de uma data UTC
local function julianDay(y: number, m: number, d: number, hourUtc: number): number
	if m <= 2 then
		y -= 1
		m += 12
	end
	local A = math.floor(y / 100)
	local B = 2 - A + math.floor(A / 4)
	return math.floor(365.25 * (y + 4716)) + math.floor(30.6001 * (m + 1)) + d + B - 1524.5 + hourUtc / 24
end

-- Devolve azimute (graus a partir do norte, sentido horário) e elevação (graus, sem refração).
function SolarPosition.compute(
	year: number,
	month: number,
	day: number,
	localHour: number,
	tzHours: number,
	latDeg: number,
	lonDeg: number
): (number, number)
	local jd = julianDay(year, month, day, localHour - tzHours)
	local T = (jd - 2451545.0) / 36525
	local L0 = (280.46646 + T * (36000.76983 + T * 0.0003032)) % 360
	local M = 357.52911 + T * (35999.05029 - 0.0001537 * T)
	local e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
	local C = math.sin(rad(M)) * (1.914602 - T * (0.004817 + 0.000014 * T))
		+ math.sin(rad(2 * M)) * (0.019993 - 0.000101 * T)
		+ math.sin(rad(3 * M)) * 0.000289
	local trueLong = L0 + C
	local omega = 125.04 - 1934.136 * T
	local lambda = trueLong - 0.00569 - 0.00478 * math.sin(rad(omega))
	local eps0 = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60
	local eps = eps0 + 0.00256 * math.cos(rad(omega))
	local decl = deg(math.asin(math.sin(rad(eps)) * math.sin(rad(lambda))))
	local y = math.tan(rad(eps / 2)) ^ 2
	local eqTime = 4
		* deg(
			y * math.sin(2 * rad(L0))
				- 2 * e * math.sin(rad(M))
				+ 4 * e * y * math.sin(rad(M)) * math.cos(2 * rad(L0))
				- 0.5 * y * y * math.sin(4 * rad(L0))
				- 1.25 * e * e * math.sin(2 * rad(M))
		)
	local trueSolarMin = (localHour * 60 + eqTime + 4 * lonDeg - 60 * tzHours) % 1440
	local ha = trueSolarMin / 4 - 180
	local lat = rad(latDeg)
	local cosZen = math.sin(lat) * math.sin(rad(decl)) + math.cos(lat) * math.cos(rad(decl)) * math.cos(rad(ha))
	local zen = math.acos(math.clamp(cosZen, -1, 1))
	local elev = 90 - deg(zen)
	local az = deg(
		math.acos(
			math.clamp((math.sin(lat) * math.cos(zen) - math.sin(rad(decl))) / (math.cos(lat) * math.sin(zen)), -1, 1)
		)
	)
	az = if ha > 0 then (az + 180) % 360 else (540 - az) % 360
	return az, elev
end

-- Vetor unitário no quadro do jogo (X = leste, Y = cima, Z = sul) apontando para o Sol.
function SolarPosition.direction(azDeg: number, elevDeg: number): (number, number, number)
	local a, e = rad(azDeg), rad(elevDeg)
	local east = math.cos(e) * math.sin(a)
	local north = math.cos(e) * math.cos(a)
	return east, math.sin(e), -north
end

-- Ajuste (ClockTime, GeographicLatitude) para que getDir(clock, lat) aponte para (tx, ty, tz).
-- getDir é injetado: no Roblox lê Lighting:GetSunDirection(); nos testes, um modelo simulado.
function SolarPosition.fit(
	tx: number,
	ty: number,
	tz: number,
	getDir: (number, number) -> (number, number, number),
	clock0: number,
	lat0: number
): (number, number, number)
	local function err(c: number, l: number): number
		local x, y, z = getDir(c, l)
		local dot = math.clamp(x * tx + y * ty + z * tz, -1, 1)
		return math.acos(dot)
	end
	local best_c, best_l, best_e = clock0, lat0, err(clock0, lat0)
	-- busca grossa quando o chute inicial está longe
	if best_e > rad(5) then
		for c = 0, 23.75, 0.25 do
			for l = -80, 80, 5 do
				local e = err(c, l)
				if e < best_e then
					best_c, best_l, best_e = c, l, e
				end
			end
		end
	end
	-- refino por busca de padrão (sem derivadas)
	local sc, sl = 0.25, 5
	for _ = 1, 60 do
		local improved = false
		for _, d in { { sc, 0 }, { -sc, 0 }, { 0, sl }, { 0, -sl } } do
			local c, l = (best_c + d[1]) % 24, math.clamp(best_l + d[2], -89, 89)
			local e = err(c, l)
			if e < best_e then
				best_c, best_l, best_e = c, l, e
				improved = true
			end
		end
		if not improved then
			sc, sl = sc / 2, sl / 2
			if sc < 1e-4 then
				break
			end
		end
	end
	return best_c, best_l, deg(best_e)
end

return SolarPosition
