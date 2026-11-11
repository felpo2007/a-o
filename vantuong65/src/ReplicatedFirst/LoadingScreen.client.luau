--!strict
-- Tela de entrada (pedido do dono, 2026-11-11: "telas de carregamento animadas de qualidade", "a
-- pessoa não entrar toda travada"; depois: "mais fluido e com uma qualidade gráfica melhor ... faça
-- com maestria", realismo de época). Identidade de 1965, própria do jogo:
--   - película por cima de tudo (Acabamento.filme: vinheta, grão a 24 quadros por segundo, poeira,
--     riscos e tremor de projetor) e a luz quente de um lampião no alto, à esquerda;
--   - à esquerda, o título e o briefing datilografado: fatos da operação tirados do The First
--     Fight (USMC, 2015; citações em research/F0_FONTES.md), um por vez, num cartão oliva;
--   - à direita, a carta 1:50.000 sendo traçada: grade, curvas de nível, os eixos a lápis vermelho
--     se desenhando e correndo, e a marca do objetivo piscando;
--   - embaixo, a pontilha de filme, a etapa datilografada, as etapas e a barra.
-- Progresso REAL, por etapas: jogo recebido, remotes do servidor, fontes e sons
-- (ContentProvider:PreloadAsync), manequins e modelos da mesa do lobby (PreloadAsync do que o
-- PreviewService publicou) e o terreno (atributo TerrainReady). A barra é um NumberValue em tween:
-- anda suave e nunca volta. O terreno não tem número (o servidor só avisa quando acaba): a barra
-- espera no fim da etapa anterior com um brilho correndo por ela.
-- "ENTRAR" (clique, toque, Enter/Espaço ou A) aparece quando o essencial (jogo, remotes, fontes)
-- está pronto; com tudo pronto, a tela sai sozinha esmaecendo sobre o lobby (sem tela preta).
-- Fora o Acabamento (no mesmo ReplicatedFirst), não depende de nada: aparece desde o 1º quadro.
-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevTela", "carregamento") reabre a
-- tela e refaz a animação (as etapas, já prontas, vão sendo marcadas de novo) para a foto; qualquer
-- outro valor (ou nil) fecha.
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
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

-- ----- título -----
local kicker = label(stage, TYPE, 16, KHAKI, 92, 104, 700, 22)
kicker.Text = "III MAF · CHU LAI · ORDEM DE OPERAÇÃO"
local title = label(stage, HEAD, 92, CARD, 86, 122, 760, 112)
title.Text = "VẠN TƯỜNG '65"
title.TextYAlignment = Enum.TextYAlignment.Center
local titleScale = Instance.new("UIScale")
titleScale.Parent = title
local rule = box(stage, STAMP, 92, 238, 0, 3)
local hair = box(stage, BRASS, 92, 245, 0, 1, 0.35)
local sub = label(stage, BODY, 20, KHAKI, 92, 256, 700, 26)
sub.Text = "OPERAÇÃO STARLITE · QUẢNG NGÃI · 18 DE AGOSTO DE 1965"

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
local stepText = label(stage, TYPE, 19, CARD, 206, 520, 830, 26)
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

local barBack = box(stage, DRAB, 206, 592, 974, 10)
corner(barBack, 2)
edge(barBack, KHAKI, 1, 0.7)
barBack.ClipsDescendants = true
local barFill = box(barBack, STAMP, 0, 0, 0, 10)
barFill.Size = UDim2.fromScale(0, 1)
lit(barFill, 90, 0.7)
local nib = box(barFill, BRASS_LIGHT, 0, 0, 2, 10, 0.1) -- ponta de tinta que anda com a barra
nib.AnchorPoint = Vector2.new(1, 0)
nib.Position = UDim2.fromScale(1, 0)
nib.Size = UDim2.new(0, 2, 1, 0)
for i = 1, 9 do -- régua de contador de filme
	local m = box(barBack, KHAKI, 0, 0, 1, 10, 0.55)
	m.Position = UDim2.new(i / 10, 0, 0, 0)
	m.Size = UDim2.new(0, 1, 1, 0)
	m.ZIndex = 2
end
local shine = box(barBack, CARD, 0, 0, 0, 0, 0) -- brilho que corre na etapa sem número
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
-- o número fica na linha da etapa (a fila de etapas usa a largura toda da barra)
local percent = label(stage, HEAD, 24, CARD, 1050, 514, 130, 32, Enum.TextXAlignment.Right)
percent.TextYAlignment = Enum.TextYAlignment.Center
percent.Text = "0%"

-- ----- ENTRAR (carimbo vermelho com filete de latão e o botão do controle num chip) -----
local enter = Instance.new("TextButton")
enter.Name = "Entrar"
enter.Position = UDim2.fromOffset(868, 622)
enter.Size = UDim2.fromOffset(312, 54)
enter.BackgroundColor3 = STAMP
enter.BackgroundTransparency = 1
enter.AutoButtonColor = false
enter.Text = ""
enter.Visible = false
enter.Parent = stage
corner(enter, 3)
lit(enter, 90, 0.72)
local enterEdge = edge(enter, BRASS, 1.5, 1)
local enterScale = Instance.new("UIScale")
enterScale.Parent = enter
local keycap = box(enter, CARD, 12, 12, 30, 30, 1)
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
keyImg.Parent = enter
local enterText = label(enter, HEAD, 24, CARD, 84, 0, 190, 54)
enterText.TextYAlignment = Enum.TextYAlignment.Center
enterText.Text = "ENTRAR NO LOBBY"
enterText.TextTransparency = 1
local enterArrow = label(enter, GLYPH, 18, CARD, 278, 0, 26, 54, Enum.TextXAlignment.Center)
enterArrow.TextYAlignment = Enum.TextYAlignment.Center
enterArrow.Text = "►"
enterArrow.TextTransparency = 1
local enterHint = label(stage, TYPE, 14, KHAKI, 206, 622, 640, 44)
enterHint.TextTransparency = 0.15

-- ----- idioma (pedido do dono, 2026-11-11): chip no alto à direita; Y no controle -----
local function openLanguage()
	if not Idioma.aberto() then
		Idioma.abrir({ z = 101 })
	end
end
local langChip = Idioma.chip(stage, { onClick = openLanguage, padKey = Enum.KeyCode.ButtonY })
langChip.button.AnchorPoint = Vector2.new(1, 0)
langChip.button.Position = UDim2.fromOffset(1180, 46)

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

-- ===== etapas =====
type Step = { name: string, weight: number, done: boolean, glyph: TextLabel, text: TextLabel, pop: UIScale }
local steps: { Step } = {}
local STEP_DEFS: { { name: string, weight: number } } = {
	{ name = "Jogo recebido", weight = 0.1 },
	{ name = "Ordens do servidor", weight = 0.1 },
	{ name = "Fontes, papéis e sons", weight = 0.2 },
	{ name = "Soldados e mesa", weight = 0.3 },
	{ name = "Terreno de Vạn Tường", weight = 0.3 },
}
for i, def in STEP_DEFS do
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
	local name = def.name
	local t = label(item, if string.find(name, "[\196-\244]") then BODY else TYPE, 15, KHAKI, 0, 0, 0, 26)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextWrapped = false
	t.TextTransparency = 0.35
	t.LayoutOrder = 2
	t.Text = name
	table.insert(steps, { name = name, weight = def.weight, done = false, glyph = g, text = t, pop = pop })
end

-- barra: valor exibido é um tween até o alvo; o alvo só sobe
local prog = Instance.new("NumberValue")
local target = 0
prog.Changed:Connect(function(v: number)
	local x = math.clamp(v, 0, 1)
	barFill.Size = UDim2.fromScale(x, 1)
	percent.Text = string.format("%d%%", math.floor(x * 100 + 0.5))
end)
local function setTarget(v: number)
	if v <= target then
		return
	end
	target = v
	tween(prog, 0.9, { Value = v })
end

local shineTween: Tween? = nil
local function setWaiting(on: boolean)
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

local function finish(i: number)
	local s = steps[i]
	if s.done then
		return
	end
	s.done = true
	s.glyph.Text = "■"
	s.glyph.TextColor3 = BRASS
	s.pop.Scale = 1.7
	tween(s.pop, 0.35, { Scale = 1 })
	tween(s.text, 0.3, { TextTransparency = 0, TextColor3 = CARD })
	local sum = 0
	for _, st in steps do
		if st.done then
			sum += st.weight
		end
	end
	setTarget(sum)
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

-- ===== ENTRAR =====
local essentialReady = false
local closing = false
local enterPulse: Tween? = nil

local function refreshKey()
	local pad = UserInputService.GamepadEnabled
		and string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
	local img: string? = nil
	if pad then
		pcall(function()
			local v = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA) :: any
			if type(v) == "string" and v ~= "" then
				img = v
			end
		end)
	end
	keyImg.Visible = img ~= nil
	keyImg.Image = img or ""
	keycap.Visible = img == nil
	keyText.Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "TOQUE" else "ENTER"
end
UserInputService.LastInputTypeChanged:Connect(refreshKey)

local function showEnter()
	refreshKey()
	enter.Visible = true
	enter.Position = UDim2.fromOffset(868, 646)
	tween(enter, 0.6, { Position = UDim2.fromOffset(868, 622), BackgroundTransparency = 0 })
	tween(enterEdge, 0.6, { Transparency = 0.25 })
	tween(enterText, 0.5, { TextTransparency = 0 }, QUINT_OUT, OUT, 0.1)
	tween(enterArrow, 0.5, { TextTransparency = 0 }, QUINT_OUT, OUT, 0.15)
	tween(keycap, 0.5, { BackgroundTransparency = 0 }, QUINT_OUT, OUT, 0.1)
	tween(keyText, 0.5, { TextTransparency = 0 }, QUINT_OUT, OUT, 0.1)
	tween(keyImg, 0.5, { ImageTransparency = 0 }, QUINT_OUT, OUT, 0.1)
	if not enterPulse then
		local tw = TweenService:Create(
			enterEdge,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, INOUT, -1, true, 0.7),
			{ Transparency = 0.75 }
		)
		tw:Play()
		enterPulse = tw
	end
	Acabamento.datilografar(enterHint, "Pronto para entrar. O resto carrega no lobby.", 70, 0.3)
end

local function hover(on: boolean)
	tween(enterScale, 0.18, { Scale = if on then 1.03 else 1 })
	tween(enter, 0.18, { BackgroundColor3 = if on then Color3.fromRGB(172, 50, 38) else STAMP })
end
enter.MouseEnter:Connect(function()
	hover(true)
end)
enter.MouseLeave:Connect(function()
	hover(false)
end)
enter.SelectionGained:Connect(function()
	hover(true)
end)
enter.SelectionLost:Connect(function()
	hover(false)
end)

-- Sai esmaecendo por cima do lobby: tudo vai para um CanvasGroup que some (o lobby aparece por
-- trás, sem passar pelo preto) enquanto o palco sobe um pouco, como câmera recuando. O grupo existe
-- desde o início, vazio (em repouso o texto fica fora dele, nítido).
local exitGroup = Instance.new("CanvasGroup")
exitGroup.Name = "Saida"
exitGroup.Size = UDim2.fromScale(1, 1)
exitGroup.BackgroundTransparency = 1
exitGroup.Parent = gui
local function close()
	if closing then
		return
	end
	closing = true
	Idioma.fechar()
	gui:SetAttribute("Saindo", true) -- a mesa do lobby (LobbyScene) começa o travelling de chegada agora
	local my = alive
	local cg = exitGroup -- criado vazio no início: nada novo nasce na hora da saída
	cg.GroupTransparency = 0
	bg.Parent = cg
	film.raiz.Parent = cg
	tween(stage, 1.0, { Position = UDim2.new(0.5, 0, 0.5, -14) }, Enum.EasingStyle.Sine, INOUT)
	local fade = tween(cg, 0.95, { GroupTransparency = 1 }, Enum.EasingStyle.Sine, INOUT, 0.05)
	fade.Completed:Wait()
	if alive == my then
		alive += 1 -- para os laços (pontilha e briefing)
	end
	Acabamento.ligar(film, false, 0)
	Acabamento.pulsar(objective, false)
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

enter.Activated:Connect(function()
	if essentialReady and not Idioma.recente() then
		close()
	end
end)
UserInputService.InputBegan:Connect(function(input: InputObject)
	if closing or not gui.Enabled or Idioma.recente() then
		return -- com o cartão de idiomas aberto, A e Enter são dele
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.ButtonY then
		openLanguage()
	elseif essentialReady and (kc == Enum.KeyCode.Return or kc == Enum.KeyCode.Space or kc == Enum.KeyCode.ButtonA) then
		close()
	end
end)

-- ===== carregamento de verdade =====
Acabamento.ligar(film, true, 0)
intro()
task.spawn(function()
	-- 1. jogo
	setStep("Recebendo o jogo…")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	finish(1)
	-- 2. remotes
	setStep("Recebendo as ordens do servidor…")
	ReplicatedStorage:WaitForChild("VT65Remotes", 60)
	finish(2)
	-- 3. fontes e sons
	setStep("Carregando fontes, papéis e sons…")
	local assets: { Instance } = {}
	for _, font in
		{ Enum.Font.Oswald, Enum.Font.SpecialElite, Enum.Font.Arimo, Enum.Font.ArimoBold, Enum.Font.GothamMedium }
	do
		local l = Instance.new("TextLabel")
		l.Font = font
		l.Text = "VẠN TƯỜNG 1965"
		table.insert(assets, l)
	end
	local bold = Instance.new("TextLabel")
	bold.FontFace = HEAD
	bold.Text = "VẠN TƯỜNG 1965"
	table.insert(assets, bold)
	for _, img in { Acabamento.VINHETA, Acabamento.LUZ, Acabamento.SOMBRA } do
		local i = Instance.new("ImageLabel")
		i.Image = img
		table.insert(assets, i)
	end
	local shared = ReplicatedStorage:WaitForChild("Shared", 30)
	local idsModule = shared and shared:FindFirstChild("AssetIds")
	if idsModule and idsModule:IsA("ModuleScript") then
		local ok, ids = pcall(require, idsModule)
		if ok and type(ids) == "table" and type((ids :: any).Sounds) == "table" then
			for _, key in { "radio_squelch", "ambience_paddy_morning", "ambience_tunnel", "ambience_village" } do
				local id = (ids :: any).Sounds[key]
				if type(id) == "number" and id ~= 0 then
					local snd = Instance.new("Sound")
					snd.SoundId = "rbxassetid://" .. id
					table.insert(assets, snd)
				end
			end
		end
	end
	local base = target
	local count = 0
	pcall(function()
		ContentProvider:PreloadAsync(assets, function()
			count += 1
			setTarget(base + steps[3].weight * count / math.max(#assets, 1) * 0.95)
		end)
	end)
	finish(3)
	essentialReady = true
	showEnter()
	-- 4. manequins e modelos da mesa (o PreviewService marca Ready quando termina)
	setStep("Montando os soldados e os objetos da mesa…")
	local preview = ReplicatedStorage:WaitForChild("VT65Preview", 60)
	if preview then
		setWaiting(true)
		local t0 = os.clock()
		while preview:GetAttribute("Ready") ~= true and os.clock() - t0 < 45 do
			task.wait(0.25)
		end
		setWaiting(false)
		local list2: { Instance } = { preview }
		local art = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
		if art then
			table.insert(list2, art)
		end
		local base4 = target
		local n4 = 0
		pcall(function()
			ContentProvider:PreloadAsync(list2, function()
				n4 += 1
				-- quantos assets há não se sabe antes: a barra anda e nunca passa da etapa
				setTarget(base4 + steps[4].weight * (1 - 1 / (1 + n4 * 0.15)))
			end)
		end)
	end
	finish(4)
	-- 5. terreno (sem número: o servidor só avisa quando acaba)
	if ReplicatedStorage:GetAttribute("TerrainReady") ~= true then
		setStep("O servidor está gerando o terreno de 4 × 2,4 km…")
		setWaiting(true)
		while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
			ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
		end
		setWaiting(false)
	end
	finish(5)
	setStep("Pronto. A mesa de campanha espera por você.")
	task.wait(1.1)
	close()
end)

-- ===== gancho de teste (só no Studio): a tela de volta, no estado bonito, para a foto =====
-- workspace:SetAttribute("VT65DevTela", "carregamento"): reabre e refaz a animação (as etapas já
-- prontas vão sendo marcadas de novo, 0,7 s cada; o terreno espera 1,5 s com o brilho correndo).
-- Fica aberta até o atributo mudar (outro valor ou nil) ou ENTRAR.
if RunService:IsStudio() then
	local function demo()
		if gui.Parent == nil or (gui.Enabled and not closing) then
			return -- ainda é a entrada de verdade
		end
		closing = false
		essentialReady = false
		gui:SetAttribute("Saindo", nil)
		gui.Enabled = true
		stage.Position = UDim2.fromScale(0.5, 0.5)
		enter.Visible = false
		enter.BackgroundTransparency = 1
		enterText.TextTransparency, enterArrow.TextTransparency = 1, 1
		enterHint.Text = ""
		target = 0
		prog.Value = 0
		for _, s in steps do
			s.done = false
			s.glyph.Text = "□"
			s.glyph.TextColor3 = KHAKI
			s.text.TextColor3 = KHAKI
			s.text.TextTransparency = 0.35
		end
		Acabamento.ligar(film, true, 0.3)
		intro()
		local my = alive
		task.spawn(function()
			local texts = {
				"Recebendo o jogo…",
				"Recebendo as ordens do servidor…",
				"Carregando fontes, papéis e sons…",
				"Montando os soldados e os objetos da mesa…",
				"O servidor está gerando o terreno de 4 × 2,4 km…",
			}
			for i = 1, #steps do
				if alive ~= my then
					return
				end
				setStep(texts[i])
				if i == 5 then
					setWaiting(true)
					task.wait(1.5)
					setWaiting(false)
				else
					task.wait(0.7)
				end
				finish(i)
				if i == 3 then
					essentialReady = true
					showEnter()
				end
			end
			setStep("Pronto. A mesa de campanha espera por você.")
		end)
	end
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "carregamento" then
			demo()
		elseif gui.Parent and gui.Enabled and essentialReady then
			task.spawn(close)
		end
	end)
end
