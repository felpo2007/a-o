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
local AnimalService = require(Modules:WaitForChild("AnimalService"))
local RadioService = require(Modules:WaitForChild("RadioService"))
local FieldWorkService = require(Modules:WaitForChild("FieldWorkService"))
local SelfTest = require(Modules:WaitForChild("SelfTest"))
local TrapService = require(Modules:WaitForChild("TrapService"))
local PreviewService = require(Modules:WaitForChild("PreviewService"))

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
task.spawn(PreviewService.start) -- tela de deslocamento: manequins vestidos e arte das armas para a prévia 3D
BotService.start()
TrapService.start() -- Parte 11 (depois): armadilhas VC, antes da logística que as arma
LogisticsService.start() -- F4: suprimento, caixotes e construções
CommanderService.start() -- F4: comandante e missões de fogo por grade
VehicleService.start() -- F4: M48A3, Ontos, LVTP-5 e UH-34D
FieldService.start() -- Parte 12: configurações de controle, marcações, mensagens, granadas e corpo a corpo
TrainingService.start() -- F6: campo de tiro e tutorial por papel
AnimalService.start() -- Parte 11: búfalos e galinhas fogem de tiros e explosões
RadioService.start() -- Parte 11: só o rádio do squad fala com o comandante
FieldWorkService.start() -- Parte 11: pá de trincheira e medevac pelo UH-34D
SelfTest.start() -- só no Studio: workspace:SetAttribute("VT65SelfTest", true)
PrivateServer.start(function(mode: string, clock: number)
	MatchService.requestMode(mode)
	LightingService.setStart(clock)
end)
print("[VT65] servidor pronto")
