--!strict
-- Explosões no servidor (F4): ferimentos por distância, postura e cobertura (Shared/Explosive),
-- dano a veículos, cratera no terreno com orçamento por minuto e efeito para os clientes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Explosive = require(ReplicatedStorage.Shared.Explosive)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local VeiculoDano = require(ReplicatedStorage.Shared.VeiculoDano)
local AnimalService = require(script.Parent.AnimalService)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local MedicalService = require(script.Parent.MedicalService)

local ExplosionService = {}
local M = 0.28
local budget = Explosive.newBudget(20)
local rng = Rng.new(651818)

-- gancho para veículos (VehicleService registra; evita dependência circular)
ExplosionService.onVehicles = nil :: ((pos: Vector3, id: string) -> ())?

-- D-193: o terreno de antes de cada cratera, para a partida nova devolver (do último ao primeiro)
-- D-203 (§22): também o capim que vira terra (napalm, caixa de munição: ExplosionService.guardar)
type Cratera = { region: Region3, mats: any, occs: any }
local crateras: { Cratera } = {}

-- Guarda o terreno da região (já no grid de 4) antes de mudar; a partida nova devolve.
function ExplosionService.guardar(region: Region3)
	local mats, occs = workspace.Terrain:ReadVoxels(region, 4)
	table.insert(crateras, { region = region, mats = mats, occs = occs })
end

function ExplosionService.restaurar(): number
	local n = #crateras
	for i = n, 1, -1 do
		local c = crateras[i]
		pcall(function()
			workspace.Terrain:WriteVoxels(c.region, 4, c.mats, c.occs)
		end)
	end
	table.clear(crateras)
	return n
end

local function covered(from: Vector3, model: Model, target: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { model }
	local fx = workspace:FindFirstChild("Effects")
	if fx then
		table.insert(ignore, fx)
	end
	params.FilterDescendantsInstances = ignore
	local dir = target - from
	local hit = workspace:Raycast(from, dir, params)
	return hit ~= nil and (hit.Position - from).Magnitude < dir.Magnitude - 0.5
end

local ZONES = { "torso", "torso", "arm", "leg", "leg", "head" }

-- ===== incendiário (2026-11-12): napalm do ataque aéreo =====
-- ExplosionService.ignite(pos, heading?, by?, id?): mancha de fogo em elipse no chão ao longo do rumo
-- do avião (Explosive.TYPES[id].burn; padrão "napalm"), que queima durationS. Também sai de
-- ExplosionService.detonate("napalm", pos, by) (rumo padrão: −Z). Para quem está na mancha:
-- queimadura na 1ª vez e queda com lethalS de exposição (Explosive.burnStep), a cada 0,25 s.
-- Visual para todos: fogo (Fire), fumaça preta (Smoke) e luz em 7 pontos da mancha. O chão
-- chamusca: capim do terreno vira terra (Terrain:ReplaceMaterial), sem mexer no relevo nem nas
-- peças do mapa, no máximo 6 manchas por minuto. D-203: o capim volta na partida nova e o fogo
-- apaga no fim da partida.
local burnBudget = Explosive.newBudget(6)
function ExplosionService.ignite(pos: Vector3, heading: Vector3?, by: Player?, id: string?, from: string?)
	local t = Explosive.TYPES[id or "napalm"]
	local b = t and t.burn
	if not b then
		return
	end
	local flat = if heading then Vector3.new(heading.X, 0, heading.Z) else Vector3.zero
	local h = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local side = Vector3.new(-h.Z, 0, h.X)
	local folder = Instance.new("Folder")
	folder.Name = "Napalm"
	folder.Parent = workspace
	local lights: { Instance } = {}
	local n = 7
	for i = 1, n do
		local f = (i - 1) / (n - 1) - 0.5
		local spot = pos
			+ h * (f * b.lengthM * 0.85 / M)
			+ side * ((rng:next() - 0.5) * b.widthM * 0.5 / M)
			+ Vector3.new(0, 0.5 / M, 0)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = Vector3.one
		p.Position = spot
		local fire = Instance.new("Fire")
		fire.Size = 22
		fire.Heat = 18
		fire.Color = Color3.fromRGB(255, 140, 40)
		fire.SecondaryColor = Color3.fromRGB(120, 30, 10)
		fire.Parent = p
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(18, 16, 14)
		smoke.Opacity = 0.55
		smoke.RiseVelocity = 14
		smoke.Size = 60
		smoke.Parent = p
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 70)
		light.Brightness = 3
		light.Range = 40
		light.Parent = p
		table.insert(lights, fire)
		table.insert(lights, light)
		p.Parent = folder
	end
	AnimalService.noise(pos, true)
	-- chão chamuscado: faixas ao longo da mancha (o capim do terreno vira terra)
	if Explosive.allowCrater(burnBudget, os.clock()) then
		pcall(function()
			for i = -2, 2 do
				local c = pos + h * (i / 5 * b.lengthM / M)
				local ext = Vector3.new(b.widthM / 2, 3, b.widthM / 2) / M
				local region = Region3.new(c - ext, c + ext):ExpandToGrid(4)
				ExplosionService.guardar(region) -- D-203: o capim volta na partida nova
				for _, mat in { Enum.Material.Grass, Enum.Material.LeafyGrass } do
					workspace.Terrain:ReplaceMaterial(region, 4, mat, Enum.Material.Ground)
				end
			end
		end)
	end
	-- D-203 (§22): o fogo é desta partida; apaga no fim (e a restauração tira a pasta)
	local rodada = MatchService.rodada
	task.spawn(function()
		local exposed: { [Model]: number } = {}
		local done: { [Model]: string } = {}
		local t0 = os.clock()
		while os.clock() - t0 < b.durationS and folder.Parent do
			local dt = task.wait(0.25)
			if MatchService.rodada ~= rodada or MatchService.ended then
				break
			end
			for _, e in Combatants.list() do
				local root = Combatants.root(e)
				local model = e.model
				if root and model and not VeiculoDano.naBlindagem(Combatants.humanoid(e)) then
					local d = (root.Position - pos) * M
					local zone = if math.abs(d.Y) < 4 then Explosive.burnAt(b, d.X, d.Z, h.X, h.Z) else nil
					if zone == "core" then
						exposed[model] = (exposed[model] or 0) + dt
					end
					local what = Explosive.burnStep(b, zone, exposed[model] or 0, done[model])
					if what == "lethal" then
						done[model] = "lethal"
						MedicalService.hit(model, "torso", 2000, rng:next(), by, from)
					elseif what == "burn" then
						done[model] = "burn"
						MedicalService.hit(
							model,
							ZONES[1 + math.floor(rng:next() * #ZONES)],
							b.burnJ,
							rng:next(),
							by,
							from
						)
					end
				end
			end
		end
		for _, x in lights do -- o fogo apaga; a fumaça ainda sobe um pouco
			if x:IsA("Fire") then
				x.Enabled = false
			elseif x:IsA("PointLight") then
				x.Enabled = false
			end
		end
		task.wait(8)
		folder:Destroy()
	end)
end

-- by: quem lançou (granada, morteiro pedido por jogador), para o abate e a assistência (D-72).
-- from: o lado de quem lançou (v41, sem fogo amigo); nil = de ninguém (destroço, armadilha)
function ExplosionService.detonate(id: string, pos: Vector3, by: Player?, from: string?)
	local t = Explosive.TYPES[id]
	if not t then
		return
	end
	Net.unreliable("Fire_Impact"):FireAllClients({ id = id, x = pos.X, y = pos.Y, z = pos.Z })
	AnimalService.noise(pos, true)
	if t.burn then
		ExplosionService.ignite(pos, nil, by, id, from)
		return
	end
	local origin = pos + Vector3.new(0, 1, 0)
	for _, e in Combatants.list() do
		local root = Combatants.root(e)
		-- D-246: o estilhaço também para no casco do blindado
		if root and not VeiculoDano.naBlindagem(Combatants.humanoid(e)) then
			local dM = (root.Position - pos).Magnitude * M
			if dM <= t.casualtyM then
				local exposure = if e.model:GetAttribute("Crouched") then Explosive.CROUCH else 1
				if covered(origin, e.model, root.Position) then
					exposure *= Explosive.COVERED
				end
				local result, energy = Explosive.effect(id, dM, exposure, rng:next())
				if result == "lethal" or result == "wound" then
					-- D-192: o golpe para a queda do corpo (CorposService), se este matar
					e.model:SetAttribute("VT65GolpeDe", pos)
					e.model:SetAttribute("VT65GolpeK", "explosao")
					e.model:SetAttribute("VT65GolpeDistM", dM)
					e.model:SetAttribute("VT65GolpeRaioM", t.impulsoM or t.casualtyM) -- D-198: o raio do empurrão
					e.model:SetAttribute("VT65GolpeT", os.clock())
				end
				-- colete M1955 (D-72, equipamento liberado): estilhaço no tronco perde energia
				local ff = e.player and e.player:GetAttribute("FragFactor")
				local vest = if type(ff) == "number" then math.clamp(ff, 0.1, 1) else 1
				if result == "lethal" then
					MedicalService.hit(e.model, "torso", energy * vest, rng:next(), by, from)
				elseif result == "wound" then
					local zone = ZONES[1 + math.floor(rng:next() * #ZONES)]
					local j = if zone == "torso" then energy * vest else energy
					MedicalService.hit(e.model, zone, j, rng:next(), by, from)
				end
			end
		end
	end
	if ExplosionService.onVehicles then
		ExplosionService.onVehicles(pos, id)
	end
	if t.craterM > 0 and Explosive.allowCrater(budget, os.clock()) then
		local terrain = workspace.Terrain
		local center = pos - Vector3.new(0, t.craterM * 0.4 / M, 0)
		local r = t.craterM / M
		pcall(function()
			-- D-193: guarda o terreno antes de abrir a cratera
			ExplosionService.guardar(
				Region3.new(center - Vector3.one * (r + 4), center + Vector3.one * (r + 4)):ExpandToGrid(4)
			)
			terrain:FillBall(center, r, Enum.Material.Air)
		end)
	end
end

return ExplosionService
