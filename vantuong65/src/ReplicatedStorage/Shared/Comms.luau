--!strict
-- Rodas radiais e mensagens predefinidas (Parte 12.5): nada exige digitar. Os itens ficam SEMPRE
-- na mesma posição (1 = topo, sentido horário), para criar memória muscular; item indisponível
-- aparece apagado, mas não sai do lugar.
local Comms = {}

Comms.MESSAGES = {
	attack = "Atacar o ponto marcado",
	defend = "Defender esta posição",
	regroup = "Reagrupar em mim",
	medic = "Preciso de médico",
	ammo = "Preciso de munição",
	contact = "Contato! Inimigo à vista",
	ok = "Entendido",
	no = "Negativo",
	no_radio = "Sem rádio: só o operador de rádio fala com o comandante",
} :: { [string]: string }

export type Item = { id: string, label: string }

-- Roda de equipamento (LB segurado): 8 posições fixas.
Comms.EQUIP = {
	{ id = "bandage", label = "Bandagem" },
	{ id = "tourniquet", label = "Torniquete" },
	{ id = "frag", label = "Granada" },
	{ id = "smoke", label = "Fumaça" },
	{ id = "build", label = "Construir" },
	{ id = "binoculars", label = "Binóculo" },
	{ id = "shovel", label = "Pá de trincheira" },
	{ id = "role_tool", label = "Ferramenta do papel" },
} :: { Item }

-- Roda de comunicação (RB segurado): página "Squad" e página "Comando".
Comms.COMM = {
	{ id = "mark", label = "Marcar" },
	{ id = "attack", label = "Atacar" },
	{ id = "defend", label = "Defender" },
	{ id = "regroup", label = "Reagrupar" },
	{ id = "medic", label = "Médico!" },
	{ id = "ammo", label = "Munição!" },
	{ id = "contact", label = "Contato" },
	{ id = "page_command", label = "Comando ▸" },
} :: { Item }

-- Página "Comando" (comandante e morteiro): habilidades e correções sem teclado.
Comms.COMMAND = {
	{ id = "ability", label = "Pedir fogo / apoio" },
	{ id = "corr_add", label = "Mais 100" },
	{ id = "corr_right", label = "Direita 50" },
	{ id = "corr_drop", label = "Menos 100" },
	{ id = "corr_left", label = "Esquerda 50" },
	{ id = "ok", label = "Entendido" },
	{ id = "no", label = "Negativo" },
	{ id = "page_squad", label = "◂ Squad" },
} :: { Item }

-- texto de correção para o servidor (mesmo formato que o observador falaria)
Comms.CORRECTION = {
	corr_add = "mais 100",
	corr_drop = "menos 100",
	corr_right = "direita 50",
	corr_left = "esquerda 50",
} :: { [string]: string }

-- Marcação imperfeita (Parte 11): marcar inimigo pelo binóculo gera uma ÁREA aproximada, maior
-- com a distância, que envelhece e some (neblina de guerra, não um ponto exato).
Comms.MARK_TTL_S = 60 -- PLACEHOLDER: a área some do mundo e da carta em 1 min
Comms.MARK_ERR_FRAC = 0.1 -- erro de 10% da distância (estimativa de distância a olho/binóculo)
Comms.MARK_ERR_MIN_M = 10
Comms.MARK_ERR_MAX_M = 100

function Comms.markError(distM: number): number
	return math.clamp(distM * Comms.MARK_ERR_FRAC, Comms.MARK_ERR_MIN_M, Comms.MARK_ERR_MAX_M)
end

-- Desvio do centro da área: uniforme no disco de raio r (o alvo real fica dentro do círculo).
function Comms.markOffset(r: number, roll1: number, roll2: number): (number, number)
	local rr = r * math.sqrt(roll1)
	local a = roll2 * 2 * math.pi
	return rr * math.cos(a), rr * math.sin(a)
end

-- Opacidade da marca com a idade (1 = nova, 0 = sumiu)
function Comms.markAlpha(ageS: number): number
	return math.clamp(1 - ageS / Comms.MARK_TTL_S, 0, 1)
end

return Comms
