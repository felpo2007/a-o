--!strict
-- D-241: dentro de casa, a chama do lampião respira e a poeira flutua na luz. Só os lampiões perto da
-- câmera: até 6 chamas e 4 nuvens de poeira, reaproveitadas. No detalhe baixo (Graficos) não há poeira.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Lampiao = require(ReplicatedStorage.Shared.LampiaoInterior)

local RAIO_CHAMA = 70
local RAIO_POEIRA = 36
local MAX_CHAMAS = 6
local MAX_POEIRA = 4

local player = Players.LocalPlayer
local pasta = Instance.new("Folder")
pasta.Name = "VT65PoeiraLocal"
pasta.Parent = workspace

type Nuvem = { parte: Part, emissor: ParticleEmitter }
local nuvens: { Nuvem } = {}
for i = 1, MAX_POEIRA do
	local p = Instance.new("Part")
	p.Name = "Poeira" .. i
	p.Size = Vector3.new(11, 6, 11)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.CFrame = CFrame.new(0, -500, 0)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(255, 214, 158))
	e.LightEmission = 0.6
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.11),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.45),
		NumberSequenceKeypoint.new(0.75, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(5, 9)
	e.Rate = 5
	e.Speed = NumberRange.new(0.05, 0.25)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 0.012, 0)
	e.Drag = 0.3
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Enabled = false
	e.Parent = p
	p.Parent = pasta
	nuvens[i] = { parte = p, emissor = e }
end

type Chama = { luz: PointLight, semente: number }
local chamas: { Chama } = {}
local acesas: { [PointLight]: boolean } = {}

-- a cor e a força da chama na hora da partida (o lampião que chega pelo streaming também)
local corAgora, brilhoAgora = Lampiao.daHora(ReplicatedStorage:GetAttribute("VT65Hora"))
local function pinta(g: Instance)
	if g:IsA("BasePart") then
		local luz = g:FindFirstChildOfClass("PointLight")
		if luz then
			luz.Color = Color3.fromRGB(corAgora[1], corAgora[2], corAgora[3])
			luz.Brightness = brilhoAgora
		end
	end
end
for _, g in CollectionService:GetTagged(Lampiao.TAG) do
	pinta(g)
end
CollectionService:GetInstanceAddedSignal(Lampiao.TAG):Connect(function(g: Instance)
	task.defer(pinta, g) -- a luz é filha do globo e pode chegar logo depois dele
end)
ReplicatedStorage:GetAttributeChangedSignal("VT65Hora"):Connect(function()
	corAgora, brilhoAgora = Lampiao.daHora(ReplicatedStorage:GetAttribute("VT65Hora"))
	for _, g in CollectionService:GetTagged(Lampiao.TAG) do
		pinta(g)
	end
end)

local function atualiza()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local c = cam.CFrame.Position
	local perto: { { g: BasePart, d: number } } = {}
	for _, g in CollectionService:GetTagged(Lampiao.TAG) do
		if g:IsA("BasePart") then
			local d = (g.Position - c).Magnitude
			if d < RAIO_CHAMA then
				table.insert(perto, { g = g, d = d })
			end
		end
	end
	table.sort(perto, function(a, b)
		return a.d < b.d
	end)
	-- as chamas: quem saiu da lista volta ao brilho fixo
	local novas: { Chama } = {}
	local ficam: { [PointLight]: boolean } = {}
	for _, x in perto do
		if #novas >= MAX_CHAMAS then
			break
		end
		local luz = x.g:FindFirstChildOfClass("PointLight")
		if luz then
			ficam[luz] = true
			table.insert(novas, { luz = luz, semente = x.g.Position.X * 0.37 + x.g.Position.Z * 0.11 })
		end
	end
	for luz in acesas do
		if not ficam[luz] and luz.Parent then
			luz.Brightness = brilhoAgora
		end
	end
	acesas = ficam
	chamas = novas
	-- a poeira: nas casas mais perto, se o detalhe permite
	local det = player:GetAttribute("GfxDetail")
	local comPoeira = type(det) ~= "number" or det >= 0.6
	for i, n in nuvens do
		local x = perto[i]
		if comPoeira and x and x.d < RAIO_POEIRA then
			n.parte.CFrame = CFrame.new(x.g.Position - Vector3.new(0, 3.2, 0))
			n.emissor.Enabled = true
		else
			n.emissor.Enabled = false
		end
	end
end

task.spawn(function()
	while true do
		atualiza()
		task.wait(0.4)
	end
end)

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, f in chamas do
		if f.luz.Parent then
			f.luz.Brightness = brilhoAgora * Lampiao.chama(t, f.semente)
		end
	end
end)
