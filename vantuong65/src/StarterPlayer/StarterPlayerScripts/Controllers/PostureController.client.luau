--!strict
-- Poses de postura de TODOS os personagens (jogadores e bots), a partir dos atributos que o
-- servidor grava: "Crouched" (pernas dobradas), "Prone" (corpo deitado) e "Lean" (-1/0/1, tronco
-- inclinado). C0 dos Motor6D é local; por isso cada cliente posa todo mundo. Visual placeholder até
-- as animações próprias. As entradas ficam no InfantryController (camada Input, Parte 12).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local original: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local CROUCH: { [string]: CFrame } = {
	LeftHip = CFrame.Angles(math.rad(70), 0, 0),
	RightHip = CFrame.Angles(math.rad(70), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-100), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-100), 0, 0),
}
local PRONE_ROOT = CFrame.Angles(math.rad(-85), 0, 0) -- corpo deitado de bruços
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

local function motor(char: Model, name: string): Motor6D?
	local m = char:FindFirstChild(name, true)
	if m and m:IsA("Motor6D") then
		if not original[m] then
			original[m] = m.C0
		end
		return m
	end
	return nil
end

RunService.Heartbeat:Connect(function()
	for _, char in characters() do
		local crouched = char:GetAttribute("Crouched") == true
		local prone = char:GetAttribute("Prone") == true
		local lean = char:GetAttribute("Lean")
		for name, rot in CROUCH do
			local m = motor(char, name)
			if m then
				m.C0 = if crouched then original[m] * rot else original[m]
			end
		end
		local root = motor(char, "Root")
		if root then
			root.C0 = if prone then original[root] * PRONE_ROOT else original[root]
		end
		local waist = motor(char, "Waist")
		if waist then
			local l = if type(lean) == "number" then lean else 0
			waist.C0 = original[waist] * CFrame.Angles(0, 0, -l * LEAN_WAIST)
		end
	end
end)
