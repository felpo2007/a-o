--!strict
-- Armadilhas VC (Parte 11): punji e granada com fio. Regras em Shared/Traps. A peça da armadilha é
-- invisível no servidor; o TrapController mostra a armadilha a quem é do lado dela ou a detectou.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Traps = require(ReplicatedStorage.Shared.Traps)
local Combatants = require(script.Parent.Combatants)
local ExplosionService = require(script.Parent.ExplosionService)
local MedicalService = require(script.Parent.MedicalService)

local TrapService = {}
local M = 0.28
local folder: Folder
-- inside: quem está em cima agora (o sorteio de disparo é UMA vez por pisada, não a cada tique)
type Live = { part: BasePart, kind: string, faction: string, armedAt: number, inside: { [Model]: boolean } }
local live: { Live } = {}
local rng = Random.new()

local function remove(t: Live)
	local i = table.find(live, t)
	if i then
		table.remove(live, i)
	end
	t.part:Destroy()
end

local function trigger(t: Live, victim: Model)
	local pos = t.part.Position
	if t.kind == "punji" then
		remove(t)
		MedicalService.hit(victim, "leg", Traps.PUNJI_ENERGY_J, rng:NextNumber())
	else
		remove(t)
		local fuse = Traps.KINDS.tripwire.fuseS
		task.delay(fuse, function()
			ExplosionService.detonate("grenade_vc", pos)
		end)
	end
end

-- Arma uma armadilha (chamado pela logística depois de validar papel, custo e limite).
function TrapService.place(kind: string, faction: string, pos: Vector3, yaw: number): Instance
	local def = Traps.KINDS[kind]
	local p = Instance.new("Part")
	p.Name = kind
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
	p.Transparency = 1 -- escondida; o cliente mostra a quem pode ver
	p.Size = if kind == "tripwire"
		then Vector3.new(3 / M, 0.05 / M, 0.05 / M)
		else Vector3.new(0.8 / M, 0.1 / M, 0.8 / M)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	p:SetAttribute("Trap", kind)
	p:SetAttribute("Faction", faction)
	p.Parent = folder
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Desarmar " .. (if def then def.name else kind)
	prompt.HoldDuration = Traps.DISARM_S
	prompt.MaxActivationDistance = 6
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false -- só depois de detectada
	prompt.Parent = p
	local t: Live = {
		part = p,
		kind = kind,
		faction = faction,
		armedAt = os.clock() + (if def then def.armDelayS else 3),
		inside = {},
	}
	table.insert(live, t)
	prompt.Triggered:Connect(function(player: Player)
		if
			p.Parent
			and Traps.canDisarm(
				player:GetAttribute("Role") :: string?,
				player:GetAttribute("Faction") :: string?,
				faction,
				p:GetAttribute("Detected") == true
			)
		then
			remove(t)
			Net.event("Logistics_State"):FireClient(player, { error = "Armadilha desarmada" })
		end
	end)
	return p
end

local function tick()
	local now = os.clock()
	for _, e in Combatants.list() do
		local root = Combatants.root(e)
		if not (root and Combatants.active(e)) then
			continue
		end
		local v = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude * M
		local role = Combatants.role(e)
		for i = #live, 1, -1 do
			local t = live[i]
			if not t.part.Parent then
				table.remove(live, i)
				continue
			end
			-- distância no plano até a armadilha (o fio é uma linha de 3 m)
			local rel = t.part.CFrame:PointToObjectSpace(root.Position)
			local along = if t.kind == "tripwire"
				then math.max(0, math.abs(rel.X) - t.part.Size.X / 2)
				else math.abs(rel.X)
			local d = math.sqrt(along * along + rel.Z * rel.Z) * M
			local detected = t.part:GetAttribute("Detected") == true
			if not detected and Traps.detects(role, e.faction, t.faction, d, v) then
				t.part:SetAttribute("Detected", true)
				local pr = t.part:FindFirstChildOfClass("ProximityPrompt")
				if pr then
					pr.Enabled = true
				end
				if e.player then
					Net.event("Logistics_State")
						:FireClient(e.player, { error = "Armadilha à vista: " .. Traps.KINDS[t.kind].name })
				end
				detected = true
			end
			local def = Traps.KINDS[t.kind]
			if d > def.radiusM then
				t.inside[e.model] = nil
			elseif not t.inside[e.model] and Traps.canTrigger(t.faction, e.faction, t.armedAt, now) then
				t.inside[e.model] = true -- pisou agora: um sorteio só
				if rng:NextNumber() < Traps.triggerChance(math.max(v, 0.2), detected) then
					trigger(t, e.model)
				end
			end
		end
	end
end

function TrapService.start()
	folder = Instance.new("Folder")
	folder.Name = "Traps"
	folder.Parent = workspace
	task.spawn(function()
		while true do
			task.wait(0.2)
			tick()
		end
	end)
end

return TrapService
