--!strict
-- Caixa de munição do Suporte (D-108). Regras puras no Shared/CaixaMunicao; aqui o servidor:
--   - "Caixa_Por" {x, y, z, yaw}: confere papel, vida, chão (raio para baixo), água, rampa, espaço
--     livre e distância, e põe a caixa (a anterior do mesmo suporte sai);
--   - 4 vezes por segundo: quem é do lado e está ao alcance pega (CombatService.resupply, +1 granada,
--     +1 foguete do antitanque), com intervalo por pessoa e estoque; quem pôs ganha "resupply";
--   - bots: o BotService liga botNeeds/botRefill (bot sem munição vai à caixa) e chama place() para o
--     bot suporte;
--   - a arte: AssetIds.Models.caixa_municao_us / _vc (frente de Blender); sem ID, o caixote de munição
--     do jogo (ammo_crate); sem ele, uma caixa em peças. Uma cópia vai para
--     ReplicatedStorage.VT65CaixaArte (a prévia do cliente usa a mesma forma).
-- Atributos do modelo (Workspace.CaixasMunicao): Faction, Owner, OwnerName, Stock, StockMax, Until
-- (hora do servidor em que some). O cliente (Controllers/CaixaMunicao.client) desenha o ícone do time
-- e a carta (CartaView) marca o lugar.
-- Studio: workspace:SetAttribute("VT65DevCaixa", true) põe uma caixa à frente de cada jogador em campo,
-- sem conferir papel nem espera (o resto vale igual).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local CaixaMunicao = require(ReplicatedStorage.Shared.CaixaMunicao)
local Net = require(ReplicatedStorage.Shared.Net)
local AssetLoader = require(script.Parent.AssetLoader)
local CombatService = require(script.Parent.CombatService)
local Combatants = require(script.Parent.Combatants)
local ProgressionService = require(script.Parent.ProgressionService)

local CaixaMunicaoService = {}
local M = 0.28

local boxes: { CaixaMunicao.Box } = {}
local models: { [string]: Model } = {}
local lastPlaced: { [string]: number } = {} -- dono -> os.clock da última caixa
local seq = 0
local folder: Folder? = nil
local templates: { [string]: Model } = {}

-- ligados pelo BotService: o bot precisa de munição? / reabastece o bot (devolve se mudou algo)
CaixaMunicaoService.botNeeds = nil :: ((model: Model) -> boolean)?
CaixaMunicaoService.botRefill = nil :: ((model: Model) -> boolean)?

-- ===== arte =====
local ART_KEY = { US = "caixa_municao_us", VC = "caixa_municao_vc" } :: { [string]: string }

local function published(key: string): boolean
	local id = AssetIds.Models[key]
	return type(id) == "number" and id ~= 0
end

local function part(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size / M
	p.CFrame = CFrame.new(cf.Position / M) * cf.Rotation
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	p.Parent = m
	return p
end

-- Substituto em peças (sem modelo publicado): caixote de madeira com ripas, alças de corda, faixa
-- pintada e uma lata de munição em cima (EUA: verde-oliva, faixa amarela "CTG 7.62MM"; VC: madeira
-- crua, faixa vermelha com 弹药, "munição" em chinês). Medidas em m (CaixaMunicao.TAMANHO_M).
local function partsBox(faction: string): Model
	local w, h, d = CaixaMunicao.size(faction)
	local us = faction == "US"
	local wood = if us then Color3.fromRGB(78, 86, 56) else Color3.fromRGB(128, 98, 62)
	local dark = if us then Color3.fromRGB(56, 62, 40) else Color3.fromRGB(92, 68, 42)
	local band = if us then Color3.fromRGB(196, 168, 70) else Color3.fromRGB(150, 40, 32)
	local m = Instance.new("Model")
	m.Name = "CaixaMunicao"
	local body = part(m, "Corpo", Vector3.new(w, h, d), CFrame.new(0, h / 2, 0), wood, Enum.Material.WoodPlanks)
	-- tampa com duas ripas e as cintas das pontas
	for _, x in { -w * 0.3, w * 0.3 } do
		part(m, "Ripa", Vector3.new(0.05, 0.02, d + 0.01), CFrame.new(x, h + 0.01, 0), dark, Enum.Material.Wood)
	end
	for _, x in { -w / 2, w / 2 } do
		part(m, "Cinta", Vector3.new(0.02, h + 0.01, d + 0.02), CFrame.new(x, h / 2, 0), dark, Enum.Material.Wood)
	end
	-- alças de corda nos lados
	for _, x in { -w / 2 - 0.012, w / 2 + 0.012 } do
		part(
			m,
			"Alca",
			Vector3.new(0.012, 0.03, 0.14),
			CFrame.new(x, h * 0.62, 0),
			Color3.fromRGB(150, 132, 96),
			Enum.Material.Fabric
		)
	end
	-- faixa pintada na frente, com o letreiro
	local front = part(
		m,
		"Faixa",
		Vector3.new(w * 0.7, 0.07, 0.004),
		CFrame.new(0, h * 0.55, -d / 2 - 0.002),
		band,
		Enum.Material.SmoothPlastic
	)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(240, 24)
	sg.LightInfluence = 1
	sg.Parent = front
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.Arial
	t.TextScaled = true
	t.TextColor3 = if us then Color3.fromRGB(30, 30, 24) else Color3.fromRGB(236, 220, 190)
	t.Text = if us then "CTG 7.62MM  M80 BALL" else "弹药  7.62"
	t.Parent = sg
	-- lata de munição em cima (M19A1 nos EUA; lata chinesa no VC)
	local can = part(
		m,
		"Lata",
		Vector3.new(0.1, 0.16, 0.26),
		CFrame.new(w * 0.18, h + 0.1, 0.02) * CFrame.Angles(0, math.rad(8), 0),
		if us then Color3.fromRGB(70, 80, 50) else Color3.fromRGB(86, 92, 70),
		Enum.Material.Metal
	)
	can.CastShadow = true
	m.PrimaryPart = body
	m.WorldPivot = CFrame.identity -- meio da base
	return m
end

-- Modelo da caixa do lado, com o pivô no meio da base (o publicado é medido pela caixa envolvente)
local function template(faction: string): Model
	local cached = templates[faction]
	if cached then
		return cached
	end
	local key = ART_KEY[faction]
	local tpl: Model? = nil
	if key and published(key) then
		tpl = AssetLoader.template(key)
	end
	if not tpl and published("ammo_crate") then
		tpl = AssetLoader.template("ammo_crate")
	end
	local m: Model
	if tpl then
		m = tpl:Clone()
		m:PivotTo(CFrame.new())
		local box, size = m:GetBoundingBox()
		m.WorldPivot = CFrame.new(box.X, box.Y - size.Y / 2, box.Z)
	else
		m = partsBox(faction)
	end
	m.Name = "CaixaMunicao"
	-- modelo do Blender (metricas.json "uso", como o MapLife.baseTemplate faz nas bases): o nó
	-- Colisao_Caixa é a colisão invisível de madeira (para bala); os nós visuais não colidem
	local hasCollider = false
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 8) == "Colisao_" then
			hasCollider = true
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			if string.sub(d.Name, 1, 8) == "Colisao_" then
				d.Transparency = 1
				d.CanCollide, d.CanQuery, d.CastShadow = true, true, false
				d:SetAttribute("Material", "Wood")
			elseif hasCollider then
				d.CanCollide, d.CanQuery = false, false
			end
		end
	end
	templates[faction] = m
	-- cópia para a prévia do cliente (translúcida, sem colisão)
	local art = ReplicatedStorage:FindFirstChild("VT65CaixaArte")
	if not art then
		art = Instance.new("Folder")
		art.Name = "VT65CaixaArte"
		art.Parent = ReplicatedStorage
	end
	local old = art:FindFirstChild(faction)
	if old then
		old:Destroy()
	end
	local copy = m:Clone()
	copy.Name = faction
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 8) == "Colisao_" then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
		elseif d:IsA("SurfaceAppearance") then
			d:Destroy() -- a prévia é pintada de verde ou vermelho (Controllers/CaixaMunicao.client)
		end
	end
	copy.Parent = art
	return m
end

-- ===== caixas =====
local function notify(p: Player?, msg: string, ok: boolean?, what: string?)
	if p then
		Net.event("Caixa_Aviso"):FireClient(p, { msg = msg, ok = ok == true, w = what })
	end
end

local function removeBox(b: CaixaMunicao.Box)
	local i = table.find(boxes, b)
	if i then
		table.remove(boxes, i)
	end
	local m = models[b.id]
	models[b.id] = nil
	if m then
		m:Destroy()
	end
end

function CaixaMunicaoService.list(): { CaixaMunicao.Box }
	return boxes
end

-- Caixa do lado mais perto de pos (studs), a até maxM metros
function CaixaMunicaoService.nearest(faction: string, pos: Vector3, maxM: number): CaixaMunicao.Box?
	return CaixaMunicao.nearest(boxes, faction, pos.X, pos.Z, maxM, M, os.clock())
end

function CaixaMunicaoService.ownerBox(owner: string): CaixaMunicao.Box?
	return CaixaMunicao.replaced(boxes, owner)
end

function CaixaMunicaoService.sinceLast(owner: string): number
	local t = lastPlaced[owner]
	return if t then os.clock() - t else math.huge
end

-- Põe a caixa (já conferida) com a base em `pos`. A anterior do mesmo dono sai.
function CaixaMunicaoService.place(
	owner: string,
	faction: string,
	pos: Vector3,
	yaw: number,
	ownerName: string?
): CaixaMunicao.Box
	local old = CaixaMunicao.replaced(boxes, owner)
	if old then
		removeBox(old)
	end
	seq += 1
	local now = os.clock()
	local b = CaixaMunicao.new("cx" .. seq, owner, faction, pos.X, pos.Y, pos.Z, now)
	local m = template(faction):Clone()
	m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
	m:SetAttribute("Faction", faction)
	m:SetAttribute("Owner", owner)
	m:SetAttribute("OwnerName", ownerName or "")
	m:SetAttribute("Stock", b.stock)
	m:SetAttribute("StockMax", CaixaMunicao.ESTOQUE)
	m:SetAttribute("Until", workspace:GetServerTimeNow() + CaixaMunicao.DURACAO_S)
	m:SetAttribute("BoxId", b.id)
	m.Parent = folder
	-- v41/v42 (achado da v40: a caixa de 0,54 m some no capim alto do terreno): o capim em volta vira
	-- terra pisada (a grama animada do terreno só nasce no Grass); ~2 voxels de 1,12 m, como o napalm
	pcall(function()
		local ext = Vector3.new(1.2, 1.5, 1.2) / M
		local region = Region3.new(pos - ext, pos + ext):ExpandToGrid(4)
		for _, mat in { Enum.Material.Grass, Enum.Material.LeafyGrass } do
			workspace.Terrain:ReplaceMaterial(region, 4, mat, Enum.Material.Ground)
		end
	end)
	lastPlaced[owner] = now
	table.insert(boxes, b)
	models[b.id] = m
	return b
end

-- Chão sob (x, z) perto de y: (posição, normal, material) ou nil. Ignora soldados e caixas.
local function groundAt(x: number, y: number, z: number): (Vector3?, Vector3?, Enum.Material?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, e in Combatants.list() do
		table.insert(skip, e.model)
	end
	if folder then
		table.insert(skip, folder)
	end
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = false
	local hit = workspace:Raycast(Vector3.new(x, y + 1.5 / M, z), Vector3.new(0, -4 / M, 0), params)
	if not hit then
		return nil, nil, nil
	end
	return hit.Position, hit.Normal, hit.Material
end

-- algo sólido no volume da caixa (fora o terreno, soldados e caixas)?
local function blockedAt(pos: Vector3, yaw: number, faction: string): boolean
	local w, h, d = CaixaMunicao.size(faction)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { workspace.Terrain }
	for _, e in Combatants.list() do
		table.insert(skip, e.model)
	end
	if folder then
		table.insert(skip, folder)
	end
	op.FilterDescendantsInstances = skip
	op.RespectCanCollide = true
	local cf = CFrame.new(pos + Vector3.new(0, (h / 2 + 0.06) / M, 0)) * CFrame.Angles(0, yaw, 0)
	local parts = workspace:GetPartBoundsInBox(cf, Vector3.new(w, h, d) * 0.9 / M, op)
	return #parts > 0
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < 1e6
end

local function onPlace(p: Player, req: any)
	if type(req) ~= "table" or not (finite(req.x) and finite(req.y) and finite(req.z)) then
		return
	end
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local faction = p:GetAttribute("Faction")
	if not (char and hum and root and type(faction) == "string") then
		return
	end
	local owner = "p:" .. p.UserId
	local yaw = if finite(req.yaw) then req.yaw :: number else 0
	local pos, normal, mat = groundAt(req.x, req.y, req.z)
	local role = p:GetAttribute("Role")
	local ok, why = CaixaMunicao.canPlace({
		role = if type(role) == "string" then role else nil,
		alive = hum.Health > 0 and not char:GetAttribute("Downed"),
		seated = hum.SeatPart ~= nil,
		distM = if pos
			then Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z).Magnitude * M
			else math.huge,
		-- a raiz fica ~1 m acima dos pés (soldado de 2 m)
		dyM = if pos then (pos.Y - root.Position.Y) * M + 1 else 0,
		slopeDeg = if normal then CaixaMunicao.slope(normal.X, normal.Y, normal.Z) else 90,
		water = mat == Enum.Material.Water,
		blocked = pos ~= nil and blockedAt(pos, yaw, faction),
		ground = pos ~= nil,
		sinceLastS = CaixaMunicaoService.sinceLast(owner),
	})
	if not ok or not pos then
		notify(p, why or "agora não", false)
		return
	end
	CaixaMunicaoService.place(owner, faction, pos, yaw, p.DisplayName)
	notify(p, "Caixa de munição no chão", true, "posta")
end

-- ===== pegar ao passar perto =====
local function reachOf(b: CaixaMunicao.Box, root: BasePart): boolean
	local dx, dz = root.Position.X - b.x, root.Position.Z - b.z
	local flatM = math.sqrt(dx * dx + dz * dz) * M
	-- a raiz fica ~1 m acima do chão
	local dyM = (root.Position.Y - b.y) * M - 1
	return CaixaMunicao.inReach(flatM, dyM)
end

-- XP de "Reabastecimento" para quem pôs (Progression.REWARDS.resupply; o mesmo par só a cada 2 min)
local function rewardOwner(b: CaixaMunicao.Box, who: string)
	if not CaixaMunicao.rewards(b.owner, who) then
		return
	end
	local uid = tonumber(string.sub(b.owner, 3))
	local op = if uid then Players:GetPlayerByUserId(uid) else nil
	if op then
		ProgressionService.award(op, "resupply", who)
	end
end

local function playerTake(b: CaixaMunicao.Box, p: Player, now: number): boolean
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) or p:GetAttribute("Faction") ~= b.faction then
		return false
	end
	local who = "p:" .. p.UserId
	local reach = reachOf(b, root)
	if not reach then
		return false
	end
	local alive = hum.Health > 0 and not char:GetAttribute("Downed") and hum.SeatPart == nil
	local spare, full, others = CombatService.ammoNeed(p)
	local frags = tonumber(p:GetAttribute("Frags")) or 0
	local fragsMax = tonumber(p:GetAttribute("FragsMax")) or frags
	local rockets = if p:GetAttribute("Role") == "anti_tank" then tonumber(p:GetAttribute("Rockets")) or 0 else nil
	local needs = CaixaMunicao.needs({
		spare = spare,
		spareFull = full,
		frags = frags,
		fragsMax = fragsMax,
		rockets = rockets,
		others = others,
	})
	if not CaixaMunicao.canTake(b, who, p:GetAttribute("Faction") :: string?, alive, reach, needs, now) then
		return false
	end
	CaixaMunicao.take(b, who, now)
	CombatService.resupply(p)
	local gotFrag = frags < fragsMax
	p:SetAttribute("Frags", CaixaMunicao.grenadesAfter(frags, fragsMax))
	if rockets then
		p:SetAttribute("Rockets", CaixaMunicao.rocketsAfter(rockets))
	end
	notify(p, if gotFrag then "Munição e 1 granada da caixa" else "Munição da caixa", true, "pegou")
	rewardOwner(b, who)
	return true
end

local function botTake(b: CaixaMunicao.Box, e: Combatants.Entry, now: number): boolean
	local needsFn, refill = CaixaMunicaoService.botNeeds, CaixaMunicaoService.botRefill
	if not (needsFn and refill) or e.faction ~= b.faction then
		return false
	end
	local root = Combatants.root(e)
	if not root or not reachOf(b, root) then
		return false
	end
	local who = "b:" .. tostring(e.model:GetAttribute("BotIndex") or e.model.Name)
	if not CaixaMunicao.canTake(b, who, e.faction, Combatants.active(e), true, needsFn(e.model), now) then
		return false
	end
	CaixaMunicao.take(b, who, now)
	refill(e.model)
	rewardOwner(b, who)
	return true
end

local function step()
	local now = os.clock()
	for i = #boxes, 1, -1 do
		local b = boxes[i]
		if CaixaMunicao.gone(b, now) then
			removeBox(b)
		end
	end
	if #boxes == 0 then
		return
	end
	local players = Players:GetPlayers()
	local list = Combatants.list()
	for _, b in boxes do
		local before = b.stock
		for _, p in players do
			if b.stock <= 0 then
				break
			end
			playerTake(b, p, now)
		end
		for _, e in list do
			if b.stock <= 0 then
				break
			end
			if e.bot then
				botTake(b, e, now)
			end
		end
		if b.stock ~= before then
			local m = models[b.id]
			if m then
				m:SetAttribute("Stock", b.stock)
			end
		end
	end
end

function CaixaMunicaoService.start()
	local f = Instance.new("Folder")
	f.Name = "CaixasMunicao"
	f.Parent = workspace
	folder = f
	-- a arte carrega antes da 1ª caixa (LoadAsset espera): a prévia do cliente já tem a forma
	task.spawn(function()
		pcall(template, "US")
		pcall(template, "VC")
	end)
	Net.event("Caixa_Por").OnServerEvent:Connect(onPlace)
	Players.PlayerRemoving:Connect(function(p)
		local b = CaixaMunicao.replaced(boxes, "p:" .. p.UserId)
		if b then
			removeBox(b)
		end
		lastPlaced["p:" .. p.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(function(): any
				step()
				return nil
			end)
			if not ok then
				warn("[VT65 CAIXA] " .. tostring(err))
			end
		end
	end)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevCaixa"):Connect(function()
			if workspace:GetAttribute("VT65DevCaixa") ~= true then
				return
			end
			workspace:SetAttribute("VT65DevCaixa", nil)
			for _, p in Players:GetPlayers() do
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local faction = p:GetAttribute("Faction")
				if root and type(faction) == "string" then
					local at = root.Position + root.CFrame.LookVector * (2 / M)
					local pos = groundAt(at.X, root.Position.Y, at.Z)
					if pos then
						-- a frente do modelo (−Z) para quem pôs: o rumo do soldado + 180°
						local _, ry = root.CFrame:ToOrientation()
						CaixaMunicaoService.place("p:" .. p.UserId, faction, pos, ry + math.pi, p.DisplayName)
						print(string.format("[VT65 CAIXA] caixa de %s posta à frente", p.Name))
					end
				end
			end
		end)
	end
end

return CaixaMunicaoService
