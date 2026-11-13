--!strict
-- Veículos da F4: M48A3, Ontos, LVTP-5 e UH-34D nos depósitos dos EUA (o VC de 1965 em Starlite não
-- tinha blindados). O motorista simula o próprio veículo (posse de rede) com Shared/VehicleDrive e
-- Shared/HeliModel; o servidor valida velocidade, assentos por papel, tiros e dano por zona.
-- Movimento (2026-11-11): a arte e os assentos ficam presos a uma peça "ArtRoot" ligada ao chassi
-- pelo Motor6D "ArtMount"; cada cliente balança a arte por ele (mola da carroceria, VehicleFx). Rampas
-- invisíveis na frente e atrás deixam a lagarta subir dique e barranco baixo. O motorista manda a
-- rotação e a carga do motor (Vehicle_Telemetry) para os outros ouvirem e verem a fumaça.
-- D-100 (pedido do dono, 2026-11-12: "por que não consigo pilotar", "coloque a interface do botão
-- para eu entrar", "faça poder atirar de dentro", "andar em todo o mapa sem bugar"):
--   - entrar só pelo painel (ProximityPrompt "VT65Embarcar" + Controllers/VehiclePrompt): o assento
--     não senta mais pelo toque (CanTouch false), e o lugar é escolhido; remote Vehicle_Board
--     (entrar, trocar, sair, desvirar) com a regra de papel de Roles e a troca de papel de campo;
--   - o lugar fica no olho medido na malha (VehicleDrive.ART): a cabeça de quem está sentado é a
--     da câmera, e quem sai é posto ao lado do veículo, fora do chassi;
--   - lugar aberto: o assento recebe a arma do ocupante ("Weapon" + "Personal") e o ângulo
--     (Arc*); a M60 e os canhões continuam montados ("Mounted");
--   - carros M151, M35 e Peugeot 403 (rodas, VehicleDrive), com substituto em peças até o modelo;
--   - preso ("Stuck") e tombado: desvirar no painel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Roles = require(ReplicatedStorage.Shared.Roles)
local VehicleDrive = require(ReplicatedStorage.Shared.VehicleDrive)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local AssetLoader = require(script.Parent.AssetLoader)
local CombatService = require(script.Parent.CombatService)
local ExplosionService = require(script.Parent.ExplosionService)
local MedicalService = require(script.Parent.MedicalService)
local SpawnService = require(script.Parent.SpawnService)

local VehicleService = {}

-- D-90: estado do bot motorista (física no servidor) e o que o BotVehicles lê dele
type BotDrive = {
	st: VehicleDrive.State,
	yaw: number?,
	pitch: number,
	roll: number,
	thr: number,
	steer: number,
	inThr: number,
	inSteer: number,
	ground: string,
	depth: number?,
	probeT: number,
	attT: number,
	telT: number,
}
export type BotDriveState = {
	v: number, -- m/s à frente
	yaw: number,
	ground: string,
	floating: boolean,
	slip: number,
	blocked: boolean,
	top: number, -- m/s: teto do chão
}
local M = MapConfig.STUD_M
local G = 9.80665
local rng = Rng.new(1965081)
local folder: Folder
local nextId = 0

-- Depósitos ao redor do QG dos EUA (posições de design, D-37), em metros a partir do QG. 6 veículos =
-- critério da F4. No mapa de 2 x 2 km (D-63) o QG fica a 50 m da borda leste e a 250 m da sul: os
-- depósitos ficam a oeste e ao norte dele (antes os LVTP-5 ficavam no mar, 140 m a leste).
-- D-100: carros dos EUA ao sul do pátio e a picape do VC ao pé do morro do QG dele (posições de
-- projeto, a conferir no Studio contra casas e árvores).
local DEPOTS = {
	{ spec = "lvtp5", dx = -60, dz = -60 },
	{ spec = "lvtp5", dx = -60, dz = -20 },
	{ spec = "m48a3", dx = -130, dz = -40 },
	{ spec = "ontos", dx = -130, dz = 0 },
	{ spec = "uh34d", dx = -20, dz = 70 },
	{ spec = "uh34d", dx = -90, dz = 70 },
	{ spec = "m151", dx = -25, dz = -100 },
	{ spec = "m151", dx = -40, dz = -100 },
	{ spec = "m35", dx = -95, dz = -100 },
	{ spec = "peugeot403", dx = 40, dz = 35 },
	{ spec = "peugeot403", dx = 55, dz = 35 },
}
-- olho de quem está sentado acima do assento (studs): o lugar fica embaixo do olho medido na malha
local EYE_ABOVE_SEAT = 3.2 -- PLACEHOLDER (soldado de 2,0 m sentado, D-98)
local PAINT: { [string]: Color3 } = {
	us = Color3.fromRGB(86, 90, 62), -- verde-oliva do USMC
	civil = Color3.fromRGB(112, 124, 128), -- cinza-azulado civil desbotado (veic_peugeot403.py)
	paint = Color3.fromRGB(86, 90, 62),
	canvas = Color3.fromRGB(98, 96, 70),
	glass = Color3.fromRGB(58, 68, 72),
	tire = Color3.fromRGB(28, 27, 25),
	wood = Color3.fromRGB(110, 92, 66),
}
local RESPAWN_S = 180 -- design
-- Giro da arte em relação ao chassi (frente do chassi = -Z). Os GLBs dos veículos têm o eixo longo
-- em X com a frente em +X, mas o importador do Roblox gira o modelo 180° em Y: no Studio (teste com a
-- arte publicada, 2026-11-10) o canhão do M48, os tubos do Ontos, a proa do LVTP-5 e o nariz do
-- UH-34D apontam para -X. O palpite antigo (+90°) punha todos andando de ré.
local ART_YAW: { [string]: number } = {
	m48a3 = math.rad(-90),
	ontos = math.rad(-90),
	lvtp5 = math.rad(-90),
	uh34d = math.rad(-90),
}

-- Armas de veículo e foguetes de infantaria (projéteis simulados no servidor).
-- v0: 106 mm M344 HEAT = 503 m/s (wiki:M40_recoilless_rifle); demais PLACEHOLDER (D-36).
local GUNS = {
	gun_90 = { explosive = "he_90", pen = "he_90", v0 = 820, reloadS = 6, launch = "gun_90" },
	-- 90 mm com munição anticarro (troca com X / tecla X): PLACEHOLDER de v0 e penetração
	gun_90_heat = { explosive = "heat_106", pen = "heat_90", v0 = 850, reloadS = 6, launch = "gun_90" },
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
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = false
		end
	end
	local spec, depot = model:GetAttribute("Spec"), model:GetAttribute("Depot")
	task.delay(30, function()
		model:Destroy()
	end)
	task.delay(RESPAWN_S, function()
		if type(spec) == "string" and type(depot) == "number" then
			-- (any): o checador antigo ordena as funções e ainda não viu o spawn aqui (D-90)
			(VehicleService :: any).spawn(spec, depot)
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

local function seatById(vehicle: Model, seatId: string): Seat?
	local s = vehicle:FindFirstChild("Seat_" .. seatId)
	return if s and s:IsA("Seat") then s else nil
end

-- Tiro da arma de um assento (jogador ou bot, D-90): a mesma validação para os dois. Devolve true
-- se o tiro saiu.
local function fireFromSeat(seat: Seat, char: Model, player: Player?, dir: Vector3, coax: boolean, now: number): boolean
	local weapon = seat:GetAttribute("Weapon")
	local model = seat:FindFirstAncestorWhichIsA("Model") :: Model
	if type(weapon) ~= "string" or model:GetAttribute("Destroyed") then
		return false
	end
	if seat:GetAttribute("Personal") == true then
		return false -- D-100: a própria arma do ocupante vai pelo CombatService (Combat_Fire)
	end
	local origin = seat.Position + Vector3.new(0, 2.5 / M, 0) + dir * (2 / M)
	-- M60 do assento (porta, cúpula) e a coaxial do atirador do M48 (RB / tecla F)
	if weapon == "m60" or (coax and weapon == "gun_90") then
		if now - (lastShot[seat :: any] or 0) < 0.09 then
			return false -- ~650 tiros/min no máximo (validação; a cadência real vem da ficha da M60)
		end
		lastShot[seat :: any] = now
		CombatService.fire(char, "m60", origin, dir, math.floor(rng:next() * 2 ^ 31), player)
		return true
	end
	if weapon == "gun_90" and model:GetAttribute("Ammo") == "heat" then
		weapon = "gun_90_heat"
	end
	local gun = GUNS[weapon]
	if not gun or now - (lastShot[seat] or 0) < gun.reloadS then
		return false
	end
	if gun.tubes then
		local left = (model:GetAttribute("Tubes") :: number?) or 0
		if left <= 0 then
			return false
		end
		model:SetAttribute("Tubes", left - 1)
	end
	lastShot[seat] = now
	shoot(gun, origin, dir, { model, char })
	return true
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
		fireFromSeat(seat, char, player, dir, req.coax == true, now)
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
local function onReload(player: Player, req: any)
	local seat = seatOf(player)
	if not seat then
		return
	end
	-- M48A3: X troca a munição do 90 mm entre explosiva (HE) e anticarro (HEAT)
	if seat:GetAttribute("Weapon") == "gun_90" and type(req) == "table" and req.op == "ammo" then
		local m = seat:FindFirstAncestorWhichIsA("Model") :: Model
		m:SetAttribute("Ammo", if m:GetAttribute("Ammo") == "heat" then "he" else "heat")
		lastShot[seat] = os.clock() -- trocar a granada na culatra leva o tempo de uma recarga
		return
	end
	if seat:GetAttribute("Weapon") ~= "rr_106" then
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

-- motor desligado: o servidor volta a simular e segura o veículo onde está (a atitude que o servidor
-- conhecia era a do nascimento: sem isto, o tanque girava de volta para o rumo do depósito)
local function hold(model: Model, chassis: BasePart)
	local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
	local ao = chassis:FindFirstChild("DriveAttitude") :: AlignOrientation?
	if lv then
		lv.PlaneVelocity = Vector2.zero
		lv.VectorVelocity = Vector3.zero
	end
	if ao then
		ao.CFrame = chassis.CFrame.Rotation
	end
	model:SetAttribute("NetRpm", 0)
	model:SetAttribute("NetLoad", 0)
	model:SetAttribute("NetRotor", 0)
end

---------------------------------------------------------------------------------------------
-- D-90: bot motorista. O servidor roda a mesma física do motorista jogador (VehicleDrive no
-- VehicleController: chão por raio, atitude pelas 4 pontas, LinearVelocity e AlignOrientation),
-- com o acelerador e o volante que o bot manda (BotVehicles). Genérico para veículo de chão: a
-- lagarta (M48A3, Ontos, LVTP-5) hoje; um carro com rodas do VC, quando existir, usa a mesma
-- entrada (a física dele é que vai ser outra). Bot não pilota o UH-34D (fica para depois, D-90).
---------------------------------------------------------------------------------------------
local botDrives: { [Model]: BotDrive } = {}

local botSolid = RaycastParams.new()
botSolid.FilterType = Enum.RaycastFilterType.Exclude
botSolid.RespectCanCollide = true
local botPaddy = RaycastParams.new()
botPaddy.FilterType = Enum.RaycastFilterType.Include
local botGroupSet = false

local function botRays(model: Model)
	if not botGroupSet then
		AssetLoader.ensureGroups()
		botGroupSet = pcall(function()
			botSolid.CollisionGroup = AssetLoader.VEHICLE_GROUP -- passa pelo tronco, como o chassi
		end)
	end
	local ex: { Instance } = { model }
	for _, name in { "Combatants", "Effects", "Granadas", "DroppedWeapons" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ex, f)
		end
	end
	botSolid.FilterDescendantsInstances = ex
end

-- Chão debaixo do chassi (como o VehicleLive.probe do cliente): chave do VehicleDrive e fundura (m)
local function botGround(chassis: BasePart): (string, number?)
	local top = chassis.Position + Vector3.new(0, chassis.Size.Y / 2, 0)
	local len = chassis.Size.Y * 1.5 + 8
	botSolid.IgnoreWater = false
	local hit = workspace:Raycast(top, Vector3.new(0, -len, 0), botSolid)
	if not hit then
		return "earth", nil
	end
	if hit.Instance == workspace.Terrain and hit.Material == Enum.Material.Water then
		botSolid.IgnoreWater = true
		local bottom = workspace:Raycast(hit.Position + Vector3.new(0, 0.05, 0), Vector3.new(0, -80, 0), botSolid)
		botSolid.IgnoreWater = false
		return "water", if bottom then (hit.Position.Y - bottom.Position.Y) * M else 30
	end
	local map = workspace:FindFirstChild("Map")
	local sheet = map and map:FindFirstChild("PaddyWater")
	if sheet then
		botPaddy.FilterDescendantsInstances = { sheet }
		if workspace:Raycast(top, Vector3.new(0, -(top.Y - hit.Position.Y) - 1, 0), botPaddy) then
			return "paddy", nil
		end
	end
	local attr = hit.Instance:GetAttribute("Material")
	return VehicleDrive.groundOf(hit.Material.Name, if type(attr) == "string" then attr else nil, hit.Instance.Name),
		nil
end

-- Atitude do chão pelas 4 pontas no rumo yaw (pitch + nariz para cima, roll + direita mais alta)
local function botAttitude(chassis: BasePart, yaw: number): (number?, number?)
	local half = Vector3.new(chassis.Size.X * 0.42, 0, chassis.Size.Z * 0.45)
	local base = CFrame.new(chassis.Position) * CFrame.Angles(0, yaw, 0)
	local hs = {}
	for i, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local p = (base * CFrame.new(c[1] * half.X, 0, c[2] * half.Z)).Position
		local r = workspace:Raycast(p + Vector3.new(0, 14, 0), Vector3.new(0, -48, 0), botSolid)
		if not r then
			return nil, nil
		end
		hs[i] = r.Position.Y
	end
	local lim = math.rad(35)
	local pitch = math.atan2(((hs[1] + hs[2]) - (hs[3] + hs[4])) / 2, half.Z * 2)
	local roll = math.atan2(((hs[2] + hs[4]) - (hs[1] + hs[3])) / 2, half.X * 2)
	return math.clamp(pitch, -lim, lim), math.clamp(roll, -lim, lim)
end

local function approachTo(x: number, target: number, tau: number, dt: number): number
	return x + (target - x) * (1 - math.exp(-dt / tau))
end

local function slewTo(x: number, target: number, rate: number, dt: number): number
	local d = target - x
	local step = rate * dt
	return if math.abs(d) <= step then target else x + (if d > 0 then step else -step)
end

local function botDriveStep(model: Model, chassis: BasePart, spec: any, d: BotDrive, dt: number)
	-- pedal e volante com curso, como o teclado do jogador
	d.thr = slewTo(d.thr, d.inThr, if math.abs(d.inThr) > math.abs(d.thr) then 3.2 else 7, dt)
	d.steer = slewTo(d.steer, d.inSteer, 4.5, dt)
	botRays(model)
	d.probeT -= dt
	if d.probeT <= 0 then
		d.probeT = 0.1
		d.ground, d.depth = botGround(chassis)
	end
	local _, cy, _ = chassis.CFrame:ToOrientation()
	local yaw = d.yaw or cy
	d.attT -= dt
	if d.attT <= 0 then
		d.attT = 0.1
		local p, r = botAttitude(chassis, yaw)
		if p and r then
			d.pitch = approachTo(d.pitch, p, 0.1, 0.1)
			d.roll = approachTo(d.roll, r, 0.1, 0.1)
		end
	end
	local rain = ReplicatedStorage:GetAttribute("Rain")
	local st = d.st
	VehicleDrive.step(spec, st, { throttle = d.thr, steer = d.steer }, {
		ground = d.ground,
		rain = if type(rain) == "number" then rain else 0,
		slopeSin = math.sin(d.pitch),
		sideSin = math.sin(d.roll),
		waterDepthM = d.depth,
		engine = ((model:GetAttribute("Engine") :: number?) or 0) / 100,
		tracks = ((model:GetAttribute("Tracks") :: number?) or 0) / 100,
	}, dt)
	local flatCF = CFrame.Angles(0, yaw, 0)
	local vel = chassis.AssemblyLinearVelocity * M
	if not st.floating then
		local measured = Vector3.new(vel.X, 0, vel.Z):Dot(flatCF.LookVector) / math.max(math.cos(d.pitch), 0.5)
		VehicleDrive.contact(st, measured, dt)
	end
	yaw += st.yawRate * dt
	d.yaw = yaw
	flatCF = CFrame.Angles(0, yaw, 0)
	local ao = chassis:FindFirstChild("DriveAttitude") :: AlignOrientation?
	local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
	if ao and lv then
		ao.CFrame = flatCF * CFrame.Angles(d.pitch, 0, d.roll)
		local hv = flatCF.LookVector * st.v * math.cos(d.pitch) + flatCF.RightVector * st.vLat
		lv.PlaneVelocity = Vector2.new(hv.X, hv.Z) / M
	end
	-- motor para os outros ouvirem (como a telemetria do jogador, ~6 por segundo)
	d.telT -= dt
	if d.telT <= 0 then
		d.telT = 1 / 6
		local function q(v: number): number
			return math.floor(math.clamp(v, 0, 1) * 20 + 0.5) / 20
		end
		local r, l = q(st.rpm), q(st.load)
		if model:GetAttribute("NetRpm") ~= r then
			model:SetAttribute("NetRpm", r)
		end
		if model:GetAttribute("NetLoad") ~= l then
			model:SetAttribute("NetLoad", l)
		end
	end
end

local function newBotDrive(chassis: BasePart): BotDrive
	local _, cy, _ = chassis.CFrame:ToOrientation()
	return {
		st = VehicleDrive.newState(),
		yaw = cy,
		pitch = 0,
		roll = 0,
		thr = 0,
		steer = 0,
		inThr = 0,
		inSteer = 0,
		ground = "earth",
		depth = nil,
		probeT = 0,
		attT = 0,
		telT = 0,
	}
end

local function isBot(hum: Humanoid?): boolean
	local c = hum and hum.Parent
	return c ~= nil and c:GetAttribute("Bot") == true
end

-- ===== D-100: sair para fora do chassi =====
-- O lugar fica embaixo do olho medido na malha (dentro do casco no motorista e no atirador); quem
-- sai é posto ao lado, no chão, do lado que estiver livre (esquerda, direita, atrás).
local outParams = RaycastParams.new()
outParams.FilterType = Enum.RaycastFilterType.Exclude
outParams.RespectCanCollide = true

local function placeOutside(char: Model, model: Model)
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (chassis and root) or not char.Parent then
		return
	end
	outParams.FilterDescendantsInstances = { model, char }
	local size = chassis.Size
	local cf = chassis.CFrame
	local bottom = (cf * Vector3.new(0, -size.Y / 2, 0)).Y
	local spots = {
		Vector3.new(-(size.X / 2 + 1.3 / M), 0, 0),
		Vector3.new(size.X / 2 + 1.3 / M, 0, 0),
		Vector3.new(0, 0, size.Z / 2 + 2.2 / M),
		Vector3.new(0, 0, -(size.Z / 2 + 2.2 / M)),
	}
	for _, off in spots do
		local p = cf * off
		local top = math.max(p.Y, bottom) + size.Y + 6
		local hit = workspace:Raycast(Vector3.new(p.X, top, p.Z), Vector3.new(0, -(size.Y + 60), 0), outParams)
		-- algo sólido acima do chão neste ponto (casa, outro veículo): tenta o próximo
		local y = if hit then hit.Position.Y else bottom
		if hit and hit.Position.Y > bottom + 2.5 / M then
			continue
		end
		-- helicóptero no ar: salta da altura da porta
		if y < bottom - 4 / M then
			y = bottom
		end
		local face = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		local at = Vector3.new(p.X, y + 3.2, p.Z)
		char:PivotTo(CFrame.lookAt(at, at + (if face.Magnitude > 0.1 then face else Vector3.zAxis)))
		root.AssemblyLinearVelocity = Vector3.zero
		return
	end
	char:PivotTo(CFrame.new(cf.Position + Vector3.new(0, size.Y + 4, 0)))
end

-- arma principal do jogador (a que o CombatService conhece): a pega do chão ou a 1ª do equipamento
local function personalWeapon(player: Player): string?
	local carried = player:GetAttribute("CarriedWeapon")
	if type(carried) == "string" and carried ~= "" then
		return carried
	end
	local lo = player:GetAttribute("Loadout")
	local first = if type(lo) == "string" then string.split(lo, ",")[1] else nil
	return if first and first ~= "" then first else nil
end

local switching: { [Player]: boolean } = {} -- trocando de lugar pelo servidor: não põe para fora
local lastOcc: { [Seat]: Humanoid? } = {}

local function addSeat(model: Model, chassis: BasePart, mount: BasePart, info: Vehicles.SeatInfo, cf: CFrame)
	local id = info.id
	local kind = tostring(model:GetAttribute("Kind"))
	local s = Instance.new("Seat")
	s.Name = "Seat_" .. id
	s.Size = Vector3.new(0.5, 0.2, 0.5) / M
	s.Transparency = 1
	s.CanCollide = false
	s.CanTouch = false -- D-100: ninguém senta pelo toque (caía no lugar que encostasse); só o painel
	s.Massless = true
	s.CFrame = cf
	s:SetAttribute("SeatId", id)
	s:SetAttribute("Label", info.label)
	s:SetAttribute("Role", info.role or "any")
	if info.weapon then
		s:SetAttribute("Weapon", info.weapon)
		s:SetAttribute("Mounted", true)
	end
	local arc = info.open
	if arc then
		s:SetAttribute("Open", true)
		s:SetAttribute("ArcYaw", arc.yaw)
		s:SetAttribute("ArcHalf", arc.half)
		s:SetAttribute("ArcDown", arc.down)
		s:SetAttribute("ArcUp", arc.up)
	end
	-- preso à arte: quem está sentado balança com a carroceria
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = mount, s
	w.Parent = s
	s.Parent = model
	s:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = s.Occupant
		local player = hum and Players:GetPlayerFromCharacter(hum.Parent)
		-- saiu: a arma do ocupante sai do lugar, e quem saiu vai para fora do chassi
		local prev = lastOcc[s]
		lastOcc[s] = hum
		if not hum then
			if s:GetAttribute("Personal") then
				s:SetAttribute("Weapon", nil)
				s:SetAttribute("Personal", nil)
			end
			local pp = prev and Players:GetPlayerFromCharacter(prev.Parent)
			if prev and pp and prev.Health > 0 and not switching[pp] then
				task.delay(0.05, function()
					local char = prev.Parent
					if prev.SeatPart == nil and char and char:IsA("Model") then
						placeOutside(char, model)
					end
				end)
			end
		end
		-- bot (D-90): só do lado do veículo (os blindados são dos EUA); não pilota helicóptero
		local bot = hum ~= nil and player == nil and isBot(hum)
		if bot and hum then
			local okBot = (hum.Parent :: Instance):GetAttribute("Faction") == model:GetAttribute("Faction")
				and not (id == "driver" and kind == "heli")
			if not okBot then
				task.defer(function()
					hum.Sit = false
				end)
				return
			end
		end
		if hum and player then
			-- D-100: a regra de papel de Roles, com o papel de campo (VehicleCrew)
			local crew = player:GetAttribute("VehicleCrew")
			local role = player:GetAttribute("Role")
			local okRole = Roles.canTakeSeat(
				kind,
				id,
				if type(role) == "string" then role else nil,
				if type(crew) == "string" then crew else nil
			)
			local ok = player:GetAttribute("Faction") == model:GetAttribute("Faction") and okRole
			if not ok then
				task.defer(function()
					hum.Sit = false
				end)
				return
			end
			if arc and not info.weapon then
				local wpn = personalWeapon(player)
				s:SetAttribute("Weapon", wpn)
				s:SetAttribute("Personal", if wpn then true else nil)
			end
		end
		if id == "driver" then
			-- helicóptero sem piloto não fica parado no ar: solta o controle e a gravidade age
			local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
			if lv and model:GetAttribute("Kind") == "heli" then
				lv.Enabled = player ~= nil
			end
			model:SetAttribute(
				"EngineOn",
				(player ~= nil or bot) and ((model:GetAttribute("Engine") :: number?) or 0) > 0
			)
			if player then
				botDrives[model] = nil
				pcall(function()
					chassis:SetNetworkOwner(player)
				end)
			elseif bot then
				-- bot motorista: o servidor simula (posse do servidor)
				pcall(function()
					chassis:SetNetworkOwner(nil)
				end)
				botDrives[model] = newBotDrive(chassis)
			else
				botDrives[model] = nil
				hold(model, chassis)
				pcall(function()
					chassis:SetNetworkOwner(nil)
				end)
			end
		end
	end)
end

-- maior peça da arte (a malha do ForgeGUI)
local function mainPart(art: Instance): BasePart?
	local best: BasePart? = nil
	local bestV = 0
	for _, p in art:GetDescendants() do
		if p:IsA("BasePart") then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > bestV then
				best, bestV = p, v
			end
		end
	end
	return best
end

-- Rampas invisíveis na frente e atrás da lagarta: degrau que ela sobe (dique, barranco baixo).
-- 0,6 m: PLACEHOLDER (a ficha do M48 não traz o obstáculo vertical). D-100: o carro sobe o que a
-- roda dele sobe (VehicleDrive.DRIVE[id].stepM).
local RAMP_L = 1.6

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = b
end

-- Roda presa à ArtRoot por Motor6D (o VehicleFx gira e esterça pelo Transform): a junta fica no
-- centro da roda, com os eixos do chassi (X = eixo da roda).
local function wheelJoint(mount: BasePart, chassis: BasePart, part: BasePart)
	local joint = CFrame.new(part.Position) * chassis.CFrame.Rotation
	local m6 = Instance.new("Motor6D")
	m6.Name = part.Name
	m6.Part0, m6.Part1 = mount, part
	m6.C0 = mount.CFrame:ToObjectSpace(joint)
	m6.C1 = part.CFrame:ToObjectSpace(joint)
	m6.Parent = mount
end

local function artPart(name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	return p
end

-- D-100: substituto em peças do carro (até o dono publicar o modelo do Blender): caixas do corpo
-- e as rodas com o nome das peças do modelo. Tudo no referencial do chassi a partir do chão.
local function placeholderCar(specId: string, chassis: BasePart, mount: BasePart): Model?
	local wd = Vehicles.WHEELED[specId]
	if not wd then
		return nil
	end
	local art = Instance.new("Model")
	art.Name = "Art"
	local base = mount.CFrame -- centro do chassi, no chão
	local paint = PAINT[wd.color] or PAINT.us
	for _, b in wd.body do
		local c = if b.color == "paint" or b.color == "civil" or b.color == "us" then paint else PAINT[b.color] or paint
		local p = artPart(
			b.name,
			Vector3.new(b.size[1], b.size[2], b.size[3]) / M,
			base * CFrame.new(b.at[1] / M, b.at[2] / M, b.at[3] / M),
			c
		)
		if b.color == "glass" then
			p.Transparency = 0.55
		elseif b.color == "canvas" then
			p.Material = Enum.Material.Fabric
		end
		p.Parent = art
		weld(mount, p)
	end
	for _, w in wd.wheels do
		local p = artPart(
			w.name,
			Vector3.new(wd.wheelW, 2 * wd.wheelR, 2 * wd.wheelR) / M,
			base * CFrame.new(w.x / M, wd.wheelR / M, w.z / M),
			PAINT.tire
		)
		p.Shape = Enum.PartType.Cylinder -- o eixo do cilindro é o X da peça (= eixo da roda)
		p.Parent = art
		wheelJoint(mount, chassis, p)
	end
	art.Parent = chassis.Parent
	return art
end

-- Onde fica cada lugar (CFrame no mundo, na hora do nascimento). Com a arte medida: embaixo do olho
-- (VehicleDrive.eyeOf, o mesmo da câmera). Carro: a posição do Blender (Vehicles.WHEELED). Sem nada:
-- a grade antiga em cima do chassi.
local function seatCFrame(
	specId: string,
	info: Vehicles.SeatInfo,
	k: number,
	chassis: BasePart,
	mount: BasePart,
	mesh: BasePart?
): CFrame
	local rot = chassis.CFrame.Rotation
	local at = Vehicles.wheeledSeatAt(specId, info.id)
	if at then
		return mount.CFrame * CFrame.new(at[1] / M, at[2] / M, at[3] / M)
	end
	local art = VehicleDrive.ART[specId]
	local ex, ey, ez = VehicleDrive.eyeOf(specId, info.id)
	if mesh and art and ex and ey and ez then
		local box = art.box
		local s = mesh.Size / Vector3.new(box[1], box[2], box[3])
		local eye = mesh.CFrame * Vector3.new(ex * s.X, ey * s.Y, ez * s.Z)
		return CFrame.new(eye - Vector3.new(0, EYE_ABOVE_SEAT, 0)) * rot
	end
	local W = chassis.Size.X
	local nSeats = #(Vehicles.SPECS[specId] :: any).seats
	if k <= nSeats then
		local off =
			Vector3.new(((k - 1) % 2 - 0.5) * W * 0.4, chassis.Size.Y / 2, -chassis.Size.Z * 0.3 + (k // 2) * 0.8 / M)
		return chassis.CFrame * CFrame.new(off)
	end
	local i = k - nSeats
	local row = (i - 1) // 2
	local off = Vector3.new(((i - 1) % 2 - 0.5) * W * 0.5, chassis.Size.Y / 2, chassis.Size.Z * 0.05 + row * 0.7 / M)
	return chassis.CFrame * CFrame.new(off)
end

-- Monta o veículo em `at` (chão sob o centro), virado para `yaw`. depot: para renascer (nil = teste).
local function build(specId: string, at: Vector3, yaw: number, depot: number?): Model?
	local spec = Vehicles.SPECS[specId]
	if not spec then
		return nil
	end
	nextId += 1
	local x, z = at.X, at.Z
	local L, W, H = spec.lengthM / M, spec.widthM / M, spec.heightM / M
	local heli = spec.kind == "heli"
	local wheeled = spec.kind == "wheeled"
	local drive = VehicleDrive.DRIVE[specId]
	local rampH = ((drive and drive.stepM) or 0.6) / M
	local tpl = AssetLoader.template(specId)
	local info = VehicleDrive.ART[specId]
	-- Comprimento do chassi: o do laço da lagarta medido na malha (o canhão do M48 passa muito da
	-- frente; a caixa antes ficava 1 m adiante do casco), menos as rampas. Sem arte: 75% da ficha.
	-- Carro: o comprimento todo menos as rampas.
	local length = if heli then L * 0.8 elseif wheeled then L - 2 * RAMP_L else L * 0.75
	local hullCenter = 0 -- x da malha que vai para o centro do chassi
	local tplMesh = if tpl then mainPart(tpl) else nil
	if not heli and tplMesh and info and info.track then
		local sx = tplMesh.Size.X / info.box[1]
		local lo, hi = math.huge, -math.huge
		for _, c in info.track.circles do
			lo = math.min(lo, c[1] - c[3])
			hi = math.max(hi, c[1] + c[3])
		end
		length = (hi - lo) * sx - 2 * RAMP_L
		hullCenter = (lo + hi) / 2 * sx
	end
	local model = Instance.new("Model")
	model.Name = spec.name
	-- o veículo entra e sai do streaming inteiro (o cliente nunca vê chassi sem arte)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(if wheeled then W * 0.95 else W, H * 0.55, length)
	chassis.Color = Color3.fromRGB(86, 90, 62)
	chassis.Material = Enum.Material.Metal
	-- densidade < 1 boia na água do terreno: só o anfíbio (e o helicóptero, que não pousa na água).
	-- O M48 e o Ontos afundam e atolam no riacho fundo em vez de flutuar; o carro também afunda.
	local density = if spec.kind == "tracked" or wheeled then 1.6 else 0.7
	chassis.CustomPhysicalProperties = PhysicalProperties.new(density, 0.6, 0.1)
	chassis.CFrame = CFrame.new(x, SpawnService.groundY(x, z) + chassis.Size.Y / 2 + 1, z) * CFrame.Angles(0, yaw, 0)
	-- passa pelo tronco das árvores da mata (D-67): o tronco só segura gente e bala
	AssetLoader.ensureGroups()
	chassis.CollisionGroup = AssetLoader.VEHICLE_GROUP
	chassis.Parent = model
	model.PrimaryPart = chassis
	if not heli then
		for _, sgn in { -1, 1 } do
			local r = Instance.new("WedgePart")
			r.Name = if sgn < 0 then "RampFront" else "RampRear"
			r.Size = Vector3.new(W * 0.95, rampH, RAMP_L)
			-- frente: rampa virada (alta na ponta, baixa junto ao chassi); atrás, o espelho
			local turn = if sgn < 0
				then CFrame.Angles(0, 0, math.pi)
				else CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, math.pi)
			r.CFrame = chassis.CFrame
				* CFrame.new(0, -chassis.Size.Y / 2 + rampH / 2, sgn * (chassis.Size.Z / 2 + RAMP_L / 2))
				* turn
			r.Transparency = 1
			r.Massless = true
			r.CanTouch = false
			r.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.2, 0)
			r.CollisionGroup = AssetLoader.VEHICLE_GROUP
			weld(chassis, r)
			r.Parent = model
		end
	end
	-- ArtRoot: a arte e os assentos ficam presos a ela; o cliente balança pelo Motor6D (mola visual)
	local mount = Instance.new("Part")
	mount.Name = "ArtRoot"
	mount.Size = Vector3.one * 0.2
	mount.Transparency = 1
	mount.CanCollide = false
	mount.CanQuery = false
	mount.CanTouch = false
	mount.Massless = true
	mount.CollisionGroup = AssetLoader.VEHICLE_GROUP
	mount.CFrame = chassis.CFrame * CFrame.new(0, if heli then 0 else -chassis.Size.Y / 2, 0)
	mount.Parent = model
	local motor = Instance.new("Motor6D")
	motor.Name = "ArtMount"
	motor.Part0, motor.Part1 = chassis, mount
	motor.C0 = chassis.CFrame:ToObjectSpace(mount.CFrame)
	motor.Parent = chassis
	-- arte do ForgeGUI/Blender (se publicada): presa à ArtRoot, sem colisão; o chassi vira invisível
	local mesh: BasePart? = nil
	local wheelNames: { [string]: boolean } = {}
	local wheeledArt = Vehicles.WHEELED[specId]
	if wheeledArt then
		for _, wh in wheeledArt.wheels do
			wheelNames[wh.name] = true
		end
	end
	if tpl then
		local art = tpl:Clone()
		art.Name = "Art"
		local artYaw = if Vehicles.WHEELED[specId]
			then math.rad(Vehicles.WHEELED[specId].artYawDeg)
			else ART_YAW[specId] or 0
		-- pela caixa (não pelo pivô, que pode estar na base): fundo da arte no fundo do chassi
		local boxCF, size = art:GetBoundingBox()
		local pivotInBox = boxCF:ToObjectSpace(art:GetPivot())
		art:PivotTo(
			chassis.CFrame
				* CFrame.new(0, -chassis.Size.Y / 2 + size.Y / 2, 0)
				* CFrame.Angles(0, artYaw, 0)
				* pivotInBox
		)
		mesh = mainPart(art)
		if mesh and hullCenter ~= 0 then
			local shift = (mesh :: BasePart).CFrame:VectorToWorldSpace(Vector3.new(hullCenter, 0, 0))
			art:PivotTo(CFrame.new(-shift) * art:GetPivot())
		end
		for _, p in art:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = false
				p.Massless = true
				if wheelNames[p.Name] then
					wheelJoint(mount, chassis, p) -- roda do modelo: gira e esterça (VehicleFx)
				else
					weld(mount, p)
				end
			end
		end
		art.Parent = model
		chassis.Transparency = 1
	elseif wheeled and placeholderCar(specId, chassis, mount) then
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
	-- os atributos antes dos assentos: o assento lê o tipo na hora de checar o papel
	model:SetAttribute("VehicleId", nextId)
	model:SetAttribute("Spec", specId)
	model:SetAttribute("Kind", spec.kind)
	model:SetAttribute("Faction", spec.faction)
	model:SetAttribute("Depot", depot)
	-- assentos (D-100: embaixo do olho medido na malha; carro, pela posição do Blender)
	for k, s in Vehicles.seatList(specId) do
		addSeat(model, chassis, mount, s, seatCFrame(specId, s, k, chassis, mount, mesh))
	end
	-- D-100: painel de entrar (Controllers/VehiclePrompt desenha; o servidor só valida o pedido)
	local pa = Instance.new("Attachment")
	pa.Name = "Embarque"
	pa.Position = Vector3.new(0, chassis.Size.Y / 2, 0)
	pa.Parent = chassis
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "VT65Embarcar"
	pp.ActionText = "Entrar"
	pp.ObjectText = spec.name
	pp.HoldDuration = 0.4 -- o toque curto de X é recarregar (InfantryController)
	pp.MaxActivationDistance = math.max(chassis.Size.X, chassis.Size.Z) / 2 + 3 / M
	pp.RequiresLineOfSight = false
	pp.Style = Enum.ProximityPromptStyle.Custom
	pp.KeyboardKeyCode = Enum.KeyCode.F
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pp.Parent = pa
	model:SetAttribute("Integrity", 100)
	model:SetAttribute("Engine", 100)
	model:SetAttribute("Tracks", 100)
	model:SetAttribute("EngineOn", false)
	model:SetAttribute("NetRpm", 0)
	model:SetAttribute("NetLoad", 0)
	model:GetAttributeChangedSignal("Engine"):Connect(function()
		if ((model:GetAttribute("Engine") :: number?) or 0) <= 0 then
			model:SetAttribute("EngineOn", false)
		end
	end)
	if specId == "ontos" then
		model:SetAttribute("Tubes", GUNS.rr_106.tubes)
	elseif specId == "m48a3" then
		model:SetAttribute("Ammo", "he")
	end
	model.Parent = folder
	return model
end

function VehicleService.spawn(specId: string, depot: number): Model?
	local d = DEPOTS[depot]
	local spec = Vehicles.SPECS[specId]
	if not spec or not d then
		return nil
	end
	local hq = MapConfig.HQ[spec.faction] or MapConfig.HQ.US
	return build(specId, Vector3.new(hq.x + d.dx / M, 0, hq.z + d.dz / M), 0, depot)
end

-- Veículo de teste fora dos depósitos (ganchos do Studio): não renasce
function VehicleService.spawnAt(specId: string, at: Vector3, yaw: number): Model?
	return build(specId, at, yaw, nil)
end

-- Rotação (0..1), carga (0..1) e rotor (0..1) que o motorista manda ~6 vezes por segundo: viram
-- atributos do veículo para todo mundo ouvir o motor e ver a fumaça (o servidor só confere e arredonda).
local lastTelemetry: { [Player]: number } = {}
local function onTelemetry(player: Player, msg: any)
	local now = os.clock()
	if now - (lastTelemetry[player] or 0) < 0.1 or type(msg) ~= "table" then
		return
	end
	lastTelemetry[player] = now
	local seat = seatOf(player)
	if not seat or seat:GetAttribute("SeatId") ~= "driver" then
		return
	end
	local model = seat:FindFirstAncestorWhichIsA("Model")
	if not model or not model:GetAttribute("VehicleId") or model:GetAttribute("Destroyed") then
		return
	end
	local function q(v: any): number?
		if type(v) ~= "number" or v ~= v then
			return nil
		end
		return math.floor(math.clamp(v, 0, 1) * 20 + 0.5) / 20
	end
	local attrs: { [string]: string } = { r = "NetRpm", l = "NetLoad", w = "NetRotor" }
	for key, attr in attrs do
		local v = q(msg[key])
		if v and model:GetAttribute(attr) ~= v then
			model:SetAttribute(attr, v)
		end
	end
end

-- ===== D-100: entrar, trocar de lugar, sair e desvirar (remote Vehicle_Board) =====
local function notice(player: Player, msg: string)
	Net.event("Vehicle_Notice"):FireClient(player, msg)
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- alcance do painel: a caixa do chassi mais 5 m (o prompt abre a 3 m da caixa)
local function reachOf(chassis: BasePart): number
	return math.max(chassis.Size.X, chassis.Size.Z) / 2 + 5 / M
end

-- Há vaga para mais um com o papel no lado? (lugares que pedem o papel contra quem já tem)
local function crewVacancy(faction: string, role: string): boolean
	local seats = 0
	for _, m in folder:GetChildren() do
		if m:GetAttribute("Faction") == faction and not m:GetAttribute("Destroyed") then
			for _, s in m:GetChildren() do
				if s:IsA("Seat") and s:GetAttribute("Role") == role then
					seats += 1
				end
			end
		end
	end
	local holders = 0
	for _, p in Players:GetPlayers() do
		if
			p:GetAttribute("Faction") == faction
			and (p:GetAttribute("Role") == role or p:GetAttribute("VehicleCrew") == role)
		then
			holders += 1
		end
	end
	return Roles.crewVacancy(seats, holders)
end

local function sitIn(player: Player, char: Model, hum: Humanoid, seat: Seat)
	switching[player] = true
	local cur = hum.SeatPart
	hum.Sit = false
	local w = cur and cur:FindFirstChild("SeatWeld")
	if w then
		w:Destroy()
	end
	task.wait()
	char:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	seat:Sit(hum)
	task.delay(0.4, function()
		switching[player] = nil
	end)
end

local recoverAt: { [Model]: number } = {}
local function recover(player: Player, model: Model, char: Model)
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (chassis and root) or model:GetAttribute("Destroyed") then
		return
	end
	local seat = seatOf(player)
	local inside = seat ~= nil and seat:FindFirstAncestorWhichIsA("Model") == model
	if player:GetAttribute("Faction") ~= model:GetAttribute("Faction") then
		return
	end
	if not inside and flatDist(root.Position, chassis.Position) > reachOf(chassis) then
		notice(player, "Longe demais")
		return
	end
	local now = os.clock()
	local speed = chassis.AssemblyLinearVelocity.Magnitude * M
	local ok, why = Vehicles.canRecover(
		chassis.CFrame.UpVector.Y,
		speed,
		model:GetAttribute("Stuck") == true,
		now - (recoverAt[model] or -1e9)
	)
	if not ok then
		notice(player, why)
		return
	end
	recoverAt[model] = now
	local driverSeat = seatById(model, "driver")
	local occ = driverSeat and driverSeat.Occupant
	local driver = occ and Players:GetPlayerFromCharacter(occ.Parent)
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	local look = chassis.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(chassis.CFrame.UpVector.X, 0, chassis.CFrame.UpVector.Z)
	end
	local yaw = if flat.Magnitude > 1e-3 then math.atan2(-flat.X, -flat.Z) else 0
	local p = chassis.Position
	local ground = SpawnService.groundY(p.X, p.Z)
	local y = math.max(p.Y, ground + chassis.Size.Y / 2) + Vehicles.RECOVER.liftM / M
	local cf = CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, yaw, 0)
	model:PivotTo(cf)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	local ao = chassis:FindFirstChild("DriveAttitude") :: AlignOrientation?
	if ao then
		ao.CFrame = cf.Rotation
	end
	local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
	if lv then
		lv.PlaneVelocity = Vector2.zero
		lv.VectorVelocity = Vector3.zero
	end
	model:SetAttribute("Stuck", nil)
	-- o motorista zera o rumo e a velocidade guardados (VehicleController)
	model:SetAttribute("Recovered", ((model:GetAttribute("Recovered") :: number?) or 0) + 1)
	task.delay(0.6, function()
		local o = driverSeat and driverSeat.Occupant
		if driver and o and o.Parent == driver.Character then
			pcall(function()
				chassis:SetNetworkOwner(driver)
			end)
		end
	end)
	notice(player, "Veículo desvirado")
end

local boardAt: { [Player]: number } = {}
local function onBoard(player: Player, req: any)
	if type(req) ~= "table" then
		return
	end
	local now = os.clock()
	if now - (boardAt[player] or 0) < 0.3 then
		return
	end
	boardAt[player] = now
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) then
		return
	end
	local cur = seatOf(player)
	if req.op == "exit" then
		if cur then
			hum.Sit = false -- o Occupant põe para fora do chassi (addSeat)
			local w = cur:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
		end
		return
	end
	local model = req.v
	if typeof(model) ~= "Instance" or not model:IsA("Model") or model.Parent ~= folder then
		return
	end
	if req.op == "recover" then
		recover(player, model, char)
		return
	end
	local seatId = req.seat
	local spec = Vehicles.SPECS[tostring(model:GetAttribute("Spec"))]
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	if type(seatId) ~= "string" or not (spec and chassis) then
		return
	end
	local seat = seatById(model, seatId)
	local inThis = cur ~= nil and cur:FindFirstAncestorWhichIsA("Model") == model
	local role = player:GetAttribute("Role")
	local crew = player:GetAttribute("VehicleCrew")
	local need = Roles.vehicleSeatRole(spec.kind, seatId)
	local faction = tostring(player:GetAttribute("Faction"))
	local verdict, missing = Vehicles.boardCheck({
		sameFaction = faction == model:GetAttribute("Faction"),
		destroyed = model:GetAttribute("Destroyed") == true,
		alive = hum.Health > 0 and char:GetAttribute("Downed") ~= true,
		near = inThis or flatDist(root.Position, chassis.Position) <= reachOf(chassis),
		inOther = cur ~= nil and not inThis,
		seatExists = seat ~= nil and not (seat :: Seat).Disabled,
		seatFree = seat ~= nil and ((seat :: Seat).Occupant == nil or (seat :: Seat).Occupant == hum),
		kind = spec.kind,
		seatId = seatId,
		role = if type(role) == "string" then role else nil,
		crewRole = if type(crew) == "string" then crew else nil,
		wantCrew = req.crew == true,
		vacancy = need == nil or crewVacancy(faction, need),
	})
	if verdict ~= "ok" and verdict ~= "crew" then
		notice(player, verdict)
		return
	end
	if verdict == "crew" and missing then
		player:SetAttribute("VehicleCrew", missing) -- papel de campo até morrer (Roles)
		notice(
			player,
			string.format("Você agora é %s neste combate", string.lower(Roles.CREW_NAME[missing] or missing))
		)
	end
	local s = seat :: Seat
	if s.Occupant == hum then
		return
	end
	sitIn(player, char, hum, s)
end

-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevDrive", "m48a3") senta o primeiro
-- jogador no motorista do veículo mais perto com essa ficha ("ontos", "lvtp5", "uh34d", "m151",
-- "m35", "peugeot403"); sem nenhum livre, faz um a 12 m à frente do jogador. "sair" tira. Põe a
-- facção do veículo e o papel de campo que o lugar pede.
local function devDrive()
	local want = workspace:GetAttribute("VT65DevDrive")
	if type(want) ~= "string" then
		return
	end
	workspace:SetAttribute("VT65DevDrive", nil)
	local player = Players:GetPlayers()[1]
	if not player then
		warn("[VT65 TESTE] VT65DevDrive: nenhum jogador")
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if want == "sair" then
		if hum then
			hum.Sit = false
		end
		return
	end
	local spec = Vehicles.SPECS[want]
	if not spec then
		warn("[VT65 TESTE] VT65DevDrive: ficha desconhecida", want)
		return
	end
	if not (char and hum and hum.Health > 0) then
		player:LoadCharacter()
		char = player.Character or player.CharacterAdded:Wait()
		hum = (char :: Model):WaitForChild("Humanoid", 10) :: Humanoid?
	end
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) then
		warn("[VT65 TESTE] VT65DevDrive: sem personagem")
		return
	end
	local best: Seat? = nil
	local bestD = math.huge
	for _, m in folder:GetChildren() do
		local seat = m:FindFirstChild("Seat_driver")
		if
			m:GetAttribute("Spec") == want
			and not m:GetAttribute("Destroyed")
			and seat
			and seat:IsA("Seat")
			and (seat.Occupant == nil or seat.Occupant == hum)
		then
			local dd = (seat.Position - root.Position).Magnitude
			if dd < bestD then
				best, bestD = seat, dd
			end
		end
	end
	if not best then
		local r = root :: BasePart
		local look = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z)
		local m = VehicleService.spawnAt(want, r.Position + look.Unit * (12 / M), math.atan2(-look.X, -look.Z))
		local seat = m and m:FindFirstChild("Seat_driver")
		best = if seat and seat:IsA("Seat") then seat else nil
		task.wait(0.2)
	end
	if not best then
		warn("[VT65 TESTE] VT65DevDrive: nenhum", want, "livre")
		return
	end
	player:SetAttribute("Faction", spec.faction)
	local need = Roles.vehicleSeatRole(spec.kind, "driver")
	if need then
		player:SetAttribute("VehicleCrew", need)
	end
	sitIn(player, char :: Model, hum :: Humanoid, best :: Seat)
	print("[VT65 TESTE] VT65DevDrive:", player.Name, "no motorista de", spec.name)
end

-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevVeh", X), sem sentar ninguém:
--   "m151" (ou outra ficha) faz o veículo 12 m à frente do primeiro jogador; "todos" faz um de cada
--   numa fila; "tombar" deita de lado o veículo mais perto (para testar o desvirar).
local function devVeh()
	local want = workspace:GetAttribute("VT65DevVeh")
	if type(want) ~= "string" then
		return
	end
	workspace:SetAttribute("VT65DevVeh", nil)
	local player = Players:GetPlayers()[1]
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		warn("[VT65 TESTE] VT65DevVeh: jogador sem personagem em campo")
		return
	end
	local r = root :: BasePart
	local look = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z).Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	local yaw = math.atan2(-look.X, -look.Z)
	if want == "tombar" then
		local best: Model? = nil
		local bestD = math.huge
		for _, m in folder:GetChildren() do
			local ch = m:FindFirstChild("Chassis") :: BasePart?
			if m:IsA("Model") and ch and not m:GetAttribute("Destroyed") then
				local d = flatDist(ch.Position, r.Position)
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
		if best then
			local ch = best:FindFirstChild("Chassis") :: BasePart
			pcall(function()
				ch:SetNetworkOwner(nil)
			end)
			local cf = ch.CFrame * CFrame.Angles(0, 0, math.rad(100))
			best:PivotTo(cf + Vector3.new(0, ch.Size.X / 2, 0))
			local ao = ch:FindFirstChild("DriveAttitude") :: AlignOrientation?
			if ao then
				ao.CFrame = cf.Rotation
			end
			print("[VT65 TESTE] VT65DevVeh: tombado", best.Name)
		end
		return
	end
	local list: { string } = {}
	if want == "todos" then
		for _, id in { "m151", "m35", "peugeot403", "m48a3", "ontos", "lvtp5", "uh34d" } do
			table.insert(list, id)
		end
	elseif Vehicles.SPECS[want] then
		table.insert(list, want)
	else
		warn("[VT65 TESTE] VT65DevVeh: ficha desconhecida", want)
		return
	end
	local x = 0
	for i, id in list do
		local spec = Vehicles.SPECS[id]
		local half = spec.widthM / M / 2
		if i > 1 then
			x += half + 4 / M
		end
		local at = r.Position + look * (14 / M) + right * x
		VehicleService.spawnAt(id, at, yaw)
		print("[VT65 TESTE] VT65DevVeh:", spec.name, "à frente do jogador")
		x += half
		task.wait(0.1)
	end
end

-- validação: velocidade acima da ficha (+25% e margem) devolve a posse ao servidor por 3 s.
-- D-100: preso = motor acelerando (rotação alta) e parado por 3 s; libera o "desvirar" no painel.
local stuckT: { [Instance]: number } = {}
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
			local rpm = model:GetAttribute("NetRpm")
			local pushing = model:GetAttribute("EngineOn") == true and type(rpm) == "number" and rpm >= 0.6
			local t = if pushing and horiz < 0.4 and spec.kind ~= "heli" then (stuckT[model] or 0) + 0.5 else 0
			stuckT[model] = t
			local stuck = t >= Vehicles.RECOVER.stuckS
			if (model:GetAttribute("Stuck") == true) ~= stuck then
				model:SetAttribute("Stuck", if stuck then true else nil)
			end
		end
	end
	for m in stuckT do
		if m.Parent ~= folder then
			stuckT[m] = nil
		end
	end
end

---------------------------------------------------------------------------------------------
-- D-90: API dos bots (BotVehicles). Entradas do motorista e do atirador no servidor.
---------------------------------------------------------------------------------------------

-- Veículos inteiros (não destruídos)
function VehicleService.vehicles(): { Model }
	local out: { Model } = {}
	local list: { Instance } = if folder then folder:GetChildren() else {}
	for _, m in list do
		if m:IsA("Model") and not m:GetAttribute("Destroyed") then
			table.insert(out, m)
		end
	end
	return out
end

-- Lugar pelo id (API dos bots). D-100: nos carros (botDrive = false) o motorista e o atirador não
-- aparecem para os bots: o BotDriver foi feito para lagarta (gira no lugar) e o carro não gira parado.
function VehicleService.seat(vehicle: Model, seatId: string): Seat?
	local spec = Vehicles.SPECS[tostring(vehicle:GetAttribute("Spec"))]
	if spec and spec.botDrive == false and (seatId == "driver" or seatId == "gunner") then
		return nil
	end
	return seatById(vehicle, seatId)
end

-- Senta o bot no assento (só do lado do veículo; motorista de helicóptero não). true se sentou.
function VehicleService.botBoard(vehicle: Model, botModel: Model, seatId: string): boolean
	if vehicle:GetAttribute("Destroyed") or vehicle.Parent ~= folder then
		return false
	end
	if botModel:GetAttribute("Bot") ~= true or botModel:GetAttribute("Faction") ~= vehicle:GetAttribute("Faction") then
		return false
	end
	if seatId == "driver" and vehicle:GetAttribute("Kind") == "heli" then
		return false
	end
	local seat = seatById(vehicle, seatId)
	local hum = botModel:FindFirstChildOfClass("Humanoid")
	if not (seat and hum) or seat.Disabled or seat.Occupant or hum.Health <= 0 then
		return false
	end
	hum.Sit = false
	botModel:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	seat:Sit(hum)
	return true
end

-- Tira o bot do assento e o põe no chão ao lado do veículo (à esquerda, para trás)
function VehicleService.botLeave(botModel: Model)
	local hum = botModel:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not (hum and seat) then
		return
	end
	local vehicle = seat:FindFirstAncestorWhichIsA("Model")
	local chassis = vehicle and vehicle:FindFirstChild("Chassis") :: BasePart?
	local k = ((botModel:GetAttribute("BotIndex") :: number?) or 0) % 4
	hum.Sit = false
	task.defer(function()
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		if chassis and botModel.Parent then
			local side = (chassis.CFrame * CFrame.new(-(chassis.Size.X / 2 + 2.5 / M), 0, (k - 1.5) * 1.2 / M)).Position
			local y = SpawnService.groundY(side.X, side.Z)
			botModel:PivotTo(CFrame.new(side.X, y + 4, side.Z))
		end
	end)
end

-- Acelerador e volante (-1..1) do bot motorista
function VehicleService.botInput(vehicle: Model, throttle: number, steer: number)
	local d = botDrives[vehicle]
	if d then
		d.inThr = math.clamp(throttle, -1, 1)
		d.inSteer = math.clamp(steer, -1, 1)
	end
end

-- Estado do veículo que um bot dirige (nil se não há bot no volante)
function VehicleService.botState(vehicle: Model): BotDriveState?
	local d = botDrives[vehicle]
	local chassis = vehicle:FindFirstChild("Chassis") :: BasePart?
	local spec = Vehicles.SPECS[vehicle:GetAttribute("Spec") :: string]
	if not (d and chassis and spec) then
		return nil
	end
	local _, cy, _ = chassis.CFrame:ToOrientation()
	local rain = ReplicatedStorage:GetAttribute("Rain")
	return {
		v = d.st.v,
		yaw = d.yaw or cy,
		ground = d.ground,
		floating = d.st.floating,
		slip = d.st.slip,
		blocked = d.st.blockedT > 0.25,
		top = VehicleDrive.topSpeed(spec, d.ground, if type(rain) == "number" then rain else nil),
	}
end

-- Tiro do bot sentado no assento (mesma validação do jogador: cadência, recarga, tubos)
function VehicleService.botFire(vehicle: Model, seatId: string, dir: Vector3, coax: boolean?): boolean
	local seat = seatById(vehicle, seatId)
	local occ = seat and seat.Occupant
	local char = occ and occ.Parent
	if not (seat and char and char:IsA("Model") and char:GetAttribute("Bot") == true) or dir.Magnitude < 0.5 then
		return false
	end
	return fireFromSeat(seat, char, nil, dir.Unit, coax == true, os.clock())
end

-- Arma principal pronta? (recarga do canhão ou do 106)
function VehicleService.mainReady(vehicle: Model, seatId: string): boolean
	local seat = seatById(vehicle, seatId)
	local weapon = seat and seat:GetAttribute("Weapon")
	if not (seat and type(weapon) == "string") then
		return false
	end
	local key = if weapon == "gun_90" and vehicle:GetAttribute("Ammo") == "heat" then "gun_90_heat" else weapon
	local gun = GUNS[key]
	return gun ~= nil and os.clock() - (lastShot[seat] or 0) >= gun.reloadS
end

function VehicleService.start()
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace
	-- bots no volante: a física do motorista roda aqui (D-90)
	RunService.Heartbeat:Connect(function(dt: number)
		if next(botDrives) == nil then
			return
		end
		dt = math.min(dt, 0.1)
		for model, d in botDrives do
			local chassis = model:FindFirstChild("Chassis") :: BasePart?
			local seat = model:FindFirstChild("Seat_driver")
			local occ = if seat and seat:IsA("Seat") then seat.Occupant else nil
			local spec = Vehicles.SPECS[model:GetAttribute("Spec") :: string]
			if not (chassis and spec and model.Parent and isBot(occ)) or model:GetAttribute("Destroyed") then
				botDrives[model] = nil
				continue
			end
			local ok, err = pcall(function(): any
				botDriveStep(model, chassis :: BasePart, spec, d, dt)
				return nil
			end)
			if not ok then
				warn("[VT65] bot motorista falhou:", err)
				botDrives[model] = nil
			end
		end
	end)
	Net.event("Vehicle_Fire").OnServerEvent:Connect(onFire)
	Net.event("Vehicle_Reload").OnServerEvent:Connect(onReload)
	-- telemetria do motorista: remote próprio, criado aqui (não está na lista do Net)
	local remotes = Net.server()
	local telemetry = remotes:FindFirstChild("Vehicle_Telemetry") :: UnreliableRemoteEvent?
	if not telemetry then
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = "Vehicle_Telemetry"
		r.Parent = remotes
		telemetry = r
	end
	(telemetry :: UnreliableRemoteEvent).OnServerEvent:Connect(onTelemetry)
	Players.PlayerRemoving:Connect(function(p)
		lastTelemetry[p] = nil
		boardAt[p] = nil
		switching[p] = nil
	end)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevDrive"):Connect(function()
			task.spawn(devDrive)
		end)
		workspace:GetAttributeChangedSignal("VT65DevVeh"):Connect(function()
			task.spawn(devVeh)
		end)
	end
	-- D-100: painel do veículo (entrar, trocar de lugar, sair, desvirar)
	Net.event("Vehicle_Board").OnServerEvent:Connect(function(player, req)
		onBoard(player, req)
	end)
	-- trocar de assento (formato antigo): próximo assento livre que a regra de papel permite. O
	-- controle agora abre o painel (D-100); fica para quem ainda manda este remote.
	Net.event("Vehicle_SwitchSeat").OnServerEvent:Connect(function(player)
		local seat = seatOf(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not seat or not (char and hum) then
			return
		end
		local model = seat:FindFirstAncestorWhichIsA("Model") :: Model
		local kind = tostring(model:GetAttribute("Kind"))
		local role, crew = player:GetAttribute("Role"), player:GetAttribute("VehicleCrew")
		local seats = {}
		for _, d in model:GetChildren() do
			if d:IsA("Seat") and not d.Disabled then
				table.insert(seats, d)
			end
		end
		table.sort(seats, function(a, b)
			return a.Name < b.Name
		end)
		local i = table.find(seats, seat) or 0
		for k = 1, #seats - 1 do
			local cand = seats[(i + k - 1) % #seats + 1]
			local ok = Roles.canTakeSeat(
				kind,
				tostring(cand:GetAttribute("SeatId")),
				if type(role) == "string" then role else nil,
				if type(crew) == "string" then crew else nil
			)
			if not cand.Occupant and ok then
				sitIn(player, char, hum, cand)
				return
			end
		end
	end)
	-- foguetes do papel antitanque: 3 por vida (PLACEHOLDER); o papel de campo do veículo (D-100)
	-- vale uma vida só
	local function arm(player: Player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Rockets", if player:GetAttribute("Role") == "anti_tank" then 3 else 0)
			player:SetAttribute("VehicleCrew", nil)
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
