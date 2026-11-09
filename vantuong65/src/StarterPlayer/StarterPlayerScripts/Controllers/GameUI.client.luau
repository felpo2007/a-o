--!strict
-- Menus da F2 (placeholder visual): facção -> squad -> papel -> mapa de spawn; tecla M abre o
-- mapa tático (setores e pontos fortes; nunca mostra inimigos — Parte 9.5).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Menus"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local PAPER = Color3.fromRGB(214, 203, 170) -- papel de carta de 1965
local INK = Color3.fromRGB(40, 36, 28)

local function frame(parent: Instance, size: UDim2, pos: UDim2): Frame
	local f = Instance.new("Frame")
	f.Size, f.Position = size, pos
	f.BackgroundColor3 = PAPER
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function button(parent: Instance, text: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -8, 0, 32)
	b.BackgroundColor3 = Color3.fromRGB(120, 112, 84)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 16
	b.Text = text
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local function list(parent: Instance): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function title(parent: Instance, text: string)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -8, 0, 28)
	t.BackgroundTransparency = 1
	t.TextColor3 = INK
	t.Font = Enum.Font.GothamBold
	t.TextSize = 18
	t.Text = text
	t.Parent = parent
end

-- painel lateral (facção / squad / papel / spawn)
local side = frame(gui, UDim2.fromOffset(330, 520), UDim2.fromOffset(16, 80))
list(side)

-- mapa tático: retângulo da área com proporção 4,0 x 2,4
local mapFrame = frame(gui, UDim2.fromOffset(700, 420), UDim2.new(0, 360, 0, 80))
mapFrame.Visible = false
local B = MapConfig.Bounds
local function toMap(x: number, z: number): UDim2
	return UDim2.fromScale((x - B.minX) / (B.maxX - B.minX), (z - B.minZ) / (B.maxZ - B.minZ))
end

local squadState: any = nil
local spawnList: { any } = {}
local matchState: any = nil

local function alive(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function drawMap()
	clear(mapFrame)
	if not matchState then
		return
	end
	for _, s in MapConfig.Sectors do
		local xs = {}
		for i = 1, #s.polygon, 2 do
			table.insert(xs, s.polygon[i])
		end
		local x0, x1 = math.min(table.unpack(xs)), math.max(table.unpack(xs))
		local band = Instance.new("Frame")
		band.Position = toMap(x0, B.minZ)
		band.Size = UDim2.fromScale((x1 - x0) / (B.maxX - B.minX), 1)
		local owner = matchState.owner[s.id]
		band.BackgroundColor3 = if owner == "US"
			then Color3.fromRGB(110, 120, 150)
			elseif owner == "VC" then Color3.fromRGB(150, 110, 100)
			else Color3.fromRGB(170, 165, 140)
		band.BackgroundTransparency = if matchState.active[s.id] then 0.5 else 0.85
		band.BorderSizePixel = 1
		band.Parent = mapFrame
	end
	for _, sp in matchState.points do
		local d = Instance.new("TextLabel")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = toMap(sp.x, sp.z)
		d.Size = UDim2.fromOffset(120, 18)
		d.BackgroundTransparency = 1
		d.TextColor3 = INK
		d.Font = Enum.Font.Code
		d.TextSize = 13
		d.Text = "◎ " .. sp.name
		d.Parent = mapFrame
	end
	if not alive() then
		for _, pt in spawnList do
			local b = Instance.new("TextButton")
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = toMap(pt.x, pt.z)
			b.Size = UDim2.fromOffset(130, 34)
			b.BackgroundColor3 = if pt.blocked then Color3.fromRGB(120, 60, 50) else Color3.fromRGB(60, 80, 50)
			b.TextColor3 = Color3.new(1, 1, 1)
			b.TextSize = 12
			b.Font = Enum.Font.GothamMedium
			b.Text = pt.name
				.. "\n"
				.. (
					if pt.blocked
						then (pt.why or "bloqueado")
						elseif pt.wait > 0 then string.format("%d s", pt.wait)
						else "PRONTO"
				)
			b.Parent = mapFrame
			b.Activated:Connect(function()
				Net.event("Spawn_Request"):FireServer(pt.id)
			end)
		end
	end
	local t = matchState.timeLeft or 0
	title(mapFrame, string.format("%s — %02d:%02d", matchState.mode, t // 60, t % 60))
end

local function drawSide()
	clear(side)
	local faction = player:GetAttribute("Faction")
	if not faction then
		title(side, "Escolha o lado")
		button(side, "Fuzileiros dos EUA (USMC)", function()
			Net.event("Team_Choose"):FireServer("US")
		end)
		button(side, "1º Regimento (Viet Cong)", function()
			Net.event("Team_Choose"):FireServer("VC")
		end)
		return
	end
	if not player:GetAttribute("SquadId") then
		title(side, "Squads")
		if squadState then
			for _, s in squadState.squads do
				local size = Roles.units[faction][s.unit].size
				button(side, string.format("Entrar: %s (%d/%d)", s.name, #s.members, size), function()
					Net.event("Squad_Action"):FireServer({ op = "join", id = s.id })
				end)
			end
			for unit, def in Roles.units[faction] do
				local ok = not def.heavy or (squadState.size or 0) >= Roles.HEAVY_UNLOCK
				if ok then
					button(side, "Criar: " .. unit, function()
						Net.event("Squad_Action"):FireServer({ op = "create", unit = unit })
					end)
				end
			end
		end
		return
	end
	if not player:GetAttribute("Role") then
		title(side, "Papel")
		local mySquad: any = nil
		if squadState then
			for _, s in squadState.squads do
				if s.id == player:GetAttribute("SquadId") then
					mySquad = s
				end
			end
		end
		if mySquad then
			for id, r in Roles.roles do
				if r.unit == mySquad.unit and Roles.loadout[faction][id] then
					button(side, r.name .. " — " .. table.concat(Roles.loadout[faction][id], ", "), function()
						Net.event("Role_Choose"):FireServer(id)
					end)
				end
			end
		end
		button(side, "Sair do squad", function()
			Net.event("Squad_Action"):FireServer({ op = "leave" })
		end)
		return
	end
	if not alive() then
		title(side, "Escolha onde renascer no mapa")
		button(side, "Trocar de papel (+15 s)", function()
			player:SetAttribute("Role", nil) -- só o menu; o servidor confirma ao escolher
			drawSide()
		end)
	end
end

local function refresh()
	local dead = not alive()
	side.Visible = dead or not player:GetAttribute("Role")
	mapFrame.Visible = (dead and player:GetAttribute("Role") ~= nil) or mapFrame:GetAttribute("Pinned") == true
	drawSide()
	if mapFrame.Visible then
		drawMap()
	end
end

Net.event("Squad_State").OnClientEvent:Connect(function(st)
	squadState = st
	refresh()
end)
Net.event("Spawn_State").OnClientEvent:Connect(function(st)
	spawnList = st
	if mapFrame.Visible then
		drawMap()
	end
end)
Net.event("Match_State").OnClientEvent:Connect(function(st)
	matchState = st
	if mapFrame.Visible then
		drawMap()
	end
end)
for _, a in { "Faction", "SquadId", "Role" } do
	player:GetAttributeChangedSignal(a):Connect(refresh)
end
player.CharacterAdded:Connect(function(char)
	refresh()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Died:Connect(refresh)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.M then
		mapFrame:SetAttribute("Pinned", not mapFrame:GetAttribute("Pinned"))
		refresh()
	end
end)
refresh()
