--!strict
-- Andar dos animais (D-77, pedido do dono: "movimento realista e perfeito"). O servidor
-- (AnimalService) decide onde cada búfalo e galinha está, a 1 Hz pastando e a 10 Hz fugindo, e
-- publica o andar no atributo "Gait" (idle, walk, run). Aqui cada animal perto da câmera ganha uma
-- cópia local em partes (ReplicatedStorage.VT65AnimalArt: corpo, pernas e cabeça), que:
-- - anda suave até a posição do servidor, na velocidade da espécie, sem os saltos de 1 Hz;
-- - vira devagar para onde vai (o búfalo ~70°/s) e acompanha a ladeira;
-- - mexe as pernas no passo certo: búfalo em quatro tempos (pata de trás, depois a da frente do
--   mesmo lado) andando e trote em diagonal fugindo; galinha alternando;
-- - balança o corpo a cada passo; o búfalo parado pasta de cabeça baixa e a galinha cisca.
-- O modelo do servidor fica escondido só neste cliente (LocalTransparencyModifier).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Animals = require(ReplicatedStorage.Shared.Animals)

local M = 0.28
local camera = workspace.CurrentCamera
local VIEW_M = 250 -- cópia local até aqui
local ANIM_M = 120 -- pernas e cabeça animadas até aqui

type Leg = { i: number, pivot: Vector3, name: string }
type BoneInfo = { b: Bone, lat: Vector3, up: Vector3 }
type Rig = {
	server: Model,
	model: Model,
	species: string,
	parts: { BasePart },
	rest: { CFrame },
	legs: { Leg },
	head: number?,
	headPivot: Vector3,
	bones: { [string]: BoneInfo }?, -- com esqueleto (D-79)
	pos: Vector3,
	yaw: number,
	pitch: number,
	speed: number, -- m/s, medida no movimento da cópia
	phase: number,
	groundAt: number,
	groundY: number,
	headPitch: number,
	peckUntil: number,
	nextPeck: number,
	seed: number,
}

-- Passo de cada espécie (PLACEHOLDER de animação, não de jogo)
local GAIT = {
	water_buffalo = {
		stride = 1.7, -- m por ciclo de passada andando
		strideRun = 2.6,
		walkAmp = math.rad(17),
		runAmp = math.rad(30),
		turn = math.rad(70),
		bob = 0.035, -- m
		walkPhase = { PernaTE = 0, PernaFE = 0.25, PernaTD = 0.5, PernaFD = 0.75 },
		runPhase = { PernaFE = 0, PernaTD = 0, PernaFD = 0.5, PernaTE = 0.5 },
		grazePitch = math.rad(-38),
	},
	chicken = {
		stride = 0.2,
		strideRun = 0.45,
		walkAmp = math.rad(32),
		runAmp = math.rad(48),
		turn = math.rad(320),
		bob = 0.012,
		walkPhase = { PernaFE = 0, PernaFD = 0.5 },
		runPhase = { PernaFE = 0, PernaFD = 0.5 },
		grazePitch = math.rad(-65), -- bicada
	},
} :: { [string]: any }

local holder = Instance.new("Folder")
holder.Name = "VT65AnimaisLocal"
holder.Parent = workspace

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

local function ground(x: number, z: number, fallback: number): number
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, fallback + 60, z), Vector3.new(0, -200, 0), groundParams)
	return if hit then hit.Position.Y else fallback
end

-- D-79: animal com esqueleto e pele (Blender, tools/animais/esqueleto.py). Uma malha só; os
-- ossos giram em volta do eixo lateral do animal (calculado no repouso, no espaço de cada osso) e a
-- pele acompanha sem fresta. Devolve o Rig com `bones`.
local function hideServer(server: Model)
	for _, d in server:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		end
	end
end

local function buildSkinned(server: Model, species: string, m: Model): Rig?
	local mesh = m:FindFirstChildWhichIsA("MeshPart", true)
	local head = m:FindFirstChild("Cabeca", true)
	local back = m:FindFirstChild("Quadril", true) or m:FindFirstChild("Corpo", true)
	if not (mesh and head and back and head:IsA("Bone") and back:IsA("Bone")) then
		m:Destroy()
		return nil
	end
	local fwd = (head.WorldPosition - back.WorldPosition) * Vector3.new(1, 0, 1)
	if fwd.Magnitude < 1e-3 then
		fwd = -Vector3.zAxis
	end
	local origin = Vector3.new(mesh.Position.X, mesh.Position.Y - mesh.Size.Y / 2, mesh.Position.Z)
	local root = CFrame.lookAt(origin, origin + fwd.Unit)
	local bones = {}
	for _, b in m:GetDescendants() do
		if b:IsA("Bone") then
			local w = b.WorldCFrame
			bones[b.Name] = {
				b = b,
				lat = w:VectorToObjectSpace(root.RightVector),
				up = w:VectorToObjectSpace(root.UpVector),
			}
		end
	end
	mesh.Anchored, mesh.CanCollide, mesh.CanQuery, mesh.CanTouch = true, false, false, false
	m.Parent = holder
	hideServer(server)
	local sp = server:GetPivot().Position
	local gy = ground(sp.X, sp.Z, sp.Y)
	return {
		server = server,
		model = m,
		species = species,
		parts = { mesh },
		rest = { root:ToObjectSpace(mesh.CFrame) },
		legs = {},
		head = nil,
		headPivot = Vector3.zero,
		bones = bones,
		pos = Vector3.new(sp.X, gy, sp.Z),
		yaw = math.random() * 2 * math.pi,
		pitch = 0,
		speed = 0,
		phase = math.random(),
		groundAt = 0,
		groundY = gy,
		headPitch = 0,
		peckUntil = 0,
		nextPeck = os.clock() + math.random() * 3,
		seed = math.random(1, 1000),
	}
end

-- Raiz da cópia: no chão, sob o centro do corpo, olhando do corpo para a cabeça. Guarda cada
-- parte relativa a ela, a junta de cada perna (topo da perna) e a do pescoço (trás da cabeça).
local function build(server: Model, species: string, tpl: Model): Rig?
	local m = tpl:Clone()
	local scale = server:GetScale()
	if math.abs(scale - 1) > 0.01 then
		m:ScaleTo(scale) -- bezerro (0,6)
	end
	if m:FindFirstChildWhichIsA("Bone", true) then
		return buildSkinned(server, species, m)
	end
	-- o importador põe cada malha dentro de um modelo "<nome>_Node"
	local body = m:FindFirstChild("Corpo", true) :: BasePart?
	local headPart = m:FindFirstChild("Cabeca", true) :: BasePart?
	if not body then
		m:Destroy()
		return nil
	end
	local parts: { BasePart } = {}
	local lowest = math.huge
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			lowest = math.min(lowest, d.Position.Y - d.Size.Y / 2)
		end
	end
	local fwd = if headPart then (headPart.Position - body.Position) * Vector3.new(1, 0, 1) else Vector3.zAxis
	if fwd.Magnitude < 1e-3 then
		fwd = -Vector3.zAxis
	end
	local origin = Vector3.new(body.Position.X, lowest, body.Position.Z)
	local root = CFrame.lookAt(origin, origin + fwd.Unit)
	local rest: { CFrame } = {}
	local legs: { Leg } = {}
	local head: number? = nil
	local headPivot = Vector3.zero
	for i, p in parts do
		rest[i] = root:ToObjectSpace(p.CFrame)
		if string.sub(p.Name, 1, 5) == "Perna" then
			local top = root:PointToObjectSpace(p.Position + Vector3.new(0, p.Size.Y * 0.45, 0))
			table.insert(legs, { i = i, pivot = top, name = p.Name })
		elseif p.Name == "Cabeca" then
			head = i
			local c = root:PointToObjectSpace(p.Position)
			-- extensão da cabeça ao longo da frente (peças vêm alinhadas aos eixos do mundo)
			local zAxis = root.LookVector
			local ext = math.abs(zAxis.X) * p.Size.X + math.abs(zAxis.Z) * p.Size.Z
			headPivot = Vector3.new(c.X, c.Y - p.Size.Y * 0.1, c.Z + ext / 2)
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	m.Parent = holder
	-- esconde o modelo do servidor só aqui
	for _, d in server:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		end
	end
	local sp = server:GetPivot().Position
	local gy = ground(sp.X, sp.Z, sp.Y)
	return {
		server = server,
		model = m,
		species = species,
		parts = parts,
		rest = rest,
		legs = legs,
		head = head,
		headPivot = headPivot,
		pos = Vector3.new(sp.X, gy, sp.Z),
		yaw = math.random() * 2 * math.pi,
		pitch = 0,
		speed = 0,
		phase = math.random(),
		groundAt = 0,
		groundY = gy,
		headPitch = 0,
		peckUntil = 0,
		nextPeck = os.clock() + math.random() * 3,
		seed = math.random(1, 1000),
	}
end

local function release(r: Rig)
	r.model:Destroy()
	for _, d in r.server:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
		end
	end
end

local function angleTo(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

local function step(r: Rig, dt: number, now: number, camPos: Vector3)
	local g = GAIT[r.species]
	local sp = Animals.SPECIES[r.species]
	local gait = r.server:GetAttribute("Gait")
	local run = gait == "run"
	local target = r.server:GetPivot().Position
	local flat = Vector3.new(target.X - r.pos.X, 0, target.Z - r.pos.Z)
	local dist = flat.Magnitude
	local moved = 0
	if dist > 60 / M then
		-- longe demais (acabou de entrar no streaming): pula para o lugar
		r.pos = Vector3.new(target.X, r.pos.Y, target.Z)
	elseif dist > 0.02 then
		local vmax = (if run then sp.fleeMs * 1.15 else sp.walkMs * 1.4) / M
		local v = math.min(vmax, dist / 0.5) -- chega devagar no ponto do servidor
		moved = math.min(dist, v * dt)
		r.pos += flat.Unit * moved
		-- vira para onde anda, no ritmo da espécie
		local want = math.atan2(-flat.X, -flat.Z)
		local d = angleTo(r.yaw, want)
		r.yaw += math.clamp(d, -g.turn * dt, g.turn * dt)
	end
	local speedNow = (moved * M) / math.max(dt, 1e-3)
	r.speed += (speedNow - r.speed) * math.min(1, dt * 6)
	-- chão e ladeira (4 vezes por segundo)
	if now >= r.groundAt then
		r.groundAt = now + 0.25
		r.groundY = ground(r.pos.X, r.pos.Z, r.pos.Y)
		if r.species == "water_buffalo" then
			local f = CFrame.Angles(0, r.yaw, 0).LookVector * (1.1 / M)
			local yf = ground(r.pos.X + f.X, r.pos.Z + f.Z, r.groundY)
			local yb = ground(r.pos.X - f.X, r.pos.Z - f.Z, r.groundY)
			r.pitch = math.clamp(math.atan2(yf - yb, 2.2 / M), -0.35, 0.35)
		end
	end
	r.pos = Vector3.new(r.pos.X, r.pos.Y + (r.groundY - r.pos.Y) * math.min(1, dt * 8), r.pos.Z)
	local far = (r.pos - camPos).Magnitude * M > ANIM_M
	-- passada
	local stride = if run then g.strideRun else g.stride
	r.phase = (r.phase + r.speed * dt / stride) % 1
	local moving = r.speed > 0.05
	local amp = if moving then (if run then g.runAmp else g.walkAmp) * math.clamp(r.speed / 0.4, 0.3, 1) else 0
	local phases = if run then g.runPhase else g.walkPhase
	local bob = if moving then math.abs(math.sin(r.phase * 2 * math.pi * 2)) * g.bob / M else 0
	local roll = if moving then math.sin(r.phase * 2 * math.pi) * math.rad(1.5) else 0
	local root = CFrame.new(r.pos + Vector3.new(0, bob, 0))
		* CFrame.Angles(0, r.yaw, 0)
		* CFrame.Angles(r.pitch, 0, roll)
	-- cabeça: búfalo parado pasta (baixa devagar, mastiga); galinha parada bica de vez em quando
	local wantHead = 0
	if not moving and gait ~= "run" then
		if r.species == "water_buffalo" then
			wantHead = g.grazePitch + math.sin(now * 1.3 + r.seed) * math.rad(3)
		else
			if now >= r.nextPeck then
				r.peckUntil = now + 0.22
				r.nextPeck = now + 0.6 + ((r.seed + math.floor(now * 7)) % 10) * 0.25
			end
			wantHead = if now < r.peckUntil then g.grazePitch else math.sin(now * 3 + r.seed) * math.rad(6)
		end
	elseif moving then
		-- cabeça acompanha a passada (galinha: o balanço rápido de pescoço)
		local k = if r.species == "chicken" then 2 else 1
		wantHead = math.sin(r.phase * 2 * math.pi * k * 2) * math.rad(if r.species == "chicken" then 9 else 4)
			+ (if run then math.rad(8) else 0)
	end
	local headRate = if r.species == "chicken" then 18 else 2.5
	r.headPitch += (wantHead - r.headPitch) * math.min(1, dt * headRate)
	local cfs = table.create(#r.parts)
	for i, rel in r.rest do
		cfs[i] = root * rel
	end
	if not far then
		for _, leg in r.legs do
			local off = phases[leg.name] or 0
			local a = amp * math.sin((r.phase + off) * 2 * math.pi)
			cfs[leg.i] = root * CFrame.new(leg.pivot) * CFrame.Angles(a, 0, 0) * CFrame.new(-leg.pivot) * r.rest[leg.i]
		end
		local h = r.head
		if h then
			local p = r.headPivot
			cfs[h] = root * CFrame.new(p) * CFrame.Angles(r.headPitch, 0, 0) * CFrame.new(-p) * r.rest[h]
		end
		local bones = r.bones
		if bones then
			-- esqueleto: coxa balança, canela dobra só no balanço (casco sobe e vai para trás),
			-- coluna verga a cada passo e respira parada, cabeça pasta, rabo espanta mosca
			local function rot(name: string, lateral: number, vertical: number?)
				local bi = bones[name]
				if bi then
					local cf = CFrame.fromAxisAngle(bi.lat, lateral)
					if vertical and vertical ~= 0 then
						cf *= CFrame.fromAxisAngle(bi.up, vertical)
					end
					bi.b.Transform = cf
				end
			end
			local knee = if run then math.rad(62) else math.rad(38)
			for _, side in { "FE", "FD", "TE", "TD" } do
				local th = (r.phase + (phases["Perna" .. side] or 0)) * 2 * math.pi
				local a = amp * math.sin(th)
				local lift = if moving then math.max(0, math.cos(th)) * math.clamp(r.speed / 0.4, 0.3, 1) else 0
				rot("Coxa" .. side, a)
				rot("Canela" .. side, -knee * lift)
			end
			local breathe = math.sin(now * 1.6 + r.seed) * math.rad(1.2)
			local step = if moving then math.sin(r.phase * 4 * math.pi) * math.rad(2.5) else breathe
			rot("Coluna", step)
			rot("Corpo", step)
			rot("Pescoco", r.headPitch * 0.45)
			rot("Cabeca", r.headPitch * 0.55)
			local swish = math.sin(now * (if run then 6 else 2.3) + r.seed) * math.rad(if run then 30 else 22)
			rot("Rabo1", math.rad(if run then 25 else 0), swish)
			rot("Rabo2", 0, swish * 0.8)
		end
	end
	workspace:BulkMoveTo(r.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local rigs: { [Model]: Rig } = {}
local art: Instance? = nil

local function sync(camPos: Vector3)
	local map = workspace:FindFirstChild("Map")
	local a = map and map:FindFirstChild("Art")
	local pen = a and a:FindFirstChild("Animals")
	if pen and art then
		for _, m in pen:GetChildren() do
			if m:IsA("Model") and Animals.SPECIES[m.Name] and not rigs[m] then
				local p = m:GetPivot().Position
				if (p - camPos).Magnitude * M < VIEW_M and m:FindFirstChildWhichIsA("BasePart", true) then
					local tpl = art:FindFirstChild(m.Name)
					if tpl and tpl:IsA("Model") then
						local r = build(m, m.Name, tpl)
						if r then
							rigs[m] = r
						end
					end
				end
			end
		end
	end
	for m, r in rigs do
		local gone = m.Parent == nil or not m:FindFirstChildWhichIsA("BasePart", true)
		if gone or (r.pos - camPos).Magnitude * M > VIEW_M + 30 then
			release(r)
			rigs[m] = nil
		end
	end
	holder:SetAttribute(
		"Animais",
		(function()
			local n = 0
			for _ in rigs do
				n += 1
			end
			return n
		end)()
	)
end

task.spawn(function()
	art = ReplicatedStorage:WaitForChild("VT65AnimalArt", 900)
end)

local lastSync = 0
RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	local camPos = camera.CFrame.Position
	if now - lastSync > 1 then
		lastSync = now
		sync(camPos)
	end
	for m, r in rigs do
		if m.Parent then
			step(r, math.min(dt, 0.1), now, camPos)
		end
	end
end)
