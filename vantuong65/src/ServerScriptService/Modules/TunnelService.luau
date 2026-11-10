--!strict
-- Túneis do VC sob An Cường (2) (Parte 4): entrada = spawn oculto do VC SÓ se o setor é do VC;
-- engenheiro dos EUA destrói a entrada com carga (segurar 8 s no ProximityPrompt).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Geometry = require(ReplicatedStorage.Shared.Geometry)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Tunnels = require(ReplicatedStorage.Shared.Tunnels) :: any

local TunnelService = {}
TunnelService.destroyed = {} :: { [string]: boolean }

export type Entrance = { id: string, x: number, z: number, sector: number? }

local function center(): (number, number)
	for _, l in MapConfig.Locations do
		if l.name == "An Cường (2)" then
			return l.x, l.z
		end
	end
	return 0, 0
end

function TunnelService.entrances(): { Entrance }
	local cx, cz = center()
	local out = {}
	for id, n in Tunnels.nodes do
		if n.entrance then
			local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
			table.insert(out, { id = id, x = x, z = z, sector = Geometry.sectorAt(MapConfig.Sectors, x, z) })
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

local function collapse(id: string, part: BasePart)
	TunnelService.destroyed[id] = true
	part:SetAttribute("Destroyed", true)
	local plug = Instance.new("Part")
	plug.Name = "Collapsed_" .. id
	plug.Anchored = true
	plug.Size = Vector3.new(5, 12, 5)
	plug.CFrame = part.CFrame * CFrame.new(0, -6, 0)
	plug.Material = Enum.Material.Ground
	plug.Color = Color3.fromRGB(90, 72, 50)
	plug.Parent = part.Parent
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt:Destroy()
	end
end

function TunnelService.start()
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Tunnels")
	if not folder then
		warn("[VT65] sem Map.Tunnels: rode o build de feições")
		return
	end
	for _, p in folder:GetChildren() do
		local id = p:GetAttribute("TunnelEntrance")
		if p:IsA("BasePart") and type(id) == "string" then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Destruir entrada (carga)"
			prompt.ObjectText = "Túnel"
			prompt.HoldDuration = 8
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = p
			prompt.Triggered:Connect(function(player: Player)
				-- só engenheiro dos EUA (a carga é placeholder até os explosivos da F4)
				if player:GetAttribute("Faction") == "US" and player:GetAttribute("Role") == "engineer" then
					collapse(id, p)
				end
			end)
		end
	end
	local _ = Players
end

return TunnelService
