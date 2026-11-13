--!strict
-- Prévia 3D do soldado no lobby. Clona o manequim que o servidor vestiu
-- (ReplicatedStorage.VT65Preview.<US|VC>, PreviewService) e troca a arma pela do papel: a arte
-- publicada (cópias em ReplicatedStorage.VT65WeaponArt) ou, sem ela, a provisória do GunModel,
-- exatamente como AssetLoader.attachWeapon faz no spawn. Dois modos:
--   - SoldierPreview.new: retrato num ViewportFrame com WorldModel; a câmera gira devagar em volta do
--     soldado (mesa giratória) e a luz principal acompanha a câmera. Enquanto o manequim não chega,
--     mostra uma silhueta;
--   - SoldierPreview.newWorld: o soldado de pé na cena do lobby (LobbyScene), com os pés no ponto
--     dado, de frente para onde o ponto olha. Ilumina-se pelas luzes da cena;
--   - SoldierPreview.newStill: retrato parado, fundo transparente (a tela atrás aparece), luz de lado
--     (tela de baixa). SoldierPreview.setModel põe um modelo próprio no lugar do manequim: o soldado
--     do próprio jogador, com a farda e a arma dele (CasualtyScreen.snapshot).
-- Enquadramento sempre pela caixa do modelo (GetBoundingBox), nunca por altura fixa: o soldado muda
-- de tamanho (2,0 m) e o retrato acompanha.
-- Pose (2026-11-13): o corpo é refeito pelas juntas (o manequim vem do servidor montado fora do mundo)
-- na guarda da 3ª pessoa, com a arma nas duas mãos (Shared/Pegada3P); SoldierPreview.setPose(p,
-- "caido") deita o soldado ferido (tela de baixa). Tudo parado e ancorado: nada roda por quadro no
-- soldado (só a câmera da mesa giratória).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GunModel = require(ReplicatedStorage.Shared.GunModel)
local Joints = require(ReplicatedStorage.Shared.Joints)
local Pegada3P = require(ReplicatedStorage.Shared.Pegada3P)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local UiKit = require(script.Parent.UiKit)

local SoldierPreview = {}

export type Preview = {
	frame: Frame?, -- contêiner do retrato: quem usa define Parent, Position e Size (nil no mundo)
	vp: ViewportFrame?,
	world: Instance, -- WorldModel do retrato ou a pasta da cena
	cam: Camera?,
	silhouette: Frame?,
	note: TextLabel?, -- texto da silhueta (quem usa registra o tamanho de texto)
	stand: CFrame?, -- modo mundo: chão sob os pés e direção do olhar
	wantFaction: string?,
	wantWeapon: string?,
	model: Model?,
	modelFaction: string?,
	weapon: string?, -- arma montada agora
	weaponArt: boolean, -- montada com a arte publicada (senão, a provisória)
	center: Vector3,
	dist: number,
	angle: number,
	speed: number, -- rad/s
	active: boolean,
	still: boolean, -- retrato parado (câmera posta uma vez, sem mesa giratória)
	custom: boolean, -- modelo próprio (setModel): o manequim do servidor não entra
	key: Vector3, -- luz principal no espaço da câmera
	pose: string?, -- "guarda" (padrão do manequim) | "caido" | nil (o modelo próprio fica como veio)
}

local FOV = 24 -- teleobjetiva: pouca distorção, cara de retrato
local KEY = Vector3.new(0.55, -0.6, -1).Unit -- luz principal no espaço da câmera: de cima e da esquerda
local SIDE = Vector3.new(1, -0.32, -0.22).Unit -- luz de lado (da esquerda), para o retrato parado
local list: { Preview } = {}

-- Só devolve o manequim quando todas as peças chegaram (atributo Parts do PreviewService): a
-- replicação vem em pedaços, e o clone feito cedo demais ficava sem tronco (D-64).
local function source(faction: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("VT65Preview")
	local m = folder and folder:FindFirstChild(faction)
	if not (m and m:IsA("Model")) then
		return nil
	end
	local want = m:GetAttribute("Parts")
	if type(want) == "number" then
		local n = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		if n < want then
			return nil
		end
	end
	return m
end

local function weaponArt(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
	local tpl = folder and folder:FindFirstChild(id)
	return if tpl and tpl:IsA("Model") and tpl.PrimaryPart then tpl else nil
end

-- tudo parado e sem scripts (um LocalScript dentro da PlayerGui rodaria)
local function freeze(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
end

-- ===== pose do manequim (parado, todo ancorado) =====
-- 2026-11-13 ("as animações nas telas ... tremendo, capacetes bugados", dono): o manequim do servidor é
-- montado FORA do Workspace (PreviewService), onde as juntas não se resolvem: com a escala do corpo de
-- bloco as peças ficavam no lugar da escala 1 (o Characters já media 1,45 m ali), e o capacete, o
-- colete e a arma soldados nelas iam junto, fora do corpo. Aqui o corpo é posto de novo pelas juntas
-- (C0 · Transform · C1⁻¹ a partir da HumanoidRootPart), com a pose de guarda da 3ª pessoa
-- (Shared/Pegada3P: tronco de lado, arma baixa nas duas mãos) ou caído (tela de baixa); o que está
-- soldado no corpo (capacete, colete, equipamento) acompanha a peça em que está soldado.
type JointRec = { j: Instance, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame }

local function jointRec(j: Instance): JointRec?
	local rest = Joints.rest(j)
	if j:IsA("Motor6D") then
		local p0, p1 = j.Part0, j.Part1
		if p0 and p1 and rest then
			local r: JointRec = { j = j :: Instance, p0 = p0, p1 = p1, c0 = rest, c1 = j.C1 }
			return r
		end
	elseif j:IsA("AnimationConstraint") then
		local a0, a1 = j.Attachment0, j.Attachment1
		local p0 = a0 and a0.Parent
		local p1 = a1 and a1.Parent
		if a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") and rest then
			local r: JointRec = { j = j :: Instance, p0 = p0, p1 = p1, c0 = rest, c1 = a1.CFrame }
			return r
		end
	end
	return nil
end

-- corpo (juntas) e o que está soldado nele, com a peça do corpo de cada coisa soldada
local function rigOf(m: Model): ({ JointRec }, { [BasePart]: { BasePart } })
	local recs: { JointRec } = {}
	local body: { [BasePart]: boolean } = {}
	local weapon = m:FindFirstChild("Weapon")
	for _, d in m:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and not (weapon and d:IsDescendantOf(weapon)) then
			local r = jointRec(d)
			if r then
				table.insert(recs, r)
				body[r.p0], body[r.p1] = true, true
			end
		end
	end
	-- soldas (WeldConstraint/Weld) entre peças, fora a arma: busca a partir das peças do corpo
	local links: { [BasePart]: { BasePart } } = {}
	local function link(a: BasePart?, b: BasePart?)
		if a and b then
			links[a] = links[a] or {}
			links[b] = links[b] or {}
			table.insert(links[a], b)
			table.insert(links[b], a)
		end
	end
	for _, d in m:GetDescendants() do
		if (d:IsA("WeldConstraint") or d:IsA("Weld")) and not (weapon and d:IsDescendantOf(weapon)) then
			local a, b = (d :: any).Part0, (d :: any).Part1
			if a and b and not (weapon and (a:IsDescendantOf(weapon) or b:IsDescendantOf(weapon))) then
				link(a, b)
			end
		end
	end
	local carried: { [BasePart]: { BasePart } } = {}
	local seen: { [BasePart]: boolean } = {}
	for part in body do
		seen[part] = true
	end
	for part in body do
		local list: { BasePart } = {}
		local queue = { part }
		while #queue > 0 do
			local cur = table.remove(queue) :: BasePart
			local ns = links[cur]
			if ns then
				for _, n in ns do
					if not seen[n] then
						seen[n] = true
						table.insert(list, n)
						table.insert(queue, n)
					end
				end
			end
		end
		if #list > 0 then
			carried[part] = list
		end
	end
	return recs, carried
end

-- Põe as peças pelas juntas, com os Transform dados (por nome da junta). Devolve false sem raiz.
local function solveRig(
	m: Model,
	recs: { JointRec },
	carried: { [BasePart]: { BasePart } },
	t: { [string]: CFrame }
): boolean
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	-- o que está soldado guarda o lugar em relação à peça do corpo, antes de mexer
	local rel: { [BasePart]: CFrame } = {}
	for part, list in carried do
		for _, c in list do
			rel[c] = part.CFrame:ToObjectSpace(c.CFrame)
		end
	end
	local kids: { [BasePart]: { JointRec } } = {}
	for _, r in recs do
		kids[r.p0] = kids[r.p0] or {}
		table.insert(kids[r.p0], r)
	end
	local queue = { root }
	local done: { [BasePart]: boolean } = { [root] = true }
	while #queue > 0 do
		local p0 = table.remove(queue, 1) :: BasePart
		local ks = kids[p0]
		if ks then
			for _, r in ks do
				if not done[r.p1] then
					done[r.p1] = true
					r.p1.CFrame = p0.CFrame * r.c0 * (t[r.j.Name] or CFrame.identity) * r.c1:Inverse()
					table.insert(queue, r.p1)
				end
			end
		end
	end
	for part, list in carried do
		for _, c in list do
			c.CFrame = part.CFrame * rel[c]
		end
	end
	return true
end

local function armRig(recs: { JointRec }, m: Model, side: string): (Pegada3P.ArmRig?, { [string]: Instance })
	local name = if side == "R" then "Right" else "Left"
	local by: { [string]: JointRec } = {}
	for _, r in recs do
		by[r.j.Name] = r
	end
	local s, e, w = by[name .. "Shoulder"], by[name .. "Elbow"], by[name .. "Wrist"]
	local hand = m:FindFirstChild(name .. "Hand")
	local grip = hand and hand:FindFirstChild(name .. "GripAttachment") :: Attachment?
	if not (s and e and w and grip) then
		return nil, {}
	end
	return {
		c0s = s.c0,
		c1s = s.c1,
		c0e = e.c0,
		c1e = e.c1,
		c0w = w.c0,
		c1w = w.c1,
		grip = (grip :: Attachment).CFrame,
	}, { s = s.j, e = e.j }
end

-- Pose do manequim: "guarda" (de pé, arma baixa nas duas mãos) ou "caido" (deitado de costas, mão
-- no peito, arma no chão ao lado). A arma "Weapon" vai para a pose (não fica pendurada na mão).
local function applyPose(m: Model, name: string)
	local recs, carried = rigOf(m)
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	local ut = m:FindFirstChild("UpperTorso") :: BasePart?
	if not (root and ut and #recs > 0) then
		return
	end
	local w = m:FindFirstChild("Weapon") :: Model?
	local kind = "rifle"
	if w then
		local id = w:GetAttribute("WeaponId")
		local wp = if type(id) == "string" then Weapons.get(id) else nil
		kind = if wp then wp.kind else "rifle"
	end
	local S = Pegada3P.S
	local t: { [string]: CFrame } = {}
	if name == "caido" then
		-- de costas no chão: a bacia gira 90° para trás; cabeça de lado; joelho direito dobrado
		t.Root = CFrame.Angles(math.rad(90), 0, 0)
		t.Neck = CFrame.Angles(math.rad(-15), math.rad(25), 0)
		t.RightHip = CFrame.Angles(math.rad(35), 0, math.rad(-6))
		t.RightKnee = CFrame.Angles(math.rad(-65), 0, 0)
		t.LeftHip = CFrame.Angles(math.rad(4), 0, math.rad(8))
		t.RightShoulder = CFrame.Angles(0, 0, math.rad(18))
	else
		local bl = Pegada3P.blade(kind)
		t.Waist = CFrame.Angles(0, -bl, 0)
		t.Neck = CFrame.Angles(0, bl, 0)
	end
	solveRig(m, recs, carried, t)
	-- braços (e a arma) pela pose da 3ª pessoa
	local rigR, jR = armRig(recs, m, "R")
	local rigL, jL = armRig(recs, m, "L")
	local gunUT: CFrame? = nil
	local primary = w and w.PrimaryPart
	if name ~= "caido" and w and primary then
		local s = Pegada3P.state(kind)
		-- soleira (o mais de trás da arma, a partir do punho)
		local pivot = w:GetPivot()
		local rear = 0.3
		for _, d in w:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local l = pivot:ToObjectSpace(d.CFrame)
				local h = d.Size / 2
				local ext = math.abs(l.RightVector.Z) * h.X
					+ math.abs(l.UpVector.Z) * h.Y
					+ math.abs(l.LookVector.Z) * h.Z
				rear = math.max(rear, l.Position.Z + ext)
			end
		end
		s.rear = rear
		gunUT = Pegada3P.gun(root.CFrame:ToObjectSpace(ut.CFrame), s)
		local g = gunUT :: CFrame
		local sup = primary:FindFirstChild("Support") :: Attachment?
		local supLocal = if sup then (pivot:ToObjectSpace(sup.WorldCFrame)).Position else Vector3.new(0, 0, -0.9)
		if rigR then
			local r1, r2 = Pegada3P.arm(rigR, g.Position, Vector3.new(1.6, -1.1, 0.5))
			t[jR.s.Name], t[jR.e.Name] = r1, r2
		end
		if rigL then
			local a, b = Pegada3P.lengths(rigL)
			local target = if kind == "pistol"
				then g * Vector3.new(-0.12, -0.05, 0.05)
				else g * Pegada3P.support(supLocal, 2.6, g:PointToObjectSpace(rigL.c0s.Position), a + b)
			local l1, l2 = Pegada3P.arm(rigL, target, Vector3.new(-0.9, -2.2, -0.3))
			t[jL.s.Name], t[jL.e.Name] = l1, l2
		end
	elseif name == "caido" and rigL then
		-- mão esquerda sobre o peito
		local l1, l2 = Pegada3P.arm(rigL, Vector3.new(0.15 * S, 0.1 * S, -0.62 * S), Vector3.new(-1, -1, -0.4))
		t[jL.s.Name], t[jL.e.Name] = l1, l2
	end
	solveRig(m, recs, carried, t)
	if w then
		if gunUT then
			w:PivotTo(ut.CFrame * gunUT)
		else
			-- caído: a arma no chão, ao lado da mão direita, deitada de lado e com a boca para a cabeça
			local lower = m:FindFirstChild("LowerTorso") :: BasePart?
			local at = lower or ut
			w:PivotTo(
				at.CFrame
					* CFrame.fromMatrix(
						Vector3.new(1.9 * S, 0.9 * S, 0.35 * S),
						Vector3.new(0, 0, -1),
						Vector3.new(1, 0, 0)
					)
			)
		end
	end
end

local function mountWeapon(p: Preview, id: string)
	local model = p.model
	local wp = Weapons.get(id)
	local hand = model and model:FindFirstChild("RightHand") :: BasePart?
	if not (model and wp and hand) then
		return
	end
	local art = weaponArt(id)
	local w: Model = if art then art:Clone() else GunModel.build(id, wp.kind)
	if not w.PrimaryPart then
		w:Destroy()
		return
	end
	local old = model:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	freeze(w)
	w.Name = "Weapon"
	w:SetAttribute("WeaponId", id)
	w:PivotTo(hand.CFrame * CFrame.Angles(-math.pi / 2, 0, 0)) -- a mesma pega do AssetLoader.attachWeapon
	w.Parent = model
	p.weapon = id
	p.weaponArt = art ~= nil
	if p.pose then
		applyPose(model, p.pose :: string) -- a arma nova vai para as mãos
	end
end

-- câmera do retrato no ângulo de agora (mesa giratória a cada quadro; o parado, uma vez)
local function aim(p: Preview)
	local cam, vp = p.cam, p.vp
	if not (cam and vp) then
		return
	end
	local a, c, d = p.angle, p.center, p.dist
	local cf = CFrame.lookAt(Vector3.new(c.X + math.sin(a) * d, c.Y + d * 0.05, c.Z - math.cos(a) * d), c)
	cam.CFrame = cf
	vp.LightDirection = cf:VectorToWorldSpace(p.key)
end

-- Enquadra pela caixa do modelo: a altura inteira cabe com 12% de folga, qualquer que seja o
-- tamanho do soldado (a largura também, para a arma não sair do quadro no retrato estreito).
local function frameModel(p: Preview)
	local model = p.model :: Model
	local cf, size = model:GetBoundingBox()
	local h = math.max(size.Y, 0.5)
	local vp = p.vp
	local aspect = 1
	if vp and vp.AbsoluteSize.Y > 1 then
		aspect = math.clamp(vp.AbsoluteSize.X / vp.AbsoluteSize.Y, 0.3, 3)
	end
	local half = math.max(h * 0.5, math.max(size.X, size.Z) * 0.5 / aspect) * 1.12
	p.center = cf.Position + Vector3.new(0, h * 0.02, 0)
	p.dist = half / math.tan(math.rad(FOV / 2))
	if p.still then
		aim(p)
	end
end

-- modo mundo: pés no chão do ponto (a arma pendurada na mão não conta como "pé")
local function standModel(m: Model, stand: CFrame)
	m:PivotTo(stand)
	local bottom = math.huge
	for _, name in { "LeftFoot", "RightFoot" } do
		local f = m:FindFirstChild(name)
		if f and f:IsA("BasePart") then
			bottom = math.min(bottom, f.Position.Y - f.Size.Y / 2)
		end
	end
	if bottom == math.huge then
		local cf, size = m:GetBoundingBox()
		bottom = cf.Position.Y - size.Y / 2
	end
	m:PivotTo(stand + Vector3.new(0, stand.Position.Y - bottom, 0))
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function()
			hum.EvaluateStateMachine = false -- boneco parado: sem estados nem física de personagem
		end)
	end
end

local function sync(p: Preview)
	if p.custom then
		local sil = p.silhouette
		if sil then
			sil.Visible = p.model == nil
		end
		return -- modelo próprio (setModel): o manequim do servidor não entra
	end
	local f = p.wantFaction
	if f ~= p.modelFaction then
		if p.model then
			p.model:Destroy()
		end
		p.model, p.modelFaction, p.weapon, p.weaponArt = nil, nil, nil, false
		local src = if f then source(f) else nil
		if src then
			local m = src:Clone()
			freeze(m)
			if p.pose then
				applyPose(m, p.pose :: string) -- juntas resolvidas, arma nas mãos (antes de pôr no chão)
			end
			local stand = p.stand
			if stand then
				standModel(m, stand)
			else
				m:PivotTo(CFrame.identity) -- frente do soldado em −Z
			end
			m.Parent = p.world
			p.model, p.modelFaction = m, f
			local w = m:FindFirstChild("Weapon")
			local wid = src:GetAttribute("Weapon")
			p.weapon = if type(wid) == "string" then wid else nil
			-- a provisória (GunModel.build) tem o atributo Kind; a publicada (GunModel.fit), não
			p.weaponArt = w ~= nil and w:GetAttribute("Kind") == nil
			if not stand then
				frameModel(p)
			end
			local vp = p.vp
			if vp then -- retrato: a foto "revela" (o soldado esmaece sobre o fundo de estúdio)
				vp.ImageTransparency = 1
				TweenService:Create(vp, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					ImageTransparency = 0,
				}):Play()
			end
		end
	end
	local sil = p.silhouette
	if sil then
		sil.Visible = p.model == nil
	end
	local want = p.wantWeapon or p.weapon
	if p.model and want and (want ~= p.weapon or (not p.weaponArt and weaponArt(want) ~= nil)) then
		mountWeapon(p, want)
	end
end

local function syncAll()
	for _, p in list do
		sync(p)
	end
end

local function blank(world: Instance): Preview
	return {
		frame = nil,
		vp = nil,
		world = world,
		cam = nil,
		silhouette = nil,
		note = nil,
		stand = nil,
		wantFaction = nil,
		wantWeapon = nil,
		model = nil,
		modelFaction = nil,
		weapon = nil,
		weaponArt = false,
		center = Vector3.zero,
		dist = 16,
		angle = -0.45,
		speed = 0.24,
		active = false,
		still = false,
		custom = false,
		key = KEY,
		pose = "guarda",
	}
end

-- Retrato num ViewportFrame (p.frame e p.note existem sempre neste modo)
function SoldierPreview.new(speed: number?, startAngle: number?): Preview
	local frame = Instance.new("Frame")
	frame.Name = "SoldierPreview"
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ClipsDescendants = true
	-- fundo de estúdio escuro (estilo novo): um pouco mais claro atrás da cabeça, quase preto no chão
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 76, 58)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(38, 42, 32)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 18, 14)),
	})
	grad.Parent = frame

	local sil = Instance.new("Frame")
	sil.Name = "Silhouette"
	sil.BackgroundTransparency = 1
	sil.Size = UDim2.fromScale(1, 1)
	sil.Parent = frame
	local head = Instance.new("Frame")
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0.16)
	head.Size = UDim2.fromScale(0.2, 0.2)
	head.BackgroundColor3 = UiKit.V.PANEL_3
	head.BackgroundTransparency = 0.3
	head.BorderSizePixel = 0
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = head
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0.5, 0)
	hc.Parent = head
	head.Parent = sil
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.38)
	body.Size = UDim2.fromScale(0.5, 0.7)
	body.BackgroundColor3 = UiKit.V.PANEL_3
	body.BackgroundTransparency = 0.3
	body.BorderSizePixel = 0
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.35, 0)
	bc.Parent = body
	body.Parent = sil
	local note = Instance.new("TextLabel")
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = UDim2.new(0.5, 0, 1, -8)
	note.Size = UDim2.new(1, -16, 0, 44)
	note.BackgroundTransparency = 1
	note.Font = UiKit.BODY_FONT
	note.TextColor3 = UiKit.V.DIM
	note.TextWrapped = true
	note.TextSize = UiKit.text(16)
	note.Text = "FOTO A CAMINHO…\nequipamento sendo carregado"
	note.ZIndex = 2
	note.Parent = sil

	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(104, 100, 86)
	vp.LightColor = Color3.fromRGB(255, 212, 160) -- luz principal quente
	vp.ImageColor3 = Color3.fromRGB(255, 246, 228) -- leve tom de cópia fotográfica
	vp.Parent = frame
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam

	local p = blank(world)
	p.frame, p.vp, p.cam, p.silhouette, p.note = frame, vp, cam, sil, note
	p.angle = startAngle or -0.45
	p.speed = speed or 0.24 -- uma volta em ~26 s
	table.insert(list, p)
	return p
end

-- Soldado de pé na cena: `stand` é o chão sob os pés, olhando para a frente do soldado (−Z).
function SoldierPreview.newWorld(parent: Instance, stand: CFrame): Preview
	local p = blank(parent)
	p.stand = stand
	table.insert(list, p)
	return p
end

-- Retrato parado: fundo transparente (a cor da tela atrás aparece), luz de lado, sem giro. angle:
-- de onde a câmera olha (0 = de frente; negativo = do lado esquerdo do soldado).
function SoldierPreview.newStill(angle: number?): Preview
	local p = SoldierPreview.new(0, angle or -0.5)
	local frame, vp = p.frame :: Frame, p.vp :: ViewportFrame
	frame.BackgroundTransparency = 1
	local g = frame:FindFirstChildOfClass("UIGradient")
	if g then
		g:Destroy()
	end
	vp.Ambient = Color3.fromRGB(58, 54, 52) -- sombra funda do lado sem luz
	vp.LightColor = Color3.fromRGB(255, 236, 214)
	vp.ImageColor3 = Color3.new(1, 1, 1)
	p.still = true
	p.key = SIDE
	-- o quadro mudou de tamanho (janela, entrada): enquadra de novo pela caixa
	vp:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if p.model then
			frameModel(p)
		end
	end)
	return p
end

-- Modelo próprio no retrato (nil volta ao manequim do servidor). O modelo é do retrato a partir de
-- agora: fica parado, sem scripts, de frente para −Z, e é destruído quando outro chega.
function SoldierPreview.setModel(p: Preview, m: Model?)
	if p.model then
		p.model:Destroy()
	end
	p.model, p.modelFaction, p.weapon, p.weaponArt = nil, nil, nil, false
	if not m then
		p.custom = false
		sync(p)
		return
	end
	p.custom = true
	freeze(m)
	if p.pose then
		-- clone do manequim do lobby (montado fora do mundo) ou do soldado: juntas resolvidas e a pose
		applyPose(m, p.pose :: string)
	end
	m:PivotTo(CFrame.identity)
	m.Parent = p.world
	p.model = m
	frameModel(p)
	local vp = p.vp
	if vp then
		vp.ImageTransparency = 1
		TweenService:Create(vp, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			ImageTransparency = 0,
		}):Play()
	end
	sync(p)
end

-- facção (nil = nada / silhueta) e arma do papel (nil = a que o servidor montou: a do fuzileiro)
function SoldierPreview.set(p: Preview, faction: string?, weaponId: string?)
	if faction == p.wantFaction and weaponId == p.wantWeapon then
		return
	end
	p.wantFaction, p.wantWeapon = faction, weaponId
	sync(p)
end

function SoldierPreview.setActive(p: Preview, on: boolean)
	p.active = on
end

-- Pose do soldado do retrato: "guarda" (de pé, arma baixa nas duas mãos; padrão do manequim) ou
-- "caido" (ferido, deitado de costas, mão no peito, arma no chão). Vale para o manequim e para o
-- modelo próprio (setModel: chame antes ou depois). O enquadramento segue a caixa nova.
function SoldierPreview.setPose(p: Preview, name: string)
	if name ~= "guarda" and name ~= "caido" then
		return
	end
	p.pose = name
	local m = p.model
	if m then
		applyPose(m, name)
		if not p.stand then
			m:PivotTo(CFrame.identity)
			frameModel(p)
		end
	end
end

-- mesa giratória: só os retratos ativos; nenhuma tabela ou instância criada por quadro
RunService.RenderStepped:Connect(function(dt: number)
	for _, p in list do
		if p.active and not p.still and p.model and p.cam and p.vp then
			p.angle = (p.angle + dt * p.speed) % (2 * math.pi)
			aim(p)
		end
	end
end)

-- manequins e arte das armas chegam do servidor depois (PreviewService, AssetLoader)
local watched: { [Instance]: boolean } = {}
local pending = false
local function syncSoon()
	-- várias peças chegam no mesmo quadro: um sync só
	if not pending then
		pending = true
		task.defer(function()
			pending = false
			syncAll()
		end)
	end
end
local function watch(folder: Instance)
	if watched[folder] then
		return
	end
	watched[folder] = true
	folder.DescendantAdded:Connect(syncSoon) -- peça a peça: o manequim só vale completo (source)
end
for _, name in { "VT65Preview", "VT65WeaponArt" } do
	local f = ReplicatedStorage:FindFirstChild(name)
	if f then
		watch(f)
	end
end
ReplicatedStorage.ChildAdded:Connect(function(c)
	if c.Name == "VT65Preview" or c.Name == "VT65WeaponArt" then
		watch(c)
		syncSoon()
	end
end)

return SoldierPreview
