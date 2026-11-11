--!strict
-- Vida no mapa (D-74, pedido do dono: "dar vida ao mapa" com o arroz, os animais e os túneis).
-- - arrozal: dossel verde de cada tabuleiro plantado (o que se vê de longe) e os ladrilhos de
--   arroz para o cliente (RiceField.client cobre os tabuleiros perto da câmera);
-- - túneis: escoras de madeira a cada 4 m, lamparinas de barro e as três câmaras mobiliadas
--   (posto de comando e enfermaria, depósito, cozinha);
-- - vilas: fumaça de cozinha, potes d'água de barro, medas de palha e lenha.
-- Peças simples (sem malha nova): baratas e fora do teto de triângulos do setor.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RiceField = require(ReplicatedStorage.Shared.RiceField)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Tunnels = require(ReplicatedStorage.Shared.Tunnels) :: any

local MapLife = {}
local M = 0.28
MapLife.LAMP_TAG = "VT65Lamp" -- o cliente faz a chama tremer (RiceField.client)
local RICE_KEYS: { [string]: string } = { hi = "rice_tile_hi", lo = "rice_tile_lo" }

local WOOD = Color3.fromRGB(88, 62, 40)
local CLAY = Color3.fromRGB(150, 86, 56)
local CLAY_DARK = Color3.fromRGB(112, 64, 42)
local STRAW = Color3.fromRGB(186, 156, 92)
local BAMBOO = Color3.fromRGB(164, 146, 96)
local SACK = Color3.fromRGB(196, 180, 140)
local CRATE = Color3.fromRGB(78, 84, 52)
local MAT = Color3.fromRGB(176, 150, 96)
-- dossel visto de longe: arroz em pé (verde cheio) e muda nova (verde-amarelado, água aparecendo)
local CANOPY = {
	mature = Color3.fromRGB(74, 98, 36),
	young = Color3.fromRGB(98, 114, 52),
} :: { [string]: Color3 }

local function part(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

-- cilindro em pé (o eixo do cilindro do Roblox é X)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

---------------------------------------------------------------------------------------------
-- Arrozal
---------------------------------------------------------------------------------------------

-- Dossel em cada tabuleiro plantado (85% deles) e ladrilhos em ReplicatedStorage.VT65RiceArt.
-- template: AssetLoader.template. Devolve quantos tabuleiros têm arroz.
function MapLife.rice(map: Instance, template: (string) -> Model?): number
	local water = map:FindFirstChild("PaddyWater")
	if not water then
		return 0
	end
	local art = Instance.new("Folder")
	art.Name = "VT65RiceArt"
	for lod, key in RICE_KEYS do
		local tpl = template(key)
		local mp = tpl and tpl:FindFirstChildWhichIsA("MeshPart", true)
		if mp then
			local c = mp:Clone()
			c.Name = lod
			c.Anchored = true
			c.CanCollide = false
			c.CanTouch = false
			c.CanQuery = false
			c.CastShadow = false
			-- Sem mapa normal o importador põe a cor em TextureID (sem SurfaceAppearance), e a
			-- MeshPart só recorta pelo alfa da textura com Transparency acima de 0: com 0 os
			-- cartões saíam como triângulos verdes opacos (Studio, 2026-11-11)
			c.Transparency = 0.02
			local sa = c:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				sa.AlphaMode = Enum.AlphaMode.Transparency
			end
			c.Parent = art
		end
	end
	art.Parent = ReplicatedStorage
	local folder = Instance.new("Folder")
	folder.Name = "Arrozal"
	local n = 0
	for _, p in water:GetChildren() do
		if p:IsA("BasePart") then
			local kind = RiceField.kind(p.Position.X, p.Position.Z)
			local h = RiceField.HEIGHT[kind]
			local sx, sz = p.Size.X - 2 * RiceField.INSET, p.Size.Z - 2 * RiceField.INSET
			if h and sx > 4 and sz > 4 then
				local top = p.Position.Y + p.Size.Y / 2
				local c = part(
					"Dossel",
					Vector3.new(sx, 0.2, sz),
					p.CFrame * CFrame.new(0, top - p.Position.Y + RiceField.CANOPY_Y * h, 0),
					CANOPY[kind],
					Enum.Material.Grass,
					folder
				)
				c:SetAttribute("WaterY", top)
				c:SetAttribute("H", h)
				n += 1
			end
		end
	end
	folder.Parent = map
	return n
end

---------------------------------------------------------------------------------------------
-- Túneis
---------------------------------------------------------------------------------------------

local function lamp(parent: Instance, cf: CFrame)
	part("Nicho", Vector3.new(0.7, 0.15, 0.7), cf, Color3.fromRGB(70, 54, 38), Enum.Material.Ground, parent)
	part("Lamparina", Vector3.new(0.45, 0.3, 0.45), cf * CFrame.new(0, 0.22, 0), CLAY, Enum.Material.Slate, parent)
	local flame = part(
		"Chama",
		Vector3.new(0.1, 0.22, 0.1),
		cf * CFrame.new(0, 0.48, 0),
		Color3.fromRGB(255, 176, 84),
		Enum.Material.Neon,
		parent
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 162, 84)
	light.Range = 14
	light.Brightness = 1.1
	light.Shadows = false
	light.Parent = flame
	CollectionService:AddTag(flame, MapLife.LAMP_TAG)
end

-- Rumos (rad, no plano XZ) das galerias que saem de um nó: os móveis da câmara ficam fora deles.
local function mouths(id: string): { number }
	local out = {}
	local a = Tunnels.nodes[id]
	for _, e in Tunnels.edges do
		local other = if e[1] == id then e[2] elseif e[2] == id then e[1] else nil
		if other then
			local b = Tunnels.nodes[other]
			table.insert(out, math.atan2(b.z - a.z, b.x - a.x))
		end
	end
	return out
end

-- Até `want` cantos livres da câmara (rumos a pelo menos 40° de toda galeria).
function MapLife.freeSlots(id: string, want: number): { number }
	local busy = mouths(id)
	local out = {}
	for k = 0, 7 do
		local ang = k * math.pi / 4 + math.pi / 8
		local ok = true
		for _, b in busy do
			local d = math.abs((ang - b + math.pi) % (2 * math.pi) - math.pi)
			if d < math.rad(40) then
				ok = false
				break
			end
		end
		if ok then
			table.insert(out, ang)
			if #out >= want then
				break
			end
		end
	end
	return out
end

local function mats(parent: Instance, cf: CFrame)
	for k = -1, 1, 2 do
		part(
			"Esteira",
			Vector3.new(1.7, 0.08, 4.6),
			cf * CFrame.new(k * 1.0, 0.04, 0),
			MAT,
			Enum.Material.Fabric,
			parent
		)
	end
	part("Trouxa", Vector3.new(1.2, 0.5, 0.8), cf * CFrame.new(-1.0, 0.3, -1.9), SACK, Enum.Material.Fabric, parent)
end

local function crates(parent: Instance, cf: CFrame)
	part("Caixote", Vector3.new(2.0, 1.1, 1.2), cf * CFrame.new(0, 0.55, 0), CRATE, Enum.Material.WoodPlanks, parent)
	part(
		"Caixote",
		Vector3.new(2.0, 1.1, 1.2),
		cf * CFrame.new(0.2, 1.65, 0.05) * CFrame.Angles(0, 0.1, 0),
		CRATE,
		Enum.Material.WoodPlanks,
		parent
	)
	part("Caixote", Vector3.new(1.4, 0.8, 1.0), cf * CFrame.new(0, 0.4, 1.3), CRATE, Enum.Material.WoodPlanks, parent)
end

local function sacks(parent: Instance, cf: CFrame)
	for k = 0, 3 do
		local x, y = (k % 2) * 1.3 - 0.65, if k < 2 then 0.45 else 1.25
		part(
			"SacoDeArroz",
			Vector3.new(1.2, 0.9, 1.6),
			cf * CFrame.new(x, y, 0) * CFrame.Angles(0, k * 0.2, 0),
			SACK,
			Enum.Material.Fabric,
			parent
		)
	end
end

local function stove(parent: Instance, cf: CFrame)
	-- fogão de barro com chaminé enterrada (o "fogão sem fumaça" dos túneis): fogo baixo e panela
	part("Fogao", Vector3.new(2.4, 1.0, 2.0), cf * CFrame.new(0, 0.5, 0), CLAY_DARK, Enum.Material.Slate, parent)
	part(
		"Panela",
		Vector3.new(0.7, 1.3, 1.3),
		cf * CFrame.new(0, 1.3, 0) * UPRIGHT,
		Color3.fromRGB(40, 38, 36),
		Enum.Material.Metal,
		parent,
		Enum.PartType.Cylinder
	)
	local ember = part(
		"Brasa",
		Vector3.new(1.0, 0.25, 0.4),
		cf * CFrame.new(0, 0.35, -1.0),
		Color3.fromRGB(255, 110, 40),
		Enum.Material.Neon,
		parent
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 50)
	light.Range = 10
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = ember
	CollectionService:AddTag(ember, MapLife.LAMP_TAG)
end

local function stretcher(parent: Instance, cf: CFrame)
	for k = -1, 1, 2 do
		part(
			"Vara",
			Vector3.new(0.15, 0.15, 5.4),
			cf * CFrame.new(k * 0.75, 0.35, 0),
			BAMBOO,
			Enum.Material.Wood,
			parent
		)
	end
	part(
		"Lona",
		Vector3.new(1.4, 0.06, 4.4),
		cf * CFrame.new(0, 0.38, 0),
		Color3.fromRGB(96, 104, 70),
		Enum.Material.Fabric,
		parent
	)
	part(
		"Ataduras",
		Vector3.new(0.9, 0.5, 0.6),
		cf * CFrame.new(1.6, 0.25, -1.6),
		Color3.fromRGB(226, 220, 204),
		Enum.Material.Fabric,
		parent
	)
end

local function lowTable(parent: Instance, cf: CFrame)
	part("Mesa", Vector3.new(2.6, 0.2, 1.6), cf * CFrame.new(0, 1.0, 0), WOOD, Enum.Material.Wood, parent)
	for _, o in { { 1.1, 0.6 }, { -1.1, 0.6 }, { 1.1, -0.6 }, { -1.1, -0.6 } } do
		part("Pe", Vector3.new(0.15, 0.9, 0.15), cf * CFrame.new(o[1], 0.45, o[2]), WOOD, Enum.Material.Wood, parent)
	end
	part(
		"Carta",
		Vector3.new(1.2, 0.02, 0.9),
		cf * CFrame.new(-0.4, 1.11, 0) * CFrame.Angles(0, 0.2, 0),
		Color3.fromRGB(214, 206, 180),
		Enum.Material.Fabric,
		parent
	)
end

local FURNITURE: { [string]: { (Instance, CFrame) -> () } } = {
	J1 = { mats, lowTable, stretcher }, -- posto de comando e enfermaria, sob o centro da vila
	J2 = { crates, sacks, crates }, -- depósito
	J3 = { stove, sacks, mats }, -- cozinha
}

-- Devolve (peças, lamparinas).
function MapLife.tunnels(map: Instance): (number, number)
	local folder = map:FindFirstChild("Tunnels")
	if not folder then
		return 0, 0
	end
	local life = Instance.new("Folder")
	life.Name = "TunnelLife"
	local W, H = Tunnels.WIDTH_M / M, Tunnels.HEIGHT_M / M
	local lamps = 0
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") and string.match(p.Name, "^Tunnel_%d+_floor$") then
			local len = p.Size.Z
			local base = p.CFrame * CFrame.new(0, p.Size.Y / 2, 0) -- piso, eixo da galeria em Z
			local k = 0
			local z = -len / 2 + 2.2 / M
			while z < len / 2 - 2 / M do
				k += 1
				local f = base * CFrame.new(0, 0, z)
				part(
					"Escora",
					Vector3.new(0.35, H, 0.35),
					f * CFrame.new(-(W / 2 - 0.2), H / 2, 0),
					WOOD,
					Enum.Material.Wood,
					life
				)
				part(
					"Escora",
					Vector3.new(0.35, H, 0.35),
					f * CFrame.new(W / 2 - 0.2, H / 2, 0),
					WOOD,
					Enum.Material.Wood,
					life
				)
				part("Escora", Vector3.new(W, 0.3, 0.4), f * CFrame.new(0, H - 0.15, 0), WOOD, Enum.Material.Wood, life)
				if k % 3 == 2 then
					local side = if k % 2 == 0 then 1 else -1
					lamp(life, f * CFrame.new(side * (W / 2 - 0.45), 2.0, 0.7))
					lamps += 1
				end
				z += 4 / M
			end
		end
	end
	for id, list in FURNITURE do
		local fl = folder:FindFirstChild("Chamber_" .. id .. "_floor") :: BasePart?
		if fl then
			local center = fl.CFrame * CFrame.new(0, fl.Size.Y / 2, 0)
			-- lamparina pendurada no meio da câmara: com as galerias ocupando os cantos, a J1 (4
			-- galerias) ficava sem luz nenhuma (Studio, 2026-11-11)
			local hang = center * CFrame.new(0.9, H - 0.45, 0.9)
			part("Cordao", Vector3.new(0.06, 0.9, 0.06), hang, Color3.fromRGB(60, 50, 40), Enum.Material.Fabric, life)
			lamp(life, hang * CFrame.new(0, -1.0, 0))
			lamps += 1
			local slots = MapLife.freeSlots(id, #list + 1)
			for i, ang in slots do
				local pos = center * CFrame.new(math.cos(ang) * 2.6, 0, math.sin(ang) * 2.6)
				local cf =
					CFrame.lookAt(pos.Position, center.Position * Vector3.new(1, 0, 1) + Vector3.new(0, pos.Y, 0))
				local f = list[i]
				if f then
					f(life, cf)
				else
					lamp(life, cf * CFrame.new(0, 2.0, 0.6))
					lamps += 1
				end
			end
		end
	end
	life.Parent = map
	return #life:GetChildren(), lamps
end

---------------------------------------------------------------------------------------------
-- Vilas
---------------------------------------------------------------------------------------------

local function smoke(parent: Instance, pos: Vector3)
	local src = part(
		"Fumaca",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(pos),
		Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic,
		parent
	)
	src.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Rate = 4
	e.Lifetime = NumberRange.new(7, 11)
	e.Speed = NumberRange.new(1.5, 2.5)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0.5, 0.35, 0.3) -- brisa do mar (leste) e subida lenta
	e.Drag = 0.3
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 9) })
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.6, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Color3.fromRGB(196, 192, 184), Color3.fromRGB(170, 168, 162))
	e.LightInfluence = 1
	e.RotSpeed = NumberRange.new(-15, 15)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = src
end

local function jar(parent: Instance, x: number, y: number, z: number, s: number)
	local m = Instance.new("Model")
	m.Name = "PoteDagua"
	local d = 2.3 * s
	local body = part(
		"Pote",
		Vector3.new(d, d, d),
		CFrame.new(x, y + d * 0.42, z),
		CLAY,
		Enum.Material.Slate,
		m,
		Enum.PartType.Ball
	)
	body.CanCollide = true
	body.CanQuery = true
	local neck = part(
		"Boca",
		Vector3.new(0.45 * s, 1.5 * s, 1.5 * s),
		CFrame.new(x, y + d * 0.88, z) * UPRIGHT,
		CLAY_DARK,
		Enum.Material.Slate,
		m,
		Enum.PartType.Cylinder
	)
	neck.CanCollide = true
	neck.CanQuery = true
	part(
		"Agua",
		Vector3.new(0.05, 1.2 * s, 1.2 * s),
		CFrame.new(x, y + d * 0.88 + 0.2 * s, z) * UPRIGHT,
		Color3.fromRGB(58, 66, 58),
		Enum.Material.Glass,
		m,
		Enum.PartType.Cylinder
	)
	m.Parent = parent
end

local function strawStack(parent: Instance, x: number, y: number, z: number, s: number)
	-- meda de palha do arroz em volta de um mastro (a debulha é no quintal)
	-- domo (bola meio enterrada) e dois capuzes menores; em degraus de cilindro parecia um bolo
	-- (Studio, 2026-11-11)
	local m = Instance.new("Model")
	m.Name = "MedaDePalha"
	local top = y
	for _, t in { { 6.4, 0.55 }, { 4.2, 2.6 }, { 2.4, 4.2 } } do
		local d = t[1] * s
		local cy = y + t[2] * s
		local p =
			part("Palha", Vector3.new(d, d, d), CFrame.new(x, cy, z), STRAW, Enum.Material.Grass, m, Enum.PartType.Ball)
		p.CanCollide = true
		p.CanQuery = true
		p:SetAttribute("Material", "Thatch") -- bala passa como no telhado de palha (CombatService)
		top = cy + d / 2
	end
	part(
		"Mastro",
		Vector3.new(0.25, top - y + 1.2, 0.25),
		CFrame.new(x, (y + top + 1.2) / 2, z),
		BAMBOO,
		Enum.Material.Wood,
		m
	)
	m.Parent = parent
end

local function firewood(parent: Instance, cf: CFrame)
	local m = Instance.new("Model")
	m.Name = "Lenha"
	for k = 0, 5 do
		local row = if k < 3 then 0 else 1
		local x = (k % 3) * 0.55 - 0.55 + row * 0.27
		local p = part(
			"Tora",
			Vector3.new(3.2, 0.5, 0.5),
			cf * CFrame.new(x, 0.25 + row * 0.45, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Color3.fromRGB(104, 78, 52),
			Enum.Material.Wood,
			m,
			Enum.PartType.Cylinder
		)
		p.CanCollide = true
		p.CanQuery = true
	end
	m.Parent = parent
end

-- houses: modelos das casas já postas. groundAt: altura do terreno (studs) ou nil.
-- isPaddy: o ponto cai no arrozal (a meda e o pote não vão para dentro d'água).
function MapLife.village(
	houses: { Model },
	out: Instance,
	rng: Rng.Rng,
	groundAt: (number, number) -> number?,
	isPaddy: (number, number) -> boolean
): { [string]: number }
	local count = { smoke = 0, jars = 0, straw = 0, wood = 0 }
	local fx = Instance.new("Folder")
	fx.Name = "VidaDaVila"
	for _, h in houses do
		local cf, size = h:GetBoundingBox()
		local kitchen = h.Name == "hut_kitchen"
		if kitchen or rng:next() < 0.22 then
			smoke(fx, (cf * CFrame.new(size.X * 0.2, size.Y / 2 - 0.4, -size.Z * 0.15)).Position)
			count.smoke += 1
		end
		if rng:next() < 0.55 then
			local side = if rng:next() < 0.5 then 1 else -1
			for k = 0, (if rng:next() < 0.4 then 1 else 0) do
				local p = cf * Vector3.new(side * (size.X / 2 + 2.6), 0, size.Z * 0.25 - k * 2.8)
				local y = groundAt(p.X, p.Z)
				if y and not isPaddy(p.X, p.Z) then
					jar(out, p.X, y, p.Z, rng:range(0.85, 1.1))
					count.jars += 1
				end
			end
		end
		if rng:next() < 0.3 then
			local a = rng:range(0, 2 * math.pi)
			local r = math.max(size.X, size.Z) / 2 + rng:range(5, 9) / M -- terreiro a 5–9 m da casa
			local x, z = cf.X + math.cos(a) * r, cf.Z + math.sin(a) * r
			local y = groundAt(x, z)
			if y and not isPaddy(x, z) then
				strawStack(out, x, y, z, rng:range(0.85, 1.2))
				count.straw += 1
			end
		end
		if kitchen or rng:next() < 0.15 then
			local p = cf * Vector3.new(-(size.X / 2 + 1.4), 0, -size.Z * 0.2)
			local y = groundAt(p.X, p.Z)
			if y then
				firewood(out, CFrame.new(p.X, y, p.Z) * (cf - cf.Position))
				count.wood += 1
			end
		end
	end
	fx.Parent = out
	return count
end

return MapLife
