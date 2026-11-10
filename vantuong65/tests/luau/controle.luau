--!strict
-- Testes da Parte 12 (controle). Uso: lune run tests/luau/controle.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local InputMap = require(S .. "InputMap")
local Rng = require(S .. "Rng")

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
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f", msg or "", a, b))
end
local D = InputMap.DEFAULTS

test("layout: sem conflito, Start nunca usado, Select só com navegação própria", function()
	local c = InputMap.conflicts(D)
	assert(#c == 0, "conflitos: " .. table.concat(c, "; "))
	for _, a in InputMap.ACTIONS do
		assert(not InputMap.RESERVED[a.pad or ""], a.id .. " usa botão reservado")
		if a.pad == "ButtonSelect" then
			assert(InputMap.SELECT_OK[a.ctx], a.id .. " usa Select fora do mapa/jogo")
		end
	end
end)

test("layout: toda ação de jogo tem botão de controle (exceções documentadas)", function()
	local padless = { give_up = "B segurado quando caído", tourniquet = "roda de equipamento" }
	for _, a in InputMap.ACTIONS do
		if not a.pad then
			assert(padless[a.id], a.id .. " sem botão de controle")
		end
	end
	-- remapear para um botão já usado gera conflito detectável
	local s = InputMap.validate({ remap = { ["infantry.reload"] = "ButtonY" } })
	assert(#InputMap.conflicts(s) > 0, "remapeamento conflitante não detectado")
end)

test("zona morta radial: circular, interna zera, externa satura", function()
	local x, y = InputMap.radialDeadzone(0.1, 0, 0.12, 0.95)
	assert(x == 0 and y == 0, "dentro da zona interna")
	local mags = {}
	for _, ang in { 0, 45, 90, 135, 200 } do
		local r = math.rad(ang)
		local ox, oy = InputMap.radialDeadzone(math.cos(r) * 0.6, math.sin(r) * 0.6, 0.12, 0.95)
		table.insert(mags, math.sqrt(ox * ox + oy * oy))
		near(math.atan2(oy, ox), math.atan2(math.sin(r), math.cos(r)), 1e-9, "direção preservada")
	end
	for i = 2, #mags do
		near(mags[i], mags[1], 1e-9, "mesma magnitude em qualquer direção (diagonal correta)")
	end
	local sx, sy = InputMap.radialDeadzone(0.7, 0.7, 0.12, 0.95)
	near(math.sqrt(sx * sx + sy * sy), 1, 1e-9, "diagonal cheia satura em 1")
end)

test("curvas: monotônicas, 0→0 e 1→1; exponencial mais fina no centro", function()
	for _, k in { "linear", "exponential", "dynamic" } do
		near(InputMap.curve(0, k), 0, 1e-12)
		near(InputMap.curve(1, k), 1, 1e-12)
		local last = -1
		for i = 0, 100 do
			local v = InputMap.curve(i / 100, k)
			assert(v >= last, k .. " não monotônica")
			last = v
		end
	end
	assert(InputMap.curve(0.5, "exponential") < InputMap.curve(0.5, "linear"))
end)

test("olhar: 180° em tempo real no quadril com aceleração; mira mais lenta; Y invertido", function()
	local st = { edgeT = 0 }
	local total, t = 0, 0
	while total < 180 do
		local yaw = InputMap.lookStep(1, 0, 1 / 60, D, "hip", st)
		total += yaw
		t += 1 / 60
		assert(t < 2, "giro de 180° demorou demais")
	end
	print(string.format("       180° no quadril com o analógico no máximo: %.2f s", t))
	assert(t < 0.85, "180° deveria levar menos de 0,85 s")
	local hip = InputMap.lookStep(0.5, 0, 0.1, D, "hip", { edgeT = 0 })
	local ads = InputMap.lookStep(0.5, 0, 0.1, D, "ads", { edgeT = 0 })
	local scope = InputMap.lookStep(0.5, 0, 0.1, D, "scope", { edgeT = 0 })
	assert(hip > ads and ads > scope, "sensibilidade por modo")
	local _, p1 = InputMap.lookStep(0, 0.8, 0.1, D, "hip", { edgeT = 0 })
	local inv = InputMap.validate({ invertY = true })
	local _, p2 = InputMap.lookStep(0, 0.8, 0.1, inv, "hip", { edgeT = 0 })
	assert(p1 > 0 and p2 < 0, "inverter Y")
	local dy, dp = InputMap.lookStep(0.05, 0.05, 1, D, "hip", { edgeT = 0 })
	assert(dy == 0 and dp == 0, "deriva do analógico parado não gira")
end)

test("gatilho: limiar ajustável", function()
	assert(InputMap.trigger(0.1, 0.15) == 0)
	near(InputMap.trigger(1, 0.15), 1, 1e-9)
	assert(InputMap.trigger(0.6, 0.15) > 0.4)
end)

test("assistência: só mirando, visível e até 150 m; no máximo 30%, nunca puxa", function()
	assert(InputMap.assistFactor("off", "ads", 50, 0, true, 0.3) == 1, "desligada")
	assert(InputMap.assistFactor("minimal", "hip", 50, 0, true, 0.3) == 1, "quadril")
	assert(InputMap.assistFactor("minimal", "ads", 50, 0, false, 0.3) == 1, "escondido atrás de vegetação/fumaça")
	assert(InputMap.assistFactor("minimal", "ads", 151, 0, true, 0.3) == 1, "além de 150 m")
	near(InputMap.assistFactor("minimal", "ads", 50, 0, true, 0.3), 0.7, 1e-9, "sobre o alvo")
	assert(InputMap.assistFactor("minimal", "scope", 100, 5, true, 0.3) == 1, "fora do cone")
	for i = 0, 50 do
		local f = InputMap.assistFactor("minimal", "ads", 30, i / 10, true, 0.3)
		assert(f >= 0.7 and f <= 1, "fator fora de [0,7; 1]")
	end
end)

test("roda radial: posições fixas, zona morta de 40%", function()
	assert(InputMap.wheelIndex(0, 1, 8) == 1, "topo")
	assert(InputMap.wheelIndex(1, 0, 8) == 3, "direita")
	assert(InputMap.wheelIndex(0, -1, 8) == 5, "baixo")
	assert(InputMap.wheelIndex(-1, 0, 8) == 7, "esquerda")
	assert(InputMap.wheelIndex(0.25, 0.25, 8) == nil, "dentro da zona morta")
	assert(InputMap.wheelIndex(0.7, 0.7, 8) == 2, "diagonal superior direita")
end)

test("mapa: ímã gruda no ponto mais próximo; LB/RB circulam", function()
	local pts = { { id = "a", x = 0.2, y = 0.2 }, { id = "b", x = 0.5, y = 0.5 } }
	local p = InputMap.magnet(0.48, 0.52, pts, 0.05)
	assert(p and p.id == "b")
	assert(InputMap.magnet(0.9, 0.9, pts, 0.05) == nil)
	assert(InputMap.cycle(3, nil, 1) == 1 and InputMap.cycle(3, 3, 1) == 1 and InputMap.cycle(3, 1, -1) == 3)
end)

test("tocar/segurar e configurações saneadas", function()
	assert(InputMap.pressKind(0.29, 0.3) == "tap" and InputMap.pressKind(0.31, 0.3) == "hold")
	local s = InputMap.validate({
		holdTime = 5,
		curve = "x",
		sensHipX = "rápido",
		invertY = true,
		remap = { ["infantry.fire"] = "ButtonStart" },
	})
	assert(s.holdTime == 0.6, "segurar limitado a 0,6 s")
	assert(s.curve == "exponential", "curva inválida ignorada")
	assert(s.sensHipX == D.sensHipX, "tipo errado ignorado")
	assert(s.invertY == true)
	assert(s.remap["infantry.fire"] == nil, "Start não pode ser remapeado")
	assert(InputMap.validate(nil).holdTime == 0.3)
end)

test("estados: menu, mapa e menu do Roblox cancelam mira, corrida, inclinação e roda", function()
	for _, ev in { "menu_open", "map_open", "roblox_menu_open", "disconnect", "downed", "die" } do
		local s = InputMap.newState()
		InputMap.event(s, "aim", true)
		InputMap.event(s, "sprint", true)
		InputMap.event(s, "lean", -1)
		InputMap.event(s, "wheel_open", "equip")
		local cancelled = InputMap.event(s, ev)
		assert(#cancelled == 4, ev .. " cancelou " .. #cancelled)
		assert(not s.aiming and not s.sprinting and s.lean == 0 and s.wheel == nil, ev)
	end
end)

test("estados: voltar ao jogo exige soltar todos os botões (nada fica preso)", function()
	local s = InputMap.newState()
	InputMap.event(s, "menu_open")
	assert(not InputMap.acceptsGame(s))
	InputMap.event(s, "menu_close")
	assert(not InputMap.acceptsGame(s), "aceitou antes de reler o controle")
	InputMap.event(s, "buttons_released")
	assert(InputMap.acceptsGame(s))
	-- controle desconectado pausa; volta só depois de soltar
	InputMap.event(s, "disconnect")
	assert(not InputMap.acceptsGame(s))
	InputMap.event(s, "reconnect")
	assert(not InputMap.acceptsGame(s))
	InputMap.event(s, "buttons_released")
	assert(InputMap.acceptsGame(s))
end)

test("transições: morrer, renascer, veículo, trocar assento, túnel, ser reanimado segurando", function()
	local s = InputMap.newState()
	InputMap.event(s, "die")
	assert(InputMap.activeContext(s) == "map", "morto vê a tela de spawn")
	InputMap.event(s, "respawn")
	InputMap.event(s, "buttons_released")
	assert(InputMap.activeContext(s) == "infantry")
	InputMap.event(s, "aim", true)
	assert(InputMap.activeContext(s) == "aim")
	InputMap.event(s, "vehicle_enter", "helicopter")
	assert(InputMap.activeContext(s) == "helicopter" and not s.aiming)
	InputMap.event(s, "seat_switch")
	assert(s.awaitRelease)
	InputMap.event(s, "buttons_released")
	InputMap.event(s, "vehicle_exit")
	InputMap.event(s, "buttons_released")
	assert(InputMap.activeContext(s) == "infantry")
	InputMap.event(s, "sprint", true)
	InputMap.event(s, "tunnel_enter")
	assert(not s.sprinting)
	InputMap.event(s, "downed")
	assert(InputMap.allowed(s, "give_up") and not InputMap.allowed(s, "fire"))
	InputMap.event(s, "revived") -- jogador ainda segurando um botão quando reanimado
	assert(not InputMap.acceptsGame(s))
	InputMap.event(s, "buttons_released")
	assert(InputMap.allowed(s, "fire"))
	-- mapa aberto durante a recarga: a recarga não é "segurada" e segue no servidor
	InputMap.event(s, "map_open")
	assert(InputMap.activeContext(s) == "map")
	InputMap.event(s, "map_close")
	InputMap.event(s, "buttons_released")
	assert(InputMap.activeContext(s) == "infantry")
end)

test("10.000 eventos aleatórios: invariantes nunca quebram", function()
	local evs = {
		"menu_open",
		"menu_close",
		"map_open",
		"map_close",
		"roblox_menu_open",
		"roblox_menu_close",
		"disconnect",
		"reconnect",
		"die",
		"respawn",
		"downed",
		"revived",
		"vehicle_enter",
		"vehicle_exit",
		"seat_switch",
		"tunnel_enter",
		"buttons_released",
		"aim",
		"sprint",
		"lean",
		"wheel_open",
		"wheel_close",
	}
	local rng = Rng.new(651818)
	local s = InputMap.newState()
	for i = 1, 10000 do
		local ev = evs[1 + math.floor(rng:next() * #evs)]
		local arg: any = nil
		if ev == "aim" or ev == "sprint" then
			arg = rng:next() < 0.5
			-- a camada de runtime só manda ações de jogo quando o jogo aceita
			if not InputMap.acceptsGame(s) then
				continue
			end
		elseif ev == "lean" then
			arg = math.floor(rng:next() * 3) - 1
			if not InputMap.acceptsGame(s) then
				continue
			end
		elseif ev == "wheel_open" then
			arg = "equip"
			if not InputMap.acceptsGame(s) then
				continue
			end
		elseif ev == "vehicle_enter" then
			arg = if rng:next() < 0.5 then "ground_vehicle" else "helicopter"
		end
		InputMap.event(s, ev, arg)
		local blocked = s.menus > 0 or s.map or s.robloxMenu or s.disconnected or not s.alive or s.downed
		if blocked then
			assert(not s.aiming and not s.sprinting and s.lean == 0 and s.wheel == nil, "segurado preso no passo " .. i)
		end
		if s.lean ~= 0 then
			assert(s.aiming, "inclinado sem mirar no passo " .. i)
		end
		local ctx = InputMap.activeContext(s)
		assert(InputMap.CONTEXTS[ctx], "contexto inválido " .. ctx)
	end
end)

test("layout padrão = tabela da Parte 12 (infantaria, veículos, mapa e menus)", function()
	local function pad(ctx: string, id: string): (string?, string?)
		for _, a in InputMap.ACTIONS do
			if a.ctx == ctx and a.id == id then
				return a.pad, a.padPress
			end
		end
		return nil, nil
	end
	local spec: { { string } } = {
		-- infantaria
		{ "infantry", "sprint", "ButtonL3", "press" },
		{ "infantry", "melee", "ButtonR3", "press" },
		{ "infantry", "aim", "ButtonL2", "press" },
		{ "infantry", "fire", "ButtonR2", "press" },
		{ "infantry", "equip_wheel", "ButtonL1", "hold" },
		{ "infantry", "last_item", "ButtonL1", "tap" },
		{ "infantry", "comm_wheel", "ButtonR1", "hold" },
		{ "infantry", "mark", "ButtonR1", "tap" },
		{ "aim", "lean_left", "ButtonL1", "press" },
		{ "aim", "lean_right", "ButtonR1", "press" },
		{ "aim", "hold_breath", "ButtonL3", "press" },
		{ "infantry", "crouch", "ButtonB", "tap" },
		{ "infantry", "prone", "ButtonB", "hold" },
		{ "infantry", "reload", "ButtonX", "tap" },
		{ "infantry", "interact", "ButtonX", "hold" },
		{ "infantry", "swap_weapon", "ButtonY", "tap" },
		{ "infantry", "bayonet", "ButtonY", "hold" },
		{ "infantry", "binoculars", "DPadUp", "press" },
		{ "infantry", "quick_bandage", "DPadDown", "press" },
		{ "infantry", "fire_mode", "DPadLeft", "tap" },
		{ "infantry", "zeroing", "DPadLeft", "hold" },
		{ "infantry", "radio_channel", "DPadRight", "press" },
		{ "global", "map", "ButtonSelect", "tap" },
		{ "global", "game_menu", "ButtonSelect", "hold" },
		-- veículos
		{ "ground_vehicle", "v_fire", "ButtonR2", "press" },
		{ "ground_vehicle", "v_optic", "ButtonL2", "press" },
		{ "ground_vehicle", "v_coax", "ButtonR1", "press" },
		{ "ground_vehicle", "v_ammo", "ButtonX", "press" },
		{ "ground_vehicle", "v_binoculars", "ButtonL2", "press" },
		{ "ground_vehicle", "v_mark", "ButtonR1", "press" },
		{ "ground_vehicle", "v_switch_seat", "ButtonY", "hold" },
		{ "ground_vehicle", "v_exit", "ButtonB", "hold" },
		{ "helicopter", "h_pedal_left", "ButtonL1", "press" },
		{ "helicopter", "h_pedal_right", "ButtonR1", "press" },
		{ "helicopter", "h_stabilize", "ButtonA", "hold" },
		{ "helicopter", "v_door_fire", "ButtonR2", "press" },
		{ "helicopter", "v_switch_seat", "ButtonY", "hold" },
		{ "helicopter", "v_exit", "ButtonB", "hold" },
		-- mapa e menus
		{ "map", "map_prev", "ButtonL1", "press" },
		{ "map", "map_next", "ButtonR1", "press" },
		{ "map", "map_select", "ButtonA", "press" },
		{ "map", "map_mark", "ButtonX", "press" },
		{ "menu", "ui_back", "ButtonB", "press" },
		{ "menu", "ui_tab_prev", "ButtonL1", "press" },
		{ "menu", "ui_tab_next", "ButtonR1", "press" },
		{ "menu", "ui_sub_prev", "ButtonL2", "press" },
		{ "menu", "ui_sub_next", "ButtonR2", "press" },
	}
	for _, row in spec do
		local p, kind = pad(row[1], row[2])
		assert(p == row[3], string.format("%s.%s: %s (esperado %s)", row[1], row[2], tostring(p), row[3]))
		assert(kind == row[4], string.format("%s.%s: %s (esperado %s)", row[1], row[2], tostring(kind), row[4]))
	end
	-- nenhum duplo toque: o tipo de toque é sempre press, tap ou hold
	for _, a in InputMap.ACTIONS do
		assert(a.padPress == "press" or a.padPress == "tap" or a.padPress == "hold", a.id)
	end
end)

test("rodas: 8 itens fixos por página; mensagens sem digitar", function()
	local Comms = require(S .. "Comms")
	for _, page in { Comms.EQUIP, Comms.COMM, Comms.COMMAND } do
		assert(#page == 8, "página com " .. #page .. " itens")
	end
	assert(Comms.EQUIP[1].id == "bandage" and Comms.COMM[1].id == "mark", "posições fixas mudaram")
	for _, it in Comms.COMM do
		assert(Comms.MESSAGES[it.id] or it.id == "mark" or it.id == "page_command", it.id .. " sem texto")
	end
	for _, id in { "corr_add", "corr_drop", "corr_right", "corr_left" } do
		assert(Comms.CORRECTION[id], id)
	end
end)

test("fumaça bloqueia a visão (bots e assistência), não a linha fora dela", function()
	local Smoke = require(S .. "Smoke")
	local clouds = { { x = 50, y = 0, z = 0, r = 10 } }
	assert(Smoke.blocks(0, 0, 0, 100, 0, 0, clouds), "atravessa a nuvem")
	assert(not Smoke.blocks(0, 0, 30, 100, 0, 30, clouds), "passa ao lado")
	assert(not Smoke.blocks(0, 0, 0, 30, 0, 0, clouds), "termina antes da nuvem")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
