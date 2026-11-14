--!strict
-- Paisagem de jogo (D-65): onde é mata fechada, onde é lavoura da vila e onde é clareira. Módulo
-- puro, usado pelo bake (diques e lâminas só na lavoura), pelo plano da mata (Vegetation) e pelo
-- tools/ArtEstimate.
-- Pedido do usuário (2026-11-10): "mata assim, com alta densidade", com fotos de floresta tropical
-- do Vietnã cobrindo o terreno e vilas de palha com roça na beira. A carta de 1965 mostra 78% de
-- arrozal; aqui o arrozal fica só onde a vila trabalha (até FARM_M das casas) e o resto vira mata.
-- Vilas, casas, riachos, relevo, setores e pontos fortes continuam os da carta.
local Landscape = {}

Landscape.FOREST = 1 -- mata fechada (era arrozal longe das vilas, ou capim)
Landscape.GROVE = 2 -- vila/mata da carta (classe 3): quintais com bambu, coqueiro e bananeira
Landscape.FARM = 3 -- arrozal da vila: diques, lâmina d'água e arroz
Landscape.CLEAR = 4 -- clareira: pontos fortes, LZ, campo de futebol e QGs
Landscape.STREAM = 5 -- riacho
-- 2026-11-12 (pedido do dono: "diminua 75% das plantações de arroz"): o arrozal da vila sem tabuleiro
-- (o crop_world deixou só 25% das lâminas) vira roça seca: capim baixo, moita rala e manchas de
-- terra (TerrainBuilder: chão Ground nas manchas)
Landscape.ROCA = 6
Landscape.SHEET_M = 4 -- a lavoura (FARM) vai até isto além da beira de cada lâmina

local M = 0.28
-- roça de arroz em volta das casas (design). D-116 (pedido do dono: "onde está a grama que tinha e
-- coloque um pouco mais de árvores"): 45 m (era 110). Com o casario de An Cường (2) (D-115), 110 m em
-- volta de cada casa viravam roça quase toda a metade leste do mapa de 500 m, e a mata sumia.
Landscape.FARM_M = 45
-- clareiras (m): todo ponto forte (pode ser o sorteado), e áreas abertas pelo nome
Landscape.CLEAR_STRONGPOINT_M = 30
Landscape.CLEAR_NAMED_M = {
	["LZ Blue"] = 90, -- zona de pouso de helicóptero da operação: aberta
	["Athletic field"] = 70,
	-- D-123 (dono: "o outro em uma floresta densa e pouco acessível"): o objetivo A é mata fechada; com
	-- os 30 m de praxe o ponto virava uma clareira no meio da mata. Fica só a roda da bandeira.
	["Mata fechada"] = 10,
	["Picada na mata"] = 10,
}
-- pontos fortes de arrozal: em volta deles a lavoura continua (o nome é a paisagem)
Landscape.FARM_STRONGPOINT_M = 130
-- 2026-11-13: o acampamento do VC (Data/Bases) fica sob a mata: sem clareira em volta do QG (o plano
-- da arte tira só as plantas de dentro das pegadas e em volta dos pontos de nascer)
-- D-116: a base dos EUA cabe em 80 m (Vegetation.US_BASE_CLEAR_M); eram 150 m, que no mapa de 500 m
-- abriam clareira em An Cường (2) e em quase toda a borda leste
Landscape.HQ_CLEAR_M = { US = 80, VC = 0 }

export type Landscape = {
	kindAt: (self: Landscape, x: number, z: number) -> number,
}

type Disc = { x: number, z: number, r2: number }

-- Vila grande do centro (Data/Village, 2026-11-12): o retângulo da vila (rua, lotes, praça e becos)
-- é clareira: sem mata entre as casas. Os quintais e o bambuzal em volta saem do plano da arte.
Landscape.VILLAGE_MARGIN_M = 6

type Sheet = { x: number, z: number, hu: number, hv: number, ca: number, sa: number }
local BUCKET = 64
local function bkey(bx: number, bz: number): number
	return (bx + 32768) * 65536 + (bz + 32768)
end

-- world: WorldData (classAt); housesXZ: x1, z1, x2, z2… em studs; village: Data/Village (opcional);
-- waters: Features.waters (x, z, nível, tamU, tamV, giro), as lâminas que ficaram (opcional: sem
-- elas, todo arrozal perto das casas é lavoura, como antes)
function Landscape.new(world: any, mapConfig: any, housesXZ: { number }, village: any?, waters: { number }?): Landscape
	local farm: { Disc } = {}
	local clear: { Disc } = {}
	local sheets: { [number]: { Sheet } } = {}
	local margin = Landscape.SHEET_M / M
	if waters then
		for i = 1, #waters - 5, 6 do
			local u, v, a = waters[i + 3], waters[i + 4], waters[i + 5]
			local s: Sheet = {
				x = waters[i],
				z = waters[i + 1],
				hu = u / 2 + margin,
				hv = v / 2 + margin,
				ca = math.cos(a),
				sa = math.sin(a),
			}
			local r = math.sqrt(s.hu * s.hu + s.hv * s.hv)
			for bx = math.floor((s.x - r) / BUCKET), math.floor((s.x + r) / BUCKET) do
				for bz = math.floor((s.z - r) / BUCKET), math.floor((s.z + r) / BUCKET) do
					local k = bkey(bx, bz)
					sheets[k] = sheets[k] or {}
					table.insert(sheets[k], s)
				end
			end
		end
	end
	local function nearSheet(x: number, z: number): boolean
		local b = sheets[bkey(math.floor(x / BUCKET), math.floor(z / BUCKET))]
		if b then
			for _, s in b do
				local dx, dz = x - s.x, z - s.z
				if math.abs(dx * s.ca - dz * s.sa) <= s.hu and math.abs(dx * s.sa + dz * s.ca) <= s.hv then
					return true
				end
			end
		end
		return false
	end
	-- retângulo da vila no quadro da rua (u ao longo, v de lado), em studs
	local vx, vz, vca, vsa, vhu, vhv = 0, 0, 1, 0, -1, -1
	if village then
		vx, vz = village.x, village.z
		-- a rua corre no rumo (cos, sin) com giro do Roblox yaw = -rumo
		vca, vsa = math.cos(-village.yaw), math.sin(-village.yaw)
		local umax, vmax = 0, 0
		for _, h in village.houses do
			local dx, dz = h[1] - vx, h[2] - vz
			umax = math.max(umax, math.abs(dx * vca + dz * vsa))
			vmax = math.max(vmax, math.abs(-dx * vsa + dz * vca))
		end
		local m = Landscape.VILLAGE_MARGIN_M / M
		vhu = umax + village.lotW / 2 + m
		vhv = vmax + village.lotD / 2 + m
	end
	local function inVillage(x: number, z: number): boolean
		if vhu < 0 then
			return false
		end
		local dx, dz = x - vx, z - vz
		return math.abs(dx * vca + dz * vsa) <= vhu and math.abs(-dx * vsa + dz * vca) <= vhv
	end
	local function add(list: { Disc }, x: number, z: number, rM: number)
		table.insert(list, { x = x, z = z, r2 = (rM / M) ^ 2 })
	end
	for i = 1, #housesXZ - 1, 2 do
		add(farm, housesXZ[i], housesXZ[i + 1], Landscape.FARM_M)
	end
	for _, sp in mapConfig.Strongpoints do
		add(clear, sp.x, sp.z, Landscape.CLEAR_NAMED_M[sp.name] or Landscape.CLEAR_STRONGPOINT_M)
		if string.find(string.lower(sp.name), "arrozal", 1, true) then
			add(farm, sp.x, sp.z, Landscape.FARM_STRONGPOINT_M)
		end
	end
	for _, l in mapConfig.Locations do
		local r = Landscape.CLEAR_NAMED_M[l.name]
		if r then
			add(clear, l.x, l.z, r)
		end
	end
	for f, hq in mapConfig.HQ do
		add(clear, hq.x, hq.z, Landscape.HQ_CLEAR_M[f] or 100)
	end
	local function inside(list: { Disc }, x: number, z: number): boolean
		for _, d in list do
			local dx, dz = x - d.x, z - d.z
			if dx * dx + dz * dz < d.r2 then
				return true
			end
		end
		return false
	end
	local self = {} :: any
	function self.kindAt(_: Landscape, x: number, z: number): number
		local c = world:classAt(x, z)
		if c == 5 then
			return Landscape.STREAM
		elseif inVillage(x, z) then
			return Landscape.CLEAR
		elseif waters and nearSheet(x, z) then
			return Landscape.FARM -- tabuleiro que ficou (e a beira dele)
		elseif c == 3 then
			return Landscape.GROVE
		end
		if inside(clear, x, z) then
			return Landscape.CLEAR
		end
		if c == 2 and inside(farm, x, z) then
			return if waters then Landscape.ROCA else Landscape.FARM
		end
		return Landscape.FOREST
	end
	return self :: Landscape
end

return Landscape
