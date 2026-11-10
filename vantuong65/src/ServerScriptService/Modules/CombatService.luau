--!strict
-- Validação de tiros no servidor (Parte 7): o cliente manda origem, direção, instante e semente;
-- o servidor confere arma, munição, cadência, origem e latência, refaz a MESMA simulação
-- determinística (Ballistics) com raycasts próprios e aplica o dano. Sem hitmarker.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Net = require(ReplicatedStorage.Shared.Net)
local Pickup = require(ReplicatedStorage.Shared.Pickup)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Combatants = require(script.Parent.Combatants)
local MedicalService = require(script.Parent.MedicalService)
local AnimalService = require(script.Parent.AnimalService)
local TrainingService = require(script.Parent.TrainingService)

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
	-- equipamento por peso (Kit_Set): carregadores escolhidos; senão a dotação padrão
	local km = player:GetAttribute("KitMags")
	local mags = if type(km) == "number" then km else (MAGS[wp.kind] or 3)
	ammo[player] = { weapon = wp.id, mag = wp.magazine, spare = mags - 1, lastShot = 0, reloadUntil = 0 }
	player:SetAttribute("CarriedWeapon", nil)
	Net.event("Combat_Ammo"):FireClient(player, ammo[player])
end

-- ===== arma caída (Parte 11): pegar a arma do inimigo só com a munição dela =====
local pickups = Instance.new("Folder")
pickups.Name = "DroppedWeapons"
pickups.Parent = workspace

local spawnPickup: (pos: Vector3, a: Pickup.Ammo) -> ()
spawnPickup = function(pos: Vector3, a: Pickup.Ammo)
	local wp = Weapons.get(a.weapon)
	if not wp then
		return
	end
	local p = Instance.new("Part")
	p.Name = a.weapon
	p.Size = Vector3.new(1.0 / M, 0.08 / M, 0.25 / M) -- volume de fuzil deitado no chão
	p.Color = Color3.fromRGB(70, 60, 45)
	p.Material = Enum.Material.Wood
	p.CanCollide = false
	p.Anchored = true
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(pos + Vector3.new(0, 10, 0), Vector3.new(0, -60, 0), params)
	p.CFrame = CFrame.new((if hit then hit.Position else pos) + Vector3.new(0, p.Size.Y / 2, 0))
		* CFrame.Angles(0, math.random() * 2 * math.pi, 0)
	p.Parent = pickups
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pegar " .. wp.name
	prompt.ObjectText = string.format("%d cartucho(s) no carregador", a.mag)
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	prompt.Triggered:Connect(function(player: Player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (char and hum) or hum.Health <= 0 or char:GetAttribute("Downed") or p.Parent ~= pickups then
			return
		end
		p:Destroy()
		local cur = ammo[player]
		local new, dropped =
			Pickup.swap(if cur then { weapon = cur.weapon, mag = cur.mag, spare = cur.spare } else nil, a)
		ammo[player] = { weapon = new.weapon, mag = new.mag, spare = new.spare, lastShot = 0, reloadUntil = 0 }
		player:SetAttribute("CarriedWeapon", new.weapon)
		Net.event("Combat_Ammo"):FireClient(player, ammo[player])
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if dropped and root then
			spawnPickup(root.Position + root.CFrame.RightVector * 2, dropped)
		end
	end)
	task.delay(Pickup.TTL_S, function()
		p:Destroy()
	end)
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

-- Simula o tiro no servidor e aplica o dano. `shooter` é o modelo do personagem (jogador ou bot).
function CombatService.fire(
	shooter: Model,
	weaponId: string,
	origin: Vector3,
	dir: Vector3,
	seed: number,
	exceptPlayer: Player?
)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { shooter }
	params.FilterDescendantsInstances = ignore
	local speedFactor = 1
	local hit = Ballistics.trace({
		ox = origin.X * M,
		oy = origin.Y * M,
		oz = origin.Z * M,
		dx = dir.X,
		dy = dir.Y,
		dz = dir.Z,
		weaponId = weaponId,
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
	AnimalService.noise(origin, false) -- búfalos e galinhas fogem do tiro (pista de detecção)
	-- traçante, som e impacto para os outros clientes (eles refazem a trajetória com a semente)
	local payload = {
		w = weaponId,
		ox = origin.X,
		oy = origin.Y,
		oz = origin.Z,
		dx = dir.X,
		dy = dir.Y,
		dz = dir.Z,
		seed = seed,
	}
	for _, other in Players:GetPlayers() do
		if other ~= exceptPlayer then
			Net.unreliable("Combat_Tracer"):FireClient(other, payload)
		end
	end
	if hit and hit.target then
		local t = hit.target :: Instance
		if t:IsA("BasePart") and t:GetAttribute("RangeTarget") ~= nil then
			TrainingService.rangeHit(shooter, t, Vector3.new(hit.x, hit.y, hit.z) / M)
			return
		end
		TrainingService.nearMiss(shooter, Vector3.new(hit.x, hit.y, hit.z) / M, t)
		local model = (hit.target :: Instance):FindFirstAncestorOfClass("Model")
		local victim = Combatants.get(model)
		if victim then
			local energy = hit.energy * speedFactor * speedFactor
			local roll = Rng.new(seed + 1):next()
			MedicalService.hit(victim.model, zoneOf(hit.target), energy, roll)
			if victim.player then -- vibração do lado do impacto (Parte 12.6)
				Net.event("Combat_Hit"):FireClient(victim.player, { x = origin.X, y = origin.Y, z = origin.Z })
			end
		end
	end
end

-- Arma caída de quem morreu (jogador ou bot): só com o carregador (Pickup.dropOnDeath).
function CombatService.dropWeapon(pos: Vector3, weapon: string, mag: number)
	local drop = Pickup.dropOnDeath({ weapon = weapon, mag = mag, spare = 0 })
	if drop then
		spawnPickup(pos, drop)
	end
end

-- reabastece a munição (caixa de munição construída pela logística). Arma do outro lado não
-- reabastece: quem pegou a arma do inimigo fica com o que tem nela.
function CombatService.refill(player: Player)
	local a = ammo[player]
	local wp = a and Weapons.get(a.weapon)
	if wp and not Pickup.canRefill(wp.faction, player:GetAttribute("Faction") :: string?) then
		return
	end
	resetAmmo(player)
end

function CombatService.start()
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function(char)
			resetAmmo(p)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			if hum then
				hum.Died:Once(function()
					local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
					local a = ammo[p]
					local drop =
						Pickup.dropOnDeath(if a then { weapon = a.weapon, mag = a.mag, spare = a.spare } else nil)
					if drop and root and not char:GetAttribute("Evacuated") then -- evacuado leva a arma
						spawnPickup(root.Position, drop)
					end
				end)
			end
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
		if not (a and char and head and hum) or hum.Health <= 0 or char:GetAttribute("Downed") then
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
		CombatService.fire(char, wp.id, Vector3.new(ox, oy, oz), Vector3.new(dx, dy, dz), seed, player)
	end)
end

return CombatService
