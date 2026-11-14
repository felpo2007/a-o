--!strict
-- Testes do "jogar agora" (pedido do dono, 2026-11-13: "Botão 'jogar agora', que já põe o jogador
-- num squad e no último ponto de spawn usado"): perfil saneado, lado, squad, papel e ponto, a
-- resposta do servidor e as ligações no jogo. Uso, a partir de vantuong65/:
--   lune run tests/luau/jogaragora.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local J = require(S .. "JogarAgora") :: any
local Roles = require(S .. "Roles") :: any
local CompraVeiculo = require(S .. "CompraVeiculo") :: any

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

-- ===== perfil =====
test("perfil: só o que existe passa (lado, unidade, squad do lado, papel com arma, ponto)", function()
	local c = J.sanitize({ f = "US", id = "infantry", sq = "Bravo", role = "medic", pt = "rally:3" })
	assert(c.f == "US" and c.unit == "infantry" and c.sq == "Bravo" and c.role == "medic" and c.pt == "rally:3")
	-- lixo: unidade e papel de antes da D-108 viram os de agora; squad de outro lado e ponto pago, não
	local d = J.sanitize({ f = "VC", id = "armor", sq = "Alfa", role = "automatic_rifleman", pt = "inplace" })
	assert(d.f == "VC" and d.unit == "infantry" and d.sq == nil and d.role == "machine_gunner" and d.pt == nil)
	assert(d.w == nil, "a M14 não é arma do VC")
	assert(
		J.sanitize({ f = "VC", id = "x", role = "tank_crew" }).role == "rifleman",
		"lugar de veículo vira fuzileiro"
	)
	assert(J.sanitize({ f = "US", role = "inventado" }).role == nil)
	assert(next(J.sanitize(nil)) == nil and next(J.sanitize("x")) == nil)
	assert(J.sanitize({ pt = "quick" }).pt == nil, "o pedido não vira ponto")
	assert(J.sanitize({ pt = string.rep("a", 80) }).pt == nil, "ponto comprido demais")
	assert(J.sanitize({ pt = "rally:3; drop" }).pt == nil, "só letras, números, : _ -")
	-- ida e volta pelo perfil e pelo atributo
	local back = J.sanitize(J.pack(c))
	assert(back.f == c.f and back.unit == c.unit and back.sq == c.sq and back.role == c.role and back.pt == c.pt)
	local dec = J.decode(J.encode(c))
	assert(dec.f == "US" and dec.unit == "infantry" and dec.sq == "Bravo" and dec.role == "medic")
	assert(J.pack(c).id == "infantry", "a unidade fica em `id` (o campo `unit` do perfil)")
end)

-- ===== 1. lado =====
test("lado: o da última vez se cabe; senão o menor; cheio ou desequilibrando, nunca", function()
	assert(J.pickFaction("VC", 5, 5, 50) == "VC")
	assert(J.pickFaction("VC", 4, 5, 50) == "US", "VC a mais: o outro lado")
	assert(J.pickFaction(nil, 7, 3, 50) == "VC")
	assert(J.pickFaction(nil, 3, 3, 50) == "US")
	assert(J.pickFaction("US", 50, 50, 50) == nil, "os dois cheios")
	-- a mesma regra do Team_Choose: entra se mine < max e mine <= theirs
	assert(J.canJoin("US", 3, 3, 50) and not J.canJoin("US", 4, 3, 50))
end)

-- ===== 2. squad =====
local function sq(id: string, unit: string, name: string, n: number): any
	local members = {}
	for i = 1, n do
		members[i] = 1000 + i
	end
	return { id = id, unit = unit, name = name, members = members, leader = members[1], roles = {} }
end

test("squad: o da última vez com vaga; senão o mais cheio da unidade; senão um novo", function()
	local squads = { sq("US:Alfa", "infantry", "Alfa", 2), sq("US:Bravo", "infantry", "Bravo", 4) }
	local last = J.sanitize({ f = "US", id = "infantry", sq = "Alfa" })
	local op, arg = J.pickSquad("US", squads, last, 10)
	assert(op == "join" and arg == "US:Alfa", "o da última vez")
	-- sem o da última vez: o mais cheio (gente junto)
	op, arg = J.pickSquad("US", squads, J.sanitize({ f = "US", id = "infantry" }), 10)
	assert(op == "join" and arg == "US:Bravo")
	-- squad cheio (6) não entra
	local full = { sq("US:Alfa", "infantry", "Alfa", 6) }
	op, arg = J.pickSquad("US", full, last, 10)
	assert(op == "create" and arg == "infantry", tostring(op) .. " " .. tostring(arg))
	-- outro lado na última vez: não vale o squad nem a unidade
	op, arg = J.pickSquad("VC", { sq("VC:Tiểu đội 1", "infantry", "Tiểu đội 1", 1) }, last, 10)
	assert(op == "join" and arg == "VC:Tiểu đội 1")
end)

test("squad: unidade antiga (blindado) vira infantaria e nomes esgotados não abrem squad", function()
	-- D-108: só comando e infantaria
	local last = J.sanitize({ f = "US", id = "armor" })
	assert(last.unit == "infantry")
	local op, arg = J.pickSquad("US", {}, last, 5)
	assert(op == "create" and arg == "infantry", "blindado virou infantaria")
	op, arg = J.pickSquad("US", {}, last, Roles.HEAVY_UNLOCK)
	assert(op == "create" and arg == "infantry")
	-- todos os squads de infantaria existem e cheios: nada
	local all = {}
	for _, n in Roles.units.US.infantry.names do
		table.insert(all, sq("US:" .. n, "infantry", n, 6))
	end
	op, arg = J.pickSquad("US", all, J.sanitize({ f = "US" }), 50)
	assert(op == nil and arg == nil)
end)

-- ===== 3. papel =====
test("papel: o da última vez se cabe (vaga, posto, líder); senão fuzileiro; senão o 1º livre", function()
	local s = { unit = "infantry", leader = 7, roles = { [9] = "medic" } }
	-- D-108: o granadeiro salvo vira o fuzileiro com a M79
	local g = J.sanitize({ f = "US", role = "grenadier" })
	assert(g.role == "rifleman" and g.w == "m79")
	assert(J.pickRole("US", s, 5, g, 1) == "rifleman")
	assert(J.pickRole("US", s, 5, J.sanitize({ f = "US", role = "support" }), 1) == "support")
	assert(J.pickRole("US", s, 5, J.sanitize({ f = "US", role = "medic" }), 1) == "rifleman", "médico ocupado")
	assert(J.pickRole("US", s, 5, J.sanitize({ f = "US", role = "squad_leader" }), 1) == "rifleman", "só o líder")
	assert(J.pickRole("US", s, 7, J.sanitize({ f = "US", role = "squad_leader" }), 1) == "squad_leader")
	-- o próprio jogador não conta como ocupando a vaga dele
	assert(
		J.pickRole(
			"US",
			{ unit = "infantry", roles = { [5] = "medic" } },
			5,
			J.sanitize({ f = "US", role = "medic" }),
			1
		) == "medic"
	)
	-- D-108: atirador de elite no squad de infantaria, sem posto; 1 por squad; o observador vira ele
	assert(J.pickRole("US", s, 5, J.sanitize({ f = "US", role = "sniper" }), 1) == "sniper")
	assert(J.pickRole("US", s, 5, J.sanitize({ f = "US", role = "observer" }), 1) == "sniper")
	local taken = { unit = "infantry", leader = 7, roles = { [9] = "sniper" } }
	assert(J.pickRole("US", taken, 5, J.sanitize({ f = "US", role = "sniper" }), 1) == "rifleman", "vaga ocupada")
	-- posto: o comandante pede 3
	local cmd = { unit = "command", leader = 5, roles = {} }
	assert(J.pickRole("US", cmd, 5, J.sanitize({ f = "US", role = "commander" }), 3) == "commander")
	assert(J.pickRole("US", cmd, 5, J.sanitize({ f = "US", role = "commander" }), 1) == nil, "comandante pede 3")
end)

-- ===== 4. ponto =====
local function pt(id: string, kind: string, x: number, z: number, wait: number, blocked: boolean?, squad: boolean?): any
	return { id = id, kind = kind, x = x, z = z, wait = wait, blocked = blocked == true, squad = squad == true }
end

test("ponto: o último se ainda vale (mesmo esperando); bloqueado ou sumido, o melhor", function()
	local list = {
		pt("hq", "hq", 0, 0, 0),
		pt("rally:2", "rally", 100, 0, 5),
		pt("rally:3", "rally", 300, 0, 0),
	}
	assert(J.pickPoint(list, "rally:2", { objX = 400, objZ = 0 }).id == "rally:2", "o último, contando a espera")
	list[2].blocked = true
	assert(J.pickPoint(list, "rally:2", { objX = 400, objZ = 0 }).id == "rally:3", "bloqueado: o mais perto")
	assert(J.pickPoint(list, "tunnel:x", { objX = 400, objZ = 0 }).id == "rally:3", "sumido")
end)

test("ponto: junto do squad antes, QG por último, a espera pesa como caminhada, nunca o pago", function()
	local list = {
		pt("hq", "hq", 390, 0, 0),
		pt("rally:3", "rally", 350, 0, 0),
		pt("mate:42", "squad", 100, 0, 0, false, true),
		pt("inplace", "rally", 400, 0, 0),
	}
	assert(J.pickPoint(list, nil, { objX = 400, objZ = 0 }).id == "mate:42", "companheiro do squad")
	list[3].blocked = true
	assert(J.pickPoint(list, nil, { objX = 400, objZ = 0 }).id == "rally:3", "o pago e o QG ficam de fora")
	list[2].blocked = true
	assert(J.pickPoint(list, nil, { objX = 400, objZ = 0 }).id == "hq", "só o QG")
	list[1].blocked = true
	assert(J.pickPoint(list, nil, {}) == nil, "nada livre")
	-- espera: 10 s a mais valem 180 studs de caminhada (WAIT_STUDS = 18)
	local w = { pt("rally:1", "rally", 300, 0, 10), pt("rally:2", "rally", 150, 0, 0) }
	assert(J.WAIT_STUDS == 18)
	assert(J.pickPoint(w, nil, { objX = 400, objZ = 0 }).id == "rally:2")
	-- a idade da lista desconta a espera
	assert(J.waitLeft(w[1], 4) == 6 and J.waitLeft(w[1], 30) == 0)
end)

test("ponto com veículo: só QG, reunião de setor e reunião avançada (D-103)", function()
	local list = {
		pt("mate:7", "squad", 390, 0, 0, false, true),
		pt("tunnel:a", "garrison", 395, 0, 0),
		pt("forward:2:3", "rally", 200, 0, 0),
		pt("hq", "hq", 0, 0, 0),
	}
	local o = { vehicle = true, allowed = CompraVeiculo.pointAllowed, objX = 400, objZ = 0 }
	assert(J.pickPoint(list, "mate:7", o).id == "forward:2:3", "o último não serve para o veículo")
	list[3].blocked = true
	assert(J.pickPoint(list, nil, o).id == "hq")
end)

test("resposta: id ou motivo, com o número do pedido", function()
	local id, why, n = J.parseReply(J.reply("rally:3", nil, 17))
	assert(id == "rally:3" and why == nil and n == 17)
	id, why, n = J.parseReply(J.reply(nil, "Os dois lados estão cheios", 4))
	assert(id == nil and why == "Os dois lados estão cheios" and n == 4)
	assert(J.parseReply("lixo") == nil and J.parseReply(nil) == nil)
	-- id com dois-pontos e barra no motivo não confundem
	id, _, n = J.parseReply(J.reply("forward:2:3", nil, 99999))
	assert(id == "forward:2:3" and n == 99999)
end)

-- ===== ligações no jogo (texto do código) =====
local SRV = "src/ServerScriptService/Modules/"
local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
test("servidor: Spawn_Request 'quick' antes da checagem de papel; último ponto gravado ao nascer", function()
	local sp = fs.readFile(SRV .. "SpawnService.luau")
	local q = string.find(sp, 'if pointId == "quick" then', 1, true)
	local guard = string.find(sp, 'not player:GetAttribute("Role") or alive(player)', 1, true)
	assert(q and guard and q < guard, "o pedido rápido vem antes da checagem (o jogador ainda não tem papel)")
	assert(string.find(sp, "TeamService.quickJoin(player, ProgressionService.rank(player))", 1, true))
	assert(string.find(sp, 'player:SetAttribute("UltimoPonto", pointId)', 1, true))
	assert(string.find(sp, "spawnAt(player, faction, sx, sz, nil, pt.id)", 1, true), "ponto comum")
	assert(string.find(sp, "spawnAt(player, faction, at.X, at.Z, at, pointId)", 1, true), "companheiro")
	assert(not string.find(sp, "spawnAt(player, faction, pos.X, pos.Z, nil", 1, true), "onde caiu não é o último")
	assert(string.find(sp, "allowed = CompraVeiculo.pointAllowed", 1, true), "veículo só onde sai")
	local ts = fs.readFile(SRV .. "TeamService.luau")
	assert(string.find(ts, "function TeamService.quickJoin(", 1, true))
	assert(string.find(ts, "(prof :: any).unit = JogarAgora.pack(clean)", 1, true), "perfil")
	assert(string.find(ts, '"UltimaEscolha"', 1, true) and string.find(ts, "PlayerData.Loaded", 1, true))
end)

test("cliente: conta a espera, entra pela transição e cancela pelo voltar", function()
	local ja = fs.readFile(C .. "JogarAgora.luau")
	assert(string.find(ja, 'FireServer("quick", { n = S.n, v = S.vehicle })', 1, true))
	assert(string.find(ja, "SpawnTransition.go(", 1, true), "a mesma transição")
	assert(string.find(ja, 'Net.event("Spawn_Request"):FireServer(id)', 1, true), "o ponto pedido normal")
	assert(string.find(ja, "Regras.waitLeft(cur, age()) <= 0", 1, true), "só pede com a espera zerada")
	local ui = fs.readFile(C .. "GameUI.client.luau")
	local _, n = string.gsub(ui, "JogarAgora%.cancel%(%)", "")
	assert(n >= 2, "B na mesa e B/M na carta cancelam")
	assert(string.find(fs.readFile(C .. "GameMenu.client.luau"), 'Bus.fire("jogar_agora")', 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
