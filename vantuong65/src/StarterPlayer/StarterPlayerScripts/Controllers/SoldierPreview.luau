--!strict
-- Prévia 3D do soldado no lobby. Clona o manequim que o servidor vestiu
-- (ReplicatedStorage.VT65Preview.<US|VC>, PreviewService) e troca a arma pela do papel: a arte
-- publicada (cópias em ReplicatedStorage.VT65WeaponArt) ou, sem ela, a provisória do GunModel,
-- exatamente como AssetLoader.attachWeapon faz no spawn. Dois modos:
--   - SoldierPreview.new: retrato num ViewportFrame com WorldModel; a câmera gira devagar em volta do
--     soldado (mesa giratória) e a luz principal acompanha a câmera. Enquanto o manequim não chega,
--     mostra uma silhueta;
--   - SoldierPreview.newWorld: o soldado de pé na cena do lobby (LobbyScene), com os pés no ponto
--     dado, de frente para onde o ponto olha. Ilumina-se pelas luzes da cena.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GunModel = require(ReplicatedStorage.Shared.GunModel)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local UiKit = require(script.Parent.UiKit)

local SoldierPreview = {}

export type Preview = {
	frame: Frame?, -- contêiner do retrato: quem usa define Parent, Position e Size (nil no mundo)
	vp: ViewportFrame?,
	world: Instance, -- WorldModel do retrato ou a pasta da cena
	cam: Camera?,
	silhouette: Frame?,
	note: TextLabel?, -- texto da silhueta (quem usa registra o tamanho de texto)
	stand: CFrame?, -- modo mundo: chão sob os pés e direção do olhar
	wantFaction: string?,
	wantWeapon: string?,
	model: Model?,
	modelFaction: string?,
	weapon: string?, -- arma montada agora
	weaponArt: boolean, -- montada com a arte publicada (senão, a provisória)
	center: Vector3,
	dist: number,
	angle: number,
	speed: number, -- rad/s
	active: boolean,
}

local FOV = 24 -- teleobjetiva: pouca distorção, cara de retrato
local KEY = Vector3.new(0.55, -0.6, -1).Unit -- luz principal no espaço da câmera: de cima e da esquerda
local list: { Preview } = {}

-- Só devolve o manequim quando todas as peças chegaram (atributo Parts do PreviewService): a
-- replicação vem em pedaços, e o clone feito cedo demais ficava sem tronco (D-64).
local function source(faction: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("VT65Preview")
	local m = folder and folder:FindFirstChild(faction)
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
			return nil
		end
	end
	return m
end

local function weaponArt(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
	local tpl = folder and folder:FindFirstChild(id)
	return if tpl and tpl:IsA("Model") and tpl.PrimaryPart then tpl else nil
end

-- tudo parado e sem scripts (um LocalScript dentro da PlayerGui rodaria)
local function freeze(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
end

local function mountWeapon(p: Preview, id: string)
	local model = p.model
	local wp = Weapons.get(id)
	local hand = model and model:FindFirstChild("RightHand") :: BasePart?
	if not (model and wp and hand) then
		return
	end
	local art = weaponArt(id)
	local w: Model = if art then art:Clone() else GunModel.build(id, wp.kind)
	if not w.PrimaryPart then
		w:Destroy()
		return
	end
	local old = model:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	freeze(w)
	w.Name = "Weapon"
	w:PivotTo(hand.CFrame * CFrame.Angles(-math.pi / 2, 0, 0)) -- a mesma pega do AssetLoader.attachWeapon
	w.Parent = model
	p.weapon = id
	p.weaponArt = art ~= nil
end

local function frameModel(p: Preview)
	local model = p.model :: Model
	local cf, size = model:GetBoundingBox()
	local h = math.max(size.Y, 4)
	p.center = cf.Position + Vector3.new(0, h * 0.02, 0)
	p.dist = (h * 0.5 * 1.12) / math.tan(math.rad(FOV / 2))
end

-- modo mundo: pés no chão do ponto (a arma pendurada na mão não conta como "pé")
local function standModel(m: Model, stand: CFrame)
	m:PivotTo(stand)
	local bottom = math.huge
	for _, name in { "LeftFoot", "RightFoot" } do
		local f = m:FindFirstChild(name)
		if f and f:IsA("BasePart") then
			bottom = math.min(bottom, f.Position.Y - f.Size.Y / 2)
		end
	end
	if bottom == math.huge then
		local cf, size = m:GetBoundingBox()
		bottom = cf.Position.Y - size.Y / 2
	end
	m:PivotTo(stand + Vector3.new(0, stand.Position.Y - bottom, 0))
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function()
			hum.EvaluateStateMachine = false -- boneco parado: sem estados nem física de personagem
		end)
	end
end

local function sync(p: Preview)
	local f = p.wantFaction
	if f ~= p.modelFaction then
		if p.model then
			p.model:Destroy()
		end
		p.model, p.modelFaction, p.weapon, p.weaponArt = nil, nil, nil, false
		local src = if f then source(f) else nil
		if src then
			local m = src:Clone()
			freeze(m)
			local stand = p.stand
			if stand then
				standModel(m, stand)
			else
				m:PivotTo(CFrame.identity) -- frente do soldado em −Z
			end
			m.Parent = p.world
			p.model, p.modelFaction = m, f
			local w = m:FindFirstChild("Weapon")
			local wid = src:GetAttribute("Weapon")
			p.weapon = if type(wid) == "string" then wid else nil
			-- a provisória (GunModel.build) tem o atributo Kind; a publicada (GunModel.fit), não
			p.weaponArt = w ~= nil and w:GetAttribute("Kind") == nil
			if not stand then
				frameModel(p)
			end
		end
	end
	local sil = p.silhouette
	if sil then
		sil.Visible = p.model == nil
	end
	local want = p.wantWeapon or p.weapon
	if p.model and want and (want ~= p.weapon or (not p.weaponArt and weaponArt(want) ~= nil)) then
		mountWeapon(p, want)
	end
end

local function syncAll()
	for _, p in list do
		sync(p)
	end
end

local function blank(world: Instance): Preview
	return {
		frame = nil,
		vp = nil,
		world = world,
		cam = nil,
		silhouette = nil,
		note = nil,
		stand = nil,
		wantFaction = nil,
		wantWeapon = nil,
		model = nil,
		modelFaction = nil,
		weapon = nil,
		weaponArt = false,
		center = Vector3.zero,
		dist = 16,
		angle = -0.45,
		speed = 0.24,
		active = false,
	}
end

-- Retrato num ViewportFrame (p.frame e p.note existem sempre neste modo)
function SoldierPreview.new(speed: number?, startAngle: number?): Preview
	local frame = Instance.new("Frame")
	frame.Name = "SoldierPreview"
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ClipsDescendants = true
	-- fundo de estúdio: claro atrás da cabeça, escuro no chão (cor pelo gradiente)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(156, 146, 114)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(92, 92, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(38, 40, 30)),
	})
	grad.Parent = frame

	local sil = Instance.new("Frame")
	sil.Name = "Silhouette"
	sil.BackgroundTransparency = 1
	sil.Size = UDim2.fromScale(1, 1)
	sil.Parent = frame
	local head = Instance.new("Frame")
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0.16)
	head.Size = UDim2.fromScale(0.2, 0.2)
	head.BackgroundColor3 = UiKit.INK
	head.BackgroundTransparency = 0.55
	head.BorderSizePixel = 0
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = head
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0.5, 0)
	hc.Parent = head
	head.Parent = sil
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.38)
	body.Size = UDim2.fromScale(0.5, 0.7)
	body.BackgroundColor3 = UiKit.INK
	body.BackgroundTransparency = 0.55
	body.BorderSizePixel = 0
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.35, 0)
	bc.Parent = body
	body.Parent = sil
	local note = Instance.new("TextLabel")
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = UDim2.new(0.5, 0, 1, -8)
	note.Size = UDim2.new(1, -16, 0, 44)
	note.BackgroundTransparency = 1
	note.Font = Enum.Font.SpecialElite
	note.TextColor3 = UiKit.CARD
	note.TextWrapped = true
	note.TextSize = UiKit.text(16)
	note.Text = "FOTO A CAMINHO…\nequipamento sendo carregado"
	note.ZIndex = 2
	note.Parent = sil

	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(104, 100, 86)
	vp.LightColor = Color3.fromRGB(255, 212, 160) -- luz principal quente
	vp.ImageColor3 = Color3.fromRGB(255, 246, 228) -- leve tom de cópia fotográfica
	vp.Parent = frame
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam

	local p = blank(world)
	p.frame, p.vp, p.cam, p.silhouette, p.note = frame, vp, cam, sil, note
	p.angle = startAngle or -0.45
	p.speed = speed or 0.24 -- uma volta em ~26 s
	table.insert(list, p)
	return p
end

-- Soldado de pé na cena: `stand` é o chão sob os pés, olhando para a frente do soldado (−Z).
function SoldierPreview.newWorld(parent: Instance, stand: CFrame): Preview
	local p = blank(parent)
	p.stand = stand
	table.insert(list, p)
	return p
end

-- facção (nil = nada / silhueta) e arma do papel (nil = a que o servidor montou: a do fuzileiro)
function SoldierPreview.set(p: Preview, faction: string?, weaponId: string?)
	if faction == p.wantFaction and weaponId == p.wantWeapon then
		return
	end
	p.wantFaction, p.wantWeapon = faction, weaponId
	sync(p)
end

function SoldierPreview.setActive(p: Preview, on: boolean)
	p.active = on
end

-- mesa giratória: só os retratos ativos; nenhuma tabela ou instância criada por quadro
RunService.RenderStepped:Connect(function(dt: number)
	for _, p in list do
		local cam, vp = p.cam, p.vp
		if p.active and p.model and cam and vp then
			local a = (p.angle + dt * p.speed) % (2 * math.pi)
			p.angle = a
			local c, d = p.center, p.dist
			local cf = CFrame.lookAt(Vector3.new(c.X + math.sin(a) * d, c.Y + d * 0.05, c.Z - math.cos(a) * d), c)
			cam.CFrame = cf
			vp.LightDirection = cf:VectorToWorldSpace(KEY)
		end
	end
end)

-- manequins e arte das armas chegam do servidor depois (PreviewService, AssetLoader)
local watched: { [Instance]: boolean } = {}
local pending = false
local function syncSoon()
	-- várias peças chegam no mesmo quadro: um sync só
	if not pending then
		pending = true
		task.defer(function()
			pending = false
			syncAll()
		end)
	end
end
local function watch(folder: Instance)
	if watched[folder] then
		return
	end
	watched[folder] = true
	folder.DescendantAdded:Connect(syncSoon) -- peça a peça: o manequim só vale completo (source)
end
for _, name in { "VT65Preview", "VT65WeaponArt" } do
	local f = ReplicatedStorage:FindFirstChild(name)
	if f then
		watch(f)
	end
end
ReplicatedStorage.ChildAdded:Connect(function(c)
	if c.Name == "VT65Preview" or c.Name == "VT65WeaponArt" then
		watch(c)
		syncSoon()
	end
end)

return SoldierPreview
