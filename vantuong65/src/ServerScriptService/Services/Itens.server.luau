--!strict
-- Liga a arma e a granada na mão que todos veem (Modules/ArmaNaMao, 2026-11-13). Script à parte para
-- não mexer no Main.server (os remotes vêm do Net.server de lá; Net.event espera).
-- D-243: o mapa deste servidor, antes de qualquer módulo ler o MapConfig (a ordem dos scripts não é garantida)
require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("MapaBoot")).iniciar()

local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")
local ArmaNaMao = require(Modules:WaitForChild("ArmaNaMao"))
ArmaNaMao.start()
