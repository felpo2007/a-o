--!strict
-- Menu do jogo (segurar View / tecla P): abas Configurações, Squad e papel, Loja (e Servidor, para o
-- dono de servidor privado). LB/RB trocam abas, LT/RT trocam sub-abas, A confirma, B volta
-- (Parte 12.5). Nada exige digitar: números têm botões "−" e "+", escolhas alternam com A, o
-- remapeamento espera o próximo botão do controle.
-- Configurações saem da conta (Settings_Get) e voltam para ela (Settings_Save) pela camada Input.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Accessibility = require(ReplicatedStorage.Shared.Accessibility)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Kit = require(ReplicatedStorage.Shared.Kit)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)
local VirtualCursor = require(script.Parent.VirtualCursor)

local player = Players.LocalPlayer
local gui = UiKit.screen("VT65GameMenu", 35)
gui.Enabled = false

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
-- cabe em qualquer tela (D-82: numa janela estreita o quadro passava da borda)
root.Size = UDim2.fromScale(0.94, 0.9)
root.BackgroundColor3 = UiKit.PAPER
root.Parent = gui
do
	local sc = Instance.new("UISizeConstraint")
	sc.MaxSize = Vector2.new(if UiKit.tv() then 900 else 720, if UiKit.tv() then 640 else 540)
	sc.Parent = root
end
local tabsBar = UiKit.label(root, "", 20, 40)
tabsBar.Position = UDim2.fromOffset(4, 4)
local subBar = UiKit.label(root, "", 16, 30)
subBar.Position = UDim2.fromOffset(4, 46)
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.fromOffset(8, 82)
body.Size = UDim2.new(1, -16, 1, -90)
body.BackgroundTransparency = 1
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.CanvasSize = UDim2.new()
body.ScrollBarThickness = 8
body.Parent = root
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body

local BASE_TABS = { "Configurações", "Squad e papel", "Loja" }
-- servidor privado: só o dono vê a aba "Servidor" (modo e horário; o servidor revalida)
local MODES = { "Warfare", "Offensive", "Skirmish" }
local MODE_NAMES = { "Warfare (5 setores, 75 min)", "Offensive (EUA atacam do leste)", "Skirmish (1 setor, 20 min)" }
local CLOCKS = { 6.5, 12, 18.5 }
local CLOCK_NAMES = { "06:30 (amanhecer)", "12:00", "18:30 (entardecer)" }
local psMode, psClock = 1, 1
-- equipamento por peso (Kit): escolha local; o servidor valida e aplica no próximo spawn
local kit: Kit.Kit? = nil
local function kitKind(): string
	local wid = string.split(tostring(player:GetAttribute("Loadout") or ""), ",")[1]
	local wp = Weapons.get(wid)
	return if wp then wp.kind else "rifle"
end
local function isOwner(): boolean
	return ReplicatedStorage:GetAttribute("PrivateServer") == true and game.PrivateServerOwnerId == player.UserId
end
local function TABS(): { string }
	local t = table.clone(BASE_TABS)
	if isOwner() then
		table.insert(t, "Servidor")
	end
	return t
end
-- D-82: "Mouse/teclado" (sensibilidade do mouse e troca de teclas) e "Gráficos"
local SUBS = { "Controle", "Mira", "Mouse/teclado", "Gráficos", "Vibração", "Acessib.", "Botões" }
local tab, sub = 1, 1
local listening: string? = nil -- "ctx.actionId" esperando um botão do controle
local keyListening: string? = nil -- "ctx.actionId" esperando uma tecla
-- A tecla capturada chega também às ações do menu (Q/E/Z/C, LB/RB...), às vezes depois da captura:
-- por um instante após capturar, as abas não trocam e o menu não fecha (teste no Studio, D-82).
local swallowUntil = 0
local function busy(): boolean
	return listening ~= nil or keyListening ~= nil or os.clock() < swallowUntil
end
local CTX_NAMES: { [string]: string } = {
	infantry = "Infantaria",
	aim = "Mirando",
	global = "Geral",
	ground_vehicle = "Veículo",
	helicopter = "Helicóptero",
	map = "Mapa",
}
local KEY_NAMES: { [string]: string } = {
	MouseLeftButton = "botão esquerdo",
	MouseRightButton = "botão direito",
	MouseMiddleButton = "botão do meio",
	LeftShift = "Shift",
	LeftControl = "Ctrl",
	Return = "Enter",
	Space = "Espaço",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
}
local MOUSE_KEYS: { [Enum.UserInputType]: string } = {
	[Enum.UserInputType.MouseButton1] = "MouseLeftButton",
	[Enum.UserInputType.MouseButton2] = "MouseRightButton",
	[Enum.UserInputType.MouseButton3] = "MouseMiddleButton",
}
do -- a barra de sub-abas cabe na largura (texto encolhe se precisar)
	subBar.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = UiKit.text(16)
	c.Parent = subBar
end

local function clearBody()
	for _, c in body:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local order = 0
local function row(text: string, onClick: () -> ())
	order += 1
	return UiKit.button(body, text, onClick, order)
end

local function set(k: string, v: any)
	local s = table.clone(Input.settings) :: any
	s[k] = v
	Input.setSettings(s)
end

local function numberRow(label: string, k: string, step: number, fmt: string)
	local holder = Instance.new("Frame")
	order += 1
	holder.LayoutOrder = order
	holder.Size = UDim2.new(1, -8, 0, if UiKit.tv() then 50 else 36)
	holder.BackgroundTransparency = 1
	holder.Parent = body
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(0.6, 0, 1, 0)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = UiKit.INK
	l.Font = Enum.Font.GothamMedium
	l.TextSize = UiKit.text(16)
	l.Text = string.format("%s: " .. fmt, label, (Input.settings :: any)[k])
	l.Parent = holder
	for i, d in { -1, 1 } do
		local b = UiKit.button(holder, if d < 0 then "−" else "+", function()
			set(k, (Input.settings :: any)[k] + d * step)
		end)
		b.Size = UDim2.new(0.18, 0, 1, 0)
		b.Position = UDim2.new(0.6 + (i - 1) * 0.2, 0, 0, 0)
	end
end

local function choiceRow(label: string, k: string, options: { any }, names: { string })
	local cur = (Input.settings :: any)[k]
	local idx = table.find(options, cur) or 1
	row(string.format("%s: %s", label, names[idx]), function()
		set(k, options[idx % #options + 1])
	end)
end

local function render()
	clearBody()
	order = 0
	local t = {}
	local tabs = TABS()
	tab = math.min(tab, #tabs)
	for i, n in tabs do
		table.insert(t, if i == tab then "[" .. n .. "]" else n)
	end
	local _, lb = Input.glyph("ui_tab_prev", "menu")
	local _, rb = Input.glyph("ui_tab_next", "menu")
	tabsBar.Text = string.format("%s  %s  %s", lb, table.concat(t, "   "), rb)
	subBar.Visible = tab == 1
	if tab == 1 then
		local st = {}
		for i, n in SUBS do
			table.insert(st, if i == sub then "[" .. n .. "]" else n)
		end
		local _, lt = Input.glyph("ui_sub_prev", "menu")
		local _, rt = Input.glyph("ui_sub_next", "menu")
		subBar.Text = string.format("%s  %s  %s", lt, table.concat(st, "  "), rt)
		local S = SUBS[sub]
		if S == "Controle" then
			numberRow("Zona morta interna (mover)", "moveInner", 0.02, "%.2f")
			numberRow("Zona morta externa (mover)", "moveOuter", 0.02, "%.2f")
			numberRow("Zona morta interna (olhar)", "lookInner", 0.02, "%.2f")
			numberRow("Zona morta externa (olhar)", "lookOuter", 0.02, "%.2f")
			numberRow("Limiar do gatilho", "triggerThreshold", 0.05, "%.2f")
			choiceRow(
				"Curva de resposta",
				"curve",
				{ "exponential", "linear", "dynamic" },
				{ "exponencial", "linear", "dinâmica" }
			)
			choiceRow("Inverter Y", "invertY", { false, true }, { "não", "sim" })
			choiceRow("Trocar analógicos (canhoto)", "swapSticks", { false, true }, { "não", "sim" })
			choiceRow("Trocar gatilhos com bumpers", "swapTriggers", { false, true }, { "não", "sim" })
			-- D-82: o analógico esquerdo vira um mouse nos menus (velocidade padrão do Roblox; A clica)
			choiceRow("Cursor virtual nos menus", "virtualCursor", { false, true }, { "desligado", "ligado" })
		elseif S == "Mouse/teclado" then
			numberRow("Sensibilidade do mouse", "mouseSens", 0.05, "%.2f")
			numberRow("Mouse apontando (fração)", "mouseAds", 0.05, "%.2f")
			numberRow("Mouse na luneta/binóculo (fração)", "mouseScope", 0.05, "%.2f")
			local conflicts = InputMap.keyConflicts(Input.settings)
			if #conflicts > 0 then
				UiKit.label(body, "Conflito: " .. conflicts[1], 14)
			end
			for _, a in InputMap.ACTIONS do
				local ctxName = CTX_NAMES[a.ctx]
				local key = InputMap.keyFor(a, Input.settings)
				if ctxName and key then
					local id = a.ctx .. "." .. a.id
					row(
						string.format(
							"[%s] %s: %s",
							ctxName,
							a.label,
							if keyListening == id then "aperte uma tecla…" else KEY_NAMES[key] or key
						),
						function()
							keyListening = id
							render()
						end
					)
				end
			end
			row("Restaurar teclas padrão", function()
				local s = table.clone(Input.settings) :: any
				s.keymap = {}
				Input.setSettings(s)
			end)
		elseif S == "Gráficos" then
			choiceRow(
				"Detalhe (arroz, poeira, folhas, fumaça)",
				"gfxDetail",
				{ "high", "medium", "low" },
				{ "alto", "médio", "baixo" }
			)
			choiceRow("Sombras do sol", "gfxShadows", { true, false }, { "ligadas", "desligadas (mais rápido)" })
			choiceRow(
				"Efeitos de tela",
				"gfxPost",
				{ "full", "light", "off" },
				{ "completos", "leves (sem brilho)", "desligados" }
			)
			numberRow("Brilho", "gfxBrightness", 0.02, "%+.2f")
			UiKit.label(body, "A qualidade geral fica no menu do Roblox (Esc > Configurações).", 14)
			row("Restaurar gráficos padrão", function()
				local s = table.clone(Input.settings) :: any
				for _, k in { "gfxDetail", "gfxShadows", "gfxPost", "gfxBrightness" } do
					s[k] = (InputMap.DEFAULTS :: any)[k]
				end
				Input.setSettings(s)
			end)
		elseif S == "Mira" then
			numberRow("Quadril horizontal", "sensHipX", 0.05, "%.2f")
			numberRow("Quadril vertical", "sensHipY", 0.05, "%.2f")
			numberRow("Mira de ferro horizontal", "sensAdsX", 0.05, "%.2f")
			numberRow("Mira de ferro vertical", "sensAdsY", 0.05, "%.2f")
			numberRow("Luneta/binóculo horizontal", "sensScopeX", 0.05, "%.2f")
			numberRow("Luneta/binóculo vertical", "sensScopeY", 0.05, "%.2f")
			choiceRow("Aceleração de giro", "turnAccel", { true, false }, { "ligada", "desligada" })
			choiceRow(
				"Assistência de mira (só controle)",
				"aimAssist",
				{ "minimal", "off" },
				{ "mínima", "desligada" }
			)
			-- câmera de ombro (ThirdPerson.client); mirando volta à 1ª pessoa. O modo pode proibir.
			local tpAllowed = workspace:GetAttribute("ThirdPersonAllowed") ~= false
			choiceRow(
				if tpAllowed then "Câmera" else "Câmera (3ª pessoa desligada neste modo)",
				"thirdPerson",
				{ false, true },
				{ "1ª pessoa", "3ª pessoa (ombro)" }
			)
			choiceRow("Ombro da 3ª pessoa", "shoulderLeft", { false, true }, { "direito", "esquerdo" })
		elseif S == "Vibração" then
			choiceRow("Disparo", "hapticFire", { "normal", "low", "off" }, { "normal", "baixa", "desligada" })
			choiceRow(
				"Dano e explosões",
				"hapticDamage",
				{ "normal", "low", "off" },
				{ "normal", "baixa", "desligada" }
			)
		elseif S == "Acessib." then
			-- D-84: idioma da interface (Traducao.client); "automático" = idioma da conta Roblox
			choiceRow(
				"Idioma / Language",
				"lang",
				{ "auto", "pt", "en", "es", "vi" },
				{ "automático", "Português", "English", "Español", "Tiếng Việt" }
			)
			numberRow("Tempo de segurar (s)", "holdTime", 0.05, "%.2f")
			choiceRow("Mirar", "aimToggle", { false, true }, { "segurar", "alternar" })
			choiceRow("Correr", "sprintToggle", { true, false }, { "alternar", "segurar (teclado)" })
			choiceRow("Rodas radiais", "wheelToggle", { false, true }, { "segurar", "alternar" })
			numberRow("Campo de visão (graus)", "fov", 5, "%d")
			choiceRow("Modo daltônico (traçantes)", "colorblind", Accessibility.MODES, {
				Accessibility.MODE_NAMES.off,
				Accessibility.MODE_NAMES.protan,
				Accessibility.MODE_NAMES.deutan,
				Accessibility.MODE_NAMES.tritan,
			})
			choiceRow("Legendas de som", "captions", { false, true }, { "desligadas", "ligadas" })
			row("Restaurar padrões", function()
				Input.setSettings(nil)
			end)
		elseif S == "Botões" then
			local conflicts = InputMap.conflicts(Input.settings)
			if #conflicts > 0 then
				UiKit.label(body, "Conflito: " .. conflicts[1], 14)
			end
			for _, a in InputMap.ACTIONS do
				if a.pad then
					local key = a.ctx .. "." .. a.id
					local pad = InputMap.padFor(a, Input.settings) or "—"
					local waiting = listening == key
					row(
						string.format(
							"[%s] %s: %s",
							a.ctx,
							a.label,
							if waiting then "aperte um botão…" else string.gsub(pad, "Button", "")
						),
						function()
							listening = key
							render()
						end
					)
				end
			end
			row("Restaurar botões padrão", function()
				local s = table.clone(Input.settings) :: any
				s.remap = {}
				Input.setSettings(s)
			end)
		end
	elseif tab == 2 then
		row("Trocar de papel (+15 s no próximo spawn)", function()
			player:SetAttribute("Role", nil)
			Bus.fire("menu_close_request")
		end)
		row("Sair do squad", function()
			Net.event("Squad_Action"):FireServer({ op = "leave" })
			Bus.fire("menu_close_request")
		end)
		-- equipamento por peso: −/+ por item, dentro do limite em kg
		local kind = kitKind()
		local k = kit or Kit.validate(nil, kind)
		kit = k
		UiKit.label(
			body,
			string.format("Equipamento: %.1f de %.1f kg (vale no próximo spawn)", Kit.weight(k, kind), Kit.limit(kind)),
			15
		).LayoutOrder = order
			+ 1
		order += 1
		for _, it in Kit.ITEMS do
			order += 1
			local holder = Instance.new("Frame")
			holder.LayoutOrder = order
			holder.Size = UDim2.new(1, -8, 0, if UiKit.tv() then 50 else 36)
			holder.BackgroundTransparency = 1
			holder.Parent = body
			local l = UiKit.label(
				holder,
				string.format("%s: %d", it.name, (k :: any)[it.id]),
				16,
				if UiKit.tv() then 50 else 36
			)
			l.Size = UDim2.new(0.6, 0, 1, 0)
			l.TextXAlignment = Enum.TextXAlignment.Left
			for i, d in { -1, 1 } do
				local b = UiKit.button(holder, if d < 0 then "−" else "+", function()
					local raw = table.clone(k) :: any
					raw[it.id] += d
					if d > 0 and Kit.weight(raw, kind) > Kit.limit(kind) + 1e-9 then
						Bus.fire("toast", "Passa do limite de peso: tire outro item antes")
						return
					end
					local nk = Kit.validate(raw, kind)
					kit = nk
					Net.event("Kit_Set"):FireServer(nk)
					render()
				end)
				b.Size = UDim2.new(0.18, 0, 1, 0)
				b.Position = UDim2.new(0.6 + (i - 1) * 0.2, 0, 0, 0)
			end
		end
		row("Refazer o tutorial do papel", function()
			Bus.fire("tutorial_restart")
			Bus.fire("menu_close_request")
		end)
		row("Pular o tutorial", function()
			Bus.fire("tutorial_skip")
			Bus.fire("menu_close_request")
		end)
	elseif tab == 3 then
		row("Abrir a loja", function()
			Bus.fire("shop_open")
		end)
	elseif tab == 4 and isOwner() then
		row("Modo: " .. MODE_NAMES[psMode], function()
			psMode = psMode % #MODES + 1
			render()
		end)
		row("Horário de início: " .. CLOCK_NAMES[psClock], function()
			psClock = psClock % #CLOCKS + 1
			render()
		end)
		row("Aplicar (vale na próxima partida)", function()
			Net.event("PrivateServer_SetOptions"):FireServer({ mode = MODES[psMode], clock = CLOCKS[psClock] })
			Bus.fire("toast", "Servidor: " .. MODES[psMode] .. " na próxima partida")
		end)
	end
	UiKit.focus(body)
end

-- D-82: com a opção "Cursor virtual", o menu usa o cursor do lobby (VirtualCursor: analógico
-- esquerdo move, A clica, direcional pula entre botões, analógico direito rola). Só desliga o
-- cursor que ele mesmo ligou.
local menuCursor = false
local function syncCursor()
	local want = gui.Enabled and Input.settings.virtualCursor
	if want and not menuCursor and not VirtualCursor.isActive() then
		menuCursor = true
		VirtualCursor.setActive(true)
	elseif not want and menuCursor then
		menuCursor = false
		VirtualCursor.setActive(false)
	end
end

local function setOpen(open: boolean)
	if open == gui.Enabled then
		return
	end
	gui.Enabled = open
	listening = nil
	keyListening = nil
	syncCursor()
	if open then
		Input.openMenu()
		render()
	else
		Input.closeMenu()
	end
end

Input.on("game_menu", "holdStart", function()
	setOpen(true)
end)
Input.on("game_menu", "press", function() -- P no teclado
	setOpen(not gui.Enabled)
end)
Input.on("ui_back", "press", function()
	local shop = player:WaitForChild("PlayerGui"):FindFirstChild("VT65Shop") :: ScreenGui?
	if shop and shop.Enabled then
		return -- a loja (por cima) fecha primeiro
	end
	if os.clock() < swallowUntil then
		return -- o B (ou a tecla) acabou de virar o botão de uma ação
	end
	if listening or keyListening then
		listening, keyListening = nil, nil
		render()
	else
		setOpen(false)
	end
end)
-- esperando um botão ou uma tecla, Q/E/Z/C e LB/RB/LT/RT trocam o botão da ação, não a aba
Input.on("ui_tab_prev", "press", function()
	if gui.Enabled and not busy() then
		tab = (tab - 2) % #TABS() + 1
		render()
	end
end)
Input.on("ui_tab_next", "press", function()
	if gui.Enabled and not busy() then
		tab = tab % #TABS() + 1
		render()
	end
end)
Input.on("ui_sub_prev", "press", function()
	if gui.Enabled and tab == 1 and not busy() then
		sub = (sub - 2) % #SUBS + 1
		render()
	end
end)
Input.on("ui_sub_next", "press", function()
	if gui.Enabled and tab == 1 and not busy() then
		sub = sub % #SUBS + 1
		render()
	end
end)
Bus.on("menu_close_request", function()
	setOpen(false)
end)
Input.SettingsChanged:Connect(function()
	if gui.Enabled then
		syncCursor()
		render()
	end
end)
UiKit.watch(root, function()
	return gui.Enabled
end)

-- D-82: troca de tecla: a próxima tecla (ou botão do mouse fora dos botões da tela) vira a tecla da
-- ação. Backspace cancela (é o "voltar"); Esc, WASD e outras do Roblox são recusadas.
UserInputService.InputBegan:Connect(function(input, processed)
	if not keyListening or not gui.Enabled then
		return
	end
	local code: string? = nil
	if input.UserInputType == Enum.UserInputType.Keyboard then
		code = input.KeyCode.Name
	elseif MOUSE_KEYS[input.UserInputType] and not processed then
		code = MOUSE_KEYS[input.UserInputType]
	end
	if not code or code == "Backspace" then
		return
	end
	if InputMap.KEY_RESERVED[code] then
		Bus.fire("toast", "Tecla reservada pelo Roblox ou pelo movimento: escolha outra")
		return
	end
	local key = keyListening :: string
	keyListening = nil
	swallowUntil = os.clock() + 0.3
	local s = table.clone(Input.settings) :: any
	s.keymap = table.clone(s.keymap)
	s.keymap[key] = code
	local trial = InputMap.validate(s)
	if #InputMap.keyConflicts(trial) > 0 then
		Bus.fire("toast", "Conflito com outra ação: escolha outra tecla")
		render()
		return
	end
	Input.setSettings(trial)
end)

-- remapeamento: o próximo botão do controle vira o novo botão da ação (Start é reservado)
UserInputService.InputBegan:Connect(function(input)
	if not listening or string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
		return
	end
	local code = input.KeyCode.Name
	if InputMap.RESERVED[code] or code == "Thumbstick1" or code == "Thumbstick2" or code == "ButtonA" then
		return -- A confirma no menu; não remapeia por aqui
	end
	local key = listening :: string
	listening = nil
	swallowUntil = os.clock() + 0.3
	local s = table.clone(Input.settings) :: any
	s.remap = table.clone(s.remap)
	s.remap[key] = code
	local trial = InputMap.validate(s)
	if #InputMap.conflicts(trial) > 0 then
		Bus.fire("toast", "Conflito com outra ação: escolha outro botão")
		render()
		return
	end
	Input.setSettings(trial)
end)
