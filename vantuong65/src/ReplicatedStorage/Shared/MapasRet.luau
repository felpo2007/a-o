--!strict
-- D-243: configuração central dos dois mapas retangulares (prompt "Mapas Retangulares", seções 2, 4, 6, 7,
-- 9, 10). Módulo PURO. Medidas em metros de projeto; a planta usa X para leste e Y para norte. Valores que o
-- prompt não fixou ficam marcados como PROVISÓRIO, para ajustar no playtest.
local MapasRet = {}

-- 1 stud = 0,28 m (a convenção do jogo, MapConfig). O soldado padrão tem 2,00 m (Shared/Corpo.HEIGHT_M).
MapasRet.M_POR_STUD = 0.28
MapasRet.ALTURA_CORPO_M = 2.0
-- Enquanto false, nenhum servidor publicado abre estes mapas: só o Studio (VT65DevMapa).
MapasRet.LIBERADOS = false

export type Setor = { id: string, nome: string, x: number, y: number }

MapasRet.FRENTE = {
	id = "frente",
	nome = "Vale das Cinco Passagens",
	modo = "LinhaFrente",
	compM = 700,
	profM = 300,
	baseOeste = { x = 35, y = 150 },
	baseLeste = { x = 665, y = 150 },
	setores = {
		{ id = "A", nome = "Olaria do Barranco", x = 135, y = 150 },
		{ id = "B", nome = "Escola do Pomar", x = 245, y = 190 },
		{ id = "C", nome = "Mercado das Duas Margens", x = 350, y = 150 },
		{ id = "D", nome = "Engenho do Canal", x = 455, y = 110 },
		{ id = "E", nome = "Vila dos Esteios", x = 565, y = 150 },
	} :: { Setor },
	inicio = 3, -- C
	regras = {
		capturaS = { 50, 40, 35 }, -- do neutro à conquista com 1, 2 e 3 ou mais jogadores
		vazioS = 10, -- área vazia antes de a barra começar a voltar
		retornoPorS = 1 / 60, -- PROVISÓRIO: a barra cheia volta ao neutro em 60 s
		transicaoS = 15,
		duracaoS = 20 * 60,
		finalS = 90, -- disputa final com C ativo
		ondaS = 10,
		larguraCapturaM = 30, -- PROVISÓRIO: dentro da faixa de 25 a 35 m
		alturaCapturaM = 3.5, -- PROVISÓRIO: limite vertical do volume, acima do piso do objetivo
	},
}

MapasRet.COMBOIO = {
	id = "comboio",
	nome = "Estrada do Bambu",
	modo = "Comboio",
	compM = 900,
	profM = 300,
	-- N1 a N10, na ordem da estrada
	nos = {
		{ x = 40, y = 120 },
		{ x = 125, y = 170 },
		{ x = 215, y = 115 },
		{ x = 310, y = 205 },
		{ x = 400, y = 155 },
		{ x = 480, y = 105 },
		{ x = 575, y = 200 },
		{ x = 670, y = 135 },
		{ x = 770, y = 195 },
		{ x = 850, y = 150 },
	} :: { { x: number, y: number } },
	-- road_guide_index do JSON (base zero): 2, 5, 6 e 9. Em Luau, N3, N6, N7 e N10.
	checkpoints = {
		{ id = "CP1", nome = "Vila do Sino Baixo", no = 3 },
		{ id = "CP2", nome = "Ponte do Canal Torto", no = 6 },
		{ id = "CP3", nome = "Serraria", no = 7 },
		{ id = "ENTREGA", nome = "Engenho do Espigão", no = 10 },
	},
	baseOeste = { x = 40, y = 120 },
	baseLeste = { x = 860, y = 150 },
	-- faixas do mapa para o resto do jogo (setores do MapConfig)
	setores = {
		{ id = "A", nome = "Arrozais das Comportas", x = 95, y = 150 },
		{ id = "B", nome = "Vila do Sino Baixo", x = 215, y = 115 },
		{ id = "C", nome = "Ponte do Canal Torto", x = 480, y = 105 },
		{ id = "D", nome = "Serraria", x = 575, y = 200 },
		{ id = "E", nome = "Engenho do Espigão", x = 850, y = 150 },
	} :: { Setor },
	ponte = { x = 440, y = 130 },
	lomba = { x = 527.5, y = 152.5, cristaM = 6 },
	regras = {
		velocidadeMS = 3.8,
		separacaoM = 18,
		extensaoM = 18, -- reserva visual antes de N1 e depois de N10
		escoltaM = 14,
		contestaM = 10,
		checkpointS = 8,
		danoPorS = 10,
		integridade = 100,
		imobilizadoS = 15,
		reparoPessoaS = 6,
		reparadoresMax = 2,
		recuperaIntegridade = 25,
		protecaoS = 20,
		imobilizacoesPorTrecho = 2,
		rodadaS = 9 * 60,
		ondaS = 10,
		-- PROVISÓRIO: a seção 15 deixa estas escolhas em aberto
		reparoRetido = true, -- o progresso do reparo fica ao interromper, até o conjunto voltar a andar
		reparoContestado = true, -- dá para reparar sob contestação (o avanço continua parado)
		integridadeNoLimite = 1, -- depois da 2ª imobilização do trecho, o dano não passa daqui
		alturaPresencaM = 4, -- raios em distância horizontal, com este limite de altura
	},
}

return MapasRet
