--!strict
-- HUD de toque (Parte 13, "núcleo do toque"). Dois polegares, na horizontal: analógico flutuante à
-- esquerda (proporcional; a borda para a frente corre; arrastar além até o cadeado trava a corrida),
-- arrastar à direita gira a câmera, tiro grande à direita (arrastar o próprio botão também gira),
-- mira, recarga, postura (tocar agacha, segurar deita, deslizar para cima levanta), pular/transpor,
-- arma, roda de equipamento, inclinar, bandagem, mapa e menu no alto à esquerda, comunicação,
-- marcar e rádio (com a voz) no alto à direita. A vaga do "interagir" é do botão contextual (T2).
-- Sem minimapa, sem marcador de inimigo: os botões só apertam as mesmas ações do controle
-- (Input.virtual). Regras puras e layouts no Shared/Toque (testados no Lune).
-- Cada toque pertence ao controle onde começou: o dedo da câmera que passa por cima de um botão não
-- o aciona; soltar fora solta. App em segundo plano, ligação ou notificação (Input.TouchReset):
-- solta tudo. Some com menus, mapa, roda, baixa (morto) e quando o toque não é a entrada (controle
-- conectado). No veículo ficam o analógico, o mapa, o menu e o rádio (os botões do veículo são do
-- agente de veículos). Área segura: ScreenInsets CoreUISafeInsets (aparelho + barra do Roblox) e
-- 2 mm de margem.
-- Para o botão contextual (T2): a ScreenGui "VT65Toque" tem os atributos InteractPos (Vector2,
-- centro em px de tela), InteractSize (px) e InteractVisible.
-- Studio (Device Emulator), workspace:SetAttribute("VT65DevToque", x):
--   "forcar" / "normal"  liga/desliga o modo de toque sem aparelho (o clique do mouse vira toque);
--   "fundo" / "volta"    simula o app ir para o segundo plano e voltar;
--   "correr" | "andar" | "devagar"  analógico na borda / na metade / pouco, para a frente, por 2 s;
--   "trava"              trava a corrida;
--   "botao:<id>"         toca o botão (ids do Shared/Toque: fire, aim, reload, posture, jump...);
--   "segurar:<id>:<s>"   segura o botão por s segundos;
--   "olhar:<dx>,<dy>"    arrasto de câmera em px;
--   "layout:<nome>"      two | three | four | custom1..3;  "espelho"  canhoto liga/desliga;
--   "estado"             escreve no Output o estado do HUD.
--   ("giro:<yaw>,<pitch>" é do CameraLook.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Toque = require(ReplicatedStorage.Shared.Toque)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)
local VozEstado = require(script.Parent.VozEstado)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local V = UiKit.V
local F = UiKit.F

-- ===== tela =====
local gui = UiKit.screen("VT65Toque", 4)
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- não cobre os botões do Roblox no alto
end)
gui.Enabled = false

-- fundo que segura os toques: o módulo de câmera do Roblox não gira com eles (quem gira é o
-- CameraLook, com a sensibilidade do jogo)
local sink = Instance.new("TextButton")
sink.Name = "Fundo"
sink.Size = UDim2.fromScale(1, 1)
sink.BackgroundTransparency = 1
sink.Text = ""
sink.AutoButtonColor = false
sink.Selectable = false
sink.ZIndex = 1
sink.Parent = gui

local root = Instance.new("Frame")
root.Name = "Area"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.ZIndex = 2
root.Parent = gui

local function circle(parent: Instance, z: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	return f
end

-- ===== botões =====
type Btn = {
	def: Toque.Def,
	f: TextButton,
	t: TextLabel,
	edge: UIStroke,
	sc: UIScale,
	cx: number,
	cy: number,
	r: number,
	alpha: number,
	visible: boolean,
	down: boolean,
	latched: boolean,
}
local btns: { [string]: Btn } = {}

local function makeButton(def: Toque.Def): Btn
	local f = Instance.new("TextButton")
	f.Name = def.id
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.AutoButtonColor = false
	f.Text = ""
	f.Selectable = false
	f.BorderSizePixel = 0
	f.BackgroundColor3 = V.PANEL
	f.ZIndex = 5
	f.Visible = false
	f.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Thickness = if def.kind == "fire" then 2.5 else 1.5
	edge.Color = V.KHAKI
	edge.Parent = f
	local sc = Instance.new("UIScale")
	sc.Parent = f
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Size = UDim2.fromScale(0.8, 0.5)
	t.TextScaled = true
	t.FontFace = F.TITLE_MED
	t.TextColor3 = V.KHAKI
	t.Text = def.glyph
	t.ZIndex = 6
	t.Parent = f
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = if def.kind == "fire" then 20 else 15
	lim.MinTextSize = 7
	lim.Parent = t
	return {
		def = def,
		f = f,
		t = t,
		edge = edge,
		sc = sc,
		cx = 0,
		cy = 0,
		r = 24,
		alpha = 1,
		visible = false,
		down = false,
		latched = false,
	}
end

for _, def in Toque.BUTTONS do
	if def.kind ~= "stick" and def.kind ~= "slot" then
		btns[def.id] = makeButton(def)
	end
end

local function paint(b: Btn)
	local a = b.alpha
	local hot = b.down or b.latched
	b.f.BackgroundColor3 = if hot then V.OLIVE elseif b.def.kind == "fire" then V.BG_RED else V.PANEL
	b.f.BackgroundTransparency = 1 - a * (if hot then 0.8 else 0.5)
	b.edge.Color = if hot then V.BRASS elseif b.def.kind == "fire" then V.RED_HI else V.KHAKI
	b.edge.Transparency = 1 - a * 0.9
	b.t.TextTransparency = 1 - a
	b.t.TextColor3 = if hot then V.TEXT else V.KHAKI
	b.sc.Scale = if b.down then 0.92 else 1
end

-- analógico: anel da base, o pino, o lugar de repouso e o cadeado da corrida
local stickUi = {
	rest = circle(root, 3),
	base = circle(root, 3),
	knob = circle(root, 4),
	lock = Instance.new("TextLabel"),
}
do
	for _, f in { stickUi.rest, stickUi.base } do
		f.BackgroundColor3 = V.PANEL
		local e = Instance.new("UIStroke")
		e.Color = V.KHAKI
		e.Thickness = 1.5
		e.Transparency = 0.4
		e.Parent = f
	end
	stickUi.knob.BackgroundColor3 = V.KHAKI
	local l = stickUi.lock
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundColor3 = V.PANEL
	l.BackgroundTransparency = 0.3
	l.BorderSizePixel = 0
	l.FontFace = F.TITLE_MED
	l.TextScaled = true
	l.TextColor3 = V.KHAKI
	l.Text = "TRAVAR"
	l.ZIndex = 4
	l.Visible = false
	l.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = l
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 4)
	p.PaddingRight = UDim.new(0, 4)
	p.Parent = l
end

-- ===== estado =====
type Touch = { id: string, start: Vector2, last: Vector2, abs: Vector2, swiped: boolean }
local S = {
	active = false, -- o HUD trata o toque agora (inclui a roda aberta: o analógico segue andando)
	shown = false, -- o HUD está na tela
	forced = false, -- Studio: modo de toque forçado
	W = 800,
	H = 360,
	short = 390,
	R = 80, -- raio do analógico (px)
	swipePx = 50, -- deslizar para cima no botão de postura
	restPos = Vector2.zero,
	slots = {} :: { [string]: Toque.Slot },
	zone = Toque.zone(false),
	ctx = { foot = true, vehicle = false, downed = false, aiming = false, voice = false } :: Toque.Ctx,
	stickVisible = false,
	tracker = Toque.newTracker(),
	touches = {} :: { [any]: Touch },
	stick = Toque.newStick(),
	stickKey = nil :: any,
	stickBase = Vector2.zero,
	sprintWant = false,
	sprintNext = 0,
	vault = Toque.newVault(),
	fireCount = 0,
	aimLatched = false,
	aimLatchedAt = 0,
	giveUpT0 = nil :: number?,
	devStick = Vector2.zero,
	devStickUntil = 0,
}

-- ===== layout =====
local function relayout()
	local full = gui.AbsoluteSize
	if full.X < 10 or full.Y < 10 then
		-- ScreenGui desligada pode não ter medido ainda: a janela da câmera serve de reserva
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		full = cam.ViewportSize
	end
	S.short = math.min(full.X, full.Y)
	local m = math.floor(Toque.rawPx(Toque.MARGIN_MM, S.short) + 0.5)
	root.Position = UDim2.fromOffset(m, m)
	root.Size = UDim2.new(1, -2 * m, 1, -2 * m)
	S.W, S.H = full.X - 2 * m, full.Y - 2 * m
	S.swipePx = Toque.rawPx(8, S.short)
	local s = Input.settings
	S.slots = Toque.layout(s :: any)
	S.zone = Toque.zone(s.touchMirror)
	local opacity = s.touchOpacity
	for id, b in btns do
		local sl = S.slots[id]
		local size = Toque.buttonPx(b.def.mm, sl.scale, S.short)
		local cx, cy = Toque.place(sl.x, sl.y, size, S.W, S.H)
		b.cx, b.cy, b.r = cx, cy, size / 2
		b.alpha = sl.alpha * opacity
		b.f.Size = UDim2.fromOffset(size, size)
		b.f.Position = UDim2.fromOffset(cx, cy)
		paint(b)
	end
	-- analógico: o diâmetro do anel é o tamanho do botão "stick"
	local st = S.slots.stick
	local d = Toque.buttonPx(Toque.BY_ID.stick.mm, st.scale, S.short)
	S.R = d / 2
	local rx, ry = Toque.place(st.x, st.y, d, S.W, S.H)
	S.restPos = Vector2.new(rx, ry)
	stickUi.rest.Size = UDim2.fromOffset(d, d)
	stickUi.base.Size = UDim2.fromOffset(d, d)
	local k = math.floor(d * 0.42)
	stickUi.knob.Size = UDim2.fromOffset(k, k)
	stickUi.lock.Size = UDim2.fromOffset(math.floor(d * 0.62), math.floor(math.max(d * 0.2, 18)))
	-- vaga do botão contextual de interagir (T2 desenha)
	local it = S.slots.interact
	local isz = Toque.buttonPx(Toque.BY_ID.interact.mm, it.scale, S.short)
	local ix, iy = Toque.place(it.x, it.y, isz, S.W, S.H)
	gui:SetAttribute("InteractPos", root.AbsolutePosition + Vector2.new(ix, iy))
	gui:SetAttribute("InteractSize", isz)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
root:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
	local it = S.slots.interact
	if it then
		local isz = Toque.buttonPx(Toque.BY_ID.interact.mm, it.scale, S.short)
		local ix, iy = Toque.place(it.x, it.y, isz, S.W, S.H)
		gui:SetAttribute("InteractPos", root.AbsolutePosition + Vector2.new(ix, iy))
	end
end)
Input.SettingsChanged:Connect(relayout)
task.defer(relayout)

-- ===== contexto e visibilidade =====
local function refresh()
	local ctx = Input.context()
	local st = Input.state
	S.active = (Input.touchActive() or S.forced)
		and st.alive
		and not st.robloxMenu
		and not st.disconnected
		and not st.unfocused
		and ctx ~= "menu"
		and ctx ~= "map"
		and player.Character ~= nil
	local shown = S.active and ctx ~= "wheel"
	if shown ~= S.shown then
		S.shown = shown
		gui.Enabled = shown
		if shown then
			task.defer(relayout) -- a ScreenGui ligada mede de novo (janela pode ter mudado)
		end
	end
	local c = S.ctx
	c.vehicle = st.vehicle ~= nil
	c.downed = st.downed
	c.foot = not c.vehicle and not c.downed
	c.aiming = st.aiming
	c.voice = VozEstado.available
	for id, b in btns do
		local sl = S.slots[id]
		local vis = sl ~= nil and sl.on and Toque.visible(b.def, c)
		if vis ~= b.visible then
			b.visible = vis
			b.f.Visible = vis
		end
	end
	S.stickVisible = Toque.visible(Toque.BY_ID.stick, c)
	local iv = S.slots.interact ~= nil and S.slots.interact.on and c.foot
	if gui:GetAttribute("InteractVisible") ~= iv then
		gui:SetAttribute("InteractVisible", iv)
	end
end

local function hitList(): { Toque.HitButton }
	local out: { Toque.HitButton } = {}
	for id, b in btns do
		if b.visible then
			table.insert(out, { id = id, cx = b.cx, cy = b.cy, r = b.r })
		end
	end
	return out
end

-- Outro botão de interface (de uma tela por cima deste HUD) está sob o dedo? Então o toque é dele.
local function blockedByOther(p: Vector2): boolean
	local ok, list = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(p.X, p.Y)
	end)
	if not ok or type(list) ~= "table" then
		return false
	end
	for _, o in list do
		if not o:IsDescendantOf(gui) and (o:IsA("GuiButton") or o:IsA("TextBox")) then
			local sg = o:FindFirstAncestorWhichIsA("ScreenGui")
			if sg and sg.Enabled and sg.DisplayOrder >= gui.DisplayOrder then
				return true
			end
		end
	end
	return false
end

-- ===== ações de cada tipo de botão =====
-- dedo fora do DESISTIR (ou o HUD soltou tudo)
local function giveUpStop()
	S.giveUpT0 = nil
	if Input.virtualDown("give_up") then
		Input.virtual("give_up", false)
	end
end

-- caído: segurar 1 s desiste (como o B segurado). Enquanto o dedo está no botão,
-- Input.virtualDown("give_up") responde que sim e a tela de queda (CasualtyScreen) enche o anel; a
-- ação só sai ao fim de 1 s.
local function giveUpStart(abs: Vector2)
	local t0 = os.clock()
	S.giveUpT0 = t0
	Input.virtualHold("give_up", abs)
	task.delay(1, function()
		if S.giveUpT0 == t0 and Input.state.downed then
			Input.virtual("give_up", true, abs)
		end
	end)
end

local function stance(): string
	local c = player.Character
	if c and c:GetAttribute("Prone") then
		return "prone"
	elseif c and c:GetAttribute("Crouched") then
		return "crouch"
	end
	return "stand"
end

-- pular: o Movement transpõe (perto de obstáculo baixo) ou levanta (agachado/deitado); de pé e sem
-- obstáculo, o Humanoid pula (no toque programável o PlayerModule não tem botão de pulo)
local function jump()
	Input.virtual("jump", true)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if
		hum
		and InputMap.allowed(Input.state, "jump")
		and player:GetAttribute("Vaulting") ~= true
		and stance() == "stand"
	then
		hum.Jump = true
	end
end

-- deslizar para cima no botão de postura levanta (o pular de agachado/deitado levanta)
local function standUp()
	if stance() ~= "stand" then
		Input.virtual("jump", true)
		Input.virtual("jump", false)
	end
end

local function aimEvent(down: boolean)
	local s = Input.settings
	local ops, latched = Toque.aimOps(s.touchAimToggle, s.aimToggle, S.aimLatched, down)
	if latched and not S.aimLatched then
		S.aimLatchedAt = os.clock()
	end
	S.aimLatched = latched
	for _, v in ops do
		Input.virtual("aim", v)
	end
	if down then
		Toque.unlock(S.stick)
	end
	local b = btns.aim
	if b then
		b.latched = latched
		paint(b)
	end
end

local function setLatch(b: Btn, on: boolean)
	if b.latched == on then
		return
	end
	b.latched = on
	Input.virtual(b.def.spec or "", on)
	paint(b)
end

-- inclinar: um toque inclina, outro volta (o polegar esquerdo não segura enquanto anda)
local function toggleLatch(b: Btn)
	if b.latched then
		setLatch(b, false)
		return
	end
	for _, o in btns do
		if o ~= b and o.def.kind == "latch" and o.latched then
			setLatch(o, false)
		end
	end
	setLatch(b, true)
end

local function buttonDown(b: Btn, t: Touch)
	local d = b.def
	b.down = true
	if d.kind == "fire" then
		S.fireCount += 1
		if S.fireCount == 1 then
			Toque.unlock(S.stick)
			Input.virtual("fire", true)
		end
	elseif d.kind == "aim" then
		aimEvent(true)
	elseif d.kind == "latch" then
		toggleLatch(b)
	elseif d.kind == "jump" then
		jump()
	elseif d.kind == "giveup" then
		giveUpStart(t.abs)
	else -- press, posture, wheel
		Input.virtual(d.spec or "", true, t.abs)
	end
	paint(b)
end

local function buttonUp(b: Btn, t: Touch)
	local d = b.def
	b.down = false
	if d.kind == "fire" then
		S.fireCount = math.max(0, S.fireCount - 1)
		if S.fireCount == 0 then
			Input.virtual("fire", false)
		end
	elseif d.kind == "aim" then
		aimEvent(false)
	elseif d.kind == "latch" then
		-- liga/desliga no aperto
	elseif d.kind == "jump" then
		Input.virtual("jump", false)
	elseif d.kind == "giveup" then
		giveUpStop()
	else
		Input.virtual(d.spec or "", false, t.abs)
	end
	paint(b)
end

-- ===== toques =====
local function began(key: any, abs: Vector2)
	if not S.shown or S.touches[key] then
		return
	end
	if blockedByOther(abs) then
		return
	end
	local lp = abs - root.AbsolutePosition
	local hit = Toque.hit(lp.X, lp.Y, S.W, S.H, hitList(), S.zone)
	if hit == "stick" and not S.stickVisible then
		hit = "camera"
	end
	local id = Toque.claim(S.tracker, key, hit)
	local t: Touch = { id = id, start = lp, last = lp, abs = abs, swiped = false }
	S.touches[key] = t
	if id == "stick" then
		Toque.stickBegan(S.stick) -- tocar no analógico destrava a corrida
		S.stickKey = key
		S.stickBase = lp
		return
	end
	local b = btns[id]
	if b then
		buttonDown(b, t)
	end
end

local function moved(key: any, abs: Vector2)
	local t = S.touches[key]
	if not t then
		return
	end
	local lp = abs - root.AbsolutePosition
	local delta = lp - t.last
	t.last, t.abs = lp, abs
	local id = t.id
	if id == "camera" or id == "fire" then
		if S.active then
			Input.addLook(delta)
		end
		return
	end
	local b = btns[id]
	if not b then
		return
	end
	if b.def.kind == "wheel" then
		Input.virtualMove(b.def.spec or "", abs)
	elseif b.def.kind == "posture" and not t.swiped and t.start.Y - lp.Y >= S.swipePx then
		t.swiped = true
		Input.virtualCancel(b.def.spec or "")
		standUp()
	end
end

local function ended(key: any)
	local t = S.touches[key]
	if not t then
		return
	end
	S.touches[key] = nil
	Toque.release(S.tracker, key)
	if t.id == "stick" then
		if S.stickKey == key then
			S.stickKey = nil
		end
		return
	end
	local b = btns[t.id]
	if b then
		buttonUp(b, t)
	end
end

-- Solta tudo. viaInput = false quando o próprio Input já soltou (app fora de foco).
local function resetAll(viaInput: boolean)
	if viaInput then
		for key in S.touches do
			ended(key)
		end
		if S.aimLatched then
			Input.virtual("aim", false)
		end
		for _, b in btns do
			if b.latched and b.def.kind == "latch" then
				Input.virtual(b.def.spec or "", false)
			end
		end
		if Input.virtualDown("sprint") then
			Input.virtual("sprint", false)
		end
	end
	table.clear(S.touches)
	Toque.releaseAll(S.tracker)
	S.stickKey = nil
	S.fireCount = 0
	S.aimLatched = false
	for _, b in btns do
		b.latched, b.down = false, false
		paint(b)
	end
	Toque.unlock(S.stick)
	S.stick.sprint = false
	S.devStickUntil = 0
	Input.setVirtualStick("left", Vector2.zero)
	giveUpStop()
end

Input.TouchReset:Connect(function(why: string)
	if why == "device" then
		resetAll(true)
	elseif why == "focus" then
		resetAll(false)
	end
	refresh()
end)

local function pos2(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

UserInputService.TouchStarted:Connect(function(touch: InputObject)
	began(touch, pos2(touch))
end)
UserInputService.TouchMoved:Connect(function(touch: InputObject)
	moved(touch, pos2(touch))
end)
UserInputService.TouchEnded:Connect(function(touch: InputObject)
	ended(touch)
end)

-- Studio, modo forçado sem aparelho: o botão esquerdo do mouse faz de dedo
local function mouseAsTouch(): boolean
	return S.forced and not UserInputService.TouchEnabled
end
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and mouseAsTouch() then
		began("mouse", pos2(input))
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseMovement and S.touches.mouse then
		moved("mouse", pos2(input))
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and S.touches.mouse then
		ended("mouse")
	end
end)

-- menu, mapa, morte, veículo cancelam o inclinar: o botão destrava
Input.StateChanged:Connect(function(cancelled: { string })
	if table.find(cancelled, "lean") then
		for _, b in btns do
			if b.latched and b.def.kind == "latch" then
				setLatch(b, false)
			end
		end
	end
end)

-- ===== quadro =====
-- corrida pelo analógico: com "alternar" (padrão) um aperto liga/desliga; com "segurar", o aperto
-- virtual fica seguro enquanto a corrida é pedida
local function syncSprint()
	local want = S.sprintWant
	local holdMode = not Input.settings.sprintToggle
	if holdMode and not want and Input.virtualDown("sprint") then
		Input.virtual("sprint", false)
	end
	local on = Input.state.sprinting
	local now = os.clock()
	if want == on or now < S.sprintNext or not InputMap.acceptsGame(Input.state) then
		return
	end
	if
		want
		and (
			player:GetAttribute("Exhausted") == true
			or player:GetAttribute("StanceBusy") == true
			or player:GetAttribute("Aiming") == true
			or player:GetAttribute("Vaulting") == true
		)
	then
		return -- o InfantryController recusaria (e avisaria "Sem fôlego" a cada tentativa)
	end
	S.sprintNext = now + 0.35
	if holdMode then
		Input.virtual("sprint", false)
		if want then
			Input.virtual("sprint", true)
		end
	else
		Input.virtual("sprint", true)
		Input.virtual("sprint", false)
	end
end

local function autoVault(dt: number, y: number)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local rootPart = c and c:FindFirstChild("HumanoidRootPart")
	if not (hum and rootPart and rootPart:IsA("BasePart")) then
		return
	end
	local v = rootPart.AssemblyLinearVelocity
	local real = Vector2.new(v.X, v.Z).Magnitude
	local go = Toque.autoVault(S.vault, dt, os.clock(), {
		enabled = Input.settings.touchAutoVault and S.shown and S.ctx.foot,
		sprinting = Input.state.sprinting,
		forward = y > 0.7,
		grounded = hum.FloorMaterial ~= Enum.Material.Air,
		speedRatio = real / math.max(hum.WalkSpeed, 1),
	})
	if go and player:GetAttribute("Vaulting") ~= true and stance() == "stand" then
		Input.virtual("jump", true) -- o Movement transpõe se houver obstáculo baixo; senão nada
		Input.virtual("jump", false)
	end
end

local function drawStick(touching: boolean, d: Vector2)
	local alpha = Input.settings.touchOpacity * (if S.slots.stick then S.slots.stick.alpha else 1)
	local vis = S.shown and S.stickVisible
	stickUi.rest.Visible = vis and not touching
	stickUi.base.Visible = vis and touching
	stickUi.knob.Visible = vis
	local base = if touching then S.stickBase else S.restPos
	stickUi.rest.Position = UDim2.fromOffset(S.restPos.X, S.restPos.Y)
	stickUi.rest.BackgroundTransparency = 1 - alpha * 0.15
	stickUi.base.Position = UDim2.fromOffset(base.X, base.Y)
	stickUi.base.BackgroundTransparency = 1 - alpha * 0.3
	local k = d
	if k.Magnitude > S.R then
		k = k.Unit * S.R
	end
	if S.stick.inLock then
		k = Vector2.new(0, -S.R)
	end
	local kp = if touching then base + k else base
	stickUi.knob.Position = UDim2.fromOffset(kp.X, kp.Y)
	stickUi.knob.BackgroundTransparency = 1 - alpha * (if touching then 0.7 else 0.35)
	-- cadeado: aparece quando o dedo vai para a frente; aceso dentro dele ou travado
	local lockOn = S.stick.locked
	local near = touching and -d.Y > 0.6 * S.R
	local l = stickUi.lock
	l.Visible = vis and (near or lockOn)
	if l.Visible then
		local lp = base + Vector2.new(0, -Toque.LOCK_K * S.R)
		l.Position = UDim2.fromOffset(lp.X, lp.Y)
		local txt = if lockOn and not touching then "CORRENDO" else "TRAVAR"
		if l.Text ~= txt then
			l.Text = txt
		end
		l.TextColor3 = if lockOn or S.stick.inLock then V.BRASS else V.KHAKI
		l.TextTransparency = 1 - alpha
		l.BackgroundTransparency = 1 - alpha * 0.6
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	refresh()
	-- toques que o sistema encerrou sem o evento de fim
	for key in S.touches do
		if typeof(key) == "InputObject" then
			local st = (key :: InputObject).UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				ended(key)
			end
		end
	end
	-- a trava da corrida é só a pé e em jogo: menu, mapa, veículo, caído ou morto destravam (no
	-- veículo o analógico dirige; a trava empurraria o carro)
	if not (S.active and S.ctx.foot) then
		Toque.unlock(S.stick)
	end
	-- analógico
	local touching = S.stickKey ~= nil
	local d = Vector2.zero
	if touching then
		local t = S.touches[S.stickKey]
		if t then
			d = t.last - S.stickBase
		else
			touching = false
		end
	elseif os.clock() < S.devStickUntil then
		touching = true
		d = S.devStick * S.R
	end
	local x, y, sprint = Toque.stickStep(S.stick, touching, d.X, d.Y, S.R)
	if not (S.active and S.stickVisible) then
		x, y, sprint = 0, 0, false
	end
	if Input.touchActive() then
		Input.setVirtualStick("left", Vector2.new(x, y))
	end
	S.sprintWant = sprint and S.ctx.foot and not Input.state.aiming
	if Input.touchActive() then
		syncSprint()
		autoVault(dt, y)
	end
	drawStick(touching and S.stickKey ~= nil, d)
	-- mira travada que outro sistema desligou (binóculo, transpor, golpe): o botão destrava
	if S.aimLatched and not Input.state.aiming and os.clock() - S.aimLatchedAt > 0.3 then
		S.aimLatched = false
		Input.virtual("aim", false)
		local b = btns.aim
		if b then
			b.latched = false
			paint(b)
		end
	end
end)

-- ===== Studio: VT65DevToque =====
local function devTap(id: string, seconds: number)
	local b = btns[id]
	if not b then
		print(string.format("[VT65 TOQUE] botão desconhecido: %s", id))
		return
	end
	local t: Touch = {
		id = id,
		start = Vector2.new(b.cx, b.cy),
		last = Vector2.new(b.cx, b.cy),
		abs = root.AbsolutePosition + Vector2.new(b.cx, b.cy),
		swiped = false,
	}
	buttonDown(b, t)
	task.delay(seconds, function()
		buttonUp(b, t)
	end)
end

local function devState()
	local vis = {}
	for id, b in btns do
		if b.visible then
			table.insert(vis, id)
		end
	end
	table.sort(vis)
	local own = 0
	for _ in S.touches do
		own += 1
	end
	local s = Input.settings
	print(
		string.format(
			"[VT65 TOQUE] toque=%s forçado=%s HUD=%s ctx=%s layout=%s espelho=%s área=%dx%d analógico=%d px (travado=%s, corrida=%s) toques=%d mira travada=%s | visíveis: %s",
			tostring(Input.touchActive()),
			tostring(S.forced),
			tostring(S.shown),
			Input.context(),
			s.touchLayout,
			tostring(s.touchMirror),
			S.W,
			S.H,
			math.floor(S.R * 2),
			tostring(S.stick.locked),
			tostring(Input.state.sprinting),
			own,
			tostring(S.aimLatched),
			table.concat(vis, ", ")
		)
	)
end

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevToque"):Connect(function()
		local v = workspace:GetAttribute("VT65DevToque")
		if type(v) ~= "string" or v == "" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevToque", nil)
		end)
		local now = os.clock()
		if v == "forcar" then
			S.forced = true
			Input.devForceTouch(true)
		elseif v == "normal" then
			S.forced = false
			Input.devForceTouch(false)
		elseif v == "fundo" then
			Input.focusLost()
		elseif v == "volta" then
			Input.focusBack()
		elseif v == "correr" or v == "andar" or v == "devagar" then
			local k = if v == "correr" then 1 elseif v == "andar" then 0.5 else 0.25
			S.devStick = Vector2.new(0, -k)
			S.devStickUntil = now + 2
		elseif v == "trava" then
			S.stick.locked = true
		elseif string.sub(v, 1, 6) == "botao:" then
			devTap(string.sub(v, 7), 0.12)
		elseif string.sub(v, 1, 8) == "segurar:" then
			local id, secs = string.match(v, "^segurar:([%w_]+):([%d%.]+)$")
			if id and secs then
				devTap(id, tonumber(secs) or 1)
			end
		elseif string.sub(v, 1, 6) == "olhar:" then
			local dx, dy = string.match(v, "^olhar:([%-%d%.]+),([%-%d%.]+)$")
			Input.addLook(Vector2.new(tonumber(dx) or 0, tonumber(dy) or 0))
		elseif string.sub(v, 1, 7) == "layout:" then
			Input.setSetting("touchLayout", string.sub(v, 8))
		elseif v == "espelho" then
			Input.setSetting("touchMirror", not Input.settings.touchMirror)
		elseif v == "estado" then
			devState()
			return
		end
		task.delay(0.3, devState)
	end)
end
