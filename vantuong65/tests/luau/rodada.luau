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
	assert(Rodada.proxima("jogo") == "fim")
	assert(Rodada.proxima("fim") == "comemoracao")
	assert(Rodada.total() == 38, "8 + 12 + 15 + 3")
	assert(Rodada.proxima("comemoracao") == "votacao")
	assert(Rodada.proxima("votacao") == "restauracao")
	assert(Rodada.proxima("restauracao") == "jogo")
	assert(Rodada.proxima("?") == "jogo")
	assert(Rodada.vale(3, 3) and not Rodada.vale(2, 3))
	for _, f in { "fim", "comemoracao", "votacao", "restauracao" } do
		assert(Rodada.DUR[f] > 0, f)
	end
end)

test("servidor: pontos da partida, ciclo depois do fim e o voto validado", function()
	local fs = require("@lune/fs")
	local ms = fs.readFile("src/ServerScriptService/Modules/MatchService.luau")
	for _, t in
		{
			"function MatchService.pontuar(p: Player, pontos: number, kind: string)",
			"MatchService.placar = {} -- D-193: pontos da partida do zero",
			"task.spawn(MatchService.afterEnd, winner)",
			"l.mortes += 1",
			"MatchService.rodada += 1",
			"RodadaService.start()",
		}
	do
		assert(string.find(ms, t, 1, true), "MatchService: " .. t)
	end
	local ps = fs.readFile("src/ServerScriptService/Modules/ProgressionService.luau")
	assert(string.find(ps, "MatchService.pontuar(p, rw.xp, kind)", 1, true), "os pontos vêm da progressão")
	local rs = fs.readFile("src/ServerScriptService/Modules/RodadaService.luau")
	for _, t in
		{
			'setFase("comemoracao", Rodada.DUR.comemoracao)',
			'setFase("votacao", Rodada.DUR.votacao)',
			'setFase("restauracao", Rodada.DUR.restauracao)',
			"MatchService.newMatch()",
			'if fase ~= "votacao" or type(id) ~= "string" or not Rodada.mapa(id) then',
			'ReplicatedStorage:SetAttribute("VT65Podio"',
			"Rodada.vale(minha, MatchService.rodada)",
		}
	do
		assert(string.find(rs, t, 1, true), "RodadaService: " .. t)
	end
	-- a ordem do ciclo: comemoração, votação, restauração, partida nova
	local a = string.find(rs, 'setFase("comemoracao"', 1, true)
	local b = string.find(rs, 'setFase("votacao"', 1, true)
	local c = string.find(rs, 'setFase("restauracao"', 1, true)
	local d = string.find(rs, "MatchService.newMatch()", 1, true)
	assert(a and b and c and d and a < b and b < c and c < d, "ordem do ciclo")
end)

test("tela: pódio congelado, empate sem vencedor, votação com o mapa real e as fases", function()
	local fs = require("@lune/fs")
	local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/FimDeRodada.client.luau")
	for _, t in
		{
			'decode("VT65Podio")',
			'title.Text = "EMPATE"',
			'decode("VT65Mapas")',
			'Net.event("Rodada_Votar"):FireServer(c.id)',
			'if ReplicatedStorage:GetAttribute("VT65Fase") == "votacao" then',
			"Players:GetPlayerByUserId(uid)", -- o personagem de quem ainda está no jogo
			"folder:FindFirstChild(lado)", -- quem saiu: o manequim do lado
			"Input.openMenu()",
			'ReplicatedStorage:GetAttribute("VT65FaseAte")',
		}
	do
		assert(string.find(src, t, 1, true), "FimDeRodada: " .. t)
	end
	assert(not string.find(src, 'string.format("VITÓRIA · %s"', 1, true), "frase inteira para a tradução")
end)

test("restauração: cada sistema devolve o seu, na ordem, e ninguém nasce entre as partidas", function()
	local fs = require("@lune/fs")
	local M = "src/ServerScriptService/Modules/"
	local rs = fs.readFile(M .. "RodadaService.luau")
	local ordem = {}
	for _, nome in { "corpos", "soltos", "armadilhas", "buracos", "crateras", "veiculos", "jogadores" } do
		local i = string.find(rs, string.format('RodadaService.aoRestaurar("%s"', nome), 1, true)
		assert(i, "registra " .. nome)
		table.insert(ordem, i)
	end
	for k = 2, #ordem do
		assert(ordem[k] > ordem[k - 1], "ordem da restauração")
	end
	local fw = fs.readFile(M .. "FieldWorkService.luau")
	assert(
		-- D-195: a obra guarda o terreno de antes na 1ª pazada
		string.find(fw, "b.mats, b.occs = workspace.Terrain:ReadVoxels(region, VOXEL)", 1, true),
		"buraco guarda o terreno"
	)
	assert(string.find(fw, "for i = n, 1, -1 do", 1, true), "buracos voltam do último ao primeiro")
	assert(string.find(fw, "buraco.parapeito =", 1, true), "o parapeito sai junto")
	local ex = fs.readFile(M .. "ExplosionService.luau")
	assert(string.find(ex, "table.insert(crateras,", 1, true), "cratera guarda o terreno")
	local vs = fs.readFile(M .. "VehicleService.luau")
	assert(string.find(vs, "if minha == epoca and type(spec)", 1, true), "reaparecer velho não duplica")
	assert(string.find(vs, "(VehicleService :: any).botLeave(occ)", 1, true), "bot sai do assento antes")
	local cs = fs.readFile(M .. "CorposService.luau")
	local a = string.find(cs, "table.clear(caindo)", 1, true)
	local b = a and string.find(cs, "c.model:Destroy()", a, true)
	assert(a and b, "primeiro a fila de quem cai, depois as cópias")
	local ss = fs.readFile(M .. "SpawnService.luau")
	assert(string.find(ss, "function SpawnService.restaurar(): number", 1, true))
	assert(string.find(ss, "inf.deathPos = nil", 1, true), "o onde caiu da partida velha some")
	local h = string.find(ss, 'Net.event("Spawn_Request").OnServerEvent:Connect', 1, true)
	local e = h and string.find(ss, "if MatchService.ended then", h, true)
	local q = h and string.find(ss, 'if pointId == "quick" then', h, true)
	assert(e and q and e < q, "entre as partidas ninguém nasce (nem o jogar agora)")
	local ts = fs.readFile(M .. "TrapService.luau")
	assert(string.find(ts, "function TrapService.limpar(): number", 1, true))
end)

-- D-193 (o Studio travou o início do servidor esperando "Rodada_Votar", que faltava na lista do Net):
-- todo remote usado no código está declarado no Shared/Net
test("todo Net.event/func/unreliable usado está declarado no Net", function()
	local fs = require("@lune/fs")
	-- além da lista do Net, os que o FrontService cria sozinho (função remote dele)
	local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
		.. fs.readFile("src/ServerScriptService/Modules/FrontService.luau")
	local faltam = {}
	local function walk(dir: string)
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path)
			elseif string.sub(name, -5) == ".luau" then
				local src = fs.readFile(path)
				for _, kind in { "event", "func", "unreliable" } do
					for remote in string.gmatch(src, "Net%." .. kind .. '%("([%w_]+)"%)') do
						if not string.find(net, '"' .. remote .. '"', 1, true) and not faltam[remote] then
							faltam[remote] = path
						end
					end
				end
			end
		end
	end
	walk("src")
	local list = {}
	for r, f in faltam do
		table.insert(list, r .. " (" .. f .. ")")
	end
	assert(#list == 0, "remotes sem declaração: " .. table.concat(list, ", "))
end)
print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
