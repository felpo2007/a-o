--!strict
-- Avisos curtos na tela (pedido do dono, 2026-11-11: "melhore a qualidade visual dos pop ups").
-- Um só sistema para todo aviso que some sozinho, em cinco tipos: info, sucesso, recompensa (XP e
-- créditos), alerta e erro. Visual de 1965, coerente com o lobby (barraca, ficha, carimbo):
--   - cartão oliva quase preto e translúcido, com luz de cima (UIGradient), filete cáqui (UIStroke)
--     e sombra leve; barra lateral e selo com o glifo na cor do tipo;
--   - título curto em caixa alta no Oswald (condensado, o mesmo do lobby) e texto no Arimo; uma
--     pauta fina embaixo é a barra de tempo;
--   - faixa abaixo do centro-topo, longe da mira: no máximo 4, o mais novo em cima, e a pilha nunca
--     passa de 40% da altura da tela; entra descendo com leve escala, sai esmaecendo;
--   - nada pede clique; na TV (UiKit.tv) tudo é maior e o texto não fica abaixo de 24 px.
-- Desempenho: cada aviso usa umas 15 instâncias, reaproveitadas (até 4 por formato); fora as
-- tweens, nada roda por quadro.
-- Uso:
--   Toast.show(texto, tipo?, opções?) -- sem tipo, deduz do texto ("✗ " erro, "✓ " sucesso, "! " alerta)
--   Toast.reward(rótulo, xp, cr, moeda) -- ganho de XP/créditos; o mesmo rótulo soma no aviso aberto
--   Toast.custom(montar, opções?) -- conteúdo próprio no mesmo cartão (cerimônia de promoção)
-- O Bus "toast" (texto, tipo?) chega aqui pelo handler do InfantryController.
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.UiKit)

local Toast = {}

-- tipo do aviso: "info", "sucesso", "recompensa", "alerta" ou "erro" (os nomes em inglês também
-- valem: success, reward, warning, error); outro valor vira "info"
export type Kind = string
export type Options = {
	title: string?, -- título fixo (o texto inteiro vira o corpo)
	fallback: string?, -- título quando o texto não começa com "Prefixo: "
	key: string?, -- mesma chave: atualiza o aviso aberto em vez de empilhar outro
	duration: number?, -- segundos na tela
}
-- onde o conteúdo próprio (Toast.custom) pode desenhar: x e largura úteis, margem, TV
export type Layout = { x: number, w: number, pad: number, tv: boolean }
export type CustomOptions = { kind: Kind?, key: string?, duration: number?, paper: boolean? }

local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

local WIDTH = px(400, 580) -- largura da faixa
local PAD = px(10, 14)
local BAR = px(4, 6) -- barra lateral
local BADGE = px(24, 36) -- selo do glifo
local GAP = px(6, 10) -- entre avisos
local LINE = px(2, 3) -- barra de tempo
local FOOT = LINE + px(4, 6) -- a barra de tempo fica a 4 px do pé do cartão
local TOP = px(64, 72) -- abaixo da barra do Roblox
local MAX = 4
local REACH = 0.4 -- a pilha não desce além de 40% da altura da tela (a mira fica no meio)
local TITLE_SIZE = px(16, 26)
local BODY_SIZE = UiKit.text(16)
local CHIP_SIZE = px(16, 26)
local CHIP_H = px(24, 38)
local CARD_W = WIDTH - 4 -- 4 px para a sombra
local TEXT_X = BAR + PAD + BADGE + PAD
local TEXT_W = CARD_W - TEXT_X - PAD

local CARD_DARK = Color3.fromRGB(26, 28, 21) -- oliva quase preto
local LIGHT = UiKit.CARD -- texto claro (cor da ficha)
local CHIP_CR = Color3.fromRGB(104, 134, 74) -- créditos: verde de cédula (o XP vai em latão)

type Style = { accent: Color3, title: Color3, glyph: string, label: string, life: number }
local STYLE: { [string]: Style } = {
	info = {
		accent = Color3.fromRGB(132, 160, 190),
		title = Color3.fromRGB(178, 200, 222),
		glyph = "i",
		label = "Aviso",
		life = 3.4,
	},
	sucesso = {
		accent = Color3.fromRGB(122, 158, 84),
		title = Color3.fromRGB(172, 206, 126),
		glyph = "✓",
		label = "Confirmado",
		life = 3.2,
	},
	recompensa = {
		accent = UiKit.BRASS,
		title = Color3.fromRGB(236, 202, 116),
		glyph = "★",
		label = "Recompensa",
		life = 2.8,
	},
	alerta = {
		accent = Color3.fromRGB(226, 148, 52),
		title = Color3.fromRGB(244, 184, 96),
		glyph = "!",
		label = "Atenção",
		life = 4.2,
	},
	erro = {
		accent = Color3.fromRGB(200, 70, 54),
		title = Color3.fromRGB(240, 124, 104),
		glyph = "✕",
		label = "Negado",
		life = 4.6,
	},
}
local KIND: { [string]: Kind } = {
	info = "info",
	sucesso = "sucesso",
	recompensa = "recompensa",
	alerta = "alerta",
	erro = "erro",
	success = "sucesso",
	reward = "recompensa",
	warning = "alerta",
	error = "erro",
}

-- selo que outros controllers já põem no começo do texto (CommanderController: "✗ " e "✓ ")
local PREFIX: { { prefix: string, kind: Kind } } = {
	{ prefix = "✗ ", kind = "erro" },
	{ prefix = "✓ ", kind = "sucesso" },
	{ prefix = "! ", kind = "alerta" },
}
-- Textos conhecidos que chegam sem tipo, ou como erro (o servidor manda tudo pelo campo "error"
-- do Logistics_State), e pedem outra cor. O tipo passado em Bus.fire("toast", texto, tipo) vale
-- mais que esta lista; o título daqui só entra quando o texto não tem "Prefixo: ".
local KNOWN: { { pattern: string, kind: Kind, title: string? } } = {
	{ pattern = "^Sem fôlego", kind = "alerta", title = "Fôlego" },
	{ pattern = "desligada neste modo", kind = "alerta", title = "Câmera" },
	{ pattern = "^Passa do limite de peso", kind = "alerta" },
	{ pattern = "^Conflito com outra ação", kind = "alerta" },
	{ pattern = "^Pancada de chuva", kind = "alerta" },
	{ pattern = "^Nenhuma missão", kind = "alerta", title = "Comando" },
	{ pattern = "^Armadilha à vista", kind = "alerta" },
	{ pattern = "^Armadilha desarmada", kind = "sucesso", title = "Armadilha" },
	{ pattern = "^Pá: cancelado", kind = "alerta" },
	{ pattern = "^Cavando", kind = "info", title = "Pá" },
	{ pattern = "^Evacuado", kind = "sucesso" },
}

-- (tipo, texto sem o selo, título sugerido)
local function classify(text: string, kind: string?): (Kind, string, string?)
	local rest = text
	local k: Kind = "info"
	for _, p in PREFIX do
		if string.sub(text, 1, #p.prefix) == p.prefix then
			rest = string.sub(text, #p.prefix + 1)
			k = p.kind
			break
		end
	end
	local title: string? = nil
	for _, g in KNOWN do
		if string.find(rest, g.pattern) then
			k = g.kind
			title = g.title
			break
		end
	end
	local explicit: Kind? = if kind then KIND[kind] else nil
	return explicit or k, rest, title
end

-- "Alça de mira: 200 m" vira título "ALÇA DE MIRA" e texto "200 m" (prefixo curto, sem ponto)
local function split(text: string): (string?, string)
	local head, tail = string.match(text, "^([^:%.!?]+):%s+(.+)$")
	if head and tail and (utf8.len(head) or 99) <= 24 then
		return head, tail
	end
	return nil, text
end

local function lifeFor(kind: Kind, text: string): number
	local base = STYLE[kind].life
	local n = utf8.len(text) or #text
	return math.min(base + math.max(n - 40, 0) * 0.04, 7)
end

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

-- ===== peças =====
local function corner(o: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

local function label(parent: Instance, name: string): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

-- esmaecer: cada transparência volta ao valor de projeto (base) ao entrar e vai a 1 ao sair
type Fade = { inst: Instance, prop: string, base: number }
local function fadeList(root: Instance): { Fade }
	local out: { Fade } = {}
	local function add(o: Instance)
		local function keep(prop: string, base: number)
			if base < 1 then
				table.insert(out, { inst = o, prop = prop, base = base })
			end
		end
		if o:IsA("GuiObject") then
			keep("BackgroundTransparency", o.BackgroundTransparency)
			if o:IsA("TextLabel") then
				keep("TextTransparency", o.TextTransparency)
			elseif o:IsA("ImageLabel") then
				keep("ImageTransparency", o.ImageTransparency)
			end
		elseif o:IsA("UIStroke") then
			keep("Transparency", o.Transparency)
		end
	end
	add(root)
	for _, d in root:GetDescendants() do
		add(d)
	end
	return out
end

local function fade(list: { Fade }, show: boolean, t: number)
	local info =
		TweenInfo.new(t, Enum.EasingStyle.Quad, if show then Enum.EasingDirection.Out else Enum.EasingDirection.In)
	for _, f in list do
		if show then
			(f.inst :: any)[f.prop] = 1
		end
		TweenService:Create(f.inst, info, { [f.prop] = if show then f.base else 1 }):Play()
	end
end

-- ===== tela e pilha =====
local screen = UiKit.screen("VT65Avisos", 45) -- acima do HUD e dos menus (avisos do menu também)
local band = Instance.new("Frame")
band.Name = "Pilha"
band.AnchorPoint = Vector2.new(0.5, 0)
band.Position = UDim2.new(0.5, 0, 0, TOP)
band.Size = UDim2.fromOffset(WIDTH, 0)
band.BackgroundTransparency = 1
band.Parent = screen
local stack = Instance.new("UIListLayout")
stack.SortOrder = Enum.SortOrder.LayoutOrder
stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
stack.Parent = band
-- janela estreita (celular, janela pequena): a faixa encolhe inteira, nada passa da borda
UiKit.fit(screen, band, WIDTH + 8, 1, 8)

-- Avisos que outra tela mostra melhor: intercept(chave, fn) recebe o texto de Toast.show com essa
-- chave; fn devolve true quando mostrou (o aviso não entra na pilha). O HUD de campo (HudCampo)
-- mostra os da arma ("arma": seletor, alça, troca) no cartão da arma, embaixo à direita.
local intercepts: { [string]: (text: string) -> boolean } = {}
function Toast.intercept(key: string, fn: ((text: string) -> boolean)?)
	intercepts[key] = fn :: any
end

type Entry = {
	form: string, -- "texto", "ganho" ou "livre"
	key: string?,
	slot: Frame, -- espaço na pilha (a altura anima e empurra os outros)
	root: Frame,
	scale: UIScale,
	card: Frame,
	bar: Frame,
	line: Frame, -- barra de tempo
	fades: { Fade },
	height: number,
	life: number,
	token: number,
	dying: boolean,
	badge: Frame?,
	glyph: TextLabel?,
	title: TextLabel?,
	body: TextLabel?,
	xpChip: TextLabel?,
	crChip: TextLabel?,
	caption: TextLabel?,
	xp: number,
	cr: number,
}

local live: { Entry } = {} -- do mais velho para o mais novo
local pool: { [string]: { Entry } } = { texto = {}, ganho = {} }
local order = 0

-- cartão vazio: sombra, fundo, filete, luz de cima, barra lateral e barra de tempo
local function shell(form: string, paper: boolean): Entry
	local slot = Instance.new("Frame")
	slot.Name = "Aviso"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.new(1, 0, 0, 0)
	-- o corpo fica preso ao pé do espaço: enquanto o espaço abre, o cartão desce para o lugar
	local root = Instance.new("Frame")
	root.Name = "Corpo"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -GAP)
	root.Size = UDim2.fromOffset(CARD_W, 0)
	root.BackgroundTransparency = 1
	root.Parent = slot
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local shadow = Instance.new("Frame")
	shadow.Name = "Sombra"
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.Position = UDim2.fromOffset(2, 3)
	shadow.Size = UDim2.fromScale(1, 1)
	corner(shadow, 5)
	shadow.Parent = root
	local card = Instance.new("Frame")
	card.Name = "Cartao"
	card.BackgroundColor3 = if paper then UiKit.CARD else CARD_DARK
	card.BackgroundTransparency = if paper then 0 else 0.1
	card.BorderSizePixel = 0
	card.Size = UDim2.fromScale(1, 1)
	corner(card, 4)
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = if paper then UiKit.INK else UiKit.KHAKI
	edge.Transparency = if paper then 0.55 else 0.72
	edge.Thickness = 1
	edge.Parent = card
	-- luz de cima (o UIGradient só pinta o próprio cartão, não os filhos)
	local light = Instance.new("UIGradient")
	light.Rotation = 90
	light.Color = if paper
		then ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(214, 206, 188))
		else ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 160))
	light.Parent = card
	card.Parent = root
	local bar = Instance.new("Frame")
	bar.Name = "Barra"
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0, BAR, 1, 0)
	corner(bar, 2)
	bar.Parent = card
	local line = Instance.new("Frame")
	line.Name = "Tempo"
	line.AnchorPoint = Vector2.new(0, 1)
	line.BorderSizePixel = 0
	line.BackgroundTransparency = 0.35
	line.Position = UDim2.new(0, BAR + PAD, 1, -(FOOT - LINE))
	line.Size = UDim2.new(1, -(BAR + 2 * PAD), 0, LINE)
	line.Parent = card
	return {
		form = form,
		key = nil,
		slot = slot,
		root = root,
		scale = scale,
		card = card,
		bar = bar,
		line = line,
		fades = {},
		height = 0,
		life = 3,
		token = 0,
		dying = false,
		xp = 0,
		cr = 0,
	}
end

local function addBadge(e: Entry, y: number)
	local badge = Instance.new("Frame")
	badge.Name = "Selo"
	badge.BorderSizePixel = 0
	badge.Position = UDim2.fromOffset(BAR + PAD, y)
	badge.Size = UDim2.fromOffset(BADGE, BADGE)
	corner(badge, 3)
	badge.Parent = e.card
	local g = label(badge, "Glifo")
	g.Size = UDim2.fromScale(1, 1)
	g.TextXAlignment = Enum.TextXAlignment.Center
	g.FontFace = UiKit.HEAD_FONT
	g.TextSize = math.floor(BADGE * 0.7)
	g.TextColor3 = UiKit.NIGHT
	e.badge, e.glyph = badge, g
end

local function paint(e: Entry, kind: Kind)
	local st = STYLE[kind]
	e.bar.BackgroundColor3 = st.accent
	e.line.BackgroundColor3 = st.accent
	if e.badge and e.glyph then
		e.badge.BackgroundColor3 = st.accent
		e.glyph.Text = st.glyph
	end
end

-- formato "texto": selo, título e texto
local function buildText(): Entry
	local e = shell("texto", false)
	addBadge(e, PAD)
	local title = label(e.card, "Titulo")
	title.Position = UDim2.fromOffset(TEXT_X, PAD - 2)
	title.Size = UDim2.fromOffset(TEXT_W, TITLE_SIZE + 4)
	title.FontFace = UiKit.HEAD_FONT
	title.TextSize = TITLE_SIZE
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local body = label(e.card, "Texto")
	body.Position = UDim2.fromOffset(TEXT_X, PAD + TITLE_SIZE + 4)
	body.Font = UiKit.BODY_FONT
	body.TextSize = BODY_SIZE
	body.TextColor3 = LIGHT
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	e.title, e.body = title, body
	e.fades = fadeList(e.root)
	return e
end

local function fillText(e: Entry, kind: Kind, title: string, text: string): number
	paint(e, kind)
	local t, b = e.title :: TextLabel, e.body :: TextLabel
	t.Text = UiKit.upper(title)
	t.FontFace = UiKit.headFont(title)
	t.TextColor3 = STYLE[kind].title
	b.Text = text
	local h = math.ceil(TextService:GetTextSize(text, BODY_SIZE, UiKit.BODY_FONT, Vector2.new(TEXT_W, 10000)).Y)
	b.Size = UDim2.fromOffset(TEXT_W, h + 2)
	return PAD + TITLE_SIZE + 4 + h + 2 + PAD + FOOT
end

-- formato "ganho": selo, chips "+10 XP" (latão) e "+$ 2" (verde) e o motivo
local function chip(parent: Instance, name: string, bg: Color3, fg: Color3, n: number): TextLabel
	local c = label(parent, name)
	c.AutomaticSize = Enum.AutomaticSize.X
	c.Size = UDim2.new(0, 0, 1, 0)
	c.BackgroundTransparency = 0
	c.BackgroundColor3 = bg
	c.TextColor3 = fg
	c.FontFace = UiKit.HEAD_FONT
	c.TextSize = CHIP_SIZE
	c.TextXAlignment = Enum.TextXAlignment.Center
	c.LayoutOrder = n
	corner(c, 3)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px(7, 10))
	p.PaddingRight = UDim.new(0, px(7, 10))
	p.Parent = c
	return c
end

local function buildGain(): Entry
	local e = shell("ganho", false)
	addBadge(e, PAD + math.floor((CHIP_H - BADGE) / 2))
	local row = Instance.new("Frame")
	row.Name = "Linha"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(TEXT_X, PAD)
	row.Size = UDim2.fromOffset(TEXT_W, CHIP_H)
	row.Parent = e.card
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, px(6, 8))
	lay.Parent = row
	e.xpChip = chip(row, "XP", UiKit.BRASS, UiKit.NIGHT, 1)
	e.crChip = chip(row, "Creditos", CHIP_CR, LIGHT, 2)
	local cap = label(row, "Motivo")
	cap.LayoutOrder = 3
	cap.Size = UDim2.new(0, 0, 1, 0)
	cap.FontFace = UiKit.HEAD_FONT
	cap.TextSize = TITLE_SIZE
	cap.TextColor3 = STYLE.recompensa.title
	cap.TextTruncate = Enum.TextTruncate.AtEnd
	local fill = Instance.new("UIFlexItem") -- o motivo ocupa o que sobra da linha
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = cap
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px(4, 6))
	p.Parent = cap
	e.caption = cap
	e.fades = fadeList(e.root)
	return e
end

local function fillGain(e: Entry, caption: string, xp: number, cr: number, cur: string): number
	paint(e, "recompensa")
	e.xp, e.cr = xp, cr
	local x, c, l = e.xpChip :: TextLabel, e.crChip :: TextLabel, e.caption :: TextLabel
	x.Text = "+" .. fmt(xp) .. " XP"
	x.Visible = xp > 0
	-- dinheiro do jogo com o símbolo na frente ("+$ 2"); outra moeda segue depois do número
	c.Text = "+" .. (if cur == "$" then "$ " .. fmt(cr) else fmt(cr) .. " " .. cur)
	c.Visible = cr > 0
	l.Text = UiKit.upper(caption)
	l.FontFace = UiKit.headFont(caption)
	return PAD + CHIP_H + PAD + FOOT
end

-- ===== vida de um aviso =====
local function find(key: string): Entry?
	for _, e in live do
		if e.key == key and not e.dying then
			return e
		end
	end
	return nil
end

local function take(form: string): Entry?
	local p = pool[form]
	return if p and #p > 0 then table.remove(p) else nil
end

local function setHeight(e: Entry, h: number)
	e.height = h
	e.root.Size = UDim2.fromOffset(CARD_W, h)
end

local function dismiss(e: Entry, fast: boolean)
	if e.dying then
		return
	end
	e.dying = true
	e.token += 1
	local i = table.find(live, e)
	if i then
		table.remove(live, i)
	end
	local t = if fast then 0.16 else 0.4
	fade(if e.form == "livre" then fadeList(e.root) else e.fades, false, t)
	TweenService:Create(e.scale, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.96 })
		:Play()
	task.delay(t, function()
		-- o espaço fecha e os de baixo sobem; o cartão volta para a reserva (ou é destruído)
		local close = TweenService:Create(
			e.slot,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(1, 0, 0, 0) }
		)
		close.Completed:Once(function()
			local p = pool[e.form]
			if p and #p < MAX then
				e.slot.Parent = nil
				table.insert(p, e)
			else
				e.slot:Destroy()
			end
		end)
		close:Play()
	end)
end

-- barra de tempo e saída programada (de novo a cada atualização)
local function arm(e: Entry)
	e.token += 1
	local my = e.token
	e.line.Size = UDim2.new(1, -(BAR + 2 * PAD), 0, LINE)
	TweenService:Create(e.line, TweenInfo.new(e.life, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, LINE) })
		:Play()
	task.delay(e.life, function()
		if e.token == my then
			dismiss(e, false)
		end
	end)
end

local function pulse(e: Entry)
	e.scale.Scale = 1.05
	TweenService:Create(e.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

local function push(e: Entry)
	order -= 1
	e.slot.LayoutOrder = order -- o mais novo em cima
	e.slot.Size = UDim2.new(1, 0, 0, 0)
	e.dying = false
	e.slot.Parent = band
	table.insert(live, e)
	-- no máximo MAX, e a pilha não desce até a mira: sai o mais velho
	local reach = math.max(screen.AbsoluteSize.Y * REACH - TOP, 0)
	local total = 0
	for _, o in live do
		total += o.height + GAP
	end
	while #live > 1 and (#live > MAX or total > reach) do
		total -= live[1].height + GAP
		dismiss(live[1], true)
	end
	-- entrada: o espaço abre (empurra os outros para baixo), o cartão desce e cresce um pouco
	TweenService:Create(
		e.slot,
		TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, 0, e.height + GAP) }
	):Play()
	e.scale.Scale = 0.92
	TweenService:Create(e.scale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	fade(e.fades, true, 0.22)
	arm(e)
end

-- ===== API =====

-- Aviso de texto. tipo: "info", "sucesso", "recompensa", "alerta" ou "erro" (nil: deduz do texto).
-- "Prefixo: resto" vira título e texto; sem prefixo, o título é o do tipo (ou opções.fallback).
function Toast.show(text: string, kind: string?, opts: Options?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local o: Options = opts or {}
	local hook = o.key and intercepts[o.key]
	if hook then
		local ok, taken = pcall(hook, text)
		if ok and taken then
			return
		end
	end
	local k, rest, known = classify(text, kind)
	local title: string, body: string
	if o.title then
		title, body = o.title, rest
	else
		local head, tail = split(rest)
		if head then
			title, body = head, tail
		else
			title, body = known or o.fallback or STYLE[k].label, rest
		end
	end
	body = UiKit.capitalize(body)
	local life = o.duration or lifeFor(k, body)
	if o.key then
		local e = find(o.key)
		if e and e.form == "texto" then
			local h = fillText(e, k, title, body)
			if h ~= e.height then
				setHeight(e, h)
				TweenService:Create(e.slot, TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, h + GAP) }):Play()
			end
			e.life = life
			pulse(e)
			arm(e)
			return
		end
	end
	local e = take("texto") or buildText()
	e.key = o.key
	e.life = life
	setHeight(e, fillText(e, k, title, body))
	push(e)
end

-- Ganho de XP e créditos (moeda: "$", ...). Ganhos com o mesmo motivo somam no aviso aberto.
function Toast.reward(caption: string, xp: number, cr: number, cur: string)
	xp, cr = math.max(xp, 0), math.max(cr, 0)
	if xp <= 0 and cr <= 0 then
		return
	end
	local key = "ganho|" .. caption .. "|" .. cur
	local life = STYLE.recompensa.life
	local open = find(key)
	if open and open.form == "ganho" then
		fillGain(open, caption, open.xp + xp, open.cr + cr, cur)
		open.life = life
		pulse(open)
		arm(open)
		return
	end
	local e = take("ganho") or buildGain()
	e.key = key
	e.life = life
	setHeight(e, fillGain(e, caption, xp, cr, cur))
	push(e)
end

-- Conteúdo próprio no cartão de aviso (com barra lateral e barra de tempo). montar(cartão, layout)
-- põe as peças e devolve a altura usada a partir do topo; paper = papel cáqui em vez do escuro.
function Toast.custom(build: (card: Frame, layout: Layout) -> number, opts: CustomOptions?)
	local o: CustomOptions = opts or {}
	if o.key then
		local old = find(o.key)
		if old then
			dismiss(old, true)
		end
	end
	local e = shell("livre", o.paper == true)
	e.key = o.key
	e.life = o.duration or 5
	paint(e, KIND[o.kind or "info"] or "info")
	local x = BAR + PAD
	local h = build(e.card, { x = x, w = CARD_W - x - PAD, pad = PAD, tv = TV })
	setHeight(e, h + PAD + FOOT)
	e.fades = fadeList(e.root)
	push(e)
end

-- ===== gancho de teste (só no Studio): fotos de cada tipo, com textos reais do jogo =====
-- workspace:SetAttribute("VT65DevToast", x), x = "info", "sucesso", "recompensa", "alerta", "erro",
-- "arma" ou "todos" ("promocao" fica no Progresso). Na barra de comando do lado do cliente o valor
-- volta a nil sozinho e dá para repetir; do lado do servidor, alterne os valores. Numa janela baixa
-- cabem menos de 4 (a pilha para em 40% da altura).
if RunService:IsStudio() then
	local SAMPLES: { [string]: () -> () } = {
		info = function()
			Toast.show("Câmera: 3ª pessoa (ombro direito)")
		end,
		sucesso = function()
			Toast.show(
				"Tutorial concluído. Refazer: menu do jogo → Squad e papel.",
				"sucesso",
				{ title = "Tutorial" }
			)
		end,
		recompensa = function()
			Toast.reward("Tempo em campo", 10, 2, "$")
		end,
		alerta = function()
			Toast.show("Pancada de chuva: visão curta e passos abafados")
		end,
		erro = function()
			Toast.show("✗ construa a posição de morteiro primeiro (tecla J)")
		end,
		arma = function()
			Toast.show("Seletor: AUTO", "info", { key = "arma", fallback = "Arma", duration = 1.8 })
		end,
	}
	workspace:GetAttributeChangedSignal("VT65DevToast"):Connect(function()
		local v = workspace:GetAttribute("VT65DevToast")
		if type(v) ~= "string" then
			return
		end
		if v == "todos" then -- a pilha cabe 4: o "sucesso" sai sozinho
			for i, k in { "erro", "alerta", "recompensa", "info" } do
				task.delay((i - 1) * 0.4, SAMPLES[k])
			end
		elseif SAMPLES[v] then
			SAMPLES[v]()
		end
		if v ~= "promocao" then
			task.defer(function()
				workspace:SetAttribute("VT65DevToast", nil) -- local: no cliente, o mesmo valor repete
			end)
		end
	end)
end

return Toast
