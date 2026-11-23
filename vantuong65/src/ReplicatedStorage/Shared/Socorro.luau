--!strict
-- D-236 (dono: "melhore o jeito de curar os aliados"). A regra de quem o soldado socorre, pura e testada
-- no Lune. Antes valia o companheiro mais perto a até 3 m, mesmo sem ferimento, sem nada na tela dizendo
-- quem estava ferido nem o que a tecla ia fazer.
-- Agora: quem precisa vem primeiro (caído, sangrando, ferido), desempatando por quem está na mira.
local Medical = require(script and (script :: any).Parent.Medical or "./Medical") :: any

local Socorro = {}

Socorro.ALCANCE_M = 4.5 -- o servidor confere o mesmo número (o caído fica deitado, longe do centro do corpo)
Socorro.VISTA_MEDICO_M = 70 -- o médico vê a cruz de todo companheiro ferido até aqui
Socorro.VISTA_CAIDO_M = 35 -- qualquer soldado vê a cruz de quem caiu até aqui
Socorro.MAX_MARCAS = 8

export type Aliado = {
	downed: boolean,
	hurt: boolean,
	bleeding: boolean,
	frac: number, -- vida, 0..1
	distM: number,
	angDeg: number, -- quanto está fora do centro da mira
}

export type Acao = {
	op: string?, -- nil: não dá para fazer agora (motivo diz por quê)
	titulo: string,
	segundos: number,
	motivo: string?,
}

function Socorro.precisa(a: Aliado): boolean
	return a.downed or a.bleeding or a.hurt
end

-- Menor é mais urgente. A classe pesa mais que a distância; dentro dela, a mira decide.
function Socorro.nota(a: Aliado): number
	local classe = if a.downed then 0 elseif a.bleeding then 1000 elseif a.hurt then 2000 else 9000
	return classe + a.angDeg + a.distM * 6
end

-- O que a tecla faz neste companheiro, ou nil se ele não precisa de nada
function Socorro.acao(a: Aliado, isMedic: boolean, bandages: number): Acao?
	local C = Medical.C
	if a.downed then
		if isMedic then
			return { op = "revive", titulo = "REANIMAR", segundos = C.reviveTime }
		end
		return { op = nil, titulo = "REANIMAR", segundos = 0, motivo = "Só o médico reanima" }
	elseif a.bleeding or a.hurt then
		if isMedic then
			return { op = "treat", titulo = "TRATAR", segundos = C.medicTreat }
		elseif bandages > 0 then
			return { op = "bandage", titulo = "CURATIVO", segundos = C.bandageOther }
		end
		return { op = nil, titulo = "CURATIVO", segundos = 0, motivo = "Sem curativos" }
	end
	return nil
end

-- Quem recebe a cruz no mundo: caído perto para todos; ferido, só para o médico
function Socorro.marca(a: Aliado, isMedic: boolean): boolean
	if a.downed then
		return a.distM <= (if isMedic then Socorro.VISTA_MEDICO_M else Socorro.VISTA_CAIDO_M)
	end
	return isMedic and (a.bleeding or a.hurt) and a.distM <= Socorro.VISTA_MEDICO_M
end

return Socorro
