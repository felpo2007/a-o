--!strict
-- Caído e corpos no cliente (D-107; números em Shared/SoldierAnims e Shared/Corpos), para TODO
-- soldado (jogadores e bots), como as outras poses: o que se muda aqui é local, cada cliente faz o
-- mesmo pelos atributos do servidor.
-- 1. Caído ("Downed"): o servidor (PostureService.setDowned) deita o corpo de costas pela junta
--    Root; aqui entra a pose de ferido (SoldierAnims.downedPose: cabeça virada, mão no flanco,
--    joelho dobrado, respiração curta, mexendo pouco) por cima do Animator (PreSimulation), e a
--    queda de DOWNED.fallS contada de "VT65CaidoT" (relógio do servidor: todos veem juntos). O fuzil
--    sai da mão: o de verdade fica escondido e uma cópia parada fica no chão ao lado, até levantar.
-- 2. Corpo (workspace.Corpos, CorposService): com "VT65Some" ele apaga em "VT65SomeS" segundos.
-- A queda do morto (boneco de pano) é do servidor e replica sozinha.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Corpos = require(ReplicatedStorage.Shared.Corpos)
local Joints = require(ReplicatedStorage.Shared.Joints)
local SoldierAnims = require(ReplicatedStorage.Shared.SoldierAnims)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = SoldierAnims.STUD_M
local POSE_RADIUS = 400 -- studs (~110 m); mais longe o caído fica no deitado reto do servidor
local GUN_SIDE = 3.4 -- studs do quadril até o fuzil no chão, do lado do braço solto
local GUN_FEET = 0.4 -- studs para o lado dos pés

type Caido = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	joints: { [string]: Instance },
	rootJ: Instance?,
	y0: number, -- altura do HRP quando o vi cair (a queda desconta o que ele já desceu)
	seed: number,
	gun: Model?, -- cópia do fuzil no chão
	hidden: { BasePart }, -- peças do fuzil de verdade escondidas
	touched: boolean,
}
local caidos: { [Model]: Caido } = {}

local function setTransform(j: Instance, cf: CFrame)
	(j :: any).Transform = cf
end
local function getTransform(j: Instance): CFrame
	return (j :: any).Transform
end

local function soldiers(): { Model }
	local list: { Model } = {}
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

local function seedOf(m: Model): number
	local p = Players:GetPlayerFromCharacter(m)
	if p then
		return p.UserId
	end
	local b = m:GetAttribute("BotIndex")
	return if type(b) == "number" then b else #m.Name
end

-- ===== fuzil no chão =====
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function dropGun(c: Caido)
	if c.gun or c.model == player.Character then
		return
	end
	local w = c.model:FindFirstChild("Weapon")
	if not (w and w:IsA("Model") and w.PrimaryPart) then
		return
	end
	local ok, copy = pcall(function(): Model?
		return w:Clone()
	end)
	if not ok or not copy then
		return
	end
	local gun = copy :: Model
	for _, d in gun:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.LocalTransparencyModifier = 0
		end
	end
	-- do lado do braço solto (a pose espelhada troca o lado), boca para os pés
	local side = if c.seed % 2 == 1 then -1 else 1
	local rcf = c.root.CFrame
	local at = rcf * Vector3.new(side * GUN_SIDE, 0, -GUN_FEET)
	local skip: { Instance } = { gun }
	for _, m in soldiers() do
		table.insert(skip, m)
	end
	local corpos = workspace:FindFirstChild("Corpos")
	if corpos then
		table.insert(skip, corpos)
	end
	groundParams.FilterDescendantsInstances = skip
	-- do meio do HRP para baixo (num túnel o raio não nasce no teto)
	local hit = workspace:Raycast(at + Vector3.new(0, 1, 0), Vector3.new(0, -10, 0), groundParams)
	local ground = if hit then hit.Position else at - Vector3.new(0, c.hum.HipHeight + c.root.Size.Y / 2, 0)
	local look = rcf.LookVector
	local yaw = math.atan2(-look.X, -look.Z) + math.rad(((c.seed * 37) % 41) - 20)
	local lowX = w:GetAttribute("LowX")
	local lift = (if type(lowX) == "number" then -lowX else 0.025 / M) + 0.005 / M
	gun:PivotTo(
		CFrame.new(ground + Vector3.new(0, lift, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.pi / 2)
	)
	gun.Name = "VT65FuzilCaido"
	gun.Parent = workspace
	c.gun = gun
end

local function hideGun(c: Caido)
	if #c.hidden > 0 or c.model == player.Character then
		return
	end
	local w = c.model:FindFirstChild("Weapon")
	if not w then
		return
	end
	for _, d in w:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			table.insert(c.hidden, d)
		end
	end
end

-- ===== caídos =====
local POSE_JOINTS: { string } = {}
for name in SoldierAnims.DOWNED_POSE do
	table.insert(POSE_JOINTS, name)
end

local function release(c: Caido)
	caidos[c.model] = nil
	if c.gun then
		c.gun:Destroy()
		c.gun = nil
	end
	for _, p in c.hidden do
		p.LocalTransparencyModifier = 0
	end
	table.clear(c.hidden)
	if c.touched then
		-- juntas de volta ao repouso ANTES do Animator do quadro seguinte (ele reescreve as que tocar;
		-- a Root é do SoldierAnimations, que levanta suave do C0 de costas)
		local joints = c.joints
		RunService.PreAnimation:Once(function()
			for _, j in joints do
				setTransform(j, CFrame.identity)
			end
		end)
	end
end

local function refresh()
	local cam = camera.CFrame.Position
	local seen: { [Model]: boolean } = {}
	for _, m in soldiers() do
		local hum = m:FindFirstChildOfClass("Humanoid")
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if
			hum
			and root
			and hum.Health > 0
			and m:GetAttribute("Downed") == true
			and (root.Position - cam).Magnitude <= POSE_RADIUS
		then
			seen[m] = true
			if not caidos[m] then
				local lower = m:FindFirstChild("LowerTorso")
				caidos[m] = {
					model = m,
					hum = hum,
					root = root,
					joints = {},
					rootJ = if lower then Joints.find(lower, "Root") else nil,
					y0 = root.Position.Y,
					seed = seedOf(m),
					gun = nil,
					hidden = {},
					touched = false,
				}
			end
		end
	end
	for m, c in caidos do
		if not seen[m] or not m.Parent then
			release(c)
		end
	end
end

local function poseOne(c: Caido, now: number)
	local caidoT = c.model:GetAttribute("VT65CaidoT")
	local el = if type(caidoT) == "number" then now - caidoT else math.huge
	local e, b = SoldierAnims.fallBlend(el)
	local pose = SoldierAnims.downedPose(now, c.seed)
	for _, name in POSE_JOINTS do
		local j = c.joints[name]
		if not j then
			local found = Joints.find(c.model, name)
			if found then
				c.joints[name] = found
				j = found
			end
		end
		local a = pose[name]
		if j and a then
			local buckle = (SoldierAnims.FALL_BUCKLE[name] or 0) * b
			local target = CFrame.Angles(math.rad(a[1] + buckle), math.rad(a[2]), math.rad(a[3]))
			setTransform(j, if e >= 1 then target else getTransform(j):Lerp(target, e))
		end
	end
	-- Root: o servidor já girou o C0 de costas; na queda, começa de pé (desfaz o C0 e sobe o que o
	-- HRP já desceu) e deita com e
	local rj = c.rootJ
	if rj then
		if e >= 1 then
			setTransform(rj, CFrame.identity)
		else
			local c0, rest = Joints.getC0(rj), Joints.rest(rj)
			if c0 and rest then
				local m = math.clamp(c.y0 - c.root.Position.Y, 0, 8)
				local lift = CFrame.new(c0:VectorToObjectSpace(Vector3.new(0, m, 0)))
				setTransform(rj, (lift * c0:Inverse() * rest):Lerp(CFrame.identity, e))
			end
		end
	end
	c.touched = true
	hideGun(c)
	if e >= 1 then
		dropGun(c)
	end
end

-- ===== corpos que somem =====
type Sumindo = { t0: number, dur: number }
local sumindo: { [Model]: Sumindo } = {}

local function watchCorpse(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local m = inst :: Model
	local function check()
		local t0 = m:GetAttribute("VT65Some")
		local dur = m:GetAttribute("VT65SomeS")
		if type(t0) == "number" and not sumindo[m] then
			sumindo[m] = { t0 = t0, dur = if type(dur) == "number" then dur else Corpos.SUMIR_S }
		end
	end
	m:GetAttributeChangedSignal("VT65Some"):Connect(check)
	check()
end

task.spawn(function()
	local folder = workspace:WaitForChild("Corpos", 60)
	if not folder then
		return
	end
	folder.ChildAdded:Connect(watchCorpse)
	for _, m in folder:GetChildren() do
		watchCorpse(m)
	end
end)

local nextRefresh = 0
RunService.PreSimulation:Connect(function()
	local t = os.clock()
	if t >= nextRefresh then
		nextRefresh = t + 0.2
		refresh()
	end
	if next(caidos) == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	for m, c in caidos do
		if m.Parent and c.hum.Health > 0 and m:GetAttribute("Downed") == true then
			poseOne(c, now)
		else
			release(c)
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if next(sumindo) == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	for m, s in sumindo do
		if not m.Parent then
			sumindo[m] = nil
			continue
		end
		local a = Corpos.apagado(now, s.t0, s.dur)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = a
			end
		end
	end
end)
