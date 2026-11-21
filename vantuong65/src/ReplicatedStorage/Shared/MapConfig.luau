--!strict
-- GERADO por tools/crop_world.py. Não editar.
-- Coordenadas em studs no quadro local: X = leste, Z = sul. A origem é o centro do
-- mundo gerado (4 x 2,4 km, D-03), não o da área jogável (0.7 x 0.7 km, E 269.48–270.18 x N 1692.58–1693.28 km na grade de 1965).
local MapConfig = {}

MapConfig.STUD_M = 0.28
MapConfig.Bounds = { minX = -2571.4, maxX = -71.4, minZ = -3142.9, maxZ = -642.9 }
-- grade de 1965 (ING-A) da origem local: E = gridE0 + x*0,28 ; N = gridN0 - z*0,28
MapConfig.GridOrigin1965 = { e = 270200.0, n = 1692400.0 }
MapConfig.OutOfBoundsKillSeconds = 10
MapConfig.CaptureRadiusStuds = 35 / 0.28 -- 35 m (D-114: setores de ~100 m; o prompt pedia 40-60 m)
MapConfig.Sectors = {
		{ id = 1, name = "A Arrozais", polygon = {-2571.4, -642.9, -2571.4, -3142.9, -1910.7, -3142.9, -1910.7, -642.9} },
		{ id = 2, name = "B Serraria", polygon = {-1910.7, -642.9, -1910.7, -3142.9, -1607.2, -3142.9, -1607.2, -642.9} },
		{ id = 3, name = "C Vila", polygon = {-1607.2, -642.9, -1607.2, -3142.9, -1000.0, -3142.9, -1000.0, -1535.7, -1178.6, -1535.7, -1178.6, -642.9} },
		{ id = 4, name = "D Ponte e Cais", polygon = {-1178.6, -642.9, -1178.6, -1535.7, -1000.0, -1535.7, -1000.0, -3142.9, -785.7, -3142.9, -785.7, -642.9} },
		{ id = 5, name = "E Engenho", polygon = {-785.7, -642.9, -785.7, -3142.9, -71.4, -3142.9, -71.4, -642.9} },
}
MapConfig.Strongpoints = {
		{ sector = 1, name = "Arrozais", x = -2053.6, z = -1303.6, real = false, note = "arrozais a sudoeste; nome de design" },
		{ sector = 2, name = "Serraria", x = -1767.9, z = -2482.2, real = false, note = "serraria na mata fechada a noroeste; nome de design" },
		{ sector = 3, name = "Vila", x = -1366.1, z = -2000.0, real = false, note = "vila grande de design no morrote do centro (40 a 60 casas); nome de design" },
		{ sector = 4, name = "Ponte e Cais", x = -1035.7, z = -1303.6, real = false, note = "ponte e cais a sudeste; nome de design" },
		{ sector = 5, name = "Engenho", x = -625.0, z = -2482.2, real = false, note = "engenho a nordeste; nome de design" },
}
MapConfig.HQ = {
		US = { x = -250.0, z = -1892.9, note = "meio da borda leste, a leste de An Cường (2) (setor S3)" },
		VC = { x = -2392.9, z = -1892.9, note = "meio da borda oeste, retaguarda do VC (setor S1)" },
}
MapConfig.Locations = {
		{ name = "An Cường (2)", grid = "BS 700928", x = -607.1, z = -1607.2, e1965 = 270030, n1965 = 1692850 },
		{ name = "An Thới (2)", grid = "BS 695932", x = -2392.9, z = -2857.2, e1965 = 269530, n1965 = 1693200 },
}
-- D-123: o VC começa com o S1, os EUA com o último, o do meio neutro
MapConfig.InitialOwner = { "VC", "VC", "Neutral", "US", "US" }

return MapConfig
