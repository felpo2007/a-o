--!nocheck
-- D-243: amostra a trajetória do comboio (Shared/Trajeto) para o tools/mapas_ret.py. A curva tem uma fonte só:
-- a estrada do terreno e o movimento dos caminhões saem do mesmo código.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local MapasRet = require("../src/ReplicatedStorage/Shared/MapasRet")
local Trajeto = require("../src/ReplicatedStorage/Shared/Trajeto")

local C = MapasRet.COMBOIO
local T = Trajeto.novo(C.nos, C.regras.extensaoM)
local pontos = {}
local s = -C.regras.extensaoM
while s <= T.comprimento + C.regras.extensaoM do
	local x, y = Trajeto.pos(T, s)
	table.insert(pontos, { math.round(x * 1000) / 1000, math.round(y * 1000) / 1000 })
	s += 3
end
fs.writeDir("assets/mapas")
fs.writeFile(
	"assets/mapas/comboio_trajeto.json",
	serde.encode("json", {
		comprimento = T.comprimento,
		sNos = T.sNos,
		raioMinimo = Trajeto.raioMinimo(T),
		pontos = pontos,
	})
)
print(
	string.format(
		"trajeto: %.2f m na curva, raio mínimo %.1f m, %d pontos",
		T.comprimento,
		Trajeto.raioMinimo(T),
		#pontos
	)
)
