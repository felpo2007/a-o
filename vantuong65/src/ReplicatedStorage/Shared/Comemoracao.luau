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
	-- D-214: em posição de sentido (o fuzil ao lado, o queixo erguido), respirando
	sentido = function(t: number): Pose
		local r = sen(0.35, t)
		local j = {
			RightShoulder = { 8, 0, 4 },
			RightElbow = { 12, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftShoulder = { 4, 0, -4 },
			LeftElbow = { 6, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			Waist = { 1.5 * r, 0, 0 },
			Neck = { 8 + 2 * r, 0, 0 },
		}
		pernas(j, 0)
		return { juntas = j, sobe = 0 }
	end,
	-- D-214: apresentar armas: o fuzil de pé à frente do peito, as duas mãos nele, firme
	apresentar = function(t: number): Pose
		local r = sen(0.35, t)
		local j = {
			RightShoulder = { 48, 0, -12 },
			RightElbow = { 96, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftShoulder = { 52 + 2 * r, 0, 22 },
			LeftElbow = { 78, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			Waist = { 0, 0, 0 },
			Neck = { 4 + 1.5 * r, 0, 0 },
		}
		pernas(j, 0)
		return { juntas = j, sobe = 0 }
	end,
	-- D-214: grito de guerra: o punho esquerdo batendo no peito, curvado; depois os braços no alto e o
	-- rosto para o céu (vai e volta num ciclo de 2,4 s, sem tranco)
	grito = function(t: number): Pose
		local k = 0.5 - 0.5 * math.cos(TAU * t / 2.4) -- 0 no peito, 1 no alto
		local b = math.max(0, sen(2.2, t)) -- as batidas no peito
		local peito = {
			RightShoulder = { 20, 0, 8 },
			RightElbow = { 40, 0, 0 },
			LeftShoulder = { 75 + 12 * b, 0, 18 },
			LeftElbow = { 118 - 10 * b, 0, 0 },
			Waist = { 6 * b, 0, 0 },
			Neck = { -6, 0, 0 },
		}
		local alto = {
			RightShoulder = { 20, 0, 150 },
			RightElbow = { 12, 0, 0 },
			LeftShoulder = { 20, 0, -150 },
			LeftElbow = { 12, 0, 0 },
			Waist = { -12, 0, 0 },
			Neck = { 24, 0, 0 },
		}
		local j: { [string]: { number } } = { RightWrist = { 0, 0, 0 }, LeftWrist = { 0, 0, 0 } }
		for nome, a in peito do
			local c = alto[nome]
			j[nome] = { a[1] + (c[1] - a[1]) * k, a[2] + (c[2] - a[2]) * k, a[3] + (c[3] - a[3]) * k }
		end
		pernas(j, 10 - 6 * k)
		return { juntas = j, sobe = 0.25 * k * math.max(0, sen(1.2, t)) }
	end,
	-- D-214: rajada para o alto: o fuzil apontado para o céu com as duas mãos, três tiros seguidos com
	-- o tranco (ombro, cintura e cabeça) e uma pausa, a cada 1,6 s
	rajada = function(t: number): Pose
		local c = t % 1.6
		local r = 0
		for _, ts in { 0, 0.2, 0.4 } do
			if c >= ts then
				r += math.exp(-(c - ts) * 16)
			end
		end
		local j = {
			RightShoulder = { 150 - 7 * r, 0, 12 },
			RightElbow = { 22, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftShoulder = { 138 - 5 * r, 0, -8 },
			LeftElbow = { 44, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			Waist = { -10 - 4 * r, 0, 0 },
			Neck = { 22 - 3 * r, 0, 0 },
		}
		pernas(j, 8)
		return { juntas = j, sobe = 0 }
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

-- O gesto (nome, segundos dentro dele) de uma sequência em laço no instante t, e o anterior com a
-- duração dele (para a mistura).
local function naSeq(seq: { { any } }, t: number): (string, number, string, number)
	local tt = t % duracao(seq)
	for i, g in seq do
		if tt < g[2] then
			local antes = seq[(i - 2) % #seq + 1]
			return g[1], tt, antes[1], antes[2]
		end
		tt -= g[2]
	end
	return seq[1][1], 0, seq[#seq][1], seq[#seq][2]
end

-- O gesto (nome, segundos dentro dele) do lugar no instante t, e o anterior com a duração dele (para
-- a mistura).
function Comemoracao.gestoEm(lugar: number, t: number): (string, number, string, number)
	local seq = Comemoracao.SEQ[lugar] or Comemoracao.SEQ[1]
	return naSeq(seq, t + (Comemoracao.ATRASO[lugar] or 0))
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

-- A pose de uma sequência em laço no instante t: o gesto da vez, saindo do anterior nos primeiros
-- MISTURA_S (curva suave).
local function poseSeq(seq: { { any } }, t: number): Pose
	local nome, dentro, antes, durAntes = naSeq(seq, t)
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

-- A pose do lugar no instante t (segundos desde o começo da comemoração): o gesto da vez, saindo do
-- anterior nos primeiros MISTURA_S (curva suave).
function Comemoracao.quadro(lugar: number, t: number): Pose
	local seq = Comemoracao.SEQ[lugar] or Comemoracao.SEQ[1]
	return poseSeq(seq, t + (Comemoracao.ATRASO[lugar] or 0))
end

-- ===== D-214: o melhor da partida e as comemorações (pedido do dono: "faça o podio como no r6
-- mostrando os 3 primeiros e depois dando zoom para o melhor bem animado e podendo fazer comemoração
-- que iremos vender comemoração dps") =====
-- Cada comemoração é um item: as grátis todo mundo tem; as outras ficam "EM BREVE" até o dono pôr à
-- venda (o perfil guarda as que o jogador tem em `comemoracoes` e a escolhida em `comemoracao`).
export type Item = { id: string, nome: string, desc: string, seq: { { any } }, gratis: boolean }
Comemoracao.PADRAO = "padrao"
Comemoracao.CATALOGO = {
	{
		id = "padrao",
		nome = "Vitória",
		desc = "O fuzil no alto e os braços em V.",
		seq = { { "fuzil_alto", 3.5 }, { "vitoria", 3.0 } },
		gratis = true,
	},
	{
		id = "apresentar_armas",
		nome = "Apresentar armas",
		desc = "Em posição de sentido, o fuzil apresentado à frente do peito.",
		seq = { { "sentido", 1.2 }, { "apresentar", 3.2 }, { "sentido", 1.0 }, { "fuzil_alto", 2.6 } },
		gratis = true,
	},
	{
		id = "grito_guerra",
		nome = "Grito de guerra",
		desc = "O punho batendo no peito e os braços no alto.",
		seq = { { "grito", 4.8 } },
		gratis = false,
	},
	{
		id = "rajada_alto",
		nome = "Rajada para o alto",
		desc = "Três tiros para o céu, com o tranco do fuzil.",
		seq = { { "rajada", 3.2 }, { "fuzil_alto", 2.0 } },
		gratis = false,
	},
	{
		id = "aceno_tropa",
		nome = "Aceno à tropa",
		desc = "Acena para os companheiros e bate o punho no ar.",
		seq = { { "aceno", 2.6 }, { "punho", 2.6 } },
		gratis = false,
	},
	{
		id = "pulos",
		nome = "Pulos de alegria",
		desc = "Pula com os dois braços em V.",
		seq = { { "vitoria", 3.0 } },
		gratis = false,
	},
} :: { Item }

local porId: { [string]: Item } = {}
for _, it in Comemoracao.CATALOGO do
	porId[it.id] = it
end

function Comemoracao.item(id: any): Item?
	return if type(id) == "string" then porId[id] else nil
end

-- o id que vale (desconhecido vira a padrão)
function Comemoracao.valida(id: any): string
	return if Comemoracao.item(id) then id :: string else Comemoracao.PADRAO
end

-- o jogador pode usar? (grátis, ou guardada no perfil)
function Comemoracao.tem(id: any, possuidas: { [string]: any }?): boolean
	local it = Comemoracao.item(id)
	if not it then
		return false
	end
	return it.gratis or (possuidas ~= nil and possuidas[it.id] == true)
end

-- a pose da comemoração `id` no instante t (em laço)
function Comemoracao.celebracao(id: any, t: number): Pose
	local it = Comemoracao.item(id) or porId[Comemoracao.PADRAO]
	return poseSeq(it.seq, t)
end

-- O roteiro do pódio (s desde o começo da comemoração, que dura 12 s): o 3º, o 2º e o 1º chegam nos
-- caixotes um depois do outro; a câmera mostra os três e depois vai até o 1º, que faz a comemoração
-- dele (a dos outros dois continua nos gestos de sempre).
Comemoracao.PODIO = {
	entrada = { [1] = 0.85, [2] = 0.45, [3] = 0.15 } :: { [number]: number },
	queda = 0.4, -- s do alto até o tampo
	zoom = 4.2, -- a câmera começa a ir até o 1º
	perto = 5.6, -- e chega
	mvp = 5.0, -- o 1º começa a comemoração dele (no meio da ida)
	mistura = 0.5,
}

-- A chegada do lugar no caixote: (à vista, quanto acima do tampo em studs). Cai de 7 studs, acelerando,
-- e dá um quique pequeno.
function Comemoracao.entrada(lugar: number, t: number): (boolean, number)
	local P = Comemoracao.PODIO
	local t0 = P.entrada[lugar] or 0
	if t < t0 then
		return false, 0
	end
	local u = (t - t0) / P.queda
	if u < 1 then
		return true, 7 * (1 - u * u)
	end
	local b = t - t0 - P.queda
	return true, 0.35 * math.max(0, math.sin(b * 12)) * math.exp(-b * 6)
end

-- A pose do lugar no pódio: os gestos de sempre; o 1º, a partir de PODIO.mvp, a comemoração `comId`
-- (saindo do gesto de antes na curva suave).
function Comemoracao.poseNoPodio(lugar: number, t: number, comId: any): Pose
	local base = Comemoracao.quadro(lugar, t)
	local P = Comemoracao.PODIO
	if lugar ~= 1 or t < P.mvp then
		return base
	end
	local c = Comemoracao.celebracao(comId, t - P.mvp)
	local k = math.clamp((t - P.mvp) / P.mistura, 0, 1)
	k = k * k * (3 - 2 * k)
	return mistura(base, c, k)
end

-- A câmera no instante t: (alvo x, y, z; distância; altura da câmera; campo de visão; giro em graus).
-- Aberta nos três, depois perto do 1º (dos joelhos para cima), na curva mais suave
-- (smootherstep). `solo` (a prévia do ARMÁRIO): só o 1º, de corpo inteiro.
export type Camera = { ax: number, ay: number, az: number, dist: number, alto: number, fov: number, giro: number }
function Comemoracao.camera(t: number, solo: boolean?): Camera
	local L1 = Comemoracao.LUGARES[1]
	if solo then
		return {
			ax = 0,
			ay = L1.alto + 4.2,
			az = 0,
			dist = 17,
			alto = L1.alto + 5.4,
			fov = 30,
			giro = 14 * math.sin(TAU * t / 12),
		}
	end
	local P = Comemoracao.PODIO
	local aberta: Camera = {
		ax = 0,
		ay = 8.6,
		az = -1,
		dist = 31 - 2 * math.min(1, t / 12),
		alto = 10.5,
		fov = 34,
		giro = 6 * math.sin(TAU * t / 11),
	}
	if t <= P.zoom then
		return aberta
	end
	-- a 16 studs com 30°: ~8,6 studs na vertical, das coxas até acima da cabeça (a 13, na faixa larga
	-- do palco, os braços erguidos cortavam)
	local perto: Camera = {
		ax = 0,
		ay = L1.alto + 5.0,
		az = 0,
		dist = 16,
		alto = L1.alto + 5.8,
		fov = 30,
		giro = 10 * math.sin(TAU * (t - P.zoom) / 9),
	}
	local u = math.clamp((t - P.zoom) / (P.perto - P.zoom), 0, 1)
	local k = u * u * u * (u * (u * 6 - 15) + 10)
	local out = {} :: any
	for campo, v in aberta :: any do
		out[campo] = v + ((perto :: any)[campo] - v) * k
	end
	return out :: Camera
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
