--!strict
-- Olhar no analógico direito (Parte 12.4). A câmera padrão do Roblox deixa de receber o
-- Thumbstick2 (afundado via ContextActionService); aqui aplicamos zona morta radial, curva,
-- sensibilidade por modo e eixo, aceleração de giro e a assistência mínima. O módulo de câmera lê
-- a direção atual a cada quadro, então a rotação persiste (como o recuo do WeaponController).
-- Balanço, inércia e recuo são os mesmos do mouse: o controle não ganha estabilidade extra.
-- Parte 13 (toque): o arrasto na metade da câmera (e no botão de tiro) chega do ToqueHud por
-- Input.addLook; o giroscópio (modos desligado / só mirando / sempre) soma por cima. Conta no
-- Shared/Toque (mm do dedo, sensibilidades separadas de olhar, ferro, luneta e giroscópio,
-- aceleração opcional, inverter Y); a assistência mínima vale igual à do controle.
-- Studio: workspace:SetAttribute("VT65DevToque", "giro:5,2") gira 5° para a direita e 2° para cima
-- como se o aparelho tivesse girado (passa pelo modo e pela sensibilidade do giroscópio).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Smoke = require(ReplicatedStorage.Shared.Smoke)
local Toque = require(ReplicatedStorage.Shared.Toque)
local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local look = { edgeT = 0 }

ContextActionService:BindActionAtPriority("VT65_LookStick", function()
	return Enum.ContextActionResult.Sink
end, false, 3000, Enum.KeyCode.Thumbstick2)

local function enemies(): { Model }
	local mine = player:GetAttribute("Faction")
	local out = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if p ~= player and c and c:GetAttribute("Faction") ~= mine then
			table.insert(out, c)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Faction") ~= mine then
				table.insert(out, m)
			end
		end
	end
	return out
end

-- Fator de desaceleração pelo alvo mais alinhado; só consulta visibilidade de um candidato.
local function assist(mode: string): number
	if Input.settings.aimAssist ~= "minimal" or mode == "hip" then
		return 1
	end
	local cf = camera.CFrame
	local best: BasePart? = nil
	local bestAng, bestDist = math.huge, 0
	for _, m in enemies() do
		local hum = m:FindFirstChildOfClass("Humanoid")
		local torso = (m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if hum and hum.Health > 0 and torso then
			local v = torso.Position - cf.Position
			local dist = v.Magnitude * M
			if dist <= InputMap.ASSIST_RANGE_M and dist > 0 then
				local ang = math.deg(math.acos(math.clamp(cf.LookVector:Dot(v.Unit), -1, 1)))
				if ang < bestAng then
					best, bestAng, bestDist = torso, ang, dist
				end
			end
		end
	end
	if not best then
		return 1
	end
	-- visível de verdade: raio da câmera até o alvo (vegetação, parede) e fumaça
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local target = best :: BasePart
	local hit = workspace:Raycast(cf.Position, target.Position - cf.Position, params)
	local model = target:FindFirstAncestorOfClass("Model")
	local visible = hit ~= nil and model ~= nil and hit.Instance:IsDescendantOf(model)
	if visible then
		local p = target.Position
		visible = not Smoke.blocks(
			cf.Position.X,
			cf.Position.Y,
			cf.Position.Z,
			p.X,
			p.Y,
			p.Z,
			Smoke.clouds(workspace:FindFirstChild("Smoke"))
		)
	end
	return InputMap.assistFactor(Input.settings.aimAssist, mode, bestDist, bestAng, visible, 0.3)
end

-- D-82: sensibilidade do mouse do jogo, por modo (quadril, mira de ferro, luneta), por cima da
-- sensibilidade do Roblox. O módulo de câmera padrão lê o delta já escalado.
local lastMouse = -1
local function mouseSens()
	local s = Input.settings
	local k = s.mouseSens
	if Input.aimMode == "ads" then
		k *= s.mouseAds
	elseif Input.aimMode == "scope" then
		k *= s.mouseScope
	end
	if math.abs(k - lastMouse) > 1e-4 then
		lastMouse = k
		UserInputService.MouseDeltaSensitivity = k
	end
end

-- gira a câmera (graus: direita e para cima), preso a ±80° de arfagem
local function turn(dyaw: number, dpitch: number)
	local cf = camera.CFrame
	local lv = cf.LookVector
	local yaw = math.atan2(-lv.X, -lv.Z) - math.rad(dyaw)
	local pitch = math.clamp(math.asin(math.clamp(lv.Y, -1, 1)) + math.rad(dpitch), math.rad(-80), math.rad(80))
	camera.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(pitch, yaw, 0)
end

-- ===== giroscópio (Parte 13) =====
-- Só ligado com o toque ativo, o modo diferente de "off" e o aparelho com giroscópio (bateria).
-- O giro entre duas leituras vira ângulos XYZ (atual * anterior:Inverse(), como o exemplo do
-- DeviceRotationChanged); deitado para o outro lado (a gravidade diz) inverte.
local gyro = {
	conn = nil :: RBXScriptConnection?,
	last = nil :: CFrame?,
	rx = 0,
	ry = 0,
	flip = false,
	flipAt = 0,
	dev = false, -- Studio: giro injetado pelo VT65DevToque (sem aparelho)
}

local function gyroWanted(): boolean
	local ok, has = pcall(function()
		return UserInputService.GyroscopeEnabled
	end)
	return Input.touchActive() and Input.settings.gyroMode ~= "off" and ok and has == true
end

local function syncGyro()
	local want = gyroWanted()
	local conn = gyro.conn
	if want and not conn then
		gyro.last = nil
		gyro.conn = UserInputService.DeviceRotationChanged:Connect(function(_r: InputObject, cf: CFrame)
			local last = gyro.last
			gyro.last = cf
			if last then
				local x, y = (cf * last:Inverse()):ToEulerAnglesXYZ()
				gyro.rx += x
				gyro.ry += y
			end
		end)
	elseif not want and conn then
		conn:Disconnect()
		gyro.conn = nil
		gyro.rx, gyro.ry = 0, 0
	end
end
Input.SettingsChanged:Connect(syncGyro)
Input.DeviceChanged:Connect(syncGyro)
task.defer(syncGyro)

local function refreshFlip(now: number)
	if now < gyro.flipAt then
		return
	end
	gyro.flipAt = now + 0.5
	pcall(function()
		local g = UserInputService:GetDeviceGravity().Position
		gyro.flip = g.X < -0.5 or g.Z > 0.5
	end)
end

-- Toque: arrasto + giroscópio, com a sensibilidade do modo e a assistência mínima.
local function touchLook(dt: number)
	local d = Input.takeLook()
	local gx, gy = gyro.rx, gyro.ry
	gyro.rx, gyro.ry = 0, 0
	local ctx = Input.context()
	if
		ctx == "map"
		or ctx == "menu"
		or ctx == "wheel"
		or Input.state.disconnected
		or Input.state.robloxMenu
		or Input.state.unfocused
	then
		return
	end
	local s = Input.settings :: any
	local mode = Input.aimMode
	local vp = camera.ViewportSize
	local dpi = Toque.dpiGuess(math.min(vp.X, vp.Y))
	local yaw, pitch = Toque.lookDelta(d.X, d.Y, dt, dpi, s, mode)
	if gyro.conn or gyro.dev then
		if gyro.conn then
			refreshFlip(os.clock())
		end
		gyro.dev = false
		local gyaw, gpitch = Toque.gyroStep(gx, gy, gyro.conn ~= nil and gyro.flip, s, mode)
		yaw += gyaw
		pitch += gpitch
	end
	if yaw == 0 and pitch == 0 then
		return
	end
	local f = assist(mode)
	turn(yaw * f, pitch * f)
end

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevToque"):Connect(function()
		local v = workspace:GetAttribute("VT65DevToque")
		if type(v) ~= "string" then
			return
		end
		local yaw, pitch = string.match(v, "^giro:([%-%d%.]+),([%-%d%.]+)$")
		local ny, np = tonumber(yaw), tonumber(pitch)
		if ny and np then
			-- passa pelo modo e pela sensibilidade como se viesse do aparelho (flip desligado)
			gyro.rx += math.rad(np)
			gyro.ry += math.rad(ny)
			gyro.dev = true
			print(
				string.format(
					"[VT65 TOQUE] giro simulado: modo %s, sensibilidade %.2f, toque %s, mira %s",
					tostring(Input.settings.gyroMode),
					Input.settings.gyroSens,
					tostring(Input.touchActive()),
					Input.aimMode
				)
			)
		end
	end)
end

RunService:BindToRenderStep("VT65_Look", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	if Input.touchActive() then
		touchLook(dt)
		return
	end
	if not Input.isGamepad() then
		mouseSens()
		return
	end
	local ctx = Input.context()
	if ctx == "map" or ctx == "menu" or ctx == "wheel" or Input.state.disconnected or Input.state.robloxMenu then
		look.edgeT = 0
		return
	end
	local r = Input.stickRaw("right")
	local mode = Input.aimMode
	local dyaw, dpitch = InputMap.lookStep(r.X, r.Y, dt, Input.settings, mode, look)
	if dyaw == 0 and dpitch == 0 then
		return
	end
	local f = assist(mode)
	turn(dyaw * f, dpitch * f)
end)
