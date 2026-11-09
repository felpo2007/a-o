--!strict
-- Spawn escolhido no mapa, só no próprio lado, com espera longa por ondas (Parte 10.1).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local SpawnRules = require(ReplicatedStorage.Shared.SpawnRules)
local MatchService = require(script.Parent.MatchService)
local TeamService = require(script.Parent.TeamService)

local SpawnService = {}
local M = MapConfig.STUD_M

type Info = { deaths: { number }, lastDeath: number?, roleChanged: boolean, firstSpawn: boolean }
local info: { [Player]: Info } = {}

export type Point = { id: string, name: string, x: number, z: number, kind: SpawnRules.Kind, sector: number? }

function SpawnService.points(faction: string): { Point }
	local out: { Point } = {}
	local hq = MapConfig.HQ[faction]
	table.insert(out, { id = "hq", name = "QG", x = hq.x, z = hq.z, kind = "hq" })
	for s, sp in MatchService.points do
		if MatchService.ownerOf(s) == faction then
			local x, z = SpawnRules.rallyPosition(sp.x, sp.z, faction, M)
			local initial = MatchService.initialOwner[s] == faction
			table.insert(out, {
				id = "rally:" .. s,
				name = "Reunião — " .. sp.name,
				x = x,
				z = z,
				kind = if initial then "rally" else "rally_captured",
				sector = s,
			})
		end
	end
	return out
end

local function enemiesMeters(faction: string): { number }
	local list = {}
	for _, p in Players:GetPlayers() do
		local f = p:GetAttribute("Faction")
		local char = p.Character
		local r = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if f and f ~= faction and r then
			table.insert(list, r.Position.X * M)
			table.insert(list, r.Position.Z * M)
		end
	end
	return list
end

local function status(player: Player, pt: Point, now: number): (number, boolean, string?)
	local inf = info[player]
	local faction = player:GetAttribute("Faction") :: string
	local ready = now
	if inf and inf.lastDeath and not inf.firstSpawn then
		local extra = SpawnRules.extraWait(pt.kind, inf.deaths, inf.roleChanged)
		ready = SpawnRules.readyAt(inf.lastDeath, extra, MatchService.waveEpoch)
	end
	local contested = pt.sector ~= nil and MatchService.isContested(pt.sector)
	local openedAt = if pt.sector then MatchService.capturedAt[pt.sector] else nil
	local blocked, why = false, nil
	if pt.kind ~= "hq" then
		blocked, why = SpawnRules.blocked(pt.x * M, pt.z * M, enemiesMeters(faction), contested, openedAt, now)
	end
	return math.max(0, ready - now), blocked, why
end

local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return if hit then hit.Position.Y else 10
end

local function alive(player: Player): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

function SpawnService.start()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(function(p)
		info[p] = { deaths = {}, roleChanged = false, firstSpawn = true }
	end)
	for _, p in Players:GetPlayers() do
		info[p] = { deaths = {}, roleChanged = false, firstSpawn = true }
	end
	Players.PlayerRemoving:Connect(function(p)
		info[p] = nil
	end)
	TeamService.RoleChanged:Connect(function(player: Player)
		local inf = info[player]
		if inf and inf.lastDeath then
			inf.roleChanged = true
		end
	end)

	Net.event("Spawn_Request").OnServerEvent:Connect(function(player, pointId)
		local faction = player:GetAttribute("Faction") :: string?
		if type(pointId) ~= "string" or not faction or not player:GetAttribute("Role") or alive(player) then
			return
		end
		local now = os.clock()
		for _, pt in SpawnService.points(faction) do
			if pt.id == pointId then
				local wait, blocked = status(player, pt, now)
				if wait > 0 or blocked then
					return
				end
				local inf = info[player]
				inf.firstSpawn, inf.roleChanged = false, false
				player:LoadCharacterAsync()
				local char = player.Character
				if char then
					local y = groundY(pt.x, pt.z)
					char:PivotTo(CFrame.new(pt.x, y + 4, pt.z))
					local hum = char:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.Died:Connect(function()
							local t = os.clock()
							inf.lastDeath = t
							table.insert(inf.deaths, t)
							if #inf.deaths > 10 then
								table.remove(inf.deaths, 1)
							end
						end)
					end
				end
				return
			end
		end
	end)

	-- estado dos pontos para quem está esperando (uma vez por segundo)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local faction = player:GetAttribute("Faction") :: string?
				if faction and not alive(player) then
					local list = {}
					for _, pt in SpawnService.points(faction) do
						local wait, blocked, why = status(player, pt, now)
						local entry = {
							id = pt.id,
							name = pt.name,
							x = pt.x,
							z = pt.z,
							wait = wait,
							blocked = blocked,
							why = why,
						}
						table.insert(list, entry)
					end
					Net.event("Spawn_State"):FireClient(player, list)
				end
			end
		end
	end)
end

return SpawnService
