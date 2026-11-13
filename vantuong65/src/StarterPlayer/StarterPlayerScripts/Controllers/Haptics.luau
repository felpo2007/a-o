--!strict
-- Vibração (Parte 12.6). Respeita a intensidade do jogador (desligada, baixa, normal; separada
-- para disparo e para dano) e confere IsMotorSupported antes de cada motor. Explosões usam
-- HapticEffect quando o tipo existe. Motores de gatilho só se o controle disser que suporta.
-- Celular (Parte 13): HapticService:SetMotor é do controle; no celular quem vibra é o HapticEffect
-- (instância nova do Roblox: celulares Android e iOS com vibração, controles PlayStation e Xbox, Quest;
-- controle ligado ao celular não vibra). Só pulsos, pelas regras do Aparelho (testadas no Lune):
-- disparo leve, atingido forte, explosão forte e caindo com a distância; intervalo mínimo por tipo;
-- nada contínuo (motor, rotor, batimento); economia de bateria tira o pulso do disparo. Forma de onda
-- própria (Custom, tempo em ms, intensidade 0..1, abaixo de 0,1 alguns aparelhos não vibram); se o
-- aparelho recusar, cai para o tipo pronto (UIClick, GameplayCollision, GameplayExplosion); sem
-- HapticEffect, não vibra.
local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Aparelho = require(script.Parent.Aparelho)
local Input = require(script.Parent.Input)

local Haptics = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local PAD = Enum.UserInputType.Gamepad1

local LEVEL: { [string]: number } = { off = 0, low = 0.45, normal = 1 }

local function supported(motor: Enum.VibrationMotor): boolean
	local ok, v = pcall(function()
		return HapticService:IsMotorSupported(PAD, motor)
	end)
	return ok and v == true
end

-- camadas somadas por motor; cada pulso some sozinho
type Pulse = { motor: Enum.VibrationMotor, v: number, untilT: number }
local pulses: { Pulse } = {}
local continuous: { [string]: { motor: Enum.VibrationMotor, v: number } } = {}

local function add(motor: Enum.VibrationMotor, v: number, seconds: number)
	if v <= 0 or not Input.isGamepad() then
		return
	end
	table.insert(pulses, { motor = motor, v = math.clamp(v, 0, 1), untilT = os.clock() + seconds })
end

-- ===== celular: HapticEffect =====
local function touchOn(): boolean
	local f = (Input :: any).touchActive
	if type(f) == "function" then
		return f() == true
	end
	return Input.device() == "touch"
end

local touch = {
	fx = {} :: { [string]: any }, -- um efeito por tipo, reaproveitado
	last = {} :: { [string]: number }, -- hora do último pulso por tipo (Aparelho.gate)
	missing = false, -- este cliente não tem HapticEffect
	custom = true, -- a forma de onda própria funciona (senão, o tipo pronto)
}

local function effect(kind: string): any
	local fx = touch.fx[kind]
	if fx and fx.Parent then
		return fx
	end
	if touch.missing then
		return nil
	end
	local ok, made = pcall(function(): any
		local e = Instance.new("HapticEffect" :: any) :: any
		e.Name = string.format("VT65Vibra_%s", kind)
		e.Parent = workspace -- como nos exemplos da documentação
		return e
	end)
	if not ok then
		touch.missing = true
		return nil
	end
	touch.fx[kind] = made
	return made
end

-- kind: "fire" | "hit" | "explosion"; x: coice (graus) ou distância (m)
local function touchPulse(kind: string, level: string, x: number)
	if not touchOn() then
		return
	end
	local p = Aparelho.pulse(kind, level, x, (Input.settings :: any).batterySaver == true)
	if not p or not Aparelho.gate(touch.last, kind, os.clock()) then
		return
	end
	local fx = effect(kind)
	if not fx then
		return
	end
	local pulse = p :: Aparelho.Pulse
	if touch.custom then
		local ok = pcall(function()
			fx:Stop()
			fx.Type = (Enum :: any).HapticEffectType.Custom
			local key = (FloatCurveKey :: any).new
			local lin = Enum.KeyInterpolationMode.Linear
			fx:SetWaveformKeys({ key(0, pulse.amp, lin), key(pulse.ms, 0, lin) })
			fx:Play()
		end)
		if ok then
			return
		end
		touch.custom = false
	end
	pcall(function()
		fx:Stop()
		fx.Type = ((Enum :: any).HapticEffectType :: any)[pulse.preset]
		fx:Play()
	end)
end

-- disparo: proporcional ao recuo (kick em graus do WeaponController)
function Haptics.fire(kickDeg: number, auto: boolean)
	touchPulse("fire", Input.settings.hapticFire, kickDeg)
	local lv = LEVEL[Input.settings.hapticFire] or 1
	local v = math.clamp(kickDeg / 1.6, 0.15, 1) * lv
	add(Enum.VibrationMotor.Small, v, if auto then 0.05 else 0.08)
	add(Enum.VibrationMotor.Large, v * (if auto then 0.5 else 0.8), if auto then 0.06 else 0.12)
	if supported(Enum.VibrationMotor.RightTrigger) then
		add(Enum.VibrationMotor.RightTrigger, v * 0.6, 0.05)
	end
end

-- explosão perto: forte e caindo com a distância
function Haptics.explosion(distM: number)
	touchPulse("explosion", Input.settings.hapticDamage, distM)
	local lv = LEVEL[Input.settings.hapticDamage] or 1
	local v = math.clamp(1 - distM / 120, 0, 1) ^ 1.5 * lv
	if v <= 0 then
		return
	end
	add(Enum.VibrationMotor.Large, v, 0.25 + 0.4 * v)
	add(Enum.VibrationMotor.Small, v * 0.6, 0.15)
end

-- tiro recebido: vibra do lado do impacto (motores da mão esquerda/direita quando houver)
function Haptics.hit(fromPos: Vector3)
	touchPulse("hit", Input.settings.hapticDamage, 0)
	local lv = LEVEL[Input.settings.hapticDamage] or 1
	local rel = camera.CFrame:PointToObjectSpace(fromPos)
	local left = rel.X < 0
	local hand = if left then Enum.VibrationMotor.LeftHand else Enum.VibrationMotor.RightHand
	if supported(hand) then
		add(hand, 0.9 * lv, 0.18)
	else
		add(if left then Enum.VibrationMotor.Large else Enum.VibrationMotor.Small, 0.9 * lv, 0.18)
	end
end

-- contínuos: batimento (ferido grave), motor do veículo, rotor
function Haptics.set(name: string, motor: Enum.VibrationMotor?, v: number?)
	if motor and v and v > 0 then
		continuous[name] = { motor = motor, v = v }
	else
		continuous[name] = nil
	end
end

local heartbeatOn = false
local nextBeat = 0
local rotorOn = false
local nextRotor = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if heartbeatOn and now >= nextBeat then
		nextBeat = now + 0.85
		local lv = LEVEL[Input.settings.hapticDamage] or 1
		add(Enum.VibrationMotor.Large, 0.55 * lv, 0.08)
		task.delay(0.18, function()
			add(Enum.VibrationMotor.Large, 0.35 * lv, 0.07)
		end)
	end
	if rotorOn and now >= nextRotor then
		nextRotor = now + 0.25 -- ritmo das pás (PLACEHOLDER: ~4 Hz)
		add(Enum.VibrationMotor.Large, 0.25, 0.08)
	end
	local sum: { [Enum.VibrationMotor]: number } = {}
	local keep = {}
	for _, p in pulses do
		if p.untilT > now then
			table.insert(keep, p)
			sum[p.motor] = math.max(sum[p.motor] or 0, p.v)
		end
	end
	pulses = keep
	for _, c in continuous do
		sum[c.motor] = math.max(sum[c.motor] or 0, c.v)
	end
	for _, motor in
		{
			Enum.VibrationMotor.Large,
			Enum.VibrationMotor.Small,
			Enum.VibrationMotor.LeftHand,
			Enum.VibrationMotor.RightHand,
			Enum.VibrationMotor.RightTrigger,
		}
	do
		if supported(motor) then
			pcall(function()
				HapticService:SetMotor(PAD, motor, if Input.isGamepad() then sum[motor] or 0 else 0)
			end)
		end
	end
end)

-- ligações diretas com os eventos do jogo
Net.event("Combat_Hit").OnClientEvent:Connect(function(o)
	Haptics.hit(Vector3.new(o.x, o.y, o.z))
end)
Net.unreliable("Fire_Impact").OnClientEvent:Connect(function(e)
	local d = (Vector3.new(e.x, e.y, e.z) - camera.CFrame.Position).Magnitude * M
	Haptics.explosion(d)
	if d < 40 and Input.isGamepad() then
		pcall(function()
			local fx = Instance.new("HapticEffect")
			fx.Type = Enum.HapticEffectType.GameplayExplosion
			fx.Parent = camera
			fx:Play()
			task.delay(1, function()
				fx:Destroy()
			end)
		end)
	end
end)
-- tiro do canhão do próprio veículo (90 mm, 106 mm): o disparo de verdade, do servidor; quem está
-- sentado a menos de 12 m da boca sente (atirador e o resto da tripulação; o tubo do M48 tem ~5 m)
Net.unreliable("Fire_Launch").OnClientEvent:Connect(function(e)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and type(e) == "table" and type(e.x) == "number" and type(e.y) == "number" and type(e.z) == "number" then
		if (Vector3.new(e.x, e.y, e.z) - seat.Position).Magnitude * M < 12 then
			Haptics.fire(1.6, false)
		end
	end
end)
Net.event("Medical_State").OnClientEvent:Connect(function(st)
	-- D-99: com o sangramento ~5x mais lento, o coração bate com ferimento arterial ou caído
	heartbeatOn = st.arterial == true or player:GetAttribute("Downed") == true
end)

-- veículo: motor constante e suave; helicóptero transmite o ritmo do rotor
task.spawn(function()
	while true do
		task.wait(0.1)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		local model = seat and seat:FindFirstAncestorWhichIsA("Model")
		local kind = model and model:GetAttribute("Kind")
		rotorOn = kind == "heli"
		if kind and kind ~= "heli" and model then
			local chassis = model:FindFirstChild("Chassis") :: BasePart?
			local sp = if chassis then chassis.AssemblyLinearVelocity.Magnitude * M else 0
			Haptics.set("engine", Enum.VibrationMotor.Large, 0.08 + math.min(sp / 14, 1) * 0.12)
		else
			Haptics.set("engine", nil, nil)
		end
	end
end)

return Haptics
