--!strict
-- Testes da lógica da F2 e da monetização (Lune). Uso: lune run tests/luau/f2.luau
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Rng = require(S .. "Rng")
local Ballistics = require(S .. "Ballistics")
local Medical = require(S .. "Medical")
local SpawnRules = require(S .. "SpawnRules")
local Capture = require(S .. "Capture")
local Squads = require(S .. "Squads")
local Roles = require(S .. "Roles")
local Weapons = require(S .. "Weapons")
local Commerce = require(S .. "Commerce")

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

-- RNG ------------------------------------------------------------------------------------
test("rng determinístico e em [0,1)", function()
	local a, b = Rng.new(1234), Rng.new(1234)
	for _ = 1, 1000 do
		local x = a:next()
		assert(x == b:next() and x >= 0 and x < 1)
	end
	assert(Rng.new(1):next() ~= Rng.new(2):next())
end)

-- Armas e balística -------------------------------------------------------------------------
test("toda arma tem fonte registrada para a velocidade de boca", function()
	for _, w in Weapons.list do
		assert(w.src.muzzleVelocity ~= nil, w.id)
		if w.enabled then
			assert(w.muzzleVelocity > 0 and w.rpm > 0 and w.magazine > 0, w.id)
		end
	end
end)

test("queda cresce com a distância (M14 e Type 56, zeragem 100 m)", function()
	for _, id in { "m14", "type56" } do
		local d1, d2, d3 =
			Ballistics.dropAt(id, 100, 100), Ballistics.dropAt(id, 200, 100), Ballistics.dropAt(id, 300, 100)
		near(d1, 0, 0.01, id .. " 100 m")
		assert(d2 > 0.05 and d3 > d2 * 2.5, id .. " curva de queda")
	end
	-- 7.62x39 cai mais que 7.62x51 a 300 m
	assert(Ballistics.dropAt("type56", 300, 100) > Ballistics.dropAt("m14", 300, 100))
end)

test("arrasto: velocidade cai e o tiro é determinístico pela semente", function()
	local function shoot(seed: number)
		return Ballistics.trace(
			{ ox = 0, oy = 1.5, oz = 0, dx = 1, dy = 0, dz = 0, weaponId = "m14", seed = seed },
			function(_ax, ay, az, bx, _by, _bz)
				if bx >= 300 then
					return { x = 300, y = ay, z = az }
				end
				return nil
			end
		)
	end
	local h1 = shoot(7) :: any
	local h2 = shoot(7) :: any
	local h3 = shoot(8) :: any
	assert(h1 and h2 and h3)
	assert(h1.y == h2.y and h1.z == h2.z, "mesma semente, mesmo impacto")
	assert(h1.z ~= h3.z, "semente diferente, dispersão diferente")
	assert(h1.speed < 853 and h1.speed > 500, "velocidade a 300 m")
	assert(math.abs(h1.z) < 0.5, "dispersão de 3 MOA a 300 m < 0,5 m")
	near(h1.energy, Ballistics.energy(9.5, h1.speed), 0.01)
end)

-- Ferimentos -------------------------------------------------------------------------------
test("tronco: fuzil incapacita, pistola fere; cabeça de fuzil mata", function()
	local a = Medical.new()
	assert(Medical.applyHit(a, "torso", 3400, 0.5, 0) == "downed")
	local b = Medical.new()
	assert(Medical.applyHit(b, "torso", 480, 0.5, 0) == "wounded" and b.health < 100)
	local c = Medical.new()
	assert(Medical.applyHit(c, "head", 2000, 0.5, 0) == "killed" and c.dead)
end)

test("sangramento, curativo e torniquete (D-99: o curativo estanca)", function()
	local s = Medical.new()
	Medical.applyHit(s, "leg", 3400, 0.1, 0) -- roll < 0,2 com fuzil: arterial
	assert(s.wounds[1].level == "arterial" and s.legImpaired)
	near(Medical.bleedRate(s), Medical.C.bleed.arterial, 1e-9)
	assert(Medical.arterial(s))
	assert(Medical.tourniquet(s) and Medical.bleedRate(s) == 0, "torniquete para a artéria")
	-- um curativo para TODO sangramento que não é arterial (antes: grave virava leve e sangrava)
	local t = Medical.new()
	Medical.applyHit(t, "arm", 2000, 0.9, 0)
	Medical.applyHit(t, "torso", 480, 0.5, 0)
	assert(#t.wounds == 2 and Medical.bleedRate(t) > 0)
	assert(Medical.bandage(t) and #t.wounds == 0 and Medical.bleedRate(t) == 0, "curativo estanca")
	assert(t.bandages == 1, "gastou um")
	assert(not Medical.bandage(t), "nada para tratar")
	-- artéria sem torniquete: compressão (vira leve, sangra devagar)
	local u = Medical.new()
	u.tourniquets = 0
	Medical.applyHit(u, "leg", 3400, 0.1, 0)
	assert(Medical.bandage(u) and u.wounds[1].level == "light")
	-- bandagem rápida: torniquete na artéria e curativo no resto, de uma vez
	local q = Medical.new()
	Medical.applyHit(q, "leg", 3400, 0.1, 0)
	Medical.applyHit(q, "torso", 480, 0.5, 0)
	local ok, b, tq = Medical.quickDress(q)
	assert(ok and b == 1 and tq == 1 and Medical.bleedRate(q) == 0, "bandagem rápida estanca tudo")
	-- sem curativo nem torniquete: nada
	local n = Medical.new()
	n.bandages, n.tourniquets = 0, 0
	Medical.applyHit(n, "arm", 2000, 0.9, 0)
	assert(not Medical.quickDress(n))
end)

test("D-99: vantagens do corpo (vida 1,12, sangramento 0,8, curativo 0,74) com e sem passe", function()
	local Vantagens = require(S .. "Vantagens")
	-- jogador de mentira: só GetAttribute e IsA (o servidor grava Vant_<chave> no Player)
	local function who(attrs: { [string]: any }): any
		return {
			GetAttribute = function(_, k: string): any
				return attrs[k]
			end,
			IsA = function(_, _c: string): boolean
				return false
			end,
		}
	end
	local sem, com = who({}), who({ Vant_health = 1.12, Vant_bleed = 0.8, Vant_bandage = 0.74, Vant_speed = 1.06 })
	for _, k in { "health", "bleed", "bandage", "speed" } do
		assert(Vantagens.mult(sem, k) == 1, "sem passe: " .. k)
	end
	near(Vantagens.mult(com, "bandage"), 0.74, 1e-9, "curativo")
	near(Vantagens.mult(who({ Vant_health = 1.5 }), "health"), 1.12, 1e-9, "teto de combate")
	-- vida máxima e sangramento (o MedicalService passa os mesmos números)
	local a = Medical.new(false, Vantagens.mult(sem, "health"), Vantagens.mult(sem, "bleed"))
	local b = Medical.new(false, Vantagens.mult(com, "health"), Vantagens.mult(com, "bleed"))
	assert(a.maxHealth == 100 and a.health == 100 and a.bleedMult == 1, "sem passe igual")
	near(b.maxHealth, 112, 1e-9, "vida máxima")
	Medical.applyHit(a, "torso", 480, 0.5, 0)
	Medical.applyHit(b, "torso", 480, 0.5, 0)
	near(Medical.bleedRate(b), Medical.bleedRate(a) * 0.8, 1e-9, "sangra 20% mais devagar")
	local function untilDown(s: any): number
		local t = 0
		while not s.downedAt and t < 3600 do
			t += 1
			Medical.tick(s, 1, t)
		end
		return t
	end
	local ta, tb = untilDown(a), untilDown(b)
	print(string.format("       pistola no tronco: sem passe %d s, com o passe %d s", ta, tb))
	assert(tb > ta * 1.3, "com o passe demora mais")
	-- tempo do curativo (MedicalService: C.bandageSelf × mult)
	near(Medical.C.bandageSelf * Vantagens.mult(com, "bandage"), Medical.C.bandageSelf * 0.74, 1e-9)
end)

test("D-99: sangrar demora minutos, não segundos", function()
	local function untilDown(zone: string, j: number, roll: number): number
		local s = Medical.new()
		Medical.applyHit(s, zone, j, roll, 0)
		local t = 0
		while not s.downedAt and t < 3600 do
			t += 1
			Medical.tick(s, 1, t)
		end
		return t
	end
	local pistolTorso = untilDown("torso", 480, 0.5)
	local arteryLeg = untilDown("leg", 3400, 0.1)
	local graveArm = untilDown("arm", 2000, 0.9)
	print(
		string.format(
			"       até cair: pistola no tronco %.0f s, artéria da perna %.0f s, braço %.0f s",
			pistolTorso,
			arteryLeg,
			graveArm
		)
	)
	assert(pistolTorso > 120 and pistolTorso < 300, "tronco de pistola: ~3 min")
	assert(arteryLeg > 60 and arteryLeg < 150, "artéria: ~1,5 min")
	assert(graveArm > pistolTorso, "braço mais lento que o tronco")
end)

test("janela de 60 s, desistir na hora (D-107), reanimar com 30 de vida", function()
	local s = Medical.new()
	assert(not Medical.canGiveUp(s, 100), "de pé não desiste")
	Medical.applyHit(s, "torso", 3400, 0.5, 100)
	assert(Medical.canGiveUp(s, 100) and Medical.canGiveUp(s, 110))
	assert(Medical.revive(s, 120) and s.health == 30 and s.blurUntil == 140)
	local d = Medical.new()
	Medical.applyHit(d, "torso", 3400, 0.5, 0)
	assert(Medical.tick(d, 1, 61) == "died" and not Medical.revive(d, 62))
end)

test("tratamento do médico devolve até 75 e para o sangramento", function()
	local s = Medical.new()
	Medical.applyHit(s, "torso", 480, 0.5, 0)
	for i = 1, 10 do
		Medical.tick(s, 1, i)
	end
	assert(s.health < 50)
	assert(Medical.treat(s) and s.health == 75 and #s.wounds == 0)
end)

-- Spawn ------------------------------------------------------------------------------------
test("espera de 10 s exatos contados da queda, sem onda (2026-11-12)", function()
	assert(SpawnRules.C.minWait == 10 and SpawnRules.C.wave == 0)
	near(SpawnRules.readyAt(0, 0, 0), 10, 1e-9)
	near(SpawnRules.readyAt(3, 0, 0), 13, 1e-9) -- antes: 15 (próxima onda de 5 s)
	near(SpawnRules.readyAt(7.3, 0, 2.1), 17.3, 1e-9) -- o início da partida não mexe mais na espera
	near(SpawnRules.readyAt(5, 5, 0), 20, 1e-9) -- extra de 5 s (reunião capturada) por cima
	-- com onda (wave > 0) o alinhamento antigo continua disponível
	SpawnRules.C.wave = 5
	near(SpawnRules.readyAt(3, 0, 0), 15, 1e-9)
	SpawnRules.C.wave = 0
end)

test("espera por tipo de ponto: 10 s sem extra; reunião capturada 15, guarnição 18, troca de papel +4", function()
	local function waitOf(kind: string, roleChanged: boolean): number
		return SpawnRules.readyAt(100, SpawnRules.extraWait(kind, { 100 }, roleChanged), 0) - 100
	end
	for _, kind in { "hq", "rally", "squad" } do
		near(waitOf(kind, false), 10, 1e-9, kind)
	end
	near(waitOf("rally_captured", false), 15, 1e-9, "reunião capturada")
	near(waitOf("garrison", false), 18, 1e-9, "guarnição (túnel)")
	near(waitOf("hq", true), 14, 1e-9, "troca de papel")
end)

test("extras: setor capturado, sequência de mortes (máx. 12) e troca de papel", function()
	assert(SpawnRules.extraWait("rally_captured", { 0 }, false) == 5)
	assert(SpawnRules.extraWait("garrison", { 0 }, true) == 12)
	assert(SpawnRules.extraWait("hq", { 0, 60, 120, 170, 200 }, false) == 12)
	assert(SpawnRules.extraWait("hq", { 0, 300 }, false) == 0)
end)

test("bloqueio: inimigo a 75 m, setor em disputa, setor recém-capturado", function()
	assert(SpawnRules.blocked(0, 0, { 50, 0 }, false, nil, 0))
	assert(not SpawnRules.blocked(0, 0, { 80, 0 }, false, nil, 0))
	assert(SpawnRules.blocked(0, 0, {}, true, nil, 0))
	assert(SpawnRules.blocked(0, 0, {}, false, 100, 120))
	assert(not SpawnRules.blocked(0, 0, {}, false, 100, 131))
end)

-- Captura ----------------------------------------------------------------------------------
local INIT = { "VC", "VC", "Neutral", "US", "US" } :: { any }
test("setor central abre para os dois; um atacante leva 90 s", function()
	local st = Capture.new(INIT)
	assert(Capture.attackable(st, 3, "US") and Capture.attackable(st, 3, "VC"))
	assert(not Capture.attackable(st, 2, "US"), "EUA não atacam S2 sem ter S3")
	local ev = {}
	for _ = 1, 89 do
		ev = Capture.step(st, { [3] = { US = 1, VC = 0 } }, 1)
	end
	assert(st.owner[3] == "Neutral")
	ev = Capture.step(st, { [3] = { US = 1, VC = 0 } }, 1)
	assert(st.owner[3] == "US" and ev[1].kind == "captured")
	assert(Capture.attackable(st, 2, "US"))
end)

test("disputado congela; vantagem acelera até 2x", function()
	local st = Capture.new(INIT)
	Capture.step(st, { [3] = { US = 3, VC = 1 } }, 30)
	assert(st.progress[3] == 0)
	Capture.step(st, { [3] = { US = 5, VC = 0 } }, 45)
	assert(st.owner[3] == "US")
end)

test("tomar setor inimigo: neutraliza e depois captura; vitória", function()
	local st = Capture.new({ "VC", "VC", "US", "US", "US" } :: { any })
	-- 5 atacantes = 2x (1 + 0,25 * 4): 45 s para neutralizar, mais 45 s para capturar
	local ev = Capture.step(st, { [2] = { US = 5, VC = 0 } }, 45)
	assert(ev[1] and ev[1].kind == "neutralized" and st.owner[2] == "Neutral")
	Capture.step(st, { [2] = { US = 5, VC = 0 } }, 45)
	assert(st.owner[2] == "US")
	Capture.step(st, { [1] = { US = 5, VC = 0 } }, 90)
	assert(Capture.winner(st, 100, 4500) == "US")
	local d = Capture.new(INIT)
	assert(Capture.winner(d, 4500, 4500) == "draw")
end)

-- Squads e papéis -----------------------------------------------------------------------------
test("squads: nomes, limite de 6, papéis únicos e blindado só com 16", function()
	local st = Squads.new("US")
	local a = Squads.create(st, "infantry", 1, 10) :: any
	assert(a and a.name == "Alfa" and a.leader == 1)
	for uid = 2, 6 do
		assert(Squads.join(st, a.id, uid))
	end
	local ok, err = Squads.join(st, a.id, 7)
	assert(not ok and err == "squad cheio")
	assert(Squads.chooseRole(st, 1, "squad_leader"))
	assert(not Squads.chooseRole(st, 2, "squad_leader"))
	assert(Squads.chooseRole(st, 2, "medic"))
	assert(not Squads.chooseRole(st, 3, "medic"), "1 médico por squad")
	assert(not Squads.chooseRole(st, 3, "pilot"), "piloto não é de infantaria")
	local arm, e2 = Squads.create(st, "armor", 8, 15)
	assert(arm == nil and e2 ~= nil)
	assert(Squads.create(st, "armor", 8, 16))
	Squads.leave(st, 1)
	assert(a.leader == 2, "liderança passa adiante")
	assert(Roles.loadout.VC.machine_gunner[1] == "rpd")
end)

-- Monetização ------------------------------------------------------------------------------------
test("cosméticos: padrão liberado, passe libera, equipar valida facção/slot", function()
	local none = { passes = {}, premium = false, subscription = false }
	local withPass = { passes = { PASS_USMC_1965 = true }, premium = false, subscription = false }
	assert(Commerce.canEquip("us_cover_leaf", "US", "helmet", none))
	assert(not Commerce.canEquip("us_cover_cloud", "US", "helmet", none))
	assert(Commerce.canEquip("us_cover_cloud", "US", "helmet", withPass))
	assert(not Commerce.canEquip("us_cover_cloud", "VC", "helmet", withPass))
	assert(not Commerce.canEquip("us_cover_cloud", "US", "extra", withPass))
	assert(Commerce.canEquip("vc_scarf", "VC", "extra", { passes = {}, premium = true, subscription = false }))
	local d = Commerce.defaultLoadout("VC")
	assert(d.uniform == "vc_khaki" and d.helmet == "vc_bare" and d.extra == "vc_none")
	assert(Commerce.productKeyById(0) == nil, "ID 0 não é produto válido")
end)

test("catálogo: cosméticos só em slots visuais; itens de jogo só os da lista do dono (D-72)", function()
	for _, c in Commerce.Cosmetics do
		assert(c.slot == "helmet" or c.slot == "uniform" or c.slot == "extra", c.id)
	end
	-- exceção decidida pelo dono em 2026-11-11: kits de equipamento e o renascer onde caiu. Qualquer
	-- outro produto ou passe de jogo (arma, munição, tempo de spawn, atributo) continua proibido.
	for _, p in Commerce.Products do
		assert(p.grants == "tip" or Commerce.GAMEPLAY[p.key] == p.grants, p.key)
	end
	for _, p in Commerce.Passes do
		assert(p.kind == nil or Commerce.GAMEPLAY[p.key] == p.kind, p.key)
	end
	local n = 0
	for _ in Commerce.GAMEPLAY do
		n += 1
	end
	assert(n == 3, "a lista do dono tem 3 itens (2 kits e o renascer)")
end)

-- Recompensa diária (caderneta de serviço) e perfil v2 ------------------------------------------
local ProfileSchema = require("../../src/ServerScriptService/Modules/ProfileSchema") :: any
local DAY = Commerce.DAY_SECONDS

-- aplica um resgate como o PlayerData (estado + itens ganhos)
local function claimOn(st: any, earned: { [string]: boolean }, day: number): any
	local r = Commerce.dailyClaim(st, day, earned)
	if r.ok then
		for _, id in r.items do
			earned[id] = true
		end
	end
	return r
end

test("diária: dia UTC vira à meia-noite e a contagem regressiva fecha com ela", function()
	assert(Commerce.dayIndex(0) == 0 and Commerce.dayIndex(DAY - 1) == 0, "antes da meia-noite")
	assert(Commerce.dayIndex(DAY) == 1, "meia-noite UTC já é o dia seguinte")
	local t = 20000 * DAY + 3600 * 23 + 59 * 60 + 30 -- 23:59:30 UTC
	assert(Commerce.secondsToNextDay(t) == 30)
	assert(Commerce.secondsToNextDay(20000 * DAY) == DAY, "na virada, falta o dia inteiro")
	assert(Commerce.dayIndex(t + 30) == Commerce.dayIndex(t) + 1)
end)

test("diária: sequência de 7 dias, um resgate por dia, volta ao dia 1 depois do 7", function()
	local st = Commerce.dailyDefault()
	local earned = {}
	local d0 = 20400
	for i = 1, 7 do
		local v = Commerce.dailyView(st, d0 + i)
		assert(v.canClaim and v.day == i, "dia " .. i .. " disponível")
		local r = claimOn(st, earned, d0 + i)
		assert(r.ok and r.day == i and r.run == i, "resgate do dia " .. i)
		st = r.state
		local again = Commerce.dailyClaim(st, d0 + i, earned)
		assert(not again.ok and again.reason == "already", "segundo resgate no mesmo dia é recusado")
		assert(again.state.total == st.total and again.state.lastDay == st.lastDay, "recusa não muda nada")
		local view = Commerce.dailyView(st, d0 + i)
		assert(view.claimedToday and not view.canClaim and view.day == i)
	end
	assert(st.total == 7 and st.run == 7)
	local r8 = claimOn(st, earned, d0 + 8)
	assert(r8.ok and r8.day == 1 and r8.run == 8, "depois do dia 7 a trilha recomeça e a sequência continua")
	assert(r8.state.total == 8)
end)

test("diária: dia perdido zera a sequência, mas o total e os itens ficam", function()
	local earned = {}
	local st = Commerce.dailyDefault()
	for i = 1, 3 do
		st = claimOn(st, earned, 100 + i).state
	end
	assert(earned.us_zippo and earned.vc_tire_sandals, "dia 3 dá o item dos dois lados")
	-- pula o dia 104 inteiro: no 105 a sequência quebrou
	local v = Commerce.dailyView(st, 105)
	assert(v.canClaim and v.broken and v.day == 1 and v.run == 0, "sequência zerada")
	local r = claimOn(st, earned, 105)
	assert(r.ok and r.day == 1 and r.run == 1 and r.state.total == 4, "total não zera")
	assert(earned.us_zippo, "item ganho não some")
	-- primeira vez na vida: não é "quebra"
	local fresh = Commerce.dailyView(Commerce.dailyDefault(), 105)
	assert(fresh.canClaim and not fresh.broken and fresh.day == 1)
end)

test("diária: item novo só na primeira vez; relógio voltando não deixa resgatar", function()
	local earned = { us_zippo = true }
	local st = { run = 2, lastDay = 49, total = 9 }
	local r = Commerce.dailyClaim(st, 50, earned)
	assert(r.ok and r.day == 3 and #r.items == 2, "dia 3: Zippo e dép lốp")
	assert(#r.newItems == 1 and r.newItems[1] == "vc_tire_sandals", "Zippo já era dele")
	local back = Commerce.dailyClaim({ run = 3, lastDay = 60, total = 10 }, 59, {})
	assert(not back.ok and back.reason == "clock", "último resgate no futuro: espera")
	-- os itens da trilha existem no catálogo, são "extra" e não saem por passe
	for _, d in Commerce.DailyTrack do
		for _, id in d.items or {} do
			local c = Commerce.find(id)
			assert(c and c.unlock == "daily" and c.slot == "extra", id)
		end
	end
	local none = { passes = {}, premium = false, subscription = false }
	assert(not Commerce.canEquip("us_zippo", "US", "extra", none), "sem ganhar, não equipa")
	local won = { passes = {}, premium = false, subscription = false, earned = { us_zippo = true } }
	assert(Commerce.canEquip("us_zippo", "US", "extra", won), "ganhou, equipa")
	assert(not Commerce.canEquip("us_zippo", "VC", "extra", won), "item de outro lado")
end)

test("perfil v1 → atual: ganha a caderneta zerada; valores corrompidos voltam ao seguro", function()
	assert(ProfileSchema.VERSION == 4) -- v4 (2026-11-12): campanha; v3 (D-72): progressão (progressao.luau)
	local v1 = { schema = 1, tips = 2, purchases = { x = 5 }, tutorial = { rifleman = true } }
	local p = ProfileSchema.migrate(v1)
	assert(p.schema == 4 and p.tips == 2 and p.purchases.x == 5 and p.tutorial.rifleman)
	assert(p.daily.run == 0 and p.daily.lastDay == -1 and p.daily.total == 0 and next(p.earned) == nil)
	local bad = ProfileSchema.migrate({
		schema = 2,
		daily = { run = -4, lastDay = 0 / 0, total = "muito" },
		earned = { us_zippo = true, vc_mess_tin = "sim", [7] = true },
	})
	assert(bad.daily.run == 0 and bad.daily.lastDay == -1 and bad.daily.total == 0, "daily corrompido")
	assert(bad.earned.us_zippo == true and bad.earned.vc_mess_tin == nil, "earned só aceita true")
	local good = { schema = 2, daily = { run = 5, lastDay = 20401, total = 12 }, earned = { vc_mess_tin = true } }
	local twice = ProfileSchema.migrate(ProfileSchema.migrate(good))
	assert(twice.daily.run == 5 and twice.daily.lastDay == 20401 and twice.daily.total == 12, "migrar 2x")
	assert(twice.earned.vc_mess_tin)
	local odd = ProfileSchema.migrate({ daily = { run = 9, lastDay = 20401, total = 3 } })
	assert(odd.daily.total == 9, "total nunca menor que a sequência")
	-- dois servidores: vale o resgate mais novo
	local a = { run = 2, lastDay = 10, total = 5 }
	local b = { run = 3, lastDay = 11, total = 6 }
	assert(ProfileSchema.newerDaily(a, b).lastDay == 11 and ProfileSchema.newerDaily(b, a).lastDay == 11)
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
