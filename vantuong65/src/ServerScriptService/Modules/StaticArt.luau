--!strict
-- GERADO por tools/estatico.py (D-155). Não edite à mão: rode o script de novo.
-- Arte fixa no arquivo do place (SLIM): chave e pivô de cada modelo de
-- src/Workspace/Estatico. O AssetLoader não põe a cópia de mesma chave cujo pivô cai a
-- menos de StaticArt.TOL studs (e devolve a fixa no lugar).

export type Entry = { key: string, x: number, y: number, z: number }

local StaticArt = {}
StaticArt.TOL = 1
StaticArt.items = {
	{ key = "vila_casa_03", x = -1280.452, y = 118.958, z = -1804.733 },
	{ key = "water_jar", x = -1266.594, y = 119.806, z = -1822.985 },
	{ key = "hut_kitchen", x = -1278.471, y = 118.959, z = -1771.532 },
	{ key = "granary", x = -1251.115, y = 118.958, z = -1789.066 },
	{ key = "bamboo_fence", x = -1308.693, y = 118.958, z = -1816.958 },
	{ key = "bamboo_fence", x = -1279.768, y = 118.958, z = -1835.498 },
} :: { Entry }

return StaticArt
