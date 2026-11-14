--!strict
-- MapService: limites da área de combate (servidor autoritativo).
-- Fora da área: aviso no cliente (atributo "OOBSecondsLeft") e morte após 10 s (prompt, Parte 3).
-- Também publica o setor atual do jogador (atributo "Sector") para o HUD de depuração da F1.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Geometry = require(ReplicatedStorage.Shared.Geometry)

local TICK = 0.25
local outSince: { [Player]: number } = {}

local function step()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (root and hum and hum.Health > 0) then
			outSince[player] = nil
			player:SetAttribute("OOBSecondsLeft", nil)
			continue
		end
		local p = root.Position
		player:SetAttribute("Sector", Geometry.sectorAt(MapConfig.Sectors, p.X, p.Z))
		if Geometry.inBounds(MapConfig.Bounds, p.X, p.Z) then
			outSince[player] = nil
			player:SetAttribute("OOBSecondsLeft", nil)
		else
			local t0 = outSince[player] or now
			outSince[player] = t0
			local left = MapConfig.OutOfBoundsKillSeconds - (now - t0)
			player:SetAttribute("OOBSecondsLeft", math.max(0, math.ceil(left)))
			if left <= 0 then
				hum.Health = 0
				outSince[player] = nil
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(p)
	outSince[p] = nil
end)

while true do
	step()
	task.wait(TICK)
end
