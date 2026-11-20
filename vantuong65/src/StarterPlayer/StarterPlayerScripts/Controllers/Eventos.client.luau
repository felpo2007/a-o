--!strict
-- Avisos dos eventos da partida (Modules/EventosService) no Toast da interface. Só chama a API do
-- Toast; o visual (ícone, faixa, marcador na carta) é do agente de interface, que lê os marcadores em
-- ReplicatedStorage.VT65Eventos (um Configuration por evento, com atributos).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local EventoCartao = require(script.Parent.EventoCartao)
local Toast = require(script.Parent.Toast)

-- D-185: o primeiro aviso de cada evento (chave "evento:<uid>") vira o cartão grande do começo
-- (Controllers/EventoCartao); os seguintes (barragem terminou, depósito destruído...) seguem em texto
local seen: { [string]: boolean } = {}

Net.event("Evento_Aviso").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" or type(msg.texto) ~= "string" then
		return
	end
	local chave = if type(msg.chave) == "string" then msg.chave else nil
	if chave and not seen[chave] then
		seen[chave] = true
		local ok, shown = pcall(EventoCartao.show, msg)
		if ok and shown then
			return
		end
	end
	Toast.show(msg.texto, if type(msg.tipo) == "string" then msg.tipo else "info", {
		title = if type(msg.titulo) == "string" then msg.titulo else nil,
		key = if type(msg.chave) == "string" then msg.chave else nil,
		duration = if type(msg.duracao) == "number" then msg.duracao else nil,
	})
end)
