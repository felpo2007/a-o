--!strict
-- Fundo da tela de deslocamento. Enquanto ela está aberta e o jogador não tem personagem (ou morreu
-- há mais de DEAD_GRACE s), a câmera (Scriptable) mostra o mapa real perto do QG do jogador, com
-- deriva lenta; antes de escolher o lado, gira devagar em volta de An Cường (2). Pede streaming em
-- volta do ponto. Efeitos só do lobby: profundidade de campo, correção de cor mais escura e uma
-- vinheta com pauta de carta em tela cheia, para a interface ler bem. Tudo volta ao normal quando o
-- personagem nasce (câmera Custom, efeitos removidos).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local UiKit = require(script.Parent.UiKit)

local LobbyScene = {}
local player = Players.LocalPlayer

local DEAD_GRACE = 2.5 -- s: depois de morrer, o corpo fica na tela um instante antes da cena
local B = MapConfig.Bounds

-- ===== vinheta e pauta (tela cheia, por baixo dos menus) =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65LobbyBackdrop"
gui.ResetOnSpawn = false
gui.DisplayOrder = 19 -- logo abaixo dos menus (VT65Menus = 20)
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None -- decoração: cobre também o entalhe da tela
end)

local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.BackgroundColor3 = UiKit.NIGHT
dim.BorderSizePixel = 0
dim.Size = UDim2.fromScale(1, 1)
dim.Parent = gui

-- vinheta: quatro faixas com gradiente de transparência (o UIGradient é só linear)
local function edge(rot: number, size: UDim2, pos: UDim2, anchor: Vector2)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.AnchorPoint = anchor
	f.Position = pos
	f.Size = size
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	f.Parent = gui
end
edge(90, UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0), Vector2.zero) -- topo
edge(-90, UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 1), Vector2.new(0, 1)) -- base
edge(0, UDim2.fromScale(0.24, 1), UDim2.fromScale(0, 0), Vector2.zero) -- esquerda
edge(180, UDim2.fromScale(0.24, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0)) -- direita

-- pauta de carta (quadrícula fina), lembrando a grade da carta de 1965
local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.Size = UDim2.fromScale(1, 1)
grid.Parent = gui
for i = 1, 11 do
	local v = Instance.new("Frame")
	v.BackgroundColor3 = UiKit.KHAKI
	v.BackgroundTransparency = 0.93
	v.BorderSizePixel = 0
	v.Position = UDim2.fromScale(i / 12, 0)
	v.Size = UDim2.new(0, 1, 1, 0)
	v.Parent = grid
end
for i = 1, 6 do
	local h = Instance.new("Frame")
	h.BackgroundColor3 = UiKit.KHAKI
	h.BackgroundTransparency = 0.93
	h.BorderSizePixel = 0
	h.Position = UDim2.fromScale(0, i / 7)
	h.Size = UDim2.new(1, 0, 0, 1)
	h.Parent = grid
end
gui.Parent = player:WaitForChild("PlayerGui")

-- ===== efeitos de pós-processamento (só no lobby) =====
local dof: DepthOfFieldEffect? = nil
local grade: ColorCorrectionEffect? = nil

local function setEffects(on: boolean)
	if on and not dof then
		local d = Instance.new("DepthOfFieldEffect")
		d.Name = "VT65LobbyDOF"
		d.FarIntensity = 0.6
		d.NearIntensity = 0.3
		d.FocusDistance = 160
		d.InFocusRadius = 50
		d.Parent = Lighting
		dof = d
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "VT65LobbyGrade"
		c.Brightness = -0.06
		c.Contrast = 0.06
		c.Saturation = -0.3
		c.TintColor = Color3.fromRGB(255, 240, 220)
		c.Parent = Lighting
		grade = c
	elseif not on and dof then
		dof:Destroy()
		dof = nil
		if grade then
			grade:Destroy()
			grade = nil
		end
	end
end

-- ===== câmera de cena =====
local function neutralPoint(): (number, number)
	for _, sp in MapConfig.Strongpoints do
		if sp.name == "An Cường (2)" then
			return sp.x, sp.z
		end
	end
	return (B.minX + B.maxX) / 2, (B.minZ + B.maxZ) / 2
end

type Shot = { orbit: boolean, fx: number, fz: number, dx: number, dz: number }
local function shotFor(faction: string?): Shot
	local hq = faction and MapConfig.HQ[faction]
	if hq then
		-- do QG para o centro da área jogável: a câmera fica atrás do QG olhando o campo
		local cx, cz = (B.minX + B.maxX) / 2, (B.minZ + B.maxZ) / 2
		local dx, dz = cx - hq.x, cz - hq.z
		local len = math.max(math.sqrt(dx * dx + dz * dz), 1)
		return { orbit = false, fx = hq.x, fz = hq.z, dx = dx / len, dz = dz / len }
	end
	local x, z = neutralPoint()
	return { orbit = true, fx = x, fz = z, dx = 0, dz = 0 }
end

local shot: Shot = shotFor(nil)
local shotKey: string = "?"
local camOn = false
local t0 = os.clock()
local camY, lookY = 120, 40 -- studs; trocados pelo chão real (raio no terreno) quando ele chega
local groundCam, groundLook = 20, 20
local nextProbe = 0
local nextStream = 0
local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Include
probe.FilterDescendantsInstances = { workspace.Terrain }

local function groundAt(x: number, z: number): number?
	local hit = workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), probe)
	return if hit then hit.Position.Y else nil
end

local function clampX(x: number): number
	return math.clamp(x, B.minX, B.maxX)
end
local function clampZ(z: number): number
	return math.clamp(z, B.minZ, B.maxZ)
end

-- posição da câmera e do alvo no instante t (studs)
local function pose(t: number): (number, number, number, number)
	local s = shot
	if s.orbit then
		local a = t * (2 * math.pi / 320) -- uma volta em ~5 min
		return s.fx + math.cos(a) * 300, s.fz + math.sin(a) * 300, s.fx, s.fz
	end
	local px, pz = -s.dz, s.dx -- perpendicular (deriva lateral)
	local sway = math.sin(t * 0.045) * 90
	local cx = s.fx - s.dx * 160 + px * sway
	local cz = s.fz - s.dz * 160 + pz * sway
	local lx = s.fx + s.dx * 520 + px * sway * 0.4
	local lz = s.fz + s.dz * 520 + pz * sway * 0.4
	return clampX(cx), clampZ(cz), lx, lz
end

local function stream(x: number, z: number)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(Vector3.new(x, groundCam, z), 10)
		end)
	end)
end

local snap = true -- primeiro chão achado (ou troca de plano): corta direto para a altura certa
local k0 = 1 -- 1 = sem suavizar neste quadro (corte)

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local t = now - t0
	local cx, cz, lx, lz = pose(t)
	if now >= nextProbe then
		nextProbe = now + 0.5
		local g1, g2 = groundAt(cx, cz), groundAt(lx, lz)
		groundCam = g1 or groundCam
		groundLook = g2 or groundLook
		if snap and g1 then
			snap = false
			k0 = 1
		end
	end
	if now >= nextStream then
		nextStream = now + 30
		stream((cx + lx) / 2, (cz + lz) / 2)
	end
	local up = if shot.orbit then 85 else 60
	local k = math.max(k0, math.min(1, dt * 1.2))
	k0 = 0
	camY += (groundCam + up + math.sin(t * 0.03) * 6 - camY) * k
	lookY += (groundLook + 10 - lookY) * k
	camera.CFrame = CFrame.lookAt(Vector3.new(cx, camY, cz), Vector3.new(lx, lookY, lz))
end

local function setCamera(on: boolean)
	if on == camOn then
		return
	end
	camOn = on
	local camera = workspace.CurrentCamera
	if on then
		t0 = os.clock()
		nextProbe, nextStream = 0, 0
		snap, k0 = true, 1
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		RunService:BindToRenderStep("VT65LobbyCam", Enum.RenderPriority.Camera.Value + 2, step)
	else
		RunService:UnbindFromRenderStep("VT65LobbyCam")
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				camera.CameraSubject = hum
			end
		end
	end
end

-- ===== estado =====
local lobbyOpen = false
local diedAt: number? = nil

local function evaluate()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local spawning = char ~= nil and hum == nil -- o CharacterAdded chega antes do Humanoid
	local dead = hum ~= nil and hum.Health <= 0
	local noBody = char == nil or (dead and diedAt ~= nil and os.clock() - diedAt >= DEAD_GRACE)
	local dressed = lobbyOpen and not spawning
	setCamera(lobbyOpen and noBody)
	setEffects(dressed)
	gui.Enabled = dressed
	-- a janela padrão do chat do Roblox escrevia por cima do cabeçalho do dossiê (captura, D-64)
	pcall(function()
		local cfg = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		if cfg then
			cfg.Enabled = not dressed
		end
	end)
	-- com a cena atrás, escurece menos (a cena é o fundo); vivo (troca de papel), escurece mais
	dim.BackgroundTransparency = if camOn then 0.62 else 0.38
end

-- open: a tela de deslocamento está visível; faction: lado do jogador (nil antes de escolher)
function LobbyScene.update(open: boolean, faction: string?)
	lobbyOpen = open
	local key = faction or "-"
	if key ~= shotKey then
		shotKey = key
		shot = shotFor(faction)
		nextStream, nextProbe = 0, 0 -- pede o streaming do ponto novo já
		snap, k0 = true, 1
		local cx, cz, lx, lz = pose(os.clock() - t0)
		stream((cx + lx) / 2, (cz + lz) / 2)
	end
	evaluate()
	if dof then
		-- foco no QG (a ~170 studs) ou na vila do plano neutro (a ~300 studs; 200 é o máximo)
		dof.FocusDistance = if shot.orbit then 200 else 160
	end
end

local function watchCharacter(char: Model)
	diedAt = nil
	-- personagem nasceu: câmera normal e sem efeitos do lobby, já (o GameUI reavalia depois)
	lobbyOpen = false
	evaluate()
	task.spawn(function()
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then
			return
		end
		local camera = workspace.CurrentCamera
		if camera and not camOn and camera.CameraSubject ~= hum then
			camera.CameraSubject = hum
		end
		hum.Died:Connect(function()
			diedAt = os.clock()
			task.delay(DEAD_GRACE + 0.05, evaluate)
		end)
	end)
end
player.CharacterAdded:Connect(watchCharacter)
player.CharacterRemoving:Connect(function()
	task.defer(evaluate)
end)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

return LobbyScene
