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

local M = 0.28
Landscape.FARM_M = 110 -- roça de arroz em volta das casas (design)
-- clareiras (m): todo ponto forte (pode ser o sorteado), e áreas abertas pelo nome
Landscape.CLEAR_STRONGPOINT_M = 30
Landscape.CLEAR_NAMED_M = {
	["LZ Blue"] = 90, -- zona de pouso de helicóptero da operação: aberta
	["Athletic field"] = 70,
}
-- pontos fortes de arrozal: em volta deles a lavoura continua (o nome é a paisagem)
Landscape.FARM_STRONGPOINT_M = 130
Landscape.HQ_CLEAR_M = { US = 150, VC = 100 }

export type Landscape = {
	kindAt: (self: Landscape, x: number, z: number) -> number,
}

type Disc = { x: number, z: number, r2: number }

-- world: WorldData (classAt); housesXZ: x1, z1, x2, z2… em studs
function Landscape.new(world: any, mapConfig: any, housesXZ: { number }): Landscape
	local farm: { Disc } = {}
	local clear: { Disc } = {}
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
		elseif c == 3 then
			return Landscape.GROVE
		end
		if inside(clear, x, z) then
			return Landscape.CLEAR
		end
		if c == 2 and inside(farm, x, z) then
			return Landscape.FARM
		end
		return Landscape.FOREST
	end
	return self :: Landscape
end

return Landscape
