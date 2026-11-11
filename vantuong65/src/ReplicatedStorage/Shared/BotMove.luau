--!strict
-- Movimento dos bots como o de um jogador (D-90; pedido do dono, 2026-11-11: "faça a movimentação
-- dos bots linear como se fossem jogadores reais"). Módulo PURO, testado no Lune
-- (tests/luau/botsmov.luau); o runtime é o Modules/BotLocomotion.
--   - caminho como polilinha seguida por perseguição pura (ponto ~0,6 s à frente): sem zigue-zague
--     entre pontos e sem "anda e para" nas pontas dos trechos;
--   - velocidade com a mesma inércia do jogador (Movement.accelStep: 7 m/s² acelerando, 10 m/s²
--     freando), freada confortável ao chegar e na curva fechada;
--   - corpo que vira com velocidade limitada pelo passo (correndo vira devagar);
--   - rastro do líder e lugar de cada um na coluna ou na cunha;
--   - detector de "preso" (anda muito menos que o pedido).
-- Unidades: posições em studs; velocidades em m/s; ângulos em radianos (rumo do Roblox: o
-- LookVector de CFrame.Angles(0, yaw, 0) é (-sin yaw, 0, -cos yaw)).
local Movement = require(script and (script :: any).Parent.Movement or "./Movement") :: any
local BotBrain = require(script and (script :: any).Parent.BotBrain or "./BotBrain") :: any

local BotMove = {}
local STUD = 0.28

---------------------------------------------------------------------------------------------
-- Ângulos
---------------------------------------------------------------------------------------------

function BotMove.wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Rumo (yaw do Roblox) que olha para a direção (dx, dz).
function BotMove.yawTo(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

-- Gira de yaw para target sem passar de maxRate (rad/s).
function BotMove.yawStep(yaw: number, target: number, maxRate: number, dt: number): number
	local d = BotMove.wrap(target - yaw)
	local step = maxRate * dt
	if math.abs(d) <= step then
		return target
	end
	return BotMove.wrap(yaw + (if d > 0 then step else -step))
end

-- Giro do corpo (rad/s) pelo passo
function BotMove.turnRate(gait: string, aiming: boolean): number
	local M = BotBrain.MOVE
	if aiming then
		return math.rad(M.aimTurnDegS)
	end
	return math.rad(M.turnDegS[gait] or M.turnDegS.jog)
end

---------------------------------------------------------------------------------------------
-- Caminho (polilinha em studs)
---------------------------------------------------------------------------------------------

export type Point = { x: number, z: number, y: number?, jump: boolean? }
export type Path = {
	x: { number },
	z: { number },
	y: { number },
	jump: { boolean },
	cum: { number }, -- comprimento acumulado até cada ponto
	n: number,
	length: number,
}

-- Tira pontos quase em linha (deixa os de pulo) e os colados (< minGap studs).
function BotMove.simplify(pts: { Point }, tolDeg: number, minGap: number): { Point }
	local n = #pts
	if n <= 2 then
		return pts
	end
	local out: { Point } = { pts[1] }
	local cosTol = math.cos(math.rad(tolDeg))
	for i = 2, n - 1 do
		local a, b, c = out[#out], pts[i], pts[i + 1]
		local keep = b.jump == true
		if not keep then
			local ux, uz = b.x - a.x, b.z - a.z
			local vx, vz = c.x - b.x, c.z - b.z
			local lu, lv = math.sqrt(ux * ux + uz * uz), math.sqrt(vx * vx + vz * vz)
			if lu >= minGap and lv > 1e-6 and (ux * vx + uz * vz) / (lu * lv) < cosTol then
				keep = true
			end
		end
		if keep then
			table.insert(out, b)
		end
	end
	table.insert(out, pts[n])
	return out
end

function BotMove.path(pts: { Point }): Path
	local p: Path = { x = {}, z = {}, y = {}, jump = {}, cum = {}, n = 0, length = 0 }
	local total = 0
	for i, q in pts do
		if i > 1 then
			local dx, dz = q.x - pts[i - 1].x, q.z - pts[i - 1].z
			total += math.sqrt(dx * dx + dz * dz)
		end
		p.x[i], p.z[i], p.y[i], p.jump[i], p.cum[i] = q.x, q.z, q.y or 0, q.jump == true, total
	end
	p.n = #pts
	p.length = total
	return p
end

-- Projeta (x, z) na polilinha a partir do trecho `from` (o bot só anda para a frente): devolve o
-- comprimento s do ponto mais perto, o trecho e a distância até ele.
function BotMove.project(p: Path, x: number, z: number, from: number?): (number, number, number)
	if p.n <= 1 then
		return 0, 1, if p.n == 1 then math.sqrt((p.x[1] - x) ^ 2 + (p.z[1] - z) ^ 2) else math.huge
	end
	local bestS, bestI, bestD2 = 0, 1, math.huge
	local i0 = math.clamp(from or 1, 1, p.n - 1)
	-- janela: do trecho atual até 8 trechos à frente (o bot não pula para o outro lado do caminho)
	for i = i0, math.min(p.n - 1, i0 + 8) do
		local ax, az = p.x[i], p.z[i]
		local bx, bz = p.x[i + 1], p.z[i + 1]
		local dx, dz = bx - ax, bz - az
		local l2 = dx * dx + dz * dz
		local t = if l2 > 1e-9 then math.clamp(((x - ax) * dx + (z - az) * dz) / l2, 0, 1) else 0
		local px, pz = ax + dx * t, az + dz * t
		local d2 = (px - x) ^ 2 + (pz - z) ^ 2
		if d2 < bestD2 then
			bestD2, bestI = d2, i
			bestS = p.cum[i] + t * math.sqrt(l2)
		end
	end
	return bestS, bestI, math.sqrt(bestD2)
end

-- Ponto no comprimento s (preso às pontas) e o trecho.
function BotMove.at(p: Path, s: number): (number, number, number, number)
	if p.n == 0 then
		return 0, 0, 0, 1
	elseif p.n == 1 or s <= 0 then
		return p.x[1], p.z[1], p.y[1], 1
	elseif s >= p.length then
		return p.x[p.n], p.z[p.n], p.y[p.n], math.max(p.n - 1, 1)
	end
	local i = 1
	while i < p.n - 1 and p.cum[i + 1] < s do
		i += 1
	end
	local seg = p.cum[i + 1] - p.cum[i]
	local t = if seg > 1e-9 then (s - p.cum[i]) / seg else 0
	return p.x[i] + (p.x[i + 1] - p.x[i]) * t, p.z[i] + (p.z[i + 1] - p.z[i]) * t, p.y[i] + (p.y[i + 1] - p.y[i]) * t, i
end

-- Maior curva (rad) entre trechos que começam em [s, s + ahead].
function BotMove.cornerAhead(p: Path, s: number, ahead: number): number
	local worst = 0
	for i = 2, p.n - 1 do
		if p.cum[i] >= s and p.cum[i] <= s + ahead then
			local ux, uz = p.x[i] - p.x[i - 1], p.z[i] - p.z[i - 1]
			local vx, vz = p.x[i + 1] - p.x[i], p.z[i + 1] - p.z[i]
			local lu, lv = math.sqrt(ux * ux + uz * uz), math.sqrt(vx * vx + vz * vz)
			if lu > 1e-6 and lv > 1e-6 then
				local c = math.clamp((ux * vx + uz * vz) / (lu * lv), -1, 1)
				worst = math.max(worst, math.acos(c))
			end
		elseif p.cum[i] > s + ahead then
			break
		end
	end
	return worst
end

-- Há pulo (dique, mureta) entre s e s + ahead?
function BotMove.jumpAhead(p: Path, s: number, ahead: number): boolean
	for i = 2, p.n do
		if p.cum[i] > s + ahead then
			return false
		elseif p.cum[i] >= s and p.jump[i] then
			return true
		end
	end
	return false
end

-- Distância à frente (studs) para a perseguição pura, pela velocidade (m/s).
function BotMove.lookahead(speedMps: number): number
	local M = BotBrain.MOVE
	return math.clamp(speedMps * M.lookaheadS, M.lookMinM, M.lookMaxM) / STUD
end

-- Teto de velocidade (m/s) para parar em distM sem passar do ponto, e na curva fechada à frente.
function BotMove.speedCap(want: number, distM: number, cornerRad: number, final: boolean): number
	local M = BotBrain.MOVE
	local v = want
	if final then
		v = math.min(v, math.sqrt(2 * M.stopDecel * math.max(distM - M.arriveM * 0.5, 0)))
	end
	if cornerRad > math.rad(M.cornerDeg) then
		v = math.min(v, math.max(Movement.WALK, want * 0.5))
	end
	return v
end

-- Estado de quem segue um caminho
export type Follow = { s: number, seg: number, done: boolean }

function BotMove.newFollow(): Follow
	return { s = 0, seg = 1, done = false }
end

-- Perseguição pura: direção (unitária) para o ponto à frente no caminho, a velocidade (m/s) com a
-- freada da chegada e da curva, e quanto falta (m). (x, z) em studs; speedNow e want em m/s.
-- final: o fim do caminho é o destino (freia para parar nele); senão, passa reto (trecho seguinte).
function BotMove.follow(
	f: Follow,
	p: Path,
	x: number,
	z: number,
	speedNow: number,
	want: number,
	final: boolean
): (number, number, number, number)
	local M = BotBrain.MOVE
	if p.n == 0 then
		f.done = true
		return 0, 0, 0, 0
	end
	local s, seg = BotMove.project(p, x, z, f.seg)
	f.s, f.seg = s, seg
	local ex, ez = p.x[p.n], p.z[p.n]
	local toEnd = math.sqrt((ex - x) ^ 2 + (ez - z) ^ 2)
	-- destino: o que falta até ele de verdade; ponto de passagem: o que falta no caminho (0 depois
	-- do fim, para o trecho seguinte ser pedido)
	local leftM = (if final then math.max(p.length - s, toEnd) else math.max(p.length - s, 0)) * STUD
	if final and leftM <= M.arriveM then
		f.done = true
		return 0, 0, 0, leftM
	end
	local look = BotMove.lookahead(math.max(speedNow, want * 0.5))
	local tx, tz = BotMove.at(p, math.min(s + look, p.length))
	if s + look >= p.length then
		tx, tz = ex, ez
		if not final and p.n >= 2 then
			-- ponto de passagem: segue reto além do fim (o trecho seguinte chega antes); mirar no
			-- fim faria o bot dar meia-volta e girar em volta dele
			local lx, lz = ex - p.x[p.n - 1], ez - p.z[p.n - 1]
			local l = math.sqrt(lx * lx + lz * lz)
			if l > 1e-6 then
				lx, lz = lx / l, lz / l
				local beyond = math.max(0, (x - ex) * lx + (z - ez) * lz) -- quanto já passou do fim
				tx, tz = ex + lx * (beyond + look), ez + lz * (beyond + look)
			end
		end
	end
	local dx, dz = tx - x, tz - z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1e-4 then
		return 0, 0, 0, leftM
	end
	local corner = BotMove.cornerAhead(p, s, M.cornerLookM / STUD)
	local speed = BotMove.speedCap(want, leftM, corner, final)
	return dx / d, dz / d, speed, leftM
end

---------------------------------------------------------------------------------------------
-- Passo do corpo (velocidade com inércia + giro)
---------------------------------------------------------------------------------------------

export type Body = { vx: number, vz: number, yaw: number }
export type Drive = {
	dirX: number, -- direção desejada (unitária ou zero)
	dirZ: number,
	speed: number, -- m/s
	faceYaw: number?, -- mirando: o corpo olha para cá e as pernas andam de lado
	turn: number, -- rad/s
	grip: number, -- 0..1 (lama e arrozal escorregam)
}

-- Um passo: a velocidade vai para a desejada com a aceleração do jogador; o corpo gira para onde
-- anda (ou para onde mira) sem passar do giro do passo. Parado sem mira, não gira.
function BotMove.step(b: Body, d: Drive, dt: number)
	local tx, tz = d.dirX * d.speed, d.dirZ * d.speed
	b.vx, b.vz = Movement.accelStep(b.vx, b.vz, tx, tz, dt, d.grip)
	local want = d.faceYaw
	if want == nil then
		local sp = math.sqrt(b.vx * b.vx + b.vz * b.vz)
		if sp > 0.3 then
			want = BotMove.yawTo(b.vx, b.vz)
		end
	end
	if want ~= nil then
		b.yaw = BotMove.yawStep(b.yaw, want, d.turn, dt)
	end
end

---------------------------------------------------------------------------------------------
-- Preso
---------------------------------------------------------------------------------------------

export type Stuck = { t: number, want: number, got: number }

function BotMove.newStuck(): Stuck
	return { t = 0, want = 0, got = 0 }
end

-- Soma o que devia andar (wantM) e o que andou (gotM). Depois de stuckS, devolve true se andou
-- menos que stuckFrac do pedido (e zera a janela).
function BotMove.stuckStep(s: Stuck, dt: number, wantM: number, gotM: number): boolean
	local M = BotBrain.MOVE
	if wantM <= 1e-3 then
		s.t, s.want, s.got = 0, 0, 0
		return false
	end
	s.t += dt
	s.want += wantM
	s.got += gotM
	if s.t < M.stuckS then
		return false
	end
	local stuck = s.want > 0.6 and s.got < s.want * M.stuckFrac
	s.t, s.want, s.got = 0, 0, 0
	return stuck
end

---------------------------------------------------------------------------------------------
-- Rastro do líder e formação
---------------------------------------------------------------------------------------------

-- Rastro: pontos do líder do mais novo (1) para o mais velho, um a cada `step` studs.
export type Trail = { x: { number }, z: { number }, step: number, max: number }

function BotMove.newTrail(stepStuds: number, maxStuds: number): Trail
	return { x = {}, z = {}, step = stepStuds, max = math.max(2, math.ceil(maxStuds / stepStuds)) }
end

function BotMove.trailPush(t: Trail, x: number, z: number)
	local n = #t.x
	if n > 0 then
		local dx, dz = x - t.x[1], z - t.z[1]
		if dx * dx + dz * dz < t.step * t.step then
			return
		end
	end
	table.insert(t.x, 1, x)
	table.insert(t.z, 1, z)
	if #t.x > t.max then
		table.remove(t.x)
		table.remove(t.z)
	end
end

function BotMove.trailClear(t: Trail)
	table.clear(t.x)
	table.clear(t.z)
end

-- Ponto a `dist` studs atrás do líder, seguindo o rastro (o líder está em hx, hz), e a direção
-- de marcha ali (unitária). Rastro curto: segue a reta para trás do último ponto.
function BotMove.trailBehind(t: Trail, hx: number, hz: number, dist: number): (number, number, number, number)
	local px, pz = hx, hz
	local left = dist
	local dirX, dirZ = 0, -1
	for i = 1, #t.x do
		local qx, qz = t.x[i], t.z[i]
		local dx, dz = px - qx, pz - qz
		local l = math.sqrt(dx * dx + dz * dz)
		if l > 1e-6 then
			dirX, dirZ = dx / l, dz / l
			if l >= left then
				return px - dirX * left, pz - dirZ * left, dirX, dirZ
			end
			left -= l
		end
		px, pz = qx, qz
	end
	return px - dirX * left, pz - dirZ * left, dirX, dirZ
end

-- Lugar do homem `index` (1 = logo atrás do líder): distância para trás e para o lado (m).
-- Coluna ("file"): um atrás do outro. Cunha ("wedge"): alternando direita e esquerda, abrindo.
function BotMove.slot(formation: string, index: number): (number, number)
	local S = BotBrain.SQUAD
	local back = index * S.spacingM
	if formation ~= "wedge" then
		return back, 0
	end
	local rank = (index + 1) // 2
	local side = if index % 2 == 1 then 1 else -1
	return rank * S.spacingM * 0.8, side * rank * S.wedgeSideM
end

-- Coluna na mata, na vila e no riacho; cunha no aberto (arrozal, clareira, capim).
function BotMove.formationFor(open: boolean): string
	return if open then "wedge" else "file"
end

-- Defesa: lugar do homem `index` de `count` num arco virado para o inimigo (rumo axis, rad do
-- Roblox) em volta do objetivo. Devolve o deslocamento (dx, dz) em studs.
function BotMove.defendSlot(index: number, count: number, axisYaw: number, roll: number): (number, number)
	local S = BotBrain.SQUAD
	local arc = math.rad(S.defendArcDeg)
	local t = if count <= 1 then 0.5 else (index - 1) / (count - 1)
	local a = axisYaw + (t - 0.5) * 2 * arc
	local r = (S.defendR[1] + (S.defendR[2] - S.defendR[1]) * math.clamp(roll, 0, 1)) / STUD
	return -math.sin(a) * r, -math.cos(a) * r
end

return BotMove
