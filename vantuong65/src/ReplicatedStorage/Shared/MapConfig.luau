--!strict
-- GERADO por tools/crop_world.py. Não editar.
-- Coordenadas em studs no quadro local: X = leste, Z = sul. A origem é o centro do
-- mundo gerado (4 x 2,4 km, D-03), não o da área jogável (0.5 x 0.5 km, E 269.66–270.16 x N 1692.64–1693.14 km na grade de 1965).
local MapConfig = {}

MapConfig.STUD_M = 0.28
MapConfig.Bounds = { minX = -1928.6, maxX = -142.9, minZ = -2642.9, maxZ = -857.1 }
-- grade de 1965 (ING-A) da origem local: E = gridE0 + x*0,28 ; N = gridN0 - z*0,28
MapConfig.GridOrigin1965 = { e = 270200.0, n = 1692400.0 }
MapConfig.OutOfBoundsKillSeconds = 10
MapConfig.CaptureRadiusStuds = 35 / 0.28 -- 35 m (D-114: setores de ~100 m; o prompt pedia 40-60 m)
MapConfig.Sectors = {
		{ id = 1, name = "A Encosta oeste", polygon = {-1928.6, -857.1, -1928.6, -2642.9, -1535.7, -2642.9, -1535.7, -857.1} },
		{ id = 2, name = "B Xóm Gò", polygon = {-1535.7, -857.1, -1535.7, -2642.9, -1178.6, -2642.9, -1178.6, -857.1} },
		{ id = 3, name = "C Sopé do morro", polygon = {-1178.6, -857.1, -1178.6, -2642.9, -928.6, -2642.9, -928.6, -857.1} },
		{ id = 4, name = "D An Cường (2)", polygon = {-928.6, -857.1, -928.6, -2642.9, -571.4, -2642.9, -571.4, -857.1} },
		{ id = 5, name = "E Vale do riacho", polygon = {-571.4, -857.1, -571.4, -2642.9, -142.9, -2642.9, -142.9, -857.1} },
}
MapConfig.Strongpoints = {
		{ sector = 1, name = "Trilha do morro", x = -1600.0, z = -1732.2, real = false, note = "subida da base do VC até a vila; nome de design" },
		{ sector = 1, name = "Encosta oeste", x = -1607.2, z = -1982.2, real = false, note = "flanco oeste do morro de Xóm Gò; nome de design" },
		{ sector = 1, name = "Capinzal oeste", x = -1642.9, z = -1482.2, real = false, note = "capim ao pé do morro; nome de design" },
		{ sector = 2, name = "Xóm Gò", x = -1339.3, z = -1892.9, real = false, note = "vila grande de design no morrote do centro (40 a 60 casas); nome de design" },
		{ sector = 2, name = "Becos de Xóm Gò", x = -1339.3, z = -1632.9, real = false, note = "travessa e becos da vila de design (a ~56 m da praça); nome de design" },
		{ sector = 2, name = "Ponta norte de Xóm Gò", x = -1339.3, z = -2152.9, real = false, note = "travessa da vila de design do lado do pagode (a ~56 m da praça); nome de design" },
		{ sector = 3, name = "Quintal oeste de An Cường (2)", x = -1053.6, z = -1714.3, real = false, note = "quintal a oeste da vila; nome de design" },
		{ sector = 3, name = "Encosta leste", x = -1071.4, z = -2053.6, real = false, note = "flanco leste do morro de Xóm Gò; nome de design" },
		{ sector = 3, name = "Sopé sul do morro", x = -1089.3, z = -1428.6, real = false, note = "pé do morro ao sul da vila; nome de design" },
		{ sector = 4, name = "An Cường (2)", x = -767.9, z = -1678.6, real = true, note = "vila fortificada (First Fight p.25)" },
		{ sector = 4, name = "Sebe ao norte de An Cường (2)", x = -767.9, z = -2053.6, real = false, note = "sebe junto da boca E4 do túnel; nome de design" },
		{ sector = 4, name = "Arrozal ao sul de An Cường (2)", x = -750.0, z = -1357.2, real = false, note = "arrozal ao sul da vila; nome de design" },
		{ sector = 5, name = "Casario sudeste de An Cường (2)", x = -464.3, z = -1339.3, real = true, note = "casas da carta de 1965 a sudeste da vila" },
		{ sector = 5, name = "Capinzal do vale", x = -321.4, z = -1410.7, real = false, note = "vale do riacho ao sul da base; nome de design" },
		{ sector = 5, name = "Vale ao norte da base", x = -357.1, z = -2267.9, real = false, note = "vale ao norte da base, junto do riacho; nome de design" },
}
MapConfig.HQ = {
		US = { x = -339.3, z = -1910.7, note = "borda leste, a nordeste de An Cường (2) (setor S5)" },
		VC = { x = -1828.6, z = -1750.0, note = "pé oeste do morro de Xóm Gò, retaguarda oeste (setor S1)" },
}
MapConfig.Locations = {
		{ name = "An Cường (2)", grid = "BS 700928", x = -607.1, z = -1607.2, e1965 = 270030, n1965 = 1692850 },
}
-- EUA começam com S4-S5, VC com S1-S2, S3 neutro (prompt, Parte 3)
MapConfig.InitialOwner = { "VC", "VC", "Neutral", "US", "US" }

return MapConfig
