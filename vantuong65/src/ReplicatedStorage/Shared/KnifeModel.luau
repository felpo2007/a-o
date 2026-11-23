--!strict
-- Modelo da faca ou da baioneta (D-94), como o GunModel faz com as armas: o publicado (cópia que o
-- servidor põe em ReplicatedStorage.VT65KnifeArt, FieldService) ou, sem asset, um provisório de
-- peças com as medidas reais (Shared/Weapons.knives). Convenção: pivô no punho (onde a mão fecha),
-- ponta em −Z, fio em −Y. Attachments na peça principal: "Grip", "Guard", "Tip" e, nas baionetas,
-- "Ring" (anel de boca da M6) ou "Base" (articulação do espigão do Tipo 56).
-- Bainha (sheathed = true): a malha "Bainha" (com o cabo da faca embainhada), pivô na presilha.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(script.Parent.Weapons)

local KnifeModel = {}
local M = 0.28
local STEEL = Color3.fromRGB(62, 64, 60)
local EDGE = Color3.fromRGB(150, 152, 150)
local LEATHER = Color3.fromRGB(112, 72, 44)
local WOOD = Color3.fromRGB(92, 62, 40)
local RATTAN = Color3.fromRGB(196, 168, 112)

local function vec(t: { number }?): Vector3
	return if t then Vector3.new(t[1], t[2], t[3]) else Vector3.zero
end

-- arte publicada (Model com as MeshParts "Faca" e "Bainha"), se o servidor já a pôs
function KnifeModel.art(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("VT65KnifeArt")
	local m = folder and folder:FindFirstChild(id)
	return if m and m:IsA("Model") then m else nil
end

local function bare(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local function point(parent: BasePart, name: string, pos: Vector3)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = pos
	a.Parent = parent
end

local function piece(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material,
	shape: Enum.PartType?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	bare(p)
	p.Parent = model
	return p
end

-- Provisório de peças: lâmina (espinha + fio claro + ponta em cunha), guarda, cabo e pomo. Origem
-- no punho; as medidas são as da ficha (comprimento total e da lâmina).
local function buildParts(k: Weapons.Knife): Model
	local model = Instance.new("Model")
	model.Name = "Faca"
	local blade = k.bladeM / M
	local handle = (k.lengthM - k.bladeM) / M
	local spike = k.id == "type56"
	local h = (if k.id == "dao" then 0.05 elseif spike then 0.014 else 0.032) / M -- altura da lâmina
	local t = (if spike then 0.014 else 0.005) / M -- espessura
	local gripZ = handle * 0.45 -- punho a ~45% do cabo, a partir da guarda
	local zGuard = -gripZ -- guarda à frente do punho (−Z)
	local main = piece(
		model,
		"Lamina",
		Vector3.new(t, h, blade * 0.82),
		CFrame.new(0, 0, zGuard - blade * 0.41),
		STEEL,
		Enum.Material.Metal
	)
	if not spike then
		piece(
			model,
			"Fio",
			Vector3.new(t * 0.5, h * 0.22, blade * 0.82),
			CFrame.new(0, -h * 0.5, zGuard - blade * 0.41),
			EDGE,
			Enum.Material.Metal
		)
	end
	-- ponta: cunha com a quina para a frente (o fio embaixo)
	local tipLen = blade * 0.18
	local w = Instance.new("WedgePart")
	w.Name = "Ponta"
	w.Size = Vector3.new(t, h, tipLen)
	w.CFrame = CFrame.new(0, 0, zGuard - blade * 0.82 - tipLen / 2) * CFrame.Angles(0, math.pi, 0)
	w.Color = STEEL
	w.Material = Enum.Material.Metal
	bare(w)
	w.Parent = model
	if k.id ~= "dao" then
		piece(
			model,
			"Guarda",
			Vector3.new(0.012 / M, if spike then 0.03 / M else 0.075 / M, 0.008 / M),
			CFrame.new(0, 0, zGuard),
			STEEL,
			Enum.Material.Metal
		)
	end
	local handleColor = if k.id == "kabar" then LEATHER elseif k.id == "dao" then WOOD else Color3.fromRGB(28, 28, 28)
	piece(
		model,
		"Cabo",
		Vector3.new(handle, 0.03 / M, 0.03 / M),
		CFrame.new(0, 0, zGuard + handle / 2) * CFrame.Angles(0, math.pi / 2, 0),
		handleColor,
		if k.id == "kabar" then Enum.Material.Leather else Enum.Material.Wood,
		Enum.PartType.Cylinder
	)
	if k.id == "dao" then
		for i = 0, 2 do
			piece(
				model,
				"Rotim" .. i,
				Vector3.new(0.012 / M, 0.034 / M, 0.034 / M),
				CFrame.new(0, 0, zGuard + handle * (0.15 + 0.35 * i)) * CFrame.Angles(0, math.pi / 2, 0),
				RATTAN,
				Enum.Material.Fabric,
				Enum.PartType.Cylinder
			)
		end
	end
	piece(
		model,
		"Pomo",
		Vector3.new(0.022 / M, 0.03 / M, 0.012 / M),
		CFrame.new(0, 0, zGuard + handle),
		STEEL,
		Enum.Material.Metal
	)
	model.PrimaryPart = main
	local inv = main.CFrame:Inverse()
	point(main, "Grip", (inv * CFrame.identity).Position)
	point(main, "Guard", (inv * CFrame.new(0, 0, zGuard)).Position)
	point(main, "Tip", (inv * CFrame.new(0, -h * 0.25, zGuard - blade)).Position)
	if k.ring then
		point(main, "Ring", (inv * CFrame.new(0, h * 0.9, zGuard)).Position)
	end
	if k.base then
		point(main, "Base", (inv * CFrame.new(0, 0, zGuard + handle * 0.8)).Position)
	end
	main.PivotOffset = inv
	return model
end

-- Bainha provisória: estojo de couro (ou madeira) com o cabo para fora; pivô na presilha.
local function buildSheath(k: Weapons.Knife): Model
	local model = Instance.new("Model")
	model.Name = "Bainha"
	local blade = k.bladeM / M
	local handle = (k.lengthM - k.bladeM) / M
	local body = piece(
		model,
		"Estojo",
		Vector3.new(0.022 / M, (if k.id == "dao" then 0.07 else 0.05) / M, blade * 1.08),
		CFrame.new(0, 0, -blade * 0.54),
		if k.id == "dao" then RATTAN elseif k.id == "m6" then Color3.fromRGB(84, 88, 60) else LEATHER,
		if k.id == "dao" then Enum.Material.Wood else Enum.Material.Leather
	)
	piece(
		model,
		"Cabo",
		Vector3.new(handle, 0.03 / M, 0.03 / M),
		CFrame.new(0, 0, handle / 2) * CFrame.Angles(0, math.pi / 2, 0),
		if k.id == "kabar" then LEATHER elseif k.id == "dao" then WOOD else Color3.fromRGB(28, 28, 28),
		Enum.Material.Leather,
		Enum.PartType.Cylinder
	)
	model.PrimaryPart = body
	body.PivotOffset = body.CFrame:Inverse() -- presilha na boca
	return model
end

-- Cópia da MeshPart publicada, com os pontos medidos (escalados se o importador mudou o tamanho).
local function fromArt(art: Model, k: Weapons.Knife, sheathed: boolean): Model?
	local src = art:FindFirstChild(if sheathed then "Bainha" else "Faca", true)
	if not (src and src:IsA("BasePart")) then
		return nil
	end
	local p = src:Clone()
	bare(p)
	for _, c in p:GetChildren() do
		if c:IsA("Attachment") or c:IsA("JointInstance") or c:IsA("WeldConstraint") then
			c:Destroy()
		end
	end
	local model = Instance.new("Model")
	model.Name = if sheathed then "Bainha" else "Faca"
	p.Parent = model
	model.PrimaryPart = p
	if sheathed then
		local s = k.sheath
		if not s then
			model:Destroy()
			return nil
		end
		local scale = if s.size[3] > 0 then p.Size.Z / s.size[3] else 1
		point(p, "Loop", vec(s.loop) * scale)
		point(p, "Mouth", vec(s.mouth) * scale)
		p.PivotOffset = CFrame.new(vec(s.mouth) * scale)
		return model
	end
	local scale = if k.size[3] > 0 then p.Size.Z / k.size[3] else 1
	point(p, "Grip", vec(k.grip) * scale)
	point(p, "Guard", vec(k.guard) * scale)
	point(p, "Tip", vec(k.tip) * scale)
	if k.ring then
		point(p, "Ring", vec(k.ring) * scale)
	end
	if k.base then
		point(p, "Base", vec(k.base) * scale)
	end
	p.PivotOffset = CFrame.new(vec(k.grip) * scale)
	return model
end

-- Faca (ou bainha) pronta para soldar: peças soltas, sem colisão, sem consulta de raio, sem massa.
function KnifeModel.build(id: string, sheathed: boolean?): Model?
	local k = Weapons.knife(id)
	if not k then
		return nil
	end
	local art = KnifeModel.art(id)
	local m = if art then fromArt(art, k, sheathed == true) else nil
	if not m then
		m = if sheathed then buildSheath(k) else buildParts(k)
	end
	local out = m :: Model
	out:SetAttribute("KnifeId", id)
	out:SetAttribute("Art", art ~= nil)
	return out
end

-- Solda todas as peças na principal.
function KnifeModel.weld(model: Model)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = primary, d
			w.Parent = d
		end
	end
end

-- Ponto (no mundo) de um Attachment da faca, ou o pivô.
function KnifeModel.at(model: Model, name: string): Vector3
	local p = model.PrimaryPart
	local a = p and p:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.WorldPosition else model:GetPivot().Position
end

return KnifeModel
