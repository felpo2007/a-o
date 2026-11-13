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

-- D-83: o analisador não pega o limite de 200 locais por função; o compilador do Luau pega
test("todo src/ compila no Luau (limite de locais e sintaxe)", function()
	local luau = require("@lune/luau")
	local bad = {}
	local function walk(dir: string)
		for _, name in fs.readDir(dir) do
			local p = dir .. "/" .. name
			if fs.isDir(p) then
				walk(p)
			elseif string.sub(name, -5) == ".luau" then
				local ok, err = pcall(luau.compile, fs.readFile(p))
				if not ok then
					table.insert(bad, p .. ": " .. tostring(err))
				end
			end
		end
	end
	walk("src")
	assert(#bad == 0, table.concat(bad, "; "))
end)

test("base64 decodifica vetores conhecidos", function()
	assert(buffer.tostring(Base64.decode("TWFu")) == "Man")
	assert(buffer.tostring(Base64.decode("TWE=")) == "Ma")
	assert(buffer.tostring(Base64.decode("TQ==")) == "M")
	assert(buffer.tostring(Base64.decode("")) == "")
end)

test("unidades: 1 stud = 0,28 m; soldado de 2,0 m (D-98) = 7,14 studs", function()
	near(Units.toStuds(2000), 7142.857, 0.01)
	near(Units.SOLDIER_HEIGHT, 7.1429, 0.001)
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

local function strongpoint(name: string): any
	for _, sp in MapConfig.Strongpoints do
		if sp.name == name then
			return sp
		end
	end
	error("sem ponto forte " .. name)
end
local function location(name: string): any
	for _, l in MapConfig.Locations do
		if l.name == name then
			return l
		end
	end
	error("sem local " .. name)
end

-- mapa de 1 x 1 km (2026-11-11): a Colina 43 ficou fora; a Colina 30 é a cota da carta no recorte
-- (tools/relevo_dem.py calibra o cume em 30 m)
test("Colina 30 chega a ~30 m no terreno", function()
	local sp = strongpoint("Colina 30")
	near(world:heightAt(sp.x, sp.z) * 0.28, 30.0, 1.0, "cume")
end)

test("área jogável é 1,0 x 1,0 km e o terreno a cobre com margem", function()
	local b = MapConfig.Bounds
	near((b.maxX - b.minX) * 0.28, 1000, 1)
	near((b.maxZ - b.minZ) * 0.28, 1000, 1)
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
	local h30 = location("Colina 30 (cume)")
	assert(Geometry.gridRef1965(MapConfig.GridOrigin1965, h30.x, h30.z, 0.28) == "BS 702934")
end)

test("lugares que fazem o jogo estão no recorte: vilas, Colina 30, trincheira e riacho", function()
	for _, name in
		{ "Nam Yên (4)", "An Cường (2)", "An Thới (2)", "Colina 30 (cume)", "Riacho a leste de An Cường (2)" }
	do
		location(name)
	end
	-- 2026-11-12: o Cemitério deixou de ser ponto forte (objetivos no centro); a vila grande Xóm Gò é o
	-- ponto forte do S3
	for _, name in { "Nam Yên (4)", "An Cường (2)", "An Thới (2)", "Xóm Gò", "Trincheira sul", "Colina 30" } do
		local sp = strongpoint(name)
		assert(Geometry.inBounds(MapConfig.Bounds, sp.x, sp.z), name)
	end
	-- QG dos EUA perto da borda leste (a base grande vem depois). O do VC (2026-11-12, métrica de
	-- contato) saiu da borda oeste: retaguarda, a oeste de todos os pontos fortes do S2 e a até 420 m
	-- da praça de Xóm Gò
	local b = MapConfig.Bounds
	assert((b.maxX - MapConfig.HQ.US.x) * 0.28 <= 80, "QG dos EUA longe da borda leste")
	local vc = MapConfig.HQ.VC
	for _, sp in MapConfig.Strongpoints do
		if sp.sector == 2 then
			assert(vc.x < sp.x, "QG do VC na frente de " .. sp.name)
		end
	end
	local praca = strongpoint("Xóm Gò")
	assert(math.sqrt((vc.x - praca.x) ^ 2 + (vc.z - praca.z) ^ 2) * 0.28 <= 420, "QG do VC longe do centro")
end)

test("riacho a leste de An Cường (2): leito contínuo de células de riacho, abaixo da margem", function()
	assert(Grid.streamCarvedCm and Grid.streamCarvedCm > 0, "leito não foi aberto (crop_world)")
	local l = location("Riacho a leste de An Cường (2)")
	-- do sul ao norte do vale, toda linha da grade entre N 1692,55 e 1693,0 tem riacho a até 120 m
	-- a oeste do local da carta
	local cell = Grid.cellStuds
	local rows = 0
	for n = 1692550, 1693000, 10 do
		local z = (MapConfig.GridOrigin1965.n - n) / 0.28
		local row = math.floor((z - Grid.originZ) / cell)
		local col = math.floor((l.x - 120 / 0.28 - Grid.originX) / cell)
		local last = math.floor((l.x + 40 / 0.28 - Grid.originX) / cell)
		local function cls(c: number): number
			return world:classAt(Grid.originX + (c + 0.5) * cell, Grid.originZ + (row + 0.5) * cell)
		end
		while col <= last and cls(col) ~= 5 do
			col += 1
		end
		assert(col <= last, "sem riacho em N " .. n)
		-- trecho de riacho da linha e a primeira célula de chão de cada lado: o espelho d'água (fundo
		-- + 0,6 m) fica abaixo das duas margens
		local c1 = col
		while cls(c1 + 1) == 5 do
			c1 += 1
		end
		local bed = math.huge
		for c = col, c1 do
			bed = math.min(bed, world:cellHeight(c, row))
		end
		local bank = math.min(world:cellHeight(col - 1, row), world:cellHeight(c1 + 1, row))
		local surface = bed + 0.6 / 0.28
		assert(
			surface <= bank + 0.05 / 0.28,
			string.format("N %d: espelho %.2f m, margem %.2f m", n, surface * 0.28, bank * 0.28)
		)
		rows += 1
	end
	assert(rows > 40)
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
	-- D-65: diques só na lavoura das vilas. 2026-11-12: arrozal a ~15% (o dono pediu -75%; os
	-- tabuleiros em ladeira também saíram) e o dique virou lombada do terreno: a peça é só o marcador
	-- dos bots, invisível, sem colisão e fora do raio (era a "parede" de que o dono reclamou)
	local nDikes = 0
	for _, d in map.Dikes:GetChildren() do
		assert(d.Transparency == 1 and not d.CanCollide and not d.CanQuery, "dique visível ou sólido")
		nDikes += 1
	end
	assert(nDikes > 100 and nDikes < 1000, "diques: " .. nDikes)
	assert(#map.Strongpoints:GetChildren() == 15, "marcadores")
	print(string.format("       (%d BaseParts no Map)", n))
end)

test("TerrainBuilder (WriteVoxels simulado): dimensões, ocupação e cume da Colina 30", function()
	local TerrainBuilder = require("../../src/ServerStorage/VT65Build/TerrainBuilder")
	local h43 = strongpoint("Colina 30")
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
	near(topAtHill * 0.28, 30.0, 1.5, "topo do voxel no cume")
end)

test("TerrainBuilder: o riacho tem água no leito e o espelho não passa da margem", function()
	local TerrainBuilder = require("../../src/ServerStorage/VT65Build/TerrainBuilder")
	local sp = strongpoint("Riacho a leste de An Cường (2)")
	local water, overflow = 0, 0
	local streamCols: { string } = {}
	local wetCols: { [string]: boolean } = {}
	local depths: { number } = {} -- fundura (m) de cada coluna do leito: espelho menos o fundo
	local mock = {}
	function mock.WriteVoxels(_, region: any, _res: number, mats: any, occs: any)
		local size = region.Size
		local sx, sy, sz = size.X / 4, size.Y / 4, size.Z / 4
		local minP = region.CFrame.Position - size / 2
		for ix = 1, sx do
			for iz = 1, sz do
				local wx, wz = minP.X + (ix - 0.5) * 4, minP.Z + (iz - 0.5) * 4
				local key = string.format("%d,%d", wx, wz)
				local inBed = world:classAt(wx, wz) == 5
				if inBed then
					table.insert(streamCols, key)
				end
				local groundTop, waterTop = -math.huge, -math.huge
				for iy = 1, sy do
					local vb = minP.Y + (iy - 1) * 4
					local mat, occ = mats[ix][iy][iz], occs[ix][iy][iz]
					if occ > 0 and mat ~= roblox.Enum.Material.Water and mat ~= roblox.Enum.Material.Air then
						groundTop = math.max(groundTop, vb + occ * 4)
					elseif mat == roblox.Enum.Material.Water and occ > 0 then
						waterTop = math.max(waterTop, vb + occ * 4)
					end
				end
				if inBed and waterTop > groundTop then
					table.insert(depths, (waterTop - groundTop) * 0.28)
				end
				for iy = 1, sy do
					if mats[ix][iy][iz] == roblox.Enum.Material.Water and occs[ix][iy][iz] > 0 then
						water += 1
						wetCols[key] = true
						-- topo da água contra o chão mais alto a 6 m para os lados
						local top = minP.Y + (iy - 1) * 4 + occs[ix][iy][iz] * 4
						local bank = math.max(world:heightAt(wx - 6 / 0.28, wz), world:heightAt(wx + 6 / 0.28, wz))
						if top > bank + 0.15 / 0.28 then
							overflow += 1
						end
					end
				end
			end
		end
	end
	local r = 80
	TerrainBuilder.build(world, {
		Enum = roblox.Enum,
		Vector3 = roblox.Vector3,
		Region3 = roblox.Region3,
		terrain = mock,
		wait = function() end,
	}, { only = { minX = sp.x - r, maxX = sp.x + r, minZ = sp.z - r, maxZ = sp.z + r } })
	print(
		string.format("       (%d voxels de água no riacho perto do ponto forte; %d acima da margem)", water, overflow)
	)
	-- toda coluna de voxels do leito tem água (antes, com o fundo no mesmo voxel do espelho, metade
	-- das colunas ficava seca)
	local dry = 0
	for _, c in streamCols do
		if not wetCols[c] then
			dry += 1
		end
	end
	-- fundura contínua perto dos 0,6 m do projeto (antes ia de 0 a ~1,1 m de um passo para o outro);
	-- mais funda só onde a coluna fica entre duas células de leito em degraus diferentes
	local near06, shallow = 0, 0
	for _, d in depths do
		if math.abs(d - 0.6) <= 0.05 then
			near06 += 1
		elseif d < 0.55 then
			shallow += 1
		end
	end
	print(
		string.format(
			"       (%d colunas de leito, %d sem água; %d de %d com 0,6 ± 0,05 m, %d mais rasas)",
			#streamCols,
			dry,
			near06,
			#depths,
			shallow
		)
	)
	assert(water > 50, "sem água no riacho")
	assert(dry == 0, dry .. " colunas do leito sem água")
	assert(overflow <= water * 0.05, "água acima da margem")
	assert(shallow == 0, shallow .. " colunas do leito com menos de 0,55 m")
	assert(near06 >= #depths * 0.9, "fundura longe dos 0,6 m em mais de 10% do leito")
end)

-- Achado no Studio (2026-11-11): o chão do terreno furava a lâmina do arrozal em metade dos pontos
-- (o soldado andava no capim e o movimento lia "seco"). Amostra de vários tabuleiros: o chão gerado
-- fica 5–15 cm abaixo do topo da lâmina dentro de cada tabuleiro, e nunca acima.
-- 2026-11-12: o terreno sai do plano da arte (Build.terrain -> ArtPlan.column), com o dique em
-- lombada; a amostra é de tabuleiros espalhados pelo mapa (o arrozal ficou a ~15%), fora da lombada
-- do dique, da estrada e dos patamares.
test("arrozal: chão plano 5–15 cm abaixo da lâmina em todo ponto amostrado dos tabuleiros", function()
	local TerrainBuilder = require("../../src/ServerStorage/VT65Build/TerrainBuilder") :: any
	local Site = require("../../src/ServerStorage/VT65Build/Site") :: any
	local ArtPlan = (require :: any)("../../src/ServerScriptService/Modules/ArtPlan")
	local ctx = ArtPlan.load(world, {
		features = require("../../src/ServerStorage/VT65Build/Data/Features") :: any,
		village = (require :: any)("../../src/ServerStorage/VT65Build/Data/Village"),
		roads = (require :: any)("../../src/ServerStorage/VT65Build/Data/Roads"),
		bases = (require :: any)("../../src/ServerStorage/VT65Build/Data/Bases"),
		mapConfig = MapConfig,
	})
	ArtPlan.structures(ctx, function(k: string): boolean
		return string.sub(k, 1, 9) ~= "vila_casa"
	end)
	local set = ctx.paddies
	local function plain(x: number, z: number): boolean
		local h = world:heightAt(x, z)
		return Site.dike(ctx.site, x, z, h) == nil
			and Site.road(ctx.site, x, z) == nil
			and select(1, Site.pad(ctx.site, x, z)) == nil
	end
	-- topo do chão de cada coluna de voxels gerada (centro da coluna)
	local tops: { [number]: number } = {}
	local function key(x: number, z: number): number
		return math.floor(x / 4) * 100000 + math.floor(z / 4)
	end
	local mock = {}
	function mock.WriteVoxels(_, region: any, _res: number, mats: any, occs: any)
		local size = region.Size
		local sx, sy, sz = size.X / 4, size.Y / 4, size.Z / 4
		local minP = region.CFrame.Position - size / 2
		for ix = 1, sx do
			for iz = 1, sz do
				local top = -math.huge
				for iy = 1, sy do
					local m, o = mats[ix][iy][iz], occs[ix][iy][iz]
					if o > 0 and m ~= roblox.Enum.Material.Water and m ~= roblox.Enum.Material.Air then
						top = math.max(top, minP.Y + (iy - 1) * 4 + o * 4)
					end
				end
				tops[key(minP.X + (ix - 0.5) * 4, minP.Z + (iz - 0.5) * 4)] = top
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
	local sampled, inRange, above, deepest, sheets = 0, 0, 0, 0, {}
	local column = function(x: number, z: number): (number, number, number, string?)
		return ArtPlan.column(ctx, x, z)
	end
	-- 8 tabuleiros espalhados pela lista
	for idx = 1, #set.list, math.max(1, #set.list // 8) do
		local p0 = set.list[idx]
		local r = math.sqrt(p0.hu * p0.hu + p0.hv * p0.hv) + 12
		table.clear(tops)
		TerrainBuilder.build(world, env, {
			only = { minX = p0.x - r, maxX = p0.x + r, minZ = p0.z - r, maxZ = p0.z + r },
			column = column,
		})
		-- pontos em grade de 1 stud dentro do tabuleiro (fora da lombada do dique, da estrada e do
		-- patamar); chão = interpolação das 4 colunas vizinhas (a superfície do terreno entre os
		-- centros dos voxels)
		local p = p0
		sheets[p] = true
		for lu = -p.hu, p.hu, 1 do
			for lv = -p.hv, p.hv, 1 do
				local x = p.x + lu * p.ca + lv * p.sa
				local z = p.z - lu * p.sa + lv * p.ca
				if not plain(x, z) or TerrainBuilder.paddyTop(set, x, z, 0) ~= p.top then
					continue -- lombada, estrada, patamar ou outro tabuleiro por cima
				end
				local fx, fz = x / 4 - 0.5, z / 4 - 0.5
				local i0, j0 = math.floor(fx), math.floor(fz)
				local tx, tz = fx - i0, fz - j0
				local function t(i: number, j: number): number?
					return tops[key(i * 4 + 2, j * 4 + 2)]
				end
				local a00, a10, a01, a11 = t(i0, j0), t(i0 + 1, j0), t(i0, j0 + 1), t(i0 + 1, j0 + 1)
				-- as quatro colunas vizinhas também fora da lombada (a superfície interpola entre elas)
				local clean = plain(i0 * 4 + 2, j0 * 4 + 2)
					and plain(i0 * 4 + 6, j0 * 4 + 2)
					and plain(i0 * 4 + 2, j0 * 4 + 6)
					and plain(i0 * 4 + 6, j0 * 4 + 6)
				if clean and a00 and a10 and a01 and a11 then
					local ground = (a00 * (1 - tx) + a10 * tx) * (1 - tz) + (a01 * (1 - tx) + a11 * tx) * tz
					local depth = (p.top - ground) * 0.28
					sampled += 1
					if depth < 0.05 - 1e-6 then
						above += 1
					elseif depth <= 0.15 + 1e-6 then
						inRange += 1
					end
					deepest = math.max(deepest, depth)
				end
			end
		end
	end
	local nSheets = 0
	for _ in sheets do
		nSheets += 1
	end
	print(
		string.format(
			"       (%d tabuleiros, %d pontos: %.1f%% com o chão 5–15 cm abaixo da lâmina, %d acima disso; mais fundo %.2f m)",
			nSheets,
			sampled,
			100 * inRange / math.max(sampled, 1),
			above,
			deepest
		)
	)
	assert(nSheets >= 8 and sampled > 1000, "amostra pequena")
	assert(above == 0, above .. " pontos com o chão a menos de 5 cm da lâmina (ou acima dela)")
	assert(inRange >= sampled * 0.8, "chão longe dos 10 cm em mais de 20% dos pontos")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
