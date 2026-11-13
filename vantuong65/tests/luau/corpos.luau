--!strict
-- Caído, morte e corpos (D-107): pose de ferido deitado (Shared/SoldierAnims), juntas do boneco e
-- fila dos corpos (Shared/Corpos). Uso, a partir de vantuong65/: lune run tests/luau/corpos.luau
-- A pose é conferida num FK do R15 de bloco do Studio (juntas de tools/anim/r15.py; peças do
-- characterR15: tronco 2 × 1,6 × 1, quadril 2 × 0,4 × 1, membros 1 de largura e de fundo), na escala
-- do jogo (Corpo.BLOCK_SCALE nos três eixos).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local S = "../../src/ReplicatedStorage/Shared/"
local SoldierAnims = require(S .. "SoldierAnims")
local Corpos = require(S .. "Corpos")
local Corpo = require(S .. "Corpo")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

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

-- ===== FK do R15 de bloco =====
local s = Corpo.BLOCK_SCALE
local SIZES: { [string]: { number } } = {
	LowerTorso = { 2, 0.4, 1 },
	UpperTorso = { 2, 1.6, 1 },
	UpperArm = { 1, 1.169, 1 },
	LowerArm = { 1, 1.052, 1 },
	Hand = { 1, 0.3, 1 },
	UpperLeg = { 1, 1.217, 1 },
	LowerLeg = { 1, 1.193, 1 },
	Foot = { 1, 0.3, 1 },
}
local HEAD_R = 0.6 -- a cabeça de bloco é redonda (malha ~1,2 de lado): esfera para o "mais baixo"
local L: { [string]: { any } } = {
	Waist = { "LowerTorso", "UpperTorso", { 0, 0.2, 0 }, { 0, -0.8, 0 } },
	Neck = { "UpperTorso", "Head", { 0, 0.8, 0 }, { 0, -0.5, 0 } },
	LeftShoulder = { "UpperTorso", "LeftUpperArm", { -1, 0.563, 0 }, { 0.5, 0.394, 0 } },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm", { 0, -0.334, 0 }, { 0, 0.259, 0 } },
	LeftWrist = { "LeftLowerArm", "LeftHand", { 0, -0.501, 0 }, { 0, 0.125, 0 } },
	LeftHip = { "LowerTorso", "LeftUpperLeg", { -0.5, -0.2, 0 }, { 0, 0.421, 0 } },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg", { 0, -0.401, 0 }, { 0, 0.379, 0 } },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot", { 0, -0.547, 0 }, { 0, 0.102, 0 } },
}
local J: { [string]: { any } } = {}
for n, d in L do
	J[n] = d
	if string.sub(n, 1, 4) == "Left" then
		local function m(v: { number }): { number }
			return { -v[1], v[2], v[3] }
		end
		J["Right" .. string.sub(n, 5)] =
			{ (string.gsub(d[1], "Left", "Right")), (string.gsub(d[2], "Left", "Right")), m(d[3]), m(d[4]) }
	end
end
local ORDER = {
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}
local function cf(v: { number }): any
	return CFrame.new(v[1] * s, v[2] * s, v[3] * s)
end
local function ang(a: { number }): any
	return CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
end
local function sizeOf(p: string): any
	for k, v in SIZES do
		if string.sub(p, -#k) == k then
			return Vector3.new(v[1] * s, v[2] * s, v[3] * s)
		end
	end
	return nil
end

-- HRP em pé com a base a `hip` do chão (y = 0); a junta Root fica na base dele
local MIN_HIP = SoldierAnims.BAKED.minHip * SoldierAnims.SCALE
local function downedC0(): any
	local D = SoldierAnims.DOWNED
	return CFrame.new(0, SoldierAnims.downedRootY(0.5 * s, MIN_HIP), 0) * CFrame.Angles(math.rad(D.pitchDeg), 0, 0)
end
local function fk(pose: { [string]: { number } }?): { [string]: any }
	local hrp = CFrame.new(0, MIN_HIP + s, 0) -- HRP de 2 s de altura
	local W: { [string]: any } = {}
	W.LowerTorso = hrp * CFrame.new(0, -s, 0) * downedC0() * cf({ 0, -0.2, 0 }):Inverse()
	for _, j in ORDER do
		local d = J[j]
		local T = if pose and pose[j] then ang(pose[j]) else CFrame.identity
		W[d[2]] = W[d[1]] * cf(d[3]) * T * cf(d[4]):Inverse()
	end
	return W
end
local function lowOf(name: string, c: any): number
	if name == "Head" then
		return c.Position.Y - HEAD_R * s
	end
	local h = sizeOf(name) / 2
	local lo = math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				lo = math.min(lo, (c * Vector3.new(x * h.X, y * h.Y, z * h.Z)).Y)
			end
		end
	end
	return lo
end

test("caído de costas: no repouso do servidor as costas encostam no chão (folga DOWNED.gap)", function()
	local W = fk(nil)
	local lo = math.huge
	for name, c in W do
		if name ~= "Head" then
			lo = math.min(lo, lowOf(name, c))
		end
	end
	near(lo, SoldierAnims.DOWNED.gap, 0.02, "parte mais baixa")
	-- a cabeça redonda é mais funda que o tronco: no repouso do servidor encosta ~3 cm a mais
	assert(lowOf("Head", W.Head) > -0.15, "cabeça enterrada")
	-- deitado de verdade: a frente do tronco olha para cima
	assert(W.UpperTorso.LookVector.Y > 0.99, "tronco de costas")
	assert(W.LowerTorso.Position.Y < 1.0, "quadril no chão")
end)

test("pose de ferido: nada enterrado, pé dobrado apoiado, mão no flanco (FK, vários instantes)", function()
	for _, seed in { 0, 1, 42, 77 } do
		for t = 0, 20, 0.37 do
			local pose = SoldierAnims.downedPose(t, seed)
			local W = fk(pose)
			for name, c in W do
				local lo = lowOf(name, c)
				assert(lo > -0.15, string.format("%s enterrado %.2f stud (semente %d, t %.2f)", name, lo, seed, t))
			end
			-- o joelho dobrado fica no alto e o pé no chão (lado da semente)
			local bent = if seed % 2 == 1 then "Right" else "Left"
			local foot = lowOf(bent .. "Foot", W[bent .. "Foot"])
			assert(foot < 0.45, string.format("pé dobrado no ar: %.2f", foot))
			local knee = (W[bent .. "UpperLeg"] * cf({ 0, -0.401, 0 })).Position.Y
			assert(knee > 1.0, string.format("joelho baixo: %.2f", knee))
			-- a mão do flanco fica à frente do tronco (acima dele, deitado), perto da barriga
			local free = if seed % 2 == 1 then "Right" else "Left"
			local hand = W.UpperTorso:ToObjectSpace(W[free .. "Hand"])
			assert(hand.Z < -0.5 * s and hand.Z > -1.8 * s, string.format("mão longe do tronco: %.2f", hand.Z))
			assert(math.abs(hand.X) < 1.4 * s, string.format("mão fora do flanco: %.2f", hand.X))
		end
	end
end)

test("pose de ferido mexe pouco e espelha pela semente", function()
	local base = SoldierAnims.DOWNED_POSE
	for t = 0, 30, 0.1 do
		local p = SoldierAnims.downedPose(t, 0)
		for name, a in p do
			local b = base[name]
			local d = math.max(math.abs(a[1] - b[1]), math.abs(a[2] - b[2]), math.abs(a[3] - b[3]))
			local lim = if name == "RightElbow" or name == "RightShoulder" then 26 else 9
			assert(d <= lim, string.format("%s mexe %.1f° (t %.1f)", name, d, t))
		end
	end
	local a, b = SoldierAnims.downedPose(3.3, 10), SoldierAnims.downedPose(3.3, 11)
	-- 10 e 11 têm fases diferentes; o espelho de 11 tem o joelho dobrado à direita
	assert(b.RightKnee[1] < -90 and b.LeftKnee[1] > -20, "semente ímpar: joelho direito dobrado")
	assert(a.LeftKnee[1] < -90 and a.RightKnee[1] > -20, "semente par: joelho esquerdo dobrado")
	assert(b.RightShoulder[2] > 0 and b.LeftShoulder[3] < 0, "espelho inverte Y e Z")
end)

test("queda até deitar: suave de 0 a 1 em DOWNED.fallS e dobra só no meio", function()
	local e0, b0 = SoldierAnims.fallBlend(0)
	local e1, b1 = SoldierAnims.fallBlend(SoldierAnims.DOWNED.fallS)
	local em, bm = SoldierAnims.fallBlend(SoldierAnims.DOWNED.fallS / 2)
	near(e0, 0, 1e-9)
	near(e1, 1, 1e-9)
	near(em, 0.5, 1e-9)
	near(b0, 0, 1e-9)
	near(b1, 0, 1e-6)
	near(bm, 1, 1e-9)
	local last = -1
	for x = 0, 1, 0.05 do
		local e = SoldierAnims.fallBlend(x * SoldierAnims.DOWNED.fallS)
		assert(e >= last, "anda só para a frente")
		last = e
	end
	local eInf = SoldierAnims.fallBlend(math.huge)
	near(eInf, 1, 1e-9, "quem chega depois vê deitado")
end)

-- ===== juntas do boneco =====
local function rot(a: { number }): any
	return ang(a).Rotation
end

test("boneco: 14 juntas, cotovelo dobra para a frente e joelho para trás (como o agachado)", function()
	local n = 0
	for name in Corpos.JUNTAS do
		n += 1
		assert(SoldierAnims.DOWNED_POSE[name], name .. " sem pose de caído")
	end
	assert(n == 14, "juntas: " .. n)
	-- o agachado do PostureController dobra o joelho em −115° e o quadril em +75° no eixo X
	local pc = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/PostureController.client.luau")
	local knee = tonumber(string.match(pc, "LeftKnee = CFrame%.Angles%(math%.rad%((%-?%d+)%)"))
	local hip = tonumber(string.match(pc, "LeftHip = CFrame%.Angles%(math%.rad%((%-?%d+)%)"))
	assert(knee and hip, "CROUCH no PostureController")
	for _, side in { "Left", "Right" } do
		local k, e = Corpos.JUNTAS[side .. "Knee"], Corpos.JUNTAS[side .. "Elbow"]
		assert(k.tipo == "dobra" and e.tipo == "dobra")
		assert((k.min :: number) <= (knee :: number) and (k.max :: number) <= 5, "joelho só para trás")
		assert((e.min :: number) >= -5 and (e.max :: number) >= 120, "cotovelo só para a frente")
		local h = Corpos.JUNTAS[side .. "Hip"]
		assert((h.cone :: number) >= (hip :: number), "o agachado cabe no cone do quadril")
	end
end)

test("boneco: a pose de ferido cabe nos limites (morrer caído não torce o corpo)", function()
	for _, seed in { 0, 1 } do
		local pose = SoldierAnims.downedPose(1.7, seed)
		for name, spec in Corpos.JUNTAS do
			local a = pose[name]
			if spec.tipo == "dobra" then
				assert(a[2] == 0 and a[3] == 0, name .. ": dobra só em X")
				assert(a[1] >= (spec.min :: number) and a[1] <= (spec.max :: number), name .. " fora da dobra")
			else
				local e1 = Corpos.eixos(spec)
				local axis = Vector3.new(e1[1], e1[2], e1[3])
				local moved = rot(a) * axis
				local cone = math.deg(math.acos(math.clamp(axis:Dot(moved), -1, 1)))
				assert(cone <= (spec.cone :: number), string.format("%s: cone %.0f° > %d°", name, cone, spec.cone))
			end
		end
	end
end)

test("boneco: eixos das juntas ortonormais (cone em volta do osso)", function()
	for name, spec in Corpos.JUNTAS do
		local e1, e2 = Corpos.eixos(spec)
		local a, b = Vector3.new(e1[1], e1[2], e1[3]), Vector3.new(e2[1], e2[2], e2[3])
		near(a:Dot(b), 0, 1e-9, name)
		near(a.Magnitude, 1, 1e-9, name)
		if spec.tipo == "bola" then
			local up = name == "Neck" or name == "Waist"
			near(a.Y, if up then 1 else -1, 1e-9, name .. ": eixo do osso")
		else
			near(a.X, 1, 1e-9, name .. ": dobra em X")
		end
	end
end)

-- ===== corpos no mapa =====
test("corpos: some depois de VIDA_S e, acima do TETO, o mais velho some depressa", function()
	local fila = {}
	for i = 1, Corpos.TETO do
		table.insert(fila, { nasceu = i, sumindo = false })
	end
	local out = Corpos.paraSumir(fila, 0, Corpos.TETO + 1)
	assert(#out == 0, "no teto e ninguém vencido")
	out = Corpos.paraSumir(fila, 2, Corpos.TETO + 1)
	assert(#out == 2 and out[1].i == 1 and out[2].i == 2, "dois caindo: os dois mais velhos")
	assert(out[1].s == Corpos.SUMIR_RAPIDO_S, "pelo teto, depressa")
	out = Corpos.paraSumir(fila, 0, 1 + Corpos.VIDA_S)
	assert(#out == 1 and out[1].i == 1 and out[1].s == Corpos.SUMIR_S, "vencido some devagar")
	fila[1].sumindo = true
	out = Corpos.paraSumir(fila, 1, Corpos.TETO + 1)
	assert(#out == 0, "o que já some não conta no teto")
	assert(Corpos.VIDA_S >= 20 and Corpos.VIDA_S <= 30, "20 a 30 s no chão")
	assert(Corpos.TETO >= 10, "teto de corpos")
end)

test("corpos: congela parado ou no tempo máximo; apaga pelo relógio do servidor", function()
	local p, done = Corpos.assentar(0, 0.5, 0.3, 1)
	assert(not done and p > 0)
	p, done = Corpos.assentar(p, 0.5, 0.3, 1.3)
	assert(done, "parado 0,6 s")
	p, done = Corpos.assentar(p, 5, 0.1, 1.4)
	assert(p == 0 and not done, "mexeu: conta de novo")
	local _, late = Corpos.assentar(0, 30, 0.1, Corpos.ASSENTAR_MAX_S)
	assert(late, "tempo máximo")
	near(Corpos.apagado(10, nil, nil), 0, 1e-9)
	near(Corpos.apagado(10, 10, 2), 0, 1e-9)
	near(Corpos.apagado(11, 10, 2), 0.5, 1e-9)
	near(Corpos.apagado(99, 10, 2), 1, 1e-9)
end)

test("corpos: corpo deitado sobe o quanto está enterrado (com folga e teto)", function()
	near(Corpos.erguer({}), 0, 1e-9)
	near(Corpos.erguer({ { 1, 0 }, { 2, 0 } }), 0, 1e-9, "tudo acima do chão")
	near(Corpos.erguer({ { -0.5, 0 }, { 0.2, 0 } }), 0.6, 1e-9)
	near(Corpos.erguer({ { -40, 0 } }), Corpos.ERGUER_MAX, 1e-9, "teto")
end)

-- ===== ligações no código =====
local function src(path: string): string
	return fs.readFile("src/" .. path)
end

test("desistir caído a qualquer hora (servidor e tela)", function()
	local Medical = require(S .. "Medical") :: any
	assert(Medical.C.giveUpAfter == 0, "Medical.C.giveUpAfter")
	local ms = src("ServerScriptService/Modules/MedicalService.luau")
	assert(string.find(ms, 'if req.op == "giveup" then', 1, true), "giveup antes de tudo")
	assert(not string.find(ms, "canGiveUp", 1, true), "o servidor não espera tempo")
	local mc = src("StarterPlayer/StarterPlayerScripts/Controllers/MedicalController.client.luau")
	assert(string.find(mc, "input.KeyCode.Name == giveUpKey()", 1, true), "tecla direta do teclado")
end)

test("morte e caído ligados no servidor", function()
	local cs = src("ServerScriptService/Modules/CorposService.luau")
	assert(string.find(cs, "hum.BreakJointsOnDeath = false", 1, true), "juntas não quebram")
	assert(string.find(cs, 'd:IsA("AlignOrientation")', 1, true), "solta a BotFacing")
	local ps = src("ServerScriptService/Modules/PostureService.luau")
	assert(string.find(ps, "MedicalService.onDowned = PostureService.setDowned", 1, true), "gancho do caído")
	local ms = src("ServerScriptService/Modules/MedicalService.luau")
	assert(string.find(ms, "CorposService.start()", 1, true), "corpos ligados")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
