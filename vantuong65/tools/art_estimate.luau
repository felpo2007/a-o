--!strict
-- Imprime a estimativa offline da arte por setor (ver tools/ArtEstimate.luau).
-- Uso, a partir de vantuong65/:  lune run tools/art_estimate.luau
local ArtBudget = require("../src/ServerScriptService/Modules/ArtBudget")
local estimate = require("./ArtEstimate")

local r = estimate()
print("setor  instâncias   triângulos   % do teto   touceiras de sebe")
local total = 0
for s = 0, 5 do
	local x = r.sectors[s]
	if x then
		total += x.tris
		print(
			string.format(
				"%5d  %10.0f  %11.0f   %8.1f%%   %5.0f%%",
				s,
				x.count,
				x.tris,
				100 * x.tris / ArtBudget.SECTOR_MAX,
				100 * x.factor
			)
		)
	end
end
print(string.format("total  %23.0f", total))
local keys = {}
for k in r.byKey do
	table.insert(keys, k)
end
table.sort(keys)
for _, k in keys do
	print(string.format("  %-16s %8.1f × %6d", k, r.byKey[k], ArtBudget.tris(k)))
end
