--!strict
-- Regras de spawn (Parte 10.1): espera longa, ondas, extras por tipo de ponto, sequência de
-- mortes, troca de papel e bloqueio por inimigo próximo ou setor em disputa.
local SpawnRules = {}

-- D-91 (pedido do dono, 2026-11-11, depois de jogar: "diminua o tempo de espera para 10 seg"; a
-- espera de 60 s + ondas de 20 s chegava a 75 s e parecia que não dava para nascer). Base de 10 s,
-- extras na mesma proporção (antes: 60 / 20 / 20 / 30 / 15 até 45 / 15).
-- 2026-11-12 (o dono pediu de novo "coloque 10 s para renascer"): a onda de 5 s arredondava para
-- cima e a espera ia de 10 a 15 s. Sem onda: a espera conta da queda de cada um e é exatamente 10 s
-- mais os extras. wave > 0 volta a alinhar às ondas contadas do início da partida.
SpawnRules.C = {
	minWait = 10,
	wave = 0,
	extraRallyCaptured = 5,
	extraGarrison = 8,
	streakStep = 4,
	streakMax = 12,
	streakWindow = 120,
	roleChange = 4,
	blockRadiusM = 75,
	newSectorDelay = 30,
	rallyBehindM = 60, -- atrás do ponto forte (D-95: mapa de 1 km; antes 100)
}

-- "squad": nascer junto de um companheiro do squad (espera igual à da reunião, sem extra)
export type Kind = "hq" | "rally" | "rally_captured" | "garrison" | "squad"

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

-- Instante em que o jogador pode renascer: espera mínima + extras, contados da queda. Com C.wave > 0,
-- alinhado à próxima onda de reforço (ondas a cada C.wave s contadas desde waveEpoch, o início da
-- partida); com 0 (o padrão desde 2026-11-12), sem onda.
function SpawnRules.readyAt(deathTime: number, extra: number, waveEpoch: number): number
	local C = SpawnRules.C
	local earliest = deathTime + C.minWait + extra
	if C.wave <= 0 then
		return earliest
	end
	local k = math.ceil((earliest - waveEpoch) / C.wave)
	return waveEpoch + k * C.wave
end

-- Ponto bloqueado? enemies: lista plana x1,z1,x2,z2,... em metros. radiusM: raio próprio do ponto
-- (o túnel avançado do VC); sem ele, C.blockRadiusM.
function SpawnRules.blocked(
	px: number,
	pz: number,
	enemies: { number },
	contested: boolean,
	openedAt: number?,
	now: number,
	radiusM: number?
): (boolean, string?)
	if contested then
		return true, "setor em disputa"
	end
	if openedAt and now < openedAt + SpawnRules.C.newSectorDelay then
		return true, "setor recém-capturado"
	end
	local r2 = (radiusM or SpawnRules.C.blockRadiusM) ^ 2
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

-- ===== túnel avançado do VC =====
-- 2026-11-12 (métrica de contato: no Offensive o VC defende ao lado da base dos EUA, e o QG dele fica
-- a ~217 s de marcha): uma boca de túnel (Shared/Tunnels) vira reunião PERMANENTE do VC, do tipo
-- "rally" (sem o extra de guarnição), bloqueada só por inimigo perto. Nunca para os EUA.
-- PLACEHOLDER de design.
SpawnRules.VC_FORWARD = {
	blockM = 50, -- bloqueado com inimigo a menos de 50 m
	minFromObjectiveM = 50, -- fora do raio de captura do ponto forte (não nasce em cima do ponto)
	exitM = 3, -- nasce a 3 m da boca, do lado do QG do VC (não em cima do poço)
}

export type TunnelMouth = { id: string, x: number, z: number, sector: number?, open: boolean }

-- Boca escolhida: intacta, fora de setor dos EUA e a pelo menos minFromObjectiveM do objetivo do VC
-- (objX, objZ); de preferência do lado do VC no eixo da frente (leste-oeste, como a rallyPosition: o
-- lado do QG do VC em X). Sem nenhuma desse lado (o VC defendendo a própria vila de An Cường (2),
-- com as bocas em volta), vale a de qualquer lado. Entre as que valem, a mais perto do objetivo.
-- Devolve a boca e o lugar de nascer (studs), ou nil.
function SpawnRules.vcForward(
	mouths: { TunnelMouth },
	owner: { string },
	objX: number,
	objZ: number,
	usX: number,
	usZ: number,
	vcX: number,
	vcZ: number,
	studM: number
): (TunnelMouth?, number?, number?)
	local C = SpawnRules.VC_FORWARD
	local best: TunnelMouth? = nil
	for _, sideOk in { false, true } do -- 1ª passada: só do lado do VC; 2ª: qualquer lado
		local bestD = math.huge
		for _, m in mouths do
			local d = math.sqrt((m.x - objX) ^ 2 + (m.z - objZ) ^ 2) * studM
			local usSide = (m.x - objX) * (usX - objX) > 0
			local enemyLand = m.sector ~= nil and owner[m.sector] == "US"
			if m.open and not enemyLand and (sideOk or not usSide) and d >= C.minFromObjectiveM and d < bestD then
				best, bestD = m, d
			end
		end
		if best then
			break
		end
	end
	if not best then
		return nil, nil, nil
	end
	local b = best :: TunnelMouth
	local dx, dz = vcX - b.x, vcZ - b.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return b, b.x, b.z
	end
	return b, b.x + dx / len * C.exitM / studM, b.z + dz / len * C.exitM / studM
end

-- ===== nascer no companheiro do squad =====
-- Pedido do dono (2026-11-12): "permita poder nascer com o batalhão". Um ponto por companheiro do
-- squad, além da reunião do squad. Todos os números são PLACEHOLDER de design (calibrar em playtest).
SpawnRules.MATE = {
	enemyM = 50, -- nenhum inimigo de pé a menos de 50 m do companheiro
	combatS = 10, -- nem tiro dado nem dano levado nos últimos 10 s
	minM = 2, -- o ponto fica a 2–4 m dele
	maxM = 4,
	stepDeg = 30, -- rumos testados: bem atrás dele e de 30 em 30° para os lados
	maxSideDeg = 90, -- até de lado; nunca na frente (do lado do inimigo)
	floorM = 1.5, -- o chão do ponto fica a até 1,5 m da altura do pé dele (sem telhado nem barranco)
	deepWaterM = 1.0, -- água mais funda que isto não serve (o riacho tem 0,6 m)
	tunnelRoofM = 1.5, -- terreno mais de 1,5 m acima da raiz dele: está no túnel
	noRoomS = 3, -- sem lugar livre: o ponto mostra o motivo por 3 s
}

export type MateCheck = {
	alive: boolean, -- vivo e em campo (com corpo)
	downed: boolean,
	inBounds: boolean,
	inVehicle: boolean,
	inTunnel: boolean,
	nearestEnemyM: number,
	sinceCombatS: number, -- desde o último tiro dado ou dano levado (math.huge = nunca)
	inContestedCapture: boolean, -- dentro do raio de captura de um ponto forte em disputa
}

-- Motivo da recusa (nil = pode nascer nele). O texto vai para o `why` do ponto na carta.
function SpawnRules.mateCheck(c: MateCheck): string?
	local C = SpawnRules.MATE
	if not c.alive then
		return "fora de campo"
	elseif c.downed then
		return "companheiro caído"
	elseif not c.inBounds then
		return "fora da área de combate"
	elseif c.inVehicle then
		return "em veículo"
	elseif c.inTunnel then
		return "no túnel"
	elseif c.inContestedCapture then
		return "na área de captura em disputa"
	elseif c.nearestEnemyM < C.enemyM then
		return string.format("inimigo a menos de %d m", C.enemyM)
	elseif c.sinceCombatS < C.combatS then
		return "em combate"
	end
	return nil
end

-- Dentro da área de captura de um ponto forte em disputa? points: { x, z, contested } no mesmo
-- quadro de (x, z); radius na mesma unidade.
function SpawnRules.inContestedCapture(
	x: number,
	z: number,
	points: { { x: number, z: number, contested: boolean } },
	radius: number
): boolean
	local r2 = radius * radius
	for _, p in points do
		if p.contested and (p.x - x) ^ 2 + (p.z - z) ^ 2 <= r2 then
			return true
		end
	end
	return false
end

-- Direção "atrás do companheiro" (vetor unitário no plano): oposta ao inimigo mais próximo; sem
-- inimigo conhecido, as costas dele (oposta ao rumo para onde olha).
function SpawnRules.behind(
	mx: number,
	mz: number,
	enemyX: number?,
	enemyZ: number?,
	lookX: number,
	lookZ: number
): (number, number)
	local dx, dz = -lookX, -lookZ
	if enemyX and enemyZ then
		dx, dz = mx - enemyX, mz - enemyZ
	end
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return 0, 1
	end
	return dx / len, dz / len
end

-- Lugares candidatos (em studs), na ordem de preferência: bem atrás a 3 m, depois a 2 e a 4 m; depois
-- ±30°, ±60° e ±90° em volta do "atrás". O servidor confere cada um com raios (chão, parede, água,
-- espaço para o corpo) e fica com o primeiro livre.
function SpawnRules.mateSpots(
	mx: number,
	mz: number,
	bx: number,
	bz: number,
	studM: number
): { { x: number, z: number } }
	local C = SpawnRules.MATE
	local dists = { (C.minM + C.maxM) / 2, C.minM, C.maxM }
	local base = math.atan2(bz, bx)
	local out = {}
	for k = 0, C.maxSideDeg, C.stepDeg do
		local signs: { number } = if k == 0 then { 1 } else { 1, -1 }
		for _, sgn in signs do
			local a = base + math.rad(k * sgn)
			local ux, uz = math.cos(a), math.sin(a)
			for _, d in dists do
				table.insert(out, { x = mx + ux * d / studM, z = mz + uz * d / studM })
			end
		end
	end
	return out
end

return SpawnRules
