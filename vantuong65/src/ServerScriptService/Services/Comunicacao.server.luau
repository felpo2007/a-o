--!strict
-- Liga a conversa no campo (Modules/Comunicacao): canais de texto, voz de perto e rádio do squad.
-- Script à parte para não mexer no Main.server (os remotes vêm do Net.server de lá; Net.event espera).
-- D-243: o mapa deste servidor, antes de qualquer módulo ler o MapConfig (a ordem dos scripts não é garantida)
require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("MapaBoot")).iniciar()

local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")
local Comunicacao = require(Modules:WaitForChild("Comunicacao"))
Comunicacao.start()
