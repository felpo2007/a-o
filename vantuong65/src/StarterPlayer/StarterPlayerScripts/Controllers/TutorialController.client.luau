--!strict
-- Tutorial curto por papel (F6, D-47). Um painel discreto mostra um passo por vez. O passo avança
-- quando o jogador faz a ação, em qualquer dispositivo, ou acerta o alvo do campo de tiro. Nada
-- é bloqueado: o jogo segue normal. Pular ou refazer: menu do jogo → Squad e papel.
-- Painel (2026-11-11): cartão compacto embaixo à esquerda, longe da mira, no visual dos avisos
-- (Toast): tarja "TUTORIAL · papel" com o passo (1/9) e uma pauta de progresso; o botão da ação
-- fica num chip de papel à esquerda e em latão no texto. Na troca de passo o conteúdo sai e entra
-- deslizando. No veículo, o painel vai para a direita do painel do veículo (VehicleController).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
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

-- botão da ação no dispositivo do jogador: (imagem do controle, texto curto, pede segurar?)
local function keyOf(actionId: string): (string?, string, boolean)
	local img, txt = Input.glyph(actionId)
	local pad = Input.isGamepad()
	if pad then
		txt = PAD_TEXT[txt] or txt
	end
	local a = ACTION[actionId]
	local kind = if a then (if pad then a.padPress else a.keyPress) else nil
	return img, txt, kind == "hold"
end

local function glyph(actionId: string): string
	local _, txt, hold = keyOf(actionId)
	return if hold then txt .. " (segurar)" else txt
end

-- ===== painel =====
local TV = UiKit.tv()
local W = if TV then 560 else 380
local PAD = if TV then 14 else 10
local HEAD_H = if TV then 36 else 24 -- tarja
local HEAD_SIZE = if TV then 26 else 16
local COUNT_W = if TV then 72 else 44
local PIP_H = if TV then 4 else 3 -- pauta de progresso
local CHIP_W = if TV then 96 else 60 -- chip do botão
local CHIP_H = if TV then 76 else 46
local ICON = if TV then 44 else 28
local SUB_H = if TV then 26 else 14 -- "SEGURAR" no pé do chip
local MARGIN = if TV then 32 else 16
local VEHICLE_X = 16 + 360 + 12 -- à direita do painel do veículo (VehicleController, 360 px)
local BODY_SIZE = UiKit.text(16)
local BODY_X = PAD + CHIP_W + PAD
local BODY_W = W - BODY_X - PAD
local CONTENT_Y = 4 + HEAD_H + 6 + PIP_H + PAD
local MAX_STEPS = 12 -- teste da F6: cada papel tem de 3 a 12 passos
local HOT = UiKit.BRASS -- o botão em destaque
local HOT_HEX = HOT:ToHex()
local LIGHT = UiKit.CARD

local function corner(o: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

local function text(parent: Instance, name: string): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Parent = parent
	return t
end

local gui = UiKit.screen("VT65Tutorial", 20)
local root = Instance.new("Frame")
root.Name = "Tutorial"
root.AnchorPoint = Vector2.new(0, 1)
root.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
root.Size = UDim2.fromOffset(W, CONTENT_Y + CHIP_H + PAD)
root.BackgroundTransparency = 1
root.Visible = false
root.Parent = gui
local shadow = Instance.new("Frame") -- sombra leve
shadow.BackgroundColor3 = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 0.55
shadow.BorderSizePixel = 0
shadow.Position = UDim2.fromOffset(2, 3)
shadow.Size = UDim2.fromScale(1, 1)
corner(shadow, 5)
shadow.Parent = root
local panel = Instance.new("Frame")
panel.Name = "Cartao"
panel.BackgroundColor3 = Color3.fromRGB(26, 28, 21)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Size = UDim2.fromScale(1, 1)
corner(panel, 4)
local edge = Instance.new("UIStroke")
edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
edge.Color = UiKit.KHAKI
edge.Transparency = 0.72
edge.Parent = panel
local light = Instance.new("UIGradient") -- luz de cima
light.Rotation = 90
light.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 160))
light.Parent = panel
panel.Parent = root

-- tarja: "TUTORIAL · papel" e o passo
local head = Instance.new("Frame")
head.Name = "Tarja"
head.BackgroundColor3 = UiKit.DRAB
head.BorderSizePixel = 0
head.Position = UDim2.fromOffset(4, 4)
head.Size = UDim2.new(1, -8, 0, HEAD_H)
corner(head, 3)
head.Parent = panel
local title = text(head, "Titulo")
title.Position = UDim2.fromOffset(PAD - 4, 0)
title.Size = UDim2.new(1, -(2 * (PAD - 4) + COUNT_W), 1, 0)
title.FontFace = UiKit.HEAD_FONT
title.TextSize = HEAD_SIZE
title.TextColor3 = UiKit.KHAKI
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextTruncate = Enum.TextTruncate.AtEnd
title.RichText = true
local count = text(head, "Passo")
count.AnchorPoint = Vector2.new(1, 0)
count.Position = UDim2.new(1, -(PAD - 4), 0, 0)
count.Size = UDim2.new(0, COUNT_W, 1, 0)
count.FontFace = UiKit.HEAD_FONT
count.TextSize = HEAD_SIZE
count.TextColor3 = HOT
count.TextXAlignment = Enum.TextXAlignment.Right

-- pauta de progresso: feito em latão, o atual claro, o resto apagado
local pips = Instance.new("Frame")
pips.Name = "Pauta"
pips.BackgroundTransparency = 1
pips.Position = UDim2.fromOffset(PAD, 4 + HEAD_H + 6)
pips.Size = UDim2.new(1, -2 * PAD, 0, PIP_H)
pips.Parent = panel
local pipLayout = Instance.new("UIListLayout")
pipLayout.FillDirection = Enum.FillDirection.Horizontal
pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
pipLayout.Padding = UDim.new(0, 3)
pipLayout.Parent = pips
local pipList: { Frame } = {}
for i = 1, MAX_STEPS do
	local p = Instance.new("Frame")
	p.BorderSizePixel = 0
	p.LayoutOrder = i
	p.Visible = false
	p.Parent = pips
	pipList[i] = p
end

-- conteúdo do passo (sai e entra deslizando na troca): chip do botão e o texto
local content = Instance.new("Frame")
content.Name = "Passo"
content.BackgroundTransparency = 1
content.Position = UDim2.fromOffset(0, CONTENT_Y)
content.Size = UDim2.new(1, 0, 0, CHIP_H)
content.Parent = panel
local chip = Instance.new("Frame")
chip.Name = "Botao"
chip.BackgroundColor3 = UiKit.CARD
chip.BorderSizePixel = 0
chip.Position = UDim2.fromOffset(PAD, 0)
chip.Size = UDim2.fromOffset(CHIP_W, CHIP_H)
corner(chip, 4)
local chipEdge = Instance.new("UIStroke")
chipEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
chipEdge.Color = UiKit.INK
chipEdge.Transparency = 0.4
chipEdge.Parent = chip
local paper = Instance.new("UIGradient") -- papel com luz de cima
paper.Rotation = 90
paper.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(212, 206, 192))
paper.Parent = chip
chip.Parent = content
-- ícone do botão no controle (o símbolo certo de Xbox ou PlayStation)
local chipIcon = Instance.new("ImageLabel")
chipIcon.AnchorPoint = Vector2.new(0.5, 0.5)
chipIcon.BackgroundTransparency = 1
chipIcon.Size = UDim2.fromOffset(ICON, ICON)
chipIcon.Visible = false
chipIcon.Parent = chip
local chipKey = text(chip, "Tecla")
chipKey.Position = UDim2.fromOffset(4, 4)
chipKey.FontFace = UiKit.HEAD_FONT
chipKey.TextColor3 = UiKit.INK
chipKey.TextScaled = true
local keyMax = Instance.new("UITextSizeConstraint")
keyMax.MaxTextSize = if TV then 36 else 24
keyMax.Parent = chipKey
local chipSub = text(chip, "Segurar")
chipSub.AnchorPoint = Vector2.new(0, 1)
chipSub.Position = UDim2.new(0, 2, 1, -2)
chipSub.Size = UDim2.new(1, -4, 0, SUB_H)
chipSub.FontFace = UiKit.HEAD_FONT
chipSub.TextSize = if TV then 24 else 12
chipSub.TextColor3 = UiKit.STAMP
local body = text(content, "Texto")
body.Position = UDim2.fromOffset(BODY_X, 0)
body.Size = UDim2.fromOffset(BODY_W, CHIP_H)
body.Font = UiKit.BODY_FONT
body.TextSize = BODY_SIZE
body.TextColor3 = LIGHT
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Center
body.TextWrapped = true
body.RichText = true

-- o que esmaece na troca de passo, com a transparência de projeto
local fadeItems: { { inst: Instance, prop: string, base: number } } = {
	{ inst = chip, prop = "BackgroundTransparency", base = 0 },
	{ inst = chipEdge, prop = "Transparency", base = 0.4 },
	{ inst = chipIcon, prop = "ImageTransparency", base = 0 },
	{ inst = chipKey, prop = "TextTransparency", base = 0 },
	{ inst = chipSub, prop = "TextTransparency", base = 0 },
	{ inst = body, prop = "TextTransparency", base = 0 },
}

-- ===== estado =====
local done: { [string]: boolean } = {}
local role: string? = nil
local steps: { Tutorial.Step } = {}
local index = 0

local function current(): Tutorial.Step?
	return if index >= 1 then steps[index] else nil
end

local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- no texto, o botão sai em latão e negrito (o texto do passo é o mesmo do Tutorial.render)
local function hotGlyph(actionId: string): string
	return string.format('<font color="#%s"><b>%s</b></font>', HOT_HEX, esc(glyph(actionId)))
end

-- Preenche o painel com o passo atual e devolve a altura dele.
local function apply(st: Tutorial.Step): number
	local def = role and Roles.roles[role]
	local name = tostring(def and def.name or "")
	title.Text = string.format('<font color="#%s">TUTORIAL</font>  ·  %s', HOT_HEX, esc(name))
	title.FontFace = UiKit.headFont(name)
	count.Text = string.format("%d/%d", index, #steps)
	local n = math.min(#steps, MAX_STEPS)
	for i, p in pipList do
		p.Visible = i <= n
		p.Size = UDim2.new(1 / math.max(n, 1), -3, 1, 0)
		p.BackgroundColor3 = if i < index then HOT elseif i == index then LIGHT else UiKit.KHAKI
		p.BackgroundTransparency = if i <= index then 0 else 0.7
	end
	-- chip: botão da ação (ícone no controle) ou a distância do alvo do campo de tiro
	local img: string?, key: string, sub: string = nil, "?", ""
	if st.action then
		local i, k, hold = keyOf(st.action)
		img, key, sub = i, k, if hold then "SEGURAR" else ""
	elseif st.range then
		key, sub = tostring(st.range) .. " m", "ALVO"
	end
	local top = if sub ~= "" then CHIP_H - SUB_H - 2 else CHIP_H
	chipIcon.Image = img or ""
	chipIcon.Visible = img ~= nil
	chipIcon.Position = UDim2.fromOffset(CHIP_W / 2, top / 2 + 1)
	chipKey.Visible = img == nil
	chipKey.Text = key
	chipKey.Size = UDim2.fromOffset(CHIP_W - 8, top - 6)
	chipSub.Text = sub
	chipSub.Visible = sub ~= ""
	-- texto: o mesmo do Tutorial.render, com o botão em destaque
	local plain = Tutorial.render(st, glyph)
	body.Text = Tutorial.render({ id = st.id, action = st.action, range = st.range, text = esc(st.text) }, hotGlyph)
	-- medida no Arimo negrito: nunca menor que o texto real (parte dele é negrito)
	local h = TextService:GetTextSize(plain, BODY_SIZE, Enum.Font.ArimoBold, Vector2.new(BODY_W, 10000)).Y
	local ch = math.max(CHIP_H, math.ceil(h) + 4)
	content.Size = UDim2.new(1, 0, 0, ch)
	body.Size = UDim2.fromOffset(BODY_W, ch)
	return CONTENT_Y + ch + PAD
end

local SLIDE = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local shown = false
local shownKey = ""
local swapToken = 0
local targetX = MARGIN

local function fadeContent(show: boolean, t: number)
	local info =
		TweenInfo.new(t, Enum.EasingStyle.Quad, if show then Enum.EasingDirection.Out else Enum.EasingDirection.In)
	for _, f in fadeItems do
		TweenService:Create(f.inst, info, { [f.prop] = if show then f.base else 1 }):Play()
	end
end

-- aparece entrando pela esquerda
local function showPanel(st: Tutorial.Step)
	swapToken += 1
	root.Size = UDim2.fromOffset(W, apply(st))
	for _, f in fadeItems do
		(f.inst :: any)[f.prop] = f.base
	end
	content.Position = UDim2.fromOffset(0, CONTENT_Y)
	root.Position = UDim2.new(0, -W - 40, 1, -MARGIN)
	root.Visible = true
	shown = true
	TweenService:Create(root, SLIDE, { Position = UDim2.new(0, targetX, 1, -MARGIN) }):Play()
end

-- troca de passo: o conteúdo sai pela esquerda, o painel muda de altura e o novo entra
local function swap()
	swapToken += 1
	local my = swapToken
	local out = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	fadeContent(false, 0.12)
	TweenService:Create(content, out, { Position = UDim2.fromOffset(-12, CONTENT_Y) }):Play()
	task.delay(0.12, function()
		local st = current()
		if my ~= swapToken or not st then
			return
		end
		local h = apply(st)
		TweenService:Create(root, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(W, h) }):Play()
		content.Position = UDim2.fromOffset(16, CONTENT_Y)
		TweenService
			:Create(content, TweenInfo.new(0.26, Enum.EasingStyle.Quint), { Position = UDim2.fromOffset(0, CONTENT_Y) })
			:Play()
		fadeContent(true, 0.22)
	end)
end

-- caído ou morto o tutorial some: a tela de ferido e o relatório de baixa ficam sozinhos (no Studio
-- o cartão cobria o painel de ferido, D-87)
local function casualtyShown(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	for _, name in { "VT65Caido", "VT65Baixa" } do
		local g = pg and pg:FindFirstChild(name)
		if g and g:IsA("ScreenGui") and g.Enabled then
			return true
		end
	end
	return false
end

local function draw()
	local st = current()
	local ctx = Input.context()
	local hurt = Input.state.downed or not Input.state.alive or casualtyShown()
	local want = st ~= nil and ctx ~= "menu" and ctx ~= "map" and ctx ~= "wheel" and not hurt
	local x = if Input.state.vehicle then VEHICLE_X else MARGIN
	local moved = x ~= targetX
	targetX = x
	if not want or not st then
		swapToken += 1
		if shown then
			shown = false
			shownKey = ""
			if st == nil then
				-- fim do tutorial: sai deslizando para a esquerda
				local tw = TweenService:Create(
					root,
					TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
					{ Position = UDim2.new(0, -W - 40, 1, -MARGIN) }
				)
				tw.Completed:Once(function()
					if not shown then
						root.Visible = false
					end
				end)
				tw:Play()
			else
				root.Visible = false -- menu, mapa ou roda: some na hora
			end
		end
		return
	end
	-- o texto entra na chave: trocar de dispositivo ou de tecla redesenha
	local key = string.format("%s|%d|%s", role or "", index, Tutorial.render(st, glyph))
	if not shown then
		shownKey = key
		showPanel(st)
	elseif key ~= shownKey then
		shownKey = key
		swap()
	end
	if moved then
		TweenService:Create(root, SLIDE, { Position = UDim2.new(0, targetX, 1, -MARGIN) }):Play()
	end
end

local function finish()
	if role then
		done[role] = true
		Net.event("Tutorial_Done"):FireServer(role)
		Toast.show("Tutorial concluído. Refazer: menu do jogo → Squad e papel.", "sucesso", { title = "Tutorial" })
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
	-- um aviso só para o campo de tiro: cada acerto atualiza o anterior
	Toast.show(
		string.format(
			"Alvo de %d m: %d cm %s, %d cm %s do centro",
			h.dist,
			math.abs(math.round(up)),
			if up >= 0 then "acima" else "abaixo",
			math.abs(math.round(right)),
			if right >= 0 then "à direita" else "à esquerda"
		),
		"sucesso",
		{ key = "campo_de_tiro" }
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
player:GetAttributeChangedSignal("Downed"):Connect(draw)
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	local function watchGui(g: Instance)
		if g:IsA("ScreenGui") and (g.Name == "VT65Caido" or g.Name == "VT65Baixa") then
			g:GetPropertyChangedSignal("Enabled"):Connect(draw)
		end
	end
	for _, g in pg:GetChildren() do
		watchGui(g)
	end
	pg.ChildAdded:Connect(watchGui)
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
