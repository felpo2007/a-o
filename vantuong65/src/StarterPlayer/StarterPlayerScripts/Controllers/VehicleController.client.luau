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
local Bus = require(script.Parent.Bus)
local Haptics = require(script.Parent.Haptics)
local Input = require(script.Parent.Input)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Net = require(ReplicatedStorage.Shared.Net)
local VehicleDrive = require(ReplicatedStorage.Shared.VehicleDrive)
local VehicleHudView = require(script.Parent.VehicleHudView)
local VehicleLive = require(script.Parent.VehicleLive)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local ViewMode = require(script.Parent.ViewMode)
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

-- nome do assento no painel (o SeatId é interno)
local SEAT_PT: { [string]: string } = {
	driver = "Motorista",
	gunner = "Atirador",
	commander = "Comandante",
	loader = "Municiador",
	copilot = "Copiloto",
}

-- painel de época do veículo (VehicleHudView): este script só calcula e passa os números
local Hud = VehicleHudView.new()

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
	stepT = 0, -- próxima sonda de degrau à frente
	stepM = nil :: number?, -- degrau à frente (m)
	climbUntil = 0,
	devInfo = false, -- Studio: workspace "VT65DevMov" = "veiculo"
	devAt = 0,
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

-- Degrau à frente da lagarta (m, + = sobe), no sentido do movimento: o chão logo depois da ponta da
-- rampa menos o chão debaixo da ponta do casco. nil se algum raio não achou chão.
local function stepAhead(chassis: BasePart, yaw: number, dirSign: number): number?
	local fwd = CFrame.Angles(0, yaw, 0).LookVector * dirSign
	local fromY = chassis.Position.Y - chassis.Size.Y / 2 + 1.2 / M
	local function groundY(dist: number): number?
		local p = chassis.Position + fwd * dist
		local r = workspace:Raycast(Vector3.new(p.X, fromY, p.Z), Vector3.new(0, -3 / M, 0), rays.solid)
		return if r then r.Position.Y else nil
	end
	local half = chassis.Size.Z / 2
	local here = groundY(half * 0.7)
	if not here then
		return nil
	end
	local best: number? = nil
	for _, extra in { 0.6, 1.2 } do
		local y = groundY(half + extra / M + 1.6) -- 1,6 stud: a rampa passa da ponta do casco
		if y then
			best = math.max(best or -math.huge, (y - here) * M)
		end
	end
	return best
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
	-- pedal e volante têm curso: tecla sobe em ~0,22 s e solta em ~0,15 s; analógico quase direto
	-- (D-93: o teclado subia em 0,3 s e o volante em 0,22 s; somado ao motor, a resposta atrasava)
	local pad = Input.isGamepad()
	ctl.thr =
		slew(ctl.thr, throttle, if math.abs(throttle) > math.abs(ctl.thr) then (if pad then 8 else 4.5) else 7, dt)
	ctl.steer = slew(ctl.steer, steer, if pad then 12 else 6, dt)
	prepRays(model)
	ctl.probeT -= dt
	if ctl.probeT <= 0 then
		ctl.probeT = 0.1
		local g, depth = VehicleLive.probe(chassis)
		ctl.ground, ctl.depth = g, depth
	end
	local _, cy, _ = chassis.CFrame:ToOrientation()
	local yaw = ctl.yaw or cy
	-- D-93: o casco não acompanhou o giro (encostado em árvore, casa ou outro veículo). O comando
	-- seguia somando e o AlignOrientation torcia o chassi de uma vez quando ele soltava ("travava" e
	-- depois dava um tranco). Agora o comando fica a no máximo 12° do giro real.
	local lag = (yaw - cy + math.pi) % (2 * math.pi) - math.pi
	if math.abs(lag) > math.rad(12) then
		yaw = cy + math.sign(lag) * math.rad(12)
		ctl.drive.yawRate *= 0.5
	end
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
	-- contato: parede, barranco ou outro veículo seguram o chassi; o modelo acompanha a velocidade real.
	-- Degrau baixo à frente (dique): a lagarta continua empurrando até a rampa subir (D-93).
	local flat = CFrame.Angles(0, yaw, 0)
	local vel = chassis.AssemblyLinearVelocity * M
	if not d.floating then
		local measured = Vector3.new(vel.X, 0, vel.Z):Dot(flat.LookVector) / math.max(math.cos(ctl.pitch), 0.5)
		local now = os.clock()
		if math.abs(d.v) > 0.5 and now >= ctl.stepT then
			ctl.stepT = now + 0.1
			local h = stepAhead(chassis, yaw, if d.v >= 0 then 1 else -1)
			ctl.stepM = h
			if h and h > 0.08 and h <= VehicleDrive.CLIMB_STEP_M then
				ctl.climbUntil = now + 1.5 -- a frente já em cima: segue valendo até o casco passar
			end
		end
		VehicleDrive.contact(d, measured, dt, now < ctl.climbUntil)
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
	Hud.ground({
		name = spec.name,
		kmh = d.v * 3.6,
		gear = if d.gear < 0 then "ré" elseif d.gear == 0 then "neutro" else string.format("%dª", d.gear),
		rpm = d.rpm,
		ground = GROUND_PT[ctl.ground] or ctl.ground,
		note = if d.floating then "boiando" elseif d.slip > 0.5 then "patinando" else nil,
		integrity = model:GetAttribute("Integrity") :: number?,
		engine = model:GetAttribute("Engine") :: number?,
		tracks = model:GetAttribute("Tracks") :: number?,
	})
	if ctl.devInfo and os.clock() >= ctl.devAt then
		ctl.devAt = os.clock() + 0.5
		print(
			string.format(
				"[VT65 VEÍCULO] %s: %.0f km/h no comando, %.0f km/h real | marcha %d, rotação %.2f | chão %s, rampa %.0f° | degrau à frente %s%s | patinando %.2f",
				spec.name,
				d.v * 3.6,
				Vector3.new(vel.X, 0, vel.Z).Magnitude * 3.6,
				d.gear,
				d.rpm,
				ctl.ground,
				math.deg(ctl.pitch),
				if ctl.stepM then string.format("%.2f m", ctl.stepM :: number) else "—",
				if os.clock() < ctl.climbUntil then " (subindo)" else "",
				d.slip
			)
		)
	end
end

-- Só no Studio: workspace:SetAttribute("VT65DevMov", "veiculo") liga/desliga a leitura do motorista no
-- Output a cada 0,5 s (velocidade no comando e real, marcha, chão, rampa, degrau à frente). Para levar
-- o veículo até um dique: "dique" (Movement.client). Para sentar no motorista: "VT65DevDrive".
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevMov"):Connect(function()
		if workspace:GetAttribute("VT65DevMov") == "veiculo" then
			ctl.devInfo = not ctl.devInfo
			print("[VT65 VEÍCULO] leitura " .. (if ctl.devInfo then "ligada" else "desligada"))
			workspace:SetAttribute("VT65DevMov", nil) -- só local: no cliente o mesmo valor repete
		end
	end)
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
	-- o rotor acelerando aparece na linha de baixo (rotor %); o aviso vermelho é só falta de potência
	-- com o rotor já em rotação de voo
	Hud.heli({
		name = "UH-34D",
		tempC = AIR_C,
		rotor = heli.rotor,
		knots = V * 1.9438,
		altM = math.max(gearH, 0),
		climb = heli.vy,
		demandHp = pDemand / 745.7,
		availHp = pAvail / 745.7,
		reqHp = pReq / 745.7,
		torque = torque,
		warn = if heli.rotor >= 1 and pReq > pAvail
			then "SEM POTÊNCIA PARA PAIRAR: corra para ganhar sustentação"
			else nil,
	})
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
		Hud.hide()
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
		local seatId = tostring(seat:GetAttribute("SeatId"))
		local seatName = if spec.kind == "heli" and seatId == "gunner"
			then "Porta"
			elseif string.match(seatId, "^p%d+$") then "Passageiro"
			else SEAT_PT[seatId] or seatId
		Hud.seat({
			name = spec.name,
			seat = seatName,
			weapon = if type(w) == "string" then w else nil,
			ammo = if w == "gun_90" then string.upper(tostring(model:GetAttribute("Ammo") or "he")) else nil,
			fire = fireTxt,
			tubes = if w == "rr_106" then (model:GetAttribute("Tubes") :: number?) or 0 else nil,
		})
	end
end)

-- ===== vista de quem está sentado =====
-- A malha do veículo só tem faces de fora: com o olho dentro dela (a cabeça do personagem sentado) o
-- casco some e o jogador flutua no capim (teste no Studio, 2026-11-11). Então:
--   - 1ª pessoa: o olho vai para o ponto do assento FORA da malha (VehicleDrive.eyeOf): cabeça para
--     fora da escotilha nos blindados (vê a borda do casco e o tubo), cabine e porta no UH-34D; a
--     ótica do atirador, o binóculo do comandante e a cabine do piloto ganham moldura na tela;
--   - 3ª pessoa (Input.settings.thirdPerson, se o modo deixa): câmera de perseguição atrás do
--     veículo, girada pelo olhar do jogador, encurtada por parede e terreno; ótica e binóculo voltam
--     à 1ª pessoa;
--   - nos dois, balanço com a carroceria e tremor pela velocidade, chão e motor.
-- A câmera do Roblox lê a própria direção a cada quadro (CameraLook): um giro deixado nela acumula.
-- Por isso o deslocamento é desfeito antes da câmera (Camera − 1) e refeito depois (Camera + 3, depois
-- do CameraLook e do ThirdPerson). O corpo do próprio personagem fica escondido (só ele vê).
local cam = {
	applied = CFrame.identity,
	slowP = 0, -- média lenta da inclinação: ladeira parada não entorta a vista, só o balanço
	slowR = 0,
	t = 0,
	model = nil :: Model?,
	blend = 0, -- 0 olho, 1 perseguição
	boom = -1, -- distância livre da perseguição (studs)
	body = {} :: { Instance },
	bodyOf = nil :: Model?,
	bodyT = 0,
	chaseAttr = false,
	aimAttr = false,
}

-- molduras na tela (atrás do painel do veículo)
local sight = Instance.new("ScreenGui")
sight.Name = "VehicleSight"
sight.ResetOnSpawn = false
sight.IgnoreGuiInset = true
sight.DisplayOrder = -1
sight.Parent = player:WaitForChild("PlayerGui")
local overlay = {
	reticle = Instance.new("Frame"),
	optic = Instance.new("Frame"),
	binoc = Instance.new("Frame"),
	cockpit = Instance.new("Frame"),
}
local overlayList: { Frame } = { overlay.reticle, overlay.optic, overlay.binoc, overlay.cockpit }
for _, f in overlayList do
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.Visible = false
	f.Parent = sight
end
local function bar(parent: Instance, pos: UDim2, size: UDim2, color: Color3, alpha: number, anchor: Vector2?): Frame
	local b = Instance.new("Frame")
	b.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	b.Position = pos
	b.Size = size
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.BackgroundTransparency = alpha
	b.Parent = parent
	return b
end
-- círculo vazado: o anel preto de borda enorme escurece tudo fora dele
local function porthole(parent: Instance, x: number, scale: number)
	local c = Instance.new("Frame")
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(x, 0.5)
	c.Size = UDim2.fromScale(scale, scale)
	c.BackgroundTransparency = 1
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = c
	local s = Instance.new("UIStroke")
	s.Thickness = 1600
	s.Color = Color3.new(0, 0, 0)
	s.Parent = c
	local r = Instance.new("UICorner")
	r.CornerRadius = UDim.new(1, 0)
	r.Parent = c
	c.Parent = parent
end
do
	local ink = Color3.fromRGB(235, 228, 200)
	bar(overlay.reticle, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(14, 2), ink, 0.2)
	bar(overlay.reticle, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(2, 14), ink, 0.2)
	-- ótica: campo redondo, retícula fina com marcas de distância abaixo do centro
	porthole(overlay.optic, 0.5, 0.86)
	local black = Color3.new(0, 0, 0)
	bar(overlay.optic, UDim2.fromScale(0.5, 0.5), UDim2.new(0.34, 0, 0, 1), black, 0.1)
	bar(overlay.optic, UDim2.fromScale(0.5, 0.5), UDim2.new(0, 1, 0.5, 0), black, 0.1)
	for i = 1, 4 do
		bar(overlay.optic, UDim2.new(0.5, 0, 0.5, i * 34), UDim2.fromOffset(28 - i * 4, 1), black, 0.1)
	end
	-- binóculo: dois campos
	porthole(overlay.binoc, 0.4, 0.62)
	porthole(overlay.binoc, 0.6, 0.62)
	-- cabine: teto, montantes do para-brisa e o painel embaixo
	local frame = Color3.fromRGB(38, 40, 32)
	bar(overlay.cockpit, UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.09), frame, 0.05, Vector2.new(0.5, 0))
	bar(overlay.cockpit, UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.17), frame, 0.05, Vector2.new(0.5, 1))
	bar(overlay.cockpit, UDim2.fromScale(0.5, 0.45), UDim2.new(0, 10, 0.8, 0), frame, 0.1)
	for _, x in { 0.07, 0.93 } do
		local post = bar(overlay.cockpit, UDim2.fromScale(x, 0.45), UDim2.new(0, 22, 0.9, 0), frame, 0.05)
		post.Rotation = if x < 0.5 then 8 else -8
	end
end

local function setLocalAttr(name: string, value: boolean, field: string)
	if (cam :: any)[field] ~= value then
		(cam :: any)[field] = value
		player:SetAttribute(name, value)
	end
end

-- o próprio corpo (e o fuzil que ele carrega) some para quem está sentado: a câmera não fica mais na
-- cabeça e o boneco apareceria cortado pelo casco
local function hideBody(char: Model)
	if cam.bodyOf ~= char or os.clock() - cam.bodyT > 2 then
		cam.bodyOf, cam.bodyT = char, os.clock()
		cam.body = {}
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				table.insert(cam.body, d)
			end
		end
	end
	for _, d in cam.body do
		if d:IsA("BasePart") then
			if d.LocalTransparencyModifier ~= 1 then
				d.LocalTransparencyModifier = 1
			end
		elseif d:IsA("Decal") and d.LocalTransparencyModifier ~= 1 then
			d.LocalTransparencyModifier = 1
		end
	end
end

local function rayList(model: Model): { Instance }
	local list: { Instance } = { model }
	for _, inst in
		{ player.Character, workspace:FindFirstChild("VT65VehicleFx"), workspace:FindFirstChild("VT65Effects") }
	do
		if inst then
			table.insert(list, inst)
		end
	end
	return list
end

local function offAll()
	for _, f in overlayList do
		f.Visible = false
	end
	setLocalAttr("VehicleChase", false, "chaseAttr")
	setLocalAttr("VehicleAim", false, "aimAttr")
end

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
		if cam.model then
			cam.model = nil
			cam.blend, cam.boom = 0, -1
			offAll()
		end
		return
	end
	if player.Character then
		hideBody(player.Character)
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
		cam.boom = -1
	end
	cam.slowP = approach(cam.slowP, p, 1.2, dt)
	cam.slowR = approach(cam.slowR, r, 1.2, dt)
	local seatId = tostring(seat:GetAttribute("SeatId"))
	local weapon = seat:GetAttribute("Weapon")
	local heliKind = model:GetAttribute("Kind") == "heli"
	local chase = Input.settings.thirdPerson and ViewMode.allowed() and state.zoom == 0
	cam.blend = approach(cam.blend, if chase then 1 else 0, 0.16, dt)
	local b = cam.blend * cam.blend * (3 - 2 * cam.blend)
	local rot = camera.CFrame.Rotation
	-- olho do assento (fora da malha), com a mola da carroceria
	local eye = camera.CFrame.Position
	local ex, ey, ez = VehicleDrive.eyeOf(tostring(model:GetAttribute("Spec")), seatId)
	if fresh and view.meshRel and ex and ey and ez then
		local s = view.scale
		eye = (cf * (view.meshRel :: CFrame) * CFrame.new(ex * s.X, ey * s.Y, ez * s.Z)).Position
	end
	local pos = eye
	if b > 0.001 then
		local dist, lift = VehicleDrive.chaseOf(if heliKind then "heli" else "ground", chassis.Size.Z + 3.2)
		local pivot = chassis.Position + Vector3.new(0, chassis.Size.Y / 2 + lift, 0)
		local want = -rot.LookVector * dist + Vector3.new(0, dist * 0.1, 0)
		local hit = workspace:Raycast(pivot, want, VehicleLive.solid(rayList(model)))
		local free = if hit then math.max((hit.Position - pivot).Magnitude - 1.5, 3) else want.Magnitude
		cam.boom = if cam.boom < 0 or free < cam.boom then free else approach(cam.boom, free, 0.5, dt)
		pos = eye:Lerp(pivot + want.Unit * cam.boom, b)
	end
	-- balanço e tremor (menores na perseguição e com zoom)
	local driver = seatId == "driver"
	local k = (if driver then 1 else 0.45) * (if state.zoom > 0 then 0.25 else 1) * (1 - 0.7 * b)
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
	local target = CFrame.new(pos) * w * rot * CFrame.new(0, bob * k / M, 0) * CFrame.Angles(sp * k, sy * k, sr * k)
	local off = camera.CFrame:Inverse() * target
	camera.CFrame = target
	cam.applied = off
	-- molduras: ótica (canhão), binóculo (comandante), cabine (pilotos, em 1ª pessoa); retícula de quem
	-- tem arma (na perseguição é por ela que se mira)
	local first = b < 0.5
	local bigGun = weapon == "gun_90" or weapon == "rr_106"
	overlay.optic.Visible = first and state.zoom == 1 and bigGun
	overlay.binoc.Visible = first and state.zoom == 2
	overlay.cockpit.Visible = first and heliKind and (seatId == "driver" or seatId == "copilot")
	-- a M60 em 1ª pessoa mira pela própria alça e massa (como a pé): retícula só na perseguição
	overlay.reticle.Visible = weapon ~= nil
		and not overlay.optic.Visible
		and not overlay.binoc.Visible
		and (not first or weapon ~= "m60")
	setLocalAttr("VehicleChase", not first, "chaseAttr")
	setLocalAttr("VehicleAim", first and state.zoom == 1 and weapon == "m60", "aimAttr")
end)

-- ===== armas e ações dos assentos (camada Input) =====
local fire = { on = false }

-- direção do tiro: em 1ª pessoa, a linha de visada; na perseguição, do assento até o ponto da retícula
local function aimDir(): Vector3
	local look = camera.CFrame.LookVector
	local seat = currentSeat()
	local model = seat and vehicleOf(seat)
	if cam.blend < 0.5 or not (seat and model) then
		return look
	end
	local origin = camera.CFrame.Position
	local hit = workspace:Raycast(origin, look * (1500 / M), VehicleLive.solid(rayList(model)))
	local at = if hit then hit.Position else origin + look * (1500 / M)
	local d = at - (seat.Position + Vector3.new(0, 2.5 / M, 0))
	return if d.Magnitude > 1 then d.Unit else look
end

local function fireOnce(extra: { [string]: any }?)
	local req: { [string]: any } = { dir = aimDir() }
	if extra then
		for k, v in extra do
			req[k] = v
		end
	end
	Net.event("Vehicle_Fire"):FireServer(req)
	local seat = currentSeat()
	if seat and seat:GetAttribute("Weapon") == "m60" and not (extra and extra.coax) then
		Bus.fire("vehicle_shot") -- coice e clarão na M60 do assento (WeaponVisuals)
	end
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
