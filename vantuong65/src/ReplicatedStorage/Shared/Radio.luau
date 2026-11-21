--!strict
-- Operador de rádio (Parte 11, "Lançamento"): só quem carrega o rádio do squad fala com o comandante
-- (canal Comando). Se ele morre, o rádio cai e o squad perde o link até um aliado pegar o rádio.
-- Módulo puro: as regras. O RadioService põe a antena nas costas e cuida do rádio caído.
local Radio = {}

-- D-108 (classes mais simples): o operador de rádio saiu; o líder do squad nasce com o rádio.
Radio.ROLE = "squad_leader"
Radio.TTL_S = 300 -- o rádio caído some em 5 min (o squad fica sem link até o líder nascer de novo)

-- Fala no canal Comando? O comandante sempre; de resto, só quem carrega o rádio (D-108: a equipe de
-- morteiro saiu; o tiro de morteiro é do comandante).
function Radio.canTalkToCommand(role: string?, carriesRadio: boolean): boolean
	return role == "commander" or carriesRadio
end

-- Nasce com o rádio?
function Radio.startsWithRadio(role: string?): boolean
	return role == Radio.ROLE
end

-- Pode pegar o rádio caído? Só alguém do mesmo lado, vivo.
function Radio.canPickUp(dropFaction: string?, faction: string?, alive: boolean): boolean
	return alive and dropFaction ~= nil and dropFaction == faction
end

-- O squad tem link com o comando? (alguém dele carrega o rádio)
function Radio.squadLinked(members: { { carries: boolean } }): boolean
	for _, m in members do
		if m.carries then
			return true
		end
	end
	return false
end

return Radio
