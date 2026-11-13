--!strict
-- Poses de postura de TODOS os personagens (jogadores e bots), a partir dos atributos que o
-- servidor grava: "Crouched" (pernas dobradas), "Prone" (corpo deitado) e "Lean" (−1..1 em quartos,
-- tronco inclinado; D-99: o próprio soldado usa o valor local do Controllers/Inclinar). O C0 da junta (Motor6D, ou o Attachment0 da AnimationConstraint: Shared/Joints) mudado
-- no cliente é local; por isso cada cliente posa todo mundo. Com os clipes de captura
-- (SoldierAnimations) as pernas do agachado vêm deles; a dobra daqui fica de reserva.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArmIK = require(ReplicatedStorage.Shared.ArmIK)
local CartaModel = require(ReplicatedStorage.Shared.CartaModel)
local FieldWork = require(ReplicatedStorage.Shared.FieldWork)
local ItemAnim = require(ReplicatedStorage.Shared.ItemAnim)
local Joints = require(ReplicatedStorage.Shared.Joints)
local Movement = require(ReplicatedStorage.Shared.Movement)
local SoldierAnims = require(ReplicatedStorage.Shared.SoldierAnims)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Inclinar = require(script.Parent.Inclinar)

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

-- Arma nas mãos: a arma fica presa ao peito (no cliente) e as duas mãos vão até ela por IK
-- (IKControl): a direita no punho, a esquerda no apoio do guarda-mão. Presa à mão (como o servidor a
-- cria), ela seguia a rotação do pulso, que o IK não acerta (20° de erro medidos no Studio).
-- D-94 ("os braços atravessam o corpo", dono): na simulação do Lune (Shared/ArmIK, tests/luau/faca)
-- a pega antiga (0,2; 0,2; −0,7; 15°; −20°) punha o antebraço direito 13 cm dentro do peito e a
-- coronha 20 cm. Agora:
-- - polo de cotovelo (IKControl.Pole) nos dois braços: cotovelo para fora e para baixo;
-- - tronco de lado (ArmIK.BLADE_DEG, o ombro esquerdo à frente, a cabeça olhando para a frente);
-- - pega nova, com o punho na altura do peito e a boca para baixo e cruzando (0 cm de penetração
--   dos braços e da arma em todas as torções de pelve e flexões medidas); pistola com os braços à
--   frente (até 1,7 cm no pior caso medido, torção de 100°);
-- - a arma presa por uma Weld local (C0 mutável): a baioneta avança com o golpe e, com a faca na
--   mão direita, o fuzil fica só na esquerda.
local HOLD_STAND = CFrame.new(0.25, 0.8, -1.5) * CFrame.Angles(0, math.rad(55), 0) * CFrame.Angles(math.rad(-20), 0, 0)
-- Deitado com a animação de captura (SoldierAnims, D-88): pega medida na pose "deitado" do retarget
-- (tools/anim); a pega antiga (0,2 / 1,3 / 1,1, 90°) deixava o fuzil acima das costas.
local HOLD_PRONE = CFrame.new(0.572, 1.446, -0.281)
	* CFrame.fromEulerAnglesXYZ(math.rad(76.29), math.rad(-0.70), math.rad(7.71))

-- D-98: o soldado é o corpo de 1,75 m ampliado por K (Shared/Corpo, SoldierAnims.SCALE). As pegas e
-- os polos acima e no ArmIK estão no tamanho da gravação (os clipes contam com eles); no jogo a
-- posição vai vezes K, a rotação fica. A arma segue no tamanho real.
local K = SoldierAnims.SCALE
local function big(cf: CFrame): CFrame
	return cf.Rotation + cf.Position * K
end
local HOLD_STAND_K = big(HOLD_STAND)
local HOLD_PRONE_K = big(HOLD_PRONE)
local function holdCF(h: { number }): CFrame
	return big(CFrame.new(h[1], h[2], h[3]) * CFrame.Angles(0, math.rad(h[4]), 0) * CFrame.Angles(math.rad(h[5]), 0, 0))
end
local HOLD_PISTOL = holdCF(ArmIK.HOLDS.pistol)
-- Carta na mão (D-98, atributo "Carta" do servidor): o fuzil a tiracolo no ombro direito, boca para
-- cima, e as duas mãos nas bordas da carta aberta diante do peito, inclinada para os olhos.
local HOLD_SLUNG = holdCF(ArmIK.HOLDS.slung)
local MAP_AT = holdCF(ArmIK.HOLDS.map)
-- Golpe com o fuzil (baioneta e coronhada): em guarda (boca para a frente) e a estocada com o passo;
-- o peito avança no clipe "baioneta" (tools/anim). Com a faca: o fuzil baixo na mão esquerda.
local HOLD_GUARD = holdCF(ArmIK.HOLDS.guard)
local HOLD_LUNGE = holdCF(ArmIK.HOLDS.lunge)
local HOLD_KNIFE = holdCF(ArmIK.HOLDS.knife)
local HOLD_RELOAD = holdCF(ArmIK.HOLDS.reload)
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
	n.C0 = HOLD_STAND_K
	n.Parent = primary
	return n
end

type Blend = { crouch: number, lean: number, blade: number, knife: number, item: number }
local blend: { [Model]: Blend } = setmetatable({}, { __mode = "k" }) :: any

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

-- Põe as mãos no item (ou na saída dele). Devolve true quando cuidou das mãos neste quadro.
local function holdItem(
	char: Model,
	b: Blend,
	dt: number,
	ut: BasePart,
	hum: Humanoid,
	primary: BasePart,
	weld: Weld,
	hold: CFrame
): boolean
	local prone = char:GetAttribute("Prone") == true
	local now = if prone or char:GetAttribute("Downed") == true then nil else itemOf(char)
	b.item = math.clamp(b.item + (if now then dt else -dt) / 0.25, 0, 1)
	if not now and b.item <= 0 then
		itemLast[char] = nil
		propOf(char, ut, nil)
		return false
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
	local inv = ut.CFrame:Inverse()
	local grip = primary:FindFirstChild("Grip") :: Attachment?
	local sup = primary:FindFirstChild("Support") :: Attachment?
	local gR = if grip then (inv * grip.WorldCFrame).Position else L.r
	local gL = if sup then (inv * sup.WorldCFrame).Position else L.l
	local tR = alvo(ut, "VT65Alvo_R", gR:Lerp(L.r, if L.right then e else 0))
	local tL = alvo(ut, "VT65Alvo_L", gL:Lerp(L.l, if L.left then e else 0))
	local free = char:GetAttribute("Downed") ~= true
	-- D-99: cotovelos para fora e para cima na mão que usa o item; a que fica no fuzil (rádio) segue
	-- com o polo de sempre
	local stand = ArmIK.POLES.stand
	ikTo(
		hum,
		"VT65IK_R",
		char:FindFirstChild("RightUpperArm"),
		char:FindFirstChild("RightHand"),
		tR,
		polo(ut, "VT65Polo_R", if L.right then ItemAnim.POLES.R else stand.R),
		free
	)
	ikTo(
		hum,
		"VT65IK_L",
		char:FindFirstChild("LeftUpperArm"),
		char:FindFirstChild("LeftHand"),
		tL,
		polo(ut, "VT65Polo_L", if L.left then ItemAnim.POLES.L else stand.L),
		free
	)
	return true
end

local function holdWeapon(char: Model, b: Blend, dt: number)
	local w = char:FindFirstChild("Weapon") :: Model?
	local ut = char:FindFirstChild("UpperTorso") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local primary = w and w.PrimaryPart
	if not (w and ut and hum and primary) then
		return
	end
	local weld = holdWeld(w, ut, primary)
	if not weld then
		return
	end
	local prone = char:GetAttribute("Prone") == true
	local kind = kindOf(w)
	local base = if prone then HOLD_PRONE_K elseif kind == "pistol" then HOLD_PISTOL else HOLD_STAND_K
	-- carta aberta (servidor, atributo "Carta"; não deitado): fuzil a tiracolo e mãos na carta
	local map =
		mapOf(char, ut, char:GetAttribute("Carta") == true and not prone and char:GetAttribute("Downed") ~= true)
	if map then
		if not weld.C0:FuzzyEq(HOLD_SLUNG, 1e-4) then
			weld.C0 = HOLD_SLUNG
		end
		-- o próprio corpo em 1ª pessoa fica escondido pela câmera, mas a SurfaceGui da folha não: ela
		-- só aparece em 3ª pessoa (em 1ª, a carta da mão é a do CartaMao)
		local lp = Players.LocalPlayer
		if char == lp.Character then
			local show = lp:GetAttribute("ThirdPersonView") == true
			for _, g in map:GetDescendants() do
				if g:IsA("SurfaceGui") and g.Enabled ~= show then
					g.Enabled = show
				end
			end
		end
		local main = map.PrimaryPart :: BasePart
		local free = char:GetAttribute("Downed") ~= true
		local poles = ArmIK.POLES.map
		ikTo(
			hum,
			"VT65IK_R",
			char:FindFirstChild("RightUpperArm"),
			char:FindFirstChild("RightHand"),
			main:FindFirstChild("MaoD"),
			polo(ut, "VT65Polo_R", poles.R),
			free
		)
		ikTo(
			hum,
			"VT65IK_L",
			char:FindFirstChild("LeftUpperArm"),
			char:FindFirstChild("LeftHand"),
			main:FindFirstChild("MaoE"),
			polo(ut, "VT65Polo_L", poles.L),
			free
		)
		return
	end
	-- D-99: item na mão (curativo, torniquete, rádio, binóculo, pá, cantil): as mãos seguem o ItemAnim
	if holdItem(char, b, dt, ut, hum, primary, weld, base) then
		return
	end
	-- faca na mão direita (o servidor solda "FacaMao"): fuzil baixo na esquerda, se o clipe existe
	local knife = char:FindFirstChild("FacaMao") ~= nil and SoldierAnims.id("faca_estocada") ~= 0 and not prone
	b.knife += ((if knife then 1 else 0) - b.knife) * math.min(1, dt / 0.12)
	local hold = if b.knife > 1e-3 then base:Lerp(HOLD_KNIFE, smooth(b.knife)) else base
	-- recarga (peso do clipe, posto pelo SoldierAnimations): o fuzil sobe para o peito
	local rl = char:GetAttribute("VT65Recarga")
	if type(rl) == "number" and rl > 0 and not prone and kind ~= "pistol" then
		hold = hold:Lerp(HOLD_RELOAD, smooth(rl))
	end
	local m = char:GetAttribute("Melee")
	local mt = char:GetAttribute("MeleeT")
	if (m == "baioneta" or m == "coronhada") and type(mt) == "number" and not prone then
		local t = workspace:GetServerTimeNow() - mt
		if t >= 0 and t < 0.9 then
			hold = strikeHold(hold, t)
		end
	end
	if (weld.C0.Position - hold.Position).Magnitude > 1e-4 or not weld.C0.Rotation:FuzzyEq(hold.Rotation, 1e-4) then
		weld.C0 = hold
	end
	local free = char:GetAttribute("Downed") ~= true
	local poles = if prone then ArmIK.POLES.prone else ArmIK.POLES.stand
	ikTo(
		hum,
		"VT65IK_R",
		char:FindFirstChild("RightUpperArm"),
		char:FindFirstChild("RightHand"),
		primary:FindFirstChild("Grip"),
		polo(ut, "VT65Polo_R", poles.R),
		free
	)
	ikTo(
		hum,
		"VT65IK_L",
		char:FindFirstChild("LeftUpperArm"),
		char:FindFirstChild("LeftHand"),
		primary:FindFirstChild("Support"),
		polo(ut, "VT65Polo_L", poles.L),
		free
	)
end

-- Transições suaves (pedido do dono, 2026-11-11): as pernas dobram em ~0,25 s e o tronco inclina em
-- ~0,2 s, em vez de pular de pose. Só escreve nas juntas enquanto a mistura anda (pose() compara).
-- "Vaulting" (transpor, Movement.client/PostureService) dobra as pernas como agachado.
local CROUCH_TIME, BLADE_TIME = 0.25, 0.15
local BLADE = math.rad(ArmIK.BLADE_DEG)

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

RunService.Heartbeat:Connect(function(dt: number)
	for _, char in characters() do
		local b = blend[char]
		if not b then
			b = { crouch = 0, lean = 0, blade = 0, knife = 0, item = 0 }
			blend[char] = b
		end
		local bent = char:GetAttribute("Crouched") == true or char:GetAttribute("Vaulting") == true
		-- com o clipe agachado tocando (SoldierAnimations marca "VT65Anim", local), as pernas são dele
		if bent and SoldierAnims.id("agachado") ~= 0 and char:GetAttribute("VT65Anim") == true then
			bent = char:GetAttribute("Vaulting") == true
		end
		local lean = char:GetAttribute("Lean")
		b.crouch = toward(b.crouch, if bent then 1 else 0, dt / CROUCH_TIME)
		if char == Players.LocalPlayer.Character then
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
		holdWeapon(char, b, dt)
		-- deitado: a junta Root é posada pelo SERVIDOR (PostureService), para o acerto bater
		local bl = smooth(b.blade) * BLADE
		local waist, rest = motor(char, "Waist")
		if waist then
			pose(waist, rest * CFrame.Angles(0, -bl, 0) * CFrame.Angles(0, 0, -b.lean * LEAN_WAIST))
		end
		local neck, nrest = motor(char, "Neck")
		if neck then
			pose(neck, nrest * CFrame.Angles(0, bl, 0)) -- a cabeça olha para a frente
		end
	end
end)
