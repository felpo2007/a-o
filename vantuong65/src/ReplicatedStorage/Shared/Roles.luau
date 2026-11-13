--!strict
-- Estrutura dos times e papéis (Parte 4). 50 por time (D-91: o servidor do Roblox aceita até 100
-- jogadores); as vagas somam mais que 50 de propósito.
local Roles = {}

Roles.TEAM_MAX = 50
Roles.HEAVY_UNLOCK = 16 -- blindado, helicóptero e morteiro só com o time a partir de 16

export type RoleDef = { id: string, name: string, unit: string, maxPerSquad: number? }
Roles.roles = {
	commander = { id = "commander", name = "Comandante", unit = "command", maxPerSquad = 1 },
	squad_leader = { id = "squad_leader", name = "Líder de squad", unit = "infantry", maxPerSquad = 1 },
	rifleman = { id = "rifleman", name = "Fuzileiro", unit = "infantry" },
	-- só dos EUA (não tem loadout no VC): o fuzileiro automático da esquadra de tiro do USMC, com a M14
	-- de seletor e bipé M2 (FM 23-8, 1965, par. 3a; Small Arms Review: 1 em automático por esquadra
	-- de 4 em Chu Lai, 1965). Um por squad: o squad do jogo (6) é menor que o de 1965 (13, com 3
	-- esquadras). Decisão do dono, 2026-11-12.
	automatic_rifleman = {
		id = "automatic_rifleman",
		name = "Fuzileiro automático",
		unit = "infantry",
		maxPerSquad = 1,
	},
	grenadier = { id = "grenadier", name = "Granadeiro", unit = "infantry", maxPerSquad = 1 },
	machine_gunner = { id = "machine_gunner", name = "Metralhador", unit = "infantry", maxPerSquad = 1 },
	anti_tank = { id = "anti_tank", name = "Antitanque", unit = "infantry", maxPerSquad = 1 },
	engineer = { id = "engineer", name = "Engenheiro/sapador", unit = "infantry", maxPerSquad = 1 },
	medic = { id = "medic", name = "Médico", unit = "infantry", maxPerSquad = 1 },
	radio_operator = { id = "radio_operator", name = "Operador de rádio", unit = "infantry", maxPerSquad = 1 },
	observer = { id = "observer", name = "Observador", unit = "recon", maxPerSquad = 1 },
	sniper = { id = "sniper", name = "Atirador de elite", unit = "recon", maxPerSquad = 1 },
	tank_crew = { id = "tank_crew", name = "Tripulante de blindado", unit = "armor", maxPerSquad = 3 },
	pilot = { id = "pilot", name = "Piloto", unit = "helicopter", maxPerSquad = 1 },
	door_gunner = { id = "door_gunner", name = "Atirador de porta", unit = "helicopter", maxPerSquad = 1 },
	mortar = { id = "mortar", name = "Morteiro", unit = "mortar", maxPerSquad = 3 },
	sapper = { id = "sapper", name = "Sapador de túnel", unit = "sapper", maxPerSquad = 4 },
} :: { [string]: RoleDef }

-- unidades por facção: quantidade máxima e tamanho
export type UnitDef = { count: number, size: number, heavy: boolean, names: { string } }
Roles.units = {
	US = {
		command = { count = 1, size = 1, heavy = false, names = { "Comando" } },
		infantry = {
			count = 7,
			size = 6,
			heavy = false,
			names = { "Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf" },
		},
		recon = { count = 1, size = 2, heavy = false, names = { "Recon" } },
		armor = { count = 1, size = 3, heavy = true, names = { "Blindado" } },
		helicopter = { count = 1, size = 2, heavy = true, names = { "Helicóptero" } },
		mortar = { count = 1, size = 3, heavy = true, names = { "Morteiro" } },
	},
	VC = {
		command = { count = 1, size = 1, heavy = false, names = { "Chỉ huy" } },
		infantry = {
			count = 8,
			size = 6,
			heavy = false,
			names = {
				"Tiểu đội 1",
				"Tiểu đội 2",
				"Tiểu đội 3",
				"Tiểu đội 4",
				"Tiểu đội 5",
				"Tiểu đội 6",
				"Tiểu đội 7",
				"Tiểu đội 8",
			},
		},
		recon = { count = 1, size = 2, heavy = false, names = { "Trinh sát" } },
		sapper = { count = 1, size = 4, heavy = false, names = { "Đặc công" } },
		mortar = { count = 1, size = 3, heavy = true, names = { "Cối" } },
	},
} :: { [string]: { [string]: UnitDef } }

-- Armas-base por papel (Parte 4): a principal (vaga 1) e a pistola (vaga 2; Shared/Equipar).
-- 2026-11-13 (pedido do dono: "coloque arma secundária para todos"): todo papel leva a pistola do lado
-- (M1911A1 nos EUA, Tipo 54 no VC). Os papéis que só tinham a pistola ganharam a arma longa do lado
-- (comandante, corpsman e morteiro dos EUA com a M14; comandante e morteiro do VC com a SKS, sem mexer
-- no kit do corpo: PLACEHOLDER, decisão de jogo). Ficam só com a pistola: antitanque (a principal é o lançador, que
-- o WeaponController põe depois dela), tripulante e piloto (a principal é o veículo; o tanquista de
-- 1965 levava a M3A1, que o jogo não tem).
Roles.loadout = {
	US = {
		commander = { "m14", "m1911" },
		squad_leader = { "m14", "m1911" },
		rifleman = { "m14", "m1911" },
		automatic_rifleman = { "m14", "m1911" }, -- com o seletor aberto e o bipé (Weapons.roleModes/bipodRoles)
		grenadier = { "m79", "m1911" },
		machine_gunner = { "m60", "m1911" },
		anti_tank = { "m1911" }, -- + bazuca 3.5" M20 (vaga "launcher")
		engineer = { "m14", "m1911" },
		medic = { "m14", "m1911" }, -- corpsman
		radio_operator = { "m14", "m1911" }, -- PRC-10 nas costas
		observer = { "m14", "m1911" },
		sniper = { "m70", "m1911" }, -- Winchester M70 com Unertl 8x (USMC, 1965; Shared/Weapons)
		tank_crew = { "m1911" },
		pilot = { "m1911" },
		door_gunner = { "m60", "m1911" },
		mortar = { "m14", "m1911" },
	},
	VC = {
		commander = { "sks", "type54" },
		squad_leader = { "type56", "type54" },
		rifleman = { "sks", "type54" },
		grenadier = { "sks", "type54" }, -- granadas de cabo na F4
		machine_gunner = { "rpd", "type54" },
		anti_tank = { "type54" }, -- + RPG-2 (vaga "launcher")
		engineer = { "sks", "type54" },
		medic = { "sks", "type54" },
		radio_operator = { "sks", "type54" },
		observer = { "type56", "type54" },
		sniper = { "mosin", "type54" }, -- Mosin-Nagant 91/30 com luneta PU 3,5x (Shared/Weapons)
		sapper = { "sks", "type54" },
		mortar = { "sks", "type54" },
	},
} :: { [string]: { [string]: { string } } }

-- Posto mínimo por papel (progressão, 2026-11-11; Shared/Progression). Só papéis de especialista: os
-- de infantaria e o líder de squad ficam no posto 1, para um servidor novo (todos no posto 1) não
-- ficar sem squad nem construção. PLACEHOLDER até o playtest.
Roles.MIN_RANK = {
	commander = 3,
	sniper = 3,
	pilot = 3,
	observer = 2,
	tank_crew = 2,
	door_gunner = 2,
} :: { [string]: number }

function Roles.minRank(roleId: string): number
	return Roles.MIN_RANK[roleId] or 1
end

function Roles.unitAllowed(faction: string, unit: string, teamSize: number): boolean
	local u = Roles.units[faction] and Roles.units[faction][unit]
	if not u then
		return false
	end
	return not u.heavy or teamSize >= Roles.HEAVY_UNLOCK
end

function Roles.roleAllowedInUnit(faction: string, roleId: string, unit: string): boolean
	local r = Roles.roles[roleId]
	return r ~= nil and r.unit == unit and Roles.loadout[faction][roleId] ~= nil
end

-- ===== papel nos lugares dos veículos (D-100) =====
-- Pedido do dono, 2026-11-12: "por que não consigo pilotar tanques, carros e helicópteros?". Antes
-- todo lugar de blindado pedia "tank_crew" e o UH-34D pedia piloto e atirador de porta; esses papéis
-- exigem posto 2 ou 3 e um squad pesado, que só abre com 16 jogadores no time. Regra nova:
--   - carro e caminhão (kind "wheeled"): qualquer um do lado dirige e senta;
--   - blindado e anfíbio: motorista e atirador pedem tripulante; comandante, municiador e tropa não;
--   - helicóptero: o lugar do piloto pede piloto; copiloto, porta e tropa não.
-- Faltou o papel e há vaga no time (mais lugares que pedem o papel do que gente com ele), o próprio
-- painel do veículo oferece "Trocar para Tripulante/Piloto e entrar": vale até morrer (atributo
-- "VehicleCrew" do jogador), sem mexer no squad, na arma nem no posto.
Roles.VEHICLE_SEAT_ROLE = {
	tracked = { driver = "tank_crew", gunner = "tank_crew" },
	amphibious = { driver = "tank_crew", gunner = "tank_crew" },
	heli = { driver = "pilot" },
} :: { [string]: { [string]: string } }
Roles.CREW_NAME = { tank_crew = "Tripulante", pilot = "Piloto" } :: { [string]: string }

-- Papel que o lugar pede (nil = qualquer um do lado)
function Roles.vehicleSeatRole(kind: string, seatId: string): string?
	local t = Roles.VEHICLE_SEAT_ROLE[kind]
	return if t then t[seatId] else nil
end

-- O jogador (papel do squad e papel de campo) pode sentar? Devolve (pode, papel que falta).
function Roles.canTakeSeat(kind: string, seatId: string, role: string?, crewRole: string?): (boolean, string?)
	local need = Roles.vehicleSeatRole(kind, seatId)
	if need == nil or role == need or crewRole == need then
		return true, nil
	end
	return false, need
end

-- Há vaga para mais um com o papel? seats = lugares do lado que pedem o papel; holders = quem já tem.
function Roles.crewVacancy(seats: number, holders: number): boolean
	return holders < seats
end

return Roles
