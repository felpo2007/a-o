--!strict
-- Recompensa diária na entrada (lote 16, D-130). Pedido do dono: "recompensa diária deve aparecer
-- toda vez que entro no jogo" e "não precisa ter um local para ela". Abre por cima do menu principal
-- na primeira vez que ele abre na sessão (Bus "diaria_entrada", posto pelo MenuPrincipal), com os 7
-- dias da caderneta, o de hoje em destaque e um botão só: RESGATAR (quando dá) ou CONTINUAR. A aba e
-- o calendário da mesa saíram (DeployScreen, LobbyScene).
-- O servidor segue sendo a fonte: Daily_Get (estado), Daily_Claim (pedido) e Daily_State (estado com
-- o resultado do pedido). Os créditos de cada dia vêm da trilha (Commerce.DailyTrack), a mesma que o
-- servidor paga (DailyRewardService).
-- Controle: A escolhe, B fecha; teclado: Enter escolhe, Backspace fecha; toque e mouse: tocar ou
-- clicar. Studio: workspace:SetAttribute("VT65DevTela", "diaria") abre de novo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V = UiKit.V
local px = UiKit.px

-- ===== medidas (projeto 1280 x 720; na TV, as da TV) =====
local W, H = px(820, 1100), px(486, 650)
local PAD = px(22, 30)
local GAP = px(10, 14)
local CARD_Y = px(118, 158)
local CARD_H = px(172, 230)
local CARD_W = math.floor((W - 2 * PAD - 6 * GAP) / Commerce.TRACK_DAYS)
local BTN_H = px(62, 84)

-- ===== montagem =====
local gui = UiKit.screen("VT65Diaria", 36) -- acima do menu principal (28) e da loja (30), abaixo do passe (38)
gui.Enabled = false
local dim = Instance.new("Frame")
dim.Name = "Veu"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = V.BG
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Active = true
dim.Parent = gui

local panel = UiKit.panel(gui, V.PANEL, 0) -- sólido: o lobby atrás não aparece através do texto
panel.Name = "Diaria"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(W, H)
local fit = UiKit.fit(gui, panel, W, H, 12)
do -- faixa de latão no alto (é recompensa)
	local a = Instance.new("Frame")
	a.BackgroundColor3 = V.BRASS
	a.BorderSizePixel = 0
	a.Size = UDim2.new(1, 0, 0, px(3, 4))
	a.Parent = panel
end

local kick = UiKit.kicker(panel, "CADERNETA DE SERVIÇO", px(14, 20), V.BRASS)
kick.Position = UDim2.fromOffset(PAD, px(16, 22))
kick.Size = UDim2.fromOffset(px(320, 430), px(20, 28))
local title = UiKit.title(panel, "RECOMPENSA DIÁRIA", px(34, 46))
title.Position = UDim2.fromOffset(PAD, px(36, 48))
title.Size = UDim2.new(1, -2 * PAD, 0, px(42, 56))
local rule = UiKit.body(panel, "Volte todo dia: o prêmio cresce. Pulou um dia, volta ao dia 1.", px(15, 21), V.DIM)
rule.Position = UDim2.fromOffset(PAD, px(82, 110))
rule.Size = UDim2.new(1, -2 * PAD, 0, px(22, 30))

-- dias seguidos, à direita do título
local runStat = UiKit.stat(panel, "DIAS SEGUIDOS", "0", px(34, 46))
runStat.frame.AnchorPoint = Vector2.new(1, 0)
runStat.frame.Position = UDim2.new(1, -PAD, 0, px(18, 24))
runStat.label.TextXAlignment = Enum.TextXAlignment.Right
runStat.value.TextXAlignment = Enum.TextXAlignment.Right

-- os sete dias
type Cell = {
	frame: Frame,
	scale: UIScale,
	stroke: UIStroke,
	day: TextLabel,
	cash: TextLabel,
	item: TextLabel,
	tag: TextLabel,
}
local cells: { Cell } = {}
for i = 1, Commerce.TRACK_DAYS do
	local f = UiKit.panel(panel, V.PANEL_2, 0, true)
	f.Name = "Dia" .. i
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(PAD + (i - 1) * (CARD_W + GAP) + CARD_W // 2, CARD_Y + CARD_H // 2)
	f.Size = UDim2.fromOffset(CARD_W, CARD_H)
	local sc = Instance.new("UIScale")
	sc.Parent = f
	local st = f:FindFirstChildOfClass("UIStroke") :: UIStroke
	local k = UiKit.kicker(f, "DIA", px(12, 17))
	k.Position = UDim2.fromOffset(0, px(8, 10))
	k.Size = UDim2.new(1, 0, 0, px(16, 22))
	k.TextXAlignment = Enum.TextXAlignment.Center
	local d = UiKit.title(f, tostring(i), px(34, 46))
	d.Position = UDim2.fromOffset(0, px(22, 30))
	d.Size = UDim2.new(1, 0, 0, px(40, 54))
	d.TextXAlignment = Enum.TextXAlignment.Center
	local cash = UiKit.title(f, "", px(19, 26), V.KHAKI)
	cash.Position = UDim2.fromOffset(0, px(66, 88))
	cash.Size = UDim2.new(1, 0, 0, px(24, 32))
	cash.TextXAlignment = Enum.TextXAlignment.Center
	local item = UiKit.body(f, "", px(12, 17), V.TEXT)
	item.Position = UDim2.fromOffset(px(4, 6), px(92, 122))
	item.Size = UDim2.new(1, -2 * px(4, 6), 0, px(42, 56))
	item.TextXAlignment = Enum.TextXAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	local tag = UiKit.tag(f, "", V.OLIVE, px(12, 17))
	tag.AnchorPoint = Vector2.new(0.5, 1)
	tag.Position = UDim2.new(0.5, 0, 1, -px(8, 10))
	tag.Visible = false
	cells[i] = { frame = f, scale = sc, stroke = st, day = d, cash = cash, item = item, tag = tag }
end

-- o que aconteceu (resgate, motivo da recusa, sequência zerada) e o aviso de sessão sem gravação
local result = UiKit.body(panel, "", px(16, 22), V.TEXT)
result.Position = UDim2.fromOffset(PAD, CARD_Y + CARD_H + px(12, 16))
result.Size = UDim2.new(1, -2 * PAD, 0, px(44, 60))
local note = UiKit.body(panel, "", px(13, 18), V.RED_HI)
note.Position = UDim2.fromOffset(PAD, CARD_Y + CARD_H + px(56, 76))
note.Size = UDim2.new(1, -2 * PAD, 0, px(20, 28))

local open = false
local token = 0
local daily: any = nil -- último estado do servidor
local dailyAt = 0 -- os.clock() da chegada (contagem regressiva local)
local busy = false
local claimedNow: any = nil -- resultado do resgate feito com a janela aberta

local setOpen: (on: boolean) -> () -- definida em "abrir e fechar"

local function claim()
	if busy or not (daily and daily.ready and daily.canClaim) then
		return
	end
	busy = true
	Net.event("Daily_Claim"):FireServer()
	task.delay(15, function() -- sem resposta: libera o botão (o servidor continua sendo a fonte)
		if busy then
			busy = false
		end
	end)
end

local mainBtn = UiKit.action(panel, "RESGATAR", "primary", function()
	if daily and daily.ready and daily.canClaim and not claimedNow then
		claim()
	elseif not busy then
		setOpen(false)
	end
end, { action = nil, ctx = nil, h = BTN_H })
mainBtn.button.Position = UDim2.fromOffset(PAD, H - PAD - BTN_H)
mainBtn.button.Size = UDim2.new(1, -2 * PAD, 0, BTN_H)

-- ===== estado =====
local function itemName(id: string): string
	local c = Commerce.find(id)
	return if c then c.name else id
end

-- lado para o nome do item: o atual, senão o da última escolha ("US|infantry|..."); nil = os dois
local function sideNow(): string?
	local f = player:GetAttribute("Faction")
	if f == "US" or f == "VC" then
		return f
	end
	local last = player:GetAttribute("UltimaEscolha")
	local s = if type(last) == "string" then string.match(last, "^(%u%u)|") else nil
	return if s == "US" or s == "VC" then s else nil
end

local function hm(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d h %02d min", s // 3600, (s % 3600) // 60)
end

local function left(): number
	if not (daily and type(daily.resetIn) == "number") then
		return 0
	end
	return daily.resetIn - (os.clock() - dailyAt)
end

local REASON: { [string]: string } = {
	already = "Este dia já foi resgatado.",
	clock = "Aguarde a virada do dia (UTC).",
	loading = "Seu perfil ainda está carregando: tente de novo em instantes.",
	readonly = "Seu perfil não carregou neste servidor: o prêmio não pode ser gravado agora (nada foi perdido).",
	error = "O registro falhou: tente de novo.",
}

local function render()
	local d = daily
	local ready = d ~= nil and d.ready == true
	local day: number = if ready and type(d.day) == "number" then d.day else 1
	local side = sideNow()
	runStat.value.Text = if ready then tostring(d.run or 0) else "—"
	for i, c in cells do
		local entry = Commerce.DailyTrack[i]
		c.cash.Text = string.format("+$ %d", entry.credits)
		local items = entry.items
		if items then
			local mine = if side then items[side] else nil
			c.item.Text = if mine then "+ " .. itemName(mine) else "+ item único"
		else
			c.item.Text = ""
		end
		local claimed = ready and d.claimedToday == true
		local done = ready and (if claimed then i < day else (d.canClaim and i < day))
		local today = ready and i == day
		local text, color = "", V.OLIVE
		if today and claimed then
			text, color = "RECEBIDO", V.OLIVE
		elseif today then
			text, color = "HOJE", V.BRASS
		elseif done then
			text, color = "✓", V.OLIVE
		elseif claimed and i == day % Commerce.TRACK_DAYS + 1 then
			text, color = "AMANHÃ", V.PANEL_3
		end
		c.tag.Visible = text ~= ""
		c.tag.Text = text
		c.tag.BackgroundColor3 = color
		c.tag.TextColor3 = if color == V.BRASS then V.BG else V.TEXT
		c.frame.BackgroundColor3 = if today then V.PANEL_3 elseif done then Color3.fromRGB(40, 50, 30) else V.PANEL_2
		c.stroke.Color = if today then V.BRASS else V.LINE
		c.stroke.Thickness = if today then 2 else 1
		c.stroke.Transparency = if today then 0 else 0.55
		c.day.TextColor3 = if today then V.BRASS elseif done then V.TEXT else V.DIM
	end
	-- botão e texto
	local label, sub, on = "CONTINUAR", "", true
	if not ready then
		label, on = "LENDO A CADERNETA…", false
	elseif busy then
		label, on = "REGISTRANDO…", false
	elseif d.canClaim and not claimedNow then
		local entry = Commerce.DailyTrack[day]
		label = string.format("RESGATAR O DIA %d", day)
		sub = string.format("+$ %d", entry.credits)
	end
	mainBtn.label.Text = label
	mainBtn.label.FontFace = UiKit.headFont(label)
	mainBtn.sub.Text = sub
	mainBtn.enabled(on)
	local r = claimedNow
	if r and r.ok then
		local entry = Commerce.DailyTrack[r.day or day]
		-- o que entrou de fato (o servidor aplica os multiplicadores da campanha); sem ele, o da trilha
		local got = if type(r.credits) == "number" and r.credits > 0 then r.credits else entry.credits
		local list = {}
		for _, id in (r.newItems or {}) :: { string } do
			local c = Commerce.find(id)
			if not side or (c and c.faction == side) then
				table.insert(list, itemName(id))
			end
		end
		-- duas frases inteiras (com e sem item novo); o item entra no %s
		result.Text = if #list > 0
			then string.format(
				"Recebido: +$ %d de crédito e um item novo no armário: %s.",
				got,
				table.concat(list, " · ")
			)
			else string.format("Recebido: +$ %d de crédito. Volte amanhã para o dia seguinte.", got)
		result.TextColor3 = V.KHAKI
	elseif r and r.reason then
		result.Text = REASON[r.reason] or REASON.error
		result.TextColor3 = V.RED_HI
	elseif ready and d.claimedToday then
		result.Text = string.format("Você já resgatou hoje. O próximo prêmio sai em %s.", hm(left()))
		result.TextColor3 = V.DIM
	elseif ready and d.clockBehind then
		result.Text = REASON.clock
		result.TextColor3 = V.DIM
	elseif ready and d.broken then
		result.Text = "Um dia passou sem prêmio: a sequência recomeçou no dia 1."
		result.TextColor3 = V.DIM
	elseif not ready then
		result.Text = "Lendo a caderneta…"
		result.TextColor3 = V.DIM
	else
		result.Text = ""
	end
	note.Text = if ready and d.saved == false
		then "Sessão sem DataStore (perfil não carregou ou Studio): o prêmio de hoje não fica gravado."
		else ""
end

-- o cartão de hoje pula ao receber
local function pop(day: number)
	local c = cells[day]
	if not c then
		return
	end
	c.scale.Scale = 1
	local up = TweenService:Create(c.scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1.12,
	})
	up.Completed:Once(function()
		TweenService:Create(c.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end)
	up:Play()
end

local asking = false
local function fetch()
	if asking then
		return
	end
	asking = true
	task.spawn(function()
		-- perfil ainda carregando: tenta por até 20 s (o Daily_State também chega sozinho)
		local t0 = os.clock()
		while os.clock() - t0 < 20 do
			local ok, s = pcall(function()
				return Net.func("Daily_Get"):InvokeServer()
			end)
			if ok and type(s) == "table" then
				daily = s
				dailyAt = os.clock()
				if open then
					render()
				end
				if s.ready then
					break
				end
			end
			task.wait(2)
		end
		asking = false
	end)
end

Net.event("Daily_State").OnClientEvent:Connect(function(s: any)
	if type(s) ~= "table" then
		return
	end
	daily = s
	dailyAt = os.clock()
	if s.result then
		busy = false
		if open then
			claimedNow = s.result
			if s.result.ok then
				pop(tonumber(s.result.day) or 1)
			end
		end
	end
	if open then
		render()
		UiKit.focus(panel)
	end
end)

-- ===== abrir e fechar =====
setOpen = function(on: boolean)
	if on == open then
		return
	end
	open = on
	token += 1
	local my = token
	if on then
		claimedNow = nil
		busy = false
		gui.Enabled = true
		UiKit.opened("diaria", gui.DisplayOrder)
		Input.openMenu()
		render()
		fetch()
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.4 }):Play()
		panel.Position = UDim2.new(0.5, 0, 0.5, 24)
		TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) })
			:Play()
		fit.play(TweenInfo.new(0.3, Enum.EasingStyle.Quint), 1, 0.95)
		-- os dias pousam um a um
		for i, c in cells do
			c.scale.Scale = 0.85
			task.delay(0.12 + 0.05 * i, function()
				if token == my then
					TweenService:Create(c.scale, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				end
			end)
		end
		UiKit.focus(panel)
	else
		Input.closeMenu()
		UiKit.closed("diaria")
		UiKit.release(gui)
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		fit.play(info, 0.95)
		task.delay(0.19, function()
			if token == my then
				gui.Enabled = false
			end
		end)
	end
end

-- a primeira abertura do menu principal na sessão (MenuPrincipal) chama esta janela
Bus.on("diaria_entrada", function()
	setOpen(true)
end)
Input.on("ui_back", "press", function()
	if open and not busy and UiKit.backFor("diaria") then
		setOpen(false)
	end
end)
-- Enter no teclado aperta o botão (no controle, o A vem pelo foco)
UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
	if processed or not open or UiKit.top() ~= "diaria" then
		return
	end
	if io.KeyCode == Enum.KeyCode.Return or io.KeyCode == Enum.KeyCode.KeypadEnter then
		if mainBtn.isEnabled() then
			if daily and daily.ready and daily.canClaim and not claimedNow then
				claim()
				render()
			elseif not busy then
				setOpen(false)
			end
		end
	end
end)
-- contagem do próximo prêmio com a janela aberta
task.spawn(function()
	while true do
		task.wait(1)
		if open then
			if daily and daily.ready and daily.claimedToday and left() <= 0 then
				fetch() -- virou o dia UTC: o estado novo traz o botão de resgatar
			end
			render()
		end
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "diaria" then
			setOpen(true)
		end
	end)
end
