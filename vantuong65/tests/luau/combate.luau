--!strict
-- Combate (D-107; pedidos do dono: "os tiros não estão acertando", "concerte o hitbox dos
-- personagens", "quero 3 ou 4 tiros para morrer", "faça o jogo mais difícil de morrer", "melhore o
-- áudio das armas", "faça o jogo mais fast paced").
-- 1. Caixas de acerto (Shared/Hitbox): raio x caixa, cabeça de bloco pela malha, capacete e colete,
--    primeira caixa no caminho, candidatos perto da linha do tiro.
-- 2. Aviso do cliente (Combat_Claim): ponto na trajetória da semente e folga até o alvo.
-- 3. Dano (Shared/Medical.shotDamage / applyShot): tiros até cair por arma, zona e distância
--    (imprime a tabela que está na D-107), caído, cabeça, sangramento.
-- 4. Som (Shared/SomArmas) e recarga mais curta.
-- Uso, a partir de vantuong65/: lune run tests/luau/combate.luau
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local S = "../../src/ReplicatedStorage/Shared/"
local Hitbox = require(S .. "Hitbox") :: any
local Ballistics = require(S .. "Ballistics") :: any
local Medical = require(S .. "Medical") :: any
local Weapons = require(S .. "Weapons") :: any
local SomArmas = require(S .. "SomArmas") :: any
local Corpo = require(S .. "Corpo") :: any

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

local I = Hitbox.IDENTITY
local M = Hitbox.M

-- ===== 0. a causa: o servidor recusava todo tiro de jogador =====
test("rede: relógio (hora do servidor) e semente (2^32) do tiro passam na conferência do servidor", function()
	local Rng = require(S .. "Rng") :: any
	-- a conferência de antes (CombatService.num): |v| < 1e7
	local function old(v: number): boolean
		return math.abs(v) < 1e7
	end
	local now = 1.79e9 -- workspace:GetServerTimeNow() em 2026 (época Unix, s)
	assert(not old(now), "a regra antiga recusava o relógio de qualquer tiro")
	local rng = Rng.new(12345)
	local oldOk, newOk = 0, 0
	for _ = 1, 1000 do
		local seed = rng:nextU32() -- WeaponController: seedRng:nextU32()
		oldOk += if old(seed) then 1 else 0
		newOk += if Ballistics.seedOf(seed) then 1 else 0
	end
	print(string.format("       (sementes aceitas: antes %d de 1000, agora %d)", oldOk, newOk))
	assert(newOk == 1000, "semente recusada")
	assert(Ballistics.clockOf(now) == now and Ballistics.clockOf(now + 0.016) ~= nil, "relógio")
	assert(Ballistics.clockOf(0 / 0) == nil and Ballistics.clockOf(math.huge) == nil, "NaN e infinito")
	assert(Ballistics.clockOf("1") == nil, "texto")
	assert(Ballistics.seedOf(-1) == nil and Ballistics.seedOf(2 ^ 32) == nil and Ballistics.seedOf(1.5) == nil)
	assert(Ballistics.seedOf(0) == 0 and Ballistics.seedOf(2 ^ 32 - 1) == 2 ^ 32 - 1)
end)

-- ===== 1. caixas =====
test("caixa: o raio entra, erra, começa dentro e respeita o giro do CFrame do Roblox", function()
	local b = Hitbox.new(0, 0, 0, I, 2, 2, 2, "torso", "UpperTorso")
	near(Hitbox.segment(-5, 0, 0, 5, 0, 0, b), 0.4, 1e-9, "entra em x = -1")
	assert(Hitbox.segment(-5, 1.5, 0, 5, 1.5, 0, b) == nil, "passa por cima")
	assert(Hitbox.segment(0, 0, 0, 5, 0, 0, b) == 0, "começa dentro")
	assert(Hitbox.segment(-5, 0, 0, -2, 0, 0, b) == nil, "para antes")
	-- caixa comprida (braço) girada 45° em Y, com a rotação do CFrame do Roblox
	local cf = roblox.CFrame.new(10, 3, -4) * roblox.CFrame.Angles(0, math.rad(45), 0)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local arm = Hitbox.new(x, y, z, { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, 4, 1, 1, "arm", "LeftUpperArm")
	local tip = cf:PointToWorldSpace(roblox.Vector3.new(1.8, 0, 0)) -- dentro, perto da ponta
	local out = cf:PointToWorldSpace(roblox.Vector3.new(0, 0, 0.8)) -- fora da espessura
	assert(Hitbox.segment(tip.X, tip.Y + 5, tip.Z, tip.X, tip.Y - 5, tip.Z, arm), "raio vertical na ponta")
	assert(Hitbox.segment(out.X, out.Y + 5, out.Z, out.X, out.Y - 5, out.Z, arm) == nil, "ao lado")
end)

test("cabeça de bloco (D-102): a caixa é a cabeça que se vê, não a peça 2 x 1 x 1", function()
	local k = Corpo.BLOCK_SCALE
	local sx, sy, sz = 2 * k, 1 * k, 1 * k -- peça Head do R15 de bloco na escala do soldado
	local hx, hy, hz = Hitbox.headSize(sx, sy, sz, false)
	near(hx, 1.25 * k, 1e-9, "cubo pela malha")
	assert(hx == hy and hy == hz, "cubo")
	local p = Hitbox.PAD.head
	local head = Hitbox.new(0, 0, 0, I, hx * p, hy * p, hz * p, "head", "Head")
	local part = Hitbox.new(0, 0, 0, I, sx, sy, sz, "head", "Head") -- o raio de antes batia nisto
	-- tiro de frente no alto da testa (0,85 stud acima do centro): antes passava por cima
	local yTop = 0.85
	assert(Hitbox.segment(0, yTop, -10, 0, yTop, 10, head), "alto da cabeça pega")
	assert(Hitbox.segment(0, yTop, -10, 0, yTop, 10, part) == nil, "a peça de antes não tinha o alto")
	-- tiro ao lado da cabeça (1,2 stud): a peça larga pegava, a cabeça não
	assert(Hitbox.segment(1.2, 0, -10, 1.2, 0, 10, part), "a peça de antes pegava ao lado")
	assert(Hitbox.segment(1.2, 0, -10, 1.2, 0, 10, head) == nil, "ao lado da cabeça é tiro errado")
	print(
		string.format(
			"       (cabeça: peça %.2f x %.2f x %.2f studs; caixa %.2f studs de lado = %.2f m)",
			sx,
			sy,
			sz,
			hx * p,
			hx * p * M
		)
	)
	-- cabeça em MeshPart (corpo "man"): o tamanho dela
	local mx, my, mz = Hitbox.headSize(1.2, 1.4, 1.3, true)
	assert(mx == 1.2 and my == 1.4 and mz == 1.3)
end)

-- personagem de mentira com as peças do Roblox (Lune): tronco, cabeça, braço, capacete e colete
local function soldier(): any
	local k = Corpo.BLOCK_SCALE
	local m = roblox.Instance.new("Model")
	local function part(name: string, size: any, pos: any, class: string?)
		local p = roblox.Instance.new(class or "Part")
		p.Name = name
		p.Size = size
		p.CFrame = roblox.CFrame.new(pos)
		p.Parent = m
		return p
	end
	part("HumanoidRootPart", roblox.Vector3.new(2, 2, 1) * k, roblox.Vector3.new(0, 0, 0))
	part("UpperTorso", roblox.Vector3.new(2, 1.6, 1) * k, roblox.Vector3.new(0, 0.6 * k, 0))
	part("LowerTorso", roblox.Vector3.new(2, 0.4, 1) * k, roblox.Vector3.new(0, -0.4 * k, 0))
	part("Head", roblox.Vector3.new(2, 1, 1) * k, roblox.Vector3.new(0, 1.95 * k, 0))
	part("LeftUpperArm", roblox.Vector3.new(1, 1.2, 1) * k, roblox.Vector3.new(-1.5 * k, 0.8 * k, 0))
	local helmet = roblox.Instance.new("Model")
	helmet.Name = "Gear_us_m1_helmet"
	local shell = roblox.Instance.new("Part")
	shell.Size = roblox.Vector3.new(2.1, 1.2, 2.3)
	shell.CFrame = roblox.CFrame.new(0, 1.95 * k + 0.9, 0)
	shell.Parent = helmet
	helmet.Parent = m
	local vest = roblox.Instance.new("Model")
	vest.Name = "Gear_us_m1955_vest"
	local v = roblox.Instance.new("Part")
	v.Size = roblox.Vector3.new(3.2, 2.5, 1.8)
	v.CFrame = roblox.CFrame.new(0, 0.6 * k, 0)
	v.Parent = vest
	vest.Parent = m
	local other = roblox.Instance.new("Model") -- arma na mão: não é corpo
	other.Name = "Weapon"
	other.Parent = m
	return m
end

test("fromModel: peças do corpo, capacete (cabeça) e colete (tronco); a raiz e a arma ficam fora", function()
	local boxes = Hitbox.fromModel(soldier())
	local zones: { [string]: number } = {}
	local parts: { [string]: boolean } = {}
	for _, b in boxes do
		zones[b.zone] = (zones[b.zone] or 0) + 1
		parts[b.part] = true
	end
	assert(#boxes == 6, "caixas: " .. #boxes)
	assert(zones.head == 2 and zones.torso == 3 and zones.arm == 1, "zonas")
	assert(not parts.HumanoidRootPart, "a raiz não é caixa")
	-- o capacete leva o aviso para a peça Head (o servidor confere a distância até ela)
	local helmet = nil -- a caixa de cabeça mais alta é a do capacete
	for _, b in boxes do
		if b.zone == "head" and (not helmet or b.y > helmet.y) then
			helmet = b
		end
	end
	assert(helmet and helmet.part == "Head", "capacete -> Head")
	-- tiro rente ao topo do capacete (acima da cabeça): pega a cabeça
	local yHelmet = helmet.y + 0.4
	local f, b = Hitbox.first(0, yHelmet, -20, 0, yHelmet, 20, boxes)
	assert(f and b and b.zone == "head", "capacete pega como cabeça")
end)

test("primeira caixa no caminho: o braço à frente do tronco", function()
	local boxes = Hitbox.fromModel(soldier())
	local k = Corpo.BLOCK_SCALE
	-- tiro da esquerda para a direita na altura do ombro: o braço esquerdo (x < 0) vem antes do tronco
	local y = 0.8 * k
	local _, b = Hitbox.first(-30, y, 0, 30, y, 0, boxes)
	assert(b and b.zone == "arm", "braço antes do tronco: " .. tostring(b and b.zone))
	local _, b2 = Hitbox.first(30, y, 0, -30, y, 0, boxes)
	assert(b2 and b2.zone == "torso", "do outro lado, o tronco: " .. tostring(b2 and b2.zone))
end)

test("candidatos: soldado a até 9 studs da linha do tiro (mais a queda da bala longe)", function()
	assert(Hitbox.nearRay(100, 3, 0, 1, 0, 0, 853, 0), "3 studs da linha")
	assert(not Hitbox.nearRay(100, 12, 0, 1, 0, 0, 853, 0), "12 studs da linha")
	assert(not Hitbox.nearRay(-30, 0, 0, 1, 0, 0, 853, 0), "atrás de quem atira")
	-- a 600 m a bala de 7,62x39 cai ~4 m: o soldado 10 studs abaixo da linha ainda é candidato
	assert(Hitbox.nearRay(600 / M, -10, 0, 1, 0, 0, 735, 0), "queda longe")
	assert(Hitbox.nearRay(100, 20, 0, 1, 0, 0, 853, Hitbox.CLAIM_MAX), "folga do aviso")
end)

-- ===== 2. aviso do cliente =====
-- trajetória gravada como no Hitbox.trace (studs)
local function pathOf(id: string, seed: number, untilM: number): ({ number }, { number })
	local path, speed = {}, {}
	Ballistics.trace(
		{ ox = 0, oy = 1.5, oz = 0, dx = 1, dy = 0.002, dz = 0.01, weaponId = id, seed = seed, dt = Ballistics.SHOT_DT },
		function(ax: number, ay: number, az: number, bx: number, by: number, bz: number): any?
			if #path == 0 then
				table.insert(path, ax / M)
				table.insert(path, ay / M)
				table.insert(path, az / M)
			end
			table.insert(path, bx / M)
			table.insert(path, by / M)
			table.insert(path, bz / M)
			local dl = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
			table.insert(speed, dl / Ballistics.SHOT_DT)
			if bx >= untilM then
				return { x = bx, y = by, z = bz }
			end
			return nil
		end
	)
	return path, speed
end

test("aviso: o ponto tem de estar na trajetória da semente (até 1 stud)", function()
	local path, speed = pathOf("m14", 7, 300)
	-- ponto no meio do 20º segmento
	local j = 19 * 3
	local px, py, pz = (path[j + 1] + path[j + 4]) / 2, (path[j + 2] + path[j + 5]) / 2, (path[j + 3] + path[j + 6]) / 2
	local d, seg = Hitbox.near(path, px, py, pz)
	assert(d < 1e-6 and seg == 20, string.format("na trajetória: %.4f, segmento %s", d, tostring(seg)))
	near(speed[seg], 853 * 0.9, 853 * 0.12, "velocidade no segmento")
	local d2 = Hitbox.near(path, px, py + 2, pz)
	assert(d2 > Hitbox.PATH_TOL, "2 studs acima: fora")
	-- outra semente (dispersão de 3 MOA) passa a mais de 1 stud a 300 m: o aviso não serve para outro tiro
	local other = pathOf("m14", 99, 300)
	local n = #other
	local dEnd = Hitbox.near(path, other[n - 2], other[n - 1], other[n])
	print(string.format("       (M14 a 300 m: outra semente passa a %.2f studs)", dEnd))
	-- depois do impacto (a trajetória gravada acaba nele): fora
	local last = #path
	local dAfter = Hitbox.near(path, path[last - 2] + 10, path[last - 1], path[last])
	assert(dAfter > Hitbox.PATH_TOL, "depois do fim da trajetória")
end)

test("aviso: folga até a peça no servidor cresce com a velocidade do alvo, com teto", function()
	near(Hitbox.tolerance(3, 0), 4.5, 1e-9, "parado")
	near(Hitbox.tolerance(3, 15), 12, 1e-9, "andando rápido (4 m/s)")
	near(Hitbox.tolerance(3, 60), Hitbox.CLAIM_MAX, 1e-9, "teto")
	assert(Hitbox.CLAIM_S >= 0.5 and Hitbox.CLAIM_S <= 2, "janela do aviso")
end)

-- ===== 3. dano =====
-- energia que sobra (fração da de boca) a `d` m, pela balística do jogo
local fracCache: { [string]: number } = {}
local function fracAt(id: string, d: number): number
	local key = id .. ":" .. d
	if fracCache[key] then
		return fracCache[key]
	end
	local wp = Weapons.get(id)
	local hit = Ballistics.trace(
		{ ox = 0, oy = 0, oz = 0, dx = 1, dy = 0, dz = 0, weaponId = id, seed = 1, maxTime = 4 },
		function(ax: number, ay: number, az: number, bx: number, _by: number, _bz: number): any?
			if bx >= d then
				return { x = d, y = ay, z = az }
			end
			return nil
		end
	)
	local f = if hit then hit.energy / Ballistics.energy(wp.bulletMassG, wp.muzzleVelocity) else 0
	fracCache[key] = f
	return f
end

-- tiros até cair (ou morrer), de vida cheia, na mesma zona e distância
local function shots(id: string, zone: string, d: number, health: number?): number
	local wp = Weapons.get(id)
	local s = Medical.new(false, (health or 100) / 100)
	local dmg = Medical.shotDamage(Weapons.damageOf(wp), zone, fracAt(id, d))
	for n = 1, 30 do
		Medical.applyShot(s, zone, dmg, 0.9, 0)
		if s.downedAt or s.dead then
			return n
		end
	end
	return 99
end

local DIST = { 10, 50, 100, 200, 300, 400 }

test("tabela: tiros até cair por arma, zona e distância (D-107)", function()
	print("       arma     zona    " .. table.concat(
		(function()
			local t = {}
			for _, d in DIST do
				table.insert(t, string.format("%4dm", d))
			end
			return t
		end)(),
		" "
	))
	for _, wp in Weapons.list do
		if wp.enabled and wp.kind ~= "launcher" then
			for _, zone in { "torso", "head", "arm" } do
				local row = {}
				for _, d in DIST do
					table.insert(row, string.format("%5d", shots(wp.id, zone, d)))
				end
				print(string.format("       %-8s %-7s %s", wp.id, zone, table.concat(row, " ")))
			end
		end
	end
end)

test("fuzil no tronco: 3 a 4 tiros de 10 a 400 m; 3 de perto (pedido do dono)", function()
	for _, id in { "m14", "type56", "sks" } do
		for _, d in DIST do
			local n = shots(id, "torso", d)
			assert(n >= 3 and n <= 4, string.format("%s a %d m: %d tiros", id, d, n))
		end
		assert(shots(id, "torso", 50) == 3, id .. ": 3 tiros de perto")
	end
end)

test("metralhadora 4 no tronco (até 300 m), pistola 4 a 5 (até 50 m), precisão 2 (até 200 m)", function()
	for _, id in { "m60", "rpd" } do
		for _, d in { 10, 50, 100, 200, 300 } do
			assert(shots(id, "torso", d) == 4, string.format("%s a %d m: %d", id, d, shots(id, "torso", d)))
		end
	end
	for _, id in { "m1911", "type54" } do
		for _, d in { 10, 25, 50 } do
			local n = shots(id, "torso", d)
			assert(n >= 4 and n <= 5, string.format("%s a %d m: %d", id, d, n))
		end
	end
	for _, id in { "m70", "mosin" } do
		for _, d in { 10, 100, 200 } do
			assert(shots(id, "torso", d) == 2, string.format("%s a %d m: %d", id, d, shots(id, "torso", d)))
		end
		assert(shots(id, "torso", 400) <= 3, id .. " a 400 m")
	end
end)

test("cabeça menos tiros (fuzil e precisão matam com 1 até 300 m; pistola 2), membro mais (5+)", function()
	for _, id in { "m14", "type56", "sks", "m70", "mosin" } do
		for _, d in { 10, 100, 200, 300 } do
			assert(shots(id, "head", d) == 1, string.format("%s cabeça a %d m", id, d))
		end
	end
	for _, id in { "m60", "rpd" } do
		for _, d in { 10, 100, 200 } do
			assert(shots(id, "head", d) == 1, string.format("%s cabeça a %d m", id, d))
		end
	end
	for _, id in { "m1911", "type54" } do
		assert(shots(id, "head", 10) == 2, id .. ": pistola na cabeça = 2")
	end
	for _, id in { "m14", "type56", "sks", "m60", "rpd" } do
		for _, d in DIST do
			assert(shots(id, "arm", d) >= 5, string.format("%s braço a %d m: %d", id, d, shots(id, "arm", d)))
			assert(shots(id, "leg", d) >= 5, string.format("%s perna a %d m", id, d))
		end
	end
end)

test("cabeça: a bala que mata na hora não deixa caído; a que não mata fere e soma", function()
	local s = Medical.new()
	assert(Medical.applyShot(s, "head", 90, 0.5, 0) == "killed" and s.dead and not s.downedAt)
	local p = Medical.new()
	assert(Medical.applyShot(p, "head", 62.5, 0.5, 0) == "wounded" and p.health < 40)
	assert(Medical.applyShot(p, "head", 62.5, 0.5, 0) == "killed", "segunda na cabeça mata")
end)

test("caído: tiro de fuzil mata; pistola de longe não (downedKill)", function()
	local s = Medical.new()
	for _ = 1, 3 do
		Medical.applyShot(s, "torso", 36, 0.5, 0)
	end
	assert(s.downedAt and not s.dead, "3 de fuzil: caído")
	assert(Medical.applyShot(s, "torso", Medical.SHOT.downedKill - 1, 0.5, 1) == "downed", "fraco não mata")
	assert(Medical.applyShot(s, "leg", 21, 0.5, 1) == "killed" and s.dead, "fuzil mata o caído")
end)

test("vantagem de vida (1,12): fuzil no tronco passa a 4 tiros de perto", function()
	for _, id in { "m14", "type56" } do
		assert(shots(id, "torso", 50, 112) == 4, id)
	end
end)

test("applyHit: sem tiro marcado segue por energia (estilhaço, faca); com nextShot usa o dano e limpa", function()
	local a = Medical.new()
	assert(Medical.applyHit(a, "torso", 3400, 0.5, 0) == "downed", "estilhaço/veículo: energia derruba")
	local b = Medical.new()
	Medical.nextShot = 36
	assert(Medical.applyHit(b, "torso", 3400, 0.5, 0) == "wounded" and b.health == 64, "bala: 36 de dano")
	assert(Medical.nextShot == nil, "consumido")
	local c = Medical.new()
	assert(Medical.applyHit(c, "torso", 3400, 0.5, 0) == "downed", "o próximo volta à regra por energia")
end)

test("membro: ferida leve, artéria só com fuzil (20%); sangrar dá tempo do curativo", function()
	local s = Medical.new()
	Medical.applyShot(s, "leg", 23.4, 0.9, 0)
	assert(s.wounds[1].level == "light" and s.legImpaired, "perna: leve")
	local t = Medical.new()
	Medical.applyShot(t, "arm", 23.4, 0.1, 0)
	assert(t.wounds[1].level == "arterial" and t.armImpaired, "fuzil com roll < 0,2: artéria")
	local p = Medical.new()
	Medical.applyShot(p, "arm", 16, 0.1, 0)
	assert(p.wounds[1].level == "light", "pistola não abre artéria")
	-- dois tiros de fuzil no tronco: 28 de vida, sangrando 0,5/s -> ~56 s até cair
	local q = Medical.new()
	Medical.applyShot(q, "torso", 36, 0.5, 0)
	Medical.applyShot(q, "torso", 36, 0.5, 0)
	local secs = 0
	while not q.downedAt and secs < 600 do
		secs += 1
		Medical.tick(q, 1, secs)
	end
	print(string.format("       (dois tiros de fuzil no tronco: cai em %d s sem curativo)", secs))
	assert(secs >= 30 and secs <= 120, "tempo de sangrar")
	local r = Medical.new()
	Medical.applyShot(r, "torso", 36, 0.5, 0)
	Medical.applyShot(r, "torso", 36, 0.5, 0)
	assert(Medical.bandage(r) and Medical.bleedRate(r) == 0, "curativo estanca")
end)

test("toda arma tem dano > 0; precisão com dano próprio", function()
	for _, wp in Weapons.list do
		assert(Weapons.damageOf(wp) > 0, wp.id)
	end
	assert(Weapons.get("m70").damage and Weapons.get("mosin").damage, "precisão")
	near(Medical.shotDamage(36, "torso", 1), 36, 1e-9)
	near(Medical.shotDamage(36, "torso", 0.5), 36 * 0.85, 1e-9)
	near(Medical.shotDamage(36, "torso", 0), 36 * 0.4, 1e-9)
	near(Medical.shotDamage(36, "arm", 1), 36 * Medical.SHOT.zone.arm, 1e-9)
end)

-- ===== 4. som e ritmo =====
test("som: toda arma ligada tem disparo; camadas por distância sem buraco; estalo e zunido", function()
	for _, wp in Weapons.list do
		if wp.enabled then
			local a = SomArmas.arma(wp.id, wp.kind)
			local def = SomArmas.LIB[a.tiro]
			assert(def and def.id > 0 and def.vol > 0 and a.pitch > 0, wp.id)
		end
	end
	assert(SomArmas.arma("arma_nova", "pistol").tiro == "pistola", "arma nova pela classe")
	for _, def in SomArmas.LIB do
		assert(def.id > 0 and def.vol > 0, "id")
	end
	-- perto domina de perto, longe domina de longe, e alguma camada sempre toca até 2.400 m
	local n0, m0, f0 = SomArmas.camadas(5)
	assert(n0 == 1 and m0 == 0 and f0 == 0, "perto")
	local _, _, f1 = SomArmas.camadas(1000)
	local n1 = SomArmas.camadas(1000)
	assert(f1 > 0 and n1 == 0, "longe")
	for d = 0, 2400, 10 do
		local a, b, c = SomArmas.camadas(d)
		assert(a + b + c >= 0.1, "buraco a " .. d .. " m")
	end
	assert(SomArmas.agudos(300, "mata") < SomArmas.agudos(300, "aberto"), "mata abafa mais")
	-- bala passando
	assert(SomArmas.passagem(5, 700, 349) == "bala_estalo", "supersônica a 5 m")
	assert(SomArmas.passagem(5, 250, 349) == "bala_zunido", ".45 a 5 m")
	assert(SomArmas.passagem(10, 700, 349) == nil, "longe")
	-- lugar de quem ouve
	assert(SomArmas.lugar(0, 8, false, false, false) == "aberto")
	assert(SomArmas.lugar(6, 8, false, false, false) == "mata")
	assert(SomArmas.lugar(2, 8, true, false, false) == "mata", "copa em cima")
	assert(SomArmas.lugar(4, 8, false, true, false) == "fechado", "vila")
	assert(SomArmas.lugar(0, 8, false, false, true) == "tunel")
	for _, l in { "aberto", "mata", "fechado", "tunel" } do
		assert(SomArmas.CAUDA[l], "cauda de " .. l)
	end
	assert(SomArmas.LUGAR == "aberto")
end)

test("fast paced: recarga mais curta (fuzil 2,4 s, metralhadora 5,5 s, pistola 2,0 s; precisão 5 s)", function()
	near(Weapons.reloadTime(Weapons.get("m14")), 2.4, 1e-9)
	near(Weapons.reloadTime(Weapons.get("type56")), 2.4, 1e-9)
	near(Weapons.reloadTime(Weapons.get("m60")), 5.5, 1e-9)
	near(Weapons.reloadTime(Weapons.get("m1911")), 2.0, 1e-9)
	near(Weapons.reloadTime(Weapons.get("m70")), 5.0, 1e-9)
	assert(Weapons.interval(Weapons.get("m70"), "bolt") < 1.0, "ferrolho da M70")
	assert(Ballistics.PASS.Bamboo and Ballistics.PASS.Thatch and Ballistics.PASS.Canvas, "PASS")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
