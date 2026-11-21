--!strict
-- Servidores privados (vendidos pelo próprio Roblox; preço definido nas configurações do jogo):
-- o dono escolhe modo e horário antes da partida — útil para treino de unidade e campeonatos.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local PrivateServer = {}

PrivateServer.Modes = { Warfare = true, Offensive = true, Skirmish = true }
PrivateServer.Clocks = { [6.5] = true, [12] = true, [18.5] = true } -- 06:30, 12:00, 18:30 (Parte 5)

function PrivateServer.isPrivate(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0
end

function PrivateServer.validate(opts: any): (boolean, { mode: string, clock: number }?)
	if type(opts) ~= "table" then
		return false, nil
	end
	local mode, clock = opts.mode, tonumber(opts.clock)
	if type(mode) ~= "string" or not PrivateServer.Modes[mode] or not clock or not PrivateServer.Clocks[clock] then
		return false, nil
	end
	return true, { mode = mode, clock = clock }
end

function PrivateServer.start(onChange: (mode: string, clock: number) -> ())
	ReplicatedStorage:SetAttribute("PrivateServer", PrivateServer.isPrivate())
	Net.event("PrivateServer_SetOptions").OnServerEvent:Connect(function(player, opts)
		if not PrivateServer.isPrivate() or player.UserId ~= game.PrivateServerOwnerId then
			return
		end
		local ok, v = PrivateServer.validate(opts)
		if not ok or not v then
			return
		end
		ReplicatedStorage:SetAttribute("MatchMode", v.mode)
		onChange(v.mode, v.clock)
	end)
end

return PrivateServer
