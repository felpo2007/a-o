--!strict
-- Relatório pós-ação (Parte 11): no fim da partida, o resultado, as baixas e a linha do tempo.
-- Abre como menu (controle: rolar com o analógico direito, B fecha) e some quando a próxima
-- partida começa. Só abre DEPOIS que a tela de fim (FrontHud, VT65FimDePartida) sai.
-- Estilo novo (pedido do dono, 2026-11-11: "não gosto dessa escrita no papel", "telas com muita
-- escrita, mude"): painel escuro, título em Oswald, o resultado em destaque com números grandes
-- (baixas dos dois lados e a duração), os setores no fim como etiquetas coloridas e a linha do tempo
-- recolhida atrás de um botão, em linhas escuras. Sem papel, carimbo nem máquina de escrever.
-- O texto vem do servidor (Shared/AfterAction) em frases inteiras do dicionário: as linhas que
-- viram números (baixas, resultado, setores) são lidas do português que chega; o resto aparece
-- linha a linha, cada uma num rótulo próprio (o Traducao traduz a frase inteira).
-- Cabe em qualquer janela (UiKit.fit) e encolhe ao conteúdo.
-- Studio: o VT65DevEnd do servidor encerra a partida; workspace:SetAttribute("VT65DevTela",
-- "relatorio") abre com um relatório de exemplo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Front = require(ReplicatedStorage.Shared.Front)
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local px = UiKit.px
local W, H = px(780, 1060), px(640, 860)

local gui = UiKit.screen("VT65AfterAction", 40)
gui.Enabled = false

local dim = Instance.new("Frame")
dim.Position = UDim2.fromOffset(0, -60)
dim.Size = UDim2.new(1, 0, 1, 60)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Parent = gui

-- o painel inteiro esmaece junto (CanvasGroup): entra e sai sem nada piscar
local sheet = Instance.new("CanvasGroup")
sheet.Name = "Relatorio"
sheet.AnchorPoint = Vector2.new(0.5, 0.5)
sheet.Position = UDim2.fromScale(0.5, 0.5)
sheet.Size = UDim2.fromOffset(W, H)
sheet.BackgroundColor3 = V.PANEL
sheet.BackgroundTransparency = 0.02
sheet.BorderSizePixel = 0
sheet.GroupTransparency = 1
sheet.Active = true
sheet.Parent = gui
UiKit.corner(sheet, 4)
UiKit.stroke(sheet, V.LINE, 1, 0.45)
local fit = UiKit.fit(gui, sheet, W, H, 16)

-- faixa de cor no alto: a cor do resultado (oliva, vermelho ou cáqui no empate)
local accent = Instance.new("Frame")
accent.Name = "Faixa"
accent.Size = UDim2.new(1, 0, 0, px(4, 6))
accent.BackgroundColor3 = V.KHAKI
accent.BorderSizePixel = 0
accent.Parent = sheet

local P = px(28, 38)
local TOP = px(118, 164) -- onde começa a lista
local kicker = UiKit.kicker(sheet, "OPERAÇÃO STARLITE · III MAF · 1965", px(14, 22))
kicker.Position = UDim2.fromOffset(P, px(20, 28))
kicker.Size = UDim2.new(1, -2 * P, 0, px(18, 26))
local title = UiKit.title(sheet, "RELATÓRIO PÓS-AÇÃO", px(34, 48))
title.Position = UDim2.fromOffset(P, px(38, 54))
title.Size = UDim2.new(1, -2 * P, 0, px(44, 62))
local subtitle = UiKit.text2(sheet, "", px(15, 22), V.DIM)
subtitle.Position = UDim2.fromOffset(P, px(84, 118))
subtitle.Size = UDim2.new(1, -2 * P, 0, px(20, 28))
subtitle.TextTruncate = Enum.TextTruncate.AtEnd

local FOOT = px(64, 88)
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(P - 6, TOP)
scroll.Size = UDim2.new(1, -2 * (P - 6), 1, -(TOP + FOOT))
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = px(5, 8)
scroll.ScrollBarImageColor3 = V.DIM
scroll.ScrollBarImageTransparency = 0.4
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Selectable = true -- o analógico rola a lista no controle
scroll.SelectionImageObject = UiKit.FOCUS
scroll.Parent = sheet
local list = UiKit.list(scroll, false, px(10, 14))
UiKit.pad(scroll, 6, 12, 2, 12)
-- o painel encolhe ao conteúdo, centrado; nunca passa da altura de projeto (aí a lista rola)
list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	local k = math.max(fit.scale.Scale, 0.01)
	local content = list.AbsoluteContentSize.Y / k + px(18, 26)
	local h = math.clamp(TOP + content + FOOT, px(340, 460), H)
	if math.abs(sheet.Size.Y.Offset - h) > 1 then
		sheet.Size = UDim2.fromOffset(W, h)
	end
end)

-- pé: dicas à esquerda, FECHAR à direita
local footLine = Instance.new("Frame")
footLine.AnchorPoint = Vector2.new(0, 1)
footLine.Position = UDim2.new(0, P, 1, -FOOT + 1)
footLine.Size = UDim2.new(1, -2 * P, 0, 1)
footLine.BackgroundColor3 = V.LINE
footLine.BackgroundTransparency = 0.5
footLine.BorderSizePixel = 0
footLine.Parent = sheet
local foot = UiKit.chips(sheet, px(30, 44), false, px(14, 22))
foot.frame.AnchorPoint = Vector2.new(0, 1)
foot.frame.Position = UDim2.new(0, P, 1, -px(14, 20))
foot.frame.Size = UDim2.new(1, -2 * P - px(220, 300), 0, px(30, 44))

local setOpen: (open: boolean) -> ()
local close = UiKit.action(sheet, "FECHAR", "secondary", function()
	setOpen(false)
end, { action = "ui_back", ctx = "menu", h = px(42, 58) })
close.button.Name = "Fechar"
close.button.AnchorPoint = Vector2.new(1, 1)
close.button.Position = UDim2.new(1, -P, 1, -px(11, 15))
close.button.Size = UDim2.fromOffset(px(200, 280), px(42, 58))

-- ===== peças do conteúdo =====
-- uma linha de texto do servidor numa faixa escura (frase inteira: o dicionário traduz)
local function row(text: string, order: number, parent: Instance, dimmed: boolean?): Frame
	local r = Instance.new("Frame")
	r.Name = "Linha"
	r.LayoutOrder = order
	r.BackgroundColor3 = V.PANEL_2
	r.BackgroundTransparency = if dimmed then 0.4 else 0
	r.BorderSizePixel = 0
	r.Size = UDim2.new(1, -8, 0, 0)
	r.AutomaticSize = Enum.AutomaticSize.Y
	UiKit.corner(r, 3)
	UiKit.pad(r, px(12, 16), px(12, 16), px(7, 10))
	local t = UiKit.body(r, text, px(15, 22), if dimmed then V.DIM else V.TEXT)
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.LineHeight = 1.1
	r.Parent = parent
	return r
end

local function trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") or s
end

-- ===== conteúdo =====
type Sec = { title: string, lines: { string } }
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
	-- seções numeradas do servidor: 1 linha do tempo, 2 baixas, 3 resultado
	local secs: { [number]: Sec } = {}
	local cur: Sec? = nil
	for i = first, #report do
		local raw = report[i]
		local t = trim(raw)
		local num = tonumber(string.match(t, "^(%d+)%. %S") or "")
		if num and UiKit.upper(t) == t then
			local s: Sec = { title = t, lines = {} }
			secs[num] = s
			cur = s
		elseif cur and t ~= "" then
			table.insert(cur.lines, raw)
		end
	end
	-- o que vira número e cor (lido do português que chega); o resto fica em linhas
	local kiaUS, kiaVC, mins, winner = nil :: number?, nil :: number?, nil :: number?, nil :: string?
	local owners: { { s: number, o: string } } = {}
	local rest: { string } = {}
	for _, n in { 3, 2 } do
		local s = secs[n]
		for _, l in (if s then s.lines else {}) :: { string } do
			local t = trim(l)
			local a, b = string.match(t, "USMC: (%d+)%s+VC: (%d+)")
			local own = string.match(t, "^Setores no fim: (.+)$")
			if a and b then
				kiaUS, kiaVC = tonumber(a), tonumber(b)
			elseif
				string.find(t, "^Vitória do USMC")
				or string.find(t, "^Vitória do VC")
				or string.find(t, "^Empate")
			then
				winner = if string.find(t, "^Vitória do USMC")
					then "US"
					elseif string.find(t, "^Vitória do VC") then "VC"
					else "draw"
				mins = tonumber(string.match(t, "Duração: (%d+) min") or "")
			elseif own then
				for sn, who in string.gmatch(own, "S(%d+) (%S+)") do
					table.insert(owners, { s = tonumber(sn) or 0, o = who or "—" })
				end
			else
				table.insert(rest, l)
			end
		end
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	-- resultado em destaque
	accent.BackgroundColor3 = if winner == "US" then V.US elseif winner == "VC" then V.VC else V.KHAKI
	if winner then
		local hero = UiKit.title(
			scroll,
			if winner == "US" then "VITÓRIA DO USMC" elseif winner == "VC" then "VITÓRIA DO VC" else "EMPATE",
			px(40, 56),
			if winner == "US" then V.US elseif winner == "VC" then V.VC else V.TEXT
		)
		hero.Name = "Resultado"
		hero.LayoutOrder = nextOrder()
		hero.Size = UDim2.new(1, -8, 0, px(48, 66))
	end
	-- números grandes: baixas dos dois lados e a duração
	local items: { { string } } = {}
	if kiaUS and kiaVC then
		table.insert(items, { "BAIXAS USMC", tostring(kiaUS) })
		table.insert(items, { "BAIXAS VC", tostring(kiaVC) })
	end
	if mins then
		table.insert(items, { "MINUTOS", tostring(mins) })
	end
	if #items > 0 then
		local sr = UiKit.statRow(scroll, items, px(46, 64))
		sr.frame.LayoutOrder = nextOrder()
		if kiaUS and kiaVC then
			sr.stats[1].value.TextColor3 = V.US
			sr.stats[2].value.TextColor3 = V.VC
		end
	end
	-- setores no fim: etiquetas na cor do dono
	if #owners > 0 then
		local box = Instance.new("Frame")
		box.Name = "Setores"
		box.BackgroundTransparency = 1
		box.LayoutOrder = nextOrder()
		box.Size = UDim2.new(1, -8, 0, px(48, 66))
		box.Parent = scroll
		local k = UiKit.kicker(box, "SETORES NO FIM", px(13, 20))
		k.Size = UDim2.new(1, 0, 0, px(18, 26))
		local tags = Instance.new("Frame")
		tags.BackgroundTransparency = 1
		tags.Position = UDim2.fromOffset(0, px(22, 32))
		tags.Size = UDim2.new(1, 0, 0, px(24, 32))
		tags.Parent = box
		UiKit.list(tags, true, px(6, 8))
		for i, it in owners do
			local c = if it.o == "USMC" then V.US elseif it.o == "VC" then V.VC else V.MUTED
			local tg = UiKit.tag(tags, Front.letra(it.s), c, px(15, 22))
			tg.LayoutOrder = i
			tg.Size = UDim2.fromOffset(0, px(24, 32))
		end
	end
	-- o resto (combate mais pesado, linhas que este cliente não conhece)
	for _, l in rest do
		row(l, nextOrder(), scroll)
	end
	-- linha do tempo recolhida atrás de um botão
	local tl = secs[1]
	if tl then
		local box = Instance.new("Frame")
		box.Name = "Registros"
		box.BackgroundTransparency = 1
		box.Size = UDim2.new(1, 0, 0, 0)
		box.AutomaticSize = Enum.AutomaticSize.Y
		box.Visible = false
		UiKit.list(box, false, px(4, 6))
		local toggleRef: UiKit.Action? = nil
		local function paint()
			local tg = toggleRef
			if not tg then
				return
			end
			local n = #tl.lines
			if n == 1 then -- singular: frase própria no dicionário
				tg.label.Text = if box.Visible
					then "Fechar a linha do tempo (1 registro) ▼"
					else "Ver a linha do tempo (1 registro) ►"
			else
				tg.label.Text = if box.Visible
					then string.format("Fechar a linha do tempo (%d registros) ▼", n)
					else string.format("Ver a linha do tempo (%d registros) ►", n)
			end
		end
		local toggle = UiKit.action(scroll, "", "secondary", function()
			box.Visible = not box.Visible
			paint()
		end, { h = px(42, 58) })
		toggle.button.Name = "LinhaDoTempo"
		toggle.button.LayoutOrder = nextOrder()
		toggle.button.Size = UDim2.new(1, -8, 0, px(42, 58))
		toggle.label.FontFace = F.TITLE_MED
		toggleRef = toggle
		box.LayoutOrder = nextOrder()
		box.Parent = scroll
		for k, l in tl.lines do
			row(l, k, box, true)
		end
		paint()
	end
	scroll.CanvasPosition = Vector2.zero
end

local function renderFoot()
	foot.clear()
	local dev = Input.device()
	if dev == "gamepad" then
		foot.add(UiKit.padImage(Enum.KeyCode.Thumbstick2), nil, "R", "Rolar")
	elseif dev == "touch" then
		foot.add(nil, nil, "Toque", "e arraste para rolar")
	else
		foot.add(nil, nil, "Roda", "rolar")
	end
end

-- ===== abrir e fechar =====
local token = 0
setOpen = function(open: boolean)
	if open == gui.Enabled then
		return
	end
	token += 1
	local my = token
	if open then
		gui.Enabled = true
		UiKit.opened("relatorio", gui.DisplayOrder)
		Input.openMenu()
		renderFoot()
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()
		sheet.Position = UDim2.new(0.5, 0, 0.5, 32)
		sheet.GroupTransparency = 1
		TweenService:Create(sheet, TweenInfo.new(0.32, Enum.EasingStyle.Quint), {
			Position = UDim2.fromScale(0.5, 0.5),
			GroupTransparency = 0,
		}):Play()
		fit.play(TweenInfo.new(0.32, Enum.EasingStyle.Quint), 1, 0.96)
		UiKit.focus(sheet)
	else
		Input.closeMenu()
		UiKit.closed("relatorio")
		UiKit.release(gui)
		local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(sheet, info, { Position = UDim2.new(0.5, 0, 0.5, 24), GroupTransparency = 1 }):Play()
		task.delay(0.21, function()
			if token == my then
				gui.Enabled = false
			end
		end)
	end
end

Input.on("ui_back", "press", function()
	if gui.Enabled and UiKit.backFor("relatorio") then
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

-- abre só depois da tela de fim (FrontHud): nada fica por trás dela
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
		task.wait(0.5) -- a tela de fim chega no mesmo Match_State
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
