--!strict
-- Menu principal (lote 5, D-117; pedido do dono: "faça uma tela de menu animada bonita, que vai ter
-- atrás o fundo do mapa bonito e o soldado, e vai ter as opções jogar, configurações, loja, passe e
-- tutorial. Não quero mais o tutorial dentro do jogo"; "uma criança tem que conseguir jogar").
-- D-118 (dono, sobre a v49: "não gostei do personagem e do fundo"): saiu o retrato grande do soldado e
-- a volta da câmera por cima do morro. O fundo agora é o próprio mapa em planos de cinema:
--   - fim de tarde (MENU_HOUR: o sol real de 18/08/1965, baixo no oés-noroeste), luz dourada e
--     sombras compridas; volta a hora da partida quando o menu fecha;
--   - três planos de SHOT_S, com corte pelo preto: fuzileiros nos becos de Xóm Gò, o Viet Cong no
--     quintal de An Cường (2) olhando a vila e fuzileiros na encosta leste subindo para Xóm Gò. Os
--     soldados (SoldierPreview.newWorld, o manequim que o servidor vestiu) ficam no chão de verdade do
--     mapa; a câmera anda devagar perto deles, com foco neles e o resto desfocado;
--   - cada plano procura chão livre para os soldados (sem casa, muro ou tronco) e tira a câmera de
--     trás do que tapar a vista; sem terreno ainda, a câmera dá a volta em Xóm Gò como antes;
--   - faixas pretas em cima e embaixo, a vinheta escura à esquerda (texto) e o nome do lugar no canto.
-- À esquerda, o título e os cinco botões: JOGAR (Jogar agora: lado, squad, papel e ponto
-- automáticos, Controllers/JogarAgora), CONFIGURAÇÕES (menu do jogo, aba Configurações), LOJA,
-- PASSE e TUTORIAL (Controllers/ComoJogar, aqui mesmo, sem entrar na partida).
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
local SolarPosition = require(ReplicatedStorage.Shared.SolarPosition)
local Bus = require(script.Parent.Bus)
local ComoJogar = require(script.Parent.ComoJogar)
local Input = require(script.Parent.Input)
local SoldierPreview = require(script.Parent.SoldierPreview)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local M = MapConfig.STUD_M

-- ===== a cena (PLACEHOLDER de direção: conferido no Studio, ajustar a gosto) =====
local SHOT_S = 11 -- s por plano
local CUT_S = 0.7 -- s do corte pelo preto (cada metade)
-- fim de tarde de 18/08/1965 em Vạn Tường (hora de Saigon, UTC+8): sol a ~13° no oés-noroeste
local MENU_HOUR = 18.1
local SUN = { year = 1965, month = 8, day = 18, tz = 8, lat = 15.30, lon = 108.85 }

-- Posições no quadro do grupo, em metros: x = direita, y = altura sobre o chão daquele ponto,
-- z = frente (para onde o grupo olha). cam0 -> cam1 é o caminho da câmera no plano.
type Shot = {
	place: string, -- legenda: o nome do ponto do mapa
	anchor: string, -- ponto forte onde o grupo fica
	toward: string, -- ponto forte para onde o grupo olha
	faction: string,
	n: number, -- soldados no plano
	cam0: Vector3,
	cam1: Vector3,
	look: Vector3,
	fov: number,
}
local SHOTS: { Shot } = {
	{ -- de frente para o grupo que entra na vila (luz do sol de lado)
		place = "Becos de Xóm Gò",
		anchor = "Becos de Xóm Gò",
		toward = "Xóm Gò",
		faction = "US",
		n = 3,
		cam0 = Vector3.new(-3.6, 1.5, 9.5),
		cam1 = Vector3.new(-2.2, 1.6, 7.0),
		look = Vector3.new(2.0, 1.3, -1.5), -- o grupo fica à direita, longe dos botões
		fov = 38,
	},
	{ -- por cima do ombro: o VC olha a vila, de frente para o sol baixo
		place = "Quintal oeste de An Cường (2)",
		anchor = "Quintal oeste de An Cường (2)",
		toward = "An Cường (2)",
		faction = "VC",
		n = 3,
		cam0 = Vector3.new(1.8, 1.7, -8.5),
		cam1 = Vector3.new(1.0, 1.8, -6.8),
		look = Vector3.new(-8, 1.5, 40),
		fov = 45,
	},
	{ -- a câmera sobe atrás dos fuzileiros: o morro de Xóm Gò contra o sol
		place = "Encosta leste",
		anchor = "Encosta leste",
		toward = "Xóm Gò",
		faction = "US",
		n = 2,
		cam0 = Vector3.new(-2.5, 1.8, -6.5),
		cam1 = Vector3.new(-3.5, 5.0, -10.0),
		look = Vector3.new(-12, 6, 70),
		fov = 50,
	},
}
-- o grupo: o da frente e dois atrás, um para cada lado, cada um olhando um pouco para um lado
-- (até 3,2 m atrás do primeiro: a câmera por cima do ombro fica atrás de todos; no Studio, com 4,4 m,
-- ela passava a 0,9 m do terceiro)
local FORMATION = { Vector3.new(0, 0, 0), Vector3.new(-2.4, 0, -1.8), Vector3.new(2.6, 0, -3.2) }
local YAW = { 0, 14, -11 }
local SIDE_NAME = { US = "FUZILEIROS DOS EUA", VC = "VIET CONG" } :: { [string]: string }

-- a volta antiga, só enquanto o terreno não chega
local ORBIT_S = 240
local ORBIT_R_M = 120
local ORBIT_UP_M = 40

local function spXZ(name: string): Vector3?
	for _, sp in MapConfig.Strongpoints do
		if sp.name == name then
			return Vector3.new(sp.x, 0, sp.z)
		end
	end
	return nil
end
local CENTER = spXZ("Xóm Gò")
	or Vector3.new(
		(MapConfig.Bounds.minX + MapConfig.Bounds.maxX) / 2,
		0,
		(MapConfig.Bounds.minZ + MapConfig.Bounds.maxZ) / 2
	)

local scene = Instance.new("Folder")
scene.Name = "VT65MenuCena"
scene.Parent = workspace

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.IgnoreWater = true
local function groundAt(x: number, z: number): number?
	terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), terrainOnly)
	return if hit then hit.Position.Y else nil
end

-- casa, muro ou tronco no lugar do soldado (peças sólidas; folha e capim não contam)
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local function blocked(p: Vector3): boolean
	overlap.FilterDescendantsInstances = { scene }
	local box = CFrame.new(p + Vector3.new(0, 1.0 / M, 0))
	for _, part in workspace:GetPartBoundsInBox(box, Vector3.new(0.9 / M, 1.7 / M, 0.9 / M), overlap) do
		if part.CanCollide and part.Transparency < 0.9 then
			return true
		end
	end
	return false
end

-- chão livre em (x, z) ou o mais perto numa espiral (passos de 1,5 m até rMax metros)
local function freeSpot(x: number, z: number, rMax: number): Vector3?
	local y = groundAt(x, z)
	if y and not blocked(Vector3.new(x, y, z)) then
		return Vector3.new(x, y, z)
	end
	local step = 1.5 / M
	for r = step, rMax / M, step do
		local n = math.max(6, math.floor(2 * math.pi * r / step))
		for i = 0, n - 1 do
			local a = i / n * 2 * math.pi
			local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
			local py = groundAt(px, pz)
			if py and not blocked(Vector3.new(px, py, pz)) then
				return Vector3.new(px, py, pz)
			end
		end
	end
	return nil
end

-- a câmera não fica atrás de parede, árvore ou morro: vem para a frente do que tapar o grupo
local sight = RaycastParams.new()
sight.FilterType = Enum.RaycastFilterType.Exclude
sight.RespectCanCollide = true -- folha e capim não puxam a câmera (Studio: ela ia parar colada no soldado)
local function clearView(cam: Vector3, subject: Vector3): Vector3
	local g = groundAt(cam.X, cam.Z)
	if g and cam.Y < g + 0.6 / M then
		cam = Vector3.new(cam.X, g + 0.6 / M, cam.Z)
	end
	sight.FilterDescendantsInstances = { scene }
	local d = cam - subject
	local hit = workspace:Raycast(subject, d, sight)
	if hit then
		local keep = math.max((hit.Position - subject).Magnitude - 0.5 / M, 1.5 / M)
		return subject + d.Unit * keep
	end
	return cam
end

-- ===== tela =====
local gui = UiKit.screen("VT65MenuPrincipal", 28) -- acima do lobby (18 a 22), abaixo da loja (30)
gui.IgnoreGuiInset = true
gui.Enabled = false

-- o corte pelo preto entre os planos fica embaixo de tudo (só cobre o mapa)
local cut = Instance.new("Frame")
cut.Name = "Corte"
cut.Size = UDim2.fromScale(1, 1)
cut.BackgroundColor3 = Color3.new(0, 0, 0)
cut.BorderSizePixel = 0
cut.ZIndex = 0
cut.Parent = gui

-- vinheta: escura à esquerda (texto) e embaixo, aberta no meio e à direita (o mapa). Preta, não o
-- vinho do fundo das telas (no Studio, o chão do plano ficava avermelhado)
local SHADE = Color3.fromRGB(6, 6, 5)
local shade = Instance.new("Frame")
shade.Name = "Vinheta"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = SHADE
shade.BorderSizePixel = 0
shade.Parent = gui
local shadeGrad = Instance.new("UIGradient")
shadeGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(0.3, 0.35),
	NumberSequenceKeypoint.new(0.56, 1),
	NumberSequenceKeypoint.new(1, 1),
})
shadeGrad.Parent = shade
local floor = Instance.new("Frame")
floor.Name = "Chao"
floor.AnchorPoint = Vector2.new(0, 1)
floor.Position = UDim2.fromScale(0, 1)
floor.Size = UDim2.fromScale(1, 0.3)
floor.BackgroundColor3 = SHADE
floor.BorderSizePixel = 0
floor.Parent = gui
local floorGrad = Instance.new("UIGradient")
floorGrad.Rotation = -90
floorGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.4),
	NumberSequenceKeypoint.new(1, 1),
})
floorGrad.Parent = floor
-- faixas de cinema
for i, y in { 0, 1 } do
	local b = Instance.new("Frame")
	b.Name = if i == 1 then "FaixaCima" else "FaixaBaixo"
	b.AnchorPoint = Vector2.new(0, y)
	b.Position = UDim2.fromScale(0, y)
	b.Size = UDim2.fromScale(1, 0.055)
	b.BackgroundColor3 = Color3.new(0, 0, 0)
	b.BorderSizePixel = 0
	b.Parent = gui
end

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

-- tudo o que entra e sai junto (título, botões, legenda)
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

-- ----- legenda do plano (canto de baixo, à direita) -----
local capBox = Instance.new("CanvasGroup")
capBox.Name = "Legenda"
capBox.AnchorPoint = Vector2.new(1, 1)
capBox.Position = UDim2.fromOffset(1220, 668)
capBox.Size = UDim2.fromOffset(560, 74)
capBox.BackgroundTransparency = 1
capBox.GroupTransparency = 1
capBox.Parent = group
local capPlace = text(capBox, F.TITLE_MED, 30, V.TEXT)
capPlace.Size = UDim2.fromOffset(560, 36)
capPlace.TextXAlignment = Enum.TextXAlignment.Right
local capSide = text(capBox, F.TITLE_REG, 19, V.KHAKI)
capSide.Position = UDim2.fromOffset(0, 40)
capSide.Size = UDim2.fromOffset(560, 24)
capSide.TextXAlignment = Enum.TextXAlignment.Right
local capRule = Instance.new("Frame")
capRule.AnchorPoint = Vector2.new(1, 0)
capRule.Position = UDim2.new(1, 0, 0, 68)
capRule.Size = UDim2.fromOffset(64, 3)
capRule.BackgroundColor3 = UiKit.BRASS
capRule.BorderSizePixel = 0
capRule.Parent = capBox

-- ===== estado =====
local open = false
local opened = false -- já abriu nesta sessão (só reabre pelo gancho do Studio)
local t0 = os.clock()
local loops: { Tween } = {}
local cc: ColorCorrectionEffect? = nil
local dof: DepthOfFieldEffect? = nil
local savedFov: number? = nil
local busy = false -- um botão de cada vez (o JOGAR fechando)
local run = 0 -- cada abertura tem a sua sequência de planos

-- o plano montado: caminho da câmera, para onde olha e o foco
type Built = { c0: Vector3, c1: Vector3, look: Vector3, focus: Vector3, fov: number, t0: number }
local cur: Built? = nil
local shotIndex = math.random(1, #SHOTS)

-- o grupo de soldados (até 3), reaproveitado em todos os planos
local crew: { SoldierPreview.Preview } = {}
for i = 1, 3 do
	crew[i] = SoldierPreview.newWorld(scene, CFrame.identity)
end
local function hideCrew()
	for _, p in crew do
		SoldierPreview.set(p, nil, nil)
	end
end

-- ===== sol de fim de tarde =====
local menuC: number?, menuL: number? = nil, nil
local savedC, savedL = 0, 0
local function fitSun()
	if menuC then
		return
	end
	local az, el = SolarPosition.compute(SUN.year, SUN.month, SUN.day, MENU_HOUR, SUN.tz, SUN.lat, SUN.lon)
	local tx, ty, tz = SolarPosition.direction(az, el)
	local c0, l0 = Lighting.ClockTime, Lighting.GeographicLatitude
	local c, l = SolarPosition.fit(tx, ty, tz, function(c1: number, l1: number)
		Lighting.ClockTime = c1
		Lighting.GeographicLatitude = l1
		local d = Lighting:GetSunDirection()
		return d.X, d.Y, d.Z
	end, 17.5, 15)
	Lighting.ClockTime, Lighting.GeographicLatitude = c0, l0
	menuC, menuL = c, l
end
-- o servidor acerta o sol a cada 15 s (LightingService): enquanto o menu está aberto, vale o daqui
local function holdSun()
	local c, l = menuC, menuL
	if c and l and math.abs(Lighting.ClockTime - c) > 0.01 then
		Lighting.ClockTime = c
		Lighting.GeographicLatitude = l
	end
end

-- ===== planos =====
local function build(s: Shot): Built?
	local a, b = spXZ(s.anchor), spXZ(s.toward)
	if not (a and b) then
		return nil
	end
	local origin = freeSpot(a.X, a.Z, 12)
	if not origin then
		return nil
	end
	local fwd = Vector3.new(b.X - origin.X, 0, b.Z - origin.Z)
	if fwd.Magnitude < 1 then
		return nil
	end
	fwd = fwd.Unit
	local G = CFrame.lookAt(origin, origin + fwd)
	local function at(v: Vector3): Vector3 -- quadro do grupo (m) -> mundo, altura sobre o chão dali
		local p = G:PointToWorldSpace(Vector3.new(v.X, 0, -v.Z) / M)
		local g = groundAt(p.X, p.Z) or origin.Y
		return Vector3.new(p.X, g + v.Y / M, p.Z)
	end
	-- soldados
	local sum, n = Vector3.zero, 0
	for i, p in crew do
		local spot: Vector3? = nil
		if i <= s.n then
			local want = at(FORMATION[i])
			spot = if i == 1 then origin else freeSpot(want.X, want.Z, 3)
		end
		if spot then
			-- o rosto do manequim fica do lado −Z (o LookVector), conferido no Studio pelo decal da cabeça
			SoldierPreview.place(p, CFrame.lookAt(spot, spot + fwd) * CFrame.Angles(0, math.rad(YAW[i]), 0))
			SoldierPreview.set(p, s.faction, nil)
			sum += spot
			n += 1
		else
			SoldierPreview.set(p, nil, nil)
		end
	end
	local focus = sum / math.max(n, 1) + Vector3.new(0, 1.3 / M, 0)
	return {
		c0 = clearView(at(s.cam0), focus),
		c1 = clearView(at(s.cam1), focus),
		look = at(s.look),
		focus = focus,
		fov = s.fov,
		t0 = os.clock(),
	}
end

local function orbitCam(cam: Camera)
	local a = (os.clock() - t0) * 2 * math.pi / ORBIT_S
	local y = groundAt(CENTER.X, CENTER.Z) or 35 / M
	local r = ORBIT_R_M / M
	local eye = Vector3.new(CENTER.X + math.cos(a) * r, y + ORBIT_UP_M / M, CENTER.Z + math.sin(a) * r)
	local look = Vector3.new(CENTER.X, y + 3 / M, CENTER.Z)
	cam.CFrame = CFrame.lookAt(eye, look)
	cam.FieldOfView = 55
	local d = dof
	if d then
		d.FocusDistance = (eye - look).Magnitude
		d.InFocusRadius = 140
	end
end

local function camStep()
	local cam = workspace.CurrentCamera
	if not (open and cam) then
		return
	end
	holdSun()
	cam.CameraType = Enum.CameraType.Scriptable
	local s = cur
	if not s then
		orbitCam(cam)
		return
	end
	local now = os.clock()
	local k = math.clamp((now - s.t0) / SHOT_S, 0, 1)
	local e = (1 - math.cos(math.pi * k)) / 2
	local pos = s.c0:Lerp(s.c1, e)
	-- câmera na mão: um balanço bem pequeno
	local sway = Vector3.new(math.noise(now * 0.31, 1.7), math.noise(now * 0.27, 5.3), math.noise(now * 0.23, 9.1))
	cam.CFrame = CFrame.lookAt(pos + sway * (0.035 / M), s.look)
	cam.FieldOfView = s.fov
	local d = dof
	if d then
		d.FocusDistance = (pos - s.focus).Magnitude
		d.InFocusRadius = 6 / M
	end
end

local function caption(s: Shot)
	capPlace.Text = s.place
	capSide.Text = SIDE_NAME[s.faction] or ""
	capBox.GroupTransparency = 1
	capBox.Position = UDim2.fromOffset(1240, 668)
	task.delay(0.9, function()
		UiKit.tween(capBox, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { GroupTransparency = 0 })
		UiKit.tween(capBox, TweenInfo.new(1.4, Enum.EasingStyle.Quint), { Position = UDim2.fromOffset(1220, 668) })
	end)
end

local function stream()
	task.spawn(function()
		for _, s in SHOTS do
			local a = spXZ(s.anchor)
			if a then
				pcall(function()
					player:RequestStreamAroundAsync(Vector3.new(a.X, groundAt(a.X, a.Z) or 0, a.Z), 8)
				end)
			end
		end
	end)
end

-- a sequência: escuro -> monta o plano -> clareia -> SHOT_S -> escurece -> o próximo
local function sequence(token: number)
	cut.BackgroundTransparency = 0
	local fails = 0
	while open and token == run do
		local s = SHOTS[shotIndex]
		shotIndex = shotIndex % #SHOTS + 1
		local built = build(s)
		if built then
			fails = 0
			cur = built
			caption(s)
			UiKit.tween(cut, TweenInfo.new(CUT_S * 1.3, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 })
			task.wait(SHOT_S - CUT_S)
			if not (open and token == run) then
				break
			end
			UiKit.tween(capBox, TweenInfo.new(CUT_S, Enum.EasingStyle.Sine), { GroupTransparency = 1 })
			UiKit.tween(cut, TweenInfo.new(CUT_S, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 }).Completed
				:Wait()
		else
			fails += 1
			if fails >= #SHOTS then
				-- terreno ainda não chegou: a volta em Xóm Gò e tenta de novo daqui a pouco
				cur = nil
				hideCrew()
				UiKit.tween(cut, TweenInfo.new(CUT_S, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 })
				task.wait(4)
				fails = 0
			end
		end
	end
end

local function focusPlay()
	if open and Input.isGamepad() and not ComoJogar.isOpen() then
		GuiService.SelectedObject = playB.b
	end
end

local function startLoops()
	for _, tw in loops do
		tw:Cancel()
	end
	table.clear(loops)
	-- o filete do JOGAR pulsa
	local ring = playB.b:FindFirstChildOfClass("UIStroke")
	if ring then
		local tw = TweenService:Create(
			ring,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.6),
			{ Transparency = 0.8 }
		)
		tw:Play()
		table.insert(loops, tw)
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
		run += 1
		t0 = os.clock() - math.random() * ORBIT_S
		cur = nil
		stream()
		if cam then
			savedFov = cam.FieldOfView
		end
		savedC, savedL = Lighting.ClockTime, Lighting.GeographicLatitude
		fitSun()
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "VT65MenuCor"
		c.TintColor = Color3.fromRGB(255, 240, 226)
		c.Contrast = 0.1
		c.Saturation = -0.08 -- a terra batida no sol baixo ficava vermelha demais (Studio)
		c.Parent = Lighting
		cc = c
		local d = Instance.new("DepthOfFieldEffect")
		d.Name = "VT65MenuDof"
		d.FarIntensity = 0.32
		d.NearIntensity = 0.25
		d.InFocusRadius = 6 / M
		d.Parent = Lighting
		dof = d
		RunService:BindToRenderStep("VT65MenuCam", Enum.RenderPriority.Camera.Value + 5, camStep)
		camStep()
		Input.openMenu()
		gui.Enabled = true
		task.spawn(sequence, run)
		-- entrada: o conteúdo esmaece, os botões chegam da esquerda um depois do outro
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
		startLoops()
		task.delay(0.4, focusPlay)
	else
		run += 1
		for _, tw in loops do
			tw:Cancel()
		end
		table.clear(loops)
		RunService:UnbindFromRenderStep("VT65MenuCam")
		cur = nil
		hideCrew()
		if cc then
			cc:Destroy()
			cc = nil
		end
		if dof then
			dof:Destroy()
			dof = nil
		end
		-- a hora da partida volta (o servidor acerta de novo em até 15 s)
		local mc = menuC
		if mc and math.abs(Lighting.ClockTime - mc) <= 0.01 then
			Lighting.ClockTime, Lighting.GeographicLatitude = savedC, savedL
		end
		if cam then
			cam.CameraType = Enum.CameraType.Custom -- a mesa (LobbyScene) ou o spawn assumem daqui
			cam.FieldOfView = savedFov or 70
		end
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

-- o foco volta para o JOGAR quando outra tela fecha
RunService.Heartbeat:Connect(function()
	if not open then
		return
	end
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
