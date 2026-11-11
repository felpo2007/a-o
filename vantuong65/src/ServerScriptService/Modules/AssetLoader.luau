--!strict
-- Troca os placeholders do greybox pelos modelos do ForgeGUI publicados no Roblox (AssetIds).
-- Com ID 0 nada muda. F3 = setor central com arte final; o resto do mapa entra na F5 (D-14).
-- Posicionamento determinístico (semente fixa), sempre no chão real do terreno.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local ArtBudget = require(script.Parent.ArtBudget)
local Animals = require(ReplicatedStorage.Shared.Animals)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local GunModel = require(ReplicatedStorage.Shared.GunModel)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Rng = require(ReplicatedStorage.Shared.Rng)
local Tunnels = require(ReplicatedStorage.Shared.Tunnels) :: any
local Vegetation = require(script.Parent.Vegetation)
local Weapons = require(ReplicatedStorage.Shared.Weapons)

local AssetLoader = {}
AssetLoader.noGround = 0 -- modelos postos sem terreno embaixo (deve ficar 0)
local cache: { [string]: Model } = {}
local M = 0.28
-- F5: arte nos 5 setores, com teto por setor (Parte 2: 60 fps no pior setor). Triângulos por
-- instância medidos no manifest (ArtBudget, conferido pelo teste da F5). O teto é conservador até a
-- medição no Studio (D-45).
local SLICE_SECTORS = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
AssetLoader.SECTOR_TRI_BUDGET = ArtBudget.SECTOR_MAX
type HedgeJob = { part: BasePart, key: string, n: number, sector: number }
local sectorTris: { [number]: number } = {}
local sectorCount: { [number]: number } = {}
-- Detalhe à distância (Model.LevelOfDetail = SLIM; o StreamingMesh é o valor antigo) nas peças
-- grandes: hut_thatch, hut_veranda, hut_kitchen, house_tile, hill_tree, coconut_palm, granary e
-- vc_bunker. Script do jogo NÃO pode ligar isso ("lacking capability PluginOrOpenCloud", conferido
-- no Studio em 2026-11-10; o luau-lsp acusou). E, pela documentação do SLIM, ele só vale para
-- modelos estáticos de um place publicado, não para modelos inseridos ou mudados em tempo de jogo,
-- como os deste arquivo (D-57). Antes este arquivo tentava ligar em tempo de jogo e daria erro no
-- carregamento da arte assim que os IDs fossem publicados.
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
	if Weapons.get(key) and GunModel.fit(tpl, key) then
		-- cópia para a arma em primeira pessoa (cliente, WeaponVisuals)
		local shared = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
		if not shared then
			shared = Instance.new("Folder")
			shared.Name = "VT65WeaponArt"
			shared.Parent = ReplicatedStorage
		end
		local copy = tpl:Clone()
		copy.Name = key
		copy.Parent = shared
	end
	cache[key] = tpl
	return tpl
end

-- Modelo da arma, com pivô no punho e boca em −Z: o publicado (já preparado por GunModel.fit) ou,
-- sem asset, o provisório. Peças soltas; quem usa decide ancorar ou soldar.
function AssetLoader.weaponModel(weaponId: string, kind: string?): Model
	local tpl = AssetLoader.template(weaponId)
	if tpl and tpl.PrimaryPart then
		local m = tpl:Clone()
		m.Name = "Weapon"
		return m
	end
	return GunModel.build(weaponId, kind)
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
	if best == -math.huge then
		AssetLoader.noGround += 1 -- sem terreno sob o ponto: avisado no resumo da arte
		return 0
	end
	return best
end

-- Coloca uma cópia com a base no chão. foliage=true desliga colisão e toque e marca como folhagem
-- (esconde, não para bala; Parte 5). scale muda o tamanho (variação da mata, D-64). shadow liga a
-- sombra da folhagem: só as árvores, para a luz manchada da mata sem pagar sombra de cada moita.
function AssetLoader.place(
	key: string,
	x: number,
	z: number,
	yaw: number,
	parent: Instance,
	foliage: boolean?,
	scale: number?,
	shadow: boolean?
): Model?
	local tpl = AssetLoader.template(key)
	if not tpl then
		return nil
	end
	local sector = Geometry.sectorAt(MapConfig.Sectors, x, z) or 0
	local tris = ArtBudget.tris(key)
	if (sectorTris[sector] or 0) + tris > AssetLoader.SECTOR_TRI_BUDGET then
		return nil -- teto do setor atingido: o placeholder (se houver) continua
	end
	sectorTris[sector] = (sectorTris[sector] or 0) + tris
	sectorCount[sector] = (sectorCount[sector] or 0) + 1
	local m = tpl:Clone()
	m.Name = key
	if scale and math.abs(scale - 1) > 0.01 then
		m:ScaleTo(m:GetScale() * scale)
	end
	local cf, size = m:GetBoundingBox()
	local pivotToBottom = m:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
	local y = groundY(x, z) + pivotToBottom - (SINK_M[key] or 0) / M
	m:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0))
	if foliage then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CastShadow = shadow == true
				d:SetAttribute("Material", "Bamboo")
			end
		end
	end
	m.Parent = parent
	return m
end

function AssetLoader.start()
	local map = workspace:WaitForChild("Map", 30)
	if not map then
		return
	end
	-- A arte vai no chão real, então espera o terreno, que é gerado em runtime (~50 s). Antes ela era
	-- posta junto com a geração: o raio não achava chão e tudo ia para y = 0. As vilas ficavam
	-- enterradas (até 20 m) sem os placeholders, que já tinham sido apagados, e os animais andavam
	-- debaixo da terra (teste do mapa no Studio, 2026-11-10).
	while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
		ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
	end
	local out = Instance.new("Folder")
	out.Name = "Art"
	out.Parent = map
	local rng = Rng.new(19650818)
	-- casas: variante por sorteio (só as que cabem na meta); o placeholder some (fica só se não houver modelo)
	local variants = ArtBudget.HOUSE_VARIANTS
	local housePos: { number } = {} -- metros, para os animais da vila
	local houses = map:FindFirstChild("Houses")
	if houses then
		for _, h in houses:GetChildren() do
			local body = h:FindFirstChild("Walls") :: BasePart?
			if h:IsA("Model") and body then
				local p = body.Position
				local _, yaw, _ = body.CFrame:ToOrientation()
				local key = variants[1 + math.floor(rng:next() * #variants)]
				table.insert(housePos, p.X * M)
				table.insert(housePos, p.Z * M)
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
					-- quintal (D-64): celeiro de bambu atrás da casa e cerca de bambu na frente
					local frame = CFrame.new(p) * CFrame.Angles(0, yaw, 0)
					if rng:next() < 0.15 then
						local g = (frame * CFrame.new(0, 0, 8 / M)).Position
						AssetLoader.place("granary", g.X, g.Z, yaw, out)
					end
					if rng:next() < 0.3 then
						for k = -1, 1 do
							local f = (frame * CFrame.new(k * 3 / M, 0, -6.5 / M)).Position
							AssetLoader.place("bamboo_fence", f.X, f.Z, yaw, out)
						end
					end
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
	-- QGs (D-64): antes, uma placa de plástico colorida. EUA: anel de sacos de areia com quatro
	-- entradas; VC: cerca de bambu, dois celeiros e um bunker de toras.
	local usHQ, vcHQ = MapConfig.HQ.US, MapConfig.HQ.VC
	for i = 0, 11 do
		if i % 3 ~= 0 then
			local a = i * math.pi / 6
			AssetLoader.place(
				"sandbags",
				usHQ.x + math.cos(a) * 14 / M,
				usHQ.z + math.sin(a) * 14 / M,
				-a + math.pi / 2,
				out
			)
		end
	end
	for i = 0, 15 do
		if i % 4 ~= 0 then
			local a = i * math.pi / 8
			AssetLoader.place(
				"bamboo_fence",
				vcHQ.x + math.cos(a) * 18 / M,
				vcHQ.z + math.sin(a) * 18 / M,
				-a + math.pi / 2,
				out
			)
		end
	end
	AssetLoader.place("granary", vcHQ.x - 10 / M, vcHQ.z + 8 / M, 0.4, out)
	AssetLoader.place("granary", vcHQ.x - 12 / M, vcHQ.z - 7 / M, 2.1, out)
	AssetLoader.place("vc_bunker", vcHQ.x + 11 / M, vcHQ.z - 4 / M, -math.pi / 2, out)
	-- tocas de atirador (spider hole) em volta dos pontos fortes que começam com o VC ou neutros
	for _, sp in MapConfig.Strongpoints do
		if sp.sector <= 3 then
			for _ = 1, 3 do
				local a, r = rng:range(0, 2 * math.pi), rng:range(25, 45) / M
				AssetLoader.place(
					"spider_hole",
					sp.x + math.cos(a) * r,
					sp.z + math.sin(a) * r,
					rng:range(0, 6.28),
					out
				)
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
		end
	end
	-- ponte de toras no riacho a leste de An Cường (2): o vau do riacho ficou fora do mapa de 2 x 2 km
	for _, l in MapConfig.Locations do
		if string.find(l.name, "Riacho", 1, true) then
			AssetLoader.place("log_bridge", l.x, l.z, rng:range(0, 3.14), out)
		end
	end
	-- árvores das colinas (cotas 43 e 30 no mapa de 2 x 2 km): bosque ralo no topo (densidade de design)
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
	-- animais da vila (Parte 11): antes das sebes no orçamento; o AnimalService os move
	if AssetLoader.template("water_buffalo") or AssetLoader.template("chicken") then
		local pen = Instance.new("Folder")
		pen.Name = "Animals"
		for _, sp in
			Animals.spawns(housePos, function()
				return rng:next()
			end)
		do
			AssetLoader.place(sp.species, sp.x / M, sp.z / M, rng:range(0, 6.28), pen, true)
		end
		pen.Parent = out
	end
	-- Sebes por último. O que sobra do teto de cada setor vira um desbaste uniforme no setor (e não
	-- um corte no meio do mapa). A peça da sebe só fica invisível se TODAS as touceiras dela
	-- entraram; senão continua como enchimento, para nunca haver cobertura invisível.
	local hedges = map:FindFirstChild("Hedges")
	if hedges then
		local jobs: { HedgeJob } = {}
		local demand: { [number]: number } = {}
		for _, hp in hedges:GetChildren() do
			if hp:IsA("BasePart") and (hp.Name == "BambooHedge" or hp.Name == "PaddyHedge") then
				local s = Geometry.sectorAt(MapConfig.Sectors, hp.Position.X, hp.Position.Z)
				if s and SLICE_SECTORS[s] then
					local tall = hp.Name == "BambooHedge"
					local key = if tall then "bamboo_clump" elseif rng:next() < 0.5 then "shrub" else "elephant_grass"
					if AssetLoader.template(key) then
						local n = ArtBudget.hedgeClumps(hp.Size.X * M, tall)
						table.insert(jobs, { part = hp, key = key, n = n, sector = s })
						demand[s] = (demand[s] or 0) + n * ArtBudget.tris(key)
					end
				end
			end
		end
		local factor: { [number]: number } = {}
		for s, d in demand do
			factor[s] = ArtBudget.factor(sectorTris[s] or 0, d)
			print(string.format("[VT65] sebes setor %d: %.0f%% das touceiras (teto do setor)", s, 100 * factor[s]))
		end
		for k, j in jobs do
			if k % 100 == 0 then
				-- com as sebes a 100% (D-64) o laço passou do limite de 10 s de script (Studio, 2026-11-10)
				task.wait()
			end
			local hp = j.part
			local placed = 0
			for i = 1, j.n do
				if rng:next() < factor[j.sector] then
					local t = (i - 0.5) / j.n - 0.5
					local pos = hp.CFrame * CFrame.new(t * hp.Size.X, 0, 0)
					if AssetLoader.place(j.key, pos.X, pos.Z, rng:range(0, 6.28), out, true) then
						placed += 1
					end
				end
			end
			if placed == j.n then
				hp.Transparency = 1
			end
		end
	end
	-- Mata por uso do solo (D-64), por último: bosque nas vilas e matas, moitas em manchas no capim,
	-- bambu nos riachos e cortina de árvores fora da borda. Como nas sebes, o que não cabe no teto
	-- do setor vira desbaste uniforme no setor inteiro.
	local world = (require(ServerStorage:WaitForChild("VT65Build"):WaitForChild("Build")) :: any).world()
	-- canteiros de arroz (rice_patch, 13 mil triângulos cada): um por vila, 2 x 4 mudas na beira do arrozal
	for _, l in MapConfig.Locations do
		if l.name == "An Cường (2)" or l.name == "Nam Yên (4)" or l.name == "An Thới (2)" then
			for _ = 1, 60 do
				local a, r = rng:range(0, 2 * math.pi), rng:range(35, 80) / M
				local x0, z0 = l.x + math.cos(a) * r, l.z + math.sin(a) * r
				if world:classAt(x0, z0) == 2 then
					local plot = CFrame.new(x0, 0, z0) * CFrame.Angles(0, a, 0)
					for i = 0, 3 do
						for j = 0, 1 do
							local t = (plot * CFrame.new(i * 2 / M, 0, j * 1.45 / M)).Position
							AssetLoader.place("rice_patch", t.X, t.Z, a, out, true)
						end
					end
					break
				end
			end
		end
	end
	local housesXZ: { number } = {}
	for i = 1, #housePos, 2 do
		table.insert(housesXZ, housePos[i] / M)
		table.insert(housesXZ, housePos[i + 1] / M)
	end
	local tunnelXZ: { number } = {}
	for _, n in Tunnels.nodes do
		local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
		table.insert(tunnelXZ, x)
		table.insert(tunnelXZ, z)
	end
	local corridors: { Vegetation.Segment } = {}
	for i = 1, #Tunnels.trench - 1 do
		local a, b = Tunnels.trench[i], Tunnels.trench[i + 1]
		local x1, z1 = Tunnels.toWorld(cx, cz, a[1], a[2])
		local x2, z2 = Tunnels.toWorld(cx, cz, b[1], b[2])
		table.insert(corridors, { x1 = x1, z1 = z1, x2 = x2, z2 = z2, w = 4 / M })
	end
	-- raias do campo de tiro (TrainingService escolhe a direção com visada livre): do QG a cada alvo
	local camp = workspace:FindFirstChild("CampoDeTiro") or workspace:WaitForChild("CampoDeTiro", 30)
	for f, hq in MapConfig.HQ do
		local lane = camp and camp:FindFirstChild(f)
		for _, d in if lane then lane:GetChildren() else {} do
			if string.sub(d.Name, 1, 4) == "Alvo" then
				local p = if d:IsA("Model") then d:GetPivot().Position elseif d:IsA("BasePart") then d.Position else nil
				if p then
					table.insert(corridors, { x1 = hq.x, z1 = hq.z, x2 = p.X, z2 = p.Z, w = 10 / M })
				end
			end
		end
	end
	local VT65Build = ServerStorage:WaitForChild("VT65Build")
	local landscape = (require(VT65Build:WaitForChild("Landscape")) :: any).new(world, MapConfig, housesXZ)
	local plan = Vegetation.plan({
		classAt = function(x: number, z: number): number
			return world:classAt(x, z)
		end,
		kindAt = function(x: number, z: number): number
			return landscape:kindAt(x, z)
		end,
		bounds = MapConfig.Bounds,
		cell = world.grid.cellStuds,
		exclude = Vegetation.exclusions(MapConfig, housesXZ, tunnelXZ),
		corridors = corridors,
		density = ArtBudget.JUNGLE_DENSITY,
		seed = 1965,
		rng = Rng.new(19650818 + 64),
		yield = function()
			task.wait()
		end,
	})
	local jDemand: { [number]: number } = {}
	for _, it in plan do
		local s = Geometry.sectorAt(MapConfig.Sectors, it.x, it.z) or 0
		jDemand[s] = (jDemand[s] or 0) + ArtBudget.tris(it.key)
	end
	local jFactor: { [number]: number } = {}
	for s, d in jDemand do
		jFactor[s] = ArtBudget.factor(sectorTris[s] or 0, d)
		print(string.format("[VT65] mata setor %d: %.0f%% do plano (teto do setor)", s, 100 * jFactor[s]))
	end
	local jungle = Instance.new("Folder")
	jungle.Name = "Jungle"
	jungle.Parent = out
	local jrng = Rng.new(64)
	local nJungle = 0
	for i, it in plan do
		local s = Geometry.sectorAt(MapConfig.Sectors, it.x, it.z) or 0
		if jrng:next() < jFactor[s] then
			local key, scale = it.key, it.scale
			local fb = Vegetation.FALLBACK[key]
			if fb and not AssetLoader.template(key) then
				key, scale = fb[1], scale * fb[2] -- espécie nova ainda sem ID publicado (D-65)
			end
			if AssetLoader.place(key, it.x, it.z, it.yaw, jungle, true, scale, it.shadow) then
				nJungle += 1
			end
		end
		if i % 200 == 0 then
			task.wait() -- não trava o servidor enquanto planta milhares de modelos
		end
	end
	print(string.format("[VT65] mata: %d plantas de %d no plano", nJungle, #plan))
	-- streaming (D-15): cada modelo chega inteiro (o impostor vem do próprio asset; ver acima)
	for _, folder in { out, jungle } do
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
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
	if AssetLoader.noGround > 0 then
		warn(string.format("[VT65] %d modelos de arte sem terreno embaixo (postos em y = 0)", AssetLoader.noGround))
	end
	out:SetAttribute("Placed", true) -- o autoteste confere a arte no chão depois disto
end

-- Arma visível na mão direita (todos veem). Sem asset publicado, usa a provisória (Shared/GunModel):
-- antes ninguém aparecia armado. Troca a anterior (arma do inimigo pega do chão).
function AssetLoader.attachWeapon(model: Model, weaponId: string)
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	local wp = Weapons.get(weaponId)
	if not (hand and wp) then
		return
	end
	local old = model:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	-- a arma publicada chega aninhada (Model > Model > Model > MeshPart) e centrada na caixa; antes
	-- ela nunca aparecia (a busca da peça não era recursiva) e, se aparecesse, ficaria atravessada.
	-- weaponModel devolve já com pivô no punho e boca em −Z (teste com a arte publicada, 2026-11-10)
	local w = AssetLoader.weaponModel(weaponId, wp.kind)
	for _, d in w:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Massless = true
		end
	end
	local primary = w.PrimaryPart
	if not primary then
		return
	end
	w:PivotTo(hand.CFrame * CFrame.Angles(-math.pi / 2, 0, 0))
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
