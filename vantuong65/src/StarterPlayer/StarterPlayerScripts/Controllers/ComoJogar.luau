--!strict
-- Tutorial fora da partida: "COMO JOGAR" (lote 5, D-117; pedido do dono: "não quero mais o tutorial
-- dentro do jogo"; "uma criança tem que conseguir jogar o jogo"). Abre pelo TUTORIAL do menu
-- principal (ou Bus "como_jogar_open", que o "refazer o tutorial" do menu do jogo também usa).
-- Nove cartões, um por vez: título, uma frase curta e os botões daquele assunto em chips grandes (o
-- botão certo do aparelho de agora: tecla, botão do controle ou nome do botão na tela de toque) com
-- o nome da ação embaixo. Texto e botão ficam separados: a tradução casa a frase inteira.
-- Controle: LB/RB trocam de cartão, A no PRÓXIMO passa, B fecha. Teclado: setas, Enter,
-- Backspace. Toque e mouse: os botões ANTERIOR, PRÓXIMO e FECHAR.
-- Studio: workspace:SetAttribute("VT65DevTela", "como_jogar") abre.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local ComoJogar = {}
local V, F = UiKit.V, UiKit.F

type Chip = { id: string, label: string }
type Card = { title: string, text: string, chips: { Chip }, objectives: boolean? }

-- Os cartões (texto curto, para quem nunca jogou). "move" não é ação do InputMap: é o direcional.
ComoJogar.CARDS = {
	{
		title = "O OBJETIVO",
		text = "Dois lados lutam pelo mapa: os Fuzileiros dos EUA e o Viet Cong. Há cinco objetivos, de A a E. O que pisca no alto da tela é o da vez: entre no círculo dele e fique lá até ele ser seu.",
		chips = {},
		objectives = true,
	},
	{
		title = "ANDAR E CORRER",
		text = "Corra para chegar antes do inimigo. Pule para passar por cima de muretas e sebes.",
		chips = {
			{ id = "move", label = "Andar" },
			{ id = "sprint", label = "Correr" },
			{ id = "jump", label = "Pular" },
		},
	},
	{
		title = "MIRAR E ATIRAR",
		text = "Mire antes de atirar: a bala vai para onde a alça da arma aponta. Quando as balas acabarem, recarregue.",
		chips = {
			{ id = "aim", label = "Mirar" },
			{ id = "fire", label = "Atirar" },
			{ id = "reload", label = "Recarregar" },
		},
	},
	{
		title = "SE PROTEGER",
		text = "Abaixado ou deitado, você é um alvo menor e erra menos. Fique atrás de casas, árvores e muretas.",
		chips = { { id = "crouch", label = "Abaixar" }, { id = "prone", label = "Deitar" } },
	},
	{
		title = "GRANADA E FACA",
		text = "A granada tira o inimigo de trás da cobertura. Bem de perto, use a faca.",
		chips = { { id = "quick_grenade", label = "Granada" }, { id = "melee", label = "Faca" } },
	},
	{
		title = "A CARTA",
		text = "A carta mostra os objetivos, o seu squad e onde você pode nascer. Marque o inimigo para o seu squad ver.",
		chips = { { id = "map", label = "Carta" }, { id = "mark", label = "Marcar" } },
	},
	{
		title = "FERIDO",
		text = "Ferido, você cai e sangra. Faça um curativo, espere um médico do seu lado ou escolha renascer.",
		chips = { { id = "quick_bandage", label = "Curativo" } },
	},
	{
		title = "O SQUAD",
		text = "Você joga num squad. Fique perto dele: o líder põe um ponto de reunião onde todos podem nascer. Fale com o squad pelo rádio.",
		chips = { { id = "radio_talk", label = "Rádio" }, { id = "comm_wheel", label = "Comunicação" } },
	},
	{
		title = "VEÍCULOS",
		text = "Chegue perto de um jipe, caminhão, tanque ou helicóptero para entrar. Lá dentro, troque de lugar ou saia.",
		chips = { { id = "interact", label = "Entrar" } },
	},
} :: { Card }

local ACTION: { [string]: InputMap.Action } = {}
for _, a in InputMap.ACTIONS do
	ACTION[a.id] = ACTION[a.id] or a
end

-- os botões do mouse por extenso (quem nunca jogou não sabe o que é RMB)
local MOUSE_TEXT = {
	LMB = "CLIQUE ESQUERDO",
	RMB = "CLIQUE DIREITO",
	MMB = "RODINHA",
} :: { [string]: string }

-- botão da ação no aparelho de agora: (imagem do controle, texto curto, pede segurar?)
local function keyOf(id: string): (string?, string, boolean)
	local touch = ToqueUi.active()
	local pad = Input.isGamepad()
	if id == "move" then
		if touch then
			return nil, "direcional", false
		elseif pad then
			return UiKit.padImage(Enum.KeyCode.Thumbstick1), "analógico", false
		end
		return nil, "W A S D", false
	end
	if touch then
		return nil, ToqueTelas.touchName(id), false
	end
	local img, txt = Input.glyph(id)
	txt = MOUSE_TEXT[txt] or txt
	local a = ACTION[id]
	local kind = if a then (if pad then a.padPress else a.keyPress) else nil
	return img, txt, kind == "hold"
end

-- ===== tela =====
local gui = UiKit.screen("VT65ComoJogar", 39) -- acima do menu do jogo (35) e do passe (38)
gui.IgnoreGuiInset = true
gui.Enabled = false

local dim = Instance.new("Frame")
dim.Name = "Fundo"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = V.BG
dim.BackgroundTransparency = 0.25
dim.BorderSizePixel = 0
dim.Active = true
dim.Parent = gui

local W, H = 980, 600
local panel = Instance.new("Frame")
panel.Name = "Painel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(W, H)
panel.BackgroundColor3 = V.PANEL
panel.BorderSizePixel = 0
panel.Parent = gui
UiKit.corner(panel, 6)
UiKit.edge(panel, V.LINE, 1, 0.2)
UiKit.fit(gui, panel, W, H, 24, 0.45)

local function label(parent: Instance, font: Font, size: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextSize = UiKit.text(size)
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.TextWrapped = true
	t.Parent = parent
	return t
end

local kicker = label(panel, F.TITLE_REG, 20, V.KHAKI)
kicker.Position = UDim2.fromOffset(40, 28)
kicker.Size = UDim2.fromOffset(600, 26)
local title = label(panel, F.TITLE, 54, V.TEXT)
title.Position = UDim2.fromOffset(40, 56)
title.Size = UDim2.fromOffset(W - 80, 64)
local rule = Instance.new("Frame")
rule.BackgroundColor3 = V.BRASS
rule.BorderSizePixel = 0
rule.Position = UDim2.fromOffset(40, 126)
rule.Size = UDim2.fromOffset(88, 4)
rule.Parent = panel
local body = label(panel, F.BODY, 26, V.TEXT)
body.Position = UDim2.fromOffset(40, 150)
body.Size = UDim2.fromOffset(W - 80, 130)

-- área dos chips (ou da barra de objetivos no 1º cartão)
local art = Instance.new("Frame")
art.Name = "Botoes"
art.BackgroundTransparency = 1
art.Position = UDim2.fromOffset(40, 290)
art.Size = UDim2.fromOffset(W - 80, 190)
art.Parent = panel
local artList = Instance.new("UIListLayout")
artList.FillDirection = Enum.FillDirection.Horizontal
artList.HorizontalAlignment = Enum.HorizontalAlignment.Center
artList.VerticalAlignment = Enum.VerticalAlignment.Center
artList.Padding = UDim.new(0, 24)
artList.Parent = art

-- pé: anterior, pontos, próximo; fechar no canto
local function footButton(text: string, x: number, w: number, kind: string): (TextButton, UiKit.Realce)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = text
	b.FontFace = F.TITLE_MED
	b.TextSize = UiKit.text(26)
	b.TextColor3 = V.TEXT
	b.Size = UDim2.fromOffset(w, 60)
	b.Position = UDim2.fromOffset(x, H - 92)
	b.BackgroundColor3 = if kind == "primary" then V.OLIVE else V.PANEL_2
	b.BorderSizePixel = 0
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = panel
	UiKit.corner(b, 4)
	UiKit.edge(b, V.LINE, 1, 0.3)
	local r = UiKit.realce(b, b.BackgroundColor3, if kind == "primary" then V.OLIVE_HI else V.PANEL_3)
	b.MouseEnter:Connect(function()
		r.set(true)
	end)
	b.MouseLeave:Connect(function()
		r.set(false)
	end)
	b.SelectionGained:Connect(function()
		r.set(true)
	end)
	b.SelectionLost:Connect(function()
		r.set(false)
	end)
	return b, r
end
local prevB = footButton("◄  ANTERIOR", 40, 230, "secondary")
prevB.Name = "Anterior"
local nextB = footButton("PRÓXIMO  ►", W - 40 - 260, 260, "primary")
nextB.Name = "Proximo"
local closeB = footButton("FECHAR", W - 40 - 170, 170, "secondary")
closeB.Name = "Fechar"
closeB.Position = UDim2.fromOffset(W - 40 - 170, 28)
closeB.Size = UDim2.fromOffset(170, 50)
closeB.TextSize = UiKit.text(22)

local dots = Instance.new("Frame")
dots.BackgroundTransparency = 1
dots.AnchorPoint = Vector2.new(0.5, 0)
dots.Position = UDim2.new(0.5, 0, 0, H - 70)
dots.Size = UDim2.fromOffset(300, 16)
dots.Parent = panel
local dotList = Instance.new("UIListLayout")
dotList.FillDirection = Enum.FillDirection.Horizontal
dotList.HorizontalAlignment = Enum.HorizontalAlignment.Center
dotList.Padding = UDim.new(0, 10)
dotList.Parent = dots
local dotFrames: { Frame } = {}
for i = 1, #ComoJogar.CARDS do
	local d = Instance.new("Frame")
	d.Size = UDim2.fromOffset(14, 14)
	d.BackgroundColor3 = V.MUTED
	d.BorderSizePixel = 0
	d.LayoutOrder = i
	d.Parent = dots
	UiKit.corner(d, 7)
	dotFrames[i] = d
end

local index = 1
local open = false

local function chip(c: Chip, order: number)
	local img, txt, hold = keyOf(c.id)
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(170, 180)
	box.LayoutOrder = order
	box.Parent = art
	local key = Instance.new("Frame")
	key.AnchorPoint = Vector2.new(0.5, 0)
	key.Position = UDim2.fromScale(0.5, 0)
	key.Size = UDim2.fromOffset(150, 110)
	key.BackgroundColor3 = UiKit.CARD
	key.BorderSizePixel = 0
	key.Parent = box
	UiKit.corner(key, 10)
	UiKit.edge(key, UiKit.BRASS, 3, 0)
	if img then
		local im = Instance.new("ImageLabel")
		im.BackgroundTransparency = 1
		im.AnchorPoint = Vector2.new(0.5, 0.5)
		im.Position = UDim2.fromScale(0.5, if hold then 0.42 else 0.5)
		im.Size = UDim2.fromOffset(64, 64)
		im.Image = img
		im.Parent = key
	else
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, -16, 1, if hold then -30 else -8)
		t.Position = UDim2.fromOffset(8, 4)
		t.FontFace = F.TITLE
		t.TextColor3 = UiKit.INK
		t.TextScaled = true
		t.Text = txt
		t.Parent = key
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = 44
		lim.Parent = t
	end
	if hold then
		local h = Instance.new("TextLabel")
		h.BackgroundTransparency = 1
		h.AnchorPoint = Vector2.new(0.5, 1)
		h.Position = UDim2.new(0.5, 0, 1, -6)
		h.Size = UDim2.new(1, -8, 0, 22)
		h.FontFace = F.TITLE_REG
		h.TextSize = UiKit.text(18)
		h.TextColor3 = UiKit.INK
		h.Text = "SEGURAR"
		h.Parent = key
	end
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, 120)
	name.Size = UDim2.fromOffset(170, 40)
	name.FontFace = F.TITLE_MED
	name.TextSize = UiKit.text(28)
	name.TextColor3 = V.KHAKI
	name.Text = c.label
	name.Parent = box
end

-- 1º cartão: a barra dos objetivos (as cores do HUD da frente: azul dos EUA, vermelho do VC)
local function objectivesBar()
	local owners = { V.VC, V.VC, V.MUTED, V.US, V.US }
	for i, letter in { "A", "B", "C", "D", "E" } do
		local b = Instance.new("Frame")
		b.Size = UDim2.fromOffset(110, 110)
		b.BackgroundColor3 = owners[i]
		b.BorderSizePixel = 0
		b.LayoutOrder = i
		b.Parent = art
		UiKit.corner(b, 8)
		if i == 3 then
			UiKit.edge(b, UiKit.BRASS, 4, 0) -- o da vez
		end
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.FontFace = F.TITLE
		t.TextSize = UiKit.text(60)
		t.TextColor3 = V.TEXT
		t.Text = letter
		t.Parent = b
	end
end

local function draw()
	local card = ComoJogar.CARDS[index]
	kicker.Text = string.format("COMO JOGAR  ·  %d / %d", index, #ComoJogar.CARDS)
	title.Text = card.title
	body.Text = card.text
	for _, c in art:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if card.objectives then
		objectivesBar()
	end
	for i, c in card.chips do
		chip(c, i)
	end
	for i, d in dotFrames do
		d.BackgroundColor3 = if i == index then UiKit.BRASS else V.MUTED
	end
	prevB.Visible = index > 1
	nextB.Text = if index < #ComoJogar.CARDS then "PRÓXIMO  ►" else "PRONTO"
end

local function focusNext()
	if open and Input.isGamepad() then
		GuiService.SelectedObject = nextB
	end
end

function ComoJogar.isOpen(): boolean
	return open
end

function ComoJogar.close()
	if not open then
		return
	end
	open = false
	gui.Enabled = false
	UiKit.closed("como_jogar")
	Input.closeMenu()
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
	Bus.fire("como_jogar_closed")
end

function ComoJogar.open()
	if open then
		return
	end
	open = true
	index = 1
	draw()
	gui.Enabled = true
	UiKit.opened("como_jogar", 39)
	Input.openMenu()
	panel.Position = UDim2.new(0.5, 0, 0.5, 24)
	UiKit.tween(panel, UiKit.SOFT, { Position = UDim2.fromScale(0.5, 0.5) })
	focusNext()
end

local function step(dir: number)
	if not open then
		return
	end
	local n = index + dir
	if n > #ComoJogar.CARDS then
		ComoJogar.close()
		return
	end
	index = math.clamp(n, 1, #ComoJogar.CARDS)
	draw()
	focusNext()
end

UiKit.bind(prevB, function()
	step(-1)
end)
UiKit.bind(nextB, function()
	step(1)
end)
UiKit.bind(closeB, ComoJogar.close)

-- setas do teclado trocam de cartão; no controle, LB/RB (o direcional anda entre os botões)
UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
	if not open or processed then
		return
	end
	if io.KeyCode == Enum.KeyCode.Left then
		step(-1)
	elseif io.KeyCode == Enum.KeyCode.Right then
		step(1)
	end
end)
Input.on("ui_tab_prev", "press", function()
	if open and UiKit.top() == "como_jogar" then
		step(-1)
	end
end)
Input.on("ui_tab_next", "press", function()
	if open and UiKit.top() == "como_jogar" then
		step(1)
	end
end)
Input.on("ui_back", "press", function()
	if open and UiKit.backFor("como_jogar") then
		ComoJogar.close()
	end
end)
Input.DeviceChanged:Connect(function()
	if open then
		draw()
		focusNext()
	end
end)

Bus.on("como_jogar_open", ComoJogar.open)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "como_jogar" then
			ComoJogar.open()
		end
	end)
end

return ComoJogar
