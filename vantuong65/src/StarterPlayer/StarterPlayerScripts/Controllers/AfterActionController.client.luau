--!strict
-- Relatório pós-ação (Parte 11): no fim da partida, uma folha datilografada com linha do tempo,
-- baixas e resultado. Abre como menu (controle: rolar com o analógico direito, B fecha) e some
-- quando a próxima partida começa.
-- Refeito (pedido do dono, 2026-11-11; D-87: "o relatório antigo, cinza e sem acentos, aparece por
-- trás da ficha de fim"): folha de papel com cabeçalho em vermelho, carimbo CONFIDENCIAL no canto do
-- cabeçalho (longe do texto), seções em Oswald com filete, linhas pautadas em máquina de escrever
-- (o vietnamita no Arimo), as linhas entrando uma a uma. Só abre DEPOIS que a ficha de fim
-- (FrontHud, VT65FimDePartida) sai; cada linha do servidor (Shared/AfterAction) é um modelo inteiro,
-- num rótulo próprio, e o dicionário traduz linha a linha. Cabe em qualquer janela (UiKit.fit).
-- Studio: o VT65DevEnd do servidor encerra a partida; workspace:SetAttribute("VT65DevTela",
-- "relatorio") abre com um relatório de exemplo.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end
local W, H = px(760, 1040), px(640, 860)

local gui = UiKit.screen("VT65AfterAction", 40)
gui.Enabled = false

local dim = Instance.new("Frame")
dim.Position = UDim2.fromOffset(0, -60)
dim.Size = UDim2.new(1, 0, 1, 60)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Parent = gui

local sheet = Instance.new("Frame")
sheet.Name = "Folha"
sheet.AnchorPoint = Vector2.new(0.5, 0.5)
sheet.Position = UDim2.fromScale(0.5, 0.5)
sheet.Size = UDim2.fromOffset(W, H)
sheet.BackgroundColor3 = UiKit.CARD
sheet.BorderSizePixel = 0
sheet.Rotation = 0.5
sheet.Active = true
sheet.Parent = gui
UiKit.lit(sheet, 0.86)
UiKit.edge(sheet, UiKit.INK, 1, 0.5)
local fit = UiKit.fit(gui, sheet, W, H, 16)
Acabamento.sombra(sheet, 24, Vector2.new(0, 10), 0.6)

local P = px(28, 38)
local head = UiKit.rotulo(sheet, px(15, 24), UiKit.RULE_RED, UiKit.TYPE_FONT)
head.Position = UDim2.fromOffset(P, px(18, 26))
head.Size = UDim2.new(1, -2 * P - px(200, 280), 0, px(20, 30))
head.Text = "OPERAÇÃO STARLITE · III MAF · 1965"
local title = UiKit.rotulo(sheet, px(30, 44), UiKit.INK, UiKit.HEAD_FONT)
title.Position = UDim2.fromOffset(P - 2, px(38, 54))
title.Size = UDim2.new(1, -2 * P - px(200, 280), 0, px(40, 56))
title.Text = "RELATÓRIO PÓS-AÇÃO"
local subtitle = UiKit.rotulo(sheet, px(15, 24), UiKit.INK, UiKit.TYPE_FONT)
subtitle.Position = UDim2.fromOffset(P, px(78, 110))
subtitle.Size = UDim2.new(1, -2 * P, 0, px(20, 30))
subtitle.TextTransparency = 0.2
local rule = Instance.new("Frame")
rule.BackgroundColor3 = UiKit.RULE_RED
rule.BorderSizePixel = 0
rule.Position = UDim2.fromOffset(P, px(104, 146))
rule.Size = UDim2.new(1, -2 * P, 0, 2)
rule.Parent = sheet
-- carimbo no canto do cabeçalho (só o título fica à esquerda dele)
local stamp = Instance.new("TextLabel")
stamp.AnchorPoint = Vector2.new(1, 0)
stamp.Position = UDim2.new(1, -P, 0, px(24, 32))
stamp.Size = UDim2.fromOffset(px(196, 270), px(46, 64))
stamp.Rotation = -6
stamp.BackgroundTransparency = 1
stamp.FontFace = UiKit.HEAD_FONT
stamp.TextSize = px(26, 38)
stamp.TextColor3 = UiKit.STAMP
stamp.Text = "CONFIDENCIAL"
stamp.Parent = sheet
local stampInk = UiKit.edge(stamp, UiKit.STAMP, 3, 0.2)
local stampScale = Instance.new("UIScale")
stampScale.Parent = stamp

local FOOT = px(54, 76)
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(P - 6, px(112, 156))
scroll.Size = UDim2.new(1, -2 * (P - 6), 1, -(px(112, 156) + FOOT))
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = px(6, 8)
scroll.ScrollBarImageColor3 = UiKit.INK
scroll.ScrollBarImageTransparency = 0.5
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Selectable = true -- o analógico rola a folha no controle
scroll.SelectionImageObject = UiKit.FOCUS
scroll.Parent = sheet
local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll
local lp = Instance.new("UIPadding")
lp.PaddingLeft = UDim.new(0, 6)
lp.PaddingRight = UDim.new(0, 10)
lp.PaddingBottom = UDim.new(0, 10)
lp.Parent = scroll

local foot = UiKit.chips(sheet, px(30, 44), true, px(14, 22))
foot.frame.AnchorPoint = Vector2.new(0, 1)
foot.frame.Position = UDim2.new(0, P, 1, -px(12, 16))
foot.frame.Size = UDim2.new(1, -2 * P - px(200, 280), 0, px(30, 44))

local close = Instance.new("TextButton")
close.Name = "Fechar"
close.AnchorPoint = Vector2.new(1, 1)
close.Position = UDim2.new(1, -P, 1, -px(10, 14))
close.Size = UDim2.fromOffset(px(180, 250), px(36, 50))
close.BackgroundColor3 = UiKit.DRAB
close.AutoButtonColor = false
close.FontFace = UiKit.HEAD_FONT
close.TextColor3 = UiKit.KHAKI
close.TextSize = UiKit.text(16)
close.Text = "ARQUIVAR ×"
close.Selectable = true
close.SelectionImageObject = UiKit.FOCUS
close.Parent = sheet
UiKit.corner(close, 3)
UiKit.lit(close, 0.72)

-- ===== conteúdo =====
local function line(text: string, order: number, parent: Instance?): TextLabel
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Parent = parent or scroll
	local t = UiKit.rotulo(row, 15, UiKit.INK, UiKit.TYPE_FONT)
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.TextWrapped = true
	t.RichText = true
	t.LineHeight = 1.15
	local trimmed = string.match(text, "^%s*(.-)%s*$") or text
	local heading = string.match(trimmed, "^%d+%. %S") ~= nil and UiKit.upper(trimmed) == trimmed
	if trimmed == "" then
		t.Text = ""
		row.Size = UDim2.new(1, 0, 0, px(8, 12))
		row.AutomaticSize = Enum.AutomaticSize.None
		t.Visible = false
	elseif heading then
		t.FontFace = UiKit.HEAD_FONT
		t.TextSize = UiKit.text(18)
		t.Text = trimmed
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, px(6, 8))
		pad.PaddingBottom = UDim.new(0, px(6, 8))
		pad.Parent = row
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0, 1)
		r.Position = UDim2.fromScale(0, 1)
		r.Size = UDim2.new(1, 0, 0, 2)
		r.BackgroundColor3 = UiKit.RULE_RED
		r.BackgroundTransparency = 0.2
		r.BorderSizePixel = 0
		r.Parent = row
	else
		-- linha pautada; o vietnamita (nome de vila) no Arimo
		t.Text = Acabamento.viet(text)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 3)
		pad.PaddingBottom = UDim.new(0, 3)
		pad.Parent = row
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0, 1)
		r.Position = UDim2.fromScale(0, 1)
		r.Size = UDim2.new(1, 0, 0, 1)
		r.BackgroundColor3 = UiKit.RULE_BLUE
		r.BackgroundTransparency = 0.55
		r.BorderSizePixel = 0
		r.Parent = row
	end
	return t
end

local function fill(report: { string })
	for _, c in scroll:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	-- 1ª linha: título (no cabeçalho); 2ª: modo e início (subtítulo)
	local first = 1
	if report[1] and string.find(report[1], "PÓS%-AÇÃO") then
		first = 2
	end
	if report[first] and string.find(report[first], "^Modo:") then
		subtitle.Text = report[first]
		first += 1
	else
		subtitle.Text = ""
	end
	-- Menos texto (pedido do dono, 2026-11-11): primeiro o que importa (3. resultado e 2. baixas);
	-- a linha do tempo (1.) fica dobrada atrás de um botão. As seções vêm numeradas do servidor
	-- (Shared/AfterAction); o número vale em qualquer idioma.
	type Sec = { title: string, lines: { string } }
	local secs: { [number]: Sec } = {}
	local cur: Sec? = nil
	for i = first, #report do
		local raw = report[i]
		local trimmed = string.match(raw, "^%s*(.-)%s*$") or raw
		local num = tonumber(string.match(trimmed, "^(%d+)%. %S") or "")
		if num and UiKit.upper(trimmed) == trimmed then
			local s: Sec = { title = trimmed, lines = {} }
			secs[num] = s
			cur = s
		elseif cur and trimmed ~= "" then
			table.insert(cur.lines, raw)
		end
	end
	local labels: { TextLabel } = {}
	local order = 0
	local function add(text: string, parent: Instance?): TextLabel
		order += 1
		local t = line(text, order, parent)
		if t.Visible then
			table.insert(labels, t)
		end
		return t
	end
	for _, n in { 3, 2 } do
		local s = secs[n]
		if s then
			add(s.title)
			for k, l in s.lines do
				local t = add(l)
				if n == 3 and k == 1 then -- o resultado, grande
					t.FontFace = UiKit.HEAD_FONT
					t.TextSize = UiKit.text(20)
				end
			end
			add("")
		end
	end
	local tl = secs[1]
	if tl then
		add(tl.title)
		-- botão que abre e fecha a linha do tempo
		order += 1
		local toggle = Instance.new("TextButton")
		toggle.Name = "LinhaDoTempo"
		toggle.LayoutOrder = order
		toggle.Size = UDim2.new(1, -8, 0, px(34, 48))
		toggle.BackgroundColor3 = UiKit.DRAB
		toggle.AutoButtonColor = false
		toggle.Text = ""
		toggle.Selectable = true
		toggle.SelectionImageObject = UiKit.FOCUS
		toggle.Parent = scroll
		UiKit.corner(toggle, 3)
		UiKit.lit(toggle, 0.72)
		local tt = UiKit.rotulo(toggle, 15, UiKit.KHAKI, UiKit.HEAD_FONT)
		tt.Position = UDim2.fromOffset(px(12, 16), 0)
		tt.Size = UDim2.new(1, -px(24, 32), 1, 0)
		order += 1
		local box = Instance.new("Frame")
		box.Name = "Registros"
		box.LayoutOrder = order
		box.BackgroundTransparency = 1
		box.Size = UDim2.new(1, 0, 0, 0)
		box.AutomaticSize = Enum.AutomaticSize.Y
		box.Visible = false
		box.Parent = scroll
		local bl = Instance.new("UIListLayout")
		bl.SortOrder = Enum.SortOrder.LayoutOrder
		bl.Parent = box
		for k, l in tl.lines do
			line(l, k, box)
		end
		local function paint()
			tt.Text = if box.Visible
				then string.format("Fechar a linha do tempo (%d registros) ▼", #tl.lines)
				else string.format("Ver a linha do tempo (%d registros) ▸", #tl.lines)
		end
		paint()
		local r = UiKit.realce(toggle, UiKit.DRAB, UiKit.OLIVE, 1.01)
		UiKit.bind(toggle, function()
			box.Visible = not box.Visible
			paint()
		end, r.set)
		toggle.MouseEnter:Connect(function()
			r.set(true)
		end)
		toggle.MouseLeave:Connect(function()
			r.set(false)
		end)
	end
	-- as linhas entram uma a uma (só as primeiras 40 animam; o resto já aparece)
	for i, t in labels do
		if i <= 40 then
			t.TextTransparency = 1
			TweenService:Create(
				t,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.45 + i * 0.035),
				{ TextTransparency = 0 }
			):Play()
		end
	end
	scroll.CanvasPosition = Vector2.zero
end

local function renderFoot()
	foot.clear()
	local dev = Input.device()
	if dev == "gamepad" then
		foot.add(UiKit.padImage(Enum.KeyCode.Thumbstick2), nil, "R", "Rolar")
		foot.action("ui_back", "menu", "Arquivar")
	elseif dev == "touch" then
		foot.add(nil, nil, "Toque", "e arraste para rolar")
	else
		foot.add(nil, nil, "Roda", "rolar")
		foot.action("ui_back", "menu", "Arquivar")
	end
end

-- ===== abrir e fechar =====
local token = 0
local function setOpen(open: boolean)
	if open == gui.Enabled then
		return
	end
	token += 1
	local my = token
	if open then
		gui.Enabled = true
		Input.openMenu()
		renderFoot()
		local k = fit.k()
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 0.45 }):Play()
		sheet.Position = UDim2.new(0.5, 0, 0.5, 60)
		fit.scale.Scale = k * 0.96
		TweenService
			:Create(sheet, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) })
			:Play()
		TweenService:Create(fit.scale, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Scale = k }):Play()
		-- o carimbo cai depois da folha
		stamp.TextTransparency = 1
		stampInk.Transparency = 1
		stampScale.Scale = 1.7
		local hit = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55)
		TweenService:Create(stamp, hit, { TextTransparency = 0.1 }):Play()
		TweenService:Create(stampInk, hit, { Transparency = 0.2 }):Play()
		TweenService:Create(stampScale, hit, { Scale = 1 }):Play()
		UiKit.focus(sheet)
	else
		Input.closeMenu()
		local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(sheet, info, { Position = UDim2.new(0.5, 0, 0.5, 40) }):Play()
		task.delay(0.23, function()
			if token == my then
				gui.Enabled = false
			end
		end)
	end
end

UiKit.bind(close, function()
	setOpen(false)
end)
Input.on("ui_back", "press", function()
	if gui.Enabled then
		setOpen(false)
	end
end)
Input.DeviceChanged:Connect(function()
	if gui.Enabled then
		renderFoot()
	end
end)
UiKit.watch(sheet, function()
	return gui.Enabled
end)

-- abre só depois da ficha de fim (FrontHud): nada fica por trás dela
local function endCardUp(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	local g = pg and pg:FindFirstChild("VT65FimDePartida")
	return g ~= nil and g:IsA("ScreenGui") and g.Enabled
end
local waitToken = 0
local function openWhenFree(report: { string })
	waitToken += 1
	local my = waitToken
	fill(report)
	task.spawn(function()
		task.wait(0.5) -- a ficha de fim chega no mesmo Match_State
		while endCardUp() and waitToken == my do
			task.wait(0.2)
		end
		if waitToken == my then
			setOpen(true)
		end
	end)
end

local shownFor: string? = nil
Net.event("Match_State").OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then
		return
	end
	if st.ended and type(st.report) == "table" then
		local body = table.concat(st.report, "\n")
		if body ~= shownFor then -- abre uma vez por partida
			shownFor = body
			openWhenFree(st.report)
		end
	elseif not st.ended then
		shownFor = nil
		waitToken += 1
		setOpen(false)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "relatorio" then
			-- relatório de exemplo montado pelo mesmo módulo do servidor (Shared/AfterAction): os
			-- textos são os modelos de verdade, já no dicionário
			local AfterAction = require(ReplicatedStorage.Shared.AfterAction) :: any
			local r = AfterAction.new("Warfare", 6.5)
			AfterAction.event(r, 720, "captured", 5, "US")
			AfterAction.event(r, 1500, "neutralized", 4, "VC")
			AfterAction.event(r, 2520, "captured", 4, "US")
			for _ = 1, 9 do
				AfterAction.casualty(r, "US", 4)
				AfterAction.casualty(r, "VC", 4)
			end
			AfterAction.finish(r, "US", 3120, { "VC", "VC", "US", "US", "US" })
			openWhenFree(AfterAction.lines(r))
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
