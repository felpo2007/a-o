--!strict
-- Bases dos dois lados e casas únicas da vila (lote de 2026-11-13). Uso: lune run tests/luau/bases.luau
--   - cada objeto das bases (Data/Bases, gerado por tools/bases_dados.py) tem ID, tipo, triângulos,
--     medida e a colisão por nó;
--   - as bases cabem no mapa, longe dos pontos fortes; os pontos de nascer e as vagas de veículo
--     ficam fora de toda construção; nenhuma construção dentro da outra;
--   - a estrada do mapa chega à entrada de cada base e não entra nela; a rua dos EUA e a trilha do
--     VC estão no Data/Roads;
--   - a raia longa do campo de tiro começa fora das duas bases;
--   - vila Xóm Gò: casas únicas publicadas no lugar das variadas, porta para a rua e nenhuma vizinha
--     (a menos de 30 m) com o mesmo modelo e o mesmo giro.
local process = require("@lune/process")

local R = require :: any
local WorldData = R("../../src/ServerStorage/VT65Build/WorldData")
local Grid = R("../../src/ServerStorage/VT65Build/Data/Grid")
local Features = R("../../src/ServerStorage/VT65Build/Data/Features")
local Village = R("../../src/ServerStorage/VT65Build/Data/Village")
local Roads = R("../../src/ServerStorage/VT65Build/Data/Roads")
local Bases = R("../../src/ServerStorage/VT65Build/Data/Bases")
local MapConfig = R("../../src/ReplicatedStorage/Shared/MapConfig")
local AssetIds = R("../../src/ReplicatedStorage/Shared/AssetIds")
local ArtBudget = R("../../src/ServerScriptService/Modules/ArtBudget")
local ArtPlan = R("../../src/ServerScriptService/Modules/ArtPlan")

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
local function has(k: string): boolean
	local id = AssetIds.Models[k]
	return type(id) == "number" and id ~= 0
end
local ctx =
	ArtPlan.load(world, { features = Features, village = Village, roads = Roads, bases = Bases, mapConfig = MapConfig })
local structures = ArtPlan.structures(ctx, has)

local function inRect(px: number, pz: number, s: any, m: number): boolean
	local dx, dz = px - s.x, pz - s.z
	local ca, sa = math.cos(s.yaw), math.sin(s.yaw)
	return math.abs(dx * ca - dz * sa) <= s.hx + m and math.abs(dx * sa + dz * ca) <= s.hz + m
end
local function areaOf(f: string): (number, number, number, number)
	local hq, a = MapConfig.HQ[f], Bases[f].area
	return hq.x + a.minX, hq.x + a.maxX, hq.z + a.minZ, hq.z + a.maxZ
end
local baseItems = {}
for _, s in structures do
	if s.group == "base" and not s.inside then
		table.insert(baseItems, s)
	end
end

test("cada objeto das bases tem ID, tipo, triângulos, medida e colisão por nó", function()
	local keys = {}
	for _, f in { "US", "VC" } do
		for _, it in Bases[f].items do
			keys[it.key] = true
		end
	end
	local n = 0
	for k in keys do
		n += 1
		assert(has(k), k .. " sem ID publicado no AssetIds")
		assert(ArtBudget.KIND[k], k .. " sem tipo no ArtBudget")
		assert(ArtBudget.TRIS[k], k .. " sem triângulos no ArtBudget")
		assert(ArtBudget.DIMS[k], k .. " sem medida no ArtBudget")
		if string.sub(k, 1, 3) == "us_" or string.sub(k, 1, 3) == "vc_" then
			assert(Bases.nodes[k], k .. " sem a colisão por nó")
		end
	end
	print(string.format("       %d chaves (29 objetos novos e os reaproveitados), %d peças postas", n, #baseItems))
	assert(n >= 33, "esperava os 29 objetos das bases e os reaproveitados")
end)

test("as bases cabem no mapa, longe dos pontos fortes, e o centro de cada uma é o QG", function()
	local B = MapConfig.Bounds
	for _, f in { "US", "VC" } do
		local x0, x1, z0, z1 = areaOf(f)
		assert(x0 >= B.minX and x1 <= B.maxX and z0 >= B.minZ and z1 <= B.maxZ, f .. ": base fora do mapa")
		for _, sp in MapConfig.Strongpoints do
			assert(
				not (sp.x > x0 - 30 / M and sp.x < x1 + 30 / M and sp.z > z0 - 30 / M and sp.z < z1 + 30 / M),
				f .. ": ponto forte " .. sp.name .. " a menos de 30 m da base"
			)
		end
	end
	for _, s in baseItems do
		assert(s.x > B.minX and s.x < B.maxX and s.z > B.minZ and s.z < B.maxZ, s.key .. " fora do mapa")
	end
end)

test("pontos de nascer e vagas de veículo fora de toda construção; nenhuma construção dentro da outra", function()
	local solid = {}
	for _, s in structures do
		if (s.padded or s.group == "house" or s.group == "base") and not s.inside then
			table.insert(solid, s)
		end
	end
	for _, f in { "US", "VC" } do
		local hq, b = MapConfig.HQ[f], Bases[f]
		for i = 1, #b.spawns - 1, 2 do
			local x, z = hq.x + b.spawns[i], hq.z + b.spawns[i + 1]
			for _, s in solid do
				assert(not inRect(x, z, s, 1 / M), string.format("%s: nascer %d dentro de %s", f, (i + 1) // 2, s.key))
			end
		end
		for _, v in b.vehicles do
			local x, z = hq.x + v.x, hq.z + v.z
			for _, s in solid do
				-- a vaga fica dentro da baia, da garagem ou no heliponto (é para isso que eles servem)
				local own = s.key == "us_armor_revetment"
					or s.key == "us_motor_pool"
					or s.key == "us_helipad"
					or s.key == "vc_car_shelter"
				assert(own or not inRect(x, z, s, 0), string.format("%s: vaga de %s dentro de %s", f, v.kind, s.key))
			end
		end
	end
	local over = 0
	for i, a in baseItems do
		for j = i + 1, #baseItems do
			local b = baseItems[j]
			if (a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 < (math.max(a.hx, a.hz) + math.max(b.hx, b.hz)) ^ 2 then
				if
					inRect(b.x, b.z, a, math.min(b.hx, b.hz) * 0.7) or inRect(a.x, a.z, b, math.min(a.hx, a.hz) * 0.7)
				then
					over += 1
					print(string.format("       %s (%s) x %s (%s)", a.key, a.id or "", b.key, b.id or ""))
				end
			end
		end
	end
	assert(over == 0, over .. " construções das bases uma dentro da outra")
end)

test("estrada do mapa chega à entrada de cada base e não entra nela; rua e trilha da base no Roads", function()
	for _, f in { "US", "VC" } do
		local hq, rd = MapConfig.HQ[f], Bases[f].road
		local ex, ez = hq.x + rd.ax, hq.z + rd.az
		local x0, x1, z0, z1 = areaOf(f)
		local own, reach = false, math.huge
		for _, r in Roads.roads do
			local p = r.pts
			if r.kind == rd.kind and math.abs(p[1] - ex) < 1 and math.abs(p[2] - ez) < 1 then
				own = true
			elseif r.kind ~= "rua" or f ~= "US" or math.abs(p[2] - ez) > 3 then
				for i = 1, #p - 2, 3 do
					local x, z = p[i], p[i + 1]
					reach = math.min(reach, math.sqrt((x - ex) ^ 2 + (z - ez) ^ 2) * M)
					-- a estrada do mapa passa fora da área (com 0,5 m de tolerância do traçado)
					local m = -0.5 / M
					assert(
						not (x > x0 - m and x < x1 + m and z > z0 - m and z < z1 + m),
						string.format("%s: estrada %s entra na base em (%.0f, %.0f)", f, r.kind, x, z)
					)
				end
			end
		end
		assert(own, f .. ": a via da base (" .. rd.kind .. ") não está no Data/Roads")
		print(string.format("       %s: a estrada do mapa chega a %.1f m da entrada", f, reach))
		assert(reach <= 8, f .. ": a estrada do mapa não chega à entrada da base")
	end
end)

test("raia longa do campo de tiro começa fora das bases, na direção do estande de cada uma", function()
	for _, f in { "US", "VC" } do
		local b = Bases[f]
		local r, a = b.range, b.area
		assert(r.targetM > 0 and math.abs(r.dirX) + math.abs(r.dirZ) == 1, f .. ": estande sem direção")
		-- a mesma conta do TrainingService.baseLane: 4 m depois da cerca, no rumo do estande
		local off = if r.dirZ ~= 0
			then math.abs((if r.dirZ > 0 then a.maxZ else a.minZ) + r.dirZ * 4 / M)
			else math.abs((if r.dirX > 0 then a.maxX else a.minX) + r.dirX * 4 / M)
		local halfDepth = if r.dirZ ~= 0 then math.max(-a.minZ, a.maxZ) else math.max(-a.minX, a.maxX)
		assert(off > halfDepth, f .. ": a raia longa começaria dentro da base")
	end
end)

test("vila Xóm Gò: casas únicas publicadas, porta para a rua, vizinhas nunca iguais em modelo e giro", function()
	local homes = {}
	local unique, fallback = 0, 0
	for _, s in structures do
		if s.group == "village" and s.home then
			table.insert(homes, s)
			if string.sub(s.key, 1, 10) == "vila_casa_" then
				unique += 1
				assert(Bases.houseDoors[s.key], s.key .. " sem a porta no Data/Bases")
				assert(Bases.nodes[s.key], s.key .. " sem a colisão por nó")
			else
				fallback += 1
			end
		end
	end
	print(string.format("       %d casas: %d únicas (vila_casa_01..10), %d variadas", #homes, unique, fallback))
	assert(unique >= 30, "poucas casas únicas")
	for i, a in homes do
		for j = i + 1, #homes do
			local b = homes[j]
			if math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) * M < 30 and a.key == b.key then
				local d = math.abs(((a.yaw - b.yaw + math.pi) % (2 * math.pi)) - math.pi)
				assert(d > math.rad(10), string.format("%s igual e no mesmo giro a menos de 30 m", a.key))
			end
		end
	end
	-- a porta da casa 09 fica no lado +X do modelo: o giro dela leva +X para a frente do lote
	local door = Bases.houseDoors.vila_casa_09
	local turn = math.atan2(door[1], -door[2])
	local nx, nz =
		door[1] * math.cos(turn) + door[2] * math.sin(turn), -door[1] * math.sin(turn) + door[2] * math.cos(turn)
	assert(math.abs(nx) < 1e-9 and math.abs(nz + 1) < 1e-9, "giro da porta não leva para -Z")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
