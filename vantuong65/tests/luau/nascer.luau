--!strict
-- D-209 (prompt de interface §8): escolher onde nascer e confirmar no NASCER. Lógica pura do
-- Shared/NascerPedido e conferências de fonte do servidor (SpawnService) e das telas.
-- Uso, a partir de vantuong65/:  lune run tests/luau/nascer.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local NascerPedido = require("../../src/ReplicatedStorage/Shared/NascerPedido") :: any

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
-- o checkout do Windows tem CRLF
local function ler(p: string): string
	return (string.gsub(fs.readFile(p), "\r\n", "\n"))
end

local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
local M = "src/ServerScriptService/Modules/"

-- ===== estado e painel =====
test("estado: pronto, espera (com tempo ou sem) e bloqueado; nada escolhido", function()
	assert(NascerPedido.estado(nil) == "nenhum")
	assert(NascerPedido.estado({ wait = 0 }) == "pronto")
	assert(NascerPedido.estado({ wait = 0, ready = true }) == "pronto")
	assert(NascerPedido.estado({ wait = 3 }) == "espera")
	assert(NascerPedido.estado({ wait = 0, ready = false, why = "companheiro em combate" }) == "espera")
	assert(NascerPedido.estado({ wait = 9, blocked = true }) == "bloqueado", "bloqueado vale mais que a espera")
end)

test("painel: só o pronto habilita o NASCER; a espera e o motivo ficam escritos", function()
	local p = NascerPedido.painel({ name = "QG", wait = 0 }, false)
	assert(p.ativo and p.botao == "NASCER" and p.estado == "pronto", p.botao)
	local w = NascerPedido.painel({ name = "LZ", wait = 11.2 }, false)
	assert(not w.ativo and w.botao == "ESPERA 12 s" and w.linha == "Libera em 12 s", w.botao)
	local b = NascerPedido.painel({ name = "Vila", blocked = true, why = "inimigo perto" }, false)
	assert(not b.ativo and b.botao == "BLOQUEADO" and b.linha == "inimigo perto")
	local e = NascerPedido.painel({ name = "Squad", wait = 0, ready = false, why = "companheiro em combate" }, false)
	assert(not e.ativo and e.botao == "ESPERE" and e.linha == "companheiro em combate")
	local n = NascerPedido.painel(nil, false)
	assert(not n.ativo and n.linha == "Escolha um ponto na carta")
	for _, x in { p, w, b, e } do
		assert(x.tag ~= "", "cada estado tem a etiqueta com o símbolo")
	end
end)

test("painel: com o pedido em curso o botão trava (nada de pedido duplicado)", function()
	local p = NascerPedido.painel({ name = "QG", wait = 0 }, true)
	assert(not p.ativo and p.estado == "pedido" and p.botao == "NASCENDO…")
	assert(NascerPedido.emCurso(10, 10 + NascerPedido.ESPERA_S - 0.1))
	assert(not NascerPedido.emCurso(10, 10 + NascerPedido.ESPERA_S), "sem resposta, o botão volta")
	assert(not NascerPedido.emCurso(nil, 5))
end)

test("tipo do ponto em palavras", function()
	assert(NascerPedido.tipo({ id = "hq", kind = "hq" }) == "QG do lado")
	assert(NascerPedido.tipo({ id = "lz:2", kind = "rally" }) == "Zona de pouso")
	assert(NascerPedido.tipo({ id = "forward:1", kind = "rally" }) == "Reunião avançada")
	assert(NascerPedido.tipo({ id = "squad:US:1", kind = "rally" }) == "Reunião do squad")
	assert(NascerPedido.tipo({ id = "tunnel:E2", kind = "rally" }) == "Boca de túnel")
	assert(NascerPedido.tipo({ id = "mate:123", kind = "squad" }) == "Companheiro do squad")
	assert(NascerPedido.tipo({ id = "inplace" }) == "Onde você caiu")
	assert(NascerPedido.tipo({ id = "sp3", kind = "garrison" }) == "Posto fortificado")
	assert(NascerPedido.tipo({ id = "s2", kind = "rally" }) == "Ponto de reunião")
end)

test("escolhido: acha pelo id; a alternativa é o pronto mais perto (nunca o 'onde caiu')", function()
	local lista = {
		{ id = "a", name = "A", x = 0, z = 0, wait = 0 },
		{ id = "b", name = "B", x = 100, z = 0, wait = 0 },
		{ id = "c", name = "C", x = 10, z = 0, wait = 0, blocked = true, why = "inimigo perto" },
		{ id = "inplace", name = "Onde caiu", x = 12, z = 0, wait = 0 },
		{ id = "d", name = "D", x = 20, z = 0, wait = 5 },
	}
	assert(NascerPedido.acha(lista, "b").name == "B")
	assert(NascerPedido.acha(lista, "z") == nil and NascerPedido.acha(lista, nil) == nil)
	local alt = NascerPedido.alternativa(lista, 11, 0, "c")
	assert(alt and alt.id == "a", "o pronto mais perto de C é A (D espera, o onde caiu custa)")
	assert(NascerPedido.alternativa({ lista[3], lista[4] }, 0, 0, "c") == nil, "sem pronto: sem alternativa")
end)

test("motivos da recusa: bloqueado leva o motivo do ponto; código desconhecido vira o genérico", function()
	assert(NascerPedido.motivo("rodada", nil) == NascerPedido.MOTIVO.rodada)
	assert(NascerPedido.motivo("bloqueado", "inimigo perto") == "inimigo perto")
	assert(NascerPedido.motivo("bloqueado", nil) == NascerPedido.MOTIVO.bloqueado)
	assert(NascerPedido.motivo("xyz", nil) == NascerPedido.MOTIVO.falhou)
	assert(NascerPedido.motivo(nil, nil) == NascerPedido.MOTIVO.falhou)
end)

-- ===== servidor =====
test("servidor: a rodada antes de tudo; cada recusa responde com o motivo; o lugar é do servidor", function()
	local ss = ler(M .. "SpawnService.luau")
	local h = assert(
		string.find(
			ss,
			'Net.event("Spawn_Request").OnServerEvent:Connect(function(player, pointId, method, rodada)',
			1,
			true
		)
	)
	local fim = assert(string.find(ss, "\n\tend)\n", h, true))
	local corpo = string.sub(ss, h, fim)
	local q = assert(string.find(corpo, 'if pointId == "quick" then', 1, true))
	local r = assert(string.find(corpo, "if rodada ~= MatchService.rodada then", 1, true))
	local g = assert(string.find(corpo, 'not player:GetAttribute("Role") or alive(player)', 1, true))
	assert(q < r and r < g, "o jogar agora (sem papel ainda) antes; a rodada antes do resto")
	for _, cod in { '"fim"', '"rodada"', '"terreno"', '"papel"', '"bloqueado", why', '"espera"', '"ponto"' } do
		assert(string.find(corpo, "responde(" .. cod, 1, true), cod)
	end
	assert(string.find(corpo, "responde(inPlace(", 1, true) and string.find(corpo, "responde(mateSpawn(", 1, true))
	assert(string.find(corpo, "spawnAt(player, faction, sx, sz, nil, pt.id)\n\t\t\t\tresponde(nil)", 1, true))
	assert(string.find(corpo, "if not inf or inf.busy then", 1, true), "pedido repetido enquanto o primeiro corre")
	-- o cliente não manda coordenada: o handler só recebe o id, o pagamento e a rodada
	assert(not string.find(corpo, "Vector3", 1, true), "sem posição vinda do cliente")
	local net = ler("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(net, '"Spawn_Result"', 1, true))
end)

test("servidor: companheiro e onde caiu devolvem o motivo (caiu, em combate, sem lugar, sem créditos)", function()
	local ss = ler(M .. "SpawnService.luau")
	assert(
		string.find(
			ss,
			"local function mateSpawn(player: Player, faction: string, pointId: string): (string?, string?)",
			1,
			true
		)
	)
	assert(string.find(ss, 'return "sem_lugar", nil', 1, true))
	assert(string.find(ss, 'return "ponto", nil -- o companheiro caiu', 1, true))
	assert(string.find(ss, "local function inPlace(player: Player, method: string?): (string?, string?)", 1, true))
	assert(string.find(ss, 'return "compra", nil', 1, true) and string.find(ss, 'return "pagamento", nil', 1, true))
end)

-- ===== telas =====
test("cliente: todo pedido de nascer leva a rodada (SpawnTransition.pedir)", function()
	local st = ler(C .. "SpawnTransition.luau")
	assert(string.find(st, 'FireServer(id, method, ReplicatedStorage:GetAttribute("VT65Rodada"))', 1, true))
	assert(string.find(st, 'Net.event("Spawn_Result").OnClientEvent', 1, true), "a recusa para a ordem na hora")
	for _, arq in { "GameUI.client.luau", "JogarAgora.luau", "CasualtyScreen.luau" } do
		local s = ler(C .. arq)
		assert(string.find(s, "SpawnTransition.pedir(", 1, true), arq)
		for ini in string.gmatch(s, 'Net%.event%("Spawn_Request"%):FireServer%(([^)]*)%)') do
			assert(string.sub(ini, 1, 7) == '"quick"', string.format("%s: pedido sem a rodada (%s)", arq, ini))
		end
	end
end)

test("carta: clicar e tocar só escolhem; o escolhido tem anel âmbar; A no escolhido confirma", function()
	local ui = ler(C .. "GameUI.client.luau")
	assert(string.find(ui, "selecionar(pt) -- D-209: clicar ou tocar só escolhe", 1, true))
	assert(not string.find(ui, "insert(pt)", 1, true), "nada insere direto")
	assert(
		string.find(
			ui,
			"if pt and tostring(pt.id) ~= selId then\n\t\t\tselecionar(pt)\n\t\telse\n\t\t\tconfirmar()",
			1,
			true
		)
	)
	assert(string.find(ui, "NascerPedido.painel(pt, pendente() or SpawnTransition.busy())", 1, true))
	assert(string.find(ui, '"BotaoNascer"', 1, true) and string.find(ui, 'action = "map_select"', 1, true))
	assert(string.find(ui, 'GetAttributeChangedSignal("VT65Rodada")', 1, true), "partida nova limpa o destino")
	local cv = ler(C .. "CartaView.luau")
	assert(string.find(cv, 'ring.Name = "Escolhido"', 1, true) and string.find(cv, "w.ring.Visible = sel", 1, true))
	assert(string.find(cv, 'item(0, V.AMBAR, "ESCOLHIDO"', 1, true), "a legenda curta tem o escolhido")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
