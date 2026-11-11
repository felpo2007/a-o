--!strict
-- Carta tática de verdade (pedido do dono, 2026-11-11: "o mapa que você abre no jogo está
-- simplório, faça um mapa de verdade"). O GameUI continua dono das telas e das entradas do mapa;
-- este módulo desenha dentro da janela do mapa:
--   - a folha: a carta topográfica (tools/make_carta.py) em 4 blocos de 1024 px, com vincos de
--     dobra, sombra sobre a prancheta e o papel; sem imagem publicada, papel liso com a quadrícula
--     de 1 km (o desenho simples de antes);
--   - por cima, a lápis de cor: setores com dono (azul = nosso, vermelho = do inimigo, grafite =
--     neutro), a frente, os objetivos com o progresso e a disputa, os pontos de inserção do lado do
--     jogador, o squad, as marcações do squad e "você" com a seta do rumo. NUNCA inimigo (Parte 9.5):
--     as marcas de área aproximada são do próprio squad e envelhecem (D-48);
--   - zoom e arrasto suaves: no controle, analógico esquerdo = cursor, direito = arrastar, gatilhos =
--     zoom, direcional = passo de arrasto, L3 = você, R3 = carta inteira; no mouse, roda = zoom no
--     ponteiro e arrastar com o botão esquerdo; no teclado, setas e +/-;
--   - escala gráfica que acompanha o zoom, seta do norte, grade do cursor ("BS 693 928") e legenda.
-- Tudo em unidades de projeto do palco do GameUI (1280 x 720 com UIScale).
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
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local CartaView = {}

local player = Players.LocalPlayer
local B = MapConfig.Bounds
local M = MapConfig.STUD_M
local SIDE_M = (B.maxX - B.minX) * M -- 2000 m

-- lápis de cor sobre a carta: azul = nosso, vermelho = do inimigo, grafite = neutro/anotação
local COR = {
	nosso = Color3.fromRGB(38, 72, 150),
	inimigo = Color3.fromRGB(168, 38, 30),
	neutro = Color3.fromRGB(78, 74, 64),
	papel = Color3.fromRGB(232, 224, 198),
	prancheta = Color3.fromRGB(40, 36, 26),
	tinta = UiKit.INK,
	latao = UiKit.BRASS,
}
local TYPE = Enum.Font.SpecialElite -- máquina de escrever (rótulos oficiais)
local HAND = Enum.Font.PatrickHand -- lápis (anotações do squad)

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

local function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.Size = UDim2.new()
	t.Font = font or TYPE
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

-- cor de um dono do ponto de vista de quem olha a carta
local function ownerColor(owner: string?): Color3
	local f = myFaction()
	if owner == "US" or owner == "VC" then
		return if owner == f then COR.nosso else COR.inimigo
	end
	return COR.neutro
end

-- linha a lápis entre dois pontos da folha (u, v): traço duplo levemente deslocado
local function pencil(
	parent: Instance,
	u1: number,
	v1: number,
	u2: number,
	v2: number,
	color: Color3,
	px: number,
	z: number?
)
	local du, dv = u2 - u1, v2 - v1
	local len = math.sqrt(du * du + dv * dv)
	if len < 1e-6 then
		return
	end
	for k = 0, 1 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = if k == 0 then 0.12 else 0.6
		f.BorderSizePixel = 0
		f.Rotation = math.deg(math.atan2(dv, du))
		f.Position = UDim2.new((u1 + u2) / 2, k, (v1 + v2) / 2, k)
		f.Size = UDim2.new(len, 0, 0, px)
		f.ZIndex = z or 1
		f.Parent = parent
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
	parent.BackgroundColor3 = COR.prancheta
	parent.BackgroundTransparency = 0
	-- prancheta: madeira escura com luz de cima
	local light = Instance.new("UIGradient")
	light.Rotation = 90
	light.Color = ColorSequence.new(Color3.fromRGB(255, 244, 220), Color3.fromRGB(150, 140, 120))
	light.Parent = parent

	local sheet = frame(parent, "Folha", 2)
	sheet.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.BackgroundColor3 = COR.papel
	sheet.BackgroundTransparency = 0
	sheet.ClipsDescendants = false
	S.sheet = sheet
	Acabamento.sombra(sheet, 14, Vector2.new(4, 8), 0.65)

	-- blocos da carta (imagem) e o papel liso de reserva com a quadrícula de 1 km
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
	local plain = frame(sheet, "PapelLiso", 1)
	S.plain = plain
	local g = MapConfig.GridOrigin1965
	for e = math.ceil((g.e + B.minX * M) / 1000) * 1000, g.e + B.maxX * M, 1000 do
		local u = select(1, uv((e - g.e) / M, 0))
		pencil(plain, u, 0, u, 1, COR.tinta, 1)
		local t = label(plain, tostring((e // 1000) % 100), 14, COR.tinta)
		t.Position = UDim2.new(u, 4, 0, 4)
	end
	for n = math.ceil((g.n - B.maxZ * M) / 1000) * 1000, g.n - B.minZ * M, 1000 do
		local v = select(2, uv(0, (g.n - n) / M))
		pencil(plain, 0, v, 1, v, COR.tinta, 1)
		local t = label(plain, tostring((n // 1000) % 100), 14, COR.tinta)
		t.Position = UDim2.new(0, 4, v, 2)
	end

	-- vincos da folha dobrada em quatro (sombra larga e fio claro, em px: não engrossam com o zoom)
	local creases = frame(sheet, "Vincos", 2)
	for _, vertical in { true, false } do
		local band = Instance.new("Frame")
		band.BorderSizePixel = 0
		band.BackgroundColor3 = Color3.new(0, 0, 0)
		band.AnchorPoint = Vector2.new(0.5, 0.5)
		band.Position = UDim2.fromScale(0.5, 0.5)
		band.Size = if vertical then UDim2.new(0, 22, 1, 0) else UDim2.new(1, 0, 0, 22)
		band.ZIndex = 2
		local gr = Instance.new("UIGradient")
		gr.Rotation = if vertical then 0 else 90
		gr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.72),
			NumberSequenceKeypoint.new(0.56, 0.95),
			NumberSequenceKeypoint.new(1, 1),
		})
		gr.Parent = band
		band.Parent = creases
		local lit = Instance.new("Frame")
		lit.BorderSizePixel = 0
		lit.BackgroundColor3 = Color3.new(1, 1, 1)
		lit.BackgroundTransparency = 0.55
		lit.AnchorPoint = Vector2.new(0.5, 0.5)
		lit.Position = if vertical then UDim2.new(0.5, 2, 0.5, 0) else UDim2.new(0.5, 0, 0.5, 2)
		lit.Size = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1)
		lit.ZIndex = 3
		lit.Parent = creases
	end
	-- camadas do lápis (ordem de baixo para cima)
	for i, name in { "setores", "linhas", "objetivos", "pontos", "marcas", "squad", "voce" } do
		S.layers[name] = frame(sheet, name, 3 + i)
	end

	-- luz da sala sobre a carta: vinheta fraca nas bordas da janela (a carta fica "na mesa")
	local vin = Instance.new("ImageLabel")
	vin.Name = "Luz"
	vin.BackgroundTransparency = 1
	vin.Image = Acabamento.VINHETA
	vin.ImageTransparency = 0.45
	vin.Size = UDim2.fromScale(1, 1)
	vin.ZIndex = 4
	pcall(function()
		vin.Interactable = false
	end)
	vin.Parent = parent

	-- HUD da janela: escala gráfica, norte, zoom
	local hud = frame(parent, "Instrumentos", 5)
	pcall(function()
		hud.Interactable = false
	end)
	local bar = Instance.new("Frame")
	bar.Name = "Escala"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 14, 1, -40)
	bar.Size = UDim2.fromOffset(100, 6)
	bar.BackgroundColor3 = COR.tinta
	bar.BorderSizePixel = 0
	bar.Parent = hud
	stroke(bar, COR.papel, 1.5, 0.2)
	local half = Instance.new("Frame")
	half.BackgroundColor3 = COR.papel
	half.BorderSizePixel = 0
	half.Position = UDim2.new(0.5, 0, 0, 1)
	half.Size = UDim2.new(0.5, -1, 1, -2)
	half.Parent = bar
	local barText = label(hud, "100 m", 13, COR.papel)
	barText.AnchorPoint = Vector2.new(0, 1)
	barText.Position = UDim2.new(0, 14, 1, -48)
	barText.TextStrokeTransparency = 0.4
	S.hud.bar, S.hud.barText = bar, barText
	local north = label(hud, "▲\nN", 15, COR.papel, Enum.Font.GothamBold)
	north.AnchorPoint = Vector2.new(1, 0)
	north.Position = UDim2.new(1, -14, 0, 10)
	north.TextStrokeTransparency = 0.3
	north.TextXAlignment = Enum.TextXAlignment.Center
	local zoomText = label(hud, "", 13, COR.papel)
	zoomText.AnchorPoint = Vector2.new(1, 0)
	zoomText.Position = UDim2.new(1, -14, 0, 54)
	zoomText.TextStrokeTransparency = 0.4
	S.hud.zoom = zoomText

	-- abertura: o papel clareia e assenta
	local flash = frame(parent, "Abertura", 8)
	flash.BackgroundColor3 = COR.papel
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

function CartaView.setMode(mode: string)
	if mode ~= S.mode then
		S.mode = mode
		S.sig, S.spawnSig = "", ""
		CartaView.redraw()
	end
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

function CartaView.bindMouse()
	UserInputService.InputChanged:Connect(function(io: InputObject)
		if not S.visible then
			return
		end
		if io.UserInputType == Enum.UserInputType.MouseWheel then
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
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
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
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
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
end

function CartaView.setInserts(list: { any })
	S.inserts = list or {}
	CartaView.drawPoints()
end

function CartaView.setSquad(list: { any })
	S.squad = list or {}
	CartaView.drawSquad()
end

-- marcação do squad (Squad_Mark do servidor): ponto, ponto pela carta ou área de inimigo aproximada
function CartaView.addMark(m: any)
	if type(m) ~= "table" or type(m.x) ~= "number" or type(m.z) ~= "number" then
		return
	end
	table.insert(S.marks, { x = m.x, z = m.z, r = m.r, kind = m.kind, from = m.from, t = os.clock(), w = nil })
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
		local t = label(sect, string.format("S%d", s.id), 22, color, HAND)
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.new(cu, 0, 0, 30)
		t.TextTransparency = if active then 0.05 else 0.45
		local lock = if not active and st.mode == "Offensive" and owner == "US" then " ✓" else ""
		local sub = label(
			sect,
			(if owner == "Neutral" then "neutro" elseif owner == myFaction() then "nosso" else "inimigo") .. lock,
			13,
			color,
			HAND
		)
		sub.AnchorPoint = Vector2.new(0.5, 0)
		sub.Position = UDim2.new(cu, 0, 0, 56)
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
				pencil(lines, u1, v1, u2, v2, COR.inimigo, 4)
			elseif contact then
				-- traço duplo: a cor de cada lado do lado dele
				local du = if math.abs(u1 - u2) < 1e-6 then 0.0016 else 0
				local dv = if du == 0 then 0.0016 else 0
				pencil(lines, u1 - du, v1 - dv, u2 - du, v2 - dv, ownerColor(oa), 2)
				pencil(lines, u1 + du, v1 + dv, u2 + du, v2 + dv, ownerColor(ob), 2)
			else
				local n = 28
				for k = 0, n - 1, 2 do
					local t0, t1 = k / n, (k + 1) / n
					pencil(
						lines,
						u1 + (u2 - u1) * t0,
						v1 + (v2 - v1) * t0,
						u1 + (u2 - u1) * t1,
						v1 + (v2 - v1) * t1,
						COR.neutro,
						1
					)
				end
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
					local arrow = label(lines, "◄", 18, COR.inimigo, Enum.Font.GothamBold)
					arrow.AnchorPoint = Vector2.new(1, 0.5)
					arrow.Position = UDim2.new(u1, -6, vv, 0)
				end
				local tag = label(lines, "FRENTE", 15, COR.inimigo, TYPE)
				tag.AnchorPoint = Vector2.new(0, 0.5)
				tag.Rotation = -90
				tag.Position = UDim2.new(u1, 10, (v1 + v2) / 2, 0)
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
		card.BackgroundColor3 = COR.papel
		card.BackgroundTransparency = if active then 0.08 else 0.35
		card.BorderSizePixel = 0
		corner(card, 3)
		stroke(card, color, 1, 0.35)
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
		local name = label(card, string.format("S%d · %s", s, UiKit.upper(p.name)), 13, COR.tinta, TYPE)
		name.LayoutOrder = 1
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(84, 6)
		bar.BackgroundColor3 = Color3.fromRGB(196, 186, 156)
		bar.BorderSizePixel = 0
		bar.LayoutOrder = 2
		bar.Visible = active
		stroke(bar, COR.tinta, 1, 0.5)
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.Parent = bar
		local mid = Instance.new("Frame")
		mid.BorderSizePixel = 0
		mid.BackgroundColor3 = COR.tinta
		mid.Position = UDim2.new(0.5, 0, 0, -1)
		mid.Size = UDim2.new(0, 1, 1, 2)
		mid.Parent = bar
		bar.Parent = card
		local status = label(card, "", 13, COR.tinta, HAND)
		status.LayoutOrder = 3
		-- papel do time: ATACAR / DEFENDER, carimbado a lápis ao lado
		if s == target and role then
			local tag = label(layer, if role == "attack" then "ATACAR" else "DEFENDER", 15, COR.nosso, TYPE)
			tag.AnchorPoint = Vector2.new(0, 1)
			tag.Position = UDim2.new(u, 12, v, -10)
			tag.Rotation = -6
			stroke(tag, COR.nosso, 1.5, 0.1).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			tag.BackgroundTransparency = 1
			local tp = Instance.new("UIPadding")
			tp.PaddingLeft, tp.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
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
		w.fill.BackgroundColor3 = if p >= 0 then COR.nosso else COR.inimigo
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
		local text, color = "", COR.tinta
		if not w.active then
			text = if st.mode == "Offensive" and owner == "US" then "tomado" else "fora de jogo"
		elseif contested then
			text, color = "⚔ EM DISPUTA", COR.inimigo
		elseif cap and cap == f then
			text, color = if owner == f then "▲ reforçando" else "▲ tomando", COR.nosso
		elseif cap then
			text, color = if owner == f then "▼ sob ataque" else "▼ inimigo reforça", COR.inimigo
		else
			text = if owner == "Neutral" then "neutro" elseif owner == f then "nosso" else "do inimigo"
		end
		w.status.Text = text
		w.status.TextColor3 = color
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

-- símbolo e nome curto de cada tipo de ponto de inserção
local KIND = {
	hq = { "QG", "QG" },
	rally = { "R", "Reunião" },
	rally_captured = { "R", "Reunião" },
	garrison = { "P", "Posto" },
}
local function pointGlyph(pt: any): string
	if type(pt.id) == "string" then
		if string.sub(pt.id, 1, 8) == "forward:" then
			return "RA"
		elseif string.sub(pt.id, 1, 6) == "squad:" then
			return "SQ"
		elseif string.sub(pt.id, 1, 7) == "tunnel:" then
			return "T"
		elseif pt.id == "inplace" then
			return "×"
		end
	end
	local k = KIND[pt.kind or ""]
	return if k then k[1] else "R"
end

-- pontos de inserção: na carta de spawn com espera e PRONTO (botões); em campo, só o símbolo
function CartaView.drawPoints()
	if not S.mounted then
		return
	end
	local spawnMode = S.mode == "spawn"
	local list: { any } = if spawnMode then S.spawns else S.inserts
	local sigParts = { S.mode }
	for _, pt in list do
		table.insert(sigParts, string.format("%s@%d,%d", tostring(pt.id), math.floor(pt.x), math.floor(pt.z)))
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
			holder.Position = UDim2.new(u, 0, v, 2)
			holder.AutomaticSize = Enum.AutomaticSize.XY
			holder.Size = UDim2.new()
			holder.BackgroundColor3 = COR.prancheta
			holder.BackgroundTransparency = if spawnMode then 0.08 else 0.25
			holder.BorderSizePixel = 0
			corner(holder, 3)
			local edge = stroke(holder, COR.latao, 0, 0)
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 5), UDim.new(0, 6)
			pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 2), UDim.new(0, 2)
			pad.Parent = holder
			local row = Instance.new("UIListLayout")
			row.FillDirection = Enum.FillDirection.Horizontal
			row.VerticalAlignment = Enum.VerticalAlignment.Center
			row.Padding = UDim.new(0, 5)
			row.SortOrder = Enum.SortOrder.LayoutOrder
			row.Parent = holder
			local glyph = label(holder, pointGlyph(pt), 13, COR.prancheta, Enum.Font.GothamBold)
			glyph.BackgroundTransparency = 0
			glyph.BackgroundColor3 = COR.latao
			glyph.LayoutOrder = 1
			corner(glyph, 2)
			local gp = Instance.new("UIPadding")
			gp.PaddingLeft, gp.PaddingRight = UDim.new(0, 3), UDim.new(0, 3)
			gp.Parent = glyph
			local text = label(holder, "", 12, COR.papel, Enum.Font.GothamMedium)
			text.LayoutOrder = 2
			text.Visible = spawnMode or S.zoom >= 2
			holder.Parent = layer
			-- pino no chão do ponto
			local pin = Instance.new("Frame")
			pin.AnchorPoint = Vector2.new(0.5, 0.5)
			pin.Position = UDim2.fromScale(u, v)
			pin.Size = UDim2.fromOffset(7, 7)
			pin.BackgroundColor3 = COR.latao
			pin.BorderSizePixel = 0
			corner(pin)
			stroke(pin, COR.prancheta, 1.5)
			pin.Parent = layer
			local id = tostring(pt.id)
			holder.Activated:Connect(function()
				local w = S.spawnWidgets[id]
				if w and not S.dragged and spawnMode and S.onSpawn then
					S.onSpawn(w.pt) -- o ponto com a espera de agora (atualizado a cada segundo)
				end
			end)
			S.spawnWidgets[tostring(pt.id)] = { holder = holder, text = text, edge = edge, pt = pt }
		end
	end
	-- textos que mudam todo segundo (espera)
	for _, pt in list do
		local w = S.spawnWidgets[tostring(pt.id)]
		if w then
			w.pt = pt
			if spawnMode then
				local state = if pt.blocked
					then (pt.why or "bloqueado")
					elseif (pt.wait or 0) > 0 then string.format("%d s", pt.wait)
					else "PRONTO"
				w.text.Text = Acabamento.viet(string.format("%s · %s", pt.name, state))
				w.text.TextColor3 = if pt.blocked
					then Color3.fromRGB(232, 140, 120)
					elseif (pt.wait or 0) > 0 then COR.papel
					else Color3.fromRGB(176, 214, 130)
			else
				w.text.Text = Acabamento.viet(pt.name)
			end
			local hot = S.focused ~= nil and S.focused.id == "spawn:" .. tostring(pt.id)
			w.edge.Thickness = if hot then 2.5 else 0
		end
	end
end

-- o próprio squad (FrontService, a cada 2 s): bolinha azul com a inicial; líder com estrela
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
			dot.BackgroundColor3 = COR.nosso
			dot.BorderSizePixel = 0
			corner(dot)
			stroke(dot, COR.papel, 1.5)
			dot.Parent = layer
			local name = label(dot, "", 12, COR.nosso, HAND)
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.new(1, 4, 0.5, 0)
			name.TextStrokeColor3 = COR.papel
			name.TextStrokeTransparency = 0.3
			w = { dot = dot, name = name }
			S.squadWidgets[m.id] = w
		end
		local u, v = uv(m.x, m.z)
		w.dot.Position = UDim2.fromScale(u, v)
		w.dot.BackgroundColor3 = if m.downed then COR.inimigo else COR.nosso
		w.name.Text = (if m.role == "squad_leader" then "★ " else "")
			.. tostring(m.name)
			.. (if m.downed then " (caído)" else "")
	end
	for id, w in S.squadWidgets do
		if not seen[id] then
			w.dot:Destroy()
			S.squadWidgets[id] = nil
		end
	end
end

-- marcações do squad a lápis: X grafite (ponto) e círculo vermelho tracejado (área aproximada)
function CartaView.drawMarks()
	if not S.mounted then
		return
	end
	local layer = S.layers.marcas
	for _, mk in S.marks do
		if mk.w then
			continue
		end
		local u, v = uv(mk.x, mk.z)
		local holder = frame(layer, "Marca")
		holder.Size = UDim2.fromScale(1, 1)
		if mk.kind == "target" and type(mk.r) == "number" then
			local rr = mk.r / M / (B.maxX - B.minX)
			local ring = Instance.new("Frame")
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(u, v)
			ring.Size = UDim2.fromScale(2 * rr, 2 * rr)
			ring.BackgroundColor3 = COR.inimigo
			ring.BackgroundTransparency = 0.82
			corner(ring)
			local st = stroke(ring, COR.inimigo, 2, 0.1)
			st.LineJoinMode = Enum.LineJoinMode.Round
			local sz = Instance.new("UISizeConstraint")
			sz.MinSize = Vector2.new(14, 14)
			sz.Parent = ring
			ring.Parent = holder
			local t = label(
				holder,
				string.format("≈ inimigo ±%d m · %s", math.floor(mk.r + 0.5), tostring(mk.from)),
				13,
				COR.inimigo,
				HAND
			)
			t.AnchorPoint = Vector2.new(0.5, 1)
			t.Position = UDim2.new(u, 0, v, -10)
		else
			pencil(holder, u - 0.004, v - 0.004, u + 0.004, v + 0.004, COR.neutro, 2.5)
			pencil(holder, u - 0.004, v + 0.004, u + 0.004, v - 0.004, COR.neutro, 2.5)
			local t = label(holder, tostring(mk.from), 13, COR.neutro, HAND)
			t.AnchorPoint = Vector2.new(0, 0.5)
			t.Position = UDim2.new(u, 10, v, 0)
		end
		holder.Rotation = 0
		mk.w = holder
	end
end

local function fadeMarks()
	local now = os.clock()
	for i = #S.marks, 1, -1 do
		local mk = S.marks[i]
		local ttl = if mk.kind == "target" then Comms.MARK_TTL_S else 90
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
		halo.BackgroundColor3 = COR.latao
		halo.BorderSizePixel = 0
		corner(halo)
		stroke(halo, COR.prancheta, 2)
		halo.Parent = me
		local arrow = label(me, "▲", 20, COR.prancheta, Enum.Font.GothamBold)
		arrow.AutomaticSize = Enum.AutomaticSize.None
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.Position = UDim2.fromScale(0.5, 0.5)
		arrow.Size = UDim2.fromOffset(30, 30)
		arrow.TextStrokeColor3 = COR.latao
		arrow.TextStrokeTransparency = 0
		arrow.ZIndex = 2
		S.me, S.meArrow = me, arrow
		local tag = label(me, "VOCÊ", 12, COR.prancheta, Enum.Font.GothamBold)
		tag.AnchorPoint = Vector2.new(0.5, 0)
		tag.Position = UDim2.new(0.5, 0, 1, 0)
		tag.TextStrokeColor3 = COR.papel
		tag.TextStrokeTransparency = 0.2
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
	if (before < 2) ~= (S.zoom < 2) and S.mode ~= "spawn" then
		S.spawnSig = "" -- nome dos pontos só com zoom
		CartaView.drawPoints()
	end
	-- ímã (controle) e realce
	local f: InputMap.MagnetPoint? = nil
	if pad then
		local cu, cv = Carta.pick(S.u, S.v, S.zoom, W, H, S.cursor.X, S.cursor.Y)
		f = InputMap.magnet(cu, cv, magnetPoints(), 0.03 / S.zoom)
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
		-- a carta "desdobra": entra um pouco menor e torta, o papel clareia e assenta
		S.zoom = S.zoomT * 0.92
		scale.Scale = 0.96
		flash.BackgroundTransparency = 0.15
		local sheet = S.sheet :: Frame
		sheet.Rotation = -1.4
		local info = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(scale, info, { Scale = 1 }):Play()
		TweenService:Create(sheet, info, { Rotation = 0 }):Play()
		TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		S.spawnSig = ""
		CartaView.drawPoints()
		CartaView.drawMarks()
	else
		S.drag = nil
	end
end

-- dobra a carta (fecha): o GameUI esconde a janela depois de `tempo` s
function CartaView.foldOut(tempo: number)
	if not S.mounted then
		return
	end
	local flash = S.hud.flash :: Frame
	local scale = S.hud.scale :: UIScale
	local info = TweenInfo.new(tempo, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(scale, info, { Scale = 0.95 }):Play()
	TweenService:Create(S.sheet :: Frame, info, { Rotation = 1.2 }):Play()
	TweenService:Create(flash, info, { BackgroundTransparency = 0.1 }):Play()
end

-- ===== legenda (painel de papel ao lado da carta, em campo) =====
function CartaView.buildLegend(parent: Instance, x: number, y: number, w: number, h: number): Frame
	local panel = Instance.new("Frame")
	panel.Name = "Legenda"
	panel.Position = UDim2.fromOffset(x, y)
	panel.Size = UDim2.fromOffset(w, h)
	panel.BackgroundColor3 = UiKit.CARD
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Visible = false
	panel.Parent = parent
	stroke(panel, UiKit.DRAB, 3)
	Acabamento.sombra(panel, 12, Vector2.new(3, 6), 0.55)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 10)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 3)
	list.Parent = panel
	local n = 0
	local function row(sw: (Frame) -> (), text: string, size: number?)
		n += 1
		local r = Instance.new("Frame")
		r.BackgroundTransparency = 1
		r.Size = UDim2.new(1, 0, 0, S.ts(size or 15) + 4)
		r.LayoutOrder = n
		r.ZIndex = 2
		r.Parent = panel
		local box = Instance.new("Frame")
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromOffset(34, S.ts(size or 15))
		box.Position = UDim2.fromOffset(0, 2)
		box.ZIndex = 2
		box.Parent = r
		sw(box)
		local t = label(r, text, size or 14, UiKit.INK, Enum.Font.Arimo)
		t.Position = UDim2.fromOffset(42, 0)
		t.ZIndex = 2
	end
	local function title(text: string)
		n += 1
		local t = label(panel, text, 15, UiKit.RULE_RED, TYPE)
		t.LayoutOrder = n
		t.ZIndex = 2
	end
	local function fill(color: Color3, tr: number): (Frame) -> ()
		return function(b: Frame)
			b.BackgroundColor3 = color
			b.BackgroundTransparency = tr
			stroke(b, UiKit.INK, 1, 0.6)
		end
	end
	local function glyph(text: string, color: Color3, bg: Color3?): (Frame) -> ()
		return function(b: Frame)
			local t = label(b, text, 14, color, Enum.Font.GothamBold)
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.fromScale(0.5, 0.5)
			t.ZIndex = 3
			if bg then
				t.BackgroundTransparency = 0
				t.BackgroundColor3 = bg
			end
		end
	end
	local function line(color: Color3, px: number, dashed: boolean?): (Frame) -> ()
		return function(b: Frame)
			local k = if dashed then 4 else 1
			for i = 0, k - 1 do
				local l = Instance.new("Frame")
				l.BorderSizePixel = 0
				l.BackgroundColor3 = color
				l.AnchorPoint = Vector2.new(0, 0.5)
				l.Position = UDim2.new(i / k, 0, 0.5, 0)
				l.Size = UDim2.new(if dashed then 0.6 / k else 1, 0, 0, px)
				l.ZIndex = 3
				l.Parent = b
			end
		end
	end
	title("LEGENDA")
	row(fill(COR.nosso, 0.6), "Setor nosso")
	row(fill(COR.inimigo, 0.6), "Setor do inimigo")
	row(fill(COR.neutro, 0.85), "Setor neutro")
	row(line(COR.inimigo, 4), "Frente / linha de contato")
	row(glyph("◆", COR.nosso), "Objetivo (raio de 50 m)")
	row(glyph("QG", COR.prancheta, COR.latao), "QG · R reunião · RA avançada")
	row(glyph("SQ", COR.prancheta, COR.latao), "Reunião do squad · P posto")
	row(glyph("▲", COR.prancheta, COR.latao), "Você e o rumo")
	row(glyph("●", COR.nosso), "Seu squad (★ líder)")
	row(glyph("×", COR.neutro), "Marca do squad (lápis)")
	row(fill(COR.inimigo, 0.8), "Inimigo marcado: área aproximada")
	title("CARTA (1:50 000, ampliada)")
	row(fill(Color3.fromRGB(196, 214, 166), 0), "Mata")
	row(fill(Color3.fromRGB(166, 194, 140), 0), "Bosque de vila e sebe de bambu")
	row(fill(Color3.fromRGB(205, 220, 222), 0), "Arrozal com diques")
	row(glyph("ψ", Color3.fromRGB(48, 86, 44)), "Baixada: bambu e tràm")
	row(glyph("■", UiKit.INK), "Casa")
	row(line(UiKit.INK, 2, true), "Trilha")
	row(line(Color3.fromRGB(168, 104, 52), 2), "Curva de nível (5 m)")
	row(line(Color3.fromRGB(52, 108, 160), 3), "Riacho")
	title("RESUMO")
	n += 1
	local score = label(panel, "", 14, UiKit.INK, TYPE)
	score.LayoutOrder = n
	score.TextWrapped = true
	score.AutomaticSize = Enum.AutomaticSize.Y
	score.Size = UDim2.new(1, 0, 0, 0)
	score.TextXAlignment = Enum.TextXAlignment.Left
	score.ZIndex = 2
	S.legend, S.legendScore = panel, score
	CartaView.updateLegend()
	return panel
end

function CartaView.updateLegend()
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

return CartaView
