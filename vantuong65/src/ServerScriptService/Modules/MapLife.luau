--!strict
-- Vida no mapa (D-74, pedido do dono: "dar vida ao mapa" com o arroz, os animais e os túneis).
-- - arrozal: dossel verde de cada tabuleiro plantado (o que se vê de longe) e os ladrilhos de
--   arroz para o cliente (RiceField.client cobre os tabuleiros perto da câmera);
-- - túneis: escoras de madeira a cada 4 m, lamparinas de barro e as três câmaras mobiliadas
--   (posto de comando e enfermaria, depósito, cozinha);
-- - vilas: fumaça de cozinha, potes d'água de barro, medas de palha e lenha.
-- Peças simples: baratas e fora do teto de triângulos do setor. Objetos do Blender (2026-11-11,
-- assets/blender): pote d'água, meda de palha, caixote e saco de arroz usam o modelo publicado
-- (place: AssetLoader.placeAt, que conta no teto do setor) e voltam para as peças com ID 0; varal e
-- chapéu cônico só existem como modelo.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RiceField = require(ReplicatedStorage.Shared.RiceField)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Tunnels = require(ReplicatedStorage.Shared.Tunnels) :: any

local MapLife = {}
local M = 0.28
MapLife.LAMP_TAG = "VT65Lamp" -- o cliente faz a chama tremer (RiceField.client)
local RICE_KEYS: { [string]: string } = { hi = "rice_tile_hi", lo = "rice_tile_lo" }
-- Varal de bambu e chapéu cônico (nón lá) nas vilas, com moderação (proporção de projeto)
MapLife.CLOTHESLINE_P = 0.12
MapLife.HAT_P = 0.15

-- Coloca um modelo publicado com o meio da base em cf (AssetLoader.placeAt); nil = sem modelo
export type PlaceAt = (key: string, cf: CFrame, parent: Instance, scale: number?) -> Model?

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

-- Animais em partes (D-77) para o cliente animar o andar (AnimalVisuals): o modelo de cada
-- espécie vai para ReplicatedStorage.VT65AnimalArt com o nome da espécie. Devolve quantos.
function MapLife.animalArt(template: (string) -> Model?): number
	local art = Instance.new("Folder")
	art.Name = "VT65AnimalArt"
	local n = 0
	for _, species in { "water_buffalo", "chicken" } do
		-- D-79: com esqueleto e pele (Blender) quando publicado; senão, em partes (D-77)
		local tpl = template(species .. "_skin") or template(species .. "_rig")
		if tpl then
			local c = tpl:Clone()
			c.Name = species
			for _, d in c:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanTouch = false
					d.CanQuery = false
					d.CastShadow = species == "water_buffalo"
				end
			end
			c.Parent = art
			n += 1
		end
	end
	art.Parent = ReplicatedStorage
	return n
end

---------------------------------------------------------------------------------------------
-- Riacho
---------------------------------------------------------------------------------------------

-- Lugar da ponte de toras: a célula de riacho (classe 5) mais perto de (x, z), até `radius` studs,
-- e o giro que deixa o X do modelo (o comprimento da ponte) atravessado no leito: perpendicular ao
-- rumo do riacho medido nas células a até 12 m. nil se não houver riacho perto.
function MapLife.bridgeSpot(world: any, x: number, z: number, radius: number): (number?, number?, number?)
	local g = world.grid
	local cell = g.cellStuds
	local best, bx, bz = math.huge, nil :: number?, nil :: number?
	local n = math.ceil(radius / cell)
	local c0 = math.floor((x - g.originX) / cell)
	local r0 = math.floor((z - g.originZ) / cell)
	for dr = -n, n do
		for dc = -n, n do
			local cx = g.originX + (c0 + dc + 0.5) * cell
			local cz = g.originZ + (r0 + dr + 0.5) * cell
			local d = (cx - x) ^ 2 + (cz - z) ^ 2
			if d < best and d <= radius * radius and world:classAt(cx, cz) == 5 then
				best, bx, bz = d, cx, cz
			end
		end
	end
	if not (bx and bz) then
		return nil, nil, nil
	end
	-- rumo do leito: eixo principal das células de riacho em volta
	local reach = 12 / M
	local k = math.ceil(reach / cell)
	local pts: { Vector3 } = {}
	local mx, mz = 0, 0
	local bc = math.floor((bx - g.originX) / cell)
	local br = math.floor((bz - g.originZ) / cell)
	for dr = -k, k do
		for dc = -k, k do
			local cx = g.originX + (bc + dc + 0.5) * cell
			local cz = g.originZ + (br + dr + 0.5) * cell
			if (cx - bx) ^ 2 + (cz - bz) ^ 2 <= reach * reach and world:classAt(cx, cz) == 5 then
				table.insert(pts, Vector3.new(cx, 0, cz))
				mx += cx
				mz += cz
			end
		end
	end
	mx, mz = mx / #pts, mz / #pts
	local sxx, szz, sxz = 0, 0, 0
	for _, p in pts do
		local dx, dz = p.X - mx, p.Z - mz
		sxx += dx * dx
		szz += dz * dz
		sxz += dx * dz
	end
	local along = 0.5 * math.atan2(2 * sxz, sxx - szz) -- ângulo do eixo principal no plano XZ
	local ax, az = math.cos(along), math.sin(along)
	local px, pz = -az, ax -- atravessado no leito
	return bx, bz, math.atan2(-pz, px)
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

-- Modelo do Blender (AssetLoader.placeAt) da vez: tunnels() e village() guardam aqui o que recebem
local placeModel: PlaceAt? = nil
local modelCount = 0

-- Modelo publicado com o meio da base em `base`; sem ele, a peça de antes (centro em `center`).
local function boxOr(
	key: string,
	base: CFrame,
	scale: number,
	parent: Instance,
	name: string,
	size: Vector3,
	center: CFrame,
	color: Color3,
	material: Enum.Material
)
	local place = placeModel
	if place and place(key, base, parent, scale) then
		modelCount += 1
		return
	end
	part(name, size, center, color, material, parent)
end

local function crates(parent: Instance, cf: CFrame)
	-- caixote de munição de 0,63 x 0,33 x 0,34 m (ammo_crate); as peças tinham 0,56 x 0,31 x 0,34 m
	local W, PL = CRATE, Enum.Material.WoodPlanks
	boxOr("ammo_crate", cf, 1, parent, "Caixote", Vector3.new(2.0, 1.1, 1.2), cf * CFrame.new(0, 0.55, 0), W, PL)
	local top = cf * CFrame.new(0.2, 1.1, 0.05) * CFrame.Angles(0, 0.1, 0)
	boxOr("ammo_crate", top, 1, parent, "Caixote", Vector3.new(2.0, 1.1, 1.2), top * CFrame.new(0, 0.55, 0), W, PL)
	local small = cf * CFrame.new(0, 0, 1.3)
	boxOr(
		"ammo_crate",
		small,
		0.72,
		parent,
		"Caixote",
		Vector3.new(1.4, 0.8, 1.0),
		small * CFrame.new(0, 0.4, 0),
		W,
		PL
	)
end

local function sacks(parent: Instance, cf: CFrame)
	for k = 0, 3 do
		local x, y = (k % 2) * 1.3 - 0.65, if k < 2 then 0 else 0.75
		local base = cf * CFrame.new(x, y, 0) * CFrame.Angles(0, k * 0.2, 0)
		-- saco de 0,47 x 0,20 x 0,35 m deitado (rice_sack): comprido em X; a peça era comprida em Z
		boxOr(
			"rice_sack",
			base * CFrame.Angles(0, math.pi / 2, 0),
			1,
			parent,
			"SacoDeArroz",
			Vector3.new(1.2, 0.9, 1.6),
			base * CFrame.new(0, 0.45, 0),
			SACK,
			Enum.Material.Fabric
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

-- Devolve (peças, lamparinas). place: AssetLoader.placeAt (caixote e saco de arroz em modelo).
function MapLife.tunnels(map: Instance, place: PlaceAt?): (number, number)
	local folder = map:FindFirstChild("Tunnels")
	if not folder then
		return 0, 0
	end
	placeModel = place
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
	placeModel = nil
	life.Parent = map
	return #life:GetChildren(), lamps
end

---------------------------------------------------------------------------------------------
-- Vilas
---------------------------------------------------------------------------------------------

local function smoke(parent: Instance, pos: Vector3): Part
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
	e:SetAttribute("BaseRate", e.Rate) -- o Ambiente.client reduz a partir disto (detalhe)
	e.Parent = src
	return src
end

local function jar(parent: Instance, x: number, y: number, z: number, s: number, yaw: number)
	-- pote de barro (chum) com tampa de tábuas e cuia: 0,76 x 0,79 x 0,60 m (water_jar)
	local place = placeModel
	if place and place("water_jar", CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), parent, s) then
		modelCount += 1
		return
	end
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

local function strawStack(parent: Instance, x: number, y: number, z: number, s: number, yaw: number)
	-- meda de palha do arroz em volta de um mastro (a debulha é no quintal)
	-- modelo do Blender (straw_stack, 2,05 x 2,84 x 2,04 m) ou, sem ele, o domo (bola meio
	-- enterrada) e dois capuzes menores; em degraus de cilindro parecia um bolo (Studio, 2026-11-11)
	local place = placeModel
	local pm = if place then place("straw_stack", CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), parent, s) else nil
	if pm then
		modelCount += 1
		for _, d in pm:GetDescendants() do
			if d:IsA("BasePart") then
				d:SetAttribute("Material", "Thatch") -- bala passa como no telhado de palha (CombatService)
			end
		end
		return
	end
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

---------------------------------------------------------------------------------------------
-- Vila grande do centro (2026-11-12, Data/Village): varanda, horta, pagode (chùa), casa comunal
-- (đình) e banca do mercado, em peças. O plano (ArtPlan.structures) dá o centro da base, o giro e a
-- pegada; a frente (porta) fica no -Z local. Porta com vão livre de DOOR_CLEAR_M (pedido do dono:
-- pelo menos 2,1 m, o soldado tem 2,0 m). Medidas de projeto (PLACEHOLDER) até os modelos do Blender.
---------------------------------------------------------------------------------------------
MapLife.DOOR_CLEAR_M = 2.4
local TILE = Color3.fromRGB(146, 72, 50) -- telha de barro
local PLASTER = Color3.fromRGB(206, 192, 160) -- parede caiada, encardida
local STONE = Color3.fromRGB(124, 116, 100)
local THATCH = Color3.fromRGB(156, 138, 90)
local LEAF = Color3.fromRGB(70, 104, 46)
local EARTH = Color3.fromRGB(104, 82, 58)

-- peça sólida (colisão, raio e sombra) com o material de penetração (CombatService)
local function solid(p: Part, mat: string?): Part
	p.CanCollide = true
	p.CanQuery = true
	p.CastShadow = true
	if mat then
		p:SetAttribute("Material", mat)
	end
	return p
end

-- telhado de duas águas: dois WedgeParts com a cumeeira no meio (ao longo do X local)
local function roof(m: Model, cf: CFrame, len: number, width: number, h: number, color: Color3, mat: string)
	for _, sgn in { -1, 1 } do
		local r = Instance.new("WedgePart")
		r.Name = "Telhado"
		r.Anchored = true
		r.Size = Vector3.new(len, h, width / 2)
		r.CFrame = cf * CFrame.new(0, h / 2, sgn * width / 4) * CFrame.Angles(0, if sgn > 0 then math.pi else 0, 0)
		r.Color = color
		r.Material = if mat == "Thatch" then Enum.Material.Grass else Enum.Material.Slate
		r.TopSurface = Enum.SurfaceType.Smooth
		r.BottomSurface = Enum.SurfaceType.Smooth
		r.CanCollide = true
		r.CanQuery = true
		r.CanTouch = false
		r:SetAttribute("Material", mat)
		r.Parent = m
	end
end

-- parede ao longo do X local de comprimento len, com um vão de largura gap no meio (gap 0: inteira)
local function wall(m: Model, cf: CFrame, len: number, h: number, t: number, gap: number, gapH: number)
	if gap <= 0 then
		solid(
			part("Parede", Vector3.new(len, h, t), cf * CFrame.new(0, h / 2, 0), PLASTER, Enum.Material.Plaster, m),
			"MudWall"
		)
		return
	end
	local side = (len - gap) / 2
	for _, sgn in { -1, 1 } do
		solid(
			part(
				"Parede",
				Vector3.new(side, h, t),
				cf * CFrame.new(sgn * (gap / 2 + side / 2), h / 2, 0),
				PLASTER,
				Enum.Material.Plaster,
				m
			),
			"MudWall"
		)
	end
	if h > gapH then
		solid(
			part(
				"Verga",
				Vector3.new(gap, h - gapH, t),
				cf * CFrame.new(0, gapH + (h - gapH) / 2, 0),
				PLASTER,
				Enum.Material.Plaster,
				m
			),
			"MudWall"
		)
	end
end

local function post(m: Model, cf: CFrame, h: number, d: number, color: Color3)
	solid(part("Esteio", Vector3.new(d, h, d), cf * CFrame.new(0, h / 2, 0), color, Enum.Material.Wood, m), "Wood")
end

-- kind: "varanda" | "horta" | "chua" | "dinh" | "banca"; cf: centro da base (no chão), giro da peça;
-- w, d: pegada (studs). Devolve o modelo (já no parent).
function MapLife.villagePart(kind: string, parent: Instance, cf: CFrame, w: number, d: number): Model
	local m = Instance.new("Model")
	m.Name = "Vila_" .. kind
	local door = MapLife.DOOR_CLEAR_M / M
	if kind == "varanda" then
		-- alpendre de palha na frente da casa: esteios de bambu na beira e telhado inclinado
		local h = 2.5 / M
		for _, k in { -1, 0, 1 } do
			post(m, cf * CFrame.new(k * (w / 2 - 0.3 / M), 0, -d / 2), h, 0.14 / M, BAMBOO)
		end
		local slab = part(
			"Alpendre",
			Vector3.new(w, 0.15 / M, d + 0.5 / M),
			cf * CFrame.new(0, h + 0.2 / M, 0),
			THATCH,
			Enum.Material.Grass,
			m
		)
		slab.CFrame = slab.CFrame * CFrame.Angles(math.rad(-8), 0, 0)
		solid(slab, "Thatch")
	elseif kind == "horta" then
		-- canteiro de hortaliça: terra fofa um palmo acima do chão e fileiras de folhas
		part("Canteiro", Vector3.new(w, 0.2 / M, d), cf * CFrame.new(0, 0.05 / M, 0), EARTH, Enum.Material.Ground, m)
		for k = 0, 3 do
			part(
				"Folhas",
				Vector3.new(w * 0.9, 0.2 / M, 0.25 / M),
				cf * CFrame.new(0, 0.25 / M, (k - 1.5) * d / 4.5),
				LEAF,
				Enum.Material.LeafyGrass,
				m
			)
		end
	elseif kind == "banca" then
		-- banca do mercado: quatro esteios, cobertura de palha a 2,4 m e balcão
		local h = 2.4 / M
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				post(m, cf * CFrame.new(sx * (w / 2 - 0.1 / M), 0, sz * (d / 2 - 0.1 / M)), h, 0.12 / M, BAMBOO)
			end
		end
		solid(
			part(
				"Cobertura",
				Vector3.new(w + 0.4 / M, 0.12 / M, d + 0.4 / M),
				cf * CFrame.new(0, h + 0.06 / M, 0),
				THATCH,
				Enum.Material.Grass,
				m
			),
			"Thatch"
		)
		solid(
			part(
				"Balcao",
				Vector3.new(w * 0.8, 0.8 / M, 0.7 / M),
				cf * CFrame.new(0, 0.4 / M, -d / 2 + 0.6 / M),
				WOOD,
				Enum.Material.Wood,
				m
			),
			"Wood"
		)
	elseif kind == "chua" then
		-- pagode da vila: base de pedra com dois degraus, salão caiado com porta larga na frente e janelas
		-- dos lados, telhado de telha em duas camadas e o altar no fundo
		local base = 0.4 / M
		solid(
			part("Base", Vector3.new(w, base, d), cf * CFrame.new(0, base / 2, 0), STONE, Enum.Material.Cobblestone, m),
			"Stone"
		)
		for k = 1, 2 do
			local sh = base * k / 3
			solid(
				part(
					"Degrau",
					Vector3.new(3.4 / M, sh, 0.35 / M),
					cf * CFrame.new(0, sh / 2, -d / 2 - (3 - k) * 0.35 / M),
					STONE,
					Enum.Material.Cobblestone,
					m
				),
				"Stone"
			)
		end
		local top = cf * CFrame.new(0, base, 0)
		local iw, id, wh, t = w - 4 / M, d - 4 / M, 3.4 / M, 0.3 / M
		wall(m, top * CFrame.new(0, 0, -id / 2), iw, wh, t, 2.4 / M, door)
		wall(m, top * CFrame.new(0, 0, id / 2), iw, wh, t, 0, 0)
		for _, sgn in { -1, 1 } do
			wall(m, top * CFrame.new(sgn * iw / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), id, wh, t, 1.2 / M, door)
		end
		roof(m, top * CFrame.new(0, wh, 0), iw + 1.6 / M, id + 2 / M, 2.0 / M, TILE, "Tile")
		roof(m, top * CFrame.new(0, wh + 2.0 / M, 0), iw * 0.55, id * 0.55, 1.6 / M, TILE, "Tile")
		solid(
			part(
				"Altar",
				Vector3.new(2.2 / M, 1.0 / M, 0.9 / M),
				top * CFrame.new(0, 0.5 / M, id / 2 - 1 / M),
				WOOD,
				Enum.Material.Wood,
				m
			),
			"Wood"
		)
	elseif kind == "dinh" then
		-- casa comunal: salão de esteios sobre assoalho de madeira (frente e lados abertos), parede no
		-- fundo e telhado grande de telha; três degraus na frente
		local floorH = 0.5 / M
		solid(
			part(
				"Assoalho",
				Vector3.new(w, floorH, d),
				cf * CFrame.new(0, floorH / 2, 0),
				WOOD,
				Enum.Material.WoodPlanks,
				m
			),
			"Wood"
		)
		for k = 1, 3 do
			local sh = floorH * k / 4
			solid(
				part(
					"Degrau",
					Vector3.new(4 / M, sh, 0.32 / M),
					cf * CFrame.new(0, sh / 2, -d / 2 - (4 - k) * 0.32 / M),
					WOOD,
					Enum.Material.WoodPlanks,
					m
				),
				"Wood"
			)
		end
		local top = cf * CFrame.new(0, floorH, 0)
		local ph = 3.2 / M
		for i = 0, 3 do
			for j = 0, 2 do
				local px = (i / 3 - 0.5) * (w - 1 / M)
				local pz = (j / 2 - 0.5) * (d - 1 / M)
				post(m, top * CFrame.new(px, 0, pz), ph, 0.32 / M, WOOD)
			end
		end
		wall(m, top * CFrame.new(0, 0, d / 2 - 0.5 / M), w - 1 / M, ph, 0.2 / M, 0, 0)
		roof(m, top * CFrame.new(0, ph, 0), w + 1.5 / M, d + 2 / M, 3.0 / M, TILE, "Tile")
	end
	m.Parent = parent
	return m
end

---------------------------------------------------------------------------------------------
-- Bases dos dois lados (2026-11-13; objetos do Blender, layouts em Data/Bases)
---------------------------------------------------------------------------------------------
-- Material de colisão que a bala atravessa perdendo energia (CombatService.PASS): a peça
-- Colisao_* dele fica consultável mesmo com a bala "passa" (a lona esconde, mas não segura o tiro).
local PASS_MATERIAL: { [string]: boolean } = { Bamboo = true, Thatch = true, Canvas = true }
-- GANCHOS DO STUDIO (o giro do importador, D-58, não dá para conferir fora dele):
-- cancela aberta a este ângulo em volta do pino (se baixar em vez de subir, troque o sinal)
MapLife.GATE_OPEN_DEG = 70
-- escada da torre: TrussPart invisível junto dos degraus (Colisao_Degrau*), caso o Humanoid não
-- suba pelos degraus de 0,30 m (false = só os degraus)
MapLife.TOWER_TRUSS = true
-- estacas punji: ferimento na perna de quem pisa (não o VC, que sabe onde elas estão), no máximo
-- um a cada PUNJI_COOLDOWN_S por pessoa. PLACEHOLDER de design (pequeno: o de um membro sem energia)
MapLife.PUNJI_COOLDOWN_S = 3
-- fumaça rala do fogão Hoàng Cầm (o duto espalha rente ao chão)
MapLife.KITCHEN_SMOKE_RATE = 1.2

-- Template de cada chave (uma vez; as cópias herdam): nós visuais sem colisão, consulta nem toque;
-- Colisao_* invisíveis, com colisão e o atributo Material (consulta só onde a bala para, ou no
-- material que ela atravessa perdendo energia); Zona_* só com toque. rules: Data/Bases.nodes[key].
-- rangeM: o alvo do estande (Silhueta e a colisão dela ganham o atributo RangeTarget).
function MapLife.baseTemplate(tpl: Model, rules: { [string]: any }?, rangeM: number?)
	for _, d in tpl:GetDescendants() do
		if d:IsA("BasePart") then
			local name = d.Name
			if string.sub(name, 1, 8) == "Colisao_" then
				local r = rules and rules[name]
				local stop = if r then r.stop == true else true
				local mat = if r and r.material ~= "" then r.material else "Wood"
				d.Transparency = 1
				d.CanCollide = true
				d.CastShadow = false
				d.CanTouch = false
				d.CanQuery = stop or PASS_MATERIAL[mat] == true
				d:SetAttribute("Material", mat)
				if rangeM then
					d:SetAttribute("RangeTarget", rangeM)
				end
			elseif string.sub(name, 1, 5) == "Zona_" then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = true
			else
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = rangeM ~= nil and name == "Silhueta"
				if d.CanQuery then
					d:SetAttribute("RangeTarget", rangeM)
				end
			end
		end
	end
end

local punjiLast: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local function punjiTouched(hit: BasePart)
	local char = hit:FindFirstAncestorWhichIsA("Model")
	if not char or char:GetAttribute("Faction") == nil or char:GetAttribute("Faction") == "VC" then
		return
	end
	local now = os.clock()
	if now - (punjiLast[char] or -math.huge) < MapLife.PUNJI_COOLDOWN_S then
		return
	end
	punjiLast[char] = now
	-- carregado aqui: o MedicalService não pode entrar no require do AssetLoader (ciclo)
	local MedicalService = require(script.Parent:WaitForChild("MedicalService")) :: any
	MedicalService.hit(char, "leg", 0, 1, nil)
end

-- Cada cópia posta (cf: o meio da base da caixa no chão, com o giro). it: o item do plano
-- (ArtPlan, com node = a placa que fica). extras: Data/Bases.extras[key].
function MapLife.baseInstance(model: Model, key: string, cf: CFrame, node: string?, extras: any?)
	-- placas de distância: fica só a do item (Placa25, Placa100…)
	if node then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and string.match(d.Name, "^Placa%d+$") and d.Name ~= node then
				d:Destroy()
			end
		end
	end
	-- cancela: gira em volta do pino (eixo do modelo), junto com a colisão dela
	if extras and extras.gatePivot then
		local p = extras.gatePivot
		local pivot = cf * CFrame.new(p[1], p[2], p[3])
		local a = math.rad(MapLife.GATE_OPEN_DEG)
		local turn = if extras.gateAxis == "X"
			then CFrame.Angles(a, 0, 0)
			elseif extras.gateAxis == "Y" then CFrame.Angles(0, a, 0)
			else CFrame.Angles(0, 0, a)
		local rot = pivot * turn * pivot:Inverse()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "Cancela" or d.Name == "Colisao_Cancela") then
				d.CFrame = rot * d.CFrame
			end
			-- o braço erguido e o garfo de apoio (poste fino) não seguram veículo: com eles, o vão
			-- entre o garfo e a cancela era de 10,8 studs e o M48 tem 13 (teste da v38); a guarita,
			-- o pilar e as placas continuam sólidos e dão o vão de 21,6 studs do portão
			if d:IsA("BasePart") and (d.Name == "Colisao_Cancela" or d.Name == "Colisao_Garfo") then
				d.CanCollide = false
			end
		end
	end
	-- fumaça rala da cozinha do VC: 3 saídas do duto (o Ambiente.client acha a peça "Fumaca" e reduz
	-- pelo detalhe a partir do BaseRate)
	if extras and extras.smoke then
		for _, p in extras.smoke do
			local src = smoke(model, (cf * CFrame.new(p[1], p[2], p[3])).Position)
			local e = src:FindFirstChildOfClass("ParticleEmitter")
			if e then
				e.Rate = MapLife.KITCHEN_SMOKE_RATE
				e:SetAttribute("BaseRate", MapLife.KITCHEN_SMOKE_RATE)
				e.Speed = NumberRange.new(0.3, 0.8) -- o fogão Hoàng Cầm solta a fumaça rente ao chão
				e.Acceleration = Vector3.new(0.6, 0.05, 0.3)
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 10) })
				e.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.75),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
		end
	end
	-- escada da torre: TrussPart invisível do pé ao alto dos degraus
	if key == "us_watchtower" and MapLife.TOWER_TRUSS then
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 14) == "Colisao_Degrau" then
				lo, hi = lo:Min(d.Position - d.Size / 2), hi:Max(d.Position + d.Size / 2)
			end
		end
		if lo.Y < hi.Y then
			local t = Instance.new("TrussPart")
			t.Name = "EscadaTruss"
			t.Anchored = true
			t.Transparency = 1
			t.CanQuery = false
			t.CastShadow = false
			t.Size = Vector3.new(2, math.max(2, math.floor((hi.Y - lo.Y) / 2 + 0.5) * 2), 2)
			local c = (lo + hi) / 2
			t.CFrame = CFrame.new(c.X, lo.Y + t.Size.Y / 2, c.Z) * (cf - cf.Position)
			t.Parent = model
		end
	end
	-- jirau da casa 09 (vila Xóm Gò): o Humanoid não sobe pela escada visual. TrussPart invisível do
	-- piso ao alto do jirau, encostada no lado dele que dá para o meio da casa (GANCHO DO STUDIO:
	-- conferir que fica na escada)
	if key == "vila_casa_09" then
		local loft = model:FindFirstChild("Colisao_gac", true)
		if loft and loft:IsA("BasePart") then
			local l = loft.CFrame:PointToObjectSpace(cf.Position)
			local sx, sz = loft.Size.X / 2, loft.Size.Z / 2
			-- o lado do jirau mais perto do meio da casa
			local off = if math.abs(l.X) / sx > math.abs(l.Z) / sz
				then Vector3.new(math.sign(l.X) * (sx + 1), 0, 0)
				else Vector3.new(0, 0, math.sign(l.Z) * (sz + 1))
			local top = loft.Position.Y + loft.Size.Y / 2
			local floor = cf.Position.Y + 0.54
			local h = math.max(2, math.floor((top - floor) / 2 + 0.5) * 2)
			local t = Instance.new("TrussPart")
			t.Name = "EscadaJirau"
			t.Anchored = true
			t.Transparency = 1
			t.CanQuery = false
			t.CastShadow = false
			t.Size = Vector3.new(2, h, 2)
			local p = loft.CFrame * off
			t.CFrame = CFrame.new(p.X, floor + h / 2, p.Z) * (loft.CFrame - loft.CFrame.Position)
			t.Parent = model
		end
	end
	-- estacas punji: o toque na zona fere quem não é do VC
	if key == "vc_punji" then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "Zona_" then
				d.Touched:Connect(punjiTouched)
			end
		end
	end
end

-- houses: modelos das casas já postas. groundAt: altura do terreno (studs) ou nil.
-- isPaddy: o ponto cai no arrozal (a meda e o pote não vão para dentro d'água).
-- place: AssetLoader.placeAt (pote, meda, varal e chapéu do Blender); sem ele, só as peças.
-- free (2026-11-12): o chão aceita o objeto de raio r (ArtPlan: fora da rua, do beco, da lâmina, do
-- patamar e das outras construções). Sem ele, vale só o arrozal.
function MapLife.village(
	houses: { Model },
	out: Instance,
	rng: Rng.Rng,
	groundAt: (number, number) -> number?,
	isPaddy: (number, number) -> boolean,
	place: PlaceAt?,
	free: ((number, number, number) -> boolean)?
): { [string]: number }
	local function ok(x: number, z: number, r: number): boolean
		return not isPaddy(x, z) and (free == nil or free(x, z, r))
	end
	placeModel = place
	modelCount = 0
	local count = { smoke = 0, jars = 0, straw = 0, wood = 0, lines = 0, hats = 0, models = 0 }
	local fx = Instance.new("Folder")
	fx.Name = "VidaDaVila"
	for _, h in houses do
		local cf, size = h:GetBoundingBox()
		local kitchen = h.Name == "hut_kitchen"
		local _, houseYaw, _ = cf:ToOrientation()
		if kitchen or rng:next() < 0.22 then
			smoke(fx, (cf * CFrame.new(size.X * 0.2, size.Y / 2 - 0.4, -size.Z * 0.15)).Position)
			count.smoke += 1
		end
		if rng:next() < 0.55 then
			local side = if rng:next() < 0.5 then 1 else -1
			for k = 0, (if rng:next() < 0.4 then 1 else 0) do
				local p = cf * Vector3.new(side * (size.X / 2 + 2.6), 0, size.Z * 0.25 - k * 2.8)
				local y = groundAt(p.X, p.Z)
				if y and ok(p.X, p.Z, 1.4) then
					jar(out, p.X, y, p.Z, rng:range(0.85, 1.1), rng:range(0, 2 * math.pi))
					count.jars += 1
				end
			end
		end
		if rng:next() < 0.3 then
			local a = rng:range(0, 2 * math.pi)
			local r = math.max(size.X, size.Z) / 2 + rng:range(5, 9) / M -- terreiro a 5–9 m da casa
			local x, z = cf.X + math.cos(a) * r, cf.Z + math.sin(a) * r
			local y = groundAt(x, z)
			if y and ok(x, z, 4) then
				strawStack(out, x, y, z, rng:range(0.85, 1.2), rng:range(0, 2 * math.pi))
				count.straw += 1
			end
		end
		-- varal de bambu no terreiro, paralelo à casa, 3–4 m para o lado (só o modelo)
		if place and rng:next() < MapLife.CLOTHESLINE_P then
			local side = if rng:next() < 0.5 then 1 else -1
			local p = cf * Vector3.new(0, 0, side * (size.Z / 2 + rng:range(3, 4) / M))
			local y = groundAt(p.X, p.Z)
			if y and ok(p.X, p.Z, 6) then
				if place("bamboo_clothesline", CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, houseYaw, 0), out) then
					count.lines += 1
					modelCount += 1
				end
			end
		end
		-- chapéu cônico (nón lá) largado no chão perto da porta (só o modelo)
		if place and rng:next() < MapLife.HAT_P then
			local p = cf * Vector3.new(size.X * rng:range(-0.3, 0.3), 0, -(size.Z / 2 + 1.2 / M))
			local y = groundAt(p.X, p.Z)
			if y and ok(p.X, p.Z, 1) then
				if
					place("conical_hat", CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, rng:range(0, 2 * math.pi), 0), out)
				then
					count.hats += 1
					modelCount += 1
				end
			end
		end
		if kitchen or rng:next() < 0.15 then
			local p = cf * Vector3.new(-(size.X / 2 + 1.4), 0, -size.Z * 0.2)
			local y = groundAt(p.X, p.Z)
			if y and (free == nil or free(p.X, p.Z, 2)) then
				firewood(out, CFrame.new(p.X, y, p.Z) * (cf - cf.Position))
				count.wood += 1
			end
		end
	end
	fx.Parent = out
	count.models = modelCount
	placeModel = nil
	return count
end

return MapLife
