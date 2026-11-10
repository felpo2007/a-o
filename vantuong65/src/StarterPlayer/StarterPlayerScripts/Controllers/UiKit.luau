--!strict
-- Interface para TV e controle (Parte 12.5): texto mínimo de 24 px na TV (IsTenFootInterface),
-- nada essencial fora da área segura (ScreenInsets = DeviceSafeInsets), foco sempre visível com
-- moldura de alto contraste e toda tela abrindo com um item focado (GuiService.SelectedObject).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Input = require(script.Parent.Input)

local UiKit = {}
local player = Players.LocalPlayer

UiKit.PAPER = Color3.fromRGB(214, 203, 170)
UiKit.INK = Color3.fromRGB(40, 36, 28)
UiKit.OLIVE = Color3.fromRGB(86, 90, 62)

function UiKit.tv(): boolean
	local ok, v = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and v == true
end

-- tamanho de texto: na TV nunca abaixo de 24 px (1080p)
function UiKit.text(size: number): number
	return if UiKit.tv() then math.max(size, 24) else size
end

function UiKit.screen(name: string, order: number?): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.DisplayOrder = order or 10
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	g.Parent = player:WaitForChild("PlayerGui")
	return g
end

-- moldura de foco de alto contraste (amarelo sobre preto, 4 px)
local focusFrame = Instance.new("Frame")
focusFrame.Name = "VT65Focus"
focusFrame.BackgroundTransparency = 1
focusFrame.Size = UDim2.new(1, 8, 1, 8)
focusFrame.Position = UDim2.fromOffset(-4, -4)
local stroke = Instance.new("UIStroke")
stroke.Thickness = 4
stroke.Color = Color3.fromRGB(255, 214, 0)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = focusFrame
local inner = Instance.new("UIStroke")
inner.Name = "Inner"
inner.Thickness = 1
inner.Color = Color3.new(0, 0, 0)
UiKit.FOCUS = focusFrame

function UiKit.button(parent: Instance, text: string, onClick: () -> (), order: number?): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -8, 0, if UiKit.tv() then 48 else 34)
	b.BackgroundColor3 = Color3.fromRGB(120, 112, 84)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = UiKit.text(16)
	b.TextWrapped = true
	b.Text = text
	b.Selectable = true
	b.SelectionImageObject = focusFrame
	b.LayoutOrder = order or 0
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

function UiKit.label(parent: Instance, text: string, size: number?, height: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -8, 0, height or (if UiKit.tv() then 34 else 26))
	t.BackgroundTransparency = 1
	t.TextColor3 = UiKit.INK
	t.Font = Enum.Font.GothamBold
	t.TextSize = UiKit.text(size or 18)
	t.TextWrapped = true
	t.Text = text
	t.Parent = parent
	return t
end

local function firstSelectable(root: Instance): GuiObject?
	local best: GuiObject? = nil
	local bestKey = math.huge
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.Selectable and d.Visible then
			local p = d.AbsolutePosition
			local key = p.Y * 10000 + p.X
			if key < bestKey then
				best, bestKey = d, key
			end
		end
	end
	return best
end

-- Põe o foco no primeiro item (de cima para baixo) se o jogador estiver no controle.
function UiKit.focus(root: Instance)
	if not Input.isGamepad() then
		return
	end
	task.defer(function()
		local cur = GuiService.SelectedObject
		if cur and cur:IsDescendantOf(root) and cur.Visible then
			return
		end
		local f = firstSelectable(root)
		if f then
			GuiService.SelectedObject = f
		end
	end)
end

-- Vigia: tela visível no controle sem foco nela vira aviso e é corrigida (Parte 12.7).
local watched: { { root: GuiObject, active: () -> boolean, warned: boolean } } = {}
function UiKit.watch(root: GuiObject, active: () -> boolean)
	table.insert(watched, { root = root, active = active, warned = false })
end
task.spawn(function()
	while true do
		task.wait(0.5)
		if Input.isGamepad() and GuiService.GuiNavigationEnabled then
			for _, w in watched do
				if w.active() and w.root.Visible then
					local cur = GuiService.SelectedObject
					if not (cur and cur:IsDescendantOf(w.root)) then
						if not firstSelectable(w.root) then
							if not w.warned then
								w.warned = true
								warn("[VT65] tela sem item focável:", w.root:GetFullName())
							end
						else
							UiKit.focus(w.root)
						end
					end
				end
			end
		end
	end
end)

Input.DeviceChanged:Connect(function(d)
	if d ~= "gamepad" then
		GuiService.SelectedObject = nil
	end
end)

return UiKit
