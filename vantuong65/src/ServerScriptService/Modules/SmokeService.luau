--!strict
-- Nuvem da granada de fumaça no servidor (2026-11-13, "copie a granada de fumaça igual ao Front 44 e
-- corrija seus defeitos"). Só o ESTADO: um modelo "Nuvem" na pasta workspace.Smoke, Persistent (vai
-- a todos os clientes, também a quem entra depois), com a hora do começo ("T0"), a duração ("Dur") e
-- os 7 sopros (Attachments "Sopro*" na peça "Centro", raio em "R"). Os bots e a assistência de mira
-- leem pelo Shared/Smoke (a visão cresce e afina com a nuvem); cada cliente desenha
-- (Controllers/Fumaca.client). Paredes e teto encurtam os sopros (Smoke.layout): a fumaça não tapa
-- a visão do outro lado de uma parede.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Smoke = require(ReplicatedStorage.Shared.Smoke)

local SmokeService = {}
local M = 0.28

local function folder(): Instance
	local f = workspace:FindFirstChild("Smoke")
	if f then
		return f
	end
	local n = Instance.new("Folder")
	n.Name = "Smoke"
	n.Parent = workspace
	return n
end

-- o que não é parede: gente, granadas, armas no chão, efeitos e as próprias nuvens
local function ignoreList(): { Instance }
	local out: { Instance } = {}
	for _, name in { "Smoke", "Granadas", "DroppedWeapons", "Combatants", "VT65Effects", "VT65Explosoes" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(out, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(out, p.Character)
		end
	end
	return out
end

-- Abre a nuvem com a lata em pos (by: quem lançou). Devolve o modelo.
function SmokeService.spawn(pos: Vector3, by: Player?): Model
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList()
	params.RespectCanCollide = true -- folhagem sem colisão não corta a fumaça
	params.IgnoreWater = true
	local R = Smoke.RADIUS_M / M
	local ground = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -5, 0), params)
	local base = if ground then ground.Position else pos
	local from = base + Vector3.new(0, Smoke.HEIGHT_M / M, 0)
	local walls: { Smoke.Wall? } = {}
	for i = 1, Smoke.RING do
		local dx, dz = Smoke.ringDir(i)
		local hit = workspace:Raycast(from, Vector3.new(dx, 0, dz) * R, params)
		-- parede: normal quase deitada (chão em rampa não conta) e não é planta (o tronco de uma árvore
		-- viraria um plano infinito cortando a nuvem; AssetLoader marca as plantas com "Foliage")
		local model = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
		if hit and math.abs(hit.Normal.Y) < 0.7 and not (model and model:GetAttribute("Foliage") == true) then
			walls[i] = { d = (hit.Position - from).Magnitude, nx = hit.Normal.X, nz = hit.Normal.Z }
		end
	end
	local up = workspace:Raycast(base + Vector3.new(0, 0.3, 0), Vector3.new(0, R, 0), params)
	local ceiling = if up then (up.Position - base).Magnitude else nil
	local m = Instance.new("Model")
	m.Name = "Nuvem"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local c = Instance.new("Part")
	c.Name = "Centro"
	c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
	c.Transparency = 1
	c.Size = Vector3.one
	c.CFrame = CFrame.new(base)
	c.Parent = m
	m.PrimaryPart = c
	for i, p in Smoke.layout(R, walls, ceiling) do
		local a = Instance.new("Attachment")
		a.Name = "Sopro" .. i
		a.Position = Vector3.new(p.x, p.y, p.z)
		a:SetAttribute("R", p.r)
		a.Parent = c
	end
	m:SetAttribute("T0", workspace:GetServerTimeNow())
	m:SetAttribute("Dur", Smoke.DURATION_S)
	m:SetAttribute("R", R)
	if by then
		m:SetAttribute("Owner", by.UserId)
	end
	m.Parent = folder()
	-- a visão já abriu (factor = 0 depois de Dur); o modelo fica um pouco para o desenho sumir
	task.delay(Smoke.DURATION_S + 3, function()
		m:Destroy()
	end)
	return m
end

return SmokeService
