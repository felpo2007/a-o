--!strict
-- Inicialização do servidor: remotes, dados, monetização e o loop central da F2.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
Net.server()

local Modules = ServerScriptService:WaitForChild("Modules")
local PlayerData = require(Modules:WaitForChild("PlayerData"))
local CommerceService = require(Modules:WaitForChild("CommerceService"))
local PrivateServer = require(Modules:WaitForChild("PrivateServer"))
local TeamService = require(Modules:WaitForChild("TeamService"))
local MatchService = require(Modules:WaitForChild("MatchService"))
local MedicalService = require(Modules:WaitForChild("MedicalService"))
local SpawnService = require(Modules:WaitForChild("SpawnService"))
local CombatService = require(Modules:WaitForChild("CombatService"))
local BotService = require(Modules:WaitForChild("BotService"))
local LightingService = require(Modules:WaitForChild("LightingService"))
local PostureService = require(Modules:WaitForChild("PostureService"))
local TunnelService = require(Modules:WaitForChild("TunnelService"))
local AssetLoader = require(Modules:WaitForChild("AssetLoader"))
local TerrainRuntime = require(Modules:WaitForChild("TerrainRuntime"))
local LogisticsService = require(Modules:WaitForChild("LogisticsService"))
local CommanderService = require(Modules:WaitForChild("CommanderService"))
local VehicleService = require(Modules:WaitForChild("VehicleService"))
local FieldService = require(Modules:WaitForChild("FieldService"))
local TrainingService = require(Modules:WaitForChild("TrainingService"))

task.spawn(TerrainRuntime.start) -- gera o terreno se o place veio sem ele
PlayerData.start()
CommerceService.start()
TeamService.start()
MatchService.start()
MedicalService.start()
SpawnService.start()
CombatService.start()
LightingService.start()
PostureService.start()
TunnelService.start()
task.spawn(AssetLoader.start) -- troca placeholders por modelos publicados (se houver IDs)
BotService.start()
LogisticsService.start() -- F4: suprimento, caixotes e construções
CommanderService.start() -- F4: comandante e missões de fogo por grade
VehicleService.start() -- F4: M48A3, Ontos, LVTP-5 e UH-34D
FieldService.start() -- Parte 12: configurações de controle, marcações, mensagens, granadas e corpo a corpo
TrainingService.start() -- F6: campo de tiro e tutorial por papel
PrivateServer.start(function(mode: string, clock: number)
	MatchService.requestMode(mode)
	LightingService.setStart(clock)
end)
print("[VT65] servidor pronto")
