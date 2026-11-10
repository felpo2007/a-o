--!strict
-- Campo de tiro e tutorial por papel (Parte 9, "Aprendizado"; F6, D-47).
-- Campo de tiro: na retaguarda de cada QG, linha de tiro e alvos de silhueta a 100, 200 e 300 m,
-- no chão real do terreno. Acerto num alvo avisa SÓ o atirador (o jogo não tem hitmarker; o campo
-- de tiro é a exceção, para ensinar alça e queda).
-- Tutorial: o perfil guarda os papéis concluídos (ProfileSchema.tutorial).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local PlayerData = require(script.Parent.PlayerData)

local TrainingService = {}
local M = 0.28
local last: { [Player]: number } = {}

local function groundY(x: number, z: number, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return if hit then hit.Position.Y else 0
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Wood
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(board: BasePart, text: string)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.CanvasSize = Vector2.new(400, 200)
	g.Parent = board
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(30, 28, 22)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = text
	l.Parent = g
end

-- Limpa a raia: raios da linha de tiro até o centro de cada alvo (deitado, ajoelhado e em pé, e
-- 25 cm para cada lado); peça do greybox no caminho (sebe, dique, casa) sai. O terreno não dá
-- para tirar: se ele bloquear, avisa no Output. No teste do Studio (2026-11-10) uma sebe de
-- arrozal a 21 m tapava o alvo de 100 m dos EUA.
local function clearLane(folder: Instance, from: Vector3, look: CFrame, plates: { BasePart })
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	local removed, blocked = 0, 0
	for _, plate in plates do
		for _, h in { 0.4, 1.0, 1.5 } do
			for _, side in { -0.25, 0, 0.25 } do
				local o = from + Vector3.new(0, h / M, 0) + look.RightVector * (side / M)
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				local ignore: { Instance } = { folder }
				params.FilterDescendantsInstances = ignore
				for _ = 1, 12 do
					local r = workspace:Raycast(o, plate.Position - o, params)
					if not r then
						break
					end
					if r.Instance:IsDescendantOf(map) then
						r.Instance:Destroy()
						removed += 1
					else
						if r.Instance == workspace.Terrain then
							blocked += 1
						end
						break
					end
				end
			end
		end
	end
	if removed > 0 or blocked > 0 then
		print(
			string.format(
				"[VT65] raia %s: %d peças removidas; %d raios barrados pelo terreno",
				folder.Name,
				removed,
				blocked
			)
		)
	end
end

-- Constrói o campo de tiro de uma facção. Devolve a pasta.
local function buildRange(faction: string, folder: Folder)
	local hq = MapConfig.HQ[faction]
	local lane = Tutorial.RANGE_LANE[faction]
	if not (hq and lane) then
		return
	end
	local dx, dz = lane.dir[1], lane.dir[2]
	local x0 = hq.x + lane.offsetM[1] / M
	local z0 = hq.z + lane.offsetM[2] / M
	local ignore: { Instance } = { folder }
	-- linha de tiro: barra baixa de madeira com a placa voltada para o atirador
	local y0 = groundY(x0, z0, ignore)
	local look = CFrame.lookAt(Vector3.new(x0, y0, z0), Vector3.new(x0 + dx, y0, z0 + dz))
	part(
		folder,
		"LinhaDeTiro",
		Vector3.new(4 / M, 0.5 / M, 0.3 / M),
		look * CFrame.new(0, 0.25 / M, 0),
		Color3.fromRGB(110, 86, 58)
	)
	local board = part(
		folder,
		"PlacaLinha",
		Vector3.new(1.6 / M, 0.8 / M, 0.05 / M),
		look * CFrame.new(-2.6 / M, 1.2 / M, 0) * CFrame.Angles(0, math.pi, 0),
		Color3.fromRGB(214, 203, 170)
	)
	sign(board, "LINHA DE TIRO\nalvos a 100, 200 e 300 m")
	local plates: { BasePart } = {}
	for _, m in Tutorial.RANGE_M do
		local x, z = x0 + dx * m / M, z0 + dz * m / M
		local y = groundY(x, z, ignore)
		local base = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x0, y, z0)) -- frente para o atirador
		part(
			folder,
			"Poste",
			Vector3.new(0.08 / M, 1.7 / M, 0.08 / M),
			base * CFrame.new(0, 0.85 / M, 0.05 / M),
			Color3.fromRGB(90, 70, 48)
		)
		-- silhueta de 0,5 x 1,0 m (meio corpo) a 0,7 m do chão; o centro é marcado
		local plate = part(
			folder,
			"Alvo" .. m,
			Vector3.new(0.5 / M, 1.0 / M, 0.03 / M),
			base * CFrame.new(0, 1.2 / M, 0),
			Color3.fromRGB(196, 182, 140)
		)
		plate.Material = Enum.Material.Cardboard
		plate:SetAttribute("RangeTarget", m)
		table.insert(plates, plate)
		local dot = part(
			folder,
			"Centro" .. m,
			Vector3.new(0.1 / M, 0.1 / M, 0.01 / M),
			plate.CFrame * CFrame.new(0, 0, -0.02 / M),
			Color3.fromRGB(30, 28, 22)
		)
		dot.CanCollide = false
		dot.CanQuery = false
		local tag = part(
			folder,
			"Placa" .. m,
			Vector3.new(0.6 / M, 0.3 / M, 0.04 / M),
			base * CFrame.new(0, 0.35 / M, 0) * CFrame.Angles(0, math.pi, 0),
			Color3.fromRGB(214, 203, 170)
		)
		tag.CanQuery = false
		sign(tag, m .. " m")
	end
	clearLane(folder, Vector3.new(x0, y0, z0), look, plates)
end

-- Chamado pelo CombatService quando um tiro para numa peça com RangeTarget.
-- hitPos em studs. Só o atirador recebe: distância do alvo e desvio do centro (cm).
function TrainingService.rangeHit(shooter: Model, target: BasePart, hitPos: Vector3)
	local player = Players:GetPlayerFromCharacter(shooter)
	local dist = target:GetAttribute("RangeTarget")
	if not player or type(dist) ~= "number" then
		return
	end
	local rel = target.CFrame:PointToObjectSpace(hitPos)
	-- o alvo olha para o atirador: o +X dele é a esquerda de quem atira
	Net.event("Range_Hit"):FireClient(player, { dist = dist, right = -rel.X * M * 100, up = rel.Y * M * 100 })
end

-- Diagnóstico só no Studio: tiro que parou perto de um alvo sem acertar mostra por quanto errou
-- (horizontal e vertical, em cm, do ponto de vista de quem atira) e no que bateu.
function TrainingService.nearMiss(shooter: Model, hitPos: Vector3, what: Instance?)
	if not RunService:IsStudio() or not Players:GetPlayerFromCharacter(shooter) then
		return
	end
	local range = workspace:FindFirstChild("CampoDeTiro")
	if not range then
		return
	end
	for _, d in range:GetDescendants() do
		local dist = d:GetAttribute("RangeTarget")
		if d:IsA("BasePart") and type(dist) == "number" and (d.Position - hitPos).Magnitude < 40 / M then
			local rel = d.CFrame:PointToObjectSpace(hitPos)
			print(
				string.format(
					"[VT65] campo de tiro: errou o alvo de %d m — %+.0f cm na horizontal, %+.0f cm na vertical; parou em %s",
					dist,
					-rel.X * M * 100,
					rel.Y * M * 100,
					if what then what:GetFullName() else "?"
				)
			)
			return
		end
	end
end

function TrainingService.start()
	Net.func("Tutorial_Get").OnServerInvoke = function(p: Player)
		local prof = PlayerData.get(p)
		return Tutorial.sanitize(prof and prof.tutorial, Roles.roles)
	end
	Net.event("Tutorial_Done").OnServerEvent:Connect(function(p: Player, role: any)
		local prof = PlayerData.get(p)
		local now = os.clock()
		if not prof or type(role) ~= "string" or not Roles.roles[role] or (last[p] or 0) > now - 2 then
			return
		end
		last[p] = now
		prof.tutorial = Tutorial.sanitize(prof.tutorial, Roles.roles)
		prof.tutorial[role] = true
	end)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
	task.spawn(function()
		while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
			task.wait(1)
		end
		local folder = Instance.new("Folder")
		folder.Name = "CampoDeTiro"
		folder.Parent = workspace
		for _, f in { "US", "VC" } do
			local sub = Instance.new("Folder")
			sub.Name = f
			sub.Parent = folder
			buildRange(f, sub)
		end
		print("[VT65] campos de tiro prontos (100, 200 e 300 m ao lado de cada QG)")
	end)
end

return TrainingService
