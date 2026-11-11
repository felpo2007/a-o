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

-- Armas-base por papel (Parte 4). Itens com arma desligada usam a pistola até a F4.
Roles.loadout = {
	US = {
		commander = { "m1911" },
		squad_leader = { "m14" },
		rifleman = { "m14" },
		grenadier = { "m79", "m1911" },
		machine_gunner = { "m60" },
		anti_tank = { "m1911" }, -- bazuca 3.5" M20 na F4
		engineer = { "m14" },
		medic = { "m1911" }, -- corpsman
		radio_operator = { "m14" }, -- PRC-10 nas costas
		observer = { "m14" },
		sniper = { "m14" }, -- rifle de precisão da época: modelo a confirmar
		tank_crew = { "m1911" },
		pilot = { "m1911" },
		door_gunner = { "m60" },
		mortar = { "m1911" },
	},
	VC = {
		commander = { "type54" },
		squad_leader = { "type56" },
		rifleman = { "sks" },
		grenadier = { "sks" }, -- granadas de cabo na F4
		machine_gunner = { "rpd" },
		anti_tank = { "type54" }, -- RPG-2 na F4
		engineer = { "sks" },
		medic = { "sks" },
		radio_operator = { "sks" },
		observer = { "type56" },
		sniper = { "sks" }, -- Mosin-Nagant com luneta na F4
		sapper = { "sks" },
		mortar = { "type54" },
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

return Roles
