--!strict
-- Aviso de saída da área de combate (lê o atributo publicado pelo MapService).
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "BoundaryWarning"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.fromScale(0.5, 0.18)
label.Size = UDim2.fromOffset(520, 64)
label.BackgroundTransparency = 0.35
label.BackgroundColor3 = Color3.fromRGB(20, 18, 14)
label.TextColor3 = Color3.fromRGB(235, 220, 190)
label.Font = Enum.Font.GothamMedium
label.TextScaled = true
label.Parent = gui

local function refresh()
	local left = player:GetAttribute("OOBSecondsLeft")
	gui.Enabled = left ~= nil
	if left ~= nil then
		label.Text = string.format("FORA DA ÁREA DE COMBATE — volte em %d s", left :: number)
	end
end

player:GetAttributeChangedSignal("OOBSecondsLeft"):Connect(refresh)
refresh()
