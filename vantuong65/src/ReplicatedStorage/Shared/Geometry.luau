--!strict
-- Geometria do mapa: limites, setor de um ponto e referência de grade de 1965.
-- Sem dependências do Roblox: roda no Lune (testes) e no jogo.
local Geometry = {}

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }

function Geometry.inBounds(b: Bounds, x: number, z: number): boolean
	return x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ
end

-- Ponto em polígono (lista plana x1, z1, x2, z2, ...), regra par-ímpar.
function Geometry.pointInPolygon(poly: { number }, x: number, z: number): boolean
	local inside = false
	local n = #poly // 2
	local j = n
	for i = 1, n do
		local xi, zi = poly[2 * i - 1], poly[2 * i]
		local xj, zj = poly[2 * j - 1], poly[2 * j]
		if (zi > z) ~= (zj > z) then
			local xCross = (xj - xi) * (z - zi) / (zj - zi) + xi
			if x < xCross then
				inside = not inside
			end
		end
		j = i
	end
	return inside
end

-- Devolve o id do setor (1..5) que contém o ponto, ou nil fora da área.
function Geometry.sectorAt(sectors: { { id: number, polygon: { number } } }, x: number, z: number): number?
	for _, s in sectors do
		if Geometry.pointInPolygon(s.polygon, x, z) then
			return s.id
		end
	end
	return nil
end

-- Referência de grade militar de 1965 ("BS 702929") a partir do quadro local.
function Geometry.gridRef1965(origin: { e: number, n: number }, x: number, z: number, studM: number): string
	local e = origin.e + x * studM
	local n = origin.n - z * studM
	local sq = if n < 1700000 then "BS" else "BT"
	local ee = math.floor((e % 100000) / 100)
	local nn = math.floor((n % 100000) / 100)
	return string.format("%s %03d%03d", sq, ee, nn)
end

return Geometry
