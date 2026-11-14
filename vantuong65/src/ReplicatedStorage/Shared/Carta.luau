--!strict
-- Geometria da carta tática (o mapa que se abre no jogo, GameUI). Módulo puro, testado no Lune
-- (tests/luau/modo.luau):
--   - a imagem (tools/make_carta.py) cobre MapConfig.Bounds em 2 x 2 blocos de 1024 px;
--   - os setores são polígonos retilíneos (D-63): viram retângulos para pintar o dono e linhas
--     para a fronteira e a frente;
--   - a folha é quadrada; a janela pode ter qualquer proporção. Zoom e arrasto mexem no centro (u, v)
--     da janela em coordenadas da folha (0..1), com o ponto sob o cursor parado ao dar zoom.
local Geometry = require(script and (script :: any).Parent.Geometry or "./Geometry") :: any

local Carta = {}

Carta.ZOOM_MIN = 1
Carta.ZOOM_MAX = 6
-- blocos da imagem: linha 0 = norte (Z menor), coluna 0 = oeste
Carta.TILES = {
	{ key = "nw", row = 0, col = 0 },
	{ key = "ne", row = 0, col = 1 },
	{ key = "sw", row = 1, col = 0 },
	{ key = "se", row = 1, col = 1 },
}

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }
export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type Segment = { x1: number, z1: number, x2: number, z2: number }

function Carta.toUV(b: Bounds, x: number, z: number): (number, number)
	return (x - b.minX) / (b.maxX - b.minX), (z - b.minZ) / (b.maxZ - b.minZ)
end

function Carta.fromUV(b: Bounds, u: number, v: number): (number, number)
	return b.minX + u * (b.maxX - b.minX), b.minZ + v * (b.maxZ - b.minZ)
end

local function uniq(list: { number }): { number }
	table.sort(list)
	local out = {}
	for _, v in list do
		if #out == 0 or math.abs(v - out[#out]) > 1e-6 then
			table.insert(out, v)
		end
	end
	return out
end

-- Polígono retilíneo (lista plana x1, z1, x2, z2...) -> retângulos que o cobrem, sem sobreposição:
-- faixas verticais entre os X dos vértices, juntando os trechos de Z que ficam dentro.
function Carta.rects(poly: { number }): { Rect }
	local xs, zs = {}, {}
	for i = 1, #poly - 1, 2 do
		table.insert(xs, poly[i])
		table.insert(zs, poly[i + 1])
	end
	xs, zs = uniq(xs), uniq(zs)
	local out: { Rect } = {}
	for i = 1, #xs - 1 do
		local xa, xb = xs[i], xs[i + 1]
		local mx = (xa + xb) / 2
		local open: number? = nil
		for j = 1, #zs - 1 do
			local inside = Geometry.pointInPolygon(poly, mx, (zs[j] + zs[j + 1]) / 2)
			if inside and open == nil then
				open = zs[j]
			elseif not inside and open ~= nil then
				table.insert(out, { x0 = xa, z0 = open, x1 = xb, z1 = zs[j] })
				open = nil
			end
		end
		if open ~= nil then
			table.insert(out, { x0 = xa, z0 = open, x1 = xb, z1 = zs[#zs] })
		end
	end
	return out
end

function Carta.edges(poly: { number }): { Segment }
	local out: { Segment } = {}
	local n = #poly // 2
	for i = 1, n do
		local j = i % n + 1
		table.insert(out, { x1 = poly[2 * i - 1], z1 = poly[2 * i], x2 = poly[2 * j - 1], z2 = poly[2 * j] })
	end
	return out
end

-- Trechos da fronteira entre os setores a e b (arestas de a que têm b do outro lado).
function Carta.boundary(sectors: { any }, a: number, b: number): { Segment }
	local poly: { number }? = nil
	for _, s in sectors do
		if s.id == a then
			poly = s.polygon
		end
	end
	if not poly then
		return {}
	end
	local out: { Segment } = {}
	for _, e in Carta.edges(poly) do
		local dx, dz = e.x2 - e.x1, e.z2 - e.z1
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1e-6 then
			local nx, nz = -dz / len, dx / len
			local mx, mz = (e.x1 + e.x2) / 2, (e.z1 + e.z2) / 2
			local s1 = Geometry.sectorAt(sectors, mx + nx, mz + nz)
			local s2 = Geometry.sectorAt(sectors, mx - nx, mz - nz)
			if (s1 == a and s2 == b) or (s1 == b and s2 == a) then
				table.insert(out, e)
			end
		end
	end
	return out
end

-- ===== janela: zoom e arrasto =====
-- A folha (quadrada) tem lado base * zoom px; base = o maior quadrado que cabe na janela. (u, v) é o
-- ponto da folha no centro da janela. Com a folha maior que a janela, o centro fica preso para a
-- borda da folha não entrar; menor, ela fica centrada naquele eixo.
function Carta.base(viewW: number, viewH: number): number
	return math.min(viewW, viewH)
end

function Carta.clampCenter(u: number, v: number, zoom: number, viewW: number, viewH: number): (number, number)
	local size = Carta.base(viewW, viewH) * zoom
	local function clamp(c: number, view: number): number
		if size <= view + 1e-6 then
			return 0.5
		end
		local half = view / 2 / size
		return math.clamp(c, half, 1 - half)
	end
	return clamp(u, viewW), clamp(v, viewH)
end

-- posição (canto superior esquerdo, px) e lado da folha na janela
function Carta.layout(u: number, v: number, zoom: number, viewW: number, viewH: number): (number, number, number)
	local size = Carta.base(viewW, viewH) * zoom
	return viewW / 2 - u * size, viewH / 2 - v * size, size
end

-- novo centro para o ponto (au, av) da folha ficar no mesmo lugar da tela ao passar de zoom a z2
function Carta.zoomAbout(u: number, v: number, zoom: number, z2: number, au: number, av: number): (number, number)
	local k = zoom / z2
	return au - (au - u) * k, av - (av - v) * k
end

-- ponto da folha (u, v) sob o pixel (px, py) da janela
function Carta.pick(
	u: number,
	v: number,
	zoom: number,
	viewW: number,
	viewH: number,
	px: number,
	py: number
): (number, number)
	local x0, y0, size = Carta.layout(u, v, zoom, viewW, viewH)
	return (px - x0) / size, (py - y0) / size
end

-- escala gráfica que cabe em ~maxPx: 25, 50, 100, 200 ou 500 m
function Carta.scaleBar(metersPerPx: number, maxPx: number): (number, number)
	local best = 25
	for _, m in { 25, 50, 100, 200, 500, 1000 } do
		if m / metersPerPx <= maxPx then
			best = m
		end
	end
	return best, best / metersPerPx
end

return Carta
