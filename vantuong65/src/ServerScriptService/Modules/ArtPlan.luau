--!strict
-- Plano da arte do mapa (módulo puro: Roblox e Lune). Decide ONDE vai cada casa, construção, objeto e
-- planta, em que altura e com que giro; o AssetLoader só clona e põe. O mesmo plano serve ao
-- TerrainBuilder (o patamar de cada construção), à varredura do mapa (tools/varredura.luau), à carta
-- e aos testes.
-- Pedido do dono (2026-11-12): "plantas onde não deveriam estar, coisas flutuando, bases de objetos".
--   - Planta nenhuma na lâmina do arrozal, em cima de dique, na estrada, no beco, no patamar de
--     construção, no leito do riacho nem na clareira de nascimento (ArtPlan.plantProblem).
--   - Construção assentada pelo ponto mais baixo do chão sob a pegada, num patamar aberto no terreno
--     (Site.addPad): sem pedestal de terra à mostra e sem canto no ar.
--   - Planta com o pé 10 cm abaixo do ponto mais baixo do chão sob ele.
--   - Vila grande do centro (Data/Village): casas únicas (vila_casa_01..12; com o ID em 0, as casas
--     de hoje com giro, escala, tom e anexos diferentes), pagode, casa comunal, mercado, poço,
--     quintais e o bambuzal em volta.
local ArtPlan = {}

local IS_ROBLOX = (script :: any) ~= nil
local function mod(roblox: () -> any, lune: string): any
	local req: any = require -- caminho dinâmico (Roblox: instância; Lune: texto)
	if IS_ROBLOX then
		return req(roblox())
	end
	return req(lune)
end
local ArtBudget = mod(function()
	return (script :: any).Parent.ArtBudget
end, "./ArtBudget")
local Vegetation = mod(function()
	return (script :: any).Parent.Vegetation
end, "./Vegetation")
local Rng = mod(function()
	return (game :: any):GetService("ReplicatedStorage").Shared.Rng
end, "../../ReplicatedStorage/Shared/Rng")
local Tunnels = mod(function()
	return (game :: any):GetService("ReplicatedStorage").Shared.Tunnels
end, "../../ReplicatedStorage/Shared/Tunnels")
local Front = mod(function()
	return (game :: any):GetService("ReplicatedStorage").Shared.Front
end, "../../ReplicatedStorage/Shared/Front")
local SpawnRules = mod(function()
	return (game :: any):GetService("ReplicatedStorage").Shared.SpawnRules
end, "../../ReplicatedStorage/Shared/SpawnRules")
local Geometry = mod(function()
	return (game :: any):GetService("ReplicatedStorage").Shared.Geometry
end, "../../ReplicatedStorage/Shared/Geometry")
local Site = mod(function()
	return (game :: any):GetService("ServerStorage").VT65Build.Site
end, "../../ServerStorage/VT65Build/Site")
local TerrainBuilder = mod(function()
	return (game :: any):GetService("ServerStorage").VT65Build.TerrainBuilder
end, "../../ServerStorage/VT65Build/TerrainBuilder")
local Landscape = mod(function()
	return (game :: any):GetService("ServerStorage").VT65Build.Landscape
end, "../../ServerStorage/VT65Build/Landscape")
local FeatureBuilder = mod(function()
	return (game :: any):GetService("ServerStorage").VT65Build.FeatureBuilder
end, "../../ServerStorage/VT65Build/FeatureBuilder")

local M = 0.28
ArtPlan.VERSION = 3 -- o terreno gerado guarda isto (atributo SitePlan): base pelo plano só se bater
-- D-115 (pedido do dono: "aumente as cabanas de todo jogo"; "cabanas muito pequenas no mapa"): casas
-- da carta e celeiros 30% maiores (o soldado tem 2,0 m, D-98; o beiral ficava na altura da cabeça).
-- As da vila grande seguem Data/Village.houseScale (tools/vila_estradas.ESCALA_CASA, o mesmo 1,3).
ArtPlan.HOUSE_SCALE = 1.3
ArtPlan.PLANT_SINK_M = 0.10 -- pé da planta abaixo do ponto mais baixo do chão sob ele
ArtPlan.DIKE_HALF_M = 0.9 -- meia largura da lombada do dique (Site: crista 0,3 m e metade da rampa)
ArtPlan.ROAD_CLEAR_M = 1.0 -- planta a pelo menos isto da beira da estrada
ArtPlan.HOUSE_FALLBACK = {
	"hut_thatch",
	"hut_veranda",
	"house_tile",
	"hut_thatch",
	"house_tile",
	"hut_veranda",
	"hut_thatch",
	"house_tile",
	"hut_veranda",
	"hut_thatch",
	"house_tile",
	"hut_veranda",
}
-- GANCHO DO STUDIO: a frente das casas únicas da vila fica em -Z do modelo depois do giro do
-- importador (D-58). Se no Studio a porta aparecer de costas para a rua, ligue isto (meia volta).
ArtPlan.VILLAGE_FRONT_FLIP = false
-- GANCHO DO STUDIO: o mesmo para as peças das bases (giro do layout = -rumo, frente em -Z): se as
-- barracas e o portão aparecerem de costas para a rua, ligue isto
ArtPlan.BASE_FRONT_FLIP = false
-- tons das casas sem modelo próprio (Color de cada peça, multiplicado pela textura quando há)
ArtPlan.TINTS = {
	{ 1, 1, 1 },
	{ 0.92, 0.86, 0.76 },
	{ 1, 0.95, 0.85 },
	{ 0.85, 0.82, 0.78 },
}

export type Item = {
	key: string, -- modelo (AssetIds.Models) ou "parts:<tipo>" (MapLife monta com peças)
	x: number,
	z: number,
	yaw: number,
	scale: number,
	hx: number, -- meia pegada (studs, na escala)
	hz: number,
	base: number, -- altura da base (studs)
	group: string, -- "house" | "prop" | "village" | "special" | "small" | "plant"
	foliage: boolean,
	shadow: boolean,
	padded: boolean,
	tint: number?,
	village: number?, -- índice da casa da vila (anexos)
	home: boolean?, -- casa de morar (da carta ou da vila): fumaça, animais
	fallback: boolean?, -- casa da vila sem o modelo único (usa o de hoje)
	sink: number?, -- studs abaixo do chão (boca de túnel, trincheira)
	-- peça das bases (Data/Bases): facção, id do layout, nó a manter (placa) e a peça que a contém
	side: string?,
	id: string?,
	node: string?,
	inside: string?,
}

export type Ctx = {
	world: any,
	mapConfig: any,
	features: any,
	village: any?,
	roads: any?,
	bases: any?, -- Data/Bases (as bases dos dois lados)
	landscape: any,
	paddies: any,
	site: any,
	housesXZ: { number },
	dikes: { { number } },
	dikeBuckets: { [number]: { { number } } },
	hedges: { any },
	spawnCircles: { any },
	spawnLanes: { any },
	pending: { any },
	small: { Item }, -- objetos pequenos sem patamar (planta não cai em cima)
}

local BUCKET = 64
local function bkey(bx: number, bz: number): number
	return (bx + 32768) * 65536 + (bz + 32768)
end

-- Dique que fica no mapa (lombada do terreno, Site.dike): encosta num tabuleiro que ficou, no meio
-- ou numa das pontas. Os outros (o arrozal tirado, a mata) somem.
function ArtPlan.dikeKept(paddies: any, x1: number, z1: number, x2: number, z2: number): boolean
	local r = Site.DIKE_PADDY_M / M
	return TerrainBuilder.paddyTop(paddies, (x1 + x2) / 2, (z1 + z2) / 2, r) ~= nil
		or TerrainBuilder.paddyTop(paddies, x1, z1, r) ~= nil
		or TerrainBuilder.paddyTop(paddies, x2, z2, r) ~= nil
end

-- Coluna do terreno para o TerrainBuilder.build: o chão do Site e, na roça seca (Landscape.ROCA),
-- manchas de terra nua (ruído de ~40 m) no meio do capim baixo. D-116: 0,8 (era 0,62): com a terra
-- batida clara (D-115) as manchas tomavam o lugar do capim; agora são poucas e pequenas.
ArtPlan.ROCA_EARTH = 0.8
function ArtPlan.column(ctx: Ctx, x: number, z: number): (number, number, number, string?)
	local h, wl, c, mat = Site.column(ctx.site, x, z)
	if
		mat == nil
		and c == 2
		and Vegetation.noise(x, z, 40 / M, 4242) > ArtPlan.ROCA_EARTH
		and ctx.landscape:kindAt(x, z) == Landscape.ROCA
	then
		mat = "Ground"
	end
	return h, wl, c, mat
end

-- data: { features, village?, roads?, mapConfig }. world: WorldData.
function ArtPlan.load(world: any, data: any): Ctx
	local F, V, MC = data.features, data.village, data.mapConfig
	local housesXZ: { number } = {}
	for i = 1, #F.houses, 4 do
		table.insert(housesXZ, F.houses[i])
		table.insert(housesXZ, F.houses[i + 1])
	end
	if V then
		for _, h in V.houses do
			table.insert(housesXZ, h[1])
			table.insert(housesXZ, h[2])
		end
	end
	local landscape = Landscape.new(world, MC, housesXZ, V, F.waters)
	local function forest(x: number, z: number): boolean
		return landscape:kindAt(x, z) == Landscape.FOREST
	end
	local waters: { number } = {}
	for i = 1, #F.waters, 6 do
		if not forest(F.waters[i], F.waters[i + 1]) then
			for k = 0, 5 do
				table.insert(waters, F.waters[i + k])
			end
		end
	end
	local paddies = TerrainBuilder.paddySet(world, waters)
	local dikes: { { number } } = {}
	local dikeBuckets: { [number]: { { number } } } = {}
	local d = FeatureBuilder.mergeDikes(F.dikes)
	for i = 1, #d, 6 do
		if ArtPlan.dikeKept(paddies, d[i], d[i + 1], d[i + 2], d[i + 3]) then
			local seg = { d[i], d[i + 1], d[i + 2], d[i + 3] }
			table.insert(dikes, seg)
			local m = 2 / M
			for bx = math.floor((math.min(seg[1], seg[3]) - m) / BUCKET), math.floor((math.max(seg[1], seg[3]) + m) / BUCKET) do
				for bz = math.floor((math.min(seg[2], seg[4]) - m) / BUCKET), math.floor((math.max(seg[2], seg[4]) + m) / BUCKET) do
					local k = bkey(bx, bz)
					dikeBuckets[k] = dikeBuckets[k] or {}
					table.insert(dikeBuckets[k], seg)
				end
			end
		end
	end
	local hedges = {}
	local hg = F.hedges
	for i = 1, #hg, 7 do
		if not forest((hg[i] + hg[i + 2]) / 2, (hg[i + 1] + hg[i + 3]) / 2) then
			table.insert(
				hedges,
				{ x1 = hg[i], z1 = hg[i + 1], x2 = hg[i + 2], z2 = hg[i + 3], h = hg[i + 5], t = hg[i + 6] }
			)
		end
	end
	local site = Site.new(world, paddies, TerrainBuilder, data.roads, if V then V.lanes else nil)
	Site.setDikes(site, dikes)
	local spots = Front.spawnSpots(MC, M, function(x: number, z: number): number?
		return Geometry.sectorAt(MC.Sectors, x, z)
	end, SpawnRules.rallyPosition, Front.C.rallyInsetM)
	local circles, lanes = Vegetation.spawnClearings(spots)
	-- pontos de nascer das bases (Data/Bases, SpawnService): 3 m sem planta em volta de cada um
	if data.bases then
		for fac, hq in MC.HQ do
			local base = data.bases[fac]
			local s = base and base.spawns or {}
			for i = 1, #s - 1, 2 do
				table.insert(circles, { x = hq.x + s[i], z = hq.z + s[i + 1], r = 3 / M })
			end
		end
	end
	return {
		world = world,
		mapConfig = MC,
		features = F,
		village = V,
		roads = data.roads,
		bases = data.bases,
		landscape = landscape,
		paddies = paddies,
		site = site,
		housesXZ = housesXZ,
		dikes = dikes,
		dikeBuckets = dikeBuckets,
		hedges = hedges,
		spawnCircles = circles,
		spawnLanes = lanes,
		pending = {},
		small = {},
	}
end

-- símbolo de cemitério da carta de 1965 (grade ING-A, m), a sudoeste de Nam Yên (4)
ArtPlan.CEMETERY_1965 = { 269435, 1692547 }
function ArtPlan.cemetery(MC: any): (number, number)
	for _, sp in MC.Strongpoints do
		if sp.name == "Cemitério" then
			return sp.x, sp.z
		end
	end
	local o = MC.GridOrigin1965
	return (ArtPlan.CEMETERY_1965[1] - o.e) / M, (o.n - ArtPlan.CEMETERY_1965[2]) / M
end

local function rot(x: number, z: number, yaw: number, lx: number, lz: number): (number, number)
	-- CFrame.Angles(0, yaw, 0): X local -> (cos, 0, -sin); Z local -> (sin, 0, cos)
	local ca, sa = math.cos(yaw), math.sin(yaw)
	return x + lx * ca + lz * sa, z - lx * sa + lz * ca
end
ArtPlan.rot = rot

-- peças montadas pelo MapLife (studs X, Y, Z na escala 1)
ArtPlan.PARTS_DIMS = {
	["parts:horta"] = { 3 / M, 0.5 / M, 2 / M },
} :: { [string]: { number } }

local function half(key: string, scale: number): (number, number)
	local d = ArtBudget.DIMS[key] or ArtPlan.PARTS_DIMS[key]
	if d then
		return d[1] * scale / 2, d[3] * scale / 2
	end
	return 1, 1
end

-- chão mais baixo e mais alto sob uma pegada (studs)
function ArtPlan.footprint(ctx: Ctx, x: number, z: number, yaw: number, hx: number, hz: number): (number, number)
	local lo, hi = math.huge, -math.huge
	for i = -2, 2 do
		for j = -2, 2 do
			local px, pz = rot(x, z, yaw, i / 2 * hx, j / 2 * hz)
			local h = Site.column(ctx.site, px, pz)
			lo, hi = math.min(lo, h), math.max(hi, h)
		end
	end
	return lo, hi
end

-- ===== construções =====
-- has(key): o modelo está publicado (AssetIds.Models diferente de 0). Põe o patamar de cada
-- construção no Site (o TerrainBuilder abre no terreno) e devolve a lista.
function ArtPlan.structures(ctx: Ctx, has: (string) -> boolean): { Item }
	local out: { Item } = {}
	local MC = ctx.mapConfig
	local F = ctx.features
	local function padded(
		key: string,
		x: number,
		z: number,
		yaw: number,
		scale: number,
		group: string,
		extra: any?
	): Item
		local hx, hz = half(key, scale)
		-- padGrow: o patamar passa da pegada na frente (-Z): a varanda fica no mesmo chão da casa
		local grow = if extra and extra.padGrow then extra.padGrow else 0
		local px, pz = rot(x, z, yaw, 0, -grow / 2)
		local pad =
			Site.addPad(ctx.site, px, pz, yaw, hx, hz + grow / 2, extra and extra.ground, extra and extra.padLevel)
		local it: Item = {
			key = key,
			x = x,
			z = z,
			yaw = yaw,
			scale = scale,
			hx = hx,
			hz = hz,
			base = pad.level,
			group = group,
			foliage = false,
			shadow = true,
			padded = true,
		}
		if extra then
			for k, v in extra do
				(it :: any)[k] = v
			end
		end
		table.insert(out, it)
		return it
	end
	-- pequeno, sem patamar: assentado pelo ponto mais baixo do chão sob ele
	local function seated(
		key: string,
		x: number,
		z: number,
		yaw: number,
		scale: number,
		group: string,
		extra: any?
	): Item
		local hx, hz = half(key, scale)
		local lo = ArtPlan.footprint(ctx, x, z, yaw, hx, hz)
		local it: Item = {
			key = key,
			x = x,
			z = z,
			yaw = yaw,
			scale = scale,
			hx = hx,
			hz = hz,
			base = lo,
			group = group,
			foliage = false,
			shadow = true,
			padded = false,
		}
		if extra then
			for k, v in extra do
				(it :: any)[k] = v
			end
		end
		table.insert(out, it)
		table.insert(ctx.small, it)
		return it
	end
	-- no chão do centro (boca de túnel, trincheira, toca: o buraco já está no terreno)
	local function sunk(key: string, x: number, z: number, yaw: number, sinkM: number)
		local hx, hz = half(key, 1)
		local it: Item = {
			key = key,
			x = x,
			z = z,
			yaw = yaw,
			scale = 1,
			hx = hx,
			hz = hz,
			base = Site.column(ctx.site, x, z) - sinkM / M,
			group = "prop",
			foliage = false,
			shadow = true,
			padded = false,
			sink = sinkM / M,
		}
		table.insert(out, it)
		table.insert(ctx.small, it)
	end

	-- casas da carta: variante sorteada, quintal (coqueiro, bananeira, celeiro, cerca)
	local rng = Rng.new(19650818)
	local variants = ArtBudget.HOUSE_VARIANTS
	local HS = ArtPlan.HOUSE_SCALE
	for i = 1, #F.houses, 4 do
		local x, z, yaw = F.houses[i], F.houses[i + 1], F.houses[i + 3]
		local key = variants[1 + math.floor(rng:next() * #variants)]
		local hx, hz = half(key, HS)
		padded(key, x, z, yaw, HS, "house", { home = true })
		local diag = math.sqrt(hx * hx + hz * hz)
		if rng:next() < 0.35 then
			local a = rng:range(0, 2 * math.pi)
			local r = diag + rng:range(2, 4) / M
			table.insert(
				ctx.pending,
				{ key = "coconut_palm", x = x + math.cos(a) * r, z = z + math.sin(a) * r, yaw = a, scale = 1 }
			)
		end
		if rng:next() < 0.3 then
			local a = rng:range(0, 2 * math.pi)
			local r = diag + rng:range(1.5, 3) / M
			table.insert(
				ctx.pending,
				{ key = "banana", x = x + math.cos(a) * r, z = z + math.sin(a) * r, yaw = a, scale = 1 }
			)
		end
		if rng:next() < 0.15 then
			local gx, gz = rot(x, z, yaw, 0, hz + 3 * HS / M)
			padded("granary", gx, gz, yaw, HS, "prop")
		end
		if rng:next() < 0.3 then
			for k = -1, 1 do
				local fx, fz = rot(x, z, yaw, k * 3 * HS / M, -(hz + 2.2 / M))
				padded("bamboo_fence", fx, fz, yaw, 1, "prop")
			end
		end
	end
	-- túneis e trincheira sul de An Cường (2)
	local cx, cz = 0, 0
	for _, l in MC.Locations do
		if l.name == "An Cường (2)" then
			cx, cz = l.x, l.z
		end
	end
	for id, n in Tunnels.nodes do
		if n.entrance then
			local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
			sunk("tunnel_entrance", x, z, rng:range(0, 6.28), 0.3)
			if id == "E1" or id == "E2" or id == "E4" then
				padded("vc_bunker", x + 9 / M, z + 4 / M, rng:range(0, 6.28), 1, "prop")
			end
		end
	end
	for i = 1, #Tunnels.trench - 1 do
		local a, b = Tunnels.trench[i], Tunnels.trench[i + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local yaw = math.atan2(-(b[2] - a[2]), b[1] - a[1])
		for k = 0, math.floor(len / 4) - 1 do
			local t = (k + 0.5) * 4 / len
			local x, z = Tunnels.toWorld(cx, cz, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
			sunk("trench_section", x, z, yaw + math.pi / 2, Tunnels.TRENCH_D_M)
		end
	end
	-- QGs (2026-11-13): as bases do Blender (Data/Bases, layouts relativos ao QG): base dos EUA em
	-- Chu Lai (barracas, posto de comando, refeitório, garagem, baias, helipontos, torres, bunkers,
	-- portão, concertina e o estande de 25 m) e o acampamento do VC (abrigos, cozinha Hoàng Cầm,
	-- redes, armeiros, abrigo do carro, estande de 23 m e estacas punji). Barraca, bunker, garagem e
	-- baia com patamar no terreno; o resto assenta no chão mais baixo da pegada; caixote e saco de
	-- arroz que ficam dentro de outra peça vão no chão dela.
	local bases = ctx.bases
	if bases then
		for _, fac in { "US", "VC" } do
			local base, hq = bases[fac], MC.HQ[fac]
			if base and hq then
				local byId: { [string]: Item } = {}
				local flip = if ArtPlan.BASE_FRONT_FLIP then math.pi else 0
				for _, b in base.items do
					if b.inside == "" then
						local extra = { side = fac, id = b.id, node = if b.node ~= "" then b.node else nil }
						local x, z = hq.x + b.x, hq.z + b.z
						byId[b.id] = if b.padded
							then padded(b.key, x, z, b.yaw + flip, b.scale or 1, "base", extra) -- v41: barracas 1,5x
							else seated(b.key, x, z, b.yaw + flip, b.scale or 1, "base", extra)
					end
				end
				for _, b in base.items do
					local host: Item? = if b.inside ~= "" then byId[b.inside] else nil
					if host then
						local hx, hz = half(b.key, 1)
						table.insert(out, {
							key = b.key,
							x = hq.x + b.x,
							z = hq.z + b.z,
							yaw = b.yaw + flip,
							scale = 1,
							hx = hx,
							hz = hz,
							base = host.base,
							group = "base",
							foliage = false,
							shadow = true,
							padded = false,
							side = fac,
							id = b.id,
							inside = b.inside,
						})
					end
				end
			end
		end
	else
		-- sem os dados das bases: sacos de areia (EUA); cerca, celeiros e bunker (VC)
		local us, vc = MC.HQ.US, MC.HQ.VC
		for i = 0, 11 do
			if i % 3 ~= 0 then
				local a = i * math.pi / 6
				padded(
					"sandbags",
					us.x + math.cos(a) * 14 / M,
					us.z + math.sin(a) * 14 / M,
					-a + math.pi / 2,
					1,
					"prop"
				)
			end
		end
		for i = 0, 15 do
			if i % 4 ~= 0 then
				local a = i * math.pi / 8
				padded(
					"bamboo_fence",
					vc.x + math.cos(a) * 18 / M,
					vc.z + math.sin(a) * 18 / M,
					-a + math.pi / 2,
					1,
					"prop"
				)
			end
		end
		padded("granary", vc.x - 10 / M, vc.z + 8 / M, 0.4, 1, "prop")
		padded("granary", vc.x - 12 / M, vc.z - 7 / M, 2.1, 1, "prop")
		padded("vc_bunker", vc.x + 11 / M, vc.z - 4 / M, -math.pi / 2, 1, "prop")
	end
	-- tocas de atirador em volta dos pontos fortes do VC e neutros (fora de casa, estrada e lâmina)
	for _, sp in MC.Strongpoints do
		if sp.sector <= 3 then
			for _ = 1, 3 do
				local a, r = rng:range(0, 2 * math.pi), rng:range(25, 45) / M
				local yaw = rng:range(0, 6.28)
				local x, z = sp.x + math.cos(a) * r, sp.z + math.sin(a) * r
				if not ArtPlan.groundProblem(ctx, x, z, 1.5 / M) then
					sunk("spider_hole", x, z, yaw, 0)
				end
			end
		end
	end
	-- altar e poço no centro de An Cường (2); túmulos no cemitério da carta (deixou de ser ponto forte
	-- em 2026-11-12, quando os objetivos foram para o centro; os túmulos ficam no lugar da carta)
	padded("shrine", cx + 25, cz + 10, 0, 1, "prop")
	padded("well", cx - 18, cz + 22, 0, 1, "prop")
	-- D-114: no mapa de 500 m o cemitério da carta fica fora da área (e do terreno): sem túmulos
	local cemX, cemZ = ArtPlan.cemetery(MC)
	local CB = MC.Bounds
	if cemX > CB.minX and cemX < CB.maxX and cemZ > CB.minZ and cemZ < CB.maxZ then
		for k = 1, 6 do
			local a = k * 1.05
			padded("grave_mound", cemX + math.cos(a) * 25, cemZ + math.sin(a) * 25, a, 1, "prop")
		end
	end
	-- ponte de toras no riacho, atravessada no leito, apoiada nas duas margens
	for _, l in MC.Locations do
		if string.find(l.name, "Riacho", 1, true) then
			local bx, bz, yaw = ArtPlan.bridgeSpot(ctx.world, l.x, l.z, 60 / M)
			if bx and bz and yaw then
				local hx = half("log_bridge", 1)
				local ax, az = rot(bx, bz, yaw, hx * 0.8, 0)
				local ex, ez = rot(bx, bz, yaw, -hx * 0.8, 0)
				local base = math.min((Site.column(ctx.site, ax, az)), (Site.column(ctx.site, ex, ez)))
				local hx2, hz2 = half("log_bridge", 1)
				local it: Item = {
					key = "log_bridge",
					x = bx,
					z = bz,
					yaw = yaw,
					scale = 1,
					hx = hx2,
					hz = hz2,
					base = base,
					group = "prop",
					foliage = false,
					shadow = true,
					padded = false,
				}
				table.insert(out, it)
			end
		end
	end
	-- ===== vila grande do centro =====
	local V = ctx.village
	if V then
		local vyaw = V.yaw
		-- D-115: casas, lotes e anexos na escala da vila (Village.houseScale; 1 nos dados antigos)
		local K = V.houseScale or 1
		-- praça do mercado: patamar de terra batida
		Site.addPad(ctx.site, V.x, V.z, vyaw, V.plazaHalf, V.plazaHalf * 0.6, true)
		for i, h in V.houses do
			local x, z, yaw, variant, tint, scale, attach = h[1], h[2], h[3], h[4], h[5], h[6], h[7]
			local unique = ArtBudget.VILLAGE_HOUSES[variant]
			local key = if unique and has(unique) then unique else ArtPlan.HOUSE_FALLBACK[variant]
			local s = if key == unique then K else scale * K
			local it: Item
			-- com varanda, o patamar da casa cresce 1,25 m (a varanda fica no chão da casa). A casa
			-- única (2026-11-13) tem a varanda e os anexos dela no modelo: sem a varanda de peças.
			local isUnique = key == unique
			if isUnique then
				attach = bit32.band(attach, bit32.bnot(1))
			end
			local grow = if bit32.btest(attach, 1) then 1.25 * K / M else 0
			if isUnique then
				-- modelo único (pegada de projeto: até houseMax de lado, pivô no meio da caixa e no
				-- chão). O patamar é o quadrado inteiro: o piso de terra batida da casa fica 0,15 m acima
				-- dele (degrau de 0,54 stud na porta). A porta principal (Data/Bases.houseDoors) vira
				-- para a rua: o giro da casa soma o da porta no modelo.
				local hm = V.houseMax / 2
				local pad = Site.addPad(ctx.site, x, z, yaw, hm, hm)
				local door = ctx.bases and ctx.bases.houseDoors and ctx.bases.houseDoors[key]
				local turn = if door then math.atan2(door[1], -door[2]) else 0
				it = {
					key = key,
					x = x,
					z = z,
					yaw = yaw + turn + (if ArtPlan.VILLAGE_FRONT_FLIP then math.pi else 0),
					scale = s,
					hx = hm,
					hz = hm,
					base = pad.level,
					group = "village",
					foliage = false,
					shadow = true,
					padded = true,
					village = i,
					home = true,
				}
				table.insert(out, it)
			else
				it = padded(
					key,
					x,
					z,
					yaw,
					s,
					"village",
					{ village = i, tint = tint, fallback = true, home = true, padGrow = grow }
				)
			end
			local hx, hz = it.hx, it.hz
			local function on(bit: number): boolean
				return bit32.btest(attach, bit)
			end
			-- anexos no quadro da casa (+Z para longe da rua; frente = -Z). Lote de 12 x 14 m com a casa
			-- (até 8,5 m) a 1,5 m da frente: o meio do quintal do fundo fica a 6,25 m do centro da casa e
			-- a frente do lote a 5,75 m (tools/vila_estradas.py). D-115: tudo vezes K.
			local back = 6.25 * K / M
			local front = -5.5 * K / M
			local side = 3.5 * K / M
			if on(1) then -- varanda de palha na frente
				local px, pz = rot(x, z, yaw, 0, -(hz + 0.6 * K / M))
				table.insert(out, {
					key = "parts:varanda",
					x = px,
					z = pz,
					yaw = yaw,
					scale = K,
					hx = hx,
					hz = 0.6 * K / M,
					base = it.base,
					group = "village",
					foliage = false,
					shadow = true,
					padded = false,
					village = i,
				})
			end
			if on(2) then -- cozinha no fundo, à esquerda
				local kx, kz = rot(x, z, yaw, -side, back)
				padded("hut_kitchen", kx, kz, yaw, 0.85 * K, "village", { village = i, padLevel = it.base })
			end
			if on(4) then -- celeiro no fundo, à direita
				local gx, gz = rot(x, z, yaw, side, back)
				padded("granary", gx, gz, yaw, 0.85 * K, "village", { village = i, padLevel = it.base })
			end
			-- o que fica no quintal ganha um patamarzinho no nível da casa (o lote é um terraço só: a vila
			-- fica na encosta do morrote; assentado pelo ponto mais baixo, o varal e a cerca entravam até
			-- 0,9 m no chão do lado de cima, e com o nível próprio o patamar dele e o da casa se cruzavam)
			if on(8) and not on(2) then -- horta no fundo, à esquerda (onde não há cozinha)
				local gx, gz = rot(x, z, yaw, -side, back)
				padded("parts:horta", gx, gz, yaw, K, "village", { village = i, padLevel = it.base })
			end
			if on(16) then -- cerca na frente do lote, com a entrada no meio
				for _, k in { -1, 1 } do
					local fx, fz = rot(x, z, yaw, k * 3.7 * K / M, front)
					padded(
						"bamboo_fence",
						fx,
						fz,
						yaw + math.pi / 2,
						0.75,
						"village",
						{ village = i, padLevel = it.base }
					)
				end
			end
			if on(32) then -- pote d'água ao lado da porta
				local jx, jz = rot(x, z, yaw, hx + 0.5 / M, -hz * 0.4)
				seated("water_jar", jx, jz, yaw, 1, "village", { village = i })
			end
			if on(64) and not on(4) then -- meda de palha no fundo, à direita (onde não há celeiro)
				local mx, mz = rot(x, z, yaw, side, back)
				padded("straw_stack", mx, mz, yaw, 0.85 * K, "village", { village = i, padLevel = it.base })
			end
			if on(128) then -- varal no meio do fundo
				local vx, vz = rot(x, z, yaw, 0, back)
				padded("bamboo_clothesline", vx, vz, yaw, 0.9, "village", { village = i, padLevel = it.base })
			end
		end
		-- pagode, casa comunal, poço e bancas do mercado
		for _, sp in V.specials do
			if sp.kind == "poco" then
				padded("well", sp.x, sp.z, vyaw, 1, "special")
			else
				local hx, hz = sp.w / 2, sp.d / 2
				local pad = Site.addPad(ctx.site, sp.x, sp.z, vyaw, hx, hz, sp.kind ~= "banca")
				-- a porta (-Z local, MapLife.villagePart) virada para a praça: meia volta se a praça
				-- fica do lado +Z (a pegada é simétrica, o patamar não muda)
				local toPlaza = (V.x - sp.x) * math.sin(vyaw) + (V.z - sp.z) * math.cos(vyaw)
				table.insert(out, {
					key = "parts:" .. sp.kind,
					x = sp.x,
					z = sp.z,
					yaw = if toPlaza > 0 then vyaw + math.pi else vyaw,
					scale = 1,
					hx = hx,
					hz = hz,
					base = pad.level,
					group = "special",
					foliage = false,
					shadow = true,
					padded = true,
				})
			end
		end
	end
	-- com todos os patamares no chão: base nunca acima do chão mais baixo sob a pegada (onde dois
	-- patamares se encostam o chão é a média dos dois)
	for _, it in out do
		if not it.sink and it.key ~= "log_bridge" then
			local lo = ArtPlan.footprint(ctx, it.x, it.z, it.yaw, it.hx * 0.95, it.hz * 0.95)
			it.base = math.min(it.base, lo)
		end
	end
	return out
end

-- ===== plantas =====
local function segDist(px: number, pz: number, x1: number, z1: number, x2: number, z2: number): number
	local dx, dz = x2 - x1, z2 - z1
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((px - x1) * dx + (pz - z1) * dz) / l2, 0, 1) else 0
	local qx, qz = x1 + t * dx - px, z1 + t * dz - pz
	return math.sqrt(qx * qx + qz * qz)
end

-- Motivo de o chão em (x, z) não aceitar planta (ou toca) de raio r (studs), ou nil:
-- "lamina", "dique", "estrada", "beco", "patamar", "riacho", "clareira", "objeto".
function ArtPlan.groundProblem(ctx: Ctx, x: number, z: number, r: number): string?
	local site = ctx.site
	if TerrainBuilder.paddyTop(ctx.paddies, x, z, r * 0.5) then
		return "lamina"
	end
	local b = ctx.dikeBuckets[bkey(math.floor(x / BUCKET), math.floor(z / BUCKET))]
	if b then
		for _, s in b do
			if segDist(x, z, s[1], s[2], s[3], s[4]) < ArtPlan.DIKE_HALF_M / M + r * 0.5 then
				return "dique"
			end
		end
	end
	local kind, d, _, hw = Site.road(site, x, z)
	if kind and d < hw + ArtPlan.ROAD_CLEAR_M / M + r * 0.5 then
		return "estrada"
	end
	if Site.lane(site, x, z) then
		return "beco"
	end
	local pad, t = Site.pad(site, x, z)
	if pad and t < 0.25 then
		return "patamar"
	end
	local w = ctx.world
	local rr = r * 0.5
	if
		w:classAt(x, z) == 5
		or w:classAt(x + rr, z) == 5
		or w:classAt(x - rr, z) == 5
		or w:classAt(x, z + rr) == 5
		or w:classAt(x, z - rr) == 5
	then
		return "riacho"
	end
	if Vegetation.blocked({ exclude = ctx.spawnCircles, corridors = ctx.spawnLanes } :: any, x, z) then
		return "clareira"
	end
	for _, s in ctx.small do
		local dx, dz = x - s.x, z - s.z
		local lim = math.max(s.hx, s.hz) + rr
		if dx * dx + dz * dz < lim * lim then
			return "objeto"
		end
	end
	return nil
end

-- passos (em células da grade) da planta do riacho até a margem
local BANK_STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }

function ArtPlan.plantRadius(key: string, scale: number): number
	return (ArtBudget.BASE_R[key] or 1) * scale
end

-- pé da planta: 10 cm abaixo do ponto mais baixo do chão sob ele (mais o disco de terra do modelo,
-- ArtBudget.BASE_SINK, quando há)
function ArtPlan.plantBase(ctx: Ctx, x: number, z: number, r: number, key: string?, scale: number?): number
	local s = ctx.site
	local rr = r * 0.35
	-- (entre parênteses: Site.column devolve 4 valores e o último iria inteiro para o math.min)
	local lo = math.min(
		(Site.column(s, x, z)),
		(Site.column(s, x + rr, z)),
		(Site.column(s, x - rr, z)),
		(Site.column(s, x, z + rr)),
		(Site.column(s, x, z - rr))
	)
	local extra = key and ArtBudget.BASE_SINK[key]
	local disc = if extra then extra.frac * extra.height * (scale or 1) else 0
	return lo - ArtPlan.PLANT_SINK_M / M - disc
end

-- (x, z) cai dentro da pegada de uma construção com patamar ou casa, com folga `pad` (studs)
function ArtPlan.inside(structures: { Item }, x: number, z: number, pad: number): boolean
	for _, s in structures do
		if s.padded or s.group == "house" or s.group == "base" then
			local dx, dz = x - s.x, z - s.z
			local lim = math.sqrt(s.hx * s.hx + s.hz * s.hz) + pad
			if dx * dx + dz * dz < lim * lim then
				local ca, sa = math.cos(s.yaw), math.sin(s.yaw)
				local lx, lz = dx * ca - dz * sa, dx * sa + dz * ca
				if math.abs(lx) < s.hx + pad and math.abs(lz) < s.hz + pad then
					return true
				end
			end
		end
	end
	return false
end

-- Tudo que é planta: quintais, Colina 30, bambuzal da vila, sebes, canteiros de muda e a mata.
-- structures: ArtPlan.structures (as zonas livres saem delas); corridors: raias do campo de tiro.
-- has(key): modelo publicado. yield: chamado de vez em quando (task.wait no Roblox).
function ArtPlan.plants(
	ctx: Ctx,
	structures: { Item },
	corridors: { any },
	has: (string) -> boolean,
	yield: (() -> ())?
): { Item }
	local out: { Item } = {}
	local MC = ctx.mapConfig
	local B = MC.Bounds
	local function inBounds(x: number, z: number): boolean
		return x >= B.minX and x <= B.maxX and z >= B.minZ and z <= B.maxZ
	end
	local group = "plant" -- "jungle" na mata (o AssetLoader desbasta pelo teto do setor)
	local function add(key: string, x: number, z: number, yaw: number, scale: number, shadow: boolean?): boolean
		local r = ArtPlan.plantRadius(key, scale)
		if ArtPlan.groundProblem(ctx, x, z, r) or ArtPlan.inside(structures, x, z, r * 0.5) then
			return false
		end
		table.insert(out, {
			key = key,
			x = x,
			z = z,
			yaw = yaw,
			scale = scale,
			hx = r,
			hz = r,
			base = ArtPlan.plantBase(ctx, x, z, r, key, scale),
			group = group,
			foliage = true,
			shadow = shadow == true,
			padded = false,
		})
		return true
	end
	-- quintais das casas da carta
	for _, p in ctx.pending do
		if inBounds(p.x, p.z) then
			add(p.key, p.x, p.z, p.yaw, p.scale)
		end
	end
	local rng = Rng.new(19650818 + 7)
	-- Colina 30: bosque ralo no topo
	for _, l in MC.Locations do
		if string.find(l.name, "Colina") then
			for i = 1, 60 do
				local a, r = rng:range(0, 2 * math.pi), math.sqrt(rng:next()) * 110 / M
				local key, scale = if i % 2 == 0 then "ph_island_tree_01" else "ph_island_tree_02", rng:range(2.6, 3.4)
				if not has(key) then
					key, scale = "hill_tree", 1
				end
				local tx, tz = l.x + math.cos(a) * r, l.z + math.sin(a) * r
				if inBounds(tx, tz) then
					add(key, tx, tz, a, scale, scale >= 3.0)
				end
			end
		end
	end
	-- vila: bambuzal em volta (a "lũy tre" das vilas da planície) e fruteiras nos quintais
	local V = ctx.village
	if V then
		local ca, sa = math.cos(-V.yaw), math.sin(-V.yaw)
		local umax, vmax = 0, 0
		for _, h in V.houses do
			local dx, dz = h[1] - V.x, h[2] - V.z
			umax = math.max(umax, math.abs(dx * ca + dz * sa))
			vmax = math.max(vmax, math.abs(-dx * sa + dz * ca))
		end
		local ru, rv = umax + V.lotW / 2 + 3 / M, vmax + V.lotD / 2 + 3 / M
		local function world(u: number, v: number): (number, number)
			return V.x + u * ca - v * sa, V.z + u * sa + v * ca
		end
		local step = 7 / M
		local u = -ru
		while u <= ru do
			for _, v in { -rv, rv } do
				local x, z = world(u + rng:range(-1, 1) / M, v + rng:range(-1, 1) / M)
				add("bamboo_clump", x, z, rng:range(0, 6.28), rng:range(0.9, 1.2))
			end
			u += step
		end
		local v = -rv + step
		while v <= rv - step do
			for _, uu in { -ru, ru } do
				local x, z = world(uu + rng:range(-1, 1) / M, v + rng:range(-1, 1) / M)
				add("bamboo_clump", x, z, rng:range(0, 6.28), rng:range(0.9, 1.2))
			end
			v += step
		end
		-- fruteiras nos quintais: coqueiro ou bananeira atrás de 1 em cada 3 casas
		for i, h in V.houses do
			if i % 3 == 0 then
				local key = if i % 2 == 0 then "coconut_palm" else "banana"
				local tx, tz = rot(h[1], h[2], h[3], rng:range(-4, 4) / M, V.lotD / 2 + 1 / M)
				add(key, tx, tz, rng:range(0, 6.28), rng:range(0.9, 1.1))
			end
		end
	end
	-- sebes: touceiras ao longo da linha, fora do dique e da água (tenta a linha e os dois lados)
	for k, hd in ctx.hedges do
		if yield and k % 100 == 0 then
			yield()
		end
		local tall = hd.h > 3 / M
		local key = if tall then "bamboo_clump" elseif rng:next() < 0.5 then "shrub" else "elephant_grass"
		local len = math.sqrt((hd.x2 - hd.x1) ^ 2 + (hd.z2 - hd.z1) ^ 2)
		local n = ArtBudget.hedgeClumps((len + hd.t * 0.5) * M, tall)
		local ux, uz = (hd.x2 - hd.x1) / math.max(len, 1e-3), (hd.z2 - hd.z1) / math.max(len, 1e-3)
		local r = ArtPlan.plantRadius(key, 1)
		local off = ArtPlan.DIKE_HALF_M / M + r * 0.6
		for i = 1, n do
			local t = (i - 0.5) / n
			local x, z = hd.x1 + (hd.x2 - hd.x1) * t, hd.z1 + (hd.z2 - hd.z1) * t
			local yaw = rng:range(0, 6.28)
			if inBounds(x, z) then
				local _ = add(key, x, z, yaw, 1)
					or add(key, x - uz * off, z + ux * off, yaw, 1)
					or add(key, x + uz * off, z - ux * off, yaw, 1)
			end
		end
	end
	-- canteiros de muda (rice_patch) na beira do arrozal de cada vila
	local world = ctx.world
	for _, l in MC.Locations do
		if l.name == "An Cường (2)" or l.name == "Nam Yên (4)" or l.name == "An Thới (2)" then
			local vx, vz = l.x, l.z
			for _, sp in MC.Strongpoints do
				if sp.name == l.name then
					vx, vz = sp.x, sp.z
				end
			end
			for _ = 1, 60 do
				local a, r = rng:range(0, 2 * math.pi), rng:range(35, 80) / M
				local x0, z0 = vx + math.cos(a) * r, vz + math.sin(a) * r
				if
					inBounds(x0, z0)
					and world:classAt(x0, z0) == 2
					and not ArtPlan.groundProblem(ctx, x0, z0, 4 / M)
				then
					for i = 0, 3 do
						for j = 0, 1 do
							local tx, tz = rot(x0, z0, -a, i * 2 / M, j * 1.45 / M)
							add("rice_patch", tx, tz, -a, 1)
						end
					end
					break
				end
			end
		end
	end
	-- mata pela paisagem (D-64/D-65), com o mesmo filtro de chão
	local exclude = Vegetation.exclusions(MC, ctx.housesXZ, {})
	for _, c in ctx.spawnCircles do
		table.insert(exclude, c)
	end
	local lanes = table.clone(corridors)
	for _, s in ctx.spawnLanes do
		table.insert(lanes, s)
	end
	local plan = Vegetation.plan({
		classAt = function(x: number, z: number): number
			return world:classAt(x, z)
		end,
		kindAt = function(x: number, z: number): number
			return ctx.landscape:kindAt(x, z)
		end,
		bounds = B,
		cell = world.grid.cellStuds,
		exclude = exclude,
		corridors = lanes,
		density = ArtBudget.JUNGLE_DENSITY,
		seed = 1965,
		rng = Rng.new(19650818 + 64),
		yield = yield,
	})
	local cell = world.grid.cellStuds
	group = "jungle"
	for i, it in plan do
		if yield and i % 500 == 0 then
			yield()
		end
		local key, scale = it.key, it.scale
		local fb = Vegetation.FALLBACK[key]
		if fb and not has(key) then
			key, scale = fb[1], scale * fb[2] -- espécie nova ainda sem ID publicado (D-65)
		end
		local outside = not inBounds(it.x, it.z)
		if outside then
			-- cortina de fora: só a beira do recorte, sem o filtro de chão (ninguém chega lá)
			local r = ArtPlan.plantRadius(key, scale)
			table.insert(out, {
				key = key,
				x = it.x,
				z = it.z,
				yaw = it.yaw,
				scale = scale,
				hx = r,
				hz = r,
				base = ArtPlan.plantBase(ctx, it.x, it.z, r, key, scale),
				group = "border",
				foliage = true,
				shadow = false,
				padded = false,
			})
		elseif
			not add(key, it.x, it.z, it.yaw, scale, it.shadow)
			and ctx.landscape:kindAt(it.x, it.z) == Landscape.STREAM
		then
			-- planta do riacho caída no leito: vai para a margem mais perto (o barranco de bambu)
			for _, o in BANK_STEPS do
				if add(key, it.x + o[1] * cell, it.z + o[2] * cell, it.yaw, scale, it.shadow) then
					break
				end
			end
		end
	end
	return out
end

-- Lugar da ponte de toras: a célula de riacho mais perto e o giro que a atravessa no leito (MapLife).
function ArtPlan.bridgeSpot(world: any, x: number, z: number, radius: number): (number?, number?, number?)
	local g = world.grid
	local cell = g.cellStuds
	local best, bx, bz = math.huge, nil :: number?, nil :: number?
	local n = math.ceil(radius / cell)
	local c0 = math.floor((x - g.originX) / cell)
	local r0 = math.floor((z - g.originZ) / cell)
	for dr = -n, n do
		for dc = -n, n do
			local px = g.originX + (c0 + dc + 0.5) * cell
			local pz = g.originZ + (r0 + dr + 0.5) * cell
			local d = (px - x) ^ 2 + (pz - z) ^ 2
			if d < best and d <= radius * radius and world:classAt(px, pz) == 5 then
				best, bx, bz = d, px, pz
			end
		end
	end
	if not (bx and bz) then
		return nil, nil, nil
	end
	local reach = 12 / M
	local k = math.ceil(reach / cell)
	local sx, sz, sxx, szz, sxz, n2 = 0, 0, 0, 0, 0, 0
	local bc = math.floor((bx - g.originX) / cell)
	local br = math.floor((bz - g.originZ) / cell)
	local pts = {}
	for dr = -k, k do
		for dc = -k, k do
			local px = g.originX + (bc + dc + 0.5) * cell
			local pz = g.originZ + (br + dr + 0.5) * cell
			if (px - bx) ^ 2 + (pz - bz) ^ 2 <= reach * reach and world:classAt(px, pz) == 5 then
				table.insert(pts, { px, pz })
				sx += px
				sz += pz
				n2 += 1
			end
		end
	end
	sx, sz = sx / n2, sz / n2
	for _, p in pts do
		local dx, dz = p[1] - sx, p[2] - sz
		sxx += dx * dx
		szz += dz * dz
		sxz += dx * dz
	end
	local along = 0.5 * math.atan2(2 * sxz, sxx - szz)
	local px, pz = -math.sin(along), math.cos(along)
	return bx, bz, math.atan2(-pz, px)
end

return ArtPlan
