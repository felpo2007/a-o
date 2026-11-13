--!strict
-- Cartão do jogador (placa de identificação) e a coluna da campanha no lobby (plano de volta diária,
-- 2026-11-12). A placa mostra o emblema, o título, o posto e 3 medalhas; a tela do cartão (Bus
-- "cartao_open") troca emblema, título e as 3 medalhas (op "card_set") e mostra a coleção de
-- medalhas com a condição de cada uma e as vantagens ativas com o número exato (transparência: a
-- vantagem paga aparece para ninguém achar que é trapaça).
-- NÃO aparece na tela de baixa como "quem te matou": a Parte 9.5 proíbe o nome de quem atirou.
-- Coluna do lobby (CartaoJogador.lobby): placa, vantagens ativas, XP dobrado do fim de semana,
-- atalhos de missões e passe e a oferta do Pacote de Recruta (só nas 3 primeiras partidas, discreta,
-- sem bloquear nada). Tudo do CampanhaCliente; os módulos Shared do servidor (Medalhas) são lidos se
-- existirem: sem eles a tela não quebra.
-- Studio: workspace:SetAttribute("VT65DevTela", "cartao") abre a tela do cartão (com exemplo).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local CampanhaCliente = require(script.Parent.CampanhaCliente)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local CartaoJogador = {}

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local px = UiKit.px

-- ===== dados =====
local rankName = "—"
task.spawn(function()
	Net.event("Progress_State").OnClientEvent:Connect(function(s: any)
		if type(s) == "table" and s.rankName ~= nil then
			rankName = tostring(s.rankName)
			Bus.fire("cartao_rank")
		end
	end)
end)

-- módulos puros do servidor (Shared/Medalhas, Shared/Vantagens): lidos se existirem
local mods: { [string]: any } = {}
local function shared(name: string): any
	if mods[name] ~= nil then
		return mods[name] or nil
	end
	local mod = ReplicatedStorage.Shared:FindFirstChild(name)
	local got: any = false
	if mod and mod:IsA("ModuleScript") then
		local ok, M = pcall(require, mod)
		if ok and type(M) == "table" then
			got = M
		end
	end
	mods[name] = got
	return got or nil
end
local function nameOf(id: string): string
	local M = shared("Medalhas")
	local names = M and M.NAMES
	return if type(names) == "table" and type(names[id]) == "string" then names[id] else id
end
local DEFAULT_EMBLEM, DEFAULT_TITLE = "emb_padrao", "tit_soldado"

-- medalhas: do Shared/Medalhas (LIST: id, name, desc); sem o módulo, vazio
export type Medal = { id: string, name: string, cond: string }
local medalCache: { Medal }? = nil
local function medals(): { Medal }
	if medalCache then
		return medalCache
	end
	local out: { Medal } = {}
	do
		local M = shared("Medalhas")
		if M then
			local list = (M :: any).LIST or (M :: any).list or (M :: any).DEFS or (M :: any).defs or (M :: any).ALL
			if type(list) == "table" then
				for k, d in list do
					if type(d) == "table" then
						local id = tostring(d.id or k)
						table.insert(out, {
							id = id,
							name = tostring(d.name or d.nome or id),
							cond = tostring(d.cond or d.condition or d.desc or d.text or ""),
						})
					end
				end
			end
		end
	end
	if #out > 0 then
		medalCache = out
	end
	return out
end
local function medalById(id: string): Medal?
	for _, m in medals() do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- emblemas e títulos que o jogador tem (ids "emb_*" e "tit_*"): os de todo mundo (Medalhas.BASE_OWNED),
-- os que o servidor mandar no cartão (card.owned, mapa ou lista) e os recebidos no passe
local function owned(s: any, kind: string): { { id: string, name: string } }
	local out: { { id: string, name: string } } = {}
	local seen: { [string]: boolean } = {}
	local prefix = if kind == "emblem" then "emb_" else "tit_"
	local function add(id: any, name: any)
		local k = tostring(id)
		if string.sub(k, 1, 4) ~= prefix or seen[k] then
			return
		end
		seen[k] = true
		table.insert(out, { id = k, name = if name ~= nil and tostring(name) ~= k then tostring(name) else nameOf(k) })
	end
	add(if kind == "emblem" then DEFAULT_EMBLEM else DEFAULT_TITLE, nil)
	local M = shared("Medalhas")
	if M and type(M.BASE_OWNED) == "table" then
		for id in M.BASE_OWNED do
			add(id, nil)
		end
	end
	local card = if type(s) == "table" then s.card else nil
	-- o servidor manda `owned` no alto do estado (contrato); card.owned fica de reserva
	local own = if type(s) == "table" and type(s.owned) == "table"
		then s.owned
		elseif type(card) == "table" then card.owned
		else nil
	if type(own) == "table" then
		for k, v in own do
			if type(k) == "string" then
				add(k, nil)
			elseif type(v) == "string" then
				add(v, nil)
			end
		end
	end
	local list = if type(card) == "table" then card[kind .. "s"] else nil
	if type(list) == "table" then
		for _, e in list do
			if type(e) == "table" then
				add(e.id, e.name)
			else
				add(e, nil)
			end
		end
	end
	local season = if type(s) == "table" then s.season else nil
	if type(season) == "table" and type(season.claimed) == "table" then
		for _, track in { "free", "vet" } do
			local got = season.claimed[track]
			local defs = season[track]
			if type(got) == "table" and type(defs) == "table" then
				for lvl, on in got do
					local r = defs[lvl] or defs[tonumber(lvl) or -1]
					if on and type(r) == "table" and r.kind == kind then
						add(r.id or r.name, r.name)
					end
				end
			end
		end
	end
	return out
end

-- vantagens ativas: rótulo e o número exato (multiplicador -> porcentagem; carregador e granada: +n)
local PERK_ORDER = { "speed", "health", "breath", "sway", "reload", "bandage", "bleed", "mags", "grenades", "mark" }
local PERK_NAME: { [string]: string } = {
	speed = "Velocidade",
	health = "Vida máxima",
	breath = "Fôlego na luneta",
	sway = "Balanço na luneta",
	reload = "Recarga",
	bandage = "Bandagem e torniquete",
	bleed = "Sangramento",
	mags = "Carregadores",
	grenades = "Granadas",
	mark = "Marca no inimigo",
}
function CartaoJogador.perkLines(perks: any): { { string } }
	local out: { { string } } = {}
	if type(perks) ~= "table" then
		return out
	end
	-- o rótulo e o número do Shared/Vantagens (o mesmo da loja), se existir
	local Vt = shared("Vantagens")
	for _, k in PERK_ORDER do
		local v = tonumber(perks[k])
		local def = Vt and type(Vt.KEYS) == "table" and Vt.KEYS[k]
		if v and def and type(Vt.display) == "function" then
			local neutral = if def.kind == "count" then v < 1 else math.abs(v - 1) < 0.005
			if not neutral then
				table.insert(out, { tostring(def.label), Vt.display(k, v) })
			end
		elseif v and PERK_NAME[k] then
			local value: string
			if k == "mags" or k == "grenades" then
				if v >= 1 then
					value = string.format("+%d", math.floor(v + 0.5))
				else
					value = ""
				end
			else
				local pct = math.floor((v - 1) * 100 + (if v >= 1 then 0.5 else -0.5))
				value = if pct > 0
					then string.format("+%d%%", pct)
					elseif pct < 0 then string.format("−%d%%", -pct)
					else ""
			end
			if value ~= "" then
				table.insert(out, { PERK_NAME[k], value })
			end
		end
	end
	return out
end

-- ===== placa =====
export type Placa = { frame: TextButton, paint: (s: any) -> () }
function CartaoJogador.placa(parent: Instance, w: number, h: number): Placa
	local f = Instance.new("TextButton")
	f.Name = "Placa"
	f.AutoButtonColor = false
	f.Text = ""
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = V.PANEL
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	f.Selectable = true
	f.SelectionImageObject = UiKit.FOCUS
	UiKit.corner(f, 4)
	UiKit.edge(f, V.KHAKI, 1, 0.55)
	f.Parent = parent
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, px(5, 7), 1, 0)
	bar.BackgroundColor3 = V.KHAKI
	bar.BorderSizePixel = 0
	bar.Parent = f
	local E = h - px(24, 32)
	local emblem = UiKit.text2(f, "★", math.floor(E * 0.5), V.KHAKI, F.TITLE)
	emblem.Position = UDim2.fromOffset(px(16, 22), px(12, 16))
	emblem.Size = UDim2.fromOffset(E, E)
	emblem.TextXAlignment = Enum.TextXAlignment.Center
	emblem.BackgroundColor3 = V.PANEL_3
	emblem.BackgroundTransparency = 0
	UiKit.corner(emblem, 4)
	UiKit.edge(emblem, V.LINE, 1, 0.3)
	local x = px(16, 22) + E + px(12, 16)
	local name = UiKit.title(f, "", px(20, 28), V.TEXT)
	name.Position = UDim2.fromOffset(x, px(10, 14))
	name.Size = UDim2.new(1, -x - px(10, 14), 0, px(26, 36))
	local sub = UiKit.kicker(f, "", px(13, 19))
	sub.Position = UDim2.fromOffset(x, px(36, 50))
	sub.Size = UDim2.new(1, -x - px(10, 14), 0, px(18, 26))
	-- as 3 medalhas numa linha "A · B · C" (o Lang traduz item a item)
	local medalLine = UiKit.text2(f, "", px(13, 19), V.KHAKI, F.TITLE_MED)
	medalLine.Position = UDim2.fromOffset(x, px(58, 80))
	medalLine.Size = UDim2.new(1, -x - px(10, 14), 0, px(26, 36))
	medalLine.TextTruncate = Enum.TextTruncate.AtEnd
	local r = UiKit.realce(f, V.PANEL, V.PANEL_2, 1.015)
	f.MouseEnter:Connect(function()
		r.set(true)
	end)
	f.MouseLeave:Connect(function()
		r.set(false)
	end)
	f.SelectionGained:Connect(function()
		r.set(true)
	end)
	f.SelectionLost:Connect(function()
		r.set(false)
	end)
	UiKit.bind(f, function()
		Bus.fire("cartao_open")
	end, r.set)
	local function paint(s: any)
		local card = if type(s) == "table" then s.card else nil
		local em = if type(card) == "table" and card.emblem then tostring(card.emblem) else DEFAULT_EMBLEM
		-- emblema: o desenho é a sigla do nome (sem imagem nova): até 2 letras (UTF-8 inteiro) do que
		-- vem depois de "Emblema: "; o padrão é a estrela
		local emName = string.gsub(nameOf(em), "^[^:]*:%s*", "")
		local cut = utf8.offset(emName, 3)
		emblem.Text = if em == DEFAULT_EMBLEM
			then "★"
			else UiKit.upper(if cut then string.sub(emName, 1, cut - 1) else emName)
		name.Text = UiKit.upper(player.DisplayName)
		name.FontFace = UiKit.headFont(player.DisplayName)
		-- "TÍTULO · POSTO" (o Lang traduz item a item)
		local title = if type(card) == "table"
				and type(card.title) == "string"
				and card.title ~= ""
			then card.title
			else DEFAULT_TITLE
		sub.Text = UiKit.upper(string.format("%s · %s", nameOf(title), rankName))
		local list = if type(card) == "table" and type(card.medals) == "table" then card.medals else {}
		local names = {}
		for i = 1, math.min(3, #list) do
			local id = tostring(list[i])
			local m = medalById(id)
			table.insert(names, if m then m.name else id)
		end
		medalLine.Text = if #names > 0 then table.concat(names, " · ") else "sem medalhas no cartão"
		medalLine.TextColor3 = if #names > 0 then V.KHAKI else V.MUTED
	end
	paint(CampanhaCliente.get())
	return { frame = f, paint = paint }
end

-- ===== coluna da campanha no lobby =====
export type Lobby = { frame: Frame, setVisible: (on: boolean) -> () }
function CartaoJogador.lobby(parent: Instance, x: number, y: number, w: number): Lobby
	local col = Instance.new("Frame")
	col.Name = "Campanha"
	col.BackgroundTransparency = 1
	col.Position = UDim2.fromOffset(x, y)
	col.Size = UDim2.fromOffset(w, 0)
	col.AutomaticSize = Enum.AutomaticSize.Y
	col.Visible = false
	col.Parent = parent
	UiKit.list(col, false, 8)
	local placa = CartaoJogador.placa(col, w, 104)
	placa.frame.LayoutOrder = 1
	-- XP dobrado de fim de semana (para todos)
	local weekend = UiKit.tag(col, "XP DOBRADO NO FIM DE SEMANA", V.KHAKI, 14)
	weekend.LayoutOrder = 2
	weekend.TextColor3 = V.BG
	weekend.Visible = false
	-- atalhos
	local missions = UiKit.action(col, "MISSÕES", "secondary", function()
		Bus.fire("missoes_open")
	end, { h = 44 })
	missions.button.LayoutOrder = 3
	local pass = UiKit.action(col, "PASSE DE CAMPANHA", "secondary", function()
		Bus.fire("passe_open")
	end, { h = 44 })
	pass.button.LayoutOrder = 4
	-- vantagens ativas
	local perksBox = UiKit.panel(col, V.PANEL, 0.12)
	perksBox.LayoutOrder = 5
	perksBox.Size = UDim2.fromOffset(w, 0)
	perksBox.AutomaticSize = Enum.AutomaticSize.Y
	UiKit.pad(perksBox, 12, 12, 8, 10)
	UiKit.list(perksBox, false, 2)
	local ph = UiKit.kicker(perksBox, "VANTAGENS ATIVAS", 13, V.KHAKI)
	ph.Size = UDim2.new(1, 0, 0, 18)
	ph.LayoutOrder = 0
	local perkRows: { { TextLabel } } = {}
	for i = 1, 10 do
		local r = Instance.new("Frame")
		r.BackgroundTransparency = 1
		r.Size = UDim2.new(1, 0, 0, 20)
		r.LayoutOrder = i
		r.Visible = false
		r.Parent = perksBox
		local l = UiKit.text2(r, "", 14, V.DIM, F.BODY)
		l.Size = UDim2.new(0.7, 0, 1, 0)
		local v = UiKit.text2(r, "", 15, V.TEXT, F.TITLE)
		v.AnchorPoint = Vector2.new(1, 0)
		v.Position = UDim2.fromScale(1, 0)
		v.Size = UDim2.new(0.3, 0, 1, 0)
		v.TextXAlignment = Enum.TextXAlignment.Right
		perkRows[i] = { l, v }
	end
	-- oferta do Pacote de Recruta (só nas 3 primeiras partidas): discreta, fecha no ×
	local offer = UiKit.panel(col, V.PANEL, 0.04)
	offer.LayoutOrder = 6
	offer.Size = UDim2.fromOffset(w, 128)
	offer.Visible = false
	do
		local band = Instance.new("Frame")
		band.Size = UDim2.new(1, 0, 0, 4)
		band.BackgroundColor3 = V.BRASS
		band.BorderSizePixel = 0
		band.Parent = offer
	end
	local ok = UiKit.kicker(offer, "OFERTA DE BOAS-VINDAS", 13, V.BRASS)
	ok.Position = UDim2.fromOffset(12, 10)
	ok.Size = UDim2.new(1, -48, 0, 18)
	local ot = UiKit.title(offer, "PACOTE DE RECRUTA", 22)
	ot.Position = UDim2.fromOffset(12, 28)
	ot.Size = UDim2.new(1, -24, 0, 28)
	local ob = UiKit.body(offer, "Uniforme, camuflagem, 3 dias de XP dobrado e 1.000 créditos.", 13)
	ob.Position = UDim2.fromOffset(12, 56)
	ob.Size = UDim2.new(1, -24, 0, 32)
	local see = UiKit.action(offer, "VER NA LOJA", "primary", function()
		Bus.fire("shop_open", "loja")
	end, { h = 30 })
	see.button.Position = UDim2.fromOffset(12, 90)
	see.button.Size = UDim2.new(1, -24, 0, 30)
	see.label.TextXAlignment = Enum.TextXAlignment.Center
	local dismissed = false
	local x0 = UiKit.action(offer, "×", "ghost", function()
		dismissed = true
		offer.Visible = false
	end, { h = 28 })
	x0.button.AnchorPoint = Vector2.new(1, 0)
	x0.button.Position = UDim2.new(1, -6, 0, 6)
	x0.button.Size = UDim2.fromOffset(28, 28)
	x0.label.TextXAlignment = Enum.TextXAlignment.Center

	local seenSent = false
	local visible = false
	local function paint(s: any)
		placa.paint(s)
		local m = if type(s) == "table" then s.missions else nil
		local done, total = 0, 0
		if type(m) == "table" and type(m.daily) == "table" then
			for _, it in m.daily do
				total += 1
				if type(it) == "table" and it.done then
					done += 1
				end
			end
		end
		missions.sub.Text = if total > 0 then string.format("%d/%d", done, total) else ""
		local season = if type(s) == "table" then s.season else nil
		pass.sub.Text = if type(season) == "table" and season.level
			then string.format("NÍVEL %d", tonumber(season.level) or 0)
			else ""
		local boosts = if type(s) == "table" then s.boosts else nil
		weekend.Visible = type(boosts) == "table" and boosts.weekend == true
		local lines = CartaoJogador.perkLines(if type(s) == "table" then s.perks else nil)
		perksBox.Visible = #lines > 0
		for i, r in perkRows do
			local ln = lines[i]
			local fr = r[1].Parent :: Frame
			fr.Visible = ln ~= nil
			if ln then
				r[1].Text = ln[1]
				r[2].Text = ln[2]
			end
		end
		local rec = if type(s) == "table" then s.recruit else nil
		local want = type(rec) == "table" and rec.offer == true and rec.owned ~= true and not dismissed
		offer.Visible = want
		if want and visible and not seenSent then
			seenSent = true -- uma vez por sessão no lobby: o servidor conta as partidas
			CampanhaCliente.action("recruit_seen")
		end
	end
	CampanhaCliente.Changed:Connect(function(s: any)
		paint(s)
	end)
	Bus.on("cartao_rank", function()
		placa.paint(CampanhaCliente.get())
	end)
	paint(CampanhaCliente.get())
	return {
		frame = col,
		setVisible = function(on: boolean)
			if on == visible then
				return
			end
			visible = on
			col.Visible = on
			if on then
				paint(CampanhaCliente.get())
				UiKit.enter({ placa.frame, missions.button, pass.button }, 10, 0.04)
			end
		end,
	}
end

-- ===== tela do cartão (editar e ver a coleção) =====
local W, H = px(900, 1200), px(600, 820)
local gui = UiKit.screen("VT65Cartao", 38)
gui.Enabled = false
gui.IgnoreGuiInset = true
local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Active = true
dim.Parent = gui
local sheet = UiKit.panel(gui, V.PANEL, 0.04)
sheet.AnchorPoint = Vector2.new(0.5, 0.5)
sheet.Position = UDim2.fromScale(0.5, 0.5)
sheet.Size = UDim2.fromOffset(W, H)
local fit = UiKit.fit(gui, sheet, W, H, 16)
local P = px(24, 32)
local LW = px(330, 440) -- coluna da esquerda: a placa e as vantagens

local kicker = UiKit.kicker(sheet, "PLACA DE IDENTIFICAÇÃO", 14)
kicker.Position = UDim2.fromOffset(P, px(16, 22))
kicker.Size = UDim2.fromOffset(LW, px(18, 26))
local title = UiKit.title(sheet, "CARTÃO DO JOGADOR", px(34, 46))
title.Position = UDim2.fromOffset(P, px(34, 48))
title.Size = UDim2.new(1, -2 * P, 0, px(44, 60))
local preview = CartaoJogador.placa(sheet, LW, px(104, 140))
preview.frame.Position = UDim2.fromOffset(P, px(92, 124))
preview.frame.Selectable = false
local perkHead = UiKit.kicker(sheet, "VANTAGENS ATIVAS", 14, V.KHAKI)
perkHead.Position = UDim2.fromOffset(P, px(210, 284))
perkHead.Size = UDim2.fromOffset(LW, px(20, 28))
local perkNone =
	UiKit.body(sheet, "Nenhuma vantagem comprada. O efeito vale para os dois lados e tem teto de 12%.", px(13, 19))
perkNone.Position = UDim2.fromOffset(P, px(234, 316))
perkNone.Size = UDim2.fromOffset(LW, px(40, 54))
local perkLabels: { { TextLabel } } = {}
for i = 1, 10 do
	local y = px(234, 316) + (i - 1) * px(24, 32)
	local l = UiKit.text2(sheet, "", px(14, 20), V.DIM, F.BODY)
	l.Position = UDim2.fromOffset(P, y)
	l.Size = UDim2.fromOffset(math.floor(LW * 0.7), px(22, 30))
	local v = UiKit.text2(sheet, "", px(16, 22), V.TEXT, F.TITLE)
	v.Position = UDim2.fromOffset(P + math.floor(LW * 0.7), y)
	v.Size = UDim2.fromOffset(math.floor(LW * 0.3), px(22, 30))
	v.TextXAlignment = Enum.TextXAlignment.Right
	perkLabels[i] = { l, v }
end

-- coluna da direita: emblema, título e medalhas
local RX = P + LW + px(24, 32)
local right = Instance.new("ScrollingFrame")
right.BackgroundTransparency = 1
right.BorderSizePixel = 0
right.Position = UDim2.fromOffset(RX, px(92, 124))
right.Size = UDim2.new(1, -RX - P, 1, -px(92, 124) - px(72, 98))
right.CanvasSize = UDim2.new()
right.AutomaticCanvasSize = Enum.AutomaticSize.Y
right.ScrollBarThickness = 4
right.ScrollingDirection = Enum.ScrollingDirection.Y
right.Selectable = false
right.Parent = sheet
UiKit.list(right, false, px(8, 10))

local pick = { emblem = DEFAULT_EMBLEM, title = DEFAULT_TITLE, medals = {} :: { string } }
local renderEdit: () -> () = function() end

local function sectionHead(text: string, order: number)
	local l = UiKit.title(right, text, px(18, 26), V.KHAKI)
	l.Size = UDim2.new(1, -8, 0, px(26, 36))
	l.LayoutOrder = order
end
local function chipRow(order: number): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = order
	row.Parent = right
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(px(120, 160), px(40, 54))
	g.CellPadding = UDim2.fromOffset(px(6, 8), px(6, 8))
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = row
	return row
end

sectionHead("EMBLEMA", 1)
local emblemRow = chipRow(2)
sectionHead("TÍTULO", 3)
local titleRow = chipRow(4)
sectionHead("MEDALHAS (ESCOLHA 3)", 5)
local medalGrid = Instance.new("Frame")
medalGrid.BackgroundTransparency = 1
medalGrid.Size = UDim2.new(1, -8, 0, 0)
medalGrid.AutomaticSize = Enum.AutomaticSize.Y
medalGrid.LayoutOrder = 6
medalGrid.Parent = right
do
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.new(0.5, -px(4, 6), 0, px(64, 88))
	g.CellPadding = UDim2.fromOffset(px(8, 10), px(8, 10))
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = medalGrid
end
local medalNone = UiKit.body(right, "As medalhas chegam com a próxima atualização do servidor.", px(14, 20))
medalNone.Size = UDim2.new(1, -8, 0, px(24, 32))
medalNone.LayoutOrder = 7

-- pools (criados sob demanda, reaproveitados)
local emblemBtns: { UiKit.Action } = {}
local titleBtns: { UiKit.Action } = {}
type MedalCard = { b: TextButton, name: TextLabel, cond: TextLabel, mark: TextLabel, id: string? }
local medalCards: { MedalCard } = {}
local emblemIds: { string } = {}
local titleIds: { string } = {}

local function chooseEmblem(i: number)
	local id = emblemIds[i]
	if id then
		pick.emblem = id
		renderEdit()
	end
end
local function chooseTitle(i: number)
	local id = titleIds[i]
	if id then
		pick.title = id
		renderEdit()
	end
end
local function toggleMedal(i: number)
	local c = medalCards[i]
	local id = c and c.id
	if not id then
		return
	end
	local at = table.find(pick.medals, id)
	if at then
		table.remove(pick.medals, at)
	elseif #pick.medals < 3 then
		table.insert(pick.medals, id)
	else
		Toast.show("O cartão leva 3 medalhas: tire uma antes", "alerta", { title = "Cartão" })
		return
	end
	renderEdit()
end

local function poolButton(pool: { UiKit.Action }, row: Frame, i: number, onPick: (number) -> ()): UiKit.Action
	local b = pool[i]
	if b then
		return b
	end
	local made = UiKit.action(row, "", "secondary", function()
		onPick(i)
	end, { h = px(40, 54) })
	made.button.LayoutOrder = i
	made.label.TextXAlignment = Enum.TextXAlignment.Center
	pool[i] = made
	return made
end

local function medalCard(i: number): MedalCard
	local c = medalCards[i]
	if c then
		return c
	end
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = V.PANEL_2
	b.BorderSizePixel = 0
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.LayoutOrder = i
	b.Parent = medalGrid
	UiKit.corner(b, 4)
	local edge = UiKit.edge(b, V.LINE, 1, 0.5)
	edge.Name = "Borda"
	local mark = UiKit.text2(b, "✦", px(22, 30), V.MUTED, F.TITLE)
	mark.Position = UDim2.fromOffset(px(8, 10), 0)
	mark.Size = UDim2.new(0, px(28, 38), 1, 0)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	local x = px(40, 54)
	local name = UiKit.text2(b, "", px(14, 20), V.TEXT, F.BODY_B)
	name.Position = UDim2.fromOffset(x, px(8, 10))
	name.Size = UDim2.new(1, -x - 8, 0, px(20, 28))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local cond = UiKit.body(b, "", px(12, 18))
	cond.Position = UDim2.fromOffset(x, px(28, 38))
	cond.Size = UDim2.new(1, -x - 8, 0, px(32, 44))
	cond.TextTruncate = Enum.TextTruncate.AtEnd
	local r = UiKit.realce(b, V.PANEL_2, V.PANEL_3, 1.02)
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
	UiKit.bind(b, function()
		toggleMedal(i)
	end, r.set)
	local made: MedalCard = { b = b, name = name, cond = cond, mark = mark, id = nil }
	medalCards[i] = made
	return made
end

local sample: any = nil
local function current(): any
	return sample or CampanhaCliente.get()
end

renderEdit = function()
	local s = current()
	-- prévia com o que está escolhido (antes de salvar)
	local view: { [string]: any } = if type(s) == "table" then table.clone(s) :: any else {}
	local oc: { [string]: any } = if type(view.card) == "table" then table.clone(view.card) :: any else {}
	oc.emblem, oc.title, oc.medals = pick.emblem, pick.title, pick.medals
	view.card = oc
	preview.paint(view)
	-- emblemas
	table.clear(emblemIds)
	for i, e in owned(s, "emblem") do
		emblemIds[i] = e.id
		local b = poolButton(emblemBtns, emblemRow, i, chooseEmblem)
		b.button.Visible = true
		b.label.Text = if e.id == DEFAULT_EMBLEM then "★" else UiKit.upper((string.gsub(e.name, "^[^:]*:%s*", "")))
		b.realce.base(if e.id == pick.emblem then V.OLIVE else V.PANEL)
	end
	for i = #emblemIds + 1, #emblemBtns do
		emblemBtns[i].button.Visible = false
	end
	-- títulos (ids "tit_*"): o de todo mundo e os ganhos
	table.clear(titleIds)
	for i, t in owned(s, "title") do
		titleIds[i] = t.id
		local b = poolButton(titleBtns, titleRow, i, chooseTitle)
		b.button.Visible = true
		b.label.Text = UiKit.upper(t.name)
		b.realce.base(if t.id == pick.title then V.OLIVE else V.PANEL)
	end
	for i = #titleIds + 1, #titleBtns do
		titleBtns[i].button.Visible = false
	end
	-- medalhas: a coleção, ganhas acesas e as outras com a condição
	local got: { [string]: boolean } = {}
	if type(s) == "table" and type(s.medals) == "table" then
		for _, m in s.medals do
			if type(m) == "table" and m.id then
				got[tostring(m.id)] = true
			elseif type(m) == "string" then
				got[m] = true
			end
		end
	end
	local defs = medals()
	medalNone.Visible = #defs == 0
	for i, d in defs do
		local c = medalCard(i)
		c.id = if got[d.id] then d.id else nil
		c.b.Visible = true
		c.name.Text = d.name
		c.cond.Text = d.cond
		local earned = got[d.id] == true
		local chosen = table.find(pick.medals, d.id) ~= nil
		c.mark.TextColor3 = if earned then V.KHAKI else V.MUTED
		c.name.TextColor3 = if earned then V.TEXT else V.DIM
		c.b.BackgroundTransparency = if earned then 0 else 0.4
		local edge = c.b:FindFirstChild("Borda") :: UIStroke?
		if edge then
			edge.Color = if chosen then V.OLIVE_HI else V.LINE
			edge.Thickness = if chosen then 2 else 1
			edge.Transparency = if chosen then 0 else 0.5
		end
	end
	for i = #defs + 1, #medalCards do
		medalCards[i].b.Visible = false
	end
	-- vantagens ativas
	local lines = CartaoJogador.perkLines(if type(s) == "table" then s.perks else nil)
	perkNone.Visible = #lines == 0
	for i, pair in perkLabels do
		local ln = lines[i]
		pair[1].Visible = ln ~= nil
		pair[2].Visible = ln ~= nil
		if ln then
			pair[1].Text = ln[1]
			pair[2].Text = ln[2]
		end
	end
end

local save = UiKit.action(sheet, "SALVAR O CARTÃO", "primary", function()
	CampanhaCliente.action("card_set", { emblem = pick.emblem, title = pick.title, medals = pick.medals })
end, { h = px(48, 66) })
save.button.AnchorPoint = Vector2.new(1, 1)
save.button.Position = UDim2.new(1, -P - px(170, 230), 1, -px(16, 22))
save.button.Size = UDim2.fromOffset(px(260, 350), px(48, 66))
save.label.TextXAlignment = Enum.TextXAlignment.Center
local closeB = UiKit.action(sheet, "FECHAR", "secondary", function()
	Bus.fire("cartao_close")
end, { action = "ui_back", ctx = "menu", h = px(48, 66) })
closeB.button.AnchorPoint = Vector2.new(1, 1)
closeB.button.Position = UDim2.new(1, -P, 1, -px(16, 22))
closeB.button.Size = UDim2.fromOffset(px(160, 220), px(48, 66))

local open = false
local token = 0
local function loadPick()
	local s = current()
	local card = if type(s) == "table" then s.card else nil
	pick.emblem = if type(card) == "table" and card.emblem then tostring(card.emblem) else DEFAULT_EMBLEM
	pick.title = if type(card) == "table"
			and type(card.title) == "string"
			and card.title ~= ""
		then card.title
		else DEFAULT_TITLE
	pick.medals = {}
	if type(card) == "table" and type(card.medals) == "table" then
		for _, id in card.medals do
			if #pick.medals < 3 then
				table.insert(pick.medals, tostring(id))
			end
		end
	end
end
local function setOpen(on: boolean)
	if on == open then
		return
	end
	open = on
	token += 1
	local my = token
	if on then
		gui.Enabled = true
		UiKit.opened("cartao", gui.DisplayOrder)
		Input.openMenu()
		if not current() then
			CampanhaCliente.refresh()
		end
		loadPick()
		renderEdit()
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
		sheet.Position = UDim2.new(0.5, 0, 0.5, px(24, 32))
		TweenService:Create(sheet, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) })
			:Play()
		fit.play(TweenInfo.new(0.3, Enum.EasingStyle.Quint), 1, 0.96)
		UiKit.focus(sheet)
	else
		UiKit.closed("cartao")
		UiKit.release(gui)
		Input.closeMenu()
		sample = nil
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		fit.play(info, 0.95)
		task.delay(0.18, function()
			if token == my then
				gui.Enabled = false
			end
		end)
	end
end

Bus.on("cartao_open", function()
	Bus.fire("menu_close_request")
	setOpen(true)
end)
Bus.on("cartao_close", function()
	setOpen(false)
end)
Input.on("ui_back", "press", function()
	if open and UiKit.backFor("cartao") then
		setOpen(false)
	end
end)
UiKit.watch(sheet, function()
	return open
end)
CampanhaCliente.Changed:Connect(function(_s: any, result: any)
	if not open or sample then
		return
	end
	if type(result) == "table" and result.op == "card_set" then
		if result.ok then
			Toast.show("Cartão salvo", "sucesso", { title = "Cartão" })
			loadPick()
		elseif type(result.msg) == "string" and result.msg ~= "" then
			Toast.show(result.msg, "erro", { title = "Cartão" })
		end
	end
	renderEdit()
end)
Bus.on("cartao_rank", function()
	if open then
		renderEdit()
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "cartao" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
		if not CampanhaCliente.get() then
			sample = {
				now = os.time(),
				card = { emblem = DEFAULT_EMBLEM, title = DEFAULT_TITLE, medals = {}, owned = { emb_top10 = true } },
				medals = { { id = "purple_heart", at = os.time() }, { id = "combat_action", at = os.time() } },
				perks = { speed = 1.06, health = 1.12, reload = 1.12, mags = 1 },
			}
		end
		if open then
			loadPick()
			renderEdit()
		else
			Bus.fire("cartao_open")
		end
	end)
end

return CartaoJogador
