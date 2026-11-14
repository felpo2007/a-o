--!strict
-- Corpo a corpo e braços (D-94). Uso: lune run tests/luau/faca.luau
-- 1. Regras do Shared/Melee (alcance, cone, dano, anti-trapaça, bot).
-- 2. Facas: pontos do Shared/Weapons iguais aos medidos no GLB (assets/facas/pontos.json), chaves
--    novas em AssetIds e no plano de upload.
-- 3. Braços: simulação do R15 (Shared/ArmIK, IK de dois ossos com polo) com cada arma publicada,
--    pega, torção de pelve e flexão do peito: penetração dos braços e da arma no corpo. Imprime a
--    tabela (antes e depois) que está na D-94.
-- 4. Clipes gravados (assets/mocap/soldado, se existirem): penetração dos braços no corpo quadro a
--    quadro e a câmera agachada na altura da cabeça (DROP.crouch).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local S = "../../src/ReplicatedStorage/Shared/"
local ArmIK = require(S .. "ArmIK")
local Melee = require(S .. "Melee")
local Weapons = require(S .. "Weapons")
local SoldierAnims = require(S .. "SoldierAnims")
local M = 0.28

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

-- Medical (limiares): lidos do arquivo para o teste não depender do módulo do servidor
local medical = fs.readFile("src/ReplicatedStorage/Shared/Medical.luau")
local TORSO_DOWN = tonumber(string.match(medical, "torsoDownJ = (%d+)")) :: number
local HEAD_KILL = tonumber(string.match(medical, "headKillJ = (%d+)")) :: number

test("estocada certeira no tronco derruba; golpe de lado fere; cabeça derruba sem matar", function()
	assert(TORSO_DOWN and HEAD_KILL, "limiares do Medical")
	local function out(id: string, zone: string, precise: boolean, knife: string?, downed: boolean?): string
		return Melee.outcome(Melee.energy(id, zone, precise, knife), zone, downed == true, TORSO_DOWN, HEAD_KILL)
	end
	assert(out("estocada", "torso", true, "kabar") == "derruba", "estocada certeira")
	assert(out("estocada", "torso", false, "kabar") == "fere", "estocada de raspão vale golpe de lado")
	assert(out("lado", "torso", true, "kabar") == "fere", "golpe de lado não derruba sozinho")
	assert(out("lado", "torso", true, "dao") == "fere", "facão também não")
	assert(out("baioneta", "torso", true) == "derruba", "baioneta certeira")
	assert(out("baioneta", "torso", false) == "fere", "baioneta de raspão = coronhada")
	for _, id in { "estocada", "lado", "baioneta", "coronhada" } do
		assert(out(id, "head", true, "kabar") == "derruba", id .. ": cabeça derruba sem matar")
		assert(out(id, "torso", true, "kabar", true) == "mata" or id == "coronhada", id .. ": caído morre")
	end
	assert(out("coronhada", "torso", true, nil, true) == "nada", "coronhada não mata caído")
	-- facão corta mais do que fura
	assert(Melee.energy("lado", "torso", true, "dao") > Melee.energy("lado", "torso", true, "kabar"))
	assert(Melee.energy("estocada", "torso", true, "dao") < Melee.energy("estocada", "torso", true, "kabar"))
	-- membro: estocada com chance de corte arterial (≥ torsoDownJ, Medical)
	assert(Melee.energy("estocada", "leg", true, "kabar") >= TORSO_DOWN * 0.99)
end)

test("alcance de 1,4 a 2,1 m e cone: fora do alcance ou do cone não acerta", function()
	for id, a in Melee.ATTACKS do
		assert(a.reachM >= 1.4 and a.reachM <= 2.1, id .. ": alcance " .. a.reachM)
		assert(a.preciseDeg <= a.coneDeg, id)
		assert(a.windup < a.impact and a.impact < a.recover, id .. ": antecipação < impacto < fim")
	end
	local A = Melee.ATTACKS.estocada
	local c, precise = Melee.pick("estocada", { { distM = 1.7, angDeg = 5, zone = "torso", key = 1 } })
	assert(c and precise, "1,7 m e 5°: acerta certeiro")
	c, precise = Melee.pick("estocada", { { distM = 1.7, angDeg = 18, zone = "torso", key = 1 } })
	assert(c and not precise, "18°: acerta de raspão")
	c = Melee.pick("estocada", { { distM = A.reachM + 0.05, angDeg = 2, zone = "torso", key = 1 } })
	assert(c == nil, "além do alcance")
	c = Melee.pick("estocada", { { distM = A.reachM + 0.05, angDeg = 2, zone = "torso", key = 1 } }, Melee.LAG_M)
	assert(c, "com a folga de latência do servidor")
	c = Melee.pick("estocada", { { distM = 1.0, angDeg = A.coneDeg + 1, zone = "torso", key = 1 } })
	assert(c == nil, "fora do cone")
	-- o mais alinhado ganha
	c = Melee.pick("lado", {
		{ distM = 1.0, angDeg = 40, zone = "arm", key = "a" },
		{ distM = 1.3, angDeg = 8, zone = "torso", key = "b" },
	})
	assert(c and c.key == "b", "o mais alinhado")
end)

test("anti-trapaça: direção finita, à frente do corpo, sem olhar para o céu; intervalo do golpe", function()
	assert(Melee.dirOk(0, 0, -1, 0, -1), "frente")
	assert(Melee.dirOk(-0.5, -0.3, -1, 0, -1), "à frente e para baixo")
	assert(not Melee.dirOk(0, 0, 1, 0, -1), "para trás")
	assert(not Melee.dirOk(1, 0, 0.1, 0, -1), "de lado (>75°)")
	assert(not Melee.dirOk(0, 1, -0.1, 0, -1), "para o céu")
	assert(not Melee.dirOk(0 / 0, 0, -1, 0, -1), "NaN")
	assert(not Melee.dirOk(0, 0, 0, 0, -1), "nula")
	-- combinação: 2º toque logo depois vira golpe de lado; com baioneta, sempre baioneta
	assert(Melee.choose(false, false, nil, 99) == "estocada")
	assert(Melee.choose(false, false, "estocada", 0.6) == "lado")
	assert(Melee.choose(false, false, "estocada", Melee.COMBO_S + 0.1) == "estocada")
	assert(Melee.choose(true, false, "estocada", 0.2) == "baioneta")
	assert(Melee.choose(false, true, nil, 99) == "coronhada")
	-- saque soma no 1º golpe; o intervalo cobre o golpe inteiro (menos a folga)
	near(Melee.impactDelay("estocada", false), Melee.DRAW_S + 0.2, 1e-9)
	near(Melee.impactDelay("estocada", true), 0.2, 1e-9)
	assert(Melee.cooldown("estocada", true) > Melee.ATTACKS.estocada.impact, "não golpeia de novo antes do impacto")
	assert(Melee.cooldown("baioneta", true) > Melee.cooldown("estocada", true), "baioneta é mais lenta")
	-- o 2º toque cabe na janela da combinação depois do intervalo
	assert(Melee.cooldown("estocada", true) < Melee.COMBO_S, "janela do golpe de lado")
end)

test("bot golpeia perto e à frente, com intervalo; o VC corta com o facão", function()
	assert(Melee.botAttack(1.2, 10, 0.1, 5, "US") == "estocada")
	assert(Melee.botAttack(1.2, 10, 0.1, 5, "VC") == "lado")
	assert(Melee.botAttack(Melee.BOT_REACH_M + 0.1, 10, 0.1, 5, "US") == nil, "longe")
	assert(Melee.botAttack(1.0, Melee.BOT_CONE_DEG + 5, 0.1, 5, "US") == nil, "de lado")
	assert(Melee.botAttack(1.0, 10, 0.1, 0.2, "US") == nil, "intervalo")
	assert(Melee.botAttack(1.0, 10, 0.99, 5, "US") == nil, "chance")
end)

test("facas: pontos do Weapons iguais ao GLB medido; chaves em AssetIds e no plano de upload", function()
	local AssetIds = require(S .. "AssetIds") :: any
	local plan = serde.decode("json", fs.readFile("assets/upload_plan.json")) :: any
	local inPlan: { [string]: string } = {}
	for _, it in plan do
		inPlan[it.key] = it.file
	end
	local pts = if fs.isFile("assets/facas/pontos.json")
		then serde.decode("json", fs.readFile("assets/facas/pontos.json")) :: any
		else nil
	for id, k in Weapons.knives do
		for _, wp in Weapons.list do
			assert(wp.name ~= k.name, id .. ": faca fora da lista das armas de fogo")
		end
		assert(AssetIds.Models[k.art] ~= nil, id .. ": AssetIds.Models." .. k.art)
		assert(inPlan["Models." .. k.art], id .. ": no upload_plan")
		-- o GLB é gerado (tools/faca) e fica fora do Git: só confere o caminho quando a pasta existe
		if fs.isDir("assets/facas") then
			assert(fs.isFile(inPlan["Models." .. k.art]), id .. ": GLB " .. inPlan["Models." .. k.art])
		end
		assert(k.tip[3] < k.guard[3] and k.guard[3] < k.grip[3], id .. ": ponta à frente (−Z), punho atrás")
		near((k.grip[3] - k.tip[3]) * M, k.bladeM + (k.grip[3] - k.guard[3]) * M, 0.02, id .. ": lâmina")
		if pts then
			local p = pts[id]
			assert(p, id .. ": sem pontos.json")
			local f = p.Faca
			for i = 1, 3 do
				near(k.size[i], f.tamanho[i], 1e-3, id .. " tamanho")
				near(k.grip[i], f.punho[i], 1e-3, id .. " punho")
				near(k.tip[i], f.ponta[i], 1e-3, id .. " ponta")
			end
			near(k.lengthM, f.comprimento_m, 1e-3, id .. " comprimento")
			if k.sheath then
				for i = 1, 3 do
					near(k.sheath.mouth[i], p.Bainha.boca[i], 1e-3, id .. " boca")
				end
			end
			local tri = 0
			for _, n in p.triangulos do
				tri += n
			end
			assert(tri <= 20000, id .. ": " .. tri .. " triângulos (herói ≤ 20 mil)")
		end
	end
	for _, s in { "faca_saque", "faca_corte", "faca_impacto", "baioneta_encaixe" } do
		assert(AssetIds.Sounds[s] ~= nil and inPlan["Sounds." .. s], s)
	end
	assert(Melee.KNIFE.US == "kabar" and Melee.KNIFE.VC == "dao")
	for wid, bid in Melee.BAYONET do
		assert(Weapons.byId[wid] and Weapons.knives[bid], wid .. " -> " .. bid)
	end
end)

test("faca no cinto de todo soldado (Gear), num lugar livre do cinto", function()
	local Gear = require("../../src/ServerScriptService/Modules/Gear") :: any
	local k = Gear.BODY_K -- D-98: corpo de 2 m
	local env = Gear.env(
		Gear.vec(1.67 * k, 0.79 * k, 1.04 * k),
		Gear.vec(1.84 * k, 2.0 * k, 1.07 * k),
		Gear.vec(1 * k, 1.2 * k, 1.1 * k),
		nil,
		nil
	)
	for faction, byRole in Gear.KIT_BY_ROLE do
		for role in byRole do
			for _, extra in { "", "us_towel", "vc_rice_tube" } do
				local pieces = Gear.layout(faction, Gear.items(faction, role, { extra = extra }), env)
				local n = 0
				for _, p in pieces do
					if p.name == "knife_sheath" or p.name == "knife_handle" then
						n += 1
						assert(p.group == "belt", "faca no grupo do cinto")
					end
				end
				assert(n == 2, string.format("%s/%s/%s: sem lugar para a faca", faction, role, extra))
				assert(#pieces <= Gear.MAX_PIECES, faction .. "/" .. role .. ": peças demais")
			end
		end
	end
end)

-- ===== braços (simulação) =====
local WeaponArt = luau.load(
	fs.readFile("src/ReplicatedStorage/Shared/WeaponArt.luau"),
	{ debugName = "WeaponArt", environment = { Vector3 = roblox.Vector3 } }
)() :: any

type Geo = { support: { number }, buttZ: number, muzzleZ: number }
-- apoio e coronha no referencial da arma (pivô no punho, boca em −Z), como o GunModel.fit
local function geo(id: string): Geo
	local a = WeaponArt[id]
	local f = ({ ["+Z"] = { 0, 0, 1 }, ["-Z"] = { 0, 0, -1 }, ["+X"] = { 1, 0, 0 }, ["-X"] = { -1, 0, 0 } })[a.forward]
	local function s(v: any): number
		return v.X * f[1] + v.Y * f[2] + v.Z * f[3]
	end
	local d = { a.support.X - a.grip.X, a.support.Y - a.grip.Y, a.support.Z - a.grip.Z }
	local w: { number }
	if a.forward == "+Z" then
		w = { -d[1], d[2], -d[3] }
	elseif a.forward == "-Z" then
		w = d
	elseif a.forward == "-X" then
		w = { -d[3], d[2], d[1] }
	else
		w = { d[3], d[2], -d[1] }
	end
	local L = a.lengthM / M
	local mz = s(a.muzzle) - s(a.grip)
	-- D-98: o corpo cresce K e a arma não; no espaço do ArmIK (corpo da gravação) a arma encolhe 1/K
	local k = 1 / SoldierAnims.SCALE
	return { support = { w[1] * k, w[2] * k, w[3] * k }, buttZ = (L - mz) * k, muzzleZ = -mz * k }
end

-- arma como um segmento da coronha à boca (coronha 4,8 cm de raio, cano 2,8 cm)
local function weaponDepth(h: { number }, g: Geo, twist: number, bend: number): number
	local p, r = ArmIK.hold(h)
	local body = ArmIK.body(twist, bend)
	local worst = 0
	for i = 0, 40 do
		local z = g.buttZ + (g.muzzleZ - g.buttZ) * i / 40
		local rad = if z > 0 then 0.17 else 0.1
		local q = ArmIK.add(p, ArmIK.mv(r, { 0, if z > 0 then -0.08 else 0, z }))
		for _, b in body do
			worst = math.max(worst, rad - ArmIK.sdBox(q, b, ArmIK.TORSO_ROUND))
		end
	end
	return math.max(worst, 0)
end

local KIND =
	{ m14 = "rifle", type56 = "rifle", sks = "rifle", m60 = "mg", rpd = "mg", m1911 = "pistol", type54 = "pistol" }
local OLD =
	{ hold = { 0.2, 0.2, -0.7, 15, -20 }, poles = { R = { 2.2, -2.0, 1.2 }, L = { -1.2, -2.6, -0.4 } }, blade = 0 }
local TWISTS = { 0, 45, -45, 75, -75 } -- pernas na direção do movimento (SoldierAnims.LEG_YAW_MAX)
local BENDS = { -0.5, 0, 0.5 } -- peito sobre a pelve (rad): corrida, agachado, olhar

type Worst = { arm: number, gap: number, weapon: number, where: string }
local function worstOf(h: { number }, g: Geo, poles: any, blade: number, withSupport: boolean): Worst
	local grip, sup = ArmIK.targets(h, g.support)
	local w: Worst = { arm = 0, gap = 0, weapon = 0, where = "" }
	for _, tw in TWISTS do
		for _, bend in BENDS do
			local twist = math.rad(blade + tw)
			local d, gp, where = ArmIK.measure({
				grip = grip,
				support = if withSupport then sup else nil,
				poles = poles,
				twist = twist,
				bend = bend,
			})
			if d > w.arm then
				w.arm, w.where = d, string.format("%s, torção %d°, flexão %d°", where, blade + tw, math.deg(bend))
			end
			w.gap = math.max(w.gap, gp)
			w.weapon = math.max(w.weapon, weaponDepth(h, g, twist, bend))
		end
	end
	return w
end

test("braços e arma fora do corpo com cada arma, torção e flexão (simulação; tabela da D-94)", function()
	print("       arma    | antes: braço / arma        | agora: braço / arma / sobra de alcance")
	for _, id in { "m14", "type56", "sks", "m60", "rpd", "m1911", "type54" } do
		local g = geo(id)
		local before = worstOf(OLD.hold, g, OLD.poles, OLD.blade, true)
		local after = worstOf(ArmIK.HOLDS[KIND[id]], g, ArmIK.POLES.stand, ArmIK.BLADE_DEG, true)
		print(
			string.format(
				"       %-7s | %5.1f / %5.1f cm          | %4.1f / %4.1f / %4.1f cm  %s",
				id,
				before.arm * M * 100,
				before.weapon * M * 100,
				after.arm * M * 100,
				after.weapon * M * 100,
				after.gap * M * 100,
				if after.arm > 0 then "(" .. after.where .. ")" else ""
			)
		)
		local limit = if KIND[id] == "pistol" then 0.015 else 0.005 -- m
		assert(after.arm * M <= limit, id .. string.format(": braço %.1f cm dentro do corpo", after.arm * M * 100))
		assert(after.weapon * M <= 0.005, id .. ": arma dentro do corpo")
		assert(after.gap * M <= 0.01, id .. ": mão não alcança")
		assert(before.arm > after.arm, id .. ": a correção melhora")
	end
end)

test("golpe com o fuzil e faca na mão: guarda, estocada e fuzil só na esquerda", function()
	for _, id in { "m14", "type56", "sks" } do
		local g = geo(id)
		-- golpe curto (0,5 s): guarda limpa; na estocada até 2 cm e as mãos até 10 cm aquém
		for _, name in { "guard", "lunge" } do
			local grip, sup = ArmIK.targets(ArmIK.HOLDS[name], g.support)
			local d, gp = ArmIK.measure({
				grip = grip,
				support = sup,
				poles = ArmIK.POLES.stand,
				twist = math.rad(ArmIK.BLADE_DEG),
			})
			local wd = weaponDepth(ArmIK.HOLDS[name], g, math.rad(ArmIK.BLADE_DEG), 0)
			print(
				string.format(
					"       %-6s %-5s braço %.1f cm, arma %.1f cm, sobra %.1f cm",
					id,
					name,
					d * M * 100,
					wd * M * 100,
					gp * M * 100
				)
			)
			-- D-98: com a arma em tamanho real no corpo de 2 m, a guarda do Tipo 56 encosta 0,6 cm
			local lim = if name == "guard" then 0.01 else 0.02
			assert(d * M <= lim and wd * M <= lim, id .. " " .. name)
			assert(gp * M <= (if name == "lunge" then 0.1 else 0.02), id .. " " .. name .. ": alcance")
		end
		-- faca na mão direita: só a esquerda no fuzil (a direita é do clipe), tronco reto
		local _, sup = ArmIK.targets(ArmIK.HOLDS.knife, g.support)
		local worst, gap = 0, 0
		for _, tw in TWISTS do
			local a = ArmIK.arm("L", sup, ArmIK.POLES.stand.L)
			local body = ArmIK.body(math.rad(tw), 0)
			for _, part in { a.upper, a.fore, a.hand } do
				worst = math.max(worst, ArmIK.depth(part, body))
			end
			worst = math.max(worst, weaponDepth(ArmIK.HOLDS.knife, g, math.rad(tw), 0))
			gap = math.max(gap, a.gap)
		end
		print(
			string.format("       %-6s faca  braço e arma %.1f cm, sobra %.1f cm", id, worst * M * 100, gap * M * 100)
		)
		assert(worst * M <= 0.005 and gap * M <= 0.02, id .. ": fuzil na esquerda")
	end
end)

test("pegas do código batem: PostureController, ArmIK, retarget e o clipe gravado", function()
	local pc = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/PostureController.client.luau")
	local h = ArmIK.HOLDS.rifle
	local B = SoldierAnims.BAKED.holdStand
	assert(h[1] == B.x and h[2] == B.y and h[3] == B.z and h[4] == B.yawDeg and h[5] == B.pitchDeg, "ArmIK x BAKED")
	assert(string.find(pc, "ArmIK.POLES", 1, true) and string.find(pc, "Pole", 1, true), "polo no IKControl")
	local rt = fs.readFile("tools/anim/retarget.py")
	local pr = {
		string.match(
			rt,
			'POLES_STAND = {"Right": np%.array%(%[([%d.%-]+), ([%d.%-]+), ([%d.%-]+)%]%), "Left": np%.array%(%[([%d.%-]+), ([%d.%-]+), ([%d.%-]+)%]%)'
		),
	}
	assert(#pr == 6, "POLES_STAND no retarget")
	local P = ArmIK.POLES.stand
	for i = 1, 3 do
		near(tonumber(pr[i]) :: number, P.R[i], 1e-9, "polo direito")
		near(tonumber(pr[i + 3]) :: number, P.L[i], 1e-9, "polo esquerdo")
	end
	local hg = tonumber(string.match(rt, "HAND_GRIP_Y = (%-?[%d.]+)"))
	near(hg :: number, Melee.HAND_GRIP_Y, 1e-9, "faca na mão: retarget x Melee")
	local rl = {
		string.match(
			rt,
			"HOLD_RELOAD = %(np%.array%(%[([%d.%-]+), ([%d.%-]+), ([%d.%-]+)%]%), np%.radians%(([%d.%-]+)%), np%.radians%(([%d.%-]+)%)%)"
		),
	}
	assert(#rl == 5, "HOLD_RELOAD no retarget")
	for i = 1, 5 do
		near(tonumber(rl[i]) :: number, ArmIK.HOLDS.reload[i], 1e-9, "pega de recarga")
	end
	local hs = {
		string.match(
			rt,
			"HOLD_STAND = %(np%.array%(%[([%d.%-]+), ([%d.%-]+), ([%d.%-]+)%]%), np%.radians%(([%d.%-]+)%), np%.radians%(([%d.%-]+)%)%)"
		),
	}
	assert(#hs == 5, "HOLD_STAND no retarget")
	for i = 1, 5 do
		near(tonumber(hs[i]) :: number, h[i], 1e-9, "pega de pé no retarget")
	end
	-- a pega de recarga: arma e braço direito fora do corpo
	local g = geo("m14")
	local grip = ArmIK.targets(ArmIK.HOLDS.reload, g.support)
	local d = ArmIK.measure({ grip = grip, poles = ArmIK.POLES.stand, twist = math.rad(ArmIK.BLADE_DEG) })
	local wd = weaponDepth(ArmIK.HOLDS.reload, g, math.rad(ArmIK.BLADE_DEG), 0)
	print(string.format("       recarga: braço direito %.1f cm, arma %.1f cm", d * M * 100, wd * M * 100))
	assert(d * M <= 0.005 and wd * M <= 0.005, "pega de recarga")
end)

-- ===== clipes gravados =====
local DIR = "assets/mocap/soldado/"
local function v3(t: any): { number }
	return { t[1], t[2], t[3] }
end
local function box(part: any, half: { number }): ArmIK.Box
	return { c = v3(part[1]), r = part[2], h = half }
end

test("clipes gravados: braços fora do corpo quadro a quadro (se existirem)", function()
	local H = ArmIK.HALF
	local found = 0
	local bad: { string } = {}
	local names: { string } = {}
	for name in SoldierAnims.CLIPS do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local path = DIR .. name .. ".json"
		if fs.isFile(path) then
			found += 1
			local d = serde.decode("json", fs.readFile(path)) :: any
			local worst, at = 0, ""
			for _, q in d.quadros do
				local pv = q.previa
				local body = {
					box(pv.UpperTorso, H.UpperTorso),
					box(pv.LowerTorso, H.LowerTorso),
					box(pv.Head, H.Head),
				}
				for _, side in { "Left", "Right" } do
					for part, half in { UpperArm = H.UpperArm, LowerArm = H.LowerArm, Hand = H.Hand } do
						local dep = ArmIK.depth(box(pv[side .. part], half), body)
						if dep > worst then
							worst, at = dep, string.format("%s%s em %.2f s", side, part, q.t)
						end
					end
				end
			end
			print(
				string.format(
					"       %-15s braço no corpo: %4.1f cm %s",
					name,
					worst * M * 100,
					if worst > 0 then "(" .. at .. ")" else ""
				)
			)
			-- Caixas do R15 maiores que a malha "Man" (cabeça em cubo, braço sem arredondar): até 1 cm
			-- é encostar. Golpes, saque e recarga: até 2,5 cm (o braço cruza à frente do peito); granada
			-- (captura da CMU): o braço passa raspando no fim; deitado: a mão do punho junto do rosto.
			local limit = if SoldierAnims.CLIPS[name].stance == "prone"
				then 0.07
				elseif name == "granada" then 0.03
				elseif SoldierAnims.CLIPS[name].layer == "upper" then 0.025
				else 0.01
			if worst * M > limit then
				table.insert(bad, name .. string.format(": %.1f cm", worst * M * 100))
			end
		end
	end
	assert(#bad == 0, table.concat(bad, "; "))
	if found == 0 then
		print("       (sem assets/mocap/soldado: rode tools/anim/retarget.py e kfs.luau)")
	end
end)

test("D-98: carta na mão (mãos nas bordas, fuzil a tiracolo) sem atravessar o corpo", function()
	local p, r = ArmIK.hold(ArmIK.HOLDS.map)
	-- bordas da folha (CartaModel: ±(W/2 − 3 cm), 4 cm abaixo do meio, 2 cm à frente), ÷ K
	local k = 1 / SoldierAnims.SCALE
	local ex, ey, ez = (0.25 - 0.03) / M * k, -0.04 / M * k, -0.02 / M * k
	local right = ArmIK.add(p, ArmIK.mv(r, { ex, ey, ez }))
	local left = ArmIK.add(p, ArmIK.mv(r, { -ex, ey, ez }))
	local worst, gap = 0, 0
	for _, tw in TWISTS do
		for _, bend in BENDS do
			local d, gp = ArmIK.measure({
				grip = right,
				support = left,
				poles = ArmIK.POLES.map,
				twist = math.rad(tw),
				bend = bend,
			})
			worst, gap = math.max(worst, d), math.max(gap, gp)
		end
	end
	local slung = 0
	for _, id in { "m14", "type56", "sks", "m60", "rpd" } do
		slung = math.max(slung, weaponDepth(ArmIK.HOLDS.slung, geo(id), 0, 0))
	end
	print(
		string.format(
			"       carta: braços %.1f cm, sobra %.1f cm; fuzil a tiracolo %.1f cm",
			worst * M * 100,
			gap * M * 100,
			slung * M * 100
		)
	)
	assert(worst * M <= 0.01 and gap * M <= 0.01, "braços na carta")
	assert(slung * M <= 0.01, "fuzil a tiracolo dentro do corpo")
end)

test("D-98: soldado de 2,0 m: o mesmo K no Corpo, no Gear e no SoldierAnims", function()
	local Corpo = require(S .. "Corpo")
	local Gear = require("../../src/ServerScriptService/Modules/Gear") :: any
	near(Corpo.HEIGHT_M, 2.0, 1e-9, "altura do dono")
	near(Corpo.K, 2.0 / 1.75, 1e-12, "K")
	near(Gear.BODY_K, Corpo.K, 1e-12, "Gear.BODY_K")
	near(SoldierAnims.SCALE, Corpo.K, 1e-12, "SoldierAnims.SCALE")
	local VehicleDrive = require(S .. "VehicleDrive") :: any
	near(VehicleDrive.BODY_K, Corpo.K, 1e-12, "VehicleDrive.BODY_K")
end)

test("câmera agachada na cabeça da animação: DROP.crouch = descida da cabeça nos clipes", function()
	local ps = fs.readFile("src/ServerScriptService/Modules/PostureService.luau")
	-- D-98: no código, o DROP do corpo de 2 m; aqui volta ao da gravação (÷ K)
	local drop = (tonumber(string.match(ps, "local DROP = { crouch = ([%d.]+)")) :: number) / SoldierAnims.SCALE
	near(drop, SoldierAnims.BAKED.drop.crouch, 1e-3, "BAKED")
	if not fs.isFile(DIR .. "parado.json") then
		return
	end
	local stand = (serde.decode("json", fs.readFile(DIR .. "parado.json")) :: any).centro_cabeca_m
	for _, n in { "agachado", "agachado_andar" } do
		local c = (serde.decode("json", fs.readFile(DIR .. n .. ".json")) :: any).centro_cabeca_m
		local fall = (stand - c) / M
		print(
			string.format(
				"       %-15s cabeça desce %.2f stud (%.0f cm); DROP.crouch %.2f",
				n,
				fall,
				fall * M * 100,
				drop
			)
		)
		assert(math.abs(fall - drop) * M <= 0.02, n .. ": câmera a mais de 2 cm da cabeça")
	end
end)

-- ===== D-99: mãos de 1ª pessoa e animação dos itens =====
local MaosPose = require(S .. "MaosPose")
local ItemAnim = require(S .. "ItemAnim")

test("D-99: mãos de 1ª pessoa com medidas de mão (não mais elipsoides)", function()
	for name in MaosPose.POSES do
		for _, side in { "R", "L" } do
			local p = MaosPose.get(name, side)
			assert(p.hand == side, name .. ": lado")
			assert(#p.chains >= 5, name .. ": dedos e polegar")
			local lo, hi = MaosPose.bounds(p)
			for i = 1, 3 do
				local span = hi[i] - lo[i]
				assert(span > 0.04 and span < 0.2, string.format("%s %s: eixo %d com %.3f m", name, side, i, span))
			end
			for _, ch in p.chains do
				assert(ch.r >= 0.007 and ch.r <= 0.025, name .. ": raio de dedo/pulso")
			end
		end
		-- espelho: a mão do outro lado é a mesma forma com x trocado
		local r, l = MaosPose.get(name, "R"), MaosPose.get(name, "L")
		near(r.chains[2].pts[1][1], -l.chains[2].pts[1][1], 1e-9, name .. ": espelho")
	end
	-- a direita fecha o punho: um dedo passa da frente do punho para o lado esquerdo dele
	local g = MaosPose.get("grip", "R")
	local left = false
	for _, ch in g.chains do
		for _, v in ch.pts do
			if v[1] < -0.012 - 0.016 + 0.004 then -- além da face esquerda do punho (centro −1,2 cm)
				left = true
			end
		end
	end
	assert(left, "os dedos não envolvem o punho")
end)

test("D-99: itens com caminho completo, laço e alcance do braço", function()
	local SA = SoldierAnims
	for name, a in ItemAnim.ANIMS do
		for _, keys in { a.tp, a.fp } do
			assert(keys[1].t == 0, name .. ": começa em 0")
			assert(math.abs(keys[#keys].t - a.dur) < 1e-9, name .. ": termina no fim nominal")
			for i = 2, #keys do
				assert(keys[i].t > keys[i - 1].t, name .. ": chaves em ordem")
			end
		end
		assert(a.loop.a >= 0 and a.loop.b <= a.dur and a.loop.b > a.loop.a, name .. ": laço")
		-- laço: o tempo das chaves nunca sai de [0, dur] e o fim chega ao fim
		for _, t in { 0, 0.3, 2, 5, 9, 30 } do
			local tt = ItemAnim.localTime(a, t, if a.held then nil else math.max(a.dur, 12))
			assert(tt >= 0 and tt <= a.dur + 1e-9, name .. ": tempo fora")
		end
		if not a.held then
			near(ItemAnim.localTime(a, 12, 12), a.dur, 1e-9, name .. ": fim")
			near(ItemAnim.localTime(a, a.dur, a.dur), a.dur, 1e-9, name .. ": fim nominal")
		end
		-- alcance (com ItemAnim.reach): nenhum alvo além do braço do corpo gravado
		for _, k in a.tp do
			for side, p in { R = k.r, L = k.l } do
				local q = ItemAnim.reach(p, side)
				local s = ItemAnim.SHOULDER[side]
				local d = math.sqrt((q[1] - s[1]) ^ 2 + (q[2] - s[2]) ^ 2 + (q[3] - s[3]) ^ 2)
				assert(d <= ItemAnim.REACH + 1e-6, name .. ": alvo fora do alcance")
			end
		end
		if a.prop then
			assert(ItemAnim.PROPS[a.prop.kind], name .. ": objeto sem medida")
		end
		-- clipe de 3ª pessoa com o mesmo tempo (id 0 até subir)
		local clip = SA.CLIPS[SA.ITEM_CLIP[name]]
		assert(clip and clip.layer == "upper", name .. ": sem clipe")
		assert(math.abs(clip.length - a.dur) < 0.04, name .. ": duração do clipe")
	end
	for name in ItemAnim.ACTIONS do
		assert(ItemAnim.ANIMS[name], name)
	end
	for name in ItemAnim.ITEMS do
		assert(ItemAnim.ANIMS[name], name)
	end
end)

test("D-99: o que o soldado usa agora vem dos atributos (relógio do servidor)", function()
	local attrs: { [string]: any } = {}
	local function get(k: string): any
		return attrs[k]
	end
	assert(ItemAnim.current(get, 100, 8) == nil, "nada")
	attrs.VT65Acao, attrs.VT65AcaoT, attrs.VT65AcaoS = "bandage", 98, 6
	local n, t, D = ItemAnim.current(get, 100, 8)
	assert(n == "bandage" and t == 2 and D == 6, "curativo")
	assert(ItemAnim.current(get, 103.5, 8) == "bandage" and ItemAnim.current(get, 104.1 + 2, 8) == nil, "acaba")
	attrs.VT65Acao = nil
	attrs.VT65Item, attrs.VT65ItemT = "radio", 90
	local n2, _, D2 = ItemAnim.current(get, 300, 8)
	assert(n2 == "radio" and D2 == nil, "rádio segurado")
	attrs.VT65Item = "shovel"
	assert(ItemAnim.current(get, 97, 8) == "shovel" and ItemAnim.current(get, 99, 8) == nil, "pá dura 8 s")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
