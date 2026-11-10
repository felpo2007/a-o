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
local HIP = CFrame.new(0.17 / M, -0.19 / M, -0.34 / M) * CFrame.Angles(0, math.rad(4), 0)
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
		return
	end
	if not showView() then
		v:PivotTo(CFrame.new(0, -1e4, 0)) -- fora da vista (sem recriar a arma)
		return
	end
	local aiming = player:GetAttribute("Aiming") == true
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
	local recoil = CFrame.new(0, 0, kick * 0.05 / M) * CFrame.Angles(kick * math.rad(4), 0, 0)
	v:PivotTo(camera.CFrame * HIP:Lerp(ads, aimT) * bob * recoil)
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
	local muzzle = if view then muzzleOf(camera) else nil
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
