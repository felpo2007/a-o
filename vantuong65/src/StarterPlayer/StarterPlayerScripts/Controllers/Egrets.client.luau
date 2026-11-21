--!strict
-- Garças no arrozal (D-76; regras em Shared/Egrets). Bandos nos tabuleiros alagados perto da câmera
-- e uma garça junto de cada búfalo. Tiro (dos outros pelo Combat_Tracer, o seu pelo Bus) e
-- explosão fazem a garça levantar voo, subir e sumir; o bando volta ao tabuleiro depois.
-- Peças simples feitas aqui (8 por garça), só no cliente; nada vai para a rede.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bus = require(script.Parent:WaitForChild("Bus"))
local Egrets = require(ReplicatedStorage.Shared.Egrets)
local Net = require(ReplicatedStorage.Shared.Net)

local M = 0.28
local camera = workspace.CurrentCamera
local HIDDEN = CFrame.new(0, -5000, 0)
local WHITE = Color3.fromRGB(240, 240, 232)

local holder = Instance.new("Folder")
holder.Name = "VT65Garcas"
holder.Parent = workspace

type Bird = {
	parts: { BasePart },
	root: CFrame, -- pé da garça, olhando para -Z
	state: string, -- "stand" | "fly" | "away"
	t0: number,
	dir: Vector3,
	start: Vector3,
	peckUntil: number,
	nextPeck: number,
	seed: number,
	scale: number, -- 1 = garça-vaqueira (~0,65 m em pé); 1,5 = garça-branca-grande (~0,95 m)
}
type Flock = { birds: { Bird }, returnAt: number }

-- tamanhos na escala 1 (studs): corpo, pescoço, cabeça, bico, pernas e asas. Tudo arredondado
-- (malha de esfera esticada): com placas retas a garça parada parecia uma caixa (Studio, 2026-11-11)
local BASE_SIZES = {
	Vector3.new(0.55, 0.58, 1.2),
	Vector3.new(0.17, 0.95, 0.17),
	Vector3.new(0.3, 0.3, 0.3),
	Vector3.new(0.07, 0.07, 0.42),
	Vector3.new(0.07, 1.05, 0.07),
	Vector3.new(0.07, 1.05, 0.07),
	Vector3.new(1.0, 0.07, 0.6),
	Vector3.new(1.0, 0.07, 0.6),
}

-- peças: corpo, pescoço, cabeça, bico, 2 pernas, 2 asas
local function makePart(size: Vector3, color: Color3, shape: string?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.CFrame = HIDDEN
	p.Parent = holder
	return p
end

local pool: { Bird } = {}
local function newBird(seed: number): Bird
	local b = table.remove(pool)
	if not b then
		local leg = Color3.fromRGB(58, 54, 46)
		local parts = {
			makePart(BASE_SIZES[1], WHITE, "egg"),
			makePart(BASE_SIZES[2], WHITE, "egg"),
			makePart(BASE_SIZES[3], WHITE, "ball"),
			makePart(BASE_SIZES[4], Color3.fromRGB(226, 186, 72)),
			makePart(BASE_SIZES[5], leg),
			makePart(BASE_SIZES[6], leg),
			makePart(BASE_SIZES[7], WHITE, "egg"),
			makePart(BASE_SIZES[8], WHITE, "egg"),
		}
		b = {
			parts = parts,
			root = HIDDEN,
			state = "stand",
			t0 = 0,
			dir = Vector3.zero,
			start = Vector3.zero,
			peckUntil = 0,
			nextPeck = 0,
			seed = seed,
			scale = 1,
		}
	end
	local bird = b :: Bird
	bird.state, bird.seed, bird.peckUntil = "stand", seed, 0
	bird.nextPeck = os.clock() + 1 + (seed % 7) * 0.6
	-- 2 em cada 5 são garças-brancas-grandes (Ardea alba), o resto garça-vaqueira
	local s = if seed % 5 < 2 then 1.5 else 1.05
	if s ~= bird.scale or bird.parts[1].Size ~= BASE_SIZES[1] * s then
		bird.scale = s
		for i, p in bird.parts do
			p.Size = BASE_SIZES[i] * s
		end
		-- bico amarelo na vaqueira, amarelo-escuro na grande
		bird.parts[4].Color = if s > 1.2 then Color3.fromRGB(214, 168, 52) else Color3.fromRGB(232, 190, 72)
	end
	return bird
end

-- pose: wing = ângulo da asa (rad), ou nil para asa recolhida junto do corpo; pitch do corpo;
-- peck = cabeça abaixada (0–1); legsUp = pernas esticadas para trás (voo)
local function pose(b: Bird, wing: number?, pitch: number, peck: number, legsUp: boolean): { CFrame }
	local s = b.scale
	local function o(x: number, y: number, z: number): CFrame
		return CFrame.new(x * s, y * s, z * s)
	end
	local r = b.root * CFrame.Angles(pitch, 0, 0)
	local headDrop = peck * 0.9
	local legs = if legsUp
		then {
			r * o(-0.1, 1.2, 0.75) * CFrame.Angles(1.4, 0, 0),
			r * o(0.1, 1.2, 0.75) * CFrame.Angles(1.4, 0, 0),
		}
		else { r * o(-0.12, 0.52, 0.05), r * o(0.12, 0.52, 0.05) }
	local body = r * o(0, 1.25, 0) * CFrame.Angles(if legsUp then 0 else math.rad(15), 0, 0)
	local wings = if wing
		then {
			r * o(-0.2, 1.35, 0.05) * CFrame.Angles(0, 0, -wing) * o(-0.5, 0, 0),
			r * o(0.2, 1.35, 0.05) * CFrame.Angles(0, 0, wing) * o(0.5, 0, 0),
		}
		else {
			-- recolhida: comprida ao longo do corpo e chapada no flanco, quase toda dentro dele (com
			-- o giro anterior a ponta ficava em pé, como uma barbatana; Studio, 2026-11-11)
			body
				* o(-0.17, 0, 0.08)
				* CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, -Vector3.xAxis),
			body * o(0.17, 0, 0.08) * CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.xAxis),
		}
	-- em voo a garça encolhe o pescoço em S (cabeça junto do ombro)
	local neckY, headY, headZ =
		if legsUp then 1.5 else 1.78, if legsUp then 1.55 else 2.22, if legsUp then -0.62 else -0.62
	return {
		body,
		r
			* o(0, neckY - headDrop * 0.4, -0.45 - headDrop * 0.2)
			* CFrame.Angles(if legsUp then math.rad(-70) else math.rad(-18) - peck * 0.9, 0, 0),
		r * o(0, headY - headDrop, headZ - headDrop * 0.45),
		r * o(0, headY - 0.04 - headDrop, headZ - 0.27 - headDrop * 0.5) * CFrame.Angles(-peck * 0.6, 0, 0),
		legs[1],
		legs[2],
		wings[1],
		wings[2],
	}
end

local function place(b: Bird, cfs: { CFrame })
	workspace:BulkMoveTo(b.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function hide(b: Bird)
	local cfs = table.create(#b.parts, HIDDEN)
	place(b, cfs)
end

local function release(b: Bird)
	hide(b)
	table.insert(pool, b)
end

local flocks: { [BasePart]: Flock } = {}
local companions: { [Model]: Flock } = {}

local function standAll(f: Flock)
	for _, b in f.birds do
		b.state = "stand"
		place(b, pose(b, nil, 0, 0, false))
	end
end

local function spawnFlock(part: BasePart, n: number): Flock
	local f: Flock = { birds = {}, returnAt = 0 }
	local top = part.Position.Y + part.Size.Y / 2
	for i = 1, n do
		local lx, lz, yaw = Egrets.spot(part.Position.X, part.Position.Z, part.Size.X, part.Size.Z, i)
		local w = part.CFrame:PointToWorldSpace(Vector3.new(lx, 0, lz))
		local b = newBird(i * 31 + math.floor(part.Position.X))
		b.root = CFrame.new(w.X, top - 0.3, w.Z) * CFrame.Angles(0, yaw, 0)
		table.insert(f.birds, b)
	end
	standAll(f)
	return f
end

local function dropFlock(f: Flock)
	for _, b in f.birds do
		release(b)
	end
	table.clear(f.birds)
end

-- assusta todas as garças em pé que ouvem o barulho em pos (studs)
local function noise(pos: Vector3, explosion: boolean)
	local now = os.clock()
	local function scare(f: Flock)
		local any = false
		for _, b in f.birds do
			local p = b.root.Position
			if b.state == "stand" and Egrets.hears(p.X * M, p.Z * M, pos.X * M, pos.Z * M, explosion) then
				local away = Vector3.new(p.X - pos.X, 0, p.Z - pos.Z)
				local ang = ((b.seed % 9) - 4) * 0.1
				local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
				b.dir = (CFrame.Angles(0, ang, 0) * dir).Unit
				b.state = "fly"
				b.t0 = now + (b.seed % 5) * 0.12 -- decolagem escalonada
				b.start = p
				any = true
			end
		end
		if any then
			local span = Egrets.RETURN_S[2] - Egrets.RETURN_S[1]
			f.returnAt = now + Egrets.RETURN_S[1] + (math.floor(now * 10) % 100) / 100 * span
		end
	end
	for _, f in flocks do
		scare(f)
	end
	for _, f in companions do
		scare(f)
	end
end

Net.unreliable("Combat_Tracer").OnClientEvent:Connect(function(shot: any)
	if type(shot) == "table" and type(shot.ox) == "number" then
		noise(Vector3.new(shot.ox, shot.oy, shot.oz), false)
	end
end)
Bus.on("shot_fired", function(shot: any)
	if type(shot) == "table" and type(shot.ox) == "number" then
		noise(Vector3.new(shot.ox, shot.oy, shot.oz), false)
	end
end)
Net.unreliable("Fire_Impact").OnClientEvent:Connect(function(e: any)
	if type(e) == "table" and type(e.x) == "number" then
		noise(Vector3.new(e.x, e.y, e.z), true)
	end
end)

-- voo, quadro a quadro, só de quem está voando
local function stepFlight(f: Flock, now: number)
	local flying = false
	for _, b in f.birds do
		if b.state == "fly" then
			local t = now - b.t0
			if t >= Egrets.FLIGHT_S then
				b.state = "away"
				hide(b)
			elseif t >= 0 then
				flying = true
				local along, alt = Egrets.flight(t)
				local pos = b.start + b.dir * (along / M) + Vector3.new(0, alt / M, 0)
				local climb = if t < Egrets.CLIMB_S then -0.35 else 0
				b.root = CFrame.lookAt(pos, pos + b.dir) * CFrame.new(0, -1.25 * b.scale, 0)
				local beat = if t < 6 then 3.4 else 1.6
				local amp = if t < 6 then 0.85 else 0.35
				local wing = 0.15 + math.sin(now * 2 * math.pi * beat + b.seed) * amp
				place(b, pose(b, wing, climb, 0, true))
			end
		end
	end
	return flying
end

-- bicada de vez em quando (só muda peça no começo e no fim da bicada)
local function stepIdle(f: Flock, now: number)
	for _, b in f.birds do
		if b.state == "stand" then
			if b.peckUntil > 0 and now >= b.peckUntil then
				b.peckUntil = 0
				place(b, pose(b, nil, 0, 0, false))
			elseif b.peckUntil == 0 and now >= b.nextPeck then
				b.peckUntil = now + 0.5
				b.nextPeck = now + 2 + (b.seed % 11) * 0.5
				place(b, pose(b, nil, 0, 1, false))
			end
		end
	end
end

local function allAway(f: Flock): boolean
	for _, b in f.birds do
		if b.state ~= "away" then
			return false
		end
	end
	return #f.birds > 0
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

-- bandos dos tabuleiros e companheiras dos búfalos: cria perto, solta longe, devolve depois do susto
local function manage(camPos: Vector3, now: number)
	local map = workspace:FindFirstChild("Map")
	local water = map and map:FindFirstChild("PaddyWater")
	if water then
		for _, part in water:GetChildren() do
			if part:IsA("BasePart") then
				local d = (Vector3.new(part.Position.X, camPos.Y, part.Position.Z) - camPos).Magnitude * M
				local f = flocks[part]
				if d < Egrets.VIEW_M and not f then
					local n = Egrets.flockSize(part.Position.X, part.Position.Z)
					if n > 0 then
						flocks[part] = spawnFlock(part, n)
					end
				elseif f and (d > Egrets.DROP_M or part.Parent == nil) then
					dropFlock(f)
					flocks[part] = nil
				elseif f and allAway(f) and now >= f.returnAt then
					dropFlock(f) -- o bando volta ao tabuleiro
					flocks[part] = spawnFlock(part, Egrets.flockSize(part.Position.X, part.Position.Z))
				end
			end
		end
		for part, f in flocks do
			if part.Parent == nil then
				dropFlock(f)
				flocks[part] = nil
			end
		end
	end
	-- uma garça junto de cada búfalo (garça-vaqueira), andando com ele
	local art = map and map:FindFirstChild("Art")
	local pen = art and art:FindFirstChild("Animals")
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	for _, m in if pen then pen:GetChildren() else {} do
		if m:IsA("Model") and m.Name == "water_buffalo" then
			local p = m:GetPivot()
			local d = (Vector3.new(p.X, camPos.Y, p.Z) - camPos).Magnitude * M
			local f: Flock? = companions[m]
			if d < Egrets.VIEW_M * 0.8 and not f then
				local nf: Flock = { birds = { newBird(math.floor(p.X) % 97) }, returnAt = 0 }
				companions[m] = nf
				f = nf
			elseif f and d > Egrets.DROP_M then
				dropFlock(f)
				companions[m] = nil
				f = nil
			end
			if f then
				local b = f.birds[1]
				if b and b.state == "stand" then
					local spot = p * CFrame.new(3.2, 0, -1.5)
					local hit =
						workspace:Raycast(spot.Position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), groundParams)
					if hit then
						local yaw = select(2, p:ToOrientation())
						b.root = CFrame.new(hit.Position.X, hit.Position.Y, hit.Position.Z)
							* CFrame.Angles(0, yaw + 0.6, 0)
						if b.peckUntil == 0 then
							place(b, pose(b, nil, 0, 0, false))
						end
					end
				elseif b and allAway(f) and now >= f.returnAt then
					b.state = "stand"
				end
			end
		end
	end
	for m, f in companions do
		if m.Parent == nil then
			dropFlock(f)
			companions[m] = nil
		end
	end
	-- contagem para o teste no Studio
	local n, birds = 0, 0
	for _, f in flocks do
		n += 1
		birds += #f.birds
	end
	for _, f in companions do
		birds += #f.birds
	end
	holder:SetAttribute("Bandos", n)
	holder:SetAttribute("Garcas", birds)
end

local lastManage = 0
local lastBuffalo = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local camPos = camera.CFrame.Position
	if now - lastManage > 1 then
		lastManage = now
		manage(camPos, now)
	elseif now - lastBuffalo > 0.5 then
		-- búfalo andando: a companheira acompanha mais vezes que o resto
		lastBuffalo = now
		for m, f in companions do
			local b = f.birds[1]
			if b and b.state == "stand" and m.Parent then
				local p = m:GetPivot()
				local spot = p * CFrame.new(3.2, 0, -1.5)
				local cur = b.root.Position
				if (Vector3.new(spot.X, cur.Y, spot.Z) - cur).Magnitude > 1 then
					local yaw = select(2, p:ToOrientation())
					b.root = CFrame.new(spot.X, cur.Y, spot.Z) * CFrame.Angles(0, yaw + 0.6, 0)
					place(b, pose(b, nil, 0, 0, false))
				end
			end
		end
	end
	for _, f in flocks do
		if not stepFlight(f, now) then
			stepIdle(f, now)
		end
	end
	for _, f in companions do
		if not stepFlight(f, now) then
			stepIdle(f, now)
		end
	end
end)
