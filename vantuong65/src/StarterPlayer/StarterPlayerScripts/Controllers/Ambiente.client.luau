--!strict
-- Ambiente vivo (D-80, pedido do dono: "coloque poeira, vento etc." e "as vilas devem fazer parte
-- do ambiente de guerra"). Tudo local e barato:
-- - vento: brisa do mar vindo do leste (a costa de Van Tuong fica a leste), com rajadas suaves;
--   na chuva sopra mais. Vai em workspace.GlobalWind: mexe o capim do terreno, a fumaça e o
--   arroz (RiceField.client);
-- - poeira no ar: cisco claro flutuando em volta da câmera de dia, levado pelo vento;
-- - folhas caindo quando a câmera está debaixo da copa da mata;
-- - fumaça de guerra no horizonte: colunas escuras de vilas e plantações queimando fora do mapa,
--   inclinadas pelo vento (agosto de 1965: a área tinha vilas bombardeadas antes do desembarque).
-- Velocidades de vento são de projeto (brisa de 3 m/s, rajada até ~7 m/s; PLACEHOLDER).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = 0.28
local camera = workspace.CurrentCamera
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SQUARE = "rbxasset://textures/particles/SquareParticle.png"

local folder = Instance.new("Folder")
folder.Name = "VT65Ambiente"
folder.Parent = workspace

local function anchorPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = size
	p.Parent = folder
	return p
end

local function seq(...: number): NumberSequence
	local a = { ... }
	local keys = {}
	for i = 1, #a, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(keys)
end

-- ===== vento =====
local BREEZE_MS = 3
local GUST_MS = 4
local function windAt(t: number): Vector3
	local rain = ReplicatedStorage:GetAttribute("Rain")
	local wet = if type(rain) == "number" then math.clamp(rain, 0, 1) else 0
	local gust = math.max(0, math.noise(t * 0.07, 3.1)) * 2 + math.noise(t * 0.31, 7.7) * 0.35
	local speed = (BREEZE_MS + GUST_MS * gust) * (1 + wet)
	local dirA = math.rad(180 + math.noise(t * 0.02, 1.3) * 25) -- do leste para oeste, oscilando
	return Vector3.new(math.cos(dirA), 0, math.sin(dirA)) * speed / M
end

-- ===== poeira no ar (em volta da câmera, só de dia e sem chuva) =====
local dustBox = anchorPart("Poeira", Vector3.new(40, 14, 40))
local dust = Instance.new("ParticleEmitter")
dust.Texture = TEX_SQUARE
dust.Shape = Enum.ParticleEmitterShape.Box
dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
dust.Rate = 10
dust.Lifetime = NumberRange.new(5, 9)
dust.Speed = NumberRange.new(0.05, 0.3)
dust.Size = seq(0, 0.035, 0.5, 0.05, 1, 0.03)
dust.Transparency = seq(0, 1, 0.2, 0.55, 0.8, 0.6, 1, 1)
dust.Color = ColorSequence.new(Color3.fromRGB(255, 240, 210))
dust.LightEmission = 0.4
dust.LightInfluence = 0.6
dust.Drag = 1.5
dust.WindAffectsDrag = true
dust.RotSpeed = NumberRange.new(-40, 40)
dust.Parent = dustBox

-- ===== folhas caindo (debaixo da copa) =====
local leafBox = anchorPart("Folhas", Vector3.new(36, 1, 36))
local leaves = Instance.new("ParticleEmitter")
leaves.Texture = TEX_SQUARE
leaves.Shape = Enum.ParticleEmitterShape.Box
leaves.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
leaves.Rate = 0
leaves.Lifetime = NumberRange.new(6, 10)
leaves.Speed = NumberRange.new(0.2, 0.8)
leaves.EmissionDirection = Enum.NormalId.Bottom
leaves.Acceleration = Vector3.new(0, -0.8 / M, 0)
leaves.Drag = 2.5
leaves.WindAffectsDrag = true
leaves.Size = seq(0, 0.16, 1, 0.13)
leaves.Transparency = seq(0, 0.1, 0.85, 0.15, 1, 1)
leaves.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 104, 46)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(122, 98, 50)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 88, 40)),
})
leaves.Rotation = NumberRange.new(0, 360)
leaves.RotSpeed = NumberRange.new(-160, 160)
leaves.Parent = leafBox

local canopyParams = RaycastParams.new()
canopyParams.FilterType = Enum.RaycastFilterType.Include
local function underCanopy(pos: Vector3): boolean
	local map = workspace:FindFirstChild("Map")
	local art = map and map:FindFirstChild("Art")
	local jungle = art and art:FindFirstChild("Jungle")
	if not jungle then
		return false
	end
	canopyParams.FilterDescendantsInstances = { jungle }
	-- copas não têm colisão nem consulta? Folhagem tem CanQuery ligada (o tiro passa pelo atributo)
	return workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, 70, 0), canopyParams) ~= nil
end

-- ===== fumaça de guerra no horizonte =====
-- Fora do mapa de 1 x 1 km (MapConfig.Bounds: X -3036 a 536, Z -3929 a -357) e do terreno (150 m
-- além da borda), a 550–750 m da área, em volta: a oeste Nam Yên (3) e a LZ Blue, ao norte An Thới
-- (1), ao sul An Phước (1) e a sudeste e leste a costa do desembarque.
local columns: { ParticleEmitter } = {}
local COLUMNS = {
	Vector3.new(-5200, 40, -1900),
	Vector3.new(-1400, 40, -6300),
	Vector3.new(-2300, 40, 2300),
	Vector3.new(2600, 30, -2400),
	Vector3.new(2200, 40, 1700),
}
for i, pos in COLUMNS do
	local base = anchorPart("ColunaDeFumaca" .. i, Vector3.new(30, 4, 30))
	base.Position = pos
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SMOKE
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Rate = 1.6
	e.Lifetime = NumberRange.new(40, 60)
	e.Speed = NumberRange.new(10, 16)
	e.SpreadAngle = Vector2.new(8, 8)
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Drag = 0.25
	e.WindAffectsDrag = true
	e.Size = seq(0, 40, 0.3, 110, 1, 260)
	e.Transparency = seq(0, 0.35, 0.5, 0.55, 1, 1)
	e.Color = ColorSequence.new(Color3.fromRGB(58, 56, 54), Color3.fromRGB(128, 126, 122))
	e.LightInfluence = 1
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-4, 4)
	e.Parent = base
	table.insert(columns, e)
	-- já começa cheia (sem ver a coluna nascer ao entrar)
	task.delay(1 + i * 0.3, function()
		e:Emit(40)
	end)
end

-- ===== detalhe (D-82, opção de gráficos: 1, 0,6 ou 0,3) =====
-- 2026-11-12 (pedido do dono: "talvez os ventos e a iluminação estejam pesando"). O vento em si
-- (workspace.GlobalWind, 15 vezes por segundo) não pesa: é um vetor que o motor já usa no capim do
-- terreno e nas partículas. O que pesa é a fumaça: cada coluna do horizonte tem ~80 partículas de
-- até 260 studs, translúcidas e sobrepostas (pixel desenhado muitas vezes na tela inteira), e cada
-- fumaça de cozinha das vilas ~40. No detalhe baixo as colunas e a fumaça das vilas somem; no médio
-- ficam pela metade.
local player = game:GetService("Players").LocalPlayer
local detail = 1
-- chave fraca: a fumaça que sai do streaming é coletada sozinha
local villageSmoke: { [ParticleEmitter]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local SMOKE_RATE = 4 -- MapLife.smoke
local function smokeRate(): number
	return if detail >= 0.9 then 1 elseif detail >= 0.5 then 0.5 else 0
end
local function readDetail()
	local d = player:GetAttribute("GfxDetail")
	detail = if type(d) == "number" then d else 1
	dust.Rate = 10 * detail
	local k = smokeRate()
	for _, e in columns do
		e.Rate = 1.6 * k
		e.Enabled = k > 0
	end
	for e in villageSmoke do
		local base = e:GetAttribute("BaseRate")
		e.Rate = (if type(base) == "number" then base else SMOKE_RATE) * k
		e.Enabled = k > 0
	end
end
readDetail()
player:GetAttributeChangedSignal("GfxDetail"):Connect(readDetail)
-- fumaça de cozinha das vilas (Map.Art.VidaDaVila, MapLife): chega por streaming
task.spawn(function()
	local map = workspace:WaitForChild("Map", 120)
	local art = map and map:WaitForChild("Art", 300)
	if not art then
		return
	end
	local function track(d: Instance)
		if d:IsA("ParticleEmitter") and d.Parent and d.Parent.Name == "Fumaca" then
			villageSmoke[d] = true
			local k = smokeRate()
			-- fumaça de cozinha das vilas (4/s) ou a rala do fogão do VC (BaseRate do servidor)
			local base = d:GetAttribute("BaseRate")
			d.Rate = (if type(base) == "number" then base else SMOKE_RATE) * k
			d.Enabled = k > 0
		end
	end
	for _, d in art:GetDescendants() do
		track(d)
	end
	art.DescendantAdded:Connect(track)
end)

-- ===== laço =====
-- 15 vezes por segundo (antes, a cada quadro): o vento muda devagar (ruído de 3 a 50 s) e a caixa
-- de poeira e a de folhas só dizem onde nascem as partículas novas, que já flutuam sozinhas.
local STEP_S = 1 / 15
local lastStep = 0
local lastCanopy = 0
local canopy = false
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	if t - lastStep < STEP_S then
		return
	end
	lastStep = t
	workspace.GlobalWind = windAt(t)
	local cf = camera.CFrame
	local pos = cf.Position
	-- poeira à frente da câmera, mais densa no sol e sem chuva
	dustBox.CFrame = CFrame.new(pos + cf.LookVector * 12)
	local rain = ReplicatedStorage:GetAttribute("Rain")
	local wet = type(rain) == "number" and rain > 0.2
	local day = Lighting.ClockTime > 6.2 and Lighting.ClockTime < 18
	dust.Enabled = day and not wet and detail >= 0.5
	if t - lastCanopy > 1 then
		lastCanopy = t
		canopy = underCanopy(pos)
	end
	leafBox.CFrame = CFrame.new(pos + Vector3.new(0, 12, 0) + cf.LookVector * 6)
	leaves.Rate = if canopy then (if wet then 4 else 1.8) * detail else 0
end)
