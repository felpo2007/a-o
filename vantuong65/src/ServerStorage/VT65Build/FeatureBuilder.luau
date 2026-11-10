--!strict
-- Cria as peças do greybox (diques, lâminas d'água, sebes, casas, pontos fortes, QGs).
-- Recebe o "ambiente" (Instance, Vector3, CFrame, Color3, Enum) para rodar igual no Roblox
-- e no Lune (tools/bake_place.luau assa as peças direto no arquivo .rbxl).
local FeatureBuilder = {}

export type Env = {
	Instance: any,
	Vector3: any,
	CFrame: any,
	Color3: any,
	Enum: any,
}

local M = 0.28
local DIKE_W = 0.6 / M
local WATER_T = 0.08 / M

local function folder(env: Env, name: string, parent: any): any
	local f = env.Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function part(env: Env, cls: string?): any
	local p = env.Instance.new(cls or "Part")
	p.Anchored = true
	p.TopSurface = env.Enum.SurfaceType.Smooth
	p.BottomSurface = env.Enum.SurfaceType.Smooth
	return p
end

-- segmento horizontal de (x1,z1) a (x2,z2), com base em y0 e altura h, espessura t
local function segmentCFrame(env: Env, x1: number, z1: number, x2: number, z2: number, yc: number)
	local mid = env.Vector3.new((x1 + x2) / 2, yc, (z1 + z2) / 2)
	local dir = env.Vector3.new(x2 - x1, 0, z2 - z1)
	local ang = math.atan2(-(z2 - z1), x2 - x1) -- rotação em Y que leva +X para dir
	return env.CFrame.new(mid.X, mid.Y, mid.Z) * env.CFrame.Angles(0, ang, 0), dir.Magnitude
end

export type Stats = { dikes: number, hedges: number, waters: number, houses: number, markers: number }

function FeatureBuilder.build(env: Env, features: any, mapConfig: any, world: any?, parent: any): Stats
	local root = folder(env, "Map", parent)
	local stats = { dikes = 0, hedges = 0, waters = 0, houses = 0, markers = 0 }
	local C = env.Color3.fromRGB

	-- diques de arrozal: x1,z1,x2,z2,yTop,yBase
	local fd = folder(env, "Dikes", root)
	local d = features.dikes
	for i = 1, #d, 6 do
		local yTop, yBase = d[i + 4], d[i + 5]
		local cf, len = segmentCFrame(env, d[i], d[i + 1], d[i + 2], d[i + 3], (yTop + yBase) / 2)
		local p = part(env)
		p.Name = "Dike"
		p.Size = env.Vector3.new(len + DIKE_W, math.max(yTop - yBase, 0.5), DIKE_W)
		p.CFrame = cf
		p.Material = env.Enum.Material.Ground
		p.Color = C(110, 94, 68) -- #6E5E44 (dique de várzea)
		p.CastShadow = false
		p.Parent = fd
		stats.dikes += 1
	end

	-- lâmina d'água dos quadros: x,z,yNivel,tamU,tamV,ang
	local fw = folder(env, "PaddyWater", root)
	local w = features.waters
	for i = 1, #w, 6 do
		local p = part(env)
		p.Name = "PaddyWater"
		p.Size = env.Vector3.new(math.max(w[i + 3], 1), WATER_T, math.max(w[i + 4], 1))
		p.CFrame = env.CFrame.new(w[i], w[i + 2] - WATER_T / 2, w[i + 1]) * env.CFrame.Angles(0, w[i + 5], 0)
		p.Material = env.Enum.Material.SmoothPlastic
		p.Color = C(94, 82, 66) -- água barrenta
		p.Transparency = 0.25
		p.Reflectance = 0.05
		p.CanCollide = false
		p.CanTouch = false
		p.CastShadow = false
		p:SetAttribute("Material", "PaddyWater") -- tabela própria de passos/penetração (Parte 5)
		p.Parent = fw
		stats.waters += 1
	end

	-- sebes: x1,z1,x2,z2,yBase,altura,espessura
	local fh = folder(env, "Hedges", root)
	local hg = features.hedges
	for i = 1, #hg, 7 do
		local yBase, hh, th = hg[i + 4], hg[i + 5], hg[i + 6]
		local cf, len = segmentCFrame(env, hg[i], hg[i + 1], hg[i + 2], hg[i + 3], yBase + hh / 2)
		local p = part(env)
		p.Name = if hh > 3 / M then "BambooHedge" else "PaddyHedge"
		p.Size = env.Vector3.new(len + th * 0.5, hh, th)
		p.CFrame = cf
		p.Material = env.Enum.Material.LeafyGrass
		p.Color = if hh > 3 / M then C(86, 100, 56) else C(95, 108, 59)
		p.CastShadow = hh > 3 / M
		p:SetAttribute("Material", "Bamboo") -- esconde, não para bala (Parte 3)
		p.Parent = fh
		stats.hedges += 1
	end

	-- casas (placeholder da casa de palha de 7 x 4,5 m): x,z,yChao,ang
	local fc = folder(env, "Houses", root)
	local hs = features.houses
	for i = 1, #hs, 4 do
		local x, z, y, a = hs[i], hs[i + 1], hs[i + 2], hs[i + 3]
		local model = env.Instance.new("Model")
		model.Name = "HutPlaceholder"
		local base = env.CFrame.new(x, y, z) * env.CFrame.Angles(0, a, 0)
		local wallH, L, W = 2.4 / M, 7 / M, 4.5 / M
		local body = part(env)
		body.Name = "Walls"
		body.Size = env.Vector3.new(L, wallH, W)
		body.CFrame = base * env.CFrame.new(0, wallH / 2, 0)
		body.Material = env.Enum.Material.Slate
		body.Color = C(160, 138, 104) -- #A08A68 (taipa)
		body:SetAttribute("Material", "MudWall")
		body.Parent = model
		local roofH = 2.2 / M
		for sgn = -1, 1, 2 do
			local r = part(env, "WedgePart")
			r.Name = "Roof"
			r.Size = env.Vector3.new(L + 1 / M, roofH, W / 2 + 0.6 / M)
			r.CFrame = base
				* env.CFrame.new(0, wallH + roofH / 2, sgn * (W / 4 + 0.3 / M))
				* env.CFrame.Angles(0, if sgn > 0 then math.pi else 0, 0) -- lado alto do WedgePart (+Z) para a cumeeira
			r.Material = env.Enum.Material.Grass
			r.Color = C(156, 138, 90) -- palha de arroz
			r:SetAttribute("Material", "Thatch")
			r.Parent = model
		end
		model.PrimaryPart = body
		model.Parent = fc
		stats.houses += 1
	end

	-- pontos fortes e QGs (marcadores de greybox)
	local fs = folder(env, "Strongpoints", root)
	local R = mapConfig.CaptureRadiusStuds
	for _, sp in mapConfig.Strongpoints do
		local y = if world then world:heightAt(sp.x, sp.z) else 0
		local p = part(env)
		p.Name = sp.name
		p.Shape = env.Enum.PartType.Cylinder
		p.Size = env.Vector3.new(2, R * 2, R * 2)
		p.CFrame = env.CFrame.new(sp.x, y + 0.5, sp.z) * env.CFrame.Angles(0, 0, math.pi / 2)
		p.Material = env.Enum.Material.ForceField
		p.Color = C(255, 196, 0)
		p.Transparency = 0.6
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p:SetAttribute("Sector", sp.sector)
		p:SetAttribute("Real", sp.real)
		p:SetAttribute("Note", sp.note)
		p.Parent = fs
		stats.markers += 1
	end
	local fq = folder(env, "HQ", root)
	for fac, hq in mapConfig.HQ do
		local y = if world then world:heightAt(hq.x, hq.z) else 0
		local p = part(env)
		p.Name = "HQ_" .. fac
		p.Size = env.Vector3.new(20, 1, 20)
		p.CFrame = env.CFrame.new(hq.x, y + 0.5, hq.z)
		p.Color = if fac == "US" then C(70, 90, 160) else C(160, 60, 50)
		p.Material = env.Enum.Material.SmoothPlastic
		p:SetAttribute("Faction", fac)
		p.Parent = fq
		stats.markers += 1
	end
	return stats
end

-- Forro dos túneis e poços (peças), a partir das caixas de TunnelGeometry.build.
function FeatureBuilder.tunnels(env: Env, boxes: { any }, parent: any): number
	local root = folder(env, "Tunnels", parent)
	local C = env.Color3.fromRGB
	local n = 0
	for _, b in boxes do
		if b.kind == "carve" then
			continue
		end
		local p
		if b.kind == "truss" then
			p = env.Instance.new("TrussPart")
			p.Anchored = true
			p.Size = env.Vector3.new(2, math.max(2, math.floor(b.size.Y / 2) * 2), 2)
			p.Transparency = 1 -- escada invisível para subir/descer o poço
		else
			p = part(env)
			p.Size = b.size
			p.Material = env.Enum.Material.Ground
			p.Color = if b.kind == "entrance" then C(92, 74, 52) else C(78, 62, 44)
			p.CastShadow = b.kind ~= "entrance"
		end
		p.CFrame = b.cf
		p.Name = b.name .. "_" .. b.kind
		if b.kind == "entrance" then
			p.CanCollide = false
			p.Transparency = 0.2
			p:SetAttribute("TunnelEntrance", b.name)
		end
		p:SetAttribute("Material", "Earth")
		p.Parent = root
		n += 1
	end
	return n
end

return FeatureBuilder
