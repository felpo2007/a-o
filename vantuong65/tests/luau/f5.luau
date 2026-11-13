--!strict
-- Testes da F5 (Lune): fusão de diques (D-14) e invariantes de orçamento.
-- Uso: lune run tests/luau/f5.luau
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local FeatureBuilder = require("../../src/ServerStorage/VT65Build/FeatureBuilder")
local Features = require("../../src/ServerStorage/VT65Build/Data/Features") :: any
local ArtBudget = require("../../src/ServerScriptService/Modules/ArtBudget")

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

local function totalLen(d: { number }): number
	local t = 0
	for i = 1, #d, 6 do
		t += math.sqrt((d[i + 2] - d[i]) ^ 2 + (d[i + 3] - d[i + 1]) ^ 2)
	end
	return t
end

test("fusão: corrente reta com o mesmo topo vira um dique; comprimento preservado", function()
	local d = { 0, 0, 10, 0, 5, 4, 10, 0, 20, 0, 5.2, 3, 20, 0, 35, 0, 5.1, 4.5 }
	local m = FeatureBuilder.mergeDikes(d)
	assert(#m == 6, "esperava 1 dique, veio " .. #m // 6)
	assert(math.abs(totalLen(m) - 35) < 1e-6)
	assert(m[5] == 5.2 and m[6] == 3, "maior topo e menor base")
end)

test("fusão: não junta topo diferente, ângulo reto nem trechos separados", function()
	local d = {
		0,
		0,
		10,
		0,
		5,
		4, -- base
		10,
		0,
		20,
		0,
		6,
		4, -- topo 1 stud acima
		0,
		0,
		0,
		10,
		5,
		4, -- perpendicular
		30,
		0,
		40,
		0,
		5,
		4, -- separado (fresta de 10)
	}
	local m = FeatureBuilder.mergeDikes(d)
	assert(#m // 6 == 4, "nenhuma fusão esperada, veio " .. #m // 6)
end)

-- remove duplicatas exatas (mesmas pontas, em qualquer ordem) para comparar comprimentos
local function dedupe(d: { number }): { number }
	local seen: { [string]: boolean } = {}
	local out = {}
	for i = 1, #d, 6 do
		local a = string.format("%.2f,%.2f", d[i], d[i + 1])
		local b = string.format("%.2f,%.2f", d[i + 2], d[i + 3])
		local k = if a < b then a .. "|" .. b else b .. "|" .. a
		if not seen[k] then
			seen[k] = true
			for o = 0, 5 do
				table.insert(out, d[i + o])
			end
		end
	end
	return out
end

test("mapa real: menos diques, comprimento preservado (±0,1%)", function()
	local d = Features.dikes
	local m = FeatureBuilder.mergeDikes(d)
	local before, after = #d // 6, #m // 6
	local l0, l1 = totalLen(dedupe(d)), totalLen(m)
	print(string.format("       duplicatas exatas no dado: %d", before - #dedupe(d) // 6))
	print(
		string.format(
			"       diques %d -> %d (-%.1f%%); comprimento %.0f -> %.0f studs",
			before,
			after,
			100 * (1 - after / before),
			l0,
			l1
		)
	)
	assert(after < before)
	assert(math.abs(l1 - l0) / l0 < 0.001, string.format("comprimento mudou %.3f%%", 100 * (l1 - l0) / l0))
end)

-- orçamento de arte (Parte 2): os números do ArtBudget são os medidos no manifest do ForgeGUI ou,
-- para os modelos do Blender (refeitos e novos, assets/blender/<chave>/metricas.json), os do novo
local manifest = serde.decode("json", fs.readFile("assets/forgegui/manifest.json")) :: any
local robloxIds = serde.decode("json", fs.readFile("assets/roblox_ids.json")) :: any
local function blenderTris(key: string): number?
	local path = "assets/blender/" .. key .. "/metricas.json"
	if not fs.isFile(path) then
		return nil
	end
	local m = serde.decode("json", fs.readFile(path)) :: any
	return m.novo and m.novo.triangulos
end
-- refeito publicado: o ID antigo do ForgeGUI fica guardado como <chave>_forge (commit 6ea6bfd) ou,
-- no bambu sem o disco da base (2026-11-12), como <chave>_disco
local function replacedByBlender(key: string): boolean
	return robloxIds["Models." .. key .. "_forge"] ~= nil or robloxIds["Models." .. key .. "_disco"] ~= nil
end
-- assets/blender é gerado (tools/blender) e fica fora do Git: sem a pasta, os números do Blender
-- não são conferidos (o resto do orçamento continua)
local haveBlender = fs.isDir("assets/blender")

test("orçamento: cada modelo do manifest tem tipo e o número medido", function()
	local n, refeitos = 0, 0
	for _, m in manifest.models do
		local key = m.chave
		if key then
			n += 1
			assert(ArtBudget.KIND[key], key .. " sem tipo (veg/prop/hero)")
			local want = m.triangulos
			if replacedByBlender(key) then
				want = if haveBlender then blenderTris(key) else nil
				refeitos += 1
			end
			if want ~= nil or not replacedByBlender(key) then
				assert(
					ArtBudget.TRIS[key] == want,
					string.format("%s: ArtBudget %s, medido %s", key, tostring(ArtBudget.TRIS[key]), tostring(want))
				)
			else
				assert(ArtBudget.TRIS[key] ~= nil, key .. ": refeito sem número no ArtBudget")
			end
		end
	end
	assert(n >= 39, "esperava ≥ 39 modelos com chave, veio " .. n)
	print(string.format("       %d modelos; %d refeitos no Blender com o número do novo", n, refeitos))
end)

test("orçamento: objeto novo do Blender no ArtBudget tem o número do metricas.json", function()
	if not haveBlender then
		print("       sem assets/blender (gerado, fora do Git): pulado")
		return
	end
	local n = 0
	for key, tris in ArtBudget.TRIS do
		local b = blenderTris(key)
		local inManifest = false
		for _, m in manifest.models do
			if m.chave == key then
				inManifest = true
			end
		end
		if b and not inManifest then
			n += 1
			assert(tris == b, string.format("%s: ArtBudget %d, metricas %d", key, tris, b))
			assert(ArtBudget.KIND[key], key .. " sem tipo")
		end
	end
	assert(n >= 6, "esperava os 6 objetos da vila e dos túneis, veio " .. n)
end)

test("orçamento: acima da meta só com exceção registrada, e nenhuma exceção velha", function()
	local over = 0
	for key, _ in ArtBudget.TRIS do
		local within = ArtBudget.within(key)
		if not within then
			over += 1
			assert(ArtBudget.EXCEPTIONS[key], key .. " acima da meta sem exceção registrada")
		else
			assert(not ArtBudget.EXCEPTIONS[key], key .. " já cabe na meta: tire a exceção")
		end
	end
	print(string.format("       %d modelos acima da meta, todos com motivo registrado", over))
end)

test("orçamento: o que o AssetLoader coloca tem número medido; casas só na meta", function()
	local src = fs.readFile("src/ServerScriptService/Modules/AssetLoader.luau")
	local placed: { [string]: boolean } = {}
	-- toda chave de modelo citada no AssetLoader (place direto ou variável das sebes)
	for key in string.gmatch(src, '"([%w_]+)"') do
		if ArtBudget.KIND[key] then
			placed[key] = true
		end
	end
	for key in string.gmatch(fs.readFile("src/ServerScriptService/Modules/LogisticsService.luau"), 'place%("([%w_]+)"') do
		placed[key] = true
	end
	-- objetos do Blender que o MapLife põe pelo AssetLoader.placeAt (vila e túneis)
	for key in string.gmatch(fs.readFile("src/ServerScriptService/Modules/MapLife.luau"), '"([%w_]+)"') do
		if ArtBudget.KIND[key] then
			placed[key] = true
		end
	end
	for _, key in ArtBudget.HOUSE_VARIANTS do
		assert(ArtBudget.within(key), "casa acima da meta no sorteio: " .. key)
		placed[key] = true
	end
	local n = 0
	for key in placed do
		n += 1
		assert(ArtBudget.TRIS[key], key .. " é colocado sem número medido")
	end
	assert(n >= 15, "esperava ≥ 15 chaves colocadas, veio " .. n)
end)

test("desbaste das sebes: fração entre 0 e 1 e que fecha o teto", function()
	assert(ArtBudget.factor(0, 0) == 1, "sem demanda: tudo")
	assert(ArtBudget.factor(ArtBudget.SECTOR_MAX, 1000) == 0, "teto cheio: nada")
	assert(ArtBudget.factor(ArtBudget.SECTOR_MAX + 5, 1000) == 0, "acima do teto: nada (nunca negativo)")
	assert(ArtBudget.factor(0, 100, 1000) == 1, "cabe tudo")
	assert(math.abs(ArtBudget.factor(500, 2000, 1000) - 0.25) < 1e-12)
	assert(ArtBudget.hedgeClumps(1, true) == 1 and ArtBudget.hedgeClumps(21, true) == 3)
	assert(ArtBudget.hedgeClumps(9, false) == 3)
end)

test("estimativa do mapa: nenhum setor passa do teto; sebes desbastadas por igual", function()
	local estimate = require("../../tools/ArtEstimate")
	local r = estimate()
	for s = 1, 5 do
		local x = r.sectors[s]
		assert(x, "setor " .. s .. " sem arte")
		assert(x.tris <= ArtBudget.SECTOR_MAX + 1, string.format("setor %d: %.0f triângulos", s, x.tris))
		assert(x.factor > 0, "setor " .. s .. " sem nenhuma touceira de sebe")
		print(string.format("       setor %d: %.0f instâncias, %.0f%% das touceiras", s, x.count, 100 * x.factor))
	end
end)

test("arte publicada: toda arma com modelo tem pontos coerentes (WeaponArt, D-58)", function()
	local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds") :: any
	local Weapons = require("../../src/ReplicatedStorage/Shared/Weapons") :: any
	-- WeaponArt usa o Vector3 global do Roblox: carrega com ambiente próprio
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox")
	local WeaponArt = luau.load(
		fs.readFile("src/ReplicatedStorage/Shared/WeaponArt.luau"),
		{ debugName = "WeaponArt", environment = { Vector3 = roblox.Vector3 } }
	)() :: any
	local M = 0.28
	local AXIS = {
		["-Z"] = roblox.Vector3.new(0, 0, -1),
		["+Z"] = roblox.Vector3.new(0, 0, 1),
		["-X"] = roblox.Vector3.new(-1, 0, 0),
		["+X"] = roblox.Vector3.new(1, 0, 0),
	}
	local n = 0
	for id, assetId in AssetIds.Models do
		if Weapons.byId[id] and assetId ~= 0 then
			n += 1
			local a = WeaponArt[id]
			assert(a, id .. ": arma publicada sem pontos em WeaponArt (rode tools/weapon_landmarks.py)")
			local ax = AXIS[a.forward]
			assert(ax, id .. ": frente inválida " .. tostring(a.forward))
			assert(math.abs(a.yaw) < math.rad(45), id .. ": giro extra grande demais")
			-- direção da boca no espaço da malha (com o giro de modelo torto)
			local f = roblox.CFrame.Angles(0, -a.yaw, 0) * ax
			local function s(v: any): number -- posição ao longo do cano (maior = mais à frente)
				return v:Dot(f)
			end
			local L = a.lengthM / M
			assert(s(a.muzzle) >= s(a.front) - 0.02, id .. ": a massa está à frente da boca")
			local mg = s(a.muzzle) - s(a.grip)
			assert(mg > 0.3 * L and mg < L, string.format("%s: boca a %.2f do punho (L %.2f)", id, mg, L))
			assert(s(a.front) > s(a.sight), id .. ": massa atrás da alça")
			assert(s(a.sight) >= s(a.grip) - 0.15 / M, id .. ": olho atrás demais do punho")
			assert(a.sight.Y >= a.muzzle.Y, id .. ": linha de visada abaixo do cano")
			assert(a.eyeM > 0 and a.eyeM <= 0.7, id .. ": olho fora de 0–0,7 m")
			-- alcance do braço (D-59): o apoio a no máximo 0,26 m do punho
			local d =
				math.sqrt((a.support.X - a.grip.X) ^ 2 + (a.support.Y - a.grip.Y) ^ 2 + (a.support.Z - a.grip.Z) ^ 2)
			assert(d * M <= 0.26, string.format("%s: apoio a %.2f m do punho", id, d * M))
		end
	end
	-- 9 do ForgeGUI; com os IDs da M70 e da Mosin (Blender, 2026-11-12) publicados, 11
	assert(n >= 9, "esperava ao menos 9 armas publicadas, vieram " .. n)
end)

test("mata (D-64/65): determinística, zonas livres, lavoura e clareira abertas, cortina fora", function()
	local M = 0.28
	local Vegetation = require("../../src/ServerScriptService/Modules/Vegetation")
	local Rng = require("../../src/ReplicatedStorage/Shared/Rng") :: any
	local WorldData = require("../../src/ServerStorage/VT65Build/WorldData")
	local Grid = require("../../src/ServerStorage/VT65Build/Data/Grid") :: any
	local MapConfig = require("../../src/ReplicatedStorage/Shared/MapConfig") :: any
	local Features = require("../../src/ServerStorage/VT65Build/Data/Features") :: any
	local chunks = {}
	for _, name in Grid.heightChunks do
		table.insert(chunks, (require :: any)("../../src/ServerStorage/VT65Build/Data/" .. name))
	end
	local world = WorldData.load(Grid, chunks)
	local houses = {}
	for i = 1, #Features.houses, 4 do
		table.insert(houses, Features.houses[i])
		table.insert(houses, Features.houses[i + 1])
	end
	local Landscape = require("../../src/ServerStorage/VT65Build/Landscape")
	local land = Landscape.new(world, MapConfig, houses)
	local function plan()
		return Vegetation.plan({
			classAt = function(x: number, z: number): number
				return world:classAt(x, z)
			end,
			kindAt = function(x: number, z: number): number
				return land:kindAt(x, z)
			end,
			bounds = MapConfig.Bounds,
			cell = Grid.cellStuds,
			exclude = Vegetation.exclusions(MapConfig, houses, {}),
			corridors = { { x1 = 0, z1 = 0, x2 = 500, z2 = 0, w = 20 } },
			seed = 1965,
			rng = Rng.new(7),
		})
	end
	local a, b = plan(), plan()
	assert(#a == #b and #a > 5000, "plano com " .. #a .. " plantas")
	for i = 1, #a, 97 do
		assert(a[i].key == b[i].key and a[i].x == b[i].x and a[i].z == b[i].z, "não determinístico")
	end
	local B = MapConfig.Bounds
	local inside, border, paddy = 0, 0, 0
	for _, it in a do
		local isIn = it.x >= B.minX and it.x <= B.maxX and it.z >= B.minZ and it.z <= B.maxZ
		if isIn then
			inside += 1
			-- 2026-11-13: só o QG dos EUA abre clareira (o acampamento do VC fica sob a mata; o plano da
			-- arte abre as pegadas e os pontos de nascer)
			local hq = MapConfig.HQ.US
			local d = math.sqrt((it.x - hq.x) ^ 2 + (it.z - hq.z) ^ 2) * M
			assert(d >= 150 - 3, string.format("%s a %.0f m do QG US", it.key, d))
			for i = 1, #houses, 2 do
				local d = math.sqrt((it.x - houses[i]) ^ 2 + (it.z - houses[i + 1]) ^ 2) * M
				assert(d >= 6.5 - 0.01, string.format("%s dentro de casa (%.1f m)", it.key, d))
			end
			-- o jitter (meia célula) pode levar a planta para a célula vizinha da lavoura ou clareira
			local kind = land:kindAt(it.x, it.z)
			if kind == Landscape.FARM or kind == Landscape.CLEAR then
				paddy += 1
			end
		else
			border += 1
		end
	end
	-- D-65: mata fechada; lavoura e clareira abertas. Mapa de 1 x 1 km (2026-11-11): ~8,3 mil plantas
	-- na área e ~600 na cortina de fora (eram ~45 mil e ~2,8 mil no de 2 x 2 km)
	assert(inside > 6000 and border > 300, string.format("dentro %d, cortina %d", inside, border))
	assert(paddy / inside < 0.03, string.format("%.1f%% das plantas na lavoura/clareira", 100 * paddy / inside))
	print(string.format("       %d plantas: %d na área, %d na cortina de fora", #a, inside, border))
end)

test("clareira de nascimento: nenhuma planta da mata a até 15 m de QG ou reunião, visada aberta", function()
	local M = 0.28
	local Vegetation = require("../../src/ServerScriptService/Modules/Vegetation")
	local Front = require("../../src/ReplicatedStorage/Shared/Front") :: any
	local SpawnRules = require("../../src/ReplicatedStorage/Shared/SpawnRules") :: any
	local Geometry = require("../../src/ReplicatedStorage/Shared/Geometry") :: any
	local Rng = require("../../src/ReplicatedStorage/Shared/Rng") :: any
	local WorldData = require("../../src/ServerStorage/VT65Build/WorldData")
	local Landscape = require("../../src/ServerStorage/VT65Build/Landscape")
	local Grid = require("../../src/ServerStorage/VT65Build/Data/Grid") :: any
	local MapConfig = require("../../src/ReplicatedStorage/Shared/MapConfig") :: any
	local chunks = {}
	for _, name in Grid.heightChunks do
		table.insert(chunks, (require :: any)("../../src/ServerStorage/VT65Build/Data/" .. name))
	end
	local world = WorldData.load(Grid, chunks)
	local houses = {}
	for i = 1, #Features.houses, 4 do
		table.insert(houses, Features.houses[i])
		table.insert(houses, Features.houses[i + 1])
	end
	local land = Landscape.new(world, MapConfig, houses)
	-- os mesmos pontos e a mesma clareira do AssetLoader
	local spots = Front.spawnSpots(MapConfig, M, function(x: number, z: number): number?
		return Geometry.sectorAt(MapConfig.Sectors, x, z)
	end, SpawnRules.rallyPosition, Front.C.rallyInsetM)
	local circles, lanes = Vegetation.spawnClearings(spots)
	local exclude = Vegetation.exclusions(MapConfig, houses, {})
	for _, c in circles do
		table.insert(exclude, c)
	end
	local plan = Vegetation.plan({
		classAt = function(x: number, z: number): number
			return world:classAt(x, z)
		end,
		kindAt = function(x: number, z: number): number
			return land:kindAt(x, z)
		end,
		bounds = MapConfig.Bounds,
		cell = Grid.cellStuds,
		exclude = exclude,
		corridors = lanes,
		seed = 1965,
		rng = Rng.new(19650818 + 64),
	})
	local B = MapConfig.Bounds
	local inLane = 0
	for _, it in plan do
		if it.x >= B.minX and it.x <= B.maxX and it.z >= B.minZ and it.z <= B.maxZ then
			for _, s in spots do
				local d = math.sqrt((it.x - s.x) ^ 2 + (it.z - s.z) ^ 2) * M
				assert(d >= Vegetation.SPAWN_CLEAR_M - 0.01, string.format("%s a %.1f m de um %s", it.key, d, s.kind))
			end
			for _, l in lanes do
				local dx, dz = l.x2 - l.x1, l.z2 - l.z1
				local t = math.clamp(((it.x - l.x1) * dx + (it.z - l.z1) * dz) / (dx * dx + dz * dz), 0, 1)
				local qx, qz = l.x1 + t * dx - it.x, l.z1 + t * dz - it.z
				if qx * qx + qz * qz < l.w * l.w then
					inLane += 1
				end
			end
		end
	end
	assert(inLane == 0, inLane .. " plantas na visada de quem nasce")
	print(string.format("       %d pontos de nascimento com clareira de %d m", #spots, Vegetation.SPAWN_CLEAR_M))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
