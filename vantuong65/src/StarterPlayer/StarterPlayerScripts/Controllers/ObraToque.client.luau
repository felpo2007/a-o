--!strict
-- Construção no toque (Parte 13, T2): antes de pedir a obra, a prévia dela no chão, à frente, com
-- botões de polegar para girar, confirmar e cancelar. No PC e no controle nada muda (a roda pede na
-- hora). Quem abre: InfantryController (roda de equipamento: pá e "Construir") e CommanderController
-- (painel de construir), pelo Bus "build_preview" (tipo da obra, ou "dig" para a pá).
-- O servidor manda no lugar (só leitura aqui): LogisticsService põe a obra 2 m à frente da raiz, no
-- rumo da raiz; FieldWorkService cava 1,5 m à frente. A prévia usa a mesma conta (ToqueTelas.buildSpot)
-- e GIRAR vira o soldado (raiz e câmera, em passos de 45°): o que se vê é o que o servidor faz.
-- Confirmar manda o mesmo remote de antes (Build_Request {kind} / Dig_Request); a recusa (inimigo
-- perto, sem caixote, limite) chega pelo Logistics_State, como sempre.
-- Studio: workspace:SetAttribute("VT65DevTela", "construir") abre a prévia do ninho de metralhadora.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FieldWork = require(ReplicatedStorage.Shared.FieldWork)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local M = 0.28
local V, F = UiKit.V, UiKit.F
local OK_COLOR = Color3.fromRGB(124, 178, 84)
local BAD_COLOR = Color3.fromRGB(212, 70, 52)

-- ===== fantasma no mundo =====
local ghost = Instance.new("Part")
ghost.Name = "VT65PreviaObra"
ghost.Anchored = true
ghost.CanCollide = false
ghost.CanQuery = false
ghost.CanTouch = false
ghost.CastShadow = false
ghost.Material = Enum.Material.SmoothPlastic
ghost.Transparency = 0.55
ghost.Color = OK_COLOR
local outline = Instance.new("SelectionBox")
outline.Adornee = ghost
outline.LineThickness = 0.04
outline.Color3 = OK_COLOR
outline.SurfaceTransparency = 1
outline.Parent = ghost
-- seta da frente (para onde a obra "olha")
local arrow = Instance.new("Part")
arrow.Name = "Frente"
arrow.Anchored = true
arrow.CanCollide = false
arrow.CanQuery = false
arrow.CanTouch = false
arrow.CastShadow = false
arrow.Material = Enum.Material.Neon
arrow.Transparency = 0.3
arrow.Size = Vector3.new(0.12, 0.04, 0.5) / M
arrow.Color = V.BRASS

-- ===== barra de botões =====
local gui = UiKit.screen("VT65Obra", 16)
gui.Enabled = false
local h = ToqueUi.minPx()
local bar = UiKit.panel(gui, V.PANEL, 0.08)
bar.Name = "Obra"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -12)
bar.AutomaticSize = Enum.AutomaticSize.XY
bar.Size = UDim2.new()
bar.Active = true
UiKit.pad(bar, 10, 10, 8, 10)
UiKit.list(bar, false, 6, Enum.HorizontalAlignment.Center)
local head = Instance.new("Frame")
head.BackgroundTransparency = 1
head.AutomaticSize = Enum.AutomaticSize.XY
head.Size = UDim2.new()
head.LayoutOrder = 1
head.Parent = bar
UiKit.list(head, false, 0, Enum.HorizontalAlignment.Center)
local title = UiKit.title(head, "", math.max(16, math.floor(h * 0.4)), V.TEXT)
title.AutomaticSize = Enum.AutomaticSize.XY
title.Size = UDim2.new()
title.LayoutOrder = 1
local sub = UiKit.text2(head, "", math.max(12, math.floor(h * 0.28)), V.DIM, F.BODY)
sub.AutomaticSize = Enum.AutomaticSize.XY
sub.Size = UDim2.new()
sub.LayoutOrder = 2
local row = Instance.new("Frame")
row.BackgroundTransparency = 1
row.AutomaticSize = Enum.AutomaticSize.XY
row.Size = UDim2.new()
row.LayoutOrder = 2
row.Parent = bar
UiKit.list(row, true, 8)
local function btn(text: string, kind: string?, w: number, order: number): TextButton
	local b = ToqueUi.bigButton(row, text, kind, w)
	b.LayoutOrder = order
	return b
end
local bLeft = btn("⟲", "secondary", h, 1)
bLeft.TextSize = math.floor(h * 0.55)
local bRight = btn("⟳", "secondary", h, 2)
bRight.TextSize = math.floor(h * 0.55)
local bOk = btn("CONSTRUIR", "primary", math.floor(h * 3.2), 3)
local bCancel = btn("✕", "secondary", h, 4)

-- ===== estado =====
type Cur = { kind: string, def: ToqueTelas.Preview }
local cur: Cur? = nil

local function root(): BasePart?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function stop()
	cur = nil
	gui.Enabled = false
	ghost.Parent = nil
	arrow.Parent = nil
end

-- pode pedir? (papel e suprimento: o resto, inimigo perto e caixote, só o servidor sabe)
local function check(kind: string): (boolean, string)
	if kind == "dig" then
		return true, string.format("fique parado %d s", FieldWork.DIG.seconds)
	end
	local b = Logistics.BUILDS[kind]
	local role = player:GetAttribute("Role")
	if not b then
		return false, "construção desconhecida"
	elseif not (type(role) == "string" and b.role[role]) then
		return false, "papel não pode construir"
	end
	local supply = tonumber(player:GetAttribute("Supply")) or 0
	if supply < b.cost then
		return false, "suprimento insuficiente"
	end
	return true, string.format("custo %d · suprimento %d", b.cost, supply)
end

local function start(kind: string)
	local def = ToqueTelas.PREVIEW[kind]
	if not def then
		return
	end
	cur = { kind = kind, def = def }
	local b = Logistics.BUILDS[kind]
	title.Text = UiKit.upper(if kind == "dig" then "Buraco de combate" elseif b then b.name else kind)
	title.FontFace = UiKit.headFont(title.Text)
	bOk.Text = if kind == "dig" then "CAVAR" else "CONSTRUIR"
	ghost.Size = Vector3.new(def.w, def.h, def.d) / M
	ghost.Parent = workspace.CurrentCamera
	arrow.Parent = workspace.CurrentCamera
	gui.Enabled = true
end

-- girar o soldado (a obra segue o rumo da raiz no servidor) e a câmera junto
local function turn(deg: number)
	local r = root()
	if not r then
		return
	end
	local _, yaw, _ = r.CFrame:ToOrientation()
	r.CFrame = CFrame.new(r.Position) * CFrame.Angles(0, ToqueTelas.turn(yaw, deg), 0)
	local cam = workspace.CurrentCamera
	if cam then
		local cf = cam.CFrame
		cam.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, math.rad(deg), 0) * cf.Rotation
	end
end

bLeft.Activated:Connect(function()
	turn(45)
end)
bRight.Activated:Connect(function()
	turn(-45)
end)
bCancel.Activated:Connect(stop)
bOk.Activated:Connect(function()
	local c = cur
	if not c then
		return
	end
	local ok = check(c.kind)
	if not ok then
		return
	end
	if c.kind == "dig" then
		Net.event("Dig_Request"):FireServer()
	else
		Net.event("Build_Request"):FireServer({ kind = c.kind })
	end
	stop()
end)

Bus.on("build_preview", function(kind: any)
	if type(kind) == "string" then
		start(kind)
	end
end)

-- ===== quadro a quadro: a prévia onde o servidor vai pôr =====
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
local lastSub = ""
RunService.RenderStepped:Connect(function()
	local c = cur
	if not c then
		return
	end
	local s = Input.state
	local r = root()
	if not r or not s.alive or s.downed or s.vehicle ~= nil or s.menus > 0 or s.map then
		stop()
		return
	end
	local rr = r :: BasePart
	local look = rr.CFrame.LookVector
	local x, z, yaw = ToqueTelas.buildSpot(rr.Position.X, rr.Position.Z, look.X, look.Z, c.def.ahead / M)
	params.FilterDescendantsInstances = { player.Character :: Model, ghost, arrow }
	local hit = workspace:Raycast(Vector3.new(x, rr.Position.Y + 8, z), Vector3.new(0, -40, 0), params)
	local y = if hit then hit.Position.Y else rr.Position.Y - 3
	local cf = CFrame.new(x, y + ghost.Size.Y / 2, z) * CFrame.Angles(0, yaw, 0)
	ghost.CFrame = cf
	arrow.CFrame = cf * CFrame.new(0, ghost.Size.Y / 2 + 0.05 / M, -ghost.Size.Z / 2 - 0.25 / M)
	local ok, why = check(c.kind)
	local color = if ok then OK_COLOR else BAD_COLOR
	ghost.Color = color
	outline.Color3 = color
	bOk.BackgroundColor3 = if ok then V.OLIVE else V.PANEL_2
	bOk.TextTransparency = if ok then 0 else 0.35
	if why ~= lastSub then
		lastSub = why
		sub.Text = why
	end
end)

player.CharacterAdded:Connect(stop)

-- Studio: a prévia do ninho de metralhadora (sacos de areia), com ou sem toque
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "construir" then
			start("mg_nest")
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
