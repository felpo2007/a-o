--!strict
-- Poses de postura de TODOS os personagens (jogadores e bots), a partir dos atributos que o
-- servidor grava: "Crouched" (pernas dobradas), "Prone" (corpo deitado) e "Lean" (−1..1 em quartos,
-- tronco inclinado; D-99: o próprio soldado usa o valor local do Controllers/Inclinar). O C0 da junta (Motor6D, ou o Attachment0 da AnimationConstraint: Shared/Joints) mudado
-- no cliente é local; por isso cada cliente posa todo mundo. Com os clipes de captura
-- (SoldierAnimations) as pernas do agachado vêm deles; a dobra daqui fica de reserva.
-- Arma em 3ª pessoa (2026-11-13, dono: "armas estão bugadas em 3ª pessoa, ajeite a pegada e tamanho
-- da arma"): a pose do Front 44 (Shared/Pegada3P) e o IK de dois ossos dele, aqui, a cada quadro,
-- DEPOIS do Animator (PreSimulation): a arma aponta para onde se mira, a coronha no ombro, e as mãos
-- (o ponto da pegada da mão) no punho e no guarda-mão. Antes a pega era fixa e cruzada no peito, e o
-- IKControl punha a mão no alvo do quadro anterior: andando ou girando a mão tremia em volta da arma.
-- Os IKControls ficam: o SoldierAnimations põe neles o peso (recarga, granada, faca) e, longe da
-- câmera (> LOD_FAR), eles fazem o IK no lugar deste script.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArmIK = require(ReplicatedStorage.Shared.ArmIK)
local CartaModel = require(ReplicatedStorage.Shared.CartaModel)
local Corpo = require(ReplicatedStorage.Shared.Corpo)
local FieldWork = require(ReplicatedStorage.Shared.FieldWork)
local ItemAnim = require(ReplicatedStorage.Shared.ItemAnim)
local Joints = require(ReplicatedStorage.Shared.Joints)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Pegada3P = require(ReplicatedStorage.Shared.Pegada3P)
local SoldierAnims = require(ReplicatedStorage.Shared.SoldierAnims)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Inclinar = require(script.Parent.Inclinar)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- pose de repouso de cada junta: Joints.rest (atributo na instância; a tabela fraca de antes
-- perdia entradas e as rotações acumulavam)
-- Dobra de reserva (sem o clipe agachado): o quadril desce PostureService.DROP.crouch = 1,03 stud;
-- coxa a 75° e joelho a −115° encolhem a perna (2,5 studs) nisso.
local CROUCH: { [string]: CFrame } = {
	LeftHip = CFrame.Angles(math.rad(75), 0, 0),
	RightHip = CFrame.Angles(math.rad(75), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-115), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-115), 0, 0),
}
-- inclinação do tronco: a do Front 44 (14° × 1,4 no inclinar inteiro; antes 16°), D-99
local LEAN_WAIST = math.rad(Movement.LEAN.waistDeg)
local LEAN_RATE = 10 -- 1/s: o atributo chega em quartos a ~10 Hz; o Front 44 suaviza assim
-- mira no tronco e na cabeça (Front 44: cintura 35% da arfagem, pescoço 50%)
local WAIST_PITCH, NECK_PITCH = 0.35, 0.5
-- longe da câmera o IKControl faz o IK (barato, sem Lua por quadro); perto, o daqui (studs)
local LOD_FAR = 150 / 0.28
-- tiro de quem quer que seja (WeaponVisuals grava o instante e a arfagem no modelo, só local):
-- a arma sobe ao ombro por SHOT_RAISE s e aponta na arfagem do tiro por SHOT_AIM s
local SHOT_RAISE, SHOT_AIM = 1.2, 2.0
-- granada segura na direita, diante do peito (espaço do UpperTorso; PLACEHOLDER: conferir no Studio)
local NADE_AT = Vector3.new(0.3, 0.15, -0.95) * Corpo.BLOCK_SCALE

-- D-98: o soldado é o corpo de 1,75 m ampliado por K (Shared/Corpo, SoldierAnims.SCALE). As pegas
-- especiais abaixo (carta, golpe, faca) e os polos do ArmIK estão no tamanho da gravação; no jogo a
-- posição vai vezes K, a rotação fica. A arma segue no tamanho real.
local K = SoldierAnims.SCALE
local function big(cf: CFrame): CFrame
	return cf.Rotation + cf.Position * K
end
local function holdCF(h: { number }): CFrame
	return big(CFrame.new(h[1], h[2], h[3]) * CFrame.Angles(0, math.rad(h[4]), 0) * CFrame.Angles(math.rad(h[5]), 0, 0))
end
-- Carta na mão (D-98, atributo "Carta" do servidor): o fuzil a tiracolo no ombro direito, boca para
-- cima, e as duas mãos nas bordas da carta aberta diante do peito, inclinada para os olhos.
-- D-102: no boneco de bloco (formato do Front 44) o tronco é 25% mais largo e fundo que o corpo gravado
-- vezes K: o fuzil a tiracolo vai para fora junto (Corpo.KX na largura e na profundidade), senão
-- afundava no ombro e nas costas.
local HOLD_SLUNG = (function(): CFrame
	local h = ArmIK.HOLDS.slung
	local cf = CFrame.new(h[1], h[2], h[3]) * CFrame.Angles(0, math.rad(h[4]), 0) * CFrame.Angles(math.rad(h[5]), 0, 0)
	return cf.Rotation + Vector3.new(cf.X * Corpo.KX, cf.Y * K, cf.Z * Corpo.KX)
end)()
local MAP_AT = holdCF(ArmIK.HOLDS.map)
-- Golpe com o fuzil (baioneta e coronhada): em guarda (boca para a frente) e a estocada com o passo;
-- o peito avança no clipe "baioneta" (tools/anim). Com a faca: o fuzil baixo na mão esquerda.
local HOLD_GUARD = holdCF(ArmIK.HOLDS.guard)
local HOLD_LUNGE = holdCF(ArmIK.HOLDS.lunge)
local HOLD_KNIFE = holdCF(ArmIK.HOLDS.knife)
local STRIKE_KEYS = { { 0, 0 }, { 0.18, 1 }, { 0.32, 2 }, { 0.45, 2 }, { 0.9, 0 } } -- 0 base, 1 guarda, 2 estocada

local function characters(): { Model }
	local list = {}
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

local function motor(char: Model, name: string): (Instance?, CFrame)
	local m = Joints.find(char, name)
	local rest = m and Joints.rest(m)
	if not (m and rest) then
		return nil, CFrame.identity
	end
	return m, rest
end

-- só grava quando muda (evita escrever ~5 juntas × 60 personagens a cada quadro)
local function pose(m: Instance, cf: CFrame)
	if Joints.getC0(m) ~= cf then
		Joints.setC0(m, cf)
	end
end

local function polo(ut: BasePart, name: string, pos: { number }): Attachment
	local a = ut:FindFirstChild(name) :: Attachment?
	if not a then
		local n = Instance.new("Attachment")
		n.Name = name
		n.Parent = ut
		a = n
	end
	local att = a :: Attachment
	local v = Vector3.new(pos[1], pos[2], pos[3]) * K -- D-98: polo no corpo ampliado
	if att.Position ~= v then
		att.Position = v
	end
	return att
end

-- IKControl: só carrega o peso (SoldierAnimations) e faz o IK longe da câmera (on = far)
local function ikTo(
	hum: Humanoid,
	name: string,
	root: Instance?,
	effector: Instance?,
	target: Instance?,
	pole: Attachment?,
	on: boolean
)
	local k = hum:FindFirstChild(name) :: IKControl?
	if not k then
		local n = Instance.new("IKControl")
		n.Name = name
		n.Type = Enum.IKControlType.Position
		n.Enabled = false
		n.Parent = hum
		k = n
	end
	local ik = k :: IKControl
	if root and effector and target then
		if ik.ChainRoot ~= root then
			ik.ChainRoot = root
		end
		if ik.EndEffector ~= effector then
			ik.EndEffector = effector
		end
		if ik.Target ~= target then
			ik.Target = target
		end
		if ik.Pole ~= pole then
			ik.Pole = pole :: any
		end
		if ik.Enabled ~= on then
			ik.Enabled = on
		end
	elseif ik.Enabled then
		ik.Enabled = false
	end
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function approach(cur: number, target: number, rate: number, dt: number): number
	return cur + (target - cur) * math.min(1, rate * dt)
end

-- pega do golpe com o fuzil (baioneta/coronhada) no instante t do golpe
local function strikeHold(base: CFrame, t: number): CFrame
	local holds = { [0] = base, [1] = HOLD_GUARD, [2] = HOLD_LUNGE }
	for i = 1, #STRIKE_KEYS - 1 do
		local a, b = STRIKE_KEYS[i], STRIKE_KEYS[i + 1]
		if t < b[1] then
			return holds[a[2]]:Lerp(holds[b[2]], smooth((t - a[1]) / (b[1] - a[1])))
		end
	end
	return base
end

local function kindOf(w: Model): string
	local id = w:GetAttribute("WeaponId")
	local wp = if type(id) == "string" then Weapons.get(id) else nil
	return if wp then wp.kind else "rifle"
end

-- Weld local da arma no peito (a WeldConstraint do servidor, mão → arma, fica desligada aqui)
local function holdWeld(w: Model, ut: BasePart, primary: BasePart): Weld?
	local j = primary:FindFirstChild("VT65Pega") :: Weld?
	if j and j.Part0 == ut then
		return j
	end
	for _, d in primary:GetChildren() do
		if d:IsA("WeldConstraint") and d.Part0 and not (d.Part0 :: BasePart):IsDescendantOf(w) then
			d.Enabled = false
		end
	end
	if j then
		j:Destroy()
	end
	local n = Instance.new("Weld")
	n.Name = "VT65Pega"
	n.Part0 = ut
	n.Part1 = primary
	n.C1 = primary.PivotOffset -- o pivô da arma (punho) vai à pega
	n.C0 = CFrame.new(0, 0, -2)
	n.Parent = primary
	return n
end

-- Medidas da arma no espaço do punho (frente −Z), uma vez por modelo: soleira (atrás), boca (frente)
-- e o apoio da mão esquerda. Guardadas no próprio modelo (atributos locais).
type GunInfo = { rear: number, front: number, support: Vector3, grip: Vector3 }
local gunInfo: { [Model]: GunInfo } = setmetatable({}, { __mode = "k" }) :: any
local function infoOf(w: Model, primary: BasePart): GunInfo
	local got = gunInfo[w]
	if got then
		return got
	end
	local pivot = primary.CFrame * primary.PivotOffset
	local rear, front = 0.3, 0.5
	for _, d in w:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local l = pivot:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			local ext = math.abs(l.RightVector.Z) * h.X + math.abs(l.UpVector.Z) * h.Y + math.abs(l.LookVector.Z) * h.Z
			rear = math.max(rear, l.Position.Z + ext)
			front = math.max(front, -(l.Position.Z - ext))
		end
	end
	local function local_(name: string): Vector3?
		local a = primary:FindFirstChild(name) :: Attachment?
		return if a then (primary.PivotOffset:Inverse() * a.CFrame).Position else nil
	end
	local info = {
		rear = rear,
		front = front,
		grip = local_("Grip") or Vector3.zero,
		support = local_("Support") or Vector3.new(0, 0, -0.9),
	}
	gunInfo[w] = info
	return info
end

-- ===== braços: IK do Front 44 (Shared/Pegada3P) escrito no Transform, depois do Animator =====
type ArmJoints = { s: Instance, e: Instance, w: Instance, rig: Pegada3P.ArmRig, reach: number }
local function c1Of(j: Instance): CFrame?
	if j:IsA("Motor6D") then
		return j.C1
	elseif j:IsA("AnimationConstraint") then
		local a1 = j.Attachment1
		return if a1 then a1.CFrame else nil
	end
	return nil
end
local armCache: { [Model]: { R: ArmJoints?, L: ArmJoints?, at: number } } = setmetatable({}, { __mode = "k" }) :: any
local function armOf(char: Model, side: string): ArmJoints?
	local c = armCache[char]
	local now = os.clock()
	if c and now - c.at < 5 then
		local a = if side == "R" then c.R else c.L
		if a and a.s.Parent and a.e.Parent and a.w.Parent then
			return a
		end
		if a == nil and now - c.at < 1 then
			return nil
		end
	end
	local function build(sd: string): ArmJoints?
		local name = if sd == "R" then "Right" else "Left"
		local s = Joints.find(char, name .. "Shoulder")
		local e = Joints.find(char, name .. "Elbow")
		local w = Joints.find(char, name .. "Wrist")
		local hand = char:FindFirstChild(name .. "Hand")
		local grip = hand and hand:FindFirstChild(name .. "GripAttachment") :: Attachment?
		if not (s and e and w and grip) then
			return nil
		end
		local c0s, c0e, c0w = Joints.rest(s), Joints.rest(e), Joints.rest(w)
		local c1s, c1e, c1w = c1Of(s), c1Of(e), c1Of(w)
		if not (c0s and c0e and c0w and c1s and c1e and c1w) then
			return nil
		end
		local rig: Pegada3P.ArmRig = {
			c0s = c0s,
			c1s = c1s,
			c0e = c0e,
			c1e = c1e,
			c0w = c0w,
			c1w = c1w,
			grip = (grip :: Attachment).CFrame,
		}
		local a, b = Pegada3P.lengths(rig)
		return { s = s, e = e, w = w, rig = rig, reach = a + b }
	end
	local fresh = { R = build("R"), L = build("L"), at = now }
	armCache[char] = fresh
	return if side == "R" then fresh.R else fresh.L
end

local function getT(j: Instance): CFrame
	return (j :: any).Transform
end
local function setT(j: Instance, cf: CFrame)
	(j :: any).Transform = cf
end

-- Põe a pegada da mão em `target` (espaço do UpperTorso), misturando com o clipe pelo peso w.
local function solveArm(a: ArmJoints, target: Vector3, pole: Vector3, w: number)
	if w <= 1e-3 then
		return
	end
	local t1, t2 = Pegada3P.arm(a.rig, target, pole)
	if w < 0.999 then
		t1 = getT(a.s):Lerp(t1, w)
		t2 = getT(a.e):Lerp(t2, w)
		setT(a.w, getT(a.w):Lerp(CFrame.identity, w))
	else
		setT(a.w, CFrame.identity) -- punho reto: a mão de bloco continua o antebraço
	end
	setT(a.s, t1)
	setT(a.e, t2)
end

-- ponto de um Attachment no espaço do UpperTorso, sem esperar a física: na própria UT ou numa peça
-- soldada nela por Weld (arma, carta, objeto da mão)
local function inUT(att: Instance?, ut: BasePart): Vector3?
	if not (att and att:IsA("Attachment")) then
		return nil
	end
	local part = att.Parent
	if part == ut then
		return att.Position
	end
	if part and part:IsA("BasePart") then
		for _, j in part:GetChildren() do
			if j:IsA("Weld") and j.Part0 == ut and j.Part1 == part and j.Enabled then
				return (j.C0 * j.C1:Inverse() * att.CFrame).Position
			end
		end
		return ut.CFrame:PointToObjectSpace(att.WorldPosition) -- reserva: um quadro atrasado
	end
	return nil
end

-- Lado do braço: alvo (Attachment ou ponto no UT), polo (direção no UT) e peso. nil = não mexe.
type ArmGoal = { target: Vector3?, pole: Vector3, w: number }
type Goals = { R: ArmGoal?, L: ArmGoal? }

local function poleDir(pos: { number }, side: string): Vector3
	-- os polos do ArmIK são pontos (IKControl.Pole); daqui sai a direção a partir do ombro
	local sh = Vector3.new(if side == "R" then 1 else -1, 0.563, 0) * Corpo.BLOCK_SCALE
	return Vector3.new(pos[1], pos[2], pos[3]) * K - sh
end

type Blend = {
	crouch: number,
	lean: number,
	blade: number,
	knife: number,
	nade: number,
	item: number,
	pitch: number,
	ads: number,
	sprint: number,
	prone: number,
	speed: number,
	phase: number,
	yaw: number?,
	yawRate: number,
	seed: number,
	pos: Vector3?,
	goals: Goals?,
	near: boolean,
}
local blend: { [Model]: Blend } = setmetatable({}, { __mode = "k" }) :: any

local function newBlend(): Blend
	return {
		crouch = 0,
		lean = 0,
		blade = 0,
		knife = 0,
		nade = 0,
		item = 0,
		pitch = 0,
		ads = 0,
		sprint = 0,
		prone = 0,
		speed = 0,
		phase = 0,
		yaw = nil,
		yawRate = 0,
		seed = math.random() * 20,
		pos = nil,
		goals = nil,
		near = true,
	}
end

-- carta na mão de cada soldado com o mapa aberto (só neste cliente, como a pose)
local maps: { [Model]: Model } = setmetatable({}, { __mode = "k" }) :: any
local function mapOf(char: Model, ut: BasePart, on: boolean): Model?
	local m = maps[char]
	if not on then
		if m then
			m:Destroy()
			maps[char] = nil
		end
		return nil
	end
	if m and m.Parent then
		return m
	end
	local c = CartaModel.build()
	local main = c.PrimaryPart :: BasePart
	c:PivotTo(ut.CFrame * MAP_AT)
	local w = Instance.new("Weld")
	w.Part0, w.Part1 = ut, main
	w.C0 = MAP_AT
	w.Parent = main
	c.Parent = char
	maps[char] = c
	return c
end

-- ===== item na mão (D-99): curativo, torniquete, rádio, binóculo, pá, cantil... =====
-- O caminho das mãos vem do Shared/ItemAnim (espaço da UpperTorso do corpo de 1,75 m, vezes K); o
-- relógio é o do servidor ("VT65AcaoT" do MedicalService, "VT65ItemT" do PostureService), então todos
-- veem o mesmo instante. As mãos vão por IK a dois Attachments na UpperTorso; o objeto (peças, no
-- tamanho real) fica soldado nela e segue a mão.
type ItemNow = { name: string, t: number, D: number? }
local function itemOf(char: Model): ItemNow?
	local name, t, D = ItemAnim.current(function(a: string): any
		return char:GetAttribute(a)
	end, workspace:GetServerTimeNow(), FieldWork.DIG.seconds)
	return if name then { name = name, t = t, D = D } else nil
end

local function alvo(ut: BasePart, name: string, pos: Vector3): Attachment
	local a = ut:FindFirstChild(name) :: Attachment?
	if not a then
		local n = Instance.new("Attachment")
		n.Name = name
		n.Parent = ut
		a = n
	end
	local att = a :: Attachment
	if (att.Position - pos).Magnitude > 1e-4 then
		att.Position = pos
	end
	return att
end

-- objeto da mão (peças no tamanho real), soldado na UpperTorso
local PROP_M = 0.28 -- m por stud: o objeto fica no tamanho real (o corpo é que é ampliado)
local props: { [Model]: { model: Model, weld: Weld, kind: string } } = setmetatable({}, { __mode = "k" }) :: any
local function propOf(char: Model, ut: BasePart, kind: string?): (Model?, Weld?)
	local cur = props[char]
	if cur and cur.kind == kind and cur.model.Parent then
		return cur.model, cur.weld
	end
	if cur then
		cur.model:Destroy()
		props[char] = nil
	end
	if not kind then
		return nil, nil
	end
	local def = ItemAnim.PROPS[kind]
	if not def then
		return nil, nil
	end
	local m = Instance.new("Model")
	m.Name = "VT65ItemProp"
	local main: BasePart? = nil
	local function piece(size: { number }, cf: CFrame, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
		if shape then
			p.Shape = shape
		end
		p.Size = Vector3.new(size[1], size[2], size[3]) / PROP_M
		p.Color = Color3.fromRGB(def.rgb[1], def.rgb[2], def.rgb[3])
		p.Material = if kind == "curativo" or kind == "torniquete"
			then Enum.Material.Fabric
			else Enum.Material.SmoothPlastic
		p.CFrame = cf
		p.Parent = m
		if main then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = main, p
			w.Parent = p
		else
			main = p
		end
		return p
	end
	local s, M = def.size, PROP_M
	if kind == "pa" then
		piece({ 0.12, 0.03, 0.03 }, CFrame.identity, Enum.PartType.Cylinder) -- cabo em T (mão direita)
		piece(
			{ s[3], s[1], s[2] },
			CFrame.new(0, 0, -s[3] / 2 / M) * CFrame.Angles(0, math.pi / 2, 0),
			Enum.PartType.Cylinder
		)
		local bl = def.blade or { 0.2, 0.15, 0.01 }
		piece({ bl[2], bl[1], bl[3] }, CFrame.new(0, 0, -(s[3] + bl[1] / 2) / M) * CFrame.Angles(math.pi / 2, 0, 0)).Material =
			Enum.Material.Metal
	elseif kind == "binoculo" then
		piece({ s[1] * 0.3, s[2], s[3] }, CFrame.identity)
		for _, x in { -1, 1 } do
			piece(
				{ s[3], s[2], s[2] },
				CFrame.new(x * s[1] * 0.33 / M, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
				Enum.PartType.Cylinder
			)
		end
	elseif kind == "curativo" or kind == "torniquete" then
		piece(s, CFrame.identity, Enum.PartType.Cylinder)
	else
		piece(s, CFrame.identity)
	end
	local p0 = main :: BasePart
	local weld = Instance.new("Weld")
	weld.Part0, weld.Part1 = ut, p0
	weld.C1 = CFrame.identity
	weld.Parent = p0
	m.PrimaryPart = p0
	m.Parent = char
	props[char] = { model = m, weld = weld, kind = kind }
	return m, weld
end

-- último alvo de cada mão (UT, studs) para a saída suave da ação
type ItemLast = { r: Vector3, l: Vector3, slung: boolean, right: boolean, left: boolean }
local itemLast: { [Model]: ItemLast } = setmetatable({}, { __mode = "k" }) :: any

-- Põe as mãos no item (ou na saída dele). Devolve os alvos quando cuidou das mãos neste quadro.
local function holdItem(
	char: Model,
	b: Blend,
	dt: number,
	ut: BasePart,
	hum: Humanoid,
	primary: BasePart,
	weld: Weld,
	hold: CFrame,
	far: boolean
): Goals?
	local prone = char:GetAttribute("Prone") == true
	local now = if prone or char:GetAttribute("Downed") == true then nil else itemOf(char)
	b.item = math.clamp(b.item + (if now then dt else -dt) / 0.25, 0, 1)
	if not now and b.item <= 0 then
		itemLast[char] = nil
		propOf(char, ut, nil)
		return nil
	end
	local last = itemLast[char]
	if now then
		local a = ItemAnim.ANIMS[now.name]
		local tt = ItemAnim.localTime(a, now.t, now.D)
		local r0, l0, tilt = ItemAnim.sample(a.tp, tt)
		local r, l = ItemAnim.reach(r0, "R"), ItemAnim.reach(l0, "L")
		last = {
			r = Vector3.new(r[1], r[2], r[3]) * K,
			l = Vector3.new(l[1], l[2], l[3]) * K,
			slung = a.slung,
			right = a.right,
			left = a.left,
		}
		itemLast[char] = last
		-- objeto na mão
		local p = a.prop
		local _, pw = propOf(char, ut, if p and ItemAnim.propOn(a, tt) then p.kind else nil)
		if pw and p then
			local lr, ll = last.r, last.l
			local cf: CFrame
			if p.kind == "pa" then
				cf = CFrame.lookAt(lr, lr + (ll - lr).Unit)
			elseif p.kind == "binoculo" then
				cf = CFrame.new((lr + ll) / 2 + Vector3.new(0, 0, -0.15))
			elseif p.hand == "L" then
				cf = CFrame.new(ll) * CFrame.Angles(math.rad(-15), 0, 0)
			else
				cf = CFrame.new(lr) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(-tilt), 0, 0)
			end
			if not pw.C0:FuzzyEq(cf, 1e-4) then
				pw.C0 = cf
			end
		end
	else
		propOf(char, ut, nil)
	end
	local L = last :: ItemLast
	local e = smooth(b.item)
	-- fuzil: a tiracolo (como na carta) ou na pega de sempre (rádio)
	local want = if L.slung then hold:Lerp(HOLD_SLUNG, e) else hold
	if not weld.C0:FuzzyEq(want, 1e-4) then
		weld.C0 = want
	end
	local grip = primary:FindFirstChild("Grip") :: Attachment?
	local sup = primary:FindFirstChild("Support") :: Attachment?
	local gR = inUT(grip, ut) or L.r
	local gL = inUT(sup, ut) or L.l
	local tR = alvo(ut, "VT65Alvo_R", gR:Lerp(L.r, if L.right then e else 0))
	local tL = alvo(ut, "VT65Alvo_L", gL:Lerp(L.l, if L.left then e else 0))
	local free = char:GetAttribute("Downed") ~= true
	-- D-99: cotovelos para fora e para cima na mão que usa o item; a que fica no fuzil (rádio) segue
	-- com o polo de sempre
	local stand = ArmIK.POLES.stand
	local pR = if L.right then ItemAnim.POLES.R else stand.R
	local pL = if L.left then ItemAnim.POLES.L else stand.L
	ikTo(
		hum,
		"VT65IK_R",
		char:FindFirstChild("RightUpperArm"),
		char:FindFirstChild("RightHand"),
		tR,
		polo(ut, "VT65Polo_R", pR),
		free and far
	)
	ikTo(
		hum,
		"VT65IK_L",
		char:FindFirstChild("LeftUpperArm"),
		char:FindFirstChild("LeftHand"),
		tL,
		polo(ut, "VT65Polo_L", pL),
		free and far
	)
	if not free then
		return {}
	end
	return {
		R = { target = tR.Position, pole = poleDir(pR, "R"), w = 1 },
		L = { target = tL.Position, pole = poleDir(pL, "L"), w = 1 },
	}
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Estado da arma de um soldado neste quadro (suavizado), a partir dos atributos
local function gunState(char: Model, b: Blend, dt: number, kind: string, info: GunInfo, root: BasePart): Pegada3P.State
	local now = os.clock()
	local mine = char == player.Character
	local shotT = char:GetAttribute("VT65TiroT")
	local since = if type(shotT) == "number" then now - shotT else math.huge
	-- arfagem da mira: a da câmera (o próprio soldado), a do servidor ("AimPitch", se um dia houver)
	-- ou a do último tiro; sem nada, a arma fica no rumo do corpo
	local pitch = 0
	if mine then
		pitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))
	else
		local ap = char:GetAttribute("AimPitch")
		local sp = char:GetAttribute("VT65TiroPitch")
		if type(ap) == "number" then
			pitch = ap
		elseif type(sp) == "number" and since < SHOT_AIM then
			pitch = sp
		end
	end
	b.pitch = approach(b.pitch, pitch, if mine then 30 else 14, dt)
	-- no ombro: atirando (e mirando, o próprio)
	local raise = since < SHOT_RAISE or (mine and player:GetAttribute("Aiming") == true)
	b.ads = approach(b.ads, if raise then 1 else 0, 12, dt)
	b.sprint = approach(b.sprint, if char:GetAttribute("Sprinting") == true then 1 else 0, 8, dt)
	b.prone = approach(b.prone, if char:GetAttribute("Prone") == true then 1 else 0, 6, dt)
	-- passada e giro (velocidade pelo deslocamento da raiz, como no Front 44)
	local pos = root.Position
	local last = b.pos or pos
	b.pos = pos
	local vel = (pos - last) / math.max(dt, 1 / 240)
	local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if flat > 60 then
		flat = 0 -- teleporte ou renascer
	end
	b.speed = approach(b.speed, flat, 10, dt)
	local stride = (if b.prone > 0.5 then 2.6 elseif b.sprint > 0.5 then 7.5 else 4.6) * Corpo.BLOCK_SCALE
	b.phase += b.speed * dt / stride * math.pi * 2
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local dyaw = if b.yaw then (yaw - (b.yaw :: number) + math.pi) % (2 * math.pi) - math.pi else 0
	b.yaw = yaw
	b.yawRate = approach(b.yawRate, math.clamp(dyaw / math.max(dt, 1 / 240), -8, 8), 8, dt)
	local s = Pegada3P.state(kind)
	s.pitch = b.pitch
	s.ads = b.ads
	s.sprint = b.sprint
	s.prone = b.prone
	local rl = char:GetAttribute("VT65Recarga")
	s.busy = if type(rl) == "number" then math.clamp(rl, 0, 1) else 0
	s.rear = info.rear
	s.moving = math.clamp(b.speed / 14 * 1.4, 0, 1)
	s.swing = math.sin(b.phase)
	s.lift = math.abs(math.cos(b.phase))
	s.breath = now + b.seed
	s.yawRate = b.yawRate
	s.kick = if since < 0.5 then math.exp(-since * 16) else 0
	return s
end

-- Arma nas mãos de um soldado (PreSimulation). Devolve os alvos das mãos (espaço da UT).
local function holdWeapon(char: Model, b: Blend, dt: number, far: boolean): Goals?
	local w = char:FindFirstChild("Weapon") :: Model?
	local ut = char:FindFirstChild("UpperTorso") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local primary = w and w.PrimaryPart
	if not (w and ut and hum and primary and root) then
		return nil
	end
	local weld = holdWeld(w, ut, primary)
	if not weld then
		return nil
	end
	local prone = char:GetAttribute("Prone") == true
	local kind = kindOf(w)
	local info = infoOf(w, primary)
	-- pose do Front 44: mira, guarda, ombro, corrida, recarga, deitado (Shared/Pegada3P)
	local s = gunState(char, b, dt, kind, info, root)
	local torso = root.CFrame:ToObjectSpace(ut.CFrame)
	local base = Pegada3P.gun(torso, s)
	local free = char:GetAttribute("Downed") ~= true
	-- carta aberta (servidor, atributo "Carta"; não deitado): fuzil a tiracolo e mãos na carta
	local map =
		mapOf(char, ut, char:GetAttribute("Carta") == true and not prone and char:GetAttribute("Downed") ~= true)
	if map then
		if not weld.C0:FuzzyEq(HOLD_SLUNG, 1e-4) then
			weld.C0 = HOLD_SLUNG
		end
		-- o próprio corpo em 1ª pessoa fica escondido pela câmera, mas a SurfaceGui da folha não: ela
		-- só aparece em 3ª pessoa (em 1ª, a carta da mão é a do CartaMao)
		if char == player.Character then
			local show = player:GetAttribute("ThirdPersonView") == true
			for _, g in map:GetDescendants() do
				if g:IsA("SurfaceGui") and g.Enabled ~= show then
					g.Enabled = show
				end
			end
		end
		local main = map.PrimaryPart :: BasePart
		local poles = ArmIK.POLES.map
		local mR, mL = main:FindFirstChild("MaoD"), main:FindFirstChild("MaoE")
		ikTo(
			hum,
			"VT65IK_R",
			char:FindFirstChild("RightUpperArm"),
			char:FindFirstChild("RightHand"),
			mR,
			polo(ut, "VT65Polo_R", poles.R),
			free and far
		)
		ikTo(
			hum,
			"VT65IK_L",
			char:FindFirstChild("LeftUpperArm"),
			char:FindFirstChild("LeftHand"),
			mL,
			polo(ut, "VT65Polo_L", poles.L),
			free and far
		)
		if not free then
			return {}
		end
		local pR, pL = inUT(mR, ut), inUT(mL, ut)
		return {
			R = if pR then { target = pR, pole = poleDir(poles.R, "R"), w = 1 } else nil,
			L = if pL then { target = pL, pole = poleDir(poles.L, "L"), w = 1 } else nil,
		}
	end
	-- D-99: item na mão (curativo, torniquete, rádio, binóculo, pá, cantil): as mãos seguem o ItemAnim
	local item = holdItem(char, b, dt, ut, hum, primary, weld, base, far)
	if item then
		return item
	end
	-- faca na mão direita (o servidor solda "FacaMao"): fuzil baixo na esquerda, se o clipe existe;
	-- com a granada na mão ("GranadaMao", Modules/ArmaNaMao) o fuzil vai igual para a esquerda
	local nade = char:FindFirstChild("GranadaMao") ~= nil and not prone
	b.nade += ((if nade then 1 else 0) - b.nade) * math.min(1, dt / 0.12)
	local knife = (char:FindFirstChild("FacaMao") ~= nil and SoldierAnims.id("faca_estocada") ~= 0 and not prone)
		or nade
	b.knife += ((if knife then 1 else 0) - b.knife) * math.min(1, dt / 0.12)
	local hold = if b.knife > 1e-3 then base:Lerp(HOLD_KNIFE, smooth(b.knife)) else base
	local m = char:GetAttribute("Melee")
	local mt = char:GetAttribute("MeleeT")
	if (m == "baioneta" or m == "coronhada") and type(mt) == "number" and not prone then
		local t = workspace:GetServerTimeNow() - mt
		if t >= 0 and t < 0.9 then
			hold = strikeHold(hold, t)
		end
	end
	if not weld.C0:FuzzyEq(hold, 1e-5) then
		weld.C0 = hold
	end
	local poles = if prone then ArmIK.POLES.prone else ArmIK.POLES.stand
	ikTo(
		hum,
		"VT65IK_R",
		char:FindFirstChild("RightUpperArm"),
		char:FindFirstChild("RightHand"),
		primary:FindFirstChild("Grip"),
		polo(ut, "VT65Polo_R", poles.R),
		free and far
	)
	ikTo(
		hum,
		"VT65IK_L",
		char:FindFirstChild("LeftUpperArm"),
		char:FindFirstChild("LeftHand"),
		primary:FindFirstChild("Support"),
		polo(ut, "VT65Polo_L", poles.L),
		free and far
	)
	if not free then
		return {}
	end
	-- alvos: o punho e, para a esquerda, o guarda-mão afastado da direita (mãos de bloco), sem
	-- passar do alcance; recarregando, a esquerda vai ao carregador (o clipe gravado não sabe onde a
	-- arma está agora)
	local gp = Pegada3P.POLES[if b.prone > 0.5 then "prone" else "stand"]
	local gripUT = (hold * info.grip)
	local leftGun: Vector3
	if kind == "pistol" then
		leftGun = info.grip + Vector3.new(-0.12, -0.05, 0.05) -- abraça a direita no cabo
	else
		local armL = armOf(char, "L")
		local shoulderL = armL and armL.rig.c0s.Position or Vector3.new(-1, 0.563, 0) * Corpo.BLOCK_SCALE
		leftGun = Pegada3P.support(
			info.support,
			info.front - 0.4,
			hold:PointToObjectSpace(shoulderL),
			if armL then armL.reach else 2.7
		)
	end
	local busy = s.busy
	local lw = 1
	if busy > 0 and kind ~= "pistol" then
		local mag = info.grip + Vector3.new(0, -0.3 - 0.12 * math.abs(math.sin(os.clock() * 5)), -0.35)
		leftGun = leftGun:Lerp(mag, smooth(busy))
	else
		local ikL = hum:FindFirstChild("VT65IK_L") :: IKControl?
		lw = if ikL then ikL.Weight else 1
	end
	local ikR = hum:FindFirstChild("VT65IK_R") :: IKControl?
	-- granada na mão (ArmaNaMao solda "GranadaMao" na direita): a direita sai do punho e segura a
	-- granada diante do peito; o fuzil fica baixo na esquerda (a pega da faca). O arremesso é do clipe.
	local rightT = gripUT
	local g = b.nade
	if g > 1e-3 then
		rightT = gripUT:Lerp(NADE_AT, smooth(g))
	end
	return {
		R = { target = rightT, pole = v3(gp.R), w = if ikR then ikR.Weight else 1 },
		L = { target = hold * leftGun, pole = v3(gp.L), w = lw },
	}
end

-- Transições suaves (pedido do dono, 2026-11-11): as pernas dobram em ~0,25 s e o tronco inclina em
-- ~0,2 s, em vez de pular de pose. Só escreve nas juntas enquanto a mistura anda (pose() compara).
-- "Vaulting" (transpor, Movement.client/PostureService) dobra as pernas como agachado.
local CROUCH_TIME, BLADE_TIME = 0.25, 0.15

local function toward(v: number, target: number, step: number): number
	if v < target then
		return math.min(v + step, target)
	end
	return math.max(v - step, target)
end

-- tronco de lado: só com arma na mão, de pé ou agachado, fora do arremesso, da faca e do assento
local function bladed(char: Model): boolean
	if char:GetAttribute("Prone") == true or char:GetAttribute("Downed") == true then
		return false
	end
	if char:GetAttribute("Throwing") == true or char:FindFirstChild("FacaMao") or char:GetAttribute("Carta") then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.SeatPart ~= nil or hum.Health <= 0 then
		return false
	end
	return char:FindFirstChild("Weapon") ~= nil
end

local function bladeOf(char: Model): number
	local w = char:FindFirstChild("Weapon") :: Model?
	return Pegada3P.blade(if w then kindOf(w) else "rifle")
end

RunService.Heartbeat:Connect(function(dt: number)
	for _, char in characters() do
		local b = blend[char]
		if not b then
			b = newBlend()
			blend[char] = b
		end
		local bent = char:GetAttribute("Crouched") == true or char:GetAttribute("Vaulting") == true
		-- com o clipe agachado tocando (SoldierAnimations marca "VT65Anim", local), as pernas são dele
		if bent and SoldierAnims.id("agachado") ~= 0 and char:GetAttribute("VT65Anim") == true then
			bent = char:GetAttribute("Vaulting") == true
		end
		local lean = char:GetAttribute("Lean")
		b.crouch = toward(b.crouch, if bent then 1 else 0, dt / CROUCH_TIME)
		if char == player.Character then
			b.lean = Inclinar.value() -- o próprio soldado: sem esperar a volta do servidor
		else
			local t = if type(lean) == "number" then math.clamp(lean, -1, 1) else 0
			b.lean += (t - b.lean) * math.min(1, dt * LEAN_RATE)
		end
		b.blade = toward(b.blade, if bladed(char) then 1 else 0, dt / BLADE_TIME)
		local e = b.crouch * b.crouch * (3 - 2 * b.crouch)
		for name, rot in CROUCH do
			local m, rest = motor(char, name)
			if m then
				pose(m, if e >= 1 then rest * rot elseif e <= 0 then rest else rest * CFrame.identity:Lerp(rot, e))
			end
		end
		-- deitado: a junta Root é posada pelo SERVIDOR (PostureService), para o acerto bater.
		-- Tronco de lado (Front 44: 34° no fuzil, 12° na pistola) e a mira dividida entre a cintura (35%)
		-- e o pescoço (50%); a arma completa o resto (Pegada3P desfaz o giro do tronco).
		-- correndo o tronco volta de frente (Front 44: blade × (1 − corrida)); a arma vai atravessada
		local bl = smooth(b.blade) * bladeOf(char) * (1 - b.sprint)
		local up = b.pitch * smooth(b.blade) * (1 - b.prone)
		local waist, rest = motor(char, "Waist")
		if waist then
			pose(
				waist,
				rest
					* CFrame.Angles(up * WAIST_PITCH, 0, 0)
					* CFrame.Angles(0, -bl, 0)
					* CFrame.Angles(0, 0, -b.lean * LEAN_WAIST)
			)
		end
		local neck, nrest = motor(char, "Neck")
		if neck then
			-- a cabeça desfaz o giro do tronco (olha para a frente) e sobe com a mira
			pose(neck, nrest * CFrame.Angles(0, bl, 0) * CFrame.Angles(up * NECK_PITCH, 0, 0))
		end
	end
end)

-- Arma e braços DEPOIS do Animator (clipes) e antes da física: o C0 da arma e o Transform dos braços
-- deste quadro saem juntos na mesma posição (antes: Heartbeat + IKControl, um quadro de atraso).
RunService.PreSimulation:Connect(function(dt: number)
	local cam = camera.CFrame.Position
	for _, char in characters() do
		local b = blend[char]
		if not b then
			b = newBlend()
			blend[char] = b
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (hum and root) or hum.Health <= 0 or hum.SeatPart ~= nil then
			continue
		end
		local d = (root.Position - cam).Magnitude
		local far = d > (if b.near then LOD_FAR * 1.1 else LOD_FAR)
		b.near = not far
		local goals = holdWeapon(char, b, dt, far)
		if far or not goals then
			continue
		end
		for _, side in { "R", "L" } do
			local g = (goals :: any)[side] :: ArmGoal?
			local a = armOf(char, side)
			if g and g.target and a then
				solveArm(a, g.target :: Vector3, g.pole, math.clamp(g.w, 0, 1))
			end
		end
	end
end)
