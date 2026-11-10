--!strict
-- Tutorial curto por papel (F6, D-47). Um painel discreto mostra um passo por vez. O passo avança
-- quando o jogador faz a ação, em qualquer dispositivo, ou acerta o alvo do campo de tiro. Nada
-- é bloqueado: o jogo segue normal. Pular ou refazer: menu do jogo → Squad e papel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer

-- nomes curtos dos botões (o Roblox nomeia pelo padrão Xbox; o ícone certo aparece ao lado)
local PAD_TEXT: { [string]: string } = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	ButtonL3 = "L3",
	ButtonR3 = "R3",
	ButtonSelect = "View",
	DPadUp = "↑",
	DPadDown = "↓",
	DPadLeft = "←",
	DPadRight = "→",
}
local ACTION: { [string]: InputMap.Action } = {}
for _, a in InputMap.ACTIONS do
	ACTION[a.id] = ACTION[a.id] or a
end

local function glyph(actionId: string): string
	local _, txt = Input.glyph(actionId)
	local pad = Input.isGamepad()
	if pad then
		txt = PAD_TEXT[txt] or txt
	end
	local a = ACTION[actionId]
	local kind = if a then (if pad then a.padPress else a.keyPress) else nil
	return if kind == "hold" then txt .. " (segurar)" else txt
end

-- ===== painel =====
local gui = UiKit.screen("VT65Tutorial", 20)
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -140)
panel.Size = UDim2.fromOffset(if UiKit.tv() then 620 else 460, if UiKit.tv() then 150 else 112)
panel.BackgroundColor3 = UiKit.PAPER
panel.BackgroundTransparency = 0.08
panel.Visible = false
panel.Parent = gui
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.PaddingTop = UDim.new(0, 6)
pad.Parent = panel
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel
local title = UiKit.label(panel, "", 14, if UiKit.tv() then 30 else 20)
title.LayoutOrder = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = UiKit.OLIVE
local row = Instance.new("Frame")
row.LayoutOrder = 2
row.BackgroundTransparency = 1
row.Size = UDim2.new(1, 0, 0, if UiKit.tv() then 100 else 76)
row.Parent = panel
local icon = Instance.new("ImageLabel")
icon.BackgroundTransparency = 1
icon.Size = UDim2.fromOffset(40, 40)
icon.Visible = false
icon.Parent = row
local body = UiKit.label(row, "", 17, if UiKit.tv() then 100 else 76)
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top

-- ===== estado =====
local done: { [string]: boolean } = {}
local role: string? = nil
local steps: { Tutorial.Step } = {}
local index = 0

local function current(): Tutorial.Step?
	return if index >= 1 then steps[index] else nil
end

local function draw()
	local st = current()
	local ctx = Input.context()
	panel.Visible = st ~= nil and ctx ~= "menu" and ctx ~= "map" and ctx ~= "wheel"
	if not st then
		return
	end
	local def = role and Roles.roles[role]
	title.Text = string.format("TUTORIAL — %s (%d/%d)", def and def.name or "", index, #steps)
	body.Text = Tutorial.render(st, glyph)
	-- ícone do botão principal (mostra o símbolo certo de Xbox ou PlayStation)
	local img = if st.action and Input.isGamepad() then select(1, Input.glyph(st.action)) else nil
	icon.Image = img or ""
	icon.Visible = img ~= nil
	body.Position = UDim2.fromOffset(if img then 48 else 0, 0)
	body.Size = UDim2.new(1, if img then -48 else 0, 1, 0)
end

local function finish()
	if role then
		done[role] = true
		Net.event("Tutorial_Done"):FireServer(role)
		Bus.fire("toast", "Tutorial concluído. Refazer: menu do jogo → Squad e papel.")
	end
	index = 0
	draw()
end

local function advance(kind: string, value: any)
	local st = current()
	if st and Tutorial.done(st, kind, value) then
		index += 1
		if index > #steps then
			finish()
		else
			draw()
		end
	end
end

local function begin(r: string?, force: boolean?)
	role = r
	steps = if r then Tutorial.steps(r) else {}
	index = if r and #steps > 0 and (force or not done[r]) then 1 else 0
	draw()
end

-- qualquer fase de ativação conta: toque no controle, aperto no teclado, início do segurar
local seen: { [string]: boolean } = {}
for _, a in InputMap.ACTIONS do
	if not seen[a.id] then
		seen[a.id] = true
		for _, phase in { "press", "tap", "holdStart" } do
			Input.on(a.id, phase, function()
				advance("action", a.id)
			end)
		end
	end
end

Net.event("Range_Hit").OnClientEvent:Connect(function(h)
	if type(h) ~= "table" or type(h.dist) ~= "number" then
		return
	end
	local up, right = tonumber(h.up) or 0, tonumber(h.right) or 0
	Bus.fire(
		"toast",
		string.format(
			"Alvo de %d m: %d cm %s, %d cm %s do centro",
			h.dist,
			math.abs(math.round(up)),
			if up >= 0 then "acima" else "abaixo",
			math.abs(math.round(right)),
			if right >= 0 then "à direita" else "à esquerda"
		)
	)
	advance("range", h.dist)
end)

Bus.on("tutorial_restart", function()
	begin(player:GetAttribute("Role") :: string?, true)
end)
Bus.on("tutorial_skip", function()
	if role and index > 0 then
		finish()
	end
end)
Input.StateChanged:Connect(function()
	draw()
end)
Input.DeviceChanged:Connect(function()
	draw()
end)

-- o tutorial do papel começa ao nascer com um papel que ainda não foi concluído
local function onSpawn()
	local r = player:GetAttribute("Role")
	if type(r) == "string" and r ~= role then
		begin(r)
	elseif type(r) == "string" and index == 0 and not done[r] then
		begin(r)
	end
end
player.CharacterAdded:Connect(function()
	task.defer(onSpawn)
end)
player:GetAttributeChangedSignal("Role"):Connect(function()
	local r = player:GetAttribute("Role")
	if r == nil then
		begin(nil) -- trocou de papel: o novo começa no próximo spawn
	end
end)

task.spawn(function()
	local ok, res = pcall(function()
		return Net.func("Tutorial_Get"):InvokeServer()
	end)
	if ok and type(res) == "table" then
		for k, v in res do
			if type(k) == "string" and v == true then
				done[k] = true
			end
		end
	end
	if player.Character then
		onSpawn()
	end
end)
