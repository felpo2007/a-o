--!strict
-- Movimento da infantaria no cliente (pedido do dono, 2026-11-11: "a melhor movimentação possível";
-- D-93, depois de jogar: "a movimentação na água está toda bugada", "faça a movimentação muito boa",
-- "faça que os do Vietnã sejam mais rápidos"). Toda a matemática e os números ficam em Shared/Movement
-- (puro, testado). Aqui:
-- - passo: o pedido de movimento (teclado ou analógico, já com a zona morta da camada Input) vira
--   uma velocidade com arrancada rápida, corrida que embala e curva que gira a velocidade
--   (Movement.moveStep); o WalkSpeed local acompanha. O teto é o do servidor (Movement.serverSpeed,
--   que o MedicalService.apply usa) e este script não passa dele; o VC anda 12% mais rápido;
-- - fôlego: pulo, transposição e mergulho gastam; a corrida não (D-89);
-- - chão: arrozal (a lâmina PaddyWater na coluna, não "a primeira coisa" que o raio acha), lama,
--   areia, mata, rampa; a superfície troca só depois de 0,3 s lida igual e o fator é suavizado;
-- - água do terreno (riacho, mar): modo pela fundura do LEITO com histerese. Vadeando (até ~1,3 m),
--   o estado Swimming do Humanoid fica desligado: o soldado anda no fundo, devagar e com passada
--   pesada, sem boiar nem alternar nadar/andar; mais fundo, nada (estável, com a câmera em pé);
-- - pulo baixo; transpor/escalar (A / Espaço); de agachado ou deitado, degrau baixo à frente vira
--   uma passada assistida sem botão; mergulho para deitado correndo (Bus "dive");
-- - câmera: inclinar, postura com transição suave, balanço preso à passada das animações, cabeça com
--   inércia (arrancar, parar, curva), inclinação lateral nas curvas, degrau suavizado (dique, soleira)
--   e afundada na aterrissagem. Tudo o que balança multiplica pela opção de movimento da câmera.
-- Atributos locais (não replicam): Stamina (0..1), Exhausted, StanceBusy, Vaulting, WaterMode.
-- Veículo: nada muda. Ganchos só no Studio: workspace "VT65DevMov" (fim do arquivo).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = require(ReplicatedStorage.Shared.Kit)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local SoldierAnims = require(ReplicatedStorage.Shared.SoldierAnims)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ViewMode = require(script.Parent.ViewMode)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = Movement.STUD_M
local PRONE_EYE = -1.6 -- studs: câmera de quem está de bruços (~0,3 m do chão; antes no InfantryController)
local LEAN = 0.35 / M -- inclinar: câmera 0,35 m para o lado (D-42)
local SWIMMING = Enum.HumanoidStateType.Swimming

-- ===== estado =====
local stamina = Movement.newStamina()
local vel = Vector3.zero -- velocidade horizontal comandada (studs/s)
local accel = Vector3.zero -- aceleração comandada, suavizada (m/s², mundo): cabeça e inclinação
local inputMag = 0
local lastFilter = 0
local loadKg = 20
local spareMags: number? = nil
local probe = {
	surface = "firm",
	ground = Movement.newGround(),
	groundK = 1, -- fator do chão suavizado (superfície × água × rampa)
	waterM = 0, -- fundura do leito (m); math.huge = água sem fundo ao alcance
	waterTop = nil :: number?,
	normal = Vector3.yAxis,
	nextAt = 0,
}
local water = { mode = "dry", swimOn = nil :: boolean?, stanceAt = 0, sinkT = 0 }
local blocked = { t = 0, stepT = 0, stepAt = 0 }
local dev = { faction = nil :: string?, info = false, infoAt = 0 }
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
	face: Vector3?, -- para onde o corpo olha (padrão: fwd)
	exit: number?, -- m/s na saída (padrão: 2,5 transpondo, 0,5 escalando)
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
	phase = 0, -- ciclos de passada (0 = apoio do pé esquerdo, como os clipes da D-88)
	phaseAt = 0,
	breathT = 0,
	stepOff = 0, -- m: degrau suavizado
	lastY = nil :: number?,
	head = Movement.newHead(),
	roll = 0, -- rad
	rollApplied = 0,
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

-- lado (VC corre mais, Movement.FACTION); no Studio, "VT65DevMov" = "vc"/"eua" finge o lado
local function myFaction(): string?
	if dev.faction then
		return dev.faction
	end
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else nil
end

-- opção de acessibilidade "movimento da câmera" (0..1). Lida de Input.settings.cameraBob quando o
-- menu ganhar a opção (InputMap); até lá, do atributo local "CameraBob" do jogador.
local function camScale(): number
	local s = (Input.settings :: any).cameraBob
	if type(s) == "number" then
		return Movement.cameraScale(s)
	end
	return Movement.cameraScale(player:GetAttribute("CameraBob"))
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
		faction = myFaction(),
	})
end

-- ===== sonda do chão (10 Hz): material, arrozal, água e rampa =====
-- Chão: só o que colide (folhagem, sebe e a lâmina do arrozal não são chão). Antes o raio parava em
-- qualquer peça e pulava até 4 sem colisão: na mata fechada às vezes não achava chão ("firme").
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true
groundParams.RespectCanCollide = true
local paddyParams = RaycastParams.new()
paddyParams.FilterType = Enum.RaycastFilterType.Include
local paddyFolder: Instance? = nil
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.FilterDescendantsInstances = { workspace.Terrain }
waterParams.IgnoreWater = false
local bedParams = RaycastParams.new()
bedParams.FilterType = Enum.RaycastFilterType.Exclude
bedParams.IgnoreWater = true
bedParams.RespectCanCollide = true

local function ignoreList(char: Model): { Instance }
	local list: { Instance } = { char, camera }
	local fx = workspace:FindFirstChild("VT65Effects")
	if fx then
		table.insert(list, fx)
	end
	return list
end

local function sheets(): Instance?
	if not (paddyFolder and paddyFolder.Parent) then
		local map = workspace:FindFirstChild("Map")
		paddyFolder = map and map:FindFirstChild("PaddyWater")
		if paddyFolder then
			paddyParams.FilterDescendantsInstances = { paddyFolder }
		end
	end
	return paddyFolder
end

local function doProbe(char: Model, hum: Humanoid, root: BasePart)
	local list = ignoreList(char)
	groundParams.FilterDescendantsInstances = list
	local feetDrop = hum.HipHeight + root.Size.Y / 2
	local feetY = root.Position.Y - feetDrop
	local down = Vector3.new(0, -(feetDrop + 3), 0)
	local hit = workspace:Raycast(root.Position, down, groundParams)
	local seen, normal = "firm", Vector3.yAxis
	if hit then
		local attr = hit.Instance:GetAttribute("Material")
		seen = Movement.surfaceOf(hit.Material.Name, if type(attr) == "string" then attr else nil, hit.Instance.Name)
		normal = if hit.Normal.Y < 0.1 then Vector3.yAxis else hit.Normal
		-- arrozal: a lâmina cobre o tabuleiro todo, mas o capim do terreno fura a lâmina em metade dos
		-- pontos. Com a lâmina na coluna (até PADDY_BELOW_M abaixo do chão achado), é arrozal.
		if hit.Instance == workspace.Terrain and sheets() then
			local w = workspace:Raycast(root.Position, down, paddyParams)
			if w and w.Position.Y >= hit.Position.Y - Movement.PADDY_BELOW_M / M then
				seen, normal = "paddy", Vector3.yAxis
			end
		end
	end
	probe.surface = Movement.surfaceStep(probe.ground, seen, 0.1)
	probe.normal = normal
	-- água do terreno: fundura do LEITO (superfície − fundo), que não depende de onde o corpo está
	-- (medida até o pé, boiando o pé subia, a "fundura" caía e o soldado alternava nadar e andar).
	-- Com o pé acima da água (ponte, margem alta, pulo), é seco.
	local w = workspace:Raycast(root.Position + Vector3.new(0, 12, 0), Vector3.new(0, -(feetDrop + 16), 0), waterParams)
	if w and w.Material == Enum.Material.Water and w.Position.Y > feetY - 0.05 / M then
		bedParams.FilterDescendantsInstances = list
		local b = workspace:Raycast(w.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, -40, 0), bedParams)
		probe.waterTop = w.Position.Y
		probe.waterM = if b then math.max((w.Position.Y - b.Position.Y) * M, 0) else math.huge
	else
		probe.waterTop, probe.waterM = nil, 0
	end
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

-- ===== água: nadar só no fundo =====
-- O Humanoid entra em Swimming com a água no HumanoidRootPart: em pé a ~0,65 m, agachado ou deitado
-- com poucos centímetros. No riacho (0,6 m no projeto, até ~1,1 m com os voxels de 4 studs) e na
-- praia, o soldado alternava nadar e andar: velocidade aos trancos (0,9 m/s nadando), corpo deitando
-- e a câmera (presa à HumanoidRootPart) girando junto. Vadeando, Swimming fica desligado.
local function applyWater(char: Model, h: Humanoid)
	local mode = Movement.waterMode(water.mode, probe.waterM)
	water.mode = mode
	setAttr("WaterMode", mode)
	local swimOn = mode ~= "wade"
	if water.swimOn ~= swimOn then
		water.swimOn = swimOn
		h:SetStateEnabled(SWIMMING, swimOn)
	end
	if not swimOn and h:GetState() == SWIMMING then
		h:ChangeState(Enum.HumanoidStateType.Running)
	end
	-- postura possível na água: deitado só no raso; nadando, de pé
	local st = stanceOf(char)
	local want = if mode == "swim" then "stand" else Movement.waterStance(st, probe.waterM)
	local now = os.clock()
	if want ~= st and not stanceBusy() and not vault and now >= water.stanceAt then
		water.stanceAt = now + 1.5
		Net.event("Posture_Set"):FireServer({ stance = want })
	end
end

-- ===== filtro de movimento (camada Input: zona morta já aplicada) =====
local function setWalk(hum: Humanoid, studs: number)
	if math.abs(hum.WalkSpeed - studs) > 0.01 then
		hum.WalkSpeed = studs
	end
end

local startStep: (Model, Humanoid, BasePart, Vector3) -> () = function() end

Input.setMoveFilter(function(vec: Vector3, rel: boolean): (Vector3, boolean)
	local now = os.clock()
	local dt = math.clamp(now - lastFilter, 0, 0.1)
	lastFilter = now
	local char, hum, root = body()
	if not (char and hum and root) or hum.SeatPart ~= nil then
		vel, accel = Vector3.zero, Vector3.zero
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
	local swimming = water.mode == "swim"
	local sprinting = c:GetAttribute("Sprinting") == true
	local rain = ReplicatedStorage:GetAttribute("Rain")
	local wM = math.min(probe.waterM, 3)
	-- fator do chão suavizado: borda de tabuleiro, raiz ou rampa não dão tranco
	local gK = Movement.groundFactor(probe.surface, if type(rain) == "number" then rain else 0, wM, gradeAlong(dir))
	probe.groundK = Movement.approach(probe.groundK, gK, Movement.GROUND_TAU_S, dt)
	local target = Movement.targetSpeed({
		stance = st,
		sprinting = sprinting,
		aiming = player:GetAttribute("Aiming") == true,
		downed = player:GetAttribute("Downed") == true,
		legImpaired = c:GetAttribute("LegImpaired") == true,
		forward = if inputMag > 0 then dir:Dot(fwd) else 1,
		stamina = stamina.value,
		loadKg = loadKg,
		surface = probe.surface,
		waterM = wM,
		grade = 0,
		rain = 0,
		transition = stanceBusy(),
		swimming = swimming,
		faction = myFaction(),
		groundK = probe.groundK,
	})
	if now < slow.untilT then
		-- aterrissagem forte: volta ao normal ao longo do tempo
		local p = 1 - (slow.untilT - now) / math.max(slow.total, 1e-3)
		target *= slow.factor + (1 - slow.factor) * p
	end
	-- corrida firme: com a corrida ligada, o analógico quase no fim vale o fim
	local mag = if sprinting and inputMag >= 0.7 then 1 else inputMag
	local tv = dir * (target * mag) -- m/s
	local grip = if swimming
		then Movement.WATER_GRIP
		elseif grounded then Movement.surfaceGrip(probe.surface) * Movement.wadeGrip(wM)
		else Movement.AIR_GRIP
	local prev = vel
	local vx, vz = Movement.moveStep(vel.X * M, vel.Z * M, tv.X, tv.Z, dt, grip)
	vel = Vector3.new(vx, 0, vz) / M
	-- encostado numa parede, a velocidade "guardada" não passa da real + 1 m/s. Só depois de 0,15 s:
	-- subindo dique ou degrau a velocidade real cai por um instante e o passo engasgava.
	local rv = r.AssemblyLinearVelocity
	local real = Vector3.new(rv.X, 0, rv.Z).Magnitude
	if grounded and vel.Magnitude > real + 1 / M then
		blocked.t += dt
		if blocked.t > 0.15 then
			vel = vel.Unit * (real + 1 / M)
		end
	else
		blocked.t = 0
	end
	if dt > 1e-4 then
		accel = accel:Lerp((vel - prev) * (M / dt), math.min(1, dt / 0.06))
	end
	-- agachado ou deitado, parado na face de um degrau baixo: passada assistida
	local cmdM = vel.Magnitude * M
	if st ~= "stand" and grounded and cmdM > 0.25 and real * M < cmdM * 0.4 and inputMag > 0.3 then
		blocked.stepT += dt
		if blocked.stepT > 0.12 and now >= blocked.stepAt and not stanceBusy() then
			blocked.stepAt = now + 0.5
			startStep(c, h, r, dir)
		end
	else
		blocked.stepT = 0
	end
	local speed = vel.Magnitude
	if speed < 0.05 then
		vel = Vector3.zero
		return Vector3.zero, false
	end
	setWalk(h, speed)
	return vel / speed, false
end)

-- ===== transpor / escalar / degrau =====
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
		agility = Movement.factionAgility(myFaction()),
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

-- Degrau à frente de quem está agachado ou deitado (dir = rumo do movimento, não da câmera).
local function probeStep(char: Model, hum: Humanoid, root: BasePart, dir: Vector3): (Movement.VaultPlan?, VaultRun?)
	if dir.Magnitude < 1e-3 then
		return nil, nil
	end
	vaultParams.FilterDescendantsInstances = ignoreList(char)
	local up = Vector3.yAxis
	local feetY = root.Position.Y - hum.HipHeight - root.Size.Y / 2
	local base = Vector3.new(root.Position.X, feetY, root.Position.Z)
	local reach = (Movement.STEP_REACH_M + 0.35) / M
	local dist: number? = nil
	for _, hM in { 0.06, 0.18, 0.32 } do
		local from = base + up * (hM / M)
		local r = workspace:Raycast(from, dir * reach, vaultParams)
		if r and not isCharacter(r.Instance) and math.abs(r.Normal.Y) < 0.7 then
			local d = (r.Position - from).Magnitude
			dist = if dist then math.min(dist, d) else d
		end
	end
	if not dist then
		return nil, nil
	end
	local face = dist :: number
	local maxH = 0.8
	local top =
		workspace:Raycast(base + dir * (face + 0.12 / M) + up * (maxH / M), -up * ((maxH + 0.05) / M), vaultParams)
	if not top then
		return nil, nil
	end
	local topY = top.Position.Y
	local upR = workspace:Raycast(top.Position + up * 0.05, up * (1.4 / M), vaultParams)
	local plan = Movement.stepPlan({
		height = (topY - feetY) * M,
		distance = math.max(face * M - 0.35, 0),
		headroom = if upR then (upR.Position.Y - topY) * M else 1.4,
		stance = stanceOf(char),
		legImpaired = char:GetAttribute("LegImpaired") == true,
		agility = Movement.factionAgility(myFaction()),
	})
	if not plan then
		return nil, nil
	end
	-- o quadril sobe para a mesma altura acima do topo e avança 0,55 m sobre ele
	local overY = topY + hum.HipHeight + root.Size.Y / 2 + 0.05 / M
	local pa = base + dir * math.max(face - 0.3 / M, 0)
	local p2 = base + dir * (face + 0.55 / M)
	return plan,
		{
			kind = "step",
			t0 = os.clock(),
			dur = plan.duration,
			fwd = dir,
			p0 = root.Position,
			pa = Vector3.new(pa.X, overY, pa.Z),
			p2 = Vector3.new(p2.X, overY, p2.Z),
			overY = overY,
			split = 0.45,
			face = flatLook(),
			exit = math.min(vel.Magnitude * M, Movement.CROUCH),
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
	local exitM = v.exit or (if v.kind == "vault" then 2.5 else 0.5)
	local exit = v.fwd * exitM / M
	root.AssemblyLinearVelocity = exit
	vel = exit
	air.active, air.maxY = true, root.Position.Y
	air.credit = if v.kind == "vault" then 0.6 else 0.3 -- descida controlada não é queda
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
end

local function startVault(plan: Movement.VaultPlan, run: VaultRun, char: Model, hum: Humanoid)
	vault = run
	setJump(hum, false)
	if plan.cost > 0 then
		Movement.spend(stamina, plan.cost, loadKg)
	end
	setAttr("Vaulting", true) -- WeaponController: sem tiro durante o movimento
	if run.kind ~= "step" then
		char:SetAttribute("Vaulting", true) -- pose local imediata; o servidor replica para os outros
		Net.event("Posture_Set"):FireServer({ vault = plan.kind, dur = plan.duration })
	end
	Bus.fire("vault_start", plan.kind)
	hum:ChangeState(Enum.HumanoidStateType.Physics) -- o Humanoid não briga com o caminho
end

startStep = function(char: Model, hum: Humanoid, root: BasePart, dir: Vector3)
	if vault or dive or hum.SeatPart ~= nil then
		return
	end
	local plan, run = probeStep(char, hum, root, dir)
	if plan and run then
		startVault(plan, run, char, hum)
	end
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
	local face = v.face or v.fwd
	local u = (os.clock() - v.t0) / v.dur
	if u >= 1 then
		local r = root :: BasePart
		r.CFrame = CFrame.lookAt(v.p2, v.p2 + face)
		endVault(hum, r)
		return
	end
	local p = vaultPos(v, u)
	local ahead = vaultPos(v, math.min(u + 0.02, 1))
	local r = root :: BasePart
	r.CFrame = CFrame.lookAt(p, p + face)
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
	if speed < Movement.DIVE_MIN_MPS or water.mode ~= "dry" then
		return -- na água não se mergulha para deitar
	end
	dive = { t0 = os.clock(), dir = vel.Unit, v0 = speed }
	Movement.spend(stamina, Movement.COST.dive, loadKg)
	Bus.fire("vault_start", "dive") -- mesma reação: tira a mira, para o tiro
end)

-- ===== câmera (antes do módulo de câmera: CameraOffset; depois dele: inclinação lateral) =====
local function proneExtra(st: string): number
	return if st == "prone" then PRONE_EYE else 0
end

-- Altura do olho que o módulo de câmera do Roblox soma à HumanoidRootPart, no referencial DELA
-- (BaseCamera.GetSubjectPosition). Nadando a HumanoidRootPart deita e o olho ia junto.
local function headOffsetY(h: Humanoid, r: BasePart): number
	if h.RigType == Enum.HumanoidRigType.R15 then
		return if h.AutomaticScalingEnabled then 1.5 + (r.Size.Y - 2) / 2 else 2
	end
	return 1.5
end

local GAIT_IDS: { [string]: string } = {}
for name, clip in SoldierAnims.CLIPS do
	if clip.cycles > 0 and clip.id ~= 0 then
		GAIT_IDS["rbxassetid://" .. clip.id] = name
	end
end

-- fase da passada que as animações tocam (ciclos, 0..1), pela trilha de passada de maior peso
local function animPhase(h: Humanoid): number?
	local animator = h:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local best: number? = nil
	local bestW = 0.2
	for _, tr in animator:GetPlayingAnimationTracks() do
		local a = tr.Animation
		local name = if a then GAIT_IDS[a.AnimationId] else nil
		if name and tr.WeightCurrent > bestW then
			local clip = SoldierAnims.CLIPS[name]
			bestW = tr.WeightCurrent
			best = (tr.TimePosition / clip.length * clip.cycles) % 1
		end
	end
	return best
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

-- passada: frequência das animações (SoldierAnims), puxada para a fase da trilha que está tocando
local function stepPhase(h: Humanoid, r: BasePart, st: string, speed: number, dt: number, now: number)
	if speed <= 0.2 then
		return
	end
	local w = SoldierAnims.targets({ stance = st, speed = speed, active = true, moving = true })
	local rate = SoldierAnims.cycleRate(w, speed)
	if rate <= 0 then
		rate = Movement.cadence(speed) / 2
	end
	local v = r.AssemblyLinearVelocity
	local _, back = SoldierAnims.legYaw(yawOf(r.CFrame.LookVector), yawOf(Vector3.new(v.X, 0, v.Z)), speed)
	camState.phase += rate * dt * (if back then -1 else 1)
	if now >= camState.phaseAt then
		camState.phaseAt = now + 0.1
		local ap = animPhase(h)
		if ap then
			camState.phase += ((ap - camState.phase + 0.5) % 1 - 0.5) * 0.5
		end
	end
end

-- postura mudou (atributo ou HipHeight): nova transição, levando o que faltava da anterior
local function stanceCamera(st: string, hip: number, r: BasePart, now: number): (number, number)
	if camState.lastHip < 0 then
		camState.lastHip, camState.stance = hip, st
		camState.extraFrom, camState.extraTo = proneExtra(st), proneExtra(st)
	end
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
	return comp, extra
end

RunService:BindToRenderStep("VT65MoveCamera", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
	-- desfaz a inclinação lateral do quadro anterior (o módulo de câmera também a tiraria)
	if camState.rollApplied ~= 0 then
		camera.CFrame *= CFrame.Angles(0, 0, -camState.rollApplied)
		camState.rollApplied = 0
	end
	local char, hum, root = body()
	if not (char and hum and root) then
		camState.roll = 0
		return
	end
	local c, h, r = char :: Model, hum :: Humanoid, root :: BasePart
	if h.SeatPart ~= nil then
		camState.roll, camState.lastY = 0, nil
		if h.CameraOffset ~= Vector3.zero then
			h.CameraOffset = Vector3.zero -- veículo: como antes (sem inclinar nem deitar)
		end
		return
	end
	local now = os.clock()
	local st = stanceOf(c)
	local comp, extra = stanceCamera(st, h.HipHeight, r, now)
	-- inclinar (só mirando, Input.state.lean), suave
	camState.lean += (Input.state.lean * LEAN - camState.lean) * (1 - math.exp(-dt / 0.1))
	local state = h:GetState()
	local grounded = h.FloorMaterial ~= Enum.Material.Air
	local swim = state == SWIMMING
	local v = r.AssemblyLinearVelocity
	local hv = Vector3.new(v.X, 0, v.Z)
	local speed = if grounded then hv.Magnitude * M else 0
	local aiming = player:GetAttribute("Aiming") == true
	local scale = camScale()
	local sk = scale * (if ViewMode.third then 0.5 else 1) -- em 3ª pessoa o balanço fica pela metade
	-- passada, respiração e aterrissagem (em metros)
	stepPhase(h, r, st, speed, dt, now)
	local bx, by
	if swim then
		bx, by = 0, Movement.swimBob(now)
	else
		bx, by = Movement.bob(2 * math.pi * camState.phase, speed, st, aiming, math.min(probe.waterM, 3))
	end
	camState.breathT += dt
	by += Movement.breath(camState.breathT, stamina.value) * (1 - math.clamp(speed / 1.5, 0, 1))
	by += land.dip * Movement.dipCurve(now - land.t0, 0.09)
	-- degrau: o corpo pula de altura (dique, soleira); a câmera vai junto, suave
	local y = r.Position.Y
	local last = camState.lastY
	if last and grounded and not camState.active and not vault and not swim then
		local dyM = (y - last) * M
		if math.abs(dyM) > 1.2 then
			camState.stepOff = 0 -- teleporte ou queda grande: sem suavizar
		else
			local expected = gradeAlong(hv) * hv.Magnitude * M * dt
			camState.stepOff = Movement.stepSmooth(camState.stepOff, dyM, expected, dt)
		end
	else
		camState.stepOff = Movement.approach(camState.stepOff, 0, 0.05, dt)
	end
	camState.lastY = y
	-- cabeça com inércia e inclinação lateral, no rumo do corpo
	local look = r.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	fwd = if fwd.Magnitude > 0.2 then fwd.Unit else flatLook()
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	local quiet = swim or vault ~= nil or dive ~= nil
	local aR, aF = accel:Dot(right), accel:Dot(fwd)
	Movement.headStep(camState.head, if quiet then 0 else aR, if quiet then 0 else aF, dt)
	local rollT = if quiet then 0 else Movement.rollTarget((vel * M):Dot(right), aR, st, aiming) * sk
	camState.roll = Movement.approach(camState.roll, rollT, Movement.ROLL.tau, dt)
	-- deslocamento no rumo do corpo (x direita, y cima, z para trás), em studs
	local offset = Vector3.new(
		camState.lean + (bx * sk + camState.head.x * scale) / M,
		comp + extra + (by * sk + camState.stepOff) / M,
		-camState.head.z * scale / M
	)
	-- a HumanoidRootPart inclinada (nadando): o olho fica em pé acima dela
	if r.CFrame.UpVector.Y < 0.995 then
		local H = Vector3.new(0, headOffsetY(h, r), 0)
		local yawCF = CFrame.lookAt(Vector3.zero, fwd)
		offset = r.CFrame:VectorToObjectSpace(yawCF:VectorToWorldSpace(offset + H)) - H
	end
	if (h.CameraOffset - offset).Magnitude > 1e-4 then
		h.CameraOffset = offset
	end
end)

-- inclinação lateral DEPOIS do módulo de câmera, do CameraLook e da 3ª pessoa: só gira em volta da
-- linha de visada (a mira e a direção do tiro não mudam); desfeita no começo do quadro seguinte
RunService:BindToRenderStep("VT65MoveRoll", Enum.RenderPriority.Camera.Value + 3, function()
	local a = camState.roll
	if math.abs(a) < 1e-5 or camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local _, hum = body()
	if not hum or camera.CameraSubject ~= hum or (hum :: Humanoid).SeatPart ~= nil then
		return
	end
	camera.CFrame *= CFrame.Angles(0, 0, a)
	camState.rollApplied = a
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
	if water.mode ~= "dry" then
		drop = math.max(drop - 0.6, 0) -- a água amortece
	end
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
	vel, accel, vault, dive = Vector3.zero, Vector3.zero, nil, nil
	jumpEnabled, jumpReadyAt = nil, 0
	air.active, air.credit = false, 0
	camState.lastHip, camState.active, camState.lastY, camState.stepOff = -1, false, nil, 0
	camState.head = Movement.newHead()
	water.mode, water.swimOn = "dry", nil
	probe.ground, probe.groundK, probe.waterM = Movement.newGround(), 1, 0
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
		elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running or new == SWIMMING then
			onLanded(r)
		end
	end)
end
player.CharacterAdded:Connect(watch)
if player.Character then
	task.spawn(watch, player.Character)
end

-- ===== ganchos só no Studio (D-93) =====
-- Na barra de comando do Studio (servidor ou cliente): workspace:SetAttribute("VT65DevMov", X)
--   "agua"    riacho raso mais perto (vadear) | "fundo" água funda (nadar) | "mar" praia rasa
--   "arrozal" meio do tabuleiro mais perto    | "dique" de frente para o dique mais perto (no assento
--             do motorista, leva o veículo)
--   "info"    liga/desliga a leitura no Output a cada 0,5 s (chão, água, estado, velocidade)
--   "vc"/"eua" finge o lado só no movimento local | "nada" desliga tudo
--   "veiculo" leitura do motorista (VehicleController).
-- Pelo servidor, para repetir o mesmo valor, passe antes por outro (ex.: "nada").
local function devSay(msg: string)
	print("[VT65 MOV] " .. msg)
end

local function devPlace(pos: Vector3, face: Vector3)
	local _, hum, root = body()
	if not (hum and root) then
		return
	end
	local f = Vector3.new(face.X, 0, face.Z)
	f = if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
	local seat = (hum :: Humanoid).SeatPart
	local model = seat and seat:FindFirstAncestorWhichIsA("Model")
	if seat and model and model:GetAttribute("VehicleId") and seat:GetAttribute("SeatId") == "driver" then
		local chassis = model:FindFirstChild("Chassis") :: BasePart?
		local lift = if chassis then chassis.Size.Y / 2 + 1 else 4
		model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, lift, 0), pos + Vector3.new(0, lift, 0) + f))
		return
	end
	local r = root :: BasePart
	local p = pos + Vector3.new(0, 4, 0)
	r.CFrame = CFrame.lookAt(p, p + f)
	r.AssemblyLinearVelocity = Vector3.zero
	vel = Vector3.zero
end

-- água do terreno numa espiral de raios ao redor (até ~200 m): leito entre minM e maxM
local function devFindWater(minM: number, maxM: number, sea: boolean): (Vector3?, number)
	local _, _, root = body()
	if not root then
		return nil, 0
	end
	local o = (root :: BasePart).Position
	local wp = RaycastParams.new()
	wp.FilterType = Enum.RaycastFilterType.Include
	wp.FilterDescendantsInstances = { workspace.Terrain }
	wp.IgnoreWater = false
	local bp = RaycastParams.new()
	bp.FilterType = Enum.RaycastFilterType.Include
	bp.FilterDescendantsInstances = { workspace.Terrain }
	bp.IgnoreWater = true
	for ring = 0, 72 do
		local rad = ring * 10
		local n = math.max(1, math.floor(2 * math.pi * rad / 10))
		for i = 1, n do
			local a = 2 * math.pi * i / n
			local p = Vector3.new(o.X + math.cos(a) * rad, o.Y + 300, o.Z + math.sin(a) * rad)
			local w = workspace:Raycast(p, Vector3.new(0, -800, 0), wp)
			if w and w.Material == Enum.Material.Water and (not sea or math.abs(w.Position.Y) < 2) then
				local b = workspace:Raycast(w.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, -60, 0), bp)
				local depth = if b then (w.Position.Y - b.Position.Y) * M else 99
				if depth >= minM and depth <= maxM then
					return w.Position, depth
				end
			end
		end
		if ring % 3 == 2 then
			task.wait()
		end
	end
	return nil, 0
end

-- peça mais perto numa pasta do mapa: a peça, o ponto do eixo X dela mais perto (no topo) e a
-- direção de quem chega pelo lado do jogador olhando para ela (eixo Z = largura do dique)
local function devNearestPart(folderName: string): (BasePart?, Vector3, Vector3)
	local _, _, root = body()
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild(folderName)
	if not (root and folder) then
		return nil, Vector3.zero, Vector3.zero
	end
	local o = (root :: BasePart).Position
	local best: BasePart? = nil
	local bestD, bestP, bestN = math.huge, Vector3.zero, Vector3.zero
	for _, p in folder:GetDescendants() do
		if p:IsA("BasePart") then
			local lp = p.CFrame:PointToObjectSpace(o)
			local cx = math.clamp(lp.X, -p.Size.X / 2, p.Size.X / 2)
			local cz = math.clamp(lp.Z, -p.Size.Z / 2, p.Size.Z / 2)
			local wpt = p.CFrame:PointToWorldSpace(Vector3.new(cx, p.Size.Y / 2, cz))
			local d = (Vector3.new(wpt.X, 0, wpt.Z) - Vector3.new(o.X, 0, o.Z)).Magnitude
			if d < bestD then
				best, bestD = p, d
				bestP = p.CFrame:PointToWorldSpace(Vector3.new(cx, p.Size.Y / 2, 0))
				-- do lado +Z, olhar para o dique é olhar para −Z (LookVector)
				bestN = p.CFrame.LookVector * (if lp.Z >= 0 then 1 else -1)
			end
		end
	end
	return best, bestP, bestN
end

local function devGroundAt(x: number, z: number, fromY: number): Vector3
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.RespectCanCollide = true
	p.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local r = workspace:Raycast(Vector3.new(x, fromY + 60, z), Vector3.new(0, -400, 0), p)
	return if r then r.Position else Vector3.new(x, fromY, z)
end

local function devMov(cmd: string)
	local _, hum, root = body()
	if cmd == "info" then
		dev.info = not dev.info
		devSay(if dev.info then "leitura ligada" else "leitura desligada")
	elseif cmd == "vc" or cmd == "eua" then
		dev.faction = if cmd == "vc" then "VC" else "US"
		loadKg = computeLoad()
		devSay(
			string.format(
				"lado fingido: %s (velocidade ×%.2f, %.1f kg)",
				dev.faction :: string,
				Movement.factionSpeed(dev.faction),
				loadKg
			)
		)
	elseif cmd == "nada" then
		dev.info, dev.faction = false, nil
		loadKg = computeLoad()
	elseif not (hum and root) then
		devSay("sem personagem em campo")
	elseif cmd == "agua" or cmd == "fundo" or cmd == "mar" then
		devSay("procurando água (até ~200 m)...")
		local lo, hi = 0.3, 1.1
		if cmd == "fundo" then
			lo, hi = 1.8, 30
		elseif cmd == "mar" then
			lo, hi = 0.4, 1.0
		end
		local pos, depth = devFindWater(lo, hi, cmd == "mar")
		if pos then
			devPlace(pos, flatLook())
			devSay(
				string.format("água com leito de %.2f m (modo esperado: %s)", depth, Movement.waterMode("dry", depth))
			)
		else
			devSay("nenhuma água assim por perto: chegue mais perto do riacho ou do mar e repita")
		end
	elseif cmd == "arrozal" then
		local part = devNearestPart("PaddyWater")
		if part then
			local p = (part :: BasePart).Position
			devPlace(devGroundAt(p.X, p.Z, p.Y), flatLook())
			devSay("no meio do tabuleiro")
		else
			devSay("nenhum tabuleiro carregado por perto")
		end
	elseif cmd == "dique" then
		local part, at, n = devNearestPart("Dikes")
		if part then
			local seat = (hum :: Humanoid).SeatPart
			local away = if seat then 9 else 1.6 -- m antes da face (veículo: o casco inteiro antes)
			local p = at - n * (((part :: BasePart).Size.Z / 2) + away / M)
			devPlace(devGroundAt(p.X, p.Z, at.Y), n)
			devSay(string.format("de frente para um dique de %.2f m de altura", (part :: BasePart).Size.Y * M))
		else
			devSay("nenhum dique carregado por perto")
		end
	elseif cmd ~= "" then
		devSay("comando desconhecido: " .. cmd)
	end
end

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevMov"):Connect(function()
		local v = workspace:GetAttribute("VT65DevMov")
		if type(v) == "string" and v ~= "" and v ~= "veiculo" then -- "veiculo": VehicleController
			task.spawn(devMov, string.lower(v))
			workspace:SetAttribute("VT65DevMov", nil) -- só local: no cliente o mesmo valor repete
		end
	end)
end

-- ===== laço por quadro (física): fôlego, corrida, pulo, sonda, água =====
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
		applyWater(c, h)
	end
	if now >= loadAt then
		loadAt = now + 1
		loadKg = computeLoad()
	end
	if air.active then
		air.maxY = math.max(air.maxY, r.Position.Y)
	end
	-- vadeando, o corpo não boia (sem Swimming, só a perna fica na água e o empuxo não vence o peso;
	-- se o avatar for leve demais, empurra de volta para o fundo)
	local v = r.AssemblyLinearVelocity
	if water.mode == "wade" and h:GetState() == Enum.HumanoidStateType.Freefall and not vault then
		water.sinkT = if v.Y > -1 then water.sinkT + dt else 0
		if water.sinkT > 0.25 then
			r.AssemblyLinearVelocity = Vector3.new(v.X, -6, v.Z)
		end
	else
		water.sinkT = 0
	end
	local d = dive
	if d and now - d.t0 >= Movement.DIVE_S then
		dive = nil
		land.t0, land.dip = now, 0.05 -- o peito chega ao chão
	end
	-- fôlego pelo esforço real (velocidade medida, não o pedido)
	local st = stanceOf(c)
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
		waterM = math.min(probe.waterM, 3),
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
	if dev.info and now >= dev.infoAt then
		dev.infoAt = now + 0.5
		devSay(
			string.format(
				"chão %s (fator %.2f) | água: leito %s, %s | estado %s | %.2f m/s (pedido %.2f) | lado %s ×%.2f | %.1f kg",
				probe.surface,
				probe.groundK,
				if probe.waterM == math.huge then "sem fundo" else string.format("%.2f m", probe.waterM),
				water.mode,
				h:GetState().Name,
				speed,
				vel.Magnitude * M,
				tostring(myFaction()),
				Movement.factionSpeed(myFaction()),
				loadKg
			)
		)
	end
end)
