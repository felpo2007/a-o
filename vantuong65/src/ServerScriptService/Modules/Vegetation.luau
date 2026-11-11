--!strict
-- Mata por paisagem (D-64, D-65). Módulo puro: devolve a lista de plantas (chave, posição, giro e
-- escala); o AssetLoader coloca e o tools/ArtEstimate conta com a mesma lista.
-- D-64: mata só onde a carta tem vegetação. D-65 (pedido do usuário, fotos de floresta tropical do
-- Vietnã): com kindAt (VT65Build/Landscape), o que não é lavoura de vila nem clareira vira mata
-- fechada em três andares — emergentes, copas tomadas de cipó e sub-bosque. A densidade é de
-- design, ajustada por captura e fps no Studio.
local Vegetation = {}

export type Item = { key: string, x: number, z: number, yaw: number, scale: number, shadow: boolean }
export type Circle = { x: number, z: number, r: number }
export type Segment = { x1: number, z1: number, x2: number, z2: number, w: number }
export type Input = {
	classAt: (x: number, z: number) -> number,
	-- paisagem da D-65 (Landscape:kindAt): 1 mata, 2 bosque de vila, 3 lavoura, 4 clareira, 5 riacho.
	-- Sem ela, vale o uso do solo da carta (D-64).
	kindAt: ((x: number, z: number) -> number)?,
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

-- patch: "wet" = manchas de baixada (tràm e bambu); "tangle" = manchas de cipó (copas tomadas)
type Entry = { key: string, p: number, s0: number, s1: number, patch: string? }

-- Mata fechada (D-65), por célula de 20 m². Em hectare: ~7 emergentes de 24 m, ~15 copas tomadas
-- de cipó, ~20 árvores de folha larga, tràm e bambu em manchas, e ~70 plantas de sub-bosque.
-- Captura do Studio (2026-11-10): com copas de 9–16 m a mata parecia um parque (capim entre as
-- árvores). Copas maiores (1,4–2,3x) fecham o dossel sem mais instâncias; montes de cipó (o arbusto
-- a 1,8–3x, 3–5 m de altura) fazem o tapete verde das fotos.
-- D-67 (pedido do usuário: árvores prontas de qualidade, jogo menos pesado): as três árvores do
-- ForgeGUI (emergente, copa de cipó e folha larga, malha cheia de folha opaca) dão lugar a árvores
-- prontas do Poly Haven (CC0) com folha em cartão recortado, de 12,5 a 13,7 mil triângulos. O
-- modelo tem o tamanho real da árvore de origem (2,6 a 5 m); a escala leva ao porte da mata:
-- emergente de 17 a 21 m, dossel de 8 a 17 m e árvore torta baixa nas manchas de cipó. A folha
-- cresce junto (25 a 65 cm), como a das árvores de folha larga da região.
Vegetation.FOREST = {
	{ key = "ph_tree_small_02", p = 0.010, s0 = 3.6, s1 = 4.6 },
	{ key = "ph_island_tree_01", p = 0.035, s0 = 2.2, s1 = 3.4 },
	{ key = "ph_island_tree_02", p = 0.035, s0 = 2.4, s1 = 3.6 },
	{ key = "ph_island_tree_03", p = 0.012, s0 = 1.6, s1 = 2.6, patch = "tangle" },
	{ key = "shrub", p = 0.03, s0 = 1.8, s1 = 3.0, patch = "tangle" }, -- monte de cipó
	{ key = "melaleuca_grove", p = 0.012, s0 = 0.9, s1 = 1.2, patch = "wet" },
	{ key = "bamboo_clump", p = 0.02, s0 = 0.9, s1 = 1.3, patch = "wet" },
	{ key = "banana", p = 0.008, s0 = 0.9, s1 = 1.3 },
	{ key = "coconut_palm", p = 0.004, s0 = 1.0, s1 = 1.3 },
	{ key = "taro_fern", p = 0.03, s0 = 0.8, s1 = 1.3 }, -- 4,6 mil triângulos: metade do previsto
	{ key = "shrub", p = 0.05, s0 = 0.8, s1 = 1.4, patch = "tangle" },
	{ key = "elephant_grass", p = 0.03, s0 = 0.9, s1 = 1.3 },
} :: { Entry }
-- Modelo novo ainda sem ID publicado: o AssetLoader põe o substituto (chave, fator de escala)
Vegetation.FALLBACK = {
	canopy_tree = { "hill_tree", 1.9 },
	vine_tree = { "hill_tree", 1.6 },
	melaleuca_grove = { "bamboo_clump", 1.0 },
	taro_fern = { "shrub", 0.8 },
	-- árvores prontas (D-67): a escala delas parte de 2,6–5 m; a das do ForgeGUI, de ~9–13 m
	ph_tree_small_02 = { "canopy_tree", 0.25 },
	ph_island_tree_01 = { "hill_tree", 0.6 },
	ph_island_tree_02 = { "hill_tree", 0.55 },
	ph_island_tree_03 = { "hill_tree", 0.5 },
} :: { [string]: { any } }

-- plantas por célula de 16 studs (4,5 m; 20 m²), com probabilidade e faixa de escala
-- 3 = vila/mata: bosque fechado de quintal, bambu, coqueiro, bananeira e árvore de folha larga
Vegetation.GROVE = {
	{ key = "ph_island_tree_02", p = 0.06, s0 = 2.0, s1 = 3.0 },
	{ key = "ph_island_tree_01", p = 0.03, s0 = 2.0, s1 = 2.8 },
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
	{ key = "ph_island_tree_03", p = 0.05, s0 = 1.4, s1 = 2.4 },
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
	{ key = "ph_island_tree_01", p = 0.03, s0 = 3.2, s1 = 4.4 },
	{ key = "ph_tree_small_02", p = 0.02, s0 = 3.6, s1 = 4.6 },
	{ key = "bamboo_clump", p = 0.04, s0 = 1.3, s1 = 1.8 },
	{ key = "coconut_palm", p = 0.02, s0 = 1.1, s1 = 1.4 },
} :: { Entry }
Vegetation.BORDER_M = { 40, 100 }
-- Sombra só das copas grandes: emergentes e árvores de folha larga a partir de uma escala.
-- Com sombra em todas as árvores (~18 mil na mata da D-65), a GPU de 2 GB do PC de teste travou no
-- Studio (DXGI_ERROR_DEVICE_HUNG, 2026-11-10, com um jogo aberto ao lado). Arbusto, capim, bambu,
-- bananeira, coqueiro e tràm ficam sem sombra; a luz manchada vem das copas grandes.
-- Valor = escala mínima para a sombra (0 = sempre). D-67: árvores prontas, só as maiores (~1/3).
Vegetation.SHADOW = {
	canopy_tree = 0,
	hill_tree = 1.7,
	vine_tree = 1.7,
	ph_tree_small_02 = 0,
	ph_island_tree_01 = 3.0,
	ph_island_tree_02 = 3.2,
} :: { [string]: number }

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
			elseif input.kindAt then
				local kind = input.kindAt(x, z)
				if kind == 1 then
					mix = Vegetation.FOREST
				elseif kind == 2 then
					mix = Vegetation.GROVE
				elseif kind == 5 then
					mix = Vegetation.STREAM
				end -- 3 lavoura e 4 clareira: abertas
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
				-- manchas: baixada úmida (tràm, bambu) e emaranhado de cipó, em ruídos de ~120 m
				local wet = 2.5 * smoothstep(0.5, 0.75, Vegetation.noise(x, z, 120 / M, input.seed + 7))
				local tangle = 0.5 + 1.5 * smoothstep(0.4, 0.7, Vegetation.noise(x, z, 90 / M, input.seed + 13))
				for _, e in mix do
					local pf = if e.patch == "wet" then wet elseif e.patch == "tangle" then tangle else 1
					if rng:next() < e.p * k * f * pf then
						local px = x + (rng:next() - 0.5) * cell
						local pz = z + (rng:next() - 0.5) * cell
						-- a cortina de fora da borda não atrapalha QG, raia nem veículo: sem exclusão
						-- (o QG dos EUA fica a 50 m da borda e a zona dele apagava a cortina)
						if out_d > 0 or not Vegetation.blocked(input, px, pz) then
							local yaw = rng:range(0, 2 * math.pi)
							local scale = rng:range(e.s0, e.s1)
							table.insert(out, {
								key = e.key,
								x = px,
								z = pz,
								yaw = yaw,
								scale = scale,
								shadow = Vegetation.SHADOW[e.key] ~= nil and scale >= Vegetation.SHADOW[e.key],
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
