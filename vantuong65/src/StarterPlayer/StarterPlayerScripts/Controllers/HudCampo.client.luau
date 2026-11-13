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
-- Toque (Parte 13): embaixo e nos cantos de cima ficam os botões do HUD de toque (T1). A bússola e o
-- cartão da arma sobem para o vão do alto, entre os botões (ToqueUi.topBand), abaixo da faixa da
-- frente, encolhendo para caber; a ordem do comandante fica só no aviso. Tocar no cartão da arma abre
-- o seletor de tiro e a alça (as ações que já existem: "fire_mode" tocar e "zeroing" segurar, pelo
-- Input.virtual). Studio: VT65DevTela = "seletor" abre o seletor de exemplo (com ou sem toque).
-- v39 (toque, "deixe a tela limpa"): a bússola fica na zona livre "bussola" e o cartão da arma na
-- "cartao", no pé do meio (Shared/Toque.ZONES, ToqueUi.zoneIn). Tocar no cartão troca de arma (era o
-- botão ARMA); segurar abre seletor, alça e baioneta (eram SELETOR e o segurar do ARMA).
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
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
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
	-- o squad na fita (pontos de latão; o líder maior; caído em vermelho); quem fala ganha um anel
	-- claro em volta (VozEstado, só aliados)
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
		local ring = UiKit.edge(d, UiKit.V.TEXT, 2, 1)
		ring.Name = "Fala"
		dots[i] = d
	end
	-- "no rádio": etiqueta acima da bússola enquanto você transmite (VozEstado.transmitting)
	local radio = UiKit.tag(box, "● NO RÁDIO", UiKit.V.RED, 13)
	radio.AnchorPoint = Vector2.new(0.5, 1)
	radio.Position = UDim2.new(0.5, 0, 0, -px(4, 6))
	radio.Visible = false
	B = { box = box, scale = sc, tape = tape, letters = letters, deg = deg, goal = goal, dots = dots, radio = radio }
end

-- ===== voz (Controllers/VozEstado: escrito pelo Voz.client; só aliados, nunca inimigo) =====
local VozEstado = require(script.Parent.VozEstado)
local devVoice = 0 -- gancho "voz": acende a fala dos aliados por 5 s
local function talking(userId: number?): boolean
	if os.clock() < devVoice then
		return true
	end
	if not userId then
		return false
	end
	local t, r = VozEstado.get(userId)
	return t or r
end
local function paintRadio()
	B.radio.Visible = VozEstado.transmitting == true or os.clock() < devVoice
end
VozEstado.Changed:Connect(function(userId: number)
	if userId == 0 then
		paintRadio()
	end
end)

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
	zeroOf = {} :: { [string]: number }, -- alça de cada arma (a troca de arma mostrava a da anterior)
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

-- nome do modo de tiro na língua do jogo (a ficha da arma usa o código em inglês: "bolt", "single")
local MODE_NAME: { [string]: string } = {
	semi = "SEMI",
	auto = "AUTOMÁTICO",
	bolt = "FERROLHO",
	single = "TIRO ÚNICO",
	burst = "RAJADA",
}
local function modeText(m: string): string
	if m == "" then
		return "—"
	end
	return MODE_NAME[string.lower(m)] or UiKit.upper(m)
end

local function renderWeapon()
	local wp = weaponDef()
	A.name.Text = if W.id == "launcher" then "Lançador" elseif wp then wp.name else "—"
	A.mode.Text = modeText(W.mode)
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
	local bipod = player:GetAttribute("Bipe")
	local armed = bipod == "prone" or bipod == "rested"
	A.stanceText.Text = if armed
		then "BIPÉ ARMADO"
		elseif idx == 3 then "DEITADO"
		elseif idx == 2 then "AGACHADO"
		else "DE PÉ"
	A.stanceText.TextColor3 = if armed then UiKit.BRASS_LIGHT else UiKit.V.TEXT
end

local function equip()
	local id = player:GetAttribute("EquippedWeapon")
	W.id = if type(id) == "string" then id else nil
	local wp = weaponDef()
	-- o modo de verdade é o do seletor (atributo local FireMode do WeaponController); a ficha só
	-- serve de reserva enquanto o atributo não chega
	local fm = player:GetAttribute("FireMode")
	W.mode = if type(fm) == "string" then fm elseif wp and wp.modes and wp.modes[1] then wp.modes[1] else ""
	-- a alça desta arma (a última que ela teve; nova: a 1ª da escala, como o WeaponController)
	local zs = if wp then Weapons.zeros(wp) else nil
	W.zero = (W.id and W.zeroOf[W.id]) or (if zs and zs[1] then zs[1] else 100)
	renderWeapon()
	wake()
end
player:GetAttributeChangedSignal("EquippedWeapon"):Connect(equip)
player:GetAttributeChangedSignal("FireMode"):Connect(function()
	local fm = player:GetAttribute("FireMode")
	if type(fm) == "string" and fm ~= W.mode then
		W.mode = fm
		renderWeapon()
		wake()
	end
end)
-- bipé armado (atributo local Bipe do WeaponController: "prone" | "rested" | nil): a linha da
-- postura vira "BIPÉ ARMADO" enquanto valer
player:GetAttributeChangedSignal("Bipe"):Connect(function()
	renderStance()
	wake()
end)

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
		if W.id then
			W.zeroOf[W.id] = W.zero
		end
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

-- ===== toque (Parte 13): seletor de tiro e alça pelo cartão da arma =====
-- O cartão é um CanvasGroup (não recebe toque): um botão transparente por cima abre, embaixo dele,
-- os botões das ações que já existem (ToqueTelas.weaponOptions): SELETOR (fire_mode tocar), ALÇA +
-- (zeroing segurar) e, na arma de um modo só e alça longa (M79, luneta), ALÇA − (fire_mode tocar).
-- O cartão mostra o resultado (o aviso "arma" do WeaponController passa pelo Toast.intercept acima).
local Sel: { [string]: any } = { open = false, until_ = 0, dev = 0, touchPos = nil, last = 0 }
do
	local V = UiKit.V
	local tap = Instance.new("TextButton")
	tap.Name = "ToqueArma"
	tap.Text = ""
	tap.AutoButtonColor = false
	tap.BackgroundTransparency = 1
	tap.Selectable = false
	tap.AnchorPoint = Vector2.new(0.5, 0)
	tap.Visible = false
	tap.Parent = holder
	local pop = UiKit.panel(holder, V.PANEL, 0.08)
	pop.Name = "Seletor"
	pop.AnchorPoint = Vector2.new(0.5, 0)
	pop.AutomaticSize = Enum.AutomaticSize.XY
	pop.Size = UDim2.new()
	pop.Visible = false
	pop.Active = true
	UiKit.pad(pop, 8, 8, 8, 8)
	UiKit.list(pop, true, 8)
	local h = ToqueUi.minPx()
	local function mk(name: string, text: string, order: number, kind: string?): TextButton
		local b = ToqueUi.bigButton(pop, text, kind, math.floor(h * 2))
		b.Name = name
		b.LayoutOrder = order
		return b
	end
	local bMode = mk("Seletor", "SELETOR", 1, "primary")
	local bDown = mk("AlcaMenos", "ALÇA −", 2)
	local bUp = mk("AlcaMais", "ALÇA +", 3)
	local bBay = mk("Baioneta", "BAIONETA", 4) -- v39: era o segurar do botão ARMA
	local bClose = mk("Fechar", "✕", 5)
	bClose.Size = UDim2.fromOffset(h, h)
	local BAYONET = (require(ReplicatedStorage.Shared.Melee) :: any).BAYONET
	local function opts(): { string }
		local wp = weaponDef()
		if not wp then
			return {}
		end
		local role = player:GetAttribute("Role")
		local modes = Weapons.modesFor(wp, if type(role) == "string" then role else nil)
		return ToqueTelas.weaponOptions(#modes, #Weapons.zeros(wp), BAYONET[W.id] ~= nil)
	end
	local function paint()
		local o = opts()
		bMode.Visible = table.find(o, "mode") ~= nil
		bDown.Visible = table.find(o, "zero_down") ~= nil
		bUp.Visible = table.find(o, "zero_up") ~= nil
		bBay.Visible = table.find(o, "bayonet") ~= nil
	end
	function Sel.setOpen(on: boolean)
		Sel.open = on
		pop.Visible = on
		if on then
			paint()
			Sel.until_ = os.clock() + 6
			wake()
		end
	end
	local function touched()
		Sel.until_ = os.clock() + 6 -- mexeu: fica aberto mais um pouco
		wake()
	end
	-- v39: tocar troca de arma; segurar parado abre o seletor (ToqueTelas.cardGesture); com o seletor
	-- aberto, tocar no cartão fecha
	local press: { io: InputObject, t0: number, p0: Vector3, held: boolean }? = nil
	tap.InputBegan:Connect(function(io: InputObject)
		local t = io.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local my = { io = io, t0 = os.clock(), p0 = io.Position, held = false }
		press = my
		task.delay(ToqueTelas.CARD_HOLD_S, function()
			local moved = (io.Position - my.p0).Magnitude
			if press == my and ToqueTelas.cardGesture(os.clock() - my.t0, moved, false) == "hold" then
				my.held = true
				Sel.setOpen(true)
			end
		end)
	end)
	game:GetService("UserInputService").InputEnded:Connect(function(io: InputObject)
		local my = press
		if not (my and (my.io == io or io.UserInputType == Enum.UserInputType.MouseButton1)) then
			return
		end
		press = nil
		local g = ToqueTelas.cardGesture(os.clock() - my.t0, (io.Position - my.p0).Magnitude, true)
		if my.held or g ~= "tap" then
			return
		end
		if Sel.open then
			Sel.setOpen(false)
		else
			ToqueUi.tap("swap_weapon")
			wake()
		end
	end)
	bBay.Activated:Connect(function()
		touched()
		ToqueUi.tap("bayonet")
	end)
	bMode.Activated:Connect(function()
		touched()
		ToqueUi.tap("fire_mode")
	end)
	bDown.Activated:Connect(function()
		touched()
		ToqueUi.tap("fire_mode") -- a arma de um modo só: o toque do seletor desce a alça
	end)
	bUp.Activated:Connect(function()
		touched()
		ToqueUi.hold("zeroing")
	end)
	bClose.Activated:Connect(function()
		Sel.setOpen(false)
	end)
	-- 4 vezes por segundo (RenderStepped): no toque o cartão fica no vão do alto, abaixo da bússola
	-- (Sel.touchPos, posto pelo bloco de escala), com o botão por cima e o seletor logo abaixo
	function Sel.update(k: number, onFoot: boolean)
		local tp: Vector2? = Sel.touchPos
		local card = A.card :: CanvasGroup
		if tp and Sel.below == false then
			-- v39: o cartão na zona do pé do meio (tp = meio da base) e o seletor logo acima dele, preso
			-- para caber na largura da tela
			card.AnchorPoint = Vector2.new(0.5, 1)
			card.Position = UDim2.fromOffset(tp.X, tp.Y)
			local half = pop.AbsoluteSize.X / 2
			local gw = gui.AbsoluteSize.X
			pop.AnchorPoint = Vector2.new(0.5, 1)
			pop.Position = UDim2.fromOffset(
				math.clamp(tp.X, math.min(half + 4, gw / 2), math.max(gw - half - 4, gw / 2)),
				tp.Y - AH * k - 6
			)
		elseif tp then
			card.AnchorPoint = Vector2.new(0.5, 0)
			card.Position = UDim2.fromOffset(tp.X, tp.Y)
			pop.AnchorPoint = Vector2.new(0.5, 0)
			pop.Position = UDim2.fromOffset(tp.X, tp.Y + AH * k + 6)
		else
			card.AnchorPoint = Vector2.new(1, 1)
			card.Position = UDim2.new(1, -px(18, 28), 1, -px(16, 26))
		end
		local show = tp ~= nil and onFoot and card.Visible
		tap.Visible = show
		tap.AnchorPoint = card.AnchorPoint
		tap.Position = card.Position
		tap.Size = UDim2.fromOffset(AW * k, AH * k)
		if Sel.open and (not show or os.clock() > Sel.until_) then
			Sel.setOpen(false)
		end
	end
end

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

-- ============================================================================================
-- ordem do comandante (plano de diversão, 2026-11-12): a ordem curta do squad ("tomar o casario",
-- "segurar o dique") no alto à esquerda, com aviso quando chega e quando é cumprida. Vem do
-- CampanhaCliente (campo `order`, só do próprio squad). Some fora de campo e depois de cumprida.
-- ============================================================================================
local Ordem: { [string]: any } = {}
do
	local CampanhaCliente = require(script.Parent.CampanhaCliente)
	local V, F = UiKit.V, UiKit.F
	local box = UiKit.panel(holder, V.PANEL, 0.12)
	box.Name = "Ordem"
	box.Position = UDim2.fromOffset(px(16, 24), px(12, 18))
	box.Size = UDim2.fromOffset(px(300, 430), px(56, 80))
	box.Visible = false
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, px(4, 6), 1, 0)
	bar.BackgroundColor3 = V.BRASS
	bar.BorderSizePixel = 0
	bar.Parent = box
	local kick = UiKit.kicker(box, "ORDEM DO COMANDANTE", px(12, 18), V.BRASS)
	kick.Position = UDim2.fromOffset(px(14, 20), px(6, 8))
	kick.Size = UDim2.new(1, -px(70, 96), 0, px(16, 24))
	local txt = UiKit.text2(box, "", px(16, 23), V.TEXT, F.BODY_B)
	txt.Position = UDim2.fromOffset(px(14, 20), px(24, 34))
	txt.Size = UDim2.new(1, -px(70, 96), 0, px(24, 34))
	txt.TextTruncate = Enum.TextTruncate.AtEnd
	local sector = UiKit.tag(box, "", V.PANEL_3, px(13, 19))
	sector.AnchorPoint = Vector2.new(1, 0.5)
	sector.Position = UDim2.new(1, -px(10, 14), 0.5, 0)
	local last: { text: string?, done: boolean? } = { text = nil, done = nil }
	local doneAt = 0
	local sample: any = nil
	local devUntil = 0
	-- o servidor manda o MODELO ("Tomar %s") e o argumento à parte (arg): a frase inteira casa no
	-- dicionário depois de montada
	local function sentence(o: any): string
		if type(o.arg) == "string" or type(o.arg) == "number" then
			local ok, s = pcall(string.format, o.text, tostring(o.arg))
			if ok then
				return s
			end
		end
		return (string.gsub(o.text, "%%s", ""))
	end
	function Ordem.current(): any
		if sample and os.clock() < devUntil then
			return sample
		end
		local s = CampanhaCliente.get()
		local o = if type(s) == "table" then s.order else nil
		return if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then o else nil
	end
	function Ordem.paint()
		local o = Ordem.current()
		if not o then
			return
		end
		txt.Text = sentence(o)
		sector.Visible = type(o.sector) == "number"
		sector.Text = if type(o.sector) == "number" then string.format("S%d", o.sector) else ""
		box.BackgroundColor3 = if o.done then V.BG_OLIVE else V.PANEL
		kick.Text = if o.done then "ORDEM CUMPRIDA" else "ORDEM DO COMANDANTE"
	end
	-- visível em campo, com ordem; cumprida, fica 8 s e sai
	function Ordem.visible(field: boolean): boolean
		local o = Ordem.current()
		if not (field and o) then
			return false
		end
		if o.done and os.clock() - doneAt > 8 then
			return false
		end
		return true
	end
	CampanhaCliente.Changed:Connect(function(s: any)
		local o = if type(s) == "table" then s.order else nil
		local text = if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then o.text else nil
		local done = text ~= nil and (o :: any).done == true
		if text and text ~= last.text and not done then
			Toast.show(sentence(o), "alerta", { title = "Ordem do comandante", key = "ordem" })
		elseif text and done and last.done == false and text == last.text then
			doneAt = os.clock()
			Toast.show(
				"Ordem cumprida: bônus para o squad",
				"sucesso",
				{ title = "Ordem do comandante", key = "ordem" }
			)
		end
		if done and last.done ~= true then
			doneAt = os.clock()
		end
		last.text, last.done = text, done
		Ordem.paint()
	end)
	function Ordem.dev()
		sample = { text = "Tomar o casario", sector = 3, untilT = os.time() + 600, done = false }
		devUntil = os.clock() + 8
		Ordem.paint()
		Toast.show(sample.text, "alerta", { title = "Ordem do comandante", key = "ordem" })
	end
	Ordem.box = box
end

local dev = 0
local lastCheck = 0
local lastDeg = -1
local compassBlocked = false -- numa tela estreita, a bússola não cabe entre o tutorial e a arma
RunService.RenderStepped:Connect(function()
	local field = inField() or os.clock() < dev
	B.box.Visible = field and not compassBlocked
	-- toque (Parte 13): o alto à esquerda é dos botões do HUD de toque (mapa, menu...); a ordem chega
	-- pelo aviso (Toast "Ordem do comandante") e o cartão fixo não aparece
	local ov = Ordem.visible(field) and not ToqueUi.active()
	if Ordem.box.Visible ~= ov then
		Ordem.box.Visible = ov
	end
	local onFoot = field and not Input.state.vehicle
	if onFoot ~= A.card.Visible then
		A.card.Visible = onFoot
		if onFoot then
			W.bright = false
			wake()
		end
	end
	local nowSel = os.clock()
	if nowSel - (Sel.last or 0) > 0.25 or (not onFoot and Sel.open) then
		Sel.last = nowSel
		Sel.update(A.scale.Scale, onFoot)
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
				local ring = dot:FindFirstChild("Fala") :: UIStroke?
				if ring then
					ring.Transparency = if talking((s :: any).userId) then 0 else 1
				end
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
		local zb, zc = ToqueUi.zoneIn(gui, "bussola"), ToqueUi.zoneIn(gui, "cartao")
		if zb and zc then
			-- toque v39: as zonas livres do HUD de toque (Shared/Toque.ZONES): a bússola embaixo da
			-- faixa da frente; o cartão da arma no pé do meio, preso pela base (o seletor abre acima)
			local kc = math.clamp(math.min(zb.w / CW, zb.h / CH), 0.45, k)
			B.scale.Scale = kc
			B.box.AnchorPoint = Vector2.new(0.5, 0)
			B.box.Position = UDim2.fromOffset(zb.x + zb.w / 2, zb.y)
			A.scale.Scale = math.clamp(math.min(zc.w / AW, zc.h / AH), 0.4, math.min(k, 0.8))
			Sel.touchPos = Vector2.new(zc.x + zc.w / 2, zc.y + zc.h)
			Sel.below = false
			compassBlocked = false
		elseif ToqueUi.active() or os.clock() < Sel.dev then
			Sel.below = true
			-- toque (Parte 13): embaixo e nos cantos de cima ficam os botões do HUD de toque. A bússola
			-- e o cartão da arma sobem para o vão do alto (ToqueUi.topBand), abaixo da faixa da frente,
			-- encolhendo para caber
			local x0, x1 = ToqueUi.topBand()
			local gap = x1 - x0 - 8
			local mid = (x0 + x1) / 2 - gui.AbsolutePosition.X
			local top = px(6, 8)
			local fg = player.PlayerGui:FindFirstChild("VT65Frente")
			local strip = fg and fg:FindFirstChild("Faixa")
			if strip and strip:IsA("GuiObject") and strip.Visible then
				top = strip.AbsolutePosition.Y + strip.AbsoluteSize.Y - gui.AbsolutePosition.Y + 4
			end
			local kc = ToqueTelas.fitScale(CW, gap, k, 0.45)
			B.scale.Scale = kc
			B.box.AnchorPoint = Vector2.new(0.5, 0)
			B.box.Position = UDim2.fromOffset(mid, top)
			local ka = ToqueTelas.fitScale(AW, gap, math.min(k, 0.62), 0.45)
			A.scale.Scale = ka
			Sel.touchPos = Vector2.new(mid, top + CH * kc + 4)
			compassBlocked = false
		else
			Sel.touchPos = nil
			B.box.AnchorPoint = Vector2.new(0.5, 1)
			local x = size.X / 2
			local pg = player:FindFirstChild("PlayerGui")
			local tg = pg and pg:FindFirstChild("VT65Tutorial")
			local tc = tg and tg:FindFirstChild("Tutorial")
			local half = CW * k / 2
			-- só se o cartão do tutorial estiver embaixo (no toque ele fica no alto)
			if tc and tc:IsA("GuiObject") and tc.Visible and tc.AnchorPoint.Y > 0.5 then
				local right = tc.AbsolutePosition.X + tc.AbsoluteSize.X + 16
				if x - half < right then
					x = right + half
				end
			end
			local cardLeft = size.X - px(18, 28) - AW * k - 12
			compassBlocked = A.card.Visible and x + half > cardLeft
			B.box.Position = UDim2.new(0, x, 1, -px(16, 26))
		end
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
		elseif v == "seletor" then
			-- o cartão no lugar do toque e o seletor aberto por 8 s (com ou sem toque)
			dev = os.clock() + 8
			Sel.dev = os.clock() + 8
			Sel.update(A.scale.Scale, true)
			Sel.setOpen(true)
			Sel.until_ = os.clock() + 8
		elseif v == "ordem" then
			-- ordem do comandante de exemplo por 8 s (o HUD acende junto)
			dev = os.clock() + 8
			Ordem.dev()
		elseif v == "voz" then
			-- a fala dos aliados (anel nos pontos do squad) e o "no rádio" por 5 s
			dev = os.clock() + 5
			devVoice = os.clock() + 5
			paintRadio()
			task.delay(5.1, paintRadio)
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
