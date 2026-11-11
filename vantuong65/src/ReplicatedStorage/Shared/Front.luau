--!strict
-- Ritmo e clareza da frente (pedido do dono, 2026-11-11): "o primeiro contato demora uns 5 minutos",
-- "os bots lutam espalhados", "não fica claro o que está em disputa". Módulo puro, testado no Lune
-- (tests/luau/modo.luau):
--   - sorteio dos pontos fortes encadeado a partir da frente (o vizinho mais perto tem mais chance);
--   - reunião avançada: um ponto de inserção no setor próprio, a ~250 m do ponto forte atacado
--     (Parte 4: "pontos de reunião na borda dianteira dos setores dominados");
--   - ponto de reunião do squad (o líder planta onde está; só o squad nasce nele);
--   - objetivo do time (atacar ou defender) para o HUD.
-- Números: PLACEHOLDER de design, a calibrar no Studio (meta da Parte 4: primeiro contato 90–150 s
-- depois de nascer no ponto mais avançado).
local Front = {}

Front.C = {
	forwardM = 250, -- reunião avançada: distância mínima até o ponto forte atacado
	forwardStepM = 20, -- recua de 20 em 20 m até cair dentro do setor próprio
	insideM = 30, -- e fica 30 m para dentro da fronteira
	fanDeg = 75, -- leque de rumos em volta da direção do ponto forte próprio
	pickPower = 2, -- sorteio: peso 1/d² até o ponto já sorteado do setor vizinho (mais perto da frente)
	squadRallyEnemyM = 100, -- reunião do squad: nenhum inimigo a menos de 100 m
	squadRallyObjectiveM = 150, -- nem a menos de 150 m de ponto forte ativo que não é do time
	squadRallyCooldownS = 90, -- entre dois plantios do mesmo squad
	squadRallyHqM = 300, -- longe do QG inimigo
}

export type Point = { x: number, z: number }

-- Sorteio dos pontos fortes (1 por setor). first: setor sorteado sem peso (a frente inicial); os
-- outros, em cadeia para fora, com peso 1/d^pickPower até o ponto do vizinho já escolhido. Assim a
-- frente começa compacta e o próximo objetivo fica perto do anterior. roll() em [0, 1).
function Front.pickStrongpoints(
	bySector: { [number]: { any } },
	n: number,
	first: number,
	roll: () -> number
): { [number]: any }
	local out: { [number]: any } = {}
	local function choose(list: { any }, near: any?): any
		if not near or #list == 1 then
			return list[1 + math.floor(roll() * #list)]
		end
		local weights, total = {}, 0
		for i, sp in list do
			local d = math.max(math.sqrt((sp.x - near.x) ^ 2 + (sp.z - near.z) ^ 2), 1)
			weights[i] = 1 / d ^ Front.C.pickPower
			total += weights[i]
		end
		local r = roll() * total
		for i, w in weights do
			r -= w
			if r <= 0 then
				return list[i]
			end
		end
		return list[#list]
	end
	if bySector[first] then
		out[first] = choose(bySector[first], nil)
	end
	for s = first - 1, 1, -1 do
		if bySector[s] then
			out[s] = choose(bySector[s], out[s + 1])
		end
	end
	for s = first + 1, n do
		if bySector[s] then
			out[s] = choose(bySector[s], out[s - 1])
		end
	end
	return out
end

-- Setor por onde a cadeia do sorteio começa: a frente inicial de cada modo.
function Front.firstSector(mode: string, n: number): number
	if mode == "Offensive" then
		return n -- base dos EUA: o 1º setor atacado fica perto dela
	end
	return math.ceil(n / 2)
end

-- Pares (setor próprio, setor atacado) que ganham reunião avançada: setor ativo que não é do time
-- e tem um setor do time ao lado (a mesma regra do Capture.attackable).
function Front.forwardPairs(
	owner: { string },
	active: { boolean },
	faction: string
): { { own: number, target: number } }
	local out = {}
	local n = #owner
	for t = 1, n do
		if active[t] and owner[t] ~= faction then
			for _, s in { t - 1, t + 1 } do
				if s >= 1 and s <= n and owner[s] == faction then
					table.insert(out, { own = s, target = t })
				end
			end
		end
	end
	return out
end

-- Reunião avançada: o lugar do setor próprio mais perto do ponto forte atacado, a pelo menos
-- forwardM dele e insideM para dentro da fronteira (o ponto não fica em cima da linha). Procura num
-- leque de rumos em volta da direção do ponto forte próprio (±75°, de 15 em 15°), andando de
-- forwardStepM em forwardStepM. sectorAt(x, z) -> id do setor. nil se não houver lugar: fica a
-- reunião comum.
function Front.forwardRally(
	own: number,
	ownSp: Point,
	targetSp: Point,
	studM: number,
	sectorAt: (x: number, z: number) -> number?
): (number?, number?)
	local dx, dz = ownSp.x - targetSp.x, ownSp.z - targetSp.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1 then
		return nil, nil
	end
	local base = math.atan2(dz, dx)
	local step = Front.C.forwardStepM / studM
	local inside = Front.C.insideM / studM
	local maxD = len + 400 / studM
	local bestD, bx, bz = math.huge, nil :: number?, nil :: number?
	for k = -Front.C.fanDeg, Front.C.fanDeg, 15 do
		local a = base + math.rad(k)
		local ux, uz = math.cos(a), math.sin(a)
		local d = Front.C.forwardM / studM
		while d < math.min(maxD, bestD) do
			local x, z = targetSp.x + ux * d, targetSp.z + uz * d
			if sectorAt(x, z) == own and sectorAt(x - ux * inside, z - uz * inside) == own then
				bestD, bx, bz = d, x, z
				break
			end
			d += step
		end
	end
	return bx, bz
end

-- Reunião do squad: motivo da recusa (nil = pode). Distâncias em metros.
export type RallyCheck = {
	leader: boolean,
	alive: boolean,
	inBounds: boolean,
	inWater: boolean,
	nearestEnemyM: number,
	nearestObjectiveM: number, -- ponto forte ativo que não é do time
	enemyHqM: number,
	now: number,
	lastPlacedAt: number?,
}

function Front.squadRallyCheck(c: RallyCheck): string?
	local C = Front.C
	if not c.leader then
		return "só o líder do squad planta o ponto de reunião"
	elseif not c.alive then
		return "caído não planta"
	elseif not c.inBounds then
		return "fora da área de combate"
	elseif c.inWater then
		return "na água não dá"
	elseif c.nearestEnemyM < C.squadRallyEnemyM then
		return string.format("inimigo a menos de %d m", C.squadRallyEnemyM)
	elseif c.nearestObjectiveM < C.squadRallyObjectiveM then
		return string.format("perto demais do ponto forte (mín. %d m)", C.squadRallyObjectiveM)
	elseif c.enemyHqM < C.squadRallyHqM then
		return "perto demais do QG inimigo"
	elseif c.lastPlacedAt and c.now - c.lastPlacedAt < C.squadRallyCooldownS then
		return string.format(
			"aguarde %d s para plantar de novo",
			math.ceil(C.squadRallyCooldownS - (c.now - c.lastPlacedAt))
		)
	end
	return nil
end

-- Objetivo do time para o HUD: "attack" (setor a tomar) ou "defend" (setor próprio ameaçado ou da
-- frente), o setor e se ele está em disputa. Ataque vem antes: o time que pode avançar avança.
-- O setor de ataque segue o BotBrain.objective (os bots vão para o mesmo lugar).
function Front.objective(
	owner: { string },
	active: { boolean },
	faction: string,
	capturing: { [number]: string }?
): (string?, number?)
	local n = #owner
	-- defender: setor próprio que o outro lado está tomando agora ("" = ninguém, como vem no remote)
	if capturing then
		for i = 1, n do
			local c = capturing[i]
			if active[i] and owner[i] == faction and c ~= nil and c ~= "" and c ~= faction then
				return "defend", i
			end
		end
	end
	local attack: { number } = {}
	for i = 1, n do
		if active[i] and owner[i] ~= faction then
			local adj = (i > 1 and owner[i - 1] == faction) or (i < n and owner[i + 1] == faction)
			local only = true
			for j = 1, n do
				if j ~= i and active[j] then
					only = false
				end
			end
			if adj or only then
				table.insert(attack, i)
			end
		end
	end
	if #attack > 0 then
		table.sort(attack, function(a, b)
			return if faction == "US" then a > b else a < b
		end)
		return "attack", attack[1]
	end
	for i = 1, n do
		if active[i] and owner[i] == faction then
			local edge = (i > 1 and owner[i - 1] ~= faction) or (i < n and owner[i + 1] ~= faction)
			if edge then
				return "defend", i
			end
		end
	end
	return nil, nil
end

return Front
