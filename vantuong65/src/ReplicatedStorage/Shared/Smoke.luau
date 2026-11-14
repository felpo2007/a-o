--!strict
-- Fumaça (granada de fumaça): bloqueia VISÃO (bots, assistência de mira), não balas. As nuvens não
-- são peças consultáveis por raycast (senão parariam tiros); o teste é geométrico: segmento x esferas.
-- 2026-11-13 ("copie a granada de fumaça igual ao Front 44 e corrija seus defeitos"). Do Front 44
-- (Effects.SmokeCloud e Equipment.BlocksSight): 7 fontes (1 no meio e 6 em volta a 0,45 do raio),
-- a nuvem abre em ~1,5 s, afina nos últimos 4 s, as fontes param 7 s antes do fim, cinza-claro,
-- espoleta de 1,4 s. Defeitos corrigidos (de lá e daqui):
--   - estourava de uma vez: aqui o bloqueio já era o raio cheio no primeiro quadro; agora a visão e o
--     desenho crescem juntos (Smoke.factor) e a lata solta um jato antes da nuvem (Controllers/Fumaca);
--   - bloqueava depois de sumir: a peça ficava 12 s a mais na pasta; agora conta o relógio do servidor;
--   - atravessava parede: uma esfera só passava pela parede (o bot dentro da casa não via o quintal
--     da fumaça do lado de fora); agora são 7 sopros, cada um encurtado pela parede no caminho
--     (Smoke.layout, raios do servidor);
--   - não aparecia para todos: no Front 44 o cliente desenhava só no aviso (quem entrava depois não
--     via); aqui a nuvem é um modelo Persistent na pasta workspace.Smoke e cada cliente desenha o que
--     está lá (também quem chega depois ou volta do streaming);
--   - pesava demais: 1 emissor de 40/s no servidor (replicado a todos, ~480 partículas de 22 studs);
--     agora o desenho é local, cai com a opção de detalhe e com a distância e some longe.
-- Duração: o Front 44 usa 22 s (número de jogo); aqui fica a da granada M18 da época (D-42, 60 s;
-- a M18 queima de 50 a 90 s). Mudar é uma linha (DURATION_S).
local Smoke = {}

Smoke.DURATION_S = 60 -- PLACEHOLDER (D-42; M18 50–90 s)
Smoke.RADIUS_M = 6 -- PLACEHOLDER (raio útil da nuvem formada; no Front 44 15 studs = 3 alturas do boneco)
Smoke.FUSE_S = 1.4 -- Front 44 (espoleta M201A1: ~1,2–2 s; PLACEHOLDER)
Smoke.GROW_S = 1.5 -- Front 44: a nuvem abre em ~1,5 s
Smoke.THIN_S = 4 -- Front 44: afina nos últimos 4 s
Smoke.TAIL_S = 7 -- Front 44: as fontes param 7 s antes do fim (a fumaça que já saiu ainda some)
Smoke.HEIGHT_M = 1.2 -- centro dos sopros acima do chão (o soldado de 2 m some inteiro)
Smoke.RING_K = 0.45 -- Front 44: fontes em volta a 0,45 do raio
Smoke.CENTER_R = 0.6 -- raio do sopro do meio (fração do raio)
Smoke.RING_R = 0.55 -- raio dos sopros de volta: 0,45 + 0,55 = o raio inteiro
Smoke.RING = 6

export type Cloud = { x: number, y: number, z: number, r: number }
export type Puff = { x: number, y: number, z: number, r: number } -- relativo ao chão sob a lata

-- Força da nuvem (0..1) na idade age de uma nuvem de duração dur: abre em GROW_S e afina em THIN_S.
function Smoke.factor(age: number, dur: number): number
	if age < 0 or age > dur then
		return 0
	end
	return math.clamp(age / Smoke.GROW_S, 0, 1) * math.clamp((dur - age) / Smoke.THIN_S, 0, 1)
end

-- Direção do sopro i (1..RING) no chão: x, z
function Smoke.ringDir(i: number): (number, number)
	local a = (i - 1) / Smoke.RING * math.pi * 2
	return math.cos(a), math.sin(a)
end

-- Parede achada pelo raio da direção i do anel: distância d (studs) e a normal no chão (nx, nz),
-- virada para a nuvem.
export type Wall = { d: number, nx: number, nz: number }

-- Os 7 sopros de uma nuvem de raio R (studs), com a parede de cada direção do anel (nil = nada até R)
-- e o teto acima do centro (studs, nil = céu). Cada parede é um plano: nenhum sopro passa dela (nem
-- o do lado, que a cruzaria de viés); o do meio fica com no mínimo 0,35 R (a fumaça escorre pela
-- parede, não some).
function Smoke.layout(R: number, walls: { Wall? }, ceiling: number?): { Puff }
	local h = R * Smoke.HEIGHT_M / Smoke.RADIUS_M
	-- planos das paredes: ponto (px, pz) e normal (nx, nz)
	local planes: { { number } } = {}
	for i = 1, Smoke.RING do
		local w = walls[i]
		if w then
			local dx, dz = Smoke.ringDir(i)
			local n = math.sqrt(w.nx * w.nx + w.nz * w.nz)
			if n > 1e-3 then
				table.insert(planes, { dx * w.d, dz * w.d, w.nx / n, w.nz / n })
			end
		end
	end
	-- maior raio que cabe aquém de todas as paredes, para um sopro centrado em (x, z)
	local function room(x: number, z: number): number
		local best = math.huge
		for _, p in planes do
			local dist = (x - p[1]) * p[3] + (z - p[2]) * p[4]
			best = math.min(best, math.max(dist, 0))
		end
		return best
	end
	local hc = h
	local roof = math.huge
	if ceiling then
		-- sob um teto (casa, abrigo), a nuvem baixa e encolhe para caber
		hc = math.min(h, math.max(ceiling * 0.5, 0.5))
		roof = math.max(ceiling - hc, R * 0.25)
	end
	local out: { Puff } = {}
	local rc = math.clamp(room(0, 0), R * 0.35, R * Smoke.CENTER_R)
	table.insert(out, { x = 0, y = hc, z = 0, r = math.min(rc, roof) })
	for i = 1, Smoke.RING do
		local dx, dz = Smoke.ringDir(i)
		local c = R * Smoke.RING_K
		local w = walls[i]
		if w then
			c = math.min(c, w.d * 0.5) -- o centro fica deste lado da parede
		end
		-- colado numa parede (de outro raio): o sopro recua para o meio até caber um pouco de fumaça
		for _ = 1, 4 do
			if room(dx * c, dz * c) >= R * 0.15 then
				break
			end
			c *= 0.6
		end
		local r = math.min(room(dx * c, dz * c), R * Smoke.RING_R)
		table.insert(out, { x = dx * c, y = hc, z = dz * c, r = math.min(r, roof) })
	end
	return out
end

-- O segmento a→b passa por dentro de alguma nuvem?
function Smoke.blocks(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	clouds: { Cloud }
): boolean
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local len2 = dx * dx + dy * dy + dz * dz
	for _, c in clouds do
		local t = 0
		if len2 > 0 then
			t = math.clamp(((c.x - ax) * dx + (c.y - ay) * dy + (c.z - az) * dz) / len2, 0, 1)
		end
		local px, py, pz = ax + dx * t, ay + dy * t, az + dz * t
		if (px - c.x) ^ 2 + (py - c.y) ^ 2 + (pz - c.z) ^ 2 <= c.r * c.r then
			return true
		end
	end
	return false
end

-- Quão dentro da fumaça está o ponto (0 fora, 1 no miolo de um sopro): o véu da câmera.
function Smoke.density(x: number, y: number, z: number, clouds: { Cloud }): number
	local best = 0
	for _, c in clouds do
		if c.r > 0 then
			local d = math.sqrt((x - c.x) ^ 2 + (y - c.y) ^ 2 + (z - c.z) ^ 2)
			best = math.max(best, 1 - d / c.r)
		end
	end
	return math.clamp(best, 0, 1)
end

-- Nuvens ativas da pasta workspace.Smoke, no relógio do servidor `now` (sem now: o da hora, com um
-- cache curto: os bots perguntam muitas vezes por segundo). Cada nuvem é um Model com "T0" e "Dur"
-- e a peça "Centro" com um Attachment por sopro (atributo "R" em studs). A peça solta com "R" (o
-- formato antigo) ainda vale, do tamanho cheio.
local cache = { at = -1, folder = nil :: Instance?, list = {} :: { Cloud } }

local function collect(folder: Instance, now: number): { Cloud }
	local out: { Cloud } = {}
	for _, c in folder:GetChildren() do
		if c:IsA("Model") then
			local t0, dur = c:GetAttribute("T0"), c:GetAttribute("Dur")
			local center = c:FindFirstChild("Centro")
			if type(t0) == "number" and type(dur) == "number" and center then
				local k = Smoke.factor(now - t0, dur)
				if k > 0 then
					for _, a in center:GetChildren() do
						local r = a:GetAttribute("R")
						if a:IsA("Attachment") and type(r) == "number" then
							local p = a.WorldPosition
							table.insert(out, { x = p.X, y = p.Y, z = p.Z, r = r * k })
						end
					end
				end
			end
		elseif c:IsA("BasePart") then
			local r = c:GetAttribute("R")
			local p = c.CFrame.Position
			table.insert(out, { x = p.X, y = p.Y, z = p.Z, r = if type(r) == "number" then r else 20 })
		end
	end
	return out
end

function Smoke.clouds(folder: Instance?, now: number?): { Cloud }
	if not folder then
		return {}
	end
	if now then
		return collect(folder, now)
	end
	local clock = os.clock()
	if cache.folder == folder and clock - cache.at < 0.1 then
		return cache.list
	end
	cache.folder, cache.at = folder, clock
	cache.list = collect(folder, workspace:GetServerTimeNow())
	return cache.list
end

-- Atalho para quem tem dois pontos (bots, assistência): a fumaça de agora tapa a linha a→b?
function Smoke.sightBlocked(a: Vector3, b: Vector3): boolean
	local list = Smoke.clouds(workspace:FindFirstChild("Smoke"))
	if #list == 0 then
		return false
	end
	return Smoke.blocks(a.X, a.Y, a.Z, b.X, b.Y, b.Z, list)
end

return Smoke
