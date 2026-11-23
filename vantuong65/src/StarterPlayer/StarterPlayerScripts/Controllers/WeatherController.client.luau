--!strict
-- Chuva tropical (Parte 11): partículas de chuva em volta da câmera, na intensidade que o servidor
-- publica (ReplicatedStorage.Rain, 0..1). A névoa vem do servidor (LightingService); os passos
-- abafados, do AudioController; a visão dos bots, do BotService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bus = require(script.Parent.Bus)

local camera = workspace.CurrentCamera
local M = 0.28

local box = Instance.new("Part")
box.Name = "VT65Rain"
box.Anchored, box.CanCollide, box.CanQuery, box.CanTouch = true, false, false, false
box.Transparency = 1
box.Size = Vector3.new(60 / M, 1, 60 / M) -- chuva num quadrado de 60 m em volta de quem olha
box.Parent = workspace

local drops = Instance.new("ParticleEmitter")
drops.Shape = Enum.ParticleEmitterShape.Box
drops.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
drops.EmissionDirection = Enum.NormalId.Bottom
drops.Speed = NumberRange.new(28 / M, 32 / M) -- ~9 m/s, gota grande de pancada tropical
drops.Lifetime = NumberRange.new(1.2, 1.6)
drops.Size = NumberSequence.new(0.06 / M)
drops.Squash = NumberSequence.new(-2.5) -- esticada na direção da queda
drops.Transparency = NumberSequence.new(0.45)
drops.Color = ColorSequence.new(Color3.fromRGB(200, 205, 210))
drops.LightEmission = 0
drops.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
drops.Rate = 0
drops.Parent = box

local warned = false
local function apply()
	local v = ReplicatedStorage:GetAttribute("Rain")
	local i = if type(v) == "number" then v else 0
	drops.Rate = 1500 * i
	if i >= 0.5 and not warned then
		warned = true
		Bus.fire("toast", "Pancada de chuva: visão curta e passos abafados")
	elseif i == 0 then
		warned = false
	end
end
ReplicatedStorage:GetAttributeChangedSignal("Rain"):Connect(apply)
apply()

RunService.RenderStepped:Connect(function()
	if drops.Rate > 0 then
		box.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 14 / M, 0))
	end
end)
