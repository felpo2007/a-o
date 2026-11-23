--!nocheck
-- D-243: exporta os dados de um mapa retangular para o pintor da vista aérea (tools/mapa_aereo.py --mapa <id>).
-- A folha da carta é quadrada e cobre a largura do mapa; a faixa jogável fica no meio dela.
-- Uso (a partir de vantuong65/): lune run tools/carta_ret.luau frente | comboio
-- Saída em assets/carta/dados_<id>/ (fora do Git).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local ArtBudget = require("../src/ServerScriptService/Modules/ArtBudget")
local ArtPlan = require("../src/ServerScriptService/Modules/ArtPlan")
local Landscape = require("../src/ServerStorage/VT65Build/Landscape")
local MapConfig = require("../src/ReplicatedStorage/Shared/MapConfig")
local MapaAtivo = require("../src/ReplicatedStorage/Shared/MapaAtivo")
local Vegetation = require("../src/ServerScriptService/Modules/Vegetation")
local WorldData = require("../src/ServerStorage/VT65Build/WorldData")

local id = process.args[1]
assert(id == "frente" or id == "comboio", "uso: lune run tools/carta_ret.luau frente|comboio")

local M = 0.28
local SEED = 1965
local OUT = "assets/carta/dados_" .. id
local BASE = "../src/ServerStorage/VT65Build/Data_" .. id .. "/"
local Grid = require(BASE .. "Grid")
local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, require(BASE .. name))
end
local Features, Roads, Layout = require(BASE .. "Features"), require(BASE .. "Roads"), require(BASE .. "Layout")

local mc = MapaAtivo.configPara(id)
local world = WorldData.load(Grid, chunks)
local ctx = ArtPlan.load(world, { features = Features, roads = Roads, layout = Layout, mapConfig = mc })
local structures = ArtPlan.structures(ctx, function(k)
	return ArtBudget.DIMS[k] ~= nil
end)

local w, h, cell = Grid.width, Grid.height, Grid.cellStuds
local kinds, wet, tangle = buffer.create(w * h), buffer.create(w * h), buffer.create(w * h)
for row = 0, h - 1 do
	local z = Grid.originZ + (row + 0.5) * cell
	for col = 0, w - 1 do
		local x = Grid.originX + (col + 0.5) * cell
		local i = row * w + col
		buffer.writeu8(kinds, i, ctx.landscape:kindAt(x, z))
		buffer.writeu8(wet, i, math.floor(Vegetation.noise(x, z, 120 / M, SEED + 7) * 255 + 0.5))
		buffer.writeu8(tangle, i, math.floor(Vegetation.noise(x, z, 90 / M, SEED + 13) * 255 + 0.5))
	end
end

local waters = {}
for _, p in ctx.paddies.list do
	table.insert(waters, { p.x, p.z, p.hu * 2, p.hv * 2, math.atan2(p.sa, p.ca) })
end
local casas, especiais = {}, {}
for _, s in structures do
	table.insert(casas, { s.x, s.z, s.yaw, s.hx * 2, s.hz * 2 })
end
for _, p in Layout.pontes do
	local dx, dz = p.x2 - p.x1, p.z2 - p.z1
	table.insert(especiais, {
		kind = "ponte",
		x = (p.x1 + p.x2) / 2,
		z = (p.z1 + p.z2) / 2,
		yaw = math.atan2(-dz, dx),
		w = math.sqrt(dx * dx + dz * dz),
		d = p.largura,
	})
end
local roads = {}
for _, r in Roads.roads do
	local pts = {}
	for i = 1, #r.pts - 2, 3 do
		table.insert(pts, { r.pts[i], r.pts[i + 1] })
	end
	table.insert(roads, { kind = r.kind, w = Roads.width[r.kind] * M, pts = pts })
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
	bounds = mc.CartaBounds,
	area = mc.Bounds,
	gridOrigin1965 = MapConfig.GridOrigin1965,
	landscape = {
		forest = Landscape.FOREST,
		grove = Landscape.GROVE,
		farm = Landscape.FARM,
		clear = Landscape.CLEAR,
		stream = Landscape.STREAM,
		roca = Landscape.ROCA,
	},
	dikes = ctx.dikes,
	waters = waters,
	hedges = {},
	houses = {},
	trench = {},
	village = { name = id, x = 0, z = 0, houses = casas, specials = especiais },
	roads = roads,
	lanes = {},
	aguasExp = {},
	bases = {},
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
		"carta %s: grade %d x %d, %d lâminas, %d construções, %d pontes, %d vias -> %s",
		id,
		w,
		h,
		#waters,
		#casas,
		#especiais,
		#roads,
		OUT
	)
)
