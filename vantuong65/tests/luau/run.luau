--!strict
-- Testes Luau (Lune). Uso, a partir de vantuong65/:  lune run tests/luau/run.luau
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Base64 = require("../../src/ServerStorage/VT65Build/Base64")
local WorldData = require("../../src/ServerStorage/VT65Build/WorldData")
local Geometry = require("../../src/ReplicatedStorage/Shared/Geometry")
local Units = require("../../src/ReplicatedStorage/Shared/Units")
local MapConfig = require("../../src/ReplicatedStorage/Shared/MapConfig") :: any
local Grid = require("../../src/ServerStorage/VT65Build/Data/Grid") :: any

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
local function near(a: number, b: number, tol: number, msg: string?)
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f (tol %.4f)", msg or "", a, b, tol))
end

test("base64 decodifica vetores conhecidos", function()
	assert(buffer.tostring(Base64.decode("TWFu")) == "Man")
	assert(buffer.tostring(Base64.decode("TWE=")) == "Ma")
	assert(buffer.tostring(Base64.decode("TQ==")) == "M")
	assert(buffer.tostring(Base64.decode("")) == "")
end)

test("unidades: 1 stud = 0,28 m; soldado 6,25 studs", function()
	near(Units.toStuds(2000), 7142.857, 0.01)
	near(Units.SOLDIER_HEIGHT, 6.25, 0.001)
end)

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, (require :: any)("../../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)

test("alturas no Luau batem com o Python (fixture)", function()
	local fixture = net.jsonDecode(fs.readFile("tests/luau/fixture_heights.json"))
	for _, f in fixture do
		near(world:heightAt(f.x, f.z), f.h_studs, 0.05, f.name)
	end
end)

test("Colina 43 chega a 43 m no terreno", function()
	local sp = MapConfig.Strongpoints[1]
	assert(sp.name == "Colina 43")
	near(world:heightAt(sp.x, sp.z) * 0.28, 43.0, 0.5, "cume")
end)

test("área jogável é 2,0 x 2,0 km (D-63) e o terreno a cobre com margem", function()
	local b = MapConfig.Bounds
	near((b.maxX - b.minX) * 0.28, 2000, 1)
	near((b.maxZ - b.minZ) * 0.28, 2000, 1)
	-- o terreno recortado (tools/crop_world.py) cobre a área inteira mais ~150 m de margem
	local g = require("../../src/ServerStorage/VT65Build/Data/Grid") :: any
	local gx0, gz0 = g.originX, g.originZ
	local gx1, gz1 = gx0 + g.width * g.cellStuds, gz0 + g.height * g.cellStuds
	assert(gx0 <= b.minX - 100 / 0.28 and gx1 >= b.maxX + 100 / 0.28, "terreno cobre leste-oeste")
	assert(gz0 <= b.minZ - 100 / 0.28 and gz1 >= b.maxZ + 100 / 0.28, "terreno cobre norte-sul")
end)

test("15 pontos fortes, 3 por setor, cada um dentro do seu setor e com >= 1 real", function()
	assert(#MapConfig.Strongpoints == 15, "total")
	local count, real = {}, {}
	for _, sp in MapConfig.Strongpoints do
		local s = Geometry.sectorAt(MapConfig.Sectors, sp.x, sp.z)
		assert(s == sp.sector, sp.name .. " caiu no setor " .. tostring(s))
		assert(Geometry.inBounds(MapConfig.Bounds, sp.x, sp.z), sp.name .. " fora da área")
		count[s] = (count[s] or 0) + 1
		if sp.real then
			real[s] = true
		end
	end
	for s = 1, 5 do
		assert(count[s] == 3, "setor " .. s .. " tem " .. tostring(count[s]))
		assert(real[s], "setor " .. s .. " sem local real")
	end
end)

test("QGs: EUA no setor 5, VC no setor 1", function()
	assert(Geometry.sectorAt(MapConfig.Sectors, MapConfig.HQ.US.x, MapConfig.HQ.US.z) == 5)
	assert(Geometry.sectorAt(MapConfig.Sectors, MapConfig.HQ.VC.x, MapConfig.HQ.VC.z) == 1)
end)

test("setores cobrem a área sem buraco nem sobreposição (amostra de 50 m)", function()
	local b = MapConfig.Bounds
	local step = 50 / 0.28
	local x = b.minX + step / 2
	while x < b.maxX do
		local z = b.minZ + step / 2
		while z < b.maxZ do
			local hits = 0
			for _, s in MapConfig.Sectors do
				if Geometry.pointInPolygon(s.polygon, x, z) then
					hits += 1
				end
			end
			assert(hits == 1, string.format("(%.0f, %.0f) em %d setores", x, z, hits))
			z += step
		end
		x += step
	end
end)

test("quadro local -> grade de 1965 erra < 3 m em todos os locais", function()
	for _, l in MapConfig.Locations do
		local e = MapConfig.GridOrigin1965.e + l.x * 0.28
		local n = MapConfig.GridOrigin1965.n - l.z * 0.28
		assert(math.abs(e - l.e1965) < 3 and math.abs(n - l.n1965) < 3, l.name)
	end
	local h43 = MapConfig.Locations[1]
	assert(Geometry.gridRef1965(MapConfig.GridOrigin1965, h43.x, h43.z, 0.28) == "BS 685916")
end)

test("place assado tem as peças e todas ancoradas", function()
	if not fs.isFile("build/VanTuong65_F1.rbxl") then
		error("rode antes: lune run tools/bake_place.luau")
	end
	local game = roblox.deserializePlace(fs.readFile("build/VanTuong65_F1.rbxl"))
	local map = game:GetService("Workspace"):FindFirstChild("Map")
	assert(map, "sem Workspace.Map")
	local n, unanchored = 0, 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
			if not d.Anchored then
				unanchored += 1
			end
		end
	end
	assert(unanchored == 0, unanchored .. " peças soltas")
	-- D-63: recorte de 2,3 x 2,3 km (área + margem) tem ~9,7 mil diques (eram ~19 mil em 4 x 2,4 km)
	assert(#map.Dikes:GetChildren() > 8000, "diques")
	assert(#map.Strongpoints:GetChildren() == 15, "marcadores")
	print(string.format("       (%d BaseParts no Map)", n))
end)

test("TerrainBuilder (WriteVoxels simulado): dimensões, ocupação e cume da Colina 43", function()
	local TerrainBuilder = require("../../src/ServerStorage/VT65Build/TerrainBuilder")
	local h43 = MapConfig.Strongpoints[1]
	local calls, topAtHill = 0, -math.huge
	local mock = {}
	function mock.WriteVoxels(_, region: any, res: number, mats: any, occs: any)
		calls += 1
		assert(res == 4, "resolução")
		local size = region.Size
		local sx, sy, sz = size.X / 4, size.Y / 4, size.Z / 4
		assert(#mats == sx and #occs == sx, "dimensão X")
		assert(#mats[1] == sy and #mats[1][1] == sz, "dimensões Y/Z")
		local minP = region.CFrame.Position - size / 2
		for ix = 1, sx do
			for iy = 1, sy do
				for iz = 1, sz do
					local o = occs[ix][iy][iz]
					assert(o >= 0 and o <= 1, "ocupação fora de [0,1]")
				end
			end
			local cx = minP.X + (ix - 0.5) * 4
			if math.abs(cx - h43.x) < 2 then
				for iz = 1, sz do
					local cz = minP.Z + (iz - 0.5) * 4
					if math.abs(cz - h43.z) < 2 then
						for iy = 1, sy do
							local o = occs[ix][iy][iz]
							if o > 0 and mats[ix][iy][iz] ~= roblox.Enum.Material.Water then
								topAtHill = math.max(topAtHill, minP.Y + (iy - 1) * 4 + o * 4)
							end
						end
					end
				end
			end
		end
	end
	local env = {
		Enum = roblox.Enum,
		Vector3 = roblox.Vector3,
		Region3 = roblox.Region3,
		terrain = mock,
		wait = function() end,
	}
	local r = 60
	local n = TerrainBuilder.build(world, env, {
		only = { minX = h43.x - r, maxX = h43.x + r, minZ = h43.z - r, maxZ = h43.z + r },
	})
	assert(n >= 1 and calls == n, "blocos escritos")
	near(topAtHill * 0.28, 43.0, 1.2, "topo do voxel no cume")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
