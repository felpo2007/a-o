--!strict
-- Fumaça (granada de fumaça): bloqueia VISÃO (bots, assistência de mira), não balas. As nuvens não
-- são peças consultáveis por raycast (senão parariam tiros); o teste é geométrico: segmento x esfera.
local Smoke = {}

Smoke.DURATION_S = 60 -- PLACEHOLDER (granada de fumaça da época: confirmar em manual)
Smoke.RADIUS_M = 6 -- PLACEHOLDER (raio útil da nuvem formada)

export type Cloud = { x: number, y: number, z: number, r: number }

-- O segmento a→b passa por dentro de alguma nuvem?
function Smoke.blocks(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	clouds: { Cloud }
): boolean
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local len2 = dx * dx + dy * dy + dz * dz
	for _, c in clouds do
		local t = 0
		if len2 > 0 then
			t = math.clamp(((c.x - ax) * dx + (c.y - ay) * dy + (c.z - az) * dz) / len2, 0, 1)
		end
		local px, py, pz = ax + dx * t, ay + dy * t, az + dz * t
		if (px - c.x) ^ 2 + (py - c.y) ^ 2 + (pz - c.z) ^ 2 <= c.r * c.r then
			return true
		end
	end
	return false
end

-- Nuvens ativas a partir da pasta workspace.Smoke (atributo "R" em studs).
function Smoke.clouds(folder: Instance?): { Cloud }
	local out = {}
	if not folder then
		return out
	end
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			local r = p:GetAttribute("R")
			table.insert(
				out,
				{ x = p.Position.X, y = p.Position.Y, z = p.Position.Z, r = if type(r) == "number" then r else 20 }
			)
		end
	end
	return out
end

return Smoke
