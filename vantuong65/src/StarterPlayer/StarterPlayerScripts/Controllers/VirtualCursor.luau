--!strict
-- Cursor virtual do controle (pedido do dono: "escolher no controle como se o analógico fosse o
-- mouse"). Fica ligado enquanto alguém pede (VirtualCursor.setActive; o GameUI liga no lobby) e só
-- aparece quando o jogador está no controle:
--   - analógico esquerdo: move o cursor, com zona morta radial (a do jogador, nunca menor que 0,14),
--     curva de resposta (fino perto do centro) e aceleração depois de segurar no máximo; sobre um
--     alvo ele desacelera (ímã leve), para ser fácil parar em cima;
--   - A: clica no botão 2D sob o cursor (registrado com VirtualCursor.bind; o UiKit.button registra
--     sozinho) ou, se não houver interface por cima, no objeto 3D da cena (VirtualCursor.world, do
--     LobbyScene, que faz o raycast);
--   - direcional: pula para o alvo mais próximo naquela direção (botões e objetos da mesa);
--   - analógico direito: rola a lista sob o cursor.
-- B, LB/RB e LT/RT continuam nas ações ui_back, ui_tab_* e ui_sub_* do contexto "menu" (Input).
-- Coordenadas: pixels da janela (as de GetMouseLocation e ViewportPointToRay). A interface 2D usa as
-- mesmas menos o GuiInset (é o espaço do AbsolutePosition e do GetGuiObjectsAtPosition).
-- Com o mouse e no toque nada daqui aparece: o ponteiro é o próprio mouse (VirtualCursor.pointer).
-- No toque (Parte 13), o mesmo registro dá o "dedo gordo": um toque curto que cai perto de um botão
-- registrado (no vão entre dois, na borda arredondada, num botão pequeno da tela encolhida) aciona
-- o botão cujo alvo, aumentado até o mínimo de toque (ToqueUi.minPx), contém o dedo. Só com tela
-- aberta (menu, mapa, morto); o toque em cima de um botão de verdade fica com o próprio botão.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Input = require(script.Parent.Input)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)

local VirtualCursor = {}
local player = Players.LocalPlayer

-- ===== ajuste (design; conferir a sensação no controle de verdade) =====
local SPEED = 0.8 -- alturas de tela por segundo, analógico no máximo, antes da aceleração
local BOOST = 0.85 -- +85% depois de segurar no máximo
local BOOST_AFTER, BOOST_RAMP = 0.3, 0.35 -- s
local STICKY = 0.45 -- fator de velocidade sobre um alvo (só antes da aceleração)
local CURVE = 1.7 -- expoente da resposta
local DEAD_MIN = 0.14 -- zona morta mínima do cursor (o drift de controle velho não arrasta)
local SCROLL = 1100 -- px/s de rolagem pelo analógico direito
local JUMP_TIME = 0.09 -- s do pulo do direcional
local HOT = Color3.fromRGB(255, 214, 0) -- o amarelo do foco do UiKit
local COLD = Color3.fromRGB(232, 222, 190)
local INK = Color3.fromRGB(20, 18, 14)

type Binding = { activate: () -> (), hover: ((boolean) -> ())? }
local bound: { [GuiObject]: Binding } = {}

export type World = {
	-- A sobre a cena 3D (sem interface por cima): o dono faz o raycast nesse ponto
	activate: (pos: Vector2) -> (),
	-- pontos (pixels da janela) para o direcional pular entre objetos da cena
	targets: (() -> { Vector2 })?,
}
VirtualCursor.world = nil :: World?
VirtualCursor.worldHot = false -- o LobbyScene avisa quando o cursor está sobre um objeto (ímã)

local active = false
local pos = Vector2.zero
local held = 0
local hovered: GuiObject? = nil
local scrollTarget: ScrollingFrame? = nil
local lastProbe = Vector2.new(-1, -1)
local lastProbeT = 0
local nextProbe = 0
local jumpFrom: Vector2? = nil
local jumpTo: Vector2? = nil
local jumpT = 0
local pulse = 0 -- s de "clique" no anel

-- ===== desenho =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Cursor"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60 -- acima de todos os menus
gui.IgnoreGuiInset = true
gui.Enabled = false
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)

local function ringFrame(size: number, thick: number, color: Color3, tr: number): (Frame, UIStroke)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundTransparency = 1
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Thickness = thick
	s.Color = color
	s.Transparency = tr
	s.Parent = f
	return f, s
end

-- mira de bússola: anel claro sobre contorno escuro, ponto e quatro traços (leitura em qualquer fundo)
local holder = Instance.new("Frame")
holder.Name = "Cursor"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Size = UDim2.fromOffset(40, 40)
holder.BackgroundTransparency = 1
holder.Parent = gui
local shadowRing, shadowStroke = ringFrame(30, 5, INK, 0.35)
shadowRing.Parent = holder
local ring, ringStroke = ringFrame(30, 2.5, COLD, 0)
ring.Parent = holder
local dot = Instance.new("Frame")
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = COLD
dot.BorderSizePixel = 0
local dc = Instance.new("UICorner")
dc.CornerRadius = UDim.new(1, 0)
dc.Parent = dot
local ds = Instance.new("UIStroke")
ds.Color = INK
ds.Thickness = 1.5
ds.Transparency = 0.3
ds.Parent = dot
dot.Parent = holder
local ticks: { Frame } = {}
for i = 0, 3 do
	local t = Instance.new("Frame")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	local a = i * math.pi / 2
	t.Position = UDim2.new(0.5, math.sin(a) * 19, 0.5, -math.cos(a) * 19)
	t.Size = if i % 2 == 0 then UDim2.fromOffset(2, 7) else UDim2.fromOffset(7, 2)
	t.BackgroundColor3 = COLD
	t.BorderSizePixel = 0
	local ts = Instance.new("UIStroke")
	ts.Color = INK
	ts.Thickness = 1
	ts.Transparency = 0.4
	ts.Parent = t
	t.Parent = holder
	table.insert(ticks, t)
end

-- moldura em volta do botão sob o cursor (a mesma ideia do foco do UiKit)
local focusBox = Instance.new("Frame")
focusBox.Name = "Focus"
focusBox.BackgroundTransparency = 1
focusBox.Visible = false
local fs = Instance.new("UIStroke")
fs.Thickness = 3
fs.Color = HOT
fs.Parent = focusBox
focusBox.Parent = gui

task.spawn(function()
	gui.Parent = player:WaitForChild("PlayerGui")
end)

-- ===== registro de botões 2D =====
-- activate: o mesmo do Activated; hover: realce opcional (o cursor também desenha a moldura)
function VirtualCursor.bind(obj: GuiObject, activate: () -> (), hover: ((boolean) -> ())?)
	local first = bound[obj] == nil
	bound[obj] = { activate = activate, hover = hover }
	if first then
		obj.Destroying:Connect(function()
			bound[obj] = nil
			if hovered == obj then
				hovered = nil
			end
		end)
	end
end

function VirtualCursor.unbind(obj: GuiObject)
	bound[obj] = nil
end

-- ===== geometria da interface =====
local function inset(): Vector2
	local tl = GuiService:GetGuiInset()
	return tl
end

local function insideRect(o: GuiObject, gp: Vector2): boolean
	local a, s = o.AbsolutePosition, o.AbsoluteSize
	return gp.X >= a.X and gp.Y >= a.Y and gp.X <= a.X + s.X and gp.Y <= a.Y + s.Y
end

-- Interactable = false (véus, sombras, filme, rótulos que não recebem clique): não conta no ponto
local hasInteractable = pcall(function()
	return (Instance.new("Frame") :: any).Interactable
end)
local function interactive(o: GuiObject): boolean
	return not hasInteractable or (o :: any).Interactable ~= false
end

-- visível de verdade naquele ponto: toda a cadeia visível e interativa, tela ligada e sem corte
-- de rolagem
local function shownAt(o: GuiObject, gp: Vector2): boolean
	local cur: Instance? = o
	while cur do
		if cur:IsA("GuiObject") then
			if not cur.Visible or not interactive(cur) then
				return false
			end
			if cur ~= o and cur.ClipsDescendants and not insideRect(cur, gp) then
				return false
			end
		elseif cur:IsA("LayerCollector") then
			return cur.Enabled
		end
		cur = cur.Parent
	end
	return false
end

-- o botão registrado que contém este pedaço (a seta, o rótulo ou a lista dentro de um cartão)
local function boundAncestor(o: Instance): GuiObject?
	local cur = o.Parent
	while cur and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") and bound[cur] then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- Botão registrado sob o ponto (pixels da janela) e se há interface tapando a cena 3D ali.
-- "Tapa" = botão de qualquer tipo, lista rolável ou quadro com Active (painéis do lobby).
-- Correção (pedido do dono, 2026-11-11: "às vezes estou em cima do que eu quero e não vai"): um
-- botão ou quadro Active DENTRO do botão registrado (as setas ◄ ► da linha do menu, uma lista no
-- cartão) tapava o próprio botão: o A não ia. Agora a peça de dentro devolve o botão que a contém.
function VirtualCursor.guiAt(p: Vector2): (GuiObject?, boolean, ScrollingFrame?)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil, false, nil
	end
	local gp = p - inset()
	local ok, list = pcall(function()
		return pg:GetGuiObjectsAtPosition(gp.X, gp.Y)
	end)
	if not ok or type(list) ~= "table" then
		return nil, false, nil
	end
	local scroller: ScrollingFrame? = nil
	for _, o in list :: { GuiObject } do
		if o:IsDescendantOf(gui) then
			continue -- o próprio cursor
		end
		if not shownAt(o, gp) then
			continue
		end
		if not scroller and o:IsA("ScrollingFrame") then
			scroller = o
		end
		local hit: GuiObject? = if bound[o] then o else nil
		if not hit and (o:IsA("GuiButton") or o:IsA("ScrollingFrame") or o.Active) then
			hit = boundAncestor(o)
			if not hit then
				return nil, true, scroller -- peça solta por cima: tapa
			end
		end
		if hit then
			if not scroller then
				-- a lista que contém o botão rola junto
				scroller = hit:FindFirstAncestorWhichIsA("ScrollingFrame")
			end
			return hit, true, scroller
		end
	end
	return nil, false, scroller
end

-- distância do ponto (pixels da janela) até a caixa do objeto (0 dentro)
local function rectDist(o: GuiObject, p: Vector2): number
	local a = o.AbsolutePosition + inset()
	local s = o.AbsoluteSize
	local dx = math.max(a.X - p.X, 0, p.X - (a.X + s.X))
	local dy = math.max(a.Y - p.Y, 0, p.Y - (a.Y + s.Y))
	return math.sqrt(dx * dx + dy * dy)
end

-- O alvo é o que o anel do cursor cobre, não só o pixel do meio: sem botão no ponto, procura num
-- círculo do tamanho do anel (o meio do cursor caía no vão de 2 px entre duas linhas, ou na
-- borda arredondada, e o A não ia com o anel em cima do botão). Fica o mais perto do meio.
local REACH = 13 -- px: o raio do anel
local RING_DIRS: { Vector2 } = {}
for i = 0, 7 do
	local a = i * math.pi / 4
	table.insert(RING_DIRS, Vector2.new(math.cos(a), math.sin(a)))
end
local function targetAt(p: Vector2): (GuiObject?, boolean, ScrollingFrame?)
	local b, over, sf = VirtualCursor.guiAt(p)
	if b then
		return b, over, sf
	end
	local best: GuiObject?, bestD, bestSf = nil, math.huge, sf
	for _, dir in RING_DIRS do
		local q = p + dir * REACH
		local hb, _, hsf = VirtualCursor.guiAt(q)
		if hb then
			local d = rectDist(hb, p)
			if d < bestD then
				best, bestD, bestSf = hb, d, hsf
			end
		end
	end
	if best then
		return best, true, bestSf
	end
	return nil, over, sf
end
VirtualCursor.targetAt = targetAt

-- A interface tapa a cena neste ponto? (o LobbyScene pergunta antes de realçar um objeto 3D, a
-- cada quadro). No cursor virtual vale o resultado da última sondagem (o mesmo alvo do realce e do
-- A, já com o alcance do anel); com o mouse, o ponto exato.
local probeOver = false
local probePos = Vector2.new(-1, -1)
function VirtualCursor.overGui(p: Vector2): boolean
	if p == probePos then
		return probeOver
	end
	local _, over = VirtualCursor.guiAt(p)
	return over
end

-- ===== estado público =====
-- ligado pelo dono da tela E o jogador no controle (o anel está na tela)
function VirtualCursor.isActive(): boolean
	return active and Input.isGamepad()
end

-- Ponteiro em pixels da janela: o cursor virtual no controle, o mouse no teclado/mouse; nil no
-- toque (não há "passar por cima") ou com o cursor desligado.
function VirtualCursor.pointer(): Vector2?
	if not active then
		return nil
	end
	local d = Input.device()
	if d == "gamepad" then
		return pos
	elseif d == "touch" then
		return nil
	end
	return UserInputService:GetMouseLocation()
end

function VirtualCursor.hoveredGui(): GuiObject?
	return hovered
end

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

local function clampPos(p: Vector2): Vector2
	local vp = viewport()
	return Vector2.new(math.clamp(p.X, 0, vp.X), math.clamp(p.Y, 0, vp.Y))
end

-- leva o cursor até um ponto (LB/RB do lobby pulam entre os objetos da mesa)
function VirtualCursor.moveTo(p: Vector2)
	jumpFrom, jumpTo, jumpT = pos, clampPos(p), 0
end

function VirtualCursor.setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	if on then
		local vp = viewport()
		if pos == Vector2.zero then
			pos = vp / 2
		end
		pos = clampPos(pos)
		GuiService.SelectedObject = nil
	else
		jumpTo = nil
	end
end

-- ===== realce =====
local function setHover(b: GuiObject?)
	if b == hovered then
		return
	end
	local old = hovered
	hovered = b
	if old then
		local bd = bound[old]
		local hv = bd and bd.hover
		if hv then
			task.spawn(hv, false)
		end
	end
	if b then
		local bd = bound[b]
		local hv = bd and bd.hover
		if hv then
			task.spawn(hv, true)
		end
	end
	focusBox.Visible = b ~= nil
end

-- ===== ações =====
local function click()
	pulse = 0.18
	GuiService.SelectedObject = nil -- nada da navegação do Roblox ativa o mesmo botão
	-- o mesmo alvo do realce: o que está aceso é o que o A aciona
	local b, over = targetAt(pos)
	local h = hovered
	if not b and h and h.Parent and h.Visible and rectDist(h, pos) <= REACH then
		b, over = h, true
	end
	if b then
		local bd = bound[b]
		if bd then
			task.spawn(bd.activate)
		end
		return
	end
	if over then
		return -- painel ou botão não registrado por cima: não clica na cena atrás
	end
	local w = VirtualCursor.world
	if w then
		task.spawn(w.activate, pos)
	end
end

local function candidates(): { Vector2 }
	local out = {}
	local ins = inset()
	for o in bound do
		if o.Parent == nil then
			continue
		end
		local size = o.AbsoluteSize
		if size.X < 2 or size.Y < 2 then
			continue
		end
		local c = o.AbsolutePosition + size / 2
		if shownAt(o, c) then
			local top = VirtualCursor.guiAt(c + ins)
			if top == o then
				table.insert(out, c + ins)
			end
		end
	end
	local w = VirtualCursor.world
	if w and w.targets then
		for _, p in w.targets() do
			local _, over = VirtualCursor.guiAt(p)
			if not over then
				table.insert(out, p)
			end
		end
	end
	return out
end

-- direcional: o alvo mais próximo à frente, com peso para o desvio lateral
local function jump(dir: Vector2)
	local best: Vector2? = nil
	local bestScore = math.huge
	for _, c in candidates() do
		local d = c - pos
		local along = d.X * dir.X + d.Y * dir.Y
		if along > 10 then
			local across = math.abs(d.X * dir.Y - d.Y * dir.X)
			local score = along + across * 2.2
			if score < bestScore then
				best, bestScore = c, score
			end
		end
	end
	if best then
		VirtualCursor.moveTo(best)
	end
end

local DPAD: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.DPadUp] = Vector2.new(0, -1),
	[Enum.KeyCode.DPadDown] = Vector2.new(0, 1),
	[Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
	[Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
}

UserInputService.InputBegan:Connect(function(input: InputObject)
	if not (active and Input.isGamepad()) then
		return
	end
	if string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
		return
	end
	if Input.state.disconnected or Input.state.robloxMenu then
		return
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.ButtonA then
		click()
	elseif DPAD[kc] then
		jump(DPAD[kc])
	end
end)

-- ===== toque: dedo gordo (Parte 13) =====
-- Peças que não querem ímã (a carta do mapa trata o toque dela): atributo VT65SemIma no caminho.
local function noSnap(o: Instance): boolean
	local cur: Instance? = o
	while cur and not cur:IsA("LayerCollector") do
		if cur:GetAttribute("VT65SemIma") then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- Botão registrado que um toque em p (pixels da janela) quis, ou nil: o dedo em cima de um botão de
-- verdade (qualquer GuiButton ou caixa de texto) fica com ele; senão, o alvo aumentado mais perto.
function VirtualCursor.touchSnap(p: Vector2): GuiObject?
	if not ToqueUi.active() then
		return nil
	end
	local s = Input.state
	if not (s.menus > 0 or s.map or not s.alive) then
		return nil -- em jogo, o toque é do HUD e da câmera
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local gp = p - inset()
	local ok, list = pcall(function()
		return pg:GetGuiObjectsAtPosition(gp.X, gp.Y)
	end)
	if not ok or type(list) ~= "table" then
		return nil
	end
	for _, o in list :: { GuiObject } do
		if o:IsDescendantOf(gui) or not shownAt(o, gp) then
			continue
		end
		if o:IsA("GuiButton") or o:IsA("TextBox") or bound[o] or noSnap(o) then
			return nil
		end
	end
	local min = ToqueUi.minPx()
	local rects: { ToqueTelas.Rect } = {}
	for o in bound do
		if o.Parent == nil or not o.Visible then
			continue
		end
		local a, sz = o.AbsolutePosition, o.AbsoluteSize
		local ex, ey, ew, eh = ToqueTelas.expand(a.X, a.Y, sz.X, sz.Y, min, min)
		if gp.X < ex or gp.X > ex + ew or gp.Y < ey or gp.Y > ey + eh then
			continue
		end
		-- de verdade na tela: a cadeia visível e o botão por cima no próprio centro
		local c = a + sz / 2
		if shownAt(o, c) and VirtualCursor.guiAt(c + inset()) == o then
			table.insert(rects, { id = o, x = a.X, y = a.Y, w = sz.X, h = sz.Y })
		end
	end
	return ToqueTelas.pick(gp.X, gp.Y, rects, min)
end

local touches: { [InputObject]: { p: Vector2, t: number } } = {}
UserInputService.InputBegan:Connect(function(io: InputObject)
	if io.UserInputType == Enum.UserInputType.Touch then
		touches[io] = { p = Vector2.new(io.Position.X, io.Position.Y), t = os.clock() }
	end
end)
UserInputService.InputEnded:Connect(function(io: InputObject)
	if io.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local t0 = touches[io]
	touches[io] = nil
	if not t0 then
		return
	end
	local p = Vector2.new(io.Position.X, io.Position.Y)
	local d = p - t0.p
	if not ToqueTelas.isTap(os.clock() - t0.t, d.X, d.Y) then
		return
	end
	local b = VirtualCursor.touchSnap(p + inset())
	local bd = b and bound[b]
	if bd then
		task.spawn(bd.activate)
	end
end)

-- trocou para o controle no meio da tela: o cursor nasce onde o mouse estava
Input.DeviceChanged:Connect(function(d: string)
	if d == "gamepad" and active then
		pos = clampPos(UserInputService:GetMouseLocation())
		GuiService.SelectedObject = nil
	elseif d ~= "gamepad" then
		setHover(nil)
	end
end)

-- ===== quadro a quadro (sem criar tabela nem instância) =====
RunService.RenderStepped:Connect(function(dt: number)
	local on = active and Input.isGamepad() and not (Input.state.disconnected or Input.state.robloxMenu)
	gui.Enabled = on
	if not on then
		if hovered then
			setHover(nil)
		end
		VirtualCursor.worldHot = false
		return
	end
	local vp = viewport()
	-- pulo do direcional / LB-RB (curto e suave)
	local jf, jt = jumpFrom, jumpTo
	if jf and jt then
		jumpT += dt
		local a = math.clamp(jumpT / JUMP_TIME, 0, 1)
		pos = jf:Lerp(jt, 1 - (1 - a) * (1 - a))
		if a >= 1 then
			jumpFrom, jumpTo = nil, nil
		end
	end
	-- analógico esquerdo
	local raw = Input.stickRaw("left")
	local inner = math.max(Input.settings.moveInner, DEAD_MIN)
	local x, y = InputMap.radialDeadzone(raw.X, raw.Y, inner, math.max(Input.settings.moveOuter, inner + 0.1))
	local m = math.sqrt(x * x + y * y)
	if m > 0 then
		jumpFrom, jumpTo = nil, nil -- o analógico manda
		if m >= 0.95 then
			held += dt
		else
			held = 0
		end
		local boost = 1 + BOOST * math.clamp((held - BOOST_AFTER) / BOOST_RAMP, 0, 1)
		local hot = hovered ~= nil or VirtualCursor.worldHot
		local sticky = if hot and held < BOOST_AFTER then STICKY else 1
		local speed = SPEED * vp.Y * (m ^ CURVE) * boost * sticky
		pos = clampPos(pos + Vector2.new(x / m, -y / m) * speed * dt)
	else
		held = 0
	end
	-- interface sob o cursor: quando mexe (até 30 vezes por segundo) e de vez em quando (a lista
	-- pode ter rolado). O mesmo targetAt do A: realce e clique pegam sempre o mesmo botão.
	local now = os.clock()
	if ((pos - lastProbe).Magnitude > 0.5 and now - lastProbeT >= 1 / 30) or now >= nextProbe then
		lastProbe = pos
		lastProbeT = now
		nextProbe = now + 0.15
		local b, over, sf = targetAt(pos)
		setHover(b)
		scrollTarget = sf
		probePos, probeOver = pos, over
	end
	-- analógico direito: rola a lista sob o cursor
	local sf = scrollTarget
	if sf and sf.Parent then
		local r = Input.stickRaw("right")
		local _, ry = InputMap.radialDeadzone(0, r.Y, 0.2, 0.95)
		if ry ~= 0 then
			local maxY = math.max(sf.AbsoluteCanvasSize.Y - sf.AbsoluteWindowSize.Y, 0)
			local cp = sf.CanvasPosition
			sf.CanvasPosition = Vector2.new(cp.X, math.clamp(cp.Y - ry * SCROLL * dt, 0, maxY))
		end
	end
	-- desenho
	local hot = hovered ~= nil or VirtualCursor.worldHot
	pulse = math.max(pulse - dt, 0)
	local size = (if hot then 36 else 30) - pulse * 30
	holder.Position = UDim2.fromOffset(pos.X, pos.Y)
	ring.Size = UDim2.fromOffset(size, size)
	shadowRing.Size = ring.Size
	local color = if hot then HOT else COLD
	ringStroke.Color = color
	dot.BackgroundColor3 = color
	for _, t in ticks do
		t.BackgroundColor3 = color
	end
	shadowStroke.Transparency = if hot then 0.2 else 0.35
	local h = hovered
	if h then
		local ins = inset()
		focusBox.Position = UDim2.fromOffset(h.AbsolutePosition.X + ins.X - 3, h.AbsolutePosition.Y + ins.Y - 3)
		focusBox.Size = UDim2.fromOffset(h.AbsoluteSize.X + 6, h.AbsoluteSize.Y + 6)
	end
end)

return VirtualCursor
