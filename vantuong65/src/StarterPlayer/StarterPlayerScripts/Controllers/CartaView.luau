--!strict
-- Carta tática de verdade (pedido do dono, 2026-11-11: "o mapa que você abre no jogo está
-- simplório, faça um mapa de verdade"). O GameUI continua dono das telas e das entradas do mapa;
-- este módulo desenha dentro da janela do mapa:
--   - a folha: a carta topográfica (tools/make_carta.py) em 4 blocos de 1024 px; sem imagem
--     publicada, um fundo escuro com a quadrícula de 1 km;
--   - por cima, no estilo novo (Estilo/UiKit, 2026-11-11: sem papel datilografado, lápis nem vincos):
--     setores com dono (azul = nosso, vermelho = do inimigo, cinza = neutro), a frente, os objetivos
--     com o progresso e a disputa, os pontos de inserção do lado do jogador (símbolo forte, estado
--     pela cor: verde = pronto, cáqui = esperando, vermelho = bloqueado), os pontos de nascer no
--     squad (com o nome do companheiro), os túneis do VC (só para o VC: bocas e para onde levam), o
--     squad, as marcações do squad e "você" com a seta do rumo. NUNCA inimigo (Parte 9.5): as marcas
--     de área aproximada são do próprio squad e envelhecem (D-48);
--   - zoom e arrasto suaves: no controle, analógico esquerdo = cursor, direito = arrastar, gatilhos =
--     zoom, direcional = passo de arrasto, L3 = você, R3 = carta inteira; no mouse, roda = zoom no
--     ponteiro e arrastar com o botão esquerdo; no teclado, setas e +/-;
--   - escala gráfica que acompanha o zoom, seta do norte, grade do cursor ("BS 693 928") e legenda.
--   - toque (Parte 13): um dedo arrasta, dois dedos fazem pinça (zoom no meio dos dedos, e a carta
--     anda junto); tocar escolhe o ponto de inserção mais perto num raio do tamanho do dedo (não
--     insere: o GameUI mostra o botão de inserir com a espera) ou o alvo do comandante; em campo,
--     tocar marca (como o clique).
-- Tudo em unidades de projeto do palco do GameUI (1280 x 720 com UIScale).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Carta = require(ReplicatedStorage.Shared.Carta)
local Comms = require(ReplicatedStorage.Shared.Comms)
local FireSupport = require(ReplicatedStorage.Shared.FireSupport)
local Front = require(ReplicatedStorage.Shared.Front)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local TunnelLinks = require(ReplicatedStorage.Shared.TunnelLinks)
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local EventosVisual = require(script.Parent.EventosVisual)
local Input = require(script.Parent.Input)
local Marcadores = require(script.Parent.Marcadores)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)
local VozEstado = require(script.Parent.VozEstado)

local CartaView = {}

local player = Players.LocalPlayer
local B = MapConfig.Bounds
local M = MapConfig.STUD_M
local SIDE_M = (B.maxX - B.minX) * M -- lado da carta em metros (sempre dos Bounds de agora)
local V, F = UiKit.V, UiKit.F

-- cores sobre a carta (legíveis na carta clara e no fundo escuro de reserva: símbolo cheio com
-- contorno escuro). Cor FIXA por lado (pedido do dono): EUA sempre azul, VC sempre vermelho, cinza =
-- neutro; "nosso" e "do inimigo" só por texto ou ícone, nunca pela cor.
local COR = {
	us = V.US,
	vc = V.VC,
	frente = V.KHAKI, -- a linha da frente não é de lado nenhum
	inimigo = V.RED_HI, -- só a área aproximada de inimigo marcada pelo squad (D-48)
	neutro = Color3.fromRGB(128, 128, 114),
	papel = V.TEXT, -- texto claro
	prancheta = V.BG, -- contorno e fundo escuros
	tinta = V.DIM, -- quadrícula do fundo de reserva
	latao = V.BRASS,
	pronto = Color3.fromRGB(124, 178, 84), -- ponto pronto
	espera = V.KHAKI, -- ponto esperando a onda
	bloqueado = V.RED, -- ponto bloqueado
	squad = V.BRASS, -- o squad (e nascer num companheiro): latão, como nos marcadores do mundo
	mine = Color3.fromRGB(120, 214, 176), -- sua marca pessoal
	lead = Color3.fromRGB(236, 120, 200), -- marca do líder para o squad
	me = V.TEXT, -- você
	tunel = Color3.fromRGB(214, 130, 64), -- túneis do VC
	lz = Color3.fromRGB(150, 196, 236), -- LZ da inserção de helicóptero (ponto "lz:<n>")
}
local TYPE = F.TITLE_MED -- rótulos (Oswald)
local HAND = F.TITLE_MED -- anotações do squad (antes a lápis; agora o mesmo Oswald)

-- estado (uma tabela só: o Luau limita 200 locais por função, e o módulo é uma função)
local S = {
	mounted = false,
	root = nil :: Frame?,
	sheet = nil :: Frame?,
	layers = {} :: { [string]: Frame },
	tiles = {} :: { ImageLabel },
	plain = nil :: Frame?,
	ts = function(n: number): number
		return n
	end,
	toLocal = nil :: ((Vector2) -> Vector2)?,
	viewW = 810,
	viewH = 486,
	mode = "view",
	zoom = 1,
	zoomT = 1,
	u = 0.5,
	v = 0.5,
	uT = 0.5,
	vT = 0.5,
	cursor = Vector2.new(405, 243), -- px na janela
	match = nil :: any,
	spawns = {} :: { any },
	inserts = {} :: { any }, -- pontos de inserção do lado (vivo, FrontService)
	squad = {} :: { any },
	marks = {} :: { any },
	focused = nil :: InputMap.MagnetPoint?,
	hoverPoint = nil :: string?, -- ponto de inserção sob o mouse (o nome aparece só nele)
	prefer = nil :: string?, -- ponto pronto mais perto do objetivo do time (a carta de inserção abre nele)
	preferShown = false, -- a vista já foi levada até ele nesta abertura
	eventWidgets = {} :: { [string]: any }, -- raio dos eventos da partida, por nome do marcador
	tunnelSig = "", -- túneis desenhados para (lado): refeitos só quando o lado muda
	tunnelDest = {} :: { [string]: { string } }, -- boca -> bocas a que leva (do mais perto)
	key = nil :: Frame?, -- legenda curta da carta de inserção
	wp = {} :: { [string]: Frame }, -- marcadores guiados na carta: "mine" (sua marca) e "lead" (líder)
	sig = "",
	spawnSig = "",
	objWidgets = {} :: { [number]: any },
	spawnWidgets = {} :: { [string]: any },
	squadWidgets = {} :: { [number]: any },
	me = nil :: Frame?,
	meArrow = nil :: TextLabel?,
	hud = {} :: { [string]: any },
	drag = nil :: any,
	dragged = false,
	dpad = {} :: { [string]: boolean },
	keys = {} :: { [string]: boolean },
	onSpawn = nil :: ((pt: any) -> ())?,
	onClick = nil :: ((u: number, v: number) -> ())?,
	pulseT = 0,
	visible = false,
	legend = nil :: Frame?,
	legendScore = nil :: TextLabel?,
	-- toque (Parte 13): dedos na carta (px da janela), pinça e o ponto escolhido por toque
	touches = {} :: { [InputObject]: Vector2 },
	touchT0 = 0,
	pinch = nil :: any,
	touchPick = nil :: InputMap.MagnetPoint?,
	onTouch = nil :: (() -> ())?,
}

-- ===== peças =====
local function frame(parent: Instance, name: string, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

-- font: Font (Oswald/Arimo do estilo) ou Enum.Font (símbolos ◆ ▲ ◄, que o Oswald não tem)
local function label(parent: Instance, text: string, size: number, color: Color3, font: any?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.new()
	if typeof(font) == "EnumItem" then
		t.Font = font :: any
	else
		t.FontFace = if typeof(font) == "Font" then font :: Font else TYPE
	end
	t.TextSize = S.ts(size)
	t.TextColor3 = color
	t.RichText = true
	t.Text = Acabamento.viet(text)
	t.Parent = parent
	return t
end

local function corner(o: GuiObject, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0)
	c.Parent = o
end

local function stroke(o: GuiObject, color: Color3, thick: number, tr: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.Transparency = tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

local function clearLayer(name: string)
	local l = S.layers[name]
	if l then
		for _, c in l:GetChildren() do
			c:Destroy()
		end
	end
end

local function uv(x: number, z: number): (number, number)
	return Carta.toUV(B, x, z)
end

local function myFaction(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else nil
end

-- cor do dono: fixa por lado (EUA azul, VC vermelho), cinza = neutro
local function ownerColor(owner: string?): Color3
	if owner == "US" then
		return COR.us
	elseif owner == "VC" then
		return COR.vc
	end
	return COR.neutro
end

-- linha reta entre dois pontos da folha (u, v), em px (não engrossa com o zoom)
local function pencil(
	parent: Instance,
	u1: number,
	v1: number,
	u2: number,
	v2: number,
	color: Color3,
	px: number,
	z: number?,
	tr: number?
): Frame?
	local du, dv = u2 - u1, v2 - v1
	local len = math.sqrt(du * du + dv * dv)
	if len < 1e-6 then
		return nil
	end
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = tr or 0.1
	f.BorderSizePixel = 0
	f.Rotation = math.deg(math.atan2(dv, du))
	f.Position = UDim2.fromScale((u1 + u2) / 2, (v1 + v2) / 2)
	f.Size = UDim2.new(len, 0, 0, px)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

-- tracejado (n trechos) entre dois pontos da folha
local function dashed(
	parent: Instance,
	u1: number,
	v1: number,
	u2: number,
	v2: number,
	color: Color3,
	px: number,
	n: number
)
	for k = 0, n - 1, 2 do
		local t0, t1 = k / n, (k + 1) / n
		pencil(parent, u1 + (u2 - u1) * t0, v1 + (v2 - v1) * t0, u1 + (u2 - u1) * t1, v1 + (v2 - v1) * t1, color, px)
	end
end

-- ===== montagem =====
function CartaView.mount(parent: Frame, ts: (n: number) -> number, toLocal: (Vector2) -> Vector2)
	if S.mounted then
		return
	end
	S.mounted = true
	S.root = parent
	S.ts = ts
	S.toLocal = toLocal
	-- painel escuro em volta da folha (estilo novo: nada de prancheta nem papel)
	parent.BackgroundColor3 = V.BG_NIGHT
	parent.BackgroundTransparency = 0

	local sheet = frame(parent, "Folha", 2)
	sheet.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.BackgroundColor3 = V.PANEL_2 -- sem a carta publicada: fundo escuro com a quadrícula
	sheet.BackgroundTransparency = 0
	sheet.ClipsDescendants = false
	S.sheet = sheet
	UiKit.stroke(sheet, V.LINE, 1, 0.3)

	-- blocos da carta (imagem) e o fundo de reserva com a quadrícula de 1 km
	for _, t in Carta.TILES do
		local img = Instance.new("ImageLabel")
		img.Name = "Carta_" .. t.key
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Position = UDim2.fromScale(t.col * 0.5, t.row * 0.5)
		img.Size = UDim2.fromScale(0.5, 0.5)
		img.ScaleType = Enum.ScaleType.Stretch
		img.ResampleMode = Enum.ResamplerMode.Default
		img.ZIndex = 1
		img:SetAttribute("Key", t.key)
		img.Parent = sheet
		table.insert(S.tiles, img)
	end
	local plain = frame(sheet, "FundoLiso", 1)
	S.plain = plain
	local g = MapConfig.GridOrigin1965
	for e = math.ceil((g.e + B.minX * M) / 1000) * 1000, g.e + B.maxX * M, 1000 do
		local u = select(1, uv((e - g.e) / M, 0))
		pencil(plain, u, 0, u, 1, V.LINE, 1, nil, 0.3)
		local t = label(plain, tostring((e // 1000) % 100), 14, COR.tinta)
		t.Position = UDim2.new(u, 4, 0, 4)
	end
	for n = math.ceil((g.n - B.maxZ * M) / 1000) * 1000, g.n - B.minZ * M, 1000 do
		local v = select(2, uv(0, (g.n - n) / M))
		pencil(plain, 0, v, 1, v, V.LINE, 1, nil, 0.3)
		local t = label(plain, tostring((n // 1000) % 100), 14, COR.tinta)
		t.Position = UDim2.new(0, 4, v, 2)
	end

	-- camadas (ordem de baixo para cima); "tuneis" só ganha peças para o VC; "eventos": o raio dos
	-- eventos da partida (EventosVisual), por baixo dos objetivos e dos pontos
	for i, name in { "setores", "linhas", "eventos", "tuneis", "objetivos", "pontos", "marcas", "squad", "voce" } do
		S.layers[name] = frame(sheet, name, 3 + i)
	end

	-- HUD da janela: escala gráfica, norte, zoom (texto claro com contorno escuro: lê na carta clara)
	local hud = frame(parent, "Instrumentos", 5)
	pcall(function()
		hud.Interactable = false
	end)
	local bar = Instance.new("Frame")
	bar.Name = "Escala"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 14, 1, -40)
	bar.Size = UDim2.fromOffset(100, 6)
	bar.BackgroundColor3 = V.BG
	bar.BorderSizePixel = 0
	bar.Parent = hud
	stroke(bar, V.TEXT, 1.5, 0.1)
	local half = Instance.new("Frame")
	half.BackgroundColor3 = V.TEXT
	half.BorderSizePixel = 0
	half.Position = UDim2.new(0.5, 0, 0, 1)
	half.Size = UDim2.new(0.5, -1, 1, -2)
	half.Parent = bar
	local barText = label(hud, "100 m", 14, V.TEXT, F.TITLE_MED)
	barText.AnchorPoint = Vector2.new(0, 1)
	barText.Position = UDim2.new(0, 14, 1, -48)
	barText.TextStrokeColor3 = V.BG
	barText.TextStrokeTransparency = 0.25
	S.hud.bar, S.hud.barText = bar, barText
	local north = label(hud, "▲\nN", 15, V.TEXT, Enum.Font.GothamBold)
	north.AnchorPoint = Vector2.new(1, 0)
	north.Position = UDim2.new(1, -14, 0, 10)
	north.TextStrokeColor3 = V.BG
	north.TextStrokeTransparency = 0.2
	north.TextXAlignment = Enum.TextXAlignment.Center
	local zoomText = label(hud, "", 14, V.TEXT, F.TITLE_MED)
	zoomText.AnchorPoint = Vector2.new(1, 0)
	zoomText.Position = UDim2.new(1, -14, 0, 54)
	zoomText.TextStrokeColor3 = V.BG
	zoomText.TextStrokeTransparency = 0.25
	S.hud.zoom = zoomText

	-- legenda curta da carta de inserção (canto de cima à esquerda): as cores dos pontos
	do
		local key = UiKit.panel(hud, V.PANEL, 0.12)
		key.Name = "LegendaCurta"
		key.Position = UDim2.fromOffset(12, 10)
		key.AutomaticSize = Enum.AutomaticSize.XY
		key.Size = UDim2.new()
		key.Visible = false
		UiKit.pad(key, 10, 12, 6)
		UiKit.list(key, true, 12)
		local function item(order: number, color: Color3, text: string, name: string?, glyph: string?)
			local f = Instance.new("Frame")
			f.Name = name or "Item"
			f.BackgroundTransparency = 1
			f.AutomaticSize = Enum.AutomaticSize.XY
			f.Size = UDim2.new()
			f.LayoutOrder = order
			UiKit.list(f, true, 6)
			local sw = Instance.new("Frame")
			sw.Size = if glyph then UDim2.fromOffset(22, 14) else UDim2.fromOffset(12, 12)
			sw.BackgroundColor3 = color
			sw.BorderSizePixel = 0
			sw.LayoutOrder = 1
			corner(sw, 3)
			stroke(sw, V.BG, 1.5)
			sw.Parent = f
			if glyph then
				-- símbolo próprio (LZ) escrito na amostra, como no ponto da carta
				local g = UiKit.text2(sw, glyph, 11, V.BG, F.TITLE)
				g.Size = UDim2.fromScale(1, 1)
				g.TextXAlignment = Enum.TextXAlignment.Center
			end
			local t = UiKit.kicker(f, text, 13, V.TEXT)
			t.AutomaticSize = Enum.AutomaticSize.XY
			t.Size = UDim2.new()
			t.LayoutOrder = 2
			f.Parent = key
		end
		item(1, COR.pronto, "PRONTO")
		item(2, COR.espera, "ESPERANDO")
		item(3, COR.bloqueado, "BLOQUEADO")
		item(4, COR.squad, "SQUAD")
		item(5, COR.tunel, "TÚNEL", "Tunel")
		-- LZ da inserção de helicóptero (EventosService): só aparece quando houver uma
		item(6, COR.lz, "HELICÓPTERO", "LZ", "LZ")
		S.key = key
	end

	-- abertura: a janela escurece e a carta assenta
	local flash = frame(parent, "Abertura", 8)
	flash.BackgroundColor3 = V.BG
	flash.BackgroundTransparency = 1
	S.hud.flash = flash
	local scale = Instance.new("UIScale")
	scale.Parent = sheet
	S.hud.scale = scale

	CartaView.refreshImages()
	ReplicatedStorage.AttributeChanged:Connect(function(a: string)
		if string.sub(a, 1, 11) == "CartaImage_" then
			CartaView.refreshImages()
		end
	end)
	CartaView.bindMouse()
end

-- Blocos: AssetIds.CartaImages, ou os atributos que o CartaService põe depois de resolver os decais.
function CartaView.refreshImages()
	local ok = true
	for _, img in S.tiles do
		local key = img:GetAttribute("Key") :: string
		local id = (AssetIds.CartaImages or {})[key]
		if type(id) ~= "number" or id == 0 then
			id = ReplicatedStorage:GetAttribute("CartaImage_" .. key)
		end
		if type(id) == "number" and id ~= 0 then
			img.Image = "rbxassetid://" .. id
		else
			img.Image = ""
			ok = false
		end
	end
	for _, img in S.tiles do
		img.Visible = ok
	end
	if S.plain then
		S.plain.Visible = not ok
	end
end

function CartaView.hasImage(): boolean
	return #S.tiles > 0 and S.tiles[1].Visible
end

-- ===== janela =====
function CartaView.resize(w: number, h: number)
	S.viewW, S.viewH = w, h
	S.cursor = Vector2.new(math.clamp(S.cursor.X, 0, w), math.clamp(S.cursor.Y, 0, h))
	S.uT, S.vT = Carta.clampCenter(S.uT, S.vT, S.zoomT, w, h)
end

-- legenda curta: só na carta de inserção; o "túnel" só para o VC
local function paintKey()
	local key = S.key
	if key then
		key.Visible = S.mode == "spawn"
		local t = key:FindFirstChild("Tunel")
		if t and t:IsA("GuiObject") then
			t.Visible = myFaction() == "VC"
		end
		local lz = key:FindFirstChild("LZ")
		if lz and lz:IsA("GuiObject") then
			local any = false
			for _, pt in S.spawns do
				if type(pt.id) == "string" and string.sub(pt.id, 1, 3) == "lz:" then
					any = true
					break
				end
			end
			lz.Visible = any
		end
	end
end

function CartaView.setMode(mode: string)
	if mode ~= S.mode then
		S.mode = mode
		S.touchPick = nil
		S.sig, S.spawnSig = "", ""
		S.preferShown = false -- entrou na carta de inserção: abre no ponto sugerido
		CartaView.redraw()
		CartaView.drawPoints()
	end
	paintKey()
end

-- ponto da folha sob o cursor (com o ímã do controle, o ponto focado)
function CartaView.cursorUV(): (number, number)
	local f = S.focused
	if f then
		return f.x, f.y
	end
	return Carta.pick(S.u, S.v, S.zoom, S.viewW, S.viewH, S.cursor.X, S.cursor.Y)
end

function CartaView.focused(): InputMap.MagnetPoint?
	return S.focused
end

function CartaView.dragged(): boolean
	return S.dragged
end

-- leva a vista (e o cursor) até um ponto da folha, suave
function CartaView.goTo(u: number, v: number, zoom: number?)
	S.zoomT = math.clamp(zoom or math.max(S.zoomT, 2), Carta.ZOOM_MIN, Carta.ZOOM_MAX)
	S.uT, S.vT = Carta.clampCenter(u, v, S.zoomT, S.viewW, S.viewH)
	local x0, y0, size = Carta.layout(S.uT, S.vT, S.zoomT, S.viewW, S.viewH)
	S.cursor = Vector2.new(math.clamp(x0 + u * size, 0, S.viewW), math.clamp(y0 + v * size, 0, S.viewH))
end

function CartaView.fit()
	S.zoomT, S.uT, S.vT = 1, 0.5, 0.5
end

local function zoomAt(z2: number, px: number, py: number)
	z2 = math.clamp(z2, Carta.ZOOM_MIN, Carta.ZOOM_MAX)
	local au, av = Carta.pick(S.uT, S.vT, S.zoomT, S.viewW, S.viewH, px, py)
	S.uT, S.vT = Carta.zoomAbout(S.uT, S.vT, S.zoomT, z2, au, av)
	S.zoomT = z2
	S.uT, S.vT = Carta.clampCenter(S.uT, S.vT, S.zoomT, S.viewW, S.viewH)
end

local function panPx(dx: number, dy: number)
	local size = Carta.base(S.viewW, S.viewH) * S.zoomT
	S.uT, S.vT = Carta.clampCenter(S.uT + dx / size, S.vT + dy / size, S.zoomT, S.viewW, S.viewH)
end

local function inside(screen: Vector2): (boolean, Vector2)
	local root = S.root
	local toLocal = S.toLocal
	if not (root and toLocal and root.Visible) then
		return false, Vector2.zero
	end
	local p = toLocal(screen)
	return p.X >= 0 and p.Y >= 0 and p.X <= S.viewW and p.Y <= S.viewH, p
end

-- ===== toque (Parte 13) =====
-- posição do dedo em px da janela (a mesma conta do GetMouseLocation, com a faixa do Roblox)
local function touchScreen(io: InputObject): Vector2
	return Vector2.new(io.Position.X, io.Position.Y) + GuiService:GetGuiInset()
end

-- unidades da janela do mapa por px da tela (o palco do GameUI tem UIScale)
local function unitsPerPx(): number
	local root = S.root
	local w = if root then root.AbsoluteSize.X else 0
	return if w > 1 then S.viewW / w else 1
end

-- toque curto na carta: escolhe o ponto de inserção (raio do dedo) ou o alvo; em campo, marca
local function touchTap(p: Vector2)
	if S.mode == "spawn" then
		local x0, y0, size = Carta.layout(S.u, S.v, S.zoom, S.viewW, S.viewH)
		local pts: { ToqueTelas.Point } = {}
		for _, pt in S.spawns do
			local u, v = uv(pt.x, pt.z)
			table.insert(pts, { id = pt, x = x0 + u * size, y = y0 + v * size })
		end
		local near = ToqueTelas.nearest(p.X, p.Y, pts, ToqueUi.minPx() * 0.8 * unitsPerPx())
		if near then
			local pt = near.id
			local u, v = uv(pt.x, pt.z)
			S.touchPick = { id = "spawn:" .. tostring(pt.id), x = u, y = v }
		else
			S.touchPick = nil
		end
		CartaView.drawPoints()
	elseif S.mode == "target" then
		local u, v = Carta.pick(S.u, S.v, S.zoom, S.viewW, S.viewH, p.X, p.Y)
		S.touchPick = { id = "alvo", x = math.clamp(u, 0, 1), y = math.clamp(v, 0, 1) }
		S.cursor = p
	else
		local u, v = Carta.pick(S.u, S.v, S.zoom, S.viewW, S.viewH, p.X, p.Y)
		if u >= 0 and v >= 0 and u <= 1 and v <= 1 and S.onClick then
			S.onClick(u, v)
		end
	end
	local cb = S.onTouch
	if cb then
		task.spawn(cb)
	end
end

local function touchCount(): number
	local n = 0
	for _ in S.touches do
		n += 1
	end
	return n
end

-- os dois primeiros dedos (posição local na janela do mapa)
local function twoFingers(): (Vector2?, Vector2?)
	local a: Vector2?, b: Vector2? = nil, nil
	local toLocal = S.toLocal
	if not toLocal then
		return nil, nil
	end
	for _, sp in S.touches do
		local lp = toLocal(sp)
		if not a then
			a = lp
		elseif not b then
			b = lp
			break
		end
	end
	return a, b
end

-- o dedo caiu num botão de outra tela por cima da carta (os botões de toque do GameUI, o cartão de
-- compra de veículo): o toque é dele, não da carta (senão o "+" do zoom também marcava o ponto)
local function overOtherButton(io: InputObject): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local root = S.root
	if not (pg and root) then
		return false
	end
	local ok, list = pcall(function()
		return pg:GetGuiObjectsAtPosition(io.Position.X, io.Position.Y)
	end)
	if not ok or type(list) ~= "table" then
		return false
	end
	for _, o in list :: { GuiObject } do
		if o:IsA("GuiButton") and not o:IsDescendantOf(root) then
			local cur: Instance? = o
			local shown = true
			while cur and not cur:IsA("LayerCollector") do
				if cur:IsA("GuiObject") and not cur.Visible then
					shown = false
					break
				end
				cur = cur.Parent
			end
			if shown and cur and cur:IsA("LayerCollector") and cur.Enabled then
				return true
			end
		end
	end
	return false
end

local function touchBegan(io: InputObject)
	local sp = touchScreen(io)
	local ok, p = inside(sp)
	if not ok and touchCount() == 0 then
		return -- o dedo começou fora da carta (botão, legenda): não é da carta
	end
	if touchCount() == 0 and overOtherButton(io) then
		return
	end
	S.touches[io] = sp
	local n = touchCount()
	if n == 1 then
		S.drag = { start = p, u = S.uT, v = S.vT }
		S.dragged = false
		S.touchT0 = os.clock()
	elseif n == 2 then
		local a, b = twoFingers()
		if a and b then
			S.pinch = { d0 = (a - b).Magnitude, z0 = S.zoomT, mid0 = (a + b) / 2, u0 = S.uT, v0 = S.vT }
			S.dragged = true -- dois dedos nunca são toque
		end
	end
end

local function touchMoved(io: InputObject)
	if not S.touches[io] then
		return
	end
	S.touches[io] = touchScreen(io)
	local pin = S.pinch
	if pin then
		local a, b = twoFingers()
		if a and b then
			local mid = (a + b) / 2
			local z2 = ToqueTelas.pinch(pin.z0, pin.d0, (a - b).Magnitude, Carta.ZOOM_MIN, Carta.ZOOM_MAX)
			-- volta ao começo da pinça e refaz: zoom no meio inicial dos dedos e a carta anda com eles
			S.uT, S.vT, S.zoomT = pin.u0, pin.v0, pin.z0
			zoomAt(z2, pin.mid0.X, pin.mid0.Y)
			panPx(pin.mid0.X - mid.X, pin.mid0.Y - mid.Y)
		end
		return
	end
	local d = S.drag
	local toLocal = S.toLocal
	if d and toLocal then
		local p = toLocal(S.touches[io])
		local delta = p - d.start
		if delta.Magnitude * (1 / unitsPerPx()) > ToqueTelas.TAP_MOVE_PX then
			S.dragged = true
		end
		if S.dragged then
			local size = Carta.base(S.viewW, S.viewH) * S.zoomT
			S.uT, S.vT = Carta.clampCenter(d.u - delta.X / size, d.v - delta.Y / size, S.zoomT, S.viewW, S.viewH)
		end
	end
end

local function touchEnded(io: InputObject)
	if not S.touches[io] then
		return
	end
	S.touches[io] = nil
	local n = touchCount()
	if S.pinch then
		if n < 2 then
			S.pinch = nil
			-- sobrou um dedo: ele continua arrastando dali (sem pulo)
			local rest = next(S.touches)
			local toLocal = S.toLocal
			if rest and toLocal then
				S.drag = { start = toLocal(S.touches[rest]), u = S.uT, v = S.vT }
			end
		end
		if n == 0 then
			S.drag = nil
			task.defer(function()
				S.dragged = false
			end)
		end
		return
	end
	if n > 0 then
		return
	end
	local d = S.drag
	S.drag = nil
	if d and S.visible and not S.dragged and os.clock() - S.touchT0 <= 0.6 then
		touchTap(d.start)
	end
	task.defer(function()
		S.dragged = false
	end)
end

-- o GameUI ouve o toque na carta (ponto escolhido, alvo) para mostrar o botão de confirmar
function CartaView.setTouchCallback(fn: (() -> ())?)
	S.onTouch = fn
end

-- ponto ou alvo escolhido por toque (nil: nenhum)
function CartaView.touchPick(): InputMap.MagnetPoint?
	return S.touchPick
end

function CartaView.clearTouchPick()
	if S.touchPick then
		S.touchPick = nil
		CartaView.drawPoints()
	end
end

-- zoom por botão (toque: + e −), no meio da janela
function CartaView.zoomBy(f: number)
	zoomAt(S.zoomT * f, S.viewW / 2, S.viewH / 2)
end

function CartaView.bindMouse()
	UserInputService.InputChanged:Connect(function(io: InputObject)
		if not S.visible then
			return
		end
		if io.UserInputType == Enum.UserInputType.Touch then
			touchMoved(io)
		elseif io.UserInputType == Enum.UserInputType.MouseWheel then
			local ok, p = inside(UserInputService:GetMouseLocation())
			if ok then
				zoomAt(S.zoomT * (if io.Position.Z > 0 then 1.35 else 1 / 1.35), p.X, p.Y)
			end
		elseif io.UserInputType == Enum.UserInputType.MouseMovement then
			local ok, p = inside(UserInputService:GetMouseLocation())
			if ok then
				S.cursor = p
			end
			local d = S.drag
			if d then
				local delta = p - d.start
				if delta.Magnitude > 5 then
					S.dragged = true
				end
				if S.dragged then
					local size = Carta.base(S.viewW, S.viewH) * S.zoomT
					S.uT, S.vT =
						Carta.clampCenter(d.u - delta.X / size, d.v - delta.Y / size, S.zoomT, S.viewW, S.viewH)
				end
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(io: InputObject)
		if not S.visible then
			return
		end
		local t = io.UserInputType
		if t == Enum.UserInputType.Touch then
			touchBegan(io)
		elseif t == Enum.UserInputType.MouseButton1 then
			local ok, p = inside(UserInputService:GetMouseLocation())
			if ok then
				S.drag = { start = p, u = S.uT, v = S.vT }
				S.dragged = false
			end
		elseif t == Enum.UserInputType.Keyboard then
			S.keys[io.KeyCode.Name] = true
		elseif string.sub(t.Name, 1, 7) == "Gamepad" then
			local k = io.KeyCode
			if string.sub(k.Name, 1, 4) == "DPad" then
				S.dpad[k.Name] = true
				local step = 0.34
				local dx = if k == Enum.KeyCode.DPadLeft then -1 elseif k == Enum.KeyCode.DPadRight then 1 else 0
				local dy = if k == Enum.KeyCode.DPadUp then -1 elseif k == Enum.KeyCode.DPadDown then 1 else 0
				panPx(dx * S.viewW * step, dy * S.viewH * step)
			elseif k == Enum.KeyCode.ButtonL3 then
				CartaView.centerOnMe()
			elseif k == Enum.KeyCode.ButtonR3 then
				CartaView.fit()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(io: InputObject)
		local t = io.UserInputType
		if t == Enum.UserInputType.Touch then
			touchEnded(io)
		elseif t == Enum.UserInputType.MouseButton1 then
			local d = S.drag
			S.drag = nil
			if d and S.visible and not S.dragged and S.onClick then
				local u, v = Carta.pick(S.u, S.v, S.zoom, S.viewW, S.viewH, d.start.X, d.start.Y)
				if u >= 0 and v >= 0 and u <= 1 and v <= 1 then
					S.onClick(u, v)
				end
			end
			task.defer(function()
				S.dragged = false
			end)
		elseif t == Enum.UserInputType.Keyboard then
			S.keys[io.KeyCode.Name] = nil
		else
			S.dpad[io.KeyCode.Name] = nil
		end
	end)
end

function CartaView.centerOnMe()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local u, v = uv(root.Position.X, root.Position.Z)
		CartaView.goTo(u, v, math.max(S.zoomT, 2.5))
	end
end

function CartaView.setCallbacks(onSpawn: (pt: any) -> (), onClick: (u: number, v: number) -> ())
	S.onSpawn, S.onClick = onSpawn, onClick
end

-- ===== dados =====
function CartaView.setMatch(st: any)
	S.match = st
	CartaView.redraw()
end

function CartaView.setSpawns(list: { any })
	S.spawns = list or {}
	CartaView.drawPoints()
	paintKey()
end

function CartaView.setInserts(list: { any })
	S.inserts = list or {}
	CartaView.drawPoints()
end

function CartaView.setSquad(list: { any })
	S.squad = list or {}
	CartaView.drawSquad()
end

-- marcação do squad (Squad_Mark do servidor): ponto, ponto pela carta ou área de inimigo aproximada.
-- Iguais se juntam (no Studio a mesma área de inimigo saía repetida, uma em cima da outra): área de
-- inimigo a menos de MERGE_M de outra vira uma só (com os nomes de quem marcou); ponto do mesmo
-- autor troca o anterior. A marca do líder para o squad é o marcador guiado (Marcadores), não daqui.
local MERGE_M = 25
-- Olho de Águia (vantagem "mark"): a área de inimigo marcada por quem tem o passe dura mais para o
-- squad todo. O atributo Vant_mark fica no Player (replica para todos): acha o autor pelo nome.
local function markMult(from: string): number
	for _, p in Players:GetPlayers() do
		if p.DisplayName == from or p.Name == from then
			return Vantagens.mult(p, "mark")
		end
	end
	return 1
end
function CartaView.addMark(m: any)
	if type(m) ~= "table" or type(m.x) ~= "number" or type(m.z) ~= "number" or m.leader then
		return
	end
	local from = tostring(m.from)
	for _, mk in S.marks do
		local near = math.sqrt((mk.x - m.x) ^ 2 + (mk.z - m.z) ^ 2) * M < MERGE_M
		local same = if m.kind == "target"
			then mk.kind == "target" and near
			else mk.kind ~= "target" and mk.from == from
		if same then
			mk.x, mk.z, mk.r, mk.t = m.x, m.z, m.r, os.clock()
			mk.mult = math.max(mk.mult or 1, markMult(from))
			if not table.find(mk.froms, from) then
				table.insert(mk.froms, from)
			end
			mk.from = table.concat(mk.froms, ", ")
			if mk.w then
				mk.w:Destroy()
				mk.w = nil
			end
			CartaView.drawMarks()
			return
		end
	end
	table.insert(S.marks, {
		x = m.x,
		z = m.z,
		r = m.r,
		kind = m.kind,
		from = from,
		froms = { from },
		t = os.clock(),
		w = nil,
		mult = markMult(from),
	})
	while #S.marks > 24 do
		local old = table.remove(S.marks, 1)
		if old and old.w then
			old.w:Destroy()
		end
	end
	CartaView.drawMarks()
end

-- ===== desenho =====
local function signature(st: any): string
	local parts = { S.mode, tostring(myFaction()), tostring(st.mode), tostring(st.front), tostring(st.ended) }
	for i = 1, #st.owner do
		local p = st.points[i]
		table.insert(parts, string.format("%s%s%s", st.owner[i], tostring(st.active[i]), if p then p.name else "-"))
	end
	return table.concat(parts, "|")
end

-- retângulos de setor, fronteiras e frente (refeitos só quando muda dono, frente ou modo)
local function drawSectors(st: any)
	clearLayer("setores")
	clearLayer("linhas")
	local sect, lines = S.layers.setores, S.layers.linhas
	for _, s in MapConfig.Sectors do
		local owner = st.owner[s.id]
		local active = st.active[s.id]
		local color = ownerColor(owner)
		for _, r in Carta.rects(s.polygon) do
			local u0, v0 = uv(r.x0, r.z0)
			local u1, v1 = uv(r.x1, r.z1)
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = color
			f.BackgroundTransparency = if owner == "Neutral" then 0.94 elseif active then 0.84 else 0.9
			f.Position = UDim2.fromScale(u0, v0)
			f.Size = UDim2.fromScale(u1 - u0, v1 - v0)
			f.Name = "S" .. s.id
			f:SetAttribute("Sector", s.id)
			f.Parent = sect
		end
		-- nome do setor no alto da faixa, a lápis
		local xs = {}
		for i = 1, #s.polygon, 2 do
			table.insert(xs, s.polygon[i])
		end
		local cu = select(1, uv((math.min(table.unpack(xs)) + math.max(table.unpack(xs))) / 2, B.minZ))
		-- só o número do setor, grande; o dono é a cor (a legenda diz qual é qual); fora de jogo, apagado
		local t = label(sect, string.format("S%d", s.id), 24, color, F.TITLE)
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.new(cu, 0, 0, 30)
		t.TextTransparency = if active then 0 else 0.4
		t.TextStrokeColor3 = V.BG
		t.TextStrokeTransparency = 0.35
		-- o que é nosso vai por texto (a cor é a do lado, a mesma para os dois jogadores)
		if owner == myFaction() then
			local mine = label(sect, "NOSSO", 12, V.TEXT, F.TITLE_MED)
			mine.AnchorPoint = Vector2.new(0.5, 0)
			mine.Position = UDim2.new(cu, 0, 0, 58)
			mine.TextStrokeColor3 = V.BG
			mine.TextStrokeTransparency = 0.3
			mine.TextTransparency = if active then 0 else 0.4
		end
	end
	-- fronteiras: tracejado fino; entre donos diferentes, a linha de contato
	for a = 1, #MapConfig.Sectors - 1 do
		local b = a + 1
		local oa, ob = st.owner[a], st.owner[b]
		local contact = oa ~= ob
		local frontLine = st.mode == "Offensive" and st.front == a
		for _, e in Carta.boundary(MapConfig.Sectors, a, b) do
			local u1, v1 = uv(e.x1, e.z1)
			local u2, v2 = uv(e.x2, e.z2)
			if frontLine then
				pencil(lines, u1, v1, u2, v2, COR.frente, 4)
			elseif contact then
				-- traço duplo: a cor de cada lado do lado dele
				local du = if math.abs(u1 - u2) < 1e-6 then 0.0016 else 0
				local dv = if du == 0 then 0.0016 else 0
				pencil(lines, u1 - du, v1 - dv, u2 - du, v2 - dv, ownerColor(oa), 2)
				pencil(lines, u1 + du, v1 + dv, u2 + du, v2 + dv, ownerColor(ob), 2)
			else
				dashed(lines, u1, v1, u2, v2, COR.neutro, 1, 28)
			end
		end
		if frontLine then
			-- "FRENTE" com setas para oeste (os EUA atacam do leste)
			local segs = Carta.boundary(MapConfig.Sectors, a, b)
			local e = segs[1]
			for _, s2 in segs do
				if math.abs(s2.z2 - s2.z1) > math.abs(e.z2 - e.z1) then
					e = s2
				end
			end
			if e then
				local u1, v1 = uv(e.x1, e.z1)
				local _, v2 = uv(e.x2, e.z2)
				for k = 1, 3 do
					local vv = v1 + (v2 - v1) * k / 4
					local arrow = label(lines, "◄", 18, COR.us, Enum.Font.GothamBold) -- os EUA atacam
					arrow.AnchorPoint = Vector2.new(1, 0.5)
					arrow.Position = UDim2.new(u1, -6, vv, 0)
				end
				local tag = label(lines, "FRENTE", 16, COR.frente, F.TITLE)
				tag.AnchorPoint = Vector2.new(0, 0.5)
				tag.Rotation = -90
				tag.Position = UDim2.new(u1, 10, (v1 + v2) / 2, 0)
				tag.TextStrokeColor3 = V.BG
				tag.TextStrokeTransparency = 0.35
			end
		end
	end
end

-- objetivos: anel de captura (50 m), nome datilografado, barra de progresso e estado
local function drawObjectives(st: any)
	clearLayer("objetivos")
	table.clear(S.objWidgets)
	local layer = S.layers.objetivos
	local f = myFaction()
	local role, target = nil, nil
	if f then
		role, target = Front.objective(st.owner, st.active, f, st.capturing)
	end
	local r = MapConfig.CaptureRadiusStuds / (B.maxX - B.minX)
	for s, p in st.points do
		local active = st.active[s]
		local color = ownerColor(st.owner[s])
		local u, v = uv(p.x, p.z)
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(u, v)
		ring.Size = UDim2.fromScale(2 * r, 2 * r)
		ring.BackgroundColor3 = color
		ring.BackgroundTransparency = if active then 0.82 else 0.93
		corner(ring)
		local rs = stroke(ring, color, 2.5, if active then 0.05 else 0.55)
		local sz = Instance.new("UISizeConstraint")
		sz.MinSize = Vector2.new(16, 16)
		sz.Parent = ring
		ring.Parent = layer
		local dot = label(layer, "◆", 14, color, Enum.Font.GothamBold)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(u, v)
		-- ficha do objetivo: nome, barra e estado
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(u, 0, v, 14)
		card.AutomaticSize = Enum.AutomaticSize.XY
		card.Size = UDim2.new()
		card.BackgroundColor3 = V.PANEL
		card.BackgroundTransparency = if active then 0.1 else 0.4
		card.BorderSizePixel = 0
		corner(card, 3)
		stroke(card, color, 1.5, 0.15)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 4)
		pad.Parent = card
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 2)
		list.Parent = card
		card.Parent = layer
		local name = label(card, string.format("S%d · %s", s, UiKit.upper(p.name)), 13, V.TEXT, TYPE)
		name.LayoutOrder = 1
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(84, 5)
		bar.BackgroundColor3 = V.PANEL_3
		bar.BorderSizePixel = 0
		bar.LayoutOrder = 2
		bar.Visible = active
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.Parent = bar
		local mid = Instance.new("Frame")
		mid.BorderSizePixel = 0
		mid.BackgroundColor3 = V.DIM
		mid.Position = UDim2.new(0.5, 0, 0, -1)
		mid.Size = UDim2.new(0, 1, 1, 2)
		mid.Parent = bar
		bar.Parent = card
		-- estado só quando conta (disputa, captura, fora de jogo); o dono já é a cor
		local status = label(card, "", 12, V.DIM, HAND)
		status.LayoutOrder = 3
		status.Visible = false
		-- papel do time: ATACAR / DEFENDER, numa etiqueta cáqui ao lado
		if s == target and role then
			local tag = label(layer, if role == "attack" then "ATACAR" else "DEFENDER", 15, V.BG, F.TITLE)
			tag.AnchorPoint = Vector2.new(0, 1)
			tag.Position = UDim2.new(u, 12, v, -10)
			tag.BackgroundTransparency = 0
			tag.BackgroundColor3 = V.KHAKI
			corner(tag, 3)
			local tp = Instance.new("UIPadding")
			tp.PaddingLeft, tp.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
			tp.Parent = tag
		end
		S.objWidgets[s] = { ring = ring, stroke = rs, fill = fill, status = status, color = color, active = active }
	end
end

-- atualiza no lugar o que muda todo segundo: barra de progresso, estado e o pulso da disputa
local function updateObjectives(st: any)
	local f = myFaction()
	local sign = if f == "VC" then -1 else 1 -- progresso do ponto de vista de quem olha (+ = nosso)
	for s, w in S.objWidgets do
		local p = (st.progress[s] or 0) * sign
		w.fill.BackgroundColor3 = if p >= 0 then COR.us else COR.vc
		if p >= 0 then
			w.fill.Position = UDim2.fromScale(0.5, 0)
			w.fill.Size = UDim2.fromScale(0.5 * p, 1)
		else
			w.fill.Position = UDim2.fromScale(0.5 + 0.5 * p, 0)
			w.fill.Size = UDim2.fromScale(-0.5 * p, 1)
		end
		local cap = st.capturing and st.capturing[s]
		local contested = st.contested and st.contested[s]
		local owner = st.owner[s]
		local text, color = "", V.DIM
		if not w.active then
			text = if st.mode == "Offensive" and owner == "US" then "tomado" else "fora de jogo"
		elseif contested then
			text, color = "⚔ EM DISPUTA", V.KHAKI
		elseif cap and cap == f then
			text, color = if owner == f then "▲ reforçando" else "▲ tomando", V.TEXT
		elseif cap then
			text, color = if owner == f then "▼ sob ataque" else "▼ inimigo reforça", V.TEXT
		end
		w.status.Text = text
		w.status.TextColor3 = color
		w.status.Visible = text ~= ""
		w.contested = contested == true
	end
end

function CartaView.redraw()
	local st = S.match
	if not (S.mounted and st and st.owner and st.points) then
		return
	end
	local sig = signature(st)
	if sig ~= S.sig then
		S.sig = sig
		drawSectors(st)
		drawObjectives(st)
	end
	updateObjectives(st)
	if S.legendScore then
		CartaView.updateLegend()
	end
end

-- símbolo de cada tipo de ponto de inserção
local KIND = {
	hq = "QG",
	rally = "R",
	rally_captured = "R",
	garrison = "P",
	squad = "●", -- companheiro do squad: símbolo próprio (a bolinha do squad), com o nome sempre
}
-- LZ da inserção de helicóptero (EventosService: kind "rally", id "lz:<n>")
local function isLZ(pt: any): boolean
	return type(pt.id) == "string" and string.sub(pt.id, 1, 3) == "lz:"
end

local function pointGlyph(pt: any): string
	if pt.kind == "squad" then
		return KIND.squad
	end
	if type(pt.id) == "string" then
		if isLZ(pt) then
			return "LZ"
		elseif string.sub(pt.id, 1, 8) == "forward:" then
			return "RA"
		elseif string.sub(pt.id, 1, 6) == "squad:" then
			return "SQ"
		elseif string.sub(pt.id, 1, 7) == "tunnel:" then
			return "T"
		elseif pt.id == "inplace" then
			return "×"
		end
	end
	return KIND[pt.kind or ""] or "R"
end

-- Nascer num companheiro do squad (Spawn_State, formato do servidor: id "mate:<UserId>" ou
-- "mate:bot:<n>", kind "squad", name = o companheiro, userId, bot, ready, squad = true). O ponto anda
-- com ele: a posição muda sem redesenhar o ponto (só o lugar).
local function squadMate(pt: any): string?
	if pt.kind ~= "squad" then
		return nil
	end
	local n = pt.name
	return if type(n) == "string" and n ~= "" then n else nil
end

-- pronto de verdade: sem bloqueio, sem espera e (quando o servidor manda) ready
local function pointReady(pt: any): boolean
	return not pt.blocked and (pt.wait or 0) <= 0 and pt.ready ~= false
end

-- ===== túneis do VC =====
-- Só para quem é do VC (regra do dono: só o VC usa os túneis). Para os EUA a camada fica vazia:
-- nada é desenhado, nem escondido. Galerias tracejadas, bocas (E1..E5) e, no ponto de inserção do
-- túnel em foco, para onde ele leva (Shared/TunnelLinks.links()).
local function tunnelCenter(): (number?, number?)
	for _, l in MapConfig.Locations or {} do
		if l.name == "An Cường (2)" then
			return l.x, l.z
		end
	end
	return nil, nil
end

local function drawTunnels()
	if not S.mounted then
		return
	end
	local f = myFaction()
	local sig = tostring(f)
	if sig == S.tunnelSig then
		return
	end
	S.tunnelSig = sig
	clearLayer("tuneis")
	table.clear(S.tunnelDest)
	paintKey()
	if f ~= "VC" then
		return
	end
	local cx, cz = tunnelCenter()
	if not (cx and cz) then
		return
	end
	local layer = S.layers.tuneis
	-- galerias: cada aresta da rede uma vez (a adjacência traz as duas mãos)
	local done: { [string]: boolean } = {}
	for a, list in TunnelLinks.adjacency() do
		for _, nb in list do
			local k = if a < nb.id then a .. "|" .. nb.id else nb.id .. "|" .. a
			if not done[k] then
				done[k] = true
				local pts = TunnelLinks.toWorld({ a, nb.id }, cx, cz)
				local u1, v1 = uv(pts[1].x, pts[1].z)
				local u2, v2 = uv(pts[2].x, pts[2].z)
				dashed(layer, u1, v1, u2, v2, COR.tunel, 2, 12)
			end
		end
	end
	-- bocas
	for _, en in TunnelLinks.entrances() do
		local p = TunnelLinks.toWorld({ en.id }, cx, cz)[1]
		local u, v = uv(p.x, p.z)
		local dot = Instance.new("Frame")
		dot.Name = en.id
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(u, v)
		dot.Size = UDim2.fromOffset(9, 9)
		dot.BackgroundColor3 = COR.tunel
		dot.BorderSizePixel = 0
		corner(dot, 2)
		stroke(dot, V.BG, 1.5)
		dot.Parent = layer
		local t = label(layer, en.id, 12, COR.tunel, F.TITLE)
		t.AnchorPoint = Vector2.new(0, 0.5)
		t.Position = UDim2.new(u, 8, v, 0)
		t.TextStrokeColor3 = V.BG
		t.TextStrokeTransparency = 0.3
	end
	-- destinos de cada boca (do mais perto ao mais longe)
	for id, list in TunnelLinks.links() do
		local to = {}
		for _, l in list do
			table.insert(to, l.to)
		end
		S.tunnelDest[id] = to
	end
end

-- ===== eventos da partida (EventosVisual) =====
-- O raio de cada evento na cor da fase (aviso, em curso, carga armada, janela, fim) e o ícone no
-- meio. Um círculo por evento, reaproveitado; muda só quando o EventosVisual avisa.
local function drawEvents()
	if not S.mounted then
		return
	end
	local layer = S.layers.eventos
	local seen: { [string]: boolean } = {}
	local spanX, spanZ = B.maxX - B.minX, B.maxZ - B.minZ
	for _, ev in EventosVisual.list() do
		seen[ev.key] = true
		local w = S.eventWidgets[ev.key]
		if not w then
			local ring = Instance.new("Frame")
			ring.Name = ev.key
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.BorderSizePixel = 0
			corner(ring)
			local st = stroke(ring, V.KHAKI, 2, 0.1)
			local lim = Instance.new("UISizeConstraint")
			lim.MinSize = Vector2.new(16, 16)
			lim.Parent = ring
			ring.Parent = layer
			local icon = label(layer, "", 16, V.TEXT, Enum.Font.GothamBold)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.TextStrokeColor3 = V.BG
			icon.TextStrokeTransparency = 0.2
			w = { ring = ring, stroke = st, icon = icon }
			S.eventWidgets[ev.key] = w
		end
		local u, v = uv(ev.x, ev.z)
		local r = EventosVisual.radiusStuds(ev)
		local c = EventosVisual.color(ev.fase)
		local over = ev.fase == "fim"
		w.ring.Position = UDim2.fromScale(u, v)
		w.ring.Size = UDim2.fromScale(2 * r / spanX, 2 * r / spanZ)
		w.ring.BackgroundColor3 = c
		w.ring.BackgroundTransparency = if over then 0.94 else 0.82
		w.stroke.Color = c
		w.stroke.Transparency = if over then 0.6 else 0.1
		w.icon.Position = UDim2.fromScale(u, v)
		w.icon.Text = EventosVisual.icon(ev.id)
		w.icon.TextTransparency = if over then 0.5 else 0
	end
	for key, w in S.eventWidgets do
		if not seen[key] then
			w.ring:Destroy()
			w.icon:Destroy()
			S.eventWidgets[key] = nil
		end
	end
end

-- ===== ponto escolhido ao abrir a carta de inserção =====
-- O ponto PRONTO mais perto do objetivo do time (Front.objective, como o HUD): a carta abre nele (o
-- ímã do controle gruda; no mouse ele fica realçado). Nunca nasce sozinho: só leva a vista e o foco.
local function objectiveXZ(): (number?, number?)
	local st = S.match
	local f = myFaction()
	if not (st and f and type(st.owner) == "table" and type(st.points) == "table") then
		return nil, nil
	end
	local cap: { [number]: string } = {}
	if type(st.capturing) == "table" then
		for i, c in st.capturing do
			if type(c) == "string" and c ~= "" then
				cap[i] = c
			end
		end
	end
	local ok, _, target = pcall(Front.objective, st.owner, st.active or {}, f, cap)
	local p = if ok and target then st.points[target] else nil
	if type(p) == "table" and type(p.x) == "number" and type(p.z) == "number" then
		return p.x, p.z
	end
	return nil, nil
end

local function preferredPoint(list: { any }): string?
	local ox, oz = objectiveXZ()
	if not (ox and oz) then
		return nil
	end
	local best: string? = nil
	local bestD = math.huge
	for _, pt in list do
		-- o "onde caiu" custa créditos ou Robux: nunca é a sugestão
		if pointReady(pt) and pt.id ~= "inplace" and type(pt.x) == "number" and type(pt.z) == "number" then
			local d = (pt.x - ox) ^ 2 + (pt.z - oz) ^ 2
			if d < bestD then
				best, bestD = tostring(pt.id), d
			end
		end
	end
	return best
end

-- texto do ponto (nome e estado); o túnel em foco diz para onde leva
local function pointText(pt: any, spawnMode: boolean): string
	local mate = squadMate(pt)
	local name = if mate then mate else tostring(pt.name)
	if not spawnMode then
		return Acabamento.viet(name)
	end
	local state = if pt.blocked
		then (pt.why or "bloqueado")
		elseif (pt.wait or 0) > 0 then string.format("%d s", pt.wait)
		elseif pt.ready == false then (pt.why or "espere")
		else "PRONTO"
	local text = string.format("%s · %s", name, state)
	local tid = if type(pt.id) == "string" and string.sub(pt.id, 1, 7) == "tunnel:" then string.sub(pt.id, 8) else nil
	local dest = tid and S.tunnelDest[tid]
	if dest and #dest > 0 then
		-- 2ª linha à parte: o Lang traduz linha a linha ("leva a %s" é um modelo inteiro)
		text = string.format("%s\n%s", text, string.format("leva a %s", table.concat(dest, ", ")))
	end
	return Acabamento.viet(text)
end

local function stateColor(pt: any, spawnMode: boolean): Color3
	if not spawnMode then
		return V.KHAKI
	elseif pt.blocked then
		return COR.bloqueado
	elseif not pointReady(pt) then
		return COR.espera
	end
	return if pt.kind == "squad" then COR.squad elseif isLZ(pt) then COR.lz else COR.pronto
end

-- pontos de inserção: na carta de spawn com espera e PRONTO (botões); em campo, só o símbolo
function CartaView.drawPoints()
	if not S.mounted then
		return
	end
	drawTunnels()
	local spawnMode = S.mode == "spawn"
	local list: { any } = if spawnMode then S.spawns else S.inserts
	local sigParts = { S.mode }
	for _, pt in list do
		-- o companheiro do squad anda: a posição dele fica fora da assinatura (muda só o lugar)
		if pt.kind == "squad" then
			table.insert(sigParts, string.format("%s:squad", tostring(pt.id)))
		else
			table.insert(
				sigParts,
				string.format("%s@%d,%d:%s", tostring(pt.id), math.floor(pt.x), math.floor(pt.z), tostring(pt.kind))
			)
		end
	end
	local sig = table.concat(sigParts, "|")
	if sig ~= S.spawnSig then
		S.spawnSig = sig
		clearLayer("pontos")
		table.clear(S.spawnWidgets)
		local layer = S.layers.pontos
		for _, pt in list do
			local u, v = uv(pt.x, pt.z)
			local holder = Instance.new("TextButton")
			holder.Name = "Ponto"
			holder.Text = ""
			holder.AutoButtonColor = false
			holder.Selectable = false -- no controle, o cursor com ímã escolhe
			holder.AnchorPoint = Vector2.new(0.5, 1)
			holder.Position = UDim2.new(u, 0, v, -4)
			holder.AutomaticSize = Enum.AutomaticSize.XY
			holder.Size = UDim2.new()
			holder.BackgroundTransparency = 1
			holder.BorderSizePixel = 0
			-- símbolo forte: letra escura sobre a cor do estado, contorno escuro (lê nos dois fundos)
			local g = pointGlyph(pt)
			local glyph = label(holder, g, 14, V.BG, if string.find(g, "^%a+$") then F.TITLE else Enum.Font.GothamBold)
			glyph.AutomaticSize = Enum.AutomaticSize.X
			glyph.Size = UDim2.fromOffset(0, S.ts(22))
			glyph.TextXAlignment = Enum.TextXAlignment.Center
			glyph.BackgroundTransparency = 0
			glyph.BackgroundColor3 = stateColor(pt, spawnMode)
			corner(glyph, 3)
			local edge = stroke(glyph, V.BG, 1.5, 0)
			local gp = Instance.new("UIPadding")
			gp.PaddingLeft, gp.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
			gp.Parent = glyph
			-- nome (e a espera) numa etiqueta escura à direita do símbolo, fora do botão: aparecer não
			-- mexe no símbolo sob o mouse (senão ele pulava e o realce piscava). Só no ponto em foco,
			-- sob o mouse, com zoom ou no companheiro do squad (todos abertos trombavam com os objetivos)
			local text = label(layer, "", 13, V.TEXT, F.TITLE_MED)
			text.AnchorPoint = Vector2.new(0, 1)
			text.Position = UDim2.new(u, S.ts(22), v, -4)
			text.Visible = false
			pcall(function()
				text.Interactable = false
			end)
			text.BackgroundTransparency = 0.08
			text.BackgroundColor3 = V.PANEL
			text.TextXAlignment = Enum.TextXAlignment.Left
			corner(text, 3)
			local tpad = Instance.new("UIPadding")
			tpad.PaddingLeft, tpad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
			tpad.PaddingTop, tpad.PaddingBottom = UDim.new(0, 2), UDim.new(0, 2)
			tpad.Parent = text
			holder.Parent = layer
			-- pino no chão do ponto
			local pin = Instance.new("Frame")
			pin.AnchorPoint = Vector2.new(0.5, 0.5)
			pin.Position = UDim2.fromScale(u, v)
			pin.Size = UDim2.fromOffset(8, 8)
			pin.BackgroundColor3 = stateColor(pt, spawnMode)
			pin.BorderSizePixel = 0
			corner(pin)
			stroke(pin, V.BG, 1.5)
			pin.Parent = layer
			local id = tostring(pt.id)
			holder.Activated:Connect(function()
				local w = S.spawnWidgets[id]
				if ToqueUi.active() then
					-- toque: só escolhe (o botão de inserir do GameUI mostra a espera e confirma)
					if w and not S.dragged and spawnMode then
						local pu, pv = uv(w.pt.x, w.pt.z)
						S.touchPick = { id = "spawn:" .. id, x = pu, y = pv }
						CartaView.drawPoints()
						local cb = S.onTouch
						if cb then
							task.spawn(cb)
						end
					end
					return
				end
				if w and not S.dragged and spawnMode and S.onSpawn then
					S.onSpawn(w.pt) -- o ponto com a espera de agora (atualizado a cada segundo)
				end
			end)
			holder.MouseEnter:Connect(function()
				S.hoverPoint = id
				CartaView.drawPoints()
			end)
			holder.MouseLeave:Connect(function()
				if S.hoverPoint == id then
					S.hoverPoint = nil
					CartaView.drawPoints()
				end
			end)
			S.spawnWidgets[id] =
				{ holder = holder, text = text, edge = edge, glyph = glyph, pin = pin, scale = nil, pt = pt }
		end
	end
	-- o ponto sugerido (pronto, mais perto do objetivo): a carta de inserção abre nele, uma vez por
	-- abertura (os pontos podem chegar depois de abrir: vale quando chegarem)
	S.prefer = if spawnMode then preferredPoint(list) else nil
	if spawnMode and S.visible and not S.preferShown and S.prefer then
		for _, pt in list do
			if tostring(pt.id) == S.prefer then
				S.preferShown = true
				local u, v = uv(pt.x, pt.z)
				CartaView.goTo(u, v, math.max(S.zoomT, 1.5))
				break
			end
		end
	end
	-- textos e cores que mudam todo segundo (espera)
	for _, pt in list do
		local w = S.spawnWidgets[tostring(pt.id)]
		if w then
			w.pt = pt
			if pt.kind == "squad" then
				-- o companheiro andou: só o lugar muda (nada é recriado)
				local u, v = uv(pt.x, pt.z)
				w.holder.Position = UDim2.new(u, 0, v, -4)
				w.pin.Position = UDim2.fromScale(u, v)
				w.text.Position = UDim2.new(u, S.ts(22), v, -4)
			end
			w.text.Text = pointText(pt, spawnMode)
			w.text.TextColor3 = if spawnMode and pt.blocked then Color3.fromRGB(240, 150, 130) else V.TEXT
			local id = tostring(pt.id)
			-- em foco (ímã), sob o mouse ou, sem nenhum dos dois, o sugerido
			local hot = (S.focused ~= nil and S.focused.id == "spawn:" .. id)
				or S.hoverPoint == id
				or (S.focused == nil and S.hoverPoint == nil and S.prefer == id)
			w.edge.Color = if hot then V.BRASS else V.BG
			w.edge.Thickness = if hot then 2.5 else 1.5
			w.text.Visible = hot or S.zoom >= 2 or (spawnMode and squadMate(pt) ~= nil)
			-- o em foco passa por cima dos vizinhos e das fichas
			w.holder.ZIndex = if hot then 3 else 1
			w.text.ZIndex = if hot then 4 else 2
			local c = stateColor(pt, spawnMode)
			w.glyph.BackgroundColor3 = c
			w.pin.BackgroundColor3 = c
		end
	end
end

-- ícone de quem fala no squad da carta: 🔊 de perto, 📻 pelo rádio (só aliados: VozEstado)
local function paintVoice(w: any, talking: boolean, radio: boolean)
	local v = w.voice :: TextLabel?
	if v then
		v.Visible = talking or radio
		v.Text = if radio then "📻" else "🔊"
	end
end
VozEstado.Changed:Connect(function(uid: number, talking: boolean, radio: boolean)
	local w = S.squadWidgets[uid]
	if w then
		paintVoice(w, talking, radio)
	end
end)

-- o próprio squad (FrontService, a cada 2 s): bolinha de latão com o nome; líder com estrela
function CartaView.drawSquad()
	if not S.mounted then
		return
	end
	local layer = S.layers.squad
	local seen: { [number]: boolean } = {}
	for _, m in S.squad do
		if m.id == player.UserId then
			continue
		end
		seen[m.id] = true
		local w = S.squadWidgets[m.id]
		if not w then
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Size = UDim2.fromOffset(12, 12)
			dot.BackgroundColor3 = COR.squad
			dot.BorderSizePixel = 0
			corner(dot)
			stroke(dot, V.BG, 2)
			dot.Parent = layer
			local name = label(dot, "", 13, V.TEXT, F.TITLE_MED)
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.new(1, 5, 0.5, 0)
			name.TextStrokeColor3 = V.BG
			name.TextStrokeTransparency = 0.2
			-- quem fala (VozEstado): o alto-falante à esquerda da bolinha; muda pelo evento
			local voice = label(dot, "🔊", 13, V.TEXT, Enum.Font.GothamBold)
			voice.AnchorPoint = Vector2.new(1, 0.5)
			voice.Position = UDim2.new(0, -4, 0.5, 0)
			voice.Visible = false
			w = { dot = dot, name = name, voice = voice }
			S.squadWidgets[m.id] = w
			local talking, radio = VozEstado.get(tonumber(m.id) or 0)
			paintVoice(w, talking, radio)
		end
		local u, v = uv(m.x, m.z)
		w.dot.Position = UDim2.fromScale(u, v)
		-- caído: cinza com "(caído)" no nome (vermelho é a cor do VC)
		w.dot.BackgroundColor3 = if m.downed then V.MUTED else COR.squad
		local nm = tostring(m.name)
		if m.role == "squad_leader" then
			nm = string.format("★ %s", nm)
		end
		w.name.Text = if m.downed then string.format("%s (caído)", nm) else nm
	end
	for id, w in S.squadWidgets do
		if not seen[id] then
			w.dot:Destroy()
			S.squadWidgets[id] = nil
		end
	end
end

-- marcações do squad: X cinza (ponto) e círculo vermelho (área aproximada do inimigo marcada pelo squad)
function CartaView.drawMarks()
	if not S.mounted then
		return
	end
	local layer = S.layers.marcas
	-- o inimigo marcado é do outro lado: a cor dele (fixa por lado); "inimigo" vai no texto
	local enemy = if myFaction() == "VC" then COR.us else COR.vc
	for _, mk in S.marks do
		if mk.w then
			continue
		end
		local u, v = uv(mk.x, mk.z)
		-- marcas perto umas das outras: o rótulo sobe um degrau por vizinha já desenhada (não se
		-- empilham uma em cima da outra)
		local k = 0
		for _, o in S.marks do
			if o ~= mk and o.w and math.sqrt((o.x - mk.x) ^ 2 + (o.z - mk.z) ^ 2) * M < 40 then
				k += 1
			end
		end
		local holder = frame(layer, "Marca")
		holder.Size = UDim2.fromScale(1, 1)
		if mk.kind == "target" and type(mk.r) == "number" then
			local rr = mk.r / M / (B.maxX - B.minX)
			local ring = Instance.new("Frame")
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(u, v)
			ring.Size = UDim2.fromScale(2 * rr, 2 * rr)
			ring.BackgroundColor3 = enemy
			ring.BackgroundTransparency = 0.82
			corner(ring)
			local st = stroke(ring, enemy, 2, 0.1)
			st.LineJoinMode = Enum.LineJoinMode.Round
			local sz = Instance.new("UISizeConstraint")
			sz.MinSize = Vector2.new(14, 14)
			sz.Parent = ring
			ring.Parent = holder
			local t = label(
				holder,
				string.format("≈ inimigo ±%d m · %s", math.floor(mk.r + 0.5), tostring(mk.from)),
				13,
				V.TEXT,
				HAND
			)
			t.AnchorPoint = Vector2.new(0.5, 1)
			t.Position = UDim2.new(u, 0, v, -10 - k * S.ts(16))
			t.TextStrokeColor3 = V.BG
			t.TextStrokeTransparency = 0.3
		else
			pencil(holder, u - 0.004, v - 0.004, u + 0.004, v + 0.004, COR.neutro, 2.5)
			pencil(holder, u - 0.004, v + 0.004, u + 0.004, v - 0.004, COR.neutro, 2.5)
			local t = label(holder, tostring(mk.from), 13, V.TEXT, HAND)
			t.AnchorPoint = Vector2.new(0, 0.5)
			t.Position = UDim2.new(u, 10, v, k * S.ts(16))
			t.TextStrokeColor3 = V.BG
			t.TextStrokeTransparency = 0.3
		end
		holder.Rotation = 0
		mk.w = holder
	end
end

local function fadeMarks()
	local now = os.clock()
	for i = #S.marks, 1, -1 do
		local mk = S.marks[i]
		-- a área de inimigo dura mais com o Olho de Águia de quem marcou (mult, 1 sem o passe)
		local ttl = if mk.kind == "target" then Comms.MARK_TTL_S * (mk.mult or 1) else 90
		local a = math.clamp(1 - (now - mk.t) / ttl, 0, 1)
		if a <= 0 then
			if mk.w then
				mk.w:Destroy()
			end
			table.remove(S.marks, i)
		elseif mk.w then
			for _, d in mk.w:GetDescendants() do
				if d:IsA("TextLabel") then
					d.TextTransparency = 1 - a
				elseif d:IsA("UIStroke") then
					d.Transparency = 1 - 0.9 * a
				end
			end
		end
	end
end

-- marcadores guiados (Marcadores: a sua marca e a do líder para o squad), reaproveitados
local function drawWaypoints()
	local layer = S.layers.marcas
	local now = Marcadores.waypoints()
	for _, k in { "mine", "lead" } do
		local wpt = (now :: any)[k]
		local f = S.wp[k]
		if wpt and not f then
			local nf = Instance.new("Frame")
			nf.Name = if k == "mine" then "SuaMarca" else "MarcaDoLider"
			nf.AnchorPoint = Vector2.new(0.5, 0.5)
			nf.Size = UDim2.fromOffset(26, 26)
			nf.BackgroundTransparency = 1
			nf.ZIndex = 3
			nf.Parent = layer
			local g = label(
				nf,
				if k == "mine" then "◆" else "★",
				22,
				if k == "mine" then COR.mine else COR.lead,
				Enum.Font.GothamBold
			)
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Position = UDim2.fromScale(0.5, 0.5)
			g.TextStrokeColor3 = V.BG
			g.TextStrokeTransparency = 0
			g.ZIndex = 3
			local t = label(nf, "", 13, V.TEXT, F.TITLE_MED)
			t.Name = "Nome"
			t.AnchorPoint = Vector2.new(0.5, 0)
			t.Position = UDim2.new(0.5, 0, 1, 0)
			t.TextStrokeColor3 = V.BG
			t.TextStrokeTransparency = 0.2
			t.ZIndex = 3
			S.wp[k] = nf
			f = nf
		end
		if f then
			f.Visible = wpt ~= nil
			if wpt then
				local u, v = uv(wpt.x, wpt.z)
				f.Position = UDim2.fromScale(u, v)
				local t = f:FindFirstChild("Nome") :: TextLabel?
				if t then
					t.Text = if k == "lead" and wpt.from then tostring(wpt.from) else ""
				end
			end
		end
	end
end

-- D-108: caixas de munição do Suporte do próprio lado (Workspace.CaixasMunicao): ▣ latão com o
-- estoque, a cada quadro da carta (são poucas: uma por suporte)
local caixaW: { [Instance]: Frame } = {}
function CartaView.drawCaixas()
	if not S.mounted then
		return
	end
	local layer = S.layers.marcas
	local folder = Workspace:FindFirstChild("CaixasMunicao")
	local mine = myFaction()
	local seen: { [Instance]: boolean } = {}
	if folder and mine then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Faction") == mine then
				seen[m] = true
				local f = caixaW[m]
				if not f then
					local nf = Instance.new("Frame")
					nf.Name = "CaixaMunicao"
					nf.AnchorPoint = Vector2.new(0.5, 0.5)
					nf.Size = UDim2.fromOffset(20, 20)
					nf.BackgroundTransparency = 1
					nf.ZIndex = 3
					nf.Parent = layer
					local g = label(nf, "▣", 17, COR.latao, Enum.Font.GothamBold)
					g.AnchorPoint = Vector2.new(0.5, 0.5)
					g.Position = UDim2.fromScale(0.5, 0.5)
					g.TextStrokeColor3 = V.BG
					g.TextStrokeTransparency = 0
					g.ZIndex = 3
					local t = label(nf, "", 12, V.TEXT, F.TITLE_MED)
					t.Name = "Estoque"
					t.AnchorPoint = Vector2.new(0, 0.5)
					t.Position = UDim2.new(1, 2, 0.5, 0)
					t.TextStrokeColor3 = V.BG
					t.TextStrokeTransparency = 0.2
					t.ZIndex = 3
					caixaW[m] = nf
					f = nf
				end
				local p = (m :: Model):GetPivot().Position
				local u, v = uv(p.X, p.Z)
				local fr = f :: Frame
				fr.Position = UDim2.fromScale(u, v)
				local t = fr:FindFirstChild("Estoque") :: TextLabel?
				if t then
					t.Text = string.format("%d", tonumber(m:GetAttribute("Stock")) or 0)
				end
			end
		end
	end
	for m, f in caixaW do
		if not seen[m] then
			f:Destroy()
			caixaW[m] = nil
		end
	end
end

-- você: ponto com a seta do rumo (para onde a câmera olha)
local function drawMe()
	local layer = S.layers.voce
	if not S.me then
		local me = Instance.new("Frame")
		me.Name = "Voce"
		me.AnchorPoint = Vector2.new(0.5, 0.5)
		me.Size = UDim2.fromOffset(30, 30)
		me.BackgroundTransparency = 1
		me.Parent = layer
		local halo = Instance.new("Frame")
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.5)
		halo.Size = UDim2.fromOffset(16, 16)
		halo.BackgroundColor3 = COR.me
		halo.BorderSizePixel = 0
		corner(halo)
		stroke(halo, COR.prancheta, 2)
		halo.Parent = me
		local arrow = label(me, "▲", 20, COR.prancheta, Enum.Font.GothamBold)
		arrow.AutomaticSize = Enum.AutomaticSize.None
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.Position = UDim2.fromScale(0.5, 0.5)
		arrow.Size = UDim2.fromOffset(30, 30)
		arrow.TextStrokeColor3 = COR.me
		arrow.TextStrokeTransparency = 0
		arrow.ZIndex = 2
		S.me, S.meArrow = me, arrow
		local tag = label(me, "VOCÊ", 13, V.BRASS, F.TITLE)
		tag.AnchorPoint = Vector2.new(0.5, 0)
		tag.Position = UDim2.new(0.5, 0, 1, 0)
		tag.TextStrokeColor3 = V.BG
		tag.TextStrokeTransparency = 0.15
		local p = TweenService:Create(
			halo,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 0.35 }
		)
		p:Play()
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local me = S.me :: Frame
	me.Visible = root ~= nil and hum ~= nil and hum.Health > 0
	if root then
		local u, v = uv(root.Position.X, root.Position.Z)
		me.Position = UDim2.fromScale(u, v)
		local cam = Workspace.CurrentCamera
		local look = if cam then cam.CFrame.LookVector else root.CFrame.LookVector
		local arrow = S.meArrow :: TextLabel
		arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end
end

-- ímã do controle: pontos de inserção (carta de spawn) e objetivos
local function magnetPoints(): { InputMap.MagnetPoint }
	local pts = {}
	if S.mode == "spawn" then
		for _, pt in S.spawns do
			local u, v = uv(pt.x, pt.z)
			table.insert(pts, { id = "spawn:" .. tostring(pt.id), x = u, y = v })
		end
	end
	local st = S.match
	if st and st.points then
		for s, sp in st.points do
			local u, v = uv(sp.x, sp.z)
			table.insert(pts, { id = "sp:" .. s, x = u, y = v })
		end
	end
	return pts
end

-- ===== quadro a quadro =====
-- gamepad: o GameUI passa se o controle está ativo e livre (sem menu do Roblox nem desconexão)
function CartaView.step(dt: number, pad: boolean)
	if not (S.mounted and S.visible) then
		return
	end
	local W, H = S.viewW, S.viewH
	if pad then
		-- analógico esquerdo: cursor na tela; empurrando na borda, a carta anda
		local mv = Input.move()
		local speed = H * 0.75
		local c = S.cursor + Vector2.new(mv.X, -mv.Y) * speed * dt
		local m = 0.1
		local ex = math.max(0, c.X - W * (1 - m)) + math.min(0, c.X - W * m)
		local ey = math.max(0, c.Y - H * (1 - m)) + math.min(0, c.Y - H * m)
		if ex ~= 0 or ey ~= 0 then
			panPx(ex * 0.9, ey * 0.9)
		end
		S.cursor = Vector2.new(math.clamp(c.X, W * m, W * (1 - m)), math.clamp(c.Y, H * m, H * (1 - m)))
		-- analógico direito: arrasta a carta
		local r = Input.stickRaw("right")
		local rx, ry = InputMap.radialDeadzone(r.X, r.Y, 0.18, 0.95)
		if rx ~= 0 or ry ~= 0 then
			panPx(rx * W * 1.1 * dt, -ry * H * 1.1 * dt)
		end
		-- gatilhos: zoom no cursor (RT aproxima, LT afasta)
		local z = Input.trigger("right") - Input.trigger("left")
		if math.abs(z) > 0.02 then
			zoomAt(S.zoomT * math.exp(z * dt * 2.4), S.cursor.X, S.cursor.Y)
		end
	end
	-- teclado: setas arrastam, + e - dão zoom
	local k = S.keys
	local kx = (if k.Right then 1 else 0) - (if k.Left then 1 else 0)
	local ky = (if k.Down then 1 else 0) - (if k.Up then 1 else 0)
	if kx ~= 0 or ky ~= 0 then
		panPx(kx * W * dt, ky * H * dt)
	end
	local kz = (if k.Equals or k.KeypadPlus then 1 else 0) - (if k.Minus or k.KeypadMinus then 1 else 0)
	if kz ~= 0 then
		zoomAt(S.zoomT * math.exp(kz * dt * 2), S.cursor.X, S.cursor.Y)
	end
	-- suavização (zoom e centro seguem o alvo; arrastando com o mouse, quase direto)
	local a = 1 - math.exp(-dt * (if S.drag and S.dragged then 30 else 12))
	local before = S.zoom
	S.zoom += (S.zoomT - S.zoom) * a
	S.u += (S.uT - S.u) * a
	S.v += (S.vT - S.v) * a
	if math.abs(S.zoomT - S.zoom) < 1e-4 then
		S.zoom = S.zoomT
	end
	S.u, S.v = Carta.clampCenter(S.u, S.v, S.zoom, W, H)
	local x0, y0, size = Carta.layout(S.u, S.v, S.zoom, W, H)
	local sheet = S.sheet :: Frame
	sheet.Position = UDim2.fromOffset(x0 + size / 2, y0 + size / 2) -- âncora no meio: abre e gira pelo centro
	sheet.Size = UDim2.fromOffset(size, size)
	if (before < 2) ~= (S.zoom < 2) then
		CartaView.drawPoints() -- com zoom, os nomes de todos os pontos aparecem (só muda a visibilidade)
	end
	-- ímã (controle) e realce
	local f: InputMap.MagnetPoint? = nil
	if pad then
		S.touchPick = nil
		local cu, cv = Carta.pick(S.u, S.v, S.zoom, W, H, S.cursor.X, S.cursor.Y)
		f = InputMap.magnet(cu, cv, magnetPoints(), 0.03 / S.zoom)
	elseif S.touchPick then
		f = S.touchPick -- toque: o ponto (ou o alvo) escolhido fica em foco até outro toque
	end
	if (f and f.id) ~= (S.focused and S.focused.id) then
		S.focused = f
		CartaView.drawPoints()
	end
	-- escala gráfica e zoom
	local mPerPx = SIDE_M / size
	local meters, px = Carta.scaleBar(mPerPx, 140)
	S.hud.bar.Size = UDim2.fromOffset(px, 6)
	S.hud.barText.Text = if meters >= 1000
		then string.format("%d km", meters // 1000)
		else string.format("%d m", meters)
	S.hud.zoom.Text = string.format("×%.1f", S.zoom)
	-- disputa pisca devagar
	S.pulseT += dt
	local pulse = 0.5 + 0.5 * math.sin(S.pulseT * 4)
	for _, w in S.objWidgets do
		if w.contested then
			w.ring.BackgroundTransparency = 0.6 + 0.3 * pulse
			w.stroke.Transparency = 0.4 * pulse
		end
	end
	fadeMarks()
	drawWaypoints()
	CartaView.drawCaixas()
	drawMe()
end

-- posição do cursor na janela (para o anel do controle) e a grade sob ele
function CartaView.cursorPx(): Vector2
	local f = S.focused
	if f then
		local x0, y0, size = Carta.layout(S.u, S.v, S.zoom, S.viewW, S.viewH)
		return Vector2.new(x0 + f.x * size, y0 + f.y * size)
	end
	return S.cursor
end

function CartaView.cursorGrid(): string
	local u, v = CartaView.cursorUV()
	local x, z = Carta.fromUV(B, math.clamp(u, 0, 1), math.clamp(v, 0, 1))
	return FireSupport.localToGrid(x, z, MapConfig.GridOrigin1965, M, 6)
end

-- ===== abrir e fechar =====
function CartaView.setVisible(on: boolean)
	if on == S.visible then
		return
	end
	S.visible = on
	if not S.mounted then
		return
	end
	local flash = S.hud.flash :: Frame
	local scale = S.hud.scale :: UIScale
	if on then
		-- a carta entra um pouco menor e assenta, saindo de um véu escuro (0,3 s)
		S.zoom = S.zoomT * 0.94
		scale.Scale = 0.97
		flash.BackgroundTransparency = 0.2
		local sheet = S.sheet :: Frame
		sheet.Rotation = 0
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(scale, info, { Scale = 1 }):Play()
		TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		S.spawnSig = ""
		S.preferShown = false
		CartaView.drawPoints()
		CartaView.drawMarks()
		drawEvents()
		paintKey()
	else
		S.drag = nil
		S.pinch = nil
		S.touchPick = nil
		table.clear(S.touches)
	end
end

-- fecha a carta (encolhe e escurece): o GameUI esconde a janela depois de `tempo` s
function CartaView.foldOut(tempo: number)
	if not S.mounted then
		return
	end
	local flash = S.hud.flash :: Frame
	local scale = S.hud.scale :: UIScale
	local info = TweenInfo.new(tempo, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(scale, info, { Scale = 0.97 }):Play()
	TweenService:Create(flash, info, { BackgroundTransparency = 0.15 }):Play()
end

-- ===== legenda (painel escuro ao lado da carta, em campo) =====
-- Curta (pedido do dono: "telas com muita escrita, mude"): as cores e os símbolos que importam e um
-- resumo de números. Os detalhes do desenho da carta (mata, arrozal, curva de nível) saíram.
function CartaView.buildLegend(parent: Instance, x: number, y: number, w: number, h: number): Frame
	local panel = UiKit.panel(parent, V.PANEL, 0.06)
	panel.Name = "Legenda"
	panel.Position = UDim2.fromOffset(x, y)
	panel.Size = UDim2.fromOffset(w, h)
	panel.ZIndex = 2
	panel.Visible = false
	UiKit.pad(panel, 14, 12, 12)
	UiKit.list(panel, false, 4)
	local n = 0
	local function row(sw: (Frame) -> (), text: string): Frame
		n += 1
		local r = Instance.new("Frame")
		r.BackgroundTransparency = 1
		r.Size = UDim2.new(1, 0, 0, S.ts(15) + 6)
		r.LayoutOrder = n
		r.ZIndex = 2
		r.Parent = panel
		local box = Instance.new("Frame")
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromOffset(30, S.ts(15))
		box.Position = UDim2.fromOffset(0, 3)
		box.ZIndex = 2
		box.Parent = r
		sw(box)
		local t = label(r, text, 14, V.TEXT, F.BODY)
		t.Position = UDim2.fromOffset(40, 2)
		t.ZIndex = 2
		return r
	end
	local function title(text: string)
		n += 1
		local t = label(panel, text, 16, V.DIM, F.TITLE)
		t.LayoutOrder = n
		t.ZIndex = 2
	end
	local function fill(color: Color3, tr: number): (Frame) -> ()
		return function(b: Frame)
			b.BackgroundColor3 = color
			b.BackgroundTransparency = tr
			corner(b, 2)
			stroke(b, color, 1, 0.2)
		end
	end
	local function glyph(text: string, color: Color3, bg: Color3?): (Frame) -> ()
		return function(b: Frame)
			local t = label(b, text, 14, color, if string.find(text, "^%a+$") then F.TITLE else Enum.Font.GothamBold)
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.fromScale(0.5, 0.5)
			t.ZIndex = 3
			if bg then
				t.BackgroundTransparency = 0
				t.BackgroundColor3 = bg
				corner(t, 3)
				local p = Instance.new("UIPadding")
				p.PaddingLeft, p.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
				p.Parent = t
			end
		end
	end
	local function line(color: Color3, px: number): (Frame) -> ()
		return function(b: Frame)
			local l = Instance.new("Frame")
			l.BorderSizePixel = 0
			l.BackgroundColor3 = color
			l.AnchorPoint = Vector2.new(0, 0.5)
			l.Position = UDim2.fromScale(0, 0.5)
			l.Size = UDim2.new(1, 0, 0, px)
			l.ZIndex = 3
			l.Parent = b
		end
	end
	title("LEGENDA")
	row(fill(COR.us, 0.45), "Setor dos EUA")
	row(fill(COR.vc, 0.45), "Setor do VC")
	row(fill(COR.neutro, 0.7), "Setor neutro")
	row(line(COR.frente, 4), "Frente")
	row(glyph("◆", V.TEXT), "Objetivo (cor do dono)")
	row(glyph("QG", V.BG, V.KHAKI), "Ponto de inserção")
	row(glyph("●", COR.squad), "Seu squad")
	row(glyph("▲", COR.me), "Você")
	row(glyph("◆", COR.mine), "Sua marca")
	row(glyph("★", COR.lead), "Marca do líder")
	row(glyph("×", COR.neutro), "Marca do squad")
	row(glyph("▣", COR.latao), "Caixa de munição") -- D-108
	-- só o VC vê os túneis (a linha some para os EUA; updateLegend acompanha o lado)
	local tunnelRow = row(line(COR.tunel, 2), "Túnel")
	tunnelRow.Visible = myFaction() == "VC"
	S.hud.legendTunnel = tunnelRow
	n += 1
	local gap = Instance.new("Frame")
	gap.BackgroundTransparency = 1
	gap.Size = UDim2.new(1, 0, 0, 8)
	gap.LayoutOrder = n
	gap.Parent = panel
	title("RESUMO")
	n += 1
	local score = label(panel, "", 14, V.TEXT, F.BODY)
	score.LayoutOrder = n
	score.TextWrapped = true
	score.AutomaticSize = Enum.AutomaticSize.Y
	score.Size = UDim2.new(1, 0, 0, 0)
	score.TextXAlignment = Enum.TextXAlignment.Left
	score.LineHeight = 1.15
	score.ZIndex = 2
	S.legend, S.legendScore = panel, score
	CartaView.updateLegend()
	return panel
end

function CartaView.updateLegend()
	local tr = S.hud.legendTunnel
	if tr then
		tr.Visible = myFaction() == "VC"
	end
	local t = S.legendScore
	local st = S.match
	if not (t and st) then
		return
	end
	local f = myFaction()
	local lines = {}
	local mine, theirs = 0, 0
	for i, o in st.owner do
		if st.active[i] then
			if o == f then
				mine += 1
			elseif o ~= "Neutral" then
				theirs += 1
			end
		end
	end
	table.insert(lines, string.format("Setores: nossos %d · inimigo %d", mine, theirs))
	if st.score and f then
		local enemy = if f == "US" then "VC" else "US"
		table.insert(lines, string.format("Reforços: nossos %d · inimigo %d", st.score[f] or 0, st.score[enemy] or 0))
	end
	if st.kia and f then
		local enemy = if f == "US" then "VC" else "US"
		table.insert(lines, string.format("Baixas: nossas %d · inimigo %d", st.kia[f] or 0, st.kia[enemy] or 0))
	end
	if st.mode == "Offensive" and type(st.front) == "number" and st.front >= 1 then
		table.insert(lines, string.format("Frente: S%d (+15 min por setor)", st.front))
	end
	local g = CartaView.cursorGrid()
	table.insert(lines, string.format("Cursor: %s", g))
	t.Text = table.concat(lines, "\n")
end

-- eventos da partida: o círculo muda só quando o EventosVisual avisa (marcador novo, fase, fim)
EventosVisual.Changed:Connect(drawEvents)

return CartaView
