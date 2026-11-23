--!nocheck
-- D-254 (prompt V5, §19): a área piloto da Vila. Dados coerentes e desligada no jogo publicado.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds")
local VilaPiloto = require("../../src/ReplicatedStorage/Shared/VilaPiloto")

local ok, falhas = 0, 0
local function test(nome: string, f: () -> ())
	local passou, erro = pcall(f)
	if passou then
		ok += 1
	else
		falhas += 1
		print("FALHA: " .. nome .. ": " .. tostring(erro))
	end
end

test("só entra no jogo publicado depois da aprovação do dono", function()
	assert(VilaPiloto.LIGADA == false)
end)

test("todo modelo da área tem ID publicado", function()
	for _, t in VilaPiloto.TROCAS do
		assert((AssetIds.Models[t.para] or 0) > 0, t.para)
	end
	for _, p in VilaPiloto.PECAS do
		assert((AssetIds.Models[p.key] or 0) > 0, p.key)
	end
end)

test("as peças ficam dentro da área e nenhuma cai no centro da captura", function()
	for _, p in VilaPiloto.PECAS do
		local d = math.sqrt(p.x * p.x + p.z * p.z)
		assert(d <= VilaPiloto.RAIO_M, p.key .. " fora da área")
		if not p.plano then
			assert(d >= 6, p.key .. " no meio do cruzamento")
		end
	end
end)

test("cada troca aponta para um lugar diferente", function()
	local vistos = {}
	for _, t in VilaPiloto.TROCAS do
		local c = string.format("%s:%.1f:%.1f", t.de, t.x, t.z)
		assert(not vistos[c], c)
		vistos[c] = true
	end
end)

test("o chão: água e arrozal não mudam; rua vira terra, sem barro em voxel; fora do raio fica igual", function()
	assert(VilaPiloto.solo(10, nil, 5, 0.1, 0.1, 1, false) == nil)
	assert(VilaPiloto.solo(10, nil, 2, 0.9, 0.9, 1, false) == nil)
	assert(VilaPiloto.solo(10, "Ground", 3, 0.3, 0.9, 1.8, false) == "Ground", "trilha de roda")
	assert(VilaPiloto.solo(10, nil, 3, 0.95, 0.95, 12, false) == "Ground", "quintal sem barro")
	assert(VilaPiloto.solo(10, "Ground", 3, 0.2, 0.1, 0.3, false) == "Ground", "meio da pista")
	assert(VilaPiloto.solo(10, nil, 3, 0.2, 0.1, 12, false) == "Grass", "quintal")
	assert(VilaPiloto.solo(10, nil, 3, 0.2, 0.1, 12, true) == "Ground", "sem capim sob o piso")
	assert(VilaPiloto.solo(500, "Ground", 3, 0.9, 0.9, 1, false) == "Ground")
end)

test("as marcas de borda suave têm imagem publicada", function()
	local n = 0
	local todas = table.clone(VilaPiloto.PECAS)
	for _, q in VilaPiloto.marcas() do
		table.insert(todas, q)
	end
	for _, p in todas do
		if p.decal then
			n += 1
			assert((AssetIds.ChaoVila[p.decal] or 0) > 0, p.decal)
		end
	end
	assert(n >= 40, n)
end)

test("o capim parado fica nos quintais, fora das ruas e das casas", function()
	assert((AssetIds.Models.ret_vila_capim or 0) > 0, "modelo publicado")
	local pontos = VilaPiloto.capimPontos()
	assert(#pontos >= 300, #pontos)
	for _, q in pontos do
		assert(math.sqrt(q.x * q.x + q.z * q.z) < VilaPiloto.RAIO_M)
		assert(VilaPiloto.distRua(q.x, q.z) > 5.4)
		assert(not VilaPiloto.sobConstrucao(q.x, q.z))
	end
	assert(VilaPiloto.capimPontos()[1].x == pontos[1].x, "sempre nos mesmos lugares")
end)

test("a área usa poucos modelos diferentes (instancing)", function()
	local chaves, total = {}, 0
	for _, t in VilaPiloto.TROCAS do
		chaves[t.para] = true
		total += 1
	end
	for _, p in VilaPiloto.PECAS do
		chaves[p.key] = true
		total += 1
	end
	local n = 0
	for _ in chaves do
		n += 1
	end
	assert(total >= n * 3, string.format("%d peças de %d modelos", total, n))
end)

local _ = serde
print(string.format("%d ok, %d falhas", ok, falhas))
if falhas > 0 then
	error("falhou")
end
