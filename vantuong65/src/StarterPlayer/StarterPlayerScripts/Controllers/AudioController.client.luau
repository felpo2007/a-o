--!strict
-- Áudio da F3 (Parte 5 e 10.7): ambiências por zona com crossfade, passos por material (seus e
-- dos outros, 3D), tiros alheios em camadas por distância com atraso do som (d/349 m/s),
-- estalo supersônico quando a bala passa perto e impacto por material. Sem asset (ID 0) fica mudo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Weapons = require(ReplicatedStorage.Shared.Weapons)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = MapConfig.STUD_M
local SND = AssetIds.Sounds

local function sid(key: string): string?
	local id = SND[key]
	return if type(id) == "number" and id ~= 0 then "rbxassetid://" .. id else nil
end

-- som 3D num ponto do mundo (ou 2D se pos == nil)
local function play(key: string, pos: Vector3?, volume: number, maxDist: number?, delay: number?)
	local id = sid(key)
	if not id then
		return
	end
	local function go()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = maxDist or 400
		local holder: Instance = SoundService
		local att: Attachment? = nil
		if pos then
			local a = Instance.new("Attachment")
			a.WorldPosition = pos
			a.Parent = workspace.Terrain
			att = a
			holder = a
		end
		s.Parent = holder
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
			if att then
				att:Destroy()
			end
		end)
	end
	if delay and delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
end

-- ===== ambiências =====
local AMB: { [string]: string } = {
	paddy = "ambience_paddy_morning",
	village = "ambience_village",
	beach = "ambience_beach",
	tunnel = "ambience_tunnel",
}
local loops: { [string]: Sound } = {}
for zone, key in AMB do
	local id = sid(key)
	if id then
		local s = Instance.new("Sound")
		s.Name = "Amb_" .. zone
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.Parent = SoundService
		s:Play()
		loops[zone] = s
	end
end

local villages: { Vector3 } = {}
local beachX = math.huge
for _, l in MapConfig.Locations do
	if
		string.find(l.name, "An Cường")
		or string.find(l.name, "Nam Yên")
		or string.find(l.name, "An Thới")
		or string.find(l.name, "An Phước")
		or string.find(l.name, "Lạc Sơn")
	then
		table.insert(villages, Vector3.new(l.x, 0, l.z))
	end
	if string.find(l.name, "Green Beach") then
		beachX = l.x - 120 / M
	end
end

local function underground(pos: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local r = workspace:Raycast(pos, Vector3.new(0, 25, 0), params)
	return r ~= nil and (r.Instance == workspace.Terrain or string.find(r.Instance.Name, "ceiling") ~= nil)
end

local function zoneAt(pos: Vector3): string
	if underground(pos) then
		return "tunnel"
	end
	if pos.X > beachX then
		return "beach"
	end
	for _, v in villages do
		if (Vector3.new(pos.X, 0, pos.Z) - v).Magnitude < 150 / M then
			return "village"
		end
	end
	return "paddy"
end

task.spawn(function()
	while true do
		task.wait(0.5)
		local zone = zoneAt(camera.CFrame.Position)
		for z, s in loops do
			local target = if z == zone then 0.5 else 0
			s.Volume += (target - s.Volume) * 0.35
		end
	end
end)

-- ===== passos =====
local function stepKey(root: BasePart, model: Model): string
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local r = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	if not r then
		return "step_grass"
	end
	local inst = r.Instance
	if inst ~= workspace.Terrain then
		local mat = inst:GetAttribute("Material")
		if mat == "PaddyWater" then
			return "step_paddy"
		elseif inst.Name == "Dike" then
			return "step_mud"
		elseif inst:FindFirstAncestor("log_bridge") then
			return "step_wood"
		end
		return "step_grass"
	end
	if r.Material == Enum.Material.Water then
		return "step_paddy"
	elseif r.Material == Enum.Material.Sand then
		return "step_sand"
	elseif r.Material == Enum.Material.Mud then
		return "step_mud"
	end
	return "step_grass"
end

local walked: { [Model]: { pos: Vector3, acc: number } } = setmetatable({}, { __mode = "k" }) :: any
local STRIDE = 0.8 / M -- ~0,8 m por passo (o arquivo de passos tem 4 passos: tocamos 1 a cada 4)

local function characters(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	return list
end

task.spawn(function()
	while true do
		task.wait(0.1)
		local listener = camera.CFrame.Position
		for _, char in characters() do
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - listener).Magnitude < 60 / M then
				local w = walked[char]
				if not w then
					walked[char] = { pos = root.Position, acc = 0 }
				else
					local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(w.pos.X, 0, w.pos.Z)).Magnitude
					w.pos = root.Position
					w.acc += d
					if w.acc >= STRIDE * 4 then
						w.acc = 0
						local vol = if char:GetAttribute("Crouched") then 0.25 else 0.6
						play(stepKey(root, char), root.Position, vol, 45 / M)
					end
				end
			end
		end
	end
end)

-- ===== tiros dos outros: camadas, atraso do som, estalo e impacto =====
local NEAR: { [string]: string } = {
	m14 = "shot_m14",
	m60 = "shot_m14",
	m1911 = "shot_m14",
	type56 = "shot_type56",
	sks = "shot_type56",
	rpd = "shot_type56",
	type54 = "shot_type56",
}

Net.unreliable("Combat_Tracer").OnClientEvent:Connect(function(shot)
	local wp = Weapons.get(shot.w)
	if not wp then
		return
	end
	local origin = Vector3.new(shot.ox, shot.oy, shot.oz)
	local dir = Vector3.new(shot.dx, shot.dy, shot.dz).Unit
	local listener = camera.CFrame.Position
	local dM = (origin - listener).Magnitude * M
	local delay = dM / Ballistics.SOUND
	if dM < 60 then
		play(NEAR[wp.id] or "shot_mid", origin, 1.0, 1500, delay)
	elseif dM < 300 then
		play("shot_mid", nil, math.clamp(1.2 - dM / 300, 0.3, 1), nil, delay)
	elseif dM < 2500 then
		play("shot_distant", nil, math.clamp(1 - dM / 2500, 0.15, 0.8), nil, delay)
	end
	-- estalo: passagem mais próxima da trajetória (reta) até o ouvinte, se supersônica
	local t = (listener - origin):Dot(dir)
	if t > 0 then
		local closest = (origin + dir * t - listener).Magnitude * M
		local distM = t * M
		local tFlight = distM / math.max(wp.muzzleVelocity * 0.85, 1)
		if closest < 8 and wp.muzzleVelocity > Ballistics.SOUND and distM > 15 then
			play("crack", nil, math.clamp(1.2 - closest / 8, 0.3, 1.2), nil, tFlight)
		end
	end
	-- impacto perto do ouvinte: refaz a trajetória com a mesma semente
	if dM < 150 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
		local hit = Ballistics.trace({
			ox = origin.X * M,
			oy = origin.Y * M,
			oz = origin.Z * M,
			dx = dir.X,
			dy = dir.Y,
			dz = dir.Z,
			weaponId = wp.id,
			seed = shot.seed,
			maxTime = 1,
		}, function(ax, ay, az, bx, by, bz)
			local r = workspace:Raycast(Vector3.new(ax, ay, az) / M, Vector3.new(bx - ax, by - ay, bz - az) / M, params)
			if not r then
				return nil
			end
			local key = "impact_earth"
			local mat = r.Instance:GetAttribute("Material")
			if mat == "PaddyWater" or r.Material == Enum.Material.Water then
				key = "impact_water"
			elseif mat == "Bamboo" then
				key = "impact_wood"
			elseif mat == "Thatch" then
				key = "impact_thatch"
			end
			local p = r.Position * M
			return { x = p.X, y = p.Y, z = p.Z, target = key }
		end)
		if hit then
			local pos = Vector3.new(hit.x, hit.y, hit.z) / M
			local dl = (pos - listener).Magnitude * M
			if dl < 80 then
				play(hit.target :: string, pos, 0.9, 80 / M, hit.t + dl / Ballistics.SOUND)
			end
		end
	end
end)

local _ = RunService
