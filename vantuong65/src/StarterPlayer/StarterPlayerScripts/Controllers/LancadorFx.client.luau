--!strict
-- D-200 (prompt de jogabilidade, item 19): o lançador visto por todos. O servidor (LancadorService)
-- manda o disparo com a velocidade (Fire_Launch, kind "rpg2" ou "m20", + vx, vy, vz, n, by) e o fim
-- (Lancador_Fim { n, x, y, z, falhou }). Aqui:
-- - no disparo: clarão curto na boca, a nuvem de pólvora em volta do atirador (o RPG-2 lança com
--   carga de pólvora: a nuvem cinza-clara denuncia quem atirou) e o sopro para trás do tubo, que
--   levanta poeira do chão;
-- - o projétil: a granada PG-2 (ogiva de 80 mm, haste e aletas) voando pela mesma conta do servidor
--   (gravidade, Shared/Lancador), com um rastro fino de fumaça e o som do voo, se houver;
-- - o fim: some no ponto do servidor; a explosão é a do ExplosionFx (Fire_Impact). Falhou (não
--   armou): um baque e poeira no ponto.
-- Até 12 projéteis ao mesmo tempo; cada um some sozinho em no máximo 9 s.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Lancador = require(ReplicatedStorage.Shared.Lancador)
local Net = require(ReplicatedStorage.Shared.Net)

local M = 0.28
local camera = workspace.CurrentCamera
local TEX = {
	-- D-198: a smoke_main só aparece com cor clara; a explosion01_smoke_main já é escura
	clara = "rbxasset://textures/particles/smoke_main.dds",
	escura = "rbxasset://textures/particles/explosion01_smoke_main.dds",
	brilho = "rbxasset://textures/particles/explosion01_core_main.dds",
}
local MAX_VOOS = 12

local fx = Instance.new("Folder")
fx.Name = "VT65Lancador"
fx.Parent = workspace

local function seq(...: number): NumberSequence
	local a = { ... }
	local keys = {}
	for i = 1, #a, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function peca(nome: string, size: Vector3, cor: Color3, forma: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = nome
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Metal
	p.Color = cor
	p.Size = size
	if forma then
		p.Shape = forma
	end
	return p
end

local function somId(chave: string): string?
	local id = AssetIds.Sounds[chave]
	return if type(id) == "number" and id ~= 0 then "rbxassetid://" .. id else nil
end

-- ===== o projétil =====
-- PG-2: ogiva de 80 mm (wiki:RPG-2), haste fina com a carga de lançamento e 6 aletas (aqui 3 cruzadas)
type Voo = { n: number, modelo: Model, pos: Vector3, vel: Vector3, t: number, params: RaycastParams, som: Sound? }
local voos: { [number]: Voo } = {}
local nVoos = 0

local function granadaModelo(id: string): Model
	local m = Instance.new("Model")
	m.Name = "Projetil_" .. id
	local verde = Color3.fromRGB(70, 78, 52)
	local corpo = peca("Ogiva", Vector3.new(0.2, 0.08, 0.08) / M, verde, Enum.PartType.Cylinder)
	local ponta = peca("Ponta", Vector3.new(0.06, 0.06, 0.06) / M, verde, Enum.PartType.Ball)
	local haste = peca("Haste", Vector3.new(0.34, 0.04, 0.04) / M, Color3.fromRGB(58, 56, 50), Enum.PartType.Cylinder)
	corpo.Parent, ponta.Parent, haste.Parent = m, m, m
	m.PrimaryPart = corpo
	-- o X da peça é o eixo do voo: a ponta à frente (+X), a haste atrás
	ponta.CFrame = CFrame.new(0.11 / M, 0, 0)
	haste.CFrame = CFrame.new(-0.26 / M, 0, 0)
	for k = 0, 2 do
		local aleta = peca("Aleta", Vector3.new(0.1, 0.005, 0.12) / M, Color3.fromRGB(58, 56, 50))
		aleta.CFrame = CFrame.new(-0.38 / M, 0, 0) * CFrame.Angles(k * math.pi / 3, 0, 0)
		aleta.Parent = m
	end
	-- rastro fino de fumaça (a carga de lançamento queima no começo)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-0.42 / M, 0.02 / M, 0)
	a0.Parent = haste
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-0.42 / M, -0.02 / M, 0)
	a1.Parent = haste
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 0.5
	tr.Texture = TEX.clara
	tr.TextureMode = Enum.TextureMode.Stretch
	tr.Color = ColorSequence.new(Color3.fromRGB(205, 200, 190))
	tr.Transparency = seq(0, 0.55, 1, 1)
	tr.WidthScale = seq(0, 1, 1, 4)
	tr.LightInfluence = 1
	tr.Parent = haste
	return m
end

local function orientar(m: Model, pos: Vector3, vel: Vector3)
	if vel.Magnitude < 1e-3 then
		return
	end
	-- o X do modelo no rumo do voo
	local look = CFrame.lookAt(pos, pos + vel)
	m:PivotTo(look * CFrame.Angles(0, math.pi / 2, 0))
end

local function tirar(n: number)
	local v = voos[n]
	if not v then
		return
	end
	voos[n] = nil
	nVoos -= 1
	if v.som then
		v.som:Destroy()
	end
	v.modelo:Destroy()
end

-- ===== o disparo: clarão, nuvem de pólvora e sopro para trás =====
local function disparo(pos: Vector3, dir: Vector3)
	local p = peca("Disparo", Vector3.one * 0.2, Color3.new(), nil)
	p.Transparency = 1
	p.CFrame = CFrame.lookAt(pos, pos + dir)
	p.Parent = fx
	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 200, 140)
	luz.Brightness = 6
	luz.Range = 14
	luz.Parent = p
	task.delay(0.06, function()
		luz:Destroy()
	end)
	-- clarão na boca
	local a = Instance.new("Attachment")
	a.Parent = p
	local brilho = Instance.new("ParticleEmitter")
	brilho.Enabled = false
	brilho.Texture = TEX.brilho
	brilho.Color = ColorSequence.new(Color3.fromRGB(255, 210, 150))
	brilho.LightEmission = 0.8
	brilho.Lifetime = NumberRange.new(0.06, 0.1)
	brilho.Speed = NumberRange.new(2, 6)
	brilho.Size = seq(0, 1.6, 1, 0.4)
	brilho.Transparency = seq(0, 0.1, 1, 1)
	brilho.SpreadAngle = Vector2.new(25, 25)
	brilho.EmissionDirection = Enum.NormalId.Front
	brilho.Parent = a
	brilho:Emit(6)
	-- nuvem de pólvora em volta do tubo (frente e trás), cinza-clara
	local nuvem = Instance.new("ParticleEmitter")
	nuvem.Enabled = false
	nuvem.Texture = TEX.clara
	nuvem.Color = ColorSequence.new(Color3.fromRGB(196, 192, 182))
	nuvem.Lifetime = NumberRange.new(2.5, 4)
	nuvem.Speed = NumberRange.new(1, 4)
	nuvem.Drag = 2
	nuvem.Size = seq(0, 2.5, 0.4, 7, 1, 11)
	nuvem.Transparency = seq(0, 0.35, 0.6, 0.6, 1, 1)
	nuvem.Rotation = NumberRange.new(0, 360)
	nuvem.RotSpeed = NumberRange.new(-15, 15)
	nuvem.SpreadAngle = Vector2.new(180, 180)
	nuvem.Acceleration = Vector3.new(0, 1.2, 0)
	nuvem.WindAffectsDrag = true
	nuvem.Parent = a
	nuvem:Emit(10)
	-- sopro para trás: jato de fumaça e poeira saindo da culatra (~1 m atrás da boca)
	local tras = Instance.new("Attachment")
	tras.Position = Vector3.new(0, 0, 1.3 / M)
	tras.Parent = p
	local sopro = Instance.new("ParticleEmitter")
	sopro.Enabled = false
	sopro.Texture = TEX.clara
	sopro.Color = ColorSequence.new(Color3.fromRGB(184, 172, 150))
	sopro.EmissionDirection = Enum.NormalId.Back
	sopro.Lifetime = NumberRange.new(1, 2)
	sopro.Speed = NumberRange.new(18, 34)
	sopro.Drag = 4
	sopro.Size = seq(0, 1.5, 0.5, 5, 1, 8)
	sopro.Transparency = seq(0, 0.3, 0.7, 0.75, 1, 1)
	sopro.SpreadAngle = Vector2.new(14, 14)
	sopro.Rotation = NumberRange.new(0, 360)
	sopro.Parent = tras
	sopro:Emit(14)
	-- poeira levantada do chão atrás, se o chão está perto
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fx, camera }
	local atras = pos - dir.Unit * (3 / M)
	local chao = workspace:Raycast(atras + Vector3.new(0, 2 / M, 0), Vector3.new(0, -5 / M, 0), params)
	if chao then
		local q = peca("SoproChao", Vector3.one * 0.2, Color3.new(), nil)
		q.Transparency = 1
		q.CFrame = CFrame.new(chao.Position)
		q.Parent = fx
		local poeira = Instance.new("ParticleEmitter")
		poeira.Enabled = false
		poeira.Texture = TEX.clara
		poeira.Color = ColorSequence.new(Color3.fromRGB(170, 150, 120))
		poeira.EmissionDirection = Enum.NormalId.Top
		poeira.Lifetime = NumberRange.new(1.2, 2.2)
		poeira.Speed = NumberRange.new(4, 9)
		poeira.Drag = 3
		poeira.Size = seq(0, 2, 1, 7)
		poeira.Transparency = seq(0, 0.4, 1, 1)
		poeira.SpreadAngle = Vector2.new(70, 70)
		poeira.Parent = q
		poeira:Emit(10)
		task.delay(3, function()
			q:Destroy()
		end)
	end
	task.delay(5, function()
		p:Destroy()
	end)
end

local function fimFalhou(pos: Vector3)
	local p = peca("Falhou", Vector3.one * 0.2, Color3.new(), nil)
	p.Transparency = 1
	p.CFrame = CFrame.new(pos)
	p.Parent = fx
	local poeira = Instance.new("ParticleEmitter")
	poeira.Enabled = false
	poeira.Texture = TEX.clara
	poeira.Color = ColorSequence.new(Color3.fromRGB(170, 150, 120))
	poeira.Lifetime = NumberRange.new(0.6, 1.2)
	poeira.Speed = NumberRange.new(3, 7)
	poeira.Size = seq(0, 0.8, 1, 3)
	poeira.Transparency = seq(0, 0.4, 1, 1)
	poeira.SpreadAngle = Vector2.new(60, 60)
	poeira.EmissionDirection = Enum.NormalId.Top
	poeira.Parent = p
	poeira:Emit(8)
	local s = Instance.new("Sound")
	s.SoundId = somId("impact_earth") or ""
	s.Volume = 0.9
	s.RollOffMaxDistance = 300 / M
	s.Parent = p
	s:Play()
	task.delay(2, function()
		p:Destroy()
	end)
end

Net.unreliable("Fire_Launch").OnClientEvent:Connect(function(e: any)
	if type(e) ~= "table" or (e.kind ~= "rpg2" and e.kind ~= "m20") or type(e.vx) ~= "number" then
		return
	end
	local pos = Vector3.new(e.x, e.y, e.z)
	local vel = Vector3.new(e.vx, e.vy, e.vz)
	if (pos - camera.CFrame.Position).Magnitude * M > 1500 then
		return
	end
	disparo(pos - vel.Unit * (0.6 / M), vel)
	if nVoos >= MAX_VOOS or type(e.n) ~= "number" then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { fx, camera }
	local by = if type(e.by) == "number" then Players:GetPlayerByUserId(e.by) else nil
	if by and by.Character then
		table.insert(ignore, by.Character)
	end
	params.FilterDescendantsInstances = ignore
	local modelo = granadaModelo(e.kind)
	orientar(modelo, pos, vel)
	modelo.Parent = fx
	local v: Voo = { n = e.n, modelo = modelo, pos = pos, vel = vel, t = 0, params = params, som = nil }
	local voo = somId(e.kind .. "_voo")
	if voo then
		local s = Instance.new("Sound")
		s.SoundId = voo
		s.Looped = true
		s.Volume = 0.8
		s.RollOffMinDistance = 6 / M
		s.RollOffMaxDistance = 180 / M
		s.Parent = modelo.PrimaryPart
		s:Play()
		v.som = s
	end
	voos[e.n] = v
	nVoos += 1
end)

Net.unreliable("Lancador_Fim").OnClientEvent:Connect(function(e: any)
	if type(e) ~= "table" or type(e.n) ~= "number" then
		return
	end
	tirar(e.n)
	if e.falhou == true and type(e.x) == "number" then
		fimFalhou(Vector3.new(e.x, e.y, e.z))
	end
end)

-- o voo no cliente: a mesma conta do servidor; para no que bater (o fim do servidor tira de vez)
RunService.Heartbeat:Connect(function(dt: number)
	local g = Lancador.G / M
	for n, v in voos do
		v.t += dt
		if v.t > 9 then
			tirar(n)
			continue
		end
		if v.modelo.Parent == nil then
			continue -- já bateu aqui; espera o fim do servidor (ou o tempo)
		end
		local nv = v.vel - Vector3.new(0, g * dt, 0)
		local step = (v.vel + nv) * 0.5 * dt
		local hit = workspace:Raycast(v.pos, step, v.params)
		if hit then
			v.modelo.Parent = nil
			if v.som then
				v.som:Stop()
			end
			continue
		end
		v.pos += step
		v.vel = nv
		orientar(v.modelo, v.pos, v.vel)
	end
end)
