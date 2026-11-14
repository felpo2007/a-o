--!strict
-- Aviso de granada perto (lote 24, pedido do dono: "coloque símbolo de granada perto: vermelho que vai
-- matar você e branco que vai dar dano"). Módulo puro: o cliente (Controllers/AvisoGranada) desenha;
-- aqui ficam a regra e a conta do anel, travadas em teste.
--   - "kill" (vermelho): dentro do raio letal da granada (Explosive.TYPES, lethalM) contado em pé. Em
--     pé é o pior caso: agachado ou atrás de cobertura o raio real é menor (ExplosionService), então o
--     vermelho nunca falta quando mataria;
--   - "hurt" (branco): fora do letal e até o raio de baixas (casualtyM), onde os estilhaços ferem;
--   - nada: mais longe, granada de fumaça, ou granada do próprio lado que não fere (fogo amigo
--     desligado, Medical.blocked). A sua própria granada fere você: aparece.
local Explosive = require(script and (script :: any).Parent.Explosive or "./Explosive") :: any
local Medical = require(script and (script :: any).Parent.Medical or "./Medical") :: any

local GrenadeWarn = {}

GrenadeWarn.MAX_SHOWN = 4 -- no máximo tantas granadas na tela (as mais perto)

-- tipo de explosivo da granada de cada lado (o mesmo que o FieldService detona)
function GrenadeWarn.typeFor(faction: string?): string
	return if faction == "VC" then "grenade_vc" else "grenade_us"
end

-- raios (m) da granada do lado: letal e de baixas
function GrenadeWarn.radii(faction: string?): (number, number)
	local t = Explosive.TYPES[GrenadeWarn.typeFor(faction)]
	return t.lethalM, t.casualtyM
end

-- "kill" | "hurt" | nil para um jogador a distM (m) de uma granada de mão.
-- kind: "frag" | "smoke"; mine: a granada é deste jogador (ela fere quem jogou).
function GrenadeWarn.level(
	distM: number,
	kind: string?,
	grenadeFaction: string?,
	myFaction: string?,
	mine: boolean
): string?
	if kind == "smoke" then
		return nil
	end
	if Medical.blocked(myFaction, grenadeFaction, mine) then
		return nil
	end
	local lethal, casualty = GrenadeWarn.radii(grenadeFaction)
	if distM <= lethal then
		return "kill"
	elseif distM <= casualty then
		return "hurt"
	end
	return nil
end

-- Ângulo (rad) da granada em volta do centro da tela, para o anel: 0 = à frente (em cima na tela),
-- positivo = à direita. look: para onde a câmera olha; dir: da câmera (ou do jogador) até a granada;
-- os dois no plano do chão (X, Z).
function GrenadeWarn.ringAngle(lookX: number, lookZ: number, dirX: number, dirZ: number): number
	local right = -dirX * lookZ + dirZ * lookX
	local ahead = dirX * lookX + dirZ * lookZ
	return math.atan2(right, ahead)
end

-- Ponto do anel (x, y) em pixels, a partir do centro (cx, cy) e do raio r: à frente fica em cima.
function GrenadeWarn.ringPoint(angle: number, cx: number, cy: number, r: number): (number, number)
	return cx + math.sin(angle) * r, cy - math.cos(angle) * r
end

return GrenadeWarn
