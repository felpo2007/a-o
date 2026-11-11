--!strict
-- Monta o soldado de cada facção: corpo, escala 1:1 (1,75 m ≈ 6,25 studs), uniforme e equipamento.
-- describe(): HumanoidDescription (partes do corpo, escala e cores; pele onde o molde v3 é transparente).
-- dress(): depois do spawn aplica os moldes (ShirtTemplate/PantsTemplate: v3 quando o ID existe em
-- AssetIds.Clothing, senão a v2), solda capacete/colete do ForgeGUI ajustados à cabeça e ao tronco
-- e monta o equipamento 3D (Modules/Gear). Sem assets publicados, fica o uniforme por cor.
-- Skins do jogador (Shared/Skins, atributos "SkinUniform" e "SkinCamo" postos pelo
-- ProgressionService): o uniforme da skin e a camuflagem de mato (feixes de folha soldados em cada
-- parte do corpo, atributo "Camo" no personagem para a visão dos bots).
-- Usado pelo SpawnService (jogador), BotService (bots) e PreviewService (manequim do lobby).
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Skins = require(ReplicatedStorage.Shared.Skins)
local Gear = require(script.Parent.Gear)

local Characters = {}

-- Corpo: partes OFICIAIS da Roblox (criador "Roblox", ID 1), que qualquer jogo carrega pelo
-- HumanoidDescription. Conferido na API do catálogo (2026-11-11):
-- - "Man": bundle 238 (o mesmo corpo do avatar padrão "Neoclassic Male", bundle 578). Corpo de
--   proporção clássica com peito, ombro e membros afinados; feito para a roupa clássica.
-- - cabeça "Man Face - Head" (cabeça dinâmica, tipo 79) e a animação de rosto "Man Face - Mood".
-- "bloco" volta ao corpo padrão em bloco (0 = parte padrão).
-- Altura: com HeightScale 1,2 o "Man" mediu 1,68 m no Studio (2026-11-11, atributo AlturaM).
-- D-77 (pedido do dono: "aumente a altura para ter melhor visão, a grama está alta"): 1,25, que
-- dá a meta de 1,75 m (1,68 x 1,25 / 1,2).
export type Body = {
	Torso: number,
	RightArm: number,
	LeftArm: number,
	LeftLeg: number,
	RightLeg: number,
	Head: number,
	MoodAnimation: number,
	heightScale: number,
}
Characters.BODIES = {
	man = {
		Torso = 86500008,
		RightArm = 86500036,
		LeftArm = 86500054,
		LeftLeg = 86500064,
		RightLeg = 86500078,
		Head = 10725826963,
		MoodAnimation = 10725833199,
		heightScale = 1.25,
	},
	bloco = {
		Torso = 0,
		RightArm = 0,
		LeftArm = 0,
		LeftLeg = 0,
		RightLeg = 0,
		Head = 0,
		MoodAnimation = 0,
		heightScale = 1.2,
	},
} :: { [string]: Body }
Characters.BODY = "man"

local function body(): Body
	return Characters.BODIES[Characters.BODY] or Characters.BODIES.bloco
end

-- HeightScale para ~6,25 studs (D-30). Mantido por compatibilidade; vem do corpo escolhido.
Characters.HEIGHT_SCALE = body().heightScale
Characters.TARGET_HEIGHT_M = 1.75

local SKIN = {
	Color3.fromRGB(196, 150, 112),
	Color3.fromRGB(171, 125, 90),
	Color3.fromRGB(141, 99, 70),
	Color3.fromRGB(224, 182, 146),
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- mesma pele no describe e no dress: a semente é o UserId do jogador, o número do bot ou 0
local function skinOf(seed: number?): Color3
	return SKIN[1 + (math.floor(seed or 0) % #SKIN)]
end

local LIMB_PARTS = {
	arms = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" },
	legs = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" },
	torso = { "UpperTorso", "LowerTorso" },
}

-- equipped: slot -> cosmético (Commerce), ex. { helmet = "vc_pith_helmet", uniform = "vc_green" }
function Characters.describe(faction: string, equipped: { [string]: string }?, seed: number?): HumanoidDescription
	local b = body()
	local desc = Instance.new("HumanoidDescription")
	desc.HeightScale = b.heightScale
	desc.WidthScale = 1
	desc.DepthScale = 1
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	desc.Torso = b.Torso
	desc.RightArm = b.RightArm
	desc.LeftArm = b.LeftArm
	desc.LeftLeg = b.LeftLeg
	desc.RightLeg = b.RightLeg
	desc.Head = b.Head
	desc.MoodAnimation = b.MoodAnimation
	local skin = skinOf(seed)
	desc.HeadColor = skin
	-- o molde v3 é transparente na mão, no antebraço arregaçado, no decote e na canela/pé do VC:
	-- ali aparece a cor do corpo, que tem de ser a pele
	local u = Gear.uniform(faction, equipped, AssetIds.Clothing, false)
	desc.TorsoColor = if u.skinTorso then skin else rgb(u.shirtRgb)
	local arms = if u.skinArms then skin else rgb(u.shirtRgb)
	desc.LeftArmColor = arms
	desc.RightArmColor = arms
	local legs = if u.skinLegs then skin else rgb(u.pantsRgb)
	desc.LeftLegColor = legs
	desc.RightLegColor = legs
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

-- Veste um modelo do ForgeGUI (capacete, chapéu, colete) ajustado à peça do corpo:
-- - gira ART_YAW (a frente dos GLB fica em −X no Roblox, D-58);
-- - com um MeshPart só, muda o Size (escala não uniforme: o colete abraça o tronco de qualquer
--   corpo); com mais peças, escala uniforme pelo eixo mais justo;
-- - centra a caixa do modelo em part.CFrame * (0, offsetY, 0) e solda.
-- fitOf recebe a caixa nativa do modelo (espaço do pivô) e devolve o ajuste (Gear.Fit).
local function wear(key: string, part: BasePart?, model: Model, fitOf: (Vector3) -> Gear.Fit?): Gear.Fit?
	local tpl = template(key)
	if not (tpl and part) then
		return nil
	end
	local acc = tpl:Clone()
	acc.Name = "Gear_" .. key
	local parts: { BasePart } = {}
	for _, d in acc:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		acc:Destroy()
		return nil
	end
	local _, native = acc:GetBoundingBox()
	local fit = fitOf(native)
	if not fit then
		acc:Destroy()
		return nil
	end
	local target = Vector3.new(fit.size.x, fit.size.y, fit.size.z)
	local only = parts[1]
	if #parts == 1 and only:IsA("MeshPart") then
		local rel = acc:GetPivot():ToObjectSpace(only.CFrame)
		local t = rel:VectorToObjectSpace(target)
		only.Size = Vector3.new(math.abs(t.X), math.abs(t.Y), math.abs(t.Z))
	else
		local k = math.min(target.X / native.X, target.Y / native.Y, target.Z / native.Z)
		acc:ScaleTo(acc:GetScale() * k)
	end
	local box = acc:GetBoundingBox()
	local pivotInBox = box:ToObjectSpace(acc:GetPivot())
	acc:PivotTo(part.CFrame * CFrame.new(0, fit.offsetY, 0) * CFrame.Angles(0, Gear.ART_YAW, 0) * pivotInBox)
	for _, d in parts do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = part, d
		w.Parent = d
	end
	acc.Parent = model
	return fit
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

-- Semente estável do soldado: UserId do jogador; número do bot ("Bot_VC_07"); 0 no manequim.
local function seedOf(model: Model): number
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player.UserId
	end
	return tonumber(string.match(model.Name, "(%d+)$")) or 0
end

local function roleOf(model: Model): string?
	local r = model:GetAttribute("Role")
	if type(r) == "string" then
		return r
	end
	local player = Players:GetPlayerFromCharacter(model)
	local pr = player and player:GetAttribute("Role")
	return if type(pr) == "string" then pr else nil
end

local function size(p: BasePart): Gear.Vec
	return Gear.vec(p.Size.X, p.Size.Y, p.Size.Z)
end

-- Altura do soldado (pé ao topo da cabeça) pelas caixas das partes do corpo, no eixo do
-- HumanoidRootPart. Vai no atributo AlturaM para conferir no Studio (meta: 1,75 m).
local BODY_PARTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftFoot",
	"RightFoot",
	"LeftLowerLeg",
	"RightLowerLeg",
	"LeftUpperLeg",
	"RightUpperLeg",
}
local warnedHeight = false
local function measureHeight(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- Só no Workspace. O manequim da prévia (PreviewService) é montado fora dele, as juntas não
	-- são resolvidas e a medida saía 1,45 m: um aviso falso a cada início de servidor. No campo,
	-- todos os soldados medem 1,68 m (Studio, 2026-11-11).
	if not root or not model:IsDescendantOf(workspace) then
		return
	end
	local up = root.CFrame.UpVector
	local lo, hi = math.huge, -math.huge
	for _, name in BODY_PARTS do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local cf, s = p.CFrame, p.Size
			local half = (
				math.abs(cf.RightVector:Dot(up)) * s.X
				+ math.abs(cf.UpVector:Dot(up)) * s.Y
				+ math.abs(cf.LookVector:Dot(up)) * s.Z
			) / 2
			local c = (p.Position - root.Position):Dot(up)
			lo = math.min(lo, c - half)
			hi = math.max(hi, c + half)
		end
	end
	if hi <= lo then
		return
	end
	local meters = (hi - lo) * Gear.STUD_M
	model:SetAttribute("AlturaM", math.round(meters * 1000) / 1000)
	if not warnedHeight and math.abs(meters - Characters.TARGET_HEIGHT_M) > 0.05 then
		warnedHeight = true
		warn(
			string.format(
				"[VT65] soldado com %.2f m (meta %.2f m): ajuste Characters.BODIES.%s.heightScale",
				meters,
				Characters.TARGET_HEIGHT_M,
				Characters.BODY
			)
		)
	end
end

-- Skin do jogador num encaixe ("SkinUniform" / "SkinCamo"), se for do lado. Bot e manequim: nil.
local function skinOfPlayer(model: Model, attr: string, kind: string, faction: string): Skins.Skin?
	local player = Players:GetPlayerFromCharacter(model)
	local s = if player then Skins.get(player:GetAttribute(attr)) else nil
	return if s and s.kind == kind and Skins.sideOk(s, faction) then s else nil
end

-- ===== camuflagem de mato (ghillie) =====
-- Uma peça por parte do corpo (Skins.GHILLIE, malha de tools/ghillie.py), escalada pela parte real
-- e soldada com Weld (o cliente balança o C0 ao vento). Textura do tipo (arrozal, selva, bambu) por
-- TextureID; o recorte pelo alfa só vale com Transparency > 0. Sem colisão, sem consulta (o tiro
-- passa para o corpo) e sem massa; a sombra o cliente desliga só no próprio jogador.
-- Sem a malha publicada (AssetIds.Accessories.ghillie = 0) não aparece nada, mas o atributo "Camo"
-- (vantagem contra os bots, BotBrain.camoFactor) vale do mesmo jeito: é o que foi comprado.
local function ghillie(model: Model, camo: Skins.Skin?)
	local old = model:FindFirstChild("Camuflagem")
	if old then
		old:Destroy()
	end
	model:SetAttribute("Camo", if camo then camo.camo else nil)
	local tpl = if camo then template("ghillie") else nil
	if not (camo and tpl) then
		return
	end
	local texId = if camo.texture then AssetIds.Images[camo.texture] else nil
	local tex = if type(texId) == "number" and texId ~= 0 then imageUrl(texId) else nil
	local tint = camo.swatch[1] or { 90, 110, 50 }
	local fit = Skins.GHILLIE
	local folder = Instance.new("Folder")
	folder.Name = "Camuflagem"
	for name, pc in fit.parts do
		local body = model:FindFirstChild(name)
		local src = tpl:FindFirstChild("Ghillie_" .. name, true)
		local ref = fit.ref[name]
		if body and body:IsA("BasePart") and src and src:IsA("MeshPart") and ref then
			local p = src:Clone()
			for _, c in p:GetChildren() do
				if c:IsA("SurfaceAppearance") then
					if tex then
						c:Destroy() -- a textura do tipo vai no TextureID
					else
						-- textura do tipo ainda não publicada: fica a do GLB (arrozal), recortada
						c.AlphaMode = Enum.AlphaMode.Transparency
					end
				end
			end
			local k = Vector3.new(body.Size.X / ref[1], body.Size.Y / ref[2], body.Size.Z / ref[3])
			p.Size = Vector3.new(pc.size[1] * k.X, pc.size[2] * k.Y, pc.size[3] * k.Z)
			if tex then
				p.TextureID = tex
			end
			p.Color = Color3.fromRGB(tint[1], tint[2], tint[3])
			p.Transparency = Skins.GHILLIE_TRANSPARENCY
			p.DoubleSided = true
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CastShadow = true
			p.Name = "Ghillie_" .. name
			local w = Instance.new("Weld")
			w.Name = "Folhas"
			w.Part0 = body
			w.Part1 = p
			w.C0 = CFrame.new(pc.offset[1] * k.X, pc.offset[2] * k.Y, pc.offset[3] * k.Z)
				* CFrame.Angles(0, Skins.GHILLIE_YAW, 0)
			w.Parent = p
			p.Parent = folder
		end
	end
	folder.Parent = model
	CollectionService:AddTag(folder, Skins.GHILLIE_TAG)
end

function Characters.dress(model: Model, faction: string, equipped: { [string]: string }?)
	local eq: { [string]: string } = equipped or {}
	local C = AssetIds.Clothing
	local isBot = model:GetAttribute("Bot") == true
	local seed = seedOf(model)
	-- skin de uniforme: o pijama preto usa a variante que o Gear já veste; as outras, molde próprio
	local uSkin = skinOfPlayer(model, "SkinUniform", "uniform", faction)
	local gearSkin: Gear.UniformSkin? = nil
	if uSkin and uSkin.gearUniform then
		eq = table.clone(eq)
		eq.uniform = uSkin.gearUniform
	elseif uSkin then
		gearSkin = { id = uSkin.id, shirt = uSkin.shirt, pants = uSkin.pants, rgb = uSkin.rgb }
	end
	local u = Gear.uniform(faction, eq, C, isBot and Gear.isGuerrilla(seed), gearSkin)
	-- O describe não sabe se o bot é guerrilheiro. Se o molde escolhido aqui deixa pele à mostra,
	-- garante a cor de pele nessas partes (só muda algo quando os moldes v3 foram publicados pela
	-- metade e o preto caiu num molde diferente do previsto no describe).
	local skin = skinOf(seed)
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	local function paintSkin(group: string, color: Color3?)
		local c = color or skin
		for _, name in LIMB_PARTS[group] do
			local p = model:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				p.Color = c
			end
		end
		if bodyColors then
			if group == "arms" then
				bodyColors.LeftArmColor3, bodyColors.RightArmColor3 = c, c
			elseif group == "legs" then
				bodyColors.LeftLegColor3, bodyColors.RightLegColor3 = c, c
			else
				bodyColors.TorsoColor3 = c
			end
		end
	end
	-- skin de uniforme sem molde nenhum publicado: o soldado fica na cor média da skin
	if gearSkin and not u.shirt then
		paintSkin("torso", rgb(u.shirtRgb))
		paintSkin("arms", rgb(u.shirtRgb))
	end
	if gearSkin and not u.pants then
		paintSkin("legs", rgb(u.pantsRgb))
	end
	if u.skinArms then
		paintSkin("arms")
	end
	if u.skinLegs then
		paintSkin("legs")
	end
	if u.skinTorso then
		paintSkin("torso")
	end
	local shirtId = if u.shirt then C[u.shirt] else 0
	local pantsId = if u.pants then C[u.pants] else 0
	if type(shirtId) == "number" and shirtId ~= 0 then
		local s = model:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
		s.ShirtTemplate = imageUrl(shirtId)
		s.Parent = model
	end
	if type(pantsId) == "number" and pantsId ~= 0 then
		local p = model:FindFirstChildOfClass("Pants") or Instance.new("Pants")
		p.PantsTemplate = imageUrl(pantsId)
		p.Parent = model
	end
	model:SetAttribute("Uniforme", u.variant)

	local head = model:FindFirstChild("Head") :: BasePart?
	local upper = model:FindFirstChild("UpperTorso") :: BasePart?
	local lower = model:FindFirstChild("LowerTorso") :: BasePart?
	local helmetFit: Gear.Fit?, vestFit: Gear.Fit? = nil, nil
	local function headgear(key: string): Gear.Fit?
		if not head then
			return nil
		end
		local hs = size(head)
		return wear(key, head, model, function(native: Vector3): Gear.Fit?
			return Gear.headgearFit(key, hs, Gear.vec(native.X, native.Y, native.Z))
		end)
	end
	if faction == "US" then
		helmetFit = headgear("us_m1_helmet")
		if upper then
			local us = size(upper)
			vestFit = wear("us_m1955_vest", upper, model, function(_native: Vector3): Gear.Fit?
				return Gear.vestFit(us)
			end)
		end
	elseif eq.helmet == "vc_pith_helmet" or eq.helmet == "vc_jungle_hat" then
		helmetFit = headgear(eq.helmet)
	end

	if upper and lower then
		local env = Gear.env(size(lower), size(upper), if head then size(head) else nil, vestFit, helmetFit)
		local pieces = Gear.layout(faction, Gear.items(faction, roleOf(model), eq), env)
		Gear.build(model, { UpperTorso = upper, LowerTorso = lower, Head = head }, pieces)
	end
	ghillie(model, skinOfPlayer(model, "SkinCamo", "camo", faction))
	measureHeight(model)
end

return Characters
