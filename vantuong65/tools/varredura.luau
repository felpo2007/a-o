--!strict
-- Varredura do mapa (pedido do dono, 2026-11-12: "plantas onde não deveriam estar, coisas flutuando,
-- bases de objetos"). Monta o plano da arte (ArtPlan) com os dados do mapa, como o AssetLoader faz no
-- servidor, e confere cada item contra o chão que o TerrainBuilder gera (ArtPlan.column), com regras
-- próprias (não as do plano):
--   planta na lâmina, no dique, na estrada, no beco, dentro de construção, no leito do riacho ou na
--   clareira de nascimento; coisa flutuando (base mais de 10 cm acima do chão mais baixo sob ela) ou
--   enterrada (chão mais de 35 cm acima da base); base à mostra (patamar abaixo da pegada); casa
--   dentro de casa, objeto dentro de objeto, sebe atravessando casa; e os diques (altura da crista
--   sobre o fundo mais baixo ao lado).
-- Uso (a partir de vantuong65/): lune run tools/varredura.luau
-- Todos os modelos contam como publicados, menos as casas únicas da vila (vila_casa_XX, ID 0 hoje).
local R = require :: any
local WorldData = R("../src/ServerStorage/VT65Build/WorldData")
local Grid = R("../src/ServerStorage/VT65Build/Data/Grid")
local Features = R("../src/ServerStorage/VT65Build/Data/Features")
local Village = R("../src/ServerStorage/VT65Build/Data/Village")
local Roads = R("../src/ServerStorage/VT65Build/Data/Roads")
local MapConfig = R("../src/ReplicatedStorage/Shared/MapConfig")
local Site = R("../src/ServerStorage/VT65Build/Site")
local TerrainBuilder = R("../src/ServerStorage/VT65Build/TerrainBuilder")
local ArtPlan = R("../src/ServerScriptService/Modules/ArtPlan")
local ArtBudget = R("../src/ServerScriptService/Modules/ArtBudget")
local AssetIds = R("../src/ReplicatedStorage/Shared/AssetIds")
local Vegetation = R("../src/ServerScriptService/Modules/Vegetation")

local M = 0.28
local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, R("../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)
local t0 = os.clock()
local ctx = ArtPlan.load(world, { features = Features, village = Village, roads = Roads, mapConfig = MapConfig })
local function has(key: string): boolean
	local id = AssetIds.Models[key]
	return type(id) == "number" and id ~= 0
end
local structures = ArtPlan.structures(ctx, has)
local plants = ArtPlan.plants(ctx, structures, {}, function(k: string): boolean
	return string.sub(k, 1, 9) ~= "vila_casa" or has(k)
end)
print(string.format("plano: %d construções e objetos, %d plantas (%.1f s)", #structures, #plants, os.clock() - t0))

local function ground(x: number, z: number): number
	local h = ArtPlan.column(ctx, x, z)
	return h
end
local function segDist(px: number, pz: number, x1: number, z1: number, x2: number, z2: number): number
	local dx, dz = x2 - x1, z2 - z1
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((px - x1) * dx + (pz - z1) * dz) / l2, 0, 1) else 0
	local qx, qz = x1 + t * dx - px, z1 + t * dz - pz
	return math.sqrt(qx * qx + qz * qz)
end
local function inRect(px: number, pz: number, s: any, m: number): boolean
	local dx, dz = px - s.x, pz - s.z
	local ca, sa = math.cos(s.yaw), math.sin(s.yaw)
	return math.abs(dx * ca - dz * sa) <= s.hx + m and math.abs(dx * sa + dz * ca) <= s.hz + m
end

local count = {
	planta_lamina = 0,
	planta_dique = 0,
	planta_estrada = 0,
	planta_beco = 0,
	planta_construcao = 0,
	planta_riacho = 0,
	planta_clareira = 0,
	flutuando = 0,
	enterrado = 0,
	base_aparecendo = 0,
	casa_em_casa = 0,
	sebe_em_casa = 0,
	objeto_em_objeto = 0,
}
local B = MapConfig.Bounds
local spawnInput = { exclude = ctx.spawnCircles, corridors = ctx.spawnLanes }
for _, it in plants do
	local inside = it.x >= B.minX and it.x <= B.maxX and it.z >= B.minZ and it.z <= B.maxZ
	if inside and it.key ~= "rice_patch" then
		local r = (ArtBudget.BASE_R[it.key] or 1) * it.scale * 0.5
		if TerrainBuilder.paddyTop(ctx.paddies, it.x, it.z, r) then
			count.planta_lamina += 1
		end
		for _, dk in ctx.dikes do
			if
				segDist(it.x, it.z, dk[1], dk[2], dk[3], dk[4])
				< (Site.DIKE_CREST_M + Site.DIKE_SIDE_M * 0.5) / M + r
			then
				count.planta_dique += 1
				break
			end
		end
		local kind, d, _, hw = Site.road(ctx.site, it.x, it.z)
		if kind and d < hw + r then
			count.planta_estrada += 1
		end
		if Site.lane(ctx.site, it.x, it.z) then
			count.planta_beco += 1
		end
		for _, s in structures do
			if (s.padded or s.group == "house") and inRect(it.x, it.z, s, r) then
				count.planta_construcao += 1
				break
			end
		end
		if
			world:classAt(it.x, it.z) == 5
			or world:classAt(it.x + r, it.z) == 5
			or world:classAt(it.x - r, it.z) == 5
			or world:classAt(it.x, it.z + r) == 5
			or world:classAt(it.x, it.z - r) == 5
		then
			count.planta_riacho += 1
		end
		if Vegetation.blocked(spawnInput :: any, it.x, it.z) then
			count.planta_clareira += 1
		end
		local rr = (ArtBudget.BASE_R[it.key] or 1) * it.scale * 0.35
		local lo = math.min(
			ground(it.x, it.z),
			ground(it.x + rr, it.z),
			ground(it.x - rr, it.z),
			ground(it.x, it.z + rr),
			ground(it.x, it.z - rr)
		)
		if it.base - lo > 0.1 / M then
			count.flutuando += 1
			print(string.format("  flutuando %s em (%.0f, %.0f): %.2f m", it.key, it.x, it.z, (it.base - lo) * M))
		end
	end
end
local sunk = { trench_section = true, tunnel_entrance = true, spider_hole = true }
for _, s in structures do
	if s.sink or sunk[s.key] or s.key == "log_bridge" then
		continue
	end
	-- chão sob a pegada (95% dela), 5 x 5 pontos
	local lo, hi = math.huge, -math.huge
	local ca, sa = math.cos(s.yaw), math.sin(s.yaw)
	for i = -2, 2 do
		for j = -2, 2 do
			local lx, lz = i / 2 * s.hx * 0.95, j / 2 * s.hz * 0.95
			local y = ground(s.x + lx * ca + lz * sa, s.z - lx * sa + lz * ca)
			lo, hi = math.min(lo, y), math.max(hi, y)
		end
	end
	if s.base - lo > 0.1 / M then
		if s.padded then
			count.base_aparecendo += 1
		else
			count.flutuando += 1
		end
		print(
			string.format(
				"  %s %s em (%.0f, %.0f): base %.2f m acima do chão mais baixo",
				if s.padded then "base à mostra" else "flutuando",
				s.key,
				s.x,
				s.z,
				(s.base - lo) * M
			)
		)
	end
	if hi - s.base > 0.35 / M then
		count.enterrado += 1
		print(
			string.format(
				"  enterrado %s em (%.0f, %.0f): chão %.2f m acima da base",
				s.key,
				s.x,
				s.z,
				(hi - s.base) * M
			)
		)
	end
end
local HOUSE = { hut_thatch = true, hut_veranda = true, hut_kitchen = true, house_tile = true }
for k = 1, 12 do
	HOUSE[string.format("vila_casa_%02d", k)] = true
end
local solid = {}
for _, s in structures do
	if s.padded or s.group == "house" then
		table.insert(solid, s)
	end
end
for i, a in solid do
	for j = i + 1, #solid do
		local b = solid[j]
		local d2 = (a.x - b.x) ^ 2 + (a.z - b.z) ^ 2
		if d2 < (math.max(a.hx, a.hz) + math.max(b.hx, b.hz)) ^ 2 then
			local hit = inRect(b.x, b.z, a, math.min(b.hx, b.hz) * 0.7)
				or inRect(a.x, a.z, b, math.min(a.hx, a.hz) * 0.7)
			if hit then
				if HOUSE[a.key] and HOUSE[b.key] then
					count.casa_em_casa += 1
				elseif not (a.key == "bamboo_fence" and b.key == "bamboo_fence") then
					count.objeto_em_objeto += 1
					print(string.format("  objeto em objeto: %s x %s em (%.0f, %.0f)", a.key, b.key, a.x, a.z))
				end
			end
		end
	end
end
for _, h in ctx.hedges do
	for _, s in solid do
		if HOUSE[s.key] then
			for k = 0, 12 do
				local t = k / 12
				if inRect(h.x1 + (h.x2 - h.x1) * t, h.z1 + (h.z2 - h.z1) * t, s, 0) then
					count.sebe_em_casa += 1
					break
				end
			end
		end
	end
end
print(string.format("itens: %d plantas, %d objetos", #plants, #structures))
for _, k in
	{
		"planta_lamina",
		"planta_dique",
		"planta_estrada",
		"planta_beco",
		"planta_construcao",
		"planta_riacho",
		"planta_clareira",
		"flutuando",
		"enterrado",
		"base_aparecendo",
		"casa_em_casa",
		"sebe_em_casa",
		"objeto_em_objeto",
	}
do
	print(string.format("%-20s %d", k, (count :: any)[k]))
end

-- ===== diques: a lombada (chão com o dique menos o chão sem ele) e o degrau entre os dois lados =====
local nDike, nPts, over, maxBump, maxStep, maxGrade = 0, 0, 0, 0, 0, 0
local step = 1 / M
local saved = ctx.site.dikes
local function bare(x: number, z: number): number
	ctx.site.dikes = {}
	local h = ground(x, z)
	ctx.site.dikes = saved
	return h
end
local reach = (Site.DIKE_CREST_M + Site.DIKE_SIDE_M + 0.3) * step
for _, dk in ctx.dikes do
	local len = math.sqrt((dk[3] - dk[1]) ^ 2 + (dk[4] - dk[2]) ^ 2)
	if len < 1 then
		continue
	end
	nDike += 1
	local ux, uz = (dk[3] - dk[1]) / len, (dk[4] - dk[2]) / len
	local nx, nz = -uz, ux
	local n = math.max(1, math.floor(len / 8))
	for k = 1, n do
		local t = (k - 0.5) / n
		local x, z = dk[1] + (dk[3] - dk[1]) * t, dk[2] + (dk[4] - dk[2]) * t
		local crest = ground(x, z)
		local bump = (crest - bare(x, z)) * M
		nPts += 1
		maxBump = math.max(maxBump, bump)
		-- a crista sobre o chão dos dois lados (fora da lombada)
		local a = ground(x + nx * reach, z + nz * reach)
		local b = ground(x - nx * reach, z - nz * reach)
		if (crest - math.min(a, b)) * M > 0.65 then
			over += 1 -- mais que o degrau que a lagarta sobe (VehicleDrive.CLIMB_STEP_M)
		end
		maxStep = math.max(maxStep, math.abs(a - b) * M)
		for _, o in { 1, -1 } do
			local y1 = ground(x + nx * o * 1.12 * step, z + nz * o * 1.12 * step)
			maxGrade = math.max(maxGrade, math.abs(crest - y1) / (1.12 * step)) -- num voxel (1,12 m)
		end
	end
end
print(
	string.format(
		"diques: %d no mapa (lombada do terreno), %d pontos; lombada até %.2f m; crista a mais de 0,65 m do chão ao lado em %d pontos; degrau entre os lados até %.2f m; rampa máx. num voxel %.0f%%",
		nDike,
		nPts,
		maxBump,
		over,
		maxStep,
		100 * maxGrade
	)
)
