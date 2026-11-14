--!strict
-- Animações do soldado com fuzil: captura de movimento da CMU (mocap.cs.cmu.edu) retargetada para o
-- R15 no tools/anim (retarget.py -> JSON -> kfs.luau -> .rbxm). Módulo PURO, testado no Lune
-- (tests/luau/anim.luau); o runtime é o Controllers/SoldierAnimations.client.
-- - id 0 = ainda não publicado. Sem os quatro de pé publicados (enabled), NADA muda no jogo.
-- - Números de cada clipe (duração, velocidade em que o pé não escorrega, ciclos de passada) saem do
--   retarget (assets/mocap/soldado/<clipe>.json), não de chute.
-- - BAKED: o que o retarget leu do código ao gravar os clipes. Os agachados e deitados são gravados
--   em relação à postura do servidor (o HipHeight cai DROP; deitado, o C0 da Root gira PRONE_ROOT);
--   o teste confere que PostureService e PostureController ainda têm esses valores.
-- - D-98: os clipes foram gravados no corpo de 1,75 m; o soldado do jogo é o mesmo corpo ampliado por
--   SCALE (Shared/Corpo.K). As rotações valem igual; a Root o Animator escala por HipHeight /
--   AuthoredHipHeight; a passada fica SCALE vezes mais longa (perna mais longa), então a velocidade
--   em que o pé não escorrega é speed × SCALE. BAKED segue no tamanho da gravação.
local Movement = require(script and (script :: any).Parent.Movement or "./Movement") :: any
local Corpo = require(script and (script :: any).Parent.Corpo or "./Corpo") :: any

local SoldierAnims = {}
SoldierAnims.STUD_M = Movement.STUD_M
SoldierAnims.SCALE = Corpo.K -- tamanho do jogo / tamanho da gravação

export type Clip = {
	id: number, -- asset de Animation (0 = não publicado)
	length: number, -- s
	speed: number, -- m/s em que o pé apoiado fica parado no chão tocando a 1x (0 = parado)
	cycles: number, -- ciclos de passada (dois passos) no laço; 0 = sem passada
	stance: string, -- "stand" | "crouch" | "prone"
	loop: boolean,
	layer: string, -- "loco" (Movement) | "upper" (Action: tronco, cabeça e braços)
}

-- stylua: ignore
SoldierAnims.CLIPS = {
	parado         = { id = 89202876813933, length = 3.3667, speed = 0,     cycles = 0, stance = "stand",  loop = true,  layer = "loco" },
	andar          = { id = 127399564065374, length = 2.275,  speed = 1.076, cycles = 2, stance = "stand",  loop = true,  layer = "loco" },
	trote          = { id = 114026505834170, length = 0.75,   speed = 2.663, cycles = 1, stance = "stand",  loop = true,  layer = "loco" },
	correr         = { id = 133413132642437, length = 0.65,   speed = 3.898, cycles = 1, stance = "stand",  loop = true,  layer = "loco" },
	-- D-94: agachados regravados com DROP.crouch 1,03 e recarregar/granada com a pega nova: id 0 até
	-- subir de novo (os velhos dobrariam o corpo no ar ou levariam a mão longe do fuzil)
	agachado       = { id = 107203115616695, length = 3.3667, speed = 0,     cycles = 0, stance = "crouch", loop = true,  layer = "loco" },
	agachado_andar = { id = 74699707687127, length = 2.5917, speed = 0.756, cycles = 2, stance = "crouch", loop = true,  layer = "loco" },
	deitado        = { id = 77922132925659, length = 2.0,    speed = 0,     cycles = 0, stance = "prone",  loop = true,  layer = "loco" },
	rastejar       = { id = 106284082412771, length = 1.6,    speed = 0.35,  cycles = 1, stance = "prone",  loop = true,  layer = "loco" },
	recarregar     = { id = 121371190730665, length = 2.4,    speed = 0,     cycles = 0, stance = "stand",  loop = false, layer = "upper" },
	granada        = { id = 93580140836876, length = 0.8,    speed = 0,     cycles = 0, stance = "stand",  loop = false, layer = "upper" },
	-- corpo a corpo (D-94, procedurais): faca na mão direita (Shared/Melee), golpe com o fuzil
	faca_saque     = { id = 128911670737726, length = 0.2833, speed = 0,     cycles = 0, stance = "stand",  loop = false, layer = "upper" },
	faca_estocada  = { id = 75823411352386, length = 0.55,   speed = 0,     cycles = 0, stance = "stand",  loop = false, layer = "upper" },
	faca_lado      = { id = 128196368754555, length = 0.6,    speed = 0,     cycles = 0, stance = "stand",  loop = false, layer = "upper" },
	faca_guardar   = { id = 106728637909412, length = 0.35,   speed = 0,     cycles = 0, stance = "stand",  loop = false, layer = "upper" },
	baioneta       = { id = 123176623109494, length = 0.9,    speed = 0,     cycles = 0, stance = "stand",  loop = false, layer = "upper" },
	-- D-99: uso de itens (procedurais, Shared/ItemAnim): tronco e cabeça; as mãos vão por IK
	-- (PostureController). Tocados parados e posicionados pelo relógio do servidor (ItemAnim.localTime).
	item_curativo       = { id = 97278159777784, length = 6.0,  speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
	item_torniquete     = { id = 115753692053828, length = 4.0,  speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
	item_curativo_outro = { id = 79700784293465, length = 4.0,  speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
	item_tratar         = { id = 97893886554554, length = 10.0, speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
	item_reanimar       = { id = 137339494942552, length = 8.0,  speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
	item_radio          = { id = 116108976413773, length = 1.3333, speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
	item_binoculo       = { id = 81042080978575, length = 2.4,  speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
	item_pa             = { id = 84255439050425, length = 8.0,  speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
	item_cantil         = { id = 84448631326434, length = 3.5,  speed = 0, cycles = 0, stance = "stand", loop = false, layer = "upper" },
} :: { [string]: Clip }

-- D-99: ação/item (Shared/ItemAnim) -> clipe de 3ª pessoa
SoldierAnims.ITEM_CLIP = {
	bandage = "item_curativo",
	tourniquet = "item_torniquete",
	bandage_other = "item_curativo_outro",
	treat = "item_tratar",
	revive = "item_reanimar",
	radio = "item_radio",
	binoculars = "item_binoculo",
	shovel = "item_pa",
	canteen = "item_cantil",
} :: { [string]: string }

-- golpe (Shared/Melee) -> clipe de 3ª pessoa; a coronhada usa o do fuzil
SoldierAnims.MELEE_CLIP = {
	estocada = "faca_estocada",
	lado = "faca_lado",
	baioneta = "baioneta",
	coronhada = "baioneta",
}
SoldierAnims.KNIFE_CLIPS = { "faca_saque", "faca_estocada", "faca_lado", "faca_guardar" }

-- o que o retarget leu do código (tools/anim/retarget.py: ler_postura, HOLD_STAND, BASE_HIP)
SoldierAnims.BAKED = {
	drop = { crouch = 1.03, prone = 4.4 }, -- PostureService.DROP (studs; D-94: agachado 2,2 -> 1,03)
	minHip = 0.2, -- PostureService.MIN_HIP
	proneRoot = { y = -0.6, pitchDeg = -85 }, -- PostureService.PRONE_ROOT
	-- PostureController.HOLD_STAND (D-94: era 0,2/0,2/−0,7, 15°, −20°; braço e coronha dentro do peito)
	holdStand = { x = 0.25, y = 0.8, z = -1.5, yawDeg = 55, pitchDeg = -20 },
	baseHip = 2.5, -- HipHeight em pé (2,40 medido com escala 1,2; PLACEHOLDER com 1,25)
	throwS = 0.8, -- FieldService.THROW_S (gesto inteiro); a granada sai em 0,4 s
}

-- Bots: cada cliente anima localmente os bots perto da câmera (o servidor não toca animação neles).
-- D-94: ligado, com nível de detalhe (SoldierAnimations): até BOT_NEAR tudo a cada quadro; até
-- BOT_RADIUS e visível, a mistura a cada FAR_STEP_S e as correções a cada FAR_POST_S; fora da vista
-- ou além do raio os clipes param. Custo com 58 bots: medir no Studio (não medido).
SoldierAnims.BOTS = true
SoldierAnims.BOT_RADIUS = 300 -- studs (~84 m)
SoldierAnims.BOT_NEAR = 100 -- studs (~28 m)
SoldierAnims.FAR_STEP_S = 0.1 -- 10 Hz
SoldierAnims.FAR_POST_S = 1 / 15

-- Âncoras da mistura de pé: cada clipe tem peso cheio na velocidade do jogo (Shared/Movement).
SoldierAnims.GAIT = { "andar", "trote", "correr" }
SoldierAnims.ANCHOR = { andar = Movement.WALK, trote = Movement.JOG, correr = Movement.SPRINT }

-- parado <-> andando, com histerese (m/s)
SoldierAnims.MOVE_ON = { stand = 0.25, crouch = 0.15, prone = 0.06 }
SoldierAnims.MOVE_OFF = { stand = 0.1, crouch = 0.06, prone = 0.03 }

-- tempos de mistura (s)
SoldierAnims.FADE_BLEND = 0.12 -- mistura da passada acompanhando a velocidade
SoldierAnims.FADE_IDLE = 0.25 -- parado <-> andando na mesma postura
SoldierAnims.FADE_OUT = 0.15 -- pulo, queda, nado, escada, assento, transpor: a camada sai
SoldierAnims.FADE_IN = 0.2
SoldierAnims.FADE_PRONE_MAX = 0.6 -- deitar/levantar: a câmera leva 0,6–1,0 s; o corpo não espera tanto
-- 2026-11-13 (movimento do Front 44): rastejar a 1,12 m/s pede 2,8x do clipe (0,35 m/s × SCALE) e o
-- VC agachado (1,96 × 1,12 = 2,2 m/s) 2,54x; com teto 2,5 o pé deslizava ~11%. 3,0 dá folga.
SoldierAnims.RATE_MIN, SoldierAnims.RATE_MAX = 0.35, 3.0

function SoldierAnims.id(name: string): number
	local c = SoldierAnims.CLIPS[name]
	return if c then c.id else 0
end

-- Liga só com os quatro de pé publicados; agachado, deitado e as camadas de cima entram se tiverem id.
function SoldierAnims.enabled(): boolean
	for _, n in { "parado", "andar", "trote", "correr" } do
		if SoldierAnims.id(n) == 0 then
			return false
		end
	end
	return true
end

function SoldierAnims.stanceOf(crouched: boolean, prone: boolean): string
	return if prone then "prone" elseif crouched then "crouch" else "stand"
end

-- Pesos da passada de pé pela velocidade real (m/s): andar em WALK, trote em JOG, correr em SPRINT.
function SoldierAnims.gaitWeights(speed: number): { [string]: number }
	local g, a = SoldierAnims.GAIT, SoldierAnims.ANCHOR
	if speed <= a[g[1]] then
		return { [g[1]] = 1 }
	end
	for i = 1, #g - 1 do
		local lo, hi = a[g[i]], a[g[i + 1]]
		if speed <= hi then
			local u = (speed - lo) / (hi - lo)
			return { [g[i]] = 1 - u, [g[i + 1]] = u }
		end
	end
	return { [g[#g]] = 1 }
end

export type Ctx = {
	stance: string,
	speed: number, -- m/s, horizontal
	active: boolean, -- no chão, vivo, de pé no Humanoid (sem pulo, nado, escada, assento, transpor)
	moving: boolean, -- estado anterior (histerese)
}

-- Pesos-alvo de cada clipe da camada de locomoção e o novo "andando". Clipe sem id fica de fora;
-- sem nenhum clipe na postura, a camada sai e ficam o Animate e as poses do PostureController.
function SoldierAnims.targets(c: Ctx): ({ [string]: number }, boolean)
	if not c.active then
		return {}, false
	end
	local on = SoldierAnims.MOVE_ON[c.stance] or 0.25
	local off = SoldierAnims.MOVE_OFF[c.stance] or 0.1
	local moving = if c.moving then c.speed > off else c.speed > on
	local w: { [string]: number }
	if c.stance == "prone" then
		w = if moving then { rastejar = 1 } else { deitado = 1 }
	elseif c.stance == "crouch" then
		w = if moving then { agachado_andar = 1 } else { agachado = 1 }
	else
		w = if moving then SoldierAnims.gaitWeights(c.speed) else { parado = 1 }
	end
	local out: { [string]: number } = {}
	local total = 0
	for name, v in w do
		if SoldierAnims.id(name) ~= 0 and v > 1e-3 then
			out[name] = v
			total += v
		end
	end
	if total > 0 and total < 1 - 1e-6 then
		for name, v in out do
			out[name] = v / total -- um clipe da mistura sem id: os outros cobrem
		end
	end
	return out, moving
end

-- Ciclos de passada por segundo para a mistura (todos os clipes da passada começam no apoio do pé
-- esquerdo, então tocando na mesma frequência ficam em fase).
function SoldierAnims.cycleRate(weights: { [string]: number }, speed: number): number
	local stride = 0
	for name, v in weights do
		local c = SoldierAnims.CLIPS[name]
		if c and c.cycles > 0 then
			stride += v * c.speed * SoldierAnims.SCALE * c.length / c.cycles
		end
	end
	return if stride > 0 then speed / stride else 0
end

-- Velocidade de reprodução (AdjustSpeed) de um clipe da passada na frequência dada.
function SoldierAnims.trackSpeed(name: string, cycleRate: number): number
	local c = SoldierAnims.CLIPS[name]
	if not c or c.cycles <= 0 or cycleRate <= 0 then
		return 1
	end
	return math.clamp(cycleRate * c.length / c.cycles, SoldierAnims.RATE_MIN, SoldierAnims.RATE_MAX)
end

-- Tempo de mistura de uma postura para outra (s), a partir do tempo da câmera (Shared/Movement).
function SoldierAnims.fadeTime(from: string, to: string, dive: boolean?): number
	if from == to then
		return SoldierAnims.FADE_IDLE
	end
	local t = Movement.stanceTime(from, to, dive)
	if from == "prone" or to == "prone" then
		return math.min(t, SoldierAnims.FADE_PRONE_MAX)
	end
	return t
end

-- Recarga: o clipe é tocado na duração que o servidor deu (WeaponController "reload_start").
function SoldierAnims.reloadSpeed(duration: number): number
	local c = SoldierAnims.CLIPS.recarregar
	return math.clamp(c.length / math.max(duration, 0.2), 0.25, 4)
end

-- Pernas na direção do movimento (o tronco segue a mira): guinada das pernas em relação à frente do
-- corpo e se a passada toca de trás para a frente (andando de costas). Ângulos em radianos.
SoldierAnims.LEG_YAW_MAX = math.rad(75)
SoldierAnims.BACKWARD_FROM = math.rad(110)
function SoldierAnims.legYaw(facing: number, moveDir: number, speed: number): (number, boolean)
	if speed < 0.3 then
		return 0, false
	end
	local a = (moveDir - facing + math.pi) % (2 * math.pi) - math.pi
	if math.abs(a) <= SoldierAnims.BACKWARD_FROM then
		return math.clamp(a, -SoldierAnims.LEG_YAW_MAX, SoldierAnims.LEG_YAW_MAX), false
	end
	local b = a - math.pi * (if a > 0 then 1 else -1)
	return math.clamp(b, -SoldierAnims.LEG_YAW_MAX, SoldierAnims.LEG_YAW_MAX), true
end

-- Ao mudar de HipHeight o HumanoidRootPart leva alguns quadros para descer ou subir: quanto falta
-- (studs, vertical; < 0 = ainda vai descer). dH = HipHeight novo − antigo; moved = quanto já andou.
function SoldierAnims.hipLag(dH: number, moved: number): number
	local m = math.clamp(moved, math.min(0, dH), math.max(0, dH))
	return dH - m
end

-- Quanto o HRP fica abaixo da altura de pé na postura do clipe, no corpo do jogo (studs): o da
-- gravação vezes SCALE (o Animator escala a Root na mesma proporção).
function SoldierAnims.bakedDrop(stance: string): number
	local b = SoldierAnims.BAKED
	local d = b.drop[stance]
	if not d then
		return 0
	end
	return (b.baseHip - math.max(b.baseHip - d, b.minHip)) * SoldierAnims.SCALE
end

-- Correção vertical da Root (studs, > 0 sobe) para a mistura de posturas que está tocando: cada
-- clipe conta com o HRP a bakedDrop(postura) abaixo da altura de pé, mas ele está a actualDrop
-- (inclui a descida que ainda falta). Na troca de postura os dois lados da mistura ficam no chão.
function SoldierAnims.rootLift(weights: { [string]: number }, actualDrop: number): number
	local total, lift = 0, 0
	for stance, w in weights do
		if w > 0 then
			total += w
			lift += w * (actualDrop - SoldierAnims.bakedDrop(stance))
		end
	end
	return if total > 1e-6 then lift / total else 0
end

-- ===== caído (D-107) =====
-- Pedido do dono: "os feridos estão de pé ao invés de deitados". Causa: o MedicalService só gravava
-- "Downed" e zerava a velocidade; nada deitava o corpo (o PostureService recusava postura caído) e o
-- SoldierAnimations tirava a camada de locomoção, ficando o "parado" do Animate em pé.
-- Agora:
-- - SERVIDOR (PostureService.setDowned): HipHeight do deitado, junta Root girada DE COSTAS
--   (pitchDeg) e erguida até as costas encostarem no chão (downedRootY), corpo no grupo do deitado
--   e a HumanoidRootPart fora das consultas (a bala não acerta a caixa em pé que sobra no ar);
-- - CLIENTES (Controllers/MorteFx): a pose de ferido (DOWNED_POSE) com respiração curta e mexendo
--   pouco, e a queda de FALL_S até o chão; ao ser reanimado, levanta em GETUP_S (SoldierAnimations).
SoldierAnims.DOWNED = {
	pitchDeg = 90, -- de costas, deitado reto (o bloco do R15 apoia costas, braços e pernas juntos)
	gap = 0.03, -- studs entre as costas e o chão
	fallS = 0.7, -- a queda até deitar (s)
	getUpS = 0.6, -- levantar ao ser reanimado (s)
}

-- Altura (studs) que a junta Root sobe no C0 deitado de costas: o quadril fica a meia espessura do
-- tronco acima do chão (a HumanoidRootPart, em pé, tem a base a hipHeight do chão).
function SoldierAnims.downedRootY(halfDepth: number, hipHeight: number): number
	return halfDepth + SoldierAnims.DOWNED.gap - hipHeight
end

-- Pose de ferido de costas (graus X, Y, Z de cada junta, no referencial de repouso do R15; X positivo
-- leva braço e perna para a frente e cabeça e tronco para TRÁS, Z abre para o lado, Y gira): cabeça
-- virada e um pouco erguida (o queixo para o peito), a mão esquerda segurando o flanco, o braço
-- direito largado no chão e o joelho esquerdo dobrado com o pé no chão. Conferida no FK do teste
-- (tests/luau/corpos.luau): nenhuma peça mais de 0,15 stud abaixo do chão; o pé dobrado fica
-- apoiado. O lado sai da semente (espelha).
-- stylua: ignore
SoldierAnims.DOWNED_POSE = {
	Waist         = { -1, 0, 0 },
	Neck          = { -12, 30, 0 },
	LeftShoulder  = { 0, -20, -5 },
	LeftElbow     = { 65, 0, 0 },
	LeftWrist     = { 0, 0, 0 },
	RightShoulder = { 0, 0, 35 },
	RightElbow    = { 15, 0, 0 },
	RightWrist    = { 0, 0, 0 },
	LeftHip       = { 48, 0, -6 },
	LeftKnee      = { -110, 0, 0 },
	LeftAnkle     = { -28, 0, 0 },
	RightHip      = { 3, 0, 8 },
	RightKnee     = { -6, 0, 0 },
	RightAnkle    = { -24, 0, 0 },
} :: { [string]: { number } }

local function mirrorName(n: string): string
	if string.sub(n, 1, 4) == "Left" then
		return "Right" .. string.sub(n, 5)
	elseif string.sub(n, 1, 5) == "Right" then
		return "Left" .. string.sub(n, 6)
	end
	return n
end

-- Pose no instante t (s) para a semente: respiração curta (~27/min) no tronco e na mão do flanco,
-- a cabeça que vira devagar, o joelho que balança e um braço que se mexe de vez em quando. Ímpar:
-- espelhada (o outro lado). Espelhar troca esquerda e direita e inverte Y e Z.
function SoldierAnims.downedPose(t: number, seed: number): { [string]: { number } }
	local ph = (seed % 97) * 0.37 -- fase própria de cada soldado
	local breath = math.sin(2 * math.pi * 0.45 * t + ph)
	local slow = math.sin(2 * math.pi * 0.07 * t + ph * 1.7)
	-- braço solto: um movimento curto a cada ~9 s
	local twitch = math.max(0, math.sin(2 * math.pi * 0.11 * t + ph * 2.3)) ^ 6
	local out: { [string]: { number } } = {}
	for name, a in SoldierAnims.DOWNED_POSE do
		out[name] = { a[1], a[2], a[3] }
	end
	out.Waist[1] += 1 * breath -- −2..0: o peito sobe, nunca entra no chão
	out.Neck[2] += 8 * slow
	out.Neck[1] += 2 * breath
	out.LeftShoulder[1] += 3 * breath
	out.LeftElbow[1] += 4 * breath
	out.RightElbow[1] += 25 * twitch
	out.RightShoulder[3] -= 6 * twitch
	out.LeftHip[3] += 4 * slow
	out.LeftKnee[1] += 4 * slow
	if seed % 2 == 1 then
		local m: { [string]: { number } } = {}
		for name, a in out do
			m[mirrorName(name)] = { a[1], -a[2], -a[3] }
		end
		return m
	end
	return out
end

-- Queda até deitar: e (0..1) do tempo desde a queda, suavizado; e o quanto os joelhos e o quadril
-- dobram no meio do caminho (0..1, zero no começo e no fim).
function SoldierAnims.fallBlend(elapsed: number): (number, number)
	local x = math.clamp(elapsed / SoldierAnims.DOWNED.fallS, 0, 1)
	return x * x * (3 - 2 * x), math.sin(math.pi * x)
end
-- dobra extra (graus) da queda, vezes o segundo valor de fallBlend
SoldierAnims.FALL_BUCKLE = { LeftKnee = -70, RightKnee = -70, LeftHip = 40, RightHip = 40, Waist = -15 } :: {
	[string]: number,
}

return SoldierAnims
