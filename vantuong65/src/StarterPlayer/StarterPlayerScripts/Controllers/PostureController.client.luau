--!strict
-- Poses de postura de TODOS os personagens (jogadores e bots), a partir dos atributos que o
-- servidor grava: "Crouched" (pernas dobradas), "Prone" (corpo deitado) e "Lean" (-1/0/1, tronco
-- inclinado). O C0 da junta (Motor6D, ou o Attachment0 da AnimationConstraint: Shared/Joints) mudado
-- no cliente é local; por isso cada cliente posa todo mundo. Com os clipes de captura
-- (SoldierAnimations) as pernas do agachado vêm deles; a dobra daqui fica de reserva.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArmIK = require(ReplicatedStorage.Shared.ArmIK)
local Joints = require(ReplicatedStorage.Shared.Joints)
local SoldierAnims = require(ReplicatedStorage.Shared.SoldierAnims)
local Weapons = require(ReplicatedStorage.Shared.Weapons)

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
local LEAN_WAIST = math.rad(16) -- inclinação do tronco (PLACEHOLDER)

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

local function holdCF(h: { number }): CFrame
	return CFrame.new(h[1], h[2], h[3]) * CFrame.Angles(0, math.rad(h[4]), 0) * CFrame.Angles(math.rad(h[5]), 0, 0)
end
local HOLD_PISTOL = holdCF(ArmIK.HOLDS.pistol)
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
	local v = Vector3.new(pos[1], pos[2], pos[3])
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
	n.C0 = HOLD_STAND
	n.Parent = primary
	return n
end

type Blend = { crouch: number, lean: number, blade: number, knife: number }
local blend: { [Model]: Blend } = setmetatable({}, { __mode = "k" }) :: any

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
	local base = if prone then HOLD_PRONE elseif kind == "pistol" then HOLD_PISTOL else HOLD_STAND
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
local CROUCH_TIME, LEAN_TIME, BLADE_TIME = 0.25, 0.2, 0.15
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
	if char:GetAttribute("Throwing") == true or char:FindFirstChild("FacaMao") then
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
			b = { crouch = 0, lean = 0, blade = 0, knife = 0 }
			blend[char] = b
		end
		local bent = char:GetAttribute("Crouched") == true or char:GetAttribute("Vaulting") == true
		-- com o clipe agachado tocando (SoldierAnimations marca "VT65Anim", local), as pernas são dele
		if bent and SoldierAnims.id("agachado") ~= 0 and char:GetAttribute("VT65Anim") == true then
			bent = char:GetAttribute("Vaulting") == true
		end
		local lean = char:GetAttribute("Lean")
		b.crouch = toward(b.crouch, if bent then 1 else 0, dt / CROUCH_TIME)
		b.lean = toward(b.lean, if type(lean) == "number" then lean else 0, dt / LEAN_TIME)
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
