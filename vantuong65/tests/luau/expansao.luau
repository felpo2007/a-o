--!strict
-- D-232: expansão da Vila e do Arrozal. Uso: lune run tests/luau/expansao.luau
-- O que já existia não muda, a expansão sai por um interruptor, o plano é repetível e cada peça nova
-- fica fora de captura, nascer, estrada, lâmina, dique e riacho (tools/expansao_check.luau).
local process = require("@lune/process")

local R = require :: any
local WorldData = R("../../src/ServerStorage/VT65Build/WorldData")
local Grid = R("../../src/ServerStorage/VT65Build/Data/Grid")
local Features = R("../../src/ServerStorage/VT65Build/Data/Features")
local Village = R("../../src/ServerStorage/VT65Build/Data/Village")
local Roads = R("../../src/ServerStorage/VT65Build/Data/Roads")
local Bases = R("../../src/ServerStorage/VT65Build/Data/Bases")
local MapConfig = R("../../src/ReplicatedStorage/Shared/MapConfig")
local AssetIds = R("../../src/ReplicatedStorage/Shared/AssetIds")
local ArtPlan = R("../../src/ServerScriptService/Modules/ArtPlan")
local ArtBudget = R("../../src/ServerScriptService/Modules/ArtBudget")
local Expansao = R("../../src/ServerScriptService/Modules/Expansao")
local TreeTrunks = R("../../src/ServerScriptService/Modules/TreeTrunks")

local M = 0.28
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

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, R("../../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)
local dados = { features = Features, village = Village, roads = Roads, bases = Bases, mapConfig = MapConfig }
local function has(k: string): boolean
	local id = AssetIds.Models[k]
	return type(id) == "number" and id ~= 0
end
local function plano(ligada: boolean): (any, { any }, { any })
	Expansao.LIGADA = ligada
	local ctx = ArtPlan.load(world, dados)
	local st = ArtPlan.structures(ctx, has)
	local pl = ArtPlan.plants(ctx, st, {}, has)
	Expansao.LIGADA = true
	return ctx, st, pl
end

local _, st0, pl0 = plano(false)
local ctx1, st1, pl1 = plano(true)
local _, st2, pl2 = plano(true)

local function novas(st: { any }): { any }
	local out = {}
	for _, it in st do
		if it.expansao then
			table.insert(out, it)
		end
	end
	return out
end

test("desligada, a expansão não põe nada no mapa", function()
	assert(#novas(st0) == 0, "construção nova com a expansão desligada")
	for _, p in pl0 do
		assert(string.sub(p.key, 1, 4) ~= "exp_", "planta nova com a expansão desligada: " .. p.key)
	end
end)

test("ligada, toda construção antiga fica igual e na mesma ordem", function()
	local velhas = {}
	for _, it in st1 do
		if not it.expansao then
			table.insert(velhas, it)
		end
	end
	assert(#velhas == #st0, string.format("%d antigas viraram %d", #st0, #velhas))
	for i, a in st0 do
		local b = velhas[i]
		assert(a.key == b.key and a.x == b.x and a.z == b.z and a.yaw == b.yaw, "mudou: " .. a.key)
		assert(math.abs(a.base - b.base) < 1e-6, "mudou a altura: " .. a.key)
	end
	print(string.format("       %d antigas iguais, %d novas", #st0, #novas(st1)))
end)

test("as plantas antigas só saem de onde o chão novo passou", function()
	local de1: { [string]: boolean } = {}
	for _, p in pl1 do
		de1[string.format("%s|%.3f|%.3f", p.key, p.x, p.z)] = true
	end
	local tiradas = 0
	for _, p in pl0 do
		if not de1[string.format("%s|%.3f|%.3f", p.key, p.x, p.z)] then
			tiradas += 1
			assert(ArtPlan.groundProblem(ctx1, p.x, p.z, p.hx) ~= nil, "tirada sem motivo: " .. p.key)
		end
	end
	assert(tiradas < #pl0 * 0.01, string.format("%d plantas antigas tiradas", tiradas))
	print(string.format("       %d antes, %d depois, %d tiradas", #pl0, #pl1, tiradas))
end)

test("o plano é repetível (mesmas peças e plantas nas duas passadas)", function()
	assert(#st1 == #st2 and #pl1 == #pl2, "tamanhos diferentes")
	for i, a in st1 do
		local b = st2[i]
		assert(a.key == b.key and a.x == b.x and a.z == b.z and a.base == b.base, "construção " .. i)
	end
	for i, a in pl1 do
		local b = pl2[i]
		assert(a.key == b.key and a.x == b.x and a.z == b.z and a.scale == b.scale, "planta " .. i)
	end
end)

test("só a Vila e o Arrozal têm setor, com nomes únicos", function()
	for nome, setor in Expansao.SETORES do
		assert(nome == "Vila" or nome == "Arrozais", "setor fora do pedido: " .. nome)
		local vistos: { [string]: boolean } = {}
		for _, p in setor.pecas do
			assert(not vistos[p.id], "id repetido: " .. p.id)
			vistos[p.id] = true
		end
	end
end)

test("todo modelo novo tem ID, orçamento e medida", function()
	local chaves: { [string]: boolean } = {}
	for _, setor in Expansao.SETORES do
		for _, p in setor.pecas do
			chaves[p.key] = true
		end
		for _, p in setor.plantas or {} do
			chaves[p.key] = true
		end
	end
	for _, e in Expansao.MATA do
		chaves[e.key] = true
	end
	for k in chaves do
		if string.sub(k, 1, 6) == "parts:" then
			assert(ArtPlan.PARTS_DIMS[k], k .. ": sem medida")
			continue
		end
		assert(has(k), k .. ": sem ID no AssetIds")
		if string.sub(k, 1, 4) == "exp_" then -- as reaproveitadas já têm o orçamento delas
			assert(ArtBudget.DIMS[k], k .. ": sem medida no ArtBudget")
			local kind = ArtBudget.KIND[k]
			assert(kind, k .. ": sem tipo no ArtBudget")
			assert(ArtBudget.TRIS[k] <= ArtBudget.MAX[kind], k .. ": acima do teto de triângulos")
		end
	end
end)

test("árvore nova tem tronco que para a bala e o pé enterrado no nível do modelo", function()
	for _, k in { "exp_figueira", "exp_arvore_a", "exp_arvore_b" } do
		assert(TreeTrunks[k] and #TreeTrunks[k] >= 1, k .. ": sem tronco medido")
		local s = ArtBudget.BASE_SINK[k]
		assert(s and s.frac > 0 and s.frac < 0.1, k .. ": sem BASE_SINK")
	end
end)

test("água nova só desce e o abrigo fica fora de lâmina, dique e riacho", function()
	for _, c in ctx1.site.cutList do
		assert(c.y2 <= c.y1 + 1e-6, "leito sobe: " .. tostring(c.kind))
	end
	local ctx0 = plano(false)
	for _, sp in MapConfig.Strongpoints do
		local setor = Expansao.SETORES[sp.name]
		for _, e in (if setor then setor.escavar else {}) :: { any } do
			local x, z = sp.x + e.x / M, sp.z + e.z / M
			local d = math.sqrt(e.x ^ 2 + e.z ^ 2)
			assert(d > 37, e.id .. ": escavação dentro da captura")
			local g = ArtPlan.groundProblem(ctx0, x, z, 1 / M)
			assert(g ~= "lamina" and g ~= "dique" and g ~= "riacho", e.id .. ": sobre " .. tostring(g))
		end
	end
end)

test("cada peça nova passa na conferência contra o mapa antigo", function()
	local r = process.spawn("lune", { "run", "tools/expansao_check.luau" })
	if not r.ok then
		local linhas = {}
		for l in string.gmatch(r.stdout, "[^\n]+") do
			if string.find(l, "<<", 1, true) or string.find(l, "ERRO", 1, true) then
				table.insert(linhas, l)
			end
		end
		error(table.concat(linhas, "\n") .. r.stderr)
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
process.exit(if failed == 0 then 0 else 1)
