--!strict
-- D-151 (pedido do dono: "as árvores devem tancar os tiros"): o tronco que para a bala e o soldado é
-- uma peça invisível por cilindro de TreeTrunks (medido na malha por tools/troncos.py), e não mais
-- a colisão automática da malha da madeira. Medido no Studio (v80): a Madeira0 da ph_tree_small_02
-- é a galhada lá em cima, então o tronco deixava a bala passar, e o coqueiro inteiro também.
-- Módulo puro (só CFrame e Vector3): o teste da F5 confere a conta.
local TrunkProxy = {}

TrunkProxy.PREFIX = "Tronco_"

function TrunkProxy.isProxy(name: string): boolean
	return string.sub(name, 1, #TrunkProxy.PREFIX) == TrunkProxy.PREFIX
end

-- Cilindro (a -> b, raio r; studs na escala 1, espaço do modelo) -> CFrame relativo ao pivô e tamanho
-- da peça. O cilindro do Roblox tem o eixo em X.
function TrunkProxy.frame(c: { a: { number }, b: { number }, r: number }, scale: number): (CFrame, Vector3)
	local a = Vector3.new(c.a[1], c.a[2], c.a[3]) * scale
	local b = Vector3.new(c.b[1], c.b[2], c.b[3]) * scale
	local axis = b - a
	local x = axis.Unit
	local ref = if math.abs(x.Y) < 0.99 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	local y = (ref - x * ref:Dot(x)).Unit
	return CFrame.fromMatrix((a + b) / 2, x, y), Vector3.new(axis.Magnitude, 2 * c.r * scale, 2 * c.r * scale)
end

return TrunkProxy
