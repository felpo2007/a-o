--!strict
-- Serviços de campo da Parte 12, todos validados no servidor:
--   configurações de controle salvas na conta (Settings_Get / Settings_Save);
--   tipo de entrada de cada jogador (Input_Type): atributo + AnalyticsService, para medir
--     equilíbrio controle x mouse (Parte 12.4);
--   marcações e mensagens predefinidas para o squad ou o comando (sem digitar, Parte 12.5);
--   granadas de fragmentação e de fumaça;
--   corpo a corpo: faca, facão, baioneta e coronhada (D-94, Modules/MeleeService + Shared/Melee).
-- Números marcados PLACEHOLDER estão na D-43.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comms = require(ReplicatedStorage.Shared.Comms)
local Kit = require(ReplicatedStorage.Shared.Kit)
local Radio = require(ReplicatedStorage.Shared.Radio)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Smoke = require(ReplicatedStorage.Shared.Smoke)
local ExplosionService = require(script.Parent.ExplosionService)
local MeleeService = require(script.Parent.MeleeService)
local PlayerData = require(script.Parent.PlayerData)

local FieldService = {}
local M = 0.28
local rng = Rng.new(1965)
local last: { [Player]: { [string]: number } } = {}

local function throttle(p: Player, key: string, seconds: number): boolean
	last[p] = last[p] or {}
	local now = os.clock()
	if now - (last[p][key] or 0) < seconds then
		return false
	end
	last[p][key] = now
	return true
end

local function alive(p: Player): Model?
	local c = p.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if c and hum and hum.Health > 0 and not c:GetAttribute("Downed") then
		return c
	end
	return nil
end

local function finite(v: any): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

-- ===== marcações e mensagens =====
local function recipients(p: Player, channel: string): { Player }
	local out = {}
	local f, sq = p:GetAttribute("Faction"), p:GetAttribute("SquadId")
	for _, o in Players:GetPlayers() do
		if o:GetAttribute("Faction") == f then
			if channel == "command" then
				local r = o:GetAttribute("Role")
				if o == p or r == "commander" or r == "squad_leader" then
					table.insert(out, o)
				end
			elseif sq ~= nil and o:GetAttribute("SquadId") == sq then
				table.insert(out, o)
			end
		end
	end
	if #out == 0 then
		table.insert(out, p)
	end
	return out
end

local markRng = Random.new()
local function onMark(p: Player, req: any)
	local c = alive(p)
	if not c or type(req) ~= "table" or not finite(req.pos) or not throttle(p, "mark", 1) then
		return
	end
	local pos: Vector3 = req.pos
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- marcação de lugar (não revela inimigo): até 1.500 m de onde o jogador está
	if root and (pos - root.Position).Magnitude * M > 1500 then
		return
	end
	local kind = if req.kind == "target" or req.kind == "map" then req.kind else "point"
	local msg = { x = pos.X, y = pos.Y, z = pos.Z, from = p.DisplayName, kind = kind } :: any
	if kind == "target" and root then
		-- inimigo: área aproximada (erro cresce com a distância); quem recebe não sabe o ponto exato
		local r = Comms.markError((pos - root.Position).Magnitude * M)
		local ox, oz = Comms.markOffset(r, markRng:NextNumber(), markRng:NextNumber())
		msg.x, msg.z = pos.X + ox / M, pos.Z + oz / M
		msg.r, msg.ttl = r, Comms.MARK_TTL_S
	end
	for _, o in recipients(p, "squad") do
		Net.event("Squad_Mark"):FireClient(o, msg)
	end
end

local function onMessage(p: Player, req: any)
	if
		type(req) ~= "table"
		or type(req.id) ~= "string"
		or not Comms.MESSAGES[req.id]
		or not throttle(p, "msg", 1.5)
	then
		return
	end
	local channel = if req.channel == "command" then "command" else "squad"
	-- canal Comando: só com o rádio do squad (Parte 11), o comandante ou o morteiro
	if
		channel == "command"
		and not Radio.canTalkToCommand(p:GetAttribute("Role") :: string?, p:GetAttribute("Radio") == true)
	then
		Net.event("Squad_Message"):FireClient(p, { id = "no_radio", from = "", channel = "squad" })
		return
	end
	for _, o in recipients(p, channel) do
		Net.event("Squad_Message"):FireClient(o, { id = req.id, from = p.DisplayName, channel = channel })
	end
end

-- ===== granadas =====
-- D-77 (pedido do dono: "granadas com qualidade de movimento de arremesso e gráficos"):
-- - modelo de verdade em peças: M26 (corpo de limão verde-oliva, espoleta e alavanca), granada de
--   cabo do VC (cabeça de ferro e cabo de madeira, gira de ponta) e a lata de fumaça M18;
-- - a gravidade do Roblox é 196,2 studs/s² (55 m/s²): a granada caía a 3–4 m da mão. Uma força
--   para cima deixa a granada com 9,81 m/s² e o voo sai na distância real (~30 m a 45°);
-- - quica e rola (atrito e elasticidade de ferro na terra), gira no ar;
-- - braço direito arma atrás da cabeça e lança (RightShoulder.C0, visto por todos); a granada sai
--   da mão em RELEASE_S, o mesmo tempo da animação em 1ª pessoa (WeaponVisuals);
-- - bots arremessam com FieldService.throwFrom (balística para cair no alvo).
local THROW_MS = 17 -- velocidade de arremesso (PLACEHOLDER; arremesso de granada de 30–40 m)
local FUSE_S = { US = 4.5, VC = 4.0 } -- espoleta (PLACEHOLDER: M26 4–5 s; cabo chinês ~4 s)
local SMOKE_FUSE_S = 1.5
local RELEASE_S = 0.4 -- do pedido à saída da mão
local THROW_S = 0.8 -- animação inteira
local G_REAL = 9.81 / M -- studs/s²
local smokeFolder: Folder
local grenadeFolder: Folder
local spawnSmoke: (pos: Vector3) -> () -- definida mais abaixo

-- Núcleo de colisão de 1 stud (invisível): bola menor que ~0,5 stud atravessa o terreno do Roblox
-- (Studio, 2026-11-11: a de 7 cm caiu a -166). A granada desenhada (Shared/GrenadeArt) é posta
-- pelo cliente em cima dele (ExplosionFx), encostada no chão quando para.
local function grenadeModel(kind: string, faction: string?): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "Granada"
	m:SetAttribute("Kind", kind)
	m:SetAttribute("Faction", faction or "US")
	local core = Instance.new("Part")
	core.Name = "Nucleo"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.one
	core.Transparency = 1
	core.CastShadow = false
	core.CanQuery = false
	core.CanTouch = false
	-- ferro na terra: atrito médio, quica pouco (densidade, atrito, elasticidade)
	core.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.6, 0.28, 1, 1)
	core.Parent = m
	m.PrimaryPart = core
	return m, core
end

-- Braço direito armando atrás da cabeça e lançando (graus: pitch, roll no ombro), visto por todos.
local THROW_KEYS = { { 0, 0, 0 }, { 0.3, -150, 18 }, { 0.5, 105, 8 }, { 0.66, 45, 0 }, { 1, 0, 0 } }
local function throwRot(t: number): CFrame
	for i = 1, #THROW_KEYS - 1 do
		local a, b = THROW_KEYS[i], THROW_KEYS[i + 1]
		if t <= b[1] then
			local k = math.clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
			k = k * k * (3 - 2 * k)
			return CFrame.Angles(math.rad(a[2] + (b[2] - a[2]) * k), 0, math.rad(a[3] + (b[3] - a[3]) * k))
		end
	end
	return CFrame.identity
end

-- O corpo "Man" (D-70) tem juntas AnimationConstraint, não Motor6D: o C0 não existe nelas (o
-- primeiro teste dava "Unable to assign property C0" a cada arremesso). Gira-se então o encaixe do
-- lado do tronco (Attachment0), que vale para os dois tipos de junta e replica para todos.
local function throwPose(model: Model)
	local ua = model:FindFirstChild("RightUpperArm")
	local sh = ua and ua:FindFirstChild("RightShoulder")
	if not sh or model:GetAttribute("Throwing") then
		return
	end
	local set: ((CFrame) -> ())?, base: CFrame? = nil, nil
	if sh:IsA("Motor6D") then
		local motor = sh
		base = motor.C0
		set = function(cf: CFrame)
			motor.C0 = cf
		end
	elseif sh:IsA("AnimationConstraint") and sh.Attachment0 then
		local att = sh.Attachment0 :: Attachment
		base = att.CFrame
		set = function(cf: CFrame)
			att.CFrame = cf
		end
	end
	local apply, rest = set, base
	if not apply or not rest then
		return
	end
	model:SetAttribute("Throwing", true)
	task.spawn(function()
		local t0 = os.clock()
		while sh.Parent do
			local t = (os.clock() - t0) / THROW_S
			if t >= 1 then
				break
			end
			apply(rest * throwRot(t))
			task.wait(1 / 30)
		end
		if sh.Parent then
			apply(rest)
		end
		model:SetAttribute("Throwing", nil)
	end)
end
FieldService.throwRot = throwRot -- teste

local function launch(kind: string, faction: string?, from: Vector3, vel: Vector3, by: Player?)
	local m, core = grenadeModel(kind, faction)
	m:PivotTo(CFrame.lookAt(from, from + vel) * CFrame.Angles(0, math.pi / 2, 0))
	m.Parent = grenadeFolder
	-- gravidade real: o Roblox puxa com workspace.Gravity; a força devolve a diferença
	local att = Instance.new("Attachment")
	att.Parent = core
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.new(0, core.AssemblyMass * math.max(workspace.Gravity - G_REAL, 0), 0)
	vf.Parent = core
	core:SetNetworkOwner(nil)
	core.AssemblyLinearVelocity = vel
	-- gira no ar: a de cabo vira de ponta, a M26 rola de lado
	core.AssemblyAngularVelocity = if faction == "VC" and kind ~= "smoke"
		then Vector3.new(0, 0, rng:range(-16, -10))
		else Vector3.new(rng:range(-8, 8), rng:range(-4, 4), rng:range(-8, 8))
	-- freio no chão: a bola do Roblox rola sem atrito de rolamento e a granada seguia a 6 m/s por
	-- mais 10 m depois de cair (Studio, 2026-11-11); granada de verdade quica e para em 1–3 m
	task.spawn(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { m }
		while m.Parent do
			task.wait(0.1)
			if workspace:Raycast(core.Position, Vector3.new(0, -0.75, 0), params) then
				core.AssemblyLinearVelocity *= 0.72
				core.AssemblyAngularVelocity *= 0.72
			end
		end
	end)
	local fuse = if kind == "smoke" then SMOKE_FUSE_S else (FUSE_S[faction or "US"] or 4.5)
	task.delay(fuse, function()
		if not m.Parent then
			return
		end
		local pos = core.Position
		if kind == "smoke" then
			spawnSmoke(pos)
			task.delay(Smoke.DURATION_S, function()
				m:Destroy()
			end)
		else
			m:Destroy()
			ExplosionService.detonate(if faction == "VC" then "grenade_vc" else "grenade_us", pos, by)
		end
	end)
end

-- Bot (ou qualquer modelo) arremessa no alvo: arco de 40° que cai em target, com a mesma animação
-- e a mesma espera de saída da mão do jogador. Devolve false se não dá (sem cabeça, já
-- arremessando, alvo alto demais para o arco).
function FieldService.throwFrom(model: Model, faction: string, kind: string, target: Vector3, by: Player?): boolean
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head or model:GetAttribute("Throwing") or model:GetAttribute("Downed") then
		return false
	end
	local from = head.Position + Vector3.new(0, 0.15 / M, 0)
	local flat = (target - from) * Vector3.new(1, 0, 1)
	local d = flat.Magnitude
	if d < 1 then
		return false
	end
	local h = target.Y - from.Y
	local th = math.rad(40)
	local denom = 2 * math.cos(th) ^ 2 * (d * math.tan(th) - h)
	if denom <= 0 then
		return false
	end
	local v = math.min(math.sqrt(G_REAL * d * d / denom), 22 / M)
	local vel = (flat.Unit * math.cos(th) + Vector3.new(0, math.sin(th), 0)) * v
	throwPose(model)
	task.delay(RELEASE_S, function()
		if model.Parent and not model:GetAttribute("Downed") then
			local hd = model:FindFirstChild("Head") :: BasePart?
			launch(kind, faction, if hd then hd.Position + flat.Unit * (0.4 / M) else from, vel, by)
		end
	end)
	return true
end

spawnSmoke = function(pos: Vector3)
	local p = Instance.new("Part")
	p.Name = "Cloud"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos + Vector3.new(0, 1.5 / M, 0)
	p:SetAttribute("R", Smoke.RADIUS_M / M)
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 40
	pe.Lifetime = NumberRange.new(8, 12)
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 22) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(205, 205, 200))
	pe.Parent = p
	p.Parent = smokeFolder
	task.delay(Smoke.DURATION_S, function()
		pe.Enabled = false
		task.wait(12)
		p:Destroy()
	end)
end

local function onThrow(p: Player, req: any)
	local c = alive(p)
	if not c or type(req) ~= "table" or not finite(req.dir) or not throttle(p, "throw", 1.2) then
		return
	end
	local kind = if req.kind == "smoke" then "smoke" else "frag"
	local attr = if kind == "smoke" then "Smokes" else "Frags"
	local left = (p:GetAttribute(attr) :: number?) or 0
	if left <= 0 then
		return
	end
	p:SetAttribute(attr, left - 1)
	if not c:FindFirstChild("Head") then
		return
	end
	local dir: Vector3 = (req.dir :: Vector3).Unit
	local faction = p:GetAttribute("Faction") :: string?
	throwPose(c)
	-- sai da mão junto com a animação de 1ª pessoa; da frente da cabeça (o que o jogador mirou)
	task.delay(RELEASE_S, function()
		local head = c:FindFirstChild("Head") :: BasePart?
		if not head or alive(p) ~= c then
			return
		end
		local from = head.Position + dir * (0.5 / M) + Vector3.new(0, 0.05 / M, 0)
		launch(kind, faction, from, (dir + Vector3.new(0, 0.2, 0)).Unit * THROW_MS / M, p)
	end)
end

-- ===== corpo a corpo (D-94) =====
-- Regras no Shared/Melee; validação, acerto no instante do impacto, bots e efeitos no MeleeService.
-- Aqui só a porta de entrada: vivo, pedido bem formado e no máximo 8 pedidos por segundo (o
-- intervalo de cada golpe é conferido lá).
local function onMelee(p: Player, req: any)
	local c = alive(p)
	if not c or type(req) ~= "table" or not finite(req.dir) or not throttle(p, "melee", 0.12) then
		return
	end
	MeleeService.onRequest(p, req)
end

function FieldService.start()
	smokeFolder = Instance.new("Folder")
	smokeFolder.Name = "Smoke"
	smokeFolder.Parent = workspace
	grenadeFolder = Instance.new("Folder")
	grenadeFolder.Name = "Granadas"
	grenadeFolder.Parent = workspace

	Net.func("Settings_Get").OnServerInvoke = function(p: Player)
		local prof = PlayerData.get(p)
		return InputMap.validate(prof and prof.settings)
	end
	Net.event("Settings_Save").OnServerEvent:Connect(function(p, raw)
		local prof = PlayerData.get(p)
		if prof and throttle(p, "settings", 1) then
			prof.settings = InputMap.validate(raw)
		end
	end)
	Net.event("Input_Type").OnServerEvent:Connect(function(p, t)
		if (t == "gamepad" or t == "kbm" or t == "touch") and throttle(p, "itype", 2) then
			if p:GetAttribute("InputType") ~= t then
				p:SetAttribute("InputType", t)
				pcall(function()
					AnalyticsService:LogCustomEvent(p, "input_type_" .. t)
				end)
			end
		end
	end)
	Net.event("Squad_Mark").OnServerEvent:Connect(onMark)
	Net.event("Squad_Message").OnServerEvent:Connect(onMessage)
	Net.event("Throw_Request").OnServerEvent:Connect(onThrow)
	Net.event("Combat_Melee").OnServerEvent:Connect(onMelee)
	MeleeService.start()
	Net.event("Posture_Set").OnServerEvent:Connect(function(p, req: any)
		if type(req) == "table" and type(req.bayonet) == "boolean" then
			FieldService.setBayonet(p, req.bayonet)
		end
	end)

	Net.event("Kit_Set").OnServerEvent:Connect(function(p: Player, raw: any)
		if not throttle(p, "kit", 0.5) then
			return
		end
		local wid = string.split(tostring(p:GetAttribute("Loadout") or ""), ",")[1]
		local wp = Weapons.get(wid)
		local k = Kit.validate(raw, if wp then wp.kind else "rifle")
		p:SetAttribute("KitMags", k.mags)
		p:SetAttribute("KitFrags", k.frags)
		p:SetAttribute("KitSmokes", k.smokes)
		p:SetAttribute("KitBandages", k.bandages)
	end)
	-- itens por vida: 2 granadas e 1 fumaça (PLACEHOLDER); baioneta começa recolhida
	local function arm(p: Player)
		p.CharacterAdded:Connect(function(c)
			-- equipamento por peso (Kit): validado no Kit_Set; padrão 2 granadas e 1 fumaça
			-- + equipamento liberado (D-72, ProgressionService.applyGear)
			local gf, gs = p:GetAttribute("GearFrags"), p:GetAttribute("GearSmokes")
			local kf, ks = p:GetAttribute("KitFrags"), p:GetAttribute("KitSmokes")
			p:SetAttribute("Frags", (if type(kf) == "number" then kf else 2) + (if type(gf) == "number" then gf else 0))
			p:SetAttribute(
				"Smokes",
				(if type(ks) == "number" then ks else 1) + (if type(gs) == "number" then gs else 0)
			)
			c:SetAttribute("Bayonet", false)
		end)
	end
	for _, p in Players:GetPlayers() do
		arm(p)
	end
	Players.PlayerAdded:Connect(arm)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
end

-- baioneta: o cliente pede; o servidor confere a arma na mão (a do chão, se pegou uma) e põe a
-- baioneta na boca do fuzil (todos veem)
function FieldService.setBayonet(p: Player, on: boolean)
	local c = alive(p)
	if not c then
		return
	end
	local w = c:FindFirstChild("Weapon")
	local wid = w and w:GetAttribute("WeaponId")
	if type(wid) ~= "string" then
		local lo = p:GetAttribute("Loadout")
		wid = if type(lo) == "string" then string.split(lo, ",")[1] else nil
	end
	MeleeService.setBayonet(c, on, if type(wid) == "string" then wid else nil)
end

return FieldService
