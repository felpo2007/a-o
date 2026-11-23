--!strict
-- D-199 (prompt de jogabilidade, item 18): como o rotor aparece pela rotação e pela distância.
-- - parado e partindo, as pás da malha giram de verdade e se veem inteiras;
-- - com a rotação subindo, elas somem (o quadro da tela não acompanha: a 220 rpm uma pá passa 15
--   vezes por segundo, e a 60 quadros por segundo ela pularia 22° a cada quadro) e entra o disco
--   borrado (tools/rotor_borrao.py), que gira devagar e mostra o plano do rotor;
-- - longe, o disco fica mais fraco, como as pás finas a centenas de metros.
-- Puro: o VehicleFx e o HeliEvento usam; o teste do Lune confere os números.
local RotorVisual = {}

RotorVisual.PAS = { 0.3, 0.7 } -- fração da rotação em que as pás da malha vão sumindo
RotorVisual.DISCO = { 0.22, 0.62 } -- e em que o disco borrado aparece
RotorVisual.LONGE_M = { 80, 700 } -- distância (m) em que o disco começa a enfraquecer e chega ao mínimo
RotorVisual.LONGE_MIN = 0.45 -- força do disco longe
RotorVisual.GIRO_HZ = 0.55 -- voltas por segundo do disco na rotação cheia

function RotorVisual.suave(x: number, a: number, b: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Transparência das pás da malha e do disco borrado (0 = inteiro, 1 = some), pela rotação (0..1)
-- e pela distância da câmera (m).
function RotorVisual.estado(rotor: number, distM: number): (number, number)
	local r = math.clamp(rotor, 0, 1)
	local pas = RotorVisual.suave(r, RotorVisual.PAS[1], RotorVisual.PAS[2])
	local longe = RotorVisual.suave(distM, RotorVisual.LONGE_M[1], RotorVisual.LONGE_M[2])
	local forca = RotorVisual.suave(r, RotorVisual.DISCO[1], RotorVisual.DISCO[2])
		* (1 - (1 - RotorVisual.LONGE_MIN) * longe)
	return pas, 1 - forca
end

-- Velocidade de giro do disco (rad/s): devagar, e só quando o rotor gira.
function RotorVisual.giro(rotor: number): number
	return math.clamp(rotor, 0, 1) * RotorVisual.GIRO_HZ * 2 * math.pi
end

return RotorVisual
