--!strict
-- Bandeiras dos idiomas (pedido do dono, 2026-11-11: "coloque as bandeiras dos países na hora de
-- escolher o idioma"). Desenhadas só com Frames, UICorner e UIGradient (sem imagem nova):
--   pt: Brasil (verde, losango amarelo em faixas finas, círculo azul com a faixa branca);
--   en: EUA (13 listras, cantão azul com as estrelas em pontos);
--   es: Espanha (vermelho, amarelo, vermelho em 1:2:1, num UIGradient de degraus);
--   vi: Vietnã (vermelho com a estrela amarela, ★ em texto escalado);
--   auto: um globo simples (círculo com meridianos e paralelos).
-- Bandeiras.criar(código, largura, altura?) devolve um Frame de w x h (padrão 3:2) que quem chama
-- posiciona. Tudo é criado de uma vez (umas 30 peças a mais grande); nada anima aqui.
local Bandeiras = {}

local function frame(parent: Instance, color: Color3, x: number, y: number, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Parent = parent
	return f
end

local function round(o: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = o
end

-- brilho de pano: um pouco mais claro em cima (o UIGradient só pinta o próprio objeto)
local function sheen(o: Instance)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
	g.Parent = o
end

local function brasil(f: Frame)
	f.BackgroundColor3 = Color3.fromRGB(0, 148, 64)
	-- losango em faixas horizontais (o Roblox não deforma um quadrado girado)
	local N = 22
	local yellow = Color3.fromRGB(254, 221, 0)
	for i = 0, N - 1 do
		local y = (i + 0.5) / N -- 0..1 no losango
		local w = 1 - math.abs(y * 2 - 1)
		local s = frame(f, yellow, 0.5, 0.085 + 0.83 * i / N, 0.86 * w, 0.83 / N + 0.004)
		s.AnchorPoint = Vector2.new(0.5, 0)
	end
	local blue = Instance.new("Frame")
	blue.AnchorPoint = Vector2.new(0.5, 0.5)
	blue.Position = UDim2.fromScale(0.5, 0.5)
	blue.Size = UDim2.fromScale(0.5, 0.5)
	blue.SizeConstraint = Enum.SizeConstraint.RelativeYY
	blue.BackgroundColor3 = Color3.fromRGB(0, 39, 118)
	blue.BorderSizePixel = 0
	blue.Parent = f
	round(blue)
	local band = frame(blue, Color3.fromRGB(246, 246, 240), 0.5, 0.5, 0.88, 0.1)
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Rotation = -10
end

local function eua(f: Frame)
	f.BackgroundColor3 = Color3.fromRGB(246, 246, 240)
	local red = Color3.fromRGB(178, 34, 52)
	for i = 0, 12, 2 do
		frame(f, red, 0, i / 13, 1, 1 / 13 + 0.002)
	end
	local canton = frame(f, Color3.fromRGB(40, 50, 110), 0, 0, 0.4, 7 / 13)
	-- estrelas em pontos (5 x 4): na escala de um cartão, um ponto lê como estrela
	for r = 0, 3 do
		for c = 0, 4 do
			local dot = frame(
				canton,
				Color3.fromRGB(246, 246, 240),
				(c + 0.5 + (r % 2) * 0.25) / 5.3,
				(r + 0.5) / 4,
				0.07,
				0.11
			)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			round(dot)
		end
	end
end

local function espanha(f: Frame)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	local red = Color3.fromRGB(176, 20, 30)
	local yellow = Color3.fromRGB(246, 194, 0)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, red),
		ColorSequenceKeypoint.new(0.25, red),
		ColorSequenceKeypoint.new(0.2501, yellow),
		ColorSequenceKeypoint.new(0.7499, yellow),
		ColorSequenceKeypoint.new(0.75, red),
		ColorSequenceKeypoint.new(1, red),
	})
	g.Parent = f
end

local function vietna(f: Frame)
	f.BackgroundColor3 = Color3.fromRGB(214, 36, 28)
	local star = Instance.new("TextLabel")
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.fromScale(0.5, 0.52)
	star.Size = UDim2.fromScale(0.62, 0.62)
	star.SizeConstraint = Enum.SizeConstraint.RelativeYY
	star.BackgroundTransparency = 1
	star.Font = Enum.Font.ArimoBold
	star.Text = "★"
	star.TextScaled = true
	star.TextColor3 = Color3.fromRGB(255, 222, 0)
	star.Parent = f
end

local function globo(f: Frame)
	f.BackgroundTransparency = 1
	local ink = Color3.fromRGB(206, 190, 142)
	local ball = Instance.new("Frame")
	ball.AnchorPoint = Vector2.new(0.5, 0.5)
	ball.Position = UDim2.fromScale(0.5, 0.5)
	ball.Size = UDim2.fromScale(0.96, 0.96)
	ball.SizeConstraint = Enum.SizeConstraint.RelativeYY
	ball.BackgroundColor3 = Color3.fromRGB(38, 62, 92)
	ball.BorderSizePixel = 0
	ball.Parent = f
	round(ball)
	local g = Instance.new("UIGradient")
	g.Rotation = 35
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 120))
	g.Parent = ball
	local edge = Instance.new("UIStroke")
	edge.Color = ink
	edge.Thickness = 1.5
	edge.Parent = ball
	-- meridianos: o eixo e duas elipses (cápsulas de borda fina)
	for _, w in { 0.56, 0.24 } do
		local m = Instance.new("Frame")
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Position = UDim2.fromScale(0.5, 0.5)
		m.Size = UDim2.fromScale(w, 1)
		m.BackgroundTransparency = 1
		m.Parent = ball
		round(m)
		local s = Instance.new("UIStroke")
		s.Color = ink
		s.Thickness = 1
		s.Transparency = 0.25
		s.Parent = m
	end
	local axis = frame(ball, ink, 0.5, 0, 0, 1)
	axis.AnchorPoint = Vector2.new(0.5, 0)
	axis.Size = UDim2.new(0, 1, 1, 0)
	-- paralelos: a corda do círculo em cada altura (a linha não passa da borda)
	for _, y in { 0.25, 0.5, 0.75 } do
		local d = 2 * math.sqrt(math.max(0, 0.25 - (y - 0.5) ^ 2))
		local p = frame(ball, ink, 0.5, y, d * 0.98, 0)
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Size = UDim2.new(d * 0.98, 0, 0, 1)
		p.BackgroundTransparency = if y == 0.5 then 0 else 0.25
	end
end

local DRAW: { [string]: (Frame) -> () } = {
	pt = brasil,
	en = eua,
	es = espanha,
	vi = vietna,
	auto = globo,
}

-- Frame de w x h com a bandeira do idioma (código sem desenho: retângulo neutro)
function Bandeiras.criar(code: string, w: number, h: number?): Frame
	local f = Instance.new("Frame")
	f.Name = string.format("Bandeira_%s", code)
	f.Size = UDim2.fromOffset(w, h or math.floor(w * 2 / 3 + 0.5))
	f.BackgroundColor3 = Color3.fromRGB(60, 62, 52)
	f.BorderSizePixel = 0
	f.ClipsDescendants = true
	local draw = DRAW[code]
	if draw then
		draw(f)
	end
	if code ~= "auto" then
		if not f:FindFirstChildOfClass("UIGradient") then -- a da Espanha já é o desenho
			sheen(f)
		end
		local s = Instance.new("UIStroke")
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Color = Color3.new(0, 0, 0)
		s.Thickness = 1
		s.Transparency = 0.55
		s.Parent = f
	end
	return f
end

return Bandeiras
