--!strict
-- Rota estratégica dos bots e dos blindados de bot (D-90). Módulo PURO, testado no Lune
-- (tests/luau/botsmov.luau); o runtime é o Modules/BotWorld, que preenche a grade com o mapa.
--   - grade de 16 studs (4,48 m), a mesma do terreno (WorldData), com a paisagem (Landscape) e
--     marcas do mapa por célula: mar, riacho, lâmina de arrozal, dique, sebe, casa, trincheira;
--   - custo por célula de cada perfil (infantaria, lagarta, anfíbio; BotBrain.NAV): arrozal
--     alagado caro, dique e sebe baratos; rampa cara; casa e sebe param a lagarta;
--   - A* com heurística inflada (BotBrain.NAV.weight) que roda em fatias (run com teto de nós):
--     nenhum quadro do servidor trava;
--   - rota simplificada por linha reta que não sai mais cara (pontos a dezenas de metros).
-- Posições em studs no quadro do jogo (X leste, Z sul).
local BotBrain = require(script and (script :: any).Parent.BotBrain or "./BotBrain") :: any

local BotNav = {}

BotNav.F = {
	SEA = 1,
	STREAM = 2,
	PADDY = 4,
	DIKE = 8,
	HEDGE = 16,
	HOUSE = 32,
	TRENCH = 64,
	BLOCK = 128, -- fora da área de combate
}
-- Paisagem (VT65Build/Landscape): 1 mata, 2 vila/mata, 3 lavoura, 4 clareira, 5 riacho, 6 roça seca;
-- 7 estrada de terra batida (Data/Roads, marcada por cima com markRoad; 2026-11-12)
BotNav.K = { FOREST = 1, GROVE = 2, FARM = 3, CLEAR = 4, STREAM = 5, ROCA = 6, ROAD = 7 }

local F = BotNav.F
local INF = math.huge
local SQRT2 = math.sqrt(2)

export type Grid = {
	w: number,
	h: number,
	cell: number,
	x0: number,
	z0: number,
	flags: buffer, -- u8 por célula
	kind: buffer, -- u8 por célula (paisagem)
	height: buffer, -- f32 por célula (studs)
	gs: buffer, -- f32: custo acumulado da busca
	parent: buffer, -- i32
	mark: buffer, -- u32: 2*gen aberto, 2*gen+1 fechado
	gen: number,
}

function BotNav.new(w: number, h: number, cell: number, x0: number, z0: number): Grid
	local n = w * h
	return {
		w = w,
		h = h,
		cell = cell,
		x0 = x0,
		z0 = z0,
		flags = buffer.create(n),
		kind = buffer.create(n),
		height = buffer.create(n * 4),
		gs = buffer.create(n * 4),
		parent = buffer.create(n * 4),
		mark = buffer.create(n * 4),
		gen = 0,
	}
end

-- Índice (0..n-1) da célula de (x, z), ou nil fora da grade.
function BotNav.index(g: Grid, x: number, z: number): number?
	local c = math.floor((x - g.x0) / g.cell)
	local r = math.floor((z - g.z0) / g.cell)
	if c < 0 or r < 0 or c >= g.w or r >= g.h then
		return nil
	end
	return r * g.w + c
end

function BotNav.center(g: Grid, i: number): (number, number)
	local r = i // g.w
	local c = i - r * g.w
	return g.x0 + (c + 0.5) * g.cell, g.z0 + (r + 0.5) * g.cell
end

function BotNav.flags(g: Grid, i: number): number
	return buffer.readu8(g.flags, i)
end

function BotNav.kindAt(g: Grid, x: number, z: number): number
	local i = BotNav.index(g, x, z)
	return if i then buffer.readu8(g.kind, i) else 0
end

function BotNav.flagsAt(g: Grid, x: number, z: number): number
	local i = BotNav.index(g, x, z)
	return if i then buffer.readu8(g.flags, i) else F.BLOCK
end

function BotNav.heightAt(g: Grid, x: number, z: number): number
	local i = BotNav.index(g, x, z)
	return if i then buffer.readf32(g.height, i * 4) else 0
end

function BotNav.setCell(g: Grid, i: number, kind: number, height: number, flags: number)
	buffer.writeu8(g.kind, i, kind)
	buffer.writef32(g.height, i * 4, height)
	buffer.writeu8(g.flags, i, bit32.bor(buffer.readu8(g.flags, i), flags))
end

function BotNav.markPoint(g: Grid, x: number, z: number, bit: number)
	local i = BotNav.index(g, x, z)
	if i then
		buffer.writeu8(g.flags, i, bit32.bor(buffer.readu8(g.flags, i), bit))
	end
end

-- Marca as células por onde passa o segmento (amostras a cada meia célula).
function BotNav.markSegment(g: Grid, x1: number, z1: number, x2: number, z2: number, bit: number)
	local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	local n = math.max(1, math.ceil(len / (g.cell * 0.5)))
	for k = 0, n do
		local t = k / n
		BotNav.markPoint(g, x1 + (x2 - x1) * t, z1 + (z2 - z1) * t, bit)
	end
end

-- Marca um retângulo girado (centro, tamanho em X e Z locais, yaw do Roblox).
function BotNav.markBox(g: Grid, cx: number, cz: number, sx: number, sz: number, yaw: number, bit: number)
	local ca, sa = math.cos(yaw), math.sin(yaw)
	local step = g.cell * 0.5
	local nx, nz = math.max(1, math.ceil(sx / step)), math.max(1, math.ceil(sz / step))
	for a = 0, nx do
		local u = (a / nx - 0.5) * sx
		for b = 0, nz do
			local v = (b / nz - 0.5) * sz
			-- CFrame.Angles(0, yaw, 0): x' = x cos + z sin ; z' = -x sin + z cos
			BotNav.markPoint(g, cx + u * ca + v * sa, cz - u * sa + v * ca, bit)
		end
	end
end

-- Estrada (Data/Roads): as células do leito (meia largura half, studs) viram paisagem ROAD.
-- roads: o módulo Data/Roads (width por tipo, roads = { kind, pts = x, z, y... }).
function BotNav.markRoads(g: Grid, roads: any): number
	local n = 0
	for _, r in roads.roads do
		local half = (roads.width[r.kind] or 20) / 2
		local p = r.pts
		for i = 1, #p - 5, 3 do
			local x1, z1, x2, z2 = p[i], p[i + 1], p[i + 3], p[i + 4]
			local y1, y2 = p[i + 2], p[i + 5]
			local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
			if len > 0 then
				local nx, nz = -(z2 - z1) / len, (x2 - x1) / len
				local steps = math.max(1, math.ceil(len / (g.cell * 0.5)))
				local across = math.max(1, math.ceil(2 * half / (g.cell * 0.5)))
				for k = 0, steps do
					local t = k / steps
					local cx, cz = x1 + (x2 - x1) * t, z1 + (z2 - z1) * t
					for a = 0, across do
						local o = (a / across - 0.5) * 2 * half
						local idx = BotNav.index(g, cx + nx * o, cz + nz * o)
						if idx and not bit32.btest(buffer.readu8(g.flags, idx), F.BLOCK) then
							if buffer.readu8(g.kind, idx) ~= BotNav.K.ROAD then
								n += 1
							end
							buffer.writeu8(g.kind, idx, BotNav.K.ROAD)
							-- altura do leito (a rampa da estrada, não a do chão natural)
							buffer.writef32(g.height, idx * 4, y1 + (y2 - y1) * t)
						end
					end
				end
			end
		end
	end
	return n
end

-- Grade do tamanho da do terreno (WorldData.grid): mesma origem e célula.
function BotNav.forWorld(world: any): Grid
	local gs = world.grid
	return BotNav.new(gs.width, gs.height, gs.cellStuds, gs.originX, gs.originZ)
end

-- Preenche as linhas [r0, r1) com a altura, o mar (classe 0 ou abaixo do nível do mar), o riacho
-- (classe 5) e a paisagem (kindAt). Em fatias: quem chama espera entre os blocos de linhas.
-- b: limites da área de combate (fora dela, bloqueado; a paisagem nem é calculada).
function BotNav.fillRows(g: Grid, world: any, kindAt: (number, number) -> number, b: any, r0: number, r1: number)
	for r = r0, math.min(r1, g.h) - 1 do
		for c = 0, g.w - 1 do
			local i = r * g.w + c
			local x, z = g.x0 + (c + 0.5) * g.cell, g.z0 + (r + 0.5) * g.cell
			local h = world:cellHeight(c, r)
			if x < b.minX or x > b.maxX or z < b.minZ or z > b.maxZ then
				BotNav.setCell(g, i, 0, h, F.BLOCK)
			else
				local cls = world:classAt(x, z)
				local f = if cls == 0 or h < 0 then F.SEA elseif cls == 5 then F.STREAM else 0
				BotNav.setCell(g, i, kindAt(x, z), h, f)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Custo
---------------------------------------------------------------------------------------------

export type Profile = {
	forest: number,
	grove: number,
	clear: number,
	farm: number,
	paddy: number,
	dike: number?,
	hedge: number,
	house: number,
	stream: number,
	sea: number,
	trench: number?,
	road: number?,
	maxGrade: number,
	upCost: number,
	downCost: number,
}

-- Perfil de um veículo ou da infantaria. specId: "infantry" ou a ficha (m48a3, ontos, lvtp5...);
-- kind: "tracked" | "amphibious" (outros, como um carro com rodas, caem na lagarta até terem perfil).
function BotNav.profile(kind: string, specId: string?): Profile
	local N = BotBrain.NAV
	local base = N.profiles[kind] or N.profiles.tracked
	local p = table.clone(base) :: any
	if specId and kind ~= "infantry" then
		local ford = N.fordM[specId]
		if ford and ford < N.streamDepthM + 0.05 then
			p.stream = INF -- o riacho de 0,6 m é fundo demais para este (Ontos)
		end
	end
	return p :: Profile
end

local function cellCost(g: Grid, i: number, p: Profile): number
	local f = buffer.readu8(g.flags, i)
	local k = buffer.readu8(g.kind, i)
	local road = p.road
	if k == 7 and road then
		-- estrada (BotNav.K.ROAD): leito firme; no riacho passa por aterro, então só a borda da área,
		-- a casa e a sebe ainda valem
		if bit32.btest(f, F.BLOCK) or (bit32.btest(f, F.HOUSE) and p.house >= INF) then
			return INF
		end
		return road
	end
	local c = if k == 1 then p.forest elseif k == 2 then p.grove elseif k == 4 then p.clear else p.farm
	if f == 0 then
		return c
	end
	if bit32.btest(f, F.BLOCK) then
		return INF
	end
	if bit32.btest(f, F.SEA) then
		c = p.sea
	elseif bit32.btest(f, F.STREAM) then
		c = p.stream
	else
		if bit32.btest(f, F.PADDY) then
			c = p.paddy
		end
		local dk = p.dike
		if dk and bit32.btest(f, F.DIKE) then
			c = math.min(c, dk)
		end
		local tr = p.trench
		if tr and bit32.btest(f, F.TRENCH) then
			c = if tr >= INF then INF else math.min(c, tr)
		end
	end
	if bit32.btest(f, F.HEDGE) then
		if p.hedge >= INF then
			return INF
		end
		c = math.min(c, p.hedge)
	end
	if bit32.btest(f, F.HOUSE) then
		if p.house >= INF then
			return INF
		end
		c = math.max(c, p.house)
	end
	return c
end
BotNav.cost = cellCost

local function gradeMult(p: Profile, dh: number, dist: number): number
	local gr = dh / dist
	if math.abs(gr) > p.maxGrade then
		return INF
	end
	return 1 + p.upCost * math.max(gr, 0) + p.downCost * math.max(-gr - 0.2, 0)
end

local function minCost(p: Profile): number
	local m = math.min(p.forest, p.grove, p.clear, p.farm, p.hedge, p.stream)
	if p.dike then
		m = math.min(m, p.dike)
	end
	if p.trench then
		m = math.min(m, p.trench)
	end
	if p.road then
		m = math.min(m, p.road)
	end
	return math.max(m, 0.05)
end

---------------------------------------------------------------------------------------------
-- A* em fatias
---------------------------------------------------------------------------------------------

export type Search = {
	g: Grid,
	p: Profile,
	start: number,
	goal: number,
	sx: number,
	sz: number,
	tx: number,
	tz: number,
	heapI: { number },
	heapF: { number },
	status: string, -- "running" | "done" | "fail"
	expanded: number,
	maxExpand: number,
	gen: number,
	best: number, -- célula mais perto do destino (rota parcial se falhar)
	bestH: number,
	minC: number,
	weight: number,
}

local function push(s: Search, i: number, f: number)
	local hi, hf = s.heapI, s.heapF
	local k = #hi + 1
	hi[k], hf[k] = i, f
	while k > 1 do
		local par = k // 2
		if hf[par] <= f then
			break
		end
		hi[k], hf[k] = hi[par], hf[par]
		k = par
	end
	hi[k], hf[k] = i, f
end

local function pop(s: Search): number
	local hi, hf = s.heapI, s.heapF
	local top = hi[1]
	local n = #hi
	local li, lf = hi[n], hf[n]
	hi[n], hf[n] = nil, nil
	n -= 1
	if n > 0 then
		local k = 1
		while true do
			local c = k * 2
			if c > n then
				break
			end
			if c < n and hf[c + 1] < hf[c] then
				c += 1
			end
			if hf[c] >= lf then
				break
			end
			hi[k], hf[k] = hi[c], hf[c]
			k = c
		end
		hi[k], hf[k] = li, lf
	end
	return top
end

-- Célula passável mais perto de (x, z), até 4 células de distância.
local function snap(g: Grid, p: Profile, x: number, z: number): number?
	local i = BotNav.index(g, x, z)
	if i and cellCost(g, i, p) < INF then
		return i
	end
	local c0 = math.floor((x - g.x0) / g.cell)
	local r0 = math.floor((z - g.z0) / g.cell)
	for rad = 1, 4 do
		local best, bestD = nil :: number?, INF
		for dr = -rad, rad do
			for dc = -rad, rad do
				if math.max(math.abs(dr), math.abs(dc)) == rad then
					local c, r = c0 + dc, r0 + dr
					if c >= 0 and r >= 0 and c < g.w and r < g.h then
						local j = r * g.w + c
						if cellCost(g, j, p) < INF and dr * dr + dc * dc < bestD then
							best, bestD = j, dr * dr + dc * dc
						end
					end
				end
			end
		end
		if best then
			return best
		end
	end
	return nil
end

local function heur(g: Grid, s: Search, i: number): number
	local r = i // g.w
	local c = i - r * g.w
	local gr = s.goal // g.w
	local gc = s.goal - gr * g.w
	local dx, dz = math.abs(c - gc), math.abs(r - gr)
	local oct = math.max(dx, dz) + (SQRT2 - 1) * math.min(dx, dz)
	return oct * g.cell * s.minC
end

-- Começa uma busca de (sx, sz) até (tx, tz). maxExpand: teto de nós (padrão 150 mil).
function BotNav.search(g: Grid, p: Profile, sx: number, sz: number, tx: number, tz: number, maxExpand: number?): Search
	g.gen += 1
	local s: Search = {
		g = g,
		p = p,
		start = -1,
		goal = -1,
		sx = sx,
		sz = sz,
		tx = tx,
		tz = tz,
		heapI = {},
		heapF = {},
		status = "running",
		expanded = 0,
		maxExpand = maxExpand or 150000,
		gen = g.gen,
		best = -1,
		bestH = INF,
		minC = minCost(p),
		weight = BotBrain.NAV.weight,
	}
	local a, b = snap(g, p, sx, sz), snap(g, p, tx, tz)
	if not a or not b then
		s.status = "fail"
		return s
	end
	s.start, s.goal = a, b
	buffer.writef32(g.gs, a * 4, 0)
	buffer.writei32(g.parent, a * 4, -1)
	buffer.writeu32(g.mark, a * 4, s.gen * 2)
	s.best, s.bestH = a, heur(g, s, a)
	push(s, a, s.bestH * s.weight)
	return s
end

local DC = { 1, -1, 0, 0, 1, 1, -1, -1 }
local DR = { 0, 0, 1, -1, 1, -1, 1, -1 }

-- Expande até `budget` nós. Devolve o estado: "running", "done" ou "fail".
function BotNav.run(s: Search, budget: number): string
	if s.status ~= "running" then
		return s.status
	end
	local g, p = s.g, s.p
	local w, h, cell = g.w, g.h, g.cell
	local open, closed = s.gen * 2, s.gen * 2 + 1
	local gsB, parB, markB, hB = g.gs, g.parent, g.mark, g.height
	local weight = s.weight
	local diagonalCorners = p.house >= INF -- veículo: não corta quina de célula bloqueada
	for _ = 1, budget do
		if #s.heapI == 0 then
			s.status = "fail"
			return s.status
		end
		local i = pop(s)
		if buffer.readu32(markB, i * 4) == closed then
			continue
		end
		buffer.writeu32(markB, i * 4, closed)
		s.expanded += 1
		if i == s.goal then
			s.status = "done"
			return s.status
		end
		if s.expanded >= s.maxExpand then
			s.status = "fail"
			return s.status
		end
		local gi = buffer.readf32(gsB, i * 4)
		local hi = buffer.readf32(hB, i * 4)
		local r = i // w
		local c = i - r * w
		for k = 1, 8 do
			local nc, nr = c + DC[k], r + DR[k]
			if nc < 0 or nr < 0 or nc >= w or nr >= h then
				continue
			end
			local j = nr * w + nc
			local mj = buffer.readu32(markB, j * 4)
			if mj == closed then
				continue
			end
			local cc = cellCost(g, j, p)
			if cc >= INF then
				continue
			end
			local diag = k > 4
			if diag and diagonalCorners then
				if cellCost(g, r * w + nc, p) >= INF or cellCost(g, nr * w + c, p) >= INF then
					continue
				end
			end
			local dist = if diag then cell * SQRT2 else cell
			local gm = gradeMult(p, buffer.readf32(hB, j * 4) - hi, dist)
			if gm >= INF then
				continue
			end
			local ng = gi + dist * cc * gm
			if mj ~= open or ng < buffer.readf32(gsB, j * 4) then
				buffer.writef32(gsB, j * 4, ng)
				buffer.writei32(parB, j * 4, i)
				buffer.writeu32(markB, j * 4, open)
				local hh = heur(g, s, j)
				if hh < s.bestH then
					s.best, s.bestH = j, hh
				end
				push(s, j, ng + hh * weight)
			end
		end
	end
	return s.status
end

-- Linha reta de a até b (centros) sem célula bloqueada e sem custar mais que `limit`.
local function lineCost(g: Grid, p: Profile, a: number, b: number, limit: number): boolean
	local ax, az = BotNav.center(g, a)
	local bx, bz = BotNav.center(g, b)
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local n = math.max(1, math.ceil(len / (g.cell * 0.5)))
	local stepLen = len / n
	local total = 0
	local prevH = buffer.readf32(g.height, a * 4)
	for k = 1, n do
		local t = k / n
		local i = BotNav.index(g, ax + (bx - ax) * t, az + (bz - az) * t)
		if not i then
			return false
		end
		local cc = cellCost(g, i, p)
		if cc >= INF then
			return false
		end
		local hh = buffer.readf32(g.height, i * 4)
		local gm = gradeMult(p, hh - prevH, stepLen)
		if gm >= INF then
			return false
		end
		prevH = hh
		total += stepLen * cc * gm
		if total > limit then
			return false
		end
	end
	return true
end

-- Rota da busca (ou a parcial até a célula mais perto do destino, se falhou): lista de pontos
-- {x, z} em studs, do início exato ao destino exato (ou ao fim da parcial), simplificada.
function BotNav.waypoints(s: Search): { { x: number, z: number } }
	local out: { { x: number, z: number } } = {}
	if s.start < 0 then
		return out
	end
	local g = s.g
	local last = if s.status == "done" then s.goal else s.best
	if last < 0 then
		return out
	end
	local cells: { number } = {}
	local i = last
	local guard = 0
	while i >= 0 and guard < 200000 do
		table.insert(cells, i)
		if i == s.start then
			break
		end
		i = buffer.readi32(g.parent, i * 4)
		guard += 1
	end
	-- do início ao fim
	local n = #cells
	for k = 1, n // 2 do
		cells[k], cells[n - k + 1] = cells[n - k + 1], cells[k]
	end
	local N = BotBrain.NAV
	local keep: { number } = { cells[1] }
	local a = 1
	while a < n do
		local bestJ = a + 1
		local ga = buffer.readf32(g.gs, cells[a] * 4)
		for j = math.min(n, a + N.simplifyLookCells), a + 2, -1 do
			local gj = buffer.readf32(g.gs, cells[j] * 4)
			if lineCost(g, s.p, cells[a], cells[j], (gj - ga) * N.simplifySlack + g.cell * 0.5) then
				bestJ = j
				break
			end
		end
		table.insert(keep, cells[bestJ])
		a = bestJ
	end
	table.insert(out, { x = s.sx, z = s.sz })
	for k = 2, #keep - 1 do
		local x, z = BotNav.center(g, keep[k])
		table.insert(out, { x = x, z = z })
	end
	if s.status == "done" then
		table.insert(out, { x = s.tx, z = s.tz })
	else
		local x, z = BotNav.center(g, last)
		table.insert(out, { x = x, z = z })
	end
	return out
end

-- Custo total (aprox.) de uma rota de pontos, para comparar alternativas.
function BotNav.pathLength(pts: { { x: number, z: number } }): number
	local t = 0
	for k = 2, #pts do
		t += math.sqrt((pts[k].x - pts[k - 1].x) ^ 2 + (pts[k].z - pts[k - 1].z) ^ 2)
	end
	return t
end

return BotNav
