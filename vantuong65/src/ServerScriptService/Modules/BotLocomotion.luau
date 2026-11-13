--!strict
-- Pernas dos bots (D-90; pedido do dono: "faça a movimentação dos bots linear como se fossem
-- jogadores reais"). O cérebro (BotService, BotSquads) pede "vá até lá, neste passo, olhando para
-- cá"; aqui, a cada quadro do servidor:
--   - segue o caminho por perseguição pura (Shared/BotMove), sem zigue-zague nem anda e para;
--   - velocidade com a inércia do jogador (Movement.accelStep) e o fator do chão (arrozal, mata,
--     riacho, rampa: Movement), o teto da postura e da perna ferida (Movement.serverSpeed);
--   - o corpo vira pela AlignOrientation "BotFacing" com o giro limitado pelo passo (AutoRotate
--     desligado): anda de lado mirando, e parado sem mira não gira;
--   - caminho: trecho curto em linha reta (1 raio no joelho) ou PathfindingService com o rótulo do
--     arrozal (BotWorld); fila com no máximo 2 cálculos ao mesmo tempo no servidor;
--   - desvio local (raio do joelho a cada 0,25 s, só no trecho reto), pulo onde o caminho pede e
--     "preso": pula, recalcula, sai de lado e, se nada der, avisa o cérebro (status "failed").
-- WalkSpeed é a velocidade real (as animações da D-88 leem a velocidade e a postura dos bots).
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local BotMove = require(ReplicatedStorage.Shared.BotMove)
local Movement = require(ReplicatedStorage.Shared.Movement)
local BotWorld = require(script.Parent.BotWorld)

local Loco = {}
local M = 0.28
local MOVE = BotBrain.MOVE

local GAIT_SPEED: { [string]: number } = {
	walk = Movement.WALK,
	jog = Movement.JOG,
	sprint = Movement.SPRINT,
	ads = Movement.ADS,
	crouch = Movement.CROUCH,
	prone = Movement.PRONE,
}

export type State = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	align: AlignOrientation,
	body: BotMove.Body,
	mode: string, -- "idle" | "path" | "direct"
	dest: Vector3?,
	final: boolean,
	gait: string,
	faceAt: Vector3?,
	path: BotMove.Path?,
	follow: BotMove.Follow,
	token: number,
	pending: boolean,
	reqAt: number,
	wantReq: Vector3?, -- pedido de caminho esperando a vez (intervalo mínimo)
	stuck: BotMove.Stuck,
	unstick: number,
	okSince: number,
	lastPos: Vector3,
	jumpAt: number,
	rayAt: number,
	avoidX: number,
	avoidZ: number,
	avoidUntil: number,
	surfAt: number,
	factor: number,
	grip: number,
	waterM: number,
	setSpeed: number,
	setYaw: number,
	moveDir: Vector3,
	status: string, -- "idle" | "moving" | "arrived" | "failed"
	leftM: number,
	pathObj: Path?,
	sprinting: boolean,
	slowT: number,
	faction: string?, -- o VC anda 12% mais rápido (Movement.factionSpeed, D-93)
	waterMode: string, -- Movement.waterMode: "dry" | "wade" | "swim"
	swimOn: boolean, -- estado Swimming do Humanoid ligado
}

local states: { [any]: State } = {}

-- Agente do PathfindingService: soldado de 2,0 m (7,14 studs; D-98, Shared/Corpo), com folga; ombros
-- ~0,45 m. Era 6,5 studs (corpo de 1,75 m).
local AGENT = {
	AgentRadius = 1.6,
	AgentHeight = 7.3,
	AgentCanJump = true,
	AgentCanClimb = false,
	WaypointSpacing = 6,
	Costs = {
		[BotWorld.PADDY_LABEL] = 4, -- PLACEHOLDER: lâmina d'água do arrozal (o dique sai mais barato)
		Water = 12,
		Mud = 2.5,
	},
}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

-- Ignora gente (bots e jogadores), armas caídas e fumaça nos raios do joelho
function Loco.setIgnore(list: { Instance })
	rayParams.FilterDescendantsInstances = list
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function stanceOf(model: Model): string
	if model:GetAttribute("Prone") then
		return "prone"
	elseif model:GetAttribute("Crouched") then
		return "crouch"
	end
	return "stand"
end

local function yawOf(cf: CFrame): number
	local _, y, _ = cf:ToOrientation()
	return y
end

local function straight(a: Vector3, b: Vector3): BotMove.Path
	return BotMove.path({ { x = a.X, z = a.Z, y = a.Y }, { x = b.X, z = b.Z, y = b.Y } })
end

-- Raio do joelho de `from` na direção (dx, dz) até len studs: bate em algo sólido?
local function kneeHit(root: BasePart, dx: number, dz: number, len: number): boolean
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1e-4 then
		return false
	end
	local o = root.Position - Vector3.new(0, 1.9, 0)
	return workspace:Raycast(o, Vector3.new(dx / l * len, 0, dz / l * len), rayParams) ~= nil
end

---------------------------------------------------------------------------------------------
-- Fila do PathfindingService
---------------------------------------------------------------------------------------------
type Req = { st: State, token: number, from: Vector3, to: Vector3 }
local queue: { Req } = {}
local running = 0

local function compute(st: State, from: Vector3, to: Vector3): { BotMove.Point }?
	local path = st.pathObj
	if not path then
		path = PathfindingService:CreatePath(AGENT)
		st.pathObj = path
	end
	local p = path :: Path
	p:ComputeAsync(from, to)
	if p.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local pts: { BotMove.Point } = {}
	for _, w in p:GetWaypoints() do
		table.insert(pts, {
			x = w.Position.X,
			z = w.Position.Z,
			y = w.Position.Y,
			jump = w.Action == Enum.PathWaypointAction.Jump,
		})
	end
	return pts
end

local function deliver(st: State, token: number, pts: { BotMove.Point }?)
	if st.token ~= token then
		return -- pedido velho (o cérebro já mandou ir para outro lugar)
	end
	st.pending = false
	local dest = st.dest
	if not dest then
		return
	end
	if pts and #pts >= 2 then
		st.path = BotMove.path(BotMove.simplify(pts, 4, 1.5))
		st.follow = BotMove.newFollow()
		st.mode = "path"
	else
		-- sem caminho (água funda, cercado): vai reto, com o desvio local
		st.path = straight(st.root.Position, dest)
		st.follow = BotMove.newFollow()
		st.mode = "direct"
	end
end

local pump: () -> ()
pump = function()
	while running < MOVE.pathConcurrent and #queue > 0 do
		local req = table.remove(queue, 1) :: Req
		if req.st.token ~= req.token or not req.st.model.Parent then
			continue
		end
		running += 1
		task.spawn(function()
			local ok, pts = pcall(compute, req.st, req.from, req.to)
			running -= 1
			deliver(req.st, req.token, if ok then pts else nil)
			pump()
		end)
	end
end

local function request(st: State, to: Vector3, now: number)
	if now - st.reqAt < MOVE.pathEveryS then
		st.wantReq = to -- vai na vez dele
		return
	end
	st.wantReq = nil
	st.reqAt = now
	st.token += 1
	st.pending = true
	for i = #queue, 1, -1 do
		if queue[i].st == st then
			table.remove(queue, i)
		end
	end
	table.insert(queue, { st = st, token = st.token, from = st.root.Position, to = to })
	pump()
end

---------------------------------------------------------------------------------------------
-- API do cérebro
---------------------------------------------------------------------------------------------

function Loco.attach(bot: any, model: Model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root) then
		return
	end
	hum.AutoRotate = false
	local att = Instance.new("Attachment")
	att.Name = "BotFacing"
	att.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "BotFacing"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = false
	ao.Responsiveness = 60
	ao.MaxTorque = 1e7
	ao.MaxAngularVelocity = math.huge
	local yaw = yawOf(root.CFrame)
	ao.CFrame = CFrame.Angles(0, yaw, 0)
	ao.Parent = root
	states[bot] = {
		model = model,
		hum = hum,
		root = root,
		align = ao,
		body = { vx = 0, vz = 0, yaw = yaw },
		mode = "idle",
		dest = nil,
		final = true,
		gait = "jog",
		faceAt = nil,
		path = nil,
		follow = BotMove.newFollow(),
		token = 0,
		pending = false,
		reqAt = -math.huge,
		wantReq = nil,
		stuck = BotMove.newStuck(),
		unstick = 0,
		okSince = os.clock(),
		lastPos = root.Position,
		jumpAt = 0,
		rayAt = 0,
		avoidX = 0,
		avoidZ = 0,
		avoidUntil = 0,
		surfAt = 0,
		factor = 1,
		grip = 1,
		waterM = 0,
		setSpeed = -1,
		setYaw = yaw,
		moveDir = Vector3.zero,
		status = "idle",
		leftM = 0,
		pathObj = nil,
		sprinting = false,
		slowT = 0,
		faction = if type(bot.faction) == "string" then bot.faction else nil,
		waterMode = "dry",
		swimOn = true,
	}
	bot.loco = states[bot]
end

function Loco.detach(bot: any)
	local st = states[bot]
	if st then
		st.token += 1
		states[bot] = nil
	end
	bot.loco = nil
end

export type GoOpts = {
	direct: boolean?, -- trecho curto: reto (sem PathfindingService) se o joelho passa
	final: boolean?, -- false: ponto de passagem (não freia no fim; o próximo trecho vem antes)
	face: Vector3?, -- mira: o corpo olha para cá e anda de lado
	keep: boolean?, -- continua no caminho atual enquanto o novo é calculado
	tolerance: number?, -- studs: destino "igual" ao atual (não pede de novo)
}

-- Vá até dest no passo `gait` ("walk", "jog", "sprint", "ads", "crouch", "prone").
function Loco.go(bot: any, dest: Vector3, gait: string, opts: GoOpts?)
	local st = states[bot]
	if not st then
		return
	end
	local o: GoOpts = opts or {}
	st.gait = gait
	st.final = o.final ~= false
	st.faceAt = o.face
	local tol = o.tolerance or 1.5 / M
	local cur = st.dest
	local pos = st.root.Position
	if cur and flat(cur, dest) < tol then
		-- mesmo destino: andando, segue; já chegou, fica (sem refazer caminho nem gastar raio)
		if st.mode ~= "idle" and st.status == "moving" then
			return
		elseif st.status == "arrived" and flat(pos, dest) * M <= MOVE.arriveM * 2 then
			return
		end
	end
	local now = os.clock()
	if st.status == "failed" then
		st.unstick = 0 -- pedido novo depois de desistir: começa a contar de novo
	end
	st.dest = dest
	st.status = "moving"
	local d = flat(pos, dest)
	local short = o.direct == true or d <= MOVE.directM / M
	if short and not kneeHit(st.root, dest.X - pos.X, dest.Z - pos.Z, math.min(d, MOVE.directM / M)) then
		st.token += 1
		st.pending = false
		st.wantReq = nil
		st.mode = "direct"
		st.path = straight(pos, dest)
		st.follow = BotMove.newFollow()
		return
	end
	if not (o.keep and st.path and st.mode == "path" and not st.follow.done) then
		-- enquanto o caminho é calculado, segue reto (com desvio): não fica parado esperando
		st.mode = "direct"
		st.path = straight(pos, dest)
		st.follow = BotMove.newFollow()
	end
	request(st, dest, now)
end

-- Destino longe (mais que um trecho): vai por trechos de legM na direção dele, sem pedir ao
-- PathfindingService um caminho de centenas de metros de uma vez.
function Loco.goFar(bot: any, dest: Vector3, gait: string, opts: GoOpts?)
	local st = states[bot]
	if not st then
		return
	end
	local pos = st.root.Position
	local leg = MOVE.legM / M
	if flat(pos, dest) <= leg then
		Loco.go(bot, dest, gait, opts)
		return
	end
	local o: GoOpts = table.clone(opts or {}) :: any
	o.final = false
	o.keep = true
	o.tolerance = math.max(o.tolerance or 0, 12 / M)
	local dir = Vector3.new(dest.X - pos.X, 0, dest.Z - pos.Z).Unit
	-- pede o trecho seguinte quando o atual está acabando
	local cur = st.dest
	if cur and st.status == "moving" and st.leftM > MOVE.prefetchM and flat(cur, dest) > 1 then
		st.gait = gait
		return
	end
	Loco.go(bot, pos + dir * leg, gait, o)
end

-- Para (freando) e, se pedido, olha para `face`.
function Loco.stop(bot: any, face: Vector3?)
	local st = states[bot]
	if not st then
		return
	end
	st.token += 1
	st.pending = false
	st.wantReq = nil
	st.mode = "idle"
	st.dest = nil
	st.path = nil
	st.faceAt = face
	if st.status == "moving" then
		st.status = "idle"
	end
end

-- Olha para pos (mira) ou, com nil, para onde anda.
function Loco.face(bot: any, pos: Vector3?)
	local st = states[bot]
	if st then
		st.faceAt = pos
	end
end

function Loco.status(bot: any): string
	local st = states[bot]
	return if st then st.status else "idle"
end

function Loco.dest(bot: any): Vector3?
	local st = states[bot]
	return if st then st.dest else nil
end

-- metros que faltam no caminho atual
function Loco.left(bot: any): number
	local st = states[bot]
	return if st and st.mode ~= "idle" then st.leftM else 0
end

function Loco.speed(bot: any): number
	local st = states[bot]
	return if st then math.sqrt(st.body.vx ^ 2 + st.body.vz ^ 2) else 0
end

-- Ângulo (rad) entre a frente do corpo e pos
function Loco.facingError(bot: any, pos: Vector3): number
	local st = states[bot]
	if not st then
		return 0
	end
	local p = st.root.Position
	local want = BotMove.yawTo(pos.X - p.X, pos.Z - p.Z)
	return math.abs(BotMove.wrap(want - st.body.yaw))
end

function Loco.yaw(bot: any): number
	local st = states[bot]
	return if st then st.body.yaw else 0
end

-- Vira o corpo na hora e zera o embalo (só depois de teleporte: sair do túnel, cena do Studio)
function Loco.setYaw(bot: any, yaw: number)
	local st = states[bot]
	if st then
		st.body.yaw = yaw
		st.body.vx, st.body.vz = 0, 0
		st.setYaw = yaw
		st.align.CFrame = CFrame.Angles(0, yaw, 0)
		st.lastPos = st.root.Position
	end
end

---------------------------------------------------------------------------------------------
-- Passo de cada quadro
---------------------------------------------------------------------------------------------

local function unstick(st: State, now: number)
	st.unstick += 1
	local dest = st.dest
	if not dest then
		return
	end
	if st.unstick == 1 and stanceOf(st.model) == "stand" then
		st.hum.Jump = true
		st.jumpAt = now + 1
	end
	if st.unstick == 2 then
		-- sai de lado por um instante
		local a = st.body.yaw + (if math.random() < 0.5 then 1 else -1) * math.pi / 2
		st.avoidX, st.avoidZ = -math.sin(a), -math.cos(a)
		st.avoidUntil = now + 0.8
	end
	if st.unstick >= 5 then
		st.status = "failed"
		st.mode = "idle"
		st.path = nil
		st.dest = nil
		st.token += 1
		return
	end
	st.reqAt = -math.huge
	request(st, dest, now)
end

local function stepOne(st: State, dt: number, now: number)
	local model, hum, root = st.model, st.hum, st.root
	if not model.Parent or hum.Health <= 0 or root.Anchored then
		return
	end
	if hum.SeatPart then
		if st.align.Enabled then
			st.align.Enabled = false
		end
		st.body.vx, st.body.vz = 0, 0
		return
	elseif not st.align.Enabled then
		st.align.Enabled = true
		local y = yawOf(root.CFrame)
		st.body.yaw, st.setYaw = y, y
		st.align.CFrame = CFrame.Angles(0, y, 0)
	end
	local pos = root.Position
	if model:GetAttribute("Downed") then
		if st.setSpeed ~= 0 then
			st.setSpeed = 0
			hum:Move(Vector3.zero, false)
			st.moveDir = Vector3.zero
		end
		st.body.vx, st.body.vz = 0, 0
		return
	end
	-- pedido de caminho que esperava a vez
	local wq = st.wantReq
	if wq and now - st.reqAt >= MOVE.pathEveryS then
		request(st, wq, now)
	end
	-- chão (a cada 0,5 s): superfície, água e rampa no rumo de marcha
	if now >= st.surfAt then
		st.surfAt = now + 0.5
		local surface, waterM = BotWorld.surface(pos)
		local sp = math.sqrt(st.body.vx ^ 2 + st.body.vz ^ 2)
		local grade = 0
		if sp > 0.3 then
			local ux, uz = st.body.vx / sp, st.body.vz / sp
			local a = BotWorld.heightAt(pos.X, pos.Z)
			local b = BotWorld.heightAt(pos.X + ux * 2 / M, pos.Z + uz * 2 / M)
			grade = (b - a) / (2 / M)
		end
		local rain = ReplicatedStorage:GetAttribute("Rain")
		st.factor = BotBrain.groundFactor(surface, if type(rain) == "number" then rain else 0, waterM, grade)
		st.grip = Movement.surfaceGrip(surface)
		st.waterM = waterM
		-- água: vadeando (riacho, raso), o Humanoid não entra em Swimming, como o jogador
		-- (Movement.client): o bot anda no fundo em vez de boiar e alternar nadar e andar
		local mode = Movement.waterMode(st.waterMode, if surface == "water" then waterM else 0)
		st.waterMode = mode
		local swimOn = mode ~= "wade"
		if swimOn ~= st.swimOn then
			st.swimOn = swimOn
			hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, swimOn)
		end
		if not swimOn and hum:GetState() == Enum.HumanoidStateType.Swimming then
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end
	end
	local stance = stanceOf(model)
	local leg = model:GetAttribute("LegImpaired") == true
	local gait = st.gait
	if stance ~= "stand" then
		gait = stance
	end
	-- lado (D-93): o VC anda, trota, corre e anda agachado 12% mais rápido; mira e rastejo, iguais
	local cap = Movement.serverSpeed(stance, gait == "sprint", leg, false, st.faction)
	local sideK = if gait == "ads" or gait == "prone" then 1 else Movement.factionSpeed(st.faction)
	local want = math.min((GAIT_SPEED[gait] or Movement.JOG) * sideK, cap) * st.factor
	local dirX, dirZ, speed = 0, 0, 0
	local curSpeed = math.sqrt(st.body.vx ^ 2 + st.body.vz ^ 2)
	local path = st.path
	if st.mode ~= "idle" and path then
		local left
		dirX, dirZ, speed, left = BotMove.follow(st.follow, path, pos.X, pos.Z, curSpeed, want, st.final)
		st.leftM = left
		if st.follow.done then
			-- chegou (pelo caminho calculado ou pelo reto, enquanto ele era calculado): o pedido
			-- pendente perde a vez
			st.mode = "idle"
			st.path = nil
			st.status = "arrived"
			st.token += 1
			st.pending = false
			st.wantReq = nil
		end
		-- desvio local no trecho reto: raio do joelho a cada 0,25 s
		if st.mode == "direct" and speed > 0 and now >= st.rayAt then
			st.rayAt = now + 0.25
			if now >= st.avoidUntil and kneeHit(root, dirX, dirZ, 2.5 / M) then
				local base = BotMove.yawTo(dirX, dirZ)
				local found = false
				for _, off in { 35, -35, 70, -70 } do
					local a = base + math.rad(off)
					local ax, az = -math.sin(a), -math.cos(a)
					if not kneeHit(root, ax, az, 2.5 / M) then
						st.avoidX, st.avoidZ, st.avoidUntil = ax, az, now + 0.6
						found = true
						break
					end
				end
				if not found and st.dest then
					request(st, st.dest :: Vector3, now) -- reto não dá: pede caminho
				end
			end
		end
		-- pulo onde o caminho pede (dique, mureta)
		if st.mode == "path" and stance == "stand" and now >= st.jumpAt then
			if BotMove.jumpAhead(path, st.follow.s, 2.2 / M) then
				hum.Jump = true
				st.jumpAt = now + 1
			end
		end
	end
	if now < st.avoidUntil and speed > 0 then
		dirX, dirZ = st.avoidX, st.avoidZ
	end
	-- corpo: velocidade com inércia e giro limitado
	local face = st.faceAt
	local faceYaw = if face then BotMove.yawTo(face.X - pos.X, face.Z - pos.Z) else nil
	local gname = if curSpeed < 0.3 then "still" else gait
	BotMove.step(st.body, {
		dirX = dirX,
		dirZ = dirZ,
		speed = speed,
		faceYaw = faceYaw,
		turn = BotMove.turnRate(gname, face ~= nil),
		grip = st.grip,
	}, dt)
	-- parede, barranco, outro soldado: a velocidade comandada cai para a real
	local real = root.AssemblyLinearVelocity
	local realM = Vector3.new(real.X, 0, real.Z).Magnitude * M
	local cmd = math.sqrt(st.body.vx ^ 2 + st.body.vz ^ 2)
	if cmd > 1 and realM < cmd * 0.4 then
		st.slowT += dt
		if st.slowT > 0.3 then
			local k = math.max(realM / cmd, 0.3)
			st.body.vx *= k
			st.body.vz *= k
		end
	else
		st.slowT = 0
	end
	-- aplica no Humanoid (só quando muda: menos rede)
	cmd = math.sqrt(st.body.vx ^ 2 + st.body.vz ^ 2)
	local ws = cmd / M
	if
		math.abs(ws - st.setSpeed) > 0.12
		or (ws < 1e-3) ~= (st.setSpeed < 1e-3)
		or math.abs(hum.WalkSpeed - st.setSpeed) > 0.05
	then
		hum.WalkSpeed = ws
		st.setSpeed = ws
	end
	local dir = if cmd > 1e-3 then Vector3.new(st.body.vx / cmd, 0, st.body.vz / cmd) else Vector3.zero
	if (dir - st.moveDir).Magnitude > 0.01 then
		hum:Move(dir, false)
		st.moveDir = dir
	end
	if math.abs(BotMove.wrap(st.body.yaw - st.setYaw)) > 0.002 then
		st.align.CFrame = CFrame.Angles(0, st.body.yaw, 0)
		st.setYaw = st.body.yaw
	end
	-- corrida: o atributo acompanha o passo real (outros sistemas leem)
	local sprinting = gait == "sprint" and stance == "stand" and cmd > Movement.SPRINT_COUNT_MPS
	if sprinting ~= st.sprinting then
		st.sprinting = sprinting
		if (model:GetAttribute("Sprinting") == true) ~= sprinting then
			model:SetAttribute("Sprinting", sprinting)
		end
	end
	-- preso?
	local moved = flat(pos, st.lastPos) * M
	st.lastPos = pos
	if BotMove.stuckStep(st.stuck, dt, if st.mode ~= "idle" then cmd * dt else 0, moved) then
		unstick(st, now)
	elseif st.mode ~= "idle" and realM > 0.8 then
		if now - st.okSince > 3 then
			st.unstick = 0
		end
	else
		st.okSince = now
	end
end

function Loco.start()
	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		dt = math.min(dt, 0.1)
		for _, st in states do
			local ok, err = pcall(function(): any
				stepOne(st, dt, now)
				return nil
			end)
			if not ok then
				warn("[VT65] bots: passo falhou:", err)
			end
		end
	end)
end

return Loco
