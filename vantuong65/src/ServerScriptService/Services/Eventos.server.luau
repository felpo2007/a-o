--!strict
-- Liga os eventos da partida (Modules/EventosService) e a métrica do primeiro contato
-- (Modules/ContatoService). Script à parte para não mexer no Main.server (os remotes vêm do
-- Net.server de lá; Net.event espera).
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")
local ContatoService = require(Modules:WaitForChild("ContatoService"))
local EventosService = require(Modules:WaitForChild("EventosService"))
ContatoService.start()
EventosService.start()
