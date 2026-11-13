--!strict
-- Terceira pessoa opcional (pedido do dono, 2026-11-11): câmera sobre o ombro, lado trocável.
-- - Liga/desliga: tecla O ou direcional → segurado; troca de ombro: tecla I ou direcional ↑ segurado
--   (a escolha fica salva na conta, Input.setSetting). Também no menu: Configurações › Mira.
-- - A câmera de 1ª pessoa do Roblox (LockFirstPerson) continua cuidando da rotação, do mouse preso e
--   do personagem virado para a câmera; este script só desloca a câmera para trás do ombro DEPOIS dela
--   (prioridade Camera+2, depois do CameraLook), então recuo, balanço e olhar no analógico seguem iguais.
-- - Colisão: esfera + raio do olho até o ombro e do ombro até a câmera. Parede e terreno puxam a câmera
--   na hora (nunca atravessa); folhagem (sem colisão) aproxima suave, até 1 m do ombro.
-- - Mirar (mira de ferro) e binóculo voltam para a 1ª pessoa; soltar volta à 3ª. Veículo, caído, tela
--   de spawn e lobby: 1ª pessoa, como antes.
-- - O próprio corpo e a arma do personagem ("Weapon", a que os outros veem) aparecem: a câmera do
--   Roblox os esconde com LocalTransparencyModifier = 1 em 1ª pessoa; aqui volta a 0 a cada quadro.
-- - Contrato com o WeaponVisuals: atributo local "ThirdPersonView" (ver ViewMode).
-- - O servidor pode proibir por modo: workspace:SetAttribute("ThirdPersonAllowed", false).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Movement = require(ReplicatedStorage.Shared.Movement)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ViewMode = require(script.Parent.ViewMode)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = Movement.STUD_M

player:SetAttribute("ThirdPersonView", false)

-- ===== entradas =====
local function shoulderName(): string
	return if Input.settings.shoulderLeft then "ombro esquerdo" else "ombro direito"
end

local function toggleView()
	if not ViewMode.allowed() then
		Bus.fire("toast", "3ª pessoa desligada neste modo")
		return
	end
	local on = not Input.settings.thirdPerson
	Input.setSetting("thirdPerson", on)
	Bus.fire("toast", if on then string.format("Câmera: 3ª pessoa (%s)", shoulderName()) else "Câmera: 1ª pessoa")
end
Input.on("view_toggle", "press", toggleView) -- tecla O
Input.on("view_toggle", "holdStart", toggleView) -- direcional → segurado

local function swapShoulder()
	Input.setSetting("shoulderLeft", not Input.settings.shoulderLeft)
	Bus.fire("toast", string.format("Câmera: %s", shoulderName()))
end
Input.on("shoulder_swap", "press", swapShoulder) -- tecla I
Input.on("shoulder_swap", "holdStart", swapShoulder) -- direcional ↑ segurado
-- 2026-11-13 ("coloque o botão para 3ª pessoa"): as mesmas funções para quem não passa pelo Input
-- (botão de toque, menu) e pelo Bus
ViewMode.toggle = toggleView
ViewMode.swapShoulder = swapShoulder
ViewMode.wanted = function(): boolean
	return Input.settings.thirdPerson == true
end
Bus.on("view_toggle", toggleView)

-- Aviso do botão nas duas primeiras entradas em campo (no Front 44 é o H; aqui o H é desistir)
local hints = 0
local function hint()
	hints += 1
	if hints > 2 or not ViewMode.allowed() then
		return
	end
	task.delay(4, function()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or Input.settings.thirdPerson then
			return
		end
		local text = if Input.touchActive()
			then "CÂMERA: 1ª / 3ª pessoa"
			elseif Input.isGamepad() then "Segure → no direcional: 1ª / 3ª pessoa"
			else "Tecla O: 1ª / 3ª pessoa"
		Bus.fire("toast", text)
	end)
end
player.CharacterAdded:Connect(hint)

workspace:GetAttributeChangedSignal("ThirdPersonAllowed"):Connect(function()
	if not ViewMode.allowed() and Input.settings.thirdPerson then
		Bus.fire("toast", "3ª pessoa desligada neste modo")
	end
end)

-- ===== peças do próprio corpo (para mostrar em 3ª pessoa) =====
local parts: { Instance } = {}
local partConns: { RBXScriptConnection } = {}
local bodyShown = false -- mexemos na transparência local (precisa devolver em 1ª pessoa)

local function watchBody(char: Model)
	for _, c in partConns do
		c:Disconnect()
	end
	table.clear(partConns)
	parts = {}
	bodyShown = false
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(parts, d)
		end
	end
	table.insert(
		partConns,
		char.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") or d:IsA("Decal") then
				table.insert(parts, d)
			end
		end)
	)
	table.insert(
		partConns,
		char.DescendantRemoving:Connect(function(d)
			local i = table.find(parts, d)
			if i then
				table.remove(parts, i)
			end
		end)
	)
end
player.CharacterAdded:Connect(watchBody)
if player.Character then
	watchBody(player.Character)
end

-- transparência local de todo o corpo (inclui a arma "Weapon"); só escreve o que mudou
local function setBody(v: number)
	for _, d in parts do
		if d:IsA("BasePart") then
			if d.LocalTransparencyModifier ~= v then
				d.LocalTransparencyModifier = v
			end
		elseif d:IsA("Decal") then
			if d.LocalTransparencyModifier ~= v then
				d.LocalTransparencyModifier = v
			end
		end
	end
end

-- ===== retícula simples (só em 3ª pessoa) =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65ThirdPerson"
gui.ResetOnSpawn = false
gui.DisplayOrder = 14
gui.IgnoreGuiInset = true -- centro exato do viewport (o raio da mira sai do centro da câmera)
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local RET_COLOR = Color3.fromRGB(232, 224, 196)
local function tick(w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = RET_COLOR
	f.BackgroundTransparency = 0.25
	local s = Instance.new("UIStroke")
	s.Thickness = 1
	s.Transparency = 0.6
	s.Color = Color3.new(0, 0, 0)
	s.Parent = f
	f.Parent = gui
	return f
end
tick(2, 2) -- ponto central
local ticks = { tick(2, 7), tick(2, 7), tick(7, 2), tick(7, 2) } -- cima, baixo, esquerda, direita
local DIRS = { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) }

-- D-81: o tiro sai do olho do soldado, não da câmera do ombro. Se algo entre o olho e o ponto da
-- retícula (borda de dique, parede, tronco) for pegar a bala antes, a retícula fica vermelha: em 3ª
-- pessoa a câmera vê por cima do que o soldado não vê.
local BLOCKED_COLOR = Color3.fromRGB(220, 70, 60)
local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Exclude
blockParams.RespectCanCollide = true
local blockedAt = 0
local blocked = false

local function updateReticle()
	-- abertura = dispersão do quadril (Movement.hipSpreadDeg), projetada na tela; mirando não há
	-- dispersão (WeaponController.shotRay): a retícula fecha no ponto
	local aimingNow = player:GetAttribute("Aiming") == true
	local spread = if aimingNow then 0 else ViewMode.hipSpread()
	local half = math.tan(math.rad(camera.FieldOfView / 2))
	local gap = math.clamp(math.tan(math.rad(spread)) / half * camera.ViewportSize.Y / 2, 3, 80)
	for i, t in ticks do
		local d = DIRS[i]
		t.Position = UDim2.new(0.5, d.X * (gap + 3.5), 0.5, d.Y * (gap + 3.5))
	end
	local now = os.clock()
	if now - blockedAt > 0.1 then
		blockedAt = now
		local char = player.Character
		local o = ViewMode.origin()
		local p = ViewMode.aimPoint(1500 / M)
		blockParams.FilterDescendantsInstances = if char then { char } else {}
		local hit = workspace:Raycast(o, p - o, blockParams)
		blocked = hit ~= nil and (p - hit.Position).Magnitude > 1.5
	end
	local color = if blocked then BLOCKED_COLOR else RET_COLOR
	for _, t in ticks do
		t.BackgroundColor3 = color
	end
end

-- ===== câmera =====
local alpha = 0 -- mistura linear 0 (1ª) .. 1 (3ª)
local wasAiming = false
local side = if Input.settings.shoulderLeft then -1 else 1 -- −1..1, suavizado na troca de ombro
local off = { side = 0.55, up = 0.12, back = 2.1 } -- deslocamento atual (m), suavizado pela postura
local boom = -1 -- distância atual (studs) do ombro até a câmera, em 3ª pessoa cheia (−1 = recomeçar)
local viewAttr = false

local function setView(on: boolean)
	ViewMode.third = on
	if on ~= viewAttr then
		viewAttr = on
		player:SetAttribute("ThirdPersonView", on)
	end
end

local function ignoreList(char: Model): { Instance }
	local list: { Instance } = { char, camera }
	local fx = workspace:FindFirstChild("VT65Effects")
	if fx then
		table.insert(list, fx)
	end
	return list
end

-- Distância livre (studs) de `from` ao longo de `dir` (vetor com o comprimento desejado), só contra
-- o que tem colisão (paredes, casas, sacos de areia, terreno). Esfera e raio fino: a esfera não vê o
-- que já toca o ponto de partida.
local solid = RaycastParams.new()
solid.FilterType = Enum.RaycastFilterType.Exclude
solid.RespectCanCollide = true
solid.IgnoreWater = true
local function freeDistance(from: Vector3, dir: Vector3): (number, boolean)
	local len = dir.Magnitude
	if len < 1e-4 then
		return 0, false
	end
	local margin = Movement.CAM_MARGIN_M / M
	local best, hit = len, false
	local s = workspace:Spherecast(from, Movement.CAM_RADIUS_M / M, dir, solid)
	if s then
		best, hit = math.min(best, math.max(s.Distance - margin, 0)), true
	end
	local r = workspace:Raycast(from, dir, solid)
	if r then
		best, hit = math.min(best, math.max((r.Position - from).Magnitude - margin, 0)), true
	end
	return best, hit
end

-- Folhagem sem colisão (bambu, capim, copas): o primeiro toque a partir de FOLIAGE_MIN_M.
local leaves = RaycastParams.new()
leaves.FilterType = Enum.RaycastFilterType.Exclude
leaves.IgnoreWater = true
local function foliageDistance(from: Vector3, dir: Vector3): number
	local len = dir.Magnitude
	local minD = Movement.FOLIAGE_MIN_M / M
	if len <= minD then
		return len
	end
	local u = dir.Unit
	local r = workspace:Raycast(from + u * minD, u * (len - minD), leaves)
	if r and r.Instance:IsA("BasePart") and not r.Instance.CanCollide then
		return math.max((r.Position - from).Magnitude - Movement.CAM_MARGIN_M / M, minD)
	end
	return len
end

local function stanceOf(char: Model): string
	return if char:GetAttribute("Prone") == true
		then "prone"
		elseif char:GetAttribute("Crouched") == true then "crouch"
		else "stand"
end

RunService:BindToRenderStep("VT65ThirdPerson", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local custom = hum ~= nil and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == hum
	local aiming = player:GetAttribute("Aiming") == true
	local binocs = player:GetAttribute("Binoculars") == true
	-- voltando da mira: a transição curta de saída vale até a câmera chegar ao ombro
	if aiming or binocs then
		wasAiming = Input.settings.thirdPerson
	elseif alpha >= 1 or not Input.settings.thirdPerson then
		wasAiming = false
	end
	local target, time = Movement.viewTarget({
		want = Input.settings.thirdPerson,
		allowed = ViewMode.allowed(),
		alive = hum ~= nil and hum.Health > 0 and Input.state.alive,
		customCamera = custom,
		seated = (hum ~= nil and hum.SeatPart ~= nil) or Input.state.vehicle ~= nil,
		downed = player:GetAttribute("Downed") == true,
		aiming = aiming,
		binoculars = binocs,
	}, wasAiming)
	alpha = Movement.viewStep(alpha, target, dt, time)
	local a = Movement.ease(alpha)
	ViewMode.alpha = a
	local cf = camera.CFrame
	ViewMode.eye = cf.Position -- a câmera de 1ª pessoa, antes do deslocamento: o olho
	if a <= 0 or not (custom and char and root) then
		setView(false)
		gui.Enabled = false
		boom = -1 -- próxima entrada começa já na distância livre (a transição é a mistura)
		if bodyShown and custom then
			setBody(1) -- 1ª pessoa: corpo escondido de novo, como a câmera do Roblox deixa
			bodyShown = false
		end
		return
	end
	local c = char :: Model
	local list = ignoreList(c)
	solid.FilterDescendantsInstances = list
	leaves.FilterDescendantsInstances = list
	-- deslocamento pela postura e troca de ombro, suaves
	local sh = Movement.shoulder(stanceOf(c))
	local k = 1 - math.exp(-dt / 0.2)
	off.side += (sh.side - off.side) * k
	off.up += (sh.up - off.up) * k
	off.back += (sh.back - off.back) * k
	side += ((if Input.settings.shoulderLeft then -1 else 1) - side) * (1 - math.exp(-dt / 0.12))
	local rot = cf.Rotation
	local pivot = cf.Position
	-- 1) do olho até o ombro (parede ao lado encolhe o ombro)
	local toShoulder = (rot.RightVector * (off.side * side) + Vector3.yAxis * off.up) * (a / M)
	local sd = freeDistance(pivot, toShoulder)
	local shoulderPos = if toShoulder.Magnitude > 1e-4 then pivot + toShoulder.Unit * sd else pivot
	-- 2) do ombro para trás
	local back = -rot.LookVector
	local full = off.back / M
	local solidD, solidHit = freeDistance(shoulderPos, back * full)
	local leafD = foliageDistance(shoulderPos, back * math.min(full, solidD))
	local want = math.min(solidD, leafD)
	if boom < 0 then
		boom = want
	end
	boom = Movement.boomStep(boom, want, dt, solidHit and solidD <= boom)
	boom = math.min(boom, solidD) -- nunca atrás da parede
	local camPos = shoulderPos + back * (boom * a)
	camera.CFrame = CFrame.new(camPos) * rot
	local third = a >= Movement.VIEW_THRESHOLD
	setView(third)
	if third then
		setBody(Movement.bodyFade((camPos - pivot).Magnitude * M))
		bodyShown = true
	else
		setBody(1)
	end
	gui.Enabled = third and Input.state.menus == 0 and not Input.state.map
	if gui.Enabled then
		updateReticle()
	end
end)
