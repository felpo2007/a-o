--!strict
-- Tela de entrada. 2026-11-13 (pedido do dono: "gostava mais da tela de carregamento inicial antiga"):
-- volta o visual da tela de antes da v37 (commit b85331e, D-83/D-92), com o carregamento completo e
-- o progresso REAL da v37 e o JOGAR AGORA:
--   - película por cima de tudo (Acabamento.filme: vinheta, grão a 24 quadros por segundo, poeira,
--     riscos e tremor de projetor) e a luz quente de um lampião no alto, à esquerda;
--   - à esquerda, o título e o briefing datilografado: fatos da operação tirados do The First
--     Fight (USMC, 2015; citações em research/F0_FONTES.md), um por vez, num cartão oliva;
--   - à direita, a carta 1:50.000 sendo traçada: grade, curvas de nível, os eixos a lápis vermelho
--     se desenhando e correndo, a marca do objetivo piscando e o carimbo SECRET;
--   - embaixo, a pontilha de filme, a etapa datilografada, as seis etapas e a barra em seis partes.
-- D-186 (dono, 20/11: "a tela de carregamento inicial esta demorando demais" e "melhore as telas de
-- carregamento"): antes a tela esperava o jogo INTEIRO (todos os sons, todas as armas, o streaming do
-- mapa todo e a arte de tudo o que chegou, D-117). Agora só o essencial segura a tela e aparece o
-- CONTINUAR; o resto termina em segundo plano, no menu.
-- O essencial, em seis etapas reais (ContentProvider:PreloadAsync em lotes; o callback conta cada
-- asset e as falhas):
--   1. o jogo (game.Loaded);
--   2. os remotes do servidor (sem resposta em 60 s: o aviso, e continua esperando);
--   3. a interface: fontes, as texturas do Acabamento, os botões do controle e as imagens que o
--      servidor resolveu (Img_*, a carta tática CartaImage_*), chão e céu do AssetIds;
--   4. a ficha do jogador (o servidor põe "XP" no jogador quando o perfil chega; "DataReadOnly" quando
--      não carregou). Sem ela em DATA_MAX_S, a tela diz que os dados ainda não chegaram: não mostra
--      uma conta vazia como se fosse a dele;
--   5. os manequins e os objetos do menu e da mesa (o PreviewService marca Ready);
--   6. o terreno (TerrainReady) e o streaming em volta dos três lugares dos planos do menu.
-- Em segundo plano (depois das seis, com a tela ainda aberta ou já no menu; o menu mostra a linha
-- "VT65Fundo" do jogador): a arte das armas, as animações do soldado, todos os sons e o mapa (o
-- streaming do centro, dos quadrantes, dos QGs e dos objetivos, 95% das peças do Map.PartCount e a
-- arte que chegou). Ao nascer, o servidor ainda pede o streaming em volta do ponto (SpawnService).
-- Sem porcentagem: a barra tem uma parte por etapa e cada parte enche com o que foi contado nela; a
-- etapa sem contagem (esperando o servidor) tem o brilho que corre.
-- CONTINUAR (Enter, A ou o toque) marca "Pronto" e a tela esmaece por cima do menu principal
-- (Controllers/MenuPrincipal). CONFIGURAÇÕES (C ou X) faz o mesmo e o menu abre a aba Configurações
-- (atributo "AbrirConfig"). Y abre o idioma. Teto: com ESSENTIAL_CAP_S, os botões aparecem com o que
-- já chegou e a tela diz o que falta.
-- Medida (D-186): os segundos de cada etapa ficam em atributos deste script ("T_<etapa>", desde o
-- primeiro quadro), e os do segundo plano também ("T_fundo_<parte>").
-- Fora o Acabamento e o Idioma (mesmo ReplicatedFirst), não depende de nada: aparece desde o 1º quadro.
-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevTela", "carregamento") reabre a
-- tela e refaz o carregamento essencial (o que já está na memória chega rápido) para a foto;
-- qualquer outro valor (ou nil) fecha, se já estiver pronta.
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local Acabamento = require(script.Parent:WaitForChild("Acabamento"))
local Idioma = require(script.Parent:WaitForChild("Idioma"))

local player = Players.LocalPlayer

local T0 = os.clock() -- D-186: as medidas contam daqui (o primeiro quadro do cliente)
local ESSENTIAL_CAP_S = 60 -- teto do essencial (D-186; D-117 esperava o mapa inteiro, até 4 min)
local REMOTES_WARN_S = 60 -- sem os remotes: o aviso (e continua esperando)
local DATA_MAX_S = 25 -- a ficha do jogador: depois disto, o aviso de que não chegou
local PREVIEW_MAX_S = 30 -- os manequins do menu
local MAP_PARTS_FRAC = 0.95 -- D-117: fração das peças do Map (Map.PartCount) que precisa ter chegado
local MAP_PARTS_MAX_S = 90 -- e no máximo isto esperando por elas (em segundo plano)
local BATCH = 16 -- assets por chamada do PreloadAsync (a barra anda por lote e por asset)
-- os lugares dos planos do menu principal (Controllers/MenuPrincipal, SHOTS): o terreno deles chega
-- antes do CONTINUAR, para o menu abrir com o mapa e os soldados
local MENU_PLACES = { "Xóm Gò", "Serraria", "Arrozais" }

local CANVAS = Color3.fromRGB(36, 38, 28) -- lona da barraca no escuro
local KHAKI = Color3.fromRGB(201, 186, 140)
local CARD = Color3.fromRGB(234, 226, 200)
local PAPER = Color3.fromRGB(222, 216, 184)
local INK = Color3.fromRGB(40, 36, 28)
local STAMP = Color3.fromRGB(150, 40, 30)
local DRAB = Color3.fromRGB(46, 50, 36)
local BRASS = Color3.fromRGB(214, 172, 72)
local BRASS_LIGHT = Color3.fromRGB(236, 202, 116)
local OLIVE_CARD = Color3.fromRGB(26, 28, 21)
local GRID = Color3.fromRGB(70, 96, 140)
local CONTOUR = Color3.fromRGB(150, 104, 60)
local HEAD = Font.fromName("Oswald", Enum.FontWeight.Bold)
local HEAD_REG = Font.fromName("Oswald", Enum.FontWeight.Regular)
local TYPE = Font.fromEnum(Enum.Font.SpecialElite)
local BODY = Font.fromEnum(Enum.Font.Arimo)
local GLYPH = Font.fromEnum(Enum.Font.ArimoBold) -- ■ □ ► e cia. estão no Arimo
local AMBER = Color3.fromRGB(232, 168, 64) -- etapa que passou com aviso (dados, imagens)

local QUINT_OUT = Enum.EasingStyle.Quint
local OUT, IN, INOUT = Enum.EasingDirection.Out, Enum.EasingDirection.In, Enum.EasingDirection.InOut

local function tween(
	o: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?,
	delay: number?
): Tween
	local tw = TweenService:Create(o, TweenInfo.new(t, style or QUINT_OUT, dir or OUT, 0, false, delay or 0), props)
	tw:Play()
	return tw
end

-- ===== texto: tamanho de projeto; na TV nunca abaixo de 24 px na tela =====
local function isTv(): boolean
	local ok, v = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and v == true
end
local TV = isTv()
local stageK = 1
local sized: { { o: any, s: number } } = {}
local function textAt(s: number): number
	return if TV then math.max(s, math.ceil(24 / math.max(stageK, 0.05))) else s
end
local function size(o: any, s: number)
	table.insert(sized, { o = o, s = s })
	o.TextSize = textAt(s)
end

local function label(
	parent: Instance,
	font: Font,
	s: number,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	align: Enum.TextXAlignment?
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.TextWrapped = true
	t.Text = ""
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Parent = parent
	size(t, s)
	return t
end

local function box(parent: Instance, color: Color3, x: number, y: number, w: number, h: number, tr: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = tr or 0
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Parent = parent
	return f
end

local function corner(o: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

local function edge(o: Instance, color: Color3, thick: number, tr: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.Transparency = tr
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

-- luz de cima no papel e nos cartões (o UIGradient só pinta o próprio objeto)
local function lit(o: Instance, rot: number, low: number)
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(low, low * 0.98, low * 0.94))
	g.Parent = o
end

-- ===== montagem =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Loading"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)

local bg = Instance.new("Frame")
bg.Name = "Fundo"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = CANVAS
bg.BorderSizePixel = 0
bg.Active = true -- o lobby atrás não recebe clique
bg.Parent = gui
do -- lona: mais clara em cima, onde bate o lampião
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 220)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(150, 148, 138)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(84, 84, 80)),
	})
	g.Parent = bg
end

local film =
	Acabamento.filme(gui, { vinheta = 1, grao = 0.6, poeira = 32, riscos = 2, tremor = 0.6, lampiao = 0.55, z = 40 })
Acabamento.luz(film, UDim2.fromScale(0.16, 0.08), 1.7)

-- palco de 1280 x 720 que escala com a tela
local stage = Instance.new("Frame")
stage.Name = "Palco"
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(1280, 720)
stage.BackgroundTransparency = 1
stage.Parent = bg
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage

-- ----- título (o nome novo do jogo, v37; o resto como antes) -----
local kicker = label(stage, TYPE, 16, KHAKI, 92, 104, 700, 22)
kicker.Text = "III MAF · CHU LAI · ORDEM DE OPERAÇÃO"
local title = label(stage, HEAD, 92, CARD, 86, 122, 700, 112)
title.Text = "STARLITE: VIETNÃ 1965"
title.TextYAlignment = Enum.TextYAlignment.Center
title.TextWrapped = false
title.TextScaled = true -- o nome novo é mais longo que o de antes: encolhe para caber na coluna
do
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = textAt(92)
	lim.MinTextSize = 40
	lim.Parent = title
end
local titleScale = Instance.new("UIScale")
titleScale.Parent = title
local rule = box(stage, STAMP, 92, 238, 0, 3)
local hair = box(stage, BRASS, 92, 245, 0, 1, 0.35)
local sub = label(stage, BODY, 20, KHAKI, 92, 256, 700, 26)
sub.Text = "OPERAÇÃO STARLITE · VẠN TƯỜNG · QUẢNG NGÃI · 18 DE AGOSTO DE 1965"

-- ----- briefing: cartão oliva com filete cáqui e barra de latão (a linguagem dos avisos) -----
local BRIEFING: { { texto: string, pagina: string } } = {
	{
		texto = "18 AGO 1965 · 0630H. As companhias K e I desembarcam como planejado na Green Beach.",
		pagina = "p. 21",
	},
	{ texto = "A praia não foi bombardeada: a vila de An Cường (1) fica perto demais.", pagina = "p. 21" },
	{ texto = "A companhia K toma o terreno alto logo depois da vila, com a Colina 22.", pagina = "p. 21" },
	{ texto = "Sebes de bambu e árvores de 1,8 a 2,4 m dividem cada arrozal.", pagina = "p. 10" },
	{ texto = "An Cường (2): vila de mata fechada, trincheiras cobertas de galhos e toras.", pagina = "p. 25" },
	{ texto = "LZ Blue, logo ao sul de Nam Yên (3). A Colina 43 fica uns 400 m a sudoeste.", pagina = "p. 29" },
	{ texto = "A Colina 30, ao norte de An Cường (2), domina a zona de pouso.", pagina = "p. 29" },
}
local brief = box(stage, OLIVE_CARD, 92, 302, 640, 166, 0.1)
brief.Name = "Briefing"
corner(brief, 4)
edge(brief, KHAKI, 1, 0.72)
lit(brief, 90, 0.66)
Acabamento.sombra(brief, 18, Vector2.new(0, 7), 0.6)
local briefBar = box(brief, BRASS, 0, 0, 5, 166)
corner(briefBar, 2)
local seal = box(brief, BRASS, 20, 16, 30, 30)
corner(seal, 3)
local sealGlyph = label(seal, HEAD, 20, Color3.fromRGB(20, 22, 16), 0, 0, 30, 30, Enum.TextXAlignment.Center)
sealGlyph.TextYAlignment = Enum.TextYAlignment.Center
sealGlyph.Text = "§"
local briefHead = label(brief, HEAD, 18, BRASS_LIGHT, 62, 14, 440, 24)
briefHead.Text = "BRIEFING · O QUE O COMANDO SABE"
local briefIdx = label(brief, HEAD_REG, 16, KHAKI, 520, 15, 100, 24, Enum.TextXAlignment.Right)
local briefText = label(brief, TYPE, 19, CARD, 62, 48, 560, 78)
briefText.RichText = true
local briefSrc = label(brief, BODY, 13, KHAKI, 62, 130, 560, 18)
briefSrc.TextTransparency = 0.3
local briefLine = box(brief, BRASS, 62, 154, 560, 2, 0.4)
-- o que esmaece junto com o cartão na entrada (valor de projeto de cada transparência)
local briefFades: { { o: Instance, prop: string, base: number } } = {
	{ o = brief, prop = "BackgroundTransparency", base = 0.1 },
	{ o = briefBar, prop = "BackgroundTransparency", base = 0 },
	{ o = seal, prop = "BackgroundTransparency", base = 0 },
	{ o = sealGlyph, prop = "TextTransparency", base = 0 },
	{ o = briefHead, prop = "TextTransparency", base = 0 },
	{ o = briefIdx, prop = "TextTransparency", base = 0 },
	{ o = briefSrc, prop = "TextTransparency", base = 0.3 },
	{ o = briefLine, prop = "BackgroundTransparency", base = 0.4 },
}
for _, s in brief:GetChildren() do
	if s:IsA("UIStroke") then
		table.insert(briefFades, { o = s :: Instance, prop = "Transparency", base = s.Transparency })
	end
end

-- ----- carta 1:50.000 sendo traçada (papel com sombra, clipe e carimbo) -----
local map = box(stage, PAPER, 812, 104, 368, 368)
map.Name = "Carta"
map.Rotation = 2
edge(map, INK, 1, 0.55)
lit(map, 70, 0.84)
local mapShadow = Acabamento.sombra(map, 22, Vector2.new(5, 12), 0.65)
local area = box(map, PAPER, 26, 22, 316, 316, 1)
area.Name = "Area"
local sea = box(area, GRID, 0.0, 0, 0, 316, 0.72) -- mar a leste (a praia é a Green Beach)
sea.Position = UDim2.fromScale(0.9, 0)
sea.Size = UDim2.fromScale(0.1, 1)
local seaName = label(area, BODY, 11, GRID, 286, 140, 30, 40, Enum.TextXAlignment.Center)
seaName.Text = "MAR"
seaName.Rotation = 90
type Draw = { f: Frame, full: UDim2, from: UDim2, delay: number }
local draws: { Draw } = {}
for i = 1, 8 do
	local v = box(area, GRID, 0, 0, 0, 0, 0.5)
	v.Position = UDim2.fromScale(i / 9, 0)
	table.insert(draws, { f = v, full = UDim2.new(0, 1, 1, 0), from = UDim2.new(0, 1, 0, 0), delay = i * 0.05 })
	local h = box(area, GRID, 0, 0, 0, 0, 0.5)
	h.Position = UDim2.fromScale(0, i / 9)
	table.insert(draws, { f = h, full = UDim2.new(1, 0, 0, 1), from = UDim2.new(0, 0, 0, 1), delay = i * 0.05 + 0.02 })
end
-- curvas de nível das duas colinas (anéis que crescem do cume para fora)
for hIdx, hill in { { 0.32, 0.4, 5 }, { 0.6, 0.74, 4 } } do
	for k = 1, hill[3] do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(hill[1], hill[2])
		ring.BackgroundTransparency = 1
		ring.Parent = area
		corner(ring, 999)
		edge(ring, CONTOUR, if k == 1 then 2 else 1, 0.2)
		local r = 0.06 + k * 0.05
		table.insert(draws, {
			f = ring,
			full = UDim2.fromScale(r * (1.3 - 0.05 * k), r),
			from = UDim2.fromScale(0, 0),
			delay = 0.5 + hIdx * 0.3 + k * 0.12,
		})
	end
end
local hill43 = label(area, TYPE, 14, INK, 82, 104, 60, 18)
hill43.Text = "43"
local hill30 = label(area, TYPE, 14, INK, 194, 218, 60, 18)
hill30.Text = "30"
-- eixos a lápis: o desembarque vindo da praia e o da LZ no norte
local axisBeach = Acabamento.linha(area, STAMP, 4, 18, 5)
local axisLz = Acabamento.linha(area, STAMP, 3, 12, 5)
local objective = Acabamento.marca(area, STAMP, 22, 6)
objective.raiz.Position = UDim2.fromScale(0.36, 0.44)
objective.raiz.Visible = false
local mapLabel = label(map, BODY, 13, INK, 26, 342, 316, 20)
mapLabel.Text = "CARTA 1:50.000 · VẠN TƯỜNG · QUẢNG NGÃI"
local secret = label(map, HEAD, 26, STAMP, 214, 280, 140, 40, Enum.TextXAlignment.Center)
secret.TextYAlignment = Enum.TextYAlignment.Center
secret.Text = "SECRET"
secret.Rotation = -9
secret.TextTransparency = 1
local secretEdge = edge(secret, STAMP, 3, 1)
local secretScale = Instance.new("UIScale")
secretScale.Parent = secret
-- clipe de papel no canto (arame: dois ovais encaixados)
local clip = box(map, Color3.fromRGB(150, 150, 146), 30, -14, 14, 44, 1)
corner(clip, 7)
edge(clip, Color3.fromRGB(170, 172, 168), 2, 0.05)
local clipIn = box(clip, Color3.fromRGB(150, 150, 146), 3, 8, 8, 30, 1)
corner(clipIn, 4)
edge(clipIn, Color3.fromRGB(150, 152, 148), 2, 0.1)

-- ----- pontilha de filme (círculo com ponteiro girando) -----
local leader = box(stage, Color3.fromRGB(56, 58, 46), 92, 520, 92, 92)
corner(leader, 999)
edge(leader, KHAKI, 2, 0)
local leaderIn = Instance.new("Frame")
leaderIn.AnchorPoint = Vector2.new(0.5, 0.5)
leaderIn.Position = UDim2.fromScale(0.5, 0.5)
leaderIn.Size = UDim2.fromScale(0.72, 0.72)
leaderIn.BackgroundTransparency = 1
leaderIn.Parent = leader
corner(leaderIn, 999)
edge(leaderIn, KHAKI, 1, 0.5)
box(leader, KHAKI, 0, 45, 92, 1, 0.55)
box(leader, KHAKI, 45, 0, 1, 92, 0.55)
local sweep = Instance.new("Frame")
sweep.AnchorPoint = Vector2.new(0.5, 1)
sweep.Position = UDim2.fromScale(0.5, 0.5)
sweep.Size = UDim2.new(0, 2, 0.5, 0)
sweep.BackgroundColor3 = KHAKI
sweep.BorderSizePixel = 0
sweep.Parent = leader
local digit = label(leader, HEAD, 46, CARD, 0, 0, 92, 92, Enum.TextXAlignment.Center)
digit.TextYAlignment = Enum.TextYAlignment.Center
digit.ZIndex = 2

-- ----- progresso -----
local stepText = label(stage, TYPE, 19, CARD, 206, 520, 650, 26)
-- D-186: a contagem real da etapa ("24/31"), entre o texto e a etapa
local countLbl = label(stage, HEAD_REG, 18, KHAKI, 866, 517, 170, 32, Enum.TextXAlignment.Right)
countLbl.Name = "Contagem"
countLbl.TextYAlignment = Enum.TextYAlignment.Center
stepText.RichText = true
stepText.TextWrapped = false
stepText.TextTruncate = Enum.TextTruncate.AtEnd
local stepsRow = Instance.new("Frame")
stepsRow.Name = "Etapas"
stepsRow.BackgroundTransparency = 1
stepsRow.Position = UDim2.fromOffset(206, 554)
stepsRow.Size = UDim2.fromOffset(974, 26)
stepsRow.Parent = stage
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0, 16)
rowLayout.Parent = stepsRow

-- D-186: a barra tem uma parte por etapa (sem porcentagem: cada parte enche com o que foi contado
-- nela); a parte da etapa que só espera o servidor ganha o brilho que corre
local N_STEPS = 6
local SEG_GAP = 6
local SEG_W = (974 - (N_STEPS - 1) * SEG_GAP) / N_STEPS
type Seg = { back: Frame, fill: Frame }
local segs: { Seg } = {}
for i = 1, N_STEPS do
	local back = box(stage, DRAB, math.floor(206 + (i - 1) * (SEG_W + SEG_GAP)), 592, math.floor(SEG_W), 10)
	back.Name = string.format("Parte%d", i)
	corner(back, 2)
	edge(back, KHAKI, 1, 0.7)
	back.ClipsDescendants = true
	local fill = box(back, STAMP, 0, 0, 0, 10)
	fill.Name = "Cheio"
	fill.Size = UDim2.fromScale(0, 1)
	lit(fill, 90, 0.7)
	segs[i] = { back = back, fill = fill }
end
local shine = box(segs[1].back, CARD, 0, 0, 0, 0, 0) -- brilho que corre na etapa sem número
shine.Size = UDim2.fromScale(1, 1)
shine.ZIndex = 3
shine.Visible = false
local shineGrad = Instance.new("UIGradient")
shineGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.42, 1),
	NumberSequenceKeypoint.new(0.5, 0.45),
	NumberSequenceKeypoint.new(0.58, 1),
	NumberSequenceKeypoint.new(1, 1),
})
shineGrad.Parent = shine
-- a etapa em que está, na linha do texto (era a porcentagem)
local stepNo = label(stage, HEAD, 22, CARD, 1050, 514, 130, 32, Enum.TextXAlignment.Right)
stepNo.TextYAlignment = Enum.TextYAlignment.Center
stepNo.Text = string.format("ETAPA %d/%d", 1, N_STEPS)
-- o que termina em segundo plano (embaixo da barra)
local bgLine = label(stage, BODY, 14, KHAKI, 206, 608, 974, 18)
bgLine.TextWrapped = false
bgLine.TextTruncate = Enum.TextTruncate.AtEnd
bgLine.TextTransparency = 0.2
bgLine.Text = "Depois do CONTINUAR, as armas, os sons e o mapa terminam de carregar no menu."

-- ----- os dois botões do fim (D-186): CONTINUAR (carimbo vermelho com filete de latão e a tecla num
-- chip) e CONFIGURAÇÕES (oliva escuro) -----
type Btn = {
	b: TextButton,
	edge: UIStroke,
	scale: UIScale,
	keycap: Frame,
	keyText: TextLabel,
	keyImg: ImageLabel,
	text: TextLabel,
	arrow: TextLabel,
	base: Color3,
	hot: Color3,
}
local function stampButton(x: number, w: number, text: string, color: Color3, hot: Color3, textSize: number): Btn
	local b = Instance.new("TextButton")
	b.Name = "Botao"
	b.Position = UDim2.fromOffset(x, 634)
	b.Size = UDim2.fromOffset(w, 54)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Text = ""
	b.Visible = false
	b.Parent = stage
	corner(b, 3)
	lit(b, 90, 0.72)
	local e = edge(b, BRASS, 1.5, 1)
	local sc = Instance.new("UIScale")
	sc.Parent = b
	local keycap = box(b, CARD, 12, 12, 30, 30, 1)
	keycap.AutomaticSize = Enum.AutomaticSize.X
	corner(keycap, 4)
	local keyPad = Instance.new("UIPadding")
	keyPad.PaddingLeft = UDim.new(0, 6)
	keyPad.PaddingRight = UDim.new(0, 6)
	keyPad.Parent = keycap
	local keyText = label(keycap, HEAD, 15, INK, 0, 0, 0, 30, Enum.TextXAlignment.Center)
	keyText.AutomaticSize = Enum.AutomaticSize.X
	keyText.TextYAlignment = Enum.TextYAlignment.Center
	keyText.TextTransparency = 1
	local keyImg = Instance.new("ImageLabel")
	keyImg.BackgroundTransparency = 1
	keyImg.Size = UDim2.fromOffset(30, 30)
	keyImg.Position = UDim2.fromOffset(12, 12)
	keyImg.ImageTransparency = 1
	keyImg.Visible = false
	keyImg.Parent = b
	local t = label(b, HEAD, textSize, CARD, 84, 0, w - 120, 54)
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextWrapped = false
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = text
	t.TextTransparency = 1
	local arrow = label(b, GLYPH, 18, CARD, w - 34, 0, 26, 54, Enum.TextXAlignment.Center)
	arrow.TextYAlignment = Enum.TextYAlignment.Center
	arrow.Text = "►"
	arrow.TextTransparency = 1
	return {
		b = b,
		edge = e,
		scale = sc,
		keycap = keycap,
		keyText = keyText,
		keyImg = keyImg,
		text = t,
		arrow = arrow,
		base = color,
		hot = hot,
	}
end
local play = stampButton(868, 312, "CONTINUAR", STAMP, Color3.fromRGB(172, 50, 38), 26)
play.b.Name = "Continuar"
local desk = stampButton(554, 300, "CONFIGURAÇÕES", DRAB, Color3.fromRGB(62, 68, 48), 20)
desk.b.Name = "Configuracoes"
play.b.NextSelectionLeft, desk.b.NextSelectionRight = desk.b, play.b
-- D-186: o aviso do que não chegou (dados do jogador, imagens, o teto), à esquerda dos botões
local enterHint = label(stage, BODY, 14, AMBER, 206, 634, 330, 54)
enterHint.Name = "Aviso"
enterHint.TextYAlignment = Enum.TextYAlignment.Center

-- ----- idioma (pedido do dono, 2026-11-11): chip no alto à direita; Y no controle -----
local function openLanguage()
	if not Idioma.aberto() then
		Idioma.abrir({ z = 101 })
	end
end
local langChip = Idioma.chip(stage, { onClick = openLanguage, padKey = Enum.KeyCode.ButtonY })
langChip.button.AnchorPoint = Vector2.new(1, 0)
langChip.button.Position = UDim2.fromOffset(1180, 46)
Idioma.soAteEscolher(langChip.button) -- v43: só enquanto o idioma não foi escolhido

gui.Parent = player:WaitForChild("PlayerGui")

-- ===== escala do palco (sem loop por quadro: só quando a janela muda) =====
local function fit()
	local s = gui.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return
	end
	stageK = math.max(math.min(s.X / 1280, s.Y / 720), 0.45)
	if TV then
		stageK = math.max(stageK * 0.92, 1) -- margem de segurança da TV
	end
	stageScale.Scale = stageK
	for _, e in sized do
		e.o.TextSize = textAt(e.s)
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

-- ===== as seis etapas do essencial (D-186) =====
type Step = { name: string, done: boolean, glyph: TextLabel, text: TextLabel, pop: UIScale }
local steps: { Step } = {}
local STEP_DEFS: { string } = {
	"Jogo",
	"Servidor",
	"Interface",
	"Sua ficha",
	"Soldados",
	"Terreno",
}
-- nome curto de cada etapa nas medidas (atributos "T_<nome>" do script)
local STEP_KEYS = { "jogo", "servidor", "interface", "ficha", "soldados", "terreno" }
for i, name in STEP_DEFS do
	local item = Instance.new("Frame")
	item.BackgroundTransparency = 1
	item.AutomaticSize = Enum.AutomaticSize.X
	item.Size = UDim2.fromOffset(0, 26)
	item.LayoutOrder = i
	item.Parent = stepsRow
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 6)
	lay.Parent = item
	local g = label(item, GLYPH, 15, KHAKI, 0, 0, 16, 26, Enum.TextXAlignment.Center)
	g.TextYAlignment = Enum.TextYAlignment.Center
	g.LayoutOrder = 1
	g.Text = "□"
	local pop = Instance.new("UIScale")
	pop.Parent = g
	local t = label(item, if string.find(name, "[\196-\244]") then BODY else TYPE, 15, KHAKI, 0, 0, 0, 26)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextWrapped = false
	t.TextTransparency = 0.35
	t.LayoutOrder = 2
	t.Text = name
	table.insert(steps, { name = name, done = false, glyph = g, text = t, pop = pop })
end

-- cada parte da barra: o que foi contado na etapa (só sobe)
local frac: { number } = table.create(N_STEPS, 0)
local warned: { boolean } = table.create(N_STEPS, false)

-- D-186: os segundos desde o primeiro quadro, num atributo do script (a tela some; o script fica)
local function mark(name: string)
	script:SetAttribute("T_" .. name, math.floor((os.clock() - T0) * 10 + 0.5) / 10)
end

local function finish(i: number)
	local s = steps[i]
	if s.done then
		return
	end
	s.done = true
	mark(STEP_KEYS[i])
	s.glyph.Text = if warned[i] then "!" else "■"
	s.glyph.TextColor3 = if warned[i] then AMBER else BRASS
	s.pop.Scale = 1.7
	tween(s.pop, 0.35, { Scale = 1 })
	tween(s.text, 0.3, { TextTransparency = 0, TextColor3 = if warned[i] then AMBER else CARD })
	stepNo.Text = string.format("ETAPA %d/%d", math.min(i + 1, N_STEPS), N_STEPS)
end

local function setFrac(i: number, f: number)
	local v = math.max(frac[i], math.clamp(f, 0, 1))
	if v > frac[i] then
		frac[i] = v
		tween(segs[i].fill, 0.35, { Size = UDim2.fromScale(v, 1) })
	end
	if v >= 1 then
		finish(i)
	end
end

-- a etapa passou, mas com aviso (o glifo "!" e a parte da barra em âmbar)
local function warnStep(i: number)
	warned[i] = true
	segs[i].fill.BackgroundColor3 = AMBER
end

-- os avisos que ficam à esquerda dos botões, um por linha e um por assunto (nil tira o do assunto)
local noteOrder: { string } = {}
local noteText: { [string]: string? } = {}
local function note(key: string, text: string?)
	if text and noteText[key] == nil then
		table.insert(noteOrder, key)
	elseif not text then
		local i = table.find(noteOrder, key)
		if i then
			table.remove(noteOrder, i)
		end
	end
	noteText[key] = text
	local lines: { string } = {}
	for _, k in noteOrder do
		local t = noteText[k]
		if t then
			table.insert(lines, t)
		end
	end
	enterHint.Text = table.concat(lines, "\n")
end

local shineTween: Tween? = nil
local function setWaiting(on: boolean, i: number?)
	if i then
		shine.Parent = segs[i].back
	end
	shine.Visible = on
	if on and not shineTween then
		shineGrad.Offset = Vector2.new(-1, 0)
		local tw = TweenService:Create(
			shineGrad,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, INOUT, -1),
			{ Offset = Vector2.new(1, 0) }
		)
		tw:Play()
		shineTween = tw
	elseif not on and shineTween then
		shineTween:Cancel()
		shineTween = nil
	end
end

local function setStep(text: string)
	Acabamento.datilografar(stepText, Acabamento.viet(text), 55)
end

-- ===== animação de entrada (tweens; os únicos laços são a pontilha, 1 Hz, e o briefing) =====
local alive = 0 -- geração da tela aberta: laços antigos param sozinhos
local leaderTween: Tween? = nil

local function drawMap(delay0: number)
	for _, d in draws do
		d.f.Size = d.from
		tween(d.f, 0.7, { Size = d.full }, Enum.EasingStyle.Quad, OUT, delay0 + d.delay)
	end
	Acabamento.tracar(axisBeach, 0.93, 0.6, 0.4, 0.46, 1.6, delay0 + 1.3)
	Acabamento.tracar(axisLz, 0.5, 0.06, 0.38, 0.36, 1.1, delay0 + 2.1)
	objective.raiz.Visible = false
	task.delay(delay0 + 2.9, function()
		objective.raiz.Visible = true
		Acabamento.pulsar(objective, true)
	end)
	-- o carimbo cai na carta
	secret.TextTransparency = 1
	secretEdge.Transparency = 1
	secretScale.Scale = 1.8
	tween(secret, 0.22, { TextTransparency = 0.12 }, QUINT_OUT, OUT, delay0 + 3.2)
	tween(secretEdge, 0.22, { Transparency = 0.2 }, QUINT_OUT, OUT, delay0 + 3.2)
	tween(secretScale, 0.3, { Scale = 1 }, QUINT_OUT, OUT, delay0 + 3.2)
end

local function briefingLoop(my: number)
	task.spawn(function()
		local i = 0
		task.wait(1.6)
		while alive == my do
			i = i % #BRIEFING + 1
			local b = BRIEFING[i]
			briefIdx.Text = string.format("%d/%d", i, #BRIEFING)
			briefSrc.Text = string.format("Fonte: The First Fight (USMC, 2015), %s", b.pagina)
			briefText.TextTransparency = 0
			local tw = Acabamento.datilografar(briefText, Acabamento.viet(b.texto), 48)
			briefLine.Size = UDim2.fromOffset(560, 2)
			local typing = (utf8.len(b.texto) or 60) / 48
			tween(briefLine, typing + 4.2, { Size = UDim2.fromOffset(0, 2) }, Enum.EasingStyle.Linear)
			tw.Completed:Wait()
			task.wait(4.2)
			if alive ~= my then
				break
			end
			tween(briefText, 0.35, { TextTransparency = 1 }, Enum.EasingStyle.Sine, IN)
			task.wait(0.4)
		end
	end)
end

local function leaderLoop(my: number)
	if not leaderTween then
		sweep.Rotation = 0
		local tw = TweenService:Create(sweep, TweenInfo.new(1, Enum.EasingStyle.Linear, OUT, -1), { Rotation = 360 })
		tw:Play()
		leaderTween = tw
	end
	task.spawn(function()
		local n = 3
		while alive == my do
			digit.Text = tostring(n)
			n = if n == 1 then 3 else n - 1
			task.wait(1)
		end
	end)
end

local function intro()
	alive += 1
	local my = alive
	-- título: entra com leve recuo de câmera (escala) e esmaecendo
	title.TextTransparency = 1
	titleScale.Scale = 1.06
	tween(title, 1.1, { TextTransparency = 0 }, Enum.EasingStyle.Sine, OUT, 0.15)
	tween(titleScale, 1.4, { Scale = 1 }, QUINT_OUT, OUT, 0.15)
	Acabamento.datilografar(kicker, kicker.Text, 40, 0.1)
	rule.Size = UDim2.fromOffset(0, 3)
	hair.Size = UDim2.fromOffset(0, 1)
	tween(rule, 0.9, { Size = UDim2.fromOffset(560, 3) }, QUINT_OUT, OUT, 0.5)
	tween(hair, 1.1, { Size = UDim2.fromOffset(380, 1) }, QUINT_OUT, OUT, 0.7)
	Acabamento.datilografar(sub, sub.Text, 45, 0.9)
	-- briefing e carta deslizam para o lugar (o cartão entra inteiro: fundo, selo, título, régua)
	brief.Position = UDim2.fromOffset(92, 326)
	for _, f in briefFades do
		(f.o :: any)[f.prop] = 1
		tween(f.o, 0.7, { [f.prop] = f.base }, QUINT_OUT, OUT, 0.9)
	end
	tween(brief, 0.7, { Position = UDim2.fromOffset(92, 302) }, QUINT_OUT, OUT, 0.9)
	map.Position = UDim2.fromOffset(840, 128)
	map.Rotation = 6
	tween(map, 0.9, { Position = UDim2.fromOffset(812, 104), Rotation = 2 }, QUINT_OUT, OUT, 0.3)
	mapShadow.ImageTransparency = 1
	tween(mapShadow, 0.9, { ImageTransparency = 0.35 }, Enum.EasingStyle.Sine, OUT, 0.3)
	drawMap(0.6)
	briefingLoop(my)
	leaderLoop(my)
end

-- ===== CONTINUAR e CONFIGURAÇÕES (D-186) =====
local allReady = false
local capped = false
local closing = false
local pulse: Tween? = nil
local hintDev = "" -- o aparelho da última dica (a dica só muda quando ele muda)

-- o aparelho em uso: "pad", "touch" ou "keys" (a dica e o chip da tecla mudam com ele)
local function device(): string
	local last = UserInputService:GetLastInputType()
	if UserInputService.GamepadEnabled and string.sub(last.Name, 1, 7) == "Gamepad" then
		return "pad"
	end
	if last == Enum.UserInputType.Touch or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return "touch"
	end
	return "keys"
end

local function refreshKeys()
	local dev = device()
	local pad = dev == "pad"
	local touch = dev == "touch"
	local function keyOf(bt: Btn, code: Enum.KeyCode, key: string)
		local img: string? = nil
		if pad then
			pcall(function()
				local v = UserInputService:GetImageForKeyCode(code) :: any
				if type(v) == "string" and v ~= "" then
					img = v
				end
			end)
		end
		bt.keyImg.Visible = img ~= nil
		bt.keyImg.Image = img or ""
		bt.keycap.Visible = img == nil and not touch
		bt.keyText.Text = key
		bt.text.Position = UDim2.fromOffset(if img == nil and touch then 22 else 84, 0)
	end
	keyOf(play, Enum.KeyCode.ButtonA, "ENTER")
	keyOf(desk, Enum.KeyCode.ButtonX, "C")
	if allReady and dev ~= hintDev then
		hintDev = dev
		setStep(
			if pad
				then "Pronto. Aperte A para continuar."
				elseif touch then "Pronto. Toque em CONTINUAR."
				else "Pronto. Aperte Enter ou clique em CONTINUAR."
		)
	end
end
UserInputService.LastInputTypeChanged:Connect(function()
	local before = play.keyImg.Visible
	refreshKeys()
	if allReady and before ~= play.keyImg.Visible and play.keyImg.Visible then
		GuiService.SelectedObject = play.b -- chegou o controle: o foco no CONTINUAR
	end
end)

local function hover(bt: Btn, on: boolean)
	tween(bt.scale, 0.18, { Scale = if on then 1.03 else 1 })
	tween(bt.b, 0.18, { BackgroundColor3 = if on then bt.hot else bt.base })
end
for _, bt in { play, desk } do
	bt.b.MouseEnter:Connect(function()
		hover(bt, true)
	end)
	bt.b.MouseLeave:Connect(function()
		hover(bt, false)
	end)
	bt.b.SelectionGained:Connect(function()
		hover(bt, true)
	end)
	bt.b.SelectionLost:Connect(function()
		hover(bt, false)
	end)
end

-- Sai esmaecendo por cima do lobby: tudo vai para um CanvasGroup que some (o lobby aparece por
-- trás, sem passar pelo preto) enquanto o palco sobe um pouco, como câmera recuando. O grupo existe
-- desde o início, vazio (em repouso o texto fica fora dele, nítido).
-- D-186: marca "Pronto" (o menu principal abre por baixo), espera o menu (atributo do jogador
-- "MenuPrincipal", até 4 s) e esmaece. settings: o menu abre a aba Configurações ("AbrirConfig").
-- O carregamento em segundo plano continua (ele não é da geração `alive`).
local exitGroup = Instance.new("CanvasGroup")
exitGroup.Name = "Saida"
exitGroup.Size = UDim2.fromScale(1, 1)
exitGroup.BackgroundTransparency = 1
exitGroup.Parent = gui
local function close(settings: boolean?)
	if closing or not allReady then
		return
	end
	closing = true
	mark(if settings then "configuracoes" else "continuar")
	Idioma.fechar()
	if pulse then
		pulse:Cancel()
		pulse = nil
	end
	GuiService.SelectedObject = nil
	gui:SetAttribute("AbrirConfig", if settings then true else nil)
	gui:SetAttribute("Pronto", true)
	local my = alive
	local w0 = os.clock()
	while player:GetAttribute("MenuPrincipal") ~= true and os.clock() - w0 < 4 and alive == my do
		task.wait(0.05)
	end
	gui:SetAttribute("Saindo", true) -- a mesa do lobby (LobbyScene) começa o travelling de chegada agora
	local cg = exitGroup -- criado vazio no início: nada novo nasce na hora da saída
	cg.GroupTransparency = 0
	bg.Parent = cg
	film.raiz.Parent = cg
	tween(stage, 1.0, { Position = UDim2.new(0.5, 0, 0.5, -14) }, Enum.EasingStyle.Sine, INOUT)
	local fade = tween(cg, 0.95, { GroupTransparency = 1 }, Enum.EasingStyle.Sine, INOUT, 0.05)
	fade.Completed:Wait()
	if alive == my then
		alive += 1 -- para os laços (pontilha, briefing, contagem)
	end
	Acabamento.ligar(film, false, 0)
	Acabamento.pulsar(objective, false)
	Acabamento.apagar(axisBeach)
	Acabamento.apagar(axisLz)
	setWaiting(false)
	if RunService:IsStudio() then
		-- no Studio a tela fica guardada para o gancho de teste (VT65DevTela)
		gui.Enabled = false
		bg.Parent = gui
		film.raiz.Parent = gui
		cg.GroupTransparency = 0
	else
		gui:Destroy()
	end
end

-- um botão entra: aparece, o fundo e o filete acendem, o texto e a tecla chegam
local function reveal(bt: Btn, delay: number)
	bt.b.Visible = true
	bt.b.BackgroundTransparency = 1
	bt.scale.Scale = 0.94
	tween(bt.b, 0.3, { BackgroundTransparency = 0 }, QUINT_OUT, OUT, delay)
	tween(bt.scale, 0.3, { Scale = 1 }, QUINT_OUT, OUT, delay)
	tween(bt.edge, 0.3, { Transparency = 0.2 }, QUINT_OUT, OUT, delay)
	for _, t in { bt.text, bt.arrow, bt.keyText } do
		tween(t, 0.25, { TextTransparency = 0 }, QUINT_OUT, OUT, delay + 0.08)
	end
	tween(bt.keycap, 0.25, { BackgroundTransparency = 0 }, QUINT_OUT, OUT, delay + 0.08)
	tween(bt.keyImg, 0.25, { ImageTransparency = 0 }, QUINT_OUT, OUT, delay + 0.08)
end

-- D-186: com o essencial pronto (ou no teto), aparecem o CONTINUAR e as CONFIGURAÇÕES. Nada avança
-- sozinho: o jogador escolhe quando sair (passar o mouse ou o foco só realça).
local function showButtons()
	if allReady then
		return
	end
	allReady = true
	mark(if capped then "botoes_teto" else "botoes")
	setWaiting(false)
	stepNo.Text = if capped then "QUASE" else "PRONTO"
	hintDev = ""
	refreshKeys() -- escreve a dica do aparelho na linha da etapa
	if capped then
		note("teto", "Parte do essencial ainda está chegando.")
	end
	reveal(desk, 0)
	reveal(play, 0.08)
	task.delay(0.45, function()
		if allReady and not closing and gui.Enabled then
			local tw = TweenService:Create(
				play.edge,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, INOUT, -1, true),
				{ Transparency = 0.75 }
			)
			tw:Play()
			pulse = tw
			if device() == "pad" then
				GuiService.SelectedObject = play.b
			end
		end
	end)
end

play.b.Activated:Connect(function()
	if allReady and not Idioma.recente() then
		task.spawn(close, false)
	end
end)
desk.b.Activated:Connect(function()
	if allReady and not Idioma.recente() then
		task.spawn(close, true)
	end
end)
UserInputService.InputBegan:Connect(function(input: InputObject)
	if closing or not gui.Enabled or Idioma.recente() then
		return -- com o cartão de idiomas aberto, A e Enter são dele
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.ButtonY and langChip.button.Visible then
		openLanguage()
	elseif not allReady or UserInputService:GetFocusedTextBox() then
		return
	elseif kc == Enum.KeyCode.Return or kc == Enum.KeyCode.KeypadEnter or kc == Enum.KeyCode.Space then
		task.spawn(close, false)
	elseif kc == Enum.KeyCode.ButtonA then
		-- A no controle: o botão com o foco (o GuiService já aperta ele); sem foco, CONTINUAR
		if GuiService.SelectedObject == nil then
			task.spawn(close, false)
		end
	elseif kc == Enum.KeyCode.C or kc == Enum.KeyCode.ButtonX then
		task.spawn(close, true)
	end
end)

-- ===== o que carregar =====
-- PreloadAsync em lotes: onStep(feitos, total) a cada asset e a cada lote. Devolve quantos falharam
-- (AssetFetchStatus.Failure; D-186: a tela diz, em vez de fingir que chegou)
local function preload(items: { any }, onStep: (done: number, total: number) -> ()): number
	local total = #items
	onStep(0, total)
	local done = 0
	local failed = 0
	local i = 1
	while i <= total do
		local batch = table.move(items, i, math.min(i + BATCH - 1, total), 1, {})
		local n = 0
		pcall(function()
			ContentProvider:PreloadAsync(batch, function(_id: string, status: Enum.AssetFetchStatus)
				n += 1
				if status == Enum.AssetFetchStatus.Failure then
					failed += 1
				end
				onStep(done + math.min(n, #batch), total)
			end)
		end)
		done += #batch
		onStep(done, total)
		i += BATCH
	end
	return failed
end

local seen: { [string]: boolean } = {}
local function addId(list: { any }, id: any)
	if type(id) == "string" and id ~= "" and not seen[id] then
		seen[id] = true
		table.insert(list, id)
	end
end
local function assetId(n: any): string?
	return if type(n) == "number" and n ~= 0 then string.format("rbxassetid://%d", n) else nil
end
-- lê uma propriedade de conteúdo (algumas não podem ser lidas por script: nil)
local function prop(o: Instance, name: string): any
	local ok, v = pcall(function()
		return (o :: any)[name]
	end)
	return if ok then v else nil
end

-- a arte de uma árvore de instâncias: um id por asset (o mesmo id em mil árvores entra uma vez)
local function scanArt(root: Instance?, list: { any })
	if not root then
		return
	end
	local all = root:GetDescendants()
	-- v41: malha vai como a PEÇA (uma por MeshId): o id em texto era pedido como imagem e cada um
	-- dava "Asset type does not match requested type" (511 avisos com o mapa todo) sem baixar a malha
	local function addMesh(inst: Instance, id: any)
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(list, inst)
		end
	end
	for k, d in all do
		if d:IsA("MeshPart") then
			addMesh(d, prop(d, "MeshId"))
			addId(list, prop(d, "TextureID"))
		elseif d:IsA("SpecialMesh") then
			addMesh(d, prop(d, "MeshId"))
			addId(list, prop(d, "TextureId"))
		elseif d:IsA("Decal") then -- Texture também
			addId(list, prop(d, "Texture"))
		elseif d:IsA("SurfaceAppearance") then
			local c = prop(d, "ColorMap")
			if type(c) == "string" then
				addId(list, c)
				addId(list, prop(d, "NormalMap"))
				addId(list, prop(d, "RoughnessMap"))
				addId(list, prop(d, "MetalnessMap"))
			else
				table.insert(list, d) -- sem leitura: o PreloadAsync pega o que ela usa
			end
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			addId(list, prop(d, "Image"))
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			addId(list, prop(d, "Texture"))
		elseif d:IsA("Shirt") then
			addId(list, prop(d, "ShirtTemplate"))
		elseif d:IsA("Pants") then
			addId(list, prop(d, "PantsTemplate"))
		elseif d:IsA("Sky") then
			for _, side in { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" } do
				addId(list, prop(d, side))
			end
		elseif d:IsA("MaterialVariant") then
			for _, m in { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" } do
				addId(list, prop(d, m))
			end
		end
		if k % 1500 == 0 then
			task.wait() -- varredura grande: um quadro de folga a cada 1.500 peças
		end
	end
end

local function sharedModule(name: string): any
	local shared = ReplicatedStorage:WaitForChild("Shared", 30)
	local m = shared and shared:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, v = pcall(require, m)
		if ok then
			return v
		end
	end
	return nil
end

local function interfaceList(): { any }
	local list: { any } = {}
	-- fontes: um rótulo por fonte (o PreloadAsync baixa a fonte do rótulo)
	for _, font in
		{
			HEAD,
			HEAD_REG,
			TYPE,
			BODY,
			GLYPH,
			Font.fromName("Oswald", Enum.FontWeight.Medium),
			Font.fromEnum(Enum.Font.GothamMedium),
			Font.fromEnum(Enum.Font.GothamBold),
		}
	do
		local l = Instance.new("TextLabel")
		l.FontFace = font
		l.Text = "VẠN TƯỜNG 1965"
		table.insert(list, l)
	end
	for _, img in { Acabamento.VINHETA, Acabamento.LUZ, Acabamento.SOMBRA } do
		addId(list, img)
	end
	-- botões do controle (os chips de dica e os botões das telas)
	for _, kc in
		{
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.ButtonB,
			Enum.KeyCode.ButtonX,
			Enum.KeyCode.ButtonY,
			Enum.KeyCode.ButtonL1,
			Enum.KeyCode.ButtonR1,
			Enum.KeyCode.ButtonL2,
			Enum.KeyCode.ButtonR2,
			Enum.KeyCode.ButtonL3,
			Enum.KeyCode.ButtonR3,
			Enum.KeyCode.ButtonSelect,
			Enum.KeyCode.DPadUp,
			Enum.KeyCode.DPadDown,
			Enum.KeyCode.DPadLeft,
			Enum.KeyCode.DPadRight,
			Enum.KeyCode.Thumbstick1,
			Enum.KeyCode.Thumbstick2,
		}
	do
		pcall(function()
			addId(list, UserInputService:GetImageForKeyCode(kc))
		end)
	end
	-- imagens que o servidor resolveu (caveira do abate, carta tática) e as do AssetIds que já são
	-- imagens (chão, céu)
	for name, v in ReplicatedStorage:GetAttributes() do
		if string.sub(name, 1, 4) == "Img_" or string.sub(name, 1, 11) == "CartaImage_" then
			addId(list, assetId(v))
		end
	end
	local ids = sharedModule("AssetIds")
	if type(ids) == "table" then
		for _, group in { "GroundImages", "SkyImages", "CartaImages" } do
			local g = ids[group]
			if type(g) == "table" then
				for _, v in g do
					addId(list, assetId(v))
				end
			end
		end
	end
	return list
end

local function soundList(): { any }
	local list: { any } = {}
	local ids = sharedModule("AssetIds")
	local sounds = if type(ids) == "table" then ids.Sounds else nil
	if type(sounds) == "table" then
		for _, v in sounds do
			local id = assetId(v)
			if id and not seen[id] then
				seen[id] = true
				local s = Instance.new("Sound")
				s.SoundId = id
				table.insert(list, s)
			end
		end
	end
	return list
end

local function animList(): { any }
	local list: { any } = {}
	local anims = sharedModule("SoldierAnims")
	local clips = if type(anims) == "table" then anims.CLIPS else nil
	if type(clips) == "table" then
		for _, c in clips do
			local id = if type(c) == "table" then assetId(c.id) else nil
			if id and not seen[id] then
				seen[id] = true
				local a = Instance.new("Animation")
				a.AnimationId = id
				table.insert(list, a)
			end
		end
	end
	return list
end

-- ===== carregamento de verdade =====
-- D-186: o essencial em seis etapas; depois, o segundo plano. A geração do carregamento (runGen) é
-- separada da tela (alive): ao CONTINUAR, a tela some e o carregamento segue.
local runGen = 0
local bgStarted = false

-- a contagem real da etapa, à direita da linha do texto ("24/31")
local function count(done: number, total: number)
	countLbl.Text = if total > 0 and done < total then string.format("%d/%d", done, total) else ""
end

-- a linha do segundo plano: aqui embaixo da barra e no atributo "VT65Fundo" do jogador (o menu
-- principal mostra a mesma linha); nil quando acabou. Cada linha é um modelo inteiro (a tradução não
-- entra num modelo dentro de outro)
local function bgSet(text: string?)
	player:SetAttribute("VT65Fundo", text)
	bgLine.Text = text or "Tudo carregado."
end

-- armas, movimentos, sons e o mapa (uma vez por sessão)
local function background()
	if bgStarted then
		return
	end
	bgStarted = true
	task.spawn(function()
		local weapons: { any } = {}
		scanArt(ReplicatedStorage:FindFirstChild("VT65WeaponArt"), weapons)
		preload(weapons, function(done: number, total: number)
			bgSet(string.format("Em segundo plano · armas: %d/%d", done, total))
		end)
		mark("fundo_armas")
		preload(animList(), function(done: number, total: number)
			bgSet(string.format("Em segundo plano · movimentos: %d/%d", done, total))
		end)
		mark("fundo_movimentos")
		preload(soundList(), function(done: number, total: number)
			bgSet(string.format("Em segundo plano · sons: %d/%d", done, total))
		end)
		mark("fundo_sons")
		-- o mapa (v41, D-117): a arte do servidor, o streaming do mapa inteiro (o centro e o meio de cada
		-- quadrante, com o raio do streaming, ~360 m, cobrem a área e a cortina de fora; depois os QGs e os
		-- objetivos), 95% das peças do Map e a arte de tudo o que chegou
		local a0 = os.clock()
		while os.clock() - a0 < 30 do
			local mapF = workspace:FindFirstChild("Map")
			local artF = mapF and mapF:FindFirstChild("Art")
			if artF and artF:GetAttribute("Placed") == true then
				break
			end
			task.wait(0.25)
		end
		local mc = sharedModule("MapConfig")
		local spots: { Vector3 } = {}
		if type(mc) == "table" then
			local b = mc.Bounds
			if type(b) == "table" then
				local cx, cz = (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2
				local qx, qz = (b.maxX - b.minX) / 4, (b.maxZ - b.minZ) / 4
				table.insert(spots, Vector3.new(cx, 20, cz))
				for _, s in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
					table.insert(spots, Vector3.new(cx + s[1] * qx, 20, cz + s[2] * qz))
				end
			end
			for _, hq in (if type(mc.HQ) == "table" then mc.HQ else {}) :: any do
				table.insert(spots, Vector3.new(hq.x, 20, hq.z))
			end
			for _, sp in (if type(mc.Strongpoints) == "table" then mc.Strongpoints else {}) :: any do
				table.insert(spots, Vector3.new(sp.x, 20, sp.z))
			end
		end
		for k, p in spots do
			bgSet(string.format("Em segundo plano · mapa: %d/%d lugares", k - 1, #spots))
			pcall(function()
				player:RequestStreamAroundAsync(p, 8)
			end)
		end
		local mapF = workspace:FindFirstChild("Map")
		local want = if mapF then mapF:GetAttribute("PartCount") else nil
		if mapF and type(want) == "number" and want > 0 then
			local w0 = os.clock()
			local goal = math.floor(want * MAP_PARTS_FRAC)
			while os.clock() - w0 < MAP_PARTS_MAX_S do
				local n = 0
				for _, d in mapF:GetDescendants() do
					if d:IsA("BasePart") then
						n += 1
					end
				end
				bgSet(string.format("Em segundo plano · peças do mapa: %d/%d", math.min(n, goal), goal))
				if n >= goal then
					break
				end
				task.wait(1)
			end
		end
		mark("fundo_pecas")
		bgSet("Em segundo plano · arte do mapa…")
		local art: { any } = {}
		scanArt(ReplicatedStorage, art)
		scanArt(workspace, art)
		scanArt(Lighting, art)
		pcall(function()
			scanArt(game:GetService("MaterialService"), art)
		end)
		preload(art, function(done: number, total: number)
			bgSet(string.format("Em segundo plano · arte do mapa: %d/%d", done, total))
		end)
		mark("fundo_mapa")
		bgSet(nil)
	end)
end

local function run()
	runGen += 1
	local my = runGen
	-- teto do essencial: com ESSENTIAL_CAP_S, os botões aparecem com o que já chegou
	task.delay(ESSENTIAL_CAP_S, function()
		if runGen == my and not allReady then
			capped = true
			showButtons()
		end
	end)
	local failed = 0
	local function addFail(n: number)
		failed += n
		if failed > 0 then
			note("falhas", string.format("%d arquivos não baixaram; o jogo tenta de novo.", failed))
		end
	end
	-- 1. o jogo
	setStep("Recebendo o jogo…")
	setWaiting(true, 1)
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	setWaiting(false)
	setFrac(1, 1)
	-- 2. o servidor (sem ele nada funciona: avisa e continua esperando)
	setStep("Recebendo as ordens do servidor…")
	setWaiting(true, 2)
	if not ReplicatedStorage:WaitForChild("VT65Remotes", REMOTES_WARN_S) then
		warnStep(2)
		note("servidor", "O servidor demora a responder.")
		setStep("O servidor ainda não respondeu: esperando…")
		ReplicatedStorage:WaitForChild("VT65Remotes")
		note("servidor", nil)
	end
	setWaiting(false)
	setFrac(2, 1)
	if runGen ~= my then
		return
	end
	-- 3. a interface (a carta tática chega do servidor logo no início: espera um pouco por ela)
	setStep("Carregando fontes, papéis e a interface…")
	local w0 = os.clock()
	while ReplicatedStorage:GetAttribute("CartaPronta") == nil and os.clock() - w0 < 6 do
		task.wait(0.2)
	end
	addFail(preload(interfaceList(), function(done: number, total: number)
		setFrac(3, if total > 0 then done / total else 1)
		count(done, total)
	end))
	setFrac(3, 1)
	-- 4. a ficha do jogador (o servidor põe "XP" quando o perfil chega; "DataReadOnly" antes, se não
	-- carregou). Sem ela, a tela diz: não mostra uma conta vazia como se fosse a dele.
	setStep("Buscando a sua ficha de serviço…")
	setWaiting(true, 4)
	local d0 = os.clock()
	while player:GetAttribute("XP") == nil and os.clock() - d0 < DATA_MAX_S and runGen == my do
		task.wait(0.2)
	end
	setWaiting(false)
	if player:GetAttribute("DataReadOnly") == true then
		warnStep(4)
		note("ficha", "Seus dados não carregaram: esta sessão não salva.")
	elseif player:GetAttribute("XP") == nil then
		warnStep(4)
		note("ficha", "Seus dados ainda não chegaram.")
		task.spawn(function()
			while player:GetAttribute("XP") == nil do
				player:GetAttributeChangedSignal("XP"):Wait()
			end
			note(
				"ficha",
				if player:GetAttribute("DataReadOnly") == true
					then "Seus dados não carregaram: esta sessão não salva."
					else nil
			)
		end)
	end
	setFrac(4, 1)
	-- 5. os manequins e os objetos do menu e da mesa (o PreviewService marca Ready quando termina)
	setStep("Montando os soldados e os objetos da mesa…")
	setWaiting(true, 5)
	local preview = ReplicatedStorage:WaitForChild("VT65Preview", PREVIEW_MAX_S)
	if preview then
		local p0 = os.clock()
		while preview:GetAttribute("Ready") ~= true and os.clock() - p0 < PREVIEW_MAX_S and runGen == my do
			task.wait(0.25)
		end
	end
	setWaiting(false)
	if not (preview and preview:GetAttribute("Ready") == true) then
		warnStep(5)
		note("soldados", "Os soldados do menu ainda estão chegando.")
	end
	local soldiers: { any } = {}
	scanArt(preview, soldiers)
	addFail(preload(soldiers, function(done: number, total: number)
		setFrac(5, if total > 0 then done / total else 1)
		count(done, total)
	end))
	setFrac(5, 1)
	-- 6. o terreno e os lugares dos planos do menu
	setStep("Abrindo o terreno de Vạn Tường…")
	setWaiting(true, 6)
	while ReplicatedStorage:GetAttribute("TerrainReady") ~= true and runGen == my do
		task.wait(0.25)
	end
	setWaiting(false)
	local mc = sharedModule("MapConfig")
	local places: { Vector3 } = {}
	if type(mc) == "table" and type(mc.Strongpoints) == "table" then
		for _, name in MENU_PLACES do
			for _, sp in mc.Strongpoints :: any do
				if sp.name == name then
					table.insert(places, Vector3.new(sp.x, 20, sp.z))
				end
			end
		end
	end
	for k, p in places do
		count(k - 1, #places)
		pcall(function()
			player:RequestStreamAroundAsync(p, 8)
		end)
		setFrac(6, k / #places)
	end
	count(0, 0)
	setFrac(6, 1)
	if runGen ~= my then
		return
	end
	task.wait(0.35) -- a última parte termina de encher antes dos botões
	if runGen == my and not allReady then
		showButtons()
	end
	background()
end

Acabamento.ligar(film, true, 0)
intro()
task.spawn(run)

-- ===== gancho de teste (só no Studio): a tela de volta, carregando de novo, para a foto =====
-- workspace:SetAttribute("VT65DevTela", "carregamento"): reabre e refaz a animação e o carregamento
-- essencial (o que já está na memória chega rápido). Fica aberta até o atributo mudar (outro valor
-- ou nil), o CONTINUAR ou as CONFIGURAÇÕES. O segundo plano não roda de novo (é uma vez por sessão).
if RunService:IsStudio() then
	local function demo()
		if gui.Parent == nil or (gui.Enabled and not closing) then
			return -- ainda é a entrada de verdade
		end
		closing, allReady, capped = false, false, false
		gui:SetAttribute("Saindo", nil)
		gui:SetAttribute("Pronto", nil)
		gui:SetAttribute("AbrirConfig", nil)
		gui.Enabled = true
		stage.Position = UDim2.fromScale(0.5, 0.5)
		for _, bt in { play, desk } do
			bt.b.Visible = false
			bt.b.BackgroundTransparency = 1
			bt.edge.Transparency = 1
			bt.text.TextTransparency, bt.arrow.TextTransparency, bt.keyText.TextTransparency = 1, 1, 1
			bt.keycap.BackgroundTransparency, bt.keyImg.ImageTransparency = 1, 1
		end
		table.clear(noteOrder)
		table.clear(noteText)
		enterHint.Text = ""
		countLbl.Text = ""
		stepNo.Text = string.format("ETAPA %d/%d", 1, N_STEPS)
		table.clear(seen)
		for i = 1, N_STEPS do
			frac[i] = 0
			warned[i] = false
			segs[i].fill.Size = UDim2.fromScale(0, 1)
			segs[i].fill.BackgroundColor3 = STAMP
		end
		for _, s in steps do
			s.done = false
			s.glyph.Text = "□"
			s.glyph.TextColor3 = KHAKI
			s.text.TextColor3 = KHAKI
			s.text.TextTransparency = 0.35
		end
		Acabamento.ligar(film, true, 0.3)
		intro()
		task.spawn(run)
	end
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "carregamento" then
			demo()
		elseif gui.Parent and gui.Enabled and allReady then
			task.spawn(close, false)
		end
	end)
end
