--!strict
-- Corpo a corpo (D-94): faca, facão, baioneta e coronhada. Módulo PURO (sem Roblox), testado no Lune
-- (tests/luau/faca.luau); o servidor é a autoridade (FieldService, parte do corpo a corpo), o
-- cliente só anima (WeaponController, KnifeView, SoldierAnimations).
--
-- Golpes (tempos em s desde o pedido; a faca já na mão — o saque soma DRAW_S na 1ª vez):
--   estocada  antecipação (recua o braço) e estocada reta; certeira no tronco derruba (caído)
--   lado      golpe de lado (corte em arco) e volta; fere e sangra, não derruba sozinho
--   baioneta  estocada com o fuzil e a baioneta armada (M14/M6, Tipo 56, SKS)
--   coronhada golpe com a coronha (fuzil sem baioneta)
-- Todos os números são de PROJETO (PLACEHOLDER até playtest): sem fonte de tempo de golpe ou alcance.
-- Alcance: do peito de quem golpeia até o ponto mais próximo do corpo atingido (braço ~0,7 m +
-- lâmina + o passo do avanço). Cone: meia-abertura em torno da direção da mira; "certeira" = dentro
-- do cone estreito (PRECISE_DEG): a estocada certeira tem o dano cheio; fora dele, o de corte.
-- Dano: energia equivalente para Medical.applyHit (torsoDownJ 1500 derruba, headKillJ 300 mata):
--   tronco ≥ 1500 derruba; cabeça < 300 derruba sem matar (golpe na cabeça atordoa/fere grave);
--   membro ≥ 1500 tem 20% de corte arterial (Medical). Caído: qualquer golpe ≥ 300 mata.
local Melee = {}

Melee.STUD_M = 0.28
Melee.DRAW_S = 0.28 -- tirar a faca da bainha (a arma longa vai para a mão esquerda)
Melee.SHEATHE_AFTER_S = 1.3 -- sem golpe por isso, a faca volta à bainha
Melee.SHEATHE_S = 0.35
Melee.COMBO_S = 1.0 -- 2º toque até aqui depois do início da estocada: golpe de lado
-- faca na mão (3ª pessoa e clipes do tools/anim): pivô da faca (punho) no RightHand a (0, Y, 0),
-- ponta para o −Z da mão e fio para o −Y (os clipes giram a mão para isso)
Melee.HAND_GRIP_Y = -0.15
Melee.LAG_M = 0.3 -- folga de alcance no servidor (latência e o alvo andando)
Melee.LOS_PAD_M = 0.08 -- o raio de linha livre para antes do ponto (não pega o próprio alvo)
Melee.MAX_YAW_DEG = 75 -- direção pedida contra a frente do corpo (anti-trapaça)
Melee.MAX_PITCH_DEG = 70

export type Attack = {
	id: string,
	windup: number, -- antecipação (s)
	impact: number, -- instante do acerto (s)
	recover: number, -- fim do golpe; o próximo só depois (s)
	reachM: number,
	coneDeg: number,
	preciseDeg: number,
	weapon: string, -- "knife" | "rifle"
	energy: { [string]: number }, -- por zona: head | torso | arm | leg
	glancing: string?, -- fora do cone estreito vale o dano deste golpe
}

-- stylua: ignore
Melee.ATTACKS = {
	estocada  = { id = "estocada",  windup = 0.10, impact = 0.20, recover = 0.55, reachM = 1.8, coneDeg = 24, preciseDeg = 12, weapon = "knife",
		energy = { torso = 1600, head = 260, arm = 1500, leg = 1500 }, glancing = "lado" },
	lado      = { id = "lado",      windup = 0.12, impact = 0.24, recover = 0.60, reachM = 1.5, coneDeg = 55, preciseDeg = 55, weapon = "knife",
		energy = { torso = 700,  head = 260, arm = 900,  leg = 900 } },
	baioneta  = { id = "baioneta",  windup = 0.18, impact = 0.32, recover = 0.90, reachM = 2.1, coneDeg = 20, preciseDeg = 10, weapon = "rifle",
		energy = { torso = 1800, head = 280, arm = 1600, leg = 1600 }, glancing = "coronhada" },
	coronhada = { id = "coronhada", windup = 0.16, impact = 0.30, recover = 0.85, reachM = 1.4, coneDeg = 35, preciseDeg = 35, weapon = "rifle",
		energy = { torso = 250,  head = 250, arm = 250,  leg = 250 } },
} :: { [string]: Attack }

-- Faca de cada lado (Shared/Weapons.knives): o USMC leva a Ka-Bar; o VC, o facão (dao), que corta
-- mais do que fura (multiplicador da energia por golpe).
Melee.KNIFE = { US = "kabar", VC = "dao" }
Melee.KNIFE_MUL = {
	kabar = { estocada = 1, lado = 1 },
	dao = { estocada = 0.9, lado = 1.4 },
} :: { [string]: { [string]: number } }
-- baioneta de cada fuzil (só estes armam; FieldService.setBayonet)
Melee.BAYONET = { m14 = "m6", type56 = "type56", sks = "type56" }

-- Bot (reflexo no servidor, FieldService): inimigo à frente e perto o bastante golpeia.
Melee.BOT_REACH_M = 1.5
Melee.BOT_CONE_DEG = 50
Melee.BOT_CHANCE = 0.7 -- por oportunidade (4 por segundo)
Melee.BOT_COOLDOWN_S = 1.1

function Melee.get(id: string): Attack?
	return Melee.ATTACKS[id]
end

-- Golpe do pedido: com a baioneta armada, estocada de baioneta; fuzil sem baioneta e o jogador
-- pedindo "coronhada"; senão faca (estocada; o 2º toque dentro de COMBO_S vira golpe de lado).
function Melee.choose(bayonetFixed: boolean, wantRifle: boolean, lastAttack: string?, sinceLast: number): string
	if bayonetFixed then
		return "baioneta"
	end
	if wantRifle then
		return "coronhada"
	end
	if lastAttack == "estocada" and sinceLast <= Melee.COMBO_S then
		return "lado"
	end
	return "estocada"
end

-- Tempo até o acerto (s), contando o saque quando a faca ainda está na bainha.
function Melee.impactDelay(id: string, knifeOut: boolean): number
	local a = Melee.ATTACKS[id]
	if not a then
		return 0
	end
	local draw = if a.weapon == "knife" and not knifeOut then Melee.DRAW_S else 0
	return draw + a.impact
end

-- Intervalo mínimo entre dois pedidos aceitos (s): o golpe anterior precisa ter acabado.
function Melee.cooldown(id: string, knifeOut: boolean): number
	local a = Melee.ATTACKS[id]
	if not a then
		return math.huge
	end
	local draw = if a.weapon == "knife" and not knifeOut then Melee.DRAW_S else 0
	return draw + a.recover * 0.9 -- 10% de folga para a latência
end

-- Ângulo (graus) entre dois vetores dados por componentes.
function Melee.angleDeg(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local la = math.sqrt(ax * ax + ay * ay + az * az)
	local lb = math.sqrt(bx * bx + by * by + bz * bz)
	if la < 1e-9 or lb < 1e-9 then
		return 180
	end
	local c = math.clamp((ax * bx + ay * by + az * bz) / (la * lb), -1, 1)
	return math.deg(math.acos(c))
end

-- Direção pedida pelo cliente é aceitável? (finita, não nula, perto da frente do corpo e sem olhar
-- para trás ou para o céu). fx, fz = frente horizontal do corpo (HumanoidRootPart).
function Melee.dirOk(dx: number, dy: number, dz: number, fx: number, fz: number): boolean
	for _, v in { dx, dy, dz } do
		if v ~= v or math.abs(v) > 1e6 then
			return false
		end
	end
	local l = math.sqrt(dx * dx + dy * dy + dz * dz)
	if l < 1e-3 then
		return false
	end
	local pitch = math.deg(math.asin(math.clamp(dy / l, -1, 1)))
	if math.abs(pitch) > Melee.MAX_PITCH_DEG then
		return false
	end
	if dx * dx + dz * dz < 1e-6 then
		return false
	end
	return Melee.angleDeg(dx, 0, dz, fx, 0, fz) <= Melee.MAX_YAW_DEG
end

export type Candidate = {
	distM: number, -- do peito de quem golpeia ao ponto mais próximo da peça
	angDeg: number, -- entre a mira e esse ponto
	zone: string,
	key: any, -- quem (o servidor põe o modelo)
}

-- Melhor alvo dentro do alcance e do cone: o mais alinhado (e, empatado, o mais perto). Devolve o
-- candidato e se foi certeiro (dentro do cone estreito).
function Melee.pick(id: string, cands: { Candidate }, lagM: number?): (Candidate?, boolean)
	local a = Melee.ATTACKS[id]
	if not a then
		return nil, false
	end
	local reach = a.reachM + (lagM or 0)
	local best: Candidate? = nil
	local bestScore = math.huge
	for _, c in cands do
		if c.distM <= reach and c.angDeg <= a.coneDeg then
			local score = c.angDeg / a.coneDeg + 0.25 * c.distM / reach
			if score < bestScore then
				best, bestScore = c, score
			end
		end
	end
	if not best then
		return nil, false
	end
	return best, (best :: Candidate).angDeg <= a.preciseDeg
end

-- Energia equivalente do golpe (J) na zona; fora do cone estreito vale o golpe "glancing".
function Melee.energy(id: string, zone: string, precise: boolean, knife: string?): number
	local a = Melee.ATTACKS[id]
	if not a then
		return 0
	end
	local use = a
	if not precise and a.glancing then
		use = Melee.ATTACKS[a.glancing] or a
	end
	local e = use.energy[zone] or use.energy.torso
	local mul = knife and Melee.KNIFE_MUL[knife]
	if mul and a.weapon == "knife" then
		e *= mul[use.id] or 1
	end
	return e
end

-- O que o golpe faz (para o teste e para o registro): "derruba", "mata", "fere" na zona dada, contra
-- os limiares de Medical (torsoDownJ, headKillJ) passados aqui para o módulo seguir puro.
function Melee.outcome(energyJ: number, zone: string, downed: boolean, torsoDownJ: number, headKillJ: number): string
	if downed then
		return if energyJ >= headKillJ then "mata" else "nada"
	end
	if zone == "head" then
		return if energyJ >= headKillJ then "mata" else "derruba"
	elseif zone == "torso" then
		return if energyJ >= torsoDownJ then "derruba" else "fere"
	end
	return "fere"
end

-- Reflexo do bot: devolve o golpe (ou nil) contra um inimigo a distM e angDeg da frente do bot.
function Melee.botAttack(distM: number, angDeg: number, roll: number, sinceLast: number, faction: string): string?
	if distM > Melee.BOT_REACH_M or angDeg > Melee.BOT_CONE_DEG or sinceLast < Melee.BOT_COOLDOWN_S then
		return nil
	end
	if roll >= Melee.BOT_CHANCE then
		return nil
	end
	-- o facão do VC é de corte; a faca do fuzileiro, de estocada
	return if faction == "VC" then "lado" else "estocada"
end

return Melee
