--!strict
-- Poses de postura de TODOS os personagens (jogadores e bots), a partir dos atributos que o
-- servidor grava: "Crouched" (pernas dobradas), "Prone" (corpo deitado) e "Lean" (-1/0/1, tronco
-- inclinado). O C0 da junta (Motor6D, ou o Attachment0 da AnimationConstraint: Shared/Joints) mudado
-- no cliente é local; por isso cada cliente posa todo mundo. Visual placeholder até as animações
-- próprias. As entradas ficam no InfantryController (camada Input, Parte 12).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Joints = require(ReplicatedStorage.Shared.Joints)

-- pose de repouso de cada junta: Joints.rest (atributo na instância; a tabela fraca de antes
-- perdia entradas e as rotações acumulavam)
local CROUCH: { [string]: CFrame } = {
	LeftHip = CFrame.Angles(math.rad(70), 0, 0),
	RightHip = CFrame.Angles(math.rad(70), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-100), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-100), 0, 0),
}
local LEAN_WAIST = math.rad(16) -- inclinação do tronco (PLACEHOLDER)

-- Arma nas mãos: a arma passa a ficar presa ao peito (no cliente), e as duas mãos vão até ela por IK
-- (IKControl): a direita no punho, a esquerda à frente do carregador. Presa à mão (como o servidor a
-- cria), ela seguia a rotação do pulso, que o IK não acerta (20° de erro medidos no Studio).
-- Em pé ou agachado: pronta-baixa, cano 20° para baixo e cruzando o corpo, para a mão esquerda
-- alcançar. Deitado: à frente do peito, cano na horizontal a ~0,2 m do chão (o tronco deitado tem o
-- +Y para a frente).
-- O IK do braço só alcança ~2,05 studs a partir do ombro (medido no Studio). Com as armas reais
-- (2026-11-10) o apoio da M14 ficava a 2,57 studs do ombro esquerdo e a mão parava a 20 cm dele: a
-- pega em pé veio 0,5 stud para trás e 0,3 para o centro (pior caso entre as 9 armas: 1,96 studs).
-- Medido no Studio com a M14 real: em pé, mãos a 7 e 11 cm do punho e do apoio (antes 6 e 20).
-- Deitado, o IK erra mais conforme a pose (até 43 cm na busca em grade): a pega foi para 0,5 stud à
-- frente (perto do rosto) e 0,4 para a esquerda: 8 e 10 cm (antes 27 e 24 cm).
local HOLD_STAND = CFrame.new(0.2, 0.2, -0.7) * CFrame.Angles(0, math.rad(15), 0) * CFrame.Angles(math.rad(-20), 0, 0)
local HOLD_PRONE = CFrame.new(-0.2, 1.3, 1.1) * CFrame.Angles(math.rad(90), 0, 0)

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

local function ikTo(hum: Humanoid, name: string, root: Instance?, effector: Instance?, target: Instance?, on: boolean)
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
		ik.ChainRoot = root
		ik.EndEffector = effector
		ik.Target = target
		ik.Enabled = on
	else
		ik.Enabled = false
	end
end

local function holdWeapon(char: Model)
	local w = char:FindFirstChild("Weapon") :: Model?
	local ut = char:FindFirstChild("UpperTorso") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local primary = w and w.PrimaryPart
	if not (w and ut and hum and primary) then
		return
	end
	local key = if char:GetAttribute("Prone") == true then "prone" else "stand"
	if w:GetAttribute("VT65Hold") ~= key then
		-- a solda que o servidor criou (mão → arma) passa a ser peito → arma, só neste cliente
		local weld: WeldConstraint? = nil
		for _, d in primary:GetChildren() do
			if d:IsA("WeldConstraint") and d.Part0 and not (d.Part0 :: BasePart):IsDescendantOf(w) then
				weld = d
			end
		end
		if not weld then
			return
		end
		weld.Enabled = false
		w:PivotTo(ut.CFrame * (if key == "prone" then HOLD_PRONE else HOLD_STAND))
		weld.Part0 = ut
		weld.Enabled = true
		w:SetAttribute("VT65Hold", key)
	end
	local free = char:GetAttribute("Downed") ~= true
	ikTo(
		hum,
		"VT65IK_R",
		char:FindFirstChild("RightUpperArm"),
		char:FindFirstChild("RightHand"),
		primary:FindFirstChild("Grip"),
		free
	)
	ikTo(
		hum,
		"VT65IK_L",
		char:FindFirstChild("LeftUpperArm"),
		char:FindFirstChild("LeftHand"),
		primary:FindFirstChild("Support"),
		free
	)
end

-- Transições suaves (pedido do dono, 2026-11-11): as pernas dobram em ~0,25 s e o tronco inclina em
-- ~0,2 s, em vez de pular de pose. Só escreve nas juntas enquanto a mistura anda (pose() compara).
-- "Vaulting" (transpor, Movement.client/PostureService) dobra as pernas como agachado.
local CROUCH_TIME, LEAN_TIME = 0.25, 0.2
type Blend = { crouch: number, lean: number }
local blend: { [Model]: Blend } = setmetatable({}, { __mode = "k" }) :: any

local function toward(v: number, target: number, step: number): number
	if v < target then
		return math.min(v + step, target)
	end
	return math.max(v - step, target)
end

RunService.Heartbeat:Connect(function(dt: number)
	for _, char in characters() do
		local b = blend[char]
		if not b then
			b = { crouch = 0, lean = 0 }
			blend[char] = b
		end
		local bent = char:GetAttribute("Crouched") == true or char:GetAttribute("Vaulting") == true
		local lean = char:GetAttribute("Lean")
		b.crouch = toward(b.crouch, if bent then 1 else 0, dt / CROUCH_TIME)
		b.lean = toward(b.lean, if type(lean) == "number" then lean else 0, dt / LEAN_TIME)
		local e = b.crouch * b.crouch * (3 - 2 * b.crouch)
		for name, rot in CROUCH do
			local m, rest = motor(char, name)
			if m then
				pose(m, if e >= 1 then rest * rot elseif e <= 0 then rest else rest * CFrame.identity:Lerp(rot, e))
			end
		end
		holdWeapon(char)
		-- deitado: a junta Root é posada pelo SERVIDOR (PostureService), para o acerto bater
		local waist, rest = motor(char, "Waist")
		if waist then
			pose(waist, rest * CFrame.Angles(0, 0, -b.lean * LEAN_WAIST))
		end
	end
end)
