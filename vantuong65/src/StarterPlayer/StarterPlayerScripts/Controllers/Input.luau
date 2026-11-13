--!strict
-- Camada única de entrada (Parte 12.1). Todos os controllers pedem ações a este módulo, nunca ao
-- UserInputService diretamente.
--
-- Fontes, com "a primeira que chegar vence" (deduplicadas por botão):
--   1. Input Action System: um InputContext por contexto do InputMap (prioridade e Sink), uma
--      InputAction por botão lógico, com InputBinding do controle e do teclado/mouse;
--   2. UserInputService, como reserva para bindings que falhem no IAS (há relatos com Thumbstick1
--      e ButtonA).
-- Analógicos e gatilhos são lidos de GetGamepadState a cada quadro, com zona morta, curva e
-- limiar do InputMap.
-- Também cuida de: dispositivo preferido (PreferredInput), ícones certos por controle
-- (GetImageForKeyCode), tocar x segurar, máquina de estados (menus, mapa, menu do Roblox,
-- desconexão, morte, veículo), configurações salvas na conta e o gravador/reprodutor de entradas.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local Input = {}

Input.settings = InputMap.validate(nil)
Input.state = InputMap.newState()
Input.seat = nil :: string? -- "driver" | "gunner" | "commander" | "door"
Input.aimMode = "hip" -- "hip" | "ads" | "scope" (sensibilidade do olhar)

local device = "kbm" -- "gamepad" | "kbm" | "touch"
local primaryPad: Enum.UserInputType = Enum.UserInputType.Gamepad1

-- definido mais abaixo (máquina de estados); declarado aqui para os handlers de entrada
local applyEvent: (string, any?) -> () = function(_: string, _a: any?) end

local deviceChanged = Instance.new("BindableEvent")
Input.DeviceChanged = deviceChanged.Event -- (device)
local stateChanged = Instance.new("BindableEvent")
Input.StateChanged = stateChanged.Event -- (cancelled: {string}, ctx)
local settingsChanged = Instance.new("BindableEvent")
Input.SettingsChanged = settingsChanged.Event

-- ===== handlers =====
type Fn = () -> ()
local handlers: { [string]: { [string]: { Fn } } } = {}

-- phase: "press" | "release" | "tap" | "holdStart" | "holdEnd"
function Input.on(actionId: string, phase: string, fn: Fn)
	handlers[actionId] = handlers[actionId] or {}
	local h = handlers[actionId]
	h[phase] = h[phase] or {}
	table.insert(h[phase], fn)
end

local function fire(a: InputMap.Action, phase: string)
	if InputMap.CONTEXTS[a.ctx].game and not InputMap.allowed(Input.state, a.id) then
		return
	end
	local h = handlers[a.id]
	local list = h and h[phase]
	if list then
		for _, fn in list do
			task.spawn(fn)
		end
	end
end

-- ===== resolução de botões =====
type Entry = { press: { InputMap.Action }, tap: { InputMap.Action }, hold: { InputMap.Action } }
-- ctx -> código lógico -> entradas (separadas para controle e teclado)
local padBind: { [string]: { [string]: Entry } } = {}
local keyBind: { [string]: { [string]: Entry } } = {}

local ANALOG_TRIG: { [string]: boolean } = { ButtonL2 = true, ButtonR2 = true }
local SWAP_TRIG = { ButtonL1 = "ButtonL2", ButtonL2 = "ButtonL1", ButtonR1 = "ButtonR2", ButtonR2 = "ButtonR1" }

local function addBind(tbl: { [string]: { [string]: Entry } }, a: InputMap.Action, code: string?, press: string)
	if not code then
		return
	end
	tbl[a.ctx] = tbl[a.ctx] or {}
	local e = tbl[a.ctx][code] or { press = {}, tap = {}, hold = {} }
	tbl[a.ctx][code] = e
	local list: { InputMap.Action } = if press == "tap" then e.tap elseif press == "hold" then e.hold else e.press
	table.insert(list, a)
end

local function rebuildBindings()
	padBind, keyBind = {}, {}
	for _, a in InputMap.ACTIONS do
		addBind(padBind, a, InputMap.padFor(a, Input.settings), a.padPress)
		addBind(keyBind, a, InputMap.keyFor(a, Input.settings), a.keyPress)
	end
end

local function seatOk(a: InputMap.Action): boolean
	return a.seat == nil or a.seat == Input.seat
end

local function filter(list: { InputMap.Action }): { InputMap.Action }
	local out = {}
	for _, a in list do
		if seatOk(a) then
			table.insert(out, a)
		end
	end
	return out
end

-- Entrada efetiva de um código no contexto ativo (a primeira camada com binding vence).
local function resolve(code: string, isPad: boolean): Entry?
	local tbl = if isPad then padBind else keyBind
	for _, ctx in InputMap.layers(InputMap.activeContext(Input.state)) do
		local e = tbl[ctx] and tbl[ctx][code]
		if e then
			local f = { press = filter(e.press), tap = filter(e.tap), hold = filter(e.hold) }
			if #f.press + #f.tap + #f.hold > 0 then
				return f
			end
		end
	end
	return nil
end

type Pressed = { entry: Entry, t0: number, held: boolean, token: number }
local pressed: { [string]: Pressed } = {}
-- Teclas que estavam apertadas na troca de contexto: ficam "consumidas" até soltar. Sem isso, a
-- segunda fonte (IAS) entregava de novo a tecla que abriu o mapa (M) ou o menu (P), e a ação dela
-- no contexto novo (fechar) disparava no mesmo quadro (teste no Studio, 2026-11-10).
local consumed: { [string]: boolean } = {}
local token = 0

-- Gravador (Parte 12.7): eventos de botão do controle com tempo relativo.
local recording: { { t: number, code: string, down: boolean } }? = nil
local recordT0 = 0

local function onButton(code: string, down: boolean, isPad: boolean)
	if isPad and Input.settings.swapTriggers and SWAP_TRIG[code] then
		code = SWAP_TRIG[code]
	end
	local id = (if isPad then "pad:" else "key:") .. code
	if recording and isPad then
		table.insert(recording, { t = os.clock() - recordT0, code = code, down = down })
	end
	if consumed[id] then
		if not down then
			consumed[id] = nil -- soltou: o próximo aperto vale
		end
		return
	end
	if down then
		if pressed[id] then
			return -- a outra fonte já entregou este aperto
		end
		local s = Input.state
		if s.disconnected or s.robloxMenu or s.awaitRelease then
			return
		end
		local e = resolve(code, isPad)
		if not e then
			return
		end
		token += 1
		local p: Pressed = { entry = e, t0 = os.clock(), held = false, token = token }
		pressed[id] = p
		for _, a in e.press do
			fire(a, "press")
		end
		if #e.hold > 0 then
			if #e.tap == 0 then
				p.held = true -- só segurar: começa já
				for _, a in e.hold do
					fire(a, "holdStart")
				end
			else
				local my = p.token
				task.delay(Input.settings.holdTime, function()
					local cur = pressed[id]
					if cur and cur.token == my and not cur.held then
						cur.held = true
						for _, a in e.hold do
							fire(a, "holdStart")
						end
					end
				end)
			end
		end
	else
		local p = pressed[id]
		if not p then
			return
		end
		pressed[id] = nil
		for _, a in p.entry.press do
			fire(a, "release")
		end
		if p.held then
			for _, a in p.entry.hold do
				fire(a, "holdEnd")
			end
		else
			for _, a in p.entry.tap do
				fire(a, "tap")
			end
		end
	end
end

-- Troca de contexto: solta (release/holdEnd) e consome as teclas cujas ações NÃO existem nas
-- camadas do contexto novo. As que continuam válidas ficam apertadas: o botão direito que liga a
-- mira (infantaria) vale na mira (que tem a infantaria por baixo); soltá-lo aqui desligava a mira
-- no mesmo quadro (teste no Studio, 2026-11-10).
local function releaseAll()
	local ctx = InputMap.activeContext(Input.state)
	for id, p in pressed do
		local all = table.clone(p.entry.press)
		table.move(p.entry.tap, 1, #p.entry.tap, #all + 1, all)
		table.move(p.entry.hold, 1, #p.entry.hold, #all + 1, all)
		if InputMap.survives(all, ctx) then
			continue
		end
		pressed[id] = nil
		consumed[id] = true
		local function run(a: InputMap.Action, phase: string)
			local h = handlers[a.id]
			local list: { Fn } = if h and h[phase] then h[phase] else {}
			for _, fn in list do
				task.spawn(fn)
			end
		end
		for _, a in p.entry.press do
			run(a, "release")
		end
		if p.held then
			for _, a in p.entry.hold do
				run(a, "holdEnd")
			end
		end
	end
end

-- ===== Input Action System =====
local iasRoot: Folder? = nil
local iasContexts: { [string]: InputContext } = {}

local function buildIAS()
	if iasRoot then
		iasRoot:Destroy()
		iasRoot = nil
	end
	iasContexts = {}
	local ok = pcall(function()
		local root = Instance.new("Folder")
		root.Name = "VT65InputContexts"
		for ctx, def in InputMap.CONTEXTS do
			local c = Instance.new("InputContext")
			c.Name = ctx
			c.Priority = def.priority
			c.Sink = def.sink
			c.Enabled = false
			local sources: { { name: string, tbl: { [string]: { [string]: Entry } } } } =
				{ { name = "pad", tbl = padBind }, { name = "key", tbl = keyBind } }
			for _, src in sources do
				local tblName, tbl = src.name, src.tbl
				local codes: { [string]: Entry } = tbl[ctx] or {}
				for code in codes do
					if tblName == "pad" and ANALOG_TRIG[code] and not Input.settings.swapTriggers then
						continue -- gatilho: aperto sintetizado pelo valor analógico (limiar ajustável)
					end
					local physical = code
					if tblName == "pad" and Input.settings.swapTriggers and SWAP_TRIG[code] then
						physical = SWAP_TRIG[code]
					end
					local a = Instance.new("InputAction")
					a.Name = tblName .. ":" .. code
					a.Type = Enum.InputActionType.Bool
					local b = Instance.new("InputBinding")
					b.KeyCode = (Enum.KeyCode :: any)[physical]
					b.Parent = a
					a.Parent = c
					local isPad = tblName == "pad"
					a.Pressed:Connect(function()
						onButton(physical, true, isPad)
					end)
					a.Released:Connect(function()
						onButton(physical, false, isPad)
					end)
				end
			end
			c.Parent = root
			iasContexts[ctx] = c
		end
		root.Parent = player:WaitForChild("PlayerScripts")
		iasRoot = root
	end)
	Input.iasActive = ok
	if not ok then
		warn("[VT65] Input Action System indisponível: usando só UserInputService")
	end
end
Input.iasActive = false

local function syncContexts()
	local layers = InputMap.layers(InputMap.activeContext(Input.state))
	for ctx, c in iasContexts do
		c.Enabled = table.find(layers, ctx) ~= nil
	end
end

-- ===== UserInputService (reserva) =====
local MOUSE: { [Enum.UserInputType]: string } = {
	[Enum.UserInputType.MouseButton1] = "MouseLeftButton",
	[Enum.UserInputType.MouseButton2] = "MouseRightButton",
	[Enum.UserInputType.MouseButton3] = "MouseMiddleButton",
}

local function isGamepad(t: Enum.UserInputType): boolean
	return string.sub(t.Name, 1, 7) == "Gamepad"
end

-- Teclas que o PlayerModule também usa pelo ContextActionService (o pulo): o Roblox marca o aperto
-- como "processado", e a reserva perderia o Espaço do transpor. Caixa de texto em foco continua vetando.
local CAS_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.Space] = true }

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	local t = input.UserInputType
	if isGamepad(t) then
		if Input.state.disconnected then
			primaryPad = t
			applyEvent("reconnect")
		end
		local kc = input.KeyCode
		if
			t == primaryPad
			and kc ~= Enum.KeyCode.Thumbstick1
			and kc ~= Enum.KeyCode.Thumbstick2
			and not ANALOG_TRIG[kc.Name]
		then
			onButton(kc.Name, true, true)
		end
	elseif t == Enum.UserInputType.Keyboard then
		if
			input.KeyCode == Enum.KeyCode.Escape
			and Input.state.menus > 0
			and not UserInputService:GetFocusedTextBox()
		then
			-- D-93: Esc também volta nas telas do jogo (como B e Backspace). O Roblox abre o menu dele
			-- por cima; ao voltar, a tela do jogo já fechou.
			local h = handlers.ui_back
			local list = h and h.press
			if list then
				for _, fn in list do
					task.spawn(fn)
				end
			end
		elseif (not processed or CAS_KEYS[input.KeyCode]) and not UserInputService:GetFocusedTextBox() then
			onButton(input.KeyCode.Name, true, false)
		end
	elseif MOUSE[t] and not processed then
		onButton(MOUSE[t], true, false)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local t = input.UserInputType
	if isGamepad(t) and t == primaryPad then
		if not ANALOG_TRIG[input.KeyCode.Name] then
			onButton(input.KeyCode.Name, false, true)
		end
	elseif t == Enum.UserInputType.Keyboard then
		onButton(input.KeyCode.Name, false, false)
	elseif MOUSE[t] then
		onButton(MOUSE[t], false, false)
	end
end)

-- ===== analógicos e gatilhos =====
local virtualPad: { [string]: Vector3 }? = nil -- reprodutor de entradas

local function padValue(code: Enum.KeyCode): Vector3
	if virtualPad then
		return virtualPad[code.Name] or Vector3.zero
	end
	for _, o in UserInputService:GetGamepadState(primaryPad) do
		if o.KeyCode == code then
			return o.Position
		end
	end
	return Vector3.zero
end

-- Analógico cru (x direita, y para cima), já com a troca de analógicos (canhoto).
function Input.stickRaw(which: string): Vector2
	local code = if which == "left" then Enum.KeyCode.Thumbstick1 else Enum.KeyCode.Thumbstick2
	if Input.settings.swapSticks then
		code = if which == "left" then Enum.KeyCode.Thumbstick2 else Enum.KeyCode.Thumbstick1
	end
	local p = padValue(code)
	return Vector2.new(p.X, p.Y)
end

-- Movimento: zona morta radial do analógico esquerdo (resposta linear).
function Input.move(): Vector2
	local r = Input.stickRaw("left")
	local x, y = InputMap.radialDeadzone(r.X, r.Y, Input.settings.moveInner, Input.settings.moveOuter)
	return Vector2.new(x, y)
end

-- Gatilho lógico 0..1 com limiar; com troca gatilho↔bumper, o bumper digital vira o gatilho.
function Input.trigger(which: string): number
	local swapped = Input.settings.swapTriggers
	if swapped then
		local code = if which == "left" then Enum.KeyCode.ButtonL1 else Enum.KeyCode.ButtonR1
		return if UserInputService:IsGamepadButtonDown(primaryPad, code) then 1 else 0
	end
	local code = if which == "left" then Enum.KeyCode.ButtonL2 else Enum.KeyCode.ButtonR2
	return InputMap.trigger(padValue(code).Z, Input.settings.triggerThreshold)
end

function Input.device(): string
	return device
end

function Input.isGamepad(): boolean
	return device == "gamepad"
end

-- ===== dispositivo =====
local lastReport = 0
local function setDevice(d: string)
	if d == device then
		return
	end
	device = d
	deviceChanged:Fire(d)
	if os.clock() - lastReport > 2 then
		lastReport = os.clock()
		Net.event("Input_Type"):FireServer(d)
	end
end

local function readPreferred()
	local ok, pref = pcall(function()
		return UserInputService.PreferredInput
	end)
	if ok and pref then
		if pref == Enum.PreferredInput.Gamepad or pref == Enum.PreferredInput.MicroGamepad then
			setDevice("gamepad")
		elseif pref == Enum.PreferredInput.Touch then
			setDevice("touch")
		elseif device ~= "gamepad" then
			setDevice("kbm") -- do controle para o teclado só por tecla, clique ou mouse andando (abaixo)
		end
		return
	end
	local last = UserInputService:GetLastInputType()
	setDevice(if isGamepad(last) then "gamepad" elseif last == Enum.UserInputType.Touch then "touch" else "kbm")
end

pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(readPreferred)
end)
-- D-80: quem joga no controle com o mouse em cima da mesa via o tutorial e os avisos voltarem para
-- teclado a cada tremida do mouse. Do controle para o teclado, só tecla, clique ou mouse andando de
-- verdade (40 px em meio segundo).
local mouseRun, mouseT0 = 0, 0
UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement or device ~= "gamepad" then
		return
	end
	local now = os.clock()
	if now - mouseT0 > 0.5 then
		mouseRun, mouseT0 = 0, now
	end
	mouseRun += input.Delta.Magnitude
	if mouseRun > 40 then
		setDevice("kbm")
	end
end)
UserInputService.LastInputTypeChanged:Connect(function(t)
	-- reação imediata à troca (o PreferredInput também muda; este cobre versões sem ele)
	if isGamepad(t) then
		setDevice("gamepad")
	elseif t == Enum.UserInputType.Keyboard or MOUSE[t] then
		setDevice("kbm")
	elseif t == Enum.UserInputType.MouseMovement and device ~= "gamepad" then
		setDevice("kbm") -- do controle, só pelo InputChanged acima
	elseif t == Enum.UserInputType.Touch then
		setDevice("touch")
	end
end)

-- ===== ícones (Parte 12.1): imagem do botão certo para o controle conectado =====
local KEY_TEXT: { [string]: string } = {
	MouseLeftButton = "LMB",
	MouseRightButton = "RMB",
	MouseMiddleButton = "MMB",
	LeftShift = "Shift",
	Return = "Enter",
	One = "1",
	Space = "Espaço",
	CapsLock = "Caps Lock",
}

-- Devolve (imagem, texto) para a ação no contexto ativo (ou num contexto dado).
function Input.glyph(actionId: string, ctx: string?): (string?, string)
	for _, a in InputMap.ACTIONS do
		if a.id == actionId and (ctx == nil or a.ctx == ctx) and seatOk(a) then
			if device == "gamepad" then
				local pad = InputMap.padFor(a, Input.settings)
				if pad then
					local img = ""
					pcall(function()
						img = UserInputService:GetImageForKeyCode((Enum.KeyCode :: any)[pad]) :: any
					end)
					return if img ~= "" then img else nil, pad
				end
			else
				local key = InputMap.keyFor(a, Input.settings)
				if key then
					return nil, KEY_TEXT[key] or key
				end
			end
		end
	end
	return nil, "?"
end

-- ===== máquina de estados =====
-- Filtro de movimento (Controllers/Movement.client: inércia, fôlego, chão): recebe o pedido já com a
-- zona morta e devolve o que o Humanoid deve andar. Sem filtro, o pedido passa direto.
export type MoveFilter = (vec: Vector3, rel: boolean) -> (Vector3, boolean)
Input.moveFilter = nil :: MoveFilter?
function Input.setMoveFilter(fn: MoveFilter?)
	Input.moveFilter = fn
end

local controls: any = nil
task.spawn(function()
	local ok, pm = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
	end)
	if ok and pm then
		controls = pm:GetControls()
		-- movimento no controle com a zona morta do jogo (aplicada antes de qualquer lógica)
		local orig = controls.moveFunction
		controls.moveFunction = function(plr: Player, vec: Vector3, rel: boolean)
			if device == "gamepad" then
				local mv = Input.move()
				vec, rel = Vector3.new(mv.X, 0, -mv.Y), true
			end
			if not InputMap.acceptsGame(Input.state) or Input.state.downed then
				vec = Vector3.zero
			end
			local f = Input.moveFilter
			if f then
				-- erro no filtro não pode travar o soldado: cai para o pedido cru
				local okF, v2, r2 = pcall(f, vec, rel)
				if okF then
					vec, rel = v2, r2
				end
			end
			orig(plr, vec, rel)
		end
	end
end)

-- Mouse livre nas telas: em primeira pessoa (LockFirstPerson) o Roblox prende o mouse no centro;
-- um botão Modal visível solta. Vale no menu, no mapa e morto (mapa de spawn). Sem isso, quem
-- joga no mouse não escolhia onde renascer (teste no Studio, 2026-11-10).
local mouseGui = Instance.new("ScreenGui")
mouseGui.Name = "VT65MouseFree"
mouseGui.ResetOnSpawn = false
local modal = Instance.new("TextButton")
modal.Modal = true
modal.Text = ""
modal.BackgroundTransparency = 1
modal.Size = UDim2.fromOffset(1, 1)
modal.Selectable = false -- o controle não navega até ele
modal.Visible = false
modal.Parent = mouseGui
task.spawn(function()
	mouseGui.Parent = player:WaitForChild("PlayerGui")
end)

local function sinkJump(_: string, _s: Enum.UserInputState, _o: InputObject): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

applyEvent = function(ev: string, arg: any?)
	local before = InputMap.activeContext(Input.state)
	local cancelled = InputMap.event(Input.state, ev, arg)
	local ctx = InputMap.activeContext(Input.state)
	if ctx ~= before then
		releaseAll()
	end
	syncContexts()
	-- menus e mapa: personagem parado (A não pula, analógico não anda); em veículo, A e Espaço
	-- não tiram o jogador do assento (sair = B segurado / Y).
	local inUi = Input.state.menus > 0 or Input.state.map
	modal.Visible = inUi or not Input.state.alive
	-- o cursor do sistema (a "mãozinha") ficava no meio da tela durante o jogo: só aparece nas telas
	UserInputService.MouseIconEnabled = inUi or not Input.state.alive
	if controls then
		if inUi then
			controls:Disable()
		else
			controls:Enable()
		end
	end
	if Input.state.vehicle then
		ContextActionService:BindActionAtPriority(
			"VT65_NoSeatJump",
			sinkJump,
			false,
			3000,
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.Space
		)
	else
		ContextActionService:UnbindAction("VT65_NoSeatJump")
	end
	if #cancelled > 0 or ctx ~= before then
		stateChanged:Fire(cancelled, ctx)
	end
end

Input.event = applyEvent

function Input.context(): string
	return InputMap.activeContext(Input.state)
end

function Input.openMenu()
	Input.event("menu_open")
end
function Input.closeMenu()
	Input.event("menu_close")
end

-- volta ao jogo: só depois de todos os botões soltos (relê o estado real do controle)
local function anyDown(): boolean
	for _, k in Enum.KeyCode:GetEnumItems() do
		local n = k.Name
		if
			(string.sub(n, 1, 6) == "Button" or string.sub(n, 1, 4) == "DPad")
			and UserInputService:IsGamepadButtonDown(primaryPad, k)
		then
			return true
		end
	end
	if
		Input.trigger("left") > 0
		or Input.trigger("right") > 0
		or #UserInputService:GetKeysPressed() > 0
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	then
		return true
	end
	return false
end

-- gatilhos: aperto/soltura sintetizados pelo valor analógico com o limiar do jogador
local trigDown: { [string]: boolean } = { ButtonL2 = false, ButtonR2 = false }
RunService.Heartbeat:Connect(function()
	for name, was in trigDown do
		local down = padValue((Enum.KeyCode :: any)[name]).Z > Input.settings.triggerThreshold
		if down ~= was then
			trigDown[name] = down
			onButton(name, down, true)
		end
	end
	if Input.state.awaitRelease and not anyDown() then
		table.clear(pressed)
		Input.event("buttons_released")
	end
end)

GuiService.MenuOpened:Connect(function()
	Input.event("roblox_menu_open")
end)
GuiService.MenuClosed:Connect(function()
	Input.event("roblox_menu_close")
end)

-- controle desconectado: pausa; volta com o primeiro controle que apertar um botão. O aviso na
-- tela (cartão de época) é do Reconexao.client, que olha Input.state.disconnected.
UserInputService.GamepadDisconnected:Connect(function(gp)
	if gp == primaryPad and device == "gamepad" then
		Input.event("disconnect")
	end
end)

-- vida do personagem → estados
local function watchCharacter(char: Model)
	Input.event("respawn")
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Died:Connect(function()
		Input.event("die")
	end)
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		if not hum.SeatPart then
			Input.seat = nil
			if Input.state.vehicle then
				Input.event("vehicle_exit")
			end
		end
	end)
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
else
	applyEvent("die") -- ainda sem personagem: tela de escolha/spawn é o contexto
end
player:GetAttributeChangedSignal("Downed"):Connect(function()
	Input.event(if player:GetAttribute("Downed") then "downed" else "revived")
end)

-- veículo: o VehicleController informa o tipo e o assento
function Input.setVehicle(kind: string?, seat: string?)
	local was = Input.state.vehicle
	Input.seat = seat
	if kind and not was then
		Input.event("vehicle_enter", kind)
	elseif kind and was then
		Input.event("seat_switch")
	elseif not kind and was then
		Input.event("vehicle_exit")
	end
end

-- ===== configurações (salvas na conta) =====
local saveQueued = false
local function queueSave()
	if not saveQueued then
		saveQueued = true
		task.delay(2, function()
			saveQueued = false
			Net.event("Settings_Save"):FireServer(Input.settings)
		end)
	end
end

function Input.setSettings(new: any)
	Input.settings = InputMap.validate(new)
	rebuildBindings()
	buildIAS()
	syncContexts()
	settingsChanged:Fire(Input.settings)
	queueSave()
end

-- Muda UMA preferência (ex.: 3ª pessoa pela tecla O) e salva na conta. Só refaz os bindings se a
-- chave mexe nos botões (InputMap.BINDING_KEYS): trocar de câmera no meio do combate não recria o IAS.
function Input.setSetting(key: string, value: any)
	local raw = table.clone(Input.settings) :: any
	raw[key] = value
	Input.settings = InputMap.validate(raw)
	if InputMap.BINDING_KEYS[key] then
		rebuildBindings()
		buildIAS()
		syncContexts()
	end
	settingsChanged:Fire(Input.settings)
	queueSave()
end

-- ===== gravador / reprodutor (Parte 12.7) =====
function Input.startRecording()
	recording = {}
	recordT0 = os.clock()
end

function Input.stopRecording(): { { t: number, code: string, down: boolean } }
	local r = recording or {}
	recording = nil
	return r
end

-- Reproduz botões (e, opcionalmente, analógicos) gravados; devolve quando termina.
function Input.replay(events: { any }, sticks: { any }?)
	virtualPad = {}
	local t0 = os.clock()
	local si = 1
	for _, e in events do
		local waitT = e.t - (os.clock() - t0)
		if waitT > 0 then
			task.wait(waitT)
		end
		while sticks and sticks[si] and sticks[si].t <= e.t do
			local s = sticks[si];
			(virtualPad :: any)[s.code] = Vector3.new(s.x, s.y, s.z or 0)
			si += 1
		end
		onButton(e.code, e.down, true)
	end
	virtualPad = nil
end

-- ===== início =====
-- loaded: a configuração da conta já chegou. pendingLang: idioma escolhido antes disso (tela de
-- entrada, ReplicatedFirst/Idioma); vale por cima do que estava salvo e é gravado.
Input.loaded = false
Input.pendingLang = nil :: string?
rebuildBindings()
buildIAS()
readPreferred()
syncContexts()
task.spawn(function()
	local ok, saved = pcall(function()
		return Net.func("Settings_Get"):InvokeServer()
	end)
	if ok and saved then
		local raw = saved :: any
		local want = Input.pendingLang
		if want and type(raw) == "table" then
			raw = table.clone(raw)
			raw.lang = want
		end
		Input.settings = InputMap.validate(raw)
		rebuildBindings()
		buildIAS()
		syncContexts()
		settingsChanged:Fire(Input.settings)
		if want then
			queueSave()
		end
	end
	Input.loaded = true
	Input.pendingLang = nil
end)

return Input
