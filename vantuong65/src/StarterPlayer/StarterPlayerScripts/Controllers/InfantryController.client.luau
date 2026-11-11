--!strict
-- Infantaria no controle (Parte 12.2): correr (L3), agachar/deitar (B tocar/segurar), inclinar
-- (LB/RB mirando), interagir segurando X (caixotes, túneis, construções via ProximityPrompt),
-- marcar (RB tocar), rodas de equipamento (LB segurar) e de comunicação (RB segurar), último item
-- (LB tocar), canal de rádio (direcional → tocar). Mostra marcações e mensagens recebidas do squad.
-- Movimento (fôlego, inércia, pulo, transpor, câmera da postura): Movement.client. Aqui ficam só os
-- pedidos de postura e corrida ao servidor; deitar correndo vira mergulho (Bus "dive").
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comms = require(ReplicatedStorage.Shared.Comms)
local Radio = require(ReplicatedStorage.Shared.Radio)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)
local ViewMode = require(script.Parent.ViewMode)
local Wheel = require(script.Parent.Wheel)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28

local function hum(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

-- ===== postura e corrida =====
local sprinting = false
local function setSprint(on: boolean)
	if on == sprinting then
		return
	end
	if on then
		-- sem fôlego, deitando/levantando, mirando ou transpondo: não começa a correr (Movement.client)
		if player:GetAttribute("Exhausted") == true then
			Bus.fire("toast", "Sem fôlego")
			return
		elseif
			player:GetAttribute("StanceBusy") == true
			or player:GetAttribute("Aiming") == true
			or player:GetAttribute("Vaulting") == true
		then
			return
		end
	end
	sprinting = on
	Input.event("sprint", on)
	Net.event("Posture_Set"):FireServer({ sprint = on })
end
-- o Movement.client para a corrida (sem fôlego, ou parado com a corrida ligada)
Bus.on("sprint_stop", function(reason: string?)
	if sprinting then
		setSprint(false)
		if reason then
			Bus.fire("toast", reason)
		end
	end
end)
-- mirar tira da corrida
Input.on("aim", "press", function()
	setSprint(false)
end)
Input.on("sprint", "press", function()
	if Input.isGamepad() or Input.settings.sprintToggle then
		setSprint(not sprinting) -- L3 alterna (Parte 12.2)
	else
		setSprint(true)
	end
end)
Input.on("sprint", "release", function()
	if not Input.isGamepad() and not Input.settings.sprintToggle then
		setSprint(false)
	end
end)

local function stance(): string
	local c = player.Character
	return if c and c:GetAttribute("Prone")
		then "prone"
		elseif c and c:GetAttribute("Crouched") then "crouch"
		else "stand"
end
Input.on("crouch", "tap", function()
	setSprint(false)
	Net.event("Posture_Set"):FireServer({ stance = if stance() == "crouch" then "stand" else "crouch" })
end)
Input.on("prone", "holdStart", function()
	local wasRunning = sprinting or (player.Character ~= nil and player.Character:GetAttribute("Sprinting") == true)
	setSprint(false)
	local st = stance()
	if st == "stand" and wasRunning then
		Bus.fire("dive") -- correndo: mergulho para o chão (o Movement confere a velocidade)
	end
	Net.event("Posture_Set"):FireServer({ stance = if st == "prone" then "stand" else "prone" })
end)

-- inclinar: só mirando; câmera desloca ~0,35 m para o lado
local function lean(dir: number)
	Input.event("lean", dir)
	Net.event("Posture_Set"):FireServer({ lean = Input.state.lean })
end
Input.on("lean_left", "press", function()
	lean(-1)
end)
Input.on("lean_left", "release", function()
	if Input.state.lean < 0 then
		lean(0)
	end
end)
Input.on("lean_right", "press", function()
	lean(1)
end)
Input.on("lean_right", "release", function()
	if Input.state.lean > 0 then
		lean(0)
	end
end)

-- ===== interagir (X segurado / F): ProximityPrompt do mundo =====
-- Os prompts do jogo têm segurar de 2 a 8 s e usam X no controle (padrão do Roblox): o toque curto
-- de X (recarregar) não completa nenhum. No teclado, a interação fica no F, como no resto do jogo.
ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	player:SetAttribute("PromptShown", true)
end)
ProximityPromptService.PromptHidden:Connect(function()
	player:SetAttribute("PromptShown", false)
end)

-- ===== marcações e mensagens =====
local function aimPoint(): Vector3?
	if ViewMode.third then
		-- 3ª pessoa: o ponto da retícula (o raio não para no que fica entre a câmera e o ombro)
		local cf = camera.CFrame
		local p = ViewMode.aimPoint(1500 / M)
		return if (p - cf.Position).Magnitude < 1499 / M then p else nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local cf = camera.CFrame
	local r = workspace:Raycast(cf.Position, cf.LookVector * (1500 / M), params)
	return r and r.Position
end

local function mark()
	local p = aimPoint()
	if p then
		local kind = if player:GetAttribute("Binoculars") then "target" else "point"
		Net.event("Squad_Mark"):FireServer({ pos = p, kind = kind })
	end
end
Input.on("mark", "tap", mark)

local channel = "squad"
local function switchChannel()
	channel = if channel == "squad" then "command" else "squad"
	player:SetAttribute("RadioChannel", channel)
	Bus.fire("toast", if channel == "squad" then "Rádio: squad" else "Rádio: comando")
end
Input.on("radio_channel", "press", switchChannel) -- tecla U
Input.on("radio_channel", "tap", switchChannel) -- direcional → tocar (segurar: 1ª/3ª pessoa)

local function sendMessage(id: string)
	Net.event("Squad_Message"):FireServer({ id = id, channel = channel })
end

-- feed e marcadores recebidos
local hud = UiKit.screen("VT65Comms", 12)
local feed = Instance.new("Frame")
feed.Position = UDim2.new(0, 16, 1, -300)
feed.Size = UDim2.fromOffset(420, 160)
feed.BackgroundTransparency = 1
feed.Parent = hud
local layout = Instance.new("UIListLayout")
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Parent = feed
local function line(text: string, color: Color3)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, if UiKit.tv() then 30 else 22)
	l.BackgroundTransparency = 0.5
	l.BackgroundColor3 = Color3.new(0, 0, 0)
	l.TextColor3 = color
	l.Font = Enum.Font.GothamMedium
	l.TextSize = UiKit.text(15)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = "  " .. text
	l.Parent = feed
	task.delay(6, function()
		l:Destroy()
	end)
end
Bus.on("toast", function(text: string)
	line(text, Color3.fromRGB(255, 230, 150))
end)
Net.event("Squad_Message").OnClientEvent:Connect(function(m)
	local text = Comms.MESSAGES[m.id] or m.id
	line(
		string.format("[%s] %s: %s", if m.channel == "command" then "CMD" else "SQD", m.from, text),
		Color3.fromRGB(220, 235, 200)
	)
end)
Net.event("Squad_Mark").OnClientEvent:Connect(function(m)
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	a.Transparency = 1
	a.Size = Vector3.one
	a.Position = Vector3.new(m.x, m.y, m.z)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 40)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 4, 0)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextColor3 = if m.kind == "target" then Color3.fromRGB(255, 120, 90) else Color3.fromRGB(255, 220, 90)
	t.TextStrokeTransparency = 0.3
	t.Font = Enum.Font.GothamBold
	t.TextSize = UiKit.text(16)
	t.Text = "▼ " .. tostring(m.from)
	t.Parent = bb
	bb.Parent = a
	a.Parent = workspace
	if m.kind == "target" and type(m.r) == "number" and type(m.ttl) == "number" then
		-- área aproximada no chão, que esmaece até sumir (Comms.markAlpha)
		local disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch = true, false, false, false
		disc.Material = Enum.Material.Neon
		disc.Color = Color3.fromRGB(255, 120, 90)
		disc.Size = Vector3.new(0.3, 2 * m.r / M, 2 * m.r / M)
		disc.CFrame = CFrame.new(m.x, m.y, m.z) * CFrame.Angles(0, 0, math.pi / 2)
		disc.Parent = a
		t.Text = string.format("≈ inimigo (±%d m) — %s", math.floor(m.r + 0.5), tostring(m.from))
		local born = os.clock()
		task.spawn(function()
			while a.Parent do
				local alpha = Comms.markAlpha(os.clock() - born)
				disc.Transparency = 1 - 0.35 * alpha
				t.TextTransparency = 1 - alpha
				if alpha <= 0 then
					break
				end
				task.wait(0.5)
			end
			a:Destroy()
		end)
		line(
			string.format("%s marcou inimigo (área de ±%d m)", m.from, math.floor(m.r + 0.5)),
			Color3.fromRGB(255, 160, 120)
		)
		return
	end
	task.delay(10, function()
		a:Destroy()
	end)
	line(string.format("%s marcou um ponto", m.from), Color3.fromRGB(255, 220, 90))
end)

-- ===== rodas =====
local lastItem: string? = nil
local role = function(): string
	local r = player:GetAttribute("Role")
	return if type(r) == "string" then r else ""
end

local function equipEnabled(id: string): boolean
	if id == "shovel" then
		return true -- cava em setor próprio (o servidor recusa e explica quando não pode)
	elseif id == "frag" then
		return ((player:GetAttribute("Frags") :: number?) or 0) > 0
	elseif id == "smoke" then
		return ((player:GetAttribute("Smokes") :: number?) or 0) > 0
	elseif id == "build" then
		for _, b in Logistics.BUILDS do
			if b.role[role()] then
				return true
			end
		end
		return false
	elseif id == "role_tool" then
		local r = role()
		return r == "commander" or r == "mortar" or r == "anti_tank" or r == "medic" or r == "engineer"
	end
	return true
end

local buildItems: { Comms.Item } = {}
for id, b in Logistics.BUILDS do
	table.insert(buildItems, { id = "build:" .. id, label = string.format("%s (%d)", b.name, b.cost) })
end
table.sort(buildItems, function(a, b)
	return a.id < b.id
end)

local function useItem(id: string)
	lastItem = id
	if id == "shovel" then
		Net.event("Dig_Request"):FireServer()
	elseif id == "frag" or id == "smoke" then
		Net.event("Throw_Request"):FireServer({ kind = id, dir = camera.CFrame.LookVector })
	elseif id == "build" then
		Wheel.open("equip", "Construir", buildItems, function(bid: string)
			local b = Logistics.BUILDS[string.sub(bid, 7)]
			return b ~= nil and b.role[role()] == true
		end)
		return
	elseif string.sub(id, 1, 6) == "build:" then
		Net.event("Build_Request"):FireServer({ kind = string.sub(id, 7) })
	elseif id == "role_tool" then
		local r = role()
		if r == "commander" or r == "mortar" then
			Bus.fire("command_page")
		elseif r == "anti_tank" then
			Bus.fire("toast", "Lançador: troque de arma (Y)")
		elseif r == "medic" or r == "engineer" then
			Bus.fire("toast", "Segure X perto do alvo para agir")
		end
	else
		Bus.fire("equip_item", id) -- bandagem, torniquete, binóculo (Medical/Weapon)
	end
end

local wheelOpen: string? = nil
local function openEquip()
	wheelOpen = "equip"
	Wheel.open("equip", "Equipamento", Comms.EQUIP, equipEnabled)
end
local function commandAllowed(): boolean
	return Radio.canTalkToCommand(role(), player:GetAttribute("Radio") == true)
end
local function openComm()
	wheelOpen = "comm"
	Wheel.open(
		"comm",
		"Comunicação · " .. (if channel == "squad" then "squad" else "comando"),
		Comms.COMM,
		function(id)
			return id ~= "page_command" or commandAllowed()
		end
	)
end
local function confirmWheel()
	local kind = wheelOpen
	wheelOpen = nil
	local id = Wheel.close(true)
	if not id then
		return
	end
	if id == "page_command" then
		wheelOpen = "comm"
		Wheel.open("comm", "Comando", Comms.COMMAND)
		return
	elseif id == "page_squad" then
		openComm()
		return
	end
	if kind == "equip" or string.sub(id, 1, 6) == "build:" then
		useItem(id)
	elseif id == "mark" then
		mark()
	elseif id == "ability" then
		Bus.fire("command_page")
	elseif Comms.CORRECTION[id] then
		Bus.fire("command_correction", Comms.CORRECTION[id])
	elseif Comms.MESSAGES[id] then
		sendMessage(id)
	end
end

-- segurar abre; soltar confirma. Com "alternar rodas", o toque abre e o próximo toque confirma.
Input.on("equip_wheel", "holdStart", openEquip)
Input.on("equip_wheel", "holdEnd", function()
	if not Input.settings.wheelToggle and Wheel.isOpen() then
		confirmWheel()
	end
end)
Input.on("comm_wheel", "holdStart", openComm)
Input.on("comm_wheel", "holdEnd", function()
	if not Input.settings.wheelToggle and Wheel.isOpen() then
		confirmWheel()
	end
end)
Input.on("last_item", "tap", function()
	if Input.settings.wheelToggle then
		if Wheel.isOpen() then
			confirmWheel()
		else
			openEquip()
		end
	elseif lastItem then
		useItem(lastItem)
	end
end)
-- páginas abertas por toque (teclado com "alternar"): o mesmo botão confirma
Bus.on("wheel_confirm", confirmWheel)

-- cancelamentos (menu, mapa, morte, veículo) chegam pela máquina de estados
Input.StateChanged:Connect(function(cancelled: { string })
	if table.find(cancelled, "sprint") then
		sprinting = false
		Net.event("Posture_Set"):FireServer({ sprint = false })
	end
	if table.find(cancelled, "lean") then
		Net.event("Posture_Set"):FireServer({ lean = 0 })
	end
	if table.find(cancelled, "wheel") then
		wheelOpen = nil
	end
end)

-- detecção de túnel (teto baixo cancela corrida e inclinação). A câmera do inclinar e de deitado
-- (CameraOffset) passou para o Movement.client, a cada quadro e com transição suave.
local wasTunnel = false
task.spawn(function()
	while true do
		task.wait(0.1)
		local h = hum()
		if h then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { player.Character :: Model }
				local up = workspace:Raycast(root.Position, Vector3.new(0, 1.0 / M, 0), params) -- galeria de 1,2 m
				local inTunnel = up ~= nil and root.Position.Y < (up.Position.Y - 0.5)
				if inTunnel and not wasTunnel then
					Input.event("tunnel_enter")
				end
				wasTunnel = inTunnel
			end
		end
	end
end)
