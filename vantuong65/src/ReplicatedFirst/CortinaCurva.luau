--!strict
-- D-215: a conta da cortina das transições (Cortina), pura, para o teste no Lune. A cortina é um
-- quadrado grande, inclinado, que atravessa a tela da esquerda para a direita: cobre, segura com o
-- título da próxima tela e segue saindo pela direita (o "passar a página" das telas de jogo de luta das
-- referências do dono: a moldura fica e o conteúdo troca por baixo).
local CortinaCurva = {}

CortinaCurva.INCLINA = 14 -- graus
CortinaCurva.TEMPO = { entra = 0.34, segura = 0.2, sai = 0.4 } -- s
CortinaCurva.TEMPO_CALMO = { entra = 0.16, segura = 0.12, sai = 0.2 } -- movimento reduzido: esmaece

-- Lado do quadrado (px) e as três posições do centro em X (px): fora à esquerda, cobrindo, fora à
-- direita, para uma tela de W x H. O quadrado tem 2,4 vezes o maior lado da tela: o círculo dentro
-- dele (raio 1,2 M) passa da meia diagonal da tela (no máximo 0,71 M), então cobre girado.
function CortinaCurva.posicoes(W: number, H: number, inclina: number?): (number, number, number, number)
	local M = math.max(W, H)
	local lado = 2.4 * M
	local a = math.rad(inclina or CortinaCurva.INCLINA)
	-- meia largura do quadrado girado, no eixo X da tela
	local hx = (lado / 2) * (math.abs(math.cos(a)) + math.abs(math.sin(a)))
	local folga = 8
	return lado, -hx - folga, W / 2, W + hx + folga
end

-- Os quatro cantos do quadrado (centro cx, cy; lado; giro em graus), para o teste conferir a cobertura.
function CortinaCurva.cantos(cx: number, cy: number, lado: number, inclina: number): { { number } }
	local a = math.rad(inclina)
	local c, s = math.cos(a), math.sin(a)
	local h = lado / 2
	local out = {}
	for _, d in { { -h, -h }, { h, -h }, { h, h }, { -h, h } } do
		table.insert(out, { cx + d[1] * c - d[2] * s, cy + d[1] * s + d[2] * c })
	end
	return out
end

-- O ponto (x, y) está dentro do quadrado girado?
function CortinaCurva.dentro(x: number, y: number, cx: number, cy: number, lado: number, inclina: number): boolean
	local a = math.rad(-inclina)
	local dx, dy = x - cx, y - cy
	local lx = dx * math.cos(a) - dy * math.sin(a)
	local ly = dx * math.sin(a) + dy * math.cos(a)
	return math.abs(lx) <= lado / 2 and math.abs(ly) <= lado / 2
end

-- Curva de cada trecho (0 a 1): entra freando no fim (cobre firme), sai acelerando no começo (a
-- página "puxa").
function CortinaCurva.entra(u: number): number
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) ^ 4
end
function CortinaCurva.sai(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * u
end

return CortinaCurva
