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
	assert(VehicleDrive.groundOf("Water") == "water" and VehicleDrive.groundOf("Ground") == "earth")
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
	for id, len in { m48a3 = 50.35, ontos = 26.77, lvtp5 = 52.55 } do
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

test("compatível: Vehicles.drive usa o mesmo modelo", function()
	local a = { v = 0 }
	for _ = 1, 300 do
		Vehicles.drive(spec("m48a3"), a, 1, "grass", DT)
	end
	local b = run("m48a3", 5, { throttle = 1, steer = 0 }, { ground = "grass" })
	near(a.v, b.v, 1e-9)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
