--!strict
-- O chão do mapa como o TerrainBuilder gera (módulo puro: Roblox e Lune). Uma função só decide a
-- altura e o material de cada coluna do terreno, e o resto do jogo usa a mesma:
--   - TerrainBuilder.build (os voxels), o AssetLoader e o plano da arte (ArtPlan: onde assentar cada
--     coisa), a varredura do mapa (tools/varredura.luau) e o teste dos veículos.
-- Camadas, de baixo para cima (2026-11-12):
--   1. chão dos dados (WorldData, bilinear) e o riacho (leito em divisa de voxel, espelho 0,6 m acima);
--   2. tabuleiros do arrozal: fundo plano 10 cm abaixo da lâmina (TerrainBuilder.paddySet), rampa de
--      PADDY_BLEND_M até o chão natural em volta e o dique em lombada;
--   3. patamar de cada construção: assentado pelo ponto mais baixo do chão sob a pegada, cortando a
--      encosta até PAD_CUT_MAX e aterrando o resto, com talude em volta (sem pedestal à mostra);
--   4. estradas de terra batida (Data/Roads): o leito na largura da estrada (aterro com bueiro onde
--      cruza o riacho) e talude dos lados; becos da vila (Data/Village) com chão de terra.
-- Diques do arrozal (pedido do dono, 2026-11-12: "essas paredes da plantação de arroz não me deixam
-- passar"): não são mais peças. Cada dique que encosta num tabuleiro que ficou é uma lombada do
-- próprio terreno, de terra (Ground, com a textura de chão), crista DIKE_RISE_M acima da lâmina mais
-- alta ao lado e no máximo DIKE_MAX_M acima do fundo mais baixo, com rampa dos dois lados. Passa a
-- pé, deitado e de lagarta (VehicleDrive: degrau de 0,65 m e rampa bem abaixo do limite).
local Site = {}

local STUD_M = 0.28
local VOXEL = 4
local STREAM_DEPTH = 0.6 / STUD_M
local BUCKET = 64

Site.PAD_MARGIN = 1 / STUD_M -- patamar 1 m além da pegada
Site.PAD_BLEND = 4 / STUD_M -- talude em volta do patamar
Site.PAD_CUT_MAX = 0.8 / STUD_M -- corte máximo da encosta; acima disso, aterro do lado de baixo
Site.DIKE_RISE_M = 0.25 -- crista acima da lâmina mais alta ao lado
Site.DIKE_MAX_M = 0.40 -- crista no máximo isto acima da água do tabuleiro mais baixo ao lado
Site.DIKE_CREST_M = 0.30 -- meia largura da crista
Site.DIKE_SIDE_M = 1.20 -- rampa de cada lado (até 0,5 m em 1,2 m, perfil suave)
Site.DIKE_PADDY_M = 2.0 -- o dique conta o tabuleiro que estiver a até isto

export type Pad = {
	x: number,
	z: number,
	ca: number,
	sa: number,
	hx: number,
	hz: number,
	level: number,
	ground: boolean?, -- chão de terra batida no patamar (praça)
	exp: boolean?, -- D-232: da expansão da Vila e do Arrozal (fora do cálculo com semExp)
	canal: boolean?, -- D-232: comporta: o canal passa pelo patamar sem margem em rampa (o muro segura)
}
-- D-232: vala ou canal aberto no chão: leito de (x1, z1, y1) a (x2, z2, y2), meia largura `half`,
-- margem `bank` em rampa e `depth` de água sobre o leito (0 = seco). Studs.
type Cut = {
	x1: number,
	z1: number,
	y1: number,
	x2: number,
	z2: number,
	y2: number,
	half: number,
	bank: number,
	depth: number,
	kind: string,
}
type Seg = {
	x1: number,
	z1: number,
	y1: number,
	x2: number,
	z2: number,
	y2: number,
	half: number,
	kind: string,
}
type Lane = { x1: number, z1: number, x2: number, z2: number, half: number, exp: boolean? }

export type Site = {
	world: any,
	paddies: any?,
	TB: any?,
	segs: { [number]: { Seg } },
	pads: { [number]: { Pad } },
	lanes: { [number]: { Lane } },
	dikes: { [number]: { Lane } },
	shoulder: number,
	padList: { Pad },
	roadList: { Seg },
	cuts: { [number]: { Cut } },
	cutList: { Cut },
	semExp: boolean, -- D-232: true = o chão como era antes da expansão (o sorteio das plantas antigas)
}

local function key(bx: number, bz: number): number
	return (bx + 32768) * 65536 + (bz + 32768)
end

local function addBox(map: { [number]: { any } }, item: any, x0: number, z0: number, x1: number, z1: number)
	for bx = math.floor(x0 / BUCKET), math.floor(x1 / BUCKET) do
		for bz = math.floor(z0 / BUCKET), math.floor(z1 / BUCKET) do
			local k = key(bx, bz)
			local b = map[k]
			if not b then
				b = {}
				map[k] = b
			end
			table.insert(b, item)
		end
	end
end

-- roads: Data/Roads (ou nil); paddies: TerrainBuilder.paddySet (ou nil); TB: o TerrainBuilder (paddyFloor);
-- lanes: Data/Village.lanes (ou nil)
function Site.new(world: any, paddies: any?, TB: any?, roads: any?, lanes: { { number } }?): Site
	local self: Site = {
		world = world,
		paddies = paddies,
		TB = TB,
		segs = {},
		pads = {},
		lanes = {},
		dikes = {},
		shoulder = if roads then roads.shoulder else 3 / STUD_M,
		padList = {},
		roadList = {},
		cuts = {},
		cutList = {},
		semExp = false,
	}
	if roads then
		local reach = self.shoulder
		for _, r in roads.roads do
			local half = (roads.width[r.kind] or 20) / 2
			local p = r.pts
			for i = 1, #p - 5, 3 do
				local s: Seg = {
					x1 = p[i],
					z1 = p[i + 1],
					y1 = p[i + 2],
					x2 = p[i + 3],
					z2 = p[i + 4],
					y2 = p[i + 5],
					half = half,
					kind = r.kind,
				}
				table.insert(self.roadList, s)
				local m = half + reach
				addBox(
					self.segs,
					s,
					math.min(s.x1, s.x2) - m,
					math.min(s.z1, s.z2) - m,
					math.max(s.x1, s.x2) + m,
					math.max(s.z1, s.z2) + m
				)
			end
		end
	end
	if lanes then
		local half = 1.25 / STUD_M
		for _, l in lanes do
			local ln: Lane = { x1 = l[1], z1 = l[2], x2 = l[3], z2 = l[4], half = half }
			addBox(
				self.lanes,
				ln,
				math.min(ln.x1, ln.x2) - half,
				math.min(ln.z1, ln.z2) - half,
				math.max(ln.x1, ln.x2) + half,
				math.max(ln.z1, ln.z2) + half
			)
		end
	end
	return self
end

-- Diques que ficam no mapa (segmentos x1, z1, x2, z2 em studs): viram lombada do terreno (column).
function Site.setDikes(self: Site, list: { { number } })
	local reach = (Site.DIKE_CREST_M + Site.DIKE_SIDE_M) / STUD_M
	for _, s in list do
		local ln: Lane = { x1 = s[1], z1 = s[2], x2 = s[3], z2 = s[4], half = reach }
		addBox(
			self.dikes,
			ln,
			math.min(ln.x1, ln.x2) - reach,
			math.min(ln.z1, ln.z2) - reach,
			math.max(ln.x1, ln.x2) + reach,
			math.max(ln.z1, ln.z2) + reach
		)
	end
end

-- Altura da lombada do dique em (x, z) sobre o fundo `floor` (studs), ou nil fora do dique.
function Site.dike(self: Site, x: number, z: number, floor: number): number?
	local b = self.dikes[key(math.floor(x / BUCKET), math.floor(z / BUCKET))]
	if not (b and self.paddies and self.TB) then
		return nil
	end
	local best = math.huge
	for _, l in b do
		local dx, dz = l.x2 - l.x1, l.z2 - l.z1
		local l2 = dx * dx + dz * dz
		local t = if l2 > 0 then math.clamp(((x - l.x1) * dx + (z - l.z1) * dz) / l2, 0, 1) else 0
		local qx, qz = l.x1 + t * dx - x, l.z1 + t * dz - z
		best = math.min(best, math.sqrt(qx * qx + qz * qz))
	end
	local crestHalf = Site.DIKE_CREST_M / STUD_M
	local side = Site.DIKE_SIDE_M / STUD_M
	if best > crestHalf + side then
		return nil
	end
	local top = self.TB.paddyTop(self.paddies, x, z, Site.DIKE_PADDY_M / STUD_M)
	if not top then
		return nil -- dique sem tabuleiro ao lado: some
	end
	-- crista: acima da lâmina mais alta, sem passar do teto sobre o chão do lugar (na beira de baixo
	-- de um tabuleiro aterrado o dique acompanha a rampa: nunca uma lombada de mais de 0,5 m)
	local depth = self.TB.PADDY_DEPTH_M / STUD_M
	local crest = math.min(top + Site.DIKE_RISE_M / STUD_M, floor + depth + Site.DIKE_MAX_M / STUD_M)
	local t = math.clamp((best - crestHalf) / side, 0, 1)
	return crest - (crest - floor) * t * t * (3 - 2 * t)
end

-- Patamar de uma construção: pegada (meias medidas hx, hz em studs, giro yaw do Roblox). O nível é
-- o ponto mais baixo do chão sob a pegada; se a encosta passar de PAD_CUT_MAX, o nível sobe até o
-- mais alto menos PAD_CUT_MAX (aterro do lado de baixo). Devolve o patamar (já posto no Site).
-- level (opcional): o nível do patamar já decidido (o anexo no mesmo terraço da casa do lote).
function Site.addPad(
	self: Site,
	x: number,
	z: number,
	yaw: number,
	hx: number,
	hz: number,
	ground: boolean?,
	level: number?
): Pad
	local ca, sa = math.cos(yaw), math.sin(yaw)
	local lo, hi = math.huge, -math.huge
	for i = -2, 2 do
		for j = -2, 2 do
			local lx, lz = i / 2 * hx, j / 2 * hz
			local h = Site.column(self, x + lx * ca + lz * sa, z - lx * sa + lz * ca)
			lo, hi = math.min(lo, h), math.max(hi, h)
		end
	end
	local pad: Pad = {
		x = x,
		z = z,
		ca = ca,
		sa = sa,
		hx = hx,
		hz = hz,
		level = level or math.max(lo, hi - Site.PAD_CUT_MAX),
		-- 2026-11-13: terra batida em todo patamar (só a banca do mercado pede capim, ground = false).
		-- Com o chão no nível do plano (TerrainBuilder.groundOcc) o piso das barracas, das casas e a
		-- chapa do heliponto ficam rentes ao chão, e o capim animado (só no Grass) atravessava o piso
		ground = if ground == nil then true else ground,
	}
	table.insert(self.padList, pad)
	local r = math.sqrt(hx * hx + hz * hz) + Site.PAD_MARGIN + Site.PAD_BLEND
	addBox(self.pads, pad, x - r, z - r, x + r, z + r)
	return pad
end

-- D-232: beco novo da expansão (chão de terra, sem planta). Meia largura em studs.
function Site.addLane(self: Site, x1: number, z1: number, x2: number, z2: number, half: number)
	local ln: Lane = { x1 = x1, z1 = z1, x2 = x2, z2 = z2, half = half, exp = true }
	addBox(
		self.lanes,
		ln,
		math.min(x1, x2) - half,
		math.min(z1, z2) - half,
		math.max(x1, x2) + half,
		math.max(z1, z2) + half
	)
end

-- D-232: vala ou canal (ver o tipo Cut). Só baixa o chão: nunca sobe nada.
function Site.addCut(self: Site, c: Cut)
	table.insert(self.cutList, c)
	local m = c.half + c.bank
	addBox(
		self.cuts,
		c,
		math.min(c.x1, c.x2) - m,
		math.min(c.z1, c.z2) - m,
		math.max(c.x1, c.x2) + m,
		math.max(c.z1, c.z2) + m
	)
end

-- distância (studs) de (x, z) ao retângulo do patamar (0 dentro)
local function padDist(p: Pad, x: number, z: number): number
	local dx, dz = x - p.x, z - p.z
	-- mundo -> local (inverso do giro do Roblox)
	local lx = dx * p.ca - dz * p.sa
	local lz = dx * p.sa + dz * p.ca
	local ex = math.max(math.abs(lx) - p.hx, 0)
	local ez = math.max(math.abs(lz) - p.hz, 0)
	return math.sqrt(ex * ex + ez * ez)
end

local function segInfo(s: Seg, x: number, z: number): (number, number)
	local dx, dz = s.x2 - s.x1, s.z2 - s.z1
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((x - s.x1) * dx + (z - s.z1) * dz) / l2, 0, 1) else 0
	local qx, qz = s.x1 + t * dx - x, s.z1 + t * dz - z
	return math.sqrt(qx * qx + qz * qz), s.y1 + (s.y2 - s.y1) * t
end

-- D-232: altura do leito (na divisa de voxel) da vala ou canal mais perto de (x, z), ou nil.
function Site.cutBed(self: Site, x: number, z: number): number?
	local best, by = math.huge, nil :: number?
	local lista: { Cut } = self.cuts[key(math.floor(x / BUCKET), math.floor(z / BUCKET))] or {}
	for _, c in lista do
		local d, y = segInfo(c :: any, x, z)
		if d < best then
			best, by = d, y
		end
	end
	return if by then math.floor(by / VOXEL) * VOXEL else nil
end

-- Estrada mais perto de (x, z) dentro da largura mais o talude: (tipo, distância do eixo, altura do
-- leito, meia largura) ou nil.
function Site.road(self: Site, x: number, z: number): (string?, number, number, number)
	local b = self.segs[key(math.floor(x / BUCKET), math.floor(z / BUCKET))]
	local best, by, bk, bh = math.huge, 0, nil :: string?, 0
	if b then
		for _, s in b do
			local d, y = segInfo(s, x, z)
			-- a mais "dentro" (distância relativa à meia largura)
			if d - s.half < best - bh then
				best, by, bk, bh = d, y, s.kind, s.half
			end
		end
	end
	if bk and best <= bh + self.shoulder then
		return bk, best, by, bh
	end
	return nil, math.huge, 0, 0
end

-- Beco da vila (chão de terra, sem planta) em (x, z)?
function Site.lane(self: Site, x: number, z: number): boolean
	local b = self.lanes[key(math.floor(x / BUCKET), math.floor(z / BUCKET))]
	if b then
		for _, l in b do
			if l.exp and self.semExp then
				continue
			end
			local d = segInfo({ x1 = l.x1, z1 = l.z1, y1 = 0, x2 = l.x2, z2 = l.z2, y2 = 0, half = 0, kind = "" }, x, z)
			if d <= l.half then
				return true
			end
		end
	end
	return false
end

-- Patamar mais perto de (x, z) com a fração do talude (0 = no patamar, 1 = fora): (patamar, t) ou nil.
function Site.pad(self: Site, x: number, z: number): (Pad?, number)
	local b = self.pads[key(math.floor(x / BUCKET), math.floor(z / BUCKET))]
	local best, bp = math.huge, nil :: Pad?
	if b then
		for _, p in b do
			if p.exp and self.semExp then
				continue
			end
			local d = padDist(p, x, z)
			if d < best then
				best, bp = d, p
			end
		end
	end
	if bp and best <= Site.PAD_MARGIN + Site.PAD_BLEND then
		return bp, math.clamp((best - Site.PAD_MARGIN) / Site.PAD_BLEND, 0, 1)
	end
	return nil, 1
end

-- D-232: (x, z), com raio r, cai em beco, patamar ou vala da expansão?
function Site.expAt(self: Site, x: number, z: number, r: number): boolean
	local k = key(math.floor(x / BUCKET), math.floor(z / BUCKET))
	local rr = r * 0.5
	local becos: { Lane } = self.lanes[k] or {}
	local patamares: { Pad } = self.pads[k] or {}
	local cortes: { Cut } = self.cuts[k] or {}
	for _, l in becos do
		if l.exp then
			local d = segInfo({ x1 = l.x1, z1 = l.z1, y1 = 0, x2 = l.x2, z2 = l.z2, y2 = 0, half = 0, kind = "" }, x, z)
			if d <= l.half + rr then
				return true
			end
		end
	end
	for _, p in patamares do
		if p.exp and padDist(p, x, z) <= Site.PAD_MARGIN + Site.PAD_BLEND * 0.25 + rr then
			return true
		end
	end
	for _, c in cortes do
		local d = segInfo(c :: any, x, z)
		if d <= c.half + c.bank + rr then
			return true
		end
	end
	return false
end

-- Coluna do terreno em (x, z): altura do chão (studs), espelho d'água (-inf sem água), classe do uso
-- do solo e o material especial ("Ground" na estrada, no beco e na praça; nil = o da classe).
function Site.column(self: Site, x: number, z: number): (number, number, number, string?)
	local world = self.world
	local h = world:heightAt(x, z)
	local c = world:classAt(x, z)
	local wl = -math.huge
	local mat: string? = nil
	if c == 5 then
		-- riacho: fundo na divisa de voxel logo abaixo da altura da célula e 0,6 m d'água (D-95)
		local g = world.grid
		local col = math.floor((x - g.originX) / g.cellStuds)
		local row = math.floor((z - g.originZ) / g.cellStuds)
		local bed = math.floor(world:cellHeight(col, row) / VOXEL) * VOXEL
		h = math.min(h, bed)
		wl = bed + STREAM_DEPTH
	elseif c ~= 0 and self.paddies and self.TB then
		local pf = self.TB.paddyFloor(self.paddies, x, z)
		if pf then
			h = pf
		else
			-- beira do tabuleiro: rampa até o chão natural (sem paredão de terra)
			local nf, t = self.TB.paddyRamp(self.paddies, x, z)
			if nf then
				h = nf + (h - nf) * t
			end
		end
		-- dique: lombada de terra entre os tabuleiros
		local dk = Site.dike(self, x, z, h)
		if dk and dk > h then
			h, mat = dk, "Ground"
		end
	end
	-- patamar das construções. Vários patamares perto (casas vizinhas, anexos do quintal): média
	-- ponderada, peso ((1 - t) / t)^2 de cada um e 1 do chão natural. Contínua em todo lugar (antes
	-- valia só o patamar mais perto, e entre dois patamares de níveis diferentes o chão dava um degrau)
	-- e plana dentro de cada patamar (t = 0).
	local onPad = false
	local naComporta = false
	local b = self.pads[key(math.floor(x / BUCKET), math.floor(z / BUCKET))]
	if b then
		local sw, sl = 1, h
		local reach = Site.PAD_MARGIN + Site.PAD_BLEND
		for _, p in b do
			if p.exp and self.semExp then
				continue
			end
			local d = padDist(p, x, z)
			if d < reach then
				local t = math.max((d - Site.PAD_MARGIN) / Site.PAD_BLEND, 1e-3)
				local s = t * t * (3 - 2 * t)
				local w = ((1 - s) / math.max(s, 1e-3)) ^ 2
				sw += w
				sl += w * p.level
				if t <= 1e-3 then
					onPad = true
					naComporta = naComporta or p.canal == true
					if p.ground then
						mat = "Ground"
					end
				end
			end
		end
		h = sl / sw
		if onPad then
			wl = -math.huge
		end
	end
	-- D-232: valas e canais da expansão. O leito fica em divisa de voxel, como o do riacho (um voxel
	-- tem um material só: a água só aparece no voxel sem chão), e a margem desce em rampa.
	if not self.semExp then
		local cb = self.cuts[key(math.floor(x / BUCKET), math.floor(z / BUCKET))]
		if cb then
			for _, corte in cb do
				local dc, yc = segInfo(corte :: any, x, z)
				if dc < corte.half + corte.bank then
					local bed = math.floor(yc / VOXEL) * VOXEL
					if dc <= corte.half then
						h = math.min(h, bed)
						mat = "Mud"
						if corte.depth > 0 then
							wl = math.max(wl, bed + corte.depth)
						end
					elseif h > bed and not naComporta then
						local t = (dc - corte.half) / corte.bank
						h = bed + (h - bed) * (t * t * (3 - 2 * t))
						if mat == nil then
							mat = "Ground"
						end
					end
				end
			end
		end
	end
	-- estrada: leito na largura, talude dos lados (o talude não entra no patamar)
	local kind, d, ry, half = Site.road(self, x, z)
	if kind then
		if d <= half then
			h, wl, mat = ry, -math.huge, "Ground"
		elseif not onPad then
			local t = math.clamp((d - half) / self.shoulder, 0, 1)
			h = ry + (h - ry) * t
			if h > wl then
				wl = -math.huge
			end
		end
	elseif mat == nil and Site.lane(self, x, z) then
		mat = "Ground"
	end
	return h, wl, c, mat
end

return Site
