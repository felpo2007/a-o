--!strict
-- D-238 (dono: "melhore a animação de como eles correm, está saltitando muito" e "quando ele rasteja
-- está tudo bugado"). Módulo PURO: só números, testado no Lune (tests/luau/passada.luau); quem aplica é
-- o Controllers/SoldierAnimations.
--
-- Por que saltitava: o clipe "correr" sobe e desce a bacia 46 cm e, nas velocidades do jogo, toca a
-- 4,9 passos por segundo. Aqui a corrida sai do caminho do PÉ:
-- - cadência de gente correndo (3,0 passos/s no trote, 3,6 na corrida) e passada longa;
-- - no apoio o pé anda para trás na velocidade do corpo (não escorrega) e, no balanço, volta num arco;
-- - o IK de dois ossos acha quadril e joelho; a bacia sobe e desce só 4 a 6 cm.
-- Rastejo: um ciclo por segundo, joelho aberto para o lado e cotovelo contrário puxando o corpo.
-- Eixos como no R15: X positivo leva a perna para a frente; joelho dobra em X negativo.
local Movement = require(script and (script :: any).Parent.Movement or "./Movement") :: any

local Passada3P = {}

local M: number = Movement.STUD_M

-- passos por segundo (dois passos = um ciclo)
Passada3P.CADENCIA = { base = 1.81, porMs = 0.253 }

-- em cada ponta: trote (Movement.JOG) e corrida (Movement.SPRINT). PLACEHOLDER: conferir no Studio.
Passada3P.TROTE = { desce = 0.08, sobe = 0.045, inclina = 8, levanta = 0.17 }
Passada3P.CORRIDA = { desce = 0.10, sobe = 0.06, inclina = 14, levanta = 0.27 }
Passada3P.FRENTE = 0.46 -- parte da passada de apoio à frente do quadril
-- O boneco tem a perna curta (0,70 m do quadril ao tornozelo): o tempo de apoio sai do que a perna
-- alcança, para o pé não escorregar nem o joelho dobrar demais
Passada3P.ALCANCE = 0.92 -- do comprimento máximo do apoio
Passada3P.APOIO = { min = 0.14, max = 0.40 }

-- rastejo: metros por ciclo (um joelho e o outro)
-- D-246 (dono: "o rastejamento ainda esta bugado quando o personagem movimenta"): rastejo baixo de
-- infantaria. A passada caiu de 1,3 para 1,15 m por ciclo (1,17 ciclo/s a 1,34 m/s) para o pé escorregar
-- menos. A bacia e os ombros giram em sentidos opostos e o corpo avança a cada empurrão.
Passada3P.RASTEJO = {
	passada = 1.15,
	quadril = 18,
	abre = 56,
	abreMin = 6,
	joelho = 96,
	joelhoMin = 4,
	rolo = 11,
	guinada = 8,
	avanco = 0.05, -- m: o corpo vai e vem ao longo de si a cada empurrão
}

-- estado da passada de cada soldado neste cliente (SoldierAnimations escreve, PostureController lê)
Passada3P.vivo = (setmetatable({}, { __mode = "k" }) :: any) :: { [any]: { rastejo: number, braco: number } }

export type Geo = {
	coxa: number, -- quadril -> joelho (studs)
	canela: number, -- joelho -> tornozelo
	pe: number, -- tornozelo -> sola
	quadril: number, -- junta Root -> quadril, na vertical
	altura: number, -- junta Root -> chão, em pé
}

export type Perna = {
	quadril: number, -- rad, X
	joelho: number, -- rad, X (negativo dobra)
	tornozelo: number, -- rad, X
	apoio: boolean,
	x: number, -- tornozelo em relação à Root, studs, frente positiva
	y: number, -- altura do tornozelo sobre o chão, studs
}

export type Pose = {
	y: number, -- studs: a Root em relação à altura de pé
	inclina: number, -- rad: tronco para a frente
	giro: number, -- rad: bacia em Y
	rolo: number, -- rad: bacia em Z
	E: Perna,
	D: Perna,
}

function Passada3P.geo(coxa: number, canela: number, pe: number, quadril: number): Geo
	return { coxa = coxa, canela = canela, pe = pe, quadril = quadril, altura = quadril + coxa + canela + pe }
end

function Passada3P.passosPorSegundo(v: number): number
	return Passada3P.CADENCIA.base + Passada3P.CADENCIA.porMs * math.max(v, 0)
end

-- ciclos por segundo
function Passada3P.ciclos(v: number): number
	return Passada3P.passosPorSegundo(v) / 2
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 0 no trote, 1 na corrida
function Passada3P.fator(v: number): number
	return math.clamp((v - Movement.JOG) / (Movement.SPRINT - Movement.JOG), 0, 1)
end

local function hermite(a: number, ma: number, b: number, mb: number, s: number): number
	local s2, s3 = s * s, s * s * s
	return (2 * s3 - 3 * s2 + 1) * a + (s3 - 2 * s2 + s) * ma + (-2 * s3 + 3 * s2) * b + (s3 - s2) * mb
end

local function liso(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

-- IK de dois ossos no plano do passo: ângulo da coxa (no mundo, 0 = para baixo, + = frente) e dobra
local function ik(hx: number, hy: number, ax: number, ay: number, a: number, b: number): (number, number)
	local dx, dy = ax - hx, ay - hy
	local d = math.sqrt(dx * dx + dy * dy)
	local dMax, dMin = (a + b) * 0.998, math.abs(a - b) + 0.05
	if d > dMax then
		dx, dy, d = dx * dMax / d, dy * dMax / d, dMax
	elseif d < dMin then
		local k = dMin / math.max(d, 1e-4)
		dx, dy, d = dx * k, dy * k, dMin
	end
	local dobra = math.pi - math.acos(math.clamp((a * a + b * b - d * d) / (2 * a * b), -1, 1))
	local linha = math.atan2(dx, -dy)
	return linha + math.asin(math.clamp(b * math.sin(dobra) / d, -1, 1)), dobra
end

-- Tornozelo (studs, em relação à projeção da Root no chão) e giro do pé na fase p da perna.
local function caminho(
	p: number,
	passo: number,
	apoio: number,
	levanta: number,
	geo: Geo
): (number, number, number, boolean)
	local frente, tras = passo * Passada3P.FRENTE, -passo * (1 - Passada3P.FRENTE)
	if p < apoio then
		local s = p / apoio
		local x = frente + (tras - frente) * s
		-- calcanhar no começo, ponta do pé no fim
		local giro = math.rad(9) * (1 - liso(s / 0.2)) - math.rad(34) * liso((s - 0.55) / 0.45)
		local sobe = math.sin(math.max(-giro, 0)) * geo.pe * 1.3
		return x, geo.pe + sobe, giro, true
	end
	local s = (p - apoio) / (1 - apoio)
	-- sai e chega com a velocidade do apoio: sem tranco no pé
	local vel = (tras - frente) / apoio * (1 - apoio)
	local x = hermite(tras, vel * 0.55, frente, vel * 0.3, s)
	local arco = math.sin(math.pi * s ^ 0.8) ^ 1.2
	local giro = lerp(-math.rad(34), math.rad(9), liso(s)) - math.rad(16) * math.sin(math.pi * s)
	local sobeFim = math.sin(math.rad(34)) * geo.pe * 1.3 * (1 - liso(s / 0.3))
	return x, geo.pe + sobeFim + levanta * arco, giro, false
end

local function perna(
	p: number,
	ry: number,
	inclina: number,
	passo: number,
	apoio: number,
	levanta: number,
	geo: Geo
): Perna
	local ax, ay, peGiro, noChao = caminho(p, passo, apoio, levanta, geo)
	-- a inclinação leva o quadril para trás e um pouco para cima
	local hx = -geo.quadril * math.sin(inclina)
	local hy = ry + geo.altura - geo.quadril * math.cos(inclina)
	local coxa, dobra = ik(hx, hy, ax, ay, geo.coxa, geo.canela)
	local canela = coxa - dobra
	return {
		quadril = coxa + inclina,
		joelho = -dobra,
		tornozelo = peGiro - canela,
		apoio = noChao,
		x = ax,
		y = ay,
	}
end

-- Pose da corrida: fase em ciclos (o pé esquerdo toca o chão em 0), v em m/s.
function Passada3P.pose(fase: number, v: number, geo: Geo): Pose
	local u = Passada3P.fator(v)
	local T, C = Passada3P.TROTE, Passada3P.CORRIDA
	local inclina = math.rad(lerp(T.inclina, C.inclina, u))
	local levanta = lerp(T.levanta, C.levanta, u) / M
	local desce = lerp(T.desce, C.desce, u) / M
	local sobe = lerp(T.sobe, C.sobe, u) / M
	local periodo = 1 / math.max(Passada3P.ciclos(v), 1e-3)
	local perna2 = geo.coxa + geo.canela
	local h = math.max(perna2 - desce, 0.1)
	local alcance = 2 * math.sqrt(math.max(perna2 * perna2 - h * h, 0)) * Passada3P.ALCANCE
	local porCiclo = math.max(v / M * periodo, 1e-3)
	local apoio = math.clamp(alcance / porCiclo, Passada3P.APOIO.min, Passada3P.APOIO.max)
	local passo = porCiclo * apoio
	local p = fase % 1
	-- mais baixo no meio de cada apoio, mais alto no voo
	local y = -desce - sobe / 2 * math.cos(4 * math.pi * (p - apoio / 2))
	local giroBacia = math.rad(lerp(5, 8, u)) * math.cos(2 * math.pi * p)
	local rolo = math.rad(lerp(2, 3, u)) * math.sin(2 * math.pi * p)
	return {
		y = y,
		inclina = inclina,
		giro = giroBacia,
		rolo = rolo,
		E = perna(p, y, inclina, passo, apoio, levanta, geo),
		D = perna((p + 0.5) % 1, y, inclina, passo, apoio, levanta, geo),
	}
end

export type RastejoPerna = { dobra: number, abre: number, gira: number, joelho: number, tornozelo: number }
export type Rastejo = {
	rolo: number, -- rad: o corpo balança em volta do próprio comprimento
	avanco: number, -- studs: ao longo do corpo, a cada empurrão
	guinada: number, -- rad: e serpenteia no chão
	E: RastejoPerna,
	D: RastejoPerna,
	braco: number, -- −1..1: cotovelo que puxa (+ esquerdo)
}

-- ciclos por segundo do rastejo (um joelho e o outro)
function Passada3P.ciclosRastejo(v: number): number
	return math.max(v, 0) / Passada3P.RASTEJO.passada
end

local function pernaRastejo(p: number, lado: number): RastejoPerna
	local R = Passada3P.RASTEJO
	-- 1 = joelho puxado, 0 = perna esticada (empurrando): puxa mais depressa do que empurra
	local q = (p % 1)
	local puxa = if q < 0.38 then liso(q / 0.38) else 1 - liso((q - 0.38) / 0.62)
	return {
		dobra = math.rad(R.quadril), -- o clipe deitado deixa a bacia inclinada: a perna desce até o chão
		abre = lado * math.rad(lerp(R.abreMin, R.abre, puxa)),
		gira = -lado * math.rad(85) * liso(puxa * 1.6),
		joelho = -math.rad(lerp(R.joelhoMin, R.joelho, puxa)),
		tornozelo = -math.rad(lerp(35, 15, puxa)),
	}
end

-- Pose do rastejo: fase em ciclos; o joelho esquerdo puxa em 0 e o direito em 0,5.
function Passada3P.rastejo(fase: number): Rastejo
	local R = Passada3P.RASTEJO
	local p = fase % 1
	local s = math.sin(2 * math.pi * (p + 0.1))
	return {
		rolo = math.rad(R.rolo) * s,
		avanco = R.avanco / M * math.sin(4 * math.pi * (p - 0.12)),
		guinada = math.rad(R.guinada) * s,
		E = pernaRastejo(p, -1),
		D = pernaRastejo(p + 0.5, 1),
		braco = math.cos(2 * math.pi * (p + 0.5)), -- cotovelo direito puxa com o joelho esquerdo
	}
end

return Passada3P
