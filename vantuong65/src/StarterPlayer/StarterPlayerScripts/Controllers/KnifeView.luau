--!strict
-- Faca, baioneta e coronhada em 1ª pessoa (D-94), chamado pelo WeaponVisuals a cada quadro. Fica
-- num módulo à parte: o WeaponVisuals já está perto do limite de 200 locais do Luau.
-- - Saque: a mão direita larga o punho do fuzil (que desce para a mão esquerda), vai à bainha no
--   quadril e volta com a faca na guarda baixa.
-- - Estocada: antecipação (o braço recua e a lâmina sobe), estocada reta e rápida, follow-through
--   e volta; golpe de lado: o pulso arma à direita com o fio para a esquerda, corta em arco e segue.
-- - Baioneta: o fuzil recua e avança com o passo; coronhada: a coronha sobe e bate.
-- - Câmera: balanço com o golpe (o corpo vai junto) e coice no impacto (tranco curto e uma pausa de
--   ~60 ms no golpe, a lâmina "prende"). O impacto local é previsto (alcance e cone do Shared/Melee
--   contra os corpos à frente); o dano é só do servidor.
-- - Sem golpe por Melee.SHEATHE_AFTER_S, a faca volta à bainha e a mão ao punho.
-- - Para todos: som do golpe e do impacto (Combat_Melee do servidor) e um efeito discreto, escuro e
--   pequeno (poeira de pano, nada de sangue: regras de conteúdo do Roblox).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Melee = require(ReplicatedStorage.Shared.Melee)
local Net = require(ReplicatedStorage.Shared.Net)

local KnifeView = {}
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = Melee.STUD_M

-- ===== quadros-chave (m no espaço da câmera; graus da faca: arfagem, guinada, rolagem) =====
-- ease do trecho que TERMINA na chave: "in" acelera (antecipação), "out" sai rápido e freia
-- (golpe), "io" suave (volta)
type Key = { t: number, p: Vector3, r: Vector3, e: string }
local function k(t: number, x: number, y: number, z: number, rx: number, ry: number, rz: number, e: string): Key
	return { t = t, p = Vector3.new(x, y, z), r = Vector3.new(rx, ry, rz), e = e }
end
local READY = k(0, 0.13, -0.2, -0.34, 8, 6, -12, "io")
local HIP = k(0, 0.24, -0.5, -0.06, -70, 0, 0, "io")
-- saque: do punho do fuzil (t = 0, posto em tempo real) à bainha e à guarda, com um passo além
local DRAW = {
	k(0.12, 0.24, -0.5, -0.06, -70, 0, 0, "in"),
	k(0.24, 0.12, -0.18, -0.37, 14, 8, -14, "out"),
	k(0.28, READY.p.X, READY.p.Y, READY.p.Z, READY.r.X, READY.r.Y, READY.r.Z, "io"),
}
-- stylua: ignore
local STRIKE: { [string]: { Key } } = {
	estocada = {
		k(0,    0.13, -0.20, -0.34,   8,   6, -12, "io"),
		k(0.10, 0.17, -0.24, -0.19,  14,  -2, -20, "in"),  -- antecipação: recua e sobe a ponta
		k(0.20, 0.04, -0.12, -0.64,  -2,  -6,  -4, "out"), -- estocada: braço estendido
		k(0.30, 0.05, -0.13, -0.60,  -4,  -5,  -2, "io"),  -- follow-through
		k(0.55, 0.13, -0.20, -0.34,   8,   6, -12, "io"),
	},
	lado = {
		k(0,    0.13, -0.20, -0.34,   8,   6, -12, "io"),
		k(0.12, 0.31, -0.07, -0.30,   4,  10, -82, "in"),  -- arma o pulso à direita, fio para a esquerda
		k(0.24, -0.04, -0.14, -0.48, -4,  36, -86, "out"), -- corte em arco
		k(0.36, -0.20, -0.22, -0.40, -8,  70, -80, "io"),  -- segue o arco
		k(0.60, 0.13, -0.20, -0.34,   8,   6, -12, "io"),
	},
}
-- fuzil (CFrame no espaço da câmera, à frente da pose de sempre) e câmera por golpe:
-- {t, x, y, z (m), arfagem, guinada, rolagem (graus)}
type RKey = { t: number, p: Vector3, r: Vector3, e: string }
-- stylua: ignore
local RIFLE: { [string]: { RKey } } = {
	baioneta = {
		k(0,    0,     0,     0,     0,  0,  0, "io"),
		k(0.18, 0.01, -0.02,  0.09,  3,  0, -4, "in"),   -- recua
		k(0.32, -0.01, -0.03, -0.30, -3, 0,  2, "out"),  -- estocada com o passo
		k(0.45, -0.01, -0.03, -0.27, -3, 0,  2, "io"),
		k(0.90, 0,     0,     0,     0,  0,  0, "io"),
	},
	coronhada = {
		k(0,    0,     0,     0,     0,   0,   0, "io"),
		k(0.16, 0.05, -0.04,  0.06,  35, -20, -15, "in"), -- arma: a coronha vem para a frente
		k(0.30, -0.04, 0.02, -0.16,  75, -45, -40, "out"), -- bate
		k(0.45, -0.03, 0.01, -0.12,  70, -40, -35, "io"),
		k(0.85, 0,     0,     0,     0,   0,   0, "io"),
	},
}
-- stylua: ignore
local CAM: { [string]: { RKey } } = {
	estocada = {
		k(0, 0, 0, 0, 0, 0, 0, "io"), k(0.10, 0, 0, 0.01, 1.0, 1.2, 1.5, "in"),
		k(0.20, 0, -0.01, -0.06, -1.2, -0.8, -2.5, "out"), k(0.55, 0, 0, 0, 0, 0, 0, "io"),
	},
	lado = {
		k(0, 0, 0, 0, 0, 0, 0, "io"), k(0.12, 0, 0, 0, 0.4, 2.5, 3, "in"),
		k(0.24, 0, -0.01, -0.03, -0.6, -3.5, -4, "out"), k(0.36, 0, 0, -0.02, -0.4, -2, -2, "io"),
		k(0.60, 0, 0, 0, 0, 0, 0, "io"),
	},
	baioneta = {
		k(0, 0, 0, 0, 0, 0, 0, "io"), k(0.18, 0, 0, 0.03, 1.2, 0, 1, "in"),
		k(0.32, 0, -0.02, -0.12, -1.5, 0, -1, "out"), k(0.90, 0, 0, 0, 0, 0, 0, "io"),
	},
	coronhada = {
		k(0, 0, 0, 0, 0, 0, 0, "io"), k(0.16, 0, 0, 0.02, 1, 2.5, 3, "in"),
		k(0.30, 0, -0.01, -0.05, -1, -3, -3, "out"), k(0.85, 0, 0, 0, 0, 0, 0, "io"),
	},
}
local LOWER = CFrame.new(-0.08 / M, -0.13 / M, 0.05 / M) * CFrame.Angles(math.rad(-25), math.rad(25), math.rad(15))

local function ease(x: number, e: string): number
	x = math.clamp(x, 0, 1)
	if e == "in" then
		return x * x * (2 - x) * 0.5 + x * x * 0.5 -- acelera, sem parar no fim
	elseif e == "out" then
		return 1 - (1 - x) ^ 3 -- sai rápido e freia
	end
	return x * x * (3 - 2 * x)
end

local function eval(keys: { Key }, t: number, first: Key?): (Vector3, Vector3)
	local list = keys
	if t <= list[1].t then
		local f = first or list[1]
		if first and list[1].t > 0 then
			local u = ease(t / list[1].t, list[1].e)
			return f.p:Lerp(list[1].p, u), f.r:Lerp(list[1].r, u)
		end
		return list[1].p, list[1].r
	end
	for i = 1, #list - 1 do
		local a, b = list[i], list[i + 1]
		if t < b.t then
			local u = ease((t - a.t) / (b.t - a.t), b.e)
			return a.p:Lerp(b.p, u), a.r:Lerp(b.r, u)
		end
	end
	local z = list[#list]
	return z.p, z.r
end

local function rot(r: Vector3): CFrame
	return CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

-- ===== estado =====
local S = {
	id = "",
	t = 99, -- tempo do golpe atual (s, já sem o saque)
	draw = 0, -- tempo do saque (s); DRAW_S = acabou
	drawing = false,
	knifeUntil = -10, -- relógio local
	sheathe = -1, -- tempo da guarda (s); −1 = parada
	impactDone = true,
	stop = 0, -- pausa do golpe no impacto (s)
	jolt = 0, -- coice no impacto (0..1)
	joltT = 99,
	camPY = CFrame.identity, -- arfagem/guinada aplicadas no quadro anterior (desfeitas no próximo)
	weight = 0, -- fuzil abaixado (0..1)
	gripFrom = Vector3.zero, -- mão no punho do fuzil quando o saque começou (espaço da câmera, m)
}
local model: Model? = nil
local modelKey = ""

-- ===== sons =====
local S_ID = AssetIds.Sounds :: any
local function soundId(key: string, fallback: string): (number, number)
	local id = S_ID[key]
	if type(id) == "number" and id ~= 0 then
		return id, 1
	end
	local f = S_ID[fallback]
	return if type(f) == "number" then f else 0, 0.75 -- substituto mais grave até subir o próprio
end

local lastLocalImpact = -10 -- o impacto previsto não repete o som quando a confirmação chega
local function play(key: string, fallback: string, volume: number, at: Vector3?)
	local id, speed = soundId(key, fallback)
	if id == 0 then
		return
	end
	if key == "faca_impacto" and at == nil then
		lastLocalImpact = os.clock()
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.PlaybackSpeed = speed * (0.94 + math.random() * 0.12)
	s.RollOffMaxDistance = 40 / M
	local holder: Instance = camera
	if at then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		holder = a
		task.delay(3, function()
			a:Destroy()
		end)
	end
	s.Parent = holder
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

-- ===== efeito do impacto (discreto: pó escuro de pano, pequeno) =====
local DUST = "rbxasset://textures/particles/smoke_main.dds"
local function puff(at: Vector3, body: boolean, dir: Vector3?)
	local a = Instance.new("Attachment")
	local n = if dir and dir.Magnitude > 1e-3 then -dir.Unit else Vector3.yAxis
	local right = if math.abs(n.Y) > 0.9 then Vector3.xAxis else n:Cross(Vector3.yAxis).Unit
	a.CFrame = CFrame.fromMatrix(at, right, n)
	local e = Instance.new("ParticleEmitter")
	e.Texture = DUST
	e.Color = ColorSequence.new(if body then Color3.fromRGB(58, 50, 44) else Color3.fromRGB(112, 96, 74))
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02 / M),
		NumberSequenceKeypoint.new(1, (if body then 0.07 else 0.1) / M),
	})
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.18, 0.32)
	e.Speed = NumberRange.new(0.3 / M, 0.9 / M)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Drag = 6
	e.Rate = 0
	e.LightInfluence = 1
	e.Parent = a
	a.Parent = workspace.Terrain
	e:Emit(if body then 5 else 7)
	task.delay(0.8, function()
		a:Destroy()
	end)
end

-- ===== impacto previsto (só o tranco e o som; o dano é do servidor) =====
local function enemies(): { Model }
	local mine = player:GetAttribute("Faction")
	local out = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if p ~= player and c and c:GetAttribute("Faction") ~= mine then
			table.insert(out, c)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	for _, m in if folder then folder:GetChildren() else {} do
		if m:IsA("Model") and m:GetAttribute("Faction") ~= mine then
			table.insert(out, m)
		end
	end
	return out
end

local function predictHit(id: string): Vector3?
	local a = Melee.get(id)
	local char = player.Character
	if not (a and char) then
		return nil
	end
	local cf = camera.CFrame
	local o, d = cf.Position, cf.LookVector
	local best: Vector3?, bestAng = nil, a.coneDeg
	for _, m in enemies() do
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			for _, name in { "UpperTorso", "Head", "LowerTorso" } do
				local p = m:FindFirstChild(name) :: BasePart?
				if p then
					local v = p.Position - o
					local dist = math.max(v.Magnitude - 0.25 / M, 0) * M
					local ang = Melee.angleDeg(d.X, d.Y, d.Z, v.X, v.Y, v.Z)
					if dist <= a.reachM and ang <= bestAng then
						best, bestAng = p.Position, ang
					end
				end
			end
		end
	end
	if not best then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = { char, camera }
	local v = (best :: Vector3) - o
	local r = workspace:Raycast(o, v * 0.9, params)
	if r and not r.Instance:FindFirstAncestorWhichIsA("Model") then
		return nil -- parede no meio
	end
	return o + v * 0.85
end

-- ===== faca do modelo de 1ª pessoa =====
local function knifeId(): string
	return if player:GetAttribute("Faction") == "VC" then Melee.KNIFE.VC else Melee.KNIFE.US
end

local function ensureModel(): Model?
	local id = knifeId()
	local key = id .. (if KnifeModel.art(id) then ":arte" else "")
	if model and key == modelKey then
		return model
	end
	if model then
		model:Destroy()
		model = nil
	end
	local m = KnifeModel.build(id)
	if not m then
		return nil
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m.Name = "VT65Faca1P"
	m.Parent = camera
	model = m
	modelKey = key
	return m
end

-- ===== API =====
-- Golpe começou (WeaponController, no toque). draw: a faca ainda estava na bainha.
function KnifeView.start(id: string, draw: boolean)
	local a = Melee.get(id)
	if not a then
		return
	end
	S.id = id
	S.t = 0
	S.impactDone = false
	S.stop = 0
	S.sheathe = -1
	S.drawing = draw and a.weapon == "knife"
	S.draw = if S.drawing then 0 else Melee.DRAW_S
	if a.weapon == "knife" then
		S.knifeUntil = os.clock() + Melee.impactDelay(id, not draw) + a.recover + Melee.SHEATHE_AFTER_S
		if S.drawing then
			play("faca_saque", "bandage", 0.5, nil)
		end
	end
	task.delay(Melee.impactDelay(id, not S.drawing) - a.impact * 0.5, function()
		if S.id == id then
			play("faca_corte", "", 0.45, nil)
		end
	end)
end

-- ===== troca de arma (2026-11-13, "não consigo puxar arma") =====
-- A arma da mão desce girando para baixo e para a direita em holsterS (o WeaponController troca o
-- modelo lá embaixo, fora da vista) e a nova sobe em drawS (tempos do Front 44, Shared/Equipar).
-- drawS = math.huge: a arma fica embaixo (granada na mão) até a próxima troca.
local SWAP_DOWN = CFrame.new(0.06 / M, -0.24 / M, 0.06 / M) * CFrame.Angles(math.rad(-50), math.rad(25), math.rad(20))
local swap = { t0 = -10, hold = 0, draw = 0 }

function KnifeView.troca(holsterS: number, drawS: number)
	swap.t0, swap.hold, swap.draw = os.clock(), math.max(holsterS, 0), math.max(drawS, 0)
end

function KnifeView.trocando(): boolean
	return os.clock() < swap.t0 + swap.hold + swap.draw
end

-- quanto a arma está abaixada pela troca agora (0..1)
local function swapWeight(now: number): number
	local t = now - swap.t0
	if t < 0 or t > swap.hold + swap.draw then
		return 0
	end
	if t < swap.hold then
		return ease(t / swap.hold, "in")
	end
	if swap.draw <= 0 then
		return 1
	end
	return 1 - ease((t - swap.hold) / swap.draw, "io")
end

-- fuzil a guardar já (atirar com a faca na mão a devolve à bainha)
function KnifeView.sheatheNow()
	if S.knifeUntil > os.clock() then
		S.knifeUntil = os.clock()
	end
end

function KnifeView.busy(): boolean
	return S.knifeUntil > os.clock() or S.sheathe >= 0 or (S.id ~= "" and S.t < 0.9)
end

export type Out = {
	rifle: CFrame, -- antes da pose da arma, no espaço da câmera
	handR: Vector3?, -- mão direita na faca (mundo)
	handRot: CFrame?,
	wristR: Vector3?,
	elbowR: Vector3?,
	active: boolean,
}
local out: Out = { rifle = CFrame.identity, handR = nil, handRot = nil, wristR = nil, elbowR = nil, active = false }

-- Câmera: tira a arfagem/guinada do quadro anterior e põe a nova; rolagem e posição são postas de
-- novo a cada quadro (o módulo de câmera refaz as duas a partir da direção do olhar).
local function applyCamera(py: CFrame, rest: CFrame)
	local cf = camera.CFrame * S.camPY:Inverse() * py
	S.camPY = py
	camera.CFrame = cf * rest
end

-- Um quadro. visible: a arma de 1ª pessoa aparece (fora do veículo, da 3ª pessoa, dos menus).
-- handR0: mão direita no punho do fuzil (mundo), para o saque e a guarda partirem dela.
function KnifeView.step(dt: number, visible: boolean, handR0: Vector3?): Out
	out.handR, out.handRot, out.wristR, out.elbowR = nil, nil, nil, nil
	out.rifle = CFrame.identity
	local now = os.clock()
	local a = Melee.get(S.id)
	-- relógio do golpe (pausa curta no impacto)
	local speed = if S.stop > 0 then 0.12 else 1
	S.stop = math.max(0, S.stop - dt)
	if S.drawing then
		S.draw += dt * speed
		if S.draw >= Melee.DRAW_S then
			S.drawing = false
			S.draw = Melee.DRAW_S
		end
	elseif a then
		S.t += dt * speed
	end
	-- impacto previsto
	if a and not S.impactDone and not S.drawing and S.t >= a.impact then
		S.impactDone = true
		local at = predictHit(S.id)
		if at then
			S.stop = 0.06
			S.jolt, S.joltT = 1, 0
			play("faca_impacto", "impact_earth", 0.6, nil)
		end
	end
	S.joltT += dt
	local knifeOut = S.knifeUntil > now or S.drawing
	if not knifeOut and S.sheathe < 0 and model and a and a.weapon == "knife" and S.t >= a.recover then
		S.sheathe = 0
	end
	if S.sheathe >= 0 then
		S.sheathe += dt
		if S.sheathe >= Melee.SHEATHE_S then
			S.sheathe = -1
			S.id = ""
		end
	end
	local knifeShown = knifeOut or S.sheathe >= 0
	-- fuzil abaixado com a faca na mão
	local wantDown = if knifeShown and S.sheathe < Melee.SHEATHE_S * 0.6 then 1 else 0
	S.weight += (wantDown - S.weight) * math.min(1, dt / 0.09)
	local rifle = CFrame.identity:Lerp(LOWER, S.weight)
	local sw = swapWeight(now)
	if sw > 0 then
		rifle = rifle * CFrame.identity:Lerp(SWAP_DOWN, sw)
	end
	if a and RIFLE[S.id] then
		local p, r = eval(RIFLE[S.id], S.t)
		rifle = rifle * CFrame.new(p / M) * rot(r)
	end
	out.rifle = rifle
	-- câmera
	local py, rest = CFrame.identity, CFrame.identity
	if a and CAM[S.id] and S.t < 1.2 then
		local p, r = eval(CAM[S.id], S.t)
		py = CFrame.fromOrientation(math.rad(r.X), math.rad(r.Y), 0)
		rest = CFrame.new(p / M) * CFrame.Angles(0, 0, math.rad(r.Z))
	end
	if S.jolt > 0 then
		local j = math.exp(-S.joltT / 0.07)
		local shake = math.sin(S.joltT * 70) * 0.5 * j
		py *= CFrame.fromOrientation(math.rad(1.6 * j + shake), math.rad(shake * 0.6), 0)
		rest *= CFrame.new(0, 0, 0.015 / M * j)
		if j < 0.02 then
			S.jolt = 0
		end
	end
	applyCamera(py, rest)
	-- faca
	local m = if knifeShown then ensureModel() else model
	if not m then
		return out
	end
	if not (knifeShown and visible) then
		m:PivotTo(CFrame.new(0, -1e4, 0))
		out.active = false
		return out
	end
	out.active = true
	local cam = camera.CFrame
	local from = if handR0 then cam:PointToObjectSpace(handR0) * M else HIP.p
	local fromKey = k(0, from.X, from.Y, from.Z, 0, 0, 0, "io")
	local p, r
	if S.drawing then
		p, r = eval(DRAW, S.draw, fromKey)
	elseif S.sheathe >= 0 then
		local u = S.sheathe / Melee.SHEATHE_S
		if u < 0.6 then
			local e = ease(u / 0.6, "io")
			p, r = READY.p:Lerp(HIP.p, e), READY.r:Lerp(HIP.r, e)
		else
			local e = ease((u - 0.6) / 0.4, "io")
			p, r = HIP.p:Lerp(from, e), HIP.r:Lerp(Vector3.zero, e)
		end
	elseif a and STRIKE[S.id] then
		p, r = eval(STRIKE[S.id], S.t)
	else
		p, r = READY.p, READY.r
	end
	-- respiração da guarda e o peso da lâmina (atraso leve na rotação)
	local breath = math.sin(now * 1.7) * 0.004
	local kcf = cam * CFrame.new((p + Vector3.new(0, breath, 0)) / M) * rot(r)
	m:PivotTo(kcf)
	out.handR = kcf * Vector3.new(0, 0.006 / M, 0)
	out.handRot = kcf.Rotation
	out.wristR = kcf * Vector3.new(0, -0.012 / M, 0.075 / M)
	-- cotovelo: atrás e abaixo da mão; mais para trás com o braço estendido
	local ext = math.clamp((-p.Z - 0.34) / 0.3, 0, 1)
	local elbow = p + Vector3.new(0.1, -0.2, 0.3):Lerp(Vector3.new(0.06, -0.12, 0.32), ext)
	out.elbowR = cam * (elbow / M)
	return out
end

-- ===== baioneta no fuzil de 1ª pessoa =====
-- O fuzil de 1ª pessoa é ancorado e reposto a cada quadro pelo WeaponVisuals (PivotTo): a baioneta
-- vai DENTRO dele, posta uma vez na boca, e anda junto.
function KnifeView.bayonet(view: Model?, weaponId: string?)
	local char = player.Character
	local on = char ~= nil and char:GetAttribute("Bayonet") == true
	local bid = if weaponId then Melee.BAYONET[weaponId] else nil
	local cur = view and view:FindFirstChild("Baioneta")
	if not (view and on and bid) then
		if cur then
			cur:Destroy()
		end
		return
	end
	if cur then
		return
	end
	local primary = view.PrimaryPart
	local muzzle = primary and primary:FindFirstChild("Muzzle") :: Attachment?
	local b = KnifeModel.build(bid)
	if not (muzzle and b) then
		return
	end
	local bm = b :: Model
	bm.Name = "Baioneta"
	local pivot = bm:GetPivot()
	local cf: CFrame
	if bid == "m6" then
		local ring = pivot:PointToObjectSpace(KnifeModel.at(bm, "Ring"))
		cf = muzzle.WorldCFrame * CFrame.new(-ring)
	else
		local tip = pivot:PointToObjectSpace(KnifeModel.at(bm, "Tip"))
		cf = muzzle.WorldCFrame * CFrame.new(0, -0.03 / M, -0.16 / M) * CFrame.new(-tip)
	end
	bm:PivotTo(cf)
	for _, d in bm:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	bm.Parent = view
	play("baioneta_encaixe", "dry_click", 0.6, nil)
end

-- ===== som e efeito dos golpes de todos (servidor) =====
Net.event("Combat_Melee").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local mine = player.Character ~= nil and msg.by == player.Character
	if msg.k == "golpe" then
		local by = msg.by
		local root = if typeof(by) == "Instance" then by:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if root and not mine then
			if msg.draw then
				play("faca_saque", "bandage", 0.4, root.Position)
			end
			play("faca_corte", "", 0.4, root.Position)
		end
	elseif msg.k == "impacto" and type(msg.x) == "number" then
		local at = Vector3.new(msg.x, msg.y, msg.z)
		local dir = if type(msg.dx) == "number" then Vector3.new(msg.dx, msg.dy, msg.dz) else nil
		puff(at, msg.corpo == true, dir)
		if not (mine and os.clock() - lastLocalImpact < 0.5) then
			play("faca_impacto", "impact_earth", if msg.corpo then 0.6 else 0.35, at)
		end
		-- quem levou o golpe sente o tranco
		if player.Character ~= nil and msg.alvo == player.Character then
			S.jolt, S.joltT = 1, 0
		end
	end
end)

return KnifeView
