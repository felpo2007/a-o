--!strict
-- Animações do soldado com fuzil (Shared/SoldierAnims; captura da CMU retargetada no tools/anim).
-- Com os ids em 0 este script não faz NADA: fica o Animate padrão e as poses do PostureController.
-- Com os ids publicados:
-- 1. No próprio personagem (o Animator replica para todos):
--    - idle/walk/run do Animate passam a ser os do soldado (por baixo, em Core: cobrem as misturas);
--    - camada de locomoção (Movement): parado/andar/trote/correr misturados pela velocidade REAL do
--      HumanoidRootPart, em fase e na cadência em que o pé não escorrega; agachado e deitado pelos
--      atributos Crouched/Prone; sai suave no pulo, queda, nado, escada, assento, transpor e caído;
--    - camadas de cima (Action): recarregar ("reload_start", na duração do servidor) e granada
--      ("grenade_throw" ou o atributo Throwing).
-- 2. Em todo cliente, para cada personagem que toca os clipes (correções locais, depois do Animator):
--    - anula a dobra de perna do agachado do PostureController (C0 de quadris e joelhos), senão a
--      perna dobraria duas vezes; idem o giro do ombro do arremesso (FieldService);
--    - enquanto o HumanoidRootPart desce ou sobe na troca de postura, segura o corpo onde ele vai
--      chegar (os clipes agachados e deitados contam com o HRP já no lugar novo);
--    - pernas na direção do movimento (até 75°) e tronco na mira; de costas a passada volta;
--    - na recarga e no arremesso solta o IK da mão que sai do fuzil (VT65IK_L / VT65IK_R).
-- 3. SoldierAnims.BOTS: anima localmente os bots perto da câmera (desligado por padrão).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Joints = require(ReplicatedStorage.Shared.Joints)
local SoldierAnims = require(ReplicatedStorage.Shared.SoldierAnims)
local Bus = require(script.Parent.Bus)

if not SoldierAnims.enabled() then
	return
end

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = SoldierAnims.STUD_M
local CLIPS = SoldierAnims.CLIPS

-- ===== animações =====
local byId: { [string]: string } = {}
local animations: { [string]: Animation } = {}
for name, c in CLIPS do
	if c.id ~= 0 then
		local a = Instance.new("Animation")
		a.Name = "VT65_" .. name
		a.AnimationId = "rbxassetid://" .. c.id
		animations[name] = a
		byId[a.AnimationId] = name
	end
end

local INACTIVE: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Physics] = true, -- transpor (Movement.client)
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

-- ===== quem toca os clipes: o próprio personagem e, com BOTS, os bots perto =====
type Driver = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	sent: { [string]: number }, -- peso-alvo já mandado
	rate: { [string]: number }, -- velocidade de reprodução já mandada
	stance: string,
	active: boolean,
	moving: boolean,
	reversed: boolean,
	phase: number, -- ciclos de passada
	bot: boolean,
	throwAt: number,
	diveAt: number,
}
local drivers: { [Model]: Driver } = {}

local function loadTracks(hum: Humanoid): { [string]: AnimationTrack }?
	local found = hum:FindFirstChildOfClass("Animator")
	local animator: Animator
	if found then
		animator = found
	else
		animator = Instance.new("Animator") -- bot montado no servidor sem Animator: só local
		animator.Parent = hum
	end
	local tracks: { [string]: AnimationTrack } = {}
	for name, a in animations do
		local ok, tr = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if ok and tr then
			local c = CLIPS[name]
			tr.Priority = if c.layer == "upper" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Movement
			tr.Looped = c.loop
			tracks[name] = tr
		end
	end
	return tracks
end

-- idle/walk/run do Animate: os do soldado (o Animate os toca em Core, por baixo da nossa camada)
local ANIMATE_SETS: { [string]: string } = { idle = "parado", walk = "andar", run = "trote" }
local function swapAnimate(model: Model)
	local animate = model:WaitForChild("Animate", 5)
	if not animate then
		return
	end
	for set, clip in ANIMATE_SETS do
		local folder = animate:FindFirstChild(set)
		local a = animations[clip]
		if folder and a then
			for _, child in folder:GetChildren() do
				if child:IsA("Animation") and child.AnimationId ~= a.AnimationId then
					child.AnimationId = a.AnimationId
				end
			end
		end
	end
end

local function newDriver(model: Model, hum: Humanoid, root: BasePart, bot: boolean): Driver?
	local tracks = loadTracks(hum)
	if not tracks then
		return nil
	end
	return {
		model = model,
		hum = hum,
		root = root,
		tracks = tracks,
		sent = {},
		rate = {},
		stance = "stand",
		active = false,
		moving = false,
		reversed = false,
		phase = 0,
		bot = bot,
		throwAt = -10,
		diveAt = -10,
	}
end

local function isActive(d: Driver): boolean
	local hum = d.hum
	if hum.Health <= 0 or hum.SeatPart ~= nil or d.model:GetAttribute("Downed") == true then
		return false
	end
	if d.model:GetAttribute("Vaulting") == true then
		return false
	end
	if d.bot then
		return math.abs(d.root.AssemblyLinearVelocity.Y) < 12 -- no chão (estado do bot não replica)
	end
	return player:GetAttribute("Downed") ~= true and not INACTIVE[hum:GetState()]
end

-- fase atual (ciclos) de um clipe de passada que está tocando
local function trackPhase(name: string, tr: AnimationTrack): number
	local c = CLIPS[name]
	return tr.TimePosition / c.length * c.cycles
end

local function syncStart(d: Driver, name: string, tr: AnimationTrack)
	local c = CLIPS[name]
	if c.cycles <= 0 then
		return
	end
	local frac = d.phase % 1
	tr.TimePosition = math.clamp(frac * c.length / c.cycles, 0, c.length - 1e-3)
end

local function setWeight(d: Driver, name: string, w: number, fade: number)
	local tr = d.tracks[name]
	if not tr then
		return
	end
	local last = d.sent[name] or 0
	if w > 0 then
		if not tr.IsPlaying then
			tr:Play(fade, w, d.rate[name] or 1)
			syncStart(d, name, tr)
			d.sent[name] = w
		elseif math.abs(w - last) > 0.04 or (w >= 1 and last < 1) then
			tr:AdjustWeight(w, fade)
			d.sent[name] = w
		end
	elseif last > 0 then
		tr:Stop(fade)
		d.sent[name] = 0
	end
end

local function setRate(d: Driver, name: string, r: number)
	local tr = d.tracks[name]
	local last = d.rate[name]
	if tr and (last == nil or math.abs(r - last) > 0.03 * math.abs(last) or (r < 0) ~= (last < 0)) then
		tr:AdjustSpeed(r)
		d.rate[name] = r
	end
end

-- Fase da passada: com um clipe só, segue o que está tocando; na mistura de dois, o que sair mais
-- de 0,08 ciclo da fase comum é recolocado (raro: as velocidades já casam).
local function keepPhase(d: Driver, weights: { [string]: number }, f: number, dt: number)
	local gait: { string } = {}
	for name in weights do
		if CLIPS[name].cycles > 0 then
			table.insert(gait, name)
		end
	end
	if #gait == 1 then
		local tr = d.tracks[gait[1]]
		if tr and tr.IsPlaying then
			d.phase = trackPhase(gait[1], tr)
			return
		end
	end
	d.phase += f * dt * (if d.reversed then -1 else 1)
	if #gait < 2 then
		return
	end
	for _, name in gait do
		local tr = d.tracks[name]
		if tr and tr.IsPlaying then
			local diff = (trackPhase(name, tr) - d.phase) % 1
			if math.min(diff, 1 - diff) > 0.08 then
				syncStart(d, name, tr)
			end
		end
	end
end

local function stepDriver(d: Driver, dt: number)
	local model, root = d.model, d.root
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local speed = flat.Magnitude * M
	local stance = SoldierAnims.stanceOf(model:GetAttribute("Crouched") == true, model:GetAttribute("Prone") == true)
	local active = isActive(d)
	local weights, moving = SoldierAnims.targets({
		stance = stance,
		speed = speed,
		active = active,
		moving = d.moving,
	})
	-- tempo de mistura do que mudou neste quadro (postura > no ar/no chão > parado/andando)
	local fade = SoldierAnims.FADE_BLEND
	if moving ~= d.moving then
		fade = SoldierAnims.FADE_IDLE
	end
	if active ~= d.active then
		fade = if active then SoldierAnims.FADE_IN else SoldierAnims.FADE_OUT
	end
	if stance ~= d.stance then
		fade = SoldierAnims.fadeTime(d.stance, stance, os.clock() - d.diveAt < 1)
	end
	d.stance, d.active, d.moving = stance, active, moving
	-- de costas: a passada toca ao contrário (as pernas viram para o lado do movimento no pós)
	local _, back = SoldierAnims.legYaw(yawOf(root.CFrame.LookVector), yawOf(flat), speed)
	d.reversed = moving and back
	local f = SoldierAnims.cycleRate(weights, speed)
	for name, c in CLIPS do
		if c.layer == "loco" then
			if c.cycles > 0 then
				local r = SoldierAnims.trackSpeed(name, f)
				setRate(d, name, if d.reversed then -r else r)
			end
			setWeight(d, name, weights[name] or 0, fade)
		end
	end
	keepPhase(d, weights, f, dt)
end

local function playUpper(d: Driver, name: string, speed: number)
	local tr = d.tracks[name]
	if tr and d.hum.Health > 0 then
		tr:Play(0.12, 1, speed)
	end
end

-- ===== próprio personagem =====
local mine: Driver? = nil
local function watchOwn(char: Model)
	mine = nil
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not (hum and root) then
		return
	end
	hum:WaitForChild("Animator", 10)
	if player.Character ~= char then
		return
	end
	swapAnimate(char)
	local d = newDriver(char, hum, root, false)
	if not d then
		return
	end
	drivers[char] = d
	mine = d
	char:GetAttributeChangedSignal("Throwing"):Connect(function()
		if char:GetAttribute("Throwing") == true and os.clock() - d.throwAt > 1 then
			d.throwAt = os.clock()
			playUpper(d, "granada", 1)
		end
	end)
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then
			drivers[char] = nil
		end
	end)
end
player.CharacterAdded:Connect(watchOwn)
if player.Character then
	task.spawn(watchOwn, player.Character)
end

Bus.on("reload_start", function(dur: number)
	local d = mine
	if d and type(dur) == "number" then
		playUpper(d, "recarregar", SoldierAnims.reloadSpeed(dur))
	end
end)
Bus.on("grenade_throw", function()
	local d = mine
	if d then
		d.throwAt = os.clock()
		playUpper(d, "granada", 1)
	end
end)
Bus.on("vault_start", function(kind: string)
	local d = mine
	if d and kind == "dive" then
		d.diveAt = os.clock()
	end
end)

-- ===== bots (opcional) =====
local function botDriver(m: Model): Driver?
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root) then
		return nil
	end
	local d = newDriver(m, hum, root, true)
	if d then
		local dd = d :: Driver
		m:GetAttributeChangedSignal("Throwing"):Connect(function()
			if m:GetAttribute("Throwing") == true and drivers[m] == dd then
				playUpper(dd, "granada", 1)
			end
		end)
	end
	return d
end

local function refreshBots()
	local folder = workspace:FindFirstChild("Combatants")
	local near: { [Model]: boolean } = {}
	if folder then
		local cam = camera.CFrame.Position
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
				if r and (r.Position - cam).Magnitude < SoldierAnims.BOT_RADIUS then
					near[m] = true
				end
			end
		end
	end
	for m, d in drivers do
		if d.bot and not near[m] then
			for _, tr in d.tracks do
				tr:Stop(0.2)
			end
			drivers[m] = nil
		end
	end
	for m in near do
		if not drivers[m] then
			local d = botDriver(m)
			if d then
				drivers[m] = d
			end
		end
	end
end

-- ===== correções depois do Animator (todo personagem que toca os clipes) =====
type Watch = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	animator: Animator?,
	joints: { [string]: Instance },
	rest: { [string]: CFrame },
	crouch: { AnimationTrack },
	loco: { AnimationTrack },
	stanceOf: { [AnimationTrack]: string },
	reload: AnimationTrack?,
	throw: AnimationTrack?,
	lastHip: number,
	lagDH: number,
	lagY0: number,
	lagT0: number,
	yaw: number,
	ikTouched: boolean,
}
local watched: { [Model]: Watch } = {}
local JOINTS = { "Root", "Waist", "LeftHip", "RightHip", "LeftKnee", "RightKnee", "RightShoulder" }

local function newWatch(m: Model): Watch?
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root) then
		return nil
	end
	local w: Watch = {
		model = m,
		hum = hum,
		root = root,
		animator = hum:FindFirstChildOfClass("Animator"),
		joints = {},
		rest = {},
		crouch = {},
		loco = {},
		stanceOf = {},
		reload = nil,
		throw = nil,
		lastHip = hum.HipHeight,
		lagDH = 0,
		lagY0 = 0,
		lagT0 = -10,
		yaw = 0,
		ikTouched = false,
	}
	return w
end

-- junta e repouso (atributo RestC0 do Shared/Joints; o ombro só fora do arremesso)
local function joint(w: Watch, name: string): (Instance?, CFrame?)
	local j: Instance? = w.joints[name]
	if not j then
		local found = Joints.find(w.model, name)
		if not found then
			return nil, nil
		end
		w.joints[name] = found
		j = found
	end
	local inst = j :: Instance
	local rest: CFrame? = w.rest[name]
	if not rest and not (name == "RightShoulder" and w.model:GetAttribute("Throwing") == true) then
		local r = Joints.rest(inst)
		if r then
			w.rest[name] = r
			rest = r
		end
	end
	return inst, rest
end

-- quais clipes nossos tocam neste personagem (4 Hz)
local function scan(w: Watch)
	local animator = w.animator or w.hum:FindFirstChildOfClass("Animator")
	w.animator = animator
	table.clear(w.crouch)
	table.clear(w.loco)
	table.clear(w.stanceOf)
	w.reload, w.throw = nil, nil
	if not animator then
		return
	end
	for _, tr in animator:GetPlayingAnimationTracks() do
		local name = byId[tr.Animation and tr.Animation.AnimationId or ""]
		if name then
			local c = CLIPS[name]
			if c.layer == "loco" then
				table.insert(w.loco, tr)
				w.stanceOf[tr] = c.stance
				if c.stance == "crouch" then
					table.insert(w.crouch, tr)
				end
			elseif name == "recarregar" then
				w.reload = tr
			elseif name == "granada" then
				w.throw = tr
			end
		end
	end
end

local function playing(list: { AnimationTrack }): number
	local s = 0
	for _, tr in list do
		if tr.IsPlaying then
			s += tr.WeightCurrent
		end
	end
	return s
end

local function setTransform(j: Instance, cf: CFrame)
	(j :: any).Transform = cf
end
local function getTransform(j: Instance): CFrame
	return (j :: any).Transform
end

-- tira o C0 posto por outro script (A0 = repouso · D): Transform' = D⁻¹ · Transform
local function cancelC0(w: Watch, name: string)
	local j, rest = joint(w, name)
	if not (j and rest) then
		return
	end
	local cur = Joints.getC0(j)
	if cur and cur ~= rest then
		local dlt = rest:Inverse() * cur
		setTransform(j, dlt:Inverse() * getTransform(j))
	end
end

-- quanto o HRP ainda vai descer (< 0) ou subir depois de mudar o HipHeight
local function lagLeft(w: Watch): number
	local hip, y = w.hum.HipHeight, w.root.Position.Y
	local now = os.clock()
	if math.abs(hip - w.lastHip) > 0.05 then
		local left = if now - w.lagT0 < 0.8 then SoldierAnims.hipLag(w.lagDH, y - w.lagY0) else 0
		w.lagDH, w.lagY0, w.lagT0 = left + (hip - w.lastHip), y, now
		w.lastHip = hip
	end
	if now - w.lagT0 > 0.8 then
		return 0
	end
	return SoldierAnims.hipLag(w.lagDH, y - w.lagY0)
end

local B = SoldierAnims.BAKED
local PRONE_ROOT = CFrame.new(0, B.proneRoot.y, 0) * CFrame.Angles(math.rad(B.proneRoot.pitchDeg), 0, 0)

-- Root: cada clipe foi gravado contra a postura dele (HRP baixado bakedDrop; deitado, C0 com
-- PRONE_ROOT). Na mistura de posturas e enquanto o HRP desce, corrige para a postura de AGORA:
-- Transform' = sobe(lift) · D⁻¹ · Kmix · Transform, D = C0 atual relativo ao repouso.
local function rootFix(w: Watch, byStance: { [string]: number })
	local j, rest = joint(w, "Root")
	local c0 = j and Joints.getC0(j)
	if not (j and rest and c0) then
		return
	end
	local total = (byStance.stand or 0) + (byStance.crouch or 0) + (byStance.prone or 0)
	if total <= 1e-3 then
		return
	end
	local base = w.model:GetAttribute("BaseHipHeight")
	local baseHip = if type(base) == "number" then base else B.baseHip
	local actual = (baseHip - w.hum.HipHeight) + lagLeft(w)
	local lift = SoldierAnims.rootLift(byStance, actual)
	local kmix = CFrame.identity:Lerp(PRONE_ROOT, (byStance.prone or 0) / total)
	local dlt = rest:Inverse() * c0
	local fix = CFrame.new(c0:VectorToObjectSpace(Vector3.new(0, lift, 0))) * dlt:Inverse() * kmix
	if fix ~= CFrame.identity then
		setTransform(j, fix * getTransform(j))
	end
end

-- pernas para o lado do movimento, tronco na mira (de pé e agachado)
local function legYaw(w: Watch, dt: number, locoW: number)
	local target = 0
	if w.model:GetAttribute("Prone") ~= true then
		local v = w.root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		target = SoldierAnims.legYaw(yawOf(w.root.CFrame.LookVector), yawOf(flat), flat.Magnitude * M)
		target *= math.clamp(locoW, 0, 1)
	end
	w.yaw += (target - w.yaw) * (1 - math.exp(-dt / 0.15))
	if math.abs(w.yaw) < 1e-3 then
		return
	end
	local rootJ = joint(w, "Root")
	local waist = joint(w, "Waist")
	if rootJ and waist then
		setTransform(rootJ, CFrame.Angles(0, w.yaw, 0) * getTransform(rootJ))
		setTransform(waist, CFrame.Angles(0, -w.yaw, 0) * getTransform(waist))
	end
end

-- recarga solta a mão esquerda do fuzil; o arremesso, a direita
local function ikWeights(w: Watch)
	local rw = if w.reload and w.reload.IsPlaying then w.reload.WeightCurrent else 0
	local tw = if w.throw and w.throw.IsPlaying then w.throw.WeightCurrent else 0
	if rw <= 0 and tw <= 0 and not w.ikTouched then
		return
	end
	w.ikTouched = rw > 0 or tw > 0
	local l = w.hum:FindFirstChild("VT65IK_L") :: IKControl?
	local r = w.hum:FindFirstChild("VT65IK_R") :: IKControl?
	if l then
		l.Weight = 1 - math.clamp(rw, 0, 1)
	end
	if r then
		r.Weight = 1 - math.clamp(tw, 0, 1)
	end
end

local function post(w: Watch, dt: number)
	local byStance: { [string]: number } = {}
	local locoW = 0
	for _, tr in w.loco do
		if tr.IsPlaying then
			local st = w.stanceOf[tr] or "stand"
			byStance[st] = (byStance[st] or 0) + tr.WeightCurrent
			locoW += tr.WeightCurrent
		end
	end
	if playing(w.crouch) > 0 then
		for _, n in { "LeftHip", "RightHip", "LeftKnee", "RightKnee" } do
			cancelC0(w, n)
		end
	end
	if w.throw and w.throw.IsPlaying then
		cancelC0(w, "RightShoulder")
	end
	if locoW > 0 then
		rootFix(w, byStance)
		legYaw(w, dt, locoW)
	else
		w.lastHip = w.hum.HipHeight
	end
	ikWeights(w)
end

local function refreshWatched()
	local seen: { [Model]: boolean } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			seen[p.Character] = true
		end
	end
	for m, d in drivers do
		if d.bot then
			seen[m] = true
		end
	end
	for m in watched do
		if not seen[m] or not m.Parent then
			watched[m] = nil
		end
	end
	for m in seen do
		if not watched[m] and m.Parent then
			local w = newWatch(m)
			if w then
				for _, n in JOINTS do
					joint(w, n) -- guarda o repouso cedo, antes de qualquer pose
				end
				watched[m] = w
			end
		end
	end
end

-- ===== laços =====
local nextScan, nextList = 0, 0
RunService.PreAnimation:Connect(function(dt: number)
	local now = os.clock()
	if now >= nextList then
		nextList = now + 0.5
		if SoldierAnims.BOTS then
			refreshBots()
		end
		refreshWatched()
	end
	for m, d in drivers do
		if m.Parent and d.hum.Parent then
			stepDriver(d, dt)
		else
			drivers[m] = nil
		end
	end
end)

RunService.PreSimulation:Connect(function(dt: number)
	local now = os.clock()
	local rescan = now >= nextScan
	if rescan then
		nextScan = now + 0.25
	end
	for _, w in watched do
		if rescan then
			scan(w)
		end
		if #w.loco > 0 or w.reload or w.throw then
			post(w, dt)
		end
	end
end)
