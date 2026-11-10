--!strict
-- Controle de veículos (F4). O motorista tem a posse de rede do chassi e simula aqui:
--   blindados/anfíbios: Shared/Vehicles.drive (potência, atrito e resistência por tipo de chão);
--   UH-34D: Shared/HeliModel (efeito solo, sustentação de translação, calor, carga e torque).
-- Teclas — chão: W/S acelera/ré, A/D vira. Helicóptero: Espaço/Ctrl coletivo, W/S cíclico
-- (arfagem), A/D cíclico (rolagem), Q/E pedais. Artilheiro: mira com a câmera, clique atira,
-- R recarrega o Ontos (parado). A pé, antitanque: Z dispara o foguete. Y sai do veículo.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local HeliModel = require(ReplicatedStorage.Shared.HeliModel)
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

local function sinkJump(_: string, _state: Enum.UserInputState, _: InputObject)
	return Enum.ContextActionResult.Sink
end

local function groundStep(model: Model, chassis: BasePart, spec: any, dt: number)
	local throttle = key(Enum.KeyCode.W) - key(Enum.KeyCode.S)
	local steer = key(Enum.KeyCode.D) - key(Enum.KeyCode.A)
	local hit = groundRay(chassis.Position, model, chassis.Size.Y + 6)
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
	heli.collective =
		math.clamp(heli.collective + (key(Enum.KeyCode.Space) - key(Enum.KeyCode.LeftControl)) * 0.35 * dt, 0, 1)
	local tp = (key(Enum.KeyCode.S) - key(Enum.KeyCode.W)) * math.rad(15)
	local tr = (key(Enum.KeyCode.A) - key(Enum.KeyCode.D)) * math.rad(15)
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
	local pedal = key(Enum.KeyCode.E) - key(Enum.KeyCode.Q)
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
RunService.Heartbeat:Connect(function(dt)
	local seat = currentSeat()
	local model = seat and vehicleOf(seat)
	if not seat or not model or model:GetAttribute("Destroyed") then
		if driving then
			ContextActionService:UnbindAction("VT65_HeliNoJump")
		end
		driving, yaw = nil, nil
		drive.v = 0
		label.Visible = false
		return
	end
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local spec = Vehicles.SPECS[model:GetAttribute("Spec") :: string]
	if not chassis or not spec then
		return
	end
	label.Visible = true
	if seat:GetAttribute("SeatId") == "driver" then
		if driving ~= model then
			driving = model
			yaw = nil
			drive.v = 0
			heli.vel = Vector3.zero
			if spec.kind == "heli" then
				ContextActionService:BindActionAtPriority("VT65_HeliNoJump", sinkJump, false, 3000, Enum.KeyCode.Space)
			end
		end
		if spec.kind == "heli" then
			heliStep(model, chassis, dt)
		else
			groundStep(model, chassis, spec, dt)
		end
	else
		local w = seat:GetAttribute("Weapon")
		label.Text = string.format(
			"%s — %s%s",
			spec.name,
			tostring(seat:GetAttribute("SeatId")),
			if w == "rr_106"
				then string.format(
					"\ntubos carregados: %d (R recarrega parado)",
					(model:GetAttribute("Tubes") :: number?) or 0
				)
				elseif w then "\narma: " .. tostring(w)
				else ""
		)
	end
end)

-- tiro do assento (mira pela câmera); M60 em automático pela cadência da ficha
local firing = false
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local seat = currentSeat()
	if input.KeyCode == Enum.KeyCode.Y and seat then
		local hum = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Sit = false
			hum.Jump = true
		end
	elseif input.KeyCode == Enum.KeyCode.R and seat and seat:GetAttribute("Weapon") == "rr_106" then
		Net.event("Vehicle_Reload"):FireServer()
	elseif input.KeyCode == Enum.KeyCode.Z and not seat and player:GetAttribute("Role") == "anti_tank" then
		Net.event("Vehicle_Fire"):FireServer({ dir = camera.CFrame.LookVector })
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and seat and seat:GetAttribute("Weapon") then
		local w = seat:GetAttribute("Weapon")
		if w == "m60" then
			firing = true
			local wp = Weapons.get("m60")
			local interval = 60 / ((wp and wp.rpm) or 550)
			task.spawn(function()
				while firing and currentSeat() == seat do
					Net.event("Vehicle_Fire"):FireServer({ dir = camera.CFrame.LookVector })
					task.wait(interval)
				end
			end)
		else
			Net.event("Vehicle_Fire"):FireServer({ dir = camera.CFrame.LookVector })
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	end
end)
