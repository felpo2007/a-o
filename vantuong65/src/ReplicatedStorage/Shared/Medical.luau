--!strict
-- Ferimentos e cura (Parte 10.2). Estado puro: o servidor é a autoridade, o cliente só mostra
-- os efeitos no corpo (respiração, visão, mancar). Valores INICIAIS, a calibrar em playtest.
local Medical = {}

Medical.C = {
	health = 100,
	bleed = { light = 0.5, grave = 1.5, arterial = 4.0 }, -- vida por segundo
	bandageSelf = 6,
	bandageOther = 4,
	tourniquet = 4,
	medicTreat = 10,
	medicHealTo = 75,
	reviveTime = 8,
	reviveHealth = 30,
	reviveBlur = 20,
	downWindow = 60,
	giveUpAfter = 15,
	soldierBandages = 2,
	soldierTourniquets = 1,
	medicBandages = 8,
	medicTourniquets = 2,
	headKillJ = 300, -- energia mínima para matar na cabeça
	torsoDownJ = 1500, -- energia que incapacita com um tiro no tronco
}

export type Wound = { zone: string, level: string }
export type State = {
	health: number,
	wounds: { Wound },
	armImpaired: boolean,
	legImpaired: boolean,
	downedAt: number?,
	dead: boolean,
	blurUntil: number,
	bandages: number,
	tourniquets: number,
}

function Medical.new(isMedic: boolean?): State
	local C = Medical.C
	return {
		health = C.health,
		wounds = {},
		armImpaired = false,
		legImpaired = false,
		downedAt = nil,
		dead = false,
		blurUntil = 0,
		bandages = if isMedic then C.medicBandages else C.soldierBandages,
		tourniquets = if isMedic then C.medicTourniquets else C.soldierTourniquets,
	}
end

function Medical.bleedRate(s: State): number
	local r = 0
	for _, w in s.wounds do
		r += Medical.C.bleed[w.level] or 0
	end
	return r
end

local function down(s: State, now: number): string
	s.health = 0
	if not s.downedAt then
		s.downedAt = now
	end
	return "downed"
end

-- zone: "head" | "torso" | "arm" | "leg"; roll: número em [0,1) da semente do tiro
function Medical.applyHit(s: State, zone: string, energyJ: number, roll: number, now: number): string
	if s.dead then
		return "dead"
	end
	local C = Medical.C
	if s.downedAt then
		-- atingido caído: um tiro de fuzil mata, de pistola não necessariamente
		if energyJ >= C.headKillJ then
			s.dead = true
			return "killed"
		end
		return "downed"
	end
	if zone == "head" then
		if energyJ >= C.headKillJ then
			s.dead = true
			s.health = 0
			return "killed"
		end
		table.insert(s.wounds, { zone = zone :: string, level = "grave" } :: Wound)
		return down(s, now)
	elseif zone == "torso" then
		if energyJ >= C.torsoDownJ then
			table.insert(s.wounds, { zone = zone :: string, level = "grave" } :: Wound)
			return down(s, now)
		end
		s.health -= math.min(90, 45 + energyJ / 50)
		table.insert(s.wounds, { zone = zone :: string, level = "grave" } :: Wound)
	else -- membros
		s.health -= math.min(45, 20 + energyJ / 250)
		local level = if energyJ >= C.torsoDownJ and roll < 0.2 then "arterial" else "grave"
		table.insert(s.wounds, { zone = zone :: string, level = level } :: Wound)
		if zone == "arm" then
			s.armImpaired = true
		else
			s.legImpaired = true
		end
	end
	if s.health <= 0 then
		return down(s, now)
	end
	return "wounded"
end

-- avança o tempo: sangramento e janela de reanimação
function Medical.tick(s: State, dt: number, now: number): string?
	if s.dead then
		return nil
	end
	if s.downedAt then
		if now - s.downedAt >= Medical.C.downWindow then
			s.dead = true
			return "died"
		end
		return nil
	end
	local r = Medical.bleedRate(s)
	if r > 0 then
		s.health -= r * dt
		if s.health <= 0 then
			return down(s, now)
		end
	end
	return nil
end

local function worst(s: State, levels: { string }): number?
	for _, lv in levels do
		for i, w in s.wounds do
			if w.level == lv then
				return i
			end
		end
	end
	return nil
end

-- curativo: grave -> leve; leve -> estancado (no ferimento mais grave não arterial)
function Medical.bandage(s: State): boolean
	if s.bandages <= 0 or s.downedAt or s.dead then
		return false
	end
	local i = worst(s, { "grave", "light" })
	if not i then
		return false
	end
	s.bandages -= 1
	if s.wounds[i].level == "grave" then
		s.wounds[i].level = "light"
	else
		table.remove(s.wounds, i)
	end
	return true
end

function Medical.tourniquet(s: State): boolean
	if s.tourniquets <= 0 or s.downedAt or s.dead then
		return false
	end
	local i = worst(s, { "arterial" })
	if not i then
		return false
	end
	s.tourniquets -= 1
	local zone = s.wounds[i].zone
	table.remove(s.wounds, i)
	if zone == "arm" then
		s.armImpaired = true
	else
		s.legImpaired = true
	end
	return true
end

-- tratamento completo do médico (10 s): para todo sangramento, imobiliza, vida até 75
function Medical.treat(s: State): boolean
	if s.downedAt or s.dead then
		return false
	end
	s.wounds = {}
	s.armImpaired = false
	s.legImpaired = false
	s.health = math.max(s.health, Medical.C.medicHealTo)
	return true
end

function Medical.revive(s: State, now: number): boolean
	if s.dead or not s.downedAt or now - s.downedAt >= Medical.C.downWindow then
		return false
	end
	s.downedAt = nil
	s.health = Medical.C.reviveHealth
	s.blurUntil = now + Medical.C.reviveBlur
	-- os ferimentos continuam, mas em nível leve (alguém precisa tratar)
	for _, w in s.wounds do
		w.level = "light"
	end
	return true
end

function Medical.canGiveUp(s: State, now: number): boolean
	return s.downedAt ~= nil and not s.dead and now - s.downedAt >= Medical.C.giveUpAfter
end

return Medical
