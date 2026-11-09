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

PlayerData.start()
CommerceService.start()
TeamService.start()
MatchService.start()
MedicalService.start()
SpawnService.start()
CombatService.start()
PrivateServer.start(function(mode: string, _clock: number)
	MatchService.requestMode(mode)
end)
print("[VT65] servidor pronto")
