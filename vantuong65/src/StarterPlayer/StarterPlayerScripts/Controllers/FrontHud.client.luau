--!strict
-- HUD da frente, avisos de setor e tela de fim de partida (pedido do dono, 2026-11-11: "não fica
-- claro o que está em disputa", "fim de partida claro, com placar").
--   - faixa no alto, ao centro (acima dos avisos do Toast): modo e relógio, os 5 setores com o dono
--     (azul = nosso, vermelho = do inimigo, cáqui = neutro), quem está tomando (▲ nós, ▼ eles), a
--     disputa (⚔) e o progresso; reforços (Warfare) ou a frente (Offensive); e o objetivo do time
--     com rumo e distância ("ATACAR · S3 Cemitério · ~420 m a noroeste"). Some com a carta e os menus;
--   - avisos pelo Toast: setor sob ataque, em disputa, tomado, perdido, neutralizado, frente que
--     anda, reforços baixos e 5 minutos;
--   - fim: carimbo VITÓRIA / DERROTA / EMPATE, o motivo e o placar (setores, reforços, baixas,
--     duração) sobre o relatório pós-ação; some sozinho ou com A / Enter.
-- Nada aqui mostra inimigo: só o estado dos pontos (Parte 9.5). Studio: o VT65DevEnd do servidor
-- encerra a partida e mostra a tela de fim.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Casualty = require(ReplicatedStorage.Shared.Casualty)
local Front = require(ReplicatedStorage.Shared.Front)
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

local C = {
	card = Color3.fromRGB(26, 28, 21),
	nosso = Color3.fromRGB(70, 104, 170),
	inimigo = Color3.fromRGB(176, 58, 44),
	neutro = Color3.fromRGB(150, 140, 106),
	khaki = UiKit.KHAKI,
	brass = UiKit.BRASS,
}

local hud = UiKit.screen("VT65Frente", 14)
local strip = Instance.new("Frame")
strip.Name = "Faixa"
strip.AnchorPoint = Vector2.new(0.5, 0)
strip.Position = UDim2.new(0.5, 0, 0, px(6, 8))
strip.Size = UDim2.fromOffset(px(560, 820), px(52, 62))
strip.BackgroundColor3 = C.card
strip.BackgroundTransparency = 0.12
strip.BorderSizePixel = 0
strip.Visible = false
strip.Parent = hud
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = strip
	local s = Instance.new("UIStroke")
	s.Color = C.khaki
	s.Transparency = 0.7
	s.Parent = strip
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 160))
	g.Parent = strip
	-- janela estreita: a faixa encolhe inteira (nada passa da borda)
	UiKit.fit(hud, strip, strip.Size.X.Offset, 1, 8)
end

local function text(parent: Instance, size: number, color: Color3, head: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextColor3 = color
	t.TextSize = size
	if head then
		t.FontFace = UiKit.HEAD_FONT
	else
		t.Font = UiKit.BODY_FONT
	end
	t.Parent = parent
	return t
end

local ROW1 = px(30, 36)
local clockMode = text(strip, px(11, 18), C.khaki, true)
clockMode.Position = UDim2.fromOffset(10, 3)
clockMode.Size = UDim2.fromOffset(px(80, 120), px(12, 18))
clockMode.TextXAlignment = Enum.TextXAlignment.Left
local clock = text(strip, px(18, 26), Color3.fromRGB(236, 228, 204), true)
clock.Position = UDim2.fromOffset(10, px(13, 18))
clock.Size = UDim2.fromOffset(px(80, 120), px(18, 22))
clock.TextXAlignment = Enum.TextXAlignment.Left
local scoreText = text(strip, px(13, 22), C.khaki, true)
scoreText.AnchorPoint = Vector2.new(1, 0)
scoreText.Position = UDim2.new(1, -10, 0, 4)
scoreText.Size = UDim2.fromOffset(px(120, 190), ROW1 - 4)
scoreText.TextXAlignment = Enum.TextXAlignment.Right
scoreText.RichText = true
local objective = text(strip, px(13, 22), Color3.fromRGB(236, 228, 204))
objective.AnchorPoint = Vector2.new(0.5, 1)
objective.Position = UDim2.new(0.5, 0, 1, -3)
objective.Size = UDim2.new(1, -20, 0, px(16, 24))
objective.RichText = true

-- os 5 setores
local CHIP_W, CHIP_H = px(46, 70), px(24, 30)
local chips: { any } = {}
do
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 4)
	row.Size = UDim2.fromOffset(5 * CHIP_W + 4 * 4, CHIP_H)
	row.Parent = strip
	for i = 1, 5 do
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset((i - 1) * (CHIP_W + 4), 0)
		f.Size = UDim2.fromOffset(CHIP_W, CHIP_H)
		f.BackgroundColor3 = C.neutro
		f.BorderSizePixel = 0
		f.Parent = row
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 3)
		c.Parent = f
		local st = Instance.new("UIStroke")
		st.Color = C.brass
		st.Thickness = 2
		st.Transparency = 1
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = f
		local name = text(f, px(13, 20), Color3.fromRGB(246, 240, 222), true)
		name.Size = UDim2.new(1, 0, 1, -4)
		name.Text = "S" .. i
		name.TextStrokeTransparency = 0.6
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0, 2, 1, -2)
		bar.Size = UDim2.new(1, -4, 0, px(3, 4))
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BackgroundTransparency = 0.5
		bar.BorderSizePixel = 0
		bar.Parent = f
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = bar
		local mark = text(f, px(12, 18), Color3.new(1, 1, 1), true)
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, -2, 0, -1)
		mark.Size = UDim2.fromOffset(14, 14)
		mark.TextStrokeTransparency = 0.3
		chips[i] = { frame = f, stroke = st, name = name, fill = fill, mark = mark }
	end
end

local state: any = nil
local prev: any = nil
local cooldown: { [string]: number } = {}
local once: { [string]: boolean } = {}

local function mine(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else nil
end

local function enemyOf(f: string?): string
	return if f == "US" then "VC" else "US"
end

local function rel(owner: string?): Color3
	local f = mine()
	if owner == "US" or owner == "VC" then
		return if owner == f then C.nosso else C.inimigo
	end
	return C.neutro
end

local function sectorName(st: any, s: number): string
	local p = st.points and st.points[s]
	return if p then string.format("S%d %s", s, p.name) else "S" .. s
end

local function throttle(key: string, seconds: number): boolean
	local now = os.clock()
	if (cooldown[key] or -math.huge) + seconds > now then
		return false
	end
	cooldown[key] = now
	return true
end

-- ===== avisos a partir da diferença entre dois estados =====
local function alerts(st: any, old: any)
	local f = mine()
	if not f or st.ended or not old or old.ended or old.mode ~= st.mode then
		return
	end
	local e = enemyOf(f)
	for s = 1, #st.owner do
		local was, now = old.owner[s], st.owner[s]
		local name = sectorName(st, s)
		if was ~= now then
			-- cada aviso é um modelo inteiro (o nome do setor entra no %s; o dicionário traduz o modelo)
			if now == f then
				Toast.show(string.format("%s é nosso", name), "sucesso", { title = "Setor tomado" })
			elseif now == e then
				Toast.show(string.format("%s caiu nas mãos do inimigo", name), "erro", { title = "Setor perdido" })
			elseif was == f then
				Toast.show(
					string.format("%s foi neutralizado: retome o ponto", name),
					"alerta",
					{ title = "Setor neutralizado" }
				)
			else
				Toast.show(
					string.format("%s neutralizado: continue até tomar", name),
					"info",
					{ title = "Setor neutralizado" }
				)
			end
		elseif st.active[s] then
			local cap, oldCap = st.capturing and st.capturing[s], old.capturing and old.capturing[s]
			local con, oldCon = st.contested and st.contested[s], old.contested and old.contested[s]
			if con and not oldCon and throttle("disputa" .. s, 45) then
				Toast.show(
					string.format("%s: os dois lados no ponto, a captura parou", name),
					"alerta",
					{ title = "Em disputa" }
				)
			elseif cap == e and oldCap ~= e and now == f and throttle("ataque" .. s, 45) then
				Toast.show(
					string.format("%s sob ataque", name),
					"alerta",
					{ title = "Setor sob ataque", key = "ataque" .. s }
				)
			elseif cap == f and oldCap ~= f and now ~= f and throttle("tomando" .. s, 60) then
				Toast.show(string.format("Tomando %s", name), "info", { title = "Captura" })
			end
		end
	end
	if st.mode == "Offensive" and st.front ~= old.front and type(st.front) == "number" and st.front >= 1 then
		Toast.show(
			string.format("A frente passa para %s (+15 min no relógio)", sectorName(st, st.front)),
			if f == "US" then "sucesso" else "alerta",
			{ title = "Frente" }
		)
	end
	if st.score and st.score.max then
		for _, side in { f, e } do
			local key = "reforcos" .. side
			if not once[key] and (st.score[side] or 0) <= st.score.max * 0.25 then
				once[key] = true
				Toast.show(
					if side == f then "Nossos reforços estão em 25%" else "Reforços do inimigo em 25%",
					if side == f then "alerta" else "info",
					{ title = "Reforços" }
				)
			end
		end
	end
	if not once.cinco and (st.timeLeft or 9999) <= 300 and (old.timeLeft or 0) > 300 then
		once.cinco = true
		Toast.show("Faltam 5 minutos", "alerta", { title = "Relógio" })
	end
end

-- ===== faixa =====
local function render(st: any)
	local f = mine()
	local t = math.max(0, math.floor(st.timeLeft or 0))
	clockMode.Text = UiKit.upper(st.mode or "")
	clock.Text = string.format("%02d:%02d", t // 60, t % 60)
	clock.TextColor3 = if t <= 300 and not st.ended then Color3.fromRGB(244, 184, 96) else Color3.fromRGB(236, 228, 204)
	local sign = if f == "VC" then -1 else 1
	local role, target = nil, nil
	if f then
		role, target = Front.objective(st.owner, st.active, f, st.capturing)
	end
	for i, ch in chips do
		local owner = st.owner[i]
		local active = st.active[i]
		ch.frame.Visible = owner ~= nil
		ch.frame.BackgroundColor3 = rel(owner)
		ch.frame.BackgroundTransparency = if active then 0 else 0.55
		ch.name.TextTransparency = if active then 0 else 0.4
		local p = (st.progress[i] or 0) * sign
		ch.fill.BackgroundColor3 = if p >= 0 then Color3.fromRGB(150, 182, 236) else Color3.fromRGB(240, 140, 120)
		ch.fill.Size = UDim2.fromScale(math.abs(p), 1)
		local cap = st.capturing and st.capturing[i]
		local con = st.contested and st.contested[i]
		ch.mark.Text = if con then "⚔" elseif cap == f then "▲" elseif cap then "▼" else ""
		ch.mark.TextColor3 = if con
			then Color3.fromRGB(255, 214, 120)
			elseif cap == f then Color3.fromRGB(190, 220, 255)
			else Color3.fromRGB(255, 170, 150)
		ch.stroke.Transparency = if i == target then 0 else 1
		ch.contested = con == true
	end
	-- direita: reforços (Warfare) ou frente (Offensive)
	if st.score and f then
		local e = enemyOf(f)
		scoreText.Text = string.format(
			'REFORÇOS <font color="#96B6EC">%d</font> · <font color="#F08C78">%d</font>',
			st.score[f] or 0,
			st.score[e] or 0
		)
	elseif st.mode == "Offensive" and type(st.front) == "number" and st.front >= 1 then
		scoreText.Text = string.format("FRENTE S%d", st.front)
	else
		scoreText.Text = ""
	end
	-- objetivo com rumo e distância de onde estou
	if role and target and st.points and st.points[target] then
		local p = st.points[target]
		local where = ""
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dx, dz = p.x - root.Position.X, p.z - root.Position.Z
			local m = math.sqrt(dx * dx + dz * dz) * 0.28
			where = if m < 50
				then " · você está nele"
				else string.format(" · ~%d m a %s", Casualty.roundDistance(m), Casualty.bearing(dx, dz))
		end
		local verb = if role == "attack"
			then '<font color="#ECCA74">ATACAR</font>'
			else '<font color="#ECCA74">DEFENDER</font>'
		objective.Text = string.format("%s · %s%s", verb, sectorName(st, target), where)
	else
		objective.Text = ""
	end
end

-- ===== fim de partida =====
local endGui = UiKit.screen("VT65FimDePartida", 43) -- acima do relatório pós-ação (40)
endGui.Enabled = false
local endShown: number? = nil
local endParts: any = {}
do
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = endGui
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.48)
	card.Size = UDim2.fromOffset(px(560, 820), px(380, 540))
	card.BackgroundColor3 = UiKit.CARD
	card.BorderSizePixel = 0
	card.Rotation = -0.8
	card.Parent = endGui
	local cs = Instance.new("UIStroke")
	cs.Color = UiKit.DRAB
	cs.Thickness = 4
	cs.Parent = card
	local sc = Instance.new("UIScale")
	sc.Parent = card
	local head = text(card, px(16, 24), UiKit.RULE_RED, false)
	head.Font = Enum.Font.SpecialElite
	head.Position = UDim2.fromOffset(24, 16)
	head.Size = UDim2.new(1, -48, 0, px(20, 28))
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.Text = "MENSAGEM · OPERAÇÃO STARLITE · FIM DA AÇÃO"
	local rule = Instance.new("Frame")
	rule.Position = UDim2.fromOffset(24, px(40, 54))
	rule.Size = UDim2.new(1, -48, 0, 2)
	rule.BackgroundColor3 = UiKit.RULE_RED
	rule.BorderSizePixel = 0
	rule.Parent = card
	local stamp = text(card, px(64, 96), UiKit.STAMP, true)
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.new(0.5, 0, 0, px(96, 140))
	stamp.Size = UDim2.fromOffset(px(420, 620), px(76, 110))
	stamp.Rotation = -7
	local ss = Instance.new("UIStroke")
	ss.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ss.Thickness = 4
	ss.Color = UiKit.STAMP
	ss.Parent = stamp
	local why = text(card, px(17, 26), UiKit.INK, false)
	why.Font = Enum.Font.SpecialElite
	-- abaixo do carimbo girado (no Studio ele encostava no motivo, D-87)
	why.Position = UDim2.fromOffset(24, px(170, 248))
	why.Size = UDim2.new(1, -48, 0, px(24, 34))
	why.TextWrapped = true
	local table_ = text(card, px(17, 26), UiKit.INK, false)
	table_.Font = Enum.Font.Code
	table_.Position = UDim2.fromOffset(40, px(206, 294))
	table_.Size = UDim2.new(1, -80, 0, px(120, 170))
	table_.TextXAlignment = Enum.TextXAlignment.Left
	table_.TextYAlignment = Enum.TextYAlignment.Top
	local foot = text(card, px(14, 22), UiKit.OLIVE, false)
	foot.Font = Enum.Font.SpecialElite
	foot.AnchorPoint = Vector2.new(0.5, 1)
	foot.Position = UDim2.new(0.5, 0, 1, -12)
	foot.Size = UDim2.new(1, -40, 0, px(20, 28))
	-- cabe em qualquer janela: a entrada termina na escala de ajuste (fit.k), não em 1
	local fit = UiKit.fit(endGui, card, card.Size.X.Offset, card.Size.Y.Offset, 16)
	endParts = {
		dim = dim,
		card = card,
		scale = sc,
		fit = fit,
		stamp = stamp,
		stampStroke = ss,
		why = why,
		table = table_,
		foot = foot,
	}
end

local function reason(st: any): string
	local w = st.winner
	if w ~= "US" and w ~= "VC" then
		return "Tempo esgotado com setores e reforços iguais."
	end
	local who = if w == "US" then "USMC" else "VC"
	local loser = if w == "US" then "VC" else "US"
	if st.mode == "Offensive" then
		return if w == "US"
			then "O USMC tomou o último setor."
			else "O relógio zerou: a defesa do VC segurou a linha."
	end
	if st.score and (st.score[loser] or 1) <= 0 then
		return string.format("Os reforços do %s acabaram.", if loser == "US" then "USMC" else "VC")
	end
	local all = true
	for i, o in st.owner do
		if st.active[i] and o ~= w then
			all = false
		end
	end
	if all then
		return string.format("O %s tomou todos os setores.", who)
	end
	return string.format("Tempo esgotado: o %s tem mais setores (ou mais reforços).", who)
end

local function closeEnd()
	if not endGui.Enabled then
		return
	end
	local p = endParts
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(p.scale, info, { Scale = p.fit.k() * 0.9 }):Play()
	TweenService:Create(p.dim, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(p.card, info, { Position = UDim2.fromScale(0.5, 1.4) }):Play()
	task.delay(0.36, function()
		endGui.Enabled = false
		-- o relatório pós-ação fica por baixo: o foco do controle volta para ele
		local rep = player.PlayerGui:FindFirstChild("VT65AfterAction")
		if rep and rep:IsA("ScreenGui") and rep.Enabled then
			UiKit.focus(rep)
		end
	end)
end

local function showEnd(st: any)
	local f = mine()
	local p = endParts
	local w = st.winner
	local word, color = "EMPATE", UiKit.OLIVE
	if w == f then
		word, color = "VITÓRIA", Color3.fromRGB(46, 96, 52)
	elseif w == "US" or w == "VC" then
		word, color = "DERROTA", UiKit.STAMP
	end
	if not f then
		word = if w == "US" then "VITÓRIA DO USMC" elseif w == "VC" then "VITÓRIA DO VC" else "EMPATE"
	end
	p.stamp.Text = word
	p.stamp.TextColor3 = color
	p.stampStroke.Color = color
	p.why.Text = reason(st)
	local sectors = { US = 0, VC = 0 }
	for i, o in st.owner do
		if st.active[i] and (o == "US" or o == "VC") then
			sectors[o] += 1
		end
	end
	local lines = { string.format("%-12s %8s %8s", "", "USMC", "VC") }
	table.insert(lines, string.format("%-12s %8d %8d", "Setores", sectors.US, sectors.VC))
	if st.score then
		table.insert(lines, string.format("%-12s %8d %8d", "Reforços", st.score.US or 0, st.score.VC or 0))
	end
	if st.kia then
		table.insert(lines, string.format("%-12s %8d %8d", "Baixas", st.kia.US or 0, st.kia.VC or 0))
	end
	table.insert(lines, string.format("%-12s %8s", "Duração", Casualty.duration(st.elapsed or 0)))
	p.table.Text = table.concat(lines, "\n")
	endShown = os.clock()
	endGui.Enabled = true
	-- carimbo: bate de cima e assenta
	p.card.Position = UDim2.fromScale(0.5, 0.48)
	local k = p.fit.k()
	p.scale.Scale = k * 0.85
	p.dim.BackgroundTransparency = 1
	TweenService:Create(p.dim, TweenInfo.new(0.4), { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(p.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = k })
		:Play()
	p.stamp.TextTransparency = 1
	p.stamp.Size = UDim2.fromOffset(px(560, 820), px(110, 160))
	task.delay(0.35, function()
		p.stamp.TextTransparency = 0
		TweenService:Create(
			p.stamp,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(px(420, 620), px(76, 110)) }
		):Play()
	end)
	task.delay(9, function()
		if endShown and os.clock() - endShown >= 8.9 then
			closeEnd()
		end
	end)
end

UserInputService.InputBegan:Connect(function(io: InputObject)
	if not endGui.Enabled or not endShown or os.clock() - endShown < 1.2 then
		return
	end
	local k = io.KeyCode
	if
		k == Enum.KeyCode.ButtonA
		or k == Enum.KeyCode.Return
		or k == Enum.KeyCode.Space
		or io.UserInputType == Enum.UserInputType.MouseButton1
	then
		closeEnd()
	end
end)

-- ===== estado =====
Net.event("Match_State").OnClientEvent:Connect(function(st)
	if type(st) ~= "table" or type(st.owner) ~= "table" then
		return
	end
	-- "quem está tomando" vem como lista cheia com "" = ninguém (MatchService.publish)
	if type(st.capturing) == "table" then
		for i, v in st.capturing do
			if v == "" then
				st.capturing[i] = nil
			end
		end
	end
	prev, state = state, st
	if prev and not prev.ended and st.ended then
		showEnd(st)
	elseif prev and prev.ended and not st.ended then
		table.clear(once)
		table.clear(cooldown)
		closeEnd()
		Toast.show(string.format("Nova partida: %s", st.mode), "info", { title = "Operação Starlite" })
	end
	alerts(st, prev)
	render(st)
end)

RunService.Heartbeat:Connect(function()
	local st = state
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local inField = st ~= nil and mine() ~= nil and hum ~= nil and hum.Health > 0
	strip.Visible = inField and not Input.state.map and Input.state.menus == 0 and not endGui.Enabled
	if endGui.Enabled and endShown then
		local n = state and state.nextIn
		endParts.foot.Text = if type(n) ~= "number"
			then ""
			elseif Input.isGamepad() then string.format("Próxima partida em %d s · A: relatório", math.ceil(n))
			else string.format("Próxima partida em %d s · Enter: relatório", math.ceil(n))
	end
	-- disputa: o setor pisca
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 5)
	for _, ch in chips do
		if ch.contested then
			ch.stroke.Color = Color3.fromRGB(255, 214, 120)
			ch.stroke.Transparency = pulse * 0.8
		else
			ch.stroke.Color = C.brass
		end
	end
	if GuiService.SelectedObject and endGui.Enabled and GuiService.SelectedObject:IsDescendantOf(player.PlayerGui) then
		-- com a tela de fim por cima, A não pode fechar o relatório de baixo
		local rep = player.PlayerGui:FindFirstChild("VT65AfterAction")
		if rep and GuiService.SelectedObject:IsDescendantOf(rep) then
			GuiService.SelectedObject = nil
		end
	end
end)
