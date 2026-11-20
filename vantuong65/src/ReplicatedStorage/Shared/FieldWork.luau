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
	-- D-195 (prompt de jogabilidade, item 13: "pressionar RT a cada cavada"): a pá fica na mão e cada
	-- aperto do gatilho (clique, toque) é uma pazada; o buraco desce um pouco a cada uma. Antes era
	-- uma ação de 8 s que fazia o buraco inteiro no fim.
	pazadas = 6, -- para o buraco inteiro (6 x 1,4 s ~ os 8 s de antes)
	pazadaS = 1.4, -- uma pazada: a animação (ItemAnim.PA.periodo) e o som pa_cavar
	contatoS = 0.35, -- a lâmina crava: a terra sai nesse instante
	-- folga da cadência no servidor (rede e engasgo do servidor): com 0,15 s um aperto a 1,55 s do
	-- anterior foi recusado no Studio (o cliente segura 1,4 s; o servidor só barra o abuso)
	folgaS = 0.3,
	bordaM = 0.15, -- as bordas descem até isto nas 2 primeiras (irregulares: 50 a 100%)
	monteM = 0.3, -- a terra tirada sobe à frente, no lado do parapeito (70 a 100%)
	juntoM = 1.2, -- pazada a até isto do centro de um buraco começado continua nele
	alcanceM = 3.2, -- no contato, quem cava tem que estar a até isto do meio do buraco (à frente 1,7 + 1,2 + folga)
	perMinute = 1, -- buracos novos por jogador
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

-- ===== D-195: as pazadas =====
-- Pode dar a pazada agora? Uma por pazadaS (o servidor aceita folgaS antes, pela rede); o excesso é
-- jogado fora, não vira fila.
function FieldWork.podePazada(last: number?, now: number): boolean
	local D = FieldWork.DIG
	return last == nil or now - last >= D.pazadaS - D.folgaS
end

-- Coluna da grade 4 x 4 de voxels em volta do buraco (ix, iz de 1 a 4, do menor X/Z ao maior): as 4
-- do meio são o buraco; a fileira do lado para onde quem começou olhava (ax, az: o eixo, ±1 ou 0) é
-- o monte da terra tirada; o resto é a borda.
function FieldWork.coluna(ix: number, iz: number, ax: number, az: number): string
	if ix >= 2 and ix <= 3 and iz >= 2 and iz <= 3 then
		return "buraco"
	end
	if (ax > 0 and ix == 4) or (ax < 0 and ix == 1) or (az > 0 and iz == 4) or (az < 0 and iz == 1) then
		return "monte"
	end
	return "borda"
end

-- 0..1 fixo por coluna (a mesma borda a cada pazada e em todo servidor)
function FieldWork.jitter(cx: number, cz: number, ix: number, iz: number): number
	local h = (math.floor(cx) * 73856093 + math.floor(cz) * 19349663 + ix * 83492791 + iz * 2654435761) % 1000003
	return (h % 1000) / 999
end

-- Quanto a coluna sobe (+) ou desce (−), em m, depois de k pazadas de n: o buraco desce por igual
-- até fundoM; a borda desce nas 2 primeiras (a depressão do começo); o monte sobe com a terra.
-- folgaM: o quanto a suavização do terreno come (Studio, D-195: pedindo 0,3 m na 1ª pazada o chão
-- não mudava; 0,6 m deu 0,07 m; depois, o visto ficava ~0,56 m abaixo do pedido). Com a folga desde a
-- 1ª pazada, o fundo visto desce por igual a cada pazada.
function FieldWork.alturaColuna(tipo: string, k: number, n: number, fundoM: number, j: number, folgaM: number?): number
	local D = FieldWork.DIG
	local f = math.clamp(k / math.max(n, 1), 0, 1)
	if tipo == "buraco" then
		if k <= 0 then
			return 0
		end
		local folga = math.clamp(folgaM or 0, 0, fundoM)
		return -(folga + (fundoM - folga) * f)
	elseif tipo == "monte" then
		return D.monteM * f * (0.7 + 0.3 * j)
	end
	return -D.bordaM * math.min(math.max(k, 0), 2) / 2 * (0.5 + 0.5 * j)
end

-- Topo de uma coluna de voxels (de baixo para cima; y0 = base do 1º voxel), em studs.
function FieldWork.topoColuna(occs: { number }, y0: number, voxelS: number): number
	for y = #occs, 1, -1 do
		if occs[y] > 0 then
			return y0 + (y - 1) * voxelS + occs[y] * voxelS
		end
	end
	return y0
end

-- A coluna com o topo em alvoY, partindo da coluna original (mats, occs). Descendo: acima vira ar e o
-- voxel do topo fica com a ocupação proporcional, com a terra mexida (chao) no lugar do capim (os
-- materiais em `troca`); subindo: a terra (chao) enche até alvoY, sem mexer no que está embaixo.
function FieldWork.colunaVoxels(
	mats: { any },
	occs: { number },
	y0: number,
	voxelS: number,
	alvoY: number,
	chao: any,
	ar: any,
	troca: { [any]: boolean }
): ({ any }, { number })
	local nm, no = table.clone(mats), table.clone(occs)
	local topo = FieldWork.topoColuna(occs, y0, voxelS)
	for y = 1, #occs do
		local yb = y0 + (y - 1) * voxelS
		if alvoY < topo then
			if yb >= alvoY then
				nm[y], no[y] = ar, 0
			elseif yb + voxelS > alvoY then
				no[y] = math.min(no[y], (alvoY - yb) / voxelS)
				if nm[y] == ar or troca[nm[y]] then
					nm[y] = chao
				end
			end
		elseif alvoY > topo and yb < alvoY and yb + voxelS > topo - 1e-6 then
			local want = math.min((alvoY - yb) / voxelS, 1)
			if want > no[y] then
				no[y] = want
				if nm[y] == ar or troca[nm[y]] then
					nm[y] = chao
				end
			end
		end
	end
	return nm, no
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
