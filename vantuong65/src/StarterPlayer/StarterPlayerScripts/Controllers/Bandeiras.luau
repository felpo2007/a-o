--!strict
-- Bandeiras dos dois lados em peças de interface (lote 16, D-130; pedido do dono: "na escolha do lado
-- coloque uma bandeira do EUA e outra do Vietnã"; a do VC é a da Frente, resposta do dono). Sem
-- imagem para subir: listras, cantão e estrelas são Frames e TextLabels, nítidos em qualquer tamanho.
--   - EUA em agosto de 1965: 50 estrelas (desde 4 de julho de 1960), 13 listras começando no
--     vermelho, cantão azul da altura de 7 listras e 0,76/1,9 da largura; estrelas em 9 fileiras
--     alternadas de 6 e 5 (Executive Order 10834, 1959). Cores Old Glory.
--   - Frente Nacional de Libertação do Vietnã do Sul (Mặt trận Dân tộc Giải phóng miền Nam Việt Nam,
--     1960): metade de cima vermelha, de baixo azul, estrela amarela de cinco pontas no meio; 2:3.
-- O pano tem uma sombra de dobra que corre devagar (UIGradient.Offset), como se o vento mexesse.
local TweenService = game:GetService("TweenService")

local Bandeiras = {}

-- proporção (largura / altura) de cada bandeira
Bandeiras.RATIO = { US = 1.9, VC = 1.5 } :: { [string]: number }

local US_RED = Color3.fromRGB(178, 34, 52)
local US_WHITE = Color3.fromRGB(255, 255, 255)
local US_BLUE = Color3.fromRGB(60, 59, 110)
local NLF_RED = Color3.fromRGB(218, 37, 29)
local NLF_BLUE = Color3.fromRGB(0, 147, 221)
local NLF_STAR = Color3.fromRGB(255, 221, 0)
local STAR_FONT = Font.fromEnum(Enum.Font.ArimoBold) -- o Arimo tem o "★"

local function rect(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function star(parent: Instance, cx: number, cy: number, size: number, color: Color3, z: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromOffset(cx, cy)
	t.Size = UDim2.fromOffset(size * 1.4, size * 1.4)
	t.FontFace = STAR_FONT
	t.Text = "★"
	t.TextSize = size
	t.TextColor3 = color
	t.ZIndex = z
	t.Parent = parent
	return t
end

-- sombra das dobras por cima do pano: faixas mais escuras e mais claras que andam devagar
local function cloth(flag: Frame, z: number)
	local o = Instance.new("Frame")
	o.Name = "Dobras"
	o.BorderSizePixel = 0
	o.BackgroundColor3 = Color3.new(0, 0, 0)
	o.Size = UDim2.fromScale(1, 1)
	o.ZIndex = z
	o.Parent = flag
	local g = Instance.new("UIGradient")
	g.Rotation = 8
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.94),
		NumberSequenceKeypoint.new(0.18, 0.78),
		NumberSequenceKeypoint.new(0.36, 0.97),
		NumberSequenceKeypoint.new(0.55, 0.8),
		NumberSequenceKeypoint.new(0.74, 0.98),
		NumberSequenceKeypoint.new(1, 0.84),
	})
	g.Parent = o
	g.Offset = Vector2.new(-0.12, 0)
	TweenService:Create(
		g,
		TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Offset = Vector2.new(0.12, 0) }
	):Play()
end

local function base(parent: Instance, w: number, h: number, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = "Bandeira"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(w, h)
	f.ClipsDescendants = true
	f.ZIndex = z
	f.Parent = parent
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = Color3.new(0, 0, 0)
	edge.Transparency = 0.6
	edge.Thickness = 1
	edge.Parent = f
	return f
end

-- Bandeira dos EUA de h px de altura (largura pela proporção 1,9).
function Bandeiras.us(parent: Instance, h: number, z: number?): Frame
	local zz = z or 1
	local w = math.floor(h * Bandeiras.RATIO.US + 0.5)
	local f = base(parent, w, h, zz)
	f.Name = "BandeiraEUA"
	local stripe = h / 13
	for i = 0, 12 do
		local y0 = math.floor(i * stripe + 0.5)
		local y1 = math.floor((i + 1) * stripe + 0.5)
		rect(f, 0, y0, w, y1 - y0, if i % 2 == 0 then US_RED else US_WHITE, zz)
	end
	local cw = math.floor(w * 0.76 / 1.9 + 0.5)
	local ch = math.floor(7 * stripe + 0.5)
	local canton = rect(f, 0, 0, cw, ch, US_BLUE, zz + 1)
	canton.Name = "Cantao"
	-- 9 fileiras: as ímpares com 6 estrelas, as pares com 5 (espaços de 1/12 da largura e 1/10 da altura)
	local gx, gy = cw / 12, ch / 10
	local size = math.max(4, math.floor(h * 0.0616 * 1.5 + 0.5))
	for row = 1, 9 do
		local six = row % 2 == 1
		for k = 1, if six then 6 else 5 do
			local col = if six then 2 * k - 1 else 2 * k
			star(canton, col * gx, row * gy, size, US_WHITE, zz + 2)
		end
	end
	cloth(f, zz + 3)
	return f
end

-- Bandeira da Frente (VC) de h px de altura (2:3).
function Bandeiras.nlf(parent: Instance, h: number, z: number?): Frame
	local zz = z or 1
	local w = math.floor(h * Bandeiras.RATIO.VC + 0.5)
	local f = base(parent, w, h, zz)
	f.Name = "BandeiraFrente"
	local half = math.floor(h / 2 + 0.5)
	rect(f, 0, 0, w, half, NLF_RED, zz)
	rect(f, 0, half, w, h - half, NLF_BLUE, zz)
	star(f, w / 2, h / 2, math.floor(h * 0.62 + 0.5), NLF_STAR, zz + 1)
	cloth(f, zz + 2)
	return f
end

-- A bandeira do lado ("US" ou "VC").
function Bandeiras.of(faction: string, parent: Instance, h: number, z: number?): Frame
	return if faction == "VC" then Bandeiras.nlf(parent, h, z) else Bandeiras.us(parent, h, z)
end

return Bandeiras
