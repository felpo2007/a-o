--!strict
-- Escolha de facção, squad e papel (Parte 4), com limite de 30 por time e equilíbrio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Squads = require(ReplicatedStorage.Shared.Squads)

local TeamService = {}
TeamService.squads = { US = Squads.new("US"), VC = Squads.new("VC") } :: { [string]: Squads.State }
local roleChanged = Instance.new("BindableEvent")
TeamService.RoleChanged = roleChanged.Event -- (player, roleId)

local teamObjects: { [string]: Team } = {}

local function teamSize(faction: string): number
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Faction") == faction then
			n += 1
		end
	end
	return n
end

local function pushSquads(faction: string)
	local st = TeamService.squads[faction]
	local list = {}
	for _, s in st.squads do
		table.insert(
			list,
			{ id = s.id, unit = s.unit, name = s.name, members = s.members, leader = s.leader, roles = s.roles }
		)
	end
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Faction") == faction then
			Net.event("Squad_State"):FireClient(p, { faction = faction, squads = list, size = teamSize(faction) })
		end
	end
end

local function setRole(player: Player, roleId: string?)
	local faction = player:GetAttribute("Faction") :: string?
	player:SetAttribute("Role", roleId)
	local loadout = if roleId and faction then Roles.loadout[faction][roleId] else nil
	player:SetAttribute("Loadout", if loadout then table.concat(loadout, ",") else nil)
	roleChanged:Fire(player, roleId)
end

local function leaveAll(player: Player)
	for faction, st in TeamService.squads do
		if Squads.squadOf(st, player.UserId) then
			Squads.leave(st, player.UserId)
			pushSquads(faction)
		end
	end
	player:SetAttribute("SquadId", nil)
	setRole(player, nil)
end

function TeamService.start()
	for _, faction in { "US", "VC" } do
		local t = Instance.new("Team")
		t.Name = faction
		t.TeamColor = if faction == "US" then BrickColor.new("Olive") else BrickColor.new("Brown")
		t.AutoAssignable = false
		t.Parent = Teams
		teamObjects[faction] = t
	end

	Net.event("Team_Choose").OnServerEvent:Connect(function(player, faction)
		if faction ~= "US" and faction ~= "VC" or player:GetAttribute("Faction") == faction then
			return
		end
		local other = if faction == "US" then "VC" else "US"
		local mine, theirs = teamSize(faction), teamSize(other)
		if player:GetAttribute("Faction") == other then
			theirs -= 1
		end
		if mine >= Roles.TEAM_MAX or mine > theirs then
			return -- cheio ou desequilibraria
		end
		leaveAll(player)
		player:SetAttribute("Faction", faction)
		player.Team = teamObjects[faction]
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = 0 -- troca de lado: volta para o mapa de spawn
		end
		pushSquads(faction)
		pushSquads(other)
	end)

	Net.event("Squad_Action").OnServerEvent:Connect(function(player, req)
		local faction = player:GetAttribute("Faction") :: string?
		if not faction or type(req) ~= "table" then
			return
		end
		local st = TeamService.squads[faction]
		if req.op == "create" and type(req.unit) == "string" then
			local sq = Squads.create(st, req.unit, player.UserId, teamSize(faction))
			if sq then
				player:SetAttribute("SquadId", sq.id)
				setRole(player, nil)
			end
		elseif req.op == "join" and type(req.id) == "string" then
			if Squads.join(st, req.id, player.UserId) then
				player:SetAttribute("SquadId", req.id)
				setRole(player, nil)
			end
		elseif req.op == "leave" then
			Squads.leave(st, player.UserId)
			player:SetAttribute("SquadId", nil)
			setRole(player, nil)
		end
		pushSquads(faction)
	end)

	Net.event("Role_Choose").OnServerEvent:Connect(function(player, roleId)
		local faction = player:GetAttribute("Faction") :: string?
		if not faction or type(roleId) ~= "string" then
			return
		end
		if Squads.chooseRole(TeamService.squads[faction], player.UserId, roleId) then
			setRole(player, roleId)
			pushSquads(faction)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local faction = player:GetAttribute("Faction") :: string?
		leaveAll(player)
		if faction then
			pushSquads(faction)
		end
	end)
end

return TeamService
