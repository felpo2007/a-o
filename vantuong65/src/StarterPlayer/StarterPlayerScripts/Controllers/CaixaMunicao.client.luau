--!strict
-- Caixa de munição do Suporte no cliente (D-108; pedido do dono: "faça a caixa de munições bonita e
-- que seja possível ver onde ele coloca no chão"). Regras no Shared/CaixaMunicao; o servidor
-- (Modules/CaixaMunicaoService) confere tudo de novo.
--   - Ferramenta do papel (vaga 0, roda de equipamento) do suporte: abre a prévia. A caixa aparece
--     translúcida onde a mira aponta, no chão perto (até CaixaMunicao.POR_MAX_M): VERDE pode,
--     VERMELHA não (longe, água, rampa, sem espaço, espera). O gatilho põe (WeaponController manda o
--     Bus "caixa_por" enquanto o atributo local "PondoCaixa" está ligado); mirar, a mesma vaga de
--     novo, morrer ou entrar num veículo cancelam. No toque: botões PÔR CAIXA e ✕.
--   - Caixas do próprio lado (Workspace.CaixasMunicao): ícone discreto por cima (vê-se de longe, some
--     de perto) com o estoque; a carta marca o lugar (CartaView.drawCaixas).
--   - Avisos do servidor (Caixa_Aviso): recusa, caixa posta e o que pegou, no Toast.
-- Studio: workspace:SetAttribute("VT65DevTela", "caixa") abre a prévia (com ou sem o papel).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CaixaMunicao = require(ReplicatedStorage.Shared.CaixaMunicao)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local M = 0.28
local V = UiKit.V
local OK_COLOR = Color3.fromRGB(124, 178, 84)
local BAD_COLOR = Color3.fromRGB(212, 70, 52)
local ICON_MAX_M = 250 -- o ícone do time aparece até 250 m
local ICON_MIN_M = 4 -- e some de perto (a caixa já se vê)

-- ===== prévia =====
local S = {
	on = false,
	dev = false,
	ok = false,
	why = "",
	pos = nil :: Vector3?,
	yaw = 0,
	lastPlaced = -math.huge,
	ghost = nil :: Model?,
	parts = {} :: { BasePart }, -- peças pintadas de verde ou vermelho
}

local function faction(): string
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else "US"
end

-- a forma da caixa do lado (a arte que o servidor copiou); sem ela, uma caixa lisa do tamanho certo
local function makeGhost(): Model
	local art = ReplicatedStorage:FindFirstChild("VT65CaixaArte")
	local src = art and art:FindFirstChild(faction())
	local m: Model
	if src and src:IsA("Model") then
		m = src:Clone()
	else
		m = Instance.new("Model")
		local w, h, d = CaixaMunicao.size(faction())
		local p = Instance.new("Part")
		p.Size = Vector3.new(w, h, d) / M
		p.CFrame = CFrame.new(0, h / 2 / M, 0)
		p.Parent = m
		m.PrimaryPart = p
		m.WorldPivot = CFrame.identity
	end
	m.Name = "VT65PreviaCaixa"
	-- a mesma malha, pintada (sem a textura) e meio transparente; sem a colisão invisível do Blender
	S.parts = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 8) == "Colisao_" then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
			if d.Transparency < 1 then
				d.Transparency = 0.5
				d.Material = Enum.Material.SmoothPlastic
				table.insert(S.parts, d)
			end
		elseif d:IsA("SurfaceGui") or d:IsA("Decal") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	-- marca no chão do tamanho da pegada da caixa (metricas.json do Blender)
	local pg = CaixaMunicao.PEGADA_STUDS[faction()] or CaixaMunicao.PEGADA_STUDS.US
	local mark = Instance.new("Part")
	mark.Name = "Pegada"
	mark.Anchored = true
	mark.CanCollide, mark.CanQuery, mark.CanTouch, mark.CastShadow = false, false, false, false
	mark.Material = Enum.Material.Neon
	mark.Transparency = 0.55
	mark.Size = Vector3.new(pg[1] + 0.3, 0.05, pg[2] + 0.3)
	mark.CFrame = m:GetPivot() * CFrame.new(0, 0.03, 0) -- o pivô é o meio da base
	mark.Parent = m
	table.insert(S.parts, mark)
	return m
end

-- ===== barra do toque e dica =====
local gui = UiKit.screen("VT65Caixa", 16)
gui.Enabled = false
local h = ToqueUi.minPx()
local bar = UiKit.panel(gui, V.PANEL, 0.08)
bar.Name = "Caixa"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -12)
bar.AutomaticSize = Enum.AutomaticSize.XY
bar.Size = UDim2.new()
bar.Active = true
UiKit.pad(bar, 10, 10, 8, 10)
UiKit.list(bar, false, 6, Enum.HorizontalAlignment.Center)
local title = UiKit.title(bar, "CAIXA DE MUNIÇÃO", math.max(16, math.floor(h * 0.4)), V.TEXT)
title.AutomaticSize = Enum.AutomaticSize.XY
title.Size = UDim2.new()
title.LayoutOrder = 1
local sub = UiKit.text2(bar, "", math.max(12, math.floor(h * 0.28)), V.DIM, UiKit.F.BODY)
sub.AutomaticSize = Enum.AutomaticSize.XY
sub.Size = UDim2.new()
sub.LayoutOrder = 2
local row = Instance.new("Frame")
row.BackgroundTransparency = 1
row.AutomaticSize = Enum.AutomaticSize.XY
row.Size = UDim2.new()
row.LayoutOrder = 3
row.Parent = bar
UiKit.list(row, true, 8)
local bOk = ToqueUi.bigButton(row, "PÔR CAIXA", "primary", math.floor(h * 3.2))
bOk.LayoutOrder = 1
local bCancel = ToqueUi.bigButton(row, "✕", "secondary", h)
bCancel.LayoutOrder = 2

local function stop()
	S.on, S.dev = false, false
	S.pos = nil
	player:SetAttribute("PondoCaixa", nil)
	gui.Enabled = false
	local g = S.ghost
	if g then
		g:Destroy()
		S.ghost = nil
	end
	S.parts = {}
end

local function start(dev: boolean?)
	if S.on then
		stop()
		return
	end
	if player:GetAttribute("Role") ~= "support" and not dev then
		return
	end
	S.on, S.dev = true, dev == true
	player:SetAttribute("PondoCaixa", true)
	local g = makeGhost()
	g.Parent = workspace.CurrentCamera
	S.ghost = g
	bar.Visible = true
	gui.Enabled = true
	bOk.Visible = ToqueUi.active()
	bCancel.Visible = ToqueUi.active()
end

local function place()
	local pos = S.pos
	if not (S.on and pos) then
		return
	end
	if not S.ok then
		Bus.fire("toast", S.why)
		return
	end
	Net.event("Caixa_Por"):FireServer({ x = pos.X, y = pos.Y, z = pos.Z, yaw = S.yaw })
	stop()
end

Bus.on("caixa_municao", function()
	start(false)
end)
Bus.on("caixa_por", place)
bOk.Activated:Connect(place)
bCancel.Activated:Connect(stop)
Input.on("aim", "press", function()
	if S.on then
		stop()
	end
end)
player.CharacterAdded:Connect(stop)

Net.event("Caixa_Aviso").OnClientEvent:Connect(function(m: any)
	if type(m) ~= "table" or type(m.msg) ~= "string" then
		return
	end
	if m.w == "posta" then
		S.lastPlaced = os.clock()
	end
	Bus.fire("toast", m.msg)
end)

-- ===== quadro a quadro: onde a caixa vai =====
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.RespectCanCollide = true

local function soldiers(): { Instance }
	local list: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		table.insert(list, folder)
	end
	local boxes = workspace:FindFirstChild("CaixasMunicao")
	if boxes then
		table.insert(list, boxes)
	end
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(list, cam)
	end
	return list
end

local lastSub = ""
RunService.RenderStepped:Connect(function()
	if not S.on then
		return
	end
	local st = Input.state
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if
		not (root and root:IsA("BasePart") and cam)
		or not st.alive
		or st.downed
		or st.vehicle ~= nil
		or st.menus > 0
	then
		stop()
		return
	end
	if player:GetAttribute("Role") ~= "support" and not S.dev then
		stop()
		return
	end
	local skip = soldiers()
	rayParams.FilterDescendantsInstances = skip
	local reach = CaixaMunicao.POR_MAX_M / M
	-- a mira no chão perto; senão, o chão à frente no rumo da câmera, até o alcance
	local look = cam.CFrame.LookVector
	local hit = workspace:Raycast(cam.CFrame.Position, look * (reach + 8 / M), rayParams)
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 1e-3 then
		flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	flatLook = flatLook.Unit
	if
		not hit
		or Vector3.new(hit.Position.X - root.Position.X, 0, hit.Position.Z - root.Position.Z).Magnitude > reach
	then
		local at = root.Position + flatLook * (reach * 0.6)
		hit = workspace:Raycast(at + Vector3.new(0, 1.5 / M, 0), Vector3.new(0, -4 / M, 0), rayParams)
	end
	S.yaw = math.atan2(-flatLook.X, -flatLook.Z) + math.pi -- a faixa pintada para quem põe
	local ghost = S.ghost
	if not hit then
		S.pos, S.ok, S.why = nil, false, "sem chão aqui"
		if ghost then
			ghost:PivotTo(CFrame.new(0, -1e4, 0))
		end
	else
		local pos = hit.Position
		S.pos = pos
		local n = hit.Normal
		local w, hh, d = CaixaMunicao.size(faction())
		overlap.FilterDescendantsInstances = { workspace.Terrain, table.unpack(skip) }
		local cf = CFrame.new(pos + Vector3.new(0, (hh / 2 + 0.06) / M, 0)) * CFrame.Angles(0, S.yaw, 0)
		local blocked = #workspace:GetPartBoundsInBox(cf, Vector3.new(w, hh, d) * 0.9 / M, overlap) > 0
		local ok, why = CaixaMunicao.canPlace({
			role = if S.dev then "support" else player:GetAttribute("Role") :: string?,
			alive = true,
			seated = false,
			distM = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z).Magnitude * M,
			dyM = (pos.Y - root.Position.Y) * M + 1,
			slopeDeg = CaixaMunicao.slope(n.X, n.Y, n.Z),
			water = hit.Material == Enum.Material.Water,
			blocked = blocked,
			ground = true,
			sinceLastS = if S.dev then math.huge else os.clock() - S.lastPlaced,
		})
		S.ok, S.why = ok, why or ""
		if ghost then
			ghost:PivotTo(CFrame.new(pos) * CFrame.Angles(0, S.yaw, 0))
		end
	end
	local color = if S.ok then OK_COLOR else BAD_COLOR
	for _, p in S.parts do
		p.Color = color
	end
	bOk.BackgroundColor3 = if S.ok then V.OLIVE else V.PANEL_2
	bOk.TextTransparency = if S.ok then 0 else 0.35
	local touch = ToqueUi.active()
	bOk.Visible, bCancel.Visible = touch, touch
	local text = if S.ok then (if touch then "Toque em PÔR CAIXA" else "Gatilho: pôr · Mirar: cancelar") else S.why
	if text ~= lastSub then
		lastSub = text
		sub.Text = text
	end
end)

-- ===== ícone do time sobre as caixas do próprio lado =====
local icons: { [Model]: BillboardGui } = {}

local function iconFor(m: Model): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "VT65IconeCaixa"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(46, 30)
	bb.MaxDistance = ICON_MAX_M / M
	-- no ponto do ícone do modelo do Blender (metricas.json: icone_studs acima do meio da base)
	local base = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	if base then
		local ic = CaixaMunicao.ICONE_STUDS[tostring(m:GetAttribute("Faction"))] or CaixaMunicao.ICONE_STUDS.US
		local at = Instance.new("Attachment")
		at.Name = "VT65IconeCaixa"
		at.WorldCFrame = m:GetPivot() * CFrame.new(ic[1], ic[2], ic[3])
		at.Parent = base
		bb.Adornee = at
	else
		bb.Adornee = m
		bb.StudsOffsetWorldSpace = Vector3.new(0, 1.1 / M, 0)
	end
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glifo"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.new(1, 0, 0, 18)
	glyph.Font = Enum.Font.GothamBold
	glyph.TextSize = 16
	glyph.Text = "▣"
	glyph.TextColor3 = V.BRASS
	glyph.TextStrokeColor3 = V.BG
	glyph.TextStrokeTransparency = 0.2
	glyph.Parent = bb
	local stock = Instance.new("TextLabel")
	stock.Name = "Estoque"
	stock.BackgroundTransparency = 1
	stock.Position = UDim2.fromOffset(0, 17)
	stock.Size = UDim2.new(1, 0, 0, 12)
	stock.Font = Enum.Font.GothamBold
	stock.TextSize = 11
	stock.TextColor3 = V.TEXT
	stock.TextStrokeColor3 = V.BG
	stock.TextStrokeTransparency = 0.3
	stock.Parent = bb
	bb.Parent = player:WaitForChild("PlayerGui")
	return bb
end

local iconAt = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - iconAt < 0.25 then
		return
	end
	iconAt = now
	local folder = workspace:FindFirstChild("CaixasMunicao")
	local mine = player:GetAttribute("Faction")
	local seen: { [Model]: boolean } = {}
	local cam = workspace.CurrentCamera
	if folder and type(mine) == "string" then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Faction") == mine then
				seen[m] = true
				local bb = icons[m] or iconFor(m)
				icons[m] = bb
				local stock = bb:FindFirstChild("Estoque") :: TextLabel?
				if stock then
					stock.Text = string.format(
						"%d/%d",
						tonumber(m:GetAttribute("Stock")) or 0,
						tonumber(m:GetAttribute("StockMax")) or 0
					)
				end
				local d = if cam then (cam.CFrame.Position - m:GetPivot().Position).Magnitude * M else 99
				bb.Enabled = d > ICON_MIN_M
			end
		end
	end
	for m, bb in icons do
		if not seen[m] then
			bb:Destroy()
			icons[m] = nil
		end
	end
end)

-- Studio: a prévia sem o papel
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "caixa" then
			start(true)
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
