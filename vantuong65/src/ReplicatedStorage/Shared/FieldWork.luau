--!strict
-- Pá de trincheira e medevac (Parte 11, "Lançamento"). Módulo puro: as regras.
-- Pá: cavar um buraco de combate de 2 homens com parapeito de sacos de areia, fora da água, longe da
-- base inimiga e com limite por minuto (custo de replicação do terreno).
-- D-183 (dono: "ela n esta funcionando"): antes, só em setor do próprio lado. No começo os EUA só têm
-- D e E e o VC A e B, então no meio do mapa, onde se luta, a pá sempre recusava ("só em setor do seu
-- lado", Studio 2026-11-16). Agora cava em qualquer chão de terra, menos perto da base inimiga.
-- Medevac: ferido grave (caído) junto a um UH-34D pousado é evacuado; o time recebe suprimento
-- (o jogo não tem recurso de "mão de obra": o suprimento faz esse papel, D-48).
local FieldWork = {}

FieldWork.DIG = {
	seconds = 8, -- tempo de jogo (cavar de verdade leva muito mais: compressão de design)
	perMinute = 1, -- por jogador
	maxTotal = 80, -- buracos por partida no mapa todo
	-- buraco de 2 homens (manual de campo: ~1,8 x 0,6 x 1,2 m). D-183: o terreno do Roblox tem voxel
	-- de 1,12 m e a pegada de 0,6 m virava 1 voxel de largura, que a suavização deixava com 0,62 m de
	-- fundo (Studio, 2026-11-16). Agora são 2 x 2 voxels (2,24 m de lado) alinhados à grade.
	lengthM = 2.24,
	widthM = 2.24,
	depthM = 1.2,
	aheadM = 1.7, -- à frente de quem cava (centro do buraco; a grade desloca até 0,56 m)
	stillM = 1.0, -- quem se afasta mais que isso cancela
	enemyHqM = 75, -- D-183: não cava perto da base inimiga (o mesmo do ponto de reunião, Front)
}
FieldWork.VOXEL_M = 1.12 -- voxel do terreno (4 studs de 0,28 m)

FieldWork.MEDEVAC = {
	radiusM = 15, -- ferido a até 15 m do helicóptero
	seconds = 5, -- embarque
	maxHeliSpeedMs = 1, -- helicóptero parado
	maxHeliAltM = 2, -- e pousado
	supply = 25, -- PLACEHOLDER: suprimento devolvido ao time por ferido evacuado
}

-- Pode cavar? enemyHqDistM: distância (m) até a base inimiga (nil = sem base). Devolve ok, o motivo da
-- recusa e, no limite por minuto, quantos segundos faltam (o aviso "Pá: próximo buraco em %d s").
function FieldWork.canDig(
	enemyHqDistM: number?,
	onWater: boolean,
	lastDig: number?,
	now: number,
	total: number
): (boolean, string?, number?)
	if onWater then
		return false, "não dá para cavar na água", nil
	end
	if enemyHqDistM and enemyHqDistM < FieldWork.DIG.enemyHqM then
		return false, "perto da base inimiga não dá", nil
	end
	local gap = 60 / FieldWork.DIG.perMinute
	if lastDig and now - lastDig < gap then
		return false, "limite: 1 buraco por minuto", math.max(1, math.ceil(gap - (now - lastDig)))
	end
	if total >= FieldWork.DIG.maxTotal then
		return false, "limite de buracos no mapa", nil
	end
	return true, nil, nil
end

-- D-183: a pegada do buraco, 2 x 2 voxels alinhados à grade do terreno (studs de `voxelS`): o canto
-- comum dos 4 voxels mais perto do ponto pedido. Devolve o centro (X, Z) e a metade do lado.
function FieldWork.holeGrid(x: number, z: number, voxelS: number): (number, number, number)
	return math.round(x / voxelS) * voxelS, math.round(z / voxelS) * voxelS, voxelS
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
