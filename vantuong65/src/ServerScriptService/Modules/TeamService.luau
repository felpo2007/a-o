--!strict
-- Escolha de facção, squad e papel (Parte 4), com limite de 30 por time e equilíbrio.
-- Jogar agora (2026-11-13): TeamService.quickJoin põe quem pediu num lado, num squad com vaga e num
-- papel pela última escolha (Shared/JogarAgora); a escolha fica no perfil (campo `unit`) e no
-- atributo "UltimaEscolha" (a tela mostra o que vai acontecer).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local JogarAgora = require(ReplicatedStorage.Shared.JogarAgora)
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Squads = require(ReplicatedStorage.Shared.Squads)
local PlayerData = require(script.Parent.PlayerData)

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

-- D-108: a arma principal escolhida no cartão do papel (Roles.PRIMARY), guardada no atributo
-- "Primaria" (vale no próximo nascimento: o CombatService lê o "Loadout" ao nascer)
local function applyLoadout(player: Player, roleId: string?, primary: string?)
	local faction = player:GetAttribute("Faction") :: string?
	local loadout = if roleId and faction then Roles.loadoutFor(faction, roleId, primary) else nil
	player:SetAttribute("Loadout", if loadout then table.concat(loadout, ",") else nil)
	local p = if roleId and faction then Roles.primaryFor(faction, roleId, primary) else nil
	player:SetAttribute("Primaria", if p and #Roles.primaries(faction :: string, roleId :: string) > 1 then p else nil)
end

local function setRole(player: Player, roleId: string?, primary: string?)
	player:SetAttribute("Role", roleId)
	applyLoadout(player, roleId, primary)
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

-- troca de lado com a regra de equilíbrio (cheio ou desequilibraria: recusa)
local function chooseFaction(player: Player, faction: string): boolean
	if faction ~= "US" and faction ~= "VC" or player:GetAttribute("Faction") == faction then
		return false
	end
	local other = if faction == "US" then "VC" else "US"
	local mine, theirs = teamSize(faction), teamSize(other)
	if player:GetAttribute("Faction") == other then
		theirs -= 1
	end
	if mine >= Roles.TEAM_MAX or mine > theirs then
		return false -- cheio ou desequilibraria
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
	return true
end

-- ===== última escolha (perfil e atributo) =====
function TeamService.lastChoice(player: Player): JogarAgora.Choice
	local prof = PlayerData.get(player)
	local c = JogarAgora.sanitize(if prof then (prof :: any).unit else nil)
	local pt = player:GetAttribute("UltimoPonto")
	if type(pt) == "string" then
		c.pt = JogarAgora.sanitize({ pt = pt }).pt
	end
	return c
end

-- Guarda o lado, o squad, o papel e o último ponto de agora (o perfil grava no próximo save).
function TeamService.remember(player: Player)
	local c = TeamService.lastChoice(player)
	local f = player:GetAttribute("Faction")
	local sid = player:GetAttribute("SquadId")
	local role = player:GetAttribute("Role")
	if type(f) == "string" and TeamService.squads[f] then
		local sq = if type(sid) == "string" then Squads.find(TeamService.squads[f], sid) else nil
		c.f = f
		if sq then
			c.unit, c.sq = sq.unit, sq.name
		end
		if type(role) == "string" then
			c.role = role
			local w = player:GetAttribute("Primaria")
			c.w = if type(w) == "string" then w else nil
		end
	end
	local clean = JogarAgora.sanitize(JogarAgora.pack(c))
	local prof = PlayerData.get(player)
	if prof then
		(prof :: any).unit = JogarAgora.pack(clean)
	end
	player:SetAttribute("UltimaEscolha", JogarAgora.encode(clean))
end

-- Jogar agora: lado, squad com vaga e papel, pela última escolha ou pelo mais adequado. rank: posto
-- do jogador (ProgressionService). Devolve nil (pronto) ou o motivo, em texto de tela.
function TeamService.quickJoin(player: Player, rank: number): string?
	local last = TeamService.lastChoice(player)
	local f = player:GetAttribute("Faction")
	if type(f) ~= "string" or not TeamService.squads[f] then
		local pick = JogarAgora.pickFaction(last.f, teamSize("US"), teamSize("VC"), Roles.TEAM_MAX)
		if not pick or not chooseFaction(player, pick) then
			return "Os dois lados estão cheios"
		end
		f = pick
	end
	local faction = f :: string
	local st = TeamService.squads[faction]
	local sq = Squads.squadOf(st, player.UserId)
	if not sq then
		local op, arg = JogarAgora.pickSquad(faction, st.squads :: any, last, teamSize(faction))
		if op == "join" and arg and Squads.join(st, arg, player.UserId) then
			player:SetAttribute("SquadId", arg)
			setRole(player, nil)
		elseif op == "create" and arg then
			local made = Squads.create(st, arg, player.UserId, teamSize(faction))
			if made then
				player:SetAttribute("SquadId", made.id)
				setRole(player, nil)
			end
		end
		sq = Squads.squadOf(st, player.UserId)
		pushSquads(faction)
		if not sq then
			return "Nenhum squad com vaga agora"
		end
	end
	local squad = sq :: Squads.Squad
	local role = player:GetAttribute("Role")
	if type(role) ~= "string" or squad.roles[player.UserId] ~= role then
		local r = JogarAgora.pickRole(faction, squad :: any, player.UserId, last, rank)
		if not r or not Squads.chooseRole(st, player.UserId, r) then
			return "Nenhum papel livre neste squad"
		end
		setRole(player, r, if r == last.role then last.w else nil)
		pushSquads(faction)
	end
	TeamService.remember(player)
	return nil
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

	-- a última escolha do perfil vira atributo (a tela do jogar agora mostra o squad e o ponto)
	local function loaded(player: Player, prof: any)
		local c = JogarAgora.sanitize(if type(prof) == "table" then prof.unit else nil)
		player:SetAttribute("UltimaEscolha", JogarAgora.encode(c))
		if c.pt and player:GetAttribute("UltimoPonto") == nil then
			player:SetAttribute("UltimoPonto", c.pt)
		end
	end
	PlayerData.Loaded:Connect(loaded)
	for _, p in Players:GetPlayers() do
		local prof = PlayerData.get(p)
		if prof then
			loaded(p, prof)
		end
	end

	Net.event("Team_Choose").OnServerEvent:Connect(function(player, faction)
		if type(faction) == "string" then
			chooseFaction(player, faction)
		end
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

	-- (papel, arma principal?) D-108: o mesmo papel com outra arma só troca o equipamento (sem os +15 s
	-- da troca de papel); vale no próximo nascimento
	Net.event("Role_Choose").OnServerEvent:Connect(function(player, roleId, primary)
		local faction = player:GetAttribute("Faction") :: string?
		if not faction or type(roleId) ~= "string" then
			return
		end
		local w = if type(primary) == "string" and #primary <= 24 then primary else nil
		if player:GetAttribute("Role") == roleId and Squads.squadOf(TeamService.squads[faction], player.UserId) then
			applyLoadout(player, roleId, w)
			TeamService.remember(player)
			return
		end
		if Squads.chooseRole(TeamService.squads[faction], player.UserId, roleId) then
			setRole(player, roleId, w)
			pushSquads(faction)
			TeamService.remember(player)
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
