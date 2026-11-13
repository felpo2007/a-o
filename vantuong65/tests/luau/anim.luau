--!strict
-- Testes das animações do soldado (Shared/SoldierAnims). Uso: lune run tests/luau/anim.luau
-- Os clipes gerados (assets/mocap/soldado, fora do Git) são conferidos só se existirem.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local S = "../../src/ReplicatedStorage/Shared/"
local SoldierAnims = require(S .. "SoldierAnims")
local Movement = require(S .. "Movement")
local ArmIK = require(S .. "ArmIK")

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

local CLIPS = SoldierAnims.CLIPS
-- roda fn com ids de mentira (e devolve os de verdade depois)
local function withIds(ids: { [string]: number }, fn: () -> ())
	local saved = {}
	for n, c in CLIPS do
		saved[n] = c.id
		c.id = ids[n] or 0
	end
	local ok, err = pcall(fn)
	for n, c in CLIPS do
		c.id = saved[n]
	end
	if not ok then
		error(err, 0)
	end
end
local ALL = {}
for n in CLIPS do
	ALL[n] = 1
end

local function sum(w: { [string]: number }): number
	local s = 0
	for _, v in w do
		s += v
	end
	return s
end

test("com os ids em 0 nada liga (o jogo fica como está)", function()
	local any = false
	for _, c in CLIPS do
		any = any or c.id ~= 0
	end
	if not any then
		assert(not SoldierAnims.enabled(), "enabled com ids 0")
	end
	withIds({ parado = 1, andar = 1, trote = 1 }, function()
		assert(not SoldierAnims.enabled(), "sem correr não liga")
	end)
	withIds({ parado = 1, andar = 1, trote = 1, correr = 1 }, function()
		assert(SoldierAnims.enabled(), "os quatro de pé ligam")
	end)
end)

test("passada de pé: peso cheio nas velocidades do jogo e soma 1 entre elas", function()
	local w = SoldierAnims.gaitWeights(Movement.WALK)
	near(w.andar or 0, 1, 1e-9, "andar em WALK")
	w = SoldierAnims.gaitWeights(Movement.JOG)
	near(w.trote or 0, 1, 1e-9, "trote em JOG")
	w = SoldierAnims.gaitWeights(Movement.SPRINT)
	near(w.correr or 0, 1, 1e-9, "correr em SPRINT")
	w = SoldierAnims.gaitWeights(0.6)
	near(w.andar or 0, 1, 1e-9, "devagar = andar")
	local last = 0
	for v = 1.4, 5.5, 0.1 do
		local g = SoldierAnims.gaitWeights(v)
		near(sum(g), 1, 1e-9, "soma em " .. v)
		local fast = (g.trote or 0) * 0.5 + (g.correr or 0)
		assert(fast >= last - 1e-9, "a mistura anda para a corrida com a velocidade")
		last = fast
	end
end)

test("estado -> clipe: postura, parado/andando com histerese e camada fora no ar", function()
	withIds(ALL, function()
		local w, m = SoldierAnims.targets({ stance = "stand", speed = 0, active = true, moving = false })
		assert(w.parado == 1 and not m, "parado")
		w, m = SoldierAnims.targets({ stance = "stand", speed = 0.2, active = true, moving = false })
		assert(w.parado == 1 and not m, "0,2 m/s parado continua parado")
		w, m = SoldierAnims.targets({ stance = "stand", speed = 0.2, active = true, moving = true })
		assert(m and (w.andar or 0) == 1, "0,2 m/s andando continua andando")
		w = SoldierAnims.targets({ stance = "stand", speed = Movement.JOG, active = true, moving = true })
		assert(w.trote == 1, "trote no JOG")
		w = SoldierAnims.targets({ stance = "crouch", speed = 0, active = true, moving = false })
		assert(w.agachado == 1, "agachado parado")
		w = SoldierAnims.targets({ stance = "crouch", speed = 0.8, active = true, moving = false })
		assert(w.agachado_andar == 1, "agachado andando")
		w = SoldierAnims.targets({ stance = "prone", speed = 0, active = true, moving = false })
		assert(w.deitado == 1, "deitado")
		w = SoldierAnims.targets({ stance = "prone", speed = 0.3, active = true, moving = false })
		assert(w.rastejar == 1, "rastejando")
		w, m = SoldierAnims.targets({ stance = "stand", speed = 3, active = false, moving = true })
		assert(next(w) == nil and not m, "no ar a camada sai")
	end)
end)

test("clipe sem id: a postura sai da camada e a mistura se ajusta", function()
	withIds({ parado = 1, andar = 1, trote = 1, correr = 1 }, function()
		local w = SoldierAnims.targets({ stance = "crouch", speed = 0, active = true, moving = false })
		assert(next(w) == nil, "agachado sem id: fica o PostureController")
	end)
	withIds({ parado = 1, andar = 1, trote = 1 }, function()
		local w = SoldierAnims.targets({ stance = "stand", speed = 4.3, active = true, moving = true })
		near(w.trote or 0, 1, 1e-9, "sem correr, o trote cobre")
	end)
end)

-- D-98: o corpo do jogo é o da gravação ampliado por SCALE; a passada também
local SC = SoldierAnims.SCALE
test("velocidade casada: pé apoiado parado no chão em qualquer velocidade real", function()
	for name, c in CLIPS do
		if c.cycles > 0 then
			for _, k in { 0.8, 1, 1.3 } do
				local v = c.speed * SC * k
				local r = SoldierAnims.trackSpeed(name, SoldierAnims.cycleRate({ [name] = 1 }, v))
				-- tocando a r, o chão do clipe (no corpo ampliado) anda a speed * SCALE * r
				near(c.speed * SC * r, v, 1e-6, name)
			end
		end
	end
	-- 2026-11-13: o trote do Front 44 (3,92 m/s) toca o clipe gravado a 2,663 m/s no corpo de 1,75 m
	near(
		SoldierAnims.trackSpeed("trote", SoldierAnims.cycleRate({ trote = 1 }, Movement.JOG)),
		Movement.JOG / (2.663 * SC),
		1e-3
	)
	assert(Movement.JOG / (2.663 * SC) <= SoldierAnims.RATE_MAX, "trote dentro do teto do clipe")
	-- rastejar e agachado (o VC 12% mais rápido) também dentro do teto: o pé não desliza
	for _, case in { { "rastejar", "prone" }, { "agachado_andar", "crouch" } } do
		for _, faction in { "US", "VC" } do
			local v = Movement.serverSpeed(case[2], false, false, false, faction, 1)
			local r = SoldierAnims.trackSpeed(case[1], SoldierAnims.cycleRate({ [case[1]] = 1 }, v))
			near(CLIPS[case[1]].speed * SC * r, v, 1e-6, case[1] .. " " .. faction .. " desliza")
		end
	end
end)

test("mistura em fase: os dois clipes fazem os mesmos ciclos por segundo", function()
	local v = 2.2
	local w = SoldierAnims.gaitWeights(v)
	local f = SoldierAnims.cycleRate(w, v)
	for name in w do
		local c = CLIPS[name]
		near(SoldierAnims.trackSpeed(name, f) * c.cycles / c.length, f, 1e-9, name)
	end
	-- passada média ponderada: a velocidade sai certa
	local stride = 0
	for name, k in w do
		local c = CLIPS[name]
		stride += k * c.speed * SC * c.length / c.cycles
	end
	near(f * stride, v, 1e-9, "ciclos x passada")
end)

test("pernas na direção do movimento; de costas a passada volta", function()
	local y, back = SoldierAnims.legYaw(0, 0, 2)
	assert(y == 0 and not back, "para a frente")
	y, back = SoldierAnims.legYaw(0, math.rad(40), 2)
	near(y, math.rad(40), 1e-9)
	y, back = SoldierAnims.legYaw(0, math.rad(-90), 2)
	near(y, -SoldierAnims.LEG_YAW_MAX, 1e-9, "de lado: limita")
	y, back = SoldierAnims.legYaw(0, math.pi, 2)
	assert(math.abs(y) < 1e-9 and back, "de costas")
	y, back = SoldierAnims.legYaw(0, math.rad(150), 2)
	near(y, math.rad(-30), 1e-9, "de costas na diagonal")
	assert(back)
	y, back = SoldierAnims.legYaw(0, math.rad(90), 0.1)
	assert(y == 0 and not back, "parado")
end)

test("troca de postura: descida do HRP e correção vertical da mistura", function()
	-- D-94: 1,03 na gravação (era 2,2); D-98: vezes SCALE no corpo de 2 m
	local dc = SoldierAnims.BAKED.drop.crouch * SC
	local dp = 2.3 * SC -- deitado: HipHeight preso no MIN_HIP
	near(SoldierAnims.bakedDrop("stand"), 0, 1e-9)
	near(SoldierAnims.bakedDrop("crouch"), dc, 1e-9)
	near(SoldierAnims.bakedDrop("prone"), dp, 1e-9, "deitado: HipHeight preso no MIN_HIP")
	near(SoldierAnims.rootLift({ stand = 1 }, 0), 0, 1e-9)
	near(SoldierAnims.rootLift({ crouch = 1 }, dc), 0, 1e-9)
	near(SoldierAnims.rootLift({ prone = 1 }, dp), 0, 1e-9)
	-- metade da mistura: o clipe de pé sobe o que o HRP desceu, o agachado fica
	near(SoldierAnims.rootLift({ stand = 0.5, crouch = 0.5 }, dc), dc / 2, 1e-9)
	-- o HRP ainda não desceu: o agachado desce já
	near(SoldierAnims.rootLift({ crouch = 1 }, 0), -dc, 1e-9)
	near(SoldierAnims.hipLag(-2.2, 0), -2.2, 1e-9)
	near(SoldierAnims.hipLag(-2.2, -1.5), -0.7, 1e-9)
	near(SoldierAnims.hipLag(-2.2, -3), 0, 1e-9, "passou do alvo")
	near(SoldierAnims.hipLag(2.2, 1), 1.2, 1e-9, "subindo")
end)

test("tempos de mistura vêm da câmera (Movement.STANCE_TIME), deitar no máximo 0,6 s", function()
	near(SoldierAnims.fadeTime("stand", "crouch"), Movement.STANCE_TIME["stand>crouch"], 1e-9)
	-- 2026-11-13 (Front 44): deitar ficou em 0,45 s, abaixo do teto de 0,6 s
	near(
		SoldierAnims.fadeTime("stand", "prone"),
		math.min(Movement.STANCE_TIME["stand>prone"], SoldierAnims.FADE_PRONE_MAX),
		1e-9
	)
	assert(SoldierAnims.fadeTime("stand", "prone") <= 0.6)
	near(SoldierAnims.fadeTime("stand", "prone", true), Movement.DIVE_TIME, 1e-9)
	near(SoldierAnims.fadeTime("crouch", "crouch"), SoldierAnims.FADE_IDLE, 1e-9)
	near(SoldierAnims.reloadSpeed(CLIPS.recarregar.length), 1, 1e-9)
	near(SoldierAnims.reloadSpeed(1.2), 2, 1e-9)
end)

local function src(path: string): string
	return fs.readFile("src/" .. path)
end

test("valores gravados nos clipes ainda batem com o código (senão: regravar no tools/anim)", function()
	local B = SoldierAnims.BAKED
	local ps = src("ServerScriptService/Modules/PostureService.luau")
	-- D-98: o servidor usa os valores da gravação vezes SCALE (corpo de 2 m); 4 casas no código
	local dc, dp = string.match(ps, "local DROP = { crouch = ([%d.]+), prone = ([%d.]+) }")
	assert(dc and dp, "DROP no PostureService")
	near(tonumber(dc) :: number, B.drop.crouch * SC, 1e-3, "PostureService.DROP.crouch mudou")
	near(tonumber(dp) :: number, B.drop.prone * SC, 1e-3, "PostureService.DROP.prone mudou")
	local mh = tonumber(string.match(ps, "local MIN_HIP = ([%d.]+)"))
	near(mh :: number, B.minHip * SC, 1e-3, "MIN_HIP mudou")
	local py, pp = string.match(ps, "CFrame%.new%(0, (%-?[%d.]+), 0%) %* CFrame%.Angles%(math%.rad%((%-?%d+)%), 0, 0%)")
	assert(py and pp, "PRONE_ROOT no PostureService")
	near(tonumber(py) :: number, B.proneRoot.y * SC, 1e-3, "PRONE_ROOT mudou")
	assert(tonumber(pp) == B.proneRoot.pitchDeg, "PRONE_ROOT: giro mudou")
	-- a pega com que os clipes foram gravados (ArmIK.HOLDS.rifle). 2026-11-13: em jogo a arma vai na
	-- pose do Front 44 (Shared/Pegada3P) e os braços pelo IK depois do Animator, então a pega gravada só
	-- vale para os clipes; se ela mudar, regravar
	local h = B.holdStand
	local r = ArmIK.HOLDS.rifle
	assert(r[1] == h.x and r[2] == h.y and r[3] == h.z and r[4] == h.yawDeg and r[5] == h.pitchDeg, "HOLD_STAND mudou")
	local fsv = src("ServerScriptService/Modules/FieldService.luau")
	assert(string.find(fsv, "local THROW_S = " .. tostring(B.throwS), 1, true), "THROW_S mudou")
	assert(string.find(fsv, "local RELEASE_S = 0.4", 1, true), "a granada sai em 0,4 s")
end)

local DIR = "assets/mocap/soldado/"
test("clipes gerados (se existirem) batem com a tabela e o .rbxm", function()
	local found = 0
	for name, c in CLIPS do
		if fs.isFile(DIR .. name .. ".json") then
			found += 1
			local d = serde.decode("json", fs.readFile(DIR .. name .. ".json"))
			near(d.duracao, c.length, 1e-3, name .. " duração")
			near(d.velocidade_m_s, c.speed, 1e-3, name .. " velocidade")
			assert(d.laco == c.loop and d.postura == c.stance, name .. " laço/postura")
			if c.cycles > 0 and name ~= "rastejar" then
				assert(d.ciclos == c.cycles, name .. " ciclos")
			end
			assert((d.escorregamento_max_cm or 0) < 0.5, name .. " escorrega")
			if fs.isFile(DIR .. name .. ".rbxm") then
				local k = roblox.deserializeModel(fs.readFile(DIR .. name .. ".rbxm"))[1] :: any
				assert(k.ClassName == "KeyframeSequence" and k.Loop == c.loop, name .. " rbxm")
				near(k.AuthoredHipHeight, d.authoredHipHeight, 1e-3, name .. " AuthoredHipHeight")
				local last = 0
				for _, kf in k:GetChildren() do
					last = math.max(last, kf.Time)
				end
				near(last, c.length, 1e-3, name .. " último quadro")
			end
		end
	end
	if found == 0 then
		print("       (sem assets/mocap/soldado: rode tools/anim/retarget.py e kfs.luau)")
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
