--!strict
-- Decisões puras dos bots que completam o servidor (Parte 11). Sem API do Roblox: testável no Lune.
-- Bots usam as MESMAS regras de tiro, dano e spawn dos jogadores; aqui só se decide o que fazer.
local BotBrain = {}

BotBrain.C = {
	senseRangeM = 300, -- alcance de detecção com linha de visada
	reactionMin = 0.5, -- s
	reactionMax = 1.2,
	objectiveSpreadM = 30, -- espalhamento em volta do ponto forte
	stuckSeconds = 3,
}

-- Setor-alvo: o setor atacável pelo time (vizinho a um setor próprio). Se nenhum, defende a
-- linha de frente (setor próprio vizinho de um não-próprio). owner/active vêm do Capture.
function BotBrain.objective(owner: { string }, active: { boolean }, faction: string): number?
	local n = #owner
	local function own(i: number): boolean
		return owner[i] == faction
	end
	local candidates = {}
	for i = 1, n do
		if active[i] and not own(i) and ((i > 1 and own(i - 1)) or (i < n and own(i + 1))) then
			table.insert(candidates, i)
		end
	end
	-- Skirmish (um setor ativo): ataca o único ativo
	if #candidates == 0 then
		local onlyActive: number? = nil
		local count = 0
		for i = 1, n do
			if active[i] then
				count += 1
				onlyActive = i
			end
		end
		if count == 1 and onlyActive and not own(onlyActive) then
			return onlyActive
		end
	end
	if #candidates > 0 then
		-- EUA avançam para oeste (índice menor); VC para leste (índice maior)
		table.sort(candidates, function(a, b)
			return if faction == "US" then a > b else a < b
		end)
		return candidates[1]
	end
	for i = 1, n do
		if active[i] and own(i) and ((i > 1 and not own(i - 1)) or (i < n and not own(i + 1))) then
			return i
		end
	end
	return nil
end

-- Erro de pontaria (1σ, radianos): cresce com a distância, com movimento e cai com habilidade.
function BotBrain.aimSigma(distM: number, moving: boolean, skill: number): number
	local base = 0.006 * (1 + distM / 150)
	if moving then
		base *= 2.2
	end
	return base * (1.6 - math.clamp(skill, 0, 1))
end

function BotBrain.reaction(roll: number): number
	local C = BotBrain.C
	return C.reactionMin + (C.reactionMax - C.reactionMin) * roll
end

-- Tamanho da rajada e intervalo entre disparos, por tipo de arma
function BotBrain.burst(kind: string, roll: number): number
	if kind == "mg" then
		return 4 + math.floor(roll * 5) -- 4-8
	end
	return 1
end

function BotBrain.shotDelay(kind: string, rpm: number, inBurst: boolean, roll: number): number
	if inBurst then
		return 60 / rpm
	end
	if kind == "mg" then
		return 0.6 + roll * 0.8
	elseif kind == "pistol" then
		return 0.5 + roll * 0.6
	end
	return 0.8 + roll * 0.9 -- fuzil semiautomático: tiro pensado
end

return BotBrain
