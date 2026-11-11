--!strict
-- Olhar no analógico direito (Parte 12.4). A câmera padrão do Roblox deixa de receber o
-- Thumbstick2 (afundado via ContextActionService); aqui aplicamos zona morta radial, curva,
-- sensibilidade por modo e eixo, aceleração de giro e a assistência mínima. O módulo de câmera lê
-- a direção atual a cada quadro, então a rotação persiste (como o recuo do WeaponController).
-- Balanço, inércia e recuo são os mesmos do mouse: o controle não ganha estabilidade extra.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Smoke = require(ReplicatedStorage.Shared.Smoke)
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
local UserInputService = game:GetService("UserInputService")
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

RunService:BindToRenderStep("VT65_Look", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
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
	dyaw *= f
	dpitch *= f
	local cf = camera.CFrame
	local lv = cf.LookVector
	local yaw = math.atan2(-lv.X, -lv.Z) - math.rad(dyaw)
	local pitch = math.clamp(math.asin(math.clamp(lv.Y, -1, 1)) + math.rad(dpitch), math.rad(-80), math.rad(80))
	camera.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(pitch, yaw, 0)
end)
