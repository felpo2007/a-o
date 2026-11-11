--!strict
-- Visual da arma e dos tiros (cliente). No teste do Studio (2026-11-10) ninguém segurava arma, não
-- havia clarão de boca nem marca de impacto, e o traçante era uma linha reta do olho até o impacto.
-- - Arma em primeira pessoa (só quem joga vê): no quadril; mirando, vai ao ombro com a alça no
--   centro da tela. Recua a cada tiro e balança ao andar.
-- - Clarão de boca: luz e chama por 2 quadros, no próprio tiro e no dos outros (na arma deles).
-- - Traçante: risco curto que voa pela trajetória real (mesma semente), saindo da boca do cano.
-- - Impacto: poeira, terra ou água onde a bala para (até 150 m). Em corpo, nada: não há hitmarker.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local GunModel = require(ReplicatedStorage.Shared.GunModel)
local Net = require(ReplicatedStorage.Shared.Net)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local IMPACT_MAX_M = 150

local fx = Instance.new("Folder")
fx.Name = "VT65Effects"
fx.Parent = workspace

-- ===== arma em primeira pessoa =====
-- quadril: arma junto ao corpo (D-69: "aproxime as armas para mais perto do jogador"); era
-- (0,17; −0,19; −0,34) m e a arma parecia flutuar longe
local HIP = CFrame.new(0.12 / M, -0.15 / M, -0.23 / M) * CFrame.Angles(0, math.rad(3), 0)
local EYE_TO_SIGHT_M = 0.09 -- olho até a alça, mirando
local view: Model? = nil
local viewId: string? = nil
local viewSight = Vector3.zero -- posição da alça no espaço da arma (punho na origem)
local viewEye = EYE_TO_SIGHT_M -- olho até a alça (m); a arma publicada traz o seu (EyeM: pistola 0,45)
-- giro que deixa a linha alça → massa (Sight → SightFront) no centro da tela, para onde o tiro vai.
-- Na arma provisória a linha já é paralela ao cano (sem giro).
local viewAlign = CFrame.identity
local aimT = 0 -- 0 = quadril, 1 = ombro
local kick = 0 -- recuo visual, volta em ~0,15 s
local bobT = 0
-- pontos no espaço da arma (punho na origem, boca em −Z, +Y para cima), lidos em setView
local gripL, supportL, magL, chargeL = Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero
local viewKind = "rifle"

-- ===== mira limpa (D-69) =====
-- "a mira está muito pixelada" (usuário): a alça e a massa ocupam poucos texels da textura de
-- 1024 px da arma inteira. Por cima delas vão peças lisas de aço, no ponto medido na malha
-- (tools/sight_align.py): anel (M14) ou entalhe (Type 56, SKS) e a lâmina da massa. Ficam 0,4–0,6 mm
-- à frente da malha (lado do olho), sem disputar o mesmo plano.
local STEEL = Color3.fromRGB(38, 39, 37)
local function sightPart(parent: Instance, cf: CFrame, sizeM: Vector3)
	local p = Instance.new("Part")
	p.Name = "MiraLimpa"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Metal
	p.Color = STEEL
	p.Size = sizeM / M
	p.CFrame = cf
	p.Parent = parent
end

local function crispSights(m: Model, sightP: Vector3, frontP: Vector3, kind: string, mm: number)
	local los = (frontP - sightP).Unit
	local up = (Vector3.yAxis - los * los:Dot(Vector3.yAxis)).Unit
	local right = los:Cross(up)
	local toEye = -los
	if kind == "anel" then
		local rIn = mm / 2000
		local rOut = rIn + 0.0022
		local rMid = (rIn + rOut) / 2
		local n = 16
		local seg = 2 * math.pi * rMid / n * 1.2
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * 2 * math.pi
			local radial = right * math.cos(a) + up * math.sin(a)
			local tangent = -right * math.sin(a) + up * math.cos(a)
			local center = sightP + radial * (rMid / M) + toEye * (0.0006 / M)
			sightPart(m, CFrame.fromMatrix(center, tangent, radial), Vector3.new(seg, rOut - rIn, 0.0025))
		end
	elseif kind == "entalhe" then
		local w = 0.0026 -- largura do entalhe (m)
		local depth = mm / 1000
		local leafW, leafH = 0.022, 0.006
		local bw = (leafW - w) / 2
		local base = sightP + toEye * (0.0006 / M)
		for _, s in { -1, 1 } do
			local c = base + right * (s * (w / 2 + bw / 2) / M) - up * (leafH / 2 / M)
			sightPart(m, CFrame.fromMatrix(c, right, up), Vector3.new(bw, leafH, 0.0016))
		end
		local hb = leafH - depth
		sightPart(m, CFrame.fromMatrix(base - up * ((depth + hb / 2) / M), right, up), Vector3.new(w, hb, 0.0016))
	end
	if kind ~= "" then
		local postH = 0.010
		local c = frontP + toEye * (0.0004 / M) - up * (postH / 2 / M)
		sightPart(m, CFrame.fromMatrix(c, right, up), Vector3.new(0.0022, postH, 0.0026))
	end
end

-- ===== braços em primeira pessoa (D-69) =====
-- Antes a arma flutuava sozinha. Mão direita no punho, esquerda no guarda-mão, antebraço com a manga
-- do uniforme até um cotovelo fixo na câmera. Na recarga a mão esquerda troca o carregador.
local SLEEVE: { [string]: Color3 } = { US = Color3.fromRGB(84, 88, 60), VC = Color3.fromRGB(142, 126, 92) }
local ELBOW_R = Vector3.new(0.2, -0.36, 0.06) / M -- espaço da câmera
local ELBOW_L = Vector3.new(-0.14, -0.38, -0.1) / M
local POUCH = Vector3.new(-0.22, -0.5, -0.12) / M -- cartucheira, fora da tela
local arms: Model? = nil
local armBits: { [string]: BasePart } = {}
local armsKey = ""

local function armPart(m: Model, name: string, color: Color3, mat: Enum.Material, cyl: boolean): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = mat
	p.Color = color
	if cyl then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Parent = m
	armBits[name] = p
	return p
end

local function ensureArms()
	local faction = player:GetAttribute("Faction")
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	local skin = if head then head.Color else Color3.fromRGB(196, 150, 112)
	local key = tostring(faction) .. ":" .. skin:ToHex()
	if arms and key == armsKey then
		return
	end
	armsKey = key
	if arms then
		arms:Destroy()
	end
	table.clear(armBits)
	local m = Instance.new("Model")
	m.Name = "VT65Arms"
	local sleeve = SLEEVE[if type(faction) == "string" then faction else "US"] or SLEEVE.US
	for _, s in { "R", "L" } do
		local h = armPart(m, "Mao" .. s, skin, Enum.Material.SmoothPlastic, false)
		h.Size = (if s == "R" then Vector3.new(0.04, 0.085, 0.1) else Vector3.new(0.09, 0.04, 0.1)) / M
		-- mão arredondada (elipsoide): o bloco reto parecia uma caixa laranja no canto da tela
		local shape = Instance.new("SpecialMesh")
		shape.MeshType = Enum.MeshType.Sphere
		shape.Parent = h
		armPart(m, "Punho" .. s, skin, Enum.Material.SmoothPlastic, true)
		armPart(m, "Manga" .. s, sleeve, Enum.Material.Fabric, true)
	end
	m.Parent = camera
	arms = m
end

-- antebraço: cilindro (eixo X) que sai do punho rumo ao cotovelo, só com o comprimento do antebraço
-- (FOREARM_M). Pedido do usuário: arma perto do corpo, só antebraço e mãos, sem o braço inteiro.
local FOREARM_M = 0.27
local function forearm(wrist: Vector3, elbow: Vector3, side: string)
	local cuff = armBits["Punho" .. side]
	local sl = armBits["Manga" .. side]
	if not (cuff and sl) then
		return
	end
	local dir = elbow - wrist
	local len = dir.Magnitude
	if len < 1e-3 then
		return
	end
	local u = dir / len
	len = math.min(len, FOREARM_M / M)
	elbow = wrist + u * len
	local cuffLen = math.min(0.05 / M, len * 0.3)
	local cuffEnd = wrist + u * cuffLen
	cuff.Size = Vector3.new(cuffLen, 0.06 / M, 0.06 / M)
	cuff.CFrame = CFrame.lookAt((wrist + cuffEnd) / 2, cuffEnd) * CFrame.Angles(0, math.pi / 2, 0)
	sl.Size = Vector3.new(len - cuffLen, 0.085 / M, 0.085 / M)
	sl.CFrame = CFrame.lookAt((cuffEnd + elbow) / 2, elbow) * CFrame.Angles(0, math.pi / 2, 0)
end

-- ===== recarga (D-69) =====
-- "faça um recarregamento real" (usuário). A malha da arma é uma peça só (o carregador não sai
-- dela), então a troca é encenada: a arma inclina, a mão esquerda puxa um carregador (peça à parte)
-- que cai no chão, busca outro na cartucheira, encaixa, dá o tapa e puxa o ferrolho. No tempo do
-- servidor (CombatService.RELOAD), avisado pelo WeaponController ("reload_start").
local reloadT0, reloadDur = 0, 0
local oldMag: BasePart? = nil
local newMag: BasePart? = nil
local magDropped = false
local MAG_SIZE: { [string]: Vector3 } = {
	rifle = Vector3.new(0.03, 0.17, 0.065),
	mg = Vector3.new(0.08, 0.1, 0.12),
	pistol = Vector3.new(0.025, 0.11, 0.032),
}
-- quadros-chave da mão esquerda: tempo (fração), espaço ("w" arma, "c" câmera), ponto
type Key = { t: number, s: string, p: Vector3 }
local function reloadKeys(): { Key }
	local down = Vector3.new(0, -1, 0) / M
	local back = Vector3.new(0, 0, 1) / M
	return {
		{ t = 0.0, s = "w", p = supportL },
		{ t = 0.13, s = "w", p = magL + down * 0.02 },
		{ t = 0.25, s = "w", p = magL + down * 0.14 },
		{ t = 0.4, s = "c", p = POUCH },
		{ t = 0.52, s = "w", p = magL + down * 0.12 },
		{ t = 0.64, s = "w", p = magL + down * 0.01 },
		{ t = 0.72, s = "w", p = magL + down * 0.03 },
		{ t = 0.79, s = "w", p = chargeL },
		{ t = 0.85, s = "w", p = chargeL + back * 0.07 },
		{ t = 0.94, s = "w", p = supportL },
		{ t = 1.0, s = "w", p = supportL },
	}
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function magPart(kind: string): BasePart
	local p = Instance.new("Part")
	p.Name = "Carregador"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Metal
	p.Color = STEEL
	p.Size = (MAG_SIZE[kind] or MAG_SIZE.rifle) / M
	p.Parent = camera
	return p
end

local function clearMags()
	if oldMag then
		oldMag:Destroy()
		oldMag = nil
	end
	if newMag then
		newMag:Destroy()
		newMag = nil
	end
end

Bus.on("reload_start", function(dur: number, _kind: string)
	clearMags()
	reloadT0, reloadDur = os.clock(), dur
	magDropped = false
end)

-- ===== arremesso de granada em 1ª pessoa (D-77) =====
-- A arma desce; a mão direita pega a granada no cinto, a esquerda puxa o pino, o braço arma ao
-- lado da cabeça e lança. A granada sai da mão em 0,4 s, junto com a do servidor (FieldService).
local THROW_S = 0.8
local throwT0 = -1
local throwKind = "frag"
local held: BasePart? = nil
local pinDone = false
-- mão direita no espaço da câmera (m): x direita, y cima, z frente negativa
local THROW_HAND = {
	{ t = 0.15, p = Vector3.new(0.17, -0.24, -0.3) },
	{ t = 0.27, p = Vector3.new(0.06, -0.13, -0.33) },
	{ t = 0.4, p = Vector3.new(0.27, 0.1, -0.06) },
	{ t = 0.52, p = Vector3.new(0.1, 0.06, -0.55) },
	{ t = 0.68, p = Vector3.new(0.02, -0.2, -0.45) },
}
local function heldGrenade(kind: string): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	if kind == "smoke" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.145, 0.06, 0.06) / M
		p.Color = Color3.fromRGB(74, 80, 48)
		p.Material = Enum.Material.Metal
	elseif player:GetAttribute("Faction") == "VC" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.25, 0.04, 0.04) / M
		p.Color = Color3.fromRGB(120, 90, 58)
		p.Material = Enum.Material.Wood
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Size = Vector3.new(0.057, 0.085, 0.057) / M
		p.Color = Color3.fromRGB(74, 80, 48)
		p.Material = Enum.Material.Metal
	end
	p.Parent = fx
	return p
end
local function dropPin(at: Vector3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.004, 0.03, 0.03) / M
	ring.Color = Color3.fromRGB(160, 160, 150)
	ring.Material = Enum.Material.Metal
	ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = false, false, false, false
	ring.CFrame = CFrame.new(at)
	ring.Parent = fx
	ring.AssemblyLinearVelocity = camera.CFrame:VectorToWorldSpace(Vector3.new(-0.5, 0.8, -0.3)) / M
	task.delay(1.5, function()
		ring:Destroy()
	end)
end
Bus.on("grenade_throw", function(kind: string)
	throwT0, throwKind, pinDone = os.clock(), kind, kind == "smoke"
	if held then
		held:Destroy()
		held = nil
	end
end)
-- (peso da arma baixada, posição da mão direita no mundo ou nil, mão esquerda no pino)
local function throwState(handR: Vector3): (number, Vector3?, boolean)
	local tp = if throwT0 >= 0 then (os.clock() - throwT0) / THROW_S else 2
	if tp >= 1 then
		if held then
			held:Destroy()
			held = nil
		end
		throwT0 = -1
		return 0, nil, false
	end
	local down = smooth(tp / 0.15) * (1 - smooth((tp - 0.8) / 0.2))
	local cam = camera.CFrame
	local function at(k: number): Vector3
		return cam * (THROW_HAND[k].p / M)
	end
	local hand: Vector3
	if tp < THROW_HAND[1].t then
		hand = handR:Lerp(at(1), smooth(tp / THROW_HAND[1].t))
	elseif tp >= THROW_HAND[#THROW_HAND].t then
		local t0 = THROW_HAND[#THROW_HAND].t
		hand = at(#THROW_HAND):Lerp(handR, smooth((tp - t0) / (1 - t0)))
	else
		hand = at(1)
		for k = 1, #THROW_HAND - 1 do
			local a, b = THROW_HAND[k], THROW_HAND[k + 1]
			if tp >= a.t and tp < b.t then
				hand = at(k):Lerp(at(k + 1), smooth((tp - a.t) / (b.t - a.t)))
				break
			end
		end
	end
	-- granada na mão do cinto (0,1) até sair (0,5)
	if tp >= 0.1 and tp < 0.5 then
		local h = held or heldGrenade(throwKind)
		held = h
		h.CFrame = cam.Rotation * CFrame.Angles(math.rad(20), 0, math.rad(70)) + hand
	elseif held then
		held:Destroy()
		held = nil
	end
	local pulling = tp >= 0.18 and tp < 0.3 and throwKind ~= "smoke"
	if tp >= 0.27 and not pinDone then
		pinDone = true
		dropPin(hand + cam.LookVector * 0.02 / M)
	end
	return down, hand, pulling
end

-- arma publicada já preparada pelo servidor (AssetLoader → GunModel.fit), se houver
local function artFor(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
	local tpl = folder and folder:FindFirstChild(id)
	return if tpl and tpl:IsA("Model") and tpl.PrimaryPart then tpl else nil
end

local function setView(id: string?)
	-- a chave inclui "arte": se o modelo publicado chegar depois, a provisória é trocada
	local art = if id then artFor(id) else nil
	local key = if id then id .. (if art then ":arte" else "") else nil
	if key == viewId then
		return
	end
	viewId = key
	if view then
		view:Destroy()
		view = nil
	end
	local wp = if id then Weapons.get(id) else nil
	if not (id and wp) then
		return
	end
	local m = if art then art:Clone() else GunModel.build(id, wp.kind)
	m:PivotTo(CFrame.identity)
	local primary = m.PrimaryPart :: BasePart
	local sight = primary:FindFirstChild("Sight") :: Attachment?
	viewSight = if sight then sight.WorldPosition else Vector3.zero -- a arma está na origem (punho)
	local eye = m:GetAttribute("EyeM")
	viewEye = if type(eye) == "number" then eye else EYE_TO_SIGHT_M
	local front = primary:FindFirstChild("SightFront") :: Attachment?
	local los = if front then front.WorldPosition - viewSight else Vector3.new(0, 0, -1)
	viewAlign = if los.Z < -1e-3 then CFrame.lookAt(Vector3.zero, los):Inverse() else CFrame.identity
	-- mãos, carregador e ferrolho (espaço da arma; a arma está na origem)
	local g = primary:FindFirstChild("Grip") :: Attachment?
	local s = primary:FindFirstChild("Support") :: Attachment?
	gripL = if g then g.WorldPosition else Vector3.zero
	supportL = if s then s.WorldPosition else gripL + Vector3.new(0, 0, -0.3 / M)
	viewKind = wp.kind
	if wp.kind == "pistol" then
		supportL = gripL + Vector3.new(-0.025 / M, -0.01 / M, -0.01 / M) -- a esquerda abraça a direita
		magL = gripL + Vector3.new(0, -0.07 / M, 0.01 / M)
		chargeL = viewSight + Vector3.new(0, 0.01 / M, 0.02 / M) -- ferrolho (corrediça)
	else
		magL = gripL:Lerp(supportL, 0.5) + Vector3.new(0, -0.04 / M, 0)
		chargeL = gripL:Lerp(supportL, 0.25) + Vector3.new(0.035 / M, 0.06 / M, 0)
	end
	local kind = m:GetAttribute("SightKind")
	local mm = m:GetAttribute("SightMm")
	if front and type(kind) == "string" and type(mm) == "number" and kind ~= "" then
		crispSights(m, viewSight, front.WorldPosition, kind, mm)
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	m.Parent = camera
	view = m
end

local function showView(): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil
		and hum.Health > 0
		and hum.SeatPart == nil
		and player:GetAttribute("Downed") ~= true
		and player:GetAttribute("Binoculars") ~= true
		-- 3ª pessoa (D-68, ThirdPerson.client): a câmera está atrás do ombro e o corpo aparece com
		-- a arma "Weapon" do personagem; mirando, volta a 1ª pessoa e o atributo fica false
		and player:GetAttribute("ThirdPersonView") ~= true
		and Input.state.menus == 0
		and not Input.state.map
end

local function muzzleOf(model: Instance?): Vector3?
	local w = model and model:FindFirstChild("Weapon")
	local primary = w and (w :: Model).PrimaryPart
	local a = primary and primary:FindFirstChild("Muzzle") :: Attachment?
	return if a then a.WorldPosition else nil
end

RunService:BindToRenderStep("VT65ViewModel", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	setView(player:GetAttribute("EquippedWeapon") :: string?)
	local v = view
	if not v then
		if arms then
			arms:PivotTo(CFrame.new(0, -1e4, 0))
		end
		return
	end
	ensureArms()
	if not showView() then
		v:PivotTo(CFrame.new(0, -1e4, 0)) -- fora da vista (sem recriar a arma)
		if arms then
			arms:PivotTo(CFrame.new(0, -1e4, 0))
		end
		clearMags()
		return
	end
	local rp = if reloadDur > 0 then (os.clock() - reloadT0) / reloadDur else 2
	local reloading = rp < 1
	if not reloading and reloadDur > 0 then
		reloadDur = 0
		clearMags()
	end
	-- recarregando, a arma sai do ombro
	local aiming = player:GetAttribute("Aiming") == true and not reloading
	aimT += ((if aiming then 1 else 0) - aimT) * math.min(1, dt * 12)
	kick = math.max(0, kick - dt * 7)
	local ads = CFrame.new(0, 0, -viewEye / M) * viewAlign * CFrame.new(-viewSight)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local speed = if root
		then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude * M
		else 0
	bobT += dt * math.clamp(speed, 0, 6) * 2.2
	local amp = math.clamp(speed / 3, 0, 1) * (1 - aimT) * 0.008 / M
	local bob = CFrame.new(math.sin(bobT) * amp, math.abs(math.cos(bobT)) * amp, 0)
	-- D-81: mirando, o coice só empurra a arma para trás (a subida da boca já vai na câmera,
	-- WeaponController). Antes a arma girava até 4° acima da câmera: o tiro seguinte saía no centro
	-- da tela e não onde a massa de mira mostrava ("a bala tem que sair em cima do risquinho").
	local recoil = CFrame.new(0, 0, kick * 0.05 / M) * CFrame.Angles(kick * math.rad(4) * (1 - aimT), 0, 0)
	-- recarga: inclina a arma para mostrar o encaixe; tapa no carregador; puxa o ferrolho
	local pose = CFrame.identity
	if reloading then
		local w = smooth(rp / 0.12) * (1 - smooth((rp - 0.86) / 0.14))
		local tilt = CFrame.new(0.02 / M, -0.07 / M, 0.03 / M)
			* CFrame.Angles(math.rad(-10), math.rad(10), math.rad(30))
		pose = CFrame.identity:Lerp(tilt, w)
		local slap = math.max(0, 1 - math.abs(rp - 0.66) / 0.03)
		local pull = smooth((rp - 0.79) / 0.06) * (1 - smooth((rp - 0.86) / 0.05))
		pose *= CFrame.new(0, slap * 0.008 / M, pull * 0.012 / M)
	end
	-- arremessando: a arma desce e sai da frente
	local throwDown = if throwT0 >= 0 then smooth(((os.clock() - throwT0) / THROW_S) / 0.15) else 0
	if throwT0 >= 0 then
		local tp = (os.clock() - throwT0) / THROW_S
		throwDown *= 1 - smooth((tp - 0.8) / 0.2)
		pose *= CFrame.new(0.05 / M * throwDown, -0.22 / M * throwDown, 0.05 / M * throwDown) * CFrame.Angles(
			math.rad(-35) * throwDown,
			math.rad(20) * throwDown,
			0
		)
	end
	local wcf = camera.CFrame * HIP:Lerp(ads, aimT) * bob * recoil * pose
	v:PivotTo(wcf)
	-- braços
	local rot = wcf.Rotation
	local handR = wcf * (gripL + Vector3.new(0.012 / M, 0, 0.015 / M))
	local handL = wcf * (supportL + Vector3.new(0, -0.025 / M, 0))
	if reloading then
		local keys = reloadKeys()
		local function world(k: Key): Vector3
			return if k.s == "c" then camera.CFrame * k.p else wcf * k.p
		end
		for i = 1, #keys - 1 do
			local a, b = keys[i], keys[i + 1]
			if rp >= a.t and rp < b.t then
				handL = world(a):Lerp(world(b), smooth((rp - a.t) / (b.t - a.t)))
				break
			end
		end
		-- carregador velho: sai com a mão (0,13–0,25) e cai; o novo vem da cartucheira (0,40–0,64)
		if viewKind ~= "launcher" then
			local magOff = Vector3.new(0, 0.07 / M, 0)
			if rp >= 0.13 and rp < 0.25 then
				oldMag = oldMag or magPart(viewKind)
				local om = oldMag :: BasePart
				om.CFrame = rot + (handL + rot * magOff)
			elseif rp >= 0.25 and oldMag and not magDropped then
				magDropped = true
				local om = oldMag :: BasePart
				oldMag = nil
				om.Anchored = false
				om.CanCollide = true
				om.Parent = fx
				om.AssemblyLinearVelocity = rot * Vector3.new(-0.6, -1.5, 0.2) / M
				task.delay(4, function()
					om:Destroy()
				end)
			end
			if rp >= 0.4 and rp < 0.64 then
				newMag = newMag or magPart(viewKind)
				local nm = newMag :: BasePart
				nm.CFrame = rot + (handL + rot * magOff)
			elseif rp >= 0.64 and newMag then
				newMag:Destroy() -- encaixado: some dentro da arma
				newMag = nil
			end
		end
	end
	-- arremesso: a mão direita larga a arma; a esquerda vai ao pino
	local _, throwHand, pulling = throwState(handR)
	local handRot = rot
	if throwHand then
		handR = throwHand
		handRot = camera.CFrame.Rotation
		if pulling then
			handL = handL:Lerp(throwHand + camera.CFrame:VectorToWorldSpace(Vector3.new(-0.05, 0.03, 0) / M), 0.85)
		end
	end
	local mr, ml = armBits.MaoR, armBits.MaoL
	if mr and ml then
		mr.CFrame = handRot + handR
		ml.CFrame = rot + handL
		local cam = camera.CFrame
		forearm(handR + rot * Vector3.new(0, -0.03 / M, 0.05 / M), cam * ELBOW_R, "R")
		forearm(handL + rot * Vector3.new(0, -0.01 / M, 0.05 / M), cam * ELBOW_L, "L")
	end
end)

-- ===== clarão de boca =====
local FLASH = Color3.fromRGB(255, 196, 110)
local function flash(at: Vector3)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = FLASH
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * (0.1 / M)
	p.Transparency = 0.2
	p.CFrame = CFrame.new(at)
	local light = Instance.new("PointLight")
	light.Color = FLASH
	light.Brightness = 5
	light.Range = 12 / M
	light.Shadows = false
	light.Parent = p
	p.Parent = fx
	task.delay(0.05, function()
		p:Destroy()
	end)
end

-- ===== impacto =====
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local function impactColor(r: RaycastResult): (Color3, boolean)
	local mat = r.Instance:GetAttribute("Material")
	if mat == "PaddyWater" or r.Material == Enum.Material.Water then
		return Color3.fromRGB(200, 204, 198), true
	elseif mat == "Bamboo" then
		return Color3.fromRGB(140, 112, 72), false
	elseif mat == "Thatch" then
		return Color3.fromRGB(172, 152, 96), false
	elseif r.Material == Enum.Material.Sand then
		return Color3.fromRGB(200, 186, 150), false
	end
	return Color3.fromRGB(112, 92, 66), false
end

local function puff(r: RaycastResult)
	local color, water = impactColor(r)
	local n = r.Normal
	local right = if math.abs(n.Y) > 0.9 then Vector3.xAxis else n:Cross(Vector3.yAxis).Unit
	local a = Instance.new("Attachment")
	a.CFrame = CFrame.fromMatrix(r.Position, right, n) -- no Terrain (origem); +Y = normal = emissão
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12 / M), NumberSequenceKeypoint.new(1, 0.5 / M) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.35, 0.8)
	e.Speed = NumberRange.new(1.5 / M, (if water then 5 else 3) / M)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Acceleration = Vector3.new(0, if water then -9.8 / M else -1 / M, 0)
	e.Drag = 4
	e.Rate = 0
	e.Enabled = false
	e.LightInfluence = 1
	e.Parent = a
	a.Parent = workspace.Terrain
	e:Emit(if water then 16 else 10)
	task.delay(1.2, function()
		a:Destroy()
	end)
end

local function isBody(inst: Instance): boolean
	local model = inst:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Refaz a trajetória (mesma semente). Devolve os pontos e o impacto.
local function trace(shot: any, ignore: { Instance }): ({ Vector3 }, RaycastResult?)
	local pts: { Vector3 } = {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result: RaycastResult? = nil
	Ballistics.trace({
		ox = shot.ox * M,
		oy = shot.oy * M,
		oz = shot.oz * M,
		dx = shot.dx,
		dy = shot.dy,
		dz = shot.dz,
		weaponId = shot.w,
		seed = shot.seed,
		maxTime = 1.2,
	}, function(ax, ay, az, bx, by, bz)
		local a = Vector3.new(ax, ay, az) / M
		table.insert(pts, a)
		local r = workspace:Raycast(a, Vector3.new(bx - ax, by - ay, bz - az) / M, params)
		if r then
			table.insert(pts, r.Position)
			result = r
			return { x = r.Position.X * M, y = r.Position.Y * M, z = r.Position.Z * M }
		end
		return nil
	end)
	return pts, result
end

local function impactOf(shot: any, ignore: { Instance })
	local _, r = trace(shot, ignore)
	if r and not isBody(r.Instance) and (r.Position - camera.CFrame.Position).Magnitude * M < IMPACT_MAX_M then
		puff(r)
	end
end

-- ===== traçante =====
local function tracer(shot: any, color: Color3)
	local ignore: { Instance } = { fx, camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local pts = trace(shot, ignore)
	if #pts < 2 then
		return
	end
	-- sai da boca do cano, não do olho
	local start = if shot.by then muzzleOf(shot.by) else (if view then muzzleOf(camera) else nil)
	if start then
		pts[1] = start
	end
	local streak = Instance.new("Part")
	streak.Anchored, streak.CanCollide, streak.CanQuery, streak.CanTouch, streak.CastShadow =
		true, false, false, false, false
	streak.Material = Enum.Material.Neon
	streak.Color = color
	streak.Parent = fx
	local STEP = 1 / 120 -- passo do Ballistics.trace
	local LEN_S = 0.004 -- comprimento do risco, em tempo de voo (~3 m)
	local t = 0
	local function at(time: number): Vector3
		local f = math.clamp(time / STEP, 0, #pts - 1)
		local i = math.floor(f)
		local a, b = pts[i + 1], pts[math.min(i + 2, #pts)]
		return a:Lerp(b, f - i)
	end
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt: number)
		t += dt
		if t / STEP >= #pts - 1 then
			conn:Disconnect()
			streak:Destroy()
			return
		end
		local head, tail = at(t), at(t - LEN_S)
		local len = (head - tail).Magnitude
		if len < 0.01 then
			return
		end
		streak.Size = Vector3.new(0.04 / M, 0.04 / M, len)
		streak.CFrame = CFrame.lookAt((head + tail) / 2, head)
	end)
end
Bus.on("tracer", tracer)

-- ===== tiros =====
Bus.on("shot_fired", function(shot: any)
	kick = 1
	-- em 3ª pessoa o clarão sai da arma do personagem (a de 1ª pessoa fica escondida)
	local muzzle = if player:GetAttribute("ThirdPersonView") == true
		then muzzleOf(player.Character)
		elseif view then muzzleOf(camera)
		else nil
	flash(muzzle or (camera.CFrame.Position + camera.CFrame.LookVector * (0.8 / M)))
	local ignore: { Instance } = { fx, camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	impactOf(shot, ignore)
end)

Net.unreliable("Combat_Tracer").OnClientEvent:Connect(function(shot: any)
	local origin = Vector3.new(shot.ox, shot.oy, shot.oz)
	local dM = (origin - camera.CFrame.Position).Magnitude * M
	if dM < 400 then
		local dir = Vector3.new(shot.dx, shot.dy, shot.dz).Unit
		flash(muzzleOf(shot.by) or (origin + dir * (0.8 / M)))
	end
	if dM < IMPACT_MAX_M + 50 then
		local ignore: { Instance } = { fx, camera }
		if typeof(shot.by) == "Instance" then
			table.insert(ignore, shot.by)
		end
		impactOf(shot, ignore)
	end
end)
