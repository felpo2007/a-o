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

-- orçamento de arte (Parte 2): os números do ArtBudget são os medidos no manifest
local manifest = serde.decode("json", fs.readFile("assets/forgegui/manifest.json")) :: any

test("orçamento: cada modelo do manifest tem tipo e o número medido", function()
	local n = 0
	for _, m in manifest.models do
		local key = m.chave
		if key then
			n += 1
			assert(ArtBudget.KIND[key], key .. " sem tipo (veg/prop/hero)")
			assert(
				ArtBudget.TRIS[key] == m.triangulos,
				string.format(
					"%s: ArtBudget %s, manifest %s",
					key,
					tostring(ArtBudget.TRIS[key]),
					tostring(m.triangulos)
				)
			)
		end
	end
	assert(n >= 39, "esperava ≥ 39 modelos com chave, veio " .. n)
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

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
