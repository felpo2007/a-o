--!strict
-- D-193 (prompt de jogabilidade, itens 21 e 22): a tela do fim de partida, pelas fases do servidor
-- (Modules/RodadaService; atributos "VT65Fase" e "VT65FaseAte" em ReplicatedStorage, que valem para
-- quem entra no meio):
--   - comemoração: o time que venceu (ou o empate, sem inventar vencedor) e o pódio congelado
--     ("VT65Podio"): o 1º no meio e mais alto, o 2º e o 3º dos lados, a colocação, o nome, os pontos e
--     abates e mortes. D-202: os três numa cena (Controllers/CenaComemoracao: palco de caixotes, o
--     pano do lado que venceu, fim de tarde), cada um com o soldado da partida (a cópia congelada no
--     fim, "VT65PodioModelos"; sem ela, o personagem de agora; quem saiu sem cópia, o manequim do
--     lado) comemorando com gestos variados (Shared/Comemoracao);
--   - votação: cada mapa que existe ("VT65Mapas", um só por enquanto), com a imagem da carta, o nome,
--     os votos ("VT65Votos") e o tempo; tocar, clicar ou A vota (pode trocar até o fim);
--   - restauração: "Preparando a próxima partida…"; depois a contagem de sempre (Controllers/Contagem).
-- Enquanto aberta, a tela segura o jogo como um menu (Input.openMenu).
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Comemoracao = require(ReplicatedStorage.Shared.Comemoracao)
local Horarios = require(ReplicatedStorage.Shared.Horarios)
local Net = require(ReplicatedStorage.Shared.Net)
local Cortina = require(game:GetService("ReplicatedFirst"):WaitForChild("Cortina"))
local ArteCatalogo = require(script.Parent.ArteCatalogo)
local CenaComemoracao = require(script.Parent.CenaComemoracao)
local PodioEfeitos = require(script.Parent.PodioEfeitos)
local PodioEpico = require(script.Parent.PodioEpico)
local Input = require(script.Parent.Input)
local UiEfeitos = require(script.Parent.UiEfeitos)
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

-- D-202: a cena (palco e soldados); embaixo, os cartões, um sob cada soldado
local stage = Instance.new("Frame")
stage.Name = "Palco"
stage.BackgroundTransparency = 1
stage.ClipsDescendants = true
-- D-221: a cena ocupa a tela inteira (fora da área segura também), atrás do título e dos cartões
stage.Size = UDim2.fromScale(1, 1)
stage.BackgroundColor3 = Color3.fromRGB(9, 11, 24)
stage.BackgroundTransparency = 0
local telaPalco = UiKit.screen("VT65PodioPalco", 45)
telaPalco.Enabled = false
pcall(function()
	telaPalco.ScreenInsets = Enum.ScreenInsets.None
end)
stage.Parent = telaPalco
local function syncPalco()
	local on = gui.Enabled and podium.Visible
	telaPalco.Enabled = on
	veil.BackgroundTransparency = if on then 1 else 0.04
end
gui:GetPropertyChangedSignal("Enabled"):Connect(syncPalco)
podium:GetPropertyChangedSignal("Visible"):Connect(syncPalco)
local cena = CenaComemoracao.nova(stage)
-- D-221: os efeitos em volta da cena: cada pouso acende o facho e dispara poeira e faíscas
local efeitos = PodioEfeitos.novo(stage, cena)
local epico = PodioEpico.novo(stage) -- D-240: VITÓRIA, os raios e os fogos
cena.aoPousar = function(lugar: number)
	efeitos:impacto(lugar)
end

type Card = {
	f: Frame,
	place: TextLabel,
	name: TextLabel,
	pts: TextLabel,
	kd: TextLabel,
}
-- os soldados ficam a ~20% da largura um do outro (Comemoracao.LUGARES): o cartão cabe em 18%
local CW, CH = px(196, 270), px(92, 126)
local cards: { Card } = {}
for i = 1, 3 do
	local f = UiKit.panel(podium, V.PANEL, 0.06)
	f.Name = string.format("Lugar%d", i)
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -px(2, 3))
	f.Size = UDim2.fromOffset(CW, CH)
	f.ZIndex = 3
	UiKit.edge(f, if i == 1 then V.BRASS else V.LINE, if i == 1 then 2 else 1, 0.1)
	-- colocação e nome na mesma linha; embaixo os pontos e os abates e mortes
	local place = label(f, "Colocacao", px(24, 33), if i == 1 then V.BRASS else V.KHAKI, F.TITLE)
	place.Position = UDim2.fromOffset(px(6, 8), px(4, 6))
	place.Size = UDim2.fromOffset(px(40, 55), px(30, 41))
	place.Text = string.format("%dº", i)
	local name = label(f, "Nome", px(18, 25), V.TEXT, F.TITLE_MED)
	name.Position = UDim2.fromOffset(px(48, 66), px(6, 8))
	name.Size = UDim2.new(1, -px(54, 74), 0, px(28, 39))
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local pts = label(f, "Pontos", px(17, 23), V.KHAKI, F.TITLE)
	pts.Position = UDim2.fromOffset(0, px(38, 52))
	pts.Size = UDim2.new(1, 0, 0, px(22, 30))
	local kd = label(f, "Abates", px(13, 18), V.DIM, F.BODY)
	kd.Position = UDim2.fromOffset(0, px(62, 85))
	kd.Size = UDim2.new(1, 0, 0, px(20, 27))
	for _, t in { place, name, pts, kd } do
		t.ZIndex = 4
	end
	cards[i] = { f = f, place = place, name = name, pts = pts, kd = kd }
end
-- D-214: o destaque do melhor da partida, quando a câmera chega perto dele (como nos jogos de
-- equipe: os três, depois o 1º comemorando)
local destaque = Instance.new("Frame")
destaque.Name = "Destaque"
destaque.Position = UDim2.fromOffset(px(20, 28), px(20, 28))
destaque.Size = UDim2.fromOffset(px(440, 600), px(132, 182))
destaque.BackgroundColor3 = V.BG
destaque.BackgroundTransparency = 0.25
destaque.BorderSizePixel = 0
destaque.Visible = false
destaque.ZIndex = 5
destaque.Parent = podium
UiKit.corner(destaque, 4)
local fundoDestaque = Instance.new("UIGradient")
fundoDestaque.Transparency = NumberSequence.new(0, 0.85)
fundoDestaque.Parent = destaque
local barraDestaque = Instance.new("Frame")
barraDestaque.Name = "Barra"
barraDestaque.BackgroundColor3 = V.BRASS
barraDestaque.BorderSizePixel = 0
barraDestaque.Size = UDim2.new(0, px(5, 7), 1, 0)
barraDestaque.ZIndex = 6
barraDestaque.Parent = destaque
local destaqueKicker = UiKit.rotulo(destaque, px(16, 22), V.BRASS, F.TITLE_MED)
destaqueKicker.Name = "Kicker"
destaqueKicker.Position = UDim2.fromOffset(px(20, 28), px(10, 14))
destaqueKicker.Size = UDim2.new(1, -px(28, 38), 0, px(22, 30))
destaqueKicker.Text = "★ MELHOR DA PARTIDA"
local destaqueNome = UiKit.rotulo(destaque, px(40, 56), V.TEXT, F.TITLE)
destaqueNome.Name = "Nome"
destaqueNome.Position = UDim2.fromOffset(px(20, 28), px(32, 44))
destaqueNome.Size = UDim2.new(1, -px(28, 38), 0, px(52, 72))
destaqueNome.TextTruncate = Enum.TextTruncate.AtEnd
local destaqueCom = UiKit.rotulo(destaque, px(15, 21), V.DIM, F.TITLE_REG)
destaqueCom.Name = "Comemoracao"
destaqueCom.Position = UDim2.fromOffset(px(20, 28), px(88, 122))
destaqueCom.Size = UDim2.new(1, -px(28, 38), 0, px(22, 30))
for _, t in { destaqueKicker, destaqueNome, destaqueCom } do
	t.ZIndex = 6
end
local destaquePos = destaque.Position
local temLinha = { false, false, false }
local destaqueFeito = false

local empty = label(podium, "Vazio", px(20, 28), V.TEXT, F.BODY)
empty.AnchorPoint = Vector2.new(0.5, 0.5)
empty.Position = UDim2.fromScale(0.5, 0.4)
empty.Size = UDim2.fromOffset(px(620, 850), px(44, 60))
empty.Text = "Ninguém do time que venceu fez pontos nesta partida."
-- em cima da cena: faixa escura para ler
empty.BackgroundColor3 = V.PANEL
empty.BackgroundTransparency = 0.2
empty.ZIndex = 3
UiKit.corner(empty, 4)

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
layout.SortOrder = Enum.SortOrder.LayoutOrder -- D-224: o mapa e, depois, os horários
layout.Padding = UDim.new(0, px(24, 34))
layout.Parent = voteList
local voteHint = label(vote, "Dica", px(17, 24), V.DIM, F.BODY)
voteHint.AnchorPoint = Vector2.new(0, 1)
voteHint.Position = UDim2.fromScale(0, 1)
voteHint.Size = UDim2.new(1, 0, 0, px(28, 38))

type MapCard = { b: TextButton, votes: TextLabel, mine: TextLabel, edge: UIStroke, id: string }
local mapCards: { MapCard } = {}
local myVote: string? = nil

local pintarHoras: () -> ()
-- D-224 (dono: "opções de horários do dia no mapa"): os quatro horários ao lado do mapa, com a pintura
-- de cada hora (tools/podio_fundo.py --horarios)
type HoraCard = { b: TextButton, votes: TextLabel, edge: UIStroke, id: string }
local horaCards: { HoraCard } = {}
local myHora: string? = nil
do
	local grade = Instance.new("Frame")
	grade.Name = "Horarios"
	grade.BackgroundTransparency = 1
	grade.Size = UDim2.fromOffset(px(620, 850), px(380, 520))
	grade.LayoutOrder = 99
	grade.Parent = voteList
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(px(304, 418), px(184, 254))
	g.CellPadding = UDim2.fromOffset(px(12, 14), px(12, 12))
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = grade
	for i, h in Horarios.LISTA do
		local b = Instance.new("TextButton")
		b.Name = "Hora_" .. h.id
		b.AutoButtonColor = false
		b.Text = ""
		b.BackgroundColor3 = V.PANEL
		b.BorderSizePixel = 0
		b.ClipsDescendants = true
		b.LayoutOrder = i
		b.Selectable = true
		b.SelectionImageObject = UiKit.FOCUS
		b.Parent = grade
		UiKit.corner(b, 6)
		local e = UiKit.edge(b, V.LINE, 2, 0.1)
		local im = Instance.new("ImageLabel")
		im.Name = "Imagem"
		im.BackgroundTransparency = 1
		im.ScaleType = Enum.ScaleType.Crop
		im.Size = UDim2.fromScale(1, 1)
		local idImg = (AssetIds.Catalogo or {})["hora_" .. h.id]
		im.Image = if type(idImg) == "number" and idImg ~= 0 then string.format("rbxassetid://%d", idImg) else ""
		im.Parent = b
		local veu = Instance.new("Frame")
		veu.BackgroundColor3 = Color3.new(0, 0, 0)
		veu.BorderSizePixel = 0
		veu.Size = UDim2.fromScale(1, 1)
		veu.Parent = b
		local vg = Instance.new("UIGradient")
		vg.Rotation = 90
		vg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.85),
			NumberSequenceKeypoint.new(1, 0.08),
		})
		vg.Parent = veu
		local nome = label(b, "Nome", px(27, 38), V.TEXT, F.TITLE)
		nome.TextXAlignment = Enum.TextXAlignment.Left
		nome.Position = UDim2.new(0, px(14, 20), 1, -px(76, 104))
		nome.Size = UDim2.new(1, -px(28, 40), 0, px(34, 46))
		nome.Text = h.nome
		local desc = label(b, "Desc", px(16, 22), V.DIM, F.BODY)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Position = UDim2.new(0, px(14, 20), 1, -px(42, 58))
		desc.Size = UDim2.new(0.68, 0, 0, px(24, 34))
		desc.Text = h.desc
		local votes = label(b, "Votos", px(17, 24), V.KHAKI, F.TITLE_MED)
		votes.TextXAlignment = Enum.TextXAlignment.Right
		votes.Position = UDim2.new(0.6, 0, 1, -px(42, 58))
		votes.Size = UDim2.new(0.4, -px(14, 20), 0, px(24, 34))
		local c: HoraCard = { b = b, votes = votes, edge = e, id = h.id }
		horaCards[i] = c
		UiKit.bind(b, function()
			if ReplicatedStorage:GetAttribute("VT65Fase") == "votacao" then
				myHora = c.id
				Net.event("Rodada_Votar"):FireServer(nil, c.id)
				pintarHoras()
			end
		end)
	end
end

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
local function copia(m: Instance): Model?
	if not m:IsA("Model") then
		return nil
	end
	local was = m.Archivable
	m.Archivable = true
	local ok, c = pcall(function(): Model
		return m:Clone()
	end)
	m.Archivable = was
	return if ok then c else nil
end

local function manequim(lado: string): Model?
	-- saiu (ou sem corpo agora): o manequim do lado, vestido pelo servidor
	local folder = ReplicatedStorage:FindFirstChild("VT65Preview")
	local m = folder and folder:FindFirstChild(lado)
	return if m then copia(m) else nil
end

local function modelFor(id: string, lado: string): Model?
	-- D-202: a cópia congelada no fim da partida (RodadaService), que vale mesmo se ele saiu
	local congelados = ReplicatedStorage:FindFirstChild("VT65PodioModelos")
	local frozen = congelados and congelados:FindFirstChild(id)
	if frozen then
		local c = copia(frozen)
		if c then
			return c
		end
	end
	local uid = tonumber(id)
	local p = if uid then Players:GetPlayerByUserId(uid) else nil
	local char = p and p.Character
	if char then
		local c = copia(char)
		if c then
			return c
		end
	end
	return manequim(lado)
end

local function showPodium()
	local data = decode("VT65Podio")
	local winner = if type(data) == "table" then tostring(data.vencedor) else "draw"
	kicker.Text = "FIM DA PARTIDA"
	if winner == "US" or winner == "VC" then
		-- frase inteira (a tradução não entra num modelo dentro de outro)
		title.Text = if winner == "US" then "VITÓRIA · FUZILEIROS DOS EUA" else "VITÓRIA · VIET CONG"
		-- D-221: mais claro: agora o título fica sobre o céu da cena
		title.TextColor3 = (if winner == "US" then V.US else V.VC):Lerp(Color3.new(1, 1, 1), 0.5)
		-- D-240: a bandeira do vencedor já é a arte do fundo; um mastro 3D na frente dela a repetiria
		if ArteCatalogo.time(winner) ~= "" then
			cena:bandeira({})
		else
			cena:bandeira(
				{ if winner == "US" then V.US else V.VC },
				{ if winner == "US" then "bandeira_eua" else "bandeira_frente" }
			)
		end
	else
		title.Text = "EMPATE"
		title.TextColor3 = V.TEXT
		-- empate: os dois panos, sem inventar vencedor
		cena:bandeira({ V.US, V.VC }, { "bandeira_eua", "bandeira_frente" })
	end
	cena:reiniciar()
	efeitos:reiniciar(if winner == "US" then V.US elseif winner == "VC" then V.VC else V.BRASS)
	-- D-240: a bandeira do vencedor ao pôr do sol atrás do pódio; no empate, o cenário de sempre
	local artePalco = if winner == "US" or winner == "VC" then ArteCatalogo.time(winner) else ""
	if artePalco ~= "" then
		cena.cenario.Image = artePalco
	else
		local fundoPodio = ReplicatedStorage:GetAttribute("Img_podio_fundo")
		cena.cenario.Image = if type(fundoPodio) == "number" and fundoPodio ~= 0
			then string.format("rbxassetid://%d", fundoPodio)
			else ""
	end
	if winner == "US" then
		epico:reiniciar("VITÓRIA", "FUZILEIROS DOS EUA", V.US)
	elseif winner == "VC" then
		epico:reiniciar("VITÓRIA", "VIET CONG", V.VC)
	else
		epico:reiniciar("EMPATE", "NINGUÉM RECUOU", V.BRASS)
	end
	destaque.Visible = false
	destaqueFeito = false
	local linhas = if type(data) == "table" and type(data.linhas) == "table" then data.linhas else {}
	for i, c in cards do
		local l = linhas[i]
		c.f.Visible = l ~= nil
		temLinha[i] = l ~= nil
		if l then
			-- D-214: a comemoração que cada um escolheu no ARMÁRIO (o servidor guardou no pódio)
			cena:comemoracao(i, if type(l.com) == "string" then l.com else nil)
			if i == 1 then
				destaqueNome.Text = UiKit.upper(tostring(l.nome))
				local it = Comemoracao.item(Comemoracao.valida(l.com))
				destaqueCom.Text = string.format("COMEMORAÇÃO: %s", UiKit.upper(if it then it.nome else ""))
			end
			c.name.Text = tostring(l.nome)
			c.pts.Text = string.format("%d pontos", tonumber(l.pontos) or 0)
			local a, m = tonumber(l.abates) or 0, tonumber(l.mortes) or 0
			-- frases inteiras, no singular quando é um (a tradução não entra num modelo dentro de outro)
			c.kd.Text = if a == 1 and m == 1
				then "1 abate · 1 morte"
				elseif a == 1 then string.format("1 abate · %d mortes", m)
				elseif m == 1 then string.format("%d abates · 1 morte", a)
				else string.format("%d abates · %d mortes", a, m)
			local lado = tostring(l.lado)
			-- copiado de um corpo que não é um R15 inteiro: o manequim no lugar
			if not cena:por(i, modelFor(tostring(l.id), lado)) then
				cena:por(i, manequim(lado))
			end
		end
	end
	empty.Visible = #linhas == 0
	podium.Visible = true
	vote.Visible = false
end

-- os cartões embaixo de cada soldado (a câmera balança, eles acompanham). D-214: quando a câmera vai
-- até o 1º, os cartões do 2º e do 3º saem e entra o destaque do melhor, com faíscas douradas.
local function cartaoX(i: number): number
	-- a cena é a tela inteira e os cartões ficam no painel centrado: passa de uma medida à outra
	local fx = cena:telaX(i)
	local sa, sp = stage.AbsoluteSize, stage.AbsolutePosition
	local pa, pp = podium.AbsoluteSize, podium.AbsolutePosition
	return if pa.X > 0 then (sp.X + fx * sa.X - pp.X) / pa.X else fx
end

-- D-221: o título volta ao lugar e à cor de leitura (votação e restauração usam o mesmo cabeçalho)
local function cabecalhoNormal()
	kicker.Position = UDim2.fromOffset(0, 0)
	title.Position = UDim2.fromOffset(0, px(26, 36))
	clock.Position = UDim2.fromOffset(0, px(92, 128))
	for _, o in { kicker, title, clock } do
		o.TextTransparency = 0
		o.TextStrokeTransparency = 1
	end
end

local function frameCards()
	local t = cena:tempo()
	local P = Comemoracao.PODIO
	-- D-221: a cena é a tela inteira: o título vai para o alto dela e os cartões para o pé, longe dos
	-- caixotes, mesmo em tela mais alta que o painel. No close, o título sai da frente do rosto.
	local sa, sp = stage.AbsoluteSize, stage.AbsolutePosition
	local ra, rp = root.AbsoluteSize, root.AbsolutePosition
	local pa, pp = podium.AbsoluteSize, podium.AbsolutePosition
	local k = if ra.X > 0 then ra.X / W else 1
	-- (o título e os cartões ficam na tela de área segura, que corta o que passa dela no celular)
	local ga, gp = gui.AbsoluteSize, gui.AbsolutePosition
	local topo = (math.max(sp.Y + sa.Y * 0.085, gp.Y + 4) - rp.Y) / k
	kicker.Position = UDim2.fromOffset(0, topo)
	title.Position = UDim2.fromOffset(0, topo + px(26, 36))
	-- D-240: o relógio vai para a faixa de cinema, e o letreiro grande fica sozinho no céu
	clock.Position = UDim2.fromOffset(0, topo - px(38, 52))
	local some = math.clamp((t - P.zoom) / 0.6, 0, 1)
	for _, o in { kicker, clock } do
		o.TextTransparency = some
		o.TextStrokeTransparency = 0.4 + 0.6 * some
	end
	-- D-240: quem diz o resultado no pódio é o letreiro grande (Controllers/PodioEpico)
	title.TextTransparency, title.TextStrokeTransparency = 1, 1
	kicker.TextTransparency, kicker.TextStrokeTransparency = 1, 1
	local pe = (math.min(sp.Y + sa.Y * 0.985, gp.Y + ga.Y - 4) - (pp.Y + pa.Y)) / k
	for i, c in cards do
		c.f.Visible = temLinha[i] and (i == 1 or t < P.zoom + 0.25)
		if c.f.Visible then
			c.f.Position = UDim2.new(math.clamp(cartaoX(i), 0.1, 0.9), 0, 1, pe)
		end
	end
	if temLinha[1] and not destaqueFeito and t >= P.perto - 0.3 then
		destaqueFeito = true
		destaque.Visible = true
		destaque.Position = destaquePos - UDim2.fromOffset(px(60, 80), 0)
		UiKit.tween(destaque, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = destaquePos,
		})
		-- (em px de projeto: o pódio fica dentro do UIScale do fit)
		local meio = Vector2.new(destaquePos.X.Offset + px(60, 80), destaquePos.Y.Offset + px(60, 84))
		UiEfeitos.faiscas(podium, meio, V.BRASS, 30, { vmin = 220, vmax = 700, gravidade = 500, z = 7 })
		UiEfeitos.onda(podium, meio, V.BRASS, px(160, 220), 0.6, 7)
	end
end

pintarHoras = function()
	local conta = decode("VT65VotosHora")
	for _, c in horaCards do
		local n = if type(conta) == "table" then tonumber(conta[c.id]) or 0 else 0
		c.votes.Text = if n == 1 then "1 voto" else string.format("%d votos", n)
		c.edge.Color = if myHora == c.id then V.BRASS else V.LINE
		c.edge.Thickness = if myHora == c.id then 3 else 2
	end
end

local function refreshVotes()
	pintarHoras()
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
	cabecalhoNormal()
	for _, c in mapCards do
		c.b:Destroy()
	end
	table.clear(mapCards)
	myVote = nil
	myHora = nil
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
		cena:reiniciar()
	end
end

local function aplicaFase(f: any)
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
		cabecalhoNormal()
		podium.Visible = false
		vote.Visible = false
		cena:reiniciar()
	else
		setShown(false)
	end
end

-- D-215: cada troca de fase passa pela cortina (Cortina), com o nome da próxima tela no meio; a troca
-- acontece com a tela coberta. Sem nada na tela antes nem depois (a partida segue), troca direto.
local SUB_FASE = {
	comemoracao = "FIM DA PARTIDA",
	votacao = "VOTAÇÃO DO MAPA",
	restauracao = "PREPARANDO O CAMPO",
} :: { [string]: string }
local function onPhase(primeira: boolean?)
	local f = ReplicatedStorage:GetAttribute("VT65Fase")
	local mostra = type(f) == "string" and SUB_FASE[f] ~= nil
	if primeira or not (shown or mostra) then
		aplicaFase(f)
		return
	end
	task.spawn(function()
		Cortina.passar(function()
			aplicaFase(ReplicatedStorage:GetAttribute("VT65Fase")) -- a fase de agora (a última vence)
		end, "STARLITE", if mostra then SUB_FASE[f :: string] else "A PARTIDA VAI COMEÇAR")
	end)
end
ReplicatedStorage:GetAttributeChangedSignal("VT65Fase"):Connect(function()
	onPhase()
end)
ReplicatedStorage:GetAttributeChangedSignal("VT65Votos"):Connect(refreshVotes)
ReplicatedStorage:GetAttributeChangedSignal("VT65VotosHora"):Connect(pintarHoras)
onPhase(true)

-- relógio da fase, a cena e os cartões
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
		cena:passo(dt)
		efeitos:passo(dt)
		epico:passo(cena:tempo())
		frameCards()
	end
end)
