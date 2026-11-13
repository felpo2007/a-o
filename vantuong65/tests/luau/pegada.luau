--!strict
-- Arma em 3ª pessoa no boneco de bloco (Shared/Pegada3P, 2026-11-13). Uso: lune run tests/luau/pegada.luau
-- Simula o R15 de bloco na escala do soldado (Corpo.BLOCK_SCALE) com a M14 de tamanho real e mede,
-- em cada pose (guarda, no ombro, correndo, recarga, inclinado, deitado, mira de −60° a +60°):
-- a mão no alvo, o alcance dos braços, a distância entre as mãos, o cano fora do tronco e da cabeça e
-- a arma apontando para a mira.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local S = "../../src/ReplicatedStorage/Shared/"
local Pegada3P = require(S .. "Pegada3P")
local Corpo = require(S .. "Corpo")
local Movement = require(S .. "Movement")
local Gear = require("../../src/ServerScriptService/Modules/Gear")
Pegada3P.env({ CFrame = CFrame, Vector3 = Vector3 })

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

local K = Pegada3P.S
local SZ = Pegada3P.SIZES
local function vs(t: { number }, kx: number?, ky: number?, kz: number?): any
	return Vector3.new(t[1] * K * (kx or 1), t[2] * K * (ky or 1), t[3] * K * (kz or 1))
end
type Box = { cf: any, h: any }
local function box(cf: any, size: any): Box
	return { cf = cf, h = size / 2 }
end
-- distância com sinal do ponto à caixa (< 0 dentro)
local function sd(p: any, b: Box): number
	local l = b.cf:PointToObjectSpace(p)
	local q = Vector3.new(math.abs(l.X) - b.h.X, math.abs(l.Y) - b.h.Y, math.abs(l.Z) - b.h.Z)
	local o = Vector3.new(math.max(q.X, 0), math.max(q.Y, 0), math.max(q.Z, 0))
	return o.Magnitude + math.min(math.max(q.X, q.Y, q.Z), 0)
end
local BODY = {
	box(CFrame.identity, vs(SZ.UpperTorso)),
	box(CFrame.new(0, 0.8 * K + 0.6 * K, 0), vs(SZ.Head)),
}
local rigR, rigL = Pegada3P.blockArm("R", K), Pegada3P.blockArm("L", K)
local a, b = Pegada3P.lengths(rigR)
local REACH = a + b
-- M14 (WeaponArt): punho -> soleira 1,046 stud, apoio 0,885 à frente, boca 2,98; D-108: na escala da
-- 3ª pessoa (comprimento L3, grossura G3)
local L3, G3 = Pegada3P.fatores3P("rifle")
local M14 = { rear = 1.046 * L3, support = Vector3.new(0, 0.036 * G3, -0.885 * L3), front = 2.976 * L3 }

type Result = {
	errR: number,
	errL: number,
	reachR: number,
	reachL: number,
	hands: number,
	bone: number,
	gun: number,
	aimDot: number,
}

local function v(t: { number }): any
	return Vector3.new(t[1], t[2], t[3])
end

local function run(st: any, torso: any, prone: boolean, aim: any, geo: any?): Result
	local W = geo or M14
	local g = Pegada3P.gun(torso, st)
	local gripT = g.Position
	local sup = if st.kind == "pistol"
		then Vector3.new(-0.12, -0.05, 0.05)
		else Pegada3P.support(W.support, W.front - 0.4, g:PointToObjectSpace(rigL.c0s.Position), REACH)
	local supT = g:PointToWorldSpace(sup)
	local poles = Pegada3P.POLES[if prone then "prone" else "stand"]
	local r1, r2 = Pegada3P.arm(rigR, gripT, v(poles.R))
	local l1, l2 = Pegada3P.arm(rigL, supT, v(poles.L))
	local uR, lR, hR = Pegada3P.parts(rigR, r1, r2)
	local uL, lL, hL = Pegada3P.parts(rigL, l1, l2)
	local gotR, gotL = (hR * rigR.grip).Position, (hL * rigL.grip).Position
	-- eixo dos ossos dentro do corpo (fora os 0,45 stud do ombro, que fica na quina do tronco)
	local function bone(rig: any, up: any, hd: any): number
		local sh = rig.c0s.Position
		local el = (up * rig.c0e).Position
		local gp = (hd * rig.grip).Position
		local worst = 0
		for i = 0, 20 do
			local t = i / 20
			local p = if t < 0.5 then sh:Lerp(el, t * 2) else el:Lerp(gp, (t - 0.5) * 2)
			if (p - sh).Magnitude > 0.45 then
				for _, bb in BODY do
					worst = math.max(worst, -sd(p, bb))
				end
			end
		end
		return worst
	end
	local _ = lR
	local _ = lL
	-- linha do cano, da soleira à boca
	local gun = 0
	for i = 0, 20 do
		local z = st.rear - (st.rear + W.front) * i / 20
		local p = g:PointToWorldSpace(Vector3.new(0, W.dy or 0.13 * G3, z))
		for _, bb in BODY do
			gun = math.max(gun, -sd(p, bb))
		end
	end
	-- direção do cano no rumo do corpo (HumanoidRootPart) contra a mira
	local fwd = (torso.Rotation * g.Rotation).LookVector
	return {
		errR = (gotR - gripT).Magnitude,
		errL = (gotL - supT).Magnitude,
		reachR = (gripT - rigR.c0s.Position).Magnitude / REACH,
		reachL = (supT - rigL.c0s.Position).Magnitude / REACH,
		hands = (gotR - gotL).Magnitude,
		bone = math.max(bone(rigR, uR, hR), bone(rigL, uL, hL)),
		gun = gun,
		aimDot = fwd:Dot(aim.LookVector),
	}
end

local BLADE = Pegada3P.blade("rifle")
-- tronco como o PostureController o põe: cintura com 35% da mira, de lado (menos correndo), inclinado
local function stand(fields: { [string]: any }, lean: number?): (any, any, any)
	local st = Pegada3P.state("rifle")
	st.rear = M14.rear
	for k2, v2 in fields do
		(st :: any)[k2] = v2
	end
	local pw = st.pitch * 0.35
	local bl = BLADE * (1 - st.sprint)
	local torso = CFrame.Angles(pw, 0, 0) * CFrame.Angles(0, -bl, 0) * CFrame.Angles(0, 0, -(lean or 0))
	return st, torso, CFrame.Angles(st.pitch, 0, 0)
end

test("braço: a pegada da mão chega ao alvo (IK do Front 44) e o alcance é o do R15 de bloco", function()
	near(REACH, (0.883 + 1.035) * K, 0.01, "ombro -> pegada")
	for _, t in { Vector3.new(0.3, 0, -1.6), Vector3.new(-0.3, 0.5, -1.8), Vector3.new(1.0, -0.8, -1.2) } do
		local r1, r2 = Pegada3P.arm(rigR, t, Vector3.new(1.6, -1.1, 0.5))
		local _, _, hand = Pegada3P.parts(rigR, r1, r2)
		near(((hand * rigR.grip).Position - t).Magnitude, 0, 1e-3, "mão no alvo")
	end
end)

test("pose: as duas mãos na arma, no alcance, afastadas, com o cano fora do corpo", function()
	local cases: { { any } } = {}
	local function add(name: string, st: any, torso: any, aim: any, prone: boolean?)
		table.insert(cases, { name, st, torso, aim, prone == true })
	end
	add("guarda", stand({}))
	for _, deg in { -60, -40, -20, 20, 40, 60 } do
		add("guarda " .. deg, stand({ pitch = math.rad(deg) }))
		add("ombro " .. deg, stand({ pitch = math.rad(deg), ads = 1 }))
	end
	add("ombro", stand({ ads = 1 }))
	add("correndo", stand({ sprint = 1, moving = 1, swing = 0.7, lift = 0.7 }))
	add("recarga", stand({ busy = 1 }))
	add("inclinado à direita", stand({}, math.rad(19.6)))
	add("no ombro inclinado à esquerda", stand({ ads = 1 }, -math.rad(19.6)))
	do
		local st = Pegada3P.state("rifle")
		st.rear, st.prone = M14.rear, 1
		add("deitado", st, CFrame.Angles(math.rad(-85), 0, 0), CFrame.identity, true)
		local st2 = Pegada3P.state("rifle")
		st2.rear, st2.prone, st2.pitch = M14.rear, 1, math.rad(15)
		add("deitado +15", st2, CFrame.Angles(math.rad(-85), 0, 0), CFrame.Angles(st2.pitch, 0, 0), true)
	end
	for _, c in cases do
		local r = run(c[2], c[3], c[5], c[4])
		print(
			string.format(
				"         %-26s alcance %3.0f%% / %3.0f%%  mãos %.2f  eixo do braço %4.1f cm  cano %4.1f cm",
				c[1],
				r.reachR * 100,
				r.reachL * 100,
				r.hands,
				r.bone * 28,
				r.gun * 28
			)
		)
		assert(r.errR < 1e-3, c[1] .. ": mão direita fora do punho")
		assert(r.reachR <= Pegada3P.REACH_USE + 1e-6, c[1] .. ": braço direito esticado demais")
		assert(r.errL < 0.02, string.format("%s: mão esquerda %.1f cm aquém do guarda-mão", c[1], r.errL * 28))
		assert(r.hands >= 0.6, string.format("%s: mãos encostadas (%.2f stud)", c[1], r.hands))
		assert(r.gun * 0.28 <= 0.05, string.format("%s: cano %.1f cm dentro do corpo", c[1], r.gun * 28))
		assert(r.bone * 0.28 <= 0.11, string.format("%s: braço %.1f cm dentro do corpo", c[1], r.bone * 28))
	end
end)

test("mira: no ombro a arma aponta para onde se mira (tronco de lado, inclinado ou deitado)", function()
	for _, deg in { -50, -20, 0, 20, 50 } do
		local st, torso, aim = stand({ pitch = math.rad(deg), ads = 1 })
		near(run(st, torso, false, aim).aimDot, 1, 1e-3, "no ombro " .. deg)
		local _, tl = stand({ pitch = math.rad(deg), ads = 1 }, math.rad(19.6))
		near(run(st, tl, false, aim).aimDot, 1, 1e-3, "inclinado " .. deg)
	end
	local st = Pegada3P.state("rifle")
	st.rear, st.prone = M14.rear, 1
	near(run(st, CFrame.Angles(math.rad(-85), 0, 0), true, CFrame.identity).aimDot, 1, 1e-3, "deitado")
	-- guarda baixa: o cano ~22° abaixo da mira (Front 44)
	local g, tg, ag = stand({})
	local d = math.deg(math.acos(math.clamp(run(g, tg, false, ag).aimDot, -1, 1)))
	assert(d > 18 and d < 30, string.format("guarda: %.1f° da mira", d))
end)

test("pistola: as duas mãos no cabo, braços à frente", function()
	local st = Pegada3P.state("pistol")
	local bl = Pegada3P.blade("pistol")
	local torso = CFrame.Angles(0, -bl, 0)
	local r = run(st, torso, false, CFrame.identity)
	assert(r.errR < 1e-3 and r.errL < 0.02, "mãos no cabo")
	assert(r.reachR > 0.75 and r.reachR <= 0.97, string.format("braço quase esticado: %.0f%%", r.reachR * 100))
	assert(math.deg(bl) < math.deg(BLADE), "pistola com o tronco menos de lado")
end)

test("mão de bloco mais estreita só no boneco de bloco", function()
	assert(Corpo.FORMATO ~= "bloco" or (Corpo.MAO_K > 0.4 and Corpo.MAO_K < 0.8), "mão de bloco estreitada")
	assert(Pegada3P.HAND_K == Corpo.MAO_K)
	-- com a mão estreitada as duas mãos não se cruzam na M14 (guarda): mais que a largura da mão
	local st, torso, aim = stand({})
	assert(run(st, torso, false, aim).hands >= Corpo.MAO_K * K, "mãos separadas")
end)

-- ===== D-108: armas maiores =====
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local WeaponArt = luau.load(
	fs.readFile("src/ReplicatedStorage/Shared/WeaponArt.luau"),
	{ debugName = "WeaponArt", environment = { Vector3 = Vector3 } }
)() :: any
local WS = require("../../src/ReplicatedStorage/Shared/Weapons") :: any
local TURN = {
	["-Z"] = CFrame.identity,
	["+Z"] = CFrame.Angles(0, math.pi, 0),
	["-X"] = CFrame.Angles(0, -math.pi / 2, 0),
	["+X"] = CFrame.Angles(0, math.pi / 2, 0),
}
local AXIS = {
	["-Z"] = Vector3.new(0, 0, -1),
	["+Z"] = Vector3.new(0, 0, 1),
	["-X"] = Vector3.new(-1, 0, 0),
	["+X"] = Vector3.new(1, 0, 0),
}
-- pontos da arte no espaço da arma (punho na origem, boca em −Z), como o GunModel.fit, escalados
local function artPoints(id: string, l: number, g: number): { [string]: any }
	local art = WeaponArt[id]
	local inv = (TURN[art.forward] * CFrame.Angles(0, art.yaw, 0)):Inverse()
	local out = {}
	for _, name in { "muzzle", "sight", "front", "grip", "support" } do
		out[name] = Pegada3P.escalaPonto(inv * (art[name] - art.grip), l, g)
	end
	-- soleira: comprimento da malha menos a boca, ao longo do cano
	out.rear = (art.lengthM / 0.28 - (art.muzzle - art.grip):Dot(AXIS[art.forward])) * l
	return out
end

test("D-108: fator da arma entre o real e o Front 44, sem caricatura", function()
	near(Corpo.ARMA_K, 1.4, 1e-9, "ARMA_K")
	near(Pegada3P.G, Corpo.ARMA_K, 1e-12, "grossura da 3ª pessoa")
	near(Pegada3P.L, Corpo.ARMA_COMPRIMENTO_3P, 1e-12, "comprimento da 3ª pessoa")
	-- comprimento / altura: M14 no soldado de 2,04 m; real (1,75 m); Front 44 (1,3x num boneco de 1,43 m)
	local aqui, real, f44 = 1.126 / 2.04, 1.126 / 1.75, 1.107 * 1.3 / (2.04 / Corpo.BLOCK_SCALE)
	print(string.format("         comprimento/altura: aqui %.2f, real %.2f, Front 44 %.2f", aqui, real, f44))
	-- grossura relativa ao corpo (real = 1): aqui G x 1,75 / 2,04; Front 44 1,3 x 1,5 no boneco dele
	local gq, gf = Corpo.ARMA_K * 1.75 / 2.04, 1.3 * 1.5 * 1.75 / (2.04 / Corpo.BLOCK_SCALE)
	print(string.format("         grossura/corpo (real = 1): aqui %.2f, Front 44 %.2f", gq, gf))
	assert(gq > 1 and gq < gf, "mais grossa que a real, menos que o Front 44")
	local l, g = Pegada3P.fatores3P("pistol")
	assert(l == Corpo.ARMA_K and g == Corpo.ARMA_K, "pistola cresce por inteiro")
end)

test("D-108: escala da arma em volta do punho (peças e pontos) e volta ao real", function()
	local p = Vector3.new(0.1, 0.2, -2)
	local s = Pegada3P.escalaPonto(p, 1.0, 1.4)
	near((s - Vector3.new(0.14, 0.28, -2)).Magnitude, 0, 1e-9, "ponto")
	-- peça alinhada: exata; peça de pé (eixo Y ao longo do cano): o eixo Y ganha o comprimento
	local sz = Pegada3P.escalaTamanho(Vector3.new(1, 2, 3), CFrame.identity, 1.0, 1.4)
	near((sz - Vector3.new(1.4, 2.8, 3)).Magnitude, 0, 1e-9, "alinhada")
	local rz = Pegada3P.escalaTamanho(Vector3.new(1, 2, 3), CFrame.Angles(math.pi / 2, 0, 0), 1.0, 1.4)
	near((rz - Vector3.new(1.4, 2, 4.2)).Magnitude, 0, 1e-5, "girada 90°")
	-- volta ao real: a medida de agora dividida pelos fatores de agora (GunModel.scale)
	local k = Pegada3P.escalaTamanho(Vector3.new(1, 1, 1), CFrame.Angles(0.3, 0.2, 0), 1.0, 1.4)
	local back = Pegada3P.escalaTamanho(Vector3.new(1, 2, 3) / k, CFrame.Angles(0.3, 0.2, 0), 1.0, 1.4)
	near((back - Vector3.new(1, 2, 3)).Magnitude, 0, 1e-5, "ida e volta")
end)

local LONGAS = { "m14", "type56", "sks", "m60", "rpd", "m70", "mosin", "m79" }
test("D-108: 3ª pessoa com cada arma escalada: mãos no punho e no guarda-mão, cano fora do corpo", function()
	for _, id in LONGAS do
		local kind = WS.get(id).kind
		local l, g = Pegada3P.fatores3P(kind)
		local P = artPoints(id, l, g)
		local geo = { rear = P.rear, support = P.support, front = -P.muzzle.Z, dy = 0.13 * g }
		local bl = Pegada3P.blade(kind)
		local worst = { r = 0, l = 0, gun = 0, bone = 0, hands = math.huge, where = "" }
		local function case(name: string, fields: { [string]: any }, lean: number?, prone: boolean?)
			local st = Pegada3P.state(kind)
			st.rear = geo.rear
			for k2, v2 in fields do
				(st :: any)[k2] = v2
			end
			local torso = if prone
				then CFrame.Angles(math.rad(-85), 0, 0)
				else CFrame.Angles(st.pitch * 0.35, 0, 0) * CFrame.Angles(0, -bl * (1 - st.sprint), 0) * CFrame.Angles(
					0,
					0,
					-(lean or 0)
				)
			local r = run(st, torso, prone == true, CFrame.Angles(st.pitch, 0, 0), geo)
			if r.reachR > worst.r then
				worst.r, worst.where = r.reachR, name
			end
			worst.l = math.max(worst.l, r.errL)
			worst.gun = math.max(worst.gun, r.gun)
			worst.bone = math.max(worst.bone, r.bone)
			worst.hands = math.min(worst.hands, r.hands)
			assert(r.errR < 1e-3, id .. " " .. name .. ": mão direita fora do punho")
		end
		case("guarda", {})
		for _, deg in { -60, -40, -20, 20, 40, 60 } do
			case("guarda " .. deg, { pitch = math.rad(deg) })
			case("ombro " .. deg, { pitch = math.rad(deg), ads = 1 })
		end
		case("correndo", { sprint = 1, moving = 1, swing = 0.7, lift = 0.7 })
		case("correndo (outro passo)", { sprint = 1, moving = 1, swing = -0.7, lift = 0.7 })
		case("recarga", { busy = 1 })
		case("inclinado", {}, math.rad(19.6))
		case("deitado", { prone = 1 }, nil, true)
		print(
			string.format(
				"         %-7s %.2f m  dir %3.0f%% (%s)  esq %4.1f cm  mãos %.2f  cano %4.1f cm  braço %4.1f cm",
				id,
				WeaponArt[id].lengthM * l,
				worst.r * 100,
				worst.where,
				worst.l * 28,
				worst.hands,
				worst.gun * 28,
				worst.bone * 28
			)
		)
		assert(worst.r <= Pegada3P.REACH_USE + 1e-6, id .. ": braço direito esticado demais em " .. worst.where)
		assert(worst.gun * 0.28 <= 0.05, id .. string.format(": cano %.1f cm dentro do corpo", worst.gun * 28))
		assert(worst.bone * 0.28 <= 0.11, id .. string.format(": braço %.1f cm dentro do corpo", worst.bone * 28))
		-- a M79 tem o guarda-mão curto e o tronco quase de frente (8°): as mãos ficam juntas, como já
		-- eram no tamanho real
		if id ~= "m79" then
			assert(worst.l < 0.02 / 0.28, id .. string.format(": mão esquerda %.1f cm aquém", worst.l * 28))
			assert(worst.hands >= 0.6, id .. ": mãos encostadas")
		end
	end
end)

test("D-108: lança-rojão (RPG-2) com o tubo no ombro: mão no punho, tubo fora da cabeça e do tronco", function()
	local l, g = Pegada3P.fatores3P("launcher")
	local P = artPoints("rpg2", l, g)
	assert(P.rear > Pegada3P.TUBE_REAR * l, "o RPG-2 é de tubo")
	local m79 = artPoints("m79", l, g)
	assert(m79.rear < Pegada3P.TUBE_REAR * l, "a M79 fica na pega de coronha")
	local geo = { rear = P.rear, support = P.support, front = -P.muzzle.Z, dy = Pegada3P.TUBE.dy * g }
	local bl = Pegada3P.blade("launcher")
	local worstR, worstGun = 0, 0
	for _, deg in { -40, -20, 0, 10, 30 } do
		for _, ads in { 0, 1 } do
			local st = Pegada3P.state("launcher")
			st.rear, st.pitch, st.ads = geo.rear, math.rad(deg), ads
			local torso = CFrame.Angles(st.pitch * 0.35, 0, 0) * CFrame.Angles(0, -bl, 0)
			local r = run(st, torso, false, CFrame.Angles(st.pitch, 0, 0), geo)
			assert(r.errR < 1e-3, "mão direita no punho")
			worstR, worstGun = math.max(worstR, r.reachR), math.max(worstGun, r.gun)
		end
	end
	print(
		string.format(
			"         rpg2: braço direito %.0f%% do alcance, tubo %.1f cm dentro do corpo",
			worstR * 100,
			worstGun * 28
		)
	)
	assert(worstR <= Pegada3P.REACH_USE, "braço direito alcança o punho")
	assert(worstGun * 0.28 <= 0.05, string.format("tubo %.1f cm dentro do corpo", worstGun * 28))
end)

test("D-108: 1ª pessoa: alça e massa no centro com a arma maior, imagem da mira igual à real", function()
	local k = Corpo.ARMA_K
	local HIP = CFrame.new(0.12 / 0.28, -0.15 / 0.28, -0.23 / 0.28) * CFrame.Angles(0, math.rad(3), 0)
	for _, id in { "m14", "type56", "sks", "m60", "rpd", "m79", "m1911", "type54" } do
		local real, big = artPoints(id, 1, 1), artPoints(id, k, k)
		local eye = (WS.adsEye(id) or WeaponArt[id].eyeM) / 0.28
		local ads1 = Pegada3P.mira1P(real.sight, real.front, eye, 1)
		local adsK = Pegada3P.mira1P(big.sight, big.front, eye, k)
		-- alça no eixo do olho, a eye x k; a massa exatamente no centro (direção −Z)
		local s, f = adsK * big.sight, adsK * big.front
		near(s.X, 0, 1e-4, id .. " alça x")
		near(s.Y, 0, 1e-4, id .. " alça y")
		near(s.Z, -eye * k, 1e-4, id .. " olho")
		local d = (f - Vector3.new(0, 0, 0)).Unit
		near(d.X, 0, 1e-4, id .. " massa x")
		near(d.Y, 0, 1e-4, id .. " massa y")
		-- mesma imagem: cada ponto da arma maior é o da real ampliado k vezes em volta do olho
		for _, name in { "muzzle", "grip", "support" } do
			local p1, pk = ads1 * real[name], adsK * big[name]
			near((pk - p1 * k).Magnitude, 0, 1e-3, id .. " " .. name)
		end
		-- quadril: a alça fica onde estava (D-69) e o resto cresce em volta dela
		local hk = Pegada3P.quadril1P(HIP, big.sight, k)
		near((hk * big.sight - HIP * real.sight).Magnitude, 0, 1e-4, id .. " alça no quadril")
		assert((hk * big.muzzle - hk * big.grip).Magnitude > (HIP * real.muzzle - HIP * real.grip).Magnitude, "maior")
	end
end)

test("D-108: a bala não muda: o tiro sai do olho (câmera), nunca da boca da arma desenhada", function()
	local wc = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/WeaponController.client.luau")
	local body = string.match(wc, "local function shotRay%(.-\nend") :: string
	assert(body and string.find(body, "ViewMode.aimDirection", 1, true), "origem = olho")
	assert(not string.find(body, "Muzzle", 1, true), "a origem não vem da arma")
	-- e o servidor confere a origem contra a cabeça (Gatilho), não contra a arma
	local cs = fs.readFile("src/ServerScriptService/Modules/CombatService.luau")
	assert(string.find(cs, "originStuds = (origin - head.Position).Magnitude", 1, true), "origem x cabeça")
end)

test("capacete na cabeça de bloco: a borda de cima da cabeça fica dentro do casco", function()
	local head = Gear.vec(1.2 * K, 1.2 * K, 1.2 * K)
	local native = {
		us_m1_helmet = Gear.vec(1.02, 0.98, 0.88),
		vc_pith_helmet = Gear.vec(1.14, 0.95, 0.96),
		vc_jungle_hat = Gear.vec(1.13, 0.95, 1.21),
	}
	for key, nat in native do
		local f = Gear.headgearFit(key, head, nat) :: any
		assert(f, key)
		local c = Gear.HEADGEAR[key]
		-- copa: elipsoide da aba (brimY) até o topo (topY), meia-largura copa/2
		local a2 = f.body.x * c.crown / 2
		local cz = f.body.z * c.crown / 2
		local hgt = f.topY - f.brimY
		-- borda de cima da cabeça clássica (cilindro arredondado): raio 0,4 x lado a 0,42 x altura
		local rx, ry = 0.4 * head.x, 0.42 * head.y
		local u = (ry - f.brimY) / hgt
		assert(u < 1, key .. ": topo da copa abaixo da cabeça")
		local wAt = math.sqrt(1 - u * u)
		assert(
			rx <= a2 * wAt and rx <= cz * wAt,
			string.format("%s: a cabeça fura a copa (%.2f > %.2f)", key, rx, a2 * wAt)
		)
		assert(f.brimY >= 0.1 * head.y, key .. ": aba na linha dos olhos")
	end
	-- cabeça antiga (peça 2 x 1 x 1 com malha): a medida visível, não a da peça
	local h = Gear.headSize(Gear.vec(2, 1, 1), true)
	near(h.x, 1.25, 1e-9)
	local same = Gear.headSize(head, false)
	assert(same.x == head.x and same.y == head.y)
end)

test("deslizar (Front 44): começa mais rápido que a corrida e termina agachado", function()
	near(Movement.slideSpeed(0, nil), 27 * 0.28, 1e-9, "27 studs/s")
	assert(Movement.slideSpeed(0, nil) > Movement.SPRINT, "mais que a corrida")
	near(Movement.slideSpeed(Movement.SLIDE_S, nil), Movement.CROUCH, 1e-9, "acaba agachado")
	local last = math.huge
	for i = 0, 20 do
		local s = Movement.slideSpeed(Movement.SLIDE_S * i / 20, nil)
		assert(s <= last + 1e-9, "só desacelera")
		last = s
	end
	near(Movement.slideSpeed(0, "VC"), 27 * 0.28 * 1.12, 1e-9, "VC")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
