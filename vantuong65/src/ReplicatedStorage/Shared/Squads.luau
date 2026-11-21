--!strict
-- Gestão de squads (pura). O servidor guarda um State por facção.
local Roles = require(script and (script :: any).Parent.Roles or "./Roles") :: any

local Squads = {}

export type Squad = {
	id: string,
	unit: string,
	name: string,
	members: { number },
	leader: number?,
	roles: { [number]: string },
}
export type State = { faction: string, squads: { Squad } }

function Squads.new(faction: string): State
	return { faction = faction, squads = {} }
end

function Squads.find(st: State, id: string): Squad?
	for _, s in st.squads do
		if s.id == id then
			return s
		end
	end
	return nil
end

function Squads.squadOf(st: State, userId: number): Squad?
	for _, s in st.squads do
		if table.find(s.members, userId) then
			return s
		end
	end
	return nil
end

function Squads.leave(st: State, userId: number)
	local s = Squads.squadOf(st, userId)
	if not s then
		return
	end
	table.remove(s.members, table.find(s.members, userId) :: number)
	s.roles[userId] = nil
	if s.leader == userId then
		s.leader = s.members[1]
	end
	if #s.members == 0 then
		table.remove(st.squads, table.find(st.squads, s) :: number)
	end
end

function Squads.create(st: State, unit: string, userId: number, teamSize: number): (Squad?, string?)
	local def = Roles.units[st.faction][unit]
	if not def then
		return nil, "unidade inexistente"
	end
	if not Roles.unitAllowed(st.faction, unit, teamSize) then
		return nil, "unidade abre com 16 jogadores no time"
	end
	local used = {}
	for _, s in st.squads do
		if s.unit == unit then
			used[s.name] = true
		end
	end
	local name: string? = nil
	for _, n in def.names do
		if not used[n] then
			name = n
			break
		end
	end
	if not name then
		return nil, "limite de unidades deste tipo"
	end
	Squads.leave(st, userId)
	local sq: Squad =
		{ id = st.faction .. ":" .. name, unit = unit, name = name, members = { userId }, leader = userId, roles = {} }
	table.insert(st.squads, sq)
	return sq, nil
end

function Squads.join(st: State, id: string, userId: number): (boolean, string?)
	local s = Squads.find(st, id)
	if not s then
		return false, "squad inexistente"
	end
	if table.find(s.members, userId) then
		return true, nil
	end
	if #s.members >= Roles.units[st.faction][s.unit].size then
		return false, "squad cheio"
	end
	Squads.leave(st, userId)
	table.insert(s.members, userId)
	if not s.leader then
		s.leader = userId
	end
	return true, nil
end

function Squads.chooseRole(st: State, userId: number, roleId: string): (boolean, string?)
	local s = Squads.squadOf(st, userId)
	if not s then
		return false, "entre num squad antes"
	end
	if not Roles.roleAllowedInUnit(st.faction, roleId, s.unit) then
		return false, "papel não pertence a esta unidade"
	end
	if roleId == "squad_leader" and s.leader ~= userId then
		return false, "só o líder do squad"
	end
	local max = Roles.roles[roleId].maxPerSquad
	if max then
		local n = 0
		for uid, r in s.roles do
			if r == roleId and uid ~= userId then
				n += 1
			end
		end
		if n >= max then
			return false, "vaga ocupada"
		end
	end
	s.roles[userId] = roleId
	return true, nil
end

return Squads
