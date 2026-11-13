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

return Corpo
