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
	{ key = "vila_casa_06", x = -1533.681, y = 116.75, z = -2047.917 },
	{ key = "vila_casa_04", x = -1439.42, y = 122.855, z = -2080.274 },
	{ key = "vila_casa_03", x = -1323.39, y = 123.953, z = -2104.316 },
	{ key = "vila_casa_10", x = -1405.34, y = 123.165, z = -2130.869 },
	{ key = "vila_casa_01", x = -1150.913, y = 119.273, z = -2108.308 },
	{ key = "vila_casa_05", x = -1159.577, y = 119.281, z = -1829.508 },
	{ key = "vila_casa_08", x = -1103.68, y = 113.874, z = -2156.215 },
	{ key = "vila_casa_02", x = -1216.73, y = 123.999, z = -2257.927 },
	{ key = "vila_casa_07", x = -1412.422, y = 114.509, z = -1791.5 },
	{ key = "vila_casa_04", x = -1252.096, y = 124.141, z = -2073.191 },
	{ key = "vila_casa_03", x = -1182.313, y = 121.107, z = -2014.677 },
	{ key = "vila_casa_10", x = -1094.761, y = 112.951, z = -2008.7 },
	{ key = "vila_casa_01", x = -1263.862, y = 125.843, z = -2209.188 },
	{ key = "vila_casa_10", x = -1165.47, y = 120.665, z = -2190.199 },
	{ key = "vila_casa_03", x = -1086.664, y = 108.088, z = -1815.491 },
	{ key = "vila_casa_10", x = -1214.25, y = 110.883, z = -1706.991 },
	{ key = "vila_casa_06", x = -1417.792, y = 122.05, z = -2248.644 },
	{ key = "vila_casa_06", x = -1134.498, y = 117.251, z = -2243.94 },
	{ key = "vila_casa_04", x = -1066.385, y = 104.211, z = -2206.64 },
	{ key = "vila_casa_06", x = -1080.041, y = 98.527, z = -1738.163 },
	{ key = "vila_casa_03", x = -1149.383, y = 99.585, z = -1667.243 },
	{ key = "vila_casa_08", x = -1496.429, y = 114.812, z = -2348.051 },
	{ key = "vila_casa_02", x = -1291.624, y = 124.013, z = -2383.36 },
	{ key = "vila_casa_04", x = -1138.139, y = 113.048, z = -2352.525 },
	{ key = "vila_casa_03", x = -1414.531, y = 120.285, z = -2393.656 },
	{ key = "vila_casa_01", x = -1314.653, y = 112.624, z = -1716.927 },
	{ key = "vila_casa_08", x = -1517.162, y = 116.588, z = -1908.373 },
	{ key = "vila_casa_04", x = -1218.187, y = 96.877, z = -1615.786 },
} :: { Entry }

return StaticArt
