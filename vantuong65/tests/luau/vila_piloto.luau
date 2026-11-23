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

test("todo modelo do setor tem ID publicado", function()
	for _, lista in
		{
			VilaPiloto.POVOADO,
			VilaPiloto.PASSARELAS,
			VilaPiloto.CENA,
			VilaPiloto.PLANTAS,
			VilaPiloto.CERCAS,
			VilaPiloto.PECAS,
		}
	do
		for _, c in lista do
			assert((AssetIds.Models[c.key] or 0) > 0 or c.key == "banana" or c.key == "coconut_palm", c.key)
		end
	end
end)

test("o setor piloto é denso e variado", function()
	local casas, tipos, n = 0, {}, 0
	for _, c in VilaPiloto.POVOADO do
		if c.classe ~= "banca" then
			casas += 1
			if not tipos[c.key] then
				tipos[c.key] = true
				n += 1
			end
		end
	end
	assert(casas >= 22, casas)
	assert(n >= 18, n)
	assert(#VilaPiloto.CENA >= 50, #VilaPiloto.CENA)
	assert(#VilaPiloto.PLANTAS >= 150, #VilaPiloto.PLANTAS)
end)

test("nada fica na rua, no centro da captura nem na lagoa", function()
	for _, c in VilaPiloto.POVOADO do
		assert(math.sqrt(c.x * c.x + c.z * c.z) >= 11, c.nome)
		assert(VilaPiloto.sobConstrucao(c.x, c.z), c.nome)
		assert(VilaPiloto.lagoa(c.x, c.z) > 1, c.nome)
	end
	assert(not VilaPiloto.sobConstrucao(0, 0, 7), "centro livre")
	for _, lista in { VilaPiloto.CENA, VilaPiloto.PLANTAS } do
		for _, c in lista do
			assert(VilaPiloto.noSetor(c.x, c.z, 0.5), c.key)
			assert(not VilaPiloto.sobConstrucao(c.x, c.z, 0.05), c.key)
			assert(VilaPiloto.lagoa(c.x, c.z) > 1, c.key)
		end
	end
end)

test("o relevo: bacia na lagoa, vala na rua, plano sob a casa e nada fora do setor", function()
	local l = VilaPiloto.LAGOA
	local dh, agua = VilaPiloto.relevo(l.x, l.z, 0.5, 0.5, false)
	assert(dh < -1 and agua ~= nil and agua > dh, "bacia")
	assert(VilaPiloto.relevo(30, 30, 0.9, 0.9, true) == 0, "sob a construção")
	assert(VilaPiloto.relevo(80, 80, 0.9, 0.9, false) == 0, "fora do setor")
end)

test("o chão: arrozal não muda; rua é terra, margem de lagoa é lama; fora do setor fica igual", function()
	assert(VilaPiloto.solo(10, nil, 5, 0.1, 0.1, 1, false, 5) == nil)
	assert(VilaPiloto.solo(10, nil, 2, 0.9, 0.9, 1, false, 5) == nil)
	assert(VilaPiloto.solo(10, "Ground", 3, 0.3, 0.9, 1.8, false, 5) == "Ground", "rua")
	assert(VilaPiloto.solo(10, nil, 3, 0.2, 0.1, 12, false, 5) == "Grass", "quintal")
	assert(VilaPiloto.solo(10, nil, 3, 0.2, 0.1, 12, true, 5) == "Ground", "sem capim sob o piso")
	assert(VilaPiloto.solo(10, nil, 3, 0.2, 0.1, 12, false, 0.5) == "Mud", "fundo da lagoa")
	assert(VilaPiloto.solo(500, "Ground", 3, 0.9, 0.9, 1, false, 5) == "Ground")
end)

test("os trechos afundados são rasos e ficam na rua", function()
	assert(#VilaPiloto.POCAS >= 5, "poças")
	for _, q in VilaPiloto.POCAS do
		local dh, agua = VilaPiloto.relevo(q.x, q.z, 0.5, 0.5, false)
		assert(dh < -0.1 and agua == nil, "rasa e sem água")
		assert(VilaPiloto.distRua(q.x, q.z) < 3, "na rua")
		assert(not VilaPiloto.sobConstrucao(q.x, q.z), "fora das casas")
	end
end)

test("a beira da rua tem capim e pedras, fora das casas", function()
	local pontos = VilaPiloto.bordaPontos()
	assert(#pontos >= 60, #pontos)
	for _, q in pontos do
		assert((AssetIds.Models[q.key] or 0) > 0, q.key)
		assert(VilaPiloto.noSetor(q.x, q.z))
		assert(not VilaPiloto.sobConstrucao(q.x, q.z, 0.25))
	end
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
	assert(n >= 20, n)
end)

test("o capim parado fica nos quintais, fora das ruas e das casas", function()
	assert((AssetIds.Models.ret_vila_capim or 0) > 0, "modelo publicado")
	local pontos = VilaPiloto.capimPontos()
	assert(#pontos >= 120, #pontos)
	for _, q in pontos do
		assert(VilaPiloto.noSetor(q.x, q.z))
		assert(VilaPiloto.distRua(q.x, q.z) > 3.9)
		assert(not VilaPiloto.sobConstrucao(q.x, q.z))
	end
	assert(VilaPiloto.capimPontos()[1].x == pontos[1].x, "sempre nos mesmos lugares")
end)

local _ = serde
print(string.format("%d ok, %d falhas", ok, falhas))
if falhas > 0 then
	error("falhou")
end
