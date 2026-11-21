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

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiEfeitos = require(script.Parent.UiEfeitos)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer

-- D-236 (dono: "melhore oq eu apontei nas imagens com imagens melhores feitas com qualidade, efeitos
-- visuais"): cada dia mostra a arte do prêmio (tools/blender/recompensas.py), sobre uma cena do jogo; o
-- dia de hoje tem raios e brilho, e ao receber as moedas voam. Sem o ID, volta o desenho de emoji.
local function arteDia(i: number): string?
	local id = (AssetIds.Recompensas or {})["r" .. i]
	return if type(id) == "number" and id ~= 0 then "rbxassetid://" .. id else nil
end
local function arteMoeda(): string?
	local id = (AssetIds.Recompensas or {}).moeda
	return if type(id) == "number" and id ~= 0 then "rbxassetid://" .. id else nil
end
local V = UiKit.V
local px = UiKit.px

-- ===== medidas (projeto 1280 x 720; na TV, as da TV) =====
-- Lote 23 (dono: "melhore ainda mais as recompensas diárias e o passe, deixe elas mais atrativas para
-- crianças e deixe as escritas e principalmente as recompensas escritas maiores"):
--   - janela maior e letras ~1,4x maiores; o valor de cada dia em letra grande e dourada;
--   - cada dia com o desenho do prêmio: 💰 (créditos) ou 🎁 (presente); o 7º dia em dourado;
--   - o dia de hoje pisca e o desenho dele pula; o dia recebido ganha o ✔ verde;
--   - o botão é verde vivo e pulsa enquanto há prêmio; ao receber, moedas voam do cartão e o valor
--     sobe em letra grande.
local W, H = px(920, 1220), px(596, 790)
local PAD = px(24, 32)
local GAP = px(10, 14)
local CARD_Y = px(132, 176)
local CARD_H = px(264, 350)
local CARD_W = math.floor((W - 2 * PAD - 6 * GAP) / Commerce.TRACK_DAYS)
local BTN_H = px(76, 100)
local ICON_D = px(108, 142)
local OURO = Color3.fromRGB(255, 206, 60)
local OURO_ESCURO = Color3.fromRGB(92, 62, 12)
local VERDE = Color3.fromRGB(70, 190, 86)
local ROXO = Color3.fromRGB(170, 70, 210) -- presente
local HOJE_BG = Color3.fromRGB(70, 60, 30)

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
panel.ClipsDescendants = true
do -- D-236: a cena do arrozal ao fundo, escurecida para o texto ler bem
	local capa = (AssetIds.Capas or {}).arrozal
	if type(capa) == "number" and capa ~= 0 then
		local f = Instance.new("ImageLabel")
		f.Name = "Cena"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ScaleType = Enum.ScaleType.Crop
		f.Image = "rbxassetid://" .. capa
		f.ZIndex = -3
		f.Parent = panel
		local veu = Instance.new("Frame")
		veu.Name = "VeuCena"
		veu.BackgroundColor3 = Color3.fromRGB(14, 15, 11)
		veu.BorderSizePixel = 0
		veu.Size = UDim2.fromScale(1, 1)
		veu.ZIndex = -2
		veu.Parent = panel
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.34),
			NumberSequenceKeypoint.new(0.24, 0.18),
			NumberSequenceKeypoint.new(1, 0.04),
		})
		g.Parent = veu
	end
end
do -- faixa de latão no alto (é recompensa)
	local a = Instance.new("Frame")
	a.BackgroundColor3 = V.BRASS
	a.BorderSizePixel = 0
	a.Size = UDim2.new(1, 0, 0, px(3, 4))
	a.Parent = panel
end

local kick = UiKit.kicker(panel, "CADERNETA DE SERVIÇO", px(16, 22), V.BRASS)
kick.Position = UDim2.fromOffset(PAD, px(16, 22))
kick.Size = UDim2.fromOffset(px(360, 480), px(22, 30))
local title = UiKit.title(panel, "RECOMPENSA DIÁRIA", px(44, 58), Color3.new(1, 1, 1))
title.Position = UDim2.fromOffset(PAD, px(36, 48))
title.Size = UDim2.new(1, -2 * PAD, 0, px(54, 70))
do -- o título em ouro, com a luz de cima
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 170)),
		ColorSequenceKeypoint.new(0.55, OURO),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 130, 28)),
	})
	g.Parent = title
end
local rule = UiKit.body(panel, "Entre todo dia: o prêmio cresce! Pulou um dia, volta ao dia 1.", px(19, 25), V.TEXT)
rule.Position = UDim2.fromOffset(PAD, px(92, 122))
rule.Size = UDim2.new(1, -2 * PAD, 0, px(28, 36))

-- dias seguidos, à direita do título
local runStat = UiKit.stat(panel, "DIAS SEGUIDOS", "0", px(40, 54))
runStat.frame.AnchorPoint = Vector2.new(1, 0)
runStat.frame.Position = UDim2.new(1, -PAD, 0, px(18, 24))
runStat.label.TextXAlignment = Enum.TextXAlignment.Right
runStat.value.TextXAlignment = Enum.TextXAlignment.Right
runStat.value.TextColor3 = OURO

-- os sete dias
type Cell = {
	frame: Frame,
	scale: UIScale,
	stroke: UIStroke,
	day: TextLabel,
	icon: Frame,
	iconScale: UIScale,
	art: ImageLabel,
	mark: TextLabel,
	cash: TextLabel,
	item: TextLabel,
	tag: TextLabel,
}
local cells: { Cell } = {}
local function centered(t: TextLabel)
	t.TextXAlignment = Enum.TextXAlignment.Center
end
for i = 1, Commerce.TRACK_DAYS do
	local f = UiKit.panel(panel, V.PANEL_2, 0, true)
	f.Name = "Dia" .. i
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(PAD + (i - 1) * (CARD_W + GAP) + CARD_W // 2, CARD_Y + CARD_H // 2)
	f.Size = UDim2.fromOffset(CARD_W, CARD_H)
	local sc = Instance.new("UIScale")
	sc.Parent = f
	local st = f:FindFirstChildOfClass("UIStroke") :: UIStroke
	do -- luz caindo de cima no cartão
		local lg = Instance.new("UIGradient")
		lg.Rotation = 90
		lg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.72, 0.72, 0.72))
		lg.Parent = f
	end
	f.ClipsDescendants = true -- os raios do dia de hoje ficam dentro do cartão
	local d = UiKit.title(f, "DIA " .. i, px(22, 29))
	d.Position = UDim2.fromOffset(0, px(7, 9))
	d.Size = UDim2.new(1, 0, 0, px(26, 34))
	d.ZIndex = 4
	centered(d)
	-- a arte do prêmio (moedas, presente ou baú); o emoji só aparece sem a imagem
	local icon = Instance.new("Frame")
	icon.Name = "Premio"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, px(38, 50))
	icon.Size = UDim2.fromOffset(ICON_D, ICON_D)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ZIndex = 3
	icon.Parent = f
	local isc = Instance.new("UIScale")
	isc.Parent = icon
	local art = Instance.new("ImageLabel")
	art.Name = "Arte"
	art.BackgroundTransparency = 1
	art.Size = UDim2.fromScale(1, 1)
	art.ScaleType = Enum.ScaleType.Fit
	art.Image = arteDia(i) or ""
	art.Visible = art.Image ~= ""
	art.Parent = icon
	-- o ✔ de recebido fica no canto da arte; sem a imagem, este é o desenho do prêmio
	local mark = UiKit.title(icon, "💰", px(38, 50), V.TEXT)
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextYAlignment = Enum.TextYAlignment.Center
	mark.ZIndex = 2
	centered(mark)
	local cash = UiKit.title(f, "", px(30, 40), OURO)
	cash.Position = UDim2.fromOffset(0, px(150, 198))
	cash.Size = UDim2.new(1, 0, 0, px(36, 48))
	cash.ZIndex = 4
	centered(cash)
	local item = UiKit.body(f, "", px(15, 20), V.TEXT)
	item.Position = UDim2.fromOffset(px(4, 6), px(188, 250))
	item.Size = UDim2.new(1, -2 * px(4, 6), 0, px(44, 58))
	item.TextWrapped = true
	item.TextYAlignment = Enum.TextYAlignment.Top
	item.ZIndex = 4
	centered(item)
	item.TextTruncate = Enum.TextTruncate.AtEnd
	local tag = UiKit.tag(f, "", V.OLIVE, px(16, 21))
	tag.AnchorPoint = Vector2.new(0.5, 1)
	tag.Position = UDim2.new(0.5, 0, 1, -px(8, 10))
	tag.Visible = false
	tag.ZIndex = 5
	cells[i] = {
		frame = f,
		scale = sc,
		stroke = st,
		day = d,
		icon = icon,
		iconScale = isc,
		art = art,
		mark = mark,
		cash = cash,
		item = item,
		tag = tag,
	}
end

-- o que aconteceu (resgate, motivo da recusa, sequência zerada) e o aviso de sessão sem gravação
local result = UiKit.body(panel, "", px(20, 27), V.TEXT)
result.Position = UDim2.fromOffset(PAD, CARD_Y + CARD_H + px(10, 14))
result.Size = UDim2.new(1, -2 * PAD, 0, px(50, 66))
result.TextWrapped = true
local note = UiKit.body(panel, "", px(15, 20), V.RED_HI)
note.Position = UDim2.fromOffset(PAD, CARD_Y + CARD_H + px(60, 80))
note.Size = UDim2.new(1, -2 * PAD, 0, px(22, 30))

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

local mainBtn = UiKit.action(panel, "RESGATAR", "premio", function()
	if daily and daily.ready and daily.canClaim and not claimedNow then
		claim()
	elseif not busy then
		setOpen(false)
	end
end, { action = nil, ctx = nil, h = BTN_H })
mainBtn.button.Position = UDim2.fromOffset(PAD, H - PAD - BTN_H)
mainBtn.button.Size = UDim2.new(1, -2 * PAD, 0, BTN_H)
mainBtn.label.TextSize = UiKit.text(px(28, 36))
mainBtn.sub.TextSize = UiKit.text(px(26, 34))
mainBtn.sub.TextColor3 = OURO
UiKit.principal(mainBtn.button) -- D-205: o foco do controle abre no RESGATAR
local btnScale = Instance.new("UIScale")
btnScale.Parent = mainBtn.button

-- ===== animações (lote 23) =====
-- o botão pulsa enquanto há prêmio para pegar; o desenho do dia de hoje pula
local btnPulse: Tween? = nil
local function pulseButton(on: boolean)
	-- D-205 (§4, §20): com movimento reduzido nada pulsa sem parar
	if on and UiKit.Estilo.reduzMovimento() then
		return
	end
	if on and not btnPulse then
		btnScale.Scale = 1
		local t = TweenService:Create(
			btnScale,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.03 }
		)
		t:Play()
		btnPulse = t
	elseif not on and btnPulse then
		btnPulse:Cancel()
		btnPulse = nil
		btnScale.Scale = 1
	end
end
local bounceDay = 0
local bounce: Tween? = nil
local glow: Tween? = nil
local luzHoje: CanvasGroup? = nil -- D-236: raios, halo e cintilas do cartão de hoje (apagar para parar)
local function apagaLuz()
	if luzHoje then
		luzHoje:Destroy()
		luzHoje = nil
	end
end
local function acendeLuz(c: Cell)
	apagaLuz()
	-- CanvasGroup: o ClipsDescendants não corta peça girada, e os raios sairiam do cartão
	local q = Instance.new("CanvasGroup")
	q.Name = "LuzHoje"
	q.BackgroundTransparency = 1
	q.BorderSizePixel = 0
	q.Size = UDim2.fromScale(1, 1)
	q.ZIndex = 2
	q.Parent = c.frame
	luzHoje = q
	local cx, cy = CARD_W / 2, px(38, 50) + ICON_D / 2
	UiEfeitos.halo(q, UDim2.fromOffset(cx, cy), OURO, ICON_D * 1.5, 0.42, 1.8, 2)
	UiEfeitos.raios(q, Vector2.new(cx, cy), OURO, ICON_D * 2, 4, 12, 2)
	UiEfeitos.cintilas(q, Color3.fromRGB(255, 240, 190), 3, nil, 6)
	UiEfeitos.varre(q, 3.2, Color3.fromRGB(255, 236, 170), 6)
end
local function bounceToday(day: number)
	if day == bounceDay then
		return
	end
	if bounce then
		bounce:Cancel()
		bounce = nil
	end
	if glow then
		glow:Cancel()
		glow = nil
	end
	apagaLuz()
	local old = cells[bounceDay]
	if old then
		old.iconScale.Scale = 1
	end
	bounceDay = day
	local c = cells[day]
	if not c then
		return
	end
	acendeLuz(c) -- com movimento reduzido, os efeitos ficam parados
	if UiKit.Estilo.reduzMovimento() then
		c.stroke.Transparency = 0 -- o dia de hoje fica marcado, sem saltar nem piscar
		return
	end
	local b = TweenService:Create(
		c.iconScale,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.07 }
	)
	b:Play()
	bounce = b
	c.stroke.Transparency = 0
	local g = TweenService:Create(
		c.stroke,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.6 }
	)
	g:Play()
	glow = g
end

-- ao receber: moedas e brilhos voam do cartão do dia e o valor sobe em letra grande
local function burst(day: number, credits: number)
	local c = cells[day]
	if not c then
		return
	end
	local origin = c.frame.Position
	local rng = Random.new()
	-- movimento reduzido: sem moedas voando; o valor aparece no lugar e some devagar
	local parado = UiKit.Estilo.reduzMovimento()
	-- D-236: a onda de luz, as faíscas e as moedas de verdade (a arte), girando no ar
	local centro = Vector2.new(origin.X.Offset, origin.Y.Offset)
	UiEfeitos.onda(panel, centro, OURO, px(220, 290), 0.6, 19)
	UiEfeitos.faiscas(panel, centro, OURO, 34, { z = 19, tam = px(24, 32), vmin = 240, vmax = 720 })
	local moeda = arteMoeda()
	for i = 1, if parado then 0 else 16 do
		local a = rng:NextNumber(-math.pi * 0.95, -math.pi * 0.05) -- para cima, num leque
		local r = rng:NextNumber(px(110, 146), px(240, 316))
		local info = TweenInfo.new(rng:NextNumber(0.75, 1.15), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local alvo = origin + UDim2.fromOffset(math.cos(a) * r, math.sin(a) * r)
		local giro = rng:NextNumber(-260, 260)
		local lado = rng:NextInteger(px(34, 44), px(56, 74))
		local function posta(q: GuiObject)
			-- antes do tween: ele guarda a posição de partida ao tocar
			q.AnchorPoint = Vector2.new(0.5, 0.5)
			q.Size = UDim2.fromOffset(lado, lado)
			q.Position = origin
			q.ZIndex = 20
		end
		local t: GuiObject
		if moeda then
			local im = Instance.new("ImageLabel")
			im.BackgroundTransparency = 1
			im.Image = moeda
			im.ScaleType = Enum.ScaleType.Fit
			posta(im)
			im.Parent = panel
			TweenService:Create(im, info, { Position = alvo, ImageTransparency = 1, Rotation = giro }):Play()
			t = im
		else
			local tx = UiKit.title(panel, if i % 3 == 0 then "✨" else "💰", px(30, 40), V.TEXT)
			centered(tx)
			posta(tx)
			TweenService:Create(tx, info, { Position = alvo, TextTransparency = 1, Rotation = giro }):Play()
			t = tx
		end
		task.delay(1.25, function()
			t:Destroy()
		end)
	end
	local big = UiKit.title(panel, string.format("+$ %d", credits), px(54, 70), OURO)
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Size = UDim2.fromOffset(px(260, 340), px(64, 84))
	big.Position = origin
	big.TextStrokeTransparency = 0.2
	big.TextStrokeColor3 = Color3.new(0, 0, 0)
	centered(big)
	big.ZIndex = 21
	TweenService:Create(big, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = if parado then origin else origin - UDim2.fromOffset(0, px(130, 170)),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.6, function()
		big:Destroy()
	end)
end

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
	local claimedAll = ready and d.claimedToday == true
	for i, c in cells do
		local entry = Commerce.DailyTrack[i]
		c.cash.Text = string.format("+$ %d", entry.credits)
		local items = entry.items
		if items then
			local mine = if side then items[side] else nil
			c.item.Text = if mine then "+ " .. itemName(mine) else "+ presente surpresa"
		else
			c.item.Text = ""
		end
		local claimed = claimedAll
		local done = ready and (if claimed then i < day else (d.canClaim and i < day))
		local today = ready and i == day
		local last = i == Commerce.TRACK_DAYS
		local text, color = "", V.OLIVE
		if today and claimed then
			text, color = "RECEBIDO", VERDE
		elseif today then
			text, color = "HOJE!", OURO
		elseif done then
			text, color = "✔", VERDE
		elseif claimed and i == day % Commerce.TRACK_DAYS + 1 then
			text, color = "AMANHÃ", V.PANEL_3
		end
		c.tag.Visible = text ~= ""
		c.tag.Text = text
		c.tag.BackgroundColor3 = color
		c.tag.TextColor3 = if color == OURO then V.BG else V.TEXT
		-- o desenho: ✔ verde no que já foi recebido; senão moedas ou presente
		local got = done or (today and claimed)
		-- D-236: com a arte, o recebido fica apagado com um ✔ grande por cima
		local temArte = c.art.Image ~= ""
		c.art.ImageTransparency = if got then 0.62 else 0
		c.mark.Text = if got then "✔" elseif items then "🎁" else "💰"
		c.mark.Visible = got or not temArte
		c.mark.TextColor3 = if got and temArte then VERDE else V.TEXT
		c.mark.TextStrokeTransparency = if got and temArte then 0.25 else 1
		c.icon.BackgroundTransparency = if temArte then 1 else 0
		c.icon.BackgroundColor3 = if got then VERDE elseif items then ROXO else OURO
		c.frame.BackgroundColor3 = if today
			then HOJE_BG
			elseif last then OURO_ESCURO
			elseif done then Color3.fromRGB(34, 58, 34)
			else V.PANEL_2
		c.stroke.Color = if today then OURO elseif last then OURO else V.LINE
		c.stroke.Thickness = if today then 3 elseif last then 2 else 1
		if not today then
			c.stroke.Transparency = if last then 0.2 else 0.55
		end
		c.day.TextColor3 = if today then OURO else V.TEXT
		c.cash.TextColor3 = if got then V.TEXT else OURO
	end
	-- o dia de hoje pula e brilha enquanto o prêmio dele está para pegar
	bounceToday(if ready and d.canClaim and not claimedNow then day else 0)
	-- botão e texto
	local label, sub, on = "CONTINUAR", "", true
	if not ready then
		label, on = "LENDO A CADERNETA…", false
	elseif busy then
		label, on = "REGISTRANDO…", false
	elseif d.canClaim and not claimedNow then
		local entry = Commerce.DailyTrack[day]
		label = string.format("PEGAR O PRÊMIO DO DIA %d!", day)
		sub = string.format("+$ %d", entry.credits)
	end
	mainBtn.label.Text = label
	mainBtn.label.FontFace = UiKit.headFont(label)
	mainBtn.sub.Text = sub
	mainBtn.enabled(on)
	pulseButton(on and sub ~= "")
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
				local day = tonumber(s.result.day) or 1
				pop(day)
				local entry = Commerce.DailyTrack[day]
				local got = if type(s.result.credits) == "number" and s.result.credits > 0
					then s.result.credits
					else (entry and entry.credits or 0)
				burst(day, got)
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
		pulseButton(false)
		bounceToday(0)
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
