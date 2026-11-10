--!strict
-- Postura (Parte 10.5 e 12.2): em pé, agachado, deitado, inclinado e correndo. O servidor é a
-- autoridade: muda HipHeight e velocidade (MedicalService.apply) e grava atributos no modelo; os
-- clientes posam todo mundo pelos atributos (PostureController). Não deixa levantar sob teto baixo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function setProneJoint(model: Model, prone: boolean)
	local lower = model:FindFirstChild("LowerTorso")
	local root = lower and lower:FindFirstChild("Root")
	if not (root and root:IsA("Motor6D")) then
		return
	end
	local orig = root:GetAttribute("StandC0")
	if typeof(orig) ~= "CFrame" then
		orig = root.C0
		root:SetAttribute("StandC0", orig)
	end
	root.C0 = if prone then (orig :: CFrame) * PRONE_ROOT else orig :: CFrame
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

function PostureService.start()
	Net.event("Posture_Set").OnServerEvent:Connect(function(player, req: any)
		local char = player.Character
		if not (char and Combatants.get(char)) then
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
			local ok = req.sprint and not char:GetAttribute("Crouched") and not char:GetAttribute("Prone")
			char:SetAttribute("Sprinting", ok)
			MedicalService.apply(char)
		end
	end)
end

return PostureService
