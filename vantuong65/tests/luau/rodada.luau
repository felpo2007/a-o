--!strict
-- Fim de partida e partida nova (D-193; Shared/Rodada): pódio, desempate, empate, votação com um
-- mapa e as fases. Uso: lune run tests/luau/rodada.luau
local process = require("@lune/process")

local Rodada = require("../../src/ReplicatedStorage/Shared/Rodada") :: any

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

local function l(id: string, lado: string, pontos: number, abates: number?, mortes: number?, ordem: number?): any
	return {
		id = id,
		nome = "J" .. id,
		lado = lado,
		pontos = pontos,
		abates = abates or 0,
		mortes = mortes or 0,
		ordem = ordem or 1,
	}
end

test("pódio: os três melhores do time que venceu, na ordem", function()
	local linhas = {
		l("1", "US", 300),
		l("2", "US", 500),
		l("3", "VC", 900),
		l("4", "US", 100),
		l("5", "US", 400),
	}
	local p = Rodada.podio(linhas, "US")
	assert(#p == 3, "três")
	assert(p[1].id == "2" and p[2].id == "5" and p[3].id == "1", "ordem pelos pontos")
	for _, x in p do
		assert(x.lado == "US", "só o time que venceu")
	end
end)

test("pódio: desempate por abates, mortes, entrada e nome", function()
	local p = Rodada.podio({
		l("a", "VC", 200, 3, 5, 1),
		l("b", "VC", 200, 4, 9, 2),
		l("c", "VC", 200, 4, 2, 3),
	}, "VC")
	assert(p[1].id == "c" and p[2].id == "b" and p[3].id == "a", "abates, depois menos mortes")
	local q = Rodada.podio({ l("x", "US", 10, 1, 1, 5), l("y", "US", 10, 1, 1, 2) }, "US")
	assert(q[1].id == "y", "quem entrou antes")
	-- a mesma entrada dá sempre a mesma ordem (o resultado congela)
	local r1 = Rodada.podio({ l("m", "US", 1), l("n", "US", 1) }, "US")
	local r2 = Rodada.podio({ l("n", "US", 1), l("m", "US", 1) }, "US")
	assert(r1[1].id == r2[1].id, "desempate estável")
end)

test("pódio: menos de três e empate entre os lados", function()
	assert(#Rodada.podio({ l("1", "US", 5) }, "US") == 1, "só o que houver")
	assert(#Rodada.podio({ l("1", "VC", 5) }, "US") == 0, "ninguém do lado que venceu")
	local d = Rodada.podio({ l("1", "US", 5), l("2", "VC", 9), l("3", "US", 7), l("4", "VC", 1) }, "draw")
	assert(#d == 3 and d[1].id == "2", "empate: os melhores dos dois lados, sem vencedor")
end)

test("votação: aparece com um mapa só; sem voto, o mapa que existe; voto inválido não conta", function()
	assert(#Rodada.MAPAS >= 1, "pelo menos um mapa")
	local id, conta = Rodada.apurar({})
	assert(id == Rodada.MAPAS[1].id and conta[id] == 0, "ninguém votou")
	local id2, conta2 = Rodada.apurar({ a = "vantuong", b = "vantuong", c = "inventado" })
	assert(id2 == "vantuong" and conta2.vantuong == 2 and conta2.inventado == nil, "só mapa real conta")
	-- mais de um mapa (preparado para depois): o mais votado; empate, o primeiro da lista
	local mapas = { { id = "a", nome = "A", carta = "" }, { id = "b", nome = "B", carta = "" } }
	assert(Rodada.apurar({ x = "b", y = "b", z = "a" }, mapas) == "b")
	assert(Rodada.apurar({ x = "a", y = "b" }, mapas) == "a", "empate: o primeiro")
	assert(Rodada.mapa("vantuong") ~= nil and Rodada.mapa("x") == nil)
end)

test("fases em ordem e a rodada velha não mexe na nova", function()
	assert(Rodada.proxima("jogo") == "comemoracao")
	assert(Rodada.proxima("comemoracao") == "votacao")
	assert(Rodada.proxima("votacao") == "restauracao")
	assert(Rodada.proxima("restauracao") == "jogo")
	assert(Rodada.proxima("?") == "jogo")
	assert(Rodada.vale(3, 3) and not Rodada.vale(2, 3))
	for _, f in { "comemoracao", "votacao", "restauracao" } do
		assert(Rodada.DUR[f] > 0, f)
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
