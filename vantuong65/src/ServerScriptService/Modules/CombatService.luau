--!strict
-- Validação de tiros no servidor (Parte 7): o cliente manda origem, direção, instante e semente;
-- o servidor confere arma, munição, cadência, origem e latência, refaz a MESMA simulação
-- determinística (Ballistics) com raycasts próprios e aplica o dano. Sem hitmarker.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local MedicalService = require(script.Parent.MedicalService)

local CombatService = {}
local M = 0.28
local MAX_LAG = 0.25 -- compensação de latência até 200 ms + folga (Parte 10.7)
local MAGS = { rifle = 6, mg = 2, pistol = 3, launcher = 6 } -- PLACEHOLDER de dotação
local RELOAD = { rifle = 3.0, mg = 7.0, pistol = 2.5, launcher = 3.0 } -- PLACEHOLDER (s)
-- materiais que a bala atravessa perdendo velocidade (fração mantida). PLACEHOLDER até a
-- tabela de penetração em cm por material (Parte 10.7).
local PASS = { Bamboo = 0.85, Thatch = 0.8 }

type Ammo = { weapon: string, mag: number, spare: number, lastShot: number, reloadUntil: number }
local ammo: { [Player]: Ammo } = {}

local function loadout(player: Player): { string }
	local s = player:GetAttribute("Loadout")
	return if type(s) == "string" then string.split(s, ",") else {}
end

local function resetAmmo(player: Player)
	local id = loadout(player)[1]
	local wp = id and Weapons.get(id)
	if not wp or not wp.enabled then
		ammo[player] = nil
		return
	end
	ammo[player] =
		{ weapon = wp.id, mag = wp.magazine, spare = (MAGS[wp.kind] or 3) - 1, lastShot = 0, reloadUntil = 0 }
	Net.event("Combat_Ammo"):FireClient(player, ammo[player])
end

local function zoneOf(part: Instance): string
	local n = part.Name
	if n == "Head" then
		return "head"
	elseif string.find(n, "Arm") or string.find(n, "Hand") then
		return "arm"
	elseif string.find(n, "Leg") or string.find(n, "Foot") then
		return "leg"
	end
	return "torso"
end

local function num(v: any): number?
	return if type(v) == "number" and v == v and math.abs(v) < 1e7 then v else nil
end

function CombatService.start()
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			resetAmmo(p)
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		ammo[p] = nil
	end)

	Net.event("Combat_Reload").OnServerEvent:Connect(function(player)
		local a = ammo[player]
		local wp = a and Weapons.get(a.weapon)
		if not (a and wp) or a.spare <= 0 or os.clock() < a.reloadUntil then
			return
		end
		a.reloadUntil = os.clock() + (RELOAD[wp.kind] or 3)
		task.delay(RELOAD[wp.kind] or 3, function()
			if ammo[player] == a then
				a.spare -= 1
				a.mag = wp.magazine
				Net.event("Combat_Ammo"):FireClient(player, a)
			end
		end)
	end)

	Net.event("Combat_Fire").OnServerEvent:Connect(function(player, shot)
		if type(shot) ~= "table" then
			return
		end
		local a = ammo[player]
		local char = player.Character
		local head = char and char:FindFirstChild("Head") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (a and head and hum) or hum.Health <= 0 or player:GetAttribute("Downed") then
			return
		end
		local wp = Weapons.get(a.weapon)
		local ox, oy, oz = num(shot.ox), num(shot.oy), num(shot.oz)
		local dx, dy, dz = num(shot.dx), num(shot.dy), num(shot.dz)
		local t, seed = num(shot.t), num(shot.seed)
		if not (wp and ox and oy and oz and dx and dy and dz and t and seed) then
			return
		end
		local now = workspace:GetServerTimeNow()
		local clock = os.clock()
		if a.mag <= 0 or clock < a.reloadUntil or math.abs(now - t) > MAX_LAG then
			return
		end
		if clock - a.lastShot < Weapons.minInterval(wp) * 0.85 then
			return -- cadência acima da arma
		end
		if (Vector3.new(ox, oy, oz) - head.Position).Magnitude > 8 then
			return -- origem longe da cabeça
		end
		a.lastShot = clock
		a.mag -= 1

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { char :: Model }
		params.FilterDescendantsInstances = ignore
		local speedFactor = 1
		local hit = Ballistics.trace({
			ox = ox * M,
			oy = oy * M,
			oz = oz * M,
			dx = dx,
			dy = dy,
			dz = dz,
			weaponId = wp.id,
			seed = seed,
		}, function(ax, ay, az, bx, by, bz)
			local from = Vector3.new(ax, ay, az) / M
			local delta = Vector3.new(bx - ax, by - ay, bz - az) / M
			for _ = 1, 4 do -- até 4 materiais atravessáveis por segmento
				local r = workspace:Raycast(from, delta, params)
				if not r then
					return nil
				end
				local mat = r.Instance:GetAttribute("Material")
				local keep = if type(mat) == "string" then PASS[mat] else nil
				if keep then
					speedFactor *= keep
					table.insert(ignore, r.Instance)
					params.FilterDescendantsInstances = ignore
				else
					local p = r.Position * M
					return { x = p.X, y = p.Y, z = p.Z, target = r.Instance }
				end
			end
			return nil
		end)
		-- traçante/efeito para os outros clientes (eles refazem a trajetória com a semente)
		for _, other in Players:GetPlayers() do
			if other ~= player then
				Net.unreliable("Combat_Tracer")
					:FireClient(other, { w = wp.id, ox = ox, oy = oy, oz = oz, dx = dx, dy = dy, dz = dz, seed = seed })
			end
		end
		if hit and hit.target then
			local model = (hit.target :: Instance):FindFirstAncestorOfClass("Model")
			local victim = if model then Players:GetPlayerFromCharacter(model) else nil
			if victim then
				local energy = hit.energy * speedFactor * speedFactor
				local roll = Rng.new(seed + 1):next()
				MedicalService.hit(victim, zoneOf(hit.target), energy, roll)
			end
		end
	end)
end

return CombatService
