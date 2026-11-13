--!strict
-- Lune: exporta, a partir dos dados do próprio jogo, o que a carta topográfica (tools/make_carta.py)
-- desenha. Usa os mesmos módulos do bake e do servidor, para a carta bater com o mundo:
--   - WorldData (alturas e uso do solo da grade de 16 studs = 4,48 m);
--   - Landscape.kindAt (D-65: mata, bosque de vila, lavoura, clareira, riacho);
--   - Vegetation.noise com as sementes do plano da mata (manchas de baixada com tràm e bambu, e
--     manchas de cipó), que não dependem do sorteio planta a planta;
--   - FeatureBuilder.mergeDikes e o mesmo filtro de mata do bake (só os diques, lâminas d'água e
--     sebes que existem no place);
--   - casas, trincheira sul de An Cường (2) e o MapConfig (limites, grade, locais, setores, QGs).
-- 2026-11-12: o plano da arte (ArtPlan) dá a paisagem (com a roça seca), os diques e lâminas que
-- ficaram, a vila grande (casas, pagode, casa comunal, nome) e as estradas (Data/Roads).
-- Uso (a partir de vantuong65/): lune run tools/carta_dados.luau
-- Saída em assets/carta/dados/ (fora do Git): alturas.bin (u16, cm + offset, por célula),
-- paisagem.bin, classes.bin, baixada.bin e cipo.bin (u8 por célula) e dados.json.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Landscape = require("../src/ServerStorage/VT65Build/Landscape")
local WorldData = require("../src/ServerStorage/VT65Build/WorldData")
local Features = require("../src/ServerStorage/VT65Build/Data/Features") :: any
local Village = require("../src/ServerStorage/VT65Build/Data/Village") :: any
local Roads = require("../src/ServerStorage/VT65Build/Data/Roads") :: any
local Grid = require("../src/ServerStorage/VT65Build/Data/Grid") :: any
local MapConfig = require("../src/ReplicatedStorage/Shared/MapConfig") :: any
local Tunnels = require("../src/ReplicatedStorage/Shared/Tunnels") :: any
local AssetIds = require("../src/ReplicatedStorage/Shared/AssetIds") :: any
local Vegetation = require("../src/ServerScriptService/Modules/Vegetation")
local ArtPlan = require("../src/ServerScriptService/Modules/ArtPlan") :: any

local M = 0.28
local OUT = "assets/carta/dados"
-- sementes do plano da mata no jogo (AssetLoader e tools/ArtEstimate: seed = 1965)
local SEED = 1965

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, (require :: any)("../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)

local ctx = ArtPlan.load(world, { features = Features, village = Village, roads = Roads, mapConfig = MapConfig })
local structures = ArtPlan.structures(ctx, function(k: string): boolean
	local id = AssetIds.Models[k]
	return type(id) == "number" and id ~= 0
end)
local landscape = ctx.landscape

local w, h, cell = Grid.width, Grid.height, Grid.cellStuds
local kinds = buffer.create(w * h)
local wet = buffer.create(w * h)
local tangle = buffer.create(w * h)
local t0 = os.clock()
for row = 0, h - 1 do
	local z = Grid.originZ + (row + 0.5) * cell
	for col = 0, w - 1 do
		local x = Grid.originX + (col + 0.5) * cell
		local i = row * w + col
		buffer.writeu8(kinds, i, landscape:kindAt(x, z))
		-- mesmos ruídos do Vegetation.plan: baixada úmida (tràm e bambu, ~120 m) e cipó (~90 m)
		buffer.writeu8(wet, i, math.floor(Vegetation.noise(x, z, 120 / M, SEED + 7) * 255 + 0.5))
		buffer.writeu8(tangle, i, math.floor(Vegetation.noise(x, z, 90 / M, SEED + 13) * 255 + 0.5))
	end
end

-- diques, lâminas e sebes: os do plano da arte (o que existe no place)
local dikes = ctx.dikes
local waters = {}
for _, p in ctx.paddies.list do
	-- o tabuleiro guarda a meia medida e o giro em cos/sin
	table.insert(waters, { p.x, p.z, p.hu * 2, p.hv * 2, math.atan2(p.sa, p.ca) })
end
local hedges = {}
for _, hd in ctx.hedges do
	table.insert(hedges, { hd.x1, hd.z1, hd.x2, hd.z2, hd.h * M })
end
local houses = {}
local hs = Features.houses
for i = 1, #hs, 4 do
	table.insert(houses, { hs[i], hs[i + 1], hs[i + 3] })
end
-- vila grande: casas (pegada do plano), pagode, casa comunal, poço e bancas
local villageHouses, specials = {}, {}
for _, s in structures do
	if s.group == "village" and s.home then
		table.insert(villageHouses, { s.x, s.z, s.yaw, s.hx * 2, s.hz * 2 })
	elseif s.group == "special" then
		table.insert(
			specials,
			{ kind = string.gsub(s.key, "parts:", ""), x = s.x, z = s.z, yaw = s.yaw, w = s.hx * 2, d = s.hz * 2 }
		)
	end
end
local roads = {}
for _, r in Roads.roads do
	local pts = {}
	for i = 1, #r.pts - 2, 3 do
		table.insert(pts, { r.pts[i], r.pts[i + 1] })
	end
	table.insert(roads, { kind = r.kind, w = Roads.width[r.kind] * M, pts = pts })
end
local lanes = {}
for _, l in Village.lanes do
	table.insert(lanes, { { l[1], l[2] }, { l[3], l[4] } })
end
local gx, gz = ArtPlan.cemetery(MapConfig)
-- trincheira sul de An Cường (2) (Tunnels.trench, traçado de design já posto no mundo)
local cx, cz = 0, 0
for _, l in MapConfig.Locations do
	if l.name == "An Cường (2)" then
		cx, cz = l.x, l.z
	end
end
local trench = {}
for _, p in Tunnels.trench do
	local x, z = Tunnels.toWorld(cx, cz, p[1], p[2])
	table.insert(trench, { x, z })
end

local info = {
	grid = {
		width = w,
		height = h,
		cellStuds = cell,
		originX = Grid.originX,
		originZ = Grid.originZ,
		heightOffsetCm = Grid.heightOffsetCm,
		classNames = Grid.classNames,
	},
	studM = M,
	bounds = MapConfig.Bounds,
	gridOrigin1965 = MapConfig.GridOrigin1965,
	locations = MapConfig.Locations,
	strongpoints = MapConfig.Strongpoints,
	hq = MapConfig.HQ,
	sectors = MapConfig.Sectors,
	landscape = {
		forest = Landscape.FOREST,
		grove = Landscape.GROVE,
		farm = Landscape.FARM,
		clear = Landscape.CLEAR,
		stream = Landscape.STREAM,
		roca = Landscape.ROCA,
	},
	dikes = dikes,
	waters = waters,
	hedges = hedges,
	houses = houses,
	trench = trench,
	village = { name = Village.name, x = Village.x, z = Village.z, houses = villageHouses, specials = specials },
	roads = roads,
	lanes = lanes,
	cemetery = { x = gx, z = gz },
}

if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
fs.writeFile(OUT .. "/alturas.bin", world.heights)
fs.writeFile(OUT .. "/classes.bin", world.classes)
fs.writeFile(OUT .. "/paisagem.bin", kinds)
fs.writeFile(OUT .. "/baixada.bin", wet)
fs.writeFile(OUT .. "/cipo.bin", tangle)
fs.writeFile(OUT .. "/dados.json", serde.encode("json", info, false))
print(
	string.format(
		"carta: grade %d x %d; %d diques, %d lâminas, %d sebes, %d casas da carta, %d da vila, %d estradas (%.1f s) -> %s",
		w,
		h,
		#dikes,
		#waters,
		#hedges,
		#houses,
		#villageHouses,
		#roads,
		os.clock() - t0,
		OUT
	)
)
