--!strict
-- D-237 (dono: "receba dinheiro e suba patentes igual no vídeo, com sons de ganhos de moedas e sons de
-- subir a patente"). O servidor segue sendo a fonte (Progress_State: gain, rankUp, xp). Aqui só se mostra:
--   - ganho: a moeda, o +$, o +XP e a barra até a próxima patente, somando enquanto a faixa está aberta;
--   - promoção: o quadro de latão no alto da tela, com raios, faíscas e o toque de metais.
-- D-246 (dono: "esta muito grande e quero q aparaeça moedas na tela", "diminua o tamanho da caixa do
-- texto quando vc subir de patente", "coloque brilhos e sons melhores"): faixa e quadro menores, moedas
-- sextavadas girando pela tela, brilho que corre no latão e fanfarra com punhado de moedas.
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
local somPromocao = som(AssetIds.Sounds.ganho_fanfarra, 0.9)
local somPunhado = som(AssetIds.Sounds.ganho_moedas, 0.75)
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
faixa.Position = UDim2.fromScale(0.5, 0.74)
faixa.Size = UDim2.fromOffset(px(290, 380), px(62, 80))
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
moeda.Position = UDim2.new(0.5, -px(92, 122), 0, px(23, 30))
moeda.Size = UDim2.fromOffset(px(36, 46), px(36, 46))
moeda.ScaleType = Enum.ScaleType.Fit
moeda.Image = "rbxassetid://" .. tostring((AssetIds.Recompensas or {}).moeda or 0)
moeda.Parent = faixa

local valor = UiKit.title(faixa, "", px(27, 35), OURO_CLARO)
valor.Name = "Valor"
valor.Position = UDim2.new(0.5, -px(70, 92), 0, px(4, 5))
valor.Size = UDim2.fromOffset(px(100, 130), px(38, 50))
valor.TextXAlignment = Enum.TextXAlignment.Left
valor.TextStrokeTransparency = 0.45
do
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 190, 60))
	g.Parent = valor
end
local xpTxt = UiKit.title(faixa, "", px(17, 22), V.TEXT)
xpTxt.Name = "Xp"
xpTxt.Position = UDim2.new(0.5, px(34, 44), 0, px(4, 5))
xpTxt.Size = UDim2.fromOffset(px(96, 124), px(21, 27))
xpTxt.TextXAlignment = Enum.TextXAlignment.Left
xpTxt.TextStrokeTransparency = 0.5
local motivo = UiKit.rotulo(faixa, px(12, 16), V.KHAKI, F.TITLE_MED)
motivo.Name = "Motivo"
motivo.BackgroundTransparency = 1
motivo.Position = UDim2.new(0.5, px(34, 44), 0, px(24, 31))
motivo.Size = UDim2.fromOffset(px(100, 130), px(15, 19))
motivo.TextXAlignment = Enum.TextXAlignment.Left
motivo.TextTruncate = Enum.TextTruncate.AtEnd

local barra = Instance.new("Frame")
barra.Name = "Barra"
barra.AnchorPoint = Vector2.new(0.5, 1)
barra.Position = UDim2.new(0.5, 0, 1, -px(13, 17))
barra.Size = UDim2.fromOffset(px(210, 276), px(4, 5))
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
local proxima = UiKit.rotulo(faixa, px(10, 13), V.DIM, F.TITLE_MED)
proxima.Name = "Proxima"
proxima.BackgroundTransparency = 1
proxima.AnchorPoint = Vector2.new(0.5, 1)
proxima.Position = UDim2.new(0.5, 0, 1, -px(0, 1))
proxima.Size = UDim2.fromOffset(px(260, 340), px(12, 15))
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

-- D-246: as moedas saem da faixa, sobem girando pela tela e caem. Um só laço e imagens reaproveitadas.
local MOEDAS_MAX = 28
type Voando = {
	img: ImageLabel,
	x: number,
	y: number,
	vx: number,
	vy: number,
	fase: number,
	giro: number,
	lado: number,
	t: number,
	vida: number,
}
local voando: { Voando } = {}
local reserva: { ImageLabel } = {}
local laco: RBXScriptConnection? = nil
local ESCALA_VOO = px(100, 132) / 100
local GRAVIDADE = 1500

local function passoMoedas(dt: number)
	for i = #voando, 1, -1 do
		local c = voando[i]
		c.t += dt
		if c.t >= c.vida then
			c.img.Visible = false
			table.insert(reserva, c.img)
			table.remove(voando, i)
		else
			c.vy += GRAVIDADE * ESCALA_VOO * dt
			c.x += c.vx * dt
			c.y += c.vy * dt
			c.fase += c.giro * dt
			local u = c.t / c.vida
			c.img.Position = UDim2.fromOffset(c.x, c.y)
			c.img.Size = UDim2.fromOffset(c.lado * math.max(0.14, math.abs(math.cos(c.fase))), c.lado)
			c.img.ImageTransparency = if u > 0.72 then (u - 0.72) / 0.28 else 0
		end
	end
	if #voando == 0 and laco then
		laco:Disconnect()
		laco = nil
	end
end

local function moedasVoando(n: number, origem: Vector2?)
	if UiKit.Estilo.reduzMovimento() then
		return
	end
	local base = gui.AbsolutePosition
	local de = origem or (moeda.AbsolutePosition - base + moeda.AbsoluteSize / 2)
	local rng = Random.new()
	for _ = 1, math.min(n, MOEDAS_MAX - #voando) do
		local img = table.remove(reserva)
		if not img then
			local novo = Instance.new("ImageLabel")
			novo.Name = "MoedaVoando"
			novo.BackgroundTransparency = 1
			novo.Image = moeda.Image
			novo.ScaleType = Enum.ScaleType.Stretch
			novo.AnchorPoint = Vector2.new(0.5, 0.5)
			novo.ZIndex = 20
			novo.Parent = gui
			img = novo
		end
		local usada = img :: ImageLabel
		local lado = rng:NextNumber(px(17, 22), px(30, 38))
		usada.ImageTransparency = 0
		usada.Rotation = rng:NextNumber(-24, 24)
		usada.Position = UDim2.fromOffset(de.X, de.Y)
		usada.Size = UDim2.fromOffset(lado, lado)
		usada.Visible = true
		table.insert(voando, {
			img = usada,
			x = de.X + rng:NextNumber(-8, 8),
			y = de.Y + rng:NextNumber(-6, 6),
			vx = rng:NextNumber(-340, 340) * ESCALA_VOO,
			vy = rng:NextNumber(-860, -430) * ESCALA_VOO,
			fase = rng:NextNumber(0, math.pi),
			giro = rng:NextNumber(7, 15) * (if rng:NextNumber() < 0.5 then -1 else 1),
			lado = lado,
			t = 0,
			vida = rng:NextNumber(0.8, 1.25),
		})
	end
	if not laco then
		laco = RunService.RenderStepped:Connect(passoMoedas)
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
		moedasVoando(math.clamp(5 + math.floor(cr / 4), 6, 16))
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
	local largura, alto = px(370, 490), px(128, 168)
	local Y = 0.27
	local quadro = Instance.new("Frame")
	quadro.Name = "Quadro"
	quadro.AnchorPoint = Vector2.new(0.5, 0.5)
	quadro.Position = UDim2.fromScale(0.5, Y)
	quadro.Size = UDim2.fromOffset(largura, alto)
	quadro.BackgroundColor3 = Color3.fromRGB(20, 17, 10)
	quadro.BackgroundTransparency = 0.06
	quadro.BorderSizePixel = 0
	quadro.ClipsDescendants = true
	quadro.ZIndex = 12
	quadro.Parent = tela
	UiKit.corner(quadro, 4)
	do
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(66, 50, 24), Color3.fromRGB(16, 13, 8))
		g.Parent = quadro
		local latao = Instance.new("UIStroke")
		latao.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		latao.Color = Color3.new(1, 1, 1)
		latao.Thickness = px(2, 3)
		latao.Parent = quadro
		local gl = Instance.new("UIGradient")
		gl.Rotation = 35
		gl.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 96, 30)),
			ColorSequenceKeypoint.new(0.32, OURO_CLARO),
			ColorSequenceKeypoint.new(0.6, OURO),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 80, 24)),
		})
		gl.Parent = latao
	end
	local escala = Instance.new("UIScale")
	escala.Scale = 0.55
	escala.Parent = quadro

	local vp = gui.AbsoluteSize
	local centro = Vector2.new(vp.X / 2, vp.Y * Y)
	UiEfeitos.halo(tela, UDim2.fromOffset(centro.X, centro.Y), OURO, largura * 1.5, 0.45, 2, 10)
	local raios = UiEfeitos.raios(tela, centro, OURO, largura * 1.5, 5, 10, 10)
	UiEfeitos.onda(tela, centro, OURO_CLARO, largura * 0.9, 0.7, 11)
	UiEfeitos.faiscas(tela, centro, OURO, 34, { z = 13, tam = px(16, 21), vmin = 180, vmax = 620 })

	local t1 = UiKit.title(quadro, "PROMOVIDO!", px(15, 20), OURO)
	t1.Position = UDim2.fromOffset(0, px(7, 9))
	t1.Size = UDim2.new(1, 0, 0, px(19, 25))
	t1.TextXAlignment = Enum.TextXAlignment.Center
	t1.ZIndex = 14
	local nome = UiKit.title(
		quadro,
		UiKit.upper(if r.name then tostring(r.name) else string.format("Posto %s", tostring(r.to))),
		px(32, 42),
		Color3.new(1, 1, 1)
	)
	nome.Position = UDim2.fromOffset(px(10, 13), px(25, 33))
	nome.Size = UDim2.new(1, -px(20, 26), 0, px(40, 52))
	nome.TextXAlignment = Enum.TextXAlignment.Center
	nome.TextScaled = true
	nome.TextStrokeTransparency = 0.5
	nome.ZIndex = 14
	do
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = px(32, 42)
		c.Parent = nome
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(OURO_CLARO, Color3.fromRGB(224, 150, 40))
		g.Parent = nome
	end
	local pt = UiKit.rotulo(quadro, px(13, 17), V.TEXT, F.BODY)
	pt.BackgroundTransparency = 1
	pt.Text = tostring(r.pt or "")
	pt.Position = UDim2.fromOffset(0, px(65, 85))
	pt.Size = UDim2.new(1, 0, 0, px(17, 22))
	pt.TextXAlignment = Enum.TextXAlignment.Center
	pt.ZIndex = 14
	local icone = Instance.new("ImageLabel")
	icone.BackgroundTransparency = 1
	icone.Image = moeda.Image
	icone.ScaleType = Enum.ScaleType.Fit
	icone.AnchorPoint = Vector2.new(0.5, 0.5)
	icone.Position = UDim2.new(0.5, -px(48, 62), 0, px(103, 135))
	icone.Size = UDim2.fromOffset(px(28, 36), px(28, 36))
	icone.ZIndex = 14
	icone.Parent = quadro
	local bonus = UiKit.title(quadro, string.format("+$ %d", tonumber(r.bonus) or 0), px(23, 30), OURO)
	bonus.Position = UDim2.new(0.5, -px(30, 40), 0, px(88, 115))
	bonus.Size = UDim2.fromOffset(px(120, 158), px(30, 40))
	bonus.TextXAlignment = Enum.TextXAlignment.Left
	bonus.ZIndex = 14

	UiEfeitos.varre(quadro, 1.5, OURO_CLARO, 15, 0.22)
	UiEfeitos.cintilas(quadro, OURO_CLARO, 9, 3.2, 15)
	if UiKit.Estilo.reduzMovimento() then
		escala.Scale = 1
	else
		TweenService:Create(escala, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
	UiEfeitos.clarao(tela, OURO_CLARO, 0.2, 0.4, 9)
	somPromocao.Volume = 0.9
	somPromocao.TimePosition = 0
	somPromocao:Play()
	task.delay(0.16, function()
		somPunhado.TimePosition = 0
		somPunhado:Play()
		moedasVoando(22, centro + Vector2.new(0, alto * 0.25))
	end)
	task.delay(3.5, function()
		TweenService:Create(somPromocao, TweenInfo.new(0.9), { Volume = 0 }):Play()
		TweenService:Create(escala, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
			:Play()
		raios:Destroy()
		task.delay(0.28, function()
			tela:Destroy()
		end)
		task.delay(0.95, function()
			somPromocao:Stop()
			somPromocao.Volume = 0.9
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
