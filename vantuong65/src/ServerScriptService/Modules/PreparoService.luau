--!strict
-- Contagem do começo da partida (D-122, pedido do dono: "a partida deve começar com cada um na sua base
-- com uma contagem regressiva; depois a partida começa e os jogadores vão dominar os pontos").
-- Enquanto MatchService.inPrep() (os PREP_S do começo de cada partida):
--   - todo ponto de nascer fora do QG fica bloqueado (reunião, squad, "renascer aqui"): o
--     SpawnService.addBlocker vale para todos eles;
--   - quem passa de BASE_M do QG do seu lado volta para a borda da base (jogadores e bots; os bots
--     também ficam parados no BotService). O carro do QG fica onde está;
--   - a tela mostra a contagem (Controllers/Contagem, pelo Match_State.prep).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local SpawnService = require(script.Parent.SpawnService) :: any

local PreparoService = {}

local M = MapConfig.STUD_M
PreparoService.BASE_M = 60 -- raio da base na contagem (a clareira do QG dos EUA tem 80 m)
PreparoService.BLOCK_WHY = "Na contagem, todos nascem na base"

local started = false

-- volta para a borda da base quem passou do raio (devolve quantos voltaram)
function PreparoService.leash(): number
	local n = 0
	local r = PreparoService.BASE_M / M
	for _, e in Combatants.list() do
		local hq = MapConfig.HQ[e.faction]
		local root = Combatants.root(e)
		local hum = Combatants.humanoid(e)
		-- sentado num veículo: fica (mover o corpo soltaria o assento)
		local seated = hum ~= nil and hum.SeatPart ~= nil
		if hq and root and Combatants.active(e) and not root.Anchored and not seated then
			local dx, dz = root.Position.X - hq.x, root.Position.Z - hq.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > r then
				local k = (r - 2 / M) / d
				local x, z = hq.x + dx * k, hq.z + dz * k
				local pos = Vector3.new(x, SpawnService.groundY(x, z) + 3, z)
				-- de frente para o QG
				e.model:PivotTo(CFrame.lookAt(pos, Vector3.new(hq.x, pos.Y, hq.z)))
				root.AssemblyLinearVelocity = Vector3.zero
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
