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
	{ key = "Vila_serraria", x = -1753.276, y = 77.687, z = -2727.818 },
	{ key = "Vila_toras", x = -1805.533, y = 78.748, z = -2716.088 },
	{ key = "Vila_tabuas", x = -1803.73, y = 77.866, z = -2780.829 },
	{ key = "Vila_moenda", x = -518.228, y = 59.453, z = -2950.801 },
	{ key = "Vila_caldeira", x = -548.295, y = 58.737, z = -2900.188 },
	{ key = "Vila_ponte", x = -964.341, y = 36.859, z = -751.925 },
	{ key = "Vila_cais", x = -1016.338, y = 36.524, z = -752.551 },
	{ key = "Vila_barco", x = -1023.59, y = 34.143, z = -743.17 },
	{ key = "Vila_barco", x = -1005.328, y = 34.143, z = -748.15 },
	{ key = "Vila_horta", x = -1227.561, y = 123.766, z = -2095.584 },
	{ key = "Vila_horta", x = -1477.596, y = 120.146, z = -2225.986 },
	{ key = "Vila_horta", x = -1061.25, y = 108.088, z = -1794.032 },
	{ key = "Vila_horta", x = -1053.793, y = 98.527, z = -1717.725 },
	{ key = "Vila_chua", x = -1299.96, y = 121.545, z = -2012.56 },
	{ key = "Vila_dinh", x = -1428.91, y = 119.132, z = -1883.61 },
	{ key = "Vila_banca", x = -1362.79, y = 121.46, z = -1857.8 },
	{ key = "Vila_banca", x = -1395.62, y = 119.132, z = -1890.63 },
	{ key = "Vila_banca", x = -1428.45, y = 119.132, z = -1923.46 },
	{ key = "Vila_banca", x = -1461.28, y = 121.468, z = -1956.29 },
} :: { Entry }

return StaticArt
