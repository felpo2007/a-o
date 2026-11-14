--!strict
-- Ligações da rede de túneis sob An Cường (2) (D-90): qual entrada leva a qual, por onde e quanto
-- se anda lá embaixo. Módulo PURO (Lune e jogo), lido pelos bots do VC (Modules/BotTunnels) e
-- pensado para a carta do VC (outro agente): `TunnelLinks.links()` é a tabela pronta.
-- Traçado de design (Shared/Tunnels): entradas E1..E5, junções J1..J3, arestas retas. Só o VC usa
-- os túneis (regra do dono, 2026-11-11); TunnelService tira de lá quem é dos EUA.
-- Unidades: metros relativos ao centro da vila (x leste, z sul), como em Shared/Tunnels.
local Tunnels = require(script and (script :: any).Parent.Tunnels or "./Tunnels") :: any

local TunnelLinks = {}

export type Node = { id: string, x: number, z: number, entrance: boolean }
export type Link = {
	to: string, -- entrada de destino
	lengthM: number, -- quanto se anda no túnel (sem os poços)
	via: { string }, -- nós do caminho, da origem ao destino (inclusive)
}

local function node(id: string): Node
	local n = Tunnels.nodes[id]
	return { id = id, x = n.x, z = n.z, entrance = n.entrance == true }
end

local function dist(a: string, b: string): number
	local p, q = Tunnels.nodes[a], Tunnels.nodes[b]
	return math.sqrt((p.x - q.x) ^ 2 + (p.z - q.z) ^ 2)
end

-- Vizinhos de cada nó: { [id] = { { id, lengthM } } }
function TunnelLinks.adjacency(): { [string]: { { id: string, lengthM: number } } }
	local adj: { [string]: { { id: string, lengthM: number } } } = {}
	for id in Tunnels.nodes do
		adj[id] = {}
	end
	for _, e in Tunnels.edges do
		local a, b = e[1], e[2]
		local l = dist(a, b)
		table.insert(adj[a], { id = b, lengthM = l })
		table.insert(adj[b], { id = a, lengthM = l })
	end
	return adj
end

-- Caminho mais curto (Dijkstra; a rede é pequena) de um nó a outro: nós e comprimento (m).
-- blocked: nós fechados (entrada destruída pelo engenheiro, desabamento).
function TunnelLinks.path(from: string, to: string, blocked: { [string]: boolean }?): ({ string }?, number)
	if not Tunnels.nodes[from] or not Tunnels.nodes[to] then
		return nil, math.huge
	end
	local adj = TunnelLinks.adjacency()
	local d: { [string]: number } = { [from] = 0 }
	local prev: { [string]: string } = {}
	local done: { [string]: boolean } = {}
	while true do
		local best, bestD = nil :: string?, math.huge
		for id, v in d do
			if not done[id] and v < bestD then
				best, bestD = id, v
			end
		end
		if not best then
			return nil, math.huge
		end
		local cur = best :: string
		if cur == to then
			break
		end
		done[cur] = true
		for _, nb in adj[cur] do
			local okNode = not (blocked and blocked[nb.id]) or nb.id == to
			if okNode and not done[nb.id] then
				local nd = bestD + nb.lengthM
				if nd < (d[nb.id] or math.huge) then
					d[nb.id] = nd
					prev[nb.id] = cur
				end
			end
		end
	end
	local out = { to }
	local k = to
	while prev[k] do
		k = prev[k]
		table.insert(out, 1, k)
	end
	return out, d[to]
end

-- Entradas, em ordem (E1, E2...).
function TunnelLinks.entrances(): { Node }
	local out: { Node } = {}
	for id, n in Tunnels.nodes do
		if n.entrance then
			table.insert(out, node(id))
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- A tabela da carta: para cada entrada, as outras entradas a que ela leva, do mais perto ao mais
-- longe, com o comprimento e os nós do caminho. blocked: entradas fechadas (não saem nem entram).
-- Exemplo: links().E1 = { { to = "E2", lengthM = 113.1, via = { "E1", "J1", "E2" } }, ... }
function TunnelLinks.links(blocked: { [string]: boolean }?): { [string]: { Link } }
	local out: { [string]: { Link } } = {}
	local ents = TunnelLinks.entrances()
	for _, a in ents do
		local list: { Link } = {}
		if not (blocked and blocked[a.id]) then
			for _, b in ents do
				if b.id ~= a.id and not (blocked and blocked[b.id]) then
					local via, len = TunnelLinks.path(a.id, b.id, blocked)
					if via then
						table.insert(list, { to = b.id, lengthM = len, via = via })
					end
				end
			end
		end
		table.sort(list, function(p, q)
			return p.lengthM < q.lengthM
		end)
		out[a.id] = list
	end
	return out
end

-- Pontos do caminho no quadro do jogo (studs), a partir do centro da vila (cx, cz).
function TunnelLinks.toWorld(via: { string }, cx: number, cz: number): { { id: string, x: number, z: number } }
	local out = {}
	for _, id in via do
		local n = Tunnels.nodes[id]
		local x, z = Tunnels.toWorld(cx, cz, n.x, n.z)
		table.insert(out, { id = id, x = x, z = z })
	end
	return out
end

return TunnelLinks
