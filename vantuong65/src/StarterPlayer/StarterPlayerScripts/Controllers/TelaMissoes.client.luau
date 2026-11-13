--!strict
-- Missões (plano de volta diária, 2026-11-12): 3 ordens do dia (meia-noite UTC) e 3 da semana, todas
-- de jogo de verdade, com barra de progresso, recompensa (XP, créditos, estrelas do passe), receber,
-- a troca grátis do dia e quando renovam. O estado vem do CampanhaCliente (Campanha_State; o servidor
-- confere tudo). Abre por Bus "missoes_open" (lobby, menu do jogo, tela de baixa, tela de fim).
-- Estilo novo: painel escuro, título grande, números grandes, poucas palavras. As seis linhas são
-- criadas uma vez; abrir e mudar o estado só trocam textos, barras e quais botões aparecem.
-- Pilha do voltar ("missoes"): B, Esc e Backspace fecham só esta tela. Studio:
-- workspace:SetAttribute("VT65DevTela", "missoes") abre (com um estado de exemplo se o servidor ainda
-- não mandou nenhum).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Progression = require(ReplicatedStorage.Shared.Progression)
local Bus = require(script.Parent.Bus)
local CampanhaCliente = require(script.Parent.CampanhaCliente)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local V, F = UiKit.V, UiKit.F
local px = UiKit.px
local W, H = px(780, 1040), px(600, 820)
local ROW_H = px(76, 104)

local gui = UiKit.screen("VT65Missoes", 38) -- acima do menu do jogo (35) e da loja (30)
gui.Enabled = false
gui.IgnoreGuiInset = true

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Active = true
dim.Parent = gui

local panel = UiKit.panel(gui, V.PANEL, 0.04)
panel.Name = "Missoes"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(W, H)
local fit = UiKit.fit(gui, panel, W, H, 16)
do
	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(1, 0, 0, px(4, 6))
	accent.BackgroundColor3 = V.OLIVE
	accent.BorderSizePixel = 0
	accent.Parent = panel
end
local P = px(24, 32)

-- ===== cabeçalho =====
local kick = UiKit.kicker(panel, "ORDENS DO DIA E DA SEMANA", 14)
kick.Position = UDim2.fromOffset(P, px(16, 22))
kick.Size = UDim2.new(1, -2 * P, 0, px(18, 26))
local title = UiKit.title(panel, "MISSÕES", px(40, 56))
title.Position = UDim2.fromOffset(P, px(34, 48))
title.Size = UDim2.new(0.6, 0, 0, px(48, 66))
local rerollStat = UiKit.stat(panel, "TROCA GRÁTIS", "1", px(34, 46))
rerollStat.frame.AnchorPoint = Vector2.new(1, 0)
rerollStat.frame.Position = UDim2.new(1, -P, 0, px(20, 28))
local closeBtn = UiKit.action(panel, "FECHAR", "secondary", function()
	Bus.fire("missoes_close")
end, { action = "ui_back", ctx = "menu", h = px(38, 54) })
closeBtn.button.AnchorPoint = Vector2.new(1, 1)
closeBtn.button.Position = UDim2.new(1, -P, 1, -px(16, 22))
closeBtn.button.Size = UDim2.fromOffset(px(150, 210), px(38, 54))

-- ===== seções e linhas =====
type Row = {
	frame: Frame,
	text: TextLabel,
	count: TextLabel,
	fill: Frame,
	reward: TextLabel,
	claim: UiKit.Action,
	reroll: UiKit.Action,
	doneTag: TextLabel,
	id: string?,
}
local rows: { Row } = {}
local sectionLabels: { TextLabel } = {}
local resetLabels: { TextLabel } = {}
-- lista rolável (Parte 13): 2 seções e 6 linhas (~558 px) não cabiam nos ~434 px do corpo; a
-- última linha passava por baixo do FECHAR. Rola no dedo, na roda do mouse e no analógico direito.
local body = Instance.new("ScrollingFrame")
body.Name = "Corpo"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Position = UDim2.fromOffset(P, px(96, 130))
body.Size = UDim2.new(1, -2 * P, 1, -px(96, 130) - px(70, 96))
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.ScrollBarThickness = px(4, 6)
body.ScrollBarImageColor3 = V.LINE
body.Selectable = false
body.Parent = panel
UiKit.list(body, false, px(6, 8))

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function section(textLabel: string): (TextLabel, TextLabel)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, px(30, 42))
	f.LayoutOrder = nextOrder()
	f.Parent = body
	local l = UiKit.title(f, textLabel, px(20, 28), V.KHAKI)
	l.Size = UDim2.new(0.5, 0, 1, 0)
	local r = UiKit.kicker(f, "", px(14, 20))
	r.AnchorPoint = Vector2.new(1, 0)
	r.Position = UDim2.fromScale(1, 0)
	r.Size = UDim2.new(0.5, 0, 1, 0)
	r.TextXAlignment = Enum.TextXAlignment.Right
	table.insert(sectionLabels, l)
	table.insert(resetLabels, r)
	return l, r
end

local function onClaim(i: number)
	local r = rows[i]
	if r and r.id then
		CampanhaCliente.action("claim_mission", { id = r.id })
	end
end
local function onReroll(i: number)
	local r = rows[i]
	if r and r.id then
		CampanhaCliente.action("reroll", { id = r.id })
	end
end

local function newRow(i: number): Row
	local f = UiKit.panel(body, V.PANEL_2, 0, true)
	f.Name = "Missao"
	f.Size = UDim2.new(1, 0, 0, ROW_H)
	f.LayoutOrder = nextOrder()
	local BTN_W = px(150, 210)
	local text = UiKit.text2(f, "", px(17, 24), V.TEXT, F.BODY_B)
	text.Position = UDim2.fromOffset(px(14, 18), px(8, 10))
	text.Size = UDim2.new(1, -px(14, 18) - BTN_W - px(150, 210), 0, px(24, 32))
	text.TextTruncate = Enum.TextTruncate.AtEnd
	local back, fill = UiKit.bar(f, px(8, 10), V.OLIVE)
	back.Position = UDim2.fromOffset(px(14, 18), px(42, 58))
	back.Size = UDim2.new(1, -px(14, 18) - BTN_W - px(150, 210) - px(70, 96), 0, px(8, 10))
	local count = UiKit.text2(f, "", px(20, 28), V.TEXT, F.TITLE)
	count.AnchorPoint = Vector2.new(0, 0.5)
	count.Position = UDim2.new(1, -BTN_W - px(150, 210) - px(62, 86), 0, px(46, 63))
	count.Size = UDim2.fromOffset(px(60, 84), px(26, 36))
	local reward = UiKit.text2(f, "", px(15, 22), V.KHAKI, F.TITLE_MED)
	reward.AnchorPoint = Vector2.new(1, 0.5)
	reward.Position = UDim2.new(1, -BTN_W - px(24, 32), 0.5, 0)
	reward.Size = UDim2.fromOffset(px(140, 196), ROW_H - px(12, 16))
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.TextWrapped = true
	local claim = UiKit.action(f, "RECEBER", "primary", function()
		onClaim(i)
	end, { h = px(44, 60) })
	claim.button.AnchorPoint = Vector2.new(1, 0.5)
	claim.button.Position = UDim2.new(1, -px(12, 16), 0.5, 0)
	claim.button.Size = UDim2.fromOffset(BTN_W, px(44, 60))
	claim.label.TextXAlignment = Enum.TextXAlignment.Center
	local reroll = UiKit.action(f, "TROCAR", "secondary", function()
		onReroll(i)
	end, { h = px(40, 56) })
	reroll.button.AnchorPoint = Vector2.new(1, 0.5)
	reroll.button.Position = UDim2.new(1, -px(12, 16), 0.5, 0)
	reroll.button.Size = UDim2.fromOffset(BTN_W, px(40, 56))
	local doneTag = UiKit.tag(f, "RECEBIDA", V.PANEL_3, px(14, 20))
	doneTag.AnchorPoint = Vector2.new(1, 0.5)
	doneTag.Position = UDim2.new(1, -px(12, 16), 0.5, 0)
	return {
		frame = f,
		text = text,
		count = count,
		fill = fill,
		reward = reward,
		claim = claim,
		reroll = reroll,
		doneTag = doneTag,
		id = nil,
	}
end

section("DO DIA")
for i = 1, 3 do
	rows[i] = newRow(i)
end
section("DA SEMANA")
for i = 4, 6 do
	rows[i] = newRow(i)
end

-- ===== pé: lembrete e dicas =====
local notifyBtn = UiKit.action(panel, "LEMBRETE: DESLIGADO", "ghost", function()
	local s = CampanhaCliente.get()
	local m = s and s.missions
	CampanhaCliente.action("notify", { on = not (type(m) == "table" and m.notify == true) })
end, { h = px(38, 54) })
notifyBtn.button.AnchorPoint = Vector2.new(0, 1)
notifyBtn.button.Position = UDim2.new(0, P, 1, -px(16, 22))
notifyBtn.button.Size = UDim2.fromOffset(px(300, 420), px(38, 54))
notifyBtn.label.TextXAlignment = Enum.TextXAlignment.Left
local empty = UiKit.body(panel, "Recebendo as missões do servidor…", px(16, 22), V.DIM)
empty.Position = UDim2.fromOffset(P, px(110, 150))
empty.Size = UDim2.new(1, -2 * P, 0, px(30, 40))
empty.Visible = false

-- ===== desenho =====
local function rewardText(rw: any): string
	-- números em linhas ("+%d XP", dinheiro do jogo, "★ %d"), cada uma um modelo inteiro
	if type(rw) ~= "table" then
		return ""
	end
	local parts = {}
	if (tonumber(rw.xp) or 0) > 0 then
		table.insert(parts, string.format("+%d XP", tonumber(rw.xp) :: number))
	end
	if (tonumber(rw.cr) or 0) > 0 then
		table.insert(parts, Progression.money(tonumber(rw.cr) :: number))
	end
	if (tonumber(rw.stars) or 0) > 0 then
		table.insert(parts, string.format("★ %d", tonumber(rw.stars) :: number))
	end
	return table.concat(parts, "\n")
end

local function missionText(m: any): string
	local t = tostring(m.text or m.id or "")
	local ok, s = pcall(string.format, t, tonumber(m.goal) or 0)
	return if ok then s else t
end

local function hm(sec: number): string
	local h = math.floor(sec / 3600)
	local mi = math.floor((sec % 3600) / 60)
	if h >= 24 then
		return string.format("renovam em %d d %d h", h // 24, h % 24)
	end
	return string.format("renovam em %d h %02d min", h, mi)
end

local function paintRow(r: Row, m: any?, rerollLeft: number, daily: boolean)
	if type(m) ~= "table" then
		r.frame.Visible = false
		r.id = nil
		return
	end
	r.frame.Visible = true
	r.id = tostring(m.id)
	r.text.Text = missionText(m)
	local goal = math.max(1, tonumber(m.goal) or 1)
	local prog = math.clamp(tonumber(m.progress) or 0, 0, goal)
	r.count.Text = string.format("%d/%d", prog, goal)
	TweenService:Create(r.fill, UiKit.SOFT, { Size = UDim2.fromScale(prog / goal, 1) }):Play()
	r.fill.BackgroundColor3 = if m.done then V.KHAKI else V.OLIVE
	r.reward.Text = rewardText(m.reward)
	local claimed = m.claimed == true
	local canClaim = m.done == true and not claimed
	local canReroll = daily and not m.done and rerollLeft > 0
	r.claim.button.Visible = canClaim
	r.reroll.button.Visible = canReroll and not canClaim
	r.doneTag.Visible = claimed
	r.frame.BackgroundColor3 = if canClaim then V.PANEL_3 else V.PANEL_2
end

local sample: any = nil -- estado de exemplo do gancho de teste
local function current(): any
	return sample or CampanhaCliente.get()
end

local function render()
	local s = current()
	local m = if type(s) == "table" then s.missions else nil
	if type(m) ~= "table" then
		empty.Visible = true
		body.Visible = false
		rerollStat.value.Text = "—"
		return
	end
	empty.Visible = false
	body.Visible = true
	local left = tonumber(m.rerollLeft) or 0
	rerollStat.value.Text = string.format("%d", left)
	rerollStat.value.TextColor3 = if left > 0 then V.KHAKI else V.MUTED
	local daily = if type(m.daily) == "table" then m.daily else {}
	local weekly = if type(m.weekly) == "table" then m.weekly else {}
	for i = 1, 3 do
		paintRow(rows[i], daily[i], left, true)
		paintRow(rows[i + 3], weekly[i], 0, false)
	end
	notifyBtn.label.Text = if m.notify == true then "LEMBRETE: LIGADO" else "LEMBRETE: DESLIGADO"
	notifyBtn.label.TextColor3 = if m.notify == true then V.KHAKI else V.DIM
end

-- relógio das renovações: 1 Hz, só com a tela aberta
local function paintClock()
	local s = current()
	local m = if type(s) == "table" then s.missions else nil
	if type(m) ~= "table" then
		return
	end
	resetLabels[1].Text = hm(CampanhaCliente.left(tonumber(m.dailyResetAt)))
	resetLabels[2].Text = hm(CampanhaCliente.left(tonumber(m.weeklyResetAt)))
end

-- ===== abrir e fechar =====
local open = false
local token = 0
local function setOpen(on: boolean)
	if on == open then
		return
	end
	open = on
	token += 1
	local my = token
	if on then
		gui.Enabled = true
		UiKit.opened("missoes", gui.DisplayOrder)
		Input.openMenu()
		if not current() then
			CampanhaCliente.refresh()
		end
		render()
		paintClock()
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
		panel.Position = UDim2.new(0.5, 0, 0.5, px(24, 32))
		TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) })
			:Play()
		fit.play(TweenInfo.new(0.3, Enum.EasingStyle.Quint), 1, 0.96)
		UiKit.focus(panel)
		task.spawn(function()
			while open and token == my do
				paintClock()
				task.wait(1)
			end
		end)
	else
		UiKit.closed("missoes")
		UiKit.release(gui)
		Input.closeMenu()
		sample = nil
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		fit.play(info, 0.95)
		task.delay(0.18, function()
			if token == my then
				gui.Enabled = false
			end
		end)
	end
end

Bus.on("missoes_open", function()
	Bus.fire("menu_close_request") -- o menu do jogo fica por baixo (35 < 38): fecha antes
	setOpen(true)
end)
Bus.on("missoes_close", function()
	setOpen(false)
end)
Input.on("ui_back", "press", function()
	if open and UiKit.backFor("missoes") then
		setOpen(false)
	end
end)
UiKit.watch(panel, function()
	return open
end)

-- estado novo: redesenha no lugar; o resultado do pedido vira aviso curto
CampanhaCliente.Changed:Connect(function(_s: any, result: any)
	if open and not sample then
		render()
		UiKit.focus(panel)
	end
	if open and type(result) == "table" and type(result.op) == "string" then
		if result.op == "claim_mission" and result.ok then
			Toast.show("Recompensa da missão recebida", "recompensa", { title = "Missões" })
		elseif result.op == "reroll" and result.ok then
			Toast.show("Missão trocada", "info", { title = "Missões" })
		elseif not result.ok and type(result.msg) == "string" and result.msg ~= "" then
			Toast.show(result.msg, "erro", { title = "Missões" })
		end
	end
end)

-- ===== gancho de teste (só no Studio) =====
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "missoes" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
		if not CampanhaCliente.get() then
			local t = os.time()
			local function mission(id: string, text: string, goal: number, prog: number, claimed: boolean?): any
				return {
					id = id,
					text = text,
					goal = goal,
					progress = prog,
					done = prog >= goal,
					claimed = claimed == true,
					reward = { xp = 250, cr = 120, stars = 2 },
				}
			end
			sample = {
				now = t,
				missions = {
					daily = {
						mission("d1", "Capturar %d setores", 2, 1),
						mission("d2", "Reanimar %d companheiros", 3, 3),
						mission("d3", "Fazer %d abates", 10, 10, true),
					},
					weekly = {
						mission("w1", "Sobreviver %d min no S3", 5, 2),
						mission("w2", "Jogar %d partida com um amigo no squad", 1, 0),
						mission("w3", "Vencer %d partidas", 5, 3),
					},
					rerollLeft = 1,
					dailyResetAt = t + 5 * 3600 + 720,
					weeklyResetAt = t + 3 * 86400 + 7200,
					notify = false,
				},
			}
		end
		if open then
			render()
		else
			Bus.fire("missoes_open")
		end
	end)
end
