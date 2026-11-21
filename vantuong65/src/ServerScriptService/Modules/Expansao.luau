--!strict
-- D-232: expansão da Vila e do Arrozal. Só DADOS: o que entra, onde e com que giro. Quem põe no plano
-- é o ArtPlan.expansao, DEPOIS de tudo o que já existia, e nada aqui muda a posição de uma peça antiga.
--
-- Para tirar só a expansão do jogo: Expansao.LIGADA = false (o mapa volta ao que era, sem apagar nada).
--
-- Coordenadas em METROS a partir do mastro do objetivo: +X leste, +Z sul. `olha`: o ponto para onde a
-- frente do modelo (a porta) aponta.
local Expansao = {}

Expansao.LIGADA = true

export type Peca = {
	id: string, -- nome único, por setor
	key: string, -- modelo (AssetIds.Models)
	x: number,
	z: number,
	olha: { number }?, -- { x, z } para onde a frente aponta
	giro: number?, -- ou o giro direto, em graus
	escala: number?,
	afunda: number?, -- metros abaixo do patamar (abrigo, trincheira, comporta)
	semPatamar: boolean?, -- assenta no chão como está (objeto pequeno)
	travessia: boolean?, -- prancha e passarela: sem patamar, na altura média do chão das duas pontas
	sobreLeito: boolean?, -- comporta: o piso do modelo no leito do canal e o patamar `afunda` acima
}
export type Beco = { number } -- x1, z1, x2, z2, ...: a linha do beco
export type Corte = {
	id: string,
	pts: { { number } }, -- { x, z }, do começo ao fim da água; { x, z, 1 }: trecho plano até aqui
	fundo: number, -- metros do leito abaixo do chão (o leito nunca sobe na direção da água)
	largura: number, -- metros
	margem: number, -- metros de rampa de cada lado
	agua: number, -- metros de água sobre o leito (0 = vala seca)
}
export type Escava = { id: string, x: number, z: number, giro: number, tam: { number }, fundo: number }
export type Planta = { key: string, x: number, z: number, escala: number? }
export type Setor = {
	pecas: { Peca },
	becos: { Beco },
	cortes: { Corte },
	escavar: { Escava },
	plantas: { Planta }?,
}
-- árvores e plantas sorteadas pelo resto do mapa (n, escalas, tipos da Landscape, distância mínima em m)
export type Mata = { key: string, n: number, s0: number, s1: number, tipos: { [number]: boolean }, dist: number }

Expansao.BECO_MEIA_M = 1.25

Expansao.SETORES = {
	-- Vila: a Rua do Poente, um beco novo que sai da casa a oeste do objetivo, dá a volta por fora do
	-- círculo de nascer de (-79, 14) e desce até a estrada principal
	Vila = {
		becos = {
			{ -52, -22, -66, -44, -100, -50, -114, -12, -110, 38, -88, 83 },
			{ -127, 47, -105.6, 47 }, -- da saída da trincheira até a rua
			{ -100, -13.2, -112, -17.5 }, -- da porta da casa da vala até a rua
			-- D-234: os caminhos dos sobrados, cada um ligado a uma rua
			{ -52, -22, -44, -36, -30, -54 },
			{ -44, -36, -43, -72, -50, -90, -10, -90 },
			{ -76, -28, -78, -46 },
			{ -85.5, 45, -107, 44.5 },
			{ 120, -78, 116, -97 },
			{ 118, 23, 114, 1 },
			{ -117, 72, -96, 68 },
		},
		cortes = {
			{
				id = "vala_poente",
				pts = { { -122, -5 }, { -100, -2 }, { -94, 6 } },
				fundo = 0.9,
				largura = 2.0,
				margem = 0.7, -- 1,7 m do eixo à borda: a prancha de 3,4 m apoia no chão das margens
				agua = 0.45,
			},
		},
		-- abrigo: a sala e o corredor das duas bocas. Trincheira: 3 trechos de 6 m em linha, com uma rampa
		-- de 4 m de terra em cada ponta (do chão até o fundo de 1,4 m)
		escavar = {
			{ id = "abrigo_sala", x = -128, z = 16, giro = 90, tam = { 4.6, 3.2 }, fundo = 1.5 },
			{ id = "abrigo_bocas", x = -128, z = 16, giro = 90, tam = { 8.0, 2.0 }, fundo = 1.5 },
			{ id = "rampa_a1", x = -127, z = 20.9, giro = 0, tam = { 2.2, 1.15 }, fundo = 0.28 },
			{ id = "rampa_a2", x = -127, z = 21.9, giro = 0, tam = { 2.2, 1.15 }, fundo = 0.56 },
			{ id = "rampa_a3", x = -127, z = 22.9, giro = 0, tam = { 2.2, 1.15 }, fundo = 0.84 },
			{ id = "rampa_a4", x = -127, z = 23.9, giro = 0, tam = { 2.2, 1.15 }, fundo = 1.12 },
			{ id = "trincheira_1", x = -127, z = 27.4, giro = 0, tam = { 2.2, 6.4 }, fundo = 1.45 },
			{ id = "trincheira_2", x = -127, z = 33.4, giro = 0, tam = { 2.2, 6.4 }, fundo = 1.45 },
			{ id = "trincheira_3", x = -127, z = 39.4, giro = 0, tam = { 2.2, 6.4 }, fundo = 1.45 },
			{ id = "rampa_b1", x = -127, z = 42.9, giro = 0, tam = { 2.2, 1.15 }, fundo = 1.12 },
			{ id = "rampa_b2", x = -127, z = 43.9, giro = 0, tam = { 2.2, 1.15 }, fundo = 0.84 },
			{ id = "rampa_b3", x = -127, z = 44.9, giro = 0, tam = { 2.2, 1.15 }, fundo = 0.56 },
			{ id = "rampa_b4", x = -127, z = 45.9, giro = 0, tam = { 2.2, 1.15 }, fundo = 0.28 },
		},
		pecas = {
			{ id = "palafita_1", key = "exp_palafita_a", x = -84, z = -60, olha = { -84, -48 } },
			{ id = "ligadas_1", key = "exp_casas_ligadas", x = -62, z = -63, olha = { -66, -44 } },
			{ id = "palafita_2", key = "exp_palafita_b", x = -113, z = -66, olha = { -100, -50 } },
			{ id = "carroca_1", key = "exp_carroca", x = -90, z = -39, olha = { -90, -50 } },
			-- a varanda do fundo dá para a vala (a faixa d'água do modelo fica na margem de cima)
			{ id = "casa_vala", key = "exp_casa_vala", x = -100, z = -8, olha = { -100, -30 } },
			{ id = "prancha_1", key = "exp_prancha", x = -113.3, z = -3.7, giro = -8, travessia = true },
			{ id = "prancha_2", key = "exp_prancha", x = -107.5, z = -3.02, giro = -8, travessia = true },
			{ id = "abrigo", key = "exp_abrigo", x = -128, z = 16, olha = { -112, 16 }, afunda = 1.4 },
			{ id = "trincheira_1", key = "exp_trincheira", x = -127, z = 27.4, giro = 0, afunda = 1.4 },
			{ id = "trincheira_2", key = "exp_trincheira", x = -127, z = 33.4, giro = 0, afunda = 1.4 },
			{ id = "trincheira_3", key = "exp_trincheira", x = -127, z = 39.4, giro = 0, afunda = 1.4 },
			-- quintais, com o que a vila já usa
			{ id = "cerca_1", key = "bamboo_fence", x = -78.5, z = -52.5, giro = 0, semPatamar = true },
			{ id = "cerca_2", key = "bamboo_fence", x = -89.5, z = -52.5, giro = 0, semPatamar = true },
			{ id = "pote_1", key = "water_jar", x = -79.3, z = -58, giro = 30, semPatamar = true },
			{ id = "varal_1", key = "bamboo_clothesline", x = -73, z = -56, giro = 10, semPatamar = true },
			{ id = "horta_1", key = "parts:horta", x = -60, z = -53, giro = 12, semPatamar = true },
			{ id = "pote_2", key = "water_jar", x = -56.5, z = -56, giro = 75, semPatamar = true },
			{ id = "palha_1", key = "straw_stack", x = -121, z = -60, giro = 40, semPatamar = true },
			{ id = "pote_3", key = "water_jar", x = -94.5, z = -8, giro = 120, semPatamar = true },
			-- D-234: sobrados grandes de dois andares (a e b: térreo aberto; c e d: térreo fechado). Todos a
			-- mais de 55 m do mastro: o andar de cima não domina a área de captura
			{ id = "sobrado_1", key = "exp_sobrado_a", x = -30, z = -62, olha = { -30, -40 } },
			{ id = "sobrado_2", key = "exp_sobrado_c", x = -76, z = -20, olha = { -77, -46 } },
			{ id = "sobrado_3", key = "exp_sobrado_b", x = -78, z = 44, olha = { -107, 44.5 } },
			{ id = "sobrado_4", key = "exp_sobrado_d", x = -50, z = -98, olha = { -50, -80 } },
			{ id = "sobrado_5", key = "exp_sobrado_a", x = -10, z = -98, olha = { -10, -80 } },
			{ id = "sobrado_6", key = "exp_sobrado_c", x = 122, z = -68, olha = { 117, -97 } },
			{ id = "sobrado_7", key = "exp_sobrado_b", x = 119, z = 31, olha = { 114, 1 } },
			{ id = "sobrado_8", key = "exp_sobrado_a", x = -126, z = 72, olha = { -96, 68 } },
		},
		plantas = {
			{ key = "exp_figueira", x = -127, z = -38 },
			{ key = "exp_arvore_a", x = -78, z = -82 },
			{ key = "exp_arvore_b", x = -46, z = -48 },
			{ key = "exp_arvore_b", x = -132, z = -6 },
			{ key = "exp_rocha", x = -118, z = -28 },
			{ key = "exp_samambaia", x = -119, z = -24 },
			{ key = "exp_samambaia", x = -96, z = 2 },
			{ key = "bamboo_clump", x = -92, z = 12 },
			{ key = "bamboo_clump", x = -122, z = 2 },
			{ key = "banana", x = -92, z = -70 },
			{ key = "banana", x = -54, z = -74 },
			{ key = "coconut_palm", x = -105, z = -76 },
			-- copas entre e atrás das casas, bambu junto da água, folhagem baixa nas cercas
			{ key = "banana", x = -70, z = -71 },
			{ key = "banana", x = -92, z = -58 },
			{ key = "banana", x = -93, z = -13 },
			{ key = "coconut_palm", x = -70, z = -50.5 },
			{ key = "coconut_palm", x = -108, z = -24 },
			{ key = "canopy_tree", x = -100, z = -84 },
			{ key = "canopy_tree", x = -60, z = -86 },
			{ key = "exp_arvore_a", x = -140, z = -25 },
			{ key = "exp_arvore_b", x = -137, z = 30 },
			{ key = "bamboo_clump", x = -117, z = -8.5 },
			{ key = "bamboo_clump", x = -135, z = 12 },
			{ key = "taro_fern", x = -103.5, z = 1 },
			{ key = "taro_fern", x = -117, z = 0.5 },
			{ key = "taro_fern", x = -99, z = 2.5 },
			{ key = "shrub", x = -76, z = -50.5 },
			{ key = "shrub", x = -92, z = -52 },
			{ key = "exp_samambaia", x = -121.5, z = 30 },
			{ key = "exp_samambaia", x = -122, z = 38 },
		},
	},
	-- Arrozal: a fazenda a leste do objetivo, em terra seca, ligada à estrada; o canal sai do tabuleiro
	-- do sudeste e desce pela comporta até o rio
	Arrozais = {
		becos = {
			{ 60, -64, 76, -42, 74, -14, 84, 4, 112, 7, 118, 2, 119, -14, 122.8, -27.5 },
			{ 76, -42, 93.5, -50.5 }, -- até a ruína
			{ 84, 4, 73.4, 4.5 }, -- até o depósito
			{ 118, 2, 119, 20, 116.6, 46.3, 115.2, 56.5 }, -- até a passarela e a comporta
			{ 107.4, 47.7, 92, 49.5, 60, 50, 57.5, 29.5 }, -- da passarela, pelo sul do tabuleiro, até o dique
		},
		cortes = {
			{
				id = "canal_leste",
				pts = {
					{ 104.5, 38 },
					{ 112, 40 },
					{ 112, 47.8 }, -- até a passarela, no nível de cima
					{ 112, 51 }, -- a queda do barranco
					{ 112, 54 },
					{ 112, 57 },
					{ 112, 67, 1 }, -- nivelado pela comporta
					{ 112.2, 71 }, -- a queda da saída
					{ 112.3, 76 }, -- dentro do rio
				},
				fundo = 1.25,
				largura = 3.4,
				margem = 1.2,
				agua = 0.6,
			},
		},
		escavar = {},
		pecas = {
			{ id = "celeiro", key = "exp_celeiro", x = 92, z = -22, olha = { 92, -6 } },
			{ id = "patio", key = "exp_patio", x = 94.3, z = -9.5, giro = 0 }, -- em frente ao portão
			{ id = "galpao", key = "exp_galpao", x = 111, z = -8, olha = { 96, -5 } },
			{ id = "deposito", key = "exp_deposito", x = 69, z = 5, olha = { 80, 3 } },
			{ id = "telheiro", key = "exp_telheiro", x = 124, z = 7, olha = { 113, 8 } },
			{ id = "casa_verde", key = "exp_casa_verde", x = 124, z = -33, olha = { 120, -16 } },
			{ id = "ruina", key = "exp_ruina", x = 97, z = -56, olha = { 88, -44 } },
			-- o canal passa 1,69 m a oeste do centro do modelo (Y de -3,39 a 0,01 m no Blender)
			{ id = "comporta", key = "exp_comporta", x = 113.69, z = 62, giro = 90, afunda = 1.25, sobreLeito = true },
			{ id = "passarela", key = "exp_passarela", x = 112, z = 47, giro = 9.5, afunda = 1.2, travessia = true },
			{ id = "muro_1", key = "exp_muro", x = 83.5, z = -9, giro = 80 },
			{ id = "muro_2", key = "exp_muro", x = 80, z = 12, giro = 15 },
			{ id = "muro_3", key = "exp_muro", x = 127.5, z = -21, giro = 5 },
			-- quintais e terreiro, com o que a vila já usa
			{ id = "palha_a", key = "straw_stack", x = 81.5, z = -19, giro = 20, semPatamar = true },
			{ id = "palha_b", key = "straw_stack", x = 81, z = -24, giro = 200, semPatamar = true },
			{ id = "saco_1", key = "rice_sack", x = 87, z = -15, giro = 15, semPatamar = true },
			{ id = "saco_2", key = "rice_sack", x = 88, z = -15.2, giro = 70, semPatamar = true },
			{ id = "saco_3", key = "rice_sack", x = 73, z = 8, giro = 40, semPatamar = true },
			{ id = "horta_a", key = "parts:horta", x = 128.5, z = -25, giro = 5, semPatamar = true },
			{ id = "horta_b", key = "parts:horta", x = 132.2, z = -25, giro = 5, semPatamar = true },
			{ id = "pote_a", key = "water_jar", x = 117.5, z = -29.5, giro = 50, semPatamar = true },
			{ id = "varal_a", key = "bamboo_clothesline", x = 114.5, z = -31, giro = 90, semPatamar = true },
		},
		plantas = {
			{ key = "exp_arvore_a", x = 118, z = -52 },
			{ key = "exp_arvore_b", x = 76, z = -24 },
			{ key = "exp_arvore_b", x = 130, z = 4 },
			{ key = "bamboo_clump", x = 123, z = 26 },
			{ key = "banana", x = 136, z = -31 },
			{ key = "banana", x = 86, z = 14 },
			{ key = "coconut_palm", x = 104, z = -40 },
			{ key = "coconut_palm", x = 130, z = -44 },
			{ key = "exp_samambaia", x = 108, z = 52 },
			{ key = "exp_samambaia", x = 117, z = 56 },
			{ key = "exp_rocha", x = 118, z = 72 },
			-- mata na borda da fazenda e ao longo do canal; o campo fica aberto
			{ key = "exp_arvore_b", x = 90, z = -38 },
			{ key = "exp_arvore_a", x = 134, z = -12 },
			{ key = "exp_arvore_a", x = 72, z = -32 },
			{ key = "canopy_tree", x = 140, z = 10 },
			{ key = "banana", x = 88, z = -31 },
			{ key = "banana", x = 97, z = -31 },
			{ key = "coconut_palm", x = 101, z = -30 },
			{ key = "bamboo_clump", x = 121, z = 40 },
			{ key = "bamboo_clump", x = 121, z = 52 },
			{ key = "bamboo_clump", x = 101.5, z = 60 },
			{ key = "taro_fern", x = 108.5, z = 53 },
			{ key = "taro_fern", x = 119, z = 54 },
			{ key = "shrub", x = 84.5, z = -4 },
			{ key = "shrub", x = 77, z = 10 },
			{ key = "exp_samambaia", x = 103, z = -60 },
			{ key = "exp_samambaia", x = 89, z = -61 },
			-- canteiros de muda perto do tabuleiro
			{ key = "rice_patch", x = 96, z = 13 },
			{ key = "rice_patch", x = 101, z = 13 },
			{ key = "rice_patch", x = 106, z = 13 },
		},
	},
} :: { [string]: Setor }

-- Resto do mapa: variedade na mata (1 = FOREST, 2 = GROVE, da Landscape), com sorteio próprio
Expansao.MATA = {
	{ key = "exp_arvore_a", n = 40, s0 = 0.85, s1 = 1.2, tipos = { [1] = true, [2] = true }, dist = 16 },
	{ key = "exp_arvore_b", n = 40, s0 = 0.85, s1 = 1.2, tipos = { [1] = true, [2] = true }, dist = 16 },
	{ key = "exp_figueira", n = 5, s0 = 0.9, s1 = 1.1, tipos = { [1] = true }, dist = 150 },
	{ key = "exp_rocha", n = 70, s0 = 0.6, s1 = 1.3, tipos = { [1] = true, [2] = true }, dist = 8 },
	{ key = "exp_samambaia", n = 140, s0 = 0.8, s1 = 1.3, tipos = { [1] = true, [2] = true }, dist = 4 },
} :: { Mata }

-- Luz quente dos interiores (lampião): { x, y, z } em metros, no quadro do modelo, a partir do centro da
-- base. Só o entorno de cada cômodo, sem sombra, e nada na iluminação geral do mapa.
Expansao.LUZ = { cor = { 255, 196, 130 }, brilho = 0.9, alcanceM = 4.5 }
Expansao.LUZES = {
	exp_abrigo = { { 0, 1.9, 0 } },
	exp_celeiro = { { -3.5, 3.2, 0 }, { 3.5, 3.2, 0 } },
	exp_casa_verde = { { 0, 2.2, 0.5 } },
	exp_casa_vala = { { 0, 2, -0.78 } },
	exp_casas_ligadas = { { -3.7, 2, 0 }, { 3.7, 2, 0 } },
	exp_palafita_a = { { 0, 4.5, 1.2 } },
	exp_palafita_b = { { 0, 4.5, 0.8 } },
	exp_comporta = { { 0, 3.3, 2 } },
	exp_deposito = { { 0, 3.6, 0 } },
	-- D-234: os dois cômodos de cima; nos de térreo fechado, também os dois de baixo
	exp_sobrado_a = { { 3.64, 5.05, 0.83 }, { -2.57, 5.05, 0.83 } },
	exp_sobrado_b = { { 3.84, 5.05, 0.83 }, { -2.77, 5.05, 0.83 } },
	exp_sobrado_c = { { 3.2, 5.05, 0.83 }, { -3.2, 5.05, 0.83 }, { 3.2, 2.2, 0.33 }, { -3.8, 2.2, 0.83 } },
	exp_sobrado_d = { { 3.5, 5.05, 0.83 }, { -3.5, 5.05, 0.83 }, { 3.5, 2.2, 0.33 }, { -4.1, 2.2, 0.83 } },
} :: { [string]: { { number } } }

-- Agitação só na queda da saída da comporta (visual; o nível da água não muda)
Expansao.ESPUMA = {
	exp_comporta = { { -4.6, 0.5, -1.69 } },
} :: { [string]: { { number } } }

return Expansao
