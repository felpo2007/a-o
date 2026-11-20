--!strict
-- D-202 (prompt de jogabilidade, §21): a cena da comemoração com os três melhores do time que venceu.
-- Módulo PURO (Lune e Roblox): o palco, os gestos e a sequência de cada lugar. Quem desenha é o
-- cliente (Controllers/CenaComemoracao, num ViewportFrame) com o pódio congelado no fim da partida.
--
-- Gestos procedurais, sem asset de animação: cada um dá o giro de cada junta do R15 (graus, no quadro
-- da peça de cima da junta: X para a direita, Y para cima, Z para trás) e quanto o corpo sobe (pulo).
--   - +X no ombro leva o braço para a frente e para cima (180 = esticado para o alto);
--   - +Z no ombro direito abre o braço para fora; no esquerdo, −Z;
--   - +X no cotovelo dobra o antebraço para a frente; −X no joelho dobra a perna para trás;
--   - +X no pescoço levanta o rosto.
-- A mão direita segura a arma da partida (soldada nela), então os gestos de mão livre usam a esquerda.
local Comemoracao = {}

export type Pose = { juntas: { [string]: { number } }, sobe: number }

Comemoracao.JUNTAS = {
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

-- Palco (studs, quadro da cena): o 1º no meio e mais alto, o 2º à esquerda de quem olha, o 3º à
-- direita. Cada um vira um pouco para o meio. Caixotes de madeira de 2,4 x 2,0 m.
-- O afastamento deixa os cartões (FimDeRodada) caberem embaixo de cada um sem se encostar.
-- Alturas em studs: 1,4 m, 0,9 m e 0,55 m (no Studio, com 1,0/0,65/0,4 m o 1º quase não se destacava).
Comemoracao.LUGARES = {
	[1] = { x = 0, alto = 5.0, giro = 0 },
	[2] = { x = -10.5, alto = 3.2, giro = 12 },
	[3] = { x = 10.5, alto = 2.0, giro = -12 },
} :: { [number]: { x: number, alto: number, giro: number } }
Comemoracao.CAIXOTE = { largura = 8.6, fundo = 7.1 }

local TAU = 2 * math.pi
local function sen(f: number, t: number, fase: number?): number
	return math.sin(TAU * f * t + (fase or 0))
end
-- 0..1: o meio ciclo de cima do seno e parado no de baixo (o soco no ar e a pausa). Elevar a menos de
-- 1 deixava o começo vertical: 19° num quadro (teste comemoracao)
local function pulsa(f: number, t: number): number
	return math.max(0, sen(f, t))
end

-- pernas: dobra (graus) nos dois lados; o pé volta a ficar plano
local function pernas(j: { [string]: { number } }, dobra: number)
	for _, lado in { "Left", "Right" } do
		j[lado .. "Hip"] = { dobra, 0, 0 }
		j[lado .. "Knee"] = { -2 * dobra, 0, 0 }
		j[lado .. "Ankle"] = { dobra, 0, 0 }
	end
end

-- Cada gesto: t em segundos desde o começo dele.
Comemoracao.GESTOS = {
	-- a arma levantada no alto com a direita, a esquerda em punho junto, pulinhos
	fuzil_alto = function(t: number): Pose
		local s = (sen(1.6, t) + 1) / 2
		local h = sen(1.6, t)
		local j = {
			RightShoulder = { 150 + 25 * s, 0, 12 },
			RightElbow = { 28 - 20 * s, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftShoulder = { 135 + 35 * s, 0, -18 },
			LeftElbow = { 45 - 30 * s, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			Waist = { -8, 6 * sen(0.8, t), 0 },
			Neck = { 14, 0, 0 },
		}
		pernas(j, 16 * math.max(0, -h))
		return { juntas = j, sobe = 0.7 * math.max(0, h) - 0.25 * math.max(0, -h) }
	end,
	-- o punho esquerdo batendo no ar; a arma baixa na direita
	punho = function(t: number): Pose
		local p = pulsa(1.3, t)
		local j = {
			LeftShoulder = { 95 + 70 * p, 0, -15 },
			LeftElbow = { 100 - 70 * p, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = { 22, 0, 8 },
			RightElbow = { 38, 0, 0 },
			RightWrist = { 0, 0, 0 },
			Waist = { -4 * p, -10 + 6 * p, 0 },
			Neck = { 6 * p, 8, 0 },
		}
		pernas(j, 6 * (1 - p))
		return { juntas = j, sobe = -0.08 * (1 - p) }
	end,
	-- o braço esquerdo aberto no alto, acenando
	aceno = function(t: number): Pose
		local w = sen(1.4, t)
		local j = {
			LeftShoulder = { 10, 0, -160 + 15 * w },
			LeftElbow = { 15, 0, 0 },
			LeftWrist = { 0, 0, 20 * sen(1.4, t, 0.5) },
			RightShoulder = { 15, 0, 6 },
			RightElbow = { 30, 0, 0 },
			RightWrist = { 0, 0, 0 },
			Waist = { 0, 8, 5 * sen(0.7, t) },
			Neck = { 4, -6, 0 },
		}
		pernas(j, 4)
		return { juntas = j, sobe = 0 }
	end,
	-- os dois braços em V, pulando
	vitoria = function(t: number): Pose
		local h = sen(1.2, t)
		local j = {
			RightShoulder = { 15, 0, 145 + 8 * h },
			RightElbow = { 10, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftShoulder = { 15, 0, -145 - 8 * h },
			LeftElbow = { 10, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			Waist = { -10, 0, 0 },
			Neck = { 18, 0, 0 },
		}
		pernas(j, 20 * math.max(0, -h))
		return { juntas = j, sobe = 0.9 * math.max(0, h) - 0.3 * math.max(0, -h) }
	end,
}

-- Sequência de cada lugar (gesto, segundos), em laço. Cada lugar começa num gesto diferente e com o
-- relógio adiantado, para os três não mexerem juntos.
Comemoracao.SEQ = {
	[1] = { { "fuzil_alto", 4.0 }, { "vitoria", 3.0 }, { "fuzil_alto", 3.5 }, { "aceno", 2.5 } },
	[2] = { { "punho", 3.2 }, { "aceno", 3.0 }, { "vitoria", 2.4 } },
	[3] = { { "aceno", 2.8 }, { "punho", 3.0 }, { "fuzil_alto", 3.0 } },
} :: { [number]: { { any } } }
Comemoracao.ATRASO = { [1] = 0, [2] = 0.8, [3] = 1.6 } :: { [number]: number }
Comemoracao.MISTURA_S = 0.6 -- passagem de um gesto ao outro (em 0,45 s o braço dava 11,7° num quadro)

local function duracao(seq: { { any } }): number
	local d = 0
	for _, g in seq do
		d += g[2]
	end
	return d
end

-- O gesto (nome, segundos dentro dele) do lugar no instante t, e o anterior com a duração dele (para
-- a mistura).
function Comemoracao.gestoEm(lugar: number, t: number): (string, number, string, number)
	local seq = Comemoracao.SEQ[lugar] or Comemoracao.SEQ[1]
	local tt = (t + (Comemoracao.ATRASO[lugar] or 0)) % duracao(seq)
	for i, g in seq do
		if tt < g[2] then
			local antes = seq[(i - 2) % #seq + 1]
			return g[1], tt, antes[1], antes[2]
		end
		tt -= g[2]
	end
	return seq[1][1], 0, seq[#seq][1], seq[#seq][2]
end

local function mistura(a: Pose, b: Pose, k: number): Pose
	local j: { [string]: { number } } = {}
	for _, nome in Comemoracao.JUNTAS do
		local pa = a.juntas[nome] or { 0, 0, 0 }
		local pb = b.juntas[nome] or { 0, 0, 0 }
		j[nome] = {
			pa[1] + (pb[1] - pa[1]) * k,
			pa[2] + (pb[2] - pa[2]) * k,
			pa[3] + (pb[3] - pa[3]) * k,
		}
	end
	return { juntas = j, sobe = a.sobe + (b.sobe - a.sobe) * k }
end

-- A pose do lugar no instante t (segundos desde o começo da comemoração): o gesto da vez, saindo do
-- anterior nos primeiros MISTURA_S (curva suave).
function Comemoracao.quadro(lugar: number, t: number): Pose
	local nome, dentro, antes, durAntes = Comemoracao.gestoEm(lugar, t)
	local agora = Comemoracao.GESTOS[nome](dentro)
	if dentro >= Comemoracao.MISTURA_S then
		return mistura(agora, agora, 1) -- todas as juntas preenchidas
	end
	-- o anterior segue no relógio dele (passou do fim por `dentro`) e sai na curva suave
	local velho = Comemoracao.GESTOS[antes](durAntes + dentro)
	local k = dentro / Comemoracao.MISTURA_S
	k = k * k * (3 - 2 * k)
	return mistura(velho, agora, k)
end

-- Giro máximo de cada tipo de junta (graus, em qualquer eixo), para o teste: nada de braço dando
-- volta nem joelho dobrando para a frente (o sinal do joelho e do cotovelo o teste confere à parte).
Comemoracao.LIMITES = {
	Shoulder = 185,
	Elbow = 150,
	Wrist = 40,
	Waist = 25,
	Neck = 30,
	Hip = 60,
	Knee = 120,
	Ankle = 60,
} :: { [string]: number }

return Comemoracao
