--!strict
-- Movimento da infantaria (pedido do dono, 2026-11-11: "a melhor movimentação possível") e a
-- câmera de ombro da 3ª pessoa. Módulo PURO, testado no Lune (tests/luau/movimento.luau); o runtime
-- fica em Controllers/Movement.client e Controllers/ThirdPerson.client.
-- D-93 (pedido do dono depois de jogar: "a movimentação na água está toda bugada", "faça a
-- movimentação do personagem e dos veículos muito boa", "faça que os do Vietnã sejam mais rápidos"):
--   - água: o modo (seco, vadeando, nadando) sai da fundura do LEITO, com histerese; vadeando, o
--     Humanoid não entra no estado Swimming (o runtime desliga o estado);
--   - chão: a superfície só troca depois de lida igual por 0,3 s, e o fator do chão é suavizado;
--   - passo: arrancada rápida, corrida que embala, curva que gira a velocidade em vez de encolher;
--   - câmera: balanço preso à passada, inclinação nas curvas, cabeça com inércia, degrau suavizado,
--     tudo multiplicado pela opção de movimento da câmera (acessibilidade);
--   - lado: o VC, mais leve, anda, trota e corre 12% mais rápido (PLACEHOLDER).
-- Tudo em metros e segundos (o runtime converte com STUD_M). Os números são de DESIGN, escolhidos
-- pela fisiologia de referência e pelo ritmo do jogo; NENHUM foi medido em playtest (PLACEHOLDER).
local Units = require(script and (script :: any).Parent.Units or "./Units") :: any
local Weather = require(script and (script :: any).Parent.Weather or "./Weather") :: any

local Movement = {}
local STUD: number = Units.STUD_M
Movement.STUD_M = STUD

-- ===== velocidades-base (m/s): as mesmas do servidor (Units.Speed e MedicalService.apply) =====
-- São também as âncoras das animações (SoldierAnims.ANCHOR) e dos bots (BotLocomotion): não mudam
-- por lado. O lado multiplica por cima (Movement.factionSpeed).
Movement.WALK = Units.Speed.walk * STUD -- 1,4: caminhada (perna ferida)
Movement.JOG = Units.Speed.jog * STUD -- 3,1: andar padrão do jogo (trote)
Movement.SPRINT = Units.Speed.sprint * STUD -- 5,5: corrida
Movement.CROUCH = Movement.WALK * 0.6 -- 0,84
Movement.PRONE = Movement.WALK * 0.25 -- 0,35: rastejar
Movement.ADS = 1.8 -- andando com a arma no ombro
Movement.TRANSITION = 0.6 -- enquanto deita ou levanta
Movement.SWIM = 0.9
-- Corrida pela direção do pedido em relação à frente (cosseno): cheia até ~45° (W+D no teclado),
-- diminui até o trote em ~60°. Antes era um degrau em 0,6 (~53°): a velocidade caía aos trancos.
Movement.SPRINT_FORWARD = 0.5
Movement.SPRINT_FORWARD_FULL = 0.7
Movement.SPRINT_FULL_AT = 0.3 -- abaixo de 30% do fôlego a corrida perde velocidade até o trote
Movement.SPRINT_MAX_WATER_M = 0.45 -- com água acima do joelho não dá para correr
Movement.SPRINT_COUNT_MPS = Movement.JOG * 1.05 -- acima disto, com a corrida ligada, o fôlego gasta

-- ===== lado (D-93): o VC levava menos peso =====
-- Em 1965 o guerrilheiro do VC andava de sandália de pneu, cinto de pano, sem capacete nem colete,
-- com poucos carregadores; o fuzileiro dos EUA ia de coturno, capacete M1 e cinto M1956 cheio.
-- O VC anda, trota, corre e anda agachado 12% mais rápido e transpõe 10% mais rápido. Mira de ferro,
-- rastejar e nado não mudam: o tiro fica igual para os dois lados. Base do equipamento: 7 kg
-- (sandália, cinto de pano, cantil, chapéu) contra 11 kg. Tudo PLACEHOLDER (escolha de jogo).
export type FactionDef = { speed: number, baseKg: number, agility: number }
Movement.FACTION = {
	VC = { speed = 1.12, baseKg = 7, agility = 1.1 },
} :: { [string]: FactionDef }

local function factionDef(faction: string?): FactionDef?
	return if faction then Movement.FACTION[faction] else nil
end

-- Multiplicador de velocidade do lado (andar, trote, corrida, agachado). 1 para os EUA e sem lado.
function Movement.factionSpeed(faction: string?): number
	local f = factionDef(faction)
	return if f then f.speed else 1
end

-- Multiplicador de agilidade (transpor, escalar, subir degrau agachado): a duração divide por ele.
function Movement.factionAgility(faction: string?): number
	local f = factionDef(faction)
	return if f then f.agility else 1
end

-- Velocidade máxima que o SERVIDOR aplica no WalkSpeed (MedicalService.apply chama esta função), em
-- m/s. `faction` é opcional (os bots chamam com 4 argumentos e ficam na velocidade-base).
function Movement.serverSpeed(
	stance: string,
	sprinting: boolean,
	legImpaired: boolean,
	downed: boolean,
	faction: string?
): number
	if downed then
		return 0
	end
	local k = Movement.factionSpeed(faction)
	local v = if stance == "prone"
		then Movement.PRONE
		elseif stance == "crouch" then Movement.CROUCH * k
		elseif sprinting then Movement.SPRINT * k
		else Movement.JOG * k
	return if legImpaired then math.min(v, Movement.WALK * k) else v
end

-- ===== peso do equipamento =====
-- Base: uniforme, coturno, capacete, cinto com 2 cantis, kit de primeiros socorros e mochila leve
-- (PLACEHOLDER, ~11 kg; VC 7 kg). O resto vem da arma (Weapons.massLoadedKg) e do Kit.
Movement.BASE_KG = 11
Movement.ROLE_KG = {
	radio_operator = 10, -- rádio de mochila (PRC-10/PRC-25, ~10 kg com bateria)
	medic = 3, -- bolsa do corpsman
	engineer = 4, -- ferramentas e carga
	sapper = 2,
	mortar = 8, -- parte do morteiro e granadas
	anti_tank = 8, -- lançador e foguetes (a 2ª arma não está em Weapons)
} :: { [string]: number }
Movement.LOAD_FREE_KG = 15 -- até aqui o peso não muda a velocidade nem o fôlego

export type Load = {
	weaponsKg: number,
	magKg: number,
	mags: number, -- carregadores de reserva
	frags: number,
	smokes: number,
	bandages: number,
	role: string,
	faction: string?,
}

function Movement.baseKg(faction: string?): number
	local f = factionDef(faction)
	return if f then f.baseKg else Movement.BASE_KG
end

function Movement.loadKg(l: Load): number
	return Movement.baseKg(l.faction)
		+ l.weaponsKg
		+ l.mags * l.magKg
		+ l.frags * 0.45
		+ l.smokes * 0.54
		+ l.bandages * 0.1
		+ (Movement.ROLE_KG[l.role] or 0)
end

-- Fator de velocidade pelo peso: na corrida pesa mais (até −20%); no trote, até −10%.
function Movement.loadFactor(kg: number, sprint: boolean): number
	local over = math.max(kg - Movement.LOAD_FREE_KG, 0)
	if sprint then
		return math.max(1 - 0.008 * over, 0.8)
	end
	return math.max(1 - 0.003 * over, 0.9)
end

-- Multiplicador do gasto de fôlego pelo peso (35 kg acima do livre = o dobro).
function Movement.loadDrain(kg: number): number
	return math.max(1 + (kg - Movement.LOAD_FREE_KG) / 35, 0.85)
end

-- ===== chão =====
export type Surface = { speed: number, drain: number, grip: number, soft: boolean }
Movement.SURFACE = {
	firm = { speed = 1, drain = 1, grip = 1, soft = false }, -- terra batida, dique, madeira, peças
	grass = { speed = 1, drain = 1, grip = 1, soft = true }, -- capim (a chuva enlameia)
	forest = { speed = 0.93, drain = 1.1, grip = 0.95, soft = true }, -- folhas, raízes e cipó
	sand = { speed = 0.85, drain = 1.25, grip = 0.85, soft = true },
	mud = { speed = 0.72, drain = 1.4, grip = 0.75, soft = true },
	paddy = { speed = 0.62, drain = 1.5, grip = 0.65, soft = true }, -- lama do arrozal sob a água
	water = { speed = 0.85, drain = 1.3, grip = 0.7, soft = true }, -- leito do riacho (a fundura pesa à parte)
} :: { [string]: Surface }

-- Classifica o chão pelo material do terreno ou da peça e pelo atributo "Material" das peças do mapa.
function Movement.surfaceOf(material: string?, attr: string?, partName: string?): string
	if attr == "PaddyWater" then
		return "paddy"
	elseif partName == "Dike" or attr == "MudWall" then
		return "firm"
	elseif material == "Mud" then
		return "mud"
	elseif material == "Sand" then
		return "sand"
	elseif material == "LeafyGrass" then
		return "forest"
	elseif material == "Grass" then
		return "grass"
	elseif material == "Water" then
		return "water"
	end
	return "firm"
end

-- Arrozal (D-93): a lâmina d'água (peça sem colisão) fica 6 cm acima da MEDIANA do chão do tabuleiro
-- (AssetLoader.fitFeatures), então o capim do terreno fura a lâmina em metade dos pontos. O raio que
-- pegava "a primeira coisa" alternava arrozal (62%) e capim (100%) a cada passo. Agora: com a lâmina
-- na coluna até PADDY_BELOW_M abaixo do chão achado, o chão é arrozal.
Movement.PADDY_BELOW_M = 0.3

local function surface(s: string): Surface
	return Movement.SURFACE[s] or Movement.SURFACE.firm
end

-- Velocidade relativa no chão; chão mole fica até 10% pior na chuva (Weather.mudSpeed).
function Movement.surfaceSpeed(s: string, rain: number): number
	local d = surface(s)
	return d.speed * (if d.soft then Weather.mudSpeed(math.clamp(rain, 0, 1)) else 1)
end

function Movement.surfaceDrain(s: string): number
	return surface(s).drain
end

function Movement.surfaceGrip(s: string): number
	return surface(s).grip
end

-- Água acima dos pés (m): até a canela quase não pesa; no joelho (0,5 m) ~75%; na cintura (1 m) ~40%.
function Movement.waterFactor(depthM: number): number
	if depthM <= 0.15 then
		return 1
	end
	return math.max(1 - 0.6 * (depthM - 0.15) / 0.85, 0.3)
end

-- Rampa na direção do movimento (subida > 0, em m/m). Subir 20% → 78%; 40% → 56% (mínimo 40%).
-- Descer forte (> 20%) também freia: pisar firme para não escorregar.
function Movement.slopeFactor(grade: number): number
	if grade >= 0 then
		return math.max(1 - 1.1 * grade, 0.4)
	end
	return math.max(1 - 0.5 * math.max(-grade - 0.2, 0), 0.7)
end

-- Fator do chão inteiro (superfície, chuva, água e rampa); os bots usam o mesmo produto.
function Movement.groundFactor(s: string, rain: number, waterM: number, grade: number): number
	return Movement.surfaceSpeed(s, rain) * Movement.waterFactor(waterM) * Movement.slopeFactor(grade)
end

-- Superfície com espera: só troca depois de lida igual por SURFACE_HOLD_S (borda de tabuleiro, capim
-- furando a lâmina, raiz). O fator do chão ainda passa por Movement.approach com GROUND_TAU_S.
Movement.SURFACE_HOLD_S = 0.3
Movement.GROUND_TAU_S = 0.25
export type GroundState = { surface: string, seen: string, seenT: number }

function Movement.newGround(): GroundState
	return { surface = "firm", seen = "firm", seenT = 0 }
end

function Movement.surfaceStep(g: GroundState, seen: string, dt: number): string
	if seen == g.surface then
		g.seen, g.seenT = seen, 0
	elseif seen ~= g.seen then
		g.seen, g.seenT = seen, dt
	else
		g.seenT += dt
	end
	if g.seen ~= g.surface and g.seenT >= Movement.SURFACE_HOLD_S - 1e-9 then
		g.surface, g.seenT = g.seen, 0
	end
	return g.surface
end

-- Aproximação exponencial (constante de tempo tau, s).
function Movement.approach(x: number, target: number, tau: number, dt: number): number
	return x + (target - x) * (1 - math.exp(-dt / math.max(tau, 1e-3)))
end

-- ===== água do terreno (riacho e mar) =====
-- O modo sai da fundura do LEITO (superfície da água − fundo), que não depende de onde o corpo está.
-- Antes a fundura era medida até o pé: boiando, o pé subia, a "fundura" caía e o soldado alternava
-- nadar e andar. Vadeando (até o peito), o runtime desliga o estado Swimming do Humanoid: o soldado
-- anda no fundo, mais devagar e com passada pesada. Acima de SWIM_IN_M nada; volta a vadear abaixo
-- de SWIM_OUT_M (histerese). Soldado de 1,75 m: cintura ~1,0 m, peito ~1,3 m.
Movement.WADE_MIN_M = 0.05
Movement.SWIM_IN_M = 1.3
Movement.SWIM_OUT_M = 1.1
Movement.WATER_GRIP = 0.5 -- nadando: arranca e vira devagar, mas não como no ar
Movement.PRONE_MAX_WATER_M = 0.3 -- deitado, a cabeça fica fora até aqui
Movement.CROUCH_MAX_WATER_M = 0.8 -- agachado, até aqui

-- "dry" | "wade" | "swim". bedM = math.huge quando há água sem fundo ao alcance.
function Movement.waterMode(prev: string, bedM: number): string
	if bedM < Movement.WADE_MIN_M then
		return "dry"
	elseif bedM >= Movement.SWIM_IN_M or (prev == "swim" and bedM >= Movement.SWIM_OUT_M) then
		return "swim"
	end
	return "wade"
end

-- Postura possível na água (o runtime pede ao servidor quando muda).
function Movement.waterStance(stance: string, bedM: number): string
	if stance ~= "stand" and bedM > Movement.CROUCH_MAX_WATER_M then
		return "stand"
	elseif stance == "prone" and bedM > Movement.PRONE_MAX_WATER_M then
		return "crouch"
	end
	return stance
end

-- Aderência vadeando: a água segura a perna (arrancar e virar pesam mais); na cintura, 65%.
function Movement.wadeGrip(bedM: number): number
	return 1 - 0.35 * math.clamp((bedM - 0.15) / 0.85, 0, 1)
end

-- Fração da corrida pela direção do pedido (0 = trote, 1 = corrida cheia).
function Movement.sprintDir(forward: number): number
	return math.clamp(
		(forward - Movement.SPRINT_FORWARD) / (Movement.SPRINT_FORWARD_FULL - Movement.SPRINT_FORWARD),
		0,
		1
	)
end

-- ===== velocidade-alvo =====
export type SpeedCtx = {
	stance: string, -- "stand" | "crouch" | "prone"
	sprinting: boolean,
	aiming: boolean,
	downed: boolean,
	legImpaired: boolean,
	forward: number, -- cosseno entre o pedido de movimento e a frente (−1..1)
	stamina: number, -- 0..1
	loadKg: number,
	surface: string,
	waterM: number,
	grade: number,
	rain: number,
	transition: boolean, -- deitando ou levantando
	swimming: boolean,
	faction: string?, -- "VC" corre mais (Movement.FACTION)
	groundK: number?, -- fator do chão já suavizado (no lugar de superfície × água × rampa)
}

-- Velocidade-alvo em m/s (para pedido de movimento cheio; o analógico escala).
function Movement.targetSpeed(c: SpeedCtx): number
	if c.downed then
		return 0
	end
	local k = Movement.factionSpeed(c.faction)
	local dirK = Movement.sprintDir(c.forward)
	local v
	local sprint = false
	if c.stance == "prone" then
		v = Movement.PRONE
	elseif c.stance == "crouch" then
		v = Movement.CROUCH * k
	elseif c.sprinting and not c.aiming and dirK > 0 and c.waterM < Movement.SPRINT_MAX_WATER_M then
		local st = math.clamp(c.stamina / Movement.SPRINT_FULL_AT, 0, 1)
		v = (Movement.JOG + (Movement.SPRINT - Movement.JOG) * st * dirK) * k
		sprint = true
	else
		v = Movement.JOG * k
	end
	if c.aiming then
		v = math.min(v, Movement.ADS)
	end
	if c.legImpaired then
		v = math.min(v, Movement.WALK * k)
	end
	if c.transition then
		v = math.min(v, Movement.TRANSITION)
	end
	v *= Movement.loadFactor(c.loadKg, sprint)
	local g = c.groundK
	v *= if g then math.clamp(g, 0, 1) else Movement.groundFactor(c.surface, c.rain, c.waterM, c.grade)
	if c.swimming then
		v = math.min(v, Movement.SWIM)
	end
	return v
end

-- ===== inércia =====
-- accelStep: o modelo vetorial da D-68 (7 m/s² acelerando, 10 freando). Os bots usam (BotMove) e ficam
-- com ele. O jogador usa moveStep (D-93).
Movement.ACCEL = 7 -- m/s² acelerando: parado → trote em ~0,45 s; trote → corrida em ~0,35 s
Movement.DECEL = 10 -- m/s² freando: corrida → parado em ~0,55 s
Movement.AIR_GRIP = 0.1 -- no ar quase não há controle (o embalo continua)

-- Passo da velocidade horizontal (vx, vz) em direção à alvo (tx, tz), com aceleração limitada.
-- grip multiplica a aceleração (lama e arrozal pesam e escorregam; no ar, AIR_GRIP).
function Movement.accelStep(vx: number, vz: number, tx: number, tz: number, dt: number, grip: number): (number, number)
	local dx, dz = tx - vx, tz - vz
	local dl = math.sqrt(dx * dx + dz * dz)
	if dl < 1e-9 then
		return tx, tz
	end
	local accelerating = (tx * tx + tz * tz) >= (vx * vx + vz * vz) and (tx * vx + tz * vz) >= 0
	local step = (if accelerating then Movement.ACCEL else Movement.DECEL) * grip * dt
	if step >= dl then
		return tx, tz
	end
	return vx + dx / dl * step, vz + dz / dl * step
end

-- D-93: o passo do jogador. O módulo da velocidade e a direção andam separados:
--   - arrancada: 11 m/s² no primeiro passo, caindo para 5 m/s² perto da corrida (o embalo pesa);
--   - parada: 12 m/s² (corrida → parado em ~0,45 s; trote → parado em ~0,25 s);
--   - curva: a direção gira até a aceleração lateral TURN_LAT (16 m/s² no chão firme; trote ~300°/s,
--     corrida ~170°/s) SEM perder velocidade. O modelo vetorial cortava caminho pela corda: no
--     A↔D ou numa curva de 90° a velocidade caía a 70% e o passo parecia patinar;
--   - meia-volta (mais de ~110°): freia e arranca para o outro lado.
Movement.ACCEL_LOW = 11
Movement.ACCEL_HIGH = 5
Movement.DECEL_MOVE = 12
Movement.TURN_LAT = 16
Movement.TURN_MAX = 8 -- rad/s (devagar a direção vira quase na hora)
Movement.TURN_MIN_MPS = 0.5 -- abaixo disto a velocidade é tratada como vetor (arrancada)
Movement.REVERSE_COS = -0.35

function Movement.accelAt(speed: number): number
	local u = math.clamp(speed / Movement.SPRINT, 0, 1)
	return Movement.ACCEL_LOW + (Movement.ACCEL_HIGH - Movement.ACCEL_LOW) * u
end

local function vecToward(vx: number, vz: number, tx: number, tz: number, step: number): (number, number)
	local dx, dz = tx - vx, tz - vz
	local dl = math.sqrt(dx * dx + dz * dz)
	if dl <= step or dl < 1e-9 then
		return tx, tz
	end
	return vx + dx / dl * step, vz + dz / dl * step
end

function Movement.moveStep(vx: number, vz: number, tx: number, tz: number, dt: number, grip: number): (number, number)
	local sp = math.sqrt(vx * vx + vz * vz)
	local ts = math.sqrt(tx * tx + tz * tz)
	if ts < 1e-6 or sp < Movement.TURN_MIN_MPS then
		local accelerating = ts * ts >= sp * sp and (tx * vx + tz * vz) >= 0
		local a = if accelerating then Movement.accelAt(sp) else Movement.DECEL_MOVE
		return vecToward(vx, vz, tx, tz, a * grip * dt)
	end
	local cos = (vx * tx + vz * tz) / (sp * ts)
	if cos < Movement.REVERSE_COS then
		return vecToward(vx, vz, tx, tz, Movement.DECEL_MOVE * grip * dt)
	end
	-- direção: gira no máximo pela aceleração lateral
	local ang = math.acos(math.clamp(cos, -1, 1))
	local rate = math.min(Movement.TURN_MAX, Movement.TURN_LAT * grip / sp)
	local turn = math.min(ang, rate * dt) * (if vx * tz - vz * tx >= 0 then 1 else -1)
	local c, s = math.cos(turn), math.sin(turn)
	local ux, uz = vx / sp, vz / sp
	local dx, dz = ux * c - uz * s, ux * s + uz * c
	-- módulo
	local ns
	if ts > sp then
		ns = math.min(sp + Movement.accelAt(sp) * grip * dt, ts)
	else
		ns = math.max(sp - Movement.DECEL_MOVE * grip * dt, ts)
	end
	return dx * ns, dz * ns
end

-- ===== fôlego =====
export type Stamina = { value: number, exhausted: boolean, rest: number }
Movement.SPRINT_S = 24 -- corrida contínua do descansado até zerar, com até 15 kg, em chão firme
Movement.EXHAUSTED_UNTIL = 0.35 -- sem fôlego: só volta a correr acima disto
Movement.RECOVER_DELAY = 1.2 -- s depois do último esforço para começar a recuperar
Movement.RECOVER = { still = 0.07, crouch = 0.085, prone = 0.1, walk = 0.045, jog = 0.012 }
Movement.COST = { jump = 0.07, vault = 0.05, mantle = 0.1, dive = 0.08 }

export type Effort = {
	kind: string, -- "sprint" | "jog" | "walk" | "still"
	stance: string,
	surface: string,
	grade: number,
	loadKg: number,
	waterM: number,
	regen: number?, -- multiplica a recuperação (cantil extra do equipamento liberado, D-72)
}

function Movement.newStamina(): Stamina
	return { value = 1, exhausted = false, rest = Movement.RECOVER_DELAY }
end

-- D-89 (pedido do dono, 2026-11-11: "permita correr sem perder a stamina"): a corrida não gasta
-- fôlego. Correndo, o fôlego se comporta como no trote, mas nunca cai (o que pulo, transposição e
-- mergulho gastaram volta devagar). O modelo antigo (24 s de corrida até zerar) fica atrás da chave.
Movement.SPRINT_FREE = true

-- Variação do fôlego por segundo (negativa = cansando).
function Movement.staminaRate(e: Effort): number
	local load = Movement.loadDrain(e.loadKg)
	local up = math.max(e.grade, 0)
	local water = math.max(e.waterM - 0.15, 0)
	if e.kind == "sprint" and Movement.SPRINT_FREE then
		local jog = table.clone(e)
		jog.kind = "jog"
		return math.max(Movement.staminaRate(jog), 0)
	elseif e.kind == "sprint" then
		return -(1 / Movement.SPRINT_S) * load * Movement.surfaceDrain(e.surface) * (1 + 3 * up) * (1 + water)
	elseif e.kind == "jog" then
		-- trote: no plano firme recupera devagar; subida, lama e água cansam
		local cost = (Movement.surfaceDrain(e.surface) - 1) * 0.03 + up * 0.12 + water * 0.04
		return Movement.RECOVER.jog / load - cost * load
	elseif e.kind == "walk" then
		return Movement.RECOVER.walk / load - up * 0.04 * load
	end
	local r = if e.stance == "prone"
		then Movement.RECOVER.prone
		elseif e.stance == "crouch" then Movement.RECOVER.crouch
		else Movement.RECOVER.still
	return r / math.sqrt(load)
end

function Movement.staminaStep(s: Stamina, dt: number, e: Effort)
	local r = Movement.staminaRate(e)
	if r < 0 then
		s.rest = 0
	else
		s.rest += dt
		if s.rest < Movement.RECOVER_DELAY then
			r = 0 -- recupera o ar antes de recuperar o fôlego
		else
			r *= math.clamp(e.regen or 1, 0.5, 2)
		end
	end
	s.value = math.clamp(s.value + r * dt, 0, 1)
	if s.value <= 0 then
		s.exhausted = true
	elseif s.exhausted and s.value >= Movement.EXHAUSTED_UNTIL then
		s.exhausted = false
	end
end

-- Gasto pontual (pulo, transpor, mergulho), escalado pelo peso.
function Movement.spend(s: Stamina, cost: number, loadKg: number)
	s.value = math.max(s.value - cost * Movement.loadDrain(loadKg), 0)
	s.rest = 0
	if s.value <= 0 then
		s.exhausted = true
	end
end

-- Pode começar (ou manter) a corrida?
function Movement.canSprint(s: Stamina): boolean
	return not s.exhausted and s.value > 0
end

-- Balanço da mira de ferro pelo cansaço (×1 descansado, ×3,5 sem fôlego).
function Movement.swayFactor(stamina: number): number
	local t = 1 - math.clamp(stamina, 0, 1)
	return 1 + 2.5 * t * t
end

-- Dispersão do tiro do quadril em 3ª pessoa (graus): a retícula não pode virar mira de ferro.
function Movement.hipSpreadDeg(speedMps: number, stamina: number, stance: string): number
	local base = if stance == "prone" then 0.6 elseif stance == "crouch" then 0.9 else 1.2
	return base + 0.5 * math.clamp(speedMps, 0, 6) + 1.2 * (1 - math.clamp(stamina, 0, 1))
end

-- ===== pulo =====
Movement.JUMP_REST_M = 0.45 -- descansado e com até 15 kg
Movement.JUMP_TIRED_M = 0.2
Movement.JUMP_MIN_M = 0.12
Movement.JUMP_MIN_STAMINA = 0.08
Movement.JUMP_COOLDOWN = 0.8 -- s depois de aterrissar (sem "coelhinho")

function Movement.jumpHeight(stamina: number, loadKg: number): number
	local h = Movement.JUMP_TIRED_M + (Movement.JUMP_REST_M - Movement.JUMP_TIRED_M) * math.clamp(stamina, 0, 1)
	h -= 0.006 * math.max(loadKg - Movement.LOAD_FREE_KG, 0)
	return math.max(h, Movement.JUMP_MIN_M)
end

-- JumpPower (studs/s) para subir heightM com a gravidade do workspace (studs/s²).
function Movement.jumpPower(heightM: number, gravityStuds: number): number
	return math.sqrt(2 * gravityStuds * heightM / STUD)
end

-- ===== aterrissagem =====
-- Pela altura da queda (m), não pela velocidade: a gravidade do Roblox (196,2 studs/s²) não é a real.
-- Devolve: afundada da câmera (m), fator de velocidade, duração do fator (s) e gasto de fôlego.
function Movement.landing(dropM: number): (number, number, number, number)
	if dropM < 0.25 then
		return 0, 1, 0, 0
	end
	local k = math.clamp((dropM - 0.25) / 2.5, 0, 1) -- 2,75 m ou mais = pior caso
	return 0.02 + 0.1 * k, 1 - 0.65 * k, 0.2 + 0.6 * k, 0.12 * k
end

-- ===== transpor / escalar (dique, cerca, sacos de areia, mureta até 1,25 m) =====
Movement.VAULT_MIN_M = 0.35 -- abaixo disto é passo ou pulo
Movement.VAULT_MAX_M = 1.25
Movement.VAULT_REACH_M = 0.9 -- distância máxima até a face do obstáculo
Movement.VAULT_CLEAR_M = 0.75 -- espaço livre acima do topo para o corpo passar
Movement.VAULT_MAX_DEPTH_M = 1.6 -- topo mais fundo que isto vira escalar (subir em cima)
Movement.VAULT_MAX_DROP_M = 2.5 -- queda máxima do outro lado
Movement.MANTLE_HEADROOM_M = 1.8 -- em cima, de pé

export type VaultProbe = {
	height: number?, -- m do topo acima dos pés (nil = nada à frente)
	distance: number, -- m até a face
	clearance: number, -- m livres acima do topo
	depth: number?, -- m de topo até a borda de trás (nil = além do alcance da sonda: plataforma)
	drop: number?, -- m do topo até o chão do outro lado (nil = sem chão até VAULT_MAX_DROP_M)
	headroom: number, -- m livres acima do topo para ficar de pé
	speed: number, -- m/s
	stamina: number,
	stance: string,
	legImpaired: boolean,
	loadKg: number,
	agility: number?, -- Movement.factionAgility (VC 1,1): a duração divide por ele
}
export type VaultPlan = { kind: string, duration: number, cost: number }

-- Decide transpor ("vault"), escalar ("mantle") ou nada (nil + motivo).
function Movement.vaultPlan(p: VaultProbe): (VaultPlan?, string)
	if p.stance ~= "stand" then
		return nil, "postura"
	elseif p.legImpaired then
		return nil, "perna ferida"
	elseif p.height == nil then
		return nil, "nada à frente"
	end
	local h = p.height :: number
	if h < Movement.VAULT_MIN_M then
		return nil, "baixo"
	elseif h > Movement.VAULT_MAX_M then
		return nil, "alto"
	elseif p.distance > Movement.VAULT_REACH_M then
		return nil, "longe"
	elseif p.clearance < Movement.VAULT_CLEAR_M then
		return nil, "sem espaço"
	elseif p.stamina <= 0.02 then
		return nil, "sem fôlego"
	end
	local kind
	if p.depth == nil or (p.depth :: number) > Movement.VAULT_MAX_DEPTH_M then
		if p.headroom < Movement.MANTLE_HEADROOM_M then
			return nil, "sem espaço em cima"
		end
		kind = "mantle"
	else
		if p.drop == nil or (p.drop :: number) > Movement.VAULT_MAX_DROP_M then
			return nil, "queda"
		end
		kind = "vault"
	end
	local base = if kind == "vault" then 0.55 else 0.95
	local tired = 1 + 0.4 * (1 - math.clamp(p.stamina, 0, 1))
	local heavy = 1 + math.max(p.loadKg - Movement.LOAD_FREE_KG, 0) / 60
	local tall = 1 + 0.4 * math.max(h - 0.6, 0)
	local run = if kind == "vault" and p.speed > 3 then 0.85 else 1
	local agile = math.clamp(p.agility or 1, 0.5, 2)
	local cost = if kind == "vault" then Movement.COST.vault else Movement.COST.mantle
	return { kind = kind, duration = base * tired * heavy * tall * run / agile, cost = cost }, "ok"
end

-- ===== degrau agachado ou deitado (D-93) =====
-- Agachado, o HumanoidRootPart fica a ~6 cm do chão (HipHeight 0,2) e batia na face do dique do
-- arrozal (35 cm ou mais): o soldado empacava e tinha de levantar. De pé o Humanoid sobe sozinho até
-- ~0,65 m; agachado ou deitado, um degrau baixo à frente vira uma passada assistida curta, sem
-- botão, na mesma postura.
Movement.STEP_MIN_M = 0.1
Movement.STEP_MAX_M = { crouch = 0.65, prone = 0.45 } :: { [string]: number }
Movement.STEP_REACH_M = 0.6
Movement.STEP_HEAD_M = { crouch = 1.0, prone = 0.45 } :: { [string]: number } -- espaço acima do topo
Movement.STEP_TIME = { crouch = 0.38, prone = 0.75 } :: { [string]: number }

export type StepProbe = {
	height: number?, -- m do topo acima dos pés
	distance: number, -- m até a face
	headroom: number, -- m livres acima do topo
	stance: string,
	legImpaired: boolean,
	agility: number?,
}

function Movement.stepPlan(p: StepProbe): (VaultPlan?, string)
	local maxH = Movement.STEP_MAX_M[p.stance]
	if not maxH then
		return nil, "postura"
	elseif p.height == nil then
		return nil, "nada à frente"
	end
	local h = p.height :: number
	if h < Movement.STEP_MIN_M then
		return nil, "baixo"
	elseif h > maxH then
		return nil, "alto"
	elseif p.distance > Movement.STEP_REACH_M then
		return nil, "longe"
	elseif p.headroom < Movement.STEP_HEAD_M[p.stance] then
		return nil, "sem espaço"
	end
	local agile = math.clamp(p.agility or 1, 0.5, 2)
	local dur = Movement.STEP_TIME[p.stance]
		* (1 + 0.8 * math.max(h - 0.2, 0))
		* (if p.legImpaired then 1.4 else 1)
		/ agile
	return { kind = "step", duration = dur, cost = 0 }, "ok"
end

-- ===== postura: tempo da transição (câmera e velocidade) =====
Movement.STANCE_TIME = {
	["stand>crouch"] = 0.28,
	["crouch>stand"] = 0.32,
	["stand>prone"] = 0.8,
	["prone>stand"] = 1.0,
	["crouch>prone"] = 0.6,
	["prone>crouch"] = 0.75,
} :: { [string]: number }
Movement.DIVE_TIME = 0.45 -- mergulho correndo: chega ao chão mais rápido
Movement.DIVE_MIN_MPS = 3.5 -- velocidade mínima para mergulhar em vez de deitar
Movement.DIVE_S = 0.5 -- duração do deslize do mergulho

function Movement.stanceTime(from: string, to: string, dive: boolean?): number
	if dive and to == "prone" then
		return Movement.DIVE_TIME
	end
	return Movement.STANCE_TIME[from .. ">" .. to] or 0.3
end

-- Envolve prone (deitar/levantar)? Nessas não se atira nem corre até terminar.
function Movement.isProneTransition(from: string, to: string): boolean
	return from ~= to and (from == "prone" or to == "prone")
end

-- Velocidade do deslize do mergulho (m/s) no instante t (s), a partir da velocidade de entrada.
function Movement.diveSpeed(v0: number, t: number): number
	local p = math.clamp(t / Movement.DIVE_S, 0, 1)
	return v0 * (1 - p) ^ 1.5
end

-- ===== câmera: passo, respiração e afundada =====
-- Passos por segundo pela velocidade (m/s): caminhada ~1,8; trote ~2,4; corrida ~3,4. Reserva: o
-- runtime usa a frequência da passada das animações (SoldierAnims.cycleRate) quando elas tocam.
function Movement.cadence(speedMps: number): number
	return math.clamp(1.2 + 0.4 * speedMps, 1.2, 3.4)
end

-- Deslocamento sutil da câmera (m): lado e altura. phase em rad, um ciclo = dois passos, 0 = apoio do
-- pé esquerdo (como os clipes da D-88): a cabeça desce no apoio e vai para o lado do pé apoiado.
-- waterM (opcional, fundura do leito): vadeando a passada é mais pesada (a perna sobe contra a água),
-- e o balanço segue o esforço (velocidade em relação à que a água deixa), não a velocidade crua.
function Movement.bob(
	phase: number,
	speedMps: number,
	stance: string,
	aiming: boolean,
	waterM: number?
): (number, number)
	local wet = math.clamp(((waterM or 0) - 0.15) / 0.85, 0, 1)
	local ref = Movement.JOG * (if wet > 0 then Movement.waterFactor(waterM :: number) else 1)
	local k = math.clamp(speedMps / ref, 0, 1.8)
	local ax, ay = 0.008 * k * (1 + 0.6 * wet), 0.012 * k * (1 + 1.2 * wet) -- trote: 0,8 cm e 1,2 cm
	if stance == "crouch" then
		ax, ay = ax * 0.8, ay * 0.6
	elseif stance == "prone" then
		ax, ay = ax * 1.2, ay * 0.3 -- rastejando, balança de lado
	end
	if aiming then
		ax, ay = ax * 0.35, ay * 0.35
	end
	return -ax * math.sin(phase), -ay * (math.abs(math.cos(phase)) - 2 / math.pi)
end

-- Nadando: a cabeça sobe e desce devagar com a braçada (m).
function Movement.swimBob(t: number): number
	return 0.025 * math.sin(2 * math.pi * 0.45 * t)
end

-- Respiração (m, vertical): mais funda e rápida sem fôlego.
function Movement.breath(t: number, stamina: number): number
	local tired = 1 - math.clamp(stamina, 0, 1)
	local amp = 0.002 + 0.006 * tired * tired
	local hz = 0.25 + 0.45 * tired
	return amp * math.sin(2 * math.pi * hz * t)
end

-- Curva de impulso da afundada (0 → pico −1 em tau → 0), multiplicada pela afundada em m.
function Movement.dipCurve(t: number, tau: number): number
	if t <= 0 then
		return 0
	end
	local x = t / tau
	return -x * math.exp(1 - x)
end

-- ===== câmera: degrau, cabeça com inércia e inclinação (D-93) =====
-- Opção de acessibilidade "movimento da câmera" (0..1; 1 = padrão): multiplica balanço, respiração,
-- afundada, inércia e inclinação. Não mexe na altura da postura nem na suavização do degrau.
function Movement.cameraScale(v: any): number
	return if type(v) == "number" and v == v then math.clamp(v, 0, 1) else 1
end

-- Degrau (dique, soleira, pedra): o Humanoid sobe o quadril de uma vez e a câmera pulava junto.
-- off = quanto a câmera está abaixo (−) ou acima (+) do corpo (m). dyM = quanto o corpo subiu neste
-- quadro; expectedM = o que a rampa explica (velocidade × inclinação): só o resto é suavizado, então
-- numa ladeira a câmera não atrasa.
Movement.STEP_TAU_S = 0.08
Movement.STEP_SMOOTH_MAX_M = 0.75

function Movement.stepSmooth(off: number, dyM: number, expectedM: number, dt: number): number
	local o = (off - (dyM - expectedM)) * math.exp(-dt / Movement.STEP_TAU_S)
	return math.clamp(o, -Movement.STEP_SMOOTH_MAX_M, Movement.STEP_SMOOTH_MAX_M)
end

-- Cabeça com inércia: massa e mola presas ao corpo. Arrancando, a cabeça fica um pouco para trás;
-- parando de repente, vai um pouco para a frente e volta; na curva, para fora. ax = aceleração para a
-- direita, az = para a frente (m/s², no rumo da câmera). Devolve em s.x (direita) e s.z (frente), m.
Movement.HEAD = { hz = 2.2, zeta = 0.7, gain = 0.4, maxM = 0.035 }
export type HeadState = { x: number, z: number, vx: number, vz: number }

function Movement.newHead(): HeadState
	return { x = 0, z = 0, vx = 0, vz = 0 }
end

function Movement.headStep(s: HeadState, ax: number, az: number, dt: number)
	local H = Movement.HEAD
	local w = 2 * math.pi * H.hz
	local n = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / n
	for _ = 1, n do
		s.vx += (-w * w * s.x - 2 * H.zeta * w * s.vx - H.gain * ax) * h
		s.x += s.vx * h
		s.vz += (-w * w * s.z - 2 * H.zeta * w * s.vz - H.gain * az) * h
		s.z += s.vz * h
	end
	s.x = math.clamp(s.x, -H.maxM, H.maxM)
	s.z = math.clamp(s.z, -H.maxM, H.maxM)
end

-- Inclinação lateral da câmera (rad; > 0 = cabeça para a esquerda, como CFrame.Angles(0, 0, a)):
-- para o lado do passo lateral e para dentro da curva. Mirando e deitado, nada (a mira de ferro fica
-- reta); agachado, menos. vRight em m/s, aRight em m/s² (para a direita > 0).
Movement.ROLL = { perMps = 0.22, perAccel = 0.06, maxDeg = 1.4, tau = 0.12 }

function Movement.rollTarget(vRight: number, aRight: number, stance: string, aiming: boolean): number
	if aiming or stance == "prone" then
		return 0
	end
	local R = Movement.ROLL
	local deg = math.clamp(-(R.perMps * vRight + R.perAccel * aRight), -R.maxDeg, R.maxDeg)
	return math.rad(if stance == "crouch" then deg * 0.6 else deg)
end

-- ===== 3ª pessoa (câmera de ombro) =====
-- Deslocamento a partir do olho (m): lado (ombro direito > 0), altura e distância para trás.
export type Shoulder = { side: number, up: number, back: number }
Movement.SHOULDER = {
	stand = { side = 0.55, up = 0.12, back = 2.1 },
	crouch = { side = 0.5, up = 0.15, back = 1.9 },
	prone = { side = 0.42, up = 0.38, back = 1.7 },
} :: { [string]: Shoulder }
Movement.CAM_RADIUS_M = 0.15 -- esfera da colisão da câmera
Movement.CAM_MARGIN_M = 0.08 -- folga da parede
Movement.FOLIAGE_MIN_M = 1.0 -- a folhagem só aproxima a câmera até 1 m do ombro
Movement.BODY_FADE_M = { 0.4, 0.9 } -- câmera mais perto que isto do ombro: o corpo some aos poucos
Movement.VIEW_TIME = { toggle = 0.28, adsIn = 0.1, adsOut = 0.2 }
Movement.VIEW_THRESHOLD = 0.5 -- acima disto a câmera está DE FATO em 3ª pessoa (ThirdPersonView)

function Movement.shoulder(stance: string): Shoulder
	return Movement.SHOULDER[stance] or Movement.SHOULDER.stand
end

-- Avança a mistura 1ª (0) ↔ 3ª (1) pessoa em direção ao alvo, percorrendo 0..1 em `time` s.
function Movement.viewStep(a: number, target: number, dt: number, time: number): number
	local step = dt / math.max(time, 1e-3)
	if a < target then
		return math.min(a + step, target)
	end
	return math.max(a - step, target)
end

function Movement.ease(a: number): number
	local x = math.clamp(a, 0, 1)
	return x * x * (3 - 2 * x)
end

export type ViewCtx = {
	want: boolean, -- o jogador escolheu 3ª pessoa
	allowed: boolean, -- o servidor permite (workspace "ThirdPersonAllowed")
	alive: boolean,
	customCamera: boolean, -- câmera do jogo (não a do lobby/tela de spawn)
	seated: boolean, -- veículo: nada muda
	downed: boolean,
	aiming: boolean, -- mira de ferro é em 1ª pessoa
	binoculars: boolean,
}

-- Alvo da mistura (0/1) e o tempo da transição.
function Movement.viewTarget(c: ViewCtx, wasAiming: boolean): (number, number)
	local base = c.want and c.allowed and c.alive and c.customCamera and not c.seated and not c.downed
	if not base then
		return 0, if c.seated or not c.customCamera then 0 else Movement.VIEW_TIME.toggle
	end
	if c.aiming or c.binoculars then
		return 0, Movement.VIEW_TIME.adsIn
	end
	return 1, if wasAiming then Movement.VIEW_TIME.adsOut else Movement.VIEW_TIME.toggle
end

-- Distância da câmera ao ombro: entra NA HORA numa parede (nunca atravessa); folhagem aproxima
-- rápido mas suave; volta devagar quando o caminho abre.
function Movement.boomStep(cur: number, target: number, dt: number, hard: boolean): number
	if target < cur then
		if hard then
			return target
		end
		return cur + (target - cur) * (1 - math.exp(-dt / 0.06))
	end
	return cur + (target - cur) * (1 - math.exp(-dt / 0.3))
end

-- Transparência local do próprio corpo em 3ª pessoa (câmera colada no ombro: o corpo some).
function Movement.bodyFade(boomM: number): number
	local a, b = Movement.BODY_FADE_M[1], Movement.BODY_FADE_M[2]
	return math.clamp((b - boomM) / (b - a), 0, 1)
end

-- ===== servidor: orçamento de corrida (anti-trapaça leve, PostureService) =====
-- Mais folgado que o do cliente (dura 50% mais, sem peso nem chão, e recupera mais rápido que o
-- melhor caso do cliente, sem a pausa): quem joga limpo cansa sempre antes no próprio cliente; só
-- quem ignora o fôlego bate neste teto (teste "servidor nunca corta antes do cliente"). A folga
-- também cobre a amostragem do servidor (4 Hz) em corridas curtas.
Movement.SERVER_SPRINT_S = Movement.SPRINT_S * 1.5
Movement.SERVER_RECOVER = 0.12
Movement.SERVER_MIN_TO_START = 1e-3

function Movement.serverBudgetStep(b: number, dt: number, sprinting: boolean): number
	if sprinting and Movement.SPRINT_FREE then
		return b -- corrida livre (D-89): o servidor não corta
	elseif sprinting then
		return math.max(b - dt / Movement.SERVER_SPRINT_S, 0)
	end
	return math.min(b + dt * Movement.SERVER_RECOVER, 1)
end

return Movement
