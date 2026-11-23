--!strict
-- Efeito das explosões (D-198; prompt de jogabilidade, item 17). Módulo PURO (tests/luau/explosao.luau),
-- usado pelo Controllers/ExplosionFx (imagem) e pelo AudioController (som).
-- Três parâmetros independentes:
-- - tamanho do efeito: aqui (escala, classe);
-- - raio de dano: Shared/Explosive (lethalM, casualtyM);
-- - empurrão dos corpos: Shared/Explosive (impulsoM; sem ele, o casualtyM).
-- Assim a bomba do A-4 pode parecer enorme sem que o mapa inteiro vire área letal.
local Rng = require(script and (script :: any).Parent.Rng or "./Rng") :: any

local ExplosaoEfeito = {}

-- escala: 1 = granada de mão (o tamanho do ExplosionFx); classe "pesada" ganha a explosão grande
-- (clarão, bola de fogo que sobe, anel de poeira no chão, coluna de fumaça, detritos e cauda no som).
-- colunaS: quanto a coluna de fumaça fica; detritos: pedaços com física (o teto, perto e em alta).
-- PLACEHOLDER de efeito (a olho no Studio).
export type Tipo = { escala: number, classe: string, colunaS: number?, detritos: number? }
ExplosaoEfeito.TIPOS = {
	grenade_us = { escala = 1, classe = "leve" },
	grenade_vc = { escala = 0.9, classe = "leve" },
	rocket_35 = { escala = 1.3, classe = "leve" },
	pg2 = { escala = 1.3, classe = "leve" },
	he_90 = { escala = 1.6, classe = "media" },
	heat_106 = { escala = 1.6, classe = "media" },
	veiculo = { escala = 1.6, classe = "media" },
	mortar_81 = { escala = 1.8, classe = "media" },
	mortar_82 = { escala = 1.8, classe = "media" },
	naval_5in = { escala = 3.2, classe = "pesada", colunaS = 12, detritos = 9 },
	bomb_250lb = { escala = 4.4, classe = "pesada", colunaS = 16, detritos = 12 },
} :: { [string]: Tipo }

function ExplosaoEfeito.de(id: string): Tipo
	return ExplosaoEfeito.TIPOS[id] or { escala = 1.5, classe = "media" }
end

-- Superfície embaixo da explosão: água, estrutura (peça que colide: casa, parede, sacos, ponte),
-- vegetação (capim e mata do terreno, folhagem) ou terra.
export type Superficie = "agua" | "estrutura" | "vegetacao" | "terra"
local VEGETACAO_TERRENO = { LeafyGrass = true, Grass = true } :: { [string]: boolean }
function ExplosaoEfeito.superficie(material: string, ehTerreno: boolean, nome: string?): Superficie
	if material == "Water" or nome == "PaddyWater" then
		return "agua"
	end
	if not ehTerreno then
		local n = string.lower(nome or "")
		if
			string.find(n, "folha", 1, true)
			or string.find(n, "tronco", 1, true)
			or string.find(n, "arvore", 1, true)
		then
			return "vegetacao"
		end
		return "estrutura"
	end
	if VEGETACAO_TERRENO[material] then
		return "vegetacao"
	end
	return "terra"
end

-- Cores da poeira e dos pedaços por superfície (RGB)
ExplosaoEfeito.CORES = {
	terra = { poeira = { 150, 122, 92 }, pedaco = { 86, 68, 48 } },
	vegetacao = { poeira = { 126, 118, 86 }, pedaco = { 72, 92, 44 } },
	estrutura = { poeira = { 150, 146, 138 }, pedaco = { 110, 88, 64 } },
	agua = { poeira = { 232, 236, 234 }, pedaco = { 214, 222, 224 } },
} :: { [string]: { poeira: { number }, pedaco: { number } } }

-- Variação de cada explosão (semente): quantos lóbulos de fogo, o giro, o ritmo e o tamanho. Iguais
-- para a mesma semente, discretas (±12% no tamanho, ±15% no ritmo).
export type Variacao = { lobos: number, giro: number, tempoK: number, tamanhoK: number, inclina: number }
function ExplosaoEfeito.variacao(seed: number): Variacao
	local r = Rng.new(seed)
	return {
		lobos = 3 + math.floor(r:next() * 3),
		giro = r:range(0, 2 * math.pi),
		tempoK = r:range(0.85, 1.15),
		tamanhoK = r:range(0.88, 1.12),
		inclina = r:range(-0.12, 0.12), -- a coluna pende um pouco (rad)
	}
end

-- Detalhe pela distância (m) e pela qualidade gráfica (1 a 10): 1 = tudo; cai com a distância e a
-- qualidade, mas nunca abaixo de 0,25 (a explosão segue reconhecível de longe).
function ExplosaoEfeito.detalhe(distM: number, qualidade: number): number
	local d = if distM <= 150 then 1 elseif distM >= 900 then 0.35 else 1 - 0.65 * (distM - 150) / 750
	local q = 0.55 + 0.45 * math.clamp((qualidade - 1) / 9, 0, 1)
	return math.max(d * q, 0.25)
end

-- Ao mesmo tempo, no máximo (o resto sai mais simples): explosões grandes completas, luzes e
-- pedaços com física.
ExplosaoEfeito.LIMITES = { grandes = 3, luzes = 4, detritos = 40 }

-- Tremor da câmera (0 a 1,5): forte perto, some no alcance (45 m vezes a escala), vezes o ajuste
-- do jogador (Configurações, "Tremor das explosões", 0 a 1).
function ExplosaoEfeito.tremor(distM: number, escala: number, ajuste: number): number
	local alcance = 45 * escala
	if distM >= alcance then
		return 0
	end
	local k = (1 - distM / alcance) ^ 2 * (0.6 + 0.25 * escala)
	return math.clamp(k * math.clamp(ajuste, 0, 1), 0, 1.5)
end

-- Som: o estrondo chega pela velocidade do som (Ballistics.SOUND ~343 m/s); a cauda (o eco pelo
-- vale e pela mata) vem logo depois, mais grave e longa, só nas pesadas.
ExplosaoEfeito.SOM_MS = 343
function ExplosaoEfeito.atrasoSom(distM: number): number
	return math.max(distM, 0) / ExplosaoEfeito.SOM_MS
end

return ExplosaoEfeito
