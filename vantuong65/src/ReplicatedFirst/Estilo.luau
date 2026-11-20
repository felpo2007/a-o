--!strict
-- Linguagem visual de todas as telas (pedido do dono, 2026-11-11: "não gosto dessa escrita no papel
-- e dessa ideia", "telas com muita escrita, mude"). Sai o papel datilografado (fichas de dossiê,
-- máquina de escrever, carimbos por toda parte); entra uma linguagem só:
--   - painéis escuros e sólidos (ou levemente translúcidos), filete fino;
--   - títulos grandes em condensada (Oswald) em caixa alta; números grandes;
--   - corpo em sans legível (Arimo); poucas palavras, hierarquia forte;
--   - cor de época só como acento: verde-oliva (ação), cáqui (destaque), vermelho de carimbo
--     (perigo, inimigo, baixa).
-- Fica no ReplicatedFirst porque a tela de entrada e a escolha de idioma rodam antes dos Controllers.
-- O UiKit reexporta tudo (UiKit.V, UiKit.F, UiKit.panel, ...) e acrescenta os botões ligados à
-- entrada (cursor virtual, foco do controle). Peças puras: criam instâncias, sem estado global.
-- Vietnamita: o Oswald não tem as letras; headFont devolve o Arimo Bold quando o texto tem letra
-- fora do Latin-1 (o Traducao.client faz o mesmo ao traduzir).
local GuiService = game:GetService("GuiService")

local Estilo = {}

-- ===== cores =====
Estilo.V = {
	-- fundos de tela cheia (cor única, escura e saturada)
	BG = Color3.fromRGB(14, 16, 12), -- quase preto, verde
	BG_OLIVE = Color3.fromRGB(26, 34, 20), -- lobby, vitória
	BG_RED = Color3.fromRGB(54, 12, 10), -- baixa, derrota
	BG_NIGHT = Color3.fromRGB(14, 18, 24), -- carregamento, mapa
	-- painéis
	PANEL = Color3.fromRGB(22, 25, 19), -- painel sólido
	PANEL_2 = Color3.fromRGB(32, 36, 27), -- painel dentro de painel, linha de lista
	PANEL_3 = Color3.fromRGB(46, 51, 38), -- realce (mouse, foco)
	LINE = Color3.fromRGB(84, 90, 68), -- filete
	-- texto
	TEXT = Color3.fromRGB(238, 234, 220), -- principal
	DIM = Color3.fromRGB(156, 156, 138), -- secundário, rótulos
	MUTED = Color3.fromRGB(104, 106, 92), -- apagado, desabilitado
	-- acentos de época
	OLIVE = Color3.fromRGB(104, 124, 64), -- ação principal (botão cheio)
	OLIVE_HI = Color3.fromRGB(130, 152, 82), -- ação principal com o foco
	KHAKI = Color3.fromRGB(206, 190, 142), -- destaque, números de ganho
	RED = Color3.fromRGB(176, 46, 34), -- perigo, baixa, inimigo
	RED_HI = Color3.fromRGB(212, 70, 52),
	BRASS = Color3.fromRGB(214, 172, 72), -- recompensa, foco
	-- lados
	US = Color3.fromRGB(86, 120, 186),
	VC = Color3.fromRGB(190, 64, 48),
	-- D-205 (prompt de interface §3: "âmbar ou amarelo para foco, seleção e ações importantes;
	-- verde-oliva e tons de papel, lona e metal como apoio"): as cores por função
	AMBAR = Color3.fromRGB(226, 166, 46), -- ação principal (botão cheio), seleção
	AMBAR_HI = Color3.fromRGB(244, 190, 72), -- ação principal com o foco
	AMBAR_TEXTO = Color3.fromRGB(24, 20, 10), -- texto sobre o âmbar (contraste 9:1)
	FOCO = Color3.fromRGB(255, 206, 64), -- moldura do foco (mouse, controle, toque)
	PAPEL = Color3.fromRGB(214, 203, 170), -- apoio: papel
	LONA = Color3.fromRGB(150, 140, 104), -- apoio: lona
	METAL = Color3.fromRGB(122, 128, 124), -- apoio: metal
}

-- D-205 (§3): estado de cada componente e de cada item, sempre com cor, símbolo E palavra (a cor
-- sozinha não basta). Os botões e cartões leem daqui.
-- rotulo: o que a etiqueta mostra (símbolo e palavra num texto só, para a tradução achar a frase)
export type Estado = { cor: Color3, simbolo: string, texto: string, rotulo: string }
Estilo.ESTADO = {
	-- componentes
	normal = { cor = Estilo.V.PANEL, simbolo = "", texto = "", rotulo = "" },
	foco = { cor = Estilo.V.FOCO, simbolo = "", texto = "", rotulo = "" },
	pressionado = { cor = Estilo.V.AMBAR, simbolo = "", texto = "", rotulo = "" },
	selecionado = { cor = Estilo.V.AMBAR, simbolo = "●", texto = "SELECIONADO", rotulo = "● SELECIONADO" },
	desabilitado = { cor = Estilo.V.MUTED, simbolo = "", texto = "INDISPONÍVEL", rotulo = "INDISPONÍVEL" },
	carregando = { cor = Estilo.V.PANEL_3, simbolo = "…", texto = "CARREGANDO", rotulo = "… CARREGANDO" },
	erro = { cor = Estilo.V.RED, simbolo = "!", texto = "ERRO", rotulo = "! ERRO" },
	-- itens
	adquirido = { cor = Estilo.V.OLIVE, simbolo = "✓", texto = "SEU", rotulo = "✓ SEU" },
	equipado = { cor = Estilo.V.AMBAR, simbolo = "✓", texto = "EQUIPADO", rotulo = "✓ EQUIPADO" },
	bloqueado = { cor = Estilo.V.PANEL_3, simbolo = "🔒", texto = "BLOQUEADO", rotulo = "🔒 BLOQUEADO" },
	-- "×" (Latin-1): o Arimo não tem o "✕", que saía como um quadrado (Studio, lote 90)
	indisponivel = { cor = Estilo.V.RED, simbolo = "×", texto = "OUTRA CLASSE", rotulo = "× OUTRA CLASSE" },
} :: { [string]: Estado }

-- ===== tipos =====
Estilo.F = {
	TITLE = Font.fromName("Oswald", Enum.FontWeight.Bold), -- títulos e números
	TITLE_MED = Font.fromName("Oswald", Enum.FontWeight.Medium), -- botões, abas
	TITLE_REG = Font.fromName("Oswald", Enum.FontWeight.Regular), -- rótulos em caixa alta
	BODY = Font.fromEnum(Enum.Font.Arimo), -- corpo
	BODY_B = Font.fromEnum(Enum.Font.ArimoBold), -- corpo em destaque, nomes
}

-- ===== tamanhos =====
function Estilo.tv(): boolean
	local ok, v = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and v == true
end
local TV = Estilo.tv()

-- tamanho de projeto no PC ou na TV
function Estilo.px(pc: number, tv: number): number
	return if TV then tv else pc
end

-- ===== preferências do jogador (D-205; prompt de interface §4 e §20) =====
-- O Roblox guarda três preferências de acessibilidade do jogador, e a interface segue as três:
--   - reduzir movimento (GuiService.ReducedMotionEnabled): o que desliza ou cresce vira troca direta
--     (UiKit.tween, Estilo.enter, a moldura de foco). Também liga pelas Configurações › Acessib.
--     (atributo local "VT65ReduzMovimento" do Player, posto pelo UiKit);
--   - transparência (GuiService.PreferredTransparency, de 0 a 1): multiplica a transparência dos
--     painéis e botões translúcidos (0 = fundos opacos);
--   - tamanho do texto (GuiService.PreferredTextSize): Estilo.ts e UiKit.text crescem por TEXTO_K.
-- Teste no Studio: workspace "VT65DevMovimento" (true), "VT65DevTransparencia" (0..1) e
-- "VT65DevTexto" ("Large", "Larger", "Largest"). Valem para o que for desenhado depois.
Estilo.TEXTO_K = { Medium = 1, Large = 1.15, Larger = 1.3, Largest = 1.45 } :: { [string]: number }
local RunService = game:GetService("RunService")
local function dev(nome: string): any
	return if RunService:IsStudio() then workspace:GetAttribute(nome) else nil
end
local function lerGui(prop: string): any
	local ok, v = pcall(function(): any
		return (GuiService :: any)[prop]
	end)
	return if ok then v else nil
end

function Estilo.reduzMovimento(): boolean
	if dev("VT65DevMovimento") == true then
		return true
	end
	local p = game:GetService("Players").LocalPlayer
	if p and p:GetAttribute("VT65ReduzMovimento") == true then
		return true
	end
	return lerGui("ReducedMotionEnabled") == true
end

function Estilo.transparencia(): number
	local d = dev("VT65DevTransparencia")
	if type(d) == "number" then
		return math.clamp(d, 0, 1)
	end
	local v = lerGui("PreferredTransparency")
	return if type(v) == "number" then math.clamp(v, 0, 1) else 1
end

function Estilo.textoK(): number
	local d = dev("VT65DevTexto")
	local nome: string? = if type(d) == "string" then d else nil
	if not nome then
		local v = lerGui("PreferredTextSize")
		nome = if typeof(v) == "EnumItem" then v.Name else "Medium"
	end
	return Estilo.TEXTO_K[nome :: string] or 1
end

-- transparência de um fundo translúcido, pela preferência do jogador (0 continua 0)
function Estilo.fundo(tr: number): number
	return tr * Estilo.transparencia()
end

-- texto: cresce com a preferência do jogador; na TV nunca abaixo de 24 px
function Estilo.ts(size: number): number
	local s = math.floor(size * Estilo.textoK() + 0.5)
	return if TV then math.max(s, 24) else s
end

-- título no Oswald; com letra do vietnamita, no Arimo Bold (o Oswald não tem)
function Estilo.headFont(text: string, font: Font?): Font
	if string.find(text, "[\196-\244]") then
		return Estilo.F.BODY_B
	end
	return font or Estilo.F.TITLE
end

-- ===== peças básicas =====
function Estilo.corner(o: Instance, r: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
	return c
end

function Estilo.stroke(o: Instance, color: Color3, thick: number, tr: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thick
	s.Transparency = tr or 0
	s.Parent = o
	return s
end

function Estilo.pad(o: Instance, l: number, r: number?, t: number?, b: number?): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l)
	p.PaddingRight = UDim.new(0, r or l)
	p.PaddingTop = UDim.new(0, t or 0)
	p.PaddingBottom = UDim.new(0, b or t or 0)
	p.Parent = o
	return p
end

-- lista vertical ou horizontal (gap em px)
function Estilo.list(o: Instance, horizontal: boolean?, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap or 0)
	if align then
		l.HorizontalAlignment = align
	end
	if horizontal then
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	l.Parent = o
	return l
end

-- texto sem fundo. font: Font (padrão: corpo). Tamanho já passa pelo mínimo da TV.
function Estilo.text(parent: Instance?, text: string, size: number, color: Color3?, font: Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.FontFace = font or Estilo.F.BODY
	t.TextColor3 = color or Estilo.V.TEXT
	t.TextSize = Estilo.ts(size)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Text = text
	t.Parent = parent
	return t
end

-- título: Oswald em caixa alta (quem chama passa o texto já em caixa alta: UiKit.upper)
function Estilo.title(parent: Instance?, text: string, size: number, color: Color3?): TextLabel
	local t = Estilo.text(parent, text, size, color, Estilo.headFont(text))
	t.TextTruncate = Enum.TextTruncate.AtEnd
	return t
end

-- rótulo pequeno em caixa alta (em cima de um número, cabeçalho de seção)
function Estilo.kicker(parent: Instance?, text: string, size: number?, color: Color3?): TextLabel
	local t = Estilo.text(parent, text, size or 14, color or Estilo.V.DIM, Estilo.headFont(text, Estilo.F.TITLE_REG))
	t.TextTruncate = Enum.TextTruncate.AtEnd
	return t
end

-- corpo: Arimo, quebra linha
function Estilo.body(parent: Instance?, text: string, size: number?, color: Color3?): TextLabel
	local t = Estilo.text(parent, text, size or 16, color or Estilo.V.DIM, Estilo.F.BODY)
	t.TextWrapped = true
	t.TextYAlignment = Enum.TextYAlignment.Top
	return t
end

-- painel escuro. tr: transparência do fundo (0 = sólido; 0,08 a 0,2 = levemente translúcido)
function Estilo.panel(parent: Instance?, color: Color3?, tr: number?, edge: boolean?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color or Estilo.V.PANEL
	f.BackgroundTransparency = Estilo.fundo(tr or 0) -- D-205: a preferência de transparência
	f.BorderSizePixel = 0
	Estilo.corner(f, 4)
	if edge ~= false then
		Estilo.stroke(f, Estilo.V.LINE, 1, 0.55)
	end
	f.Parent = parent
	return f
end

-- fundo de tela cheia: cor única escura, com a luz caindo de cima à esquerda
function Estilo.backdrop(parent: Instance?, color: Color3?): Frame
	local c = color or Estilo.V.BG
	local f = Instance.new("Frame")
	f.Name = "Fundo"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = c
	f.BorderSizePixel = 0
	f.Active = true -- nada atrás recebe clique
	local g = Instance.new("UIGradient")
	g.Rotation = 35
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.55, 0.55, 0.55))
	g.Parent = f
	f.Parent = parent
	return f
end

-- título enorme dentro de um retângulo de borda fina (o retângulo acompanha o texto)
function Estilo.titleBox(parent: Instance?, text: string, size: number, color: Color3?): (Frame, TextLabel)
	local box = Instance.new("Frame")
	box.Name = "Titulo"
	box.BackgroundTransparency = 1
	box.AutomaticSize = Enum.AutomaticSize.XY
	box.Size = UDim2.new()
	Estilo.stroke(box, color or Estilo.V.TEXT, Estilo.px(2, 3), 0.15)
	Estilo.pad(box, Estilo.px(18, 26), nil, Estilo.px(2, 4))
	local t = Estilo.text(box, text, size, color, Estilo.headFont(text))
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.new()
	box.Parent = parent
	return box, t
end

-- barra inclinada entre números (como "/")
function Estilo.slash(parent: Instance?, h: number, color: Color3?, order: number?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Barra"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(math.floor(h * 0.42), h)
	holder.LayoutOrder = order or 0
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.new(0, Estilo.px(3, 4), 1, 0)
	bar.Rotation = 18
	bar.BackgroundColor3 = color or Estilo.V.LINE
	bar.BorderSizePixel = 0
	bar.Parent = holder
	holder.Parent = parent
	return holder
end

-- número grande com o rótulo em cima
export type Stat = { frame: Frame, label: TextLabel, value: TextLabel }
function Estilo.stat(parent: Instance?, label: string, value: string, size: number?, order: number?): Stat
	local f = Instance.new("Frame")
	f.Name = "Numero"
	f.BackgroundTransparency = 1
	f.AutomaticSize = Enum.AutomaticSize.XY
	f.Size = UDim2.new()
	f.LayoutOrder = order or 0
	Estilo.list(f, false, 0)
	local n = size or 44
	local l = Estilo.kicker(f, label, math.max(12, math.floor(n * 0.32)))
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Size = UDim2.new()
	l.LayoutOrder = 1
	local v = Estilo.text(f, value, n, Estilo.V.TEXT, Estilo.F.TITLE)
	v.AutomaticSize = Enum.AutomaticSize.XY
	v.Size = UDim2.new()
	v.LayoutOrder = 2
	f.Parent = parent
	return { frame = f, label = l, value = v }
end

-- fileira de números separados por barras inclinadas
export type StatRow = { frame: Frame, stats: { Stat } }
function Estilo.statRow(parent: Instance?, items: { { string } }, size: number?): StatRow
	local row = Instance.new("Frame")
	row.Name = "Numeros"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Size = UDim2.new()
	local n = size or 44
	Estilo.list(row, true, math.floor(n * 0.4))
	local stats = {}
	for i, it in items do
		if i > 1 then
			Estilo.slash(row, math.floor(n * 1.5), nil, 2 * i - 1)
		end
		table.insert(stats, Estilo.stat(row, it[1], it[2], n, 2 * i))
	end
	row.Parent = parent
	return { frame = row, stats = stats }
end

-- etiqueta (pílula) de estado: PRONTO, BLOQUEADO, NOVO...
function Estilo.tag(parent: Instance?, text: string, color: Color3?, size: number?): TextLabel
	local t = Estilo.text(parent, text, size or 13, Estilo.V.TEXT, Estilo.headFont(text, Estilo.F.TITLE_MED))
	t.BackgroundColor3 = color or Estilo.V.OLIVE
	t.BackgroundTransparency = 0
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, Estilo.px(20, 30))
	t.TextXAlignment = Enum.TextXAlignment.Center
	Estilo.corner(t, 3)
	Estilo.pad(t, Estilo.px(8, 12))
	return t
end

-- barra de progresso: devolve o fundo e o preenchimento (Size.X.Scale = fração)
function Estilo.bar(parent: Instance?, h: number, color: Color3?): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Name = "Barra"
	back.BackgroundColor3 = Estilo.V.PANEL_2
	back.BorderSizePixel = 0
	back.Size = UDim2.new(1, 0, 0, h)
	back.ClipsDescendants = true
	Estilo.corner(back, math.floor(h / 2))
	local fill = Instance.new("Frame")
	fill.Name = "Cheio"
	fill.BackgroundColor3 = color or Estilo.V.OLIVE
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = back
	Estilo.corner(fill, math.floor(h / 2))
	back.Parent = parent
	return back, fill
end

-- ===== botões (só a forma; o UiKit liga ao clique, ao cursor virtual e ao realce) =====
-- kind: "primary" (enorme e cheio, oliva), "danger" (cheio, vermelho), "secondary" (fino, só
-- contorno), "ghost" (sem contorno, texto apagado). O botão tem:
--   - Rotulo: o texto (Oswald);
--   - Sub: texto menor à direita (contagem, preço), vazio por padrão;
--   - Tecla: ImageLabel do botão do controle à esquerda (escondida por padrão).
export type ButtonParts = { button: TextButton, label: TextLabel, sub: TextLabel, glyph: ImageLabel }
function Estilo.button(parent: Instance?, text: string, kind: string?, h: number?): ButtonParts
	local k = kind or "primary"
	local big = k == "primary" or k == "danger"
	local height = h or (if big then Estilo.px(64, 88) else Estilo.px(44, 62))
	local b = Instance.new("TextButton")
	b.Name = "Botao"
	b.AutoButtonColor = false
	b.Text = ""
	b.Size = UDim2.new(1, 0, 0, height)
	b.BorderSizePixel = 0
	-- D-205 (§3): a ação principal em âmbar, com texto escuro; o oliva fica de apoio
	b.BackgroundColor3 = if k == "primary" then Estilo.V.AMBAR elseif k == "danger" then Estilo.V.RED else Estilo.V.PANEL
	b.BackgroundTransparency = if big then 0 elseif k == "secondary" then Estilo.fundo(0.35) else 1
	Estilo.corner(b, 4)
	Estilo.stroke(
		b,
		if k == "primary" then Estilo.V.AMBAR_TEXTO elseif big then Estilo.V.TEXT else Estilo.V.LINE,
		1,
		if big then 0.8 elseif k == "ghost" then 1 else 0.1
	)
	local padX = Estilo.px(18, 26)
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Tecla"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0, 0.5)
	glyph.Position = UDim2.new(0, padX, 0.5, 0)
	local g = math.floor(height * (if big then 0.46 else 0.56))
	glyph.Size = UDim2.fromOffset(g, g)
	glyph.Visible = false
	glyph.Parent = b
	local label = Estilo.text(
		b,
		text,
		if big then math.floor(height * 0.42) else math.floor(height * 0.4),
		nil,
		Estilo.headFont(text, if big then Estilo.F.TITLE else Estilo.F.TITLE_MED)
	)
	label.Name = "Rotulo"
	label.Size = UDim2.new(1, -2 * padX, 1, 0)
	label.Position = UDim2.fromOffset(padX, 0)
	label.TextXAlignment = if big then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextColor3 = if k == "ghost"
		then Estilo.V.DIM
		elseif k == "primary" then Estilo.V.AMBAR_TEXTO
		else Estilo.V.TEXT
	local sub = Estilo.text(
		b,
		"",
		math.floor(height * (if big then 0.3 else 0.34)),
		if k == "primary" then Estilo.V.AMBAR_TEXTO else Estilo.V.TEXT,
		Estilo.F.TITLE_MED
	)
	sub.Name = "Sub"
	sub.AnchorPoint = Vector2.new(1, 0)
	sub.Position = UDim2.new(1, -padX, 0, 0)
	sub.Size = UDim2.new(0.45, 0, 1, 0)
	sub.TextXAlignment = Enum.TextXAlignment.Right
	sub.TextTransparency = 0.15
	b.Parent = parent
	return { button = b, label = label, sub = sub, glyph = glyph }
end

-- mostra o botão do controle (ou nada) à esquerda do rótulo, abrindo espaço para ele
function Estilo.setGlyph(p: ButtonParts, img: string?)
	local padX = p.label.Position.X.Offset
	p.glyph.Visible = img ~= nil
	p.glyph.Image = img or ""
	if img then
		local gw = p.glyph.Size.X.Offset + Estilo.px(10, 14)
		p.label.Position = UDim2.fromOffset(p.glyph.Position.X.Offset + gw, 0)
		p.label.Size = UDim2.new(1, -(p.glyph.Position.X.Offset + gw + padX), 1, 0)
	else
		p.label.Position = UDim2.fromOffset(p.glyph.Position.X.Offset, 0)
		p.label.Size = UDim2.new(1, -2 * p.glyph.Position.X.Offset, 1, 0)
	end
end

-- ===== cartão de item (itens liberados, recompensas) =====
-- miniatura quadrada (imagem ou sigla), nome e tipo. accent: cor da faixa de baixo.
export type ItemCard = {
	frame: Frame,
	thumb: Frame,
	image: ImageLabel,
	mark: TextLabel,
	name: TextLabel,
	kind: TextLabel,
}
function Estilo.itemCard(parent: Instance?, name: string, kind: string, accent: Color3?, w: number?): ItemCard
	local W = w or Estilo.px(200, 280)
	local H = Estilo.px(64, 90)
	local f = Estilo.panel(parent, Estilo.V.PANEL_2, 0, true)
	f.Name = "Item"
	f.Size = UDim2.fromOffset(W, H)
	local thumb = Instance.new("Frame")
	thumb.Name = "Miniatura"
	thumb.BackgroundColor3 = Estilo.V.PANEL_3
	thumb.BorderSizePixel = 0
	thumb.Position = UDim2.fromOffset(Estilo.px(6, 8), Estilo.px(6, 8))
	thumb.Size = UDim2.fromOffset(H - 2 * Estilo.px(6, 8), H - 2 * Estilo.px(6, 8))
	Estilo.corner(thumb, 3)
	thumb.Parent = f
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Fit
	image.Visible = false
	image.Parent = thumb
	local mark = Estilo.text(thumb, "", math.floor(H * 0.34), Estilo.V.KHAKI, Estilo.F.TITLE)
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	local x = H + Estilo.px(4, 6)
	local n = Estilo.text(f, name, Estilo.px(15, 22), Estilo.V.TEXT, Estilo.F.BODY_B)
	n.Position = UDim2.fromOffset(x, Estilo.px(8, 12))
	n.Size = UDim2.new(1, -x - Estilo.px(8, 10), 0, Estilo.px(20, 28))
	n.TextTruncate = Enum.TextTruncate.AtEnd
	local kd = Estilo.kicker(f, kind, Estilo.px(13, 20))
	kd.Position = UDim2.fromOffset(x, Estilo.px(32, 46))
	kd.Size = UDim2.new(1, -x - Estilo.px(8, 10), 0, Estilo.px(18, 26))
	local strip = Instance.new("Frame")
	strip.Name = "Faixa"
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0, 1)
	strip.Size = UDim2.new(1, 0, 0, Estilo.px(3, 4))
	strip.BackgroundColor3 = accent or Estilo.V.KHAKI
	strip.BorderSizePixel = 0
	strip.Parent = f
	return { frame = f, thumb = thumb, image = image, mark = mark, name = n, kind = kd }
end

-- D-205 (§3): etiqueta de estado com cor, símbolo e palavra ("✓ EQUIPADO", "🔒 BLOQUEADO"): a cor
-- sozinha não diz o estado. Texto escuro sobre o âmbar.
function Estilo.estadoTag(parent: Instance?, nome: string, size: number?): TextLabel
	local e = Estilo.ESTADO[nome] or Estilo.ESTADO.normal
	local t = Estilo.tag(parent, e.rotulo, e.cor, size)
	t.Name = "Estado"
	-- todas no Arimo Bold: o Oswald desenha o "×" como um ponto e não tem o "✓" (no Studio as
	-- etiquetas saíam em duas fontes)
	t.FontFace = Estilo.F.BODY_B
	t.TextColor3 = if e.cor == Estilo.V.AMBAR then Estilo.V.AMBAR_TEXTO else Estilo.V.TEXT
	t.Visible = e.rotulo ~= ""
	return t
end

-- estado de um cartão de item: etiqueta no canto de cima à direita (uma só, trocada no lugar) e o
-- nome apagado quando o item não pode ser usado. nil tira a etiqueta.
function Estilo.cardEstado(c: ItemCard, nome: string?)
	local velha = c.frame:FindFirstChild("Estado")
	if velha then
		velha:Destroy()
	end
	local apagado = nome == "bloqueado" or nome == "indisponivel"
	c.name.TextColor3 = if apagado then Estilo.V.DIM else Estilo.V.TEXT
	c.image.ImageTransparency = if apagado then 0.5 else 0
	if not nome then
		return
	end
	local t = Estilo.estadoTag(c.frame, nome, Estilo.px(11, 18))
	t.AnchorPoint = Vector2.new(1, 0)
	t.Position = UDim2.new(1, -Estilo.px(4, 6), 0, Estilo.px(4, 6))
	t.Size = UDim2.fromOffset(0, Estilo.px(18, 26))
	-- o nome encolhe para a etiqueta (no Studio, "NÃO NESTA CLASSE" cobria o nome do item)
	local nome0 = c.name.Size
	local function abre()
		if t.Parent then
			c.name.Size = UDim2.new(
				nome0.X.Scale,
				nome0.X.Offset - t.AbsoluteSize.X - Estilo.px(6, 8),
				nome0.Y.Scale,
				nome0.Y.Offset
			)
		else
			c.name.Size = nome0
		end
	end
	t:GetPropertyChangedSignal("AbsoluteSize"):Connect(abre)
	t.Destroying:Connect(function()
		c.name.Size = nome0
	end)
	abre()
	t.ZIndex = c.frame.ZIndex + 2
end

-- ===== movimento =====
-- D-205 (§4: "transições curtas, de 0,15 a 0,30 s"): QUICK para realce e cor, SOFT para escala e
-- entrada. Com movimento reduzido, a entrada não desliza (Estilo.enter) e o UiKit.tween troca direto
-- o que mexe de lugar ou de tamanho.
Estilo.QUICK = TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
Estilo.SOFT = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- entrada escalonada: cada objeto desliza `dy` px até a posição de repouso (guardada na 1ª vez)
function Estilo.enter(list: { GuiObject }, dy: number?, step: number?, delay: number?)
	local TweenService = game:GetService("TweenService")
	local parado = Estilo.reduzMovimento()
	for i, o in list do
		local base = o:GetAttribute("EstiloBase")
		local p: UDim2
		if typeof(base) == "UDim2" then
			p = base
		else
			p = o.Position
			o:SetAttribute("EstiloBase", p)
		end
		if parado then
			o.Position = p
			continue
		end
		o.Position = p + UDim2.fromOffset(0, dy or 14)
		TweenService:Create(
			o,
			TweenInfo.new(
				0.32,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out,
				0,
				false,
				(delay or 0) + (i - 1) * (step or 0.04)
			),
			{ Position = p }
		):Play()
	end
end

return Estilo
