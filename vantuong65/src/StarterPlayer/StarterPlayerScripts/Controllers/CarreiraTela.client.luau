--!strict
-- D-247 (dono: "criar sistema de progressao e de vantagens"): a tela de carreira, em quatro quadros de
-- latão: medalhas, árvore de vantagens, nível do soldado e prestígio. O servidor confere tudo
-- (CarreiraService); aqui só se mostra e se pede. Abre por Bus "carreira_open".
-- Studio: workspace:SetAttribute("VT65DevTela", "carreira").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Carreira = require(ReplicatedStorage.Shared.Carreira)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local UiEfeitos = require(script.Parent.UiEfeitos)
local UiKit = require(script.Parent.UiKit)

local V, F = UiKit.V, UiKit.F
local px = UiKit.px
local K = px(1000, 1320) / 1000
local function s(n: number): number
	return math.floor(n * K + 0.5)
end

local W, H = s(1240), s(716)
local OURO = Color3.fromRGB(255, 206, 72)
local OURO_CLARO = Color3.fromRGB(255, 238, 176)
local LATAO = Color3.fromRGB(176, 128, 48)
local FUNDO = Color3.fromRGB(20, 17, 11)
local TILE = Color3.fromRGB(34, 29, 19)
local VERDE = Color3.fromRGB(92, 196, 92)

local function imagem(chave: string): string
	local id = (AssetIds.Carreira or {})[chave]
	return if id and id ~= 0 then "rbxassetid://" .. tostring(id) else ""
end

local gui = UiKit.screen("VT65Carreira", 38)
gui.Enabled = false
gui.IgnoreGuiInset = true

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.Active = true
dim.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Carreira"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(W, H)
panel.BackgroundColor3 = Color3.fromRGB(12, 11, 7)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui
UiKit.corner(panel, 4)
local fit = UiKit.fit(gui, panel, W, H, 10)
-- faíscas e ondas por cima do painel, em coordenadas de tela
local camadaFx = Instance.new("Frame")
camadaFx.Name = "Efeitos"
camadaFx.Size = UDim2.fromScale(1, 1)
camadaFx.BackgroundTransparency = 1
camadaFx.ZIndex = 30
camadaFx.Parent = gui

-- ===== peças =====
local function bronze(o: Instance, grossura: number?)
	local e = Instance.new("UIStroke")
	e.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	e.Thickness = grossura or s(2)
	e.Color = Color3.new(1, 1, 1)
	e.Parent = o
	local g = Instance.new("UIGradient")
	g.Rotation = 35
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 82, 30)),
		ColorSequenceKeypoint.new(0.35, OURO_CLARO),
		ColorSequenceKeypoint.new(0.62, OURO),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(104, 70, 24)),
	})
	g.Parent = e
	return e
end

local function quadro(parent: Instance, x: number, y: number, w: number, h: number, cor: Color3?): Frame
	local f = Instance.new("Frame")
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = cor or FUNDO
	f.BorderSizePixel = 0
	f.Parent = parent
	UiKit.corner(f, 3)
	return f
end

local function letra(
	parent: Instance,
	txt: string,
	tam: number,
	cor: Color3,
	fonte: any,
	x: number,
	y: number,
	w: number,
	h: number
): TextLabel
	local t = UiKit.rotulo(parent, tam, cor, fonte)
	t.Text = txt
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.TextWrapped = h > tam * 1.7
	t.TextYAlignment = if h > tam * 1.7 then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	return t
end

local function foto(parent: Instance, id: string, x: number, y: number, w: number, h: number): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.Image = id
	i.ScaleType = Enum.ScaleType.Fit
	i.Position = UDim2.fromOffset(x, y)
	i.Size = UDim2.fromOffset(w, h)
	i.Parent = parent
	return i
end

local function secao(x: number, y: number, w: number, h: number, titulo: string, sub: string): Frame
	local f = quadro(panel, x, y, w, h)
	f.BackgroundTransparency = 0.05
	f.Name = titulo
	f.ClipsDescendants = true
	bronze(f)
	do
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(58, 45, 24), Color3.fromRGB(16, 14, 9))
		g.Parent = f
	end
	for i = 0, 2 do -- divisa da patente, ao lado do título
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Text = "︿"
		d.Font = Enum.Font.ArimoBold
		d.TextSize = s(30)
		d.TextColor3 = OURO
		d.Position = UDim2.fromOffset(s(12), s(4 + i * 10))
		d.Size = UDim2.fromOffset(s(40), s(26))
		d.Parent = f
	end
	local t = UiKit.title(f, titulo, s(30), OURO_CLARO)
	t.Position = UDim2.fromOffset(s(58), s(6))
	t.Size = UDim2.fromOffset(w - s(70), s(36))
	local d = letra(f, sub, s(14), V.KHAKI, F.BODY, s(58), s(40), w - s(70), s(18))
	d.TextTruncate = Enum.TextTruncate.AtEnd
	return f
end

local function botaoTile(parent: Instance, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.Size = UDim2.fromScale(1, 1)
	b.ZIndex = 8
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = parent
	UiKit.bind(b, onClick)
	return b
end

-- ===== cabeçalho =====
local titulo = UiKit.title(panel, "CARREIRA", s(36), OURO)
titulo.Position = UDim2.fromOffset(s(18), s(6))
titulo.Size = UDim2.fromOffset(s(360), s(44))
local fechar = UiKit.action(panel, "FECHAR", "secondary", function()
	Bus.fire("carreira_close")
end, { action = "ui_back", ctx = "menu", h = s(38) })
fechar.button.AnchorPoint = Vector2.new(1, 0)
fechar.button.Position = UDim2.new(1, -s(14), 0, s(10))
fechar.button.Size = UDim2.fromOffset(s(140), s(38))

local CW = (W - s(14) * 2 - s(12)) // 2
local TOPO, ALTO1, ALTO2 = s(56), s(340), s(296)
local X1, X2 = s(14), s(14) + CW + s(12)
local Y2 = TOPO + ALTO1 + s(10)

-- ===== medalhas =====
local med = secao(X1, TOPO, CW, ALTO1, "MEDALHAS E CONQUISTAS", "Reconhecimento pelo que você faz em combate.")
local vitrine = quadro(med, s(12), s(66), s(176), s(262), Color3.fromRGB(26, 21, 13))
bronze(vitrine, 1)
local vitrineImg = foto(vitrine, "", s(8), s(2), s(160), s(160))
local vitrineNome = letra(vitrine, "", s(15), OURO_CLARO, F.TITLE_MED, s(8), s(162), s(160), s(22))
vitrineNome.TextXAlignment = Enum.TextXAlignment.Center
vitrineNome.TextTruncate = Enum.TextTruncate.AtEnd
local vitrineDesc = letra(vitrine, "", s(12), V.TEXT, F.BODY, s(8), s(186), s(160), s(50))
vitrineDesc.TextXAlignment = Enum.TextXAlignment.Center
local vitrineConta = letra(vitrine, "", s(13), OURO, F.TITLE_MED, s(8), s(238), s(160), s(18))
vitrineConta.TextXAlignment = Enum.TextXAlignment.Center

type Tile = { f: Frame, img: ImageLabel, tranca: TextLabel, borda: UIStroke, id: string? }
local abas: { [string]: { b: TextButton, t: TextLabel } } = {}
local abaAtual = "todas"
local ABAS = {
	{ "todas", "TODAS" },
	{ "combate", "COMBATE" },
	{ "objetivos", "OBJETIVOS" },
	{ "suporte", "SUPORTE" },
	{ "especiais", "ESPECIAIS" },
}
local tiles: { Tile } = {}
local medSel: string? = nil
local pintaMedalhas: () -> () = function() end

local gx0, gw = s(198), CW - s(210)
local larguraAba = (gw - s(4) * 4) // 5
for i, a in ABAS do
	local f = quadro(med, gx0 + (i - 1) * (larguraAba + s(4)), s(66), larguraAba, s(28), TILE)
	local e = Instance.new("UIStroke")
	e.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	e.Color = LATAO
	e.Parent = f
	local t = letra(f, a[2], s(12), V.TEXT, F.TITLE_MED, 0, 0, larguraAba, s(28))
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextScaled = true
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = s(13)
	lim.Parent = t
	local b = botaoTile(f, function()
		abaAtual = a[1]
		pintaMedalhas()
	end)
	abas[a[1]] = { b = b, t = t }
	b:SetAttribute("Aba", a[1])
end

local TW = (gw - s(6) * 4) // 5
local TH = s(84)
for i = 1, 10 do
	local col, lin = (i - 1) % 5, (i - 1) // 5
	local f = quadro(med, gx0 + col * (TW + s(6)), s(102) + lin * (TH + s(6)), TW, TH, TILE)
	local borda = Instance.new("UIStroke")
	borda.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	borda.Color = LATAO
	borda.Parent = f
	local img = foto(f, "", s(3), s(3), TW - s(6), TH - s(6))
	local tranca = letra(f, "🔒", s(14), V.TEXT, F.BODY, TW - s(22), s(2), s(20), s(20))
	local t: Tile = { f = f, img = img, tranca = tranca, borda = borda, id = nil }
	tiles[i] = t
	botaoTile(f, function()
		if t.id then
			medSel = t.id
			pintaMedalhas()
		end
	end)
end

local contaTxt = letra(med, "", s(14), OURO_CLARO, F.TITLE_MED, gx0, s(286), s(190), s(20))
local pctTxt = letra(med, "", s(14), OURO_CLARO, F.TITLE_MED, gx0 + gw - s(60), s(286), s(60), s(20))
pctTxt.TextXAlignment = Enum.TextXAlignment.Right
local barraMed = quadro(med, gx0, s(310), gw, s(10), Color3.fromRGB(46, 40, 28))
local cheioMed = quadro(barraMed, 0, 0, 0, s(10), OURO)
cheioMed.Size = UDim2.fromScale(0, 1)

-- ===== vantagens =====
local van = secao(X2, TOPO, CW, ALTO1, "VANTAGENS", "Bônus permanentes, ganhos jogando.")
local caixaPontos = quadro(van, CW - s(170), s(8), s(158), s(48), Color3.fromRGB(26, 21, 13))
bronze(caixaPontos, 1)
local pontosRot = letra(caixaPontos, "PONTOS DE VANTAGEM", s(11), V.TEXT, F.TITLE_MED, 0, s(3), s(158), s(16))
pontosRot.TextXAlignment = Enum.TextXAlignment.Center
local pontosTxt = UiKit.title(caixaPontos, "★ 0", s(24), OURO)
pontosTxt.Position = UDim2.fromOffset(0, s(18))
pontosTxt.Size = UDim2.fromOffset(s(158), s(28))
pontosTxt.TextXAlignment = Enum.TextXAlignment.Center

type NoUi = { f: Frame, img: ImageLabel, borda: UIStroke, marca: TextLabel, tranca: TextLabel }
local nosUi: { [string]: NoUi } = {}
local ligas: { { f: Frame, a: string, b: string } } = {}
local noSel = "passo"
local NO, PASSOX, PASSOY = s(62), s(86), s(84)
local ax, ay = s(18), s(70)
local function centro(n: Carreira.No): (number, number)
	return ax + (n.coluna - 1) * PASSOX + NO // 2, ay + (n.linha - 1) * PASSOY + NO // 2
end
for _, n in Carreira.ARVORE do
	if n.requer then
		local r = Carreira.no(n.requer) :: Carreira.No
		local x0, y0 = centro(r)
		local x1, y1 = centro(n)
		local grossa = s(3)
		local l = quadro(van, math.min(x0, x1) - grossa // 2, math.min(y0, y1) - grossa // 2, 0, 0, LATAO)
		l.Size = UDim2.fromOffset(math.abs(x1 - x0) + grossa, math.abs(y1 - y0) + grossa)
		table.insert(ligas, { f = l, a = r.id, b = n.id })
	end
end
local pintaArvore: () -> () = function() end
for _, n in Carreira.ARVORE do
	local f = quadro(van, ax + (n.coluna - 1) * PASSOX, ay + (n.linha - 1) * PASSOY, NO, NO, Color3.fromRGB(30, 26, 17))
	f.Name = "No_" .. n.id
	local borda = Instance.new("UIStroke")
	borda.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	borda.Thickness = s(2)
	borda.Color = LATAO
	borda.Parent = f
	local img = foto(f, imagem("no_" .. n.icone), s(7), s(7), NO - s(14), NO - s(14))
	local marca = letra(f, "✓", s(14), Color3.new(1, 1, 1), F.TITLE_MED, NO - s(20), NO - s(20), s(20), s(20))
	marca.TextXAlignment = Enum.TextXAlignment.Center
	marca.BackgroundColor3 = Color3.fromRGB(46, 150, 62)
	marca.BackgroundTransparency = 0
	UiKit.corner(marca, s(10))
	marca.ZIndex = 4
	local tranca = letra(f, "🔒", s(12), V.TEXT, F.BODY, NO - s(19), NO - s(19), s(18), s(18))
	tranca.ZIndex = 4
	nosUi[n.id] = { f = f, img = img, borda = borda, marca = marca, tranca = tranca }
	botaoTile(f, function()
		noSel = n.id
		pintaArvore()
	end)
end

local detX = ax + 4 * PASSOX
local detalhe = quadro(van, detX, s(66), CW - detX - s(12), s(262), Color3.fromRGB(26, 21, 13))
bronze(detalhe, 1)
local detW = CW - detX - s(12)
local detImg = foto(detalhe, "", (detW - s(84)) // 2, s(10), s(84), s(84))
local detNome = UiKit.title(detalhe, "", s(21), OURO_CLARO)
detNome.Position = UDim2.fromOffset(s(8), s(98))
detNome.Size = UDim2.fromOffset(detW - s(16), s(30))
detNome.TextXAlignment = Enum.TextXAlignment.Center
detNome.TextScaled = true
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = s(21)
	c.Parent = detNome
end
local detDesc = letra(detalhe, "", s(13), V.TEXT, F.BODY, s(10), s(130), detW - s(20), s(58))
detDesc.TextXAlignment = Enum.TextXAlignment.Center
local pedir = function(op: string, id: string?)
	Net.event("Carreira_Action"):FireServer({ op = op, id = id })
end
local ativar = UiKit.action(detalhe, "ATIVAR", "primary", function()
	pedir("ativar", noSel)
end, { h = s(36) })
ativar.button.Position = UDim2.fromOffset(s(10), s(186))
ativar.button.Size = UDim2.fromOffset(detW - s(20), s(36))
local limpar = UiKit.action(detalhe, "REDISTRIBUIR", "secondary", function()
	pedir("limpar")
end, { h = s(28) })
limpar.button.Position = UDim2.fromOffset(s(10), s(226))
limpar.button.Size = UDim2.fromOffset(detW - s(20), s(28))

-- ===== nível =====
local pro = secao(X1, Y2, CW, ALTO2, "PROGRESSÃO", "Seu desenvolvimento no campo de batalha.")
local retrato = foto(pro, imagem("retrato"), s(4), s(62), s(190), s(232))
retrato.ScaleType = Enum.ScaleType.Crop
do
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.72, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = retrato
end
local px0 = s(204)
local pw = CW - px0 - s(14)
letra(pro, "NÍVEL DO SOLDADO", s(13), V.KHAKI, F.TITLE_MED, px0, s(64), s(190), s(18))
local nivelTxt = UiKit.title(pro, "NÍVEL 1", s(42), OURO)
nivelTxt.Position = UDim2.fromOffset(px0, s(80))
nivelTxt.Size = UDim2.fromOffset(s(220), s(50))
local xpRot = letra(pro, "XP ATUAL", s(13), V.KHAKI, F.TITLE_MED, px0 + s(220), s(64), pw - s(220), s(18))
xpRot.TextXAlignment = Enum.TextXAlignment.Right
local xpTxt = UiKit.title(pro, "", s(20), V.TEXT)
xpTxt.Position = UDim2.fromOffset(px0 + s(200), s(84))
xpTxt.Size = UDim2.fromOffset(pw - s(200), s(26))
xpTxt.TextXAlignment = Enum.TextXAlignment.Right
local barraXp = quadro(pro, px0 + s(200), s(116), pw - s(200), s(10), Color3.fromRGB(46, 40, 28))
local cheioXp = quadro(barraXp, 0, 0, 0, s(10), OURO)
cheioXp.Size = UDim2.fromScale(0, 1)
local proxTit = letra(pro, "PRÓXIMAS RECOMPENSAS", s(14), OURO_CLARO, F.TITLE_MED, px0, s(138), pw, s(20))
proxTit.TextTruncate = Enum.TextTruncate.AtEnd
type Prox = { f: Frame, nivel: TextLabel, valor: TextLabel, extra: TextLabel }
local prox: { Prox } = {}
local PW = (pw - s(6) * 3) // 4
for i = 1, 4 do
	local f = quadro(pro, px0 + (i - 1) * (PW + s(6)), s(162), PW, s(122), TILE)
	local e = Instance.new("UIStroke")
	e.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	e.Color = LATAO
	e.Parent = f
	local n = letra(f, "", s(12), V.KHAKI, F.TITLE_MED, 0, s(4), PW, s(16))
	n.TextXAlignment = Enum.TextXAlignment.Center
	foto(
		f,
		"rbxassetid://" .. tostring((AssetIds.Recompensas or {}).moeda or 0),
		(PW - s(44)) // 2,
		s(22),
		s(44),
		s(44)
	)
	local v = UiKit.title(f, "", s(19), OURO)
	v.Position = UDim2.fromOffset(0, s(68))
	v.Size = UDim2.fromOffset(PW, s(24))
	v.TextXAlignment = Enum.TextXAlignment.Center
	local x = letra(f, "", s(11), V.TEXT, F.BODY, s(3), s(92), PW - s(6), s(28))
	x.TextXAlignment = Enum.TextXAlignment.Center
	prox[i] = { f = f, nivel = n, valor = v, extra = x }
end

-- ===== prestígio =====
local pre = secao(X2, Y2, CW, ALTO2, "PRESTÍGIO", "Recomece o nível e prove sua experiência.")
foto(pre, imagem("prestigio"), s(8), s(62), s(208), s(226))
local pX = s(226)
local preTit = UiKit.title(pre, "PRESTÍGIO 0", s(34), OURO_CLARO)
preTit.Position = UDim2.fromOffset(pX, s(64))
preTit.Size = UDim2.fromOffset(s(240), s(42))
local preMax = letra(pre, "", s(14), V.TEXT, F.BODY, pX, s(106), s(240), s(20))
letra(pre, "Bônus permanente:", s(14), OURO_CLARO, F.TITLE_MED, pX, s(132), s(240), s(20))
local preB1 = letra(pre, "", s(13), V.TEXT, F.BODY, pX, s(154), s(240), s(20))
letra(pre, "● Patente, créditos e itens continuam seus", s(13), V.TEXT, F.BODY, pX, s(176), s(240), s(38))
letra(pre, "● Árvore de vantagens inteira liberada", s(13), V.TEXT, F.BODY, pX, s(216), s(240), s(38))
local prX = pX + s(246)
local prW = CW - prX - s(12)
local caixaPre = quadro(pre, prX, s(70), prW, s(214), Color3.fromRGB(26, 21, 13))
bronze(caixaPre, 1)
local confirmando = false
local confirmaAte = 0
local prestigiar: UiKit.Action
prestigiar = UiKit.action(caixaPre, "PRESTIGIAR", "primary", function()
	if not confirmando then
		confirmando = true
		confirmaAte = os.clock() + 5
		prestigiar.label.Text = "CONFIRMAR"
		task.delay(5.05, function()
			if confirmando and os.clock() >= confirmaAte then
				confirmando = false
				prestigiar.label.Text = "PRESTIGIAR"
			end
		end)
		return
	end
	confirmando = false
	prestigiar.label.Text = "PRESTIGIAR"
	pedir("prestigiar")
end, { h = s(52) })
prestigiar.button.Position = UDim2.fromOffset(s(8), s(14))
prestigiar.button.Size = UDim2.fromOffset(prW - s(16), s(52))
local preDesc = letra(caixaPre, "", s(13), V.TEXT, F.BODY, s(10), s(74), prW - s(20), s(132))
preDesc.TextXAlignment = Enum.TextXAlignment.Center

-- ===== desenho =====
local estado: { [string]: any }? = nil

local function milhar(n: number): string
	local t = tostring(math.floor(n))
	local partes = {}
	while #t > 3 do
		table.insert(partes, 1, string.sub(t, -3))
		t = string.sub(t, 1, -4)
	end
	table.insert(partes, 1, t)
	return table.concat(partes, ".")
end

pintaMedalhas = function()
	local st = estado
	if not st then
		return
	end
	for id, a in abas do
		local on = id == abaAtual
		local f = a.b.Parent :: Frame
		f.BackgroundColor3 = if on then V.AMBAR else TILE
		a.t.TextColor3 = if on then V.AMBAR_TEXTO else V.TEXT
	end
	local lista = {}
	local ganhas = 0
	for _, m in st.medalhas do
		if m.ganha then
			ganhas += 1
		end
		if abaAtual == "todas" or m.categoria == abaAtual then
			table.insert(lista, m)
		end
	end
	local sel: any = nil
	for _, m in st.medalhas do
		if m.id == medSel then
			sel = m
		end
	end
	sel = sel or lista[1] or st.medalhas[1]
	medSel = sel and sel.id
	for i, t in tiles do
		local m = lista[i]
		t.f.Visible = m ~= nil
		t.id = m and m.id
		if m then
			t.img.Image = imagem("med_" .. m.id)
			t.img.ImageColor3 = if m.ganha then Color3.new(1, 1, 1) else Color3.fromRGB(92, 88, 78)
			t.img.ImageTransparency = if m.ganha then 0 else 0.25
			t.tranca.Visible = not m.ganha
			t.borda.Color = if m.id == medSel then OURO elseif m.ganha then LATAO else Color3.fromRGB(70, 60, 42)
			t.borda.Thickness = if m.id == medSel then s(2) else 1
		end
	end
	if sel then
		vitrineImg.Image = imagem("med_" .. sel.id)
		vitrineImg.ImageColor3 = if sel.ganha then Color3.new(1, 1, 1) else Color3.fromRGB(120, 114, 100)
		vitrineNome.Text = sel.nome
		vitrineDesc.Text = sel.desc
		vitrineConta.Text = if sel.ganha then "✓ CONQUISTADA" else string.format("%d / %d", sel.atual, sel.meta)
	end
	local total = #st.medalhas
	contaTxt.Text = string.format("CONQUISTAS   %d / %d", ganhas, total)
	local f = if total > 0 then ganhas / total else 0
	pctTxt.Text = string.format("%d%%", math.floor(f * 100 + 0.5))
	cheioMed.Size = UDim2.fromScale(f, 1)
end

pintaArvore = function()
	local st = estado
	if not st then
		return
	end
	local nos: { [string]: boolean } = st.nos or {}
	pontosTxt.Text = string.format("★ %d", st.pontos)
	for _, n in Carreira.ARVORE do
		local u = nosUi[n.id]
		local on = nos[n.id] == true
		local livre = not n.requer or nos[n.requer] == true
		u.marca.Visible = on
		u.tranca.Visible = not on and not livre
		u.img.ImageColor3 = if on or livre then Color3.new(1, 1, 1) else Color3.fromRGB(96, 92, 80)
		u.img.ImageTransparency = if on then 0 elseif livre then 0.12 else 0.4
		u.borda.Color = if n.id == noSel then OURO_CLARO elseif on then OURO else Color3.fromRGB(84, 70, 44)
		u.borda.Thickness = if n.id == noSel or on then s(2) else 1
		u.f.BackgroundColor3 = if on then Color3.fromRGB(58, 44, 18) else Color3.fromRGB(30, 26, 17)
	end
	for _, l in ligas do
		l.f.BackgroundColor3 = if nos[l.a] and nos[l.b] then OURO else Color3.fromRGB(70, 58, 36)
	end
	local n = Carreira.no(noSel) :: Carreira.No
	detImg.Image = imagem("no_" .. n.icone)
	detNome.Text = UiKit.upper(n.nome)
	detDesc.Text = n.desc
	local on = nos[n.id] == true
	local livre = not n.requer or nos[n.requer] == true
	if on then
		ativar.label.Text = "✓ ATIVADA"
		ativar.enabled(false)
	elseif not livre then
		ativar.label.Text = "BLOQUEADA"
		ativar.enabled(false)
	elseif st.pontos <= 0 then
		ativar.label.Text = "SEM PONTOS"
		ativar.enabled(false)
	else
		ativar.label.Text = "ATIVAR"
		ativar.enabled(true)
	end
	limpar.enabled(next(nos) ~= nil)
end

local function pintaNivel()
	local st = estado
	if not st then
		return
	end
	nivelTxt.Text = string.format("NÍVEL %d", st.nivel)
	if st.falta > 0 then
		xpTxt.Text = string.format("%s / %s XP", milhar(st.dentro), milhar(st.falta))
		cheioXp.Size = UDim2.fromScale(math.clamp(st.dentro / st.falta, 0, 1), 1)
		proxTit.Text = string.format("PRÓXIMAS RECOMPENSAS (NÍVEL %d)", st.nivel + 1)
	else
		xpTxt.Text = "NÍVEL MÁXIMO"
		cheioXp.Size = UDim2.fromScale(1, 1)
		proxTit.Text = "NÍVEL MÁXIMO: PRESTIGIE PARA RECOMEÇAR"
	end
	for i, p in prox do
		local r = st.proximas[i]
		p.f.Visible = r ~= nil
		if r then
			p.nivel.Text = string.format("NÍVEL %d", r.nivel)
			p.valor.Text = string.format("+$ %d", r.creditos)
			p.extra.Text = if r.caixa then "+ Caixa de Serviço" elseif r.ponto then "+ 1 ponto de vantagem" else ""
		end
	end
	preTit.Text = string.format("PRESTÍGIO %d", st.prestigio)
	preMax.Text = string.format("Nível máximo: %d", st.nivelMax)
	preB1.Text = string.format("● +%d%% de XP em todas as partidas", math.floor((st.multXp - 1) * 100 + 0.5))
	if st.prestigio >= st.prestigioMax then
		prestigiar.label.Text = "MÁXIMO"
		prestigiar.enabled(false)
		preDesc.Text = "Você chegou ao último prestígio."
	elseif st.podePrestigiar then
		if not confirmando then
			prestigiar.label.Text = "PRESTIGIAR"
		end
		prestigiar.enabled(true)
		preDesc.Text = string.format(
			"O nível volta a 1. Você vai para o Prestígio %d, com +2%% de XP. Patente, créditos e itens não mudam.",
			st.prestigio + 1
		)
	else
		prestigiar.label.Text = "PRESTIGIAR"
		prestigiar.enabled(false)
		preDesc.Text = string.format("Chegue ao nível %d para prestigiar.", st.nivelMax)
	end
end

local function pintar()
	pintaMedalhas()
	pintaArvore()
	pintaNivel()
end

-- ===== abrir e fechar =====
local aberto = false
local token = 0
local function setAberto(on: boolean)
	if on == aberto then
		return
	end
	aberto = on
	token += 1
	local meu = token
	if on then
		gui.Enabled = true
		UiKit.opened("carreira", gui.DisplayOrder)
		Input.openMenu()
		task.spawn(function()
			local ok, st = pcall(function(): any
				return Net.func("Carreira_Get"):InvokeServer()
			end)
			if ok and type(st) == "table" and token == meu then
				estado = st
				pintar()
			end
		end)
		pintar()
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
		fit.play(TweenInfo.new(0.3, Enum.EasingStyle.Quint), 1, 0.96)
		UiKit.focus(panel)
	else
		UiKit.closed("carreira")
		UiKit.release(gui)
		Input.closeMenu()
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, info, { BackgroundTransparency = 1 }):Play()
		fit.play(info, 0.95)
		task.delay(0.18, function()
			if token == meu then
				gui.Enabled = false
			end
		end)
	end
end

Bus.on("carreira_open", function()
	Bus.fire("menu_close_request")
	setAberto(true)
end)
Bus.on("carreira_close", function()
	setAberto(false)
end)
Input.on("ui_back", "press", function()
	if aberto and UiKit.backFor("carreira") then
		setAberto(false)
	end
end)
UiKit.watch(panel, function()
	return aberto
end)

local MOTIVOS: { [string]: string } = {
	["sem pontos"] = "Sem pontos de vantagem.",
	bloqueada = "Ative a vantagem anterior primeiro.",
	ativa = "Essa vantagem já está ativa.",
}

Net.event("Carreira_State").OnClientEvent:Connect(function(st: any)
	if type(st) ~= "table" then
		return
	end
	estado = st
	if aberto then
		pintar()
	end
	local r = st.resultado
	if type(r) ~= "table" then
		return
	end
	if r.op == "ativar" and r.ok then
		local u = nosUi[r.id]
		if u and not UiKit.Estilo.reduzMovimento() then
			UiEfeitos.onda(camadaFx, u.f.AbsolutePosition + u.f.AbsoluteSize / 2, OURO, s(90), 0.5, 40)
		end
	elseif r.op == "ativar" and aberto then
		Toast.show(MOTIVOS[r.motivo] or "Não foi possível ativar.", "erro", { title = "Vantagens" })
	elseif r.op == "prestigiar" and r.ok then
		Toast.show(string.format("Prestígio %d alcançado!", r.prestigio), "recompensa", { title = "Prestígio" })
		if aberto and not UiKit.Estilo.reduzMovimento() then
			local c = pre.AbsolutePosition + pre.AbsoluteSize / 2
			UiEfeitos.faiscas(camadaFx, c, OURO, 40, { z = 40, tam = s(22), vmin = 200, vmax = 760 })
		end
	elseif r.op == "nivel" and r.ok then
		Toast.show(
			string.format("Nível %d: +$ %d", r.nivel, r.creditos),
			"recompensa",
			{ title = "Nível do soldado" }
		)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "carreira" then
			Bus.fire("carreira_open")
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
