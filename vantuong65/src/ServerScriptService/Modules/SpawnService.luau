--!strict
-- Spawn escolhido no mapa, só no próprio lado, com espera longa por ondas (Parte 10.1).
-- D-72: equipamento liberado aplicado ao nascer (ProgressionService.applyGear) e o "renascer onde
-- caiu" (ponto "inplace" na carta, só para quem caiu): pago com um renascer guardado (Robux), com
-- créditos de intendência ou abrindo a compra em Robux. Regras em Shared/Progression.INPLACE.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Roles = require(ReplicatedStorage.Shared.Roles)
local SpawnRules = require(ReplicatedStorage.Shared.SpawnRules)
local AssetLoader = require(script.Parent.AssetLoader)
local Characters = require(script.Parent.Characters)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressionService = require(script.Parent.ProgressionService)
local TeamService = require(script.Parent.TeamService)
local TunnelService = require(script.Parent.TunnelService)

local SpawnService = {}
local M = MapConfig.STUD_M

type Info = {
	deaths: { number },
	lastDeath: number?,
	roleChanged: boolean,
	firstSpawn: boolean,
	deathPos: Vector3?, -- onde caiu (studs); nil depois de renascer, se evacuado ou sem lado
	inplaceUses: number, -- renasceres no lugar nesta partida
	matchStart: number, -- MatchService.startedAt quando os usos foram contados
	buyAt: number?, -- pediu a compra em Robux do renascer no lugar (os.clock)
}
local info: { [Player]: Info } = {}

local function newInfo(): Info
	return { deaths = {}, roleChanged = false, firstSpawn = true, inplaceUses = 0, matchStart = 0 }
end

-- squad: ponto de reunião do squad (FrontService); só os membros desse squad veem e nascem nele
export type Point = {
	id: string,
	name: string,
	x: number,
	z: number,
	kind: SpawnRules.Kind,
	sector: number?,
	squad: string?,
}

-- o ponto vale para este jogador? (ponto de squad só para o próprio squad)
local function visibleTo(pt: Point, player: Player): boolean
	return pt.squad == nil or pt.squad == player:GetAttribute("SquadId")
end

-- Provedores extras de pontos (postos construídos, reforço por túnel): LogisticsService etc.
local providers: { (faction: string) -> { Point } } = {}
function SpawnService.addProvider(fn: (faction: string) -> { Point })
	table.insert(providers, fn)
end

function SpawnService.points(faction: string): { Point }
	local out: { Point } = {}
	for _, fn in providers do
		for _, pt in fn(faction) do
			table.insert(out, pt)
		end
	end
	local hq = MapConfig.HQ[faction]
	table.insert(out, { id = "hq", name = "QG", x = hq.x, z = hq.z, kind = "hq" })
	for s, sp in MatchService.points do
		if MatchService.ownerOf(s) == faction then
			local x, z = SpawnRules.rallyPosition(sp.x, sp.z, faction, M)
			local initial = MatchService.initialOwner[s] == faction
			table.insert(out, {
				id = "rally:" .. s,
				name = string.format("Reunião — %s", sp.name),
				x = x,
				z = z,
				kind = if initial then "rally" else "rally_captured",
				sector = s,
			})
		end
	end
	if faction == "VC" then
		for _, en in TunnelService.entrances() do
			if en.sector and MatchService.ownerOf(en.sector) == "VC" and not TunnelService.destroyed[en.id] then
				table.insert(out, {
					id = "tunnel:" .. en.id,
					name = string.format("Túnel %s", en.id),
					x = en.x,
					z = en.z,
					kind = "garrison",
					sector = en.sector,
				})
			end
		end
	end
	return out
end

function SpawnService.enemiesMeters(faction: string): { number }
	local list = {}
	for _, e in Combatants.list() do
		local r = Combatants.root(e)
		if e.faction ~= faction and r and Combatants.active(e) then
			table.insert(list, r.Position.X * M)
			table.insert(list, r.Position.Z * M)
		end
	end
	return list
end
local enemiesMeters = SpawnService.enemiesMeters

local function status(player: Player, pt: Point, now: number): (number, boolean, string?)
	local inf = info[player]
	local faction = player:GetAttribute("Faction") :: string
	local ready = now
	if inf and inf.lastDeath and not inf.firstSpawn then
		local extra = SpawnRules.extraWait(pt.kind, inf.deaths, inf.roleChanged)
		ready = SpawnRules.readyAt(inf.lastDeath, extra, MatchService.waveEpoch)
	end
	local contested = pt.sector ~= nil and MatchService.isContested(pt.sector)
	local openedAt = if pt.sector then MatchService.capturedAt[pt.sector] else nil
	local blocked, why = false, nil
	if pt.kind ~= "hq" then
		blocked, why = SpawnRules.blocked(pt.x * M, pt.z * M, enemiesMeters(faction), contested, openedAt, now)
	end
	return math.max(0, ready - now), blocked, why
end

function SpawnService.groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return if hit then hit.Position.Y else 10
end
local groundY = SpawnService.groundY

-- pontos livres agora (para bots): sem bloqueio
function SpawnService.freePoints(faction: string): { Point }
	local out = {}
	local now = os.clock()
	for _, pt in SpawnService.points(faction) do
		local contested = pt.sector ~= nil and MatchService.isContested(pt.sector)
		local openedAt = if pt.sector then MatchService.capturedAt[pt.sector] else nil
		local blocked = pt.kind ~= "hq"
			and SpawnRules.blocked(pt.x * M, pt.z * M, enemiesMeters(faction), contested, openedAt, now)
		if not blocked and pt.squad == nil then -- bot não tem squad
			table.insert(out, pt)
		end
	end
	return out
end

local function alive(player: Player): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- Põe o personagem no chão em (x, z), com uniforme, equipamento e arma. Registra a morte.
local function spawnAt(player: Player, faction: string, x: number, z: number)
	local inf = info[player]
	inf.firstSpawn, inf.roleChanged = false, false
	inf.deathPos = nil
	ProgressionService.applyGear(player) -- antes do personagem: o kit lê os atributos ao nascer
	local prof = PlayerData.get(player)
	local equipped = if prof then prof.equipped[faction] else nil
	player:LoadCharacterWithHumanoidDescriptionAsync(Characters.describe(faction, equipped, player.UserId))
	local char = player.Character
	if not char then
		return
	end
	local y = groundY(x, z)
	char:PivotTo(CFrame.new(x, y + 5, z))
	Combatants.register(char, faction, player)
	Characters.dress(char, faction, equipped)
	local lo = player:GetAttribute("Loadout")
	if type(lo) == "string" then
		AssetLoader.attachWeapon(char, string.split(lo, ",")[1])
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			local t = os.clock()
			inf.lastDeath = t
			table.insert(inf.deaths, t)
			if #inf.deaths > 10 then
				table.remove(inf.deaths, 1)
			end
			-- ponto de queda para o renascer onde caiu (evacuado pelo medevac não conta)
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			inf.deathPos = if root and char:GetAttribute("Evacuated") ~= true then root.Position else nil
		end)
	end
end

-- ===== renascer onde caiu (D-72) =====
local function inWater(pos: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = false
	local hit = workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return hit ~= nil and hit.Material == Enum.Material.Water
end

-- Contexto das regras (Progression.inPlaceCheck) e o motivo do bloqueio (nil = permitido) e a espera.
local function inPlaceStatus(player: Player, now: number): (string?, number, Vector3?)
	local inf = info[player]
	local faction = player:GetAttribute("Faction") :: string?
	if not inf or not faction then
		return "sem lado", 0, nil
	end
	if inf.matchStart ~= MatchService.startedAt then
		inf.matchStart = MatchService.startedAt
		inf.inplaceUses = 0
	end
	local pos = inf.deathPos
	local enemy = if faction == "US" then "VC" else "US"
	local hq = MapConfig.HQ[enemy]
	local b = MapConfig.Bounds
	local x, z = if pos then pos.X else 0, if pos then pos.Z else 0
	local sector = if pos then Geometry.sectorAt(MapConfig.Sectors, x, z) else nil
	local st = MatchService.state :: any
	local owner = if sector then MatchService.ownerOf(sector) else nil
	local locked = sector ~= nil and owner == enemy and st ~= nil and st.active ~= nil and st.active[sector] == false
	local extra = SpawnRules.extraWait("rally", inf.deaths, inf.roleChanged)
	local readyAt = if inf.lastDeath then SpawnRules.readyAt(inf.lastDeath, extra, MatchService.waveEpoch) else now
	local role = tostring(player:GetAttribute("Role") or "")
	local why, wait = Progression.inPlaceCheck({
		matchOver = MatchService.ended,
		hasDeath = pos ~= nil and not inf.firstSpawn,
		uses = inf.inplaceUses,
		roleLocked = ProgressionService.rank(player) < Roles.minRank(role),
		now = now,
		deathT = inf.lastDeath or now,
		regularReadyAt = readyAt,
		inBounds = pos ~= nil and x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ,
		inWater = pos ~= nil and inWater(pos),
		enemyHqM = if pos then Vector3.new(x - hq.x, 0, z - hq.z).Magnitude * M else 0,
		sectorLocked = locked,
		contested = sector ~= nil and MatchService.isContested(sector),
		x = x * M,
		z = z * M,
		enemies = SpawnService.enemiesMeters(faction),
	})
	return why, wait, pos
end

local function productOn(): boolean
	return Commerce.IDS.PRODUCT_RESPAWN_INPLACE ~= 0
end

-- rótulo do pagamento no ponto da carta
local function payLabel(player: Player): (string?, string)
	local inf = info[player]
	local prof = PlayerData.get(player)
	local credits = if prof then prof.credits else 0
	local rc = if prof then prof.respawnCredits else 0
	local m = Progression.inPlaceAuto(inf.inplaceUses, credits, rc, productOn())
	if m == "credit" then
		return m, "renascer guardado"
	elseif m == "ci" then
		return m, string.format("%d %s", Progression.inPlacePrice(inf.inplaceUses) or 0, Progression.CUR)
	elseif m == "robux" then
		return m, "Robux"
	end
	local price = Progression.inPlacePrice(inf.inplaceUses)
	if not price then
		return nil, "limite da partida"
	end
	return nil, string.format("%d %s: faltam %d", price, Progression.CUR, math.max(price - credits, 0))
end

-- Tenta o renascer onde caiu. method: "credit" | "ci" | "robux" | nil (automático).
local function inPlace(player: Player, method: string?)
	local faction = player:GetAttribute("Faction") :: string?
	local inf = info[player]
	if not faction or not inf or alive(player) then
		return
	end
	local now = os.clock()
	local why, wait, pos = inPlaceStatus(player, now)
	if why or wait > 0 or not pos then
		return
	end
	local prof = PlayerData.get(player)
	local credits = if prof then prof.credits else 0
	local rc = if prof then prof.respawnCredits else 0
	local m = method
	if m ~= "credit" and m ~= "ci" and m ~= "robux" then
		m = Progression.inPlaceAuto(inf.inplaceUses, credits, rc, productOn())
	end
	if not m then
		return
	end
	local ok, _, price = Progression.inPlacePay(m, inf.inplaceUses, credits, rc, productOn())
	if not ok then
		return
	end
	if m == "robux" then
		-- abre a compra; o recibo vira um renascer guardado e volta aqui (onRespawnCredit)
		inf.buyAt = now
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, Commerce.IDS.PRODUCT_RESPAWN_INPLACE)
		end)
		return
	end
	local paid = if m == "credit"
		then ProgressionService.useRespawnCredit(player)
		else ProgressionService.spendCredits(player, price or math.huge)
	if not paid then
		return
	end
	inf.inplaceUses += 1
	spawnAt(player, faction, pos.X, pos.Z)
end

function SpawnService.start()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(function(p)
		info[p] = newInfo()
	end)
	for _, p in Players:GetPlayers() do
		info[p] = newInfo()
	end
	-- recibo do renascer em Robux chegou: se o pedido é recente e ainda vale, renasce agora
	ProgressionService.onRespawnCredit = function(p: Player)
		local inf = info[p]
		if inf and inf.buyAt and os.clock() - inf.buyAt <= Progression.INPLACE.buyTimeoutS then
			inf.buyAt = nil
			inPlace(p, "credit")
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		info[p] = nil
	end)
	TeamService.RoleChanged:Connect(function(player: Player)
		local inf = info[player]
		if inf and inf.lastDeath then
			inf.roleChanged = true
		end
	end)

	Net.event("Spawn_Request").OnServerEvent:Connect(function(player, pointId, method)
		local faction = player:GetAttribute("Faction") :: string?
		if type(pointId) ~= "string" or not faction or not player:GetAttribute("Role") or alive(player) then
			return
		end
		if ReplicatedStorage:GetAttribute("TerrainReady") == false then
			return -- terreno ainda sendo gerado
		end
		local role = tostring(player:GetAttribute("Role"))
		if ProgressionService.rank(player) < Roles.minRank(role) then
			return -- papel acima do posto (o lobby mostra o cadeado)
		end
		if pointId == "inplace" then
			inPlace(player, if type(method) == "string" then method else nil)
			return
		end
		local now = os.clock()
		for _, pt in SpawnService.points(faction) do
			if pt.id == pointId and visibleTo(pt, player) then
				local wait, blocked = status(player, pt, now)
				if wait > 0 or blocked then
					return
				end
				spawnAt(player, faction, pt.x, pt.z)
				return
			end
		end
	end)

	-- estado dos pontos para quem está esperando (uma vez por segundo)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local faction = player:GetAttribute("Faction") :: string?
				if faction and not alive(player) then
					local list: { any } = {}
					for _, pt in SpawnService.points(faction) do
						if not visibleTo(pt, player) then
							continue
						end
						local wait, blocked, why = status(player, pt, now)
						local entry = {
							id = pt.id,
							name = pt.name,
							x = pt.x,
							z = pt.z,
							wait = wait,
							blocked = blocked,
							why = why,
							kind = pt.kind, -- símbolo na carta (QG, reunião, posto, squad)
							squad = pt.squad ~= nil,
						}
						table.insert(list, entry)
					end
					-- renascer onde caiu: só para quem tem ponto de queda nesta partida
					local inf = info[player]
					if inf and inf.deathPos then
						local why, wait, pos = inPlaceStatus(player, now)
						local m, label = payLabel(player)
						if pos then
							table.insert(list, {
								id = "inplace",
								name = string.format("Onde caiu (%s)", label),
								x = pos.X,
								z = pos.Z,
								wait = wait,
								blocked = why ~= nil or m == nil,
								why = why or (if m == nil then label else nil),
								pay = m,
							})
						end
					end
					Net.event("Spawn_State"):FireClient(player, list)
				end
			end
		end
	end)
end

return SpawnService
