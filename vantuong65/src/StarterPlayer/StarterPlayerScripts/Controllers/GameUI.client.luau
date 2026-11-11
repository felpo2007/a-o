--!strict
-- Menus de entrada e mapa tático (F2 + Parte 12.5).
-- Lobby (DeployScreen sobre a mesa 3D do LobbyScene): lado → mesa → squad → papel → inserção. No
-- controle, o analógico esquerdo move o cursor virtual (VirtualCursor) pela mesa e pelos papéis;
-- A escolhe, B volta, LB/RB pulam entre os objetos/abas. A carta de spawn abre quando a inserção é
-- escolhida na mesa (ou direto, ao morrer com papel).
-- Mapa (tocar View / M): carta topográfica de verdade (CartaView; pedido do dono, 2026-11-11), com
-- setores, frente, objetivos, pontos de inserção, squad e marcações; nunca inimigos (Parte 9.5).
-- No controle: analógico esquerdo = cursor com ímã (gruda nos pontos de spawn e nos objetivos);
-- direito = arrastar; gatilhos = zoom; direcional = passo de arrasto; L3 = você; R3 = carta inteira;
-- LB/RB pulam entre spawns liberados; A escolhe; X marca; Y troca de papel (morto) ou planta o ponto
-- de reunião do squad (líder, em campo); B/Select fecham. Mouse: roda = zoom, arrastar = mover.
-- A navegação automática do Roblox fica desligada no mapa (a nossa assume).
-- Modos: "spawn" (morto), "view" (aberto em jogo) e "target" (comandante escolhendo o alvo).
-- Tudo fica num "palco" de projeto de 1280 x 720 que escala para caber na tela (UIScale).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Carta = require(ReplicatedStorage.Shared.Carta)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local CartaView = require(script.Parent.CartaView)
local DeployScreen = require(script.Parent.DeployScreen)
local Input = require(script.Parent.Input)
local LobbyScene = require(script.Parent.LobbyScene)
local SpawnTransition = require(script.Parent.SpawnTransition)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)
local VirtualCursor = require(script.Parent.VirtualCursor)

local player = Players.LocalPlayer
local gui = UiKit.screen("VT65Menus", 20)
gui.IgnoreGuiInset = true

-- palco de projeto (1280 x 720), centrado e escalado para caber; o fundo em tela cheia é do LobbyScene
local DESIGN_W, DESIGN_H = 1280, 720
local stage = Instance.new("Frame")
stage.Name = "Stage"
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
stage.BackgroundTransparency = 1
stage.Parent = gui
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage

-- tamanho de texto no palco: na TV, nunca abaixo de 24 px na tela
local function TS(size: number): number
	return UiKit.textAt(size, stageScale.Scale)
end

-- tela de deslocamento (lado / squad / papel / inserção), em tela cheia no palco
local side = DeployScreen.root
side.Parent = stage

-- Janela do mapa. Na carta de inserção (morto) fica à direita da ficha do DeployScreen; aberta em
-- campo (ou no alvo do comandante) ocupa o palco, com a legenda à direita.
local SPAWN_RECT = { x = 430, y = 176, w = 810, h = 486 }
local VIEW_RECT = { x = 24, y = 64, w = 940, h = 620 }
local LEGEND_RECT = { x = 980, y = 64, w = 276, h = 620 }
local mapFrame = Instance.new("Frame")
mapFrame.Name = "Carta"
mapFrame.BorderSizePixel = 0
mapFrame.ClipsDescendants = true
mapFrame.Active = true -- tapa a mesa 3D do lobby atrás da carta (o clique não atravessa)
mapFrame.Visible = false
mapFrame.ZIndex = 2 -- por cima da tela de deslocamento (passo da inserção)
mapFrame.Parent = stage
local mapEdge = Instance.new("UIStroke")
mapEdge.Thickness = 4
mapEdge.Color = UiKit.DRAB
mapEdge.Parent = mapFrame
-- aba datilografada em cima da carta (fora do mapFrame, que corta os filhos)
local mapTab = Instance.new("TextLabel")
mapTab.Size = UDim2.fromOffset(SPAWN_RECT.w, 28)
mapTab.BackgroundColor3 = UiKit.DRAB
mapTab.BorderSizePixel = 0
mapTab.TextColor3 = UiKit.KHAKI
mapTab.Font = Enum.Font.SpecialElite
mapTab.TextXAlignment = Enum.TextXAlignment.Left
mapTab.TextSize = TS(16)
mapTab.Visible = false
mapTab.ZIndex = 2
mapTab.Parent = stage
local mapTabPad = Instance.new("UIPadding")
mapTabPad.PaddingLeft = UDim.new(0, 12)
mapTabPad.Parent = mapTab
-- faixa de estado no pé da carta: modo, relógio e grade do cursor à esquerda; comandos à direita
local status = Instance.new("TextLabel")
status.Name = "Estado"
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 0, 1, 0)
status.Size = UDim2.new(1, 0, 0, if UiKit.tv() then 34 else 26)
status.BackgroundColor3 = UiKit.NIGHT
status.BackgroundTransparency = 0.15
status.TextColor3 = UiKit.KHAKI
status.Font = Enum.Font.SpecialElite
status.TextSize = TS(15)
status.TextXAlignment = Enum.TextXAlignment.Left
status.ZIndex = 9
status.Parent = mapFrame
local statusPad = Instance.new("UIPadding")
statusPad.PaddingLeft, statusPad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
statusPad.Parent = status
local hints = Instance.new("TextLabel")
hints.Name = "Comandos"
hints.BackgroundTransparency = 1
hints.Size = UDim2.fromScale(1, 1)
hints.TextColor3 = UiKit.KHAKI
hints.TextTransparency = 0.25
hints.Font = Enum.Font.Arimo
hints.TextSize = TS(13)
hints.TextXAlignment = Enum.TextXAlignment.Right
hints.ZIndex = 9
hints.Parent = status
local cursorUI = Instance.new("Frame")
cursorUI.Name = "Cursor"
cursorUI.AnchorPoint = Vector2.new(0.5, 0.5)
cursorUI.Size = UDim2.fromOffset(26, 26)
cursorUI.BackgroundTransparency = 1
cursorUI.ZIndex = 9
local cs = Instance.new("UIStroke")
cs.Thickness = 3
cs.Color = Color3.fromRGB(255, 214, 0)
cs.Parent = cursorUI
local cr = Instance.new("UICorner")
cr.CornerRadius = UDim.new(1, 0)
cr.Parent = cursorUI
local cross = Instance.new("Frame")
cross.AnchorPoint = Vector2.new(0.5, 0.5)
cross.Position = UDim2.fromScale(0.5, 0.5)
cross.Size = UDim2.fromOffset(4, 4)
cross.BackgroundColor3 = Color3.fromRGB(255, 214, 0)
cross.BorderSizePixel = 0
cross.Parent = cursorUI
cursorUI.Parent = mapFrame

-- tela (GetMouseLocation, com a faixa do Roblox) -> unidades de projeto da janela do mapa. O
-- AbsolutePosition não conta a faixa de cima (GetGuiInset), o mouse conta.
CartaView.mount(mapFrame, TS, function(p: Vector2): Vector2
	local abs = mapFrame.AbsoluteSize
	local k = if abs.X > 0 then mapFrame.Size.X.Offset / abs.X else 1
	local inset = GuiService:GetGuiInset()
	return (p - inset - mapFrame.AbsolutePosition) * k
end)
local legend = CartaView.buildLegend(stage, LEGEND_RECT.x, LEGEND_RECT.y, LEGEND_RECT.w, LEGEND_RECT.h)

local B = MapConfig.Bounds
local function fromUV(u: number, v: number): (number, number)
	return Carta.fromUV(B, u, v)
end

local squadState: any = nil
local spawnList: { any } = {}
local matchState: any = nil
local mode: string = "spawn" -- "spawn" | "view" | "target"
local pinned = false
local targetAbility: string? = nil
local focusIdx: number? = nil
local mapWanted = false -- a carta pedida (a janela some depois da dobra)
local foldToken = 0

local function alive(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function readySpawns(): { any }
	local out = {}
	for _, pt in spawnList do
		if not pt.blocked then
			table.insert(out, pt)
		end
	end
	return out
end

local function spawnById(id: string): any
	for _, pt in spawnList do
		if "spawn:" .. pt.id == id then
			return pt
		end
	end
	return nil
end

local function spawnText(pt: any): string
	-- lista "nome · estado": o estado é frase ou modelo inteiro (o Lang traduz item a item)
	if pt.blocked then
		return string.format("%s · %s", pt.name, pt.why or "bloqueado")
	elseif (pt.wait or 0) > 0 then
		return string.format("%s · espera %d s", pt.name, pt.wait)
	end
	return string.format("%s · PRONTO", pt.name)
end

-- Inserção: só ponto PRONTO; a transição carrega a área antes de pedir o spawn (SpawnTransition)
local function insert(pt: any)
	if SpawnTransition.busy() then
		return
	end
	if pt.blocked or (type(pt.wait) == "number" and pt.wait > 0) then
		status.Text = spawnText(pt)
		return
	end
	SpawnTransition.go({ id = pt.id, name = pt.name, x = pt.x, z = pt.z }, function()
		Net.event("Spawn_Request"):FireServer(pt.id)
	end)
end

-- alvo da missão de fogo escolhido na carta (controle: A; mouse: clique sem arrastar)
local function chooseTarget(u: number, v: number)
	local x, z = fromUV(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
	Bus.fire("target_chosen", targetAbility, x, z)
	Bus.fire("map_target_end")
end

CartaView.setCallbacks(function(pt: any)
	if mode == "spawn" then
		insert(pt)
	end
end, function(u: number, v: number)
	if mode == "target" and not Input.isGamepad() then
		chooseTarget(u, v)
	end
end)

-- posição da carta: à direita da ficha de inserção (morto) ou no palco inteiro (em campo / alvo)
local function placeMap()
	local insertion = mode == "spawn" and side.Visible
	local r = if insertion then SPAWN_RECT else VIEW_RECT
	mapFrame.Position = UDim2.fromOffset(r.x, r.y)
	mapFrame.Size = UDim2.fromOffset(r.w, r.h)
	CartaView.resize(r.w, r.h)
	mapTab.Position = UDim2.fromOffset(r.x, r.y - 32)
	mapTab.Size = UDim2.fromOffset(r.w, 28)
	mapTab.Visible = mapWanted
	legend.Visible = mapWanted and not insertion
	mapTab.Text = if mode == "spawn"
		then "CARTA DE INSERÇÃO · escolha um ponto PRONTO"
		elseif mode == "target" then "CARTA TÁTICA · ALVO DA MISSÃO DE FOGO"
		else "CARTA TÁTICA · VẠN TƯỜNG — série L7014, folha 6739 I · sem inimigos"
	mapTab.Font = Enum.Font.Arimo
	CartaView.setMode(mode)
end

-- abre na hora; fecha dobrando a carta (0,16 s) antes de esconder
local function showMap(on: boolean)
	if on == mapWanted then
		return
	end
	mapWanted = on
	foldToken += 1
	if on then
		mapFrame.Visible = true
		CartaView.setVisible(true)
		CartaView.setMatch(matchState)
	else
		CartaView.setVisible(false)
		local my = foldToken
		CartaView.foldOut(0.16)
		task.delay(0.16, function()
			if foldToken == my then
				mapFrame.Visible = false
			end
		end)
	end
end

-- a tela de deslocamento é um "menu" (personagem parado, A confirma) enquanto não houver papel
local sideAsMenu = false
local mapOpenState = false

local function syncInput()
	local wantMenu = side.Visible and not mapWanted
	if wantMenu ~= sideAsMenu then
		sideAsMenu = wantMenu
		if wantMenu then
			Input.openMenu()
		else
			Input.closeMenu()
		end
	end
	local wantMap = mapWanted and alive()
	if wantMap ~= mapOpenState then
		mapOpenState = wantMap
		Input.event(if wantMap then "map_open" else "map_close")
	end
	-- lobby: o cursor virtual do controle manda (mesa 3D e papéis); no mapa, o cursor com ímã do
	-- mapa; fora dos dois, a navegação do Roblox
	VirtualCursor.setActive(wantMenu)
	GuiService.GuiNavigationEnabled = not mapWanted and not VirtualCursor.isActive()
	cursorUI.Visible = mapWanted and Input.isGamepad()
	if VirtualCursor.isActive() or mapWanted then
		GuiService.SelectedObject = nil
	elseif wantMenu then
		UiKit.focus(side)
	end
end

local function refresh()
	local dead = not alive()
	local hasRole = player:GetAttribute("Role") ~= nil
	side.Visible = dead or not hasRole
	DeployScreen.render(squadState) -- decide o painel (a inserção abre a carta de spawn)
	local insertion = side.Visible and dead and hasRole and DeployScreen.panel() == "insert"
	local targeting = mode == "target"
	if not targeting then
		if dead and hasRole then
			mode = "spawn"
		elseif not dead then
			mode = "view"
		end
	end
	showMap(insertion or pinned or targeting)
	placeMap()
	local faction = player:GetAttribute("Faction")
	LobbyScene.update(side.Visible, if type(faction) == "string" then faction else nil)
	syncInput()
end
DeployScreen.changed = refresh -- voltar um passo (B) e trocar de papel pelo botão mudam só o cliente

UiKit.watch(side, function()
	return side.Visible and not mapWanted
end)

-- B / Backspace na tela de deslocamento. Outro menu por cima (menu do jogo, loja, relatório) fecha
-- primeiro: os handlers de ui_back rodam todos no mesmo aperto, então olha também o quadro anterior.
local menusBefore = 0
RunService.Heartbeat:Connect(function()
	menusBefore = Input.state.menus
end)
Input.on("ui_back", "press", function()
	if Input.state.menus > 1 or menusBefore > 1 then
		return
	end
	if side.Visible and not mapWanted then
		DeployScreen.back()
	end
end)
-- LB/RB (Q/E): objeto seguinte da mesa / aba seguinte do lobby (só com o lobby por cima de tudo)
local TAB_DIR: { [string]: number } = { ui_tab_prev = -1, ui_tab_next = 1 }
for action, dir in TAB_DIR do
	Input.on(action, "press", function()
		if Input.state.menus > 1 or menusBefore > 1 then
			return
		end
		if side.Visible and not mapWanted then
			DeployScreen.cycle(dir)
		end
	end)
end

-- a carta de spawn aberta pela mesa: B (ou Select) volta para a mesa, não fecha o lobby
local function spawnMapBack(): boolean
	if mode == "spawn" and side.Visible and DeployScreen.panel() == "insert" then
		DeployScreen.open("desk")
		return true
	end
	return false
end

-- ===== entradas do mapa =====
local function moveCursorTo(pt: any)
	local u, v = Carta.toUV(B, pt.x, pt.z)
	CartaView.goTo(u, v)
end

Input.on("map", "tap", function()
	pinned = not pinned
	refresh()
end)
Input.on("map", "press", function() -- M no teclado
	pinned = not pinned
	refresh()
end)
local function closeMap()
	if mode == "target" then
		Bus.fire("map_target_end")
	end
	pinned = false
	if not spawnMapBack() then
		refresh()
	end
end
Input.on("map_close", "press", closeMap)
Input.on("map_back", "press", closeMap)
Input.on("map_next", "press", function()
	local list = readySpawns()
	focusIdx = InputMap.cycle(#list, focusIdx, 1)
	if focusIdx then
		moveCursorTo(list[focusIdx])
	end
end)
Input.on("map_prev", "press", function()
	local list = readySpawns()
	focusIdx = InputMap.cycle(#list, focusIdx, -1)
	if focusIdx then
		moveCursorTo(list[focusIdx])
	end
end)
Input.on("map_select", "press", function()
	local focused = CartaView.focused()
	if mode == "target" then
		local u, v = CartaView.cursorUV()
		chooseTarget(u, v)
	elseif mode == "spawn" and focused then
		local pt = spawnById(focused.id)
		if pt then
			insert(pt)
		end
	end
end)
Input.on("map_mark", "press", function()
	local u, v = CartaView.cursorUV()
	local x, z = fromUV(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
	Net.event("Squad_Mark"):FireServer({ pos = Vector3.new(x, 0, z), kind = "map" })
end)
Input.on("map_role", "press", function()
	if mode == "spawn" and not alive() then
		DeployScreen.open("role") -- o papel da mesa; o servidor só troca ao escolher outro (+15 s)
	elseif mode == "view" and alive() then
		-- em campo, o líder planta o ponto de reunião do squad onde está (FrontService valida)
		if player:GetAttribute("Role") == "squad_leader" then
			Net.event("SquadRally_Place"):FireServer()
		else
			Toast.show("Só o líder do squad planta o ponto de reunião", "alerta", { title = "Reunião" })
		end
	end
end)

-- modo alvo (comandante / morteiro): pedido vindo do CommanderController
Bus.on("map_target", function(ability: string, label: string?)
	targetAbility = ability
	mode = "target"
	status.Text = string.format("ALVO: %s — mova o cursor e confirme", label or ability)
	refresh()
end)
Bus.on("map_target_end", function()
	if mode == "target" then
		mode = if alive() then "view" else "spawn"
		targetAbility = nil
		refresh()
	end
end)

-- comandos na faixa de estado, pelo dispositivo
local function hintText(): string
	if Input.isGamepad() then
		if mode == "spawn" then
			return "LB/RB pontos · A inserir · gatilhos zoom · Y papel · B volta"
		elseif mode == "target" then
			return "A confirma o alvo · gatilhos zoom · B cancela"
		end
		return "gatilhos zoom · R arrasta · L3 você · X marca · Y reunião do squad · B fecha"
	end
	if mode == "spawn" then
		return "clique num ponto PRONTO · roda zoom · arraste · R papel · M volta"
	elseif mode == "target" then
		return "clique no alvo · roda zoom · arraste · M cancela"
	end
	return "roda zoom · arraste · X marca · R reunião do squad · M fecha"
end

local function statusLine(): string
	local st = matchState
	if not st then
		return string.format("Carta · %s", CartaView.cursorGrid())
	end
	-- lista "A · B · C": cada pedaço é frase ou modelo inteiro (o Lang traduz item a item)
	local t = math.floor(st.timeLeft or 0)
	local parts = { string.format("%s %02d:%02d", UiKit.upper(st.mode), t // 60, t % 60) }
	if st.ended then
		local w = st.winner or ReplicatedStorage:GetAttribute("LastWinner")
		table.insert(parts, if w == "US" then "vitória dos EUA" elseif w == "VC" then "vitória do VC" else "empate")
	elseif st.mode == "Offensive" and st.front and st.front >= 1 then
		table.insert(parts, string.format("frente S%d", st.front))
	end
	table.insert(parts, string.format("cursor %s", CartaView.cursorGrid()))
	return table.concat(parts, " · ")
end

-- quadro a quadro: zoom, arrasto, cursor e ímã ficam na CartaView
local lastStatus = 0
RunService.RenderStepped:Connect(function(dt: number)
	if not mapWanted then
		return
	end
	local pad = Input.isGamepad() and not (Input.state.disconnected or Input.state.robloxMenu)
	CartaView.step(dt, pad)
	cursorUI.Position = UDim2.fromOffset(CartaView.cursorPx().X, CartaView.cursorPx().Y)
	local now = os.clock()
	if now - lastStatus > 0.1 then
		lastStatus = now
		local focused = CartaView.focused()
		local pt = if focused and mode == "spawn" then spawnById(focused.id) else nil
		if pt then
			status.Text = spawnText(pt)
		elseif mode ~= "target" or targetAbility == nil then
			status.Text = statusLine()
		else
			status.Text = string.format("ALVO %s — confirme", CartaView.cursorGrid())
		end
		hints.Text = hintText()
		if legend.Visible then
			CartaView.updateLegend()
		end
	end
end)

-- ===== estado do jogo =====
Net.event("Squad_State").OnClientEvent:Connect(function(st)
	squadState = st
	refresh()
end)
Net.event("Spawn_State").OnClientEvent:Connect(function(st)
	spawnList = st
	CartaView.setSpawns(st)
end)
Net.event("Match_State").OnClientEvent:Connect(function(st)
	-- "quem está tomando" vem como lista cheia com "" = ninguém (MatchService.publish)
	if type(st) == "table" and type(st.capturing) == "table" then
		for i, v in st.capturing do
			if v == "" then
				st.capturing[i] = nil
			end
		end
	end
	matchState = st
	if mapWanted then
		CartaView.setMatch(st)
	end
end)
Net.event("Squad_Mark").OnClientEvent:Connect(function(m)
	CartaView.addMark(m)
end)
-- FrontService: pontos de inserção do lado (em campo), o squad e o ponto de reunião do squad
task.spawn(function()
	Net.event("Spawn_Points").OnClientEvent:Connect(function(list)
		CartaView.setInserts(list)
	end)
	Net.event("Squad_Positions").OnClientEvent:Connect(function(list)
		CartaView.setSquad(list)
	end)
	Net.event("SquadRally_State").OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" or type(msg.msg) ~= "string" then
			return
		end
		local kind = if msg.ok then "sucesso" elseif msg.lost then "alerta" else "erro"
		Toast.show(msg.msg, kind, { title = "Reunião do squad", key = "reuniao_squad" })
	end)
end)
for _, a in { "Faction", "SquadId", "Role" } do
	player:GetAttributeChangedSignal(a):Connect(refresh)
end
player.CharacterAdded:Connect(function(char)
	pinned = false
	refresh()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Died:Connect(refresh)
	refresh() -- o CharacterAdded chega antes do Humanoid: sem isto o mapa de spawn ficava na tela
end)
Input.DeviceChanged:Connect(refresh)

-- aviso enquanto o servidor gera o terreno (faixa datilografada à direita dos passos)
local loading = Instance.new("TextLabel")
loading.Position = UDim2.fromOffset(660, 138) -- entre as abas do lobby e os papéis
loading.Size = UDim2.fromOffset(580, 20)
loading.BackgroundColor3 = UiKit.NIGHT
loading.BackgroundTransparency = 0.35
loading.BorderSizePixel = 0
loading.TextColor3 = UiKit.KHAKI
loading.TextXAlignment = Enum.TextXAlignment.Right
loading.Font = Enum.Font.SpecialElite
loading.TextSize = TS(16)
loading.Text = "● Preparando o campo de batalha (terreno de 4 x 2,4 km)…"
loading.ZIndex = 3
loading.Parent = stage
local loadingPad = Instance.new("UIPadding")
loadingPad.PaddingRight = UDim.new(0, 8)
loadingPad.Parent = loading
local function loadingState()
	loading.Visible = ReplicatedStorage:GetAttribute("TerrainReady") == false
end
ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Connect(loadingState)
loadingState()

-- palco: cabe na tela inteira (na TV, com margem de segurança e nunca menor que 1:1)
local function fit()
	local s = gui.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return
	end
	local k = math.min(s.X / DESIGN_W, s.Y / DESIGN_H)
	if UiKit.tv() then
		k = math.max(k * 0.92, 1)
	end
	stageScale.Scale = k
	DeployScreen.setScale(k)
	status.TextSize = TS(15)
	hints.TextSize = TS(13)
	mapTab.TextSize = TS(16)
	loading.TextSize = TS(16)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()
refresh()

-- ===== gancho de teste (só no Studio): foto da carta =====
-- Na barra de comando do lado do cliente: workspace:SetAttribute("VT65DevCarta", "abrir") abre a carta
-- em campo; "zoom" aproxima na frente; "fechar" fecha. Volta a nil sozinho (dá para repetir).
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevCarta"):Connect(function()
		local v = workspace:GetAttribute("VT65DevCarta")
		if type(v) ~= "string" then
			return
		end
		if v == "abrir" or v == "zoom" then
			pinned = true
			refresh()
			if v == "zoom" and matchState and matchState.points then
				local f = player:GetAttribute("Faction")
				local best = nil
				for s, p in matchState.points do
					if matchState.active[s] and matchState.owner[s] ~= f then
						best = p
						break
					end
				end
				if best then
					moveCursorTo(best)
				end
			end
		elseif v == "fechar" then
			pinned = false
			refresh()
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevCarta", nil)
		end)
	end)
end
