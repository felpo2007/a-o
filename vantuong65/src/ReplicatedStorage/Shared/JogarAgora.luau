--!strict
-- Jogar agora (pedido do dono, 2026-11-13: "Botão 'jogar agora', que já põe o jogador num squad e no
-- último ponto de spawn usado"). Regras puras, testadas no Lune (tests/luau/jogaragora.luau); o
-- servidor (TeamService.quickJoin e SpawnService, pedido Spawn_Request "quick") aplica e o cliente
-- (Controllers/JogarAgora) mostra e entra.
--   1. lado: o atual; sem lado, o da última vez se cabe (a mesma regra do Team_Choose); senão o menor;
--   2. squad: o atual; senão o da última vez com vaga; senão um da mesma unidade com vaga (o mais
--      cheio: junto de gente); senão um novo dessa unidade; senão infantaria (com vaga, ou nova);
--   3. papel: o atual; senão o da última vez, se cabe no squad, no posto e na vaga; senão fuzileiro;
--      senão o primeiro livre da unidade;
--   4. ponto: o último usado, se ainda vale (pode estar contando a espera); senão junto do squad
--      (companheiro ou reunião do squad), depois reunião, túnel ou posto, e o QG por último. Em cada
--      grupo, o mais perto do objetivo, com a espera pesando como caminhada. Nunca "onde caiu" (pago).
-- A última escolha mora no perfil (campo `unit`, que existia sem uso: { id = unidade, f, sq, role,
-- pt }) e é saneada aqui ao ler.
local Roles = require(script and (script :: any).Parent.Roles or "./Roles") :: any

local JogarAgora = {}

-- espera (s) pesada como caminhada até o objetivo: 1 s de espera vale 18 studs (~5 m/s correndo).
-- PLACEHOLDER de design.
JogarAgora.WAIT_STUDS = 18
-- ordem dos papéis quando o da última vez não serve (o fuzileiro sempre antes). D-108: os 8 papéis
JogarAgora.ROLE_ORDER = {
	"rifleman",
	"squad_leader",
	"support",
	"medic",
	"machine_gunner",
	"anti_tank",
	"sniper",
	"commander",
}

export type Choice = {
	f: string?, -- lado
	unit: string?, -- unidade do squad
	sq: string?, -- nome do squad ("Alfa", "Tiểu đội 2")
	role: string?, -- papel
	pt: string?, -- id do último ponto de inserção
	w: string?, -- D-108: arma principal escolhida no cartão do papel (Roles.PRIMARY)
}

local function str(v: any, max: number): string?
	if type(v) ~= "string" or #v == 0 or #v > max then
		return nil
	end
	return v
end

-- Perfil (qualquer forma) -> escolha válida. Nunca confia no que veio salvo.
function JogarAgora.sanitize(raw: any): Choice
	local c: Choice = {}
	if type(raw) ~= "table" then
		return c
	end
	local f = raw.f
	if f == "US" or f == "VC" then
		c.f = f
		-- D-108: unidade e papel de antes das classes mais simples viram os de agora (Roles.migrate)
		local unit = Roles.migrateUnit(str(raw.id, 24))
		if unit and Roles.units[f][unit] then
			c.unit = unit
			local sq = str(raw.sq, 40)
			if sq and table.find(Roles.units[f][unit].names, sq) then
				c.sq = sq
			end
		end
		local role, wNew = Roles.migrate(str(raw.role, 32))
		if role and Roles.roles[role] and Roles.loadout[f][role] then
			c.role = role
			local w = str(raw.w, 24) or wNew
			if w and table.find(Roles.primaries(f, role), w) then
				c.w = w
			end
		end
	end
	local pt = str(raw.pt, 60)
	if pt and pt ~= "inplace" and pt ~= "quick" and string.match(pt, "^[%w_:%-]+$") then
		c.pt = pt
	end
	return c
end

-- Escolha -> o que vai para o perfil (o campo `unit` guarda a unidade em `id`)
function JogarAgora.pack(c: Choice): { [string]: string }
	local out: { [string]: string } = {}
	out.id = c.unit :: any
	out.f = c.f :: any
	out.sq = c.sq :: any
	out.role = c.role :: any
	out.pt = c.pt :: any
	out.w = c.w :: any
	return out
end

-- Texto curto "f|unidade|squad|papel" para o atributo do jogador (a tela mostra o que vai acontecer)
function JogarAgora.encode(c: Choice): string
	return table.concat({ c.f or "", c.unit or "", c.sq or "", c.role or "", c.w or "" }, "|")
end

function JogarAgora.decode(s: any): Choice
	if type(s) ~= "string" then
		return {}
	end
	local p = string.split(s, "|")
	return JogarAgora.sanitize({ f = p[1], id = p[2], sq = p[3], role = p[4], w = p[5] })
end

-- ===== 1. lado =====
-- Pode entrar no lado f? (a regra do TeamService: cheio, ou desequilibraria)
function JogarAgora.canJoin(f: string, us: number, vc: number, teamMax: number): boolean
	local mine = if f == "US" then us else vc
	local theirs = if f == "US" then vc else us
	return mine < teamMax and mine <= theirs
end

-- Lado para quem ainda não tem: o da última vez se cabe; senão o que cabe (o menor primeiro).
function JogarAgora.pickFaction(last: string?, us: number, vc: number, teamMax: number): string?
	if (last == "US" or last == "VC") and JogarAgora.canJoin(last, us, vc, teamMax) then
		return last
	end
	local first = if us <= vc then "US" else "VC"
	local second = if first == "US" then "VC" else "US"
	for _, f in { first, second } do
		if JogarAgora.canJoin(f, us, vc, teamMax) then
			return f
		end
	end
	return nil
end

-- ===== 2. squad =====
export type SquadLite = { id: string, unit: string, name: string, members: { number }, leader: number? }

local function hasRoom(units: any, s: SquadLite): boolean
	local def = units[s.unit]
	return def ~= nil and #s.members < def.size
end

local function canCreate(faction: string, units: any, squads: { SquadLite }, unit: string, teamSize: number): boolean
	local def = units[unit]
	if not def or not Roles.unitAllowed(faction, unit, teamSize) then
		return false
	end
	local used = 0
	for _, s in squads do
		if s.unit == unit then
			used += 1
		end
	end
	return used < #def.names
end

-- os squads da unidade com vaga, do mais cheio para o mais vazio (empate: a ordem dos nomes)
local function withRoom(units: any, squads: { SquadLite }, unit: string): { SquadLite }
	local out: { SquadLite } = {}
	for _, s in squads do
		if s.unit == unit and hasRoom(units, s) then
			table.insert(out, s)
		end
	end
	local names = if units[unit] then units[unit].names else {}
	table.sort(out, function(a: SquadLite, b: SquadLite): boolean
		if #a.members ~= #b.members then
			return #a.members > #b.members
		end
		return (table.find(names, a.name) or 99) < (table.find(names, b.name) or 99)
	end)
	return out
end

-- Devolve ("join", id do squad) | ("create", unidade) | (nil, nil) quando não há lugar.
function JogarAgora.pickSquad(
	faction: string,
	squads: { SquadLite },
	last: Choice,
	teamSize: number
): (string?, string?)
	local units = Roles.units[faction]
	if not units then
		return nil, nil
	end
	-- o da última vez, se ainda existe e tem vaga (mesmo lado)
	if last.f == faction and last.sq then
		for _, s in squads do
			if s.name == last.sq and hasRoom(units, s) then
				return "join", s.id
			end
		end
	end
	local unit = if last.f == faction
			and last.unit
			and Roles.unitAllowed(faction, last.unit, teamSize)
		then last.unit
		else "infantry"
	for _, u in { unit, "infantry" } do
		local open = withRoom(units, squads, u)
		if #open > 0 then
			return "join", open[1].id
		end
		if canCreate(faction, units, squads, u, teamSize) then
			return "create", u
		end
	end
	return nil, nil
end

-- ===== 3. papel =====
export type SquadRoles = { unit: string, leader: number?, roles: { [any]: string } }

-- O papel cabe? (unidade, posto, só o líder, vaga no squad sem contar ele mesmo)
function JogarAgora.roleFits(faction: string, sq: SquadRoles, userId: number, roleId: string, rank: number): boolean
	if not Roles.roleAllowedInUnit(faction, roleId, sq.unit) then
		return false
	end
	if rank < Roles.minRank(roleId) then
		return false
	end
	if roleId == "squad_leader" and sq.leader ~= userId then
		return false
	end
	local max = Roles.roles[roleId].maxPerSquad
	if max then
		local n = 0
		for uid, r in sq.roles do
			if r == roleId and tostring(uid) ~= tostring(userId) then
				n += 1
			end
		end
		if n >= max then
			return false
		end
	end
	return true
end

function JogarAgora.pickRole(faction: string, sq: SquadRoles, userId: number, last: Choice, rank: number): string?
	local tries: { string } = {}
	if last.role and last.f == faction then
		table.insert(tries, last.role)
	end
	for _, r in JogarAgora.ROLE_ORDER do
		table.insert(tries, r)
	end
	for _, r in tries do
		if JogarAgora.roleFits(faction, sq, userId, r, rank) then
			return r
		end
	end
	return nil
end

-- ===== 4. ponto =====
-- grupo do ponto: 1 junto do squad (companheiro, reunião do squad), 2 o resto, 3 o QG
local function group(e: any): number
	if e.id == "hq" or e.kind == "hq" then
		return 3
	end
	if e.kind == "squad" or e.squad == true or string.sub(tostring(e.id), 1, 6) == "squad:" then
		return 1
	end
	return 2
end

export type PickOpts = {
	vehicle: boolean?, -- só pontos onde o veículo comprado sai (allowed)
	allowed: ((id: string) -> boolean)?,
	objX: number?, -- objetivo do lado (studs), para escolher o ponto mais perto
	objZ: number?,
	age: number?, -- segundos desde a lista (desconta da espera)
}

-- Espera que falta (s) num ponto da lista do servidor (Spawn_State)
function JogarAgora.waitLeft(e: any, age: number?): number
	local w = if type(e.wait) == "number" then e.wait else 0
	return math.max(0, w - (age or 0))
end

-- O ponto ainda vale para entrar? (não bloqueado, não é o pago, e com veículo só onde ele sai)
function JogarAgora.usable(e: any, opts: PickOpts?): boolean
	if type(e) ~= "table" or type(e.id) ~= "string" or e.id == "inplace" or e.blocked == true then
		return false
	end
	local o: PickOpts = opts or {}
	local allowed = o.allowed
	if o.vehicle and allowed and not allowed(e.id) then
		return false
	end
	return true
end

-- Ponto do "jogar agora": o último (se vale) ou o melhor da lista. nil = nenhum ponto livre.
function JogarAgora.pickPoint(entries: { any }, lastId: string?, opts: PickOpts?): any?
	local o: PickOpts = opts or {}
	local list: { any } = {}
	for _, e in entries do
		if JogarAgora.usable(e, o) then
			table.insert(list, e)
		end
	end
	if lastId then
		for _, e in list do
			if e.id == lastId then
				return e
			end
		end
	end
	local best: any = nil
	local bestG, bestS = math.huge, math.huge
	for _, e in list do
		local g = group(e)
		local d = 0
		local ox, oz = o.objX, o.objZ
		if ox and oz and type(e.x) == "number" and type(e.z) == "number" then
			d = math.sqrt((e.x - ox) ^ 2 + (e.z - oz) ^ 2)
		end
		local s = d + JogarAgora.waitLeft(e, o.age) * JogarAgora.WAIT_STUDS
		if g < bestG or (g == bestG and (s < bestS or (s == bestS and best and e.id < best.id))) then
			best, bestG, bestS = e, g, s
		end
	end
	return best
end

-- Resposta do servidor no atributo "JogarAgora": "<id>|<n>" ou "!<motivo>|<n>"
function JogarAgora.reply(id: string?, why: string?, n: number): string
	if id then
		return string.format("%s|%d", id, n)
	end
	return string.format("!%s|%d", why or "", n)
end

-- Lê a resposta: (id do ponto, motivo, número do pedido)
function JogarAgora.parseReply(s: any): (string?, string?, number?)
	if type(s) ~= "string" then
		return nil, nil, nil
	end
	local body, n = string.match(s, "^(.*)|(%d+)$")
	if not body then
		return nil, nil, nil
	end
	local num = tonumber(n)
	if string.sub(body, 1, 1) == "!" then
		return nil, string.sub(body, 2), num
	end
	return body, nil, num
end

return JogarAgora
