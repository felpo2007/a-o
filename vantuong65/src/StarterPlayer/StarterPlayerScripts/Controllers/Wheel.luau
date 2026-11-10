--!strict
-- Roda radial (Parte 12.5): seleção pelo analógico direito com zona morta de 40% (ou pelo mouse /
-- teclas 1–8); soltar o botão que abriu confirma; B cancela. Itens em posições fixas.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(game:GetService("ReplicatedStorage").Shared.InputMap)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local Wheel = {}

export type Item = { id: string, label: string }

local gui = UiKit.screen("VT65Wheel", 40)
gui.Enabled = false
local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.fromOffset(440, 440)
center.BackgroundTransparency = 1
center.Parent = gui
local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromOffset(180, 60)
title.BackgroundColor3 = Color3.fromRGB(30, 30, 24)
title.BackgroundTransparency = 0.25
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextWrapped = true
title.Parent = center

local slots: { TextLabel } = {}
for i = 1, 8 do
	local a = (i - 1) * math.pi / 4
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.new(0.5, math.sin(a) * 165, 0.5, -math.cos(a) * 165)
	l.Size = UDim2.fromOffset(130, 58)
	l.BackgroundColor3 = Color3.fromRGB(46, 44, 34)
	l.BackgroundTransparency = 0.2
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamMedium
	l.TextWrapped = true
	local s = Instance.new("UIStroke")
	s.Thickness = 0
	s.Color = Color3.fromRGB(255, 214, 0)
	s.Parent = l
	l.Parent = center
	slots[i] = l
end

local items: { Item } = {}
local enabledFn: (string) -> boolean = function()
	return true
end
local selected: number? = nil
local cursor = Vector2.zero -- teclado/mouse: deslocamento acumulado do mouse

local function render()
	title.TextSize = UiKit.text(18)
	for i, l in slots do
		local it = items[i]
		l.Visible = it ~= nil
		if it then
			local on = enabledFn(it.id)
			l.Text = string.format("%d  %s", i, it.label)
			l.TextSize = UiKit.text(15)
			l.TextTransparency = if on then 0 else 0.6
			local stroke = l:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Thickness = if selected == i then 4 else 0
			l.BackgroundColor3 = if selected == i then Color3.fromRGB(110, 100, 60) else Color3.fromRGB(46, 44, 34)
		end
	end
end

function Wheel.isOpen(): boolean
	return gui.Enabled
end

function Wheel.open(name: string, label: string, list: { Item }, enabled: ((string) -> boolean)?)
	items = list
	enabledFn = enabled or function()
		return true
	end
	selected, cursor = nil, Vector2.zero
	title.Text = label
	gui.Enabled = true
	Input.event("wheel_open", name)
	render()
end

-- troca de página sem fechar (ex.: "Comando ▸")
function Wheel.page(label: string, list: { Item }, enabled: ((string) -> boolean)?)
	items = list
	if enabled then
		enabledFn = enabled
	end
	selected, cursor = nil, Vector2.zero
	title.Text = label
	render()
end

-- Fecha; devolve o id escolhido (ou nil se cancelou / item apagado).
function Wheel.close(confirm: boolean): string?
	if not gui.Enabled then
		return nil
	end
	gui.Enabled = false
	Input.event("wheel_close")
	local it = selected and items[selected]
	if confirm and it and enabledFn(it.id) then
		return it.id
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	local idx: number?
	if Input.isGamepad() then
		local r = Input.stickRaw("right")
		idx = InputMap.wheelIndex(r.X, r.Y, #items)
	else
		local d = UserInputService:GetMouseDelta()
		cursor = cursor + Vector2.new(d.X, -d.Y)
		if cursor.Magnitude > 120 then
			cursor = cursor.Unit * 120
		end
		idx = InputMap.wheelIndex(cursor.X / 120, cursor.Y / 120, #items)
	end
	if idx then
		selected = idx
	end
	render()
end)

-- teclas 1–8 escolhem direto no teclado
UserInputService.InputBegan:Connect(function(input)
	if not gui.Enabled or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local n = ({
		One = 1,
		Two = 2,
		Three = 3,
		Four = 4,
		Five = 5,
		Six = 6,
		Seven = 7,
		Eight = 8,
	} :: { [string]: number })[input.KeyCode.Name]
	if n and items[n] then
		selected = n
		render()
	end
end)

Input.on("wheel_cancel", "press", function()
	Wheel.close(false)
end)
Input.StateChanged:Connect(function(cancelled: { string })
	if table.find(cancelled, "wheel") and gui.Enabled then
		gui.Enabled = false -- menu/mapa/morte cancelaram a roda
	end
end)

return Wheel
