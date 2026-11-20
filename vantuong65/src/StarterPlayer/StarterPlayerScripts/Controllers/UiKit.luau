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
local Estilo = require(game:GetService("ReplicatedFirst"):WaitForChild("Estilo"))
local Input = require(script.Parent.Input)
local Texto = require(script.Parent.Texto)
local VirtualCursor = require(script.Parent.VirtualCursor)

local UiKit = {}
local player = Players.LocalPlayer

-- ===== linguagem visual nova (ReplicatedFirst/Estilo, 2026-11-11) =====
-- Painéis escuros, títulos em Oswald caixa alta, números grandes, corpo em Arimo, acentos de época.
-- Toda tela nova usa estes tokens e peças; os tokens antigos de papel (CARD, INK, MANILA, STAMP)
-- ficam só para o que ainda não foi refeito.
UiKit.Estilo = Estilo
UiKit.V = Estilo.V
UiKit.F = Estilo.F
UiKit.px = Estilo.px
UiKit.ts = Estilo.ts
UiKit.pad = Estilo.pad
UiKit.list = Estilo.list
UiKit.stroke = Estilo.stroke
UiKit.text2 = Estilo.text
UiKit.panel = Estilo.panel
UiKit.backdrop = Estilo.backdrop
UiKit.title = Estilo.title
UiKit.kicker = Estilo.kicker
UiKit.body = Estilo.body
UiKit.titleBox = Estilo.titleBox
UiKit.slash = Estilo.slash
UiKit.stat = Estilo.stat
UiKit.statRow = Estilo.statRow
UiKit.tag = Estilo.tag
UiKit.bar = Estilo.bar
UiKit.itemCard = Estilo.itemCard
UiKit.enter = Estilo.enter
UiKit.setGlyph = Estilo.setGlyph

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
-- A máquina de escrever saiu (o dono não gostou do papel datilografado): o nome antigo continua,
-- agora no Arimo, para as telas que ainda o usam. TYPE_OLD só para um detalhe mínimo, se houver.
UiKit.TYPE_FONT = Enum.Font.Arimo
UiKit.TYPE_OLD = Enum.Font.SpecialElite

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

-- tamanho de texto: cresce com a preferência do jogador (D-205, Estilo.textoK); na TV nunca abaixo
-- de 24 px (1080p)
function UiKit.text(size: number): number
	return Estilo.ts(size)
end

-- Texto dentro de uma tela com UIScale: na TV o tamanho NA TELA (size × scale) nunca fica abaixo de
-- 24 px. Fora da TV devolve o tamanho de projeto (com a preferência de tamanho, D-205).
function UiKit.textAt(size: number, scale: number): number
	local s = math.floor(size * Estilo.textoK() + 0.5)
	if not UiKit.tv() then
		return s
	end
	return math.max(s, math.ceil(24 / math.max(scale, 0.05)))
end

-- D-205: "Reduzir movimento" das Configurações (Input.settings.uiReduceMotion) vira o atributo local
-- que o Estilo lê junto com a preferência do Roblox
local function syncMovimento()
	player:SetAttribute("VT65ReduzMovimento", (Input.settings :: any).uiReduceMotion == true)
end
Input.SettingsChanged:Connect(syncMovimento)
syncMovimento()

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
-- Tempos de interface: QUICK para realce e cor, SOFT para escala e entrada de cartão (D-205: 0,15 e
-- 0,30 s, a faixa do §4). Um tween novo na mesma propriedade substitui o anterior (o TweenService
-- cancela o que estava andando): trocar rápido de foco não acumula animação.
UiKit.QUICK = Estilo.QUICK
UiKit.SOFT = Estilo.SOFT

-- propriedades que mexem de lugar ou de tamanho: com movimento reduzido elas trocam direto
UiKit.MOVIMENTO = {
	Position = true,
	Size = true,
	Rotation = true,
	Scale = true,
	CanvasPosition = true,
	AnchorPoint = true,
	Offset = true,
} :: { [string]: boolean }

function UiKit.tween(o: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local i = info
	if Estilo.reduzMovimento() then
		for k in props do
			if UiKit.MOVIMENTO[k] then
				i = TweenInfo.new(0)
				break
			end
		end
	end
	local t = TweenService:Create(o, i, props)
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
	quente: (color: Color3) -> (), -- troca a cor do realce (botão que muda de forma de pagar)
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
		s.Color = Estilo.V.FOCO
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
				Color = if v then Estilo.V.FOCO else rest.color,
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
		quente = function(c: Color3)
			quente = c
			if on then
				paint()
			end
		end,
	}
end

-- ===== cores de compra (pedido do dono, 2026-11-13: "coloque cores nos botões de compra") =====
-- Um padrão só em todo o jogo (baixa, loja, carta de inserção, passe, vantagens, intendência):
--   - robux: verde-esmeralda (o que se paga em Robux);
--   - ci: âmbar (créditos de intendência, o "$" do jogo);
--   - free: o oliva da ação (grátis, já pago, pronto para usar);
--   - apagado: o enabled(false) de sempre (painel escuro e texto fraco).
-- Contraste do texto claro (V.TEXT) no fundo: robux 4,5:1, ci 4,1:1, free 3,8:1 (rótulos em Oswald
-- grosso, texto grande: o mínimo é 3:1).
UiKit.PAGAR = {
	robux = { base = Color3.fromRGB(20, 120, 92), hot = Color3.fromRGB(32, 148, 114) },
	ci = { base = Color3.fromRGB(150, 104, 24), hot = Color3.fromRGB(178, 126, 38) },
	free = { base = Estilo.V.OLIVE, hot = Estilo.V.OLIVE_HI },
	-- lote 23 (diária e passe para crianças): pegar um prêmio, verde vivo (não é compra)
	premio = { base = Color3.fromRGB(38, 150, 64), hot = Color3.fromRGB(56, 182, 84) },
} :: { [string]: { base: Color3, hot: Color3 } }

-- forma de pagar de uma moeda do jogo ("robux", "ci", "credit" do renascer guardado, "free")
function UiKit.payKind(currency: string?): string
	if currency == "robux" then
		return "robux"
	elseif currency == "ci" or currency == "credits" or currency == "$" then
		return "ci"
	end
	return "free"
end

-- Pinta um TextButton feito à mão com a cor da forma de pagar (as telas que não usam UiKit.action);
-- devolve o realce já ligado à cor certa.
function UiKit.payPaint(b: GuiButton, kind: string, escala: number?): Realce
	local c = UiKit.PAGAR[kind] or UiKit.PAGAR.free
	b.BackgroundColor3 = c.base
	b.BackgroundTransparency = 0
	if b:IsA("TextButton") then
		b.TextColor3 = Estilo.V.TEXT
	end
	return UiKit.realce(b, c.base, c.hot, escala or 1.03)
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
stroke.Color = Estilo.V.FOCO -- D-205: o âmbar do foco
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
	if Estilo.reduzMovimento() then
		-- D-205: movimento reduzido: a moldura aparece no lugar e não respira
		focusFrame.Size = UDim2.new(1, 8, 1, 8)
		focusFrame.Position = UDim2.fromOffset(-4, -4)
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

-- Botão do estilo novo, pronto: forma (Estilo.button), realce (mouse, foco do controle e cursor
-- virtual), clique ligado e foco de alto contraste. kind: "primary", "danger", "secondary", "ghost"
-- ou uma forma de pagar (UiKit.PAGAR: "robux", "ci", "free": cheio, na cor dela).
-- opts.action/opts.ctx: mostra o botão do controle dessa ação à esquerda (só no controle; troca
-- sozinho ao trocar de dispositivo). enabled(false) apaga e trava o botão (o clique não roda).
-- setKind(k) troca a forma de pagar (ou volta a "primary"/"secondary") sem recriar o botão.
export type Action = Estilo.ButtonParts & {
	realce: Realce,
	enabled: (on: boolean) -> (),
	isEnabled: () -> boolean,
	setKind: (kind: string) -> (),
	carregando: (on: boolean) -> (), -- D-205: trava e mostra "…" (operação em andamento)
	erro: (msg: string) -> (), -- D-205: borda vermelha e o motivo por 2,5 s
}
export type ActionOpts = { action: string?, ctx: string?, h: number? }

-- cores de repouso e de realce de cada tipo de botão
local function kindColors(k: string): (Color3, Color3)
	local pay = UiKit.PAGAR[k]
	if pay then
		return pay.base, pay.hot
	elseif k == "primary" then
		return Estilo.V.AMBAR, Estilo.V.AMBAR_HI -- D-205 (§3): ação principal em âmbar
	elseif k == "danger" then
		return Estilo.V.RED, Estilo.V.RED_HI
	end
	return Estilo.V.PANEL, Estilo.V.PANEL_3
end

function UiKit.action(parent: Instance?, text: string, kind: string?, onClick: () -> (), opts: ActionOpts?): Action
	local o: ActionOpts = opts or { action = nil, ctx = nil, h = nil }
	local k = kind or "primary"
	local solid = UiKit.PAGAR[k] ~= nil
	-- forma de pagar: a forma do botão fino, com o fundo cheio na cor dela (o Estilo não a conhece)
	local parts = Estilo.button(parent, text, if solid then "secondary" else k, o.h)
	local b = parts.button
	b.Selectable = true
	b.SelectionImageObject = focusFrame
	local base, hot = kindColors(k)
	local edgeLine = b:FindFirstChildOfClass("UIStroke")
	local function shape(kk: string)
		if UiKit.PAGAR[kk] then
			b.BackgroundTransparency = 0
			if edgeLine then
				edgeLine.Color = Estilo.V.TEXT
				edgeLine.Transparency = 0.8
			end
		elseif kk == "secondary" then
			b.BackgroundTransparency = 0.35
			if edgeLine then
				edgeLine.Color = Estilo.V.LINE
				edgeLine.Transparency = 0.1
			end
		end
	end
	if solid then
		b.BackgroundColor3 = base
		shape(k)
	end
	local r = UiKit.realce(b, base, hot, if k == "primary" or k == "danger" then 1.015 else 1.025)
	local on = true
	local function click()
		if on then
			onClick()
		end
	end
	UiKit.bind(b, click, r.set)
	b.MouseEnter:Connect(function()
		r.set(true)
	end)
	b.MouseLeave:Connect(function()
		r.set(false)
	end)
	b.SelectionGained:Connect(function()
		r.set(true)
	end)
	b.SelectionLost:Connect(function()
		r.set(false)
	end)
	local function glyph()
		if o.action and Input.isGamepad() then
			local img = Input.glyph(o.action, o.ctx)
			Estilo.setGlyph(parts, img)
		else
			Estilo.setGlyph(parts, nil)
		end
	end
	glyph()
	-- D-205 (§21): a conexão sai junto com o botão (antes cada tela recriada deixava uma para trás)
	local devConn = Input.DeviceChanged:Connect(glyph)
	b.Destroying:Connect(function()
		devConn:Disconnect()
	end)
	-- D-205 (§3): pressionado: o botão afunda um pouco enquanto o dedo ou o mouse seguram
	local scl = b:FindFirstChild("Escala") :: UIScale?
	local function afunda(v: boolean)
		if scl and on then
			UiKit.tween(scl, UiKit.QUICK, { Scale = if v then 0.97 else (if r.hot() then 1.015 else 1) })
		end
	end
	b.MouseButton1Down:Connect(function()
		afunda(true)
	end)
	b.MouseButton1Up:Connect(function()
		afunda(false)
	end)
	b.MouseLeave:Connect(function()
		afunda(false)
	end)
	local a = parts :: any
	a.realce = r
	-- D-205: texto escuro só sobre o âmbar da ação principal habilitada; apagado, texto claro
	local function tinta()
		local escuro = on and k == "primary"
		local c = if escuro then Estilo.V.AMBAR_TEXTO elseif k == "ghost" then Estilo.V.DIM else Estilo.V.TEXT
		parts.label.TextColor3 = c
		parts.sub.TextColor3 = if escuro then Estilo.V.AMBAR_TEXTO else Estilo.V.TEXT
	end
	a.enabled = function(v: boolean)
		on = v
		b.AutoButtonColor = false
		parts.label.TextTransparency = if v then 0 else 0.55
		parts.sub.TextTransparency = if v then 0.15 else 0.6
		tinta()
		r.base(if v then base else Estilo.V.PANEL_2)
	end
	a.isEnabled = function(): boolean
		return on
	end
	-- D-205 (§3, §9: "o botão não deve permitir solicitações duplicadas enquanto uma operação estiver
	-- sendo processada"): carregando trava o clique e mostra "…" à direita; erro pisca a borda em
	-- vermelho e escreve o motivo no lugar do "…" por 2,5 s
	local subAntes: string? = nil
	local erroGen = 0
	a.carregando = function(v: boolean)
		if v then
			subAntes = subAntes or parts.sub.Text
			parts.sub.Text = "…"
			a.enabled(false)
		else
			parts.sub.Text = subAntes or ""
			subAntes = nil
			a.enabled(true)
		end
	end
	a.erro = function(msg: string)
		erroGen += 1
		local g = erroGen
		local antes = parts.sub.Text
		parts.sub.Text = msg
		parts.sub.TextColor3 = Estilo.V.RED_HI
		local e = edgeLine
		if e then
			local c, tr = e.Color, e.Transparency
			e.Color, e.Transparency = Estilo.V.RED_HI, 0
			task.delay(2.5, function()
				if erroGen == g and e.Parent then
					e.Color, e.Transparency = c, tr
				end
			end)
		end
		task.delay(2.5, function()
			if erroGen == g and parts.sub.Parent then
				parts.sub.Text = antes
				tinta()
			end
		end)
	end
	a.setKind = function(kk: string)
		if kk == k then
			return
		end
		k = kk
		base, hot = kindColors(kk)
		shape(kk)
		tinta()
		r.quente(hot)
		r.base(if on then base else Estilo.V.PANEL_2)
	end
	return a :: Action
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

-- D-205 (§19: "definir foco inicial"): a ação principal de uma tela se marca com UiKit.principal;
-- o foco começa nela, e não no item mais em cima à esquerda
function UiKit.principal(o: GuiObject)
	o:SetAttribute("VT65Principal", true)
end
local function principalEm(root: Instance): GuiObject?
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.Selectable and d.Visible and d:GetAttribute("VT65Principal") == true then
			return d
		end
	end
	return nil
end

-- Põe o foco na ação principal (UiKit.principal) ou no primeiro item (de cima para baixo) se o
-- jogador estiver no controle.
function UiKit.focus(root: Instance)
	if not Input.isGamepad() or VirtualCursor.isActive() then
		return -- com o cursor virtual, quem escolhe é o cursor (A não pode ativar dois botões)
	end
	task.defer(function()
		local cur = GuiService.SelectedObject
		if cur and cur:IsDescendantOf(root) and cur.Visible then
			return
		end
		local f = principalEm(root) or firstSelectable(root)
		if f then
			GuiService.SelectedObject = f
		end
	end)
end

-- Vigia: tela visível no controle sem foco nela vira aviso e é corrigida (Parte 12.7).
local watched: { { root: GuiObject, active: () -> boolean, warned: boolean } } = {}
-- (definida lá embaixo, com a pilha de telas)
local focoPorCima: (root: GuiObject) -> boolean = function(_root: GuiObject): boolean
	return false
end
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
					-- D-205: foco numa tela por cima (a confirmação, uma janela aberta do menu) fica lá
					if not (cur and cur:IsDescendantOf(w.root)) and not focoPorCima(w.root) then
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
		-- estilo novo: tecla escura com filete claro, texto em Arimo (sem papel nem máquina de escrever)
		local key = Instance.new("TextLabel")
		key.BackgroundColor3 = if light then Estilo.V.TEXT else Estilo.V.PANEL_3
		key.BorderSizePixel = 0
		key.AutomaticSize = Enum.AutomaticSize.X
		key.Size = UDim2.fromOffset(0, math.floor(height * 0.78))
		key.FontFace = Estilo.F.TITLE_MED
		key.TextColor3 = if light then Estilo.V.BG else Estilo.V.TEXT
		key.TextSize = ts
		key.LayoutOrder = 3
		key.Parent = f
		UiKit.corner(key, 4)
		UiKit.edge(key, Estilo.V.LINE, 1, 0.2)
		local kp = Instance.new("UIPadding")
		kp.PaddingLeft = UDim.new(0, 7)
		kp.PaddingRight = UDim.new(0, 7)
		kp.Parent = key
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromOffset(0, height)
		t.Font = UiKit.BODY_FONT
		t.TextSize = ts
		t.TextColor3 = if light then UiKit.INK else Estilo.V.DIM
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
-- D-205 (§19: "restaurar o foco após fechar um modal"): cada entrada guarda o foco de antes de a tela
-- abrir; ao fechar, o foco volta para ele se ainda estiver na tela (só no controle).
type Entry = { name: string, order: number, foco: GuiObject? }
local stack: { Entry } = {}
local lastBack = 0
-- o objeto está na tela agora: no PlayerGui, numa ScreenGui ligada e com ele e os pais visíveis
local function naTela(o: GuiObject): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not (pg and o:IsDescendantOf(pg)) then
		return false
	end
	local p: Instance? = o
	while p and p:IsA("GuiObject") do
		if not p.Visible then
			return false
		end
		p = p.Parent
	end
	local g = o:FindFirstAncestorWhichIsA("LayerCollector")
	return g == nil or not g:IsA("ScreenGui") or g.Enabled
end
UiKit.naTela = naTela
-- o foco do controle está numa tela à vista que fica por cima desta (DisplayOrder maior)?
focoPorCima = function(root: GuiObject): boolean
	local cur = GuiService.SelectedObject
	if not (cur and naTela(cur)) then
		return false
	end
	local a = cur:FindFirstAncestorWhichIsA("ScreenGui")
	local b = root:FindFirstAncestorWhichIsA("ScreenGui")
	return a ~= nil and b ~= nil and a ~= b and a.DisplayOrder > b.DisplayOrder
end
UiKit.focoPorCima = focoPorCima
local function focoValido(f: GuiObject?): boolean
	return f ~= nil and f.Parent ~= nil and f.Selectable and naTela(f)
end
function UiKit.closed(name: string, semVoltarFoco: boolean?)
	for i, e in stack do
		if e.name == name then
			table.remove(stack, i)
			local f = e.foco
			if not semVoltarFoco and Input.isGamepad() and f then
				task.defer(function()
					if focoValido(f) then
						GuiService.SelectedObject = f
					end
				end)
			end
			return
		end
	end
end
function UiKit.opened(name: string, order: number?)
	local antes = GuiService.SelectedObject
	UiKit.closed(name, true)
	local o = order or 0
	local at = #stack + 1
	while at > 1 and stack[at - 1].order > o do
		at -= 1
	end
	table.insert(stack, at, { name = name, order = o, foco = antes })
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

-- ----- confirmação (D-205; prompt de interface §18, "Modais": "confirmação clara para sair da
-- partida, descartar alterações ou outras ações relevantes. Ofereça confirmar e voltar, com foco
-- previsível") -----
-- Uma janela por vez, por cima das telas (DisplayOrder 95). O foco do controle começa em VOLTAR (a
-- resposta que não muda nada) e não sai da janela; B ou Backspace voltam. Ao fechar, o foco volta
-- para onde estava (UiKit.closed). Devolve uma função que fecha sem responder (a tela que abriu a
-- confirmação fechou por outro motivo).
export type ModalOpts = {
	titulo: string,
	texto: string?,
	confirmar: string?, -- padrão "CONFIRMAR"
	voltar: string?, -- padrão "VOLTAR"
	perigo: boolean?, -- confirmar em vermelho (apagar, sair, descartar)
	aoConfirmar: () -> (),
	aoVoltar: (() -> ())?,
}
local modalGui: ScreenGui? = nil
local modalAberto: ((ok: boolean, silencioso: boolean?) -> ())? = nil
function UiKit.modal(o: ModalOpts): () -> ()
	local anterior = modalAberto
	if anterior then
		anterior(false, true)
	end
	local px, V = Estilo.px, Estilo.V
	local g = modalGui or UiKit.screen("VT65Confirma", 95)
	modalGui = g
	g.Enabled = true
	-- véu escuro: cobre também a borda fora da área segura, e nada atrás recebe clique
	local veu = Instance.new("Frame")
	veu.Name = "Veu"
	veu.Active = true
	veu.BackgroundColor3 = Color3.new(0, 0, 0)
	veu.BackgroundTransparency = 1
	veu.BorderSizePixel = 0
	veu.Position = UDim2.fromOffset(-200, -200)
	veu.Size = UDim2.new(1, 400, 1, 400)
	veu.Parent = g
	local painel = Estilo.panel(g, V.PANEL, 0, true)
	painel.Name = "Confirmacao"
	painel.Active = true
	painel.AnchorPoint = Vector2.new(0.5, 0.5)
	painel.Position = UDim2.fromScale(0.5, 0.5)
	painel.Size = UDim2.new(0.92, 0, 0, 0)
	painel.AutomaticSize = Enum.AutomaticSize.Y
	-- o foco do controle não sai da janela
	painel.SelectionGroup = true
	painel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	painel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	painel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	painel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(px(480, 680), math.huge)
	lim.Parent = painel
	local esc = Instance.new("UIScale")
	esc.Name = "Escala"
	esc.Parent = painel
	local gap = px(14, 20)
	Estilo.pad(painel, px(22, 30), nil, px(20, 28), px(20, 28))
	Estilo.list(painel, false, gap)
	local faixa = Instance.new("Frame")
	faixa.Name = "Faixa"
	faixa.BackgroundColor3 = if o.perigo then V.RED else V.AMBAR
	faixa.BorderSizePixel = 0
	faixa.Size = UDim2.new(0, px(48, 64), 0, px(3, 4))
	faixa.LayoutOrder = 1
	faixa.Parent = painel
	local titulo = Estilo.title(painel, UiKit.upper(o.titulo), px(26, 36))
	titulo.Name = "Titulo"
	titulo.TextWrapped = true
	titulo.TextTruncate = Enum.TextTruncate.None
	titulo.AutomaticSize = Enum.AutomaticSize.Y
	titulo.Size = UDim2.new(1, 0, 0, px(30, 42))
	titulo.LayoutOrder = 2
	if o.texto and o.texto ~= "" then
		local corpo = Estilo.body(painel, o.texto, px(16, 24), V.DIM)
		corpo.Name = "Texto"
		corpo.AutomaticSize = Enum.AutomaticSize.Y
		corpo.Size = UDim2.new(1, 0, 0, px(20, 28))
		corpo.LayoutOrder = 3
	end
	local linha = Instance.new("Frame")
	linha.Name = "Botoes"
	linha.BackgroundTransparency = 1
	linha.Size = UDim2.new(1, 0, 0, px(48, 66))
	linha.LayoutOrder = 4
	linha.Parent = painel
	Estilo.list(linha, true, gap)
	local feito = false
	local fechar: (ok: boolean, silencioso: boolean?) -> ()
	local h = px(48, 66)
	local voltar = UiKit.action(linha, o.voltar or "VOLTAR", "secondary", function()
		fechar(false)
	end, { action = "ui_back", ctx = "menu", h = h })
	voltar.button.Name = "Voltar"
	voltar.button.Size = UDim2.new(0.5, -math.floor(gap / 2), 0, h)
	voltar.button.LayoutOrder = 1
	local conf = UiKit.action(linha, o.confirmar or "CONFIRMAR", if o.perigo then "danger" else "primary", function()
		fechar(true)
	end, { h = h })
	conf.button.Name = "Confirmar"
	conf.button.Size = UDim2.new(0.5, -math.floor(gap / 2), 0, h)
	conf.button.LayoutOrder = 2
	UiKit.principal(voltar.button)
	fechar = function(ok: boolean, silencioso: boolean?)
		if feito then
			return
		end
		feito = true
		if modalAberto == fechar then
			modalAberto = nil
		end
		UiKit.release(painel)
		veu:Destroy()
		painel:Destroy()
		UiKit.closed("confirma", silencioso)
		if modalAberto == nil then
			g.Enabled = false
		end
		if not silencioso then
			if ok then
				o.aoConfirmar()
			elseif o.aoVoltar then
				(o.aoVoltar :: () -> ())()
			end
		end
	end
	modalAberto = fechar
	UiKit.opened("confirma", g.DisplayOrder)
	-- entrada curta: o véu escurece e a janela cresce de 96 % (sem crescer com movimento reduzido)
	UiKit.tween(veu, UiKit.QUICK, { BackgroundTransparency = 0.45 })
	esc.Scale = 0.96
	UiKit.tween(esc, UiKit.SOFT, { Scale = 1 })
	UiKit.focus(painel)
	return function()
		fechar(false, true)
	end
end
Input.on("ui_back", "press", function()
	local f = modalAberto
	if f and UiKit.backFor("confirma") then
		f(false)
	end
end)

-- ----- abas (D-205; §18 componentes, §19 "navegar por abas", tabela de controles: "Alternar abas:
-- LB/RB") -----
-- Fileira de abas com LB/RB (ou Q/E) nas pontas; a ativa em texto claro com o traço âmbar embaixo.
-- Clique, toque, LB/RB e Q/E trocam. tela: o nome dado ao UiKit.opened (LB/RB só valem com ela por
-- cima e as abas à vista). aoTrocar(id) roda a cada troca, não na criação. Sai do registro sozinha
-- quando o quadro é destruído.
export type Aba = { id: string, nome: string }
export type Abas = {
	frame: Frame,
	set: (id: string, silencioso: boolean?) -> (),
	atual: () -> string,
	passo: (dir: number) -> (),
	tela: string,
}
local abasVivas: { [Frame]: Abas } = {}
function UiKit.abas(parent: Instance, lista: { Aba }, tela: string, aoTrocar: (id: string) -> (), h: number?): Abas
	local px, V = Estilo.px, Estilo.V
	local H = h or px(44, 60)
	local row = Instance.new("Frame")
	row.Name = "Abas"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, H)
	row.Parent = parent
	local lay = Estilo.list(row, true, px(16, 24))
	lay.VerticalAlignment = Enum.VerticalAlignment.Bottom
	local function dica(ordem: number): (ImageLabel, TextLabel)
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(math.floor(H * 0.62), math.floor(H * 0.62))
		img.LayoutOrder = ordem
		img.Parent = row
		local t = Estilo.text(row, "", px(14, 20), V.TEXT, Estilo.F.TITLE_MED)
		t.BackgroundColor3 = V.PANEL_3
		t.BackgroundTransparency = 0
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromOffset(0, math.floor(H * 0.6))
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.LayoutOrder = ordem
		Estilo.corner(t, 3)
		Estilo.stroke(t, V.LINE, 1, 0.2)
		Estilo.pad(t, px(7, 10))
		t.Parent = row
		return img, t
	end
	local imgA, keyA = dica(0)
	local imgB, keyB = dica(#lista + 1)
	local function dica1(img: ImageLabel, key: TextLabel, acao: string)
		local i, txt = Input.glyph(acao, "menu")
		local toque = Input.touchActive()
		img.Visible = not toque and i ~= nil
		img.Image = i or ""
		key.Visible = not toque and i == nil and txt ~= ""
		key.Text = UiKit.keyName(txt)
	end
	local function dicas()
		dica1(imgA, keyA, "ui_tab_prev")
		dica1(imgB, keyB, "ui_tab_next")
	end
	dicas()
	local devConn = Input.DeviceChanged:Connect(dicas)
	local atual = lista[1] and lista[1].id or ""
	local botoes: { [string]: TextButton } = {}
	local api: Abas
	local function pinta()
		for id, b in botoes do
			local on = id == atual
			b.TextColor3 = if on then V.TEXT else V.DIM
			local m = b:FindFirstChild("Marca") :: Frame?
			if m then
				m.BackgroundTransparency = if on then 0 else 1
			end
		end
	end
	for i, d in lista do
		local b = Instance.new("TextButton")
		b.Name = "Aba_" .. d.id
		b.AutoButtonColor = false
		b.AutomaticSize = Enum.AutomaticSize.X
		b.Size = UDim2.fromOffset(0, H)
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.FontFace = Estilo.headFont(d.nome, Estilo.F.TITLE_MED)
		b.TextSize = Estilo.ts(px(17, 23))
		b.Text = d.nome
		-- LB/RB trocam a aba; o foco fica no conteúdo (aba focável prenderia o direcional no alto)
		b.Selectable = false
		b.LayoutOrder = i
		b.Parent = row
		Estilo.pad(b, px(2, 4), nil, 0, px(8, 10))
		local m = Instance.new("Frame")
		m.Name = "Marca"
		m.AnchorPoint = Vector2.new(0.5, 1)
		m.Position = UDim2.new(0.5, 0, 1, px(8, 10))
		m.Size = UDim2.new(1, px(4, 8), 0, px(3, 4))
		m.BackgroundColor3 = V.AMBAR
		m.BorderSizePixel = 0
		m.Parent = b
		b.MouseEnter:Connect(function()
			if d.id ~= atual then
				b.TextColor3 = V.TEXT
			end
		end)
		b.MouseLeave:Connect(pinta)
		UiKit.bind(b, function()
			api.set(d.id)
		end)
		botoes[d.id] = b
	end
	api = {
		frame = row,
		tela = tela,
		atual = function(): string
			return atual
		end,
		set = function(id: string, silencioso: boolean?)
			if not botoes[id] then
				return
			end
			local mudou = id ~= atual
			atual = id
			pinta()
			if mudou and not silencioso then
				aoTrocar(id)
			end
		end,
		passo = function(dir: number)
			local n = #lista
			if n == 0 then
				return
			end
			local i = 1
			for k, d in lista do
				if d.id == atual then
					i = k
				end
			end
			api.set(lista[(i - 1 + dir) % n + 1].id)
		end,
	}
	pinta()
	abasVivas[row] = api
	row.Destroying:Connect(function()
		abasVivas[row] = nil
		devConn:Disconnect()
	end)
	return api
end
for acao, dir in { ui_tab_prev = -1, ui_tab_next = 1 } :: { [string]: number } do
	Input.on(acao, "press", function()
		local topo = UiKit.top()
		for row, a in abasVivas do
			if a.tela == topo and naTela(row) then
				a.passo(dir)
				return
			end
		end
	end)
end

-- ----- vitrine dos componentes (só no Studio, D-205) -----
-- workspace "VT65DevTela" (do lado do cliente): "componentes" abre a vitrine (abas, estados do
-- cartão e do botão); "confirma" abre uma confirmação e grava a resposta em "VT65DevConfirma"
-- ("confirmou"/"voltou"); "aba:+1" e "aba:-1" passam a aba como LB/RB. Repetir o valor: nil antes.
if game:GetService("RunService"):IsStudio() then
	local vitrine: ScreenGui? = nil
	local function abrirVitrine()
		if vitrine then
			vitrine:Destroy()
		end
		local px, V = Estilo.px, Estilo.V
		local g = UiKit.screen("VT65Componentes", 60)
		vitrine = g
		local p = Estilo.panel(g, V.PANEL, 0, true)
		p.Name = "Vitrine"
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(0.5, 0.5)
		p.Size = UDim2.fromOffset(px(700, 980), px(440, 620))
		Estilo.pad(p, px(20, 28), nil, px(14, 20))
		local corpo = Instance.new("Frame")
		corpo.Name = "Corpo"
		corpo.BackgroundTransparency = 1
		corpo.Position = UDim2.fromOffset(0, px(60, 84))
		corpo.Size = UDim2.new(1, 0, 1, -px(60, 84))
		corpo.Parent = p
		local function limpar()
			for _, c in corpo:GetChildren() do
				c:Destroy()
			end
		end
		local function grade(): Frame
			local f = Instance.new("Frame")
			f.BackgroundTransparency = 1
			f.Size = UDim2.fromScale(1, 1)
			f.Parent = corpo
			local gl = Instance.new("UIGridLayout")
			gl.CellSize = UDim2.fromOffset(px(210, 300), px(64, 90))
			gl.CellPadding = UDim2.fromOffset(px(12, 16), px(12, 16))
			gl.SortOrder = Enum.SortOrder.LayoutOrder
			gl.Parent = f
			return f
		end
		local function desenhar(id: string)
			limpar()
			local f = grade()
			if id == "estados" then
				for i, nome in
					{ "adquirido", "equipado", "bloqueado", "indisponivel", "selecionado", "carregando", "erro" }
				do
					local c = Estilo.itemCard(f, "M14", "FUZIL", V.KHAKI)
					c.frame.Name = "Cartao_" .. nome
					c.frame.LayoutOrder = i
					c.mark.Text = "M14"
					Estilo.cardEstado(c, nome)
				end
			else
				local a = UiKit.action(f, "PRINCIPAL", "primary", function() end, { h = px(56, 78) })
				a.button.LayoutOrder = 1
				UiKit.action(f, "SECUNDÁRIO", "secondary", function() end, { h = px(56, 78) }).button.LayoutOrder = 2
				UiKit.action(f, "PERIGO", "danger", function() end, { h = px(56, 78) }).button.LayoutOrder = 3
				local d = UiKit.action(f, "APAGADO", "primary", function() end, { h = px(56, 78) })
				d.button.LayoutOrder = 4
				d.enabled(false)
				local c = UiKit.action(f, "CARREGANDO", "primary", function() end, { h = px(56, 78) })
				c.button.LayoutOrder = 5
				c.carregando(true)
				local e = UiKit.action(f, "COM ERRO", "secondary", function() end, { h = px(56, 78) })
				e.button.Name = "ComErro"
				e.button.LayoutOrder = 6
				e.erro("Falhou")
				UiKit.principal(a.button)
			end
			UiKit.focus(corpo)
		end
		UiKit.abas(p, {
			{ id = "estados", nome = "ESTADOS" },
			{ id = "botoes", nome = "BOTÕES" },
		}, "componentes", desenhar)
		desenhar("estados")
		UiKit.opened("componentes", g.DisplayOrder)
		g.Destroying:Connect(function()
			UiKit.closed("componentes")
		end)
	end
	Input.on("ui_back", "press", function()
		local v = vitrine
		if v and UiKit.backFor("componentes") then
			vitrine = nil
			v:Destroy()
		end
	end)
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if v == "componentes" then
			abrirVitrine()
		elseif v == "componentes:fechar" and vitrine then
			(vitrine :: ScreenGui):Destroy()
			vitrine = nil
		elseif v == "confirma" then
			workspace:SetAttribute("VT65DevConfirma", nil)
			UiKit.modal({
				titulo = "Restaurar padrões?",
				texto = "Todas as opções desta aba voltam ao padrão.",
				confirmar = "RESTAURAR",
				perigo = true,
				aoConfirmar = function()
					workspace:SetAttribute("VT65DevConfirma", "confirmou")
				end,
				aoVoltar = function()
					workspace:SetAttribute("VT65DevConfirma", "voltou")
				end,
			})
		elseif v == "aba:+1" or v == "aba:-1" then
			local topo = UiKit.top()
			for row, a in abasVivas do
				if a.tela == topo and naTela(row) then
					a.passo(if v == "aba:+1" then 1 else -1)
					break
				end
			end
		end
	end)
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
