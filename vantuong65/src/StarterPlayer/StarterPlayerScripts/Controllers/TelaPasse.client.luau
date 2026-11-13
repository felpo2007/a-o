--!strict
-- Passe de campanha (plano de volta diária, 2026-11-12: "Operação Starlite: Temporada 1", 50 níveis,
-- estrelas, trilha grátis e Veterano). Abre por Bus "passe_open" (loja → MERCADO, tela de baixa,
-- lobby). Estilo novo: painel escuro, o nível em número grande, a barra de estrelas, as duas trilhas
-- lado a lado (GRÁTIS | VETERANO, um nível por linha) e, à direita, a prévia do item escolhido com
-- o botão de receber; embaixo, receber tudo, comprar o Veterano e pular nível (Robux, Commerce.IDS).
-- Os 50 níveis são montados uma vez (em segundo plano, logo depois de carregar); abrir só pinta.
-- Controle: A escolhe (e recebe o que já pode), LB/RB andam 10 níveis, LT/RT trocam de trilha, B
-- fecha. O estado vem do servidor (CampanhaCliente); a tela nunca espera vazia.
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
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local px = UiKit.px
local MAX = 50

local W, H = px(1000, 1320), px(640, 860)
local PREV_W = px(300, 400)
local PAD = px(20, 28)
local HEAD_H = px(104, 138)
local FOOT_H = px(46, 64)
local ROW_H = px(62, 84)
local GAP = px(6, 8)
local LVL_W = px(58, 78)

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

-- cabeçalho das colunas
local listX = PAD
local listW = W - PREV_W - 3 * PAD
local colW = math.floor((listW - LVL_W - 2 * GAP) / 2)
do
	local y = HEAD_H
	local function colHead(text: string, x: number, color: Color3)
		local t = UiKit.kicker(panel, text, px(14, 20), color)
		t.Position = UDim2.fromOffset(x, y)
		t.Size = UDim2.fromOffset(colW, px(20, 28))
		t.TextXAlignment = Enum.TextXAlignment.Center
	end
	colHead("GRÁTIS", listX + LVL_W + GAP, V.TEXT)
	colHead("VETERANO", listX + LVL_W + 2 * GAP + colW, V.BRASS)
end
local LIST_Y = HEAD_H + px(24, 32)
local list = Instance.new("ScrollingFrame")
list.Name = "Niveis"
list.Position = UDim2.fromOffset(listX, LIST_Y)
list.Size = UDim2.fromOffset(listW, H - LIST_Y - FOOT_H - px(8, 10))
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = px(5, 7)
list.ScrollBarImageColor3 = V.LINE
list.CanvasSize = UDim2.fromOffset(0, MAX * (ROW_H + GAP))
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Selectable = false
list.Parent = panel

-- prévia à direita
local prev = UiKit.panel(panel, V.PANEL_2, 0)
prev.Name = "Previa"
prev.AnchorPoint = Vector2.new(1, 0)
prev.Position = UDim2.new(1, -PAD, 0, HEAD_H)
prev.Size = UDim2.fromOffset(PREV_W, H - HEAD_H - FOOT_H - px(8, 10))
local P = px(14, 18)
local prevThumb = Instance.new("Frame")
prevThumb.BackgroundColor3 = V.PANEL_3
prevThumb.BorderSizePixel = 0
prevThumb.Position = UDim2.fromOffset(P, P)
prevThumb.Size = UDim2.new(1, -2 * P, 0, px(120, 160))
prevThumb.Parent = prev
UiKit.corner(prevThumb, 3)
local prevMark = UiKit.text2(prevThumb, "★", px(56, 76), V.BRASS, F.TITLE)
prevMark.Size = UDim2.fromScale(1, 1)
prevMark.TextXAlignment = Enum.TextXAlignment.Center
local prevKind = UiKit.kicker(prev, "", px(13, 19))
prevKind.Position = UDim2.fromOffset(P, P + px(128, 170))
prevKind.Size = UDim2.new(1, -2 * P, 0, px(18, 26))
local prevName = UiKit.title(prev, "", px(24, 34))
prevName.Position = UDim2.fromOffset(P, P + px(146, 196))
prevName.Size = UDim2.new(1, -2 * P, 0, px(32, 44))
local prevInfo = UiKit.body(prev, "", px(14, 20), V.DIM)
prevInfo.Position = UDim2.fromOffset(P, P + px(180, 242))
prevInfo.Size = UDim2.new(1, -2 * P, 0, px(40, 56))
local claimOne = UiKit.action(prev, "RECEBER", "primary", function()
	Bus.fire("passe_claim_selected")
end, { h = px(48, 66) })
claimOne.button.Position = UDim2.fromOffset(P, P + px(224, 300))
claimOne.button.Size = UDim2.new(1, -2 * P, 0, px(48, 66))
claimOne.label.TextXAlignment = Enum.TextXAlignment.Center
-- embaixo: receber tudo, Veterano e pular nível
local claimAll = UiKit.action(prev, "RECEBER TUDO", "secondary", function()
	CampanhaCliente.action("claim_all")
end, { h = px(40, 56) })
claimAll.button.AnchorPoint = Vector2.new(0, 1)
claimAll.button.Position = UDim2.new(0, P, 1, -(P + 2 * px(46, 64)))
claimAll.button.Size = UDim2.new(1, -2 * P, 0, px(40, 56))
local buyVet = UiKit.action(prev, "", "primary", function()
	Bus.fire("passe_buy", "season")
end, { h = px(40, 56) })
buyVet.button.AnchorPoint = Vector2.new(0, 1)
buyVet.button.Position = UDim2.new(0, P, 1, -(P + px(46, 64)))
buyVet.button.Size = UDim2.new(1, -2 * P, 0, px(40, 56))
buyVet.label.TextXAlignment = Enum.TextXAlignment.Center
buyVet.label.TextSize = UiKit.text(px(16, 22))
local skip = UiKit.action(prev, "", "secondary", function()
	Bus.fire("passe_buy", "skip")
end, { h = px(40, 56) })
skip.button.AnchorPoint = Vector2.new(0, 1)
skip.button.Position = UDim2.new(0, P, 1, -P)
skip.button.Size = UDim2.new(1, -2 * P, 0, px(40, 56))

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
	for _, list in { C.CampaignPasses or {}, Commerce.Passes } :: { { any } } do
		for _, p in list do
			if cat == "season" and match(p.key, p.kind) then
				return p.key, tonumber((Commerce.IDS :: any)[p.key]) or 0, Enum.InfoType.GamePass
			end
		end
	end
	for _, list in { C.CampaignProducts or {}, Commerce.Products } :: { { any } } do
		for _, p in list do
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

-- ===== as linhas (montadas uma vez) =====
type Cell = { button: TextButton, mark: TextLabel, name: TextLabel, sub: TextLabel, tag: TextLabel, edge: UIStroke }
type Row = { frame: Frame, level: TextLabel, free: Cell, vet: Cell }
local rows: { Row } = {}
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

local paint: () -> () = function() end
local function choose(lvl: number, track: string, focus: boolean?)
	sel.level = math.clamp(lvl, 1, MAX)
	sel.track = track
	paint()
	if focus and Input.isGamepad() and built then
		local r = rows[sel.level]
		GuiService.SelectedObject = if track == "vet" then r.vet.button else r.free.button
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

local function makeCell(parent: Instance, x: number, lvl: number, track: string): Cell
	local b = Instance.new("TextButton")
	b.Name = track
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = V.PANEL_2
	b.BorderSizePixel = 0
	b.Position = UDim2.fromOffset(x, 0)
	b.Size = UDim2.fromOffset(colW, ROW_H)
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = parent
	UiKit.corner(b, 3)
	local edge = UiKit.edge(b, V.LINE, 1, 0.55)
	local M = px(40, 54)
	local mark = UiKit.text2(b, "", px(18, 26), V.KHAKI, F.TITLE)
	mark.BackgroundColor3 = V.PANEL_3
	mark.BackgroundTransparency = 0
	mark.Position = UDim2.fromOffset(px(8, 10), (ROW_H - M) // 2)
	mark.Size = UDim2.fromOffset(M, M)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	UiKit.corner(mark, 3)
	local x0 = px(8, 10) + M + px(8, 10)
	local name = UiKit.text2(b, "", px(14, 20), V.TEXT, F.BODY_B)
	name.Position = UDim2.fromOffset(x0, px(10, 14))
	name.Size = UDim2.new(1, -(x0 + px(84, 112)), 0, px(20, 28))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local sub = UiKit.kicker(b, "", px(12, 17))
	sub.Position = UDim2.fromOffset(x0, px(32, 44))
	sub.Size = UDim2.new(1, -(x0 + px(84, 112)), 0, px(18, 24))
	local tag = UiKit.tag(b, "", V.OLIVE, px(12, 17))
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.new(1, -px(8, 10), 0.5, 0)
	local r = UiKit.realce(b, V.PANEL_2, V.PANEL_3, 1.015)
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
	end)
	b.SelectionLost:Connect(function()
		r.set(false)
	end)
	UiKit.bind(b, function()
		choose(lvl, track)
		claimSelected()
	end, hover)
	return { button = b, mark = mark, name = name, sub = sub, tag = tag, edge = edge }
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
		f.Position = UDim2.fromOffset(0, (lvl - 1) * (ROW_H + GAP))
		f.Size = UDim2.new(1, -px(10, 14), 0, ROW_H)
		f.Parent = list
		local lv = UiKit.text2(f, tostring(lvl), px(24, 34), V.DIM, F.TITLE)
		lv.Size = UDim2.fromOffset(LVL_W, ROW_H)
		lv.TextXAlignment = Enum.TextXAlignment.Center
		rows[lvl] = {
			frame = f,
			level = lv,
			free = makeCell(f, LVL_W + GAP, lvl, "free"),
			vet = makeCell(f, LVL_W + 2 * GAP + colW, lvl, "vet"),
		}
	end
end

local STATE_TAG: { [string]: { text: string, color: Color3 } } = {
	ready = { text = "RECEBER", color = V.OLIVE },
	claimed = { text = "✔", color = V.PANEL_3 },
	locked = { text = "VETERANO", color = V.PANEL_3 },
}
local function paintCell(c: Cell, se: { [string]: any }, track: string, lvl: number)
	local r: Reward? = at(if track == "vet" then se.vet else se.free, lvl)
	local st = cellState(se, track, lvl)
	local km = KIND_MARK[(r and r.kind) or ""]
	c.mark.Text = if r then (if km then km.text else "★") else ""
	c.mark.TextColor3 = if km then km.color else V.KHAKI
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
	local on = sel.level == lvl and sel.track == track
	c.edge.Color = if on then V.BRASS elseif st == "ready" then V.OLIVE_HI else V.LINE
	c.edge.Transparency = if on or st == "ready" then 0 else 0.55
end

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
	if built then
		for lvl, r in rows do
			paintCell(r.free, se, "free", lvl)
			paintCell(r.vet, se, "vet", lvl)
			r.level.TextColor3 = if lvl == level then V.BRASS elseif lvl < level then V.TEXT else V.DIM
		end
	end
	-- prévia do escolhido
	local rw: Reward? = at(if sel.track == "vet" then se.vet else se.free, sel.level)
	local km = KIND_MARK[(rw and rw.kind) or ""]
	prevMark.Text = if km then km.text else "★"
	prevMark.TextColor3 = if km then km.color else V.BRASS
	prevKind.Text = UiKit.upper(KIND_NAME[(rw and rw.kind) or ""] or "Item")
	prevName.Text = UiKit.upper(rewardName(rw))
	prevName.FontFace = UiKit.headFont(prevName.Text)
	prevInfo.Text = if sel.track == "vet"
		then string.format("Nível %d · trilha Veterano", sel.level)
		else string.format("Nível %d · trilha grátis", sel.level)
	local st = cellState(se, sel.track, sel.level)
	claimOne.button.Visible = st == "ready" or (st == "locked" and not se.veteran)
	claimOne.label.Text = if st == "locked" then "LIBERAR O VETERANO" else "RECEBER"
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
	elseif Input.device() == "touch" then
		foot.add(nil, nil, "Toque", "no nível")
	else
		foot.add(nil, nil, "Clique", "no nível")
		foot.action("ui_back", "menu", "Fechar")
	end
end

-- rola a lista até o nível (no meio da vista)
local function scrollTo(lvl: number, instant: boolean?)
	local y = (lvl - 1) * (ROW_H + GAP) - (list.AbsoluteWindowSize.Y - ROW_H) / 2
	local maxY = math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y)
	local target = Vector2.new(0, math.clamp(y, 0, maxY))
	if instant then
		list.CanvasPosition = target
	else
		TweenService:Create(list, UiKit.SOFT, { CanvasPosition = target }):Play()
	end
end

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
		end)
	else
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
			scrollTo(sel.level)
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
