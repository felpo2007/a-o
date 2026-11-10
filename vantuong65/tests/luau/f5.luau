--!strict
-- Testes da F5 (Lune): fusão de diques (D-14) e invariantes de orçamento.
-- Uso: lune run tests/luau/f5.luau
local process = require("@lune/process")

local FeatureBuilder = require("../../src/ServerStorage/VT65Build/FeatureBuilder")
local Features = require("../../src/ServerStorage/VT65Build/Data/Features") :: any

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

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
