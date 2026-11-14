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

-- Buraco com o fundo na altura pedida. O voxel do terreno tem 4 studs (1,12 m) e a superfície é
-- suavizada: um FillBlock de 0,6 m de largura afundava só 0,2 a 0,5 m (reteste no Studio,
-- 2026-11-10). Aqui as colunas de voxels sob a pegada ficam vazias acima do fundo, e o voxel do
-- fundo fica com ocupação proporcional. A pegada vira múltiplo do voxel (2,2 a 3,4 m de lado).
-- A suavização ainda ergue o fundo de um buraco tão estreito: pedindo 1,2 m ele ficava a 0,58 m
-- (média de 10 buracos no Studio); pedindo 1,8 m, a 1,19 m (mediana de 42 medidas). Daí o extra.
local VOXEL = 4
local SMOOTH_EXTRA_M = 0.6
local function excavate(cf: CFrame, lengthS: number, widthS: number, floorY: number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, s in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local p = cf * Vector3.new(s[1] * lengthS / 2, 0, s[2] * widthS / 2)
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	local region =
		Region3.new(Vector3.new(minX, floorY - VOXEL, minZ), Vector3.new(maxX, cf.Position.Y + 2 * VOXEL, maxZ))
			:ExpandToGrid(VOXEL)
	local mats, occs = workspace.Terrain:ReadVoxels(region, VOXEL)
	local size = mats.Size
	local y0 = region.CFrame.Position.Y - region.Size.Y / 2
	for x = 1, size.X do
		for z = 1, size.Z do
			-- material do chão da coluna: o voxel cheio mais alto
			local ground = Enum.Material.Ground
			for y = size.Y, 1, -1 do
				if mats[x][y][z] ~= Enum.Material.Air then
					ground = mats[x][y][z]
					break
				end
			end
			for y = 1, size.Y do
				local yb = y0 + (y - 1) * VOXEL
				if yb >= floorY then
					mats[x][y][z] = Enum.Material.Air
					occs[x][y][z] = 0
				elseif yb + VOXEL > floorY then
					local o = (floorY - yb) / VOXEL
					if occs[x][y][z] > o or mats[x][y][z] == Enum.Material.Air then
						mats[x][y][z] = ground
						occs[x][y][z] = o
					end
				end
			end
		end
	end
	workspace.Terrain:WriteVoxels(region, VOXEL, mats, occs)
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
		toast(p, string.format("Pá: %s", tostring(why)))
		return
	end
	digging[p] = true
	local start = root.Position
	toast(p, string.format("Cavando… fique parado %d s", C.seconds))
	-- D-99: a animação da pá (ItemView) segue esta chave, nunca o texto do aviso, que pode vir traduzido
	Net.event("Logistics_State"):FireClient(p, { key = "dig_start" })
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
			Net.event("Logistics_State"):FireClient(p, { key = "dig_cancel" })
			return
		end
		lastDig[p] = os.clock()
		holes += 1
		local yaw = math.atan2(-look.X, -look.Z)
		local cf = CFrame.new(hit.Position) * CFrame.Angles(0, yaw, 0)
		-- buraco: tira o terreno; a terra vira o parapeito de sacos de areia à frente
		excavate(cf, C.lengthM / M, C.widthM / M, hit.Position.Y - (C.depthM + SMOOTH_EXTRA_M) / M)
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
