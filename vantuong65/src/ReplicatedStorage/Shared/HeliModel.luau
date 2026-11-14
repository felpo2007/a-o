--!strict
-- UH-34D (Parte 9.7): teoria do momento com efeito solo (Cheeseman–Bennett), sustentação de
-- translação (velocidade induzida de Glauert), potência de perfil e parasita, perda de potência
-- com calor e altitude, torque do rotor. Os parâmetros livres são CALIBRADOS na carga do módulo
-- contra números da ficha (wiki:Sikorsky_H-34, research/veiculos/...):
--   - teto de pairar OGE 5.500 ft e IGE 9.600 ft (H-34A) → expoente de perda e potência de perfil;
--   - velocidade máxima 122 mph → área plana equivalente f;
--   - subida vertical de 600 ft/min ao nível do mar → fator de subida no pairado;
--   - razão de subida de 1.100 ft/min ao nível do mar (Sikorsky Archives, "S-58"; Army Aviation
--     Magazine, "CH-34 Choctaw"; Patriots Point, "UH-34D Seahorse"), na potência máxima contínua
--     → fator de subida em voo à frente, na velocidade de potência mínima. Entre as duas, o fator
--     varia com a velocidade.
local HeliModel = {}

local G = 9.80665
local HP = 745.7
local FT = 0.3048
local LB = 0.45359237

HeliModel.SPEC = {
	rotorR = 56 * FT / 2, -- 56 ft de diâmetro
	areaM2 = 2463 * FT * FT, -- 2.463 ft²
	emptyKg = 7646 * LB,
	grossKg = 11867 * LB,
	maxKg = 13300 * LB,
	takeoffHp = 1525, -- Wright R-1820-84, decolagem
	metoHp = 1275, -- máxima contínua (5 min, nota da ficha)
	maxSpeedMs = 122 * 1609.344 / 3600,
	cruiseMs = 97 * 1609.344 / 3600,
	troops = 12, -- H-34A (a ficha dá 12 para o A e 18 para o C)
	hoverOGEft = 5500,
	hoverIGEft = 9600,
	vClimbMs = 600 * FT / 60,
	rocMs = 1100 * FT / 60, -- melhor razão de subida, nível do mar, peso bruto
	-- suposições (D-38): altura do rotor no pairado IGE (cubo 4,36 m + 5 ft de roda), fator de
	-- potência induzida e perdas de transmissão/rotor de cauda; velocidade de ponta da pá.
	igeZ = 14.29 * FT + 5 * FT,
	kappa = 1.15,
	eta = 1.15,
	tipMs = 200,
}

export type Atm = { rho: number, sigma: number, tempC: number }

-- ISA em altitude, com temperatura real (densidade = p / (R T))
function HeliModel.atmosphere(tempC: number, altM: number?): Atm
	local h = altM or 0
	local p = 101325 * (1 - 2.25577e-5 * h) ^ 5.25588
	local rho = p / (287.05 * (tempC + 273.15))
	return { rho = rho, sigma = rho / 1.225, tempC = tempC }
end

local function isa(hft: number): Atm
	local h = hft * FT
	return HeliModel.atmosphere(15 - 0.0065 * h, h)
end

local cal = { n = 0.7, p0 = 300 * HP, f = 2.0, climbK = 1.0, climbKf = 1.0, vMinPower = 30 }

function HeliModel.powerAvailable(atm: Atm, hp: number?): number
	return (hp or HeliModel.SPEC.takeoffHp) * HP * atm.sigma ^ cal.n
end

local function groundFactor(z: number): number
	local R = HeliModel.SPEC.rotorR
	if z >= 4 * R then
		return 1
	end
	local zz = math.max(z, 14.29 * FT) -- o cubo nunca fica abaixo da altura com rodas no chão
	return math.max(0, 1 - (R / (4 * zz)) ^ 2)
end

-- velocidade induzida em voo à frente (Glauert, voo nivelado)
local function induced(T: number, V: number, rho: number): number
	local vh = math.sqrt(T / (2 * rho * HeliModel.SPEC.areaM2))
	local v2 = (-V * V + math.sqrt(V ^ 4 + 4 * vh ^ 4)) / 2
	return math.sqrt(math.max(v2, 0))
end

-- potência exigida (W) para massa, velocidade horizontal V (m/s) e altura do rotor z (m)
function HeliModel.powerRequired(massKg: number, V: number, z: number, atm: Atm): number
	local S = HeliModel.SPEC
	local T = massKg * G
	local vi = induced(T, V, atm.rho)
	-- o efeito solo some com a velocidade (o colchão de ar fica para trás)
	local ge = 1 - (1 - groundFactor(z)) * math.max(0, 1 - V / 10)
	local pi = S.kappa * T * vi * ge
	local mu = V / S.tipMs
	local p0 = cal.p0 * atm.sigma * (1 + 4.65 * mu * mu)
	local pp = 0.5 * atm.rho * V ^ 3 * cal.f
	return S.eta * (pi + p0 + pp)
end

-- calibração (roda uma vez): n e P0 pelos tetos de pairar; f pela velocidade máxima; fator de subida
do
	local S = HeliModel.SPEC
	local W = S.grossKg * G
	local a1, a2 = isa(S.hoverOGEft), isa(S.hoverIGEft)
	local function iid(atm: Atm): number
		return S.kappa * W ^ 1.5 / math.sqrt(2 * atm.rho * S.areaM2)
	end
	local ge = groundFactor(S.igeZ)
	local function residual(n: number): (number, number)
		local p0 = (S.takeoffHp * HP * a1.sigma ^ n / S.eta - iid(a1)) / a1.sigma
		local r = S.eta * (iid(a2) * ge + p0 * a2.sigma) - S.takeoffHp * HP * a2.sigma ^ n
		return r, p0
	end
	local lo, hi = 0.0, 3.0
	for _ = 1, 60 do
		local mid = (lo + hi) / 2
		local rlo = residual(lo)
		local rmid = residual(mid)
		if (rlo < 0) == (rmid < 0) then
			lo = mid
		else
			hi = mid
		end
	end
	cal.n = (lo + hi) / 2
	local _, p0 = residual(cal.n)
	cal.p0 = p0
	-- f: na velocidade máxima, ao nível do mar e no peso bruto, potência exigida = disponível
	local sl = isa(0)
	local flo, fhi = 0.1, 10.0
	for _ = 1, 60 do
		cal.f = (flo + fhi) / 2
		if HeliModel.powerRequired(S.grossKg, S.maxSpeedMs, 1000, sl) > HeliModel.powerAvailable(sl) then
			fhi = cal.f
		else
			flo = cal.f
		end
	end
	-- subida vertical: Vc = climbK * excesso de potência / peso (ficha: 600 ft/min ao nível do mar)
	local excess = HeliModel.powerAvailable(sl) - HeliModel.powerRequired(S.grossKg, 0, 1000, sl)
	cal.climbK = S.vClimbMs / math.max(excess / W, 1e-6)
	-- em voo à frente: a melhor subida sai na velocidade de potência mínima (ficha: 1.100 ft/min)
	local best, vBest = math.huge, 0
	for v = 0, S.maxSpeedMs, 0.25 do
		local p = HeliModel.powerRequired(S.grossKg, v, 1000, sl)
		if p < best then
			best, vBest = p, v
		end
	end
	cal.vMinPower = vBest
	-- a razão publicada é na potência máxima contínua (1.275 hp): nela o fator sai ~1, como manda a
	-- conservação de energia (todo o excesso vira subida); com a de decolagem sairia 0,62
	cal.climbKf = S.rocMs / math.max((HeliModel.powerAvailable(sl, S.metoHp) - best) / W, 1e-6)
end

export type Calibration = {
	n: number,
	p0: number,
	f: number,
	climbK: number,
	climbKf: number,
	vMinPower: number,
}

function HeliModel.calibration(): Calibration
	return table.clone(cal)
end

-- maior massa que paira a uma altura z (bisseção)
function HeliModel.maxHoverKg(z: number, atm: Atm, hp: number?): number
	local lo, hi = 0, HeliModel.SPEC.maxKg * 2
	local pa = HeliModel.powerAvailable(atm, hp)
	for _ = 1, 50 do
		local mid = (lo + hi) / 2
		if HeliModel.powerRequired(mid, 0, z, atm) > pa then
			hi = mid
		else
			lo = mid
		end
	end
	return (lo + hi) / 2
end

-- velocidade vertical sustentável (m/s) com a potência pedida (W); negativa = afunda. O fator vai
-- do pairado (600 ft/min na subida vertical) ao voo à frente (1.100 ft/min) até a velocidade de
-- potência mínima. Antes o controle cortava a subida em 8 m/s, sem fonte.
function HeliModel.climbRate(powerW: number, massKg: number, V: number, z: number, atm: Atm): number
	local excess = powerW - HeliModel.powerRequired(massKg, V, z, atm)
	local t = math.clamp(V / math.max(cal.vMinPower, 1), 0, 1)
	local k = cal.climbK + (cal.climbKf - cal.climbK) * t
	return k * excess / (massKg * G)
end

-- fração do torque máximo (para o pedal): P/Ω contra o torque na potência de decolagem
function HeliModel.torqueFraction(powerW: number): number
	return powerW / (HeliModel.SPEC.takeoffHp * HP)
end

return HeliModel
