--!strict
-- Troca os placeholders do greybox pelos modelos do ForgeGUI publicados no Roblox (AssetIds).
-- Com ID 0 nada muda. F3 = setor central com arte final; o resto do mapa entra na F5 (D-14).
-- Posicionamento determinístico (semente fixa), sempre no chão real do terreno.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Rng = require(ReplicatedStorage.Shared.Rng)
local Tunnels = require(ReplicatedStorage.Shared.Tunnels) :: any

local AssetLoader = {}
local cache: { [string]: Model } = {}
local M = 0.28
-- F5: arte nos 5 setores, com teto por setor (Parte 2: 60 fps no pior setor). Triângulos por
-- instância saem do manifest (depois do remesh da F5: vegetação ≤ 3k, props ≤ 5k). O teto é
-- conservador até a medição no Studio (D-45).
local SLICE_SECTORS = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
AssetLoader.SECTOR_TRI_BUDGET = 2500000 -- triângulos estimados de arte por setor (PLACEHOLDER)
AssetLoader.TRIS = {
	bamboo_clump = 2800,
	shrub = 2800,
	elephant_grass = 2800,
	banana = 2800,
	coconut_palm = 2800,
	hill_tree = 2800,
	hut_thatch = 4800,
	hut_veranda = 4800,
	hut_kitchen = 4800,
	house_tile = 4800,
} :: { [string]: number }
local DEFAULT_TRIS = 4800
local sectorTris: { [number]: number } = {}
local sectorCount: { [number]: number } = {}
-- peças grandes ganham imagem simplificada (impostor) quando estão fora do raio de streaming
local BIG: { [string]: boolean } = {
	hut_thatch = true,
	hut_veranda = true,
	hut_kitchen = true,
	house_tile = true,
	hill_tree = true,
	coconut_palm = true,
	granary = true,
	vc_bunker = true,
}
-- Quanto (m) a base do modelo fica abaixo do chão: a entrada do túnel tem ~0,3 m de poço sob a
-- moldura; a trincheira apoia no fundo da vala já escavada no terreno (TRENCH_D_M).
local SINK_M: { [string]: number } = {
	tunnel_entrance = 0.3,
	trench_section = Tunnels.TRENCH_D_M,
}

-- Carrega o modelo publicado (uma vez) e devolve um template ancorado, sem colisão de folhagem.
function AssetLoader.template(key: string): Model?
	if cache[key] then
		return cache[key]
	end
	local id = AssetIds.Models[key]
	if type(id) ~= "number" or id == 0 then
		return nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not container then
		warn("[VT65] não carregou o asset", key, id, container)
		return nil
	end
	local model = container:FindFirstChildWhichIsA("Model") or container
	local tpl: Model
	if model:IsA("Model") then
		tpl = model
	else
		tpl = Instance.new("Model")
		for _, c in container:GetChildren() do
			c.Parent = tpl
		end
	end
	for _, d in tpl:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	cache[key] = tpl
	return tpl
end

-- Altura do chão: o maior de 5 raios (centro e ±0,8 m), para que poços de túnel e a vala da
-- trincheira (já escavados no terreno) não puxem o modelo para o fundo.
local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local d = 0.8 / M
	local best = -math.huge
	for _, o in { { 0, 0 }, { d, 0 }, { -d, 0 }, { 0, d }, { 0, -d } } do
		local hit = workspace:Raycast(Vector3.new(x + o[1], 2000, z + o[2]), Vector3.new(0, -4000, 0), params)
		if hit then
			best = math.max(best, hit.Position.Y)
		end
	end
	return if best > -math.huge then best else 0
end

-- coloca uma cópia com a base no chão; foliage=true desliga colisão/consulta/sombra (Parte 5)
function AssetLoader.place(key: string, x: number, z: number, yaw: number, parent: Instance, foliage: boolean?): Model?
	local tpl = AssetLoader.template(key)
	if not tpl then
		return nil
	end
	local sector = Geometry.sectorAt(MapConfig.Sectors, x, z) or 0
	local tris = AssetLoader.TRIS[key] or DEFAULT_TRIS
	if (sectorTris[sector] or 0) + tris > AssetLoader.SECTOR_TRI_BUDGET then
		return nil -- teto do setor atingido: o placeholder (se houver) continua
	end
	sectorTris[sector] = (sectorTris[sector] or 0) + tris
	sectorCount[sector] = (sectorCount[sector] or 0) + 1
	local m = tpl:Clone()
	m.Name = key
	local cf, size = m:GetBoundingBox()
	local pivotToBottom = m:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
	local y = groundY(x, z) + pivotToBottom - (SINK_M[key] or 0) / M
	m:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0))
	if foliage then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CastShadow = false
				d:SetAttribute("Material", "Bamboo")
			end
		end
	end
	m.Parent = parent
	return m
end

local function inSlice(x: number, z: number): boolean
	local s = Geometry.sectorAt(MapConfig.Sectors, x, z)
	return s ~= nil and SLICE_SECTORS[s] == true
end

function AssetLoader.start()
	local map = workspace:WaitForChild("Map", 30)
	if not map then
		return
	end
	local out = Instance.new("Folder")
	out.Name = "Art"
	out.Parent = map
	local rng = Rng.new(19650818)
	-- casas: variante por sorteio; o placeholder some (fica só se não houver modelo)
	local variants = { "hut_thatch", "hut_veranda", "hut_thatch", "hut_kitchen", "house_tile" }
	local houses = map:FindFirstChild("Houses")
	if houses then
		for _, h in houses:GetChildren() do
			local body = h:FindFirstChild("Walls") :: BasePart?
			if h:IsA("Model") and body then
				local p = body.Position
				local _, yaw, _ = body.CFrame:ToOrientation()
				local key = variants[1 + math.floor(rng:next() * #variants)]
				if AssetLoader.place(key, p.X, p.Z, yaw, out) then
					h:Destroy()
					-- quintal: bananeira e coqueiro ao redor (densidade da Parte 5)
					if rng:next() < 0.35 then
						local a = rng:range(0, 2 * math.pi)
						AssetLoader.place("coconut_palm", p.X + math.cos(a) * 30, p.Z + math.sin(a) * 30, a, out, true)
					end
					if rng:next() < 0.3 then
						local a = rng:range(0, 2 * math.pi)
						AssetLoader.place("banana", p.X + math.cos(a) * 16, p.Z + math.sin(a) * 16, a, out, true)
					end
				end
			end
		end
	end
	-- bambu das vilas: touceiras ao longo das sebes (a peça fica invisível e mantém colisão e visada)
	local hedges = map:FindFirstChild("Hedges")
	if hedges and AssetLoader.template("bamboo_clump") then
		for _, hp in hedges:GetChildren() do
			if hp:IsA("BasePart") and hp.Name == "BambooHedge" and inSlice(hp.Position.X, hp.Position.Z) then
				local n = math.max(1, math.floor(hp.Size.X * M / 7))
				for i = 1, n do
					local t = (i - 0.5) / n - 0.5
					local pos = hp.CFrame * CFrame.new(t * hp.Size.X, 0, 0)
					AssetLoader.place("bamboo_clump", pos.X, pos.Z, rng:range(0, 6.28), out, true)
				end
				hp.Transparency = 1
			elseif hp:IsA("BasePart") and hp.Name == "PaddyHedge" and inSlice(hp.Position.X, hp.Position.Z) then
				local key = if rng:next() < 0.5 then "shrub" else "elephant_grass"
				if AssetLoader.template(key) then
					local n = math.max(1, math.floor(hp.Size.X * M / 3))
					for i = 1, n do
						local t = (i - 0.5) / n - 0.5
						local pos = hp.CFrame * CFrame.new(t * hp.Size.X, 0, 0)
						AssetLoader.place(key, pos.X, pos.Z, rng:range(0, 6.28), out, true)
					end
					hp.Transparency = 1
				end
			end
		end
	end
	-- túneis e trincheira sul de An Cường (2)
	local cx, cz = 0, 0
	for _, l in MapConfig.Locations do
		if l.name == "An Cường (2)" then
			cx, cz = l.x, l.z
		end
	end
	for id, n in Tunnels.nodes do
		if n.entrance then
			local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
			AssetLoader.place("tunnel_entrance", x, z, rng:range(0, 6.28), out)
			-- bunker de toras ao lado das entradas da vila (não na do arrozal nem na da trincheira)
			if id == "E1" or id == "E2" or id == "E4" then
				AssetLoader.place("vc_bunker", x + 9 / M, z + 4 / M, rng:range(0, 6.28), out)
			end
		end
	end
	if AssetLoader.template("trench_section") then
		for i = 1, #Tunnels.trench - 1 do
			local a, b = Tunnels.trench[i], Tunnels.trench[i + 1]
			local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
			local yaw = math.atan2(-(b[2] - a[2]), b[1] - a[1])
			for k = 0, math.floor(len / 4) - 1 do
				local t = (k + 0.5) * 4 / len
				local xm, zm = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
				local x, z = Tunnels.toWorld(cx, cz, xm, zm)
				AssetLoader.place("trench_section", x, z, yaw + math.pi / 2, out)
			end
		end
	end
	-- vila: altar e poço no centro de An Cường (2); túmulos no cemitério da carta (S2)
	AssetLoader.place("shrine", cx + 25, cz + 10, 0, out)
	AssetLoader.place("well", cx - 18, cz + 22, 0, out)
	for _, sp in MapConfig.Strongpoints do
		if sp.name == "Cemitério" then
			for k = 1, 6 do
				local a = k * 1.05
				AssetLoader.place("grave_mound", sp.x + math.cos(a) * 25, sp.z + math.sin(a) * 25, a, out)
			end
		elseif sp.name == "Vau do riacho" then
			AssetLoader.place("log_bridge", sp.x, sp.z, rng:range(0, 3.14), out)
		end
	end
	-- árvores das colinas (cotas 43, 30 e 22): bosque ralo no topo (densidade de design)
	if AssetLoader.template("hill_tree") then
		for _, l in MapConfig.Locations do
			if string.find(l.name, "Colina") then
				for _ = 1, 60 do
					local a, r = rng:range(0, 2 * math.pi), math.sqrt(rng:next()) * 110 / M
					AssetLoader.place("hill_tree", l.x + math.cos(a) * r, l.z + math.sin(a) * r, a, out, true)
				end
			end
		end
	end
	-- streaming (D-15): cada modelo chega inteiro; os grandes têm impostor à distância
	for _, m in out:GetChildren() do
		if m:IsA("Model") then
			m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			if BIG[m.Name] then
				m.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
			end
		end
	end
	for sector = 0, 5 do
		if sectorCount[sector] then
			print(
				string.format(
					"[VT65] arte setor %d: %d modelos, ~%.0f mil triângulos",
					sector,
					sectorCount[sector],
					(sectorTris[sector] or 0) / 1000
				)
			)
		end
	end
	print("[VT65] arte carregada:", #out:GetChildren(), "modelos")
end

-- Eixo longo de cada GLB preparado: quase todos em Z; o RPG-2 veio em X (manifest dim_studs_xyz).
local WEAPON_TURN: { [string]: CFrame } = {
	rpg2 = CFrame.Angles(0, math.pi / 2, 0),
}

-- Arma visível na mão direita (todos veem). Sem asset publicado, nada acontece.
function AssetLoader.attachWeapon(model: Model, weaponId: string)
	local tpl = AssetLoader.template(weaponId)
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	if not (tpl and hand) then
		return
	end
	local w = tpl:Clone()
	for _, d in w:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	local primary = w.PrimaryPart or w:FindFirstChildWhichIsA("BasePart")
	if not primary then
		return
	end
	w:PivotTo(hand.CFrame * CFrame.Angles(-math.pi / 2, 0, 0) * (WEAPON_TURN[weaponId] or CFrame.identity))
	for _, d in w:GetDescendants() do
		if d:IsA("BasePart") and d ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = primary, d
			weld.Parent = d
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = hand, primary
	weld.Parent = primary
	w.Name = "Weapon"
	w.Parent = model
end

return AssetLoader
