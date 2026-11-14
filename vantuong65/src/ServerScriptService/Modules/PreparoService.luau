--!strict
-- Contagem do começo da partida (D-122, pedido do dono: "a partida deve começar com cada um na sua base
-- com uma contagem regressiva; depois a partida começa e os jogadores vão dominar os pontos").
-- Enquanto MatchService.inPrep() (os PREP_S do começo de cada partida):
--   - todo ponto de nascer fora do QG fica bloqueado (reunião, squad, "renascer aqui"): o
--     SpawnService.addBlocker vale para todos eles;
--   - quem passa de BASE_M do QG do seu lado volta para a borda da base (jogadores e bots; os bots
--     também ficam parados no BotService). O carro do QG fica onde está;
--   - a tela mostra a contagem (Controllers/Contagem, pelo Match_State.prep).
-- Lote 22 (dono: "faça de 10 seg a contagem regressiva onde os jogadores podem pegar os veículos etc,
-- porém não podem sair da base"): a contagem caiu para 10 s (MatchService.PREP_S) e o veículo também
-- fica preso: passou do raio com gente dentro, volta para a borda de frente para o QG, parado, com
-- quem está sentado. Quem é puxado de volta (a pé ou no veículo) ganha +1 no atributo PrepVolta do
-- Player, e a contagem na tela avisa "Não saia da base!".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local SpawnService = require(script.Parent.SpawnService) :: any

local PreparoService = {}

local M = MapConfig.STUD_M
PreparoService.BASE_M = 60 -- raio da base na contagem (a clareira do QG dos EUA tem 80 m)
PreparoService.VEHICLE_IN_M = 6 -- o veículo volta para dentro do raio com esta folga (o casco é longo)
PreparoService.BLOCK_WHY = "Na contagem, todos nascem na base"

local started = false

local function avisar(model: Model)
	local p = Players:GetPlayerFromCharacter(model)
	if p then
		p:SetAttribute("PrepVolta", (p:GetAttribute("PrepVolta") or 0) + 1)
	end
end

-- o veículo (modelo com VehicleId) do assento
local function vehicleOf(seat: Instance): Model?
	local m = seat:FindFirstAncestorWhichIsA("Model")
	while m and not m:GetAttribute("VehicleId") do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return m
end

-- volta para a borda da base o veículo que passou do raio, com quem está dentro
local function leashVehicle(v: Model, hq: any, r: number): boolean
	local chassis = v:FindFirstChild("Chassis")
	if not (chassis and chassis:IsA("BasePart")) or chassis.Anchored then
		return false
	end
	local p = chassis.Position
	local dx, dz = p.X - hq.x, p.Z - hq.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= r then
		return false
	end
	local k = (r - PreparoService.VEHICLE_IN_M / M) / d
	local x, z = hq.x + dx * k, hq.z + dz * k
	-- a mesma altura sobre o chão (no chão, o carro; no ar, o helicóptero)
	local above = p.Y - SpawnService.groundY(p.X, p.Z)
	local y = SpawnService.groundY(x, z) + math.max(above, 0) + 0.5
	-- frente do chassi = -Z: o lookAt deixa o veículo de frente para o QG
	local cf = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(hq.x, y, hq.z))
	v:PivotTo(cf * chassis.CFrame:ToObjectSpace(v:GetPivot()))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	return true
end

-- volta para a borda da base quem passou do raio (devolve quantos voltaram)
function PreparoService.leash(): number
	local n = 0
	local r = PreparoService.BASE_M / M
	local done: { [Model]: boolean } = {}
	for _, e in Combatants.list() do
		local hq = MapConfig.HQ[e.faction]
		local root = Combatants.root(e)
		local hum = Combatants.humanoid(e)
		local seat = if hum then hum.SeatPart else nil
		if hq and root and Combatants.active(e) and seat then
			-- sentado num veículo: o veículo inteiro volta (mover só o corpo soltaria o assento)
			local v = vehicleOf(seat)
			if v and not done[v] then
				done[v] = true
				if leashVehicle(v, hq, r) then
					n += 1
					for _, s in v:GetDescendants() do
						if s:IsA("VehicleSeat") or s:IsA("Seat") then
							local occ = s.Occupant
							if occ and occ.Parent and occ.Parent:IsA("Model") then
								avisar(occ.Parent :: Model)
							end
						end
					end
				end
			end
		elseif hq and root and Combatants.active(e) and not root.Anchored then
			local dx, dz = root.Position.X - hq.x, root.Position.Z - hq.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > r then
				local k = (r - 2 / M) / d
				local x, z = hq.x + dx * k, hq.z + dz * k
				local pos = Vector3.new(x, SpawnService.groundY(x, z) + 3, z)
				-- de frente para o QG
				e.model:PivotTo(CFrame.lookAt(pos, Vector3.new(hq.x, pos.Y, hq.z)))
				root.AssemblyLinearVelocity = Vector3.zero
				avisar(e.model)
				n += 1
			end
		end
	end
	return n
end

function PreparoService.start()
	if started then
		return
	end
	started = true
	SpawnService.addBlocker(function(_x: number, _z: number, _faction: string): string?
		if MatchService.inPrep() then
			return PreparoService.BLOCK_WHY
		end
		return nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if MatchService.inPrep() then
				PreparoService.leash()
			end
		end
	end)
end

return PreparoService
