--!strict
-- D-193 (prompt de jogabilidade, itens 21 e 22): a tela do fim de partida, pelas fases do servidor
-- (Modules/RodadaService; atributos "VT65Fase" e "VT65FaseAte" em ReplicatedStorage, que valem para
-- quem entra no meio):
--   - comemoração: o time que venceu (ou o empate, sem inventar vencedor) e o pódio congelado
--     ("VT65Podio"): o 1º no meio e mais alto, o 2º e o 3º dos lados, cada um com o soldado (o
--     personagem dele, ou o manequim do lado se ele saiu), a colocação, o nome, os pontos e abates e
--     mortes. O soldado gira devagar. PLACEHOLDER: sem animação de comemoração ainda;
--   - votação: cada mapa que existe ("VT65Mapas", um só por enquanto), com a imagem da carta, o nome,
--     os votos ("VT65Votos") e o tempo; tocar, clicar ou A vota (pode trocar até o fim);
--   - restauração: "Preparando a próxima partida…"; depois a contagem de sempre (Controllers/Contagem).
-- Enquanto aberta, a tela segura o jogo como um menu (Input.openMenu).
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local V, F = UiKit.V, UiKit.F
local px = UiKit.px

local W, H = px(1100, 1500), px(600, 820)
local gui = UiKit.screen("VT65FimDeRodada", 46) -- acima do relatório de fim (FrontHud) e do HUD
gui.Enabled = false
local veil = Instance.new("Frame")
veil.Name = "Veu"
veil.Size = UDim2.fromScale(1, 1)
veil.BackgroundColor3 = V.BG
veil.BackgroundTransparency = 0.04 -- quase opaco: o relatório de trás não confunde a leitura
veil.BorderSizePixel = 0
veil.Active = true
veil.Parent = gui
local root = Instance.new("Frame")
root.Name = "Painel"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(W, H)
root.BackgroundTransparency = 1
root.Parent = gui
local fit = UiKit.fit(gui, root, W, H, 16)

local function label(parent: Instance, name: string, size: number, color: Color3, font: Font): TextLabel
	local t = UiKit.rotulo(parent, size, color, font)
	t.Name = name
	t.TextXAlignment = Enum.TextXAlignment.Center
	return t
end

-- ===== cabeçalho (as duas fases) =====
local kicker = label(root, "Fase", px(18, 26), V.BRASS, F.TITLE_REG)
kicker.Size = UDim2.new(1, 0, 0, px(24, 34))
local title = label(root, "Titulo", px(54, 76), V.TEXT, F.TITLE)
title.Position = UDim2.fromOffset(0, px(26, 36))
title.Size = UDim2.new(1, 0, 0, px(64, 90))
local clock = label(root, "Tempo", px(18, 26), V.DIM, F.TITLE_REG)
clock.Position = UDim2.fromOffset(0, px(92, 128))
clock.Size = UDim2.new(1, 0, 0, px(24, 34))

-- ===== pódio =====
local podium = Instance.new("Frame")
podium.Name = "Podio"
podium.BackgroundTransparency = 1
podium.Position = UDim2.fromOffset(0, px(130, 180))
podium.Size = UDim2.new(1, 0, 1, -px(130, 180))
podium.Parent = root

type Card = {
	f: Frame,
	vp: ViewportFrame,
	place: TextLabel,
	name: TextLabel,
	pts: TextLabel,
	kd: TextLabel,
	model: Model?,
}
-- colocação -> (x central em fração, altura em px, deslocamento para baixo)
local SLOT = {
	[1] = { x = 0.5, h = px(440, 610), down = 0 },
	[2] = { x = 0.2, h = px(390, 540), down = px(50, 70) },
	[3] = { x = 0.8, h = px(370, 510), down = px(70, 98) },
}
local CW = px(300, 410)
local cards: { Card } = {}
for i = 1, 3 do
	local s = SLOT[i]
	local f = UiKit.panel(podium, V.PANEL, 0.08)
	f.Name = string.format("Lugar%d", i)
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(s.x, 0, 0, s.down)
	f.Size = UDim2.fromOffset(CW, s.h)
	UiKit.edge(f, if i == 1 then V.BRASS else V.LINE, if i == 1 then 2 else 1, 0.1)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Soldado"
	vp.BackgroundTransparency = 1
	vp.Position = UDim2.fromOffset(px(8, 11), px(44, 60))
	vp.Size = UDim2.new(1, -px(16, 22), 1, -px(150, 206))
	vp.Ambient = Color3.fromRGB(140, 136, 124)
	vp.LightColor = Color3.fromRGB(255, 240, 220)
	vp.LightDirection = Vector3.new(-0.5, -0.8, -1)
	vp.Parent = f
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local place = label(f, "Colocacao", px(34, 48), if i == 1 then V.BRASS else V.KHAKI, F.TITLE)
	place.Position = UDim2.fromOffset(0, px(6, 8))
	place.Size = UDim2.new(1, 0, 0, px(38, 52))
	place.Text = string.format("%dº", i)
	local name = label(f, "Nome", px(22, 31), V.TEXT, F.TITLE_MED)
	name.AnchorPoint = Vector2.new(0, 1)
	name.Position = UDim2.new(0, px(8, 11), 1, -px(70, 96))
	name.Size = UDim2.new(1, -px(16, 22), 0, px(30, 42))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local pts = label(f, "Pontos", px(20, 28), V.KHAKI, F.TITLE)
	pts.AnchorPoint = Vector2.new(0, 1)
	pts.Position = UDim2.new(0, 0, 1, -px(40, 55))
	pts.Size = UDim2.new(1, 0, 0, px(26, 36))
	local kd = label(f, "Abates", px(15, 21), V.DIM, F.BODY)
	kd.AnchorPoint = Vector2.new(0, 1)
	kd.Position = UDim2.new(0, 0, 1, -px(14, 20))
	kd.Size = UDim2.new(1, 0, 0, px(22, 30))
	cards[i] = { f = f, vp = vp, place = place, name = name, pts = pts, kd = kd, model = nil }
end
local empty = label(podium, "Vazio", px(20, 28), V.DIM, F.BODY)
empty.Position = UDim2.fromScale(0, 0.4)
empty.Size = UDim2.new(1, 0, 0, px(30, 42))
empty.Text = "Ninguém do time que venceu fez pontos nesta partida."

-- ===== votação =====
local vote = Instance.new("Frame")
vote.Name = "Votacao"
vote.BackgroundTransparency = 1
vote.Position = UDim2.fromOffset(0, px(140, 194))
vote.Size = UDim2.new(1, 0, 1, -px(140, 194))
vote.Parent = root
local voteList = Instance.new("Frame")
voteList.Name = "Mapas"
voteList.BackgroundTransparency = 1
voteList.Size = UDim2.new(1, 0, 1, -px(40, 55))
voteList.Parent = vote
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, px(24, 34))
layout.Parent = voteList
local voteHint = label(vote, "Dica", px(17, 24), V.DIM, F.BODY)
voteHint.AnchorPoint = Vector2.new(0, 1)
voteHint.Position = UDim2.fromScale(0, 1)
voteHint.Size = UDim2.new(1, 0, 0, px(28, 38))

type MapCard = { b: TextButton, votes: TextLabel, mine: TextLabel, edge: UIStroke, id: string }
local mapCards: { MapCard } = {}
local myVote: string? = nil

local function mapCard(m: any): MapCard
	local b = Instance.new("TextButton")
	b.Name = "Mapa_" .. tostring(m.id)
	b.AutoButtonColor = false
	b.Text = ""
	b.Size = UDim2.fromOffset(px(420, 580), px(380, 520))
	b.BackgroundColor3 = V.PANEL
	b.BorderSizePixel = 0
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = voteList
	UiKit.corner(b, 6)
	local e = UiKit.edge(b, V.LINE, 2, 0.1)
	-- a carta tática inteira: os quatro blocos do CartaService (prefixo + nw, ne, sw, se), recortados
	-- no quadro do cartão
	local img = Instance.new("Frame")
	img.Name = "Carta"
	img.BackgroundColor3 = V.PANEL_2
	img.BorderSizePixel = 0
	img.ClipsDescendants = true
	img.Position = UDim2.fromOffset(px(10, 14), px(10, 14))
	img.Size = UDim2.new(1, -px(20, 28), 1, -px(110, 152))
	img.Parent = b
	UiKit.corner(img, 4)
	local square = Instance.new("Frame")
	square.Name = "Blocos"
	square.BackgroundTransparency = 1
	square.AnchorPoint = Vector2.new(0.5, 0.5)
	square.Position = UDim2.fromScale(0.5, 0.5)
	square.Size = UDim2.fromScale(1, 1)
	square.SizeConstraint = Enum.SizeConstraint.RelativeXX
	square.Parent = img
	for k, q in
		{
			{ id = "nw", x = 0, y = 0 },
			{ id = "ne", x = 0.5, y = 0 },
			{ id = "sw", x = 0, y = 0.5 },
			{ id = "se", x = 0.5, y = 0.5 },
		}
	do
		local t = Instance.new("ImageLabel")
		t.Name = string.format("Bloco%d", k)
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(q.x, q.y)
		t.Size = UDim2.fromScale(0.5, 0.5)
		local id = ReplicatedStorage:GetAttribute(tostring(m.carta) .. q.id)
		t.Image = if type(id) == "number" and id ~= 0 then string.format("rbxassetid://%d", id) else ""
		t.Parent = square
	end
	local name = label(b, "Nome", px(28, 39), V.TEXT, F.TITLE)
	name.AnchorPoint = Vector2.new(0, 1)
	name.Position = UDim2.new(0, 0, 1, -px(56, 78))
	name.Size = UDim2.new(1, 0, 0, px(36, 50))
	name.Text = UiKit.upper(tostring(m.nome))
	local votes = label(b, "Votos", px(18, 25), V.KHAKI, F.TITLE_REG)
	votes.AnchorPoint = Vector2.new(0, 1)
	votes.Position = UDim2.new(0, 0, 1, -px(30, 42))
	votes.Size = UDim2.new(1, 0, 0, px(24, 34))
	local mine = label(b, "SeuVoto", px(15, 21), V.BRASS, F.TITLE_MED)
	mine.AnchorPoint = Vector2.new(0, 1)
	mine.Position = UDim2.new(0, 0, 1, -px(6, 9))
	mine.Size = UDim2.new(1, 0, 0, px(22, 30))
	local c: MapCard = { b = b, votes = votes, mine = mine, edge = e, id = tostring(m.id) }
	UiKit.bind(b, function()
		if ReplicatedStorage:GetAttribute("VT65Fase") == "votacao" then
			myVote = c.id
			Net.event("Rodada_Votar"):FireServer(c.id)
		end
	end)
	return c
end

local function decode(attr: string): any
	local raw = ReplicatedStorage:GetAttribute(attr)
	if type(raw) ~= "string" then
		return nil
	end
	local ok, v = pcall(function(): any
		return HttpService:JSONDecode(raw)
	end)
	return if ok then v else nil
end

-- ===== o soldado de cada lugar =====
local function modelFor(id: string, lado: string): Model?
	local uid = tonumber(id)
	local p = if uid then Players:GetPlayerByUserId(uid) else nil
	local char = p and p.Character
	if char then
		local was = char.Archivable
		char.Archivable = true
		local ok, c = pcall(function(): Model
			return char:Clone()
		end)
		char.Archivable = was
		if ok and c then
			return c
		end
	end
	-- saiu (ou sem corpo agora): o manequim do lado, vestido pelo servidor
	local folder = ReplicatedStorage:FindFirstChild("VT65Preview")
	local m = folder and folder:FindFirstChild(lado)
	if m and m:IsA("Model") then
		return m:Clone()
	end
	return nil
end

local function setSoldier(card: Card, m: Model?)
	if card.model then
		card.model:Destroy()
		card.model = nil
	end
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	m:PivotTo(CFrame.identity)
	m.Parent = card.vp
	card.model = m
end

local spinT = 0
local function frameCards(dt: number)
	spinT += dt
	for i, c in cards do
		local m = c.model
		local cam = c.vp.CurrentCamera
		if m and cam and c.f.Visible then
			local cf, size = m:GetBoundingBox()
			-- gira devagar; o 1º um pouco mais rápido
			local a = spinT * (if i == 1 then 0.5 else 0.35) + i
			local d = size.Y / 2 / math.tan(math.rad(cam.FieldOfView / 2)) * 1.15
			local dir = Vector3.new(math.sin(a), 0.12, math.cos(a)).Unit
			cam.CFrame = CFrame.lookAt(cf.Position + dir * d, cf.Position)
		end
	end
end

local function showPodium()
	local data = decode("VT65Podio")
	local winner = if type(data) == "table" then tostring(data.vencedor) else "draw"
	kicker.Text = "FIM DA PARTIDA"
	if winner == "US" or winner == "VC" then
		-- frase inteira (a tradução não entra num modelo dentro de outro)
		title.Text = if winner == "US" then "VITÓRIA · FUZILEIROS DOS EUA" else "VITÓRIA · VIET CONG"
		title.TextColor3 = if winner == "US" then V.US else V.VC
	else
		title.Text = "EMPATE"
		title.TextColor3 = V.TEXT
	end
	local linhas = if type(data) == "table" and type(data.linhas) == "table" then data.linhas else {}
	for i, c in cards do
		local l = linhas[i]
		c.f.Visible = l ~= nil
		if l then
			c.name.Text = tostring(l.nome)
			c.pts.Text = string.format("%d pontos", tonumber(l.pontos) or 0)
			local a, m = tonumber(l.abates) or 0, tonumber(l.mortes) or 0
			-- frases inteiras, no singular quando é um (a tradução não entra num modelo dentro de outro)
			c.kd.Text = if a == 1 and m == 1
				then "1 abate · 1 morte"
				elseif a == 1 then string.format("1 abate · %d mortes", m)
				elseif m == 1 then string.format("%d abates · 1 morte", a)
				else string.format("%d abates · %d mortes", a, m)
			setSoldier(c, modelFor(tostring(l.id), tostring(l.lado)))
		else
			setSoldier(c, nil)
		end
	end
	empty.Visible = #linhas == 0
	podium.Visible = true
	vote.Visible = false
end

local function refreshVotes()
	local conta = decode("VT65Votos")
	for _, c in mapCards do
		local n = if type(conta) == "table" then tonumber(conta[c.id]) or 0 else 0
		c.votes.Text = if n == 1 then "1 voto" else string.format("%d votos", n)
		local mine = myVote == c.id
		c.mine.Text = if mine then "SEU VOTO" else ""
		c.edge.Color = if mine then V.BRASS else V.LINE
	end
end

local function showVote()
	kicker.Text = "PRÓXIMA PARTIDA"
	title.Text = "VOTAÇÃO DO MAPA"
	title.TextColor3 = V.TEXT
	for _, c in mapCards do
		c.b:Destroy()
	end
	table.clear(mapCards)
	myVote = nil
	local mapas = decode("VT65Mapas")
	if type(mapas) == "table" then
		for _, m in mapas do
			table.insert(mapCards, mapCard(m))
		end
	end
	refreshVotes()
	voteHint.Text = if Input.isGamepad()
		then "A vota · dá para trocar até o fim"
		elseif Input.touchActive() then "Toque no mapa para votar · dá para trocar até o fim"
		else "Clique no mapa para votar · dá para trocar até o fim"
	podium.Visible = false
	vote.Visible = true
	if Input.isGamepad() and mapCards[1] then
		GuiService.SelectedObject = mapCards[1].b
	end
end

-- ===== fases =====
local shown = false
local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	gui.Enabled = on
	if on then
		Input.openMenu()
		fit.play(TweenInfo.new(0.25, Enum.EasingStyle.Quint), 1, 0.96)
	else
		Input.closeMenu()
		UiKit.release(gui)
		for _, c in cards do
			setSoldier(c, nil)
		end
	end
end

local function onPhase()
	local f = ReplicatedStorage:GetAttribute("VT65Fase")
	if f == "comemoracao" then
		setShown(true)
		showPodium()
	elseif f == "votacao" then
		setShown(true)
		showVote()
	elseif f == "restauracao" then
		setShown(true)
		kicker.Text = "PRÓXIMA PARTIDA"
		title.Text = "PREPARANDO O CAMPO…"
		title.TextColor3 = V.TEXT
		podium.Visible = false
		vote.Visible = false
	else
		setShown(false)
	end
end
ReplicatedStorage:GetAttributeChangedSignal("VT65Fase"):Connect(onPhase)
ReplicatedStorage:GetAttributeChangedSignal("VT65Votos"):Connect(refreshVotes)
onPhase()

-- relógio da fase e o giro dos soldados
RunService.RenderStepped:Connect(function(dt: number)
	if not shown then
		return
	end
	local ate = ReplicatedStorage:GetAttribute("VT65FaseAte")
	if type(ate) == "number" then
		local s = math.max(0, math.ceil(ate - workspace:GetServerTimeNow()))
		clock.Text = string.format("%d s", s)
	else
		clock.Text = ""
	end
	if podium.Visible then
		frameCards(dt)
	end
end)
