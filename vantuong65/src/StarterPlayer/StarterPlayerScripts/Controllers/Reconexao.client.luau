--!strict
-- Avisos de ligação, no estilo novo das telas (painel escuro, título em Oswald, corpo em Arimo):
-- 1. Controle desconectado (Parte 12: a regra fica no Input, que pausa a entrada e volta com o
--    primeiro controle que apertar um botão): cartão no centro com o controle desenhado e a luz de
--    sinal piscando; a tela atrás escurece; etiqueta "PAUSADO". Escala para qualquer janela.
-- 2. Rede instável (Parte 13, celular trocando Wi-Fi ↔ dados ou sinal fraco): faixa pequena no alto,
--    sem travar nada. Quem segura a ligação é o Roblox; a faixa só avisa (Aparelho.netStep: quase
--    nada chegando do servidor por 2 s, ou latência alta por 3 s).
-- 3. Conexão perdida: o Roblox mostra a janela de erro dele por cima de tudo. Só nos erros de rede
--    (Aparelho.shouldRejoin: 277, 266, 279, 260 a 262; nunca expulsão, ociosidade, manutenção ou
--    servidor fechado) o jogo tenta voltar sozinho para a MESMA partida (TeleportToPlaceInstance com
--    o JobId), duas vezes, e depois para qualquer partida (Teleport). Uma faixa embaixo diz a
--    tentativa. Melhor esforço: o aviso de erro do GuiService (ErrorMessageChanged, GetErrorCode) não
--    está na referência pública e o teleporte pelo cliente está marcado como obsoleto (o TeleportAsync
--    é só do servidor); tudo protegido por pcall; fora do Studio só. A troca de rede leva alguns
--    segundos: a 1ª tentativa espera 3 s.
-- Nada é criado depois da montagem.
-- Studio: workspace:SetAttribute("VT65DevTela", "controle") mostra o cartão por 5 s; "rede" mostra a
-- faixa de rede instável e depois a de conexão perdida (sem teleporte), 4 s cada.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Aparelho = require(script.Parent.Aparelho)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local px = UiKit.px
local W, H = px(560, 820), px(232, 330)

local gui = UiKit.screen("VT65Reconexao", 100)
gui.IgnoreGuiInset = true

-- ===== 1. controle desconectado =====
local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Visible = false
dim.Parent = gui

local card = UiKit.panel(gui, V.PANEL, 0.04, true)
card.Name = "Controle"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(W, H)
card.Visible = false
local fit = UiKit.fit(gui, card, W, H, 24)
local stripe = Instance.new("Frame")
stripe.Size = UDim2.new(0, px(4, 6), 1, 0)
stripe.BackgroundColor3 = V.BRASS
stripe.BorderSizePixel = 0
stripe.Parent = card

local P = px(22, 32)
local head = UiKit.title(card, "LIGAÇÃO PERDIDA · CONTROLE DESCONECTADO", 20)
head.Position = UDim2.fromOffset(P, px(14, 20))
head.Size = UDim2.new(1, -2 * P, 0, px(28, 40))

-- o controle desenhado (corpo, punhos, analógicos) e a luz de sinal
local pad = Instance.new("Frame")
pad.Name = "Desenho"
pad.BackgroundTransparency = 1
pad.Position = UDim2.fromOffset(P, px(60, 86))
pad.Size = UDim2.fromOffset(px(130, 190), px(96, 140))
pad.Parent = card
local padEdges: { UIStroke } = {}
local function padPart(x: number, y: number, w: number, h: number, r: number)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = V.PANEL_2
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	f.Parent = pad
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r, 0)
	c.Parent = f
	table.insert(padEdges, UiKit.stroke(f, V.TEXT, px(2, 3), 0.15))
end
padPart(0.24, 0.62, 0.34, 0.62, 0.5) -- punho esquerdo
padPart(0.76, 0.62, 0.34, 0.62, 0.5) -- punho direito
padPart(0.5, 0.42, 0.9, 0.46, 0.45) -- corpo
padPart(0.32, 0.42, 0.14, 0.19, 1) -- analógico esquerdo
padPart(0.62, 0.58, 0.14, 0.19, 1) -- analógico direito
local light = Instance.new("Frame")
light.AnchorPoint = Vector2.new(0.5, 0.5)
light.Position = UDim2.fromScale(0.5, 0.26)
light.Size = UDim2.fromOffset(px(10, 14), px(10, 14))
light.BackgroundColor3 = V.BRASS
light.BorderSizePixel = 0
light.Parent = pad
UiKit.corner(light, 99)

local x0 = P + px(150, 214)
local body = UiKit.body(card, "Reconecte o controle e aperte qualquer botão para voltar.", 17, V.TEXT)
body.Position = UDim2.fromOffset(x0, px(60, 86))
body.Size = UDim2.new(1, -x0 - P, 0, px(70, 100))
local note = UiKit.body(card, "Seu soldado fica parado até lá. Teclado e mouse continuam valendo.", 14, V.DIM)
note.Position = UDim2.fromOffset(x0, px(134, 192))
note.Size = UDim2.new(1, -x0 - P - px(120, 170), 0, px(48, 68))

local stamp = UiKit.tag(card, "PAUSADO", V.RED, 15)
stamp.AnchorPoint = Vector2.new(1, 1)
stamp.Position = UDim2.new(1, -P, 1, -px(18, 26))
stamp.Size = UDim2.fromOffset(0, px(28, 40))

local shown = false
local loops: { Tween } = {}
local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	for _, t in loops do
		t:Cancel()
	end
	table.clear(loops)
	if on then
		dim.Visible = true
		card.Visible = true
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.4 }):Play()
		card.Position = UDim2.new(0.5, 0, 0.5, 30)
		TweenService:Create(card, UiKit.SOFT, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
		-- um tween de escala por vez (a janela mudando no meio assenta na escala nova)
		fit.play(UiKit.SOFT, 1, 0.95)
		-- a luz de sinal pisca e o desenho "procura" o controle
		local blink = TweenService:Create(
			light,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.85 }
		)
		blink:Play()
		table.insert(loops, blink)
		for _, e in padEdges do
			local t = TweenService:Create(
				e,
				TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.65 }
			)
			t:Play()
			table.insert(loops, t)
		end
	else
		local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(card, info, { Position = UDim2.new(0.5, 0, 0.5, 24) }):Play()
		fit.play(info, 0.94)
		task.delay(0.23, function()
			if not shown then
				dim.Visible = false
				card.Visible = false
			end
		end)
	end
end

-- ===== faixas de rede (alto: instável; embaixo: perdida) =====
local function strip(name: string, color: Color3, title: string): (Frame, TextLabel, Frame)
	local f = UiKit.panel(gui, V.PANEL, 0.08, true)
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Size = UDim2.fromOffset(px(380, 560), px(52, 74))
	f.Visible = false
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, px(14, 20), 0.5, 0)
	dot.Size = UDim2.fromOffset(px(10, 14), px(10, 14))
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.Parent = f
	UiKit.corner(dot, 99)
	local x = px(34, 48)
	local t = UiKit.title(f, title, 16, color)
	t.Position = UDim2.fromOffset(x, px(6, 8))
	t.Size = UDim2.new(1, -x - px(12, 16), 0, px(20, 28))
	local sub = UiKit.text2(f, "", 13, V.DIM, F.BODY)
	sub.Position = UDim2.fromOffset(x, px(27, 38))
	sub.Size = UDim2.new(1, -x - px(12, 16), 0, px(18, 26))
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	return f, sub, dot
end

local weak, weakSub, weakDot = strip("RedeInstavel", V.BRASS, "CONEXÃO INSTÁVEL")
weakSub.Text = "Esperando o sinal da partida"
local lost, lostSub, lostDot = strip("ConexaoPerdida", V.RED_HI, "CONEXÃO PERDIDA")
-- o alto fica abaixo da barra do Roblox; embaixo, longe da janela de erro dele (no centro)
local function placeStrips()
	local top = 0
	pcall(function()
		local inset = GuiService:GetGuiInset()
		top = inset.Y
	end)
	weak.Position = UDim2.new(0.5, 0, 0, top + 8)
	lost.AnchorPoint = Vector2.new(0.5, 1)
	lost.Position = UDim2.new(0.5, 0, 1, -px(24, 36))
end
placeStrips()

for _, d in { weakDot, lostDot } do
	TweenService:Create(d, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		BackgroundTransparency = 0.8,
	}):Play()
end

local function setWeak(on: boolean)
	if weak.Visible ~= on then
		weak.Visible = on
		if on then
			UiKit.enter({ weak }, -10)
		end
	end
end

-- ===== 3. conexão perdida: voltar para a mesma partida =====
local rejoin = { active = false, attempt = 0, token = 0 }

local function attempt()
	rejoin.attempt += 1
	rejoin.token += 1
	local my = rejoin.token
	local waitS, same = Aparelho.rejoinStep(rejoin.attempt)
	local max = #Aparelho.REJOIN_PLAN
	lost.Visible = true
	if not waitS then
		lostSub.Text = "Não deu para voltar. Use Reconectar na janela do Roblox."
		return
	end
	lostSub.Text = if same
		then string.format("Voltando para a mesma partida (%d de %d)", rejoin.attempt, max)
		else string.format("Voltando para uma partida (%d de %d)", rejoin.attempt, max)
	task.delay(waitS :: number, function()
		if my ~= rejoin.token then
			return
		end
		local ok = pcall(function()
			if same then
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
			else
				TeleportService:Teleport(game.PlaceId, player)
			end
		end)
		if not ok then
			attempt()
			return
		end
		-- sem resposta em 20 s (o pedido sumiu na rede): a próxima tentativa
		task.delay(20, function()
			if my == rejoin.token then
				attempt()
			end
		end)
	end)
end

TeleportService.TeleportInitFailed:Connect(function(plr: Player)
	if plr == player and rejoin.active then
		attempt()
	end
end)

local function startRejoin()
	if rejoin.active or RunService:IsStudio() or game.JobId == "" then
		return
	end
	rejoin.active = true
	setWeak(false)
	attempt()
end

-- o código do erro do Roblox (Enum.ConnectionError): nome e número
local function errorCode(): (string?, number?)
	local name, value = nil, nil
	for _, method in { "GetErrorCode", "GetErrorType" } do
		pcall(function()
			local code = (GuiService :: any)[method](GuiService)
			if typeof(code) == "EnumItem" then
				name, value = (code :: any).Name, (code :: any).Value
			elseif type(code) == "number" then
				value = code
			end
		end)
		if name or value then
			break
		end
	end
	return name, value
end

pcall(function()
	(GuiService :: any).ErrorMessageChanged:Connect(function()
		local name, value = errorCode()
		if Aparelho.shouldRejoin(name, value) then
			startRejoin()
		end
	end)
end)

-- ===== laço =====
local devUntil = 0
local devNet = { weakUntil = 0, lostUntil = 0 }
RunService.Heartbeat:Connect(function()
	local want = Input.state.disconnected == true or os.clock() < devUntil
	if want ~= shown then
		setShown(want)
	end
	if not rejoin.active and os.clock() >= devNet.lostUntil and lost.Visible then
		lost.Visible = false
	end
end)

-- sinal fraco: 2 amostras por segundo (no Studio só pelo gancho: a rede local não diz nada)
local net = Aparelho.newNet()
task.spawn(function()
	while true do
		task.wait(0.5)
		local isWeak = false
		if not RunService:IsStudio() then
			local recv: number? = nil
			local ping: number? = nil
			pcall(function()
				local v = (Stats :: any).DataReceiveKbps
				recv = if type(v) == "number" then v else nil
			end)
			pcall(function()
				ping = player:GetNetworkPing()
			end)
			isWeak = Aparelho.netStep(net, 0.5, recv, ping)
		end
		setWeak((isWeak or os.clock() < devNet.weakUntil) and not rejoin.active and not shown)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if v == "controle" then
			devUntil = os.clock() + 5
		elseif v == "rede" then
			devNet.weakUntil = os.clock() + 4
			task.delay(4, function()
				devNet.lostUntil = os.clock() + 4
				lost.Visible = true
				lostSub.Text = string.format("Voltando para a mesma partida (%d de %d)", 1, #Aparelho.REJOIN_PLAN)
			end)
		else
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
	end)
end
