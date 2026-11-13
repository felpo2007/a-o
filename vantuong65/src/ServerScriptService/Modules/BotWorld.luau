--!strict
-- O mapa como os bots o entendem (D-90; pedido do dono: "faça os bots entenderem ... os locais do
-- jogo"). Montado uma vez, em fatias, depois que o terreno e a arte estão no lugar:
--   - grade de rota (Shared/BotNav) do tamanho da do terreno (16 studs): altura, mar, riacho,
--     paisagem (mata, vila, lavoura, clareira) e as peças do mapa (dique, sebe, lâmina d'água do
--     arrozal, casa, trincheira);
--   - índice de abrigos fixos (dique, sebe, parede de casa, sacos, bunker, trincheira): o bot sabe
--     que há um dique 12 m à frente sem gastar raio;
--   - rótulo "VT65Arrozal" (PathfindingModifier) nas lâminas d'água: o PathfindingService dos
--     trechos curtos também foge do arrozal alagado e prefere o dique;
--   - fila de rotas (A* em fatias de no máximo 2 ms por quadro).
-- Sem a grade (terreno ainda gerando, erro), os bots andam direto com desvio local.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local BotNav = require(ReplicatedStorage.Shared.BotNav)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Tunnels = require(ReplicatedStorage.Shared.Tunnels) :: any

local BotWorld = {}
local M = 0.28
local F = BotNav.F

BotWorld.grid = nil :: BotNav.Grid?
BotWorld.world = nil :: any -- WorldData (alturas bilineares)
BotWorld.ready = false -- grade pronta (rotas)
BotWorld.artReady = false -- abrigos da arte indexados
BotWorld.PADDY_LABEL = "VT65Arrozal"

-- ===== índice de abrigos fixos =====
export type CoverEntry = {
	kind: string, -- BotBrain.COVER
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	half: number, -- meia espessura (studs)
	solid: boolean,
}
local COVER_CELL = 64
local coverCells: { [number]: { CoverEntry } } = {}
local coverCount = 0

local function ckey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

local function addCover(e: CoverEntry)
	local x0 = math.floor((math.min(e.x1, e.x2) - e.half) / COVER_CELL)
	local x1 = math.floor((math.max(e.x1, e.x2) + e.half) / COVER_CELL)
	local z0 = math.floor((math.min(e.z1, e.z2) - e.half) / COVER_CELL)
	local z1 = math.floor((math.max(e.z1, e.z2) + e.half) / COVER_CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local k = ckey(cx, cz)
			local list = coverCells[k]
			if not list then
				list = {}
				coverCells[k] = list
			end
			table.insert(list, e)
		end
	end
	coverCount += 1
end

-- Abrigos fixos a até `radius` studs de pos (sem repetir).
function BotWorld.coversNear(pos: Vector3, radius: number): { CoverEntry }
	local out: { CoverEntry } = {}
	local seen: { [CoverEntry]: boolean } = {}
	local x0, x1 = math.floor((pos.X - radius) / COVER_CELL), math.floor((pos.X + radius) / COVER_CELL)
	local z0, z1 = math.floor((pos.Z - radius) / COVER_CELL), math.floor((pos.Z + radius) / COVER_CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local list = coverCells[ckey(cx, cz)]
			if list then
				for _, e in list do
					if not seen[e] then
						seen[e] = true
						table.insert(out, e)
					end
				end
			end
		end
	end
	return out
end

-- Ponto mais perto de (x, z) no segmento do abrigo e a normal (unitária, horizontal).
function BotWorld.closest(e: CoverEntry, x: number, z: number): (number, number, number, number)
	local dx, dz = e.x2 - e.x1, e.z2 - e.z1
	local l2 = dx * dx + dz * dz
	local t = if l2 > 1e-6 then math.clamp(((x - e.x1) * dx + (z - e.z1) * dz) / l2, 0, 1) else 0
	local px, pz = e.x1 + dx * t, e.z1 + dz * t
	local l = math.sqrt(l2)
	local nx, nz = if l > 1e-6 then -dz / l else 1, if l > 1e-6 then dx / l else 0
	return px, pz, nx, nz
end

-- ===== consultas da grade =====
function BotWorld.flagsAt(pos: Vector3): number
	local g = BotWorld.grid
	return if g then BotNav.flagsAt(g, pos.X, pos.Z) else 0
end

function BotWorld.kindAt(pos: Vector3): number
	local g = BotWorld.grid
	return if g then BotNav.kindAt(g, pos.X, pos.Z) else 0
end

-- Chão para o Movement (superfície e fundura da água, m)
function BotWorld.surface(pos: Vector3): (string, number)
	local g = BotWorld.grid
	if not g then
		return "firm", 0
	end
	local f = BotNav.flagsAt(g, pos.X, pos.Z)
	if bit32.btest(f, F.SEA) then
		return "water", 1.5
	elseif bit32.btest(f, F.STREAM) then
		return "water", BotBrain.NAV.streamDepthM
	elseif bit32.btest(f, F.PADDY) and not bit32.btest(f, F.DIKE) then
		return "paddy", 0.1
	end
	local k = BotNav.kindAt(g, pos.X, pos.Z)
	if k == BotNav.K.FOREST or k == BotNav.K.GROVE then
		return "forest", 0
	elseif k == BotNav.K.FARM or k == BotNav.K.CLEAR then
		return "grass", 0
	end
	return "firm", 0
end

-- Campo aberto (arrozal, clareira, capim da lavoura): squad em cunha; atravessa correndo sob ameaça
function BotWorld.isOpen(pos: Vector3): boolean
	local g = BotWorld.grid
	if not g then
		return false
	end
	local f = BotNav.flagsAt(g, pos.X, pos.Z)
	if bit32.btest(f, F.PADDY) then
		return true
	end
	local k = BotNav.kindAt(g, pos.X, pos.Z)
	return k == BotNav.K.FARM or k == BotNav.K.CLEAR
end

-- Altura do chão (studs) pelos dados do terreno (sem raio)
function BotWorld.heightAt(x: number, z: number): number
	local w = BotWorld.world
	if w then
		return w:heightAt(x, z)
	end
	local g = BotWorld.grid
	return if g then BotNav.heightAt(g, x, z) else 0
end

function BotWorld.villageCenter(): (number, number)
	for _, l in MapConfig.Locations do
		if l.name == "An Cường (2)" then
			return l.x, l.z
		end
	end
	return 0, 0
end

-- ===== fila de rotas =====
type Job = {
	key: string,
	profile: BotNav.Profile,
	from: Vector3,
	to: Vector3,
	cb: ({ Vector3 }?, boolean) -> (),
	search: BotNav.Search?,
}
local jobs: { Job } = {}
local current: Job? = nil

-- Pede uma rota (studs). kind: "infantry" | "tracked" | "amphibious"; spec: ficha do veículo. O
-- retorno vem depois (callback com os pontos e se chegou ao destino; nil sem grade). Um pedido novo
-- com a mesma chave troca o antigo que ainda não começou.
function BotWorld.route(
	key: string,
	kind: string,
	spec: string?,
	from: Vector3,
	to: Vector3,
	cb: ({ Vector3 }?, boolean) -> ()
)
	local g = BotWorld.grid
	if not (BotWorld.ready and g) then
		task.defer(cb, nil, false)
		return
	end
	for i, j in jobs do
		if j.key == key then
			table.remove(jobs, i)
			break
		end
	end
	table.insert(jobs, { key = key, profile = BotNav.profile(kind, spec), from = from, to = to, cb = cb, search = nil })
end

function BotWorld.pending(): number
	return #jobs + (if current then 1 else 0)
end

local function finish(job: Job, ok: boolean, pts: { { x: number, z: number } }?)
	local out: { Vector3 }? = nil
	if pts and #pts > 0 then
		local list: { Vector3 } = {}
		for _, p in pts do
			table.insert(list, Vector3.new(p.x, BotWorld.heightAt(p.x, p.z), p.z))
		end
		out = list
	end
	task.spawn(function()
		local okCb, err = pcall(function(): any
			job.cb(out, ok)
			return nil
		end)
		if not okCb then
			warn("[VT65] bots: rota falhou no retorno:", err)
		end
	end)
end

local function stepJobs()
	local g = BotWorld.grid
	if not g then
		return
	end
	local N = BotBrain.NAV
	local t0 = os.clock()
	while os.clock() - t0 < N.frameBudgetS do
		local cur = current
		if not cur then
			local nextJob = table.remove(jobs, 1)
			if not nextJob then
				return
			end
			nextJob.search =
				BotNav.search(g, nextJob.profile, nextJob.from.X, nextJob.from.Z, nextJob.to.X, nextJob.to.Z)
			current = nextJob
			cur = nextJob
		end
		local job: Job = cur :: Job
		local s = job.search :: BotNav.Search
		local st = BotNav.run(s, math.max(100, N.expandPerFrame // 4))
		if st ~= "running" then
			current = nil
			if st == "done" then
				finish(job, true, BotNav.waypoints(s))
			elseif s.start >= 0 and s.best >= 0 then
				finish(job, false, BotNav.waypoints(s)) -- parcial: até onde dá
			else
				finish(job, false, nil)
			end
		end
	end
end

-- ===== montagem =====
local function yawOf(cf: CFrame): number
	local _, y, _ = cf:ToOrientation()
	return y
end

-- segmento do comprimento (X local) de uma peça fina (dique, sebe)
local function segmentOf(p: BasePart): (number, number, number, number)
	local half = math.max(p.Size.X / 2 - p.Size.Z / 2, 0.5)
	local a = p.CFrame * Vector3.new(-half, 0, 0)
	local b = p.CFrame * Vector3.new(half, 0, 0)
	return a.X, a.Z, b.X, b.Z
end

-- caixa (centro, tamanho) -> segmento do eixo longo e meia espessura
local function boxSegment(cf: CFrame, size: Vector3): (number, number, number, number, number)
	local long = if size.X >= size.Z then Vector3.new(size.X / 2, 0, 0) else Vector3.new(0, 0, size.Z / 2)
	local a, b = cf * long, cf * -long
	return a.X, a.Z, b.X, b.Z, math.min(size.X, size.Z) / 2
end

local function markMapParts(g: BotNav.Grid, map: Instance)
	local n = 0
	local function tick()
		n += 1
		if n % 400 == 0 then
			task.wait()
		end
	end
	local dikes = map:FindFirstChild("Dikes")
	local listdikes: { Instance } = if dikes then dikes:GetChildren() else {}
	for _, p in listdikes do
		if p:IsA("BasePart") then
			local x1, z1, x2, z2 = segmentOf(p)
			BotNav.markSegment(g, x1, z1, x2, z2, F.DIKE)
			addCover({ kind = "dike", x1 = x1, z1 = z1, x2 = x2, z2 = z2, half = p.Size.Z / 2, solid = true })
			tick()
		end
	end
	local hedges = map:FindFirstChild("Hedges")
	local listhedges: { Instance } = if hedges then hedges:GetChildren() else {}
	for _, p in listhedges do
		if p:IsA("BasePart") and p.CanCollide then
			local x1, z1, x2, z2 = segmentOf(p)
			BotNav.markSegment(g, x1, z1, x2, z2, F.HEDGE)
			addCover({ kind = "hedge", x1 = x1, z1 = z1, x2 = x2, z2 = z2, half = p.Size.Z / 2, solid = false })
			tick()
		end
	end
	local waters = map:FindFirstChild("PaddyWater")
	local listwaters: { Instance } = if waters then waters:GetChildren() else {}
	for _, p in listwaters do
		if p:IsA("BasePart") then
			BotNav.markBox(g, p.Position.X, p.Position.Z, p.Size.X, p.Size.Z, yawOf(p.CFrame), F.PADDY)
			-- o PathfindingService dos trechos curtos também paga caro pelo arrozal alagado
			if not p:FindFirstChildOfClass("PathfindingModifier") then
				local mod = Instance.new("PathfindingModifier")
				mod.Label = BotWorld.PADDY_LABEL
				mod.Parent = p
			end
			tick()
		end
	end
	local houses = map:FindFirstChild("Houses")
	local listhouses: { Instance } = if houses then houses:GetChildren() else {}
	for _, h in listhouses do
		local body = h:FindFirstChild("Walls")
		if body and body:IsA("BasePart") then
			BotNav.markBox(g, body.Position.X, body.Position.Z, body.Size.X, body.Size.Z, yawOf(body.CFrame), F.HOUSE)
			local x1, z1, x2, z2, half = boxSegment(body.CFrame, body.Size)
			addCover({ kind = "wall", x1 = x1, z1 = z1, x2 = x2, z2 = z2, half = half, solid = true })
		end
	end
	-- trincheira sul (Shared/Tunnels): célula barata e abrigo
	local cx, cz = BotWorld.villageCenter()
	for i = 1, #Tunnels.trench - 1 do
		local a, b = Tunnels.trench[i], Tunnels.trench[i + 1]
		local x1, z1 = Tunnels.toWorld(cx, cz, a[1], a[2])
		local x2, z2 = Tunnels.toWorld(cx, cz, b[1], b[2])
		BotNav.markSegment(g, x1, z1, x2, z2, F.TRENCH)
		addCover({
			kind = "trench",
			x1 = x1,
			z1 = z1,
			x2 = x2,
			z2 = z2,
			half = Tunnels.TRENCH_W_M / M / 2,
			solid = true,
		})
	end
end

-- Arte posta pelo AssetLoader (casas, celeiros, sacos, bunkers, cerca): casa na grade e abrigo
local function markArt(g: BotNav.Grid, art: Instance)
	local n = 0
	for _, m in art:GetChildren() do
		if m:IsA("Model") and not BotBrain.plantKind(m.Name) then
			local kind = BotBrain.coverKind("MeshPart", m.Name, nil, false)
			if kind ~= "solid" and kind ~= "grass" then
				local cf, size = m:GetBoundingBox()
				if kind == "wall" or kind == "earth" then
					BotNav.markBox(g, cf.X, cf.Z, size.X, size.Z, yawOf(cf), F.HOUSE)
				end
				local x1, z1, x2, z2, half = boxSegment(cf, size)
				local info = BotBrain.COVER[kind] or BotBrain.COVER.solid
				addCover({ kind = kind, x1 = x1, z1 = z1, x2 = x2, z2 = z2, half = half, solid = info.solid })
				n += 1
				if n % 200 == 0 then
					task.wait()
				end
			end
		end
	end
	return n
end

local function build()
	while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
		ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
	end
	local t0 = os.clock()
	local okW, world = pcall(function(): any
		return (require(ServerStorage:WaitForChild("VT65Build"):WaitForChild("Build")) :: any).world()
	end)
	if not okW or not world then
		warn("[VT65] bots: sem dados do terreno; andam direto", world)
		return
	end
	BotWorld.world = world
	-- paisagem igual à do bake (casas dos dados do mapa)
	local VT65Build = ServerStorage:WaitForChild("VT65Build")
	local features = require(VT65Build:WaitForChild("Data"):WaitForChild("Features")) :: any
	local housesXZ: { number } = {}
	for i = 1, #features.houses, 4 do
		table.insert(housesXZ, features.houses[i])
		table.insert(housesXZ, features.houses[i + 1])
	end
	-- a mesma paisagem do plano da arte (2026-11-12): vila grande e as lâminas que ficaram
	local villageModule = VT65Build:WaitForChild("Data"):FindFirstChild("Village")
	local village = if villageModule then require(villageModule :: ModuleScript) :: any else nil
	if village then
		for _, h in village.houses do
			table.insert(housesXZ, h[1])
			table.insert(housesXZ, h[2])
		end
	end
	local landscape = (require(VT65Build:WaitForChild("Landscape")) :: any).new(
		world,
		MapConfig,
		housesXZ,
		village,
		features.waters
	)
	local g = BotNav.forWorld(world)
	local kindAt = function(x: number, z: number): number
		return landscape:kindAt(x, z)
	end
	-- 4 linhas por quadro (~2 mil células com paisagem): o servidor não engasga ao montar
	for r = 0, g.h - 1, 4 do
		BotNav.fillRows(g, world, kindAt, MapConfig.Bounds, r, r + 4)
		task.wait()
	end
	-- estradas de terra batida (2026-11-12, Data/Roads): o blindado de bot anda nelas
	local roadsModule = VT65Build:WaitForChild("Data"):FindFirstChild("Roads")
	if roadsModule then
		BotNav.markRoads(g, require(roadsModule :: ModuleScript) :: any)
	end
	local map = workspace:FindFirstChild("Map") or workspace:WaitForChild("Map", 30)
	if map then
		markMapParts(g, map)
	end
	BotWorld.grid = g
	BotWorld.ready = true
	print(string.format("[VT65] bots: mapa pronto em %.1f s (%d abrigos fixos)", os.clock() - t0, coverCount))
	-- arte (casas de verdade, sacos, bunkers): espera o AssetLoader terminar (até 3 min)
	local art = map and map:FindFirstChild("Art")
	local waited = 0
	while waited < 180 and not (art and art:GetAttribute("Placed") == true) do
		task.wait(2)
		waited += 2
		art = map and map:FindFirstChild("Art")
	end
	if art then
		local n = markArt(g, art)
		print(string.format("[VT65] bots: %d peças de arte viraram abrigo", n))
	end
	BotWorld.artReady = true
end

function BotWorld.start()
	task.spawn(function()
		local ok, err = pcall(function(): any
			build()
			return nil
		end)
		if not ok then
			warn("[VT65] bots: falha ao montar o mapa:", err)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if current or #jobs > 0 then
			local ok, err = pcall(function(): any
				stepJobs()
				return nil
			end)
			if not ok then
				current = nil
				warn("[VT65] bots: rota falhou:", err)
			end
		end
	end)
end

return BotWorld
