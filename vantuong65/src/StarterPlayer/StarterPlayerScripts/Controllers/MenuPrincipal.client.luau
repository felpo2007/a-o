--!strict
-- Menu principal (lote 5, D-117; pedido do dono: "faça uma tela de menu animada bonita, que vai ter
-- atrás o fundo do mapa bonito e o soldado, e vai ter as opções jogar, configurações, loja, passe e
-- tutorial. Não quero mais o tutorial dentro do jogo"; "uma criança tem que conseguir jogar").
-- Abre quando a tela de carregamento termina (atributo "Pronto" na VT65Loading) e fica até o JOGAR:
--   - fundo: o mapa de verdade. A câmera dá a volta devagar em Xóm Gò, no morro do centro (uma volta
--     em ORBIT_S), com cor quente e um desfoque leve ao longe; à esquerda, uma vinheta escura para o
--     texto ler bem;
--   - à direita, o soldado (SoldierPreview.newStill, o manequim que o servidor vestiu): o do lado do
--     jogador ou, antes de escolher, os dois lados se revezando; respira devagar;
--   - à esquerda, o título e os cinco botões: JOGAR (Jogar agora: lado, squad, papel e ponto
--     automáticos, Controllers/JogarAgora), CONFIGURAÇÕES (menu do jogo, aba Configurações), LOJA,
--     PASSE e TUTORIAL (Controllers/ComoJogar, aqui mesmo, sem entrar na partida).
-- Enquanto aberto, o atributo do jogador "MenuPrincipal" fica true: o GameUI esconde o lobby (a mesa)
-- e a câmera é daqui. Fecha só no JOGAR (a mesa continua no menu do jogo e na tela de baixa).
-- Controle: ↑ ↓ andam, A escolhe; teclado: setas e Enter; toque e mouse: tocar ou clicar.
-- Studio: workspace:SetAttribute("VT65DevTela", "menu_principal") abre de novo.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Bus = require(script.Parent.Bus)
local ComoJogar = require(script.Parent.ComoJogar)
local Input = require(script.Parent.Input)
local SoldierPreview = require(script.Parent.SoldierPreview)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local M = MapConfig.STUD_M

-- ===== câmera: a volta em Xóm Gò (PLACEHOLDER de direção) =====
local ORBIT_S = 240 -- s por volta
local ORBIT_R_M = 120 -- raio da volta
local ORBIT_UP_M = 40 -- altura da câmera sobre o chão do centro
local LOOK_UP_M = 3 -- a câmera olha um pouco acima do chão do centro
local FOV = 55
local SOLDIER_SWAP_S = 9 -- antes de escolher o lado: troca o soldado a cada isto

local function centerXZ(): (number, number)
	for _, sp in MapConfig.Strongpoints do
		if sp.name == "Xóm Gò" then
			return sp.x, sp.z
		end
	end
	local b = MapConfig.Bounds
	return (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2
end
local CX, CZ = centerXZ()

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
local groundY: number? = nil
local function centerY(): number
	local y = groundY
	if y then
		return y
	end
	terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(CX, 2000, CZ), Vector3.new(0, -4000, 0), terrainOnly)
	if hit then
		groundY = hit.Position.Y
		return hit.Position.Y
	end
	return 35 / M -- o terreno ainda não chegou: a altura do morro
end

-- ===== tela =====
local gui = UiKit.screen("VT65MenuPrincipal", 28) -- acima do lobby (18 a 22), abaixo da loja (30)
gui.IgnoreGuiInset = true
gui.Enabled = false

-- vinheta: escura à esquerda (texto) e embaixo, aberta no meio e à direita (mapa e soldado)
local shade = Instance.new("Frame")
shade.Name = "Vinheta"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = V.BG
shade.BorderSizePixel = 0
shade.Parent = gui
local shadeGrad = Instance.new("UIGradient")
shadeGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.36, 0.3),
	NumberSequenceKeypoint.new(0.62, 1),
	NumberSequenceKeypoint.new(1, 1),
})
shadeGrad.Parent = shade
local floor = Instance.new("Frame")
floor.Name = "Chao"
floor.AnchorPoint = Vector2.new(0, 1)
floor.Position = UDim2.fromScale(0, 1)
floor.Size = UDim2.fromScale(1, 0.35)
floor.BackgroundColor3 = V.BG
floor.BorderSizePixel = 0
floor.Parent = gui
local floorGrad = Instance.new("UIGradient")
floorGrad.Rotation = -90
floorGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.25),
	NumberSequenceKeypoint.new(1, 1),
})
floorGrad.Parent = floor

-- palco de 1280 x 720 que escala com a tela (como as outras telas)
local stage = Instance.new("Frame")
stage.Name = "Palco"
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(1280, 720)
stage.BackgroundTransparency = 1
stage.Parent = gui
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage
local function rescale()
	local cam = workspace.CurrentCamera
	if cam then
		local v = cam.ViewportSize
		stageScale.Scale = math.max(0.35, math.min(v.X / 1280, v.Y / 720))
	end
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

-- tudo o que entra e sai junto (título, botões, soldado)
local group = Instance.new("CanvasGroup")
group.Name = "Conteudo"
group.Size = UDim2.fromScale(1, 1)
group.BackgroundTransparency = 1
group.Parent = stage

local function text(parent: Instance, font: Font, size: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

-- ----- título -----
local titleBox = Instance.new("Frame")
titleBox.Name = "Titulo"
titleBox.BackgroundTransparency = 1
titleBox.Position = UDim2.fromOffset(84, 70)
titleBox.Size = UDim2.fromOffset(620, 200)
titleBox.Parent = group
local t1 = text(titleBox, F.TITLE, 108, V.TEXT)
t1.Size = UDim2.fromOffset(620, 110)
t1.Text = "STARLITE"
local t2 = text(titleBox, F.TITLE_MED, 46, V.KHAKI)
t2.Position = UDim2.fromOffset(4, 104)
t2.Size = UDim2.fromOffset(620, 52)
t2.Text = "VIETNÃ 1965"
local bar = Instance.new("Frame")
bar.BackgroundColor3 = V.RED
bar.BorderSizePixel = 0
bar.Position = UDim2.fromOffset(6, 162)
bar.Size = UDim2.fromOffset(120, 5)
bar.Parent = titleBox
local t3 = text(titleBox, F.BODY, 19, V.KHAKI)
t3.Position = UDim2.fromOffset(6, 174)
t3.Size = UDim2.fromOffset(620, 24)
t3.Text = "Operação Starlite · Vạn Tường · agosto de 1965"

-- ----- botões -----
type Btn = { b: TextButton, r: UiKit.Realce, x: number }
local buttons: { Btn } = {}
local BX, BY = 84, 276
local function makeButton(label: string, primary: boolean, y: number, h: number): Btn
	local b = Instance.new("TextButton")
	b.Name = label
	b.AutoButtonColor = false
	b.Text = ""
	b.Size = UDim2.fromOffset(if primary then 440 else 400, h)
	b.Position = UDim2.fromOffset(BX, y)
	b.BackgroundColor3 = if primary then V.RED else V.PANEL
	b.BackgroundTransparency = if primary then 0 else 0.12
	b.BorderSizePixel = 0
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = group
	UiKit.corner(b, 4)
	UiKit.edge(b, if primary then UiKit.BRASS else V.LINE, if primary then 2 else 1, if primary then 0.2 else 0.35)
	local accent = Instance.new("Frame")
	accent.Name = "Filete"
	accent.BorderSizePixel = 0
	accent.BackgroundColor3 = if primary then UiKit.BRASS else V.KHAKI
	accent.Size = UDim2.new(0, if primary then 8 else 5, 1, 0)
	accent.Parent = b
	local t = Instance.new("TextLabel")
	t.Name = "Texto"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(if primary then 34 else 28, 0)
	t.Size = UDim2.new(1, -60, 1, 0)
	t.FontFace = if primary then F.TITLE else F.TITLE_MED
	t.TextSize = if primary then 46 else 30
	t.TextColor3 = V.TEXT
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = label
	t.Parent = b
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Seta"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(1, 0)
	arrow.Position = UDim2.new(1, -22, 0, 0)
	arrow.Size = UDim2.new(0, 30, 1, 0)
	arrow.FontFace = F.TITLE
	arrow.TextSize = if primary then 40 else 26
	arrow.TextColor3 = if primary then UiKit.BRASS_LIGHT else V.DIM
	arrow.Text = "›"
	arrow.Parent = b
	local r =
		UiKit.realce(b, b.BackgroundColor3, if primary then V.RED_HI else V.PANEL_3, if primary then 1.04 else 1.035)
	local function hover(on: boolean)
		r.set(on)
		UiKit.tween(arrow, UiKit.QUICK, { Position = UDim2.new(1, if on then -12 else -22, 0, 0) })
	end
	b.MouseEnter:Connect(function()
		hover(true)
	end)
	b.MouseLeave:Connect(function()
		hover(false)
	end)
	b.SelectionGained:Connect(function()
		hover(true)
	end)
	b.SelectionLost:Connect(function()
		hover(false)
	end)
	local btn: Btn = { b = b, r = r, x = BX }
	table.insert(buttons, btn)
	return btn
end

local playB = makeButton("JOGAR", true, BY, 92)
local subPlay = text(group, F.BODY, 18, V.TEXT)
subPlay.Position = UDim2.fromOffset(BX + 6, BY + 98)
subPlay.Size = UDim2.fromOffset(440, 22)
subPlay.Text = "Entra num squad e vai direto para o campo."
local Y2 = BY + 132
local settingsB = makeButton("CONFIGURAÇÕES", false, Y2, 60)
local shopB = makeButton("LOJA", false, Y2 + 70, 60)
local passB = makeButton("PASSE", false, Y2 + 140, 60)
local tutB = makeButton("TUTORIAL", false, Y2 + 210, 60)
-- o controle anda só pela coluna (↑ ↓), em volta
local order = { playB, settingsB, shopB, passB, tutB }
for i, btn in order do
	btn.b.NextSelectionUp = order[if i == 1 then #order else i - 1].b
	btn.b.NextSelectionDown = order[if i == #order then 1 else i + 1].b
	btn.b.NextSelectionLeft = btn.b
	btn.b.NextSelectionRight = btn.b
end

-- dica do aparelho, embaixo à esquerda
local hint = text(group, F.TITLE_REG, 20, V.KHAKI)
hint.Position = UDim2.fromOffset(BX + 6, 686)
hint.Size = UDim2.fromOffset(600, 26)
local function refreshHint()
	if Input.isGamepad() then
		hint.Text = "A  ESCOLHER     ↑ ↓  ANDAR"
	elseif Input.touchActive() then
		hint.Text = ""
	else
		hint.Text = "ENTER  ESCOLHER     ↑ ↓  ANDAR"
	end
end
refreshHint()

-- ----- soldado -----
local soldier = SoldierPreview.newStill(-0.35)
local sFrame = soldier.frame :: Frame
sFrame.AnchorPoint = Vector2.new(1, 1)
sFrame.Position = UDim2.fromOffset(1250, 735)
sFrame.Size = UDim2.fromOffset(520, 700)
sFrame.Parent = group
local breathe = Instance.new("UIScale")
breathe.Parent = sFrame
local sideTag = text(group, F.TITLE_REG, 22, V.KHAKI)
sideTag.AnchorPoint = Vector2.new(1, 0)
sideTag.Position = UDim2.fromOffset(1220, 40)
sideTag.Size = UDim2.fromOffset(400, 28)
sideTag.TextXAlignment = Enum.TextXAlignment.Right
local SIDE_NAME = { US = "FUZILEIROS DOS EUA", VC = "VIET CONG" } :: { [string]: string }

-- ===== estado =====
local open = false
local opened = false -- já abriu nesta sessão (só reabre pelo gancho do Studio)
local t0 = os.clock()
local swapAt = 0
local shown: string? = nil
local loops: { Tween } = {}
local cc: ColorCorrectionEffect? = nil
local dof: DepthOfFieldEffect? = nil
local savedFov: number? = nil
local busy = false -- um botão de cada vez (o JOGAR fechando)

local function wantSide(): string
	local f = player:GetAttribute("Faction")
	if f == "US" or f == "VC" then
		return f
	end
	local now = os.clock()
	if now >= swapAt then
		swapAt = now + SOLDIER_SWAP_S
		return if shown == "US" then "VC" else "US"
	end
	return shown or "US"
end

local function syncSoldier()
	local f = wantSide()
	if f ~= shown then
		shown = f
		SoldierPreview.set(soldier, f, nil)
		sideTag.Text = SIDE_NAME[f] or ""
	end
end

local function camStep()
	local cam = workspace.CurrentCamera
	if not (open and cam) then
		return
	end
	local a = (os.clock() - t0) * 2 * math.pi / ORBIT_S
	local y = centerY()
	local r = ORBIT_R_M / M
	local eye = Vector3.new(CX + math.cos(a) * r, y + ORBIT_UP_M / M, CZ + math.sin(a) * r)
	local look = Vector3.new(CX, y + LOOK_UP_M / M, CZ)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(eye, look)
	cam.FieldOfView = FOV
	local d = dof
	if d then
		d.FocusDistance = (eye - look).Magnitude
	end
end

local function focusPlay()
	if open and Input.isGamepad() and not ComoJogar.isOpen() then
		GuiService.SelectedObject = playB.b
	end
end

local function stream()
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(Vector3.new(CX, centerY(), CZ), 8)
		end)
	end)
end

local function startLoops()
	for _, tw in loops do
		tw:Cancel()
	end
	table.clear(loops)
	local function loop(o: Instance, info: TweenInfo, props: { [string]: any })
		local tw = TweenService:Create(o, info, props)
		tw:Play()
		table.insert(loops, tw)
	end
	-- o soldado respira; o filete do JOGAR pulsa
	breathe.Scale = 1
	loop(breathe, TweenInfo.new(3.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.012 })
	local ring = playB.b:FindFirstChildOfClass("UIStroke")
	if ring then
		loop(
			ring,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.6),
			{ Transparency = 0.8 }
		)
	end
end

local function setOpen(on: boolean)
	if on == open then
		return
	end
	open = on
	player:SetAttribute("MenuPrincipal", on)
	local cam = workspace.CurrentCamera
	if on then
		opened = true
		busy = false
		t0 = os.clock() - math.random() * ORBIT_S -- cada entrada começa de um lado do morro
		groundY = nil
		stream()
		if cam then
			savedFov = cam.FieldOfView
		end
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "VT65MenuCor"
		c.TintColor = Color3.fromRGB(255, 240, 220)
		c.Contrast = 0.08
		c.Saturation = 0.06
		c.Parent = Lighting
		cc = c
		local d = Instance.new("DepthOfFieldEffect")
		d.Name = "VT65MenuDof"
		d.FarIntensity = 0.18
		d.NearIntensity = 0
		d.InFocusRadius = 140
		d.Parent = Lighting
		dof = d
		RunService:BindToRenderStep("VT65MenuCam", Enum.RenderPriority.Camera.Value + 5, camStep)
		camStep()
		Input.openMenu()
		syncSoldier()
		SoldierPreview.setActive(soldier, true)
		gui.Enabled = true
		-- entrada: a vinheta e o conteúdo esmaecem, os botões chegam da esquerda um depois do outro
		group.GroupTransparency = 1
		shade.BackgroundTransparency = 1
		UiKit.tween(group, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { GroupTransparency = 0 })
		UiKit.tween(shade, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 })
		titleBox.Position = UDim2.fromOffset(44, 70)
		UiKit.tween(titleBox, TweenInfo.new(0.9, Enum.EasingStyle.Quint), { Position = UDim2.fromOffset(84, 70) })
		for i, btn in order do
			local p = btn.b.Position
			btn.b.Position = UDim2.fromOffset(btn.x - 60, p.Y.Offset)
			task.delay(0.15 + 0.07 * i, function()
				if open then
					UiKit.tween(
						btn.b,
						TweenInfo.new(0.6, Enum.EasingStyle.Quint),
						{ Position = UDim2.fromOffset(btn.x, p.Y.Offset) }
					)
				end
			end)
		end
		sFrame.Position = UDim2.fromOffset(1310, 735)
		UiKit.tween(sFrame, TweenInfo.new(1.1, Enum.EasingStyle.Quint), { Position = UDim2.fromOffset(1250, 735) })
		startLoops()
		task.delay(0.4, focusPlay)
	else
		for _, tw in loops do
			tw:Cancel()
		end
		table.clear(loops)
		RunService:UnbindFromRenderStep("VT65MenuCam")
		if cc then
			cc:Destroy()
			cc = nil
		end
		if dof then
			dof:Destroy()
			dof = nil
		end
		if cam then
			cam.CameraType = Enum.CameraType.Custom -- a mesa (LobbyScene) ou o spawn assumem daqui
			cam.FieldOfView = savedFov or 70
		end
		SoldierPreview.setActive(soldier, false)
		UiKit.release(gui)
		gui.Enabled = false
		Input.closeMenu()
	end
end

-- JOGAR: o menu esmaece e o Jogar agora pede lado, squad, papel e ponto ao servidor
local function play()
	if busy or not open then
		return
	end
	busy = true
	UiKit.tween(group, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { GroupTransparency = 1 })
	local fade = UiKit.tween(shade, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 })
	fade.Completed:Wait()
	setOpen(false)
	Bus.fire("jogar_agora")
end

UiKit.bind(playB.b, function()
	task.spawn(play)
end)
UiKit.bind(settingsB.b, function()
	if open and not busy then
		Bus.fire("menu_open", 1) -- aba Configurações
	end
end)
UiKit.bind(shopB.b, function()
	if open and not busy then
		Bus.fire("shop_open")
	end
end)
UiKit.bind(passB.b, function()
	if open and not busy then
		Bus.fire("passe_open")
	end
end)
UiKit.bind(tutB.b, function()
	if open and not busy then
		ComoJogar.open()
	end
end)

-- o soldado troca de lado (antes de escolher) e o foco volta para o JOGAR quando outra tela fecha
RunService.Heartbeat:Connect(function()
	if not open then
		return
	end
	syncSoldier()
	if Input.isGamepad() and GuiService.SelectedObject == nil and UiKit.top() == nil and not ComoJogar.isOpen() then
		focusPlay()
	end
end)
Input.DeviceChanged:Connect(function()
	refreshHint()
	focusPlay()
end)
task.spawn(function()
	while true do
		task.wait(30)
		if open then
			stream()
		end
	end
end)

-- ===== quando abrir =====
-- Uma vez por sessão: quando a tela de entrada marca "Pronto" (ou some), sem corpo em campo.
local function inField(): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	local w0 = os.clock()
	while os.clock() - w0 < 300 do
		local lg = pg:FindFirstChild("VT65Loading")
		if lg == nil or not lg:IsA("ScreenGui") or lg:GetAttribute("Pronto") == true or not lg.Enabled then
			break
		end
		task.wait(0.2)
	end
	if not opened and not inField() then
		setOpen(true)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "menu_principal" then
			setOpen(true)
		end
	end)
end
