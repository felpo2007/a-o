--!strict
-- Troca os placeholders do greybox pelos modelos do ForgeGUI publicados no Roblox (AssetIds).
-- Com ID 0 nada muda. F3 = setor central com arte final; o resto do mapa entra na F5 (D-14).
-- Posicionamento determinístico (semente fixa). 2026-11-12: o lugar e a altura de cada coisa vêm do
-- plano da arte (ArtPlan), o mesmo que gerou o terreno.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local ArtBudget = require(script.Parent.ArtBudget)
local ArtPlan = require(script.Parent.ArtPlan) :: any
local Animals = require(ReplicatedStorage.Shared.Animals)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local GunModel = require(ReplicatedStorage.Shared.GunModel)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local MapLife = require(script.Parent.MapLife)
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
AssetLoader.SECTOR_TRI_BUDGET = ArtBudget.SECTOR_MAX
local sectorTris: { [number]: number } = {}
local sectorCount: { [number]: number } = {}
-- vilas da carta com gente morando (D-74): canteiro de muda e manada de búfalos no arrozal. Mapa de
-- 1 x 1 km (2026-11-11): Nam Yên (4), An Thới (2) e An Cường (2) (as outras ficaram fora do recorte).
-- D-114 (500 x 500 m): só An Cường (2) segue no mapa; as outras duas ficam aqui sem efeito.
local VILLAGES: { [string]: boolean } = {
	["An Cường (2)"] = true,
	["Nam Yên (4)"] = true,
	["An Thới (2)"] = true,
}
-- Mata, dentro da área: a base vai ao chão no centro do pé, 15 cm abaixo (a raiz entra no chão).
-- Antes eram 5 raios no pé do tronco (o mais baixo); com ~45 mil plantas eram ~230 mil raios só
-- para assentar a mata. Na ladeira mais forte do recorte (~12°) o pé de 1 m varia ±0,1 m.
local FOLIAGE_SINK_M = 0.15
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

-- Grupos de colisão (D-67): o tronco das árvores prontas segura gente e bala, mas não o chassi dos
-- veículos. Com o tronco sólido, um M48 parava em cada árvore da mata.
AssetLoader.TRUNK_GROUP = "VT65Tronco"
AssetLoader.VEHICLE_GROUP = "VT65Veiculo"
local groupsReady = false
function AssetLoader.ensureGroups()
	if groupsReady then
		return
	end
	local PhysicsService = game:GetService("PhysicsService")
	for _, g in { AssetLoader.TRUNK_GROUP, AssetLoader.VEHICLE_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(AssetLoader.TRUNK_GROUP, AssetLoader.VEHICLE_GROUP, false)
	groupsReady = true
end

-- Data/Bases (as bases dos dois lados e as casas únicas da vila), carregado na primeira vez
local bases: any = nil
local function baseData(): any
	if bases == nil then
		local ok, m = pcall(function(): any
			local data = ServerStorage:WaitForChild("VT65Build"):WaitForChild("Data"):FindFirstChild("Bases")
			return if data then (require :: any)(data) else false
		end)
		bases = if ok then m else false
	end
	return if bases then bases else nil
end

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
		-- Árvore pronta do Poly Haven (D-67): folhas em cartão. O importador do Open Cloud traz a
		-- textura com AlphaMode Overlay e face única; o script do jogo pode trocar (conferido no
		-- Studio, 2026-11-11). O template é clonado, então vale para todas as cópias.
		if d:IsA("MeshPart") and string.sub(d.Name, 1, 6) == "Folhas" then
			d.DoubleSided = true
			local sa = d:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				sa.AlphaMode = Enum.AlphaMode.Transparency
			end
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
	-- objetos das bases e casas únicas da vila (Blender, 2026-11-13): nós visuais sem colisão,
	-- Colisao_* invisíveis com o Material, Zona_* só toque (MapLife.baseTemplate)
	local data = baseData()
	local rules = data and data.nodes and data.nodes[key]
	if rules then
		local rangeM: number? = nil
		if key == "us_range_target" then
			rangeM = data.US.range.targetM
		elseif key == "vc_range_target" then
			rangeM = data.VC.range.targetM
		end
		MapLife.baseTemplate(tpl, rules, rangeM)
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

-- Assentamento em ladeira (D-73). Medido no Studio (2026-11-11): 217 modelos com a base até 1,2 m
-- acima do lado de baixo do chão (casas, celeiros, cercas, túmulos, coqueiros), porque a base ia
-- para o ponto mais alto de 5 raios.
-- - PLATFORM: construções e montes. A base fica no ponto mais alto do chão sob a planta (sem chão
--   entrando na casa) e o terreno embaixo é aterrado até ela: o patamar de terra batida das casas
--   da região.
-- - Folhagem e cerca: a base vai ao ponto mais baixo sob o tronco (a raiz entra na encosta).
local PLATFORM: { [string]: boolean } = {
	hut_thatch = true,
	hut_veranda = true,
	hut_kitchen = true,
	house_tile = true,
	-- bases (2026-11-13): barracas, bunker, garagem e baias (no plano: Data/Bases, padded)
	us_tent_gp_medium = true,
	us_tent_gp_large = true,
	us_command_tent = true,
	us_mess_tent = true,
	us_bunker = true,
	us_motor_pool = true,
	us_armor_revetment = true,
	granary = true,
	shrine = true,
	well = true,
	grave_mound = true,
	vc_bunker = true,
	sandbags = true,
}
local SINK_LOW: { [string]: boolean } = { bamboo_fence = true }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function groundAt(x: number, z: number): number?
	rayParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), rayParams)
	return if hit then hit.Position.Y else nil
end
-- menor e maior altura do chão na planta (centro e 4 cantos a 45% da meia caixa, girados)
local function footprint(x: number, z: number, yaw: number, hx: number, hz: number): (number?, number?)
	local lo, hi = math.huge, -math.huge
	local rot = CFrame.Angles(0, yaw, 0)
	for _, o in { { 0, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		local p = rot * Vector3.new(o[1] * hx * 0.9, 0, o[2] * hz * 0.9)
		local y = groundAt(x + p.X, z + p.Z)
		if y then
			lo, hi = math.min(lo, y), math.max(hi, y)
		end
	end
	if lo == math.huge then
		return nil, nil
	end
	return lo, hi
end

-- Conta o modelo no teto de triângulos do setor; false se não cabe (D-45).
local function budget(key: string, x: number, z: number): boolean
	local sector = Geometry.sectorAt(MapConfig.Sectors, x, z) or 0
	local tris = ArtBudget.tris(key)
	if (sectorTris[sector] or 0) + tris > AssetLoader.SECTOR_TRI_BUDGET then
		return false
	end
	sectorTris[sector] = (sectorTris[sector] or 0) + tris
	sectorCount[sector] = (sectorCount[sector] or 0) + 1
	return true
end

-- Coloca uma cópia com o meio da base da caixa em `cf` (posição e giro), sem procurar o chão: para
-- o que já tem a altura certa, como a mobília das câmaras dos túneis (debaixo do terreno) e os
-- objetos da vila assentados pelo MapLife. nil sem modelo publicado (quem chama usa as Parts).
function AssetLoader.placeAt(key: string, cf: CFrame, parent: Instance, scale: number?): Model?
	local tpl = AssetLoader.template(key)
	if not tpl or not budget(key, cf.X, cf.Z) then
		return nil
	end
	local m = tpl:Clone()
	m.Name = key
	if scale and math.abs(scale - 1) > 0.01 then
		m:ScaleTo(m:GetScale() * scale)
	end
	m:PivotTo(CFrame.new())
	local box, size = m:GetBoundingBox()
	local bottom = Vector3.new(box.X, box.Y - size.Y / 2, box.Z)
	m:PivotTo(cf * CFrame.new(-bottom))
	m.Parent = parent
	return m
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
	if not budget(key, x, z) then
		return nil -- teto do setor atingido: o placeholder (se houver) continua
	end
	local m = tpl:Clone()
	m.Name = key
	if scale and math.abs(scale - 1) > 0.01 then
		m:ScaleTo(m:GetScale() * scale)
	end
	local cf, size = m:GetBoundingBox()
	local pivotToBottom = m:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
	local base: number
	if SINK_M[key] then
		base = groundY(x, z) -- poço de túnel e vala de trincheira: o mais alto de 5 raios
	elseif foliage then
		local y = groundAt(x, z)
		base = if y then y - FOLIAGE_SINK_M / M else groundY(x, z)
	elseif SINK_LOW[key] then
		local lo = footprint(x, z, yaw, 0.5 / M, 0.5 / M) -- só o pé do mourão
		base = lo or groundY(x, z)
	else
		local lo, hi = footprint(x, z, yaw, size.X / 2, size.Z / 2)
		-- construção com patamar: no mais alto (o patamar aterra o resto). Objeto sem patamar (morteiro
		-- da logística): no mais baixo, entrando no lado de cima da ladeira; no mais alto ficava com o
		-- canto de baixo no ar (2026-11-13, "conserte tudo que esteja flutuando")
		base = (if PLATFORM[key] then hi else lo) or groundY(x, z)
		-- patamar de terra sob a construção, do ponto mais baixo até a base (só se houver vão)
		if PLATFORM[key] and lo and hi and (hi - lo) * M > 0.1 then
			-- o Roblox desenha o chão do FillBlock meio voxel (2 studs) acima do bloco (Studio,
			-- 2026-11-13): sem o desconto o patamar cobria 0,5 m da base (sacos de areia da pá)
			local top = base - 0.02 / M - 2
			local bottom = lo - 0.6 / M
			workspace.Terrain:FillBlock(
				CFrame.new(x, (top + bottom) / 2, z) * CFrame.Angles(0, yaw, 0),
				Vector3.new(size.X + 0.8 / M, top - bottom, size.Z + 0.8 / M),
				Enum.Material.Ground
			)
		end
	end
	local y = base + pivotToBottom - (SINK_M[key] or 0) / M
	m:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0))
	if foliage then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				-- árvore pronta (D-67): o tronco (Madeira0) é sólido e para a bala; copa e galhos não
				local trunk = string.sub(d.Name, 1, 8) == "Madeira0"
				if trunk then
					AssetLoader.ensureGroups()
					d.CollisionGroup = AssetLoader.TRUNK_GROUP
				end
				d.CanCollide = trunk
				d.CanTouch = false
				d.CastShadow = shadow == true
				d:SetAttribute("Material", if trunk then "Wood" else "Bamboo")
			end
		end
	end
	m.Parent = parent
	return m
end

-- Encaixe das peças do bake no terreno real (D-73). O terreno é gerado em tempo de jogo
-- (WriteVoxels, voxel de 4 studs) e a superfície sai ~0,44 m acima da altura que o bake usou. Medido
-- no Studio (2026-11-11): 1.136 das 1.155 lâminas d'água do arrozal com o topo abaixo do chão (o
-- arrozal parecia capim seco), 594 diques enterrados e 134 sebes flutuando até 0,9 m.
-- - lâmina: 6 cm acima da mediana do chão sob ela;
-- - sebe (peça invisível que marca a linha das touceiras): pé no chão e SEM colisão. Era uma parede
--   invisível de 2,3 m no meio da lavoura.
-- Mapa de 1 x 1 km (2026-11-11, achado no Studio: o chão furava a lâmina e o movimento lia "seco"):
-- com `paddies` (ArtPlan: o plano do terreno), o terreno já sai plano debaixo de cada tabuleiro e a
-- lâmina vai ao topo calculado do tabuleiro, 10 cm acima do chão. O dique virou lombada do terreno
-- (2026-11-12, Site.dike).
function AssetLoader.fitFeatures(map: Instance, paddies: any?): { [string]: number }
	local TB = if paddies
		then require(ServerStorage:WaitForChild("VT65Build"):WaitForChild("TerrainBuilder")) :: any
		else nil
	local done: { [string]: number } = { water = 0, dikes = 0, hedges = 0 }
	local function along(p: BasePart, offs: { { number } }): { number }
		local ys = {}
		for _, o in offs do
			local q = p.CFrame * Vector3.new(o[1] * p.Size.X, 0, o[2] * p.Size.Z)
			local y = groundAt(q.X, q.Z)
			if y then
				table.insert(ys, y)
			end
		end
		table.sort(ys)
		return ys
	end
	local function setY(p: BasePart, centerY: number)
		p.CFrame = p.CFrame + Vector3.new(0, centerY - p.Position.Y, 0)
	end
	local i = 0
	local function tick()
		i += 1
		if i % 300 == 0 then
			task.wait()
		end
	end
	local water = map:FindFirstChild("PaddyWater")
	if water then
		for _, p in water:GetDescendants() do
			if p:IsA("BasePart") then
				tick()
				local pad = if TB then TB.paddyOf(paddies, p.Position.X, p.Position.Z) else nil
				if pad then
					setY(p, pad.top - p.Size.Y / 2)
					done.water += 1
				else
					local ys =
						along(p, { { 0, 0 }, { 0.35, 0.35 }, { -0.35, 0.35 }, { 0.35, -0.35 }, { -0.35, -0.35 } })
					if #ys > 0 then
						local med = ys[math.ceil(#ys / 2)]
						setY(p, med + 0.06 / M - p.Size.Y / 2)
						done.water += 1
					end
				end
			end
		end
	end
	-- 2026-11-12: o dique é lombada do terreno (Site.dike); a peça "Dike" é só o marcador invisível
	-- dos bots e não precisa de encaixe
	local line = { { -0.45, 0 }, { -0.2, 0 }, { 0, 0 }, { 0.2, 0 }, { 0.45, 0 } }
	local hedges = map:FindFirstChild("Hedges")
	if hedges then
		for _, p in hedges:GetDescendants() do
			if p:IsA("BasePart") then
				tick()
				p.CanCollide = false
				local ys = along(p, line)
				if #ys > 0 then
					setY(p, ys[1] - 0.1 / M + p.Size.Y / 2)
					done.hedges += 1
				end
			end
		end
	end
	return done
end

-- Assentamento pelo plano (2026-11-12, pedido do dono: "plantas onde não deveriam estar, coisas
-- flutuando, bases de objetos"). O ArtPlan decide onde vai cada coisa e em que altura; o terreno foi
-- gerado pelo mesmo plano (Build.terrain, atributo SitePlan), com o patamar de cada construção aberto
-- no chão, o dique em lombada e a estrada no leito. Aqui só se clona e põe:
-- - construção: o meio da caixa no ponto do plano e a base no patamar (nada de pedestal de terra);
-- - planta: o pé no ponto mais baixo do chão sob ele, 10 cm abaixo (e o disco do bambu enterrado).
-- Sem o atributo (place salvo com terreno antigo), a base volta a sair do raio no chão real.
local PLAN_TOL_M = 0.6 -- plano x chão real no meio da construção: acima disto conta como desvio
AssetLoader.planMismatch = 0

-- Chão REAL mais baixo sob o objeto sem patamar (2026-11-13, "conserte tudo que esteja flutuando").
-- Medido no Studio com o terreno no plano: na encosta forte da Colina 30 e na beira do riacho o chão
-- desenhado (interpolado entre as colunas de 4 studs) sai até 0,5 m abaixo do plano num lado; a toca
-- ficava 0,5 m no ar, a ponte com as cabeceiras a 0,3–0,55 m das margens e algumas plantas com um
-- lado do pé no ar. O objeto vai ao menor entre o plano e o chão real (entra no lado de cima).
-- Boca de túnel e trincheira ficam fora: assentam no poço e na vala escavados.
local OVER_HOLE: { [string]: boolean } = { tunnel_entrance = true, trench_section = true }
local FOOT5 = { { 0, 0 }, { 0.9, 0.9 }, { -0.9, 0.9 }, { 0.9, -0.9 }, { -0.9, -0.9 } }
local BRIDGE_ENDS = { { 0.8, 0 }, { -0.8, 0 } } -- cabeceiras da ponte (eixo X do plano)
local PLANT5 = { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local function realLow(x: number, z: number, yaw: number, hx: number, hz: number, pts: { { number } }): number?
	local lo: number? = nil
	for _, o in pts do
		local px, pz = ArtPlan.rot(x, z, yaw, o[1] * hx, o[2] * hz)
		local y = groundAt(px, pz)
		if y and (lo == nil or y < lo) then
			lo = y
		end
	end
	return lo
end

-- tom da casa da vila sem modelo próprio (ArtPlan.TINTS): multiplica a cor de cada peça
local function tintModel(m: Model, k: number)
	local t = ArtPlan.TINTS[k]
	if not t or (t[1] == 1 and t[2] == 1 and t[3] == 1) then
		return
	end
	local mul = Color3.new(t[1], t[2], t[3])
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			d.Color = Color3.new(c.R * t[1], c.G * t[2], c.B * t[3])
			local sa = d:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				-- SurfaceAppearance.Color multiplica o mapa de cor (sem a propriedade, fica a cor da peça)
				pcall(function()
					(sa :: any).Color = mul
				end)
			end
		end
	end
end

local function foliageParts(m: Model, shadow: boolean)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			-- árvore pronta (D-67): o tronco (Madeira0) é sólido e para a bala; copa e galhos não
			local trunk = string.sub(d.Name, 1, 8) == "Madeira0"
			if trunk then
				AssetLoader.ensureGroups()
				d.CollisionGroup = AssetLoader.TRUNK_GROUP
			end
			d.CanCollide = trunk
			d.CanTouch = false
			d.CastShadow = shadow
			d:SetAttribute("Material", if trunk then "Wood" else "Bamboo")
		end
	end
	if shadow then
		-- copa com sombra: o cliente liga ou desliga pela opção Sombra das árvores (Graficos.client)
		m:SetAttribute("PlantShadow", true)
	end
	-- planta: a raia do campo de tiro pode tirar (TrainingService); construção, não
	m:SetAttribute("Foliage", true)
end

-- Põe um item do plano (ArtPlan.Item). planned: o terreno é o do plano (atributo SitePlan).
function AssetLoader.placeItem(it: any, parent: Instance, planned: boolean): Model?
	if string.sub(it.key, 1, 6) == "parts:" then
		local cf = CFrame.new(it.x, it.base, it.z) * CFrame.Angles(0, it.yaw, 0)
		return MapLife.villagePart(string.sub(it.key, 7), parent, cf, it.hx * 2, it.hz * 2)
	end
	local tpl = AssetLoader.template(it.key)
	if not tpl or not budget(it.key, it.x, it.z) then
		return nil
	end
	local m = tpl:Clone()
	m.Name = it.key
	if math.abs(it.scale - 1) > 0.01 then
		m:ScaleTo(m:GetScale() * it.scale)
	end
	m:PivotTo(CFrame.Angles(0, it.yaw, 0))
	local box, size = m:GetBoundingBox()
	-- com o pivô na origem: o fundo da caixa e (construção) o meio dela
	local bottom = box.Y - size.Y / 2
	local ox, oz = 0, 0
	if not it.foliage then
		ox, oz = box.X, box.Z
	end
	local base = it.base
	if it.foliage then
		-- pé: o mais baixo do chão real no meio e a 0,3–0,6 m em cruz (antes só o meio)
		local rr = math.clamp(it.hx * 0.35, 0.3 / M, 0.6 / M)
		local y = realLow(it.x, it.z, 0, rr, rr, PLANT5)
		if y then
			base = math.min(base, y - ArtPlan.PLANT_SINK_M / M)
		elseif not planned then
			base = groundY(it.x, it.z)
		end
	elseif planned and not it.padded and not OVER_HOLE[it.key] then
		-- objeto sem patamar (caixote, saco, toca, cerca de arame, ponte): o menor entre o plano e o
		-- chão real sob a pegada
		local pts = if it.key == "log_bridge" then BRIDGE_ENDS else FOOT5
		local y = realLow(it.x, it.z, it.yaw, it.hx, it.hz, pts)
		if y then
			base = math.min(base, y - (it.sink or 0))
		end
	elseif not planned then
		-- terreno antigo: base no ponto mais alto do chão sob a pegada (como antes)
		if it.sink then
			base = groundY(it.x, it.z) - it.sink
		else
			local _, hi = footprint(it.x, it.z, it.yaw, it.hx, it.hz)
			base = hi or groundY(it.x, it.z)
		end
	elseif it.padded then
		local y = groundAt(it.x, it.z)
		if y and math.abs(y - base) * M > PLAN_TOL_M then
			AssetLoader.planMismatch += 1
		end
	end
	m:PivotTo(CFrame.new(it.x - ox, base - bottom, it.z - oz) * CFrame.Angles(0, it.yaw, 0))
	if it.foliage then
		foliageParts(m, it.shadow == true)
	end
	if it.tint then
		tintModel(m, it.tint)
	end
	-- bases e casas únicas: placa certa, cancela no pino, fumaça da cozinha, escada da torre e do
	-- jirau, estacas punji (MapLife.baseInstance; cf = o meio da base da caixa, com o giro)
	local data = baseData()
	if data and data.nodes and data.nodes[it.key] then
		local cf = CFrame.new(it.x, base, it.z) * CFrame.Angles(0, it.yaw, 0)
		MapLife.baseInstance(m, it.key, cf, it.node, data.extras and data.extras[it.key])
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
	-- posta junto com a geração: o raio não achava chão e tudo ia para y = 0 (Studio, 2026-11-10).
	while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
		ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
	end
	local Build = require(ServerStorage:WaitForChild("VT65Build"):WaitForChild("Build")) :: any
	local world = Build.world()
	local ctx, structures = Build.plan(world)
	local planned = workspace.Terrain:GetAttribute("SitePlan") == ArtPlan.VERSION
	local paddies = if workspace.Terrain:GetAttribute("PaddiesFlat") == true then ctx.paddies else nil
	local fit = AssetLoader.fitFeatures(map, paddies)
	print(
		string.format(
			"[VT65] arrozal no terreno real: %d lâminas, %d sebes (plano do chão: %s)",
			fit.water,
			fit.hedges,
			if planned then "sim" else "não, terreno antigo"
		)
	)
	-- arrozal (D-74): dossel dos tabuleiros plantados e ladrilhos de arroz para o cliente
	print(string.format("[VT65] arrozal: %d tabuleiros com arroz", MapLife.rice(map, AssetLoader.template)))
	print(string.format("[VT65] animais em partes para o cliente: %d", MapLife.animalArt(AssetLoader.template)))
	-- lâminas d'água (studs): a manada usa para saber se o ponto é arrozal alagado
	local sheets: { { cf: CFrame, hx: number, hz: number } } = {}
	local waterFolder = map:FindFirstChild("PaddyWater")
	for _, p in if waterFolder then waterFolder:GetChildren() else {} do
		if p:IsA("BasePart") then
			table.insert(sheets, { cf = p.CFrame, hx = p.Size.X / 2, hz = p.Size.Z / 2 })
		end
	end
	local function inWater(x: number, z: number): boolean
		for _, s in sheets do
			local lp = s.cf:PointToObjectSpace(Vector3.new(x, s.cf.Y, z))
			if math.abs(lp.X) <= s.hx and math.abs(lp.Z) <= s.hz then
				return true
			end
		end
		return false
	end
	local out = Instance.new("Folder")
	out.Name = "Art"
	out.Parent = map
	local rng = Rng.new(19650818)
	local B = MapConfig.Bounds
	local function inBounds(x: number, z: number): boolean
		return x >= B.minX and x <= B.maxX and z >= B.minZ and z <= B.maxZ
	end

	-- ===== construções do plano: casas da carta e quintais, túneis, QGs, tocas, túmulos, ponte e a
	-- vila grande (casas, anexos, pagode, casa comunal, poço e bancas) =====
	local placeholders: { { model: Instance, x: number, z: number } } = {}
	local houses = map:FindFirstChild("Houses")
	for _, h in if houses then houses:GetChildren() else {} do
		local body = h:FindFirstChild("Walls")
		if body and body:IsA("BasePart") then
			table.insert(placeholders, { model = h, x = body.Position.X, z = body.Position.Z })
		end
	end
	local houseModels: { Model } = {}
	local housePos: { number } = {} -- metros, para os animais da vila
	local nModels, nParts = 0, 0
	for i, it in structures do
		if i % 100 == 0 then
			task.wait()
		end
		local m = AssetLoader.placeItem(it, out, planned)
		if m then
			if string.sub(it.key, 1, 6) == "parts:" then
				nParts += 1
			else
				nModels += 1
			end
			if it.home then
				table.insert(housePos, it.x * M)
				table.insert(housePos, it.z * M)
			end
			if it.group == "house" then
				table.insert(houseModels, m)
				-- o placeholder do greybox some quando a casa da carta tem modelo
				for _, ph in placeholders do
					if math.abs(ph.x - it.x) < 1 and math.abs(ph.z - it.z) < 1 then
						ph.model:Destroy()
					end
				end
			end
		end
	end
	print(string.format("[VT65] construções do plano: %d modelos, %d em peças", nModels, nParts))
	-- túneis por dentro (D-74): escoras, lamparinas e câmaras mobiliadas
	local tParts, tLamps = MapLife.tunnels(map, AssetLoader.placeAt)
	print(string.format("[VT65] túneis: %d peças de escora e mobília, %d lamparinas", tParts, tLamps))
	-- centro de cada vila no mapa: o ponto forte com o nome dela ou, sem ponto forte, o local da carta
	local function villageCenter(name: string): (number, number)
		for _, sp in MapConfig.Strongpoints do
			if sp.name == name then
				return sp.x, sp.z
			end
		end
		for _, l in MapConfig.Locations do
			if l.name == name then
				return l.x, l.z
			end
		end
		return 0, 0
	end
	-- animais da vila (Parte 11): o AnimalService os move
	if AssetLoader.template("water_buffalo") or AssetLoader.template("chicken") then
		local pen = Instance.new("Folder")
		pen.Name = "Animals"
		local function free(x: number, z: number): boolean
			return ArtPlan.groundProblem(ctx, x, z, 2 / M) == nil and not ArtPlan.inside(structures, x, z, 1 / M)
		end
		for _, sp in
			Animals.spawns(housePos, function()
				return rng:next()
			end)
		do
			local x, z = sp.x / M, sp.z / M
			if free(x, z) or inWater(x, z) then
				AssetLoader.place(sp.species, x, z, rng:range(0, 6.28), pen, true)
			end
		end
		-- manadas no arrozal alagado perto das vilas (D-74): 2 búfalos e 1 bezerro
		local herds = 0
		for _, l in MapConfig.Locations do
			if VILLAGES[l.name] then
				local vx, vz = villageCenter(l.name)
				local herd = Animals.herd(vx * M, vz * M, function()
					return rng:next()
				end, function(xm: number, zm: number): boolean
					return inBounds(xm / M, zm / M) and inWater(xm / M, zm / M)
				end)
				for _, b in herd do
					AssetLoader.place(b.species, b.x / M, b.z / M, rng:range(0, 6.28), pen, true, b.scale)
				end
				herds += if #herd > 0 then 1 else 0
			end
		end
		print(string.format("[VT65] animais postos: %d (%d manadas no arrozal)", #pen:GetChildren(), herds))
		pen.Parent = out
	end
	-- vida nas casas da carta (D-74): fumaça de cozinha, potes, medas, lenha, varal e chapéu. A vila
	-- grande já tem os anexos do plano. Só onde o chão aceita (fora da rua, do beco, da lâmina, do
	-- leito e das outras construções).
	local vida = MapLife.village(
		houseModels,
		out,
		rng,
		groundAt,
		inWater,
		AssetLoader.placeAt,
		function(x: number, z: number, r: number): boolean
			local p = ArtPlan.groundProblem(ctx, x, z, r)
			if p and p ~= "patamar" and p ~= "clareira" then
				return false
			end
			return not ArtPlan.inside(structures, x, z, r * 0.5)
		end
	)
	print(
		string.format(
			"[VT65] vilas: %d fumaças, %d potes, %d medas, %d lenhas, %d varais, %d chapéus (%d em modelo)",
			vida.smoke,
			vida.jars,
			vida.straw,
			vida.wood,
			vida.lines,
			vida.hats,
			vida.models
		)
	)

	-- ===== plantas do plano: quintais, Colina 30, bambuzal da vila, sebes, canteiros e a mata =====
	-- raias que a mata não fecha: a trincheira sul e o campo de tiro de cada QG
	local cx, cz = villageCenter("An Cường (2)")
	for _, l in MapConfig.Locations do
		if l.name == "An Cường (2)" then
			cx, cz = l.x, l.z -- a trincheira sai do local da carta (Tunnels.toWorld), não do ponto forte
		end
	end
	local corridors: { Vegetation.Segment } = {}
	for i = 1, #Tunnels.trench - 1 do
		local a, b = Tunnels.trench[i], Tunnels.trench[i + 1]
		local x1, z1 = Tunnels.toWorld(cx, cz, a[1], a[2])
		local x2, z2 = Tunnels.toWorld(cx, cz, b[1], b[2])
		table.insert(corridors, { x1 = x1, z1 = z1, x2 = x2, z2 = z2, w = 4 / M })
	end
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
	local plants = ArtPlan.plants(ctx, structures, corridors, Build.has, function()
		task.wait()
	end)
	-- a peça de cada sebe vira só o marcador (sem cor) quando as touceiras têm modelo
	local hedges = map:FindFirstChild("Hedges")
	if hedges and AssetLoader.template("bamboo_clump") and AssetLoader.template("shrub") then
		for _, hp in hedges:GetChildren() do
			if hp:IsA("BasePart") then
				hp.Transparency = 1
			end
		end
	end
	-- O que não cabe no teto de triângulos do setor (D-45) vira desbaste uniforme da mata no setor; o
	-- resto (quintais, sebes, bambuzal da vila, canteiros) entra antes.
	local jDemand: { [number]: number } = {}
	for _, it in plants do
		if it.group == "jungle" then
			local s = Geometry.sectorAt(MapConfig.Sectors, it.x, it.z) or 0
			jDemand[s] = (jDemand[s] or 0) + ArtBudget.tris(it.key)
		end
	end
	local nPlants = 0
	for i, it in plants do
		if i % 300 == 0 then
			task.wait()
		end
		if it.group ~= "jungle" and it.group ~= "border" and AssetLoader.placeItem(it, out, planned) then
			nPlants += 1
		end
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
	local nJungle, nBorder, skippedLane, nPlanned = 0, 0, 0, 0
	-- raio do tronco (peça Madeira0, com os galhos grossos) de cada árvore pronta, na escala 1
	local trunkR: { [string]: number } = {}
	local function laneClear(key: string, scale: number, x: number, z: number): boolean
		if string.sub(key, 1, 3) ~= "ph_" then
			return true
		end
		if trunkR[key] == nil then
			-- o centro do tronco fica fora do pé (tronco inclinado, galhos abertos): conta o
			-- deslocamento horizontal até o pivô e a meia largura
			local tpl = AssetLoader.template(key)
			local trunk = tpl and tpl:FindFirstChild("Madeira0_0", true) :: BasePart?
			if tpl and trunk then
				local off = trunk.Position - tpl:GetPivot().Position
				trunkR[key] = Vector3.new(off.X, 0, off.Z).Magnitude + math.max(trunk.Size.X, trunk.Size.Z) / 2
			else
				trunkR[key] = 0
			end
		end
		local r = trunkR[key] * scale + 2 / M
		for _, sgm in corridors do
			local dx, dz = sgm.x2 - sgm.x1, sgm.z2 - sgm.z1
			local L2 = dx * dx + dz * dz
			local t = if L2 > 0 then math.clamp(((x - sgm.x1) * dx + (z - sgm.z1) * dz) / L2, 0, 1) else 0
			local qx, qz = sgm.x1 + t * dx - x, sgm.z1 + t * dz - z
			if qx * qx + qz * qz < (sgm.w + r) ^ 2 then
				return false
			end
		end
		return true
	end
	for i, it in plants do
		if i % 200 == 0 then
			task.wait() -- não trava o servidor enquanto planta milhares de modelos
		end
		if it.group == "jungle" or it.group == "border" then
			local s = Geometry.sectorAt(MapConfig.Sectors, it.x, it.z) or 0
			nPlanned += 1
			if it.group == "border" or jrng:next() < (jFactor[s] or 1) then
				if not laneClear(it.key, it.scale, it.x, it.z) then
					skippedLane += 1
				else
					local pm = AssetLoader.placeItem(it, jungle, planned)
					if pm then
						nJungle += 1
						if it.group == "border" then
							-- cortina de fora da área: só moldura. Ninguém chega nela (morre fora da área
							-- em 10 s), então sem colisão, sem consulta de raio e sem sombra
							nBorder += 1
							for _, d in pm:GetDescendants() do
								if d:IsA("BasePart") then
									d.CanCollide = false
									d.CanQuery = false
									d.CastShadow = false
								end
							end
						end
					end
				end
			end
		end
	end
	print(
		string.format(
			"[VT65] plantas: %d de quintal, sebe e vila; mata %d de %d no plano (%d na cortina de fora, %d tiradas da raia)",
			nPlants,
			nJungle,
			nPlanned,
			nBorder,
			skippedLane
		)
	)
	-- streaming (D-15): cada modelo chega inteiro
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
	if AssetLoader.planMismatch > 0 then
		warn(
			string.format(
				"[VT65] %d construções com o chão real a mais de %.1f m do patamar do plano",
				AssetLoader.planMismatch,
				PLAN_TOL_M
			)
		)
	end
	out:SetAttribute("Placed", true) -- o autoteste confere a arte no chão depois disto
	-- Studio: workspace:SetAttribute("VT65DevFlutua", true) mede o que flutua no mapa (Flutua.luau)
	require(script.Parent.Flutua).hook()
end

-- Arma visível na mão direita (todos veem). Sem asset publicado, usa a provisória (Shared/GunModel):
-- antes ninguém aparecia armado. Troca a anterior (arma do inimigo pega do chão).
-- Skin (Shared/Skins): o atributo "WeaponSkins" do dono (ProgressionService.applySkins) diz o
-- acabamento desta arma; o modelo ganha os atributos "WeaponId" e "Skin". Bot e manequim: de fábrica.
function AssetLoader.attachWeapon(model: Model, weaponId: string)
	local Skins = require(ReplicatedStorage.Shared.Skins)
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
	local owner = game:GetService("Players"):GetPlayerFromCharacter(model)
	w:SetAttribute("WeaponId", weaponId)
	Skins.applyWeapon(w, if owner then Skins.weaponSkinFrom(owner:GetAttribute("WeaponSkins"), weaponId) else nil)
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
