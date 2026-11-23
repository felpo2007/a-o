--!strict
-- Testes de "nascer no squad" e da conversa no campo (pedido do dono, 2026-11-12).
-- Uso, a partir de vantuong65/: lune run tests/luau/comunicacao.luau
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local SpawnRules = require(S .. "SpawnRules") :: any
local Conversa = require(S .. "Conversa") :: any
local InputMap = require(S .. "InputMap") :: any

local M = 0.28

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
local function near(a: number, b: number, tol: number, msg: string?)
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f (tol %.4f)", msg or "", a, b, tol))
end

-- ===== nascer no companheiro =====
local function okMate(): any
	return {
		alive = true,
		downed = false,
		inBounds = true,
		inVehicle = false,
		inTunnel = false,
		nearestEnemyM = 200,
		sinceCombatS = math.huge,
		inContestedCapture = false,
	}
end

test("companheiro: livre quando vivo, de pé, longe do inimigo e fora de combate", function()
	assert(SpawnRules.mateCheck(okMate()) == nil)
end)

test("companheiro: cada regra recusa com um motivo", function()
	local cases: { { any } } = {
		{ "alive", false, "fora de campo" },
		{ "downed", true, "companheiro caído" },
		{ "inBounds", false, "fora da área de combate" },
		{ "inVehicle", true, "em veículo" },
		{ "inTunnel", true, "no túnel" },
		{ "inContestedCapture", true, "na área de captura em disputa" },
		{ "nearestEnemyM", 49.9, "inimigo a menos de 50 m" },
		{ "sinceCombatS", 9.9, "em combate" },
	}
	for _, c in cases do
		local m = okMate()
		m[c[1]] = c[2]
		local why = SpawnRules.mateCheck(m)
		assert(why == c[3], string.format("%s: %s", c[1], tostring(why)))
	end
	-- nos limites, pode
	local m = okMate()
	m.nearestEnemyM, m.sinceCombatS = 50, 10
	assert(SpawnRules.mateCheck(m) == nil, "50 m e 10 s exatos")
end)

test("companheiro: espera igual à da reunião (sem extra)", function()
	for _, deaths in { { 0 }, { 0, 60 }, { 0, 60, 100 } } do
		assert(SpawnRules.extraWait("squad", deaths, false) == SpawnRules.extraWait("rally", deaths, false))
		assert(SpawnRules.extraWait("squad", deaths, true) == SpawnRules.extraWait("rally", deaths, true))
	end
	near(SpawnRules.readyAt(0, SpawnRules.extraWait("squad", { 0 }, false), 0), 10, 1e-9, "10 s de espera")
end)

test("companheiro: área de captura em disputa só conta no raio e com disputa", function()
	local r = 50 / M
	local pts = { { x = 0, z = 0, contested = true }, { x = 1000, z = 0, contested = false } }
	assert(SpawnRules.inContestedCapture(10, 10, pts, r))
	assert(not SpawnRules.inContestedCapture(r + 1, 0, pts, r), "fora do raio")
	assert(not SpawnRules.inContestedCapture(1000, 0, pts, r), "ponto sem disputa")
end)

test("lugar: atrás do companheiro em relação ao inimigo (sem inimigo, nas costas)", function()
	local bx, bz = SpawnRules.behind(0, 0, 100, 0, 0, 1)
	near(bx, -1, 1e-9, "inimigo a leste: atrás é oeste")
	near(bz, 0, 1e-9)
	bx, bz = SpawnRules.behind(0, 0, nil, nil, 0, -1)
	near(bx, 0, 1e-9, "olhando para -Z: atrás é +Z")
	near(bz, 1, 1e-9)
	bx, bz = SpawnRules.behind(5, 5, 5, 5, 0, 0)
	near(bx * bx + bz * bz, 1, 1e-9, "caso degenerado ainda é unitário")
end)

test("lugar: 2–4 m dele, primeiro bem atrás a 3 m, nunca na frente", function()
	local mx, mz = 100, -200
	local ex, ez = 100 + 300, -200 -- inimigo a leste
	local bx, bz = SpawnRules.behind(mx, mz, ex, ez, 0, 1)
	local spots = SpawnRules.mateSpots(mx, mz, bx, bz, M)
	local C = SpawnRules.MATE
	local dirs = 1 + 2 * math.floor(C.maxSideDeg / C.stepDeg)
	assert(#spots == dirs * 3, "candidatos: " .. #spots)
	local first = spots[1]
	near((first.x - mx) * M, -3, 1e-6, "primeiro: 3 m a oeste")
	near((first.z - mz) * M, 0, 1e-6)
	local tx, tz = (ex - mx) / 300, (ez - mz) / 300 -- rumo do inimigo
	for i, s in spots do
		local dx, dz = (s.x - mx) * M, (s.z - mz) * M
		local d = math.sqrt(dx * dx + dz * dz)
		assert(d >= C.minM - 1e-6 and d <= C.maxM + 1e-6, string.format("candidato %d a %.2f m", i, d))
		assert((dx * tx + dz * tz) / d <= 1e-6, string.format("candidato %d na frente", i))
	end
end)

-- ===== conversa =====
local function who(id: number, x: number, z: number, opts: any?): any
	local o = opts or {}
	return {
		userId = id,
		faction = o.faction or "US",
		squad = o.squad,
		inField = if o.inField == nil then true else o.inField,
		downed = o.downed == true,
		x = x,
		z = z,
		radio = o.radio == true,
	}
end

test("texto de perto: só em campo e a até 40 m", function()
	local a, b = who(1, 0, 0), who(2, 40, 0)
	assert(Conversa.nearText(a, b), "40 m exatos")
	assert(not Conversa.nearText(a, who(2, 40.1, 0)), "40,1 m")
	assert(not Conversa.nearText(who(1, 0, 0, { inField = false }), b), "lobby não fala para o campo")
	assert(not Conversa.nearText(a, who(2, 1, 0, { inField = false })), "lobby não lê o campo")
	assert(Conversa.nearText(a, who(3, 10, 0, { faction = "VC" })), "inimigo perto lê, como no real")
	assert(not Conversa.nearText(nil, b))
end)

test("geral do Roblox: só fora do campo", function()
	local lobbyA, lobbyB = who(1, 0, 0, { inField = false }), who(2, 0, 0, { inField = false })
	assert(Conversa.generalText(lobbyA, lobbyB))
	assert(not Conversa.generalText(who(1, 0, 0), lobbyB), "em campo não envia")
	assert(not Conversa.generalText(lobbyA, who(2, 0, 0)), "em campo não recebe")
end)

test("membros: perto = em campo; squad e lado = todos do squad e do lado", function()
	local all = {
		who(1, 0, 0, { squad = "US:Alfa" }),
		who(2, 0, 0, { squad = "US:Alfa", inField = false }),
		who(3, 0, 0, { faction = "VC", squad = "VC:Tổ 1" }),
		who(4, 0, 0, { inField = false }),
	}
	all[4].faction = nil -- ainda sem lado
	local m = Conversa.members(all)
	assert(m.near[1] and not m.near[2] and m.near[3] and not m.near[4], "perto")
	assert(m.squads["US:Alfa"][1] and m.squads["US:Alfa"][2] and not m.squads["US:Alfa"][3], "squad")
	assert(m.sides.US[1] and m.sides.US[2] and m.sides.VC[3] and not m.sides.US[4], "lado")
end)

test("voz: perto chega a todos a até 50 m; o rádio só ao próprio squad, nunca ao inimigo", function()
	local sp = who(1, 0, 0, { squad = "US:Alfa" })
	local mateFar = who(2, 500, 0, { squad = "US:Alfa" })
	local mateLobby = who(3, 0, 0, { squad = "US:Alfa", inField = false })
	local otherSquad = who(4, 600, 0, { squad = "US:Bravo" })
	local enemyNear = who(5, 30, 0, { faction = "VC", squad = "US:Alfa" }) -- nome igual de outro lado
	local enemyFar = who(6, 400, 0, { faction = "VC", squad = "US:Alfa" })
	local allyNear = who(7, 49, 0, { squad = "US:Charlie" })
	local all = { sp, mateFar, mateLobby, otherSquad, enemyNear, enemyFar, allyNear }
	local function has(list: { number }, id: number): boolean
		return table.find(list, id) ~= nil
	end
	local quiet = Conversa.voiceAllow(sp, all)
	assert(has(quiet, 5) and has(quiet, 7), "perto: inimigo e aliado a até 50 m")
	assert(not has(quiet, 2) and not has(quiet, 3) and not has(quiet, 6), "sem rádio, ninguém longe")
	sp.radio = true
	local radio = Conversa.voiceAllow(sp, all)
	assert(has(radio, 2) and has(radio, 3), "rádio: squad em qualquer lugar (e esperando para nascer)")
	assert(not has(radio, 4), "rádio: outro squad não")
	assert(not has(radio, 6), "rádio: inimigo longe nunca")
	assert(not has(radio, 1), "sem eco")
	for i = 2, #radio do
		assert(radio[i - 1] < radio[i], "lista em ordem")
	end
	local lobby = who(1, 0, 0, { squad = "US:Alfa", inField = false, radio = true })
	assert(#Conversa.voiceAllow(lobby, all) == 0, "fora do campo ninguém ouve")
end)

test("rádio: só em campo, de pé e com squad", function()
	assert(Conversa.radioCheck(true, false, "US:Alfa") == nil)
	assert(Conversa.radioCheck(false, false, "US:Alfa") == "fora de campo")
	assert(Conversa.radioCheck(true, true, "US:Alfa") == "caído")
	assert(Conversa.radioCheck(true, false, nil) == "sem squad")
end)

test("curva da voz: cheia até 3 m, cai sem subir e some aos 40 m", function()
	near(Conversa.nearVolume(0), 1, 1e-9)
	near(Conversa.nearVolume(3), 1, 1e-9)
	near(Conversa.nearVolume(40), 0, 1e-9)
	near(Conversa.nearVolume(80), 0, 1e-9)
	local prev = 1
	for d = 0, 45, 0.5 do
		local v = Conversa.nearVolume(d)
		assert(v <= prev + 1e-9, string.format("subiu em %.1f m", d))
		prev = v
	end
	local studs = Conversa.attenuationStuds(M)
	near(studs[40 / M], 0, 1e-9, "40 m em studs")
	near(studs[3 / M], 1, 1e-9, "3 m em studs")
	assert(Conversa.C.voiceStreamM > Conversa.C.voiceNearM, "o servidor libera além de onde a voz some")
end)

test("nomes, listas e ícone de fala", function()
	assert(Conversa.squadChannel("US:Alfa") == "VT65Squad_US_Alfa")
	assert(not string.find(Conversa.squadChannel("VC:Tổ 1"), "[:%s]"), "sem ':' nem espaço")
	assert(Conversa.sameIds({ 1, 2 }, { 1, 2 }) and not Conversa.sameIds({ 1 }, { 1, 2 }))
	local talking, at = Conversa.speaking(0.05, 10, nil)
	assert(talking and at == 10)
	talking = Conversa.speaking(0, 10.3, at)
	assert(talking, "segura o ícone depois da sílaba")
	talking = Conversa.speaking(0, 10.5, at)
	assert(not talking, "apaga depois de 0,4 s")
end)

-- ===== botão, remotes e configuração =====
test("botão do rádio: ↓ segurado e Caps Lock em todo contexto de jogo, sem conflito", function()
	local found: { [string]: boolean } = {}
	for _, a in InputMap.ACTIONS do
		if a.id == "radio_talk" then
			assert(a.pad == "DPadDown" and a.padPress == "hold", a.ctx .. ": controle")
			assert(a.key == "CapsLock" and a.keyPress == "press", a.ctx .. ": teclado")
			found[a.ctx] = true
		elseif a.id == "quick_bandage" then
			assert(a.padPress == "tap", "↓ tocar segue a bandagem rápida")
		end
	end
	assert(found.infantry and found.ground_vehicle and found.helicopter, "infantaria e veículos")
	assert(#InputMap.conflicts(InputMap.DEFAULTS) == 0, table.concat(InputMap.conflicts(InputMap.DEFAULTS), "; "))
	assert(#InputMap.keyConflicts(InputMap.DEFAULTS) == 0, table.concat(InputMap.keyConflicts(InputMap.DEFAULTS), "; "))
	assert(not InputMap.KEY_RESERVED.CapsLock, "Caps Lock livre")
	-- caído não abre o rádio (o servidor também recusa)
	local st = InputMap.newState()
	InputMap.event(st, "downed")
	assert(not InputMap.allowed(st, "radio_talk"))
end)

test("remotes, pontos do squad na carta e voz no place", function()
	local netSrc = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(netSrc, '"Voz_Radio"', 1, true) and string.find(netSrc, '"Voz_Estado"', 1, true))
	-- o ponto de companheiro vai no mesmo Spawn_State, com os campos da carta
	local sp = fs.readFile("src/ServerScriptService/Modules/SpawnService.luau")
	local body = string.match(sp, "local function mateEntries.-\nend\n") or ""
	for _, field in { 'kind = "squad"', "userId =", "name =", "x =", "z =", "ready =", "why =", "wait =" } do
		assert(string.find(body, field, 1, true), "falta " .. field)
	end
	local proj = net.jsonDecode(fs.readFile("default.project.json"))
	local vcs = proj.tree.VoiceChatService["$properties"]
	assert(vcs.UseAudioApi == "Enabled" and vcs.EnableDefaultVoice == false, "VoiceChatService no projeto")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
