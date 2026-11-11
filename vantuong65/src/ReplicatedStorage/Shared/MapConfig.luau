--!strict
-- GERADO por tools/crop_world.py. Não editar.
-- Coordenadas em studs no quadro local: X = leste, Z = sul. A origem é o centro do
-- mundo gerado (4 x 2,4 km, D-03), não o da área jogável (1 x 1 km, E 269.35–270.35 x N 1692.5–1693.5 km na grade de 1965).
local MapConfig = {}

MapConfig.STUD_M = 0.28
MapConfig.Bounds = { minX = -3035.7, maxX = 535.7, minZ = -3928.6, maxZ = -357.1 }
-- grade de 1965 (ING-A) da origem local: E = gridE0 + x*0,28 ; N = gridN0 - z*0,28
MapConfig.GridOrigin1965 = { e = 270200.0, n = 1692400.0 }
MapConfig.OutOfBoundsKillSeconds = 10
MapConfig.CaptureRadiusStuds = 50 / 0.28 -- 50 m (prompt: 40-60 m)
MapConfig.Sectors = {
		{ id = 1, name = "S1 Nam Yên (4)", polygon = {-3035.7, -357.1, -3035.7, -3928.6, -2500.0, -3928.6, -2500.0, -2142.9, -2178.6, -2142.9, -2178.6, -357.1} },
		{ id = 2, name = "S2 An Thới (2)", polygon = {-2178.6, -357.1, -2178.6, -2142.9, -2500.0, -2142.9, -2500.0, -3928.6, -1857.2, -3928.6, -1857.2, -2142.9, -1714.3, -2142.9, -1714.3, -357.1} },
		{ id = 3, name = "S3 Morrote do arrozal", polygon = {-1714.3, -357.1, -1714.3, -2142.9, -1857.2, -2142.9, -1857.2, -3928.6, -946.4, -3928.6, -946.4, -357.1} },
		{ id = 4, name = "S4 An Cường (2)", polygon = {-946.4, -357.1, -946.4, -3928.6, -196.4, -3928.6, -196.4, -357.1} },
		{ id = 5, name = "S5 Riacho", polygon = {-196.4, -357.1, -196.4, -3928.6, 535.7, -3928.6, 535.7, -357.1} },
}
MapConfig.Strongpoints = {
		{ sector = 1, name = "Nam Yên (4)", x = -2607.2, z = -1392.9, real = true, note = "vila da carta" },
		{ sector = 1, name = "Cemitério", x = -2732.2, z = -525.0, real = true, note = "símbolo de cemitério da carta" },
		{ sector = 1, name = "Capinzal oeste", x = -2785.7, z = -2392.9, real = false, note = "capim da carta no flanco do morro noroeste; nome de design" },
		{ sector = 2, name = "An Thới (2)", x = -2339.3, z = -2932.2, real = true, note = "vila da carta" },
		{ sector = 2, name = "Arrozal central", x = -1946.4, z = -1071.4, real = false, note = "diques e sebes do arrozal; elemento de design" },
		{ sector = 2, name = "Encosta norte", x = -2035.7, z = -2392.9, real = false, note = "flanco noroeste do morrote (capim da carta); nome de design" },
		{ sector = 3, name = "Morrote do arrozal", x = -1553.6, z = -2035.7, real = false, note = "morrote de 34 m no DEM; nome de design" },
		{ sector = 3, name = "Lugarejo a sudoeste de An Cường (2)", x = -1157.1, z = -746.4, real = true, note = "mancha de vila/mata da carta" },
		{ sector = 3, name = "Arrozal norte", x = -1321.4, z = -3071.4, real = false, note = "diques e sebes do arrozal; elemento de design" },
		{ sector = 4, name = "An Cường (2)", x = -607.1, z = -1607.2, real = true, note = "vila fortificada (First Fight p.25)" },
		{ sector = 4, name = "Trincheira sul", x = -571.4, z = -857.1, real = true, note = "'wide, deep trench south of the village' (p.23)" },
		{ sector = 4, name = "Arrozal ao norte de An Cường (2)", x = -571.4, z = -2750.0, real = false, note = "diques e sebes do arrozal; elemento de design" },
		{ sector = 5, name = "Colina 30", x = 17.9, z = -3642.9, real = true, note = "First Fight p.29" },
		{ sector = 5, name = "Riacho a leste de An Cường (2)", x = -7.1, z = -625.0, real = true, note = "'the streambed just east of An Cuong (2)' (First Fight p.29)" },
		{ sector = 5, name = "Encosta sul da Colina 30", x = 142.9, z = -2857.2, real = false, note = "relevo do DEM (vale do riacho até a Colina 30); nome de design" },
}
MapConfig.HQ = {
		US = { x = 357.1, z = -1964.3, note = "borda leste, no vale do riacho a leste de An Cường (2) (setor S5)" },
		VC = { x = -2821.4, z = -3678.6, note = "morro do noroeste, retaguarda oeste (setor S1)" },
}
MapConfig.Locations = {
		{ name = "Nam Yên (4)", grid = "BS 693928", x = -3035.7, z = -1678.6, e1965 = 269350, n1965 = 1692870 },
		{ name = "An Cường (2)", grid = "BS 700928", x = -607.1, z = -1607.2, e1965 = 270030, n1965 = 1692850 },
		{ name = "Riacho a leste de An Cường (2)", grid = "BS 702929", x = 214.3, z = -1785.7, e1965 = 270260, n1965 = 1692900 },
		{ name = "Colina 30 (cume)", grid = "BS 702934", x = 17.9, z = -3642.9, e1965 = 270205, n1965 = 1693420 },
		{ name = "An Thới (2)", grid = "BS 695932", x = -2392.9, z = -2857.2, e1965 = 269530, n1965 = 1693200 },
}
-- EUA começam com S4-S5, VC com S1-S2, S3 neutro (prompt, Parte 3)
MapConfig.InitialOwner = { "VC", "VC", "Neutral", "US", "US" }

return MapConfig
