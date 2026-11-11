--!strict
-- Controle de veículos (F4 + Parte 12.3). O motorista tem a posse de rede do chassi e simula aqui:
--   blindados/anfíbios: Shared/VehicleDrive (motor que enche, conversor e marchas, freio, giro de
--   lagarta no lugar e amplo em movimento, ladeira, lama, arrozal e água pelo chão debaixo);
--   UH-34D: Shared/HeliModel (efeito solo, sustentação de translação, calor, carga e torque) com
--   atitude e subida com inércia, rotor que parte e para, pouso amortecido e curva coordenada.
-- Câmera de quem está no veículo: balança com a carroceria (só o movimento, não a ladeira parada) e
-- treme pela velocidade, pelo chão e pelo motor; o motorista sente mais, o resto da tripulação menos.
-- Controle: motorista — analógico esquerdo dirige, RT acelera, LT freia/ré; atirador — analógico
-- direito gira a torre (câmera), RT tiro principal, LT ótica, RB coaxial, X munição; comandante —
-- LT binóculo, RB marca o alvo; piloto — analógico esquerdo cíclico, RT/LT coletivo, RB/LB
-- pedais, A segurado estabiliza (assistência opcional); porta — RT atira, LT zoom; todos — Y
-- segurado troca de assento, B segurado sai. Teclado: WASD, Espaço/Ctrl, Q/E, mouse, C, Y.
-- Limite do Roblox: 200 locais por função contando o nível de cima. O estado fica em tabelas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local HeliModel = require(ReplicatedStorage.Shared.HeliModel)
local Haptics = require(script.Parent.Haptics)
local Input = require(script.Parent.Input)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Net = require(ReplicatedStorage.Shared.Net)
local VehicleDrive = require(ReplicatedStorage.Shared.VehicleDrive)
local VehicleLive = require(script.Parent.VehicleLive)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local AIR_C = 30 -- °C de agosto na costa (mesma premissa da balística, Ballistics.RHO)
local GROUND_PT: { [string]: string } = {
	road = "estrada",
	earth = "terra",
	grass = "capim",
	forest = "mata",
	sand = "areia",
	mud = "lama",
	paddy = "arrozal",
	water = "água",
}

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

local function approach(x: number, target: number, tau: number, dt: number): number
	return x + (target - x) * (1 - math.exp(-dt / math.max(tau, 1e-3)))
end

-- muda no máximo `rate` por segundo (curso do pedal e do volante)
local function slew(x: number, target: number, rate: number, dt: number): number
	local d = target - x
	local step = rate * dt
	return if math.abs(d) <= step then target else x + math.sign(d) * step
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

-- ===== chão debaixo do veículo (raio compartilhado com o VehicleFx, em VehicleLive) =====
local rays = { solid = RaycastParams.new() }

local function prepRays(model: Model)
	local list: { Instance } = { model }
	if player.Character then
		table.insert(list, player.Character)
	end
	local fx = workspace:FindFirstChild("VT65VehicleFx")
	if fx then
		table.insert(list, fx)
	end
	rays.solid = VehicleLive.solid(list)
end

-- Atitude do chão por 4 raios nas pontas, no rumo `yaw`: (pitch + = nariz para cima, roll + = lado
-- direito mais alto), em rad. nil se alguma ponta não achou chão.
local function groundAttitude(chassis: BasePart, yaw: number): (number?, number?)
	local half = Vector3.new(chassis.Size.X * 0.42, 0, chassis.Size.Z * 0.45)
	local base = CFrame.new(chassis.Position) * CFrame.Angles(0, yaw, 0)
	local hs = {}
	for i, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do -- fl, fr, bl, br (frente = -Z)
		local p = (base * CFrame.new(c[1] * half.X, 0, c[2] * half.Z)).Position
		local r = workspace:Raycast(p + Vector3.new(0, 14, 0), Vector3.new(0, -48, 0), rays.solid)
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

-- ===== estado do veículo dirigido =====
local ctl = {
	drive = VehicleDrive.newState(),
	yaw = nil :: number?,
	pitch = 0, -- atitude do chão, filtrada
	roll = 0,
	thr = 0, -- acelerador e volante com curso
	steer = 0,
	ground = "earth",
	depth = nil :: number?,
	probeT = 0,
	telemetryT = 0,
	telemetry = nil :: UnreliableRemoteEvent?,
	pedalL = false,
	pedalR = false,
	stabilize = false,
}
local heli = {
	collective = 0.55,
	vel = Vector3.zero,
	pitch = 0,
	pitchV = 0,
	roll = 0,
	rollV = 0,
	yawRate = 0,
	vy = 0,
	rotor = 0,
}

-- remote criado pelo servidor (VehicleService.start); sem ele a telemetria só não sai
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("VT65Remotes", 60)
	local r = folder and folder:WaitForChild("Vehicle_Telemetry", 60)
	if r and r:IsA("UnreliableRemoteEvent") then
		ctl.telemetry = r
	end
end)

local function sendTelemetry(dt: number, rpm: number, load: number, rotor: number)
	ctl.telemetryT += dt
	local r = ctl.telemetry
	if ctl.telemetryT >= 1 / 6 and r then
		ctl.telemetryT = 0
		r:FireServer({ r = rpm, l = load, w = rotor })
	end
end

local function groundStep(model: Model, chassis: BasePart, spec: any, dt: number)
	-- controle: RT acelera, LT freia/ré, analógico esquerdo dirige (Parte 12.3); teclado: WASD
	local throttle, steer
	if Input.isGamepad() then
		throttle = Input.trigger("right") - Input.trigger("left")
		local x = Input.move().X
		steer = math.sign(x) * math.abs(x) ^ 1.4 -- mais precisão perto do centro do analógico
	else
		throttle = key(Enum.KeyCode.W) - key(Enum.KeyCode.S)
		steer = key(Enum.KeyCode.D) - key(Enum.KeyCode.A)
	end
	if not InputMap.acceptsGame(Input.state) then
		throttle, steer = 0, 0
	end
	-- pedal e volante têm curso: tecla sobe em ~0,3 s e solta em ~0,15 s; analógico quase direto
	local pad = Input.isGamepad()
	ctl.thr =
		slew(ctl.thr, throttle, if math.abs(throttle) > math.abs(ctl.thr) then (if pad then 8 else 3.2) else 7, dt)
	ctl.steer = slew(ctl.steer, steer, if pad then 10 else 4.5, dt)
	prepRays(model)
	ctl.probeT -= dt
	if ctl.probeT <= 0 then
		ctl.probeT = 0.1
		local g, depth = VehicleLive.probe(chassis)
		ctl.ground, ctl.depth = g, depth
	end
	local _, cy, _ = chassis.CFrame:ToOrientation()
	local yaw = ctl.yaw or cy
	local p, r = groundAttitude(chassis, yaw)
	if p and r then
		ctl.pitch = approach(ctl.pitch, p, 0.1, dt)
		ctl.roll = approach(ctl.roll, r, 0.1, dt)
	end
	local rain = ReplicatedStorage:GetAttribute("Rain")
	local d = ctl.drive
	VehicleDrive.step(spec, d, { throttle = ctl.thr, steer = ctl.steer }, {
		ground = ctl.ground,
		rain = if type(rain) == "number" then rain else 0,
		slopeSin = math.sin(ctl.pitch),
		sideSin = math.sin(ctl.roll),
		waterDepthM = ctl.depth,
		engine = ((model:GetAttribute("Engine") :: number?) or 0) / 100,
		tracks = ((model:GetAttribute("Tracks") :: number?) or 0) / 100,
	}, dt)
	-- contato: parede, barranco ou outro veículo seguram o chassi; o modelo acompanha a velocidade real
	local flat = CFrame.Angles(0, yaw, 0)
	local vel = chassis.AssemblyLinearVelocity * M
	if not d.floating then
		local measured = Vector3.new(vel.X, 0, vel.Z):Dot(flat.LookVector) / math.max(math.cos(ctl.pitch), 0.5)
		VehicleDrive.contact(d, measured, dt)
	end
	yaw += d.yawRate * dt
	ctl.yaw = yaw
	flat = CFrame.Angles(0, yaw, 0)
	local ao = chassis:FindFirstChild("DriveAttitude") :: AlignOrientation?
	local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
	if ao and lv then
		ao.CFrame = flat * CFrame.Angles(ctl.pitch, 0, ctl.roll)
		local hv = flat.LookVector * d.v * math.cos(ctl.pitch) + flat.RightVector * d.vLat
		lv.PlaneVelocity = Vector2.new(hv.X, hv.Z) / M
	end
	local live = VehicleLive.drive
	live.model = model
	live.rpm, live.load, live.throttle, live.steer = d.rpm, d.load, ctl.thr, ctl.steer
	live.slip, live.gear, live.ground, live.floating, live.rotor = d.slip, d.gear, ctl.ground, d.floating, 0
	sendTelemetry(dt, d.rpm, d.load, 0)
	-- vibração do chão no motor pequeno do controle (o grande já é o do motor, Haptics)
	local g = VehicleDrive.GROUND[ctl.ground] or VehicleDrive.GROUND.earth
	local speedFrac = math.clamp(math.abs(d.v) / 13, 0, 1)
	Haptics.set("vt_ride", Enum.VibrationMotor.Small, g.rough * speedFrac * 0.3 + d.slip * 0.15)
	local ds = VehicleDrive.spec(spec.id)
	local gearTxt = if d.gear < 0 then "ré" elseif d.gear == 0 then "neutro" else d.gear .. "ª"
	label.Text = string.format(
		"%s\n%3.0f km/h  %s  %4.0f rpm  chão: %s%s\nintegridade %d  motor %d  esteiras %d",
		spec.name,
		d.v * 3.6,
		gearTxt,
		d.rpm * ds.rpmMax,
		GROUND_PT[ctl.ground] or ctl.ground,
		if d.floating then " (boiando)" elseif d.slip > 0.5 then " (patinando)" else "",
		model:GetAttribute("Integrity") :: number,
		model:GetAttribute("Engine") :: number,
		model:GetAttribute("Tracks") :: number
	)
end

local function heliStep(model: Model, chassis: BasePart, dt: number)
	local S = HeliModel.SPEC
	local H = VehicleDrive.HELI
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
	prepRays(model)
	local engineOk = ((model:GetAttribute("Engine") :: number?) or 0) > 0
	heli.rotor = VehicleDrive.rotorStep(heli.rotor, engineOk, dt)
	heli.collective = math.clamp(heli.collective + up * 0.35 * dt, 0, 1)
	local _, cy, _ = chassis.CFrame:ToOrientation()
	local yaw = ctl.yaw or cy
	-- carga: vazio + 2 pilotos + ocupantes + combustível (PLACEHOLDER 400 kg)
	local occ = 0
	for _, s in model:GetChildren() do
		if s:IsA("Seat") and s.Occupant then
			occ += 1
		end
	end
	local mass = S.emptyKg + 400 + occ * 100
	local rotorZ = 400
	do
		local r = workspace:Raycast(chassis.Position, Vector3.new(0, -400, 0), rays.solid)
		local hub = chassis.Position.Y + (S.igeZ - 1.52) / M - chassis.Size.Y / 2
		if r then
			rotorZ = (hub - r.Position.Y) * M
		end
	end
	local gearH = rotorZ - S.igeZ -- altura das rodas
	local V = Vector3.new(heli.vel.X, 0, heli.vel.Z).Magnitude
	-- a sustentação cresce com o rotor²: parado, o motor gira o rotor antes de levantar
	local pAvail = HeliModel.powerAvailable(atm) * heli.rotor * heli.rotor
	local pDemand = heli.collective * pAvail
	local pReq = HeliModel.powerRequired(mass, V, rotorZ, atm)
	local climb = HeliModel.climbRate(pDemand, mass, V, rotorZ, atm)
	local onGround = gearH <= 0.3 and climb <= 0.05
	-- cíclico: disco inclina com inércia (2ª ordem); no chão a atitude é a do terreno
	local tp = -cyc.Y * math.rad(15)
	local tr = -cyc.X * math.rad(15)
	-- estabilizar (A segurado): assistência opcional, sem piloto automático — nivela o disco
	-- contra a deriva e aproxima o coletivo do pairado; o piloto segue no comando.
	if ctl.stabilize then
		local localV = CFrame.Angles(0, yaw, 0):VectorToObjectSpace(heli.vel)
		tp += math.clamp(-localV.Z * 0.02, -0.15, 0.15)
		tr += math.clamp(localV.X * 0.02, -0.15, 0.15)
		if up == 0 and pAvail > 0 then
			heli.collective += ((pReq / pAvail) - heli.collective) * math.min(1, dt * 0.8)
		end
	end
	local live = VehicleLive.drive
	live.cyclicX, live.cyclicY = tr, tp
	if onGround then
		local gp, gr = groundAttitude(chassis, yaw)
		tp, tr = gp or 0, gr or 0
	end
	heli.pitch, heli.pitchV = VehicleDrive.attitude(heli.pitch, heli.pitchV, tp, dt)
	heli.roll, heli.rollV = VehicleDrive.attitude(heli.roll, heli.rollV, tr, dt)
	-- guinada: pedais, torque sem pedal e, em velocidade, a cauda alinhando o nariz com a curva
	local torque = HeliModel.torqueFraction(pDemand)
	local pedal = (if ctl.pedalR then 1 else 0) - (if ctl.pedalL then 1 else 0)
	local drift = if torque > 0.92 then (torque - 0.92) * math.rad(200) else 0 -- falta pedal: nariz gira
	local yawTarget = -(pedal * math.rad(35) * (if onGround then 0.5 else 1) + drift) * math.min(heli.rotor * 2, 1)
	if not onGround then
		yawTarget += VehicleDrive.coordinatedYaw(heli.roll, V)
	end
	heli.yawRate = approach(heli.yawRate, yawTarget, H.yawTauS, dt)
	yaw += heli.yawRate * dt
	ctl.yaw = yaw
	-- horizontal: inclinação do disco acelera; arrasto parasita freia (área f calibrada)
	local yawCF = CFrame.Angles(0, yaw, 0)
	local lift = math.min(heli.rotor * heli.rotor, 1)
	local acc = (
		yawCF.LookVector * (9.80665 * math.tan(-heli.pitch)) + yawCF.RightVector * (9.80665 * math.tan(-heli.roll))
	) * (if onGround then 0 else lift)
	local hv = Vector3.new(heli.vel.X, 0, heli.vel.Z)
	local drag = if V > 0.1 then hv.Unit * (0.5 * atm.rho * V * V * HeliModel.calibration().f / mass) else Vector3.zero
	hv += (acc - drag) * dt
	if onGround then
		hv *= math.max(0, 1 - 3 * dt) -- rodas no chão
	end
	if hv.Magnitude > S.maxSpeedMs then
		hv = hv.Unit * S.maxSpeedMs
	end
	-- vertical com inércia; perto do chão a descida é amortecida (pouso suave, assistência de design).
	-- A subida vem do modelo (calibrado em 600 e 1.100 ft/min, D-61); 20 m/s é só rede de segurança.
	local vy = VehicleDrive.heliVertical(heli.vy, climb, gearH, dt)
	if onGround then
		vy = math.max(vy, 0)
	end
	heli.vy = math.clamp(vy, -10, 20)
	heli.vel = Vector3.new(hv.X, heli.vy, hv.Z)
	local lv = chassis:FindFirstChild("DriveVelocity") :: LinearVelocity?
	local ao = chassis:FindFirstChild("DriveAttitude") :: AlignOrientation?
	if lv and ao then
		lv.VectorVelocity = heli.vel / M
		ao.CFrame = yawCF * CFrame.Angles(heli.pitch, 0, heli.roll)
	end
	live.model = model
	live.rpm, live.load, live.rotor, live.throttle = heli.rotor, heli.collective, heli.rotor, up
	live.slip, live.gear, live.floating = 0, 0, false
	sendTelemetry(dt, heli.rotor, heli.collective, heli.rotor)
	Haptics.set("vt_ride", Enum.VibrationMotor.Small, heli.rotor * 0.08)
	label.Text = string.format(
		"UH-34D  %d °C  rotor %3.0f%%\nvelocidade %3.0f nós  altura %4.0f m  subida %+.1f m/s\npotência %4.0f/%4.0f hp (exige %4.0f)  torque %3.0f%%%s",
		AIR_C,
		heli.rotor * 100,
		V * 1.9438,
		math.max(gearH, 0),
		heli.vy,
		pDemand / 745.7,
		pAvail / 745.7,
		pReq / 745.7,
		torque * 100,
		if heli.rotor < 1 and heli.rotor > 0
			then "\nrotor acelerando…"
			elseif pReq > pAvail then "\nSEM POTÊNCIA PARA PAIRAR: corra para ganhar sustentação"
			else ""
	)
end

local state = {
	driving = nil :: Model?,
	seatNow = nil :: Seat?,
	zoom = 0, -- 0 nenhum, 1 ótica/zoom, 2 binóculo
}

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

local function leaveDriver()
	if not state.driving then
		return
	end
	state.driving = nil
	VehicleLive.drive.model = nil
	Haptics.set("vt_ride", nil, nil)
	ctl.yaw = nil
	ctl.drive = VehicleDrive.newState()
	ctl.thr, ctl.steer = 0, 0
end

RunService.Heartbeat:Connect(function(dt: number)
	local seat = currentSeat()
	local model = seat and vehicleOf(seat)
	if not seat or not model or model:GetAttribute("Destroyed") then
		if state.seatNow then
			state.seatNow = nil
			Input.setVehicle(nil, nil)
			camera.FieldOfView = Input.settings.fov
		end
		leaveDriver()
		state.zoom = 0
		label.Visible = false
		return
	end
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local spec = Vehicles.SPECS[model:GetAttribute("Spec") :: string]
	if not chassis or not spec then
		return
	end
	if seat ~= state.seatNow then
		state.seatNow = seat
		state.zoom = 0
		Input.setVehicle(if spec.kind == "heli" then "helicopter" else "ground_vehicle", seatRole(seat, spec))
	end
	-- FOV no veículo: ótica do atirador ~20°, binóculo do comandante 10°, zoom leve da porta 50°
	local target = if state.zoom == 2
		then 10
		elseif state.zoom == 1 then (if seat:GetAttribute("Weapon") == "m60" then 50 else 20)
		else Input.settings.fov
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 8)
	label.Visible = true
	if seat:GetAttribute("SeatId") == "driver" then
		if state.driving ~= model then
			leaveDriver()
			state.driving = model
			heli.vel = Vector3.zero
			heli.vy = 0
			heli.yawRate = 0
			heli.pitch, heli.pitchV, heli.roll, heli.rollV = 0, 0, 0, 0
			-- rotor já girando (troca de piloto no ar): continua de onde os outros veem
			local net = model:GetAttribute("NetRotor")
			heli.rotor = if type(net) == "number" then net else 0
		end
		if spec.kind == "heli" then
			heliStep(model, chassis, dt)
		else
			groundStep(model, chassis, spec, dt)
		end
	else
		leaveDriver()
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

-- ===== câmera: balanço e tremor =====
-- A câmera do Roblox lê a própria direção a cada quadro (CameraLook): um giro deixado nela acumula.
-- Por isso o deslocamento é desfeito antes da câmera (Camera − 1) e refeito depois (Camera + 3, depois
-- do CameraLook e do ThirdPerson).
local cam = {
	applied = CFrame.identity,
	slowP = 0, -- média lenta da inclinação: ladeira parada não entorta a vista, só o balanço
	slowR = 0,
	t = 0,
	model = nil :: Model?,
}

RunService:BindToRenderStep("VT65VehicleCamUndo", Enum.RenderPriority.Camera.Value - 1, function()
	if cam.applied ~= CFrame.identity then
		camera.CFrame = camera.CFrame * cam.applied:Inverse()
		cam.applied = CFrame.identity
	end
end)

RunService:BindToRenderStep("VT65VehicleCam", Enum.RenderPriority.Camera.Value + 3, function(dt: number)
	local seat = currentSeat()
	local model = seat and vehicleOf(seat)
	local chassis = model and model:FindFirstChild("Chassis") :: BasePart?
	if not (seat and model and chassis) or camera.CameraType ~= Enum.CameraType.Custom then
		cam.model = nil
		return
	end
	cam.t += dt
	local cf = chassis.CFrame
	local view = VehicleLive.view
	local fresh = view.model == model
	local p = math.asin(math.clamp(cf.LookVector.Y, -1, 1)) + (if fresh then view.pitch else 0)
	local r = math.asin(math.clamp(cf.RightVector.Y, -1, 1)) + (if fresh then view.roll else 0)
	if cam.model ~= model then
		cam.model = model
		cam.slowP, cam.slowR = p, r
	end
	cam.slowP = approach(cam.slowP, p, 1.2, dt)
	cam.slowR = approach(cam.slowR, r, 1.2, dt)
	local driver = seat:GetAttribute("SeatId") == "driver"
	local k = (if driver then 1 else 0.45) * (if state.zoom > 0 then 0.25 else 1)
	local heliKind = model:GetAttribute("Kind") == "heli"
	local speed = chassis.AssemblyLinearVelocity.Magnitude * M
	local sp, sy, sr, bob
	if heliKind then
		-- rotor: arrepio contínuo e o tremor da sustentação de translação (~6–14 m/s)
		local etl = math.clamp(1 - math.abs(speed - 10) / 5, 0, 1)
		sp, sy, sr, bob = VehicleDrive.shake(cam.t, 8 * etl, 0.6 * etl + 0.1, view.rotor * 2.5)
	else
		sp, sy, sr, bob = VehicleDrive.shake(cam.t, speed, if fresh then view.rough else 0.4, view.rpm)
	end
	local follow = 0.6 * k -- quanto da inclinação dinâmica a vista acompanha
	local w = CFrame.fromAxisAngle(cf.RightVector, (p - cam.slowP) * follow)
		* CFrame.fromAxisAngle(-cf.LookVector, (r - cam.slowR) * follow)
	local rot = camera.CFrame.Rotation
	local off = rot:Inverse() * w * rot * CFrame.new(0, bob * k / M, 0) * CFrame.Angles(sp * k, sy * k, sr * k)
	camera.CFrame = camera.CFrame * off
	cam.applied = off
end)

-- ===== armas e ações dos assentos (camada Input) =====
local fire = { on = false }
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
	fire.on = true
	local wp = Weapons.get("m60")
	local interval = 60 / ((wp and wp.rpm) or 550)
	local seat = currentSeat()
	task.spawn(function()
		while fire.on and currentSeat() == seat do
			fireOnce(extra)
			task.wait(interval)
		end
	end)
end
local function stopFire()
	fire.on = false
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
	state.zoom = 1
end)
Input.on("v_optic", "release", function()
	state.zoom = 0
end)
-- comandante: LT binóculo, RB marca o alvo para o atirador
Input.on("v_binoculars", "press", function()
	state.zoom = 2
end)
Input.on("v_binoculars", "release", function()
	state.zoom = 0
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
	ctl.pedalL = true
end)
Input.on("h_pedal_left", "release", function()
	ctl.pedalL = false
end)
Input.on("h_pedal_right", "press", function()
	ctl.pedalR = true
end)
Input.on("h_pedal_right", "release", function()
	ctl.pedalR = false
end)
Input.on("h_stabilize", "holdStart", function()
	ctl.stabilize = true
end)
Input.on("h_stabilize", "holdEnd", function()
	ctl.stabilize = false
end)
Input.on("h_stabilize", "press", function() -- R no teclado: alterna
	ctl.stabilize = not ctl.stabilize
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
	fire.on = false
	ctl.pedalL, ctl.pedalR, ctl.stabilize = false, false, false
end)
