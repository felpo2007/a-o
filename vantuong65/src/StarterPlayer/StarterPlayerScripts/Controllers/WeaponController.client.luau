--!strict
-- Arma placeholder (F2): disparo com semente, mira (zoom de FOV), recarga, recuo com tendência
-- aleatória e traçantes. Sem retícula, sem hitmarker, sem contador de munição na tela (Parte 1).
-- O visual (mira de ferro 3D, IK, animações) entra com os assets do Lote 2.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Weapons = require(ReplicatedStorage.Shared.Weapons)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28

local weapon: Weapons.Weapon? = nil
local modeIdx = 1
local mag = 0
local firing = false
local aiming = false
local lastShot = 0
local seedRng = Rng.new(os.time() + player.UserId)
local recoilPitch, recoilYaw = 0, 0

local function equip()
	local s = player:GetAttribute("Loadout")
	local id = if type(s) == "string" then string.split(s, ",")[1] else nil
	local wp = id and Weapons.get(id)
	weapon = if wp and wp.enabled then wp else nil
	modeIdx = 1
end

Net.event("Combat_Ammo").OnClientEvent:Connect(function(a)
	mag = a.mag
end)

-- traçante visual: refaz a trajetória (mesma semente) e desenha um segmento curto
local tracerFolder = Instance.new("Folder")
tracerFolder.Name = "VT65Tracers"
tracerFolder.Parent = workspace
local function tracer(shot: any, color: Color3)
	local pts: { Vector3 } = {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { tracerFolder, player.Character :: Model }
	Ballistics.trace({
		ox = shot.ox * M,
		oy = shot.oy * M,
		oz = shot.oz * M,
		dx = shot.dx,
		dy = shot.dy,
		dz = shot.dz,
		weaponId = shot.w,
		seed = shot.seed,
		maxTime = 1.2,
	}, function(ax, ay, az, bx, by, bz)
		table.insert(pts, Vector3.new(ax, ay, az) / M)
		local r = workspace:Raycast(Vector3.new(ax, ay, az) / M, Vector3.new(bx - ax, by - ay, bz - az) / M, params)
		return if r then { x = r.Position.X * M, y = r.Position.Y * M, z = r.Position.Z * M } else nil
	end)
	if #pts < 2 then
		return
	end
	local a, b = pts[1], pts[#pts]
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.08, 0.08, (b - a).Magnitude)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	p.Transparency = 0.3
	p.Parent = tracerFolder
	task.delay(0.08, function()
		p:Destroy()
	end)
end

Net.unreliable("Combat_Tracer").OnClientEvent:Connect(function(shot)
	local wp = Weapons.get(shot.w)
	-- só metralhadoras com traçante (proporção real das fitas a confirmar: PLACEHOLDER 1 em 5)
	if wp and wp.kind == "mg" and shot.seed % 5 == 0 then
		tracer(shot, if wp.faction == "US" then Color3.fromRGB(255, 80, 60) else Color3.fromRGB(90, 255, 120))
	end
end)

-- som do próprio tiro (camadas perto/médio/longe e o estalo supersônico entram na F3)
local S = AssetIds.Sounds
local SHOT_SOUND: { [string]: number } = {
	m14 = S.shot_m14,
	m60 = S.shot_m14, -- mesmo cartucho 7.62x51 até a camada própria
	m1911 = S.shot_m14,
	type56 = S.shot_type56,
	sks = S.shot_type56,
	rpd = S.shot_type56,
	type54 = S.shot_type56,
}
local function playId(id: number, volume: number)
	if id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = camera
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end
local function playShot(id: string)
	local sid = SHOT_SOUND[id]
	if not sid or sid == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. sid
	s.Volume = 0.8
	s.Parent = camera
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local function fire()
	local wp = weapon
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		return -- em veículo: a arma do assento é do VehicleController
	end
	if not (wp and head) or player:GetAttribute("Downed") then
		return
	end
	if mag <= 0 then
		if os.clock() - lastShot > 0.3 then
			lastShot = os.clock()
			playId(S.dry_click, 0.8) -- Type 56 sem trava do ferrolho: só o clique (Parte 10.6)
		end
		return
	end
	local now = os.clock()
	if now - lastShot < Weapons.minInterval(wp) then
		return
	end
	lastShot = now
	mag -= 1
	local o = camera.CFrame.Position
	local d = camera.CFrame.LookVector
	local seed = seedRng:nextU32()
	local shot = {
		w = wp.id,
		ox = o.X,
		oy = o.Y,
		oz = o.Z,
		dx = d.X,
		dy = d.Y,
		dz = d.Z,
		seed = seed,
		t = workspace:GetServerTimeNow(),
	}
	Net.event("Combat_Fire"):FireServer(shot)
	playShot(wp.id)
	if wp.kind == "mg" and seed % 5 == 0 then
		tracer(shot, if wp.faction == "US" then Color3.fromRGB(255, 80, 60) else Color3.fromRGB(90, 255, 120))
	end
	-- recuo físico aproximado: impulso do projétil e dos gases (~1,5x) contra a massa da arma.
	-- PLACEHOLDER de escala; padrão aleatório com tendência por semente (Parte 10.3)
	local impulse = (wp.bulletMassG / 1000) * wp.muzzleVelocity * 1.5
	local kick = math.deg(impulse / wp.massLoadedKg) * 0.9
	if player:GetAttribute("ArmImpaired") then
		kick *= 1.5
	end
	if aiming then
		kick *= 0.8
	end
	local r = Rng.new(seed)
	recoilPitch += kick
	recoilYaw += (r:next() - 0.35) * kick * 0.6 -- tendência leve para a direita
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		fire()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		aiming = true
	elseif input.KeyCode == Enum.KeyCode.R then
		Net.event("Combat_Reload"):FireServer()
		if weapon then
			playId(if weapon.faction == "US" then S.reload_m14 else S.reload_type56, 0.7)
		end
	elseif input.KeyCode == Enum.KeyCode.V and weapon then
		modeIdx = modeIdx % #weapon.modes + 1
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		aiming = false
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local wp = weapon
	if firing and wp and wp.modes[modeIdx] == "auto" then
		fire()
	end
	-- mira: levar ao ombro leva tempo proporcional ao peso (Parte 10.4)
	local target = if aiming then 55 else 70
	local speed = if wp then 10 / math.max(wp.massLoadedKg, 1) else 4
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * speed)
	-- aplica e recupera o recuo
	if recoilPitch ~= 0 or recoilYaw ~= 0 then
		local stepP = recoilPitch * math.min(1, dt * 18)
		local stepY = recoilYaw * math.min(1, dt * 18)
		camera.CFrame *= CFrame.Angles(math.rad(stepP), math.rad(-stepY), 0)
		recoilPitch -= stepP
		recoilYaw -= stepY
	end
end)

player:GetAttributeChangedSignal("Loadout"):Connect(equip)
player.CharacterAdded:Connect(function()
	equip()
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- primeira pessoa (Parte 10.5)
end)
equip()
