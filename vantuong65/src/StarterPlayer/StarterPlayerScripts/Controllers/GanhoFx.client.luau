--!strict
-- D-237 (dono: "receba dinheiro e suba patentes igual no vídeo, com sons de ganhos de moedas e sons de
-- subir a patente"). O servidor segue sendo a fonte (Progress_State: gain, rankUp, xp). Aqui só se mostra:
--   - ganho: a moeda, o +$, o +XP e a barra até a próxima patente, somando enquanto a faixa está aberta;
--   - promoção: a faixa grande no meio da tela, com raios, faíscas e o toque de metais.
-- Studio: workspace "VT65DevGanho" = "ganho" ou "promocao".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression) :: any
local Bus = require(script.Parent.Bus)
local UiEfeitos = require(script.Parent.UiEfeitos)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local px = UiKit.px
local OURO = Color3.fromRGB(255, 206, 60)
local OURO_CLARO = Color3.fromRGB(255, 240, 170)
local MOSTRA_S = 2.6

local gui = UiKit.screen("VT65Ganhos", 34)
gui.IgnoreGuiInset = true
gui.DisplayOrder = 34

-- ===== sons (gravações da biblioteca do Roblox) =====
local function som(id: number, vol: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = vol
	s.SoundGroup = SoundService:FindFirstChild("VT65Efeitos") :: SoundGroup?
	s.Parent = SoundService
	return s
end
local somMoeda = som(AssetIds.Sounds.ganho_moeda, 0.8)
local somPromocao = som(AssetIds.Sounds.ganho_promocao, 1.1)
local ultimaMoeda = 0
local function tocaMoeda()
	local agora = os.clock()
	if agora - ultimaMoeda < 0.28 then
		return
	end
	ultimaMoeda = agora
	somMoeda.PlaybackSpeed = 0.96 + math.random() * 0.1
	somMoeda.TimePosition = 0
	somMoeda:Play()
end

-- ===== a faixa do ganho =====
local faixa = Instance.new("Frame")
faixa.Name = "Ganho"
faixa.AnchorPoint = Vector2.new(0.5, 0.5)
faixa.Position = UDim2.fromScale(0.5, 0.71)
faixa.Size = UDim2.fromOffset(px(420, 560), px(92, 122))
faixa.BackgroundTransparency = 1
faixa.Visible = false
faixa.Parent = gui
local faixaEscala = Instance.new("UIScale")
faixaEscala.Parent = faixa

local fundo = Instance.new("Frame")
fundo.Name = "Fundo"
fundo.Size = UDim2.fromScale(1, 1)
fundo.BackgroundColor3 = Color3.fromRGB(12, 13, 9)
fundo.BorderSizePixel = 0
fundo.Parent = faixa
do
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, 0.32),
		NumberSequenceKeypoint.new(0.78, 0.32),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = fundo
end

local moeda = Instance.new("ImageLabel")
moeda.Name = "Moeda"
moeda.BackgroundTransparency = 1
moeda.AnchorPoint = Vector2.new(0.5, 0.5)
moeda.Position = UDim2.new(0.5, -px(116, 154), 0, px(36, 48))
moeda.Size = UDim2.fromOffset(px(58, 76), px(58, 76))
moeda.ScaleType = Enum.ScaleType.Fit
moeda.Image = "rbxassetid://" .. tostring((AssetIds.Recompensas or {}).moeda or 0)
moeda.Parent = faixa

local valor = UiKit.title(faixa, "", px(42, 56), OURO_CLARO)
valor.Name = "Valor"
valor.Position = UDim2.new(0.5, -px(84, 112), 0, px(6, 8))
valor.Size = UDim2.fromOffset(px(150, 200), px(58, 76))
valor.TextXAlignment = Enum.TextXAlignment.Left
valor.TextStrokeTransparency = 0.45
do
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 190, 60))
	g.Parent = valor
end
local xpTxt = UiKit.title(faixa, "", px(26, 34), V.TEXT)
xpTxt.Name = "Xp"
xpTxt.Position = UDim2.new(0.5, px(52, 70), 0, px(4, 5))
xpTxt.Size = UDim2.fromOffset(px(130, 174), px(34, 44))
xpTxt.TextXAlignment = Enum.TextXAlignment.Left
xpTxt.TextStrokeTransparency = 0.5
local motivo = UiKit.rotulo(faixa, px(17, 23), V.KHAKI, F.TITLE_MED)
motivo.Name = "Motivo"
motivo.BackgroundTransparency = 1
motivo.Position = UDim2.new(0.5, px(52, 70), 0, px(36, 48))
motivo.Size = UDim2.fromOffset(px(150, 200), px(24, 32))
motivo.TextXAlignment = Enum.TextXAlignment.Left
motivo.TextTruncate = Enum.TextTruncate.AtEnd

local barra = Instance.new("Frame")
barra.Name = "Barra"
barra.AnchorPoint = Vector2.new(0.5, 1)
barra.Position = UDim2.new(0.5, 0, 1, -px(16, 20))
barra.Size = UDim2.fromOffset(px(300, 400), px(6, 8))
barra.BackgroundColor3 = Color3.fromRGB(46, 48, 36)
barra.BorderSizePixel = 0
barra.Parent = faixa
UiKit.corner(barra, 3)
local cheio = Instance.new("Frame")
cheio.Name = "Cheio"
cheio.Size = UDim2.fromScale(0, 1)
cheio.BackgroundColor3 = OURO
cheio.BorderSizePixel = 0
cheio.Parent = barra
UiKit.corner(cheio, 3)
local proxima = UiKit.rotulo(faixa, px(13, 17), V.DIM, F.TITLE_MED)
proxima.Name = "Proxima"
proxima.BackgroundTransparency = 1
proxima.AnchorPoint = Vector2.new(0.5, 1)
proxima.Position = UDim2.new(0.5, 0, 1, -px(0, 1))
proxima.Size = UDim2.fromOffset(px(300, 400), px(16, 20))
proxima.TextXAlignment = Enum.TextXAlignment.Center

local soma = { xp = 0, cr = 0, ate = 0, token = 0, mostrado = 0 }
local xpAtual: number? = nil

local function pintaBarra()
	if not xpAtual then
		barra.Visible, proxima.Visible = false, false
		return
	end
	local r, dentro, falta = Progression.progress(xpAtual)
	barra.Visible, proxima.Visible = true, true
	local f = if falta > 0 then math.clamp(dentro / falta, 0, 1) else 1
	TweenService:Create(cheio, TweenInfo.new(0.5, Enum.EasingStyle.Quart), { Size = UDim2.fromScale(f, 1) }):Play()
	local lado = player:GetAttribute("Faction")
	proxima.Text = if falta > 0
		then string.format(
			"%d / %d XP ATÉ %s",
			dentro,
			falta,
			UiKit.upper(Progression.rankName(if lado == "VC" then "VC" else "US", r + 1))
		)
		else "PATENTE MÁXIMA"
end

local function moedasVoando()
	if UiKit.Estilo.reduzMovimento() then
		return
	end
	local rng = Random.new()
	for _ = 1, 6 do
		local m = Instance.new("ImageLabel")
		m.BackgroundTransparency = 1
		m.Image = moeda.Image
		m.ScaleType = Enum.ScaleType.Fit
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		local lado = rng:NextInteger(px(18, 24), px(32, 42))
		m.Size = UDim2.fromOffset(lado, lado)
		m.Position = moeda.Position
		m.ZIndex = 4
		m.Parent = faixa
		local a = rng:NextNumber(-math.pi * 0.92, -math.pi * 0.08)
		local d = rng:NextNumber(px(40, 54), px(100, 132))
		local alvo = moeda.Position + UDim2.fromOffset(math.cos(a) * d, math.sin(a) * d)
		TweenService:Create(
			m,
			TweenInfo.new(rng:NextNumber(0.45, 0.75), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = alvo, ImageTransparency = 1, Rotation = rng:NextNumber(-220, 220) }
		):Play()
		task.delay(0.8, function()
			m:Destroy()
		end)
	end
end

local function contar(alvo: number, token: number)
	local de = soma.mostrado
	local t0 = os.clock()
	task.spawn(function()
		while soma.token == token do
			local u = math.clamp((os.clock() - t0) / 0.32, 0, 1)
			soma.mostrado = math.floor(de + (alvo - de) * (1 - (1 - u) ^ 3) + 0.5)
			valor.Text = string.format("+$ %d", soma.mostrado)
			if u >= 1 then
				return
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function ganho(label: string, xp: number, cr: number)
	if xp <= 0 and cr <= 0 then
		return
	end
	local agora = os.clock()
	if soma.ate < agora then
		soma.xp, soma.cr, soma.mostrado = 0, 0, 0
	end
	soma.xp += xp
	soma.cr += cr
	soma.ate = agora + MOSTRA_S
	soma.token += 1
	local my = soma.token
	moeda.Visible = soma.cr > 0
	valor.Visible = soma.cr > 0
	if soma.cr > 0 then
		contar(soma.cr, my)
		tocaMoeda()
		moedasVoando()
	end
	xpTxt.Text = if soma.xp > 0 then string.format("+%d XP", soma.xp) else ""
	motivo.Text = UiKit.upper(label)
	pintaBarra()
	faixa.Visible = true
	if UiKit.Estilo.reduzMovimento() then
		faixaEscala.Scale = 1
	else
		faixaEscala.Scale = 1.14
		TweenService:Create(faixaEscala, TweenInfo.new(0.24, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	task.delay(MOSTRA_S, function()
		if soma.token == my then
			faixa.Visible = false
		end
	end)
end

-- ===== a promoção =====
local function promocao(r: { [string]: any })
	local tela = Instance.new("Frame")
	tela.Name = "Promocao"
	tela.Size = UDim2.fromScale(1, 1)
	tela.BackgroundTransparency = 1
	tela.ClipsDescendants = true
	tela.ZIndex = 10
	tela.Parent = gui
	local alto = px(250, 330)
	local banda = Instance.new("Frame")
	banda.Name = "Banda"
	banda.AnchorPoint = Vector2.new(0.5, 0.5)
	banda.Position = UDim2.fromScale(0.5, 0.36)
	banda.Size = UDim2.new(1, 0, 0, 0)
	banda.BackgroundColor3 = Color3.fromRGB(10, 10, 7)
	banda.BackgroundTransparency = 0.08
	banda.BorderSizePixel = 0
	banda.ClipsDescendants = true
	banda.ZIndex = 10
	banda.Parent = tela
	do
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.1),
			NumberSequenceKeypoint.new(0.8, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = banda
	end
	for _, y in { 0, 1 } do
		local filete = Instance.new("Frame")
		filete.AnchorPoint = Vector2.new(0.5, y)
		filete.Position = UDim2.fromScale(0.5, y)
		filete.Size = UDim2.new(0.8, 0, 0, px(3, 4))
		filete.BackgroundColor3 = OURO
		filete.BorderSizePixel = 0
		filete.ZIndex = 13
		filete.Parent = banda
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = filete
	end
	local vp = gui.AbsoluteSize
	local centro = Vector2.new(vp.X / 2, vp.Y * 0.36)
	UiEfeitos.halo(tela, UDim2.fromOffset(centro.X, centro.Y), OURO, alto * 2.4, 0.38, 2, 10)
	local raios = UiEfeitos.raios(tela, centro, OURO, alto * 3.4, 6, 10, 10)
	UiEfeitos.onda(tela, centro, OURO_CLARO, alto * 1.8, 0.8, 11)
	UiEfeitos.faiscas(tela, centro, OURO, 60, { z = 12, tam = px(26, 34), vmin = 300, vmax = 980 })

	local t1 = UiKit.title(banda, "PROMOVIDO!", px(34, 46), OURO)
	t1.Position = UDim2.new(0, 0, 0.5, -px(104, 138))
	t1.Size = UDim2.new(1, 0, 0, px(42, 56))
	t1.TextXAlignment = Enum.TextXAlignment.Center
	t1.ZIndex = 14
	local nome = UiKit.title(
		banda,
		UiKit.upper(if r.name then tostring(r.name) else string.format("Posto %s", tostring(r.to))),
		px(66, 88),
		Color3.new(1, 1, 1)
	)
	nome.Position = UDim2.new(0, 0, 0.5, -px(62, 82))
	nome.Size = UDim2.new(1, 0, 0, px(80, 106))
	nome.TextXAlignment = Enum.TextXAlignment.Center
	nome.TextStrokeTransparency = 0.5
	nome.ZIndex = 14
	do
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(OURO_CLARO, Color3.fromRGB(224, 150, 40))
		g.Parent = nome
	end
	local pt = UiKit.rotulo(banda, px(20, 27), V.TEXT, F.BODY)
	pt.BackgroundTransparency = 1
	pt.Text = tostring(r.pt or "")
	pt.Position = UDim2.new(0, 0, 0.5, px(18, 24))
	pt.Size = UDim2.new(1, 0, 0, px(28, 36))
	pt.TextXAlignment = Enum.TextXAlignment.Center
	pt.ZIndex = 14
	local bonus = UiKit.title(banda, string.format("+$ %d", tonumber(r.bonus) or 0), px(38, 50), OURO)
	bonus.Position = UDim2.new(0, 0, 0.5, px(50, 66))
	bonus.Size = UDim2.new(1, 0, 0, px(46, 60))
	bonus.TextXAlignment = Enum.TextXAlignment.Center
	bonus.ZIndex = 14

	local info = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(banda, info, { Size = UDim2.new(1, 0, 0, alto) }):Play()
	UiEfeitos.clarao(tela, OURO_CLARO, 0.45, 0.5, 15)
	somPromocao.TimePosition = 0
	somPromocao:Play()
	task.delay(0.42, tocaMoeda)
	task.delay(4.4, function()
		TweenService:Create(
			banda,
			TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(1, 0, 0, 0) }
		):Play()
		raios:Destroy()
		task.delay(0.36, function()
			tela:Destroy()
		end)
	end)
end

-- ===== o que o servidor manda =====
Bus.on("ganho_fx", function(label: any, xp: any, cr: any)
	ganho(tostring(label or ""), tonumber(xp) or 0, tonumber(cr) or 0)
end)
Bus.on("promocao_fx", function(r: any)
	if type(r) == "table" then
		promocao(r)
	end
end)
Net.event("Progress_State").OnClientEvent:Connect(function(s: any)
	if type(s) == "table" and type(s.xp) == "number" then
		xpAtual = s.xp
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevGanho"):Connect(function()
		local v = workspace:GetAttribute("VT65DevGanho")
		if v == "ganho" then
			xpAtual = xpAtual or 130
			ganho("Abate", 100, 10)
		elseif v == "promocao" then
			promocao({ to = 3, name = "Lance Corporal", pt = "cabo de esquadra", bonus = 150 })
		end
	end)
end
