--!strict
-- Agachar (tecla C). O servidor confirma (HipHeight e velocidade). Aqui dobramos as pernas de
-- todos os personagens com atributo "Crouched" (C0 dos Motor6D; visual placeholder até as
-- animações próprias).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local original: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local POSE: { [string]: CFrame } = {
	LeftHip = CFrame.Angles(math.rad(70), 0, 0),
	RightHip = CFrame.Angles(math.rad(70), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-100), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-100), 0, 0),
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.C then
		return
	end
	local char = player.Character
	if char then
		Net.event("Posture_Set"):FireServer(not char:GetAttribute("Crouched"))
	end
end)

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

RunService.Heartbeat:Connect(function()
	for _, char in characters() do
		local crouched = char:GetAttribute("Crouched") == true
		for name, rot in POSE do
			local m = char:FindFirstChild(name, true)
			if m and m:IsA("Motor6D") then
				if not original[m] then
					original[m] = m.C0
				end
				m.C0 = if crouched then original[m] * rot else original[m]
			end
		end
	end
end)
