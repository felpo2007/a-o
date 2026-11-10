--!strict
-- Tutorial curto por papel e campo de tiro (Parte 9, "Aprendizado"; F6). Módulo puro: passos e
-- regra de avanço. Cada passo espera uma ação do InputMap (em qualquer fase de ativação: toque,
-- aperto ou segurar, conforme o dispositivo) ou um acerto num alvo do campo de tiro.
-- O texto não cita teclas: o cliente troca {a} pelo botão da ação no dispositivo do jogador e
-- {nome_da_acao} pelo botão de outra ação, com "(segurar)" quando o dispositivo pede segurar.
local Tutorial = {}

export type Step = { id: string, action: string?, range: number?, text: string }

local function act(action: string, text: string): Step
	return { id = action, action = action, text = text }
end

local function target(m: number, text: string): Step
	return { id = "range_" .. m, range = m, text = text }
end

-- distâncias dos alvos do campo de tiro (m), ao lado de cada QG
Tutorial.RANGE_M = { 100, 200, 300 }
-- o campo de tiro fica na retaguarda: sai do QG em direção oposta à frente, ao longo da borda
Tutorial.RANGE_LANE = {
	US = { offsetM = { 0, 40 }, dir = { 0, 1 } }, -- praia, para o sul
	VC = { offsetM = { 0, -40 }, dir = { 0, -1 } }, -- retaguarda oeste, para o norte
}

Tutorial.COMMON = {
	act("aim", "Mirar: {a}. A mira é a alça da arma."),
	act("fire", "Atirar: {a}. Um ou dois tiros de fuzil derrubam: escolha a cobertura antes de sair."),
	act("reload", "Recarregar: {a}."),
	act("prone", "Deitar: {a}. Você aparece menos e o tiro fica mais estável."),
	act("map", "Carta de 1965: {a}. Não há minimapa: use a bússola, a carta e o rádio."),
}

Tutorial.RANGE = {
	target(100, "Campo de tiro, ao lado do QG: acerte o alvo de 100 m."),
	target(200, "Acerte o alvo de 200 m. A bala cai com a distância: ajuste a alça com {zeroing}."),
	target(300, "Acerte o alvo de 300 m. Mirando, prenda a respiração com {hold_breath}."),
}

-- papéis que usam fuzil ou metralhadora: passam pelo campo de tiro
Tutorial.RIFLE_ROLES = {
	squad_leader = true,
	rifleman = true,
	machine_gunner = true,
	engineer = true,
	observer = true,
	sniper = true,
	sapper = true,
	radio_operator = true,
}

-- veículos: o tutorial começa ao entrar (interagir perto do veículo)
local ENTER = act("interact", "Entrar no veículo: {a}, perto dele.")
local GRENADES = act("equip_wheel", "Roda de equipamento: {a}. Granadas e fumaça ficam nela.")

Tutorial.ROLE = {
	commander = {
		act("comm_wheel", "Roda de comunicação: {a}. A página Comando pede fogo de apoio no mapa."),
		act("binoculars", "Binóculo: {a}."),
	},
	squad_leader = {
		act("mark", "Marcar um ponto para o squad: {a}."),
		act("comm_wheel", "Mensagens rápidas ao squad: {a}."),
		act("equip_wheel", "Construir o posto de reunião do squad (perto de suprimento): {a}."),
	},
	rifleman = { GRENADES },
	grenadier = { GRENADES },
	machine_gunner = { act("fire_mode", "Modo de tiro: {a}. Deitado, a rajada fica controlável.") },
	anti_tank = { act("swap_weapon", "Lançador: {a}. A blindagem da frente é grossa: mire no lado.") },
	engineer = {
		act("equip_wheel", "Construir ninho de metralhadora ou caixa de munição: {a}."),
		act("crouch", "Agachado, perto, você percebe armadilhas inimigas: {a}. Para desarmar, segure Interagir."),
	},
	medic = {
		act("quick_bandage", "Bandagem no seu sangramento mais urgente: {a}."),
		act("interact", "Tratar ou reanimar um ferido: {a}, perto dele."),
	},
	observer = {
		act("binoculars", "Binóculo: {a}."),
		act("mark", "Marcar o alvo para o comandante e o morteiro: {a}."),
	},
	sniper = { act("zeroing", "Alça de mira (100, 200, 300 m): {a}.") },
	mortar = {
		act("equip_wheel", "Construir a posição de morteiro: {a}."),
		act("comm_wheel", "Roda de comunicação: {a}. A página Comando pede a missão de fogo pela grade."),
	},
	sapper = {
		GRENADES,
		act("equip_wheel", "Construir armadilhas (estacas punji, granada com fio) longe do inimigo: {a}."),
	},
	radio_operator = {
		act(
			"comm_wheel",
			"Rádio: {a}. Só você fala com o comandante (página Comando). Se cair, um aliado pega o rádio."
		),
	},
	tank_crew = {
		ENTER,
		act("v_optic", "Ótica: {a}."),
		act("v_fire", "Canhão: {a}."),
		act("v_switch_seat", "Trocar de assento: {a}."),
	},
	pilot = {
		ENTER,
		act("h_stabilize", "Estabilizar o pairado: {a}. Calor e peso roubam potência: decole correndo."),
		act("v_exit", "Sair do helicóptero, já pousado: {a}."),
	},
	door_gunner = { ENTER, act("v_door_fire", "Atirar com a M60 da porta: {a}.") },
} :: { [string]: { Step } }

-- Passos do papel: comuns de infantaria + campo de tiro (fuzil) + específicos. Tripulantes e
-- pilotos começam pelo veículo (o comum de infantaria vem depois, mais curto: mapa).
function Tutorial.steps(role: string): { Step }
	local out: { Step } = {}
	local vehicle = role == "tank_crew" or role == "pilot" or role == "door_gunner"
	if vehicle then
		for _, s in Tutorial.ROLE[role] do
			table.insert(out, s)
		end
		table.insert(out, Tutorial.COMMON[#Tutorial.COMMON]) -- mapa
		return out
	end
	for _, s in Tutorial.COMMON do
		table.insert(out, s)
	end
	if Tutorial.RIFLE_ROLES[role] then
		for _, s in Tutorial.RANGE do
			table.insert(out, s)
		end
	end
	local extra: { Step } = Tutorial.ROLE[role] or {}
	for _, s in extra do
		table.insert(out, s)
	end
	return out
end

-- O passo foi cumprido? kind = "action" (value = id da ação) ou "range" (value = distância do alvo).
function Tutorial.done(step: Step, kind: string, value: any): boolean
	if kind == "action" then
		return step.action ~= nil and step.action == value
	elseif kind == "range" then
		return step.range ~= nil and step.range == value
	end
	return false
end

-- Texto final: troca {a} e {outra_acao} pelo botão (glyph) no dispositivo do jogador.
function Tutorial.render(step: Step, glyph: (actionId: string) -> string): string
	return (
		string.gsub(step.text, "{([%w_]+)}", function(name: string): string
			return glyph(if name == "a" then step.action or "?" else name)
		end)
	)
end

-- Ações citadas no texto ({a} e {outra_acao}), na ordem.
function Tutorial.placeholders(step: Step): { string }
	local out = {}
	for name in string.gmatch(step.text, "{([%w_]+)}") do
		table.insert(out, if name == "a" then step.action or "?" else name)
	end
	return out
end

-- Papéis concluídos vindos do perfil: só ids de papel conhecidos, só true.
function Tutorial.sanitize(raw: any, roles: { [string]: any }): { [string]: boolean }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for k, v in raw do
		if type(k) == "string" and roles[k] and v == true then
			out[k] = true
		end
	end
	return out
end

return Tutorial
