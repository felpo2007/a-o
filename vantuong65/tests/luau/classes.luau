--!strict
-- D-108 (pedido do dono, 2026-11-13): classes mais simples, Suporte com caixa de munição, atirador de
-- elite no squad e espingarda calibre 12. Regras puras e ligações no jogo. Uso, a partir de vantuong65/:
--   lune run tests/luau/classes.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Roles = require(S .. "Roles") :: any
local Squads = require(S .. "Squads") :: any
local Tutorial = require(S .. "Tutorial") :: any
local Weapons = require(S .. "Weapons") :: any
local Ballistics = require(S .. "Ballistics") :: any
local Medical = require(S .. "Medical") :: any
local Gatilho = require(S .. "Gatilho") :: any
local Kit = require(S .. "Kit") :: any
local Logistics = require(S .. "Logistics") :: any
local Equipar = require(S .. "Equipar") :: any
local CaixaMunicao = require(S .. "CaixaMunicao") :: any
local SomArmas = require(S .. "SomArmas") :: any
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

local SQUAD_ROLES = { "squad_leader", "rifleman", "medic", "support", "machine_gunner", "anti_tank", "sniper" }

-- ===== classes =====
test("classes: 8 papéis de escolha, só comando e infantaria, vagas para 50 por lado", function()
	local pick = 0
	for id, r in Roles.roles do
		if r.unit ~= "vehicle" then
			pick += 1
			assert(r.unit == "infantry" or (id == "commander" and r.unit == "command"), id)
		end
	end
	assert(pick == 8, "papéis de escolha: " .. pick)
	for _, f in { "US", "VC" } do
		local slots, n = 0, 0
		for unit, u in Roles.units[f] do
			assert(unit == "infantry" or unit == "command", f .. ": " .. unit)
			assert(#u.names == u.count, f .. " " .. unit .. ": nomes")
			slots += u.count * u.size
			n += 1
		end
		assert(n == 2 and slots >= Roles.TEAM_MAX, string.format("%s: %d vagas", f, slots))
		for _, id in SQUAD_ROLES do
			assert(Roles.roleAllowedInUnit(f, id, "infantry"), f .. ": " .. id .. " no squad")
		end
		assert(
			not Roles.roleAllowedInUnit(f, "tank_crew", "infantry")
				and not Roles.roleAllowedInUnit(f, "pilot", "infantry")
		)
	end
	-- um de cada (só o fuzileiro sem limite) e nenhum posto além do comandante
	for _, id in SQUAD_ROLES do
		local r = Roles.roles[id]
		assert((id == "rifleman") == (r.maxPerSquad == nil), id .. ": limite")
		assert(Roles.minRank(id) == 1, id .. ": posto")
	end
	assert(Roles.minRank("commander") == 3)
end)

test("classes: squad de 6 com líder, médico, suporte, metralhador, antitanque e atirador", function()
	for _, f in { "US", "VC" } do
		local st = Squads.new(f)
		local sq = Squads.create(st, "infantry", 1, 10) :: any
		for uid = 2, 6 do
			assert(Squads.join(st, sq.id, uid))
		end
		local plan = { "squad_leader", "medic", "support", "machine_gunner", "anti_tank", "sniper" }
		for i, id in plan do
			local ok, why = Squads.chooseRole(st, i, id)
			assert(ok, f .. " " .. id .. ": " .. tostring(why))
		end
		assert(not Squads.chooseRole(st, 2, "sniper"), "2º atirador")
		assert(Squads.chooseRole(st, 2, "rifleman"), "fuzileiro sempre cabe")
	end
end)

test("armas: as do papel e as de escolha existem e atiram; espingarda e M79 no fuzileiro dos EUA", function()
	for _, f in { "US", "VC" } do
		for role, list in Roles.loadout[f] do
			for _, id in list do
				local wp = Weapons.get(id)
				assert(wp and wp.enabled and wp.faction == f, f .. " " .. role .. ": " .. id)
			end
			local pr = Roles.primaries(f, role)
			assert(#pr == 0 or pr[1] == list[1], f .. " " .. role .. ": a 1ª escolha é a padrão")
			for _, id in pr do
				local wp = Weapons.get(id)
				assert(wp and wp.enabled and wp.faction == f, f .. " " .. role .. ": " .. id)
			end
		end
	end
	assert(Roles.loadout.US.sniper[1] == "m70" and Roles.loadout.VC.sniper[1] == "mosin")
	local lo = Roles.loadoutFor("US", "rifleman", "win12")
	assert(lo[1] == "win12" and lo[2] == "m1911")
	assert(Roles.loadoutFor("US", "rifleman", "mosin")[1] == "m14", "arma de fora da lista: a padrão")
	assert(Roles.loadoutFor("US", "support", "win12")[1] == "win12")
	assert(Roles.loadoutFor("US", "anti_tank", "m14")[1] == "m1911", "antitanque: só a pistola (+ lançador)")
	assert(#Roles.primaries("US", "medic") == 1 and Roles.primaryFor("US", "medic", "win12") == "m14")
	-- ferramenta do papel do suporte (vaga 0) e as obras dele
	assert(Equipar.ROLE_TOOL.support and not Equipar.ROLE_TOOL.rifleman)
	assert(Logistics.BUILDS.ammo == nil, "a caixa construída saiu (é a do suporte)")
	assert(Logistics.roleCan(Logistics.BUILDS.mg_nest, "support", "US"))
	assert(Logistics.roleCan(Logistics.BUILDS.mortar_pit, "support", "VC"))
	assert(Logistics.roleCan(Logistics.BUILDS.mortar_pit, "commander", "US"))
end)

-- ===== migração =====
test("migração: todo papel e unidade de antes vira um de agora, sem erro", function()
	local old = {
		"automatic_rifleman",
		"grenadier",
		"engineer",
		"sapper",
		"radio_operator",
		"observer",
		"mortar",
		"door_gunner",
		"tank_crew",
		"pilot",
	}
	for _, id in old do
		local r = Roles.migrate(id)
		assert(r and Roles.roles[r] and Roles.roles[r].unit == "infantry", id .. " -> " .. tostring(r))
		for _, f in { "US", "VC" } do
			assert(Roles.loadout[f][r], f .. ": " .. id .. " -> " .. r .. " sem armas")
		end
	end
	assert(select(2, Roles.migrate("grenadier")) == "m79")
	for _, id in SQUAD_ROLES do
		assert(Roles.migrate(id) == id, id .. " fica")
	end
	assert(Roles.migrate("commander") == "commander" and Roles.migrate(nil) == nil and Roles.migrate("xyz") == nil)
	for _, u in { "recon", "armor", "helicopter", "mortar", "sapper" } do
		assert(Roles.migrateUnit(u) == "infantry", u)
	end
	assert(Roles.migrateUnit("command") == "command")
	-- tutorial concluído de antes conta no papel novo
	local t = Tutorial.sanitize({ engineer = true, observer = true, medic = true, lixo = true }, Roles.roles)
	assert(t.support and t.sniper and t.medic and t.lixo == nil and t.engineer == nil)
	-- todo papel de escolha tem passos no tutorial
	for _, id in SQUAD_ROLES do
		assert(#Tutorial.steps(id) > 0, id)
	end
	assert(Tutorial.RIFLE_ROLES.sniper and Tutorial.RIFLE_ROLES.support)
end)

-- ===== caixa de munição =====
local function place(o: any): (boolean, string?)
	local i = {
		role = "support",
		alive = true,
		seated = false,
		distM = 2,
		dyM = 0,
		slopeDeg = 5,
		water = false,
		blocked = false,
		ground = true,
		sinceLastS = math.huge,
	}
	for k, v in o do
		(i :: any)[k] = v
	end
	return CaixaMunicao.canPlace(i)
end

test("caixa: só o suporte põe, no chão perto, sem água, rampa nem obstáculo, com espera", function()
	assert(place({}))
	assert(not place({ role = "rifleman" }), "só o suporte")
	assert(not place({ alive = false }) and not place({ seated = true }))
	assert(not place({ distM = CaixaMunicao.POR_MAX_M + 1 }), "longe")
	assert(place({ distM = CaixaMunicao.POR_MAX_M }), "no limite")
	assert(not place({ dyM = 3 }), "andar de cima")
	assert(not place({ water = true }) and not place({ blocked = true }) and not place({ ground = false }))
	assert(
		not place({ slopeDeg = CaixaMunicao.INCLINACAO_MAX + 1 }) and place({ slopeDeg = CaixaMunicao.INCLINACAO_MAX })
	)
	local ok, why = place({ sinceLastS = CaixaMunicao.RECARGA_S - 10 })
	assert(not ok and why == "caixa nova em 10 s", tostring(why))
	assert(math.abs(CaixaMunicao.slope(0, 1, 0)) < 1e-9 and math.abs(CaixaMunicao.slope(1, 1, 0) - 45) < 1e-6)
	-- medidas do modelo do Blender (metricas.json): EUA 0,75 x 0,54 x 0,45 m; VC 0,71 x 0,43 x 0,46 m
	local w, h, d = CaixaMunicao.size("VC")
	assert(w == 0.71 and h == 0.43 and d == 0.46 and select(1, CaixaMunicao.size(nil)) == 0.75)
	assert(CaixaMunicao.PEGADA_STUDS.US[1] == 2.5 and CaixaMunicao.ICONE_STUDS.VC[2] > 2.5)
end)

test("caixa: alcance, intervalo por pessoa, estoque, tempo, uma por suporte e XP de quem pôs", function()
	local b = CaixaMunicao.new("cx1", "p:10", "US", 0, 0, 0, 100)
	assert(b.stock == CaixaMunicao.ESTOQUE and b.untilT == 100 + CaixaMunicao.DURACAO_S)
	assert(
		CaixaMunicao.inReach(CaixaMunicao.ALCANCE_M, 0) and not CaixaMunicao.inReach(CaixaMunicao.ALCANCE_M + 0.1, 0)
	)
	assert(not CaixaMunicao.inReach(1, CaixaMunicao.ALTURA_M + 0.1), "outro andar")
	-- quem pode
	assert(CaixaMunicao.canTake(b, "p:2", "US", true, true, true, 101))
	assert(not CaixaMunicao.canTake(b, "p:2", "VC", true, true, true, 101), "outro lado")
	assert(not CaixaMunicao.canTake(b, "p:2", "US", false, true, true, 101), "caído")
	assert(not CaixaMunicao.canTake(b, "p:2", "US", true, false, true, 101), "longe")
	assert(not CaixaMunicao.canTake(b, "p:2", "US", true, true, false, 101), "cheio de tudo não gasta")
	-- intervalo por pessoa
	assert(CaixaMunicao.take(b, "p:2", 101) == CaixaMunicao.ESTOQUE - 1)
	assert(not CaixaMunicao.canTake(b, "p:2", "US", true, true, true, 101 + CaixaMunicao.INTERVALO_S - 1))
	assert(CaixaMunicao.canTake(b, "p:2", "US", true, true, true, 101 + CaixaMunicao.INTERVALO_S))
	assert(CaixaMunicao.canTake(b, "p:3", "US", true, true, true, 102), "outra pessoa não espera")
	-- estoque e tempo
	for i = 1, CaixaMunicao.ESTOQUE - 1 do
		CaixaMunicao.take(b, "p:" .. (100 + i), 103)
	end
	assert(
		b.stock == 0 and CaixaMunicao.gone(b, 103) and not CaixaMunicao.canTake(b, "p:9", "US", true, true, true, 200)
	)
	local c = CaixaMunicao.new("cx2", "p:10", "US", 0, 0, 0, 0)
	assert(not CaixaMunicao.gone(c, CaixaMunicao.DURACAO_S - 1) and CaixaMunicao.gone(c, CaixaMunicao.DURACAO_S))
	-- uma por suporte
	local list = { CaixaMunicao.new("a", "p:1", "US", 0, 0, 0, 0), c }
	assert(CaixaMunicao.replaced(list, "p:10") == c and CaixaMunicao.replaced(list, "p:99") == nil)
	-- XP só para jogador e não para si mesmo
	assert(CaixaMunicao.rewards("p:10", "p:2") and not CaixaMunicao.rewards("p:10", "p:10"))
	assert(not CaixaMunicao.rewards("b:4", "p:2"), "bot não ganha XP")
end)

test("caixa: o que entrega (carregadores até a dotação, 1 granada até as do nascimento, foguete)", function()
	local need = { spare = 2, spareFull = 5, frags = 2, fragsMax = 2 }
	assert(CaixaMunicao.needs(need))
	assert(not CaixaMunicao.needs({ spare = 5, spareFull = 5, frags = 2, fragsMax = 2 }), "cheio")
	assert(CaixaMunicao.needs({ spare = 5, spareFull = 5, frags = 1, fragsMax = 2 }), "falta granada")
	assert(CaixaMunicao.needs({ spare = 5, spareFull = 5, frags = 2, fragsMax = 2, others = true }), "pistola")
	assert(CaixaMunicao.needs({ spare = 5, spareFull = 5, frags = 2, fragsMax = 2, rockets = 1 }), "foguete")
	assert(
		CaixaMunicao.grenadesAfter(0, 2) == 1
			and CaixaMunicao.grenadesAfter(2, 2) == 2
			and CaixaMunicao.grenadesAfter(3, 2) == 3
	)
	assert(CaixaMunicao.rocketsAfter(1) == 2 and CaixaMunicao.rocketsAfter(3) == 3)
	-- reserva cheia: carregadores de sobra; espingarda em cartuchos
	local m14, win12 = Weapons.get("m14"), Weapons.get("win12")
	assert(CaixaMunicao.spareFull(Weapons.magsFor(m14), m14.magazine, false) == 5)
	assert(CaixaMunicao.spareFull(Weapons.magsFor(win12), win12.magazine, true) == 28, "4 cargas de 7 cartuchos")
	-- bots
	assert(
		CaixaMunicao.botWants(0, 5, 20) and not CaixaMunicao.botWants(1, 0, 20) and not CaixaMunicao.botWants(0, 15, 20)
	)
	local boxes = {
		CaixaMunicao.new("a", "b:1", "US", 100, 0, 0, 0),
		CaixaMunicao.new("b", "b:2", "US", 40, 0, 0, 0),
		CaixaMunicao.new("c", "b:3", "VC", 10, 0, 0, 0),
	}
	local n = CaixaMunicao.nearest(boxes, "US", 0, 0, 80, 0.28, 1)
	assert(n and n.id == "b", "a do lado mais perto")
	assert(CaixaMunicao.nearest(boxes, "US", 0, 0, 5, 0.28, 1) == nil, "longe demais")
end)

-- ===== espingarda =====
-- Bagos de um tiro num alvo plano a d metros (tronco de 0,5 x 0,7 m, PLACEHOLDER do tamanho da caixa
-- de acerto): (bagos no tronco, fração da energia de boca de cada um)
local function shotgunHits(d: number, seed: number): { any }
	local wp = Weapons.get("win12")
	local e0 = Ballistics.energy(wp.bulletMassG, wp.muzzleVelocity)
	local out = {}
	for i = 0, Weapons.pelletsOf(wp) - 1 do
		local hit = Ballistics.trace({
			ox = 0,
			oy = 0,
			oz = 0,
			dx = 1,
			dy = 0,
			dz = 0,
			weaponId = "win12",
			seed = Weapons.pelletSeed(seed, i),
			maxTime = wp.maxFlightS,
		}, function(ax, ay, az, bx, by, bz)
			if ax < d and bx >= d then
				local k = (d - ax) / (bx - ax)
				return { x = d, y = ay + (by - ay) * k, z = az + (bz - az) * k }
			end
			return nil
		end)
		if hit and math.abs(hit.z) <= 0.25 and math.abs(hit.y) <= 0.35 then
			table.insert(out, { zone = "torso", frac = hit.energy / e0 })
		end
	end
	return out
end

test("espingarda: Winchester 12, 9 bagos de 00, 7 cartuchos, bomba e recarga um a um", function()
	local wp = Weapons.get("win12")
	assert(wp and wp.enabled and wp.faction == "US" and wp.kind == "shotgun")
	assert(Weapons.pelletsOf(wp) == 9 and Weapons.pelletsOf(Weapons.get("m14")) == 1)
	assert(wp.magazine == 7 and wp.feed == "tube" and wp.modes[1] == "pump")
	-- bomba: o intervalo é o da telha; o gatilho segura como o ferrolho
	assert(Weapons.interval(wp, "pump") == wp.boltS)
	local t = Gatilho.new("win12", "pump", 7)
	t.last = 10
	assert(Gatilho.cycling(t, 10 + wp.boltS * 0.5) and not Gatilho.cycling(t, 10 + wp.boltS + 0.01))
	-- recarga cartucho a cartucho (vazia, bombeia no fim)
	local two = Weapons.reloadTime(wp, 1, 5, 20)
	local full = Weapons.reloadTime(wp, 1, 0, 20)
	assert(math.abs(two - (wp.reloadStartS + 2 * wp.shellS)) < 1e-9, "2 cartuchos: " .. two)
	assert(math.abs(full - (wp.reloadStartS + 7 * wp.shellS + wp.reloadEndS)) < 1e-9, "7 + bomba: " .. full)
	assert(Weapons.tubeShells(wp, 5, 1) == 1 and Weapons.tubeShells(wp, 7, 10) == 0)
	assert(Weapons.reloadTime(Weapons.get("m14"), 1, 0, 3) == 2.4, "as outras não mudam")
	-- sementes dos bagos: a 1ª é a do tiro e são todas diferentes
	local seen = {}
	for i = 0, 8 do
		local s = Weapons.pelletSeed(123456, i)
		assert(not seen[s] and s >= 0 and s < 4294967296)
		seen[s] = true
	end
	assert(Weapons.pelletSeed(77, 0) == 77)
	-- peso e som
	assert(Kit.DEFAULT_MAGS.shotgun == Weapons.MAGS.shotgun and Kit.MAG_KG.shotgun > 0)
	local a = SomArmas.arma("win12", "shotgun")
	assert(a.tiro == "espingarda" and a.mecanica == "mec_bomba" and a.cartucho == "mec_cartucho")
	assert(SomArmas.LIB.espingarda and SomArmas.LIB.mec_bomba and SomArmas.LIB.mec_cartucho)
	assert(SomArmas.mecanica("m70") == "mec_ferrolho" and SomArmas.mecanica("win12") == "mec_bomba")
end)

test("espingarda: bagos somam num ferimento; mata de perto em 1–2 tiros, fraca de longe", function()
	-- soma e zona do bago que mais feriu
	local d, z = Medical.pelletDamage(15, { { zone = "arm", frac = 1 }, { zone = "torso", frac = 1 } })
	assert(math.abs(d - (15 * 0.65 + 15)) < 1e-9 and z == "torso")
	local b0 = Weapons.damageOf(Weapons.get("win12"))
	local head3 = { { zone = "head", frac = 1 }, { zone = "head", frac = 1 }, { zone = "head", frac = 1 } }
	local hd, hz = Medical.pelletDamage(b0, head3)
	assert(hz == "head" and hd >= Medical.SHOT.headLethal, "3 bagos na cabeça matam")
	local s = Medical.new()
	assert(Medical.applyShot(s, z, d, 0.9, 0) == "wounded" and #s.wounds == 1, "um ferimento só")
	-- dano médio por tiro no tronco pela distância (20 sementes)
	local base = Weapons.damageOf(Weapons.get("win12"))
	local line = {}
	local avg: { [number]: number } = {}
	for _, dist in { 5, 10, 20, 30, 50 } do
		local sum, pel = 0, 0
		for seed = 1, 20 do
			local hits = shotgunHits(dist, seed * 7919)
			sum += Medical.pelletDamage(base, hits)
			pel += #hits
		end
		avg[dist] = sum / 20
		table.insert(line, string.format("%d m: %.1f bagos, %.0f de dano", dist, pel / 20, avg[dist]))
	end
	print("       (" .. table.concat(line, "; ") .. ")")
	assert(avg[5] >= 100, "1 tiro a 5 m")
	assert(avg[10] >= 90, "1 tiro (às vezes 2) a 10 m")
	assert(avg[20] >= 50, "2 tiros a 20 m")
	assert(avg[50] < 34, "fraca a 50 m (4 tiros ou mais)")
end)

-- ===== atirador de elite =====
test("atirador de elite: 2 tiros no tronco até 200 m (D-107: M70 ~270, Mosin ~230), 1 na cabeça", function()
	for _, id in { "m70", "mosin" } do
		local wp = Weapons.get(id)
		assert(wp.scope and wp.modes[1] == "bolt" and #Weapons.zeros(wp) >= 10, id)
		local e0 = Ballistics.energy(wp.bulletMassG, wp.muzzleVelocity)
		local line = {}
		for _, dist in { 100, 200, 250, 400 } do
			local hit = Ballistics.trace({
				ox = 0,
				oy = 0,
				oz = 0,
				dx = 1,
				dy = 0,
				dz = 0,
				weaponId = id,
				seed = 3,
				maxTime = wp.maxFlightS,
			}, function(ax, ay, az, bx, by, bz)
				if ax < dist and bx >= dist then
					return { x = dist, y = ay, z = az }
				end
				return nil
			end)
			assert(hit, id .. " não chega a " .. dist)
			local dmg = Medical.shotDamage(Weapons.damageOf(wp), "torso", hit.energy / e0)
			table.insert(line, string.format("%d m %.0f", dist, dmg))
			if dist <= 200 then
				assert(dmg * 2 >= 100, string.format("%s: 2 tiros a %d m (%.1f)", id, dist, dmg))
			end
			assert(Medical.shotDamage(Weapons.damageOf(wp), "head", hit.energy / e0) >= Medical.SHOT.headLethal)
		end
		print(string.format("       (%s, tronco: %s)", id, table.concat(line, ", ")))
	end
	assert(Weapons.breathTime(true, 1) == Weapons.BREATH_S)
	assert(Tutorial.ROLE.sniper[1].action == "zeroing" and Tutorial.ROLE.sniper[2].action == "hold_breath")
end)

-- ===== ligações no jogo =====
local function read(p: string): string
	return fs.readFile(p)
end

test("ligações: servidor, cliente, carta, remotes, gatilho e a ficha para a frente de Blender", function()
	local logi = read("src/ServerScriptService/Modules/LogisticsService.luau")
	assert(string.find(logi, "CaixaMunicaoService.start()", 1, true), "a caixa sobe com a logística")
	local net = read("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(net, '"Caixa_Por"', 1, true) and string.find(net, '"Caixa_Aviso"', 1, true))
	local srv = read("src/ServerScriptService/Modules/CaixaMunicaoService.luau")
	for _, k in
		{ "caixa_municao_us", "caixa_municao_vc", "ammo_crate", "CombatService.resupply", '"resupply"', "VT65DevCaixa" }
	do
		assert(string.find(srv, k, 1, true), "serviço: " .. k)
	end
	local wc = read("src/StarterPlayer/StarterPlayerScripts/Controllers/WeaponController.client.luau")
	assert(string.find(wc, '"PondoCaixa"', 1, true) and string.find(wc, '"caixa_por"', 1, true), "gatilho põe")
	assert(string.find(wc, 't.mode == "pump"', 1, true), "bomba anima")
	local inf = read("src/StarterPlayer/StarterPlayerScripts/Controllers/InfantryController.client.luau")
	assert(string.find(inf, 'Bus.fire("caixa_municao")', 1, true), "ferramenta do suporte")
	local cli = read("src/StarterPlayer/StarterPlayerScripts/Controllers/CaixaMunicao.client.luau")
	assert(string.find(cli, 'Bus.on("caixa_municao"', 1, true) and string.find(cli, "PÔR CAIXA", 1, true))
	local carta = read("src/StarterPlayer/StarterPlayerScripts/Controllers/CartaView.luau")
	assert(string.find(carta, "CartaView.drawCaixas()", 1, true), "a carta marca a caixa")
	local combat = read("src/ServerScriptService/Modules/CombatService.luau")
	assert(string.find(combat, "firePellets", 1, true) and string.find(combat, "Weapons.tubeShells", 1, true))
	local bots = read("src/ServerScriptService/Modules/BotService.luau")
	assert(string.find(bots, "CaixaMunicaoService.botRefill", 1, true) and string.find(bots, "supportBox", 1, true))
	local deploy = read("src/StarterPlayer/StarterPlayerScripts/Controllers/DeployScreen.luau")
	assert(string.find(deploy, "swapPrimary", 1, true) and string.find(deploy, '"support"', 1, true))
	local team = read("src/ServerScriptService/Modules/TeamService.luau")
	assert(string.find(team, "Roles.loadoutFor", 1, true) and string.find(team, '"Primaria"', 1, true))
	local ficha = read("tools/blender/ESPINGARDA.txt")
	assert(string.find(ficha, "win12", 1, true) and string.find(ficha, "1.003 mm", 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
