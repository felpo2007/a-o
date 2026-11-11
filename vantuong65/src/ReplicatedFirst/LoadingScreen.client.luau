--!strict
-- Tela de carregamento de entrada (pedido do dono, 2026-11-11: "telas de carregamento animadas de
-- qualidade", "a pessoa não entrar toda travada"). Identidade de 1965, própria do jogo:
--   - fundo de filme granulado (grão, riscos e tremor de luz), com a contagem de "pontilha" de
--     filme (círculo com ponteiro girando) no canto;
--   - uma carta topográfica sendo traçada: grade, curvas de nível e o lápis vermelho do eixo de
--     desembarque;
--   - o título datilografado e a lista do que está carregando de verdade.
-- Progresso REAL, por etapas: jogo recebido, remotes do servidor, fontes e sons
-- (ContentProvider:PreloadAsync), manequins e modelos da mesa do lobby (PreloadAsync do que o
-- PreviewService publicou) e o terreno (atributo TerrainReady). A porcentagem só conta etapas
-- concluídas; o terreno não tem número (o servidor só avisa quando acaba), então a barra pulsa.
-- "ENTRAR" (clique, toque, Enter/Espaço ou A) aparece quando o essencial (jogo, remotes, fontes)
-- está pronto; com tudo pronto, a tela some sozinha.
-- Não depende dos módulos de Controllers: pode ir para o ReplicatedFirst sem mudar nada (lá ela
-- apareceria desde o primeiro quadro; aqui, logo depois da tela padrão do Roblox).
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local NIGHT = Color3.fromRGB(20, 22, 16)
local KHAKI = Color3.fromRGB(201, 186, 140)
local CARD = Color3.fromRGB(234, 226, 200)
local INK = Color3.fromRGB(40, 36, 28)
local STAMP = Color3.fromRGB(150, 40, 30)
local DRAB = Color3.fromRGB(46, 50, 36)
local GRID = Color3.fromRGB(70, 96, 140)
local HEAD, TYPE, VIET = Enum.Font.Oswald, Enum.Font.SpecialElite, Enum.Font.Arimo

local function tv(): boolean
	local ok, v = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and v == true
end
local function ts(size: number): number
	return if tv() then math.max(size, 24) else size
end

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

-- ===== desenho =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Loading"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = NIGHT
bg.BorderSizePixel = 0
bg.Active = true -- o lobby atrás não recebe clique
bg.Parent = gui

local flickerFrame = Instance.new("Frame") -- tremor da luz do projetor
flickerFrame.Size = UDim2.fromScale(1, 1)
flickerFrame.BackgroundColor3 = Color3.new(0, 0, 0)
flickerFrame.BackgroundTransparency = 0.95
flickerFrame.BorderSizePixel = 0
flickerFrame.ZIndex = 8
flickerFrame.Parent = bg

local grain: { Frame } = {}
for i = 1, 56 do
	local g = Instance.new("Frame")
	g.BorderSizePixel = 0
	g.BackgroundColor3 = if i % 3 == 0 then Color3.new(0, 0, 0) else Color3.fromRGB(230, 220, 190)
	g.BackgroundTransparency = 0.5
	g.Size = UDim2.fromOffset(2 + i % 3, 2 + i % 2)
	g.ZIndex = 9
	g.Parent = bg
	table.insert(grain, g)
end
local scratches: { Frame } = {}
for _ = 1, 3 do
	local s = Instance.new("Frame")
	s.BorderSizePixel = 0
	s.BackgroundColor3 = Color3.fromRGB(230, 220, 190)
	s.BackgroundTransparency = 0.82
	s.Size = UDim2.new(0, 1, 1, 0)
	s.ZIndex = 9
	s.Parent = bg
	table.insert(scratches, s)
end

-- palco de 1280 x 720 que escala com a tela
local stage = Instance.new("Frame")
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(1280, 720)
stage.BackgroundTransparency = 1
stage.Parent = bg
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage

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
	t.TextSize = ts(size)
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.TextWrapped = true
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Parent = parent
	return t
end

local title = label(stage, HEAD, 76, CARD, 90, 150, 640, 96)
title.Text = "VẠN TƯỜNG '65"
local sub = label(stage, VIET, 20, KHAKI, 94, 248, 620, 28)
sub.Text = "OPERAÇÃO STARLITE · QUẢNG NGÃI · 18 DE AGOSTO DE 1965"
local motto = label(stage, TYPE, 18, KHAKI, 94, 286, 600, 56)
local rule = Instance.new("Frame")
rule.BackgroundColor3 = STAMP
rule.BorderSizePixel = 0
rule.Position = UDim2.fromOffset(94, 240)
rule.Size = UDim2.fromOffset(0, 3)
rule.Parent = stage

-- a carta sendo traçada
local map = Instance.new("Frame")
map.Position = UDim2.fromOffset(820, 120)
map.Size = UDim2.fromOffset(360, 360)
map.BackgroundColor3 = Color3.fromRGB(218, 214, 182)
map.BorderSizePixel = 0
map.ClipsDescendants = true
map.Rotation = 2
map.Parent = stage
local mapStroke = Instance.new("UIStroke")
mapStroke.Color = INK
mapStroke.Thickness = 2
mapStroke.Parent = map
type Draw = { f: Frame, full: UDim2, delay: number }
local draws: { Draw } = {}
for i = 1, 8 do
	local v = Instance.new("Frame")
	v.BackgroundColor3 = GRID
	v.BackgroundTransparency = 0.45
	v.BorderSizePixel = 0
	v.Position = UDim2.fromScale(i / 9, 0)
	v.Size = UDim2.new(0, 1, 0, 0)
	v.Parent = map
	table.insert(draws, { f = v, full = UDim2.new(0, 1, 1, 0), delay = i * 0.05 })
	local h = Instance.new("Frame")
	h.BackgroundColor3 = GRID
	h.BackgroundTransparency = 0.45
	h.BorderSizePixel = 0
	h.Position = UDim2.fromScale(0, i / 9)
	h.Size = UDim2.new(0, 0, 0, 1)
	h.Parent = map
	table.insert(draws, { f = h, full = UDim2.new(1, 0, 0, 1), delay = i * 0.05 + 0.02 })
end
-- curvas de nível de duas colinas (anéis que crescem do cume para fora)
local hills = { { 0.3, 0.32, 5 }, { 0.72, 0.7, 4 } }
for hIdx, hill in hills do
	for k = 1, hill[3] do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(hill[1], hill[2])
		ring.Size = UDim2.fromScale(0, 0)
		ring.BackgroundTransparency = 1
		ring.Parent = map
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = ring
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(150, 104, 60)
		s.Thickness = if k == 1 then 2 else 1
		s.Transparency = 0.15
		s.Parent = ring
		local r = 0.06 + k * 0.055
		table.insert(draws, {
			f = ring,
			full = UDim2.fromScale(r * (1.3 - 0.05 * k), r),
			delay = 0.5 + hIdx * 0.3 + k * 0.12,
		})
	end
end
local hillName = label(map, TYPE, 14, INK, 70, 92, 120, 20)
hillName.Text = "43"
local hill2 = label(map, TYPE, 14, INK, 240, 238, 120, 20)
hill2.Text = "30"
-- lápis vermelho: eixo do desembarque, da praia (leste) para o interior
local pencil = Instance.new("Frame")
pencil.AnchorPoint = Vector2.new(1, 0.5)
pencil.Position = UDim2.fromScale(0.95, 0.55)
pencil.Size = UDim2.new(0, 0, 0, 4)
pencil.Rotation = 8
pencil.BackgroundColor3 = STAMP
pencil.BorderSizePixel = 0
pencil.Parent = map
local mapLabel = label(map, TYPE, 14, INK, 10, 334, 340, 20)
mapLabel.Text = "CARTA 1:50.000 · VẠN TƯỜNG"
mapLabel.Font = VIET

-- contagem de pontilha de filme (círculo com ponteiro)
local leader = Instance.new("Frame")
leader.Position = UDim2.fromOffset(90, 470)
leader.Size = UDim2.fromOffset(92, 92)
leader.BackgroundColor3 = Color3.fromRGB(56, 58, 46)
leader.BorderSizePixel = 0
leader.Parent = stage
local lc = Instance.new("UICorner")
lc.CornerRadius = UDim.new(1, 0)
lc.Parent = leader
local ls = Instance.new("UIStroke")
ls.Color = KHAKI
ls.Thickness = 2
ls.Parent = leader
local sweep = Instance.new("Frame")
sweep.AnchorPoint = Vector2.new(0.5, 1)
sweep.Position = UDim2.fromScale(0.5, 0.5)
sweep.Size = UDim2.new(0, 2, 0.5, 0)
sweep.BackgroundColor3 = KHAKI
sweep.BorderSizePixel = 0
sweep.Parent = leader
local digit = label(leader, HEAD, 44, CARD, 0, 0, 92, 92)
digit.TextXAlignment = Enum.TextXAlignment.Center
digit.TextYAlignment = Enum.TextYAlignment.Center
digit.ZIndex = 2

-- progresso
local stepText = label(stage, TYPE, 18, KHAKI, 206, 474, 900, 26)
local list = label(stage, TYPE, 15, KHAKI, 206, 504, 900, 60)
list.TextTransparency = 0.25
local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(206, 574)
barBack.Size = UDim2.fromOffset(974, 12)
barBack.BackgroundColor3 = DRAB
barBack.BorderSizePixel = 0
barBack.Parent = stage
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = STAMP
barFill.BorderSizePixel = 0
barFill.Parent = barBack
local pulse = Instance.new("Frame") -- trecho que corre na etapa sem número (terreno)
pulse.Size = UDim2.fromScale(0.08, 1)
pulse.BackgroundColor3 = KHAKI
pulse.BackgroundTransparency = 0.4
pulse.BorderSizePixel = 0
pulse.Visible = false
pulse.Parent = barBack
local percent = label(stage, HEAD, 20, CARD, 1080, 540, 100, 28)
percent.TextXAlignment = Enum.TextXAlignment.Right

local enter = Instance.new("TextButton")
enter.Position = UDim2.fromOffset(880, 610)
enter.Size = UDim2.fromOffset(300, 52)
enter.BackgroundColor3 = STAMP
enter.TextColor3 = CARD
enter.Font = HEAD
enter.TextSize = ts(24)
enter.Text = "ENTRAR NO LOBBY ►"
enter.AutoButtonColor = true
enter.Visible = false
enter.Parent = stage
local enterHint = label(stage, TYPE, 14, KHAKI, 206, 620, 660, 40)

gui.Parent = player:WaitForChild("PlayerGui")

-- ===== animação (só enquanto a tela existe) =====
local t = 0
local nextGrain = 0
local shown, target = 0, 0
local indeterminate = false
local leaderN = 3
local closing = false

local conn = RunService.RenderStepped:Connect(function(dt: number)
	t += dt
	local cam = workspace.CurrentCamera
	if cam then
		local vp = cam.ViewportSize
		stageScale.Scale = math.max(math.min(vp.X / 1280, vp.Y / 720), 0.45)
	end
	shown += (target - shown) * math.min(1, dt * 5)
	barFill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	pulse.Visible = indeterminate
	if indeterminate then
		pulse.Position = UDim2.fromScale(shown + ((t * 0.35) % 1) * math.max(1 - shown - 0.08, 0), 0)
	end
	sweep.Rotation = (t * 360) % 360
	local n = 3 - math.floor(t) % 3
	if n ~= leaderN then
		leaderN = n
		digit.Text = tostring(n)
	end
	if t >= nextGrain then
		nextGrain = t + 1 / 18
		for _, g in grain do
			g.Position = UDim2.fromScale(math.random(), math.random())
		end
		for _, s in scratches do
			s.Position = UDim2.fromScale(math.random(), 0)
			s.Visible = math.random() < 0.45
		end
		flickerFrame.BackgroundTransparency = 0.9 + math.random() * 0.08
	end
end)

-- carta: grade, curvas e lápis se desenham; título e lema datilografados
local function drawMap()
	for _, d in draws do
		TweenService:Create(
			d.f,
			TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, d.delay),
			{ Size = d.full }
		):Play()
	end
	TweenService:Create(pencil, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, 1.4), {
		Size = UDim2.new(0.62, 0, 0, 4),
	}):Play()
end
local function typeText(l: TextLabel, s: string, seconds: number, delay: number)
	l.Text = s
	l.MaxVisibleGraphemes = 0
	TweenService:Create(
		l,
		TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay),
		{ MaxVisibleGraphemes = utf8.len(s) or #s }
	):Play()
end
drawMap()
typeText(title, "VẠN TƯỜNG '65", 0.7, 0.1)
typeText(sub, sub.Text, 1.1, 0.8)
typeText(motto, "Ordem de deslocamento: a mesa de campanha está sendo arrumada.", 1.4, 1.8)
TweenService:Create(rule, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.6), {
	Size = UDim2.fromOffset(560, 3),
}):Play()

-- ===== etapas reais =====
type Step = { name: string, weight: number, done: boolean }
local steps: { Step } = {
	{ name = "Jogo recebido", weight = 0.1, done = false },
	{ name = "Ordens do servidor (remotes)", weight = 0.1, done = false },
	{ name = "Fontes, papéis e sons", weight = 0.2, done = false },
	{ name = "Soldados e objetos da mesa", weight = 0.3, done = false },
	{ name = "Terreno de Vạn Tường", weight = 0.3, done = false },
}
local essentialReady = false

local function refreshList()
	local lines = {}
	local sum = 0
	for _, s in steps do
		table.insert(lines, (if s.done then "■ " else "□ ") .. s.name)
		if s.done then
			sum += s.weight
		end
	end
	list.Text = table.concat(lines, "   ")
	target = math.max(target, sum)
	percent.Text = string.format("%d%%", math.floor(sum * 100 + 0.5))
end

local function finish(i: number)
	steps[i].done = true
	refreshList()
end

local function close()
	if closing then
		return
	end
	closing = true
	enter.Visible = false
	TweenService:Create(bg, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	for _, d in bg:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
		if d:IsA("GuiObject") and d.BackgroundTransparency < 1 then
			TweenService:Create(d, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		end
		if d:IsA("UIStroke") then
			TweenService:Create(d, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
	end
	task.delay(0.65, function()
		conn:Disconnect()
		gui:Destroy()
	end)
end

enter.Activated:Connect(function()
	if essentialReady then
		close()
	end
end)
UserInputService.InputBegan:Connect(function(input: InputObject)
	if not essentialReady or closing then
		return
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.Return or kc == Enum.KeyCode.Space or kc == Enum.KeyCode.ButtonA then
		close()
	end
end)

refreshList()
task.spawn(function()
	-- 1. jogo
	stepText.Text = "Recebendo o jogo…"
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	finish(1)
	-- 2. remotes
	stepText.Text = "Recebendo as ordens do servidor…"
	ReplicatedStorage:WaitForChild("VT65Remotes", 60)
	finish(2)
	-- 3. fontes e sons
	stepText.Text = "Carregando fontes, papéis e sons…"
	local assets: { Instance } = {}
	for _, font in { HEAD, TYPE, VIET, Enum.Font.Arimo, Enum.Font.GothamMedium } do
		local l = Instance.new("TextLabel")
		l.Font = font
		l.Text = "VẠN TƯỜNG 1965"
		table.insert(assets, l)
	end
	local shared = ReplicatedStorage:WaitForChild("Shared", 30)
	local idsModule = shared and shared:FindFirstChild("AssetIds")
	if idsModule and idsModule:IsA("ModuleScript") then
		local ok, ids = pcall(require, idsModule)
		if ok and type(ids) == "table" and type((ids :: any).Sounds) == "table" then
			for _, key in { "radio_squelch", "ambience_paddy_morning", "ambience_tunnel", "ambience_village" } do
				local id = (ids :: any).Sounds[key]
				if type(id) == "number" and id ~= 0 then
					local snd = Instance.new("Sound")
					snd.SoundId = "rbxassetid://" .. id
					table.insert(assets, snd)
				end
			end
		end
	end
	local base = target
	local count = 0
	pcall(function()
		ContentProvider:PreloadAsync(assets, function()
			count += 1
			target = math.max(target, base + steps[3].weight * count / math.max(#assets, 1) * 0.95)
		end)
	end)
	finish(3)
	essentialReady = true
	enter.Visible = true
	enter.Position = UDim2.fromOffset(880, 640)
	TweenService:Create(enter, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(880, 610),
	}):Play()
	enterHint.Text = "Já dá para entrar (clique, toque, Enter ou A). O resto termina no lobby; o spawn só "
		.. "libera com o terreno pronto."
	-- 4. manequins e modelos da mesa (o PreviewService marca Ready quando termina)
	stepText.Text = "Montando os soldados e os objetos da mesa…"
	local preview = ReplicatedStorage:WaitForChild("VT65Preview", 60)
	if preview then
		local t0 = os.clock()
		while preview:GetAttribute("Ready") ~= true and os.clock() - t0 < 45 do
			task.wait(0.25)
		end
		local list2: { Instance } = { preview }
		local art = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
		if art then
			table.insert(list2, art)
		end
		local base4 = target
		local n4 = 0
		pcall(function()
			ContentProvider:PreloadAsync(list2, function()
				n4 += 1
				-- quantos assets há não se sabe antes: a barra anda e nunca passa da etapa
				target = math.max(target, base4 + steps[4].weight * (1 - 1 / (1 + n4 * 0.15)))
			end)
		end)
	end
	finish(4)
	-- 5. terreno (sem número: o servidor só avisa quando acaba)
	if ReplicatedStorage:GetAttribute("TerrainReady") ~= true then
		stepText.Text = "O servidor está gerando o terreno de 4 × 2,4 km…"
		indeterminate = true
		while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
			ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
		end
		indeterminate = false
	end
	finish(5)
	stepText.Text = "Pronto. A mesa de campanha espera por você."
	task.wait(0.8)
	close()
end)
