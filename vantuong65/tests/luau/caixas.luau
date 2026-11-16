--!strict
-- Testes das caixas de suprimentos (D-173): tabelas, chances exatas, 100 mil sorteios por caixa
-- (qui-quadrado), repetidas, recibo idempotente, jogador restrito, troca, bilhetes e perfil.
-- D-174: caixas grátis por marco (guardadas), prêmios de saldo, compra direta com créditos e os
-- ganchos dos marcos no servidor.
-- Uso: lune run tests/luau/caixas.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local M = "../../src/ServerScriptService/Modules/"
local Caixas = require(S .. "Caixas") :: any
local Cosmeticos = require(S .. "Cosmeticos") :: any
local Commerce = require(S .. "Commerce") :: any
local Rng = require(S .. "Rng") :: any
local Temporada = require(S .. "Temporada") :: any
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

local E = Caixas.ESCALA

local function perfil(): any
	return ProfileSchema.default()
end

-- qui-quadrado crítico (p = 0,001) pela aproximação de Wilson-Hilferty
local function chiCrit(df: number): number
	local z = 3.0902
	local a = 2 / (9 * df)
	return df * (1 - a + z * math.sqrt(a)) ^ 3
end

-- ===== tabelas =====
test("todas as caixas passam na validação e somam exatamente 100%", function()
	assert(#Caixas.CAIXAS == 10, "10 caixas (D-174)")
	for _, c in Caixas.CAIXAS do
		local erros = Caixas.validar(c, Cosmeticos.info)
		assert(#erros == 0, table.concat(erros, "; "))
		local soma = 0
		for _, e in c.itens do
			soma += e.peso
		end
		assert(soma == E, c.id)
	end
end)

test("caixa de suprimentos: 60/25/10/4/1 e 126 itens (a tabela do pedido + os 100 da D-178)", function()
	local c = Caixas.get("suprimentos")
	assert(#c.itens == 126, #c.itens)
	local t = Caixas.porRaridade(c, Cosmeticos.info, nil)
	assert(t.comum == 60000 and t.incomum == 25000 and t.raro == 10000, "60/25/10")
	assert(t.epico == 4000 and t.lendario == 1000, "4/1")
	local n: { [string]: number } = {}
	for _, e in c.itens do
		local r = Cosmeticos.info(e.item).raridade
		n[r] = (n[r] or 0) + 1
	end
	assert(n.comum == 19 and n.incomum == 23 and n.raro == 34 and n.epico == 32 and n.lendario == 18)
end)

test("a raridade é do item: nenhuma caixa tem item com vantagem de jogo", function()
	for _, c in Caixas.CAIXAS do
		for _, e in c.itens do
			local info = Cosmeticos.info(e.item)
			assert(info and not info.vantagem, e.item)
			assert(string.sub(e.item, 1, 5) ~= "camo_", "camuflagem de mato fora: " .. e.item)
		end
	end
	assert(Cosmeticos.info("camo_rice") == nil, "a camuflagem nem é item de caixa")
end)

test("percentual exato em texto", function()
	assert(Caixas.pct(6000) == "6%", Caixas.pct(6000))
	assert(Caixas.pct(500) == "0,5%", Caixas.pct(500))
	assert(Caixas.pct(12500) == "12,5%", Caixas.pct(12500))
	assert(Caixas.pct(1) == "0,001%", Caixas.pct(1))
	assert(Caixas.pct(E) == "100%")
end)

test("validação recusa peso ruim, soma errada, item desconhecido, repetido e vantagem", function()
	local base = Caixas.get("suprimentos")
	local function com(itens: { any }, extra: { [string]: any }?): { string }
		local c = table.clone(base)
		c.itens = itens
		for k, v in extra or {} do
			c[k] = v
		end
		return Caixas.validar(c, Cosmeticos.info)
	end
	assert(#com({ { item = "tag_aco", peso = -1 }, { item = "tag_aluminio", peso = E + 1 } }) > 0, "negativo")
	assert(#com({ { item = "tag_aco", peso = 0.5 }, { item = "tag_aluminio", peso = E - 0.5 } }) > 0, "fração")
	assert(#com({ { item = "tag_aco", peso = 0 / 0 }, { item = "tag_aluminio", peso = E } }) > 0, "NaN")
	assert(#com({ { item = "tag_aco", peso = 50000 }, { item = "tag_aluminio", peso = 40000 } }) > 0, "soma")
	assert(#com({ { item = "nada_disso", peso = E } }) > 0, "desconhecido")
	assert(#com({ { item = "tag_aco", peso = 50000 }, { item = "tag_aco", peso = 50000 } }) > 0, "repetido")
	assert(#com({ { item = "tag_aco", peso = E } }, { produto = false }) > 0, "paga sem produto")
	local free = table.clone(Caixas.get("gratuita"))
	free.robux = 49
	assert(#Caixas.validar(free, Cosmeticos.info) > 0, "gratuita com preço")
	-- vantagem: um item com vantagem (simulado) é recusado
	local info = function(id: string): any
		local i = Cosmeticos.info(id)
		return if id == "tag_aco" then { raridade = "comum", vantagem = true } else i
	end
	local c2 = table.clone(base)
	assert(#Caixas.validar(c2, info) > 0, "vantagem")
end)

test("escolher: limites da faixa e erro fora dela", function()
	local c = Caixas.get("suprimentos")
	assert(Caixas.escolher(c.itens, 0).item == c.itens[1].item)
	assert(Caixas.escolher(c.itens, E - 1).item == c.itens[#c.itens].item)
	assert(not pcall(Caixas.escolher, c.itens, E), "n = ESCALA fora")
	assert(not pcall(Caixas.escolher, c.itens, -1), "negativo fora")
	assert(not pcall(Caixas.escolher, c.itens, 0.5), "fração fora")
end)

-- ===== 100 mil sorteios por caixa =====
test("100.000 sorteios por caixa batem com as chances (qui-quadrado, p = 0,001)", function()
	local N = 100000
	local rng = Rng.new(19650818)
	for _, c in Caixas.CAIXAS do
		local count: { [string]: number } = {}
		for _ = 1, N do
			local n = rng:nextU32() % E
			local e = Caixas.escolher(c.itens, n)
			count[e.item] = (count[e.item] or 0) + 1
		end
		local chi = 0
		for _, e in c.itens do
			local esperado = N * e.peso / E
			local obs = count[e.item] or 0
			chi += (obs - esperado) ^ 2 / esperado
		end
		local df = #c.itens - 1
		local lim = chiCrit(df)
		print(
			string.format("         %-12s %2d itens  qui² %6.2f  (limite %6.2f, gl %d)", c.id, #c.itens, chi, lim, df)
		)
		assert(chi < lim, c.id .. ": qui² acima do limite")
		-- por raridade também
		local rar: { [string]: number } = {}
		for _, e in c.itens do
			local r = Cosmeticos.info(e.item).raridade
			rar[r] = (rar[r] or 0) + (count[e.item] or 0)
		end
		local esperadoR = Caixas.porRaridade(c, Cosmeticos.info, nil)
		local chiR, k = 0, 0
		for id, w in esperadoR do
			if w > 0 then
				k += 1
				local exp = N * w / E
				chiR += ((rar[id] or 0) - exp) ^ 2 / exp
			end
		end
		if k > 1 then
			assert(chiR < chiCrit(k - 1), c.id .. ": raridade fora")
		end
		if c.id == "suprimentos" then
			print(
				string.format(
					"         suprimentos por raridade: comum %.2f%%  incomum %.2f%%  raro %.2f%%  épico %.2f%%  lendário %.2f%%",
					100 * (rar.comum or 0) / N,
					100 * (rar.incomum or 0) / N,
					100 * (rar.raro or 0) / N,
					100 * (rar.epico or 0) / N,
					100 * (rar.lendario or 0) / N
				)
			)
		end
	end
end)

-- ===== resultados finais do jogador =====
test("item que já tem: o resultado final vira Fragmentos e a soma segue 100%", function()
	local p = perfil()
	p.campaign.owned.tag_aco = true
	p.skins.owned.skin_m14_birch = true
	local odds = CaixaRegras.odds(p, "suprimentos", {})
	local soma = 0
	for _, r in odds do
		soma += r.peso
		if r.item == "tag_aco" then
			assert(r.repetido and r.fragmentos == 5, "comum = 5")
		elseif r.item == "skin_m14_birch" then
			assert(r.repetido and r.fragmentos == 15, "incomum = 15")
		else
			assert(not r.repetido and r.fragmentos == 0)
		end
	end
	assert(soma == E)
	-- uniforme por Game Pass também conta como já tem
	local odds2 = CaixaRegras.odds(p, "elite", { PASS_SKIN_US_TIGER = true })
	for _, r in odds2 do
		if r.item == "skin_us_tiger" then
			assert(r.repetido and r.fragmentos == 250, "lendário = 250")
		end
	end
end)

-- ===== transações =====
test("caixa gratuita: sem bilhete não abre; com bilhete gasta 1 e entrega", function()
	local p = perfil()
	local r, motivo = CaixaRegras.abrirGratuita(p, "gratuita", 0, 100, {})
	assert(r == nil and motivo == "bilhetes")
	p.caixas.bilhetes = 1
	local r2 = CaixaRegras.abrirGratuita(p, "gratuita", 0, 100, {})
	assert(r2 and r2.item == "tag_aco" and not r2.repetido, "primeiro item da tabela")
	assert(p.caixas.bilhetes == 0 and p.campaign.owned.tag_aco == true)
	assert(#p.caixas.hist == 1 and p.caixas.abertas.gratuita == 1)
	-- caixa paga não abre com bilhete
	p.caixas.bilhetes = 5
	local r3, m3 = CaixaRegras.abrirGratuita(p, "suprimentos", 0, 100, {})
	assert(r3 == nil and m3 == "caixa")
end)

test("repetida nunca some: vira Fragmentos da raridade, sem conceder de novo", function()
	local p = perfil()
	p.caixas.bilhetes = 2
	CaixaRegras.abrirGratuita(p, "gratuita", 0, 1, {})
	local r = CaixaRegras.abrirGratuita(p, "gratuita", 0, 2, {})
	assert(r.repetido and r.fragmentos == 5 and p.caixas.fragmentos == 5)
	-- skin: vai para skins.owned; repetida vira fragmentos
	local p2 = perfil()
	local c = Caixas.get("especiais")
	local r2 = CaixaRegras.aplicar(p2, "especiais", 0, 1, "recibo", {}, "x1")
	assert(r2.item == c.itens[1].item and p2.skins.owned[r2.item] == true)
	local r3 = CaixaRegras.aplicar(p2, "especiais", 0, 2, "recibo", {}, "x2")
	assert(r3.repetido and r3.fragmentos == 15 and p2.caixas.fragmentos == 15)
end)

test("recibo da caixa paga é idempotente: o mesmo PurchaseId não sorteia de novo", function()
	local p = perfil()
	local r1, novo1 = CaixaRegras.recibo(p, "suprimentos", "P-1", 0, 10, false, {})
	assert(novo1 and r1.item == "tag_aco" and r1.id == "P-1")
	local r2, novo2 = CaixaRegras.recibo(p, "suprimentos", "P-1", E - 1, 20, false, {})
	assert(not novo2 and r2.item == "tag_aco", "devolve o resultado gravado, não sorteia com o n novo")
	assert(p.caixas.abertas.suprimentos == 1 and #p.caixas.hist == 1 and p.caixas.fragmentos == 0)
	-- o recibo sobrevive à ida e volta pelo DataStore (migrate)
	local back = ProfileSchema.migrate(p)
	local r3, novo3 = CaixaRegras.recibo(back, "suprimentos", "P-1", E - 1, 30, false, {})
	assert(not novo3 and r3.item == "tag_aco")
end)

test("jogador restrito (PolicyService) que chegou a um recibo: Fragmentos fixos, sem sorteio", function()
	local p = perfil()
	local r, novo = CaixaRegras.recibo(p, "elite", "P-9", 0, 10, true, {})
	assert(novo and r.item == nil and r.origem == "restrito")
	assert(r.fragmentos == CaixaRegras.FIXO_RESTRITO.elite and p.caixas.fragmentos == r.fragmentos)
	assert((p.caixas.abertas.elite or 0) == 0, "nada sorteado")
	local again = CaixaRegras.recibo(p, "elite", "P-9", 0, 11, false, {})
	assert(again.origem == "restrito" and p.caixas.fragmentos == CaixaRegras.FIXO_RESTRITO.elite, "não paga 2 vezes")
end)

test("troca de Fragmentos: custo da raridade, só o que não tem", function()
	local p = perfil()
	local r, m = CaixaRegras.trocar(p, "tag_gravada", 1, {})
	assert(r == nil and m == "fragmentos")
	p.caixas.fragmentos = 4000
	local r2 = CaixaRegras.trocar(p, "tag_gravada", 1, {})
	assert(r2 and p.caixas.fragmentos == 1500 and p.campaign.owned.tag_gravada == true, "lendário custa 2500")
	p.caixas.fragmentos = 4000
	local r3, m3 = CaixaRegras.trocar(p, "tag_gravada", 1, {})
	assert(r3 == nil and m3 == "possui" and p.caixas.fragmentos == 4000)
	local r4, m4 = CaixaRegras.trocar(p, "camo_rice", 1, {})
	assert(r4 == nil and m4 == "item", "camuflagem fora da troca")
	for _, t in CaixaRegras.troca() do
		local info = Cosmeticos.info(t.item)
		assert(t.custo == Caixas.raridade(info.raridade).custo)
	end
end)

test("bilhetes: teto por dia e boas-vindas uma vez só", function()
	local p = perfil()
	assert(CaixaRegras.ganhar(p, 2, 10, "boas_vindas") == 2)
	assert(CaixaRegras.ganhar(p, 2, 10, "boas_vindas") == 0)
	assert(CaixaRegras.ganhar(p, 1, 20, "missao") == 1)
	assert(CaixaRegras.ganhar(p, 2, 20, "missao") == 2)
	assert(CaixaRegras.ganhar(p, 2, 20, "missao") == 1, "teto 4 no dia")
	assert(CaixaRegras.ganhar(p, 2, 20, "missao") == 0)
	assert(CaixaRegras.ganhar(p, 2, 21, "missao") == 2, "dia novo")
	assert(p.caixas.bilhetes == 2 + 4 + 2)
end)

test("equipar plaqueta e moldura: só o que tem e do tipo certo", function()
	local p = perfil()
	assert(not CaixaRegras.equipar(p, "tag", "tag_aco"))
	p.campaign.owned.tag_aco = true
	p.campaign.owned.mol_lona = true
	assert(CaixaRegras.equipar(p, "tag", "tag_aco") and p.caixas.on.tag == "tag_aco")
	assert(not CaixaRegras.equipar(p, "tag", "mol_lona"), "moldura não vai na plaqueta")
	assert(CaixaRegras.equipar(p, "mol", "mol_lona"))
	assert(CaixaRegras.equipar(p, "tag", "") and p.caixas.on.tag == nil)
	assert(not CaixaRegras.equipar(p, "outro", "tag_aco"))
end)

test("perfil: sem `caixas` vira zerado; lixo saneado; o salvamento não sobrescreve as caixas", function()
	local p = ProfileSchema.migrate({ xp = 10 })
	assert(p.caixas.bilhetes == 0 and p.caixas.fragmentos == 0 and #p.caixas.hist == 0)
	local d = CaixaRegras.sanear({ bilhetes = -5, fragmentos = "x", abertas = { nada = 3, gratuita = 2 }, hist = 7 })
	assert(d.bilhetes == 0 and d.fragmentos == 0 and d.abertas.nada == nil and d.abertas.gratuita == 2)
	-- applySession: a memória (antiga) não apaga o que a transação gravou
	local stored = perfil()
	stored.caixas.bilhetes = 9
	local mem = perfil()
	mem.caixas.bilhetes = 1
	local rec = table.clone(mem)
	ProfileSchema.applySession(rec, stored, mem, ProfileSchema.synced(mem))
	assert(rec.caixas.bilhetes == 9, "vale o gravado")
end)

test("garantia progressiva: desligada não muda nada; ligada (simulada) soma 100% e garante", function()
	local c = Caixas.get("suprimentos")
	assert(Caixas.PITY.enabled == false, "fica desligada por padrão")
	local base = Caixas.pesosEfetivos(c, Cosmeticos.info, 999)
	for i, e in base do
		assert(e.peso == c.itens[i].peso)
	end
	Caixas.PITY.enabled = true
	local ok, err = pcall(function()
		local P = Caixas.PITY
		local antes = Caixas.porRaridade(c, Cosmeticos.info, P.depois - 1)
		local depois = Caixas.porRaridade(c, Cosmeticos.info, P.depois + 4)
		assert(antes.epico + antes.lendario == 5000)
		assert(depois.epico + depois.lendario > 5000, "subiu depois do limite")
		for _, cont in { 0, P.depois, P.depois + 7, P.garantia - 1 } do
			local soma = 0
			for _, e in Caixas.pesosEfetivos(c, Cosmeticos.info, cont) do
				soma += e.peso
				assert(e.peso >= 0 and e.peso == math.floor(e.peso))
			end
			assert(soma == E, "soma no contador " .. cont)
		end
		local g = Caixas.porRaridade(c, Cosmeticos.info, P.garantia - 1)
		assert(g.epico + g.lendario == E, "garantia")
		assert(Caixas.proximoContador(10, "comum") == 11 and Caixas.proximoContador(10, "lendario") == 0)
	end)
	Caixas.PITY.enabled = false
	assert(ok, err)
end)

-- ===== D-174: caixas grátis por marco, prêmios de saldo e compra direta =====
test("D-174: as cinco caixas grátis de marco existem, com o como ganhar, e a de bilhete segue", function()
	local marco = {}
	for _, c in Caixas.CAIXAS do
		if c.fonte == "marco" then
			table.insert(marco, c.id)
		end
	end
	table.sort(marco)
	assert(table.concat(marco, ",") == "batalhao,campanha,recruta,servico,veterano", table.concat(marco, ","))
	assert(Caixas.get("gratuita").fonte == "bilhete")
	-- fragmentos por raridade: 5/15/40/100/250 (o pedido do dono)
	local f = {}
	for _, r in Caixas.RARIDADES do
		table.insert(f, tostring(r.fragmentos))
		assert(r.custo == r.fragmentos * 10, r.id .. ": troca = 10 repetidas da mesma raridade")
		assert(r.creditos and r.creditos > 0, r.id .. ": preço em créditos")
	end
	assert(table.concat(f, "/") == "5/15/40/100/250", table.concat(f, "/"))
end)

test("D-174: caixa de marco fica guardada, cada marco vale uma vez, e abrir gasta a guardada", function()
	local p = perfil()
	local r0, m0 = CaixaRegras.abrirGratuita(p, "servico", 0, 1, {})
	assert(r0 == nil and m0 == "guardada", "sem guardada não abre")
	assert(CaixaRegras.darCaixa(p, "servico", "posto:2"), "dá")
	assert(not CaixaRegras.darCaixa(p, "servico", "posto:2"), "o mesmo marco não dá duas vezes")
	assert(CaixaRegras.darCaixa(p, "servico", "posto:3"))
	assert(p.caixas.guardadas.servico == 2)
	-- só caixa grátis de marco: nem a de bilhete, nem a paga, nem caixa inventada
	assert(not CaixaRegras.darCaixa(p, "gratuita", "x") and not CaixaRegras.darCaixa(p, "suprimentos", "y"))
	assert(not CaixaRegras.darCaixa(p, "nada", "z"))
	local r = CaixaRegras.abrirGratuita(p, "servico", 0, 2, {})
	assert(r and r.origem == "marco" and p.caixas.guardadas.servico == 1)
	assert(p.caixas.bilhetes == 0, "não gasta bilhete")
	-- as guardadas e os marcos sobrevivem à ida e volta pelo DataStore
	local back = ProfileSchema.migrate(p)
	assert(back.caixas.guardadas.servico == 1 and back.caixas.marcos["posto:2"] == true)
	assert(not CaixaRegras.darCaixa(back, "servico", "posto:3"), "marco gravado não volta a dar")
	-- teto de marcos guardados (perfil não cresce sem fim)
	local p2 = perfil()
	for i = 1, CaixaRegras.MAX_MARCOS do
		p2.caixas.marcos["m" .. i] = true
	end
	assert(not CaixaRegras.darCaixa(p2, "veterano", "partidas:10"), "teto")
	-- lixo no perfil é saneado
	local d = CaixaRegras.sanear({
		guardadas = { servico = -3, nada = 2, veterano = 1.5 },
		marcos = { [1] = true, ok = "sim" },
	})
	assert((d.guardadas.servico or 0) == 0 and d.guardadas.nada == nil, "guardadas saneadas")
	assert(next(d.marcos) == nil, "marcos saneados")
end)

test("D-174: prêmio de saldo entra no saldo, nunca é repetido e não vai para troca nem loja", function()
	local p = perfil()
	p.credits = 100
	CaixaRegras.darCaixa(p, "campanha", "passe:10")
	CaixaRegras.darCaixa(p, "campanha", "passe:20")
	local c = Caixas.get("campanha")
	-- acha o n que cai no prêmio de créditos
	local acc, nCr = 0, nil
	for _, e in c.itens do
		if e.item == "cr_1500" then
			nCr = acc
		end
		acc += e.peso
	end
	assert(nCr, "a caixa de campanha tem o prêmio de créditos")
	local r1 = CaixaRegras.abrirGratuita(p, "campanha", nCr, 1, {})
	assert(r1.item == "cr_1500" and not r1.repetido and p.credits == 1600, "entrou no saldo")
	local r2 = CaixaRegras.abrirGratuita(p, "campanha", nCr, 2, {})
	assert(r2.item == "cr_1500" and not r2.repetido and p.credits == 3100, "de novo: soma, não vira fragmento")
	assert(p.caixas.fragmentos == 0)
	assert(p.campaign.owned.cr_1500 == nil, "não vira posse")
	for _, t in CaixaRegras.troca() do
		local k = Cosmeticos.info(t.item).kind
		assert(k ~= "creditos" and k ~= "fragmentos", t.item)
	end
	assert(CaixaRegras.precoCreditos("cr_500") == nil and CaixaRegras.precoCreditos("frag_250") == nil)
	-- caixa paga só com cosméticos: a validação recusa prêmio de saldo
	local paga = table.clone(Caixas.get("suprimentos"))
	paga.itens = table.clone(paga.itens)
	paga.itens[1] = { item = "cr_500", peso = paga.itens[1].peso }
	assert(#Caixas.validar(paga, Cosmeticos.info) > 0, "paga com créditos")
end)

test("D-174: compra direta com créditos: preço da raridade, saldo exato, só o que não tem", function()
	local p = perfil()
	p.credits = 0
	local preco = CaixaRegras.precoCreditos("tag_aco")
	assert(preco == Caixas.raridade("comum").creditos)
	local r0, m0 = CaixaRegras.comprarCreditos(p, "tag_aco", 1)
	assert(r0 == nil and m0 == "creditos" and p.credits == 0)
	p.credits = preco + 7
	local r = CaixaRegras.comprarCreditos(p, "tag_aco", 2)
	assert(r and r.origem == "compra" and p.credits == 7 and p.campaign.owned.tag_aco == true)
	local r2, m2 = CaixaRegras.comprarCreditos(p, "tag_aco", 3)
	assert(r2 == nil and m2 == "possui" and p.credits == 7, "não cobra duas vezes")
	-- skins têm a compra própria na Intendência; camuflagem e item inventado ficam fora
	for _, id in { "skin_m14_birch", "camo_rice", "nada" } do
		local rx, mx = CaixaRegras.comprarCreditos(p, id, 4)
		assert(rx == nil and mx == "item", id)
	end
	assert(#p.caixas.hist == 1, "só a compra entrou no histórico")
end)

test("D-174: os marcos chamam darCaixa no servidor (treino, posto, missão da semana, passe, partidas)", function()
	local function tem(arq: string, trecho: string)
		local src = fs.readFile(arq)
		assert(string.find(src, trecho, 1, true), arq .. ": " .. trecho)
	end
	tem("src/ServerScriptService/Modules/TrainingService.luau", 'CaixaService.darCaixa(p, "recruta"')
	tem("src/ServerScriptService/Modules/ProgressionService.luau", 'CaixaService.darCaixa(p, "servico"')
	tem("src/ServerScriptService/Modules/CampanhaService.luau", 'CaixaService.darCaixa(p, "batalhao"')
	tem("src/ServerScriptService/Modules/CampanhaService.luau", 'CaixaService.darCaixa(p, "campanha"')
	tem("src/ServerScriptService/Modules/CampanhaService.luau", "CaixaService.partidaCompleta(")
	tem("src/ServerScriptService/Modules/CaixaService.luau", 'CaixaService.darCaixa(player, "veterano"')
	-- a compra direta passa pela gravação atômica, que junta os créditos da sessão antes
	tem("src/ServerScriptService/Modules/CaixaService.luau", "CaixaRegras.comprarCreditos(p, item, os.time())")
	tem("src/ServerScriptService/Modules/PlayerData.luau", "deltaUsado")
end)

-- ===== D-178: os 100 itens novos =====
test("D-178: 100 itens novos, nas caixas sem mudar a fatia de nenhuma raridade", function()
	local n = 0
	for _, l in Caixas.NOVOS_D178 do
		n += #l
	end
	assert(n == 100, "100 itens: " .. n)
	-- as porcentagens por raridade de antes (MONETIZATION.md), caixa por caixa
	local ANTES = {
		gratuita = { 82000, 13000, 3000, 1000, 1000 },
		recruta = { 84000, 11000, 3000, 1500, 500 },
		servico = { 39000, 43000, 16000, 1500, 500 },
		batalhao = { 42000, 30000, 24000, 3000, 1000 },
		campanha = { 0, 55000, 30000, 13000, 2000 },
		veterano = { 0, 0, 44000, 46000, 10000 },
		suprimentos = { 60000, 25000, 10000, 4000, 1000 },
		especiais = { 0, 45000, 36000, 16000, 3000 },
		elite = { 0, 0, 40000, 48000, 12000 },
		historica = { 0, 50000, 30000, 15000, 5000 },
	}
	for id, v in ANTES do
		local t = Caixas.porRaridade(Caixas.get(id), Cosmeticos.info, nil)
		for i, r in Caixas.RARIDADES do
			assert((t[r.id] or 0) == v[i], string.format("%s %s: %d (era %d)", id, r.id, t[r.id] or 0, v[i]))
		end
	end
	-- cada novo numa caixa grátis e na de Suprimentos; nenhum peso zerado
	local gratis, sup = {}, {}
	for _, c in Caixas.CAIXAS do
		for _, e in c.itens do
			assert(e.peso >= 1 and e.peso == math.floor(e.peso), c.id .. " " .. e.item)
			if c.tipo == "gratuita" then
				gratis[e.item] = true
			end
			if c.id == "suprimentos" then
				sup[e.item] = true
			end
		end
	end
	for _, l in Caixas.NOVOS_D178 do
		for _, id in l do
			assert(gratis[id], id .. " sem caixa grátis")
			assert(sup[id], id .. " fora da de Suprimentos")
			local info = Cosmeticos.info(id)
			assert(info and not info.vantagem and not info.exclusivo, id)
		end
	end
	-- a regra de acrescentar recusa raridade que a caixa não tem
	assert(not pcall(Caixas.acrescentar, Caixas.get("elite").itens, { "skin_m14_carbono" }, Cosmeticos.info))
end)

test("D-178: o acabamento extravagante sai só das caixas e da troca", function()
	local Skins = require(S .. "Skins") :: any
	local n = 0
	for _, s in Skins.CATALOG do
		if s.soCaixa then
			n += 1
			assert(s.kind == "weapon" and Skins.robuxId(s) == 0, s.id)
			local ok, why = Skins.canBuy(s.id, {}, {}, 1e9)
			assert(not ok and why == "só nas caixas", s.id)
			local naTroca = false
			for _, t in CaixaRegras.troca() do
				naTroca = naTroca or t.item == s.id
			end
			assert(naTroca, s.id .. " fora da troca")
		end
	end
	assert(n == 60, "60 acabamentos: " .. n)
end)

-- ===== produtos, temporada e servidor =====
test("caixas pagas: produto em Commerce.IDS, venda desligada até o questionário", function()
	assert(Caixas.PAGAS_LIGADAS == false, "D-173: o dono liga depois de reenviar o questionário")
	for _, c in Caixas.CAIXAS do
		if c.tipo == "paga" then
			assert(type(Commerce.IDS[c.produto]) == "number", c.produto)
			assert(Caixas.porProduto(c.produto) == c)
			assert(c.robux and c.robux > 0)
		else
			assert(c.produto == nil and c.robux == nil, c.id)
			if c.fonte == "bilhete" then
				assert((c.bilhetes or 0) >= 1, c.id)
			else
				assert(c.fonte == "marco" and type(c.ganha) == "string" and #c.ganha > 10, c.id .. ": como ganhar")
			end
		end
	end
	local h = Caixas.get("historica")
	local S1 = Temporada.SEASON
	assert(Caixas.disponivel(h, S1.startsAt + 10, S1) and not Caixas.disponivel(h, S1.endsAt, S1))
	assert(Caixas.disponivel(Caixas.get("suprimentos"), 0, S1))
end)

test("servidor: sorteio só no servidor, PolicyService conferido e falha bloqueia", function()
	local src = fs.readFile("src/ServerScriptService/Modules/CaixaService.luau")
	assert(string.find(src, "Random.new()", 1, true), "Random do servidor")
	assert(not string.find(src, "math.random", 1, true))
	assert(string.find(src, "ArePaidRandomItemsRestricted", 1, true))
	assert(
		string.find(src, "policy[player] = { at = os.clock(), ok = false, restricted = true }", 1, true),
		"falha = restrito"
	)
	-- recibo com a venda desligada (prompt aberto pelo próprio cliente): Fragmentos fixos, sem sorteio
	assert(string.find(src, "or not pagasLigadas()", 1, true), "venda desligada não sorteia")
	-- o cliente só manda o id da caixa (nada de número, peso ou resultado)
	assert(
		string.find(
			src,
			'Net.func("Suprimento_Abrir").OnServerInvoke = function(player: Player, caixaId: any)',
			1,
			true
		)
	)
	local cs = fs.readFile("src/ServerScriptService/Modules/CommerceService.luau")
	assert(string.find(cs, "Caixas.porProduto(key)", 1, true), "o recibo da caixa entra no ProcessReceipt")
	local cr = fs.readFile("src/ServerScriptService/Modules/CaixaRegras.luau")
	assert(
		not string.find(cr, "Random.new", 1, true) and not string.find(cr, "math.random", 1, true),
		"as regras não sorteiam: recebem o n"
	)
end)

-- D-173: o Suprimento_Comprar foi declarado como RemoteFunction e ligado como evento; o erro parou a
-- subida do servidor no Studio. Confere no projeto inteiro: Net.event só com nome de Events (ou
-- Unreliable) e Net.func só com nome de Functions.
test("remotes: cada Net.event/Net.func usa o tipo declarado no Net", function()
	local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
	local function bloco(nome: string): { [string]: boolean }
		local s = string.match(net, "Net%." .. nome .. " = (%b{})") or ""
		local t: { [string]: boolean } = {}
		for n in string.gmatch(s, '"([%w_]+)"') do
			t[n] = true
		end
		return t
	end
	local ev, un, fn = bloco("Events"), bloco("Unreliable"), bloco("Functions")
	local erros = {}
	local function varre(dir: string)
		for _, nome in fs.readDir(dir) do
			local p = dir .. "/" .. nome
			if fs.isDir(p) then
				varre(p)
			elseif string.sub(nome, -5) == ".luau" then
				local src = fs.readFile(p)
				-- (há remotes criados por outros serviços, fora das listas: só o tipo trocado é erro)
				for n in string.gmatch(src, 'Net%.event%("([%w_]+)"%)') do
					if fn[n] then
						table.insert(erros, p .. ": Net.event com nome de Functions " .. n)
					end
				end
				for n in string.gmatch(src, 'Net%.func%("([%w_]+)"%)') do
					if ev[n] or un[n] then
						table.insert(erros, p .. ": Net.func com nome de Events " .. n)
					end
				end
			end
		end
	end
	varre("src")
	assert(#erros == 0, table.concat(erros, "; "))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
