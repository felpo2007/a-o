--!strict
-- Testes da roleta das caixas (D-177): a faixa usa as chances reais e não mexe nos vizinhos do
-- vencedor; a parada é exata no cartão do servidor em qualquer largura; a curva desacelera sem tranco.
-- Uso: lune run tests/luau/roleta.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Caixas = require(S .. "Caixas") :: any
local Cosmeticos = require(S .. "Cosmeticos") :: any
local Rng = require(S .. "Rng") :: any
local Roleta = require(S .. "Roleta") :: any

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

local function chiCrit(df: number): number
	local z = 3.0902
	local a = 2 / (9 * df)
	return df * (1 - a + z * math.sqrt(a)) ^ 3
end

test("faixa: tamanho fixo, vencedor no lugar certo, só itens da caixa", function()
	local c = Caixas.get("suprimentos")
	local rng = Rng.new(1)
	local f = Roleta.faixa(c.itens, "tag_gravada", function()
		return rng:nextU32() % E
	end)
	assert(#f == Roleta.TOTAL and f[Roleta.POS_VENCEDOR] == "tag_gravada")
	assert(Roleta.TOTAL - Roleta.POS_VENCEDOR >= 4, "cartões depois do vencedor")
	assert(Roleta.POS_VENCEDOR - Roleta.INICIO >= 30, "distância para a rolagem")
	local da: { [string]: boolean } = {}
	for _, e in c.itens do
		da[e.item] = true
	end
	for _, id in f do
		assert(da[id], id)
	end
end)

test("enchimento com as chances reais, também ao lado do vencedor (sem quase vitória)", function()
	-- vencedor lendário: os vizinhos seguem a tabela, nem mais nem menos raros
	local c = Caixas.get("suprimentos")
	local rng = Rng.new(19650818)
	local N = 4000
	local porRar: { [string]: number } = {}
	local vizinhos: { [string]: number } = {}
	local total, totalViz = 0, 0
	for _ = 1, N do
		local f = Roleta.faixa(c.itens, "tag_gravada", function()
			return rng:nextU32() % E
		end)
		for i, id in f do
			if i ~= Roleta.POS_VENCEDOR then
				local r = Cosmeticos.info(id).raridade
				porRar[r] = (porRar[r] or 0) + 1
				total += 1
				if i == Roleta.POS_VENCEDOR - 1 or i == Roleta.POS_VENCEDOR + 1 then
					vizinhos[r] = (vizinhos[r] or 0) + 1
					totalViz += 1
				end
			end
		end
	end
	local esperado = Caixas.porRaridade(c, Cosmeticos.info, nil)
	for _, conj in { { porRar, total }, { vizinhos, totalViz } } do
		local cont, n = conj[1], conj[2]
		local chi, k = 0, 0
		for id, w in esperado do
			if w > 0 then
				k += 1
				local exp = n * w / E
				chi += ((cont[id] or 0) - exp) ^ 2 / exp
			end
		end
		assert(chi < chiCrit(k - 1), string.format("qui² %.2f", chi))
	end
	print(
		string.format(
			"         vizinhos do vencedor lendário: lendário %.2f%% (tabela 1%%), épico %.2f%% (tabela 4%%)",
			100 * (vizinhos.lendario or 0) / totalViz,
			100 * (vizinhos.epico or 0) / totalViz
		)
	)
end)

test("parada exata: o cartão do servidor fica no centro em qualquer largura", function()
	for _, larg in { 360, 412, 768, 1024, 1280, 1366, 1600, 1920, 2560, 3840 } do
		for _, minC in { 110, 140, 170, 210 } do
			local n = Roleta.visiveis(larg, minC)
			assert(n % 2 == 1 and n >= 3 and n <= 7, "visíveis " .. n)
			for _, gap in { 6, 10, 14 } do
				local cartao = Roleta.larguraCartao(larg, n, gap)
				assert(cartao > 0)
				assert(n * cartao + (n - 1) * gap <= larg, "cabem")
				for i = 1, Roleta.TOTAL do
					local x = Roleta.posicao(i, cartao, gap, larg)
					assert(Roleta.noMarcador(x, cartao, gap, larg) == i, string.format("%d em %d", i, larg))
					-- o centro do cartão i cai exatamente no centro da janela
					local centro = x + (i - 1) * (cartao + gap) + cartao / 2
					assert(math.abs(centro - larg / 2) < 1e-9)
				end
			end
		end
	end
	assert(Roleta.visiveis(1920, 170) == 7 and Roleta.visiveis(1000, 170) == 5 and Roleta.visiveis(375, 170) == 3)
	-- celular: até 5, mesmo com largura para mais
	assert(Roleta.visiveis(1920, 104, 5) == 5 and Roleta.visiveis(615, 104, 5) == 5 and Roleta.visiveis(615, 104) == 5)
end)

test("curva: começa rápida, sobe sempre e para sem tranco", function()
	assert(Roleta.curva(0) == 0 and Roleta.curva(1) == 1)
	local antes = 0
	for i = 1, 100 do
		local v = Roleta.curva(i / 100)
		assert(v >= antes, "sobe")
		antes = v
	end
	assert(Roleta.curva(0.1) > 0.4, "rápida no começo")
	local d = (Roleta.curva(1) - Roleta.curva(0.999)) / 0.001
	assert(d < 1e-6, "velocidade zero no fim")
	assert(Roleta.DURACAO.completa >= 5 and Roleta.DURACAO.completa <= 7, "5 a 7 s")
end)

test("tela: a roleta para no cartão do vencedor que o servidor mandou", function()
	local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/CaixasTela.client.luau")
	assert(string.find(src, "Roleta.faixa(", 1, true), "monta a faixa")
	assert(string.find(src, "Roleta.posicao(i, cartao, gap, janelaW)", 1, true), "posição pela regra pura")
	assert(string.find(src, "UDim2.fromOffset(px0(Roleta.POS_VENCEDOR), y)", 1, true), "para no vencedor")
	assert(string.find(src, "Roleta.faixa(lista, res.item,", 1, true), "o vencedor é o do servidor")
	assert(not string.find(src, "math.random", 1, true), "sem sorteio próprio de resultado")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
