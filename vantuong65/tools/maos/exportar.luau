--!strict
-- D-99: grava assets/blender/maos_1p/capsulas.json com as formas das mãos de 1ª pessoa (Shared/MaosPose:
-- cápsulas e caixas, em metros, espaço da arma) para o tools/maos/produzir.py montar a malha no Blender.
-- Uso (a partir de vantuong65): lune run tools/maos/exportar.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local MaosPose = require("../../src/ReplicatedStorage/Shared/MaosPose")

local out = { poses = {}, forearm = MaosPose.FOREARM_M, wrist = MaosPose.WRIST, sleeve = MaosPose.SLEEVE }
for name in MaosPose.POSES do
	for _, side in { "R", "L" } do
		local p = MaosPose.get(name, side)
		local lo, hi = MaosPose.bounds(p)
		out.poses[(if side == "R" then "MaoD_" else "MaoE_") .. name] = {
			chains = p.chains,
			boxes = p.boxes,
			bounds = { lo, hi },
		}
	end
end
fs.writeDir("assets/blender/maos_1p")
fs.writeFile("assets/blender/maos_1p/capsulas.json", serde.encode("json", out, true))
print("assets/blender/maos_1p/capsulas.json gravado")
