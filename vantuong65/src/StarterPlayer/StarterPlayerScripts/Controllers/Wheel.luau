--!strict
-- Roda radial (Parte 12.5): seleção pelo analógico direito com zona morta de 40% (ou pelo mouse /
-- teclas 1–8); soltar o botão que abriu confirma; B cancela. Itens em posições fixas.
-- Visual (pedido do dono, 2026-11-11: "melhore ainda mais todas as interfaces"): mostrador de
-- bússola oliva com filete cáqui, ponteiro de latão que gira até o item, fichas em volta (a
-- escolhida acende em latão e cresce), o nome do item escolhido no miolo e as dicas em chip. Entra
-- crescendo do centro. Por quadro só se lê o analógico; o desenho muda só quando a escolha muda.
-- Studio: workspace:SetAttribute("VT65DevTela", "roda") abre a roda de comunicação por 4 s.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(game:GetService("ReplicatedStorage").Shared.InputMap)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local Wheel = {}

export type Item = { id: string, label: string }

local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end
-- Fichas numa elipse (D-93; no Studio as fichas 5 e 6 se sobrepunham e a 1 encostava no anel):
-- mais largo que alto, as diagonais ficam fora do alcance das de cima/baixo e o anel de marcas
-- (0,46) fica por dentro de todas, com folga até na ficha acesa (escala 1,1).
local SIZE = px(520, 728)
local RX, RY = SIZE * 0.42, SIZE * 0.34
local CARD_W, CARD_H = px(136, 190), px(58, 80)

local gui = UiKit.screen("VT65Wheel", 40)
gui.Enabled = false
local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.fromOffset(SIZE, SIZE)
center.BackgroundTransparency = 1
center.Parent = gui
-- a área medida inclui as fichas dos lados (passam do mostrador)
local fit = UiKit.fit(gui, center, 2 * (RX + CARD_W * 0.55), SIZE, 10)

local function circle(parent: Instance, d: number, color: Color3, tr: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(d, d)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = tr
	f.BorderSizePixel = 0
	f.Parent = parent
	UiKit.corner(f, 9999)
	return f
end
-- mostrador: disco oliva, anel de marcas e o miolo
local dial = circle(center, 0.9, UiKit.CARD_DARK, 0.22)
UiKit.edge(dial, UiKit.KHAKI, 1, 0.65)
UiKit.lit(dial, 0.7)
local ring = circle(center, 0.46, UiKit.CARD_DARK, 1)
UiKit.edge(ring, UiKit.KHAKI, 1, 0.82)
for i = 0, 35 do -- marcas de 10° como num mostrador (o giro é no centro do quadro inteiro)
	local tick = Instance.new("Frame")
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.fromScale(0.5, 0.5)
	tick.Size = UDim2.fromScale(1, 1)
	tick.Rotation = i * 10
	tick.BackgroundTransparency = 1
	tick.Parent = dial
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.new(0.5, 0, 0, 3)
	mark.Size = UDim2.fromOffset(if i % 9 == 0 then 2 else 1, if i % 9 == 0 then px(10, 14) else px(5, 8))
	mark.BackgroundColor3 = UiKit.KHAKI
	mark.BackgroundTransparency = if i % 9 == 0 then 0.2 else 0.55
	mark.BorderSizePixel = 0
	mark.Parent = tick
end
-- ponteiro de latão (gira no centro)
local needle = Instance.new("Frame")
needle.AnchorPoint = Vector2.new(0.5, 0.5)
needle.Position = UDim2.fromScale(0.5, 0.5)
needle.Size = UDim2.fromScale(1, 1)
needle.BackgroundTransparency = 1
needle.Visible = false
needle.Parent = center
local needleBar = Instance.new("Frame")
needleBar.AnchorPoint = Vector2.new(0.5, 1)
needleBar.Position = UDim2.fromScale(0.5, 0.5)
needleBar.Size = UDim2.new(0, px(3, 4), 0.25, 0)
needleBar.BackgroundColor3 = UiKit.BRASS
needleBar.BorderSizePixel = 0
needleBar.Parent = needle
local needleTip = Instance.new("Frame")
needleTip.AnchorPoint = Vector2.new(0.5, 0.5)
needleTip.Position = UDim2.new(0.5, 0, 0.25, 0)
needleTip.Size = UDim2.fromOffset(px(10, 14), px(10, 14))
needleTip.Rotation = 45
needleTip.BackgroundColor3 = UiKit.BRASS
needleTip.BorderSizePixel = 0
needleTip.Parent = needle
local hub = circle(center, 0.34, UiKit.DRAB, 0.05)
UiKit.edge(hub, UiKit.BRASS, 1.5, 0.35)
UiKit.lit(hub, 0.72)
local title = UiKit.rotulo(hub, 17, UiKit.BRASS_LIGHT, UiKit.HEAD_FONT)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0.16, 0)
title.Size = UDim2.new(0.86, 0, 0.26, 0)
title.TextXAlignment = Enum.TextXAlignment.Center
title.TextWrapped = true
local chosen = UiKit.rotulo(hub, 14, UiKit.CARD, UiKit.BODY_FONT)
chosen.AnchorPoint = Vector2.new(0.5, 0)
chosen.Position = UDim2.new(0.5, 0, 0.44, 0)
chosen.Size = UDim2.new(0.84, 0, 0.3, 0)
chosen.TextXAlignment = Enum.TextXAlignment.Center
chosen.TextWrapped = true
local hint = UiKit.rotulo(hub, 11, UiKit.KHAKI, UiKit.TYPE_FONT)
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 0.9, 0)
hint.Size = UDim2.new(0.86, 0, 0.16, 0)
hint.TextXAlignment = Enum.TextXAlignment.Center
hint.TextTransparency = 0.2

type Slot = { f: TextButton, t: TextLabel, n: TextLabel, sc: UIScale, e: UIStroke, on: boolean?, hot: boolean? }
local slots: { Slot } = {}
for i = 1, 8 do
	local a = (i - 1) * math.pi / 4
	local f = Instance.new("TextButton") -- o mouse também escolhe pela ficha
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, math.sin(a) * RX, 0.5, -math.cos(a) * RY)
	f.Size = UDim2.fromOffset(CARD_W, CARD_H)
	f.BackgroundColor3 = UiKit.DRAB
	f.BackgroundTransparency = 0.08
	f.AutoButtonColor = false
	f.Text = ""
	f.Selectable = false
	f.ZIndex = 3
	f.Parent = center
	UiKit.corner(f, 4)
	UiKit.lit(f, 0.75)
	local e = UiKit.edge(f, UiKit.KHAKI, 1, 0.6)
	local sc = Instance.new("UIScale")
	sc.Parent = f
	local t = UiKit.rotulo(f, 14, UiKit.KHAKI, UiKit.HEAD_FONT)
	t.Position = UDim2.fromOffset(px(8, 12), 0)
	t.Size = UDim2.new(1, -px(16, 24), 1, 0)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextWrapped = true
	t.ZIndex = 4
	local n = UiKit.rotulo(f, 11, UiKit.NIGHT, UiKit.HEAD_FONT)
	n.Position = UDim2.fromOffset(3, 3)
	n.Size = UDim2.fromOffset(px(16, 24), px(16, 24))
	n.BackgroundColor3 = UiKit.KHAKI
	n.BackgroundTransparency = 0.1
	n.TextXAlignment = Enum.TextXAlignment.Center
	n.Text = tostring(i)
	n.ZIndex = 5
	UiKit.corner(n, 3)
	slots[i] = { f = f, t = t, n = n, sc = sc, e = e }
end

local items: { Item } = {}
local enabledFn: (string) -> boolean = function()
	return true
end
local selected: number? = nil
local cursor = Vector2.zero -- teclado/mouse: deslocamento acumulado do mouse
local drawnSel: number? = -1
local needleAngle = 0

local function paintSlot(i: number, s: Slot, it: Item)
	local on = enabledFn(it.id)
	local hot = selected == i
	if s.on == on and s.hot == hot and s.t.Text == it.label then
		return
	end
	s.on, s.hot = on, hot
	s.t.Text = it.label
	s.t.FontFace = UiKit.headFont(it.label)
	s.n.Visible = not Input.isGamepad()
	TweenService:Create(s.f, UiKit.QUICK, {
		BackgroundColor3 = if hot and on then UiKit.OLIVE elseif hot then UiKit.STAMP else UiKit.DRAB,
		BackgroundTransparency = if on or hot then 0.05 else 0.45,
	}):Play()
	TweenService:Create(s.t, UiKit.QUICK, {
		TextColor3 = if hot then UiKit.CARD else UiKit.KHAKI,
		TextTransparency = if on then 0 else 0.55,
	}):Play()
	TweenService:Create(s.e, UiKit.QUICK, {
		Color = if hot then UiKit.BRASS else UiKit.KHAKI,
		Thickness = if hot then 2 else 1,
		Transparency = if hot then 0 else 0.6,
	}):Play()
	TweenService:Create(s.sc, UiKit.SOFT, { Scale = if hot then 1.1 else 1 }):Play()
end

local function render()
	for i, s in slots do
		local it = items[i]
		s.f.Visible = it ~= nil
		if it then
			paintSlot(i, s, it)
		end
	end
	if drawnSel ~= selected then
		drawnSel = selected
		local it = selected and items[selected]
		if it then
			local on = enabledFn(it.id)
			chosen.Text = if on then it.label else string.format("%s (indisponível)", it.label)
			chosen.TextColor3 = if on then UiKit.CARD else Color3.fromRGB(240, 124, 104)
			-- o ponteiro gira pelo caminho mais curto
			local target = ((selected :: number) - 1) * 45
			local d = (target - needleAngle + 540) % 360 - 180
			needleAngle += d
			needle.Visible = true
			TweenService:Create(needle, TweenInfo.new(0.16, Enum.EasingStyle.Quint), { Rotation = needleAngle }):Play()
		else
			chosen.Text = ""
			needle.Visible = false
		end
	end
end

local function renderHint()
	-- frases inteiras (o dicionário traduz a frase, não o verbo solto)
	local toggle = Input.settings.wheelToggle
	if Input.isGamepad() then
		hint.Text = if toggle then "Toque de novo para escolher · B cancela" else "Solte para escolher · B cancela"
	else
		hint.Text = if toggle
			then "Toque de novo para escolher · 1–8 · Backspace cancela"
			else "Solte para escolher · 1–8 · Backspace cancela"
	end
end

-- aberta de fato (a ScreenGui fica ligada mais 0,1 s na saída, só para o encolher)
local isOpen = false
local openToken = 0
function Wheel.isOpen(): boolean
	return isOpen
end

local function hide(animated: boolean)
	isOpen = false
	openToken += 1
	local my = openToken
	if not animated then
		gui.Enabled = false
		return
	end
	fit.play(TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), 0.9)
	TweenService:Create(dial, TweenInfo.new(0.1), { BackgroundTransparency = 0.7 }):Play()
	task.delay(0.1, function()
		if openToken == my then
			gui.Enabled = false
		end
	end)
end

local function reset(label: string, list: { Item })
	items = list
	selected, cursor = nil, Vector2.zero
	drawnSel = -1
	title.Text = UiKit.upper(label)
	title.FontFace = UiKit.headFont(label)
	for _, s in slots do
		s.on, s.hot = nil, nil
	end
	renderHint()
	render()
end

function Wheel.open(name: string, label: string, list: { Item }, enabled: ((string) -> boolean)?)
	enabledFn = enabled or function()
		return true
	end
	openToken += 1
	isOpen = true
	gui.Enabled = true
	Input.event("wheel_open", name)
	reset(label, list)
	-- entra crescendo do centro
	fit.play(TweenInfo.new(0.16, Enum.EasingStyle.Quint), 1, 0.84)
	dial.BackgroundTransparency = 0.6
	TweenService:Create(dial, TweenInfo.new(0.16), { BackgroundTransparency = 0.22 }):Play()
end

-- troca de página sem fechar (ex.: "Comando ►")
function Wheel.page(label: string, list: { Item }, enabled: ((string) -> boolean)?)
	if enabled then
		enabledFn = enabled
	end
	reset(label, list)
	fit.play(TweenInfo.new(0.14, Enum.EasingStyle.Quint), 1, 0.94)
end

-- Fecha; devolve o id escolhido (ou nil se cancelou / item apagado).
function Wheel.close(confirm: boolean): string?
	if not isOpen then
		return nil
	end
	hide(true)
	Input.event("wheel_close")
	local it = selected and items[selected]
	if confirm and it and enabledFn(it.id) then
		return it.id
	end
	return nil
end

-- o mouse sobre uma ficha também escolhe (sem precisar do arrasto)
for i, s in slots do
	s.f.MouseEnter:Connect(function()
		if isOpen and items[i] then
			selected = i
			render()
		end
	end)
end

RunService.RenderStepped:Connect(function()
	if not isOpen then
		return
	end
	local idx: number?
	if Input.isGamepad() then
		local r = Input.stickRaw("right")
		idx = InputMap.wheelIndex(r.X, r.Y, #items)
	else
		local d = UserInputService:GetMouseDelta()
		cursor = cursor + Vector2.new(d.X, -d.Y)
		if cursor.Magnitude > 120 then
			cursor = cursor.Unit * 120
		end
		idx = InputMap.wheelIndex(cursor.X / 120, cursor.Y / 120, #items)
	end
	if idx and idx ~= selected then
		selected = idx
		render()
	end
end)

-- teclas 1–8 escolhem direto no teclado
UserInputService.InputBegan:Connect(function(input)
	if not isOpen or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local n = ({
		One = 1,
		Two = 2,
		Three = 3,
		Four = 4,
		Five = 5,
		Six = 6,
		Seven = 7,
		Eight = 8,
	} :: { [string]: number })[input.KeyCode.Name]
	if n and items[n] then
		selected = n
		render()
	end
end)

Input.on("wheel_cancel", "press", function()
	Wheel.close(false)
end)
Input.StateChanged:Connect(function(cancelled: { string })
	if table.find(cancelled, "wheel") and isOpen then
		hide(false) -- menu/mapa/morte cancelaram a roda (sai na hora: outra tela vem por cima)
	end
end)
Input.DeviceChanged:Connect(function()
	if isOpen then
		renderHint()
		for _, s in slots do
			s.on, s.hot = nil, nil
		end
		render()
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "roda" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
		-- a roda de comunicação de verdade (Shared/Comms), com a página Comando apagada
		local Comms = require(game:GetService("ReplicatedStorage").Shared.Comms) :: any
		Wheel.open("comm", "Comunicação · squad", Comms.COMM, function(id)
			return id ~= "page_command"
		end)
		selected = 3
		render()
		task.delay(4, function()
			if isOpen then
				Wheel.close(false)
			end
		end)
	end)
end

return Wheel
