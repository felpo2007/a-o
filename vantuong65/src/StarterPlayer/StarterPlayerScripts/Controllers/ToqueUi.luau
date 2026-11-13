--!strict
-- Toque (Parte 13, T2): peças de runtime das telas e das ações no toque. A lógica pura fica no
-- ToqueTelas (testada no Lune).
--   - active(): o toque é a entrada agora (Input.touchActive do T1; antes dele, Input.device());
--   - minPx()/firePx(): tamanho físico do contrato (Shared/Toque.px do T1; sem ele, 48 e 84 px);
--   - press/tap/hold: apertam a ação como o botão físico dela (Input.virtual do T1, protegido);
--   - slot(nome): o lugar que o HUD do T1 reservou (um GuiObject com esse nome) para um botão nosso;
--   - roundButton(): botão redondo de polegar com glifo, rótulo curto e anel de progresso.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Estilo = require(game:GetService("ReplicatedFirst"):WaitForChild("Estilo"))
local Input = require(script.Parent.Input)
local ToqueTelas = require(script.Parent.ToqueTelas)

local ToqueUi = {}
local player = Players.LocalPlayer
local V, F = Estilo.V, Estilo.F

-- Shared/Toque (T1): px(mm, screenPx = lado curto, dpiGuess). Protegido (pcall).
local Toque: any = nil
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local m = shared and shared:FindFirstChild("Toque")
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" then
			Toque = mod
		end
	end
end
ToqueUi.Toque = Toque

local devForce = false -- gancho de Studio: as telas de toque aparecem sem aparelho

-- O toque é a entrada principal agora?
function ToqueUi.active(): boolean
	if devForce then
		return true
	end
	local I = Input :: any
	if type(I.touchActive) == "function" then
		local ok, v = pcall(I.touchActive)
		return ok and v == true
	end
	return Input.device() == "touch"
end

function ToqueUi.setDev(on: boolean)
	devForce = on
end

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

-- px de interface para mm físicos (Shared/Toque); reserva: 9 mm = ToqueTelas.MIN_PX
function ToqueUi.px(mm: number): number
	local T = Toque
	if T and type(T.px) == "function" then
		local vp = viewport()
		local ok, v = pcall(T.px, mm, math.min(vp.X, vp.Y), nil)
		if ok and type(v) == "number" and v == v and v > 0 then
			return math.clamp(v, mm * 3, mm * 16)
		end
	end
	return mm / 9 * ToqueTelas.MIN_PX
end

function ToqueUi.minPx(): number
	return math.max(math.floor(ToqueUi.px(9) + 0.5), 40)
end

function ToqueUi.firePx(): number
	return math.max(math.floor(ToqueUi.px(16) + 0.5), 64)
end

-- ===== ações virtuais (Input.virtual do T1) =====
function ToqueUi.hasVirtual(): boolean
	return type((Input :: any).virtual) == "function"
end

-- aperta (true) ou solta (false) a ação (spec do Input.virtual: "acao", "a|b", "acao:tap");
-- devolve se o Input aceitou (contexto e estado)
function ToqueUi.press(actionId: string, down: boolean): boolean
	local f = (Input :: any).virtual
	if type(f) ~= "function" then
		return false
	end
	local ok, accepted = pcall(f, actionId, down)
	return ok and accepted ~= false
end

-- toque curto (as ações "tap" disparam ao soltar antes do tempo de segurar). Solta sempre, mesmo
-- recusado: o Input guarda o dedo no botão (virtualDown) até a soltura.
function ToqueUi.tap(actionId: string): boolean
	if not ToqueUi.hasVirtual() then
		return false
	end
	local ok = ToqueUi.press(actionId, true)
	task.delay(0.05, function()
		ToqueUi.press(actionId, false)
	end)
	return ok
end

-- segurar um instante (as ações "hold" começam no aperto ou depois do tempo de segurar)
function ToqueUi.hold(actionId: string): boolean
	if not ToqueUi.hasVirtual() then
		return false
	end
	local ok = ToqueUi.press(actionId, true)
	task.delay((Input.settings.holdTime or 0.3) + 0.08, function()
		ToqueUi.press(actionId, false)
	end)
	return ok
end

-- ===== lugar reservado no HUD do T1 =====
-- O HUD de toque (ToqueHud, ScreenGui "VT65Toque") publica a vaga do botão contextual nos atributos
-- InteractPos (centro, espaço do AbsolutePosition), InteractSize (px) e InteractVisible (a vaga está
-- ligada no layout e o soldado a pé). Sem ele, um GuiObject com o nome pedido numa tela que não é a
-- nossa. Devolve centro, lado e se a vaga está ligada (nil: não se sabe).
local slotCache: { [string]: GuiObject } = {}
function ToqueUi.slot(name: string, mine: Instance?): (Vector2?, number?, boolean?)
	local pg0 = player:FindFirstChildOfClass("PlayerGui")
	local hud = pg0 and pg0:FindFirstChild("VT65Toque")
	if hud and name == "Interagir" then
		local pos, size = hud:GetAttribute("InteractPos"), hud:GetAttribute("InteractSize")
		if typeof(pos) == "Vector2" then
			local vis = hud:GetAttribute("InteractVisible")
			return pos, if type(size) == "number" then size else nil, if type(vis) == "boolean" then vis else nil
		end
	end
	local cached: GuiObject? = slotCache[name]
	if not (cached and cached.Parent) then
		cached = nil
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if pg then
			for _, d in pg:GetDescendants() do
				if d.Name == name and d:IsA("GuiObject") and not (mine and d:IsDescendantOf(mine)) then
					cached = d
					break
				end
			end
		end
		if cached then
			slotCache[name] = cached
		end
	end
	local o = cached
	if o and o.AbsoluteSize.X > 2 then
		return o.AbsolutePosition + o.AbsoluteSize / 2, math.min(o.AbsoluteSize.X, o.AbsoluteSize.Y), nil
	end
	return nil, nil, nil
end

-- ===== faixa livre no alto (entre os botões de cima do HUD de toque) =====
-- Lê os botões visíveis da tela "VT65Toque" (só posição e tamanho). Devolve, no espaço do
-- AbsolutePosition: o vão (x0, x1) e a base dos botões do alto. Sem o HUD na tela: a tela inteira.
function ToqueUi.topBand(): (number, number, number)
	local vp = viewport()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("VT65Toque")
	local area = hud and hud:FindFirstChild("Area")
	if not (hud and hud:IsA("ScreenGui") and hud.Enabled and area and area:IsA("GuiObject")) then
		return 0, vp.X, 0
	end
	local rects: { ToqueTelas.Rect } = {}
	for _, b in area:GetChildren() do
		if b:IsA("GuiButton") and b.Visible then
			local p, s = b.AbsolutePosition, b.AbsoluteSize
			table.insert(rects, { id = b.Name, x = p.X, y = p.Y, w = s.X, h = s.Y })
		end
	end
	local a = area.AbsolutePosition
	local sz = area.AbsoluteSize
	return ToqueTelas.topBand(rects, a.X, a.X + sz.X, a.Y + sz.Y * 0.22)
end

-- ===== botão redondo de polegar =====
export type Ring = { frame: Frame, set: (frac: number) -> () }

-- Anel de progresso em segmentos (o Roblox não desenha arco): n pontos em volta, acendem no sentido
-- do relógio a partir do alto.
function ToqueUi.ring(parent: GuiObject, n: number, color: Color3?): Ring
	local f = Instance.new("Frame")
	f.Name = "Anel"
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.new(1, 10, 1, 10)
	f.ZIndex = parent.ZIndex + 2
	pcall(function()
		f.Interactable = false
	end)
	f.Parent = parent
	local dots: { Frame } = {}
	for i = 1, n do
		local a = (i - 0.5) / n * 2 * math.pi
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(0.5 + 0.5 * math.sin(a), 0.5 - 0.5 * math.cos(a))
		d.Size = UDim2.fromOffset(6, 6)
		d.BackgroundColor3 = color or V.BRASS
		d.BackgroundTransparency = 1
		d.BorderSizePixel = 0
		d.ZIndex = f.ZIndex
		Estilo.corner(d, 3)
		d.Parent = f
		dots[i] = d
	end
	local lit = -1
	return {
		frame = f,
		set = function(frac: number)
			local k = ToqueTelas.ringLit(frac, n)
			if k == lit then
				return
			end
			lit = k
			for i, d in dots do
				d.BackgroundTransparency = if i <= k then 0 else 1
			end
		end,
	}
end

export type Round = { button: TextButton, glyph: TextLabel, label: TextLabel, ring: Ring }

-- Botão redondo (lado em px), glifo grande no meio e um rótulo curto embaixo (fora do círculo).
function ToqueUi.roundButton(parent: Instance, name: string, size: number, glyph: string): Round
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = V.PANEL
	b.BackgroundTransparency = 0.25
	b.BorderSizePixel = 0
	b.Selectable = false
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	Estilo.stroke(b, V.KHAKI, 2, 0.25)
	local g = Estilo.text(b, glyph, math.floor(size * 0.42), V.TEXT, F.TITLE)
	g.Name = "Glifo"
	g.Size = UDim2.fromScale(1, 1)
	g.TextXAlignment = Enum.TextXAlignment.Center
	g.ZIndex = b.ZIndex + 1
	local l = Estilo.text(b, "", math.max(12, math.floor(size * 0.2)), V.TEXT, F.TITLE_MED)
	l.Name = "Rotulo"
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 1, 4)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, math.max(16, math.floor(size * 0.28)))
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.BackgroundColor3 = V.PANEL
	l.BackgroundTransparency = 0.2
	l.TextStrokeColor3 = V.BG
	l.TextStrokeTransparency = 0.4
	Estilo.corner(l, 3)
	Estilo.pad(l, 6)
	local r = ToqueUi.ring(b, 20)
	return { button = b, glyph = g, label = l, ring = r }
end

-- Botão retangular de polegar (barras de confirmar/cancelar): altura mínima de toque, texto curto.
function ToqueUi.bigButton(parent: Instance, text: string, kind: string?, w: number?): TextButton
	local h = ToqueUi.minPx()
	local k = kind or "secondary"
	local b = Instance.new("TextButton")
	b.Name = "BotaoToque"
	b.AutoButtonColor = true
	b.Size = UDim2.fromOffset(w or math.floor(h * 2.4), h)
	b.BackgroundColor3 = if k == "primary" then V.OLIVE elseif k == "danger" then V.RED else V.PANEL
	b.BackgroundTransparency = if k == "secondary" then 0.15 else 0
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = V.TEXT
	b.FontFace = Estilo.headFont(text, F.TITLE_MED)
	b.TextSize = math.floor(h * 0.4)
	b.TextWrapped = false
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Selectable = false
	Estilo.corner(b, 4)
	Estilo.stroke(b, if k == "secondary" then V.LINE else V.TEXT, 1, if k == "secondary" then 0.1 else 0.8)
	b.Parent = parent
	return b
end

return ToqueUi
