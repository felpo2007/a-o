--!strict
-- Regras de spawn (Parte 10.1): espera longa, ondas, extras por tipo de ponto, sequência de
-- mortes, troca de papel e bloqueio por inimigo próximo ou setor em disputa.
local SpawnRules = {}

SpawnRules.C = {
	minWait = 60,
	wave = 20,
	extraRallyCaptured = 20,
	extraGarrison = 30,
	streakStep = 15,
	streakMax = 45,
	streakWindow = 120,
	roleChange = 15,
	blockRadiusM = 75,
	newSectorDelay = 30,
	rallyBehindM = 100, -- 80-120 m atrás do ponto forte
}

export type Kind = "hq" | "rally" | "rally_captured" | "garrison"

-- deaths: instantes das mortes anteriores (a última é a atual)
function SpawnRules.extraWait(kind: Kind, deaths: { number }, changedRole: boolean): number
	local C = SpawnRules.C
	local extra = 0
	if kind == "rally_captured" then
		extra += C.extraRallyCaptured
	elseif kind == "garrison" then
		extra += C.extraGarrison
	end
	-- mortes seguidas: cada morte a menos de 2 min da anterior soma 15 s (até 45 s)
	local streak = 0
	for i = #deaths, 2, -1 do
		if deaths[i] - deaths[i - 1] < C.streakWindow then
			streak += 1
		else
			break
		end
	end
	extra += math.min(C.streakMax, streak * C.streakStep)
	if changedRole then
		extra += C.roleChange
	end
	return extra
end

-- Instante em que o jogador pode renascer: espera mínima + extras, alinhado à próxima onda
-- de reforço (ondas a cada 20 s contadas desde waveEpoch, o início da partida).
function SpawnRules.readyAt(deathTime: number, extra: number, waveEpoch: number): number
	local C = SpawnRules.C
	local earliest = deathTime + C.minWait + extra
	local k = math.ceil((earliest - waveEpoch) / C.wave)
	return waveEpoch + k * C.wave
end

-- Ponto bloqueado? enemies: lista plana x1,z1,x2,z2,... em metros.
function SpawnRules.blocked(
	px: number,
	pz: number,
	enemies: { number },
	contested: boolean,
	openedAt: number?,
	now: number
): (boolean, string?)
	if contested then
		return true, "setor em disputa"
	end
	if openedAt and now < openedAt + SpawnRules.C.newSectorDelay then
		return true, "setor recém-capturado"
	end
	local r2 = SpawnRules.C.blockRadiusM ^ 2
	for i = 1, #enemies, 2 do
		local dx, dz = enemies[i] - px, enemies[i + 1] - pz
		if dx * dx + dz * dz < r2 then
			return true, "inimigo próximo"
		end
	end
	return false, nil
end

-- Ponto de reunião atrás do ponto forte, do lado oposto à frente.
-- Quadro local: +X = leste. A frente dos EUA é o oeste (-X); a do VC é o leste (+X).
function SpawnRules.rallyPosition(spX: number, spZ: number, owner: string, studM: number): (number, number)
	local d = SpawnRules.C.rallyBehindM / studM
	if owner == "US" then
		return spX + d, spZ
	end
	return spX - d, spZ
end

return SpawnRules
