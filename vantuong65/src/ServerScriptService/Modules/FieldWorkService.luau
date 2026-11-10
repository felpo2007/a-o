--!strict
-- Pá de trincheira e medevac (Parte 11). Regras em Shared/FieldWork.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FieldWork = require(ReplicatedStorage.Shared.FieldWork)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local AssetLoader = require(script.Parent.AssetLoader)
local Combatants = require(script.Parent.Combatants)
local LogisticsService = require(script.Parent.LogisticsService)
local MatchService = require(script.Parent.MatchService)

local FieldWorkService = {}
local M = 0.28
local lastDig: { [Player]: number } = {}
local digging: { [Player]: boolean } = {}
local holes = 0

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include

local function toast(p: Player, text: string)
	Net.event("Logistics_State"):FireClient(p, { error = text })
end

-- ===== pá =====
local function onDig(p: Player)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) or hum.Health <= 0 or char:GetAttribute("Downed") or hum.SeatPart or digging[p] then
		return
	end
	local C = FieldWork.DIG
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local at = root.Position + look.Unit * (C.aheadM / M)
	local hit = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), terrainOnly)
	if not hit then
		return
	end
	local sector = Geometry.sectorAt(MapConfig.Sectors, at.X, at.Z)
	local owner = if sector then MatchService.ownerOf(sector) else nil
	-- água: terreno de água ou a lâmina d'água do arrozal (peça com Material "PaddyWater")
	local anyParams = RaycastParams.new()
	anyParams.FilterType = Enum.RaycastFilterType.Exclude
	anyParams.FilterDescendantsInstances = { char }
	local top = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), anyParams)
	local onWater = hit.Material == Enum.Material.Water
		or (top ~= nil and top.Instance:GetAttribute("Material") == "PaddyWater")
	local ok, why =
		FieldWork.canDig(owner, p:GetAttribute("Faction") :: string?, onWater, lastDig[p], os.clock(), holes)
	if not ok then
		toast(p, "Pá: " .. tostring(why))
		return
	end
	digging[p] = true
	local start = root.Position
	toast(p, string.format("Cavando… fique parado %d s", C.seconds))
	task.delay(C.seconds, function()
		digging[p] = nil
		local r2 = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if
			not r2
			or hum.Health <= 0
			or char:GetAttribute("Downed")
			or (r2.Position - start).Magnitude * M > C.stillM
		then
			toast(p, "Pá: cancelado (você se moveu)")
			return
		end
		lastDig[p] = os.clock()
		holes += 1
		local yaw = math.atan2(-look.X, -look.Z)
		local cf = CFrame.new(hit.Position) * CFrame.Angles(0, yaw, 0)
		-- buraco: tira o terreno; a terra vira o parapeito de sacos de areia à frente
		workspace.Terrain:FillBlock(
			cf * CFrame.new(0, -C.depthM / 2 / M, 0),
			Vector3.new(C.lengthM / M, C.depthM / M, C.widthM / M),
			Enum.Material.Air
		)
		local front = cf * CFrame.new(0, 0, -(C.widthM / 2 + 0.4) / M)
		local folder = workspace:FindFirstChild("Map") and (workspace :: any).Map:FindFirstChild("Art")
		if folder then
			AssetLoader.place("sandbags", front.Position.X, front.Position.Z, yaw, folder)
		end
	end)
end

FieldWorkService.dig = onDig -- autoteste (SelfTest) chama direto

-- ===== medevac =====
local boarding: { [Model]: number } = {}

local function helis(): { Model }
	local out = {}
	local f = workspace:FindFirstChild("Vehicles")
	for _, m in (if f then f:GetChildren() else {}) do
		if m:IsA("Model") and m:GetAttribute("Spec") == "uh34d" then
			table.insert(out, m)
		end
	end
	return out
end

local function heliReady(h: Model): boolean
	local ch = h.PrimaryPart
	if not ch then
		return false
	end
	local hit = workspace:Raycast(ch.Position, Vector3.new(0, -200, 0), terrainOnly)
	local alt = if hit then (ch.Position.Y - ch.Size.Y / 2 - hit.Position.Y) * M else math.huge
	return FieldWork.heliReady(ch.AssemblyLinearVelocity.Magnitude * M, alt, h:GetAttribute("Destroyed") == true)
end

local function medevacTick()
	local ready = {}
	for _, h in helis() do
		if heliReady(h) and h.PrimaryPart then
			table.insert(ready, (h.PrimaryPart :: BasePart).Position)
		end
	end
	for _, e in Combatants.list() do
		local model, root = e.model, Combatants.root(e)
		if e.faction == "US" and root and model:GetAttribute("Downed") and not model:GetAttribute("Evacuated") then
			local near = false
			for _, pos in ready do
				if (pos - root.Position).Magnitude * M <= FieldWork.MEDEVAC.radiusM then
					near = true
				end
			end
			local t, done = FieldWork.boarding(boarding[model] or 0, near, 1)
			boarding[model] = t
			if done then
				boarding[model] = nil
				model:SetAttribute("Evacuated", true) -- não conta como morto no relatório
				local st = LogisticsService.state
				st.supply.US = math.min(Logistics.CAP, (st.supply.US or 0) + FieldWork.MEDEVAC.supply)
				local hum = Combatants.humanoid(e)
				if e.player then
					toast(
						e.player,
						string.format("Evacuado pelo UH-34D: +%d de suprimento para o time", FieldWork.MEDEVAC.supply)
					)
				end
				if hum then
					hum.Health = 0 -- sai do campo; renasce pelas regras normais
				end
			end
		end
	end
end

function FieldWorkService.start()
	terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
	Net.event("Dig_Request").OnServerEvent:Connect(onDig)
	Players.PlayerRemoving:Connect(function(p)
		lastDig[p] = nil
		digging[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			medevacTick()
		end
	end)
end

return FieldWorkService
