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
	{ id = "shovel", label = "Pá (F5)" },
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

return Comms
