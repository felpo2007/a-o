--!strict
-- Arma em 3ª pessoa no boneco de bloco (pedido do dono, 2026-11-13: "armas estão bugadas em 3ª
-- pessoa, ajeite a pegada e tamanho da arma"). Módulo PURO: só CFrame e Vector3 (no Lune, os do
-- @lune/roblox por Pegada3P.env). Quem usa: PostureController (todos os soldados, todo quadro) e
-- SoldierPreview (manequins do menu, parados).
--
-- Copiado do Front 44 (Client/Poses.luau: pose() e armIK(); Config.Bodies.BlockyHold), levado ao
-- boneco daqui (Corpo.BLOCK_SCALE = 1,4286 vezes o de lá) com a arma no TAMANHO REAL (D-108: mais
-- grossa, Corpo.ARMA_K; o comprimento é o que o braço alcança com a coronha no ombro):
-- - lá a arma é 1,3 vez a real e o pivô fica dentro do peito; aqui a coronha encosta no bolso do
--   ombro direito, na frente do peito, e a arma gira em volta dela;
-- - a arma aponta para onde o soldado mira: o giro do tronco (postura de lado, inclinar, deitado,
--   clipe) é desfeito pela rotação do tronco em relação à HumanoidRootPart;
-- - guarda baixa (cano 22° para baixo), atirando sobe ao ombro (AdsRaise), correndo vai atravessada
--   no peito com o cano para cima (SprintHighPort), recarregando vem para perto do peito;
-- - braços: IK de dois ossos do Front 44 (cotovelo pelo polo, punho reto: a mão de bloco continua o
--   antebraço), com o ponto da pegada da mão (GripAttachment) no punho e no guarda-mão.
-- Antes (D-94/D-98): pega fixa, cruzada no peito (55° de guinada, boca para baixo), medida no corpo
-- "Man"; o IKControl punha o CENTRO da mão no alvo um quadro atrasado (a mão tremia andando).
-- Tudo em studs do soldado de 2 m, no espaço do UpperTorso (X direita, Y cima, frente −Z).
local Corpo = require(script and (script :: any).Parent.Corpo or "./Corpo") :: any

local Pegada3P = {}

local CF: any = CFrame
local V3: any = Vector3

-- Lune: Pegada3P.env({ CFrame = roblox.CFrame, Vector3 = roblox.Vector3 })
function Pegada3P.env(e: { CFrame: any, Vector3: any })
	CF, V3 = e.CFrame, e.Vector3
end

local S: number = Corpo.BLOCK_SCALE -- boneco de bloco de escala 1 (Front 44) -> soldado daqui
Pegada3P.S = S
-- mão menor (Corpo.MAO_K): a mão de bloco do R15 tem a largura do braço (40 cm no soldado de 2 m) e
-- engolia o punho e o guarda-mão da arma de tamanho real
Pegada3P.HAND_K = Corpo.MAO_K

-- ===== armas maiores (D-108, Shared/Corpo.ARMA_K) =====
-- Arma de 3ª pessoa: comprimento L (ao longo do cano) e grossura G (largura e altura). A pistola cresce
-- por inteiro (o cabo fica na mão e o braço não estica). Soleira, punho, apoio e boca chegam medidos no
-- modelo já escalado (PostureController.infoOf); aqui escalam as medidas da arma escritas em número.
Pegada3P.L = Corpo.ARMA_COMPRIMENTO_3P
Pegada3P.G = Corpo.ARMA_K

-- (comprimento, grossura) da arma de 3ª pessoa pelo tipo
function Pegada3P.fatores3P(kind: string?): (number, number)
	if kind == "pistol" then
		return Pegada3P.G, Pegada3P.G
	end
	return Pegada3P.L, Pegada3P.G
end

-- Ponto no espaço da arma (punho na origem, boca em −Z) com a arma escalada.
function Pegada3P.escalaPonto(p: Vector3, l: number, g: number): Vector3
	return V3.new(p.X * g, p.Y * g, p.Z * l)
end

-- Tamanho de uma peça de giro `rot` (no espaço da arma) com a arma escalada: cada eixo da peça estica
-- pelo comprimento que ele ganha (Front 44, GunModels.thicken; exato nas peças alinhadas à arma).
function Pegada3P.escalaTamanho(size: Vector3, rot: CFrame, l: number, g: number): Vector3
	local function k(x: number, y: number, z: number): number
		local d = rot:VectorToWorldSpace(V3.new(x, y, z))
		return math.sqrt((d.X * g) ^ 2 + (d.Y * g) ^ 2 + (d.Z * l) ^ 2)
	end
	return V3.new(size.X * k(1, 0, 0), size.Y * k(0, 1, 0), size.Z * k(0, 0, 1))
end

-- ===== 1ª pessoa (WeaponVisuals): a arma k vezes maior por inteiro =====
-- Quadril: a alça fica onde ficava com a arma real (D-69) e a arma cresce em volta dela; o punho e a
-- mão descem um pouco. `sight` = alça na arma JÁ escalada (punho na origem), studs.
function Pegada3P.quadril1P(hip: CFrame, sight: Vector3, k: number): CFrame
	return hip * CF.new(-sight * ((k - 1) / k))
end

-- Mira: o olho a eye x k da alça e a linha alça -> massa no centro da tela (D-60). Com a arma k vezes
-- maior e o olho k vezes mais longe, a imagem é a da arma real (ampliação em volta do olho): alça,
-- massa, anel e o que fica embaixo deles aparecem como na D-67. eye = olho até a alça (studs, real).
function Pegada3P.mira1P(sight: Vector3, front: Vector3?, eye: number, k: number): CFrame
	local los = if front then front - sight else V3.new(0, 0, -1)
	-- giro mínimo que leva a linha a −Z (o CFrame.lookAt do Lune erra; no Roblox dá o mesmo a 0,01°).
	-- Sem o corte do fromTo: a linha da M14 está a 0,23° do cano e precisa girar.
	local align = CF.identity
	if los.Z < -1e-3 then
		local u, fwd = los.Unit, V3.new(0, 0, -1)
		local ax = u:Cross(fwd)
		if ax.Magnitude > 1e-9 then
			align = CF.fromAxisAngle(ax.Unit, math.acos(math.clamp(u:Dot(fwd), -1, 1)))
		end
	end
	return CF.new(0, 0, -eye * k) * align * CF.new(-sight)
end

-- ===== pose da arma (PLACEHOLDER: conferir no Studio) =====
-- Coronha no bolso do ombro direito, na frente do peito (o tronco de bloco tem meia profundidade 0,5 x S).
-- Escolhidas no simulador (tests/luau/pegada.luau): as duas mãos no alcance, o cano fora do tronco.
Pegada3P.BUTT = { 0.25, 0.40, -0.53 } -- x S
Pegada3P.BUTT_PRONE = { 0.15, 0.40, -0.80 } -- deitado: abaixo da cabeça, rente ao chão
Pegada3P.BUTT_DY = 0.13 -- studs (x G): centro da soleira acima do punho (M14: cano 0,18 stud acima)
-- Front 44 (x S): na mira a arma sobe até o rosto; guarda baixa; corrida de assalto; recarga perto do peito
Pegada3P.RAISE = 0.45
Pegada3P.GUARD = { pos = { 0, -0.18, 0.05 }, rot = { -22, 8, -6 } }
-- corrida: Front 44 (−0,42; 0,05; 0,05) e (48°, 38°, 32°); para o lado só −0,24 (com −0,42 o braço
-- direito ia a 98% do alcance na arma mais curta; com −0,32, a 100% na M60, D-108)
Pegada3P.PORT = { pos = { -0.24, 0.05, 0.05 }, rot = { 48, 38, 32 }, pump = 7, lift = 0.08 }
Pegada3P.RELOAD = { pos = { -0.1, -0.1, 0.1 }, rot = { 8, 0, 0 } } -- z 0,3 do Front 44 enterrava a coronha
-- pistola: as duas mãos no cabo, braços quase esticados (Front 44 BlockyHold.Pivot + PistolGrip; o
-- −1,35 de lá deixava o braço direito a 97% do alcance aqui)
Pegada3P.PISTOL_PIVOT = { 0.55, 0.4, -0.1 }
Pegada3P.PISTOL_GRIP = { -0.3, -0.25, -1.2 }
-- tronco de lado (graus; Front 44 BLADE: 12, 8 e 32): o ombro esquerdo à frente. Fuzil 34° aqui: a
-- arma real é mais curta e a mão esquerda precisa chegar ao guarda-mão
Pegada3P.BLADE = { pistol = 12, launcher = 8, rifle = 34 } :: { [string]: number }
-- polos dos cotovelos (direções no UpperTorso; Front 44 ARMS.Pole e os do retarget deitado)
Pegada3P.POLES = {
	stand = { R = { 1.6, -1.1, 0.5 }, L = { -0.9, -2.2, -0.3 } },
	prone = { R = { 2.4, 0.4, -2.2 }, L = { -2.4, 0.8, -2.2 } },
} :: { [string]: { R: { number }, L: { number } } }
-- mão esquerda: no mínimo SUPPORT_MIN à frente do punho (mais perto, as mãos de 0,79 stud se
-- tocam); fica antes da boca. Fora do alcance do braço (mira muito alta ou baixa), escorrega para
-- trás ao longo do cano (Front 44, Poses "slideBack") até SUPPORT_BACK, junto do carregador.
Pegada3P.SUPPORT_MIN = 1.0
Pegada3P.SUPPORT_BACK = 0.62 -- studs (x L)
Pegada3P.REACH_USE = 0.97
-- Lança-rojão (RPG-2): atrás do punho o tubo é bem mais comprido que uma coronha (2,57 studs; a M79 tem
-- 1,1) e vai APOIADO EM CIMA do ombro direito, por fora da cabeça, com o punho à frente do ombro. Antes a
-- ponta de trás ia ao bolso do ombro e o punho ficava a ~72 cm dele: a mão direita não chegava (137% do
-- alcance). pos: apoio no ombro (x S); dy: eixo do tubo acima do punho (studs, x G); ahead: punho à
-- frente do apoio (x S); pitch: arfagem que o tubo acompanha sem entrar no ombro (graus). PLACEHOLDER.
Pegada3P.TUBE_REAR = 1.6 -- studs (x L): soleira mais longe que isso = tubo no ombro
Pegada3P.TUBE = { pos = { 0.82, 0.92, -0.42 }, dy = 0.32, ahead = 0.6, pitch = { -20, 12 }, guard = -6 }

local function v(t: { number }, k: number?): Vector3
	local m = k or 1
	return V3.new(t[1] * m, t[2] * m, t[3] * m)
end

local function rot(t: { number }, w: number): CFrame
	return CF.Angles(math.rad(t[1]) * w, math.rad(t[2]) * w, math.rad(t[3]) * w)
end

function Pegada3P.blade(kind: string?): number
	return math.rad(Pegada3P.BLADE[kind or "rifle"] or Pegada3P.BLADE.rifle)
end

export type State = {
	kind: string, -- "rifle" | "mg" | "pistol" | "launcher"
	pitch: number, -- rad: mira (para cima > 0), no rumo da HumanoidRootPart
	ads: number, -- 0..1: no ombro (atirando)
	sprint: number, -- 0..1
	prone: number, -- 0..1
	busy: number, -- 0..1: recarga
	rear: number, -- studs do punho até a soleira, ao longo do cano
	moving: number, -- 0..1
	swing: number, -- −1..1: fase da passada (sen)
	lift: number, -- 0..1: |cos| da passada
	breath: number, -- s (relógio da respiração)
	yawRate: number, -- rad/s: o corpo virando (a arma atrasa)
	kick: number, -- 0..1: coice do tiro
}

function Pegada3P.state(kind: string?): State
	return {
		kind = kind or "rifle",
		pitch = 0,
		ads = 0,
		sprint = 0,
		prone = 0,
		busy = 0,
		rear = 1.05,
		moving = 0,
		swing = 0,
		lift = 0,
		breath = 0,
		yawRate = 0,
		kick = 0,
	}
end

-- Pivô da arma (punho, frente −Z) no espaço do UpperTorso. torso = rotação do UpperTorso em relação
-- à HumanoidRootPart (o rumo do corpo); a mira é o rumo dele mais a arfagem s.pitch.
function Pegada3P.gun(torso: CFrame, s: State): CFrame
	local p = math.clamp(s.prone, 0, 1)
	local sp = math.clamp(s.sprint, 0, 1) * (1 - math.clamp(s.busy, 0, 1)) * (1 - p)
	local busy = math.clamp(s.busy, 0, 1) * (1 - p)
	local ads = math.clamp(s.ads, 0, 1) * (1 - p) * (1 - sp)
	local guard = (1 - ads) * (1 - sp) * (1 - p) * (1 - busy)
	-- mira no espaço do tronco: desfaz o giro dele (postura de lado, inclinar, deitado)
	local aim = torso.Rotation:Inverse() * CF.Angles(math.clamp(s.pitch, -1.3, 1.3), 0, 0)
	-- respiração, passada e atraso no giro (Front 44 "life"), menos no ombro
	local calm = 1 - 0.75 * ads
	local still = (1 - s.moving) * calm
	local tb = s.breath
	local life = CF.new(
		math.sin(tb * 0.7) * 0.012 * S * still,
		math.sin(tb * 1.6) * 0.022 * S * still - s.lift * s.moving * (1 - sp) * 0.06 * S * calm,
		0
	) * CF.Angles(
		math.rad(math.sin(tb * 1.6 + 0.6) * 1.1 * still + s.swing * 1.6 * s.moving * calm),
		math.rad(-math.clamp(s.yawRate * 1.6, -7, 7) * calm + s.swing * 2.2 * s.moving * calm),
		math.rad(math.sin(tb * 0.9) * 0.8 * still + s.swing * 2.5 * s.moving * calm)
	)
	local G = Pegada3P.GUARD
	local lowered = CF.new(v(G.pos, S * guard)) * rot(G.rot, guard)
	local P = Pegada3P.PORT
	local port = CF.new(P.pos[1] * S * sp, (P.pos[2] + s.lift * P.lift) * S * sp, P.pos[3] * S * sp)
		* CF.Angles(
			math.rad(48) * sp,
			math.rad(38) * sp,
			math.rad(32) * sp + math.rad(P.pump) * s.swing * s.moving * sp
		)
	local R = Pegada3P.RELOAD
	local reload = CF.new(v(R.pos, S * busy)) * rot(R.rot, busy)
	local k = math.clamp(s.kick, 0, 1)
	local kick = CF.new(0, 0.02 * S * k, 0.14 * S * k) * CF.Angles(math.rad(5) * k, 0, 0)
	if Pegada3P.tubo(s) then
		-- tubo no ombro: gira no apoio, sem corrida atravessada nem recarga no peito (D-108)
		local T = Pegada3P.TUBE
		local tp = math.clamp(s.pitch, math.rad(T.pitch[1]), math.rad(T.pitch[2]))
		local tAim = torso.Rotation:Inverse() * CF.Angles(tp, 0, 0)
		local droop = CF.Angles(math.rad(T.guard) * (1 - ads), 0, 0)
		local base = v(T.pos, S):Lerp(v(Pegada3P.BUTT_PRONE, S), p)
		return CF.new(base) * tAim * droop * life * kick * CF.new(0, -T.dy * Pegada3P.G, -T.ahead * S)
	end
	if s.kind == "pistol" then
		local pivot = v(Pegada3P.PISTOL_PIVOT, S) + V3.new(0, Pegada3P.RAISE * S * ads * 0.5, 0)
		return CF.new(pivot) * aim * lowered * port * reload * life * kick * CF.new(v(Pegada3P.PISTOL_GRIP, S))
	end
	local butt = v(Pegada3P.BUTT, S):Lerp(v(Pegada3P.BUTT_PRONE, S), p)
	local raised = V3.new(0, Pegada3P.RAISE * S * ads, 0)
	return CF.new(butt + raised)
		* aim
		* lowered
		* port
		* reload
		* life
		* kick
		* CF.new(0, -Pegada3P.BUTT_DY * Pegada3P.G, -math.max(s.rear, 0.3))
end

-- Lança-rojão de tubo (RPG-2): vai no ombro, não na pega de coronha.
function Pegada3P.tubo(s: State): boolean
	return s.kind == "launcher" and s.rear > Pegada3P.TUBE_REAR * Pegada3P.L
end

-- Alvo da mão esquerda (espaço da arma, a partir do punho): o apoio da arma, empurrado para a frente
-- até SUPPORT_MIN (sem passar de `maxZ`, perto da boca) e, se o braço não alcança, de volta ao longo
-- do cano até SUPPORT_BACK. shoulder = ombro esquerdo no espaço da arma; reach = alcance (studs).
function Pegada3P.support(base: Vector3, maxZ: number, shoulder: Vector3, reach: number): Vector3
	local z = math.max(-base.Z, Pegada3P.SUPPORT_MIN)
	z = math.min(z, math.max(maxZ, -base.Z))
	local pos = V3.new(base.X, base.Y, -z)
	local lim = reach * Pegada3P.REACH_USE
	if (pos - shoulder).Magnitude > lim then
		local lo, hi = math.min(Pegada3P.SUPPORT_BACK * Pegada3P.L, -base.Z), z
		for _ = 1, 12 do
			local mid = (lo + hi) / 2
			if (V3.new(base.X, base.Y, -mid) - shoulder).Magnitude > lim then
				hi = mid
			else
				lo = mid
			end
		end
		pos = V3.new(base.X, base.Y, -lo)
	end
	return pos
end

-- ===== braço: IK de dois ossos (Front 44 armIK) =====
-- Juntas do braço como no R15 (C0 no pai, C1 no filho; o Transform vai entre eles):
-- braço = UT · c0s · T1 · c1s⁻¹; antebraço = braço · c0e · T2 · c1e⁻¹; mão = antebraço · c0w · c1w⁻¹.
export type ArmRig = {
	c0s: CFrame,
	c1s: CFrame,
	c0e: CFrame,
	c1e: CFrame,
	c0w: CFrame,
	c1w: CFrame,
	grip: CFrame, -- ponto da pegada na mão (GripAttachment)
}

-- Rotação mínima que leva a direção a até b (unitários).
local function fromTo(a: Vector3, b: Vector3): CFrame
	local d = math.clamp(a:Dot(b), -1, 1)
	if d > 0.99999 then
		return CF.identity
	elseif d < -0.99999 then
		local ax = if math.abs(a.X) < 0.9 then a:Cross(V3.new(1, 0, 0)) else a:Cross(V3.new(0, 1, 0))
		return CF.fromAxisAngle(ax.Unit, math.pi)
	end
	return CF.fromAxisAngle(a:Cross(b).Unit, math.acos(d))
end
Pegada3P.fromTo = fromTo

-- Cotovelo no plano ombro–alvo, do lado do polo (direção).
local function elbowAt(shoulder: Vector3, target: Vector3, a: number, b: number, pole: Vector3): Vector3
	local delta = target - shoulder
	local d = math.clamp(delta.Magnitude, math.abs(a - b) + 1e-3, a + b - 1e-3)
	local dir = if delta.Magnitude > 1e-4 then delta.Unit else V3.new(0, -1, 0)
	local x = (a * a - b * b + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, a * a - x * x))
	local bend = pole - dir * pole:Dot(dir)
	bend = if bend.Magnitude > 1e-4 then bend.Unit else V3.new(0, -1, 0)
	return shoulder + dir * x + bend * h
end

-- Comprimentos do braço: ombro -> cotovelo e cotovelo -> pegada (punho reto).
function Pegada3P.lengths(r: ArmRig): (number, number)
	local upper = (r.c1s:Inverse() * r.c0e).Position
	local lower = (r.c1e:Inverse() * r.c0w * r.c1w:Inverse() * r.grip).Position
	return upper.Magnitude, lower.Magnitude
end

-- Transform do ombro e do cotovelo que põem a pegada da mão em `target` (espaço do UpperTorso);
-- pole = direção para onde o cotovelo dobra, no mesmo espaço.
function Pegada3P.arm(r: ArmRig, target: Vector3, pole: Vector3): (CFrame, CFrame)
	local upperVec = (r.c1s:Inverse() * r.c0e).Position
	local lowerVec = (r.c1e:Inverse() * r.c0w * r.c1w:Inverse() * r.grip).Position
	local shoulder = r.c0s.Position
	local elbow = elbowAt(shoulder, target, upperVec.Magnitude, lowerVec.Magnitude, pole)
	local r1 = fromTo(upperVec.Unit, r.c0s:VectorToObjectSpace(elbow - shoulder).Unit)
	local j1 = r.c0s * r1 * r.c1s:Inverse() * r.c0e
	local r2 = fromTo(lowerVec.Unit, j1:VectorToObjectSpace(target - elbow).Unit)
	return r1, r2
end

-- Peças do braço no espaço do UpperTorso para os Transform dados (teste e prévia).
function Pegada3P.parts(r: ArmRig, t1: CFrame, t2: CFrame): (CFrame, CFrame, CFrame)
	local upper = r.c0s * t1 * r.c1s:Inverse()
	local lower = upper * r.c0e * t2 * r.c1e:Inverse()
	local hand = lower * r.c0w * r.c1w:Inverse()
	return upper, lower, hand
end

-- Braço do R15 de bloco (attachments da escala 1, vezes k) para o teste e para a prévia sem juntas.
-- Medidas do R15 em bloco (tools/anim/r15.py, Front 44: ombro -> cotovelo 0,89; cotovelo -> pegada 1,04).
function Pegada3P.blockArm(side: string, k: number): ArmRig
	local sx = if side == "L" then -1 else 1
	return {
		c0s = CF.new(1.0 * sx * k, 0.563 * k, 0),
		c1s = CF.new(-0.5 * sx * k, 0.394 * k, 0),
		c0e = CF.new(0, -0.334 * k, 0),
		c1e = CF.new(0, 0.259 * k, 0),
		c0w = CF.new(0, -0.501 * k, 0),
		c1w = CF.new(0, 0.125 * k, 0),
		grip = CF.new(0, -0.15 * k, 0),
	}
end

-- Tamanhos das peças do boneco de bloco (escala 1, vezes k): para o teste de penetração.
Pegada3P.SIZES = {
	UpperTorso = { 2, 1.6, 1 },
	Head = { 1.2, 1.2, 1.2 },
	UpperArm = { 1, 1.169, 1 },
	LowerArm = { 1, 1.052, 1 },
	Hand = { 1, 0.3, 1 },
} :: { [string]: { number } }

return Pegada3P
