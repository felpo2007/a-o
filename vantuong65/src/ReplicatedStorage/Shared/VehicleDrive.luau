--!strict
-- Movimento dos veículos (pedido do dono, 2026-11-11: "faça a movimentação dos veículos realista e
-- visualmente agradável"). Módulo puro, testado no Lune (tests/luau/veiculos.luau):
--   - chão: resistência ao rolamento, tração, aderência lateral e teto de velocidade por material;
--   - motor e câmbio: rotação com inércia (o motor "enche"), conversor de torque, trocas de marcha,
--     potência limitada pela rotação, freio, freio-motor e ré;
--   - lagarta: giro no lugar, giro amplo em movimento (limite de aceleração lateral), deriva lateral
--     na lama e na água, perda de velocidade na curva e na ladeira;
--   - anfíbio: empuxo na água calibrado pela velocidade da ficha, deriva e giro lentos;
--   - visual: mola da carroceria (inclina na arrancada e na freada, rola na curva), laço da lagarta
--     para as faixas animadas, voz do motor e tremor da câmera;
--   - UH-34D: atitude com inércia, rotor que acelera e desacelera, assistência de pouso suave.
-- Unidades SI (m, s, kg, N, rad); quem chama converte studs (1 stud = 0,28 m).
-- Números: "ficha" = Shared/Vehicles (com fonte); "D-36" = estimativa de engenharia já registrada;
-- "malha" = medido no GLB publicado; o resto é PLACEHOLDER (projeto, a trocar por manual).
local VehicleDrive = {}

local G = 9.80665
local HP_W = 745.7
VehicleDrive.G = G
VehicleDrive.STUD_M = 0.28
VehicleDrive.DRIVE_EFF = 0.6 -- eficiência motor→lagarta (D-36)

-- ===== chão =====
export type Ground = {
	crr: number, -- resistência ao rolamento (fração do peso)
	mu: number, -- tração máxima da lagarta (fração do peso)
	muLat: number, -- aderência lateral (fração do peso): abaixo disso a carroceria escorrega de lado
	ride: number, -- teto fora de estrada (fração da máxima da ficha): suspensão e tripulação aguentam
	soft: boolean, -- a chuva enlameia
	sinkM: number, -- quanto a lagarta afunda (só visual)
	fx: string, -- efeito: "dust" | "grass" | "leaves" | "sand" | "mud" | "paddy" | "water"
	rough: number, -- 0..1: trepidação (câmera e carroceria)
}

-- c_rr de estrada, terra, areia e arrozal: D-36 (0,04–0,18). Mata, capim e lama, aderências, tetos
-- fora de estrada, afundamento e trepidação: PLACEHOLDER. Sem fonte para a velocidade do M48A3 fora
-- de estrada: o teto vem do "ride" (o mapa não tem estrada; o capim dá ~31 km/h e o arrozal ~14 km/h).
VehicleDrive.GROUND = {
	road = { crr = 0.04, mu = 0.8, muLat = 0.7, ride = 1.0, soft = false, sinkM = 0, fx = "dust", rough = 0.1 },
	earth = { crr = 0.06, mu = 0.7, muLat = 0.6, ride = 0.75, soft = true, sinkM = 0.02, fx = "dust", rough = 0.45 },
	grass = { crr = 0.07, mu = 0.65, muLat = 0.55, ride = 0.65, soft = true, sinkM = 0.03, fx = "grass", rough = 0.4 },
	forest = { crr = 0.09, mu = 0.6, muLat = 0.5, ride = 0.5, soft = true, sinkM = 0.04, fx = "leaves", rough = 0.75 },
	sand = { crr = 0.12, mu = 0.5, muLat = 0.45, ride = 0.6, soft = false, sinkM = 0.08, fx = "sand", rough = 0.3 },
	mud = { crr = 0.15, mu = 0.45, muLat = 0.35, ride = 0.4, soft = true, sinkM = 0.15, fx = "mud", rough = 0.45 },
	paddy = { crr = 0.18, mu = 0.4, muLat = 0.3, ride = 0.3, soft = true, sinkM = 0.22, fx = "paddy", rough = 0.35 },
	water = { crr = 0, mu = 0, muLat = 0, ride = 0, soft = false, sinkM = 0, fx = "water", rough = 0.1 },
} :: { [string]: Ground }

-- Classifica o chão pelo material do terreno ou da peça (Enum.Material.Name) e pelo atributo
-- "Material"/nome das peças do mapa. A lâmina d'água do arrozal é a peça "PaddyWater".
function VehicleDrive.groundOf(material: string?, attr: string?, partName: string?): string
	if attr == "PaddyWater" or partName == "PaddyWater" then
		return "paddy"
	elseif partName == "Dike" or attr == "MudWall" or attr == "Earth" then
		return "earth"
	elseif material == "Water" then
		return "water"
	elseif material == "Mud" then
		return "mud"
	elseif material == "Sand" then
		return "sand"
	elseif material == "LeafyGrass" then
		return "forest"
	elseif material == "Grass" then
		return "grass"
	elseif
		material == "Asphalt"
		or material == "Pavement"
		or material == "Concrete"
		or material == "Cobblestone"
		or material == "Brick"
	then
		return "road"
	end
	return "earth"
end

-- Chão com a chuva (0..1): o mole perde tração e o teto cai, e rola pior (PLACEHOLDER).
function VehicleDrive.ground(key: string, rain: number?): Ground
	local g = VehicleDrive.GROUND[key] or VehicleDrive.GROUND.earth
	local r = math.clamp(rain or 0, 0, 1)
	if r <= 0 or not g.soft then
		return g
	end
	local w = table.clone(g)
	w.crr = g.crr * (1 + 0.5 * r)
	w.mu = g.mu * (1 - 0.2 * r)
	w.muLat = g.muLat * (1 - 0.2 * r)
	w.ride = g.ride * (1 - 0.15 * r)
	w.sinkM = g.sinkM * (1 + 0.5 * r)
	if w.fx == "dust" or w.fx == "grass" or w.fx == "leaves" then
		w.fx = if r > 0.3 then "mud" else w.fx
	end
	return w
end

-- ===== motor, câmbio e lagarta, por veículo =====
export type SpringParams = {
	pitchHz: number,
	rollHz: number,
	heaveHz: number,
	zeta: number,
	pitchDegPerG: number, -- nariz sobe por g de aceleração (abaixa na freada)
	rollDegPerG: number, -- rola para fora da curva por g lateral
	heaveMPerG: number, -- afunda por g vertical (lombada, queda)
}

export type WaterSpec = {
	thrust: number, -- fração da potência útil que vira empuxo na água
	yawDegS: number,
	yawTauS: number,
	latTauS: number, -- a deriva lateral some nesse tempo
	addedMass: number, -- massa de água arrastada (fração da massa)
	draftM: number, -- fundura em que flutua (abaixo disso a lagarta pega no fundo)
}

export type DriveSpec = {
	gears: { number }, -- velocidade no topo de cada marcha à frente (fração da máxima da ficha)
	reverse: number, -- velocidade máxima de ré (fração da máxima)
	shiftS: number, -- tempo da troca (o motor alivia)
	rpmIdle: number,
	rpmMax: number,
	stall: number, -- rotação do conversor de torque com o veículo parado (fração da máxima)
	spoolUpS: number, -- constante de tempo do motor subindo de giro
	spoolDownS: number,
	tractive: number, -- esforço trator máximo do conversor na rotação de estol / peso
	massFactor: number, -- inércia das peças que giram (rodas, lagarta, transmissão)
	brakeG: number,
	coastG: number, -- freio-motor e perdas com o acelerador solto
	pivotDegS: number, -- giro no lugar
	yawTauS: number, -- inércia do giro
	latG: number, -- aceleração lateral máxima em movimento (limita o giro: curva ampla)
	turnDrag: number, -- resistência extra da lagarta derrapando na curva (fração do peso no giro máximo)
	fordM: number, -- fundura que vadeia sem flutuar
	water: WaterSpec?,
	spring: SpringParams,
}

VehicleDrive.DRIVE = {
	-- M48A3: câmbio Allison CD-850-4A/B com duas faixas à frente e uma ré (wiki:M48_Patton). Frações
	-- das marchas, rotações do AVDS-1790-2, giro, freio, mola e vau: PLACEHOLDER.
	m48a3 = {
		gears = { 0.45, 1.0 },
		reverse = 0.3,
		shiftS = 0.5,
		rpmIdle = 700,
		rpmMax = 2400,
		stall = 0.8,
		spoolUpS = 0.9,
		spoolDownS = 0.7,
		tractive = 0.65,
		massFactor = 1.2,
		brakeG = 0.45,
		coastG = 0.025,
		pivotDegS = 20,
		yawTauS = 0.6,
		latG = 0.35,
		turnDrag = 0.06,
		fordM = 1.2,
		spring = {
			pitchHz = 1.0,
			rollHz = 1.2,
			heaveHz = 1.6,
			zeta = 0.3,
			pitchDegPerG = 6,
			rollDegPerG = 4.5,
			heaveMPerG = 0.05,
		},
	},
	-- M50 Ontos (8,6 t, 145 hp a gasolina): mais leve e mais vivo. Tudo PLACEHOLDER além da ficha.
	ontos = {
		gears = { 0.45, 1.0 },
		reverse = 0.3,
		shiftS = 0.35,
		rpmIdle = 500,
		rpmMax = 3600,
		stall = 0.75,
		spoolUpS = 0.45,
		spoolDownS = 0.4,
		tractive = 0.7,
		massFactor = 1.15,
		brakeG = 0.5,
		coastG = 0.03,
		pivotDegS = 40,
		yawTauS = 0.3,
		latG = 0.4,
		turnDrag = 0.05,
		fordM = 0.6,
		spring = {
			pitchHz = 1.4,
			rollHz = 1.6,
			heaveHz = 2.0,
			zeta = 0.3,
			pitchDegPerG = 7,
			rollDegPerG = 5.5,
			heaveMPerG = 0.04,
		},
	},
	-- LVTP-5 (37,4 t, 704 hp; 48 km/h em terra e 11 km/h na água, ficha). Empuxo na água: o mesmo
	-- fator de antes (0,15 da potência útil); calado, giro e deriva na água: PLACEHOLDER.
	lvtp5 = {
		gears = { 0.45, 1.0 },
		reverse = 0.3,
		shiftS = 0.5,
		rpmIdle = 600,
		rpmMax = 2800,
		stall = 0.8,
		spoolUpS = 0.8,
		spoolDownS = 0.6,
		tractive = 0.6,
		massFactor = 1.2,
		brakeG = 0.4,
		coastG = 0.025,
		pivotDegS = 18,
		yawTauS = 0.65,
		latG = 0.3,
		turnDrag = 0.07,
		fordM = 99,
		water = { thrust = 0.15, yawDegS = 8, yawTauS = 1.4, latTauS = 2.5, addedMass = 0.25, draftM = 1.4 },
		spring = {
			pitchHz = 0.9,
			rollHz = 1.1,
			heaveHz = 1.4,
			zeta = 0.32,
			pitchDegPerG = 6.5,
			rollDegPerG = 5,
			heaveMPerG = 0.05,
		},
	},
} :: { [string]: DriveSpec }

-- Ficha mínima (Shared/Vehicles.Spec serve)
export type Body = {
	id: string,
	kind: string,
	massKg: number,
	powerHp: number,
	maxKmh: number,
	waterKmh: number?,
}

export type State = {
	v: number, -- m/s ao longo da frente (+ à frente)
	vLat: number, -- m/s para a direita
	yawRate: number, -- rad/s (+ = para a esquerda, como CFrame.Angles)
	rpm: number, -- rotação (fração da máxima)
	gear: number, -- 1..n à frente, -1 ré, 0 neutro
	shiftT: number, -- tempo restante da troca
	load: number, -- 0..1: quanto da potência disponível está em uso
	slip: number, -- 0..1: lagarta patinando ou carroceria escorregando
	floating: boolean,
	blockedT: number,
	accel: number, -- m/s² ao longo da frente no último passo
}

export type Input = { throttle: number, steer: number }

export type Env = {
	ground: string,
	rain: number?,
	slopeSin: number?, -- seno da rampa (+ = nariz para cima)
	sideSin: number?, -- seno da inclinação lateral (+ = lado direito mais alto)
	waterDepthM: number?, -- fundura da água sob o veículo (nil = sem medida)
	engine: number?, -- 0..1 (atributo Engine / 100)
	tracks: number?, -- 0..1 (atributo Tracks / 100)
}

function VehicleDrive.newState(): State
	return {
		v = 0,
		vLat = 0,
		yawRate = 0,
		rpm = 0,
		gear = 0,
		shiftT = 0,
		load = 0,
		slip = 0,
		floating = false,
		blockedT = 0,
		accel = 0,
	}
end

function VehicleDrive.spec(id: string): DriveSpec
	return VehicleDrive.DRIVE[id] or VehicleDrive.DRIVE.m48a3
end

local function sign(x: number): number
	return if x > 0 then 1 elseif x < 0 then -1 else 0
end

local function approach(x: number, target: number, tau: number, dt: number): number
	return x + (target - x) * (1 - math.exp(-dt / math.max(tau, 1e-3)))
end

-- Teto de velocidade à frente (m/s) no chão, pela ficha e pelo "ride"
function VehicleDrive.topSpeed(body: Body, groundKey: string, rain: number?): number
	if groundKey == "water" then
		return (body.waterKmh or 0) / 3.6
	end
	return body.maxKmh / 3.6 * VehicleDrive.ground(groundKey, rain).ride
end

-- Um passo da dinâmica de chão (ou de água, no anfíbio). Muda `st` e devolve.
function VehicleDrive.step(body: Body, st: State, inp: Input, env: Env, dt: number): State
	local d = VehicleDrive.spec(body.id)
	local m = body.massKg
	local W = m * G
	local engine = math.clamp(env.engine or 1, 0, 1)
	local alive = engine > 0
	local mobile = alive and (env.tracks or 1) > 0
	local throttle = if mobile then math.clamp(inp.throttle, -1, 1) else 0
	local steer = if mobile then math.clamp(inp.steer, -1, 1) else 0
	local key = env.ground
	local floating = false
	local drowned = false
	if key == "water" then
		local w = d.water
		if body.kind == "amphibious" and w and (env.waterDepthM == nil or (env.waterDepthM :: number) >= w.draftM) then
			floating = true
		elseif env.waterDepthM ~= nil and (env.waterDepthM :: number) < (if w then w.draftM else d.fordM) then
			key = "mud" -- água rasa: a lagarta anda no leito do riacho
		else
			drowned = true -- fundo demais e não flutua: atola e o motor afoga
		end
	end
	st.floating = floating
	local g = VehicleDrive.ground(key, env.rain)
	local slope = math.clamp(env.slopeSin or 0, -0.95, 0.95)
	local side = math.clamp(env.sideSin or 0, -0.95, 0.95)
	local cosS = math.sqrt(1 - slope * slope)
	local vmax = body.maxKmh / 3.6
	local v = st.v
	local v0 = v

	-- intenção: acelerador para o lado do movimento anda; para o lado contrário freia; parado, engata
	local want, braking = 0, false
	if throttle > 0.02 then
		if v < -0.3 then
			braking = true
		else
			want = 1
		end
	elseif throttle < -0.02 then
		if v > 0.3 then
			braking = true
		else
			want = -1
		end
	end

	-- câmbio
	if want == -1 then
		if st.gear ~= -1 then
			st.gear = -1
			st.shiftT = d.shiftS -- engatar a ré leva um instante
		end
	elseif want == 1 and st.gear < 1 then
		st.gear = 1
		st.shiftT = d.shiftS * 0.6
	elseif want == 0 and math.abs(v) < 0.3 and not braking then
		st.gear = 0
	end
	if st.gear >= 1 then
		local n = #d.gears
		local top = d.gears[st.gear] * vmax
		if want == 1 and st.shiftT <= 0 and st.gear < n and math.abs(v) > top * 0.96 then
			st.gear += 1
			st.shiftT = d.shiftS
		elseif st.gear > 1 and math.abs(v) < d.gears[st.gear - 1] * vmax * 0.8 then
			st.gear -= 1
			st.shiftT = if want == 1 then d.shiftS * 0.6 else 0
		end
	end
	local shifting = st.shiftT > 0
	st.shiftT = math.max(0, st.shiftT - dt)

	-- rotação: o conversor deixa o motor subir até o estol parado; acoplado, segue a lagarta
	local idle = d.rpmIdle / d.rpmMax
	local wheel = 0
	if st.gear ~= 0 then
		local top = (if st.gear < 0 then d.reverse else d.gears[st.gear]) * vmax
		wheel = math.abs(v) / math.max(top, 0.1)
	end
	-- na água, "frear" é dar ré na lagarta: o motor sobe de giro
	local demand = if braking and not floating then 0 else math.abs(throttle)
	if shifting then
		demand *= 0.15
	end
	-- girar no lugar pede motor (a lagarta de dentro freia e a de fora empurra terra)
	local pivotDemand = math.abs(steer) * (if math.abs(v) < 1.5 then 0.55 else 0.2)
	if not floating then
		demand = math.max(demand, pivotDemand)
	end
	local rpmTarget = 0
	if alive then
		rpmTarget = math.max(idle, wheel + demand * math.max(0, d.stall - wheel) * 0.8 + demand * 0.08)
		rpmTarget = math.min(rpmTarget, if drowned then idle else 1.05)
	end
	st.rpm = approach(st.rpm, rpmTarget, if rpmTarget > st.rpm then d.spoolUpS else d.spoolDownS, dt)

	-- potência útil e força de tração: o acelerador dosa a potência; o conversor limita a força pela
	-- rotação do motor (em marcha lenta só arrasta)
	local P = body.powerHp * HP_W * VehicleDrive.DRIVE_EFF * engine * (0.15 + 0.85 * math.clamp(st.rpm, 0, 1))
	local fConv = d.tractive * W * math.clamp(st.rpm / d.stall, 0, 1) ^ 2
	local fFull = math.min(P / math.max(math.abs(v), 1.0), fConv)
	local fDrive = 0
	local slip = 0
	local mEff = m * d.massFactor
	local a: number
	if floating then
		-- água: empuxo da lagarta contra o arrasto quadrático (velocidade final = a da ficha)
		local w = d.water :: WaterSpec
		local vw = math.max((body.waterKmh or 0) / 3.6, 0.5)
		local tMax = body.powerHp * HP_W * VehicleDrive.DRIVE_EFF * w.thrust * engine / vw
		local k = 0.9 * tMax / (vw * vw) -- com o termo linear abaixo, a final fica exatamente em vw
		local thrust = 0
		if braking then
			thrust = -sign(v) * 0.5 * tMax * math.abs(throttle)
		elseif want ~= 0 then
			thrust = want * math.abs(throttle) * tMax * (if want < 0 then 0.5 else 1)
		end
		thrust *= math.clamp(st.rpm / math.max(d.stall, 0.1), 0, 1)
		fDrive = thrust
		-- arrasto quadrático + um pouco de linear (devagar o casco ainda para)
		a = (thrust - k * v * math.abs(v) - 0.1 * tMax * v / vw) / (m * (1 + w.addedMass))
		v += a * dt
		if v0 ~= 0 and thrust == 0 and sign(v) ~= sign(v0) then
			v = 0
		end
		st.load = math.clamp(math.abs(thrust) / math.max(tMax, 1), 0, 1)
	elseif drowned then
		v *= math.max(0, 1 - 2 * dt)
		a = (v - v0) / dt
		st.load = 0
	else
		if want ~= 0 then
			fDrive = math.min(demand * P / math.max(math.abs(v), 1.0), fConv)
			local grip = g.mu * W * cosS
			if fDrive > grip then
				slip = (fDrive - grip) / fDrive
				fDrive = grip
			end
			fDrive *= want
		end
		-- resistências: rolamento (mais na curva, a lagarta derrapa), freio e freio-motor
		local turnFrac = math.min(math.abs(st.yawRate) / math.rad(d.pivotDegS), 1.5)
		local roll = (g.crr + d.turnDrag * turnFrac) * W * cosS
		local brake = 0
		if braking then
			brake = math.min(d.brakeG, g.mu) * W * math.abs(throttle)
		elseif want == 0 then
			brake = d.coastG * W
		end
		local fGrade = -W * slope
		-- teto: o motorista alivia o acelerador para não passar do que o chão e a marcha aguentam
		local cap = if want < 0 then vmax * d.reverse * math.min(g.ride / 0.75, 1) else vmax * g.ride
		if want ~= 0 and sign(v) == want and math.abs(v) >= cap * 0.995 then
			local needed = roll - want * fGrade -- força para manter a velocidade
			fDrive = want * math.clamp(needed, 0, math.abs(fDrive))
		end
		local ext = fDrive + fGrade
		local resist = roll + brake
		if math.abs(v) < 0.05 then
			-- parado: o freio segura até o limite da aderência
			local hold = roll + (if want == 0 then g.mu * W * cosS else 0)
			if math.abs(ext) <= hold then
				a = -v / dt
			else
				a = (ext - sign(ext) * hold) / mEff
			end
			v += a * dt
		else
			a = (ext - sign(v) * resist) / mEff
			local nv = v + a * dt
			-- resistência não inverte o sentido
			if sign(nv) ~= sign(v) and sign(ext) ~= sign(nv) then
				nv = 0
			end
			-- freando (ou acelerando contra) e ainda ganhando velocidade: escorrega ladeira abaixo
			if braking and sign(a) == sign(v) then
				slip = 1
			end
			v = nv
		end
		-- acima do teto (descida, chão que ficou pior): o motorista freia
		local over = if v < 0 then vmax * d.reverse * math.min(g.ride / 0.75, 1) else vmax * g.ride
		if math.abs(v) > over * 1.01 then
			-- tira o que a ladeira acabou de dar e mais o excesso em ~0,6 s, até o limite do freio
			local excess = math.abs(v) - over
			local along = math.max(0, (v - v0) / dt * sign(v))
			v -= sign(v) * math.min(excess, math.min(excess / 0.6 + along, d.brakeG * G) * dt)
		end
		a = (v - v0) / dt
		st.load = if want ~= 0 then math.clamp(math.abs(fDrive) / math.max(fFull, 1), 0, 1) else pivotDemand * 0.9
		if shifting then
			st.load *= 0.3
		end
	end
	st.v = v
	st.accel = a

	-- giro: no lugar pela transmissão; em movimento pela aderência lateral (curva mais aberta)
	local pivot = math.rad(if floating then (d.water :: WaterSpec).yawDegS else d.pivotDegS)
	if not floating then
		pivot *= math.clamp(g.mu / 0.7, 0.45, 1)
	end
	local speed = math.abs(v)
	local limit = pivot
	if speed > 0.5 and not floating then
		limit = math.min(pivot, d.latG * G * math.clamp(g.muLat / 0.6, 0.4, 1) / speed)
	end
	local rev = if v < -0.3 then -1 else 1 -- de ré, como carro: a traseira vai para o lado do comando
	local yawTarget = if mobile and not drowned then -steer * limit * rev else 0
	st.yawRate = approach(st.yawRate, yawTarget, if floating then (d.water :: WaterSpec).yawTauS else d.yawTauS, dt)

	-- deriva lateral: a carroceria gira debaixo da velocidade; a lagarta segura até a aderência
	local dpsi = st.yawRate * dt
	local vLat = st.vLat
	st.vLat = vLat + st.v * dpsi - G * side * dt
	st.v -= vLat * dpsi
	if floating then
		st.vLat *= math.exp(-dt / (d.water :: WaterSpec).latTauS)
	elseif drowned then
		st.vLat *= math.max(0, 1 - 2 * dt)
	else
		local dec = g.muLat * G * cosS * dt
		st.vLat = if math.abs(st.vLat) <= dec then 0 else st.vLat - sign(st.vLat) * dec
	end
	local scrub = if speed < 1.5 then math.abs(st.yawRate) / math.max(pivot, 1e-3) * 0.4 else 0
	st.slip = math.clamp(math.max(slip, math.abs(st.vLat) / 2, scrub), 0, 1)
	return st
end

-- O chassi não acompanha o comando (parede, barranco, outro veículo): depois de 0,25 s a velocidade
-- do modelo cai para a medida e a lagarta patina. `measured` = m/s reais ao longo da frente.
function VehicleDrive.contact(st: State, measured: number, dt: number): boolean
	local gap = (st.v - measured) * sign(st.v)
	if math.abs(st.v) > 1 and gap > 1.2 then
		st.blockedT += dt
	else
		st.blockedT = 0
	end
	if st.blockedT > 0.25 then
		st.v = measured + (st.v - measured) * math.exp(-dt / 0.15)
		st.slip = 1
		return true
	end
	return false
end

-- ===== mola visual da carroceria =====
export type SpringState = {
	pitch: number,
	pitchV: number,
	roll: number,
	rollV: number,
	heave: number,
	heaveV: number,
}

function VehicleDrive.newSpring(): SpringState
	return { pitch = 0, pitchV = 0, roll = 0, rollV = 0, heave = 0, heaveV = 0 }
end

VehicleDrive.SPRING_MAX_DEG = 6
VehicleDrive.SPRING_MAX_M = 0.15

-- Oscilador amortecido por eixo. aLong > 0 acelerando (nariz sobe), aLat > 0 aceleração para a
-- direita (a carroceria rola para fora: lado direito sobe, roll > 0), aVert > 0 para cima (afunda).
-- Ângulos em rad e altura em m. Subpassos para ficar estável com dt grande.
function VehicleDrive.springStep(
	sp: SpringState,
	p: SpringParams,
	aLong: number,
	aLat: number,
	aVert: number,
	dt: number
)
	local n = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / n
	local maxA = math.rad(VehicleDrive.SPRING_MAX_DEG)
	local tp = math.clamp(math.rad(p.pitchDegPerG) * aLong / G, -maxA, maxA)
	local tr = math.clamp(math.rad(p.rollDegPerG) * aLat / G, -maxA, maxA)
	local th = math.clamp(-p.heaveMPerG * aVert / G, -VehicleDrive.SPRING_MAX_M, VehicleDrive.SPRING_MAX_M)
	local wp, wr, wh = 2 * math.pi * p.pitchHz, 2 * math.pi * p.rollHz, 2 * math.pi * p.heaveHz
	for _ = 1, n do
		sp.pitchV += (wp * wp * (tp - sp.pitch) - 2 * p.zeta * wp * sp.pitchV) * h
		sp.pitch += sp.pitchV * h
		sp.rollV += (wr * wr * (tr - sp.roll) - 2 * p.zeta * wr * sp.rollV) * h
		sp.roll += sp.rollV * h
		sp.heaveV += (wh * wh * (th - sp.heave) - 2 * p.zeta * wh * sp.heaveV) * h
		sp.heave += sp.heaveV * h
	end
	sp.pitch = math.clamp(sp.pitch, -maxA * 1.5, maxA * 1.5)
	sp.roll = math.clamp(sp.roll, -maxA * 1.5, maxA * 1.5)
	sp.heave = math.clamp(sp.heave, -VehicleDrive.SPRING_MAX_M * 1.5, VehicleDrive.SPRING_MAX_M * 1.5)
end

-- Ajuste ao chão pelas 4 pontas (só visual). Folgas = distância (m) do fundo da lagarta até o chão
-- em cada ponta (+ = chão abaixo). Devolve (pitch, roll, heave) em rad e m, limitados.
function VehicleDrive.cornerFit(
	gapFL: number,
	gapFR: number,
	gapBL: number,
	gapBR: number,
	halfLenM: number,
	halfWidM: number
): (number, number, number)
	local front, rear = (gapFL + gapFR) / 2, (gapBL + gapBR) / 2
	local left, right = (gapFL + gapBL) / 2, (gapFR + gapBR) / 2
	local lim = math.rad(4)
	local pitch = math.clamp(-math.atan((front - rear) / (2 * halfLenM)), -lim, lim)
	local roll = math.clamp(-math.atan((right - left) / (2 * halfWidM)), -lim, lim)
	local heave = math.clamp(-(front + rear) / 2, -0.12, 0.12)
	return pitch, roll, heave
end

-- ===== laço da lagarta (faixas animadas) =====
-- Envoltória convexa de círculos (roda-guia, rodas de apoio das pontas, roda motriz), na vista
-- lateral (x ao longo, y para cima), percorrida no sentido anti-horário: o ramo de baixo anda em +x.
export type BeltSeg = {
	line: boolean,
	len: number,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	cx: number,
	cy: number,
	r: number,
	a0: number,
	a1: number,
}
export type Belt = { segs: { BeltSeg }, length: number }

function VehicleDrive.belt(circles: { { number } }): Belt
	local n = #circles
	local phis = table.create(n, 0)
	for i = 1, n do
		local c1, c2 = circles[i], circles[i % n + 1]
		local dx, dy = c2[1] - c1[1], c2[2] - c1[2]
		local L = math.sqrt(dx * dx + dy * dy)
		phis[i] = math.atan2(dy, dx) - math.acos(math.clamp((c1[3] - c2[3]) / L, -1, 1))
	end
	local segs: { BeltSeg } = {}
	local total = 0
	for i = 1, n do
		local c = circles[i]
		local a0 = phis[(i - 2) % n + 1]
		local a1 = phis[i]
		while a1 < a0 do
			a1 += 2 * math.pi
		end
		local arcLen = c[3] * (a1 - a0)
		table.insert(segs, {
			line = false,
			len = arcLen,
			x0 = 0,
			y0 = 0,
			x1 = 0,
			y1 = 0,
			cx = c[1],
			cy = c[2],
			r = c[3],
			a0 = a0,
			a1 = a1,
		})
		total += arcLen
		local c2 = circles[i % n + 1]
		local x0, y0 = c[1] + c[3] * math.cos(phis[i]), c[2] + c[3] * math.sin(phis[i])
		local x1, y1 = c2[1] + c2[3] * math.cos(phis[i]), c2[2] + c2[3] * math.sin(phis[i])
		local lineLen = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
		table.insert(segs, {
			line = true,
			len = lineLen,
			x0 = x0,
			y0 = y0,
			x1 = x1,
			y1 = y1,
			cx = 0,
			cy = 0,
			r = 0,
			a0 = 0,
			a1 = 0,
		})
		total += lineLen
	end
	return { segs = segs, length = total }
end

-- Ponto do laço a uma distância s (qualquer valor; dá a volta). Devolve x, y e o ângulo da tangente.
function VehicleDrive.beltAt(b: Belt, s: number): (number, number, number)
	local t = s % b.length
	for _, sg in b.segs do
		if t <= sg.len or sg == b.segs[#b.segs] then
			if sg.line then
				local u = if sg.len > 0 then math.clamp(t / sg.len, 0, 1) else 0
				return sg.x0 + (sg.x1 - sg.x0) * u,
					sg.y0 + (sg.y1 - sg.y0) * u,
					math.atan2(sg.y1 - sg.y0, sg.x1 - sg.x0)
			end
			local a = sg.a0 + (if sg.r > 0 then t / sg.r else 0)
			return sg.cx + sg.r * math.cos(a), sg.cy + sg.r * math.sin(a), a + math.pi / 2
		end
		t -= sg.len
	end
	return 0, 0, 0
end

-- ===== arte publicada: pontos medidos na malha =====
-- Referencial da MeshPart no Roblox (como tools/weapon_landmarks.load_points: GLB girado 180° em Y,
-- centro da caixa), em studs. O nariz fica em −X (VehicleService.ART_YAW). Os círculos da lagarta
-- (roda-guia, 1ª e última rodas, roda motriz: x, y, raio) foram ajustados sobre a vista lateral da
-- malha e conferidos por sobreposição (2026-11-11); o rotor é o cubo e a ponta das pás da malha.
-- Escapamentos: posição de projeto (PLACEHOLDER: conferir no Studio).
export type TrackArt = { zIn: number, zOut: number, circles: { { number } }, bars: number }
export type RotorArt = { x: number, y: number, z: number, r: number }
-- passageiros em fileiras de 2 (um de cada lado, ±z), a partir de x0, de dx em dx
export type Riders = { x0: number, dx: number, y: number, z: number }
export type Art = {
	box: { number },
	track: TrackArt?,
	exhaust: { { number } }?,
	rotor: RotorArt?,
	tail: RotorArt?,
	-- Olho de cada assento (SeatId → x, y, z). A malha só tem faces de fora: com o olho dentro dela
	-- o casco some e o jogador flutua no capim. Então o olho fica FORA da malha: cabeça para fora da
	-- escotilha nos blindados (convés/teto medido na malha + ~0,5 m de cabeça), cabine e porta aberta
	-- no UH-34D. Alturas de convés e teto: mapa de alturas da malha (2026-11-11); o resto é projeto.
	eyes: { [string]: { number } }?,
	riders: Riders?,
}

VehicleDrive.ART = {
	m48a3 = {
		box = { 28.17, 12.67, 13.39 },
		track = {
			zIn = 4.2,
			zOut = 6.45,
			circles = { { -6.9, -2.3, 1.55 }, { -3.9, -5.15, 1.15 }, { 10.3, -5.15, 1.15 }, { 12.55, -2.55, 1.55 } },
			bars = 34,
		},
		exhaust = { { 13.4, -0.2, 3.0 }, { 13.4, -0.2, -3.0 } },
		-- convés da frente y ≈ 0 (o tubo do canhão passa em z ≈ 0, y ≈ 2,5); teto da torre 3,8–5,0;
		-- cúpula do comandante à direita atrás (≈ 4,9); escotilha do municiador à esquerda (≈ 5,4)
		eyes = {
			-- escotilha na frente do casco, à esquerda do tubo. No Studio, em x = −7 o olho ficava em
			-- cima da quina da frente e o casco não aparecia; raios na malha deram o convés em y ≈ 0,3
			-- (malha) de x = −6,4 a −3,4 e a frente da torre em x ≈ −2,4: o olho vai ~1,8 stud à frente
			-- dela, com a cabeça 1,5 stud (0,4 m) acima do convés
			driver = { -4.2, 1.8, 2.2 },
			gunner = { -0.8, 4.9, -2.4 }, -- periscópio da mira no teto, frente direita da torre
			commander = { 4.6, 6.6, -1.6 }, -- cabeça fora da cúpula
			loader = { 3.2, 6.8, 2.8 },
		},
	},
	ontos = {
		box = { 12.1, 10.26, 7.75 },
		track = {
			zIn = 2.4,
			zOut = 3.8,
			circles = { { -4.6, -2.9, 1.2 }, { -3.2, -4.1, 1.0 }, { 3.4, -4.1, 1.0 }, { 4.7, -2.9, 1.2 } },
			bars = 22,
		},
		exhaust = { { 5.7, -0.6, -2.0 } },
		-- convés da frente y ≈ 0,3; teto do meio ≈ 3,3; os 6 tubos dos dois lados sobem até ≈ 5,1
		eyes = {
			driver = { -4.6, 2.2, 1.6 }, -- escotilha da frente, à esquerda
			gunner = { 0.0, 4.8, 0.0 }, -- cabeça fora, entre os tubos
			loader = { 3.4, 4.8, 0.0 },
		},
	},
	lvtp5 = {
		box = { 28.41, 12.45, 12.14 },
		track = {
			zIn = 4.0,
			zOut = 6.05,
			circles = { { -9.6, -3.0, 1.3 }, { -6.6, -5.0, 1.2 }, { 10.1, -5.0, 1.2 }, { 12.0, -3.2, 1.3 } },
			bars = 36,
		},
		exhaust = { { 13.9, 3.6, 3.6 }, { 13.9, 3.6, -3.6 } },
		-- convés y ≈ 3,2–3,9; cúpula da metralhadora na frente, no meio (≈ 6,2)
		eyes = {
			driver = { -9.6, 5.2, 3.4 },
			gunner = { -6.0, 7.6, 0.1 },
			commander = { -9.6, 5.2, -3.4 },
		},
		-- a tropa vai sentada em cima (no Vietnã os fuzileiros andavam no teto do amtrac por causa das
		-- minas): olho a ~0,9 m acima do convés
		riders = { x0 = 0.0, dx = 2.2, y = 6.9, z = 3.0 },
	},
	uh34d = {
		box = { 48.09, 19.76, 47.01 },
		rotor = { x = -6.2, y = 8.7, z = 0, r = 23.5 },
		tail = { x = 21.8, y = 4.37, z = -0.06, r = 2.24 },
		-- cabine alta sobre o motor do nariz (teto ≈ 7,4 em x ≈ −16,5); pele da direita em z ≈ −4,9
		eyes = {
			driver = { -15.5, 6.3, -1.7 }, -- piloto à direita
			copilot = { -15.5, 6.3, 1.7 },
			gunner = { -6.0, -1.0, -5.4 }, -- porta da direita aberta, debruçado para fora
		},
		-- tropa sentada nas portas, pernas para fora (a da esquerda é licença: o H-34 só tem a da direita)
		riders = { x0 = -10.0, dx = 2.4, y = -2.2, z = 5.3 },
	},
} :: { [string]: Art }

-- Olho do assento no referencial da malha (studs): tripulação pela tabela; passageiro "p<n>" na
-- fileira (n−1)//2, ímpar à direita (−z), par à esquerda (+z). nil = sem olho (fica a cabeça).
function VehicleDrive.eyeOf(id: string, seatId: string): (number?, number?, number?)
	local art = VehicleDrive.ART[id]
	if not art then
		return nil, nil, nil
	end
	local e = art.eyes and art.eyes[seatId]
	if e then
		return e[1], e[2], e[3]
	end
	local n = tonumber(string.match(seatId, "^p(%d+)$"))
	local r = art.riders
	if n and r then
		local row = (n - 1) // 2
		return r.x0 + row * r.dx, r.y, (if n % 2 == 1 then -1 else 1) * r.z
	end
	return nil, nil, nil
end

-- Câmera de perseguição (3ª pessoa) atrás do veículo: distância (studs) e altura do pivô acima do
-- topo do chassi, pelo tamanho. Projeto: o casco inteiro cabe na tela com FOV 70.
function VehicleDrive.chaseOf(kind: string, lengthStuds: number): (number, number)
	if kind == "heli" then
		return 62, 6
	end
	return lengthStuds * 1.2 + 8, 4
end

-- ===== som do motor =====
-- Tom (PlaybackSpeed) e volume relativo pela rotação (0..1) e pela carga (0..1). A rotação de marcha
-- lenta (~0,25–0,3) fica perto do tom original do arquivo. Faixas de projeto.
function VehicleDrive.engineVoice(rpm: number, load: number): (number, number)
	local r = math.clamp(rpm, 0, 1.1)
	local l = math.clamp(load, 0, 1)
	return 0.62 + 0.62 * r, (0.45 + 0.55 * l) * (0.7 + 0.3 * r)
end

-- ===== tremor da câmera (motorista) =====
-- Ruído em rad (pitch, yaw, roll) e balanço vertical (m) pela velocidade, pelo chão e pelo motor.
-- Amplitudes de projeto: ~0,35° a 13 m/s no capim; o motor em marcha lenta só arrepia (0,03°).
function VehicleDrive.shake(t: number, speedMs: number, rough: number, rpm: number): (number, number, number, number)
	local s = math.clamp(speedMs / 13, 0, 1.2)
	local amp = math.rad(0.05 + 0.5 * rough * s) -- terreno
	local eng = math.rad(0.03 * math.clamp(rpm, 0, 1.1)) -- motor
	local f = 7 + 6 * s
	local p = math.noise(t * f, 1.7) * amp + math.noise(t * 31, 4.1) * eng
	local y = math.noise(t * f * 0.7, 8.3) * amp * 0.4
	local r = math.noise(t * f * 0.9, 12.9) * amp * 0.8 + math.noise(t * 27, 2.2) * eng
	local bob = math.noise(t * f * 0.6, 21.5) * 0.02 * rough * s
	return p, y, r, bob
end

-- ===== UH-34D: rotor, atitude e pouso =====
VehicleDrive.HELI = {
	spinUpS = 9, -- partida do rotor até a rotação de voo (PLACEHOLDER)
	spinDownS = 14,
	rotorRpm = 220, -- só visual (PLACEHOLDER)
	tailRpm = 1100, -- só visual (PLACEHOLDER)
	attHz = 0.55, -- resposta da atitude ao cíclico
	attZeta = 0.9,
	vyTauS = 0.9, -- inércia vertical
	yawTauS = 0.6,
	coordStartMs = 8, -- curva coordenada: a cauda (deriva) alinha o nariz com a velocidade
	coordFullMs = 20,
	touchMs = 1.2, -- assistência de pouso: descida máxima ao tocar o chão (design)
	cushionPerM = 0.8, -- e mais 0,8 m/s por metro de altura das rodas
	cushionM = 12, -- acima disso não há envelope (a 12 m ele já é 10,8 m/s, mais que a descida do modelo)
}

-- Rotor: 0 parado .. 1 rotação de voo. A sustentação disponível escala com rotor².
function VehicleDrive.rotorStep(rotor: number, on: boolean, dt: number): number
	local H = VehicleDrive.HELI
	if on then
		return math.min(1, rotor + dt / H.spinUpS)
	end
	return math.max(0, rotor - dt / H.spinDownS)
end

-- Atitude (rad) com inércia de 2ª ordem: suave para sair e para chegar (sem tranco no controle).
function VehicleDrive.attitude(x: number, xv: number, target: number, dt: number): (number, number)
	local H = VehicleDrive.HELI
	local w = 2 * math.pi * H.attHz
	local n = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / n
	for _ = 1, n do
		xv += (w * w * (target - x) - 2 * H.attZeta * w * xv) * h
		x += xv * h
	end
	return x, xv
end

-- Velocidade vertical (m/s): segue a subida do modelo com inércia; perto do chão a descida é amortecida
-- (efeito solo e o piloto "segurando" o coletivo) até `touchMs` no toque. gearH = altura das rodas (m).
function VehicleDrive.heliVertical(vy: number, climb: number, gearH: number, dt: number): number
	local H = VehicleDrive.HELI
	local v = approach(vy, climb, H.vyTauS, dt)
	if gearH < H.cushionM then
		-- envelope: descida máxima = touchMs + cushionPerM × altura. A altura cai suave (exponencial),
		-- então a desaceleração também é suave (~0,3 g a 4 m descendo a 4 m/s)
		v = math.max(v, -(H.touchMs + H.cushionPerM * math.max(gearH, 0)))
	end
	return v
end

-- Guinada da curva coordenada (rad/s): inclinado em velocidade, o nariz acompanha a curva.
-- roll > 0 = lado direito para cima (curva para a esquerda, guinada +).
function VehicleDrive.coordinatedYaw(roll: number, speedMs: number): number
	local H = VehicleDrive.HELI
	if speedMs < H.coordStartMs then
		return 0
	end
	local k = math.clamp((speedMs - H.coordStartMs) / (H.coordFullMs - H.coordStartMs), 0, 1)
	return k * G * math.tan(roll) / math.max(speedMs, 1)
end

return VehicleDrive
