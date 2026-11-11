--!strict
-- Granada desenhada em peças (D-77), montada no cliente sobre o núcleo de colisão do servidor
-- (FieldService). O núcleo tem 1 stud: bola menor que ~0,5 stud atravessa o terreno do Roblox
-- (teste no Studio, 2026-11-11: bola de 0,25 caiu a -166, de 0,5 afundou 25 studs, de 1 parou).
-- - M26 dos EUA: corpo de limão verde-oliva (5,7 x 9,9 cm), espoleta M204 e alavanca;
-- - granada de cabo do VC (modelo chinês): cabeça de ferro de 5,5 cm e cabo de madeira de 16 cm;
-- - fumaça M18: lata de 6 x 14,5 cm com a ponta clara.
local GrenadeArt = {}

local M = 0.28
local OLIVE = Color3.fromRGB(74, 80, 48)
local IRON = Color3.fromRGB(58, 58, 54)
local WOOD = Color3.fromRGB(130, 96, 60)

-- Devolve o modelo (peças ancoradas, sem colisão; PrimaryPart no centro) e o raio de apoio
-- (studs): quanto o centro fica acima do chão com a granada deitada.
function GrenadeArt.build(kind: string, faction: string?): (Model, number)
	local m = Instance.new("Model")
	m.Name = "GranadaVisual"
	local center = Instance.new("Part")
	center.Name = "Centro"
	center.Size = Vector3.one * 0.05
	center.Transparency = 1
	center.Anchored = true
	center.CanCollide, center.CanQuery, center.CanTouch, center.CastShadow = false, false, false, false
	center.Parent = m
	m.PrimaryPart = center
	local function bit(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: string?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		if shape == "cyl" then
			p.Shape = Enum.PartType.Cylinder
		elseif shape == "egg" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.CFrame = cf
		p.Parent = m
	end
	if kind == "smoke" then
		bit("Lata", Vector3.new(0.145, 0.06, 0.06) / M, CFrame.identity, OLIVE, Enum.Material.Metal, "cyl")
		bit(
			"Tampa",
			Vector3.new(0.012, 0.061, 0.061) / M,
			CFrame.new(0.07 / M, 0, 0),
			Color3.fromRGB(196, 196, 186),
			Enum.Material.Metal,
			"cyl"
		)
		return m, 0.03 / M
	elseif faction == "VC" then
		bit(
			"Cabeca",
			Vector3.new(0.09, 0.055, 0.055) / M,
			CFrame.new(-0.05 / M, 0, 0),
			IRON,
			Enum.Material.Metal,
			"cyl"
		)
		bit("Cabo", Vector3.new(0.16, 0.026, 0.026) / M, CFrame.new(0.075 / M, 0, 0), WOOD, Enum.Material.Wood, "cyl")
		bit("Tampa", Vector3.new(0.01, 0.03, 0.03) / M, CFrame.new(0.158 / M, 0, 0), IRON, Enum.Material.Metal, "cyl")
		return m, 0.0275 / M
	end
	bit("Corpo", Vector3.new(0.057, 0.085, 0.057) / M, CFrame.identity, OLIVE, Enum.Material.Metal, "egg")
	bit(
		"Espoleta",
		Vector3.new(0.022, 0.022, 0.022) / M,
		CFrame.new(0, 0.05 / M, 0) * CFrame.Angles(0, 0, math.pi / 2),
		IRON,
		Enum.Material.Metal,
		"cyl"
	)
	bit(
		"Alavanca",
		Vector3.new(0.008, 0.075, 0.016) / M,
		CFrame.new(0.032 / M, 0.012 / M, 0) * CFrame.Angles(0, 0, math.rad(-8)),
		IRON,
		Enum.Material.Metal
	)
	return m, 0.0285 / M
end

return GrenadeArt
