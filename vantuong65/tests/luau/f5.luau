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
	-- D-123: quantos setores o mapa tiver (3 no mapa de 700 m)
	local nS = #(require("../../src/ReplicatedStorage/Shared/MapConfig") :: any).Sectors
	for s = 1, nS do
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
	assert(#a == #b and #a > 1500, "plano com " .. #a .. " plantas") -- D-114: mapa de 500 m
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
			assert(d >= Vegetation.US_BASE_CLEAR_M - 3, string.format("%s a %.0f m do QG US", it.key, d))
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
	-- na área e ~600 na cortina de fora (eram ~45 mil e ~2,8 mil no de 2 x 2 km). D-114 (500 x 500 m):
	-- ~1/4 da área, ~2,2 mil na área e ~350 na cortina
	assert(inside > 1500 and border > 150, string.format("dentro %d, cortina %d", inside, border))
	-- D-114: no mapa de 500 m a vila e as clareiras são uma parte maior da área e o jitter de meia célula
	-- leva mais plantas da borda para dentro delas (3,2%; eram < 3% no de 1 km)
	assert(paddy / inside < 0.04, string.format("%.1f%% das plantas na lavoura/clareira", 100 * paddy / inside))
	print(string.format("       %d plantas: %d na área, %d na cortina de fora", #a, inside, border))
	-- D-127: com metade dos arbustos, o resto da mata fica igual planta por planta (o descarte vem
	-- depois dos sorteios) e sobra perto da metade dos arbustos
	local keep = Vegetation.SHRUB_KEEP
	Vegetation.SHRUB_KEEP = 1
	local full = plan()
	Vegetation.SHRUB_KEEP = keep
	local others, shrubsA, shrubsFull = {}, 0, 0
	for _, it in full do
		if it.key == "shrub" then
			shrubsFull += 1
		else
			table.insert(others, it)
		end
	end
	local j = 0
	for _, it in a do
		if it.key == "shrub" then
			shrubsA += 1
		else
			j += 1
			local o = others[j]
			assert(o and o.key == it.key and o.x == it.x and o.z == it.z, "a mata mudou além dos arbustos")
		end
	end
	assert(j == #others, "a mata mudou além dos arbustos")
	local frac = shrubsA / math.max(shrubsFull, 1)
	assert(frac > 0.4 and frac < 0.6, string.format("ficaram %.0f%% dos arbustos", 100 * frac))
	print(string.format("       arbustos: %d de %d (%.0f%%)", shrubsA, shrubsFull, 100 * frac))
end)

test("D-153: longe das estradas e dos objetivos, bambu, capim-elefante e bananeira afinam; o resto igual", function()
	local M = 0.28
	local Vegetation = require("../../src/ServerScriptService/Modules/Vegetation")
	local Rng = require("../../src/ReplicatedStorage/Shared/Rng") :: any
	local WorldData = require("../../src/ServerStorage/VT65Build/WorldData")
	local Grid = require("../../src/ServerStorage/VT65Build/Data/Grid") :: any
	local MapConfig = require("../../src/ReplicatedStorage/Shared/MapConfig") :: any
	local Features = require("../../src/ServerStorage/VT65Build/Data/Features") :: any
	local Roads = require("../../src/ServerStorage/VT65Build/Data/Roads") :: any
	local Landscape = require("../../src/ServerStorage/VT65Build/Landscape")
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
	local paths = Vegetation.roadSegments(Roads)
	local focus = Vegetation.focusCircles(MapConfig)
	local dense = Vegetation.denseCircles(MapConfig)
	assert(#paths > 100 and #focus >= 7, string.format("%d trechos de estrada, %d pontos", #paths, #focus))
	local function plan(withPaths: boolean)
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
			dense = dense,
			paths = if withPaths then paths else nil,
			focus = if withPaths then focus else nil,
			seed = 1965,
			rng = Rng.new(7),
		})
	end
	local full, thin = plan(false), plan(true)
	local F = Vegetation.FAR
	local function dist(x: number, z: number): (number, number)
		local best = math.huge
		for _, s in paths do
			local dx, dz = s.x2 - s.x1, s.z2 - s.z1
			local L2 = dx * dx + dz * dz
			local t = if L2 > 0 then math.clamp(((x - s.x1) * dx + (z - s.z1) * dz) / L2, 0, 1) else 0
			best = math.min(best, (s.x1 + t * dx - x) ^ 2 + (s.z1 + t * dz - z) ^ 2)
		end
		local near = math.huge
		for _, c in focus do
			near = math.min(near, math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2))
		end
		return math.sqrt(best) * M, near * M
	end
	-- o plano afinado é o completo sem algumas plantas das três espécies, na mesma ordem
	local j, cut, farAll, farKept = 1, 0, 0, 0
	for _, it in full do
		local t = thin[j]
		local same = t and t.key == it.key and t.x == it.x and t.z == it.z
		local dPath, dFocus = math.huge, math.huge
		if F.keys[it.key] then
			dPath, dFocus = dist(it.x, it.z)
		end
		if same then
			j += 1
		else
			cut += 1
			assert(F.keys[it.key], it.key .. " sumiu (só bambu, capim-elefante e bananeira afinam)")
			assert(
				dPath > F.pathM and dFocus > F.focusM,
				string.format("%s cortado a %.0f m da estrada e %.0f m de um objetivo", it.key, dPath, dFocus)
			)
		end
		local B = MapConfig.Bounds
		local inside = it.x >= B.minX and it.x <= B.maxX and it.z >= B.minZ and it.z <= B.maxZ
		if F.keys[it.key] and inside and dPath > F.pathM + F.rampM and dFocus > F.focusM + F.rampM then
			local isDense = false
			for _, c in dense do
				if math.sqrt((it.x - c.x) ^ 2 + (it.z - c.z) ^ 2) < c.r * 1.5 then
					isDense = true
				end
			end
			if not isDense then
				farAll += 1
				if same then
					farKept += 1
				end
			end
		end
	end
	assert(j == #thin + 1, "o plano afinado tem planta que o completo não tem")
	local frac = farKept / math.max(farAll, 1)
	assert(farAll > 100 and frac > 0.35 and frac < 0.65, string.format("longe: ficaram %d de %d", farKept, farAll))
	print(string.format("       %d plantas a menos; longe de tudo ficaram %d de %d", cut, farKept, farAll))
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

test("tronco que para a bala (D-151): toda árvore da mata tem tronco medido e a peça cai no cilindro", function()
	local M = 0.28
	local TreeTrunks = require("../../src/ServerScriptService/Modules/TreeTrunks") :: any
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox") :: any
	local TrunkProxy = luau.load(
		fs.readFile("src/ServerScriptService/Modules/TrunkProxy.luau"),
		{ debugName = "TrunkProxy", environment = { Vector3 = roblox.Vector3, CFrame = roblox.CFrame } }
	)() :: any
	-- as árvores que a mata põe (Vegetation): as prontas do Poly Haven e o coqueiro
	local src = fs.readFile("src/ServerScriptService/Modules/Vegetation.luau")
	local keys: { [string]: boolean } = { coconut_palm = true }
	for k in string.gmatch(src, 'key = "(ph_[%w_]+)"') do
		keys[k] = true
	end
	local n = 0
	for k in keys do
		local cyls = TreeTrunks[k]
		assert(cyls and #cyls >= 1, k .. ": árvore sem tronco medido (rode tools/troncos.py)")
		local low = math.huge
		for i, c in cyls do
			assert(c.r > 0.02 / M and c.r < 1.2 / M, string.format("%s[%d]: raio %.2f studs", k, i, c.r))
			low = math.min(low, c.a[2], c.b[2])
			for _, scale in { 1, 2.5 } do
				local cf, size = TrunkProxy.frame(c, scale)
				local a = roblox.Vector3.new(c.a[1], c.a[2], c.a[3]) * scale
				local b = roblox.Vector3.new(c.b[1], c.b[2], c.b[3]) * scale
				-- as pontas do eixo X da peça são as pontas do cilindro; a espessura é o diâmetro
				local pa = cf * roblox.Vector3.new(-size.X / 2, 0, 0)
				local pb = cf * roblox.Vector3.new(size.X / 2, 0, 0)
				assert((pa - a).Magnitude < 1e-3 and (pb - b).Magnitude < 1e-3, k .. ": eixo fora do cilindro")
				assert(math.abs(size.Y - 2 * c.r * scale) < 1e-4 and size.Y == size.Z, k .. ": espessura errada")
				-- nada abaixo do pé: a caixa da peça não desce do pivô (o assentamento usa a caixa)
				local ux = (b - a).Unit
				local drop = math.min(a.Y, b.Y) - c.r * scale * math.sqrt(math.max(0, 1 - ux.Y * ux.Y))
				assert(drop > -0.02, string.format("%s[%d]: a peça desce %.2f studs abaixo do pé", k, i, -drop))
			end
			n += 1
		end
		-- o tronco nasce no chão (até 0,3 m acima do pé, na escala 1)
		assert(low <= 0.3 / M, string.format("%s: tronco começa a %.2f m do pé", k, low * M))
	end
	assert(TrunkProxy.isProxy("Tronco_2") and not TrunkProxy.isProxy("Madeira0_0"), "nome da peça do tronco")
	print(string.format("       %d cilindros nas árvores da mata", n))
end)

test("cerca de bambu no teto da vegetação (D-152): era 1/4 dos triângulos da vista da base dos EUA", function()
	assert(ArtBudget.TRIS.bamboo_fence <= 6000, "cerca com " .. ArtBudget.TRIS.bamboo_fence .. " triângulos")
	local man = serde.decode("json", fs.readFile("assets/forgegui/manifest.json")) :: any
	for _, m in man.models do
		if m.chave == "bamboo_fence" then
			assert(m.reducao_local and m.triangulos == ArtBudget.TRIS.bamboo_fence, "manifest sem a redução da cerca")
			return
		end
	end
	error("cerca fora do manifest")
end)

test("trim sheet da vila (D-159): as 10 casas sobem com as folhas comuns e o portador tem ID", function()
	local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds") :: any
	local plan = serde.decode("json", fs.readFile("assets/upload_plan.json")) :: any
	local casas, portador = 0, false
	for _, item in plan do
		local key = string.match(item.key, "^Models%.(vila_casa_%d+)$")
		if key then
			casas += 1
			-- D-249: o que sobe é a trim sem as grades (assets/janelas); a origem segue em file_limpo
			assert(
				string.find(item.file_limpo or item.file, key .. "_trim%.glb$"),
				key .. ": o plano não sobe o GLB da trim sheet"
			)
		elseif item.key == "Models.vila_trim" then
			portador = true
		end
	end
	assert(casas == 10, "esperava 10 casas no plano, veio " .. casas)
	assert(portador, "portador vila_trim fora do plano")
	assert(AssetIds.Models.vila_trim ~= 0, "portador vila_trim sem ID: as casas ficariam sem textura")
	-- o AssetLoader troca a SurfaceAppearance só dos nós Trim_<letra> e nunca no próprio portador
	local src = fs.readFile("src/ServerScriptService/Modules/AssetLoader.luau")
	assert(string.find(src, 'TRIM_KEY = "vila_trim"', 1, true), "AssetLoader sem a chave do portador")
	-- D-255: o setor piloto tem um segundo portador, com a mesma grade
	assert(
		string.find(src, "if key ~= AssetLoader.TRIM_KEY and key ~= AssetLoader.TRIM_POV then", 1, true),
		"o portador não pode receber a folha"
	)
	if not haveBlender then
		return
	end
	for k = 1, 10 do
		local key = string.format("vila_casa_%02d", k)
		local m = serde.decode("json", fs.readFile("assets/blender/" .. key .. "/metricas.json")) :: any
		assert(m.trim and #m.trim.folhas >= 2, key .. ": sem a conversão (tools/blender/vila_trim.py)")
		assert(string.find(m.novo.arquivo, "_trim%.glb$"), key .. ": metricas.json não aponta para o GLB da trim")
		local trims = 0
		for _, n in m.novo.nos do
			assert(n.atlas ~= "Casa", key .. ": nó " .. n.no .. " ainda no atlas Casa")
			if n.atlas == "trim" then
				trims += 1
				assert(string.match(n.no, "^Trim_[MWOP]$"), key .. ": nó de trim com nome fora do padrão: " .. n.no)
			end
		end
		assert(trims == #m.trim.folhas, key .. ": nós Trim_ e folhas não batem")
	end
end)

-- D-168: a construção de peças (pagode, casa comunal, serraria...) também pode ser arte fixa do SLIM
test("arte fixa (D-155, D-168): o plano acha a construção de peças fixa pelo pivô da base", function()
	local function semCR(s: string): string
		return (string.gsub(s, "\r", ""))
	end
	local ml = semCR(fs.readFile("src/ServerScriptService/Modules/MapLife.luau"))
	local vp = string.match(ml, "function MapLife%.villagePart%(.-\nend\n")
	assert(vp, "MapLife.villagePart não achado")
	assert(string.find(vp, "m.WorldPivot = cf", 1, true), "o pivô da construção tem que ser o centro da base")
	local al = semCR(fs.readFile("src/ServerScriptService/Modules/AssetLoader.luau"))
	local pi = string.match(al, "function AssetLoader%.placeItem%(.-\nend\n")
	assert(pi, "AssetLoader.placeItem não achado")
	local a = string.find(pi, 'AssetLoader.staticModel(parent, "Vila_" .. kind, cf.Position)', 1, true)
	local b = string.find(pi, "MapLife.villagePart(kind", 1, true)
	assert(a and b and a < b, "a cópia fixa tem que ser procurada antes de montar a construção")
	-- o copiador escreve as peças comuns (linha B) com o CFrame inteiro
	local cp = fs.readFile("tools/estatico_copiar.luau")
	assert(string.find(cp, "p.CFrame:GetComponents()", 1, true), "o copiador grava o CFrame inteiro do bloco")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
