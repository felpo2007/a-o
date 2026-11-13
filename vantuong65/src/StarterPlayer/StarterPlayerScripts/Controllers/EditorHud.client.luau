--!strict
-- Editor do HUD de toque (Parte 13, parte 7 do pedido do dono). Abre pelo menu do jogo →
-- Configurações → Toque → "Editar o HUD de toque" (Bus "editor_hud_open").
-- Mover (arrastar), redimensionar (60–150%) e transparência de cada botão; os três layouts prontos
-- (2 polegares, 3 dedos, 4 dedos), o canhoto espelhado e 3 espaços próprios (Meu 1–3) salvos na
-- conta (configuração touchCustom, pelo Settings_Save do Input). A área é a mesma do HUD (área
-- segura + 2 mm), então o que se vê aqui é o que vale no campo.
-- Testar: não há campo de tiro no lobby (o do jogo fica atrás de cada QG, já no mapa), então o teste
-- é na própria tela: tocar num botão mostra a ação; o analógico mostra andar/correr/trava.
-- O painel é arrastável pelo título e encolhe (–) para não tapar os botões.
-- v39: os botões que só aparecem quando servem (recarga, golpe, fôlego, bandagem, rádio, interagir)
-- aparecem todos aqui para escolher o lugar; "VER" troca entre a pé, mirando (o fôlego no lugar do
-- golpe) e caído. No tablet o padrão é o compacto (Shared/Toque.compact). Layout salvo com botão que
-- saiu do jogo (ARMA, SELETOR, MARCAR, CÂMERA, CANAL): o botão é ignorado e some ao salvar de novo.
-- Studio: workspace:SetAttribute("VT65DevTela", "editorhud") abre o editor.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Toque = require(ReplicatedStorage.Shared.Toque)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local V = UiKit.V
local F = UiKit.F

local gui = UiKit.screen("VT65EditorHud", 60)
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- a mesma área do HUD de toque
end)
gui.Enabled = false

local veil = Instance.new("Frame")
veil.Name = "Veu"
veil.Size = UDim2.fromScale(1, 1)
veil.BackgroundColor3 = Color3.new(0, 0, 0)
veil.BackgroundTransparency = 0.45
veil.BorderSizePixel = 0
veil.Active = true
veil.Parent = gui

local canvas = Instance.new("Frame")
canvas.Name = "Area"
canvas.BackgroundTransparency = 1
canvas.Size = UDim2.fromScale(1, 1)
canvas.ZIndex = 2
canvas.Parent = gui

-- ===== estado =====
type Item = { def: Toque.Def, f: Frame, t: TextLabel, edge: UIStroke, size: number, cx: number, cy: number }
local E = {
	open = false,
	name = "two", -- layout em edição
	mirror = false,
	work = {} :: { [string]: Toque.Slot },
	dirty = false,
	exitArmed = false,
	selected = nil :: string?,
	testing = false,
	view = "pe", -- o que se vê: "pe" (a pé), "mira" (mirando na luneta) ou "caido"
	W = 800,
	H = 360,
	short = 390,
	drag = nil :: { key: any, id: string, off: Vector2 }?,
	test = {} :: { [any]: { id: string, start: Vector2, last: Vector2 } },
	stick = Toque.newStick(),
}
local items: { [string]: Item } = {}

-- ===== painel =====
local panel = UiKit.panel(gui, V.PANEL, 0.06)
panel.Name = "Painel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(470, 236)
panel.ZIndex = 10
panel.Active = true
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local function row(y: number, h: number): Frame
	local r = Instance.new("Frame")
	r.BackgroundTransparency = 1
	r.Position = UDim2.fromOffset(10, y)
	r.Size = UDim2.new(1, -20, 0, h)
	r.ZIndex = 11
	r.Parent = panel
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = r
	return r
end

local function btn(
	parent: Instance,
	text: string,
	kind: string,
	w: number,
	order: number,
	onClick: () -> ()
): UiKit.Action
	local a = UiKit.action(parent, text, kind, onClick, { h = 28 })
	a.button.Size = UDim2.fromOffset(w, 28)
	a.button.LayoutOrder = order
	a.button.ZIndex = 12
	a.label.ZIndex = 13
	a.label.TextScaled = true
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = 13
	lim.Parent = a.label
	return a
end

-- título (arrasta o painel) e encolher
local titleBar = Instance.new("TextButton")
titleBar.Name = "Titulo"
titleBar.BackgroundTransparency = 1
titleBar.Text = ""
titleBar.AutoButtonColor = false
titleBar.Selectable = false
titleBar.Size = UDim2.new(1, -44, 0, 28)
titleBar.ZIndex = 11
titleBar.Parent = panel
local title = UiKit.kicker(titleBar, "EDITOR DO HUD DE TOQUE", 14, V.KHAKI)
title.Position = UDim2.fromOffset(10, 6)
title.Size = UDim2.new(1, -10, 0, 18)
title.ZIndex = 12

local body = Instance.new("Frame")
body.Name = "Corpo"
body.BackgroundTransparency = 1
body.Size = UDim2.fromScale(1, 1)
body.ZIndex = 11
body.Parent = panel

local presetRow = row(30, 30)
local optRow = row(64, 30)
local selRow = row(98, 26)
local sizeRow = row(128, 30)
local status = UiKit.body(body, "", 13, V.DIM)
status.Position = UDim2.fromOffset(10, 162)
status.Size = UDim2.new(1, -20, 0, 32)
status.ZIndex = 12
local saveRow = row(198, 30)
for _, r in { presetRow, optRow, selRow, sizeRow, saveRow } do
	r.Parent = body
end

-- ===== desenho =====
local function relayoutArea()
	local full = gui.AbsoluteSize
	if full.X < 10 or full.Y < 10 then
		return
	end
	E.short = math.min(full.X, full.Y)
	local m = math.floor(Toque.rawPx(Toque.MARGIN_MM, E.short) + 0.5)
	canvas.Position = UDim2.fromOffset(m, m)
	canvas.Size = UDim2.new(1, -2 * m, 1, -2 * m)
	E.W, E.H = full.X - 2 * m, full.Y - 2 * m
	panelScale.Scale = math.clamp(math.min(full.X / 760, full.Y / 400), 0.6, 1)
end

-- todos os contextuais acesos (o lugar de cada um); golpe e fôlego dividem o lugar
local function shownInView(d: Toque.Def): boolean
	local downed = E.view == "caido"
	local c: Toque.Ctx = {
		foot = not downed,
		vehicle = false,
		downed = downed,
		aiming = E.view == "mira",
		voice = true,
		reload = true,
		melee = true,
		breath = true,
		bleed = true,
		command = true,
	}
	if d.kind == "slot" then
		return not downed
	end
	return Toque.visible(d, c)
end

local function glyphOf(d: Toque.Def): string
	if d.kind == "stick" then
		return "ANALÓGICO"
	elseif d.kind == "slot" then
		return "INTERAGIR"
	end
	return d.glyph
end

local function paintItem(it: Item, hot: boolean)
	local sl = E.work[it.def.id]
	local a = if sl then sl.alpha * Input.settings.touchOpacity else 1
	local on = sl ~= nil and sl.on
	local sel = E.selected == it.def.id
	it.f.BackgroundColor3 = if hot then V.OLIVE elseif it.def.kind == "fire" then V.BG_RED else V.PANEL
	it.f.BackgroundTransparency = if on then 1 - a * 0.6 else 0.85
	it.edge.Color = if sel or hot then V.BRASS else V.KHAKI
	it.edge.Thickness = if sel then 3 else 1.5
	it.edge.Transparency = if on then 1 - a * 0.95 else 0.6
	it.t.TextTransparency = if on then 1 - math.max(a, 0.35) else 0.6
end

local function placeAll()
	for id, it in items do
		local sl = E.work[id]
		local vis = sl ~= nil and shownInView(it.def)
		it.f.Visible = vis
		if sl and vis then
			local size = Toque.buttonPx(it.def.mm, sl.scale, E.short)
			local cx, cy = Toque.place(sl.x, sl.y, size, E.W, E.H)
			it.size, it.cx, it.cy = size, cx, cy
			it.f.Size = UDim2.fromOffset(size, size)
			it.f.Position = UDim2.fromOffset(cx, cy)
			paintItem(it, false)
		end
	end
end

for _, def in Toque.BUTTONS do
	local f = Instance.new("Frame")
	f.Name = def.id
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	f.ZIndex = if def.kind == "stick" then 3 else 4
	f.Parent = canvas
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = f
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Size = UDim2.fromScale(0.8, 0.45)
	t.TextScaled = true
	t.FontFace = F.TITLE_MED
	t.TextColor3 = V.KHAKI
	t.Text = glyphOf(def)
	t.ZIndex = f.ZIndex + 1
	t.Parent = f
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = 15
	lim.MinTextSize = 7
	lim.Parent = t
	items[def.id] = { def = def, f = f, t = t, edge = edge, size = 48, cx = 0, cy = 0 }
end

-- ===== painel: linhas =====
local presetBtns: { [string]: UiKit.Action } = {}
local PRESET_TEXT: { [string]: string } = {
	two = "2 POLEGARES",
	three = "3 DEDOS",
	four = "4 DEDOS",
	custom1 = "MEU 1",
	custom2 = "MEU 2",
	custom3 = "MEU 3",
}
local SAVED_TEXT: { [string]: string } = {
	custom1 = "Salvo em Meu 1.",
	custom2 = "Salvo em Meu 2.",
	custom3 = "Salvo em Meu 3.",
}

local refreshPanel: () -> () = function() end

local function say(text: string)
	status.Text = text
end

local function load(name: string)
	local s = Input.settings
	local custom = s.touchCustom :: any
	local empty = Toque.CUSTOM[name] and (type(custom) ~= "table" or custom[name] == nil)
	if empty and next(E.work) ~= nil then
		-- espaço próprio vazio: começa do que está na tela
		E.dirty = true
	else
		E.work = Toque.layout(
			{ touchLayout = name, touchMirror = E.mirror, touchCustom = custom },
			nil,
			Toque.isTablet(E.short)
		)
		E.dirty = false
	end
	E.name = name
	E.exitArmed = false
	placeAll()
	refreshPanel()
end

for i, name in Toque.LAYOUTS do
	presetBtns[name] = btn(presetRow, PRESET_TEXT[name], "secondary", 66, i, function()
		load(name)
		say("Arraste um botão para mover. Toque nele para escolher.")
	end)
end

local mirrorBtn = btn(optRow, "CANHOTO: NÃO", "secondary", 118, 1, function()
	E.mirror = not E.mirror
	for _, sl in E.work do
		sl.x = 1 - sl.x
	end
	E.dirty = true
	placeAll()
	refreshPanel()
end)
local NEXT_VIEW: { [string]: string } = { pe = "mira", mira = "caido", caido = "pe" }
local VIEW_TEXT: { [string]: string } = { pe = "VER: A PÉ", mira = "VER: MIRANDO", caido = "VER: CAÍDO" }
local viewBtn = btn(optRow, "VER: A PÉ", "secondary", 96, 2, function()
	E.view = NEXT_VIEW[E.view] or "pe"
	placeAll()
	refreshPanel()
end)
local testBtn = btn(optRow, "TESTAR", "secondary", 90, 3, function()
	E.testing = not E.testing
	E.drag = nil
	table.clear(E.test)
	say(
		if E.testing
			then "Toque nos botões: o nome da ação aparece aqui."
			else "Arraste um botão para mover. Toque nele para escolher."
	)
	refreshPanel()
end)
btn(optRow, "DESFAZER", "ghost", 96, 4, function()
	load(E.name)
end)

local selName = UiKit.title(selRow, "", 15, V.TEXT)
selName.Size = UDim2.fromOffset(300, 24)
selName.LayoutOrder = 1
selName.ZIndex = 12
local showBtn = btn(selRow, "OCULTAR", "secondary", 120, 2, function()
	local id = E.selected
	local sl = id and E.work[id]
	if sl then
		sl.on = not sl.on
		E.dirty = true
		placeAll()
		refreshPanel()
	end
end)

local function adjust(field: string, d: number)
	local id = E.selected
	local sl = id and E.work[id]
	if not sl then
		say("Nenhum botão escolhido.")
		return
	end
	if field == "scale" then
		sl.scale = math.clamp(math.floor((sl.scale + d) * 100 + 0.5) / 100, 0.6, 1.5)
	else
		sl.alpha = math.clamp(math.floor((sl.alpha + d) * 100 + 0.5) / 100, 0.1, 1)
	end
	E.dirty = true
	placeAll()
	refreshPanel()
end
btn(sizeRow, "−", "secondary", 34, 1, function()
	adjust("scale", -0.1)
end)
local sizeText = UiKit.body(sizeRow, "", 13, V.TEXT)
sizeText.Size = UDim2.fromOffset(118, 24)
sizeText.LayoutOrder = 2
sizeText.TextXAlignment = Enum.TextXAlignment.Center
sizeText.TextYAlignment = Enum.TextYAlignment.Center
sizeText.ZIndex = 12
btn(sizeRow, "+", "secondary", 34, 3, function()
	adjust("scale", 0.1)
end)
btn(sizeRow, "−", "secondary", 34, 4, function()
	adjust("alpha", 0.1) -- menos transparência = mais opaco
end)
local alphaText = UiKit.body(sizeRow, "", 13, V.TEXT)
alphaText.Size = UDim2.fromOffset(150, 24)
alphaText.LayoutOrder = 5
alphaText.TextXAlignment = Enum.TextXAlignment.Center
alphaText.TextYAlignment = Enum.TextYAlignment.Center
alphaText.ZIndex = 12
btn(sizeRow, "+", "secondary", 34, 6, function()
	adjust("alpha", -0.1)
end)

local close: () -> () = function() end

local function save()
	local target = if Toque.CUSTOM[E.name] then E.name else nil
	local s = table.clone(Input.settings) :: any
	if E.dirty or target then
		target = target or "custom1"
		local tc = table.clone(s.touchCustom or {})
		tc[target] = Toque.toCustom(E.work, E.mirror)
		s.touchCustom = tc
		s.touchLayout = target
	else
		s.touchLayout = E.name
	end
	s.touchMirror = E.mirror
	Input.setSettings(s)
	E.name = s.touchLayout
	E.dirty = false
	E.exitArmed = false
	say(SAVED_TEXT[E.name] or "Layout escolhido.")
	refreshPanel()
end
btn(saveRow, "SALVAR", "primary", 200, 1, save)
btn(saveRow, "SAIR", "secondary", 120, 2, function()
	if E.dirty and not E.exitArmed then
		E.exitArmed = true
		say("Alterações não salvas: toque em SAIR de novo para sair.")
		return
	end
	close()
end)

-- encolher o painel (só o título fica)
local mini = btn(panel, "–", "ghost", 34, 0, function() end)
mini.button.AnchorPoint = Vector2.new(1, 0)
mini.button.Position = UDim2.new(1, -6, 0, 2)
local collapsed = false
mini.button.Activated:Connect(function()
	collapsed = not collapsed
	body.Visible = not collapsed
	panel.Size = UDim2.fromOffset(470, if collapsed then 32 else 236)
end)

refreshPanel = function()
	for name, a in presetBtns do
		local on = name == E.name
		a.realce.base(if on then V.OLIVE else V.PANEL)
	end
	mirrorBtn.label.Text = if E.mirror then "CANHOTO: SIM" else "CANHOTO: NÃO"
	viewBtn.label.Text = VIEW_TEXT[E.view] or "VER: A PÉ"
	testBtn.label.Text = if E.testing then "EDITAR" else "TESTAR"
	local id = E.selected
	local sl = id and E.work[id]
	if id and sl then
		local d = Toque.BY_ID[id]
		selName.Text = d.label
		selName.FontFace = UiKit.headFont(d.label)
		-- ocultar: os opcionais, a vaga do interagir e os que só aparecem quando servem
		local ctxBtn = d.show == "reload"
			or d.show == "melee"
			or d.show == "breath"
			or d.show == "bleed"
			or d.show == "radio"
		showBtn.button.Visible = d.optional == true or d.kind == "slot" or ctxBtn or not sl.on
		showBtn.label.Text = if sl.on then "OCULTAR" else "MOSTRAR"
		sizeText.Text = string.format("Tamanho: %d%%", math.floor(sl.scale * 100 + 0.5))
		alphaText.Text = string.format("Transparência: %d%%", math.floor((1 - sl.alpha) * 100 + 0.5))
	else
		selName.Text = "Nenhum botão escolhido."
		showBtn.button.Visible = false
		sizeText.Text = ""
		alphaText.Text = ""
	end
	for _, it in items do
		paintItem(it, false)
	end
end

-- ===== toque e mouse no editor =====
local function inPanel(p: Vector2): boolean
	local a, s = panel.AbsolutePosition, panel.AbsoluteSize
	return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

local function hitItem(lp: Vector2): string?
	local list: { Toque.HitButton } = {}
	for id, it in items do
		if it.f.Visible then
			table.insert(list, { id = id, cx = it.cx, cy = it.cy, r = it.size / 2 })
		end
	end
	local h = Toque.hit(lp.X, lp.Y, E.W, E.H, list, Toque.zone(E.mirror))
	if h == "camera" or h == "stick" then
		return nil
	end
	return h
end

local TEST_ACTION: { [string]: string } = {}
for _, d in Toque.BUTTONS do
	TEST_ACTION[d.id] = d.label
end

local function pointerDown(key: any, abs: Vector2)
	if not E.open or inPanel(abs) then
		return
	end
	local lp = abs - canvas.AbsolutePosition
	local id = hitItem(lp)
	if E.testing then
		local z = Toque.zone(E.mirror)
		local inZone = lp.X >= z.x0 * E.W and lp.X <= z.x1 * E.W and lp.Y >= z.y0 * E.H and lp.Y <= z.y1 * E.H
		local tid = id or (if inZone then "stick" else "camera")
		E.test[key] = { id = tid, start = lp, last = lp }
		if tid == "stick" then
			Toque.stickBegan(E.stick)
		end
		local it = items[tid]
		if it then
			paintItem(it, true)
		end
		say(if tid == "camera" then "Câmera" elseif tid == "stick" then "Analógico" else TEST_ACTION[tid] or tid)
		return
	end
	if not id then
		return
	end
	E.selected = id
	local it = items[id]
	E.drag = { key = key, id = id, off = lp - Vector2.new(it.cx, it.cy) }
	refreshPanel()
end

local function pointerMove(key: any, abs: Vector2)
	local lp = abs - canvas.AbsolutePosition
	local tt = E.test[key]
	if tt then
		tt.last = lp
		if tt.id == "stick" then
			local d = lp - tt.start
			local R = Toque.buttonPx(Toque.BY_ID.stick.mm, 1, E.short) / 2
			local _, _, sprint = Toque.stickStep(E.stick, true, d.X, d.Y, R)
			local _, _, m = Toque.stickValue(d.X, d.Y, R)
			say(
				if E.stick.locked
					then "Corrida travada"
					elseif sprint then "Correr"
					else string.format("Andar: %d%%", math.floor(m * 100 + 0.5))
			)
		end
		return
	end
	local dr = E.drag
	if not dr or dr.key ~= key then
		return
	end
	local sl = E.work[dr.id]
	if not sl then
		return
	end
	local c = lp - dr.off
	sl.x = math.clamp(c.X / math.max(E.W, 1), 0, 1)
	sl.y = math.clamp(c.Y / math.max(E.H, 1), 0, 1)
	E.dirty = true
	E.exitArmed = false
	placeAll()
end

local function pointerUp(key: any)
	local tt = E.test[key]
	if tt then
		E.test[key] = nil
		local it = items[tt.id]
		if it then
			paintItem(it, false)
		end
		if tt.id == "stick" then
			Toque.stickStep(E.stick, false, 0, 0, 1)
			say(if E.stick.locked then "Corrida travada" else "")
		end
		return
	end
	local dr = E.drag
	if dr and dr.key == key then
		E.drag = nil
		refreshPanel()
	end
end

local function pos2(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end
UserInputService.InputBegan:Connect(function(input: InputObject)
	if not E.open then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		pointerDown(input, pos2(input))
	elseif t == Enum.UserInputType.MouseButton1 then
		pointerDown("mouse", pos2(input))
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject)
	if not E.open then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		pointerMove(input, pos2(input))
	elseif t == Enum.UserInputType.MouseMovement then
		pointerMove("mouse", pos2(input))
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		pointerUp(input)
	elseif t == Enum.UserInputType.MouseButton1 then
		pointerUp("mouse")
	end
end)

-- arrastar o painel pelo título
local panelDrag: { key: any, off: Vector2 }? = nil
titleBar.InputBegan:Connect(function(input: InputObject)
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
		local key: any = if t == Enum.UserInputType.Touch then input else "mouse"
		panelDrag = { key = key, off = pos2(input) - panel.AbsolutePosition - panel.AbsoluteSize / 2 }
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject)
	local pd = panelDrag
	if not pd then
		return
	end
	local t = input.UserInputType
	local key: any = if t == Enum.UserInputType.Touch then input else "mouse"
	if (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseMovement) and key == pd.key then
		local c = pos2(input) - pd.off - gui.AbsolutePosition
		panel.Position = UDim2.fromOffset(c.X, c.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	local pd = panelDrag
	if not pd then
		return
	end
	local t = input.UserInputType
	local key: any = if t == Enum.UserInputType.Touch then input else "mouse"
	if key == pd.key then
		panelDrag = nil
	end
end)

-- ===== abrir e fechar =====
local function open()
	if E.open then
		return
	end
	E.open = true
	E.mirror = Input.settings.touchMirror
	E.testing, E.view, E.selected, E.drag = false, "pe", nil, nil
	table.clear(E.test)
	gui.Enabled = true
	relayoutArea()
	load(Input.settings.touchLayout)
	say("Arraste um botão para mover. Toque nele para escolher.")
	Input.openMenu()
	UiKit.opened("editorhud", 60)
	UiKit.focus(panel) -- no controle: navega pelos botões do painel (B fecha)
end

close = function()
	if not E.open then
		return
	end
	E.open = false
	gui.Enabled = false
	E.drag = nil
	table.clear(E.test)
	UiKit.release(gui)
	UiKit.closed("editorhud")
	Input.closeMenu()
end

Bus.on("editor_hud_open", open)
Input.on("ui_back", "press", function()
	if E.open and UiKit.backFor("editorhud") then
		close()
	end
end)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if E.open then
		relayoutArea()
		placeAll()
	end
end)
-- o jogo mudou o layout por fora (menu): o editor fechado relê ao abrir; aberto, a opacidade muda
Input.SettingsChanged:Connect(function()
	if E.open then
		refreshPanel()
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "editorhud" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
		open()
	end)
end
