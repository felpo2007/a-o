--!strict
-- Tutorial fora da partida: "COMO JOGAR" (lote 5, D-117; pedido do dono: "não quero mais o tutorial
-- dentro do jogo"; "uma criança tem que conseguir jogar o jogo"). Abre pelo TUTORIAL do menu
-- principal (ou Bus "como_jogar_open", que o "refazer o tutorial" do menu do jogo também usa).
-- D-118 (pedido do dono: "o tutorial tem que se adaptar conforme o local que a pessoa está jogando"):
-- tudo segue o aparelho de agora e muda na hora quando ele muda:
--   - uma etiqueta no alto diz onde: NO CELULAR, NO CONTROLE ou NO COMPUTADOR;
--   - a frase do cartão tem versão para cada aparelho quando o jeito de fazer muda (no celular,
--     "toque em FOGO"; no controle, "aperte RT");
--   - os chips mostram o botão certo (tecla, botão do controle com a imagem do Roblox ou o nome do
--     botão na tela de toque) com o nome da ação embaixo;
--   - ao lado, o desenho do aparelho com o botão daquele assunto aceso no lugar dele: o celular com
--     os botões do layout de toque (Shared/Toque, onde eles ficam de verdade), o controle ou o
--     teclado e o mouse.
-- Texto e botão ficam separados: a tradução casa a frase inteira.
-- Controle: LB/RB trocam de cartão, A no PRÓXIMO passa, B fecha. Teclado: setas, Enter,
-- Backspace. Toque e mouse: os botões ANTERIOR, PRÓXIMO e FECHAR.
-- Studio: workspace:SetAttribute("VT65DevTela", "como_jogar") abre.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Toque = require(ReplicatedStorage.Shared.Toque)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local ComoJogar = {}
local V, F = UiKit.V, UiKit.F

-- chip: a ação (id) e, quando o aparelho usa outra, a dele (kbm = teclado e mouse, pad, touch)
type Chip = { id: string, label: string, kbm: string?, pad: string?, touch: string? }
type Card = {
	title: string,
	text: string, -- computador (e o padrão)
	pad: string?, -- controle
	touch: string?, -- celular
	chips: { Chip },
	objectives: boolean?,
}

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
		pad = "Ande com o analógico esquerdo e aperte ele para correr. Pule para passar por cima de muretas e sebes.",
		touch = "Arraste o polegar no analógico, embaixo à esquerda, para andar; leve até a borda para correr. Toque em PULAR para passar por cima de muretas.",
		chips = {
			{ id = "move", label = "Andar" },
			{ id = "sprint", label = "Correr" },
			{ id = "jump", label = "Pular" },
		},
	},
	{
		title = "MIRAR E ATIRAR",
		text = "Mire antes de atirar: a bala vai para onde a alça da arma aponta. Quando as balas acabarem, recarregue.",
		pad = "Segure LT para mirar e aperte RT para atirar: a bala vai para onde a alça da arma aponta. Recarregue quando as balas acabarem.",
		touch = "Toque em MIRA e depois em FOGO: a bala vai para onde a alça da arma aponta. Quando as balas acabam, o botão RECARGA aparece.",
		chips = {
			{ id = "aim", label = "Mirar" },
			{ id = "fire", label = "Atirar" },
			{ id = "reload", label = "Recarregar" },
		},
	},
	{
		title = "SE PROTEGER",
		text = "Abaixado ou deitado, você é um alvo menor e erra menos. Fique atrás de casas, árvores e muretas.",
		touch = "Toque em AGACHAR para abaixar; segure para deitar. Abaixado ou deitado, você é um alvo menor e erra menos.",
		chips = { { id = "crouch", label = "Abaixar" }, { id = "prone", label = "Deitar" } },
	},
	{
		title = "GRANADA E FACA",
		text = "A granada tira o inimigo de trás da cobertura. Bem de perto, use a faca.",
		touch = "A granada fica no botão ITEM. Bem perto do inimigo, aparece o botão GOLPE para usar a faca.",
		chips = {
			{ id = "quick_grenade", kbm = "slot_3", touch = "last_item", label = "Granada" },
			{ id = "melee", label = "Faca" },
		},
	},
	{
		title = "A CARTA",
		text = "A carta mostra os objetivos, o seu squad e onde você pode nascer. Marque o inimigo para o seu squad ver.",
		touch = "Toque em MAPA, no alto à esquerda, para ver os objetivos e o seu squad. Toque em COMUNICAR para marcar o inimigo.",
		chips = { { id = "map", label = "Carta" }, { id = "mark", label = "Marcar" } },
	},
	{
		title = "FERIDO",
		text = "Ferido, você cai e sangra. Faça um curativo, espere um médico do seu lado ou escolha renascer.",
		touch = "Ferido, você sangra: toque em BANDAGEM, que aparece à esquerda. Se cair, espere um médico do seu lado ou escolha renascer.",
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
		touch = "Chegue perto de um jipe, caminhão, tanque ou helicóptero: o botão para entrar aparece no meio da tela.",
		chips = { { id = "interact", label = "Entrar" } },
	},
} :: { Card }

ComoJogar.DEVICE_NAME = {
	toque = "NO CELULAR",
	controle = "NO CONTROLE",
	teclado = "NO COMPUTADOR",
} :: { [string]: string }

local ACTION: { [string]: InputMap.Action } = {}
for _, a in InputMap.ACTIONS do
	ACTION[a.id] = ACTION[a.id] or a
end

-- ação -> botão da tela de toque (spec "a|b" e "a:tap"), mais o analógico para andar e correr
ComoJogar.TOUCH_BUTTON = { move = "stick", sprint = "stick", interact = "interact" } :: { [string]: string }
for _, d in Toque.BUTTONS do
	for part in string.gmatch(d.spec or "", "[^|]+") do
		local id = string.match(part, "^([%w_]+)")
		if id and ComoJogar.TOUCH_BUTTON[id] == nil then
			ComoJogar.TOUCH_BUTTON[id] = d.id
		end
	end
end

-- os botões do mouse por extenso (quem nunca jogou não sabe o que é RMB)
local MOUSE_TEXT = {
	LMB = "CLIQUE ESQUERDO",
	RMB = "CLIQUE DIREITO",
	MMB = "RODINHA",
} :: { [string]: string }

-- controle: as peças do desenho (posição no desenho, tamanho, arredondado, letra) e o nome curto
-- do botão quando o Roblox não tem a imagem
type PadPart = { code: string, x: number, y: number, w: number, h: number, r: number, txt: string }
local PAD_PARTS: { PadPart } = {
	{ code = "ButtonL2", x = 102, y = 14, w = 64, h = 22, r = 8, txt = "LT" },
	{ code = "ButtonR2", x = 298, y = 14, w = 64, h = 22, r = 8, txt = "RT" },
	{ code = "ButtonL1", x = 102, y = 42, w = 78, h = 18, r = 8, txt = "LB" },
	{ code = "ButtonR1", x = 298, y = 42, w = 78, h = 18, r = 8, txt = "RB" },
	{ code = "Thumbstick1", x = 128, y = 122, w = 44, h = 44, r = 22, txt = "L" },
	{ code = "Thumbstick2", x = 244, y = 172, w = 44, h = 44, r = 22, txt = "R" },
	{ code = "DPadUp", x = 158, y = 156, w = 18, h = 18, r = 3, txt = "" },
	{ code = "DPadDown", x = 158, y = 192, w = 18, h = 18, r = 3, txt = "" },
	{ code = "DPadLeft", x = 140, y = 174, w = 18, h = 18, r = 3, txt = "" },
	{ code = "DPadRight", x = 176, y = 174, w = 18, h = 18, r = 3, txt = "" },
	{ code = "ButtonY", x = 276, y = 100, w = 26, h = 26, r = 13, txt = "Y" },
	{ code = "ButtonX", x = 250, y = 124, w = 26, h = 26, r = 13, txt = "X" },
	{ code = "ButtonB", x = 302, y = 124, w = 26, h = 26, r = 13, txt = "B" },
	{ code = "ButtonA", x = 276, y = 148, w = 26, h = 26, r = 13, txt = "A" },
	{ code = "ButtonSelect", x = 186, y = 114, w = 18, h = 12, r = 6, txt = "" },
	{ code = "ButtonStart", x = 234, y = 114, w = 18, h = 12, r = 6, txt = "" },
}
local PAD_TEXT: { [string]: string } = { ButtonL3 = "L", ButtonR3 = "R", ButtonSelect = "VIEW", ButtonStart = "MENU" }
for _, p in PAD_PARTS do
	if p.txt ~= "" then
		PAD_TEXT[p.code] = PAD_TEXT[p.code] or p.txt
	end
end
local PAD_ALIAS: { [string]: string } = { ButtonL3 = "Thumbstick1", ButtonR3 = "Thumbstick2" }

local function device(): string
	if ToqueUi.active() then
		return "toque"
	elseif Input.isGamepad() then
		return "controle"
	end
	return "teclado"
end

-- ação do chip no aparelho de agora
local function chipAction(c: Chip, dev: string): string
	if dev == "toque" then
		return c.touch or c.id
	elseif dev == "controle" then
		return c.pad or c.id
	end
	return c.kbm or c.id
end

-- botão da ação no aparelho de agora: (imagem do controle, texto curto, pede segurar?, código do
-- botão no controle ou nome da tecla, para acender no desenho)
local function keyOf(id: string, dev: string): (string?, string, boolean, string?)
	if id == "move" then
		if dev == "toque" then
			return nil, "ANALÓGICO", false, nil
		elseif dev == "controle" then
			local stick = UiKit.padImage(Enum.KeyCode.Thumbstick1)
			-- sem a imagem do Roblox (Studio: veio vazia e o chip ficou em branco), a letra
			return if stick and stick ~= "" then stick else nil, "L", false, "Thumbstick1"
		end
		return nil, "W A S D", false, "WASD"
	end
	if dev == "toque" then
		return nil, ToqueTelas.touchName(id), false, nil
	end
	local img, txt = Input.glyph(id)
	local code = txt
	if dev == "controle" then
		txt = PAD_TEXT[txt] or txt
	else
		txt = MOUSE_TEXT[txt] or txt
	end
	local a = ACTION[id]
	local kind = if a then (if dev == "controle" then a.padPress else a.keyPress) else nil
	return img, txt, kind == "hold", code
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

local W, H = 1040, 640
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
kicker.Size = UDim2.fromOffset(420, 26)
local title = label(panel, F.TITLE, 52, V.TEXT)
title.Position = UDim2.fromOffset(40, 56)
title.Size = UDim2.fromOffset(W - 500, 62)
local rule = Instance.new("Frame")
rule.BackgroundColor3 = V.BRASS
rule.BorderSizePixel = 0
rule.Position = UDim2.fromOffset(40, 122)
rule.Size = UDim2.fromOffset(88, 4)
rule.Parent = panel
local body = label(panel, F.BODY, 24, V.TEXT)
body.Position = UDim2.fromOffset(40, 142)
body.Size = UDim2.fromOffset(W - 80, 110)

-- etiqueta do aparelho (no alto, ao lado do FECHAR)
local devTag = Instance.new("TextLabel")
devTag.Name = "Aparelho"
devTag.AnchorPoint = Vector2.new(1, 0)
devTag.Position = UDim2.fromOffset(W - 40 - 170 - 16, 28)
devTag.Size = UDim2.fromOffset(250, 50)
devTag.BackgroundColor3 = V.OLIVE
devTag.BorderSizePixel = 0
devTag.FontFace = F.TITLE
devTag.TextSize = UiKit.text(26)
devTag.TextColor3 = UiKit.BRASS_LIGHT
devTag.Parent = panel
UiKit.corner(devTag, 25)
UiKit.edge(devTag, UiKit.BRASS, 2, 0)

-- chips à esquerda (ou a barra dos objetivos no 1º cartão)
local art = Instance.new("Frame")
art.Name = "Botoes"
art.BackgroundTransparency = 1
art.Position = UDim2.fromOffset(40, 268)
art.Size = UDim2.fromOffset(520, 250)
art.Parent = panel
local artList = Instance.new("UIListLayout")
artList.FillDirection = Enum.FillDirection.Horizontal
artList.HorizontalAlignment = Enum.HorizontalAlignment.Center
artList.VerticalAlignment = Enum.VerticalAlignment.Center
artList.Padding = UDim.new(0, 16)
artList.Parent = art

-- o desenho do aparelho à direita
local DEV_W, DEV_H = 420, 250
local devBox = Instance.new("Frame")
devBox.Name = "Desenho"
devBox.BackgroundTransparency = 1
devBox.Position = UDim2.fromOffset(W - 40 - DEV_W, 268)
devBox.Size = UDim2.fromOffset(DEV_W, DEV_H)
devBox.Parent = panel

-- pé: anterior, pontos, próximo; fechar no canto
local function footButton(text: string, x: number, w: number, kind: string): TextButton
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
	return b
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
local pulses: { Tween } = {}

-- ===== chips =====
local function chip(c: Chip, order: number, dev: string)
	local img, txt, hold = keyOf(chipAction(c, dev), dev)
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(150, 170)
	box.LayoutOrder = order
	box.Parent = art
	local key = Instance.new("Frame")
	key.AnchorPoint = Vector2.new(0.5, 0)
	key.Position = UDim2.fromScale(0.5, 0)
	key.Size = UDim2.fromOffset(140, 110)
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
	name.Size = UDim2.fromOffset(150, 40)
	name.FontFace = F.TITLE_MED
	name.TextSize = UiKit.text(26)
	name.TextColor3 = V.KHAKI
	name.Text = c.label
	name.Parent = box
end

-- 1º cartão: a barra dos objetivos (as cores do HUD da frente: azul dos EUA, vermelho do VC)
local function objectivesBar()
	local owners = { V.VC, V.VC, V.MUTED, V.US, V.US }
	for i, letter in { "A", "B", "C", "D", "E" } do
		local b = Instance.new("Frame")
		b.Size = UDim2.fromOffset(84, 84)
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
		t.TextSize = UiKit.text(48)
		t.TextColor3 = V.TEXT
		t.Text = letter
		t.Parent = b
	end
end

-- ===== desenho do aparelho =====
local OFF = Color3.fromRGB(70, 74, 62) -- peça apagada
local OFF_TEXT = Color3.fromRGB(160, 160, 142)
local SHELL = Color3.fromRGB(26, 28, 24)

local function piece(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	round: number,
	lit: boolean,
	txt: string?
): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = if lit then UiKit.BRASS else OFF
	f.BorderSizePixel = 0
	f.ZIndex = 3
	f.Parent = parent
	UiKit.corner(f, round)
	if lit then
		f.Name = "Aceso"
		local ring = Instance.new("UIStroke")
		ring.Color = UiKit.BRASS_LIGHT
		ring.Thickness = 3
		ring.Parent = f
		local tw = TweenService:Create(
			ring,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = 7, Transparency = 0.6 }
		)
		tw:Play()
		table.insert(pulses, tw)
	end
	if txt and txt ~= "" then
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.FontFace = F.TITLE
		t.TextScaled = true
		t.TextColor3 = if lit then UiKit.INK else OFF_TEXT
		t.Text = txt
		t.ZIndex = 4
		t.Parent = f
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 2)
		pad.PaddingRight = UDim.new(0, 2)
		pad.PaddingTop = UDim.new(0, 1)
		pad.PaddingBottom = UDim.new(0, 1)
		pad.Parent = t
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = 20
		lim.Parent = t
	end
	return f
end

local function shell(x: number, y: number, w: number, h: number, round: number, z: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = SHELL
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = devBox
	UiKit.corner(f, round)
	UiKit.edge(f, V.LINE, 2, 0)
	return f
end

local function legenda(text: string)
	local t = label(devBox, F.TITLE_REG, 18, V.DIM)
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 1, -22)
	t.Size = UDim2.fromOffset(DEV_W, 22)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.Text = text
end

-- celular deitado com os botões do layout de toque (Toque.PRESETS.two) no lugar deles
local function drawPhone(lit: { [string]: boolean })
	local pw, ph = 400, 196
	local phone = shell(DEV_W / 2, 2 + ph / 2, pw, ph, 26, 1)
	phone.BackgroundColor3 = Color3.fromRGB(12, 12, 10)
	local screen = Instance.new("Frame")
	screen.AnchorPoint = Vector2.new(0.5, 0.5)
	screen.Position = UDim2.fromScale(0.5, 0.5)
	screen.Size = UDim2.new(1, -28, 1, -16)
	screen.BackgroundColor3 = Color3.new(1, 1, 1)
	screen.BorderSizePixel = 0
	screen.ZIndex = 2
	screen.Parent = phone
	UiKit.corner(screen, 16)
	local sg = Instance.new("UIGradient")
	sg.Rotation = 90
	sg.Color = ColorSequence.new(Color3.fromRGB(96, 112, 124), Color3.fromRGB(52, 64, 40))
	sg.Parent = screen
	local sw, sh = pw - 28, ph - 16
	local layout = Toque.PRESETS.two
	for _, d in Toque.BUTTONS do
		local pos = layout[d.id]
		local isLit = lit[d.id] == true
		-- os botões de sempre e os acesos (os contextuais só aparecem quando servem)
		local always = d.show == "move" or d.show == "foot" or d.show == "game" or d.show == "talk"
		if pos and not d.optional and (always or isLit) then
			local size = math.clamp(d.mm * 2.6, 22, 64)
			local txt = if d.id == "interact" then "►" else d.glyph
			piece(screen, pos.x * sw, pos.y * sh, size, size, math.floor(size / 2), isLit, txt)
		end
	end
	legenda("A tela do seu celular: o botão aceso é este")
end

-- controle: gatilhos e botões de ombro em cima, analógicos, direcional, A B X Y, View e Menu
local function drawPad(lit: { [string]: boolean })
	shell(DEV_W / 2, 130, 300, 150, 60, 2)
	for _, s in { -1, 1 } do
		shell(DEV_W / 2 + s * 112, 180, 86, 86, 43, 1)
	end
	for _, p in PAD_PARTS do
		piece(devBox, p.x, p.y, p.w, p.h, p.r, lit[p.code] == true, p.txt)
	end
	legenda("O seu controle: o botão aceso é este")
end

-- teclado (o lado esquerdo, onde a mão fica) e o mouse
local KEY_ROWS: { { string } } = {
	{ "1", "2", "3", "4", "5" },
	{ "Tab", "Q", "W", "E", "R", "T" },
	{ "Caps Lock", "A", "S", "D", "F", "G" },
	{ "Shift", "Z", "X", "C", "V", "B", "N", "M" },
	{ "Ctrl", "Alt", "Espaço" },
}
local KEY_W: { [string]: number } = { Tab = 46, ["Caps Lock"] = 56, Shift = 66, Ctrl = 46, Alt = 40, ["Espaço"] = 160 }

local function drawKeyboard(lit: { [string]: boolean })
	local x0, y0, kw, gap = 6, 10, 30, 4
	for r, row in KEY_ROWS do
		local x = x0 + (if r == 1 then 18 else 0)
		for _, k in row do
			local w = KEY_W[k] or kw
			local txt = if k == "Caps Lock" then "CAPS" elseif k == "Espaço" then "ESPAÇO" else string.upper(k)
			piece(devBox, x + w / 2, y0 + (r - 1) * (kw + 4) + kw / 2, w, kw, 5, lit[k] == true, txt)
			x += w + gap
		end
	end
	-- mouse: corpo, botões esquerdo e direito e a rodinha
	local mx, my = 368, 96
	shell(mx, my + 22, 84, 136, 40, 2)
	piece(devBox, mx - 20, my - 12, 36, 50, 10, lit.LMB == true, "")
	piece(devBox, mx + 20, my - 12, 36, 50, 10, lit.RMB == true, "")
	piece(devBox, mx, my - 16, 10, 22, 5, lit.MMB == true, "")
	legenda("O seu teclado e o mouse: o que está aceso é o botão")
end

local function clearDevice()
	for _, tw in pulses do
		tw:Cancel()
	end
	table.clear(pulses)
	for _, c in devBox:GetChildren() do
		c:Destroy()
	end
end

-- o que acende no desenho: ids de botão de toque, códigos do controle ou nomes de tecla
function ComoJogar.litFor(card: Card, dev: string): { [string]: boolean }
	local lit: { [string]: boolean } = {}
	for _, c in card.chips do
		local id = chipAction(c, dev)
		if dev == "toque" then
			local b = ComoJogar.TOUCH_BUTTON[id]
			if b then
				lit[b] = true
			end
		else
			local _, _, _, code = keyOf(id, dev)
			if code == "WASD" then
				lit.W, lit.A, lit.S, lit.D = true, true, true, true
			elseif code then
				lit[PAD_ALIAS[code] or code] = true
			end
		end
	end
	return lit
end

local function drawDevice(card: Card, dev: string)
	clearDevice()
	local lit = ComoJogar.litFor(card, dev)
	if dev == "toque" then
		drawPhone(lit)
	elseif dev == "controle" then
		drawPad(lit)
	else
		drawKeyboard(lit)
	end
end

local function draw()
	local card = ComoJogar.CARDS[index]
	local dev = device()
	kicker.Text = string.format("COMO JOGAR  ·  %d / %d", index, #ComoJogar.CARDS)
	devTag.Text = ComoJogar.DEVICE_NAME[dev]
	title.Text = card.title
	body.Text = (if dev == "toque" then card.touch elseif dev == "controle" then card.pad else nil) or card.text
	for _, c in art:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if card.objectives then
		objectivesBar()
	end
	for i, c in card.chips do
		chip(c, i, dev)
	end
	-- o 1º cartão não tem botão: a barra dos objetivos ocupa a largura toda
	art.Size = UDim2.fromOffset(if card.objectives then W - 80 else 520, 250)
	if card.objectives then
		clearDevice()
	else
		drawDevice(card, dev)
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
	clearDevice()
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
-- trocou de aparelho no meio (pegou o controle, tocou na tela): o cartão se refaz na hora
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
