--!strict
-- Túneis do VC sob An Cường (2) (Parte 4): entrada = spawn oculto do VC SÓ se o setor é do VC;
-- engenheiro dos EUA destrói a entrada com carga (segurar 8 s no ProximityPrompt).
-- D-90 (regra do dono, 2026-11-11: só o VC usa túneis e passagens): o poço é um buraco aberto e
-- qualquer um caía nele; agora quem é dos EUA (jogador ou bot) que entra no poço ou no túnel é posto
-- de volta na superfície, ao lado da boca mais perto. A granada continua caindo pelo poço.
-- `TunnelService.links()`: qual boca leva a qual (Shared/TunnelLinks), para a carta do VC.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Geometry = require(ReplicatedStorage.Shared.Geometry)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local TunnelLinks = require(ReplicatedStorage.Shared.TunnelLinks)
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

export type LinkInfo = {
	id: string, -- boca de origem
	x: number, -- studs, no quadro do jogo
	z: number,
	open: boolean, -- não destruída
	to: { { id: string, x: number, z: number, lengthM: number, via: { string } } },
}

-- Qual boca leva a qual, no quadro do jogo (studs), com o comprimento lá embaixo (m) e os nós do
-- caminho. Bocas destruídas pelo engenheiro ficam fora das ligações. Pura (só lê os dados).
function TunnelService.links(): { LinkInfo }
	local cx, cz = center()
	local closed: { [string]: boolean } = {}
	for id, v in TunnelService.destroyed do
		if v then
			closed[id] = true
		end
	end
	local all = TunnelLinks.links(closed)
	local out: { LinkInfo } = {}
	for _, e in TunnelLinks.entrances() do
		local x, z = Tunnels.toWorld(cx, cz, e.x, e.z)
		local to = {}
		local links = all[e.id]
		if links then
			for _, l in links do
				local n = Tunnels.nodes[l.to]
				local tx, tz = Tunnels.toWorld(cx, cz, n.x, n.z)
				table.insert(to, { id = l.to, x = tx, z = tz, lengthM = l.lengthM, via = l.via })
			end
		end
		table.insert(out, { id = e.id, x = x, z = z, open = not closed[e.id], to = to })
	end
	return out
end

-- ===== só o VC entra (D-90) =====
local M = 0.28
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include

local function surfaceY(x: number, z: number): number?
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), terrainParams)
	return if hit then hit.Position.Y else nil
end

-- distância horizontal (studs) de (x, z) ao segmento
local function segDist(x: number, z: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local l2 = dx * dx + dz * dz
	local t = if l2 > 1e-6 then math.clamp(((x - ax) * dx + (z - az) * dz) / l2, 0, 1) else 0
	return math.sqrt((x - ax - dx * t) ^ 2 + (z - az - dz * t) ^ 2)
end

-- Altura do chão sobre cada nó: na boca, a placa da entrada; na junção, um raio (o terreno acima da
-- câmara continua lá). No poço o raio desceria pelo buraco, por isso não se mede no lugar do soldado.
local nodeTop: { [string]: number } = {}
local function topOf(id: string): number?
	local t = nodeTop[id]
	if t then
		return t
	end
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Tunnels")
	for _, p in if folder then folder:GetChildren() else {} do
		if p:IsA("BasePart") and p:GetAttribute("TunnelEntrance") == id then
			nodeTop[id] = p.Position.Y - 0.1
			return nodeTop[id]
		end
	end
	local cx, cz = center()
	local n = Tunnels.nodes[id]
	local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
	local y = surfaceY(x, z)
	if y then
		nodeTop[id] = y
	end
	return y
end

-- Está dentro da rede (bem abaixo do chão, sobre o traçado ou no poço)?
local function insideTunnel(pos: Vector3): boolean
	local cx, cz = center()
	for _, e in Tunnels.edges do
		local a, b = Tunnels.nodes[e[1]], Tunnels.nodes[e[2]]
		local ax, az = Tunnels.toWorld(cx, cz, a.x, a.z)
		local bx, bz = Tunnels.toWorld(cx, cz, b.x, b.z)
		if segDist(pos.X, pos.Z, ax, az, bx, bz) <= Tunnels.WIDTH_M / M / 2 + 2 then
			local ta, tb = topOf(e[1]), topOf(e[2])
			if ta and tb then
				local dx, dz = bx - ax, bz - az
				local l2 = dx * dx + dz * dz
				local t = if l2 > 1e-6 then math.clamp(((pos.X - ax) * dx + (pos.Z - az) * dz) / l2, 0, 1) else 0
				-- o piso do túnel fica 10,7 studs abaixo do chão (a raiz, a ~9); deitado na trincheira
				-- sul (1,5 m, onde fica a E5) a raiz fica a ~4: o corte em 6,5 não pega a trincheira
				if pos.Y < ta + (tb - ta) * t - 6.5 then
					return true
				end
			end
		end
	end
	return false
end

local function eject(model: Model, pos: Vector3)
	local best: Entrance? = nil
	local bestD = math.huge
	for _, en in TunnelService.entrances() do
		local d = (Vector3.new(en.x, 0, en.z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
		if d < bestD then
			best, bestD = en, d
		end
	end
	if not best then
		return
	end
	local a = math.random() * 2 * math.pi
	local x, z = best.x + math.cos(a) * 3 / M, best.z + math.sin(a) * 3 / M
	local y = surfaceY(x, z) or pos.Y
	model:PivotTo(CFrame.new(x, y + 4, z))
	print(string.format("[VT65] túnel: %s é dos EUA e foi posto de volta na boca %s", model.Name, best.id))
end

local function guard()
	local cx, cz = center()
	local reach = 0
	for _, n in Tunnels.nodes do
		reach = math.max(reach, math.sqrt(n.x * n.x + n.z * n.z))
	end
	local reachStuds = reach / M + 20
	local function check(model: Model?)
		local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (model and root) or root.Anchored then
			return
		end
		local p = root.Position
		if (Vector3.new(p.X - cx, 0, p.Z - cz)).Magnitude > reachStuds then
			return
		end
		if insideTunnel(p) then
			eject(model, p)
		end
	end
	while true do
		task.wait(0.3)
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("Faction") == "US" then
				check(p.Character)
			end
		end
		local folder = workspace:FindFirstChild("Combatants")
		for _, m in if folder then folder:GetChildren() else {} do
			if m:IsA("Model") and m:GetAttribute("Faction") == "US" then
				check(m)
			end
		end
	end
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
	task.spawn(guard) -- só o VC entra (D-90)
end

return TunnelService
