--!strict
-- D-213 (pedido do dono de 20/11: "faça uma nova animação perfeita e realista com efeitos visuais para
-- a loja e para a abertura das caixas itens etc"): a matemática dos efeitos de interface, pura (sem
-- instância), para a tela e para o teste no Lune. Quem desenha é o Controllers/UiEfeitos.
--
-- A abertura da caixa tem um roteiro (segundos desde o começo):
--   queda (a caixa cai do alto) -> pouso (baque, poeira, tranco) -> tremor (sacode cada vez mais,
--   faíscas escapando pela fresta) -> estouro (clarão, a tampa voa, faíscas, onda, raios) -> saída
--   (a caixa recua para o fundo e a roleta entra) -> fim.
-- A cor da abertura é a da CAIXA, nunca a do item sorteado: o resultado só aparece na roleta (nada de
-- adiantar nem de fingir um "quase").
-- Tudo é função do tempo (fórmula fechada): o quadro lento não muda a trajetória.
local Efeitos = {}

export type Roteiro = {
	pouso: number,
	tremor: number,
	estouro: number,
	saida: number,
	fim: number,
}

Efeitos.ROTEIRO = {
	completa = { pouso = 0.42, tremor = 0.62, estouro = 1.62, saida = 2.15, fim = 2.45 },
	curta = { pouso = 0.0, tremor = 0.05, estouro = 0.35, saida = 0.6, fim = 0.75 },
} :: { [string]: Roteiro }

-- ===== a caixa =====
-- queda: deslocamento vertical (em alturas da caixa, negativo = acima) de 0 até o pouso, acelerando
-- como na gravidade
function Efeitos.queda(t: number, pouso: number): number
	if pouso <= 0 or t >= pouso then
		return 0
	end
	local u = math.max(0, t) / pouso
	return -1.4 * (1 - u * u)
end

-- o tranco do pouso: (largura, altura) multiplicadas, amassando e voltando com uma mola amortecida
function Efeitos.amasso(dt: number): (number, number)
	if dt < 0 then
		return 1, 1
	end
	local k = 0.1 * math.exp(-dt * 11) * math.cos(dt * 34)
	return 1 + k * 0.6, 1 - k
end

-- tremor: (dx, dy em frações da caixa; giro em graus) no instante t de uma sacudida de `dur` s. A força
-- e a frequência sobem até o estouro (cada vez mais forte e mais rápido); `forca` 0 deixa parado.
function Efeitos.tremor(t: number, dur: number, forca: number): (number, number, number)
	if forca <= 0 or dur <= 0 or t < 0 then
		return 0, 0, 0
	end
	local u = math.clamp(t / dur, 0, 1)
	local a = forca * (0.2 + 0.8 * u ^ 1.6)
	local fase = 2 * math.pi * (8 * t + 7 * t * t / dur)
	local dx = a * 0.035 * math.sin(fase)
	local dy = -a * 0.03 * math.abs(math.sin(fase * 0.5)) -- pulinhos: só para cima
	local giro = a * 6 * math.sin(fase * 1.13 + 1.7)
	return dx, dy, giro
end

-- a tampa depois do estouro: (dx, dy em frações da caixa, giro em graus, transparência 0 a 1). Sobe
-- rápido, tomba para o lado e some.
function Efeitos.tampa(t: number): (number, number, number, number)
	if t <= 0 then
		return 0, 0, 0, 0
	end
	local vx, vy, g = 0.55, -2.6, 4.2
	local dx = vx * t
	local dy = vy * t + 0.5 * g * t * t
	local giro = 160 * t + 120 * t * t
	local tr = math.clamp((t - 0.3) / 0.45, 0, 1)
	return dx, dy, giro, tr
end

-- ===== partículas =====
-- gerador com semente (MINSTD, contas exatas em double, como o Calendario.pick): igual no Roblox e
-- no Lune, que não tem o Random
local function gerador(semente: number): () -> number
	local s = math.floor(math.abs(semente)) % 2147483646 + 1
	return function(): number
		s = (s * 48271) % 2147483647
		return (s - 1) / 2147483646
	end
end

export type Faisca = {
	ang: number, -- direção em radianos (0 = direita, -pi/2 = para cima na tela)
	vel: number, -- px/s no começo
	vida: number, -- s
	tam: number, -- fração do tamanho base
	atraso: number, -- s antes de nascer
	brilho: boolean, -- bolinha de luz (lenta e grande) em vez de rastro
}

-- quantas faíscas cada raridade solta (a da caixa no estouro usa "caixa"); com efeitos curtos, 60 %;
-- sem efeitos, nenhuma
local QUANTAS = { comum = 16, incomum = 22, raro = 34, epico = 48, lendario = 64, caixa = 40 }
function Efeitos.quantas(raridade: string?, modo: string?): number
	if modo == "sem" then
		return 0
	end
	local n = QUANTAS[raridade or "comum"] or QUANTAS.comum
	return if modo == "curta" then math.floor(n * 0.6) else n
end

-- força da luz por raridade (halo, raios, tremor da recompensa)
Efeitos.FORCA = { comum = 0.55, incomum = 0.7, raro = 0.9, epico = 1.15, lendario = 1.4 } :: { [string]: number }

-- uma explosão de `n` faíscas: `cone` é a direção do meio (radianos) e `abertura` o leque inteiro;
-- velocidades entre vmin e vmax. Mesma semente, mesma explosão.
function Efeitos.faiscas(
	n: number,
	semente: number,
	cone: number,
	abertura: number,
	vmin: number,
	vmax: number
): { Faisca }
	local r = gerador(semente)
	local out: { Faisca } = {}
	for _ = 1, n do
		local brilho = r() < 0.28
		table.insert(out, {
			ang = cone + (r() - 0.5) * abertura,
			vel = (vmin + (vmax - vmin) * r() ^ 0.7) * (if brilho then 0.45 else 1),
			vida = (if brilho then 0.9 else 0.55) + r() * 0.5,
			tam = 0.6 + r() * 0.8,
			atraso = r() * 0.06,
			brilho = brilho,
		})
	end
	return out
end

-- posição (px a partir do ponto de saída; y para baixo), transparência e escala de uma faísca `t` s
-- depois de nascer. Arrasto `k` (1/s) e gravidade `g` (px/s²), em fórmula fechada:
--   v(t) = v0·e^(-kt) + (g/k)(1 - e^(-kt))
function Efeitos.particula(p: Faisca, t: number, g: number, k: number): (number, number, number, number)
	if t < 0 or t >= p.vida then
		return 0, 0, 1, 0
	end
	local e = math.exp(-k * t)
	local s = (1 - e) / k
	local vx, vy = math.cos(p.ang) * p.vel, math.sin(p.ang) * p.vel
	local x = vx * s
	local y = vy * s + (g / k) * (t - s)
	local u = t / p.vida
	local entra = math.clamp(t / 0.04, 0, 1)
	local tr = 1 - entra * (1 - u * u)
	local esc = p.tam * (1 - 0.5 * u)
	return x, y, tr, esc
end

-- velocidade (px/s) e direção (graus) da faísca no instante t, para alinhar o rastro
function Efeitos.rumo(p: Faisca, t: number, g: number, k: number): (number, number)
	local e = math.exp(-k * math.max(0, t))
	local vx = math.cos(p.ang) * p.vel * e
	local vy = math.sin(p.ang) * p.vel * e + (g / k) * (1 - e)
	return math.sqrt(vx * vx + vy * vy), math.deg(math.atan2(vy, vx))
end

-- ===== vida da loja =====
-- o brilho que varre um cartão: posição da faixa de -1,5 (fora, à esquerda) a 1,5 (fora, à direita);
-- passa em `dur` s no começo de cada `periodo` e fica escondida no resto
function Efeitos.varredura(t: number, periodo: number, dur: number): number
	local f = t % periodo
	if f >= dur then
		return -1.5
	end
	local u = f / dur
	u = u * u * (3 - 2 * u)
	return -1.5 + 3 * u
end

-- pulso suave de 0 a 1 (halo da caixa pronta)
function Efeitos.pulso(t: number, periodo: number): number
	return 0.5 - 0.5 * math.cos(2 * math.pi * t / periodo)
end

export type Brasa = { x0: number, vel: number, fase: number, balanco: number, freq: number, tam: number }

-- brasas subindo devagar dentro de um cartão (laço): x0 e o balanço em frações da largura
function Efeitos.brasas(n: number, semente: number): { Brasa }
	local r = gerador(semente)
	local out: { Brasa } = {}
	for _ = 1, n do
		table.insert(out, {
			x0 = 0.12 + r() * 0.76,
			vel = 0.1 + r() * 0.12, -- alturas por segundo
			fase = r(),
			balanco = 0.02 + r() * 0.04,
			freq = 0.4 + r() * 0.6,
			tam = 0.6 + r() * 0.8,
		})
	end
	return out
end

-- (x, y em frações do quadro, transparência) de uma brasa no instante t: nasce embaixo, sobe e some
function Efeitos.brasa(b: Brasa, t: number): (number, number, number)
	local u = (t * b.vel + b.fase) % 1
	local x = b.x0 + b.balanco * math.sin(2 * math.pi * (b.freq * t + b.fase))
	local y = 1 - u
	local tr = 1 - math.sin(math.pi * u) ^ 0.8
	return x, y, tr
end

return Efeitos
