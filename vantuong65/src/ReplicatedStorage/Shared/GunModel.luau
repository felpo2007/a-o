--!strict
-- Arma provisória feita de peças, enquanto o modelo do ForgeGUI não está publicado (AssetIds em 0).
-- Antes, sem asset, ninguém aparecia segurando arma e a arma caída era uma tábua.
-- Comprimento total real de cada arma (fichas públicas); o resto é proporção, sem pretensão de
-- detalhe. Origem no punho; a frente é −Z (LookVector). Tem os Attachments "Muzzle" (boca do
-- cano) e "Sight" (linha de visada, na alça), usados pela arma em primeira pessoa e pelos efeitos.
local GunModel = {}

local M = 0.28
local LENGTH_M: { [string]: number } = {
	m14 = 1.126,
	type56 = 0.882,
	sks = 1.02,
	m60 = 1.105,
	rpd = 1.037,
	m79 = 0.737,
	m1911 = 0.216,
	type54 = 0.196,
	rpg2 = 0.95,
}
local WOOD = Color3.fromRGB(96, 66, 42)
local STEEL = Color3.fromRGB(44, 45, 47)

local function piece(model: Model, name: string, sizeM: Vector3, zM: number, yM: number, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = sizeM / M
	p.CFrame = CFrame.new(0, yM / M, -zM / M)
	p.Color = color
	p.Material = if color == WOOD then Enum.Material.Wood else Enum.Material.Metal
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = model
	return p
end

function GunModel.length(weaponId: string, kind: string?): number
	return LENGTH_M[weaponId] or (if kind == "pistol" then 0.21 else 1.0)
end

-- Monta a arma (peças soltas, sem solda: quem usa decide ancorar ou soldar com GunModel.weld).
function GunModel.build(weaponId: string, kind: string?): Model
	local L = GunModel.length(weaponId, kind)
	local model = Instance.new("Model")
	model.Name = "Weapon"
	model:SetAttribute("WeaponId", weaponId)
	model:SetAttribute("Kind", kind or "rifle")
	local receiver: Part
	local muzzleZ, sightY, sightZ = 0, 0, 0
	if kind == "pistol" then
		receiver = piece(model, "Slide", Vector3.new(0.028, 0.034, L), L * 0.4, 0.03, STEEL)
		piece(model, "Grip", Vector3.new(0.026, 0.11, 0.035), 0, -0.035, STEEL)
		muzzleZ, sightY, sightZ = L * 0.9, 0.055, L * 0.0
	else
		-- coronha atrás do punho, caixa da culatra, guarda-mão e cano até a boca (−30% a +70% de L)
		piece(model, "Stock", Vector3.new(0.042, 0.10, L * 0.28), -L * 0.16, -0.015, WOOD)
		receiver = piece(model, "Receiver", Vector3.new(0.05, 0.07, L * 0.27), L * 0.115, 0.02, STEEL)
		piece(model, "Handguard", Vector3.new(0.048, 0.052, L * 0.22), L * 0.36, 0.018, WOOD)
		piece(model, "Barrel", Vector3.new(0.02, 0.02, L * 0.23), L * 0.585, 0.025, STEEL)
		piece(model, "Grip", Vector3.new(0.03, 0.09, 0.04), 0, -0.04, WOOD)
		local magH = if kind == "mg" then 0.1 else 0.13
		piece(model, "Magazine", Vector3.new(0.028, magH, 0.06), L * 0.1, -0.02 - magH / 2, STEEL)
		piece(model, "FrontSight", Vector3.new(0.006, 0.03, 0.006), L * 0.68, 0.05, STEEL)
		piece(model, "RearSight", Vector3.new(0.03, 0.025, 0.012), L * 0.2, 0.065, STEEL)
		muzzleZ, sightY, sightZ = L * 0.7, 0.067, L * 0.2
	end
	model.PrimaryPart = receiver
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = receiver.CFrame:ToObjectSpace(CFrame.new(0, 0.025 / M, -muzzleZ / M))
	muzzle.Parent = receiver
	local sight = Instance.new("Attachment")
	sight.Name = "Sight"
	sight.CFrame = receiver.CFrame:ToObjectSpace(CFrame.new(0, sightY / M, -sightZ / M))
	sight.Parent = receiver
	-- mãos (IK no PostureController): direita no punho; esquerda logo à frente do carregador, a
	-- 22% do comprimento. O braço esquerdo alcança ~0,58 m: a 36% (meio do guarda-mão) não chegava.
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.CFrame = receiver.CFrame:ToObjectSpace(CFrame.identity)
	grip.Parent = receiver
	local support = Instance.new("Attachment")
	support.Name = "Support"
	support.CFrame = receiver.CFrame:ToObjectSpace(CFrame.new(0, 0, -(if kind == "pistol" then 0 else L * 0.22) / M))
	support.Parent = receiver
	model.WorldPivot = CFrame.identity -- punho
	return model
end

-- Solda todas as peças na principal (para a arma presa na mão ou solta no chão).
function GunModel.weld(model: Model)
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

return GunModel
