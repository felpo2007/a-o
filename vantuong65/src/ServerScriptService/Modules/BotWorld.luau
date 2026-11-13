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

-- ===== eixo das estradas =====
-- A rota sai da grade em centros de célula (16 studs): na rua da base o blindado andava 8 studs fora
-- do eixo e batia na guarita do portão (vão de 22 studs para um casco de 13; teste da v38). Os
-- pontos da rota de VEÍCULO que caem no leito de uma estrada vão para o eixo dela.
type RoadSeg = { x1: number, z1: number, x2: number, z2: number, half: number }
local roadSegs: { RoadSeg } = {}
local ROAD_SNAP_EXTRA = 4 -- studs além da meia largura do leito
local DENSIFY = 24 -- studs entre pontos da rota de veículo antes de alinhar

local function loadRoadSegs(roads: any)
	for _, r in roads.roads do
		local half = (roads.width[r.kind] or 20) / 2
		local p = r.pts
		for i = 1, #p - 5, 3 do
			table.insert(roadSegs, { x1 = p[i], z1 = p[i + 1], x2 = p[i + 3], z2 = p[i + 4], half = half })
		end
	end
end

local function snapToRoad(x: number, z: number): (number, number)
	local bx, bz, bd = x, z, math.huge
	for _, s in roadSegs do
		local lim = s.half + ROAD_SNAP_EXTRA
		if
			x < math.min(s.x1, s.x2) - lim
			or x > math.max(s.x1, s.x2) + lim
			or z < math.min(s.z1, s.z2) - lim
			or z > math.max(s.z1, s.z2) + lim
		then
			continue
		end
		local dx, dz = s.x2 - s.x1, s.z2 - s.z1
		local l2 = dx * dx + dz * dz
		local t = if l2 > 1e-6 then math.clamp(((x - s.x1) * dx + (z - s.z1) * dz) / l2, 0, 1) else 0
		local px, pz = s.x1 + dx * t, s.z1 + dz * t
		local d = (x - px) ^ 2 + (z - pz) ^ 2
		if d < bd and d <= lim * lim then
			bd, bx, bz = d, px, pz
		end
	end
	return bx, bz
end

-- Trecho de estrada feito no jogo (aterro da saída da base, VehicleService): entra no alinhamento
-- das rotas e, na grade, vira leito de estrada (agora ou quando a grade ficar pronta).
local pendingRoads: { any } = {}
function BotWorld.addRoad(x1: number, z1: number, x2: number, z2: number, widthStuds: number)
	table.insert(roadSegs, { x1 = x1, z1 = z1, x2 = x2, z2 = z2, half = widthStuds / 2 })
	local roads = { width = { aterro = widthStuds }, roads = { { kind = "aterro", pts = { x1, z1, 0, x2, z2, 0 } } } }
	local g = BotWorld.grid
	if g then
		BotNav.markRoads(g, roads)
	else
		table.insert(pendingRoads, roads)
	end
end

-- Pontos onde veículo não passa (leito de vala ao lado de um aterro, VehicleService): marca de sebe,
-- que só pesa para a lagarta e o anfíbio; a estrada por cima continua aberta.
local pendingBlocks: { Vector3 } = {}
function BotWorld.blockForVehicles(points: { Vector3 })
	local g = BotWorld.grid
	for _, p in points do
		if g then
			BotNav.markPoint(g, p.X, p.Z, F.HEDGE)
		else
			table.insert(pendingBlocks, p)
		end
	end
end

-- Pontos a cada DENSIFY studs; os do meio que estão no leito vão para o eixo (o primeiro e o último
-- ficam: são o veículo e o destino).
local function alignVehicleRoute(pts: { { x: number, z: number } }): { { x: number, z: number } }
	if #roadSegs == 0 or #pts < 2 then
		return pts
	end
	local out: { { x: number, z: number } } = { pts[1] }
	for k = 2, #pts do
		local a, b = pts[k - 1], pts[k]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local n = math.max(1, math.ceil(len / DENSIFY))
		for j = 1, n do
			local t = j / n
			local x, z = a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
			if not (k == #pts and j == n) then
				x, z = snapToRoad(x, z)
			end
			table.insert(out, { x = x, z = z })
		end
	end
	return out
end

-- ===== obstáculo aprendido =====
-- Veículo de bot preso contra uma peça fixa que a grade não conhece (poste, mureta, tronco que o
-- markTrunks não pegou; teste da v38: o M48 e o LVTP-5 paravam num tronco e a rota nova passava no
-- mesmo lugar). A célula do obstáculo ganha a marca de sebe: o veículo não passa e a infantaria
-- não sente. Nunca no leito da estrada (o portão e as pontes ficam abertos) nem dentro das bases
-- (lá a grade já tem as peças certas) e com teto, para um erro não fechar o mapa.
local LEARN_MAX = 300
local LEARN_BASE_R = 65 / M -- raio das bases a partir do QG (studs)
local learned = 0

-- dir: 1 = estava indo para a frente, -1 = de ré. ignore: o próprio veículo e o que se mexe.
function BotWorld.learnObstacle(chassis: BasePart, dir: number, ignore: { Instance }): number
	local g = BotWorld.grid
	if not g or learned >= LEARN_MAX then
		return 0
	end
	local pos = chassis.Position
	for _, hq in MapConfig.HQ do
		if (pos.X - hq.x) ^ 2 + (pos.Z - hq.z) ^ 2 < LEARN_BASE_R ^ 2 then
			return 0
		end
	end
	local probe = chassis.CFrame * CFrame.new(0, 0, -dir * (chassis.Size.Z / 2 + 3))
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local n = 0
	for _, h in workspace:GetPartBoundsInBox(probe, Vector3.new(chassis.Size.X + 2, chassis.Size.Y, 6), params) do
		if h ~= workspace.Terrain and h.CanCollide and h.Anchored then
			-- ponto da peça mais perto do veículo (uma casa grande tem o centro longe)
			local rel = h.CFrame:PointToObjectSpace(pos)
			local half = h.Size / 2
			local near = h.CFrame:PointToWorldSpace(
				Vector3.new(
					math.clamp(rel.X, -half.X, half.X),
					math.clamp(rel.Y, -half.Y, half.Y),
					math.clamp(rel.Z, -half.Z, half.Z)
				)
			)
			if BotNav.kindAt(g, near.X, near.Z) ~= BotNav.K.ROAD then
				if h.Size.X < 30 and h.Size.Z < 30 then
					local _, yaw, _ = h.CFrame:ToOrientation()
					BotNav.markBox(g, h.Position.X, h.Position.Z, h.Size.X, h.Size.Z, yaw, F.HEDGE)
				end
				BotNav.markPoint(g, near.X, near.Z, F.HEDGE)
				n += 1
				if n >= 4 then
					break
				end
			end
		end
	end
	learned += n
	return n
end

-- ===== fila de rotas =====
type Job = {
	key: string,
	vehicle: boolean,
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
	table.insert(jobs, {
		key = key,
		vehicle = kind ~= "infantry",
		profile = BotNav.profile(kind, spec),
		from = from,
		to = to,
		cb = cb,
		search = nil,
	})
end

function BotWorld.pending(): number
	return #jobs + (if current then 1 else 0)
end

local function finish(job: Job, ok: boolean, pts: { { x: number, z: number } }?)
	local out: { Vector3 }? = nil
	if pts and job.vehicle then
		pts = alignVehicleRoute(pts)
	end
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

-- Peças das bases (2026-11-13) que o bot contorna mas que não são abrigo: a lona e o bambu deixam a
-- bala passar, mas seguram quem anda (a colisão Colisao_* do Blender). O arame em concertina e o
-- gerador também (teste da v38: sem eles na grade, a rota do blindado de bot cortava a cerca e
-- empacava no arame em vez de sair pelo portão da base).
local NAV_BLOCK: { [string]: boolean } = {
	us_tent_gp_medium = true,
	us_tent_gp_large = true,
	us_command_tent = true,
	us_mess_tent = true,
	us_concertina = true,
	us_flagpole = true,
	us_generator = true,
	us_fuel_drums = true,
	us_water_trailer = true,
	vc_lean_to = true,
	vc_hoang_cam_kitchen = true,
	vc_car_shelter = true,
}

-- Tronco de árvore com colisão (Madeira0_0 das árvores prontas, D-67): célula com a marca de sebe,
-- que para o veículo (hedge = infinito na lagarta e no anfíbio) e não pesa para a infantaria. Teste
-- da v38: a mata e o bosque eram só "caros" para o blindado de bot, e a rota atravessava capões de
-- árvore no meio do campo, onde o tanque encalhava entre os troncos.
local function markTrunks(g: BotNav.Grid, folder: Instance): number
	local n = 0
	for i, m in folder:GetChildren() do
		if i % 300 == 0 then
			task.wait()
		end
		if m:IsA("Model") and BotBrain.plantKind(m.Name) then
			local trunk = m:FindFirstChild("Madeira0_0", true)
			if trunk and trunk:IsA("BasePart") and trunk.CanCollide then
				-- a peça do tronco leva os galhos grossos: a pegada dela (até 24 studs), não só o centro
				-- (no teste o LVTP-5 encalhou num tronco inclinado com o centro na célula do lado)
				local _, yaw, _ = trunk.CFrame:ToOrientation()
				BotNav.markBox(
					g,
					trunk.Position.X,
					trunk.Position.Z,
					math.min(trunk.Size.X, 24),
					math.min(trunk.Size.Z, 24),
					yaw,
					F.HEDGE
				)
				n += 1
			end
		end
	end
	return n
end

-- Arte posta pelo AssetLoader (casas, celeiros, sacos, bunkers, cerca): casa na grade e abrigo
local function markArt(g: BotNav.Grid, art: Instance)
	local n = 0
	local trunks = markTrunks(g, art)
	local jungle = art:FindFirstChild("Jungle")
	if jungle then
		trunks += markTrunks(g, jungle)
	end
	print(string.format("[VT65] bots: %d troncos de árvore barram os veículos", trunks))
	for _, m in art:GetChildren() do
		if m:IsA("Model") and NAV_BLOCK[m.Name] then
			local cf, size = m:GetBoundingBox()
			BotNav.markBox(g, cf.X, cf.Z, size.X, size.Z, yawOf(cf), F.HOUSE)
		end
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
		local roads = require(roadsModule :: ModuleScript) :: any
		BotNav.markRoads(g, roads)
		loadRoadSegs(roads)
	end
	local map = workspace:FindFirstChild("Map") or workspace:WaitForChild("Map", 30)
	if map then
		markMapParts(g, map)
	end
	BotWorld.grid = g
	for _, roads in pendingRoads do
		BotNav.markRoads(g, roads)
	end
	table.clear(pendingRoads)
	for _, p in pendingBlocks do
		BotNav.markPoint(g, p.X, p.Z, F.HEDGE)
	end
	table.clear(pendingBlocks)
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
