--!strict
-- Interface para TV e controle (Parte 12.5): texto mínimo de 24 px na TV (IsTenFootInterface),
-- nada essencial fora da área segura (ScreenInsets = DeviceSafeInsets), foco sempre visível com
-- moldura de alto contraste e toda tela abrindo com um item focado (GuiService.SelectedObject).
-- No lobby o controle usa o cursor virtual (VirtualCursor): todo UiKit.button já fica registrado
-- nele, e o foco automático fica desligado enquanto o cursor estiver na tela.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Lang = require(game:GetService("ReplicatedStorage").Shared.Lang)
local Input = require(script.Parent.Input)
local Texto = require(script.Parent.Texto)
local VirtualCursor = require(script.Parent.VirtualCursor)

local UiKit = {}
local player = Players.LocalPlayer

UiKit.PAPER = Color3.fromRGB(214, 203, 170)
UiKit.INK = Color3.fromRGB(40, 36, 28)
UiKit.OLIVE = Color3.fromRGB(86, 90, 62)
-- dossiê de operações de 1965 (tela de deslocamento e mapa): pasta parda, ficha pautada, carimbo
UiKit.NIGHT = Color3.fromRGB(20, 22, 16) -- fundo verde-oliva quase preto
UiKit.DRAB = Color3.fromRGB(46, 50, 36) -- painel oliva escuro
UiKit.KHAKI = Color3.fromRGB(201, 186, 140) -- texto claro sobre oliva
UiKit.MANILA = Color3.fromRGB(190, 166, 116) -- pasta parda
UiKit.CARD = Color3.fromRGB(234, 226, 200) -- ficha de arquivo
UiKit.RULE_RED = Color3.fromRGB(176, 62, 48) -- linha de cabeçalho da ficha
UiKit.RULE_BLUE = Color3.fromRGB(118, 138, 168) -- pauta da ficha
UiKit.STAMP = Color3.fromRGB(150, 40, 30) -- tinta de carimbo
UiKit.BRASS = Color3.fromRGB(214, 172, 72) -- latão: recompensa e botão em destaque

UiKit.CARD_DARK = Color3.fromRGB(26, 28, 21) -- cartão oliva quase preto (avisos, HUD)
UiKit.BRASS_LIGHT = Color3.fromRGB(236, 202, 116) -- título em latão claro sobre oliva

-- tipografia dos avisos e do tutorial, a mesma do lobby: título condensado (Oswald) e texto legível
UiKit.HEAD_FONT = Font.fromName("Oswald", Enum.FontWeight.Bold)
UiKit.HEAD_REG = Font.fromName("Oswald", Enum.FontWeight.Regular)
UiKit.BODY_FONT = Enum.Font.Arimo
UiKit.TYPE_FONT = Enum.Font.SpecialElite -- máquina de escrever (sem as letras do vietnamita)

-- O Oswald pode não ter as letras do vietnamita (como a máquina de escrever do lobby): texto com
-- letra fora do Latin-1 vai no Arimo, que tem.
function UiKit.headFont(text: string): Font
	return if string.find(text, "[\196-\244]") then Font.fromEnum(Enum.Font.ArimoBold) else UiKit.HEAD_FONT
end

-- Caixa alta que também sobe as letras acentuadas do português e do vietnamita (o string.upper só
-- mexe no ASCII; no Studio "An Cường" saía "AN CườNG"). Mora no Shared/Lang (a tradução usa a
-- mesma para achar "FUZILEIRO" no dicionário de "Fuzileiro").
UiKit.upper = Lang.upper

-- Primeira letra em maiúscula (texto do servidor chega em minúscula: "alvo fora do mapa").
function UiKit.capitalize(s: string): string
	if string.byte(s, 1) == 195 then
		return UiKit.upper(string.sub(s, 1, 2)) .. string.sub(s, 3)
	end
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

function UiKit.tv(): boolean
	local ok, v = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and v == true
end

-- tamanho de texto: na TV nunca abaixo de 24 px (1080p)
function UiKit.text(size: number): number
	return if UiKit.tv() then math.max(size, 24) else size
end

-- Texto dentro de uma tela com UIScale: na TV o tamanho NA TELA (size × scale) nunca fica abaixo de
-- 24 px. Fora da TV devolve o tamanho de projeto.
function UiKit.textAt(size: number, scale: number): number
	if not UiKit.tv() then
		return size
	end
	return math.max(size, math.ceil(24 / math.max(scale, 0.05)))
end

function UiKit.screen(name: string, order: number?): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.DisplayOrder = order or 10
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	g.Parent = player:WaitForChild("PlayerGui")
	return g
end

-- ===== movimento (pedido do dono, 2026-11-11: "mais fluido") =====
-- Tempos de interface: QUICK para realce e cor, SOFT para escala e entrada de cartão.
UiKit.QUICK = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
UiKit.SOFT = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function UiKit.tween(o: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local t = TweenService:Create(o, info, props)
	t:Play()
	return t
end

-- Realce animado de um botão (mouse, foco do Roblox e cursor virtual chamam set): cresce um pouco,
-- a borda vira latão e o fundo passa para `quente`. base() troca a cor de repouso (ficha cheia,
-- trancada) com a mesma transição. A escala usa o UIScale "Escala" do botão (criado se faltar), o
-- mesmo que a entrada escalonada dos cartões anima.
export type Realce = {
	set: (on: boolean) -> (),
	base: (color: Color3) -> (),
	hot: () -> boolean,
}
function UiKit.realce(b: GuiObject, base: Color3?, quente: Color3?, escala: number?): Realce
	local sc = b:FindFirstChild("Escala")
	if not (sc and sc:IsA("UIScale")) then
		local s = Instance.new("UIScale")
		s.Name = "Escala"
		s.Parent = b
		sc = s
	end
	local scale = sc :: UIScale
	local ring: UIStroke? = nil
	for _, c in b:GetChildren() do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			ring = c
			break
		end
	end
	if not ring then
		local s = Instance.new("UIStroke")
		s.Name = "Realce"
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Color = UiKit.BRASS
		s.Thickness = 2
		s.Transparency = 1
		s.Parent = b
		ring = s
	end
	local edge = ring :: UIStroke
	local rest = { color = edge.Color, thick = edge.Thickness, tr = edge.Transparency }
	local on = false
	local cold: Color3? = base
	local function paint()
		local c = if on and quente then quente else cold
		if c then
			UiKit.tween(b, UiKit.QUICK, { BackgroundColor3 = c })
		end
	end
	return {
		set = function(v: boolean)
			if v == on then
				return
			end
			on = v
			UiKit.tween(scale, UiKit.SOFT, { Scale = if v then (escala or 1.035) else 1 })
			UiKit.tween(edge, UiKit.QUICK, {
				Color = if v then UiKit.BRASS else rest.color,
				Thickness = if v then math.max(rest.thick, 2) else rest.thick,
				Transparency = if v then 0 else rest.tr,
			})
			paint()
		end,
		base = function(c: Color3)
			if c == cold then
				return -- a tela redesenha muito: só anima quando a cor muda de fato
			end
			cold = c
			paint()
		end,
		hot = function(): boolean
			return on
		end,
	}
end

-- moldura de foco de alto contraste (amarelo sobre preto, 4 px). Ao trocar de item ela "fecha" sobre
-- o novo (vem de 10 px para 4) e depois respira devagar: o foco do controle nunca some nem pula seco.
local focusFrame = Instance.new("Frame")
focusFrame.Name = "VT65Focus"
focusFrame.BackgroundTransparency = 1
focusFrame.Size = UDim2.new(1, 8, 1, 8)
focusFrame.Position = UDim2.fromOffset(-4, -4)
local stroke = Instance.new("UIStroke")
stroke.Thickness = 4
stroke.Color = Color3.fromRGB(255, 214, 0)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = focusFrame
UiKit.FOCUS = focusFrame

local breathe: Tween? = nil
GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
	local b = breathe
	if b then
		b:Cancel()
		breathe = nil
	end
	stroke.Transparency = 0
	if not GuiService.SelectedObject then
		return
	end
	focusFrame.Size = UDim2.new(1, 20, 1, 20)
	focusFrame.Position = UDim2.fromOffset(-10, -10)
	UiKit.tween(focusFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 8, 1, 8),
		Position = UDim2.fromOffset(-4, -4),
	})
	local t = TweenService:Create(
		stroke,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.25),
		{ Transparency = 0.4 }
	)
	t:Play()
	breathe = t
end)

function UiKit.button(parent: Instance, text: string, onClick: () -> (), order: number?): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -8, 0, if UiKit.tv() then 48 else 34)
	b.BackgroundColor3 = Color3.fromRGB(120, 112, 84)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = UiKit.text(16)
	b.TextWrapped = true
	b.Text = text
	b.Selectable = true
	b.SelectionImageObject = focusFrame
	b.LayoutOrder = order or 0
	b.Parent = parent
	b.Activated:Connect(onClick)
	VirtualCursor.bind(b, onClick)
	return b
end

-- Liga um botão feito à mão ao clique (mouse, toque, A da navegação do Roblox) e ao cursor virtual
-- do controle; hover (opcional) recebe também o passar do cursor virtual.
function UiKit.bind(b: GuiButton, onClick: () -> (), hover: ((boolean) -> ())?)
	b.Activated:Connect(onClick)
	VirtualCursor.bind(b, onClick, hover)
end

function UiKit.label(parent: Instance, text: string, size: number?, height: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -8, 0, height or (if UiKit.tv() then 34 else 26))
	t.BackgroundTransparency = 1
	t.TextColor3 = UiKit.INK
	t.Font = Enum.Font.GothamBold
	t.TextSize = UiKit.text(size or 18)
	t.TextWrapped = true
	t.Text = text
	t.Parent = parent
	return t
end

local function firstSelectable(root: Instance): GuiObject?
	local best: GuiObject? = nil
	local bestKey = math.huge
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.Selectable and d.Visible then
			local p = d.AbsolutePosition
			local key = p.Y * 10000 + p.X
			if key < bestKey then
				best, bestKey = d, key
			end
		end
	end
	return best
end

-- Põe o foco no primeiro item (de cima para baixo) se o jogador estiver no controle.
function UiKit.focus(root: Instance)
	if not Input.isGamepad() or VirtualCursor.isActive() then
		return -- com o cursor virtual, quem escolhe é o cursor (A não pode ativar dois botões)
	end
	task.defer(function()
		local cur = GuiService.SelectedObject
		if cur and cur:IsDescendantOf(root) and cur.Visible then
			return
		end
		local f = firstSelectable(root)
		if f then
			GuiService.SelectedObject = f
		end
	end)
end

-- Vigia: tela visível no controle sem foco nela vira aviso e é corrigida (Parte 12.7).
local watched: { { root: GuiObject, active: () -> boolean, warned: boolean } } = {}
function UiKit.watch(root: GuiObject, active: () -> boolean)
	table.insert(watched, { root = root, active = active, warned = false })
end
task.spawn(function()
	while true do
		task.wait(0.5)
		if Input.isGamepad() and GuiService.GuiNavigationEnabled and not VirtualCursor.isActive() then
			for _, w in watched do
				if w.active() and w.root.Visible then
					local cur = GuiService.SelectedObject
					if not (cur and cur:IsDescendantOf(w.root)) then
						if not firstSelectable(w.root) then
							if not w.warned then
								w.warned = true
								warn("[VT65] tela sem item focável:", w.root:GetFullName())
							end
						else
							UiKit.focus(w.root)
						end
					end
				end
			end
		end
	end
end)

Input.DeviceChanged:Connect(function(d)
	if d ~= "gamepad" then
		GuiService.SelectedObject = nil
	end
end)

-- ===== peças de época compartilhadas (pedido do dono, 2026-11-11: "melhore todas as interfaces") =====
-- Usadas pelas telas refeitas (menu do jogo, relatório pós-ação, roda, loja, HUD, aviso do controle).
function UiKit.corner(o: Instance, r: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
	return c
end

-- filete na borda (não no texto)
function UiKit.edge(o: Instance, color: Color3, thick: number, tr: number): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thick
	s.Transparency = tr
	s.Parent = o
	return s
end

-- luz de cima (o UIGradient só pinta o próprio objeto): low = quanto escurece embaixo
function UiKit.lit(o: Instance, low: number?, rot: number?): UIGradient
	local k = low or 0.7
	local g = Instance.new("UIGradient")
	g.Rotation = rot or 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(k, k * 0.98, k * 0.94))
	g.Parent = o
	return g
end

-- rótulo sem fundo; font aceita Enum.Font ou Font
function UiKit.rotulo(parent: Instance, size: number, color: Color3, font: any?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextColor3 = color
	t.TextSize = UiKit.text(size)
	if typeof(font) == "Font" then
		t.FontFace = font
	elseif typeof(font) == "EnumItem" then
		t.Font = font :: any
	else
		t.Font = UiKit.BODY_FONT
	end
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

-- ----- menos texto na tela, sem quebrar a tradução (pedido do dono, 2026-11-11: "algumas telas
-- que possuem muita escrita, mude") -----
-- O dicionário traduz a FRASE INTEIRA (é a chave). Então o texto inteiro vai num rótulo escondido
-- (o Traducao.client traduz) e a tela mostra só a 1ª frase e, menor, o resto, em TextBox só de
-- leitura (a tradução nunca mexe em TextBox). Trocou o idioma: o rótulo escondido muda e a divisão
-- se refaz sozinha.
function UiKit.fixedText(parent: Instance, size: number, color: Color3, font: any?): TextBox
	local t = Instance.new("TextBox")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextColor3 = color
	t.TextSize = UiKit.text(size)
	if typeof(font) == "Font" then
		t.FontFace = font
	elseif typeof(font) == "EnumItem" then
		t.Font = font :: any
	else
		t.Font = UiKit.BODY_FONT
	end
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextEditable = false
	t.ClearTextOnFocus = false
	t.Selectable = false
	t.Active = false
	t.Text = ""
	pcall(function()
		t.Interactable = false
	end)
	t.Parent = parent
	return t
end

-- 1ª frase e o resto (Controllers/Texto, puro e testado no Lune)
UiKit.splitSentence = Texto.splitSentence

-- Liga o rótulo escondido (fonte) à divisão: onSplit(1ª frase, resto) a cada texto novo/traduzido.
function UiKit.resumo(source: TextLabel, onSplit: (head: string, rest: string) -> ())
	local function run()
		local head, rest = UiKit.splitSentence(source.Text)
		onSplit(head, rest)
	end
	source:GetPropertyChangedSignal("Text"):Connect(run)
	run()
end

-- ----- teclas e botões -----
local KEY_TEXT: { [string]: string } = {
	MouseLeftButton = "LMB",
	MouseRightButton = "RMB",
	MouseMiddleButton = "MMB",
	LeftShift = "Shift",
	LeftControl = "Ctrl",
	Return = "Enter",
	Space = "Espaço",
	Backspace = "Backspace",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
}
function UiKit.keyName(code: string): string
	return KEY_TEXT[code] or code
end

-- imagem do botão no controle conectado (Xbox, PlayStation...) ou nil
function UiKit.padImage(code: Enum.KeyCode): string?
	local img: string? = nil
	pcall(function()
		local v = UserInputService:GetImageForKeyCode(code) :: any
		if type(v) == "string" and v ~= "" then
			img = v
		end
	end)
	return img
end

-- ----- dicas de botão em chip -----
-- Uma fileira de chips reaproveitados: imagem do botão do controle ou tecla em relevo (ficha clara,
-- filete de tinta, luz de cima) e o que ela faz. light = fileira sobre papel (texto em tinta).
export type Chips = {
	frame: Frame,
	clear: () -> (),
	add: (img: string?, img2: string?, key: string, label: string) -> (),
	action: (actionId: string, ctx: string?, label: string) -> (),
	pair: (a: string, b: string, ctx: string?, label: string) -> (),
}
type ChipSlot = { f: Frame, img: ImageLabel, img2: ImageLabel, key: TextLabel, t: TextLabel }
function UiKit.chips(parent: Instance, height: number, light: boolean?, size: number?): Chips
	local row = Instance.new("Frame")
	row.Name = "Dicas"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, height)
	row.Parent = parent
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, math.floor(height * 0.5))
	lay.Parent = row
	local ts = UiKit.text(size or 14)
	local slots: { ChipSlot } = {}
	local used = 0
	local function slot(): ChipSlot
		used += 1
		local s = slots[used]
		if s then
			s.f.Visible = true
			return s
		end
		local f = Instance.new("Frame")
		f.BackgroundTransparency = 1
		f.AutomaticSize = Enum.AutomaticSize.X
		f.Size = UDim2.fromOffset(0, height)
		f.LayoutOrder = used
		f.Parent = row
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.VerticalAlignment = Enum.VerticalAlignment.Center
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Padding = UDim.new(0, 5)
		l.Parent = f
		local icon = math.floor(height * 0.86)
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(icon, icon)
		img.LayoutOrder = 1
		img.Parent = f
		local img2 = img:Clone()
		img2.LayoutOrder = 2
		img2.Parent = f
		local key = Instance.new("TextLabel")
		key.BackgroundColor3 = UiKit.CARD
		key.BorderSizePixel = 0
		key.AutomaticSize = Enum.AutomaticSize.X
		key.Size = UDim2.fromOffset(0, math.floor(height * 0.78))
		key.FontFace = UiKit.HEAD_FONT
		key.TextColor3 = UiKit.INK
		key.TextSize = ts
		key.LayoutOrder = 3
		key.Parent = f
		UiKit.corner(key, 4)
		UiKit.lit(key, 0.82)
		UiKit.edge(key, UiKit.INK, 1, 0.45)
		local kp = Instance.new("UIPadding")
		kp.PaddingLeft = UDim.new(0, 7)
		kp.PaddingRight = UDim.new(0, 7)
		kp.Parent = key
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromOffset(0, height)
		t.Font = UiKit.TYPE_FONT
		t.TextSize = ts
		t.TextColor3 = if light then UiKit.INK else UiKit.KHAKI
		t.LayoutOrder = 4
		t.Parent = f
		local made: ChipSlot = { f = f, img = img, img2 = img2, key = key, t = t }
		slots[used] = made
		return made
	end
	local chips: Chips = {} :: any
	chips.frame = row
	function chips.clear()
		used = 0
		for _, s in slots do
			s.f.Visible = false
		end
	end
	function chips.add(img: string?, img2: string?, key: string, label: string)
		local s = slot()
		s.img.Visible = img ~= nil
		s.img.Image = img or ""
		s.img2.Visible = img2 ~= nil
		s.img2.Image = img2 or ""
		s.key.Visible = img == nil and key ~= ""
		s.key.Text = UiKit.upper(key)
		s.key.FontFace = UiKit.headFont(key)
		s.t.Text = label
		s.t.Font = if string.find(label, "[\196-\225]") then UiKit.BODY_FONT else UiKit.TYPE_FONT
	end
	function chips.action(actionId: string, ctx: string?, label: string)
		local img, txt = Input.glyph(actionId, ctx)
		chips.add(img, nil, UiKit.keyName(txt), label)
	end
	function chips.pair(a: string, b: string, ctx: string?, label: string)
		local ia, ta = Input.glyph(a, ctx)
		local ib, tb = Input.glyph(b, ctx)
		if ia and ib then
			chips.add(ia, ib, "", label)
		else
			chips.add(nil, nil, string.format("%s/%s", UiKit.keyName(ta), UiKit.keyName(tb)), label)
		end
	end
	return chips
end

-- ----- escala para qualquer tela -----
-- O quadro de projeto (w x h) cabe na tela com margem: abaixo do tamanho de projeto ele encolhe por
-- UIScale (nunca cresce; na TV os tamanhos já são os da TV). k() dá a escala atual para quem anima
-- a entrada (o tween termina em k(), não em 1). Usa o UIScale que o alvo já tiver.
export type Fit = {
	scale: UIScale,
	k: () -> number,
	play: (info: TweenInfo, to: number?, from: number?) -> Tween,
}
function UiKit.fit(gui: LayerCollector, target: GuiObject, w: number, h: number, margin: number?, minK: number?): Fit
	local sc = target:FindFirstChildOfClass("UIScale")
	if not sc then
		local s = Instance.new("UIScale")
		s.Name = "Ajuste"
		s.Parent = target
		sc = s
	end
	local scale = sc :: UIScale
	local k = 1
	local m = margin or 16
	-- Área útil medida na hora. A ScreenGui desligada não atualiza o AbsoluteSize: o menu criado
	-- desligado guardava a escala da janela do início e, numa janela mais estreita, abria cortado dos
	-- lados (visto no Studio com 671 px de largura). Para ScreenGui vale o tamanho da câmera.
	local function area(): Vector2
		local cam = workspace.CurrentCamera
		if gui:IsA("ScreenGui") and cam then
			local v = cam.ViewportSize
			if not (gui :: ScreenGui).IgnoreGuiInset then
				local tl, br = GuiService:GetGuiInset()
				v -= tl + br
			end
			return v
		end
		return gui.AbsoluteSize
	end
	local function measure(): number
		local a = area()
		if a.X >= 10 and a.Y >= 10 then
			k = math.clamp(math.min((a.X - 2 * m) / w, (a.Y - 2 * m) / h), minK or 0.45, 1)
		end
		return k
	end
	-- um tween de escala por vez: entrada, saída e mudança de janela não brigam pela mesma
	-- propriedade (o novo cancela o anterior; a janela mudando cancela e assenta na hora)
	local running: Tween? = nil
	local function stop()
		local t = running
		if t then
			running = nil
			t:Cancel()
		end
	end
	local function update()
		stop()
		scale.Scale = measure()
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	update()
	return {
		scale = scale,
		-- mede de novo: quem anima a entrada termina o tween na escala da janela de agora
		k = measure,
		-- anima a escala de from × k até to × k (from nil: de onde está)
		play = function(info: TweenInfo, to: number?, from: number?): Tween
			stop()
			local kk = measure()
			if from then
				scale.Scale = kk * from
			end
			local t = TweenService:Create(scale, info, { Scale = kk * (to or 1) })
			running = t
			t:Play()
			return t
		end,
	}
end

-- ----- foco do controle nunca preso numa tela fechada -----
function UiKit.release(root: Instance)
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

-- ----- qual tela está por cima (B, Backspace e Esc fecham só a de cima) -----
-- Cada tela que fecha com "voltar" se registra ao abrir (UiKit.opened) e sai ao fechar
-- (UiKit.closed). UiKit.backFor(nome) diz se esta tela deve tratar o "voltar" agora: só a de cima,
-- e um aperto só fecha uma tela (os handlers de ui_back rodam todos no mesmo aperto).
-- order = DisplayOrder da tela: uma tela que abre DEPOIS mas fica por baixo (o relatório, 40, que
-- chega com a tela de fim, 43, já aberta) entra abaixo dela na pilha, como aparece.
type Entry = { name: string, order: number }
local stack: { Entry } = {}
local lastBack = 0
function UiKit.closed(name: string)
	for i, e in stack do
		if e.name == name then
			table.remove(stack, i)
			return
		end
	end
end
function UiKit.opened(name: string, order: number?)
	UiKit.closed(name)
	local o = order or 0
	local at = #stack + 1
	while at > 1 and stack[at - 1].order > o do
		at -= 1
	end
	table.insert(stack, at, { name = name, order = o })
end
function UiKit.top(): string?
	local e = stack[#stack]
	return if e then e.name else nil
end
function UiKit.backFor(name: string): boolean
	if UiKit.top() ~= name or os.clock() - lastBack < 0.15 then
		return false
	end
	lastBack = os.clock()
	return true
end

-- ----- segurar para confirmar -----
-- Barra de latão que enche enquanto o jogador segura; done() roda ao encher. start/stop vêm de
-- quem lê o botão. Um tween só (nada por quadro).
export type Hold = { start: () -> (), stop: () -> (), holding: () -> boolean }
function UiKit.hold(bar: Frame, seconds: number, done: () -> ()): Hold
	local tw: Tween? = nil
	local on = false
	local function reset()
		local t = tw
		if t then
			t:Cancel()
			tw = nil
		end
		bar.Size = UDim2.new(0, 0, bar.Size.Y.Scale, bar.Size.Y.Offset)
	end
	return {
		start = function()
			if on then
				return
			end
			on = true
			reset()
			local t = TweenService:Create(bar, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
				Size = UDim2.new(1, 0, bar.Size.Y.Scale, bar.Size.Y.Offset),
			})
			tw = t
			t.Completed:Once(function(state: Enum.PlaybackState)
				if state == Enum.PlaybackState.Completed and on then
					on = false
					done()
					reset()
				end
			end)
			t:Play()
		end,
		stop = function()
			on = false
			reset()
		end,
		holding = function(): boolean
			return on
		end,
	}
end

-- ----- pré-carga (pedido do dono, 2026-11-11: "1000x mais liso") -----
-- As imagens das telas (botões do controle nos chips, vinheta, luz e sombra do Acabamento) entram
-- na memória uma vez, logo no início: nenhuma tela aparece com o ícone vazio e "pisca" depois.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local list: { Instance } = {}
	local function img(id: string?)
		if id and id ~= "" then
			local i = Instance.new("ImageLabel")
			i.Image = id
			table.insert(list, i)
		end
	end
	for _, k in
		{
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.ButtonB,
			Enum.KeyCode.ButtonX,
			Enum.KeyCode.ButtonY,
			Enum.KeyCode.ButtonL1,
			Enum.KeyCode.ButtonR1,
			Enum.KeyCode.ButtonL2,
			Enum.KeyCode.ButtonR2,
			Enum.KeyCode.ButtonSelect,
			Enum.KeyCode.DPadLeft,
			Enum.KeyCode.DPadRight,
			Enum.KeyCode.Thumbstick2,
		}
	do
		img(UiKit.padImage(k))
	end
	local ok, acab = pcall(function()
		return require(game:GetService("ReplicatedFirst"):WaitForChild("Acabamento", 10) :: ModuleScript) :: any
	end)
	if ok and type(acab) == "table" then
		img(acab.VINHETA)
		img(acab.LUZ)
		img(acab.SOMBRA)
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	for _, i in list do
		i:Destroy()
	end
end)

return UiKit
