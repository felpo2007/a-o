--!strict
-- Acerto (D-107; pedidos do dono: "os tiros não estão acertando", "concerte o hitbox dos
-- personagens", "mostre quando você acerta o tiro com o dano, ou barulho diferente mas leve").
-- 1. Acerto visto: a cada tiro próprio (Bus "shot_fired") refaz a bala com a mesma semente
--    (Shared/Hitbox.trace, a mesma conta do servidor) contra as caixas de acerto dos soldados COMO
--    ESTE cliente os vê: posição na tela, postura, animação e inclinação. Se a bala pega alguém,
--    manda Combat_Claim; o servidor confere (trajetória, caminho livre, alvo perto) e aplica o dano.
-- 2. Marcador: o servidor confirma o acerto só para quem atirou (Combat_Confirm). X leve no centro
--    da tela (onde a mira está, em 1ª e 3ª pessoa) e o dano em número pequeno que sobe e some. Cor:
--    claro no corpo, latão na cabeça, vermelho no abate (caiu ou morreu), azul no companheiro. Som
--    leve e diferente para corpo, cabeça e abate (Shared/SomArmas), e o baque da bala no alvo. Só
--    imagem e som: vale igual com mouse, controle e toque.
-- 3. Studio: workspace:SetAttribute("VT65DevHitbox", true) desenha as caixas de acerto (vermelho
--    cabeça, laranja tronco, amarelo braço e perna) como este cliente as vê.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Hitbox = require(ReplicatedStorage.Shared.Hitbox)
local Net = require(ReplicatedStorage.Shared.Net)
local SomArmas = require(ReplicatedStorage.Shared.SomArmas)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Som = require(script.Parent.Som)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = Hitbox.M

-- soldados em campo (jogadores e bots), sem o próprio
local function soldiers(): { Model }
	local list: { Model } = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and p ~= player then
			table.insert(list, c)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	return list
end

-- ===== 1. acerto visto =====
Bus.on("shot_fired", function(shot: any)
	if type(shot) ~= "table" or type(shot.w) ~= "string" or type(shot.seed) ~= "number" then
		return
	end
	local wp = Weapons.get(shot.w)
	if not wp or wp.kind == "launcher" then
		return
	end
	local origin = Vector3.new(shot.ox, shot.oy, shot.oz)
	local raw = Vector3.new(shot.dx, shot.dy, shot.dz)
	if raw.Magnitude < 1e-3 then
		return
	end
	local dir = raw.Unit -- o servidor recebe e usa dir.Unit
	local char = player.Character
	local skip: { Instance } = {}
	if char then
		table.insert(skip, char)
		-- sentado: o casco do próprio veículo não para a bala (como no servidor)
		local hum = char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		local vehicle = seat and seat:FindFirstAncestorWhichIsA("Model")
		if vehicle and vehicle:GetAttribute("VehicleId") ~= nil then
			table.insert(skip, vehicle)
		end
	end
	local boxes: { Hitbox.Box } = {}
	for _, m in soldiers() do
		table.insert(skip, m)
		local hum = m:FindFirstChildOfClass("Humanoid")
		local root = m:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and root and root:IsA("BasePart") then
			local rel = root.Position - origin
			if Hitbox.nearRay(rel.X, rel.Y, rel.Z, dir.X, dir.Y, dir.Z, wp.muzzleVelocity, 0) then
				Hitbox.fromModel(m, boxes)
			end
		end
	end
	if #boxes == 0 then
		return -- ninguém perto da linha do tiro
	end
	local t = Hitbox.trace(wp.id, origin, dir, shot.seed, wp.maxFlightS, skip, boxes, false)
	local box, hit = t.box, t.hit
	if box and hit then
		Net.event("Combat_Claim"):FireServer({
			s = shot.seed,
			v = box.model,
			p = box.part,
			x = hit.x / M,
			y = hit.y / M,
			z = hit.z / M,
		})
	end
end)

-- ===== 2. marcador =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Acerto"
gui.ResetOnSpawn = false
gui.DisplayOrder = 15 -- acima da retícula da 3ª pessoa (14)
gui.IgnoreGuiInset = true -- centro exato do viewport (onde sai o raio da mira)
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)
gui.Parent = player:WaitForChild("PlayerGui")

local WHITE = Color3.fromRGB(240, 236, 220)
local HEAD = UiKit.BRASS_LIGHT
local KILL = Color3.fromRGB(220, 70, 60)
local MATE = Color3.fromRGB(120, 160, 210)

local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.fromOffset(0, 0)
center.BackgroundTransparency = 1
center.Parent = gui

-- X: quatro traços a 45° em volta do centro
local lines: { Frame } = {}
for _, angle in { 45, 135, 225, 315 } do
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(0, 0)
	holder.BackgroundTransparency = 1
	holder.Rotation = angle
	holder.Parent = center
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 1)
	line.Position = UDim2.fromOffset(0, -6)
	line.Size = UDim2.fromOffset(2, 8)
	line.BorderSizePixel = 0
	line.BackgroundColor3 = WHITE
	line.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 1
	stroke.Parent = line
	line.Parent = holder
	table.insert(lines, line)
end

-- dano: número pequeno ao lado do X
local number = Instance.new("TextLabel")
number.AnchorPoint = Vector2.new(0, 1)
number.Position = UDim2.fromOffset(16, -12)
number.Size = UDim2.fromOffset(80, 22)
number.BackgroundTransparency = 1
number.FontFace = UiKit.HEAD_FONT
number.TextSize = UiKit.text(18)
number.TextXAlignment = Enum.TextXAlignment.Left
number.TextColor3 = WHITE
number.TextStrokeColor3 = Color3.new(0, 0, 0)
number.TextTransparency = 1
number.TextStrokeTransparency = 1
number.Text = ""
number.Parent = center

type Mark = { t: number, color: Color3, size: number, life: number, sum: number, numLife: number }
local mark: Mark = { t = -10, color = WHITE, size = 8, life = 0.25, sum = 0, numLife = 0.6 }
local conn: RBXScriptConnection? = nil
local lastSound = 0

local function render()
	local age = os.clock() - mark.t
	local a = math.clamp(1 - age / mark.life, 0, 1)
	for _, l in lines do
		l.BackgroundTransparency = 1 - a
		l.BackgroundColor3 = mark.color
		l.Size = UDim2.fromOffset(2, mark.size)
		local s = l:FindFirstChildOfClass("UIStroke")
		if s then
			s.Transparency = 1 - a * 0.5
		end
	end
	local n = math.clamp((mark.numLife - age) / 0.25, 0, 1) -- some nos últimos 0,25 s
	number.TextTransparency = 1 - n
	number.TextStrokeTransparency = 1 - n * 0.6
	number.TextColor3 = mark.color
	number.Position = UDim2.fromOffset(16, -12 - math.min(age, mark.numLife) * 18)
	if a <= 0 and n <= 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

Net.event("Combat_Confirm").OnClientEvent:Connect(function(c: any)
	if type(c) ~= "table" then
		return
	end
	local dmg = if type(c.d) == "number" then c.d else 0
	local head = c.zn == Hitbox.ZONE.Head
	local kill = c.k == 1 or c.k == 2
	local now = os.clock()
	-- tiros seguidos (rajada) somam no mesmo número enquanto ele está na tela
	local sum = if now - mark.t < 0.35 then mark.sum + dmg else dmg
	mark.t = now
	mark.sum = sum
	mark.color = if c.f == true then MATE elseif kill then KILL elseif head then HEAD else WHITE
	mark.size = if kill then 12 else 8
	mark.life = if kill then 0.5 else 0.25
	mark.numLife = if kill then 0.85 else 0.6
	number.Text = if kill then string.format("✕ %d", sum) elseif sum > 0 then tostring(sum) else ""
	number.TextSize = UiKit.text(if kill or head then 20 else 17)
	if not conn then
		conn = RunService.RenderStepped:Connect(render)
	end
	render()
	-- som leve, 2D, um por vez na rajada; o baque da bala no corpo, no lugar do alvo
	if now - lastSound > 0.05 then
		lastSound = now
		Som.play(if kill then "acerto_abate" elseif head then "acerto_cabeca" else "acerto_corpo", {})
	end
	local x, y, z = c.x, c.y, c.z
	if type(x) == "number" and type(y) == "number" and type(z) == "number" then
		local carne = SomArmas.CARNE[math.random(1, #SomArmas.CARNE)]
		Som.play(carne, {
			pos = Vector3.new(x, y, z),
			vol = 0.8,
			pitch = 0.9 + math.random() * 0.2,
			minDist = 6 / M,
			maxDist = 80 / M,
		})
	end
end)

-- ===== 3. Studio: caixas de acerto na tela =====
if RunService:IsStudio() then
	local pool: { Part } = {}
	local COLORS = {
		head = Color3.fromRGB(230, 40, 40),
		torso = Color3.fromRGB(240, 140, 30),
		arm = Color3.fromRGB(240, 220, 40),
		leg = Color3.fromRGB(240, 220, 40),
	} :: { [string]: Color3 }
	local function part(i: number): Part
		local found = pool[i]
		if found then
			return found
		end
		local p = Instance.new("Part")
		p.Name = "VT65Caixa"
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		p.Material = Enum.Material.ForceField
		p.Transparency = 0.4
		pool[i] = p
		return p
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			local on = workspace:GetAttribute("VT65DevHitbox") == true
			local n = 0
			if on then
				local eye = camera.CFrame.Position
				for _, m in soldiers() do
					local root = m:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") and (root.Position - eye).Magnitude < 150 / M then
						for _, b in Hitbox.fromModel(m) do
							n += 1
							local p = part(n)
							local r = b.r
							p.Size = Vector3.new(b.hx * 2, b.hy * 2, b.hz * 2)
							p.CFrame = CFrame.new(b.x, b.y, b.z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
							p.Color = COLORS[b.zone] or COLORS.torso
							p.Parent = camera
						end
					end
				end
			end
			for i = n + 1, #pool do
				pool[i].Parent = nil
			end
		end
	end)
end
