--!strict
-- GERADO por tools/crop_world.py (DESIGN.md D-63). Não editar.
-- Coordenadas em studs no quadro local: X = leste, Z = sul. A origem é o centro do
-- mundo gerado (4 x 2,4 km, D-03), não o da área jogável (2 x 2 km, a oeste).
local MapConfig = {}

MapConfig.STUD_M = 0.28
MapConfig.Bounds = { minX = -6607.2, maxX = 535.7, minZ = -3928.6, maxZ = 3214.3 }
-- grade de 1965 (ING-A) da origem local: E = gridE0 + x*0,28 ; N = gridN0 - z*0,28
MapConfig.GridOrigin1965 = { e = 270200.0, n = 1692400.0 }
MapConfig.OutOfBoundsKillSeconds = 10
MapConfig.CaptureRadiusStuds = 50 / 0.28 -- 50 m (prompt: 40-60 m)
MapConfig.Sectors = {
		{ id = 1, name = "S1 Colina 43", polygon = {-6607.2, 3214.3, -6607.2, -3928.6, -5178.6, -3928.6, -5178.6, 3214.3} },
		{ id = 2, name = "S2 LZ Blue", polygon = {-5178.6, 3214.3, -5178.6, -3928.6, -3750.0, -3928.6, -3750.0, 3214.3} },
		{ id = 3, name = "S3 Nam Yên (4)", polygon = {-3750.0, 3214.3, -3750.0, -3928.6, -2678.6, -3928.6, -2678.6, -2142.9, -2142.9, -2142.9, -2142.9, 3214.3} },
		{ id = 4, name = "S4 Arrozais", polygon = {-2142.9, 3214.3, -2142.9, -2142.9, -2678.6, -2142.9, -2678.6, -3928.6, -1250.0, -3928.6, -1250.0, 3214.3} },
		{ id = 5, name = "S5 An Cường (2)", polygon = {-1250.0, 3214.3, -1250.0, -3928.6, 535.7, -3928.6, 535.7, 3214.3} },
}
MapConfig.Strongpoints = {
		{ sector = 1, name = "Colina 43", x = -5910.8, z = 2660.7, real = true, note = "cota 43 da carta" },
		{ sector = 1, name = "Athletic field", x = -6357.2, z = 821.4, real = true, note = "retângulo tracejado da carta" },
		{ sector = 1, name = "Lugarejo da Colina 43", x = -5517.9, z = 2867.9, real = true, note = "5 casas da carta ao pé da colina, sem nome" },
		{ sector = 2, name = "LZ Blue", x = -4821.5, z = 1607.1, real = true, note = "First Fight p.26 + mapa p.25" },
		{ sector = 2, name = "Nam Yên (3)", x = -4464.3, z = 892.9, real = true, note = "vila da carta" },
		{ sector = 2, name = "Encosta norte", x = -4642.9, z = -3035.7, real = false, note = "relevo do DEM (sobe a ~50 m na borda norte); nome de design" },
		{ sector = 3, name = "Nam Yên (4)", x = -3035.7, z = -1678.6, real = true, note = "vila da carta" },
		{ sector = 3, name = "Cemitério", x = -2732.2, z = -525.0, real = true, note = "símbolo de cemitério da carta" },
		{ sector = 3, name = "Bosque ao sul de Nam Yên (4)", x = -3317.9, z = 1407.1, real = true, note = "mancha de vila/mata da carta" },
		{ sector = 4, name = "An Thới (2)", x = -2392.9, z = -2857.2, real = true, note = "vila da carta" },
		{ sector = 4, name = "Morrote do arrozal", x = -1639.3, z = -2014.3, real = false, note = "morrote de 34 m no DEM; nome de design" },
		{ sector = 4, name = "Arrozal central", x = -1696.4, z = 357.1, real = false, note = "diques e sebes do arrozal; elemento de design" },
		{ sector = 5, name = "An Cường (2)", x = -607.1, z = -1607.2, real = true, note = "vila fortificada (First Fight p.25)" },
		{ sector = 5, name = "Trincheira sul", x = -571.4, z = -857.1, real = true, note = "'wide, deep trench south of the village' (p.23)" },
		{ sector = 5, name = "Colina 30", x = 17.9, z = -3642.9, real = true, note = "First Fight p.29" },
}
MapConfig.HQ = {
		US = { x = 357.1, z = 2321.4, note = "borda leste, ao sul de An Cường (2) (setor S5)" },
		VC = { x = -6357.2, z = -1785.7, note = "retaguarda oeste, ao norte do Athletic field (setor S1)" },
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
}
-- EUA começam com S4-S5, VC com S1-S2, S3 neutro (prompt, Parte 3)
MapConfig.InitialOwner = { "VC", "VC", "Neutral", "US", "US" }

return MapConfig
