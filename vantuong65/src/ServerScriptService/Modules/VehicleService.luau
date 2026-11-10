--!strict
-- Veículos da F4: M48A3, Ontos, LVTP-5 e UH-34D nos depósitos dos EUA (o VC de 1965 em Starlite não
-- tinha blindados). O motorista simula o próprio veículo (posse de rede) com Shared/Vehicles e
-- Shared/HeliModel; o servidor valida velocidade, assentos por papel, tiros e dano por zona.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local AssetLoader = require(script.Parent.AssetLoader)
local CombatService = require(script.Parent.CombatService)
local ExplosionService = require(script.Parent.ExplosionService)
local MedicalService = require(script.Parent.MedicalService)
local SpawnService = require(script.Parent.SpawnService)

local VehicleService = {}
local M = MapConfig.STUD_M
local G = 9.80665
local rng = Rng.new(1965081)
local folder: Folder
local nextId = 0

-- Depósitos ao redor do QG dos EUA na praia (posições de design, D-37). 6 veículos = critério da F4.
local DEPOTS = {
	{ spec = "lvtp5", dx = 140, dz = -40 },
	{ spec = "lvtp5", dx = 140, dz = 0 },
	{ spec = "m48a3", dx = 60, dz = -30 },
	{ spec = "ontos", dx = 60, dz = 10 },
	{ spec = "uh34d", dx = -80, dz = -60 },
	{ spec = "uh34d", dx = -80, dz = 30 },
}
local RESPAWN_S = 180 -- design
-- Giro da arte em relação ao chassi (frente do chassi = -Z). Os GLBs dos veículos vieram com o eixo
-- longo em X e o ForgeGUI não infere a frente: 90° é o palpite; se no Studio o veículo andar de
-- ré, troque por -90° (TODO_USUARIO).
local ART_YAW: { [string]: number } = {
	m48a3 = math.rad(90),
	ontos = math.rad(90),
	lvtp5 = math.rad(90),
	uh34d = math.rad(90),
}

-- Armas de veículo e foguetes de infantaria (projéteis simulados no servidor).
-- v0: 106 mm M344 HEAT = 503 m/s (wiki:M40_recoilless_rifle); demais PLACEHOLDER (D-36).
local GUNS = {
	gun_90 = { explosive = "he_90", pen = "he_90", v0 = 820, reloadS = 6, launch = "gun_90" },
	rr_106 = { explosive = "heat_106", pen = "heat_106", v0 = 503, reloadS = 1.2, launch = "rr_106", tubes = 6 },
	pg2 = { explosive = "pg2", pen = "pg2", v0 = 84, reloadS = 6, launch = "rocket" },
	rocket_35 = { explosive = "rocket_35", pen = "rocket_35", v0 = 100, reloadS = 6, launch = "rocket" },
}
local lastShot: { [Instance]: number } = {}

local function chassisOf(inst: Instance?): BasePart?
	local m = inst and inst:FindFirstAncestorWhichIsA("Model")
	while m and not m:GetAttribute("VehicleId") do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return m and m:FindFirstChild("Chassis") :: BasePart?
end

local function occupants(model: Model): { Model }
	local out = {}
	for _, s in model:GetDescendants() do
		if s:IsA("Seat") and s.Occupant then
			table.insert(out, s.Occupant.Parent :: Model)
		end
	end
	return out
end

local function destroyVehicle(model: Model)
	if model:GetAttribute("Destroyed") then
		return
	end
	model:SetAttribute("Destroyed", true)
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	for _, occ in occupants(model) do
		MedicalService.hit(occ, "torso", 3000, rng:next())
	end
	if chassis then
		ExplosionService.detonate("he_90", chassis.Position)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = Color3.fromRGB(30, 28, 26)
		elseif d:IsA("Seat") then
			d.Disabled = true
		end
	end
	local spec, depot = model:GetAttribute("Spec"), model:GetAttribute("Depot")
	task.delay(30, function()
		model:Destroy()
	end)
	task.delay(RESPAWN_S, function()
		if type(spec) == "string" and type(depot) == "number" then
			VehicleService.spawn(spec, depot)
		end
	end)
end

-- dano direto de projétil num veículo: zona pela direção, blindagem, penetração e componentes
local function hitVehicle(model: Model, chassis: BasePart, penKey: string, dir: Vector3)
	local spec = Vehicles.SPECS[model:GetAttribute("Spec") :: string]
	if not spec then
		return
	end
	local loc = chassis.CFrame:VectorToObjectSpace(dir.Unit)
	local zone = Vehicles.zoneFromLocal(loc.X, loc.Y, loc.Z)
	local pen = Vehicles.PEN[penKey] or 0
	local integ = model:GetAttribute("Integrity") :: number
	if spec.kind == "heli" or not spec.armor then
		model:SetAttribute("Integrity", integ - 50)
	else
		local armor = (spec.armor :: any)[zone] or (spec.armor :: any).side
		local through, ratio = Vehicles.penetrates(pen, armor, 0, rng:next())
		if not through then
			return
		end
		model:SetAttribute("Integrity", integ - 40 * math.clamp(ratio, 1, 2))
		if zone == "rear" and rng:next() < 0.5 then
			model:SetAttribute("Engine", 0)
		elseif zone == "side" and rng:next() < 0.3 then
			model:SetAttribute("Tracks", 0)
		end
		local occ = occupants(model)
		if #occ > 0 then -- estilhaços internos atingem um tripulante
			MedicalService.hit(occ[1 + math.floor(rng:next() * #occ)], "torso", 800, rng:next())
		end
	end
	if (model:GetAttribute("Integrity") :: number) <= 0 then
		destroyVehicle(model)
	end
end

-- sopro de explosão perto de veículos (morteiro, naval, bomba)
ExplosionService.onVehicles = function(pos: Vector3, id: string)
	for _, model in folder:GetChildren() do
		local chassis = model:FindFirstChild("Chassis") :: BasePart?
		if model:IsA("Model") and chassis and not model:GetAttribute("Destroyed") then
			local dM = (chassis.Position - pos).Magnitude * M
			local big = id == "naval_5in" or id == "bomb_250lb"
			local reach = if big then 8 else 3
			if dM < reach then
				local integ = model:GetAttribute("Integrity") :: number
				local spec = Vehicles.SPECS[model:GetAttribute("Spec") :: string]
				local factor = if spec and spec.kind == "heli" then 2 elseif big then 1 else 0.3
				model:SetAttribute("Integrity", integ - 30 * factor * (1 - dM / reach))
				if (model:GetAttribute("Integrity") :: number) <= 0 then
					destroyVehicle(model)
				end
			end
		end
	end
end

-- projétil balístico simulado no servidor (gravidade; o arrasto é desprezado a essas distâncias)
local function shoot(gun: any, origin: Vector3, dir: Vector3, ignore: { Instance })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	Net.unreliable("Fire_Launch"):FireAllClients({ kind = gun.launch, x = origin.X, y = origin.Y, z = origin.Z })
	task.spawn(function()
		local pos = origin
		local vel = dir.Unit * gun.v0 / M
		local t = 0
		while t < 8 do
			local dt = task.wait()
			t += dt
			local nv = vel - Vector3.new(0, G / M * dt, 0)
			local step = (vel + nv) / 2 * dt
			local hit = workspace:Raycast(pos, step, params)
			if hit then
				local chassis = chassisOf(hit.Instance)
				if chassis then
					hitVehicle(chassis.Parent :: Model, chassis, gun.pen, step)
				end
				ExplosionService.detonate(gun.explosive, hit.Position)
				return
			end
			pos += step
			vel = nv
		end
	end)
end

local function seatOf(player: Player): Seat?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local s = hum and hum.SeatPart
	return if s and s:IsA("Seat") then s else nil
end

local function onFire(player: Player, req: any)
	if type(req) ~= "table" or typeof(req.dir) ~= "Vector3" or req.dir.Magnitude < 0.5 then
		return
	end
	local dir: Vector3 = req.dir.Unit
	local char = player.Character
	if not char then
		return
	end
	local seat = seatOf(player)
	local now = os.clock()
	if seat then
		local weapon = seat:GetAttribute("Weapon")
		local model = seat:FindFirstAncestorWhichIsA("Model") :: Model
		if type(weapon) ~= "string" or model:GetAttribute("Destroyed") then
			return
		end
		local origin = seat.Position + Vector3.new(0, 2.5 / M, 0) + dir * (2 / M)
		if weapon == "m60" then
			CombatService.fire(char, "m60", origin, dir, math.floor(rng:next() * 2 ^ 31), player)
			return
		end
		local gun = GUNS[weapon]
		if not gun or now - (lastShot[seat] or 0) < gun.reloadS then
			return
		end
		if gun.tubes then
			local left = (model:GetAttribute("Tubes") :: number?) or 0
			if left <= 0 then
				return
			end
			model:SetAttribute("Tubes", left - 1)
		end
		lastShot[seat] = now
		shoot(gun, origin, dir, { model, char })
		return
	end
	-- foguete de infantaria (papel antitanque, a pé)
	if player:GetAttribute("Role") ~= "anti_tank" then
		return
	end
	local key = if player:GetAttribute("Faction") == "VC" then "pg2" else "rocket_35"
	local left = (player:GetAttribute("Rockets") :: number?) or 0
	if left <= 0 or now - (lastShot[player :: any] or 0) < GUNS[key].reloadS then
		return
	end
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	player:SetAttribute("Rockets", left - 1)
	lastShot[player :: any] = now
	shoot(GUNS[key], head.Position + dir * (1.5 / M), dir, { char })
end

-- recarga do Ontos: os tubos são carregados por fora; só com o veículo parado (10 s por tubo, D-36)
local function onReload(player: Player)
	local seat = seatOf(player)
	if not seat or seat:GetAttribute("Weapon") ~= "rr_106" then
		return
	end
	local model = seat:FindFirstAncestorWhichIsA("Model") :: Model
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	if model:GetAttribute("Reloading") or chassis.AssemblyLinearVelocity.Magnitude * M > 0.5 then
		return
	end
	model:SetAttribute("Reloading", true)
	task.spawn(function()
		while (model:GetAttribute("Tubes") :: number) < GUNS.rr_106.tubes do
			task.wait(10)
			if chassis.AssemblyLinearVelocity.Magnitude * M > 0.5 or not model.Parent then
				break
			end
			model:SetAttribute("Tubes", (model:GetAttribute("Tubes") :: number) + 1)
		end
		model:SetAttribute("Reloading", nil)
	end)
end

local function addSeat(model: Model, chassis: BasePart, id: string, role: string, weapon: string?, offset: Vector3)
	local s = Instance.new("Seat")
	s.Name = "Seat_" .. id
	s.Size = Vector3.new(0.5, 0.2, 0.5) / M
	s.Transparency = 1
	s.CanCollide = false
	s.Massless = true
	s.CFrame = chassis.CFrame * CFrame.new(offset)
	s:SetAttribute("SeatId", id)
	s:SetAttribute("Role", role)
	if weapon then
		s:SetAttribute("Weapon", weapon)
	end
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = chassis, s
	w.Parent = s
	s.Parent = model
	s:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = s.Occupant
		local player = hum and Players:GetPlayerFromCharacter(hum.Parent)
		if hum and player then
			local ok = player:GetAttribute("Faction") == model:GetAttribute("Faction")
				and (role == "any" or player:GetAttribute("Role") == role)
			if not ok then
				task.defer(function()
					hum.Sit = false
				end)
				return
			end
		end
		if id == "driver" then
			-- helicóptero sem piloto não fica parado no ar: solta o controle e a gravidade age
			local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
			if lv and model:GetAttribute("Kind") == "heli" then
				lv.Enabled = player ~= nil
			end
			if player then
				pcall(function()
					chassis:SetNetworkOwner(player)
				end)
			else
				pcall(function()
					chassis:SetNetworkOwner(nil)
				end)
			end
		end
	end)
end

function VehicleService.spawn(specId: string, depot: number): Model?
	local spec = Vehicles.SPECS[specId]
	local d = DEPOTS[depot]
	local hq = MapConfig.HQ.US
	if not spec or not d then
		return nil
	end
	nextId += 1
	local x, z = hq.x + d.dx / M, hq.z + d.dz / M
	local L, W, H = spec.lengthM / M, spec.widthM / M, spec.heightM / M
	local model = Instance.new("Model")
	model.Name = spec.name
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(W, H * 0.55, if spec.kind == "heli" then L * 0.8 else L * 0.75)
	chassis.Color = Color3.fromRGB(86, 90, 62)
	chassis.Material = Enum.Material.Metal
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.6, 0.1)
	chassis.CFrame = CFrame.new(x, SpawnService.groundY(x, z) + chassis.Size.Y / 2 + 1, z)
	chassis.Parent = model
	model.PrimaryPart = chassis
	-- arte do ForgeGUI (se publicada): soldada, sem colisão; o chassi vira invisível
	local tpl = AssetLoader.template(specId)
	if tpl then
		local art = tpl:Clone()
		art.Name = "Art"
		local _, size = art:GetBoundingBox()
		art:PivotTo(
			chassis.CFrame
				* CFrame.new(0, -chassis.Size.Y / 2 + size.Y / 2, 0)
				* CFrame.Angles(0, ART_YAW[specId] or 0, 0)
		)
		for _, p in art:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = false
				p.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = chassis, p
				w.Parent = p
			end
		end
		art.Parent = model
		chassis.Transparency = 1
	end
	local att = Instance.new("Attachment")
	att.Name = "Drive"
	att.Parent = chassis
	local lv = Instance.new("LinearVelocity")
	lv.Name = "DriveVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	if spec.kind == "heli" then
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.MaxForce = chassis.AssemblyMass * workspace.Gravity * 3
		lv.Enabled = false -- só com piloto
	else
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		lv.PrimaryTangentAxis = Vector3.xAxis
		lv.SecondaryTangentAxis = Vector3.zAxis
		lv.MaxForce = chassis.AssemblyMass * workspace.Gravity * 2
	end
	lv.Parent = chassis
	local ao = Instance.new("AlignOrientation")
	ao.Name = "DriveAttitude"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.Responsiveness = 12
	ao.MaxTorque = chassis.AssemblyMass * workspace.Gravity * 50
	ao.CFrame = chassis.CFrame.Rotation
	ao.Parent = chassis
	-- assentos: tripulação na frente, passageiros atrás
	for i, s in spec.seats do
		local off =
			Vector3.new(((i - 1) % 2 - 0.5) * W * 0.4, chassis.Size.Y / 2, -chassis.Size.Z * 0.3 + (i // 2) * 0.8 / M)
		addSeat(model, chassis, s.id, s.role, s.weapon, off)
	end
	for i = 1, Vehicles.PASSENGERS[specId] or 0 do
		local row = (i - 1) // 2
		local off =
			Vector3.new(((i - 1) % 2 - 0.5) * W * 0.5, chassis.Size.Y / 2, chassis.Size.Z * 0.05 + row * 0.7 / M)
		addSeat(model, chassis, "p" .. i, "any", nil, off)
	end
	model:SetAttribute("VehicleId", nextId)
	model:SetAttribute("Spec", specId)
	model:SetAttribute("Kind", spec.kind)
	model:SetAttribute("Faction", spec.faction)
	model:SetAttribute("Depot", depot)
	model:SetAttribute("Integrity", 100)
	model:SetAttribute("Engine", 100)
	model:SetAttribute("Tracks", 100)
	if specId == "ontos" then
		model:SetAttribute("Tubes", GUNS.rr_106.tubes)
	end
	model.Parent = folder
	return model
end

-- validação: velocidade acima da ficha (+25% e margem) devolve a posse ao servidor por 3 s
local function validate()
	for _, model in folder:GetChildren() do
		local chassis = model:FindFirstChild("Chassis") :: BasePart?
		local spec = Vehicles.SPECS[model:GetAttribute("Spec") :: string]
		if chassis and spec and not model:GetAttribute("Destroyed") then
			local v = chassis.AssemblyLinearVelocity
			local horiz = Vector3.new(v.X, 0, v.Z).Magnitude * M
			local limit = spec.maxKmh / 3.6 * 1.25 + 3
			if horiz > limit and not chassis.Anchored then
				warn("[VT65] velocidade inválida em", model.Name, horiz, "m/s")
				pcall(function()
					chassis:SetNetworkOwner(nil)
				end)
				local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
				if lv then
					lv.PlaneVelocity = Vector2.zero
					lv.VectorVelocity = Vector3.zero
				end
			end
		end
	end
end

function VehicleService.start()
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace
	Net.event("Vehicle_Fire").OnServerEvent:Connect(onFire)
	Net.event("Vehicle_Reload").OnServerEvent:Connect(onReload)
	-- foguetes do papel antitanque: 3 por vida (PLACEHOLDER)
	local function arm(player: Player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Rockets", if player:GetAttribute("Role") == "anti_tank" then 3 else 0)
		end)
	end
	for _, p in Players:GetPlayers() do
		arm(p)
	end
	Players.PlayerAdded:Connect(arm)
	task.spawn(function()
		while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
			ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
		end
		for i, d in DEPOTS do
			VehicleService.spawn(d.spec, i)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.5 then
			acc = 0
			validate()
		end
	end)
end

return VehicleService
