--!strict
-- Animais da vila (Parte 11): move os búfalos e galinhas que o AssetLoader colocou
-- (workspace.Map.Art.Animals) e os assusta com tiros e explosões. A lógica fica em Shared/Animals.
-- Quem está fugindo anda a 10 Hz; quem pasta, a 1 Hz (custo de replicação baixo).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animals = require(ReplicatedStorage.Shared.Animals)
local Rng = require(ReplicatedStorage.Shared.Rng)

local AnimalService = {}
local M = 0.28
-- Frente de cada modelo PUBLICADO: no GLB o búfalo olha para +X e a galinha para +Z, mas o
-- importador do Roblox gira 180° em Y; no Studio (2026-11-10) a cabeça do búfalo está em -X e a da
-- galinha em -Z. lookAt aponta -Z; estes ângulos levam a frente do modelo ao rumo (antes: +90° e
-- 180°, os dois andariam de ré).
local FACE_YAW: { [string]: number } = { water_buffalo = -math.pi / 2, chicken = 0 }

type Live = { a: Animals.Animal, model: Model, lift: number, lastSlow: number }
local live: { Live } = {}
local rng = Rng.new(19650818 + 7)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local function groundY(x: number, z: number): number?
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return hit and hit.Position.Y
end

local function place(l: Live)
	local x, z = l.a.x / M, l.a.z / M
	local y = groundY(x, z)
	if not y then
		return
	end
	local pos = Vector3.new(x, y + l.lift, z)
	local dir = Vector3.new(l.a.dirX, 0, l.a.dirZ)
	local cf = if dir.Magnitude > 0.1 then CFrame.lookAt(pos, pos + dir) else CFrame.new(pos)
	l.model:PivotTo(cf * CFrame.Angles(0, FACE_YAW[l.a.species] or 0, 0))
end

-- Barulho em pos (studs). Chamado pelo CombatService (tiro) e pelo ExplosionService.
function AnimalService.noise(pos: Vector3, explosion: boolean)
	local now = os.clock()
	for _, l in live do
		Animals.noise(l.a, pos.X * M, pos.Z * M, explosion, now)
	end
end

local function adopt(folder: Instance)
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and Animals.SPECIES[m.Name] then
			local p = m:GetPivot().Position
			local y = groundY(p.X, p.Z) or p.Y
			table.insert(live, { a = Animals.new(m.Name, p.X * M, p.Z * M), model = m, lift = p.Y - y, lastSlow = 0 })
		end
	end
	print(string.format("[VT65] animais da vila: %d", #live))
end

function AnimalService.start()
	params.FilterDescendantsInstances = { workspace.Terrain }
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 60)
		local art = map and map:WaitForChild("Art", 600)
		local folder = art and art:WaitForChild("Animals", 600)
		if not folder then
			return -- sem modelos publicados (AssetIds = 0): nada a mover
		end
		adopt(folder)
		while true do
			local dt = task.wait(0.1)
			local now = os.clock()
			for _, l in live do
				if l.model.Parent == nil then
					continue
				end
				if Animals.fleeing(l.a, now) then
					Animals.step(l.a, dt, now, rng:next())
					place(l)
				elseif now - l.lastSlow >= 1 then
					Animals.step(l.a, now - math.max(l.lastSlow, now - 1), now, rng:next())
					l.lastSlow = now
					place(l)
				end
			end
		end
	end)
end

return AnimalService
