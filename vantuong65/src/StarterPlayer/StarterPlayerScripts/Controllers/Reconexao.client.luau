--!strict
-- Aviso de controle desconectado (Parte 12: o jogo pausa a entrada e volta com o primeiro controle
-- que apertar um botão; a regra fica no Input). Antes era um texto branco em Gotham sobre preto;
-- agora é uma ficha de época como as outras telas: papel, máquina de escrever, carimbo "PAUSADO", o
-- controle desenhado com a luz de sinal piscando, e a tela atrás escurece. Entra e sai em tween.
-- Escala para qualquer janela (UiKit.fit). Nada é criado depois da montagem.
-- Studio: workspace:SetAttribute("VT65DevTela", "controle") mostra por 5 s.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end
local W, H = px(560, 820), px(232, 330)

local gui = UiKit.screen("VT65Reconexao", 100)
gui.IgnoreGuiInset = true
gui.Enabled = false

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Parent = gui
local vin = Instance.new("ImageLabel")
vin.Size = UDim2.fromScale(1, 1)
vin.BackgroundTransparency = 1
vin.Image = Acabamento.VINHETA
vin.ImageColor3 = Color3.new(0, 0, 0)
vin.ImageTransparency = 1
vin.Parent = gui

local card = Instance.new("Frame")
card.Name = "Ficha"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(W, H)
card.BackgroundColor3 = UiKit.CARD
card.BorderSizePixel = 0
card.Rotation = -0.8
card.Parent = gui
UiKit.lit(card, 0.86)
UiKit.edge(card, UiKit.INK, 1, 0.5)
local fit = UiKit.fit(gui, card, W, H, 24)
Acabamento.sombra(card, 20, Vector2.new(0, 8), 0.6)

local head = UiKit.rotulo(card, px(15, 24), UiKit.RULE_RED, UiKit.TYPE_FONT)
head.Position = UDim2.fromOffset(px(22, 32), px(14, 20))
head.Size = UDim2.new(1, -px(44, 64), 0, px(22, 32))
head.Text = "LIGAÇÃO PERDIDA · CONTROLE DESCONECTADO"
local rule = Instance.new("Frame")
rule.BackgroundColor3 = UiKit.RULE_RED
rule.BorderSizePixel = 0
rule.Position = UDim2.fromOffset(px(22, 32), px(40, 58))
rule.Size = UDim2.new(1, -px(44, 64), 0, 2)
rule.Parent = card

-- o controle desenhado (corpo, punhos, analógicos) e a luz de sinal
local pad = Instance.new("Frame")
pad.Name = "Controle"
pad.BackgroundTransparency = 1
pad.Position = UDim2.fromOffset(px(26, 38), px(64, 92))
pad.Size = UDim2.fromOffset(px(130, 190), px(96, 140))
pad.Parent = card
local padEdges: { UIStroke } = {}
local function padPart(x: number, y: number, w: number, h: number, r: number)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = UiKit.DRAB
	f.BackgroundTransparency = 0.82
	f.BorderSizePixel = 0
	f.Parent = pad
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r, 0)
	c.Parent = f
	table.insert(padEdges, UiKit.edge(f, UiKit.INK, px(2, 3), 0.1))
end
padPart(0.24, 0.62, 0.34, 0.62, 0.5) -- punho esquerdo
padPart(0.76, 0.62, 0.34, 0.62, 0.5) -- punho direito
padPart(0.5, 0.42, 0.9, 0.46, 0.45) -- corpo
padPart(0.32, 0.42, 0.14, 0.19, 1) -- analógico esquerdo
padPart(0.62, 0.58, 0.14, 0.19, 1) -- analógico direito
local light = Instance.new("Frame")
light.AnchorPoint = Vector2.new(0.5, 0.5)
light.Position = UDim2.fromScale(0.5, 0.26)
light.Size = UDim2.fromOffset(px(10, 14), px(10, 14))
light.BackgroundColor3 = UiKit.STAMP
light.BorderSizePixel = 0
light.Parent = pad
UiKit.corner(light, 99)

local x0 = px(176, 256)
local body = UiKit.rotulo(card, px(18, 28), UiKit.INK, UiKit.TYPE_FONT)
body.Position = UDim2.fromOffset(x0, px(60, 86))
body.Size = UDim2.new(1, -x0 - px(22, 32), 0, px(80, 116))
body.TextWrapped = true
body.TextYAlignment = Enum.TextYAlignment.Top
body.LineHeight = 1.15
body.Text = "Reconecte o controle e aperte qualquer botão para voltar."
local note = UiKit.rotulo(card, px(14, 24), UiKit.OLIVE, UiKit.BODY_FONT)
note.Position = UDim2.fromOffset(x0, px(144, 206))
note.Size = UDim2.new(1, -x0 - px(150, 210), 0, px(40, 60))
note.TextWrapped = true
note.TextYAlignment = Enum.TextYAlignment.Top
note.Text = "Seu soldado fica parado até lá. Teclado e mouse continuam valendo."

local stamp = Instance.new("TextLabel")
stamp.AnchorPoint = Vector2.new(0.5, 0.5)
stamp.Position = UDim2.new(1, -px(78, 112), 1, -px(40, 58))
stamp.Size = UDim2.fromOffset(px(130, 190), px(44, 64))
stamp.Rotation = -9
stamp.BackgroundTransparency = 1
stamp.FontFace = UiKit.HEAD_FONT
stamp.TextSize = px(28, 42)
stamp.TextColor3 = UiKit.STAMP
stamp.Text = "PAUSADO"
stamp.Parent = card
local stampInk = UiKit.edge(stamp, UiKit.STAMP, 3, 0.15)
local stampScale = Instance.new("UIScale")
stampScale.Parent = stamp

-- ===== mostrar e esconder =====
local shown = false
local loops: { Tween } = {}
local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	for _, t in loops do
		t:Cancel()
	end
	table.clear(loops)
	if on then
		gui.Enabled = true
		dim.BackgroundTransparency = 1
		vin.ImageTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.4 }):Play()
		TweenService:Create(vin, TweenInfo.new(0.3), { ImageTransparency = 0.25 }):Play()
		card.Position = UDim2.new(0.5, 0, 0.5, 30)
		TweenService:Create(card, TweenInfo.new(0.32, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) })
			:Play()
		-- um tween de escala por vez (a janela mudando no meio assenta na escala nova)
		fit.play(TweenInfo.new(0.32, Enum.EasingStyle.Quint), 1, 0.95)
		-- o carimbo cai depois da ficha
		stamp.TextTransparency = 1
		stampInk.Transparency = 1
		stampScale.Scale = 1.7
		local hit = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4)
		TweenService:Create(stamp, hit, { TextTransparency = 0.08 }):Play()
		TweenService:Create(stampInk, hit, { Transparency = 0.15 }):Play()
		TweenService:Create(stampScale, hit, { Scale = 1 }):Play()
		-- a luz de sinal pisca e o desenho "procura" o controle
		local blink = TweenService:Create(
			light,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.85 }
		)
		blink:Play()
		table.insert(loops, blink)
		for _, e in padEdges do
			local t = TweenService:Create(
				e,
				TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.6 }
			)
			t:Play()
			table.insert(loops, t)
		end
	else
		local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(vin, info, { ImageTransparency = 1 }):Play()
		TweenService:Create(card, info, { Position = UDim2.new(0.5, 0, 0.5, 24) }):Play()
		fit.play(info, 0.94)
		task.delay(0.23, function()
			if not shown then
				gui.Enabled = false
			end
		end)
	end
end

local devUntil = 0
RunService.Heartbeat:Connect(function()
	local want = Input.state.disconnected == true or os.clock() < devUntil
	if want ~= shown then
		setShown(want)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "controle" then
			devUntil = os.clock() + 5
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
