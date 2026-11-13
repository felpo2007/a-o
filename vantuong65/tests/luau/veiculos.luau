--!strict
-- Testes do movimento dos veículos (Lune): chão, motor e câmbio, lagarta, ladeira, lama, água,
-- mola visual, laço da lagarta, som e UH-34D. Uso: lune run tests/luau/veiculos.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local VehicleDrive = require(S .. "VehicleDrive") :: any
local Vehicles = require(S .. "Vehicles") :: any

local G = 9.80665
local DT = 1 / 60

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

local function spec(id: string): any
	return Vehicles.SPECS[id]
end

-- roda `secs` segundos com comando e ambiente fixos; devolve o estado
local function run(id: string, secs: number, inp: any, env: any, st: any?): any
	local s = st or VehicleDrive.newState()
	for _ = 1, math.floor(secs / DT + 0.5) do
		VehicleDrive.step(spec(id), s, inp, env, DT)
	end
	return s
end

-- tempo (s) até passar de `kmh` acelerando a fundo
local function timeTo(id: string, kmh: number, ground: string): number
	local s = VehicleDrive.newState()
	local t = 0
	while s.v * 3.6 < kmh and t < 120 do
		VehicleDrive.step(spec(id), s, { throttle = 1, steer = 0 }, { ground = ground }, DT)
		t += DT
	end
	return t
end

test("chão: material do terreno, lâmina do arrozal (PaddyWater), dique e chuva", function()
	assert(VehicleDrive.groundOf("Grass", "PaddyWater", "PaddyWater") == "paddy")
	assert(VehicleDrive.groundOf("SmoothPlastic", nil, "PaddyWater") == "paddy")
	assert(VehicleDrive.groundOf("LeafyGrass", nil, "Dike") == "earth", "dique é terra batida")
	assert(VehicleDrive.groundOf("Mud") == "mud" and VehicleDrive.groundOf("Sand") == "sand")
	assert(VehicleDrive.groundOf("LeafyGrass") == "forest" and VehicleDrive.groundOf("Grass") == "grass")
	-- D-100: o terreno "Ground" é a estrada de terra do mapa (estrada, beco e praça)
	assert(VehicleDrive.groundOf("Water") == "water" and VehicleDrive.groundOf("Ground") == "dirt")
	assert(VehicleDrive.groundOf(nil) == "earth" and VehicleDrive.groundOf("Asphalt") == "road")
	local dry, wet = VehicleDrive.ground("grass", 0), VehicleDrive.ground("grass", 1)
	assert(wet.mu < dry.mu and wet.crr > dry.crr and wet.ride < dry.ride, "chuva enlameia o capim")
	assert(wet.fx == "mud", "capim molhado joga barro, não poeira")
	assert(VehicleDrive.ground("sand", 1).mu == VehicleDrive.ground("sand", 0).mu, "areia não enlameia")
end)

test("motor: a rotação sobe com atraso e o tanque de 45 t arranca devagar (mais que o Ontos)", function()
	local s = run("m48a3", 0.2, { throttle = 1, steer = 0 }, { ground = "road" })
	assert(s.rpm < 0.6, string.format("rotação em 0,2 s: %.2f (o diesel ainda está enchendo)", s.rpm))
	local v1 = run("m48a3", 1, { throttle = 1, steer = 0 }, { ground = "road" }).v
	local v5 = run("m48a3", 5, { throttle = 1, steer = 0 }, { ground = "road" }).v
	assert(v1 * 3.6 < 6, string.format("M48 em 1 s: %.1f km/h", v1 * 3.6))
	assert(v5 > v1 * 2)
	local m10, o10 = timeTo("m48a3", 10, "road"), timeTo("ontos", 10, "road")
	local m30, o30 = timeTo("m48a3", 30, "road"), timeTo("ontos", 30, "road")
	assert(m30 > o30, "o M48 demora mais a chegar a 30 km/h")
	assert(m30 > 8, string.format("M48 0–30 km/h em %.1f s (arranca devagar)", m30))
	print(
		string.format(
			"       estrada: 0–10 km/h M48 %.1f s, Ontos %.1f s; 0–30 km/h M48 %.1f s, Ontos %.1f s; M48 em 1 s %.1f km/h, em 5 s %.1f km/h",
			m10,
			o10,
			m30,
			o30,
			v1 * 3.6,
			v5 * 3.6
		)
	)
end)

test("câmbio: duas faixas no M48 (ficha); na troca a rotação cai e volta a subir", function()
	local s = VehicleDrive.newState()
	local before, dipped, gear2At = 0, 2, nil :: number?
	local t = 0
	while t < 60 do
		local g0 = s.gear
		local r0 = s.rpm
		VehicleDrive.step(spec("m48a3"), s, { throttle = 1, steer = 0 }, { ground = "road" }, DT)
		t += DT
		if g0 == 1 and s.gear == 2 then
			before, gear2At = r0, t
		end
		if gear2At and t < (gear2At :: number) + 1.0 then
			dipped = math.min(dipped, s.rpm)
		end
	end
	assert(gear2At, "não trocou para a 2ª")
	assert(dipped < before - 0.1, string.format("rotação na troca: %.2f → %.2f", before, dipped))
	assert(s.gear == 2 and s.rpm > dipped, "volta a subir na 2ª")
	print(
		string.format("       troca 1ª→2ª aos %.1f s: rotação %.2f → %.2f", gear2At :: number, before, dipped)
	)
end)

test("velocidade máxima: M48A3 48 km/h na estrada (ficha) e bem menos fora dela", function()
	local rows = {}
	for _, id in { "m48a3", "ontos", "lvtp5" } do
		local line = {}
		for _, g in { "road", "earth", "grass", "forest", "sand", "mud", "paddy" } do
			local v = run(id, 120, { throttle = 1, steer = 0 }, { ground = g }).v * 3.6
			local cap = VehicleDrive.topSpeed(spec(id), g) * 3.6
			-- o teto do chão (suspensão) ou a potência contra o rolamento, o que vier antes
			assert(v <= cap + 0.6, string.format("%s em %s: %.1f acima do teto %.1f", id, g, v, cap))
			if g == "road" or g == "grass" then
				near(v, cap, 0.6, id .. " em " .. g)
			end
			table.insert(line, string.format("%s %.0f", g, v))
		end
		table.insert(rows, id .. ": " .. table.concat(line, ", "))
	end
	local m = spec("m48a3")
	near(VehicleDrive.topSpeed(m, "road") * 3.6, 48, 0.01, "estrada")
	assert(VehicleDrive.topSpeed(m, "grass") * 3.6 < 35 and VehicleDrive.topSpeed(m, "paddy") * 3.6 < 17)
	for _, r in rows do
		print("       " .. r .. " km/h")
	end
end)

test("teto na água: lâmina rasa conta como lama; funda para o tanque e o anfíbio nada", function()
	local m, l = spec("m48a3"), spec("lvtp5")
	local mud = VehicleDrive.topSpeed(m, "mud")
	near(VehicleDrive.topSpeed(m, "water", nil, 0.03), mud, 1e-6, "M48 em lâmina de 3 cm")
	assert(VehicleDrive.topSpeed(m, "water", nil, 2) == 0, "M48 em 2 m de água: afoga")
	assert(VehicleDrive.topSpeed(m, "water") == 0, "fundura desconhecida: como funda")
	near(VehicleDrive.topSpeed(l, "water", nil, 0.5), VehicleDrive.topSpeed(l, "mud"), 1e-6, "LVTP-5 no raso")
	assert(VehicleDrive.topSpeed(l, "water", nil, 3) > 0, "LVTP-5 nada")
	-- o passo faz o mesmo: o M48 anda na lâmina rasa
	local v = run("m48a3", 30, { throttle = 1, steer = 0 }, { ground = "water", waterDepthM = 0.03 }).v
	assert(v > 1, string.format("M48 na lâmina rasa: %.2f m/s", v))
end)

test("freio: freia mais que o freio-motor e não engata a ré sozinho; parado, a ré anda", function()
	local env = { ground = "grass" }
	local s = run("m48a3", 40, { throttle = 1, steer = 0 }, env)
	local v0 = s.v
	local braked = table.clone(s)
	local coast = table.clone(s)
	local tb, tc = 0, 0
	while braked.v > 0 and tb < 60 do
		VehicleDrive.step(spec("m48a3"), braked, { throttle = -1, steer = 0 }, env, DT)
		tb += DT
	end
	while coast.v > 0 and tc < 120 do
		VehicleDrive.step(spec("m48a3"), coast, { throttle = 0, steer = 0 }, env, DT)
		tc += DT
	end
	assert(tb < tc / 3, string.format("freando %.1f s, solto %.1f s", tb, tc))
	assert(braked.v >= -0.01, "o freio para, não inverte")
	run("m48a3", 8, { throttle = -1, steer = 0 }, env, braked)
	assert(braked.v < -1 and braked.gear == -1, "parado, segurar a ré anda para trás")
	near(braked.v * 3.6, -48 * 0.3 * math.min(0.65 / 0.75, 1), 1.0, "ré limitada")
	print(
		string.format(
			"       capim a %.0f km/h: para em %.1f s freando e %.1f s no freio-motor; ré %.0f km/h",
			v0 * 3.6,
			tb,
			tc,
			braked.v * 3.6
		)
	)
end)

test("lagarta: gira no lugar; em movimento a curva abre com a velocidade e come velocidade", function()
	local env = { ground = "earth" }
	local s = run("m48a3", 3, { throttle = 0, steer = 1 }, env)
	near(s.yawRate, -math.rad(20), math.rad(1.5), "M48 gira no lugar (direita = guinada negativa)")
	assert(math.abs(s.v) < 0.05, "girar no lugar não anda")
	local o = run("ontos", 3, { throttle = 0, steer = -1 }, env)
	assert(o.yawRate > 0 and o.yawRate > math.abs(s.yawRate), "Ontos gira mais rápido, para a esquerda")
	local function radius(thr: number): (number, number)
		local st = run("m48a3", 40, { throttle = thr, steer = 0 }, env)
		run("m48a3", 6, { throttle = thr, steer = 1 }, env, st)
		return math.abs(st.v / st.yawRate), st.v
	end
	local rSlow, vSlow = radius(0.4)
	local rFast, vFast = radius(1)
	assert(rFast > rSlow * 1.5, string.format("raio %.1f m devagar, %.1f m rápido", rSlow, rFast))
	local straight = run("m48a3", 46, { throttle = 1, steer = 0 }, env).v
	assert(vFast < straight - 0.3, "a curva gasta velocidade")
	-- ré como carro: segurando a ré e a direita, a carroceria gira para a esquerda (traseira à direita)
	local r = run("m48a3", 10, { throttle = -1, steer = 0 }, env)
	run("m48a3", 2, { throttle = -1, steer = 1 }, env, r)
	assert(r.yawRate > 0, "de ré, o comando é como no carro")
	print(
		string.format(
			"       terra: raio %.1f m a %.0f km/h e %.1f m a %.0f km/h; giro no lugar M48 %.0f°/s, Ontos %.0f°/s",
			rSlow,
			vSlow * 3.6,
			rFast,
			vFast * 3.6,
			math.deg(math.abs(s.yawRate)),
			math.deg(o.yawRate)
		)
	)
end)

test("ladeira: sobe mais devagar, segura parado e escorrega quando a lama não segura", function()
	local flat = run("m48a3", 60, { throttle = 1, steer = 0 }, { ground = "earth" }).v
	local up = run("m48a3", 60, { throttle = 1, steer = 0 }, { ground = "earth", slopeSin = math.sin(math.rad(15)) }).v
	assert(up < flat - 1, string.format("15° na terra: %.1f vs %.1f km/h", up * 3.6, flat * 3.6))
	local park = run("m48a3", 10, { throttle = 0, steer = 0 }, { ground = "earth", slopeSin = math.sin(math.rad(20)) })
	near(park.v, 0, 1e-6, "freio segura a 20° na terra")
	local mudUp = run("m48a3", 10, { throttle = 1, steer = 0 }, { ground = "mud", slopeSin = math.sin(math.rad(35)) })
	assert(
		mudUp.v < 0 and mudUp.slip > 0.1,
		string.format("35° na lama: %.2f m/s, patinando %.2f", mudUp.v, mudUp.slip)
	)
	local mudHold = run("m48a3", 10, { throttle = 0, steer = 0 }, { ground = "mud", slopeSin = math.sin(math.rad(35)) })
	assert(mudHold.v < 0, "35° na lama: nem o freio segura")
	-- já rodando, descendo 25° sem acelerar: ganha velocidade, mas o motorista segura no teto do chão
	local rolling = VehicleDrive.newState()
	rolling.v, rolling.gear = 3, 1
	local down = run(
		"m48a3",
		20,
		{ throttle = 0, steer = 0 },
		{ ground = "grass", slopeSin = -math.sin(math.rad(25)) },
		rolling
	)
	local cap = VehicleDrive.topSpeed(spec("m48a3"), "grass")
	assert(
		down.v > 3 and down.v <= cap * 1.02,
		string.format("descida: %.1f km/h (teto %.1f)", down.v * 3.6, cap * 3.6)
	)
	-- de lado no barranco liso: escorrega para o lado baixo
	local side = run("m48a3", 2, { throttle = 0, steer = 0 }, { ground = "paddy", sideSin = math.sin(math.rad(25)) })
	assert(side.vLat < -0.5, "lado direito alto: desliza para a esquerda")
	print(
		string.format(
			"       terra: plano %.0f km/h, 15° %.0f km/h; 35° na lama: %.1f m/s",
			flat * 3.6,
			up * 3.6,
			mudUp.v
		)
	)
end)

test("lama e arrozal: mais devagar, patina na arrancada e afunda (visual)", function()
	local grass = run("m48a3", 60, { throttle = 1, steer = 0 }, { ground = "grass" }).v
	local paddy = run("m48a3", 60, { throttle = 1, steer = 0 }, { ground = "paddy" }).v
	assert(paddy < grass * 0.55)
	local start = VehicleDrive.newState()
	local maxSlip = 0
	for _ = 1, 120 do
		VehicleDrive.step(spec("m48a3"), start, { throttle = 1, steer = 0 }, { ground = "paddy" }, DT)
		maxSlip = math.max(maxSlip, start.slip)
	end
	assert(maxSlip > 0, "arrancada no arrozal patina")
	local dry = VehicleDrive.newState()
	local drySlip = 0
	for _ = 1, 120 do
		VehicleDrive.step(spec("m48a3"), dry, { throttle = 1, steer = 0 }, { ground = "road" }, DT)
		drySlip = math.max(drySlip, dry.slip)
	end
	assert(drySlip < maxSlip, "na estrada patina menos")
	assert(VehicleDrive.GROUND.paddy.sinkM > VehicleDrive.GROUND.grass.sinkM)
end)

test("água: LVTP-5 boia a 11 km/h (ficha), gira e para devagar; o M48 só vadeia o raso", function()
	local deep = { ground = "water", waterDepthM = 3 }
	local s = run("lvtp5", 60, { throttle = 1, steer = 0 }, deep)
	assert(s.floating, "boia")
	near(s.v * 3.6, 11, 0.3, "LVTP-5 na água")
	local t90 = 0
	local a = VehicleDrive.newState()
	while a.v * 3.6 < 9.9 and t90 < 120 do
		VehicleDrive.step(spec("lvtp5"), a, { throttle = 1, steer = 0 }, deep, DT)
		t90 += DT
	end
	local turn = run("lvtp5", 4, { throttle = 0, steer = 1 }, deep)
	assert(math.abs(turn.yawRate) < math.rad(9), "gira devagar na água")
	-- deriva: a velocidade lateral demora a sumir na água e some logo na terra
	local w = VehicleDrive.newState()
	w.vLat, w.floating = 2, true
	run("lvtp5", 1, { throttle = 0, steer = 0 }, deep, w)
	local l = VehicleDrive.newState()
	l.vLat = 2
	run("lvtp5", 1, { throttle = 0, steer = 0 }, { ground = "earth" }, l)
	assert(w.vLat > 1.0 and l.vLat == 0, string.format("deriva: água %.2f, terra %.2f m/s", w.vLat, l.vLat))
	local shallow = run("lvtp5", 30, { throttle = 1, steer = 0 }, { ground = "water", waterDepthM = 0.8 })
	assert(not shallow.floating and shallow.v * 3.6 > 15, "no raso a lagarta pega no fundo")
	local tank = run("m48a3", 30, { throttle = 1, steer = 0 }, { ground = "water", waterDepthM = 2 })
	assert(tank.v < 0.03, "M48 não navega")
	local ford = run("m48a3", 30, { throttle = 1, steer = 0 }, { ground = "water", waterDepthM = 0.5 })
	assert(ford.v * 3.6 > 15, "M48 vadeia o riacho raso")
	local full = run("lvtp5", 60, { throttle = 1, steer = 0 }, deep)
	local coast = run("lvtp5", 20, { throttle = 0, steer = 0 }, deep, table.clone(full))
	assert(coast.v < full.v * 0.5 and coast.v > 0, "solto, o casco desliza e perde velocidade")
	local tStop = 0
	local brake = table.clone(full)
	while brake.v > 0.3 and tStop < 60 do
		VehicleDrive.step(spec("lvtp5"), brake, { throttle = -1, steer = 0 }, deep, DT)
		tStop += DT
	end
	assert(tStop < 15, "com a lagarta em ré para em menos de 15 s")
	print(
		string.format(
			"       LVTP-5: 0–90%% da velocidade na água em %.1f s; solto, %.1f km/h após 20 s; em ré para em %.1f s",
			t90,
			coast.v * 3.6,
			tStop
		)
	)
end)

test("avaria: sem motor ou sem lagarta não anda nem gira", function()
	local e = run("m48a3", 5, { throttle = 1, steer = 1 }, { ground = "earth", engine = 0 })
	assert(e.v == 0 and math.abs(e.yawRate) < 1e-6 and e.rpm < 0.01)
	local t = run("m48a3", 5, { throttle = 1, steer = 1 }, { ground = "earth", tracks = 0 })
	assert(t.v == 0 and math.abs(t.yawRate) < 1e-6 and t.rpm > 0.2, "lagarta partida: motor ligado, parado")
end)

test("contato: parede ou barranco seguram o chassi e a velocidade do modelo cai para a real", function()
	local s = run("m48a3", 20, { throttle = 1, steer = 0 }, { ground = "earth" })
	local v = s.v
	assert(not VehicleDrive.contact(s, 0, 0.1), "um toque curto não conta")
	assert(s.v == v)
	VehicleDrive.contact(s, 0, 0.1)
	VehicleDrive.contact(s, 0, 0.1)
	assert(s.v < v and s.slip == 1, "bloqueado: cai e patina")
end)

test("D-93: dique (degrau baixo à frente): a lagarta continua empurrando até a rampa subir", function()
	-- a quina segura o chassi (velocidade real ~0): sem degrau, o comando cai (como antes)
	local wall = run("m48a3", 30, { throttle = 1, steer = 0 }, { ground = "paddy" })
	local climb = table.clone(wall)
	for _ = 1, 60 do -- 1 s segurado
		VehicleDrive.contact(wall, 0, DT)
		VehicleDrive.contact(climb, 0, DT, true)
	end
	-- (abaixo de 1 m/s o contato solta e o comando para de cair: fica perto de 1 m/s)
	assert(wall.v < VehicleDrive.CLIMB_MPS - 0.3, string.format("parede: %.2f m/s", wall.v))
	assert(climb.v >= VehicleDrive.CLIMB_MPS - 1e-9 and climb.slip < 1, "dique: segue empurrando")
	-- preso de verdade (degrau que não sobe em 3 s): desiste e o comando cai como na parede, e a ajuda
	-- não volta enquanto o casco não andar
	for _ = 1, math.ceil(VehicleDrive.CLIMB_MAX_S / DT) + 60 do
		VehicleDrive.contact(climb, 0, DT, true)
	end
	assert(climb.v <= wall.v + 0.05, string.format("preso: %.2f m/s", climb.v))
	climb.v = 3
	for _ = 1, 30 do
		VehicleDrive.contact(climb, 0, DT, true)
	end
	assert(climb.v < VehicleDrive.CLIMB_MPS, "sem ajuda de novo sem andar")
	-- andou (subiu): os contadores zeram
	VehicleDrive.contact(climb, 2, DT, true)
	assert(climb.blockedT == 0 and climb.climbT == 0)
	-- devagar (abaixo da subida assistida) não acelera sozinho
	local slowSt = VehicleDrive.newState()
	slowSt.v = 1.2
	for _ = 1, 60 do
		VehicleDrive.contact(slowSt, -0.5, DT, true)
	end
	assert(slowSt.v <= 1.2 + 1e-9, "não passa do comando")
end)

test("D-93: direção mais viva (giro chega antes) e curva de raio fixo andando, sem mudar a D-86", function()
	-- giro no lugar: mesma velocidade da D-86, mas chega a 90% em menos de 1,1 s (antes 1,4 s)
	local p = VehicleDrive.newState()
	local t = 0
	while math.abs(p.yawRate) < math.rad(20) * 0.9 and t < 5 do
		VehicleDrive.step(spec("m48a3"), p, { throttle = 0, steer = 1 }, { ground = "road" }, DT)
		t += DT
	end
	assert(t < 1.1, string.format("giro do M48 a 90%% em %.2f s", t))
	-- andando devagar, o raio fixo do câmbio dá mais guinada que o giro no lugar; rápido, a aderência
	-- lateral limita (a curva continua abrindo com a velocidade)
	local s = VehicleDrive.newState()
	s.v, s.gear, s.rpm = 5, 1, 0.8
	for _ = 1, 120 do
		VehicleDrive.step(spec("m48a3"), s, { throttle = 0.6, steer = 1 }, { ground = "earth" }, DT)
	end
	assert(math.abs(s.yawRate) > math.rad(20), string.format("a 18 km/h: %.1f°/s", math.deg(math.abs(s.yawRate))))
	local f = VehicleDrive.newState()
	f.v, f.gear, f.rpm = 10, 2, 0.9
	VehicleDrive.step(spec("m48a3"), f, { throttle = 1, steer = 1 }, { ground = "earth" }, 2)
	local latLimit = VehicleDrive.DRIVE.m48a3.latG * G / f.v
	assert(math.abs(f.yawRate) <= latLimit + 1e-6, "limite da aderência lateral")
	-- números da D-86 (tabela) continuam: giro no lugar 20/40°/s, ré 12 km/h, freada 2,2 s, máximas
	assert(VehicleDrive.DRIVE.m48a3.pivotDegS == 20 and VehicleDrive.DRIVE.ontos.pivotDegS == 40)
	print(
		string.format(
			"       giro do M48 a 90%% em %.2f s; a 18 km/h na terra %.0f°/s (giro no lugar 20°/s)",
			t,
			math.deg(math.abs(s.yawRate))
		)
	)
end)

test("mola visual: arrancada levanta o nariz, freada mergulha, balança e assenta", function()
	local p = VehicleDrive.DRIVE.m48a3.spring
	local sp = VehicleDrive.newSpring()
	local peak = 0
	for _ = 1, 120 do
		VehicleDrive.springStep(sp, p, 1.5, 0, 0, DT)
		peak = math.max(peak, sp.pitch)
	end
	local steady = math.rad(p.pitchDegPerG) * 1.5 / G
	assert(peak > steady, "passa do ponto (mola pouco amortecida)")
	for _ = 1, 600 do
		VehicleDrive.springStep(sp, p, 1.5, 0, 0, DT)
	end
	near(sp.pitch, steady, math.rad(0.05), "assenta")
	local b = VehicleDrive.newSpring()
	VehicleDrive.springStep(b, p, -4, 2, 0, 0.5)
	assert(b.pitch < 0 and b.roll > 0, "freada: nariz desce; curva à direita: rola para fora")
	local big = VehicleDrive.newSpring()
	VehicleDrive.springStep(big, p, 200, 0, 0, 1)
	assert(math.deg(big.pitch) <= VehicleDrive.SPRING_MAX_DEG * 1.5 + 1e-6, "limitado")
	print(string.format("       M48 a 1,5 m/s²: nariz %.2f° (pico %.2f°)", math.deg(steady), math.deg(peak)))
end)

test("4 pontas: chão mais baixo na frente abaixa o nariz; à direita, rola para a direita", function()
	local pitch, roll, heave = VehicleDrive.cornerFit(0.2, 0.2, 0, 0, 3, 1.5)
	assert(pitch < 0 and math.abs(roll) < 1e-9 and heave < 0)
	local _, roll2 = VehicleDrive.cornerFit(0, 0.3, 0, 0.3, 3, 1.5)
	assert(roll2 < 0)
	local p3 = VehicleDrive.cornerFit(5, 5, 0, 0, 3, 1.5)
	assert(math.abs(p3) <= math.rad(4) + 1e-9, "limitado a 4°")
end)

test("laço da lagarta: comprimento medido na malha, contínuo, ramo de baixo andando em +x", function()
	-- lote _v2 (modelos do Blender na medida real): antes 50,35 / 26,77 / 52,55
	for id, len in { m48a3 = 49.15, ontos = 28.81, lvtp5 = 65.84 } do
		local art = VehicleDrive.ART[id]
		local b = VehicleDrive.belt(art.track.circles)
		near(b.length, len, 0.2, id .. " comprimento")
		local px, py = VehicleDrive.beltAt(b, 0)
		local step = b.length / 400
		local minY = math.huge
		for i = 1, 400 do
			local x, y = VehicleDrive.beltAt(b, i * step)
			assert(math.sqrt((x - px) ^ 2 + (y - py) ^ 2) <= step * 1.05, id .. ": salto no laço em " .. i)
			for _, c in art.track.circles do
				assert(math.sqrt((x - c[1]) ^ 2 + (y - c[2]) ^ 2) >= c[3] - 1e-6, id .. ": laço entra numa roda")
			end
			minY = math.min(minY, y)
			px, py = x, y
		end
		-- ramo de baixo: ponto mais baixo com tangente em +x
		local c2 = art.track.circles[2]
		near(minY, c2[2] - c2[3], 0.01, id .. " fundo")
		local s = 0
		local found = false
		while s < b.length do
			local _, y, ang = VehicleDrive.beltAt(b, s)
			if math.abs(y - minY) < 1e-3 then
				near(math.cos(ang), 1, 1e-3, id .. " sentido do ramo de baixo")
				found = true
				break
			end
			s += step
		end
		assert(found)
	end
end)

test("som: o tom sobe com a rotação e o volume com a carga", function()
	local p1, v1 = VehicleDrive.engineVoice(0.3, 0)
	local p2, v2 = VehicleDrive.engineVoice(1, 0)
	local _, v3 = VehicleDrive.engineVoice(1, 1)
	assert(p2 > p1 and v2 > v1 and v3 > v2)
	assert(p1 > 0.7 and p1 < 1 and p2 < 1.4, "faixa de tom")
end)

test("câmera: o tremor cresce com a velocidade e com o chão ruim", function()
	local function rms(speed: number, rough: number): number
		local acc = 0
		for i = 1, 600 do
			local p = VehicleDrive.shake(i / 60, speed, rough, 0.5)
			acc += p * p
		end
		return math.sqrt(acc / 600)
	end
	local still, road, field = rms(0, 0.45), rms(13, 0.1), rms(13, 0.75)
	assert(still < road and road < field, string.format("%.4f %.4f %.4f", still, road, field))
	assert(math.deg(field) < 1, "tremor contido (< 1°)")
end)

test("UH-34D: rotor parte e para, atitude com inércia, pouso amortecido, curva coordenada", function()
	local H = VehicleDrive.HELI
	local r = 0
	local t = 0
	while r < 1 do
		r = VehicleDrive.rotorStep(r, true, DT)
		t += DT
	end
	near(t, H.spinUpS, 0.05, "partida")
	assert(VehicleDrive.rotorStep(1, false, 1) < 1)
	local x, xv, peak = 0, 0, 0
	local target = math.rad(10)
	local t10 = nil :: number?
	for i = 1, 600 do
		x, xv = VehicleDrive.attitude(x, xv, target, DT)
		peak = math.max(peak, x)
		if not t10 and x >= target * 0.9 then
			t10 = i * DT
		end
	end
	assert(peak <= target * 1.05, "sem passar muito do ponto")
	assert(t10 and (t10 :: number) > 0.4, "tem inércia")
	local free = VehicleDrive.heliVertical(-6, -6, 30, 1)
	near(free, -6, 0.01, "longe do chão segue o modelo")
	local vy = -6
	for _ = 1, 120 do
		vy = VehicleDrive.heliVertical(vy, -6, 0.3, DT)
	end
	assert(vy >= -(H.touchMs + H.cushionPerM * 0.3) - 0.01, string.format("toque a %.2f m/s", vy))
	assert(VehicleDrive.coordinatedYaw(math.rad(-15), 3) == 0, "parado não há curva coordenada")
	assert(VehicleDrive.coordinatedYaw(math.rad(-15), 30) < 0, "inclinado à direita, nariz vai à direita")
	print(string.format("       atitude: 90%% de 10° em %.2f s; partida do rotor %.0f s", t10 :: number, t))
end)

test("vista sentado: todo assento tem olho fora do casco (escotilha, cabine, porta, teto)", function()
	for id, sp in Vehicles.SPECS do
		local art = VehicleDrive.ART[id]
		if not art then
			-- D-100: carro sem malha medida ainda (substituto em peças): a câmera fica na cabeça
			assert(Vehicles.WHEELED[id], id .. ": sem malha medida e sem posição de lugar")
			continue
		end
		local box = art.box
		local seats = {}
		for _, s in sp.seats do
			table.insert(seats, s.id)
		end
		for i = 1, Vehicles.PASSENGERS[id] or 0 do
			table.insert(seats, "p" .. i)
		end
		local seen = {}
		for _, seatId in seats do
			local x, y, z = VehicleDrive.eyeOf(id, seatId)
			assert(x and y and z, id .. ": sem olho para " .. seatId)
			assert(math.abs(x) <= box[1] / 2 and math.abs(z) <= box[3] / 2 + 1, id .. ": olho fora da caixa " .. seatId)
			local key = string.format("%.1f %.1f %.1f", x, y, z)
			assert(not seen[key], id .. ": dois assentos no mesmo olho " .. seatId)
			seen[key] = true
			if art.track then
				-- blindado: a cabeça fica acima do laço da lagarta (convés), nunca dentro do casco baixo
				local top = -math.huge
				for _, c in art.track.circles do
					top = math.max(top, c[2] + c[3])
				end
				assert(y > top + 1, string.format("%s %s: olho em y %.1f, laço até %.1f", id, seatId, y, top))
			end
		end
	end
	-- UH-34D (_v2, medida real): cabine alta acima do porão; atirador debruçado para fora da pele da
	-- direita (meia largura da fuselagem 0,84 m); a tropa DENTRO do porão (antes caía fora)
	local half = 0.84 / 0.28
	local _, py = VehicleDrive.eyeOf("uh34d", "driver")
	local _, ry, rz = VehicleDrive.eyeOf("uh34d", "p1")
	local _, _, gz = VehicleDrive.eyeOf("uh34d", "gunner")
	assert((py :: number) > (ry :: number) + 3, "cabine acima do porão")
	assert((gz :: number) < -half, "atirador para fora da porta")
	for i = 1, Vehicles.PASSENGERS.uh34d do
		local _, _, z = VehicleDrive.eyeOf("uh34d", "p" .. i)
		assert(math.abs(z :: number) < half, "passageiro fora da fuselagem: p" .. i)
	end
	assert(math.abs(rz :: number) < half)
	assert(VehicleDrive.eyeOf("m48a3", "p1") == nil, "M48 não leva passageiro")
	local dHeli = VehicleDrive.chaseOf("heli", 40)
	local dTank = VehicleDrive.chaseOf("ground", 22.6)
	assert(dHeli > dTank and dTank > 22.6, "perseguição mostra o casco inteiro")
end)

test("compatível: Vehicles.drive usa o mesmo modelo", function()
	local a = { v = 0 }
	for _ = 1, 300 do
		Vehicles.drive(spec("m48a3"), a, 1, "grass", DT)
	end
	local b = run("m48a3", 5, { throttle = 1, steer = 0 }, { ground = "grass" })
	near(a.v, b.v, 1e-9)
end)

-- ===== D-100: pilotar, lugares, atirar de dentro, carros e desvirar =====
local Roles = require(S .. "Roles") :: any
local fs = require("@lune/fs")

test("D-100: papel por lugar — carro qualquer um; blindado pede tripulante só no motorista e atirador", function()
	for _, id in { "m151", "m35", "peugeot403" } do
		for _, s in Vehicles.seatList(id) do
			assert(s.role == nil, id .. " " .. s.id .. ": carro não pede papel")
			assert((Roles.canTakeSeat("wheeled", s.id, "rifleman", nil)), "fuzileiro senta no " .. id)
		end
	end
	for _, kind in { "tracked", "amphibious" } do
		assert(
			Roles.vehicleSeatRole(kind, "driver") == "tank_crew"
				and Roles.vehicleSeatRole(kind, "gunner") == "tank_crew"
		)
		assert(Roles.vehicleSeatRole(kind, "commander") == nil and Roles.vehicleSeatRole(kind, "loader") == nil)
		assert(Roles.vehicleSeatRole(kind, "p1") == nil)
	end
	assert(Roles.vehicleSeatRole("heli", "driver") == "pilot")
	assert(Roles.vehicleSeatRole("heli", "copilot") == nil and Roles.vehicleSeatRole("heli", "gunner") == nil)
	local ok, need = Roles.canTakeSeat("tracked", "driver", "rifleman", nil)
	assert(not ok and need == "tank_crew", "fuzileiro não dirige o M48 sem trocar")
	assert((Roles.canTakeSeat("tracked", "driver", "rifleman", "tank_crew")), "com o papel de campo dirige")
	assert((Roles.canTakeSeat("tracked", "driver", "tank_crew", nil)), "tripulante do squad dirige")
	assert(Roles.crewVacancy(4, 3) and not Roles.crewVacancy(4, 4))
	-- a ficha diz o mesmo que a regra (o VehicleService grava a regra no atributo do assento)
	for id, sp in Vehicles.SPECS do
		for _, s in sp.seats do
			local rule = Roles.vehicleSeatRole(sp.kind, s.id) or "any"
			assert(s.role == rule, string.format("%s %s: ficha %s, regra %s", id, s.id, s.role, rule))
		end
	end
end)

test("D-100: painel — motivo de cada recusa e a troca de papel com vaga", function()
	local base = {
		sameFaction = true,
		destroyed = false,
		alive = true,
		near = true,
		inOther = false,
		seatExists = true,
		seatFree = true,
		kind = "tracked",
		seatId = "driver",
		role = "rifleman",
		crewRole = nil,
		wantCrew = false,
		vacancy = true,
	}
	local function check(over: { [string]: any }): (string, string?)
		local c = table.clone(base)
		for k, v in over do
			c[k] = v
		end
		return Vehicles.boardCheck(c)
	end
	assert(check({ kind = "wheeled" }) == "ok", "carro: entra")
	local v, need = check({})
	assert(v == "Este lugar pede tripulante" and need == "tank_crew", v)
	assert(check({ wantCrew = true }) == "crew", "troca e entra")
	assert(check({ wantCrew = true, vacancy = false }) == "Sem vaga de tripulante no time")
	assert(check({ role = "tank_crew" }) == "ok")
	assert(check({ sameFaction = false }) == "Veículo do outro lado")
	assert(check({ destroyed = true }) == "Veículo destruído")
	assert(check({ near = false }) == "Longe demais")
	assert(check({ seatFree = false }) == "Lugar ocupado")
	assert(check({ inOther = true }) == "Saia do outro veículo antes")
	assert(check({ alive = false }) == "Fora de combate")
	assert(check({ kind = "heli", wantCrew = true }) == "crew", "piloto de campo")
	assert(check({ kind = "heli", seatId = "gunner" }) == "ok", "porta do UH-34D: qualquer um")
end)

test("D-100: lugares — ordem, nomes, quem atira de dentro e em que ângulo", function()
	for id, _ in Vehicles.SPECS do
		local list = Vehicles.seatList(id)
		assert(list[1].id == "driver", id .. ": motorista/piloto primeiro")
		local seen = {}
		for _, s in list do
			assert(not seen[s.id], id .. ": lugar repetido " .. s.id)
			seen[s.id] = true
			assert(type(s.label) == "string" and #s.label > 0)
			assert(not (s.weapon and s.open), id .. " " .. s.id .. ": montada ou própria, não as duas")
		end
	end
	assert(Vehicles.seatLabel("uh34d", "driver") == "Piloto" and Vehicles.seatLabel("m48a3", "driver") == "Motorista")
	assert(Vehicles.seatLabel("m48a3", "loader") == "Municiador" and Vehicles.seatLabel("lvtp5", "p3") == "Tropa 3")
	-- fechados: motorista, municiador, cabine do caminhão e da picape; abertos: jipe, caçamba, teto, porta
	assert(Vehicles.seatInfo("m48a3", "loader").open == nil and Vehicles.seatInfo("m35", "passenger").open == nil)
	assert(Vehicles.seatInfo("m151", "passenger").open ~= nil and Vehicles.seatInfo("m35", "p1").open ~= nil)
	assert(Vehicles.seatInfo("lvtp5", "p12").open ~= nil and Vehicles.seatInfo("uh34d", "p1").open ~= nil)
	assert(Vehicles.seatInfo("peugeot403", "p1").open == nil, "sob a lona")
	assert(Vehicles.seatInfo("peugeot403", "p6").open ~= nil, "a fileira de trás atira pela aba")
	assert(Vehicles.seatInfo("m48a3", "commander").weapon == "m60", "M60 montada da cúpula")
	-- porta da direita (ímpar) atira para a direita, não para a esquerda nem por cima da cabine
	local right = Vehicles.seatInfo("uh34d", "p1").open
	assert(
		Vehicles.inArc(right, -90, -20) and not Vehicles.inArc(right, 90, -20) and not Vehicles.inArc(right, -90, 40)
	)
	local left = Vehicles.seatInfo("uh34d", "p2").open
	assert(Vehicles.inArc(left, 100, 0) and not Vehicles.inArc(left, -100, 0))
	-- volta do ângulo (179° e −179° são vizinhos)
	local rear = Vehicles.seatInfo("peugeot403", "p6").open
	assert(Vehicles.inArc(rear, 179, 0) and Vehicles.inArc(rear, -179, 0) and not Vehicles.inArc(rear, 0, 0))
	assert(Vehicles.inArc(Vehicles.seatInfo("lvtp5", "p1").open, 37, 10), "teto: para qualquer lado")
end)

test("D-100: carros — medidas do Blender, rodas pelo nome das peças, lugares dentro da caixa", function()
	local names = {
		m151 = { "Roda_FE", "Roda_FD", "Roda_TE", "Roda_TD" },
		m35 = { "Roda_FE", "Roda_FD", "Roda_T1E", "Roda_T1D", "Roda_T2E", "Roda_T2D" },
		peugeot403 = { "Roda_FE", "Roda_FD", "Roda_TE", "Roda_TD" },
	}
	for id, list in names do
		local sp, wd = spec(id), Vehicles.WHEELED[id]
		assert(sp.kind == "wheeled" and sp.botDrive == false and VehicleDrive.DRIVE[id].wheeled)
		local got = {}
		local front, rear = math.huge, -math.huge
		for _, w in wd.wheels do
			got[w.name] = w
			assert(math.abs(w.x) <= sp.widthM / 2 and math.abs(w.z) <= sp.lengthM / 2, id .. " " .. w.name)
			assert((string.sub(w.name, 6, 6) == "F") == w.steer, id .. ": só a frente esterça")
			assert((string.sub(w.name, -1) == "E") == (w.x < 0), id .. ": E = esquerda (−x)")
			front, rear = math.min(front, w.z), math.max(rear, w.z)
		end
		for _, n in list do
			assert(got[n], id .. ": falta " .. n)
		end
		if id ~= "m35" then
			near(rear - front, wd.wheelbaseM, 1e-6, id .. " entre-eixos")
		end
		for _, s in Vehicles.seatList(id) do
			local at = Vehicles.wheeledSeatAt(id, s.id)
			assert(at, id .. ": sem posição para " .. s.id)
			assert(math.abs(at[1]) <= sp.widthM / 2 and at[2] > 0 and at[2] < sp.heightM, id .. " " .. s.id)
			assert(math.abs(at[3]) <= sp.lengthM / 2, id .. " " .. s.id)
		end
		for _, b in wd.body do
			assert(
				math.abs(b.at[3]) + b.size[3] / 2 <= sp.lengthM / 2 + 0.05,
				id .. " " .. b.name .. " cabe no comprimento"
			)
			assert(b.at[2] + b.size[2] / 2 <= sp.heightM + 0.05, id .. " " .. b.name .. " cabe na altura")
		end
	end
	assert(Vehicles.PASSENGERS.m151 == 2 and Vehicles.PASSENGERS.m35 == 12 and Vehicles.PASSENGERS.peugeot403 == 6)
	assert(spec("peugeot403").faction == "VC" and spec("m151").faction == "US" and spec("m35").faction == "US")
end)

test("D-100: rodas — não gira parado, curva pelo raio mínimo, rápido na estrada e passa o arrozal", function()
	local lines = {}
	for _, id in { "m151", "m35", "peugeot403" } do
		local still = run(id, 3, { throttle = 0, steer = 1 }, { ground = "earth" })
		assert(
			math.abs(still.yawRate) < 1e-6 and math.abs(still.v) < 1e-6,
			id .. ": parado, o volante não gira o carro"
		)
		-- devagar, o raio da curva é o mínimo da ficha
		local s = VehicleDrive.newState()
		s.v, s.gear, s.rpm = 2, 1, 0.6
		for _ = 1, 180 do
			s.v = 2 -- velocidade de manobra fixa
			VehicleDrive.step(spec(id), s, { throttle = 0.3, steer = 1 }, { ground = "earth" }, DT)
		end
		local radius = 2 / math.abs(s.yawRate)
		near(radius, VehicleDrive.DRIVE[id].turnRadiusM, VehicleDrive.DRIVE[id].turnRadiusM * 0.15, id .. " raio")
		local road = run(id, 120, { throttle = 1, steer = 0 }, { ground = "road" }).v * 3.6
		local dirt = run(id, 120, { throttle = 1, steer = 0 }, { ground = "dirt" }).v * 3.6
		local grass = run(id, 120, { throttle = 1, steer = 0 }, { ground = "grass" }).v * 3.6
		local paddy = run(id, 60, { throttle = 1, steer = 0 }, { ground = "paddy" }).v * 3.6
		near(road, spec(id).maxKmh, 1.5, id .. " na estrada")
		assert(dirt > grass and grass > paddy, id .. ": estrada de terra > capim > arrozal")
		assert(paddy > 3, string.format("%s atola no arrozal seco: %.1f km/h", id, paddy))
		table.insert(
			lines,
			string.format(
				"%s: estrada %.0f, terra batida %.0f, capim %.0f, arrozal %.0f km/h; raio %.1f m",
				id,
				road,
				dirt,
				grass,
				paddy,
				radius
			)
		)
	end
	-- a lagarta também ganha a estrada de terra (D-86 intacta nos outros chãos)
	local m48dirt = run("m48a3", 120, { throttle = 1, steer = 0 }, { ground = "dirt" }).v * 3.6
	near(m48dirt, 48 * 0.9, 0.6, "M48 na estrada de terra")
	-- o jipe arranca muito antes do tanque
	assert(timeTo("m151", 30, "road") < timeTo("m48a3", 30, "road") * 0.6)
	for _, l in lines do
		print("       " .. l)
	end
	print(
		string.format(
			"       M48 na estrada de terra: %.0f km/h; M151 0–30 km/h em %.1f s",
			m48dirt,
			timeTo("m151", 30, "road")
		)
	)
end)

test("D-100: desvirar — só tombado ou preso, quase parado, um a cada 8 s", function()
	assert(Vehicles.tipped(0.2) and not Vehicles.tipped(0.95))
	assert((Vehicles.canRecover(0.1, 0.2, false, 60)), "tombado e parado")
	assert((Vehicles.canRecover(1, 0.2, true, 60)), "preso (motor acelerando e parado)")
	local ok, why = Vehicles.canRecover(1, 0.2, false, 60)
	assert(not ok and why == "O veículo não está tombado nem preso")
	assert(select(2, Vehicles.canRecover(0.1, 5, false, 60)) == "Pare o veículo antes")
	assert(select(2, Vehicles.canRecover(0.1, 0.2, false, 2)) == "Espere um pouco")
end)

test("D-100: ligações no jogo (entrar pelo painel, assento sem toque, tiro de dentro)", function()
	local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(net, '"Vehicle_Board"', 1, true) and string.find(net, '"Vehicle_Notice"', 1, true))
	local vs = fs.readFile("src/ServerScriptService/Modules/VehicleService.luau")
	assert(string.find(vs, "s.CanTouch = false", 1, true), "assento não senta pelo toque")
	assert(string.find(vs, '"VT65Embarcar"', 1, true) and string.find(vs, '"Vehicle_Board"', 1, true))
	assert(string.find(vs, "Roles.canTakeSeat", 1, true), "o servidor usa a regra de papel")
	for _, fn in { "botBoard", "botLeave", "botInput", "botState", "botFire", "mainReady", "vehicles", "seat" } do
		assert(string.find(vs, "function VehicleService." .. fn .. "(", 1, true), "API dos bots: " .. fn)
	end
	local prompt = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/VehiclePrompt.client.luau")
	assert(string.find(prompt, '"VT65Embarcar"', 1, true) and string.find(prompt, '"Vehicle_Board"', 1, true))
	local wc = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/WeaponController.client.luau")
	assert(string.find(wc, '"SeatFire"', 1, true) and string.find(wc, '"seat_fire"', 1, true), "gatilho sentado")
end)

test("lote _v2: modelo do Blender, peças móveis, olho do soldado de 2 m e orçamento", function()
	local AssetIds = require(S .. "AssetIds") :: any
	local ArtBudget = require("../../src/ServerScriptService/Modules/ArtBudget") :: any
	for id in Vehicles.SPECS do
		local key = Vehicles.modelKey(id)
		local art = VehicleDrive.ART[id]
		assert(type(AssetIds.Models[key]) == "number" and AssetIds.Models[key] > 0, id .. ": sem ID em " .. key)
		assert(ArtBudget.KIND[key] == "hero" and ArtBudget.within(key), id .. ": orçamento de " .. key)
		assert(art and art.pivots, id .. ": sem juntas na tabela ART")
		-- toda junta dentro da caixa da malha (+ meio stud de folga)
		for name, p in art.pivots do
			for k = 1, 3 do
				assert(math.abs(p[k]) <= art.box[k] / 2 + 0.5, id .. ": junta fora da caixa " .. name)
			end
		end
	end
	assert(Vehicles.modelKey("m48a3") == "m48a3_v2" and Vehicles.modelKey("uh34d") == "uh34d_v2")
	-- quem gira: torre e cano nos três blindados (o LVTP-5 só a cúpula), rotores no UH-34D, volante nos carros
	for _, id in { "m48a3", "ontos" } do
		local a = VehicleDrive.ART[id]
		assert(a.pivots.Torre and a.pivots.Cano and a.aim and a.aim.seat == "gunner" and a.aim.up > a.aim.down)
	end
	assert(VehicleDrive.ART.lvtp5.pivots.Torre and VehicleDrive.ART.lvtp5.aim)
	local h = VehicleDrive.ART.uh34d
	assert(h.pivots.RotorPrincipal and h.pivots.RotorCauda)
	near(h.pivots.RotorPrincipal[1], h.rotor.x, 1e-9, "cubo do rotor")
	near(h.pivots.RotorCauda[3], h.tail.z, 1e-9, "rotor de cauda")
	for _, id in { "m151", "m35", "peugeot403" } do
		local a = VehicleDrive.ART[id]
		assert(a.pivots.Volante and a.steerTiltDeg and a.steerTiltDeg > 30 and a.steerTiltDeg < 70, id)
		-- o volante fica do lado do motorista (+z = esquerda) e à frente do olho dele
		assert(a.pivots.Volante[3] > 0 and a.pivots.Volante[1] < a.eyes.driver[1], id .. ": volante")
	end
	-- soldado de 2,0 m (metricas.json do Blender, "soldado_2m": cabeça 0,12 m acima do olho; teto
	-- medido acima do olho): no Peugeot a cabeça não atravessa o teto; no M35 e no UH-34D sobra espaço
	local HEAD = 0.12 / 0.28
	local roofs = {
		peugeot403 = 1.86 + (0.12 - 0.094) / 0.28, -- olho de 2 m do Blender + cabeça + folga (−9 cm)
		m35 = 3.07 + (2.764 - 2.292) / 0.28, -- olho da tabela + (teto − olho), em m do chão
		uh34d = 2.73 + (3.457 - 3.189) / 0.28,
	}
	for id, roof in roofs do
		local _, y = VehicleDrive.eyeOf(id, "driver")
		assert(
			(y :: number) + HEAD < roof,
			string.format("%s: cabeça em %.2f, teto %.2f", id, (y :: number) + HEAD, roof)
		)
	end
	-- ligações: o VehicleService pega o modelo novo e monta as juntas; o VehicleFx gira pelos nomes
	local vs = fs.readFile("src/ServerScriptService/Modules/VehicleService.luau")
	assert(string.find(vs, "AssetLoader.template(Vehicles.modelKey(specId))", 1, true))
	assert(string.find(vs, "artJoints(art, mount, chassis, mesh, info)", 1, true))
	assert(string.find(vs, '"^Pa_%d+$"', 1, true), "pás soldadas no cubo")
	local vfx = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/VehicleFx.client.luau")
	for _, name in { "Torre", "Cano", "RotorPrincipal", "RotorCauda", "Volante" } do
		assert(string.find(vfx, name .. ' = "', 1, true), "VehicleFx sem a junta " .. name)
	end
	assert(string.find(vfx, '"Vehicle_Aim"', 1, true) and string.find(vs, '"Vehicle_Aim"', 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
