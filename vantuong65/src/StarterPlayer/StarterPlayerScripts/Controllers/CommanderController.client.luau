--!strict
-- Painel de apoio de fogo (N) e de construção (J) — F4.
-- N: comandante e morteiro pedem fogo por GRADE da carta de 1965 (ex.: "BS 7003 9285") e corrigem
-- como o observador ("mais 100, direita 50"). Sem marcador de inimigo: o alvo sai do mapa de papel.
-- J: construções da logística permitidas ao papel (custo em suprimento).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FireSupport = require(ReplicatedStorage.Shared.FireSupport)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "CommanderPanel"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(420, 360)
frame.Position = UDim2.new(1, -440, 0.5, -180)
frame.BackgroundColor3 = Color3.fromRGB(46, 44, 34)
frame.BackgroundTransparency = 0.1
frame.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = frame
local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10)
pad.Parent = frame

local function text(parent: Instance, t: string, h: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, h)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(235, 228, 200)
	l.Font = Enum.Font.Code
	l.TextSize = 14
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = t
	l.Parent = parent
	return l
end

local function box(placeholder: string): TextBox
	local b = Instance.new("TextBox")
	b.Size = UDim2.new(1, 0, 0, 28)
	b.BackgroundColor3 = Color3.fromRGB(220, 212, 180)
	b.TextColor3 = Color3.fromRGB(20, 20, 16)
	b.Font = Enum.Font.Code
	b.TextSize = 15
	b.PlaceholderText = placeholder
	b.Text = ""
	b.ClearTextOnFocus = false
	b.Parent = frame
	return b
end

local title = text(frame, "APOIO DE FOGO", 20)
local myGrid = text(frame, "", 18)
local gridBox = box("grade do alvo, ex.: BS 7003 9285")
local corrBox = box("correção: mais 100, direita 50")
local confirm = Instance.new("TextButton")
confirm.Size = UDim2.new(1, 0, 0, 24)
confirm.Text = "[ ] confirmar perigo próximo"
confirm.Font = Enum.Font.Code
confirm.TextSize = 14
confirm.BackgroundColor3 = Color3.fromRGB(90, 70, 50)
confirm.TextColor3 = Color3.fromRGB(240, 230, 200)
confirm.Parent = frame
local confirmed = false
confirm.Activated:Connect(function()
	confirmed = not confirmed
	confirm.Text = (if confirmed then "[X]" else "[ ]") .. " confirmar perigo próximo"
end)
local buttons = Instance.new("Frame")
buttons.Size = UDim2.new(1, 0, 0, 120)
buttons.BackgroundTransparency = 1
buttons.Parent = frame
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -4, 0, 34)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.Parent = buttons
local status = text(frame, "", 60)

local mode = "fire" -- "fire" | "build"
local state: { [string]: any } = { readyAt = {}, now = 0, at = 0 }

local function rebuild()
	for _, c in buttons:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local faction = player:GetAttribute("Faction")
	local role = player:GetAttribute("Role")
	if mode == "fire" then
		title.Text = "APOIO DE FOGO — suprimento " .. tostring(player:GetAttribute("Supply") or 0)
		for id, a in FireSupport.ABILITIES do
			if a.faction == faction and a.who == role then
				local b = Instance.new("TextButton")
				b.Text = a.name
				b.Font = Enum.Font.Code
				b.TextSize = 13
				b.TextWrapped = true
				b.BackgroundColor3 = Color3.fromRGB(70, 74, 52)
				b.TextColor3 = Color3.fromRGB(240, 236, 210)
				b.Parent = buttons
				b.Activated:Connect(function()
					Net.event("Commander_Request"):FireServer({
						ability = id,
						grid = gridBox.Text,
						correction = corrBox.Text,
						confirm = confirmed,
					})
					corrBox.Text = ""
					confirmed = false
					confirm.Text = "[ ] confirmar perigo próximo"
				end)
			end
		end
	else
		title.Text = "CONSTRUIR — suprimento " .. tostring(player:GetAttribute("Supply") or 0)
		for id, b in Logistics.BUILDS do
			if role and b.role[role :: string] then
				local btn = Instance.new("TextButton")
				btn.Text = string.format("%s (%d)", b.name, b.cost)
				btn.Font = Enum.Font.Code
				btn.TextSize = 13
				btn.TextWrapped = true
				btn.BackgroundColor3 = Color3.fromRGB(70, 74, 52)
				btn.TextColor3 = Color3.fromRGB(240, 236, 210)
				btn.Parent = buttons
				btn.Activated:Connect(function()
					Net.event("Build_Request"):FireServer({ kind = id })
				end)
			end
		end
	end
	local visibleFire = mode == "fire"
	gridBox.Visible, corrBox.Visible, confirm.Visible = visibleFire, visibleFire, visibleFire
end

local function updateStatus()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		myGrid.Text = "sua posição: "
			.. FireSupport.localToGrid(root.Position.X, root.Position.Z, MapConfig.GridOrigin1965, MapConfig.STUD_M, 8)
	end
end

Net.event("Commander_State").OnClientEvent:Connect(function(msg)
	if msg.readyAt then
		state.readyAt, state.now, state.at = msg.readyAt, msg.now, os.clock()
	end
	if msg.error then
		status.Text = "✗ " .. msg.error
	elseif msg.warning then
		status.Text = "! " .. msg.warning
	elseif msg.info then
		status.Text = "✓ " .. msg.info
	end
	if gui.Enabled then
		rebuild()
	end
end)
Net.event("Logistics_State").OnClientEvent:Connect(function(msg)
	if msg.error then
		status.Text = "✗ " .. msg.error
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.N or k == Enum.KeyCode.J then
		local m = if k == Enum.KeyCode.N then "fire" else "build"
		if gui.Enabled and mode == m then
			gui.Enabled = false
		else
			mode = m
			gui.Enabled = true
			rebuild()
			updateStatus()
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled then
			updateStatus()
		end
	end
end)
