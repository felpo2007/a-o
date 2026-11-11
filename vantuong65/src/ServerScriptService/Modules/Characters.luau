--!strict
-- Monta o soldado de cada facção: escala 1:1 (1,75 m ≈ 6,25 studs), uniforme e equipamento.
-- describe(): HumanoidDescription (escala e cores de placeholder).
-- dress(): depois do spawn aplica os moldes de uniforme (ShirtTemplate/PantsTemplate) e solda
-- capacete/colete (modelos do ForgeGUI). Sem assets publicados, fica o uniforme por cor.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any

local Characters = {}

-- HeightScale para ~6,25 studs. PROVISÓRIO: o HUD de medição (F3) mostra a altura real em m.
Characters.HEIGHT_SCALE = 1.2

local SKIN = {
	Color3.fromRGB(196, 150, 112),
	Color3.fromRGB(171, 125, 90),
	Color3.fromRGB(141, 99, 70),
	Color3.fromRGB(224, 182, 146),
}
local UNIFORM = {
	US = { shirt = Color3.fromRGB(88, 92, 62), pants = Color3.fromRGB(80, 84, 58) }, -- OG-107
	VC_khaki = { shirt = Color3.fromRGB(150, 132, 96), pants = Color3.fromRGB(140, 124, 90) },
	VC_green = { shirt = Color3.fromRGB(76, 90, 64), pants = Color3.fromRGB(70, 82, 60) },
}

-- equipped: slot -> cosmético (Commerce), ex. { helmet = "vc_pith_helmet", uniform = "vc_green" }
function Characters.describe(faction: string, equipped: { [string]: string }?, seed: number?): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	desc.HeightScale = Characters.HEIGHT_SCALE
	desc.WidthScale = 1
	desc.DepthScale = 1
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	desc.HeadColor = SKIN[1 + ((seed or 0) % #SKIN)]
	local eq: { [string]: string } = equipped or {}
	local uni = if faction == "US"
		then UNIFORM.US
		elseif eq.uniform == "vc_green" then UNIFORM.VC_green
		else UNIFORM.VC_khaki
	desc.TorsoColor = uni.shirt
	desc.LeftArmColor = uni.shirt
	desc.RightArmColor = uni.shirt
	desc.LeftLegColor = uni.pants
	desc.RightLegColor = uni.pants
	return desc
end

local templates: { [string]: Model } = {}
local function template(key: string): Model?
	if templates[key] then
		return templates[key]
	end
	local id = AssetIds.Accessories[key]
	if type(id) ~= "number" or id == 0 then
		return nil
	end
	local ok, c = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not c then
		return nil
	end
	local m = c:FindFirstChildWhichIsA("Model") or c
	templates[key] = m :: Model
	return m :: Model
end

local function weldTo(key: string, part: BasePart?, offset: CFrame, model: Model, scale: number?)
	local tpl = template(key)
	if not (tpl and part) then
		return
	end
	local acc = tpl:Clone()
	acc.Name = "Gear_" .. key
	if scale then
		acc:ScaleTo(acc:GetScale() * scale)
	end
	local parts = {}
	for _, d in acc:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			table.insert(parts, d)
		end
	end
	acc:PivotTo(part.CFrame * offset)
	for _, d in parts do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = part, d
		w.Parent = d
	end
	acc.Parent = model
end

-- O Open Cloud sobe imagens como Decal: o ID devolvido é do Decal, não da imagem. Carrega o
-- Decal uma vez e usa o Texture dele; se não for Decal, usa o ID direto.
local images: { [number]: string } = {}
local function imageUrl(id: number): string
	local cached = images[id]
	if cached then
		return cached
	end
	local url = "rbxassetid://" .. id
	local ok, c = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if ok and c then
		local decal = c:FindFirstChildWhichIsA("Decal", true)
		if decal and decal.Texture ~= "" then
			url = decal.Texture
		end
		c:Destroy()
	end
	images[id] = url
	return url
end

function Characters.dress(model: Model, faction: string, equipped: { [string]: string }?)
	local eq: { [string]: string } = equipped or {}
	local C = AssetIds.Clothing
	local shirtId, pantsId
	if faction == "US" then
		shirtId, pantsId = C.us_shirt, C.us_pants
	elseif eq.uniform == "vc_green" then
		shirtId, pantsId = C.vc_green_shirt, C.vc_green_pants
	else
		shirtId, pantsId = C.vc_khaki_shirt, C.vc_khaki_pants
	end
	if shirtId ~= 0 then
		local s = model:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
		s.ShirtTemplate = imageUrl(shirtId)
		s.Parent = model
	end
	if pantsId ~= 0 then
		local p = model:FindFirstChildOfClass("Pants") or Instance.new("Pants")
		p.PantsTemplate = imageUrl(pantsId)
		p.Parent = model
	end
	local head = model:FindFirstChild("Head") :: BasePart?
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	-- O capacete tem tamanho real (0,29 m ≈ 1 stud), mas a cabeça do avatar do Roblox tem 1,2 studs:
	-- ficava rente à cabeça e parecia uma faixa escura, não um M1 (captura do lobby, D-64).
	local up = if head then CFrame.new(0, head.Size.Y * 0.38, 0) else CFrame.new()
	local HEADGEAR = 1.15
	if faction == "US" then
		weldTo("us_m1_helmet", head, up, model, HEADGEAR)
		weldTo("us_m1955_vest", torso, CFrame.new(), model)
	elseif eq.helmet == "vc_pith_helmet" or eq.helmet == "vc_jungle_hat" then
		weldTo(eq.helmet, head, up, model, HEADGEAR)
	end
end

return Characters
