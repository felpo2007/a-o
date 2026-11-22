--!strict
-- D-243: leva quem está no servidor para um servidor reservado com o mapa escolhido na votação. O perfil é salvo
-- antes de sair. Se o teleporte falhar, devolve false e a partida seguinte acontece aqui mesmo, no mapa de agora.
-- No Studio não há teleporte: só registra o que faria.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local PlayerData = require(script.Parent.PlayerData)

local MapaViagem = {}

local function salvaTodos(lista: { Player })
	local faltam = #lista
	for _, p in lista do
		task.spawn(function()
			pcall(function()
				PlayerData.save(p)
			end)
			faltam -= 1
		end)
	end
	local t0 = os.clock()
	while faltam > 0 and os.clock() - t0 < 6 do
		task.wait(0.1)
	end
end

function MapaViagem.levar(id: string): boolean
	local lista = Players:GetPlayers()
	if #lista == 0 then
		return false
	end
	if RunService:IsStudio() then
		print(
			string.format(
				"[VT65] votação: levaria %d jogador(es) para o mapa %s (sem teleporte no Studio)",
				#lista,
				id
			)
		)
		return false
	end
	salvaTodos(lista)
	local okR, codigo = pcall(function(): any
		return (TeleportService:ReserveServer(game.PlaceId))
	end)
	if not okR or type(codigo) ~= "string" then
		warn("[VT65] votação: não reservou o servidor:", codigo)
		return false
	end
	local opcoes = Instance.new("TeleportOptions")
	opcoes.ReservedServerAccessCode = codigo
	opcoes:SetTeleportData({ mapa = id })
	local okT, erro = pcall(function(): any
		return TeleportService:TeleportAsync(game.PlaceId, lista, opcoes)
	end)
	if not okT then
		warn("[VT65] votação: teleporte falhou:", erro)
		return false
	end
	return true
end

return MapaViagem
