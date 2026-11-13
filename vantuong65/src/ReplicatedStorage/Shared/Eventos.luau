--!strict
-- Eventos da partida (pedido do dono, 2026-11-12, depois de jogar a v36: "faça o jogo mais
-- interativo, com eventos e outras coisas"; métrica: "nos primeiros 3 minutos de gameplay, já tenha
-- tido pelo menos uma troca de tiros"). Regras puras, testadas no Lune (tests/luau/eventos.luau e
-- tests/luau/contato.luau). O servidor (Modules/EventosService) agenda, avisa e aplica; o dano é o das
-- explosões que já existem (ExplosionService + Shared/Explosive); a métrica é do ContatoService.
--
-- Cada evento tem a fonte histórica em `source` (W = artigo "Operation Starlite" da Wikipédia em
-- inglês, que resume Shulimson & Johnson, "U.S. Marines in Vietnam: The Landing and the Buildup,
-- 1965", USMC, 1978). Todos os números de jogo (avisos, duração, rodadas, CEP, recompensas) são
-- PLACEHOLDER de design.
local FireSupport = require(script and (script :: any).Parent.FireSupport or "./FireSupport") :: any

local Eventos = {}

Eventos.C = {
	firstAtS = 60, -- o primeiro evento (abertura) cai no minuto 1 da partida
	gapMinS = 120, -- depois, um evento a cada 2 a 3 min
	gapMaxS = 180,
	retryS = 15, -- sem alvo agora: tenta de novo em 15 s
	assaultS = 60, -- janela depois da barragem: quem toma ou segura o ponto ganha
	blockExtraM = 30, -- ponto de nascimento a até (alcance da barragem + 30 m) fica bloqueado no aviso
	hqSafeM = 200, -- nenhuma barragem a menos de 200 m de um QG
	shiftStepM = 10, -- a barragem recua de 10 em 10 m para longe dos amigos de quem pediu
	maxShiftM = 80, -- até 80 m; senão, não há barragem
	lzFromTargetM = 140, -- LZ da inserção: 140 m do ponto atacado, do lado de quem chega
	lzEnemyClearM = 60, -- e nenhum inimigo a menos de 60 m na hora de pousar
	lzHotM = 120, -- quem ataca a LZ: a até 120 m dela
	depotBehindM = 60, -- depósito: atrás do ponto forte do VC (como a reunião) ...
	depotSideM = 40, -- ... e 40 m para o lado (fora da clareira de nascer)
	escortM = 20, -- medevac: quem está a até 20 m quando o ferido sai leva a escolta
	-- métrica (ContatoService)
	contactM = 150, -- troca de tiros: atirou num inimigo ou levou tiro a até 150 m
	coneDeg = 8, -- "atirou num inimigo": ele está a até 8° da linha do tiro
	goalS = 180, -- meta do dono: primeira troca de tiros em até 3 min
}

export type Reward = { xp: number, cr: number, label: string }
export type Def = {
	id: string,
	name: string,
	side: string, -- quem o evento favorece: "US", "VC" ou "any" (o lado da vez)
	kind: string, -- "barrage" | "lz" | "medevac" | "depot" | "counter"
	rotation: boolean, -- entra no sorteio de 2 a 3 min (o contra-ataque é reação a uma captura)
	durationS: number,
	warnS: number?, -- aviso antes da barragem cair (8 a 10 s)
	explosive: string?, -- tipo do Shared/Explosive (dano e cratera de lá)
	rounds: number?,
	cepM: number?,
	intervalS: number?,
	line: boolean?, -- impactos em linha de 120 m (FireSupport.impacts)
	reward: Reward, -- para o lado favorecido
	rewardOther: Reward, -- para o outro lado (quem resiste, ataca a LZ, defende o depósito)
	source: string,
}

Eventos.DEFS = {
	naval = {
		id = "naval",
		name = "Apoio naval",
		side = "US",
		kind = "barrage",
		rotation = true,
		durationS = 0, -- aviso + rodadas + janela de assalto (calculado)
		warnS = 10,
		explosive = "naval_5in",
		rounds = 6,
		cepM = 45,
		intervalS = 2.5,
		reward = { xp = 120, cr = 12, label = "Assalto depois do tiro naval" },
		rewardOther = { xp = 120, cr = 12, label = "Ponto mantido sob tiro naval" },
		source = "W: os contratorpedeiros USS Orleck e USS Prichett e o cruzador USS Galveston deram apoio de "
			.. "fogo; Galveston e Orleck cobriram o desembarque de 18/08/1965",
	},
	air = {
		id = "air",
		name = "Ataque aéreo (A-4)",
		side = "US",
		kind = "barrage",
		rotation = true,
		durationS = 0,
		warnS = 8,
		explosive = "bomb_250lb",
		rounds = 4,
		cepM = 20,
		intervalS = 0.3,
		line = true,
		reward = { xp = 120, cr = 12, label = "Assalto depois do ataque aéreo" },
		rewardOther = { xp = 120, cr = 12, label = "Ponto mantido sob bombardeio" },
		source = "W: A-4 e F-4 dos MAG-11 e MAG-12 lançaram 18 t de bombas e napalm nas LZs antes do pouso; "
			.. "ataques aéreos sobre Nam Yên e a Colina 30. Aqui só bombas (o jogo não tem tipo de napalm)",
	},
	heli = {
		id = "heli",
		name = "Inserção de helicóptero",
		side = "US",
		kind = "lz",
		rotation = true,
		durationS = 100, -- 6 s descendo, 90 s pousado (ponto de nascimento), 4 s subindo
		reward = { xp = 60, cr = 6, label = "Inserção pela LZ" },
		rewardOther = { xp = 80, cr = 8, label = "Ataque à LZ" },
		source = "W: UH-34 dos HMM-261 e HMM-361 levaram o 2/4 às LZs Red, White e Blue; a Cia I do 3/7 "
			.. "chegou depois pelo HMM-163. A LZ Blue pousou em cima do 60º Batalhão do VC",
	},
	mortar = {
		id = "mortar",
		name = "Morteiro do VC",
		side = "VC",
		kind = "barrage",
		rotation = true,
		durationS = 0,
		warnS = 9,
		explosive = "mortar_82",
		rounds = 8,
		cepM = 40,
		intervalS = 2,
		reward = { xp = 120, cr = 12, label = "Assalto depois do morteiro" },
		rewardOther = { xp = 120, cr = 12, label = "Ponto mantido sob morteiro" },
		source = "W: morteiros e canhões sem recuo do VC atingiram a coluna de suprimento; duas granadas "
			.. "de 60 mm caíram sobre a tropa que avançava em An Cường",
	},
	medevac = {
		id = "medevac",
		name = "Resgate de feridos",
		side = "any",
		kind = "medevac",
		rotation = true,
		durationS = 120,
		reward = { xp = 50, cr = 5, label = "Atendido no resgate" },
		rewardOther = { xp = 40, cr = 4, label = "Escolta de ferido" },
		source = "W: helicópteros do MAG-16 evacuaram os feridos (foto no artigo); esquadras da Cia I foram "
			.. "evacuadas da Colina 30. O posto de socorro do VC é de design",
	},
	depot = {
		id = "depot",
		name = "Depósito de munição do VC",
		side = "VC",
		kind = "depot",
		rotation = true,
		durationS = 180,
		explosive = "bomb_250lb",
		reward = { xp = 150, cr = 15, label = "Depósito defendido" },
		rewardOther = { xp = 200, cr = 20, label = "Depósito do VC destruído" },
		source = "W: An Cường (2) tinha túneis interligados; os fuzileiros explodiram túneis e recolheram "
			.. "109 armas (mais de 40 na Colina 43). O depósito em si é de design",
	},
	counter = {
		id = "counter",
		name = "Contra-ataque",
		side = "any",
		kind = "counter",
		rotation = false,
		durationS = 120,
		reward = { xp = 250, cr = 25, label = "Setor retomado no contra-ataque" },
		rewardOther = { xp = 120, cr = 12, label = "Setor segurado no contra-ataque" },
		source = "Design: o artigo não descreve contra-ataque formal; o mais perto é o socorro à coluna de "
			.. "suprimento emboscada (W)",
	},
} :: { [string]: Def }

-- Ordem fixa para o sorteio (o mesmo rolo dá o mesmo evento).
Eventos.ORDER = { "naval", "air", "heli", "mortar", "medevac", "depot" }

-- Recompensas no formato de Progression.REWARDS: "evento_<id>" (lado favorecido) e
-- "evento_<id>_outro" (o outro lado). O EventosService registra na partida.
function Eventos.rewards(): { [string]: Reward }
	local out: { [string]: Reward } = {}
	for id, d in Eventos.DEFS do
		out["evento_" .. id] = d.reward
		out["evento_" .. id .. "_outro"] = d.rewardOther
	end
	return out
end

-- ===== ritmo =====
function Eventos.gap(roll: number): number
	local C = Eventos.C
	return C.gapMinS + math.clamp(roll, 0, 1) * (C.gapMaxS - C.gapMinS)
end

local function other(side: string): string
	return if side == "US" then "VC" else "US"
end
Eventos.other = other

-- Próximo evento: nunca o mesmo da vez anterior; o lado que teve menos eventos vem primeiro (empate:
-- o contrário do último). available[id] = há alvo para ele agora. Devolve (id, lado favorecido).
function Eventos.pick(
	lastId: string?,
	lastSide: string?,
	counts: { [string]: number },
	available: { [string]: boolean },
	roll: number
): (string?, string?)
	local us, vc = counts.US or 0, counts.VC or 0
	local want = if us < vc then "US" elseif vc < us then "VC" elseif lastSide then other(lastSide) else "US"
	local function candidates(sideOk: (s: string) -> boolean): { string }
		local out = {}
		for _, id in Eventos.ORDER do
			local d = Eventos.DEFS[id]
			if d.rotation and id ~= lastId and available[id] and sideOk(d.side) then
				table.insert(out, id)
			end
		end
		return out
	end
	local list = candidates(function(s: string): boolean
		return s == want or s == "any"
	end)
	if #list == 0 then
		list = candidates(function(_: string): boolean
			return true
		end)
	end
	if #list == 0 then
		return nil, nil
	end
	local id = list[1 + math.floor(math.clamp(roll, 0, 0.999999) * #list)]
	local side = Eventos.DEFS[id].side
	if side == "any" then
		side = want
	end
	return id, side
end

-- ===== barragens =====
-- Até onde a barragem pode ferir, a partir do centro (m): 3 CEP (quase todo impacto), meia linha e o
-- raio de baixas do explosivo.
function Eventos.reachM(d: Def, casualtyM: number): number
	return 3 * (d.cepM or 0) + (if d.line then 60 else 0) + casualtyM
end

-- Duração da barragem: aviso, as rodadas e a janela de assalto.
function Eventos.barrageS(d: Def): number
	return (d.warnS or 0) + ((d.rounds or 1) - 1) * (d.intervalS or 0) + Eventos.C.assaultS
end

-- Centro seguro: parte do ponto (cx, cz) e recua para (ax, az) (vetor unitário, para o fundo do
-- inimigo) de shiftStepM em shiftStepM até nenhum amigo de quem pediu ficar a menos de dangerM e o
-- centro ficar a hqSafeM dos dois QGs. friends e hqs em studs; nil se não houver lugar.
function Eventos.safeCenter(
	cx: number,
	cz: number,
	ax: number,
	az: number,
	friends: { { x: number, z: number } },
	dangerM: number,
	hqs: { { x: number, z: number } },
	studM: number
): (number?, number?)
	local C = Eventos.C
	local d = 0
	while d <= C.maxShiftM do
		local x, z = cx + ax * d / studM, cz + az * d / studM
		local ok = true
		for _, f in friends do
			if math.sqrt((f.x - x) ^ 2 + (f.z - z) ^ 2) * studM < dangerM then
				ok = false
				break
			end
		end
		for _, h in hqs do
			if ok and math.sqrt((h.x - x) ^ 2 + (h.z - z) ^ 2) * studM < C.hqSafeM then
				ok = false
			end
		end
		if ok then
			return x, z
		end
		d += C.shiftStepM
	end
	return nil, nil
end

-- Impactos (studs) e o instante de cada um, contado do aviso: o primeiro cai em warnS.
function Eventos.impacts(
	d: Def,
	cx: number,
	cz: number,
	headingRad: number,
	studM: number,
	rand: () -> number
): { { x: number, z: number, t: number } }
	local ability = {
		kind = if d.line then "line" else "salvo",
		rounds = d.rounds or 1,
		cepM = d.cepM or 0,
		intervalS = d.intervalS or 0,
	}
	local out = FireSupport.impacts(ability, cx, cz, headingRad, studM, rand)
	for _, imp in out do
		imp.t += d.warnS or 0
	end
	return out
end

-- Ponto a distM de (tx, tz) na direção de (hx, hz) (a base de quem chega), dentro da área com
-- insetM de folga. Studs.
function Eventos.towards(
	tx: number,
	tz: number,
	hx: number,
	hz: number,
	distM: number,
	studM: number,
	bounds: any,
	insetM: number
): (number, number)
	local dx, dz = hx - tx, hz - tz
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return tx, tz
	end
	local k = math.min(distM / studM, len)
	local x, z = tx + dx / len * k, tz + dz / len * k
	local e = insetM / studM
	return math.clamp(x, bounds.minX + e, bounds.maxX - e), math.clamp(z, bounds.minZ + e, bounds.maxZ - e)
end

-- ===== contra-ataque =====
-- Setores que mudaram de dono: quem perdeu (US/VC) e quem ficou.
function Eventos.losses(prev: { string }, now: { string }): { { sector: number, loser: string, holder: string } }
	local out: { { sector: number, loser: string, holder: string } } = {}
	for s, was in prev do
		local cur = now[s]
		if (was == "US" or was == "VC") and cur ~= nil and cur ~= was then
			local loser: string = was
			table.insert(out, { sector = s, loser = loser, holder = cur })
		end
	end
	return out
end

-- ===== métrica: primeira troca de tiros =====
-- O alvo está na linha do tiro? Tudo no plano, em studs; dir não precisa ser unitário.
function Eventos.inCone(
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	tx: number,
	tz: number,
	maxM: number,
	coneDeg: number,
	studM: number
): boolean
	local vx, vz = tx - ox, tz - oz
	local dist = math.sqrt(vx * vx + vz * vz)
	local dl = math.sqrt(dx * dx + dz * dz)
	if dist * studM > maxM or dl < 1e-9 then
		return false
	end
	if dist < 1e-6 then
		return true
	end
	local cos = (vx * dx + vz * dz) / (dist * dl)
	return cos >= math.cos(math.rad(coneDeg))
end

export type Metric = { times: { number } }

function Eventos.newMetric(): Metric
	return { times = {} }
end

function Eventos.addContact(m: Metric, seconds: number)
	table.insert(m.times, seconds)
end

-- Resumo: quem já trocou tiros (n, média, mediana, pior) e a fração dentro da meta, contando como
-- fora quem está em campo há mais de goalS sem nenhuma troca (late).
function Eventos.summary(
	m: Metric,
	late: number
): { n: number, mean: number, median: number, worst: number, within: number }
	local t = table.clone(m.times)
	table.sort(t)
	local n = #t
	local sum, inside = 0, 0
	for _, s in t do
		sum += s
		if s <= Eventos.C.goalS then
			inside += 1
		end
	end
	local median = 0
	if n > 0 then
		median = if n % 2 == 1 then t[(n + 1) // 2] else (t[n // 2] + t[n // 2 + 1]) / 2
	end
	return {
		n = n,
		mean = if n > 0 then sum / n else 0,
		median = median,
		worst = t[n] or 0,
		within = inside / math.max(n + late, 1),
	}
end

return Eventos
