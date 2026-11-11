--!strict
-- Lobby diegético em 3D (pedido do dono, 2026-11-11): a câmera olha de cima para uma mesa de
-- campanha e os objetos da mesa são os botões. Identidade própria, 1965 (nada copiado de outro jogo):
--   - EUA: mesa de campanha numa barraca de comando dos Marines (lona, lampião, carta 1:50.000 de
--     Vạn Tường, dossiê da Operação Starlite, rádio PRC-10, lata de munição .30, calendário de
--     AGO 1965, capacete M1, caneca e ração);
--   - VC: mesa de tábuas num abrigo de terra com teto de toras (lamparina, croqui feito à mão,
--     bandeira da Frente, maço de documentos amarrado, telefone de campanha, caixote de munição,
--     caderneta "sổ tay" e capacete de fibra);
--   - antes de escolher o lado: sala de arquivo com os dois dossiês e os dois soldados.
-- Objeto -> ação (o DeployScreen decide o que cada ação abre): rádio/telefone = "squad",
-- dossiê/documentos e o soldado = "role", carta/croqui = "insert", calendário/caderneta = "daily",
-- munição = "shop", capacete = "faction"; na sala de arquivo, "pick_US" e "pick_VC".
-- Passar o ponteiro (mouse ou o cursor virtual do controle) realça o objeto (Highlight) e mostra uma
-- etiqueta com o nome da ação; escolher aproxima a câmera do objeto e anima a abertura (a pasta
-- abre, o fone sobe, a tampa levanta). No toque, tocar escolhe (os dossiês de lado pedem 2 toques).
-- Tudo é local (peças criadas no cliente, longe do mapa) e só fica no Workspace com a câmera na
-- mesa. Escala do jogo: 1 m = 1/0,28 stud. A carta da mesa é desenhada com o MapConfig (grade UTM
-- de 1965, pontos fortes e QGs de verdade).
-- Continua do lobby antigo: só com o lobby aberto e sem corpo na tela (ou morto há DEAD_GRACE s);
-- pede streaming em volta do QG do lado (o spawn fica pronto); esconde o chat padrão; efeitos só no
-- lobby (profundidade de campo e cor). Ao nascer, tudo volta ao normal.
-- Movimento (pedido do dono, 2026-11-11: "mais fluido ... com maestria"): a câmera chega à mesa
-- num travelling lento (sem corte seco), vai de um objeto a outro em curva suave (sem tranco no
-- começo nem no fim), a troca de cena passa por um escuro quente curto, e o realce e a etiqueta do
-- objeto entram animados. Película leve (Acabamento: vinheta, grão, luz de lampião) sobre a cena e
-- abaixo dos papéis.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local SoldierPreview = require(script.Parent.SoldierPreview)
local UiKit = require(script.Parent.UiKit)
local VirtualCursor = require(script.Parent.VirtualCursor)

local LobbyScene = {}
local player = Players.LocalPlayer

local M = MapConfig.STUD_M -- 0,28 m por stud
local FOV = 50
local DEAD_GRACE = 2.5 -- s: depois de morrer, o corpo fica na tela um instante antes da cena
local MOVE_TIME = 0.7 -- s da câmera indo até um objeto
local ARRIVE_TIME = 1.6 -- s do travelling de chegada (abrir a mesa, trocar de cena)
local B = MapConfig.Bounds
-- as cenas ficam no alto e fora da área jogável: ninguém as vê do mapa e o mapa não aparece nelas
local BASE = Vector3.new((B.minX + B.maxX) / 2, 2600, B.maxZ + 3000)

local HEAD, TYPE, VIET = Enum.Font.Oswald, Enum.Font.SpecialElite, Enum.Font.Arimo
local INK, CARD, MANILA, KHAKI, STAMP = UiKit.INK, UiKit.CARD, UiKit.MANILA, UiKit.KHAKI, UiKit.STAMP
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- ===== tipos =====
type Shot = { focus: Vector3, view: Vector3, dist: number }
type Obj = {
	id: string, -- ação
	model: Model,
	hit: BasePart,
	title: string,
	sub: string,
	font: Enum.Font,
	shot: Shot,
	top: Vector3, -- onde a etiqueta aparece
	open: ((boolean) -> ())?,
	confirmTouch: boolean, -- no toque, o 1º toque só mostra (escolha de lado)
}
type Flicker = { light: Light, base: number, seed: number }
type PropSlot = { key: string, holder: Model, place: CFrame, size: Vector3, fallback: Model?, filled: boolean }
type Scene = {
	id: string,
	root: CFrame,
	folder: Model,
	hits: Folder,
	objects: { Obj },
	byHit: { [BasePart]: Obj },
	lights: { Flicker },
	spots: { [string]: SpotLight },
	overview: Shot,
	previews: { [string]: SoldierPreview.Preview },
}

-- textos vivos das peças (DeployScreen manda: squad, papel, dia da recompensa)
local live: { [string]: { TextLabel } } = {}
local liveValue: { [string]: string } = {}
local liveColor: { [string]: Color3 } = {}
local propSlots: { PropSlot } = {}

-- ===== construção (medidas em metros na cena; mesa com o tampo em y = 0, câmera do lado +Z) =====
local R = CFrame.identity -- raiz da cena em construção
-- folha deitada que se lê de quem está do lado +Z (SurfaceGui na face Front; alto da folha = longe)
local FLAT = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1))
local FACE = CFrame.Angles(0, math.pi, 0) -- face Front virada para a câmera
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cilindro em pé (o eixo do cilindro é o X)

local function W(cf: CFrame): CFrame
	return R * (CFrame.new(cf.Position / M) * cf.Rotation)
end
local function V(x: number, y: number, z: number): Vector3
	return R:PointToWorldSpace(Vector3.new(x, y, z) / M)
end
local function D(x: number, y: number, z: number): Vector3
	return R:VectorToWorldSpace(Vector3.new(x, y, z).Unit)
end
local function at(x: number, y: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

local function part(
	parent: Instance,
	sx: number,
	sy: number,
	sz: number,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(math.max(sx / M, 0.01), math.max(sy / M, 0.01), math.max(sz / M, 0.01))
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.CFrame = W(cf)
	p.Parent = parent
	return p
end

-- cilindro: comprimento no eixo X do cf (use UPRIGHT para ficar em pé)
local function cyl(parent: Instance, len: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = part(parent, len, dia, dia, cf, color, mat)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- elipsoide (esfera achatada pela malha)
local function blob(
	parent: Instance,
	sx: number,
	sy: number,
	sz: number,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?
): Part
	local p = part(parent, sx, sy, sz, cf, color, mat)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- folha deitada (papel, carta) com a face de cima pronta para SurfaceGui (Front)
local function sheet(
	parent: Instance,
	w: number,
	d: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	color: Color3,
	thick: number?
): Part
	local t = thick or 0.003
	return part(parent, w, d, t, at(x, y + t / 2, z, yaw) * FLAT, color, Enum.Material.SmoothPlastic)
end

local function group(parent: Instance, name: string): Model
	local g = Instance.new("Model")
	g.Name = name
	g.Parent = parent
	return g
end

local function light(p: BasePart, color: Color3, range: number, brightness: number, shadows: boolean): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range / M
	l.Brightness = brightness
	l.Shadows = shadows
	l.Parent = p
	return l
end

-- ===== SurfaceGui =====
local function surface(p: BasePart, pps: number?): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps or 160
	sg.LightInfluence = 0.9 -- o papel acompanha a luz do lampião (não brilha no escuro)
	sg.ClipsDescendants = true
	sg.Parent = p
	return sg
end

local function sgBox(parent: Instance, color: Color3, x: number, y: number, w: number, h: number, tr: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BackgroundTransparency = tr or 0
	f.BorderSizePixel = 0
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Parent = parent
	return f
end

local function sgText(
	parent: Instance,
	text: string,
	font: Enum.Font,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	align: Enum.TextXAlignment?,
	maxSize: number?
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = font
	t.TextColor3 = color
	t.Text = text
	t.TextScaled = true
	t.TextWrapped = true
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
	if maxSize then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = maxSize
		c.Parent = t
	end
	t.Parent = parent
	return t
end

-- carimbo: texto e moldura na mesma tinta, um pouco torto
local function sgStamp(
	parent: Instance,
	text: string,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	rot: number
)
	local t = sgText(parent, text, HEAD, color, x, y, w, h, Enum.TextXAlignment.Center)
	t.Rotation = rot
	t.TextTransparency = 0.15
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 3
	s.Transparency = 0.25
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = t
	return t
end

-- texto que o DeployScreen atualiza (LobbyScene.setText)
local function liveText(key: string, t: TextLabel)
	live[key] = live[key] or {}
	table.insert(live[key], t)
	local v = liveValue[key]
	if v then
		t.Text = v
	end
	local c = liveColor[key]
	if c then
		t.TextColor3 = c
	end
end

-- ===== carta da mesa (dados reais do MapConfig) =====
local function mapUV(x: number, z: number): (number, number)
	return (x - B.minX) / (B.maxX - B.minX), (z - B.minZ) / (B.maxZ - B.minZ)
end

-- traço reto entre dois pontos da área quadrada (escala isotrópica)
local function stroke(parent: Instance, u1: number, v1: number, u2: number, v2: number, px: number, color: Color3)
	local du, dv = u2 - u1, v2 - v1
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((u1 + u2) / 2, (v1 + v2) / 2)
	f.Size = UDim2.new(math.sqrt(du * du + dv * dv), 0, 0, px)
	f.Rotation = math.deg(math.atan2(dv, du))
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
end

local function arrow(parent: Instance, u1: number, v1: number, u2: number, v2: number, color: Color3)
	stroke(parent, u1, v1, u2, v2, 4, color)
	local a = math.atan2(v2 - v1, u2 - u1)
	for _, s in { 1, -1 } do
		local b = a + math.pi + s * 0.5
		stroke(parent, u2, v2, u2 + math.cos(b) * 0.05, v2 + math.sin(b) * 0.05, 4, color)
	end
end

local VC_NAMES: { [string]: string } =
	{ ["Colina 43"] = "Đồi 43", ["Colina 30"] = "Đồi 30", ["Cemitério"] = "Nghĩa địa" }
local US_ONLY: { [string]: boolean } = { ["LZ Blue"] = true, ["Athletic field"] = true }

local function strongpoint(name: string): (number?, number?)
	for _, sp in MapConfig.Strongpoints do
		if sp.name == name then
			return sp.x, sp.z
		end
	end
	return nil, nil
end

local function drawMap(p: BasePart, style: string)
	local us = style == "US"
	local paper = if us then rgb(226, 222, 194) else rgb(204, 186, 144)
	local ink = if us then rgb(44, 50, 58) else rgb(84, 50, 28)
	local red = rgb(176, 40, 30)
	local sg = surface(p, 220)
	sgBox(sg, paper, 0, 0, 1, 1)
	-- área jogável quadrada no meio da folha; as margens ficam para o título e a legenda
	local area = sgBox(sg, paper, 0.5, 0.5, 1, 0.88)
	area.AnchorPoint = Vector2.new(0.5, 0.5)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = area
	local edge = Instance.new("UIStroke")
	edge.Color = ink
	edge.Thickness = 2
	edge.Parent = area
	-- setores (faixas da carta), tinta de mata clara alternada
	for i, s in MapConfig.Sectors do
		local x0, x1 = math.huge, -math.huge
		for k = 1, #s.polygon, 2 do
			x0 = math.min(x0, s.polygon[k])
			x1 = math.max(x1, s.polygon[k])
		end
		local u0 = mapUV(x0, 0)
		local u1 = mapUV(x1, 0)
		local tint = if us
			then (if i % 2 == 0 then rgb(170, 196, 140) else rgb(190, 206, 156))
			else (if i % 2 == 0 then rgb(184, 160, 116) else rgb(194, 172, 128))
		sgBox(area, tint, u0, 0, u1 - u0, 1, 0.45)
		if i > 1 then
			sgBox(area, ink, u0, 0, 0.002, 1, 0.5)
		end
		sgText(area, string.match(s.name, "^S%d") or "", HEAD, ink, u0 + 0.01, 0.01, 0.08, 0.04)
	end
	-- grade UTM de 500 m (origem de 1965 do MapConfig)
	if us then
		local g = MapConfig.GridOrigin1965
		local step = 500
		local e0, e1 = g.e + B.minX * M, g.e + B.maxX * M
		local e = math.ceil(e0 / step) * step
		while e <= e1 do
			local u = (e - e0) / (e1 - e0)
			sgBox(area, rgb(70, 96, 140), u, 0, 0.0025, 1, 0.35)
			if e % 1000 == 0 then
				sgText(
					area,
					string.format("%02d", (e // 1000) % 100),
					TYPE,
					rgb(70, 96, 140),
					u + 0.004,
					0.955,
					0.06,
					0.04
				)
			end
			e += step
		end
		local n1, n0 = g.n - B.minZ * M, g.n - B.maxZ * M -- norte em cima
		local n = math.ceil(n0 / step) * step
		while n <= n1 do
			local v = (n1 - n) / (n1 - n0)
			sgBox(area, rgb(70, 96, 140), 0, v, 1, 0.0025, 0.35)
			if n % 1000 == 0 then
				sgText(
					area,
					string.format("%02d", (n // 1000) % 100),
					TYPE,
					rgb(70, 96, 140),
					0.004,
					v + 0.004,
					0.06,
					0.04
				)
			end
			n += step
		end
	end
	-- pontos fortes reais
	for _, sp in MapConfig.Strongpoints do
		if sp.real and (us or not US_ONLY[sp.name]) then
			local u, v = mapUV(sp.x, sp.z)
			local dot = sgBox(area, ink, u, v, 0.016, 0.016)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = dot
			local name = if us then sp.name else (VC_NAMES[sp.name] or sp.name)
			local t = sgText(area, name, if us then TYPE else VIET, ink, u + 0.012, v - 0.018, 0.3, 0.036)
			t.TextScaled = false
			t.TextSize = 13
		end
	end
	-- QGs e eixos de lápis de cera
	local hqUS, hqVC = MapConfig.HQ.US, MapConfig.HQ.VC
	local ux, uz = mapUV(hqUS.x, hqUS.z)
	local vx, vz = mapUV(hqVC.x, hqVC.z)
	local acx, acz = strongpoint("An Cường (2)")
	local nyx, nyz = strongpoint("Nam Yên (4)")
	if us then
		local box = sgBox(area, rgb(40, 70, 140), ux, uz, 0.05, 0.035, 0.15)
		box.AnchorPoint = Vector2.new(1, 0.5)
		sgText(box, "QG", HEAD, CARD, 0, 0, 1, 1, Enum.TextXAlignment.Center)
		if acx and acz then
			local ax, az = mapUV(acx, acz)
			arrow(area, ux - 0.06, uz, ax + 0.04, az + 0.03, red)
			local ring = sgBox(area, red, ax, az, 0.12, 0.12, 1)
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(1, 0)
			rc.Parent = ring
			local rs = Instance.new("UIStroke")
			rs.Color = red
			rs.Thickness = 3
			rs.Transparency = 0.15
			rs.Parent = ring
		end
	else
		local flag = sgBox(area, red, vx, vz, 0.05, 0.035, 0.1)
		flag.AnchorPoint = Vector2.new(0, 0.5)
		sgText(flag, "BCH", VIET, CARD, 0, 0, 1, 1, Enum.TextXAlignment.Center)
		if nyx and nyz then
			local nx, nz = mapUV(nyx, nyz)
			arrow(area, vx + 0.06, vz, nx - 0.03, nz + 0.02, red)
		end
		if acx and acz then
			local ax, az = mapUV(acx, acz)
			arrow(area, vx + 0.06, vz - 0.03, ax - 0.04, az - 0.02, red)
		end
	end
	-- margens: título e legenda
	if us then
		sgText(sg, "CARTA\n1:50.000", HEAD, ink, 0.015, 0.05, 0.19, 0.16)
		sgText(sg, "VẠN TƯỜNG\nQUẢNG NGÃI", VIET, ink, 0.015, 0.23, 0.19, 0.12)
		sgText(sg, "Grade UTM\n500 m · BS", TYPE, rgb(70, 96, 140), 0.015, 0.8, 0.19, 0.12)
		sgText(sg, "■ QG\n● ponto forte\n→ eixo", TYPE, ink, 0.80, 0.05, 0.19, 0.2)
		sgStamp(sg, "SECRETO", red, 0.80, 0.78, 0.18, 0.1, -8) -- em português: o dicionário traduz
	else
		sgText(sg, "SƠ ĐỒ\nVẠN TƯỜNG", VIET, ink, 0.015, 0.05, 0.19, 0.16)
		sgText(sg, "Trung đoàn 1\n8 · 1965", VIET, ink, 0.015, 0.8, 0.19, 0.12)
		sgStamp(sg, "MẬT", red, 0.82, 0.78, 0.14, 0.1, 6)
	end
end

-- ===== animações de "abrir" =====
-- gira o grupo em volta de uma dobradiça (CFrame no mundo) pelo ângulo dado (rad, eixos da dobradiça)
-- pivô no centro do grupo (Model novo sem PrimaryPart pode ter o pivô longe, na origem do mundo)
local function centerPivot(g: Model): CFrame
	local cf = g:GetBoundingBox()
	local p = CFrame.new(cf.Position)
	g.WorldPivot = p
	return p
end

local function hinge(g: Model, pivotWorld: CFrame, angles: Vector3, time: number?): (boolean) -> ()
	local closed = centerPivot(g)
	local rel = pivotWorld:Inverse() * closed
	local v = Instance.new("NumberValue")
	v.Changed:Connect(function(a: number)
		g:PivotTo(pivotWorld * CFrame.Angles(angles.X * a, angles.Y * a, angles.Z * a) * rel)
	end)
	local info = TweenInfo.new(time or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	return function(on: boolean)
		TweenService:Create(v, info, { Value = if on then 1 else 0 }):Play()
	end
end

-- leva o grupo de onde está até `opened` (no mundo)
local function lift(g: Model, offset: CFrame, time: number?): (boolean) -> ()
	local closed = centerPivot(g)
	local opened = closed * offset
	local v = Instance.new("NumberValue")
	v.Changed:Connect(function(a: number)
		g:PivotTo(closed:Lerp(opened, a))
	end)
	local info = TweenInfo.new(time or 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	return function(on: boolean)
		TweenService:Create(v, info, { Value = if on then 1 else 0 }):Play()
	end
end

-- ===== modelos publicados (PreviewService põe em VT65Preview.Props) =====
local function propSource(key: string): Model?
	local root = ReplicatedStorage:FindFirstChild("VT65Preview")
	local props = root and root:FindFirstChild("Props")
	local m = props and props:FindFirstChild(key)
	if not (m and m:IsA("Model")) then
		return nil
	end
	local want = m:GetAttribute("Parts")
	if type(want) == "number" then
		local n = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		if n < want then
			return nil -- ainda chegando
		end
	end
	return m
end

-- encaixa o modelo publicado na caixa `size` (studs, eixos do próprio modelo), base no chão do lugar
local function fillSlot(slot: PropSlot)
	if slot.filled then
		return
	end
	local src = propSource(slot.key)
	if not src then
		return
	end
	slot.filled = true
	local m = src:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m:PivotTo(slot.place)
	local _, size = m:GetBoundingBox()
	local k = math.min(slot.size.X / size.X, slot.size.Y / size.Y, slot.size.Z / size.Z)
	if k > 0 and k == k and math.abs(k - 1) > 0.02 then
		m:ScaleTo(m:GetScale() * k)
	end
	local cf, sz = m:GetBoundingBox()
	local want = slot.place.Position
	local bottom = cf.Position.Y - sz.Y / 2
	m:PivotTo(m:GetPivot() + Vector3.new(want.X - cf.Position.X, want.Y - bottom, want.Z - cf.Position.Z))
	m.Name = "Prop_" .. slot.key
	m.Parent = slot.holder
	local fb = slot.fallback
	if fb then
		fb:Destroy()
		slot.fallback = nil
	end
end

-- lugar de um modelo publicado; enquanto ele não chega (ou sem ID), vale o feito de peças
local function prop(holder: Model, key: string, place: CFrame, size: Vector3, fallback: Model?)
	local slot: PropSlot =
		{ key = key, holder = holder, place = W(place), size = size / M, fallback = fallback, filled = false }
	table.insert(propSlots, slot)
	fillSlot(slot)
end

-- ===== cenas =====
local scenes: { [string]: Scene } = {}

local function newScene(id: string, offset: Vector3): Scene
	local folder = Instance.new("Model")
	folder.Name = "VT65Lobby_" .. id
	local hits = Instance.new("Folder")
	hits.Name = "Hits"
	hits.Parent = folder
	return {
		id = id,
		root = CFrame.new(BASE + offset),
		folder = folder,
		hits = hits,
		objects = {},
		byHit = {},
		lights = {},
		spots = {},
		overview = { focus = Vector3.zero, view = Vector3.yAxis, dist = 10 },
		previews = {},
	}
end

local function shot(fx: number, fy: number, fz: number, vx: number, vy: number, vz: number, dist: number): Shot
	return { focus = V(fx, fy, fz), view = D(vx, vy, vz), dist = dist / M }
end

-- objeto clicável: caixa invisível de raycast + realce no grupo
local function addObj(
	sc: Scene,
	id: string,
	model: Model,
	box: Vector3,
	boxAt: CFrame,
	title: string,
	sub: string,
	sh: Shot,
	font: Enum.Font?
): Obj
	local hit = part(sc.hits, box.X, box.Y, box.Z, boxAt, Color3.new(1, 1, 1))
	hit.Name = "Hit_" .. id
	hit.Transparency = 1
	hit.CanQuery = true
	local top = (W(boxAt) * CFrame.new(0, box.Y / M / 2, 0)).Position
	local o: Obj = {
		id = id,
		model = model,
		hit = hit,
		title = title,
		sub = sub,
		font = font or HEAD,
		shot = sh,
		top = top,
		open = nil,
		confirmTouch = false,
	}
	table.insert(sc.objects, o)
	sc.byHit[hit] = o
	return o
end

local function flicker(sc: Scene, l: Light)
	table.insert(sc.lights, { light = l, base = l.Brightness, seed = #sc.lights * 7.3 + 1.1 })
end

-- mesa genérica: tampo, pernas e (opcional) tábuas separadas
local function table_(parent: Instance, w: number, d: number, color: Color3, mat: Enum.Material, planks: boolean)
	local t = group(parent, "Mesa")
	if planks then
		local n = 4
		for i = 1, n do
			local z = -d / 2 + (i - 0.5) * d / n
			part(
				t,
				w,
				0.045,
				d / n - 0.008,
				at(0, -0.0225, z, (i % 2 - 0.5) * 0.6),
				color:Lerp(rgb(60, 44, 30), (i % 3) * 0.08),
				mat
			)
		end
	else
		part(t, w, 0.045, d, at(0, -0.0225, 0), color, mat)
		part(t, w + 0.01, 0.02, 0.02, at(0, -0.03, d / 2), color:Lerp(INK, 0.25), mat)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (w / 2 - 0.07), sz * (d / 2 - 0.07)
			if planks then
				cyl(t, 0.73, 0.07, at(x, -0.41, z) * UPRIGHT, rgb(78, 60, 42), Enum.Material.Wood)
			else
				part(t, 0.045, 0.73, 0.045, at(x, -0.41, z), color:Lerp(INK, 0.15), mat)
			end
		end
	end
	return t
end

-- soldado de pé (prévia do servidor), dentro de um grupo próprio: o realce do objeto pega o boneco
local function soldier(sc: Scene, side: string, x: number, z: number, yaw: number): Model
	local holder = group(sc.folder, "Soldado" .. side)
	-- a prévia tem a frente em −Z (SoldierPreview) e a câmera olha da frente da mesa (+Z): sem os
	-- 180°, os soldados ficavam de costas (Studio, 2026-11-11)
	local stand = W(at(x, -0.76, z, yaw + 180))
	local pv = SoldierPreview.newWorld(holder, stand)
	sc.previews[side] = pv
	SoldierPreview.set(pv, side, nil)
	return holder
end

-- ---------- EUA: barraca de comando ----------
local function buildUS(): Scene
	local sc = newScene("US", Vector3.zero)
	R = sc.root
	local f = sc.folder
	local canvas, canvasDark = rgb(96, 98, 68), rgb(78, 80, 54)
	local room = group(f, "Barraca")
	part(room, 5.2, 0.06, 4.6, at(0, -0.79, 0), rgb(104, 88, 64), Enum.Material.WoodPlanks) -- estrado
	part(room, 5.2, 1.95, 0.04, at(0, 0.215, -1.6), canvas, Enum.Material.Fabric) -- fundo
	part(room, 5.2, 1.95, 0.04, at(0, 0.215, 3.0), canvas, Enum.Material.Fabric) -- frente (atrás da câmera)
	part(room, 0.04, 1.95, 4.6, at(-2.6, 0.215, 0.7), canvas, Enum.Material.Fabric)
	part(room, 0.04, 1.95, 4.6, at(2.6, 0.215, 0.7), canvas, Enum.Material.Fabric)
	for _, s in { -1, 1 } do -- teto de duas águas
		local half = 2.6
		local rise = 1.1
		local len = math.sqrt(half * half + rise * rise)
		local ang = math.atan2(rise, half)
		part(
			room,
			len + 0.05,
			0.04,
			4.7,
			at(s * half / 2, 1.19 + rise / 2, 0.7) * CFrame.Angles(0, 0, s * -ang),
			canvasDark,
			Enum.Material.Fabric
		)
	end
	for i = -2, 2 do -- costuras da lona no fundo
		part(room, 0.03, 1.95, 0.01, at(i * 1.05, 0.215, -1.575), canvasDark, Enum.Material.Fabric)
	end
	for _, x in { -2.2, 2.2 } do -- mastros
		cyl(room, 3.1, 0.08, at(x, 0.76, -1.45) * UPRIGHT, rgb(112, 86, 56), Enum.Material.Wood)
	end
	-- quadro de avisos na lona do fundo
	local board = part(room, 1.25, 0.8, 0.03, at(-0.55, 0.62, -1.56) * FACE, rgb(150, 116, 78), Enum.Material.Fabric)
	local bsg = surface(board, 120)
	local function note(x: number, y: number, w: number, h: number, rot: number, text: string, font: Enum.Font)
		local n = sgBox(bsg, CARD, x, y, w, h)
		n.Rotation = rot
		sgText(n, text, font, INK, 0.06, 0.06, 0.88, 0.88)
		sgBox(n, STAMP, 0.47, 0.02, 0.06, 0.06)
	end
	note(0.04, 0.06, 0.42, 0.42, -3, "III MAF · CHU LAI\nOPERAÇÃO STARLITE\nDIA D 18 AGO 65\nHORA H 0630", TYPE)
	note(0.52, 0.08, 0.42, 0.36, 2, "RLT-7\n3/3 · 2/4 · 3/7\nGREEN BEACH\nLZ RED · WHITE · BLUE", TYPE)
	local ph = sgBox(bsg, rgb(236, 234, 226), 0.08, 0.56, 0.3, 0.38)
	ph.Rotation = 4
	sgBox(ph, rgb(92, 96, 90), 0.07, 0.07, 0.86, 0.66)
	sgText(ph, "FOTO AÉREA", TYPE, INK, 0.07, 0.76, 0.86, 0.2, Enum.TextXAlignment.Center)
	local ph2 = sgBox(bsg, rgb(236, 234, 226), 0.56, 0.54, 0.34, 0.4)
	ph2.Rotation = -5
	sgBox(ph2, rgb(110, 112, 104), 0.07, 0.07, 0.86, 0.66)
	sgText(ph2, "VẠN TƯỜNG", VIET, INK, 0.07, 0.76, 0.86, 0.2, Enum.TextXAlignment.Center)
	-- sacos de areia no pé da lona do fundo (modelo publicado ou caixas)
	local bags = group(f, "Sacos")
	local fbBags = group(bags, "Fallback")
	for i = 0, 3 do
		for j = 0, 1 do
			blob(
				fbBags,
				0.5,
				0.17,
				0.32,
				at(1.05 + i * 0.47 + j * 0.23, -0.67 + j * 0.16, -1.36),
				rgb(142, 126, 92),
				Enum.Material.Fabric
			)
		end
	end
	prop(bags, "sandbags", at(1.75, -0.76, -1.36, 90), Vector3.new(0.48, 0.7, 2.05), fbBags)
	-- mesa de campanha
	table_(f, 1.8, 0.9, rgb(88, 84, 60), Enum.Material.Wood, false)
	-- lampião (a luz principal)
	local lamp = group(f, "Lampiao")
	cyl(lamp, 0.05, 0.12, at(-0.32, 0.025, -0.34) * UPRIGHT, rgb(60, 62, 44), Enum.Material.Metal)
	local glass = cyl(lamp, 0.14, 0.095, at(-0.32, 0.12, -0.34) * UPRIGHT, rgb(255, 236, 200), Enum.Material.Glass)
	glass.Transparency = 0.55
	local flame = blob(lamp, 0.025, 0.05, 0.025, at(-0.32, 0.11, -0.34), rgb(255, 170, 70), Enum.Material.Neon)
	cyl(lamp, 0.03, 0.1, at(-0.32, 0.205, -0.34) * UPRIGHT, rgb(60, 62, 44), Enum.Material.Metal)
	part(lamp, 0.004, 0.09, 0.11, at(-0.32, 0.25, -0.34), rgb(40, 40, 36), Enum.Material.Metal)
	flicker(sc, light(flame, rgb(255, 184, 116), 4.6, 2.6, true))
	-- luz de enchimento fraca (lâmpada pendurada no alto)
	local bulb = blob(f, 0.06, 0.08, 0.06, at(0.4, 1.55, 0.6), rgb(255, 222, 170), Enum.Material.Neon)
	part(f, 0.006, 0.5, 0.006, at(0.4, 1.83, 0.6), rgb(30, 30, 28))
	light(bulb, rgb(255, 214, 160), 5.5, 0.55, false)
	-- carta 1:50.000 (inserção)
	local map = group(f, "Carta")
	local mapSheet = sheet(map, 0.95, 0.62, -0.12, 0, -0.12, 3, rgb(226, 222, 194))
	drawMap(mapSheet, "US")
	cyl(map, 0.15, 0.009, at(0.18, 0.006, -0.2, 30), rgb(170, 36, 28)) -- lápis de cera
	local prot = sheet(map, 0.12, 0.12, -0.38, 0.003, 0.02, -12, rgb(230, 236, 230), 0.002) -- transferidor
	prot.Transparency = 0.55
	addObj(
		sc,
		"insert",
		map,
		Vector3.new(0.95, 0.04, 0.62),
		at(-0.12, 0.02, -0.12, 3),
		"CARTA 1:50.000",
		"INSERÇÃO · pontos de entrada",
		shot(-0.12, 0, -0.12, 0, 1, 0.1, 0.98)
	)
	-- dossiê aberto (papel e equipamento)
	local dos = group(f, "Dossie")
	sheet(dos, 0.5, 0.33, 0.12, 0.004, 0.22, -5, MANILA, 0.004)
	local left = sheet(dos, 0.225, 0.3, 0.005, 0.008, 0.222, -5, CARD)
	local lsg = surface(left, 300)
	sgText(lsg, "OPERAÇÃO\nSTARLITE", HEAD, INK, 0.08, 0.06, 0.84, 0.26)
	sgText(lsg, "18 AGO 1965 · RLT-7", TYPE, INK, 0.08, 0.34, 0.84, 0.08)
	sgBox(lsg, UiKit.RULE_RED, 0.08, 0.44, 0.84, 0.008)
	sgText(lsg, "Ordem de deslocamento\ndo fuzileiro", TYPE, INK, 0.08, 0.48, 0.84, 0.14)
	sgStamp(lsg, "SECRETO", STAMP, 0.18, 0.72, 0.64, 0.14, -7)
	local pages = group(dos, "Pagina")
	local right = sheet(pages, 0.225, 0.3, 0.235, 0.009, 0.202, -5, CARD)
	local rsg = surface(right, 300)
	sgText(rsg, "FICHA DO FUZILEIRO", HEAD, INK, 0.08, 0.05, 0.84, 0.1)
	sgBox(rsg, UiKit.RULE_RED, 0.08, 0.16, 0.84, 0.008)
	for i = 1, 7 do
		sgBox(rsg, UiKit.RULE_BLUE, 0.08, 0.2 + i * 0.09, 0.84, 0.004, 0.5)
	end
	liveText("dossier", sgText(rsg, "", TYPE, INK, 0.08, 0.2, 0.84, 0.66))
	part(dos, 0.03, 0.006, 0.008, at(0.31, 0.012, 0.07, -5), rgb(150, 150, 150), Enum.Material.Metal) -- clipe
	cyl(dos, 0.17, 0.008, at(0.36, 0.008, 0.33, 80), rgb(196, 160, 60), Enum.Material.Wood) -- lápis
	local hingeAt = W(at(0.12, 0.012, 0.22, -5))
	local o = addObj(
		sc,
		"role",
		dos,
		Vector3.new(0.5, 0.05, 0.34),
		at(0.12, 0.02, 0.22, -5),
		"DOSSIÊ STARLITE",
		"PAPEL E EQUIPAMENTO",
		shot(0.78, 0.42, -1.05, -0.45, 0.12, 1, 2.35)
	)
	o.open = hinge(pages, hingeAt, Vector3.new(0, 0, math.rad(40)), 0.5) -- a folha da direita levanta
	-- rádio PRC-10 (squad)
	local radio = group(f, "Radio")
	local olive = rgb(70, 76, 50)
	part(radio, 0.29, 0.31, 0.11, at(0.64, 0.155 + 0.12, -0.2) * FACE, olive, Enum.Material.Metal)
	part(radio, 0.29, 0.12, 0.11, at(0.64, 0.06, -0.2) * FACE, rgb(62, 66, 44), Enum.Material.Metal) -- bateria
	part(radio, 0.292, 0.008, 0.112, at(0.64, 0.12, -0.2), rgb(40, 42, 32), Enum.Material.Metal)
	for i, x in { 0.56, 0.72 } do
		cyl(radio, 0.025, 0.035, at(x, 0.442, -0.2 + (i - 1.5) * 0.02) * UPRIGHT, rgb(30, 30, 28))
	end
	cyl(
		radio,
		0.82,
		0.006,
		at(0.55, 0.83, -0.27) * CFrame.Angles(0, 0, math.rad(80)),
		rgb(40, 42, 32),
		Enum.Material.Metal
	)
	local dial = part(radio, 0.2, 0.09, 0.004, at(0.64, 0.33, -0.143) * FACE, rgb(24, 24, 20), Enum.Material.Glass)
	local dsg = surface(dial, 400)
	sgText(dsg, "AN/PRC-10 · 38–54,9 MC", TYPE, rgb(214, 196, 140), 0.05, 0.05, 0.9, 0.3)
	liveText("radio", sgText(dsg, "", HEAD, rgb(255, 200, 110), 0.05, 0.4, 0.9, 0.55, Enum.TextXAlignment.Center))
	local handset = group(radio, "Fone")
	part(handset, 0.2, 0.035, 0.045, at(0.43, 0.02, -0.02, 20), rgb(26, 26, 24))
	cyl(handset, 0.04, 0.06, at(0.34, 0.03, -0.055, 20) * UPRIGHT, rgb(30, 30, 28))
	cyl(handset, 0.04, 0.06, at(0.52, 0.03, 0.013, 20) * UPRIGHT, rgb(30, 30, 28))
	for i = 0, 4 do -- fio enrolado
		cyl(radio, 0.05, 0.012, at(0.47 + i * 0.03, 0.01, -0.1 - i * 0.02, 50), rgb(20, 20, 18))
	end
	o = addObj(
		sc,
		"squad",
		radio,
		Vector3.new(0.42, 0.48, 0.32),
		at(0.58, 0.24, -0.14),
		"RÁDIO PRC-10",
		"SQUAD · formar ou entrar",
		shot(0.6, 0.2, -0.16, -0.3, 0.55, 1, 1.0)
	)
	o.open = lift(handset, CFrame.new(0, 0.32 / M, 0.05 / M) * CFrame.Angles(math.rad(-25), 0, math.rad(12)))
	-- lata de munição .30 (intendência)
	local can = group(f, "Municao")
	part(can, 0.28, 0.17, 0.095, at(0.68, 0.085, 0.27) * FACE, rgb(76, 82, 52), Enum.Material.Metal)
	local lid = group(can, "Tampa")
	part(lid, 0.285, 0.02, 0.1, at(0.68, 0.18, 0.27), rgb(70, 76, 48), Enum.Material.Metal)
	part(lid, 0.06, 0.012, 0.02, at(0.68, 0.195, 0.27), rgb(50, 54, 36), Enum.Material.Metal)
	local sten = part(can, 0.24, 0.1, 0.002, at(0.68, 0.09, 0.3185) * FACE, rgb(76, 82, 52), Enum.Material.Metal)
	sten.Transparency = 1
	local ssg = surface(sten, 400)
	sgText(
		ssg,
		"CAL .30 · 250 CTGS\nBALL M2 · LINKED",
		TYPE,
		rgb(222, 200, 90),
		0.02,
		0.05,
		0.96,
		0.9,
		Enum.TextXAlignment.Center
	)
	o = addObj(
		sc,
		"shop",
		can,
		Vector3.new(0.3, 0.22, 0.14),
		at(0.68, 0.1, 0.27),
		"CAIXA DE MUNIÇÃO",
		"INTENDÊNCIA (LOJA)",
		shot(0.66, 0.08, 0.26, -0.35, 0.8, 1, 0.78)
	)
	o.open = hinge(lid, W(at(0.68, 0.19, 0.2225)), Vector3.new(math.rad(-70), 0, 0), 0.4) -- dobradiça atrás
	-- calendário de mesa AGO 1965 (recompensa diária)
	local cal = group(f, "Calendario")
	part(cal, 0.16, 0.13, 0.006, at(-0.66, 0.062, 0.25) * FACE * CFrame.Angles(math.rad(22), 0, 0), rgb(60, 56, 44)) -- base em A
	local page = group(cal, "Folha")
	local front =
		part(page, 0.15, 0.125, 0.003, at(-0.66, 0.064, 0.233) * FACE * CFrame.Angles(math.rad(22), 0, 0), CARD)
	local csg = surface(front, 600)
	sgBox(csg, STAMP, 0, 0, 1, 0.24)
	sgText(csg, "AUG · 1965", HEAD, CARD, 0.05, 0.02, 0.9, 0.2, Enum.TextXAlignment.Center)
	liveText("calDay", sgText(csg, "18", HEAD, INK, 0.05, 0.25, 0.9, 0.5, Enum.TextXAlignment.Center))
	liveText("calNote", sgText(csg, "", TYPE, STAMP, 0.05, 0.76, 0.9, 0.2, Enum.TextXAlignment.Center))
	o = addObj(
		sc,
		"daily",
		cal,
		Vector3.new(0.2, 0.17, 0.12),
		at(-0.66, 0.07, 0.25),
		"CALENDÁRIO · AGO 1965",
		"RECOMPENSA DIÁRIA",
		shot(-0.64, 0.06, 0.22, 0.25, 0.85, 1, 0.62)
	)
	o.open = hinge(page, W(at(-0.66, 0.12, 0.21)), Vector3.new(math.rad(150), 0, 0), 0.5) -- a folha vira por cima
	-- capacete M1 (trocar de lado)
	local helm = group(f, "Capacete")
	local fbHelm = group(helm, "Fallback")
	blob(fbHelm, 0.3, 0.34, 0.33, at(-0.62, 0, -0.2), rgb(84, 90, 60), Enum.Material.Fabric)
	cyl(fbHelm, 0.012, 0.34, at(-0.62, 0.003, -0.2) * UPRIGHT, rgb(74, 80, 52), Enum.Material.Fabric)
	prop(helm, "us_m1_helmet", at(-0.62, 0, -0.2, -20), Vector3.new(0.31, 0.3, 0.27), fbHelm)
	o = addObj(
		sc,
		"faction",
		helm,
		Vector3.new(0.34, 0.2, 0.34),
		at(-0.62, 0.09, -0.2),
		"CAPACETE M1",
		"TROCAR DE LADO",
		shot(-0.6, 0.1, -0.2, 0.3, 0.7, 1, 0.85)
	)
	-- enfeites: caneca, ração, fotos
	local mug = group(f, "Caneca")
	cyl(mug, 0.1, 0.085, at(-0.3, 0.05, 0.3) * UPRIGHT, rgb(70, 74, 52), Enum.Material.Metal)
	cyl(mug, 0.004, 0.075, at(-0.3, 0.085, 0.3) * UPRIGHT, rgb(48, 30, 18))
	part(mug, 0.06, 0.012, 0.012, at(-0.36, 0.06, 0.3), rgb(70, 74, 52), Enum.Material.Metal)
	for _, xz in { { -0.44, 0.33 }, { -0.5, 0.26 } } do -- latas de ração (MCI)
		cyl(f, 0.09, 0.07, at(xz[1], 0.045, xz[2]) * UPRIGHT, rgb(92, 88, 60), Enum.Material.Metal)
	end
	local photo = sheet(f, 0.11, 0.08, 0.36, 0.004, -0.36, 14, rgb(236, 234, 226))
	local psg = surface(photo, 400)
	sgBox(psg, rgb(98, 102, 96), 0.07, 0.08, 0.86, 0.68)
	sgText(psg, "FOTO AÉREA · 17 AGO", TYPE, INK, 0.05, 0.78, 0.9, 0.2, Enum.TextXAlignment.Center)
	-- soldado ao lado da mesa
	addObj(
		sc,
		"role",
		soldier(sc, "US", 0.78, -1.05, -18),
		Vector3.new(0.62, 1.8, 0.5),
		at(0.78, 0.14, -1.05),
		"SEU FUZILEIRO",
		"PAPEL E EQUIPAMENTO",
		shot(0.78, 0.42, -1.05, -0.45, 0.12, 1, 2.35)
	)
	sc.overview = shot(0.02, 0, -0.04, 0, 1.12, 1, 1.95)
	return sc
end

-- ---------- VC: abrigo de terra ----------
local function buildVC(): Scene
	local sc = newScene("VC", Vector3.new(90, 0, 0))
	R = sc.root
	local f = sc.folder
	local earth, earthDark = rgb(92, 72, 50), rgb(70, 54, 38)
	local room = group(f, "Abrigo")
	part(room, 4.6, 0.08, 4.4, at(0, -0.8, 0.4), rgb(96, 76, 54), Enum.Material.Ground)
	part(room, 4.6, 2.0, 0.3, at(0, 0.24, -1.6), earth, Enum.Material.Mud)
	part(room, 4.6, 2.0, 0.3, at(0, 0.24, 2.6), earth, Enum.Material.Mud)
	part(room, 0.3, 2.0, 4.4, at(-2.2, 0.24, 0.4), earthDark, Enum.Material.Mud)
	part(room, 0.3, 2.0, 4.4, at(2.2, 0.24, 0.4), earthDark, Enum.Material.Mud)
	for i = 0, 18 do -- teto de toras
		cyl(
			room,
			4.6,
			0.2,
			at(0, 1.3, -1.45 + i * 0.22) * CFrame.Angles(0, 0, 0),
			rgb(72 + (i % 3) * 6, 54, 36),
			Enum.Material.Wood
		)
	end
	for _, x in { -1.9, 1.9 } do -- esteios
		cyl(room, 2.05, 0.16, at(x, 0.27, -1.38) * UPRIGHT, rgb(80, 60, 40), Enum.Material.Wood)
	end
	-- bandeira da Frente (vermelho em cima, azul embaixo, estrela amarela)
	local flag = part(room, 0.9, 0.6, 0.01, at(-0.25, 0.62, -1.44) * FACE, rgb(200, 40, 32), Enum.Material.Fabric)
	local fsg = surface(flag, 160)
	sgBox(fsg, rgb(200, 40, 32), 0, 0, 1, 0.5, 0.05)
	sgBox(fsg, rgb(36, 110, 190), 0, 0.5, 1, 0.5, 0.05)
	sgText(fsg, "★", VIET, rgb(255, 206, 0), 0.32, 0.15, 0.36, 0.7, Enum.TextXAlignment.Center)
	for _, x in { -0.68, 0.18 } do
		cyl(
			room,
			0.04,
			0.02,
			at(x, 0.9, -1.43) * CFrame.Angles(0, math.pi / 2, 0),
			rgb(120, 120, 116),
			Enum.Material.Metal
		)
	end
	-- caixotes empilhados no canto
	for i = 0, 1 do
		part(room, 0.6, 0.32, 0.4, at(1.55, -0.6 + i * 0.33, -1.15, i * 8), rgb(118, 94, 62), Enum.Material.WoodPlanks)
	end
	-- mesa de tábuas
	table_(f, 1.6, 0.85, rgb(122, 96, 66), Enum.Material.WoodPlanks, true)
	-- lamparina
	local lamp = group(f, "Lamparina")
	local bottle = cyl(lamp, 0.1, 0.07, at(-0.34, 0.05, -0.3) * UPRIGHT, rgb(170, 190, 170), Enum.Material.Glass)
	bottle.Transparency = 0.4
	cyl(lamp, 0.02, 0.03, at(-0.34, 0.11, -0.3) * UPRIGHT, rgb(110, 100, 80), Enum.Material.Metal)
	local flame = blob(lamp, 0.02, 0.045, 0.02, at(-0.34, 0.145, -0.3), rgb(255, 150, 60), Enum.Material.Neon)
	flicker(sc, light(flame, rgb(255, 156, 86), 4.0, 2.4, true))
	-- croqui feito à mão (inserção)
	local map = group(f, "Croqui")
	local mapSheet = sheet(map, 0.85, 0.6, -0.1, 0, -0.1, -3, rgb(204, 186, 144))
	drawMap(mapSheet, "VC")
	cyl(map, 0.13, 0.008, at(0.22, 0.006, -0.22, -40), rgb(40, 34, 30)) -- caneta
	addObj(
		sc,
		"insert",
		map,
		Vector3.new(0.85, 0.04, 0.6),
		at(-0.1, 0.02, -0.1, -3),
		"CROQUI DE VẠN TƯỜNG",
		"INSERÇÃO · pontos de entrada",
		shot(-0.1, 0, -0.1, 0, 1, 0.1, 0.92),
		VIET
	)
	-- maço de documentos amarrado (papel e equipamento)
	local docs = group(f, "Documentos")
	sheet(docs, 0.3, 0.38, 0.12, 0.004, 0.22, 4, rgb(214, 200, 160), 0.008)
	sheet(docs, 0.29, 0.37, 0.125, 0.012, 0.215, -3, rgb(222, 210, 172), 0.004)
	local topSheet = group(docs, "Folha")
	local top = sheet(topSheet, 0.28, 0.36, 0.12, 0.016, 0.22, 1, rgb(230, 220, 186))
	local tsg = surface(top, 300)
	sgText(tsg, "TRUNG ĐOÀN 1", VIET, INK, 0.08, 0.05, 0.84, 0.1)
	sgText(tsg, "QUÂN GIẢI PHÓNG", VIET, INK, 0.08, 0.15, 0.84, 0.08)
	sgBox(tsg, UiKit.RULE_RED, 0.08, 0.25, 0.84, 0.006)
	liveText("dossier", sgText(tsg, "", VIET, INK, 0.08, 0.29, 0.84, 0.5))
	sgStamp(tsg, "MẬT", STAMP, 0.6, 0.8, 0.3, 0.12, -10)
	part(docs, 0.33, 0.006, 0.012, at(0.12, 0.022, 0.22, 1), rgb(140, 70, 50), Enum.Material.Fabric) -- barbante
	part(docs, 0.012, 0.006, 0.41, at(0.12, 0.022, 0.22, 1), rgb(140, 70, 50), Enum.Material.Fabric)
	local o = addObj(
		sc,
		"role",
		docs,
		Vector3.new(0.34, 0.06, 0.42),
		at(0.12, 0.02, 0.22),
		"DOCUMENTOS DO REGIMENTO",
		"PAPEL E EQUIPAMENTO",
		shot(0.75, 0.42, -1.0, -0.45, 0.12, 1, 2.3)
	)
	o.open = lift(topSheet, CFrame.new(-0.06 / M, 0.06 / M, 0) * CFrame.Angles(0, 0, math.rad(-8)))
	-- telefone de campanha (squad)
	local phone = group(f, "Telefone")
	part(phone, 0.24, 0.16, 0.13, at(0.6, 0.08, -0.18, -10) * FACE, rgb(94, 68, 42), Enum.Material.Leather)
	cyl(phone, 0.05, 0.03, at(0.735, 0.09, -0.2, -10), rgb(60, 50, 40), Enum.Material.Metal)
	part(phone, 0.012, 0.07, 0.012, at(0.765, 0.07, -0.2, -10), rgb(60, 50, 40), Enum.Material.Metal) -- manivela
	local fone = group(phone, "Fone")
	part(fone, 0.2, 0.03, 0.04, at(0.6, 0.175, -0.18, -10), rgb(24, 24, 22))
	cyl(fone, 0.035, 0.055, at(0.51, 0.18, -0.165, -10) * UPRIGHT, rgb(28, 28, 26))
	cyl(fone, 0.035, 0.055, at(0.69, 0.18, -0.195, -10) * UPRIGHT, rgb(28, 28, 26))
	local plate = part(phone, 0.16, 0.06, 0.002, at(0.61, 0.08, -0.11, -10) * FACE, rgb(94, 68, 42))
	plate.Transparency = 1
	liveText("radio", sgText(surface(plate, 400), "", VIET, rgb(232, 210, 160), 0, 0, 1, 1, Enum.TextXAlignment.Center))
	o = addObj(
		sc,
		"squad",
		phone,
		Vector3.new(0.32, 0.24, 0.22),
		at(0.62, 0.11, -0.18),
		"TELEFONE DE CAMPANHA",
		"SQUAD · formar ou entrar",
		shot(0.6, 0.1, -0.16, -0.3, 0.6, 1, 0.85)
	)
	o.open = lift(fone, CFrame.new(0, 0.28 / M, 0.05 / M) * CFrame.Angles(math.rad(-20), 0, math.rad(10)))
	-- caixote de munição (intendência)
	local crate = group(f, "Caixote")
	part(crate, 0.36, 0.15, 0.22, at(0.62, 0.075, 0.27, 6) * FACE, rgb(126, 102, 68), Enum.Material.WoodPlanks)
	local cl = group(crate, "Tampa")
	part(cl, 0.37, 0.025, 0.23, at(0.62, 0.162, 0.27, 6), rgb(116, 94, 62), Enum.Material.WoodPlanks)
	local cst = part(crate, 0.3, 0.1, 0.002, at(0.632, 0.075, 0.382, 6) * FACE, rgb(126, 102, 68))
	cst.Transparency = 1
	sgText(surface(cst, 400), "7,62 · 440", TYPE, rgb(30, 26, 20), 0.05, 0.1, 0.9, 0.8, Enum.TextXAlignment.Center)
	o = addObj(
		sc,
		"shop",
		crate,
		Vector3.new(0.4, 0.2, 0.26),
		at(0.62, 0.09, 0.27, 6),
		"CAIXOTE DE MUNIÇÃO",
		"INTENDÊNCIA (LOJA)",
		shot(0.6, 0.08, 0.26, -0.35, 0.8, 1, 0.8)
	)
	o.open = hinge(cl, W(at(0.62, 0.175, 0.16, 6)), Vector3.new(math.rad(-75), 0, 0), 0.4) -- dobradiça atrás
	-- caderneta "sổ tay" (recompensa diária)
	local book = group(f, "Caderneta")
	sheet(book, 0.13, 0.18, -0.62, 0.004, 0.22, 8, rgb(226, 214, 180), 0.012)
	local cover = group(book, "Capa")
	local cv = sheet(cover, 0.135, 0.185, -0.62, 0.016, 0.22, 8, rgb(128, 48, 38), 0.004)
	local bsg = surface(cv, 600)
	sgText(bsg, "SỔ TAY", VIET, rgb(236, 210, 150), 0.1, 0.08, 0.8, 0.16, Enum.TextXAlignment.Center)
	liveText("calDay", sgText(bsg, "18", HEAD, rgb(236, 210, 150), 0.1, 0.3, 0.8, 0.36, Enum.TextXAlignment.Center))
	sgText(bsg, "8 · 1965", VIET, rgb(236, 210, 150), 0.1, 0.66, 0.8, 0.1, Enum.TextXAlignment.Center)
	liveText("calNote", sgText(bsg, "", TYPE, rgb(255, 214, 120), 0.05, 0.8, 0.9, 0.14, Enum.TextXAlignment.Center))
	cyl(book, 0.14, 0.009, at(-0.53, 0.01, 0.2, 75), rgb(30, 50, 90)) -- caneta
	o = addObj(
		sc,
		"daily",
		book,
		Vector3.new(0.18, 0.06, 0.22),
		at(-0.62, 0.02, 0.22, 8),
		"CADERNETA (SỔ TAY)",
		"RECOMPENSA DIÁRIA",
		shot(-0.6, 0.02, 0.2, 0.25, 0.9, 1, 0.6),
		VIET
	)
	o.open = hinge(cover, W(at(-0.6875, 0.02, 0.22, 8)), Vector3.new(0, 0, math.rad(165)), 0.5)
	-- capacete de fibra (trocar de lado)
	local helm = group(f, "Capacete")
	local fbHelm = group(helm, "Fallback")
	blob(fbHelm, 0.32, 0.3, 0.34, at(-0.6, 0, -0.22), rgb(132, 126, 86), Enum.Material.Fabric)
	cyl(fbHelm, 0.012, 0.4, at(-0.6, 0.004, -0.22) * UPRIGHT, rgb(122, 116, 78), Enum.Material.Fabric)
	prop(helm, "vc_pith_helmet", at(-0.6, 0, -0.22, 25), Vector3.new(0.33, 0.29, 0.29), fbHelm)
	addObj(
		sc,
		"faction",
		helm,
		Vector3.new(0.4, 0.2, 0.4),
		at(-0.6, 0.09, -0.22),
		"CAPACETE DE FIBRA",
		"TROCAR DE LADO",
		shot(-0.58, 0.1, -0.22, 0.3, 0.7, 1, 0.85)
	)
	-- tigela de arroz e hashis
	local bowl = group(f, "Tigela")
	cyl(bowl, 0.05, 0.11, at(-0.28, 0.025, 0.3) * UPRIGHT, rgb(210, 206, 196))
	cyl(bowl, 0.004, 0.095, at(-0.28, 0.05, 0.3) * UPRIGHT, rgb(240, 238, 230))
	cyl(bowl, 0.2, 0.006, at(-0.26, 0.06, 0.3, 20), rgb(150, 120, 70), Enum.Material.Wood)
	-- soldado
	addObj(
		sc,
		"role",
		soldier(sc, "VC", 0.75, -1.0, -18),
		Vector3.new(0.6, 1.75, 0.5),
		at(0.75, 0.12, -1.0),
		"SEU COMBATENTE",
		"PAPEL E EQUIPAMENTO",
		shot(0.75, 0.42, -1.0, -0.45, 0.12, 1, 2.3)
	)
	sc.overview = shot(0.02, 0, -0.04, 0, 1.12, 1, 1.85)
	return sc
end

-- ---------- sala de arquivo: escolha do lado ----------
local function buildChoose(): Scene
	local sc = newScene("choose", Vector3.new(-90, 0, 0))
	R = sc.root
	local f = sc.folder
	local wood = rgb(62, 52, 40)
	local room = group(f, "Sala")
	part(room, 5, 0.06, 4.6, at(0, -0.79, 0.5), rgb(84, 68, 50), Enum.Material.WoodPlanks)
	part(room, 5, 2.8, 0.06, at(0, 0.64, -1.7), wood, Enum.Material.WoodPlanks)
	part(room, 0.06, 2.8, 4.6, at(-2.5, 0.64, 0.5), wood, Enum.Material.WoodPlanks)
	part(room, 0.06, 2.8, 4.6, at(2.5, 0.64, 0.5), wood, Enum.Material.WoodPlanks)
	part(room, 5, 2.8, 0.06, at(0, 0.64, 2.8), wood, Enum.Material.WoodPlanks)
	part(room, 5, 0.06, 4.6, at(0, 2.07, 0.5), rgb(40, 34, 28), Enum.Material.Wood)
	-- arquivo de aço ao fundo
	for i = 0, 2 do
		part(room, 0.46, 1.3, 0.6, at(-1.7 + i * 0.5, -0.11, -1.35), rgb(88, 92, 82), Enum.Material.Metal)
		for j = 0, 3 do
			part(
				room,
				0.12,
				0.025,
				0.01,
				at(-1.7 + i * 0.5, 0.36 - j * 0.32, -1.045),
				rgb(170, 170, 160),
				Enum.Material.Metal
			)
		end
	end
	table_(f, 1.6, 0.85, rgb(110, 86, 60), Enum.Material.Wood, false)
	-- lâmpada pendurada sobre a mesa
	local bulb = blob(f, 0.07, 0.09, 0.07, at(0, 1.05, 0), rgb(255, 226, 176), Enum.Material.Neon)
	part(f, 0.006, 0.94, 0.006, at(0, 1.57, 0), rgb(26, 26, 24)) -- fio até o teto
	local shade = cyl(f, 0.1, 0.26, at(0, 1.12, 0) * UPRIGHT, rgb(46, 52, 40), Enum.Material.Metal)
	shade.Transparency = 0.1
	flicker(sc, light(bulb, rgb(255, 216, 168), 5.0, 2.2, true))
	-- dossiê dos EUA
	local us = group(f, "DossieEUA")
	local usSheet = sheet(us, 0.25, 0.32, -0.34, 0.004, 0.12, 7, MANILA, 0.008)
	local usg = surface(usSheet, 300)
	sgText(usg, "UNITED STATES\nMARINE CORPS", HEAD, INK, 0.08, 0.06, 0.84, 0.2, Enum.TextXAlignment.Center)
	sgStamp(usg, "USMC", STAMP, 0.18, 0.32, 0.64, 0.16, -6)
	sgText(
		usg,
		"RLT-7 · 3/3 · 2/4 · 3/7\nOPERATION STARLITE",
		TYPE,
		INK,
		0.08,
		0.6,
		0.84,
		0.2,
		Enum.TextXAlignment.Center
	)
	local o = addObj(
		sc,
		"pick_US",
		us,
		Vector3.new(0.3, 0.05, 0.36),
		at(-0.34, 0.02, 0.12, 7),
		"FUZILEIROS NAVAIS DOS EUA",
		"RLT-7 · alistar-se",
		shot(-0.34, 0.2, -0.3, 0.12, 0.45, 1, 2.0)
	)
	o.confirmTouch = true
	-- maço do VC
	local vc = group(f, "MacoVC")
	sheet(vc, 0.27, 0.34, 0.34, 0.004, 0.12, -5, rgb(160, 120, 80), 0.02)
	local vcTop = sheet(vc, 0.25, 0.32, 0.34, 0.024, 0.12, -5, rgb(214, 196, 150))
	local vsg = surface(vcTop, 300)
	sgText(vsg, "MẶT TRẬN DÂN TỘC\nGIẢI PHÓNG", VIET, INK, 0.08, 0.06, 0.84, 0.2, Enum.TextXAlignment.Center)
	sgStamp(vsg, "QUÂN GIẢI PHÓNG", STAMP, 0.08, 0.32, 0.84, 0.14, 5)
	sgText(vsg, "TRUNG ĐOÀN 1\nchủ lực", VIET, INK, 0.08, 0.6, 0.84, 0.2, Enum.TextXAlignment.Center)
	part(vc, 0.3, 0.006, 0.012, at(0.34, 0.03, 0.12, -5), rgb(140, 70, 50), Enum.Material.Fabric)
	part(vc, 0.012, 0.006, 0.37, at(0.34, 0.03, 0.12, -5), rgb(140, 70, 50), Enum.Material.Fabric)
	o = addObj(
		sc,
		"pick_VC",
		vc,
		Vector3.new(0.3, 0.06, 0.38),
		at(0.34, 0.02, 0.12, -5),
		"1º REGIMENTO VIET CONG",
		"Força principal · alistar-se",
		shot(0.34, 0.2, -0.3, -0.12, 0.45, 1, 2.0)
	)
	o.confirmTouch = true
	-- os dois soldados atrás da mesa, com um foco de luz cada
	for _, side in { "US", "VC" } do
		local x = if side == "US" then -0.7 else 0.7
		local body = soldier(sc, side, x, -0.8, if x < 0 then 12 else -12)
		local lampHolder = part(f, 0.05, 0.05, 0.05, at(x, 1.4, -0.4), rgb(20, 20, 20))
		lampHolder.Transparency = 1
		local sp = Instance.new("SpotLight")
		sp.Face = Enum.NormalId.Bottom
		sp.Angle = 50
		sp.Range = 3.4 / M
		sp.Brightness = 0.6
		sp.Color = rgb(255, 226, 186)
		sp.Parent = lampHolder
		sc.spots[side] = sp
		local who = addObj(
			sc,
			"pick_" .. side,
			body,
			Vector3.new(0.6, 1.8, 0.5),
			at(x, 0.14, -0.8),
			if side == "US" then "FUZILEIROS NAVAIS DOS EUA" else "1º REGIMENTO VIET CONG",
			"alistar-se",
			shot(x, 0.3, -0.8, 0, 0.3, 1, 2.2)
		)
		who.confirmTouch = true
	end
	sc.overview = shot(0, 0.28, -0.3, 0, 0.4, 1, 2.5)
	return sc
end

local function sceneFor(id: string): Scene
	local sc = scenes[id]
	if sc then
		return sc
	end
	local built = if id == "US" then buildUS() elseif id == "VC" then buildVC() else buildChoose()
	scenes[id] = built
	return built
end

-- os modelos publicados chegam depois: preenche os lugares que estavam com a versão de peças
local pendingProps = false
local function fillSoon()
	if pendingProps then
		return
	end
	pendingProps = true
	task.defer(function()
		pendingProps = false
		for _, s in propSlots do
			fillSlot(s)
		end
	end)
end
local function watchProps(folder: Instance)
	folder.DescendantAdded:Connect(fillSoon)
end
task.spawn(function()
	local root = ReplicatedStorage:WaitForChild("VT65Preview", 120)
	if root then
		watchProps(root)
		fillSoon()
	end
end)

-- ===== interface da cena: vinheta, etiquetas, escurecimento =====
local backdrop = Instance.new("ScreenGui")
backdrop.Name = "VT65LobbyBackdrop"
backdrop.ResetOnSpawn = false
backdrop.DisplayOrder = 18 -- abaixo das etiquetas (19) e dos menus (VT65Menus = 20)
backdrop.IgnoreGuiInset = true
backdrop.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
backdrop.Enabled = false
pcall(function()
	backdrop.ScreenInsets = Enum.ScreenInsets.None -- decoração: cobre também o entalhe da tela
end)
local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.BackgroundColor3 = UiKit.NIGHT
dim.BorderSizePixel = 0
dim.Size = UDim2.fromScale(1, 1)
dim.Parent = backdrop
-- vinheta: quatro faixas com gradiente de transparência (o UIGradient é só linear)
local edges: { Frame } = {}
local function edge(rot: number, size: UDim2, pos: UDim2, anchor: Vector2)
	local fr = Instance.new("Frame")
	fr.BackgroundColor3 = Color3.new(0, 0, 0)
	fr.BorderSizePixel = 0
	fr.AnchorPoint = anchor
	fr.Position = pos
	fr.Size = size
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = fr
	fr.Parent = backdrop
	table.insert(edges, fr)
end
edge(90, UDim2.fromScale(1, 0.26), UDim2.fromScale(0, 0), Vector2.zero)
edge(-90, UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 1), Vector2.new(0, 1))
edge(0, UDim2.fromScale(0.2, 1), UDim2.fromScale(0, 0), Vector2.zero)
edge(180, UDim2.fromScale(0.2, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0))
local fade = Instance.new("Frame")
fade.Name = "Fade"
fade.BackgroundColor3 = rgb(14, 12, 8) -- escuro quente (barraca à noite), não preto chapado
fade.BackgroundTransparency = 1
fade.BorderSizePixel = 0
fade.Size = UDim2.fromScale(1, 1)
fade.ZIndex = 5
fade.Parent = backdrop
-- película da mesa: leve (a cena 3D já tem luz própria), só com a câmera na mesa
local film = Acabamento.filme(backdrop, {
	vinheta = 0.5,
	grao = 0.32,
	poeira = 22,
	riscos = 1,
	tremor = 0.3,
	lampiao = 0.18,
	z = 3,
})
Acabamento.luz(film, UDim2.fromScale(0.5, -0.05), 1.5)
local filmOn = false
backdrop.Parent = player:WaitForChild("PlayerGui")

local tags = Instance.new("ScreenGui")
tags.Name = "VT65LobbyTags"
tags.ResetOnSpawn = false
tags.DisplayOrder = 19
tags.IgnoreGuiInset = true
tags.Enabled = false
pcall(function()
	tags.ScreenInsets = Enum.ScreenInsets.None
end)
tags.Parent = player:WaitForChild("PlayerGui")

-- etiqueta de papel presa ao objeto (nome da ação + linha de situação)
local function makeTag(hot: boolean): (Frame, TextLabel, TextLabel)
	local fr = Instance.new("Frame")
	fr.AnchorPoint = Vector2.new(0.5, 1)
	fr.AutomaticSize = Enum.AutomaticSize.XY
	fr.BackgroundColor3 = if hot then CARD else UiKit.DRAB
	fr.BorderSizePixel = 0
	fr.Visible = false
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 6)
	pad.Parent = fr
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.Parent = fr
	local st = Instance.new("UIStroke")
	st.Color = if hot then STAMP else KHAKI
	st.Thickness = 2
	st.Transparency = 0.2
	st.Parent = fr
	local light = Instance.new("UIGradient") -- papel com luz de cima, como as fichas
	light.Rotation = 90
	light.Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(206, 200, 186))
	light.Parent = fr
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = fr
	local t1 = Instance.new("TextLabel")
	t1.BackgroundTransparency = 1
	t1.AutomaticSize = Enum.AutomaticSize.XY
	t1.Font = HEAD
	t1.TextColor3 = if hot then INK else KHAKI
	t1.TextSize = UiKit.text(if hot then 22 else 16)
	t1.LayoutOrder = 1
	t1.Parent = fr
	local t2 = Instance.new("TextLabel")
	t2.BackgroundTransparency = 1
	t2.AutomaticSize = Enum.AutomaticSize.XY
	t2.Font = TYPE
	t2.TextColor3 = if hot then STAMP else KHAKI
	t2.TextSize = UiKit.text(15)
	t2.LayoutOrder = 2
	t2.Parent = fr
	fr.Parent = tags
	return fr, t1, t2
end
local hoverTag, hoverTitle, hoverSub = makeTag(true)
local nextTag, nextTitle, nextSub = makeTag(false)

-- ===== efeitos de pós-processamento (só no lobby) =====
local dof: DepthOfFieldEffect? = nil
local grade: ColorCorrectionEffect? = nil
local function setEffects(on: boolean)
	if on and not dof then
		local d = Instance.new("DepthOfFieldEffect")
		d.Name = "VT65LobbyDOF"
		d.FarIntensity = 0.35
		d.NearIntensity = 0.05
		d.FocusDistance = 8
		d.InFocusRadius = 5
		d.Parent = Lighting
		dof = d
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "VT65LobbyGrade"
		c.Brightness = 0.02
		c.Contrast = 0.08
		c.Saturation = -0.12
		c.TintColor = rgb(255, 238, 218)
		c.Parent = Lighting
		grade = c
	elseif not on and dof then
		dof:Destroy()
		dof = nil
		if grade then
			grade:Destroy()
			grade = nil
		end
	end
end

-- ===== estado =====
local lobbyOpen = false
local diedAt: number? = nil
local deskOn = false -- câmera na mesa
local current: Scene? = nil
local wantScene = "choose"
local focusId: string? = nil -- objeto em foco (painel aberto) ou nil = visão geral
local focusNdc = Vector2.new(-0.5, 0)
local overviewNdc = Vector2.new(0.22, 0)
local nextId: string? = nil
local externalHover: string? = nil
local hovered: Obj? = nil
local touchSel: Obj? = nil
local openObj: Obj? = nil
local subOverride: { [string]: string } = {}
local camFrom: CFrame? = nil
local camT = 1
local camDur = MOVE_TIME
local arriving = false -- próximo quadro começa o travelling de chegada
local wasCovered = false -- a tela de entrada (LoadingScreen) cobria a mesa no quadro anterior
local lastShow: Obj? = nil -- objeto realçado no quadro anterior (entrada do realce e da etiqueta)
local lastNext: Obj? = nil
local sway = Vector2.zero
local savedFov: number? = nil
local rainWas: boolean? = nil
local faction: string? = nil
local nextStream = 0
local t0 = os.clock()
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

LobbyScene.onActivate = function(_id: string) end -- o DeployScreen troca
LobbyScene.onHover = function(_id: string?) end

local function camera(): Camera?
	return workspace.CurrentCamera
end

local function objById(sc: Scene, id: string): Obj?
	for _, o in sc.objects do
		if o.id == id then
			return o
		end
	end
	return nil
end

-- câmera para um enquadramento: foco no ponto da tela (NDC) pedido
local function shotCF(s: Shot, ndc: Vector2): CFrame
	local cam = camera()
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local aspect = vp.X / math.max(vp.Y, 1)
	local tanV = math.tan(math.rad(FOV / 2))
	-- tela estreita (4:3, celular em pé): afasta um pouco para caber na largura, sem sair da sala
	local dist = s.dist * math.clamp(1.6 / math.max(aspect, 0.4), 1, 1.4)
	local eye = s.focus + s.view * dist
	local cf = CFrame.lookAt(eye, s.focus)
	return cf * CFrame.Angles(0, math.atan(ndc.X * tanV * aspect), 0) * CFrame.Angles(-math.atan(ndc.Y * tanV), 0, 0)
end

local function targetShot(): (Shot?, Vector2)
	local sc = current
	if not sc then
		return nil, Vector2.zero
	end
	local id = focusId
	if id then
		local o = objById(sc, id)
		if o then
			return o.shot, focusNdc
		end
	end
	return sc.overview, overviewNdc
end

local function startMove()
	local cam = camera()
	camFrom = if cam then cam.CFrame else nil
	camT = 0
	camDur = MOVE_TIME
	arriving = false
end

-- curva sem tranco: começa e termina com velocidade e aceleração zero (smootherstep)
local function smooth(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- A tela de entrada ainda cobre a mesa? (ela marca "Saindo" quando começa a esmaecer)
local function entryCovering(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local lg = pg and pg:FindFirstChild("VT65Loading")
	return lg ~= nil and lg:IsA("ScreenGui") and lg.Enabled and lg:GetAttribute("Saindo") ~= true
end

-- realce do objeto sob o ponteiro e contorno pulsante do "próximo passo"
local hl = Instance.new("Highlight")
hl.Name = "VT65LobbyHover"
hl.DepthMode = Enum.HighlightDepthMode.Occluded
hl.FillColor = rgb(255, 226, 160)
hl.FillTransparency = 0.82
hl.OutlineColor = rgb(255, 214, 110)
hl.OutlineTransparency = 0.05
hl.Enabled = false
local nextHl = Instance.new("Highlight")
nextHl.Name = "VT65LobbyNext"
nextHl.DepthMode = Enum.HighlightDepthMode.Occluded
nextHl.FillTransparency = 1
nextHl.OutlineColor = rgb(226, 110, 70)
nextHl.Enabled = false

-- ===== streaming do QG (o spawn fica pronto enquanto o jogador escolhe) =====
local function stream()
	local f = faction
	local hq = f and MapConfig.HQ[f]
	if not hq then
		return
	end
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(Vector3.new(hq.x, 30, hq.z), 10)
		end)
	end)
end

-- ===== troca de cena (escurece, troca, clareia) =====
local function applyScene(id: string)
	local sc = sceneFor(id)
	if current == sc then
		return
	end
	local old = current
	if old then
		old.folder.Parent = nil
		if openObj then
			local fn = openObj.open
			if fn then
				fn(false)
			end
			openObj = nil
		end
	end
	current = sc
	sc.folder.Parent = workspace
	hl.Parent = sc.folder
	nextHl.Parent = sc.folder
	params.FilterDescendantsInstances = { sc.hits }
	hovered, touchSel = nil, nil
	lastShow, lastNext = nil, nil
	-- cena nova: a câmera chega num travelling (sai de um pouco mais longe e assenta)
	camFrom, camT = nil, 1
	arriving = true
end

local fadeToken = 0
local function switchScene(id: string)
	if current and current.id == id then
		return
	end
	if not deskOn or not current then
		applyScene(id)
		return
	end
	fadeToken += 1
	local my = fadeToken
	TweenService
		:Create(
			fade,
			TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ BackgroundTransparency = 0 }
		)
		:Play()
	task.delay(0.21, function()
		if my ~= fadeToken then
			return
		end
		applyScene(wantScene)
		TweenService:Create(
			fade,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end)
end

-- ===== realce =====
local function setHovered(o: Obj?)
	if o == hovered then
		return
	end
	hovered = o
	LobbyScene.onHover(if o then o.id else nil)
	local sc = current
	if sc then
		for fct, sp in sc.spots do
			sp.Brightness = if o and o.id == "pick_" .. fct then 3.2 else 0.6
		end
	end
end

local function raycastAt(ray: Ray): Obj?
	local sc = current
	if not sc then
		return nil
	end
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	if hit and hit.Instance:IsA("BasePart") then
		return sc.byHit[hit.Instance]
	end
	return nil
end

local function activate(o: Obj)
	LobbyScene.onActivate(o.id)
end

-- A do cursor virtual sobre a cena
VirtualCursor.world = {
	activate = function(pos: Vector2)
		local cam = camera()
		if not (deskOn and lobbyOpen and cam) then
			return
		end
		local o = raycastAt(cam:ViewportPointToRay(pos.X, pos.Y))
		if o then
			activate(o)
		end
	end,
	targets = function(): { Vector2 }
		local out = {}
		local cam = camera()
		local sc = current
		if not (deskOn and lobbyOpen and cam and sc) then
			return out
		end
		local seen: { [string]: boolean } = {}
		for _, o in sc.objects do
			if not seen[o.id] then
				seen[o.id] = true
				local p, onScreen = cam:WorldToViewportPoint(o.hit.Position)
				if onScreen then
					table.insert(out, Vector2.new(p.X, p.Y))
				end
			end
		end
		return out
	end,
}

-- mouse: clique na cena (o processado pela interface não chega aqui)
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not (deskOn and lobbyOpen) then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and hovered then
		activate(hovered)
	end
end)

-- toque: tocar escolhe; os dossiês de lado pedem um 2º toque (o 1º mostra a ficha)
UserInputService.TouchTap:Connect(function(positions: { Vector2 }, processed: boolean)
	local cam = camera()
	if processed or not (deskOn and lobbyOpen and cam) or #positions == 0 then
		return
	end
	local p = positions[1]
	local o = raycastAt(cam:ScreenPointToRay(p.X, p.Y))
	if not o then
		touchSel = nil
		setHovered(nil)
		return
	end
	if o.confirmTouch and touchSel ~= o then
		touchSel = o
		setHovered(o)
		return
	end
	touchSel = nil
	activate(o)
end)

-- ===== etiquetas =====
local function placeTag(fr: Frame, cam: Camera, o: Obj, rise: number): boolean
	local p, onScreen = cam:WorldToViewportPoint(o.top)
	if not onScreen then
		return false
	end
	local vp = cam.ViewportSize
	local x = math.clamp(p.X, 120, vp.X - 120)
	local y = math.clamp(p.Y - rise, 60, vp.Y - 20)
	fr.Position = UDim2.fromOffset(x, y)
	return true
end

local function subFor(o: Obj): string
	return subOverride[o.id] or o.sub
end

-- ===== quadro a quadro (só com a câmera na mesa) =====
local function step(dt: number)
	local cam = camera()
	local sc = current
	if not (cam and sc) then
		return
	end
	local now = os.clock()
	local t = now - t0
	-- ponteiro: mouse ou cursor virtual (o toque escolhe por toque)
	local ptr = VirtualCursor.pointer()
	local over: Obj? = nil
	if ptr and lobbyOpen and not VirtualCursor.overGui(ptr) then
		over = raycastAt(cam:ViewportPointToRay(ptr.X, ptr.Y))
	end
	if ptr then
		touchSel = nil
		setHovered(over)
	elseif not touchSel then
		setHovered(nil)
	end
	VirtualCursor.worldHot = over ~= nil
	-- realce: o objeto sob o ponteiro (ou o que a interface 2D aponta)
	local show = hovered
	if not show and externalHover then
		show = objById(sc, externalHover)
	end
	if show then
		hl.Adornee = show.model
		hl.Enabled = true
	else
		hl.Enabled = false
	end
	if show ~= lastShow then
		lastShow = show
		if show then -- o contorno acende e a etiqueta "sai" do objeto (só quando o alvo muda)
			hl.OutlineTransparency, hl.FillTransparency = 1, 1
			TweenService:Create(hl, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				OutlineTransparency = 0.05,
				FillTransparency = 0.82,
			}):Play()
			local pop = hoverTag:FindFirstChild("Pop") :: UIScale?
			if pop then
				pop.Scale = 0.86
				TweenService:Create(pop, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end
		end
	end
	local nx = if nextId and focusId == nil then objById(sc, nextId) else nil
	if nx ~= lastNext then
		lastNext = nx
		local pop = nextTag:FindFirstChild("Pop") :: UIScale?
		if nx and pop then
			pop.Scale = 0.9
			TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end
	if nx and nx ~= show then
		nextHl.Adornee = nx.model
		nextHl.Enabled = true
		nextHl.OutlineTransparency = 0.35 + 0.35 * (0.5 + 0.5 * math.sin(t * 4))
	else
		nextHl.Enabled = false
	end
	-- etiquetas
	if show and placeTag(hoverTag, cam, show, 16) then
		hoverTitle.Text = show.title
		hoverTitle.Font = show.font
		hoverSub.Text = subFor(show)
		hoverTag.Visible = true
	else
		hoverTag.Visible = false
	end
	if nx and nx ~= show and placeTag(nextTag, cam, nx, 12) then
		nextTitle.Text = string.format("► PRÓXIMO: %s", nx.title)
		nextTitle.Font = nx.font
		nextSub.Text = subFor(nx)
		nextTag.Visible = true
	else
		nextTag.Visible = false
	end
	-- câmera: vai suave até o enquadramento; na visão geral, leve paralaxe com o ponteiro
	local s, ndc = targetShot()
	if s then
		local target = shotCF(s, ndc)
		local vp = cam.ViewportSize
		local want = Vector2.zero
		if focusId == nil and ptr then
			want = Vector2.new(ptr.X / math.max(vp.X, 1) - 0.5, ptr.Y / math.max(vp.Y, 1) - 0.5)
		end
		sway = sway:Lerp(want, 1 - math.exp(-dt * 3))
		local breathe = math.sin(t * 0.7) * 0.0015
		target = target * CFrame.Angles(-sway.Y * 0.03 + breathe, -sway.X * 0.04, 0)
		-- a tela de entrada acabou de começar a sair: a mesa "chega" junto com o esmaecer dela
		local covered = entryCovering()
		if wasCovered and not covered then
			arriving = true
		end
		wasCovered = covered
		if arriving then
			-- travelling de chegada: de 22% mais longe e um pouco mais alto até o enquadramento (a
			-- folga do shotCF para tela estreita é de até 40%: o recuo não sai da barraca). Com a
			-- tela de entrada por cima, a câmera espera parada no ponto de partida.
			local dist = (s.focus - target.Position).Magnitude
			camFrom = target * CFrame.new(0, dist * 0.06, dist * 0.22)
			camT, camDur = 0, ARRIVE_TIME
			if not covered then
				arriving = false
			end
		end
		local from = camFrom
		if from and camT < 1 then
			if not arriving then
				camT = math.min(camT + dt / camDur, 1)
			end
			cam.CFrame = from:Lerp(target, smooth(camT))
		else
			cam.CFrame = target
		end
		cam.FieldOfView = FOV
		local d = dof
		if d then
			local dist = (s.focus - cam.CFrame.Position).Magnitude
			d.FocusDistance = math.clamp(dist, 0, 200)
			d.InFocusRadius = math.clamp(dist * 0.55, 1, 50)
		end
	end
	-- lampião tremendo (um valor por luz)
	for _, fl in sc.lights do
		fl.light.Brightness = fl.base * (0.9 + 0.1 * math.noise(t * 2.3, fl.seed))
	end
	if now >= nextStream then
		nextStream = now + 30
		stream()
	end
end

local function setDesk(on: boolean)
	if on == deskOn then
		return
	end
	deskOn = on
	local cam = camera()
	if on then
		applyScene(wantScene)
		t0 = os.clock()
		nextStream = 0
		camFrom, camT = nil, 1
		if cam then
			savedFov = cam.FieldOfView
			cam.CameraType = Enum.CameraType.Scriptable
		end
		local rain = workspace:FindFirstChild("VT65Rain")
		local pe = rain and rain:FindFirstChildOfClass("ParticleEmitter")
		if pe then
			rainWas = pe.Enabled
			pe.Enabled = false -- chuva não entra na barraca (WeatherController só mexe no Rate)
		end
		RunService:BindToRenderStep("VT65LobbyCam", Enum.RenderPriority.Camera.Value + 2, step)
	else
		RunService:UnbindFromRenderStep("VT65LobbyCam")
		local sc = current
		if sc then
			sc.folder.Parent = nil
		end
		current = nil
		hovered, touchSel = nil, nil
		hl.Enabled, nextHl.Enabled = false, false
		hoverTag.Visible, nextTag.Visible = false, false
		VirtualCursor.worldHot = false
		local rain = workspace:FindFirstChild("VT65Rain")
		local pe = rain and rain:FindFirstChildOfClass("ParticleEmitter")
		if pe and rainWas ~= nil then
			pe.Enabled = rainWas
		end
		rainWas = nil
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			if savedFov then
				cam.FieldOfView = savedFov
			end
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				cam.CameraSubject = hum
			end
		end
		savedFov = nil
	end
end

local function evaluate()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local spawning = char ~= nil and hum == nil -- o CharacterAdded chega antes do Humanoid
	local dead = hum ~= nil and hum.Health <= 0
	local noBody = char == nil or (dead and diedAt ~= nil and os.clock() - diedAt >= DEAD_GRACE)
	local dressed = lobbyOpen and not spawning
	setDesk(lobbyOpen and noBody)
	setEffects(dressed)
	backdrop.Enabled = dressed
	tags.Enabled = dressed and deskOn
	-- a janela padrão do chat do Roblox escrevia por cima do cabeçalho (captura, D-64)
	pcall(function()
		local cfg = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		if cfg then
			cfg.Enabled = not dressed
		end
		-- só a janela não basta: a mensagem do sistema e a barra de digitar seguiam por cima do
		-- cabeçalho (Studio, 2026-11-11). Desliga o chat inteiro com o lobby aberto.
		local bar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
		if bar then
			bar.Enabled = not dressed
		end
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, not dressed)
	end)
	-- na mesa: só a vinheta; vivo (troca de papel), escurece o jogo atrás dos papéis
	dim.BackgroundTransparency = if deskOn then 1 else 0.38
	for _, e in edges do
		e.BackgroundTransparency = if deskOn then 0.35 else 0
	end
	local wantFilm = dressed and deskOn
	if wantFilm ~= filmOn then
		filmOn = wantFilm
		Acabamento.ligar(film, wantFilm, if wantFilm then 1.2 else 0)
	end
end

-- ===== API (GameUI e DeployScreen) =====
-- open: a tela do lobby está visível; f: lado do jogador (nil antes de escolher)
function LobbyScene.update(open: boolean, f: string?)
	lobbyOpen = open
	if f ~= faction then
		faction = f
		nextStream = 0
		stream()
	end
	evaluate()
end

-- "choose" (sala de arquivo) | "US" | "VC"
function LobbyScene.setScene(id: string)
	if id == wantScene then
		return
	end
	wantScene = id
	focusId = nil
	if deskOn then
		switchScene(id)
	end
end

-- Objeto em foco (painel aberto) ou nil = visão geral. ndc: onde o objeto deve aparecer na tela
-- (-1..1; x para a direita, y para cima), fora do painel 2D.
function LobbyScene.setFocus(id: string?, ndc: Vector2?)
	if ndc then
		if id then
			focusNdc = ndc
		else
			overviewNdc = ndc
		end
	end
	if id == focusId then
		return
	end
	focusId = id
	local sc = current
	local o = if sc and id then objById(sc, id) else nil
	if openObj and openObj ~= o then
		local fn = openObj.open
		if fn then
			fn(false)
		end
		openObj = nil
	end
	if o and o.open then
		local fn = o.open
		if fn then
			fn(true)
		end
		openObj = o
	end
	if deskOn then
		startMove()
	end
end

-- objeto que pisca como "próximo passo" na visão geral
function LobbyScene.setNext(id: string?)
	nextId = id
end

-- a interface 2D aponta para um objeto (ficha sob o mouse/cursor): realça sem precisar do ponteiro
function LobbyScene.setExternalHover(id: string?)
	externalHover = id
	local sc = current
	if sc then
		for fct, sp in sc.spots do
			sp.Brightness = if (id == "pick_" .. fct) or (hovered and hovered.id == "pick_" .. fct) then 3.2 else 0.6
		end
	end
end

-- linha de situação da etiqueta de uma ação (ex.: "squad" -> "Alfa · 4/6")
function LobbyScene.setSub(id: string, text: string?)
	if text then
		subOverride[id] = text
	else
		subOverride[id] = nil
	end
end

-- textos das peças: "dossier", "radio", "calDay", "calNote"
function LobbyScene.setText(key: string, text: string, color: Color3?)
	liveValue[key] = text
	if color then
		liveColor[key] = color
	end
	local list = live[key]
	if list then
		for _, t in list do
			t.Text = text
			if color then
				t.TextColor3 = color
			end
		end
	end
end

-- arma do soldado da mesa (papel em foco)
function LobbyScene.setLoadout(f: string, weaponId: string?)
	local sc = scenes[f]
	local pv = sc and sc.previews[f]
	if pv then
		SoldierPreview.set(pv, f, weaponId)
	end
end

function LobbyScene.deskVisible(): boolean
	return deskOn
end

function LobbyScene.hoveredId(): string?
	return if hovered then hovered.id else nil
end

-- ordem das ações da cena (LB/RB) e o ponto na tela de cada uma (para levar o cursor)
function LobbyScene.screenPoint(id: string): Vector2?
	local cam = camera()
	local sc = current
	if not (cam and sc and deskOn) then
		return nil
	end
	local o = objById(sc, id)
	if not o then
		return nil
	end
	local p, onScreen = cam:WorldToViewportPoint(o.hit.Position)
	return if onScreen then Vector2.new(p.X, p.Y) else nil
end

-- ===== personagem =====
local function watchCharacter(char: Model)
	diedAt = nil
	-- nasceu: câmera normal e sem efeitos do lobby, já (o GameUI reavalia depois)
	lobbyOpen = false
	evaluate()
	task.spawn(function()
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then
			return
		end
		local cam = camera()
		if cam and not deskOn and cam.CameraSubject ~= hum then
			cam.CameraSubject = hum
		end
		hum.Died:Connect(function()
			diedAt = os.clock()
			task.delay(DEAD_GRACE + 0.05, evaluate)
		end)
	end)
end
player.CharacterAdded:Connect(watchCharacter)
player.CharacterRemoving:Connect(function()
	task.defer(evaluate)
end)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

return LobbyScene
