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
	-- paisagem da D-65 (Landscape:kindAt): 1 mata, 2 bosque de vila, 3 lavoura, 4 clareira, 5 riacho,
	-- 6 roça seca.
	-- Sem ela, vale o uso do solo da carta (D-64).
	kindAt: ((x: number, z: number) -> number)?,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	cell: number, -- studs por célula da grade de uso do solo
	exclude: { Circle }, -- QGs, casas, pontos fortes, túneis
	corridors: { Segment }?, -- raias do campo de tiro
	density: number?, -- multiplica todas as probabilidades (1 = projeto)
	dense: { Circle }?, -- D-123: mata cerrada em volta do objetivo da mata (Vegetation.denseCircles)
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
-- D-116 (pedido do dono: "coloque um pouco mais de árvores"): as quatro árvores 40% mais frequentes
-- (eram 0,010 / 0,035 / 0,035 / 0,012); o sub-bosque fica igual.
Vegetation.FOREST = {
	{ key = "ph_tree_small_02", p = 0.014, s0 = 3.6, s1 = 4.6 },
	{ key = "ph_island_tree_01", p = 0.049, s0 = 2.2, s1 = 3.4 },
	{ key = "ph_island_tree_02", p = 0.049, s0 = 2.4, s1 = 3.6 },
	{ key = "ph_island_tree_03", p = 0.017, s0 = 1.6, s1 = 2.6, patch = "tangle" },
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
-- 6 = roça seca (2026-11-12: o arrozal tirado, 75%): capim baixo do terreno, moita e capim-elefante
-- ralos em touceiras soltas, uma bananeira de vez em quando. Densidade de design (PLACEHOLDER).
-- D-116: uma árvore de folha larga ou um coqueiro solto de vez em quando, como na beira das roças
Vegetation.ROCA = {
	{ key = "elephant_grass", p = 0.035, s0 = 0.7, s1 = 1.1 },
	{ key = "shrub", p = 0.025, s0 = 0.6, s1 = 1.0 },
	{ key = "banana", p = 0.004, s0 = 0.8, s1 = 1.1 },
	{ key = "ph_island_tree_02", p = 0.006, s0 = 2.0, s1 = 3.0 },
	{ key = "coconut_palm", p = 0.005, s0 = 0.9, s1 = 1.2 },
} :: { Entry }
-- 5 = riacho: barranco com bambu e bananeira
Vegetation.STREAM = {
	{ key = "bamboo_clump", p = 0.2, s0 = 0.9, s1 = 1.2 },
	{ key = "banana", p = 0.1, s0 = 0.9, s1 = 1.2 },
	{ key = "shrub", p = 0.2, s0 = 0.8, s1 = 1.2 },
} :: { Entry }
-- Fora da área jogável (40 a 80 m da borda): cortina de árvores grandes que esconde o fim do
-- terreno recortado (D-63). Moldura de arte, não é a carta: ninguém joga ali. O AssetLoader tira
-- colisão, consulta de raio e sombra delas. Mapa de 1 x 1 km (2026-11-11): a faixa era de 40 a 100 m
-- e o bambu (40% da cortina, baixo, atrás das copas) saiu; a cortina caiu de 2.777 plantas (2 x 2
-- km) para 636 no plano (Vegetation.plan com os dados do mapa, no Lune).
Vegetation.BORDER = {
	{ key = "ph_island_tree_01", p = 0.03, s0 = 3.2, s1 = 4.4 },
	{ key = "ph_tree_small_02", p = 0.02, s0 = 3.6, s1 = 4.6 },
	{ key = "coconut_palm", p = 0.02, s0 = 1.1, s1 = 1.4 },
} :: { Entry }
Vegetation.BORDER_M = { 40, 80 }
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

-- Zonas sem mata (studs): a base dos EUA com os depósitos de veículos (US_BASE_CLEAR_M), o mastro de
-- cada ponto forte (8 m), as casas (6,5 m) e as bocas de túnel (5 m). housesXZ e tunnelXZ: x1, z1, x2,
-- z2…
-- D-114 (mapa de 500 m): 80 m, o canto mais longe da base (90 x 122 m) fica a 77 m do QG. Eram 150 m,
-- que no mapa novo pelariam An Cường (2).
Vegetation.US_BASE_CLEAR_M = 80
function Vegetation.exclusions(mapConfig: any, housesXZ: { number }, tunnelXZ: { number }): { Circle }
	local out: { Circle } = {}
	-- 2026-11-13: o acampamento do VC fica sob a mata (só as pegadas e os pontos de nascer abrem)
	for f, hq in mapConfig.HQ do
		if f == "US" then
			table.insert(out, { x = hq.x, z = hq.z, r = Vegetation.US_BASE_CLEAR_M / M })
		end
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

-- Clareira dos pontos de nascimento (pedido do dono, 2026-11-11: os dois lados nasciam no QG dentro
-- do capim-elefante e a tela ficava toda de folha). spots: Front.spawnSpots. Cada ponto ganha um
-- círculo sem planta de SPAWN_CLEAR_M e uma visada de SPAWN_VIEW_M x 2·SPAWN_VIEW_W_M na direção do
-- objetivo. O resto da mata fica como está.
Vegetation.SPAWN_CLEAR_M = 15
Vegetation.SPAWN_VIEW_M = 35
Vegetation.SPAWN_VIEW_W_M = 4
function Vegetation.spawnClearings(spots: { any }): ({ Circle }, { Segment })
	local circles: { Circle } = {}
	local lanes: { Segment } = {}
	for _, s in spots do
		table.insert(circles, { x = s.x, z = s.z, r = Vegetation.SPAWN_CLEAR_M / M })
		local dx, dz = s.aimX - s.x, s.aimZ - s.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1 then
			local k = math.min(Vegetation.SPAWN_VIEW_M / M, len) / len
			table.insert(lanes, {
				x1 = s.x,
				z1 = s.z,
				x2 = s.x + dx * k,
				z2 = s.z + dz * k,
				w = Vegetation.SPAWN_VIEW_W_M / M,
			})
		end
	end
	return circles, lanes
end

-- Mata cerrada do objetivo da mata (D-123, pedido do dono: "outro numa floresta densa e pouco
-- acessível"): em volta dos pontos fortes do setor DENSE_SECTOR, a mata fica DENSE_K vezes mais cheia
-- até DENSE_M e volta ao normal suave até 1,5 x DENSE_M. Densidade de design (PLACEHOLDER).
Vegetation.DENSE_SECTOR = 1
Vegetation.DENSE_M = 70
Vegetation.DENSE_K = 1.8
function Vegetation.denseCircles(mapConfig: any): { Circle }
	local out: { Circle } = {}
	for _, sp in mapConfig.Strongpoints do
		if sp.sector == Vegetation.DENSE_SECTOR then
			table.insert(out, { x = sp.x, z = sp.z, r = Vegetation.DENSE_M / M })
		end
	end
	return out
end
local function denseAt(circles: { Circle }?, x: number, z: number): number
	if not circles then
		return 1
	end
	local best = 1
	for _, c in circles do
		local d = math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2)
		local t = 1 - smoothstep(c.r, c.r * 1.5, d)
		best = math.max(best, 1 + (Vegetation.DENSE_K - 1) * t)
	end
	return best
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
					f = denseAt(input.dense, x, z) -- D-123: mata cerrada do objetivo da mata
				elseif kind == 2 then
					mix = Vegetation.GROVE
				elseif kind == 5 then
					mix = Vegetation.STREAM
				elseif kind == 6 then
					mix = Vegetation.ROCA
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
						-- (os dois QGs ficam a 50–60 m da borda e a zona deles apagava a cortina)
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
