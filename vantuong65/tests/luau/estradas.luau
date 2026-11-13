--!strict
-- Estradas e veículos no mapa (pedido do dono, 2026-11-12: "os veículos conseguem andar em todo o
-- mapa sem bugar?" e "faça vários caminhos no mapa para que os veículos possam andar, porém um
-- principal que interliga todos os objetivos"). Uso: lune run tests/luau/estradas.luau
--
-- O chão é o que o TerrainBuilder gera (ArtPlan.column: riacho, tabuleiros, diques em lombada,
-- patamares, estradas). As regras de subida são as do VehicleDrive (só leitura):
--   - rampa: sobe se tan(rampa) < min(mu do chão x tração das rodas, esforço trator) - crr;
--   - degrau: até CLIMB_STEP_M (lagarta) ou stepM (rodas) entre dois pontos a 2 m;
--   - água: fundura abaixo do vau (fordM); o LVTP-5 flutua.
-- Grade de 2 m na área toda; construções (pegada + meia largura do veículo) bloqueiam. Tronco de
-- árvore não segura veículo (D-67) e a moita não tem colisão.
local process = require("@lune/process")

local R = require :: any
local WorldData = R("../../src/ServerStorage/VT65Build/WorldData")
local Grid = R("../../src/ServerStorage/VT65Build/Data/Grid")
local Features = R("../../src/ServerStorage/VT65Build/Data/Features")
local Village = R("../../src/ServerStorage/VT65Build/Data/Village")
local Roads = R("../../src/ServerStorage/VT65Build/Data/Roads")
local MapConfig = R("../../src/ReplicatedStorage/Shared/MapConfig")
local VehicleDrive = R("../../src/ReplicatedStorage/Shared/VehicleDrive")
local AssetIds = R("../../src/ReplicatedStorage/Shared/AssetIds")
local ArtPlan = R("../../src/ServerScriptService/Modules/ArtPlan")
local TerrainBuilder = R("../../src/ServerStorage/VT65Build/TerrainBuilder")

local M = 0.28
local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FALHA " .. name .. ": " .. tostring(err))
	end
end

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, R("../../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)
local Bases = R("../../src/ServerStorage/VT65Build/Data/Bases")
local ctx =
	ArtPlan.load(world, { features = Features, village = Village, roads = Roads, bases = Bases, mapConfig = MapConfig })
local structures = ArtPlan.structures(ctx, function(k: string): boolean
	local id = AssetIds.Models[k]
	return type(id) == "number" and id ~= 0
end)

-- ===== grade de 2 m com o chão gerado =====
local STEP = 2 / M
local B = MapConfig.Bounds
local W = math.floor((B.maxX - B.minX) / STEP)
local H = math.floor((B.maxZ - B.minZ) / STEP)
local N = W * H
local hgt = table.create(N, 0) :: { number }
local depth = table.create(N, 0) :: { number } -- fundura da água (m)
local ground = table.create(N, "") :: { string }
local t0 = os.clock()
for r = 0, H - 1 do
	for c = 0, W - 1 do
		local x, z = B.minX + (c + 0.5) * STEP, B.minZ + (r + 0.5) * STEP
		local h, wl, cls, mat = ArtPlan.column(ctx, x, z)
		local i = r * W + c + 1
		hgt[i] = h
		depth[i] = math.max(wl - h, 0) * M
		local g: string
		if mat == "Ground" then
			g = "dirt"
		elseif cls == 5 then
			g = if depth[i] > 0 then "water" else "mud"
		elseif TerrainBuilder.paddyTop(ctx.paddies, x, z, 0) then
			g = "paddy" -- a lâmina (peça) por cima do capim
		elseif cls == 3 then
			g = "forest"
		elseif cls == 0 or cls == 1 then
			g = "sand"
		else
			g = "grass"
		end
		ground[i] = g
	end
end
print(string.format("       grade de %d x %d (2 m) com o chão do plano em %.1f s", W, H, os.clock() - t0))

-- construções: pegada + folga (meia largura do veículo), rasterizada na grade
local function blockedGrid(halfM: number): { boolean }
	local blk = table.create(N, false) :: { boolean }
	local pad = halfM / M
	for _, s in structures do
		if s.padded or s.group == "house" or s.group == "village" or s.group == "special" or s.group == "base" then
			local ca, sa = math.cos(s.yaw), math.sin(s.yaw)
			local ex, ez = s.hx + pad, s.hz + pad
			local rr = math.sqrt(ex * ex + ez * ez)
			local c0, c1 = math.floor((s.x - rr - B.minX) / STEP), math.floor((s.x + rr - B.minX) / STEP)
			local r0, r1 = math.floor((s.z - rr - B.minZ) / STEP), math.floor((s.z + rr - B.minZ) / STEP)
			for r = math.max(r0, 0), math.min(r1, H - 1) do
				for c = math.max(c0, 0), math.min(c1, W - 1) do
					local x, z = B.minX + (c + 0.5) * STEP, B.minZ + (r + 0.5) * STEP
					local dx, dz = x - s.x, z - s.z
					if math.abs(dx * ca - dz * sa) <= ex and math.abs(dx * sa + dz * ca) <= ez then
						blk[r * W + c + 1] = true
					end
				end
			end
		end
	end
	return blk
end

type Veh = { id: string, halfM: number, rain: number }
local function climbTan(spec: any, g: string, rain: number): number
	local gr = VehicleDrive.ground(g, rain, spec.wheeled)
	local drive = math.min(gr.mu * (spec.driven or 1), spec.tractive)
	return drive - gr.crr
end

-- busca em largura nas 8 vizinhas; reverse = arestas ao contrário (quem chega ao ponto)
local function reach(v: Veh, blk: { boolean }, start: number, reverse: boolean): { boolean }
	local spec = VehicleDrive.DRIVE[v.id]
	local stepM = spec.stepM or VehicleDrive.CLIMB_STEP_M
	local tanBy: { [string]: number } = {}
	for _, g in { "dirt", "earth", "grass", "forest", "sand", "mud", "paddy", "water" } do
		tanBy[g] = climbTan(spec, g, v.rain)
	end
	local seen = table.create(N, false) :: { boolean }
	local queue = { start }
	seen[start] = true
	local head = 1
	local function ok(a: number, b: number, dist: number): boolean
		if blk[b] or depth[b] >= spec.fordM then
			return false
		end
		-- de a para b (na busca reversa, a aresta real é b -> a)
		local from, to = if reverse then b else a, if reverse then a else b
		local dh = (hgt[to] - hgt[from]) * M
		if dh > stepM then
			return false
		end
		local slope = dh / dist
		if slope > 0 then
			return slope < (tanBy[ground[to]] or 0)
		end
		return -slope < 1.0 -- descida de até 45°
	end
	while head <= #queue do
		local i = queue[head]
		head += 1
		local r = (i - 1) // W
		local c = (i - 1) - r * W
		for dr = -1, 1 do
			for dc = -1, 1 do
				if dr ~= 0 or dc ~= 0 then
					local rr, cc = r + dr, c + dc
					if rr >= 0 and rr < H and cc >= 0 and cc < W then
						local j = rr * W + cc + 1
						if not seen[j] and ok(i, j, if dr ~= 0 and dc ~= 0 then 2.83 else 2) then
							seen[j] = true
							table.insert(queue, j)
						end
					end
				end
			end
		end
	end
	return seen
end

local function cellOf(x: number, z: number): number
	local c = math.clamp(math.floor((x - B.minX) / STEP), 0, W - 1)
	local r = math.clamp(math.floor((z - B.minZ) / STEP), 0, H - 1)
	return r * W + c + 1
end
-- célula livre mais perto do ponto (o ponto forte pode cair em cima de uma casa)
local function freeNear(blk: { boolean }, x: number, z: number): number
	local i0 = cellOf(x, z)
	if not blk[i0] then
		return i0
	end
	for rad = 1, 15 do
		for dr = -rad, rad do
			for dc = -rad, rad do
				local j = i0 + dr * W + dc
				if j >= 1 and j <= N and not blk[j] then
					return j
				end
			end
		end
	end
	return i0
end
-- algum ponto a até rM do lugar está no conjunto
local function near(set: { boolean }, x: number, z: number, rM: number): boolean
	local k = math.ceil(rM / 2)
	local i0 = cellOf(x, z)
	for dr = -k, k do
		for dc = -k, k do
			local j = i0 + dr * W + dc
			if j >= 1 and j <= N and set[j] then
				return true
			end
		end
	end
	return false
end

local results: { [string]: any } = {}
local function run(v: Veh): any
	local key = v.id .. (if v.rain > 0 then " (chuva)" else "")
	if results[key] then
		return results[key]
	end
	local blk = blockedGrid(v.halfM)
	local hq = MapConfig.HQ.US
	local s = freeNear(blk, hq.x, hq.z)
	local fwd = reach(v, blk, s, false)
	local back = reach(v, blk, s, true)
	local fit, both, stuck, island = 0, 0, 0, 0
	local stuckBy: { [string]: number } = {}
	for i = 1, N do
		if not blk[i] and depth[i] < VehicleDrive.DRIVE[v.id].fordM then
			fit += 1
			if fwd[i] and back[i] then
				both += 1
			elseif fwd[i] then
				stuck += 1 -- entra e não sai
				stuckBy[ground[i]] = (stuckBy[ground[i]] or 0) + 1
			elseif not back[i] then
				island += 1
			end
		end
	end
	local missing = {}
	for _, sp in MapConfig.Strongpoints do
		if not (near(fwd, sp.x, sp.z, 25) and near(back, sp.x, sp.z, 25)) then
			table.insert(missing, sp.name)
		end
	end
	local vc = MapConfig.HQ.VC
	if not (near(fwd, vc.x, vc.z, 25) and near(back, vc.x, vc.z, 25)) then
		table.insert(missing, "QG do VC")
	end
	local res = { fit = fit, both = both, stuck = stuck, island = island, missing = missing }
	local parts = {}
	for g, n in stuckBy do
		table.insert(parts, string.format("%s %d", g, n))
	end
	table.sort(parts)
	print(
		string.format(
			"       %-16s cabe em %d células; vai e volta do QG dos EUA em %d (%.1f%%); entra e não sai: %d (%.2f%%: %s); fora do alcance: %d; objetivos sem ida e volta: %s",
			key,
			fit,
			both,
			100 * both / fit,
			stuck,
			100 * stuck / fit,
			table.concat(parts, ", "),
			island,
			if #missing == 0 then "nenhum" else table.concat(missing, ", ")
		)
	)
	results[key] = res
	return res
end

test("estradas: leito com rampa até 15%, largura do M48 e a principal passa por todos os objetivos", function()
	local maxGrade, nPrincipal = 0, 0
	local pts: { { number } } = {}
	for _, r in Roads.roads do
		local p = r.pts
		if r.kind == "principal" or r.kind == "rua" then
			nPrincipal += 1
		end
		for i = 1, #p - 5, 3 do
			local d = math.sqrt((p[i + 3] - p[i]) ^ 2 + (p[i + 4] - p[i + 1]) ^ 2)
			if d > 1 then
				maxGrade = math.max(maxGrade, math.abs(p[i + 5] - p[i + 2]) / d)
			end
			if r.kind ~= "secundaria" then
				table.insert(pts, { p[i], p[i + 1] })
			end
		end
	end
	print(
		string.format(
			"       %d trechos (%d da principal e da rua), rampa máx. do leito %.1f%%",
			#Roads.roads,
			nPrincipal,
			100 * maxGrade
		)
	)
	assert(maxGrade <= Roads.gradeMax + 0.01, "rampa do leito")
	assert(Roads.width.principal * M >= 3.6 + 2, "a principal tem que caber o M48 (3,6 m) com folga")
	local function dist(x: number, z: number): number
		local best = math.huge
		for _, q in pts do
			best = math.min(best, math.sqrt((q[1] - x) ^ 2 + (q[2] - z) ^ 2) * M)
		end
		return best
	end
	for _, sp in MapConfig.Strongpoints do
		assert(dist(sp.x, sp.z) <= 40, sp.name .. string.format(" a %.0f m da estrada principal", dist(sp.x, sp.z)))
	end
	for f, hq in MapConfig.HQ do
		assert(dist(hq.x, hq.z) <= 40, "QG " .. f .. " longe da estrada principal")
	end
end)

test("estradas no chão gerado: leito sem água, sem construção e sem planta, rampa que o M48 sobe", function()
	local spec = VehicleDrive.DRIVE.m48a3
	local tanDirt = climbTan(spec, "dirt", 1) -- na chuva
	local blk = blockedGrid(0)
	local worst, wet, inHouse, n = 0, 0, 0, 0
	for _, r in Roads.roads do
		local p = r.pts
		local prev: number? = nil
		for i = 1, #p - 5, 3 do
			local x1, z1, x2, z2 = p[i], p[i + 1], p[i + 3], p[i + 4]
			local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
			local k = math.max(1, math.floor(len / STEP))
			for s = 0, k - 1 do
				local x, z = x1 + (x2 - x1) * s / k, z1 + (z2 - z1) * s / k
				local h, wl = ArtPlan.column(ctx, x, z)
				n += 1
				if wl > h then
					wet += 1
				end
				if blk[cellOf(x, z)] and r.kind ~= "rua" then
					inHouse += 1
				end
				if prev then
					worst = math.max(worst, math.abs(h - prev) * M / (len / k * M))
				end
				prev = h
			end
		end
	end
	print(
		string.format(
			"       %d pontos do eixo: rampa máx. %.1f%% (o M48 sobe %.0f%% em terra na chuva), %d com água, %d em construção",
			n,
			100 * worst,
			100 * tanDirt,
			wet,
			inHouse
		)
	)
	assert(worst < tanDirt, "rampa da estrada acima do que o M48 sobe")
	assert(wet == 0, "água no leito")
	assert(inHouse == 0, "estrada dentro de construção")
end)

test("M48A3: do QG dos EUA a todos os objetivos e de volta; quase nada onde entra e não sai", function()
	local r = run({ id = "m48a3", halfM = 1.8, rain = 0 })
	assert(#r.missing == 0, "sem ida e volta: " .. table.concat(r.missing, ", "))
	assert(r.stuck <= r.fit * 0.005, string.format("%d células onde o M48 entra e não sai", r.stuck))
	local rr = run({ id = "m48a3", halfM = 1.8, rain = 1 })
	assert(#rr.missing == 0, "na chuva, sem ida e volta: " .. table.concat(rr.missing, ", "))
end)

test("rodas e anfíbio: jipe M151, caminhão M35 e LVTP-5 chegam a todos os objetivos", function()
	for _, v in
		{
			{ id = "m151", halfM = 0.9, rain = 0 },
			{ id = "m35", halfM = 1.2, rain = 0 },
			{ id = "lvtp5", halfM = 1.8, rain = 0 },
			{ id = "ontos", halfM = 1.3, rain = 0 },
		}
	do
		local r = run(v)
		assert(#r.missing == 0, v.id .. " sem ida e volta: " .. table.concat(r.missing, ", "))
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
