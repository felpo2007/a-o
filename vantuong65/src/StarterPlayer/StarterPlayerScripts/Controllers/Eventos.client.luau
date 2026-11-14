--!strict
-- Avisos dos eventos da partida (Modules/EventosService) no Toast da interface. Só chama a API do
-- Toast; o visual (ícone, faixa, marcador na carta) é do agente de interface, que lê os marcadores em
-- ReplicatedStorage.VT65Eventos (um Configuration por evento, com atributos).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Toast = require(script.Parent.Toast)

Net.event("Evento_Aviso").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" or type(msg.texto) ~= "string" then
		return
	end
	Toast.show(msg.texto, if type(msg.tipo) == "string" then msg.tipo else "info", {
		title = if type(msg.titulo) == "string" then msg.titulo else nil,
		key = if type(msg.chave) == "string" then msg.chave else nil,
		duration = if type(msg.duracao) == "number" then msg.duracao else nil,
	})
end)
