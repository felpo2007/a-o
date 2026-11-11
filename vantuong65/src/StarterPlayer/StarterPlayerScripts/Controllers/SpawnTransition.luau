--!strict
-- Inserção sem entrar travado (pedido do dono, 2026-11-11). Ao escolher o ponto de spawn:
--   1. a tela escurece numa "ordem de inserção" de 1965 (texto datilografado, carta com o ponto
--      pulsando, grão de filme e barra de progresso) e os controles ficam parados (Input.openMenu);
--   2. o cliente pede o streaming da área do ponto (RequestStreamAroundAsync) e só DEPOIS pede o
--      spawn ao servidor (o servidor valida tudo de novo);
--   3. espera o corpo novo chegar no ponto, segura o HumanoidRootPart parado (só no cliente, dono da
--      física do próprio corpo), pede o streaming em volta dele e confere que há chão embaixo;
--   4. solta o corpo, carimba "EM CAMPO" e clareia; só então devolve o controle.
-- Se o servidor recusar (o corpo não chega), a ordem é cancelada e o lobby volta.
-- Tempos-limite são de segurança: nunca deixam o jogador preso aqui.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local SpawnTransition = {}
local player = Players.LocalPlayer

export type Point = { id: string, name: string, x: number, z: number }

local HEAD, TYPE = Enum.Font.Oswald, Enum.Font.SpecialElite
local INK, CARD, KHAKI, STAMP, DRAB = UiKit.INK, UiKit.CARD, UiKit.KHAKI, UiKit.STAMP, UiKit.DRAB
local B = MapConfig.Bounds

local STREAM_POINT_S = 8 -- s máximos esperando a área do ponto
local BODY_S = 8 -- s esperando o corpo novo
local PLACE_S = 3 -- s esperando o corpo ir para o ponto
local GROUND_S = 4 -- s esperando o chão embaixo

-- ===== desenho =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Insertion"
gui.ResetOnSpawn = false
gui.DisplayOrder = 90 -- acima do lobby e dos menus, abaixo do aviso de controle desconectado
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)

local bg = Instance.new("Frame")
bg.Name = "Fundo"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = UiKit.NIGHT
bg.BackgroundTransparency = 1
bg.BorderSizePixel = 0
bg.Active = true -- nada atrás recebe clique durante a inserção
bg.Parent = gui

-- grão e riscos de filme (poucos quadros reposicionados a cada 1/16 s)
local grain: { Frame } = {}
for i = 1, 40 do
	local g = Instance.new("Frame")
	g.BorderSizePixel = 0
	g.BackgroundColor3 = if i % 3 == 0 then Color3.new(0, 0, 0) else Color3.fromRGB(230, 220, 190)
	g.BackgroundTransparency = 0.55
	g.Size = UDim2.fromOffset(2 + i % 3, 2 + i % 2)
	g.ZIndex = 4
	g.Parent = bg
	table.insert(grain, g)
end
local scratches: { Frame } = {}
for _ = 1, 2 do
	local s = Instance.new("Frame")
	s.BorderSizePixel = 0
	s.BackgroundColor3 = Color3.fromRGB(230, 220, 190)
	s.BackgroundTransparency = 0.8
	s.Size = UDim2.new(0, 1, 1, 0)
	s.ZIndex = 4
	s.Parent = bg
	table.insert(scratches, s)
end

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.5)
holder.Size = UDim2.fromOffset(820, 360)
holder.BackgroundTransparency = 1
holder.Parent = bg
local fit = Instance.new("UIScale")
fit.Parent = holder

local card = Instance.new("Frame")
card.Size = UDim2.fromOffset(540, 300)
card.BackgroundColor3 = CARD
card.BorderSizePixel = 0
card.Parent = holder
local cg = Instance.new("UIGradient")
cg.Rotation = 80
cg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(212, 206, 192))
cg.Parent = card

local function label(
	parent: Instance,
	font: Enum.Font,
	size: number,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextSize = UiKit.text(size)
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.TextWrapped = true
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Parent = parent
	return t
end

local head = label(card, HEAD, 26, INK, 20, 12, 500, 34)
head.Text = "ORDEM DE INSERÇÃO"
local rule = Instance.new("Frame")
rule.BackgroundColor3 = UiKit.RULE_RED
rule.BorderSizePixel = 0
rule.Position = UDim2.fromOffset(20, 50)
rule.Size = UDim2.fromOffset(500, 2)
rule.Parent = card
local body = label(card, TYPE, 18, INK, 20, 62, 500, 150)
local stageText = label(card, TYPE, 15, INK, 20, 226, 500, 22)
local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(20, 254)
barBack.Size = UDim2.fromOffset(500, 14)
barBack.BackgroundColor3 = DRAB
barBack.BorderSizePixel = 0
barBack.Parent = card
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = STAMP
barFill.BorderSizePixel = 0
barFill.Parent = barBack
-- marcas de régua na barra (cara de contador de filme)
for i = 1, 9 do
	local m = Instance.new("Frame")
	m.BackgroundColor3 = KHAKI
	m.BackgroundTransparency = 0.5
	m.BorderSizePixel = 0
	m.Position = UDim2.new(i / 10, 0, 0, 0)
	m.Size = UDim2.new(0, 1, 1, 0)
	m.ZIndex = 2
	m.Parent = barBack
end
local done = label(card, HEAD, 34, STAMP, 300, 150, 220, 52)
done.TextXAlignment = Enum.TextXAlignment.Center
done.TextYAlignment = Enum.TextYAlignment.Center
done.Text = "EM CAMPO"
done.Rotation = -8
done.Visible = false
local ds = Instance.new("UIStroke")
ds.Color = STAMP
ds.Thickness = 3
ds.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
ds.Parent = done

-- carta com o ponto (grade que se desenha sozinha)
local map = Instance.new("Frame")
map.Position = UDim2.fromOffset(560, 20)
map.Size = UDim2.fromOffset(260, 260)
map.BackgroundColor3 = Color3.fromRGB(214, 214, 182)
map.BorderSizePixel = 0
map.ClipsDescendants = true
map.Parent = holder
local ms = Instance.new("UIStroke")
ms.Color = INK
ms.Thickness = 2
ms.Parent = map
local gridLines: { { f: Frame, full: UDim2 } } = {}
for i = 1, 7 do
	local v = Instance.new("Frame")
	v.BackgroundColor3 = Color3.fromRGB(70, 96, 140)
	v.BackgroundTransparency = 0.4
	v.BorderSizePixel = 0
	v.Position = UDim2.fromScale(i / 8, 0)
	v.Parent = map
	table.insert(gridLines, { f = v, full = UDim2.new(0, 1, 1, 0) })
	local h = Instance.new("Frame")
	h.BackgroundColor3 = Color3.fromRGB(70, 96, 140)
	h.BackgroundTransparency = 0.4
	h.BorderSizePixel = 0
	h.Position = UDim2.fromScale(0, i / 8)
	h.Parent = map
	table.insert(gridLines, { f = h, full = UDim2.new(1, 0, 0, 1) })
end
local marker = Instance.new("Frame")
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Size = UDim2.fromOffset(18, 18)
marker.BackgroundTransparency = 1
marker.ZIndex = 3
marker.Parent = map
local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(1, 0)
mc.Parent = marker
local mstroke = Instance.new("UIStroke")
mstroke.Color = STAMP
mstroke.Thickness = 3
mstroke.Parent = marker
local mdot = Instance.new("Frame")
mdot.AnchorPoint = Vector2.new(0.5, 0.5)
mdot.Position = UDim2.fromScale(0.5, 0.5)
mdot.Size = UDim2.fromOffset(6, 6)
mdot.BackgroundColor3 = STAMP
mdot.BorderSizePixel = 0
mdot.ZIndex = 3
mdot.Parent = marker
local mdc = Instance.new("UICorner")
mdc.CornerRadius = UDim.new(1, 0)
mdc.Parent = mdot
local mapName = label(map, TYPE, 14, INK, 6, 236, 248, 20)

task.spawn(function()
	gui.Parent = player:WaitForChild("PlayerGui")
end)

-- ===== estado =====
local busy = false
local progress, shown = 0, 0
local animT = 0
local nextGrain = 0

local function gridRef(x: number, z: number): string
	local g = MapConfig.GridOrigin1965
	local e = g.e + x * MapConfig.STUD_M
	local n = g.n - z * MapConfig.STUD_M
	return string.format("BS %03d%03d", math.floor((e % 100000) / 100), math.floor((n % 100000) / 100))
end

local function clock(): string
	local c = Lighting.ClockTime
	return string.format("%02d%02d", math.floor(c) % 24, math.floor((c % 1) * 60))
end

-- quadro a quadro só com a ordem na tela: barra suave, marcador pulsando, grão
RunService.RenderStepped:Connect(function(dt: number)
	if not gui.Enabled then
		return
	end
	animT += dt
	shown += (progress - shown) * math.min(1, dt * 6)
	barFill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	local s = 18 + 10 * (0.5 + 0.5 * math.sin(animT * 6))
	marker.Size = UDim2.fromOffset(s, s)
	if animT >= nextGrain then
		nextGrain = animT + 1 / 16
		for _, g in grain do
			g.Position = UDim2.fromScale(math.random(), math.random())
		end
		for _, sc in scratches do
			sc.Position = UDim2.fromScale(math.random(), 0)
			sc.Visible = math.random() < 0.5
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		fit.Scale = math.clamp(cam.ViewportSize.Y / 720, 0.7, 1.6)
	end
end)

local function setStage(text: string, p: number)
	stageText.Text = text
	progress = math.max(progress, p)
end

-- texto datilografado (MaxVisibleGraphemes sobe com o tempo)
local function typeText(t: TextLabel, s: string, seconds: number)
	t.Text = s
	t.MaxVisibleGraphemes = 0
	local n = utf8.len(s) or #s
	TweenService:Create(t, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = n }):Play()
end

local function show(pt: Point)
	local u = math.clamp((pt.x - B.minX) / (B.maxX - B.minX), 0, 1)
	local v = math.clamp((pt.z - B.minZ) / (B.maxZ - B.minZ), 0, 1)
	marker.Position = UDim2.fromScale(u, v)
	mapName.Text = pt.name
	progress, shown = 0, 0
	done.Visible = false
	gui.Enabled = true
	bg.BackgroundTransparency = 1
	holder.Position = UDim2.new(0.5, 0, 0.5, 24)
	TweenService:Create(bg, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(holder, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.5),
	}):Play()
	for i, gl in gridLines do
		gl.f.Size = if gl.full.X.Scale > 0 then UDim2.new(0, 0, 0, 1) else UDim2.new(0, 1, 0, 0)
		TweenService
			:Create(gl.f, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, i * 0.03), {
				Size = gl.full,
			})
			:Play()
	end
	typeText(
		body,
		string.format(
			"PONTO: %s\nGRADE: %s\nHORA: %sH · 18 AGO 1965\nLado: %s",
			pt.name,
			gridRef(pt.x, pt.z),
			clock(),
			tostring(player:GetAttribute("Faction") or "?")
		),
		0.9
	)
end

local function hide(after: number)
	task.delay(after, function()
		TweenService:Create(bg, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(holder, TweenInfo.new(0.35), { Position = UDim2.new(0.5, 0, 0.5, -24) }):Play()
		task.delay(0.46, function()
			if not busy then
				gui.Enabled = false
			end
		end)
	end)
end

-- ===== etapas =====
local function streamAround(pos: Vector3, timeout: number)
	pcall(function()
		player:RequestStreamAroundAsync(pos, timeout)
	end)
end

local function newBody(old: Model?, timeout: number): (Model?, BasePart?)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local c = player.Character
		if c and c ~= old then
			local hum = c:FindFirstChildOfClass("Humanoid")
			local root = c:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") then
				return c, root
			end
		end
		task.wait(0.1)
	end
	return nil, nil
end

local function groundUnder(root: BasePart, char: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	return workspace:Raycast(root.Position, Vector3.new(0, -60, 0), params) ~= nil
end

function SpawnTransition.busy(): boolean
	return busy
end

-- Começa a inserção no ponto; `fire` pede o spawn ao servidor. Devolve false se já há uma em curso.
function SpawnTransition.go(pt: Point, fire: () -> ()): boolean
	if busy then
		return false
	end
	busy = true
	Input.openMenu() -- personagem parado até a área chegar
	show(pt)
	task.spawn(function()
		local old = player.Character
		-- 1. área do ponto (o chão ainda nem existe no cliente)
		setStage("Recebendo a área de inserção…", 0.08)
		task.spawn(function()
			-- a barra anda enquanto o streaming responde (sem número inventado: o fim vem do Roblox)
			local t0 = os.clock()
			while busy and progress < 0.55 and os.clock() - t0 < STREAM_POINT_S do
				progress = math.max(progress, 0.08 + 0.45 * (1 - math.exp(-(os.clock() - t0))))
				task.wait(0.1)
			end
		end)
		streamAround(Vector3.new(pt.x, 30, pt.z), STREAM_POINT_S)
		setStage("Área recebida. Pedindo a inserção ao comando…", 0.6)
		-- 2. pede o spawn e espera o corpo novo
		fire()
		local char, root = newBody(old, BODY_S)
		if not (char and root) then
			setStage("Inserção recusada pelo comando (o ponto mudou?). Escolha outro.", 0.6)
			busy = false
			hide(1.6)
			Input.closeMenu()
			return
		end
		-- 3. o servidor leva o corpo ao ponto; segura-o parado enquanto o chão chega
		setStage("Desembarcando…", 0.72)
		local t0 = os.clock()
		while os.clock() - t0 < PLACE_S do
			local d = Vector2.new(root.Position.X - pt.x, root.Position.Z - pt.z).Magnitude
			if d < 80 then
				break
			end
			task.wait(0.05)
		end
		local held = false
		if root.Parent and not root.Anchored then
			root.Anchored = true
			held = true
		end
		setStage("Firmando o terreno sob os pés…", 0.82)
		streamAround(root.Position, GROUND_S)
		t0 = os.clock()
		while os.clock() - t0 < GROUND_S and root.Parent and not groundUnder(root, char) do
			task.wait(0.1)
		end
		if held and root.Parent then
			root.Anchored = false
		end
		-- 4. pronto
		setStage("Em posição.", 1)
		done.Visible = true
		done.TextTransparency = 1
		TweenService:Create(done, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
		busy = false
		hide(0.55)
		task.delay(0.6, function()
			Input.closeMenu()
		end)
	end)
	return true
end

return SpawnTransition
