--!nocheck
-- D-232: dados da planta anotada da expansão (o desenho sai de tools/expansao_planta.py).
--   lune run tools/expansao_planta.luau build/expansao_planta.json
-- Tudo em metros a partir do mastro do objetivo: o que é novo, o que já existia e o que não pode mudar.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local R = require :: any

local WorldData = R("../src/ServerStorage/VT65Build/WorldData")
local Grid = R("../src/ServerStorage/VT65Build/Data/Grid")
local Features = R("../src/ServerStorage/VT65Build/Data/Features")
local Village = R("../src/ServerStorage/VT65Build/Data/Village")
local Roads = R("../src/ServerStorage/VT65Build/Data/Roads")
local Bases = R("../src/ServerStorage/VT65Build/Data/Bases")
local MapConfig = R("../src/ReplicatedStorage/Shared/MapConfig")
local AssetIds = R("../src/ReplicatedStorage/Shared/AssetIds")
local ArtPlan = R("../src/ServerScriptService/Modules/ArtPlan")
local Expansao = R("../src/ServerScriptService/Modules/Expansao")
local M = 0.28
local RAIO_M = 150

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, R("../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)
local dados = { features = Features, village = Village, roads = Roads, bases = Bases, mapConfig = MapConfig }
local function has(key: string): boolean
	local id = AssetIds.Models[key]
	return type(id) == "number" and id ~= 0
end
local function plano(ligada: boolean)
	Expansao.LIGADA = ligada
	local ctx = ArtPlan.load(world, dados)
	local st = ArtPlan.structures(ctx, has)
	return ctx, st, ArtPlan.plants(ctx, st, {}, has)
end

local _, _, pl0 = plano(false)
local ctx, st, pl1 = plano(true)
local antes = {}
for _, p in pl0 do
	antes[string.format("%s|%.3f|%.3f", p.key, p.x, p.z)] = true
end

local B = MapConfig.Bounds
local out = { bounds = { B.minX, B.maxX, B.minZ, B.maxZ }, setores = {} }
for _, sp in MapConfig.Strongpoints do
	local setor = Expansao.SETORES[sp.name]
	if not setor then
		continue
	end
	local function perto(x: number, z: number): boolean
		return math.abs(x - sp.x) * M < RAIO_M and math.abs(z - sp.z) * M < RAIO_M
	end
	local function peca(it)
		return {
			id = it.id,
			k = it.key,
			x = (it.x - sp.x) * M,
			z = (it.z - sp.z) * M,
			giro = it.yaw,
			hx = it.hx * M,
			hz = it.hz * M,
		}
	end
	local d = {
		x = sp.x,
		z = sp.z,
		raio = RAIO_M,
		novas = {},
		antigas = {},
		plantas = {},
		nascer = {},
		becos = setor.becos,
		cortes = {},
		escavar = setor.escavar,
	}
	for _, it in st do
		if it.expansao then
			if it.objective == sp.name then
				table.insert(d.novas, peca(it))
			end
		elseif perto(it.x, it.z) then
			table.insert(d.antigas, peca(it))
		end
	end
	for _, p in pl1 do
		if perto(p.x, p.z) and not antes[string.format("%s|%.3f|%.3f", p.key, p.x, p.z)] then
			table.insert(d.plantas, { (p.x - sp.x) * M, (p.z - sp.z) * M })
		end
	end
	for _, c in ctx.spawnCircles do
		if perto(c.x, c.z) then
			table.insert(d.nascer, { (c.x - sp.x) * M, (c.z - sp.z) * M, c.r * M })
		end
	end
	for _, c in setor.cortes do
		table.insert(d.cortes, { id = c.id, pts = c.pts, largura = c.largura })
	end
	out.setores[sp.name] = d
end
fs.writeFile(process.args[1], serde.encode("json", out))
print(string.format("planta: %s", process.args[1]))
