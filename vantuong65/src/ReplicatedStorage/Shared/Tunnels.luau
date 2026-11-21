--!strict
-- Rede de túneis pré-escavada sob An Cường (2) (Parte 4): estreita (1,0 x 1,2 m), a ~3 m de
-- profundidade, com entradas camufladas. TRAÇADO DE DESIGN: as fontes confirmam túneis ligando
-- trincheiras e buracos de combate na vila (First Fight PDF p.25; VFW), não a planta exata.
-- Coordenadas em metros relativos ao centro de An Cường (2): x = leste, z = sul.
local Tunnels = {}

Tunnels.WIDTH_M = 1.0
Tunnels.HEIGHT_M = 1.2
Tunnels.DEPTH_M = 3.0 -- piso abaixo do chão
Tunnels.SHAFT_M = 0.6 -- poço de entrada

Tunnels.nodes = {
	J1 = { x = 0, z = 0, entrance = false }, -- sob o centro da vila
	J2 = { x = 5, z = 100, entrance = false },
	J3 = { x = -25, z = -60, entrance = false },
	E1 = { x = -60, z = -15, entrance = true }, -- quintal a oeste
	E2 = { x = 45, z = 25, entrance = true }, -- junto ao riacho a leste
	E3 = { x = -15, z = 150, entrance = true }, -- arrozal ao sul (saída de emboscada)
	E4 = { x = -35, z = -95, entrance = true }, -- sebe ao norte
	-- dentro da trincheira sul. D-115: 185 m (era 205): no mapa de 500 m a 205 m ficava na borda sul
	E5 = { x = 10, z = 185, entrance = true },
} :: { [string]: { x: number, z: number, entrance: boolean } }

Tunnels.edges = {
	{ "E1", "J1" },
	{ "E2", "J1" },
	{ "J3", "J1" },
	{ "E4", "J3" },
	{ "J1", "J2" },
	{ "J2", "E3" },
	{ "J2", "E5" },
}

-- Trincheira sul ("wide, deep trench south of the village", First Fight PDF p.23): traçado de
-- design, 1,0 m de largura x 1,5 m de profundidade, em metros relativos ao centro da vila (o local da
-- carta, MapConfig.Locations). D-115: 20 m mais perto da vila (a 204–212 m, metade dela caía fora do
-- mapa de 500 m, cuja borda sul fica a 210 m do centro); agora fica a 18–26 m da borda.
Tunnels.trench = { { -60, 185 }, { -20, 190 }, { 20, 184 }, { 60, 192 }, { 95, 186 } }
Tunnels.TRENCH_W_M = 1.0
Tunnels.TRENCH_D_M = 1.5

-- Converte para studs no quadro do jogo a partir da posição (studs) de An Cường (2).
function Tunnels.toWorld(cx: number, cz: number, xm: number, zm: number): (number, number)
	return cx + xm / 0.28, cz + zm / 0.28
end

function Tunnels.length(): number
	local total = 0
	for _, e in Tunnels.edges do
		local a, b = Tunnels.nodes[e[1]], Tunnels.nodes[e[2]]
		total += math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	end
	return total
end

return Tunnels
