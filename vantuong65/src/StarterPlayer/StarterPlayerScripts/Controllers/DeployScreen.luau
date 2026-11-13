--!strict
-- Lobby (Partes 4 e 12.5) sobre a mesa 3D do LobbyScene (pedido do dono, 2026-11-11). Os objetos
-- da mesa são os botões; esta tela põe por cima os painéis que eles abrem. Estilo novo (o dono não
-- gostou do papel datilografado): painéis escuros sólidos, títulos grandes em Oswald caixa alta,
-- números grandes (efetivo, vagas, dias), corpo em Arimo, poucas palavras; etiquetas cheias no
-- lugar dos carimbos. Os nomes antigos das peças (folder, stamp, CARD, INK) ficaram, com o visual
-- novo, para não reescrever a lógica:
--   - sala de arquivo (antes do lado, ou "trocar de lado"): os dois dossiês na mesa e as duas fichas
--     de alistamento embaixo;
--   - mesa do lado: visão geral; rádio/telefone = SQUAD, dossiê/documentos e o soldado = PAPEL,
--     carta/croqui = INSERÇÃO (o mapa de spawn do GameUI), calendário/caderneta = RECOMPENSA
--     DIÁRIA, munição = INTENDÊNCIA (a loja), capacete = TROCAR DE LADO.
-- Abas no alto repetem os objetos (mouse, toque, LB/RB e Q/E). Ao escolher, a câmera vai até o
-- objeto e o painel abre do lado dele. Fluxo: lado → mesa → squad → papel → inserção (avança
-- sozinho); morto com papel, o lobby já abre na inserção. B / VOLTAR: painel → mesa; sala de arquivo
-- (trocando de lado) → mesa.
-- Construída uma vez: render() só troca textos, cores e visibilidade (os cartões ficam num
-- reservatório por chave). Só dados reais: Roles, Weapons, MapConfig, efetivo pelo atributo
-- "Faction" (a conta do TeamService) e a caderneta do servidor (Daily_State).
-- Remotes: Team_Choose, Squad_Action {op = create/join/leave}, Role_Choose, Daily_Get/Daily_Claim.
-- Movimento e acabamento (pedido do dono, 2026-11-11: "mais fluido e com uma qualidade gráfica
-- melhor ... faça com maestria", realismo de época):
--   - troca de pasta em crossfade: a que sai esmaece e recua, a que entra desliza e abre; durante a
--     troca cada pasta vai para um CanvasGroup do tamanho dela (em repouso fica fora, texto nítido);
--   - cartões entram escalonados (um véu da cor do painel some, escala e giro assentam); as
--     etiquetas de estado aparecem crescendo um pouco;
--   - realce animado no mouse, no foco do controle e no cursor virtual (UiKit.realce);
--   - painéis com sombra macia (Acabamento.sombra) e filete; selos com glifo por papel e por unidade
--     (glifos do Arimo, que vêm com o Roblox);
--   - o cartão do papel mostra o que muda ao escolher: as armas, e cano, cadência, carregador e peso
--     em barras que deslizam, com a diferença para o papel atual;
--   - abas com indicador deslizando; dicas de botão em chip (imagem do botão do controle ou tecla).
-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevTela", "escolha") abre o passo
-- de escolha (lado, se não há; senão squad ou papel); também "lado", "squad", "papel", "diaria" e
-- "insercao" (completa lado, squad e papel pelos remotes e abre a ficha de inserção). Ver o fim do
-- arquivo.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Commerce = require(ReplicatedStorage.Shared.Commerce)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local LobbyScene = require(script.Parent.LobbyScene)
local SoldierPreview = require(script.Parent.SoldierPreview)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)
local VirtualCursor = require(script.Parent.VirtualCursor)

local player = Players.LocalPlayer
local DeployScreen = {}

-- ===== estilo (linguagem nova, ReplicatedFirst/Estilo: o dono não gostou do papel datilografado) =====
-- Os nomes de antes ficam (a tela inteira os usa), agora com as cores do estilo novo: a "pasta" é
-- um painel escuro, a "ficha" é um cartão um tom acima, a "tinta" é o texto claro e o "carimbo"
-- é uma etiqueta cheia (vermelho de carimbo só para perigo). Nada de máquina de escrever.
local V, F = UiKit.V, UiKit.F
local HEAD = Enum.Font.Oswald -- títulos condensados
local TYPE = Enum.Font.Arimo -- corpo (a máquina de escrever saiu)
local VIET = Enum.Font.Arimo -- texto em vietnamita (o Oswald não tem as letras)
local INK, CARD, MANILA, DRAB, KHAKI, STAMP = V.TEXT, V.PANEL_2, V.PANEL, V.PANEL_2, V.KHAKI, V.RED
local CARD_HOT = V.PANEL_3 -- cartão sob o ponteiro
local CARD_OFF = Color3.fromRGB(24, 26, 21) -- cartão cheio ou trancado (apagado)
local NEW_CARD = Color3.fromRGB(44, 54, 32) -- "formar squad" (oliva escuro)
local OLIVE_INK = V.OLIVE -- etiqueta verde ("ABERTO", "ATUAL", "RECEBIDO")
local NOTICE = V.RED_HI
local BRASS = V.KHAKI
local HEAD_B = F.TITLE -- títulos em negrito (hierarquia)
local GLYPH = Font.fromEnum(Enum.Font.ArimoBold) -- glifos dos selos (todos existem no Arimo)
local VEIL = MANILA -- cor do painel sob os cartões (véu da entrada)
local DESIGN_W, DESIGN_H = 1280, 720

-- tempos de movimento
local QUICK = UiKit.QUICK
local SOFT = UiKit.SOFT
local PAGE_IN = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local PAGE_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
local function tw(o: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local t = TweenService:Create(o, info, props)
	t:Play()
	return t
end
local function after(delay: number, info: TweenInfo): TweenInfo
	return TweenInfo.new(info.Time, info.EasingStyle, info.EasingDirection, 0, false, delay)
end

-- selos: um glifo por papel e por unidade (sinais de carta militar, do que o Arimo tem)
local ROLE_GLYPH: { [string]: string } = {
	commander = "♦",
	squad_leader = "▲",
	rifleman = "×", -- o X do símbolo de infantaria
	automatic_rifleman = "‡", -- fuzileiro automático (EUA, 2026-11-12)
	grenadier = "⁂",
	machine_gunner = "≡", -- fita de munição
	anti_tank = "►",
	engineer = "⌂",
	medic = "+",
	radio_operator = "≈",
	observer = "∞", -- binóculo
	sniper = "◙",
	sapper = "▼",
	mortar = "∩", -- trajetória curva
	tank_crew = "▬",
	pilot = "┼", -- rotor visto de cima
	door_gunner = "◄",
}
local UNIT_GLYPH: { [string]: string } = {
	command = "♦",
	infantry = "×",
	recon = "∞",
	sapper = "▼",
	mortar = "∩",
	armor = "▬",
	helicopter = "┼",
}

local UNIT_ORDER = { "infantry", "command", "recon", "sapper", "mortar", "armor", "helicopter" }
local UNIT_NAME: { [string]: string } = {
	command = "Comando",
	infantry = "Infantaria",
	recon = "Reconhecimento",
	sapper = "Sapadores",
	mortar = "Morteiro",
	armor = "Blindado",
	helicopter = "Helicóptero",
}
local ROLE_ORDER = {
	"squad_leader",
	"rifleman",
	"automatic_rifleman",
	"grenadier",
	"machine_gunner",
	"anti_tank",
	"engineer",
	"medic",
	"radio_operator",
	"commander",
	"observer",
	"sniper",
	"sapper",
	"mortar",
	"tank_crew",
	"pilot",
	"door_gunner",
}

-- textos das facções: nomes e unidades de Starlite (research/F0_FONTES.md: RLT-7 com 3/3, 2/4 e 3/7;
-- o 1º Regimento VC, força principal); uniforme como o Characters veste por padrão
type FactionInfo = { stamp: string, title: string, unit: string, short: string, kit: string }
local FACTION: { [string]: FactionInfo } = {
	US = {
		stamp = "USMC",
		title = "FUZILEIROS NAVAIS DOS EUA",
		unit = "RLT-7 · batalhões 3/3, 2/4 e 3/7",
		short = "EUA",
		kit = "Uniforme OG-107 · capacete M1 · colete M1955",
	},
	VC = {
		stamp = "QUÂN GIẢI PHÓNG",
		title = "1º REGIMENTO VIET CONG",
		unit = "Força principal",
		short = "VC",
		kit = "Uniforme cáqui",
	},
}

local function ordered(keys: { [string]: any }, pref: { string }): { string }
	local out = {}
	for _, k in pref do
		if keys[k] ~= nil then
			table.insert(out, k)
		end
	end
	local extra = {}
	for k in keys do
		if not table.find(pref, k) then
			table.insert(extra, k)
		end
	end
	table.sort(extra)
	for _, k in extra do
		table.insert(out, k)
	end
	return out
end
local UNITS_OF: { [string]: { string } } = {
	US = ordered(Roles.units.US, UNIT_ORDER),
	VC = ordered(Roles.units.VC, UNIT_ORDER),
}
local ROLE_IDS = ordered(Roles.roles, ROLE_ORDER)

-- grade de 1965 (6 algarismos) de um ponto do mapa, pela origem do MapConfig
local function gridRef(x: number, z: number): string
	local g = MapConfig.GridOrigin1965
	local e = g.e + x * MapConfig.STUD_M
	local n = g.n - z * MapConfig.STUD_M
	return string.format("BS %03d%03d", math.floor((e % 100000) / 100), math.floor((n % 100000) / 100))
end

local function weaponLine(id: string): string
	local w = Weapons.get(id)
	return if w then w.name else id
end

local function weaponNames(list: { string }?): string
	if not list then
		return "—"
	end
	local names = {}
	for _, id in list do
		table.insert(names, weaponLine(id))
	end
	return table.concat(names, " + ")
end

local function keyName(code: string): string
	return (string.gsub(code, "^Button", ""))
end

local function hms(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
end

-- ===== tamanho de texto (projeto 1280 x 720; na TV, nunca abaixo de 24 px na tela) =====
local scale = 1
local texts: { { o: any, s: number } } = {}
local function reg(o: any, s: number)
	table.insert(texts, { o = o, s = s })
	o.TextSize = UiKit.textAt(s, scale)
end

function DeployScreen.setScale(k: number)
	scale = k
	for _, e in texts do
		e.o.TextSize = UiKit.textAt(e.s, k)
	end
end

-- ===== peças =====
local function box(parent: Instance?, color: Color3, x: number, y: number, w: number, h: number, tr: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = tr or 0
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Parent = parent
	return f
end

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thick: number, tr: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.Transparency = tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function txt(
	parent: Instance,
	font: Enum.Font,
	size: number,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	align: Enum.TextXAlignment?
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = font
	t.TextColor3 = color
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Text = ""
	t.Parent = parent
	reg(t, size)
	return t
end

-- etiqueta de estado (era o carimbo de borracha): pílula cheia, reta, texto claro em Oswald.
-- `rot` ficou na assinatura (as chamadas antigas) e é ignorado: nada torto no estilo novo.
local function stamp(
	parent: Instance,
	size: number,
	x: number,
	y: number,
	w: number,
	h: number,
	_rot: number
): TextLabel
	local t = txt(parent, HEAD, math.min(size, 16), V.TEXT, x, y, w, h, Enum.TextXAlignment.Center)
	t.FontFace = F.TITLE_MED
	t.BackgroundColor3 = STAMP
	t.BackgroundTransparency = 0
	t.TextWrapped = false
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.ZIndex = 3
	corner(t, 3)
	local hit = Instance.new("UIScale")
	hit.Name = "Pancada"
	hit.Parent = t
	return t
end

-- cor da etiqueta (o fundo; o texto fica claro). "Tinta" comum vira um cinza de painel.
local function inkStamp(t: TextLabel, color: Color3)
	t.BackgroundColor3 = if color == INK then V.PANEL_3 else color
end

-- a etiqueta aparece: cresce um pouco e assenta em 0,2 s
local function thump(t: TextLabel, delay: number?)
	local hit = t:FindFirstChild("Pancada")
	local d = delay or 0
	if hit and hit:IsA("UIScale") then
		hit.Scale = 1.2
		tw(hit, after(d, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)), { Scale = 1 })
	end
	t.TextTransparency = 1
	t.BackgroundTransparency = 1
	tw(t, after(d, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)), {
		TextTransparency = 0,
		BackgroundTransparency = 0,
	})
end

-- Muda o carimbo; se o texto mudou (ou ele apareceu agora), ele cai de novo.
local function stampSet(t: TextLabel, text: string?, color: Color3?, delay: number?)
	local show = text ~= nil and text ~= ""
	local changed = show and (not t.Visible or t.Text ~= text)
	t.Visible = show
	if not show then
		return
	end
	t.Text = text :: string
	if color then
		inkStamp(t, color)
	end
	if changed then
		thump(t, delay)
	end
end

-- selo redondo com glifo (papel, unidade): anel de tinta e o sinal no meio
local function seal(parent: Instance, x: number, y: number, d: number, glyph: string): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.Name = "Selo"
	f.BackgroundColor3 = V.PANEL_3
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(d, d)
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	stroke(f, V.LINE, 1, 0.2)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = GLYPH
	t.TextColor3 = V.KHAKI
	t.Text = glyph
	t.Parent = f
	reg(t, math.floor(d * 0.56))
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = f
	return f, t
end

-- filete: as linhas de ficha (vermelha de cabeçalho, azul de pauta) viram o filete fino do painel
local function hline(parent: Instance, color: Color3, x: number, y: number, w: number, tr: number?)
	local paperLine = color == UiKit.RULE_RED or color == UiKit.RULE_BLUE
	box(parent, if paperLine then V.LINE else color, x, y, w, 1, if paperLine then 0.35 else tr)
end

-- era a luz de cima do papel; os painéis do estilo novo são lisos (nada a fazer)
local function paper(_parent: Instance, _rot: number) end

-- Peças da entrada escalonada: o UIScale "Escala" (também do realce) e o "Veu", um quadro da cor da
-- pasta por cima de tudo que some quando o cartão "pousa" na pasta.
local function entryParts(o: GuiObject, radius: number?)
	local sc = Instance.new("UIScale")
	sc.Name = "Escala"
	sc.Parent = o
	local veil = Instance.new("Frame")
	veil.Name = "Veu"
	veil.BackgroundColor3 = VEIL
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.Size = UDim2.fromScale(1, 1)
	veil.ZIndex = 20
	if radius then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, radius)
		c.Parent = veil
	end
	pcall(function()
		veil.Interactable = false -- não tapa o clique nem o cursor virtual
	end)
	veil.Parent = o
end

-- Cartão clicável (com as peças da entrada escalonada).
local function cardButton(parent: Instance?, w: number, h: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(w, h)
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	entryParts(b, 3)
	b.Parent = parent
	return b
end

-- Entrada escalonada: cada cartão "pousa" (véu some, escala e um leve giro assentam), um depois do
-- outro. Só os visíveis, na ordem em que aparecem.
local function deal(list: { GuiObject }, delay0: number?, step: number?)
	local d0 = delay0 or 0.1
	local k = 0
	for _, b in list do
		if not b.Visible then
			continue
		end
		local d = d0 + k * (step or 0.035)
		k += 1
		local veil = b:FindFirstChild("Veu")
		if veil and veil:IsA("Frame") then
			veil.BackgroundTransparency = 0
			tw(veil, after(d, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)), {
				BackgroundTransparency = 1,
			})
		end
		local sc = b:FindFirstChild("Escala")
		if sc and sc:IsA("UIScale") then
			sc.Scale = 0.95
			tw(sc, after(d, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)), { Scale = 1 })
		end
	end
end

-- botões visíveis de uma lista, na ordem do LayoutOrder (para a entrada escalonada)
local function byOrder(list: { GuiObject }): { GuiObject }
	local out = {}
	for _, b in list do
		if b.Visible then
			table.insert(out, b)
		end
	end
	table.sort(out, function(a: GuiObject, b: GuiObject): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return out
end

-- clique (mouse, toque, A) + realce do mouse, do foco nativo e do cursor virtual do controle
local function bindCard(b: GuiButton, onClick: () -> (), fn: ((on: boolean) -> ())?)
	local over, sel, pad = false, false, false
	local function apply()
		if fn then
			fn(over or sel or pad)
		end
	end
	b.MouseEnter:Connect(function()
		over = true
		apply()
	end)
	b.MouseLeave:Connect(function()
		over = false
		apply()
	end)
	b.SelectionGained:Connect(function()
		sel = true
		apply()
	end)
	b.SelectionLost:Connect(function()
		sel = false
		apply()
	end)
	UiKit.bind(b, onClick, function(on: boolean)
		pad = on
		apply()
	end)
end

local function scroller(parent: Instance, x: number, y: number, w: number, h: number): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Position = UDim2.fromOffset(x, y)
	s.Size = UDim2.fromOffset(w, h)
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ScrollBarThickness = 4
	s.ScrollBarImageColor3 = V.LINE
	s.Selectable = false -- o foco vai nos cartões, nunca na rolagem
	s.Parent = parent
	return s
end

-- Painel de briefing (o espírito da primeira tela de carregamento, que o dono adorou): fundo escuro
-- levemente translúcido sobre a cena, borda fina cáqui, barra da cor do lado à esquerda, título
-- grande em Oswald e poucas linhas. O visual (a cena 3D, o soldado, a carta) fica ao lado, livre.
-- Devolve o painel e a linha de informação à direita do título (curta: um número, um estado).
-- As barras de acento ganham a cor do lado do jogador (sideAccents, pintadas no updateHeader).
local sideAccents: { Frame } = {}
local function folder(parent: Instance, tab: string, w: number, h: number): (Frame, TextLabel)
	local f = box(parent, MANILA, 0, 0, w, h, 0.1)
	f.Name = "Pasta"
	f.Active = true -- tapa a mesa atrás (clique e cursor não atravessam)
	f.ZIndex = 2
	corner(f, 3)
	stroke(f, V.KHAKI, 1, 0.72)
	local shadow = Acabamento.sombra(f, 20, Vector2.new(0, 9), 0.6)
	shadow.ZIndex = 0
	table.insert(sideAccents, box(f, V.OLIVE, 0, 0, 5, h)) -- barra do lado
	local tt = txt(f, HEAD, 28, V.TEXT, 22, 6, w - 40, 38)
	tt.FontFace = HEAD_B
	tt.TextWrapped = false
	tt.Text = tab
	table.insert(sideAccents, box(f, V.OLIVE, 22, 44, 44, 3)) -- filete sob o título
	local info =
		txt(f, TYPE, 15, V.DIM, math.floor(w * 0.42), 10, math.floor(w * 0.58) - 18, 30, Enum.TextXAlignment.Right)
	info.TextTruncate = Enum.TextTruncate.AtEnd
	return f, info
end

-- botão de ação secundária (contorno fino; realce: escala e fundo um tom acima)
local function darkButton(parent: Instance, text: string, x: number, y: number, w: number, h: number): TextButton
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, h)
	b.BackgroundColor3 = DRAB
	b.TextColor3 = V.TEXT
	b.FontFace = F.TITLE_MED
	b.AutoButtonColor = false
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Text = text
	b.Parent = parent
	reg(b, 17)
	corner(b, 4)
	stroke(b, V.LINE, 1, 0.1)
	return b
end

local function bindDark(b: GuiButton, onClick: () -> ())
	local r = UiKit.realce(b, DRAB, V.PANEL_3, 1.03)
	bindCard(b, onClick, r.set)
end

-- texto que entra (era datilografado): troca e aparece em 0,2 s; nada de máquina de escrever
local function reveal(t: TextLabel, text: string, delay: number?)
	if t.Text == text then
		return
	end
	t.Text = text
	t.TextTransparency = 1
	tw(
		t,
		after(delay or 0, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)),
		{ TextTransparency = 0 }
	)
end

-- ===== raiz =====
local root = Instance.new("Frame")
root.Name = "Deploy"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Visible = false
DeployScreen.root = root
DeployScreen.changed = function() end -- o GameUI troca pelo refresh()
-- definidas mais abaixo (as abas e os cartões já chamam)
DeployScreen.open = function(_name: string) end
DeployScreen.back = function(): boolean
	return false
end

-- ponto do palco de projeto (1280 x 720) -> NDC da câmera (onde o objeto 3D deve aparecer)
local function ndc(dx: number, dy: number): Vector2
	local cam = workspace.CurrentCamera
	if not cam then
		return Vector2.zero
	end
	local a, s = root.AbsolutePosition, root.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return Vector2.new(dx / DESIGN_W * 2 - 1, 1 - dy / DESIGN_H * 2)
	end
	local inset = GuiService:GetGuiInset()
	local p = a + Vector2.new(dx / DESIGN_W * s.X, dy / DESIGN_H * s.Y) + inset
	local vp = cam.ViewportSize
	return Vector2.new(p.X / math.max(vp.X, 1) * 2 - 1, 1 - p.Y / math.max(vp.Y, 1) * 2)
end

-- cabeçalho: o nome grande (nome novo do jogo, pedido do dono), uma linha curta e o efetivo dos
-- lados em números grandes à direita. Cor fixa por lado em tudo: EUA azul, VC vermelho.
do
	local title = txt(root, HEAD, 38, V.TEXT, 40, 6, 600, 46)
	title.FontFace = HEAD_B
	title.TextWrapped = false
	title.Text = "STARLITE: Vietnã 1965"
	-- o subtítulo tem letras do vietnamita (Vạn Tường): no Arimo, que tem
	local subtitle = txt(root, TYPE, 16, V.DIM, 40, 52, 600, 22)
	subtitle.TextWrapped = false
	subtitle.Text = "Operação Starlite · Vạn Tường, 18–24 ago 1965"
end
local function sideColor(f: string?): Color3
	return if f == "US" then V.US elseif f == "VC" then V.VC else V.OLIVE
end
local teamNums: { [string]: TextLabel } = {}
do
	for i, f in { "US", "VC" } do
		local x = 900 + (i - 1) * 176
		local k = txt(root, HEAD, 14, sideColor(f), x, 4, 156, 18, Enum.TextXAlignment.Right)
		k.FontFace = F.TITLE_MED
		k.Text = if f == "US" then "EUA" else "VC"
		box(root, sideColor(f), x + 162, 8, 3, 46)
		local n = txt(root, HEAD, 32, sideColor(f), x, 20, 156, 36, Enum.TextXAlignment.Right)
		n.FontFace = HEAD_B
		n.TextWrapped = false
		teamNums[f] = n
	end
end
local notice = txt(root, TYPE, 15, NOTICE, 560, 60, 680, 22, Enum.TextXAlignment.Right)
notice.RichText = true
notice.TextTruncate = Enum.TextTruncate.AtEnd

-- lugar do posto (rank) e da experiência: atributos "Rank" e "XP" (números) do jogador, publicados
-- pelo sistema de progressão; sem eles, a plaqueta fica escondida
local rankTag = box(root, DRAB, 470, 14, 220, 30) -- depois do título (o nome novo é mais longo)
corner(rankTag, 3)
paper(rankTag, 90)
local rankEdge = stroke(rankTag, BRASS, 1, 0.45)
local rankPop = Instance.new("UIScale")
rankPop.Parent = rankTag
local rankText = txt(rankTag, HEAD, 16, KHAKI, 8, 0, 204, 30, Enum.TextXAlignment.Center)
rankText.FontFace = HEAD_B
local function rankLine(): string?
	local r, xp = player:GetAttribute("Rank"), player:GetAttribute("XP")
	if type(r) ~= "number" then
		return nil
	end
	return if type(xp) == "number"
		then string.format("POSTO %d · %d XP", r, math.floor(xp))
		else string.format("POSTO %d", r)
end
local function renderRank()
	local line = rankLine()
	local changed = rankTag.Visible and line ~= nil and line ~= rankText.Text
	rankTag.Visible = line ~= nil
	rankText.Text = line or ""
	if changed then -- XP ou posto novo: a plaqueta acende e assenta
		rankPop.Scale = 1.08
		rankEdge.Transparency = 0
		tw(rankPop, SOFT, { Scale = 1 })
		tw(rankEdge, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Transparency = 0.45 })
	end
end
renderRank()
player:GetAttributeChangedSignal("Rank"):Connect(renderRank)
player:GetAttributeChangedSignal("XP"):Connect(renderRank)
-- aviso do cabeçalho: aparece e some esmaecendo depois de 6 s
local noticeToken = 0
local function notify(msg: string)
	noticeToken += 1
	local my = noticeToken
	notice.Text = ""
	reveal(notice, Acabamento.viet(msg))
	task.delay(6, function()
		if noticeToken == my then
			local t =
				tw(notice, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { TextTransparency = 1 })
			t.Completed:Once(function()
				if noticeToken == my then
					notice.Text = ""
					notice.TextTransparency = 0
				end
			end)
		end
	end)
end

-- ===== estado =====
local panel = "desk" -- "desk" | "squad" | "role" | "insert" | "daily" | "shop"
local browsing = false -- na sala de arquivo para trocar de lado (vale enquanto o lado não muda)
local browsingFaction: string? = nil
local wasVisible = false
local previewRole: string? = nil
local hoverFaction: string? = nil -- ficha/dossiê de lado sob o ponteiro
local cycleIdx = 0

local function myFaction(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" and FACTION[f] then f else nil
end

local function isBrowsing(): boolean
	return browsing and browsingFaction ~= nil and browsingFaction == myFaction()
end

local function sceneId(): string
	local f = myFaction()
	if not f or isBrowsing() then
		return "choose"
	end
	return f
end

local function alive(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function hasSquad(): boolean
	return type(player:GetAttribute("SquadId")) == "string"
end

local function currentRole(): string?
	local r = player:GetAttribute("Role")
	return if type(r) == "string" then r else nil
end

-- painel ao abrir o lobby: morto com papel vai direto à inserção; o resto começa na mesa
local function defaultPanel(): string
	if myFaction() and currentRole() and hasSquad() and not alive() then
		return "insert"
	end
	return "desk"
end

-- próximo passo para entrar em campo (o objeto pisca na mesa)
local function nextStep(): string?
	if not myFaction() then
		return nil
	elseif not hasSquad() then
		return "squad"
	elseif not currentRole() then
		return "role"
	elseif not alive() then
		return "insert"
	end
	return nil
end

local function counts(): (number, number)
	local us, vc = 0, 0
	for _, p in Players:GetPlayers() do
		local f = p:GetAttribute("Faction")
		if f == "US" then
			us += 1
		elseif f == "VC" then
			vc += 1
		end
	end
	return us, vc
end

-- mesma regra do TeamService (Team_Choose): lado cheio ou que desequilibraria é recusado
local function joinBlocked(f: string): string?
	local us, vc = counts()
	local mine = if f == "US" then us else vc
	local theirs = if f == "US" then vc else us
	local cur = myFaction()
	if cur == f then
		return nil
	elseif cur ~= nil then
		theirs -= 1
	end
	if mine >= Roles.TEAM_MAX then
		return "LOTADO"
	elseif mine > theirs then
		return "EM EXCESSO"
	end
	return nil
end

-- ===== recompensa diária (estado do servidor) =====
local daily: any = nil
local dailyAt = 0 -- os.clock() da chegada (contagem regressiva local)
local dailyBusy = false
local dailyResult: any = nil
local dailyAsked = 0

local function fetchDaily()
	local now = os.clock()
	if now - dailyAsked < 3 then
		return
	end
	dailyAsked = now
	task.spawn(function()
		local ok, s = pcall(function()
			return Net.func("Daily_Get"):InvokeServer()
		end)
		if ok and type(s) == "table" then
			daily = s
			dailyAt = os.clock()
			DeployScreen.changed()
		end
	end)
end

local function dailyLeft(): number
	if not (daily and type(daily.resetIn) == "number") then
		return 0
	end
	return daily.resetIn - (os.clock() - dailyAt)
end

local function itemName(id: string): string
	local c = Commerce.find(id)
	return if c then c.name else id
end

-- ===== painéis =====
local function page(x: number, y: number, w: number, h: number): Frame
	local p = Instance.new("Frame")
	p.BackgroundTransparency = 1
	p.AnchorPoint = Vector2.new(0.5, 0.5) -- a pasta "abre" pelo meio (o UIScale escala pela âncora)
	p.Position = UDim2.fromOffset(x + w / 2, y + h / 2)
	p.Size = UDim2.fromOffset(w, h)
	return p
end
local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 560, 146, 680, 520
local CHOOSE_Y = 396 -- a sala de arquivo só usa a faixa de baixo (as fichas); o alto é a mesa 3D
local pages: { [string]: Frame } = {
	squad = page(PANEL_X, PANEL_Y, PANEL_W, PANEL_H),
	role = page(PANEL_X, PANEL_Y, PANEL_W, PANEL_H),
	daily = page(PANEL_X, PANEL_Y, PANEL_W, PANEL_H),
	insert = page(40, PANEL_Y, 300, PANEL_H), -- estreito: a carta de spawn vai de x 356 a 1240
	choose = page(0, CHOOSE_Y, DESIGN_W, 300),
}

-- ===== transições: crossfade de pastas =====
-- Em repouso a pasta fica direto na raiz (texto nítido). Na troca ela vai para um CanvasGroup do
-- tamanho dela (com folga para a sombra), que esmaece: a que sai recua e some, a que entra desliza
-- e abre (escala 0,96 → 1). Só Position, escala e GroupTransparency: o motor faz o resto.
local MARGIN = 40
local pageBase: { [string]: UDim2 } = {}
local pageScale: { [string]: UIScale } = {}
local carrier: { [string]: CanvasGroup } = {}
local pageToken: { [string]: number } = {}
local pageShown: { [string]: boolean } = {}
for name, p in pages do
	pageBase[name] = p.Position
	local s = Instance.new("UIScale")
	s.Parent = p
	pageScale[name] = s
	local cg = Instance.new("CanvasGroup")
	cg.Name = "Troca_" .. name
	cg.BackgroundTransparency = 1
	cg.Size = p.Size + UDim2.fromOffset(2 * MARGIN, 2 * MARGIN)
	carrier[name] = cg
	pageToken[name] = 0
	pageShown[name] = false
end

local function pageShow(name: string, on: boolean, dx: number, dy: number)
	pageToken[name] += 1
	local my = pageToken[name]
	local p, cg, s, base = pages[name], carrier[name], pageScale[name], pageBase[name]
	-- a pasta (âncora no meio) fica no CanvasGroup com MARGIN de folga para a sombra
	local inner = UDim2.fromOffset(MARGIN + p.Size.X.Offset / 2, MARGIN + p.Size.Y.Offset / 2)
	local home = base - inner
	-- já no meio de uma troca (entrou e já vai sair, ou o contrário): continua de onde está
	local inFlight = p.Parent == cg and cg.Parent == root
	p.Parent = cg
	p.Position = inner
	cg.Parent = root
	if on then
		if not inFlight then
			cg.Position = home + UDim2.fromOffset(dx, dy)
			cg.GroupTransparency = 1
			s.Scale = 0.96
		end
		tw(cg, PAGE_IN, { Position = home, GroupTransparency = 0 })
		tw(s, PAGE_IN, { Scale = 1 }).Completed:Once(function()
			if pageToken[name] == my then
				p.Parent = root -- assentou: sai do CanvasGroup
				p.Position = base
				cg.Parent = nil
			end
		end)
	else
		if not inFlight then
			cg.Position = home
			cg.GroupTransparency = 0
		end
		tw(s, PAGE_OUT, { Scale = 0.97 })
		tw(cg, PAGE_OUT, { Position = home + UDim2.fromOffset(dx, dy), GroupTransparency = 1 }).Completed:Once(
			function()
				if pageToken[name] == my then
					p.Parent = nil
					p.Position = base
					s.Scale = 1
					cg.Parent = nil
				end
			end
		)
	end
end

-- lobby fechado: tudo sai na hora (a próxima abertura anima de novo)
local function pagesReset()
	for name, p in pages do
		pageToken[name] += 1
		pageShown[name] = false
		p.Parent = nil
		p.Position = pageBase[name]
		pageScale[name].Scale = 1
		carrier[name].Parent = nil
	end
end

-- ===== abas (os mesmos objetos da mesa) =====
-- A aba ativa fica em vermelho de carimbo e um filete de latão desliza até ela.
type Tab = { id: string, btn: TextButton, name: TextLabel, info: TextLabel, hot: boolean, look: string }
local TAB_DEFS: { { id: string, name: string, w: number } } = {
	{ id = "desk", name = "◄ MESA", w = 118 },
	{ id = "squad", name = "1 · SQUAD", w = 160 },
	{ id = "role", name = "2 · PAPEL", w = 160 },
	{ id = "insert", name = "3 · INSERÇÃO", w = 168 },
	{ id = "daily", name = "RECOMPENSA DIÁRIA", w = 226 },
	{ id = "shop", name = "INTENDÊNCIA", w = 160 },
	{ id = "faction", name = "TROCAR DE LADO", w = 160 },
}
local CYCLE = { "squad", "role", "insert", "daily", "shop" }
local tabsFrame = Instance.new("Frame")
tabsFrame.BackgroundTransparency = 1
tabsFrame.Position = UDim2.fromOffset(40, 84)
tabsFrame.Size = UDim2.fromOffset(1200, 52)
tabsFrame.Parent = root
local tabs: { [string]: Tab } = {}
local tabMark = box(tabsFrame, BRASS, 0, 50, 118, 3)
tabMark.Name = "Indicador"
tabMark.ZIndex = 3
corner(tabMark, 1)

local function tabStyle(t: Tab)
	local active = t.id == panel
	local look = (if active then "a" else "-") .. (if t.hot then "h" else "-")
	if look == t.look then
		return
	end
	t.look = look
	local f = t.btn
	tw(f, QUICK, { BackgroundColor3 = if active then V.OLIVE elseif t.hot then V.PANEL_3 else V.PANEL })
	tw(t.name, QUICK, { TextColor3 = if active or t.hot then V.TEXT else V.DIM })
	tw(t.info, QUICK, { TextColor3 = if active then V.TEXT else V.MUTED })
	local sc = f:FindFirstChild("Escala")
	if sc then
		tw(sc, SOFT, { Scale = if t.hot then 1.04 else 1 })
	end
	if active then
		tw(tabMark, PAGE_IN, {
			Position = UDim2.fromOffset(f.Position.X.Offset + 6, 50),
			Size = UDim2.fromOffset(f.Size.X.Offset - 12, 3),
		})
	end
end

do
	local x = 0
	for _, d in TAB_DEFS do
		local b = cardButton(tabsFrame, d.w, 50, V.PANEL)
		b.Position = UDim2.fromOffset(x, 0)
		b.BackgroundTransparency = 0.08
		corner(b, 3)
		stroke(b, V.LINE, 1, 0.5)
		local n = txt(b, HEAD, 17, V.DIM, 8, 3, d.w - 16, 26, Enum.TextXAlignment.Center)
		n.FontFace = HEAD_B
		n.TextWrapped = false
		n.TextTruncate = Enum.TextTruncate.AtEnd
		n.Text = d.name
		local i = txt(b, TYPE, 13, V.MUTED, 6, 27, d.w - 12, 20, Enum.TextXAlignment.Center)
		i.TextWrapped = false
		i.TextTruncate = Enum.TextTruncate.AtEnd
		local t: Tab = { id = d.id, btn = b, name = n, info = i, hot = false, look = "" }
		tabs[d.id] = t
		bindCard(b, function()
			if d.id == "desk" then
				DeployScreen.back()
			else
				DeployScreen.open(d.id)
			end
		end, function(on: boolean)
			t.hot = on
			tabStyle(t)
		end)
		x += d.w + 8
	end
end

-- ===== sala de arquivo: fichas de alistamento =====
type FCard = {
	btn: TextButton,
	count: TextLabel,
	avail: TextLabel,
	cta: Frame,
	ctaText: TextLabel,
	hot: boolean,
	realce: UiKit.Realce,
	shadow: ImageLabel,
	look: boolean?,
}
local fcards: { [string]: FCard } = {}

local function chooseFaction(f: string)
	if myFaction() == f then
		browsing = false -- o mesmo lado: só volta à mesa
		DeployScreen.changed()
		return
	end
	local why = joinBlocked(f)
	if why then
		-- frase inteira por motivo: o dicionário de idiomas traduz a frase, não os pedaços
		notify(
			if why == "LOTADO"
				then "Este lado está lotado: o servidor deve recusar."
				else "Este lado está em excesso: o servidor deve recusar."
		)
	end
	Net.event("Team_Choose"):FireServer(f)
end

-- cartão sob o ponteiro (ou o dossiê na mesa): cresce um pouco e a faixa de baixo vira oliva
local function fcardStyle(f: string)
	local c = fcards[f]
	local on = c.hot or hoverFaction == f
	if c.look == on then
		return
	end
	c.look = on
	c.realce.set(on)
	tw(c.cta, QUICK, { BackgroundColor3 = if on then V.OLIVE else V.PANEL_3 })
	tw(c.shadow, SOFT, { ImageTransparency = if on then 0.3 else 0.45 })
end

-- Cartão de lado (estilo novo): faixa da cor do lado, o nome grande, uma linha da unidade e o
-- número de jogadores grande; a vaga numa etiqueta e a ação na faixa de baixo. Pouco texto.
local FCARD_Y = 48
local FCARD_CY = FCARD_Y + 108 -- centro do cartão (a âncora fica no meio: o realce cresce por igual)
local function factionCard(f: string, x: number): FCard
	local info = FACTION[f]
	local b = cardButton(pages.choose, 560, 216, MANILA)
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromOffset(x + 280, FCARD_CY)
	b.BackgroundTransparency = 0.1
	corner(b, 3)
	stroke(b, V.KHAKI, 1, 0.72)
	local shadow = Acabamento.sombra(b, 18, Vector2.new(0, 8), 0.55)
	box(b, sideColor(f), 0, 0, 6, 172) -- cor fixa do lado: EUA azul, VC vermelho
	local k = txt(b, HEAD, 15, sideColor(f), 26, 12, 360, 20)
	k.FontFace = F.TITLE_MED
	k.Text = info.stamp
	if f == "VC" then
		k.Font = VIET
	end
	local t = txt(b, HEAD, 30, V.TEXT, 26, 32, 516, 40)
	t.FontFace = HEAD_B
	t.TextWrapped = false
	t.TextScaled = true
	do
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = 30
		lim.Parent = t
	end
	t.Text = info.title
	local u = txt(b, TYPE, 15, V.DIM, 26, 74, 516, 20)
	u.TextTruncate = Enum.TextTruncate.AtEnd
	u.Text = info.unit
	local pk = txt(b, HEAD, 13, V.DIM, 26, 104, 200, 16)
	pk.FontFace = F.TITLE_REG
	pk.Text = "JOGADORES"
	local count = txt(b, HEAD, 40, V.TEXT, 26, 118, 220, 46)
	count.FontFace = HEAD_B
	count.TextWrapped = false
	local avail = stamp(b, 15, 400, 126, 140, 28, 0)
	local cta = box(b, V.PANEL_3, 0, 172, 560, 44)
	local ctaText = txt(cta, HEAD, 22, V.TEXT, 0, 0, 560, 44, Enum.TextXAlignment.Center)
	ctaText.FontFace = HEAD_B
	local c: FCard = {
		btn = b,
		count = count,
		avail = avail,
		cta = cta,
		ctaText = ctaText,
		hot = false,
		realce = UiKit.realce(b, MANILA, V.PANEL_2, 1.025),
		shadow = shadow,
		look = nil,
	}
	bindCard(b, function()
		chooseFaction(f)
	end, function(on: boolean)
		c.hot = on
		fcardStyle(f)
		LobbyScene.setExternalHover(if on then "pick_" .. f else nil)
	end)
	return c
end
fcards.US = factionCard("US", 40)
fcards.VC = factionCard("VC", 680)
-- D-93: a dica ficava no meio da tela, por cima dos dossiês da mesa (Studio); agora vai na faixa
-- das abas (livre na sala de arquivo: as abas só aparecem depois do lado escolhido)
local chooseHint = txt(root, HEAD, 30, V.TEXT, 40, 88, 1200, 40, Enum.TextXAlignment.Center)
chooseHint.FontFace = HEAD_B
chooseHint.Text = "ESCOLHA O SEU LADO"
chooseHint.TextTruncate = Enum.TextTruncate.AtEnd
chooseHint.Visible = false

-- as duas fichas sobem para a mesa, uma depois da outra, e o carimbo de vaga cai
local function dealChoose()
	for i, f in { "US", "VC" } do
		local c = fcards[f]
		local d = 0.12 + (i - 1) * 0.09
		local x = c.btn.Position.X.Offset
		c.btn.Position = UDim2.fromOffset(x, FCARD_CY + 36)
		tw(c.btn, after(d, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)), {
			Position = UDim2.fromOffset(x, FCARD_CY),
		})
		if c.avail.Visible then
			thump(c.avail, d + 0.3)
		end
	end
	chooseHint.TextTransparency = 1
	tw(chooseHint, after(0.1, SOFT), { TextTransparency = 0 })
end

local function renderChoose()
	local us, vc = counts()
	local mine = myFaction()
	for f, c in fcards do
		-- jogadores (os bots não contam no equilíbrio do TeamService)
		c.count.Text = string.format("%d/%d", if f == "US" then us else vc, Roles.TEAM_MAX)
		local why = joinBlocked(f)
		if mine == f then
			stampSet(c.avail, "SEU LADO", OLIVE_INK)
			c.ctaText.Text = "VOLTAR À MESA ►"
		elseif why then
			stampSet(c.avail, why, STAMP)
			c.ctaText.Text = "ALISTAR-SE ►"
		else
			stampSet(c.avail, "ABERTO", OLIVE_INK)
			c.ctaText.Text = "ALISTAR-SE ►"
		end
		fcardStyle(f)
	end
end

-- ===== papel: ficha do soldado (embaixo, à esquerda, sobre a cena) =====
-- Mostra o que muda ao escolher: as armas do papel (as que trocam marcadas com ►) e, da arma
-- principal, cano (V0), cadência, carregador e peso em barras que deslizam até o valor; o traço
-- vermelho em cada barra é a arma do papel atual. Valores do Shared/Weapons (as fontes estão lá).
-- Na TV o texto não fica abaixo de 24 px na tela: a ficha cresce (mais larga e mais alta, subindo
-- a partir do rodapé) para as linhas caberem.
local capHolder = Instance.new("CanvasGroup") -- entra e sai esmaecendo (pequeno: 548 x 188)
local capShown = ""
local capToken = 0
local capOn = false
local caption: (f: string, roleId: string?, extra: string?) -> ()
local capShow: (on: boolean) -> ()
do
	local TV = UiKit.tv()
	local CAP_W, CAP_H, CAP_M = if TV then 600 else 500, if TV then 210 else 140, 24
	local CAP_Y = 660 - CAP_H
	local CAP_TEXT_W = if TV then 272 else 236 -- coluna das armas
	local STAT_LW = if TV then 112 else 84 -- rótulo da barra ("CARREGADOR" não cabia em 74)
	local STAT_VW = if TV then 66 else 52 -- valor da barra
	local STAT_DY = if TV then 36 else 21 -- entre as barras
	capHolder.Name = "FichaPapel"
	capHolder.BackgroundTransparency = 1
	capHolder.Position = UDim2.fromOffset(40 - CAP_M, CAP_Y - CAP_M)
	capHolder.Size = UDim2.fromOffset(CAP_W + 2 * CAP_M, CAP_H + 2 * CAP_M)
	capHolder.GroupTransparency = 1
	capHolder.Visible = false
	capHolder.Parent = root
	local capCard = box(capHolder, V.PANEL, CAP_M, CAP_M, CAP_W, CAP_H, 0.06)
	capCard.Active = true
	capCard.ZIndex = 2
	corner(capCard, 4)
	stroke(capCard, V.LINE, 1, 0.45)
	Acabamento.sombra(capCard, 16, Vector2.new(0, 6), 0.55).ZIndex = 1
	local capSeal, capGlyph = seal(capCard, 12, 8, 32, "×")
	local capTitle = txt(capCard, HEAD, 22, INK, 52, 6, CAP_W - 180, 32)
	capTitle.FontFace = HEAD_B
	capTitle.TextYAlignment = Enum.TextYAlignment.Center
	capTitle.TextTruncate = Enum.TextTruncate.AtEnd
	local capMark = stamp(capCard, 14, CAP_W - 112, 10, 100, 24, 0)
	capMark.Visible = false
	hline(capCard, UiKit.RULE_RED, 12, 44, CAP_W - 24)
	local capLines = txt(capCard, TYPE, 14, INK, 12, 50, CAP_TEXT_W, CAP_H - 54)
	capLines.TextYAlignment = Enum.TextYAlignment.Top
	capLines.RichText = true
	-- nome de arma longo passava da coluna e corria por cima das barras (Studio, D-93): quebra
	-- dentro da coluna e o que não couber termina em "…"
	capLines.TextWrapped = true
	capLines.TextTruncate = Enum.TextTruncate.AtEnd
	capLines.ClipsDescendants = true

	-- maiores valores entre as armas ligadas: a barra cheia é a melhor arma do jogo naquele número
	type Stat = { key: string, label: string, unit: string, max: number, more: boolean }
	local STATS: { Stat } = {
		{ key = "muzzleVelocity", label = "V0", unit = " m/s", max = 1, more = true },
		{ key = "rpm", label = "CADÊNCIA", unit = "/min", max = 1, more = true },
		{ key = "magazine", label = "CARREGADOR", unit = "", max = 1, more = true },
		{ key = "massLoadedKg", label = "PESO", unit = " kg", max = 1, more = false },
	}
	for _, w in Weapons.list do
		if w.enabled then
			for _, s in STATS do
				s.max = math.max(s.max, (w :: any)[s.key] :: number)
			end
		end
	end
	type StatRow = { fill: Frame, ghost: Frame, value: TextLabel }
	local statRows: { StatRow } = {}
	do
		local lx = 12 + CAP_TEXT_W + 10 -- rótulo
		local bx = lx + STAT_LW + 2 -- barra
		local vx = CAP_W - 12 - STAT_VW -- valor
		local bw = vx - 4 - bx
		local rowH = if TV then 30 else 18
		for i, s in STATS do
			local y = 50 + (i - 1) * STAT_DY
			local l = txt(capCard, HEAD, 12, V.DIM, lx, y, STAT_LW, rowH)
			l.FontFace = F.TITLE_REG
			l.Text = s.label
			l.TextYAlignment = Enum.TextYAlignment.Center
			l.TextWrapped = false -- uma linha só; o que passar termina em "…" (não invade a barra)
			l.TextTruncate = Enum.TextTruncate.AtEnd
			local back = box(capCard, INK, bx, y + math.floor(rowH / 2) - 3, bw, 6, 0.84)
			corner(back, 2)
			local fill = box(back, INK, 0, 0, 0, 6, 0.1)
			fill.Size = UDim2.fromScale(0, 1)
			corner(fill, 2)
			local ghost = box(back, STAMP, 0, -3, 2, 12)
			ghost.AnchorPoint = Vector2.new(0.5, 0)
			ghost.Visible = false
			local v = txt(capCard, HEAD, 13, INK, vx, y, STAT_VW, rowH, Enum.TextXAlignment.Right)
			v.FontFace = HEAD_B
			v.TextYAlignment = Enum.TextYAlignment.Center
			statRows[i] = { fill = fill, ghost = ghost, value = v }
		end
	end

	local function statText(s: Stat, x: number): string
		if s.key == "massLoadedKg" then
			return string.format("%.1f", x):gsub("%.", ",") .. s.unit
		end
		return tostring(math.floor(x + 0.5)) .. s.unit
	end

	function caption(f: string, roleId: string?, extra: string?)
		local rid = roleId or "rifleman"
		local key = f .. "|" .. rid .. "|" .. (extra or "") .. "|" .. tostring(player:GetAttribute("Role"))
		if key == capShown then
			return -- o mesmo papel: nada a animar (render chama a cada mudança de estado)
		end
		capShown = key
		local r = Roles.roles[rid]
		local lo = Roles.loadout[f][rid]
		local cur = player:GetAttribute("Role")
		local curLo = if type(cur) == "string" then Roles.loadout[f][cur] else nil
		local isCurrent = cur == rid
		-- cabeçalho: selo com o glifo do papel e o título datilografado
		capGlyph.Text = ROLE_GLYPH[rid] or "•"
		capGlyph.TextColor3 = if rid == "medic" then V.RED_HI else V.KHAKI
		local pop = capSeal:FindFirstChild("Pop") :: UIScale?
		if pop then
			pop.Scale = 1.3
			tw(pop, SOFT, { Scale = 1 })
		end
		reveal(capTitle, UiKit.upper(if r then r.name else rid))
		if isCurrent then
			stampSet(capMark, "ATUAL", OLIVE_INK)
		elseif curLo then
			stampSet(capMark, "TROCA", STAMP) -- escolher este papel troca o equipamento
		else
			stampSet(capMark, nil)
		end
		-- armas: as que não estão no papel atual vão marcadas (o viet vem antes da marca: o padrão dele
		-- não pode ver as tags)
		local lines = {}
		if lo then
			for _, id in lo do
				local w = Weapons.get(id)
				local line = Acabamento.viet(if w then string.format("%s · %s", w.name, w.cartridge) else id)
				local new = curLo ~= nil and not isCurrent and not table.find(curLo, id)
				table.insert(lines, if new then '<font color="#CEBE8E" face="Arimo">►</font> ' .. line else line)
			end
		end
		if extra then
			table.insert(lines, Acabamento.viet(extra))
		end
		reveal(capLines, table.concat(lines, "\n"), 0.05)
		-- barras da arma principal (e o traço da arma do papel atual)
		local w = if lo then Weapons.get(lo[1]) else nil
		local cw = if curLo and not isCurrent then Weapons.get(curLo[1]) else nil
		for i, s in STATS do
			local row = statRows[i]
			local x = if w then (w :: any)[s.key] :: number else 0
			local k = math.clamp(x / s.max, 0, 1)
			local better = cw and (if s.more then x > (cw :: any)[s.key] else x < (cw :: any)[s.key])
			local worse = cw and (if s.more then x < (cw :: any)[s.key] else x > (cw :: any)[s.key])
			tw(row.fill, after((i - 1) * 0.04, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)), {
				Size = UDim2.fromScale(k, 1),
				BackgroundColor3 = if better then V.OLIVE_HI elseif worse then V.RED_HI else INK,
			})
			row.value.Text = if w then statText(s, x) else "—"
			row.ghost.Visible = cw ~= nil
			if cw then
				tw(row.ghost, SOFT, {
					Position = UDim2.fromScale(math.clamp(((cw :: any)[s.key] :: number) / s.max, 0, 1), 0),
				})
			end
		end
	end

	function capShow(on: boolean)
		if on == capOn then
			return
		end
		capOn = on
		capToken += 1
		local my = capToken
		local home = UDim2.fromOffset(40 - CAP_M, CAP_Y - CAP_M)
		if on then
			capHolder.Visible = true
			capHolder.Position = home - UDim2.fromOffset(36, 0)
			capHolder.GroupTransparency = 1
			tw(capHolder, PAGE_IN, { Position = home, GroupTransparency = 0 })
		else
			tw(capHolder, PAGE_OUT, { Position = home - UDim2.fromOffset(24, 0), GroupTransparency = 1 }).Completed:Once(
				function()
					if capToken == my then
						capHolder.Visible = false
					end
				end
			)
		end
	end
end
-- ===== squad =====
type SCard = {
	btn: TextButton,
	top: TextLabel,
	mid: TextLabel,
	bottom: TextLabel,
	base: Color3,
	hot: boolean,
	action: (() -> ())?,
	realce: UiKit.Realce,
}
type Row = {
	frame: Frame,
	label: Frame,
	glyph: TextLabel,
	name: TextLabel,
	detail: TextLabel,
	holder: Frame,
	newCard: SCard,
}

local dealSquad: () -> ()
local renderSquad: (f: string, st: any) -> { GuiObject }
do
	local sFolder, sInfo = folder(pages.squad, "SQUAD", PANEL_W, PANEL_H)
	local sScroll = scroller(sFolder, 16, 56, PANEL_W - 32, PANEL_H - 116)
	local sList = Instance.new("UIListLayout")
	sList.Padding = UDim.new(0, 10)
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.Parent = sScroll
	local sPad = Instance.new("UIPadding") -- folga para o cartão crescer no realce sem cortar
	sPad.PaddingLeft = UDim.new(0, 4)
	sPad.PaddingTop = UDim.new(0, 4)
	sPad.PaddingBottom = UDim.new(0, 10)
	sPad.Parent = sScroll
	local leaveBtn = darkButton(sFolder, "SAIR DO SQUAD", PANEL_W - 236, PANEL_H - 52, 220, 38)
	bindDark(leaveBtn, function()
		Net.event("Squad_Action"):FireServer({ op = "leave" })
	end)
	local squadHint = txt(sFolder, TYPE, 14, V.DIM, 16, PANEL_H - 50, PANEL_W - 270, 36)

	local function squadCard(parent: Instance, isNew: boolean): SCard
		local base = if isNew then NEW_CARD else CARD
		local b = cardButton(parent, 104, 92, base)
		corner(b, 3)
		stroke(b, if isNew then V.OLIVE else V.LINE, 1, if isNew then 0.2 else 0.5)
		local top = txt(b, HEAD, 18, INK, 7, 2, 90, 26)
		top.FontFace = HEAD_B
		-- D-91: 7 squads nos EUA e 8 no VC ("Tiểu đội 8"): o nome encolhe para caber, nunca corta
		top.TextScaled = true
		do
			local lim = Instance.new("UITextSizeConstraint")
			lim.MaxTextSize = 18
			lim.Parent = top
		end
		hline(b, UiKit.RULE_RED, 7, 29, 90)
		local mid = if isNew then txt(b, TYPE, 15, INK, 7, 34, 90, 30) else txt(b, HEAD, 30, INK, 7, 31, 90, 34)
		if not isNew then
			mid.FontFace = HEAD_B
		end
		local bottom = txt(b, HEAD, 14, V.DIM, 7, 66, 90, 22)
		bottom.FontFace = F.TITLE_MED
		local c: SCard = {
			btn = b,
			top = top,
			mid = mid,
			bottom = bottom,
			base = base,
			hot = false,
			action = nil,
			realce = UiKit.realce(b, base, CARD_HOT, 1.05),
		}
		bindCard(b, function()
			local fn = c.action
			if fn then
				fn()
			end
		end, function(on: boolean)
			c.hot = on
			b.ZIndex = if on then 3 else 1 -- o cartão que cresce fica por cima dos vizinhos
			c.realce.set(on)
		end)
		return c
	end

	local rows: { [string]: Row } = {}
	local squadCards: { [string]: SCard } = {}

	local function unitRow(): Row
		local fr = Instance.new("Frame")
		fr.BackgroundTransparency = 1
		fr.AutomaticSize = Enum.AutomaticSize.Y
		fr.Size = UDim2.fromOffset(PANEL_W - 44, 92)
		fr.Parent = sScroll
		local label = box(fr, V.PANEL, 0, 0, 170, 92, 0)
		corner(label, 3)
		entryParts(label, 3)
		local _, glyph = seal(label, 8, 4, 26, "×")
		local name = txt(label, HEAD, 19, INK, 40, 2, 124, 26)
		name.FontFace = HEAD_B
		name.TextWrapped = false
		name.TextScaled = true
		do
			local lim = Instance.new("UITextSizeConstraint")
			lim.MaxTextSize = 19
			lim.Parent = name
		end
		hline(label, UiKit.RULE_RED, 9, 33, 152)
		local detail = txt(label, TYPE, 13, V.DIM, 9, 38, 156, 52)
		detail.TextYAlignment = Enum.TextYAlignment.Top
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.fromOffset(178, 0)
		holder.Size = UDim2.fromOffset(PANEL_W - 44 - 178, 92)
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.Parent = fr
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(104, 92)
		grid.CellPadding = UDim2.fromOffset(8, 8)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = holder
		local nc = squadCard(holder, true)
		nc.btn.LayoutOrder = 99
		return { frame = fr, label = label, glyph = glyph, name = name, detail = detail, holder = holder, newCard = nc }
	end

	-- entrada da ficha de squad: rótulos e cartões pousando, linha por linha
	function dealSquad()
		local list: { GuiObject } = {}
		local ordered: { Row } = {}
		for _, r in rows do
			if r.frame.Visible then
				table.insert(ordered, r)
			end
		end
		table.sort(ordered, function(a: Row, b: Row): boolean
			return a.frame.LayoutOrder < b.frame.LayoutOrder
		end)
		for _, r in ordered do
			table.insert(list, r.label)
			local cards: { GuiObject } = {}
			for _, c in r.holder:GetChildren() do
				if c:IsA("GuiButton") then
					table.insert(cards, c)
				end
			end
			for _, c in byOrder(cards) do
				table.insert(list, c)
			end
		end
		deal(list, 0.12, 0.03)
	end

	-- Desenha a ficha de squad; devolve os cartões que acabaram de aparecer (squad novo formado por
	-- alguém, ou o estado do servidor chegando), para pousarem animados.
	function renderSquad(f: string, st: any): { GuiObject }
		local before: { [GuiObject]: boolean } = {}
		for _, r in rows do
			if r.frame.Visible then
				before[r.label] = true
				for _, c in r.holder:GetChildren() do
					if c:IsA("GuiButton") and c.Visible then
						before[c] = true
					end
				end
			end
		end
		local size: number? = if st and type(st.size) == "number" then st.size else nil
		local squads: { any } = if st and type(st.squads) == "table" then st.squads else {}
		local mySid = player:GetAttribute("SquadId")
		sInfo.Text = if size
			then string.format(
				"Jogadores %s %d/%d · pesados abrem com %d",
				FACTION[f].short,
				size,
				Roles.TEAM_MAX,
				Roles.HEAVY_UNLOCK
			)
			else "Recebendo os squads do servidor…"
		leaveBtn.Visible = type(mySid) == "string"
		squadHint.Text = if type(mySid) == "string"
			then "Trocar de squad tira o papel atual."
			else "Entre num squad com vaga ou forme um novo."
		for _, r in rows do
			r.frame.Visible = false
		end
		for _, c in squadCards do
			c.btn.Visible = false
		end
		for order, unit in UNITS_OF[f] do
			local def = Roles.units[f][unit]
			local key = f .. ":" .. unit
			local row = rows[key]
			if not row then
				row = unitRow()
				rows[key] = row
			end
			row.frame.Visible = true
			row.frame.LayoutOrder = order
			row.name.Text = UiKit.upper(UNIT_NAME[unit] or unit)
			row.glyph.Text = UNIT_GLYPH[unit] or "•"
			local locked = def.heavy and (size == nil or size < Roles.HEAVY_UNLOCK)
			local detail = if def.size == 1
				then "1 vaga"
				else string.format("Squads de %d · até %d", def.size, def.count)
			if def.heavy then
				detail ..= if locked
					then string.format(
						"\nAbre com %d no time%s",
						Roles.HEAVY_UNLOCK,
						if size then string.format(" (agora %d)", size) else ""
					)
					else "\nLiberado"
			end
			row.detail.Text = detail
			local used: { [string]: boolean } = {}
			for _, s in squads do
				if s.unit == unit and type(s.id) == "string" then
					used[s.name] = true
					local c = squadCards[s.id]
					if not c then
						c = squadCard(row.holder, false)
						squadCards[s.id] = c
					end
					local card = c :: SCard
					if card.btn.Parent ~= row.holder then
						card.btn.Parent = row.holder
					end
					local n = if type(s.members) == "table" then #s.members else 0
					local full = n >= def.size
					local mine = s.id == mySid
					card.btn.Visible = true
					card.btn.LayoutOrder = table.find(def.names, s.name) or 50
					card.top.Text = tostring(s.name)
					card.top.Font = if f == "VC" then VIET else HEAD
					card.mid.Text = string.format("%d/%d", n, def.size)
					card.bottom.Text = if mine then "SEU SQUAD" elseif full then "CHEIO" else "ENTRAR"
					card.base = if mine then NEW_CARD elseif full then CARD_OFF else CARD
					card.realce.base(card.base)
					local id = s.id
					card.action = function()
						if mine then
							DeployScreen.open("role") -- já é o seu: segue para o papel
							return
						end
						if full then
							notify("Squad cheio: o servidor deve recusar.")
						end
						Net.event("Squad_Action"):FireServer({ op = "join", id = id })
					end
				end
			end
			local nextName: string? = nil
			for _, nm in def.names do
				if not used[nm] then
					nextName = nm
					break
				end
			end
			local nc = row.newCard
			nc.btn.Visible = nextName ~= nil
			if nextName then
				nc.top.Text = "+ NOVO"
				nc.mid.Text = nextName
				nc.mid.Font = if f == "VC" then VIET else TYPE
				nc.bottom.Text = if locked then "TRANCADO" else "FORMAR"
				nc.base = if locked then CARD_OFF else NEW_CARD
				nc.realce.base(nc.base)
				nc.action = function()
					if locked then
						notify(string.format("Unidade pesada: abre com %d no time.", Roles.HEAVY_UNLOCK))
						return
					end
					Net.event("Squad_Action"):FireServer({ op = "create", unit = unit })
				end
			end
		end
		local fresh: { GuiObject } = {}
		for _, r in rows do
			if r.frame.Visible then
				if not before[r.label] then
					table.insert(fresh, r.label)
				end
				local cards: { GuiObject } = {}
				for _, c in r.holder:GetChildren() do
					if c:IsA("GuiButton") and c.Visible and not before[c] then
						table.insert(cards, c)
					end
				end
				for _, c in byOrder(cards) do
					table.insert(fresh, c)
				end
			end
		end
		return fresh
	end

	-- ===== papel =====
end
type RCard = {
	btn: TextButton,
	name: TextLabel,
	weapons: TextLabel,
	slots: TextLabel,
	mark: TextLabel,
	base: Color3,
	hot: boolean,
	blocked: string?,
	realce: UiKit.Realce,
}
local dealRoles: () -> ()
local findSquad: (st: any, sid: string) -> any
local unitOfSquad: (f: string, sid: string) -> string?
local renderRole: (f: string, st: any, sid: string) -> ()
do
	local rFolder, rInfo = folder(pages.role, "PAPEL", PANEL_W, PANEL_H)
	local rScroll = scroller(rFolder, 16, 56, PANEL_W - 32, PANEL_H - 72)
	local rGrid = Instance.new("UIGridLayout")
	rGrid.CellSize = UDim2.fromOffset(196, 150)
	rGrid.CellPadding = UDim2.fromOffset(10, 10)
	rGrid.SortOrder = Enum.SortOrder.LayoutOrder
	rGrid.Parent = rScroll
	local rPad = Instance.new("UIPadding") -- folga para o cartão crescer no realce sem cortar
	rPad.PaddingLeft = UDim.new(0, 4)
	rPad.PaddingTop = UDim.new(0, 4)
	rPad.PaddingBottom = UDim.new(0, 10)
	rPad.Parent = rScroll
	local roleCards: { [string]: RCard } = {}
	local roleTap = ToqueTelas.newTap2() -- toque: 1º toque mostra, 2º escolhe

	local function showRole(id: string?)
		local f = myFaction()
		if not f then
			return
		end
		previewRole = id
		local lo = if id then Roles.loadout[f][id] else nil
		LobbyScene.setLoadout(f, if lo then lo[1] else nil)
		local sid = player:GetAttribute("SquadId")
		local squadName = if type(sid) == "string" then string.match(sid, ":(.+)$") else nil
		caption(f, id, if squadName then string.format("Squad %s", squadName) else nil)
	end

	local function chooseRole(id: string)
		local c = roleCards[id]
		if id == currentRole() then
			DeployScreen.open(if alive() then "desk" else "insert") -- o mesmo papel: sem os +15 s
			return
		end
		if c and c.blocked then
			notify(
				if c.blocked == "SÓ O LÍDER"
					then "Papel só do líder do squad: o servidor deve recusar."
					else "Papel ocupado: o servidor deve recusar."
			)
		end
		Net.event("Role_Choose"):FireServer(id)
	end

	-- ficha de papel: selo com o glifo do papel, nome em negrito, armas datilografadas, vagas e o
	-- carimbo (ATUAL, OCUPADO, SÓ O LÍDER)
	local function roleCard(id: string): RCard
		local b = cardButton(rScroll, 196, 150, CARD)
		corner(b, 3)
		stroke(b, V.LINE, 1, 0.5)
		local _, glyph = seal(b, 10, 9, 32, ROLE_GLYPH[id] or "•")
		if id == "medic" then
			glyph.TextColor3 = V.RED_HI
		end
		local name = txt(b, HEAD, 19, INK, 50, 4, 138, 48)
		name.FontFace = HEAD_B
		name.TextYAlignment = Enum.TextYAlignment.Center
		hline(b, UiKit.RULE_RED, 10, 54, 176)
		local weapons = txt(b, TYPE, 14, V.DIM, 10, 60, 176, 52)
		weapons.TextYAlignment = Enum.TextYAlignment.Top
		weapons.TextTruncate = Enum.TextTruncate.AtEnd
		local slots = txt(b, HEAD, 15, V.TEXT, 100, 120, 86, 24, Enum.TextXAlignment.Right)
		slots.FontFace = F.TITLE_MED
		-- estado (ATUAL, OCUPADO, SÓ O LÍDER) numa etiqueta embaixo, sem cobrir as armas
		local mark = stamp(b, 13, 10, 121, 92, 22, 0)
		mark.Visible = false
		local c: RCard = {
			btn = b,
			name = name,
			weapons = weapons,
			slots = slots,
			mark = mark,
			base = CARD,
			hot = false,
			blocked = nil,
			realce = UiKit.realce(b, CARD, CARD_HOT, 1.04),
		}
		bindCard(b, function()
			-- toque (Parte 13): sem "passar o mouse", o 1º toque mostra o papel (armas, barras e o
			-- soldado) e o 2º no mesmo cartão escolhe; trocar custa +15 s, então nada de escolher sem ver
			if ToqueUi.active() and id ~= currentRole() and not ToqueTelas.secondTap(roleTap, id, os.clock()) then
				for oid, oc in roleCards do
					oc.hot = oid == id
					oc.btn.ZIndex = if oid == id then 3 else 1
					oc.realce.set(oid == id)
				end
				showRole(id)
				notify("Toque de novo no cartão para escolher este papel.")
				return
			end
			chooseRole(id)
		end, function(on: boolean)
			c.hot = on
			b.ZIndex = if on then 3 else 1
			c.realce.set(on)
			if on then
				showRole(id)
			end
		end)
		return c
	end

	function dealRoles()
		local list: { GuiObject } = {}
		for _, c in roleCards do
			table.insert(list, c.btn)
		end
		deal(byOrder(list), 0.12, 0.04)
	end

	function findSquad(st: any, sid: string): any
		if st and type(st.squads) == "table" then
			for _, s in st.squads do
				if s.id == sid then
					return s
				end
			end
		end
		return nil
	end

	-- unidade pelo nome do squad no id ("US:Alfa"), enquanto o Squad_State não chega
	function unitOfSquad(f: string, sid: string): string?
		local name = string.match(sid, ":(.+)$")
		if not name then
			return nil
		end
		for unit, def in Roles.units[f] do
			if table.find(def.names, name) then
				return unit
			end
		end
		return nil
	end

	function renderRole(f: string, st: any, sid: string)
		local sq = findSquad(st, sid)
		local unit: string? = if sq then sq.unit else unitOfSquad(f, sid)
		local def = if unit then Roles.units[f][unit] else nil
		local me = player.UserId
		-- lista "A · B · C": cada pedaço é uma frase ou um modelo inteiro (o Lang traduz item a item)
		local squadName = string.match(sid, ":(.+)$") or sid
		local infoParts = { string.format("Squad %s", squadName), if unit then UNIT_NAME[unit] or unit else "?" }
		if sq and def then
			table.insert(infoParts, string.format("%d de %d", #sq.members, def.size))
		end
		if sq and sq.leader then
			local lp = Players:GetPlayerByUserId(sq.leader)
			if sq.leader == me then
				table.insert(infoParts, "líder: você")
			elseif lp then
				table.insert(infoParts, string.format("líder: %s", lp.DisplayName))
			end
		end
		rInfo.Text = table.concat(infoParts, " · ")
		local cur = currentRole()
		local firstFree: string? = nil
		local firstId: string? = nil
		for order, id in ROLE_IDS do
			local r = Roles.roles[id]
			local lo = Roles.loadout[f][id]
			local show = unit ~= nil and r.unit == unit and lo ~= nil
			local c = roleCards[id]
			if show and not c then
				c = roleCard(id)
				roleCards[id] = c
			end
			if c then
				local card = c :: RCard
				card.btn.Visible = show
				if show then
					card.btn.LayoutOrder = order
					card.name.Text = UiKit.upper(r.name)
					card.weapons.Text = weaponNames(lo)
					local max = r.maxPerSquad
					local free: number? = nil
					if max then
						local taken = 0
						if sq and type(sq.roles) == "table" then
							for uid, rr in sq.roles do
								if rr == id and tostring(uid) ~= tostring(me) then
									taken += 1
								end
							end
						end
						free = max - taken
						card.slots.Text = if sq
							then string.format("VAGA %d/%d", math.max(free or 0, 0), max)
							else string.format("VAGA ?/%d", max)
					else
						card.slots.Text = "LIVRE"
					end
					local blocked: string? = nil
					if id == "squad_leader" and sq and sq.leader ~= me then
						blocked = "SÓ O LÍDER"
					elseif free ~= nil and sq and free <= 0 then
						blocked = "OCUPADO"
					end
					card.blocked = blocked
					local current = cur == id
					if current then
						stampSet(card.mark, "ATUAL", OLIVE_INK)
					elseif blocked then
						stampSet(card.mark, blocked, STAMP)
					else
						stampSet(card.mark, nil)
					end
					card.base = if blocked then CARD_OFF else CARD
					card.realce.base(card.base)
					if not firstId then
						firstId = id
					end
					if not blocked and not firstFree then
						firstFree = id
					end
				end
			end
		end
		-- soldado e legenda: o papel sob o ponteiro; ao entrar, o atual ou o primeiro livre
		if not (previewRole and roleCards[previewRole] and roleCards[previewRole].btn.Visible) then
			previewRole = if cur and roleCards[cur] and roleCards[cur].btn.Visible then cur else (firstFree or firstId)
		end
		showRole(previewRole)
	end
end

-- ===== inserção (o mapa do GameUI fica à direita) =====
local portrait = SoldierPreview.new(0.24, -0.45)
local iLines: TextLabel
local loadoutNow: (f: string) -> { string }?
local renderInsert: (f: string) -> ()
local dealInsert: () -> ()
-- Painel estreito à esquerda (contrato com a carta: x 40, w 300; o mapa ocupa x 356..1240): o
-- soldado, o papel em letra grande, o squad e as armas em duas linhas, e o que fazer.
do
	local INSERT_W = 300
	local iFolder, iInfo = folder(pages.insert, "INSERÇÃO", INSERT_W, PANEL_H)
	iInfo.FontFace = F.TITLE_MED
	iInfo.TextColor3 = V.TEXT
	local iPhoto = box(iFolder, V.BG, 16, 54, INSERT_W - 32, 226)
	corner(iPhoto, 3)
	stroke(iPhoto, V.LINE, 1, 0.5)
	local iSlot = box(iPhoto, V.BG, 0, 0, INSERT_W - 32, 226)
	iSlot.BackgroundTransparency = 1
	local iCaption = txt(iFolder, HEAD, 26, V.TEXT, 16, 288, INSERT_W - 32, 34)
	iCaption.FontFace = HEAD_B
	iCaption.TextWrapped = false
	iCaption.TextTruncate = Enum.TextTruncate.AtEnd
	local rows: { TextLabel } = {}
	for i, k in { "SQUAD", "ARMAS" } do
		local y = 328 + (i - 1) * 50
		local kl = txt(iFolder, HEAD, 13, V.DIM, 16, y, INSERT_W - 32, 16)
		kl.FontFace = F.TITLE_REG
		kl.Text = k
		local vl = txt(iFolder, TYPE, 16, V.TEXT, 16, y + 16, INSERT_W - 32, 30)
		vl.TextWrapped = false
		vl.TextTruncate = Enum.TextTruncate.AtEnd
		rows[i] = vl
	end
	iLines = txt(iFolder, TYPE, 14, V.DIM, 16, 436, INSERT_W - 32, 72)
	iLines.TextYAlignment = Enum.TextYAlignment.Top
	iLines.RichText = true
	local portraitFrame = portrait.frame :: Frame
	portraitFrame.Parent = iSlot
	reg(portrait.note :: TextLabel, 16)

	function loadoutNow(f: string): { string }?
		local loAttr = player:GetAttribute("Loadout")
		if type(loAttr) == "string" and loAttr ~= "" then
			return string.split(loAttr, ",")
		end
		return Roles.loadout[f][currentRole() or "rifleman"]
	end

	function renderInsert(f: string)
		local rid = currentRole() or "rifleman"
		local r = Roles.roles[rid]
		local lo = loadoutNow(f)
		SoldierPreview.set(portrait, f, if lo then lo[1] else nil)
		local sid = player:GetAttribute("SquadId")
		local squadName = if type(sid) == "string" then (string.match(sid, ":(.+)$") or sid) else "—"
		local unit = if type(sid) == "string" then unitOfSquad(f, sid) else nil
		iInfo.Text = FACTION[f].short
		iInfo.TextColor3 = sideColor(f)
		iCaption.Text = UiKit.upper(if r then r.name else rid)
		-- lista "A · B": cada pedaço é traduzido sozinho (o Lang traduz item a item)
		rows[1].Text =
			Acabamento.viet(if unit then string.format("%s · %s", squadName, UNIT_NAME[unit] or unit) else squadName)
		rows[2].Text = Acabamento.viet(weaponNames(lo))
		local _, padText = Input.glyph("map_role", "map")
		reveal(
			iLines,
			table.concat({
				"Escolha na carta um ponto PRONTO.",
				-- toque: não há tecla (o botão PAPEL fica na carta)
				if ToqueUi.active()
					then "Trocar de papel: aba PAPEL (+15 s)"
					else string.format("Trocar de papel: aba PAPEL ou %s (+15 s)", keyName(padText)),
			}, "\n")
		)
	end

	-- entrada do painel de inserção: o retrato sobe um pouco e a imagem aparece
	function dealInsert()
		local p0 = UDim2.fromOffset(16, 54)
		iPhoto.Position = p0 + UDim2.fromOffset(0, 12)
		tw(iPhoto, after(0.08, SOFT), { Position = p0 })
		local vp = portrait.vp
		if vp then
			vp.ImageTransparency = 1
			tw(vp, after(0.15, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)), {
				ImageTransparency = 0,
			})
		end
	end
end

-- ===== recompensa diária: a caderneta de serviço =====
local dealDaily: () -> ()
local dailySummary: () -> (string, string)
local renderDaily: (f: string) -> ()
do
	type DCell = { frame: Frame, day: TextLabel, date: TextLabel, reward: TextLabel, mark: TextLabel }
	-- Studio (D-93): a ficha sobrava embaixo, a regra ocupava três linhas e o "HOJE" era miúdo.
	-- Agora a regra é uma linha, a ficha é do tamanho do conteúdo e o carimbo do dia é maior.
	-- Estilo novo: a sequência e o total em números grandes, a regra numa linha, os sete dias em
	-- cartões com o número do dia grande e o estado numa etiqueta; o botão cheio de oliva.
	local DAILY_H = 470
	local dFolder, dInfo = folder(pages.daily, "RECOMPENSA DIÁRIA", PANEL_W, DAILY_H)
	local dRun: TextLabel, dTotal: TextLabel
	do
		local nums: { TextLabel } = {}
		for i, k in { "SEQUÊNCIA", "SELOS" } do
			local x = 18 + (i - 1) * 170
			local kl = txt(dFolder, HEAD, 13, V.DIM, x, 54, 140, 16)
			kl.FontFace = F.TITLE_REG
			kl.Text = k
			local n = txt(dFolder, HEAD, 40, V.TEXT, x, 68, 140, 44)
			n.FontFace = HEAD_B
			n.TextWrapped = false
			nums[i] = n
			if i == 1 then
				local sl = box(dFolder, V.LINE, x + 150, 60, 3, 48)
				sl.Rotation = 18
			end
		end
		dRun, dTotal = nums[1], nums[2]
	end
	local dRule = txt(dFolder, TYPE, 14, V.DIM, 16, 112, PANEL_W - 32, 20)
	dRule.TextWrapped = false
	dRule.TextTruncate = Enum.TextTruncate.AtEnd
	dRule.Text = "Um selo por dia (UTC). Pulou um dia, volta ao dia 1. Dias 3 e 7: item único."
	local cells: { DCell } = {}
	for i = 1, Commerce.TRACK_DAYS do
		local x = 14 + (i - 1) * 94
		local fr = box(dFolder, CARD, x, 138, 88, 176)
		corner(fr, 3)
		stroke(fr, V.LINE, 1, 0.5)
		entryParts(fr, 3)
		local dk = txt(fr, HEAD, 12, V.DIM, 4, 6, 80, 14, Enum.TextXAlignment.Center)
		dk.FontFace = F.TITLE_REG
		dk.Text = "DIA"
		local d = txt(fr, HEAD, 30, INK, 4, 18, 80, 34, Enum.TextXAlignment.Center)
		d.FontFace = HEAD_B
		d.TextWrapped = false
		local dt = txt(fr, TYPE, 12, V.DIM, 4, 52, 80, 16, Enum.TextXAlignment.Center)
		hline(fr, UiKit.RULE_RED, 8, 72, 72)
		local rw = txt(fr, TYPE, 12, V.DIM, 5, 78, 78, 62)
		rw.TextYAlignment = Enum.TextYAlignment.Top
		rw.TextXAlignment = Enum.TextXAlignment.Center
		rw.TextTruncate = Enum.TextTruncate.AtEnd
		local mk = stamp(fr, 13, 4, 146, 80, 24, 0)
		mk.Visible = false
		cells[i] = { frame = fr, day = d, date = dt, reward = rw, mark = mk }
	end
	local claimBtn = Instance.new("TextButton")
	claimBtn.Position = UDim2.fromOffset(14, 324)
	claimBtn.Size = UDim2.fromOffset(PANEL_W - 28, 56)
	claimBtn.BackgroundColor3 = V.OLIVE
	claimBtn.TextColor3 = V.TEXT
	claimBtn.FontFace = HEAD_B
	claimBtn.AutoButtonColor = false
	claimBtn.Selectable = true
	claimBtn.SelectionImageObject = UiKit.FOCUS
	claimBtn.Parent = dFolder
	reg(claimBtn, 24)
	corner(claimBtn, 4)
	local claimLook = UiKit.realce(claimBtn, V.OLIVE, nil, 1.02)

	-- entrada da caderneta: os sete dias pousam em fila
	function dealDaily()
		local list: { GuiObject } = {}
		for _, c in cells do
			table.insert(list, c.frame)
		end
		deal(list, 0.12, 0.05)
	end
	local dResult = txt(dFolder, TYPE, 15, INK, 16, 388, PANEL_W - 32, 44)
	dResult.TextYAlignment = Enum.TextYAlignment.Top
	local dNote = txt(dFolder, TYPE, 13, V.RED_HI, 16, 434, PANEL_W - 32, 30)
	dNote.TextYAlignment = Enum.TextYAlignment.Top

	local REASON: { [string]: string } = {
		already = "Este dia já foi carimbado.",
		clock = "Aguarde a virada do dia (UTC).",
		loading = "Seu perfil ainda está carregando: tente de novo em instantes.",
		readonly = "Seu perfil não carregou neste servidor: o selo não pode ser gravado agora (nada foi perdido).",
		error = "O registro falhou: tente de novo.",
	}

	local function claim()
		if dailyBusy or not (daily and daily.ready and daily.canClaim) then
			return
		end
		dailyBusy = true
		Net.event("Daily_Claim"):FireServer()
		DeployScreen.changed()
		task.delay(15, function() -- sem resposta: libera o botão (o servidor continua sendo a fonte)
			if dailyBusy then
				dailyBusy = false
				fetchDaily()
			end
		end)
	end
	bindCard(claimBtn, claim, claimLook.set)

	function dailySummary(): (string, string)
		-- texto curto para a aba e para o calendário da mesa
		if not (daily and daily.ready) then
			return "…", ""
		elseif daily.canClaim then
			return "★ disponível", "★ RESGATAR"
		elseif daily.claimedToday then
			local left = dailyLeft()
			return string.format("volta em %s", string.sub(hms(left), 1, 5)), "CARIMBADO ✓"
		end
		return "aguarde", ""
	end

	function renderDaily(f: string)
		local d = daily
		if not (d and d.ready) then
			dInfo.Text = "Lendo a caderneta…"
			dRun.Text, dTotal.Text = "—", "—"
			claimBtn.Text = "CARREGANDO A CADERNETA…"
			claimLook.base(DRAB)
			claimBtn.TextColor3 = V.DIM
			for _, c in cells do
				c.mark.Visible = false
			end
			fetchDaily()
			return
		end
		local day: number = d.day or 1
		local run: number = d.run or 0
		dInfo.Text = ""
		dRun.Text = tostring(run)
		dTotal.Text = tostring(d.total or 0)
		local earned: { [string]: boolean } = if type(d.earned) == "table" then d.earned else {}
		local tomorrow = day % Commerce.TRACK_DAYS + 1
		for i, c in cells do
			local entry = Commerce.DailyTrack[i]
			c.day.Text = tostring(i)
			c.date.Text = entry.date
			local items = entry.items
			local mine = items and items[f]
			if mine then
				c.reward.Text = "Selo +\n"
					.. itemName(mine)
					.. (if earned[mine] then "\n✔ já é seu" else "\n(e o do outro lado)")
			else
				c.reward.Text = "Selo de\nserviço"
			end
			local done = if d.claimedToday then i <= day else (d.canClaim and i < day)
			local today = i == day
			local markText, markColor = "", STAMP
			if today and d.claimedToday then
				markText, markColor = "CARIMBADO", OLIVE_INK
			elseif today and d.canClaim then
				markText, markColor = "HOJE", STAMP
			elseif done then
				markText, markColor = "RECEBIDO", OLIVE_INK
			elseif d.claimedToday and i == tomorrow then
				markText, markColor = "AMANHÃ", INK
			end
			-- a etiqueta nova (o resgate de hoje) aparece; a que já estava fica parada
			stampSet(c.mark, if markText ~= "" then markText else nil, markColor)
			c.frame.BackgroundColor3 = if today then CARD_HOT elseif done then NEW_CARD else CARD
			local s = c.frame:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = if today then V.OLIVE_HI else V.LINE
				s.Thickness = if today then 2 else 1
				s.Transparency = if today then 0 else 0.5
			end
		end
		if dailyBusy then
			claimBtn.Text = "REGISTRANDO O SELO…"
			claimLook.base(DRAB)
			claimBtn.TextColor3 = V.DIM
		elseif d.canClaim then
			claimBtn.Text = string.format("CARIMBAR O DIA %d · RESGATAR", day)
			claimLook.base(V.OLIVE)
			claimBtn.TextColor3 = V.TEXT
		elseif d.claimedToday then
			claimBtn.Text = string.format("CARIMBADO HOJE · próximo selo em %s (UTC)", hms(dailyLeft()))
			claimLook.base(DRAB)
			claimBtn.TextColor3 = V.DIM
		else
			claimBtn.Text = "AGUARDE A VIRADA DO DIA (UTC)"
			claimLook.base(DRAB)
			claimBtn.TextColor3 = V.DIM
		end
		local res = dailyResult
		if res and res.ok and d.canClaim then
			res = nil -- virou o dia: o recibo de ontem sai da folha
			dailyResult = nil
		end
		if res and res.ok then
			local list = {}
			for _, id in (res.newItems or {}) :: { string } do
				table.insert(list, itemName(id))
			end
			-- duas frases inteiras (com e sem item novo); os itens entram juntos no %s
			dResult.Text = if #list > 0
				then string.format(
					"Selo do dia %d recebido: +1 dia de serviço. Novo no armário da Intendência: %s.",
					res.day or day,
					table.concat(list, " · ")
				)
				else string.format("Selo do dia %d recebido: +1 dia de serviço.", res.day or day)
		elseif res and res.reason then
			dResult.Text = REASON[res.reason] or REASON.error
		elseif d.broken then
			dResult.Text = "Um dia passou sem selo: a sequência recomeçou no dia 1."
		else
			dResult.Text = ""
		end
		dNote.Text = if d.saved == false
			then "Sessão sem DataStore (perfil não carregou ou Studio): o selo de hoje não fica gravado."
			else ""
	end
end

local renderFooter: (scene: string) -> ()
do
	-- ===== rodapé: dicas de botão e "VOLTAR" para mouse e toque =====
	-- numa faixa escura do tamanho das dicas: sobre os papéis claros e a carta, o cáqui sumia
	-- (Studio, D-93)
	local hints = Instance.new("Frame")
	hints.BackgroundColor3 = UiKit.NIGHT
	hints.BackgroundTransparency = 0.28
	hints.BorderSizePixel = 0
	hints.Position = UDim2.fromOffset(40, 676)
	hints.AutomaticSize = Enum.AutomaticSize.X
	hints.Size = UDim2.fromOffset(0, 36)
	hints.Parent = root
	corner(hints, 4)
	do
		local hp = Instance.new("UIPadding")
		hp.PaddingLeft = UDim.new(0, 10)
		hp.PaddingRight = UDim.new(0, 12)
		hp.Parent = hints
	end
	local hintsLayout = Instance.new("UIListLayout")
	hintsLayout.FillDirection = Enum.FillDirection.Horizontal
	hintsLayout.Padding = UDim.new(0, 22)
	hintsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hintsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hintsLayout.Parent = hints
	-- Cada dica é um chip: o botão do controle (imagem do Roblox para o controle conectado) ou, no
	-- teclado e no toque, a tecla em relevo (ficha clara, filete de tinta, luz de cima); depois o texto.
	type Chip = { f: Frame, img: ImageLabel, img2: ImageLabel, key: TextLabel, t: TextLabel }
	local chips: { Chip } = {}
	for i = 1, 6 do
		local f = Instance.new("Frame")
		f.BackgroundTransparency = 1
		f.AutomaticSize = Enum.AutomaticSize.X
		f.Size = UDim2.fromOffset(0, 36)
		f.LayoutOrder = i
		f.Visible = false
		f.Parent = hints
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.Padding = UDim.new(0, 6)
		l.VerticalAlignment = Enum.VerticalAlignment.Center
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = f
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(30, 30)
		img.LayoutOrder = 1
		img.Parent = f
		local img2 = Instance.new("ImageLabel")
		img2.BackgroundTransparency = 1
		img2.Size = UDim2.fromOffset(30, 30)
		img2.LayoutOrder = 2
		img2.Parent = f
		local key = Instance.new("TextLabel")
		key.BackgroundColor3 = V.PANEL_3
		key.BorderSizePixel = 0
		key.AutomaticSize = Enum.AutomaticSize.X
		key.Size = UDim2.fromOffset(0, 26)
		key.FontFace = F.TITLE_MED
		key.TextColor3 = V.TEXT
		key.LayoutOrder = 3
		key.Parent = f
		reg(key, 15)
		corner(key, 4)
		stroke(key, V.LINE, 1, 0.2)
		local kp = Instance.new("UIPadding")
		kp.PaddingLeft = UDim.new(0, 8)
		kp.PaddingRight = UDim.new(0, 8)
		kp.Parent = key
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromOffset(0, 36)
		t.Font = TYPE
		t.TextColor3 = V.DIM
		t.LayoutOrder = 4
		t.Parent = f
		reg(t, 16)
		table.insert(chips, { f = f, img = img, img2 = img2, key = key, t = t })
	end

	local function padImage(code: Enum.KeyCode): string?
		local img: string? = nil
		pcall(function()
			local v = UserInputService:GetImageForKeyCode(code) :: any
			if type(v) == "string" and v ~= "" then
				img = v
			end
		end)
		return img
	end

	local hintCount = 0
	local function chip(img: string?, img2: string?, key: string, label: string)
		hintCount += 1
		local c = chips[hintCount]
		if not c then
			return
		end
		c.f.Visible = true
		c.img.Visible = img ~= nil
		c.img.Image = img or ""
		c.img2.Visible = img2 ~= nil
		c.img2.Image = img2 or ""
		c.key.Visible = img == nil and key ~= ""
		c.key.Text = UiKit.upper(key)
		c.key.FontFace = UiKit.headFont(key)
		c.t.Text = label
	end

	-- ícone do botão certo do controle conectado (Input.glyph usa GetImageForKeyCode)
	local function actionChip(actionId: string, ctx: string, label: string)
		local img, text = Input.glyph(actionId, ctx)
		chip(img, nil, keyName(text), label)
	end

	local function pairChip(a: string, b: string, ctx: string, label: string)
		local ia, ta = Input.glyph(a, ctx)
		local ib, tb = Input.glyph(b, ctx)
		if ia and ib then
			chip(ia, ib, "", label)
		else
			chip(nil, nil, keyName(ta) .. "/" .. keyName(tb), label)
		end
	end

	local backBtn = darkButton(root, "", 960, 674, 280, 40)
	backBtn.Visible = false
	bindDark(backBtn, function()
		DeployScreen.back()
	end)

	local function backLabel(scene: string): string?
		if scene == "choose" then
			return if isBrowsing() then "◄ VOLTAR À MESA" else nil
		elseif panel ~= "desk" then
			return "◄ VOLTAR À MESA"
		end
		return nil
	end

	function renderFooter(scene: string)
		hintCount = 0
		local dev = Input.device()
		local back = backLabel(scene)
		if panel == "insert" and scene ~= "choose" then
			if dev == "gamepad" then
				actionChip("map_next", "map", "Próximo ponto")
				actionChip("map_select", "map", "Inserir")
				actionChip("map_mark", "map", "Levar veículo")
				actionChip("map_role", "map", "Trocar de papel")
				actionChip("map_back", "map", "Voltar à mesa")
			elseif dev == "touch" then
				chip(nil, nil, "Toque", "no ponto de inserção")
			else
				chip(nil, nil, "Clique", "no ponto de inserção")
				actionChip("map_next", "map", "Próximo ponto")
				actionChip("map_select", "map", "Inserir")
				actionChip("map_back", "map", "Voltar à mesa")
			end
		elseif dev == "gamepad" then
			chip(padImage(Enum.KeyCode.ButtonA), nil, "A", "Escolher")
			if back then
				actionChip("ui_back", "menu", "Voltar")
			end
			pairChip("ui_tab_prev", "ui_tab_next", "menu", if scene == "choose" then "Lado" else "Objeto / aba")
			chip(padImage(Enum.KeyCode.DPadUp), padImage(Enum.KeyCode.DPadRight), "D-pad", "Pular")
		else
			chip(nil, nil, if dev == "touch" then "Toque" else "Clique", "num objeto da mesa")
			if dev ~= "touch" then
				if back then
					actionChip("ui_back", "menu", "Voltar")
				end
				if scene ~= "choose" then
					pairChip("ui_tab_prev", "ui_tab_next", "menu", "Abas")
				end
			end
		end
		for i = hintCount + 1, #chips do
			chips[i].f.Visible = false
		end
		hints.Visible = hintCount > 0
		backBtn.Visible = back ~= nil and dev ~= "gamepad"
		backBtn.Text = back or ""
	end
end

-- ===== cabeçalho =====
-- efetivo dos lados (jogadores; os bots não contam no equilíbrio), em números grandes; os acentos
-- dos painéis e o indicador das abas na cor do lado do jogador (EUA azul, VC vermelho)
local accentNow: Color3? = nil
local function updateHeader(f: string?)
	local us, vc = counts()
	teamNums.US.Text = string.format("%d/%d", us, Roles.TEAM_MAX)
	teamNums.VC.Text = string.format("%d/%d", vc, Roles.TEAM_MAX)
	local c = sideColor(f)
	if c ~= accentNow then
		accentNow = c
		for _, a in sideAccents do
			a.BackgroundColor3 = c
		end
		tabMark.BackgroundColor3 = c
	end
end

-- abas: estado de cada passo na segunda linha
local function renderTabs(f: string, st: any)
	local sid = player:GetAttribute("SquadId")
	local squadText = "formar ou entrar"
	if type(sid) == "string" then
		local name = string.match(sid, ":(.+)$") or sid
		local sq = findSquad(st, sid)
		local unit = if sq then sq.unit else unitOfSquad(f, sid)
		local def = if unit then Roles.units[f][unit] else nil
		squadText = if sq and def
			then string.format("✓ %s %d/%d", name, #sq.members, def.size)
			else string.format("✓ %s", name)
	end
	local rid = currentRole()
	local roleText = if rid and Roles.roles[rid] then string.format("✓ %s", Roles.roles[rid].name) else "escolher"
	local insertText = if not rid then "falta o papel" elseif alive() then "em campo" else "carta de spawn"
	local dTab = dailySummary()
	tabs.squad.info.Text = squadText
	tabs.role.info.Text = roleText
	tabs.insert.info.Text = insertText
	tabs.daily.info.Text = dTab
	tabs.shop.info.Text = "loja e armário"
	tabs.faction.info.Text = string.format("agora: %s", FACTION[f].short)
	tabs.desk.info.Text = "visão geral"
	for _, t in tabs do
		tabStyle(t)
	end
	-- as mesmas situações nas etiquetas dos objetos da mesa
	LobbyScene.setSub("squad", string.format("SQUAD · %s", squadText))
	LobbyScene.setSub("role", string.format("PAPEL · %s", roleText))
	LobbyScene.setSub("insert", string.format("INSERÇÃO · %s", insertText))
	LobbyScene.setSub("daily", string.format("RECOMPENSA DIÁRIA · %s", dTab))
end

-- textos das peças da mesa (rádio, dossiê, calendário)
local function renderDesk(f: string, st: any)
	local sid = player:GetAttribute("SquadId")
	local squadName = if type(sid) == "string" then (string.match(sid, ":(.+)$") or sid) else nil
	local sq = if type(sid) == "string" then findSquad(st, sid) else nil
	local unit = if type(sid) == "string" then (if sq then sq.unit else unitOfSquad(f, sid)) else nil
	local def = if unit then Roles.units[f][unit] else nil
	LobbyScene.setText(
		"radio",
		if squadName
			then UiKit.upper(squadName) .. (if sq and def then string.format("  %d/%d", #sq.members, def.size) else "")
			else "— SEM SQUAD —"
	)
	local rid = currentRole()
	local lo = loadoutNow(f)
	local hq = MapConfig.HQ[f]
	LobbyScene.setText(
		"dossier",
		table.concat({
			string.format(
				"POSTO: %s",
				if type(player:GetAttribute("Rank")) == "number" then tostring(player:GetAttribute("Rank")) else "—"
			),
			string.format("SQUAD: %s", squadName or "—"),
			string.format("PAPEL: %s", if rid and Roles.roles[rid] then Roles.roles[rid].name else "—"),
			string.format("ARMAS: %s", if rid then weaponNames(lo) else "—"),
			string.format("QG: %s", gridRef(hq.x, hq.z)),
		}, "\n")
	)
	local d = daily
	local day = if d and d.ready and d.day then d.day else 1
	local _, note = dailySummary()
	LobbyScene.setText("calDay", tostring(17 + day))
	LobbyScene.setText("calNote", note)
	-- soldado da mesa com a arma do papel (fora do painel de papel, o papel atual)
	if panel ~= "role" then
		LobbyScene.setLoadout(f, if lo then lo[1] else nil)
	end
end

-- ===== render =====
local function placeLobbyCamera(scene: string)
	-- etiquetas 3D da mesa: abaixo do título e das abas (subiam por cima deles, D-93); com uma pasta
	-- aberta elas somem
	LobbyScene.setTagArea(function(): number
		local a, s = root.AbsolutePosition, root.AbsoluteSize
		if s.Y < 10 then
			return 60
		end
		local bottom = if tabsFrame.Visible then tabsFrame.Position.Y.Offset + tabsFrame.Size.Y.Offset else 120
		return a.Y + bottom / DESIGN_H * s.Y + GuiService:GetGuiInset().Y
	end, scene ~= "choose" and panel ~= "desk")
	if scene == "choose" then
		LobbyScene.setFocus(nil, ndc(640, 250))
		LobbyScene.setNext(nil)
		return
	end
	if panel == "desk" then
		LobbyScene.setFocus(nil, ndc(790, 400))
	elseif panel == "insert" then
		LobbyScene.setFocus("insert", ndc(835, 419))
	elseif panel == "shop" then
		LobbyScene.setFocus("shop", ndc(200, 420))
	else
		LobbyScene.setFocus(panel, ndc(290, 360))
	end
	LobbyScene.setNext(nextStep())
end

-- ordem das pastas no caminho até o campo: a pasta seguinte chega da direita, a anterior da esquerda
local PAGE_ORDER: { [string]: number } = { squad = 1, role = 2, insert = 3, daily = 4 }
local lastPage: string? = nil

-- Troca de pasta em crossfade (pageShow). Devolve a pasta que acabou de entrar (para a entrada
-- escalonada dos cartões, depois de desenhados) ou nil.
local function swapPages(onChoose: boolean): string?
	local want: string? = if onChoose then "choose" elseif pages[panel] then panel else nil
	local from = lastPage
	local dir = 1
	if want and from and PAGE_ORDER[want] and PAGE_ORDER[from] and PAGE_ORDER[want] < PAGE_ORDER[from] then
		dir = -1
	end
	local entered: string? = nil
	for name in pages do
		local on = name == want
		if on ~= pageShown[name] then
			pageShown[name] = on
			if on then
				entered = name
			end
			if name == "choose" then
				pageShow(name, on, 0, if on then 36 else 24) -- fichas de lado: sobem / descem
			elseif name == "insert" then
				pageShow(name, on, if on then -50 else -30, 0) -- inserção: pela esquerda
			else
				pageShow(name, on, if on then 60 * dir else -30 * dir, 0) -- papéis: folheando
			end
		end
	end
	lastPage = want
	return entered
end

-- abas descem para o lugar, uma depois da outra
local function dealTabs()
	tabsFrame.Position = UDim2.fromOffset(40, 70)
	tw(tabsFrame, PAGE_IN, { Position = UDim2.fromOffset(40, 84) })
	for i, d in TAB_DEFS do
		local b = tabs[d.id].btn
		local sc = b:FindFirstChild("Escala")
		if sc and sc:IsA("UIScale") then
			sc.Scale = 0.9
			tw(sc, after(0.04 * i, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)), {
				Scale = 1,
			})
		end
	end
end

-- lobby fechado (ou aberto de novo): a próxima abertura anima tudo outra vez
local function resetLook()
	pagesReset()
	lastPage = nil
	capToken += 1
	capOn = false
	capHolder.Visible = false
	capHolder.GroupTransparency = 1
	capShown = ""
	iLines.Text = ""
	tabsFrame.Visible = false
	chooseHint.Visible = false
end

-- Coluna da campanha (plano de volta diária, 2026-11-12): placa do jogador, vantagens ativas, XP
-- dobrado do fim de semana, atalhos de missões e passe e a oferta do Pacote de Recruta. Só na mesa
-- (sem pasta aberta), à esquerda, onde a cena 3D deixa livre. Guardada na tabela do módulo (a
-- DeployScreen está perto do limite de 200 locais).
do
	local ok, Cartao = pcall(require, script.Parent:WaitForChild("CartaoJogador"))
	if ok and type(Cartao) == "table" then
		(DeployScreen :: any)._campanha = (Cartao :: any).lobby(root, 40, 146, 300)
	end
end

-- st: último Squad_State (ou nil). Só desenha com a tela visível (o GameUI controla Visible).
function DeployScreen.render(st: any)
	if not root.Visible then
		if wasVisible then
			resetLook()
			local camp = (DeployScreen :: any)._campanha
			if camp then
				camp.setVisible(false)
			end
		end
		wasVisible = false
		SoldierPreview.setActive(portrait, false)
		LobbyScene.setExternalHover(nil)
		return
	end
	if not wasVisible then
		wasVisible = true
		panel = defaultPanel()
		resetLook()
		fetchDaily()
	end
	local f = myFaction()
	if st and st.faction ~= f then
		st = nil -- estado do lado antigo (troca de lado): espera o do lado novo
	end
	-- painel que perdeu o pré-requisito (saiu do squad, papel limpo, nasceu)
	if not f then
		panel = "desk"
	elseif panel == "role" and not hasSquad() then
		panel = "squad"
	elseif panel == "insert" and not (hasSquad() and currentRole() and not alive()) then
		panel = if not hasSquad() then "squad" elseif not currentRole() then "role" else "desk"
	end
	local scene = sceneId()
	LobbyScene.setScene(scene)
	updateHeader(f)
	local onChoose = scene == "choose"
	chooseHint.Visible = onChoose
	-- pasta nova na tela: a anterior esmaece e recua, a nova desliza e abre
	local entered = swapPages(onChoose)
	if tabsFrame.Visible == onChoose then
		tabsFrame.Visible = not onChoose
		if not onChoose then
			dealTabs()
		end
	end
	if onChoose then
		renderChoose()
	elseif f then
		renderTabs(f, st)
		renderDesk(f, st)
		if panel == "squad" then
			local fresh = renderSquad(f, st)
			if entered ~= "squad" and #fresh > 0 then
				deal(fresh, 0.02, 0.04) -- squad novo (de outro jogador) ou o estado chegando
			end
		elseif panel == "role" then
			local sid = player:GetAttribute("SquadId")
			renderRole(f, st, tostring(sid))
		elseif panel == "insert" then
			renderInsert(f)
		elseif panel == "daily" then
			renderDaily(f)
		end
	end
	-- ficha do soldado (papel): entra depois de desenhada, esmaecendo
	capShow(not onChoose and panel == "role")
	local camp = (DeployScreen :: any)._campanha
	if camp then
		camp.setVisible(not onChoose and f ~= nil and panel == "desk")
	end
	-- cartões da pasta que acabou de entrar pousam um a um (já com o conteúdo certo)
	if entered == "choose" then
		dealChoose()
	elseif entered == "squad" then
		dealSquad()
	elseif entered == "role" then
		dealRoles()
	elseif entered == "daily" then
		dealDaily()
	elseif entered == "insert" then
		dealInsert()
	end
	SoldierPreview.setActive(portrait, not onChoose and panel == "insert")
	Bus.fire("insercao_painel", not onChoose and panel == "insert") -- D-103: Controllers/CompraVeiculo
	placeLobbyCamera(scene)
	renderFooter(scene)
end

-- painel que a mesa mostra agora (o GameUI abre o mapa de spawn em "insert")
function DeployScreen.panel(): string
	if not root.Visible or sceneId() == "choose" then
		return "desk"
	end
	return panel
end

-- Abre o que um objeto da mesa (ou uma aba) pede, com os pré-requisitos do caminho até o campo.
function DeployScreen.open(name: string)
	if name == "faction" then
		browsing, browsingFaction = true, myFaction()
		panel = "desk"
		DeployScreen.changed()
		return
	end
	if not myFaction() then
		return
	end
	if name == "desk" then
		panel = "desk"
		DeployScreen.changed()
		return
	end
	if name == "role" and not hasSquad() then
		notify("Primeiro um squad: o rádio da mesa.")
		name = "squad"
	elseif name == "insert" then
		if not hasSquad() then
			notify("Primeiro um squad: o rádio da mesa.")
			name = "squad"
		elseif not currentRole() then
			notify("Escolha o papel no dossiê antes da inserção.")
			name = "role"
		elseif alive() then
			notify("Você já está em campo.")
			return
		end
	end
	if name == "daily" then
		fetchDaily()
	end
	if name == "role" then
		previewRole = nil
	end
	panel = name
	if name == "shop" then
		Bus.fire("shop_open")
	end
	DeployScreen.changed()
end

-- B / VOLTAR: devolve true se tratou
function DeployScreen.back(): boolean
	if not root.Visible then
		return false
	end
	if sceneId() == "choose" then
		if isBrowsing() then
			browsing = false
			DeployScreen.changed()
			return true
		end
		return false
	end
	if panel ~= "desk" then
		panel = "desk"
		DeployScreen.changed()
		return true
	end
	return false
end

-- LB/RB (Q/E): na mesa, no controle, leva o cursor ao próximo objeto; com um painel aberto (ou no
-- teclado), abre o painel seguinte, como abas. Na sala de arquivo, alterna entre os dois lados.
function DeployScreen.cycle(dir: number)
	if not root.Visible then
		return
	end
	if sceneId() == "choose" then
		cycleIdx = cycleIdx % 2 + 1
		local id = if cycleIdx == 1 then "pick_US" else "pick_VC"
		local p = LobbyScene.screenPoint(id)
		if p and VirtualCursor.isActive() then
			VirtualCursor.moveTo(p)
		else
			hoverFaction = string.sub(id, 6)
			LobbyScene.setExternalHover(id)
			renderChoose()
		end
		return
	end
	if panel == "desk" and VirtualCursor.isActive() and LobbyScene.deskVisible() then
		for _ = 1, #CYCLE do
			cycleIdx = (cycleIdx - 1 + dir) % #CYCLE + 1
			local p = LobbyScene.screenPoint(CYCLE[cycleIdx])
			if p then
				VirtualCursor.moveTo(p)
				return
			end
		end
		return
	end
	local i = table.find(CYCLE, panel) or 0
	local nextName = CYCLE[(i - 1 + dir) % #CYCLE + 1]
	if i == 0 and dir < 0 then
		nextName = CYCLE[#CYCLE]
	end
	DeployScreen.open(nextName)
end

-- ===== a mesa 3D chama aqui =====
LobbyScene.onActivate = function(id: string)
	if not root.Visible then
		return
	end
	if id == "pick_US" or id == "pick_VC" then
		chooseFaction(string.sub(id, 6))
	elseif id == panel then
		return -- já aberto
	else
		DeployScreen.open(id)
	end
end
LobbyScene.onHover = function(id: string?)
	local f: string? = nil
	if id == "pick_US" then
		f = "US"
	elseif id == "pick_VC" then
		f = "VC"
	end
	if f ~= hoverFaction then
		hoverFaction = f
		if root.Visible and sceneId() == "choose" then
			for side in fcards do
				fcardStyle(side)
			end
		end
	end
end

-- a loja fechou (B ou ✕): a câmera volta da caixa de munição para a mesa
Bus.on("shop_closed", function()
	if panel == "shop" then
		panel = "desk"
		DeployScreen.changed()
	end
end)

-- ===== recompensa diária: estado do servidor =====
task.spawn(function()
	Net.event("Daily_State").OnClientEvent:Connect(function(s: any)
		if type(s) ~= "table" then
			return
		end
		daily = s
		dailyAt = os.clock()
		if s.result then
			dailyResult = s.result
			dailyBusy = false
		end
		DeployScreen.changed()
	end)
	fetchDaily()
end)

-- ===== atributos: o caminho avança sozinho =====
player:GetAttributeChangedSignal("SquadId"):Connect(function()
	previewRole = nil
	if hasSquad() then
		if panel == "squad" then
			panel = "role"
		end
	elseif panel == "role" or panel == "insert" then
		panel = "squad"
	end
	DeployScreen.changed()
end)
player:GetAttributeChangedSignal("Role"):Connect(function()
	if currentRole() and panel == "role" then
		panel = if alive() then "desk" else "insert"
	end
	DeployScreen.changed()
end)
player:GetAttributeChangedSignal("Faction"):Connect(function()
	browsing, browsingFaction = false, nil
	previewRole = nil
	panel = "desk" -- lado novo: chega na mesa (visão geral)
	DeployScreen.changed()
end)

-- efetivo dos lados e contagem da caderneta: só textos, uma vez por segundo com a tela aberta
task.spawn(function()
	while true do
		task.wait(1)
		if root.Visible then
			local f = myFaction()
			updateHeader(f)
			local scene = sceneId()
			if scene == "choose" then
				renderChoose()
			elseif f then
				local dTab, note = dailySummary()
				tabs.daily.info.Text = dTab
				LobbyScene.setSub("daily", string.format("RECOMPENSA DIÁRIA · %s", dTab))
				LobbyScene.setText("calNote", note)
				if panel == "daily" then
					renderDaily(f)
				end
			end
			-- virou o dia UTC com a tela aberta: pede o estado novo
			if daily and daily.ready and daily.claimedToday and dailyLeft() <= 0 then
				fetchDaily()
			end
		end
	end
end)

-- ===== gancho de teste (só no Studio): fotos da escolha e da inserção =====
-- workspace:SetAttribute("VT65DevTela", x), com o jogador no lobby (sem corpo em campo):
--   - "escolha": o passo de escolha que falta (lado; com lado, o squad; com squad, o papel);
--   - "lado", "squad", "papel", "diaria": aquela ficha (com lado escolhido, "lado" abre a sala de
--     arquivo do "trocar de lado");
--   - "insercao": completa o caminho pelos remotes, como o jogador faria (EUA se não há lado, squad
--     de infantaria, fuzileiro) e abre a ficha de inserção com a carta de spawn.
-- "carregamento" é da tela de entrada (LoadingScreen) e "transicao", da ordem de inserção
-- (SpawnTransition). Do lado do cliente o valor volta a nil sozinho (dá para repetir); do lado do
-- servidor, alterne os valores.
if RunService:IsStudio() then
	local function waitAttr(name: string, seconds: number): boolean
		local t0 = os.clock()
		while player:GetAttribute(name) == nil and os.clock() - t0 < seconds do
			task.wait(0.1)
		end
		return player:GetAttribute(name) ~= nil
	end
	local function devInsertion()
		if not myFaction() then
			Net.event("Team_Choose"):FireServer("US")
			if not waitAttr("Faction", 5) then
				warn("[VT65] VT65DevTela insercao: o servidor não deu lado")
				return
			end
		end
		if not hasSquad() then
			Net.event("Squad_Action"):FireServer({ op = "create", unit = "infantry" })
			if not waitAttr("SquadId", 5) then
				warn("[VT65] VT65DevTela insercao: o servidor não deu squad")
				return
			end
		end
		if not currentRole() then
			Net.event("Role_Choose"):FireServer("rifleman")
			if not waitAttr("Role", 5) then
				warn("[VT65] VT65DevTela insercao: o servidor não deu papel")
				return
			end
		end
		task.wait(0.2) -- deixa o refresh do GameUI rodar com o papel novo
		DeployScreen.open("insert")
	end
	local DEV_PANEL: { [string]: string } = { squad = "squad", papel = "role", diaria = "daily" }
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if type(v) ~= "string" or v == "carregamento" or v == "transicao" then
			return
		end
		if v == "escolha" then
			if not myFaction() then
				DeployScreen.changed()
			elseif not hasSquad() then
				DeployScreen.open("squad")
			else
				DeployScreen.open("role")
			end
		elseif v == "lado" then
			if myFaction() then
				DeployScreen.open("faction")
			else
				DeployScreen.changed()
			end
		elseif DEV_PANEL[v] then
			DeployScreen.open(DEV_PANEL[v])
		elseif v == "insercao" then
			task.spawn(devInsertion)
		else
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil) -- local: no cliente, o mesmo valor repete
		end)
	end)
end

return DeployScreen
