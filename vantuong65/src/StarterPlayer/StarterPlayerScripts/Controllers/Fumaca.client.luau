--!strict
-- Nuvem da granada de fumaça, desenho de cada cliente (2026-11-13, "copie a granada de fumaça igual ao
-- Front 44 e corrija seus defeitos"). O estado vem do servidor (Modules/SmokeService: modelo
-- "Nuvem" Persistent em workspace.Smoke, com T0, Dur e os 7 sopros); as regras, do Shared/Smoke.
-- Do Front 44 (Effects.SmokeCloud): uma fonte de fumaça grossa e cinza por sopro, partículas grandes e
-- opacas (tapam a visão de verdade), subindo devagar, girando, e as fontes param 7 s antes do fim.
-- Diferente de lá:
--   - não estoura: a lata solta um jato e as fontes ganham força junto com a visão (Smoke.factor);
--   - quem chega depois (ou volta do streaming) vê a nuvem já formada, na idade certa;
--   - pesa menos: cai com a opção de detalhe (atributo GfxDetail: 1, 0,6, 0,3) e pela metade longe;
--   - dentro da nuvem a tela fica velada (a câmera dentro das partículas via através delas).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Smoke = require(ReplicatedStorage.Shared.Smoke)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = 0.28
local TEX = "rbxasset://textures/particles/smoke_main.dds"
local K = Smoke.RADIUS_M / M / 15 -- escala do Front 44 (nuvem de 15 studs) para a nossa
local COLOR = ColorSequence.new(Color3.fromRGB(196, 196, 190), Color3.fromRGB(160, 160, 156))
local FAR_STUDS = 700 / M -- além disso, metade das partículas (a nuvem ainda se vê de longe)

local fx = Instance.new("Folder")
fx.Name = "VT65Fumaca"
fx.Parent = workspace

type Vis = {
	model: Model,
	part: Part,
	puffs: { ParticleEmitter },
	jet: ParticleEmitter,
	t0: number,
	dur: number,
	full: { number }, -- taxa cheia de cada fonte
	ended: boolean,
}
local live: { [Model]: Vis } = {}

local function detail(): number
	local d = player:GetAttribute("GfxDetail")
	return if type(d) == "number" then math.clamp(d, 0.2, 1) else 1
end

local function seq(...: number): NumberSequence
	local a = { ... }
	local keys = {}
	for i = 1, #a, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function build(model: Model)
	if live[model] then
		return
	end
	local center = model:WaitForChild("Centro", 5)
	local t0, dur = model:GetAttribute("T0"), model:GetAttribute("Dur")
	if not (center and center:IsA("BasePart") and type(t0) == "number" and type(dur) == "number") then
		return
	end
	local R = model:GetAttribute("R")
	local Rs = if type(R) == "number" then R else Smoke.RADIUS_M / M
	local part = Instance.new("Part")
	part.Name = "Nuvem"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = center.CFrame
	part.Parent = fx
	local v: Vis = {
		model = model,
		part = part,
		puffs = {},
		jet = Instance.new("ParticleEmitter"),
		t0 = t0,
		dur = dur,
		full = {},
		ended = false,
	}
	for _, a in center:GetChildren() do
		local r = a:GetAttribute("R")
		if a:IsA("Attachment") and type(r) == "number" then
			local att = Instance.new("Attachment")
			att.Position = a.Position
			att.Parent = part
			-- sopro cortado pela parede: partículas menores e mais lentas (não atravessam tanto)
			local s = math.clamp(r / (Rs * Smoke.RING_R), 0.3, 1.1)
			local e = Instance.new("ParticleEmitter")
			e.Texture = TEX
			e.Color = COLOR
			e.Size = seq(0, Rs * 0.35 * s, 0.4, Rs * 0.75 * s, 1, Rs * 0.95 * s)
			e.Transparency = seq(0, 0.55, 0.15, 0.08, 0.8, 0.2, 1, 1)
			e.Lifetime = NumberRange.new(7, 10)
			e.Speed = NumberRange.new(1.5 * K * s, 4 * K * s)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Acceleration = Vector3.new(0, 0.6 * K, 0)
			e.Drag = 0.6
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-12, 12)
			e.LightInfluence = 0.9
			e.Rate = 0
			e.Parent = att
			table.insert(v.puffs, e)
		end
	end
	-- jato da lata: chiado de fumaça fina saindo rápido do chão
	local j = v.jet
	j.Texture = TEX
	j.Color = COLOR
	j.Size = seq(0, 0.15 / M, 1, 1.2 / M)
	j.Transparency = seq(0, 0.35, 0.6, 0.5, 1, 1)
	j.Lifetime = NumberRange.new(0.8, 1.6)
	j.Speed = NumberRange.new(2.5 / M, 4 / M)
	j.SpreadAngle = Vector2.new(35, 35)
	j.EmissionDirection = Enum.NormalId.Top
	j.Acceleration = Vector3.new(0, 0.3 / M, 0)
	j.Drag = 1.5
	j.Rotation = NumberRange.new(0, 360)
	j.LightInfluence = 0.9
	j.Rate = 0
	j.Parent = part
	live[model] = v
	-- chegou com a nuvem já aberta (entrou depois, voltou do streaming): enche na idade dela
	local age = workspace:GetServerTimeNow() - t0
	if age > Smoke.GROW_S and age < dur - Smoke.TAIL_S then
		local n = math.floor((6 * detail() + 1) * math.min(age, 8))
		for _, e in v.puffs do
			e:Emit(n)
		end
	end
end

local function finish(v: Vis)
	if v.ended then
		return
	end
	v.ended = true
	for _, e in v.puffs do
		e.Enabled = false
	end
	v.jet.Enabled = false
	task.delay(11, function()
		v.part:Destroy()
	end)
end

task.spawn(function()
	local folder = workspace:WaitForChild("Smoke", 120)
	if not folder then
		return
	end
	for _, c in folder:GetChildren() do
		if c:IsA("Model") then
			task.spawn(build, c)
		end
	end
	folder.ChildAdded:Connect(function(c)
		if c:IsA("Model") then
			task.spawn(build, c)
		end
	end)
	folder.ChildRemoved:Connect(function(c)
		local v = if c:IsA("Model") then live[c] else nil
		if v then
			live[c] = nil
			finish(v)
		end
	end)
end)

-- ===== véu dentro da nuvem =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65FumacaVeu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1 -- por baixo do HUD
local veil = Instance.new("Frame")
veil.Size = UDim2.fromScale(1, 1)
veil.BackgroundColor3 = Color3.fromRGB(176, 176, 170)
veil.BackgroundTransparency = 1
veil.BorderSizePixel = 0
veil.Parent = gui
task.spawn(function()
	gui.Parent = player:WaitForChild("PlayerGui")
end)

-- ===== quadro: força das fontes (crescer, durar, parar) e o véu =====
local lastRates = 0
RunService.RenderStepped:Connect(function()
	if next(live) == nil then
		if veil.BackgroundTransparency < 1 then
			veil.BackgroundTransparency = 1
		end
		return
	end
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	-- taxas 10 vezes por segundo (Rate não precisa de quadro a quadro)
	if clock - lastRates >= 0.1 then
		lastRates = clock
		local d = detail()
		local camPos = camera.CFrame.Position
		for _, v in live do
			local age = now - v.t0
			if age >= v.dur - Smoke.TAIL_S then
				finish(v)
			elseif not v.ended then
				local grow = math.clamp(age / Smoke.GROW_S, 0, 1)
				local far = (v.part.Position - camPos).Magnitude > FAR_STUDS
				local rate = (6 * d + 1) * grow * (if far then 0.5 else 1)
				for _, e in v.puffs do
					e.Rate = rate
				end
				-- o jato forte no começo, depois um chiado contínuo
				v.jet.Rate = if age < Smoke.GROW_S + 1 then 22 * d else 5 * d
			end
		end
	end
	-- véu: quanto a câmera está dentro de um sopro
	local cam = camera.CFrame.Position
	local dens = Smoke.density(cam.X, cam.Y, cam.Z, Smoke.clouds(workspace:FindFirstChild("Smoke")))
	local want = if dens > 0 then 1 - 0.88 * dens ^ 0.6 else 1
	if math.abs(veil.BackgroundTransparency - want) > 0.01 then
		veil.BackgroundTransparency = want
	end
end)

-- Studio: workspace:SetAttribute("VT65DevFumaca", "estado") lista as nuvens (idade, sopros, taxa)
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevFumaca"):Connect(function()
		if workspace:GetAttribute("VT65DevFumaca") ~= "estado" then
			return
		end
		local now = workspace:GetServerTimeNow()
		local n = 0
		for _, v in live do
			n += 1
			print(
				string.format(
					"[VT65 FUMAÇA] nuvem %d: idade %.1f s de %d s, %d sopros, taxa %.1f/s, a %.0f m",
					n,
					now - v.t0,
					v.dur,
					#v.puffs,
					if v.puffs[1] then v.puffs[1].Rate else 0,
					(v.part.Position - camera.CFrame.Position).Magnitude * M
				)
			)
		end
		print(string.format("[VT65 FUMAÇA] %d nuvem(ns) desenhada(s)", n))
	end)
end
