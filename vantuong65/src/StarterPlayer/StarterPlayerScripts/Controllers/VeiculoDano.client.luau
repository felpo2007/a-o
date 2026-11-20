--!strict
-- Dano, explosão e destroço dos veículos vistos por todos (D-197; prompt de jogabilidade, item 16).
-- Regras em Shared/VeiculoDano; o dano é do servidor (VehicleService.destroyVehicle), aqui só o efeito,
-- local e apagado depois:
-- - estágio pela integridade: fumaça clara do motor (≤ 60), fogo e fumaça escura (≤ 25);
-- - destruído, visto ao vivo: clarão, bola de fogo, fumaça preta subindo, poeira no chão, alguns
--   pedaços de chapa voando (contados pelo porte) e o som da explosão do tamanho do veículo;
-- - o destroço queima e fumega até o servidor tirá-lo (30 s). Quem chega depois (streaming) vê só o
--   destroço, sem a explosão.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local VeiculoDano = require(ReplicatedStorage.Shared.VeiculoDano)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local M = 0.28
local camera = workspace.CurrentCamera
local TEX = {
	core = "rbxasset://textures/particles/explosion01_core_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	dust = "rbxasset://textures/particles/smoke_main.dds",
	sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "VT65VeiculoDano"
fxFolder.Parent = workspace

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

local function porteDe(model: Model): VeiculoDano.Explosao
	local spec = Vehicles.SPECS[tostring(model:GetAttribute("Spec"))]
	local p = VeiculoDano.porte(if spec then spec.massKg else 5000)
	return VeiculoDano.EXPLOSAO[p]
end

-- ===== a explosão (uma vez, ao vivo) =====
local function explode(model: Model, chassis: BasePart)
	local E = porteDe(model)
	local s = E.escala
	local pos = chassis.Position + Vector3.new(0, chassis.Size.Y * 0.3, 0)
	if (pos - camera.CFrame.Position).Magnitude * M > 1500 then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = fxFolder
	Debris:AddItem(anchor, 12)
	-- clarão
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 100)
	light.Brightness = 14
	light.Range = math.min(60, E.luz / M)
	light.Shadows = false
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	-- bola de fogo: o combustível e a munição queimando (maior e mais lenta que a de um projétil)
	local ball = Instance.new("Part")
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch, ball.CastShadow = true, false, false, false, false
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 160, 60)
	ball.Size = Vector3.one * (0.8 * s / M)
	ball.CFrame = anchor.CFrame
	ball.Parent = fxFolder
	TweenService:Create(ball, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * (2.6 * s / M),
		Transparency = 1,
		Color = Color3.fromRGB(110, 50, 25),
	}):Play()
	Debris:AddItem(ball, 0.5)
	emitter(anchor, {
		Texture = TEX.core,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 140), Color3.fromRGB(255, 100, 30)),
		Size = seq(0, 1.2 * s / M, 1, 3.4 * s / M),
		Transparency = seq(0, 0.05, 1, 1),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(2 / M, 6 / M),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
	}):Emit(math.floor(6 * s))
	-- faíscas
	emitter(anchor, {
		Texture = TEX.sparks,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 110)),
		Size = seq(0, 0.14 / M, 1, 0),
		Lifetime = NumberRange.new(0.5, 1.2),
		Speed = NumberRange.new(10 / M, 26 / M),
		SpreadAngle = Vector2.new(80, 80),
		Acceleration = Vector3.new(0, -9.8 / M, 0),
		Drag = 1.5,
	}):Emit(math.floor(14 * s))
	-- fumaça preta subindo (óleo e borracha)
	emitter(anchor, {
		Texture = TEX.dust,
		Color = ColorSequence.new(Color3.fromRGB(34, 32, 30), Color3.fromRGB(70, 68, 64)),
		Size = seq(0, 1.4 * s / M, 0.5, 3.4 * s / M, 1, 5 * s / M),
		Transparency = seq(0, 0.2, 0.6, 0.55, 1, 1),
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(3 / M, 7 / M),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0.3 / M, 1.2 / M, 0),
		Drag = 1.2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-15, 15),
	}):Emit(math.floor(9 * s))
	-- poeira rasteira (a onda de choque levanta o chão em volta)
	emitter(anchor, {
		Texture = TEX.dust,
		Color = ColorSequence.new(Color3.fromRGB(150, 132, 108)),
		Size = seq(0, 1 * s / M, 1, 3.2 * s / M),
		Transparency = seq(0, 0.35, 1, 1),
		Lifetime = NumberRange.new(1.2, 2.2),
		Speed = NumberRange.new(7 * s / M, 11 * s / M),
		SpreadAngle = Vector2.new(88, 88),
		Drag = 3,
		Rotation = NumberRange.new(0, 360),
	}):Emit(math.floor(10 * s))
	-- pedaços de chapa: poucos (contados pelo porte), com física local, e somem em 4 s
	local rng = Random.new()
	for _ = 1, E.fragmentos do
		local p = Instance.new("Part")
		p.Name = "Chapa"
		p.Size = Vector3.new(rng:NextNumber(0.15, 0.45), 0.03, rng:NextNumber(0.12, 0.35)) / M
		p.Color = Color3.fromRGB(42, 40, 36)
		p.Material = Enum.Material.CorrodedMetal
		p.CanQuery, p.CanTouch = false, false
		p.CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
		p.Parent = fxFolder
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.6, 1.4), rng:NextNumber(-1, 1)).Unit
		p.AssemblyLinearVelocity = dir * rng:NextNumber(8, 16) / M
		p.AssemblyAngularVelocity =
			Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		Debris:AddItem(p, 4)
	end
	-- som do tamanho do veículo
	local id = AssetIds.Sounds.explosion
	if type(id) == "number" and id ~= 0 then
		local snd = Instance.new("Sound")
		snd.SoundId = "rbxassetid://" .. id
		snd.Volume = E.volume
		snd.PlaybackSpeed = E.tom
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 8 / M
		snd.RollOffMaxDistance = 900 / M
		snd.Parent = anchor
		snd:Play()
	end
end

-- ===== fumaça e fogo pelo dano, e o destroço =====
type Watch = {
	model: Model,
	chassis: BasePart,
	att: Attachment,
	smoke: ParticleEmitter,
	fire: ParticleEmitter,
	estagio: string,
	destruidoT: number?, -- os.clock da destruição vista (o destroço queima a partir daí)
	fumacaS: number,
}
local watched: { [Model]: Watch } = {}

local function aplicar(w: Watch)
	local est =
		VeiculoDano.estagio(w.model:GetAttribute("Integrity") :: number?, w.model:GetAttribute("Destroyed") == true)
	w.estagio = est
	if est == "inteiro" then
		w.smoke.Enabled, w.fire.Enabled = false, false
	elseif est == "fumaca" then
		w.smoke.Color = ColorSequence.new(Color3.fromRGB(150, 148, 142), Color3.fromRGB(190, 188, 182))
		w.smoke.Rate = 6
		w.smoke.Enabled, w.fire.Enabled = true, false
	elseif est == "fogo" then
		w.smoke.Color = ColorSequence.new(Color3.fromRGB(46, 44, 40), Color3.fromRGB(96, 92, 86))
		w.smoke.Rate = 10
		w.fire.Rate = 18
		w.smoke.Enabled, w.fire.Enabled = true, true
	else
		w.smoke.Color = ColorSequence.new(Color3.fromRGB(28, 26, 24), Color3.fromRGB(70, 66, 60))
		w.smoke.Enabled, w.fire.Enabled = true, true
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") or watched[model] or not model:GetAttribute("VehicleId") then
		return
	end
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "VT65Dano"
	-- em cima do motor: a traseira do chassi (frente em −Z)
	att.Position = Vector3.new(0, chassis.Size.Y / 2, chassis.Size.Z * 0.3)
	att.Parent = chassis
	local smoke = emitter(att, {
		Texture = TEX.dust,
		Size = seq(0, 0.6 / M, 1, 2.6 / M),
		Transparency = seq(0, 0.35, 1, 1),
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(1.5 / M, 3 / M),
		SpreadAngle = Vector2.new(14, 14),
		Acceleration = Vector3.new(0.4 / M, 0.8 / M, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-12, 12),
	})
	local fire = emitter(att, {
		Texture = TEX.fire,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(230, 80, 30)),
		Size = seq(0, 0.5 / M, 1, 0.1 / M),
		Transparency = seq(0, 0.15, 1, 1),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(1 / M, 2.5 / M),
		SpreadAngle = Vector2.new(20, 20),
		Acceleration = Vector3.new(0, 2 / M, 0),
	})
	local w: Watch = {
		model = model,
		chassis = chassis,
		att = att,
		smoke = smoke,
		fire = fire,
		estagio = "inteiro",
		destruidoT = if model:GetAttribute("Destroyed") then os.clock() else nil,
		fumacaS = porteDe(model).fumacaS,
	}
	watched[model] = w
	aplicar(w)
	model:GetAttributeChangedSignal("Integrity"):Connect(function()
		aplicar(w)
	end)
	model:GetAttributeChangedSignal("Destroyed"):Connect(function()
		if model:GetAttribute("Destroyed") == true and not w.destruidoT then
			w.destruidoT = os.clock()
			explode(model, chassis)
		end
		aplicar(w)
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			watched[model] = nil
		end
	end)
end

-- o destroço queima e fumega cada vez menos (4 vezes por segundo)
local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	if acc < 0.25 then
		return
	end
	acc = 0
	for _, w in watched do
		local t0 = w.destruidoT
		if t0 and w.estagio == "destroco" then
			local fumaca, fogo = VeiculoDano.queima(os.clock() - t0, w.fumacaS)
			w.smoke.Rate = 14 * fumaca
			w.fire.Rate = 24 * fogo
			w.smoke.Enabled, w.fire.Enabled = fumaca > 0.02, fogo > 0.02
		end
	end
end)

local function hook(folder: Instance)
	for _, m in folder:GetChildren() do
		task.spawn(watch, m)
	end
	folder.ChildAdded:Connect(function(m)
		-- a peça Chassis pode chegar depois (streaming): espera um pouco
		task.delay(0.5, watch, m)
	end)
end

local vehicles = workspace:FindFirstChild("Vehicles")
if vehicles then
	hook(vehicles)
else
	task.spawn(function()
		hook(workspace:WaitForChild("Vehicles"))
	end)
end
