--!strict
-- Testes do ARQUIVO MILITAR STARLITE (D-175): catálogo, origens, caminho grátis de cada item,
-- coleções, exclusivos fora das caixas e da compra, e o resgate atômico (uma vez por conta).
-- Uso: lune run tests/luau/arquivo.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local M = "../../src/ServerScriptService/Modules/"
local Arquivo = require(S .. "Arquivo") :: any
local Caixas = require(S .. "Caixas") :: any
local Cosmeticos = require(S .. "Cosmeticos") :: any
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

local function perfil(): any
	return ProfileSchema.default()
end

-- dá todos os itens de uma coleção (como o gancho de Studio)
local function completa(p: any, colId: string)
	for _, id in Arquivo.colecao(colId).itens do
		if not CaixaRegras.possui(p, id, {}) then
			Cosmeticos.conceder(p, id)
		end
	end
end

test("as coleções passam na validação", function()
	local erros = Arquivo.validar()
	assert(#erros == 0, table.concat(erros, "; "))
	assert(#Arquivo.COLECOES == 9, "9 coleções")
end)

test("álbum: todos os cosméticos e skins, sem camuflagem nem prêmio de saldo", function()
	local itens = Arquivo.itens()
	local n = { uniformes = 0, acabamentos = 0, insignias = 0, plaquetas = 0, molduras = 0 }
	local vistos = {}
	for _, id in itens do
		assert(not vistos[id], "repetido " .. id)
		vistos[id] = true
		local c = Arquivo.categoria(id)
		n[c] += 1
	end
	assert(n.uniformes == 8 and n.acabamentos == 17, "skins: 8 uniformes e 17 acabamentos")
	assert(n.insignias == 9 and n.plaquetas == 9 and n.molduras == 10, "cartão com os 9 exclusivos")
	for _, id in { "camo_rice", "camo_jungle", "camo_bamboo", "cr_500", "frag_250", "nada" } do
		assert(Arquivo.categoria(id) == nil and not vistos[id], id)
	end
	-- ordem: categoria e, dentro dela, raridade
	local ordemCat = {}
	for i, c in Arquivo.CATEGORIAS do
		ordemCat[c.id] = i
	end
	for i = 2, #itens do
		assert(ordemCat[Arquivo.categoria(itens[i - 1])] <= ordemCat[Arquivo.categoria(itens[i])], "ordem")
	end
end)

test("todo item do álbum tem caminho grátis; nenhuma coleção exige caixa paga", function()
	for _, id in Arquivo.itens() do
		assert(Arquivo.gratis(id), "sem caminho grátis: " .. id)
	end
	-- um item que só existisse em caixa paga seria recusado
	local soPaga = false
	for _, o in Arquivo.origens("skin_us_lizard") do
		soPaga = soPaga or o.tipo == "intendencia"
	end
	assert(soPaga, "o lagarto (fora das caixas) sai pela Intendência")
end)

test("origens: caixas, troca, compra direta, Intendência, Robux e coleção batem com as regras", function()
	-- emblema comum: caixas grátis e paga, troca, compra direta
	local o = Arquivo.origens("emb_arrozais")
	local tipos: { [string]: number } = {}
	local pagas, gratis = 0, 0
	for _, x in o do
		tipos[x.tipo] = (tipos[x.tipo] or 0) + 1
		if x.tipo == "caixa" then
			if x.paga then
				pagas += 1
			else
				gratis += 1
			end
		end
	end
	assert(gratis == 3 and pagas == 1, "gratuita, recruta, batalhão e suprimentos")
	assert(tipos.troca == 1 and tipos.compra_direta == 1 and not tipos.intendencia)
	-- o preço da compra direta é o mesmo do servidor, item a item
	for _, id in Arquivo.itens() do
		assert(Arquivo.precoDireto(id) == CaixaRegras.precoCreditos(id), "preço de " .. id)
	end
	-- skin: Intendência ($) e Robux
	local s = Arquivo.origens("skin_m14_birch")
	local temI, temR = false, false
	for _, x in s do
		temI = temI or (x.tipo == "intendencia" and x.preco == Skins.tierPrice("weapon"))
		temR = temR or x.tipo == "robux"
	end
	assert(temI and temR)
	-- caixa de temporada marcada
	local hist = false
	for _, x in Arquivo.origens("skin_us_tadpole") do
		hist = hist or (x.tipo == "caixa" and x.caixa == "historica" and x.temporada == true)
	end
	assert(hist, "tadpole na caixa histórica (temporada)")
	-- exclusivo: só a coleção
	local e = Arquivo.origens("mol_arquivo")
	assert(#e == 1 and e[1].tipo == "colecao" and e[1].colecao == "arquivo")
	assert(not Arquivo.compraDireta("mol_arquivo") and Arquivo.compraDireta("emb_arrozais"))
end)

test("exclusivos do Arquivo: fora das caixas, da troca e da compra direta", function()
	local n = 0
	for _, it in Cosmeticos.ITENS do
		if it.exclusivo == "arquivo" then
			n += 1
			assert(CaixaRegras.precoCreditos(it.id) == nil, it.id)
			local r, m = CaixaRegras.comprarCreditos(perfil(), it.id, 1)
			assert(r == nil and m == "item", it.id .. " sem compra")
			for _, c in Caixas.CAIXAS do
				for _, e in c.itens do
					assert(e.item ~= it.id, it.id .. " em caixa")
				end
			end
		end
	end
	assert(n == 9, "9 exclusivos")
	for _, t in CaixaRegras.troca() do
		assert(not Cosmeticos.info(t.item).exclusivo, "troca " .. t.item)
	end
	-- a validação das caixas recusa um exclusivo
	local c = table.clone(Caixas.get("suprimentos"))
	c.itens = table.clone(c.itens)
	c.itens[1] = { item = "mol_arquivo", peso = c.itens[1].peso }
	assert(#Caixas.validar(c, Cosmeticos.info) > 0)
end)

test("progresso e resgate: só completa, uma vez, entrega o prêmio inteiro", function()
	local p = perfil()
	p.credits = 0
	local r0, m0 = CaixaRegras.resgatarColecao(p, "objetivos", 10, {})
	assert(r0 == nil and m0 == "incompleta")
	p.campaign.owned.emb_arrozais = true
	local c = Arquivo.colecao("objetivos")
	local t, n = Arquivo.progresso(c, function(id)
		return CaixaRegras.possui(p, id, {})
	end)
	assert(t == 1 and n == 5)
	completa(p, "objetivos")
	local r = CaixaRegras.resgatarColecao(p, "objetivos", 11, {})
	assert(r and r.origem == "colecao" and r.item == "tag_carta" and not r.repetido)
	assert(p.campaign.owned.tag_carta == true and p.caixas.fragmentos == 100 and p.credits == 0)
	assert(p.caixas.arquivo.objetivos == 11 and #p.caixas.hist == 1)
	local r2, m2 = CaixaRegras.resgatarColecao(p, "objetivos", 12, {})
	assert(r2 == nil and m2 == "resgatada" and p.caixas.fragmentos == 100, "não paga duas vezes")
	assert(select(2, CaixaRegras.resgatarColecao(p, "nada", 1, {})) == "colecao")
	-- o resgate sobrevive à ida e volta pelo DataStore
	local back = ProfileSchema.migrate(p)
	assert(back.caixas.arquivo.objetivos == 11)
	assert(select(2, CaixaRegras.resgatarColecao(back, "objetivos", 13, {})) == "resgatada")
	-- lixo saneado
	local d = CaixaRegras.sanear({ arquivo = { objetivos = "x", nada = 5, plaquetas = 7.5 } })
	assert(d.arquivo.objetivos == 0 and d.arquivo.nada == nil and d.arquivo.plaquetas == 7)
end)

test("uniforme por Game Pass conta na coleção; créditos do prêmio entram no saldo", function()
	local p = perfil()
	p.credits = 50
	p.skins.owned.skin_vc_black = true
	p.skins.owned.skin_vc_brown = true
	local passes = { [Skins.get("skin_vc_tiger").robuxKey] = true }
	local r = CaixaRegras.resgatarColecao(p, "fardas_vc", 1, passes)
	assert(r and r.item == "tag_fardas_vc", "o Game Pass do tiger stripe conta")
	assert(p.credits == 3050 and p.caixas.fragmentos == 300)
end)

test("Arquivo Completo: só com as 8 coleções completas", function()
	local p = perfil()
	local col = Arquivo.colecao("arquivo")
	for i, sub in col.colecoes do
		local r, m = CaixaRegras.resgatarColecao(p, "arquivo", 1, {})
		assert(r == nil and m == "incompleta", "faltando " .. sub)
		completa(p, sub)
		local t = Arquivo.progresso(col, function(id)
			return CaixaRegras.possui(p, id, {})
		end)
		assert(t == i)
	end
	local r = CaixaRegras.resgatarColecao(p, "arquivo", 2, {})
	assert(r and r.item == "mol_arquivo" and p.campaign.owned.mol_arquivo == true)
	-- os prêmios das outras não precisam ter sido resgatados (completa = ter os itens)
	assert(next(p.caixas.arquivo) == "arquivo" and next(p.caixas.arquivo, "arquivo") == nil)
end)

test("servidor: remotes do álbum, resgate atômico e validação na partida", function()
	local src = fs.readFile("src/ServerScriptService/Modules/CaixaService.luau")
	assert(string.find(src, 'Net.func("Arquivo_Resgatar").OnServerInvoke', 1, true))
	assert(string.find(src, "CaixaRegras.resgatarColecao(p, colId, os.time(), ps)", 1, true), "dentro do transact")
	assert(string.find(src, "Arquivo.validar()", 1, true))
	local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(net, '"Arquivo_Get"', 1, true) and string.find(net, '"Arquivo_Resgatar"', 1, true))
	-- o cliente só manda o id da coleção
	assert(string.find(src, "function CaixaService.resgatarColecao(player: Player, colId: any)", 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
