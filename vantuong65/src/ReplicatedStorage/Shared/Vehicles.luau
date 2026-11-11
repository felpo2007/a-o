--!strict
-- Veículos da F4 (Parte 9.7): ficha com fonte por número, tração por potência/atrito/resistência ao
-- rolamento por tipo de chão, transição água–areia do LVTP-5 e blindagem por zona.
-- Fonte das fichas: research/veiculos/wikipedia_infobox_2026-11-09.json (marcado "wiki:").
local VehicleDrive = require(script and (script :: any).Parent.VehicleDrive or "./VehicleDrive") :: any

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
		powerHp = 750, -- diesel Continental AVDS-1790-2 do M48A3 (FAS DoD-101; afvdatabase)
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
			-- lado: 76 mm na metade da frente e 51 mm na de trás; uma zona só, com o valor da frente
			side = { mm = 76, slopeDeg = 0, src = "FAS DoD-101 M48 (lado 76 mm na frente, 51 mm atrás)" },
			rear = { mm = 44, slopeDeg = 0, src = "FAS DoD-101 M48 (traseira 44 mm)" },
			top = { mm = 25, slopeDeg = 0, src = PH .. " (o piso é 25 mm, FAS)" },
		},
		turretDegS = 24, -- giro hidráulico máximo 24°/s (afvdatabase M48)
		src = {
			massKg = "wiki:M48_Patton (M48: 49,6 ST)",
			dims = "wiki:M48_Patton (9,3 x 3,65 x 3,1 m)",
			powerHp = "FAS DoD-101 M48; afvdatabase (AVDS-1790-2, 750 hp)",
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
			-- 13 mm (0,5 pol.) no casco e na superestrutura; o piso tem 6,5 mm (tanks-encyclopedia M50)
			front = { mm = 13, slopeDeg = 0, src = "tanks-encyclopedia M50 Ontos (13 mm)" },
			side = { mm = 13, slopeDeg = 0, src = "tanks-encyclopedia M50 Ontos (13 mm)" },
			rear = { mm = 13, slopeDeg = 0, src = "tanks-encyclopedia M50 Ontos (13 mm)" },
			top = { mm = 13, slopeDeg = 0, src = "tanks-encyclopedia M50 Ontos (13 mm)" },
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

-- Chão, motor, câmbio, lagarta e água ficam em Shared/VehicleDrive (2026-11-11). Aqui só o atalho
-- da F4: c_rr, tração e teto por chão (D-36 e PLACEHOLDER, ver VehicleDrive.GROUND).
Vehicles.SURFACE = VehicleDrive.GROUND
Vehicles.DRIVE_EFF = VehicleDrive.DRIVE_EFF -- eficiência motor→esteira (estimativa de engenharia, D-36)

export type DriveState = { v: number, full: any? }

-- Velocidade longitudinal (m/s) com o acelerador fixo em chão plano, sem curva. throttle em [-1, 1].
-- Mesmo modelo do controle (VehicleDrive.step: rotação, conversor, marchas, teto por chão, água).
function Vehicles.drive(spec: Spec, st: DriveState, throttle: number, surface: string, dt: number): number
	local full = st.full or VehicleDrive.newState()
	st.full = full
	full.v = st.v
	VehicleDrive.step(spec, full, { throttle = throttle, steer = 0 }, { ground = surface }, dt)
	st.v = full.v
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

-- Munições contra blindagem (mm RHA), com a fonte de cada uma (D-61). As fontes dão faixas; usamos
-- o valor de referência mais citado e, no PG-2, o piso da faixa.
Vehicles.PEN = {
	pg2 = 150, -- RPG-2 (PG-2 HEAT): 150–180 mm (wiki:RPG-2; weaponsystems.net)
	rocket_35 = 280, -- bazuca M20 3,5 pol. (M28A2 HEAT): ~11 pol. de chapa homogênea (koreanwaronline; weaponsystems.net 280 mm)
	heat_106 = 400, -- M40A1C, M344 HEAT: "mais de 400 mm" (wiki:M40_recoilless_rifle)
	heat_90 = 280, -- 90 mm HEAT do M48A3: PLACEHOLDER (sem fonte)
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
