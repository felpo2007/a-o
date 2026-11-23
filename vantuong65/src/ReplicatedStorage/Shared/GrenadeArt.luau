--!strict
-- Granada desenhada em peças (D-77), montada no cliente sobre o núcleo de colisão do servidor
-- (FieldService). O núcleo tem 1 stud: bola menor que ~0,5 stud atravessa o terreno do Roblox
-- (teste no Studio, 2026-11-11: bola de 0,25 caiu a -166, de 0,5 afundou 25 studs, de 1 parou).
-- - M26 dos EUA: corpo de limão verde-oliva (5,7 x 9,9 cm com a espoleta M204), espoleta, alavanca,
--   pino e argola;
-- - granada de cabo do VC (modelo chinês): cabeça de ferro de 5,5 x 9 cm, cabo de madeira de 16 cm,
--   tampa de rosca no fim do cabo e, dentro, o cordão com a conta de porcelana;
-- - fumaça M18: lata de 6,35 x 11,4 cm com a ponta clara e a espoleta por cima (14 cm ao todo).
-- 2026-11-13 ("copie a granada de fumaça igual ao Front 44"): as peças seguem o GrenadeModels do
-- Front 44 (espoleta com corpo e tampa, alavanca colada no corpo, pino atravessado e argola de 10
-- elos; na de cabo, a tampa, o cordão e a conta). Duas montagens:
-- - GrenadeArt.build: a granada lançada (sem pino e sem alavanca, que saltam na mão), com o centro
--   de massa na peça "Centro" (o núcleo do servidor fica nele);
-- - GrenadeArt.hand: a granada na mão (1ª pessoa no ItemView, 3ª pessoa no ArmaNaMao), com o pivô na
--   pegada (peça "Pega"), +Y para a espoleta (ou a cabeça), e o pino/argola nas peças "Pino*".
-- Medidas em cm (como no Front 44), convertidas para studs (0,28 m).
local GrenadeArt = {}

local M = 0.28
local CM = 1 / 100 / M -- studs por cm
local OLIVE = Color3.fromRGB(74, 80, 48)
local OLIVE_DARK = Color3.fromRGB(58, 64, 40)
local IRON = Color3.fromRGB(58, 58, 54)
local STEEL = Color3.fromRGB(70, 72, 70)
local BRASS = Color3.fromRGB(150, 138, 104)
local WOOD = Color3.fromRGB(130, 96, 60)
local TOP = Color3.fromRGB(196, 196, 186) -- ponta da lata da fumaça
local PORCELAIN = Color3.fromRGB(236, 234, 228)

type Spec = {
	name: string,
	shape: string, -- "cyl" (eixo em pé) | "egg" | "block"
	size: Vector3, -- cm (cilindro: comprimento, diâmetro, diâmetro)
	cf: CFrame, -- cm
	color: Color3,
	mat: Enum.Material,
	pin: boolean?, -- sai antes do arremesso (pino, argola, tampa, cordão, conta)
	spoon: boolean?, -- alavanca: salta quando a granada sai da mão
}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cilindro do Roblox (eixo X) de pé

local function cyl(
	list: { Spec },
	name: string,
	d: number,
	len: number,
	y: number,
	color: Color3,
	mat: Enum.Material?
): Spec
	local s: Spec = {
		name = name,
		shape = "cyl",
		size = Vector3.new(len, d, d),
		cf = CFrame.new(0, y, 0) * VERTICAL,
		color = color,
		mat = mat or Enum.Material.Metal,
	}
	table.insert(list, s)
	return s
end

local function block(list: { Spec }, name: string, size: Vector3, cf: CFrame, color: Color3): Spec
	local s: Spec = { name = name, shape = "block", size = size, cf = cf, color = color, mat = Enum.Material.Metal }
	table.insert(list, s)
	return s
end

-- Espoleta com alavanca, pino e argola no topo (y = top) de um corpo de raio radiusAt(y) (Front 44).
local function fuze(list: { Spec }, top: number, radiusAt: (number) -> number)
	cyl(list, "Espoleta", 1.9, 1.7, top + 0.75, STEEL)
	cyl(list, "EspoletaTampa", 1.35, 0.9, top + 1.9, STEEL)
	-- alavanca: lâmina que desce colada no corpo pelo lado direito
	local upper = Vector3.new(1.1, top + 1.6, 0)
	local lowerY = top - 4.4
	local lower = Vector3.new(radiusAt(lowerY) + 0.35, lowerY, 0)
	local axis = upper - lower
	local sp = block(
		list,
		"Alavanca",
		Vector3.new(0.3, axis.Magnitude, 1.35),
		CFrame.new((upper + lower) * 0.5) * CFrame.Angles(0, 0, math.atan2(-axis.X, axis.Y)),
		STEEL
	)
	sp.spoon = true
	-- pino atravessado e argola pendurada do lado esquerdo (a mão esquerda puxa)
	local shaft: Spec = {
		name = "PinoHaste",
		shape = "cyl",
		size = Vector3.new(2.6, 0.28, 0.28),
		cf = CFrame.new(-0.6, top + 1.0, 0),
		color = BRASS,
		mat = Enum.Material.Metal,
		pin = true,
	}
	table.insert(list, shaft)
	local center = Vector3.new(-2.75, top + 0.5, 0)
	for i = 0, 9 do
		local t = i / 10 * math.pi * 2
		local pos = center + Vector3.new(math.cos(t), math.sin(t), 0) * 1.15
		local tangent = Vector3.new(-math.sin(t), math.cos(t), 0)
		local e = block(
			list,
			"PinoArgola",
			Vector3.new(0.78, 0.24, 0.24),
			CFrame.fromMatrix(pos, tangent, Vector3.zAxis),
			BRASS
		)
		e.pin = true
	end
end

-- M26: corpo de limão (5,7 cm, 7,4 cm de corpo) e a espoleta por cima: 9,9 cm ao todo
local function m26(): ({ Spec }, Vector3, number)
	local list: { Spec } = {}
	local rx, ry = 2.85, 3.7
	local function radiusAt(y: number): number
		return rx * math.sqrt(math.max(0, 1 - (y / ry) ^ 2))
	end
	table.insert(list, {
		name = "Corpo",
		shape = "egg",
		size = Vector3.new(rx * 2, ry * 2, rx * 2),
		cf = CFrame.identity,
		color = OLIVE,
		mat = Enum.Material.Metal,
	})
	cyl(list, "Base", 1.4, 0.5, -ry + 0.1, OLIVE_DARK)
	fuze(list, ry, radiusAt)
	return list, Vector3.zero, rx
end

-- M18: lata de 6,35 cm por 11,4 cm, ponta clara, espoleta M201A1 por cima
local function m18(): ({ Spec }, Vector3, number)
	local list: { Spec } = {}
	local r = 3.175
	local function radiusAt(_: number): number
		return r
	end
	cyl(list, "Lata", r * 2, 11.4, 0.5, OLIVE)
	cyl(list, "Ponta", r * 2 + 0.1, 0.6, 5.95, TOP)
	cyl(list, "Fundo", r * 2 + 0.15, 0.5, -4.95, OLIVE_DARK)
	fuze(list, 6.25, radiusAt)
	return list, Vector3.new(0, 0.5, 0), r
end

-- Granada de cabo chinesa: pegada a 5 cm do fim do cabo de 16 cm; cabeça de 5,5 x 9 cm
local function stick(): ({ Spec }, Vector3, number)
	local list: { Spec } = {}
	local bottom = -5
	local top = bottom + 16
	cyl(list, "Cabo", 2.6, 16, (bottom + top) * 0.5, WOOD, Enum.Material.Wood)
	cyl(list, "Virola", 3.0, 1.5, top - 0.5, IRON)
	cyl(list, "Cabeca", 5.5, 9, top + 4.5, IRON)
	cyl(list, "CabecaBase", 5.8, 0.5, top + 0.25, IRON)
	cyl(list, "CabecaTopo", 5.3, 0.5, top + 9.1, IRON)
	-- tampa de rosca no fim do cabo; dentro, o cordão e a conta (aparecem ao puxar)
	local cap = cyl(list, "PinoTampa", 2.9, 1.2, bottom - 0.5, IRON)
	cap.pin = true
	local cord = cyl(list, "PinoCordao", 0.2, 3.0, bottom + 1.4, PORCELAIN, Enum.Material.Fabric)
	cord.pin = true
	table.insert(list, {
		name = "PinoConta",
		shape = "egg",
		size = Vector3.new(1.1, 1.1, 1.1),
		cf = CFrame.new(0, bottom + 3.1, 0),
		color = PORCELAIN,
		mat = Enum.Material.SmoothPlastic,
		pin = true,
	})
	return list, Vector3.new(0, top + 3, 0), 2.75
end

-- peças, centro de massa (cm) e raio de apoio (cm)
local function specs(kind: string, faction: string?): ({ Spec }, Vector3, number)
	if kind == "smoke" then
		return m18()
	elseif faction == "VC" then
		return stick()
	end
	return m26()
end

local function makePart(s: Spec, parent: Instance, origin: CFrame): BasePart
	local p = Instance.new("Part")
	p.Name = s.name
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	p.Massless = true
	p.Material = s.mat
	p.Color = s.color
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Size = s.size * CM
	if s.shape == "cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif s.shape == "egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.CFrame = origin * (s.cf.Rotation + s.cf.Position * CM)
	p.Parent = parent
	return p
end

local function root(name: string, cf: CFrame, parent: Model): BasePart
	local c = Instance.new("Part")
	c.Name = name
	c.Size = Vector3.one * 0.05
	c.Transparency = 1
	c.Anchored = true
	c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = false, false, false, false
	c.Massless = true
	c.CFrame = cf
	c.Parent = parent
	parent.PrimaryPart = c
	return c
end

-- Granada lançada. Devolve o modelo (peças ancoradas, sem colisão; PrimaryPart "Centro" no centro de
-- massa) e o raio de apoio (studs): quanto o centro fica acima do chão com a granada deitada.
function GrenadeArt.build(kind: string, faction: string?): (Model, number)
	local list, center, r = specs(kind, faction)
	local m = Instance.new("Model")
	m.Name = "GranadaVisual"
	root("Centro", CFrame.identity, m)
	local origin = CFrame.new(-center * CM)
	for _, s in list do
		if not (s.pin or s.spoon) then
			makePart(s, m, origin)
		end
	end
	return m, r * CM
end

-- Granada na mão: pivô na pegada ("Pega"), +Y para a espoleta/cabeça. As peças do pino têm o nome
-- começando por "Pino" (somem quando o pino sai); a alavanca é "Alavanca".
function GrenadeArt.hand(kind: string, faction: string?): Model
	local list = specs(kind, faction)
	local m = Instance.new("Model")
	m.Name = "GranadaMao"
	root("Pega", CFrame.identity, m)
	for _, s in list do
		makePart(s, m, CFrame.identity)
	end
	return m
end

-- Altura da granada na mão (cm, da pegada ao topo): para a mão de 1ª pessoa segurar no lugar certo.
function GrenadeArt.top(kind: string, faction: string?): number
	local list = specs(kind, faction)
	local best = 0
	for _, s in list do
		local half = if s.shape == "cyl" then s.size.X / 2 else s.size.Y / 2
		best = math.max(best, s.cf.Position.Y + half)
	end
	return best
end

-- Medidas puras (teste): peças, centro e raio em cm.
GrenadeArt.specs = specs

return GrenadeArt
