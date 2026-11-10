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

local original: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local CROUCH: { [string]: CFrame } = {
	LeftHip = CFrame.Angles(math.rad(70), 0, 0),
	RightHip = CFrame.Angles(math.rad(70), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-100), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-100), 0, 0),
}
local LEAN_WAIST = math.rad(16) -- inclinação do tronco (PLACEHOLDER)

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

local function motor(char: Model, name: string): Instance?
	local m = Joints.find(char, name)
	if m and not original[m] then
		local c0 = Joints.getC0(m)
		if not c0 then
			return nil
		end
		original[m] = c0
	end
	return m
end

-- só grava quando muda (evita escrever ~5 juntas × 60 personagens a cada quadro)
local function pose(m: Instance, cf: CFrame)
	if Joints.getC0(m) ~= cf then
		Joints.setC0(m, cf)
	end
end

RunService.Heartbeat:Connect(function()
	for _, char in characters() do
		local crouched = char:GetAttribute("Crouched") == true
		local lean = char:GetAttribute("Lean")
		for name, rot in CROUCH do
			local m = motor(char, name)
			if m then
				pose(m, if crouched then original[m] * rot else original[m])
			end
		end
		-- deitado: a junta Root é posada pelo SERVIDOR (PostureService), para o acerto bater
		local waist = motor(char, "Waist")
		if waist then
			local l = if type(lean) == "number" then lean else 0
			pose(waist, original[waist] * CFrame.Angles(0, 0, -l * LEAN_WAIST))
		end
	end
end)
