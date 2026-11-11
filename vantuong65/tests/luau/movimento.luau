--!strict
-- Testes do movimento e da 3ª pessoa (Shared/Movement). Uso: lune run tests/luau/movimento.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Movement = require(S .. "Movement")
local Kit = require(S .. "Kit")
local Rng = require(S .. "Rng")
local Weapons = require(S .. "Weapons")

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

local function ctx(over: { [string]: any }?): Movement.SpeedCtx
	local c: Movement.SpeedCtx = {
		stance = "stand",
		sprinting = false,
		aiming = false,
		downed = false,
		legImpaired = false,
		forward = 1,
		stamina = 1,
		loadKg = 12,
		surface = "firm",
		waterM = 0,
		grade = 0,
		rain = 0,
		transition = false,
		swimming = false,
	}
	for k, v in over or {} do
		(c :: any)[k] = v
	end
	return c
end

-- ===== velocidades =====
test("velocidade: bases iguais às do servidor (trote, corrida, agachado, rastejar)", function()
	near(Movement.targetSpeed(ctx()), 3.1, 1e-6, "trote")
	near(Movement.targetSpeed(ctx({ sprinting = true })), 5.5, 1e-6, "corrida")
	near(Movement.targetSpeed(ctx({ stance = "crouch" })), 0.84, 1e-6, "agachado")
	near(Movement.targetSpeed(ctx({ stance = "prone" })), 0.35, 1e-6, "rastejar")
	near(Movement.targetSpeed(ctx({ aiming = true })), Movement.ADS, 1e-6, "mirando")
	near(Movement.targetSpeed(ctx({ legImpaired = true, sprinting = true })), 1.4, 1e-6, "perna ferida")
	assert(Movement.targetSpeed(ctx({ downed = true })) == 0, "caído")
	near(Movement.targetSpeed(ctx({ sprinting = true, forward = -1 })), 3.1, 1e-6, "corrida de costas = trote")
	near(Movement.targetSpeed(ctx({ sprinting = true, forward = 0.3 })), 3.1, 1e-6, "corrida de lado = trote")
	near(Movement.targetSpeed(ctx({ sprinting = true, waterM = 0.6 })), 3.1 * Movement.waterFactor(0.6), 1e-6)
end)

test("velocidade: o cliente nunca passa do teto do servidor (5.000 sorteios)", function()
	local rng = Rng.new(651818)
	local stances = { "stand", "crouch", "prone" }
	local surfaces = { "firm", "grass", "forest", "sand", "mud", "paddy", "water" }
	for i = 1, 5000 do
		local c = ctx({
			stance = stances[1 + math.floor(rng:next() * 3)],
			sprinting = rng:next() < 0.5,
			aiming = rng:next() < 0.3,
			downed = rng:next() < 0.05,
			legImpaired = rng:next() < 0.1,
			forward = rng:range(-1, 1),
			stamina = rng:next(),
			loadKg = rng:range(8, 40),
			surface = surfaces[1 + math.floor(rng:next() * #surfaces)],
			waterM = rng:range(0, 1.5),
			grade = rng:range(-0.8, 0.8),
			rain = rng:next(),
			transition = rng:next() < 0.1,
		})
		local v = Movement.targetSpeed(c)
		local cap = Movement.serverSpeed(c.stance, c.sprinting, c.legImpaired, c.downed)
		assert(v >= 0 and v <= cap + 1e-9, string.format("sorteio %d: %.3f > teto %.3f", i, v, cap))
	end
end)

test("velocidade: fôlego baixo tira a corrida aos poucos; peso pesa mais correndo", function()
	near(Movement.targetSpeed(ctx({ sprinting = true, stamina = 0.3 })), 5.5, 1e-6, "30% ainda corre cheio")
	local half = Movement.targetSpeed(ctx({ sprinting = true, stamina = 0.15 }))
	assert(half > 3.1 and half < 5.5, "15%: entre trote e corrida")
	near(Movement.targetSpeed(ctx({ sprinting = true, stamina = 0 })), 3.1, 1e-6, "zerado = trote")
	assert(Movement.loadFactor(35, true) < Movement.loadFactor(35, false), "peso pesa mais na corrida")
	near(Movement.loadFactor(15, true), 1, 1e-9, "até 15 kg não pesa")
	near(Movement.loadFactor(100, true), 0.8, 1e-9, "piso da corrida")
	near(Movement.loadFactor(100, false), 0.9, 1e-9, "piso do trote")
end)

test("chão: arrozal < lama < areia < mata < firme; a chuva só pesa no chão mole", function()
	local function v(s: string, rain: number?): number
		return Movement.surfaceSpeed(s, rain or 0)
	end
	assert(v("paddy") < v("mud") and v("mud") < v("sand") and v("sand") < v("forest") and v("forest") < v("firm"))
	near(v("firm", 1), 1, 1e-9, "chão firme na chuva")
	near(v("paddy", 1), v("paddy") * 0.9, 1e-9, "arrozal na chuva (Weather.mudSpeed)")
	assert(Movement.surfaceOf(nil, "PaddyWater", "PaddyWater") == "paddy")
	assert(Movement.surfaceOf("Grass", nil, "Dike") == "firm", "dique é terra batida")
	assert(Movement.surfaceOf("LeafyGrass", nil, "Terrain") == "forest")
	assert(Movement.surfaceOf("Mud", nil, "Terrain") == "mud" and Movement.surfaceOf("Sand", nil, nil) == "sand")
	assert(Movement.surfaceOf("Basalt", nil, nil) == "firm", "desconhecido = firme")
	-- água: monotônica, canela quase livre, cintura ~40%
	local last = 2
	for i = 0, 20 do
		local f = Movement.waterFactor(i * 0.1)
		assert(f <= last + 1e-12 and f >= 0.3, "água monotônica")
		last = f
	end
	near(Movement.waterFactor(0.1), 1, 1e-9, "canela")
	near(Movement.waterFactor(1.0), 0.4, 0.01, "cintura")
	-- rampa: subida freia, descida leve não, descida forte freia um pouco
	assert(Movement.slopeFactor(0.2) < 0.8 and Movement.slopeFactor(0.4) < Movement.slopeFactor(0.2))
	near(Movement.slopeFactor(-0.15), 1, 1e-9, "descida leve")
	assert(Movement.slopeFactor(-0.6) < 1 and Movement.slopeFactor(-0.6) >= 0.7)
	assert(Movement.slopeFactor(3) >= 0.4, "piso da subida")
end)

-- ===== inércia =====
local function timeTo(vx: number, tx: number, tz: number, grip: number): number
	local x, z, t = vx, 0, 0
	while math.abs(x - tx) + math.abs(z - tz) > 1e-6 do
		x, z = Movement.accelStep(x, z, tx, tz, 1 / 60, grip)
		t += 1 / 60
		assert(t < 10, "não chegou")
	end
	return t
end

test("inércia: arranca, freia e vira com aceleração limitada", function()
	local start = timeTo(0, 3.1, 0, 1)
	local stop = timeTo(5.5, 0, 0, 1)
	local turn = timeTo(3.1, -3.1, 0, 1)
	print(
		string.format(
			"       parado→trote %.2f s; corrida→parado %.2f s; meia-volta no trote %.2f s",
			start,
			stop,
			turn
		)
	)
	assert(start > 0.3 and start < 0.6, "arrancada")
	assert(stop > 0.4 and stop < 0.8, "frenagem")
	assert(turn > stop * 0.5 and turn < 1.2, "meia-volta")
	assert(timeTo(0, 3.1, 0, Movement.surfaceGrip("paddy")) > start, "arrozal arranca mais devagar")
	-- no ar quase não muda o embalo
	local x = Movement.accelStep(3, 0, -3, 0, 0.1, Movement.AIR_GRIP)
	assert(x > 2.8, "controle no ar")
end)

-- ===== fôlego =====
local function sprintFor(kg: number, surface: string?, grade: number?): number
	local s = Movement.newStamina()
	local t = 0
	while Movement.canSprint(s) do
		Movement.staminaStep(s, 0.05, {
			kind = "sprint",
			stance = "stand",
			surface = surface or "firm",
			grade = grade or 0,
			loadKg = kg,
			waterM = 0,
		})
		t += 0.05
		assert(t < 120, "nunca cansa")
	end
	return t
end

test("fôlego: corrida dura ~24 s leve; menos com peso, arrozal e subida", function()
	local light = sprintFor(15)
	local rifle = sprintFor(21)
	local radio = sprintFor(31)
	local paddy = sprintFor(21, "paddy")
	local hill = sprintFor(21, "firm", 0.2)
	print(
		string.format(
			"       corrida até zerar: 15 kg %.1f s; 21 kg %.1f s; 31 kg %.1f s; arrozal %.1f s; subida 20%% %.1f s",
			light,
			rifle,
			radio,
			paddy,
			hill
		)
	)
	near(light, Movement.SPRINT_S, 0.1, "15 kg")
	assert(rifle < light and radio < rifle and paddy < rifle and hill < rifle)
end)

test("fôlego: sem fôlego trava a corrida até 35%; recupera parado depois de uma pausa", function()
	local s = Movement.newStamina()
	s.value = 0.01
	local run = { kind = "sprint", stance = "stand", surface = "firm", grade = 0, loadKg = 15, waterM = 0 }
	Movement.staminaStep(s, 1, run)
	assert(s.value == 0 and s.exhausted and not Movement.canSprint(s), "zerou")
	local rest = { kind = "still", stance = "stand", surface = "firm", grade = 0, loadKg = 15, waterM = 0 }
	Movement.staminaStep(s, Movement.RECOVER_DELAY * 0.5, rest)
	assert(s.value == 0, "a pausa vem antes da recuperação")
	local t = Movement.RECOVER_DELAY * 0.5
	while s.exhausted do
		Movement.staminaStep(s, 0.05, rest)
		t += 0.05
		assert(t < 30, "não recuperou")
	end
	assert(s.value >= Movement.EXHAUSTED_UNTIL - 1e-9 and Movement.canSprint(s))
	local full = Movement.newStamina()
	full.value = 0
	full.rest = 0
	local tf = 0
	while full.value < 1 do
		Movement.staminaStep(full, 0.05, rest)
		tf += 0.05
	end
	print(string.format("       parado: volta a correr em %.1f s; cheio em %.1f s (deitado é mais rápido)", t, tf))
	assert(tf < 20, "recuperação parado")
	-- trote no plano recupera devagar; trote em subida ou no arrozal cansa
	assert(
		Movement.staminaRate({ kind = "jog", stance = "stand", surface = "firm", grade = 0, loadKg = 20, waterM = 0 })
			> 0
	)
	assert(
		Movement.staminaRate({ kind = "jog", stance = "stand", surface = "firm", grade = 0.3, loadKg = 20, waterM = 0 })
			< 0
	)
	assert(
		Movement.staminaRate({ kind = "jog", stance = "stand", surface = "paddy", grade = 0, loadKg = 20, waterM = 0 })
			< 0
	)
	local prone =
		Movement.staminaRate({ kind = "still", stance = "prone", surface = "firm", grade = 0, loadKg = 20, waterM = 0 })
	assert(prone > Movement.staminaRate(rest), "deitado recupera mais rápido")
	-- gasto pontual
	local g = Movement.newStamina()
	Movement.spend(g, Movement.COST.jump, 15)
	near(g.value, 1 - Movement.COST.jump, 1e-9, "pulo")
	assert(g.rest == 0)
	assert(Movement.swayFactor(1) == 1 and Movement.swayFactor(0) > 3, "balanço da mira cansado")
end)

test("peso: fuzileiro com a dotação padrão (M14, 5 carregadores, 2 granadas, fumaça)", function()
	local m14 = Weapons.get("m14")
	assert(m14, "m14")
	local d = Kit.defaults("rifle")
	local kg = Movement.loadKg({
		weaponsKg = (m14 :: any).massLoadedKg,
		magKg = Kit.MAG_KG.rifle,
		mags = d.mags - 1,
		frags = d.frags,
		smokes = d.smokes,
		bandages = d.bandages,
		role = "rifleman",
	})
	print(string.format("       fuzileiro: %.1f kg; com rádio: %.1f kg", kg, kg + Movement.ROLE_KG.radio_operator))
	assert(kg > 18 and kg < 25, "fuzileiro entre 18 e 25 kg")
	assert(Movement.loadDrain(kg + Movement.ROLE_KG.radio_operator) > Movement.loadDrain(kg))
end)

-- ===== pulo e aterrissagem =====
test("pulo: 0,45 m descansado, menos cansado e com peso; JumpPower bate com a altura", function()
	near(Movement.jumpHeight(1, 15), 0.45, 1e-9, "descansado")
	assert(Movement.jumpHeight(0, 15) < 0.25, "cansado")
	assert(Movement.jumpHeight(1, 30) < 0.45, "com peso")
	assert(Movement.jumpHeight(0, 200) >= Movement.JUMP_MIN_M, "piso")
	local g = 196.2
	local v = Movement.jumpPower(0.45, g)
	near(v * v / (2 * g) * Movement.STUD_M, 0.45, 1e-9, "altura do JumpPower")
end)

test("aterrissagem: pulo só balança; queda de 3 m freia e cansa", function()
	local dip, slowF, secs, cost = Movement.landing(0.1)
	assert(dip == 0 and slowF == 1 and secs == 0 and cost == 0, "degrau")
	dip, slowF, secs, cost = Movement.landing(0.45)
	assert(dip > 0 and dip < 0.04 and slowF > 0.9, "pulo normal")
	dip, slowF, secs, cost = Movement.landing(3)
	assert(dip >= 0.1 and slowF < 0.5 and secs > 0.6 and cost > 0.1, "queda forte")
	assert(Movement.dipCurve(0, 0.09) == 0 and Movement.dipCurve(0.09, 0.09) < -0.99, "pico da afundada")
	assert(math.abs(Movement.dipCurve(0.9, 0.09)) < 0.01, "afundada some")
end)

-- ===== transpor =====
local NIL = newproxy() -- campo ausente (nil numa tabela literal não cria a chave)
local function vp(over: { [string]: any }): Movement.VaultProbe
	local p: Movement.VaultProbe = {
		height = 0.5,
		distance = 0.3,
		clearance = 2,
		depth = 0.8,
		drop = 0.5,
		headroom = 2,
		speed = 1.5,
		stamina = 1,
		stance = "stand",
		legImpaired = false,
		loadKg = 20,
	}
	for k, v in over do
		(p :: any)[k] = if v == NIL then nil else v
	end
	return p
end

test("transpor: dique, cerca e sacos de areia transpõe; mureta com chão em cima escala", function()
	local dike = Movement.vaultPlan(vp({ height = 0.5, depth = 0.9, drop = 0.45 }))
	assert(dike and dike.kind == "vault", "dique de 0,5 m")
	local fence = Movement.vaultPlan(vp({ height = 1.0, depth = 0.1, drop = 1.0 }))
	assert(fence and fence.kind == "vault", "cerca de 1 m")
	local bags = Movement.vaultPlan(vp({ height = 1.1, depth = 0.6, drop = 1.1 }))
	assert(bags and bags.kind == "vault", "sacos de areia de 1,1 m")
	local wall = Movement.vaultPlan(vp({ height = 1.2, depth = NIL, drop = NIL, headroom = 3 }))
	assert(wall and wall.kind == "mantle", "mureta/plataforma de 1,2 m: escala")
	assert(wall.duration > (bags :: any).duration, "escalar demora mais")
	print(
		string.format(
			"       dique %.2f s; sacos %.2f s; escalar %.2f s",
			dike.duration,
			(bags :: any).duration,
			wall.duration
		)
	)
end)

test("transpor: recusa alto, baixo, longe, sem espaço, queda, deitado e perna ferida", function()
	local cases: { { any } } = {
		{ { height = 1.4 }, "alto" },
		{ { height = 0.25 }, "baixo" },
		{ { height = NIL }, "nada à frente" },
		{ { distance = 1.2 }, "longe" },
		{ { clearance = 0.4 }, "sem espaço" },
		{ { drop = 4 }, "queda" },
		{ { drop = NIL }, "queda" },
		{ { depth = NIL, headroom = 1.2 }, "sem espaço em cima" },
		{ { stance = "crouch" }, "postura" },
		{ { stance = "prone" }, "postura" },
		{ { legImpaired = true }, "perna ferida" },
		{ { stamina = 0 }, "sem fôlego" },
	}
	for _, c in cases do
		local plan, why = Movement.vaultPlan(vp(c[1]))
		assert(plan == nil and why == c[2], string.format("esperado '%s', veio '%s'", c[2], tostring(why)))
	end
end)

test("transpor: cansado e pesado é mais lento; correndo é mais rápido", function()
	local base = Movement.vaultPlan(vp({})) :: Movement.VaultPlan
	local tired = Movement.vaultPlan(vp({ stamina = 0.1 })) :: Movement.VaultPlan
	local heavy = Movement.vaultPlan(vp({ loadKg = 35 })) :: Movement.VaultPlan
	local run = Movement.vaultPlan(vp({ speed = 5 })) :: Movement.VaultPlan
	assert(tired.duration > base.duration and heavy.duration > base.duration and run.duration < base.duration)
	assert(base.cost == Movement.COST.vault)
end)

-- ===== postura =====
test("postura: deitar e levantar demoram mais que agachar; mergulho chega antes", function()
	assert(Movement.stanceTime("stand", "crouch") < Movement.stanceTime("stand", "prone"))
	assert(Movement.stanceTime("prone", "stand") > Movement.stanceTime("stand", "prone"))
	assert(Movement.stanceTime("stand", "prone", true) < Movement.stanceTime("stand", "prone"))
	assert(Movement.isProneTransition("stand", "prone") and not Movement.isProneTransition("stand", "crouch"))
	near(Movement.diveSpeed(5, 0), 5, 1e-9)
	assert(Movement.diveSpeed(5, Movement.DIVE_S) == 0 and Movement.diveSpeed(5, 0.2) < 5)
end)

test("câmera: balanço sutil (≤ 2,5 cm), menor mirando e agachado; respiração mais funda cansado", function()
	local maxY, maxX = 0, 0
	for i = 0, 200 do
		local x, y = Movement.bob(i * 0.05, Movement.SPRINT, "stand", false)
		maxX, maxY = math.max(maxX, math.abs(x)), math.max(maxY, math.abs(y))
	end
	assert(maxY <= 0.025 and maxX <= 0.02, "sutil")
	local _, ya = Movement.bob(0, 3.1, "stand", true)
	local _, ys = Movement.bob(0, 3.1, "stand", false)
	assert(math.abs(ya) < math.abs(ys), "mirando")
	local x0, y0 = Movement.bob(1, 0, "stand", false)
	assert(x0 == 0 and y0 == 0, "parado não balança")
	assert(Movement.cadence(1.4) < Movement.cadence(3.1) and Movement.cadence(5.5) <= 3.4)
	local rested, tired = 0, 0
	for i = 0, 400 do
		rested = math.max(rested, math.abs(Movement.breath(i * 0.02, 1)))
		tired = math.max(tired, math.abs(Movement.breath(i * 0.02, 0)))
	end
	assert(tired > rested * 3 and tired <= 0.0081, "respiração")
end)

-- ===== 3ª pessoa =====
local function vc(over: { [string]: any }): Movement.ViewCtx
	local c: Movement.ViewCtx = {
		want = true,
		allowed = true,
		alive = true,
		customCamera = true,
		seated = false,
		downed = false,
		aiming = false,
		binoculars = false,
	}
	for k, v in over do
		(c :: any)[k] = v
	end
	return c
end

test("3ª pessoa: mirar e binóculo voltam à 1ª rápido; soltar volta à 3ª; veículo nada muda", function()
	local t, time = Movement.viewTarget(vc({}), false)
	assert(t == 1 and time == Movement.VIEW_TIME.toggle, "ligada")
	t, time = Movement.viewTarget(vc({ aiming = true }), false)
	assert(t == 0 and time == Movement.VIEW_TIME.adsIn, "mirando: 1ª pessoa")
	t, time = Movement.viewTarget(vc({ binoculars = true }), false)
	assert(t == 0 and time == Movement.VIEW_TIME.adsIn, "binóculo")
	t, time = Movement.viewTarget(vc({}), true)
	assert(t == 1 and time == Movement.VIEW_TIME.adsOut, "soltou a mira")
	t, time = Movement.viewTarget(vc({ seated = true }), false)
	assert(t == 0 and time == 0, "veículo: na hora, como antes")
	t, time = Movement.viewTarget(vc({ customCamera = false }), false)
	assert(t == 0 and time == 0, "lobby/tela de spawn")
	for _, k in { "want", "allowed", "alive" } do
		t = Movement.viewTarget(vc({ [k] = false }), false)
		assert(t == 0, k)
	end
	assert(Movement.viewTarget(vc({ downed = true }), false) == 0, "caído")
	-- a mistura chega ao alvo no tempo pedido e a suavização é monotônica
	local a, n = 0, 0
	while a < 1 do
		a = Movement.viewStep(a, 1, 1 / 60, 0.28)
		n += 1
	end
	near(n / 60, 0.28, 1 / 60 + 1e-9, "tempo da transição")
	assert(Movement.viewStep(0.5, 0, 10, 0.1) == 0, "não passa do alvo")
	local last = -1
	for i = 0, 100 do
		local e = Movement.ease(i / 100)
		assert(e >= last, "ease monotônico")
		last = e
	end
	assert(Movement.ease(0) == 0 and Movement.ease(1) == 1 and Movement.ease(0.5) == 0.5)
	assert(Movement.ease(Movement.VIEW_THRESHOLD) == 0.5, "limiar do ThirdPersonView no meio")
end)

test("3ª pessoa: parede puxa a câmera na hora; folhagem puxa suave; volta devagar", function()
	assert(Movement.boomStep(7, 2, 1 / 60, true) == 2, "parede: na hora")
	local soft = Movement.boomStep(7, 2, 1 / 60, false)
	assert(soft < 7 and soft > 2, "folhagem: suave")
	local back = Movement.boomStep(2, 7, 1 / 60, false)
	assert(back > 2 and back < 2.5, "volta devagar")
	local b = 2
	for _ = 1, 120 do
		b = Movement.boomStep(b, 7, 1 / 60, false)
	end
	assert(b > 6.8, "em 2 s volta inteira")
	assert(Movement.bodyFade(2) == 0 and Movement.bodyFade(0.2) == 1, "corpo some com a câmera colada")
	for _, st in { "stand", "crouch", "prone" } do
		local sh = Movement.shoulder(st)
		assert(sh.back >= 1.5 and sh.back <= 2.5 and sh.side > 0.3 and sh.side < 0.7, st)
	end
	assert(Movement.shoulder("prone").up > Movement.shoulder("stand").up, "deitado: câmera acima do chão")
end)

test("3ª pessoa: dispersão do quadril cresce com velocidade e cansaço", function()
	local still = Movement.hipSpreadDeg(0, 1, "stand")
	assert(Movement.hipSpreadDeg(3.1, 1, "stand") > still and Movement.hipSpreadDeg(0, 0, "stand") > still)
	assert(Movement.hipSpreadDeg(0, 1, "prone") < Movement.hipSpreadDeg(0, 1, "crouch"))
	assert(still >= 1, "nunca vira mira de ferro")
end)

-- ===== servidor =====
test("servidor nunca corta a corrida antes do cliente (10.000 passos aleatórios)", function()
	-- cliente no melhor caso (mais leve, chão firme, plano) contra o orçamento do servidor
	local rng = Rng.new(19650818)
	local s = Movement.newStamina()
	local b = 1
	local wantSprint = false
	for i = 1, 10000 do
		if rng:next() < 0.05 then
			wantSprint = not wantSprint
		end
		local dt = rng:range(0.01, 0.3)
		local running = wantSprint and Movement.canSprint(s)
		local stance = if rng:next() < 0.3 then "prone" else "stand"
		Movement.staminaStep(s, dt, {
			kind = if running then "sprint" else "still",
			stance = if running then "stand" else stance,
			surface = "firm",
			grade = 0,
			loadKg = 5,
			waterM = 0,
		})
		b = Movement.serverBudgetStep(b, dt, running)
		assert(b >= s.value - 1e-9, string.format("passo %d: servidor %.3f < cliente %.3f", i, b, s.value))
		if running then
			assert(b >= Movement.SERVER_MIN_TO_START or s.value <= Movement.SERVER_MIN_TO_START, "servidor recusaria")
		end
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
