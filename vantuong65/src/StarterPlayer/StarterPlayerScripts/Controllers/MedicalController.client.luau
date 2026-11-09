--!strict
-- Corpo e cura no cliente: sem barra de vida. A visão perde cor e escurece com a vida, borra
-- depois da reanimação e quando caído; teclas: G curativo, T torniquete, F tratar/reanimar
-- aliado à frente (médico) ou fazer curativo nele, H desistir (caído, após 15 s).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "VT65Body"
cc.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Name = "VT65BodyBlur"
blur.Size = 0
blur.Parent = Lighting

local state: any = nil
Net.event("Medical_State").OnClientEvent:Connect(function(s)
	state = s
	state.recvAt = os.clock()
end)

local function nearestAlly(): Player?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local best, bestD = nil, 3 / 0.28 -- 3 m
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("Faction") == player:GetAttribute("Faction") then
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				local d = (r.Position - root.Position).Magnitude
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
	end
	return best
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.G then
		Net.event("Medical_Action"):FireServer({ op = "bandage" })
	elseif k == Enum.KeyCode.T then
		Net.event("Medical_Action"):FireServer({ op = "tourniquet" })
	elseif k == Enum.KeyCode.H then
		Net.event("Medical_Action"):FireServer({ op = "giveup" })
	elseif k == Enum.KeyCode.F then
		local ally = nearestAlly()
		if ally then
			local op = if ally:GetAttribute("Downed")
				then "revive"
				elseif player:GetAttribute("Role") == "medic" then "treat"
				else "bandage"
			Net.event("Medical_Action"):FireServer({ op = op, target = ally.UserId })
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if not state then
		cc.Saturation, cc.Brightness = 0, 0
		blur.Size = 0
		return
	end
	local h = math.clamp(state.health or 100, 0, 100) / 100
	-- menos vida: menos cor e mais escuro (a correção global de -0,1 fica no Lighting)
	cc.Saturation = -0.9 * (1 - h)
	cc.Brightness = -0.25 * (1 - h)
	local now = os.clock() - (state.recvAt or os.clock()) + (state.now or 0)
	local blurred = state.downedAt ~= nil or (state.blurUntil or 0) > now
	blur.Size = if state.downedAt then 18 elseif blurred then 8 else 0
end)

player.CharacterAdded:Connect(function()
	state = nil
end)
