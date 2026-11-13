--!strict
-- Spawn escolhido no mapa, só no próprio lado, com espera longa por ondas (Parte 10.1).
-- D-72: equipamento liberado aplicado ao nascer (ProgressionService.applyGear) e o "renascer onde
-- caiu" (ponto "inplace" na carta, só para quem caiu): pago com um renascer guardado (Robux), com
-- créditos de intendência ou abrindo a compra em Robux. Regras em Shared/Progression.INPLACE.
-- 2026-11-12 (pedido do dono: "permita poder nascer com o batalhão"): um ponto por companheiro do
-- squad em campo (kind "squad", id "mate:<UserId>"), com as regras de SpawnRules.mateCheck e o lugar
-- livre de SpawnRules.mateSpots conferido com raios (mateSpot).
-- 2026-11-13 (pedido do dono: "Botão 'jogar agora'"): Spawn_Request("quick", { n, v }) põe o
-- jogador num lado, squad e papel (TeamService.quickJoin) e responde no atributo "JogarAgora" o
-- ponto escolhido (Shared/JogarAgora.pickPoint: o último usado ou o melhor); o cliente conta a espera
-- e pede o ponto como sempre. Todo nascer num ponto grava o "UltimoPonto" (atributo e perfil).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local CompraVeiculo = require(ReplicatedStorage.Shared.CompraVeiculo)
local Front = require(ReplicatedStorage.Shared.Front)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local JogarAgora = require(ReplicatedStorage.Shared.JogarAgora)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Roles = require(ReplicatedStorage.Shared.Roles)
local SpawnRules = require(ReplicatedStorage.Shared.SpawnRules)
local AssetLoader = require(script.Parent.AssetLoader)
local Characters = require(script.Parent.Characters)
local CombatService = require(script.Parent.CombatService)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local MedicalService = require(script.Parent.MedicalService)
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
	busy: boolean, -- nascendo agora (carregando o corpo ou o mapa em volta): pedido repetido é ignorado
}
local info: { [Player]: Info } = {}

local function newInfo(): Info
	return { deaths = {}, roleChanged = false, firstSpawn = true, inplaceUses = 0, matchStart = 0, busy = false }
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
	blockM: number?, -- raio próprio de bloqueio por inimigo (túnel avançado do VC); sem setor em disputa
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

-- Bloqueios temporários de área (EventosService: barragem avisada). fn(x, z, lado) em studs devolve o
-- motivo ou nil. Vale para todo ponto menos o QG, para o companheiro do squad e para o "onde caiu":
-- ninguém nasce dentro de uma barragem que já foi avisada.
local blockers: { (x: number, z: number, faction: string) -> string? } = {}
function SpawnService.addBlocker(fn: (x: number, z: number, faction: string) -> string?)
	table.insert(blockers, fn)
end
local function blockedBy(x: number, z: number, faction: string): string?
	for _, fn in blockers do
		local why = fn(x, z, faction)
		if why then
			return why
		end
	end
	return nil
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
			-- mapa de 1 x 1 km: 100 m atrás de um ponto forte perto da borda (o Cemitério fica a 85 m
			-- da borda oeste) caía fora da área e o soldado nascia contando os 10 s para morrer. A mata
			-- abre a clareira no mesmo lugar (Front.spawnSpots, AssetLoader).
			x, z = Front.clampInside(MapConfig.Bounds, x, z, Front.C.rallyInsetM / M)
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
		-- 2026-11-12: túnel avançado, reunião permanente do VC na boca mais perto do objetivo dele
		-- (SpawnRules.vcForward): sem o extra de guarnição, bloqueado só com inimigo a VC_FORWARD.blockM
		local st = MatchService.state
		local goal: number? = nil
		if st then
			local _, s = Front.objective(st.owner, st.active, "VC")
			goal = s
		end
		local gsp = if goal then MatchService.points[goal] else nil
		if st and gsp then
			local mouths: { SpawnRules.TunnelMouth } = {}
			for _, en in TunnelService.entrances() do
				table.insert(
					mouths,
					{ id = en.id, x = en.x, z = en.z, sector = en.sector, open = not TunnelService.destroyed[en.id] }
				)
			end
			local us, vc = MapConfig.HQ.US, MapConfig.HQ.VC
			local m, fx, fz = SpawnRules.vcForward(mouths, st.owner, gsp.x, gsp.z, us.x, us.z, vc.x, vc.z, M)
			if m and fx and fz then
				table.insert(out, {
					id = "vcfront:" .. m.id,
					name = string.format("Túnel avançado %s", m.id),
					x = fx,
					z = fz,
					kind = "rally",
					blockM = SpawnRules.VC_FORWARD.blockM,
				})
			end
		end
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

-- segundos até poder nascer num ponto deste tipo (0 = já pode)
local function waitFor(player: Player, kind: SpawnRules.Kind, now: number): number
	local inf = info[player]
	local ready = now
	if inf and inf.lastDeath and not inf.firstSpawn then
		local extra = SpawnRules.extraWait(kind, inf.deaths, inf.roleChanged)
		ready = SpawnRules.readyAt(inf.lastDeath, extra, MatchService.waveEpoch)
	end
	return math.max(0, ready - now)
end

-- enemies: a lista do lado (enemiesMeters), quando o chamador já a tem
local function status(player: Player, pt: Point, now: number, enemies: { number }?): (number, boolean, string?)
	local faction = player:GetAttribute("Faction") :: string
	local contested = pt.sector ~= nil and MatchService.isContested(pt.sector)
	local openedAt = if pt.sector then MatchService.capturedAt[pt.sector] else nil
	local blocked, why = false, nil
	if pt.kind ~= "hq" then
		blocked, why = SpawnRules.blocked(
			pt.x * M,
			pt.z * M,
			enemies or enemiesMeters(faction),
			contested,
			openedAt,
			now,
			pt.blockM
		)
		if not blocked then
			why = blockedBy(pt.x, pt.z, faction)
			blocked = why ~= nil
		end
	end
	return waitFor(player, pt.kind, now), blocked, why
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
			and (
				SpawnRules.blocked(pt.x * M, pt.z * M, enemiesMeters(faction), contested, openedAt, now, pt.blockM)
				or blockedBy(pt.x, pt.z, faction) ~= nil
			)
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
-- at: lugar e rumo exatos (nascer no companheiro); sem ele, o chão do terreno em (x, z).
local function placeBody(player: Player, faction: string, x: number, z: number, at: CFrame?)
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
	if at then
		char:PivotTo(at)
	else
		char:PivotTo(CFrame.new(x, groundY(x, z) + 5, z))
	end
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

-- Nascer no QG (2026-11-13): num dos pontos de nascer da base (layout do Blender, Data/Bases), em
-- rodízio, fora das barracas e da rua. Sem os dados, o meio do QG, como antes.
local hqTurn: { [string]: number } = {}
local baseSpawns: any = nil
function SpawnService.hqSpot(faction: string, x: number, z: number): (number, number)
	if baseSpawns == nil then
		local data = game:GetService("ServerStorage"):FindFirstChild("VT65Build")
		local mod = data and data:FindFirstChild("Data") and data.Data:FindFirstChild("Bases")
		baseSpawns = if mod then (require :: any)(mod) else false
	end
	local base = baseSpawns and baseSpawns[faction]
	local s = base and base.spawns
	local hq = MapConfig.HQ[faction]
	if not (s and hq and #s >= 2) then
		return x, z
	end
	hqTurn[faction] = (hqTurn[faction] or 0) % (#s // 2) + 1
	local i = hqTurn[faction] * 2 - 1
	return hq.x + s[i], hq.z + s[i + 1]
end

-- Um nascer por vez: carregar o corpo cede a vez, e um segundo Spawn_Request chegava antes do fim.
-- pointId: o ponto escolhido (vira o "último ponto" do jogar agora); nil no renascer onde caiu.
local function spawnAt(player: Player, faction: string, x: number, z: number, at: CFrame?, pointId: string?)
	local inf = info[player]
	if not inf or inf.busy then
		return
	end
	inf.busy = true
	local ok, err = pcall(function(): any
		placeBody(player, faction, x, z, at)
		return nil
	end)
	inf.busy = false
	if not ok then
		warn("[VT65] nascer falhou:", err)
	elseif pointId and alive(player) then
		player:SetAttribute("UltimoPonto", pointId)
		TeamService.remember(player)
	end
end

-- ===== nascer no companheiro do squad =====
-- Último tiro dado ou dano levado por modelo (jogador ou bot), para a regra "não está em combate".
-- Os ganchos envolvem CombatService.fire (todo tiro validado: jogador, bot, assento de veículo) e
-- MedicalService.hit (todo dano: tiro, estilhaço, faca, armadilha), chamadas pela tabela, como a
-- supressão do BotService já faz. Só anotam a hora; o tiro e o dano seguem iguais.
local lastCombat: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local function markCombat(m: Instance?)
	if m and m:IsA("Model") then
		lastCombat[m] = os.clock()
	end
end

local function hookCombat()
	local fire0 = CombatService.fire
	CombatService.fire = function(
		shooter: Model,
		weaponId: string,
		origin: Vector3,
		dir: Vector3,
		seed: number,
		exceptPlayer: Player?
	)
		fire0(shooter, weaponId, origin, dir, seed, exceptPlayer)
		markCombat(shooter)
	end
	local hit0 = MedicalService.hit
	MedicalService.hit = function(victim: Model, zone: string, energyJ: number, roll: number, by: Player?)
		hit0(victim, zone, energyJ, roll, by)
		markCombat(victim)
		if by then
			markCombat(by.Character)
		end
	end
end

-- Companheiro em campo. Bots valem se o BotService os puser no squad do jogador com o atributo
-- "SquadId" no modelo (hoje os bots têm squads próprios; o gancho VT65DevSquadBots faz isso no Studio).
type Mate = { id: string, name: string, userId: number, bot: boolean, model: Model }
local botIds: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local nextBotId = 0
local noRoom: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function squadMates(player: Player): { Mate }
	local out: { Mate } = {}
	local sid = player:GetAttribute("SquadId")
	local faction = player:GetAttribute("Faction")
	if type(sid) ~= "string" then
		return out
	end
	for _, e in Combatants.list() do
		local hum = Combatants.humanoid(e)
		if e.faction ~= faction or e.player == player or not hum or hum.Health <= 0 then
			continue
		end
		local p = e.player
		if p then
			if p:GetAttribute("SquadId") == sid and p.Character == e.model then
				table.insert(out, {
					id = "mate:" .. p.UserId,
					name = p.DisplayName,
					userId = p.UserId,
					bot = false,
					model = e.model,
				})
			end
		elseif e.model:GetAttribute("SquadId") == sid then
			local n = botIds[e.model]
			if not n then
				nextBotId += 1
				n = nextBotId
				botIds[e.model] = n
			end
			local bn = e.model:GetAttribute("BotName")
			table.insert(out, {
				id = "mate:bot:" .. n,
				name = if type(bn) == "string" then bn else e.model.Name,
				userId = 0,
				bot = true,
				model = e.model,
			})
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- terreno bem acima da raiz: está numa galeria do túnel (a mesma ideia do TunnelService)
local function underground(pos: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(pos + Vector3.new(0, 150, 0), Vector3.new(0, -150, 0), params)
	return hit ~= nil and (hit.Position.Y - pos.Y) * M > SpawnRules.MATE.tunnelRoofM
end

local function nearestEnemy(pos: Vector3, enemies: { number }): (number, number?, number?)
	local mx, mz = pos.X * M, pos.Z * M
	local best, ex, ez = math.huge, nil :: number?, nil :: number?
	for i = 1, #enemies, 2 do
		local d = (enemies[i] - mx) ^ 2 + (enemies[i + 1] - mz) ^ 2
		if d < best then
			best, ex, ez = d, enemies[i] / M, enemies[i + 1] / M
		end
	end
	return math.sqrt(best), ex, ez
end

-- motivo de não poder nascer nele agora (nil = pode)
local function mateWhy(m: Mate, enemies: { number }, now: number): string?
	local model = m.model
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local living = hum ~= nil and root ~= nil and hum.Health > 0 and model.Parent ~= nil
	local pos = if root then root.Position else Vector3.zero
	local pts = {}
	local st = MatchService.state
	for s, sp in MatchService.points do
		if st and st.active[s] then
			table.insert(pts, { x = sp.x, z = sp.z, contested = MatchService.isContested(s) })
		end
	end
	local last = lastCombat[model]
	local why = SpawnRules.mateCheck({
		alive = living,
		downed = model:GetAttribute("Downed") == true,
		inBounds = Geometry.inBounds(MapConfig.Bounds, pos.X, pos.Z),
		inVehicle = hum ~= nil and (hum.SeatPart ~= nil or hum.Sit),
		inTunnel = living and (model:GetAttribute("InTunnel") ~= nil or underground(pos)),
		nearestEnemyM = (nearestEnemy(pos, enemies)),
		sinceCombatS = if last then now - last else math.huge,
		inContestedCapture = SpawnRules.inContestedCapture(pos.X, pos.Z, pts, MapConfig.CaptureRadiusStuds),
	})
	if not why and noRoom[model] and now - noRoom[model] < SpawnRules.MATE.noRoomS then
		return "sem lugar livre perto dele"
	end
	if not why and living then
		local f = model:GetAttribute("Faction")
		why = blockedBy(pos.X, pos.Z, if type(f) == "string" then f else "")
	end
	return why
end

-- Lugar livre a 2–4 m dele, atrás em relação ao inimigo mais próximo (sem inimigo: nas costas dele).
-- Cada candidato (SpawnRules.mateSpots, na ordem) precisa de: chão a até 1,5 m da altura do pé dele
-- (sem telhado nem barranco), linha livre do peito dele ao peito do novo (nada de parede, sebe ou
-- tronco no meio), água rasa e uma caixa de 0,8 x 1,8 x 0,8 m vazia para o corpo. Rumo: o dele.
local function mateSpot(m: Mate, enemies: { number }): CFrame?
	local C = SpawnRules.MATE
	local model = m.model
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then
		return nil
	end
	local pos = root.Position
	local _, ex, ez = nearestEnemy(pos, enemies)
	local look = root.CFrame.LookVector
	local bx, bz = SpawnRules.behind(pos.X, pos.Z, ex, ez, look.X, look.Z)
	local footY = pos.Y - hum.HipHeight - root.Size.Y / 2
	local skip: { Instance } = {}
	for _, e in Combatants.list() do
		table.insert(skip, e.model)
	end
	for _, name in { "SquadRallies", "DroppedWeapons" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(skip, f)
		end
	end
	local solid = RaycastParams.new()
	solid.FilterType = Enum.RaycastFilterType.Exclude
	solid.FilterDescendantsInstances = skip
	solid.RespectCanCollide = true -- folha e capim sem colisão não contam
	solid.IgnoreWater = true
	local water = RaycastParams.new()
	water.FilterType = Enum.RaycastFilterType.Include
	water.FilterDescendantsInstances = { workspace.Terrain }
	water.IgnoreWater = false
	local body = OverlapParams.new()
	body.FilterType = Enum.RaycastFilterType.Exclude
	local skipBody = table.clone(skip)
	table.insert(skipBody, workspace.Terrain) -- a encosta pode raspar a caixa; o chão já foi medido
	body.FilterDescendantsInstances = skipBody
	body.RespectCanCollide = true
	local chest = pos + Vector3.new(0, 0.3 / M, 0)
	local size = Vector3.new(0.8, 1.8, 0.8) / M
	local top = footY + (C.floorM + 0.5) / M
	local drop = Vector3.new(0, -(2 * C.floorM + 0.5) / M, 0)
	for _, c in SpawnRules.mateSpots(pos.X, pos.Z, bx, bz, M) do
		local down = workspace:Raycast(Vector3.new(c.x, top, c.z), drop, solid)
		if not down or math.abs(down.Position.Y - footY) * M > C.floorM then
			continue
		end
		local floorY = down.Position.Y
		local head = Vector3.new(c.x, floorY + 1.2 / M, c.z)
		if workspace:Raycast(chest, head - chest, solid) then
			continue
		end
		local w = workspace:Raycast(Vector3.new(c.x, top, c.z), drop, water)
		if w and w.Material == Enum.Material.Water and (w.Position.Y - floorY) * M > C.deepWaterM then
			continue
		end
		if #workspace:GetPartBoundsInBox(CFrame.new(c.x, floorY + 1.0 / M, c.z), size, body) > 0 then
			continue
		end
		local at = Vector3.new(c.x, floorY + 4, c.z)
		return CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z))
	end
	return nil
end

local function mateSpawn(player: Player, faction: string, pointId: string)
	local inf = info[player]
	if not inf or inf.busy then
		return
	end
	local now = os.clock()
	local enemies = enemiesMeters(faction)
	for _, m in squadMates(player) do
		if m.id == pointId then
			if waitFor(player, "squad", now) > 0 or mateWhy(m, enemies, now) then
				return
			end
			local at = mateSpot(m, enemies)
			if not at then
				noRoom[m.model] = now
				return
			end
			-- o cliente recebe o chão em volta antes do corpo (streaming: o lugar pode estar longe)
			inf.busy = true
			pcall(function()
				player:RequestStreamAroundAsync(at.Position, 2)
			end)
			inf.busy = false
			-- até 2 s se passaram: ele pode ter caído ou entrado em combate
			if info[player] ~= inf or alive(player) or mateWhy(m, enemiesMeters(faction), os.clock()) then
				return
			end
			spawnAt(player, faction, at.X, at.Z, at, pointId)
			return
		end
	end
end

-- pontos dos companheiros para a carta de inserção (mesmo formato dos outros pontos)
local function mateEntries(player: Player, now: number, enemies: { number }): { any }
	local out = {}
	local wait = waitFor(player, "squad", now)
	for _, m in squadMates(player) do
		local root = m.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local why = mateWhy(m, enemies, now)
			table.insert(out, {
				id = m.id,
				name = m.name,
				kind = "squad",
				userId = m.userId,
				bot = m.bot,
				x = math.floor(root.Position.X),
				z = math.floor(root.Position.Z),
				wait = wait,
				blocked = why ~= nil,
				why = why,
				ready = wait <= 0 and why == nil,
				squad = true,
			})
		end
	end
	return out
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
	if not why and pos then
		why = blockedBy(pos.X, pos.Z, faction)
	end
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

-- Pontos de quem espera, como vão no Spawn_State. Campos de cada ponto: id, name, kind, x, z
-- (studs), wait (s), blocked, why, ready (= wait 0 e livre), squad; os de companheiro (kind "squad")
-- trazem também userId (0 se bot) e bot; o "onde caiu" traz pay.
local function stateFor(player: Player, faction: string, now: number, enemies: { number }): { any }
	local list: { any } = {}
	for _, pt in SpawnService.points(faction) do
		if not visibleTo(pt, player) then
			continue
		end
		local wait, blocked, why = status(player, pt, now, enemies)
		table.insert(list, {
			id = pt.id,
			name = pt.name,
			x = pt.x,
			z = pt.z,
			wait = wait,
			blocked = blocked,
			why = why,
			ready = wait <= 0 and not blocked,
			kind = pt.kind, -- símbolo na carta (QG, reunião, posto, squad)
			squad = pt.squad ~= nil,
		})
	end
	for _, entry in mateEntries(player, now, enemies) do
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
				ready = wait <= 0 and why == nil and m ~= nil,
				pay = m,
			})
		end
	end
	return list
end

-- objetivo do lado agora (studs), para o jogar agora escolher o ponto mais perto da luta
local function objectiveOf(faction: string): (number?, number?)
	local st = MatchService.state
	if not st then
		return nil, nil
	end
	local ok, _, s = pcall(Front.objective, st.owner, st.active, faction)
	local sp = if ok and s then MatchService.points[s] else nil
	if sp then
		return sp.x, sp.z
	end
	return nil, nil
end

-- Jogar agora: lado, squad, papel e o ponto (o último ou o melhor). A resposta vai no atributo
-- "JogarAgora" ("<id>|<n>" ou "!<motivo>|<n>"); quem entra é o cliente, pelo Spawn_Request normal,
-- quando a espera do ponto acaba (a transição e a compra do veículo seguem iguais).
local quickAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local function quickPlay(player: Player, req: any)
	local n = if type(req) == "table" and type(req.n) == "number" then math.floor(req.n) % 100000 else 0
	local vehicle = type(req) == "table" and req.v == true
	local t = os.clock()
	if t - (quickAt[player] or 0) < 0.4 then
		return
	end
	quickAt[player] = t
	local function reply(id: string?, why: string?)
		player:SetAttribute("JogarAgora", JogarAgora.reply(id, why, n))
	end
	if alive(player) then
		reply(nil, "Você já está em campo")
		return
	end
	if ReplicatedStorage:GetAttribute("TerrainReady") == false then
		reply(nil, "O campo ainda está sendo preparado")
		return
	end
	local why = TeamService.quickJoin(player, ProgressionService.rank(player))
	if why then
		reply(nil, why)
		return
	end
	local faction = player:GetAttribute("Faction")
	if type(faction) ~= "string" then
		reply(nil, "Sem lado")
		return
	end
	local role = tostring(player:GetAttribute("Role"))
	if ProgressionService.rank(player) < Roles.minRank(role) then
		reply(nil, "Papel acima do seu posto")
		return
	end
	local list = stateFor(player, faction, t, enemiesMeters(faction))
	local ox, oz = objectiveOf(faction)
	local last = player:GetAttribute("UltimoPonto")
	local pick = JogarAgora.pickPoint(list, if type(last) == "string" then last else nil, {
		vehicle = vehicle,
		allowed = CompraVeiculo.pointAllowed,
		objX = ox,
		objZ = oz,
	})
	if not pick then
		reply(nil, if vehicle then "Nenhum QG ou ponto de reunião livre agora" else "Nenhum ponto livre agora")
		return
	end
	reply(pick.id, nil)
end

function SpawnService.start()
	Players.CharacterAutoLoads = false
	hookCombat()
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
		if pointId == "quick" then
			quickPlay(player, method) -- jogar agora: lado, squad e papel podem faltar ainda
			return
		end
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
		if string.sub(pointId, 1, 5) == "mate:" then
			mateSpawn(player, faction, pointId)
			return
		end
		local now = os.clock()
		for _, pt in SpawnService.points(faction) do
			if pt.id == pointId and visibleTo(pt, player) then
				local wait, blocked = status(player, pt, now)
				if wait > 0 or blocked then
					return
				end
				local sx, sz = pt.x, pt.z
				if pt.kind == "hq" then
					sx, sz = SpawnService.hqSpot(faction, sx, sz)
				end
				spawnAt(player, faction, sx, sz, nil, pt.id)
				return
			end
		end
	end)

	-- estado dos pontos para quem está esperando (uma vez por segundo; campos em stateFor)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			local enemyCache: { [string]: { number } } = {}
			for _, player in Players:GetPlayers() do
				local faction = player:GetAttribute("Faction") :: string?
				if faction and not alive(player) then
					local enemies = enemyCache[faction]
					if not enemies then
						enemies = enemiesMeters(faction)
						enemyCache[faction] = enemies
					end
					Net.event("Spawn_State"):FireClient(player, stateFor(player, faction, now, enemies))
				end
			end
		end
	end)

	-- Gancho do Studio: workspace:SetAttribute("VT65DevSquadBots", n) põe n bots (true = 2) do lado do
	-- primeiro jogador com squad no squad dele, só pelo atributo SquadId no modelo (os bots continuam
	-- no squad deles), para ver os pontos de companheiro na carta de inserção (VT65DevTela = "insercao").
	-- 0 ou false tira.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevSquadBots"):Connect(function()
			local v = workspace:GetAttribute("VT65DevSquadBots")
			local want = if type(v) == "number" then v elseif v == true then 2 else 0
			for _, e in Combatants.list() do
				if e.bot and e.model:GetAttribute("SquadId") ~= nil then
					e.model:SetAttribute("SquadId", nil)
				end
			end
			for _, p in Players:GetPlayers() do
				local sid = p:GetAttribute("SquadId")
				if type(sid) == "string" then
					local n = 0
					for _, e in Combatants.list() do
						if n < want and e.bot and e.faction == p:GetAttribute("Faction") and Combatants.active(e) then
							e.model:SetAttribute("SquadId", sid)
							n += 1
						end
					end
					print(string.format("[VT65 TESTE] %d bot(s) no squad %s de %s", n, sid, p.Name))
					break
				end
			end
		end)
	end
end

return SpawnService
