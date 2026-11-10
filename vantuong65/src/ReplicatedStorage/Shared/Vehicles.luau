--!strict
-- Veículos da F4 (Parte 9.7): ficha com fonte por número, tração por potência/atrito/resistência ao
-- rolamento por tipo de chão, transição água–areia do LVTP-5 e blindagem por zona.
-- Fonte das fichas: research/veiculos/wikipedia_infobox_2026-11-09.json (marcado "wiki:").
local Vehicles = {}

Vehicles.G = 9.80665
Vehicles.KMH = 1 / 3.6

export type Seat = { id: string, role: string, weapon: string? }
export type Armor = { mm: number, slopeDeg: number, src: string }
export type Spec = {
	id: string,
	name: string,
	faction: string,
	kind: string, -- "tracked" | "amphibious" | "heli"
	massKg: number,
	lengthM: number,
	widthM: number,
	heightM: number,
	powerHp: number,
	maxKmh: number,
	waterKmh: number?,
	seats: { Seat },
	armor: { [string]: Armor }?, -- front | side | rear | top
	turretDegS: number?, -- giro da torre (graus/s)
	src: { [string]: string },
}

local PH = "PLACEHOLDER (sem fonte)"

Vehicles.SPECS = {
	m48a3 = {
		id = "m48a3",
		name = "M48A3 Patton",
		faction = "US",
		kind = "tracked",
		massKg = 45000, -- 49,6 short tons (M48) = 45,0 t
		lengthM = 9.3, -- com o canhão
		widthM = 3.65,
		heightM = 3.1,
		powerHp = 750, -- AVDS-1790-2 do M48A3: confirmar na ficha (D-36)
		maxKmh = 48, -- 30 mph (valor da infobox para o M48A5)
		seats = {
			{ id = "driver", role = "tank_crew" },
			{ id = "gunner", role = "tank_crew", weapon = "gun_90" },
			{ id = "commander", role = "tank_crew", weapon = "m60" },
			{ id = "loader", role = "tank_crew" },
		},
		armor = {
			front = { mm = 110, slopeDeg = 60, src = "wiki:M48_Patton (glacis 110 mm a 60°)" },
			turret = { mm = 178, slopeDeg = 0, src = "wiki:M48_Patton (frente da torre)" },
			side = { mm = 76, slopeDeg = 0, src = PH },
			rear = { mm = 51, slopeDeg = 0, src = PH },
			top = { mm = 25, slopeDeg = 0, src = PH },
		},
		turretDegS = 24, -- PLACEHOLDER (giro hidráulico)
		src = {
			massKg = "wiki:M48_Patton (M48: 49,6 ST)",
			dims = "wiki:M48_Patton (9,3 x 3,65 x 3,1 m)",
			powerHp = "D-36: a confirmar (infobox lista o motor por versão)",
			maxKmh = "wiki:M48_Patton (M48A5: 30 mph)",
		},
	},
	ontos = {
		id = "ontos",
		name = "M50 Ontos",
		faction = "US",
		kind = "tracked",
		massKg = 8600,
		lengthM = 3.83,
		widthM = 2.59,
		heightM = 2.13,
		powerHp = 145,
		maxKmh = 48,
		seats = {
			{ id = "driver", role = "tank_crew" },
			{ id = "gunner", role = "tank_crew", weapon = "rr_106" },
			{ id = "loader", role = "tank_crew" },
		},
		armor = {
			front = { mm = 13, slopeDeg = 0, src = PH },
			side = { mm = 13, slopeDeg = 0, src = PH },
			rear = { mm = 13, slopeDeg = 0, src = PH },
			top = { mm = 13, slopeDeg = 0, src = PH },
		},
		turretDegS = 30, -- PLACEHOLDER
		src = { all = "wiki:M50_Ontos (8.600 kg; 3,83 x 2,59 x 2,13 m; 145 hp; 48 km/h; 3 tripulantes; 6 x M40A1C)" },
	},
	lvtp5 = {
		id = "lvtp5",
		name = "LVTP-5",
		faction = "US",
		kind = "amphibious",
		massKg = 37400,
		lengthM = 9.04,
		widthM = 3.57,
		heightM = 2.92,
		powerHp = 704,
		maxKmh = 48,
		waterKmh = 11,
		seats = {
			{ id = "driver", role = "tank_crew" },
			{ id = "gunner", role = "tank_crew", weapon = "m60" }, -- cúpula .30: usamos a M60 como aproximação
			{ id = "commander", role = "tank_crew" },
		},
		armor = {
			front = { mm = 16, slopeDeg = 0, src = "wiki:LVTP-5 (6–16 mm)" },
			side = { mm = 6, slopeDeg = 0, src = "wiki:LVTP-5 (6–16 mm)" },
			rear = { mm = 6, slopeDeg = 0, src = "wiki:LVTP-5 (6–16 mm)" },
			top = { mm = 6, slopeDeg = 0, src = "wiki:LVTP-5 (6–16 mm)" },
		},
		src = { all = "wiki:LVTP-5 (37,4 t; 9,04 x 3,57 x 2,92 m; 704 hp; 48 km/h, 11 km/h na água; 3+34)" },
	},
	-- UH-34D: dimensões e massa da ficha do H-34 (wiki:Sikorsky_H-34); voo em Shared/HeliModel.
	uh34d = {
		id = "uh34d",
		name = "UH-34D Seahorse",
		faction = "US",
		kind = "heli",
		massKg = 11867 * 0.45359237, -- peso bruto
		lengthM = (47 * 12 + 2) * 0.0254, -- fuselagem 47 ft 2 in
		widthM = 4.0, -- PLACEHOLDER (fuselagem; a largura da ficha inclui o rotor dobrado)
		heightM = (14 * 12 + 3.5) * 0.0254,
		powerHp = 1525,
		maxKmh = 122 * 1.609344,
		seats = {
			{ id = "driver", role = "pilot" },
			{ id = "copilot", role = "pilot" },
			{ id = "gunner", role = "door_gunner", weapon = "m60" },
		},
		src = {
			all = "wiki:Sikorsky_H-34 (47 ft 2 in; 14 ft 3,5 in; 11.867 lb; 1.525 hp; 122 mph; 12 soldados no H-34A)",
		},
	},
} :: { [string]: Spec }

-- Passageiros: LVTP-5 leva 34 pela ficha e o H-34A, 12. No jogo, 12 e 8 assentos, porque o squad
-- tem 6 (D-37).
Vehicles.PASSENGERS = { lvtp5 = 12, uh34d = 8, m48a3 = 0, ontos = 0 }

-- Chão → (fator de resistência ao rolamento c_rr, atrito μ, fator de velocidade máxima).
-- Ordem de grandeza de veículos de esteira (estimativa de engenharia, D-36): c_rr 0,03–0,05 em chão
-- firme e 0,1–0,2 em solo mole. A lama do arrozal corta a velocidade.
Vehicles.SURFACE = {
	road = { crr = 0.04, mu = 0.8, vmax = 1.0 },
	earth = { crr = 0.06, mu = 0.7, vmax = 0.85 },
	sand = { crr = 0.12, mu = 0.5, vmax = 0.6 },
	paddy = { crr = 0.18, mu = 0.4, vmax = 0.35 },
	water = { crr = 0, mu = 0, vmax = 0 }, -- só anfíbios: usam waterKmh
} :: { [string]: { crr: number, mu: number, vmax: number } }

Vehicles.DRIVE_EFF = 0.6 -- eficiência motor→esteira (estimativa de engenharia, D-36)

export type DriveState = { v: number }

-- Integra a velocidade longitudinal (m/s). throttle em [-1, 1]. Devolve a nova velocidade.
function Vehicles.drive(spec: Spec, st: DriveState, throttle: number, surface: string, dt: number): number
	local s = Vehicles.SURFACE[surface] or Vehicles.SURFACE.earth
	local m = spec.massKg
	local vmax: number
	if surface == "water" then
		if spec.kind ~= "amphibious" then
			st.v *= math.max(0, 1 - 2 * dt) -- encalha/afoga: perde tração
			return st.v
		end
		vmax = (spec.waterKmh or 0) * Vehicles.KMH
	else
		vmax = spec.maxKmh * Vehicles.KMH * s.vmax
	end
	local reverseMax = vmax * 0.35
	local target = if throttle >= 0 then throttle * vmax else throttle * reverseMax
	local p = spec.powerHp * 745.7 * Vehicles.DRIVE_EFF
	local fTraction = math.min(p / math.max(math.abs(st.v), 1.0), s.mu * m * Vehicles.G)
	if surface == "water" then
		fTraction = p / math.max(math.abs(st.v), 1.0) * 0.15 -- hélice/esteira na água: pouco empuxo
	end
	local fRoll = s.crr * m * Vehicles.G
	local a: number
	if math.abs(target - st.v) < 0.05 then
		a = 0
	elseif target > st.v then
		a = (fTraction - fRoll) / m
	else
		a = -(fTraction + fRoll) / m -- freio/inversão
	end
	local nv = st.v + a * dt
	if (target - st.v) * (target - nv) < 0 then
		nv = target
	end
	st.v = math.clamp(nv, -reverseMax, vmax)
	return st.v
end

-- Blindagem: espessura efetiva na linha de tiro. `impactDeg` = ângulo entre o tiro e a normal da
-- placa já incluindo a inclinação da placa. HEAT não normaliza.
function Vehicles.effectiveMm(mm: number, impactDeg: number): number
	local c = math.cos(math.rad(math.clamp(impactDeg, 0, 85)))
	return mm / c
end

-- Penetração da munição (mm RHA) contra uma zona; `u` em [0,1) dá ±5% de variação.
function Vehicles.penetrates(penMm: number, armor: Armor, extraDeg: number, u: number): (boolean, number)
	local eff = Vehicles.effectiveMm(armor.mm, armor.slopeDeg + extraDeg)
	local pen = penMm * (0.95 + 0.1 * u)
	return pen >= eff, pen / eff
end

-- Munições contra blindagem (mm RHA). Todas PLACEHOLDER até a ficha técnica (D-36).
Vehicles.PEN = {
	pg2 = 150, -- RPG-2 (PG-2 HEAT)
	rocket_35 = 250, -- bazuca M20 3,5 pol. (M28A2 HEAT)
	heat_106 = 400, -- M40A1C, M344 HEAT
	he_90 = 40, -- 90 mm HE (efeito por estilhaço/sopro)
	m60 = 8, -- 7,62 mm comum a curta distância
	rpd = 8,
}

-- Zona atingida pela direção do tiro no quadro do veículo (frente = -Z local, como no Roblox).
function Vehicles.zoneFromLocal(dx: number, dy: number, dz: number): string
	if dy < -0.7 then
		return "top"
	end
	local ax, az = math.abs(dx), math.abs(dz)
	if az >= ax then
		return if dz > 0 then "front" else "rear" -- o tiro viaja para +Z local = vindo da frente
	end
	return "side"
end

return Vehicles
