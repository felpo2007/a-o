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
-- As decisões e os números ficam no BotBrain (puro, testado no Lune); aqui, os raios e o Humanoid.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Rng = require(ReplicatedStorage.Shared.Rng)
local Smoke = require(ReplicatedStorage.Shared.Smoke)
local Roles = require(ReplicatedStorage.Shared.Roles)
local SpawnRules = require(ReplicatedStorage.Shared.SpawnRules)
local Weather = require(ReplicatedStorage.Shared.Weather)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local AssetLoader = require(script.Parent.AssetLoader)
local Characters = require(script.Parent.Characters)
local CombatService = require(script.Parent.CombatService)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local MedicalService = require(script.Parent.MedicalService)
local PostureService = require(script.Parent.PostureService)
local SpawnService = require(script.Parent.SpawnService)

local BotService = {}
local M = 0.28
local C = BotBrain.C
local SENSE = C.senseRangeM / M
local PROBE = C.probeM
local MAX_SHOT = 1000 / M -- bala não voa mais que isto (Ballistics: 2,5 s)
local PASS_THROUGH = { Bamboo = true, Thatch = true } :: { [string]: boolean } -- CombatService.PASS

type Cover = {
	pos: Vector3, -- onde ficar (Y = chão)
	level: number, -- 1 baixo, 2 médio, 3 alto (BotBrain.coverLevel)
	kind: string, -- BotBrain.coverKind
	side: number, -- abrigo alto: lado livre para atirar (-1 ou 1); 0 = cego ou não precisa
	sideDir: Vector3, -- perpendicular à direção do inimigo
}

type Bot = {
	id: number,
	faction: string,
	role: string,
	weapon: Weapons.Weapon,
	rng: Rng.Rng,
	diff: BotBrain.Difficulty,
	style: BotBrain.Style,
	model: Model?,
	spawning: boolean,
	life: number, -- conta as vidas: tarefa atrasada da vida anterior não mexe na nova
	-- tiro
	mag: number,
	reloadUntil: number,
	nextVolley: number,
	firing: boolean,
	target: Model?,
	reactAt: number,
	-- memória do inimigo
	lastKnown: Vector3?, -- onde o viu por último
	lastKnownAt: number,
	threatPos: Vector3?, -- de onde veio o último tiro que passou perto
	threatAt: number,
	inCombat: boolean,
	contactAt: number,
	-- corpo
	supp: number, -- supressão 0..1
	lastHealth: number,
	lastThink: number,
	rays: number, -- orçamento de raios de abrigo
	open: boolean, -- campo aberto (arrozal, capim): deita sob fogo
	wounded: boolean,
	-- abrigo
	cover: Cover?,
	coverSector: number?, -- abrigo de emboscada deste setor-alvo
	mode: string, -- "advance" | "move" | "hide" | "peek" | "hold"
	moveUntil: number,
	nextPeek: number,
	peekUntil: number,
	peekFired: boolean,
	bursts: number,
	burstsMax: number,
	failedPeeks: number,
	exposed: number,
	recheckAt: number,
	searchAt: number,
	avoid: Vector3?, -- abrigo que acabou de largar
	resumeAt: number,
	grenades: number,
	nextGrenade: number,
	-- objetivo
	goal: Vector3?,
	goalSector: number?,
	lastPos: Vector3?,
	lastProgress: number,
	readyAt: number,
	removed: boolean,
}

local bots: { Bot } = {}
local folder = Instance.new("Folder")
folder.Name = "Combatants"
folder.Parent = workspace
local nextId = 0

function BotService.fill(): number
	local v = ReplicatedStorage:GetAttribute("BotFill")
	if type(v) == "number" then
		return v
	end
	return if RunService:IsStudio() then 15 else 10
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

-- zera o estado de uma vida nova (chamado no spawn)
local function resetLife(bot: Bot)
	local now = os.clock()
	bot.life += 1
	bot.mag = bot.weapon.magazine
	bot.reloadUntil, bot.nextVolley, bot.firing = 0, 0, false
	bot.target, bot.reactAt = nil, 0
	bot.lastKnown, bot.lastKnownAt, bot.threatPos, bot.threatAt = nil, -math.huge, nil, -math.huge
	bot.inCombat, bot.contactAt = false, 0
	bot.supp, bot.lastHealth, bot.lastThink = 0, -math.huge, now -- -inf: 1º pensamento só anota a vida
	bot.rays, bot.open, bot.wounded = bot.diff.rayCap, false, false
	bot.cover, bot.coverSector, bot.mode, bot.moveUntil = nil, nil, "advance", 0
	bot.nextPeek, bot.peekUntil, bot.peekFired = 0, 0, false
	bot.bursts, bot.burstsMax, bot.failedPeeks, bot.exposed = 0, 2, 0, 0
	bot.recheckAt, bot.searchAt, bot.avoid, bot.resumeAt = 0, 0, nil, 0
	bot.grenades, bot.nextGrenade = 0, 0
	bot.goal, bot.goalSector, bot.lastPos, bot.lastProgress = nil, nil, nil, now
end

local function spawnModel(bot: Bot)
	local pts = SpawnService.freePoints(bot.faction)
	if #pts == 0 then
		return
	end
	local goal = objectivePos(bot.faction)
	table.sort(pts, function(a, b)
		if not goal then
			return a.kind == "hq"
		end
		local da = (Vector3.new(a.x, 0, a.z) - goal).Magnitude
		local db = (Vector3.new(b.x, 0, b.z) - goal).Magnitude
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
	resetLife(bot)
	-- Died antes de qualquer espera: register() já o torna alvo, e attachWeapon/dress carregam
	-- arte (LoadAsset). Morto nessa janela, o bot ficava caído para sempre, sem largar a arma e
	-- sem voltar (autoteste no Studio, 2026-11-10: "nenhuma arma caiu em 3 s").
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			local t = os.clock()
			bot.readyAt = SpawnRules.readyAt(t, 0, MatchService.waveEpoch)
			-- a arma do bot cai com o que tinha no carregador (Parte 11: pegar a arma do inimigo)
			local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
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
	model:PivotTo(CFrame.new(pt.x + jx, y + 5, pt.z + jz))
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
end

local function newBot(faction: string): Bot
	nextId += 1
	local idx = 0
	for _, b in bots do
		if b.faction == faction then
			idx += 1
		end
	end
	local role = if idx % 6 == 5 then "machine_gunner" else "rifleman"
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
		lastKnown = nil,
		lastKnownAt = -math.huge,
		threatPos = nil,
		threatAt = -math.huge,
		inCombat = false,
		contactAt = 0,
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
		lastPos = nil,
		lastProgress = 0,
		readyAt = 0, -- primeiro spawn imediato
		removed = false,
	}
	table.insert(bots, bot)
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

local function refreshFilters()
	local map = workspace:FindFirstChild("Map")
	local water = if map then map:FindFirstChild("PaddyWater") else nil
	local ex: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	for _, name in { "DroppedWeapons", "Smoke" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ex, f)
		end
	end
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
local function searchCover(bot: Bot, hum: Humanoid, root: BasePart, threat: Vector3, retreating: boolean): Cover?
	raysUsed = 0
	local here = root.Position
	local foot = footY(root, hum)
	local base = Vector3.new(here.X, foot, here.Z)
	local surface = surfaceAt(here)
	local goal = bot.goal
	local avoid = bot.avoid
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
					local s = BotBrain.coverScore(bot.style, candidate(p, kind, info.level, false), retreating)
					table.insert(found, { pos = p, score = s })
				end
			end
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
		local s = BotBrain.coverScore(bot.style, candidate(p, kind, level, level >= 3 and side == 0), retreating)
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
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { selfModel }
	local r = workspace:Raycast(from, head.Position - from, params)
	if not (r ~= nil and r.Instance:IsDescendantOf(target)) then
		return false
	end
	-- fumaça tapa a visão (não as balas)
	local h = head.Position
	return not Smoke.blocks(from.X, from.Y, from.Z, h.X, h.Y, h.Z, Smoke.clouds(workspace:FindFirstChild("Smoke")))
end

local function stanceOf(model: Model): string
	if model:GetAttribute("Prone") then
		return "prone"
	elseif model:GetAttribute("Crouched") then
		return "crouch"
	end
	return "stand"
end

type Seen = { m: Model, d: number }

-- Inimigo ativo mais próximo com linha de visada. Só os C.maxLosChecks mais próximos gastam raio
-- (o alvo atual sempre); deitado e agachado são vistos de mais perto (BotBrain.spotFactor).
local function perceive(bot: Bot, model: Model, root: BasePart, head: BasePart): (Model?, number)
	-- chuva forte: enxergam até metade da distância (Weather)
	local rain = ReplicatedStorage:GetAttribute("Rain")
	local range = SENSE * Weather.sightFactor(if type(rain) == "number" then rain else 0)
	local cands: { Seen } = {}
	for _, e in Combatants.list() do
		if e.faction ~= bot.faction and Combatants.active(e) then
			local r = Combatants.root(e)
			if r then
				local dd = (r.Position - root.Position).Magnitude
				if dd < range * BotBrain.spotFactor(bot.diff, stanceOf(e.model), e.model == bot.target) then
					table.insert(cands, { m = e.model, d = dd })
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
			if visible(head.Position, c.m, model) then
				return c.m, c.d
			end
		end
	end
	return nil, 0
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

local function setStance(model: Model, stance: string)
	PostureService.setStance(model, stance)
end

-- corrida até o abrigo sob fogo (só em pé; PostureService desliga ao abaixar)
local function sprint(model: Model, on: boolean)
	local want = on and not model:GetAttribute("Crouched") and not model:GetAttribute("Prone")
	if (model:GetAttribute("Sprinting") == true) ~= want then
		model:SetAttribute("Sprinting", want)
		MedicalService.apply(model)
	end
end

local function face(root: BasePart, p: Vector3)
	local at = Vector3.new(p.X, root.Position.Y, p.Z)
	if (at - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, at)
	end
end

-- alvo abaixado mostra pouco: mira na cabeça; em pé, no peito
local function aimPart(target: Model): BasePart?
	if target:GetAttribute("Prone") or target:GetAttribute("Crouched") then
		return (target:FindFirstChild("Head") or target:FindFirstChild("UpperTorso")) :: BasePart?
	end
	return (target:FindFirstChild("UpperTorso") or target:FindFirstChild("Head")) :: BasePart?
end

local function startReload(bot: Bot, now: number)
	bot.reloadUntil = now + (C.reloadS[bot.weapon.kind] or 3)
	bot.mag = bot.weapon.magazine
end

-- Rajada curta (BotBrain.volleySize) numa tarefa própria, na cadência certa. Cada tiro recalcula o
-- erro (distância, supressão, postura, braço ferido e recuo). Depois, pausa até a próxima.
local function fireVolley(bot: Bot, target: Model)
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
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local first = aimPart(target)
		if root and first then
			face(root, first.Position)
		end
		for i = 1, n do
			local hum = model:FindFirstChildOfClass("Humanoid")
			local head = model:FindFirstChild("Head") :: BasePart?
			local aim = aimPart(target)
			local te = Combatants.get(target)
			if
				bot.life ~= life
				or bot.model ~= model
				or not (hum and head and aim and te)
				or hum.Health <= 0
				or model:GetAttribute("Downed")
				or not Combatants.active(te)
				or bot.mag <= 0
			then
				break
			end
			local to = aim.Position - head.Position
			local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local sigma = BotBrain.aimError(d, to.Magnitude * M, {
				moving = r ~= nil and r.AssemblyLinearVelocity.Magnitude > 2,
				suppression = bot.supp,
				stance = stanceOf(model),
				armHurt = model:GetAttribute("ArmImpaired") == true,
				shot = i,
				kind = kind,
			})
			CombatService.fire(
				model,
				bot.weapon.id,
				head.Position,
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

-- atira se já reagiu, se a pausa acabou e se tem munição (senão, recarrega)
local function tryFire(bot: Bot, target: Model, now: number): boolean
	if bot.firing or now < bot.reactAt or now < bot.nextVolley or now < bot.reloadUntil then
		return false
	end
	if bot.mag <= 0 then
		startReload(bot, now)
		return false
	end
	fireVolley(bot, target)
	return bot.firing
end

local function friendlyNear(bot: Bot, p: Vector3): boolean
	local r = bot.diff.grenade.friendlyClearM / M
	for _, e in Combatants.list() do
		if e.faction == bot.faction and e.model ~= bot.model and Combatants.active(e) then
			local er = Combatants.root(e)
			if er and (er.Position - p).Magnitude < r then
				return true
			end
		end
	end
	return false
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

-- Granada no inimigo que se escondeu a 15-35 m (BotBrain.shouldThrow). Joga numa tarefa própria
-- (a função pode esperar a animação); se não sair, devolve a vez.
local function maybeGrenade(bot: Bot, model: Model, root: BasePart, now: number, pinned: boolean)
	local lk = bot.lastKnown
	if not lk then
		return
	end
	local G = bot.diff.grenade
	local distM = flat(root.Position, lk) * M
	if distM < G.minM or distM > G.maxM or now < bot.nextGrenade or bot.grenades >= G.perLife then
		return -- atalho barato antes de olhar os companheiros
	end
	local go = BotBrain.shouldThrow(bot.diff, {
		distM = distM,
		los = false,
		thrown = bot.grenades,
		now = now,
		nextAt = bot.nextGrenade,
		knownAgeS = now - bot.lastKnownAt,
		friendlyNear = friendlyNear(bot, lk),
		pinned = pinned,
		roll = bot.rng:next(),
	})
	if not go then
		return
	end
	bot.grenades += 1
	bot.nextGrenade = now + G.cooldownS
	if model:GetAttribute("Prone") then
		setStance(model, "crouch")
	end
	local life = bot.life
	task.spawn(function()
		if not throwGrenade(model, bot.faction, lk) and bot.life == life then
			bot.grenades -= 1
			bot.nextGrenade = os.clock() + G.retryS
		end
	end)
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

-- Vai até o abrigo (corre sob fogo). Preso pelo fogo longe dele, abaixa e espera aliviar.
-- Devolve true ao chegar.
local function goTo(
	bot: Bot,
	model: Model,
	hum: Humanoid,
	root: BasePart,
	now: number,
	underFire: boolean,
	pinned: boolean
): boolean
	local c = bot.cover
	if not c then
		return false
	end
	local dist = flat(root.Position, c.pos)
	if dist <= C.arriveM / M then
		sprint(model, false)
		return true
	end
	if pinned and dist > 2 / M then
		sprint(model, false)
		setStance(model, BotBrain.coverStance("none", 0, true, true, bot.open))
		hum:MoveTo(root.Position)
		bot.moveUntil += C.thinkS
		return false
	end
	setStance(model, "stand")
	sprint(model, underFire)
	hum:MoveTo(c.pos)
	if now > bot.moveUntil then
		-- não chegou (caminho fechado, água funda): larga este abrigo
		sprint(model, false)
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
end

-- No abrigo: escondido na postura do lugar; de tempos em tempos espia (levanta ou sai de lado),
-- dá uma rajada e volta. Troca de abrigo depois de algumas rajadas, de 2 espiadas sem alvo ou se
-- o inimigo deu a volta.
local function fromCover(
	bot: Bot,
	model: Model,
	hum: Humanoid,
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
		if not goTo(bot, model, hum, root, now, underFire, pinned) then
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
	if bot.mode == "hide" then
		if now >= bot.recheckAt and bot.rays >= 1 then
			bot.recheckAt = now + d.recheckS
			if not stillCovers(bot, c, threat) then
				relocate(bot, now)
				return
			end
		end
		sprint(model, false)
		setStance(model, hide)
		hum:MoveTo(c.pos)
		if bot.mag < bot.weapon.magazine * 0.3 and now >= bot.reloadUntil and not bot.firing then
			startReload(bot, now) -- recarrega escondido
		end
		if target then
			-- visto do esconderijo: atrás de dique o agachado já vê por cima (atira dali);
			-- atrás de abrigo médio ou alto, o inimigo deu a volta
			if
				not pinned
				and not BotBrain.holdFire(style, targetD * M, underFire, heldS)
				and tryFire(bot, target, now)
			then
				bot.bursts += 1
				if c.level >= 2 then
					bot.exposed += 1
				end
			end
			if (bot.exposed >= 2 or bot.bursts >= bot.burstsMax) and not bot.firing then
				relocate(bot, now)
			end
			return
		end
		if pinned or bot.firing or now < bot.nextPeek or now < bot.reloadUntil then
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
			bot.nextPeek = now + BotBrain.hideTime(d, style, bot.rng:next(), retreating)
			if bot.failedPeeks >= 2 and not retreating then
				relocate(bot, now) -- nem o da emboscada fica: cego, nunca atiraria
			end
			return
		end
		bot.mode, bot.peekUntil, bot.peekFired = "peek", now + d.peekMaxS, false
		setStance(model, peek)
		hum:MoveTo(if sidestep then c.pos + c.sideDir * c.side * (C.peekStepM / M) else c.pos)
		return
	end
	-- espiando
	if pinned and not bot.firing then
		bot.mode = "hide"
		bot.nextPeek = now + BotBrain.hideTime(d, style, bot.rng:next(), retreating)
		setStance(model, hide)
		hum:MoveTo(c.pos)
		return
	end
	if target and not bot.firing then
		if BotBrain.holdFire(style, targetD * M, underFire, heldS) then
			bot.peekUntil = math.max(bot.peekUntil, now + 1) -- emboscada: de olho, sem atirar
		elseif tryFire(bot, target, now) then
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
		bot.nextPeek = now + BotBrain.hideTime(d, style, bot.rng:next(), retreating)
		setStance(model, hide)
		hum:MoveTo(c.pos)
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
	if target and targetD * M < d.closeM then
		-- inimigo colado: luta onde está, ajoelhado
		sprint(model, false)
		setStance(model, "crouch")
		hum:MoveTo(root.Position)
		tryFire(bot, target, now)
		return
	end
	if not target then
		maybeGrenade(bot, model, root, now, pinned)
	end
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
		fromCover(bot, model, hum, root, now, c, target, targetD, threat, pinned, underFire, retreating)
		return
	end
	-- sem abrigo por perto: postura pelo lugar (deita no arrozal e no capim sob fogo) e atira daqui
	sprint(model, false)
	setStance(model, BotBrain.coverStance("none", 0, pinned, underFire, bot.open))
	hum:MoveTo(root.Position)
	if target and not pinned then
		tryFire(bot, target, now)
	end
end

-- Sem inimigo: vai para o ponto forte do setor-alvo; lá, procura abrigo virado para o inimigo e
-- espera de olho (emboscada). Logo depois de um combate, fica um tempo no abrigo (o VC, bem mais).
local function calm(bot: Bot, model: Model, hum: Humanoid, root: BasePart, now: number, pinned: boolean)
	local point, sector = objectivePos(bot.faction)
	if not (point and sector) then
		return
	end
	if bot.goalSector ~= sector or not bot.goal then
		local spread = C.objectiveSpreadM / M
		bot.goal = point + Vector3.new(bot.rng:range(-spread, spread), 0, bot.rng:range(-spread, spread))
		bot.goalSector = sector
	end
	sprint(model, false)
	if pinned then
		-- tiro ou explosão sem origem conhecida: abaixa onde está
		setStance(model, BotBrain.coverStance("none", 0, true, true, bot.open))
		hum:MoveTo(root.Position)
		return
	end
	local c = bot.cover
	if c and bot.coverSector == sector then
		if bot.mode == "move" and not goTo(bot, model, hum, root, now, false, false) then
			return
		end
		-- de olho no abrigo da emboscada (postura de espiar)
		bot.mode = "hold"
		local hide = BotBrain.coverStance(c.kind, c.level, false, false, bot.open)
		local peek, sidestep = BotBrain.peekStance(c.level, hide)
		setStance(model, peek)
		hum:MoveTo(if sidestep and c.side ~= 0 then c.pos + c.sideDir * c.side * (C.peekStepM / M) else c.pos)
		return
	end
	if c and now < bot.resumeAt then
		setStance(model, BotBrain.coverStance(c.kind, c.level, false, false, bot.open))
		hum:MoveTo(c.pos)
		return
	end
	bot.cover = nil
	local g = bot.goal :: Vector3
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
		hum:MoveTo(root.Position)
		return
	end
	-- avança para o ponto forte, com espalhamento
	bot.mode = "advance"
	setStance(model, "stand")
	hum:MoveTo(Vector3.new(g.X, root.Position.Y, g.Z))
	-- preso: sem avanço por 3 s -> pula e muda o desvio
	if bot.lastPos and (root.Position - bot.lastPos).Magnitude > 2 then
		bot.lastProgress = now
		bot.lastPos = root.Position
	elseif not bot.lastPos then
		bot.lastPos = root.Position
	elseif now - bot.lastProgress > C.stuckSeconds then
		hum.Jump = true
		bot.goal = g + Vector3.new(bot.rng:range(-40, 40), 0, bot.rng:range(-40, 40))
		bot.lastProgress = now
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
	local d = bot.diff
	local dt = math.clamp(now - bot.lastThink, 0, 1)
	bot.lastThink = now
	bot.rays = BotBrain.budgetStep(bot.rays, dt, d.rayRate, d.rayCap)
	bot.supp = BotBrain.suppressionDecay(d, bot.supp, dt)
	if hum.Health < bot.lastHealth - 0.5 then
		bot.supp = BotBrain.suppressionAdd(d, bot.supp, 0, true) -- levou tiro ou estilhaço
	end
	bot.lastHealth = hum.Health
	local pinned, underFire = BotBrain.pinned(d, bot.supp), BotBrain.underFire(d, bot.supp)
	-- percepção: reação conta a partir de quando o alvo aparece (de novo)
	local target, targetD = perceive(bot, model, root, head)
	if target then
		local tr = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if tr then
			bot.lastKnown = tr.Position
		end
		bot.lastKnownAt = now
		if bot.target ~= target then
			bot.reactAt = now + BotBrain.reactionTime(d, bot.rng:next(), bot.supp, bot.inCombat)
		end
	end
	bot.target = target
	-- ameaça: o inimigo visto, o lembrado ou de onde veio o tiro (o mais recente)
	local threat: Vector3? = nil
	local seenAge, shotAge = now - bot.lastKnownAt, now - bot.threatAt
	if bot.lastKnown and seenAge < bot.style.forgetS then
		threat = bot.lastKnown
	end
	if bot.threatPos and shotAge < bot.style.forgetS and (threat == nil or shotAge < seenAge) then
		threat = bot.threatPos
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
	if threat then
		if not bot.inCombat then
			enterCombat(bot, now)
		end
		combat(bot, model, hum, root, now, target, targetD, threat, pinned, underFire, retreating)
	else
		if bot.inCombat then
			leaveCombat(bot, now)
		end
		calm(bot, model, hum, root, now, pinned)
	end
end

-- Toda bala validada (de jogador, bot ou veículo) passa aqui: bot inimigo perto da linha leva
-- supressão e fica sabendo de onde veio o tiro. A bala é tratada como reta (a queda até 300 m é
-- menor que o raio de 3 m); se parou antes, longe dele, em algo que segura bala, não conta.
local function onShot(shooter: Model, origin: Vector3, dir: Vector3)
	if dir.Magnitude < 1e-6 then
		return
	end
	local u = dir.Unit
	local se = Combatants.get(shooter)
	local sf = if se then se.faction else nil
	local now = os.clock()
	for _, b in bots do
		local m = b.model
		local head = if m then m:FindFirstChild("Head") :: BasePart? else nil
		if m and head and m ~= shooter and b.faction ~= sf then
			local p = head.Position
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

function BotService.start()
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
