--!strict
-- D-233: alívio de desenho da expansão (D-232). Longe da câmera, somem só peças sem colisão e que não
-- escondem ninguém: as raízes, a samambaia e o piso das casas térreas. Móvel e objeto de quintal ficam
-- sempre visíveis, porque têm colisão: sumir com eles deixaria uma barreira invisível à distância.
-- Módulo puro: o servidor marca as peças e o cliente (Controllers/ExpansaoLod) decide.
local ExpansaoLod = {}

ExpansaoLod.TAG = "VT65ExpLod"
ExpansaoLod.ATRIBUTO = "VT65LodM"
ExpansaoLod.FOLGA = 1.08 -- some um pouco depois de onde volta: a peça não pisca no limite

local M = 0.28
local TERREAS = {
	exp_abrigo = true,
	exp_casa_vala = true,
	exp_casa_verde = true,
	exp_casas_ligadas = true,
	exp_celeiro = true,
}
-- D-235: nos sobrados o piso aparece por baixo das colunas e no alpendre. A 90 m, com zoom, a troca não
-- se vê: o chão embaixo é a mesma terra do patamar.
local SOBRADOS = {
	exp_sobrado_a = true,
	exp_sobrado_b = true,
	exp_sobrado_c = true,
	exp_sobrado_d = true,
}

-- Distância (m) a partir da qual a peça some, ou nil se ela fica sempre.
function ExpansaoLod.limiteM(chave: string, peca: string): number?
	if string.sub(chave, 1, 4) ~= "exp_" then
		return nil
	end
	if string.sub(peca, 1, 6) == "Raizes" then
		return if chave == "exp_figueira" then 70 else 45
	end
	if chave == "exp_samambaia" and string.sub(peca, 1, 6) == "Folhas" then
		return 55
	end
	if peca == "Trim_P" and TERREAS[chave] then
		return 70
	end
	if peca == "Trim_P" and SOBRADOS[chave] then
		return 90
	end
	return nil
end

-- Opção de detalhe do jogador (1, 0,6 ou 0,3): com menos detalhe, o corte chega mais perto.
function ExpansaoLod.fator(detalhe: number): number
	return math.clamp(0.45 + 0.55 * detalhe, 0.5, 1)
end

function ExpansaoLod.esconde(distStuds: number, limiteM: number, detalhe: number, estava: boolean): boolean
	local limite = limiteM * ExpansaoLod.fator(detalhe) / M
	return distStuds > (if estava then limite else limite * ExpansaoLod.FOLGA)
end

return ExpansaoLod
