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

test("sangramento, curativo e torniquete", function()
	local s = Medical.new()
	Medical.applyHit(s, "leg", 3400, 0.1, 0) -- roll < 0,2 com fuzil: arterial
	assert(s.wounds[1].level == "arterial" and s.legImpaired)
	near(Medical.bleedRate(s), 4.0, 1e-9)
	assert(not Medical.bandage(s), "curativo não para arterial")
	assert(Medical.tourniquet(s) and Medical.bleedRate(s) == 0)
	local t = Medical.new()
	Medical.applyHit(t, "arm", 2000, 0.9, 0)
	assert(t.wounds[1].level == "grave")
	assert(Medical.bandage(t) and t.wounds[1].level == "light")
	assert(Medical.bandage(t) and #t.wounds == 0)
	assert(not Medical.bandage(t), "sem curativos (2 por soldado)")
end)

test("janela de 60 s, desistir após 15 s, reanimar com 30 de vida", function()
	local s = Medical.new()
	Medical.applyHit(s, "torso", 3400, 0.5, 100)
	assert(not Medical.canGiveUp(s, 110) and Medical.canGiveUp(s, 116))
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
test("espera mínima de 60 s alinhada às ondas de 20 s", function()
	near(SpawnRules.readyAt(0, 0, 0), 60, 1e-9)
	near(SpawnRules.readyAt(5, 0, 0), 80, 1e-9) -- 65 -> próxima onda em 80
	near(SpawnRules.readyAt(5, 20, 0), 100, 1e-9)
end)

test("extras: setor capturado, sequência de mortes (máx. 45) e troca de papel", function()
	assert(SpawnRules.extraWait("rally_captured", { 0 }, false) == 20)
	assert(SpawnRules.extraWait("garrison", { 0 }, true) == 45)
	assert(SpawnRules.extraWait("hq", { 0, 60, 120, 170, 200 }, false) == 45)
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

test("nenhum item à venda dá vantagem: catálogo só tem slots cosméticos", function()
	for _, c in Commerce.Cosmetics do
		assert(c.slot == "helmet" or c.slot == "uniform" or c.slot == "extra", c.id)
	end
	for _, p in Commerce.Products do
		assert(p.grants == "tip", p.key)
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
