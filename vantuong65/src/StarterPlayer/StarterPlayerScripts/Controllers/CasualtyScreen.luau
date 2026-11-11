--!strict
-- Tela de queda e de baixa (pedido do dono, 2026-11-11). Realismo da Parte 9.5: sem killcam e sem o
-- nome de quem atirou.
--   CAÍDO (atributo Downed): a visão escurece e pulsa no ritmo do coração (que acelera com o
--   sangramento), o relógio da janela de 60 s escoa, "segure B para desistir" (só depois de 15 s,
--   com o anel enchendo enquanto segura) e o aviso de médico do lado a até 80 m (ou como pedir um).
--   MORTO: ficha de baixa datilografada por cima da tela de inserção: a causa como o soldado
--   perceberia (Shared/Casualty: arma pelo som, rumo em 8 setores e distância de ouvido), onde caiu
--   na grade, a hora em grupo data-hora de 1965 e o tempo em campo. Depois de ~5 s (ou A/Enter), a
--   ficha desce, o preto abre e o controle passa para a carta de inserção (DeployScreen + GameUI).
-- De onde vem a causa, sem mexer no servidor: o Combat_Hit (origem do tiro que acertou) casa com o
-- Combat_Tracer de mesma origem (arma do tiro); o Fire_Impact dá o explosivo que caiu perto.
-- Visual de época no estilo do Toast: oliva escuro, cáqui, latão e carimbo vermelho.
-- Studio (barra de comando do cliente): workspace:SetAttribute("VT65DevQueda", "caido") ou "morto".
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Casualty = require(ReplicatedStorage.Shared.Casualty)
local Explosive = require(ReplicatedStorage.Shared.Explosive)
local FireSupport = require(ReplicatedStorage.Shared.FireSupport)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Medical = require(ReplicatedStorage.Shared.Medical)
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local DeployScreen = require(script.Parent.DeployScreen)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local CasualtyScreen = {}

local player = Players.LocalPlayer
local M = MapConfig.STUD_M
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end
local MEDIC_M = 80 -- médico do lado a até 80 m (o aviso)

local DARK = Color3.fromRGB(26, 28, 21)
local BLOOD = Color3.fromRGB(70, 6, 4)

-- ===== estado =====
local S = {
	medical = nil :: any,
	recvAt = 0,
	downedAt = nil :: number?, -- os.clock local
	cause = nil :: Casualty.Cause?,
	tracers = {} :: { any },
	lastHit = nil :: any,
	lastBlast = nil :: any,
	holdAt = nil :: number?,
	gaveUp = false,
	spawnedAt = os.clock(),
	factionAt = 0,
	deathCard = false,
	dev = false,
	skipFrom = 0, -- A/Enter só passa a ficha depois de 1,2 s (não pula sem querer)
}

-- ===== de onde veio =====
local function myPos(): Vector3?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if r then r.Position else nil
end

local function weaponKind(id: any): string?
	local wp = if type(id) == "string" then Weapons.get(id) else nil
	return if wp then wp.kind else nil
end

-- traçantes recentes (a arma de cada tiro); só os 2 últimos segundos
Net.unreliable("Combat_Tracer").OnClientEvent:Connect(function(p: any)
	if type(p) ~= "table" or type(p.ox) ~= "number" then
		return
	end
	local now = os.clock()
	table.insert(S.tracers, { t = now, o = Vector3.new(p.ox, p.oy, p.oz), w = p.w })
	while #S.tracers > 0 and now - S.tracers[1].t > 2 do
		table.remove(S.tracers, 1)
	end
end)

local function tracerKind(origin: Vector3): string?
	for i = #S.tracers, 1, -1 do
		local tr = S.tracers[i]
		if (tr.o - origin).Magnitude < 1.5 then
			return weaponKind(tr.w)
		end
	end
	return nil
end

Net.event("Combat_Hit").OnClientEvent:Connect(function(o: any)
	if type(o) ~= "table" or type(o.x) ~= "number" then
		return
	end
	local origin = Vector3.new(o.x, o.y, o.z)
	local hit = { t = os.clock(), origin = origin, kind = tracerKind(origin) }
	S.lastHit = hit
	if not hit.kind then
		-- o traçante é "não confiável" e pode chegar depois do acerto: confere de novo
		task.delay(0.3, function()
			if S.lastHit == hit and not hit.kind then
				hit.kind = tracerKind(origin)
			end
		end)
	end
end)

Net.unreliable("Fire_Impact").OnClientEvent:Connect(function(e: any)
	local me = myPos()
	if type(e) ~= "table" or type(e.x) ~= "number" or not me then
		return
	end
	local pos = Vector3.new(e.x, e.y, e.z)
	local t = Explosive.TYPES[tostring(e.id)]
	local reach = if t then t.casualtyM else 30
	if (pos - me).Magnitude * M <= reach then
		S.lastBlast = { t = os.clock(), pos = pos, id = tostring(e.id) }
	end
end)

-- causa do ferimento agora: o tiro ou a explosão mais recente dos últimos 3 s
local function currentCause(): Casualty.Cause
	local me = myPos()
	local now = os.clock()
	local hit, blast = S.lastHit, S.lastBlast
	local hitOk = hit and now - hit.t <= 3
	local blastOk = blast and now - blast.t <= 3
	if me and hitOk and (not blastOk or hit.t >= blast.t) then
		return { kind = "shot", weaponKind = hit.kind, dx = hit.origin.X - me.X, dz = hit.origin.Z - me.Z, studM = M }
	elseif me and blastOk then
		return { kind = "explosion", explosive = blast.id, dx = blast.pos.X - me.X, dz = blast.pos.Z - me.Z, studM = M }
	end
	return { kind = "unknown" }
end

-- ===== camadas =====
local downGui = UiKit.screen("VT65Caido", 13) -- abaixo dos menus e da carta (o caído pode abrir a carta)
downGui.IgnoreGuiInset = true
downGui.Enabled = false
local D: any = {}
do
	local tint = Instance.new("Frame")
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = BLOOD
	tint.BackgroundTransparency = 1
	tint.BorderSizePixel = 0
	tint.Parent = downGui
	local vin = Instance.new("ImageLabel")
	vin.Size = UDim2.fromScale(1, 1)
	vin.BackgroundTransparency = 1
	vin.Image = Acabamento.VINHETA
	vin.ImageColor3 = Color3.fromRGB(40, 0, 0)
	vin.ImageTransparency = 0.2
	vin.Parent = downGui
	local vin2 = vin:Clone()
	vin2.ImageColor3 = Color3.new(0, 0, 0)
	vin2.Parent = downGui
	-- ficha embaixo, longe do meio da tela (o caído ainda olha em volta)
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -px(56, 80))
	card.Size = UDim2.fromOffset(px(440, 660), px(132, 196))
	card.BackgroundColor3 = DARK
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Parent = downGui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = card
	local st = Instance.new("UIStroke")
	st.Color = UiKit.KHAKI
	st.Transparency = 0.7
	st.Parent = card
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, px(4, 6), 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(200, 70, 54)
	bar.BorderSizePixel = 0
	bar.Parent = card
	local function t(size: number, color: Color3, head: boolean?): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.TextColor3 = color
		l.TextSize = size
		l.TextXAlignment = Enum.TextXAlignment.Left
		if head then
			l.FontFace = UiKit.HEAD_FONT
		else
			l.Font = UiKit.BODY_FONT
		end
		l.Parent = card
		return l
	end
	local title = t(px(20, 30), Color3.fromRGB(240, 124, 104), true)
	title.Position = UDim2.fromOffset(px(18, 26), px(8, 12))
	title.Size = UDim2.new(1, -px(120, 180), 0, px(24, 34))
	title.Text = "FERIDO — SANGRANDO"
	local clock = t(px(26, 40), Color3.fromRGB(236, 228, 204), true)
	clock.AnchorPoint = Vector2.new(1, 0)
	clock.Position = UDim2.new(1, -14, 0, px(6, 8))
	clock.Size = UDim2.fromOffset(px(90, 140), px(30, 44))
	clock.TextXAlignment = Enum.TextXAlignment.Right
	local cause = t(px(15, 24), UiKit.CARD)
	cause.Position = UDim2.fromOffset(px(18, 26), px(34, 50))
	cause.Size = UDim2.new(1, -px(32, 44), 0, px(20, 30))
	local drain = Instance.new("Frame")
	drain.Position = UDim2.fromOffset(px(18, 26), px(58, 86))
	drain.Size = UDim2.new(1, -px(32, 44), 0, px(4, 6))
	drain.BackgroundColor3 = Color3.fromRGB(60, 58, 46)
	drain.BorderSizePixel = 0
	drain.Parent = card
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(176, 52, 40)
	fill.BorderSizePixel = 0
	fill.Parent = drain
	local medic = t(px(15, 24), UiKit.KHAKI)
	medic.Position = UDim2.fromOffset(px(18, 26), px(68, 100))
	medic.Size = UDim2.new(1, -px(32, 44), 0, px(20, 30))
	medic.RichText = true
	local giveup = t(px(15, 24), UiKit.CARD)
	giveup.Position = UDim2.fromOffset(px(18, 26) + px(30, 44), px(96, 142))
	giveup.Size = UDim2.new(1, -px(70, 100), 0, px(24, 34))
	giveup.RichText = true
	-- anel do segurar B (UIGradient gira o preenchimento: meia-lua que fecha)
	local ring = Instance.new("Frame")
	ring.Position = UDim2.fromOffset(px(18, 26), px(98, 144))
	ring.Size = UDim2.fromOffset(px(22, 32), px(22, 32))
	ring.BackgroundTransparency = 1
	ring.Parent = card
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(1, 0)
	rc.Parent = ring
	local rs = Instance.new("UIStroke")
	rs.Thickness = px(3, 4)
	rs.Color = UiKit.BRASS
	rs.Parent = ring
	local rg = Instance.new("UIGradient")
	rg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 0.85),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	rg.Parent = rs
	local key = t(px(12, 18), UiKit.BRASS, true)
	key.Size = UDim2.fromScale(1, 1)
	key.TextXAlignment = Enum.TextXAlignment.Center
	key.Parent = ring
	UiKit.fit(downGui, card, card.Size.X.Offset, card.Size.Y.Offset + px(56, 80), 12) -- janela estreita
	D = {
		tint = tint,
		vin = vin,
		vin2 = vin2,
		card = card,
		clock = clock,
		cause = cause,
		fill = fill,
		medic = medic,
		giveup = giveup,
		ring = ring,
		ringGrad = rg,
		key = key,
	}
end

local deathGui = UiKit.screen("VT65Baixa", 25) -- acima da tela de inserção (20), abaixo dos avisos
deathGui.IgnoreGuiInset = true
deathGui.Enabled = false
local K: any = {}
do
	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.fromRGB(8, 8, 6)
	black.BorderSizePixel = 0
	black.Parent = deathGui
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(px(520, 780), px(330, 480))
	card.BackgroundColor3 = UiKit.CARD
	card.BorderSizePixel = 0
	card.Rotation = 1.2
	card.Parent = deathGui
	local cs = Instance.new("UIStroke")
	cs.Color = UiKit.DRAB
	cs.Thickness = 3
	cs.Parent = card
	local sc = Instance.new("UIScale")
	sc.Parent = card
	-- luz quente de lampião sobre a ficha
	local glow = Instance.new("ImageLabel")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.42)
	glow.Size = UDim2.fromScale(1.8, 1.8)
	glow.BackgroundTransparency = 1
	glow.Image = Acabamento.LUZ
	glow.ImageColor3 = Color3.fromRGB(255, 190, 120)
	glow.ImageTransparency = 0.55
	glow.ZIndex = 0
	glow.Parent = black
	local function t(size: number, color: Color3, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.TextColor3 = color
		l.TextSize = size
		l.Font = font
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.RichText = true
		l.Parent = card
		return l
	end
	local head = t(px(15, 22), UiKit.RULE_RED, Enum.Font.SpecialElite)
	head.Position = UDim2.fromOffset(24, 16)
	head.Size = UDim2.new(1, -48, 0, px(20, 28))
	head.Text = "RELATÓRIO DE BAIXA · OPERAÇÃO STARLITE"
	local rule = Instance.new("Frame")
	rule.Position = UDim2.fromOffset(24, px(40, 54))
	rule.Size = UDim2.new(1, -48, 0, 2)
	rule.BackgroundColor3 = UiKit.RULE_RED
	rule.BorderSizePixel = 0
	rule.Parent = card
	for i = 1, 7 do
		local l = Instance.new("Frame")
		l.Position = UDim2.fromOffset(24, px(40, 54) + i * px(30, 44))
		l.Size = UDim2.new(1, -48, 0, 1)
		l.BackgroundColor3 = UiKit.RULE_BLUE
		l.BackgroundTransparency = 0.5
		l.BorderSizePixel = 0
		l.Parent = card
	end
	local body = t(px(17, 26), UiKit.INK, Enum.Font.SpecialElite)
	body.Position = UDim2.fromOffset(28, px(48, 64))
	body.Size = UDim2.new(1, -56, 1, -px(100, 140))
	body.LineHeight = 1.32
	local stamp = Instance.new("TextLabel")
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	-- canto de baixo à direita, nas linhas vazias: no alto cobria a causa (teste no Studio, D-87)
	stamp.Position = UDim2.new(1, -px(130, 190), 1, -px(84, 120))
	stamp.Size = UDim2.fromOffset(px(190, 280), px(54, 80))
	stamp.Rotation = -11
	stamp.BackgroundTransparency = 1
	stamp.FontFace = UiKit.HEAD_FONT
	stamp.TextSize = px(40, 60)
	stamp.TextColor3 = UiKit.STAMP
	stamp.Text = "BAIXA"
	stamp.Parent = card
	local ss = Instance.new("UIStroke")
	ss.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ss.Color = UiKit.STAMP
	ss.Thickness = 4
	ss.Parent = stamp
	local foot = t(px(14, 22), UiKit.OLIVE, Enum.Font.SpecialElite)
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.new(0, 24, 1, -12)
	foot.Size = UDim2.new(1, -48, 0, px(20, 28))
	-- cabe em qualquer janela: a entrada termina na escala de ajuste (fit.k), não em 1
	local fit = UiKit.fit(deathGui, card, card.Size.X.Offset, card.Size.Y.Offset, 20)
	K = { black = black, card = card, scale = sc, fit = fit, body = body, stamp = stamp, foot = foot, glow = glow }
end

-- ===== caído =====
function CasualtyScreen.setMedical(s: any)
	S.medical = s
	S.recvAt = os.clock()
end

function CasualtyScreen.holdGiveUp(t0: number?)
	S.holdAt = t0
end

function CasualtyScreen.noteGiveUp()
	S.gaveUp = true
end

-- segundos desde a queda (pelo relógio do servidor que veio no Medical_State)
local function downedFor(): number
	local m = S.medical
	if m and type(m.downedAt) == "number" and type(m.now) == "number" then
		return (m.now - m.downedAt) + (os.clock() - S.recvAt)
	end
	if S.downedAt then
		return os.clock() - S.downedAt
	end
	return 0
end

-- batida do coração: 0..1 (tum-tá), no pulso de quem sangra (sobe de 110 a 150)
local function beat(t: number, bpm: number): number
	local T = 60 / bpm
	local p = t % T
	return math.exp(-((p / 0.07) ^ 2)) + 0.6 * math.exp(-(((p - 0.2) / 0.07) ^ 2))
end

function CasualtyScreen.beat(): number
	if not downGui.Enabled then
		return 0
	end
	local frac = math.clamp(downedFor() / Medical.C.downWindow, 0, 1)
	return math.clamp(beat(os.clock(), Casualty.pulse(frac)), 0, 1)
end

-- aliado médico (jogador ou bot) mais perto, vivo e de pé
local function nearestMedicM(): number?
	local me = myPos()
	local f = player:GetAttribute("Faction")
	if not me then
		return nil
	end
	local best: number? = nil
	local function check(m: Model?, role: any)
		if not m or role ~= "medic" or m:GetAttribute("Faction") ~= f or m:GetAttribute("Downed") then
			return
		end
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		local h = m:FindFirstChildOfClass("Humanoid")
		if r and h and h.Health > 0 then
			local d = (r.Position - me).Magnitude * M
			if d <= MEDIC_M and (best == nil or d < best) then
				best = d
			end
		end
	end
	for _, p in Players:GetPlayers() do
		if p ~= player then
			check(p.Character, p:GetAttribute("Role"))
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				check(m, m:GetAttribute("Role"))
			end
		end
	end
	return best
end

local function showDowned(on: boolean)
	if on == downGui.Enabled then
		return
	end
	downGui.Enabled = on
	if on then
		S.downedAt = os.clock()
		S.cause = currentCause()
		S.gaveUp = false
		D.cause.Text = Casualty.text(S.cause, true)
		-- o aviso do acerto pode chegar depois do atributo Downed: refaz a causa num instante
		local at = S.downedAt
		task.delay(0.4, function()
			if downGui.Enabled and S.downedAt == at then
				local c = currentCause()
				if c.kind ~= "unknown" then
					S.cause = c
					D.cause.Text = Casualty.text(c, true)
				end
			end
		end)
		D.card.Position = UDim2.new(0.5, 0, 1, px(80, 120))
		TweenService:Create(
			D.card,
			TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 1, -px(56, 80)) }
		):Play()
	else
		S.downedAt = nil
	end
end

local medicCheck = 0
RunService.RenderStepped:Connect(function()
	if not downGui.Enabled then
		return
	end
	local t = downedFor()
	local window = Medical.C.downWindow
	local left = math.max(0, window - t)
	local frac = math.clamp(t / window, 0, 1)
	local b = math.clamp(beat(os.clock(), Casualty.pulse(frac)), 0, 1)
	-- a visão fecha com o tempo e pulsa a cada batida
	D.tint.BackgroundTransparency = 1 - (0.12 + 0.32 * frac + 0.1 * b)
	D.vin.ImageTransparency = math.clamp(0.35 - 0.3 * frac - 0.25 * b, 0, 1)
	D.vin2.ImageTransparency = math.clamp(0.9 - 0.7 * frac, 0, 1)
	D.clock.Text = string.format("%d:%02d", math.floor(left) // 60, math.floor(left) % 60)
	D.clock.TextColor3 = if left < 15 then Color3.fromRGB(240, 124, 104) else Color3.fromRGB(236, 228, 204)
	D.fill.Size = UDim2.fromScale(left / window, 1)
	-- desistir: depois de 15 s (Medical.C.giveUpAfter), segurando B (1 s) ou H
	local pad = Input.isGamepad()
	local wait = math.max(0, Medical.C.giveUpAfter - t)
	D.key.Text = if pad then "B" else "H"
	if wait > 0 then
		D.giveup.Text = string.format("Desistir só em %d s: espere socorro", math.ceil(wait))
		D.ringGrad.Rotation = -90
		D.ring.Visible = false
	else
		D.ring.Visible = true
		local holding = pad and S.holdAt ~= nil
		local p = if holding then math.clamp((os.clock() - (S.holdAt :: number)) / 1.0, 0, 1) else 0
		D.ringGrad.Rotation = -90 + 360 * p
		D.giveup.Text = if pad
			then (if holding then "Desistindo…" else "<b>Segure B</b> para desistir e voltar à carta")
			else "<b>H</b> para desistir e voltar à carta"
	end
	local now = os.clock()
	if now - medicCheck > 0.5 then
		medicCheck = now
		local d = nearestMedicM()
		D.medic.Text = if d
			then string.format(
				'<font color="#ACCE7E">Médico a ~%d m</font>: fique onde está',
				Casualty.roundDistance(d)
			)
			else "Sem médico por perto. Peça pela roda de comunicação: <b>Médico!</b>"
	end
end)

-- ===== morto =====
local function closeDeath(fast: boolean?)
	if not deathGui.Enabled then
		return
	end
	S.deathCard = false
	local t = if fast then 0.25 else 0.6
	local info = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(K.card, info, { Position = UDim2.fromScale(0.5, 1.5), Rotation = 4 }):Play()
	TweenService:Create(K.black, TweenInfo.new(t + 0.2, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(K.glow, TweenInfo.new(t), { ImageTransparency = 1 }):Play()
	task.delay(t + 0.25, function()
		if not S.deathCard then
			deathGui.Enabled = false
			S.dev = false
			Input.closeMenu() -- o controle volta para a carta de inserção
		end
	end)
end

local function roleName(): string
	local r = player:GetAttribute("Role")
	local def = if type(r) == "string" and Roles.roles then Roles.roles[r] else nil
	return if def and def.name then def.name else tostring(r or "—")
end

local function showDeath(cause: Casualty.Cause?, where: Vector3?, note: string?)
	if deathGui.Enabled then
		return
	end
	S.deathCard = true
	deathGui.Enabled = true
	Input.openMenu() -- até a ficha descer, nada da carta de baixo responde
	GuiService.SelectedObject = nil
	local sid = player:GetAttribute("SquadId")
	local squad = if type(sid) == "string" then (string.match(sid, ":(.+)$") or sid) else "—"
	local grid = if where then FireSupport.localToGrid(where.X, where.Z, MapConfig.GridOrigin1965, M, 6) else "—"
	-- uma linha por modelo inteiro ("Rótulo   %s"): o dicionário traduz o rótulo e o valor conhecido
	local lines = {
		string.format("NOME       %s", player.DisplayName),
		string.format("SQUAD      %s · %s", squad, roleName()),
		string.format("CAUSA      %s", Casualty.text(cause, false)),
		string.format("LOCAL      %s", grid),
		string.format("HORA       %s", Casualty.dtg(Lighting.ClockTime)),
		string.format("EM CAMPO   %s", Casualty.duration(os.clock() - S.spawnedAt)),
	}
	if note then
		table.insert(lines, string.format("OBS.       %s", note))
	end
	K.body.Text = Acabamento.viet(table.concat(lines, "\n"))
	K.foot.Text = ""
	-- entra: preto, a ficha cai na mesa, o carimbo bate e o texto é datilografado
	K.black.BackgroundTransparency = 1
	TweenService:Create(K.black, TweenInfo.new(0.5), { BackgroundTransparency = 0.08 }):Play()
	K.glow.ImageTransparency = 1
	TweenService:Create(K.glow, TweenInfo.new(1.2), { ImageTransparency = 0.55 }):Play()
	K.card.Position = UDim2.fromScale(0.5, 0.42)
	K.card.Rotation = -4
	local k = K.fit.k()
	K.scale.Scale = k * 1.08
	local drop = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.35)
	TweenService:Create(K.card, drop, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 1.2 }):Play()
	TweenService:Create(K.scale, drop, { Scale = k }):Play()
	K.stamp.TextTransparency = 1
	K.stamp.Size = UDim2.fromOffset(px(260, 380), px(74, 110))
	task.delay(1.0, function()
		K.stamp.TextTransparency = 0
		TweenService:Create(
			K.stamp,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(px(190, 280), px(54, 80)) }
		):Play()
	end)
	Acabamento.datilografar(K.body, K.body.Text, 90, 0.7)
	local shownAt = os.clock()
	-- passagem: quando a tela de inserção já está aberta por baixo e a ficha ficou o bastante
	task.spawn(function()
		while S.deathCard and deathGui.Enabled do
			local t = os.clock() - shownAt
			local ready = DeployScreen.root.Visible or S.dev
			K.foot.Text = if t > 1.2
				then (if Input.isGamepad()
					then "A: ir para a carta de inserção"
					else "Enter ou clique: ir para a carta")
				else ""
			if ready and t >= 5.5 then
				closeDeath(false)
				break
			end
			task.wait(0.1)
		end
	end)
	S.skipFrom = shownAt + 1.2
end

UserInputService.InputBegan:Connect(function(io: InputObject)
	if not (deathGui.Enabled and S.deathCard) or os.clock() < S.skipFrom then
		return
	end
	local k = io.KeyCode
	if
		k == Enum.KeyCode.ButtonA
		or k == Enum.KeyCode.Return
		or k == Enum.KeyCode.Space
		or io.UserInputType == Enum.UserInputType.MouseButton1
	then
		if DeployScreen.root.Visible or S.dev then
			closeDeath(true)
		end
	end
end)

-- ===== personagem =====
local function watch(char: Model)
	S.spawnedAt = os.clock()
	S.lastHit, S.lastBlast, S.cause = nil, nil, nil
	S.medical = nil
	showDowned(false)
	if deathGui.Enabled and not S.dev then
		closeDeath(true) -- renasceu (reanimado pela transição) com a ficha ainda na tela
	end
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum.Died:Connect(function()
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local where = if root then root.Position else nil
		local wasDowned = downGui.Enabled
		local downFor = downedFor()
		local diedAt = os.clock()
		local note: string? = nil
		if wasDowned and S.gaveUp then
			note = "desistiu à espera de socorro"
		elseif wasDowned and downFor >= Medical.C.downWindow - 1 then
			note = "sangrou sem socorro"
		end
		-- troca de lado (o servidor mata o personagem) e lobby sem papel não são baixa
		if os.clock() - S.factionAt < 3 or player:GetAttribute("Role") == nil or char:GetAttribute("Evacuated") then
			showDowned(false)
			return
		end
		-- o aviso do tiro (Combat_Hit) pode chegar um instante depois da morte: espera 0,3 s
		task.delay(0.3, function()
			local cause = S.cause
			-- morto de uma vez, ou já caído por outro tiro ou explosão: a causa nova vale
			local fresh = currentCause()
			if fresh.kind ~= "unknown" then
				local h = S.lastHit
				local bl = S.lastBlast
				local latest = math.max(if h then h.t else 0, if bl then bl.t else 0)
				if not wasDowned or (downFor > 1 and diedAt - latest < 1.5) then
					cause = fresh
				end
			end
			showDowned(false)
			showDeath(cause, where, note)
		end)
	end)
end

player:GetAttributeChangedSignal("Downed"):Connect(function()
	showDowned(player:GetAttribute("Downed") == true)
end)
player:GetAttributeChangedSignal("Faction"):Connect(function()
	S.factionAt = os.clock()
end)
player.CharacterAdded:Connect(watch)
if player.Character then
	task.spawn(watch, player.Character)
end

-- ===== gancho de teste (só no Studio): fotos das duas telas =====
-- Na barra de comando do lado do cliente: workspace:SetAttribute("VT65DevQueda", "caido") mostra a
-- tela de caído (20 s, com causa de exemplo); "morto" mostra a ficha de baixa; "fim" fecha as duas.
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevQueda"):Connect(function()
		local v = workspace:GetAttribute("VT65DevQueda")
		if type(v) ~= "string" then
			return
		end
		local sample: Casualty.Cause = { kind = "shot", weaponKind = "rifle", dx = 300, dz = -310, studM = M }
		if v == "caido" then
			S.lastHit =
				{ t = os.clock(), origin = (myPos() or Vector3.zero) + Vector3.new(300, 0, -310), kind = "rifle" }
			showDowned(true)
			task.delay(20, function()
				if player:GetAttribute("Downed") ~= true then
					showDowned(false)
				end
			end)
		elseif v == "morto" then
			S.dev = true
			showDowned(false)
			showDeath(sample, myPos(), nil)
		elseif v == "fim" then
			S.dev = false
			showDowned(false)
			closeDeath(true)
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevQueda", nil)
		end)
	end)
end

return CasualtyScreen
