--!strict
-- Lista os acabamentos de arma (Shared/Skins) em JSON para o tools/acabamentos.py (D-178): id,
-- arma, cores de fábrica de reserva (finish) e a arte gerada (receita, cores, alvo).
-- Uso: lune run tools/acabamentos_dump.luau <saida.json>
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Skins = require("../src/ReplicatedStorage/Shared/Skins") :: any

local saida = process.args[1]
assert(saida, "uso: lune run tools/acabamentos_dump.luau <saida.json>")

local out = {}
for _, s in Skins.CATALOG do
	if s.kind == "weapon" then
		table.insert(out, {
			id = s.id,
			arma = s.weapon,
			finish = s.finish or {},
			arte = s.arte,
			soCaixa = s.soCaixa == true,
		})
	end
end
fs.writeFile(saida, serde.encode("json", out, true))
print(#out .. " acabamentos")
