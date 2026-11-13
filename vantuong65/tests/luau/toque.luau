--!strict
-- Testes da Parte 13 (celular e tablet, núcleo do toque). Uso: lune run tests/luau/toque.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Toque = require(S .. "Toque")
local InputMap = require(S .. "InputMap")
local Gatilho = require(S .. "Gatilho") :: any
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
local D = InputMap.DEFAULTS :: any

-- telas de referência: área do HUD (área segura do Roblox + 2 mm) e o lado curto da tela
local SCREENS = {
	{ name = "celular 19,5:9", W = 724, H = 285, short = 311 },
	{ name = "celular 16:9", W = 640, H = 300, short = 330 },
	{ name = "tablet 4:3", W = 1000, H = 700, short = 732 },
}

-- botões na tela (px) para um contexto
local function placed(slots: { [string]: any }, sc: any, c: Toque.Ctx): { Toque.HitButton }
	local out: { Toque.HitButton } = {}
	for _, d in Toque.BUTTONS do
		local sl = slots[d.id]
		if d.kind ~= "stick" and d.kind ~= "slot" and sl.on and Toque.visible(d, c) then
			local size = Toque.buttonPx(d.mm, sl.scale, sc.short)
			local cx, cy = Toque.place(sl.x, sl.y, size, sc.W, sc.H)
			table.insert(out, { id = d.id, cx = cx, cy = cy, r = size / 2 })
		end
	end
	return out
end

local FOOT: Toque.Ctx = { foot = true, vehicle = false, downed = false, aiming = true, voice = true }
local DOWNED: Toque.Ctx = { foot = false, vehicle = false, downed = true, aiming = false, voice = true }
local VEHICLE: Toque.Ctx = { foot = false, vehicle = true, downed = false, aiming = false, voice = true }

test("tamanho físico: mínimo de 48 px (44 pt / 48 dp ≈ 9 mm), tiro bem maior, teto na tela", function()
	assert(Toque.MIN_MM >= 9 and Toque.MIN_PX >= 48, "mínimo de toque")
	for _, sc in SCREENS do
		local small = Toque.px(Toque.MIN_MM, sc.short)
		local fire = Toque.px(Toque.FIRE_MM, sc.short)
		assert(small >= 48, sc.name .. ": botão abaixo de 48 px")
		assert(fire >= small * 1.6, sc.name .. ": tiro deveria ser bem maior")
		assert(fire <= math.max(48, sc.short * 0.32) + 0.5, sc.name .. ": tiro passa do teto")
	end
	-- celular (~160 px por polegada): 9 mm ≈ 57 px; tablet (~132): 16 mm ≈ 83 px
	near(Toque.px(9, 390), 57, 1, "9 mm no celular")
	near(Toque.px(16, 768), 83, 1, "16 mm no tablet")
	assert(Toque.px(1, 390) == 48, "nada abaixo do mínimo, nem 1 mm")
	-- o editor (60–150%) nunca leva um botão abaixo do mínimo
	assert(Toque.buttonPx(9, 0.6, 390) >= 48 and Toque.buttonPx(9, 0.1, 390) >= 48)
	assert(Toque.buttonPx(10, 1.5, 390) > Toque.buttonPx(10, 1, 390), "150% cresce")
	near(Toque.buttonPx(10, 9, 390), Toque.buttonPx(10, 1.5, 390), 0, "escala presa em 1,5")
	-- todo botão de toque pedido com pelo menos o mínimo físico; o tiro com 16 mm
	for _, d in Toque.BUTTONS do
		assert(d.mm >= Toque.MIN_MM, d.id .. " menor que 9 mm")
	end
	assert(Toque.BY_ID.fire.mm == Toque.FIRE_MM)
	near(Toque.mm(Toque.rawPx(12, 390), Toque.dpiGuess(390)), 12, 1e-9, "mm <-> px")
end)

test("layouts prontos: nenhum botão sobre outro e todos dentro da área, a pé, caído e no veículo", function()
	for _, name in { "two", "three", "four" } do
		for _, mirror in { false, true } do
			local slots = Toque.layout({ touchLayout = name, touchMirror = mirror, touchCustom = {} })
			for _, sc in SCREENS do
				for _, c in { FOOT, DOWNED, VEHICLE } do
					local list = placed(slots, sc, c)
					for i = 1, #list do
						local a = list[i]
						assert(
							a.cx - a.r >= -0.5
								and a.cx + a.r <= sc.W + 0.5
								and a.cy - a.r >= -0.5
								and a.cy + a.r <= sc.H + 0.5,
							string.format("%s %s: %s fora da área", name, sc.name, a.id)
						)
						for j = i + 1, #list do
							local b = list[j]
							local d = math.sqrt((a.cx - b.cx) ^ 2 + (a.cy - b.cy) ^ 2)
							assert(
								d >= a.r + b.r - 1,
								string.format(
									"%s%s %s: %s e %s se sobrepõem (%.0f < %.0f)",
									name,
									if mirror then " (canhoto)" else "",
									sc.name,
									a.id,
									b.id,
									d,
									a.r + b.r
								)
							)
						end
					end
				end
			end
		end
	end
end)

test("zonas: botão sob o dedo, analógico à esquerda embaixo, câmera no resto; canhoto espelha", function()
	local sc = SCREENS[1]
	local slots = Toque.layout({ touchLayout = "two", touchMirror = false, touchCustom = {} })
	local list = placed(slots, sc, FOOT)
	local zone = Toque.zone(false)
	local fire: Toque.HitButton? = nil
	for _, b in list do
		if b.id == "fire" then
			fire = b
		end
	end
	assert(fire, "tiro na tela")
	local f = fire :: Toque.HitButton
	assert(Toque.hit(f.cx, f.cy, sc.W, sc.H, list, zone) == "fire", "centro do tiro")
	assert(Toque.hit(f.cx + f.r * 1.05, f.cy, sc.W, sc.H, list, zone) == "fire", "folga do dedo na borda")
	assert(Toque.hit(sc.W * 0.25, sc.H * 0.85, sc.W, sc.H, list, zone) == "stick", "metade de baixo à esquerda")
	assert(Toque.hit(sc.W * 0.5, sc.H * 0.6, sc.W, sc.H, list, zone) == "camera", "meio da tela")
	assert(Toque.hit(sc.W * 0.25, sc.H * 0.05, sc.W, sc.H, {}, zone) == "camera", "alto à esquerda é câmera")
	-- dois botões encostados: o mais central ganha
	local two = { { id = "a", cx = 100, cy = 100, r = 30 }, { id = "b", cx = 155, cy = 100, r = 30 } }
	assert(Toque.hit(120, 100, 400, 300, two, zone) == "a" and Toque.hit(140, 100, 400, 300, two, zone) == "b")
	-- canhoto: o analógico vai para a direita e o tiro para a esquerda
	local m = Toque.layout({ touchLayout = "two", touchMirror = true, touchCustom = {} })
	local mz = Toque.zone(true)
	assert(m.fire.x < 0.5 and m.stick.x > 0.5, "espelho dos botões")
	assert(Toque.hit(sc.W * 0.75, sc.H * 0.85, sc.W, sc.H, {}, mz) == "stick", "analógico do canhoto")
	assert(Toque.hit(sc.W * 0.25, sc.H * 0.85, sc.W, sc.H, {}, mz) == "camera", "câmera do canhoto")
end)

test("dono do toque: o dedo da câmera que passa num botão não o aciona; soltar fora solta", function()
	local tr = Toque.newTracker()
	local camFinger, fireFinger, other = {}, {}, {}
	assert(Toque.claim(tr, camFinger, "camera") == "camera")
	-- o dedo da câmera passa por cima do tiro: o dono não muda (mover não reclama dono)
	assert(Toque.owner(tr, camFinger) == "camera")
	assert(Toque.claim(tr, fireFinger, "fire") == "fire")
	-- outro dedo no mesmo botão já seguro vira câmera (não aperta duas vezes)
	assert(Toque.claim(tr, other, "fire") == "camera", "botão já seguro")
	-- o dedo do tiro sai do botão e solta lá fora: quem solta é o tiro
	assert(Toque.release(tr, fireFinger) == "fire")
	assert(tr.held.fire == nil, "o botão ficou livre")
	assert(Toque.claim(tr, {}, "fire") == "fire", "aperta de novo depois de solto")
	assert(Toque.release(tr, camFinger) == "camera")
	assert(Toque.release(tr, camFinger) == nil, "soltar duas vezes não solta nada")
	-- o analógico tem um dedo só
	assert(Toque.claim(tr, "a", "stick") == "stick" and Toque.claim(tr, "b", "stick") == "camera")
end)

test("segundo plano / ligação / notificação: solta tudo e só volta com tudo solto", function()
	local tr = Toque.newTracker()
	Toque.claim(tr, 1, "fire")
	Toque.claim(tr, 2, "stick")
	Toque.claim(tr, 3, "camera")
	local out = Toque.releaseAll(tr)
	assert(#out == 3 and next(tr.owners) == nil and next(tr.held) == nil, "rastreador limpo")
	assert(Toque.claim(tr, 4, "fire") == "fire", "nada ficou preso")
	-- a máquina de estados: o que estava segurado é cancelado e o jogo pausa
	local s = InputMap.newState()
	InputMap.event(s, "aim", true)
	InputMap.event(s, "sprint", true)
	InputMap.event(s, "lean", 1)
	InputMap.event(s, "wheel_open", "equip")
	local cancelled = InputMap.event(s, "focus_lost")
	assert(#cancelled == 4, "cancelou " .. #cancelled)
	assert(not InputMap.acceptsGame(s), "fora de foco não aceita jogo")
	InputMap.event(s, "aim", true) -- (o runtime nem manda; mesmo assim nada passa)
	InputMap.event(s, "focus_back")
	assert(not InputMap.acceptsGame(s), "voltou: relê o estado antes de aceitar")
	InputMap.event(s, "buttons_released")
	assert(InputMap.acceptsGame(s))
	-- 10.000 eventos com foco entrando e saindo: nada segurado fora de foco
	local evs = {
		"menu_open",
		"menu_close",
		"focus_lost",
		"focus_back",
		"buttons_released",
		"aim",
		"sprint",
		"lean",
		"wheel_open",
		"wheel_close",
		"die",
		"respawn",
	}
	local rng = Rng.new(1365)
	local st = InputMap.newState()
	for i = 1, 10000 do
		local ev = evs[1 + math.floor(rng:next() * #evs)]
		local arg: any = nil
		if ev == "aim" or ev == "sprint" or ev == "lean" or ev == "wheel_open" then
			if not InputMap.acceptsGame(st) then
				continue
			end
			arg = if ev == "lean" then 1 elseif ev == "wheel_open" then "comm" else true
		end
		InputMap.event(st, ev, arg)
		if st.unfocused then
			assert(not st.aiming and not st.sprinting and st.lean == 0 and st.wheel == nil, "preso fora de foco " .. i)
			assert(not InputMap.acceptsGame(st))
		end
	end
end)

test("analógico proporcional: pouco = devagar, metade anda, borda corre (só para a frente)", function()
	local R = 80
	local _, _, z = Toque.stickValue(R * 0.05, 0, R)
	assert(z == 0, "zona morta")
	local _, _, slow = Toque.stickValue(0, -R * 0.25, R)
	local _, y2, half = Toque.stickValue(0, -R * 0.5, R)
	local _, _, full = Toque.stickValue(0, -R * 1.3, R)
	assert(slow > 0 and slow < 0.3, string.format("pouco: %.2f", slow))
	assert(half > 0.4 and half < 0.6, string.format("metade: %.2f", half))
	assert(full == 1, "borda satura")
	assert(y2 > 0, "dedo para cima = para a frente")
	local x, y = Toque.stickValue(R * 0.6, R * 0.6, R) -- diagonal para trás à direita
	assert(x > 0 and y < 0)
	near(math.sqrt(x * x + y * y), Toque.stickValue(R * 0.6 * math.sqrt(2), 0, R), 1e-9, "magnitude igual em diagonal")
	local st = Toque.newStick()
	local _, _, run = Toque.stickStep(st, true, 0, -R * 0.5, R)
	assert(not run, "metade não corre")
	_, _, run = Toque.stickStep(st, true, 0, -R, R)
	assert(run, "borda para a frente corre")
	_, _, run = Toque.stickStep(st, true, 0, -R * 0.85, R)
	assert(run, "histerese: um pouco abaixo da borda segue correndo")
	_, _, run = Toque.stickStep(st, true, 0, -R * 0.5, R)
	assert(not run, "voltou para a metade: para de correr")
	_, _, run = Toque.stickStep(st, true, R, 0, R)
	assert(not run, "de lado não corre")
	_, _, run = Toque.stickStep(st, true, 0, R, R)
	assert(not run, "para trás não corre")
	local _, _, idle = Toque.stickStep(st, false, 0, 0, R)
	assert(not idle, "sem dedo, sem corrida")
end)

test("trava da corrida: arrastar até o cadeado trava; tocar no analógico, mirar ou atirar destrava", function()
	local R = 80
	local st = Toque.newStick()
	local x, y, run = Toque.stickStep(st, true, 0, -R * (Toque.LOCK_K + 0.1), R)
	assert(st.locked and st.inLock and run and x == 0 and y == 1, "no cadeado: trava e corre reto")
	-- solta o dedo: continua correndo para a frente
	x, y, run = Toque.stickStep(st, false, 0, 0, R)
	assert(st.locked and run and y == 1, "solto: segue correndo")
	-- tocar no analógico destrava
	Toque.stickBegan(st)
	assert(not st.locked)
	x, y, run = Toque.stickStep(st, true, 0, -R * 0.3, R)
	assert(not run and y > 0 and y < 0.5)
	-- arrastar até o cadeado e voltar sem soltar destrava
	Toque.stickStep(st, true, 0, -R * 2, R)
	assert(st.locked)
	Toque.stickStep(st, true, 0, -R * 0.9, R)
	assert(not st.locked, "saiu do cadeado com o dedo no chão")
	-- cadeado só em frente: de lado não trava
	Toque.stickStep(st, true, R * 2, -R * 0.4, R)
	assert(not st.locked)
	-- mirar ou atirar destrava
	Toque.stickStep(st, true, 0, -R * 2, R)
	Toque.stickStep(st, false, 0, 0, R)
	assert(st.locked)
	Toque.unlock(st)
	local _, _, after = Toque.stickStep(st, false, 0, 0, R)
	assert(not st.locked and not after, "mira/tiro destravou")
end)

test("transpor sozinho: correndo contra o obstáculo, uma vez por segundo, e só com a opção", function()
	local v = Toque.newVault()
	local base = { enabled = true, sprinting = true, forward = true, grounded = true, speedRatio = 0.1 }
	local fired, t = 0, 0
	for _ = 1, 120 do -- 2 s a 60 quadros
		t += 1 / 60
		if Toque.autoVault(v, 1 / 60, t, base) then
			fired += 1
		end
	end
	assert(fired == 2, "duas tentativas em 2 s, veio " .. fired)
	local v2 = Toque.newVault()
	for _, k in { "enabled", "sprinting", "forward", "grounded" } do
		local i = table.clone(base) :: any
		i[k] = false
		for n = 1, 60 do
			assert(not Toque.autoVault(v2, 1 / 60, n / 60, i), k .. " desligado")
		end
	end
	local i = table.clone(base)
	i.speedRatio = 0.8 -- andando livre
	for n = 1, 60 do
		assert(not Toque.autoVault(v2, 1 / 60, n / 60, i), "sem obstáculo")
	end
end)

test("mira no toque: alternar (padrão) ou segurar; o 'alternar' do controle continua valendo", function()
	assert(D.touchAimToggle == true, "padrão no toque: alternar")
	-- alternar: toque liga (fica apertado), soltar o dedo não muda, outro toque desliga
	local ops, latched = Toque.aimOps(true, false, false, true)
	assert(#ops == 1 and ops[1] == true and latched)
	ops, latched = Toque.aimOps(true, false, latched, false)
	assert(#ops == 0 and latched, "soltar o dedo mantém a mira")
	ops, latched = Toque.aimOps(true, false, latched, true)
	assert(#ops == 1 and ops[1] == false and not latched)
	-- segurar
	ops, latched = Toque.aimOps(false, false, false, true)
	assert(ops[1] == true and latched)
	ops, latched = Toque.aimOps(false, false, latched, false)
	assert(ops[1] == false and not latched)
	-- "Mirar: alternar" do Acessib.: o WeaponController alterna; o toque só aperta e solta
	ops, latched = Toque.aimOps(true, true, false, true)
	assert(#ops == 2 and ops[1] == true and ops[2] == false and not latched)
	ops = Toque.aimOps(false, true, false, false)
	assert(#ops == 0)
end)

test("tiro no toque: semiautomático = um tiro por toque; automático = enquanto segura", function()
	local function shots(mode: string, holdS: number, taps: number): number
		local t = Gatilho.new("type56", mode, 30)
		local n, now = 0, 0
		for _ = 1, taps do
			Gatilho.press(t, now) -- dedo no botão de tiro (Input.virtual("fire", true))
			local untilT = now + holdS
			while now < untilT do
				if Gatilho.step(t, now) == "fire" then
					n += 1
				end
				now += 1 / 60
			end
			Gatilho.release(t, now) -- dedo solto
			for _ = 1, 30 do
				if Gatilho.step(t, now) == "fire" then
					n += 1
				end
				now += 1 / 60
			end
		end
		return n
	end
	assert(shots("semi", 1.0, 1) == 1, "semi segurado 1 s: um tiro só")
	assert(shots("semi", 0.05, 3) == 3, "três toques, três tiros")
	assert(shots("auto", 1.0, 1) >= 8, "automático segurando 1 s: rajada")
	assert(shots("auto", 0.02, 1) <= 2, "toque rápido no automático: um ou dois")
end)

test("olhar pelo arrasto: sensibilidades separadas, aceleração opcional, inverter Y", function()
	local s = InputMap.validate(nil) :: any
	local dpi = 160
	local px = Toque.rawPx(10, 390, dpi) -- 10 mm de arrasto
	local hip = Toque.lookDelta(px, 0, 1 / 60, dpi, s, "hip")
	local ads = Toque.lookDelta(px, 0, 1 / 60, dpi, s, "ads")
	local scope = Toque.lookDelta(px, 0, 1 / 60, dpi, s, "scope")
	near(hip, 10 * Toque.LOOK_DEG_PER_MM, 1e-6, "quadril: graus por mm")
	assert(hip > ads and ads > scope and scope > 0, "quadril > ferro > luneta")
	local _, up = Toque.lookDelta(0, -px, 1 / 60, dpi, s, "hip")
	assert(up > 0, "arrastar para cima olha para cima")
	local inv = InputMap.validate({ invertY = true }) :: any
	local _, upInv = Toque.lookDelta(0, -px, 1 / 60, dpi, inv, "hip")
	assert(upInv < 0, "Y invertido")
	local a, b = Toque.lookDelta(0, 0, 1 / 60, dpi, s, "hip")
	assert(a == 0 and b == 0)
	-- aceleração: só com a opção e só no arrasto rápido
	local acc = InputMap.validate({ touchAccel = true }) :: any
	local slowPx = Toque.rawPx(0.5, 390, dpi) -- 0,5 mm num quadro = 30 mm/s
	near(Toque.lookDelta(slowPx, 0, 1 / 60, dpi, acc, "hip"), Toque.lookDelta(slowPx, 0, 1 / 60, dpi, s, "hip"), 1e-9)
	assert(Toque.lookDelta(px, 0, 1 / 60, dpi, acc, "hip") > hip * 1.5, "arrasto rápido acelera")
	-- sensibilidade sobe, giro sobe
	local hi = InputMap.validate({ touchLookSens = 2 }) :: any
	near(Toque.lookDelta(px, 0, 1 / 60, dpi, hi, "hip"), hip * 2, 1e-6)
end)

test("giroscópio: desligado, só mirando ou sempre; sensibilidade própria; aparelho virado inverte", function()
	local rx, ry = math.rad(2), math.rad(3)
	local off = InputMap.validate(nil) :: any
	assert(off.gyroMode == "off")
	local a, b = Toque.gyroStep(rx, ry, false, off, "ads")
	assert(a == 0 and b == 0, "desligado")
	local aim = InputMap.validate({ gyroMode = "aim" }) :: any
	a, b = Toque.gyroStep(rx, ry, false, aim, "hip")
	assert(a == 0 and b == 0, "só mirando: no quadril nada")
	a, b = Toque.gyroStep(rx, ry, false, aim, "ads")
	near(a, 3, 1e-9, "giro horizontal")
	near(b, 2, 1e-9, "giro vertical")
	local fa, fb = Toque.gyroStep(rx, ry, true, aim, "scope")
	assert(fa == -a and fb == -b, "deitado para o outro lado inverte")
	local always = InputMap.validate({ gyroMode = "always", gyroSens = 2 }) :: any
	a = Toque.gyroStep(rx, ry, false, always, "hip")
	near(a, 6, 1e-9, "sempre, com sensibilidade 2")
	local t1, t2 = Toque.gyroStep(math.rad(0.005), math.rad(0.005), false, always, "hip")
	assert(t1 == 0 and t2 == 0, "tremor da mão parada")
end)

test("layouts: 2 polegares, 3 e 4 dedos, canhoto espelhado e os próprios por cima", function()
	local two = Toque.layout({ touchLayout = "two", touchMirror = false, touchCustom = {} })
	local three = Toque.layout({ touchLayout = "three", touchMirror = false, touchCustom = {} })
	local four = Toque.layout({ touchLayout = "four", touchMirror = false, touchCustom = {} })
	for _, d in Toque.BUTTONS do
		assert(two[d.id] and three[d.id] and four[d.id], d.id .. " sem lugar")
	end
	assert(not two.fire_left.on and three.fire_left.on and four.fire_left.on, "tiro esquerdo opcional")
	assert(four.aim.y < two.aim.y, "4 dedos: mira no alto para o indicador")
	assert(two.stick.x < 0.5 and two.fire.x > 0.5, "polegar esquerdo anda, direito atira")
	assert(two.map.x < 0.5 and two.map.y < 0.2 and two.comm.x > 0.5 and two.comm.y < 0.2, "alto: mapa e comunicação")
	-- espelho
	local m = Toque.layout({ touchLayout = "three", touchMirror = true, touchCustom = {} })
	for id, sl in three do
		near(m[id].x, 1 - sl.x, 1e-9, id .. " espelhado")
		near(m[id].y, sl.y, 1e-9)
	end
	-- próprio: por cima do de 2 polegares (botão novo fica no lugar padrão)
	local custom = {
		custom2 = {
			fire = { x = 0.7, y = 0.5, scale = 1.3, alpha = 0.5 },
			fire_left = { x = 0.2, y = 0.2, scale = 1, alpha = 1, on = true },
		},
	}
	local c = Toque.layout({ touchLayout = "custom2", touchMirror = false, touchCustom = custom })
	assert(c.fire.x == 0.7 and c.fire.scale == 1.3 and c.fire.alpha == 0.5 and c.fire_left.on)
	assert(c.aim.x == two.aim.x, "o resto vem do padrão")
	local empty = Toque.layout({ touchLayout = "custom3", touchMirror = false, touchCustom = custom })
	assert(empty.fire.x == two.fire.x, "espaço vazio = 2 polegares")
	-- salvar a partir da tela espelhada guarda o lado destro
	local mc = Toque.layout({ touchLayout = "custom2", touchMirror = true, touchCustom = custom })
	local saved = Toque.toCustom(mc, true)
	near(saved.fire.x, 0.7, 1e-9, "salvo sem espelho")
	assert(saved.fire.scale == 1.3 and saved.fire_left.on == true)
	-- o salvo passa no saneamento do servidor como veio
	local s = InputMap.validate({ touchCustom = { custom1 = saved }, touchLayout = "custom1" }) :: any
	near(s.touchCustom.custom1.fire.x, 0.7, 1e-9)
	assert(s.touchLayout == "custom1")
end)

test("touchCustom saneado: só 3 espaços, nomes curtos, números presos, lixo fora", function()
	local nan = 0 / 0
	local many = {}
	for i = 1, 60 do
		many["b" .. i] = { x = 0.5, y = 0.5 }
	end
	local s = InputMap.validate({
		touchCustom = {
			custom1 = {
				fire = { x = 2, y = -1, scale = 9, alpha = 0, on = "sim" },
				aim = { x = nan, y = 0.5 },
				reload = { x = "0.5", y = 0.5 },
				["bad id!"] = { x = 0.5, y = 0.5 },
				[1] = { x = 0.5, y = 0.5 },
				jump = "x",
				melee = { x = 0.3, y = 0.4, scale = nan, alpha = math.huge, on = false },
			},
			custom4 = { fire = { x = 0.5, y = 0.5 } },
			custom2 = many,
			custom3 = "lixo",
		},
	}) :: any
	local c1 = s.touchCustom.custom1
	assert(c1.fire.x == 1 and c1.fire.y == 0 and c1.fire.scale == 1.5 and c1.fire.alpha == 0.1, "faixas")
	assert(c1.fire.on == nil, "on só booleano")
	assert(c1.aim == nil and c1.reload == nil and c1["bad id!"] == nil and c1.jump == nil, "lixo fora")
	assert(c1.melee.scale == 1 and c1.melee.alpha == 1 and c1.melee.on == false, "NaN/infinito")
	assert(s.touchCustom.custom4 == nil and s.touchCustom.custom3 == nil, "só custom1..3")
	local n = 0
	for _ in s.touchCustom.custom2 do
		n += 1
	end
	assert(n == 40, "até 40 botões por layout, veio " .. n)
	assert(next(InputMap.validate({ touchCustom = 5 }).touchCustom) == nil)
	assert(next(InputMap.validate(nil).touchCustom) == nil)
	-- o padrão não é compartilhado (mexer num validado não muda o DEFAULTS)
	local a = InputMap.validate(nil) :: any
	a.touchCustom.custom1 = {}
	assert(next(InputMap.DEFAULTS.touchCustom) == nil)
end)

test("chaves novas do contrato: padrões, faixas e escolhas", function()
	local want = {
		touchAimToggle = true,
		gyroMode = "off",
		gyroSens = 1,
		touchLookSens = 1,
		touchAdsSens = 0.6,
		touchScopeSens = 0.4,
		touchAccel = false,
		touchOpacity = 0.75,
		touchLayout = "two",
		touchMirror = false,
		touchAutoVault = true,
		batterySaver = false,
	}
	for k, v in want do
		assert(D[k] == v, string.format("padrão de %s: %s", k, tostring(D[k])))
	end
	local s = InputMap.validate({
		gyroMode = "girar",
		gyroSens = 10,
		touchLookSens = 0,
		touchAdsSens = 5,
		touchScopeSens = 0.01,
		touchOpacity = 0,
		touchLayout = "five",
		touchMirror = "sim",
		batterySaver = true,
		touchAutoVault = false,
	}) :: any
	assert(s.gyroMode == "off" and s.touchLayout == "two" and s.touchMirror == false, "escolhas")
	assert(s.gyroSens == 3 and s.touchLookSens == 0.2 and s.touchAdsSens == 2 and s.touchScopeSens == 0.1)
	assert(s.touchOpacity == 0.2 and s.batterySaver == true and s.touchAutoVault == false)
	for _, name in Toque.LAYOUTS do
		assert(InputMap.validate({ touchLayout = name }).touchLayout == name, name)
	end
	assert(not InputMap.BINDING_KEYS.touchLayout, "trocar o layout não refaz os bindings")
end)

test("botões: ações que existem, visibilidade por contexto e a especificação de cada botão", function()
	local ids: { [string]: boolean } = {}
	for _, a in InputMap.ACTIONS do
		ids[a.id] = true
	end
	for _, d in Toque.BUTTONS do
		if d.spec then
			local parts = Toque.parseSpec(d.spec)
			assert(#parts >= 1, d.id .. " sem ação")
			for _, p in parts do
				assert(ids[p.id], string.format("%s: ação %s não existe no InputMap", d.id, p.id))
			end
		else
			assert(d.kind == "stick" or d.kind == "slot", d.id .. " sem spec")
		end
	end
	local parts = Toque.parseSpec("view_toggle:tap|shoulder_swap:hold|x:bogus|ok")
	assert(
		#parts == 3
			and parts[1].kind == "tap"
			and parts[2].kind == "hold"
			and parts[3].id == "ok"
			and parts[3].kind == nil
	)
	assert(Toque.specHas("last_item|equip_wheel", "equip_wheel") and not Toque.specHas("crouch|prone", "jump"))
	-- caído: mapa, menu, comunicação, marcar e desistir; nada de tiro, analógico ou postura
	local function vis(id: string, c: Toque.Ctx): boolean
		return Toque.visible(Toque.BY_ID[id], c)
	end
	for _, id in { "map", "menu", "comm", "mark", "give_up" } do
		assert(vis(id, DOWNED), id .. " some caído")
	end
	for _, id in { "fire", "stick", "posture", "jump", "radio" } do
		assert(not vis(id, DOWNED), id .. " aparece caído")
	end
	-- veículo: o analógico, mapa, menu e rádio ficam; os de infantaria saem (os do veículo são do T3)
	for _, id in { "stick", "map", "menu", "radio" } do
		assert(vis(id, VEHICLE), id .. " some no veículo")
	end
	for _, id in { "fire", "aim", "reload", "posture", "jump", "comm", "lean_l" } do
		assert(not vis(id, VEHICLE), id .. " aparece no veículo")
	end
	-- a pé: prender a respiração só mirando; o rádio só com a voz
	local noAim = table.clone(FOOT)
	noAim.aiming = false
	assert(vis("hold_breath", FOOT) and not vis("hold_breath", noAim))
	local noVoice = table.clone(FOOT)
	noVoice.voice = false
	assert(vis("radio", FOOT) and not vis("radio", noVoice))
	assert(not vis("interact", FOOT), "a vaga do interagir é desenhada pelo T2")
	-- caído só aceita o que o InputMap deixa (os botões que aparecem caído funcionam)
	local st = InputMap.newState()
	InputMap.event(st, "downed")
	for _, id in { "map", "game_menu", "comm_wheel", "mark", "give_up" } do
		assert(InputMap.allowed(st, id), id .. " recusado caído")
	end
end)

test("contrato do Input no código: toque ativo, virtual, analógico virtual e a roda segurada", function()
	local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
	local input = fs.readFile(C .. "Input.luau")
	for _, fn in
		{
			"function Input.touchActive(): boolean",
			"function Input.virtual(spec: string, down: boolean",
			"function Input.setVirtualStick(which: string, v: Vector2)",
			"function Input.virtualDown(actionId: string): boolean",
			"function Input.recoilReturnK(): number",
		}
	do
		assert(string.find(input, fn, 1, true), "falta " .. fn)
	end
	assert(string.find(input, 'if device == "touch" then\n\t\treturn virtStick', 1, true), "stickRaw devolve o virtual")
	assert(string.find(input, "WindowFocusReleased", 1, true) and string.find(input, "WindowFocused", 1, true))
	local wheel = fs.readFile(C .. "Wheel.luau")
	assert(string.find(wheel, "Input.virtualDown(holdAction)", 1, true), "roda: botão virtual segurado")
	local wc = fs.readFile(C .. "WeaponController.client.luau")
	assert(string.find(wc, "Input.recoilReturnK()", 1, true), "volta do recuo mais rápida no toque")
	near(
		(
				string.match(input, "TOUCH_RECOIL_RETURN = ([%d%.]+)")
					and tonumber(string.match(input, "TOUCH_RECOIL_RETURN = ([%d%.]+)"))
				or 0
			) :: number,
		1.25,
		1e-9,
		"até 25%"
	)
	local proj = fs.readFile("default.project.json")
	assert(string.find(proj, '"ScreenOrientation": "LandscapeSensor"', 1, true), "horizontal")
	assert(string.find(proj, '"DevTouchMovementMode": "Scriptable"', 1, true), "movimento de toque programável")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
