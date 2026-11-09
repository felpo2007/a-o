--!strict
-- Ferimentos no servidor (Parte 10.2): aplica tiros, sangramento, curativos, torniquete,
-- tratamento do médico, reanimação e desistência. O cliente só recebe o próprio estado.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = require(ReplicatedStorage.Shared.Medical)
local Net = require(ReplicatedStorage.Shared.Net)
local Units = require(ReplicatedStorage.Shared.Units)

local MedicalService = {}
local states: { [Player]: Medical.State } = {}
local busy: { [Player]: number } = {} -- token da ação em andamento
local REACH = 3 / 0.28 -- 3 m

function MedicalService.get(player: Player): Medical.State?
	return states[player]
end

local function humanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function root(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function apply(player: Player)
	local s, hum = states[player], humanoid(player)
	if not (s and hum) then
		return
	end
	if s.dead then
		hum.Health = 0
		return
	end
	player:SetAttribute("Downed", s.downedAt ~= nil)
	if s.downedAt then
		hum.Health = 1
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	else
		hum.Health = math.clamp(s.health, 1, 100)
		hum.WalkSpeed = if s.legImpaired then Units.Speed.walk else Units.Speed.jog
		hum.JumpPower = if s.legImpaired then 0 else 30
	end
	player:SetAttribute("ArmImpaired", s.armImpaired)
	player:SetAttribute("LegImpaired", s.legImpaired)
	Net.event("Medical_State"):FireClient(player, {
		health = s.health,
		bleed = Medical.bleedRate(s),
		downedAt = s.downedAt,
		now = os.clock(),
		blurUntil = s.blurUntil,
		arm = s.armImpaired,
		leg = s.legImpaired,
		bandages = s.bandages,
		tourniquets = s.tourniquets,
	})
end

-- chamado pelo CombatService após validar o tiro
function MedicalService.hit(victim: Player, zone: string, energyJ: number, roll: number)
	local s = states[victim]
	if not s then
		return
	end
	busy[victim] = nil -- levar dano interrompe a ação
	Medical.applyHit(s, zone, energyJ, roll, os.clock())
	apply(victim)
end

local function still(player: Player): boolean
	local r = root(player)
	return r ~= nil and Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude < 1
end

-- executa uma ação com tempo; cancela se mexer, levar dano ou o alvo sair do alcance
local function timed(actor: Player, target: Player, seconds: number, fn: () -> boolean)
	local token = os.clock()
	busy[actor] = token
	actor:SetAttribute("ActionUntil", os.clock() + seconds)
	task.delay(seconds, function()
		actor:SetAttribute("ActionUntil", nil)
		if busy[actor] ~= token then
			return
		end
		busy[actor] = nil
		local ra, rt = root(actor), root(target)
		if not (ra and rt) or (ra.Position - rt.Position).Magnitude > REACH or not still(actor) then
			return
		end
		if fn() then
			apply(target)
			apply(actor)
		end
	end)
end

function MedicalService.start()
	local function onChar(player: Player)
		states[player] = Medical.new(player:GetAttribute("Role") == "medic")
		busy[player] = nil
		task.defer(apply, player)
	end
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			onChar(p)
		end)
	end)
	for _, p in Players:GetPlayers() do
		p.CharacterAdded:Connect(function()
			onChar(p)
		end)
	end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
		busy[p] = nil
	end)

	Net.event("Medical_Action").OnServerEvent:Connect(function(actor, req)
		if type(req) ~= "table" or type(req.op) ~= "string" then
			return
		end
		local mine = states[actor]
		if not mine or mine.dead then
			return
		end
		local target = actor
		if type(req.target) == "number" then
			target = Players:GetPlayerByUserId(req.target) or actor
		end
		local ts = states[target]
		if not ts or (target ~= actor and target:GetAttribute("Faction") ~= actor:GetAttribute("Faction")) then
			return
		end
		local C = Medical.C
		local isMedic = actor:GetAttribute("Role") == "medic"
		if req.op == "giveup" and target == actor and Medical.canGiveUp(mine, os.clock()) then
			mine.dead = true
			apply(actor)
		elseif mine.downedAt then
			return -- caído não faz nada além de desistir
		elseif req.op == "bandage" then
			timed(actor, target, if target == actor then C.bandageSelf else C.bandageOther, function()
				if mine.bandages <= 0 then
					return false
				end
				-- o curativo sai do estoque de quem aplica
				local stock = ts.bandages
				ts.bandages = 1
				local ok = Medical.bandage(ts)
				ts.bandages = stock
				if ok then
					mine.bandages -= 1
				end
				return ok
			end)
		elseif req.op == "tourniquet" and target == actor then
			timed(actor, actor, C.tourniquet, function()
				return Medical.tourniquet(mine)
			end)
		elseif req.op == "treat" and isMedic and target ~= actor then
			timed(actor, target, C.medicTreat, function()
				return Medical.treat(ts)
			end)
		elseif req.op == "revive" and isMedic and target ~= actor then
			timed(actor, target, C.reviveTime, function()
				return Medical.revive(ts, os.clock())
			end)
		end
	end)

	task.spawn(function()
		while true do
			local dt = 0.25
			task.wait(dt)
			local now = os.clock()
			for player, s in states do
				local ev = Medical.tick(s, dt, now)
				if ev or s.downedAt or Medical.bleedRate(s) > 0 then
					apply(player)
				end
			end
		end
	end)
end

return MedicalService
