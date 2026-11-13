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
-- o campo de tiro fica na retaguarda: sai do QG ao longo da borda, sem atirar para a frente
-- Mapa de 1 x 1 km (2026-11-11): a 340 m para oeste, a raia dos EUA cruzaria An Cường (2).
Tutorial.RANGE_LANE = {
	-- QG na borda leste, no vale do riacho: a raia desce o vale para o sul, a 50 m da borda
	US = { offsetM = { 0, 40 }, dir = { 0, 1 } },
	-- QG no morro do noroeste: a raia corre para leste ao longo da borda norte (para o sul ela
	-- passaria pelo Capinzal oeste)
	VC = { offsetM = { 40, 0 }, dir = { 1, 0 } },
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
-- D-108 (classes mais simples): Líder, Fuzileiro, Médico, Suporte, Metralhador, Antitanque e Atirador
-- de elite no squad; os papéis que saíram viraram estes (Roles.MIGRATE)
Tutorial.RIFLE_ROLES = {
	squad_leader = true,
	rifleman = true,
	machine_gunner = true,
	support = true,
	medic = true,
	sniper = true,
}

-- veículos: o tutorial começa ao entrar (interagir perto do veículo)
local ENTER = act("interact", "Entrar no veículo: {a}, perto dele.")
local GRENADES = act("equip_wheel", "Roda de equipamento: {a}. Granadas e fumaça ficam nela.")

Tutorial.ROLE = {
	commander = {
		act("comm_wheel", "Roda de comunicação: {a}. A página Comando pede fogo de apoio no mapa."),
		act("binoculars", "Binóculo: {a}."),
	},
	-- D-108: o líder leva o rádio do squad (era do operador de rádio)
	squad_leader = {
		act("mark", "Marcar um ponto para o squad: {a}."),
		act(
			"comm_wheel",
			"Rádio: {a}. Só você fala com o comandante (página Comando). Se cair, um aliado pega o rádio."
		),
		act("equip_wheel", "Construir o posto de reunião do squad (perto de suprimento): {a}."),
	},
	rifleman = { GRENADES },
	machine_gunner = { act("fire_mode", "Modo de tiro: {a}. Deitado, a rajada fica controlável.") },
	anti_tank = { act("swap_weapon", "Lançador: {a}. A blindagem da frente é grossa: mire no lado.") },
	-- D-108: a caixa de munição (Ferramenta do papel) e as obras do engenheiro, do sapador e do morteiro
	support = {
		act(
			"equip_wheel",
			"Caixa de munição: {a}, Ferramenta do papel. Ponha no chão perto do squad: quem passa pega munição e 1 granada."
		),
		act("crouch", "Agachado, perto, você percebe armadilhas inimigas: {a}. Para desarmar, segure Interagir."),
	},
	medic = {
		act("quick_bandage", "Bandagem no seu sangramento mais urgente: {a}."),
		act("interact", "Tratar ou reanimar um ferido: {a}, perto dele."),
	},
	-- luneta (2026-11-12): alça de 100 em 100 m (até 1.000 na Unertl e 1.300 na PU); o toque no
	-- seletor desce (o ferrolho não tem seletor). D-108: o binóculo do observador e a respiração
	sniper = {
		act("zeroing", "Alça da luneta, 100 m a mais: {a}. Tocar o seletor desce."),
		act("hold_breath", "Prender a respiração na luneta: {a}. Segure pouco: depois o fôlego falta."),
		act("binoculars", "Binóculo: {a}."),
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
} :: { [string]: { Step } }

-- Passos do papel: comuns de infantaria + campo de tiro (fuzil) + específicos. Tripulantes e
-- pilotos começam pelo veículo (o comum de infantaria vem depois, mais curto: mapa).
function Tutorial.steps(role: string): { Step }
	local out: { Step } = {}
	local vehicle = role == "tank_crew" or role == "pilot"
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

-- D-108: papel concluído antes das classes mais simples -> o papel que o substituiu (o mesmo de
-- Roles.MIGRATE; aqui sem o require, o módulo fica puro)
Tutorial.MIGRATE = {
	automatic_rifleman = "machine_gunner",
	grenadier = "rifleman",
	engineer = "support",
	sapper = "support",
	radio_operator = "squad_leader",
	observer = "sniper",
	mortar = "support",
	door_gunner = "machine_gunner",
} :: { [string]: string }

-- Papéis concluídos vindos do perfil: só ids de papel conhecidos, só true. O papel antigo conta como
-- o novo (D-108).
function Tutorial.sanitize(raw: any, roles: { [string]: any }): { [string]: boolean }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for k, v in raw do
		if type(k) == "string" and v == true then
			local id = if roles[k] then k else Tutorial.MIGRATE[k]
			if id and roles[id] then
				out[id] = true
			end
		end
	end
	return out
end

return Tutorial
