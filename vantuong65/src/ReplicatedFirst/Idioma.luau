--!strict
-- Escolha do idioma (pedido do dono, 2026-11-11: "faça o jogo completamente na língua que foi
-- selecionada"). Cartão de época com as 5 opções (automático, português, English, Español, Tiếng
-- Việt) e um chip "IDIOMA · LANGUAGE" que o abre. Fica no ReplicatedFirst porque a tela de entrada
-- (LoadingScreen) usa antes de tudo; o lobby (IdiomaLobby.client) e o menu do jogo (GameMenu) também.
-- Gravar: Input.setSetting("lang", código), e o Traducao.client retraduz o que está aberto. Na tela
-- de entrada o módulo Input ainda pode não existir (os Controllers chegam depois): a escolha espera
-- por ele, e o Input a mantém por cima da configuração salva que chega do servidor (Input.pendingLang).
-- Os nomes dos idiomas ficam no próprio idioma (endônimo) e não passam pela tradução: vão em TextBox
-- só de leitura, que o Traducao.client nunca traduz. O resto do cartão é traduzido normalmente.
-- Navegação: clique e toque; teclado (setas, Enter, Esc/Backspace); controle (direcional ou
-- analógico, A, B). Com o cursor virtual do lobby (opcoes.cursor = true), o A e o direcional são do
-- cursor (os botões chegam registrados por opcoes.bind).
local GuiService = game:GetService("GuiService")
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Idioma = {}

export type Opcao = { code: string, nome: string, tag: string }
Idioma.OPCOES = {
	{ code = "auto", nome = "", tag = "AUTO" }, -- o nome sai do idioma da conta
	{ code = "pt", nome = "Português", tag = "PT" },
	{ code = "en", nome = "English", tag = "EN" },
	{ code = "es", nome = "Español", tag = "ES" },
	{ code = "vi", nome = "Tiếng Việt", tag = "VI" },
} :: { Opcao }
local NOME: { [string]: string } = { pt = "Português", en = "English", es = "Español", vi = "Tiếng Việt" }

local CARD = Color3.fromRGB(234, 226, 200)
local CARD_HOT = Color3.fromRGB(250, 244, 226)
local INK = Color3.fromRGB(40, 36, 28)
local DRAB = Color3.fromRGB(46, 50, 36)
local KHAKI = Color3.fromRGB(201, 186, 140)
local BRASS = Color3.fromRGB(214, 172, 72)
local STAMP = Color3.fromRGB(150, 40, 30)
local RULE_RED = Color3.fromRGB(176, 62, 48)
local HEAD = Font.fromName("Oswald", Enum.FontWeight.Bold)
local BODY = Font.fromEnum(Enum.Font.Arimo)
local BODY_B = Font.fromEnum(Enum.Font.ArimoBold)
local TYPE = Font.fromEnum(Enum.Font.SpecialElite)

local function isTv(): boolean
	local ok, v = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and v == true
end
local TV = isTv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

-- ===== idioma atual e gravação =====
local function inputModule(wait: boolean): any
	local player = Players.LocalPlayer
	local ps = if wait then player:WaitForChild("PlayerScripts", 60) else player:FindFirstChild("PlayerScripts")
	local ctl = ps and (if wait then ps:WaitForChild("Controllers", 60) else ps:FindFirstChild("Controllers"))
	local m = ctl and (if wait then ctl:WaitForChild("Input", 60) else ctl:FindFirstChild("Input"))
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok then
			return mod
		end
	end
	return nil
end

local pendente: string? = nil
local mudou = Instance.new("BindableEvent")
Idioma.Mudou = mudou.Event -- (código)

-- idioma da conta Roblox (o que o "automático" usa); sem dicionário cai no inglês (Shared/Lang)
function Idioma.daConta(): string
	local ok, id = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	local code = string.lower(string.sub(if ok and type(id) == "string" then id else "", 1, 2))
	return if NOME[code] then code else "en"
end

-- a escolha gravada ("auto", "pt", "en", "es" ou "vi")
function Idioma.atual(): string
	if pendente then
		return pendente
	end
	local I = inputModule(false)
	if I and I.settings and type(I.settings.lang) == "string" then
		return I.settings.lang
	end
	return "auto"
end

function Idioma.nome(code: string): string
	return NOME[if code == "auto" then Idioma.daConta() else code] or code
end

function Idioma.aplicar(code: string)
	pendente = code
	mudou:Fire(code)
	task.spawn(function()
		local I = inputModule(true)
		if not I then
			return
		end
		if not I.loaded then
			I.pendingLang = code -- a configuração salva que chegar não apaga a escolha
		end
		I.setSetting("lang", code)
		if pendente == code then
			pendente = nil
		end
	end)
end

-- ===== peças =====
local function corner(o: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end
local function edge(o: Instance, color: Color3, t: number, tr: number): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = t
	s.Transparency = tr
	s.Parent = o
	return s
end
local function lit(o: Instance, low: number)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(low, low * 0.98, low * 0.94))
	g.Parent = o
end
local function label(parent: Instance, font: Font, size: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end
-- texto que a tradução não toca (endônimos e o título em várias línguas): TextBox só de leitura
local function fixed(parent: Instance, font: Font, size: number, color: Color3, text: string): TextBox
	local t = Instance.new("TextBox")
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextEditable = false
	t.ClearTextOnFocus = false
	t.Selectable = false
	t.Active = false
	t.Text = text
	pcall(function()
		t.Interactable = false -- o clique passa para o botão de baixo
	end)
	t.Parent = parent
	return t
end

local function padImage(code: Enum.KeyCode): string?
	local img: string? = nil
	pcall(function()
		local v = UserInputService:GetImageForKeyCode(code) :: any
		if type(v) == "string" and v ~= "" then
			img = v
		end
	end)
	return img
end
local function usingPad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

-- ===== chip "IDIOMA · LANGUAGE" =====
export type Chip = { button: TextButton, atualizar: () -> () }
-- padKey: botão do controle que também abre (a imagem dele aparece no chip quando se joga no controle)
export type ChipOpcoes = {
	bind: ((b: GuiButton, fn: () -> ()) -> ())?,
	onClick: () -> (),
	padKey: Enum.KeyCode?,
}
function Idioma.chip(parent: Instance, o: ChipOpcoes): Chip
	local b = Instance.new("TextButton")
	b.Name = "Idioma"
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = DRAB
	b.BackgroundTransparency = 0.08
	b.Size = UDim2.fromOffset(px(236, 330), px(34, 48))
	b.Selectable = false
	b.Parent = parent
	corner(b, 3)
	lit(b, 0.72)
	local e = edge(b, KHAKI, 1, 0.55)
	local sc = Instance.new("UIScale")
	sc.Parent = b
	local key = Instance.new("ImageLabel")
	key.BackgroundTransparency = 1
	key.AnchorPoint = Vector2.new(1, 0.5)
	key.Position = UDim2.new(0, -6, 0.5, 0)
	key.Size = UDim2.fromOffset(px(26, 38), px(26, 38))
	key.Visible = false
	key.Parent = b
	local head = fixed(b, HEAD, px(13, 22), KHAKI, "IDIOMA · LANGUAGE")
	head.Position = UDim2.fromOffset(px(10, 14), 0)
	head.Size = UDim2.new(0, px(120, 170), 1, 0)
	local cur = fixed(b, HEAD, px(16, 26), CARD, "")
	cur.Position = UDim2.new(0, px(128, 186), 0, 0)
	cur.Size = UDim2.new(1, -px(138, 196), 1, 0)
	cur.TextXAlignment = Enum.TextXAlignment.Right
	cur.TextTruncate = Enum.TextTruncate.AtEnd
	local function atualizar()
		local c = Idioma.atual()
		local n = Idioma.nome(c)
		cur.Text = if c == "auto" then string.format("AUTO · %s ▾", n) else string.format("%s ▾", n)
		cur.FontFace = if string.find(n, "[\196-\225]") then BODY_B else HEAD
		local img = if o.padKey and usingPad() then padImage(o.padKey) else nil
		key.Image = img or ""
		key.Visible = img ~= nil
	end
	UserInputService.LastInputTypeChanged:Connect(function()
		atualizar()
	end)
	atualizar()
	mudou.Event:Connect(function()
		atualizar()
	end)
	local function hover(on: boolean)
		TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Scale = if on then 1.04 else 1 }):Play()
		TweenService
			:Create(
				e,
				TweenInfo.new(0.14),
				{ Color = if on then BRASS else KHAKI, Transparency = if on then 0 else 0.55 }
			)
			:Play()
	end
	b.MouseEnter:Connect(function()
		hover(true)
	end)
	b.MouseLeave:Connect(function()
		hover(false)
	end)
	if o.bind then
		o.bind(b, o.onClick)
	else
		b.Activated:Connect(o.onClick)
	end
	return { button = b, atualizar = atualizar }
end

-- ===== cartão de escolha =====
export type AbrirOpcoes = {
	z: number?, -- DisplayOrder da tela própria (sem parent)
	parent: Instance?, -- dentro de uma tela que já existe (senão cria a sua)
	cursor: boolean?, -- o cursor virtual do lobby cuida do A e do direcional
	bind: ((b: GuiButton, fn: () -> (), hover: ((boolean) -> ())?) -> ())?,
	primeiraVez: boolean?, -- texto de boas-vindas no alto
	aoFechar: (() -> ())?,
}

local aberto: (() -> ())? = nil
local fechadoEm = 0
function Idioma.aberto(): boolean
	return aberto ~= nil
end
-- aberto agora ou fechado há um instante: o B que fechou o cartão não fecha também a tela de baixo
function Idioma.recente(): boolean
	return aberto ~= nil or os.clock() - fechadoEm < 0.35
end
function Idioma.fechar()
	local f = aberto
	if f then
		f()
	end
end

function Idioma.abrir(o: AbrirOpcoes?)
	if aberto then
		return
	end
	local op: AbrirOpcoes = o or {}
	local own: ScreenGui? = nil
	local host: Instance
	if op.parent then
		host = op.parent
	else
		local g = Instance.new("ScreenGui")
		g.Name = "VT65Idioma"
		g.ResetOnSpawn = false
		g.DisplayOrder = op.z or 110
		g.IgnoreGuiInset = true
		g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		own = g
		host = g
	end
	local layer = Instance.new("Frame")
	layer.Name = "EscolhaDeIdioma"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundColor3 = Color3.new(0, 0, 0)
	layer.BackgroundTransparency = 1
	layer.Active = true -- nada atrás recebe o clique
	layer.ZIndex = 50
	layer.Parent = host

	local W, ROW = px(520, 760), px(58, 84)
	local H = px(118, 170) + #Idioma.OPCOES * (ROW + 8) + px(46, 66)
	local card = Instance.new("Frame")
	card.Name = "Cartao"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(W, H)
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	card.ZIndex = 51
	card.Rotation = -0.6
	card.Parent = layer
	lit(card, 0.86)
	edge(card, INK, 1, 0.5)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	-- cabe na tela (janela estreita)
	local function fitK(): number
		local a = layer.AbsoluteSize
		if a.X < 10 then
			return 1
		end
		return math.clamp(math.min((a.X - 32) / W, (a.Y - 32) / H), 0.45, 1)
	end
	local fitConn = layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		scale.Scale = fitK()
	end)

	local head = Instance.new("Frame")
	head.BackgroundColor3 = DRAB
	head.BorderSizePixel = 0
	head.Size = UDim2.new(1, 0, 0, px(46, 66))
	head.ZIndex = 52
	head.Parent = card
	lit(head, 0.7)
	local title = fixed(head, BODY_B, px(18, 28), KHAKI, "IDIOMA · LANGUAGE · IDIOMA · NGÔN NGỮ")
	title.Position = UDim2.fromOffset(px(18, 26), 0)
	title.Size = UDim2.new(1, -px(36, 52), 1, 0)
	title.ZIndex = 53
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = RULE_RED
	rule.BorderSizePixel = 0
	rule.Position = UDim2.fromOffset(px(18, 26), px(50, 72))
	rule.Size = UDim2.new(1, -px(36, 52), 0, 2)
	rule.ZIndex = 52
	rule.Parent = card
	local intro = label(card, TYPE, px(15, 24), INK)
	intro.Position = UDim2.fromOffset(px(18, 26), px(58, 82))
	intro.Size = UDim2.new(1, -px(36, 52), 0, px(52, 80))
	intro.TextWrapped = true
	intro.TextYAlignment = Enum.TextYAlignment.Top
	intro.ZIndex = 52
	intro.Text = if op.primeiraVez
		then "Escolha o idioma do jogo. Dá para trocar depois no lobby ou no menu do jogo."
		else "O jogo inteiro muda na hora. Automático segue o idioma da sua conta Roblox."

	type Row = { b: TextButton, code: string, mark: TextLabel, sc: UIScale, e: UIStroke }
	local rows: { Row } = {}
	local sel = 1
	local atual = Idioma.atual()
	for i, opc in Idioma.OPCOES do
		if opc.code == atual then
			sel = i
		end
	end
	local closing = false
	local conns: { RBXScriptConnection } = { fitConn }

	local function paint()
		for i, r in rows do
			local hot = i == sel
			TweenService:Create(r.b, TweenInfo.new(0.14), { BackgroundColor3 = if hot then CARD_HOT else CARD }):Play()
			TweenService:Create(r.sc, TweenInfo.new(0.22, Enum.EasingStyle.Quint), { Scale = if hot then 1.02 else 1 })
				:Play()
			TweenService:Create(r.e, TweenInfo.new(0.14), {
				Color = if hot then BRASS else INK,
				Thickness = if hot then 2 else 1,
				Transparency = if hot then 0 else 0.7,
			}):Play()
		end
	end

	local function close()
		if closing then
			return
		end
		closing = true
		aberto = nil
		fechadoEm = os.clock()
		for _, c in conns do
			c:Disconnect()
		end
		TweenService:Create(layer, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0.5, 24),
		}):Play()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = fitK() * 0.94,
		}):Play()
		task.delay(0.21, function()
			layer:Destroy()
			if own then
				own:Destroy()
			end
			local f = op.aoFechar
			if f then
				f()
			end
		end)
	end

	local function choose(i: number)
		if closing then
			return
		end
		sel = i
		paint()
		local code = Idioma.OPCOES[i].code
		for _, r in rows do
			r.mark.Text = if r.code == code then "■" else ""
		end
		Idioma.aplicar(code)
		-- o carimbo cai na linha escolhida e o cartão fecha
		local m = rows[i].mark
		local ms = m:FindFirstChildOfClass("UIScale") :: UIScale
		ms.Scale = 1.8
		TweenService:Create(ms, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Scale = 1 }):Play()
		task.delay(0.45, close)
	end

	for i, opc in Idioma.OPCOES do
		local b = Instance.new("TextButton")
		b.Name = opc.code
		b.AutoButtonColor = false
		b.Text = ""
		b.BackgroundColor3 = CARD
		b.BorderSizePixel = 0
		b.Position = UDim2.fromOffset(px(18, 26), px(112, 164) + (i - 1) * (ROW + 8))
		b.Size = UDim2.new(1, -px(36, 52), 0, ROW)
		b.Selectable = false
		b.ZIndex = 52
		b.Parent = card
		corner(b, 3)
		local e = edge(b, INK, 1, 0.7)
		local sc = Instance.new("UIScale")
		sc.Parent = b
		local tag = Instance.new("TextLabel")
		tag.BackgroundColor3 = DRAB
		tag.BorderSizePixel = 0
		tag.Position = UDim2.fromOffset(px(10, 14), px(10, 14))
		tag.Size = UDim2.fromOffset(px(58, 84), ROW - px(20, 28))
		tag.FontFace = HEAD
		tag.TextSize = px(16, 24)
		tag.TextColor3 = KHAKI
		tag.Text = opc.tag
		tag.ZIndex = 53
		tag.Parent = b
		corner(tag, 2)
		local x = px(82, 116)
		if opc.code == "auto" then
			local n = label(b, HEAD, px(20, 30), INK)
			n.Position = UDim2.fromOffset(x, px(4, 6))
			n.Size = UDim2.new(1, -x - px(48, 70), 0, px(28, 40))
			n.Text = "AUTOMÁTICO"
			n.ZIndex = 53
			local s = label(b, BODY, px(13, 22), INK)
			s.Position = UDim2.fromOffset(x, px(30, 44))
			s.Size = UDim2.new(1, -x - px(48, 70), 0, px(20, 30))
			s.TextTransparency = 0.25
			s.Text = string.format("Idioma da conta Roblox: %s", Idioma.nome("auto"))
			s.ZIndex = 53
		else
			local n = fixed(b, if string.find(opc.nome, "[\196-\225]") then BODY_B else HEAD, px(22, 32), INK, opc.nome)
			n.Position = UDim2.fromOffset(x, 0)
			n.Size = UDim2.new(1, -x - px(48, 70), 1, 0)
			n.ZIndex = 53
		end
		local mark = label(b, BODY_B, px(22, 32), STAMP)
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, -px(14, 20), 0, 0)
		mark.Size = UDim2.new(0, px(30, 44), 1, 0)
		mark.TextXAlignment = Enum.TextXAlignment.Center
		mark.Text = if opc.code == atual then "■" else ""
		mark.ZIndex = 53
		local msc = Instance.new("UIScale")
		msc.Parent = mark
		local row: Row = { b = b, code = opc.code, mark = mark, sc = sc, e = e }
		table.insert(rows, row)
		local function hover(on: boolean)
			if on and not closing then
				sel = i
				paint()
			end
		end
		b.MouseEnter:Connect(function()
			hover(true)
		end)
		if op.bind then
			op.bind(b, function()
				choose(i)
			end, hover)
		else
			b.Activated:Connect(function()
				choose(i)
			end)
		end
	end

	-- pé: como escolher (imagem do botão do controle ou o texto do teclado e do toque)
	local foot = Instance.new("Frame")
	foot.BackgroundTransparency = 1
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.new(0, px(18, 26), 1, -px(10, 14))
	foot.Size = UDim2.new(1, -px(36, 52), 0, px(28, 40))
	foot.ZIndex = 52
	foot.Parent = card
	local fl = Instance.new("UIListLayout")
	fl.FillDirection = Enum.FillDirection.Horizontal
	fl.VerticalAlignment = Enum.VerticalAlignment.Center
	fl.SortOrder = Enum.SortOrder.LayoutOrder
	fl.Padding = UDim.new(0, 6)
	fl.Parent = foot
	local aImg = padImage(Enum.KeyCode.ButtonA)
	local bImg = padImage(Enum.KeyCode.ButtonB)
	local function refreshFoot()
		for _, c in foot:GetChildren() do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		local function txt(s: string, n: number)
			local t = label(foot, TYPE, px(14, 22), INK)
			t.AutomaticSize = Enum.AutomaticSize.X
			t.Size = UDim2.fromOffset(0, px(28, 40))
			t.TextTransparency = 0.2
			t.Text = s
			t.LayoutOrder = n
			t.ZIndex = 53
		end
		local function img(im: string, n: number)
			local il = Instance.new("ImageLabel")
			il.BackgroundTransparency = 1
			il.Image = im
			il.Size = UDim2.fromOffset(px(24, 36), px(24, 36))
			il.LayoutOrder = n
			il.ZIndex = 53
			il.Parent = foot
		end
		if usingPad() and aImg and bImg then
			img(aImg, 1)
			txt("escolher", 2)
			txt("   ", 3)
			img(bImg, 4)
			txt("fechar", 5)
		elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			txt("Toque num idioma · toque fora para fechar", 1)
		else
			txt("Clique ou ↑ ↓ e Enter · Esc fecha", 1)
		end
	end
	refreshFoot()

	-- teclado e controle (sem o cursor virtual): ↑ ↓, Enter/A, Esc/B
	local STEP: { [Enum.KeyCode]: number } = {
		[Enum.KeyCode.Up] = -1,
		[Enum.KeyCode.Down] = 1,
		[Enum.KeyCode.DPadUp] = -1,
		[Enum.KeyCode.DPadDown] = 1,
	}
	table.insert(
		conns,
		UserInputService.InputBegan:Connect(function(io: InputObject)
			local k = io.KeyCode
			if k == Enum.KeyCode.ButtonB or k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace then
				close()
				return
			end
			if op.cursor then
				return
			end
			local d = STEP[k]
			if d then
				sel = (sel - 1 + d) % #rows + 1
				paint()
			elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA then
				choose(sel)
			end
		end)
	)
	local stickReady = true
	table.insert(
		conns,
		UserInputService.InputChanged:Connect(function(io: InputObject)
			if op.cursor or io.KeyCode ~= Enum.KeyCode.Thumbstick1 then
				return
			end
			local y = io.Position.Y
			if math.abs(y) < 0.35 then
				stickReady = true
			elseif stickReady and math.abs(y) > 0.6 then
				stickReady = false
				sel = (sel - 1 + (if y > 0 then -1 else 1)) % #rows + 1
				paint()
			end
		end)
	)
	table.insert(conns, UserInputService.LastInputTypeChanged:Connect(refreshFoot))
	-- tocar fora do cartão fecha
	layer.InputBegan:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			local p = io.Position
			local a, s = card.AbsolutePosition, card.AbsoluteSize
			if p.X < a.X or p.Y < a.Y or p.X > a.X + s.X or p.Y > a.Y + s.Y then
				close()
			end
		end
	end)

	-- entra: o véu escurece e o cartão sobe e assenta
	local k = fitK()
	scale.Scale = k * 0.95
	card.Position = UDim2.new(0.5, 0, 0.5, 28)
	TweenService:Create(layer, TweenInfo.new(0.25), { BackgroundTransparency = 0.42 }):Play()
	TweenService:Create(card, TweenInfo.new(0.34, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) })
		:Play()
	TweenService:Create(scale, TweenInfo.new(0.34, Enum.EasingStyle.Quint), { Scale = k }):Play()
	paint()
	aberto = close
end

return Idioma
