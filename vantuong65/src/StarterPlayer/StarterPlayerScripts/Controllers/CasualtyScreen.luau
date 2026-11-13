--!strict
-- Tela de queda e de baixa (pedido do dono, 2026-11-11). Realismo da Parte 9.5: sem killcam e sem o
-- nome de quem atirou.
--   CAÍDO (atributo Downed): a visão escurece e pulsa no ritmo do coração (que acelera com o
--   sangramento), o relógio da janela de 60 s escoa, "segure B para desistir" (o anel e a tecla
--   ficam sempre na tela; a espera mínima é a do Shared/Medical, que pode ser zero) e o aviso de
--   médico do lado a até 80 m (ou como pedir um).
--   MORTO (2026-11-13, pedido do dono: "melhore a tela de morte, principalmente o personagem, e quero
--   que coloque a opção de spawnar com o carro aqui"; "faça o jogo mais fast paced"): fundo vermelho
--   escuro; à direita o próprio soldado CAÍDO no chão, com a arma largada (CenaBaixa); à esquerda,
--   de cima para baixo, quem era, BAIXA, a causa numa linha, três números (abates / assistências /
--   tempo) e os ganhos (só se houver). Embaixo, os botões por ordem de uso:
--     1. RENASCER (cheio, enorme): o jogar agora (Controllers/JogarAgora): o squad e o último ponto,
--        com a contagem e a barra no próprio botão; entra sozinho quando a espera zera. A linha de
--        baixo diz onde ("Alfa · Fuzileiro · Reunião — Cemitério");
--     2. NO MESMO LUGAR: créditos (âmbar) ou Robux (verde), regras e cobrança no servidor
--        (Progression.inPlaceCheck/inPlacePay pelo SpawnService), com o motivo quando bloqueado;
--     3. COM VEÍCULO (abre as viaturas do lado em créditos ou Robux, D-103: arma o pedido e renasce
--        num ponto onde ele sai) e ESCOLHER NA CARTA (a carta de inserção, como antes);
--     4. fileira fina: MESA, LOJA, PASSE, MISSÕES.
--   Cores de compra do UiKit.PAGAR: Robux verde, créditos âmbar, grátis/pronto oliva, apagado escuro.
--   Controle: A renascer, X aqui com créditos, Y aqui com Robux, RT veículo, LT carta, B mesa, RB
--   loja, LB missões, direcional para cima passe. Teclado: Enter/Espaço renascer, V veículo, M carta,
--   L loja, Backspace/Esc mesa. Mouse e toque: os botões.
--   A causa: tiro (arma pelo som, rumo e distância), explosão, arma branca (faca, facão, baioneta,
--   coronhada: Combat_Melee com este corpo como alvo) ou "Causa desconhecida".
-- De onde vem a causa, sem mexer no servidor: o Combat_Hit (origem do tiro que acertou) casa com o
-- Combat_Tracer de mesma origem (arma do tiro); o Fire_Impact dá o explosivo que caiu perto.
-- Números da vida: os ganhos do Progress_State desde o nascimento (rótulos do Progression.REWARDS).
-- Studio (barra de comando do cliente): workspace:SetAttribute("VT65DevQueda", "caido") ou "morto"
-- (ou VT65DevTela = "caido" / "morto").
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Casualty = require(ReplicatedStorage.Shared.Casualty)
local Commerce = require(ReplicatedStorage.Shared.Commerce) :: any
local CompraVeiculo = require(ReplicatedStorage.Shared.CompraVeiculo)
local Explosive = require(ReplicatedStorage.Shared.Explosive)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Medical = require(ReplicatedStorage.Shared.Medical)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Vehicles = require(ReplicatedStorage.Shared.Vehicles) :: any
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Bus = require(script.Parent.Bus)
local CenaBaixa = require(script.Parent.CenaBaixa)
local DeployScreen = require(script.Parent.DeployScreen)
local Input = require(script.Parent.Input)
local JogarAgora = require(script.Parent.JogarAgora)
local SpawnTransition = require(script.Parent.SpawnTransition)
local Toast = require(script.Parent.Toast)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)
local VirtualCursor = require(script.Parent.VirtualCursor)

local CasualtyScreen = {}

local player = Players.LocalPlayer
local M = MapConfig.STUD_M
local px = UiKit.px
local V, F = UiKit.V, UiKit.F
local MEDIC_M = 80 -- médico do lado a até 80 m (o aviso)
local ARM_S = 0.7 -- os botões só valem depois disso (quem morreu atirando não clica sem querer)

local BLOOD = Color3.fromRGB(70, 6, 4)

-- janela de caído e espera para desistir (Shared/Medical; sem o número, os padrões)
local function downWindow(): number
	return tonumber((Medical.C :: any).downWindow) or 60
end
local function giveUpAfter(): number
	return tonumber((Medical.C :: any).giveUpAfter) or 0
end

-- ===== estado =====
local S = {
	medical = nil :: any,
	recvAt = 0,
	downedAt = nil :: number?, -- os.clock local
	cause = nil :: Casualty.Cause?,
	tracers = {} :: { any },
	lastHit = nil :: any,
	lastBlast = nil :: any,
	lastMelee = nil :: any, -- golpe de arma branca recebido (Combat_Melee)
	holdAt = nil :: number?,
	gaveUp = false,
	spawnedAt = os.clock(),
	factionAt = 0,
	deathCard = false,
	dev = false,
	skipFrom = 0, -- os botões só valem depois de ARM_S
	-- números da vida (zerados a cada nascimento) e o último estado de progresso
	life = { kills = 0, assists = 0, xp = 0, cr = 0, ranks = {} :: { string }, base = nil :: { [string]: boolean }? },
	progress = nil :: any,
	-- espera dos pontos (Spawn_State, a cada 1 s) e o renascer onde caiu
	spawns = {} :: { any },
	spawnsAt = 0,
	buying = nil :: number?, -- os.clock do pedido de compra em Robux (aguardando o recibo)
	bought = false,
	robuxPrice = nil :: number?,
	portrait = nil :: Model?, -- retrato do soldado tirado em vida (farda e arma dele)
	-- veículo ao nascer (D-103): estado do servidor e o pedido feito daqui
	veh = { spec = nil :: string?, state = "none", cooldown = 0, mine = 0, team = 0, at = 0 },
	vehWant = nil :: { spec: string, pay: string, at: number }?,
	vehOpen = false,
	vehMsg = nil :: string?,
	waitMax = 0, -- a maior espera vista nesta baixa (a barra do RENASCER)
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

-- arma branca (D-94): o MeleeService manda o Combat_Melee ("impacto", com o alvo) a quem está perto;
-- se o alvo é este corpo, foi golpe nele (faca ou facão pela faca do lado de quem golpeou)
Net.event("Combat_Melee").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" or msg.k ~= "impacto" or msg.corpo ~= true then
		return
	end
	local char = player.Character
	if not char or msg.alvo ~= char then
		return
	end
	local by = msg.by
	local f = if typeof(by) == "Instance" then by:GetAttribute("Faction") else nil
	S.lastMelee = {
		t = os.clock(),
		attack = if type(msg.a) == "string" then msg.a else nil,
		blade = if f == "VC" then "dao" elseif f == "US" then "kabar" else nil,
	}
end)

-- causa do ferimento agora: o tiro, a explosão ou o golpe mais recente dos últimos 3 s
local function currentCause(): Casualty.Cause
	local me = myPos()
	local now = os.clock()
	local hit, blast, melee = S.lastHit, S.lastBlast, S.lastMelee
	local hitT = if hit and now - hit.t <= 3 then hit.t else -math.huge
	local blastT = if blast and now - blast.t <= 3 then blast.t else -math.huge
	local meleeT = if melee and now - melee.t <= 3 then melee.t else -math.huge
	local best = math.max(hitT, blastT, meleeT)
	if best == -math.huge then
		return { kind = "unknown" }
	elseif meleeT == best then
		return { kind = "melee", melee = melee.attack, blade = melee.blade }
	elseif me and hitT == best then
		return { kind = "shot", weaponKind = hit.kind, dx = hit.origin.X - me.X, dz = hit.origin.Z - me.Z, studM = M }
	elseif me and blastT == best then
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
	-- painel embaixo, longe do meio da tela (o caído ainda olha em volta): o relógio grande à
	-- esquerda, a causa, o médico e o desistir à direita, a barra do sangramento no pé
	local CW, CH = px(560, 780), px(124, 172)
	local card = UiKit.panel(downGui, V.PANEL, 0.1)
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -px(56, 80))
	card.Size = UDim2.fromOffset(CW, CH)
	local P = px(18, 26)
	local LEFT = px(150, 210)
	local kick = UiKit.kicker(card, "FERIDO", px(15, 22), V.RED_HI)
	kick.Position = UDim2.fromOffset(P, px(12, 16))
	kick.Size = UDim2.fromOffset(LEFT - P, px(20, 28))
	local clock = UiKit.text2(card, "1:00", px(56, 78), V.TEXT, F.TITLE)
	clock.Position = UDim2.fromOffset(P, px(30, 42))
	clock.Size = UDim2.fromOffset(LEFT - P, px(70, 96))
	local sl = UiKit.slash(card, CH - px(36, 50), V.LINE)
	sl.Position = UDim2.fromOffset(LEFT, px(14, 20))
	local X = LEFT + sl.Size.X.Offset + px(10, 14)
	local cause = UiKit.text2(card, "", px(16, 24), V.TEXT, F.BODY_B)
	cause.Position = UDim2.fromOffset(X, px(14, 20))
	cause.Size = UDim2.new(1, -X - P, 0, px(22, 32))
	cause.TextTruncate = Enum.TextTruncate.AtEnd
	local medic = UiKit.text2(card, "", px(15, 22), V.DIM, F.BODY)
	medic.Position = UDim2.fromOffset(X, px(42, 60))
	medic.Size = UDim2.new(1, -X - P, 0, px(20, 30))
	medic.RichText = true
	medic.TextTruncate = Enum.TextTruncate.AtEnd
	-- anel do segurar B (UIGradient gira o preenchimento: meia-lua que fecha)
	local RING = px(24, 34)
	local ring = Instance.new("Frame")
	ring.Position = UDim2.fromOffset(X, px(72, 102))
	ring.Size = UDim2.fromOffset(RING, RING)
	ring.BackgroundTransparency = 1
	ring.Parent = card
	UiKit.corner(ring, 999)
	local rs = Instance.new("UIStroke")
	rs.Thickness = px(3, 4)
	rs.Color = V.KHAKI
	rs.Parent = ring
	local rg = Instance.new("UIGradient")
	rg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 0.85),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	rg.Parent = rs
	local key = UiKit.text2(ring, "", px(12, 18), V.KHAKI, F.TITLE)
	key.Size = UDim2.fromScale(1, 1)
	key.TextXAlignment = Enum.TextXAlignment.Center
	local giveup = UiKit.text2(card, "", px(15, 22), V.TEXT, F.BODY)
	giveup.Position = UDim2.fromOffset(X + RING + px(10, 14), px(72, 102))
	giveup.Size = UDim2.new(1, -X - RING - px(10, 14) - P, 0, RING)
	giveup.RichText = true
	giveup.TextTruncate = Enum.TextTruncate.AtEnd
	local drainBack, fill = UiKit.bar(card, px(4, 6), V.RED)
	drainBack.AnchorPoint = Vector2.new(0, 1)
	drainBack.Position = UDim2.new(0, P, 1, -px(10, 14))
	drainBack.Size = UDim2.new(1, -2 * P, 0, px(4, 6))
	fill.Size = UDim2.fromScale(1, 1)
	local fit = UiKit.fit(downGui, card, CW, CH + px(56, 80), 12) -- janela estreita
	D = {
		fit = fit,
		w = CW,
		h = CH,
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

-- toque (Parte 13): o botão DESISTIR do HUD de toque (ToqueHud, segurar 1 s, no lugar do tiro) aperta
-- a ação "give_up"; aqui o texto diz isso e o anel do cartão enche enquanto o dedo está nele
-- (Input.virtualDown). Sem o HUD de toque (Input.virtual ausente), não há botão: o texto fica o do PC.
local touchHoldAt: number? = nil

-- ===== baixa (morto) =====
local deathGui = UiKit.screen("VT65Baixa", 25) -- acima da tela de inserção (20), abaixo dos avisos
deathGui.IgnoreGuiInset = true
deathGui.Enabled = false
local K: any = {}
do
	-- fundo de cor única, vermelho escuro e saturado (a luz cai de cima à esquerda)
	local bg = UiKit.backdrop(deathGui, V.BG_RED)
	-- luz de lado atrás do soldado (direita): faixa clara que some para o meio
	local side = Instance.new("Frame")
	side.Name = "LuzDeLado"
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.fromScale(1, 0)
	side.Size = UDim2.fromScale(0.55, 1)
	side.BackgroundColor3 = Color3.fromRGB(150, 70, 56)
	side.BorderSizePixel = 0
	side.Parent = bg
	local sg = Instance.new("UIGradient")
	sg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 0.72),
		NumberSequenceKeypoint.new(1, 0.86),
	})
	sg.Parent = side
	local vin = Instance.new("ImageLabel")
	vin.Name = "Vinheta"
	vin.BackgroundTransparency = 1
	vin.Size = UDim2.fromScale(1, 1)
	vin.Image = Acabamento.VINHETA
	vin.ImageColor3 = Color3.new(0, 0, 0)
	vin.ImageTransparency = 0.35
	vin.Parent = bg

	local W, H = px(1180, 1600), px(680, 920)
	local stage = Instance.new("Frame")
	stage.Name = "Baixa"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(W, H)
	stage.BackgroundTransparency = 1
	stage.Parent = deathGui
	local fit = UiKit.fit(deathGui, stage, W, H, 24)

	-- à direita: o soldado caído no chão, com a arma largada (a cena passa um pouco da coluna)
	local SW = px(580, 790)
	local scene = CenaBaixa.new()
	local sframe = scene.frame
	sframe.AnchorPoint = Vector2.new(1, 0.5)
	sframe.Position = UDim2.new(1, px(40, 54), 0.5, 0)
	sframe.Size = UDim2.new(0, SW, 1, px(40, 54))
	sframe.Parent = stage

	-- à esquerda, de cima para baixo: quem era, BAIXA, a causa, os números e os ganhos
	local LW = W - SW - px(10, 14)
	local top = Instance.new("Frame")
	top.Name = "Topo"
	top.BackgroundTransparency = 1
	top.Size = UDim2.fromOffset(LW, 0)
	top.AutomaticSize = Enum.AutomaticSize.Y
	top.Parent = stage
	UiKit.list(top, false, px(6, 10))
	local who = UiKit.kicker(top, "", px(16, 24), V.DIM)
	who.LayoutOrder = 1
	who.Size = UDim2.new(1, 0, 0, px(22, 32))
	local titleBox, title = UiKit.titleBox(top, "BAIXA", px(66, 90), V.TEXT)
	titleBox.LayoutOrder = 2
	local cause = UiKit.text2(top, "", px(22, 30), V.TEXT, F.BODY_B)
	cause.LayoutOrder = 3
	cause.Size = UDim2.new(1, 0, 0, px(30, 42))
	cause.TextTruncate = Enum.TextTruncate.AtEnd
	local note = UiKit.text2(top, "", px(16, 24), V.KHAKI, F.BODY)
	note.LayoutOrder = 4
	note.Size = UDim2.new(1, 0, 0, px(20, 30))
	note.TextTruncate = Enum.TextTruncate.AtEnd
	local row =
		UiKit.statRow(top, { { "ABATES", "0" }, { "ASSISTÊNCIAS", "0" }, { "TEMPO EM CAMPO", "0:00" } }, px(40, 56))
	row.frame.LayoutOrder = 5
	-- ganhos da vida em cartões (só aparecem se houver): XP, créditos, promoção e liberados
	local cards = Instance.new("Frame")
	cards.Name = "Ganhos"
	cards.BackgroundTransparency = 1
	cards.LayoutOrder = 6
	cards.Size = UDim2.new(1, 0, 0, px(64, 90))
	cards.Parent = top
	UiKit.list(cards, true, px(8, 12))
	local CARD_W = math.floor((LW - 3 * px(8, 12)) / 4)
	local pool = {}
	for i = 1, 4 do
		local c = UiKit.itemCard(cards, "", "", V.KHAKI, CARD_W)
		c.frame.LayoutOrder = i
		c.frame.Visible = false
		pool[i] = c
	end

	-- embaixo, empilhados na ordem de uso
	local buttons = Instance.new("Frame")
	buttons.Name = "Botoes"
	buttons.AnchorPoint = Vector2.new(0, 1)
	buttons.Position = UDim2.fromScale(0, 1)
	buttons.Size = UDim2.fromOffset(LW, 0)
	buttons.AutomaticSize = Enum.AutomaticSize.Y
	buttons.BackgroundTransparency = 1
	buttons.Parent = stage
	UiKit.list(buttons, false, px(6, 10))
	local actions: any = {} -- os cliques chegam depois (funções do fluxo, mais abaixo)
	local GAP = px(8, 12)
	local function pair(order: number, h: number): Frame
		local f = Instance.new("Frame")
		f.BackgroundTransparency = 1
		f.LayoutOrder = order
		f.Size = UDim2.new(1, 0, 0, h)
		f.Parent = buttons
		return f
	end
	local function half(a: any, right: boolean)
		a.button.AnchorPoint = Vector2.new(if right then 1 else 0, 0)
		a.button.Position = UDim2.fromScale(if right then 1 else 0, 0)
		a.button.Size = UDim2.new(0.5, -GAP // 2, 1, 0)
	end
	-- 1. RENASCER: o jogar agora (squad e último ponto), com a espera e a barra no botão
	local RH = px(72, 96)
	local respawn = UiKit.action(buttons, "RENASCER", "primary", function()
		actions.respawn()
	end, { h = RH })
	respawn.button.LayoutOrder = 1
	respawn.sub.TextSize = UiKit.text(px(26, 36))
	respawn.sub.FontFace = F.TITLE
	local rbar = Instance.new("Frame")
	rbar.Name = "Espera"
	rbar.AnchorPoint = Vector2.new(0, 1)
	rbar.Position = UDim2.fromScale(0, 1)
	rbar.Size = UDim2.new(0, 0, 0, px(5, 7))
	rbar.BackgroundColor3 = V.TEXT
	rbar.BackgroundTransparency = 0.2
	rbar.BorderSizePixel = 0
	rbar.Parent = respawn.button
	local dest = UiKit.text2(buttons, "", px(15, 22), V.DIM, F.BODY)
	dest.LayoutOrder = 2
	dest.Size = UDim2.new(1, 0, 0, px(20, 30))
	dest.TextTruncate = Enum.TextTruncate.AtEnd
	-- 2. no mesmo lugar: créditos e Robux, com o motivo à direita
	local hereHead = pair(3, px(20, 30))
	local hereKick = UiKit.kicker(hereHead, "NO MESMO LUGAR", px(15, 22), V.DIM)
	hereKick.Size = UDim2.fromScale(0.45, 1)
	local hereWhy = UiKit.text2(hereHead, "", px(15, 22), V.KHAKI, F.BODY)
	hereWhy.AnchorPoint = Vector2.new(1, 0)
	hereWhy.Position = UDim2.fromScale(1, 0)
	hereWhy.Size = UDim2.fromScale(0.62, 1)
	hereWhy.TextXAlignment = Enum.TextXAlignment.Right
	hereWhy.TextTruncate = Enum.TextTruncate.AtEnd
	local BH = px(46, 64)
	local hereRow = pair(4, BH)
	local hereCi = UiKit.action(hereRow, "Renascer aqui · créditos", "ci", function()
		actions.here("ci")
	end, { h = BH })
	half(hereCi, false)
	local hereRbx = UiKit.action(hereRow, "Renascer aqui · Robux", "robux", function()
		actions.here("robux")
	end, { h = BH })
	half(hereRbx, true)
	-- v43 (pedido do dono: "coloque o botão de renascer ali com Robux com cor chamativa"): verde vivo do
	-- Robux com borda dourada que pulsa. Travado (regra do setor, espera), fica num verde mais escuro
	-- com a borda, sem virar o painel apagado dos outros botões.
	do
		local GREEN, GREEN_HOT = Color3.fromRGB(0, 168, 104), Color3.fromRGB(18, 198, 128)
		local GREEN_OFF = Color3.fromRGB(24, 92, 66)
		local GOLD = Color3.fromRGB(255, 202, 64)
		local edge = hereRbx.button:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = GOLD
			edge.Thickness = px(2, 3)
			edge.Transparency = 0
			TweenService:Create(
				edge,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.55 }
			):Play()
		end
		hereRbx.realce.quente(GREEN_HOT)
		hereRbx.realce.base(GREEN)
		local plainEnabled = hereRbx.enabled
		hereRbx.enabled = function(v: boolean)
			plainEnabled(v)
			hereRbx.realce.base(if v then GREEN else GREEN_OFF)
			hereRbx.label.TextTransparency = if v then 0 else 0.25
		end
	end
	-- 3. com veículo e a carta
	local moreRow = pair(5, BH)
	local vehicle = UiKit.action(moreRow, "COM VEÍCULO", "secondary", function()
		actions.vehicleMenu()
	end, { h = BH })
	half(vehicle, false)
	local map = UiKit.action(moreRow, "ESCOLHER NA CARTA", "secondary", function()
		actions.map()
	end, { h = BH })
	half(map, true)
	-- 3b. as viaturas do lado (no lugar das linhas 2 e 3 enquanto aberto)
	local vehHead = pair(6, px(20, 30))
	vehHead.Visible = false
	local vehKick = UiKit.kicker(vehHead, "VEÍCULO AO NASCER", px(15, 22), V.DIM)
	vehKick.Size = UDim2.fromScale(0.4, 1)
	local vehWhy = UiKit.text2(vehHead, "", px(15, 22), V.KHAKI, F.BODY)
	vehWhy.AnchorPoint = Vector2.new(1, 0)
	vehWhy.Position = UDim2.fromScale(1, 0)
	vehWhy.Size = UDim2.fromScale(0.62, 1)
	vehWhy.TextXAlignment = Enum.TextXAlignment.Right
	vehWhy.TextTruncate = Enum.TextTruncate.AtEnd
	local vehGrid = Instance.new("Frame")
	vehGrid.Name = "Viaturas"
	vehGrid.BackgroundTransparency = 1
	vehGrid.LayoutOrder = 7
	vehGrid.Size = UDim2.new(1, 0, 0, 0)
	vehGrid.AutomaticSize = Enum.AutomaticSize.Y
	vehGrid.Visible = false
	vehGrid.Parent = buttons
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -GAP // 2, 0, px(44, 60))
	gl.CellPadding = UDim2.fromOffset(GAP, px(6, 10))
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = vehGrid
	-- uma linha por viatura e forma de pagar (até 2 viaturas x 2 formas) e o voltar; refeitas ao abrir
	local vehBtns: { any } = {}
	for i = 1, 4 do
		local b = UiKit.action(vehGrid, "", "ci", function()
			actions.vehicleOrder(i)
		end, { h = px(44, 60) })
		b.button.LayoutOrder = i
		b.button.Visible = false
		vehBtns[i] = b
	end
	local vehBack = UiKit.action(vehGrid, "◄ VOLTAR", "secondary", function()
		actions.vehicleMenu()
	end, { h = px(44, 60) })
	vehBack.button.LayoutOrder = 9
	-- 4. a fileira fina: mesa, loja, passe e missões
	local LH = px(36, 50)
	local lowRow = pair(8, LH)
	UiKit.list(lowRow, true, GAP)
	local function small(text: string, order: number, fn: () -> ()): any
		local a = UiKit.action(lowRow, text, "secondary", fn, { h = LH })
		a.button.LayoutOrder = order
		a.button.Size = UDim2.new(0.25, -GAP * 3 // 4, 1, 0)
		return a
	end
	local desk = small("MESA", 1, function()
		actions.desk()
	end)
	local shop = small("LOJA", 2, function()
		actions.shop()
	end)
	local pass = small("PASSE", 3, function()
		actions.pass()
	end)
	local missions = small("MISSÕES", 4, function()
		actions.missions()
	end)

	K = {
		bg = bg,
		side = side,
		stage = stage,
		fit = fit,
		scene = scene,
		sframe = sframe,
		top = top,
		who = who,
		title = title,
		cause = cause,
		note = note,
		stats = row.stats,
		cards = cards,
		pool = pool,
		buttons = buttons,
		respawn = respawn,
		rbar = rbar,
		dest = dest,
		hereHead = hereHead,
		hereWhy = hereWhy,
		hereRow = hereRow,
		hereCi = hereCi,
		hereRbx = hereRbx,
		moreRow = moreRow,
		vehicle = vehicle,
		map = map,
		vehHead = vehHead,
		vehWhy = vehWhy,
		vehGrid = vehGrid,
		vehBtns = vehBtns,
		vehBack = vehBack,
		vehOpts = {} :: { { spec: string, pay: string } },
		desk = desk,
		shop = shop,
		pass = pass,
		missions = missions,
		actions = actions,
		ciMethod = "ci",
	}
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
	local frac = math.clamp(downedFor() / downWindow(), 0, 1)
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

-- Lugar do cartão. No toque (v41, pedido do dono: "botoes estao em cima da outros"), a zona "caido"
-- do Shared/Toque, no pé à esquerda do DESISTIR (que fica no lugar do tiro); fora dele, embaixo no
-- meio, como sempre.
local function cardHome(): UDim2
	if ToqueUi.fitZone(D.card, D.fit.scale, "caido", D.w, D.h, Vector2.new(0.5, 1), 1, 0.4) then
		return D.card.Position
	end
	D.card.AnchorPoint = Vector2.new(0.5, 1)
	D.fit.scale.Scale = D.fit.k()
	return UDim2.new(0.5, 0, 1, -px(56, 80))
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
		D.cause.Text = Casualty.short(S.cause, true)
		-- o aviso do acerto pode chegar depois do atributo Downed: refaz a causa num instante
		local at = S.downedAt
		task.delay(0.4, function()
			if downGui.Enabled and S.downedAt == at then
				local c = currentCause()
				if c.kind ~= "unknown" then
					S.cause = c
					D.cause.Text = Casualty.short(c, true)
				end
			end
		end)
		local home = cardHome()
		D.card.Position = home + UDim2.fromOffset(0, D.h + px(136, 200))
		TweenService
			:Create(D.card, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = home })
			:Play()
	else
		S.downedAt = nil
	end
end

local medicCheck = 0
RunService.RenderStepped:Connect(function()
	if not downGui.Enabled then
		touchHoldAt = nil
		return
	end
	local t = downedFor()
	local window = downWindow()
	local left = math.max(0, window - t)
	local frac = math.clamp(t / window, 0, 1)
	local b = math.clamp(beat(os.clock(), Casualty.pulse(frac)), 0, 1)
	-- a visão fecha com o tempo e pulsa a cada batida
	D.tint.BackgroundTransparency = 1 - (0.12 + 0.32 * frac + 0.1 * b)
	D.vin.ImageTransparency = math.clamp(0.35 - 0.3 * frac - 0.25 * b, 0, 1)
	D.vin2.ImageTransparency = math.clamp(0.9 - 0.7 * frac, 0, 1)
	-- textos só quando mudam (o relógio anda de segundo em segundo; o resto é o pulso)
	local secs = math.floor(left)
	if secs ~= D.lastSecs then
		D.lastSecs = secs
		D.clock.Text = string.format("%d:%02d", secs // 60, secs % 60)
		D.clock.TextColor3 = if left < 15 then V.RED_HI else V.TEXT
	end
	D.fill.Size = UDim2.fromScale(left / window, 1)
	-- desistir (pedido do dono, 2026-11-13: "permita desistir quando morre sempre"): o anel e a
	-- tecla ficam sempre; se o Shared/Medical ainda pede uma espera, ela aparece no texto. Segurando
	-- B (1 s) ou H; no toque, segurando o botão DESISTIR do HUD de toque (1 s)
	local pad = Input.isGamepad()
	local touch = ToqueUi.active() and ToqueUi.hasVirtual()
	local wait = math.max(0, giveUpAfter() - t)
	D.key.Text = if pad then "B" elseif touch then "✕" else "H"
	local give: string
	-- o dedo no DESISTIR do toque: o anel conta daqui (o HUD manda a ação ao fim de 1 s)
	local vd = (Input :: any).virtualDown
	local fingerOn = touch and type(vd) == "function" and vd("give_up") == true
	if fingerOn and not touchHoldAt then
		touchHoldAt = os.clock()
	elseif not fingerOn then
		touchHoldAt = nil
	end
	D.ring.Visible = true
	if wait > 0 then
		give = string.format("Desistir em %d s", math.ceil(wait))
		D.ringGrad.Rotation = -90
	else
		local at = if pad then S.holdAt else touchHoldAt
		local holding = (pad or touch) and at ~= nil
		local p = if holding then math.clamp((os.clock() - (at :: number)) / 1.0, 0, 1) else 0
		D.ringGrad.Rotation = -90 + 360 * p
		give = if holding
			then "Desistindo…"
			elseif pad then "<b>Segure B</b> para desistir"
			elseif touch then "<b>Segure DESISTIR</b> para desistir"
			else "<b>H</b> para desistir"
	end
	if D.giveup.Text ~= give then
		D.giveup.Text = give
	end
	local now = os.clock()
	if now - medicCheck > 0.5 then
		medicCheck = now
		-- a tela girou ou o layout de toque mudou: o cartão volta ao lugar (depois da entrada)
		if S.downedAt and now - S.downedAt > 0.5 then
			D.card.Position = cardHome()
		end
		local d = nearestMedicM()
		D.medic.Text = if d
			then string.format(
				'<font color="#ACCE7E">Médico a ~%d m</font>: fique onde está',
				Casualty.roundDistance(d)
			)
			else "Sem médico perto: peça na roda (<b>Médico!</b>)"
	end
end)

-- ===== morto =====
-- Uma tela por vez. deathToken invalida a saída pendente se outra baixa chega no meio dela;
-- menuHeld garante um closeMenu para cada openMenu (antes, fechar duas vezes na mesma saída, pelo
-- renascer e pelo relógio, descontava o contador de menus duas vezes).
local deathToken = 0
local menuHeld = false
local REW = Progression.REWARDS
local PRODUCT = tonumber(Commerce.IDS and Commerce.IDS.PRODUCT_RESPAWN_INPLACE) or 0
-- preço em créditos no rótulo do ponto "Onde caiu (60 $)" (SpawnService: "%d %s", preço e moeda)
local PRICE_PAT = string.format("(%%d+) %s", (string.gsub(Progression.CUR, "%p", "%%%0")))

local function unlockedSet(s: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(s) == "table" and type(s.gear) == "table" then
		for _, g in s.gear do
			if type(g) == "table" and g.unlocked and type(g.id) == "string" then
				out[g.id] = true
			end
		end
	end
	return out
end

-- os ganhos chegam pelo Progress_State (uma mensagem por recompensa) e contam só em vida
Net.event("Progress_State").OnClientEvent:Connect(function(s: any)
	if type(s) ~= "table" then
		return
	end
	S.progress = s
	local L = S.life
	if not L.base then
		L.base = unlockedSet(s)
	end
	if S.deathCard then
		return
	end
	local g = s.gain
	if type(g) == "table" then
		if g.label == REW.kill.label then
			L.kills += 1
		elseif g.label == REW.assist.label then
			L.assists += 1
		end
		L.xp += tonumber(g.xp) or 0
		L.cr += tonumber(g.cr) or 0
	end
	local up = s.rankUp
	if type(up) == "table" and up.name ~= nil then
		table.insert(L.ranks, tostring(up.name))
	end
end)

-- espera dos pontos e o renascer onde caiu (o servidor manda a cada 1 s a quem está fora de campo)
Net.event("Spawn_State").OnClientEvent:Connect(function(list: any)
	if type(list) == "table" then
		S.spawns = list
		S.spawnsAt = os.clock()
	end
end)

-- preço do produto em Robux (uma vez) e o fim da compra
if PRODUCT ~= 0 then
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(PRODUCT, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" then
			S.robuxPrice = tonumber((info :: any).PriceInRobux)
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, bought: boolean)
			if userId == player.UserId and productId == PRODUCT and S.buying then
				S.buying = nil
				S.bought = bought -- o recibo vira um renascer guardado e o servidor renasce aqui
			end
		end
	)
end

-- ===== veículo ao nascer (D-103): estado do servidor =====
local vehPrice: { [number]: number } = {} -- preço em Robux por produto (-1 = buscando ou sem)
local function robuxOf(id: number): number?
	if id == 0 then
		return nil
	end
	local p = vehPrice[id]
	if p == nil then
		vehPrice[id] = -1
		task.spawn(function()
			local ok, inf = pcall(function()
				return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
			end)
			vehPrice[id] = if ok
					and type(inf) == "table"
					and type((inf :: any).PriceInRobux) == "number"
				then (inf :: any).PriceInRobux
				else -1
		end)
		return nil
	end
	return if p >= 0 then p else nil
end

local respawnQuick: (vehicle: boolean) -> ()

Net.event("Vehicle_OrderState").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" then
		return
	end
	S.veh = {
		spec = if type(msg.spec) == "string" then msg.spec else nil,
		state = if type(msg.state) == "string" then msg.state else "none",
		cooldown = if type(msg.cooldown) == "number" then msg.cooldown else 0,
		mine = if type(msg.mine) == "number" then msg.mine else 0,
		team = if type(msg.team) == "number" then msg.team else 0,
		at = os.clock(),
	}
	local want = S.vehWant
	if not (want and S.deathCard) then
		return
	end
	if msg.spec == want.spec and msg.state == "armed" then
		-- pedido armado: renasce num ponto onde o veículo sai (QG ou reunião), já
		S.vehWant = nil
		respawnQuick(true)
	elseif type(msg.msg) == "string" then
		S.vehWant = nil
		S.vehMsg = msg.msg -- recusa (falta crédito, espera, teto): fica na linha das viaturas
	end
end)

local function myCredits(): number
	local prog = S.progress
	if type(prog) == "table" and type(prog.credits) == "number" then
		return prog.credits
	end
	local c = player:GetAttribute("Credits")
	return if type(c) == "number" then c else 0
end

-- motivo de não poder pedir agora (o servidor confere de novo)
local function vehBlocked(): string?
	local v = S.veh
	if v.state == "reserved" then
		return "Compra em Robux esperando"
	end
	if v.mine >= CompraVeiculo.RULES.perPlayer and v.spec == nil then
		return "Você já tem um em campo"
	end
	if v.team >= CompraVeiculo.RULES.teamCap and v.spec == nil then
		return "Lado no teto de veículos"
	end
	local cd = math.max(0, math.ceil(v.cooldown - (os.clock() - v.at)))
	if cd > 0 then
		return string.format("Próximo veículo em %d s", cd)
	end
	return nil
end

local function inplaceEntry(): any
	for _, e in S.spawns do
		if type(e) == "table" and e.id == "inplace" then
			return e
		end
	end
	if S.dev then -- foto no Studio: o ponto de exemplo, liberado
		local me = myPos() or Vector3.zero
		return {
			id = "inplace",
			name = "Onde caiu (60 $)",
			x = me.X,
			z = me.Z,
			wait = 0,
			blocked = false,
			pay = "ci",
			dev = true,
		}
	end
	return nil
end

local function setLabel(b: any, text: string)
	if b.label.Text ~= text then
		b.label.Text = text
	end
end

local function setText(t: TextLabel, text: string)
	if t.Text ~= text then
		t.Text = text
	end
end

-- viaturas do lado no painel (nome e preço em créditos ou Robux, na cor de cada forma de pagar)
local function paintVehicles(armed: boolean)
	local f = player:GetAttribute("Faction")
	local list: { string } = if type(f) == "string" then CompraVeiculo.ORDER[f] or {} else {}
	local opts: { { spec: string, pay: string } } = {}
	for _, spec in list do
		table.insert(opts, { spec = spec, pay = "ci" })
		if CompraVeiculo.productId(spec) ~= 0 then
			table.insert(opts, { spec = spec, pay = "robux" })
		end
	end
	K.vehOpts = opts
	local why = vehBlocked()
	for i, b in K.vehBtns do
		local o = opts[i]
		b.button.Visible = o ~= nil
		if o then
			local item = CompraVeiculo.ITEMS[o.spec]
			local s = Vehicles.SPECS[o.spec]
			local name = UiKit.upper(if s then s.name else o.spec)
			b.setKind(o.pay)
			setLabel(b, name)
			local can = armed and why == nil and S.vehWant == nil
			if o.pay == "ci" then
				local short = item.credits - myCredits()
				b.sub.Text = Progression.money(item.credits)
				can = can and short <= 0
			else
				local p = robuxOf(CompraVeiculo.productId(o.spec))
				b.sub.Text = if p then string.format("%d Robux", p) else "Robux"
			end
			b.enabled(can)
		end
	end
	local status = if S.vehWant then "Armando o pedido…" else (S.vehMsg or why or "Sai ao seu lado: QG ou reunião")
	setText(K.vehWhy, status)
end

-- botões, a espera do RENASCER e o porquê do "no mesmo lugar" (4 vezes por segundo, tela aberta)
local function paintButtons()
	local armed = os.clock() >= S.skipFrom
	local vehicleArmed = S.veh.state == "armed"
	-- 1. renascer: a espera do ponto do jogar agora e a barra que enche
	local e, w = JogarAgora.preview(vehicleArmed)
	if w then
		S.waitMax = math.max(S.waitMax, w)
	end
	local sub = if w == nil then "" elseif w > 0.5 then string.format("%d s", math.ceil(w)) else "PRONTO"
	if K.respawn.sub.Text ~= sub then
		K.respawn.sub.Text = sub
	end
	local fill = if w == nil then 0 elseif S.waitMax > 0 then 1 - math.clamp(w / S.waitMax, 0, 1) else 1
	K.rbar.Size = UDim2.new(fill, 0, 0, K.rbar.Size.Y.Offset)
	setText(K.dest, if e or S.dev then JogarAgora.summary(vehicleArmed) else "Squad e último ponto de inserção")
	K.respawn.enabled(armed)
	K.map.enabled(armed)
	K.vehicle.enabled(armed)
	K.desk.enabled(armed)
	K.shop.enabled(armed)
	-- 2/3. o painel das viaturas fica no lugar do "mesmo lugar" e da linha do veículo
	local open = S.vehOpen
	K.vehHead.Visible = open
	K.vehGrid.Visible = open
	K.moreRow.Visible = not open
	if open then
		K.hereHead.Visible = false
		K.hereRow.Visible = false
		paintVehicles(armed)
		return
	end
	setLabel(
		K.vehicle,
		if vehicleArmed and S.veh.spec
			then string.format(
				"COM %s",
				UiKit.upper(Vehicles.SPECS[S.veh.spec] and Vehicles.SPECS[S.veh.spec].name or S.veh.spec)
			)
			else "COM VEÍCULO"
	)
	local inplace = inplaceEntry()
	K.hereHead.Visible = inplace ~= nil
	K.hereRow.Visible = inplace ~= nil
	if not inplace then
		return
	end
	local wait = math.max(0, (tonumber(inplace.wait) or 0) - (if inplace.dev then 0 else os.clock() - S.spawnsAt))
	local why: string? = if type(inplace.why) == "string" then inplace.why else nil
	-- bloqueio só de pagamento ("60 $: faltam 20") ou de regra (inimigo perto, QG, limite...)
	local payOnly = inplace.pay == nil and why ~= nil and string.find(why, "faltam", 1, true) ~= nil
	local rule = inplace.blocked == true and not payOnly
	local prog = S.progress
	local credits = if type(prog) == "table" then tonumber(prog.credits) or 0 else 0
	local stored = if type(prog) == "table"
		then tonumber(prog.respawnCredits) or 0
		else tonumber(player:GetAttribute("RespawnCredits")) or 0
	local raw = string.match(tostring(inplace.name or ""), PRICE_PAT) or string.match(why or "", PRICE_PAT)
	local price: number? = if raw then tonumber(raw :: any) else nil
	local ready = armed and not rule and wait <= 0 and not SpawnTransition.busy() and not S.bought
	if stored >= 1 then
		K.ciMethod = "credit" -- já pago (comprado em Robux antes): usa o guardado, sem cobrar
		K.hereCi.setKind("free")
		setLabel(K.hereCi, "Renascer aqui · guardado")
		K.hereCi.enabled(ready)
	elseif price then
		K.ciMethod = "ci"
		K.hereCi.setKind("ci")
		setLabel(K.hereCi, string.format("Renascer aqui · %s", Progression.money(price)))
		K.hereCi.enabled(ready and credits >= price)
	else
		K.ciMethod = "ci"
		K.hereCi.setKind("ci")
		setLabel(K.hereCi, "Renascer aqui · créditos")
		K.hereCi.enabled(false)
	end
	-- Robux só com o produto criado (ID 0: o botão de créditos ocupa a linha inteira)
	local rbxOn = PRODUCT ~= 0
	K.hereRbx.button.Visible = rbxOn
	K.hereCi.button.Size = if rbxOn then UDim2.new(0.5, -px(8, 12) // 2, 1, 0) else UDim2.fromScale(1, 1)
	local rp = S.robuxPrice
	setLabel(K.hereRbx, if rp then string.format("Renascer aqui · %d Robux", rp) else "Renascer aqui · Robux")
	K.hereRbx.enabled(ready and rbxOn and S.buying == nil)
	local status: string
	if S.buying then
		status = "Aguardando a compra…"
	elseif S.bought then
		status = "Compra feita: renascendo…"
	elseif rule and why then
		status = why
	elseif wait > 0 then
		status = string.format("pronto em %d s", math.ceil(wait))
	elseif payOnly and why then
		status = why
	else
		status = ""
	end
	setText(K.hereWhy, status)
end

-- botão do controle de cada ação; depois do UiKit, que limpa
local function paintGlyphs()
	local pad = Input.isGamepad()
	local function g(b: any, code: Enum.KeyCode)
		UiKit.setGlyph(b, if pad then UiKit.padImage(code) else nil)
	end
	g(K.respawn, Enum.KeyCode.ButtonA)
	g(K.hereCi, Enum.KeyCode.ButtonX)
	g(K.hereRbx, Enum.KeyCode.ButtonY)
	g(K.vehicle, Enum.KeyCode.ButtonR2)
	g(K.map, Enum.KeyCode.ButtonL2)
	g(K.desk, Enum.KeyCode.ButtonB)
	g(K.shop, Enum.KeyCode.ButtonR1)
	g(K.pass, Enum.KeyCode.DPadUp)
	g(K.missions, Enum.KeyCode.ButtonL1)
end
Input.DeviceChanged:Connect(function()
	task.defer(paintGlyphs)
end)

-- o A do controle aciona o botão de cima: foco nele (navegação do Roblox) ou o cursor virtual
local function focusOn(b: GuiObject)
	if not Input.isGamepad() then
		return
	end
	if VirtualCursor.isActive() then
		VirtualCursor.moveTo(b.AbsolutePosition + b.AbsoluteSize / 2 + GuiService:GetGuiInset())
	else
		GuiService.SelectedObject = b
	end
end

local function closeDeath(fast: boolean?)
	if not S.deathCard then
		return
	end
	S.deathCard = false
	S.vehOpen = false
	deathToken += 1
	local my = deathToken
	UiKit.closed("baixa")
	UiKit.release(deathGui)
	CenaBaixa.pause(K.scene)
	local t = if fast then 0.18 else 0.26
	local info = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(K.bg, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(K.side, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(K.stage, info, { Position = UDim2.new(0.5, 0, 0.5, px(36, 48)) }):Play()
	K.fit.play(info, 0.96)
	task.delay(t + 0.02, function()
		if deathToken ~= my then
			return
		end
		deathGui.Enabled = false
		S.dev = false
		Toast.hold(false) -- os avisos que esperaram a tela sair aparecem agora
		if menuHeld then
			menuHeld = false
			Input.closeMenu() -- o controle volta para a carta de inserção (ou para a mesa)
		end
	end)
end

-- ===== ações =====
local function canAct(): boolean
	return S.deathCard and os.clock() >= S.skipFrom
end

-- RENASCER: a carta de inserção por baixo e o jogar agora contando; entra sozinho na espera zerada
respawnQuick = function(vehicle: boolean)
	if not canAct() then
		return
	end
	if S.dev then
		closeDeath(false)
		return
	end
	DeployScreen.open("insert")
	closeDeath(false)
	JogarAgora.start({ vehicle = vehicle })
end
K.actions.respawn = function()
	respawnQuick(S.veh.state == "armed")
end
-- a carta de inserção, para escolher o ponto (como antes)
K.actions.map = function()
	if not canAct() then
		return
	end
	if not S.dev then
		DeployScreen.open("insert")
	end
	closeDeath(false)
end
K.actions.desk = function()
	if not canAct() then
		return
	end
	if not S.dev then
		DeployScreen.open("desk") -- a mesa: trocar de papel, de squad ou de equipamento
	end
	closeDeath(true)
end
-- atalho para a loja: a tela de baixa sai antes (nada de menu aberto por baixo da loja); no lobby
-- a câmera vai para a caixa de munição (painel "shop" da mesa), e a loja abre na aba da loja
K.actions.shop = function()
	if not canAct() then
		return
	end
	local dev = S.dev
	closeDeath(true)
	if not dev then
		DeployScreen.open("shop")
	end
	Bus.fire("shop_open", "loja")
end
-- o passe e as missões ficam por cima da tela de baixa (pilha do UiKit): fechar volta aqui
K.actions.pass = function()
	if canAct() then
		Bus.fire("passe_open")
	end
end
K.actions.missions = function()
	if canAct() then
		Bus.fire("missoes_open")
	end
end
-- abre e fecha as viaturas (no lugar do "mesmo lugar")
K.actions.vehicleMenu = function()
	if not canAct() then
		return
	end
	S.vehOpen = not S.vehOpen
	S.vehMsg = nil
	if S.vehOpen then
		Net.event("Vehicle_Order"):FireServer({ op = "get" })
	end
	paintButtons()
	focusOn(if S.vehOpen then K.vehBtns[1].button else K.vehicle.button)
end
-- pede a viatura (o servidor arma o pedido; armado, renasce num ponto onde ela sai)
K.actions.vehicleOrder = function(i: number)
	local o = K.vehOpts[i]
	local b = K.vehBtns[i]
	if not (canAct() and o and b and b.isEnabled()) then
		return
	end
	if S.dev then
		closeDeath(false)
		return
	end
	S.vehMsg = nil
	S.vehWant = { spec = o.spec, pay = o.pay, at = os.clock() }
	Net.event("Vehicle_Order"):FireServer({ spec = o.spec, pay = o.pay })
	local want = S.vehWant
	task.delay(4, function()
		if S.vehWant == want then
			S.vehWant = nil
			S.vehMsg = "Sem resposta do servidor"
		end
	end)
	paintButtons()
end
K.actions.here = function(kind: string)
	if not canAct() or SpawnTransition.busy() then
		return
	end
	local e = inplaceEntry()
	if not e or e.dev then
		return
	end
	if kind == "robux" then
		if not (K.hereRbx.isEnabled() and K.hereRbx.button.Visible) then
			return
		end
		-- o servidor confere as regras e abre a compra; o recibo vira um renascer guardado e ele
		-- renasce aqui sozinho (ProgressionService.onRespawnCredit -> SpawnService)
		local at = os.clock()
		S.buying, S.bought = at, false
		Net.event("Spawn_Request"):FireServer("inplace", "robux")
		task.delay(Progression.INPLACE.buyTimeoutS, function()
			if S.buying == at then
				S.buying = nil
			end
		end)
	else
		if not K.hereCi.isEnabled() then
			return
		end
		local method = K.ciMethod
		SpawnTransition.go({ id = "inplace", name = tostring(e.name), x = e.x, z = e.z }, function()
			Net.event("Spawn_Request"):FireServer("inplace", method)
		end)
	end
	paintButtons()
end

local function roleName(): string
	local r = player:GetAttribute("Role")
	local def = if type(r) == "string" and Roles.roles then Roles.roles[r] else nil
	return if def and def.name then def.name else tostring(r or "—")
end

-- números da vida contando do zero (um NumberValue por número, criados uma vez)
local counters: { NumberValue } = {}
do
	local fmts: { (number) -> string } = {
		function(v: number): string
			return string.format("%d", math.floor(v + 0.5))
		end,
		function(v: number): string
			return string.format("%d", math.floor(v + 0.5))
		end,
		function(v: number): string
			local s = math.floor(v + 0.5)
			return string.format("%d:%02d", s // 60, s % 60)
		end,
	}
	for i = 1, 3 do
		local nv = Instance.new("NumberValue")
		local label = K.stats[i].value :: TextLabel
		nv.Changed:Connect(function(v: number)
			label.Text = fmts[i](v)
		end)
		counters[i] = nv
	end
end

-- ganhos da vida em cartões: XP, créditos, promoção e equipamento liberado (até 4; nenhum: some)
local function fillGains()
	local L = S.life
	type Gain = { name: string, kind: string, mark: string, color: Color3 }
	local items: { Gain } = {}
	if L.xp > 0 then
		table.insert(items, { name = string.format("+%d", L.xp), kind = "XP", mark = "XP", color = V.KHAKI })
	end
	if L.cr > 0 then
		table.insert(
			items,
			{ name = string.format("+%s", Progression.money(L.cr)), kind = "CRÉDITOS", mark = "$", color = V.KHAKI }
		)
	end
	for _, r in L.ranks do
		table.insert(items, { name = r, kind = "PROMOÇÃO", mark = "★", color = V.BRASS })
	end
	local base, prog = L.base, S.progress
	if base and type(prog) == "table" and type(prog.gear) == "table" then
		for _, g in prog.gear do
			if type(g) == "table" and g.unlocked and type(g.id) == "string" and not base[g.id] then
				table.insert(
					items,
					{ name = tostring(g.name or g.id), kind = "LIBERADO", mark = "+", color = V.OLIVE_HI }
				)
			end
		end
	end
	for i, c in K.pool do
		local it = items[i]
		c.frame.Visible = it ~= nil
		if it then
			c.name.Text = it.name
			c.kind.Text = it.kind
			c.mark.Text = it.mark
			local strip = c.frame:FindFirstChild("Faixa")
			if strip and strip:IsA("Frame") then
				strip.BackgroundColor3 = it.color
			end
		end
	end
	K.cards.Visible = #items > 0
end

local function showDeath(cause: Casualty.Cause?, _where: Vector3?, note: string?)
	if S.deathCard then
		return
	end
	S.deathCard = true
	S.vehOpen, S.vehWant, S.vehMsg = false, nil, nil
	S.waitMax = 0
	deathToken += 1
	local my = deathToken
	deathGui.Enabled = true
	if not menuHeld then
		menuHeld = true
		Input.openMenu() -- até a tela sair, nada da carta de baixo responde
	end
	UiKit.opened("baixa", deathGui.DisplayOrder)
	-- os avisos (ganhos do abate, setores) esperam: a faixa deles saía por cima da tela (D-93)
	Toast.hold(true)
	GuiService.SelectedObject = nil
	-- quem era, a causa numa linha, o porquê (se houver)
	local sid = player:GetAttribute("SquadId")
	local squad = if type(sid) == "string" then (string.match(sid, ":(.+)$") or sid) else nil
	K.who.Text = if squad
		then string.format("%s · %s", UiKit.upper(roleName()), UiKit.upper(squad))
		else UiKit.upper(roleName())
	K.cause.Text = Casualty.short(cause, false)
	K.note.Text = note or ""
	K.note.Visible = note ~= nil
	-- números e ganhos
	local L = S.life
	local values = { L.kills, L.assists, math.max(0, os.clock() - S.spawnedAt) }
	for i, nv in counters do
		nv.Value = 0
		K.stats[i].value.Text = if i == 3 then "0:00" else "0"
		TweenService:Create(
			nv,
			TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.15 + (i - 1) * 0.08),
			{ Value = values[i] }
		):Play()
	end
	fillGains()
	-- o soldado caído: o retrato tirado em vida (farda e arma dele) ou, sem ele, o manequim do lado
	local snap = S.portrait
	S.portrait = nil
	local f = player:GetAttribute("Faction")
	CenaBaixa.show(K.scene, snap, if type(f) == "string" then f else nil)
	-- o estado do veículo (para o painel das viaturas e o RENASCER com o veículo armado)
	if not S.dev then
		task.spawn(function()
			Net.event("Vehicle_Order"):FireServer({ op = "get" })
		end)
	end
	-- entra: a cor sobe, o conteúdo desliza e assenta (0,3 s)
	K.stage.Position = UDim2.fromScale(0.5, 0.5)
	K.bg.BackgroundTransparency = 1
	K.side.BackgroundTransparency = 1
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(K.bg, info, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(K.side, info, { BackgroundTransparency = 0 }):Play()
	K.fit.play(TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), 1, 0.97)
	UiKit.enter({ K.top, K.buttons, K.sframe }, px(18, 24), 0.06)
	S.skipFrom = os.clock() + ARM_S
	paintGlyphs()
	paintButtons()
	task.spawn(function()
		local armed = false
		while S.deathCard and deathToken == my do
			paintButtons()
			if not armed and os.clock() >= S.skipFrom then
				armed = true
				focusOn(K.respawn.button)
			end
			task.wait(0.25)
		end
	end)
end

-- teclado e controle. Só com esta tela por cima (o menu do jogo aberto por cima usa o X dele).
UserInputService.InputBegan:Connect(function(io: InputObject)
	if not (deathGui.Enabled and S.deathCard) or UiKit.top() ~= "baixa" then
		return
	end
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local k = io.KeyCode
	if k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter or k == Enum.KeyCode.Space then
		if not typing then
			K.actions.respawn()
		end
	elseif k == Enum.KeyCode.ButtonX then
		K.actions.here("ci")
	elseif k == Enum.KeyCode.ButtonY then
		K.actions.here("robux")
	elseif k == Enum.KeyCode.ButtonR2 or (k == Enum.KeyCode.V and not typing) then
		K.actions.vehicleMenu()
	elseif k == Enum.KeyCode.ButtonL2 or (k == Enum.KeyCode.M and not typing) then
		K.actions.map()
	elseif k == Enum.KeyCode.ButtonR1 or (k == Enum.KeyCode.L and not typing) then
		K.actions.shop() -- RB no controle; L no teclado (o mesmo atalho da loja em campo)
	elseif k == Enum.KeyCode.ButtonL1 then
		K.actions.missions() -- LB: missões
	elseif k == Enum.KeyCode.DPadUp then
		K.actions.pass() -- direcional para cima: passe
	end
end)
Input.on("ui_back", "press", function()
	if S.deathCard and UiKit.backFor("baixa") then
		if S.vehOpen then
			K.actions.vehicleMenu() -- B com as viaturas abertas: só fecha o painel
		else
			K.actions.desk()
		end
	end
end)

-- ===== retrato do soldado, tirado em vida =====
-- Cópia do próprio personagem (farda, equipamento e arma dele), parada, sem scripts nem sons, com o
-- corpo visível (a 1ª pessoa o esconde por LocalTransparencyModifier). Tirada uma vez por vida,
-- quando o soldado está parado. A CenaBaixa a deita no chão na hora da baixa.
local function snapshot(char: Model): Model?
	local was = char.Archivable
	char.Archivable = true
	local ok, made = pcall(function()
		return char:Clone()
	end)
	char.Archivable = was
	if not ok or not made then
		return nil
	end
	local m = made :: Model
	for _, d in m:GetDescendants() do
		if
			d:IsA("BaseScript")
			or d:IsA("ModuleScript")
			or d:IsA("Sound")
			or d:IsA("ParticleEmitter")
			or d:IsA("Trail")
			or d:IsA("Beam")
			or d:IsA("Light")
			or d:IsA("BillboardGui")
			or d:IsA("Highlight")
			or d:IsA("ForceField")
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	if not m.PrimaryPart then
		local root = m:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			m.PrimaryPart = root
		end
	end
	return m
end

local function takePortrait(char: Model)
	task.wait(2.5)
	for _ = 1, 12 do
		if player.Character ~= char or not char.Parent then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if
			hum
			and hum.Health > 0
			and root
			and root:IsA("BasePart")
			and player:GetAttribute("Downed") ~= true
			and root.AssemblyLinearVelocity.Magnitude < 3
		then
			local m = snapshot(char)
			if m then
				local old = S.portrait
				if old then
					old:Destroy()
				end
				S.portrait = m
				return
			end
		end
		task.wait(1)
	end
end

-- ===== personagem =====
local function watch(char: Model)
	S.spawnedAt = os.clock()
	S.lastHit, S.lastBlast, S.lastMelee, S.cause = nil, nil, nil, nil
	S.medical = nil
	-- vida nova: números do zero; o que já estava liberado é a base dos "liberados"
	S.life = {
		kills = 0,
		assists = 0,
		xp = 0,
		cr = 0,
		ranks = {},
		base = if S.progress then unlockedSet(S.progress) else nil,
	}
	S.buying, S.bought = nil, false
	showDowned(false)
	if deathGui.Enabled and not S.dev then
		closeDeath(true) -- renasceu (reanimado pela transição, ou no mesmo lugar) com a tela aberta
	end
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	task.spawn(takePortrait, char)
	hum.Died:Connect(function()
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local where = if root then root.Position else nil
		local wasDowned = downGui.Enabled
		local downFor = downedFor()
		local diedAt = os.clock()
		local note: string? = nil
		if wasDowned and S.gaveUp then
			note = "Desistiu antes do socorro"
		elseif wasDowned and downFor >= downWindow() - 1 then
			note = "Sangrou sem socorro"
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
				local ml = S.lastMelee
				local latest = math.max(if h then h.t else 0, if bl then bl.t else 0, if ml then ml.t else 0)
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
-- tela de caído (20 s, com causa de exemplo); "morto" mostra a tela de baixa (com o retrato de agora
-- deitado no chão, números de exemplo e o "no mesmo lugar" liberado, sem cobrar nada); "veiculo" a
-- mesma com as viaturas abertas; "fim" fecha as duas.
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
		elseif v == "morto" or v == "veiculo" then
			S.dev = true
			showDowned(false)
			-- foto: o retrato de agora e números de exemplo se a vida ainda não rendeu nada
			local char = player.Character
			if not S.portrait and char then
				S.portrait = snapshot(char)
			end
			local L = S.life
			if L.kills == 0 and L.xp == 0 then
				L.kills, L.assists, L.xp, L.cr = 3, 1, 350, 35
			end
			showDeath(sample, myPos(), nil)
			if v == "veiculo" then
				S.vehOpen = true
				paintButtons()
			end
		elseif v == "fim" then
			S.dev = false
			showDowned(false)
			closeDeath(true)
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevQueda", nil)
		end)
	end)
	-- os mesmos pelo gancho comum das telas: VT65DevTela = "caido" ou "morto"
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if v == "caido" or v == "morto" then
			workspace:SetAttribute("VT65DevQueda", v)
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end

return CasualtyScreen
