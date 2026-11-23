--!strict
-- D-238 (dono: "o jeito que o personagem recarrega, tem que ser perfeito e sensacional"). Módulo PURO:
-- a sequência da recarga de 3ª pessoa, vista por todos, nos jogadores e nos bots. O servidor grava o
-- início e a duração no soldado (atributos VT65RecargaIni e VT65RecargaDur, no relógio do servidor) e
-- cada cliente calcula o mesmo instante.
-- Sequência do carregador: a mão vai ao carregador, puxa, leva à cartucheira, traz outro, encaixa, dá o
-- tapa, puxa o ferrolho e volta ao guarda-mão. A arma gira para mostrar o encaixe.
local Recarga = {}

export type Chave = { t: number, alvo: string, mag: boolean? }
export type Tipo = string -- "caixa" | "tubo" | "cinta"

-- stylua: ignore
Recarga.CAIXA = {
	{ t = 0.00, alvo = "apoio" },
	{ t = 0.12, alvo = "carregador" },
	{ t = 0.22, alvo = "abaixo", mag = true },
	{ t = 0.38, alvo = "bolsa", mag = true },
	{ t = 0.46, alvo = "bolsa", mag = true },
	{ t = 0.58, alvo = "abaixo", mag = true },
	{ t = 0.66, alvo = "carregador", mag = true },
	{ t = 0.70, alvo = "tapa" },
	{ t = 0.74, alvo = "carregador" },
	{ t = 0.80, alvo = "alavanca" },
	{ t = 0.86, alvo = "alavancaAtras" },
	{ t = 0.93, alvo = "apoio" },
	{ t = 1.00, alvo = "apoio" },
} :: { Chave }

-- stylua: ignore
Recarga.CINTA = {
	{ t = 0.00, alvo = "apoio" },
	{ t = 0.10, alvo = "alavanca" },
	{ t = 0.18, alvo = "alavancaAtras" },
	{ t = 0.28, alvo = "carregador" },
	{ t = 0.40, alvo = "bolsa", mag = true },
	{ t = 0.50, alvo = "bolsa", mag = true },
	{ t = 0.64, alvo = "carregador", mag = true },
	{ t = 0.72, alvo = "tapa" },
	{ t = 0.82, alvo = "alavanca" },
	{ t = 0.88, alvo = "alavancaAtras" },
	{ t = 0.95, alvo = "apoio" },
	{ t = 1.00, alvo = "apoio" },
} :: { Chave }

-- cartucho a cartucho: a mão vai à cartucheira e empurra na janela, três vezes
-- stylua: ignore
Recarga.TUBO = {
	{ t = 0.00, alvo = "apoio" },
	{ t = 0.10, alvo = "bolsa", mag = true },
	{ t = 0.22, alvo = "carregador", mag = true },
	{ t = 0.27, alvo = "tapa" },
	{ t = 0.38, alvo = "bolsa", mag = true },
	{ t = 0.50, alvo = "carregador", mag = true },
	{ t = 0.55, alvo = "tapa" },
	{ t = 0.66, alvo = "bolsa", mag = true },
	{ t = 0.78, alvo = "carregador", mag = true },
	{ t = 0.83, alvo = "tapa" },
	{ t = 0.93, alvo = "apoio" },
	{ t = 1.00, alvo = "apoio" },
} :: { Chave }

function Recarga.tipo(feed: string?, kind: string?): Tipo
	if feed == "tube" then
		return "tubo"
	elseif kind == "mg" then
		return "cinta"
	end
	return "caixa"
end

local function chaves(tipo: Tipo): { Chave }
	return if tipo == "tubo" then Recarga.TUBO elseif tipo == "cinta" then Recarga.CINTA else Recarga.CAIXA
end

-- Fração da recarga (0..1) ou nil fora dela.
function Recarga.progresso(ini: any, dur: any, agora: number): number?
	if type(ini) ~= "number" or type(dur) ~= "number" or dur <= 0 then
		return nil
	end
	local p = (agora - ini) / dur
	return if p >= 0 and p < 1 then p else nil
end

local function liso(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Quanto a arma está na pose de recarga (entra e sai suave).
function Recarga.envelope(p: number): number
	return liso(p / 0.1) * (1 - liso((p - 0.91) / 0.09))
end

-- Onde a mão esquerda está: alvo de partida, alvo de chegada, mistura e se há carregador na mão.
function Recarga.mao(tipo: Tipo, p: number): (string, string, number, boolean)
	local lista = chaves(tipo)
	for i = 1, #lista - 1 do
		local a, b = lista[i], lista[i + 1]
		if p >= a.t and p < b.t then
			return a.alvo, b.alvo, liso((p - a.t) / (b.t - a.t)), a.mag == true
		end
	end
	local fim = lista[#lista]
	return fim.alvo, fim.alvo, 1, false
end

-- Giro da arma (graus) e deslocamento (studs): mostra o encaixe, sente o tapa e o ferrolho.
function Recarga.arma(tipo: Tipo, p: number): (number, number, number, number)
	local e = Recarga.envelope(p)
	local arfa, rola = 9 * e, 24 * e
	local sobe, recua = 0, 0
	if tipo == "tubo" then
		rola = -16 * e -- a janela do cartucho fica para o lado da mão
		for _, q in { 0.27, 0.55, 0.83 } do
			sobe += 0.03 * math.max(0, 1 - math.abs(p - q) / 0.035)
		end
	else
		local tapa = if tipo == "cinta" then 0.72 else 0.7
		sobe = 0.07 * math.max(0, 1 - math.abs(p - tapa) / 0.03)
		local rack = if tipo == "cinta" then 0.88 else 0.86
		recua = 0.09 * math.max(0, 1 - math.abs(p - rack) / 0.04)
		arfa += 7 * math.max(0, 1 - math.abs(p - rack) / 0.08)
	end
	return arfa, rola, sobe, recua
end

return Recarga
