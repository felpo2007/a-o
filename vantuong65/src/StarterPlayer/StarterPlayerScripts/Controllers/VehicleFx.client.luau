--!strict
-- Visual, efeitos e som dos veículos (pedido do dono, 2026-11-11: "movimentação realista e visualmente
-- agradável" e "coloque poeira, vento etc."). Tudo no cliente e só perto da câmera:
-- - mola da carroceria: a arte (presa ao chassi pelo Motor6D "ArtMount", VehicleService) levanta o
--   nariz na arrancada, mergulha na freada, rola para fora na curva, balança e assenta; acompanha o
--   chão pelas 4 pontas, afunda na lama e no arrozal e, boiando, sobe e desce na água;
-- - lagarta: faixas finas que correm no laço da lagarta medido na malha (VehicleDrive.ART), cada
--   lado na sua velocidade (na curva e no giro no lugar elas andam em sentidos opostos);
-- - UH-34D: disco de desfoque e pás do rotor principal e do de cauda, que partem e param devagar; o
--   disco inclina com a aceleração; downwash de poeira, capim ou água debaixo dele;
-- - poeira na terra seca e na areia, capim e folhas, barro na lama, respingo no arrozal, esteira e
--   espuma na água, fumaça de escapamento que engrossa na aceleração e solta um bafo na partida;
--   tudo levado pelo vento (WindAffectsDrag + workspace.GlobalWind do Ambiente.client);
-- - som do motor com tom e volume pela rotação e pela carga (AssetIds.Sounds); o laço antigo do
--   AudioController é calado no veículo para não tocarem dois motores.
-- Do motorista local vem o estado exato (VehicleLive.drive); dos outros, a telemetria (NetRpm,
-- NetLoad) e a física replicada. Detalhe gráfico (Input.settings.gfxDetail) reduz partículas e faixas.
-- Limite do Roblox: 200 locais por função contando o nível de cima. O estado fica em tabelas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local VehicleDrive = require(ReplicatedStorage.Shared.VehicleDrive)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles) :: any
local Input = require(script.Parent.Input)
local VehicleLive = require(script.Parent.VehicleLive)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28

local CFG = {
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	square = "rbxasset://textures/particles/SquareParticle.png",
	nearStuds = 80 / M, -- faixas, 4 pontas, rotor detalhado, sondagem rápida
	midStuds = 220 / M, -- mola, poeira, fumaça, downwash
	soundStuds = 600 / M,
	rampStuds = 1.6, -- rampas do VehicleService (o casco vai até a ponta delas)
	idleRpm = 0.25,
	-- mola da fuselagem do UH-34D (trem de pouso e balanço sob o rotor): PLACEHOLDER
	heliSpring = {
		pitchHz = 0.8,
		rollHz = 0.9,
		heaveHz = 1.8,
		zeta = 0.45,
		pitchDegPerG = 2,
		rollDegPerG = 2,
		heaveMPerG = 0.08,
	} :: VehicleDrive.SpringParams,
	engineSound = { m48a3 = "engine_tank", ontos = "engine_tank", lvtp5 = "engine_amtrac", uh34d = "uh34d_loop" },
	diesel = { m48a3 = true } :: { [string]: boolean }, -- AVDS-1790-2 a diesel; Ontos e LVTP-5 a gasolina
}

-- cores por chão (poeira/névoa e detritos: torrão, capim, folha, gota)
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local COLORS = {
	dust = {
		road = rgb(176, 160, 132),
		earth = rgb(156, 116, 84), -- laterita avermelhada da costa
		grass = rgb(164, 152, 114),
		forest = rgb(126, 108, 82),
		sand = rgb(206, 188, 152),
		mud = rgb(104, 86, 62),
		paddy = rgb(196, 200, 186),
		water = rgb(226, 230, 224),
	} :: { [string]: Color3 },
	debris = {
		road = rgb(120, 104, 84),
		earth = rgb(112, 84, 60),
		grass = rgb(104, 118, 56),
		forest = rgb(96, 82, 50),
		sand = rgb(192, 172, 136),
		mud = rgb(72, 58, 42),
		paddy = rgb(78, 70, 50),
		water = rgb(214, 222, 220),
	} :: { [string]: Color3 },
	bar = rgb(46, 44, 40),
	barMud = rgb(86, 70, 50),
}

local folder = Instance.new("Folder")
folder.Name = "VT65VehicleFx"
folder.Parent = workspace

local function seq(...: number): NumberSequence
	local a = { ... }
	local keys = {}
	for i = 1, #a, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function gfx(): number
	local d = Input.settings.gfxDetail
	return if d == "low" then 0.35 elseif d == "medium" then 0.65 else 1
end

local function soundId(key: string?): string?
	local id = key and AssetIds.Sounds[key]
	return if type(id) == "number" and id ~= 0 then "rbxassetid://" .. id else nil
end

local function localPart(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

-- Emissor parado (Rate 0) de um tipo; quem chama regula Rate e Color a cada quadro.
local function emitter(parent: Instance, kind: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Front
	e.LightInfluence = 1
	e.Rotation = NumberRange.new(0, 360)
	e.WindAffectsDrag = true
	if kind == "dust" then
		-- poeira de lagarta: nuvem que cresce, sobe um pouco e vai com o vento
		e.Texture = CFG.smoke
		e.Size = seq(0, 2.2, 0.4, 7, 1, 13)
		e.Transparency = seq(0, 1, 0.07, 0.5, 0.55, 0.72, 1, 1)
		e.Lifetime = NumberRange.new(2.5, 4.5)
		e.Speed = NumberRange.new(4, 9)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(0, 1.2, 0)
		e.Drag = 1.4
		e.RotSpeed = NumberRange.new(-18, 18)
	elseif kind == "debris" then
		-- torrões, capim, folhas ou gotas jogados pela lagarta
		e.Texture = CFG.square
		e.Size = seq(0, 0.32, 1, 0.22)
		e.Transparency = seq(0, 0.05, 0.8, 0.2, 1, 1)
		e.Lifetime = NumberRange.new(0.5, 1.1)
		e.Speed = NumberRange.new(9, 17)
		e.SpreadAngle = Vector2.new(22, 22)
		e.Acceleration = Vector3.new(0, -VehicleDrive.G / M * 1.4, 0)
		e.Drag = 0.4
		e.RotSpeed = NumberRange.new(-300, 300)
	elseif kind == "mist" then
		-- respingo e névoa d'água
		e.Texture = CFG.smoke
		e.Size = seq(0, 1.4, 1, 6)
		e.Transparency = seq(0, 0.35, 0.5, 0.65, 1, 1)
		e.Lifetime = NumberRange.new(0.7, 1.5)
		e.Speed = NumberRange.new(5, 10)
		e.SpreadAngle = Vector2.new(30, 30)
		e.Acceleration = Vector3.new(0, -12, 0)
		e.Drag = 2
		e.RotSpeed = NumberRange.new(-40, 40)
	elseif kind == "exhaust" then
		e.Texture = CFG.smoke
		e.Size = seq(0, 0.7, 0.25, 2.4, 1, 7.5)
		e.Transparency = seq(0, 0.5, 0.2, 0.6, 1, 1)
		e.Lifetime = NumberRange.new(1.6, 3.2)
		e.Speed = NumberRange.new(5, 9)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Drag = 1.2
		e.RotSpeed = NumberRange.new(-30, 30)
	elseif kind == "foam" then
		-- espuma deitada na água: sobe quase nada e fica perpendicular à velocidade (de cara para
		-- cima). Sem vento: com arrasto do vento a velocidade deitaria e a espuma ficaria em pé.
		e.Texture = CFG.smoke
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		e.EmissionDirection = Enum.NormalId.Top
		e.Size = seq(0, 3, 1, 12)
		e.Transparency = seq(0, 0.45, 0.6, 0.7, 1, 1)
		e.Lifetime = NumberRange.new(5, 8)
		e.Speed = NumberRange.new(0.05, 0.1)
		e.SpreadAngle = Vector2.new(0, 0)
		e.Drag = 0
		e.WindAffectsDrag = false
		e.Color = ColorSequence.new(rgb(232, 234, 228))
		e.RotSpeed = NumberRange.new(-6, 6)
	end
	e.Parent = parent
	return e
end

-- ponto de emissão; a frente (−Z) aponta para `dir` (sem `dir`, sem giro: o "Top" é para cima)
local function attach(parent: Instance, pos: Vector3, dir: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.CFrame = if dir then CFrame.lookAt(pos, pos + dir) else CFrame.new(pos)
	a.Parent = parent
	return a
end

-- ===== estado por veículo =====
type Emit = {
	sideX: { number }, -- lado de cada lagarta no chassi (−1 esquerda, +1 direita)
	kick: { ParticleEmitter }, -- poeira atrás de cada lagarta
	kickBits: { ParticleEmitter },
	bow: { ParticleEmitter }, -- respingo na frente de cada lagarta
	bowBits: { ParticleEmitter },
	exhaust: { ParticleEmitter },
	puffT: number,
	ground: string,
}

type Fx = {
	model: Model,
	chassis: BasePart,
	id: string,
	kind: string,
	body: any,
	art: VehicleDrive.Art?,
	motor: Motor6D?,
	meshRel: CFrame?, -- malha em relação à ArtRoot (constante)
	scale: Vector3,
	springP: VehicleDrive.SpringParams,
	spring: VehicleDrive.SpringState,
	vel: Vector3?,
	acc: Vector3,
	corner: Vector3, -- (pitch, roll, heave em m)
	sink: number,
	ground: string,
	depth: number?,
	surfY: number?,
	floating: boolean,
	probeT: number,
	rpm: number,
	load: number,
	rotor: number,
	slip: number,
	engineOn: boolean,
	t: number,
	pose: CFrame,
	pitch: number,
	roll: number,
	dist: number,
	visual: boolean,
	created: { Instance },
	emit: Emit?,
	bars: { BasePart }?,
	barCF: { CFrame },
	belt: VehicleDrive.Belt?,
	phase: { number },
	sideX: { number }, -- lado no chassi das lagartas +z e −z da malha (−1 esquerda, +1 direita)
	fwdSign: number, -- 1 se o nariz da malha é −x (o ramo de baixo corre em +x andando para a frente)
	barsMud: boolean,
	rotorParts: { BasePart }?,
	rotorAng: number,
	tailAng: number,
	wash: { holder: BasePart, dust: { ParticleEmitter }, bits: { ParticleEmitter }, ground: string }?,
	wake: { holder: BasePart, bow: ParticleEmitter, spray: ParticleEmitter, foam: { ParticleEmitter } }?,
	sound: Sound?,
	distort: DistortionSoundEffect?,
}

local fxs: { [Model]: Fx } = {}

local function mainPart(art: Instance): BasePart?
	local best: BasePart? = nil
	local bestV = 0
	for _, p in art:GetDescendants() do
		if p:IsA("BasePart") then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > bestV then
				best, bestV = p, v
			end
		end
	end
	return best
end

-- ponto da malha (studs, referencial do VehicleDrive.ART) → ponto no referencial do chassi, em repouso
local function meshPoint(fx: Fx, x: number, y: number, z: number): Vector3
	local motor = fx.motor
	local rel = fx.meshRel
	if not (motor and rel) then
		return Vector3.new(x, y, z)
	end
	return (motor.C0 * rel * CFrame.new(x * fx.scale.X, y * fx.scale.Y, z * fx.scale.Z)).Position
end

-- malha agora (com a mola), no mundo
local function meshCF(fx: Fx): CFrame?
	local motor = fx.motor
	local rel = fx.meshRel
	if not (motor and rel) then
		return nil
	end
	return fx.chassis.CFrame * motor.C0 * fx.pose * rel
end

local function newFx(model: Model, chassis: BasePart): Fx
	local id = model:GetAttribute("Spec") :: string
	local kind = (model:GetAttribute("Kind") :: string?) or "tracked"
	local fx: Fx = {
		model = model,
		chassis = chassis,
		id = id,
		kind = kind,
		body = Vehicles.SPECS[id],
		art = VehicleDrive.ART[id],
		motor = nil,
		meshRel = nil,
		scale = Vector3.one,
		springP = if kind == "heli" then CFG.heliSpring else VehicleDrive.spec(id).spring,
		spring = VehicleDrive.newSpring(),
		vel = nil,
		acc = Vector3.zero,
		corner = Vector3.zero,
		sink = 0,
		ground = "earth",
		depth = nil,
		surfY = nil,
		floating = false,
		probeT = 0,
		rpm = 0,
		load = 0,
		rotor = 0,
		slip = 0,
		engineOn = false,
		t = math.random() * 100,
		pose = CFrame.identity,
		pitch = 0,
		roll = 0,
		dist = math.huge,
		visual = false,
		created = {},
		emit = nil,
		bars = nil,
		barCF = {},
		belt = nil,
		phase = { 0, 0 },
		sideX = { -1, 1 },
		fwdSign = 1,
		barsMud = false,
		rotorParts = nil,
		rotorAng = 0,
		tailAng = 0,
		wash = nil,
		wake = nil,
		sound = nil,
		distort = nil,
	}
	local motor = chassis:FindFirstChild("ArtMount")
	local art = model:FindFirstChild("Art")
	local mesh = art and mainPart(art)
	if motor and motor:IsA("Motor6D") and motor.Part1 then
		fx.motor = motor
		if mesh and fx.art then
			fx.meshRel = (motor.Part1 :: BasePart).CFrame:ToObjectSpace(mesh.CFrame)
			local box = (fx.art :: VehicleDrive.Art).box
			fx.scale = mesh.Size / Vector3.new(box[1], box[2], box[3])
		end
	end
	return fx
end

-- ===== partes visuais (criadas perto, destruídas longe) =====
local function track(fx: Fx, inst: Instance)
	table.insert(fx.created, inst)
end

local function setupVisual(fx: Fx)
	fx.visual = true
	local chassis = fx.chassis
	local detail = gfx()
	local art = fx.art
	local tr = art and art.track
	local size = chassis.Size
	-- geometria das lagartas no chassi (medida na malha; sem malha, pela caixa)
	local bottom, zc, xFront, xRear = -size.Y / 2, size.X * 0.38, -size.Z / 2, size.Z / 2
	local rearPt: { Vector3 } = {}
	local frontPt: { Vector3 } = {}
	if tr and fx.meshRel then
		local cs = tr.circles
		local zMid = (tr.zIn + tr.zOut) / 2
		local yb = cs[2][2] - cs[2][3]
		-- de que lado do chassi fica cada lagarta da malha, e para onde é a frente (conferido no chassi,
		-- sem supor o giro do importador)
		fx.sideX = { math.sign(meshPoint(fx, 0, 0, zMid).X), math.sign(meshPoint(fx, 0, 0, -zMid).X) }
		fx.fwdSign = if meshPoint(fx, -10, 0, 0).Z < meshPoint(fx, 10, 0, 0).Z then 1 else -1
		-- roda motriz atrás, roda-guia na frente (o laço vai da roda-guia, em −x, à motriz)
		local rearC, frontC = cs[4], cs[1]
		if fx.fwdSign < 0 then
			rearC, frontC = cs[1], cs[4]
		end
		for _, side in { 1, -1 } do
			table.insert(rearPt, meshPoint(fx, rearC[1] + fx.fwdSign * rearC[3] * 0.6, yb + 0.6, side * zMid))
			table.insert(frontPt, meshPoint(fx, frontC[1] - fx.fwdSign * frontC[3] * 0.4, yb + 0.9, side * zMid))
		end
	else
		for _, side in { -1, 1 } do
			table.insert(rearPt, Vector3.new(side * zc, bottom + 0.6, xRear))
			table.insert(frontPt, Vector3.new(side * zc, bottom + 0.9, xFront))
		end
	end
	if fx.kind ~= "heli" then
		local emit: Emit = {
			sideX = { math.sign(rearPt[1].X), math.sign(rearPt[2].X) },
			kick = {},
			kickBits = {},
			bow = {},
			bowBits = {},
			exhaust = {},
			puffT = 0,
			ground = "",
		}
		for i = 1, 2 do
			local out = math.sign(rearPt[i].X)
			local a = attach(chassis, rearPt[i], Vector3.new(out * 0.25, 0.45, 1))
			track(fx, a)
			table.insert(emit.kick, emitter(a, "dust"))
			table.insert(emit.kickBits, emitter(a, "debris"))
			local b = attach(chassis, frontPt[i], Vector3.new(math.sign(frontPt[i].X) * 0.7, 0.8, -0.5))
			track(fx, b)
			table.insert(emit.bow, emitter(b, "mist"))
			table.insert(emit.bowBits, emitter(b, "debris"))
		end
		local exhausts: { { number } } = if art and art.exhaust then art.exhaust else {}
		for _, e in exhausts do
			local p = if fx.meshRel then meshPoint(fx, e[1], e[2], e[3]) else Vector3.new(0, size.Y / 2, xRear)
			local a = attach(chassis, p, Vector3.new(0, 0.55, 1))
			track(fx, a)
			table.insert(emit.exhaust, emitter(a, "exhaust"))
		end
		fx.emit = emit
		-- faixas da lagarta
		if tr and fx.meshRel and detail > 0.5 then
			local belt = VehicleDrive.belt(tr.circles)
			fx.belt = belt
			local n = math.max(8, math.floor(tr.bars * (if detail < 1 then 0.6 else 1)))
			local bars: { BasePart } = {}
			local along = belt.length / tr.bars * 0.3 * fx.scale.X
			local width = (tr.zOut - tr.zIn + 0.14) * fx.scale.Z
			for _ = 1, 2 * n do
				local p = localPart("Faixa", Vector3.new(along, 0.16, width), COLORS.bar)
				p.Material = Enum.Material.Metal
				track(fx, p)
				table.insert(bars, p)
			end
			fx.bars = bars
			fx.barCF = table.create(2 * n, CFrame.identity)
		end
		-- esteira na água (anfíbio)
		if fx.kind == "amphibious" then
			local holder: BasePart = localPart("Esteira", Vector3.one * 0.2, COLORS.bar)
			holder.Transparency = 1
			track(fx, holder)
			local half = size.Z / 2 + CFG.rampStuds
			local bowA = attach(holder, Vector3.new(0, 0.2, -half), Vector3.new(0, 0.9, -0.5))
			local foam = {}
			for _, side in { -1, 1 } do
				local a = attach(holder, Vector3.new(side * size.X * 0.45, 0, half * 0.9), nil)
				table.insert(foam, emitter(a, "foam"))
			end
			local spray = emitter(bowA, "debris")
			spray.SpreadAngle = Vector2.new(60, 25)
			spray.Color = ColorSequence.new(COLORS.debris.water)
			local bowMist = emitter(bowA, "mist")
			bowMist.Color = ColorSequence.new(COLORS.dust.water)
			fx.wake = { holder = holder, bow = bowMist, spray = spray, foam = foam }
		end
	else
		-- rotor principal (disco + 4 pás) e de cauda (disco + 4 pás), por cima das pás paradas da malha
		local rot = art and art.rotor
		local tail = art and art.tail
		if rot and tail and fx.meshRel then
			local s = fx.scale.X
			local R, r = rot.r * s, tail.r * s
			local parts: { BasePart } = {}
			local disc = localPart("RotorDisco", Vector3.new(0.12, 2 * R, 2 * R), rgb(48, 48, 44))
			disc.Shape = Enum.PartType.Cylinder
			disc.Transparency = 1
			table.insert(parts, disc)
			for _ = 1, 4 do
				table.insert(parts, localPart("RotorPa", Vector3.new(R * 0.97, 0.12, 1.15 * s), rgb(34, 34, 32)))
			end
			local tdisc = localPart("CaudaDisco", Vector3.new(0.08, 2 * r, 2 * r), rgb(60, 60, 56))
			tdisc.Shape = Enum.PartType.Cylinder
			tdisc.Transparency = 1
			table.insert(parts, tdisc)
			for _ = 1, 2 do
				table.insert(parts, localPart("CaudaPa", Vector3.new(2 * r * 0.96, 0.3 * s, 0.06), rgb(40, 40, 38)))
			end
			for _, p in parts do
				track(fx, p)
			end
			fx.rotorParts = parts
			fx.barCF = table.create(#parts, CFrame.identity)
		end
		-- downwash: anel de 6 pontos no chão debaixo do cubo
		local holder: BasePart = localPart("Downwash", Vector3.one * 0.2, COLORS.bar)
		holder.Transparency = 1
		track(fx, holder)
		local ringR = (if rot then rot.r * fx.scale.X else 20) * 0.35
		local dust, bits = {}, {}
		for k = 0, 5 do
			local a = Instance.new("Attachment")
			a.CFrame = CFrame.Angles(0, k * math.pi / 3, 0)
				* CFrame.new(0, 0.6, -ringR)
				* CFrame.Angles(math.rad(8), 0, 0)
			a.Parent = holder
			local d = emitter(a, "dust")
			d.Speed = NumberRange.new(30, 55)
			d.SpreadAngle = Vector2.new(30, 6)
			d.Drag = 2.2
			d.Lifetime = NumberRange.new(1.8, 3.2)
			d.Size = seq(0, 3, 0.4, 9, 1, 15)
			table.insert(dust, d)
			local b = emitter(a, "debris")
			b.Speed = NumberRange.new(25, 45)
			b.SpreadAngle = Vector2.new(30, 10)
			b.Acceleration = Vector3.new(0, -20, 0)
			b.Drag = 1.2
			table.insert(bits, b)
		end
		fx.wash = { holder = holder, dust = dust, bits = bits, ground = "" }
	end
end

local function teardownVisual(fx: Fx)
	fx.visual = false
	for _, inst in fx.created do
		inst:Destroy()
	end
	table.clear(fx.created)
	fx.emit, fx.bars, fx.belt, fx.rotorParts, fx.wash, fx.wake = nil, nil, nil, nil, nil, nil
	fx.barCF = {}
	fx.pose = CFrame.identity
	local motor = fx.motor
	if motor and motor.Parent then
		motor.Transform = CFrame.identity
	end
end

local function teardown(fx: Fx)
	teardownVisual(fx)
	if fx.sound then
		fx.sound:Destroy()
		fx.sound = nil
	end
	fxs[fx.model] = nil
end

-- ===== estado: motor, chão, mola (PreSimulation: o Motor6D.Transform é aplicado nesta etapa) =====
local function excludeList(fx: Fx): { Instance }
	local list: { Instance } = { fx.model, folder }
	if player.Character then
		table.insert(list, player.Character)
	end
	return list
end

local function mine(fx: Fx): boolean
	return VehicleLive.drive.model == fx.model
end

local function updateEngine(fx: Fx, dt: number)
	local model = fx.model
	local on = model:GetAttribute("EngineOn") == true
	if on and not fx.engineOn and fx.emit then
		for _, e in fx.emit.exhaust do
			e:Emit(if CFG.diesel[fx.id] then 16 else 8) -- bafo da partida
		end
	end
	fx.engineOn = on
	local live = VehicleLive.drive
	if mine(fx) then
		fx.rpm, fx.load, fx.slip = live.rpm, live.load, live.slip
		fx.rotor = live.rotor
		return
	end
	local netRpm = model:GetAttribute("NetRpm")
	local netLoad = model:GetAttribute("NetLoad")
	local target = if on then math.max(if type(netRpm) == "number" then netRpm else 0, CFG.idleRpm) else 0
	fx.rpm += (target - fx.rpm) * (1 - math.exp(-dt / (if target > fx.rpm then 0.3 else 0.6)))
	local l = if on and type(netLoad) == "number" then netLoad else 0
	fx.load += (l - fx.load) * (1 - math.exp(-dt / 0.25))
	if fx.kind == "heli" then
		fx.rotor = VehicleDrive.rotorStep(fx.rotor, on, dt)
	end
end

local function updateGround(fx: Fx, dt: number)
	fx.probeT -= dt
	if fx.probeT > 0 then
		return
	end
	fx.probeT = if fx.dist < CFG.nearStuds then 0.15 else 0.4
	VehicleLive.solid(excludeList(fx))
	local g, depth, surfY = VehicleLive.probe(fx.chassis)
	fx.ground, fx.depth, fx.surfY = g, depth, surfY
	local w = VehicleDrive.DRIVE[fx.id] and VehicleDrive.DRIVE[fx.id].water
	fx.floating = if mine(fx)
		then VehicleLive.drive.floating
		else g == "water" and fx.kind == "amphibious" and w ~= nil and (depth or 99) >= w.draftM
end

-- 4 pontas: folga (m) entre o fundo da lagarta e o chão em cada ponta, no referencial do chassi
local function updateCorners(fx: Fx, dt: number)
	local chassis = fx.chassis
	local size = chassis.Size
	local hw, hl = size.X * 0.38, size.Z / 2 + CFG.rampStuds
	local params = VehicleLive.solid(excludeList(fx))
	local cf = chassis.CFrame
	local down = -cf.UpVector * 14
	local gaps = {}
	for i, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do -- fl, fr, bl, br
		local from = cf:PointToWorldSpace(Vector3.new(c[1] * hw, -size.Y / 2 + 6, c[2] * hl))
		local r = workspace:Raycast(from, down, params)
		gaps[i] = if r then ((from - r.Position).Magnitude - 6) * M else 0.3
	end
	local p, rr, h = VehicleDrive.cornerFit(gaps[1], gaps[2], gaps[3], gaps[4], hl * M, hw * M)
	fx.corner = fx.corner:Lerp(Vector3.new(p, rr, h), 1 - math.exp(-dt / 0.06))
end

local function updatePose(fx: Fx, dt: number)
	local chassis = fx.chassis
	local vel = chassis.AssemblyLinearVelocity
	if fx.vel and dt > 0 then
		local raw = (vel - (fx.vel :: Vector3)) / dt * M
		fx.acc = fx.acc:Lerp(raw, 1 - math.exp(-dt / (if mine(fx) then 0.06 else 0.12)))
	end
	fx.vel = vel
	local a = chassis.CFrame:VectorToObjectSpace(fx.acc)
	local lim = 2.5 * VehicleDrive.G
	VehicleDrive.springStep(
		fx.spring,
		fx.springP,
		math.clamp(-a.Z, -lim, lim),
		math.clamp(a.X, -lim, lim),
		math.clamp(a.Y, -lim * 0.6, lim * 0.6),
		dt
	)
	fx.t += dt
	local t = fx.t
	local sp = fx.spring
	local pitch, roll, heave = sp.pitch, sp.roll, sp.heave
	-- arrepio do motor ligado (diesel em marcha lenta treme o casco)
	local shiver = math.rad(if CFG.diesel[fx.id] then 0.1 else 0.05) * math.clamp(fx.rpm, 0, 1.1)
	pitch += math.noise(t * 23, 1.3) * shiver
	roll += math.noise(t * 27, 7.1) * shiver
	if fx.kind ~= "heli" then
		local g = VehicleDrive.ground(fx.ground, ReplicatedStorage:GetAttribute("Rain") :: number?)
		local onGround = not fx.floating and fx.ground ~= "water"
		fx.sink += ((if onGround then g.sinkM else 0) - fx.sink) * (1 - math.exp(-dt / 0.8))
		heave -= fx.sink
		if onGround and fx.dist < CFG.nearStuds and gfx() > 0.5 then
			updateCorners(fx, dt)
		else
			fx.corner = fx.corner:Lerp(Vector3.zero, 1 - math.exp(-dt / 0.3))
		end
		pitch += fx.corner.X
		roll += fx.corner.Y
		heave += fx.corner.Z
		if fx.floating then
			-- boiando: marola, e o nariz sobe um pouco com a velocidade
			local speed = -chassis.CFrame:VectorToObjectSpace(vel).Z * M
			local vw = math.max(((fx.body and fx.body.waterKmh) or 11) / 3.6, 0.5)
			heave += math.sin(t * 0.9) * 0.06 + math.noise(t * 0.4, 3.3) * 0.04
			pitch += math.sin(t * 0.55 + 1.1) * math.rad(0.7) + math.rad(1.5) * math.clamp(speed / vw, 0, 1.2)
			roll += math.sin(t * 0.73 + 2.3) * math.rad(1.0)
		end
	end
	fx.pitch, fx.roll = pitch, roll
	fx.pose = CFrame.new(0, heave / M, 0) * CFrame.Angles(pitch, 0, roll)
	local motor = fx.motor
	if motor then
		motor.Transform = fx.pose
	end
end

-- ===== desenho: faixas, rotor, partículas e som (PreRender) =====
local bulk = { parts = {} :: { BasePart }, cfs = {} :: { CFrame } }

local function drawBars(fx: Fx, dt: number, vFwd: number, yawRate: number)
	local bars, belt, tr = fx.bars, fx.belt, fx.art and fx.art.track
	local mcf = meshCF(fx)
	if not (bars and belt and tr and mcf) then
		return
	end
	local s = fx.scale
	local zMid = (tr.zIn + tr.zOut) / 2
	local halfB = zMid * s.Z * M -- m do centro a cada lagarta
	local n = #bars // 2
	local muddy = fx.ground == "mud" or fx.ground == "paddy"
	if muddy ~= fx.barsMud then
		fx.barsMud = muddy
		for _, p in bars do
			p.Color = if muddy then COLORS.barMud else COLORS.bar
		end
	end
	for side = 1, 2 do
		-- lado 1 = +z da malha. Na curva para a esquerda (guinada +) a lagarta da esquerda anda menos;
		-- no giro no lugar as duas andam em sentidos opostos
		local sz = if side == 1 then 1 else -1
		local vSide = vFwd + fx.sideX[side] * yawRate * halfB
		fx.phase[side] = (fx.phase[side] + fx.fwdSign * vSide / M / s.X * dt) % belt.length
		for k = 1, n do
			local x, y, ang = VehicleDrive.beltAt(belt, fx.phase[side] + (k - 1) * belt.length / n)
			local nx, ny = math.sin(ang), -math.cos(ang) -- para fora do laço
			local i = (side - 1) * n + k
			fx.barCF[i] = mcf
				* CFrame.new((x + nx * 0.05) * s.X, (y + ny * 0.05) * s.Y, sz * zMid * s.Z)
				* CFrame.Angles(0, 0, ang)
			table.insert(bulk.parts, bars[i])
			table.insert(bulk.cfs, fx.barCF[i])
		end
	end
end

local function drawRotor(fx: Fx, dt: number)
	local parts = fx.rotorParts
	local art = fx.art
	local mcf = meshCF(fx)
	if not (parts and art and art.rotor and art.tail and mcf) then
		return
	end
	local rot, tail = art.rotor :: VehicleDrive.RotorArt, art.tail :: VehicleDrive.RotorArt
	local H = VehicleDrive.HELI
	local s = fx.scale
	local rotor = fx.rotor
	local show = rotor > 0.02
	fx.rotorAng = (fx.rotorAng + rotor * H.rotorRpm / 60 * 2 * math.pi * dt) % (2 * math.pi)
	fx.tailAng = (fx.tailAng + rotor * H.tailRpm / 60 * 2 * math.pi * dt) % (2 * math.pi)
	-- disco inclina com a aceleração (e, no piloto local, com o cíclico pedido)
	local a = fx.chassis.CFrame:VectorToObjectSpace(fx.acc)
	local tiltF = math.clamp(-a.Z / VehicleDrive.G * 0.35, -0.08, 0.08)
	local tiltR = math.clamp(a.X / VehicleDrive.G * 0.35, -0.08, 0.08)
	if mine(fx) then
		tiltF += math.clamp(-VehicleLive.drive.cyclicY * 0.3, -0.05, 0.05)
		tiltR += math.clamp(-VehicleLive.drive.cyclicX * 0.3, -0.05, 0.05)
	end
	-- referencial da malha: nariz em −x, direita em −z. Frente para baixo = giro + em z; direita para
	-- baixo = giro − em x (fwdSign corrige se a malha vier com o nariz em +x)
	local hub = mcf
		* CFrame.new(rot.x * s.X, rot.y * s.Y, rot.z * s.Z)
		* CFrame.Angles(-tiltR * fx.fwdSign, 0, tiltF * fx.fwdSign)
	local R = rot.r * s.X
	local blur = math.clamp((rotor - 0.3) / 0.5, 0, 1)
	parts[1].Transparency = if show then 1 - 0.22 * blur else 1
	table.insert(bulk.parts, parts[1])
	table.insert(bulk.cfs, hub * CFrame.Angles(0, 0, math.pi / 2))
	for k = 1, 4 do
		local p = parts[1 + k]
		p.Transparency = if show then 0.25 + 0.65 * math.clamp(rotor / 0.6, 0, 1) else 1
		table.insert(bulk.parts, p)
		table.insert(
			bulk.cfs,
			hub * CFrame.Angles(0, fx.rotorAng + (k - 1) * math.pi / 2, 0) * CFrame.new(R * 0.5 + 0.4, 0.05, 0)
		)
	end
	local tcf = mcf * CFrame.new(tail.x * s.X, tail.y * s.Y, tail.z * s.Z)
	parts[6].Transparency = if show then 1 - 0.3 * blur else 1
	table.insert(bulk.parts, parts[6])
	table.insert(bulk.cfs, tcf * CFrame.Angles(0, math.pi / 2, 0))
	for k = 1, 2 do
		local p = parts[6 + k]
		p.Transparency = if show then 0.3 + 0.6 * math.clamp(rotor / 0.5, 0, 1) else 1
		table.insert(bulk.parts, p)
		table.insert(bulk.cfs, tcf * CFrame.Angles(0, 0, fx.tailAng + (k - 1) * math.pi / 2))
	end
end

local function setColor(list: { ParticleEmitter }, c: Color3)
	for _, e in list do
		e.Color = ColorSequence.new(c)
	end
end

local function setRate(list: { ParticleEmitter }, rates: { number })
	for i, e in list do
		e.Rate = rates[i] or rates[1]
	end
end

local function drawTrackFx(fx: Fx, dt: number, vFwd: number, yawRate: number, rain: number)
	local emit = fx.emit
	if not emit then
		return
	end
	local detail = gfx()
	local g = VehicleDrive.ground(fx.ground, rain)
	local kind = if fx.floating then "float" else g.fx
	if kind ~= emit.ground then
		emit.ground = kind
		local key = if fx.ground == "water" then "water" else fx.ground
		setColor(emit.kick, COLORS.dust[key] or COLORS.dust.earth)
		setColor(emit.kickBits, COLORS.debris[key] or COLORS.debris.earth)
		local wet = kind == "paddy" or kind == "water"
		setColor(emit.bow, if wet then COLORS.dust.paddy else COLORS.dust[key] or COLORS.dust.earth)
		setColor(emit.bowBits, if wet then COLORS.debris.paddy else COLORS.debris[key] or COLORS.debris.earth)
	end
	local halfB = fx.chassis.Size.X * 0.38 * M
	local sideV = {
		math.abs(vFwd + emit.sideX[1] * yawRate * halfB),
		math.abs(vFwd + emit.sideX[2] * yawRate * halfB),
	}
	local slip = fx.slip
	local dustK, bitsK, bowK, bowBitsK = 0, 0, 0, 0
	if kind == "dust" or kind == "sand" then
		dustK, bitsK = 2.4 * (1 - 0.8 * rain), if kind == "sand" then 0.6 else 0.25
	elseif kind == "grass" or kind == "leaves" then
		dustK, bitsK = 1.3 * (1 - 0.8 * rain), 1.1
	elseif kind == "mud" then
		bitsK, bowBitsK = 3, 0.8
	elseif kind == "paddy" then
		bitsK, bowK, bowBitsK = 2.2, 3.5, 4
	elseif kind == "water" then -- vadeando o riacho
		bowK, bowBitsK = 5, 5
	end
	local kick, bits, bow, bowBits = {}, {}, {}, {}
	for i = 1, 2 do
		local v = sideV[i]
		kick[i] = (dustK * v + dustK * slip * 6) * detail
		bits[i] = (bitsK * v + bitsK * slip * 8) * detail
		bow[i] = bowK * v * detail
		bowBits[i] = bowBitsK * v * detail
	end
	setRate(emit.kick, kick)
	setRate(emit.kickBits, bits)
	setRate(emit.bow, bow)
	setRate(emit.bowBits, bowBits)
	-- escapamento: fio na marcha lenta, grosso e escuro com carga; bafo quando o motor sobe de giro
	local diesel = CFG.diesel[fx.id] == true
	local on = fx.engineOn and fx.rpm > 0.05
	for _, e in emit.exhaust do
		e.Rate = if on then (2.5 + 28 * fx.load * math.clamp(fx.rpm, 0, 1)) * (if diesel then 1 else 0.5) else 0
		local dark = if diesel then 70 - 30 * fx.load else 150 - 20 * fx.load
		e.Color = ColorSequence.new(rgb(dark, dark - 2, dark - 6), rgb(dark + 60, dark + 58, dark + 52))
	end
	emit.puffT -= dt
	if on and fx.load > 0.7 and emit.puffT <= 0 and fx.rpm < 0.85 then
		emit.puffT = 0.6
		for _, e in emit.exhaust do
			e:Emit(if diesel then 3 else 1)
		end
	end
	local wake = fx.wake
	if wake then
		local speed = math.abs(vFwd)
		local float = fx.floating and fx.surfY ~= nil
		if float then
			local cf = fx.chassis.CFrame
			local _, yaw, _ = cf:ToOrientation()
			wake.holder.CFrame = CFrame.new(cf.Position.X, (fx.surfY :: number) + 0.15, cf.Position.Z)
				* CFrame.Angles(0, yaw, 0)
		end
		wake.bow.Rate = if float then (4 + 6 * speed) * detail else 0
		wake.spray.Rate = if float then 8 * speed * detail else 0
		for _, e in wake.foam do
			e.Rate = if float then (1.5 + 3 * speed) * detail else 0
		end
	end
end

local function drawWash(fx: Fx, rain: number)
	local wash = fx.wash
	local art = fx.art
	if not wash then
		return
	end
	local strength = 0
	local mcf = meshCF(fx)
	local hubPos = fx.chassis.Position
	local R = 20
	if mcf and art and art.rotor then
		hubPos = (mcf * CFrame.new(art.rotor.x * fx.scale.X, art.rotor.y * fx.scale.Y, art.rotor.z * fx.scale.Z)).Position
		R = art.rotor.r * fx.scale.X
	end
	if fx.rotor > 0.3 then
		VehicleLive.solid(excludeList(fx))
		local hmax = 5 * R
		local g, _, at = VehicleLive.groundAt(hubPos, hmax)
		if g and at then
			local h = (hubPos.Y - at.Y) / hmax
			local thrust = math.clamp(0.4 + fx.load, 0.4, 1.2)
			strength = fx.rotor * fx.rotor * thrust * (1 - h) ^ 2
			wash.holder.CFrame = CFrame.new(at)
			if g ~= wash.ground then
				wash.ground = g
				local wet = g == "water" or g == "paddy"
				setColor(wash.dust, if wet then COLORS.dust.water else COLORS.dust[g] or COLORS.dust.earth)
				setColor(wash.bits, if wet then COLORS.debris.water else COLORS.debris[g] or COLORS.debris.earth)
			end
		end
	end
	local detail = gfx()
	local wet = wash.ground == "water" or wash.ground == "paddy"
	local dusty = 1 - (if wet then 0 else 0.7 * rain)
	for _, e in wash.dust do
		e.Rate = strength * 14 * detail * dusty
	end
	local bitsK = if wet then 16 elseif wash.ground == "grass" or wash.ground == "forest" then 10 else 4
	for _, e in wash.bits do
		e.Rate = strength * bitsK * detail
	end
end

local function updateSound(fx: Fx)
	local chassis = fx.chassis
	-- o laço antigo do AudioController (só tom pela velocidade): calado aqui para não tocar dois motores
	local old = chassis:FindFirstChild("Engine")
	if old and old:IsA("Sound") and old.Playing then
		old:Stop()
	end
	local id = soundId(CFG.engineSound[fx.id])
	if not id then
		return -- sem som publicado (UH-34D: uh34d_loop = 0); o gancho fica pronto
	end
	local level = if fx.kind == "heli" then fx.rotor else fx.rpm
	local snd = fx.sound
	if not snd then
		if level < 0.02 then
			return
		end
		local s = Instance.new("Sound")
		s.Name = "VT65Engine"
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 14
		s.RollOffMaxDistance = CFG.soundStuds
		local d = Instance.new("DistortionSoundEffect")
		d.Level = 0
		d.Parent = s
		s.Parent = chassis
		s:Play()
		fx.sound, fx.distort = s, d
		snd = s
	end
	local s = snd :: Sound
	local pitch, vol
	if fx.kind == "heli" then
		pitch, vol = 0.45 + 0.55 * fx.rotor, fx.rotor * (0.8 + 0.2 * fx.load)
	else
		pitch, vol = VehicleDrive.engineVoice(fx.rpm, fx.load)
		-- partida: o motor acorda devagar
		vol *= math.clamp(fx.rpm / CFG.idleRpm, 0, 1)
	end
	s.PlaybackSpeed = pitch
	s.Volume = 0.85 * vol
	if fx.distort then
		fx.distort.Level = 0.04 + 0.18 * fx.load
	end
	if level < 0.01 then
		s:Destroy()
		fx.sound, fx.distort = nil, nil
	end
end

-- ===== laço =====
local scan = { t = 0 }

local function seatedModel(): Model?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local m = seat and seat:FindFirstAncestorWhichIsA("Model")
	return if m and m:GetAttribute("VehicleId") then m else nil
end

local function refresh()
	local vehicles = workspace:FindFirstChild("Vehicles")
	local camPos = camera.CFrame.Position
	for model, fx in fxs do
		if model.Parent ~= vehicles or not fx.chassis.Parent or model:GetAttribute("Destroyed") then
			teardown(fx)
		end
	end
	if not vehicles then
		return
	end
	for _, model in vehicles:GetChildren() do
		if model:IsA("Model") and not model:GetAttribute("Destroyed") then
			local chassis = model:FindFirstChild("Chassis")
			if chassis and chassis:IsA("BasePart") then
				local d = (chassis.Position - camPos).Magnitude
				local fx = fxs[model]
				if not fx and d < CFG.soundStuds then
					fx = newFx(model, chassis)
					fxs[model] = fx
				end
				if fx then
					fx.dist = d
					if d > CFG.soundStuds * 1.1 then
						teardown(fx)
					elseif not fx.visual and d < CFG.midStuds then
						setupVisual(fx)
					elseif fx.visual and d > CFG.midStuds * 1.15 then
						teardownVisual(fx)
					end
				end
			end
		end
	end
end

RunService.PreSimulation:Connect(function(dt: number)
	scan.t -= dt
	if scan.t <= 0 then
		scan.t = 0.5
		refresh()
	end
	local seated = seatedModel()
	local camPos = camera.CFrame.Position
	for model, fx in fxs do
		if not fx.chassis.Parent then
			continue
		end
		fx.dist = (fx.chassis.Position - camPos).Magnitude
		updateEngine(fx, dt)
		if fx.visual then
			updateGround(fx, dt)
			updatePose(fx, dt)
		end
		if model == seated then
			local view = VehicleLive.view
			view.model = model
			view.pitch, view.roll = fx.pitch, fx.roll
			view.rough = VehicleDrive.ground(fx.ground).rough
			view.speed = fx.chassis.AssemblyLinearVelocity.Magnitude * M
			view.rpm, view.rotor = fx.rpm, fx.rotor
			local motor, rel = fx.motor, fx.meshRel
			view.meshRel = if motor and rel then motor.C0 * fx.pose * rel else nil
			view.scale = fx.scale
		end
	end
	if not seated or not fxs[seated] then
		VehicleLive.view.model = nil
		VehicleLive.view.meshRel = nil
	end
end)

RunService.PreRender:Connect(function(dt: number)
	table.clear(bulk.parts)
	table.clear(bulk.cfs)
	local rainAttr = ReplicatedStorage:GetAttribute("Rain")
	local rain = if type(rainAttr) == "number" then math.clamp(rainAttr, 0, 1) else 0
	for _, fx in fxs do
		if not fx.chassis.Parent then
			continue
		end
		updateSound(fx)
		if not fx.visual then
			continue
		end
		local chassis = fx.chassis
		local lv = chassis.CFrame:VectorToObjectSpace(chassis.AssemblyLinearVelocity)
		local vFwd = -lv.Z * M
		local yawRate = chassis.AssemblyAngularVelocity:Dot(chassis.CFrame.UpVector)
		if fx.kind == "heli" then
			drawRotor(fx, dt)
			drawWash(fx, rain)
		else
			if not mine(fx) then
				-- dos outros: patina quando gira no lugar ou está bloqueado (sem o estado do motorista)
				fx.slip = math.clamp(math.abs(yawRate) * 0.6 - math.abs(vFwd) * 0.05, 0, 1)
			end
			drawTrackFx(fx, dt, vFwd, yawRate, rain)
			if fx.dist < CFG.nearStuds then
				drawBars(fx, dt, vFwd, yawRate)
			end
		end
	end
	if #bulk.parts > 0 then
		workspace:BulkMoveTo(bulk.parts, bulk.cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
