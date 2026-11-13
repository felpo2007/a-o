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
	{ name = "celular 20:9", W = 775, H = 299, short = 324 },
	{ name = "tablet 4:3", W = 1000, H = 700, short = 732 },
	{ name = "tablet 16:10", W = 1259, H = 743, short = 764 },
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

-- Tudo o que o HUD de toque põe na tela num contexto: os botões, o anel de repouso do analógico e o
-- botão contextual de interagir (Interagir.client: 1,5 vez o mínimo de toque; desde a v39 o rótulo
-- fica dentro do botão, ToqueUi.roundButton).
type Shape = { id: string, cx: number, cy: number, r: number, label: Toque.Rect? }
local function report(bad: { string })
	for i, b in bad do
		if i > 40 then
			print(string.format("      ... e mais %d", #bad - 40))
			break
		end
		print("      " .. b)
	end
	assert(#bad == 0, string.format("%d problema(s)", #bad))
end
local function interactPx(short: number): number
	local min = math.max(math.floor(Toque.px(9, short) + 0.5), 40)
	return math.max(Toque.buttonPx(Toque.BY_ID.interact.mm, 1, short), math.floor(min * 1.5))
end
local function shapes(slots: { [string]: any }, sc: any, c: Toque.Ctx): { Shape }
	local out: { Shape } = {}
	for _, d in Toque.BUTTONS do
		local sl = slots[d.id]
		local vis = sl ~= nil and sl.on
		if vis and d.kind == "slot" then
			vis = c.foot and not c.downed and not c.vehicle
		elseif vis then
			vis = Toque.visible(d, c)
		end
		if vis then
			local size = if d.kind == "slot" then interactPx(sc.short) else Toque.buttonPx(d.mm, sl.scale, sc.short)
			local cx, cy = Toque.place(sl.x, sl.y, size, sc.W, sc.H)
			table.insert(out, { id = d.id, cx = cx, cy = cy, r = size / 2 })
		end
	end
	return out
end

local FOOT: Toque.Ctx = { foot = true, vehicle = false, downed = false, aiming = true, voice = true }
local DOWNED: Toque.Ctx = { foot = false, vehicle = false, downed = true, aiming = false, voice = true }
local VEHICLE: Toque.Ctx = { foot = false, vehicle = true, downed = false, aiming = false, voice = true }
-- a pé com TODOS os contextuais acesos (o pior caso): sem mirar e mirando na luneta
local FOOT_ALL: Toque.Ctx = {
	foot = true,
	vehicle = false,
	downed = false,
	aiming = false,
	voice = true,
	reload = true,
	melee = true,
	breath = true,
	bleed = true,
	command = true,
}
local AIM_ALL: Toque.Ctx = table.clone(FOOT_ALL)
AIM_ALL.aiming = true
local CTXS = { { "a pé", FOOT_ALL }, { "mirando", AIM_ALL }, { "caído", DOWNED }, { "veículo", VEHICLE } }

-- percorre layout pronto x canhoto x tela (o tablet usa o compacto, como o HUD)
local function eachLayout(fn: (name: string, mirror: boolean, sc: any, slots: { [string]: any }) -> ())
	for _, name in { "two", "three", "four" } do
		for _, mirror in { false, true } do
			for _, sc in SCREENS do
				local tablet = Toque.isTablet(sc.short)
				fn(
					name,
					mirror,
					sc,
					Toque.layout({ touchLayout = name, touchMirror = mirror, touchCustom = {} }, nil, tablet)
				)
			end
		end
	end
end

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

test(
	"layouts prontos: nada sobre nada e tudo na área (a pé, mirando, caído, veículo; 16:9 a 20:9 e tablet)",
	function()
		local bad = {}
		eachLayout(function(name, mirror, sc, slots)
			for _, cc in CTXS do
				local list = shapes(slots, sc, cc[2])
				local tag = string.format("%s%s %s %s", name, if mirror then " (canhoto)" else "", sc.name, cc[1])
				for i = 1, #list do
					local a = list[i]
					if a.cx - a.r < -0.5 or a.cx + a.r > sc.W + 0.5 or a.cy - a.r < -0.5 or a.cy + a.r > sc.H + 0.5 then
						table.insert(bad, string.format("%s: %s fora da área", tag, a.id))
					end
					local la = a.label
					if la and (la.x0 < -0.5 or la.x1 > sc.W + 0.5 or la.y1 > sc.H + 0.5) then
						table.insert(bad, string.format("%s: rótulo de %s fora da área", tag, a.id))
					end
					for j = i + 1, #list do
						local b = list[j]
						local d = math.sqrt((a.cx - b.cx) ^ 2 + (a.cy - b.cy) ^ 2)
						if d < a.r + b.r - 1 then
							table.insert(
								bad,
								string.format("%s: %s e %s se sobrepõem (%.0f < %.0f)", tag, a.id, b.id, d, a.r + b.r)
							)
						end
						local lb = b.label
						if la and Toque.circleHitsRect(b.cx, b.cy, b.r, la) then
							table.insert(bad, string.format("%s: rótulo de %s em cima de %s", tag, a.id, b.id))
						end
						if lb and Toque.circleHitsRect(a.cx, a.cy, a.r, lb) then
							table.insert(bad, string.format("%s: rótulo de %s em cima de %s", tag, b.id, a.id))
						end
					end
					-- o miolo da tela é da mira e do marcador de acerto
					local dc = math.sqrt((a.cx - sc.W / 2) ^ 2 + (a.cy - sc.H / 2) ^ 2)
					if dc < a.r + sc.H * 0.08 then
						table.insert(bad, string.format("%s: %s em cima da mira", tag, a.id))
					end
				end
			end
		end)
		report(bad)
	end
)

test(
	"zonas livres: faixa, bússola, eventos, avisos, cartão, captura, tutorial e vagas sem botão nem uma na outra",
	function()
		local bad = {}
		local names = {}
		for n in Toque.ZONES do
			table.insert(names, n)
		end
		table.sort(names)
		eachLayout(function(name, mirror, sc, slots)
			local index = slots.fire_left.on
			local rects: { [string]: Toque.Rect } = {}
			for _, n in names do
				rects[n] = Toque.zoneRect(n, sc.W, sc.H, mirror, index) :: Toque.Rect
			end
			local tag = string.format("%s%s %s", name, if mirror then " (canhoto)" else "", sc.name)
			for _, n in names do
				local z = rects[n]
				if
					z.x0 < -0.5
					or z.y0 < -0.5
					or z.x1 > sc.W + 0.5
					or z.y1 > sc.H + 0.5
					or z.x1 <= z.x0
					or z.y1 <= z.y0
				then
					table.insert(bad, string.format("%s: zona %s fora da área", tag, n))
				end
				-- a mira (o centro) nunca fica dentro de uma zona
				if sc.W / 2 > z.x0 and sc.W / 2 < z.x1 and sc.H / 2 > z.y0 and sc.H / 2 < z.y1 then
					table.insert(bad, string.format("%s: zona %s cobre a mira", tag, n))
				end
				local only = Toque.ZONE_CTX[n]
				for _, cc in CTXS do
					local skip = only == "downed" and not cc[2].downed
					for _, s in (if skip then {} else shapes(slots, sc, cc[2])) do
						if Toque.circleHitsRect(s.cx, s.cy, s.r, z) then
							table.insert(bad, string.format("%s %s: %s em cima da zona %s", tag, cc[1], s.id, n))
						end
						if s.label and Toque.rectsHit(s.label, z) then
							table.insert(bad, string.format("%s %s: rótulo de %s na zona %s", tag, cc[1], s.id, n))
						end
					end
				end
				for _, m in names do
					local shared = (Toque.ZONE_SHARE[n] and Toque.ZONE_SHARE[n][m])
						or (Toque.ZONE_SHARE[m] and Toque.ZONE_SHARE[m][n])
					if m > n and not shared and Toque.rectsHit(z, rects[m]) then
						table.insert(bad, string.format("%s: zonas %s e %s se cobrem", tag, n, m))
					end
				end
			end
		end)
		report(bad)
		-- canhoto espelha; com o tiro do indicador esquerdo a coluna da esquerda começa depois dele
		local z = Toque.zoneRect("cartao", 1000, 500, false) :: Toque.Rect
		local m = Toque.zoneRect("cartao", 1000, 500, true) :: Toque.Rect
		near(m.x0, 1000 - z.x1, 1e-9)
		near(m.x1, 1000 - z.x0, 1e-9)
		assert((Toque.zoneRect("eventos", 1000, 500, false, true) :: Toque.Rect).x0 > 0)
		assert(Toque.zoneRect("nao_existe", 1000, 500) == nil)
		-- caber na zona: nunca cresce além do teto, piso legível
		near(Toque.fitK(560, 52, 280, 52, 1, 0.4), 0.5, 1e-9)
		assert(Toque.fitK(100, 50, 1000, 1000, 1, 0.4) == 1 and Toque.fitK(1000, 50, 10, 10, 1, 0.4) == 0.4)
	end
)

test("tablet: os mesmos botões, mais perto dos cantos de baixo; a fileira do alto não muda", function()
	local phone = Toque.layout({ touchLayout = "two", touchMirror = false, touchCustom = {} })
	local tab = Toque.layout({ touchLayout = "two", touchMirror = false, touchCustom = {} }, nil, true)
	assert(not Toque.isTablet(390) and Toque.isTablet(768))
	for _, d in Toque.BUTTONS do
		local p, t = phone[d.id], tab[d.id]
		assert(p.on == t.on, d.id .. ": o tablet mostra o mesmo")
		if Toque.TOP_ROW[d.id] then
			assert(p.x == t.x and p.y == t.y, d.id .. " mudou no alto")
		else
			local edgeP = if p.x < 0.5 then p.x else 1 - p.x
			local edgeT = if t.x < 0.5 then t.x else 1 - t.x
			assert(edgeT <= edgeP + 1e-9 and 1 - t.y <= 1 - p.y + 1e-9, d.id .. " não foi para o canto")
		end
	end
	-- o rádio fica no alto à direita (a fileira de LUGAR/SAIR do ToqueVeiculo se apoia nele)
	assert(tab.radio.x > 0.5 and tab.radio.y < 0.2)
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
		-- v39: automáticos do toque (o tiro sozinho vem desligado) e a recarga automática (frente de itens)
		touchAutoLean = true,
		touchAutoPickup = true,
		touchAutoBreath = true,
		touchAssist = true,
		touchAutoFire = false,
		autoReload = true,
	}
	for k, v in want do
		assert(D[k] == v, string.format("padrão de %s: %s", k, tostring(D[k])))
	end
	local off = InputMap.validate({
		touchAutoLean = false,
		touchAutoPickup = false,
		touchAutoBreath = false,
		touchAssist = false,
		touchAutoFire = true,
	}) :: any
	assert(
		not off.touchAutoLean and not off.touchAutoPickup and not off.touchAutoBreath and not off.touchAssist,
		"dá para desligar cada automático"
	)
	assert(off.touchAutoFire == true and InputMap.validate({ touchAutoFire = "sim" }).touchAutoFire == false)
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
	-- caído: mapa, menu, comunicação (marcar no toque) e desistir; nada de tiro, analógico ou postura
	local function vis(id: string, c: Toque.Ctx): boolean
		return Toque.visible(Toque.BY_ID[id], c)
	end
	for _, id in { "map", "menu", "comm", "give_up" } do
		assert(vis(id, DOWNED), id .. " some caído")
	end
	for _, id in { "fire", "stick", "posture", "jump", "radio", "reload", "bandage" } do
		assert(not vis(id, DOWNED), id .. " aparece caído")
	end
	-- veículo: o analógico, mapa, menu e rádio ficam; os de infantaria saem (os do veículo são do T3)
	for _, id in { "stick", "map", "menu", "radio" } do
		assert(vis(id, VEHICLE), id .. " some no veículo")
	end
	for _, id in { "fire", "aim", "reload", "posture", "jump", "comm", "lean_l", "melee", "bandage" } do
		assert(not vis(id, VEHICLE), id .. " aparece no veículo")
	end
	local noVoice = table.clone(FOOT)
	noVoice.voice = false
	assert(vis("radio", FOOT) and not vis("radio", noVoice), "o rádio só com a voz")
	assert(not vis("interact", FOOT), "a vaga do interagir é desenhada pelo Interagir.client")
	-- caído só aceita o que o InputMap deixa (os botões que aparecem caído funcionam)
	local st = InputMap.newState()
	InputMap.event(st, "downed")
	for _, id in { "map", "game_menu", "comm_wheel", "mark", "give_up" } do
		assert(InputMap.allowed(st, id), id .. " recusado caído")
	end
end)

test("tela enxuta: fixos só os do uso o tempo todo; o resto some, vira contextual ou vai para o menu", function()
	local function vis(id: string, c: Toque.Ctx): boolean
		return Toque.visible(Toque.BY_ID[id], c)
	end
	-- a pé, sem nada acontecendo: só analógico, tiro, mira, pular, agachar, ITEM, COMUNICAR, mapa e
	-- menu (o cartão da arma é do HudCampo; o interagir, do Interagir.client)
	local calm: Toque.Ctx = { foot = true, vehicle = false, downed = false, aiming = false, voice = false }
	local slots = Toque.layout({ touchLayout = "two", touchMirror = false, touchCustom = {} })
	local shown = {}
	for _, d in Toque.BUTTONS do
		if d.kind ~= "slot" and slots[d.id].on and Toque.visible(d, calm) then
			table.insert(shown, d.id)
		end
	end
	table.sort(shown)
	assert(
		table.concat(shown, ",") == "aim,comm,equip,fire,jump,map,menu,posture,stick",
		"fixos: " .. table.concat(shown, ",")
	)
	-- os que saíram da tela: troca de arma e seletor no cartão, marcar no COMUNICAR, câmera no menu,
	-- canal no RÁDIO
	for _, id in { "swap", "fire_mode", "mark", "view", "channel" } do
		assert(Toque.BY_ID[id] == nil, id .. " ainda é botão")
	end
	assert(Toque.specHas(Toque.BY_ID.comm.spec :: string, "mark"), "tocar no COMUNICAR marca")
	assert(Toque.specHas(Toque.BY_ID.comm.spec :: string, "comm_wheel"), "segurar abre a roda")
	local rp = Toque.parseSpec(Toque.BY_ID.radio.spec :: string)
	assert(rp[1].id == "radio_channel" and rp[1].kind == "tap" and rp[2].id == "radio_talk" and rp[2].kind == "hold")
	-- inclinar: opcional (desligado; o automático inclina na quina), o editor liga
	assert(Toque.BY_ID.lean_l.optional and not slots.lean_l.on and not slots.lean_r.on)
	-- contextuais: cada um só com o seu motivo
	local function with(k: string, v: boolean, aiming: boolean?): Toque.Ctx
		local c = table.clone(calm) :: any
		c[k] = v
		c.aiming = aiming == true
		return c
	end
	assert(vis("reload", with("reload", true)) and not vis("reload", calm))
	assert(vis("melee", with("melee", true)) and not vis("melee", calm))
	assert(not vis("melee", with("melee", true, true)), "golpe nunca mirando (divide o lugar com o fôlego)")
	assert(vis("hold_breath", with("breath", true, true)) and not vis("hold_breath", with("breath", true)))
	assert(vis("bandage", with("bleed", true)) and not vis("bandage", calm))
	assert(vis("radio", with("command", true)) and not vis("radio", calm), "rádio: quem fala com o comando")
	local cmdCar = table.clone(VEHICLE)
	cmdCar.voice, cmdCar.command = false, true
	assert(not vis("radio", cmdCar), "no veículo o canal não vale: só com a voz")
	-- golpe e fôlego dividem o lugar e nunca aparecem juntos
	for _, name in { "two", "three", "four" } do
		local l = Toque.layout({ touchLayout = name, touchMirror = false, touchCustom = {} })
		assert(l.melee.x == l.hold_breath.x and l.melee.y == l.hold_breath.y, name)
	end
	assert(not (vis("melee", AIM_ALL) and vis("hold_breath", AIM_ALL)))
	assert(not (vis("melee", FOOT_ALL) and vis("hold_breath", FOOT_ALL)))
end)

test("layout salvo da v38: continua valendo; botão que saiu do jogo é ignorado sem quebrar", function()
	local old = {
		custom1 = {
			fire = { x = 0.8, y = 0.6, scale = 1.2, alpha = 0.9, on = true },
			swap = { x = 0.62, y = 0.88, scale = 1, alpha = 1, on = true },
			fire_mode = { x = 0.52, y = 0.91, scale = 1, alpha = 1, on = true },
			view = { x = 0.23, y = 0.09, scale = 1, alpha = 1, on = true },
			mark = { x = 0.8, y = 0.09, scale = 1, alpha = 1, on = true },
			channel = { x = 0.325, y = 0.09, scale = 1, alpha = 1, on = true },
			reload = { x = 0.75, y = 0.47, scale = 1.1, alpha = 1, on = true },
		},
	}
	local s = InputMap.validate({ touchLayout = "custom1", touchCustom = old }) :: any
	local l = Toque.layout(s, false)
	assert(l.fire.x == 0.8 and l.fire.scale == 1.2, "o tiro salvo vale")
	assert(l.reload.x == 0.75 and l.reload.scale == 1.1, "a recarga salva vale (contextual)")
	for _, id in { "swap", "fire_mode", "view", "mark", "channel" } do
		assert(l[id] == nil, id .. " voltou")
	end
	-- no tablet o salvo vale como está (o compacto é só dos prontos)
	local lt = Toque.layout(s, false, true)
	assert(lt.fire.x == 0.8 and lt.fire.y == 0.6)
	-- salvar de novo limpa o que saiu
	local again = Toque.toCustom(l, false)
	assert(again.swap == nil and again.view == nil and again.fire ~= nil)
end)

test("contextuais: recarga (com e sem a automática), golpe à vista e bandagem", function()
	local base = { mag = 10, size = 20, spare = 40, reloading = false, auto = false, sinceShot = 0 }
	local function r(over: { [string]: any }): boolean
		local i = table.clone(base) :: any
		for k, v in over do
			i[k] = v
		end
		return Toque.showReload(i)
	end
	assert(r({}), "sem a automática: carregador gasto mostra")
	assert(r({ mag = 19 }), "um tiro já mostra")
	assert(not r({ mag = 20 }), "cheio não mostra")
	assert(not r({ spare = 0 }), "sem reserva não mostra")
	assert(not r({ reloading = true }), "recarregando não mostra")
	assert(
		not Toque.showReload({ mag = nil, size = 20, spare = 40, reloading = false, auto = false, sinceShot = 0 })
			and not r({ size = 0 }),
		"sem arma não mostra"
	)
	assert(r({ mag = 0 }), "vazio sem a automática mostra")
	-- com a automática: só a recarga tática numa pausa
	assert(not r({ auto = true, mag = 0, sinceShot = 5 }), "vazio: a automática cobre")
	assert(not r({ auto = true, mag = 15, sinceShot = 5 }), "mais da metade: não")
	assert(not r({ auto = true, mag = 10, sinceShot = 0.5 }), "atirando: não")
	assert(r({ auto = true, mag = 10, sinceShot = Toque.RELOAD_PAUSE_S }), "metade, na pausa: sim")
	-- golpe: à vista, a até 4 m, na frente (o alcance do golpe mais longo é 2,1 m)
	assert(Toque.meleeNear(2, 10, true) and Toque.meleeNear(Toque.MELEE_M, Toque.MELEE_DEG, true))
	assert(not Toque.meleeNear(2, 10, false), "atrás da parede não")
	assert(not Toque.meleeNear(4.5, 10, true) and not Toque.meleeNear(2, 120, true))
	local Melee = require(S .. "Melee") :: any
	for _, a in Melee.ATTACKS or {} do
		assert(a.reachM < Toque.MELEE_M, "golpe alcança além do botão")
	end
	-- bandagem
	assert(Toque.showBandage(0.4, 1, 0) and Toque.showBandage(0.4, 0, 1))
	assert(not Toque.showBandage(0, 3, 1) and not Toque.showBandage(0.4, 0, 0) and not Toque.showBandage(nil, 3, 3))
end)

test("inclinar sozinho na quina: só mirando, depois de 0,2 s, para o lado aberto; sai quando a quina acaba", function()
	local st = Toque.newLean()
	local i = {
		enabled = true,
		aiming = true,
		blocked = false,
		manual = false,
		ahead = true,
		clearL = false,
		clearR = true,
	}
	local side = 0
	for _ = 1, 6 do
		side = Toque.autoLean(st, 1 / 60, i)
	end
	assert(side == 0, "passar rente não inclina")
	for _ = 1, 12 do
		side = Toque.autoLean(st, 1 / 60, i)
	end
	assert(side == 1, "quina com a direita aberta: inclina à direita")
	-- já inclinado, a quina continua: fica
	assert(Toque.autoLean(st, 1 / 60, i) == 1)
	-- a parede à frente acabou (andou): volta
	local j = table.clone(i)
	j.ahead = false
	assert(Toque.autoLean(st, 1 / 60, j) == 0)
	-- os dois lados abertos (poste fino) ou nenhum: não inclina
	for _, k in { { true, true }, { false, false } } do
		local s2 = Toque.newLean()
		local x = table.clone(i)
		x.clearL, x.clearR = k[1], k[2]
		for _ = 1, 60 do
			assert(Toque.autoLean(s2, 1 / 60, x) == 0)
		end
	end
	-- sem mirar, desligado, correndo/deitado ou com o botão manual: nada
	for _, key in { "aiming", "enabled" } do
		local s3 = Toque.newLean()
		local x = table.clone(i) :: any
		x[key] = false
		for _ = 1, 60 do
			assert(Toque.autoLean(s3, 1 / 60, x) == 0, key)
		end
	end
	for _, key in { "blocked", "manual" } do
		local s3 = Toque.newLean()
		local x = table.clone(i) :: any
		x[key] = true
		for _ = 1, 60 do
			assert(Toque.autoLean(s3, 1 / 60, x) == 0, key)
		end
	end
	-- esquerda
	local s4 = Toque.newLean()
	local l = table.clone(i)
	l.clearL, l.clearR = true, false
	for _ = 1, 30 do
		side = Toque.autoLean(s4, 1 / 60, l)
	end
	assert(side == -1)
end)

test("ímã leve no toque: só mirando, alvo à vista, mexendo a mira; até 1,5°/s e nunca passa do alvo", function()
	local dt = 1 / 60
	local cone = Toque.magnetCone(50)
	assert(cone > 0 and cone < 5, string.format("cone a 50 m: %.2f°", cone))
	local pull = Toque.magnet(true, "ads", true, 50, cone * 0.5, true, dt)
	assert(pull > 0 and pull <= Toque.MAGNET_DEG_S * dt + 1e-9, "puxão pequeno")
	assert(Toque.magnet(true, "ads", true, 50, 0.001, true, dt) <= 0.001 * 0.25 + 1e-12, "nunca passa do alvo")
	assert(Toque.magnet(true, "hip", true, 50, cone * 0.5, true, dt) == 0, "quadril: nada")
	assert(Toque.magnet(true, "ads", false, 50, cone * 0.5, true, dt) == 0, "atrás de mata/fumaça: nada")
	assert(Toque.magnet(true, "ads", true, 50, cone * 0.5, false, dt) == 0, "parado: não gruda sozinho")
	assert(Toque.magnet(true, "ads", true, 50, cone * 1.01, true, dt) == 0, "fora do cone")
	assert(Toque.magnet(true, "ads", true, 200, 0.1, true, dt) == 0, "além de 150 m")
	assert(Toque.magnet(false, "ads", true, 50, cone * 0.5, true, dt) == 0, "desligado")
	assert(Toque.ASSIST_RANGE_M == InputMap.ASSIST_RANGE_M, "o mesmo alcance da fricção")
	-- em 1 s de arrasto o ímã sozinho fecha no máximo 1,5°
	local total = 0
	for _ = 1, 60 do
		total += Toque.magnet(true, "ads", true, 30, 2, true, dt)
	end
	assert(total <= Toque.MAGNET_DEG_S + 1e-9)
end)

test("tiro sozinho (opção desligada): espera a reação, semi em toques espaçados, automático segura", function()
	local dt = 1 / 60
	local function run(full: boolean, seconds: number, onTarget: boolean): (number, number)
		local st = Toque.newAutoFire()
		local presses, firstAt = 0, -1
		local t = 0
		local i = { enabled = true, aiming = true, onTarget = onTarget, full = full, canFire = true }
		while t < seconds do
			t += dt
			local op = Toque.autoFire(st, dt, t, i)
			if op == "press" then
				presses += 1
				if firstAt < 0 then
					firstAt = t
				end
			end
		end
		return presses, firstAt
	end
	local n, first = run(false, 1.0, true)
	assert(first >= Toque.AUTOFIRE_REACT_S - 1e-9, string.format("1º tiro em %.2f s", first))
	assert(n >= 2 and n <= math.ceil((1 - Toque.AUTOFIRE_REACT_S) / Toque.AUTOFIRE_GAP_S) + 1, "semi: " .. n)
	local na = run(true, 1.0, true)
	assert(na == 1, "automático: um aperto segurado")
	assert(run(false, 1.0, false) == 0, "sem alvo, nada")
	-- solta ao perder o alvo e quando para de mirar
	local st = Toque.newAutoFire()
	local i = { enabled = true, aiming = true, onTarget = true, full = true, canFire = true }
	local held = false
	for k = 1, 30 do
		local op = Toque.autoFire(st, dt, k * dt, i)
		if op == "press" then
			held = true
		end
	end
	assert(held)
	i.aiming = false
	assert(Toque.autoFire(st, dt, 1, i) == "release", "parou de mirar: solta")
	for _, key in { "enabled", "aiming", "canFire" } do
		local x = { enabled = true, aiming = true, onTarget = true, full = false, canFire = true } :: any
		x[key] = false
		local s2 = Toque.newAutoFire()
		for k = 1, 120 do
			assert(Toque.autoFire(s2, dt, k * dt, x) == nil, key)
		end
	end
	assert(D.touchAutoFire == false, "vem desligado")
end)

test("pegar munição e abrir caixote ao encostar; respiração sozinha solta antes de cansar", function()
	assert(Toque.autoPickup(true, "ammo", 1, 0.2, 5, 60))
	assert(Toque.autoPickup(true, "crate", Toque.PICKUP_M, Toque.PICKUP_SPEED, 5, 60))
	assert(not Toque.autoPickup(true, "weapon", 1, 0, 5, 60), "arma do chão é escolha")
	assert(not Toque.autoPickup(true, "radio", 1, 0, 5, 60) and not Toque.autoPickup(true, nil, 1, 0, 5, 60))
	assert(not Toque.autoPickup(true, "ammo", 2.5, 0, 5, 60), "longe")
	assert(not Toque.autoPickup(true, "ammo", 1, 4, 5, 60), "passando correndo")
	assert(not Toque.autoPickup(true, "ammo", 1, 0, 0.5, 60), "em combate")
	assert(not Toque.autoPickup(true, "ammo", 1, 0, 5, 3), "acabou de pegar")
	assert(not Toque.autoPickup(false, "ammo", 1, 0, 5, 60), "desligado")
	local Weapons = require(S .. "Weapons") :: any
	local K = Weapons.BREATH_TIRED_K
	assert(type(K) == "number" and K > 0 and K <= 1)
	local len = 4
	assert(not Toque.breathRelease(1, len, K))
	assert(Toque.breathRelease(len * K - Toque.BREATH_EARLY_S, len, K), "solta antes do cansaço")
	assert(len * K - Toque.BREATH_EARLY_S < len * K, "nunca chega ao cansaço")
end)

test("transpor sozinho também andando firme (obstáculo baixo)", function()
	local v = Toque.newVault()
	local i = { enabled = true, sprinting = false, walking = true, forward = true, grounded = true, speedRatio = 0.1 }
	local fired = 0
	for n = 1, 60 do
		if Toque.autoVault(v, 1 / 60, n / 60, i) then
			fired += 1
		end
	end
	assert(fired == 1, "andando contra o obstáculo: tenta")
	local w = Toque.newVault()
	i.walking = false
	for n = 1, 60 do
		assert(not Toque.autoVault(w, 1 / 60, n / 60, i), "parado não")
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
