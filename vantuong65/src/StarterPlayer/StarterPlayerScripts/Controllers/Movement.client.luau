--!strict
-- Movimento da infantaria no cliente (pedido do dono, 2026-11-11: "a melhor movimentação possível").
-- Toda a matemática e os números ficam em Shared/Movement (puro, testado). Aqui:
-- - inércia: o pedido de movimento (teclado ou analógico, já com a zona morta da camada Input) vira
--   uma velocidade que acelera e freia aos poucos; o WalkSpeed local acompanha essa velocidade. O
--   servidor continua mandando o teto pela postura (MedicalService.apply) e este script não passa dele;
-- - fôlego: a corrida cansa (mais com peso, subida, lama, arrozal e água) e recupera parado;
--   sem fôlego a corrida para, só volta acima de 35%, e a mira de ferro balança mais;
-- - chão: lama do arrozal (PaddyWater), lama, areia, chão de mata, água do riacho pela fundura, rampa;
--   a chuva (atributo "Rain") enlameia o chão mole;
-- - pulo baixo (0,45 m descansado, 0,2 m cansado, menos com peso), com intervalo e gasto de fôlego;
--   agachado ou deitado, o botão de pulo levanta;
-- - transpor/escalar (A / Espaço perto de dique, cerca, sacos de areia ou mureta até 1,25 m);
-- - mergulho para deitado correndo (InfantryController pede pelo Bus "dive");
-- - câmera: inclinar, postura com transição suave (deitar ~0,8 s, levantar ~1 s), balanço do passo e da
--   respiração sutis, afundada na aterrissagem (via Humanoid.CameraOffset, antes da câmera).
-- Atributos locais (não replicam): Stamina (0..1), Exhausted, StanceBusy (deitando/levantando),
-- Vaulting. Veículo: nada muda.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = require(ReplicatedStorage.Shared.Kit)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ViewMode = require(script.Parent.ViewMode)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = Movement.STUD_M
local PRONE_EYE = -1.6 -- studs: câmera de quem está de bruços (~0,3 m do chão; antes no InfantryController)
local LEAN = 0.35 / M -- inclinar: câmera 0,35 m para o lado (D-42)

-- ===== estado =====
local stamina = Movement.newStamina()
local vel = Vector3.zero -- velocidade horizontal comandada (studs/s)
local inputMag = 0
local lastFilter = 0
local loadKg = 20
local spareMags: number? = nil
local probe = { surface = "firm", waterM = 0, normal = Vector3.yAxis, nextAt = 0 }
local jumpEnabled: boolean? = nil
local jumpReadyAt = 0
local air = { active = false, maxY = 0, credit = 0 }
local slow = { factor = 1, untilT = 0, total = 0 }
local land = { t0 = -10, dip = 0 }
local dive: { t0: number, dir: Vector3, v0: number }? = nil
local sprintIdle = 0
local stopAt = 0

type VaultRun = {
	kind: string,
	t0: number,
	dur: number,
	fwd: Vector3,
	p0: Vector3,
	pa: Vector3, -- encostado na face, já em cima
	p2: Vector3, -- do outro lado (ou em cima)
	overY: number,
	split: number,
}
local vault: VaultRun? = nil

-- câmera
local camState = {
	stance = "stand",
	lastHip = -1,
	t0 = 0,
	T = 0,
	dH = 0,
	rootY0 = 0,
	carry = 0,
	extraFrom = 0,
	extraTo = 0,
	active = false,
	prone = false, -- transição envolve deitar/levantar
	lean = 0,
	phase = 0,
	breathT = 0,
}

local attrCache: { [string]: any } = {}
local function setAttr(name: string, v: any)
	if attrCache[name] ~= v then
		attrCache[name] = v
		player:SetAttribute(name, v)
	end
end

local function body(): (Model?, Humanoid?, BasePart?)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if c and h and r and h.Health > 0 then
		return c, h, r
	end
	return nil, nil, nil
end

local function stanceOf(char: Model): string
	return if char:GetAttribute("Prone") == true
		then "prone"
		elseif char:GetAttribute("Crouched") == true then "crouch"
		else "stand"
end

local function flatLook(): Vector3
	local cf = camera.CFrame
	local f = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if f.Magnitude < 1e-3 then
		f = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z)
	end
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

local function num(v: any, default: number): number
	return if type(v) == "number" then v else default
end

-- ===== peso =====
Net.event("Combat_Ammo").OnClientEvent:Connect(function(a: any)
	if type(a) == "table" and type(a.spare) == "number" then
		spareMags = math.max(a.spare, 0)
	end
end)

local function computeLoad(): number
	local slots = string.split(tostring(player:GetAttribute("Loadout") or ""), ",")
	local carried = player:GetAttribute("CarriedWeapon")
	if type(carried) == "string" and #slots > 0 then
		slots[1] = carried
	end
	local kg, kind = 0, "rifle"
	for i, id in slots do
		local wp = Weapons.get(id)
		if wp then
			kg += wp.massLoadedKg
			if i == 1 then
				kind = wp.kind
			end
		end
	end
	-- + equipamento liberado (D-72): carregadores a mais e o peso fixo (colete, cantil)
	local spare = spareMags
		or (
			num(player:GetAttribute("KitMags"), Kit.DEFAULT_MAGS[kind] or 3)
			+ num(player:GetAttribute("GearMags"), 0)
			- 1
		)
	kg += num(player:GetAttribute("GearKg"), 0)
	return Movement.loadKg({
		weaponsKg = kg,
		magKg = Kit.MAG_KG[kind] or 0.75,
		mags = spare,
		frags = num(player:GetAttribute("Frags"), 2),
		smokes = num(player:GetAttribute("Smokes"), 1),
		bandages = num(player:GetAttribute("KitBandages"), 2),
		role = tostring(player:GetAttribute("Role") or ""),
	})
end

-- ===== sonda do chão (10 Hz): material, água e rampa =====
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.FilterDescendantsInstances = { workspace.Terrain }
waterParams.IgnoreWater = false

local function ignoreList(char: Model): { Instance }
	local list: { Instance } = { char, camera }
	local fx = workspace:FindFirstChild("VT65Effects")
	if fx then
		table.insert(list, fx)
	end
	return list
end

local function doProbe(char: Model, hum: Humanoid, root: BasePart)
	local list = ignoreList(char)
	groundParams.FilterDescendantsInstances = list
	local feetDrop = hum.HipHeight + root.Size.Y / 2
	local hit: RaycastResult? = nil
	for _ = 1, 4 do
		local r = workspace:Raycast(root.Position, Vector3.new(0, -(feetDrop + 3), 0), groundParams)
		if not r then
			break
		end
		local inst = r.Instance
		if inst ~= workspace.Terrain and not inst.CanCollide and inst:GetAttribute("Material") ~= "PaddyWater" then
			table.insert(list, inst) -- folhagem sem colisão: não é chão
			groundParams.FilterDescendantsInstances = list
			continue
		end
		hit = r
		break
	end
	if hit then
		local attr = hit.Instance:GetAttribute("Material")
		probe.surface =
			Movement.surfaceOf(hit.Material.Name, if type(attr) == "string" then attr else nil, hit.Instance.Name)
		probe.normal = if attr == "PaddyWater" or hit.Normal.Y < 0.1 then Vector3.yAxis else hit.Normal
	else
		probe.surface, probe.normal = "firm", Vector3.yAxis
	end
	local feetY = root.Position.Y - feetDrop
	local w = workspace:Raycast(root.Position + Vector3.new(0, 4, 0), Vector3.new(0, -(feetDrop + 7), 0), waterParams)
	probe.waterM = if w and w.Material == Enum.Material.Water then math.max((w.Position.Y - feetY) * M, 0) else 0
end

-- rampa (m/m) na direção horizontal d, a partir da normal do chão
local function gradeAlong(d: Vector3): number
	local n = probe.normal
	if d.Magnitude < 1e-3 or n.Y < 0.1 then
		return 0
	end
	local u = d.Unit
	return -(n.X * u.X + n.Z * u.Z) / n.Y
end

-- ===== transição de postura =====
local function stanceBusy(): boolean
	return camState.active and camState.prone
end

-- ===== filtro de movimento (camada Input: zona morta já aplicada) =====
local function setWalk(hum: Humanoid, studs: number)
	if math.abs(hum.WalkSpeed - studs) > 0.01 then
		hum.WalkSpeed = studs
	end
end

Input.setMoveFilter(function(vec: Vector3, rel: boolean): (Vector3, boolean)
	local now = os.clock()
	local dt = math.clamp(now - lastFilter, 0, 0.1)
	lastFilter = now
	local char, hum, root = body()
	if not (char and hum and root) or hum.SeatPart ~= nil then
		vel = Vector3.zero
		return vec, rel
	end
	local c, h, r = char :: Model, hum :: Humanoid, root :: BasePart
	-- pedido no mundo (o PlayerModule manda relativo à câmera)
	local fwd = flatLook()
	local world = vec
	if rel then
		local right = Vector3.new(-fwd.Z, 0, fwd.X)
		world = right * vec.X + fwd * -vec.Z
	end
	world = Vector3.new(world.X, 0, world.Z)
	inputMag = math.min(world.Magnitude, 1)
	local dir = if world.Magnitude > 1e-3 then world.Unit else Vector3.zero
	if vault then
		return Vector3.zero, false -- o transpor conduz o corpo
	end
	local d = dive
	if d then
		local s = Movement.diveSpeed(d.v0, now - d.t0)
		vel = d.dir * (s / M)
		if s < 0.05 then
			return Vector3.zero, false
		end
		setWalk(h, s / M)
		return d.dir, false
	end
	local st = stanceOf(c)
	local grounded = h.FloorMaterial ~= Enum.Material.Air
	local rain = ReplicatedStorage:GetAttribute("Rain")
	local target = Movement.targetSpeed({
		stance = st,
		sprinting = c:GetAttribute("Sprinting") == true,
		aiming = player:GetAttribute("Aiming") == true,
		downed = player:GetAttribute("Downed") == true,
		legImpaired = c:GetAttribute("LegImpaired") == true,
		forward = if inputMag > 0 then dir:Dot(fwd) else 1,
		stamina = stamina.value,
		loadKg = loadKg,
		surface = probe.surface,
		waterM = probe.waterM,
		grade = gradeAlong(dir),
		rain = if type(rain) == "number" then rain else 0,
		transition = stanceBusy(),
		swimming = h:GetState() == Enum.HumanoidStateType.Swimming,
	})
	if now < slow.untilT then
		-- aterrissagem forte: volta ao normal ao longo do tempo
		local p = 1 - (slow.untilT - now) / math.max(slow.total, 1e-3)
		target *= slow.factor + (1 - slow.factor) * p
	end
	local tv = dir * (target * inputMag) -- m/s
	local grip = if grounded then Movement.surfaceGrip(probe.surface) else Movement.AIR_GRIP
	local vx, vz = Movement.accelStep(vel.X * M, vel.Z * M, tv.X, tv.Z, dt, grip)
	vel = Vector3.new(vx, 0, vz) / M
	-- encostado numa parede, a velocidade "guardada" não passa da real + 1 m/s
	local real = Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude
	if grounded and vel.Magnitude > real + 1 / M then
		vel = vel.Unit * (real + 1 / M)
	end
	local speed = vel.Magnitude
	if speed < 0.05 then
		vel = Vector3.zero
		return Vector3.zero, false
	end
	setWalk(h, speed)
	return vel / speed, false
end)

-- ===== transpor / escalar =====
local vaultParams = RaycastParams.new()
vaultParams.FilterType = Enum.RaycastFilterType.Exclude
vaultParams.RespectCanCollide = true
vaultParams.IgnoreWater = true

local function isCharacter(inst: Instance): boolean
	local model = inst:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local VAULT_LIFT = 2.2 -- studs do topo até o centro do HumanoidRootPart (só tronco e cabeça colidem)

local function probeVault(char: Model, hum: Humanoid, root: BasePart): (Movement.VaultPlan?, VaultRun?)
	vaultParams.FilterDescendantsInstances = ignoreList(char)
	local fwd = flatLook()
	local up = Vector3.yAxis
	local feetY = root.Position.Y - hum.HipHeight - root.Size.Y / 2
	local base = Vector3.new(root.Position.X, feetY, root.Position.Z)
	local reach = (Movement.VAULT_REACH_M + 0.3) / M -- do eixo do corpo (raio ~0,3 m)
	local dist: number? = nil
	for _, hM in { 0.4, 0.75, 1.1 } do
		local from = base + up * (hM / M)
		local r = workspace:Raycast(from, fwd * reach, vaultParams)
		if r and not isCharacter(r.Instance) and math.abs(r.Normal.Y) < 0.7 then
			local d = (r.Position - from).Magnitude
			dist = if dist then math.min(dist, d) else d
		end
	end
	local plan: Movement.VaultPlan?
	local probeT: Movement.VaultProbe = {
		height = nil,
		distance = 0,
		clearance = 0,
		depth = nil,
		drop = nil,
		headroom = 0,
		speed = vel.Magnitude * M,
		stamina = stamina.value,
		stance = stanceOf(char),
		legImpaired = char:GetAttribute("LegImpaired") == true,
		loadKg = loadKg,
	}
	if not dist then
		return nil, nil
	end
	local face = dist :: number
	probeT.distance = math.max(face * M - 0.3, 0)
	-- topo: de cima para baixo, logo depois da face
	local over = base + fwd * (face + 0.15 / M)
	local top = workspace:Raycast(
		over + up * ((Movement.VAULT_MAX_M + 0.6) / M),
		-up * ((Movement.VAULT_MAX_M + 0.6) / M),
		vaultParams
	)
	if not top then
		return nil, nil
	end
	local topY = top.Position.Y
	local h = (topY - feetY) * M
	probeT.height = h
	-- espaço: para cima a partir do topo, e para a frente na altura em que o corpo passa
	local upR = workspace:Raycast(top.Position + up * 0.05, up * (2 / M), vaultParams)
	probeT.headroom = if upR then (upR.Position.Y - topY) * M else 2
	local pass = Vector3.new(root.Position.X, topY + 0.45 / M, root.Position.Z)
	local passR = workspace:Raycast(pass, fwd * (face + 1.2 / M), vaultParams)
	probeT.clearance = if passR then math.min(probeT.headroom, 0.3) else probeT.headroom
	-- profundidade do topo e queda do outro lado (amostras a cada 0,3 m)
	local landing: Vector3? = nil
	for i = 1, 6 do
		local dd = face + (0.15 + 0.3 * i) / M
		local p = base + fwd * dd + up * ((h + 0.3) / M)
		local r = workspace:Raycast(p, -up * ((h + 0.3 + Movement.VAULT_MAX_DROP_M + 0.3) / M), vaultParams)
		if not r then
			probeT.depth = (dd - face) * M
			probeT.drop = nil
			break
		end
		if (r.Position.Y - feetY) * M < h - 0.25 then
			probeT.depth = (dd - face) * M
			probeT.drop = (topY - r.Position.Y) * M
			landing = r.Position
			break
		end
	end
	-- sem plano (baixo, alto, sem espaço...): fica o pulo normal do Humanoid
	plan = Movement.vaultPlan(probeT)
	if not plan then
		return nil, nil
	end
	local pl = plan :: Movement.VaultPlan
	local rootHalf = root.Size.Y / 2
	local overY = topY + VAULT_LIFT
	local pa = base + fwd * math.max(face - 0.35 / M, 0)
	pa = Vector3.new(pa.X, overY, pa.Z)
	local p2
	if pl.kind == "vault" then
		local farD = if probeT.depth then face + (probeT.depth :: number) / M else face + 0.6 / M
		local l = landing
		p2 = base + fwd * (farD + 0.35 / M)
		p2 = Vector3.new(p2.X, if l then math.max(overY - 0.2 / M, l.Y + rootHalf + hum.HipHeight) else overY, p2.Z)
	else
		local stand = num(char:GetAttribute("BaseHipHeight"), hum.HipHeight)
		p2 = base + fwd * (face + 0.6 / M)
		p2 = Vector3.new(p2.X, topY + stand + rootHalf + 0.1 / M, p2.Z)
	end
	return pl,
		{
			kind = pl.kind,
			t0 = os.clock(),
			dur = pl.duration,
			fwd = fwd,
			p0 = root.Position,
			pa = pa,
			p2 = p2,
			overY = overY,
			split = if pl.kind == "vault" then 0.4 else 0.55,
		}
end

local function vaultPos(v: VaultRun, u: number): Vector3
	if u <= v.split then
		-- sobe (desacelerando) e encosta na face
		local s = u / v.split
		local rise = 1 - (1 - s) * (1 - s)
		local hz = Movement.ease(s)
		local x = v.p0:Lerp(v.pa, hz)
		return Vector3.new(x.X, v.p0.Y + (v.pa.Y - v.p0.Y) * rise, x.Z)
	end
	local s = math.clamp((u - v.split) / (1 - v.split), 0, 1)
	local e = Movement.ease(s)
	local x = v.pa:Lerp(v.p2, e)
	local y = if v.kind == "vault"
		then v.overY + (v.p2.Y - v.overY) * e + math.sin(math.pi * s) * (0.08 / M)
		else v.pa.Y + (v.p2.Y - v.pa.Y) * e
	return Vector3.new(x.X, y, x.Z)
end

local function setJump(hum: Humanoid, on: boolean)
	if jumpEnabled ~= on then
		jumpEnabled = on
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, on)
	end
end

local function endVault(hum: Humanoid?, root: BasePart?)
	local v = vault
	vault = nil
	local char = player.Character
	if char then
		char:SetAttribute("Vaulting", nil)
	end
	setAttr("Vaulting", false)
	if not (v and hum and root) then
		return
	end
	local exit = v.fwd * (if v.kind == "vault" then 2.5 else 0.5) / M
	root.AssemblyLinearVelocity = exit
	vel = exit
	air.active, air.maxY = true, root.Position.Y
	air.credit = if v.kind == "vault" then 0.6 else 0.3 -- descida controlada não é queda
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
end

local function startVault(plan: Movement.VaultPlan, run: VaultRun, char: Model, hum: Humanoid)
	vault = run
	setJump(hum, false)
	Movement.spend(stamina, plan.cost, loadKg)
	char:SetAttribute("Vaulting", true) -- pose local imediata; o servidor replica para os outros
	setAttr("Vaulting", true)
	Bus.fire("vault_start", plan.kind)
	Net.event("Posture_Set"):FireServer({ vault = plan.kind, dur = plan.duration })
	hum:ChangeState(Enum.HumanoidStateType.Physics) -- o Humanoid não briga com o caminho
end

RunService.PreSimulation:Connect(function()
	local v = vault
	if not v then
		return
	end
	local char, hum, root = body()
	if not (char and hum and root) or player:GetAttribute("Downed") == true then
		endVault(hum, root)
		return
	end
	local u = (os.clock() - v.t0) / v.dur
	if u >= 1 then
		local r = root :: BasePart
		r.CFrame = CFrame.lookAt(v.p2, v.p2 + v.fwd)
		endVault(hum, r)
		return
	end
	local p = vaultPos(v, u)
	local ahead = vaultPos(v, math.min(u + 0.02, 1))
	local r = root :: BasePart
	r.CFrame = CFrame.lookAt(p, p + v.fwd)
	r.AssemblyLinearVelocity = (ahead - p) / (0.02 * v.dur)
	r.AssemblyAngularVelocity = Vector3.zero -- no estado Physics nada segura o corpo em pé
end)

-- botão de pulo: agachado/deitado levanta; de pé, perto de obstáculo baixo, transpõe ou escala
Input.on("jump", "press", function()
	local char, hum, root = body()
	if not (char and hum and root) or hum.SeatPart ~= nil or vault or dive then
		return
	end
	local c, h, r = char :: Model, hum :: Humanoid, root :: BasePart
	if stanceOf(c) ~= "stand" then
		if not stanceBusy() then
			Net.event("Posture_Set"):FireServer({ stance = "stand" }) -- o servidor confere o teto
		end
		return
	end
	if h.FloorMaterial == Enum.Material.Air then
		return
	end
	local plan, run = probeVault(c, h, r)
	if plan and run then
		startVault(plan, run, c, h)
	end
end)

-- ===== mergulho (InfantryController: deitar correndo) =====
Bus.on("dive", function()
	local char, hum, root = body()
	if not (char and hum and root) or vault or dive then
		return
	end
	local speed = vel.Magnitude * M
	if stanceOf(char :: Model) ~= "stand" or (hum :: Humanoid).FloorMaterial == Enum.Material.Air then
		return
	end
	if speed < Movement.DIVE_MIN_MPS then
		return
	end
	dive = { t0 = os.clock(), dir = vel.Unit, v0 = speed }
	Movement.spend(stamina, Movement.COST.dive, loadKg)
	Bus.fire("vault_start", "dive") -- mesma reação: tira a mira, para o tiro
end)

-- ===== câmera (antes do módulo de câmera: CameraOffset) =====
local function proneExtra(st: string): number
	return if st == "prone" then PRONE_EYE else 0
end

RunService:BindToRenderStep("VT65MoveCamera", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
	local char, hum, root = body()
	if not (char and hum and root) then
		return
	end
	local c, h, r = char :: Model, hum :: Humanoid, root :: BasePart
	if h.SeatPart ~= nil then
		if h.CameraOffset ~= Vector3.zero then
			h.CameraOffset = Vector3.zero -- veículo: como antes (sem inclinar nem deitar)
		end
		return
	end
	local now = os.clock()
	local st = stanceOf(c)
	local hip = h.HipHeight
	if camState.lastHip < 0 then
		camState.lastHip, camState.stance = hip, st
		camState.extraFrom, camState.extraTo = proneExtra(st), proneExtra(st)
	end
	-- postura mudou (atributo ou HipHeight): nova transição, levando o que faltava da anterior
	local changed = st ~= camState.stance
	if changed or math.abs(hip - camState.lastHip) > 0.05 then
		local p = if camState.active then Movement.ease((now - camState.t0) / camState.T) else 1
		local moved = if camState.active
			then math.clamp(r.Position.Y - camState.rootY0, math.min(0, camState.dH), math.max(0, camState.dH))
			else 0
		local comp = if camState.active then camState.carry * (1 - p) - moved + camState.dH * p else 0
		local extra = camState.extraFrom + (camState.extraTo - camState.extraFrom) * p
		local T = if changed
			then Movement.stanceTime(camState.stance, st, dive ~= nil)
			elseif camState.active then math.max(camState.T - (now - camState.t0), 0.15)
			else 0.3
		camState.prone = if changed
			then Movement.isProneTransition(camState.stance, st)
			else camState.prone and camState.active
		camState.t0, camState.T = now, T
		camState.dH, camState.rootY0, camState.carry = hip - camState.lastHip, r.Position.Y, comp
		camState.extraFrom, camState.extraTo = extra, proneExtra(st)
		camState.active = true
		camState.lastHip, camState.stance = hip, st
	end
	local comp, extra = 0, camState.extraTo
	if camState.active then
		local p = Movement.ease((now - camState.t0) / camState.T)
		local moved = math.clamp(r.Position.Y - camState.rootY0, math.min(0, camState.dH), math.max(0, camState.dH))
		comp = camState.carry * (1 - p) - moved + camState.dH * p
		extra = camState.extraFrom + (camState.extraTo - camState.extraFrom) * p
		if p >= 1 then
			camState.active = false
			comp, extra = 0, camState.extraTo
		end
	end
	-- inclinar (só mirando, Input.state.lean), suave
	camState.lean += (Input.state.lean * LEAN - camState.lean) * (1 - math.exp(-dt / 0.1))
	-- passo, respiração e aterrissagem (em metros)
	local v = r.AssemblyLinearVelocity
	local speed = if h.FloorMaterial ~= Enum.Material.Air then Vector3.new(v.X, 0, v.Z).Magnitude * M else 0
	local aiming = player:GetAttribute("Aiming") == true
	if speed > 0.2 then
		camState.phase += dt * math.pi * Movement.cadence(speed)
	end
	local bx, by = Movement.bob(camState.phase, speed, st, aiming)
	camState.breathT += dt
	by += Movement.breath(camState.breathT, stamina.value) * (1 - math.clamp(speed / 1.5, 0, 1))
	by += land.dip * Movement.dipCurve(now - land.t0, 0.09)
	local k = if ViewMode.third then 0.5 else 1 -- em 3ª pessoa o balanço fica pela metade
	local offset = Vector3.new(camState.lean + bx * k / M, comp + extra + by * k / M, 0)
	if (h.CameraOffset - offset).Magnitude > 1e-4 then
		h.CameraOffset = offset
	end
end)

-- ===== estados do Humanoid: pulo e aterrissagem =====
local stateConn: RBXScriptConnection? = nil
local function onLanded(root: BasePart)
	if not air.active then
		return
	end
	air.active = false
	local drop = math.max((air.maxY - root.Position.Y) * M - air.credit, 0)
	air.credit = 0
	local dip, factor, secs, cost = Movement.landing(drop)
	if dip > 0 then
		land.t0, land.dip = os.clock(), dip
	end
	if secs > 0 then
		slow.factor, slow.untilT, slow.total = factor, os.clock() + secs, secs
	end
	if cost > 0 then
		Movement.spend(stamina, cost, loadKg)
	end
	if drop > 0.25 then
		Bus.fire("landed", drop)
	end
	jumpReadyAt = os.clock() + Movement.JUMP_COOLDOWN
end

local function watch(char: Model)
	if stateConn then
		stateConn:Disconnect()
		stateConn = nil
	end
	stamina = Movement.newStamina()
	vel, vault, dive = Vector3.zero, nil, nil
	jumpEnabled, jumpReadyAt = nil, 0
	air.active, air.credit = false, 0
	camState.lastHip, camState.active = -1, false
	spareMags = nil
	setAttr("Vaulting", false)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not (hum and root) then
		return
	end
	local h, r = hum :: Humanoid, root :: BasePart
	loadKg = computeLoad()
	stateConn = h.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			if not vault then
				Movement.spend(stamina, Movement.COST.jump, loadKg)
				jumpReadyAt = math.huge -- só conta depois de aterrissar
			end
			air.active, air.maxY = true, r.Position.Y
		elseif new == Enum.HumanoidStateType.Freefall then
			if not air.active then
				air.active, air.maxY = true, r.Position.Y
			end
		elseif
			new == Enum.HumanoidStateType.Landed
			or new == Enum.HumanoidStateType.Running
			or new == Enum.HumanoidStateType.Swimming
		then
			onLanded(r)
		end
	end)
end
player.CharacterAdded:Connect(watch)
if player.Character then
	task.spawn(watch, player.Character)
end

-- ===== laço por quadro (física): fôlego, corrida, pulo, sonda =====
local loadAt = 0
RunService.Heartbeat:Connect(function(dt: number)
	local char, hum, root = body()
	if not (char and hum and root) then
		return
	end
	local c, h, r = char :: Model, hum :: Humanoid, root :: BasePart
	local now = os.clock()
	if h.SeatPart ~= nil then
		vel = Vector3.zero
		return -- veículo: nada muda
	end
	if now - lastFilter > 0.25 then
		vel = Vector3.zero -- controles desligados (menu): sem embalo guardado
	end
	if now >= probe.nextAt then
		probe.nextAt = now + 0.1
		doProbe(c, h, r)
	end
	if now >= loadAt then
		loadAt = now + 1
		loadKg = computeLoad()
	end
	if air.active then
		air.maxY = math.max(air.maxY, r.Position.Y)
	end
	local d = dive
	if d and now - d.t0 >= Movement.DIVE_S then
		dive = nil
		land.t0, land.dip = now, 0.05 -- o peito chega ao chão
	end
	-- fôlego pelo esforço real (velocidade medida, não o pedido)
	local st = stanceOf(c)
	local v = r.AssemblyLinearVelocity
	local hv = Vector3.new(v.X, 0, v.Z)
	local speed = hv.Magnitude * M
	local sprinting = c:GetAttribute("Sprinting") == true
	local kind = if vault or d
		then "jog" -- o gasto do transpor e do mergulho já foi cobrado de uma vez
		elseif sprinting and speed > Movement.SPRINT_COUNT_MPS then "sprint"
		elseif speed > 2 then "jog"
		elseif speed > 0.3 then "walk"
		else "still"
	Movement.staminaStep(stamina, dt, {
		kind = kind,
		stance = st,
		surface = probe.surface,
		grade = gradeAlong(hv),
		loadKg = loadKg,
		waterM = probe.waterM,
		regen = num(player:GetAttribute("StaminaRegen"), 1),
	})
	-- corrida: sem fôlego para; parado com a corrida ligada (alternar), desliga. Um pedido por segundo
	-- no máximo (o atributo do servidor demora um ping para cair).
	if (Input.state.sprinting or sprinting) and now >= stopAt then
		if not Movement.canSprint(stamina) then
			stopAt = now + 1
			Bus.fire("sprint_stop", "Sem fôlego")
		elseif inputMag < 0.2 then
			sprintIdle += dt
			if sprintIdle > 0.5 then
				sprintIdle = 0
				stopAt = now + 1
				Bus.fire("sprint_stop", nil)
			end
		else
			sprintIdle = 0
		end
	end
	-- pulo: só de pé, descansado o bastante, fora de transições, com intervalo
	local canJump = st == "stand"
		and c:GetAttribute("LegImpaired") ~= true
		and player:GetAttribute("Downed") ~= true
		and now >= jumpReadyAt
		and stamina.value >= Movement.JUMP_MIN_STAMINA
		and not vault
		and not dive
		and not stanceBusy()
	setJump(h, canJump)
	local jp = Movement.jumpPower(Movement.jumpHeight(stamina.value, loadKg), workspace.Gravity)
	if not h.UseJumpPower then
		h.UseJumpPower = true
	end
	if math.abs(h.JumpPower - jp) > 0.2 then
		h.JumpPower = jp
	end
	-- estado para os outros controllers (atributos locais)
	setAttr("Stamina", math.floor(stamina.value * 100 + 0.5) / 100)
	setAttr("Exhausted", stamina.exhausted)
	setAttr("StanceBusy", stanceBusy())
end)
