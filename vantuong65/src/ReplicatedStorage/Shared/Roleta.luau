--!strict
-- Roleta horizontal da abertura das caixas (D-177, pedido do dono: "roleta estilo Counter-Strike",
-- com identidade própria). PURO (Lune: tests/luau/roleta.luau). Só a APRESENTAÇÃO: o resultado já
-- vem gravado do servidor (CaixaRegras.aplicar); a roleta monta a faixa para parar nele.
-- Regras (o pedido e a política de itens aleatórios pagos):
--   - os cartões de enchimento são sorteados com os MESMOS pesos que o servidor mostra na lista
--     (cada um independente, sem olhar o vencedor): nada de pôr item raro ao lado do vencedor para
--     fingir que "quase saiu";
--   - a parada é exata no centro do cartão vencedor (sem deslocamento que finja "por pouco");
--   - o vencedor fica perto do fim da faixa (há cartões depois dele: a faixa nunca acaba vazia).
local Caixas = require(script and (script :: any).Parent.Caixas or "./Caixas") :: any

local Roleta = {}

Roleta.TOTAL = 48 -- cartões na faixa
Roleta.POS_VENCEDOR = 42 -- índice do vencedor (6 depois dele)
Roleta.INICIO = 3 -- cartão no marcador quando a roleta começa
-- duração (s) por ajuste de efeitos (CaixasTela: completa, curta; "sem" pula a roleta)
Roleta.DURACAO = { completa = 6.0, curta = 2.6 } :: { [string]: number }

export type Entrada = { item: string, peso: number }

-- Faixa de Roleta.TOTAL ids com o vencedor em POS_VENCEDOR. `sorteio()` devolve um inteiro em
-- [0, Caixas.ESCALA) (no cliente, Random; no teste, o gerador fixo). `lista`: os pesos efetivos
-- que a tela mostra (a soma é Caixas.ESCALA).
function Roleta.faixa(lista: { Entrada }, vencedor: string, sorteio: () -> number): { string }
	assert(#lista > 0, "lista vazia")
	local out: { string } = table.create(Roleta.TOTAL)
	for i = 1, Roleta.TOTAL do
		if i == Roleta.POS_VENCEDOR then
			out[i] = vencedor
		else
			out[i] = Caixas.escolher(lista, sorteio()).item
		end
	end
	return out
end

-- Quantos cartões cabem na largura (ímpar, de 3 até `maximo`, 7 se não disser): 5 a 7 no PC,
-- até 5 no celular (o cartão não fica pequeno demais para o dedo e o olho).
function Roleta.visiveis(largura: number, minCartao: number, maximo: number?): number
	local n = math.floor(largura / math.max(minCartao, 1))
	n = math.clamp(n, 3, math.max(3, maximo or 7))
	if n % 2 == 0 then
		n -= 1
	end
	return n
end

-- Largura do cartão para `n` cartões e `gap` entre eles caberem em `largura`.
function Roleta.larguraCartao(largura: number, n: number, gap: number): number
	return math.floor((largura - gap * (n - 1)) / n)
end

-- Posição X da faixa (em pixels, relativa à janela) que põe o CENTRO do cartão `i` no centro da
-- janela. Os cartões ficam em x = (i - 1) * (cartao + gap) dentro da faixa.
function Roleta.posicao(i: number, cartao: number, gap: number, janela: number): number
	return janela / 2 - ((i - 1) * (cartao + gap) + cartao / 2)
end

-- Índice do cartão sob o marcador (centro da janela) com a faixa em `x`. Entre dois cartões (no
-- vão), devolve o da esquerda.
function Roleta.noMarcador(x: number, cartao: number, gap: number, janela: number): number
	local p = janela / 2 - x -- distância do início da faixa até o marcador
	return math.floor(p / (cartao + gap)) + 1
end

-- Curva de desaceleração (0..1 -> 0..1): começa rápida e para devagar, sem tranco no fim
-- (derivada zero em t = 1). Igual à EasingStyle.Quint, direção Out.
function Roleta.curva(t: number): number
	local u = 1 - math.clamp(t, 0, 1)
	return 1 - u * u * u * u * u
end

return Roleta
