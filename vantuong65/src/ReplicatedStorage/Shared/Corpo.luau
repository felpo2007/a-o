--!strict
-- Tamanho do soldado (D-98). Módulo PURO (Lune e Roblox).
-- Decisão do dono (2026-11-12): "os personagens estão muito pequenos em relação ao mapa; coloque eles
-- com 2 m de altura". É escolha de jogo, não medida histórica: o fuzileiro médio de 1965 tinha
-- ~1,75 m, e o soldado do jogo é esse corpo ampliado por igual (altura, largura, profundidade e
-- cabeça) por K = 2,0 / 1,75.
-- Tudo o que foi medido ou gravado no corpo de 1,75 m (juntas do R15 no tools/anim, clipes, pegas do
-- fuzil, polos do IK, equipamento do Gear) continua nesses números e é multiplicado por K onde vira
-- posição no jogo. As animações seguem sem regravar: o Animator escala a translação da Root por
-- HipHeight / AuthoredHipHeight, e o HipHeight cresce junto com o corpo (PostureService.DROP e
-- MIN_HIP também foram multiplicados por K).
-- Armas e facas ficam no tamanho real (a M14 continua com 1,126 m).
local Corpo = {}

Corpo.HEIGHT_M = 2.0 -- altura do soldado no jogo (decisão do dono)
Corpo.BASE_HEIGHT_M = 1.75 -- corpo em que clipes, pegas e medidas foram feitos (D-77)
Corpo.K = Corpo.HEIGHT_M / Corpo.BASE_HEIGHT_M

-- Distância (studs ou m) do corpo antigo levada ao corpo do jogo.
function Corpo.s(v: number): number
	return v * Corpo.K
end

-- ===== formato do Front 44 (D-102) =====
-- Pedido do dono: "faça os personagens do mesmo formato do Front 44". O Front 44 hoje (0.28.0, a D-102
-- de lá: "voltar com os bonecos do roblox"; Config.Bodies.Blocky = true, Realistic = false) usa o
-- boneco de BLOCO clássico do R15: peças padrão (tronco, braços, pernas e cabeça = 0), todas as
-- escalas iguais (altura = largura = profundidade = cabeça; tipo de corpo e proporção 0), cabeça de
-- bloco com o rosto em decalque, pele lisa na cabeça e nas mãos, farda em Shirt/Pants clássicos com
-- tecido nas peças, capacete e equipamento em peças por cima. Lá o boneco tem escala 1 (~5 studs,
-- ~1,4 m na escala da arma). Aqui as mesmas proporções na escala que dá o soldado de 2 m: a escala
-- da altura do corpo de 1,75 m (1,25) vezes K, em TODOS os eixos. Fica com 2,04 m (a cabeça de bloco
-- é 4 cm mais alta que a do "Man") e 0,8 m de ombro a ombro (o tronco de bloco tem 2 studs de largura
-- por 5 de altura).
Corpo.BLOCK_SCALE = 1.25 * Corpo.K
-- Corpo em uso: "bloco" (formato do Front 44) ou "man" (o de antes, D-98). O Characters segue isto.
Corpo.FORMATO = "bloco"
-- Fator na LARGURA e na PROFUNDIDADE em relação ao corpo gravado (r15 do tools/anim: largura 1, altura
-- 1,25). No "man" é K (tudo por igual); no bloco é 1,25 x K: o tronco fica 25% mais largo e fundo que
-- o gravado vezes K. Usado onde uma pega encosta no lado ou nas costas (fuzil a tiracolo).
Corpo.KX = if Corpo.FORMATO == "bloco" then Corpo.BLOCK_SCALE else Corpo.K
-- Mão de bloco mais estreita (largura e profundidade; o comprimento fica): no R15 de bloco a mão tem a
-- largura do braço, 40 cm no soldado de 2 m, e engolia o punho e o guarda-mão da arma de tamanho real
-- (foto do dono, 2026-11-13: "mãos enormes"). 0,55 = 22 cm. PLACEHOLDER: conferir no Studio.
Corpo.MAO_K = if Corpo.FORMATO == "bloco" then 0.55 else 1

-- Rostos de época (tools/rostos/make_rostos.py -> assets/rostos/*.png, decalques da cabeça de bloco).
-- Ids das imagens publicadas (0 = ainda não subiu; fica o rosto padrão do Roblox, como nos bots do
-- Front 44). A ordem é a dos arquivos rosto_<lado>_NN.png.
Corpo.ROSTOS = {
	-- IDs de IMAGEM (o decal publicado foi aberto no Studio e lido o Texture; os IDs dos decals estão
	-- em assets/roblox_ids.json, "Rostos.*")
	US = {
		79354813339241,
		87900435042207,
		124645966462677,
		81395332449469,
		132336006077589,
		135367952507187,
		117165887504830,
		85768954487659,
		110718422633744,
		123935090023939,
		94860476762265,
		91122845478942,
	},
	VC = {
		130820863395776,
		98519487536490,
		107023904829579,
		91876326725895,
		110570675804559,
		121638585178440,
		120321533547987,
		85929185938512,
		104636747932071,
		118279338810209,
		98402693800939,
		71892576492432,
	},
} :: { [string]: { number } }

-- Tons de pele (cabeça e mãos), como os do Front 44 (Main.server SKIN): do claro ao escuro. Fuzileiros
-- de 1965 de todas as origens; os do VC no tom do Sul do Vietnã, sol de campo. Escolha pela semente.
Corpo.PELE = {
	US = { { 238, 206, 178 }, { 224, 182, 148 }, { 204, 158, 120 }, { 160, 114, 82 }, { 116, 80, 56 } },
	VC = { { 226, 184, 146 }, { 212, 168, 128 }, { 196, 150, 110 }, { 178, 132, 96 } },
} :: { [string]: { { number } } }

-- Tom de pele e rosto de um soldado (pela semente: UserId do jogador ou número do bot).
function Corpo.pele(faction: string?, seed: number?): { number }
	local list = Corpo.PELE[faction or "US"] or Corpo.PELE.US
	return list[1 + (math.floor(math.abs(seed or 0)) % #list)]
end

function Corpo.rosto(faction: string?, seed: number?): number
	local list = Corpo.ROSTOS[faction or "US"] or Corpo.ROSTOS.US
	-- outro passo da semente que o da pele, para não casar sempre o mesmo rosto com o mesmo tom
	return list[1 + (math.floor(math.abs(seed or 0) / 7) % #list)]
end

return Corpo
