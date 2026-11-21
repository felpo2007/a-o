--!strict
-- Botões de toque dos veículos (Parte 13, T3). Só aparecem com o toque como entrada principal
-- (Input.touchActive), sentado num veículo, fora de menu, mapa e menu do Roblox. O analógico
-- flutuante da esquerda (T1) continua valendo dentro do veículo: dirige o blindado e é o cíclico do
-- UH-34D (VehicleController lê Input.move). Arrastar no resto da tela olha, gira a torre e mira a
-- porta (é a câmera, como no PC). Cada botão aperta a ação do InputMap pelo Input.virtual, o mesmo
-- caminho do botão físico: o VehicleController recebe pelos handlers de sempre.
-- v39 (dono: "muitos botões na tela do celular, deixe somente os importantes; o resto automático"):
--   motorista e comandante: lugar e sair;
--   atirador e porta: só o tiro (16 mm; arrastar o próprio botão também mira). No canhão de 90 mm
--     e no 106 mm, segurar mira pela ótica e soltar dispara; um toque rápido dispara direto. Os tubos
--     do Ontos recarregam sozinhos com o veículo parado; o 90 mm fica na explosiva;
--   piloto do UH-34D: alavanca do coletivo à direita (o polegar arrasta de onde ela está; a marca de
--     latão é o pairado). Pedais e estabilizador saíram da tela: o analógico de lado vira o nariz
--     devagar e o estabilizador fica sempre ligado (PilotoToque.touchYaw, VehicleController);
--   todos: lugar (painel de lugares) e sair (segurar ~0,45 s: ninguém pula do helicóptero sem querer).
-- Coaxial, binóculo, marcar e trocar a munição ficam no controle e no teclado.
-- Tamanho físico pelo Shared/Toque do T1 (Toque.rawPx); sem ele, PilotoToque.mmToPx (o mesmo
-- palpite). Disposição em PilotoToque.layout (testada): tudo na metade direita, à esquerda do rádio
-- do HUD do T1 no alto, espelhado com touchMirror. Esta tela fica por cima do HUD do T1 (ordem 14 >
-- 4): o toque num botão daqui é daqui; no vazio, é do T1 (câmera ou analógico).
-- Studio (Device Emulator): workspace:SetAttribute("VT65DevTela", "toqueveiculo") mostra motorista,
-- atirador, comandante e porta (4 s cada); "helicoptero" mostra o piloto por 10 s.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Input = require(script.Parent.Input)
local PilotoToque = require(script.Parent.PilotoToque)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local L = PilotoToque.lever

local gui = UiKit.screen("VT65ToqueVeiculo", 14)
gui.Enabled = false
local root = Instance.new("Frame")
root.Name = "Botoes"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Active = false -- o vazio deixa o arrasto chegar à câmera
root.Parent = gui

-- ===== contrato com o T1 (protegido enquanto não existir) =====
local function touchOn(): boolean
	local f = (Input :: any).touchActive
	if type(f) == "function" then
		return f() == true
	end
	return Input.device() == "touch"
end

local warned = false
local function virtual(id: string, down: boolean)
	local f = (Input :: any).virtual
	if type(f) == "function" then
		f(id, down)
	elseif not warned and RunService:IsStudio() then
		warned = true
		warn("[VT65] Input.virtual ainda não existe (T1): os botões de toque do veículo não agem")
	end
end

local function setting(key: string): any
	return (Input.settings :: any)[key]
end

-- Shared/Toque do T1 (tamanho físico e o layout do HUD de toque dele); false se não carregar
local toque: any = nil
local function toqueMod(): any
	if toque == nil then
		local m = ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("Toque")
		local ok, mod = false, nil
		if m and m:IsA("ModuleScript") then
			ok, mod = pcall(require, m)
		end
		toque = if ok and type(mod) == "table" then mod else false
	end
	return toque
end

local function shortSide(): number
	local a = root.AbsoluteSize
	return math.max(math.min(a.X, a.Y), 1)
end

-- mm → px da interface sem limites (a disposição cuida dos mínimos): Toque.rawPx do T1, o mesmo
-- palpite de pontos por polegada do PilotoToque.mmToPx (a reserva)
local function mmPx(mm: number): number
	local short = shortSide()
	local T = toqueMod()
	if T and type(T.rawPx) == "function" then
		local ok, r = pcall(T.rawPx, mm, short, nil)
		if ok and type(r) == "number" and r >= mm * 2 and r <= mm * 20 then
			return math.floor(r + 0.5)
		end
	end
	return PilotoToque.mmToPx(mm, short)
end

-- O rádio do HUD de toque do T1 fica no alto à direita também no veículo: o retângulo dele (px da
-- área), no layout que o jogador escolheu, para a fileira de lugar/sair ficar à esquerda dele.
local function radioRect(W: number, H: number): PilotoToque.Rect?
	local T = toqueMod()
	if not T then
		return nil
	end
	local ok, r = pcall(function(): PilotoToque.Rect?
		local slot = T.layout(Input.settings :: any, false).radio
		local def = T.BY_ID.radio
		if not (slot and def and slot.on ~= false) then
			return nil
		end
		local size = T.buttonPx(def.mm, slot.scale, math.min(W, H), nil)
		local cx, cy = T.place(slot.x, slot.y, size, W, H)
		return { x = cx - size / 2, y = cy - size / 2, w = size, h = size }
	end)
	return if ok then r else nil
end

-- ===== botões =====
type Btn = {
	name: string,
	button: TextButton,
	stroke: UIStroke,
	label: TextLabel,
	marks: { GuiObject }, -- desenho do glifo (retícula, setas)
	rings: { UIStroke },
	action: string?,
	mode: string, -- "hold" | "exit" | "aimfire" (canhão: segurar mira, soltar dispara)
	on: boolean, -- ligado (botão de alternar)
	io: InputObject?, -- o dedo que segura
	down: boolean,
	lit: boolean, -- pintado aceso agora
	danger: boolean,
}

local buttons: { [string]: Btn } = {}
local held: { [InputObject]: Btn } = {}

local function opacity(): number
	local o = setting("touchOpacity")
	return if type(o) == "number" then math.clamp(o, 0.2, 1) else 0.75
end

local function paint(b: Btn)
	local op = opacity()
	local lit = b.down or b.on
	b.lit = lit
	b.button.BackgroundColor3 = if lit then (if b.danger then V.RED else V.OLIVE) else V.PANEL
	b.button.BackgroundTransparency = if lit then 1 - op * 0.95 else 1 - op * 0.7
	b.stroke.Transparency = 1 - op * 0.75
	b.label.TextTransparency = 1 - op
	for _, g in b.marks do
		g.BackgroundTransparency = 1 - op
	end
	for _, r in b.rings do
		r.Transparency = 1 - op
	end
end

local function make(name: string, text: string, round: boolean, danger: boolean?): Btn
	local t = Instance.new("TextButton")
	t.Name = name
	t.Text = ""
	t.AutoButtonColor = false
	t.BorderSizePixel = 0
	t.Visible = false
	t.Selectable = false
	t.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0, 6)
	c.Parent = t
	local s = UiKit.stroke(t, V.TEXT, 1.5, 0.3)
	local label = UiKit.text2(t, text, 16, V.TEXT, F.TITLE_MED)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.84, 0.5)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextScaled = true
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = 17
	lim.MinTextSize = 8
	lim.Parent = label
	local b: Btn = {
		name = name,
		button = t,
		stroke = s,
		label = label,
		marks = {},
		rings = {},
		action = nil,
		mode = "hold",
		on = false,
		io = nil,
		down = false,
		lit = false,
		danger = danger == true,
	}
	buttons[name] = b
	return b
end

local function mark(b: Btn, pos: UDim2, size: UDim2, rot: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = size
	f.Rotation = rot or 0
	f.BackgroundColor3 = V.TEXT
	f.BorderSizePixel = 0
	f.Parent = b.button
	table.insert(b.marks, f)
	return f
end

-- retícula do tiro: anel e quatro traços
local function reticle(b: Btn)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.42, 0.42)
	ring.BackgroundTransparency = 1
	ring.Parent = b.button
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = ring
	table.insert(b.rings, UiKit.stroke(ring, V.TEXT, 2.5, 0))
	mark(b, UDim2.fromScale(0.5, 0.2), UDim2.new(0, 3, 0.14, 0))
	mark(b, UDim2.fromScale(0.5, 0.8), UDim2.new(0, 3, 0.14, 0))
	mark(b, UDim2.fromScale(0.2, 0.5), UDim2.new(0.14, 0, 0, 3))
	mark(b, UDim2.fromScale(0.8, 0.5), UDim2.new(0.14, 0, 0, 3))
	mark(b, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(4, 4))
end

-- v39: só o essencial na tela (o resto é automático ou fica no controle e no teclado)
make("exit", "SAIR", false, true)
make("seat", "LUGAR", false)
reticle(make("fire", "", true, true))
buttons.exit.mode = "exit"
buttons.exit.action = "v_exit"
buttons.seat.action = "v_switch_seat"

-- sair: segurar enche a barra; cheia, aperta a ação
local exitBar = Instance.new("Frame")
exitBar.Name = "Segurar"
exitBar.AnchorPoint = Vector2.new(0, 1)
exitBar.Position = UDim2.fromScale(0, 1)
exitBar.Size = UDim2.new(0, 0, 0, 4)
exitBar.BackgroundColor3 = V.BRASS
exitBar.BorderSizePixel = 0
exitBar.Parent = buttons.exit.button
local exitHold = UiKit.hold(exitBar, 0.45, function()
	virtual("v_exit", true)
	task.delay(0.1, function()
		virtual("v_exit", false)
	end)
end)

-- ===== alavanca do coletivo =====
local track = Instance.new("TextButton")
track.Name = "Coletivo"
track.Text = ""
track.AutoButtonColor = false
track.BorderSizePixel = 0
track.BackgroundColor3 = V.PANEL
track.Visible = false
track.Selectable = false
track.Parent = root
UiKit.corner(track, 6)
local trackStroke = UiKit.stroke(track, V.TEXT, 1.5, 0.3)
local fill = Instance.new("Frame")
fill.AnchorPoint = Vector2.new(0, 1)
fill.Position = UDim2.fromScale(0, 1)
fill.Size = UDim2.fromScale(1, 0.5)
fill.BackgroundColor3 = V.OLIVE
fill.BorderSizePixel = 0
fill.Parent = track
UiKit.corner(fill, 6)
local hoverMark = Instance.new("Frame")
hoverMark.AnchorPoint = Vector2.new(0, 0.5)
hoverMark.Size = UDim2.new(1, 0, 0, 3)
hoverMark.BackgroundColor3 = V.BRASS
hoverMark.BorderSizePixel = 0
hoverMark.Visible = false
hoverMark.Parent = track
local handle = Instance.new("Frame")
handle.AnchorPoint = Vector2.new(0.5, 0.5)
handle.Size = UDim2.new(1, 10, 0, 14)
handle.BackgroundColor3 = V.TEXT
handle.BorderSizePixel = 0
handle.Parent = track
UiKit.corner(handle, 4)
local trackLabel = UiKit.kicker(root, "COLETIVO", 12, V.TEXT)
trackLabel.TextXAlignment = Enum.TextXAlignment.Center
trackLabel.Visible = false
local leverIo: InputObject? = nil

local function paintLever()
	local op = opacity()
	track.BackgroundTransparency = 1 - op * 0.7
	trackStroke.Transparency = 1 - op * 0.75
	fill.BackgroundTransparency = 1 - op * 0.8
	handle.BackgroundTransparency = 1 - op
	hoverMark.BackgroundTransparency = 1 - op
	trackLabel.TextTransparency = 1 - op
end

local function releaseLever()
	leverIo = nil
	PilotoToque.release(L)
end

-- ===== apertar e soltar =====
local function pointer(io: InputObject): boolean
	return io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1
end

-- v39: canhão no toque: segurar passa de AIM_HOLD_S e liga a ótica; soltar dispara e desliga
local aim = { pressN = 0, zoom = false }

local function aimRelease()
	if aim.zoom then
		aim.zoom = false
		virtual("v_optic", false)
	end
end

local function press(b: Btn, down: boolean)
	local id = b.action
	if not id then
		return
	end
	if b.mode == "exit" then
		if down then
			exitHold.start()
		else
			exitHold.stop()
		end
	elseif b.mode == "aimfire" then
		aim.pressN += 1
		if down then
			local n = aim.pressN
			task.delay(PilotoToque.AIM_HOLD_S, function()
				if aim.pressN == n and b.down and not aim.zoom then
					aim.zoom = true
					virtual("v_optic", true)
				end
			end)
		else
			virtual(id, true)
			task.delay(0.08, function()
				virtual(id, false)
			end)
			aimRelease()
		end
	else
		virtual(id, down)
	end
end

-- Arrastar o próprio botão de tiro também mira (como o tiro da infantaria no HUD do T1): o atirador
-- de porta segura a M60 e acompanha o alvo com o mesmo polegar.
local aimFrom: { [InputObject]: Vector2 } = {}

local function startPress(b: Btn, io: InputObject)
	if b.io or not b.button.Visible then
		return
	end
	b.io = io
	held[io] = b
	if b.name == "fire" then
		aimFrom[io] = Vector2.new(io.Position.X, io.Position.Y)
	end
	b.down = true
	paint(b)
	press(b, true)
end

local function endPress(io: InputObject)
	local b = held[io]
	if not b then
		return
	end
	held[io] = nil
	aimFrom[io] = nil
	b.io = nil
	b.down = false
	paint(b)
	press(b, false)
end

for _, b in buttons do
	b.button.InputBegan:Connect(function(io: InputObject)
		if pointer(io) then
			startPress(b, io)
		end
	end)
end

track.InputBegan:Connect(function(io: InputObject)
	if pointer(io) and not leverIo then
		leverIo = io
		PilotoToque.grab(L, io.Position.Y, L.value)
	end
end)

local function ended(io: InputObject)
	if held[io] then
		endPress(io)
	elseif io.UserInputType == Enum.UserInputType.MouseButton1 then
		for k in held do
			if k.UserInputType == Enum.UserInputType.MouseButton1 then
				endPress(k)
			end
		end
	end
	local li = leverIo
	if
		li
		and (io == li or (io.UserInputType == Enum.UserInputType.MouseButton1 and li.UserInputType == io.UserInputType))
	then
		releaseLever()
	end
end
UserInputService.InputEnded:Connect(ended)
UserInputService.TouchEnded:Connect(ended)

UserInputService.InputChanged:Connect(function(io: InputObject)
	local from = aimFrom[io]
	if from then
		local p = Vector2.new(io.Position.X, io.Position.Y)
		aimFrom[io] = p
		local addLook = (Input :: any).addLook
		if type(addLook) == "function" then
			addLook(p - from) -- o CameraLook do T1 aplica com a sensibilidade do toque
		end
		return
	end
	local li = leverIo
	if not li then
		return
	end
	local mouseDrag = li.UserInputType == Enum.UserInputType.MouseButton1
		and io.UserInputType == Enum.UserInputType.MouseMovement
	if io == li or mouseDrag then
		PilotoToque.drag(L, io.Position.Y, track.AbsoluteSize.Y)
	end
end)

-- solta tudo (sumiu, trocou de lugar, abriu menu): nada fica apertado sem dedo
local function releaseAll()
	-- sumiu no meio da mira do canhão: não dispara, só desliga a ótica
	aim.pressN += 1
	for io, b in held do
		if b.mode == "aimfire" then
			held[io] = nil
			aimFrom[io] = nil
			b.io = nil
			b.down = false
		end
	end
	aimRelease()
	for io in held do
		endPress(io)
	end
	for _, b in buttons do
		if b.lit ~= (b.down or b.on) then
			paint(b)
		end
	end
	exitHold.stop()
	releaseLever()
end

-- ===== disposição =====
local dev = { untilT = 0, role = "", kind = "", weapon = nil :: string?, personal = false }

type SeatInfo = { role: string, kind: string, weapon: string?, personal: boolean }

local function current(): SeatInfo?
	if os.clock() < dev.untilT then
		return { role = dev.role, kind = dev.kind, weapon = dev.weapon, personal = dev.personal }
	end
	local kind = Input.state.vehicle
	local s = Input.state
	if not kind or not touchOn() or s.menus > 0 or s.map or not s.alive or s.robloxMenu then
		return nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local w = seat and seat:GetAttribute("Weapon")
	local id = Input.seat
	local role = if id == "driver"
		then (if kind == "helicopter" then "pilot" else "driver")
		elseif id == "gunner" or id == "commander" or id == "door" then id
		else "passenger"
	return {
		role = role,
		kind = kind,
		weapon = if type(w) == "string" then w else nil,
		personal = seat ~= nil and seat:GetAttribute("Personal") == true,
	}
end

local laidOut = ""

local function place(o: GuiObject, r: PilotoToque.Rect?)
	if r then
		o.Position = UDim2.fromOffset(r.x, r.y)
		o.Size = UDim2.fromOffset(r.w, r.h)
		o.Visible = true
	else
		o.Visible = false
	end
end

local function layout(st: SeatInfo)
	local a = root.AbsoluteSize
	if a.X < 10 or a.Y < 10 then
		return -- a tela acabou de ligar: o tamanho chega no próximo quadro
	end
	local mirror = setting("touchMirror") == true
	local key = string.format(
		"%s|%s|%s|%s|%d|%d|%s",
		st.role,
		st.kind,
		st.weapon or "",
		tostring(st.personal),
		a.X,
		a.Y,
		tostring(mirror)
	)
	if key == laidOut then
		return
	end
	releaseAll()
	laidOut = key
	local armed = st.weapon ~= nil or st.personal
	local rects = PilotoToque.layout(st.role, a.X, a.Y, {
		fire = armed or st.role == "door",
		mirror = mirror,
		avoid = radioRect(a.X, a.Y),
	}, mmPx)
	-- ação do tiro do lugar; canhão: segurar mira, soltar dispara (a arma do ocupante atira no aperto)
	buttons.fire.action = if st.role == "door" then "v_door_fire" else "v_fire"
	buttons.fire.mode = if PilotoToque.aimOnHold(st.weapon) and not st.personal then "aimfire" else "hold"
	for name, b in buttons do
		place(b.button, rects[name])
		paint(b)
	end
	place(track, rects.lever)
	place(trackLabel, rects.leverLabel)
	paintLever()
end

-- v39: tubos do Ontos recarregam sozinhos no toque com o veículo parado (o mesmo pedido do X)
local reload = { last = -math.huge }
local function autoReload(st: SeatInfo)
	if st.weapon ~= "rr_106" or st.personal or os.clock() < dev.untilT then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local model = seat and seat:FindFirstAncestorWhichIsA("Model")
	local chassis = model and model:FindFirstChild("Chassis")
	if not (model and chassis and chassis:IsA("BasePart")) then
		return
	end
	local tubes = model:GetAttribute("Tubes")
	local now = os.clock()
	local due = PilotoToque.autoReload(
		if type(tubes) == "number" then tubes else nil,
		6, -- tubos do M50 (VehicleService.GUNS.rr_106.tubes)
		chassis.AssemblyLinearVelocity.Magnitude * 0.28,
		model:GetAttribute("Reloading") == true,
		now - reload.last
	)
	if due then
		reload.last = now
		virtual("v_ammo", true)
		task.delay(0.1, function()
			virtual("v_ammo", false)
		end)
	end
end

-- ===== laço =====
RunService.Heartbeat:Connect(function()
	local st = current()
	if not st then
		if gui.Enabled then
			releaseAll()
			gui.Enabled = false
			laidOut = ""
		end
		return
	end
	if not gui.Enabled then
		gui.Enabled = true
	end
	layout(st)
	autoReload(st)
	for _, b in buttons do
		if b.button.Visible and b.lit ~= (b.down or b.on) then
			paint(b)
		end
	end
	if track.Visible then
		local v = math.clamp(L.value, 0, 1)
		fill.Size = UDim2.fromScale(1, v)
		handle.Position = UDim2.fromScale(0.5, 1 - v)
		local hv = L.hover
		hoverMark.Visible = hv ~= nil and hv >= 0 and hv <= 1
		if hv then
			hoverMark.Position = UDim2.fromScale(0, 1 - math.clamp(hv, 0, 1))
		end
	end
end)

-- troca de contexto (menu, lugar, morte): o Input solta as ações; aqui as teclas da tela também
Input.StateChanged:Connect(function()
	releaseAll()
end)
Input.SettingsChanged:Connect(function()
	laidOut = "" -- opacidade, espelho, layout do T1 e ótica de alternar refazem a tela
end)
-- app em segundo plano, ligação, troca de aparelho (Input.TouchReset do T1): o dedo some sem o fim
-- do toque; solta tudo
do
	local reset = (Input :: any).TouchReset
	if typeof(reset) == "RBXScriptSignal" then
		reset:Connect(function()
			releaseAll()
		end)
	end
end

-- ===== gancho de teste (só no Studio, Device Emulator) =====
if RunService:IsStudio() then
	local function show(role: string, kind: string, weapon: string?, seconds: number)
		dev.role, dev.kind, dev.weapon, dev.personal = role, kind, weapon, false
		dev.untilT = os.clock() + seconds
		laidOut = ""
	end
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if v == "helicoptero" then
			-- o HudCampo mostra o painel do UH-34D junto e limpa o atributo
			L.hover, L.assist = 0.62, true
			show("pilot", "helicopter", nil, 10)
		elseif v == "toqueveiculo" then
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil) -- local: no cliente o mesmo valor repete
			end)
			task.spawn(function()
				for _, s in
					{
						{ "driver", "ground_vehicle", "", 4 },
						{ "gunner", "ground_vehicle", "gun_90", 4 },
						{ "commander", "ground_vehicle", "", 3 },
						{ "door", "helicopter", "m60", 4 },
					} :: { { any } }
				do
					local w = s[3] :: string
					show(s[1] :: string, s[2] :: string, if w == "" then nil else w, s[4] :: number)
					task.wait(s[4] :: number)
				end
			end)
		end
	end)
end
