--!strict
-- Geometria dos túneis e da trincheira sul (caixas orientadas), usada por FeatureBuilder (forro
-- de peças, assado no Lune) e por TerrainBuilder (escavação do terreno no Studio).
-- Recebe o ambiente (CFrame/Vector3) para rodar igual no Roblox e no Lune.
local TunnelGeometry = {}

local M = 0.28

export type Box = { cf: any, size: any, kind: string, name: string }

-- center: posição (studs) do centro de An Cường (2); heightAt: altura do chão (studs) em (x, z)
function TunnelGeometry.build(
	env: any,
	Tunnels: any,
	cx: number,
	cz: number,
	heightAt: (number, number) -> number
): { Box }
	local V, CF = env.Vector3, env.CFrame
	local W, H = Tunnels.WIDTH_M / M, Tunnels.HEIGHT_M / M
	local DEPTH = Tunnels.DEPTH_M / M
	local S = Tunnels.SHAFT_M / M
	local T = 1 -- espessura do forro (studs)
	local boxes: { Box } = {}
	local function floorAt(name: string): any
		local n = Tunnels.nodes[name]
		local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
		return V.new(x, heightAt(x, z) - DEPTH, z)
	end
	-- trechos de túnel: piso, teto e paredes ao longo de cada aresta
	for i, e in Tunnels.edges do
		local a, b = floorAt(e[1]), floorAt(e[2])
		local ya, yb = a.Y + H / 2, b.Y + H / 2
		local pa, pb = V.new(a.X, ya, a.Z), V.new(b.X, yb, b.Z)
		local len = (pb - pa).Magnitude
		local base = CF.lookAt((pa + pb) / 2, pb)
		local name = "Tunnel_" .. i
		table.insert(
			boxes,
			{ cf = base, size = V.new(W + 2 * T + 1, H + 2 * T + 1, len + 1), kind = "carve", name = name }
		)
		table.insert(
			boxes,
			{ cf = base * CF.new(0, -(H + T) / 2, 0), size = V.new(W + 2 * T, T, len + T), kind = "floor", name = name }
		)
		table.insert(boxes, {
			cf = base * CF.new(0, (H + T) / 2, 0),
			size = V.new(W + 2 * T, T, len + T),
			kind = "ceiling",
			name = name,
		})
		table.insert(
			boxes,
			{ cf = base * CF.new(-(W + T) / 2, 0, 0), size = V.new(T, H, len), kind = "wall", name = name }
		)
		table.insert(
			boxes,
			{ cf = base * CF.new((W + T) / 2, 0, 0), size = V.new(T, H, len), kind = "wall", name = name }
		)
	end
	-- câmaras nas junções e poços de entrada
	for name, n in Tunnels.nodes do
		local f = floorAt(name)
		local x, z = f.X, f.Z
		if n.entrance then
			local top = heightAt(x, z)
			local h = top - f.Y + 0.5
			local mid = CF.new(x, f.Y + h / 2, z)
			table.insert(boxes, { cf = mid, size = V.new(4.5, h + 2, 4.5), kind = "carve", name = "Shaft_" .. name })
			for _, o in
				{
					{ S / 2 + 0.5, 0, 1, S + 2 },
					{ -(S / 2 + 0.5), 0, 1, S + 2 },
					{ 0, S / 2 + 0.5, S + 2, 1 },
					{ 0, -(S / 2 + 0.5), S + 2, 1 },
				}
			do
				-- paredes do poço só acima da altura do túnel (a base fica aberta para o túnel)
				local wallH = h - H
				local cyw = f.Y + H + wallH / 2
				table.insert(boxes, {
					cf = CF.new(x + o[1], cyw, z + o[2]),
					size = V.new(o[3], wallH, o[4]),
					kind = "shaftwall",
					name = "Shaft_" .. name,
				})
			end
			table.insert(
				boxes,
				{ cf = CF.new(x, f.Y + h / 2, z), size = V.new(2, h, 2), kind = "truss", name = "Shaft_" .. name }
			)
			table.insert(
				boxes,
				{ cf = CF.new(x, top + 0.1, z), size = V.new(S + 2, 0.2, S + 2), kind = "entrance", name = name }
			)
		else
			table.insert(boxes, {
				cf = CF.new(x, f.Y + H / 2, z),
				size = V.new(W * 2 + 2, H + 2, W * 2 + 2),
				kind = "carve",
				name = "Chamber_" .. name,
			})
			table.insert(boxes, {
				cf = CF.new(x, f.Y - 0.5, z),
				size = V.new(W * 2 + 2, 1, W * 2 + 2),
				kind = "floor",
				name = "Chamber_" .. name,
			})
			table.insert(boxes, {
				cf = CF.new(x, f.Y + H + 0.5, z),
				size = V.new(W * 2 + 2, 1, W * 2 + 2),
				kind = "ceiling",
				name = "Chamber_" .. name,
			})
		end
	end
	-- trincheira sul: só escavação (as paredes ficam de terra)
	local TW, TD = Tunnels.TRENCH_W_M / M, Tunnels.TRENCH_D_M / M
	for i = 1, #Tunnels.trench - 1 do
		local p1, p2 = Tunnels.trench[i], Tunnels.trench[i + 1]
		local x1, z1 = Tunnels.toWorld(cx, cz, p1[1], p1[2])
		local x2, z2 = Tunnels.toWorld(cx, cz, p2[1], p2[2])
		local y1, y2 = heightAt(x1, z1), heightAt(x2, z2)
		local a, b = V.new(x1, (y1 - TD / 2), z1), V.new(x2, (y2 - TD / 2), z2)
		local len = (b - a).Magnitude
		table.insert(boxes, {
			cf = CF.lookAt((a + b) / 2, b),
			size = V.new(TW, TD + 2, len + TW),
			kind = "carve",
			name = "Trench_" .. i,
		})
	end
	return boxes
end

return TunnelGeometry
