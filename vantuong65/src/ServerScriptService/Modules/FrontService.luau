--!strict
-- Ritmo da frente no servidor (pedido do dono, 2026-11-11: primeiro contato em ~5 min e bots
-- espalhados). Regras puras em Shared/Front:
--   - reunião avançada: ponto de inserção no setor próprio a ~125 m do ponto forte atacado. Os bots
--     nascem no ponto livre mais perto do objetivo (BotService), então chegam juntos e cedo;
--   - ponto de reunião do squad: o líder planta onde está (carta aberta: Y; teclado: R); só o squad
--     nasce nele, com as regras de bloqueio de sempre (inimigo a menos de 75 m);
--   - posições do próprio squad e pontos de inserção do próprio lado para a carta de quem está em
--     campo (nada do outro lado: Parte 9.5).
-- Remotes próprios, criados aqui na pasta do Net (o Net.luau não está na lista desta tarefa):
--   SquadRally_Place (c->s), SquadRally_State (s->c { ok, msg, x?, z? }),
--   Squad_Positions (s->c { { id, name, x, z, yaw, downed, leader, role } }),
--   Spawn_Points (s->c { { id, name, x, z, kind } }) para quem está vivo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FireSupport = require(ReplicatedStorage.Shared.FireSupport)
local Front = require(ReplicatedStorage.Shared.Front)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local SpawnService = require(script.Parent.SpawnService)
local TeamService = require(script.Parent.TeamService)

local FrontService = {}
local M = MapConfig.STUD_M

type Rally = { squad: string, faction: string, name: string, x: number, z: number, at: number, model: Model }
local rallies: { [string]: Rally } = {} -- por squad
local lastPlaced: { [string]: number } = {}
local folder: Folder? = nil

local function remote(name: string, unreliable: boolean?): RemoteEvent
	local f = ReplicatedStorage:WaitForChild("VT65Remotes")
	local r = f:FindFirstChild(name)
	if not r then
		r = Instance.new(if unreliable then "UnreliableRemoteEvent" else "RemoteEvent")
		r.Name = name
		r.Parent = f
	end
	return r :: any
end

local function sectorAt(x: number, z: number): number?
	return Geometry.sectorAt(MapConfig.Sectors, x, z)
end

-- ===== reunião avançada =====
-- A busca (leque de 11 rumos, passos de 10 m, ponto-no-polígono dos 5 setores) roda a cada pedido de
-- pontos: 1 vez por segundo por jogador esperando, a cada 4 s por jogador em campo e a cada nascer de
-- bot. O lugar só muda com os pontos fortes sorteados, então fica guardado por par e por partida.
local rallyCache: { [string]: { x: number?, z: number? } } = {}
local rallyCacheMatch = -1

local function forwardRallyCached(own: number, ownSp: any, target: number, targetSp: any): (number?, number?)
	if rallyCacheMatch ~= MatchService.startedAt then
		rallyCacheMatch = MatchService.startedAt
		table.clear(rallyCache)
	end
	-- chave sem string.format: o extrator de textos de tela (tools/i18n) pegaria o modelo
	local key = table.concat({ own, target, ownSp.x, ownSp.z, targetSp.x, targetSp.z }, ":")
	local hit = rallyCache[key]
	if not hit then
		local x, z = Front.forwardRally(own, ownSp, targetSp, M, sectorAt, MapConfig.Bounds)
		hit = { x = x, z = z }
		rallyCache[key] = hit
	end
	return hit.x, hit.z
end

function FrontService.forwardPoints(faction: string): { SpawnService.Point }
	local out: { SpawnService.Point } = {}
	local st = MatchService.state
	if not st or MatchService.ended then
		return out
	end
	for _, pair in Front.forwardPairs(st.owner, st.active, faction) do
		local own, target = MatchService.points[pair.own], MatchService.points[pair.target]
		if own and target then
			local x, z = forwardRallyCached(pair.own, own, pair.target, target)
			if x and z then
				local initial = MatchService.initialOwner[pair.own] == faction
				table.insert(out, {
					id = string.format("forward:%d:%d", pair.own, pair.target),
					name = string.format("Reunião avançada — %s", Front.letra(pair.own)),
					x = x,
					z = z,
					kind = if initial then "rally" else "rally_captured",
					sector = pair.own,
				})
			end
		end
	end
	return out
end

-- ===== reunião do squad =====
local function squadName(faction: string, sid: string): string
	local sq = TeamService.squads[faction]
	local list: { any } = if sq then sq.squads else {}
	for _, s in list do
		if s.id == sid then
			return s.name
		end
	end
	return string.match(sid, ":(.+)$") or sid
end

local function removeRally(sid: string)
	local r = rallies[sid]
	if r then
		r.model:Destroy()
		rallies[sid] = nil
	end
end

-- mochila com rádio e bandeirola (marca no mundo: o inimigo que achar desfaz)
local function prop(x: number, z: number, faction: string): Model
	local m = Instance.new("Model")
	m.Name = "ReuniaoSquad"
	local y = SpawnService.groundY(x, z)
	local function part(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Size, p.CFrame, p.Color, p.Material = size, cf, color, mat
		p.Anchored, p.CanCollide, p.CanTouch, p.CastShadow = true, false, false, true
		p.CanQuery = false -- a bala e o abrigo dos bots não "veem" a mochila
		p.Parent = m
		return p
	end
	local olive = if faction == "US" then Color3.fromRGB(84, 88, 58) else Color3.fromRGB(110, 96, 62)
	part(Vector3.new(0.45, 0.5, 0.3) / M, CFrame.new(x, y + 0.25 / M, z), olive, Enum.Material.Fabric)
	part(
		Vector3.new(0.03, 1.4, 0.03) / M,
		CFrame.new(x + 0.25 / M, y + 0.7 / M, z),
		Color3.fromRGB(96, 80, 56),
		Enum.Material.Wood
	)
	part(
		Vector3.new(0.3, 0.18, 0.01) / M,
		CFrame.new(x + 0.4 / M, y + 1.3 / M, z),
		if faction == "US" then Color3.fromRGB(200, 170, 60) else Color3.fromRGB(170, 40, 34),
		Enum.Material.Fabric
	)
	m:SetAttribute("Faction", faction)
	m.Parent = folder
	return m
end

local function nearestEnemyM(faction: string, pos: Vector3): number
	local best = math.huge
	for _, e in Combatants.list() do
		local r = Combatants.root(e)
		if e.faction ~= faction and r and Combatants.active(e) then
			best = math.min(best, (r.Position - pos).Magnitude * M)
		end
	end
	return best
end

local function nearestObjectiveM(faction: string, pos: Vector3): number
	local st = MatchService.state
	local best = math.huge
	for s, sp in MatchService.points do
		if st and st.active[s] and st.owner[s] ~= faction then
			best = math.min(best, Vector3.new(sp.x - pos.X, 0, sp.z - pos.Z).Magnitude * M)
		end
	end
	return best
end

local function inWater(pos: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = false
	local hit = workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return hit ~= nil and hit.Material == Enum.Material.Water
end

local function members(sid: string): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("SquadId") == sid then
			table.insert(out, p)
		end
	end
	return out
end

local function place(player: Player)
	local faction = player:GetAttribute("Faction") :: string?
	local sid = player:GetAttribute("SquadId") :: string?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local state = remote("SquadRally_State")
	if not (faction and sid and root and hum) then
		state:FireClient(player, { ok = false, msg = "entre num squad e em campo antes" })
		return
	end
	local pos = root.Position
	local b = MapConfig.Bounds
	local enemy = if faction == "US" then "VC" else "US"
	local hq = MapConfig.HQ[enemy]
	local why = Front.squadRallyCheck({
		leader = player:GetAttribute("Role") == "squad_leader",
		alive = hum.Health > 0 and not (char :: Model):GetAttribute("Downed"),
		inBounds = Geometry.inBounds(b, pos.X, pos.Z),
		inWater = inWater(pos),
		nearestEnemyM = nearestEnemyM(faction, pos),
		nearestObjectiveM = nearestObjectiveM(faction, pos),
		enemyHqM = Vector3.new(pos.X - hq.x, 0, pos.Z - hq.z).Magnitude * M,
		now = os.clock(),
		lastPlacedAt = lastPlaced[sid],
	})
	if why then
		state:FireClient(player, { ok = false, msg = why })
		return
	end
	removeRally(sid)
	lastPlaced[sid] = os.clock()
	rallies[sid] = {
		squad = sid,
		faction = faction,
		name = squadName(faction, sid),
		x = pos.X,
		z = pos.Z,
		at = os.clock(),
		model = prop(pos.X, pos.Z, faction),
	}
	local grid = FireSupport.localToGrid(pos.X, pos.Z, MapConfig.GridOrigin1965, M, 6)
	for _, p in members(sid) do
		state:FireClient(p, {
			ok = true,
			msg = string.format("Ponto de reunião do squad em %s", grid),
			x = pos.X,
			z = pos.Z,
			by = player.DisplayName,
		})
	end
end

-- ===== laços =====
local function aliveRole(p: Player): boolean
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

function FrontService.start()
	local f = Instance.new("Folder")
	f.Name = "SquadRallies"
	f.Parent = workspace
	folder = f
	remote("SquadRally_Place").OnServerEvent:Connect(place)
	remote("SquadRally_State")
	remote("Squad_Positions")
	remote("Spawn_Points")

	SpawnService.addProvider(function(faction: string)
		local out = FrontService.forwardPoints(faction)
		for sid, r in rallies do
			if r.faction == faction then
				table.insert(out, {
					id = "squad:" .. sid,
					name = string.format("Reunião do squad %s", r.name),
					x = r.x,
					z = r.z,
					kind = "rally",
					squad = sid, -- só o squad vê e nasce (SpawnService)
				})
			end
		end
		return out
	end)

	-- nova partida: os pontos do squad somem (o mapa e os setores mudam)
	local lastStart = MatchService.startedAt
	task.spawn(function()
		while true do
			task.wait(1)
			if MatchService.startedAt ~= lastStart then
				lastStart = MatchService.startedAt
				for sid in rallies do
					removeRally(sid)
				end
				table.clear(lastPlaced)
			end
			-- squad desfeito, líder que saiu do squad ou inimigo em cima: o ponto some
			for sid, r in rallies do
				local alive = #members(sid) > 0
				local enemyClose = nearestEnemyM(r.faction, Vector3.new(r.x, 0, r.z)) < 15
				if not alive or enemyClose then
					removeRally(sid)
					for _, p in members(sid) do
						remote("SquadRally_State"):FireClient(p, {
							ok = false,
							lost = true,
							msg = if enemyClose
								then "O inimigo achou o ponto de reunião do squad"
								else "Ponto de reunião desfeito",
						})
					end
				end
			end
		end
	end)

	-- carta de quem está em campo: o próprio squad (a cada 2 s) e os pontos de inserção (a cada 4 s)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(2)
			tick += 1
			local bySquad: { [string]: { any } } = {}
			for _, p in Players:GetPlayers() do
				local sid = p:GetAttribute("SquadId")
				local c = p.Character
				local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
				if type(sid) == "string" and r and aliveRole(p) then
					local look = r.CFrame.LookVector
					bySquad[sid] = bySquad[sid] or {}
					table.insert(bySquad[sid], {
						id = p.UserId,
						name = p.DisplayName,
						x = math.floor(r.Position.X),
						z = math.floor(r.Position.Z),
						yaw = math.floor(math.deg(math.atan2(look.X, -look.Z))),
						downed = c and c:GetAttribute("Downed") == true or false,
						role = p:GetAttribute("Role"),
					})
				end
			end
			for _, p in Players:GetPlayers() do
				local sid = p:GetAttribute("SquadId")
				if type(sid) == "string" then
					remote("Squad_Positions"):FireClient(p, bySquad[sid] or {})
				end
			end
			if tick % 2 == 0 then
				for _, p in Players:GetPlayers() do
					local faction = p:GetAttribute("Faction")
					if type(faction) == "string" and aliveRole(p) then
						local sid = p:GetAttribute("SquadId")
						local list = {}
						for _, pt in SpawnService.points(faction) do
							local sq = (pt :: any).squad
							if sq == nil or sq == sid then
								table.insert(list, { id = pt.id, name = pt.name, x = pt.x, z = pt.z, kind = pt.kind })
							end
						end
						remote("Spawn_Points"):FireClient(p, list)
					end
				end
			end
		end
	end)
end

return FrontService
