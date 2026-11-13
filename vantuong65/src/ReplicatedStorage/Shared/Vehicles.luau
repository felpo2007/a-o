--!strict
-- Veículos da F4 (Parte 9.7): ficha com fonte por número, tração por potência/atrito/resistência ao
-- rolamento por tipo de chão, transição água–areia do LVTP-5 e blindagem por zona.
-- Fonte das fichas: research/veiculos/wikipedia_infobox_2026-11-09.json (marcado "wiki:").
-- D-100 (pedido do dono, 2026-11-12: "por que não consigo pilotar tanques, carros e helicópteros?",
-- "coloque a interface do botão para eu entrar", "faça poder atirar de dentro dos veículos"):
--   - carros novos: M151 e M35 (EUA) e a picape Peugeot 403 do VC, com medidas dos scripts do
--     Blender (tools/blender/veic_*.py), rodas pelo nome das peças e um substituto em peças;
--   - cada lugar tem nome, papel (Roles.vehicleSeatRole) e, se é aberto, o ângulo em que a própria
--     arma atira (caçamba, jipe, teto do LVTP-5, porta do UH-34D); fechado não atira;
--   - regras puras de embarque e de desvirar (o VehicleService aplica, o painel mostra).
local VehicleDrive = require(script and (script :: any).Parent.VehicleDrive or "./VehicleDrive") :: any
local Roles = require(script and (script :: any).Parent.Roles or "./Roles") :: any

local Vehicles = {}

Vehicles.G = 9.80665
Vehicles.KMH = 1 / 3.6

-- Ângulo de tiro de um lugar aberto, em graus: centro (a partir da frente do veículo, + para a
-- esquerda, como o giro do Roblox), meia-abertura e a faixa de inclinação (down < 0 < up).
export type Arc = { yaw: number, half: number, down: number, up: number }
export type Seat = { id: string, role: string, weapon: string?, label: string?, open: Arc? }
export type Armor = { mm: number, slopeDeg: number, src: string }
export type Spec = {
	id: string,
	name: string,
	faction: string,
	kind: string, -- "tracked" | "amphibious" | "heli" | "wheeled"
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
	botDrive: boolean?, -- false: os bots não dirigem (o BotDriver foi feito para lagarta)
}

local PH = "PLACEHOLDER (sem fonte)"
local ALL: Arc = { yaw = 0, half = 180, down = -35, up = 50 } -- em cima do casco, para qualquer lado

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
			{ id = "commander", role = "any", weapon = "m60" }, -- M60 da cúpula (montada)
			{ id = "loader", role = "any" }, -- dentro da torre: não atira
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
			{ id = "loader", role = "any" },
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
			{ id = "commander", role = "any", open = ALL }, -- cabeça fora da escotilha: a própria arma
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
			{ id = "copilot", role = "any" },
			{ id = "gunner", role = "any", weapon = "m60" }, -- M60 da porta da direita (montada)
		},
		src = {
			all = "wiki:Sikorsky_H-34 (47 ft 2 in; 14 ft 3,5 in; 11.867 lb; 1.525 hp; 122 mph; 12 soldados no H-34A)",
		},
	},
	-- ===== D-100: carros (modelos do Blender a publicar; até lá, substituto em peças) =====
	-- Medidas: tools/blender/veic_m151.py, veic_m35.py e veic_peugeot403.py (com a fonte de cada
	-- uma lá). Massa, potência e velocidade: valores das fichas que conheço, a CONFERIR na fonte
	-- antes do lançamento (marcados "conferir").
	m151 = {
		id = "m151",
		name = "M151 MUTT",
		faction = "US",
		kind = "wheeled",
		massKg = 1100, -- conferir: wiki:M151_MUTT, ~2.400 lb
		lengthM = 3.353, -- ficha de Haugh: 132 pol (veic_m151.py)
		widthM = 1.60,
		heightM = 1.803, -- com o para-brisa levantado
		powerHp = 72, -- conferir: wiki:M151_MUTT (motor de 2,3 L)
		maxKmh = 106, -- conferir: wiki:M151_MUTT (66 mph)
		seats = {
			{ id = "driver", role = "any" },
			-- jipe sem portas: o carona atira pela direita, por cima do capô até a traseira
			{ id = "passenger", role = "any", open = { yaw = -80, half = 110, down = -30, up = 45 } },
		},
		src = {
			dims = "tools/blender/veic_m151.py (ficha de Haugh, warwheels.net M151DataSheet.pdf)",
			massKg = "conferir (wiki:M151_MUTT)",
		},
		botDrive = false,
	},
	m35 = {
		id = "m35",
		name = "M35 2½ t",
		faction = "US",
		kind = "wheeled",
		massKg = 5900, -- conferir: wiki:M35_2½-ton_cargo_truck (~13.000 lb vazio)
		lengthM = 6.98, -- com o guincho (veic_m35.py)
		widthM = 2.36,
		heightM = 2.82,
		powerHp = 146, -- conferir: REO OA-331 a gasolina do M35 (o M35A2 multicombustível tem 134 hp)
		maxKmh = 90, -- conferir: wiki (56 mph)
		seats = {
			{ id = "driver", role = "any" },
			{ id = "passenger", role = "any" }, -- cabine: não atira
		},
		src = {
			dims = "tools/blender/veic_m35.py (wiki:M35; nf6x.net M35A2C)",
			massKg = "conferir (wiki:M35)",
		},
		botDrive = false,
	},
	peugeot403 = {
		id = "peugeot403",
		name = "Peugeot 403",
		faction = "VC",
		kind = "wheeled",
		massKg = 1150, -- PLACEHOLDER (berlina ~1,1 t; picape sem ficha)
		lengthM = 4.61, -- perua/familiale (veic_peugeot403.py; a picape não tem ficha)
		widthM = 1.67,
		heightM = 1.80, -- com a lona
		powerHp = 58, -- conferir: wiki:Peugeot_403 (1,5 L)
		maxKmh = 115, -- PLACEHOLDER (a berlina passa de 120 km/h; a picape carregada, menos)
		seats = {
			{ id = "driver", role = "any" },
			{ id = "passenger", role = "any" },
		},
		src = {
			dims = "tools/blender/veic_peugeot403.py (wiki:Peugeot_403)",
			all = "requisitada pelo VC: escolha de jogo (sem fonte de uso em Quảng Ngãi em 1965)",
		},
		botDrive = false,
	},
} :: { [string]: Spec }

-- Passageiros: LVTP-5 leva 34 pela ficha e o H-34A, 12. No jogo, 12 e 8 assentos, porque o squad
-- tem 6 (D-37). D-100: M151 com 2 atrás, M35 com 12 na caçamba e a Peugeot com 6 sob a lona.
Vehicles.PASSENGERS = { lvtp5 = 12, uh34d = 8, m48a3 = 0, ontos = 0, m151 = 2, m35 = 12, peugeot403 = 6 }

-- Modelo publicado de cada ficha (chave de AssetIds.Models). Lote dos _v2 (2026-11-12): os blindados e
-- o UH-34D refeitos no Blender na medida real, em peças; as chaves antigas (m48a3, ontos, lvtp5,
-- uh34d) continuam com os modelos velhos. Os números da malha estão em VehicleDrive.ART.
Vehicles.MODEL = {
	m48a3 = "m48a3_v2",
	ontos = "ontos_v2",
	lvtp5 = "lvtp5_v2",
	uh34d = "uh34d_v2",
	m151 = "m151",
	m35 = "m35",
	peugeot403 = "peugeot403",
} :: { [string]: string }

function Vehicles.modelKey(specId: string): string
	return Vehicles.MODEL[specId] or specId
end

-- ===== lugares: nome, papel e ângulo de tiro =====
local LABEL: { [string]: string } = {
	driver = "Motorista",
	gunner = "Atirador",
	commander = "Comandante",
	loader = "Municiador",
	copilot = "Copiloto",
	passenger = "Carona",
}

-- Nome do lugar no painel e no HUD
function Vehicles.seatLabel(specId: string, seatId: string): string
	local spec = Vehicles.SPECS[specId]
	if seatId == "driver" and spec and spec.kind == "heli" then
		return "Piloto"
	elseif seatId == "gunner" and spec and spec.kind == "heli" then
		return "Porta (M60)"
	end
	local n = tonumber(string.match(seatId, "^p(%d+)$"))
	if n then
		return string.format("Tropa %d", n)
	end
	return LABEL[seatId] or seatId
end

-- Ângulo de tiro da própria arma no passageiro "p<n>" (nil = fechado). Ímpar à direita, par à
-- esquerda (como VehicleDrive.eyeOf).
local function passengerArc(specId: string, n: number): Arc?
	local right = n % 2 == 1
	local side = if right then -90 else 90
	if specId == "lvtp5" then
		return ALL -- a tropa vai no teto (as minas)
	elseif specId == "uh34d" then
		return { yaw = side, half = 70, down = -70, up = 15 } -- sentado na porta, pernas para fora
	elseif specId == "m151" then
		return { yaw = if right then -100 else 100, half = 125, down = -30, up = 45 }
	elseif specId == "m35" then
		-- de costas para a grade da caçamba; a última fileira também atira para trás
		local last = (n - 1) // 2 == (Vehicles.PASSENGERS.m35 - 1) // 2
		return { yaw = side, half = if last then 125 else 95, down = -30, up = 40 }
	elseif specId == "peugeot403" then
		-- sob a lona: só a fileira de trás, pela aba enrolada
		if (n - 1) // 2 == (Vehicles.PASSENGERS.peugeot403 - 1) // 2 then
			return { yaw = 180, half = 50, down = -25, up = 30 }
		end
	end
	return nil
end

export type SeatInfo = {
	id: string,
	label: string,
	role: string?, -- papel exigido (nil = qualquer um do lado)
	weapon: string?, -- arma montada no lugar
	open: Arc?, -- aberto: atira com a própria arma neste ângulo
	order: number,
}

-- Lugares em ordem (motorista/piloto primeiro, tropa por último)
function Vehicles.seatList(specId: string): { SeatInfo }
	local spec = Vehicles.SPECS[specId]
	local out: { SeatInfo } = {}
	if not spec then
		return out
	end
	for i, s in spec.seats do
		table.insert(out, {
			id = s.id,
			label = Vehicles.seatLabel(specId, s.id),
			role = Roles.vehicleSeatRole(spec.kind, s.id),
			weapon = s.weapon,
			open = s.open,
			order = i,
		})
	end
	for n = 1, Vehicles.PASSENGERS[specId] or 0 do
		local id = "p" .. n
		table.insert(out, {
			id = id,
			label = Vehicles.seatLabel(specId, id),
			role = nil,
			weapon = nil,
			open = passengerArc(specId, n),
			order = #spec.seats + n,
		})
	end
	return out
end

function Vehicles.seatInfo(specId: string, seatId: string): SeatInfo?
	for _, s in Vehicles.seatList(specId) do
		if s.id == seatId then
			return s
		end
	end
	return nil
end

-- A própria arma atira nesta direção? relYawDeg: rumo do olhar menos o rumo do veículo (graus, +
-- esquerda); pitchDeg: inclinação do olhar (+ para cima).
function Vehicles.inArc(arc: Arc, relYawDeg: number, pitchDeg: number): boolean
	local d = (relYawDeg - arc.yaw + 180) % 360 - 180
	return math.abs(d) <= arc.half + 1e-9 and pitchDeg >= arc.down and pitchDeg <= arc.up
end

-- ===== D-100: carros com rodas (medidas em metros, no referencial do chassi: x para a direita,
-- y para cima a partir do chão, z para trás; a frente é −z, como no Roblox) =====
-- Do Blender (x à frente, y à esquerda, z para cima): x_chassi = −y, y_chassi = z, z_chassi = −x.
-- Rodas pelo nome das peças do modelo (Roda_FE = frente esquerda = lado do motorista; T1/T2 =
-- 1º e 2º eixos de trás do M35). Corpo do substituto em peças: caixas (tamanho e centro, m).
export type Wheel = { name: string, x: number, z: number, steer: boolean }
export type Box = { name: string, size: { number }, at: { number }, color: string }
export type Rows = { z0: number, dz: number, x: number, y: number } -- tropa: fileiras de 2
export type Wheeled = {
	wheelR: number,
	wheelW: number,
	clearanceM: number,
	wheelbaseM: number,
	wheels: { Wheel },
	seatAt: { [string]: { number } },
	rows: Rows?,
	body: { Box },
	stepM: number, -- degrau que a rampa sobe (dique)
	artYawDeg: number, -- giro do GLB publicado em relação ao chassi (conferir no Studio)
	color: string,
}

local function axle(names: { string }, z: number, half: number, steer: boolean): { Wheel }
	return {
		{ name = names[1], x = -half, z = z, steer = steer },
		{ name = names[2], x = half, z = z, steer = steer },
	}
end

local function concat(...: { Wheel }): { Wheel }
	local out = {}
	for _, list in { ... } do
		for _, w in list do
			table.insert(out, w)
		end
	end
	return out
end

Vehicles.WHEELED = {
	-- veic_m151.py: X_FA = 1,10, X_RA = 1,10 − 2,159; bitola 1,346; roda 0,37; vão livre 0,239
	m151 = {
		wheelR = 0.37,
		wheelW = 0.18,
		clearanceM = 0.239,
		wheelbaseM = 2.159,
		wheels = concat(
			axle({ "Roda_FE", "Roda_FD" }, -1.10, 1.346 / 2, true),
			axle({ "Roda_TE", "Roda_TD" }, 2.159 - 1.10, 1.346 / 2, false)
		),
		seatAt = { driver = { -0.36, 0.77, 0.05 }, passenger = { 0.36, 0.77, 0.05 } },
		rows = { z0 = 1.02, dz = 0.5, x = 0.3, y = 0.74 },
		body = {
			{ name = "Casco", size = { 1.56, 0.62, 3.25 }, at = { 0, 0.69, 0 }, color = "paint" },
			{ name = "Capo", size = { 1.16, 0.12, 1.0 }, at = { 0, 1.02, -1.15 }, color = "paint" },
			{ name = "ParaBrisa", size = { 1.42, 0.76, 0.05 }, at = { 0, 1.42, -0.62 }, color = "glass" },
			{ name = "Banco", size = { 1.2, 0.1, 0.42 }, at = { 0, 0.74, 1.02 }, color = "canvas" },
			-- estepe em pé na traseira, eixo para trás (veic_m151.py: torno no eixo X do Blender)
			{ name = "Estepe", size = { 0.74, 0.74, 0.18 }, at = { 0.3, 0.84, 1.58 }, color = "tire" },
		},
		stepM = 0.4,
		artYawDeg = -90,
		color = "us",
	},
	-- veic_m35.py: X_FA = 3,49 − 1,15; eixos de trás a ±0,65 de X_FA − 3,91; bitola 1,72; roda 0,48
	m35 = {
		wheelR = 0.48,
		wheelW = 0.46, -- duplas atrás numa peça (a da frente é simples)
		clearanceM = 0.3,
		wheelbaseM = 3.91,
		wheels = concat(
			axle({ "Roda_FE", "Roda_FD" }, -2.34, 1.72 / 2, true),
			axle({ "Roda_T1E", "Roda_T1D" }, 0.92, 1.72 / 2, false),
			axle({ "Roda_T2E", "Roda_T2D" }, 2.22, 1.72 / 2, false)
		),
		seatAt = { driver = { -0.45, 1.55, -0.7 }, passenger = { 0.45, 1.55, -0.7 } },
		rows = { z0 = 0.23, dz = 0.55, x = 0.85, y = 1.7 },
		body = {
			{ name = "Chassi", size = { 1.1, 0.4, 6.8 }, at = { 0, 0.9, 0 }, color = "paint" },
			{ name = "Capo", size = { 1.3, 0.9, 1.9 }, at = { 0, 1.45, -2.45 }, color = "paint" },
			{ name = "Cabine", size = { 2.1, 1.3, 1.12 }, at = { 0, 2.1, -0.91 }, color = "paint" },
			{ name = "Cacamba", size = { 2.36, 0.12, 3.66 }, at = { 0, 1.25, 1.66 }, color = "paint" },
			{ name = "GradeE", size = { 0.06, 0.6, 3.66 }, at = { -1.15, 1.6, 1.66 }, color = "wood" },
			{ name = "GradeD", size = { 0.06, 0.6, 3.66 }, at = { 1.15, 1.6, 1.66 }, color = "wood" },
		},
		stepM = 0.5,
		artYawDeg = -90,
		color = "us",
	},
	-- veic_peugeot403.py: X_FA = 2,305 − 0,75, X_RA = X_FA − 2,90; bitola 1,35; roda 0,32
	peugeot403 = {
		wheelR = 0.32,
		wheelW = 0.165,
		clearanceM = 0.18,
		wheelbaseM = 2.90,
		wheels = concat(
			axle({ "Roda_FE", "Roda_FD" }, -1.555, 1.35 / 2, true),
			axle({ "Roda_TE", "Roda_TD" }, 1.345, 1.35 / 2, false)
		),
		seatAt = { driver = { -0.38, 0.67, -0.12 }, passenger = { 0.38, 0.67, -0.12 } },
		rows = { z0 = 0.75, dz = 0.5, x = 0.5, y = 0.9 },
		body = {
			{ name = "Casco", size = { 1.67, 0.6, 4.5 }, at = { 0, 0.64, 0 }, color = "civil" },
			{ name = "Cabine", size = { 1.5, 0.55, 1.14 }, at = { 0, 1.22, -0.29 }, color = "civil" },
			{ name = "Lona", size = { 1.6, 0.85, 2.0 }, at = { 0, 1.37, 1.29 }, color = "canvas" },
		},
		stepM = 0.3,
		artYawDeg = -90,
		color = "civil",
	},
} :: { [string]: Wheeled }

-- Posição do lugar (m, referencial do chassi a partir do chão) no carro; nil se não é carro
function Vehicles.wheeledSeatAt(specId: string, seatId: string): { number }?
	local w = Vehicles.WHEELED[specId]
	if not w then
		return nil
	end
	local fixed = w.seatAt[seatId]
	if fixed then
		return fixed
	end
	local n = tonumber(string.match(seatId, "^p(%d+)$"))
	local r = w.rows
	if not (n and r) or n > (Vehicles.PASSENGERS[specId] or 0) then
		return nil
	end
	local row = (n - 1) // 2
	return { (if n % 2 == 1 then 1 else -1) * r.x, r.y, r.z0 + row * r.dz }
end

-- ===== D-100: embarque (o VehicleService aplica; o painel mostra) =====
export type BoardCtx = {
	sameFaction: boolean,
	destroyed: boolean,
	alive: boolean, -- vivo e de pé (não caído)
	near: boolean, -- perto do veículo ou já dentro dele
	inOther: boolean, -- sentado em outro veículo
	seatExists: boolean,
	seatFree: boolean, -- vazio (ou é o próprio lugar)
	kind: string,
	seatId: string,
	role: string?, -- papel do squad
	crewRole: string?, -- papel de campo (VehicleCrew)
	wantCrew: boolean, -- pediu "trocar para tripulante/piloto e entrar"
	vacancy: boolean, -- há vaga no time para o papel que falta
}

-- "ok" | "crew" (entra assumindo o papel de campo) | motivo da recusa (texto para o aviso).
-- Segundo valor: o papel que falta (para o botão de troca).
function Vehicles.boardCheck(c: BoardCtx): (string, string?)
	if not c.alive then
		return "Fora de combate", nil
	elseif not c.sameFaction then
		return "Veículo do outro lado", nil
	elseif c.destroyed then
		return "Veículo destruído", nil
	elseif c.inOther then
		return "Saia do outro veículo antes", nil
	elseif not c.near then
		return "Longe demais", nil
	elseif not c.seatExists then
		return "Lugar inexistente", nil
	elseif not c.seatFree then
		return "Lugar ocupado", nil
	end
	local ok, need = Roles.canTakeSeat(c.kind, c.seatId, c.role, c.crewRole)
	if ok then
		return "ok", nil
	end
	local name = Roles.CREW_NAME[need :: string] or need
	if not c.vacancy then
		return string.format("Sem vaga de %s no time", string.lower(name :: string)), need
	elseif not c.wantCrew then
		return string.format("Este lugar pede %s", string.lower(name :: string)), need
	end
	return "crew", need
end

-- ===== D-100: desvirar e desatolar =====
-- Tombado (de lado, de ponta-cabeça) ou preso (motor acelerando e parado) e quase parado: segurar o
-- botão do painel levanta 1,5 m e põe em pé, no mesmo lugar e rumo. Um por veículo a cada 8 s.
Vehicles.RECOVER = { tippedUpY = 0.6, maxMps = 1.5, cooldownS = 8, liftM = 1.5, stuckS = 3 }

function Vehicles.tipped(upY: number): boolean
	return upY < Vehicles.RECOVER.tippedUpY
end

function Vehicles.canRecover(upY: number, speedMps: number, stuck: boolean, sinceLastS: number): (boolean, string)
	local R = Vehicles.RECOVER
	if sinceLastS < R.cooldownS then
		return false, "Espere um pouco"
	elseif speedMps > R.maxMps then
		return false, "Pare o veículo antes"
	elseif not (Vehicles.tipped(upY) or stuck) then
		return false, "O veículo não está tombado nem preso"
	end
	return true, "ok"
end

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
