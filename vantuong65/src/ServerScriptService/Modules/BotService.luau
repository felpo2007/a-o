--!strict
-- Bots que completam o servidor (Parte 11) e permitem testar o 15v15 da F2 com poucos humanos.
-- Saem quando entra gente. Usam as MESMAS regras: tiro simulado no servidor, dano, ferimentos,
-- spawn por ondas. Visão bloqueada por sebes e casas (não enxergam através da vegetação).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Smoke = require(ReplicatedStorage.Shared.Smoke)
local Roles = require(ReplicatedStorage.Shared.Roles)
local SpawnRules = require(ReplicatedStorage.Shared.SpawnRules)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local AssetLoader = require(script.Parent.AssetLoader)
local Characters = require(script.Parent.Characters)
local CombatService = require(script.Parent.CombatService)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local SpawnService = require(script.Parent.SpawnService)

local BotService = {}
local M = 0.28
local SENSE = BotBrain.C.senseRangeM / M

type Bot = {
	id: number,
	faction: string,
	role: string,
	weapon: Weapons.Weapon,
	rng: Rng.Rng,
	model: Model?,
	mag: number,
	nextShot: number,
	burstLeft: number,
	target: Model?,
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
	model.Name = string.format("Bot_%s_%02d", bot.faction, bot.id)
	model:SetAttribute("Bot", true)
	model:SetAttribute("Role", bot.role)
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
	bot.model = model
	bot.mag = bot.weapon.magazine
	bot.target, bot.goal, bot.goalSector = nil, nil, nil
	bot.lastProgress = os.clock()
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
	local bot: Bot = {
		id = nextId,
		faction = faction,
		role = role,
		weapon = wp,
		rng = Rng.new(nextId * 7919 + os.time()),
		model = nil,
		mag = wp.magazine,
		nextShot = 0,
		burstLeft = 0,
		target = nil,
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

local function perturb(dir: Vector3, sigma: number, rng: Rng.Rng): Vector3
	local up = if math.abs(dir.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local r = dir:Cross(up).Unit
	local q = r:Cross(dir).Unit
	return (dir + r * rng:gauss() * sigma + q * rng:gauss() * sigma).Unit
end

local function think(bot: Bot, now: number)
	local model = bot.model
	if not model then
		if not bot.removed and now >= bot.readyAt then
			spawnModel(bot)
		end
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?
	if not (hum and root and head) or hum.Health <= 0 or model:GetAttribute("Downed") then
		return
	end
	-- percepção: inimigo ativo mais próximo com linha de visada
	local best: Model? = nil
	local bestD = SENSE
	for _, e in Combatants.list() do
		if e.faction ~= bot.faction and Combatants.active(e) then
			local r = Combatants.root(e)
			if r then
				local d = (r.Position - root.Position).Magnitude
				if d < bestD and visible(head.Position, e.model, model) then
					best, bestD = e.model, d
				end
			end
		end
	end
	if best then
		if bot.target ~= best then
			bot.target = best
			bot.nextShot = now + BotBrain.reaction(bot.rng:next())
			bot.burstLeft = 0
		end
		hum:MoveTo(root.Position) -- para para atirar
		if now >= bot.nextShot then
			if bot.mag <= 0 then
				bot.mag = bot.weapon.magazine
				bot.nextShot = now + (if bot.weapon.kind == "mg" then 7 else 3)
				return
			end
			local aimPart = (best:FindFirstChild("UpperTorso") or best:FindFirstChild("Head")) :: BasePart?
			if aimPart then
				local dir = (aimPart.Position - head.Position).Unit
				local moving = root.AssemblyLinearVelocity.Magnitude > 2
				dir = perturb(dir, BotBrain.aimSigma(bestD * M, moving, 0.5), bot.rng)
				CombatService.fire(model, bot.weapon.id, head.Position, dir, bot.rng:nextU32(), nil)
				bot.mag -= 1
				if bot.burstLeft <= 0 then
					bot.burstLeft = BotBrain.burst(bot.weapon.kind, bot.rng:next())
				end
				bot.burstLeft -= 1
				bot.nextShot = now
					+ BotBrain.shotDelay(bot.weapon.kind, bot.weapon.rpm, bot.burstLeft > 0, bot.rng:next())
			end
		end
		return
	end
	bot.target = nil
	-- movimento: vai para o ponto forte do setor-alvo, com espalhamento
	local goal, sector = objectivePos(bot.faction)
	if not goal then
		return
	end
	if bot.goalSector ~= sector or not bot.goal then
		local spread = BotBrain.C.objectiveSpreadM / M
		bot.goal = goal + Vector3.new(bot.rng:range(-spread, spread), 0, bot.rng:range(-spread, spread))
		bot.goalSector = sector
	end
	local g = bot.goal :: Vector3
	hum:MoveTo(Vector3.new(g.X, root.Position.Y, g.Z))
	-- preso: sem avanço por 3 s -> pula e muda o desvio
	if bot.lastPos and (root.Position - bot.lastPos).Magnitude > 2 then
		bot.lastProgress = now
		bot.lastPos = root.Position
	elseif not bot.lastPos then
		bot.lastPos = root.Position
	elseif now - bot.lastProgress > BotBrain.C.stuckSeconds then
		hum.Jump = true
		bot.goal = g + Vector3.new(bot.rng:range(-40, 40), 0, bot.rng:range(-40, 40))
		bot.lastProgress = now
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
		while true do
			task.wait(0.1)
			local now = os.clock()
			-- cada bot pensa a cada ~0,5 s (escalonado)
			for k, b in bots do
				if (k + i) % 5 == 0 then
					think(b, now)
				end
			end
			i += 1
		end
	end)
end

return BotService
