--!strict
-- HUD de campo (pedido do dono, 2026-11-11: "melhore ainda mais todas as interfaces"; a Parte 1 pede
-- HUD mínimo, "bússola e mapa de papel", sem contador de munição). Duas peças, as duas de época:
--   - BÚSSOLA (embaixo, ao centro): fita de rumo como a de uma bússola de lente, com marcas de 5°,
--     graus de 15 em 15, os pontos cardeais na língua escolhida (N L S O, N E S W, N E S O, B Đ N T),
--     a linha de fé em latão, o rumo em graus e o objetivo do time (▼ em latão, o mesmo da faixa da
--     frente; nunca inimigo). Some no menu, na carta, caído e morto;
--   - ARMA E POSTURA (embaixo, à direita, só a pé): nome da arma, seletor (SEMI/AUTO), alça de mira,
--     os carregadores de reserva como pentes (não há número de balas: o soldado sente o peso; o
--     carregador na arma aparece como "cheio / pela metade / no fim"), a recarga correndo e a
--     postura (de pé, agachado, deitado) em três barras. Fica nítido quando algo muda e esmaece em
--     5 s (HUD mínimo). Os avisos da arma (Toast com a chave "arma": seletor, alça, troca de arma,
--     baioneta) passam a sair aqui, não na pilha do alto.
-- Fontes de dados (nada do WeaponController muda): atributo local "EquippedWeapon", remote
-- Combat_Ammo, Bus "reload_start", atributos Prone/Crouched do personagem e Match_State.
-- Desempenho: tudo é criado uma vez. Por quadro, só a posição da fita (uma propriedade) e o texto
-- do rumo quando muda; o resto é tween ou evento. Escala para a janela (UIScale) e foge do cartão do
-- tutorial numa tela estreita.
-- Studio: workspace:SetAttribute("VT65DevTela", "hud") acende o cartão da arma.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Front = require(ReplicatedStorage.Shared.Front)
local Net = require(ReplicatedStorage.Shared.Net)
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local Marcadores = require(script.Parent.Marcadores) -- liga os marcadores de aliados e objetivos
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

local gui = UiKit.screen("VT65HudCampo", 13)
local holder = Instance.new("Frame")
holder.Name = "HUD"
holder.BackgroundTransparency = 1
holder.Size = UDim2.fromScale(1, 1)
holder.Parent = gui

-- ============================================================================================
-- bússola
-- ============================================================================================
local CW, CH = px(380, 560), px(54, 78)
local DEG_PX = CW / 110 -- ~110° à vista
local B: { [string]: any } = {}
do
	local box = Instance.new("Frame")
	box.Name = "Bussola"
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -px(16, 26))
	box.Size = UDim2.fromOffset(CW, CH)
	box.BackgroundTransparency = 1
	box.Visible = false
	box.Parent = holder
	local sc = Instance.new("UIScale")
	sc.Parent = box
	-- fundo oliva que some nas pontas (a fita "entra" pela borda)
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, px(34, 48))
	back.BackgroundColor3 = UiKit.CARD_DARK
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = box
	UiKit.corner(back, 3)
	local bg = Instance.new("UIGradient")
	bg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0),
		NumberSequenceKeypoint.new(0.82, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	bg.Parent = back
	-- a fita fica num CanvasGroup para esmaecer nas pontas
	local view = Instance.new("CanvasGroup")
	view.Size = UDim2.new(1, 0, 0, px(34, 48))
	view.BackgroundTransparency = 1
	view.Parent = box
	local fade = Instance.new("UIGradient")
	fade.Transparency = bg.Transparency
	fade.Parent = view
	local tape = Instance.new("Frame")
	tape.Name = "Fita"
	tape.BackgroundTransparency = 1
	tape.Size = UDim2.new(0, 720 * DEG_PX, 1, 0)
	tape.Parent = view
	local letters: { [number]: TextLabel } = {}
	for d = 0, 715, 5 do
		local a = d % 360
		local major = a % 45 == 0
		local mid = a % 15 == 0
		local t = Instance.new("Frame")
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.fromOffset(d * DEG_PX, 0)
		t.Size =
			UDim2.fromOffset(if major then 2 else 1, if major then px(12, 18) elseif mid then px(9, 13) else px(5, 8))
		t.BackgroundColor3 = UiKit.KHAKI
		t.BackgroundTransparency = if major then 0 elseif mid then 0.25 else 0.5
		t.BorderSizePixel = 0
		t.Parent = tape
		if mid then
			local l = UiKit.rotulo(
				tape,
				if major then 15 else 12,
				if a % 90 == 0 then UiKit.CARD else UiKit.KHAKI,
				UiKit.HEAD_FONT
			)
			l.AnchorPoint = Vector2.new(0.5, 0)
			l.Position = UDim2.fromOffset(d * DEG_PX, px(12, 18))
			l.Size = UDim2.fromOffset(px(40, 60), px(20, 28))
			l.TextXAlignment = Enum.TextXAlignment.Center
			l.Text = if major then "" else string.format("%d", a)
			if major then
				letters[d] = l
			end
		end
	end
	-- linha de fé (latão) e o rumo
	local lubber = Instance.new("Frame")
	lubber.AnchorPoint = Vector2.new(0.5, 0)
	lubber.Position = UDim2.fromScale(0.5, 0)
	lubber.Size = UDim2.new(0, 2, 0, px(34, 48))
	lubber.BackgroundColor3 = UiKit.BRASS
	lubber.BorderSizePixel = 0
	lubber.Parent = box
	local notch = Instance.new("Frame")
	notch.AnchorPoint = Vector2.new(0.5, 0.5)
	notch.Position = UDim2.fromScale(0.5, 0)
	notch.Size = UDim2.fromOffset(px(8, 12), px(8, 12))
	notch.Rotation = 45
	notch.BackgroundColor3 = UiKit.BRASS
	notch.BorderSizePixel = 0
	notch.Parent = box
	local tag = Instance.new("Frame")
	tag.AnchorPoint = Vector2.new(0.5, 1)
	tag.Position = UDim2.fromScale(0.5, 1)
	tag.Size = UDim2.fromOffset(px(58, 84), px(20, 30))
	tag.BackgroundColor3 = UiKit.CARD_DARK
	tag.BackgroundTransparency = 0.15
	tag.BorderSizePixel = 0
	tag.Parent = box
	UiKit.corner(tag, 3)
	UiKit.edge(tag, UiKit.BRASS, 1, 0.4)
	local deg = UiKit.rotulo(tag, 14, UiKit.BRASS_LIGHT, UiKit.HEAD_FONT)
	deg.Size = UDim2.fromScale(1, 1)
	deg.TextXAlignment = Enum.TextXAlignment.Center
	-- objetivo do time na fita (▼); fora da vista, seta na borda
	local goal = UiKit.rotulo(view, 14, UiKit.BRASS, Enum.Font.ArimoBold)
	goal.AnchorPoint = Vector2.new(0.5, 0)
	goal.Size = UDim2.fromOffset(px(20, 30), px(16, 22))
	goal.Position = UDim2.fromOffset(0, -2)
	goal.TextXAlignment = Enum.TextXAlignment.Center
	goal.Text = "▼"
	goal.Visible = false
	-- o squad na fita (pontos de latão; o líder maior; caído em vermelho)
	local dots: { Frame } = {}
	for i = 1, 8 do
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 1)
		d.Size = UDim2.fromOffset(px(6, 9), px(6, 9))
		d.Position = UDim2.new(0, 0, 1, -2)
		d.BackgroundColor3 = UiKit.BRASS_LIGHT
		d.BorderSizePixel = 0
		d.Visible = false
		d.Parent = view
		UiKit.corner(d, 99)
		dots[i] = d
	end
	B = { box = box, scale = sc, tape = tape, letters = letters, deg = deg, goal = goal, dots = dots }
end

-- pontos cardeais na língua escolhida (atributo "Lang" do Traducao.client)
local CARDINAL: { [string]: { string } } = {
	pt = { "N", "NE", "L", "SE", "S", "SO", "O", "NO" },
	es = { "N", "NE", "E", "SE", "S", "SO", "O", "NO" },
	en = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" },
	vi = { "B", "ĐB", "Đ", "ĐN", "N", "TN", "T", "TB" },
}
local function paintCardinals()
	local lang = player:GetAttribute("Lang")
	local set = CARDINAL[if type(lang) == "string" then lang else "pt"] or CARDINAL.pt
	for d, l in B.letters :: { [number]: TextLabel } do
		local s = set[(d % 360) // 45 + 1]
		l.Text = s
		l.FontFace = UiKit.headFont(s)
		l.TextColor3 = if (d % 360) % 90 == 0 then UiKit.CARD else UiKit.KHAKI
	end
end
player:GetAttributeChangedSignal("Lang"):Connect(paintCardinals)
paintCardinals()

-- ============================================================================================
-- arma e postura
-- ============================================================================================
-- D-93 (Studio: contraste baixo e letra miúda): cartão maior, fundo mais fechado, letras maiores
local AW, AH = px(290, 410), px(108, 152)
local A: { [string]: any } = {}
do
	local card = Instance.new("CanvasGroup")
	card.Name = "Arma"
	card.AnchorPoint = Vector2.new(1, 1)
	card.Position = UDim2.new(1, -px(18, 28), 1, -px(16, 26))
	card.Size = UDim2.fromOffset(AW, AH)
	card.BackgroundColor3 = UiKit.CARD_DARK
	card.BackgroundTransparency = 0.18
	card.BorderSizePixel = 0
	card.GroupTransparency = 1
	card.Visible = false
	card.Parent = holder
	UiKit.corner(card, 4)
	UiKit.edge(card, UiKit.KHAKI, 1, 0.72)
	local sc = Instance.new("UIScale")
	sc.Parent = card
	-- luz de cima num fundo próprio (um UIGradient no CanvasGroup escureceria o texto também)
	card.BackgroundTransparency = 1
	local cardBack = Instance.new("Frame")
	cardBack.Size = UDim2.fromScale(1, 1)
	cardBack.BackgroundColor3 = UiKit.CARD_DARK
	cardBack.BackgroundTransparency = 0.06
	cardBack.BorderSizePixel = 0
	cardBack.Parent = card
	UiKit.corner(cardBack, 4)
	UiKit.lit(cardBack, 0.7)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, px(4, 6), 1, 0)
	bar.BackgroundColor3 = UiKit.BRASS
	bar.BorderSizePixel = 0
	bar.Parent = card
	local P = px(12, 18)
	local name = UiKit.rotulo(card, 21, UiKit.CARD, UiKit.HEAD_FONT)
	name.Position = UDim2.fromOffset(P, px(6, 8))
	name.Size = UDim2.new(1, -P - px(54, 78), 0, px(26, 36))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	-- postura: três barras (de pé, agachado, deitado), a ativa em latão
	local stance = Instance.new("Frame")
	stance.AnchorPoint = Vector2.new(1, 0)
	stance.Position = UDim2.new(1, -P, 0, px(8, 10))
	stance.Size = UDim2.fromOffset(px(40, 58), px(24, 34))
	stance.BackgroundTransparency = 1
	stance.Parent = card
	local bars: { Frame } = {}
	for i, h in { 1, 0.66, 0.33 } do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.new((i - 1) / 3, 1, 1, 0)
		f.Size = UDim2.new(1 / 3, -3, h, 0)
		f.BackgroundColor3 = UiKit.KHAKI
		f.BackgroundTransparency = 0.6
		f.BorderSizePixel = 0
		f.Parent = stance
		bars[i] = f
	end
	local stanceText = UiKit.rotulo(card, 13, UiKit.CARD, UiKit.HEAD_REG)
	stanceText.AnchorPoint = Vector2.new(1, 0)
	stanceText.Position = UDim2.new(1, -P, 0, px(34, 46))
	stanceText.Size = UDim2.fromOffset(px(88, 130), px(18, 24))
	stanceText.TextTruncate = Enum.TextTruncate.AtEnd
	stanceText.TextXAlignment = Enum.TextXAlignment.Right
	-- seletor e alça em etiquetas
	local function pill(x: number, w: number): TextLabel
		local l = UiKit.rotulo(card, 15, UiKit.NIGHT, UiKit.HEAD_FONT)
		l.Position = UDim2.fromOffset(x, px(38, 54))
		l.Size = UDim2.fromOffset(w, px(22, 30))
		l.BackgroundColor3 = UiKit.KHAKI
		l.BackgroundTransparency = 0
		l.TextXAlignment = Enum.TextXAlignment.Center
		UiKit.corner(l, 3)
		return l
	end
	local mode = pill(P, px(62, 86))
	local zero = pill(P + px(68, 94), px(106, 146))
	zero.BackgroundColor3 = UiKit.DRAB
	zero.TextColor3 = UiKit.KHAKI
	-- carregadores: o da arma (barra de 4 pedaços) e os de reserva (pentes)
	local magBox = Instance.new("Frame")
	magBox.Position = UDim2.fromOffset(P, px(68, 96))
	magBox.Size = UDim2.fromOffset(px(11, 15), px(30, 42))
	magBox.BackgroundTransparency = 1
	magBox.Parent = card
	local cells: { Frame } = {}
	for i = 1, 4 do
		local c = Instance.new("Frame")
		c.Position = UDim2.new(0, 0, (4 - i) / 4, 1)
		c.Size = UDim2.new(1, 0, 1 / 4, -2)
		c.BackgroundColor3 = UiKit.BRASS
		c.BorderSizePixel = 0
		c.Parent = magBox
		cells[i] = c
	end
	local magText = UiKit.rotulo(card, 14, UiKit.CARD, UiKit.BODY_FONT)
	magText.Position = UDim2.fromOffset(P + px(18, 24), px(66, 92))
	magText.Size = UDim2.fromOffset(px(130, 180), px(18, 26))
	local spareRow = Instance.new("Frame")
	spareRow.Position = UDim2.fromOffset(P + px(18, 24), px(87, 122))
	spareRow.Size = UDim2.new(1, -P - px(32, 44), 0, px(12, 16))
	spareRow.BackgroundTransparency = 1
	spareRow.Parent = card
	local srl = Instance.new("UIListLayout")
	srl.FillDirection = Enum.FillDirection.Horizontal
	srl.Padding = UDim.new(0, 3)
	srl.Parent = spareRow
	local pips: { Frame } = {}
	for i = 1, 10 do
		local p = Instance.new("Frame")
		p.Size = UDim2.fromOffset(px(8, 11), px(12, 16))
		p.BackgroundColor3 = UiKit.KHAKI
		p.BorderSizePixel = 0
		p.LayoutOrder = i
		p.Visible = false
		p.Parent = spareRow
		UiKit.corner(p, 1)
		pips[i] = p
	end
	local more = UiKit.rotulo(spareRow, 13, UiKit.CARD, UiKit.HEAD_FONT)
	more.LayoutOrder = 99
	more.AutomaticSize = Enum.AutomaticSize.X
	more.Size = UDim2.fromOffset(0, px(12, 16))
	-- recarga: barra que corre embaixo; aviso curto da arma no alto à direita
	local reload = Instance.new("Frame")
	reload.AnchorPoint = Vector2.new(0, 1)
	reload.Position = UDim2.new(0, 0, 1, 0)
	reload.Size = UDim2.new(0, 0, 0, px(3, 4))
	reload.BackgroundColor3 = UiKit.BRASS_LIGHT
	reload.BorderSizePixel = 0
	reload.Parent = card
	local flash = UiKit.rotulo(card, 15, UiKit.BRASS_LIGHT, UiKit.HEAD_FONT)
	flash.AnchorPoint = Vector2.new(1, 0)
	flash.Position = UDim2.new(1, -P, 0, px(66, 92))
	flash.Size = UDim2.fromOffset(px(124, 176), px(18, 26))
	flash.TextXAlignment = Enum.TextXAlignment.Right
	flash.TextTransparency = 1
	A = {
		card = card,
		scale = sc,
		name = name,
		bars = bars,
		stanceText = stanceText,
		mode = mode,
		zero = zero,
		cells = cells,
		magText = magText,
		pips = pips,
		more = more,
		reload = reload,
		flash = flash,
	}
end

-- ===== estado da arma =====
local W = {
	id = nil :: string?,
	mode = "",
	zero = 100,
	mag = -1,
	spare = -1,
	lastActive = 0,
	bright = false,
}

local function weaponDef(): any
	return if W.id and W.id ~= "launcher" then Weapons.get(W.id) else nil
end

local function wake()
	W.lastActive = os.clock()
	if not W.bright then
		W.bright = true
		TweenService:Create(A.card, TweenInfo.new(0.18), { GroupTransparency = 0 }):Play()
	end
end

local function renderWeapon()
	local wp = weaponDef()
	A.name.Text = if W.id == "launcher" then "Lançador" elseif wp then wp.name else "—"
	A.mode.Text = UiKit.upper(W.mode ~= "" and W.mode or "—")
	A.mode.Visible = wp ~= nil
	A.zero.Text = string.format("Alça %d m", W.zero)
	A.zero.Visible = wp ~= nil and wp.kind ~= "launcher"
	local size = if wp and type(wp.magazine) == "number" then wp.magazine else 0
	-- carregador na arma em 4 níveis, sem número (Parte 1)
	local frac = if size > 0 and W.mag >= 0 then math.clamp(W.mag / size, 0, 1) else 0
	local lvl = if W.mag < 0 then 0 else math.ceil(frac * 4 - 1e-6)
	for i, c in A.cells :: { Frame } do
		c.BackgroundTransparency = if i <= lvl then 0 else 0.8
		c.BackgroundColor3 = if lvl <= 1 then UiKit.STAMP else UiKit.BRASS
	end
	A.magText.Text = if W.mag < 0
		then ""
		elseif frac >= 0.75 then "cheio"
		elseif frac >= 0.4 then "pela metade"
		elseif W.mag > 0 then "no fim"
		else "vazio"
	-- reservas: um pente por carregador cheio que sobra
	local spareMags = if size > 0 and W.spare >= 0 then math.ceil(W.spare / size - 1e-6) else 0
	for i, p in A.pips :: { Frame } do
		p.Visible = i <= math.min(spareMags, 10)
	end
	A.more.Text = if spareMags > 10 then string.format("+%d", spareMags - 10) else ""
end

local function renderStance()
	local c = player.Character
	local idx = if c and c:GetAttribute("Prone") then 3 elseif c and c:GetAttribute("Crouched") then 2 else 1
	for i, b in A.bars :: { Frame } do
		TweenService:Create(b, UiKit.QUICK, {
			BackgroundTransparency = if i == idx then 0 else 0.6,
			BackgroundColor3 = if i == idx then UiKit.BRASS else UiKit.KHAKI,
		}):Play()
	end
	A.stanceText.Text = if idx == 3 then "DEITADO" elseif idx == 2 then "AGACHADO" else "DE PÉ"
end

local function equip()
	local id = player:GetAttribute("EquippedWeapon")
	W.id = if type(id) == "string" then id else nil
	local wp = weaponDef()
	W.mode = if wp and wp.modes and wp.modes[1] then wp.modes[1] else ""
	renderWeapon()
	wake()
end
player:GetAttributeChangedSignal("EquippedWeapon"):Connect(equip)

Net.event("Combat_Ammo").OnClientEvent:Connect(function(a: any)
	if type(a) ~= "table" then
		return
	end
	local before = W.spare
	W.mag = tonumber(a.mag) or W.mag
	W.spare = if type(a.spare) == "number" then a.spare else W.spare
	renderWeapon()
	if W.spare ~= before then
		wake()
	end
end)

local reloadTween: Tween? = nil
Bus.on("reload_start", function(dur: number)
	local t = reloadTween
	if t then
		t:Cancel()
	end
	A.reload.Size = UDim2.new(0, 0, 0, px(3, 4))
	local tw = TweenService:Create(A.reload, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
		Size = UDim2.new(1, 0, 0, px(3, 4)),
	})
	tw.Completed:Once(function()
		A.reload.Size = UDim2.new(0, 0, 0, px(3, 4))
	end)
	reloadTween = tw
	tw:Play()
	wake()
end)

-- aviso curto no cartão (troca de arma, baioneta...)
local flashToken = 0
local function flash(text: string)
	flashToken += 1
	local my = flashToken
	A.flash.Text = text
	A.flash.TextTransparency = 0
	task.delay(2.2, function()
		if flashToken == my then
			TweenService:Create(A.flash, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

-- os avisos da arma (Toast "arma") viram estado do cartão quando ele está na tela
Toast.intercept("arma", function(text: string): boolean
	if not A.card.Visible then
		return false
	end
	local sel = string.match(text, "^Seletor: (.+)$")
	local zero = string.match(text, "^Alça de mira: (%d+) m$")
	if sel then
		W.mode = string.lower(sel)
	elseif zero then
		W.zero = tonumber(zero) or W.zero
	else
		flash(text)
	end
	renderWeapon()
	-- a etiqueta que mudou dá um pulo
	local target = if sel then A.mode elseif zero then A.zero else nil
	if target then
		local s = target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		s.Parent = target
		s.Scale = 1.25
		TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	wake()
	return true
end)

-- ===== objetivo do time (o mesmo da faixa da frente) =====
local goalPos: Vector3? = nil
Net.event("Match_State").OnClientEvent:Connect(function(st: any)
	goalPos = nil
	if type(st) ~= "table" or type(st.owner) ~= "table" or st.ended then
		return
	end
	local f = player:GetAttribute("Faction")
	if type(f) ~= "string" then
		return
	end
	local cap = {}
	if type(st.capturing) == "table" then
		for i, v in st.capturing do
			cap[i] = if v == "" then nil else v
		end
	end
	local _, target = Front.objective(st.owner, st.active, f, cap)
	local p = target and st.points and st.points[target]
	if p then
		goalPos = Vector3.new(p.x, 0, p.z)
	end
end)

-- ===== personagem =====
local charConns: { RBXScriptConnection } = {}
local function watchChar(c: Model)
	for _, k in charConns do
		k:Disconnect()
	end
	table.clear(charConns)
	for _, a in { "Prone", "Crouched" } do
		table.insert(
			charConns,
			c:GetAttributeChangedSignal(a):Connect(function()
				renderStance()
				wake()
			end)
		)
	end
	W.mag, W.spare = -1, -1
	renderStance()
	equip()
end
player.CharacterAdded:Connect(watchChar)
if player.Character then
	task.spawn(watchChar, player.Character)
end

-- ===== visibilidade, escala e o tutorial =====
local function inField(): boolean
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil
		and h.Health > 0
		and Input.state.alive
		and not Input.state.downed
		and not Input.state.map
		and Input.state.menus == 0
		and player:GetAttribute("Role") ~= nil
end

local dev = 0
local lastCheck = 0
local lastDeg = -1
local compassBlocked = false -- numa tela estreita, a bússola não cabe entre o tutorial e a arma
RunService.RenderStepped:Connect(function()
	local field = inField() or os.clock() < dev
	B.box.Visible = field and not compassBlocked
	local onFoot = field and not Input.state.vehicle
	if onFoot ~= A.card.Visible then
		A.card.Visible = onFoot
		if onFoot then
			W.bright = false
			wake()
		end
	end
	if not field then
		return
	end
	-- rumo da câmera: 0 = norte (−Z), 90 = leste (+X)
	local cam = workspace.CurrentCamera
	if cam then
		local lv = cam.CFrame.LookVector
		local h = math.deg(math.atan2(lv.X, -lv.Z)) % 360
		B.tape.Position = UDim2.fromOffset(CW / 2 - (h + 360 * (if h < 180 then 1 else 0)) * DEG_PX, 0)
		local d = math.floor(h + 0.5) % 360
		if d ~= lastDeg then
			lastDeg = d
			B.deg.Text = string.format("%03d°", d)
		end
		-- objetivo
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local g = goalPos
		if g and root then
			local dx, dz = g.X - root.Position.X, g.Z - root.Position.Z
			local b = math.deg(math.atan2(dx, -dz)) % 360
			local rel = (b - h + 540) % 360 - 180 -- -180..180 em relação ao rumo
			local half = 110 / 2 - 4
			B.goal.Visible = true
			B.goal.Text = if rel < -half then "◄" elseif rel > half then "►" else "▼"
			B.goal.Position = UDim2.fromOffset(CW / 2 + math.clamp(rel, -half, half) * DEG_PX, -2)
		else
			B.goal.Visible = false
		end
		-- squad (Marcadores): cada um no rumo dele; fora da vista, na borda
		local mates = Marcadores.squad()
		for i, dot in B.dots :: { Frame } do
			local s = mates[i]
			if s and root then
				local dx, dz = s.pos.X - root.Position.X, s.pos.Z - root.Position.Z
				local b = math.deg(math.atan2(dx, -dz)) % 360
				local rel = (b - h + 540) % 360 - 180
				local half = 110 / 2 - 2
				dot.Visible = true
				dot.Position = UDim2.new(0, CW / 2 + math.clamp(rel, -half, half) * DEG_PX, 1, -2)
				dot.BackgroundColor3 = if s.downed
					then Color3.fromRGB(240, 124, 104)
					elseif s.leader then Color3.fromRGB(255, 226, 140)
					else UiKit.BRASS_LIGHT
				dot.Size = if s.leader
					then UDim2.fromOffset(px(8, 12), px(8, 12))
					else UDim2.fromOffset(px(6, 9), px(6, 9))
			else
				dot.Visible = false
			end
		end
	end
	-- HUD mínimo: o cartão esmaece em 5 s sem novidade
	if W.bright and os.clock() - W.lastActive > 5 then
		W.bright = false
		-- parado: esmaece só até 0,35 (a 0,62 sumia no campo claro, Studio D-93)
		TweenService:Create(A.card, TweenInfo.new(0.8), { GroupTransparency = 0.35 }):Play()
	end
	-- 4 vezes por segundo: escala da janela e o cartão do tutorial (nada sobreposto)
	local now = os.clock()
	if now - lastCheck > 0.25 then
		lastCheck = now
		local size = gui.AbsoluteSize
		local k = if TV then 1 else math.clamp(size.X / 1280, 0.72, 1)
		B.scale.Scale = k
		A.scale.Scale = k
		local x = size.X / 2
		local pg = player:FindFirstChild("PlayerGui")
		local tg = pg and pg:FindFirstChild("VT65Tutorial")
		local tc = tg and tg:FindFirstChild("Tutorial")
		local half = CW * k / 2
		if tc and tc:IsA("GuiObject") and tc.Visible then
			local right = tc.AbsolutePosition.X + tc.AbsoluteSize.X + 16
			if x - half < right then
				x = right + half
			end
		end
		local cardLeft = size.X - px(18, 28) - AW * k - 12
		compassBlocked = A.card.Visible and x + half > cardLeft
		B.box.Position = UDim2.new(0, x, 1, -px(16, 26))
	end
end)

-- Studio: "hud" acende a bússola e o cartão da arma por 8 s; "veiculo" e "helicoptero" mostram o
-- painel novo do veículo (VehicleHudView, que o dono do VehicleController liga) por 8 s
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if v == "hud" then
			dev = os.clock() + 8
			W.bright = false
			wake()
		elseif v == "veiculo" or v == "helicoptero" then
			local VehicleHudView = require(script.Parent.VehicleHudView)
			local view = VehicleHudView.demo(v :: string)
			task.delay(8, function()
				view.hide()
				local g = view.root.Parent
				if g and g:IsA("ScreenGui") then
					g:Destroy()
				end
			end)
		else
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
	end)
end
