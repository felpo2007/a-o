--!strict
-- Aviso de granada perto (lote 24, pedido do dono: "coloque símbolo de granada perto: vermelho que vai
-- matar você e branco que vai dar dano"). A regra (raios, fogo amigo, a sua própria granada) fica em
-- Shared/GrenadeWarn; aqui o desenho:
--   - o símbolo da granada (corpo redondo, alavanca e anel do pino), vermelho e pulsando quando mataria,
--     branco quando só fere. D-191 (dono: "remova a metragem numérica exibida para granadas"): sem
--     o número da distância (antes "4 m" embaixo); a cor, o pulso e a direção continuam;
--   - granada à vista: o símbolo fica em cima dela na tela;
--   - granada fora da vista (atrás, do lado): o símbolo vai para um anel em volta do meio da tela, na
--     direção dela, com uma seta apontando para fora;
--   - até GrenadeWarn.MAX_SHOWN granadas (as mais perto); some fora de campo e quando ela explode.
-- As granadas são os modelos "Granada" em workspace.Granadas (FieldService), com Kind, Faction e By.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GrenadeWarn = require(ReplicatedStorage.Shared.GrenadeWarn)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local M = MapConfig.STUD_M
local px = UiKit.px

local RED = Color3.fromRGB(255, 52, 40)
local WHITE = Color3.fromRGB(250, 250, 246)
local ICON = px(52, 70) -- lado do símbolo
local RING = 0.3 -- raio do anel, em fração do menor lado da tela

local gui = UiKit.screen("VT65AvisoGranada", 14) -- acima do HUD de campo (13)
gui.IgnoreGuiInset = true

type Mark = {
	frame: Frame,
	body: Frame,
	lever: Frame,
	pin: Frame,
	dist: TextLabel,
	arrow: TextLabel,
	strokes: { UIStroke },
}

local function piece(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function outline(f: GuiObject, list: { UIStroke })
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Thickness = 2
	s.Transparency = 0.15
	s.Parent = f
	table.insert(list, s)
end

local function newMark(): Mark
	local strokes: { UIStroke } = {}
	local f = Instance.new("Frame")
	f.Name = "Granada"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(ICON, ICON)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.Parent = gui
	-- corpo: a granada redonda (um pouco mais alta que larga)
	local body = piece(f, "Corpo")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.new(0.5, 0, 1, 0)
	body.Size = UDim2.fromScale(0.66, 0.74)
	UiKit.corner(body, ICON)
	outline(body, strokes)
	-- alavanca: a colher em cima, puxada para o lado
	local lever = piece(f, "Alavanca")
	lever.AnchorPoint = Vector2.new(0, 1)
	lever.Position = UDim2.new(0.5, 0, 0.32, 0)
	lever.Size = UDim2.fromScale(0.34, 0.12)
	lever.Rotation = 28
	UiKit.corner(lever, 3)
	outline(lever, strokes)
	-- anel do pino
	local pin = piece(f, "Pino")
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.fromScale(0.3, 0.2)
	pin.Size = UDim2.fromScale(0.24, 0.24)
	pin.BackgroundTransparency = 1
	UiKit.corner(pin, ICON)
	local ring = Instance.new("UIStroke")
	ring.Thickness = 3
	ring.Parent = pin
	-- distância embaixo
	local dist = Instance.new("TextLabel")
	dist.Name = "Distancia"
	dist.BackgroundTransparency = 1
	dist.AnchorPoint = Vector2.new(0.5, 0)
	dist.Position = UDim2.new(0.5, 0, 1, px(2, 4))
	dist.Size = UDim2.fromOffset(px(90, 120), px(24, 32))
	dist.FontFace = UiKit.F.TITLE
	dist.TextSize = UiKit.text(px(20, 26))
	dist.TextStrokeTransparency = 0.2
	dist.TextStrokeColor3 = Color3.new(0, 0, 0)
	dist.Visible = false -- D-191: sem metragem
	dist.Parent = f
	-- seta para fora (só no anel)
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Seta"
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(px(28, 36), px(28, 36))
	arrow.FontFace = UiKit.F.TITLE
	arrow.Text = "▲"
	arrow.TextSize = UiKit.text(px(24, 32))
	arrow.TextStrokeTransparency = 0.2
	arrow.TextStrokeColor3 = Color3.new(0, 0, 0)
	arrow.Visible = false
	arrow.Parent = f
	return { frame = f, body = body, lever = lever, pin = pin, dist = dist, arrow = arrow, strokes = strokes }
end

local marks: { Mark } = {}
for i = 1, GrenadeWarn.MAX_SHOWN do
	marks[i] = newMark()
end

local function paint(m: Mark, kill: boolean, pulse: number)
	local c = if kill then RED else WHITE
	m.body.BackgroundColor3 = c
	m.lever.BackgroundColor3 = c
	local ring = m.pin:FindFirstChildOfClass("UIStroke")
	if ring then
		ring.Color = c
	end
	m.dist.TextColor3 = c
	m.arrow.TextColor3 = c
	-- vermelho pulsa (cresce e encolhe); branco fica parado
	local s = if kill then 1 + 0.18 * pulse else 1
	m.frame.Size = UDim2.fromOffset(math.floor(ICON * s), math.floor(ICON * s))
end

-- granadas vivas na pasta (atualizada pelo ChildAdded/Removed)
local live: { [Model]: BasePart } = {}
local function track(g: Instance)
	if not g:IsA("Model") then
		return
	end
	local core = g:WaitForChild("Nucleo", 3)
	if core and core:IsA("BasePart") and g.Parent then
		live[g] = core
	end
end
task.spawn(function()
	local folder = workspace:WaitForChild("Granadas", 120)
	if not folder then
		return
	end
	for _, g in folder:GetChildren() do
		task.spawn(track, g)
	end
	folder.ChildAdded:Connect(track)
	folder.ChildRemoved:Connect(function(g: Instance)
		live[g :: any] = nil
	end)
end)

local function alive(): BasePart?
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not (h and h.Health > 0 and root and root:IsA("BasePart")) then
		return nil
	end
	return root
end

type Near = { core: BasePart, distM: number, kill: boolean }
RunService.RenderStepped:Connect(function()
	local root = alive()
	local near: { Near } = {}
	if root then
		local myFaction = player:GetAttribute("Faction") :: string?
		for g, core in live do
			if g.Parent == nil or core.Parent == nil then
				live[g] = nil
				continue
			end
			local d = (core.Position - root.Position).Magnitude * M
			local by = g:GetAttribute("By")
			local level = GrenadeWarn.level(
				d,
				g:GetAttribute("Kind") :: string?,
				g:GetAttribute("Faction") :: string?,
				myFaction,
				by == player.UserId
			)
			if level then
				table.insert(near, { core = core, distM = d, kill = level == "kill" })
			end
		end
		table.sort(near, function(a, b)
			return a.distM < b.distM
		end)
	end
	-- a câmera do quadro (o jogo troca de câmera: menu, mesa, campo)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local vp = camera.ViewportSize
	local inset = gui.AbsolutePosition -- a ScreenGui ignora o recorte do topo; o ponto de tela já vem nela
	local cx, cy = vp.X / 2, vp.Y / 2
	local r = RING * math.min(vp.X, vp.Y)
	local margin = ICON
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 10)
	local look = camera.CFrame.LookVector
	for i, m in marks do
		local n = near[i]
		if not n then
			m.frame.Visible = false
			continue
		end
		local pos = n.core.Position
		local sp, onScreen = camera:WorldToViewportPoint(pos)
		local inside = onScreen
			and sp.Z > 0
			and sp.X > margin
			and sp.X < vp.X - margin
			and sp.Y > margin
			and sp.Y < vp.Y - margin
		if inside then
			-- em cima da granada, um pouco acima dela; a distância embaixo do símbolo
			m.frame.Position = UDim2.fromOffset(sp.X - inset.X, sp.Y - inset.Y - ICON * 0.6)
			m.arrow.Visible = false
			m.dist.AnchorPoint = Vector2.new(0.5, 0)
			m.dist.Position = UDim2.new(0.5, 0, 1, px(2, 4))
		else
			local dir = pos - camera.CFrame.Position
			local a = GrenadeWarn.ringAngle(look.X, look.Z, dir.X, dir.Z)
			local x, y = GrenadeWarn.ringPoint(a, cx, cy, r)
			m.frame.Position = UDim2.fromOffset(x - inset.X, y - inset.Y)
			-- a seta fica do lado de fora do símbolo, apontando para a granada; a distância do lado
			-- de dentro (para o meio da tela), sem bater na seta
			local ax, ay = math.sin(a), -math.cos(a)
			m.arrow.Visible = true
			m.arrow.Rotation = math.deg(a)
			m.arrow.Position = UDim2.new(0.5, ax * ICON * 0.9, 0.5, ay * ICON * 0.9)
			m.dist.AnchorPoint = Vector2.new(0.5, 0.5)
			m.dist.Position = UDim2.new(0.5, -ax * ICON * 1.05, 0.5, -ay * ICON * 1.05)
		end
		m.dist.Text = "" -- D-191: sem o número da distância (a regra de perto continua no GrenadeWarn)
		paint(m, n.kill, pulse)
		m.frame.Visible = true
	end
end)
