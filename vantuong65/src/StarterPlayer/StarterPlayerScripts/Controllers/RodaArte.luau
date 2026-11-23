--!strict
-- D-190 (dono: "o principal são as imagens reconhecíveis das armas e dos itens"): o desenho de cada
-- setor da roda de equipamento é o próprio modelo do jogo num ViewportFrame, parado e enquadrado:
--   - armas: a arte publicada (ReplicatedStorage.VT65WeaponArt, a mesma da 1ª pessoa e da
--     Intendência), de lado; sem ela, a provisória do GunModel;
--   - granada e fumaça: Shared/GrenadeArt (a mesma da mão);
--   - pá: Shared/PaArte (a do Blender, D-183);
--   - bandagem e torniquete: as peças da mão de 1ª pessoa (Shared/ItemAnim.PROPS);
--   - construir: sacos de areia; ferramenta do papel: o lançador (antitanque), a caixa de munição
--     (suporte), a bolsa do médico (médico) e o rádio (comandante). PLACEHOLDER de forma (peças
--     simples) até um modelo próprio.
-- Um modelo por chave fica guardado; cada setor clona o dele só quando a chave muda.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Equipar = require(ReplicatedStorage.Shared.Equipar)
local GrenadeArt = require(ReplicatedStorage.Shared.GrenadeArt) :: any
local GunModel = require(ReplicatedStorage.Shared.GunModel) :: any
local ItemAnim = require(ReplicatedStorage.Shared.ItemAnim)
local PaArte = require(ReplicatedStorage.Shared.PaArte) :: any
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any

local RodaArte = {}
local player = Players.LocalPlayer
local M = 0.28

local function faction(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else nil
end

local function piece(
	m: Model,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	if shape then
		p.Shape = shape
	end
	p.Size = size / M
	p.CFrame = CFrame.new(cf.Position / M) * cf.Rotation
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = m
	return p
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function weapon(id: string): Model
	local folder = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
	local art = if folder then folder:FindFirstChild(id) else nil
	if art and art:IsA("Model") then
		return art:Clone()
	end
	local wp = Weapons.get(id)
	return GunModel.build(id, if wp then wp.kind else nil)
end

local function bandage(): Model
	local m = Instance.new("Model")
	local d = ItemAnim.PROPS.curativo
	-- rolo de gaze com a ponta solta
	piece(
		m,
		Vector3.new(d.size[1], d.size[2], d.size[2]),
		CFrame.Angles(0, 0, math.pi / 2),
		rgb(d.rgb),
		Enum.Material.Fabric,
		Enum.PartType.Cylinder
	)
	piece(m, Vector3.new(0.05, 0.004, d.size[2] * 0.9), CFrame.new(0.03, -0.027, 0), rgb(d.rgb), Enum.Material.Fabric)
	return m
end

local function tourniquet(): Model
	local m = Instance.new("Model")
	local d = ItemAnim.PROPS.torniquete
	-- a tira em laço e a fivela
	for i = 0, 5 do
		local a = i * math.pi / 3
		piece(
			m,
			Vector3.new(0.035, 0.012, 0.03),
			CFrame.new(math.cos(a) * 0.045, math.sin(a) * 0.045, 0) * CFrame.Angles(0, 0, a + math.pi / 2),
			rgb(d.rgb),
			Enum.Material.Fabric
		)
	end
	piece(
		m,
		Vector3.new(0.03, 0.02, 0.034),
		CFrame.new(0, -0.05, 0),
		Color3.fromRGB(150, 146, 132),
		Enum.Material.Metal
	)
	return m
end

local function sandbags(): Model
	local m = Instance.new("Model")
	local tan = Color3.fromRGB(176, 156, 112)
	for i, p in { { -0.17, 0 }, { 0.17, 0 }, { 0, 0.11 } } do
		local b = piece(m, Vector3.new(0.32, 0.12, 0.2), CFrame.new(p[1], p[2], 0), tan, Enum.Material.Fabric)
		b.Name = string.format("Saco%d", i)
	end
	return m
end

local function ammoCan(): Model
	local m = Instance.new("Model")
	local olive = Color3.fromRGB(78, 84, 52)
	piece(m, Vector3.new(0.28, 0.18, 0.1), CFrame.identity, olive, Enum.Material.Metal)
	piece(
		m,
		Vector3.new(0.29, 0.03, 0.105),
		CFrame.new(0, 0.095, 0),
		olive:Lerp(Color3.new(0, 0, 0), 0.2),
		Enum.Material.Metal
	)
	piece(m, Vector3.new(0.12, 0.012, 0.02), CFrame.new(0, 0.115, 0), Color3.fromRGB(40, 40, 36), Enum.Material.Metal)
	return m
end

local function medicBag(): Model
	local m = Instance.new("Model")
	piece(m, Vector3.new(0.26, 0.16, 0.1), CFrame.identity, Color3.fromRGB(116, 112, 76), Enum.Material.Fabric)
	local white = Color3.fromRGB(226, 222, 206)
	piece(m, Vector3.new(0.09, 0.09, 0.004), CFrame.new(0, 0, -0.051), white)
	local red = Color3.fromRGB(176, 40, 32)
	piece(m, Vector3.new(0.07, 0.022, 0.006), CFrame.new(0, 0, -0.053), red)
	piece(m, Vector3.new(0.022, 0.07, 0.006), CFrame.new(0, 0, -0.053), red)
	return m
end

local function radio(): Model
	local m = Instance.new("Model")
	local olive = Color3.fromRGB(70, 74, 50)
	piece(m, Vector3.new(0.22, 0.27, 0.1), CFrame.identity, olive, Enum.Material.Metal)
	piece(
		m,
		Vector3.new(0.006, 0.42, 0.006),
		CFrame.new(0.08, 0.34, 0),
		Color3.fromRGB(30, 30, 28),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	local h = ItemAnim.PROPS.fone
	piece(m, Vector3.new(h.size[1], h.size[2], h.size[3]), CFrame.new(-0.15, 0.02, 0), rgb(h.rgb))
	return m
end

-- art: "weapon:<id>" | "grenade:frag" | "grenade:smoke" | "shovel" | "bandage" | "tourniquet" |
-- "build" | "role:<papel>"
local function build(art: string): Model?
	local fac = faction()
	local k0, a0 = string.match(art, "^([^:]+):?(.*)$")
	local kind: string = k0 or ""
	local arg: string = a0 or ""
	if kind == "weapon" then
		return if arg ~= "" then weapon(Equipar.handId(arg, fac) or arg) else nil
	elseif kind == "grenade" then
		return GrenadeArt.hand(if arg == "smoke" then "smoke" else "frag", fac)
	elseif kind == "shovel" then
		return PaArte.build(fac, true)
	elseif kind == "bandage" then
		return bandage()
	elseif kind == "tourniquet" then
		return tourniquet()
	elseif kind == "build" then
		return sandbags()
	elseif kind == "role" then
		if arg == "anti_tank" then
			return weapon(Equipar.handId("launcher", fac) or "launcher")
		elseif arg == "support" then
			return ammoCan()
		elseif arg == "medic" then
			return medicBag()
		elseif arg == "commander" then
			return radio()
		end
	end
	return nil
end

local cache: { [string]: Model } = {}
local function cacheKey(art: string): string
	local fac = faction() or "?"
	-- a pá muda quando a arte do Blender chega (PaArte.cacheKey)
	local extra = if art == "shovel" then PaArte.cacheKey(faction()) else ""
	return string.format("%s|%s|%s", art, fac, extra)
end

local function modelFor(art: string): Model?
	local key = cacheKey(art)
	local m = cache[key]
	if m then
		return m
	end
	local ok, made = pcall(build, art)
	if not (ok and made) then
		return nil
	end
	local model = made :: Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	model:PivotTo(CFrame.identity)
	cache[key] = model
	return model
end

-- Uma janela de desenho para um setor (sem modelo ainda).
function RodaArte.frame(parent: Instance): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Arte"
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(150, 146, 136)
	vp.LightColor = Color3.fromRGB(255, 244, 226)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.8)
	vp.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 24
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- Põe o desenho `art` na janela (nada se já é ele). false = sem desenho para esta chave.
function RodaArte.show(vp: ViewportFrame, art: string?): boolean
	local key = if art then cacheKey(art) else ""
	if vp:GetAttribute("Arte") == key then
		return art ~= nil and vp:FindFirstChildOfClass("Model") ~= nil
	end
	vp:SetAttribute("Arte", key)
	for _, c in vp:GetChildren() do
		if c:IsA("Model") then
			c:Destroy()
		end
	end
	if not art then
		return false
	end
	local src = modelFor(art)
	if not src then
		return false
	end
	local m = src:Clone()
	m.Parent = vp
	local cam = vp.CurrentCamera
	if not cam then
		return true
	end
	local cf, size = m:GetBoundingBox()
	local dist = size.Magnitude / 2 / math.tan(math.rad(cam.FieldOfView / 2)) * 1.02
	local weaponLike = string.sub(art, 1, 7) == "weapon:" or art == "role:anti_tank" or art == "shovel"
	if weaponLike then
		-- de lado, como na Intendência (o cano não sai do quadro)
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist, dist * 0.18, dist * 0.12), cf.Position)
	else
		-- três quartos, de cima
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.62, dist * 0.5, -dist * 0.62), cf.Position)
	end
	return true
end

-- A chave do desenho de um item da roda de equipamento (nil = sem desenho).
function RodaArte.artFor(id: string, weaponId: string?, role: string?): string?
	if string.sub(id, 1, 5) == "slot:" then
		return if weaponId then "weapon:" .. weaponId else nil
	elseif id == "frag" or id == "smoke" then
		return "grenade:" .. id
	elseif id == "shovel" or id == "bandage" or id == "tourniquet" or id == "build" then
		return id
	elseif id == "role_tool" then
		return if role then "role:" .. role else nil
	end
	return nil
end

return RodaArte
