--!strict
-- HUD de infantaria: as peças novas do §13 do prompt de interface (D-210). Zonas:
--   - inferior central: a VIDA com o valor real (Humanoid; o MedicalService a mantém) e os estados do
--     corpo (Medical_State), logo acima da bússola do HudCampo. O dano recebido deixa um rastro claro
--     que encolhe depois;
--   - centro: a DIREÇÃO DO DANO, arcos vermelhos em volta da mira apontando de onde veio o tiro
--     (Combat_Hit). O objetivo continua em latão na bússola: cor, forma e lugar diferentes;
--   - superior direita: o XP discreto (Bus "hud_ganho", do Progresso) e os ABATES (Combat_Feed), no
--     máximo 4 linhas de 6 s; o seu abate (ou a sua queda) com o filete âmbar;
--   - lateral esquerda: o ESQUADRÃO (Squad_State): o líder com ★, o papel e em campo (●), caído (✚)
--     ou fora (○). A coluna de comandos (PainelComandos) começa embaixo dele.
-- Toque: a vida fica embaixo da bússola (no alto); abates e esquadrão saem (a tela limpa da v39) e o
-- XP volta ao aviso de sempre (Toast). Tudo some com os menus, a carta, caído e morto; a vida também
-- no veículo (o painel do veículo é do VehicleHudView).
-- Leve: tudo é criado uma vez; texto e tamanho mudam por evento; 4 vezes por segundo, só o lugar e a
-- visibilidade; os arcos de dano só andam (por quadro) enquanto estão na tela.
-- Studio: workspace:SetAttribute("VT65DevTela", "hud_infantaria") mostra exemplos por 8 s (dano,
-- abates, XP e estados).
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Estilo = require(ReplicatedFirst:WaitForChild("Estilo"))
local HudInfantaria = require(ReplicatedStorage.Shared.HudInfantaria)
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V = UiKit.V
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

local COR_NIVEL: { [string]: Color3 } = {
	bem = Color3.fromRGB(150, 182, 98),
	ferido = V.AMBAR,
	grave = V.RED_HI,
}
local COR_LADO: { [string]: Color3 } = { US = V.US, VC = V.VC }
local COR_ESTADO: { [string]: Color3 } = {
	campo = Color3.fromRGB(124, 178, 84),
	caido = V.RED_HI,
	fora = V.DIM,
}
local GLIFO_ESTADO: { [string]: string } = { campo = "●", caido = "✚", fora = "○" }

local gui = UiKit.screen("VT65HudInfantaria", 13)
local squadGui = UiKit.screen("VT65Esquadrao", 12) -- o PainelComandos lê o tamanho dele

local function scaled(o: GuiObject): UIScale
	local s = Instance.new("UIScale")
	s.Parent = o
	return s
end

-- ============================================================================================
-- vida e estados (inferior central)
-- ============================================================================================
local VW = px(300, 420)
local VH = px(12, 16)
local vida = Instance.new("Frame")
vida.Name = "Vida"
vida.AnchorPoint = Vector2.new(0.5, 1)
vida.Size = UDim2.fromOffset(VW, px(46, 64))
vida.BackgroundTransparency = 1
vida.Visible = false
vida.Parent = gui
local vidaScale = scaled(vida)
-- estados: uma linha de etiquetas acima da barra
local estRow = Instance.new("Frame")
estRow.Name = "Estados"
estRow.BackgroundTransparency = 1
estRow.Size = UDim2.new(1, 0, 0, px(20, 28))
estRow.Parent = vida
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Padding = UDim.new(0, px(6, 8))
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = estRow
end
local chips: { TextLabel } = {}
for i = 1, 3 do
	local c = UiKit.rotulo(estRow, 13, V.TEXT, UiKit.F.BODY_B)
	c.Name = "Estado"
	c.LayoutOrder = i
	c.AutomaticSize = Enum.AutomaticSize.X
	c.Size = UDim2.fromOffset(0, px(20, 28))
	c.BackgroundTransparency = 0.1
	c.TextXAlignment = Enum.TextXAlignment.Center
	c.Visible = false
	UiKit.corner(c, 3)
	UiKit.pad(c, px(7, 10))
	chips[i] = c
end
-- a barra (o número à direita)
local NUM_W = px(44, 62)
local barBack = Instance.new("Frame")
barBack.Name = "Barra"
barBack.AnchorPoint = Vector2.new(0, 1)
barBack.Position = UDim2.new(0, 0, 1, -px(5, 7))
barBack.Size = UDim2.new(1, -NUM_W, 0, VH)
barBack.BackgroundColor3 = UiKit.CARD_DARK
barBack.BackgroundTransparency = 0.2
barBack.BorderSizePixel = 0
barBack.ClipsDescendants = true
barBack.Parent = vida
UiKit.corner(barBack, 3)
UiKit.edge(barBack, UiKit.KHAKI, 1, 0.65)
local ghost = Instance.new("Frame")
ghost.Name = "Rastro"
ghost.Size = UDim2.fromScale(1, 1)
ghost.BackgroundColor3 = UiKit.CARD
ghost.BackgroundTransparency = 0.25
ghost.BorderSizePixel = 0
ghost.Parent = barBack
local fill = Instance.new("Frame")
fill.Name = "Cheio"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = COR_NIVEL.bem
fill.BorderSizePixel = 0
fill.Parent = barBack
-- marcas de 25% (ler a barra sem contar pixel)
for q = 1, 3 do
	local m = Instance.new("Frame")
	m.Position = UDim2.new(q / 4, 0, 0, 0)
	m.Size = UDim2.new(0, 1, 1, 0)
	m.BackgroundColor3 = UiKit.CARD_DARK
	m.BackgroundTransparency = 0.3
	m.BorderSizePixel = 0
	m.ZIndex = 2
	m.Parent = barBack
end
local num = UiKit.rotulo(vida, 20, UiKit.CARD, UiKit.HEAD_FONT)
num.Name = "Numero"
num.AnchorPoint = Vector2.new(1, 1)
num.Position = UDim2.new(1, 0, 1, 0)
num.Size = UDim2.fromOffset(NUM_W - px(6, 8), px(24, 32))
num.TextXAlignment = Enum.TextXAlignment.Right
num.TextStrokeColor3 = UiKit.NIGHT
num.TextStrokeTransparency = 0.4

local med: any = nil -- o último Medical_State
local lastFrac = 1
local ghostToken = 0
local function paintVida(animar: boolean)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not h then
		return
	end
	local f, texto, nivel = HudInfantaria.vida(h.Health, h.MaxHealth)
	num.Text = texto
	local cor = COR_NIVEL[nivel]
	num.TextColor3 = if nivel == "bem" then UiKit.CARD else cor
	local info = if animar then TweenInfo.new(0.12) else TweenInfo.new(0)
	TweenService:Create(fill, info, { Size = UDim2.fromScale(f, 1), BackgroundColor3 = cor }):Play()
	if f < lastFrac and animar then
		-- dano: o rastro claro fica onde estava e encolhe depois (lê quanto caiu)
		ghostToken += 1
		local my = ghostToken
		task.delay(0.45, function()
			if ghostToken == my then
				TweenService:Create(ghost, TweenInfo.new(0.4), { Size = UDim2.fromScale(f, 1) }):Play()
			end
		end)
	else
		ghost.Size = UDim2.fromScale(f, 1)
	end
	lastFrac = f
end

local function paintEstados()
	local list = HudInfantaria.estados(med)
	for i, c in chips do
		local e = list[i]
		c.Visible = e ~= nil
		if e then
			c.Text = e.texto
			c.BackgroundColor3 = if e.grave then V.RED else UiKit.CARD_DARK
			c.TextColor3 = if e.grave then V.TEXT else V.AMBAR
		end
	end
end

Net.event("Medical_State").OnClientEvent:Connect(function(s: any)
	if type(s) == "table" then
		med = s
		paintEstados()
	end
end)

local healthConn: RBXScriptConnection? = nil
local function watchChar(c: Model)
	local old = healthConn
	if old then
		old:Disconnect()
	end
	med = nil
	paintEstados()
	local h = c:WaitForChild("Humanoid", 10) :: Humanoid?
	if not h then
		return
	end
	lastFrac = 1
	paintVida(false)
	healthConn = h.HealthChanged:Connect(function()
		paintVida(true)
	end)
end
player.CharacterAdded:Connect(watchChar)
if player.Character then
	task.spawn(watchChar, player.Character)
end

-- ============================================================================================
-- direção do dano (centro)
-- ============================================================================================
local RAIO = px(120, 170)
local danoHolder = Instance.new("Frame")
danoHolder.Name = "Dano"
danoHolder.AnchorPoint = Vector2.new(0.5, 0.5)
danoHolder.Position = UDim2.fromScale(0.5, 0.5)
danoHolder.Size = UDim2.fromOffset(0, 0)
danoHolder.BackgroundTransparency = 1
danoHolder.Parent = gui
local danoScale = scaled(danoHolder)
type Arco = { segs: { Frame }, origem: Vector3?, ate: number }
local arcos: { Arco } = {}
local SEG_DEG = { -11, 0, 11 } -- três pedaços formam o arco
for i = 1, HudInfantaria.DANO_MAX do
	local segs: { Frame } = {}
	for j = 1, #SEG_DEG do
		local s = Instance.new("Frame")
		s.Name = "Arco"
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Size = UDim2.fromOffset(px(26, 36), if j == 2 then px(8, 11) else px(6, 8))
		s.BackgroundColor3 = V.RED_HI
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.Parent = danoHolder
		UiKit.corner(s, 3)
		segs[j] = s
	end
	arcos[i] = { segs = segs, origem = nil, ate = 0 }
end

local function placeArco(a: Arco, ang: number)
	for j, s in a.segs do
		local t = math.rad(ang + SEG_DEG[j])
		s.Position = UDim2.fromOffset(math.sin(t) * RAIO, -math.cos(t) * RAIO)
		s.Rotation = ang + SEG_DEG[j]
	end
end

local function anguloDe(origem: Vector3): number
	local cam = workspace.CurrentCamera
	if not cam then
		return 0
	end
	local look = cam.CFrame.LookVector
	local d = origem - cam.CFrame.Position
	return HudInfantaria.anguloDano(look.X, look.Z, d.X, d.Z)
end

local function hit(origem: Vector3)
	local now = os.clock()
	local ang = anguloDe(origem)
	-- o mesmo lado de um arco aceso: renova o arco (não empilha)
	local pick: Arco? = nil
	for _, a in arcos do
		local o = a.origem
		if o and a.ate > now and math.abs(((anguloDe(o) - ang + 180) % 360) - 180) < 20 then
			pick = a
			break
		end
	end
	if not pick then
		local older: Arco = arcos[1]
		for _, a in arcos do
			if a.ate < older.ate then
				older = a
			end
		end
		pick = older
	end
	local a = pick :: Arco
	a.origem = origem
	a.ate = now + HudInfantaria.DANO_S
	placeArco(a, ang)
	for _, s in a.segs do
		s.BackgroundTransparency = 0.05
		TweenService:Create(s, TweenInfo.new(HudInfantaria.DANO_S, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
	end
end

Net.event("Combat_Hit").OnClientEvent:Connect(function(o: any)
	if type(o) == "table" and type(o.x) == "number" and type(o.y) == "number" and type(o.z) == "number" then
		hit(Vector3.new(o.x, o.y, o.z))
	end
end)

-- os arcos acesos acompanham a câmera (girar mostra o lado certo)
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for _, a in arcos do
		local o = a.origem
		if o and a.ate > now then
			placeArco(a, anguloDe(o))
		elseif o then
			a.origem = nil
		end
	end
end)

-- ============================================================================================
-- XP e abates (superior direita)
-- ============================================================================================
local FW = px(340, 480)
local feed = Instance.new("Frame")
feed.Name = "Abates"
feed.AnchorPoint = Vector2.new(1, 0)
feed.Size = UDim2.fromOffset(FW, 0)
feed.AutomaticSize = Enum.AutomaticSize.Y
feed.BackgroundTransparency = 1
feed.Visible = false
feed.Parent = gui
local feedScale = scaled(feed)
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	l.Padding = UDim.new(0, px(3, 4))
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = feed
end
local function linha(order: number, size: number): TextLabel
	local t = UiKit.rotulo(feed, size, V.TEXT, UiKit.HEAD_FONT)
	t.LayoutOrder = order
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, px(24, 32))
	t.BackgroundColor3 = UiKit.CARD_DARK
	t.BackgroundTransparency = 0.25
	t.TextXAlignment = Enum.TextXAlignment.Right
	t.RichText = true
	t.Visible = false
	UiKit.corner(t, 3)
	UiKit.pad(t, px(8, 12))
	return t
end
local xpLine = linha(0, 16)
xpLine.Name = "XP"
xpLine.TextColor3 = UiKit.BRASS_LIGHT
xpLine.RichText = false
local killLines: { TextLabel } = {}
local killEdges: { UIStroke } = {}
for i = 1, HudInfantaria.FEED_MAX do
	local t = linha(i, 15)
	t.Name = "Abate"
	killLines[i] = t
	killEdges[i] = UiKit.edge(t, V.AMBAR, 1.5, 1)
end

local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end
local function corDe(lado: string?): string
	return (COR_LADO[lado or ""] or V.TEXT):ToHex()
end

type Item = { a: HudInfantaria.Abate, t: number }
local abates: { Item } = {}
local function paintAbates()
	local now = os.clock()
	for i = #abates, 1, -1 do
		if now - abates[i].t > HudInfantaria.FEED_S then
			table.remove(abates, i)
		end
	end
	for i, t in killLines do
		local it = abates[i]
		t.Visible = it ~= nil
		if it then
			local a = it.a
			t.Text = string.format(
				'<font color="#%s">%s</font>   <font color="#%s">[%s]</font>   <font color="#%s">%s</font>',
				corDe(a.ladoQuem),
				esc(a.quem),
				UiKit.BRASS_LIGHT:ToHex(),
				esc(a.arma),
				corDe(a.ladoCaiu),
				esc(a.caiu)
			)
			killEdges[i].Transparency = if a.meu then 0 else 1
		end
	end
end

local function armaNome(id: string?, lado: string?): string
	local ok, n = pcall(Weapons.shortName, id, lado)
	return if ok and type(n) == "string" and n ~= "" then n else "—"
end

local function addAbate(ev: any)
	local a = HudInfantaria.abate(ev, player.UserId, armaNome)
	if a then
		HudInfantaria.empilha(abates, { a = a, t = os.clock() }, HudInfantaria.FEED_MAX)
		paintAbates()
	end
end
Net.event("Combat_Feed").OnClientEvent:Connect(addAbate)

-- XP: o mesmo rótulo soma enquanto a linha está aberta
local xp = { label = "", xp = 0, cr = 0, cur = "", ate = 0, token = 0 }
local function paintXp()
	local parts = { string.format("+%d XP", xp.xp) }
	if xp.cr > 0 then
		table.insert(parts, string.format("+%d %s", xp.cr, xp.cur))
	end
	if xp.label ~= "" then
		table.insert(parts, xp.label)
	end
	xpLine.Text = table.concat(parts, " · ")
	xpLine.Visible = true
	local s = xpLine:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = xpLine
	s.Scale = if Estilo.reduzMovimento() then 1 else 1.12
	TweenService:Create(s, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end
Bus.on("hud_ganho", function(label: string, gx: number, gcr: number, cur: string)
	if ToqueUi.active() then
		Toast.reward(label, gx, gcr, cur) -- toque: a tela limpa (o aviso de sempre)
		return
	end
	local now = os.clock()
	if xp.ate > now and xp.label == label and xp.cur == cur then
		xp.xp += gx
		xp.cr += gcr
	else
		xp.label, xp.xp, xp.cr, xp.cur = label, gx, gcr, cur
	end
	xp.ate = now + HudInfantaria.XP_S
	xp.token += 1
	local my = xp.token
	paintXp()
	task.delay(HudInfantaria.XP_S, function()
		if xp.token == my then
			xpLine.Visible = false
		end
	end)
end)

-- ============================================================================================
-- esquadrão (lateral esquerda)
-- ============================================================================================
local SW = px(236, 330)
local RH = px(22, 30)
local squad = Instance.new("Frame")
squad.Name = "Esquadrao"
squad.Position = UDim2.fromOffset(px(16, 24), px(250, 330)) -- abaixo da reserva do alto (PainelComandos)
squad.Size = UDim2.fromOffset(SW, 0)
squad.AutomaticSize = Enum.AutomaticSize.Y
squad.BackgroundColor3 = UiKit.CARD_DARK
squad.BackgroundTransparency = 0.3
squad.BorderSizePixel = 0
squad.Visible = false
squad.Parent = squadGui
UiKit.corner(squad, 4)
UiKit.pad(squad, px(10, 14), px(10, 14), px(6, 8), px(6, 8))
local squadScale = scaled(squad)
do
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, px(2, 3))
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = squad
end
local squadHead = UiKit.rotulo(squad, 13, UiKit.KHAKI, UiKit.HEAD_FONT)
squadHead.Name = "Titulo"
squadHead.LayoutOrder = 0
squadHead.Size = UDim2.new(1, 0, 0, px(18, 24))
squadHead.TextXAlignment = Enum.TextXAlignment.Left
type Row = { f: Frame, glyph: TextLabel, name: TextLabel, role: TextLabel }
local rows: { Row } = {}
for i = 1, HudInfantaria.SQUAD_MAX do
	local f = Instance.new("Frame")
	f.Name = "Membro"
	f.LayoutOrder = i
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, RH)
	f.Visible = false
	f.Parent = squad
	local g = UiKit.rotulo(f, 14, V.TEXT, UiKit.F.BODY_B)
	g.Name = "Estado"
	g.Size = UDim2.fromOffset(px(16, 22), RH)
	g.TextXAlignment = Enum.TextXAlignment.Center
	local n = UiKit.rotulo(f, 15, V.TEXT, UiKit.F.BODY_B)
	n.Name = "Nome"
	n.Position = UDim2.fromOffset(px(20, 28), 0)
	n.Size = UDim2.new(0.62, -px(20, 28), 1, 0)
	n.TextXAlignment = Enum.TextXAlignment.Left
	n.TextTruncate = Enum.TextTruncate.AtEnd
	local r = UiKit.rotulo(f, 13, V.DIM, UiKit.HEAD_REG)
	r.Name = "Papel"
	r.AnchorPoint = Vector2.new(1, 0)
	r.Position = UDim2.fromScale(1, 0)
	r.Size = UDim2.new(0.38, 0, 1, 0)
	r.TextXAlignment = Enum.TextXAlignment.Right
	r.TextTruncate = Enum.TextTruncate.AtEnd
	rows[i] = { f = f, glyph = g, name = n, role = r }
end

local squadState: any = nil
local squadCount = 0
local function memberInfo(uid: number): (string?, string)
	local p = Players:GetPlayerByUserId(uid)
	if not p then
		return nil, "fora"
	end
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if c and h and h.Health > 0 then
		if c:GetAttribute("Downed") == true or p:GetAttribute("Downed") == true then
			return p.DisplayName, "caido"
		end
		return p.DisplayName, "campo"
	end
	return p.DisplayName, "fora"
end

local function paintSquad()
	local sid = player:GetAttribute("SquadId")
	local list = HudInfantaria.esquadrao(squadState, sid, player.UserId, memberInfo)
	local nome = ""
	if type(squadState) == "table" and type(squadState.squads) == "table" then
		for _, s in squadState.squads do
			if type(s) == "table" and s.id == sid then
				nome = tostring(s.name or "")
			end
		end
	end
	squadHead.Text = UiKit.upper(if nome ~= "" then string.format("Squad %s", nome) else "Squad")
	for i, r in rows do
		local l = list[i]
		r.f.Visible = l ~= nil
		if l then
			r.glyph.Text = GLIFO_ESTADO[l.estado] or "○"
			r.glyph.TextColor3 = COR_ESTADO[l.estado] or V.DIM
			r.name.Text = if l.lider then string.format("★ %s", l.nome) else l.nome
			r.name.TextColor3 = if l.estado == "fora" then V.DIM else V.TEXT
			local def = if l.papel then Roles.roles[l.papel] else nil
			r.role.Text = if def then tostring(def.name) else ""
		end
	end
	if #list ~= squadCount then
		squadCount = #list
		Bus.fire("esquadrao_mudou")
	end
end
Net.event("Squad_State").OnClientEvent:Connect(function(st: any)
	squadState = st
	paintSquad()
end)

-- ============================================================================================
-- visibilidade e lugar (4 vezes por segundo)
-- ============================================================================================
local devUntil = 0
local function inField(): boolean
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil
		and h.Health > 0
		and Input.state.alive
		and not Input.state.downed
		and not Input.state.map
		and Input.state.menus == 0
		and player:GetAttribute("Role") ~= nil
end

local function visivel(o: GuiObject?): GuiObject?
	if o and o.Visible then
		local g = o:FindFirstAncestorOfClass("ScreenGui")
		if g and g.Enabled then
			return o
		end
	end
	return nil
end

local lastSquadShown = false
local lastCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastCheck < 0.25 then
		return
	end
	lastCheck = now
	local size = gui.AbsoluteSize
	if size.X < 10 then
		return
	end
	local k = if TV then 1 else math.clamp(size.X / 1280, 0.72, 1)
	vidaScale.Scale = k
	danoScale.Scale = k
	feedScale.Scale = k
	squadScale.Scale = k
	local dev = now < devUntil
	local campo = inField() or dev
	local touch = ToqueUi.active()
	-- vida: acima da bússola (PC) ou embaixo dela (toque); sem a bússola, no pé do meio, à esquerda
	-- do cartão da arma se a janela for estreita
	vida.Visible = campo and Input.state.vehicle == nil
	if vida.Visible then
		local hc = player.PlayerGui:FindFirstChild("VT65HudCampo")
		local hud = hc and hc:FindFirstChild("HUD")
		local bus = visivel(hud and hud:FindFirstChild("Bussola") :: GuiObject?)
		local card = visivel(hud and hud:FindFirstChild("Arma") :: GuiObject?)
		local w = VW * k
		-- as telas contam a faixa do Roblox de jeitos diferentes: tudo em coordenadas desta tela
		local o = gui.AbsolutePosition
		if bus then
			local cx = bus.AbsolutePosition.X + bus.AbsoluteSize.X / 2 - o.X
			if bus.AnchorPoint.Y < 0.5 then
				vida.AnchorPoint = Vector2.new(0.5, 0)
				vida.Position = UDim2.fromOffset(cx, bus.AbsolutePosition.Y + bus.AbsoluteSize.Y + 4 - o.Y)
			else
				vida.AnchorPoint = Vector2.new(0.5, 1)
				vida.Position = UDim2.fromOffset(cx, bus.AbsolutePosition.Y - 2 - o.Y)
			end
		else
			local cx = size.X / 2
			if card and not touch then
				cx = math.min(cx, card.AbsolutePosition.X - o.X - 12 - w / 2)
			end
			vida.AnchorPoint = Vector2.new(0.5, 1)
			vida.Position = UDim2.new(0, math.max(cx, w / 2 + 8), 1, -px(16, 26))
		end
	end
	-- abates e XP: no alto à direita, abaixo da faixa da frente quando ela chega até ali
	feed.Visible = (campo or dev) and not touch
	if feed.Visible then
		local fg = player.PlayerGui:FindFirstChild("VT65Frente")
		local strip = visivel(fg and fg:FindFirstChild("Faixa") :: GuiObject?)
		local top = px(12, 18)
		local o = gui.AbsolutePosition
		if strip and strip.AbsolutePosition.X - o.X + strip.AbsoluteSize.X > size.X - FW * k - 24 then
			top = math.max(top, strip.AbsolutePosition.Y - o.Y + strip.AbsoluteSize.Y + 8)
		end
		feed.Position = UDim2.new(1, -px(16, 24), 0, top)
		paintAbates()
	end
	-- esquadrão (o exemplo do Studio fica até o fim do gancho)
	if campo and not touch and not dev then
		paintSquad()
	end
	local showSquad = campo and not touch and squadCount > 0
	squad.Visible = showSquad
	if showSquad ~= lastSquadShown then
		lastSquadShown = showSquad
		Bus.fire("esquadrao_mudou")
	end
end)

-- ============================================================================================
-- Studio: exemplos na tela por 8 s
-- ============================================================================================
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "hud_infantaria" then
			return
		end
		devUntil = os.clock() + 8
		local cam = workspace.CurrentCamera
		if cam then
			local cf = cam.CFrame
			hit(cf.Position + cf.RightVector * 60)
			hit(cf.Position - cf.LookVector * 80 - cf.RightVector * 20)
		end
		med = { bleed = 0.4, arterial = false, leg = true, arm = false }
		paintEstados()
		addAbate({ k = "SOLDADO TESTE", ku = player.UserId, kf = "US", v = "Bot VC 12", vu = 0, vf = "VC", w = "m14" })
		addAbate({ k = "Bot VC 03", ku = 0, kf = "VC", v = "Fuzileiro 07", vu = 0, vf = "US", w = "type56" })
		Bus.fire("hud_ganho", "Abate", 100, 10, "CI")
		-- o esquadrão de exemplo (sozinho no servidor não há companheiro): líder, caído e fora
		squadHead.Text = UiKit.upper("Squad Alfa")
		local amostra = {
			{ nome = "LIDER TESTE", papel = "squad_leader", estado = "campo", lider = true },
			{ nome = "MEDICO TESTE", papel = "medic", estado = "caido", lider = false },
			{ nome = "APOIO TESTE", papel = "support", estado = "fora", lider = false },
		}
		for i, r in rows do
			local l = amostra[i]
			r.f.Visible = l ~= nil
			if l then
				r.glyph.Text = GLIFO_ESTADO[l.estado]
				r.glyph.TextColor3 = COR_ESTADO[l.estado]
				r.name.Text = if l.lider then string.format("★ %s", l.nome) else l.nome
				r.name.TextColor3 = if l.estado == "fora" then V.DIM else V.TEXT
				local def = Roles.roles[l.papel]
				r.role.Text = if def then tostring(def.name) else ""
			end
		end
		squadCount = #amostra
		Bus.fire("esquadrao_mudou")
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
	end)
end
