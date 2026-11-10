--!strict
-- Modo Warfare (Parte 4): 5 setores em linha; só se ataca o setor vizinho a um setor próprio.
-- progress em [-1, 1]: +1 = EUA dono, -1 = VC dono, 0 = neutro.
local Capture = {}

Capture.C = {
	soloSeconds = 90, -- 1 atacante leva 90 s de neutro a dono
	maxSpeedup = 2.0, -- 4+ atacantes de vantagem: 45 s
	regenSeconds = 120, -- defensores sozinhos devolvem o ponto ao dono
	warfareMinutes = 75,
	skirmishMinutes = 20,
}

export type Owner = string -- "US" | "VC" | "Neutral"
export type State = { owner: { Owner }, progress: { number }, active: { boolean } }
export type Event = { kind: string, sector: number, team: Owner }

local SIGN = { US = 1, VC = -1 }

function Capture.new(initial: { Owner }, active: { boolean }?): State
	local st: State = { owner = {}, progress = {}, active = {} }
	for i, o in initial do
		st.owner[i] = o
		st.progress[i] = if o == "US" then 1 elseif o == "VC" then -1 else 0
		st.active[i] = if active then active[i] else true
	end
	return st
end

function Capture.owns(st: State, i: number, team: string): boolean
	return st.owner[i] == team
end

-- O time pode atacar o setor i? (não é dono e tem setor próprio vizinho)
function Capture.attackable(st: State, i: number, team: string): boolean
	if not st.active[i] or st.owner[i] == team then
		return false
	end
	local n = #st.owner
	local left = i > 1 and st.owner[i - 1] == team
	local right = i < n and st.owner[i + 1] == team
	-- no Skirmish (um setor ativo) qualquer time pode atacar
	local activeCount = 0
	for _, a in st.active do
		if a then
			activeCount += 1
		end
	end
	return left or right or activeCount == 1
end

-- counts[i] = { US = n, VC = m } (vivos e não incapacitados no raio do ponto forte)
function Capture.step(st: State, counts: { { US: number, VC: number } }, dt: number): { Event }
	local C = Capture.C
	local events: { Event } = {}
	for i = 1, #st.owner do
		if not st.active[i] then
			continue
		end
		local c = counts[i] or { US = 0, VC = 0 }
		local before = st.progress[i]
		local p = before
		if c.US > 0 and c.VC > 0 then
			-- disputado: nada muda
		elseif c.US > 0 or c.VC > 0 then
			local team: string = if c.US > 0 then "US" else "VC"
			local n = if c.US > 0 then c.US else c.VC
			local sign = SIGN[team]
			if st.owner[i] == team then
				-- defensor sozinho: regenera até o máximo
				p = math.clamp(p + sign * dt / C.regenSeconds, -1, 1)
			elseif Capture.attackable(st, i, team) then
				local speed = math.min(C.maxSpeedup, 1 + 0.25 * (n - 1))
				p = math.clamp(p + sign * speed * dt / C.soloSeconds, -1, 1)
			end
		end
		-- encaixa nos extremos para não depender de erro de arredondamento acumulado
		if p > 1 - 1e-9 then
			p = 1
		elseif p < -1 + 1e-9 then
			p = -1
		end
		st.progress[i] = p
		-- transições de dono
		local owner = st.owner[i]
		if owner ~= "Neutral" and ((owner == "US" and p <= 0) or (owner == "VC" and p >= 0)) then
			st.owner[i] = "Neutral"
			table.insert(events, { kind = "neutralized", sector = i, team = owner :: string } :: Event)
		end
		if p >= 1 and st.owner[i] ~= "US" then
			st.owner[i] = "US"
			table.insert(events, { kind = "captured", sector = i, team = "US" })
		elseif p <= -1 and st.owner[i] ~= "VC" then
			st.owner[i] = "VC"
			table.insert(events, { kind = "captured", sector = i, team = "VC" })
		end
	end
	return events
end

function Capture.count(st: State, team: string): number
	local n = 0
	for i, o in st.owner do
		if st.active[i] and o == team then
			n += 1
		end
	end
	return n
end

-- Próximo modo: o servidor público segue a rotação; o privado (fixed) fica no modo escolhido.
function Capture.nextMode(current: string, fixed: boolean, rotation: { string }): string
	if fixed then
		return current
	end
	for i, m in rotation do
		if m == current then
			return rotation[i % #rotation + 1]
		end
	end
	return rotation[1]
end

-- Vencedor: dono de todos os setores ativos na hora, ou mais setores ao fim do tempo.
function Capture.winner(st: State, elapsed: number, limitSeconds: number): string?
	local active = 0
	for _, a in st.active do
		if a then
			active += 1
		end
	end
	local us, vc = Capture.count(st, "US"), Capture.count(st, "VC")
	if us == active then
		return "US"
	elseif vc == active then
		return "VC"
	end
	if elapsed >= limitSeconds then
		if us > vc then
			return "US"
		elseif vc > us then
			return "VC"
		end
		return "draw"
	end
	return nil
end

return Capture
