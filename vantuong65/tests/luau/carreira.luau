--!strict
-- D-247: nível do soldado, árvore de vantagens, prestígio e o perfil. Uso: lune run tests/luau/carreira.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Carreira = require(S .. "Carreira")
local Medalhas = require(S .. "Medalhas")
local Progression = require(S .. "Progression")
local Vantagens = require(S .. "Vantagens")
local ProfileSchema = require("../../src/ServerScriptService/Modules/ProfileSchema")

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

local XP_MAX = Carreira.XP_NIVEL[Carreira.NIVEL_MAX]

test("nível: 55 níveis, curva crescente e o topo perto da última patente", function()
	assert(#Carreira.XP_NIVEL == 55)
	for i = 3, 55 do
		assert(Carreira.XP_NIVEL[i] - Carreira.XP_NIVEL[i - 1] > Carreira.XP_NIVEL[i - 1] - Carreira.XP_NIVEL[i - 2])
	end
	assert(XP_MAX == 73440, "xp do nível 55: " .. XP_MAX)
	assert(XP_MAX <= Progression.THRESHOLD[Progression.MAX_RANK])
	assert((Carreira.nivel(0, 0)) == 1)
	assert((Carreira.nivel(299, 0)) == 1)
	assert((Carreira.nivel(300, 0)) == 2)
	local n, dentro, falta = Carreira.nivel(XP_MAX + 500, 0)
	assert(n == 55 and dentro == 500 and falta == 0)
end)

test("árvore: 12 nós, 3 x 4, efeitos em chaves reais e sem ciclo", function()
	assert(#Carreira.ARVORE == 12)
	local vistos: { [string]: boolean } = {}
	for _, n in Carreira.ARVORE do
		assert(not vistos[n.id], "repetido " .. n.id)
		assert(n.linha >= 1 and n.linha <= 3 and n.coluna >= 1 and n.coluna <= 4)
		if n.requer then
			assert(vistos[n.requer], n.id .. " pede um nó que vem depois")
		end
		for k in n.efeitos do
			assert(Vantagens.KEYS[k], n.id .. ": chave " .. k)
		end
		vistos[n.id] = true
	end
end)

test("pontos: 1 a cada 4 níveis; ativa em ordem, sem ponto e sem o anterior não ativa", function()
	assert(Carreira.pontosTotal(1, 0) == 0 and Carreira.pontosTotal(5, 0) == 1 and Carreira.pontosTotal(9, 0) == 2)
	assert(Carreira.pontosTotal(55, 0) == 12, "o nível máximo dá a árvore inteira")
	local e = Carreira.padrao()
	local xp = Carreira.XP_NIVEL[9] -- 2 pontos
	assert(not Carreira.podeAtivar(e, "cartucheira", xp), "pede o anterior")
	assert(not Carreira.podeAtivar(e, "nao existe", xp))
	assert(not Carreira.podeAtivar(e, 42, xp), "id que não é texto")
	assert(Carreira.podeAtivar(e, "passo", xp))
	e.nos.passo = true
	assert(not Carreira.podeAtivar(e, "passo", xp), "já ativa")
	e.nos.cartucheira = true
	local ok, motivo = Carreira.podeAtivar(e, "mira", xp)
	assert(not ok and motivo == "sem pontos")
	Carreira.limpar(e)
	assert(Carreira.pontosLivres(e, xp) == 2, "limpar devolve os pontos")
end)

test("efeitos: a árvore inteira com todos os passes respeita o teto de combate", function()
	local nos: { [string]: boolean } = {}
	for _, n in Carreira.ARVORE do
		nos[n.id] = true
	end
	local ef = Carreira.efeitos(nos)
	assert(math.abs(ef.health - 1.0609) < 1e-6)
	assert(ef.mags == 1 and ef.grenades == 1)
	local tudo = Vantagens.compute({ [Vantagens.BUNDLE] = true }, nil, ef)
	for k, d in Vantagens.KEYS do
		local v = tudo[k]
		if v and d.combat and d.kind ~= "count" then
			assert(v <= 1 + Vantagens.CAP + 1e-9 and v >= 1 - Vantagens.CAP - 1e-9, k .. " passou do teto")
		end
	end
	assert(tudo.mags == 2 and tudo.grenades == 2, "passe e árvore somam")
	local so = Vantagens.compute({}, nil, ef)
	assert(math.abs(so.speed - 1.02) < 1e-6, "a árvore vale sem passe")
	local semNada = Vantagens.compute({})
	assert(next(semNada) == nil, "sem passe e sem árvore não há efeito")
end)

test("prestígio: só no 55; o nível volta a 1 e a árvore e o XP ficam", function()
	local e = Carreira.padrao()
	assert(not Carreira.prestigiar(e, XP_MAX - 1), "antes do 55")
	e.nos.passo = true
	assert(Carreira.prestigiar(e, XP_MAX))
	assert(e.prestigio == 1 and e.base == XP_MAX and e.pago == 1 and e.nos.passo)
	assert((Carreira.nivel(XP_MAX, e.base)) == 1)
	assert(Carreira.pontosTotal(1, 1) == 12, "quem prestigiou tem a árvore inteira")
	assert(Progression.rankFor(XP_MAX) == Progression.rankFor(e.base), "a patente não muda")
	assert(math.abs(Carreira.multXp(3) - 1.06) < 1e-9)
	assert(math.abs(Carreira.multXp(99) - 1.2) < 1e-9, "bônus com teto")
	e.prestigio = Carreira.PRESTIGIO_MAX
	e.base = 0
	local ok, motivo = Carreira.podePrestigiar(e, XP_MAX)
	assert(not ok and motivo == "prestigio maximo")
end)

test("recompensa: cada nível paga uma vez e o XP antigo não paga de uma vez", function()
	local velho = Carreira.sanear(nil, Carreira.XP_NIVEL[20])
	assert(velho.pago == 20, "quem já jogava começa pago")
	assert(#Carreira.receber(velho, Carreira.XP_NIVEL[20]) == 0)
	local r = Carreira.receber(velho, Carreira.XP_NIVEL[22])
	assert(#r == 2 and r[1].nivel == 21 and r[2].nivel == 22)
	assert(#Carreira.receber(velho, Carreira.XP_NIVEL[22]) == 0, "não paga de novo")
	assert(Carreira.recompensa(10).caixa and not Carreira.recompensa(11).caixa)
	assert(Carreira.recompensa(5).ponto and not Carreira.recompensa(6).ponto)
end)

test("perfil: saneia lixo, nó sem o anterior cai e o prestígio maior vence entre servidores", function()
	local e = Carreira.sanear(
		{ base = -5, prestigio = 999, pago = "x", nos = { maos = true, passo = true, nada = true } },
		100
	)
	assert(e.base == 0 and e.prestigio == Carreira.PRESTIGIO_MAX and e.pago == 1)
	assert(e.nos.passo and not e.nos.maos and not e.nos.nada)
	assert(Carreira.sanear({ base = 900 }, 100).base == 100, "base nunca passa do XP")
	local a = { base = 10, prestigio = 2, pago = 5, nos = { passo = true } }
	local b = { base = 90, prestigio = 1, pago = 40, nos = {} }
	local m = Carreira.mesclar(b :: any, a :: any)
	assert(m.prestigio == 2 and m.base == 10 and m.nos.passo)
	local m2 = Carreira.mesclar(a :: any, b :: any)
	assert(m2.prestigio == 2 and m2.base == 10, "vale nos dois sentidos")
	local p = ProfileSchema.default()
	assert(p.carreira and p.carreira.prestigio == 0)
	local velho = ProfileSchema.migrate({ xp = Carreira.XP_NIVEL[12] })
	assert(velho.carreira.pago == 12, "perfil antigo entra sem pagar o passado")
	local mem =
		ProfileSchema.migrate({ xp = 1000, carreira = { base = 0, prestigio = 1, pago = 2, nos = { passo = true } } })
	local gravado = ProfileSchema.migrate({ xp = 1000 })
	local rec = ProfileSchema.migrate({ xp = 1000 })
	ProfileSchema.applySession(rec, gravado, mem, ProfileSchema.synced(mem))
	assert(rec.carreira.prestigio == 1 and rec.carreira.nos.passo, "o salvamento grava a carreira")
end)

test("vitrine: todas as medalhas, com categoria e progresso limitado à meta", function()
	local v = Carreira.vitrine({ kills = 500, revives = 3 }, { bronze_star = 123 })
	assert(#v == #Medalhas.LIST)
	for _, m in v do
		assert(table.find(Carreira.CATEGORIAS, m.categoria), m.id .. ": categoria")
		assert(Carreira.CATEGORIA_MEDALHA[m.id], m.id .. " sem categoria")
		assert(m.atual <= m.meta)
		if m.id == "bronze_star" then
			assert(m.ganha and m.atual == 100)
		elseif m.id == "socorro" then
			assert(not m.ganha and m.atual == 3)
		end
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
