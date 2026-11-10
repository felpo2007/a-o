--!strict
-- Gera o terreno do greybox (F1) com Terrain:WriteVoxels a partir das alturas exportadas.
-- SÓ RODA NO STUDIO, em modo de edição, pela barra de comando:
--     require(game.ServerStorage.VT65Build.Build).terrain()
-- Depois salve o place. Leva minutos (≈17,9 x 12,1 mil studs, voxels de 4 studs).
local TerrainBuilder = {}

local VOXEL = 4
local CHUNK = 64 -- voxels por lado de bloco horizontal (256 studs)
local STUD_M = 0.28
local STREAM_DEPTH = 0.6 / STUD_M -- lâmina d'água dos riachos (studs)
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

export type Options = {
	yieldEvery: number?,
	-- limita a geração a um retângulo XZ (studs): útil para testes e para regerar um trecho
	only: { minX: number, maxX: number, minZ: number, maxZ: number }?,
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
	local MATERIAL: { [number]: any } = {
		[0] = Enum.Material.Sand,
		[1] = Enum.Material.Sand,
		[2] = Enum.Material.Mud,
		[3] = Enum.Material.Ground,
		[4] = Enum.Material.Grass,
		[5] = Enum.Material.Mud,
	}
	local terrain = env.terrain
	local only = opts and opts.only
	local g = world.grid
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
			local ymin, ymax = math.huge, -math.huge
			for iz = 1, sz do
				for ix = 1, sx do
					local wx = x0 + (cx + ix - 0.5) * VOXEL
					local wz = z0 + (cz + iz - 0.5) * VOXEL
					local h = world:heightAt(wx, wz)
					local c = world:classAt(wx, wz)
					if c == 0 then
						local coast = coastX[math.floor((wz - g.originZ) / g.cellStuds)]
						if coast and wx >= coast then
							local depthM = math.clamp(
								SEA_MIN_M + (wx - coast) * STUD_M * SEA_SLOPE,
								SEA_MIN_M,
								SEA_MAX_M
							)
							h = math.min(h, -depthM / STUD_M)
						end
					end
					local wl = -math.huge
					if c == 0 or h < 0 then
						wl = 0 -- nível do mar
					elseif c == 5 then
						wl = h + STREAM_DEPTH
					end
					local k = (iz - 1) * sx + ix
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
					local h, wl, mat = surf[k], water[k], MATERIAL[cls[k]] or Enum.Material.Ground
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
function TerrainBuilder.carve(boxes: { any }, terrainIn: any?): number
	local terrain = terrainIn or workspace.Terrain
	local n = 0
	for _, b in boxes do
		if b.kind == "carve" then
			terrain:FillBlock(b.cf, b.size, Enum.Material.Air)
			n += 1
		end
	end
	return n
end

return TerrainBuilder
