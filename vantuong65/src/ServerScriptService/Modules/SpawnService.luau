--!strict
-- Spawn escolhido no mapa, só no próprio lado, com espera longa por ondas (Parte 10.1).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local SpawnRules = require(ReplicatedStorage.Shared.SpawnRules)
local AssetLoader = require(script.Parent.AssetLoader)
local Characters = require(script.Parent.Characters)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local PlayerData = require(script.Parent.PlayerData)
local TeamService = require(script.Parent.TeamService)
local TunnelService = require(script.Parent.TunnelService)

local SpawnService = {}
local M = MapConfig.STUD_M

type Info = { deaths: { number }, lastDeath: number?, roleChanged: boolean, firstSpawn: boolean }
local info: { [Player]: Info } = {}

export type Point = { id: string, name: string, x: number, z: number, kind: SpawnRules.Kind, sector: number? }

-- Provedores extras de pontos (postos construídos, reforço por túnel): LogisticsService etc.
local providers: { (faction: string) -> { Point } } = {}
function SpawnService.addProvider(fn: (faction: string) -> { Point })
	table.insert(providers, fn)
end

function SpawnService.points(faction: string): { Point }
	local out: { Point } = {}
	for _, fn in providers do
		for _, pt in fn(faction) do
			table.insert(out, pt)
		end
	end
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
	if faction == "VC" then
		for _, en in TunnelService.entrances() do
			if en.sector and MatchService.ownerOf(en.sector) == "VC" and not TunnelService.destroyed[en.id] then
				table.insert(out, {
					id = "tunnel:" .. en.id,
					name = "Túnel " .. en.id,
					x = en.x,
					z = en.z,
					kind = "garrison",
					sector = en.sector,
				})
			end
		end
	end
	return out
end

function SpawnService.enemiesMeters(faction: string): { number }
	local list = {}
	for _, e in Combatants.list() do
		local r = Combatants.root(e)
		if e.faction ~= faction and r and Combatants.active(e) then
			table.insert(list, r.Position.X * M)
			table.insert(list, r.Position.Z * M)
		end
	end
	return list
end
local enemiesMeters = SpawnService.enemiesMeters

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

function SpawnService.groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return if hit then hit.Position.Y else 10
end
local groundY = SpawnService.groundY

-- pontos livres agora (para bots): sem bloqueio
function SpawnService.freePoints(faction: string): { Point }
	local out = {}
	local now = os.clock()
	for _, pt in SpawnService.points(faction) do
		local contested = pt.sector ~= nil and MatchService.isContested(pt.sector)
		local openedAt = if pt.sector then MatchService.capturedAt[pt.sector] else nil
		local blocked = pt.kind ~= "hq"
			and SpawnRules.blocked(pt.x * M, pt.z * M, enemiesMeters(faction), contested, openedAt, now)
		if not blocked then
			table.insert(out, pt)
		end
	end
	return out
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
		if ReplicatedStorage:GetAttribute("TerrainReady") == false then
			return -- terreno ainda sendo gerado
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
				local prof = PlayerData.get(player)
				local equipped = if prof then prof.equipped[faction] else nil
				player:LoadCharacterWithHumanoidDescriptionAsync(Characters.describe(faction, equipped, player.UserId))
				local char = player.Character
				if char then
					local y = groundY(pt.x, pt.z)
					char:PivotTo(CFrame.new(pt.x, y + 5, pt.z))
					Combatants.register(char, faction, player)
					Characters.dress(char, faction, equipped)
					local lo = player:GetAttribute("Loadout")
					if type(lo) == "string" then
						AssetLoader.attachWeapon(char, string.split(lo, ",")[1])
					end
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
