--!strict
-- GERADO por tools/export_roblox.py a partir de DESIGN.md (D-03, D-08). Não editar.
-- Coordenadas em studs no quadro local: X = leste, Z = sul, origem no centro da área.
local MapConfig = {}

MapConfig.STUD_M = 0.28
MapConfig.Bounds = { minX = -7142.9, maxX = 7142.9, minZ = -4285.7, maxZ = 4285.7 }
-- grade de 1965 (ING-A) da origem local: E = gridE0 + x*0,28 ; N = gridN0 - z*0,28
MapConfig.GridOrigin1965 = { e = 270200.0, n = 1692400.0 }
MapConfig.OutOfBoundsKillSeconds = 10
MapConfig.CaptureRadiusStuds = 50 / 0.28 -- 50 m (prompt: 40-60 m)
MapConfig.Sectors = {
		{ id = 1, name = "S1 Colina 43", polygon = {-7142.9, 4285.7, -7142.9, -4285.7, -4107.2, -4285.7, -4107.2, -178.6, -3214.3, -178.6, -3214.3, 4285.7} },
		{ id = 2, name = "S2 Nam Yên", polygon = {-3214.3, 4285.7, -3214.3, -178.6, -4107.2, -178.6, -4107.2, -4285.7, -1428.6, -4285.7, -1428.6, 4285.7} },
		{ id = 3, name = "S3 An Cường (2)", polygon = {-1428.6, 4285.7, -1428.6, -4285.7, 1071.4, -4285.7, 1071.4, 0.0, 785.7, 0.0, 785.7, 4285.7} },
		{ id = 4, name = "S4 An Phước", polygon = {785.7, 4285.7, 785.7, 0.0, 1071.4, 0.0, 1071.4, -4285.7, 3750.0, -4285.7, 3750.0, 4285.7} },
		{ id = 5, name = "S5 Green Beach", polygon = {3750.0, 4285.7, 3750.0, -4285.7, 7142.9, -4285.7, 7142.9, 4285.7} },
}
MapConfig.Strongpoints = {
		{ sector = 1, name = "Colina 43", x = -5910.8, z = 2660.7, real = true, note = "cota 43 da carta" },
		{ sector = 1, name = "LZ Blue / Nam Yên (3)", x = -4642.9, z = 1250.0, real = true, note = "First Fight PDF p.29" },
		{ sector = 1, name = "Athletic field", x = -6428.6, z = 821.4, real = true, note = "retângulo tracejado da carta" },
		{ sector = 2, name = "Nam Yên (4)", x = -3035.7, z = -1678.6, real = true, note = "vila da carta" },
		{ sector = 2, name = "An Thới (2)", x = -2392.9, z = -2857.2, real = true, note = "vila da carta" },
		{ sector = 2, name = "Cemitério", x = -2732.2, z = -525.0, real = true, note = "símbolo de cemitério da carta" },
		{ sector = 3, name = "An Cường (2)", x = -607.1, z = -1607.2, real = true, note = "vila fortificada (First Fight p.25)" },
		{ sector = 3, name = "Trincheira sul", x = -571.4, z = -857.1, real = true, note = "'wide, deep trench south of the village' (p.23)" },
		{ sector = 3, name = "Colina 30", x = 17.9, z = -3642.9, real = true, note = "First Fight p.29" },
		{ sector = 4, name = "An Phước (1)", x = 1285.7, z = 2857.2, real = true, note = "vila da carta" },
		{ sector = 4, name = "Vau do riacho", x = 1892.9, z = 1375.0, real = true, note = "riacho real; ponto do vau é de design" },
		{ sector = 4, name = "Túmulos da várzea", x = 2678.6, z = -1785.7, real = false, note = "elemento de design (confirmar em foto)" },
		{ sector = 5, name = "An Cường (1)", x = 4821.5, z = 142.9, real = true, note = "vila de pescadores (First Fight p.21)" },
		{ sector = 5, name = "Colina 22", x = 5107.2, z = -1214.3, real = true, note = "Hill 22 (First Fight p.21) = cota trig. 22" },
		{ sector = 5, name = "Green Beach (dunas)", x = 5714.3, z = -357.1, real = true, note = "praia do desembarque, 06:30" },
}
MapConfig.HQ = {
		US = { x = 5821.5, z = 2321.4, note = "Green Beach sul (setor S5)" },
		VC = { x = -6857.2, z = -1785.7, note = "retaguarda oeste (setor S1)" },
}
MapConfig.Locations = {
		{ name = "Colina 43 (cume)", grid = "BS 685916", x = -5910.8, z = 2660.7, e1965 = 268545, n1965 = 1691655 },
		{ name = "LZ Blue", grid = "BS 688919", x = -4821.5, z = 1607.1, e1965 = 268850, n1965 = 1691950 },
		{ name = "Nam Yên (3)", grid = "BS 689921", x = -4464.3, z = 892.9, e1965 = 268950, n1965 = 1692150 },
		{ name = "Athletic field", grid = "BS 684921", x = -6428.6, z = 821.4, e1965 = 268400, n1965 = 1692170 },
		{ name = "Lạc Sơn (1)", grid = "BS 684914", x = -6357.2, z = 3285.7, e1965 = 268420, n1965 = 1691480 },
		{ name = "Nam Yên (4)", grid = "BS 693928", x = -3035.7, z = -1678.6, e1965 = 269350, n1965 = 1692870 },
		{ name = "An Cường (2)", grid = "BS 700928", x = -607.1, z = -1607.2, e1965 = 270030, n1965 = 1692850 },
		{ name = "Riacho a leste de An Cường (2)", grid = "BS 702929", x = 214.3, z = -1785.7, e1965 = 270260, n1965 = 1692900 },
		{ name = "Colina 30 (cume)", grid = "BS 702934", x = 17.9, z = -3642.9, e1965 = 270205, n1965 = 1693420 },
		{ name = "An Thới (2)", grid = "BS 695932", x = -2392.9, z = -2857.2, e1965 = 269530, n1965 = 1693200 },
		{ name = "An Thới (1)", grid = "BS 700936", x = -535.7, z = -4607.2, e1965 = 270050, n1965 = 1693690 },
		{ name = "An Phước (1)", grid = "BS 705916", x = 1285.7, z = 2857.2, e1965 = 270560, n1965 = 1691600 },
		{ name = "An Cường (1)", grid = "BS 715923", x = 4821.5, z = 142.9, e1965 = 271550, n1965 = 1692360 },
		{ name = "Green Beach (centro provisório)", grid = "BS 718925", x = 5714.3, z = -357.1, e1965 = 271800, n1965 = 1692500 },
		{ name = "Cota trigonométrica 22", grid = "BS 716927", x = 5107.2, z = -1214.3, e1965 = 271630, n1965 = 1692740 },
		{ name = "Cota trigonométrica 10", grid = "BS 721913", x = 6900.0, z = 3592.9, e1965 = 272132, n1965 = 1691394 },
		{ name = "Cota trigonométrica 45 (Núi Đầm Tre)", grid = "BS 720937", x = 6632.2, z = -4964.3, e1965 = 272057, n1965 = 1693790 },
		{ name = "Marco da Rota 523", grid = "BS 686911", x = -5714.3, z = 4525.0, e1965 = 268600, n1965 = 1691133 },
		{ name = "Vạn Tường (1)", grid = "BS 702957", x = 0.0, z = -11785.8, e1965 = 270200, n1965 = 1695700 },
}
-- EUA começam com S4-S5, VC com S1-S2, S3 neutro (prompt, Parte 3)
MapConfig.InitialOwner = { "VC", "VC", "Neutral", "US", "US" }

return MapConfig
