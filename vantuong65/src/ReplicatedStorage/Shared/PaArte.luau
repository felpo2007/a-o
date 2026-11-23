--!strict
-- Pá de trincheira na mão (D-183, dono: "crie a pá no blender"). Monta a pá da 1ª pessoa
-- (Controllers/ItemView) e da 3ª pessoa (PostureController), com:
-- - a arte do Blender (tools/blender/novos.py): a M1943 dos EUA ou a cópia chinesa da MPL-50 do VC.
--   O servidor (FieldWorkService) copia os modelos publicados para ReplicatedStorage.VT65ItemArte;
-- - sem a arte (não chegou ou o ID é 0), a pá em peças de antes (ItemAnim.PROPS.pa).
-- O modelo tem a PrimaryPart "Pega" (invisível) na mão direita, perto da ponta do cabo: a pá sai em
-- -Z dela (cabo e lâmina) e a concha da lâmina fica para +Y. PivotTo(cf) põe a pega em cf.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemAnim = require(script.Parent.ItemAnim)

local PaArte = {}

local M = 0.28
PaArte.FOLDER = "VT65ItemArte"
PaArte.PEGA_M = 0.05 -- a mão direita a 5 cm da ponta do cabo
-- O importador do Roblox gira o GLB 180° em Y (D-58): a lâmina (-Y no Blender) fica em -Z e a ponta do
-- cabo em +Z do modelo publicado (conferido no Studio, D-183).
PaArte.CABO_Z = 1

function PaArte.key(faction: string?): string
	return if faction == "VC" then "shovel_vc" else "shovel_us"
end

-- O modelo publicado deste lado, se o servidor já copiou.
function PaArte.art(faction: string?): Model?
	local f = ReplicatedStorage:FindFirstChild(PaArte.FOLDER)
	local m = f and f:FindFirstChild(PaArte.key(faction))
	return if m and m:IsA("Model") then m else nil
end

-- Chave de cache: muda quando a arte chega (quem guardou a pá em peças monta de novo).
function PaArte.cacheKey(faction: string?): string
	return PaArte.key(faction) .. (if PaArte.art(faction) then ":arte" else ":pecas")
end

local function prep(p: BasePart, anchored: boolean)
	p.Anchored = anchored
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	p.Massless = true
end

-- Solda com o desvio escrito (C0). Não é WeldConstraint: essa grava o desvio quando entra no workspace,
-- e aí a Weld do tronco já levou a Pega para a mão e a peça ficava a ~1.800 studs (Studio, D-183).
local function soldar(pega: BasePart, p: BasePart)
	local w = Instance.new("Weld")
	w.Part0, w.Part1 = pega, p
	w.C0 = pega.CFrame:ToObjectSpace(p.CFrame)
	w.C1 = CFrame.identity
	w.Parent = p
end

-- Caixa (no mundo do modelo) de todas as peças.
local function bounds(m: Instance): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size / 2
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local h = Vector3.new(
				math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
				math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
				math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
			)
			lo = lo:Min(cf.Position - h)
			hi = hi:Max(cf.Position + h)
		end
	end
	return lo, hi
end

-- Onde fica a pega no modelo publicado: no eixo do cabo (meio da caixa em X e Y), a PEGA_M da ponta.
function PaArte.grip(m: Instance): CFrame
	local lo, hi = bounds(m)
	local c = (lo + hi) / 2
	local z = if PaArte.CABO_Z > 0 then hi.Z - PaArte.PEGA_M / M else lo.Z + PaArte.PEGA_M / M
	local cf = CFrame.new(c.X, c.Y, z)
	return if PaArte.CABO_Z > 0 then cf else cf * CFrame.Angles(0, math.pi, 0)
end

-- A pá em peças (a de antes da D-183): cabo em T na pega, cabo de 0,55 m e lâmina de 0,2 x 0,15 m.
local function pecas(m: Model, pega: BasePart, anchored: boolean)
	local def = ItemAnim.PROPS.pa
	local s = def.size
	local function piece(size: { number }, cf: CFrame, shape: Enum.PartType?, metal: boolean?)
		local p = Instance.new("Part")
		prep(p, anchored)
		if shape then
			p.Shape = shape
		end
		p.Size = Vector3.new(size[1], size[2], size[3]) / M
		p.Color = Color3.fromRGB(def.rgb[1], def.rgb[2], def.rgb[3])
		p.Material = if metal then Enum.Material.Metal else Enum.Material.SmoothPlastic
		p.CFrame = cf
		p.Parent = m
		if not anchored then
			soldar(pega, p)
		end
	end
	piece({ 0.12, 0.03, 0.03 }, CFrame.identity, Enum.PartType.Cylinder) -- cabo em T (mão direita)
	piece(
		{ s[3], s[1], s[2] },
		CFrame.new(0, 0, -s[3] / 2 / M) * CFrame.Angles(0, math.pi / 2, 0),
		Enum.PartType.Cylinder
	)
	local b = def.blade or { 0.2, 0.15, 0.01 }
	piece({ b[2], b[1], b[3] }, CFrame.new(0, 0, -(s[3] + b[1] / 2) / M) * CFrame.Angles(math.pi / 2, 0, 0), nil, true)
end

-- Monta a pá deste lado. anchored: 1ª pessoa (peças ancoradas, PivotTo a cada quadro); false: 3ª
-- pessoa (soldada na Pega, que o PostureController solda no tronco).
function PaArte.build(faction: string?, anchored: boolean): Model
	local m = Instance.new("Model")
	m.Name = "VT65Pa"
	local pega = Instance.new("Part")
	pega.Name = "Pega"
	pega.Size = Vector3.one * 0.05
	pega.Transparency = 1
	prep(pega, anchored)
	pega.CFrame = CFrame.identity
	pega.Parent = m
	m.PrimaryPart = pega
	local art = PaArte.art(faction)
	if art then
		local copy = art:Clone()
		local frame = PaArte.grip(copy)
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = frame:ToObjectSpace(d.CFrame)
				prep(d, anchored)
				d.Parent = m
				if not anchored then
					soldar(pega, d)
				end
			end
		end
		copy:Destroy()
	else
		pecas(m, pega, anchored)
	end
	m:SetAttribute("Arte", art ~= nil)
	return m
end

return PaArte
