--!strict
-- Roda radial (Parte 12.5): seleção pelo analógico direito com zona morta de 40% (ou pelo mouse /
-- teclas 1–8); soltar o botão que abriu confirma; B cancela. Itens em posições fixas.
-- Visual (pedido do dono, 2026-11-11: "melhore ainda mais todas as interfaces"): mostrador de
-- bússola oliva com filete cáqui, ponteiro de latão que gira até o item, fichas em volta (a
-- escolhida acende em latão e cresce), o nome do item escolhido no miolo e as dicas em chip. Entra
-- crescendo do centro. Por quadro só se lê o analógico; o desenho muda só quando a escolha muda.
-- Parte 13 (toque): segurar o botão da roda no HUD de toque abre a roda em volta do polegar;
-- deslizar escolhe pela direção (zona morta de 40% de ~12 mm), soltar confirma e soltar no centro
-- cancela. Aberta sem segurar (alternar, página "Comando ►"): tocar no item escolhe, tocar fora
-- cancela. O botão virtual conta como o físico (Input.virtualDown / Input.VirtualChanged).
-- Studio: workspace:SetAttribute("VT65DevTela", "roda") abre a roda de comunicação por 4 s.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(game:GetService("ReplicatedStorage").Shared.InputMap)
local Toque = require(game:GetService("ReplicatedStorage").Shared.Toque)
local Bus = require(script.Parent.Bus)
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
-- toque: referência de coordenadas (o dedo vem em px de tela) e o véu que cancela ao tocar fora
local area = Instance.new("TextButton")
area.Name = "Veu"
area.Size = UDim2.fromScale(1, 1)
area.BackgroundTransparency = 1
area.Text = ""
area.AutoButtonColor = false
area.Selectable = false
area.ZIndex = 0
area.Parent = gui
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
local holdCodes: { Enum.KeyCode } = {} -- botões que abriram a roda segurando (vazio: sem segurar)
local holdAction: string? = nil -- a ação que abriu segurando (o botão virtual do toque também conta)

local function paintSlot(i: number, s: Slot, it: Item)
	local on = enabledFn(it.id)
	local hot = selected == i
	if s.on == on and s.hot == hot and s.t.Text == it.label then
		return
	end
	s.on, s.hot = on, hot
	s.t.Text = it.label
	s.t.FontFace = UiKit.headFont(it.label)
	s.n.Visible = not Input.isGamepad() and not Input.touchActive() -- as teclas 1–8 são do teclado
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
	local free = not toggle and #holdCodes == 0 -- página aberta depois de soltar (ex.: "Comando ►")
	if Input.touchActive() then
		local holding = not toggle and holdAction ~= nil and Input.virtualDown(holdAction)
		hint.Text = if holding
			then "Deslize e solte para escolher · no centro cancela"
			else "Toque num item · toque fora cancela"
	elseif Input.isGamepad() then
		hint.Text = if toggle
			then "Toque de novo para escolher · B cancela"
			elseif free then "A escolhe · B cancela"
			else "Solte para escolher · B cancela"
	else
		hint.Text = if toggle
			then "Toque de novo para escolher · 1–8 · Backspace cancela"
			elseif free then "Clique ou Enter escolhe · 1–8 · Backspace cancela"
			else "Solte para escolher · 1–8 · Backspace cancela"
	end
end

-- aberta de fato (a ScreenGui fica ligada mais 0,1 s na saída, só para o encolher)
local isOpen = false
local openToken = 0
local openedAt = 0
function Wheel.isOpen(): boolean
	return isOpen
end

-- ===== segurar o botão (D-94, o dono: "não consigo trocar de equipamento nem me comunicar; a tela
-- some muito rápido") =====
-- Ao abrir, o contexto vira "wheel", que não tem a ação que abriu a roda: o Input solta o botão
-- seguro (holdEnd) no mesmo instante e a roda fechava sem escolha. Agora a roda sabe quais botões a
-- abriram (os da ação, no controle e no teclado) e só a soltura FÍSICA deles confirma; o holdEnd
-- falso de quem chama é ignorado enquanto o botão segue apertado (Wheel.heldDown).
function Wheel.heldDown(): boolean
	if holdAction and Input.virtualDown(holdAction) then
		return true -- o dedo segue no botão do HUD de toque
	end
	for _, kc in holdCodes do
		local name = kc.Name
		if string.sub(name, 1, 6) == "Button" or string.sub(name, 1, 4) == "DPad" then
			for _, pad in UserInputService:GetConnectedGamepads() do
				if UserInputService:IsGamepadButtonDown(pad, kc) then
					return true
				end
			end
		elseif UserInputService:IsKeyDown(kc) then
			return true
		end
	end
	return false
end

local function codesFor(actionId: string?): { Enum.KeyCode }
	local out: { Enum.KeyCode } = {}
	if not actionId then
		return out
	end
	for _, a in InputMap.ACTIONS do
		if a.id == actionId then
			for _, name in { InputMap.padFor(a, Input.settings) or "", InputMap.keyFor(a, Input.settings) or "" } do
				local ok, kc = pcall(function()
					return (Enum.KeyCode :: any)[name]
				end)
				if name ~= "" and ok and typeof(kc) == "EnumItem" then
					table.insert(out, kc :: Enum.KeyCode)
				end
			end
		end
	end
	return out
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

-- Toque: a roda nasce em volta do polegar (presa para caber na tela); fora do toque, no centro.
local function placeCenter()
	local s = if holdAction and Input.touchActive() then Input.virtualPoint(holdAction) else nil
	if not s then
		center.Position = UDim2.fromScale(0.5, 0.5)
		return
	end
	local k = fit.k()
	local hw, hh = (RX + CARD_W * 0.55) * k, SIZE / 2 * k
	local a = area.AbsoluteSize
	if a.X < 10 or a.Y < 10 then
		a = workspace.CurrentCamera.ViewportSize
	end
	local p = s - area.AbsolutePosition
	center.Position = UDim2.fromOffset(
		math.clamp(p.X, math.min(hw, a.X / 2), math.max(a.X - hw, a.X / 2)),
		math.clamp(p.Y, math.min(hh, a.Y / 2), math.max(a.Y - hh, a.Y / 2))
	)
end

-- holdAction: a ação que abriu a roda segurando ("equip_wheel", "comm_wheel"); sem ela (página
-- aberta depois de soltar), A, Enter ou o clique confirmam
function Wheel.open(name: string, label: string, list: { Item }, enabled: ((string) -> boolean)?, holdBy: string?)
	enabledFn = enabled or function()
		return true
	end
	holdCodes = codesFor(holdBy)
	holdAction = holdBy
	openedAt = os.clock()
	openToken += 1
	isOpen = true
	gui.Enabled = true
	placeCenter()
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
	holdCodes = {}
	holdAction = nil
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
	-- toque: tocar na ficha escolhe e confirma (roda aberta sem o polegar segurando)
	s.f.Activated:Connect(function(input: InputObject)
		if not isOpen or not items[i] or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if holdAction and Input.virtualDown(holdAction) and not Input.settings.wheelToggle then
			return -- segurando: quem escolhe é o polegar
		end
		selected = i
		render()
		Bus.fire("wheel_confirm")
	end)
end
-- toque fora da roda cancela
area.Activated:Connect(function(input: InputObject)
	if isOpen and input.UserInputType == Enum.UserInputType.Touch and os.clock() - openedAt > 0.15 then
		if not (holdAction and Input.virtualDown(holdAction)) or Input.settings.wheelToggle then
			Wheel.close(false)
		end
	end
end)

-- raio do gesto do polegar (~12 mm; a zona morta é 40% dele)
local function thumbR(): number
	local vp = workspace.CurrentCamera.ViewportSize
	return Toque.rawPx(12, math.min(vp.X, vp.Y))
end

RunService.RenderStepped:Connect(function()
	if not isOpen then
		return
	end
	local idx: number?
	if Input.touchActive() then
		-- polegar no botão: a direção do dedo desde onde começou escolhe; no centro, nada
		local s: Vector2?, cur: Vector2? = nil, nil
		if holdAction then
			s, cur = Input.virtualPoint(holdAction)
		end
		if s and cur then
			local d = cur - s
			local r = thumbR()
			idx = InputMap.wheelIndex(d.X / r, -d.Y / r, #items)
			if idx ~= selected then
				selected = idx
				render()
			end
		end
		return
	elseif Input.isGamepad() then
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

-- soltar o botão que abriu a roda confirma (com folga: a escolha feita até ali vale, mesmo que o
-- analógico já tenha voltado ao centro); quem confirma é o dono da roda (Bus "wheel_confirm")
UserInputService.InputEnded:Connect(function(input: InputObject)
	if not isOpen or Input.settings.wheelToggle or #holdCodes == 0 then
		return
	end
	if table.find(holdCodes, input.KeyCode) and not Wheel.heldDown() then
		task.defer(function()
			if isOpen then
				Bus.fire("wheel_confirm")
			end
		end)
	end
end)
-- sem botão seguro (página aberta depois de soltar, ou "alternar"): A, Enter ou clique confirmam
UserInputService.InputBegan:Connect(function(input: InputObject)
	if not isOpen or os.clock() - openedAt < 0.15 or Wheel.heldDown() then
		return
	end
	if not Input.settings.wheelToggle and #holdCodes > 0 then
		return -- segurando: quem confirma é a soltura
	end
	local k = input.KeyCode
	if
		k == Enum.KeyCode.ButtonA
		or k == Enum.KeyCode.Return
		or k == Enum.KeyCode.KeypadEnter
		or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		Bus.fire("wheel_confirm")
	end
end)

-- toque: soltar o polegar do botão que abriu a roda confirma (como soltar o botão físico)
Input.VirtualChanged:Connect(function(spec: string, down: boolean)
	if down or not isOpen or Input.settings.wheelToggle or not holdAction then
		return
	end
	if Toque.specHas(spec, holdAction :: string) and not Wheel.heldDown() then
		if selected == nil and os.clock() - openedAt < 0.3 then
			-- toque curto: a roda fica aberta para escolher tocando no item (toque fora cancela)
			holdAction = nil
			holdCodes = {}
			renderHint()
			return
		end
		task.defer(function()
			if isOpen then
				Bus.fire("wheel_confirm")
			end
		end)
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
