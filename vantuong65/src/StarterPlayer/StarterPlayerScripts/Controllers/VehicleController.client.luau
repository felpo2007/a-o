--!strict
-- Controle de veículos (F4 + Parte 12.3). O motorista tem a posse de rede do chassi e simula aqui:
--   blindados/anfíbios: Shared/Vehicles.drive (potência, atrito e resistência por tipo de chão);
--   UH-34D: Shared/HeliModel (efeito solo, sustentação de translação, calor, carga e torque).
-- Controle: motorista — analógico esquerdo dirige, RT acelera, LT freia/ré; atirador — analógico
-- direito gira a torre (câmera), RT tiro principal, LT ótica, RB coaxial, X munição; comandante —
-- LT binóculo, RB marca o alvo; piloto — analógico esquerdo cíclico, RT/LT coletivo, RB/LB
-- pedais, A segurado estabiliza (assistência opcional); porta — RT atira, LT zoom; todos — Y
-- segurado troca de assento, B segurado sai. Teclado: WASD, Espaço/Ctrl, Q/E, mouse, C, Y.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local HeliModel = require(ReplicatedStorage.Shared.HeliModel)
local Input = require(script.Parent.Input)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local AIR_C = 30 -- °C de agosto na costa (mesma premissa da balística, Ballistics.RHO)

local gui = Instance.new("ScreenGui")
gui.Name = "VehicleHud"
gui.ResetOnSpawn = false
local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(360, 92)
label.Position = UDim2.new(0, 16, 1, -110)
label.BackgroundTransparency = 0.45
label.BackgroundColor3 = Color3.fromRGB(20, 22, 16)
label.TextColor3 = Color3.fromRGB(230, 225, 200)
label.Font = Enum.Font.Code
label.TextSize = 14
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Visible = false
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local function key(k: Enum.KeyCode): number
	return if UserInputService:IsKeyDown(k) then 1 else 0
end

local function currentSeat(): Seat?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local s = hum and hum.SeatPart
	return if s and s:IsA("Seat") then s else nil
end

local function vehicleOf(seat: Seat): Model?
	local m = seat:FindFirstAncestorWhichIsA("Model")
	return if m and m:GetAttribute("VehicleId") then m else nil
end

local function groundRay(from: Vector3, model: Model, len: number): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, player.Character :: Model }
	return workspace:Raycast(from, Vector3.new(0, -len, 0), params)
end

local function surfaceOf(hit: RaycastResult?): string
	if not hit then
		return "earth"
	end
	if hit.Instance == workspace.Terrain then
		local m = hit.Material
		if m == Enum.Material.Water then
			return "water"
		elseif m == Enum.Material.Sand then
			return "sand"
		elseif m == Enum.Material.Mud then
			return "paddy"
		elseif m == Enum.Material.Asphalt or m == Enum.Material.Pavement or m == Enum.Material.Concrete then
			return "road"
		end
		return "earth"
	end
	if hit.Instance:GetAttribute("Material") == "PaddyWater" or hit.Instance.Name == "PaddyWater" then
		return "paddy"
	end
	return "earth"
end

-- estado do veículo dirigido
local drive = { v = 0 }
local yaw: number? = nil
local heli = { collective = 0.55, vel = Vector3.zero, pitch = 0, roll = 0 }
local pedalL, pedalR, stabilize = false, false, false

local function groundStep(model: Model, chassis: BasePart, spec: any, dt: number)
	-- controle: RT acelera, LT freia/ré, analógico esquerdo dirige (Parte 12.3); teclado: WASD
	local throttle, steer
	if Input.isGamepad() then
		throttle = Input.trigger("right") - Input.trigger("left")
		steer = Input.move().X
	else
		throttle = key(Enum.KeyCode.W) - key(Enum.KeyCode.S)
		steer = key(Enum.KeyCode.D) - key(Enum.KeyCode.A)
	end
	if not InputMap.acceptsGame(Input.state) then
		throttle, steer = 0, 0
	end
	-- do topo do chassi: flutuando, o centro do LVTP-5 fica abaixo da superfície (y −1,2 no Studio) e
	-- o raio que saía do centro acertava a areia do fundo, dando velocidade de terra na água
	local hit = groundRay(chassis.Position + Vector3.new(0, chassis.Size.Y / 2, 0), model, chassis.Size.Y * 1.5 + 6)
	local surface = surfaceOf(hit)
	if (model:GetAttribute("Engine") :: number) <= 0 or (model:GetAttribute("Tracks") :: number) <= 0 then
		throttle = 0
	end
	Vehicles.drive(spec, drive, throttle, surface, dt)
	local _, cy, _ = chassis.CFrame:ToOrientation()
	yaw = yaw or cy
	local vmax = spec.maxKmh / 3.6
	local turn = math.rad(30) * (1 - 0.5 * math.min(math.abs(drive.v) / vmax, 1)) -- PLACEHOLDER
	yaw = (yaw :: number) - steer * turn * dt
	-- atitude: normal do chão por 4 raios nos cantos
	local half = chassis.Size * 0.45
	local function h(dx: number, dz: number): number
		local p = (CFrame.new(chassis.Position) * CFrame.Angles(0, yaw :: number, 0) * CFrame.new(dx, 0, dz)).Position
		local r = groundRay(p + Vector3.new(0, 10, 0), model, 40)
		return if r then r.Position.Y else chassis.Position.Y - half.Y
	end
	local fl, fr, bl, br = h(-half.X, -half.Z), h(half.X, -half.Z), h(-half.X, half.Z), h(half.X, half.Z)
	local pitch = math.atan2(((fl + fr) - (bl + br)) / 2, half.Z * 2)
	local roll = math.atan2(((fr + br) - (fl + bl)) / 2, half.X * 2) -- lado direito mais alto = gira +Z
	local att = CFrame.Angles(0, yaw :: number, 0) * CFrame.Angles(pitch, 0, roll)
	local ao = chassis:FindFirstChild("DriveAttitude") :: AlignOrientation?
	local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
	if ao and lv then
		ao.CFrame = att
		local fwd = (CFrame.Angles(0, yaw :: number, 0)).LookVector
		local v = fwd * drive.v / M
		lv.PlaneVelocity = Vector2.new(v.X, v.Z)
	end
	label.Text = string.format(
		"%s\nvelocidade %3.0f km/h  chão: %s\nintegridade %d  motor %d  esteiras %d",
		spec.name,
		drive.v * 3.6,
		surface,
		model:GetAttribute("Integrity") :: number,
		model:GetAttribute("Engine") :: number,
		model:GetAttribute("Tracks") :: number
	)
end

local function heliStep(model: Model, chassis: BasePart, dt: number)
	local S = HeliModel.SPEC
	local atm = HeliModel.atmosphere(AIR_C)
	-- controle: RT/LT coletivo, analógico esquerdo cíclico, RB/LB pedais; teclado: Espaço/Ctrl, WASD, Q/E
	local up, cyc
	if Input.isGamepad() then
		up = Input.trigger("right") - Input.trigger("left")
		cyc = Input.move()
	else
		up = key(Enum.KeyCode.Space) - key(Enum.KeyCode.LeftControl)
		cyc = Vector2.new(key(Enum.KeyCode.D) - key(Enum.KeyCode.A), key(Enum.KeyCode.W) - key(Enum.KeyCode.S))
	end
	if not InputMap.acceptsGame(Input.state) then
		up, cyc = 0, Vector2.zero
	end
	heli.collective = math.clamp(heli.collective + up * 0.35 * dt, 0, 1)
	local tp = -cyc.Y * math.rad(15)
	local tr = -cyc.X * math.rad(15)
	-- estabilizar (A segurado): assistência opcional, sem piloto automático — nivela o disco
	-- contra a deriva e aproxima o coletivo do pairado; o piloto segue no comando.
	if stabilize then
		local localV = CFrame.Angles(0, (yaw or 0) :: number, 0):VectorToObjectSpace(heli.vel)
		tp += math.clamp(-localV.Z * 0.02, -0.15, 0.15)
		tr += math.clamp(localV.X * 0.02, -0.15, 0.15)
	end
	heli.pitch += (tp - heli.pitch) * math.min(1, 2 * dt)
	heli.roll += (tr - heli.roll) * math.min(1, 2 * dt)
	-- carga: vazio + 2 pilotos + ocupantes + combustível (PLACEHOLDER 400 kg)
	local occ = 0
	for _, s in model:GetDescendants() do
		if s:IsA("Seat") and s.Occupant then
			occ += 1
		end
	end
	local mass = S.emptyKg + 400 + occ * 100
	local rotorZ = (function()
		local r = groundRay(chassis.Position, model, 400)
		local hub = chassis.Position.Y + (S.igeZ - 1.52) / M - chassis.Size.Y / 2
		return if r then (hub - r.Position.Y) * M else 400
	end)()
	local V = Vector3.new(heli.vel.X, 0, heli.vel.Z).Magnitude
	local pAvail = HeliModel.powerAvailable(atm)
	local pDemand = heli.collective * pAvail
	local pReq = HeliModel.powerRequired(mass, V, rotorZ, atm)
	local climb = HeliModel.climbRate(pDemand, mass, V, rotorZ, atm)
	local onGround = rotorZ <= S.igeZ + 0.3 and climb <= 0
	-- horizontal: inclinação do disco acelera; arrasto parasita freia (área f calibrada)
	local _, cy, _ = chassis.CFrame:ToOrientation()
	yaw = yaw or cy
	local torque = HeliModel.torqueFraction(pDemand)
	local pedal = (if pedalR then 1 else 0) - (if pedalL then 1 else 0)
	if stabilize and up == 0 then
		-- aproxima o coletivo da potência de pairar (subida ~0)
		heli.collective += ((pReq / pAvail) - heli.collective) * math.min(1, dt * 0.8)
	end
	local drift = if torque > 0.92 then (torque - 0.92) * math.rad(200) else 0 -- falta pedal: nariz gira
	yaw = (yaw :: number) - (pedal * math.rad(35) + drift) * dt
	local yawCF = CFrame.Angles(0, yaw :: number, 0)
	local accFwd = 9.80665 * math.tan(-heli.pitch)
	local accSide = 9.80665 * math.tan(-heli.roll)
	local acc = yawCF.LookVector * accFwd + yawCF.RightVector * accSide
	local hv = Vector3.new(heli.vel.X, 0, heli.vel.Z)
	local drag = if V > 0.1 then hv.Unit * (0.5 * atm.rho * V * V * HeliModel.calibration().f / mass) else Vector3.zero
	hv += (acc - drag) * dt
	if onGround then
		hv *= math.max(0, 1 - 3 * dt) -- rodas no chão
		climb = math.max(climb, 0)
	end
	if hv.Magnitude > S.maxSpeedMs then
		hv = hv.Unit * S.maxSpeedMs
	end
	heli.vel = Vector3.new(hv.X, math.clamp(climb, -10, 8), hv.Z)
	local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
	local ao = chassis:FindFirstChild("DriveAttitude") :: AlignOrientation?
	if lv and ao then
		lv.VectorVelocity = heli.vel / M
		ao.CFrame = yawCF * CFrame.Angles(if onGround then 0 else heli.pitch, 0, if onGround then 0 else heli.roll)
	end
	label.Text = string.format(
		"UH-34D  %d °C\nvelocidade %3.0f nós  altura %4.0f m  subida %+.1f m/s\npotência %4.0f/%4.0f hp (exige %4.0f)  torque %3.0f%%%s",
		AIR_C,
		V * 1.9438,
		rotorZ,
		climb,
		pDemand / 745.7,
		pAvail / 745.7,
		pReq / 745.7,
		torque * 100,
		if pReq > pAvail then "\nSEM POTÊNCIA PARA PAIRAR: corra para ganhar sustentação" else ""
	)
end

local driving: Model? = nil
local seatNow: Seat? = nil
local zoom = 0 -- 0 nenhum, 1 ótica/zoom, 2 binóculo

-- tipo de contexto e papel do assento para a camada Input (Parte 12.3)
local function seatRole(seat: Seat, spec: any): string?
	local id = seat:GetAttribute("SeatId")
	if id == "driver" then
		return "driver"
	elseif id == "gunner" then
		return if spec.kind == "heli" then "door" else "gunner"
	elseif id == "commander" then
		return "commander"
	end
	return nil
end

RunService.Heartbeat:Connect(function(dt: number)
	local seat = currentSeat()
	local model = seat and vehicleOf(seat)
	if not seat or not model or model:GetAttribute("Destroyed") then
		if seatNow then
			seatNow = nil
			Input.setVehicle(nil, nil)
			camera.FieldOfView = Input.settings.fov
		end
		driving, yaw = nil, nil
		drive.v = 0
		zoom = 0
		label.Visible = false
		return
	end
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local spec = Vehicles.SPECS[model:GetAttribute("Spec") :: string]
	if not chassis or not spec then
		return
	end
	if seat ~= seatNow then
		seatNow = seat
		zoom = 0
		Input.setVehicle(if spec.kind == "heli" then "helicopter" else "ground_vehicle", seatRole(seat, spec))
	end
	-- FOV no veículo: ótica do atirador ~20°, binóculo do comandante 10°, zoom leve da porta 50°
	local target = if zoom == 2
		then 10
		elseif zoom == 1 then (if seat:GetAttribute("Weapon") == "m60" then 50 else 20)
		else Input.settings.fov
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 8)
	label.Visible = true
	if seat:GetAttribute("SeatId") == "driver" then
		if driving ~= model then
			driving = model
			yaw = nil
			drive.v = 0
			heli.vel = Vector3.zero
		end
		if spec.kind == "heli" then
			heliStep(model, chassis, dt)
		else
			groundStep(model, chassis, spec, dt)
		end
	else
		local w = seat:GetAttribute("Weapon")
		local _, fireTxt = Input.glyph(if seatRole(seat, spec) == "door" then "v_door_fire" else "v_fire")
		label.Text = string.format(
			"%s — %s%s",
			spec.name,
			tostring(seat:GetAttribute("SeatId")),
			if w == "rr_106"
				then string.format(
					"\ntubos carregados: %d (recarregar: parado)",
					(model:GetAttribute("Tubes") :: number?) or 0
				)
				elseif w == "gun_90" then string.format(
					"\nmunição: %s · atirar: %s",
					tostring(model:GetAttribute("Ammo") or "he"),
					fireTxt
				)
				elseif w then "\narma: " .. tostring(w) .. " · atirar: " .. fireTxt
				else ""
		)
	end
end)

-- ===== armas e ações dos assentos (camada Input) =====
local firing = false
local function fireOnce(extra: { [string]: any }?)
	local req: { [string]: any } = { dir = camera.CFrame.LookVector }
	if extra then
		for k, v in extra do
			req[k] = v
		end
	end
	Net.event("Vehicle_Fire"):FireServer(req)
end
local function autoFire(extra: { [string]: any }?)
	firing = true
	local wp = Weapons.get("m60")
	local interval = 60 / ((wp and wp.rpm) or 550)
	local seat = currentSeat()
	task.spawn(function()
		while firing and currentSeat() == seat do
			fireOnce(extra)
			task.wait(interval)
		end
	end)
end
local function stopFire()
	firing = false
end

-- atirador do blindado: RT principal, RB coaxial, LT ótica, X munição/recarga
Input.on("v_fire", "press", function()
	local seat = currentSeat()
	if seat and seat:GetAttribute("Weapon") == "m60" then
		autoFire(nil)
	else
		fireOnce(nil)
	end
end)
Input.on("v_fire", "release", stopFire)
Input.on("v_coax", "press", function()
	autoFire({ coax = true })
end)
Input.on("v_coax", "release", stopFire)
Input.on("v_ammo", "press", function()
	Net.event("Vehicle_Reload"):FireServer({ op = "ammo" })
end)
Input.on("v_optic", "press", function()
	zoom = 1
end)
Input.on("v_optic", "release", function()
	zoom = 0
end)
-- comandante: LT binóculo, RB marca o alvo para o atirador
Input.on("v_binoculars", "press", function()
	zoom = 2
end)
Input.on("v_binoculars", "release", function()
	zoom = 0
end)
Input.on("v_mark", "press", function()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local seat = currentSeat()
	local model = seat and vehicleOf(seat)
	if model then
		params:AddToFilter(model)
	end
	local r = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * (2000 / M), params)
	if r then
		Net.event("Squad_Mark"):FireServer({ pos = r.Position, kind = "target" })
	end
end)
-- atirador de porta: RT atira (automático), LT zoom leve
Input.on("v_door_fire", "press", function()
	autoFire(nil)
end)
Input.on("v_door_fire", "release", stopFire)
-- piloto: pedais e estabilização
Input.on("h_pedal_left", "press", function()
	pedalL = true
end)
Input.on("h_pedal_left", "release", function()
	pedalL = false
end)
Input.on("h_pedal_right", "press", function()
	pedalR = true
end)
Input.on("h_pedal_right", "release", function()
	pedalR = false
end)
Input.on("h_stabilize", "holdStart", function()
	stabilize = true
end)
Input.on("h_stabilize", "holdEnd", function()
	stabilize = false
end)
Input.on("h_stabilize", "press", function() -- R no teclado: alterna
	stabilize = not stabilize
end)
-- todos: Y segurado troca de assento; B segurado sai (teclado: C e Y)
local function switchSeat()
	Net.event("Vehicle_SwitchSeat"):FireServer()
end
local function exitVehicle()
	local hum = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Sit = false
		hum.Jump = true
	end
end
Input.on("v_switch_seat", "holdStart", switchSeat)
Input.on("v_switch_seat", "press", switchSeat)
Input.on("v_exit", "holdStart", exitVehicle)
Input.on("v_exit", "press", exitVehicle)
Input.StateChanged:Connect(function()
	firing = false
	pedalL, pedalR, stabilize = false, false, false
end)
