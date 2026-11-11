--!strict
-- Ferimentos no servidor (Parte 10.2), para jogadores e bots (chave = modelo do personagem).
-- O cliente só recebe o próprio estado (sem barra de vida: efeitos no corpo).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = require(ReplicatedStorage.Shared.Medical)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Units = require(ReplicatedStorage.Shared.Units)
local Combatants = require(script.Parent.Combatants)

local MedicalService = {}
local states: { [Model]: Medical.State } = {}
local busy: { [Model]: number } = {}
local REACH = 3 / 0.28 -- 3 m

function MedicalService.get(model: Model): Medical.State?
	return states[model]
end

local function humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function root(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function apply(model: Model)
	local s, hum = states[model], humanoid(model)
	if not (s and hum) then
		return
	end
	local e = Combatants.get(model)
	local player = e and e.player
	if s.dead then
		hum.Health = 0
		return
	end
	model:SetAttribute("Downed", s.downedAt ~= nil)
	if s.downedAt then
		hum.Health = 1
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	else
		hum.Health = math.clamp(s.health, 1, 100)
		-- postura e corrida (PostureService): deitado rasteja, agachado anda devagar, correndo só
		-- de pé e sem perna ferida. Teto único em Shared/Movement.serverSpeed (o cliente nunca passa
		-- dele, teste "movimento"); o VC, mais leve, tem teto 12% maior (D-93).
		local stance = if model:GetAttribute("Prone")
			then "prone"
			elseif model:GetAttribute("Crouched") then "crouch"
			else "stand"
		local faction = model:GetAttribute("Faction")
		hum.WalkSpeed = Movement.serverSpeed(
			stance,
			model:GetAttribute("Sprinting") == true,
			s.legImpaired,
			false,
			if type(faction) == "string" then faction else nil
		) / Units.STUD_M
		hum.JumpPower = if s.legImpaired then 0 else 30
	end
	model:SetAttribute("ArmImpaired", s.armImpaired)
	model:SetAttribute("LegImpaired", s.legImpaired)
	if player then
		player:SetAttribute("Downed", s.downedAt ~= nil)
		player:SetAttribute("ArmImpaired", s.armImpaired)
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
end
MedicalService.apply = apply

-- Progressão (D-72): quem acertou quem e quando, para o abate e a assistência na morte, e o aviso
-- de cuidado com um companheiro. Ganchos postos pelo ProgressionService (sem dependência circular).
local attackers: { [Model]: { [Player]: number } } = {}
MedicalService.onCare = nil :: ((actor: Player, target: Model, op: string) -> ())?

-- jogadores que acertaram a vítima (instante do último acerto de cada um)
function MedicalService.attackers(victim: Model): { [Player]: number }
	return attackers[victim] or {}
end

-- chamado pelo CombatService após validar o tiro (by = quem atirou, se for jogador)
function MedicalService.hit(victim: Model, zone: string, energyJ: number, roll: number, by: Player?)
	local s = states[victim]
	if not s then
		return
	end
	if by and by.Character ~= victim then
		attackers[victim] = attackers[victim] or {}
		attackers[victim][by] = os.clock()
	end
	busy[victim] = nil -- levar dano interrompe a ação
	Medical.applyHit(s, zone, energyJ, roll, os.clock())
	apply(victim)
end

local function still(model: Model): boolean
	local r = root(model)
	return r ~= nil and Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude < 1
end

-- ação com tempo; cancela se mexer, levar dano ou o alvo sair do alcance
local function timed(actor: Model, target: Model, seconds: number, fn: () -> boolean, op: string?)
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
			local who = Players:GetPlayerFromCharacter(actor)
			if op and who and target ~= actor and MedicalService.onCare then
				MedicalService.onCare(who, target, op)
			end
		end
	end)
end

function MedicalService.start()
	Combatants.Added:Connect(function(e: Combatants.Entry)
		states[e.model] = Medical.new(Combatants.role(e) == "medic")
		local kb = e.player and e.player:GetAttribute("KitBandages")
		if type(kb) == "number" then
			-- médico mantém a dotação de médico se ela for maior; os outros levam o que escolheram
			local s = states[e.model]
			s.bandages = if Combatants.role(e) == "medic" then math.max(s.bandages, kb) else kb
		end
		-- equipamento liberado (D-72, ProgressionService.applyGear): curativos e torniquetes a mais
		if e.player then
			local s = states[e.model]
			local gb, gt = e.player:GetAttribute("GearBandages"), e.player:GetAttribute("GearTourniquets")
			s.bandages += if type(gb) == "number" then gb else 0
			s.tourniquets += if type(gt) == "number" then gt else 0
		end
		busy[e.model] = nil
		attackers[e.model] = nil
		e.model.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				states[e.model] = nil
				busy[e.model] = nil
				attackers[e.model] = nil
			end
		end)
		task.defer(apply, e.model)
	end)

	Net.event("Medical_Action").OnServerEvent:Connect(function(player, req)
		if type(req) ~= "table" or type(req.op) ~= "string" then
			return
		end
		local actor = player.Character
		local mine = actor and states[actor]
		if not (actor and mine) or mine.dead then
			return
		end
		local target: Model = actor
		if typeof(req.target) == "Instance" then
			local te = Combatants.get(req.target)
			if te then
				target = te.model
			end
		elseif type(req.target) == "number" then
			local tp = Players:GetPlayerByUserId(req.target)
			if tp and tp.Character then
				target = tp.Character
			end
		end
		local ts = states[target]
		if not ts or (target ~= actor and target:GetAttribute("Faction") ~= actor:GetAttribute("Faction")) then
			return
		end
		local C = Medical.C
		local isMedic = player:GetAttribute("Role") == "medic"
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
				local stock = ts.bandages
				ts.bandages = 1
				local ok = Medical.bandage(ts)
				ts.bandages = stock
				if ok then
					mine.bandages -= 1
				end
				return ok
			end, "bandage")
		elseif req.op == "tourniquet" and target == actor then
			timed(actor, actor, C.tourniquet, function()
				return Medical.tourniquet(mine)
			end)
		elseif req.op == "treat" and isMedic and target ~= actor then
			timed(actor, target, C.medicTreat, function()
				return Medical.treat(ts)
			end, "treat")
		elseif req.op == "revive" and isMedic and target ~= actor then
			timed(actor, target, C.reviveTime, function()
				return Medical.revive(ts, os.clock())
			end, "revive")
		end
	end)

	task.spawn(function()
		while true do
			local dt = 0.25
			task.wait(dt)
			local now = os.clock()
			for model, s in states do
				local ev = Medical.tick(s, dt, now)
				if ev or s.downedAt or Medical.bleedRate(s) > 0 then
					apply(model)
				end
			end
		end
	end)
end

return MedicalService
