--!strict
-- Escolha do idioma (pedido do dono, 2026-11-11: "faça o jogo completamente na língua que foi
-- selecionada"; depois: "coloque as bandeiras dos países na hora de escolher o idioma"). Cartão com
-- as 5 opções em cartões grandes com a bandeira (ReplicatedFirst/Bandeiras: Brasil, EUA, Espanha,
-- Vietnã e um globo para o automático), o nome no próprio idioma e o código; e um chip "IDIOMA ·
-- LANGUAGE" com a bandeira atual que o abre. Estilo novo (ReplicatedFirst/Estilo): painel escuro,
-- títulos em Oswald, nada de papel.
-- Fica no ReplicatedFirst porque a tela de entrada (LoadingScreen) usa antes de tudo; o lobby
-- (IdiomaLobby.client) e o menu do jogo (GameMenu) também.
-- Gravar: Input.setSetting("lang", código), e o Traducao.client retraduz o que está aberto. Na tela
-- de entrada o módulo Input ainda pode não existir (os Controllers chegam depois): a escolha espera
-- por ele, e o Input a mantém por cima da configuração salva que chega do servidor (Input.pendingLang).
-- Os nomes dos idiomas ficam no próprio idioma (endônimo) e não passam pela tradução: vão em TextBox
-- só de leitura, que o Traducao.client nunca traduz. O resto do cartão é traduzido normalmente.
-- Navegação: clique e toque; teclado (← → ou ↑ ↓, Enter, Esc/Backspace); controle (direcional ou
-- analógico, A, B). Com o cursor virtual do lobby (opcoes.cursor = true), o A e o direcional são do
-- cursor (os botões chegam registrados por opcoes.bind).
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Bandeiras = require(script.Parent:WaitForChild("Bandeiras"))
local Estilo = require(script.Parent:WaitForChild("Estilo"))

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

local V, F = Estilo.V, Estilo.F
local px = Estilo.px

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

-- v43 (pedido do dono: "quando você já escolheu a língua do jogo no início não precisa mais ficar
-- aparecendo a opção para alterá-la; apenas nas configurações"): o chip da tela de entrada e da mesa
-- só aparece enquanto o idioma está no automático (nunca escolhido) e some na hora da escolha. Começa
-- escondido e espera a configuração salva da conta chegar (Input.loaded, até 20 s). O menu do jogo
-- (Configurações) mantém o seu chip sempre.
function Idioma.soAteEscolher(button: GuiObject)
	button.Visible = false
	Idioma.Mudou:Connect(function(code: string)
		if code ~= "auto" then
			button.Visible = false
		end
	end)
	task.spawn(function()
		local I = inputModule(true)
		local t0 = os.clock()
		while I and not I.loaded and os.clock() - t0 < 20 do
			task.wait(0.25)
		end
		button.Visible = Idioma.atual() == "auto"
	end)
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
-- texto que a tradução não toca (endônimos, códigos e o título em várias línguas): TextBox só de
-- leitura. Com letra do vietnamita vai no Arimo Bold (o Oswald não tem).
local function fixed(parent: Instance, font: Font, size: number, color: Color3, text: string): TextBox
	local t = Instance.new("TextBox")
	t.BackgroundTransparency = 1
	t.FontFace = Estilo.headFont(text, font)
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

local function tween(
	o: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
		:Play()
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
	local H = px(34, 48)
	local b = Instance.new("TextButton")
	b.Name = "Idioma"
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = V.PANEL
	b.BackgroundTransparency = 0.08
	b.Size = UDim2.fromOffset(px(236, 330), H)
	b.Selectable = false
	b.Parent = parent
	Estilo.corner(b, 4)
	local e = Estilo.stroke(b, V.LINE, 1, 0.3)
	local sc = Instance.new("UIScale")
	sc.Parent = b
	local key = Instance.new("ImageLabel")
	key.BackgroundTransparency = 1
	key.AnchorPoint = Vector2.new(1, 0.5)
	key.Position = UDim2.new(0, -6, 0.5, 0)
	key.Size = UDim2.fromOffset(px(26, 38), px(26, 38))
	key.Visible = false
	key.Parent = b
	-- a bandeira do idioma de agora, à esquerda
	local FH = H - px(14, 20)
	local flagSlot = Instance.new("Frame")
	flagSlot.Name = "Bandeira"
	flagSlot.BackgroundTransparency = 1
	flagSlot.AnchorPoint = Vector2.new(0, 0.5)
	flagSlot.Position = UDim2.new(0, px(8, 12), 0.5, 0)
	flagSlot.Size = UDim2.fromOffset(math.floor(FH * 1.5), FH)
	flagSlot.Parent = b
	local x = px(8, 12) + math.floor(FH * 1.5) + px(8, 10)
	local head = fixed(b, F.TITLE_REG, px(13, 20), V.DIM, "IDIOMA · LANGUAGE")
	head.Position = UDim2.fromOffset(x, 0)
	head.Size = UDim2.new(0, px(104, 150), 1, 0)
	local cur = fixed(b, F.TITLE, px(15, 24), V.TEXT, "")
	cur.AnchorPoint = Vector2.new(1, 0)
	cur.Position = UDim2.new(1, -px(10, 14), 0, 0)
	cur.Size = UDim2.new(1, -(x + px(104, 150) + px(14, 20)), 1, 0)
	cur.TextXAlignment = Enum.TextXAlignment.Right
	cur.TextTruncate = Enum.TextTruncate.AtEnd
	local shownFlag = ""
	local function atualizar()
		local c = Idioma.atual()
		local n = Idioma.nome(c)
		cur.Text = string.format("%s ▼", n)
		cur.FontFace = Estilo.headFont(n)
		if shownFlag ~= c then
			shownFlag = c
			for _, ch in flagSlot:GetChildren() do
				ch:Destroy()
			end
			local fl = Bandeiras.criar(c, flagSlot.Size.X.Offset, FH)
			fl.Parent = flagSlot
		end
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
		tween(sc, 0.2, { Scale = if on then 1.04 else 1 })
		tween(e, 0.14, { Color = if on then V.BRASS else V.LINE, Transparency = if on then 0 else 0.3 })
		tween(b, 0.14, { BackgroundColor3 = if on then V.PANEL_3 else V.PANEL })
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
	primeiraVez: boolean?, -- uma linha de boas-vindas no alto
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

	-- medidas: cinco cartões lado a lado
	local PAD, GAP = px(24, 34), px(12, 16)
	local CW, CH = px(132, 190), px(176, 248)
	local HEAD_H = px(58, 82)
	local INTRO_H = if op.primeiraVez then px(30, 42) else 0
	local FOOT_H = px(46, 64)
	local n = #Idioma.OPCOES
	local W = 2 * PAD + n * CW + (n - 1) * GAP
	local H = HEAD_H + INTRO_H + CH + FOOT_H + px(18, 24)
	local card = Estilo.panel(layer, V.PANEL, 0, true)
	card.Name = "Cartao"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(W, H)
	card.ZIndex = 51
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

	-- cabeçalho: o título nas quatro línguas e um filete oliva
	local title = fixed(card, F.BODY_B, px(20, 30), V.TEXT, "IDIOMA · LANGUAGE · IDIOMA · NGÔN NGỮ")
	title.Position = UDim2.fromOffset(PAD, 0)
	title.Size = UDim2.new(1, -2 * PAD, 0, HEAD_H - px(6, 8))
	title.ZIndex = 52
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = V.OLIVE
	rule.BorderSizePixel = 0
	rule.Position = UDim2.fromOffset(PAD, HEAD_H - px(6, 8))
	rule.Size = UDim2.fromOffset(px(64, 90), px(3, 4))
	rule.ZIndex = 52
	rule.Parent = card
	if op.primeiraVez then
		local intro = Estilo.text(card, "Escolha o idioma. Dá para trocar depois.", px(16, 24), V.DIM, F.BODY)
		intro.Position = UDim2.fromOffset(PAD, HEAD_H + px(4, 6))
		intro.Size = UDim2.new(1, -2 * PAD, 0, INTRO_H - px(4, 6))
		intro.TextTruncate = Enum.TextTruncate.AtEnd
		intro.ZIndex = 52
	end

	type Row = { b: TextButton, code: string, cur: Frame, sc: UIScale, e: UIStroke }
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
			tween(r.b, 0.14, { BackgroundColor3 = if hot then V.PANEL_3 else V.PANEL_2 })
			tween(r.sc, 0.22, { Scale = if hot then 1.04 else 1 })
			tween(r.e, 0.14, {
				Color = if hot then V.BRASS else V.LINE,
				Thickness = if hot then 2 else 1,
				Transparency = if hot then 0 else 0.45,
			})
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
		tween(layer, 0.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(card, 0.2, { Position = UDim2.new(0.5, 0, 0.5, 24) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(scale, 0.2, { Scale = fitK() * 0.94 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
			r.cur.Visible = r.code == code
		end
		Idioma.aplicar(code)
		-- o cartão escolhido pulsa e o cartão fecha
		local sc = rows[i].sc
		sc.Scale = 1.1
		tween(sc, 0.25, { Scale = 1.04 })
		task.delay(0.35, close)
	end

	local y0 = HEAD_H + INTRO_H + px(6, 8)
	local FLAG_W = CW - 2 * px(14, 20)
	local FLAG_H = math.floor(FLAG_W * 2 / 3 + 0.5)
	for i, opc in Idioma.OPCOES do
		local b = Instance.new("TextButton")
		b.Name = opc.code
		b.AutoButtonColor = false
		b.Text = ""
		b.BackgroundColor3 = V.PANEL_2
		b.BorderSizePixel = 0
		b.Position = UDim2.fromOffset(PAD + (i - 1) * (CW + GAP), y0)
		b.Size = UDim2.fromOffset(CW, CH)
		b.Selectable = false
		b.ZIndex = 52
		b.Parent = card
		Estilo.corner(b, 4)
		local e = Estilo.stroke(b, V.LINE, 1, 0.45)
		local sc = Instance.new("UIScale")
		sc.Parent = b
		local flag = Bandeiras.criar(opc.code, FLAG_W, FLAG_H)
		flag.AnchorPoint = Vector2.new(0.5, 0)
		flag.Position = UDim2.new(0.5, 0, 0, px(14, 20))
		flag.ZIndex = 53
		flag.Parent = b
		local ny = px(14, 20) + FLAG_H + px(10, 14)
		if opc.code == "auto" then
			local nm = Estilo.text(b, "AUTOMÁTICO", px(18, 26), V.TEXT, F.TITLE)
			nm.Position = UDim2.fromOffset(px(6, 8), ny)
			nm.Size = UDim2.new(1, -2 * px(6, 8), 0, px(26, 36))
			nm.TextXAlignment = Enum.TextXAlignment.Center
			nm.TextScaled = true
			nm.ZIndex = 53
			local lim = Instance.new("UITextSizeConstraint")
			lim.MaxTextSize = px(18, 26)
			lim.Parent = nm
			local acc = fixed(b, F.BODY, px(13, 20), V.DIM, Idioma.nome("auto"))
			acc.Position = UDim2.fromOffset(px(6, 8), ny + px(26, 36))
			acc.Size = UDim2.new(1, -2 * px(6, 8), 0, px(20, 28))
			acc.TextXAlignment = Enum.TextXAlignment.Center
			acc.ZIndex = 53
		else
			local nm = fixed(b, F.TITLE, px(20, 28), V.TEXT, opc.nome)
			nm.Position = UDim2.fromOffset(px(6, 8), ny)
			nm.Size = UDim2.new(1, -2 * px(6, 8), 0, px(26, 36))
			nm.TextXAlignment = Enum.TextXAlignment.Center
			nm.TextScaled = true
			nm.ZIndex = 53
			local lim = Instance.new("UITextSizeConstraint")
			lim.MaxTextSize = px(20, 28)
			lim.Parent = nm
			local codeText = fixed(b, F.TITLE_REG, px(13, 20), V.DIM, opc.tag)
			codeText.Position = UDim2.fromOffset(px(6, 8), ny + px(26, 36))
			codeText.Size = UDim2.new(1, -2 * px(6, 8), 0, px(20, 28))
			codeText.TextXAlignment = Enum.TextXAlignment.Center
			codeText.ZIndex = 53
		end
		-- o idioma de agora: faixa oliva embaixo do cartão
		local cur = Instance.new("Frame")
		cur.Name = "Atual"
		cur.AnchorPoint = Vector2.new(0, 1)
		cur.Position = UDim2.fromScale(0, 1)
		cur.Size = UDim2.new(1, 0, 0, px(5, 7))
		cur.BackgroundColor3 = V.OLIVE_HI
		cur.BorderSizePixel = 0
		cur.Visible = opc.code == atual
		cur.ZIndex = 54
		cur.Parent = b
		local row: Row = { b = b, code = opc.code, cur = cur, sc = sc, e = e }
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
	foot.Position = UDim2.new(0, PAD, 1, -px(10, 14))
	foot.Size = UDim2.new(1, -2 * PAD, 0, px(28, 40))
	foot.ZIndex = 52
	foot.Parent = card
	Estilo.list(foot, true, px(6, 8))
	local aImg = padImage(Enum.KeyCode.ButtonA)
	local bImg = padImage(Enum.KeyCode.ButtonB)
	local function refreshFoot()
		for _, c in foot:GetChildren() do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		local function txt(s: string, k: number)
			local t = Estilo.text(foot, s, px(14, 22), V.DIM, F.BODY)
			t.AutomaticSize = Enum.AutomaticSize.X
			t.Size = UDim2.fromOffset(0, px(28, 40))
			t.LayoutOrder = k
			t.ZIndex = 53
		end
		local function img(im: string, k: number)
			local il = Instance.new("ImageLabel")
			il.BackgroundTransparency = 1
			il.Image = im
			il.Size = UDim2.fromOffset(px(24, 36), px(24, 36))
			il.LayoutOrder = k
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
			txt("Clique ou ← → e Enter · Esc fecha", 1)
		end
	end
	refreshFoot()

	-- teclado e controle (sem o cursor virtual): ← → ↑ ↓, Enter/A, Esc/B
	local STEP: { [Enum.KeyCode]: number } = {
		[Enum.KeyCode.Left] = -1,
		[Enum.KeyCode.Right] = 1,
		[Enum.KeyCode.Up] = -1,
		[Enum.KeyCode.Down] = 1,
		[Enum.KeyCode.DPadLeft] = -1,
		[Enum.KeyCode.DPadRight] = 1,
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
			local x = io.Position.X
			if math.abs(x) < 0.35 then
				stickReady = true
			elseif stickReady and math.abs(x) > 0.6 then
				stickReady = false
				sel = (sel - 1 + (if x > 0 then 1 else -1)) % #rows + 1
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

	-- entra: o véu escurece, o cartão sobe e assenta e os cartões de idioma chegam em fila
	local k = fitK()
	scale.Scale = k * 0.95
	card.Position = UDim2.new(0.5, 0, 0.5, 24)
	tween(layer, 0.25, { BackgroundTransparency = 0.45 })
	tween(card, 0.3, { Position = UDim2.fromScale(0.5, 0.5) })
	tween(scale, 0.3, { Scale = k })
	local list: { GuiObject } = {}
	for _, r in rows do
		table.insert(list, r.b)
	end
	Estilo.enter(list, px(12, 16), 0.03, 0.05)
	paint()
	aberto = close
end

return Idioma
