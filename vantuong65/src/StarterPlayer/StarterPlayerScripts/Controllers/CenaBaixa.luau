--!strict
-- Cena da tela de baixa (pedido do dono, 2026-11-13: "melhore a tela de morte, principalmente o
-- personagem"; antes era o soldado de pé, com a arma no meio da pega). Agora o próprio soldado (o
-- retrato tirado em vida: farda, equipamento e capacete dele) aparece CAÍDO de costas num pedaço de
-- chão de terra, com a arma largada ao lado, visto do alto (câmera a ~52°, de lado e dos pés), com
-- luz quente de cima e um respiro lento da câmera.
-- A pose é montada aqui, num clone parado: cada peça vai para o lugar que a junta mandaria
-- (Parte1 = Parte0 · C0 · pose · C1⁻¹), pelas juntas do R15 (Motor6D ou AnimationConstraint; o C0 de
-- repouso vem do atributo RestC0 quando a postura mexeu nele, Shared/Joints). Solda, acessório e
-- equipamento seguem a peça a que estão presos. Nada roda por quadro fora do respiro (tween).
-- Sem retrato (morreu logo depois de nascer), o manequim do lado (ReplicatedStorage.VT65Preview).
-- O SoldierPreview (frente de movimento/corpo) não é usado aqui: a pose e o enquadramento são desta
-- tela. Pose nova: mexa em POSE (graus, no quadro de cada junta; PLACEHOLDER até a foto no Studio).
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))

local CenaBaixa = {}

local FOV = 30
local ELEV = math.rad(52) -- altura da câmera
local CAM_DIR = Vector3.new(-0.62, 0, -0.78).Unit -- do lado esquerdo do soldado, dos pés
local DRIFT = math.rad(3) -- respiro da câmera (± graus em volta do soldado)
local FILL = 0.84 -- quanto da janela o soldado ocupa (esfera da caixa)
local GROUND = Color3.fromRGB(58, 42, 32)
local GROUND_EDGE = Color3.fromRGB(40, 26, 20)
local EDGE = Color3.fromRGB(54, 12, 10) -- o vermelho do fundo da tela de baixa (Estilo.V.BG_RED)

-- Pose de caído de costas (graus: x, y, z no quadro da junta). Braço direito largado no chão, mão
-- esquerda sobre o peito, joelho esquerdo dobrado, cabeça virada para a câmera.
local function deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end
local POSE: { [string]: CFrame } = {
	Root = CFrame.identity,
	Waist = deg(-6, 10, 0),
	Neck = deg(-12, 38, 8),
	RightShoulder = deg(10, 0, 78),
	RightElbow = deg(15, 0, 0),
	RightWrist = deg(0, 0, -10),
	LeftShoulder = deg(30, 0, 12),
	LeftElbow = deg(115, 0, 0),
	LeftWrist = deg(0, 0, 0),
	RightHip = deg(4, 0, 10),
	RightKnee = deg(-8, 0, 0),
	RightAnkle = deg(-20, 0, 0),
	LeftHip = deg(42, 0, -8),
	LeftKnee = deg(-78, 0, 0),
	LeftAnkle = deg(-50, 0, 0),
}
-- o corpo deitado: costas no chão (a frente olha o céu), cabeça para +Z, um pouco virado de lado
local LYING = CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, math.rad(12), 0)

export type Cena = {
	frame: Frame,
	vp: ViewportFrame,
	world: WorldModel,
	cam: Camera,
	model: Model?,
	center: Vector3,
	dist: number,
	angle: Instance, -- NumberValue do respiro
	drift: Tween?,
}

-- tudo parado e sem scripts; o corpo visível mesmo em 1ª pessoa
local function freeze(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		elseif
			d:IsA("BaseScript")
			or d:IsA("ModuleScript")
			or d:IsA("Sound")
			or d:IsA("ParticleEmitter")
			or d:IsA("Trail")
			or d:IsA("Beam")
			or d:IsA("Light")
			or d:IsA("BillboardGui")
			or d:IsA("Highlight")
			or d:IsA("ForceField")
		then
			d:Destroy()
		end
	end
	local hum = root:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			hum.EvaluateStateMachine = false
		end)
	end
end

-- junta do R15: (peça 0, peça 1, C0 de repouso, C1) de um Motor6D ou de uma AnimationConstraint
local function jointParts(j: Instance): (BasePart?, BasePart?, CFrame?, CFrame?)
	if j:IsA("Motor6D") then
		local rest = j:GetAttribute("RestC0")
		return j.Part0, j.Part1, if typeof(rest) == "CFrame" then rest else j.C0, j.C1
	elseif j:IsA("AnimationConstraint") then
		local a0, a1 = j.Attachment0, j.Attachment1
		if not (a0 and a1) then
			return nil, nil, nil, nil
		end
		local p0, p1 = a0.Parent, a1.Parent
		local rest = a0:GetAttribute("RestC0")
		return if p0 and p0:IsA("BasePart") then p0 else nil,
			if p1 and p1:IsA("BasePart") then p1 else nil,
			if typeof(rest) == "CFrame" then rest else a0.CFrame,
			a1.CFrame
	end
	return nil, nil, nil, nil
end

-- outras ligações (solda, acessório, equipamento): só as duas peças; a posição relativa fica
local function rigidParts(j: Instance): (BasePart?, BasePart?)
	if j:IsA("JointInstance") then
		return (j :: any).Part0, (j :: any).Part1
	elseif j:IsA("WeldConstraint") or j:IsA("NoCollisionConstraint") then
		return (j :: any).Part0, (j :: any).Part1
	elseif j:IsA("RigidConstraint") then
		local a0, a1 = (j :: any).Attachment0, (j :: any).Attachment1
		local p0 = if a0 then a0.Parent else nil
		local p1 = if a1 then a1.Parent else nil
		return if p0 and p0:IsA("BasePart") then p0 else nil, if p1 and p1:IsA("BasePart") then p1 else nil
	end
	return nil, nil
end

-- caixa no mundo (mínimo e máximo) das peças visíveis; skip: peças de fora (a arma)
local function bounds(parts: { BasePart }): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in parts do
		if p.Transparency < 0.99 then
			local cf, s = p.CFrame, p.Size / 2
			local r = cf.RightVector * s.X
			local u = cf.UpVector * s.Y
			local b = cf.LookVector * s.Z
			local ext = Vector3.new(
				math.abs(r.X) + math.abs(u.X) + math.abs(b.X),
				math.abs(r.Y) + math.abs(u.Y) + math.abs(b.Y),
				math.abs(r.Z) + math.abs(u.Z) + math.abs(b.Z)
			)
			lo = lo:Min(cf.Position - ext)
			hi = hi:Max(cf.Position + ext)
		end
	end
	return lo, hi
end

local function partsOf(root: Instance, skip: Instance?): { BasePart }
	local out: { BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not (skip and d:IsDescendantOf(skip)) then
			table.insert(out, d)
		end
	end
	return out
end

-- v44: em pé para o retrato, braços ao lado do corpo (o repouso do R15) e a cabeça reta, um pouco
-- erguida. As mesmas juntas da pose de caído (as que não estão aqui ficam no repouso).
local POSE_STAND: { [string]: CFrame } = {
	Root = CFrame.identity,
	Waist = CFrame.identity,
	Neck = deg(6, 0, 0),
	RightShoulder = deg(0, 0, 4),
	RightElbow = CFrame.identity,
	RightWrist = CFrame.identity,
	LeftShoulder = deg(0, 0, -4),
	LeftElbow = CFrame.identity,
	LeftWrist = CFrame.identity,
	RightHip = CFrame.identity,
	RightKnee = CFrame.identity,
	RightAnkle = CFrame.identity,
	LeftHip = CFrame.identity,
	LeftKnee = CFrame.identity,
	LeftAnkle = CFrame.identity,
}

-- Deita o modelo (já parado) na pose de caído, com a arma largada ao lado, os pés no chão (y = 0).
-- v44: rootCF/poses trocam a pose (o retrato em pé usa POSE_STAND e tira a arma).
local function lay(m: Model, rootCF: CFrame?, poses: { [string]: CFrame }?)
	local P = poses or POSE
	local R = rootCF or LYING
	local root = m:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		m:PivotTo(R)
		return
	end
	local weapon = m:FindFirstChild("Weapon")
	local skip: Instance? = if weapon and weapon:IsA("Model") then weapon else nil
	local parts = partsOf(m, skip)
	local orig: { [BasePart]: CFrame } = {}
	for _, p in parts do
		orig[p] = p.CFrame
	end
	-- ligações: as juntas do corpo com a pose; o resto rígido
	type Edge = { other: BasePart, joint: Instance?, forward: boolean }
	local adj: { [BasePart]: { Edge } } = {}
	local function add(a: BasePart, e: Edge)
		local list = adj[a]
		if not list then
			list = {}
			adj[a] = list
		end
		table.insert(list :: { Edge }, e)
	end
	local function link(a: BasePart?, b: BasePart?, j: Instance?)
		if a and b and orig[a] and orig[b] then
			add(a, { other = b, joint = j, forward = true })
			add(b, { other = a, joint = j, forward = false })
		end
	end
	for _, d in m:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and P[d.Name] then
			local p0, p1 = jointParts(d)
			link(p0, p1, d)
		else
			local p0, p1 = rigidParts(d)
			link(p0, p1, nil)
		end
	end
	local placed: { [BasePart]: CFrame } = { [root] = R }
	local done: { [BasePart]: boolean } = { [root] = true }
	local queue: { BasePart } = { root }
	local head = 1
	local none: { Edge } = {}
	while head <= #queue do
		local p = queue[head]
		head += 1
		local edges: { Edge } = adj[p] or none
		for _, e in edges do
			if not done[e.other] then
				done[e.other] = true
				local cf: CFrame
				local j = e.joint
				local c0: CFrame?, c1: CFrame? = nil, nil
				if j then
					local _, _, a0, a1 = jointParts(j)
					c0, c1 = a0, a1
				end
				if j and c0 and c1 then
					local pose = P[j.Name] or CFrame.identity
					if e.forward then
						cf = placed[p] * c0 * pose * c1:Inverse()
					else
						cf = placed[p] * c1 * pose:Inverse() * c0:Inverse()
					end
				else
					cf = placed[p] * orig[p]:ToObjectSpace(orig[e.other])
				end
				placed[e.other] = cf
				table.insert(queue, e.other)
			end
		end
	end
	-- o que não se liga a nada acompanha a raiz
	for _, p in parts do
		if not done[p] then
			placed[p] = R * orig[root]:ToObjectSpace(orig[p])
		end
		p.CFrame = placed[p]
	end
	-- a arma largada ao lado da mão direita, deitada de lado, quase paralela ao corpo (no retrato, sai)
	local hand = m:FindFirstChild("RightHand")
	if skip and poses then
		skip:Destroy()
	elseif skip then
		local w = skip :: Model
		local at = if hand and hand:IsA("BasePart") then hand.Position else root.Position
		local out = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z)
		out = if out.Magnitude > 0.01 then out.Unit else Vector3.new(1, 0, 0)
		local along = CFrame.Angles(0, math.rad(-25), 0):VectorToWorldSpace(Vector3.new(0, 0, 1))
		local pos = Vector3.new(at.X, 0, at.Z) + out * 1.4
		w:PivotTo(CFrame.lookAt(pos, pos + along) * CFrame.Angles(0, 0, math.rad(90)))
		local wlo = bounds(partsOf(w))
		if wlo.Y < math.huge then
			w:PivotTo(w:GetPivot() + Vector3.new(0, -wlo.Y, 0))
		end
	end
	-- o corpo encosta no chão
	local lo = bounds(parts)
	if lo.Y < math.huge then
		local dy = -lo.Y - 0.05
		for _, p in parts do
			p.CFrame += Vector3.new(0, dy, 0)
		end
	end
end

-- manequim completo do lado (o PreviewService marca quantas peças vêm: clone só com todas)
local function mannequin(faction: string?): Model?
	local folder = ReplicatedStorage:FindFirstChild("VT65Preview")
	local src = if folder and faction then folder:FindFirstChild(faction) else nil
	if not (src and src:IsA("Model")) then
		return nil
	end
	local want = src:GetAttribute("Parts")
	if type(want) == "number" and #partsOf(src) < want then
		return nil
	end
	local ok, made = pcall(function()
		return src:Clone()
	end)
	return if ok then made :: Model else nil
end

local function aim(c: Cena)
	local a = (c.angle :: any).Value :: number
	local dir = CFrame.Angles(0, a, 0):VectorToWorldSpace(CAM_DIR)
	local eye = c.center + (dir * math.cos(ELEV) + Vector3.new(0, math.sin(ELEV), 0)) * c.dist
	c.cam.CFrame = CFrame.lookAt(eye, c.center)
end

-- enquadra o soldado e a arma pela caixa (esfera), na proporção da janela de agora
local function frame(c: Cena)
	local m = c.model
	if not m then
		return
	end
	local lo, hi = bounds(partsOf(m))
	if lo.X == math.huge then
		return
	end
	local center = (lo + hi) / 2
	local radius = math.max((hi - lo).Magnitude / 2, 1)
	local size = c.vp.AbsoluteSize
	local aspect = if size.Y > 1 then math.clamp(size.X / size.Y, 0.3, 3) else 0.8
	local half = math.rad(FOV / 2)
	local halfH = math.atan(math.tan(half) * aspect)
	c.center = center
	c.dist = radius * FILL / math.sin(math.min(half, halfH))
	aim(c)
end

-- ===== v44: retrato de identificação =====
-- Pedido do dono (2026-11-13: "esse bot caído na tela de morte está horrível, melhore essa tela"): o
-- soldado deitado dependia de girar cada junta do boneco de bloco e ficava quebrado (braços tortos,
-- corpo de lado). Agora é um retrato de pé, de frente, do peito para cima, como a foto da ficha do
-- soldado em 1965: tom sépia, luz de cima e da frente, câmera um pouco abaixo dos olhos. Não depende
-- de pose; a arma de quem estava com ela na mão sai do quadro. A cena antiga (lay) fica no código.
CenaBaixa.RETRATO = true
local PORTRAIT_FOV = 26
local PORTRAIT_FILL = 0.42 -- metade da altura do corpo que o quadro mostra (do peito para cima, ombros)
local SEPIA = Color3.fromRGB(255, 226, 186)

local function standPortrait(m: Model)
	-- de pé, de frente para +Z (a câmera fica em +Z), juntas no repouso (braços ao lado do corpo, sem a
	-- pose de segurar a arma) e sem a arma da mão; lay() encosta os pés em y = 0
	lay(m, CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 1)), POSE_STAND)
end

local function aimPortrait(c: Cena)
	local a = (c.angle :: any).Value :: number
	-- de frente, um pouco à direita do soldado, na altura do peito
	local dir = CFrame.Angles(0, a, 0):VectorToWorldSpace(Vector3.new(0.22, 0.02, 1).Unit)
	c.cam.CFrame = CFrame.lookAt(c.center + dir * c.dist, c.center)
end

local function framePortrait(c: Cena)
	local m = c.model
	if not m then
		return
	end
	local lo, hi = bounds(partsOf(m))
	if lo.X == math.huge then
		return
	end
	local h = hi.Y - lo.Y
	local size = c.vp.AbsoluteSize
	local aspect = if size.Y > 1 then math.clamp(size.X / size.Y, 0.3, 3) else 0.8
	local half = math.rad(PORTRAIT_FOV / 2)
	local halfW = math.atan(math.tan(half) * aspect)
	c.center = Vector3.new((lo.X + hi.X) / 2, hi.Y - h * 0.27, (lo.Z + hi.Z) / 2)
	c.dist = (h * PORTRAIT_FILL) / math.tan(math.min(half, halfW))
	aimPortrait(c)
end

function CenaBaixa.new(): Cena
	local holder = Instance.new("Frame")
	holder.Name = "CenaBaixa"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(92, 72, 64) -- sombra quente (a tela atrás é vermelha)
	vp.LightColor = Color3.fromRGB(255, 228, 196)
	vp.LightDirection = Vector3.new(0.45, -1, 0.3).Unit -- de cima, um pouco da cabeça
	vp.Parent = holder
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam
	-- chão: disco de terra com a borda mais escura (some no fundo da tela)
	local function disc(d: number, h: number, y: number, color: Color3, tr: number)
		local g = Instance.new("Part")
		g.Shape = Enum.PartType.Cylinder
		g.Size = Vector3.new(h, d, d)
		g.CFrame = CFrame.new(0, y - h / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		g.Anchored = true
		g.Material = Enum.Material.Ground
		g.Color = color
		g.Transparency = tr
		g.Parent = world
	end
	disc(34, 0.2, -0.02, GROUND_EDGE, 0.35)
	disc(22, 0.3, 0, GROUND, 0)
	-- as bordas do quadro somem no vermelho da tela (duas vinhetas na cor do fundo da baixa)
	for _, tr in { 0, 0.25 } do
		local vin = Instance.new("ImageLabel")
		vin.Name = "Vinheta"
		vin.BackgroundTransparency = 1
		vin.Size = UDim2.fromScale(1, 1)
		vin.Image = Acabamento.VINHETA
		vin.ImageColor3 = EDGE
		vin.ImageTransparency = tr
		vin.ZIndex = 2
		vin.Parent = holder
	end
	local angle = Instance.new("NumberValue")
	local c: Cena = {
		frame = holder,
		vp = vp,
		world = world,
		cam = cam,
		model = nil,
		center = Vector3.zero,
		dist = 20,
		angle = angle,
		drift = nil,
	}
	angle.Changed:Connect(function()
		if c.model then
			if CenaBaixa.RETRATO then
				aimPortrait(c)
			else
				aim(c)
			end
		end
	end)
	vp:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if CenaBaixa.RETRATO then
			framePortrait(c)
		else
			frame(c)
		end
	end)
	if CenaBaixa.RETRATO then
		-- foto de 1965: tom sépia, luz de cima e da frente, sem o chão de terra
		vp.ImageColor3 = SEPIA
		vp.Ambient = Color3.fromRGB(120, 104, 92)
		vp.LightDirection = Vector3.new(-0.3, -0.8, -0.55).Unit
		for _, g in world:GetChildren() do
			if g:IsA("BasePart") then
				g.Transparency = 1
			end
		end
	end
	return c
end

-- Põe o soldado caído: `m` é o retrato tirado em vida (passa a ser da cena) ou nil (o manequim do
-- lado `faction`). A imagem aparece esmaecendo e a câmera começa a respirar.
function CenaBaixa.show(c: Cena, m: Model?, faction: string?)
	local old = c.model
	if old then
		old:Destroy()
	end
	c.model = nil
	-- v44: o retrato usa o manequim do lado (de pé, juntas no repouso certo); o retrato tirado em vida
	-- vinha com o repouso do pescoço já inclinado pela mira (cabeça 48° para baixo no Studio)
	local model: Model? = nil
	if CenaBaixa.RETRATO then
		model = mannequin(faction)
		if model and m then
			m:Destroy()
		end
	end
	model = model or m or mannequin(faction)
	if not model then
		return
	end
	freeze(model)
	local ok, err = pcall(function(): any
		if CenaBaixa.RETRATO then
			standPortrait(model)
		else
			lay(model)
		end
		return nil
	end)
	if not ok then
		warn("[VT65] cena da baixa: pose falhou:", err)
	end
	model.Parent = c.world
	c.model = model
	local val = c.angle :: any
	val.Value = -DRIFT
	if CenaBaixa.RETRATO then
		framePortrait(c)
	else
		frame(c)
	end
	local d = c.drift
	if d then
		d:Cancel()
	end
	local t = TweenService:Create(
		c.angle,
		TweenInfo.new(7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Value = DRIFT }
	)
	c.drift = t
	t:Play()
	c.vp.ImageTransparency = 1
	TweenService:Create(c.vp, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 0,
	}):Play()
end

-- tela fechada: para o respiro (o modelo fica até a próxima baixa)
function CenaBaixa.pause(c: Cena)
	local d = c.drift
	if d then
		d:Cancel()
		c.drift = nil
	end
end

return CenaBaixa
