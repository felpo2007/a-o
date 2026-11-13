--!strict
-- Animação dos itens (D-99). Pedido do dono: "faça as animações perfeitas para bandagens etc." e
-- "faça animações perfeitas e realistas para todos os itens ao utilizá-los". Módulo PURO (testado no
-- Lune): o caminho das duas mãos em cada uso, em 3ª pessoa (PostureController: IK, todos veem) e em
-- 1ª pessoa (Controllers/ItemView: mãos do Maos1P e o objeto na mão).
-- - 3ª pessoa: studs no espaço da UpperTorso do corpo de 1,75 m (como as pegas do ArmIK; no jogo
--   vezes K). Referências do corpo gravado: ombros em (±1,0; 0,6; 0), olhos ~(0; 1,5; −0,4), boca
--   ~(0; 1,15; −0,5), bolsa de primeiros socorros no cinto à esquerda ~(−0,5; −0,7; −0,6), meio da
--   coxa direita ~(0,45; −1,6; −0,4). Cotovelos pelos polos ItemAnim.POLES (para fora, para cima e
--   um pouco à frente): com os polos da carta o braço entrava até 8 cm no peito nas mãos à frente.
-- - 1ª pessoa: metros no espaço da câmera (x direita, y cima, −z frente).
-- Tempo: as chaves vão de 0 ao fim nominal; [loop.a, loop.b] repete enquanto a ação dura (o tempo do
-- servidor) ou enquanto o botão está seguro; depois de loop.b vem o fim (amarrar, guardar). Ações:
--   bandage (curativo em si: tira da bolsa, rasga, enrola no braço, amarra), tourniquet (torniquete na
--   coxa direita: passa a tira, gira a haste, prende), bandage_other / treat / revive (no companheiro caído
--   à frente: curativo, tratamento do médico, compressões), radio (fone no ouvido, só a esquerda),
--   binoculars (binóculo nos olhos), shovel (pá de trincheira: crava, alavanca, joga a terra),
--   canteen (cantil: tira do cinto, abre, bebe, guarda). Granada, fumaça, carta e recarga têm os
--   seus (D-77, D-98, D-69 e os clipes do tools/anim).
-- Números de projeto, medidos a olho em vídeos de treinamento de campanha (FM 21-11, 1958). PLACEHOLDER.
-- As chaves de 3ª pessoa foram depois afastadas do corpo pelo tools/anim/itens_fora.luau (braço no
-- máximo 1,5 cm dentro do tronco no simulador do ArmIK); ao mudar uma, rode-o de novo.
local ItemAnim = {}

export type V = { number }
export type Key = { t: number, r: V, l: V, tilt: number? }
export type Prop = { kind: string, hand: string, from: number?, to: number? } -- from/to: s nominais
export type Anim = {
	dur: number, -- fim nominal (s)
	loop: { a: number, b: number },
	slung: boolean, -- fuzil a tiracolo (false: o fuzil fica na direita, como no rádio)
	left: boolean, -- a esquerda segue o caminho
	right: boolean, -- a direita segue o caminho
	held: boolean, -- dura enquanto o botão/estado durar (sem fim próprio)
	tp: { Key },
	fp: { Key },
	poseR: string, -- pega da mão de 1ª pessoa (MaosPose)
	poseL: string,
	prop: Prop?,
}

-- polos dos cotovelos no uso de itens (studs, UpperTorso do corpo gravado; IKControl.Pole), medidos
-- no simulador do ArmIK (tools/anim/itens_fora.luau)
ItemAnim.POLES = { R = { 4.0, 2.0, -1.0 }, L = { -4.0, 2.0, -1.0 } } :: { [string]: V }

local FP_R0, FP_L0 = { 0.2, -0.5, -0.25 }, { -0.2, -0.5, -0.25 } -- abaixo da tela

local function k(t: number, r: V, l: V, tilt: number?): Key
	return { t = t, r = r, l = l, tilt = tilt }
end

ItemAnim.ANIMS = {
	bandage = {
		dur = 6,
		loop = { a = 1.2, b = 2.2 },
		slung = true,
		left = true,
		right = true,
		held = false,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
			k(0.5, { -0.102, -0.368, -0.861 }, { -0.6, -0.3, -1 }), -- a direita na bolsa do cinto
			k(0.9, { 0.1, 0.1, -1.3 }, { -0.15, 0.1, -1.3 }), -- rasga o envelope diante do peito
			-- o braço esquerdo para a frente; a direita enrola a atadura em volta dele (uma volta/s)
			k(1.2, { -0.2, -0.07, -1.2 }, { -0.6, -0.35, -1.05 }),
			k(1.45, { -0.174, -0.034, -1.299 }, { -0.6, -0.33, -1.05 }),
			k(1.7, { -0.068, -0.321, -1.022 }, { -0.61, -0.37, -1.04 }),
			k(1.95, { -0.019, -0.414, -0.886 }, { -0.6, -0.36, -1.05 }),
			k(2.2, { -0.2, -0.07, -1.2 }, { -0.6, -0.35, -1.05 }),
			k(4.9, { -0.185, -0.113, -1.119 }, { -0.6, -0.35, -1.05 }), -- amarra: as pontas puxadas
			k(5.3, { 0, -0.25, -1.3 }, { -0.55, -0.3, -1.2 }),
			k(6, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
		},
		fp = {
			k(0, FP_R0, FP_L0),
			k(0.5, { 0.05, -0.42, -0.3 }, { -0.16, -0.36, -0.36 }),
			k(0.9, { 0.04, -0.2, -0.36 }, { -0.04, -0.2, -0.36 }),
			k(1.2, { 0.0, -0.2, -0.36 }, { -0.14, -0.26, -0.4 }),
			k(1.45, { -0.06, -0.17, -0.42 }, { -0.14, -0.26, -0.4 }),
			k(1.7, { -0.12, -0.27, -0.42 }, { -0.14, -0.27, -0.4 }),
			k(1.95, { -0.06, -0.31, -0.34 }, { -0.14, -0.26, -0.4 }),
			k(2.2, { 0.0, -0.2, -0.36 }, { -0.14, -0.26, -0.4 }),
			k(4.9, { -0.04, -0.24, -0.37 }, { -0.14, -0.26, -0.4 }),
			k(5.3, { 0.06, -0.24, -0.38 }, { -0.12, -0.25, -0.4 }),
			k(6, FP_R0, FP_L0),
		},
		poseR = "grip",
		poseL = "flat",
		prop = { kind = "curativo", hand = "R", from = 0.5, to = 5.3 },
	},
	tourniquet = {
		dur = 4,
		loop = { a = 1.0, b = 1.8 },
		slung = true,
		left = true,
		right = true,
		held = false,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
			k(0.45, { 0.7, -0.7, -0.9 }, { 0.015, -0.222, -1.384 }), -- a direita na bolsa do cinto
			k(1.0, { 0.865, -1.04, -0.864 }, { -0.127, -0.569, -1.032 }), -- a tira em volta da coxa direita
			k(1.2, { 0.642, -0.955, -0.961 }, { -0.127, -0.569, -1.032 }), -- gira a haste (molinete)
			k(1.4, { 0.808, -1.027, -0.88 }, { -0.126, -0.575, -1.024 }),
			k(1.6, { 0.944, -1.083, -0.781 }, { -0.127, -0.569, -1.032 }),
			k(1.8, { 0.865, -1.04, -0.864 }, { -0.127, -0.569, -1.032 }),
			k(3.2, { 0.743, -1.002, -0.911 }, { -0.167, -0.57, -0.993 }),
			k(3.6, { 0.689, -0.973, -0.948 }, { -0.113, -0.548, -0.966 }), -- prende a haste
			k(4, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
		},
		fp = {
			k(0, FP_R0, FP_L0),
			k(0.45, { 0.16, -0.4, -0.3 }, { 0.0, -0.38, -0.32 }),
			k(1.0, { 0.14, -0.4, -0.36 }, { 0.02, -0.42, -0.34 }),
			k(1.2, { 0.1, -0.36, -0.4 }, { 0.02, -0.42, -0.34 }),
			k(1.4, { 0.06, -0.4, -0.38 }, { 0.02, -0.43, -0.34 }),
			k(1.6, { 0.1, -0.44, -0.34 }, { 0.02, -0.42, -0.34 }),
			k(1.8, { 0.14, -0.4, -0.36 }, { 0.02, -0.42, -0.34 }),
			k(3.2, { 0.12, -0.4, -0.36 }, { 0.03, -0.41, -0.35 }),
			k(3.6, { 0.08, -0.38, -0.38 }, { 0.05, -0.4, -0.36 }),
			k(4, FP_R0, FP_L0),
		},
		poseR = "grip",
		poseL = "flat",
		prop = { kind = "torniquete", hand = "R", from = 0.45, to = 3.6 },
	},
	bandage_other = {
		dur = 4,
		loop = { a = 0.6, b = 1.6 },
		slung = true,
		left = true,
		right = true,
		held = false,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
			k(0.6, { 0.432, -0.719, -1.207 }, { -0.529, -0.82, -1.123 }), -- o companheiro no chão à frente
			k(0.85, { 0.312, -0.571, -1.306 }, { -0.53, -0.817, -1.128 }),
			k(1.1, { 0.221, -0.652, -1.167 }, { -0.525, -0.825, -1.115 }),
			k(1.35, { 0.321, -0.792, -1.052 }, { -0.529, -0.82, -1.123 }),
			k(1.6, { 0.432, -0.719, -1.207 }, { -0.529, -0.82, -1.123 }),
			k(3.4, { 0.393, -0.727, -1.178 }, { -0.494, -0.782, -1.158 }),
			k(4, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
		},
		fp = {
			k(0, FP_R0, FP_L0),
			k(0.6, { 0.08, -0.4, -0.46 }, { -0.1, -0.42, -0.44 }),
			k(0.85, { 0.02, -0.36, -0.5 }, { -0.1, -0.42, -0.44 }),
			k(1.1, { -0.06, -0.42, -0.48 }, { -0.1, -0.43, -0.44 }),
			k(1.35, { 0.02, -0.46, -0.42 }, { -0.1, -0.42, -0.44 }),
			k(1.6, { 0.08, -0.4, -0.46 }, { -0.1, -0.42, -0.44 }),
			k(3.4, { 0.06, -0.4, -0.45 }, { -0.09, -0.41, -0.45 }),
			k(4, FP_R0, FP_L0),
		},
		poseR = "grip",
		poseL = "flat",
		prop = { kind = "curativo", hand = "R", from = 0.3, to = 3.4 },
	},
	treat = {
		dur = 10,
		loop = { a = 0.6, b = 1.4 },
		slung = true,
		left = true,
		right = true,
		held = false,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
			k(0.6, { 0.452, -0.759, -1.168 }, { -0.523, -0.764, -1.193 }),
			k(1.0, { 0.375, -0.714, -1.185 }, { -0.386, -0.743, -1.155 }), -- as duas mãos trabalhando
			k(1.4, { 0.452, -0.759, -1.168 }, { -0.523, -0.764, -1.193 }),
			k(9.4, { 0.419, -0.751, -1.162 }, { -0.466, -0.759, -1.175 }),
			k(10, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
		},
		fp = {
			k(0, FP_R0, FP_L0),
			k(0.6, { 0.1, -0.4, -0.44 }, { -0.1, -0.44, -0.48 }),
			k(1.0, { 0.03, -0.44, -0.48 }, { -0.05, -0.4, -0.44 }),
			k(1.4, { 0.1, -0.4, -0.44 }, { -0.1, -0.44, -0.48 }),
			k(9.4, { 0.08, -0.4, -0.44 }, { -0.08, -0.42, -0.46 }),
			k(10, FP_R0, FP_L0),
		},
		poseR = "grip",
		poseL = "flat",
		prop = { kind = "curativo", hand = "R", from = 0.3, to = 9.4 },
	},
	revive = {
		dur = 8,
		loop = { a = 0.6, b = 1.1 },
		slung = true,
		left = true,
		right = true,
		held = false,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
			k(0.6, { 0.33, -0.71, -1.164 }, { -0.33, -0.71, -1.164 }), -- mãos sobrepostas no peito dele
			k(0.85, { 0.372, -0.786, -1.091 }, { -0.372, -0.786, -1.091 }), -- compressão (2 por segundo)
			k(1.1, { 0.33, -0.71, -1.164 }, { -0.33, -0.71, -1.164 }),
			k(7.4, { 0.33, -0.71, -1.164 }, { -0.33, -0.71, -1.164 }),
			k(8, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
		},
		fp = {
			k(0, FP_R0, FP_L0),
			k(0.6, { 0.02, -0.36, -0.42 }, { -0.02, -0.37, -0.43 }),
			k(0.85, { 0.02, -0.46, -0.42 }, { -0.02, -0.47, -0.43 }),
			k(1.1, { 0.02, -0.36, -0.42 }, { -0.02, -0.37, -0.43 }),
			k(7.4, { 0.02, -0.36, -0.42 }, { -0.02, -0.37, -0.43 }),
			k(8, FP_R0, FP_L0),
		},
		poseR = "flat",
		poseL = "flat",
	},
	radio = {
		dur = 1.35,
		loop = { a = 0.35, b = 1.35 },
		slung = false,
		left = true,
		right = false,
		held = true,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0.4, -1.3 }),
			k(0.18, { 0.45, 0, -1.2 }, { -0.9, 0.75, -1.1 }), -- por fora do ombro
			k(0.35, { 0.45, 0, -1.2 }, { -0.8, 1.25, -0.45 }), -- o fone no ouvido esquerdo, a boca no bocal
			k(0.85, { 0.45, 0, -1.2 }, { -0.8, 1.22, -0.47 }),
			k(1.35, { 0.45, 0, -1.2 }, { -0.8, 1.25, -0.45 }),
		},
		fp = {
			k(0, FP_R0, { -0.12, -0.2, -0.3 }),
			k(0.35, FP_R0, { -0.2, 0.0, -0.06 }), -- sobe e sai pela esquerda da tela
			k(1.35, FP_R0, { -0.2, 0.0, -0.06 }),
		},
		poseR = "grip",
		poseL = "grip",
		prop = { kind = "fone", hand = "L", from = 0.05 },
	},
	binoculars = {
		dur = 2.4,
		loop = { a = 0.4, b = 2.4 },
		slung = true,
		left = true,
		right = true,
		held = true,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
			k(0.4, { 0.22, 1.2, -1.25 }, { -0.22, 1.2, -1.25 }),
			k(1.4, { 0.22, 1.21, -1.26 }, { -0.22, 1.19, -1.25 }),
			k(2.4, { 0.22, 1.2, -1.25 }, { -0.22, 1.2, -1.25 }),
		},
		fp = {
			k(0, FP_R0, FP_L0),
			k(0.4, { 0.07, -0.02, -0.14 }, { -0.07, -0.02, -0.14 }),
			k(2.4, { 0.07, -0.02, -0.14 }, { -0.07, -0.02, -0.14 }),
		},
		poseR = "grip",
		poseL = "grip",
		prop = { kind = "binoculo", hand = "both", from = 0 },
	},
	shovel = {
		dur = 8,
		loop = { a = 0.6, b = 2.0 },
		slung = true,
		left = true,
		right = true,
		held = false,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
			k(0.6, { 0.35, 0.1, -1 }, { -0.021, -0.419, -1.259 }), -- pronto, a lâmina no chão à frente
			k(0.95, { 0.3, -0.6, -1.25 }, { -0.272, -0.682, -1.164 }), -- crava
			k(1.25, { 0.45, -0.2, -0.95 }, { -0.169, -0.565, -1.226 }), -- alavanca
			k(1.6, { 0.83, 0.2, -0.8 }, { 0.116, -0.014, -1.429 }), -- joga a terra para a direita
			k(2.0, { 0.35, 0.1, -1 }, { -0.021, -0.419, -1.259 }),
			k(7.5, { 0.35, 0.1, -1 }, { -0.021, -0.419, -1.259 }),
			k(8, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
		},
		fp = {
			k(0, FP_R0, FP_L0),
			k(0.6, { 0.12, -0.2, -0.3 }, { 0.02, -0.34, -0.44 }),
			k(0.95, { 0.1, -0.34, -0.36 }, { 0.0, -0.5, -0.52 }),
			k(1.25, { 0.14, -0.24, -0.28 }, { 0.02, -0.42, -0.5 }),
			k(1.6, { 0.26, -0.16, -0.26 }, { 0.2, -0.26, -0.42 }),
			k(2.0, { 0.12, -0.2, -0.3 }, { 0.02, -0.34, -0.44 }),
			k(7.5, { 0.12, -0.2, -0.3 }, { 0.02, -0.34, -0.44 }),
			k(8, FP_R0, FP_L0),
		},
		poseR = "grip",
		poseL = "grip",
		prop = { kind = "pa", hand = "both", from = 0.3, to = 7.7 },
	},
	canteen = {
		dur = 3.5,
		loop = { a = 1.4, b = 2.4 },
		slung = true,
		left = true,
		right = true,
		held = false,
		tp = {
			k(0, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }),
			k(0.25, { 1.2, -0.1, -0.85 }, { -0.4, -0.1, -1.15 }, 0), -- sai por fora do corpo
			k(0.5, { 1.3, -0.6, 0 }, { -0.3, -0.2, -1.1 }, 0), -- o cantil no cinto, atrás do quadril
			k(0.75, { 1.25, 0.15, -0.75 }, { -0.2, 0.2, -1.05 }, 5), -- sobe por fora do corpo
			k(1.0, { 0.1, 0.6, -0.9 }, { -0.1, 0.65, -0.9 }, 10), -- abre a tampa
			k(1.4, { 0.13, 1.1, -0.81 }, { -0.35, 0.3, -1 }, 70), -- bebe
			k(1.9, { 0.13, 1.12, -0.8 }, { -0.35, 0.3, -1 }, 75),
			k(2.4, { 0.13, 1.1, -0.81 }, { -0.35, 0.3, -1 }, 70),
			k(2.9, { 0.1, 0.6, -0.9 }, { -0.1, 0.65, -0.9 }, 10),
			k(3.05, { 1.25, 0.15, -0.75 }, { -0.2, 0.2, -1.05 }, 5),
			k(3.2, { 1.3, -0.6, 0 }, { -0.3, -0.2, -1.1 }, 0),
			k(3.35, { 1.2, -0.1, -0.85 }, { -0.4, -0.1, -1.15 }, 0), -- volta por fora do corpo
			k(3.5, { 0.45, 0, -1.2 }, { -0.45, 0, -1.2 }, 0),
		},
		fp = {
			k(0, FP_R0, FP_L0, 0),
			k(0.5, { 0.28, -0.45, -0.18 }, { -0.16, -0.42, -0.3 }, 0),
			k(1.0, { 0.04, -0.2, -0.3 }, { -0.04, -0.18, -0.3 }, 10),
			k(1.4, { 0.0, -0.11, -0.14 }, { -0.18, -0.36, -0.3 }, 70),
			k(1.9, { 0.0, -0.1, -0.13 }, { -0.18, -0.36, -0.3 }, 75),
			k(2.4, { 0.0, -0.11, -0.14 }, { -0.18, -0.36, -0.3 }, 70),
			k(2.9, { 0.04, -0.2, -0.3 }, { -0.04, -0.18, -0.3 }, 10),
			k(3.2, { 0.28, -0.45, -0.18 }, { -0.16, -0.42, -0.3 }, 0),
			k(3.5, FP_R0, FP_L0, 0),
		},
		poseR = "grip",
		poseL = "flat",
		prop = { kind = "cantil", hand = "R", from = 0.5, to = 3.2 },
	},
} :: { [string]: Anim }

-- Ações do servidor (atributo "VT65Acao") e itens que o cliente manda (atributo "VT65Item").
ItemAnim.ACTIONS = { bandage = true, tourniquet = true, bandage_other = true, treat = true, revive = true }
ItemAnim.ITEMS = { radio = true, binoculars = true, shovel = true, canteen = true }

-- Objetos na mão (m): tamanho e cor (RGB 0-255). Medidas reais: curativo de campanha em rolo (~7 cm),
-- torniquete de tira com haste (~10 cm), fone H-138 (~21 cm), binóculo 7x50 M17 (~17 x 12 cm), pá de
-- trincheira M1956 (cabo ~0,55 m, lâmina 20 x 15 cm), cantil de 1 quarto (18 x 12 x 7 cm).
ItemAnim.PROPS = {
	curativo = { size = { 0.07, 0.05, 0.05 }, rgb = { 196, 190, 160 } },
	torniquete = { size = { 0.10, 0.014, 0.014 }, rgb = { 40, 38, 34 } },
	fone = { size = { 0.05, 0.21, 0.05 }, rgb = { 30, 30, 28 } },
	binoculo = { size = { 0.17, 0.065, 0.12 }, rgb = { 26, 26, 24 } },
	pa = { size = { 0.035, 0.035, 0.55 }, rgb = { 84, 88, 60 }, blade = { 0.2, 0.15, 0.01 } },
	cantil = { size = { 0.12, 0.17, 0.07 }, rgb = { 70, 74, 50 } },
} :: { [string]: { size: V, rgb: V, blade: V? } }

-- Tempo dentro das chaves (s) no instante t da ação de duração total D (nil: segurado, sem fim).
function ItemAnim.localTime(a: Anim, t: number, D: number?): number
	local tail = a.dur - a.loop.b
	local span = math.max(a.loop.b - a.loop.a, 1e-3)
	if t < a.loop.a then
		return math.max(t, 0)
	end
	if D and t > D - tail then
		return math.min(a.loop.b + (t - (D - tail)), a.dur)
	end
	return a.loop.a + (t - a.loop.a) % span
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a: V, b: V, u: number): V
	return { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u }
end

-- Mãos (direita, esquerda) e giro do objeto (graus) no tempo tt das chaves.
function ItemAnim.sample(keys: { Key }, tt: number): (V, V, number)
	if tt <= keys[1].t then
		return keys[1].r, keys[1].l, keys[1].tilt or 0
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if tt < b.t then
			local u = smooth((tt - a.t) / math.max(b.t - a.t, 1e-3))
			return lerp(a.r, b.r, u), lerp(a.l, b.l, u), (a.tilt or 0) + ((b.tilt or 0) - (a.tilt or 0)) * u
		end
	end
	local z = keys[#keys]
	return z.r, z.l, z.tilt or 0
end

-- O objeto aparece na mão neste tempo das chaves?
function ItemAnim.propOn(a: Anim, tt: number): boolean
	local p = a.prop
	if not p then
		return false
	end
	return tt >= (p.from or 0) and tt <= (p.to or math.huge)
end

-- Alcance do braço do corpo gravado (tools/anim/r15.py): ombro em (±1,0; 0,703; 0) e 2,15 studs do
-- ombro ao centro da mão. Um alvo além de REACH (cotovelo ainda dobrado) é puxado para o ombro,
-- na mesma direção: o braço não estica até travar (no Lune: tests/luau/faca, "itens").
ItemAnim.SHOULDER = { R = { 1.0, 0.703, 0.0 }, L = { -1.0, 0.703, 0.0 } } :: { [string]: V }
ItemAnim.REACH = 1.95

function ItemAnim.reach(p: V, side: string): V
	local s = ItemAnim.SHOULDER[side] or ItemAnim.SHOULDER.R
	local d = { p[1] - s[1], p[2] - s[2], p[3] - s[3] }
	local n = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
	if n <= ItemAnim.REACH or n < 1e-6 then
		return p
	end
	local k = ItemAnim.REACH / n
	return { s[1] + d[1] * k, s[2] + d[2] * k, s[3] + d[3] * k }
end

-- O que o soldado está usando agora, pelos atributos do personagem (get = GetAttribute), no relógio
-- do servidor `now`: ação médica ("VT65Acao", "VT65AcaoT", "VT65AcaoS") ou item ("VT65Item",
-- "VT65ItemT"; a pá dura digS, o cantil o nominal, rádio e binóculo enquanto o atributo existir).
-- Devolve nome, tempo desde o começo e duração (nil = segurado).
function ItemAnim.current(get: (string) -> any, now: number, digS: number): (string?, number, number?)
	local acao, t0 = get("VT65Acao"), get("VT65AcaoT")
	if type(acao) == "string" and ItemAnim.ANIMS[acao] and type(t0) == "number" then
		local s = get("VT65AcaoS")
		local D = if type(s) == "number" then s else ItemAnim.ANIMS[acao].dur
		if now - t0 <= D then
			return acao, math.max(now - t0, 0), D
		end
	end
	local it, i0 = get("VT65Item"), get("VT65ItemT")
	if type(it) == "string" and ItemAnim.ANIMS[it] and type(i0) == "number" then
		local D: number? = if it == "shovel"
			then digS
			elseif ItemAnim.ANIMS[it].held then nil
			else ItemAnim.ANIMS[it].dur
		if not D or now - i0 <= D then
			return it, math.max(now - i0, 0), D
		end
	end
	return nil, 0, nil
end

-- Duração das ações do servidor (s), para quem não recebeu "VT65AcaoS".
function ItemAnim.duration(name: string): number?
	local a = ItemAnim.ANIMS[name]
	return if a and not a.held then a.dur else nil
end

return ItemAnim
