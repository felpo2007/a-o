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
-- Uso (a partir de vantuong65/): lune run tools/carta_dados.luau
-- Saída em assets/carta/dados/ (fora do Git): alturas.bin (u16, cm + offset, por célula),
-- paisagem.bin, classes.bin, baixada.bin e cipo.bin (u8 por célula) e dados.json.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local FeatureBuilder = require("../src/ServerStorage/VT65Build/FeatureBuilder")
local Landscape = require("../src/ServerStorage/VT65Build/Landscape")
local WorldData = require("../src/ServerStorage/VT65Build/WorldData")
local Features = require("../src/ServerStorage/VT65Build/Data/Features") :: any
local Grid = require("../src/ServerStorage/VT65Build/Data/Grid") :: any
local MapConfig = require("../src/ReplicatedStorage/Shared/MapConfig") :: any
local Tunnels = require("../src/ReplicatedStorage/Shared/Tunnels") :: any
local Vegetation = require("../src/ServerScriptService/Modules/Vegetation")

local M = 0.28
local OUT = "assets/carta/dados"
-- sementes do plano da mata no jogo (AssetLoader e tools/ArtEstimate: seed = 1965)
local SEED = 1965

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, (require :: any)("../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)

local housesXZ = {}
for i = 1, #Features.houses, 4 do
	table.insert(housesXZ, Features.houses[i])
	table.insert(housesXZ, Features.houses[i + 1])
end
local landscape = Landscape.new(world, MapConfig, housesXZ)

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

local FOREST = Landscape.FOREST
local function forest(x: number, z: number): boolean
	return landscape:kindAt(x, z) == FOREST
end

-- diques, lâminas e sebes: o mesmo filtro do FeatureBuilder.build (o que existe no place)
local dikes = {}
local d = FeatureBuilder.mergeDikes(Features.dikes)
for i = 1, #d, 6 do
	local mx, mz = (d[i] + d[i + 2]) / 2, (d[i + 1] + d[i + 3]) / 2
	if not (forest(mx, mz) and forest(d[i], d[i + 1]) and forest(d[i + 2], d[i + 3])) then
		table.insert(dikes, { d[i], d[i + 1], d[i + 2], d[i + 3] })
	end
end
local waters = {}
local wt = Features.waters
for i = 1, #wt, 6 do
	if not forest(wt[i], wt[i + 1]) then
		table.insert(waters, { wt[i], wt[i + 1], wt[i + 3], wt[i + 4], wt[i + 5] })
	end
end
local hedges = {}
local hg = Features.hedges
for i = 1, #hg, 7 do
	if not forest((hg[i] + hg[i + 2]) / 2, (hg[i + 1] + hg[i + 3]) / 2) then
		table.insert(hedges, { hg[i], hg[i + 1], hg[i + 2], hg[i + 3], hg[i + 5] * M })
	end
end
local houses = {}
local hs = Features.houses
for i = 1, #hs, 4 do
	table.insert(houses, { hs[i], hs[i + 1], hs[i + 3] })
end
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
	},
	dikes = dikes,
	waters = waters,
	hedges = hedges,
	houses = houses,
	trench = trench,
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
		"carta: grade %d x %d; %d diques, %d lâminas, %d sebes, %d casas (%.1f s) -> %s",
		w,
		h,
		#dikes,
		#waters,
		#hedges,
		#houses,
		os.clock() - t0,
		OUT
	)
)
