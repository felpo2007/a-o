--!strict
-- Estrutura dos times e papéis (Parte 4). 50 por time (D-91: o servidor do Roblox aceita até 100
-- jogadores); as vagas somam mais que 50 de propósito.
-- D-108 (pedido do dono, 2026-11-13: "faça classes mais simples, tem muitas"): de 16 papéis em 7
-- unidades para 8 papéis em 2 unidades. Cada squad de infantaria (6) tem Líder, Médico, Suporte,
-- Metralhador, Antitanque e Atirador de elite (1 de cada) e Fuzileiros. O que saiu foi junto:
--   - granadeiro -> fuzileiro (a M79 é uma arma do fuzileiro dos EUA);
--   - fuzileiro automático -> metralhador (a M14 de seletor e bipé é uma arma do metralhador dos EUA);
--   - engenheiro e sapador de túnel -> suporte (constrói, arma e desarma armadilhas, explode túnel);
--   - operador de rádio -> líder (o líder leva o rádio do squad: Shared/Radio);
--   - observador -> atirador de elite (binóculo na vaga 7, como todos);
--   - morteiro -> comandante (pede o tiro) e suporte (constrói a posição);
--   - tripulante, piloto e atirador de porta: o lugar do veículo dá o papel (D-100), sem squad.
-- O papel salvo de antes vira o novo pelo Roles.migrate (perfil, jogar agora, tutorial).
local Roles = {}

Roles.TEAM_MAX = 40 -- D-114 (pedido do dono: "faça o jogo 40x40"); era 50 (D-91)
Roles.HEAVY_UNLOCK = 16 -- unidade pesada só com o time a partir de 16 (D-108: nenhuma unidade pesada hoje)

export type RoleDef = { id: string, name: string, unit: string, maxPerSquad: number? }
Roles.roles = {
	commander = { id = "commander", name = "Comandante", unit = "command", maxPerSquad = 1 },
	squad_leader = { id = "squad_leader", name = "Líder de squad", unit = "infantry", maxPerSquad = 1 },
	rifleman = { id = "rifleman", name = "Fuzileiro", unit = "infantry" },
	medic = { id = "medic", name = "Médico", unit = "infantry", maxPerSquad = 1 },
	-- D-108: caixa de munição no chão (Shared/CaixaMunicao), construções e armadilhas
	support = { id = "support", name = "Suporte", unit = "infantry", maxPerSquad = 1 },
	machine_gunner = { id = "machine_gunner", name = "Metralhador", unit = "infantry", maxPerSquad = 1 },
	anti_tank = { id = "anti_tank", name = "Antitanque", unit = "infantry", maxPerSquad = 1 },
	-- D-108: saiu do squad de reconhecimento (2 vagas por lado, posto 3): 1 por squad de infantaria
	sniper = { id = "sniper", name = "Atirador de elite", unit = "infantry", maxPerSquad = 1 },
	-- papéis de lugar de veículo (D-100): o painel do veículo dá ("VehicleCrew"); não se escolhem
	tank_crew = { id = "tank_crew", name = "Tripulante de blindado", unit = "vehicle" },
	pilot = { id = "pilot", name = "Piloto", unit = "vehicle" },
} :: { [string]: RoleDef }

-- unidades por facção: quantidade máxima e tamanho. D-108: só comando e infantaria; 9 squads de 6 (54
-- vagas + o comandante) para caber os 50 de cada lado com folga.
export type UnitDef = { count: number, size: number, heavy: boolean, names: { string } }
Roles.units = {
	US = {
		command = { count = 1, size = 1, heavy = false, names = { "Comando" } },
		infantry = {
			count = 9,
			size = 6,
			heavy = false,
			names = { "Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India" },
		},
	},
	VC = {
		command = { count = 1, size = 1, heavy = false, names = { "Chỉ huy" } },
		infantry = {
			count = 9,
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
				"Tiểu đội 9",
			},
		},
	},
} :: { [string]: { [string]: UnitDef } }

-- Armas-base por papel (Parte 4): a principal (vaga 1) e a pistola (vaga 2; Shared/Equipar). Todo
-- papel leva a pistola do lado (M1911A1 nos EUA, Tipo 54 no VC). O antitanque só tem a pistola: a
-- principal é o lançador, que o WeaponController põe depois dela.
Roles.loadout = {
	US = {
		commander = { "m14", "m1911" },
		squad_leader = { "m14", "m1911" }, -- + rádio (Shared/Radio, D-108)
		rifleman = { "m14", "m1911" },
		medic = { "m14", "m1911" }, -- corpsman
		support = { "m14", "m1911" },
		machine_gunner = { "m60", "m1911" },
		anti_tank = { "m1911" }, -- + bazuca 3.5" M20 (vaga "launcher")
		sniper = { "m70", "m1911" }, -- Winchester M70 com Unertl 8x (USMC, 1965; Shared/Weapons)
	},
	VC = {
		commander = { "sks", "type54" },
		squad_leader = { "type56", "type54" },
		rifleman = { "sks", "type54" },
		medic = { "sks", "type54" },
		support = { "sks", "type54" },
		machine_gunner = { "rpd", "type54" },
		anti_tank = { "type54" }, -- + RPG-2 (vaga "launcher")
		sniper = { "mosin", "type54" }, -- Mosin-Nagant 91/30 com luneta PU 3,5x (Shared/Weapons)
	},
} :: { [string]: { [string]: { string } } }

-- D-108: arma principal à escolha no cartão do papel (um toque troca; vale no próximo nascimento). A
-- 1ª é a padrão (a do Roles.loadout). EUA: o fuzileiro leva a M14, a espingarda Winchester 12 ou a
-- M79 (o antigo granadeiro); o suporte, a M14 ou a espingarda; o metralhador, a M60 ou a M14 de
-- seletor e bipé (o antigo fuzileiro automático: Weapons.roleModes). VC: SKS ou Tipo 56.
Roles.PRIMARY = {
	US = {
		rifleman = { "m14", "win12", "m79" },
		support = { "m14", "win12" },
		machine_gunner = { "m60", "m14" },
	},
	VC = {
		rifleman = { "sks", "type56" },
		support = { "sks", "type56" },
	},
} :: { [string]: { [string]: { string } } }

-- Armas principais que o papel pode escolher (sempre ao menos a padrão)
function Roles.primaries(faction: string, roleId: string): { string }
	local byF = Roles.PRIMARY[faction]
	local list = byF and byF[roleId]
	if list then
		return list
	end
	local lo = Roles.loadout[faction] and Roles.loadout[faction][roleId]
	return if lo and #lo > 1 then { lo[1] } else {}
end

-- A principal pedida vale para o papel? (nil ou fora da lista: a padrão)
function Roles.primaryFor(faction: string, roleId: string, primary: string?): string?
	local list = Roles.primaries(faction, roleId)
	if primary and table.find(list, primary) then
		return primary
	end
	return list[1]
end

-- Equipamento do papel com a principal escolhida (a pistola fica)
function Roles.loadoutFor(faction: string, roleId: string, primary: string?): { string }?
	local lo = Roles.loadout[faction] and Roles.loadout[faction][roleId]
	if not lo then
		return nil
	end
	local out = table.clone(lo)
	local p = Roles.primaryFor(faction, roleId, primary)
	if p and #out > 1 then
		out[1] = p
	end
	return out
end

-- ===== papel de antes (D-108) =====
-- Papel salvo antes da D-108 -> (papel novo, principal sugerida). O papel que ainda existe fica.
Roles.MIGRATE = {
	automatic_rifleman = { "machine_gunner", "m14" },
	grenadier = { "rifleman", "m79" },
	engineer = { "support" },
	sapper = { "support" },
	radio_operator = { "squad_leader" },
	observer = { "sniper" },
	mortar = { "support" },
	door_gunner = { "machine_gunner" },
	tank_crew = { "rifleman" },
	pilot = { "rifleman" },
} :: { [string]: { string } }
Roles.UNIT_MIGRATE = {
	recon = "infantry",
	armor = "infantry",
	helicopter = "infantry",
	mortar = "infantry",
	sapper = "infantry",
} :: { [string]: string }

function Roles.migrate(roleId: string?): (string?, string?)
	if type(roleId) ~= "string" then
		return nil, nil
	end
	local m = Roles.MIGRATE[roleId]
	if m then
		return m[1], m[2]
	end
	local r = Roles.roles[roleId]
	if r and r.unit ~= "vehicle" then
		return roleId, nil
	end
	return nil, nil
end

function Roles.migrateUnit(unit: string?): string?
	if type(unit) ~= "string" then
		return nil
	end
	return Roles.UNIT_MIGRATE[unit] or unit
end

-- Posto mínimo por papel (progressão, 2026-11-11; Shared/Progression). D-108: só o comandante (o
-- atirador de elite ficou livre, 1 por squad: pedido do dono). PLACEHOLDER até o playtest.
Roles.MIN_RANK = {
	commander = 3,
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
	return r ~= nil and r.unit == unit and Roles.loadout[faction] ~= nil and Roles.loadout[faction][roleId] ~= nil
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
