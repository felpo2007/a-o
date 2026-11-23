--!strict
-- Exporta o catálogo de skins (Shared/Skins) para o tools/roblox_cloud.py criar os itens de Robux.
-- Uso (de vantuong65/): lune run tools/skins_loja.luau > assets/skins_loja.json
local net = require("@lune/net")

local Skins = require("../src/ReplicatedStorage/Shared/Skins") :: any

local out = {}
for _, s in Skins.CATALOG do
	table.insert(out, {
		id = s.id,
		kind = s.kind,
		side = s.side,
		name = s.name,
		desc = s.desc,
		robux = s.robux,
		key = s.robuxKey,
		robuxKind = s.robuxKind,
		swatch = s.swatch,
		shirt = s.shirt,
		texture = s.texture,
	})
end
print(net.jsonEncode(out, true))
