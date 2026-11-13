--!strict
-- Caveira do abate (pedido do dono, 2026-11-11: "faça uma caveira bem feita quando você mata
-- alguém"). Quando o servidor dá o crédito do abate (ProgressionService.award(killer, "kill"), que
-- chega no Progress_State com o ganho "Abate"), uma caveira de estêncil militar aparece abaixo da
-- mira por ~1,2 s: cai como carimbo (escala e giro assentam), um anel de tinta abre e some, e ela
-- esmaece. v43 (pedido do dono): fica a 62% da altura, com o nome de quem caiu embaixo (Combat_Kill).
-- Sem som: o abate é do servidor, não do tiro.
-- Arte: assets/ui/caveira_abate.png (tools/make_caveira.py, 1024 px com alfa), tingida de osso. O
-- servidor resolve o decal publicado no ID da imagem (Modules/ImagensUi, atributo
-- "Img_caveira_abate"); sem ele, a caveira é desenhada com frames (reserva vetorial).
-- Tamanho: 11% da altura da tela (~119 px em 1080p, ~238 px em 4K), translúcida, para a mira
-- continuar visível. Tudo é criado uma vez; a animação é só tween.
-- Studio: workspace:SetAttribute("VT65DevTela", "caveira") mostra (a imagem, se houver);
-- "caveira_desenho" força a reserva com frames.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local UiKit = require(script.Parent.UiKit)

local BONE = Color3.fromRGB(236, 228, 204)
local HOLE = Color3.fromRGB(18, 18, 14)
local ALPHA = 0.16 -- transparência no auge (a cena atrás continua legível)
local LABEL = "Abate" -- Progression.REWARDS.kill.label

-- ===== montagem =====
local gui = UiKit.screen("VT65Caveira", 16) -- acima do HUD (12 a 15), abaixo dos menus (20+)
gui.IgnoreGuiInset = true -- o centro da tela é o centro da mira

-- v43 (pedido do dono: "coloque a caveira para baixo da tela e coloque o nome da kill também"): abaixo
-- da mira (a 62% da altura, sai da frente do alvo; o nome fica a ~70%, acima do cartão do tutorial e da
-- bússola) e um pouco menor, com o nome de quem caiu embaixo
local holder = Instance.new("Frame")
holder.Name = "Caveira"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.62)
holder.SizeConstraint = Enum.SizeConstraint.RelativeYY
holder.Size = UDim2.fromScale(0.09, 0.09)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = gui
do
	local lim = Instance.new("UISizeConstraint")
	lim.MinSize = Vector2.new(72, 72)
	lim.MaxSize = Vector2.new(260, 260)
	lim.Parent = holder
end
local scale = Instance.new("UIScale")
scale.Parent = holder

-- nome de quem caiu (Combat_Kill), logo abaixo da caveira
local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "Nome"
nameLabel.AnchorPoint = Vector2.new(0.5, 0)
nameLabel.Position = UDim2.new(0.5, 0, 1, 6)
nameLabel.Size = UDim2.new(4, 0, 0, UiKit.text(20))
nameLabel.BackgroundTransparency = 1
nameLabel.FontFace = UiKit.HEAD_FONT
nameLabel.TextSize = UiKit.text(18)
nameLabel.TextColor3 = BONE
nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
nameLabel.TextStrokeTransparency = 1
nameLabel.TextTransparency = 1
nameLabel.Text = ""
nameLabel.ZIndex = 4
nameLabel.Parent = holder

-- anel de tinta (a pancada do carimbo): abre e some
local ring = Instance.new("Frame")
ring.Name = "Anel"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.52)
ring.Size = UDim2.fromScale(1.15, 1.15)
ring.BackgroundTransparency = 1
ring.ZIndex = 1
ring.Parent = holder
UiKit.corner(ring, 9999)
local ringInk = Instance.new("UIStroke")
ringInk.Color = BONE
ringInk.Thickness = 2
ringInk.Transparency = 1
ringInk.Parent = ring

-- imagem (com sombra embaixo, para ler no céu claro)
local shadow = Instance.new("ImageLabel")
shadow.Name = "Sombra"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.new(0.5, 2, 0.5, 3)
shadow.Size = UDim2.fromScale(1, 1)
shadow.BackgroundTransparency = 1
shadow.ImageColor3 = Color3.new(0, 0, 0)
shadow.ImageTransparency = 1
shadow.ZIndex = 2
shadow.Visible = false
shadow.Parent = holder
local img = shadow:Clone()
img.Name = "Imagem"
img.Position = UDim2.fromScale(0.5, 0.5)
img.ImageColor3 = BONE
img.ZIndex = 3
img.Parent = holder

-- ----- reserva: a mesma caveira em frames (osso e vãos), nas proporções do PNG -----
local vector = Instance.new("Frame")
vector.Name = "Desenho"
vector.Size = UDim2.fromScale(1, 1)
vector.BackgroundTransparency = 1
vector.ZIndex = 2
vector.Visible = false
vector.Parent = holder
type Piece = { o: Frame, base: number }
local pieces: { Piece } = {}
local function part(color: Color3, x: number, y: number, w: number, h: number, round: number, rot: number?, z: number?)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	f.ZIndex = z or 2
	if round > 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = vector
	table.insert(pieces, { o = f, base = ALPHA })
end
do
	-- osso: crânio, maçãs do rosto, maxila e mandíbula
	part(BONE, 0.5, 0.40, 0.63, 0.60, 0.5)
	part(BONE, 0.5, 0.56, 0.60, 0.16, 0.45)
	part(BONE, 0.5, 0.66, 0.42, 0.18, 0.25)
	part(BONE, 0.5, 0.80, 0.42, 0.24, 0.42)
	-- órbitas: o canto de dentro desce (olhar duro)
	for _, s in { -1, 1 } do
		part(HOLE, 0.5 + s * 0.135, 0.476, 0.18, 0.13, 0.42, s * -11, 3)
		part(HOLE, 0.5 + s * 0.262, 0.540, 0.11, 0.013, 0.5, s * 10, 3) -- arco zigomático
		part(HOLE, 0.5 + s * 0.012, 0.606, 0.036, 0.09, 0.5, s * -22, 3) -- nariz (coração invertido)
	end
	-- dentes: gengivas, mordida e os vãos
	part(HOLE, 0.5, 0.676, 0.27, 0.011, 0.5, 0, 3)
	part(HOLE, 0.5, 0.750, 0.34, 0.013, 0.5, 0, 3)
	part(HOLE, 0.5, 0.822, 0.25, 0.011, 0.5, 0, 3)
	for k = -3, 3 do
		part(HOLE, 0.5 + k * 0.034, 0.749, 0.011, 0.146, 0.5, 0, 3)
	end
	part(HOLE, 0.5, 0.655, 0.012, 0.045, 0.5, 0, 3) -- ponte do nariz aos dentes
end

-- ===== imagem publicada =====
local imageReady = false
local function useImage()
	local id = ReplicatedStorage:GetAttribute("Img_caveira_abate")
	if type(id) ~= "number" or id == 0 then
		imageReady = false
		return
	end
	local uri = "rbxassetid://" .. tostring(id)
	img.Image = uri
	shadow.Image = uri
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ img })
		end)
		imageReady = img.IsLoaded
		if not imageReady then
			warn("[VT65] caveira do abate: a imagem não carregou; fica o desenho com frames")
		end
	end)
end
ReplicatedStorage:GetAttributeChangedSignal("Img_caveira_abate"):Connect(useImage)
useImage()

-- ===== animação =====
local token = 0
local running: { Tween } = {}
local function play(
	o: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?,
	delay: number?
)
	local tw = TweenService:Create(
		o,
		TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, delay or 0),
		props
	)
	table.insert(running, tw)
	tw:Play()
end

local function show(forceVector: boolean?, victim: string?)
	token += 1
	local my = token
	for _, tw in running do
		tw:Cancel()
	end
	table.clear(running)
	local useImg = imageReady and not forceVector
	img.Visible = useImg
	shadow.Visible = useImg
	vector.Visible = not useImg
	holder.Visible = true
	nameLabel.Text = if victim and victim ~= "" then string.upper(victim) else ""
	nameLabel.TextTransparency = 1
	nameLabel.TextStrokeTransparency = 1
	if nameLabel.Text ~= "" then
		play(nameLabel, 0.15, { TextTransparency = 0.05, TextStrokeTransparency = 0.45 }, Enum.EasingStyle.Quad)
	end
	-- entra: cai como carimbo, um pouco torta, e assenta
	scale.Scale = 1.24
	holder.Rotation = -7
	play(scale, 0.2, { Scale = 1 })
	play(holder, 0.24, { Rotation = -2 })
	if useImg then
		img.ImageTransparency = 1
		shadow.ImageTransparency = 1
		play(img, 0.12, { ImageTransparency = ALPHA }, Enum.EasingStyle.Quad)
		play(shadow, 0.12, { ImageTransparency = 0.62 }, Enum.EasingStyle.Quad)
	else
		for _, p in pieces do
			p.o.BackgroundTransparency = 1
			play(p.o, 0.12, { BackgroundTransparency = p.base }, Enum.EasingStyle.Quad)
		end
	end
	-- anel de tinta
	ring.Size = UDim2.fromScale(0.95, 0.95)
	ringInk.Transparency = 0.35
	play(ring, 0.55, { Size = UDim2.fromScale(1.4, 1.4) }, Enum.EasingStyle.Quad)
	play(ringInk, 0.55, { Transparency = 1 }, Enum.EasingStyle.Quad)
	-- fica um instante e sai esmaecendo. A saída começa por relógio, não por tween com atraso: um
	-- tween atrasado na MESMA propriedade cancela o de entrada na hora (no Studio a caveira não
	-- aparecia: ficava em transparência 1 o tempo todo).
	local HOLD, OUT = 0.72, 0.42
	task.delay(HOLD, function()
		if token ~= my then
			return
		end
		play(scale, OUT, { Scale = 0.94 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		play(
			nameLabel,
			OUT,
			{ TextTransparency = 1, TextStrokeTransparency = 1 },
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.In
		)
		if useImg then
			play(img, OUT, { ImageTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
			play(shadow, OUT, { ImageTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		else
			for _, p in pieces do
				play(p.o, OUT, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
			end
		end
	end)
	task.delay(HOLD + OUT + 0.05, function()
		if token == my then
			holder.Visible = false
		end
	end)
end

-- ===== o crédito do abate =====
-- O ganho "Abate" (Progress_State) e o nome (Combat_Kill, v43) saem juntos do servidor; a caveira
-- espera um instante pelo nome, que pode chegar depois.
local lastName, lastNameAt = "", -math.huge
Net.event("Combat_Kill").OnClientEvent:Connect(function(k: any)
	if type(k) == "table" and type(k.name) == "string" then
		lastName, lastNameAt = k.name, os.clock()
		if holder.Visible and nameLabel.Text == "" then
			nameLabel.Text = string.upper(k.name)
			play(nameLabel, 0.15, { TextTransparency = 0.05, TextStrokeTransparency = 0.45 }, Enum.EasingStyle.Quad)
		end
	end
end)
Net.event("Progress_State").OnClientEvent:Connect(function(s: any)
	local g = type(s) == "table" and s.gain
	if type(g) == "table" and g.label == LABEL then
		task.delay(0.05, function()
			show(nil, if os.clock() - lastNameAt < 0.6 then lastName else nil)
		end)
	end
end)

-- ===== gancho de teste (só no Studio) =====
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if v == "caveira" or v == "caveira_desenho" then
			show(v == "caveira_desenho", "Fuzileiro 23")
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil) -- local: no cliente, o mesmo valor repete
			end)
		end
	end)
end
