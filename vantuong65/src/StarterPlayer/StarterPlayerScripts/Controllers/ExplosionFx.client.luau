--!strict
-- Efeito visual das explosões (D-77, pedido do dono: "granadas com gráficos"). Antes a explosão era
-- só som e cratera. Agora, no aviso Fire_Impact do servidor (ExplosionService):
-- - clarão (luz forte por 0,15 s) e bola de fogo curta, que somem rápido (explosivo militar quase
--   não faz chama; a nuvem é de terra e fumaça);
-- - nuvem de terra marrom que sobe e se espalha, e fumaça cinza que fica alguns segundos;
-- - torrões de terra caindo e faíscas;
-- - na água (arrozal, riacho) uma coluna de água branca no lugar da terra;
-- - câmera treme perto (cai com a distância);
-- O tamanho vem do tipo (granada, morteiro, canhão, bomba). Tudo local e apagado depois.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GrenadeArt = require(ReplicatedStorage.Shared.GrenadeArt)
local Net = require(ReplicatedStorage.Shared.Net)

local M = 0.28
local camera = workspace.CurrentCamera
local TEX = {
	core = "rbxasset://textures/particles/explosion01_core_main.dds",
	smoke = "rbxasset://textures/particles/explosion01_smoke_main.dds",
	dust = "rbxasset://textures/particles/smoke_main.dds",
	sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	square = "rbxasset://textures/particles/SquareParticle.png",
}
-- escala por tipo (1 = granada de mão)
local SCALE: { [string]: number } = {
	grenade_us = 1,
	grenade_vc = 0.9,
	rocket_35 = 1.3,
	pg2 = 1.3,
	he_90 = 1.6,
	heat_106 = 1.6,
	mortar_81 = 1.8,
	mortar_82 = 1.8,
	naval_5in = 2.8,
	bomb_250lb = 3.6,
}

local fx = Instance.new("Folder")
fx.Name = "VT65Explosoes"
fx.Parent = workspace

local function seq(...: number): NumberSequence
	local a = { ... }
	local keys = {}
	for i = 1, #a, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- água sob o ponto? (lâmina do arrozal ou água do terreno)
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
local function inWater(pos: Vector3): boolean
	waterParams.FilterDescendantsInstances = { fx, camera }
	waterParams.IgnoreWater = false
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), waterParams)
	if not hit then
		return false
	end
	return hit.Material == Enum.Material.Water
		or hit.Instance:GetAttribute("Material") == "PaddyWater"
		or hit.Instance.Name == "PaddyWater"
end

-- tremor da câmera: soma dos pedidos, cai sozinho
local shake = 0
RunService:BindToRenderStep("VT65Tremor", Enum.RenderPriority.Camera.Value + 5, function(dt: number)
	if shake <= 0.001 then
		shake = 0
		return
	end
	local t = os.clock() * 40
	local a = shake * math.rad(1.6)
	camera.CFrame *= CFrame.Angles(math.noise(t, 1) * a, math.noise(t, 2) * a, math.noise(t, 3) * a * 0.5)
	shake = math.max(0, shake - dt * 2.5)
end)

local function explode(id: string, pos: Vector3)
	local s = SCALE[id] or 1.5
	local dM = (pos - camera.CFrame.Position).Magnitude * M
	if dM > 1500 then
		return
	end
	local water = inWater(pos)
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(pos + Vector3.new(0, 0.3 / M, 0))
	anchor.Parent = fx
	Debris:AddItem(anchor, 9)
	-- clarão
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 196, 120)
	light.Brightness = 10
	light.Range = math.min(60, 8 * s / M)
	light.Shadows = false
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.18 * s, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	-- bola de fogo: curta e baixa
	local ball = Instance.new("Part")
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch, ball.CastShadow = true, false, false, false, false
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 170, 70)
	ball.Size = Vector3.one * (0.6 * s / M)
	ball.CFrame = anchor.CFrame
	ball.Parent = fx
	TweenService:Create(ball, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * (2.4 * s / M),
		Transparency = 1,
		Color = Color3.fromRGB(120, 70, 40),
	}):Play()
	Debris:AddItem(ball, 0.3)
	-- núcleo
	emitter(anchor, {
		Texture = TEX.core,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 150), Color3.fromRGB(255, 120, 40)),
		Size = seq(0, 1.2 * s / M, 1, 3.2 * s / M),
		Transparency = seq(0, 0.1, 1, 1),
		Lifetime = NumberRange.new(0.18, 0.3),
		Speed = NumberRange.new(2 / M, 5 / M),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
	}):Emit(math.floor(5 * s))
	-- faíscas
	emitter(anchor, {
		Texture = TEX.sparks,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 120)),
		Size = seq(0, 0.12 / M, 1, 0),
		Lifetime = NumberRange.new(0.3, 0.7),
		Speed = NumberRange.new(10 / M, 22 / M),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -9.8 / M, 0),
		Drag = 2,
	}):Emit(math.floor(18 * s))
	if water then
		-- coluna de água: sobe branca e cai
		emitter(anchor, {
			Texture = TEX.dust,
			Color = ColorSequence.new(Color3.fromRGB(235, 238, 236), Color3.fromRGB(190, 196, 190)),
			-- coluna estreita: granada levanta ~3–5 m de água, morteiro ~10 m (no Studio a 1ª versão
			-- virou uma nuvem branca do tamanho de um prédio)
			Size = seq(0, 0.35 * s / M, 0.5, 0.9 * s / M, 1, 1.3 * s / M),
			Transparency = seq(0, 0.1, 0.7, 0.45, 1, 1),
			Lifetime = NumberRange.new(0.9, 1.5),
			Speed = NumberRange.new(5 * s / M, 9 * s / M),
			SpreadAngle = Vector2.new(9, 9),
			Acceleration = Vector3.new(0, -9.8 / M, 0),
			Drag = 0.6,
			Rotation = NumberRange.new(0, 360),
		}):Emit(math.floor(26 * s))
		emitter(anchor, {
			Texture = TEX.square,
			Color = ColorSequence.new(Color3.fromRGB(220, 226, 226)),
			Size = seq(0, 0.08 / M, 1, 0.03 / M),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(6 / M, 14 / M),
			SpreadAngle = Vector2.new(50, 50),
			Acceleration = Vector3.new(0, -9.8 / M, 0),
		}):Emit(math.floor(40 * s))
	else
		-- terra: nuvem marrom que sobe e torrões caindo
		-- (a textura explosion01_smoke do Roblox é quase preta: a nuvem saía uma bola escura)
		emitter(anchor, {
			Texture = TEX.dust,
			Color = ColorSequence.new(Color3.fromRGB(150, 122, 92), Color3.fromRGB(176, 164, 148)),
			Size = seq(0, 0.7 * s / M, 0.4, 2.2 * s / M, 1, 3.4 * s / M),
			Transparency = seq(0, 0.2, 0.6, 0.6, 1, 1),
			Lifetime = NumberRange.new(2.5, 4.5),
			Speed = NumberRange.new(4 * s / M, 9 * s / M),
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0.3 / M, -1 / M, 0),
			Drag = 2.2,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
		}):Emit(math.floor(16 * s))
		emitter(anchor, {
			Texture = TEX.square,
			Color = ColorSequence.new(Color3.fromRGB(70, 56, 40), Color3.fromRGB(96, 78, 56)),
			Size = seq(0, 0.1 / M, 1, 0.06 / M),
			Lifetime = NumberRange.new(1.0, 1.8),
			Speed = NumberRange.new(7 * s / M, 15 * s / M),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = Vector3.new(0, -9.8 / M, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-200, 200),
		}):Emit(math.floor(36 * s))
		-- poeira rasteira (onda de choque levantando o chão)
		emitter(anchor, {
			Texture = TEX.dust,
			Color = ColorSequence.new(Color3.fromRGB(150, 132, 108)),
			Size = seq(0, 1 * s / M, 1, 3 * s / M),
			Transparency = seq(0, 0.35, 1, 1),
			Lifetime = NumberRange.new(1.2, 2.2),
			Speed = NumberRange.new(6 * s / M, 10 * s / M),
			SpreadAngle = Vector2.new(85, 85),
			Drag = 3,
			Rotation = NumberRange.new(0, 360),
		}):Emit(math.floor(12 * s))
	end
	-- fumaça cinza que fica
	emitter(anchor, {
		Texture = TEX.dust,
		Color = ColorSequence.new(Color3.fromRGB(120, 116, 110), Color3.fromRGB(168, 166, 160)),
		Size = seq(0, 1.2 * s / M, 1, 4.5 * s / M),
		Transparency = seq(0, 0.5, 0.5, 0.7, 1, 1),
		Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(1 / M, 3 / M),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0.4 / M, 0.6 / M, 0.2 / M),
		Drag = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-10, 10),
	}):Emit(math.floor(8 * s))
	-- tremor: forte a poucos metros, some a ~50 m da granada (mais longe para bomba)
	local reach = 45 * s
	if dM < reach then
		shake = math.min(1.5, shake + (1 - dM / reach) ^ 2 * (0.6 + 0.25 * s))
	end
end

Net.unreliable("Fire_Impact").OnClientEvent:Connect(function(e: any)
	if type(e) == "table" and type(e.x) == "number" then
		explode(tostring(e.id), Vector3.new(e.x, e.y, e.z))
	end
end)

-- ===== granada no ar e no chão =====
-- O servidor simula um núcleo de 1 stud (invisível); aqui a granada desenhada segue o núcleo,
-- girando com ele, e encosta no chão quando para (senão ficaria 10 cm no ar).
type Live = { core: BasePart, model: Model, r: number }
local live: { [Instance]: Live } = {}
local restParams = RaycastParams.new()
restParams.FilterType = Enum.RaycastFilterType.Exclude

local function track(g: Instance)
	if not g:IsA("Model") or live[g] then
		return
	end
	local core = g:WaitForChild("Nucleo", 3)
	if not core or not core:IsA("BasePart") then
		return
	end
	local kind = g:GetAttribute("Kind")
	local faction = g:GetAttribute("Faction")
	local model, r = GrenadeArt.build(
		if type(kind) == "string" then kind else "frag",
		if type(faction) == "string" then faction else nil
	)
	model.Parent = fx
	live[g] = { core = core, model = model, r = r }
end

task.spawn(function()
	local folder = workspace:WaitForChild("Granadas", 120)
	if folder then
		for _, g in folder:GetChildren() do
			task.spawn(track, g)
		end
		folder.ChildAdded:Connect(track)
	end
end)

RunService.RenderStepped:Connect(function()
	for g, l in live do
		if g.Parent == nil or l.core.Parent == nil then
			l.model:Destroy()
			live[g] = nil
			continue
		end
		local pos = l.core.Position
		restParams.FilterDescendantsInstances = { fx, g, camera }
		local hit = workspace:Raycast(pos, Vector3.new(0, -0.9, 0), restParams)
		local at = if hit and (pos - hit.Position).Magnitude < 0.62 then hit.Position + hit.Normal * l.r else pos
		l.model:PivotTo(CFrame.new(at) * l.core.CFrame.Rotation)
	end
end)
