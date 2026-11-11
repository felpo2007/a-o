--!strict
-- Postura (Parte 10.5 e 12.2): em pé, agachado, deitado, inclinado e correndo. O servidor é a
-- autoridade: muda HipHeight e velocidade (MedicalService.apply) e grava atributos no modelo; os
-- clientes posam todo mundo pelos atributos (PostureController). Não deixa levantar sob teto baixo.
-- Movimento (2026-11-11): o fôlego mora no cliente (Movement.client); aqui há um orçamento de corrida
-- MAIS FOLGADO (Movement.serverBudgetStep) que só corta quem ignora o fôlego. "Vaulting" (transpor)
-- vai para o modelo por ~1 s para os outros clientes dobrarem as pernas.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Joints = require(ReplicatedStorage.Shared.Joints)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Combatants = require(script.Parent.Combatants)
local MedicalService = require(script.Parent.MedicalService)

local PostureService = {}
local DROP = { crouch = 2.2, prone = 4.4 } -- studs que o quadril desce (PLACEHOLDER de pose)
-- HipHeight nunca negativo: com 2,4 − 4,4 = −2 o Humanoid ficava em queda livre o tempo todo e
-- deitado em encosta virava escorregador (66 m/s no teste do Studio, 2026-11-10).
local MIN_HIP = 0.2
-- Deitado: o SERVIDOR deita o corpo (junta Root), para os acertos (raycast no servidor) baterem
-- com o que se vê. Antes só os clientes posavam e o "deitado" do servidor era o corpo enterrado.
local PRONE_ROOT = CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(-85), 0, 0)

-- Motor6D ou AnimationConstraint (Shared/Joints): com a atualização de juntas do Roblox, a junta
-- Root virou AnimationConstraint e o corpo deixou de deitar (reteste no Studio, 2026-11-10).
local function setProneJoint(model: Model, prone: boolean)
	local lower = model:FindFirstChild("LowerTorso")
	local root = lower and Joints.find(lower, "Root")
	if not root then
		return
	end
	local orig = Joints.rest(root)
	if not orig then
		return
	end
	Joints.setC0(root, if prone then orig * PRONE_ROOT else orig)
end

-- Deitado, o corpo encosta no chão. Com a colisão normal o soldado era empurrado e escorregava
-- (reteste no Studio, 2026-11-10: 70 m em 5 s numa encosta de 14°), e o Humanoid religa o
-- CanCollide do tronco. Por isso, grupos de colisão: o corpo deitado não colide com o terreno
-- ("Ground"), mas os dois continuam colidindo com o grupo padrão, e os raycasts dos tiros (grupo
-- Default) ainda acertam o corpo. O HumanoidRootPart fica no Default e segura o soldado pelo HipHeight.
local GROUND, PRONE_BODY = "Ground", "ProneBody"
local function setProneCollision(model: Model, prone: boolean)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.CollisionGroup = if prone then PRONE_BODY else "Default"
		end
	end
end

local function headroom(model: Model, need: number): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local head = model:FindFirstChild("Head") :: BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if head then head.Position elseif root then root.Position else nil
	return from == nil or workspace:Raycast(from, Vector3.new(0, need + 0.3, 0), params) == nil
end

-- stance: "stand" | "crouch" | "prone"
local function setStance(model: Model, stance: string): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or model:GetAttribute("Downed") then
		return false
	end
	local cur = if model:GetAttribute("Prone")
		then "prone"
		elseif model:GetAttribute("Crouched") then "crouch"
		else "stand"
	if cur == stance then
		return true
	end
	local curDrop = if cur == "stand" then 0 else DROP[cur]
	local newDrop = if stance == "stand" then 0 else DROP[stance]
	if newDrop < curDrop and not headroom(model, curDrop - newDrop) then
		return false -- sem espaço para subir (túnel, teto baixo)
	end
	local base = model:GetAttribute("BaseHipHeight")
	if type(base) ~= "number" then
		base = hum.HipHeight
		model:SetAttribute("BaseHipHeight", base)
	end
	hum.HipHeight = math.max((base :: number) - newDrop, MIN_HIP)
	setProneJoint(model, stance == "prone")
	setProneCollision(model, stance == "prone")
	model:SetAttribute("Crouched", stance == "crouch")
	model:SetAttribute("Prone", stance == "prone")
	if stance ~= "stand" then
		model:SetAttribute("Sprinting", false)
	end
	if stance == "prone" then
		model:SetAttribute("Lean", 0)
	end
	MedicalService.apply(model)
	return true
end
PostureService.setStance = setStance

function PostureService.setCrouch(model: Model, on: boolean): boolean
	return setStance(model, if on then "crouch" else "stand")
end

-- orçamento de corrida por jogador (0..1), folgado de propósito (ver Movement.SERVER_*)
local budget: { [Player]: number } = {}
local budgetChar: { [Player]: Model? } = {}

function PostureService.start()
	for _, g in { GROUND, PRONE_BODY } do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(PRONE_BODY, GROUND, false)
	workspace.Terrain.CollisionGroup = GROUND
	Players.PlayerRemoving:Connect(function(p)
		budget[p] = nil
		budgetChar[p] = nil
	end)
	task.spawn(function()
		local DT = 0.25
		while true do
			task.wait(DT)
			for _, p in Players:GetPlayers() do
				local char = p.Character
				if budgetChar[p] ~= char then
					budgetChar[p] = char
					budget[p] = 1 -- renasceu descansado (o cliente também zera o cansaço)
				end
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local v = if root then root.AssemblyLinearVelocity else Vector3.zero
				-- só gasta correndo de verdade (como o cliente), não com a corrida ligada e parado
				local running = char ~= nil
					and char:GetAttribute("Sprinting") == true
					and Vector3.new(v.X, 0, v.Z).Magnitude * Movement.STUD_M > Movement.SPRINT_COUNT_MPS
				local b = Movement.serverBudgetStep(budget[p] or 1, DT, running)
				budget[p] = b
				if running and b <= 0 and char then
					char:SetAttribute("Sprinting", false)
					MedicalService.apply(char)
				end
			end
		end
	end)
	Net.event("Posture_Set").OnServerEvent:Connect(function(player, req: any)
		local char = player.Character
		if not (char and Combatants.get(char)) then
			return
		end
		if type(req) == "table" and (req.vault == "vault" or req.vault == "mantle") then
			-- transpor: só de pé, sem estar caído, um por vez
			local hum = char:FindFirstChildOfClass("Humanoid")
			if
				hum
				and hum.Health > 0
				and not char:GetAttribute("Prone")
				and not char:GetAttribute("Downed")
				and not char:GetAttribute("Vaulting")
			then
				char:SetAttribute("Vaulting", true)
				local dur = if type(req.dur) == "number" and req.dur == req.dur
					then math.clamp(req.dur, 0.3, 1.5)
					else 0.8
				task.delay(dur, function()
					if char.Parent then
						char:SetAttribute("Vaulting", nil)
					end
				end)
			end
			return
		end
		if type(req) == "boolean" then -- formato antigo: agachar
			setStance(char, if req then "crouch" else "stand")
			return
		end
		if type(req) ~= "table" then
			return
		end
		if req.stance == "stand" or req.stance == "crouch" or req.stance == "prone" then
			setStance(char, req.stance)
		end
		if type(req.lean) == "number" then
			local l = math.clamp(math.round(req.lean), -1, 1)
			char:SetAttribute("Lean", if char:GetAttribute("Prone") then 0 else l)
		end
		if type(req.sprint) == "boolean" then
			local ok = req.sprint
				and not char:GetAttribute("Crouched")
				and not char:GetAttribute("Prone")
				and (if budgetChar[player] == char then budget[player] or 1 else 1) >= Movement.SERVER_MIN_TO_START
			char:SetAttribute("Sprinting", ok)
			MedicalService.apply(char)
		end
	end)
end

return PostureService
