--!strict
-- Gera o terreno com Terrain:WriteVoxels a partir das alturas exportadas. O servidor roda isto no
-- início (TerrainRuntime) quando o place vem sem terreno; no Studio, pela barra de comando:
--     require(game.ServerStorage.VT65Build.Build).terrain()
-- Mapa de 1 x 1 km (2026-11-11): grade de 292 x 291 células (1,3 x 1,3 km com a margem), 361 blocos
-- de 64 x 64 voxels (eram 1.089 no mapa de 2 x 2 km).
local TerrainBuilder = {}

local VOXEL = 4
local CHUNK = 64 -- voxels por lado de bloco horizontal (256 studs)
local STUD_M = 0.28
local STREAM_DEPTH = 0.6 / STUD_M -- lâmina d'água dos riachos (studs)
-- Riacho com leito aberto (crop_world: Grid.streamCarvedCm): o espelho d'água é plano na célula
-- inteira, STREAM_DEPTH acima do fundo do leito, que fica numa divisa de voxel (ver build). Antes a
-- água seguia a altura interpolada de cada coluna e ficava acima da margem na beira da célula.
-- Mar: o DEM dá 0 m no mar, e a água só aparece onde o fundo fica abaixo do nível 0. Sem isto o mar
-- a leste virava uma planície de areia (teste no Studio, 2026-11-10: 1 ponto de água de terreno no
-- mapa todo, e o LVTP-5 não tinha onde flutuar). O fundo desce a partir da costa (o início do mar
-- contínuo vindo do leste, em cada linha da grade) numa rampa de 1:40, de 0,4 a 8 m. PLACEHOLDER
-- de design até haver batimetria de 1965.
local SEA_SLOPE = 1 / 40
local SEA_MIN_M, SEA_MAX_M = 0.4, 8

-- classes: 0 mar | 1 areia | 2 arrozal | 3 vila/mata | 4 capim | 5 riacho

export type Env = {
	Enum: any,
	Vector3: any,
	Region3: any,
	terrain: any, -- objeto com WriteVoxels(region, resolution, materials, occupancies)
	wait: () -> (),
}

-- ===== tabuleiros do arrozal: chão plano debaixo da lâmina =====
-- Achado no Studio (2026-11-11): a lâmina d'água ia para a mediana do chão sob ela + 6 cm, e o chão
-- natural (inclinado, irregular) furava a lâmina em metade dos pontos. Num tabuleiro o soldado
-- andava no capim e o movimento lia "seco". Agora o terreno é aplainado em cada tabuleiro que existe
-- no place (o mesmo filtro de mata do FeatureBuilder): fundo PADDY_DEPTH_M abaixo do topo da lâmina,
-- e o AssetLoader põe a lâmina na mesma altura (TerrainBuilder.paddyTop).
-- - O fundo fica na mediana do chão sob a lâmina (2026-11-12: antes ia a uma divisa de meio voxel, e
--   dois tabuleiros vizinhos saíam com degraus de 0,56 m; o dique entre eles ficava alto demais para
--   a lagarta subir). A ocupação do voxel põe a superfície na altura pedida (como o importador de
--   mapa de altura do Roblox).
-- - O aplainado passa um voxel além da borda da lâmina (PADDY_MARGIN): todo ponto da lâmina fica
--   entre colunas aplainadas. Onde dois tabuleiros se encostam, vale o fundo mais baixo, então o chão
--   nunca sobe acima da água; junto ao dique de um tabuleiro mais baixo a água fica mais funda.
TerrainBuilder.PADDY_DEPTH_M = 0.10
local PADDY_MARGIN = VOXEL
local PADDY_BUCKET = 64
-- 2026-11-12 (achado na varredura: a borda do tabuleiro ficava até 3 m acima ou abaixo do chão em
-- volta, um paredão de terra): fora do aplainado, o chão volta ao natural numa rampa desta largura.
TerrainBuilder.PADDY_BLEND_M = 4
local PADDY_BLEND = TerrainBuilder.PADDY_BLEND_M / STUD_M

export type Paddy = { x: number, z: number, hu: number, hv: number, ca: number, sa: number, floor: number, top: number }
export type PaddySet = { list: { Paddy }, buckets: { [number]: { Paddy } } }

local function bucketKey(bx: number, bz: number): number
	return (bx + 32768) * 65536 + (bz + 32768)
end

-- waters: lista plana x, z, yNivel, tamU, tamV, ângulo (Features.waters) dos tabuleiros que existem
-- no place. O nível sai do chão dos dados (mediana de 9 pontos), não do yNivel do export (o relevo
-- foi recalibrado depois dele, D-66/D-73).
function TerrainBuilder.paddySet(world: any, waters: { number }): PaddySet
	local set: PaddySet = { list = {}, buckets = {} }
	local depth = TerrainBuilder.PADDY_DEPTH_M / STUD_M
	for i = 1, #waters - 5, 6 do
		local x, z, u, v, a = waters[i], waters[i + 1], waters[i + 3], waters[i + 4], waters[i + 5]
		local ca, sa = math.cos(a), math.sin(a)
		local hs = {}
		for _, o in
			{
				{ 0, 0 },
				{ 0.35, 0 },
				{ -0.35, 0 },
				{ 0, 0.35 },
				{ 0, -0.35 },
				{ 0.35, 0.35 },
				{ -0.35, -0.35 },
				{ 0.35, -0.35 },
				{ -0.35, 0.35 },
			}
		do
			local lu, lv = o[1] * u, o[2] * v
			-- local -> mundo (inverso de lu = dx*ca - dz*sa, lv = dx*sa + dz*ca)
			table.insert(hs, world:heightAt(x + lu * ca + lv * sa, z - lu * sa + lv * ca))
		end
		table.sort(hs)
		local floor = hs[5]
		local p: Paddy = { x = x, z = z, hu = u / 2, hv = v / 2, ca = ca, sa = sa, floor = floor, top = floor + depth }
		table.insert(set.list, p)
		local r = math.sqrt(p.hu * p.hu + p.hv * p.hv) + PADDY_MARGIN + PADDY_BLEND
		for bx = math.floor((x - r) / PADDY_BUCKET), math.floor((x + r) / PADDY_BUCKET) do
			for bz = math.floor((z - r) / PADDY_BUCKET), math.floor((z + r) / PADDY_BUCKET) do
				local k = bucketKey(bx, bz)
				local b = set.buckets[k]
				if not b then
					b = {}
					set.buckets[k] = b
				end
				table.insert(b, p)
			end
		end
	end
	return set
end

local function covers(p: Paddy, x: number, z: number, margin: number): boolean
	local dx, dz = x - p.x, z - p.z
	local lu = dx * p.ca - dz * p.sa
	local lv = dx * p.sa + dz * p.ca
	return math.abs(lu) <= p.hu + margin and math.abs(lv) <= p.hv + margin
end

-- Fundo aplainado na coluna (x, z): o mais baixo dos tabuleiros a até um voxel; nil fora deles.
function TerrainBuilder.paddyFloor(set: PaddySet, x: number, z: number): number?
	local b = set.buckets[bucketKey(math.floor(x / PADDY_BUCKET), math.floor(z / PADDY_BUCKET))]
	local best: number? = nil
	if b then
		for _, p in b do
			if covers(p, x, z, PADDY_MARGIN) and (best == nil or p.floor < best) then
				best = p.floor
			end
		end
	end
	return best
end

-- Rampa da borda: fundo do tabuleiro mais perto e a fração da rampa em (x, z) (0 na beira do
-- aplainado, 1 a PADDY_BLEND dela); nil, 1 longe de todos.
function TerrainBuilder.paddyRamp(set: PaddySet, x: number, z: number): (number?, number)
	local b = set.buckets[bucketKey(math.floor(x / PADDY_BUCKET), math.floor(z / PADDY_BUCKET))]
	local best, floor = math.huge, nil :: number?
	if b then
		for _, p in b do
			local dx, dz = x - p.x, z - p.z
			local ex = math.max(math.abs(dx * p.ca - dz * p.sa) - p.hu - PADDY_MARGIN, 0)
			local ez = math.max(math.abs(dx * p.sa + dz * p.ca) - p.hv - PADDY_MARGIN, 0)
			local d = math.sqrt(ex * ex + ez * ez)
			if d < best or (d == best and floor and p.floor < floor) then
				best, floor = d, p.floor
			end
		end
	end
	if floor and best < PADDY_BLEND then
		local t = best / PADDY_BLEND
		return floor, t * t * (3 - 2 * t)
	end
	return nil, 1
end

-- O tabuleiro com centro em (x, z) (a lâmina do place tem o centro do dado), ou nil.
function TerrainBuilder.paddyOf(set: PaddySet, x: number, z: number): Paddy?
	local b = set.buckets[bucketKey(math.floor(x / PADDY_BUCKET), math.floor(z / PADDY_BUCKET))]
	if b then
		for _, p in b do
			if math.abs(p.x - x) < 0.5 and math.abs(p.z - z) < 0.5 then
				return p
			end
		end
	end
	return nil
end

-- Topo da lâmina mais alta que cobre (x, z), com `margin` studs de folga (dique: a crista fica acima
-- dela). nil fora dos tabuleiros.
function TerrainBuilder.paddyTop(set: PaddySet, x: number, z: number, margin: number?): number?
	local b = set.buckets[bucketKey(math.floor(x / PADDY_BUCKET), math.floor(z / PADDY_BUCKET))]
	local best: number? = nil
	if b then
		for _, p in b do
			if covers(p, x, z, margin or 0) and (best == nil or p.top > best) then
				best = p.top
			end
		end
	end
	return best
end

export type Options = {
	yieldEvery: number?,
	-- limita a geração a um retângulo XZ (studs): útil para testes e para regerar um trecho
	only: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	-- tabuleiros do arrozal que existem no place (TerrainBuilder.paddySet): chão plano sob a lâmina
	paddies: PaddySet?,
	-- 2026-11-12: a coluna inteira pelo Site (riacho, arrozal, patamar das construções, estrada e
	-- beco): devolve altura, espelho d'água, classe e o material especial ("Ground"). Com ela,
	-- `paddies` não é usado.
	column: ((x: number, z: number) -> (number, number, number, string?))?,
}

function TerrainBuilder.build(world: any, envIn: Env?, opts: Options?): number
	local env: Env = envIn
		or {
			Enum = Enum,
			Vector3 = Vector3,
			Region3 = Region3,
			terrain = workspace.Terrain,
			wait = function()
				task.wait()
			end,
		}
	local Enum = env.Enum
	-- arrozal = Grass (D-64): a grama animada do Roblox faz o arroz verde de agosto debaixo da lâmina
	-- d'água. Passos e veículos continuam "arrozal" porque o raio acerta a lâmina (PaddyWater) antes.
	local MATERIAL: { [number]: any } = {
		[0] = Enum.Material.Sand,
		[1] = Enum.Material.Sand,
		[2] = Enum.Material.Grass,
		[3] = Enum.Material.LeafyGrass, -- chão de mata e quintal: folhas secas e capim (D-64)
		[4] = Enum.Material.Grass,
		[5] = Enum.Material.Mud,
	}
	local terrain = env.terrain
	local only = opts and opts.only
	local paddies = opts and opts.paddies
	local column = opts and opts.column
	local g = world.grid
	local carved = g.streamCarvedCm ~= nil
	local x0 = math.floor(g.originX / VOXEL) * VOXEL
	local z0 = math.floor(g.originZ / VOXEL) * VOXEL
	local nx = math.ceil(g.width * g.cellStuds / VOXEL)
	local nz = math.ceil(g.height * g.cellStuds / VOXEL)
	local total = math.ceil(nx / CHUNK) * math.ceil(nz / CHUNK)
	-- costa por linha da grade: do leste para o oeste, enquanto a célula for mar
	local coastX: { [number]: number } = {}
	for row = 0, g.height - 1 do
		local wz = g.originZ + (row + 0.5) * g.cellStuds
		local coast = g.originX + g.width * g.cellStuds
		for col = g.width - 1, 0, -1 do
			local wx = g.originX + (col + 0.5) * g.cellStuds
			if world:classAt(wx, wz) ~= 0 then
				break
			end
			coast = wx - g.cellStuds / 2
		end
		coastX[row] = coast
	end
	local done = 0
	local t0 = os.clock()
	for cz = 0, nz - 1, CHUNK do
		for cx = 0, nx - 1, CHUNK do
			local sx = math.min(CHUNK, nx - cx)
			local sz = math.min(CHUNK, nz - cz)
			if only then
				local bx0, bz0 = x0 + cx * VOXEL, z0 + cz * VOXEL
				if
					bx0 > only.maxX
					or bx0 + sx * VOXEL < only.minX
					or bz0 > only.maxZ
					or bz0 + sz * VOXEL < only.minZ
				then
					continue
				end
			end
			-- alturas das colunas e faixa vertical do bloco
			local surf = table.create(sx * sz) :: { number }
			local water = table.create(sx * sz) :: { number }
			local cls = table.create(sx * sz) :: { number }
			local special = table.create(sx * sz) :: { any }
			local ymin, ymax = math.huge, -math.huge
			for iz = 1, sz do
				for ix = 1, sx do
					local wx = x0 + (cx + ix - 0.5) * VOXEL
					local wz = z0 + (cz + iz - 0.5) * VOXEL
					local k = (iz - 1) * sx + ix
					if column then
						local h, wl, c, mat = column(wx, wz)
						surf[k], water[k], cls[k] = h, wl, c
						special[k] = if mat then (Enum.Material :: any)[mat] else false
						ymin = math.min(ymin, h)
						ymax = math.max(ymax, h, wl)
						continue
					end
					special[k] = false
					local h = world:heightAt(wx, wz)
					local c = world:classAt(wx, wz)
					-- tabuleiro do arrozal: chão plano 10 cm abaixo da lâmina (o riacho fica como está)
					local pf = if paddies and c ~= 5 and c ~= 0 then TerrainBuilder.paddyFloor(paddies, wx, wz) else nil
					if pf then
						h = pf
					end
					if c == 0 then
						local coast = coastX[math.floor((wz - g.originZ) / g.cellStuds)]
						if coast and wx >= coast then
							local depthM =
								math.clamp(SEA_MIN_M + (wx - coast) * STUD_M * SEA_SLOPE, SEA_MIN_M, SEA_MAX_M)
							h = math.min(h, -depthM / STUD_M)
						end
					end
					local wl = -math.huge
					if c == 0 or h < 0 then
						wl = 0 -- nível do mar
					elseif c == 5 then
						if carved then
							local col = math.floor((wx - g.originX) / g.cellStuds)
							local row = math.floor((wz - g.originZ) / g.cellStuds)
							-- Um voxel tem um material só (WriteVoxels): a água só aparece num voxel sem
							-- chão. Com o fundo no meio de um voxel, a fundura ia de 0 a ~1,1 m de um passo
							-- para o outro. O fundo do leito vai à divisa de voxel logo abaixo da altura
							-- da célula e o espelho fica STREAM_DEPTH acima dela: 0,6 m em todo o leito.
							-- O crop_world deixa o fundo sem subir rio abaixo, então o espelho desce em
							-- degraus de 1,12 m (corredeiras) onde o fundo cruza uma divisa.
							local bed = math.floor(world:cellHeight(col, row) / VOXEL) * VOXEL
							h = math.min(h, bed)
							wl = bed + STREAM_DEPTH
						else
							wl = h + STREAM_DEPTH
						end
					end
					surf[k], water[k], cls[k] = h, wl, c
					ymin = math.min(ymin, h)
					ymax = math.max(ymax, h, wl)
				end
			end
			local yb = math.floor((ymin - 16) / VOXEL) * VOXEL -- 16 studs de solo abaixo do mínimo
			local yt = math.ceil((ymax + VOXEL) / VOXEL) * VOXEL
			local ny = (yt - yb) // VOXEL
			local mats = table.create(sx)
			local occs = table.create(sx)
			for ix = 1, sx do
				local mcol = table.create(ny)
				local ocol = table.create(ny)
				for iy = 1, ny do
					mcol[iy] = table.create(sz)
					ocol[iy] = table.create(sz)
				end
				for iz = 1, sz do
					local k = (iz - 1) * sx + ix
					local h, wl, mat = surf[k], water[k], special[k] or MATERIAL[cls[k]] or Enum.Material.Ground
					for iy = 1, ny do
						local vb = yb + (iy - 1) * VOXEL
						local occ = math.clamp((h - vb) / VOXEL, 0, 1)
						if occ > 0 then
							mcol[iy][iz] = mat
							ocol[iy][iz] = occ
						elseif wl > vb then
							mcol[iy][iz] = Enum.Material.Water
							ocol[iy][iz] = math.clamp((wl - vb) / VOXEL, 0, 1)
						else
							mcol[iy][iz] = Enum.Material.Air
							ocol[iy][iz] = 0
						end
					end
				end
				mats[ix] = mcol
				occs[ix] = ocol
			end
			local p0 = env.Vector3.new(x0 + cx * VOXEL, yb, z0 + cz * VOXEL)
			local region = env.Region3.new(p0, p0 + env.Vector3.new(sx * VOXEL, ny * VOXEL, sz * VOXEL))
			terrain:WriteVoxels(region, VOXEL, mats, occs)
			done += 1
			if done % ((opts and opts.yieldEvery) or 8) == 0 then
				env.wait()
			end
			-- progresso a cada 10% (antes: uma linha a cada 8 blocos, 420 linhas no Output)
			if done % math.max(1, total // 10) == 0 then
				print(
					string.format(
						"[VT65] terreno %d%% (%d/%d blocos, %.0f s)",
						math.floor(100 * done / total + 0.5),
						done,
						total,
						os.clock() - t0
					)
				)
			end
		end
	end
	print(string.format("[VT65] terreno pronto: %d blocos em %.0f s", done, os.clock() - t0))
	return done
end

-- Escava túneis, poços e a trincheira (caixas "carve" de TunnelGeometry.build).
-- D-74: a coluna do terreno é toda do material da superfície (capim até o fundo), então a parede
-- e o chão escavados eram de capim, e o capim animado nascia DENTRO das câmaras e galerias (visto
-- no Studio, 2026-11-11). Em volta de cada caixa o capim vira terra antes de escavar.
function TerrainBuilder.carve(boxes: { any }, terrainIn: any?): number
	local terrain = terrainIn or workspace.Terrain
	-- dentro da função: o módulo também carrega no Lune (teste do WriteVoxels), sem Enum.Material
	local GRASSY = { Enum.Material.Grass, Enum.Material.LeafyGrass }
	local n = 0
	for _, b in boxes do
		if b.kind == "carve" then
			local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local c = b.cf
							* Vector3.new(sx * (b.size.X / 2 + 3), sy * (b.size.Y / 2 + 3), sz * (b.size.Z / 2 + 3))
						lo, hi = lo:Min(c), hi:Max(c)
					end
				end
			end
			local region = Region3.new(lo, hi):ExpandToGrid(4)
			for _, m in GRASSY do
				terrain:ReplaceMaterial(region, 4, m, Enum.Material.Ground)
			end
			terrain:FillBlock(b.cf, b.size, Enum.Material.Air)
			n += 1
		end
	end
	return n
end

return TerrainBuilder
