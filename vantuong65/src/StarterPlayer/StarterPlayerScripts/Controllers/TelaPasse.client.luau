--!strict
-- Passe de campanha (plano de volta diária, 2026-11-12: "Operação Starlite: Temporada 1", 50 níveis,
-- estrelas, trilha grátis e Veterano). Abre por Bus "passe_open" (menu principal, tela de baixa).
-- D-124 (lote 11, pedido do dono: "coloque o passe em ordem cronológica horizontal"): os 50 níveis
-- numa linha do tempo da esquerda para a direita, desenhada como a rota de uma operação na carta:
--   - cada nível é um marco na linha, com o número no círculo; de 10 em 10, um marco maior;
--   - o trecho já andado fica em latão; o marco do nível atual pulsa;
--   - a trilha VETERANO fica em cima e a GRÁTIS embaixo, cada cartão preso ao marco por um traço;
--   - embaixo, a ficha do item escolhido: receber, receber tudo, o Veterano e pular nível (Robux,
--     Commerce.IDS).
-- Os 50 níveis são montados uma vez (em segundo plano, logo depois de carregar); abrir só pinta.
-- Controle: A escolhe (e recebe o que já pode), o direcional anda de nível em nível, LB/RB andam 10
-- níveis, LT/RT trocam de trilha, B fecha. Mouse: roda ou as setas ◄ ► dos lados; toque: arrastar.
-- O estado vem do servidor (CampanhaCliente); a tela nunca espera vazia.
-- Sem pressão falsa: o único relógio é o fim real da temporada.
-- Studio: workspace:SetAttribute("VT65DevTela", "passe") abre (com um estado de exemplo se o
-- servidor ainda não mandou o passe).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Bus = require(script.Parent.Bus)
local CampanhaCliente = require(script.Parent.CampanhaCliente)
local Input = require(script.Parent.Input)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local px = UiKit.px
local MAX = 50

local W, H = px(1000, 1320), px(640, 860)
local PAD = px(20, 28)
local HEAD_H = px(104, 138)
local FOOT_H = px(46, 64)
local DETAIL_H = px(140, 186)
-- linha do tempo
local GUTTER = px(96, 128) -- rótulos fixos das trilhas, à esquerda
local COL_W = px(128, 170)
local COL_GAP = px(12, 16)
local CARD_H = px(116, 154)
local NODE_ROW = px(52, 70)
local NODE_D = px(30, 40)
local LINE_H = px(4, 6)
local VET_BG = Color3.fromRGB(46, 39, 22) -- cartão do Veterano: oliva puxado para o latão
local VET_BG_HI = Color3.fromRGB(62, 52, 28)

-- ===== montagem =====
local gui = UiKit.screen("VT65Passe", 38) -- acima da loja (30) e do menu (35)
gui.Enabled = false
local dim = Instance.new("Frame")
dim.Name = "Veu"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = V.BG
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Active = true
dim.Parent = gui

local panel = UiKit.panel(gui, V.PANEL, 0.03)
panel.Name = "Passe"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(W, H)
local fit = UiKit.fit(gui, panel, W, H, 12)
do -- faixa de latão no alto (o passe é a "recompensa")
	local a = Instance.new("Frame")
	a.BackgroundColor3 = V.BRASS
	a.BorderSizePixel = 0
	a.Size = UDim2.new(1, 0, 0, px(3, 4))
	a.Parent = panel
end

-- cabeçalho: rótulo, nome da temporada, nível grande, barra de estrelas e o fim real
local kick = UiKit.kicker(panel, "PASSE DE CAMPANHA", px(14, 20), V.BRASS)
kick.Position = UDim2.fromOffset(PAD, px(14, 18))
kick.Size = UDim2.fromOffset(px(300, 400), px(20, 28))
local title = UiKit.title(panel, "", px(30, 42))
title.Position = UDim2.fromOffset(PAD, px(34, 46))
title.Size = UDim2.new(1, -(PAD + px(330, 440)), 0, px(40, 54))
local ends = UiKit.kicker(panel, "", px(13, 19))
ends.Position = UDim2.fromOffset(PAD, px(76, 102))
ends.Size = UDim2.fromOffset(px(420, 560), px(18, 26))
local levelStat = UiKit.stat(panel, "NÍVEL", "0", px(40, 56))
levelStat.frame.AnchorPoint = Vector2.new(1, 0)
levelStat.frame.Position = UDim2.new(1, -(PAD + px(176, 232)), 0, px(24, 32))
local starsBox = Instance.new("Frame")
starsBox.BackgroundTransparency = 1
starsBox.AnchorPoint = Vector2.new(1, 0)
starsBox.Position = UDim2.new(1, -PAD, 0, px(46, 62))
starsBox.Size = UDim2.fromOffset(px(160, 214), px(56, 76))
starsBox.Parent = panel
local starsLabel = UiKit.kicker(starsBox, "", px(13, 19), V.KHAKI)
starsLabel.Size = UDim2.new(1, 0, 0, px(20, 28))
local starsBack, starsFill = UiKit.bar(starsBox, px(8, 12), V.BRASS)
starsBack.Position = UDim2.fromOffset(0, px(24, 32))

-- fechar
local closeBtn = UiKit.action(panel, "FECHAR ×", "secondary", function()
	Bus.fire("passe_close")
end, { h = px(34, 48) })
closeBtn.button.AnchorPoint = Vector2.new(1, 0)
closeBtn.button.Position = UDim2.new(1, -PAD, 0, px(10, 14))
closeBtn.button.Size = UDim2.fromOffset(px(110, 150), px(28, 40))
closeBtn.button.Selectable = false

-- ----- a faixa da linha do tempo -----
local TL_Y = HEAD_H + px(4, 6)
local TL_H = H - TL_Y - DETAIL_H - FOOT_H - px(6, 8)
local strip = Instance.new("Frame")
strip.Name = "LinhaDoTempo"
strip.BackgroundColor3 = V.BG
strip.BackgroundTransparency = 0.35
strip.BorderSizePixel = 0
strip.Position = UDim2.fromOffset(PAD, TL_Y)
strip.Size = UDim2.new(1, -2 * PAD, 0, TL_H)
strip.ClipsDescendants = true
strip.Parent = panel
UiKit.corner(strip, 4)
UiKit.edge(strip, V.LINE, 1, 0.55)
-- a altura útil (sem a barra de rolagem) e onde ficam os cartões e a linha dentro dela
local SCROLL_BAR = px(6, 8)
local INNER_H = TL_H - SCROLL_BAR - px(4, 6)
local TOP_Y = math.max(0, math.floor((INNER_H - (2 * CARD_H + NODE_ROW)) / 2))
local NODE_Y = TOP_Y + CARD_H + NODE_ROW // 2 -- o meio da linha
local FREE_Y = TOP_Y + CARD_H + NODE_ROW

-- rótulos fixos das trilhas (não rolam)
local gutter = Instance.new("Frame")
gutter.Name = "Trilhas"
gutter.BackgroundColor3 = V.PANEL
gutter.BackgroundTransparency = 0
gutter.BorderSizePixel = 0
gutter.Size = UDim2.new(0, GUTTER, 1, 0)
gutter.ZIndex = 3
gutter.Parent = strip
local function trackLabel(y: number, name: string, color: Color3): TextLabel
	local t = UiKit.title(gutter, name, px(17, 24), color)
	t.Position = UDim2.fromOffset(px(10, 14), y + CARD_H // 2 - px(22, 30))
	t.Size = UDim2.new(1, -px(14, 18), 0, px(24, 32))
	t.ZIndex = 3
	local sub = UiKit.kicker(gutter, "", px(11, 15))
	sub.Position = UDim2.fromOffset(px(10, 14), y + CARD_H // 2 + px(4, 6))
	sub.Size = UDim2.new(1, -px(14, 18), 0, px(30, 40))
	sub.TextWrapped = true
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.ZIndex = 3
	return sub
end
local vetSub = trackLabel(TOP_Y, "VETERANO", V.BRASS)
local freeSub = trackLabel(FREE_Y, "GRÁTIS", V.OLIVE_HI)
freeSub.Text = "PARA TODOS"
do -- o marco do rótulo na altura da linha
	local t = UiKit.kicker(gutter, "NÍVEL", px(12, 17), V.DIM)
	t.Position = UDim2.fromOffset(px(10, 14), NODE_Y - px(9, 12))
	t.Size = UDim2.new(1, -px(14, 18), 0, px(18, 24))
	t.ZIndex = 3
	local r = Instance.new("Frame")
	r.BackgroundColor3 = V.LINE
	r.BorderSizePixel = 0
	r.AnchorPoint = Vector2.new(1, 0)
	r.Position = UDim2.new(1, 0, 0, 0)
	r.Size = UDim2.new(0, 1, 1, 0)
	r.ZIndex = 3
	r.Parent = gutter
end

local list = Instance.new("ScrollingFrame")
list.Name = "Niveis"
list.Position = UDim2.fromOffset(GUTTER, 0)
list.Size = UDim2.new(1, -GUTTER, 1, 0)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = SCROLL_BAR
list.ScrollBarImageColor3 = V.KHAKI
list.ScrollBarImageTransparency = 0.35
list.HorizontalScrollBarInset = Enum.ScrollBarInset.None
list.CanvasSize = UDim2.fromOffset(COL_GAP + MAX * (COL_W + COL_GAP) + COL_GAP, 0)
list.ScrollingDirection = Enum.ScrollingDirection.X
list.ElasticBehavior = Enum.ElasticBehavior.Never
list.Selectable = false
list.Parent = strip

-- a rota: a linha toda apagada e o trecho já andado em latão por cima
local function colX(lvl: number): number
	return COL_GAP + (lvl - 1) * (COL_W + COL_GAP)
end
local route = Instance.new("Frame")
route.Name = "Rota"
route.BackgroundColor3 = V.LINE
route.BackgroundTransparency = 0.2
route.BorderSizePixel = 0
route.Position = UDim2.fromOffset(colX(1) + COL_W // 2, NODE_Y - LINE_H // 2)
route.Size = UDim2.fromOffset(colX(MAX) - colX(1), LINE_H)
route.Parent = list
UiKit.corner(route, LINE_H // 2)
local walked = Instance.new("Frame")
walked.Name = "Andado"
walked.BackgroundColor3 = V.BRASS
walked.BorderSizePixel = 0
walked.Position = route.Position
walked.Size = UDim2.fromOffset(0, LINE_H)
walked.ZIndex = 2
walked.Parent = list
UiKit.corner(walked, LINE_H // 2)

-- setas dos lados (mouse): andam 4 níveis
local scrollBy: (cols: number) -> () = function(_cols: number) end
local function arrow(text: string, left: boolean, cols: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = if left then "Esquerda" else "Direita"
	b.AutoButtonColor = false
	b.Text = text
	b.FontFace = F.TITLE
	b.TextSize = UiKit.text(px(18, 24))
	b.TextColor3 = V.TEXT
	b.BackgroundColor3 = V.PANEL_3
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AnchorPoint = Vector2.new(if left then 0 else 1, 0.5)
	b.Position = if left then UDim2.fromOffset(GUTTER + px(6, 8), NODE_Y) else UDim2.new(1, -px(6, 8), 0, NODE_Y)
	b.Size = UDim2.fromOffset(px(34, 46), px(34, 46))
	b.Selectable = false
	b.ZIndex = 4
	b.Parent = strip
	UiKit.corner(b, px(17, 23))
	UiKit.edge(b, V.KHAKI, 1, 0.4)
	local r = UiKit.realce(b, V.PANEL_3, V.OLIVE, 1.08)
	b.MouseEnter:Connect(function()
		r.set(true)
	end)
	b.MouseLeave:Connect(function()
		r.set(false)
	end)
	UiKit.bind(b, function()
		scrollBy(cols)
	end)
	return b
end
local leftArrow = arrow("◄", true, -4)
local rightArrow = arrow("►", false, 4)

-- ----- ficha do item escolhido (embaixo) -----
local detail = UiKit.panel(panel, V.PANEL_2, 0)
detail.Name = "Ficha"
detail.Position = UDim2.fromOffset(PAD, H - FOOT_H - DETAIL_H)
detail.Size = UDim2.new(1, -2 * PAD, 0, DETAIL_H - px(6, 8))
local P = px(12, 16)
local DH = DETAIL_H - px(6, 8)
local ICON = DH - 2 * P
local prevThumb = Instance.new("Frame")
prevThumb.Name = "Icone"
prevThumb.BackgroundColor3 = V.PANEL_3
prevThumb.BorderSizePixel = 0
prevThumb.Position = UDim2.fromOffset(P, P)
prevThumb.Size = UDim2.fromOffset(ICON, ICON)
prevThumb.Parent = detail
UiKit.corner(prevThumb, 4)
local prevGlow = Instance.new("UIGradient")
prevGlow.Rotation = 90
prevGlow.Parent = prevThumb
local prevMark = UiKit.text2(prevThumb, "★", px(48, 64), V.BRASS, F.TITLE)
prevMark.Size = UDim2.fromScale(1, 1)
prevMark.TextXAlignment = Enum.TextXAlignment.Center
local BTN_W = px(214, 286)
local BTN_H = px(40, 54)
local textX = P + ICON + px(14, 18)
local textW = -(textX + 2 * BTN_W + px(24, 32))
local prevKind = UiKit.kicker(detail, "", px(13, 19))
prevKind.Position = UDim2.fromOffset(textX, P)
prevKind.Size = UDim2.new(1, textW, 0, px(18, 26))
local prevName = UiKit.title(detail, "", px(26, 36))
prevName.Position = UDim2.fromOffset(textX, P + px(18, 26))
prevName.Size = UDim2.new(1, textW, 0, px(36, 48))
prevName.TextScaled = true
do
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = UiKit.text(px(26, 36))
	lim.MinTextSize = UiKit.text(px(15, 20))
	lim.Parent = prevName
end
local prevInfo = UiKit.body(detail, "", px(14, 20), V.DIM)
prevInfo.Position = UDim2.fromOffset(textX, P + px(58, 78))
prevInfo.Size = UDim2.new(1, textW, 0, px(40, 54))
prevInfo.TextWrapped = true
prevInfo.TextYAlignment = Enum.TextYAlignment.Top
-- botões em duas colunas à direita: receber | Veterano, receber tudo | pular nível. Cores de compra
-- (UiKit.PAGAR, 2026-11-13): receber é grátis (oliva); o Veterano e o pular nível se pagam em Robux
-- (verde); sem ID, apagados
local function place(b: TextButton, col: number, row: number)
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -(P + (2 - col) * (BTN_W + px(10, 14))), 0, P + (row - 1) * (BTN_H + px(10, 14)))
	b.Size = UDim2.fromOffset(BTN_W, BTN_H)
end
local claimOne = UiKit.action(detail, "RECEBER", "primary", function()
	Bus.fire("passe_claim_selected")
end, { h = BTN_H })
place(claimOne.button, 1, 1)
claimOne.label.TextXAlignment = Enum.TextXAlignment.Center
local claimAll = UiKit.action(detail, "RECEBER TUDO", "free", function()
	CampanhaCliente.action("claim_all")
end, { h = BTN_H })
place(claimAll.button, 1, 2)
claimAll.label.TextXAlignment = Enum.TextXAlignment.Center
local buyVet = UiKit.action(detail, "", "robux", function()
	Bus.fire("passe_buy", "season")
end, { h = BTN_H })
place(buyVet.button, 2, 1)
buyVet.label.TextXAlignment = Enum.TextXAlignment.Center
buyVet.label.TextSize = UiKit.text(px(16, 22))
local skip = UiKit.action(detail, "", "robux", function()
	Bus.fire("passe_buy", "skip")
end, { h = BTN_H })
place(skip.button, 2, 2)
skip.label.TextXAlignment = Enum.TextXAlignment.Center

-- pé: dicas do controle e do teclado
local foot = UiKit.chips(panel, px(30, 44), false, px(14, 22))
foot.frame.AnchorPoint = Vector2.new(0, 1)
foot.frame.Position = UDim2.new(0, PAD, 1, -px(8, 10))
foot.frame.Size = UDim2.new(1, -2 * PAD, 0, px(30, 44))

-- ===== estado =====
type Reward = { kind: string?, id: string?, name: string?, amount: number? }
local sample: { [string]: any }? = nil -- gancho do Studio sem passe do servidor
local function season(): { [string]: any }?
	local s = CampanhaCliente.get()
	local se = s and s.season
	if type(se) == "table" then
		return se
	end
	return sample
end
-- tabelas com chave de nível: pelo remote, uma lista esparsa pode chegar com a chave em texto
local function at(t: any, lvl: number): any
	if type(t) ~= "table" then
		return nil
	end
	local v = t[lvl]
	if v == nil then
		v = t[tostring(lvl)]
	end
	return v
end

local KIND_NAME: { [string]: string } = {
	credits = "Créditos",
	emblem = "Emblema",
	camo = "Camuflagem",
	title = "Título",
	uniform = "Uniforme",
	killcard = "Cartão de abate",
	gesture = "Gesto",
	music = "Música",
	boost = "Reforço",
	stars = "Estrelas",
}
local KIND_MARK: { [string]: { text: string, color: Color3 } } = {
	credits = { text = "$", color = V.KHAKI },
	emblem = { text = "★", color = V.BRASS },
	camo = { text = "C", color = V.OLIVE_HI },
	title = { text = "T", color = V.TEXT },
	uniform = { text = "U", color = V.KHAKI },
	killcard = { text = "K", color = V.RED_HI },
	gesture = { text = "G", color = V.TEXT },
	music = { text = "♪", color = V.TEXT },
	boost = { text = "×2", color = V.BRASS },
	stars = { text = "★", color = V.BRASS },
}
local function rewardName(r: Reward?): string
	if not r then
		return "—"
	end
	if r.kind == "credits" and type(r.amount) == "number" then
		return Progression.money(r.amount)
	end
	if type(r.name) == "string" and r.name ~= "" then
		return r.name
	end
	return KIND_NAME[r.kind or ""] or "Item"
end

-- passes e produtos do passe no Commerce (ID 0: ainda não criados no Roblox)
local function storeKey(cat: string): (string?, number, Enum.InfoType)
	local function match(key: string, kind: string?): boolean
		local k = string.upper(key)
		local g = string.lower(kind or "")
		if cat == "season" then
			return string.find(k, "SEASON", 1, true) ~= nil
				or string.find(k, "TEMPORADA", 1, true) ~= nil
				or g == "season"
		end
		return string.find(k, "SKIP", 1, true) ~= nil
			or string.find(k, "LEVEL", 1, true) ~= nil
			or string.find(k, "NIVEL", 1, true) ~= nil
			or string.find(g, "level", 1, true) ~= nil
	end
	-- o passe e o pular nível moram nas listas da campanha (Commerce.CampaignPasses / Products);
	-- passes só valem para "season" e produtos só para "skip" (PRODUCT_SEASON_SKIP tem SEASON no nome)
	local C = Commerce :: any
	for _, lst in { C.CampaignPasses or {}, Commerce.Passes } :: { { any } } do
		for _, p in lst do
			if cat == "season" and match(p.key, p.kind) then
				return p.key, tonumber((Commerce.IDS :: any)[p.key]) or 0, Enum.InfoType.GamePass
			end
		end
	end
	for _, lst in { C.CampaignProducts or {}, Commerce.Products } :: { { any } } do
		for _, p in lst do
			if cat ~= "season" and match(p.key, p.grants) then
				return p.key, tonumber((Commerce.IDS :: any)[p.key]) or 0, Enum.InfoType.Product
			end
		end
	end
	return nil, 0, Enum.InfoType.Product
end
local priceCache: { [string]: string } = {}
local function livePrice(id: number, infoType: Enum.InfoType, onDone: (string) -> ())
	local key = tostring(infoType) .. id
	if priceCache[key] then
		onDone(priceCache[key])
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType)
		end)
		local p = if ok and info and info.PriceInRobux then string.format("R$ %d", info.PriceInRobux) else "—"
		priceCache[key] = p
		onDone(p)
	end)
end
Bus.on("passe_buy", function(cat: string)
	local key, id, infoType = storeKey(cat)
	if not key or id == 0 then
		return
	end
	Net.event("Commerce_Track"):FireServer("prompt", key)
	if infoType == Enum.InfoType.GamePass then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
end)

-- ===== as colunas (montadas uma vez) =====
type Cell = {
	button: TextButton,
	icon: Frame,
	mark: TextLabel,
	name: TextLabel,
	sub: TextLabel,
	tag: TextLabel,
	edge: UIStroke,
	base: Color3,
	realce: UiKit.Realce,
}
type Col = { frame: Frame, node: Frame, nodeText: TextLabel, nodeEdge: UIStroke, free: Cell, vet: Cell }
local cols: { Col } = {}
local built = false
local sel = { level = 1, track = "free" }

local function cellState(se: { [string]: any }, track: string, lvl: number): string
	local level = tonumber(se.level) or 0
	local claimed = at(se.claimed and se.claimed[track], lvl) == true
	if claimed then
		return "claimed"
	elseif track == "vet" and not se.veteran then
		return "locked"
	elseif lvl <= level then
		return "ready"
	end
	return "future"
end

-- O CanvasPosition anda em pixels de tela (com a escala do painel, UiKit.fit): no Studio ele parou em
-- 3.985 = 4.545 (AbsoluteCanvasSize) − 559 (AbsoluteWindowSize). As colunas são postas em pixels do
-- desenho (colX); k converte uma coisa na outra.
local function k(): number
	local o = list.CanvasSize.X.Offset
	return if o > 0 then list.AbsoluteCanvasSize.X / o else 1
end
local function maxScroll(): number
	return math.max(0, list.AbsoluteCanvasSize.X - list.AbsoluteWindowSize.X)
end

-- rola a linha até o nível (no meio da vista)
local function scrollTo(lvl: number, instant: boolean?)
	local x = (colX(lvl) + COL_W / 2) * k() - list.AbsoluteWindowSize.X / 2
	local target = Vector2.new(math.clamp(x, 0, maxScroll()), 0)
	if instant then
		list.CanvasPosition = target
	else
		TweenService:Create(list, UiKit.SOFT, { CanvasPosition = target }):Play()
	end
end
scrollBy = function(n: number)
	local x = math.clamp(list.CanvasPosition.X + n * (COL_W + COL_GAP) * k(), 0, maxScroll())
	TweenService:Create(list, UiKit.SOFT, { CanvasPosition = Vector2.new(x, 0) }):Play()
end
local paint: () -> () = function() end
local function choose(lvl: number, track: string, focus: boolean?)
	sel.level = math.clamp(lvl, 1, MAX)
	sel.track = track
	paint()
	if focus and built then
		scrollTo(sel.level)
		if Input.isGamepad() then
			local c = cols[sel.level]
			GuiService.SelectedObject = if track == "vet" then c.vet.button else c.free.button
		end
	end
end

local function claimSelected()
	local se = season()
	if not se then
		return
	end
	if cellState(se, sel.track, sel.level) == "ready" then
		CampanhaCliente.action("claim_level", { track = sel.track, level = sel.level })
	elseif cellState(se, sel.track, sel.level) == "locked" then
		Bus.fire("passe_buy", "season")
	end
end
Bus.on("passe_claim_selected", claimSelected)

local cellTap = ToqueTelas.newTap2() -- toque: 1º toque mostra, 2º resgata
local function makeCell(parent: Instance, y: number, lvl: number, track: string): Cell
	local base = if track == "vet" then VET_BG else V.PANEL_2
	local b = Instance.new("TextButton")
	b.Name = track
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = base
	b.BorderSizePixel = 0
	b.Position = UDim2.fromOffset(0, y)
	b.Size = UDim2.fromOffset(COL_W, CARD_H)
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.ZIndex = 2
	b.Parent = parent
	UiKit.corner(b, 4)
	local edge = UiKit.edge(b, V.LINE, 1, 0.55)
	-- o ícone: quadrado com a cor do tipo de recompensa e a luz caindo de cima
	local IC = px(46, 62)
	local icon = Instance.new("Frame")
	icon.Name = "Icone"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, px(10, 14))
	icon.Size = UDim2.fromOffset(IC, IC)
	icon.BackgroundColor3 = V.PANEL_3
	icon.BorderSizePixel = 0
	icon.ZIndex = 2
	icon.Parent = b
	UiKit.corner(icon, IC // 2)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.62, 0.62, 0.62))
	g.Parent = icon
	local mark = UiKit.text2(icon, "", px(22, 30), V.KHAKI, F.TITLE)
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	mark.ZIndex = 2
	local ny = px(10, 14) + IC + px(6, 8)
	local name = UiKit.text2(b, "", px(13, 18), V.TEXT, F.BODY_B)
	name.Position = UDim2.fromOffset(px(6, 8), ny)
	name.Size = UDim2.new(1, -px(12, 16), 0, px(32, 44))
	name.TextWrapped = true
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 2
	local sub = UiKit.kicker(b, "", px(11, 15))
	sub.Position = UDim2.fromOffset(px(6, 8), CARD_H - px(20, 26))
	sub.Size = UDim2.new(1, -px(12, 16), 0, px(16, 22))
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.ZIndex = 2
	local tag = UiKit.tag(b, "", V.OLIVE, px(11, 15))
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, -px(5, 7), 0, px(5, 7))
	tag.ZIndex = 3
	local r = UiKit.realce(b, base, if track == "vet" then VET_BG_HI else V.PANEL_3, 1.03)
	local function hover(on: boolean)
		r.set(on)
		if on then
			choose(lvl, track)
		end
	end
	b.MouseEnter:Connect(function()
		hover(true)
	end)
	b.MouseLeave:Connect(function()
		r.set(false)
	end)
	b.SelectionGained:Connect(function()
		hover(true)
		scrollTo(lvl) -- o direcional anda pela linha e ela acompanha
	end)
	b.SelectionLost:Connect(function()
		r.set(false)
	end)
	UiKit.bind(b, function()
		choose(lvl, track)
		-- toque (Parte 13): sem "passar o mouse", o 1º toque só mostra a recompensa; o 2º na mesma
		-- célula resgata (ou abre a compra do Veterano). Antes, ver já resgatava ou abria a compra.
		if ToqueUi.active() and not ToqueTelas.secondTap(cellTap, string.format("%s:%d", track, lvl), os.clock()) then
			return
		end
		claimSelected()
	end, hover)
	return {
		button = b,
		icon = icon,
		mark = mark,
		name = name,
		sub = sub,
		tag = tag,
		edge = edge,
		base = base,
		realce = r,
	}
end

local function build()
	if built then
		return
	end
	built = true
	for lvl = 1, MAX do
		local f = Instance.new("Frame")
		f.Name = string.format("Nivel%02d", lvl)
		f.BackgroundTransparency = 1
		f.Position = UDim2.fromOffset(colX(lvl), 0)
		f.Size = UDim2.fromOffset(COL_W, INNER_H)
		f.Parent = list
		-- traços do cartão ao marco
		for _, y in { TOP_Y + CARD_H, NODE_Y + NODE_D // 2 } do
			local t = Instance.new("Frame")
			t.BackgroundColor3 = V.LINE
			t.BorderSizePixel = 0
			t.AnchorPoint = Vector2.new(0.5, 0)
			t.Position = UDim2.fromOffset(COL_W // 2, y)
			t.Size = UDim2.fromOffset(2, (NODE_ROW - NODE_D) // 2)
			t.Parent = f
		end
		-- o marco: de 10 em 10, maior e com contorno grosso
		local big = lvl % 10 == 0
		local d = if big then NODE_D + px(8, 10) else NODE_D
		local node = Instance.new("Frame")
		node.Name = "Marco"
		node.AnchorPoint = Vector2.new(0.5, 0.5)
		node.Position = UDim2.fromOffset(COL_W // 2, NODE_Y)
		node.Size = UDim2.fromOffset(d, d)
		node.BackgroundColor3 = V.PANEL
		node.BorderSizePixel = 0
		node.ZIndex = 3
		node.Parent = f
		UiKit.corner(node, d // 2)
		local nodeEdge = UiKit.edge(node, V.LINE, if big then 3 else 2, 0)
		local nt = UiKit.text2(node, tostring(lvl), if big then px(16, 22) else px(14, 19), V.DIM, F.TITLE)
		nt.Size = UDim2.fromScale(1, 1)
		nt.TextXAlignment = Enum.TextXAlignment.Center
		nt.ZIndex = 3
		cols[lvl] = {
			frame = f,
			node = node,
			nodeText = nt,
			nodeEdge = nodeEdge,
			vet = makeCell(f, TOP_Y, lvl, "vet"),
			free = makeCell(f, FREE_Y, lvl, "free"),
		}
	end
end

local STATE_TAG: { [string]: { text: string, color: Color3 } } = {
	ready = { text = "RECEBER", color = V.OLIVE },
	claimed = { text = "✔", color = V.PANEL_3 },
	locked = { text = "VETERANO", color = Color3.fromRGB(120, 96, 40) },
}
local function paintCell(c: Cell, se: { [string]: any }, track: string, lvl: number)
	local r: Reward? = at(if track == "vet" then se.vet else se.free, lvl)
	local st = cellState(se, track, lvl)
	local km = KIND_MARK[(r and r.kind) or ""]
	c.mark.Text = if r then (if km then km.text else "★") else ""
	c.mark.TextColor3 = if km then km.color else V.KHAKI
	c.icon.BackgroundColor3 = if km then km.color:Lerp(V.PANEL, 0.72) else V.PANEL_3
	c.name.Text = if r then rewardName(r) else "—"
	c.sub.Text = if r then UiKit.upper(KIND_NAME[r.kind or ""] or "Item") else ""
	local tg = STATE_TAG[st]
	c.tag.Visible = tg ~= nil and r ~= nil
	if tg then
		c.tag.Text = tg.text
		c.tag.BackgroundColor3 = tg.color
	end
	local dimmed = st == "future" or st == "locked" or st == "claimed"
	c.name.TextColor3 = if dimmed then V.DIM else V.TEXT
	c.mark.TextTransparency = if st == "future" or st == "locked" then 0.45 else 0
	c.icon.BackgroundTransparency = if st == "claimed" then 0.5 else 0
	local on = sel.level == lvl and sel.track == track
	-- o Veterano com o filete de latão: a trilha paga se distingue de longe
	c.edge.Color = if on then V.BRASS elseif st == "ready" then V.OLIVE_HI elseif track == "vet" then V.BRASS else V.LINE
	c.edge.Thickness = if on then 2 else 1
	c.edge.Transparency = if on or st == "ready" then 0 elseif track == "vet" then 0.6 else 0.55
end

local pulse: Tween? = nil
paint = function()
	local se = season()
	if not se then
		title.Text = "PASSE DE CAMPANHA"
		ends.Text = "Recebendo o passe do servidor…"
		return
	end
	local level = tonumber(se.level) or 0
	local per = math.max(1, tonumber(se.starsPerLevel) or 1)
	local inLvl = tonumber(se.starsInLevel) or 0
	title.Text = UiKit.upper(tostring(se.name or "Passe de campanha"))
	title.FontFace = UiKit.headFont(title.Text)
	levelStat.value.Text = string.format("%d/%d", level, tonumber(se.maxLevel) or MAX)
	starsLabel.Text = if level >= MAX then "NÍVEL MÁXIMO" else string.format("%d/%d ★ PARA O PRÓXIMO", inLvl, per)
	starsFill.Size = UDim2.fromScale(if level >= MAX then 1 else math.clamp(inLvl / per, 0, 1), 1)
	local left = if type(se.endsAt) == "number" then CampanhaCliente.left(se.endsAt) else 0
	ends.Text = if left > 0
		then string.format("A temporada termina em %d dias.", math.max(1, math.floor(left / 86400)))
		else ""
	vetSub.Text = if se.veteran then "LIBERADO" else "COM O VETERANO"
	-- o trecho andado: até o marco do nível atual, mais a fração das estrelas até o próximo
	local frac = if level >= MAX then 0 else math.clamp(inLvl / per, 0, 1)
	local upTo = if level <= 0 then 0 else colX(math.min(level, MAX)) - colX(1) + frac * (COL_W + COL_GAP)
	walked.Size = UDim2.fromOffset(math.max(0, math.floor(math.min(upTo, colX(MAX) - colX(1)))), LINE_H)
	if built then
		for lvl, c in cols do
			paintCell(c.free, se, "free", lvl)
			paintCell(c.vet, se, "vet", lvl)
			local here = lvl == level
			local done = lvl <= level
			c.node.BackgroundColor3 = if here then V.BRASS elseif done then Color3.fromRGB(96, 80, 40) else V.PANEL
			c.nodeEdge.Color = if done then V.BRASS elseif lvl % 10 == 0 then V.KHAKI else V.LINE
			c.nodeText.TextColor3 = if here then V.BG elseif done then V.TEXT else V.DIM
		end
		-- o marco atual pulsa (um só tween, no contorno)
		local cur = cols[math.clamp(level, 1, MAX)]
		if pulse then
			pulse:Cancel()
			pulse = nil
		end
		if level >= 1 and cur then
			for _, c in cols do
				c.nodeEdge.Transparency = 0
			end
			local t = TweenService:Create(
				cur.nodeEdge,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.75 }
			)
			t:Play()
			pulse = t
		end
	end
	-- ficha do escolhido
	local rw: Reward? = at(if sel.track == "vet" then se.vet else se.free, sel.level)
	local km = KIND_MARK[(rw and rw.kind) or ""]
	prevMark.Text = if km then km.text else "★"
	prevMark.TextColor3 = if km then km.color else V.BRASS
	local tint = if km then km.color else V.BRASS
	prevThumb.BackgroundColor3 = tint:Lerp(V.PANEL, 0.7)
	prevGlow.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.6, 0.6, 0.6))
	prevKind.Text = UiKit.upper(KIND_NAME[(rw and rw.kind) or ""] or "Item")
	prevKind.TextColor3 = if sel.track == "vet" then V.BRASS else V.OLIVE_HI
	prevName.Text = UiKit.upper(rewardName(rw))
	prevName.FontFace = UiKit.headFont(prevName.Text)
	local st = cellState(se, sel.track, sel.level)
	local why = if st == "claimed"
		then "Já é seu."
		elseif st == "ready" then "Pronto para receber."
		elseif st == "locked" then "Precisa do Veterano."
		else string.format("Chegue ao nível %d para receber.", sel.level)
	prevInfo.Text = string.format(
		"%s %s",
		if sel.track == "vet"
			then string.format("Nível %d · trilha Veterano.", sel.level)
			else string.format("Nível %d · trilha grátis.", sel.level),
		why
	)
	claimOne.button.Visible = st == "ready" or (st == "locked" and not se.veteran)
	claimOne.label.Text = if st == "locked" then "LIBERAR O VETERANO" else "RECEBER"
	claimOne.setKind(if st == "locked" then "robux" else "free") -- liberar é a compra do Veterano
	-- receber tudo: só se há algo para receber
	local any = false
	for lvl = 1, math.min(level, MAX) do
		if cellState(se, "free", lvl) == "ready" or cellState(se, "vet", lvl) == "ready" then
			any = true
			break
		end
	end
	claimAll.enabled(any)
	-- Veterano e pular nível (preço ao vivo; ID 0 = ainda não criado no Roblox)
	local vKey, vId, vType = storeKey("season")
	buyVet.button.Visible = not se.veteran
	if vKey and vId ~= 0 then
		buyVet.enabled(true)
		livePrice(vId, vType, function(p: string)
			buyVet.label.Text = string.format("VETERANO · %s", p)
		end)
	else
		buyVet.enabled(false)
		buyVet.label.Text = "VETERANO · EM BREVE"
	end
	local sKey, sId, sType = storeKey("skip")
	skip.button.Visible = level < MAX
	if sKey and sId ~= 0 then
		skip.enabled(true)
		livePrice(sId, sType, function(p: string)
			skip.label.Text = string.format("PULAR NÍVEL · %s", p)
		end)
	else
		skip.enabled(false)
		skip.label.Text = "PULAR NÍVEL · EM BREVE"
	end
end

local function renderFoot()
	foot.clear()
	if Input.device() == "gamepad" then
		foot.pair("ui_tab_prev", "ui_tab_next", "menu", "10 níveis")
		foot.pair("ui_sub_prev", "ui_sub_next", "menu", "Trilha")
		foot.add(UiKit.padImage(Enum.KeyCode.ButtonA), nil, "A", "Receber")
		foot.action("ui_back", "menu", "Fechar")
	elseif Input.device() == "touch" or ToqueUi.active() then
		foot.add(nil, nil, "Arraste", "para os lados")
		foot.add(nil, nil, "Toque", "no nível para ver")
		foot.add(nil, nil, "2×", "para receber")
	else
		foot.add(nil, nil, "Roda", "anda na linha")
		foot.add(nil, nil, "Clique", "no nível")
		foot.action("ui_back", "menu", "Fechar")
	end
end

-- a roda do mouse anda na linha: o próprio Roblox rola de lado uma ScrollingFrame só em X (no Studio,
-- um passo da roda andava 100 px; com um código nosso junto, andava em dobro)
-- as setas somem nas pontas
local function arrows()
	local maxX = maxScroll()
	leftArrow.Visible = list.CanvasPosition.X > 2
	rightArrow.Visible = list.CanvasPosition.X < maxX - 2
end
list:GetPropertyChangedSignal("CanvasPosition"):Connect(arrows)
list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(arrows)

-- ===== abrir e fechar =====
local open = false
local token = 0
local function setOpen(on: boolean)
	if on == open then
		return
	end
	open = on
	token += 1
	local my = token
	if on then
		build()
		gui.Enabled = true
		UiKit.opened("passe", gui.DisplayOrder)
		Input.openMenu()
		local se = season()
		if not se then
			CampanhaCliente.refresh()
		end
		local level = if se then math.clamp(tonumber(se.level) or 1, 1, MAX) else 1
		sel.level, sel.track = level, "free"
		paint()
		renderFoot()
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
		panel.Position = UDim2.new(0.5, 0, 0.5, 24)
		TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) })
			:Play()
		fit.play(TweenInfo.new(0.3, Enum.EasingStyle.Quint), 1, 0.95)
		task.defer(function()
			scrollTo(level, true)
			choose(level, "free", true)
			arrows()
		end)
	else
		if pulse then
			pulse:Cancel()
			pulse = nil
		end
		Input.closeMenu()
		UiKit.closed("passe")
		UiKit.release(gui)
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		fit.play(info, 0.95)
		task.delay(0.19, function()
			if token == my then
				gui.Enabled = false
			end
		end)
	end
end

Bus.on("passe_open", function()
	setOpen(true)
end)
Bus.on("passe_close", function()
	setOpen(false)
end)
Input.on("ui_back", "press", function()
	if open and UiKit.backFor("passe") then
		setOpen(false)
	end
end)
-- LB/RB: 10 níveis; LT/RT: troca de trilha
for action, dir in { ui_tab_prev = -10, ui_tab_next = 10 } :: { [string]: number } do
	Input.on(action, "press", function()
		if open and UiKit.top() == "passe" then
			choose(sel.level + dir, sel.track, true)
		end
	end)
end
for _, action in { "ui_sub_prev", "ui_sub_next" } do
	Input.on(action, "press", function()
		if open and UiKit.top() == "passe" then
			choose(sel.level, if sel.track == "free" then "vet" else "free", true)
		end
	end)
end
Input.DeviceChanged:Connect(function()
	if open then
		renderFoot()
	end
end)

CampanhaCliente.Changed:Connect(function(_s: any, result: any)
	if open then
		paint()
	end
	if
		type(result) == "table"
		and (result.op == "claim_level" or result.op == "claim_all")
		and not result.ok
		and type(result.msg) == "string"
	then
		Bus.fire("toast", result.msg)
	end
end)
-- o Veterano comprado chega pelo servidor (Campanha_State); o preço some quando já é seu
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, _id: number, bought: boolean)
	if who == player and bought then
		CampanhaCliente.refresh()
	end
end)

-- os 50 níveis montados em segundo plano, logo depois de carregar (abrir só pinta)
task.delay(4, build)

-- ===== gancho de teste (só no Studio) =====
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "passe" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
		local s = CampanhaCliente.get()
		if not (s and type(s.season) == "table") then
			local kinds = { "credits", "emblem", "camo", "title", "stars" }
			local vkinds = { "uniform", "camo", "killcard", "gesture", "music", "credits" }
			local free, vet = {}, {}
			for lvl = 1, MAX do
				local k = kinds[(lvl - 1) % #kinds + 1]
				free[lvl] = {
					kind = k,
					name = if k == "credits" then nil else string.format("Exemplo %d", lvl),
					amount = 100 * lvl,
				}
				local vk = vkinds[(lvl - 1) % #vkinds + 1]
				vet[lvl] = {
					kind = vk,
					name = if vk == "credits" then nil else string.format("Exemplo %d", lvl),
					amount = 150 * lvl,
				}
			end
			sample = {
				id = "S1",
				name = "Operação Starlite: Temporada 1",
				level = 12,
				stars = 130,
				starsInLevel = 4,
				starsPerLevel = 10,
				maxLevel = MAX,
				veteran = false,
				endsAt = nil,
				claimed = { free = { [1] = true, [2] = true, [3] = true }, vet = {} },
				free = free,
				vet = vet,
			}
		end
		setOpen(true)
	end)
end
