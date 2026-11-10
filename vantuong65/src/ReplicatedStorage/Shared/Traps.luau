--!strict
-- Armadilhas VC (Parte 11, "Depois"): estacas punji e granada com fio. O sapador VC arma; o
-- engenheiro EUA detecta (agachado ou deitado, perto) e desarma. Assimetria real entre as
-- facções. Módulo puro: as regras. Números de design (PLACEHOLDER) até playtest.
local Traps = {}

export type Kind = {
	name: string,
	radiusM: number, -- distância do centro que dispara
	armDelayS: number, -- tempo até ficar armada depois de posta (o sapador sai de perto)
	fuseS: number, -- granada: espoleta depois do fio puxado
}

Traps.KINDS = {
	-- buraco com estacas (pé e canela): ferimento na perna, sangramento
	punji = { name = "Estacas punji", radiusM = 0.5, armDelayS = 3, fuseS = 0 },
	-- granada de cabo presa a um fio de ~3 m na altura da canela
	tripwire = { name = "Granada com fio", radiusM = 1.5, armDelayS = 3, fuseS = 1.0 },
} :: { [string]: Kind }

Traps.PUNJI_ENERGY_J = 350 -- energia de ferimento na perna (Medical): ferida, não morte
Traps.DETECT_M = 6 -- o engenheiro EUA percebe a armadilha a esta distância...
Traps.DETECT_SLOW_MS = 1.2 -- ...andando devagar (agachado/deitado ou parado)
Traps.CAREFUL_MS = 0.6 -- abaixo disto, quem passa por cima tem metade da chance de disparar
Traps.DISARM_S = 4

-- Chance de disparar ao pisar (dentro do raio). Detectada não dispara para quem a detectou.
function Traps.triggerChance(speedMs: number, detected: boolean): number
	if detected then
		return 0
	end
	if speedMs < 0.15 then
		return 0 -- parado em cima não pisa de novo
	end
	return if speedMs < Traps.CAREFUL_MS then 0.5 else 1
end

-- Quem dispara: só o lado inimigo de quem armou, e só depois de armada.
function Traps.canTrigger(trapFaction: string, victimFaction: string?, armedAt: number, now: number): boolean
	return victimFaction ~= nil and victimFaction ~= trapFaction and now >= armedAt
end

-- O engenheiro EUA detecta: perto, devagar e de lado inimigo.
function Traps.detects(role: string?, faction: string?, trapFaction: string, distM: number, speedMs: number): boolean
	return role == "engineer"
		and faction ~= nil
		and faction ~= trapFaction
		and distM <= Traps.DETECT_M
		and speedMs <= Traps.DETECT_SLOW_MS
end

-- Pode desarmar: engenheiro do outro lado, com a armadilha já detectada.
function Traps.canDisarm(role: string?, faction: string?, trapFaction: string, detected: boolean): boolean
	return role == "engineer" and faction ~= nil and faction ~= trapFaction and detected
end

return Traps
