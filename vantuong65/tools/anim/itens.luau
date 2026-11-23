--!strict
-- D-99: grava tools/anim/itens.json com o caminho das mãos de cada uso de item (Shared/ItemAnim, o
-- mesmo que o PostureController usa no jogo) para o retarget.py fazer os clipes "item_*".
-- Uso (a partir de vantuong65): lune run tools/anim/itens.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local ItemAnim = require("../../src/ReplicatedStorage/Shared/ItemAnim")

local out = {}
for name, a in ItemAnim.ANIMS do
	local keys = {}
	for _, k in a.tp do
		-- o mesmo alcance do jogo (ItemAnim.reach, PostureController)
		table.insert(keys, { t = k.t, r = ItemAnim.reach(k.r, "R"), l = ItemAnim.reach(k.l, "L"), tilt = k.tilt or 0 })
	end
	out[name] = {
		dur = a.dur,
		loop = { a.loop.a, a.loop.b },
		slung = a.slung,
		left = a.left,
		right = a.right,
		held = a.held,
		keys = keys,
	}
end
fs.writeFile("tools/anim/itens.json", serde.encode("json", { anims = out, poles = ItemAnim.POLES }, true))
print("tools/anim/itens.json:", #(fs.readFile("tools/anim/itens.json")), "bytes")
