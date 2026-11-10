--!strict
-- Explosões no servidor (F4): ferimentos por distância, postura e cobertura (Shared/Explosive),
-- dano a veículos, cratera no terreno com orçamento por minuto e efeito para os clientes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Explosive = require(ReplicatedStorage.Shared.Explosive)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Combatants = require(script.Parent.Combatants)
local MedicalService = require(script.Parent.MedicalService)

local ExplosionService = {}
local M = 0.28
local budget = Explosive.newBudget(20)
local rng = Rng.new(651818)

-- gancho para veículos (VehicleService registra; evita dependência circular)
ExplosionService.onVehicles = nil :: ((pos: Vector3, id: string) -> ())?

local function covered(from: Vector3, model: Model, target: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { model }
	local fx = workspace:FindFirstChild("Effects")
	if fx then
		table.insert(ignore, fx)
	end
	params.FilterDescendantsInstances = ignore
	local dir = target - from
	local hit = workspace:Raycast(from, dir, params)
	return hit ~= nil and (hit.Position - from).Magnitude < dir.Magnitude - 0.5
end

local ZONES = { "torso", "torso", "arm", "leg", "leg", "head" }

function ExplosionService.detonate(id: string, pos: Vector3)
	local t = Explosive.TYPES[id]
	if not t then
		return
	end
	Net.unreliable("Fire_Impact"):FireAllClients({ id = id, x = pos.X, y = pos.Y, z = pos.Z })
	local origin = pos + Vector3.new(0, 1, 0)
	for _, e in Combatants.list() do
		local root = Combatants.root(e)
		if root then
			local dM = (root.Position - pos).Magnitude * M
			if dM <= t.casualtyM then
				local exposure = if e.model:GetAttribute("Crouched") then Explosive.CROUCH else 1
				if covered(origin, e.model, root.Position) then
					exposure *= Explosive.COVERED
				end
				local result, energy = Explosive.effect(id, dM, exposure, rng:next())
				if result == "lethal" then
					MedicalService.hit(e.model, "torso", energy, rng:next())
				elseif result == "wound" then
					local zone = ZONES[1 + math.floor(rng:next() * #ZONES)]
					MedicalService.hit(e.model, zone, energy, rng:next())
				end
			end
		end
	end
	if ExplosionService.onVehicles then
		ExplosionService.onVehicles(pos, id)
	end
	if t.craterM > 0 and Explosive.allowCrater(budget, os.clock()) then
		local terrain = workspace.Terrain
		pcall(function()
			terrain:FillBall(pos - Vector3.new(0, t.craterM * 0.4 / M, 0), t.craterM / M, Enum.Material.Air)
		end)
	end
end

return ExplosionService
