--!strict
-- Testes dos conjuntos em Game Pass (D-176): itens novos e exclusivos, só visuais, fora das caixas, da
-- troca, da compra direta, do $ da Intendência e do Mercado; a posse grava no perfil uma vez.
-- Uso: lune run tests/luau/conjuntos.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local M = "../../src/ServerScriptService/Modules/"
local Arquivo = require(S .. "Arquivo") :: any
local Caixas = require(S .. "Caixas") :: any
local Commerce = require(S .. "Commerce") :: any
local Conjuntos = require(S .. "Conjuntos") :: any
local Cosmeticos = require(S .. "Cosmeticos") :: any
local Medalhas = require(S .. "Medalhas") :: any
local Mercado = require(S .. "Mercado") :: any
local Skins = require(S .. "Skins") :: any
local CaixaRegras = require(M .. "CaixaRegras") :: any
local ProfileSchema = require(M .. "ProfileSchema") :: any

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

test("os 4 conjuntos do pedido, com os preços de referência e a chave no Commerce", function()
	local ref = {
		PASS_SET_IDENTIDADE = 49,
		PASS_SET_UNIFORMES = 99,
		PASS_SET_ARMAS = 149,
		PASS_SET_FUNDADOR = 499,
	}
	assert(#Conjuntos.LISTA == 4)
	for _, c in Conjuntos.LISTA do
		assert(ref[c.key] == c.robux, c.key .. ": preço")
		assert(type(Commerce.IDS[c.key]) == "number", c.key .. ": fora do Commerce.IDS")
		assert(#c.nome > 0 and #c.desc > 0 and string.find(c.desc, "Só visual", 1, true), c.key)
		assert(#c.itens >= 4, c.key .. ": itens")
	end
end)

test("cada item é novo, exclusivo do conjunto e só visual", function()
	local vistos = {}
	for _, c in Conjuntos.LISTA do
		for _, id in c.itens do
			assert(not vistos[id], "item em dois conjuntos: " .. id)
			vistos[id] = true
			assert(Conjuntos.doItem(id) == c.key)
			if string.sub(id, 1, 4) == "tit_" then
				assert(Conjuntos.TITULOS[id] and Medalhas.NAMES[id], id .. ": título sem nome")
			else
				local info = Cosmeticos.info(id)
				assert(info, id .. ": sem cadastro")
				assert(not info.vantagem, id .. ": vantagem")
				local s = Skins.get(id)
				if s then
					assert(s.soPasse and s.robuxKey == c.key and s.robuxKind == "pass", id .. ": skin do conjunto")
					assert(s.kind ~= "camo", id .. ": camuflagem dá vantagem")
				else
					assert(info.exclusivo == "passe" and info.passe == c.key, id .. ": cosmético do conjunto")
				end
			end
		end
	end
end)

test("fora das caixas, da troca, da compra direta, do $ e do Mercado", function()
	for _, c in Conjuntos.LISTA do
		for _, id in c.itens do
			for _, cx in Caixas.CAIXAS do
				for _, e in cx.itens do
					assert(e.item ~= id, id .. " em caixa " .. cx.id)
				end
			end
			assert(CaixaRegras.precoCreditos(id) == nil, id .. ": compra direta")
			local s = Skins.get(id)
			if s then
				local ok, why = Skins.canBuy(id, {}, {}, 1e9)
				assert(not ok and why == "só no conjunto em Game Pass", id .. ": $ da Intendência")
			end
		end
	end
	for _, t in CaixaRegras.troca() do
		assert(not Conjuntos.doItem(t.item), "troca " .. t.item)
	end
	for day = 0, 400 do
		for _, it in Mercado.rotation(day) do
			assert(not Conjuntos.doItem(it.id), "mercado do dia " .. day .. ": " .. it.id)
		end
	end
	-- a validação das caixas recusa um item de conjunto
	local cx = table.clone(Caixas.get("suprimentos"))
	cx.itens = table.clone(cx.itens)
	cx.itens[1] = { item = "mol_fundador", peso = cx.itens[1].peso }
	assert(#Caixas.validar(cx, Cosmeticos.info) > 0)
end)

test("posse: a skin vale pelo passe; o cartão e o título gravam no perfil uma vez", function()
	local p = ProfileSchema.default()
	local passes = { PASS_SET_FUNDADOR = true }
	assert(Skins.owns(Skins.get("skin_us_fundador"), p.skins.owned, passes))
	assert(not Skins.owns(Skins.get("skin_us_hbt"), p.skins.owned, passes), "o outro conjunto não")
	local novos = CaixaRegras.gravarConjuntos(p, passes)
	table.sort(novos)
	assert(
		table.concat(novos, ",") == "emb_fundador,emb_fundador_65,mol_fundador,tag_fundador,tit_fundador",
		table.concat(novos, ",")
	)
	assert(#CaixaRegras.gravarConjuntos(p, passes) == 0, "idempotente")
	assert(#CaixaRegras.gravarConjuntos(p, {}) == 0 and #CaixaRegras.gravarConjuntos(p, nil) == 0)
	-- o cartão aceita a insígnia e o título; a plaqueta e a moldura podem ser usadas
	local card = Medalhas.validCard(
		{ emblem = "emb_fundador", title = "tit_fundador", medals = {} },
		p.campaign.owned,
		{}
	)
	assert(card and card.emblem == "emb_fundador" and card.title == "tit_fundador")
	assert(CaixaRegras.equipar(p, "tag", "tag_fundador") and CaixaRegras.equipar(p, "mol", "mol_fundador"))
	-- sem o passe, nada
	local q = ProfileSchema.default()
	assert(
		not Medalhas.validCard({ emblem = "emb_fundador", title = "tit_fundador", medals = {} }, q.campaign.owned, {})
	)
	assert(not CaixaRegras.equipar(q, "tag", "tag_fundador"))
end)

test("álbum: a origem é o conjunto (compra direta em Robux), sem caminho grátis", function()
	for _, c in Conjuntos.LISTA do
		for _, id in c.itens do
			local o = Arquivo.origens(id)
			local temPasse = false
			for _, x in o do
				assert(x.tipo == "passe", id .. ": origem " .. x.tipo)
				temPasse = temPasse or x.passe == c.key
			end
			assert(temPasse, id)
			assert(not Arquivo.gratis(id) and Arquivo.compraDireta(id))
		end
	end
	-- nenhuma coleção pede item de conjunto
	for _, col in Arquivo.COLECOES do
		for _, id in col.itens do
			assert(not Conjuntos.doItem(id), col.id .. ": " .. id)
		end
	end
end)

test("servidor: a posse dos conjuntos é relida e gravada (entrada e compra)", function()
	local cs = fs.readFile("src/ServerScriptService/Modules/CommerceService.luau")
	assert(string.find(cs, "for _, c in Conjuntos.LISTA do", 1, true), "refresh lê os conjuntos")
	assert(string.find(cs, "CommerceService.onConjuntos", 1, true))
	local cx = fs.readFile("src/ServerScriptService/Modules/CaixaService.luau")
	assert(string.find(cx, "CaixaRegras.gravarConjuntos(prof, ps)", 1, true), "dentro do transact")
	assert(string.find(cx, "task.spawn(CaixaService.conjuntos, player)", 1, true), "ao carregar o perfil")
	-- o id do passe acha a chave (para a compra)
	local antes = Commerce.IDS.PASS_SET_ARMAS
	Commerce.IDS.PASS_SET_ARMAS = 123456
	local k = Commerce.passKeyById(123456)
	Commerce.IDS.PASS_SET_ARMAS = antes
	assert(k == "PASS_SET_ARMAS")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
