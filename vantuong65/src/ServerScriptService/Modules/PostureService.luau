--!strict
-- Postura em pé/agachado (Parte 10.5, versão mínima para os túneis da F3). O servidor é a
-- autoridade: muda HipHeight e a velocidade; os clientes dobram as pernas de todo mundo que tem o
-- atributo "Crouched" (PostureController). Não deixa levantar sob teto baixo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Combatants = require(script.Parent.Combatants)
local MedicalService = require(script.Parent.MedicalService)

local PostureService = {}
local DROP = 2.2 -- studs que o quadril desce ao agachar (6,25 -> ~4,05 studs de altura)

local function setCrouch(model: Model, on: boolean): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root) or model:GetAttribute("Downed") then
		return false
	end
	local was = model:GetAttribute("Crouched") == true
	if on == was then
		return true
	end
	if not on then
		-- só levanta se houver espaço acima da cabeça
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local head = model:FindFirstChild("Head") :: BasePart?
		local from = if head then head.Position else root.Position
		if workspace:Raycast(from, Vector3.new(0, DROP + 0.3, 0), params) then
			return false
		end
	end
	local base = model:GetAttribute("BaseHipHeight")
	if type(base) ~= "number" then
		base = hum.HipHeight
		model:SetAttribute("BaseHipHeight", base)
	end
	hum.HipHeight = if on then (base :: number) - DROP else base :: number
	model:SetAttribute("Crouched", on)
	MedicalService.apply(model) -- recalcula a velocidade
	return true
end
PostureService.setCrouch = setCrouch

function PostureService.start()
	Net.event("Posture_Set").OnServerEvent:Connect(function(player, crouched)
		local char = player.Character
		if char and Combatants.get(char) and type(crouched) == "boolean" then
			setCrouch(char, crouched)
		end
	end)
end

return PostureService
