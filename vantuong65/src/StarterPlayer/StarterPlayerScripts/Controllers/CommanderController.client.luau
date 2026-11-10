--!strict
-- Apoio de fogo e construção (F4 + Parte 12.5). Nada exige digitar:
--   Comandante/morteiro: roda de comunicação → "Comando" → "Pedir fogo / apoio" (ou tecla N) abre
--   este painel; escolher a habilidade abre o mapa no modo ALVO (cursor com ímã, A confirma).
--   Correções do observador vêm da roda ("Mais 100", "Direita 50"...) e o "perigo próximo" é
--   confirmado num botão. No teclado, a grade digitada ("BS 7003 9285") continua opcional.
--   Construir: roda de equipamento → "Construir" (ou tecla J).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FireSupport = require(ReplicatedStorage.Shared.FireSupport)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local gui = UiKit.screen("CommanderPanel", 32)
gui.Enabled = false

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(if UiKit.tv() then 540 else 440, if UiKit.tv() then 520 else 420)
frame.Position = UDim2.new(1, if UiKit.tv() then -560 else -460, 0.5, -210)
frame.BackgroundColor3 = Color3.fromRGB(46, 44, 34)
frame.BackgroundTransparency = 0.1
frame.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = frame
local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10)
pad.Parent = frame

local function text(t: string, h: number, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, h)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(235, 228, 200)
	l.Font = Enum.Font.Code
	l.TextSize = UiKit.text(14)
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = t
	l.LayoutOrder = order
	l.Parent = frame
	return l
end

local title = text("", 22, 1)
local myGrid = text("", 20, 2)
local gridBox = Instance.new("TextBox")
gridBox.Size = UDim2.new(1, 0, 0, 28)
gridBox.BackgroundColor3 = Color3.fromRGB(220, 212, 180)
gridBox.TextColor3 = Color3.fromRGB(20, 20, 16)
gridBox.Font = Enum.Font.Code
gridBox.TextSize = UiKit.text(15)
gridBox.PlaceholderText = "opcional (teclado): grade, ex. BS 7003 9285"
gridBox.Text = ""
gridBox.ClearTextOnFocus = false
gridBox.Selectable = false
gridBox.LayoutOrder = 3
gridBox.Parent = frame
local buttons = Instance.new("Frame")
buttons.Size = UDim2.new(1, 0, 0, 220)
buttons.BackgroundTransparency = 1
buttons.LayoutOrder = 4
buttons.Parent = frame
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -4, 0, if UiKit.tv() then 50 else 38)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = buttons
local status = text("", 60, 5)

local mode = "fire" -- "fire" | "build" | "confirm"
local lastAbility: string? = nil
local lastReq: { [string]: any }? = nil

local function send(req: { [string]: any })
	lastAbility = req.ability
	lastReq = req
	Net.event("Commander_Request"):FireServer(req)
end

local function close()
	if gui.Enabled then
		gui.Enabled = false
		Input.closeMenu()
	end
end

local rebuild: () -> ()
local function open(m: string)
	mode = m
	if not gui.Enabled then
		gui.Enabled = true
		Input.openMenu()
	end
	rebuild()
	UiKit.focus(buttons)
end

local function addButton(label: string, order: number, onClick: () -> ())
	local b = UiKit.button(buttons, label, onClick, order)
	b.BackgroundColor3 = Color3.fromRGB(70, 74, 52)
	b.TextSize = UiKit.text(13)
end

rebuild = function()
	for _, c in buttons:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local faction = player:GetAttribute("Faction")
	local role = player:GetAttribute("Role")
	gridBox.Visible = mode == "fire" and not Input.isGamepad()
	if mode == "fire" then
		title.Text = "APOIO DE FOGO — suprimento " .. tostring(player:GetAttribute("Supply") or 0)
		local n = 0
		for id, a in FireSupport.ABILITIES do
			if a.faction == faction and a.who == role then
				n += 1
				addButton(a.name, n, function()
					if gridBox.Visible and #gridBox.Text > 0 then
						send({ ability = id, grid = gridBox.Text })
						return
					end
					close()
					Bus.fire("map_target", id, a.name) -- alvo no mapa, sem digitar
				end)
			end
		end
		if n == 0 then
			status.Text = "Seu papel não pede fogo (comandante ou morteiro)."
		end
	elseif mode == "build" then
		title.Text = "CONSTRUIR — suprimento " .. tostring(player:GetAttribute("Supply") or 0)
		local n = 0
		for id, b in Logistics.BUILDS do
			if role and b.role[role :: string] then
				n += 1
				addButton(string.format("%s (%d)", b.name, b.cost), n, function()
					Net.event("Build_Request"):FireServer({ kind = id })
				end)
			end
		end
	elseif mode == "confirm" then
		title.Text = "PERIGO PRÓXIMO"
		addButton("Confirmar e repetir o pedido", 1, function()
			if lastReq then
				local req = table.clone(lastReq)
				req.confirm = true
				send(req)
			end
			close()
		end)
		addButton("Cancelar", 2, close)
	end
end

local function updateStatus()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		myGrid.Text = "sua posição: "
			.. FireSupport.localToGrid(root.Position.X, root.Position.Z, MapConfig.GridOrigin1965, MapConfig.STUD_M, 8)
	end
end

-- alvo escolhido no mapa (GameUI)
Bus.on("target_chosen", function(ability: string?, x: number, z: number)
	if ability then
		send({ ability = ability, x = x, z = z })
	end
end)
-- correções e atalhos vindos das rodas
Bus.on("command_correction", function(corr: string)
	if lastAbility then
		send({ ability = lastAbility, correction = corr })
	else
		Bus.fire("toast", "Nenhuma missão para corrigir")
	end
end)
Bus.on("command_page", function()
	open("fire")
	updateStatus()
end)

Net.event("Commander_State").OnClientEvent:Connect(function(msg)
	if msg.error then
		status.Text = "✗ " .. msg.error
		Bus.fire("toast", "✗ " .. msg.error)
	elseif msg.warning then
		status.Text = "! " .. msg.warning
		open("confirm") -- confirmação por botão, foco no "Confirmar"
	elseif msg.info then
		status.Text = "✓ " .. msg.info
		Bus.fire("toast", "✓ " .. msg.info)
	end
	if gui.Enabled and mode ~= "confirm" then
		rebuild()
	end
end)
Net.event("Logistics_State").OnClientEvent:Connect(function(msg)
	if msg.error then
		status.Text = "✗ " .. msg.error
		Bus.fire("toast", "✗ " .. msg.error)
	end
end)

Input.on("ui_back", "press", close)
UiKit.watch(buttons, function()
	return gui.Enabled
end)

-- atalhos de teclado (N fogo, J construir)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.N or k == Enum.KeyCode.J then
		local m = if k == Enum.KeyCode.N then "fire" else "build"
		if gui.Enabled and mode == m then
			close()
		else
			open(m)
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
