--!strict
-- Braços no fuzil sem atravessar o corpo (D-94). Módulo PURO (sem Roblox): o PostureController usa
-- as pegas (HOLD) e os polos de cotovelo daqui, e o teste do Lune (tests/luau/faca.luau) mede a
-- penetração dos braços no tronco numa simulação do R15 com o IK de dois ossos (o IKControl com
-- Pole põe o cotovelo no plano ombro–alvo–polo, do lado do polo).
--
-- Tudo no espaço do UpperTorso (studs; X direita, Y cima, frente −Z). Medidas do R15 em bloco com
-- HeightScale 1,25 (tools/anim/r15.py: juntas do characterR15 do Studio); tamanhos das peças do
-- corpo "Man" aproximados (r15.SIZES), PLACEHOLDER até despejar um soldado no Studio. As peças do
-- braço entram como caixas reduzidas a 80% (a malha "Man" é arredondada; a caixa cheia acusaria
-- penetração nas quinas que não existem).
local ArmIK = {}

export type V = { number }

local S = 1.25
ArmIK.SHOULDER = { R = { 1.0, 0.563 * S, 0 }, L = { -1.0, 0.563 * S, 0 } }
-- osso do braço (pivô do ombro, na quina de dentro da peça, até o cotovelo), no espaço da peça
ArmIK.UPPER = { R = { 0.5, -0.728 * S, 0 }, L = { -0.5, -0.728 * S, 0 } }
ArmIK.UPPER_C1 = { R = { -0.5, 0.394 * S, 0 }, L = { 0.5, 0.394 * S, 0 } } -- ombro na peça
ArmIK.ELBOW_C0 = -0.334 * S -- cotovelo no braço (y)
ArmIK.FORE_C1 = 0.259 * S -- cotovelo no antebraço (y)
ArmIK.FORE = 0.76 * S -- cotovelo -> pulso
ArmIK.HAND = 0.125 * S -- pulso -> centro da mão (o IKControl leva o CENTRO da mão ao alvo)
-- meias-caixas (studs)
ArmIK.HALF = {
	UpperTorso = { 0.92, 0.8 * S, 0.535 },
	LowerTorso = { 0.835, 0.315 * S, 0.52 },
	Head = { 0.5, 0.6, 0.55 },
	UpperArm = { 0.3, 0.55 * S, 0.375 },
	LowerArm = { 0.3, 0.475 * S, 0.31 },
	Hand = { 0.25, 0.225 * S, 0.3 },
}
ArmIK.TORSO_ROUND = 0.22 -- raio das quinas do tronco (o "Man" é arredondado)
ArmIK.ARM_SHRINK = 0.8
-- LowerTorso e cabeça no espaço do UpperTorso (repouso): Waist 0,2/−0,8 e Neck 0,8/−0,5
ArmIK.WAIST = { 0, -0.8 * S, 0 }
ArmIK.LOWER_FROM_WAIST = { 0, -0.2 * S, 0 }
ArmIK.HEAD = { 0, 0.8 * S + 0.5, 0 }

-- ===== pegas (CFrame do pivô da arma, no punho, no UpperTorso) =====
-- {x, y, z, guinada°, arfagem°}: CFrame.new(x, y, z) * Angles(0, guinada, 0) * Angles(arfagem, 0, 0)
-- "stand" é a pega de pé/agachado com que os clipes foram gravados (tools/anim, BAKED.holdStand).
-- Por tipo de arma, a pega muda (a pistola fica com os braços à frente, não colada no peito).
-- Escolhidas por busca em grade na simulação (penetração dos braços e da arma no corpo, com o
-- tronco de lado BLADE_DEG e torções de pelve até ±75° além dele, flexões de ±29°); o teste
-- tests/luau/faca.luau mede e imprime cada caso. Antes (0,2; 0,2; −0,7; 15°; −20°, sem polo e sem
-- tronco de lado): antebraço direito 13 cm dentro do peito e a coronha 20 cm.
-- Pronta: punho na altura do peito, ~27 cm à frente dele, boca para baixo e cruzando à esquerda
-- (30° no mundo com o tronco de lado). Pistola: duas mãos à frente, braços quase estendidos.
-- stylua: ignore
ArmIK.HOLDS = {
	rifle  = { 0.25, 0.8, -1.5, 55, -20 },
	mg     = { 0.25, 0.8, -1.5, 55, -20 },
	pistol = { 0.0, 0.9, -1.85, 20, -35 },
	-- golpe com o fuzil (PostureController, com o tronco de lado): em guarda, a boca 5° à esquerda
	-- da mira; a estocada anda 0,4 stud ao longo da arma (as mãos ficam até 9 cm aquém no fim)
	guard  = { 0.2, 1.0, -1.3, 30, -15 },
	lunge  = { 0.01, 0.9, -1.63, 30, -15 },
	-- faca na mão direita (tronco reto): o fuzil baixo, à esquerda, só na mão esquerda
	knife  = { -1.0, 0.1, -1.3, 50, -40 },
	-- recarga: o fuzil sobe e chega ao peito (o encaixe do carregador à vista); na pega de sempre a
	-- mão esquerda cruzava o peito para chegar ao encaixe (6 cm dentro do tronco no clipe)
	reload = { 0.2, 1.0, -1.3, 60, -20 },
} :: { [string]: { number } }
-- Tronco de lado (guinada do peito sobre a pelve, graus; o ombro esquerdo à frente, como quem segura
-- um fuzil de verdade); a cabeça gira de volta e olha para a frente. Sai no arremesso, na faca e
-- deitado (PostureController).
ArmIK.BLADE_DEG = 25

-- ===== polos dos cotovelos (no UpperTorso) =====
-- Sem polo o IKControl dobra o cotovelo para onde a pose de antes deixou: com o alvo perto do peito
-- (punho do fuzil a 0,2 stud da frente do tronco) o cotovelo podia ir para dentro e o braço passar
-- pelo peito. Direita: cotovelo para fora, para baixo e para trás (fuzil na pronta-baixa). Esquerda:
-- para fora e para baixo, sob o guarda-mão.
-- stylua: ignore
ArmIK.POLES = {
	stand = { R = { 3.2, -2.6, 0.4 }, L = { -3.0, -3.0, -1.2 } },
	prone = { R = { 2.4, 0.4, -2.2 }, L = { -2.4, 0.8, -2.2 } }, -- os do retarget deitado (tools/anim)
} :: { [string]: { R: V, L: V } }

-- ===== vetores e rotações (tabelas {x, y, z}; matriz 3x3 por linhas) =====
local function add(a: V, b: V): V
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end
local function sub(a: V, b: V): V
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function mul(a: V, k: number): V
	return { a[1] * k, a[2] * k, a[3] * k }
end
local function dot(a: V, b: V): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function cross(a: V, b: V): V
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function len(a: V): number
	return math.sqrt(dot(a, a))
end
local function unit(a: V): V
	local l = len(a)
	return if l > 1e-12 then mul(a, 1 / l) else a
end
ArmIK.add, ArmIK.sub, ArmIK.mul, ArmIK.dot, ArmIK.cross, ArmIK.len, ArmIK.unit = add, sub, mul, dot, cross, len, unit

export type R = { { number } }
local function mv(r: R, v: V): V
	return {
		r[1][1] * v[1] + r[1][2] * v[2] + r[1][3] * v[3],
		r[2][1] * v[1] + r[2][2] * v[2] + r[2][3] * v[3],
		r[3][1] * v[1] + r[3][2] * v[2] + r[3][3] * v[3],
	}
end
local function mm(a: R, b: R): R
	local o = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
	for i = 1, 3 do
		for j = 1, 3 do
			o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return o
end
local function tr(a: R): R
	return { { a[1][1], a[2][1], a[3][1] }, { a[1][2], a[2][2], a[3][2] }, { a[1][3], a[2][3], a[3][3] } }
end
ArmIK.mv, ArmIK.mm, ArmIK.tr = mv, mm, tr

function ArmIK.rx(a: number): R
	local c, s = math.cos(a), math.sin(a)
	return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } }
end
function ArmIK.ry(a: number): R
	local c, s = math.cos(a), math.sin(a)
	return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } }
end
function ArmIK.rz(a: number): R
	local c, s = math.cos(a), math.sin(a)
	return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } }
end

-- rotação que leva a1 exatamente a b1 e a2 o mais perto de b2 (como o r15.triad)
local function frame(p: V, q: V): R
	local e1 = unit(p)
	local e2 = unit(sub(q, mul(e1, dot(q, e1))))
	local e3 = cross(e1, e2)
	return { { e1[1], e2[1], e3[1] }, { e1[2], e2[2], e3[2] }, { e1[3], e2[3], e3[3] } }
end
function ArmIK.triad(a1: V, a2: V, b1: V, b2: V): R
	return mm(frame(b1, b2), tr(frame(a1, a2)))
end

-- Pega (CFrame do pivô) como (posição, rotação) a partir de {x, y, z, guinada°, arfagem°}.
function ArmIK.hold(h: { number }): (V, R)
	return { h[1], h[2], h[3] }, mm(ArmIK.ry(math.rad(h[4])), ArmIK.rx(math.rad(h[5])))
end

-- IK de dois ossos: cotovelo no plano raiz–alvo–polo, do lado do polo. Devolve (cotovelo, sobra):
-- sobra > 0 quando o alvo está fora do alcance (a mão para antes).
function ArmIK.twoBone(root: V, target: V, l1: number, l2: number, pole: V): (V, number)
	local d = sub(target, root)
	local dist = len(d)
	local reach = l1 + l2 - 1e-4
	local gap = 0
	if dist > reach then
		gap = dist - reach
		dist = reach
	end
	dist = math.max(dist, math.abs(l1 - l2) + 1e-4)
	local u = unit(d)
	local p = sub(pole, root)
	p = unit(sub(p, mul(u, dot(p, u))))
	local a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
	local h = math.sqrt(math.max(l1 * l1 - a * a, 0))
	return add(add(root, mul(u, a)), mul(p, h)), gap
end

export type Box = { c: V, r: R, h: V }
export type Arm = { upper: Box, fore: Box, hand: Box, gap: number, elbow: V, wrist: V }

-- Braço do lado ("R" | "L") com a mão (centro) em `target` e o cotovelo pelo `pole`.
function ArmIK.arm(side: string, target: V, pole: V): Arm
	local sh = ArmIK.SHOULDER[side]
	local u0 = ArmIK.UPPER[side]
	local l1 = len(u0)
	local l2 = ArmIK.FORE + ArmIK.HAND
	local elbow, gap = ArmIK.twoBone(sh, target, l1, l2, pole)
	local d1 = unit(sub(elbow, sh))
	local d2 = unit(sub(target, elbow))
	local sgn = if side == "L" then -1 else 1
	-- o lado de fora da peça do braço para fora do tronco (como o retarget)
	local wUp = ArmIK.triad(unit(u0), { sgn, 0, 0 }, d1, { sgn, 0, 0 })
	local wFore = ArmIK.triad({ 0, -1, 0 }, { 1, 0, 0 }, d2, mv(wUp, { 1, 0, 0 }))
	local upC = sub(sh, mv(wUp, ArmIK.UPPER_C1[side]))
	local foreC = sub(elbow, mv(wFore, { 0, ArmIK.FORE_C1, 0 }))
	local wrist = add(elbow, mul(d2, ArmIK.FORE))
	return {
		upper = { c = upC, r = wUp, h = ArmIK.HALF.UpperArm },
		fore = { c = foreC, r = wFore, h = ArmIK.HALF.LowerArm },
		hand = { c = target, r = wFore, h = ArmIK.HALF.Hand },
		gap = gap,
		elbow = elbow,
		wrist = wrist,
	}
end

-- Distância com sinal do ponto à caixa arredondada (centro c, rotação r, meia-caixa h, raio rr):
-- < 0 dentro.
function ArmIK.sdBox(p: V, b: Box, rr: number): number
	local l = mv(tr(b.r), sub(p, b.c))
	local q = {
		math.abs(l[1]) - (b.h[1] - rr),
		math.abs(l[2]) - (b.h[2] - rr),
		math.abs(l[3]) - (b.h[3] - rr),
	}
	local o = { math.max(q[1], 0), math.max(q[2], 0), math.max(q[3], 0) }
	return len(o) + math.min(math.max(q[1], q[2], q[3]), 0) - rr
end

local IDENT: R = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

-- Corpo no espaço do UpperTorso; twist = guinada da pelve em relação ao peito (pernas na direção do
-- movimento, SoldierAnimations.legYaw: até 75°); bend = arfagem do peito sobre a pelve (rad).
function ArmIK.body(twist: number?, bend: number?): { Box }
	local tw = ArmIK.ry(twist or 0)
	local bd = ArmIK.rx(-(bend or 0))
	local lr = mm(bd, tw)
	local waist = ArmIK.WAIST
	local lower = add(waist, mv(lr, ArmIK.LOWER_FROM_WAIST))
	return {
		{ c = { 0, 0, 0 }, r = IDENT, h = ArmIK.HALF.UpperTorso },
		{ c = lower, r = lr, h = ArmIK.HALF.LowerTorso },
		{ c = ArmIK.HEAD, r = IDENT, h = ArmIK.HALF.Head },
	}
end

-- Penetração (studs, ≥ 0) da peça do braço no corpo: o ponto mais fundo de uma grade 3×5×3 dentro
-- da caixa da peça reduzida (ARM_SHRINK).
function ArmIK.depth(part: Box, body: { Box }): number
	local worst = 0
	local k = ArmIK.ARM_SHRINK
	for i = -1, 1 do
		for j = -2, 2 do
			for m = -1, 1 do
				local lp = { part.h[1] * k * i, part.h[2] * k * j / 2, part.h[3] * k * m }
				local p = add(part.c, mv(part.r, lp))
				for _, b in body do
					local sd = ArmIK.sdBox(p, b, math.min(ArmIK.TORSO_ROUND, b.h[1], b.h[2], b.h[3]))
					if sd < -worst then
						worst = -sd
					end
				end
			end
		end
	end
	return worst
end

export type Case = {
	grip: V, -- mão direita (centro), no UpperTorso
	support: V?, -- mão esquerda; nil = solta (recarga)
	poles: { R: V, L: V },
	twist: number?,
	bend: number?,
}

-- Pior penetração (studs) dos dois braços no corpo e a maior sobra de alcance.
function ArmIK.measure(c: Case): (number, number, string)
	local body = ArmIK.body(c.twist, c.bend)
	local worst, gap, where = 0, 0, ""
	local function check(side: string, target: V)
		local a = ArmIK.arm(side, target, c.poles[side])
		gap = math.max(gap, a.gap)
		local names = { "upper", "fore", "hand" }
		for i, part in { a.upper, a.fore, a.hand } do
			local d = ArmIK.depth(part, body)
			if d > worst then
				worst, where = d, side .. ":" .. names[i]
			end
		end
	end
	check("R", c.grip)
	if c.support then
		check("L", c.support :: V)
	end
	return worst, gap, where
end

-- Alvos das mãos para a arma: pega (pivô no punho) e apoio (deslocamento do apoio no espaço da arma).
function ArmIK.targets(holdT: { number }, supportOff: V): (V, V)
	local p, r = ArmIK.hold(holdT)
	return p, add(p, mv(r, supportOff))
end

return ArmIK
