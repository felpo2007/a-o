--!strict
-- Testes das armas (2026-11-12, pedido do dono: "as armas não estão automáticas", "algumas armas
-- não estão atirando", "faça sniper", "atirar de dentro dos veículos").
-- Um teste por arma passa pelo caminho inteiro com os módulos puros: o cliente (Shared/Gatilho, a
-- 60 quadros por segundo, como o WeaponController) aperta o gatilho e cada tiro viaja pela rede (70 ms
-- ± 40 ms, em ordem) até o servidor (Gatilho.validate, como o CombatService), que confere arma, modo
-- do papel, munição, recarga, cadência, origem e lugar do veículo.
-- Uso: lune run tests/luau/armas.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Weapons = require(S .. "Weapons") :: any
local Gatilho = require(S .. "Gatilho") :: any
local Ballistics = require(S .. "Ballistics") :: any
local Roles = require(S .. "Roles") :: any
local Vehicles = require(S .. "Vehicles") :: any
local Rng = require(S .. "Rng") :: any

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

local DT = 1 / 60

-- papel que leva a arma no jogo (o 1º que a tem no Roles; senão o fuzileiro)
local function roleOf(wp: any): string
	for role, list in Roles.loadout[wp.faction] do
		if table.find(list, wp.id) then
			return role
		end
	end
	return "rifleman"
end

local function newRec(wp: any, spare: number): any
	return { weapon = wp.id, mag = wp.magazine, spare = spare, reloadUntil = 0, gate = Gatilho.newGate() }
end

-- Simula o cliente e o servidor. `plan(t)` devolve true enquanto o dedo está no gatilho.
-- Devolve tiros do cliente, aceitos e recusados no servidor (com os motivos) e cliques secos.
type Result = { shots: number, accepted: number, refused: { [string]: number }, dry: number, mag: number }
local function run(wp: any, mode: string, role: string?, plan: (number) -> boolean, secs: number, opts: any?): Result
	local o = opts or {}
	local trig = Gatilho.new(wp.id, mode, o.mag or wp.magazine)
	local rec = o.rec or newRec(wp, 3)
	rec.mag = o.mag or wp.magazine
	local rng = Rng.new(o.seed or 7)
	local queue: { { arrive: number, t: number } } = {}
	local lastArrive = 0
	local res: Result = { shots = 0, accepted = 0, refused = {}, dry = 0, mag = 0 }
	local down = false
	local now = 0
	while now < secs + 0.5 do
		local want = now < secs and plan(now)
		if want and not down then
			Gatilho.press(trig, now)
		elseif not want and down then
			Gatilho.release(trig, now)
		end
		down = want
		local act = Gatilho.step(trig, now)
		if act == "fire" then
			res.shots += 1
			-- o cliente pode mandar mais rápido que a arma (trapaça): o servidor confere
			local lat = (o.lag or 0.07) + (rng:next() - 0.5) * 2 * (o.jitter or 0.04)
			local arrive = math.max(lastArrive, now + lat)
			lastArrive = arrive
			table.insert(queue, { arrive = arrive, t = now + (o.clockSkew or 0) })
		elseif act == "dry" then
			res.dry += 1
		end
		-- chegadas no servidor até agora
		while #queue > 0 and queue[1].arrive <= now do
			local s = table.remove(queue, 1) :: any
			local ok, why = Gatilho.validate(rec, {
				weapon = wp.id,
				mode = o.sendMode or mode,
				role = role,
				t = s.t,
				now = s.arrive,
				clock = s.arrive,
				originStuds = o.originStuds or 0.2,
				seat = o.seat,
			})
			if ok then
				res.accepted += 1
				rec.mag -= 1
			else
				res.refused[why] = (res.refused[why] or 0) + 1
			end
		end
		now += DT
	end
	res.mag = trig.mag
	return res
end

local function refusedText(r: Result): string
	local parts = {}
	for k, v in r.refused do
		table.insert(parts, k .. "=" .. v)
	end
	return table.concat(parts, ", ")
end

-- ===== um teste por arma =====
for _, wp in Weapons.list do
	if not wp.enabled then
		test(string.format("%s: fora do slot de arma (enabled = false)", wp.id), function()
			-- o RPG-2 atira pelo slot "launcher" do antitanque (VehicleService, PG-2)
			assert(wp.id == "rpg2", wp.id .. " desligada sem motivo")
		end)
		continue
	end
	local role = roleOf(wp)
	local modes = Weapons.modesFor(wp, role)
	local mode = modes[1]
	test(string.format("%s (%s, %s): segurar, tocar, munição, recarga e servidor", wp.id, role, mode), function()
		local iv = Weapons.interval(wp, mode)
		-- 1) segurar 1 s
		local hold = run(wp, mode, role, function()
			return true
		end, 1.0)
		if mode == "auto" then
			-- cadência cíclica: tiros em 1 s = 1 + floor(1 / intervalo), ou o carregador
			local expect = math.min(1 + math.floor(1.0 / iv + 1e-9), wp.magazine)
			assert(math.abs(hold.shots - expect) <= 1, string.format("auto: %d tiros, esperado %d", hold.shots, expect))
		else
			assert(hold.shots == 1, string.format("%s: segurar deu %d tiros", mode, hold.shots))
		end
		assert(
			hold.accepted == hold.shots,
			string.format("servidor aceitou %d de %d (%s)", hold.accepted, hold.shots, refusedText(hold))
		)
		-- 2) toques a cada 0,15 s por 1,2 s (8 toques), com o dedo 0,04 s no gatilho
		local taps = run(wp, mode, role, function(t)
			return (t % 0.15) < 0.04
		end, 1.2)
		local expect: number
		local manual = mode == "bolt" or mode == "pump" -- D-108: a bomba da espingarda segura como o ferrolho
		if manual then
			expect = 1 + math.floor(1.2 / iv) -- o ferrolho segura o ritmo; o toque guardado sai logo depois
		elseif mode == "single" then
			expect = 1 -- tiro único: carregador de 1
		else
			expect = math.min(8, wp.magazine)
		end
		assert(
			math.abs(taps.shots - expect) <= (if manual then 1 else 0),
			string.format("toques: %d tiros, esperado %d", taps.shots, expect)
		)
		assert(taps.accepted == taps.shots, string.format("toques: servidor recusou (%s)", refusedText(taps)))
		-- 3) carregador vazio: um clique seco por aperto, e o servidor não vê tiro
		local empty = run(wp, mode, role, function(t)
			return (t % 0.3) < 0.1
		end, 0.9, { mag = 0 })
		assert(
			empty.shots == 0 and empty.dry == 3,
			string.format("vazio: %d tiros, %d cliques", empty.shots, empty.dry)
		)
		-- 4) recarga: o servidor recusa durante e aceita depois
		local rec = newRec(wp, 2)
		rec.mag = 0
		rec.reloadUntil = 10
		local during = Gatilho.validate(
			rec,
			{ weapon = wp.id, mode = mode, role = role, t = 5, now = 5, clock = 5, originStuds = 0.2 }
		)
		assert(not during, "atirou recarregando")
		rec.mag, rec.spare = wp.magazine, rec.spare - 1
		local after = Gatilho.validate(
			rec,
			{ weapon = wp.id, mode = mode, role = role, t = 11, now = 11, clock = 11, originStuds = 0.2 }
		)
		assert(after, "não atirou depois da recarga")
		assert(Weapons.reloadTime(wp) > 0, "sem tempo de recarga")
		-- 5) alça: toda distância da alça tem ângulo e a queda nela é ~0
		for _, z in Weapons.zeros(wp) do
			local a = Ballistics.zeroAngle(wp.id, z)
			assert(a > 0, string.format("alça de %d m sem ângulo", z))
			near(Ballistics.dropAt(wp.id, z, z), 0, 0.05, string.format("queda na alça de %d m", z))
		end
		print(
			string.format(
				"       (%s: %s; intervalo %.3f s; segurar 1 s = %d tiro(s); 8 toques = %d; recarga %.1f s)",
				wp.id,
				table.concat(modes, "/"),
				iv,
				hold.shots,
				taps.shots,
				Weapons.reloadTime(wp)
			)
		)
	end)
end

-- ===== as causas achadas =====
test("SKS e pistolas: o semi não usa mais a cadência prática (SKS 1,5 s; pistola 0,5 s entre tiros)", function()
	for _, id in { "sks", "m1911", "type54" } do
		local wp = Weapons.get(id)
		near(Weapons.interval(wp, "semi"), Weapons.SEMI_MIN_S, 1e-9, id)
		assert(60 / wp.rpm >= 1.5 or id ~= "sks", "a cadência prática da SKS (bots) continua 40")
	end
end)

test("granadeiro: as duas armas do equipamento estão ligadas (a M79 desligada matava a pistola)", function()
	for _, f in { "US", "VC" } do
		for role, list in Roles.loadout[f] do
			for _, id in list do
				local wp = Weapons.get(id)
				assert(wp, role .. ": arma " .. id .. " não existe")
				assert(wp.enabled, role .. ": " .. id .. " desligada")
			end
		end
	end
	-- D-108: o granadeiro virou a M79 do fuzileiro (arma principal à escolha); todas as escolhas ligadas
	for _, f in { "US", "VC" } do
		for role, list in Roles.PRIMARY[f] do
			for _, id in list do
				local wp = Weapons.get(id)
				assert(wp and wp.enabled, role .. ": " .. id)
			end
		end
	end
	local g = Roles.loadoutFor("US", "rifleman", "m79")
	assert(g[1] == "m79" and g[2] == "m1911")
end)

test(
	"seletor: Tipo 56 sai no automático; M60 e RPD só automático; M14 semi salvo o fuzileiro automático",
	function()
		assert(Weapons.modesFor(Weapons.get("type56"), "squad_leader")[1] == "auto")
		assert(#Weapons.modesFor(Weapons.get("type56"), "rifleman") == 2)
		for _, id in { "m60", "rpd" } do
			local m = Weapons.modesFor(Weapons.get(id), "machine_gunner")
			assert(#m == 1 and m[1] == "auto", id)
		end
		local m14 = Weapons.get("m14")
		local rifleman = Weapons.modesFor(m14, "rifleman")
		assert(#rifleman == 1 and rifleman[1] == "semi", "M14 do fuzileiro: só semi")
		local ar = Weapons.modesFor(m14, Weapons.AUTO_RIFLEMAN)
		assert(#ar == 2 and ar[1] == "semi" and ar[2] == "auto", "M14 do fuzileiro automático: semi e auto")
		-- o servidor recusa o automático de quem não tem o seletor
		local r = run(m14, "auto", "rifleman", function()
			return true
		end, 0.5)
		assert(r.accepted == 0 and (r.refused["modo"] or 0) == r.shots and r.shots > 3, "M14 auto do fuzileiro passou")
		local r2 = run(m14, "auto", Weapons.AUTO_RIFLEMAN, function()
			return true
		end, 0.5)
		assert(r2.accepted == r2.shots and r2.shots >= 6, "M14 auto do fuzileiro automático: " .. r2.accepted)
	end
)

-- D-108 (classes mais simples): o fuzileiro automático virou o metralhador dos EUA com a M14
test("fuzileiro automático -> metralhador com a M14 (EUA): 1 por squad, seletor e bipé, posto livre", function()
	local Squads = require(S .. "Squads") :: any
	local Tutorial = require(S .. "Tutorial") :: any
	assert(Roles.roles.automatic_rifleman == nil, "o papel saiu")
	assert(Roles.migrate("automatic_rifleman") == "machine_gunner")
	assert(select(2, Roles.migrate("automatic_rifleman")) == "m14", "com a M14")
	assert(Weapons.AUTO_RIFLEMAN == "machine_gunner")
	assert(table.find(Roles.primaries("US", "machine_gunner"), "m14"), "M14 no metralhador dos EUA")
	assert(not table.find(Roles.primaries("VC", "machine_gunner"), "m14"), "só dos EUA")
	assert(Roles.minRank("machine_gunner") == Roles.minRank("rifleman"), "posto mínimo do fuzileiro")
	-- um por squad
	local st = Squads.new("US")
	local sq = Squads.create(st, "infantry", 1, 10) :: any
	assert(Squads.join(st, sq.id, 2) and Squads.join(st, sq.id, 3))
	assert(Squads.chooseRole(st, 2, "machine_gunner"))
	local ok, why = Squads.chooseRole(st, 3, "machine_gunner")
	assert(not ok and why == "vaga ocupada", "segundo metralhador no squad")
	-- arma: seletor e bipé só nele; M60 e RPD têm bipé integral
	local m14 = Weapons.get("m14")
	assert(Weapons.hasBipod(m14, "machine_gunner") and not Weapons.hasBipod(m14, "rifleman"))
	assert(Weapons.hasBipod(Weapons.get("m60"), nil) and Weapons.hasBipod(Weapons.get("rpd"), nil))
	assert(not Weapons.hasBipod(Weapons.get("type56"), "squad_leader"))
	local B = Weapons.BIPOD
	assert(B.prone.kick < B.rested.kick and B.rested.kick < 1 and B.prone.sway < 1, "bipé firma")
	-- tutorial: campo de tiro e o passo do seletor
	assert(Tutorial.RIFLE_ROLES.machine_gunner, "campo de tiro")
	local steps = Tutorial.steps("machine_gunner")
	assert(steps[#steps].action == "fire_mode", "passo do seletor")
	-- rajada de 1 s da M14 do metralhador: cadência cíclica (725/min), servidor aceita tudo
	local rr = run(m14, "auto", "machine_gunner", function()
		return true
	end, 1.0)
	assert(rr.shots >= 12 and rr.shots <= 14 and rr.accepted == rr.shots, rr.shots .. " / " .. rr.accepted)
end)

test("vantagens compradas nas armas, com e sem passe (recarga, fôlego, balanço, carregador, granada)", function()
	local Vantagens = require(S .. "Vantagens") :: any
	local Kit = require(S .. "Kit") :: any
	local none = Vantagens.compute({})
	local all = Vantagens.compute({ [Vantagens.BUNDLE] = true })
	local m14 = Weapons.get("m14")
	-- recarga: 2,4 s sem passe (D-107: era 3,0); 2,112 s com "Mãos Rápidas" (0,88)
	near(Weapons.reloadTime(m14, none.reload or 1), 2.4, 1e-9, "recarga sem passe")
	near(Weapons.reloadTime(m14, all.reload), 2.112, 1e-9, "recarga com passe")
	-- o servidor (Gatilho.validate) só devolve o gatilho depois da recarga de cada um
	for _, case in { { m = none.reload or 1, okAt = 2.4 }, { m = all.reload, okAt = 2.112 } } do
		local rec = newRec(m14, 2)
		rec.reloadUntil = Weapons.reloadTime(m14, case.m)
		local function at(t: number): boolean
			return (
				Gatilho.validate(
					rec,
					{ weapon = "m14", mode = "semi", role = "rifleman", t = t, now = t, clock = t, originStuds = 0.2 }
				)
			)
		end
		assert(not at(case.okAt - 0.02), "atirou antes do fim da recarga")
		assert(at(case.okAt + 0.02), "não atirou depois da recarga")
	end
	-- fôlego na luneta: 4 s sem passe; 6,4 s com "Fôlego de Atirador" (1,6). Fora da luneta, 4 s.
	near(Weapons.breathTime(true, none.breath or 1), 4.0, 1e-9)
	near(Weapons.breathTime(true, all.breath), 6.4, 1e-9)
	near(Weapons.breathTime(false, all.breath), 4.0, 1e-9)
	-- balanço na luneta: o 0,75 do plano passa pelo teto de 12% (0,88)
	near(all.sway, 0.88, 1e-9, "balanço com passe")
	assert(none.sway == nil, "sem passe, sem balanço a menos")
	-- carregadores e granadas: +1 cada, somando com o kit e o equipamento liberado
	assert(Weapons.magsFor(m14, nil, nil, none.mags or 0) == Kit.DEFAULT_MAGS.rifle, "dotação = kit padrão")
	assert(Weapons.magsFor(m14, nil, nil, all.mags) == 7)
	assert(Weapons.magsFor(m14, 4, 2, all.mags) == 7, "kit 4 + equipamento 2 + passe 1")
	assert(Weapons.magsFor(Weapons.get("m60"), nil, nil, all.mags) == 3)
	assert(Weapons.grenadesFor(nil, nil, none.grenades or 0) == 2 and Weapons.grenadesFor(nil, nil, all.grenades) == 3)
	assert(Weapons.grenadesFor(1, 1, all.grenades) == 3, "kit 1 + equipamento 1 + passe 1")
	-- leitura do atributo gravado pelo servidor (Vant_<chave>), com o teto mesmo se vier valor errado
	local roblox = require("@lune/roblox") :: any
	local who = roblox.Instance.new("Folder")
	assert(Vantagens.mult(who, "reload") == 1 and Vantagens.extra(who, "mags") == 0, "sem atributo = sem passe")
	who:SetAttribute(Vantagens.attr("reload"), all.reload)
	who:SetAttribute(Vantagens.attr("mags"), all.mags)
	near(Vantagens.mult(who, "reload"), 0.88, 1e-9)
	assert(Vantagens.extra(who, "mags") == 1)
	who:SetAttribute(Vantagens.attr("reload"), 0.2)
	near(Vantagens.mult(who, "reload"), 0.88, 1e-9, "teto de 12% mesmo com valor errado")
end)

test("rede: tremor de ±40 ms não derruba tiro da rajada (antes: chegada a menos de 85% do intervalo)", function()
	-- a regra antiga, na hora de CHEGADA (quadro de 1/60 s do servidor), para comparar
	local wpOld = Weapons.get("m60")
	local ivOld = 60 / wpOld.rpm
	local rngOld = Rng.new(5)
	local lastArr, lastOk, okOld, n = 0, -math.huge, 0, 0
	for i = 0, 199 do
		local send = i * ivOld
		local arr = math.max(lastArr, send + 0.12 + (rngOld:next() - 0.5) * 0.08)
		lastArr = arr
		local clock = math.ceil(arr * 60) / 60
		n += 1
		if clock - lastOk >= ivOld * 0.85 then
			okOld += 1
			lastOk = clock
		end
	end
	print(
		string.format(
			"       (regra antiga na M60 com ±40 ms: %d%% dos tiros da rajada recusados)",
			math.floor(100 * (n - okOld) / n + 0.5)
		)
	)
	for _, id in { "m60", "rpd", "type56" } do
		local wp = Weapons.get(id)
		for seed = 1, 20 do
			local r = run(wp, "auto", "machine_gunner", function()
				return true
			end, 2.0, { seed = seed, jitter = 0.04, lag = 0.12 })
			assert(r.accepted == r.shots, string.format("%s semente %d: %s", id, seed, refusedText(r)))
		end
	end
end)

test("trapaça: cliente que manda o dobro da cadência tem a metade recusada", function()
	local wp = Weapons.get("m60")
	local rec = newRec(wp, 1)
	rec.mag = 1000
	local accepted, sent = 0, 0
	local iv = Weapons.interval(wp, "auto")
	local t = 100
	for _ = 1, 200 do
		t += iv / 2
		sent += 1
		if Gatilho.validate(rec, { weapon = "m60", mode = "auto", t = t, now = t, clock = t, originStuds = 0.2 }) then
			accepted += 1
		end
	end
	near(accepted / sent, 0.5, 0.03, "fração aceita")
	-- semi feito por macro a cada 30 ms: no máximo um tiro a cada SEMI_MIN_S
	local sks = Weapons.get("sks")
	local r2 = newRec(sks, 1)
	r2.mag = 1000
	local ok2 = 0
	t = 0
	for _ = 1, 100 do
		t += 0.03
		if Gatilho.validate(r2, { weapon = "sks", mode = "semi", t = t, now = t, clock = t, originStuds = 0.2 }) then
			ok2 += 1
		end
	end
	assert(ok2 <= math.ceil(3 / Weapons.SEMI_MIN_S / (1 - Gatilho.TOLERANCE)) + 1, "macro: " .. ok2)
end)

test("relógio do tiro atrasado (rede lenta) não recusa: é preso na janela de 250 ms", function()
	local wp = Weapons.get("m14")
	local r = run(wp, "semi", "rifleman", function(t)
		return (t % 0.3) < 0.05
	end, 1.5, { lag = 0.45, jitter = 0.05 })
	assert(r.accepted == r.shots and r.shots == 5, string.format("%d de %d (%s)", r.accepted, r.shots, refusedText(r)))
end)

test("origem a mais de 8 studs da cabeça: recusada", function()
	local r = run(Weapons.get("m14"), "semi", "rifleman", function()
		return true
	end, 0.2, { originStuds = 9 })
	assert(r.accepted == 0 and r.refused["origem"] == 1)
end)

-- ===== veículo (D-100) =====
test("veículo: lugar fechado recusa; lugar aberto só no ângulo; folga cresce com o giro", function()
	local wp = Weapons.get("m14")
	local function shot(seat: any): (boolean, string?)
		local rec = newRec(wp, 1)
		return Gatilho.validate(rec, {
			weapon = "m14",
			mode = "semi",
			role = "rifleman",
			t = 1,
			now = 1,
			clock = 1,
			originStuds = 1,
			seat = seat,
		})
	end
	local door = Vehicles.seatInfo("uh34d", "p1").open -- porta da direita
	assert(door, "porta do UH-34D sem ângulo")
	local ok, why = shot({ personal = false, weapon = nil, arc = nil, relYawDeg = 0, pitchDeg = 0 })
	assert(not ok and why == "lugar fechado")
	ok = shot({ personal = true, weapon = "m14", arc = door, relYawDeg = door.yaw, pitchDeg = -10 })
	assert(ok, "dentro do ângulo")
	ok, why = shot({ personal = true, weapon = "m14", arc = door, relYawDeg = door.yaw + 180, pitchDeg = 0 })
	assert(not ok and why == "fora do ângulo", "para dentro da cabine")
	-- logo fora da borda: recusa parado, aceita girando a 60°/s (a folga cobre a defasagem)
	local edge = door.yaw + door.half + Gatilho.ARC_SLACK_DEG + 5
	ok = shot({ personal = true, weapon = "m14", arc = door, relYawDeg = edge, pitchDeg = 0, turnDegS = 0 })
	assert(not ok, "borda parado")
	ok = shot({ personal = true, weapon = "m14", arc = door, relYawDeg = edge, pitchDeg = 0, turnDegS = 60 })
	assert(ok, "borda girando")
	-- arma diferente da do lugar (a pistola do granadeiro no lugar da M79): recusa
	ok, why = shot({ personal = true, weapon = "m79", arc = door, relYawDeg = door.yaw, pitchDeg = 0 })
	assert(not ok and why == "lugar fechado")
	-- a conta do ângulo é a mesma do Vehicles.inArc (sem folga)
	local rng = Rng.new(99)
	for _ = 1, 500 do
		local arc =
			{ yaw = rng:range(-180, 180), half = rng:range(10, 180), down = rng:range(-70, 0), up = rng:range(0, 60) }
		local y, p = rng:range(-360, 360), rng:range(-90, 90)
		assert(Vehicles.inArc(arc, y, p) == Gatilho.inArc(arc, y, p, 0), "inArc diverge")
	end
end)

-- ===== fuzis de precisão =====
test("sniper: M70 (Unertl 8x) e Mosin 91/30 (PU 3,5x) no papel, com ferrolho e luneta", function()
	assert(Roles.loadout.US.sniper[1] == "m70" and Roles.loadout.VC.sniper[1] == "mosin")
	for _, id in { "m70", "mosin" } do
		local wp = Weapons.get(id)
		assert(wp.modes[1] == "bolt" and #wp.modes == 1, id .. ": ferrolho")
		assert(wp.scope and wp.scope.fov > 0 and wp.scope.fov < 25, id .. ": luneta")
		near(wp.scope.fov, 70 / wp.scope.mag, 1e-9, id .. ": FOV pela regra do binóculo")
		assert(Weapons.adsEye(id) == wp.scope.eyeReliefM, id .. ": olho no alívio da luneta")
		near(Weapons.interval(wp, "bolt"), wp.boltS, 1e-9, id)
		-- chega a 1.000 m dentro do voo simulado, ainda acima de 60 m/s, e a alça de 1.000 m zera lá
		local hit = Ballistics.trace({
			ox = 0,
			oy = 0,
			oz = 0,
			dx = 1,
			dy = math.tan(Ballistics.zeroAngle(id, 1000)),
			dz = 0,
			weaponId = id,
			seed = 3,
			maxTime = wp.maxFlightS,
		}, function(ax, ay, az, bx, by, bz)
			if bx >= 1000 then
				local f = (1000 - ax) / (bx - ax)
				return { x = 1000, y = ay + (by - ay) * f, z = az + (bz - az) * f }
			end
			return nil
		end)
		assert(hit, id .. ": não chegou a 1.000 m")
		assert(math.abs(hit.y) < 0.6, string.format("%s: %.2f m de altura a 1.000 m com a alça de 1.000", id, hit.y))
		print(
			string.format(
				"       (%s: %.0f m/s a 1.000 m, %.2f s de voo, %.0f J; queda com alça de 100 m a 500 m: %.2f m)",
				id,
				hit.speed,
				hit.t,
				hit.energy,
				Ballistics.dropAt(id, 500, 100)
			)
		)
	end
	-- a 7,62x54R leve sai mais rápida e cai menos a 300 m; a .30-06 de 173 gr chega com mais energia longe
	assert(Ballistics.dropAt("mosin", 300, 100) < Ballistics.dropAt("m70", 300, 100))
end)

test("M79: alcance máximo ~400 m (wiki), alça de 75 a 375 m, arma entre 14 e 27 m (FAS)", function()
	local best = 0
	for a = 30, 50 do
		best = math.max(best, Ballistics.rangeAt("m79", math.rad(a)))
	end
	near(best, 400, 10, "alcance máximo")
	local wp = Weapons.get("m79")
	assert(wp.armM[1] == 14 and wp.armM[2] == 27)
	assert(wp.zeros[1] == 75 and wp.zeros[#wp.zeros] == 375)
	-- a granada a 375 m: voa dentro do tempo simulado (12 s) e não para no meio do caminho
	local a = Ballistics.zeroAngle("m79", 375)
	local hit = Ballistics.trace({
		ox = 0,
		oy = 0,
		oz = 0,
		dx = math.cos(a),
		dy = math.sin(a),
		dz = 0,
		weaponId = "m79",
		seed = 1,
		maxTime = wp.maxFlightS,
		dt = 1 / 60,
	}, function(ax, ay, _az, bx, by, _bz)
		if by < 0 and ay >= 0 then
			return { x = ax + (bx - ax) * ay / (ay - by), y = 0, z = 0 }
		end
		return nil
	end)
	assert(hit, "a granada não caiu")
	near(hit.x, 375, 25, "a granada de 375 m")
	print(string.format("       (M79: 375 m a %.1f°, %.1f s de voo)", math.deg(a), hit.t))
end)

test("napalm (Explosive.burn): mancha ao longo do rumo, queimadura e queda com a exposição", function()
	local Explosive = require(S .. "Explosive") :: any
	local b = Explosive.TYPES.napalm.burn
	assert(b and Explosive.TYPES.napalm.lethalM == 0, "napalm sem fogo")
	-- rumo leste (+X): 30 m à frente é fogo, 30 m ao lado não
	assert(Explosive.burnAt(b, 30, 0, 1, 0) == "core")
	assert(Explosive.burnAt(b, 0, 30, 1, 0) == nil)
	assert(Explosive.burnAt(b, 0, b.widthM / 2 + 3, 1, 0) == "edge")
	-- no meio da mancha: queima no 1º passo e cai com lethalS acumulados; na borda só queima
	local done, exposed, events = nil, 0, {}
	for _ = 1, 20 do
		exposed += 0.25
		local what = Explosive.burnStep(b, "core", exposed, done)
		if what then
			table.insert(events, string.format("%s@%.2f", what, exposed))
			done = what
		end
	end
	assert(
		#events == 2 and events[1] == "burn@0.25" and events[2] == string.format("lethal@%.2f", b.lethalS),
		table.concat(events, " ")
	)
	assert(Explosive.burnStep(b, "edge", 99, "burn") == nil, "a borda não mata")
end)

test("recuo por tiro (graus de subida da boca, a fórmula do WeaponController)", function()
	local out = {}
	for _, wp in Weapons.list do
		if wp.enabled then
			-- D-108: a espingarda empurra a carga inteira (9 bagos: chargeG), como no WeaponController
			local kick = ((wp.chargeG or wp.bulletMassG) / 1000) * wp.muzzleVelocity * 1.5 / wp.massLoadedKg * 0.9
			assert(kick > 0.5 and kick < 10, wp.id .. string.format(": %.2f°", kick))
			table.insert(out, string.format("%s %.1f°", wp.id, kick))
		end
	end
	print("       (" .. table.concat(out, ", ") .. ")")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
