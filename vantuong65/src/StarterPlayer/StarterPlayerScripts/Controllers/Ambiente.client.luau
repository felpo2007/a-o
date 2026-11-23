--!strict
-- Ambiente (D-80). Tudo local e barato:
-- - SEM vento (D-253, prompt V5 §4): nada de poeira ou folhas soltas no ar, capim, arroz e tecidos parados;
-- - fumaça de guerra no horizonte: colunas escuras de vilas e plantações queimando fora do mapa
--   (agosto de 1965: a área tinha vilas bombardeadas antes do desembarque).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SemVento = require(ReplicatedStorage.Shared.SemVento)

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

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

-- ===== sem vento (D-253) =====
SemVento.aplicar()

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
