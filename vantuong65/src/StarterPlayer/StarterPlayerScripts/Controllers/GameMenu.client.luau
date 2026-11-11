--!strict
-- Menu do jogo (segurar View / tecla P): abas Configurações, Squad e papel, Loja (e Servidor, para o
-- dono de servidor privado). LB/RB trocam abas, LT/RT trocam sub-abas, A confirma, B volta
-- (Parte 12.5). Nada exige digitar: números e escolhas mudam com A, com o direcional ◄ ► ou com as
-- setas da linha; o remapeamento espera o próximo botão do controle (ou a próxima tecla).
-- Configurações saem da conta (Settings_Get) e voltam para ela (Settings_Save) pela camada Input.
-- Visual (pedido do dono, 2026-11-11: "melhore ainda mais todas as interfaces"; D-82 ainda era
-- simples): pasta parda de dossiê com abas de arquivo, folha pautada com linha vermelha, títulos em
-- Oswald, rótulos em Arimo, valores em etiqueta oliva com ◄ ►, carimbo no título, dicas de botão em
-- chip no pé. Entra subindo e assentando; a troca de aba desliza a folha. Cabe em qualquer janela
-- (UiKit.fit: abaixo de 840 x 600 o dossiê encolhe inteiro, nada passa da borda). Redesenhar mantém
-- o foco e a rolagem na mesma linha (antes o foco do controle pulava para o alto a cada mudança).
-- Tutorial em andamento: faixa no alto da folha com "Pular o tutorial" (focada primeiro). Para não
-- pular sem querer: segurar Y (livre no contexto do menu), ou A/clique duas vezes.
-- Idioma: botão "IDIOMA · LANGUAGE" no alto (X no controle) abre o cartão de idiomas (Idioma).
-- Só no Studio: workspace:SetAttribute("VT65DevTela", "menu") abre o menu.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Accessibility = require(ReplicatedStorage.Shared.Accessibility)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Kit = require(ReplicatedStorage.Shared.Kit)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Net = require(ReplicatedStorage.Shared.Net)
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Idioma = require(ReplicatedFirst:WaitForChild("Idioma"))
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)
local VirtualCursor = require(script.Parent.VirtualCursor)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

-- medidas de projeto (o UiKit.fit encolhe tudo numa janela menor)
local L = {
	W = px(840, 1120),
	H = px(600, 800),
	HEAD = px(72, 98),
	TAB_H = px(38, 54),
	FOOT = px(50, 70),
	ROW = px(42, 60),
	BANNER = px(58, 82),
	SUB = px(40, 56),
	PAD = px(16, 22),
}
local C = {
	ink = UiKit.INK,
	card = UiKit.CARD,
	hot = Color3.fromRGB(250, 244, 226),
	manila = UiKit.MANILA,
	tabOff = Color3.fromRGB(170, 148, 102),
	drab = UiKit.DRAB,
	khaki = UiKit.KHAKI,
	brass = UiKit.BRASS,
	stamp = UiKit.STAMP,
	red = UiKit.RULE_RED,
	blue = UiKit.RULE_BLUE,
	olive = UiKit.OLIVE,
}

-- ===== tela =====
local gui = UiKit.screen("VT65GameMenu", 35)
gui.Enabled = false

local U: { [string]: any } = {}
do
	local dim = Instance.new("Frame")
	dim.Name = "Veu"
	dim.Position = UDim2.fromOffset(0, -60) -- cobre também a faixa do Roblox
	dim.Size = UDim2.new(1, 0, 1, 60)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = gui
	U.dim = dim

	local root = Instance.new("Frame")
	root.Name = "Dossie"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(L.W, L.H)
	root.BackgroundColor3 = C.manila
	root.BorderSizePixel = 0
	root.Active = true
	root.Parent = gui
	UiKit.corner(root, 5)
	UiKit.lit(root, 0.8)
	UiKit.edge(root, C.ink, 1, 0.55)
	U.root = root
	U.fit = UiKit.fit(gui, root, L.W, L.H, 12)
	Acabamento.sombra(root, 26, Vector2.new(0, 10), 0.6)

	-- cabeçalho: rubrica datilografada e o título da aba com carimbo
	local kicker = UiKit.rotulo(root, px(14, 22), C.ink, UiKit.TYPE_FONT)
	kicker.Position = UDim2.fromOffset(L.PAD + 6, px(10, 14))
	kicker.Size = UDim2.fromOffset(px(420, 560), px(18, 26))
	kicker.TextTransparency = 0.3
	kicker.Text = "MENU DO JOGO · OPERAÇÃO STARLITE · 1965"
	local title = UiKit.rotulo(root, px(30, 44), C.ink, UiKit.HEAD_FONT)
	title.Position = UDim2.fromOffset(L.PAD + 4, px(26, 36))
	title.Size = UDim2.fromOffset(px(420, 560), px(40, 56))
	U.title = title
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title
	U.titleScale = titleScale

	-- fechar (mouse e toque; no controle é o B)
	local close = Instance.new("TextButton")
	close.Name = "Fechar"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -L.PAD, 0, px(16, 22))
	close.Size = UDim2.fromOffset(px(112, 160), px(36, 50))
	close.BackgroundColor3 = C.drab
	close.AutoButtonColor = false
	close.FontFace = UiKit.HEAD_FONT
	close.TextColor3 = C.khaki
	close.TextSize = UiKit.text(16)
	close.Text = "FECHAR ×"
	close.Selectable = false
	close.Parent = root
	UiKit.corner(close, 3)
	UiKit.lit(close, 0.72)
	U.close = close

	-- abas de arquivo (o mouse clica; no controle LB/RB)
	local tabs = Instance.new("Frame")
	tabs.Name = "Abas"
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(L.PAD, L.HEAD)
	tabs.Size = UDim2.new(1, -2 * L.PAD, 0, L.TAB_H)
	tabs.Parent = root
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 4)
	tl.Parent = tabs
	U.tabs = tabs

	-- folha pautada
	local sheet = Instance.new("Frame")
	sheet.Name = "Folha"
	sheet.Position = UDim2.fromOffset(L.PAD - 4, L.HEAD + L.TAB_H)
	sheet.Size = UDim2.new(1, -2 * (L.PAD - 4), 1, -(L.HEAD + L.TAB_H + L.FOOT))
	sheet.BackgroundColor3 = C.card
	sheet.BorderSizePixel = 0
	sheet.ClipsDescendants = true
	sheet.Parent = root
	UiKit.corner(sheet, 3)
	UiKit.lit(sheet, 0.9)
	UiKit.edge(sheet, C.ink, 1, 0.6)
	U.sheet = sheet
	local redRule = Instance.new("Frame")
	redRule.BackgroundColor3 = C.red
	redRule.BorderSizePixel = 0
	redRule.Position = UDim2.fromOffset(0, 3)
	redRule.Size = UDim2.new(1, 0, 0, 2)
	redRule.Parent = sheet

	-- pé: dicas de botão
	local foot = UiKit.chips(root, px(30, 44), true, px(14, 22))
	foot.frame.AnchorPoint = Vector2.new(0, 1)
	foot.frame.Position = UDim2.new(0, L.PAD + 4, 1, -px(10, 14))
	foot.frame.Size = UDim2.new(1, -2 * L.PAD, 0, px(30, 44))
	U.foot = foot
end

-- ===== estado =====
local BASE_TABS = { "Configurações", "Squad e papel", "Loja" }
local SUBS = { "Controle", "Mira", "Mouse/teclado", "Gráficos", "Som", "Vibração", "Acessib.", "Botões" }
-- servidor privado: só o dono vê a aba "Servidor" (modo e horário; o servidor revalida)
local MODES = { "Warfare", "Offensive", "Skirmish" }
local MODE_NAMES = { "Warfare (5 setores, 75 min)", "Offensive (EUA atacam do leste)", "Skirmish (1 setor, 20 min)" }
local CLOCKS = { 6.5, 12, 18.5 }
local CLOCK_NAMES = { "06:30 (amanhecer)", "12:00", "18:30 (entardecer)" }
local CTX_NAMES: { [string]: string } = {
	infantry = "Infantaria",
	aim = "Mirando",
	global = "Geral",
	ground_vehicle = "Veículo",
	helicopter = "Helicóptero",
	map = "Mapa",
	wheel = "Roda",
	menu = "Menus",
}
local CTX_ORDER = { "infantry", "aim", "global", "ground_vehicle", "helicopter", "map", "wheel", "menu" }
local MOUSE_KEYS: { [Enum.UserInputType]: string } = {
	[Enum.UserInputType.MouseButton1] = "MouseLeftButton",
	[Enum.UserInputType.MouseButton2] = "MouseRightButton",
	[Enum.UserInputType.MouseButton3] = "MouseMiddleButton",
}

local S = {
	tab = 1,
	sub = 1,
	psMode = 1,
	psClock = 1,
	kit = nil :: Kit.Kit?,
	listening = nil :: string?, -- "ctx.actionId" esperando um botão do controle
	keyListening = nil :: string?, -- "ctx.actionId" esperando uma tecla
	-- A tecla capturada chega também às ações do menu (Q/E/Z/C, LB/RB...), às vezes depois da
	-- captura: por um instante após capturar, as abas não trocam e o menu não fecha (D-82).
	swallowUntil = 0,
	order = 0,
	menuCursor = false,
	armedUntil = 0, -- "Pular o tutorial": o primeiro A/clique arma por 3 s
	lastTab = 0,
	dirty = true, -- algo mudou com o menu fechado: redesenha ao abrir (senão abre o que já existe)
}
local function busy(): boolean
	return S.listening ~= nil or S.keyListening ~= nil or os.clock() < S.swallowUntil
end
local function isOwner(): boolean
	return ReplicatedStorage:GetAttribute("PrivateServer") == true and game.PrivateServerOwnerId == player.UserId
end
local function TABS(): { string }
	local t = table.clone(BASE_TABS)
	if isOwner() then
		table.insert(t, "Servidor")
	end
	return t
end
local function kitKind(): string
	local wid = string.split(tostring(player:GetAttribute("Loadout") or ""), ",")[1]
	local wp = Weapons.get(wid)
	return if wp then wp.kind else "rifle"
end
local function tutorialActive(): boolean
	return type(player:GetAttribute("TutorialPasso")) == "number"
end

-- ===== faixa do tutorial =====
do
	local banner = Instance.new("Frame")
	banner.Name = "Tutorial"
	banner.BackgroundColor3 = C.drab
	banner.BorderSizePixel = 0
	banner.Position = UDim2.fromOffset(10, 12)
	banner.Size = UDim2.new(1, -20, 0, L.BANNER - 8)
	banner.Visible = false
	banner.Parent = U.sheet
	UiKit.corner(banner, 3)
	UiKit.lit(banner, 0.72)
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = C.brass
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0, px(5, 7), 1, 0)
	bar.Parent = banner
	local head = UiKit.rotulo(banner, px(13, 22), UiKit.BRASS_LIGHT, UiKit.HEAD_FONT)
	head.Position = UDim2.fromOffset(px(16, 22), px(4, 6))
	head.Size = UDim2.new(1, -px(300, 420), 0, px(20, 28))
	head.Text = "TUTORIAL EM ANDAMENTO"
	local info = UiKit.rotulo(banner, px(15, 24), C.card, UiKit.BODY_FONT)
	info.Position = UDim2.fromOffset(px(16, 22), px(24, 34))
	info.Size = UDim2.new(1, -px(300, 420), 0, px(22, 32))
	info.TextTruncate = Enum.TextTruncate.AtEnd
	local skip = Instance.new("TextButton")
	skip.Name = "PularTutorial"
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -px(10, 14), 0.5, 0)
	skip.Size = UDim2.fromOffset(px(270, 390), L.BANNER - 22)
	skip.BackgroundColor3 = C.stamp
	skip.AutoButtonColor = false
	skip.Text = ""
	skip.Selectable = true
	skip.SelectionImageObject = UiKit.FOCUS
	skip.Parent = banner
	UiKit.corner(skip, 3)
	UiKit.lit(skip, 0.75)
	local skipText = UiKit.rotulo(skip, px(16, 26), C.card, UiKit.HEAD_FONT)
	skipText.Size = UDim2.new(1, -px(46, 64), 1, 0)
	skipText.Position = UDim2.fromOffset(px(10, 14), 0)
	local skipKey = Instance.new("ImageLabel")
	skipKey.BackgroundTransparency = 1
	skipKey.AnchorPoint = Vector2.new(1, 0.5)
	skipKey.Position = UDim2.new(1, -px(8, 12), 0.5, 0)
	skipKey.Size = UDim2.fromOffset(px(26, 38), px(26, 38))
	skipKey.Parent = skip
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.new(0, 0, 1, 0)
	fill.Size = UDim2.new(0, 0, 0, px(4, 5))
	fill.BackgroundColor3 = C.brass
	fill.BorderSizePixel = 0
	fill.Parent = skip
	U.banner, U.bannerInfo, U.skip, U.skipText, U.skipKey, U.skipFill = banner, info, skip, skipText, skipKey, fill
end

-- ===== sub-abas (Configurações) e o corpo =====
do
	local sub = Instance.new("Frame")
	sub.Name = "SubAbas"
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(1, -20, 0, L.SUB - 6)
	sub.Parent = U.sheet
	local lt = Instance.new("ImageLabel")
	lt.BackgroundTransparency = 1
	lt.Size = UDim2.fromOffset(px(28, 40), px(28, 40))
	lt.Position = UDim2.fromOffset(0, (L.SUB - 6 - px(28, 40)) / 2)
	lt.Parent = sub
	local rt = lt:Clone()
	rt.AnchorPoint = Vector2.new(1, 0)
	rt.Position = UDim2.new(1, 0, 0, lt.Position.Y.Offset)
	rt.Parent = sub
	local strip = Instance.new("ScrollingFrame")
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Position = UDim2.fromOffset(px(34, 48), 0)
	strip.Size = UDim2.new(1, -2 * px(34, 48), 1, 0)
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new()
	strip.ScrollBarThickness = 0
	strip.Selectable = false
	strip.Parent = sub
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.VerticalAlignment = Enum.VerticalAlignment.Center
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Padding = UDim.new(0, 6)
	sl.Parent = strip
	U.subBar, U.subStrip, U.lt, U.rt = sub, strip, lt, rt

	local body = Instance.new("ScrollingFrame")
	body.Name = "Corpo"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ScrollBarThickness = px(6, 8)
	body.ScrollBarImageColor3 = C.ink
	body.ScrollBarImageTransparency = 0.5
	body.Selectable = false
	body.Parent = U.sheet
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 2)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = body
	local bp = Instance.new("UIPadding")
	bp.PaddingTop = UDim.new(0, 4)
	bp.PaddingBottom = UDim.new(0, 12)
	bp.Parent = body
	U.body = body
end

-- posições dentro da folha: faixa do tutorial (se houver), sub-abas (aba 1) e o corpo
local function layoutSheet()
	local y = 10
	U.banner.Visible = tutorialActive()
	if U.banner.Visible then
		U.banner.Position = UDim2.fromOffset(10, y)
		y += L.BANNER
	end
	U.subBar.Visible = S.tab == 1
	if S.tab == 1 then
		U.subBar.Position = UDim2.fromOffset(10, y)
		y += L.SUB
	end
	U.body.Position = UDim2.fromOffset(4, y)
	U.body.Size = UDim2.new(1, -8, 1, -y - 4)
end

-- ===== linhas =====
-- Cada linha é um botão (focável no controle) com o rótulo à esquerda e o valor numa etiqueta
-- oliva à direita. adjust(dir) muda o valor (◄ ► do direcional, das setas da linha e do A).
local adjusters: { [Instance]: (dir: number) -> () } = {}
local updaters: { () -> () } = {} -- valores que mudam no lugar quando a configuração muda

local function rowShell(key: string, labelText: string): (TextButton, TextLabel)
	S.order += 1
	local b = Instance.new("TextButton")
	b.Name = key
	b.LayoutOrder = S.order
	b.Size = UDim2.new(1, -16, 0, L.ROW)
	b.BackgroundColor3 = C.card
	b.BackgroundTransparency = 0
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = U.body
	UiKit.corner(b, 2)
	local rule = Instance.new("Frame")
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.new(0, 6, 1, 0)
	rule.Size = UDim2.new(1, -12, 0, 1)
	rule.BackgroundColor3 = C.blue
	rule.BackgroundTransparency = 0.55
	rule.BorderSizePixel = 0
	rule.Parent = b
	local l = UiKit.rotulo(b, 16, C.ink, UiKit.BODY_FONT)
	l.Position = UDim2.fromOffset(px(12, 16), 0)
	l.Size = UDim2.new(0.58, -px(12, 16), 1, 0)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = labelText
	local r = UiKit.realce(b, C.card, C.hot, 1.008)
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
	return b, l
end

-- etiqueta do valor, com ◄ ► clicáveis quando adjust existe; img = botão do controle
local function valueTag(
	b: TextButton,
	text: string,
	adjust: ((dir: number) -> ())?,
	img: string?,
	waiting: boolean?
): TextLabel
	local tag = Instance.new("Frame")
	tag.Name = "Valor"
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.new(1, -px(8, 12), 0.5, 0)
	tag.Size = UDim2.new(0.4, 0, 1, -px(10, 14))
	tag.BackgroundColor3 = if waiting then C.stamp else C.drab
	tag.BorderSizePixel = 0
	tag.Parent = b
	UiKit.corner(tag, 3)
	UiKit.lit(tag, 0.74)
	local inner = px(28, 40)
	local t = UiKit.rotulo(tag, 15, C.card, UiKit.HEAD_FONT)
	t.Size = UDim2.new(1, -2 * inner, 1, 0)
	t.Position = UDim2.fromOffset(inner, 0)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = text
	t.FontFace = UiKit.headFont(text)
	if img then
		local il = Instance.new("ImageLabel")
		il.BackgroundTransparency = 1
		il.AnchorPoint = Vector2.new(0.5, 0.5)
		il.Position = UDim2.fromScale(0.5, 0.5)
		il.Size = UDim2.fromOffset(px(26, 38), px(26, 38))
		il.Image = img
		il.Parent = tag
		t.Visible = false
	end
	if adjust then
		for _, d in { -1, 1 } do
			local a = Instance.new("TextButton")
			a.Name = if d < 0 then "Menos" else "Mais"
			a.AnchorPoint = Vector2.new(if d < 0 then 0 else 1, 0)
			a.Position = UDim2.fromScale(if d < 0 then 0 else 1, 0)
			a.Size = UDim2.new(0, inner, 1, 0)
			a.BackgroundTransparency = 1
			a.Font = Enum.Font.ArimoBold
			a.TextSize = UiKit.text(14)
			a.TextColor3 = C.khaki
			a.Text = if d < 0 then "◄" else "►"
			a.Selectable = false
			a.Parent = tag
			-- registrada no cursor virtual também: sem isso a seta "tapava" a linha e o A não ia
			UiKit.bind(a, function()
				adjust(d)
			end)
		end
		adjusters[b] = adjust
	end
	return t
end

local function section(text: string)
	S.order += 1
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.LayoutOrder = S.order
	f.Size = UDim2.new(1, -16, 0, px(34, 48))
	f.Parent = U.body
	-- sem caixa alta forçada: o modelo "Teclas · %s" só casa no dicionário como foi escrito
	local t = UiKit.rotulo(f, 16, C.ink, UiKit.HEAD_FONT)
	t.Position = UDim2.fromOffset(px(10, 14), px(8, 12))
	t.Size = UDim2.new(1, -20, 0, px(22, 30))
	t.Text = text
	t.FontFace = UiKit.headFont(text)
	local r = Instance.new("Frame")
	r.AnchorPoint = Vector2.new(0, 1)
	r.Position = UDim2.new(0, px(10, 14), 1, 0)
	r.Size = UDim2.new(1, -2 * px(10, 14), 0, 2)
	r.BackgroundColor3 = C.red
	r.BorderSizePixel = 0
	r.Parent = f
end

local function note(text: string, color: Color3?)
	S.order += 1
	local t = UiKit.rotulo(U.body, 14, color or C.olive, UiKit.TYPE_FONT)
	t.LayoutOrder = S.order
	t.Size = UDim2.new(1, -36, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.TextWrapped = true
	t.Text = text
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 6)
	p.PaddingBottom = UDim.new(0, 6)
	p.Parent = t
end

-- botão de ação de largura inteira (danger = carimbo vermelho)
local function action(key: string, text: string, onClick: () -> (), danger: boolean?)
	local b, l = rowShell(key, text)
	l.Size = UDim2.new(1, -px(24, 32), 1, 0)
	l.FontFace = UiKit.HEAD_FONT
	l.Text = UiKit.upper(text)
	l.FontFace = UiKit.headFont(text)
	l.TextColor3 = if danger then C.stamp else C.ink
	local arrow = UiKit.rotulo(b, 14, if danger then C.stamp else C.olive, Enum.Font.ArimoBold)
	arrow.AnchorPoint = Vector2.new(1, 0)
	arrow.Position = UDim2.new(1, -px(14, 20), 0, 0)
	arrow.Size = UDim2.new(0, px(20, 30), 1, 0)
	arrow.Text = "►"
	UiKit.bind(b, onClick)
end

-- Muda UMA configuração pelo caminho leve do Input (setSetting só refaz os botões quando a chave
-- mexe neles); antes cada ◄ ► recriava todo o Input Action System e redesenhava o menu inteiro.
local function set(k: string, v: any)
	Input.setSetting(k, v)
end

-- valor que muda no lugar (sem redesenhar a folha): a etiqueta troca o texto e dá um pulo
local function refreshTag(t: TextLabel, text: string)
	if t.Text == text then
		return
	end
	t.Text = text
	t.FontFace = UiKit.headFont(text)
	local sc = t:FindFirstChildOfClass("UIScale")
	if not sc then
		local s = Instance.new("UIScale")
		s.Parent = t
		sc = s
	end
	local scale = sc :: UIScale
	scale.Scale = 1.18
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function numberRow(label: string, k: string, step: number, fmt: string, scaleBy: number?)
	local b = rowShell("n:" .. k, label)
	local mul = scaleBy or 1
	local function text(): string
		local v = (Input.settings :: any)[k] * mul
		return string.format(fmt, if mul ~= 1 then math.floor(v + 0.5) else v)
	end
	local function adjust(d: number)
		set(k, (Input.settings :: any)[k] + d * step)
	end
	local t = valueTag(b, text(), adjust)
	table.insert(updaters, function()
		refreshTag(t, text())
	end)
	UiKit.bind(b, function()
		adjust(1)
	end)
end

local function choiceRow(label: string, k: string, options: { any }, names: { string })
	local function idx(): number
		return table.find(options, (Input.settings :: any)[k]) or 1
	end
	local b = rowShell("c:" .. k, label)
	local function adjust(d: number)
		set(k, options[(idx() - 1 + d) % #options + 1])
	end
	local t = valueTag(b, names[idx()], adjust)
	table.insert(updaters, function()
		refreshTag(t, names[idx()])
	end)
	UiKit.bind(b, function()
		adjust(1)
	end)
end

-- ===== conteúdo das abas =====
local render: () -> () = function() end

local function conflictText(raw: string, keyboard: boolean): string
	-- "ctx|código: idA x idB" -> "Conflito: Correr e Inclinar à esquerda em Shift"
	local code, a, b = string.match(raw, "^[^|]+|([^:]+): (%S+) x (%S+)$")
	local function labelOf(id: string?): string
		for _, act in InputMap.ACTIONS do
			if act.id == id then
				return act.label
			end
		end
		return id or "?"
	end
	local where = if code then (if keyboard then UiKit.keyName(code) else string.gsub(code, "Button", "")) else "?"
	return string.format("Conflito: %s e %s em %s", labelOf(a), labelOf(b), where)
end

local function renderSettings()
	local SUB = SUBS[S.sub]
	if SUB == "Controle" then
		section("Analógicos")
		numberRow("Zona morta interna (mover)", "moveInner", 0.02, "%.2f")
		numberRow("Zona morta externa (mover)", "moveOuter", 0.02, "%.2f")
		numberRow("Zona morta interna (olhar)", "lookInner", 0.02, "%.2f")
		numberRow("Zona morta externa (olhar)", "lookOuter", 0.02, "%.2f")
		numberRow("Limiar do gatilho", "triggerThreshold", 0.05, "%.2f")
		choiceRow(
			"Curva de resposta",
			"curve",
			{ "exponential", "linear", "dynamic" },
			{ "exponencial", "linear", "dinâmica" }
		)
		choiceRow("Inverter Y", "invertY", { false, true }, { "não", "sim" })
		choiceRow("Trocar analógicos (canhoto)", "swapSticks", { false, true }, { "não", "sim" })
		choiceRow("Trocar gatilhos com bumpers", "swapTriggers", { false, true }, { "não", "sim" })
		section("Menus")
		-- D-82: o analógico esquerdo vira um mouse nos menus (velocidade padrão do Roblox; A clica)
		choiceRow("Cursor virtual nos menus", "virtualCursor", { false, true }, { "desligado", "ligado" })
	elseif SUB == "Mouse/teclado" then
		section("Mouse")
		numberRow("Sensibilidade do mouse", "mouseSens", 0.05, "%.2f")
		numberRow("Mouse apontando (fração)", "mouseAds", 0.05, "%.2f")
		numberRow("Mouse na luneta/binóculo (fração)", "mouseScope", 0.05, "%.2f")
		local conflicts = InputMap.keyConflicts(Input.settings)
		if #conflicts > 0 then
			note(conflictText(conflicts[1], true), C.stamp)
		end
		local last = ""
		for _, ctx in CTX_ORDER do
			for _, a in InputMap.ACTIONS do
				local key = InputMap.keyFor(a, Input.settings)
				if a.ctx == ctx and key and ctx ~= "menu" and ctx ~= "wheel" then
					if last ~= ctx then
						last = ctx
						section(string.format("Teclas · %s", CTX_NAMES[ctx] or ctx))
					end
					local id = a.ctx .. "." .. a.id
					local waiting = S.keyListening == id
					local b = rowShell("k:" .. id, a.label)
					valueTag(b, if waiting then "aperte uma tecla…" else UiKit.keyName(key), nil, nil, waiting)
					UiKit.bind(b, function()
						S.keyListening = id
						render()
					end)
				end
			end
		end
		action("k:reset", "Restaurar teclas padrão", function()
			local s = table.clone(Input.settings) :: any
			s.keymap = {}
			Input.setSettings(s)
		end)
	elseif SUB == "Gráficos" then
		section("Imagem")
		choiceRow(
			"Detalhe (arroz, poeira, folhas, fumaça)",
			"gfxDetail",
			{ "high", "medium", "low" },
			{ "alto", "médio", "baixo" }
		)
		choiceRow("Sombras do sol", "gfxShadows", { true, false }, { "ligadas", "desligadas (mais rápido)" })
		choiceRow(
			"Efeitos de tela",
			"gfxPost",
			{ "full", "light", "off" },
			{ "completos", "leves (sem brilho)", "desligados" }
		)
		numberRow("Brilho", "gfxBrightness", 0.02, "%+.2f")
		note("A qualidade geral fica no menu do Roblox (Esc > Configurações).")
		action("g:reset", "Restaurar gráficos padrão", function()
			local s = table.clone(Input.settings) :: any
			for _, k in { "gfxDetail", "gfxShadows", "gfxPost", "gfxBrightness" } do
				s[k] = (InputMap.DEFAULTS :: any)[k]
			end
			Input.setSettings(s)
		end)
	elseif SUB == "Mira" then
		section("Sensibilidade no controle")
		numberRow("Quadril horizontal", "sensHipX", 0.05, "%.2f")
		numberRow("Quadril vertical", "sensHipY", 0.05, "%.2f")
		numberRow("Mira de ferro horizontal", "sensAdsX", 0.05, "%.2f")
		numberRow("Mira de ferro vertical", "sensAdsY", 0.05, "%.2f")
		numberRow("Luneta/binóculo horizontal", "sensScopeX", 0.05, "%.2f")
		numberRow("Luneta/binóculo vertical", "sensScopeY", 0.05, "%.2f")
		choiceRow("Aceleração de giro", "turnAccel", { true, false }, { "ligada", "desligada" })
		choiceRow("Assistência de mira (só controle)", "aimAssist", { "minimal", "off" }, { "mínima", "desligada" })
		section("Câmera")
		-- câmera de ombro (ThirdPerson.client); mirando volta à 1ª pessoa. O modo pode proibir.
		local tpAllowed = workspace:GetAttribute("ThirdPersonAllowed") ~= false
		choiceRow(
			if tpAllowed then "Câmera" else "Câmera (3ª pessoa desligada neste modo)",
			"thirdPerson",
			{ false, true },
			{ "1ª pessoa", "3ª pessoa (ombro)" }
		)
		choiceRow("Ombro da 3ª pessoa", "shoulderLeft", { false, true }, { "direito", "esquerdo" })
	elseif SUB == "Som" then
		-- volume de cada SoundGroup do AudioController (VT65Efeitos, VT65Ambiente, VT65Musica)
		section("Volume")
		numberRow("Efeitos (tiros, passos, motores)", "volEffects", 0.05, "%d%%", 100)
		numberRow("Ambiente (mata, vila, chuva)", "volAmbient", 0.05, "%d%%", 100)
		numberRow("Música (menus)", "volMusic", 0.05, "%d%%", 100)
		action("v:reset", "Restaurar o som padrão", function()
			for _, k in { "volEffects", "volAmbient", "volMusic" } do
				Input.setSetting(k, (InputMap.DEFAULTS :: any)[k])
			end
		end)
	elseif SUB == "Vibração" then
		section("Vibração do controle")
		choiceRow("Disparo", "hapticFire", { "normal", "low", "off" }, { "normal", "baixa", "desligada" })
		choiceRow("Dano e explosões", "hapticDamage", { "normal", "low", "off" }, { "normal", "baixa", "desligada" })
	elseif SUB == "Acessib." then
		section("Idioma / Language")
		-- D-84: idioma da interface (Traducao.client); "automático" = idioma da conta Roblox
		choiceRow(
			"Idioma / Language",
			"lang",
			{ "auto", "pt", "en", "es", "vi" },
			{ "automático", "Português", "English", "Español", "Tiếng Việt" }
		)
		section("Acessibilidade")
		numberRow("Tempo de segurar (s)", "holdTime", 0.05, "%.2f")
		choiceRow("Mirar", "aimToggle", { false, true }, { "segurar", "alternar" })
		choiceRow("Correr", "sprintToggle", { true, false }, { "alternar", "segurar (teclado)" })
		choiceRow("Rodas radiais", "wheelToggle", { false, true }, { "segurar", "alternar" })
		numberRow("Campo de visão (graus)", "fov", 5, "%d")
		choiceRow("Modo daltônico (traçantes)", "colorblind", Accessibility.MODES, {
			Accessibility.MODE_NAMES.off,
			Accessibility.MODE_NAMES.protan,
			Accessibility.MODE_NAMES.deutan,
			Accessibility.MODE_NAMES.tritan,
		})
		choiceRow("Legendas de som", "captions", { false, true }, { "desligadas", "ligadas" })
		action("a:reset", "Restaurar padrões", function()
			Input.setSettings(nil)
		end, true)
	elseif SUB == "Botões" then
		local conflicts = InputMap.conflicts(Input.settings)
		if #conflicts > 0 then
			note(conflictText(conflicts[1], false), C.stamp)
		end
		local last = ""
		for _, ctx in CTX_ORDER do
			for _, a in InputMap.ACTIONS do
				if a.ctx == ctx and a.pad then
					if last ~= ctx then
						last = ctx
						section(string.format("Controle · %s", CTX_NAMES[ctx] or ctx))
					end
					local key = a.ctx .. "." .. a.id
					local pad = InputMap.padFor(a, Input.settings) or "—"
					local waiting = S.listening == key
					local b = rowShell("b:" .. key, a.label)
					local hold = a.padPress == "hold"
					local img = if waiting or hold then nil else UiKit.padImage((Enum.KeyCode :: any)[pad])
					local short = (string.gsub(pad, "Button", ""))
					local text = if waiting
						then "aperte um botão…"
						elseif hold then string.format("%s (segurar)", short)
						else short
					valueTag(b, text, nil, img, waiting)
					UiKit.bind(b, function()
						S.listening = key
						render()
					end)
				end
			end
		end
		action("b:reset", "Restaurar botões padrão", function()
			local s = table.clone(Input.settings) :: any
			s.remap = {}
			Input.setSettings(s)
		end)
	end
end

local function renderSquad()
	section("Papel e squad")
	action("s:role", "Trocar de papel (+15 s no próximo spawn)", function()
		player:SetAttribute("Role", nil)
		Bus.fire("menu_close_request")
	end)
	action("s:leave", "Sair do squad", function()
		Net.event("Squad_Action"):FireServer({ op = "leave" })
		Bus.fire("menu_close_request")
	end)
	-- equipamento por peso: ◄ ► por item, dentro do limite em kg
	local kind = kitKind()
	local k = S.kit or Kit.validate(nil, kind)
	S.kit = k
	section("Equipamento por peso")
	note(string.format("Equipamento: %.1f de %.1f kg (vale no próximo spawn)", Kit.weight(k, kind), Kit.limit(kind)))
	for _, it in Kit.ITEMS do
		local b = rowShell("kit:" .. it.id, it.name)
		local function adjust(d: number)
			local raw = table.clone(k) :: any
			raw[it.id] += d
			if d > 0 and Kit.weight(raw, kind) > Kit.limit(kind) + 1e-9 then
				Bus.fire("toast", "Passa do limite de peso: tire outro item antes")
				return
			end
			local nk = Kit.validate(raw, kind)
			S.kit = nk
			Net.event("Kit_Set"):FireServer(nk)
			render()
		end
		valueTag(b, string.format("%d", (k :: any)[it.id]), adjust)
		UiKit.bind(b, function()
			adjust(1)
		end)
	end
	section("Tutorial")
	action("s:tutorial", "Refazer o tutorial do papel", function()
		Bus.fire("tutorial_restart")
		Bus.fire("menu_close_request")
	end)
	if tutorialActive() then
		note("Pular o tutorial: use a faixa no alto desta folha.")
	end
end

local function renderShop()
	section("Intendência")
	note("Passes visuais, apoio, skins e equipamento de campo.")
	action("l:open", "Abrir a loja", function()
		Bus.fire("shop_open")
	end)
end

local function renderServer()
	section("Servidor privado")
	local b1 = rowShell("p:mode", "Modo")
	valueTag(b1, MODE_NAMES[S.psMode], function(d: number)
		S.psMode = (S.psMode - 1 + d) % #MODES + 1
		render()
	end)
	UiKit.bind(b1, function()
		S.psMode = S.psMode % #MODES + 1
		render()
	end)
	local b2 = rowShell("p:clock", "Horário de início")
	valueTag(b2, CLOCK_NAMES[S.psClock], function(d: number)
		S.psClock = (S.psClock - 1 + d) % #CLOCKS + 1
		render()
	end)
	UiKit.bind(b2, function()
		S.psClock = S.psClock % #CLOCKS + 1
		render()
	end)
	action("p:apply", "Aplicar (vale na próxima partida)", function()
		Net.event("PrivateServer_SetOptions"):FireServer({ mode = MODES[S.psMode], clock = CLOCKS[S.psClock] })
		Bus.fire("toast", string.format("Servidor: %s na próxima partida", MODES[S.psMode]))
	end)
end

-- ===== abas, sub-abas e pé =====
local tabButtons: { TextButton } = {}
local function renderTabs()
	local tabs = TABS()
	for i, name in tabs do
		local b = tabButtons[i]
		if not b then
			local nb = Instance.new("TextButton")
			nb.AutoButtonColor = false
			nb.AutomaticSize = Enum.AutomaticSize.X
			nb.Size = UDim2.fromOffset(0, L.TAB_H)
			nb.BackgroundColor3 = C.tabOff
			nb.BorderSizePixel = 0
			nb.FontFace = UiKit.HEAD_FONT
			nb.TextSize = UiKit.text(17)
			nb.TextColor3 = C.ink
			nb.Selectable = false
			nb.LayoutOrder = i
			nb.Parent = U.tabs
			UiKit.corner(nb, 4)
			UiKit.lit(nb, 0.86)
			local p = Instance.new("UIPadding")
			p.PaddingLeft = UDim.new(0, px(18, 24))
			p.PaddingRight = UDim.new(0, px(18, 24))
			p.PaddingBottom = UDim.new(0, 4)
			p.Parent = nb
			local idx = i
			UiKit.bind(nb, function()
				if S.tab ~= idx and not busy() then
					S.tab = idx
					render()
				end
			end)
			tabButtons[i] = nb
			b = nb
		end
		b.Visible = true
		b.Text = UiKit.upper(name)
		local on = i == S.tab
		TweenService:Create(b, UiKit.QUICK, {
			BackgroundColor3 = if on then C.card else C.tabOff,
			Size = UDim2.fromOffset(0, if on then L.TAB_H + 4 else L.TAB_H - 4),
		}):Play()
		b.TextColor3 = if on then C.stamp else C.ink
	end
	for i = #tabs + 1, #tabButtons do
		tabButtons[i].Visible = false
	end
end

local subButtons: { TextButton } = {}
local function renderSubs()
	if S.tab ~= 1 then
		return
	end
	local il, _ = Input.glyph("ui_sub_prev", "menu")
	local ir, _ = Input.glyph("ui_sub_next", "menu")
	U.lt.Image = if Input.isGamepad() then il or "" else ""
	U.rt.Image = if Input.isGamepad() then ir or "" else ""
	for i, name in SUBS do
		local b = subButtons[i]
		if not b then
			local nb = Instance.new("TextButton")
			nb.AutoButtonColor = false
			nb.AutomaticSize = Enum.AutomaticSize.X
			nb.Size = UDim2.fromOffset(0, L.SUB - 14)
			nb.BorderSizePixel = 0
			nb.FontFace = UiKit.HEAD_FONT
			nb.TextSize = UiKit.text(15)
			nb.Selectable = false
			nb.LayoutOrder = i
			nb.Text = UiKit.upper(name)
			nb.Parent = U.subStrip
			UiKit.corner(nb, 99)
			local p = Instance.new("UIPadding")
			p.PaddingLeft = UDim.new(0, px(12, 16))
			p.PaddingRight = UDim.new(0, px(12, 16))
			p.Parent = nb
			local idx = i
			UiKit.bind(nb, function()
				if S.sub ~= idx and not busy() then
					S.sub = idx
					render()
				end
			end)
			subButtons[i] = nb
			b = nb
		end
		local on = i == S.sub
		TweenService:Create(b, UiKit.QUICK, {
			BackgroundColor3 = if on then C.stamp else C.card,
			BackgroundTransparency = if on then 0 else 1,
			TextColor3 = if on then C.card else C.ink,
		}):Play()
	end
	-- a sub-aba ativa sempre à vista na faixa
	task.defer(function()
		local b = subButtons[S.sub]
		local strip = U.subStrip :: ScrollingFrame
		if b then
			local x = b.AbsolutePosition.X - strip.AbsolutePosition.X + strip.CanvasPosition.X
			local want = math.clamp(
				x - strip.AbsoluteSize.X / 2 + b.AbsoluteSize.X / 2,
				0,
				math.max(strip.AbsoluteCanvasSize.X - strip.AbsoluteSize.X, 0)
			)
			TweenService:Create(strip, UiKit.SOFT, { CanvasPosition = Vector2.new(want, 0) }):Play()
		end
	end)
end

local function renderFoot()
	local f = U.foot
	f.clear()
	local dev = Input.device()
	if dev == "gamepad" then
		f.pair("ui_tab_prev", "ui_tab_next", "menu", "Abas")
		if S.tab == 1 then
			f.pair("ui_sub_prev", "ui_sub_next", "menu", "Seções")
		end
		f.add(UiKit.padImage(Enum.KeyCode.ButtonA), nil, "A", "Mudar")
		f.add(UiKit.padImage(Enum.KeyCode.DPadLeft), UiKit.padImage(Enum.KeyCode.DPadRight), "◄ ►", "Ajustar")
		f.add(UiKit.padImage(Enum.KeyCode.ButtonX), nil, "X", "Idioma")
		f.action("ui_back", "menu", "Voltar")
	elseif dev == "touch" then
		f.add(nil, nil, "Toque", "numa linha para mudar")
	else
		f.pair("ui_tab_prev", "ui_tab_next", "menu", "Abas")
		if S.tab == 1 then
			f.pair("ui_sub_prev", "ui_sub_next", "menu", "Seções")
		end
		f.add(nil, nil, "Clique", "mudar · ◄ ► ajustar")
		f.action("ui_back", "menu", "Voltar")
	end
end

local function renderBanner()
	local n, total = player:GetAttribute("TutorialPasso"), player:GetAttribute("TutorialTotal")
	local papel = player:GetAttribute("TutorialPapel")
	if type(n) ~= "number" or type(total) ~= "number" then
		return
	end
	U.bannerInfo.Text = string.format("%s · passo %d de %d", tostring(papel or ""), n, total)
	U.bannerInfo.Font = if string.find(tostring(papel or ""), "[\196-\225]") then Enum.Font.Arimo else UiKit.BODY_FONT
	local armed = os.clock() < S.armedUntil
	U.skipText.Text = if armed then "CONFIRMAR: DE NOVO" else "PULAR O TUTORIAL"
	local img = if Input.isGamepad() then UiKit.padImage(Enum.KeyCode.ButtonY) else nil
	U.skipKey.Image = img or ""
	U.skipKey.Visible = img ~= nil
end

-- ===== desenhar =====
render = function()
	-- guarda o foco e a rolagem para voltar na mesma linha
	local sel = GuiService.SelectedObject
	local focusName = if sel and sel:IsDescendantOf(U.root) then sel.Name else nil
	local canvas = U.body.CanvasPosition
	local tabChanged = S.lastTab ~= S.tab * 10 + S.sub
	S.lastTab = S.tab * 10 + S.sub
	for _, c in U.body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	table.clear(adjusters)
	table.clear(updaters)
	S.order = 0
	local tabs = TABS()
	S.tab = math.min(S.tab, #tabs)
	local name = tabs[S.tab]
	U.title.Text = UiKit.upper(name)
	U.title.FontFace = UiKit.headFont(name)
	renderTabs()
	layoutSheet()
	renderSubs()
	renderBanner()
	if S.tab == 1 then
		renderSettings()
	elseif S.tab == 2 then
		renderSquad()
	elseif S.tab == 3 then
		renderShop()
	elseif S.tab == 4 and isOwner() then
		renderServer()
	end
	renderFoot()
	if tabChanged then
		-- a folha desliza com o conteúdo novo; o título assenta
		U.body.CanvasPosition = Vector2.zero
		local p = U.body.Position
		U.body.Position = p + UDim2.fromOffset(px(18, 24), 0)
		TweenService:Create(U.body, TweenInfo.new(0.26, Enum.EasingStyle.Quint), { Position = p }):Play()
		U.titleScale.Scale = 1.06
		TweenService:Create(U.titleScale, UiKit.SOFT, { Scale = 1 }):Play()
	else
		U.body.CanvasPosition = canvas
	end
	-- foco: a mesma linha; senão "Pular o tutorial" (se houver) ou a primeira linha
	S.dirty = false
	if gui.Enabled and Input.isGamepad() and not VirtualCursor.isActive() then
		task.defer(function()
			local again = if focusName and not tabChanged then U.root:FindFirstChild(focusName, true) else nil
			if again and again:IsA("GuiObject") and again.Selectable then
				GuiService.SelectedObject = again
			elseif U.banner.Visible then
				GuiService.SelectedObject = U.skip
			else
				UiKit.focus(U.body)
			end
		end)
	end
end

-- ===== pular o tutorial pela faixa =====
local skipHold = UiKit.hold(U.skipFill, 1.0, function()
	Bus.fire("tutorial_skip")
	Bus.fire("menu_close_request")
end)
local function skipPress()
	if os.clock() < S.armedUntil then
		S.armedUntil = 0
		Bus.fire("tutorial_skip")
		Bus.fire("menu_close_request")
		return
	end
	S.armedUntil = os.clock() + 3
	renderBanner()
	U.skip.BackgroundColor3 = Color3.fromRGB(190, 58, 42)
	TweenService:Create(U.skip, TweenInfo.new(0.4), { BackgroundColor3 = C.stamp }):Play()
	task.delay(3.05, function()
		if gui.Enabled then
			renderBanner()
		end
	end)
end
UiKit.bind(U.skip, skipPress)
for _, a in { "TutorialPasso", "TutorialTotal" } do
	player:GetAttributeChangedSignal(a):Connect(function()
		if gui.Enabled then
			render()
		else
			S.dirty = true
		end
	end)
end

-- ===== abrir e fechar =====
-- D-82: com a opção "Cursor virtual", o menu usa o cursor do lobby (VirtualCursor: analógico
-- esquerdo move, A clica, direcional pula entre botões, analógico direito rola). Só desliga o
-- cursor que ele mesmo ligou.
local function syncCursor()
	local want = gui.Enabled and Input.settings.virtualCursor
	if want and not S.menuCursor and not VirtualCursor.isActive() then
		S.menuCursor = true
		VirtualCursor.setActive(true)
	elseif not want and S.menuCursor then
		S.menuCursor = false
		VirtualCursor.setActive(false)
	end
end

local closeToken = 0
local function setOpen(open: boolean)
	if open == gui.Enabled then
		return
	end
	closeToken += 1
	local my = closeToken
	S.listening = nil
	S.keyListening = nil
	skipHold.stop()
	if open then
		gui.Enabled = true
		syncCursor()
		Input.openMenu()
		if S.dirty then
			S.lastTab = -1
			render()
		else
			-- nada mudou desde a última vez: abre a folha que já existe (nada é criado na entrada)
			renderBanner()
			renderFoot()
			if Input.isGamepad() and not VirtualCursor.isActive() then
				task.defer(function()
					if U.banner.Visible then
						GuiService.SelectedObject = U.skip
					else
						UiKit.focus(U.body)
					end
				end)
			end
		end
		-- entra: o véu escurece, o dossiê sobe e assenta
		local k = U.fit.k()
		U.dim.BackgroundTransparency = 1
		TweenService:Create(U.dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.42 }):Play()
		U.root.Position = UDim2.new(0.5, 0, 0.5, 26)
		U.fit.scale.Scale = k * 0.96
		TweenService
			:Create(U.root, TweenInfo.new(0.34, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) })
			:Play()
		TweenService:Create(U.fit.scale, TweenInfo.new(0.34, Enum.EasingStyle.Quint), { Scale = k }):Play()
	else
		Idioma.fechar()
		Input.closeMenu()
		local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(U.dim, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(U.root, info, { Position = UDim2.new(0.5, 0, 0.5, 18) }):Play()
		TweenService:Create(U.fit.scale, info, { Scale = U.fit.k() * 0.97 }):Play()
		task.delay(0.17, function()
			if closeToken == my then
				gui.Enabled = false
				syncCursor()
			end
		end)
	end
end

local function openLanguage()
	if not gui.Enabled or busy() or Idioma.aberto() then
		return
	end
	-- o cartão cuida do direcional e do A: a navegação do Roblox pausa (senão o A também clicaria a
	-- linha do menu por trás) e o foco volta para a mesma linha ao fechar
	local cursor = VirtualCursor.isActive()
	local prev = GuiService.SelectedObject
	local nav = GuiService.GuiNavigationEnabled
	if not cursor then
		GuiService.SelectedObject = nil
		GuiService.GuiNavigationEnabled = false
	end
	Idioma.abrir({
		z = 36,
		bind = UiKit.bind,
		cursor = cursor,
		aoFechar = function()
			if not cursor then
				GuiService.GuiNavigationEnabled = nav
				if gui.Enabled and prev and prev.Parent and Input.isGamepad() then
					GuiService.SelectedObject = prev
				end
			end
		end,
	})
end
do
	local chip = Idioma.chip(U.root, { bind = UiKit.bind, onClick = openLanguage })
	chip.button.AnchorPoint = Vector2.new(1, 0)
	chip.button.Position = UDim2.new(1, -(L.PAD + px(124, 174)), 0, px(17, 23))
	U.langChip = chip
end
UiKit.bind(U.close, function()
	setOpen(false)
end)

Input.on("game_menu", "holdStart", function()
	setOpen(true)
end)
Input.on("game_menu", "press", function() -- P no teclado
	if Idioma.aberto() then
		return
	end
	setOpen(not gui.Enabled)
end)
Input.on("ui_back", "press", function()
	local shop = player:WaitForChild("PlayerGui"):FindFirstChild("VT65Shop") :: ScreenGui?
	if shop and shop.Enabled then
		return -- a loja (por cima) fecha primeiro
	end
	if Idioma.recente() then
		return -- o B fechou o cartão de idiomas
	end
	if os.clock() < S.swallowUntil then
		return -- o B (ou a tecla) acabou de virar o botão de uma ação
	end
	if S.listening or S.keyListening then
		S.listening, S.keyListening = nil, nil
		render()
	else
		setOpen(false)
	end
end)
-- esperando um botão ou uma tecla, Q/E/Z/C e LB/RB/LT/RT trocam o botão da ação, não a aba
Input.on("ui_tab_prev", "press", function()
	if gui.Enabled and not busy() and not Idioma.aberto() then
		S.tab = (S.tab - 2) % #TABS() + 1
		render()
	end
end)
Input.on("ui_tab_next", "press", function()
	if gui.Enabled and not busy() and not Idioma.aberto() then
		S.tab = S.tab % #TABS() + 1
		render()
	end
end)
Input.on("ui_sub_prev", "press", function()
	if gui.Enabled and S.tab == 1 and not busy() and not Idioma.aberto() then
		S.sub = (S.sub - 2) % #SUBS + 1
		render()
	end
end)
Input.on("ui_sub_next", "press", function()
	if gui.Enabled and S.tab == 1 and not busy() and not Idioma.aberto() then
		S.sub = S.sub % #SUBS + 1
		render()
	end
end)
Bus.on("menu_close_request", function()
	setOpen(false)
end)
-- Configuração mudou: nas folhas de valores, só as etiquetas trocam (sem recriar nada, o foco e a
-- rolagem ficam); teclas e botões (a lista e os conflitos mudam) redesenham a folha.
local function bindingSig(): string
	local parts = {}
	for k, v in Input.settings.remap do
		table.insert(parts, k .. "=" .. v)
	end
	for k, v in Input.settings.keymap do
		table.insert(parts, k .. ":" .. v)
	end
	table.sort(parts)
	return table.concat(parts, ",") .. tostring(Input.settings.swapTriggers)
end
local lastSig = bindingSig()
Input.SettingsChanged:Connect(function()
	local sig = bindingSig()
	local bindingsChanged = sig ~= lastSig
	lastSig = sig
	if not gui.Enabled then
		S.dirty = true
		return
	end
	syncCursor()
	local structural = S.tab ~= 1 or bindingsChanged or #updaters == 0
	if structural then
		render()
	else
		for _, fn in updaters do
			fn()
		end
	end
end)
Input.DeviceChanged:Connect(function()
	if gui.Enabled then
		renderFoot()
		renderSubs()
		renderBanner()
	end
end)
UiKit.watch(U.root, function()
	return gui.Enabled
end)

-- direcional ◄ ► (e setas do teclado) ajusta a linha focada; Y segurado pula o tutorial; X abre
-- os idiomas. Nenhum deles tem ação no contexto do menu (InputMap).
UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
	if not gui.Enabled or busy() or Idioma.aberto() then
		return
	end
	local k = io.KeyCode
	if k == Enum.KeyCode.DPadLeft or k == Enum.KeyCode.DPadRight then
		local sel = GuiService.SelectedObject
		local fn = sel and adjusters[sel]
		if fn then
			fn(if k == Enum.KeyCode.DPadLeft then -1 else 1)
		end
	elseif (k == Enum.KeyCode.Left or k == Enum.KeyCode.Right) and not processed then
		local hot = VirtualCursor.hoveredGui() or GuiService.SelectedObject
		local fn = hot and adjusters[hot]
		if fn then
			fn(if k == Enum.KeyCode.Left then -1 else 1)
		end
	elseif k == Enum.KeyCode.ButtonY and U.banner.Visible then
		skipHold.start()
	elseif k == Enum.KeyCode.ButtonX then
		openLanguage()
	end
end)
UserInputService.InputEnded:Connect(function(io: InputObject)
	if io.KeyCode == Enum.KeyCode.ButtonY then
		skipHold.stop()
	end
end)

-- D-82: troca de tecla: a próxima tecla (ou botão do mouse fora dos botões da tela) vira a tecla da
-- ação. Backspace cancela (é o "voltar"); Esc, WASD e outras do Roblox são recusadas.
UserInputService.InputBegan:Connect(function(input, processed)
	if not S.keyListening or not gui.Enabled then
		return
	end
	local code: string? = nil
	if input.UserInputType == Enum.UserInputType.Keyboard then
		code = input.KeyCode.Name
	elseif MOUSE_KEYS[input.UserInputType] and not processed then
		code = MOUSE_KEYS[input.UserInputType]
	end
	if not code or code == "Backspace" then
		return
	end
	if InputMap.KEY_RESERVED[code] then
		Bus.fire("toast", "Tecla reservada pelo Roblox ou pelo movimento: escolha outra")
		return
	end
	local key = S.keyListening :: string
	S.keyListening = nil
	S.swallowUntil = os.clock() + 0.3
	local s = table.clone(Input.settings) :: any
	s.keymap = table.clone(s.keymap)
	s.keymap[key] = code
	local trial = InputMap.validate(s)
	if #InputMap.keyConflicts(trial) > 0 then
		Bus.fire("toast", "Conflito com outra ação: escolha outra tecla")
		render()
		return
	end
	Input.setSettings(trial)
end)

-- remapeamento: o próximo botão do controle vira o novo botão da ação (Start é reservado)
UserInputService.InputBegan:Connect(function(input)
	if not S.listening or string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
		return
	end
	local code = input.KeyCode.Name
	if InputMap.RESERVED[code] or code == "Thumbstick1" or code == "Thumbstick2" or code == "ButtonA" then
		return -- A confirma no menu; não remapeia por aqui
	end
	local key = S.listening :: string
	S.listening = nil
	S.swallowUntil = os.clock() + 0.3
	local s = table.clone(Input.settings) :: any
	s.remap = table.clone(s.remap)
	s.remap[key] = code
	local trial = InputMap.validate(s)
	if #InputMap.conflicts(trial) > 0 then
		Bus.fire("toast", "Conflito com outra ação: escolha outro botão")
		render()
		return
	end
	Input.setSettings(trial)
end)

-- a folha é montada com o jogo parado, em segundo plano: a 1ª abertura já não cria nada
task.delay(4, function()
	if not gui.Enabled and S.dirty then
		render()
	end
end)

-- ===== gancho de teste (só no Studio): foto do menu =====
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if v == "menu" or v == "menu_som" then
			if v == "menu_som" then
				S.tab = 1
				S.sub = table.find(SUBS, "Som") or 1
				S.dirty = true
			end
			setOpen(true)
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
