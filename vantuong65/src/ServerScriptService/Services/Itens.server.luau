--!strict
-- Liga a arma e a granada na mão que todos veem (Modules/ArmaNaMao, 2026-11-13). Script à parte para
-- não mexer no Main.server (os remotes vêm do Net.server de lá; Net.event espera).
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")
local ArmaNaMao = require(Modules:WaitForChild("ArmaNaMao"))
ArmaNaMao.start()
