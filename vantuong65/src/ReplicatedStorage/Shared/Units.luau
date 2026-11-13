--!strict
-- Unidades reais <-> studs. 1 stud = 0,28 m (create.roblox.com/docs/physics/units).
local Units = {}

Units.STUD_M = 0.28

function Units.toStuds(meters: number): number
	return meters / Units.STUD_M
end

function Units.toMeters(studs: number): number
	return studs * Units.STUD_M
end

-- Velocidades PROVISÓRIAS da F1 (o movimento real com ControllerManager entra na F2).
-- m/s -> studs/s
Units.Speed = {
	walk = 1.4 / Units.STUD_M, -- caminhada
	jog = 3.1 / Units.STUD_M, -- corrida leve (padrão da F1 para medir travessia)
	sprint = 5.5 / Units.STUD_M, -- corrida com fôlego (F2)
}

-- Soldado de 2,0 m = 7,14 studs (D-98, decisão do dono; era 1,75 m da Parte 2). O mesmo de
-- Shared/Corpo.HEIGHT_M (aqui sem o require, para não criar ciclo).
Units.SOLDIER_HEIGHT = 2.0 / Units.STUD_M

return Units
