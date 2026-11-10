--!strict
-- Pá de trincheira e medevac (Parte 11, "Lançamento"). Módulo puro: as regras.
-- Pá: cavar um buraco de combate de 2 homens com parapeito de sacos de areia, só em setor próprio,
-- fora da água e com limite por minuto (custo de replicação do terreno).
-- Medevac: ferido grave (caído) junto a um UH-34D pousado é evacuado; o time recebe suprimento
-- (o jogo não tem recurso de "mão de obra": o suprimento faz esse papel, D-48).
local FieldWork = {}

FieldWork.DIG = {
	seconds = 8, -- tempo de jogo (cavar de verdade leva muito mais: compressão de design)
	perMinute = 1, -- por jogador
	maxTotal = 80, -- buracos por partida no mapa todo
	lengthM = 1.8, -- buraco de 2 homens (manual de campo: ~1,8 x 0,6 x 1,2 m)
	widthM = 0.6,
	depthM = 1.2,
	aheadM = 1.5, -- à frente de quem cava
	stillM = 1.0, -- quem se afasta mais que isso cancela
}

FieldWork.MEDEVAC = {
	radiusM = 15, -- ferido a até 15 m do helicóptero
	seconds = 5, -- embarque
	maxHeliSpeedMs = 1, -- helicóptero parado
	maxHeliAltM = 2, -- e pousado
	supply = 25, -- PLACEHOLDER: suprimento devolvido ao time por ferido evacuado
}

-- Pode cavar? Devolve ok e o motivo da recusa.
function FieldWork.canDig(
	sectorOwner: string?,
	faction: string?,
	onWater: boolean,
	lastDig: number?,
	now: number,
	total: number
): (boolean, string?)
	if onWater then
		return false, "não dá para cavar na água"
	end
	if sectorOwner == nil or sectorOwner ~= faction then
		return false, "só em setor do seu lado"
	end
	if lastDig and now - lastDig < 60 / FieldWork.DIG.perMinute then
		return false, "limite: 1 buraco por minuto"
	end
	if total >= FieldWork.DIG.maxTotal then
		return false, "limite de buracos no mapa"
	end
	return true, nil
end

-- O helicóptero serve para medevac agora? (velocidade em m/s, altura sobre o chão em m)
function FieldWork.heliReady(speedMs: number, altM: number, destroyed: boolean): boolean
	local C = FieldWork.MEDEVAC
	return not destroyed and speedMs <= C.maxHeliSpeedMs and altM <= C.maxHeliAltM
end

-- Acumula o embarque de um ferido. Devolve o novo tempo e se terminou.
function FieldWork.boarding(t: number, near: boolean, dt: number): (number, boolean)
	if not near then
		return 0, false
	end
	local nt = t + dt
	return nt, nt >= FieldWork.MEDEVAC.seconds
end

return FieldWork
