--!strict
-- D-240: as cenas da tela de carregamento são as capas publicadas do jogo.
local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds") :: any
local CapasEntrada = require("../../src/ReplicatedFirst/CapasEntrada") :: any

local ok, fail = 0, 0
local function test(name: string, fn: () -> ())
	local good, err = pcall(fn)
	if good then
		ok += 1
	else
		fail += 1
		print("FALHOU: " .. name .. "\n  " .. tostring(err))
	end
end

test("toda cena do carregamento é uma capa publicada, sem repetir", function()
	local capas: { [number]: boolean } = {}
	local n = 0
	for _, id in AssetIds.Capas do
		capas[id] = true
		n += 1
	end
	local vistas: { [number]: boolean } = {}
	for _, id in CapasEntrada do
		assert(capas[id], "não é capa: " .. id)
		assert(not vistas[id], "repetida: " .. id)
		vistas[id] = true
	end
	assert(#CapasEntrada == n, string.format("%d cenas para %d capas", #CapasEntrada, n))
end)

print(string.format("telas: %d ok, %d falhas", ok, fail))
if fail > 0 then
	error("falhas")
end
