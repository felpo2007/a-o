--!strict
-- Tela de queda e de baixa (pedido do dono, 2026-11-11). Realismo da Parte 9.5: sem killcam e sem o
-- nome de quem atirou.
--   CAÍDO (atributo Downed): a visão escurece e pulsa no ritmo do coração (que acelera com o
--   sangramento), o relógio da janela de 60 s escoa, "segure B para desistir" (só depois de 15 s,
--   com o anel enchendo enquanto segura) e o aviso de médico do lado a até 80 m (ou como pedir um).
--   MORTO (estilo novo, 2026-11-11: sai a ficha datilografada): fundo vermelho escuro de cor única,
--   "BAIXA" enorme num retângulo de borda fina, a causa numa linha (Shared/Casualty: arma pelo som,
--   rumo em 8 setores e distância de ouvido), três números da vida (abates / assistências / tempo
--   em campo), os ganhos da vida em cartões (XP, créditos, promoção, equipamento liberado) e, à
--   direita, o próprio soldado inteiro (retrato tirado em vida: farda e arma dele), com luz de lado.
--   Embaixo: RENASCER (cheio, com a espera da onda) leva à carta de inserção; "no mesmo lugar" em
--   créditos ou Robux (regras e cobrança do servidor: Progression.inPlaceCheck/inPlacePay pelo
--   SpawnService, com o motivo quando bloqueado); VOLTAR À MESA e IR PARA A LOJA (finos, só
--   contorno; a loja abre com esta tela já fechada).
--   Controle: A renascer, X aqui com créditos, Y aqui com Robux, B mesa, RB loja. Teclado: Enter
--   renascer, Backspace/Esc mesa, L loja. Mouse e toque: os botões.
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
local Explosive = require(ReplicatedStorage.Shared.Explosive)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Medical = require(ReplicatedStorage.Shared.Medical)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Bus = require(script.Parent.Bus)
local DeployScreen = require(script.Parent.DeployScreen)
local Input = require(script.Parent.Input)
local SoldierPreview = require(script.Parent.SoldierPreview)
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
	lastMelee = nil :: any, -- golpe de arma branca recebido (Combat_Melee)
	holdAt = nil :: number?,
	gaveUp = false,
	spawnedAt = os.clock(),
	factionAt = 0,
	deathCard = false,
	dev = false,
	skipFrom = 0, -- os botões só valem depois de 1 s (quem morreu atirando não clica sem querer)
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
	UiKit.fit(downGui, card, CW, CH + px(56, 80), 12) -- janela estreita
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
	side.Size = UDim2.fromScale(0.5, 1)
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

	-- 680 de altura: cabe a fileira do passe e das missões sem encostar nos ganhos (o fit encolhe)
	local W, H = px(1180, 1600), px(680, 920)
	local stage = Instance.new("Frame")
	stage.Name = "Baixa"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(W, H)
	stage.BackgroundTransparency = 1
	stage.Parent = deathGui
	local fit = UiKit.fit(deathGui, stage, W, H, 24)

	-- à direita: o soldado inteiro, parado, com luz de lado (retrato tirado em vida)
	local PW = px(440, 600)
	local pv = SoldierPreview.newStill(-0.55)
	local pframe = pv.frame :: Frame
	pframe.AnchorPoint = Vector2.new(1, 0)
	pframe.Position = UDim2.fromScale(1, 0)
	pframe.Size = UDim2.new(0, PW, 1, 0)
	pframe.Parent = stage
	local pnote = pv.note :: TextLabel
	pnote.Text = ""

	-- à esquerda, de cima para baixo: quem era, BAIXA, a causa, os números e os ganhos
	local LW = W - PW - px(30, 40)
	local top = Instance.new("Frame")
	top.Name = "Topo"
	top.BackgroundTransparency = 1
	top.Size = UDim2.fromOffset(LW, 0)
	top.AutomaticSize = Enum.AutomaticSize.Y
	top.Parent = stage
	UiKit.list(top, false, px(8, 12))
	local who = UiKit.kicker(top, "", px(16, 24), V.DIM)
	who.LayoutOrder = 1
	who.Size = UDim2.new(1, 0, 0, px(22, 32))
	local titleBox, title = UiKit.titleBox(top, "BAIXA", px(84, 112), V.TEXT)
	titleBox.LayoutOrder = 2
	local cause = UiKit.text2(top, "", px(22, 30), V.TEXT, F.BODY_B)
	cause.LayoutOrder = 3
	cause.Size = UDim2.new(1, 0, 0, px(30, 42))
	cause.TextTruncate = Enum.TextTruncate.AtEnd
	local note = UiKit.text2(top, "", px(16, 24), V.KHAKI, F.BODY)
	note.LayoutOrder = 4
	note.Size = UDim2.new(1, 0, 0, px(20, 30))
	note.TextTruncate = Enum.TextTruncate.AtEnd
	local gap1 = Instance.new("Frame")
	gap1.BackgroundTransparency = 1
	gap1.Size = UDim2.fromOffset(1, px(6, 10))
	gap1.LayoutOrder = 5
	gap1.Parent = top
	local row =
		UiKit.statRow(top, { { "ABATES", "0" }, { "ASSISTÊNCIAS", "0" }, { "TEMPO EM CAMPO", "0:00" } }, px(54, 74))
	row.frame.LayoutOrder = 6
	local gap2 = gap1:Clone()
	gap2.LayoutOrder = 7
	gap2.Parent = top
	local gainsHead = UiKit.kicker(top, "GANHOS DESTA VIDA", px(15, 22), V.DIM)
	gainsHead.LayoutOrder = 8
	gainsHead.Size = UDim2.new(1, 0, 0, px(20, 30))
	local cards = Instance.new("Frame")
	cards.Name = "Ganhos"
	cards.BackgroundTransparency = 1
	cards.LayoutOrder = 9
	cards.Size = UDim2.new(1, 0, 0, px(64, 90))
	cards.Parent = top
	UiKit.list(cards, true, px(10, 14))
	-- cartões reaproveitados (nada é criado ao abrir): XP, créditos, promoção e liberados
	local CARD_W = math.floor((LW - 3 * px(10, 14)) / 4)
	local pool = {}
	for i = 1, 4 do
		local c = UiKit.itemCard(cards, "", "", V.KHAKI, CARD_W)
		c.frame.LayoutOrder = i
		c.frame.Visible = false
		pool[i] = c
	end
	local none = UiKit.text2(cards, "Nenhum ganho nesta vida", px(16, 24), V.MUTED, F.BODY)
	none.Size = UDim2.new(1, 0, 1, 0)
	none.LayoutOrder = 10
	none.Visible = false

	-- embaixo, empilhados: RENASCER (cheio, enorme), no mesmo lugar (dois), VOLTAR À MESA (fino)
	local BW = math.min(px(560, 760), LW)
	local buttons = Instance.new("Frame")
	buttons.Name = "Botoes"
	buttons.AnchorPoint = Vector2.new(0, 1)
	buttons.Position = UDim2.fromScale(0, 1)
	buttons.Size = UDim2.fromOffset(BW, 0)
	buttons.AutomaticSize = Enum.AutomaticSize.Y
	buttons.BackgroundTransparency = 1
	buttons.Parent = stage
	UiKit.list(buttons, false, px(8, 12))
	local actions: any = {} -- os cliques chegam depois (funções do fluxo, mais abaixo)
	local respawn = UiKit.action(buttons, "RENASCER", "primary", function()
		actions.respawn()
	end, { h = px(68, 92) })
	respawn.button.LayoutOrder = 1
	local hereHead = Instance.new("Frame")
	hereHead.BackgroundTransparency = 1
	hereHead.LayoutOrder = 2
	hereHead.Size = UDim2.new(1, 0, 0, px(20, 30))
	hereHead.Parent = buttons
	local hereKick = UiKit.kicker(hereHead, "NO MESMO LUGAR", px(15, 22), V.DIM)
	hereKick.Size = UDim2.fromScale(0.5, 1)
	local hereWhy = UiKit.text2(hereHead, "", px(15, 22), V.KHAKI, F.BODY)
	hereWhy.AnchorPoint = Vector2.new(1, 0)
	hereWhy.Position = UDim2.fromScale(1, 0)
	hereWhy.Size = UDim2.fromScale(0.62, 1)
	hereWhy.TextXAlignment = Enum.TextXAlignment.Right
	hereWhy.TextTruncate = Enum.TextTruncate.AtEnd
	local hereRow = Instance.new("Frame")
	hereRow.BackgroundTransparency = 1
	hereRow.LayoutOrder = 3
	hereRow.Size = UDim2.new(1, 0, 0, px(48, 66))
	hereRow.Parent = buttons
	local hereCi = UiKit.action(hereRow, "Renascer aqui · créditos", "secondary", function()
		actions.here("ci")
	end, { h = px(48, 66) })
	hereCi.button.Size = UDim2.new(0.5, -px(5, 7), 1, 0)
	local hereRbx = UiKit.action(hereRow, "Renascer aqui · Robux", "secondary", function()
		actions.here("robux")
	end, { h = px(48, 66) })
	hereRbx.button.AnchorPoint = Vector2.new(1, 0)
	hereRbx.button.Position = UDim2.fromScale(1, 0)
	hereRbx.button.Size = UDim2.new(0.5, -px(5, 7), 1, 0)
	-- os dois finos, lado a lado: a mesa e o atalho para a loja
	local lowRow = Instance.new("Frame")
	lowRow.BackgroundTransparency = 1
	lowRow.LayoutOrder = 4
	lowRow.Size = UDim2.new(1, 0, 0, px(40, 56))
	lowRow.Parent = buttons
	local desk = UiKit.action(lowRow, "VOLTAR À MESA", "secondary", function()
		actions.desk()
	end, { h = px(40, 56) })
	desk.button.Size = UDim2.new(0.5, -px(5, 7), 1, 0)
	local shop = UiKit.action(lowRow, "IR PARA A LOJA", "secondary", function()
		actions.shop()
	end, { h = px(40, 56) })
	shop.button.AnchorPoint = Vector2.new(1, 0)
	shop.button.Position = UDim2.fromScale(1, 0)
	shop.button.Size = UDim2.new(0.5, -px(5, 7), 1, 0)
	-- campanha (2026-11-12): o passe e as missões abrem POR CIMA desta tela (fecham e voltam aqui)
	local campRow = Instance.new("Frame")
	campRow.BackgroundTransparency = 1
	campRow.LayoutOrder = 5
	campRow.Size = UDim2.new(1, 0, 0, px(40, 56))
	campRow.Parent = buttons
	local pass = UiKit.action(campRow, "PASSE DE CAMPANHA", "secondary", function()
		actions.pass()
	end, { h = px(40, 56) })
	pass.button.Size = UDim2.new(0.5, -px(5, 7), 1, 0)
	local missions = UiKit.action(campRow, "MISSÕES", "secondary", function()
		actions.missions()
	end, { h = px(40, 56) })
	missions.button.AnchorPoint = Vector2.new(1, 0)
	missions.button.Position = UDim2.fromScale(1, 0)
	missions.button.Size = UDim2.new(0.5, -px(5, 7), 1, 0)

	K = {
		bg = bg,
		side = side,
		stage = stage,
		fit = fit,
		pv = pv,
		pframe = pframe,
		top = top,
		who = who,
		title = title,
		cause = cause,
		note = note,
		stats = row.stats,
		gainsHead = gainsHead,
		pool = pool,
		none = none,
		buttons = buttons,
		respawn = respawn,
		hereHead = hereHead,
		hereWhy = hereWhy,
		hereRow = hereRow,
		hereCi = hereCi,
		hereRbx = hereRbx,
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
		touchHoldAt = nil
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
	-- textos só quando mudam (o relógio anda de segundo em segundo; o resto é o pulso)
	local secs = math.floor(left)
	if secs ~= D.lastSecs then
		D.lastSecs = secs
		D.clock.Text = string.format("%d:%02d", secs // 60, secs % 60)
		D.clock.TextColor3 = if left < 15 then V.RED_HI else V.TEXT
	end
	D.fill.Size = UDim2.fromScale(left / window, 1)
	-- desistir: depois de 15 s (Medical.C.giveUpAfter), segurando B (1 s) ou H; no toque, segurando
	-- o botão DESISTIR do HUD de toque (1 s)
	local pad = Input.isGamepad()
	local touch = ToqueUi.active() and ToqueUi.hasVirtual()
	local wait = math.max(0, Medical.C.giveUpAfter - t)
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
	if wait > 0 then
		give = string.format("Desistir em %d s", math.ceil(wait))
		D.ringGrad.Rotation = -90
		D.ring.Visible = false
	else
		D.ring.Visible = true
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

-- a espera mais curta entre os pontos normais (a onda), descontado o tempo desde a mensagem
local function regularWait(): number?
	local best: number? = nil
	for _, e in S.spawns do
		if type(e) == "table" and e.id ~= "inplace" and not e.blocked and type(e.wait) == "number" then
			best = if best then math.min(best, e.wait) else e.wait
		end
	end
	if best == nil then
		return nil
	end
	return math.max(0, best - (os.clock() - S.spawnsAt))
end

local function setLabel(b: any, text: string)
	if b.label.Text ~= text then
		b.label.Text = text
	end
end

-- botões e o porquê do "no mesmo lugar" (4 vezes por segundo com a tela aberta)
local function paintButtons()
	local armed = os.clock() >= S.skipFrom
	local w = regularWait()
	local sub = if w == nil then "" elseif w > 0 then string.format("%d s", math.ceil(w)) else "PRONTO"
	if K.respawn.sub.Text ~= sub then
		K.respawn.sub.Text = sub
	end
	K.respawn.enabled(armed)
	K.desk.enabled(armed)
	K.shop.enabled(armed)
	local e = inplaceEntry()
	K.hereHead.Visible = e ~= nil
	K.hereRow.Visible = e ~= nil
	if not e then
		return
	end
	local wait = math.max(0, (tonumber(e.wait) or 0) - (if e.dev then 0 else os.clock() - S.spawnsAt))
	local why: string? = if type(e.why) == "string" then e.why else nil
	-- bloqueio só de pagamento ("60 $: faltam 20") ou de regra (inimigo perto, QG, limite...)
	local payOnly = e.pay == nil and why ~= nil and string.find(why, "faltam", 1, true) ~= nil
	local rule = e.blocked == true and not payOnly
	local prog = S.progress
	local credits = if type(prog) == "table" then tonumber(prog.credits) or 0 else 0
	local stored = if type(prog) == "table"
		then tonumber(prog.respawnCredits) or 0
		else tonumber(player:GetAttribute("RespawnCredits")) or 0
	local raw = string.match(tostring(e.name or ""), PRICE_PAT) or string.match(why or "", PRICE_PAT)
	local price: number? = if raw then tonumber(raw :: any) else nil
	local ready = armed and not rule and wait <= 0 and not SpawnTransition.busy() and not S.bought
	if stored >= 1 then
		K.ciMethod = "credit" -- já pago (comprado em Robux antes): usa o guardado
		setLabel(K.hereCi, "Renascer aqui · guardado")
		K.hereCi.enabled(ready)
	elseif price then
		K.ciMethod = "ci"
		setLabel(K.hereCi, string.format("Renascer aqui · %s", Progression.money(price)))
		K.hereCi.enabled(ready and credits >= price)
	else
		K.ciMethod = "ci"
		setLabel(K.hereCi, "Renascer aqui · créditos")
		K.hereCi.enabled(false)
	end
	local rp = S.robuxPrice
	setLabel(K.hereRbx, if rp then string.format("Renascer aqui · %d Robux", rp) else "Renascer aqui · Robux")
	K.hereRbx.enabled(ready and PRODUCT ~= 0 and S.buying == nil)
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
	if K.hereWhy.Text ~= status then
		K.hereWhy.Text = status
	end
end

-- botão do controle de cada ação (A renascer, X e Y aqui, B mesa); depois do UiKit, que limpa
local function paintGlyphs()
	local pad = Input.isGamepad()
	UiKit.setGlyph(K.respawn, if pad then UiKit.padImage(Enum.KeyCode.ButtonA) else nil)
	UiKit.setGlyph(K.hereCi, if pad then UiKit.padImage(Enum.KeyCode.ButtonX) else nil)
	UiKit.setGlyph(K.hereRbx, if pad then UiKit.padImage(Enum.KeyCode.ButtonY) else nil)
	UiKit.setGlyph(K.desk, if pad then UiKit.padImage(Enum.KeyCode.ButtonB) else nil)
	UiKit.setGlyph(K.shop, if pad then UiKit.padImage(Enum.KeyCode.ButtonR1) else nil)
	UiKit.setGlyph(K.pass, if pad then UiKit.padImage(Enum.KeyCode.DPadUp) else nil)
	UiKit.setGlyph(K.missions, if pad then UiKit.padImage(Enum.KeyCode.ButtonL1) else nil)
end
Input.DeviceChanged:Connect(function()
	task.defer(paintGlyphs)
end)

-- o A do controle aciona RENASCER: foco nele (navegação do Roblox) ou o cursor virtual em cima dele
local function focusPrimary()
	if not Input.isGamepad() then
		return
	end
	local b = K.respawn.button :: TextButton
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
	deathToken += 1
	local my = deathToken
	UiKit.closed("baixa")
	UiKit.release(deathGui)
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
K.actions.respawn = function()
	if not S.deathCard or os.clock() < S.skipFrom then
		return
	end
	if not S.dev then
		DeployScreen.open("insert") -- a carta de inserção, com a espera de cada ponto
	end
	closeDeath(false)
end
K.actions.desk = function()
	if not S.deathCard or os.clock() < S.skipFrom then
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
	if not S.deathCard or os.clock() < S.skipFrom then
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
	if S.deathCard and os.clock() >= S.skipFrom then
		Bus.fire("passe_open")
	end
end
K.actions.missions = function()
	if S.deathCard and os.clock() >= S.skipFrom then
		Bus.fire("missoes_open")
	end
end
K.actions.here = function(kind: string)
	if not S.deathCard or os.clock() < S.skipFrom or SpawnTransition.busy() then
		return
	end
	local e = inplaceEntry()
	if not e or e.dev then
		return
	end
	if kind == "robux" then
		if not K.hereRbx.isEnabled() then
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

-- ganhos da vida em cartões: XP, créditos, promoção e equipamento liberado (até 4)
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
	K.none.Visible = #items == 0
end

local function showDeath(cause: Casualty.Cause?, _where: Vector3?, note: string?)
	if S.deathCard then
		return
	end
	S.deathCard = true
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
	-- o soldado: o retrato tirado em vida (farda e arma dele) ou, sem ele, o manequim do lado
	local snap = S.portrait
	S.portrait = nil
	if snap then
		SoldierPreview.setModel(K.pv, snap)
	else
		SoldierPreview.setModel(K.pv, nil)
		local f, r = player:GetAttribute("Faction"), player:GetAttribute("Role")
		local los = if type(f) == "string" then Roles.loadout[f] else nil
		local lo = if los and type(r) == "string" then los[r] else nil
		SoldierPreview.set(K.pv, if type(f) == "string" then f else nil, if lo then lo[1] else nil)
	end
	-- entra: a cor sobe, o conteúdo desliza e assenta (0,3 s)
	K.stage.Position = UDim2.fromScale(0.5, 0.5)
	K.bg.BackgroundTransparency = 1
	K.side.BackgroundTransparency = 1
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(K.bg, info, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(K.side, info, { BackgroundTransparency = 0 }):Play()
	K.fit.play(TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), 1, 0.97)
	UiKit.enter({ K.top, K.buttons, K.pframe }, px(18, 24), 0.06)
	-- os botões só valem depois de 1 s (quem morreu atirando não clica sem querer)
	S.skipFrom = os.clock() + 1.0
	paintGlyphs()
	paintButtons()
	task.spawn(function()
		local armed = false
		while S.deathCard and deathToken == my do
			paintButtons()
			if not armed and os.clock() >= S.skipFrom then
				armed = true
				focusPrimary()
			end
			task.wait(0.25)
		end
	end)
end

-- teclado: Enter renascer; controle: X e Y no mesmo lugar (A vai pelo foco ou pelo cursor virtual,
-- B pelo "voltar"). Só com esta tela por cima (o menu do jogo aberto por cima usa o X dele).
UserInputService.InputBegan:Connect(function(io: InputObject)
	if not (deathGui.Enabled and S.deathCard) or UiKit.top() ~= "baixa" then
		return
	end
	local k = io.KeyCode
	if k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter or k == Enum.KeyCode.Space then
		if not UserInputService:GetFocusedTextBox() then
			K.actions.respawn()
		end
	elseif k == Enum.KeyCode.ButtonX then
		K.actions.here("ci")
	elseif k == Enum.KeyCode.ButtonY then
		K.actions.here("robux")
	elseif k == Enum.KeyCode.ButtonR1 or (k == Enum.KeyCode.L and not UserInputService:GetFocusedTextBox()) then
		K.actions.shop() -- RB no controle; L no teclado (o mesmo atalho da loja em campo)
	elseif k == Enum.KeyCode.ButtonL1 then
		K.actions.missions() -- LB: missões
	elseif k == Enum.KeyCode.DPadUp then
		K.actions.pass() -- direcional para cima: passe
	end
end)
Input.on("ui_back", "press", function()
	if S.deathCard and UiKit.backFor("baixa") then
		K.actions.desk()
	end
end)

-- ===== retrato do soldado, tirado em vida =====
-- Cópia do próprio personagem (farda, equipamento e arma dele), parada, sem scripts nem sons, com o
-- corpo visível (a 1ª pessoa o esconde por LocalTransparencyModifier). Tirada uma vez por vida,
-- quando o soldado está parado (a pose do clone é a da hora: em pé, com a arma).
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
		elseif wasDowned and downFor >= Medical.C.downWindow - 1 then
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
-- tela de caído (20 s, com causa de exemplo); "morto" mostra a tela de baixa (com o retrato de agora,
-- números de exemplo e o "no mesmo lugar" liberado, sem cobrar nada); "fim" fecha as duas.
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
