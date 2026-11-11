--!strict
-- Mata por uso do solo (D-64). Módulo puro: devolve a lista de plantas (chave, posição, giro e
-- escala); o AssetLoader coloca e o tools/ArtEstimate conta com a mesma lista.
-- Antes só as vilas, as sebes e as duas colinas tinham arte: a mata e o capim eram terreno pelado.
-- A carta de 1965 manda no "onde": arrozal (78% da área) fica aberto, com o arroz da grama do
-- terreno. A densidade é de design, ajustada por captura e fps no Studio.
local Vegetation = {}

export type Item = { key: string, x: number, z: number, yaw: number, scale: number, shadow: boolean }
export type Circle = { x: number, z: number, r: number }
export type Segment = { x1: number, z1: number, x2: number, z2: number, w: number }
export type Input = {
	classAt: (x: number, z: number) -> number,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	cell: number, -- studs por célula da grade de uso do solo
	exclude: { Circle }, -- QGs, casas, pontos fortes, túneis
	corridors: { Segment }?, -- raias do campo de tiro
	density: number?, -- multiplica todas as probabilidades (1 = projeto)
	seed: number, -- semente do ruído das manchas de moita
	rng: any, -- Shared/Rng (next, range)
	-- chamado a cada poucas colunas: no Roblox, task.wait. Sem isso o plano (~200 mil células) passou
	-- do limite de 10 s de script num servidor lento (Studio, 2026-11-10: "Script timeout").
	yield: (() -> ())?,
}

type Entry = { key: string, p: number, s0: number, s1: number }

-- plantas por célula de 16 studs (4,5 m; 20 m²), com probabilidade e faixa de escala
-- 3 = vila/mata: bosque fechado de quintal, bambu, coqueiro, bananeira e árvore de folha larga
Vegetation.GROVE = {
	{ key = "hill_tree", p = 0.09, s0 = 0.8, s1 = 1.3 },
	{ key = "coconut_palm", p = 0.07, s0 = 0.85, s1 = 1.2 },
	{ key = "bamboo_clump", p = 0.10, s0 = 0.8, s1 = 1.2 },
	{ key = "banana", p = 0.09, s0 = 0.8, s1 = 1.25 },
	{ key = "shrub", p = 0.28, s0 = 0.7, s1 = 1.3 },
	{ key = "elephant_grass", p = 0.12, s0 = 0.8, s1 = 1.3 },
} :: { Entry }
-- 4 = capim: moitas fechadas em manchas (ruído de ~70 m) e capim alto solto no resto
Vegetation.THICKET = {
	{ key = "shrub", p = 0.26, s0 = 0.7, s1 = 1.35 },
	{ key = "elephant_grass", p = 0.26, s0 = 0.8, s1 = 1.35 },
	{ key = "hill_tree", p = 0.05, s0 = 0.75, s1 = 1.25 },
	{ key = "bamboo_clump", p = 0.03, s0 = 0.8, s1 = 1.15 },
	{ key = "banana", p = 0.02, s0 = 0.8, s1 = 1.1 },
} :: { Entry }
Vegetation.OPEN = {
	{ key = "elephant_grass", p = 0.025, s0 = 0.8, s1 = 1.3 },
	{ key = "shrub", p = 0.015, s0 = 0.7, s1 = 1.2 },
} :: { Entry }
-- 5 = riacho: barranco com bambu e bananeira
Vegetation.STREAM = {
	{ key = "bamboo_clump", p = 0.2, s0 = 0.9, s1 = 1.2 },
	{ key = "banana", p = 0.1, s0 = 0.9, s1 = 1.2 },
	{ key = "shrub", p = 0.2, s0 = 0.8, s1 = 1.2 },
} :: { Entry }
-- Fora da área jogável (40 a 100 m da borda): cortina de árvores grandes que esconde o fim do
-- terreno recortado (D-63). Moldura de arte, não é a carta: ninguém joga ali.
Vegetation.BORDER = {
	{ key = "hill_tree", p = 0.05, s0 = 1.6, s1 = 2.4 },
	{ key = "bamboo_clump", p = 0.04, s0 = 1.3, s1 = 1.8 },
	{ key = "coconut_palm", p = 0.02, s0 = 1.1, s1 = 1.4 },
} :: { Entry }
Vegetation.BORDER_M = { 40, 100 }
-- árvores fazem sombra (luz manchada da mata); arbusto e capim não (custo das sombras)
Vegetation.SHADOW =
	{ hill_tree = true, coconut_palm = true, bamboo_clump = true, banana = true } :: { [string]: boolean }

local M = 0.28

-- ruído de valor em [0, 1], grade de `scaleStuds`, interpolação suave; determinístico pela semente.
-- Contas inteiras abaixo de 2^53 (exatas em double) e reduzidas a 32 bits a cada passo.
local U32 = 4294967296
local function hash(ix: number, iz: number, seed: number): number
	local h = (ix * 73856093 + iz * 19349663 + (seed % 65536) * 83492791) % U32
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1103 + 12345) % U32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return (h % 1000003) / 1000003
end

function Vegetation.noise(x: number, z: number, scaleStuds: number, seed: number): number
	local fx, fz = x / scaleStuds, z / scaleStuds
	local ix, iz = math.floor(fx), math.floor(fz)
	local tx, tz = fx - ix, fz - iz
	tx, tz = tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)
	local a, b = hash(ix, iz, seed), hash(ix + 1, iz, seed)
	local c, d = hash(ix, iz + 1, seed), hash(ix + 1, iz + 1, seed)
	return (a + (b - a) * tx) * (1 - tz) + (c + (d - c) * tx) * tz
end

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function segDist2(px: number, pz: number, s: Segment): number
	local dx, dz = s.x2 - s.x1, s.z2 - s.z1
	local L2 = dx * dx + dz * dz
	local t = if L2 > 0 then math.clamp(((px - s.x1) * dx + (pz - s.z1) * dz) / L2, 0, 1) else 0
	local qx, qz = s.x1 + t * dx - px, s.z1 + t * dz - pz
	return qx * qx + qz * qz
end

-- distância (studs) de um ponto até fora do retângulo: 0 dentro
local function outside(b: any, x: number, z: number): number
	local dx = math.max(b.minX - x, 0, x - b.maxX)
	local dz = math.max(b.minZ - z, 0, z - b.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- Zonas sem mata (studs): QGs com os depósitos de veículos (EUA 150 m, VC 100 m), o mastro de cada
-- ponto forte (8 m), as casas (6,5 m) e as bocas de túnel (5 m). housesXZ e tunnelXZ: x1, z1, x2, z2…
function Vegetation.exclusions(mapConfig: any, housesXZ: { number }, tunnelXZ: { number }): { Circle }
	local out: { Circle } = {}
	for f, hq in mapConfig.HQ do
		table.insert(out, { x = hq.x, z = hq.z, r = (if f == "US" then 150 else 100) / M })
	end
	for _, sp in mapConfig.Strongpoints do
		table.insert(out, { x = sp.x, z = sp.z, r = 8 / M })
	end
	for i = 1, #housesXZ - 1, 2 do
		table.insert(out, { x = housesXZ[i], z = housesXZ[i + 1], r = 6.5 / M })
	end
	for i = 1, #tunnelXZ - 1, 2 do
		table.insert(out, { x = tunnelXZ[i], z = tunnelXZ[i + 1], r = 5 / M })
	end
	return out
end

function Vegetation.blocked(input: Input, x: number, z: number): boolean
	for _, c in input.exclude do
		local dx, dz = x - c.x, z - c.z
		if dx * dx + dz * dz < c.r * c.r then
			return true
		end
	end
	local cors = input.corridors
	if cors then
		for _, s in cors do
			if segDist2(x, z, s) < s.w * s.w then
				return true
			end
		end
	end
	return false
end

function Vegetation.plan(input: Input): { Item }
	local out: { Item } = {}
	local rng = input.rng
	local k = input.density or 1
	local cell = input.cell
	local b = input.bounds
	local b0, b1 = Vegetation.BORDER_M[1] / M, Vegetation.BORDER_M[2] / M
	local x = b.minX - b1 + cell / 2
	local column = 0
	while x < b.maxX + b1 do
		column += 1
		if input.yield and column % 8 == 0 then
			input.yield()
		end
		local z = b.minZ - b1 + cell / 2
		while z < b.maxZ + b1 do
			local out_d = outside(b, x, z)
			local mix: { Entry }? = nil
			local f = 1
			if out_d > 0 then
				if out_d >= b0 and out_d <= b1 then
					mix = Vegetation.BORDER
				end
			else
				local c = input.classAt(x, z)
				if c == 3 then
					mix = Vegetation.GROVE
				elseif c == 5 then
					mix = Vegetation.STREAM
				elseif c == 4 then
					f = smoothstep(0.5, 0.68, Vegetation.noise(x, z, 70 / M, input.seed))
					mix = if rng:next() < f then Vegetation.THICKET else Vegetation.OPEN
					f = 1
				end
			end
			if mix then
				for _, e in mix do
					if rng:next() < e.p * k * f then
						local px = x + (rng:next() - 0.5) * cell
						local pz = z + (rng:next() - 0.5) * cell
						-- a cortina de fora da borda não atrapalha QG, raia nem veículo: sem exclusão
						-- (o QG dos EUA fica a 50 m da borda e a zona dele apagava a cortina)
						if out_d > 0 or not Vegetation.blocked(input, px, pz) then
							table.insert(out, {
								key = e.key,
								x = px,
								z = pz,
								yaw = rng:range(0, 2 * math.pi),
								scale = rng:range(e.s0, e.s1),
								shadow = Vegetation.SHADOW[e.key] == true,
							})
						end
					end
				end
			end
			z += cell
		end
		x += cell
	end
	return out
end

return Vegetation
