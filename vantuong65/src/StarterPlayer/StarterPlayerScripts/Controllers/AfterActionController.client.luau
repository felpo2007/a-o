--!strict
-- Relatório pós-ação (Parte 11): no fim da partida, uma folha datilografada com linha do tempo,
-- baixas e resultado. Abre como menu (controle: rolar com o analógico, B fecha) e some quando a
-- próxima partida começa.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local _player = Players.LocalPlayer
local gui = UiKit.screen("VT65AfterAction", 40)
gui.Enabled = false

local sheet = Instance.new("Frame")
sheet.AnchorPoint = Vector2.new(0.5, 0.5)
sheet.Position = UDim2.fromScale(0.5, 0.5)
sheet.Size = UDim2.fromScale(0.62, 0.82)
sheet.BackgroundColor3 = Color3.fromRGB(232, 224, 200) -- papel
sheet.Parent = gui
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(900, 900)
limit.Parent = sheet

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(18, 14)
scroll.Size = UDim2.new(1, -36, 1, -78)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness = 8
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Selectable = true -- o analógico rola a folha no controle
scroll.SelectionImageObject = UiKit.FOCUS
scroll.Parent = sheet
local text = Instance.new("TextLabel")
text.Size = UDim2.new(1, -10, 0, 0)
text.AutomaticSize = Enum.AutomaticSize.Y
text.BackgroundTransparency = 1
text.TextXAlignment = Enum.TextXAlignment.Left
text.TextYAlignment = Enum.TextYAlignment.Top
text.TextWrapped = true
text.Font = Enum.Font.SpecialElite -- máquina de escrever
text.TextColor3 = Color3.fromRGB(30, 28, 24)
text.TextSize = UiKit.text(17)
text.Parent = scroll

local close: TextButton
local function setOpen(open: boolean)
	if open == gui.Enabled then
		return
	end
	gui.Enabled = open
	if open then
		Input.openMenu()
		UiKit.focus(sheet)
	else
		Input.closeMenu()
	end
end
close = UiKit.button(sheet, "Fechar", function()
	setOpen(false)
end)
close.AnchorPoint = Vector2.new(0.5, 1)
close.Position = UDim2.new(0.5, 0, 1, -12)
close.Size = UDim2.fromOffset(220, if UiKit.tv() then 48 else 36)

Input.on("ui_back", "press", function()
	if gui.Enabled then
		setOpen(false)
	end
end)

local shownFor: string? = nil
Net.event("Match_State").OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then
		return
	end
	if st.ended and type(st.report) == "table" then
		local body = table.concat(st.report, "\n")
		if body ~= shownFor then -- abre uma vez por partida
			shownFor = body
			text.Text = body
			setOpen(true)
		end
	elseif not st.ended then
		shownFor = nil
		setOpen(false)
	end
end)
