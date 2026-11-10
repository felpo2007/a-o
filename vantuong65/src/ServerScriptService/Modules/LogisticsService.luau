--!strict
-- Logística (F4): suprimento por facção, caixotes físicos, construções (posto de reunião, ninho de
-- metralhadora, posição de morteiro, caixa de munição) e pontos de reunião temporários de túnel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logistics = require(ReplicatedStorage.Shared.Logistics)
local Net = require(ReplicatedStorage.Shared.Net)
local AssetLoader = require(script.Parent.AssetLoader)
local CombatService = require(script.Parent.CombatService)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local SpawnService = require(script.Parent.SpawnService)

local LogisticsService = {}
local M = 0.28
LogisticsService.state = Logistics.new()

type Built = { id: string, kind: string, faction: string, pos: Vector3, model: Instance }
local built: { Built } = {}
local temp: { { faction: string, x: number, z: number, name: string, untilT: number, id: string } } = {}
local folder: Folder

local function counts(faction: string, kind: string): number
	local n = 0
	for _, b in built do
		if b.faction == faction and b.kind == kind and b.model.Parent then
			n += 1
		end
	end
	return n
end

local function nearestEnemyM(faction: string, pos: Vector3): number
	local best = math.huge
	for _, e in Combatants.list() do
		if e.faction ~= faction and Combatants.active(e) then
			local r = Combatants.root(e)
			if r then
				best = math.min(best, (r.Position - pos).Magnitude * M)
			end
		end
	end
	return best
end

function LogisticsService.crates(faction: string): { BasePart }
	local out = {}
	for _, c in folder:GetChildren() do
		if c:IsA("BasePart") and c.Name == "Crate" and c:GetAttribute("Faction") == faction then
			table.insert(out, c)
		end
	end
	return out
end

local function nearestCrateM(faction: string, pos: Vector3): number
	local best = math.huge
	for _, c in LogisticsService.crates(faction) do
		best = math.min(best, (c.Position - pos).Magnitude * M)
	end
	return best
end

function LogisticsService.spend(faction: string, amount: number): boolean
	return Logistics.spend(LogisticsService.state, faction, amount)
end

function LogisticsService.supply(faction: string): number
	return LogisticsService.state.supply[faction] or 0
end

-- Caixote de suprimento: fica no chão; o próximo construtor perto dele não paga deslocamento.
-- Ao ser "aberto" (ProximityPrompt) soma ao suprimento da facção.
function LogisticsService.spawnCrate(faction: string, pos: Vector3, amount: number?): BasePart
	local c = Instance.new("Part")
	c.Name = "Crate"
	c.Size = Vector3.new(0.9, 0.6, 0.6) / M
	c.Color = if faction == "US" then Color3.fromRGB(92, 98, 66) else Color3.fromRGB(120, 96, 64)
	c.Material = Enum.Material.WoodPlanks
	c.Anchored = true
	c.CFrame = CFrame.new(SpawnService.groundY(pos.X, pos.Z) * Vector3.yAxis + Vector3.new(pos.X, c.Size.Y / 2, pos.Z))
	c:SetAttribute("Faction", faction)
	c:SetAttribute("Amount", amount or Logistics.CRATE)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir suprimento"
	prompt.ObjectText = "Caixote"
	prompt.HoldDuration = 3
	prompt.MaxActivationDistance = 10
	prompt.Parent = c
	prompt.Triggered:Connect(function(player)
		if player:GetAttribute("Faction") ~= faction or not c.Parent then
			return
		end
		Logistics.add(LogisticsService.state, faction, c:GetAttribute("Amount") :: number)
		c:Destroy()
	end)
	c.Parent = folder
	return c
end

local function place(kind: string, faction: string, pos: Vector3, yaw: number): Instance
	local out: Instance
	if kind == "mg_nest" then
		local m = AssetLoader.place("sandbags", pos.X, pos.Z, yaw, folder)
		out = m or Instance.new("Model")
	elseif kind == "mortar_pit" then
		local key = if faction == "US" then "mortar_81" else "mortar_82"
		local m = AssetLoader.place(key, pos.X, pos.Z, yaw, folder)
		out = m or Instance.new("Model")
	else
		local p = Instance.new("Part")
		p.Size = if kind == "garrison" then Vector3.new(1.2, 2.2, 0.1) / M else Vector3.new(0.6, 0.4, 0.4) / M
		p.Color = Color3.fromRGB(80, 70, 50)
		p.Anchored = true
		p.CFrame = CFrame.new(pos.X, SpawnService.groundY(pos.X, pos.Z) + p.Size.Y / 2, pos.Z)
			* CFrame.Angles(0, yaw, 0)
		if kind == "ammo" then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Pegar munição"
			prompt.HoldDuration = 2
			prompt.Parent = p
			prompt.Triggered:Connect(function(player)
				if player:GetAttribute("Faction") == faction then
					CombatService.refill(player)
				end
			end)
		end
		out = p
	end
	if out:IsA("Model") and not out.Parent then
		out.Parent = folder
	elseif out:IsA("BasePart") then
		out.Parent = folder
	end
	out:SetAttribute("Faction", faction)
	out:SetAttribute("Build", kind)
	return out
end

local function handleBuild(player: Player, req: any)
	local kind = type(req) == "table" and req.kind
	local faction = player:GetAttribute("Faction")
	local role = player:GetAttribute("Role")
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if type(kind) ~= "string" or type(faction) ~= "string" or type(role) ~= "string" or not root then
		return
	end
	local pos = root.Position + root.CFrame.LookVector * (2 / M)
	local ok, why = Logistics.canBuild(
		LogisticsService.state,
		faction,
		role,
		kind,
		counts(faction, kind),
		nearestEnemyM(faction, pos),
		nearestCrateM(faction, pos)
	)
	if not ok then
		Net.event("Logistics_State"):FireClient(player, { error = why })
		return
	end
	local def = Logistics.BUILDS[kind]
	Logistics.spend(LogisticsService.state, faction, def.cost)
	local _, yaw, _ = root.CFrame:ToOrientation()
	local model = place(kind, faction, pos, yaw)
	local id = kind .. ":" .. tostring(#built + 1)
	table.insert(built, { id = id, kind = kind, faction = faction, pos = pos, model = model })
	if kind == "mortar_pit" then
		player:SetAttribute("MortarX", pos.X)
		player:SetAttribute("MortarZ", pos.Z)
	end
end

-- ponto de reunião temporário (reforço pelo túnel do comandante VC)
function LogisticsService.tempGarrison(faction: string, x: number, z: number, name: string, seconds: number)
	table.insert(
		temp,
		{ faction = faction, x = x, z = z, name = name, untilT = os.clock() + seconds, id = "temp:" .. name }
	)
end

function LogisticsService.start()
	folder = Instance.new("Folder")
	folder.Name = "Logistics"
	folder.Parent = workspace
	Net.event("Build_Request").OnServerEvent:Connect(handleBuild)
	SpawnService.addProvider(function(faction: string)
		local out = {}
		for _, b in built do
			if b.kind == "garrison" and b.faction == faction and b.model.Parent then
				table.insert(
					out,
					{ id = b.id, name = "Posto de reunião", x = b.pos.X, z = b.pos.Z, kind = "garrison" }
				)
			end
		end
		local now = os.clock()
		for _, t in temp do
			if t.faction == faction and t.untilT > now then
				table.insert(out, { id = t.id, name = t.name, x = t.x, z = t.z, kind = "garrison" })
			end
		end
		return out :: any
	end)
	-- renda por minuto e estado para os clientes
	task.spawn(function()
		while true do
			task.wait(1)
			local owned = { US = 0, VC = 0 }
			for s in MatchService.points do
				local o = MatchService.ownerOf(s)
				if owned[o] then
					owned[o] += 1
				end
			end
			Logistics.tick(LogisticsService.state, 1, owned)
			for _, p in Players:GetPlayers() do
				local f = p:GetAttribute("Faction")
				if f then
					p:SetAttribute("Supply", LogisticsService.state.supply[f])
				end
			end
		end
	end)
	-- caixotes iniciais: praia (EUA) e depósito de retaguarda (VC)
	local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
	for f, hq in MapConfig.HQ do
		for i = 1, 2 do
			LogisticsService.spawnCrate(f, Vector3.new(hq.x + i * 12, 0, hq.z + 8), Logistics.CRATE)
		end
	end
end

return LogisticsService
