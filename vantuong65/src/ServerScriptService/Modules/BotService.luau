--!strict
-- Bots que completam o servidor (Parte 11) e permitem testar o 15v15 da F2 com poucos humanos.
-- Saem quando entra gente. Usam as MESMAS regras: tiro simulado no servidor, dano, ferimentos,
-- spawn por ondas. Visão bloqueada por sebes e casas (não enxergam através da vegetação).
-- Nível médio que se adapta ao terreno (2026-11-11):
-- - ao avistar o inimigo ou com bala passando perto, procuram abrigo a até 15 m com raios em volta
--   (dique, sebe, tronco, parede, trincheira, sacos de areia) e vão para o lado protegido;
-- - a postura sai da altura medida do abrigo e do chão (deitam no arrozal e no capim sob fogo);
-- - bala perto suprime: ficam abaixados alguns segundos e miram pior;
-- - atiram do abrigo (saem, rajada curta, voltam) e trocam de abrigo depois de algumas rajadas;
-- - ferido recua para abrigo; granada em quem se esconde a 15-35 m.
-- D-90 (pedido do dono, 2026-11-11: veículos, locais, túneis, granadas; "movimentação linear como
-- se fossem jogadores reais"):
-- - pernas de jogador (BotLocomotion): caminho suave, inércia, corpo que vira, passo pela situação;
-- - mapa entendido (BotWorld): rota que foge do arrozal alagado e usa dique, sebe e mata; abrigos
--   fixos conhecidos (dique 12 m à frente sem gastar raio);
-- - squads (BotSquads): seguem o líder em coluna ou cunha, avisam o contato, avançam em lances;
-- - notar leva tempo (cone de visão), a mira firma no alvo novo, disciplina de fogo, supressão na
--   última posição vista, granada atrás do dique sem acertar o próprio squad;
-- - túneis só do VC (BotTunnels); blindados com tripulação de bots dos EUA (BotVehicles).
-- As decisões e os números ficam no BotBrain (puro, testado no Lune); aqui, os raios e o Humanoid.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local BotMove = require(ReplicatedStorage.Shared.BotMove)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Rng = require(ReplicatedStorage.Shared.Rng)
local Smoke = require(ReplicatedStorage.Shared.Smoke)
local Roles = require(ReplicatedStorage.Shared.Roles)
local SpawnRules = require(ReplicatedStorage.Shared.SpawnRules)
local Weather = require(ReplicatedStorage.Shared.Weather)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local AssetLoader = require(script.Parent.AssetLoader)
local BotEscolta = require(script.Parent.BotEscolta)
local BotLocomotion = require(script.Parent.BotLocomotion)
local BotSquads = require(script.Parent.BotSquads)
local BotTunnels = require(script.Parent.BotTunnels)
local BotTypes = require(script.Parent.BotTypes)
local BotVehicles = require(script.Parent.BotVehicles)
local BotWorld = require(script.Parent.BotWorld)
local Characters = require(script.Parent.Characters)
local CombatService = require(script.Parent.CombatService)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local MedicalService = require(script.Parent.MedicalService)
local PostureService = require(script.Parent.PostureService)
local SpawnService = require(script.Parent.SpawnService)
local TunnelService = require(script.Parent.TunnelService)
local VehicleService = require(script.Parent.VehicleService)

local BotService = {}
local M = 0.28
local C = BotBrain.C
local MOVE = BotBrain.MOVE
local SENSE = C.senseRangeM / M
local PROBE = C.probeM
local MAX_SHOT = 1000 / M -- bala não voa mais que isto (Ballistics: 2,5 s)
local PASS_THROUGH = { Bamboo = true, Thatch = true } :: { [string]: boolean } -- CombatService.PASS

type Cover = BotTypes.Cover
type Bot = BotTypes.Bot

local bots: { Bot } = {}
local folder = Instance.new("Folder")
folder.Name = "Combatants"
folder.Parent = workspace
local nextId = 0
local debugOn = false
local lastFire: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- quem atirou e quando

function BotService.fill(): number
	local v = ReplicatedStorage:GetAttribute("BotFill")
	if type(v) == "number" then
		return v
	end
	return if RunService:IsStudio() then 15 else 10
end

function BotService.list(): { Bot }
	return bots
end

-- 2026-11-12: põe (sid) ou tira (nil) o bot de um squad de JOGADOR (BotEscolta: os bots completam o
-- squad do jogador até 4). O atributo SquadId do modelo liga o "nascer no companheiro" (SpawnService)
-- e vale também depois de renascer.
function BotService.setPlayerSquad(bot: Bot, sid: string?)
	BotEscolta.setSquad(bot, sid)
end

local function humans(faction: string): number
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Faction") == faction then
			n += 1
		end
	end
	return n
end

local function objectivePos(faction: string): (Vector3?, number?)
	local st = MatchService.state
	if not st then
		return nil, nil
	end
	local s = BotBrain.objective(st.owner, st.active, faction)
	local sp = s and MatchService.points[s]
	if not (s and sp) then
		return nil, nil
	end
	return Vector3.new(sp.x, 0, sp.z), s
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function between(r: { number }, roll: number): number
	return r[1] + (r[2] - r[1]) * roll
end

-- lista de combatentes do quadro (uma por passada do laço, para todos os bots)
local listCache: { Combatants.Entry } = {}
local listAt = -1
local function combatList(): { Combatants.Entry }
	local now = os.clock()
	if now - listAt > 0.05 then
		listCache = Combatants.list()
		listAt = now
	end
	return listCache
end

-- zera o estado de uma vida nova (chamado no spawn)
local function resetLife(bot: Bot)
	local now = os.clock()
	bot.life += 1
	bot.mag = bot.weapon.magazine
	bot.reloadUntil, bot.nextVolley, bot.firing = 0, 0, false
	bot.target, bot.reactAt, bot.trackSince = nil, 0, 0
	bot.noticeTarget, bot.noticeAcc, bot.heardPos, bot.heardAt = nil, 0, nil, -math.huge
	bot.lastKnown, bot.lastKnownAt, bot.threatPos, bot.threatAt = nil, -math.huge, nil, -math.huge
	bot.inCombat, bot.contactAt, bot.nextSuppress = false, 0, 0
	bot.supp, bot.lastHealth, bot.lastThink = 0, -math.huge, now -- -inf: 1º pensamento só anota a vida
	bot.rays, bot.open, bot.wounded = bot.diff.rayCap, false, false
	bot.cover, bot.coverSector, bot.mode, bot.moveUntil = nil, nil, "advance", 0
	bot.nextPeek, bot.peekUntil, bot.peekFired = 0, 0, false
	bot.bursts, bot.burstsMax, bot.failedPeeks, bot.exposed = 0, 2, 0, 0
	bot.recheckAt, bot.searchAt, bot.avoid, bot.resumeAt = 0, 0, nil, 0
	bot.grenades, bot.nextGrenade = 0, 0
	bot.goal, bot.goalSector = nil, nil
	bot.scanAt, bot.scanSide = 0, 0
	bot.stillSince = nil
	BotTunnels.reset(bot)
end

local function setStance(model: Model, stance: string)
	PostureService.setStance(model, stance)
end

local function stanceOf(model: Model): string
	if model:GetAttribute("Prone") then
		return "prone"
	elseif model:GetAttribute("Crouched") then
		return "crouch"
	end
	return "stand"
end

local function spawnModel(bot: Bot)
	local pts = SpawnService.freePoints(bot.faction)
	if #pts == 0 then
		return
	end
	local goal = objectivePos(bot.faction)
	local atHQ = BotVehicles.spawnAtHQ(bot) -- tripulação e squad do LVTP-5 nascem no QG
	-- 2026-11-12: bot no squad de um jogador nasce no ponto livre mais perto do humano que segue
	local near = BotEscolta.spawnAnchor(bot) or goal
	table.sort(pts, function(a, b)
		if atHQ or not near then
			return a.kind == "hq" and b.kind ~= "hq"
		end
		local da = (Vector3.new(a.x, 0, a.z) - Vector3.new(near.X, 0, near.Z)).Magnitude
		local db = (Vector3.new(b.x, 0, b.z) - Vector3.new(near.X, 0, near.Z)).Magnitude
		return da < db
	end)
	local pt = pts[1]
	local desc = Characters.describe(bot.faction, nil, bot.id)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return
	end
	if bot.removed then
		model:Destroy() -- saiu enquanto o avatar era criado (entrou gente)
		return
	end
	model.Name = string.format("Bot_%s_%02d", bot.faction, bot.id)
	model:SetAttribute("Bot", true)
	model:SetAttribute("Role", bot.role)
	model:SetAttribute("BotIndex", bot.id)
	-- 2026-11-12: nome legível (carta de inserção, nascer no companheiro) e o squad de jogador, se ele
	-- estiver num (SpawnService lê SquadId e BotName do modelo)
	local roleDef = Roles.roles[bot.role]
	model:SetAttribute("BotName", string.format("%s %02d", if roleDef then roleDef.name else bot.role, bot.id))
	model:SetAttribute("SquadId", bot.playerSquad)
	resetLife(bot)
	-- Died antes de qualquer espera: register() já o torna alvo, e attachWeapon/dress carregam
	-- arte (LoadAsset). Morto nessa janela, o bot ficava caído para sempre, sem largar a arma e
	-- sem voltar (autoteste no Studio, 2026-11-10: "nenhuma arma caiu em 3 s").
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		-- 2026-11-12: o nome "Bot_US_09" flutuava sobre o bot (fotos da v36); o aliado já aparece
		-- pelos marcadores da interface
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.NameDisplayDistance = 0
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	if hum then
		hum.Died:Connect(function()
			local t = os.clock()
			bot.readyAt = SpawnRules.readyAt(t, 0, MatchService.waveEpoch)
			BotLocomotion.detach(bot)
			BotTunnels.reset(bot)
			-- a arma do bot cai com o que tinha no carregador (Parte 11: pegar a arma do inimigo)
			local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				if r.Anchored then
					r.Anchored = false -- morreu no túnel
				end
				CombatService.dropWeapon(r.Position, bot.weapon.id, bot.mag)
			end
			task.delay(5, function()
				if bot.model == model then
					bot.model = nil
				end
				model:Destroy()
			end)
		end)
	end
	local jx, jz = bot.rng:range(-20, 20), bot.rng:range(-20, 20)
	local y = SpawnService.groundY(pt.x + jx, pt.z + jz)
	local face = if goal then BotMove.yawTo(goal.X - pt.x, goal.Z - pt.z) else 0
	model:PivotTo(CFrame.new(pt.x + jx, y + 5, pt.z + jz) * CFrame.Angles(0, face, 0))
	model.Parent = folder
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root:SetNetworkOwner(nil)
	end
	Combatants.register(model, bot.faction, nil)
	AssetLoader.attachWeapon(model, bot.weapon.id)
	Characters.dress(model, bot.faction, nil)
	if hum and hum.Health <= 0 then
		return -- morreu enquanto se vestia: o Died já marcou a volta e some com o corpo
	end
	if bot.removed then
		model:Destroy()
		return
	end
	bot.model = model
	BotLocomotion.attach(bot, model)
end

local function newBot(faction: string): Bot
	nextId += 1
	local idx = 0
	for _, b in bots do
		if b.faction == faction then
			idx += 1
		end
	end
	-- squad de 6: líder, 4 fuzileiros e a metralhadora
	local role = if idx % 6 == 5 then "machine_gunner" elseif idx % 6 == 0 then "squad_leader" else "rifleman"
	local wid = Roles.loadout[faction][role][1]
	local wp = Weapons.get(wid) :: Weapons.Weapon
	local diff = BotBrain.DIFFICULTY.medium
	local bot: Bot = {
		id = nextId,
		faction = faction,
		role = role,
		weapon = wp,
		rng = Rng.new(nextId * 7919 + os.time()),
		diff = diff,
		style = if faction == "VC" then BotBrain.STYLE.VC else BotBrain.STYLE.US,
		model = nil,
		spawning = false,
		life = 0,
		mag = wp.magazine,
		reloadUntil = 0,
		nextVolley = 0,
		firing = false,
		target = nil,
		reactAt = 0,
		trackSince = 0,
		noticeTarget = nil,
		noticeAcc = 0,
		heardPos = nil,
		heardAt = -math.huge,
		lastKnown = nil,
		lastKnownAt = -math.huge,
		threatPos = nil,
		threatAt = -math.huge,
		inCombat = false,
		contactAt = 0,
		nextSuppress = 0,
		supp = 0,
		lastHealth = -math.huge,
		lastThink = 0,
		rays = diff.rayCap,
		open = false,
		wounded = false,
		cover = nil,
		coverSector = nil,
		mode = "advance",
		moveUntil = 0,
		nextPeek = 0,
		peekUntil = 0,
		peekFired = false,
		bursts = 0,
		burstsMax = 2,
		failedPeeks = 0,
		exposed = 0,
		recheckAt = 0,
		searchAt = 0,
		avoid = nil,
		resumeAt = 0,
		grenades = 0,
		nextGrenade = 0,
		goal = nil,
		goalSector = nil,
		readyAt = 0, -- primeiro spawn imediato
		removed = false,
		loco = nil,
		squad = nil,
		slot = 0,
		team = 1,
		crew = nil,
		tunnel = nil,
		scanAt = 0,
		scanSide = 0,
		order = nil,
	}
	table.insert(bots, bot)
	BotSquads.assign(bot)
	return bot
end

---------------------------------------------------------------------------------------------
-- Raios
---------------------------------------------------------------------------------------------

-- Abrigo: ignora gente, armas caídas, fumaça, a lâmina d'água do arrozal e os animais (refeito a
-- cada 1 s). Chão: só o terreno. Superfície: terreno e lâmina (para saber se é arrozal).
local coverParams = RaycastParams.new()
coverParams.FilterType = Enum.RaycastFilterType.Exclude
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Include
local shotParams = RaycastParams.new()
shotParams.FilterType = Enum.RaycastFilterType.Exclude
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshFilters()
	local map = workspace:FindFirstChild("Map")
	local water = if map then map:FindFirstChild("PaddyWater") else nil
	local ex: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	for _, name in { "DroppedWeapons", "Smoke", "Granadas" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ex, f)
		end
	end
	-- pernas e cunha: mesma lista (o raio do joelho respeita colisão: a lâmina d'água não conta)
	BotLocomotion.setIgnore(table.clone(ex))
	BotSquads.setIgnore(table.clone(ex))
	if water then
		table.insert(ex, water)
	end
	local art = if map then map:FindFirstChild("Art") else nil
	local animals = if art then art:FindFirstChild("Animals") else nil
	if animals then
		table.insert(ex, animals)
	end
	coverParams.FilterDescendantsInstances = ex
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	surfaceParams.FilterDescendantsInstances = if water then { workspace.Terrain, water } else { workspace.Terrain }
end

-- conta os raios de abrigo para o orçamento de cada bot
local raysUsed = 0
local function cast(from: Vector3, dir: Vector3, params: RaycastParams): RaycastResult?
	raysUsed += 1
	return workspace:Raycast(from, dir, params)
end

local function footY(root: BasePart, hum: Humanoid): number
	return root.Position.Y - hum.HipHeight - root.Size.Y / 2
end

-- modelo de arte mais de fora (AssetLoader põe o nome da chave do asset nele)
local function topModel(inst: Instance): Model?
	local best: Model? = nil
	local p = inst.Parent
	while p and p ~= workspace do
		if p:IsA("Model") then
			best = p
		end
		p = p.Parent
	end
	return best
end

local function classify(inst: Instance): string
	if inst:IsA("Terrain") then
		return "terrain"
	end
	local m = topModel(inst)
	local mat = inst:GetAttribute("Material")
	return BotBrain.coverKind(inst.Name, if m then m.Name else nil, if type(mat) == "string" then mat else nil, false)
end

-- espessura de obstáculo fino e reto (segmento do FeatureBuilder: comprimento em X, espessura em Z)
local function thickness(inst: Instance): number?
	if inst:IsA("BasePart") and (inst.Name == "Dike" or inst.Name == "PaddyHedge" or inst.Name == "BambooHedge") then
		return inst.Size.Z
	end
	return nil
end

-- chão sob o bot: arrozal (lâmina d'água), capim, mata, areia, lama
local function surfaceAt(p: Vector3): string
	local r = cast(p + Vector3.new(0, 2, 0), Vector3.new(0, -12 / M, 0), surfaceParams)
	if not r then
		return "other"
	end
	if r.Instance.Name == "PaddyWater" then
		return "paddy"
	end
	local mat = r.Material
	if mat == Enum.Material.Grass then
		return "grass" -- arrozal seco e capim (TerrainBuilder)
	elseif mat == Enum.Material.LeafyGrass then
		return "forest"
	elseif mat == Enum.Material.Sand then
		return "sand"
	elseif mat == Enum.Material.Mud then
		return "mud"
	end
	return "other"
end

local function groundAt(x: number, z: number, nearY: number): number
	local r = cast(Vector3.new(x, nearY + 4 / M, z), Vector3.new(0, -10 / M, 0), terrainParams)
	return if r then r.Position.Y else nearY
end

-- Mede o abrigo num lugar (Y = chão): nível 0..3, tipo do que tapa e o lado livre para atirar
-- (só abrigo alto). Até 5 raios.
local function probeAt(spot: Vector3, toward: Vector3): (number, string, number, Vector3)
	local d = Vector3.new(toward.X - spot.X, 0, toward.Z - spot.Z)
	if d.Magnitude < 1 then
		return 0, "none", 0, Vector3.xAxis
	end
	local u = d.Unit
	local len = u * (C.probeLenM / M)
	local hits = { false, false, false }
	local kind = "none"
	for k = 1, 3 do
		local r = cast(spot + Vector3.new(0, PROBE[k] / M, 0), len, coverParams)
		if r then
			hits[k] = true
			if kind == "none" then
				kind = classify(r.Instance)
			end
		end
	end
	local level = BotBrain.coverLevel(hits[1], hits[2], hits[3])
	local sideDir = Vector3.new(-u.Z, 0, u.X)
	local side = 0
	if level >= 3 then
		local eye = spot + Vector3.new(0, PROBE[3] / M, 0)
		for _, sgn in { 1, -1 } do
			if not cast(eye + sideDir * sgn * (C.peekStepM / M), len, coverParams) then
				side = sgn
				break
			end
		end
	end
	return level, kind, side, sideDir
end

type Found = { pos: Vector3, score: number }

-- Busca de abrigo contra `threat`: raios em volta na altura do dique, lugar do lado protegido
-- (BotBrain.coverSpot), nota pelo tipo e mede o lugar atual e os 2 melhores. Custa até
-- C.searchCost raios, descontados do orçamento do bot. Também decide se o chão é aberto.
-- D-90: os abrigos fixos do mapa (BotWorld: dique, sebe, parede, trincheira) entram como
-- candidatos sem gastar raio; no lance de ataque, o avanço pesa mais.
local function searchCover(bot: Bot, hum: Humanoid, root: BasePart, threat: Vector3, retreating: boolean): Cover?
	raysUsed = 0
	local here = root.Position
	local foot = footY(root, hum)
	local base = Vector3.new(here.X, foot, here.Z)
	local surface = surfaceAt(here)
	local goal = bot.goal
	local avoid = bot.avoid
	local style = bot.style
	if BotSquads.advancing(bot) and not retreating then
		style = table.clone(style)
		style.advanceBias *= BotBrain.SQUAD.boundAdvance
	end
	local function candidate(p: Vector3, kind: string, level: number, blind: boolean): BotBrain.Candidate
		return {
			kind = kind,
			level = level,
			distM = flat(here, p) * M,
			enemyM = flat(p, threat) * M,
			progressM = if goal then (flat(here, goal) - flat(p, goal)) * M else 0,
			awayM = (flat(p, threat) - flat(here, threat)) * M,
			blind = blind,
		}
	end
	local found: { Found } = {}
	local solid = 0
	local origin = base + Vector3.new(0, C.scanHeightM / M, 0)
	local reach = bot.diff.coverSearchM / M
	local a0 = bot.rng:next() * 2 * math.pi
	for i = 0, C.coverRays - 1 do
		local a = a0 + i * 2 * math.pi / C.coverRays
		local r = cast(origin, Vector3.new(math.cos(a), 0, math.sin(a)) * reach, coverParams)
		-- face de pé (o chão subindo não conta)
		if r and r.Normal.X * r.Normal.X + r.Normal.Z * r.Normal.Z >= 0.09 then
			local kind = classify(r.Instance)
			local info = BotBrain.COVER[kind] or BotBrain.COVER.solid
			if info.solid then
				solid += 1
			end
			local sx, sz = BotBrain.coverSpot(
				r.Position.X,
				r.Position.Z,
				r.Normal.X,
				r.Normal.Z,
				threat.X,
				threat.Z,
				C.standoffM / M,
				thickness(r.Instance)
			)
			if sx and sz then
				local p = Vector3.new(sx, foot, sz)
				if not (avoid and flat(p, avoid) < C.relocateMinM / M) then
					local s = BotBrain.coverScore(style, candidate(p, kind, info.level, false), retreating)
					table.insert(found, { pos = p, score = s })
				end
			end
		end
	end
	-- abrigos fixos conhecidos (sem raio): lado protegido do segmento mais perto
	for _, e in BotWorld.coversNear(here, reach) do
		local px, pz, nx, nz = BotWorld.closest(e, here.X, here.Z)
		if (threat.X - px) * nx + (threat.Z - pz) * nz > 0 then
			nx, nz = -nx, -nz -- normal para o nosso lado
		end
		local back = e.half + C.standoffM / M
		local p = Vector3.new(px + nx * back, foot, pz + nz * back)
		if flat(p, here) <= reach and not (avoid and flat(p, avoid) < C.relocateMinM / M) then
			local info = BotBrain.COVER[e.kind] or BotBrain.COVER.solid
			local s = BotBrain.coverScore(style, candidate(p, e.kind, info.level, false), retreating)
			table.insert(found, { pos = p, score = s })
		end
	end
	bot.open = BotBrain.openGround(surface, solid, C.coverRays)
	table.sort(found, function(a, b)
		return a.score > b.score
	end)
	local best: Cover? = nil
	local bestScore = -math.huge
	local function consider(p: Vector3)
		local level, kind, side, sideDir = probeAt(p, threat)
		if level <= 0 then
			return
		end
		local s = BotBrain.coverScore(style, candidate(p, kind, level, level >= 3 and side == 0), retreating)
		if s > bestScore then
			bestScore = s
			best = { pos = p, level = level, kind = kind, side = side, sideDir = sideDir }
		end
	end
	-- o lugar atual também concorre (pode já estar abrigado: trincheira, atrás do dique)
	if not (avoid and flat(base, avoid) < C.relocateMinM / M) then
		consider(base)
	end
	for i = 1, math.min(#found, C.coverVerify) do
		local p = found[i].pos
		consider(Vector3.new(p.X, groundAt(p.X, p.Z, foot), p.Z))
	end
	bot.rays -= raysUsed
	return best
end

-- O abrigo ainda tapa a ameaça na altura em que foi medido? (o inimigo pode ter dado a volta)
local function stillCovers(bot: Bot, c: Cover, threat: Vector3): boolean
	local d = Vector3.new(threat.X - c.pos.X, 0, threat.Z - c.pos.Z)
	if d.Magnitude < 1 then
		return false
	end
	raysUsed = 0
	local h = PROBE[math.clamp(c.level, 1, 3)]
	local r = cast(c.pos + Vector3.new(0, h / M, 0), d.Unit * (C.probeLenM / M), coverParams)
	bot.rays -= raysUsed
	return r ~= nil
end

local function visible(from: Vector3, target: Model, selfModel: Model): boolean
	local head = target:FindFirstChild("Head") :: BasePart?
	if not head then
		return false
	end
	losParams.FilterDescendantsInstances = { selfModel }
	local r = workspace:Raycast(from, head.Position - from, losParams)
	if not (r ~= nil and r.Instance:IsDescendantOf(target)) then
		return false
	end
	-- fumaça tapa a visão (não as balas)
	local h = head.Position
	return not Smoke.blocks(from.X, from.Y, from.Z, h.X, h.Y, h.Z, Smoke.clouds(workspace:FindFirstChild("Smoke")))
end

type Seen = { m: Model, d: number }

-- ===== camuflagem de mato (Shared/Skins): em que vegetação o alvo camuflado está =====
-- Índice das plantas da arte (Map/Art e Map/Art/Jungle; o modelo tem o nome da chave), montado uma
-- vez depois que a arte foi posta, numa grade com células do tamanho do raio de contagem. A lâmina
-- d'água do arrozal sai de um raio para baixo. O resultado de cada alvo vale 1 s.
type Plant = { x: number, z: number, k: string }
local VEG_R = BotBrain.VEG.radiusM / M
local vegCells: { [string]: { Plant } }? = nil
local vegBuilding = false
local function buildVeg()
	local map = workspace:FindFirstChild("Map")
	local art = if map then map:FindFirstChild("Art") else nil
	if vegCells or vegBuilding or not art or art:GetAttribute("Placed") ~= true then
		return
	end
	vegBuilding = true
	task.spawn(function()
		local cells: { [string]: { Plant } } = {}
		local n = 0
		local function add(m: Instance)
			local kind = BotBrain.plantKind(m.Name)
			if kind and m:IsA("Model") then
				local p = m:GetPivot().Position
				local key = math.floor(p.X / VEG_R) .. "," .. math.floor(p.Z / VEG_R)
				local list = cells[key] or {}
				cells[key] = list
				table.insert(list, { x = p.X, z = p.Z, k = kind })
				n += 1
				if n % 2000 == 0 then
					task.wait()
				end
			end
		end
		for _, c in art:GetChildren() do
			add(c)
		end
		local jungle = art:FindFirstChild("Jungle")
		for _, c in if jungle then jungle:GetChildren() else {} do
			add(c)
		end
		vegCells = cells
	end)
end

local function vegetationAt(pos: Vector3): string
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -12 / M, 0), surfaceParams)
	local surface = if hit and hit.Instance.Name == "PaddyWater" then "paddy" else "ground"
	local n: { [string]: number } = { jungle = 0, bamboo = 0, grass = 0, rice = 0 }
	local cells = vegCells
	if cells then
		local cx, cz = math.floor(pos.X / VEG_R), math.floor(pos.Z / VEG_R)
		local r2 = VEG_R * VEG_R
		for dx = -1, 1 do
			for dz = -1, 1 do
				local list = cells[(cx + dx) .. "," .. (cz + dz)]
				if list then
					for _, pl in list do
						local ddx, ddz = pl.x - pos.X, pl.z - pos.Z
						if ddx * ddx + ddz * ddz <= r2 then
							n[pl.k] = (n[pl.k] or 0) + 1
						end
					end
				end
			end
		end
	else
		buildVeg()
	end
	return BotBrain.vegetation(surface, { jungle = n.jungle, bamboo = n.bamboo, grass = n.grass, rice = n.rice })
end

local vegCache: { [Model]: { t: number, v: string } } = setmetatable({}, { __mode = "k" }) :: any
local function vegOf(model: Model, pos: Vector3): string
	local now = os.clock()
	local c = vegCache[model]
	if c and now - c.t < 1 then
		return c.v
	end
	local v = vegetationAt(pos)
	vegCache[model] = { t = now, v = v }
	return v
end

-- Inimigo ativo com linha de visada: o alvo atual primeiro (fixação de alvo), senão o mais perto.
-- Só os C.maxLosChecks mais próximos gastam raio; deitado e agachado são vistos de mais perto, e o
-- camuflado na vegetação do tipo da camuflagem mais perto ainda (BotBrain.spotFactor). Quem está no
-- túnel ou dentro de veículo fica de fora da busca (o terreno e a lata tapam).
local function perceive(bot: Bot, model: Model, root: BasePart, eye: Vector3): (Model?, number)
	-- chuva forte: enxergam até metade da distância (Weather)
	local rain = ReplicatedStorage:GetAttribute("Rain")
	local weather = Weather.sightFactor(if type(rain) == "number" then rain else 0)
	-- 2026-11-12: o alcance de cada alvo sai da vegetação em que ele está (BotBrain.sightRange: 120 m no
	-- aberto, 40 m na mata, 15 m no capim), da postura, da camuflagem e de estar atirando
	local cap = SENSE * BotBrain.SIGHT_FIRING * weather
	local now = os.clock()
	local cands: { Seen } = {}
	for _, e in combatList() do
		if e.faction ~= bot.faction and Combatants.active(e) and not e.model:GetAttribute("InTunnel") then
			local r = Combatants.root(e)
			if r then
				local dd = (r.Position - root.Position).Magnitude
				if dd < cap then
					local tracking = e.model == bot.target
					local camo = e.model:GetAttribute("Camo")
					local firing = now - (lastFire[e.model] or -math.huge) < 2
					local rangeM = BotBrain.sightRange(
						bot.diff,
						vegOf(e.model, r.Position),
						stanceOf(e.model),
						tracking,
						if type(camo) == "string" then camo else nil,
						firing
					)
					if dd < rangeM / M * weather then
						table.insert(cands, { m = e.model, d = if tracking then -1 else dd })
					end
				end
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.d < b.d
	end)
	local checks = 0
	for _, c in cands do
		if checks < C.maxLosChecks or c.m == bot.target then
			checks += 1
			if visible(eye, c.m, model) then
				local r = c.m:FindFirstChild("HumanoidRootPart") :: BasePart?
				return c.m, if r then (r.Position - root.Position).Magnitude else c.d
			end
		end
	end
	return nil, 0
end

-- D-90: notar leva tempo. Devolve o alvo já notado (ou nil enquanto ainda não notou).
local function notice(bot: Bot, root: BasePart, seen: Model?, seenD: number, dt: number, now: number): Model?
	if not seen or seen == bot.target then
		bot.noticeTarget, bot.noticeAcc = nil, 0
		return seen
	end
	if bot.noticeTarget ~= seen then
		bot.noticeTarget, bot.noticeAcc = seen, 0
	end
	bot.noticeAcc += dt
	local tr = seen:FindFirstChild("HumanoidRootPart") :: BasePart?
	local still = tr == nil or tr.AssemblyLinearVelocity.Magnitude * M < 0.3
	local firing = now - (lastFire[seen] or -math.huge) < 2
	local off = 0
	local veg: string? = nil
	if tr then
		off = math.deg(BotLocomotion.facingError(bot, tr.Position))
		veg = vegOf(seen, tr.Position) -- 2026-11-12: na mata e no capim demora mais a notar
	end
	local need = BotBrain.noticeTime(bot.diff, seenD * M, stanceOf(seen), still, firing, off, veg)
	if bot.inCombat then
		need *= bot.diff.alertedReaction -- já em combate, procurando: nota mais rápido
	end
	if bot.noticeAcc >= need then
		bot.noticeTarget, bot.noticeAcc = nil, 0
		return seen
	end
	-- ouvindo um tiro dele, já vira para lá
	if firing and tr then
		BotLocomotion.face(bot, tr.Position)
	end
	local _ = root
	return nil
end

---------------------------------------------------------------------------------------------
-- Ações
---------------------------------------------------------------------------------------------

local function perturb(dir: Vector3, sigma: number, rng: Rng.Rng): Vector3
	local up = if math.abs(dir.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local r = dir:Cross(up).Unit
	local q = r:Cross(dir).Unit
	return (dir + r * rng:gauss() * sigma + q * rng:gauss() * sigma).Unit
end

-- 2026-11-12: mira sempre no meio do tronco (BotBrain.aimPartName). Antes mirava na cabeça de quem
-- estava abaixado e acertava cabeça em série.
local function aimPart(target: Model): BasePart?
	local name = BotBrain.aimPartName(stanceOf(target))
	return (target:FindFirstChild(name) or target:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function startReload(bot: Bot, now: number)
	bot.reloadUntil = now + (C.reloadS[bot.weapon.kind] or 3)
	bot.mag = bot.weapon.magazine
end

-- Rajada curta (BotBrain.volleySize) numa tarefa própria, na cadência certa. Cada tiro recalcula o
-- erro (distância, supressão, postura, braço ferido, recuo e a mira que firma, D-90). Depois, pausa
-- até a próxima. `at`: supressão numa posição (sem alvo à vista).
local function fireVolley(bot: Bot, target: Model?, at: Vector3?)
	local model = bot.model
	if not model then
		return
	end
	local d = bot.diff
	local kind = bot.weapon.kind
	local n = math.min(BotBrain.volleySize(d, kind, bot.rng:next()), bot.mag)
	if n <= 0 then
		return
	end
	bot.firing = true
	local life = bot.life
	task.spawn(function()
		for i = 1, n do
			local hum = model:FindFirstChildOfClass("Humanoid")
			local head = model:FindFirstChild("Head") :: BasePart?
			local aim = if target then aimPart(target) else nil
			local te = if target then Combatants.get(target) else nil
			local aimPos = if aim then aim.Position else at
			if
				bot.life ~= life
				or bot.model ~= model
				or not (hum and head and aimPos)
				or hum.Health <= 0
				or model:GetAttribute("Downed")
				or (target ~= nil and not (te and Combatants.active(te)))
				or bot.mag <= 0
			then
				break
			end
			local to = (aimPos :: Vector3) - (head :: BasePart).Position
			local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local sigma = BotBrain.aimError(d, to.Magnitude * M, {
				moving = r ~= nil and r.AssemblyLinearVelocity.Magnitude > 2,
				suppression = bot.supp,
				stance = stanceOf(model),
				armHurt = model:GetAttribute("ArmImpaired") == true,
				shot = i,
				kind = kind,
			}) * BotBrain.settleFactor(d, if target then os.clock() - bot.trackSince else 0)
			CombatService.fire(
				model,
				bot.weapon.id,
				(head :: BasePart).Position,
				perturb(to.Unit, sigma, bot.rng),
				bot.rng:nextU32(),
				nil
			)
			bot.mag -= 1
			if i < n then
				task.wait(BotBrain.volleyGap(d, kind, bot.weapon.rpm, bot.rng:next()))
			end
		end
		if bot.life == life then
			bot.firing = false
			bot.nextVolley = os.clock() + BotBrain.pause(d, kind, bot.rng:next())
		end
	end)
end

-- Atira se já reagiu, se a pausa acabou, se tem munição (senão, recarrega), se está no alcance
-- (disciplina) e se o corpo já está virado para o alvo (D-90: vira primeiro, depois atira).
local function tryFire(bot: Bot, target: Model, now: number, distStuds: number?): boolean
	if bot.firing or now < bot.reactAt or now < bot.nextVolley or now < bot.reloadUntil then
		return false
	end
	if bot.mag <= 0 then
		startReload(bot, now)
		return false
	end
	if distStuds and not BotBrain.inRange(bot.diff, bot.weapon.kind, distStuds * M) then
		return false
	end
	local aim = aimPart(target)
	if aim then
		BotLocomotion.face(bot, aim.Position)
		if BotLocomotion.facingError(bot, aim.Position) > math.rad(15) then
			return false
		end
	end
	fireVolley(bot, target, nil)
	return bot.firing
end

-- Posições de companheiros (e para onde vão) em lista plana, para a granada não cair neles
local function friendsXZ(bot: Bot): { number }
	local out: { number } = {}
	for _, e in combatList() do
		if e.faction == bot.faction and Combatants.active(e) then
			local er = Combatants.root(e)
			if er then
				table.insert(out, er.Position.X)
				table.insert(out, er.Position.Z)
			end
		end
	end
	for _, b in bots do
		if b ~= bot and b.faction == bot.faction and b.model then
			local dest = BotLocomotion.dest(b)
			if dest then
				table.insert(out, dest.X)
				table.insert(out, dest.Z)
			end
		end
	end
	return out
end

-- FieldService.throwFrom está sendo escrita por outra pessoa: require tardio (só aqui dentro),
-- protegido por pcall e só se a função existir. Sem ela, o bot não joga e nada quebra.
local function throwGrenade(model: Model, faction: string, at: Vector3): boolean
	local ok, res = pcall(function(): boolean
		local FieldService = require(script.Parent.FieldService) :: any
		local fn = if type(FieldService) == "table" then FieldService.throwFrom else nil
		if type(fn) ~= "function" then
			return false
		end
		return fn(model, faction, "frag", at, nil) == true
	end)
	return ok and res == true
end

-- Arremesso com as regras do bot (conta da vida, recarga, sem companheiro no ponto). Usado pelo
-- BotTunnels (boca do túnel) e pela granada de combate.
local function botThrow(bot: Bot, at: Vector3): boolean
	local model = bot.model
	local G = bot.diff.grenade
	if not model or bot.grenades >= G.perLife or os.clock() < bot.nextGrenade then
		return false
	end
	if not BotBrain.grenadeClear(at.X, at.Z, friendsXZ(bot), G.friendlyClearM / M) then
		return false
	end
	bot.grenades += 1
	bot.nextGrenade = os.clock() + G.cooldownS
	if model:GetAttribute("Prone") then
		setStance(model, "crouch")
	end
	local life = bot.life
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		BotLocomotion.face(bot, at)
	end
	task.spawn(function()
		if not throwGrenade(model, bot.faction, at) and bot.life == life then
			bot.grenades -= 1
			bot.nextGrenade = os.clock() + G.retryS
		end
	end)
	return true
end

-- Granada no inimigo que se escondeu a 15-35 m, ou que está atrás de dique ou parede (D-90: o
-- ponto passa um pouco do abrigo), nunca no próprio squad (BotBrain.shouldThrow, grenadeClear).
local function maybeGrenade(bot: Bot, model: Model, root: BasePart, now: number, pinned: boolean, target: Model?)
	local lk = bot.lastKnown
	if not lk then
		return
	end
	local G = bot.diff.grenade
	local distM = flat(root.Position, lk) * M
	if distM < G.minM or distM > G.maxM or now < bot.nextGrenade or bot.grenades >= G.perLife then
		return -- atalho barato antes de olhar os companheiros
	end
	local aimAt = lk
	local covered = false
	if target then
		-- vendo: só vale se o corpo dele está atrás de algo sólido (1 raio no peito)
		local torso = target:FindFirstChild("UpperTorso") :: BasePart?
		local head = model:FindFirstChild("Head") :: BasePart?
		if not (torso and head) or bot.rays < 1 then
			return
		end
		bot.rays -= 1
		local hit = workspace:Raycast(head.Position, torso.Position - head.Position, coverParams)
		if not hit or hit.Instance:IsDescendantOf(target) then
			return
		end
		local kind = classify(hit.Instance)
		local info = BotBrain.COVER[kind] or BotBrain.COVER.solid
		if not info.solid or (hit.Position - torso.Position).Magnitude * M > 3 then
			return
		end
		covered = true
		local ax, az = BotBrain.grenadeAim(hit.Position.X, hit.Position.Z, torso.Position.X, torso.Position.Z, 1.2 / M)
		aimAt = Vector3.new(ax, torso.Position.Y - 2, az)
	end
	local go = BotBrain.shouldThrow(bot.diff, {
		distM = distM,
		los = target ~= nil,
		thrown = bot.grenades,
		now = now,
		nextAt = bot.nextGrenade,
		knownAgeS = now - bot.lastKnownAt,
		friendlyNear = not BotBrain.grenadeClear(aimAt.X, aimAt.Z, friendsXZ(bot), G.friendlyClearM / M),
		pinned = pinned,
		roll = bot.rng:next(),
		covered = covered,
	})
	if go then
		botThrow(bot, aimAt)
	end
end

local function enemyHQ(bot: Bot, root: BasePart): Vector3
	local hq = MapConfig.HQ[if bot.faction == "US" then "VC" else "US"]
	if hq then
		return Vector3.new(hq.x, root.Position.Y, hq.z)
	end
	return root.Position + root.CFrame.LookVector * 100
end

---------------------------------------------------------------------------------------------
-- Comportamento
---------------------------------------------------------------------------------------------

local function relocate(bot: Bot, now: number)
	local c = bot.cover
	bot.avoid = if c then c.pos else nil
	bot.cover = nil
	bot.mode = "advance"
	bot.searchAt = now
end

-- Vai até o abrigo. Sob fogo corre; com o alvo à vista e perto, anda de lado mirando e atira
-- (D-90). Preso pelo fogo longe dele, abaixa e espera aliviar. Devolve true ao chegar.
local function goTo(
	bot: Bot,
	model: Model,
	root: BasePart,
	now: number,
	underFire: boolean,
	pinned: boolean,
	target: Model?,
	targetD: number
): boolean
	local c = bot.cover
	if not c then
		return false
	end
	local dist = flat(root.Position, c.pos)
	if dist <= C.arriveM / M or BotLocomotion.status(bot) == "arrived" and dist <= 2 / M then
		return true
	end
	if pinned and dist > 2 / M then
		-- preso longe do abrigo: rasteja se é perto, senão abaixa e espera
		if dist * M <= MOVE.crawlMaxM then
			setStance(model, "prone")
			BotLocomotion.go(bot, c.pos, "prone", { direct = true })
		else
			setStance(model, BotBrain.coverStance("none", 0, true, true, bot.open))
			BotLocomotion.stop(bot, bot.lastKnown)
		end
		bot.moveUntil += C.thinkS
		return false
	end
	local ap = if target then aimPart(target) else nil
	if target and ap and not underFire and targetD * M <= bot.diff.strafeFireM then
		-- anda de lado mirando e atira andando (erro maior: BotBrain.aimError "moving")
		setStance(model, "stand")
		BotLocomotion.go(bot, c.pos, "ads", { direct = dist * M < MOVE.directM, face = ap.Position })
		tryFire(bot, target, now, targetD)
	else
		setStance(model, "stand")
		BotLocomotion.go(
			bot,
			c.pos,
			if underFire or bot.open then "sprint" else "jog",
			{ direct = dist * M < MOVE.directM }
		)
	end
	if now > bot.moveUntil or BotLocomotion.status(bot) == "failed" then
		-- não chegou (caminho fechado, água funda): larga este abrigo
		relocate(bot, now)
	end
	return false
end

local function chooseCover(bot: Bot, root: BasePart, c: Cover, now: number, retreating: boolean)
	bot.cover = c
	bot.mode = "move"
	bot.moveUntil = now + flat(root.Position, c.pos) * M / 2 + 4 -- a 2 m/s, com folga
	bot.bursts, bot.failedPeeks, bot.exposed = 0, 0, 0
	bot.burstsMax = BotBrain.burstsPerCover(bot.diff, bot.style, bot.rng:next(), retreating)
	if BotSquads.covering(bot) and not retreating then
		bot.burstsMax = math.huge -- a equipe que cobre fica e atira
	end
end

-- Supressão (D-90): sem alvo à vista, quem cobre o lance (ou a metralhadora) dá uma rajada na
-- última posição vista, se o raio até lá não para logo no próprio abrigo.
local function suppress(bot: Bot, model: Model, now: number): boolean
	local lk = bot.lastKnown
	local d = bot.diff
	if not lk or now - bot.lastKnownAt > d.suppressMaxAgeS or now < bot.nextSuppress then
		return false
	end
	if not (BotSquads.covering(bot) or bot.weapon.kind == "mg") then
		return false
	end
	if bot.firing or now < bot.reloadUntil or bot.mag <= 2 or bot.rays < 1 then
		return false
	end
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return false
	end
	local aim = lk + Vector3.new(bot.rng:range(-6, 6), 2, bot.rng:range(-6, 6))
	bot.rays -= 1
	local hit = workspace:Raycast(head.Position, aim - head.Position, coverParams)
	if hit and (hit.Position - head.Position).Magnitude < (aim - head.Position).Magnitude * 0.6 then
		return false -- o próprio abrigo tapa: não adianta
	end
	bot.nextSuppress = now + between(d.suppressS, bot.rng:next())
	BotLocomotion.face(bot, aim)
	if BotLocomotion.facingError(bot, aim) > math.rad(15) then
		return false
	end
	fireVolley(bot, nil, aim)
	return true
end

-- No abrigo: escondido na postura do lugar; de tempos em tempos espia (levanta ou sai de lado),
-- dá uma rajada e volta. Troca de abrigo depois de algumas rajadas, de 2 espiadas sem alvo ou se
-- o inimigo deu a volta. No lance de ataque (D-90), quem avança troca logo para o abrigo da frente.
local function fromCover(
	bot: Bot,
	model: Model,
	root: BasePart,
	now: number,
	c: Cover,
	target: Model?,
	targetD: number,
	threat: Vector3,
	pinned: boolean,
	underFire: boolean,
	retreating: boolean
)
	local d, style = bot.diff, bot.style
	if bot.mode == "move" or bot.mode == "advance" then
		if not goTo(bot, model, root, now, underFire, pinned, target, targetD) then
			return
		end
		bot.mode = "hide"
		bot.nextPeek = now + 0.3 + 0.4 * bot.rng:next() -- olha logo ao chegar
		bot.recheckAt = now + d.recheckS
	elseif bot.mode == "hold" then
		bot.mode, bot.peekUntil, bot.peekFired = "peek", now + d.peekMaxS, false
	end
	local hide = BotBrain.coverStance(c.kind, c.level, pinned, underFire, bot.open)
	local heldS = now - bot.contactAt
	local advancing = BotSquads.advancing(bot) and not retreating
	local hideMult = if BotSquads.covering(bot) then 0.6 else 1
	if bot.mode == "hide" then
		if now >= bot.recheckAt and bot.rays >= 1 then
			bot.recheckAt = now + d.recheckS
			if not stillCovers(bot, c, threat) then
				relocate(bot, now)
				return
			end
		end
		setStance(model, hide)
		BotLocomotion.go(bot, c.pos, hide, { direct = true, tolerance = 0.8 / M, face = threat })
		if bot.mag < bot.weapon.magazine * 0.3 and now >= bot.reloadUntil and not bot.firing then
			startReload(bot, now) -- recarrega escondido
		end
		if target then
			-- visto do esconderijo: atrás de dique o agachado já vê por cima (atira dali);
			-- atrás de abrigo médio ou alto, o inimigo deu a volta
			if
				not pinned
				and not BotBrain.holdFire(style, targetD * M, underFire, heldS)
				and tryFire(bot, target, now, targetD)
			then
				bot.bursts += 1
				if c.level >= 2 then
					bot.exposed += 1
				end
			end
			if
				(bot.exposed >= 2 or bot.bursts >= bot.burstsMax or (advancing and bot.bursts >= 1)) and not bot.firing
			then
				relocate(bot, now)
			end
			return
		end
		if pinned or bot.firing or now < bot.reloadUntil then
			return
		end
		if advancing and bot.bursts >= 1 then
			relocate(bot, now) -- a minha equipe está no lance: abrigo da frente
			return
		end
		if now < bot.nextPeek then
			if suppress(bot, model, now) then
				bot.bursts += 1
			end
			return
		end
		if bot.bursts >= bot.burstsMax then
			relocate(bot, now)
			return
		end
		local peek, sidestep = BotBrain.peekStance(c.level, hide)
		if sidestep and c.side == 0 then
			-- abrigo cego (parede comprida): dali não dá para atirar
			bot.failedPeeks += 1
			bot.nextPeek = now + BotBrain.hideTime(d, style, bot.rng:next(), retreating) * hideMult
			if bot.failedPeeks >= 2 and not retreating then
				relocate(bot, now) -- nem o da emboscada fica: cego, nunca atiraria
			end
			return
		end
		bot.mode, bot.peekUntil, bot.peekFired = "peek", now + d.peekMaxS, false
		setStance(model, peek)
		local spot = if sidestep then c.pos + c.sideDir * c.side * (C.peekStepM / M) else c.pos
		BotLocomotion.go(
			bot,
			spot,
			if peek == "stand" then "ads" else peek,
			{ direct = true, face = threat, tolerance = 0.5 / M }
		)
		return
	end
	-- espiando
	if pinned and not bot.firing then
		bot.mode = "hide"
		bot.nextPeek = now + BotBrain.hideTime(d, style, bot.rng:next(), retreating) * hideMult
		setStance(model, hide)
		BotLocomotion.go(bot, c.pos, hide, { direct = true, face = threat })
		return
	end
	if target and not bot.firing then
		if BotBrain.holdFire(style, targetD * M, underFire, heldS) then
			bot.peekUntil = math.max(bot.peekUntil, now + 1) -- emboscada: de olho, sem atirar
			BotLocomotion.face(bot, (target :: Model):GetPivot().Position)
		elseif tryFire(bot, target, now, targetD) then
			bot.peekFired = true
			bot.bursts += 1
		end
	end
	if bot.firing then
		return
	end
	if bot.peekFired or now >= bot.peekUntil then
		bot.failedPeeks = if bot.peekFired then 0 else bot.failedPeeks + 1
		bot.mode = "hide"
		bot.nextPeek = now + BotBrain.hideTime(d, style, bot.rng:next(), retreating) * hideMult
		setStance(model, hide)
		BotLocomotion.go(bot, c.pos, hide, { direct = true, face = threat })
		-- 2 espiadas sem alvo: procura outro ângulo (quem guarda o ponto forte fica)
		if bot.failedPeeks >= 2 and not retreating and bot.coverSector == nil then
			relocate(bot, now)
		end
	end
end

local function combat(
	bot: Bot,
	model: Model,
	hum: Humanoid,
	root: BasePart,
	now: number,
	target: Model?,
	targetD: number,
	threat: Vector3,
	pinned: boolean,
	underFire: boolean,
	retreating: boolean
)
	local d = bot.diff
	-- VC ferido com boca de túnel perto: some lá dentro (D-90)
	if retreating and bot.faction == "VC" and not bot.tunnel and BotTunnels.vanish(bot, root, threat) then
		return
	end
	if target and targetD * M < d.closeM then
		-- inimigo colado: luta onde está, ajoelhado
		setStance(model, "crouch")
		BotLocomotion.stop(bot, (target :: Model):GetPivot().Position)
		tryFire(bot, target, now, targetD)
		return
	end
	maybeGrenade(bot, model, root, now, pinned, target)
	if not bot.cover and now >= bot.searchAt and bot.rays >= C.searchCost then
		bot.searchAt = now + d.searchEveryS
		local found = searchCover(bot, hum, root, threat, retreating)
		if found then
			bot.coverSector = nil
			chooseCover(bot, root, found, now, retreating)
		end
	end
	local c = bot.cover
	if c then
		fromCover(bot, model, root, now, c, target, targetD, threat, pinned, underFire, retreating)
		return
	end
	-- sem abrigo por perto: postura pelo lugar (deita no arrozal e no capim sob fogo; longe e
	-- parado, deita para firmar o tiro) e atira daqui
	local st = BotBrain.coverStance("none", 0, pinned, underFire, bot.open)
	if target and not pinned and targetD * M > 150 then
		st = "prone"
	end
	setStance(model, st)
	BotLocomotion.stop(bot, threat)
	if target and not pinned then
		tryFire(bot, target, now, targetD)
	elseif not target then
		suppress(bot, model, now)
	end
end

-- Perto do objetivo: o lugar de cada um (arco de defesa ou dentro do raio no ataque), abrigo virado
-- para o inimigo e espera de olho (emboscada). Longe: segue o squad. Logo depois de um combate,
-- fica um tempo no abrigo (o VC, bem mais).
local function calm(bot: Bot, model: Model, hum: Humanoid, root: BasePart, head: BasePart, now: number, pinned: boolean)
	if BotVehicles.calm(bot, model, root) then
		return
	end
	-- EUA: acham e granadeiam as bocas de túnel (não para o resto)
	BotTunnels.suspect(bot, model, root, head, now)
	local point, sector = objectivePos(bot.faction)
	if not (point and sector) then
		BotLocomotion.stop(bot, nil)
		return
	end
	if pinned then
		-- tiro ou explosão sem origem conhecida: abaixa onde está
		setStance(model, BotBrain.coverStance("none", 0, true, true, bot.open))
		BotLocomotion.stop(bot, nil)
		return
	end
	-- 2026-11-12: parado demais sem contato e fora do lugar no objetivo: larga o abrigo e segue
	if BotBrain.idleExpired(now - (bot.stillSince or now), false, BotSquads.phase(bot) == "deploy") then
		bot.cover, bot.coverSector, bot.resumeAt, bot.stillSince = nil, nil, 0, nil
	end
	local c = bot.cover
	if c and now < bot.resumeAt and bot.coverSector ~= sector then
		setStance(model, BotBrain.coverStance(c.kind, c.level, false, false, bot.open))
		BotLocomotion.go(bot, c.pos, "walk", { direct = true })
		return
	end
	-- 2026-11-12: bot no squad de um jogador segue o líder humano (ou a marca dele)
	if BotEscolta.calm(bot, model, root, now) then
		return
	end
	-- em marcha com o squad
	if BotSquads.phase(bot) == "move" then
		bot.coverSector = nil
		bot.cover = nil
		local sq = bot.squad
		local squadGoal: Vector3 = if sq and sq.goal then sq.goal else point
		local threatNear = bot.lastKnown ~= nil
			and now - bot.lastKnownAt < 30
			and flat(root.Position, bot.lastKnown :: Vector3) * M < MOVE.sprintThreatM
		if BotSquads.isLeader(bot) then
			if BotTunnels.considerMove(bot, root, squadGoal, true) then
				return
			end
			setStance(model, "stand")
			BotSquads.lead(bot, root, now, threatNear)
			return
		end
		if BotTunnels.considerMove(bot, root, squadGoal, false) then
			return
		end
		if BotSquads.follow(bot, root, now) then
			setStance(model, "stand")
			return
		end
		-- sem líder por perto: vai sozinho, pelo caminho
		setStance(model, "stand")
		BotLocomotion.goFar(bot, squadGoal, if threatNear then "walk" else "jog", { tolerance = 6 / M })
		return
	end
	-- perto do objetivo: o lugar de cada um. VC defendendo An Cường: os dois últimos do squad
	-- esperam no túnel, na boca virada para o inimigo (emboscada)
	local sqd = bot.squad
	if
		bot.faction == "VC"
		and sqd
		and not sqd.attack
		and bot.slot >= 4
		and BotTunnels.defend(bot, root, point, BotSquads.threatYaw(bot.faction, point))
	then
		return
	end
	if bot.goalSector ~= sector or not bot.goal then
		bot.goal = BotSquads.deployGoal(bot, point)
		bot.goalSector = sector
	end
	local g = bot.goal :: Vector3
	if c and bot.coverSector == sector then
		if bot.mode == "move" and not goTo(bot, model, root, now, false, false, nil, 0) then
			return
		end
		-- de olho no abrigo da emboscada (postura de espiar)
		bot.mode = "hold"
		local hide = BotBrain.coverStance(c.kind, c.level, false, false, bot.open)
		local peek, sidestep = BotBrain.peekStance(c.level, hide)
		setStance(model, peek)
		local spot = if sidestep and c.side ~= 0 then c.pos + c.sideDir * c.side * (C.peekStepM / M) else c.pos
		BotLocomotion.go(
			bot,
			spot,
			if peek == "stand" then "walk" else peek,
			{ direct = true, face = enemyHQ(bot, root), tolerance = 0.6 / M }
		)
		return
	end
	bot.cover = nil
	if flat(root.Position, g) <= C.holdRadiusM / M then
		if now >= bot.searchAt and bot.rays >= C.searchCost then
			bot.searchAt = now + 5
			local found = searchCover(bot, hum, root, enemyHQ(bot, root), false)
			-- só abrigo dentro do raio de captura do ponto forte
			if found and flat(found.pos, point) < MapConfig.CaptureRadiusStuds - 5 / M then
				bot.coverSector = sector
				chooseCover(bot, root, found, now, false)
				return
			end
		end
		setStance(model, "crouch")
		BotLocomotion.stop(bot, enemyHQ(bot, root))
		return
	end
	-- vai para o seu lugar (cauteloso: o inimigo pode estar perto)
	bot.mode = "advance"
	local dist = flat(root.Position, g) * M
	setStance(model, "stand")
	BotLocomotion.go(bot, g, if dist > 40 then "jog" else "walk", { tolerance = 2 / M })
	if BotLocomotion.status(bot) == "failed" then
		-- caminho não fecha: muda o lugar
		bot.goal = g + Vector3.new(bot.rng:range(-40, 40), 0, bot.rng:range(-40, 40))
	end
end

local function enterCombat(bot: Bot, now: number)
	bot.inCombat = true
	bot.contactAt = now
	if bot.mode == "advance" then
		bot.cover = nil
	end
	bot.bursts, bot.failedPeeks, bot.exposed = 0, 0, 0
	bot.burstsMax = BotBrain.burstsPerCover(bot.diff, bot.style, bot.rng:next(), bot.wounded)
end

local function leaveCombat(bot: Bot, now: number)
	bot.inCombat = false
	bot.resumeAt = now + between(bot.style.resumeS, bot.rng:next())
	bot.avoid = nil
	-- abrigo perto do objetivo vira o da emboscada
	local c, g = bot.cover, bot.goal
	if c and g and flat(c.pos, g) < (C.holdRadiusM + bot.diff.coverSearchM) / M then
		bot.coverSector = bot.goalSector
		bot.mode = "hold"
	elseif c then
		bot.mode = "hide"
	end
end

-- Texto do gancho de depuração (Studio): o que o bot está fazendo
local MODE_PT: { [string]: string } = {
	advance = "avançando",
	move = "indo ao abrigo",
	hide = "abrigado",
	peek = "espiando",
	hold = "de olho",
}
local function debugLabel(bot: Bot, model: Model)
	local bb = model:FindFirstChild("BotDebug") :: BillboardGui?
	if not debugOn then
		if bb then
			bb:Destroy()
		end
		return
	end
	if not bb then
		local g = Instance.new("BillboardGui")
		g.Name = "BotDebug"
		g.Size = UDim2.fromOffset(220, 40)
		g.StudsOffset = Vector3.new(0, 4.5, 0)
		g.AlwaysOnTop = true
		g.MaxDistance = 250
		local t = Instance.new("TextLabel")
		t.Name = "T"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextColor3 = if bot.faction == "US" then Color3.fromRGB(170, 200, 255) else Color3.fromRGB(255, 180, 160)
		t.TextStrokeTransparency = 0.3
		t.TextScaled = true
		t.Parent = g
		g.Parent = model
		bb = g
	end
	local t = (bb :: BillboardGui):FindFirstChild("T") :: TextLabel?
	if not t then
		return
	end
	local who = if BotSquads.isLeader(bot) then "líder" else string.format("homem %d", bot.slot)
	local veh = BotVehicles.debugText(bot)
	local tun = if bot.tunnel then string.format("túnel %s", tostring(bot.tunnel.phase)) else nil
	local st = BotLocomotion.status(bot)
	local loco = bot.loco
	t.Text = string.format(
		"%s · %s · %s\n%s · %.1f m/s · %s",
		who,
		if bot.inCombat then "combate" else "calmo",
		veh or tun or (MODE_PT[bot.mode] or bot.mode),
		if loco then tostring(loco.gait) else "-",
		BotLocomotion.speed(bot),
		st
	)
end

local function think(bot: Bot, now: number)
	local model = bot.model
	if not model then
		if not bot.removed and not bot.spawning and now >= bot.readyAt then
			-- numa tarefa própria: criar o modelo espera (avatar, arte) e não pode parar os outros
			bot.spawning = true
			task.spawn(function()
				pcall(spawnModel, bot)
				bot.spawning = false
			end)
		end
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?
	if not (hum and root and head) or hum.Health <= 0 or model:GetAttribute("Downed") then
		return
	end
	debugLabel(bot, model)
	local d = bot.diff
	local dt = math.clamp(now - bot.lastThink, 0, 1)
	bot.lastThink = now
	bot.rays = BotBrain.budgetStep(bot.rays, dt, d.rayRate, d.rayCap)
	bot.supp = BotBrain.suppressionDecay(d, bot.supp, dt)
	if hum.Health < bot.lastHealth - 0.5 then
		bot.supp = BotBrain.suppressionAdd(d, bot.supp, 0, true) -- levou tiro ou estilhaço
	end
	bot.lastHealth = hum.Health
	-- no túnel (VC) ou sentado num veículo: os módulos cuidam
	if bot.tunnel then
		BotTunnels.think(bot, model, hum, root, now)
		if bot.tunnel and bot.tunnel.phase ~= "approach" then
			return
		end
	end
	if hum.SeatPart then
		if not BotVehicles.gunner(bot, model, now) then
			BotVehicles.seatedThink(bot, model, now)
		end
		return
	end
	local pinned, underFire = BotBrain.pinned(d, bot.supp), BotBrain.underFire(d, bot.supp)
	-- percepção: notar leva tempo; a reação conta a partir de quando nota
	local seen, seenD = perceive(bot, model, root, head.Position)
	local target = notice(bot, root, seen, seenD, dt, now)
	local targetD = if target then seenD else 0
	if target then
		local tr = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if tr then
			bot.lastKnown = tr.Position
			BotSquads.callout(bot, tr.Position, now)
		end
		bot.lastKnownAt = now
		if bot.target ~= target then
			bot.reactAt = now + BotBrain.reactionTime(d, bot.rng:next(), bot.supp, bot.inCombat)
			bot.trackSince = now
		end
	end
	bot.target = target
	-- ameaça: o inimigo visto, o lembrado, de onde veio o tiro ou o contato avisado pelo squad
	local threat: Vector3? = nil
	local seenAge, shotAge = now - bot.lastKnownAt, now - bot.threatAt
	if bot.lastKnown and seenAge < bot.style.forgetS then
		threat = bot.lastKnown
	end
	if bot.threatPos and shotAge < bot.style.forgetS and (threat == nil or shotAge < seenAge) then
		threat = bot.threatPos
	end
	if not threat then
		threat = BotSquads.sharedThreat(bot, now)
	end
	-- tiro ouvido perto (até 60 m): é ameaça; mais longe só vira para lá
	local hp = bot.heardPos
	if hp and now - bot.heardAt < 3 then
		if not threat and flat(root.Position, hp) * M <= 60 then
			threat = hp
		elseif not target then
			BotLocomotion.face(bot, hp)
		end
	end
	-- ferido: recua para abrigo (troca abrigo baixo por um melhor) e fica mais tempo escondido
	local ms = MedicalService.get(model)
	local retreating = BotBrain.shouldRetreat(d, if ms then ms.health else hum.Health)
	if retreating and not bot.wounded then
		bot.wounded = true
		bot.burstsMax = math.huge
		local c = bot.cover
		if bot.inCombat and c and c.level < 2 then
			relocate(bot, now)
		end
	end
	-- 2026-11-12 ("faça eles avançarem mais em vez de ficarem parados"): quem ataca, sem alvo à vista
	-- e sem fogo em cima há PRESS.afterS, volta a andar com o squad (os lances vêm do BotSquads); o
	-- defensor fica no ponto e só reage
	local sq = bot.squad
	local sinceSeen = now - math.max(bot.lastKnownAt, bot.threatAt)
	if
		threat
		and BotBrain.shouldPress(sq ~= nil and sq.attack == true, target ~= nil, underFire, retreating, sinceSeen)
	then
		threat = nil
		if bot.inCombat then
			leaveCombat(bot, now)
		end
		bot.resumeAt = 0
		if bot.coverSector == nil then
			bot.cover = nil
		end
	end
	-- parado fora de combate: conta o tempo (BotBrain.idleExpired, no calm)
	if bot.inCombat or root.AssemblyLinearVelocity.Magnitude * M > 0.3 then
		bot.stillSince = nil
	elseif not bot.stillSince then
		bot.stillSince = now
	end
	if threat and not (bot.tunnel and bot.tunnel.phase == "approach") then
		if not bot.inCombat then
			enterCombat(bot, now)
		end
		combat(bot, model, hum, root, now, target, targetD, threat, pinned, underFire, retreating)
	elseif not bot.tunnel then
		if bot.inCombat then
			leaveCombat(bot, now)
		end
		calm(bot, model, hum, root, head, now, pinned)
	end
end

-- Toda bala validada (de jogador, bot ou veículo) passa aqui: bot inimigo perto da linha leva
-- supressão e fica sabendo de onde veio o tiro. A bala é tratada como reta (a queda até 300 m é
-- menor que o raio de 3 m); se parou antes, longe dele, em algo que segura bala, não conta.
-- D-90: quem ouve o tiro (até hearShotM) vira para o rumo; o clarão ajuda a notar quem atira.
local function onShot(shooter: Model, origin: Vector3, dir: Vector3)
	if dir.Magnitude < 1e-6 then
		return
	end
	local u = dir.Unit
	local se = Combatants.get(shooter)
	local sf = if se then se.faction else nil
	local now = os.clock()
	lastFire[shooter] = now
	for _, b in bots do
		local m = b.model
		local head = if m then m:FindFirstChild("Head") :: BasePart? else nil
		if m and head and m ~= shooter and b.faction ~= sf then
			local p = head.Position
			if (p - origin).Magnitude * M <= b.diff.hearShotM then
				b.heardPos, b.heardAt = origin, now
			end
			local miss, along = BotBrain.passBy(origin.X, origin.Y, origin.Z, u.X, u.Y, u.Z, p.X, p.Y, p.Z)
			local near = b.diff.nearMissM / M
			if along > 0 and along < MAX_SHOT and miss < near then
				shotParams.FilterDescendantsInstances = { shooter, m }
				local r = workspace:Raycast(origin, u * along, shotParams)
				local mat = if r then r.Instance:GetAttribute("Material") else nil
				local reached = r == nil
					or (r.Position - p).Magnitude < near * 1.5
					or (type(mat) == "string" and PASS_THROUGH[mat] == true)
				if reached then
					b.supp = BotBrain.suppressionAdd(b.diff, b.supp, miss * M, false)
					b.threatPos, b.threatAt = origin, now
				end
			end
		end
	end
end

local function rebalance()
	local fill = BotService.fill()
	for _, faction in { "US", "VC" } do
		local h = humans(faction)
		local want = math.clamp(fill - h, 0, Roles.TEAM_MAX - h)
		local mine = {}
		for _, b in bots do
			if b.faction == faction and not b.removed then
				table.insert(mine, b)
			end
		end
		for _ = #mine + 1, want do
			newBot(faction)
		end
		for i = want + 1, #mine do
			local b = mine[i]
			b.removed = true
			BotEscolta.forget(b)
			BotSquads.remove(b)
			BotLocomotion.detach(b)
			BotTunnels.reset(b)
			if b.model then
				b.model:Destroy()
				b.model = nil
			end
		end
	end
	for i = #bots, 1, -1 do
		if bots[i].removed then
			table.remove(bots, i)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Ganchos do Studio (workspace:SetAttribute("VT65DevBots", ...)): cenas para ver no Studio
---------------------------------------------------------------------------------------------
local function aliveBots(faction: string): { Bot }
	local out: { Bot } = {}
	for _, b in bots do
		local m = b.model
		local hum = m and m:FindFirstChildOfClass("Humanoid")
		if b.faction == faction and m and hum and hum.Health > 0 and not b.crew and not b.tunnel then
			table.insert(out, b)
		end
	end
	return out
end

local function place(b: Bot, pos: Vector3, faceAt: Vector3)
	local m = b.model
	if not m then
		return
	end
	local y = SpawnService.groundY(pos.X, pos.Z)
	local yaw = BotMove.yawTo(faceAt.X - pos.X, faceAt.Z - pos.Z)
	m:PivotTo(CFrame.new(pos.X, y + 4, pos.Z) * CFrame.Angles(0, yaw, 0))
	BotLocomotion.stop(b, nil)
	BotLocomotion.setYaw(b, yaw)
end

local function sceneVehicle(spec: string)
	local veh: Model? = nil
	for _, v in VehicleService.vehicles() do
		if v:GetAttribute("Spec") == spec then
			veh = v
			break
		end
	end
	if not veh then
		warn(string.format("[VT65 TESTE] VT65DevBots: nenhum %s inteiro", spec))
		return
	end
	local c = BotVehicles.force(bots, veh :: Model, 3)
	if c then
		print(
			string.format(
				"[VT65 TESTE] VT65DevBots: tripulação de bots no %s indo para o S3 (veja o motorista no assento, a rota pela mata e a parada atrás de cobertura)",
				spec
			)
		)
	else
		warn("[VT65 TESTE] VT65DevBots: sem bots dos EUA para tripular")
	end
end

local function sceneTunnel()
	local vc = aliveBots("VC")
	if #vc == 0 then
		warn("[VT65 TESTE] VT65DevBots: nenhum bot do VC em campo")
		return
	end
	local list = TunnelService.entrances()
	local e1, e3 = nil :: TunnelService.Entrance?, nil :: TunnelService.Entrance?
	for _, e in list do
		if e.id == "E1" then
			e1 = e
		elseif e.id == "E3" then
			e3 = e
		end
	end
	if not (e1 and e3) or TunnelService.destroyed.E1 or TunnelService.destroyed.E3 then
		warn("[VT65 TESTE] VT65DevBots: E1 ou E3 destruída")
		return
	end
	local a = e1 :: TunnelService.Entrance
	local entry = Vector3.new(a.x, 0, a.z)
	for i = 1, math.min(4, #vc) do
		local b = vc[i]
		b.order = "tunel"
		local ang = i * 1.6
		place(b, entry + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (6 + i * 2) / M, entry)
		BotTunnels.ambush(b, "E1", "E3")
	end
	print(
		string.format(
			"[VT65 TESTE] VT65DevBots: %d bots do VC entrando na E1 para emboscar na E3 (saem quando os EUA chegam a 45 m ou em 150 s)",
			math.min(4, #vc)
		)
	)
end

local function sceneCover()
	local us, vc = aliveBots("US"), aliveBots("VC")
	local sp = MatchService.points[3]
	if #us < 3 or not sp then
		warn("[VT65 TESTE] VT65DevBots: precisa de 3 bots dos EUA em campo e do S3 sorteado")
		return
	end
	local point = Vector3.new(sp.x, 0, sp.z)
	-- VC defendendo o S3; squad dos EUA a ~220 m a leste, atacando pela cobertura
	for i = 1, math.min(4, #vc) do
		local b = vc[i]
		b.order = "cobertura"
		local ang = i * 1.3
		place(b, point + Vector3.new(math.cos(ang), 0, math.sin(ang)) * 25 / M, point + Vector3.new(400, 0, 0))
		b.goal, b.goalSector = nil, nil
	end
	local start = point + Vector3.new(220 / M, 0, 0)
	for i = 1, math.min(6, #us) do
		local b = us[i]
		b.order = "cobertura"
		place(b, start + Vector3.new(i * 2 / M, 0, (i % 2) * 3 / M), point)
	end
	print(
		"[VT65 TESTE] VT65DevBots: squad dos EUA a 220 m do S3 atacando pela cobertura (coluna ou cunha, dique e sebe, lances e granada)"
	)
end

local function devBots()
	local v = workspace:GetAttribute("VT65DevBots")
	if type(v) ~= "string" then
		return
	end
	workspace:SetAttribute("VT65DevBots", nil)
	if v == "m48" then
		sceneVehicle("m48a3")
	elseif v == "ontos" then
		sceneVehicle("ontos")
	elseif v == "lvtp" then
		sceneVehicle("lvtp5")
	elseif v == "tunel" then
		sceneTunnel()
	elseif v == "cobertura" then
		sceneCover()
	elseif v == "depurar" then
		debugOn = not debugOn
		print(
			string.format("[VT65 TESTE] VT65DevBots: rótulos dos bots %s", if debugOn then "ligados" else "desligados")
		)
	elseif v == "parar" then
		for _, b in bots do
			b.order = nil
		end
		for _, c in BotVehicles.list() do
			c.forceSector = nil
		end
		print("[VT65 TESTE] VT65DevBots: cenas desfeitas")
	elseif v == "squad" or v == "squad0" or v == "squad1" then
		-- 2026-11-12: bots no squad do jogador (BotEscolta): "squad" mostra; "squad0"/"squad1" desliga/liga
		BotEscolta.dev(v)
	else
		warn(string.format("[VT65 TESTE] VT65DevBots: cena desconhecida %s", v))
	end
end

function BotService.start()
	BotTypes.hooks.setStance = setStance
	BotTypes.hooks.throwGrenade = botThrow
	BotTypes.hooks.objective = objectivePos
	BotTypes.hooks.bots = function(): { Bot }
		return bots
	end
	BotWorld.start()
	BotLocomotion.start()
	BotTunnels.startLoop()
	BotEscolta.start(function(): { Bot }
		return bots
	end)
	-- Supressão: ouve cada tiro validado. CombatService.fire é chamada pela tabela (jogadores, bots,
	-- veículos), então envolvê-la aqui pega todos sem mexer no CombatService. O tiro sai primeiro;
	-- erro na conta dos bots não derruba o tiro.
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
		local ok, err = pcall(function(): any
			onShot(shooter, origin, dir)
			return nil
		end)
		if not ok then
			warn("[VT65] bots: supressão falhou:", err)
		end
	end
	refreshFilters()
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevBots"):Connect(function()
			task.spawn(devBots)
		end)
	end
	task.spawn(function()
		while true do
			if ReplicatedStorage:GetAttribute("TerrainReady") ~= false then
				rebalance()
			end
			task.wait(5)
		end
	end)
	task.spawn(function()
		local i = 0
		local every = math.max(1, math.floor(C.thinkS / 0.1 + 0.5))
		local lastWarn = -math.huge
		while true do
			task.wait(0.1)
			if i % 10 == 0 then
				refreshFilters()
			end
			local now = os.clock()
			if i % 5 == 0 then
				local ok, err = pcall(function(): any
					BotSquads.tick(now, objectivePos)
					return nil
				end)
				if not ok and now - lastWarn > 5 then
					lastWarn = now
					warn("[VT65] bots: squad falhou:", err)
				end
			end
			if i % 20 == 0 then
				local ok, err = pcall(function(): any
					BotVehicles.assign(bots, nil)
					return nil
				end)
				if not ok and now - lastWarn > 5 then
					lastWarn = now
					warn("[VT65] bots: tripulação falhou:", err)
				end
			end
			local okD, errD = pcall(function(): any
				BotVehicles.drive(now, 0.1)
				return nil
			end)
			if not okD and now - lastWarn > 5 then
				lastWarn = now
				warn("[VT65] bots: direção falhou:", errD)
			end
			-- cada bot pensa a cada C.thinkS (escalonado)
			for k, b in bots do
				if (k + i) % every == 0 then
					local ok, err = pcall(function(): any
						think(b, now)
						return nil
					end)
					if not ok and now - lastWarn > 5 then
						lastWarn = now
						warn("[VT65] bot falhou ao pensar:", err)
					end
				end
			end
			i += 1
		end
	end)
end

return BotService
