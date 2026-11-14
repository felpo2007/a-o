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
	{
		id = 1,
		name = "A Mata fechada",
		polygon = { -2571.4, -642.9, -2571.4, -3142.9, -1607.2, -3142.9, -1607.2, -642.9 },
	},
	{ id = 2, name = "B Xóm Gò", polygon = { -1607.2, -642.9, -1607.2, -3142.9, -1000.0, -3142.9, -1000.0, -642.9 } },
	{
		id = 3,
		name = "C An Cường (2)",
		polygon = { -1000.0, -642.9, -1000.0, -3142.9, -71.4, -3142.9, -71.4, -642.9 },
	},
}
MapConfig.Strongpoints = {
	{
		sector = 1,
		name = "Mata fechada",
		x = -1964.3,
		z = -2142.9,
		real = false,
		note = "mata cerrada a noroeste do morro; nome de design",
	},
	{
		sector = 1,
		name = "Picada na mata",
		x = -2053.6,
		z = -1392.9,
		real = false,
		note = "trilha estreita na mata a sudoeste; nome de design",
	},
	{
		sector = 2,
		name = "Xóm Gò",
		x = -1339.3,
		z = -1892.9,
		real = false,
		note = "vila grande de design no morrote do centro (40 a 60 casas); nome de design",
	},
	{
		sector = 2,
		name = "Becos de Xóm Gò",
		x = -1339.3,
		z = -1632.9,
		real = false,
		note = "travessa e becos da vila de design (a ~56 m da praça); nome de design",
	},
	{
		sector = 2,
		name = "Ponta norte de Xóm Gò",
		x = -1339.3,
		z = -2152.9,
		real = false,
		note = "travessa da vila de design do lado do pagode (a ~56 m da praça); nome de design",
	},
	{
		sector = 3,
		name = "An Cường (2)",
		x = -767.9,
		z = -1678.6,
		real = true,
		note = "vila fortificada (First Fight p.25)",
	},
	{
		sector = 3,
		name = "Sebe ao norte de An Cường (2)",
		x = -767.9,
		z = -2053.6,
		real = false,
		note = "sebe junto da boca E4 do túnel; nome de design",
	},
	{
		sector = 3,
		name = "Arrozal ao sul de An Cường (2)",
		x = -750.0,
		z = -1357.2,
		real = false,
		note = "arrozal ao sul da vila; nome de design",
	},
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
MapConfig.InitialOwner = { "VC", "Neutral", "US" }

return MapConfig
