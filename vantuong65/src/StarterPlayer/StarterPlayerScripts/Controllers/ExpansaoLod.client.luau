--!strict
-- D-233: esconde de longe as peças da expansão que não têm colisão (regra em Shared/ExpansaoLod).
-- Passa pela lista 2,5 vezes por segundo, e só quando a câmera andou ou chegou peça pelo streaming.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExpansaoLod = require(ReplicatedStorage.Shared.ExpansaoLod)

local player = Players.LocalPlayer

type Item = { parte: BasePart, limite: number, oculta: boolean }
local itens: { [Instance]: Item } = {}
local mudou = true

local function entra(i: Instance)
	local limite = i:GetAttribute(ExpansaoLod.ATRIBUTO)
	if i:IsA("BasePart") and type(limite) == "number" then
		itens[i] = { parte = i, limite = limite, oculta = false }
		mudou = true
	end
end

CollectionService:GetInstanceAddedSignal(ExpansaoLod.TAG):Connect(entra)
CollectionService:GetInstanceRemovedSignal(ExpansaoLod.TAG):Connect(function(i: Instance)
	itens[i] = nil
end)
for _, i in CollectionService:GetTagged(ExpansaoLod.TAG) do
	entra(i)
end

task.spawn(function()
	local ultima = Vector3.new(math.huge, 0, 0)
	local ultimoDetalhe = -1
	while true do
		task.wait(0.4)
		local camera = workspace.CurrentCamera
		if camera then
			local pos = camera.CFrame.Position
			local d = player:GetAttribute("GfxDetail")
			local detalhe = if type(d) == "number" then d else 1
			if mudou or detalhe ~= ultimoDetalhe or (pos - ultima).Magnitude > 4 then
				mudou, ultima, ultimoDetalhe = false, pos, detalhe
				for _, it in itens do
					local oculta =
						ExpansaoLod.esconde((it.parte.Position - pos).Magnitude, it.limite, detalhe, it.oculta)
					if oculta ~= it.oculta then
						it.oculta = oculta
						it.parte.LocalTransparencyModifier = if oculta then 1 else 0
					end
				end
			end
		end
	end
end)
