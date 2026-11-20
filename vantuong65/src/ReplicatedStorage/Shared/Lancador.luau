--!strict
-- D-200 (prompt de jogabilidade, item 19): o lançador do antitanque (RPG-2 do VC; a bazuca M20 dos
-- EUA usa o mesmo caminho, sem arte de 1ª pessoa). Puro: o servidor (LancadorService), o cliente
-- (WeaponController, LancadorFx, HudCampo) e o teste do Lune usam as mesmas contas.
--
-- Munição: "Rockets" é o total que o soldado carrega, contando o que está no tubo; "RocketLoaded"
-- diz se o tubo está carregado. Atira só carregado; a recarga põe um da reserva no tubo.
--
-- O PG-2 não tem motor: sai a 84 m/s e cai como um projétil (sem arrasto; a essa velocidade e a
-- 150 m a perda é pequena). A 100 m ele já caiu ~7 m: por isso a alça, como a do RPG-2 (50, 100 e
-- 150 m). A ponta do centro da tela é onde ele cai na distância da alça.
local Lancador = {}

export type Ficha = {
	id: string, -- arte e som ("rpg2"); "m20" para a bazuca (sem arte)
	nome: string,
	municao: string,
	gun: string, -- ficha do projétil no VehicleService (explosivo e penetração)
	explosive: string, -- Shared/Explosive
	pen: string, -- Vehicles.PEN
	v0: number, -- m/s
	recargaS: number,
	armM: number, -- a espoleta arma depois desses metros de voo (antes: falha, sem explosão)
	dispersaoGraus: number, -- desvio padrão do tiro
	total: number, -- quantos ele leva ao nascer (com o do tubo)
	alcas: { number }, -- m
	maxVooS: number,
	src: { [string]: string },
}

Lancador.FICHA = {
	VC = {
		id = "rpg2",
		nome = "RPG-2",
		municao = "PG-2",
		gun = "pg2",
		explosive = "pg2",
		pen = "pg2",
		v0 = 84,
		recargaS = 6,
		armM = 5,
		dispersaoGraus = 0.4,
		total = 3,
		alcas = { 50, 100, 150 },
		maxVooS = 4,
		src = {
			v0 = "wiki:RPG-2; DTIC AD0783955 (84 m/s)",
			alcas = "wiki:RPG-2 (eficaz 100–150 m, máximo 200 m); russianwarrior.com (alça até 150 m)",
			recargaS = "equilíbrio: 4 a 6 tiros por minuto com a mira (Small Arms Survey); 6 s só a recarga",
			armM = "PLACEHOLDER (espoleta piezoelétrica; distância de armar sem fonte)",
			dispersaoGraus = "PLACEHOLDER",
			total = "PLACEHOLDER (3 por vida, como antes)",
		},
	} :: Ficha,
	US = {
		id = "m20",
		nome = "Bazuca M20",
		municao = "M28A2",
		gun = "rocket_35",
		explosive = "rocket_35",
		pen = "rocket_35",
		v0 = 100,
		recargaS = 6,
		armM = 5,
		dispersaoGraus = 0.35,
		total = 3,
		alcas = { 50, 100, 150, 200 },
		maxVooS = 4,
		src = {
			v0 = "PLACEHOLDER (o de antes)",
			alcas = "PLACEHOLDER",
			recargaS = "PLACEHOLDER (o de antes)",
			armM = "PLACEHOLDER",
			dispersaoGraus = "PLACEHOLDER",
			total = "PLACEHOLDER (3 por vida, como antes)",
		},
	} :: Ficha,
}
Lancador.ALCA_PADRAO = 100
Lancador.G = 9.80665
Lancador.INTERVALO_MIN_S = 0.8 -- entre dois pedidos de tiro (o servidor recusa antes)
Lancador.SAIDA_M = 1.0 -- o projétil nasce 1 m à frente da cabeça, na direção do tiro
-- o construtor do Vector3 (o global do Roblox; o teste do Lune põe o do @lune/roblox)
Lancador.V3 = (Vector3 :: any) :: typeof(Vector3)

function Lancador.de(faction: string?): Ficha
	return if faction == "US" then Lancador.FICHA.US else Lancador.FICHA.VC
end

-- tubo e reserva a partir do total e do "carregado"
function Lancador.estado(total: number?, carregado: boolean?): (number, number)
	local t = math.max(0, math.floor(tonumber(total) or 0))
	local tubo = if carregado == true and t > 0 then 1 else 0
	return tubo, t - tubo
end

function Lancador.podeAtirar(total: number?, carregado: boolean?): boolean
	local tubo = Lancador.estado(total, carregado)
	return tubo == 1
end

function Lancador.podeRecarregar(total: number?, carregado: boolean?): boolean
	local tubo, reserva = Lancador.estado(total, carregado)
	return tubo == 0 and reserva > 0
end

-- ângulo de elevação (rad) para cair a `distM` no mesmo nível, saindo a v0
function Lancador.elevacao(distM: number, v0: number): number
	local x = math.clamp(Lancador.G * distM / (v0 * v0), 0, 1)
	return 0.5 * math.asin(x)
end

-- a alça seguinte (passo +1/-1), sem dar a volta
function Lancador.proximaAlca(f: Ficha, atual: number, passo: number): number
	local i = table.find(f.alcas, atual) or 1
	return f.alcas[math.clamp(i + passo, 1, #f.alcas)]
end

-- direção do tiro: a da mira levantada pela alça (em volta do eixo "direita" da mira) e desviada
-- pela dispersão (u1, u2 em [0, 1): o ângulo e o raio do desvio)
function Lancador.direcao(mira: Vector3, f: Ficha, alcaM: number, u1: number, u2: number): Vector3
	local d = mira.Unit
	local up = Lancador.V3.new(0, 1, 0)
	local right = d:Cross(up)
	if right.Magnitude < 1e-4 then
		right = Lancador.V3.new(1, 0, 0)
	end
	right = right.Unit
	local theta = Lancador.elevacao(alcaM, f.v0)
	-- girar d em volta de right por theta (para cima)
	local c, s = math.cos(theta), math.sin(theta)
	local up2 = right:Cross(d).Unit
	d = (d * c + up2 * s).Unit
	-- dispersão: desvio gaussiano aproximado (Box-Muller com u2) num ângulo u1
	local sigma = math.rad(f.dispersaoGraus)
	local r = sigma * math.sqrt(-2 * math.log(math.max(1e-6, 1 - u2)))
	local a = 2 * math.pi * u1
	local side = right * math.cos(a) + up2 * math.sin(a)
	return (d + side * math.tan(r)).Unit
end

-- um passo do voo (m e m/s): posição nova e velocidade nova
function Lancador.passo(pos: Vector3, vel: Vector3, dt: number): (Vector3, Vector3)
	local nv = vel - Lancador.V3.new(0, Lancador.G * dt, 0)
	return pos + (vel + nv) * 0.5 * dt, nv
end

-- onde cai, no plano de saída, mirando reto pela alça (para o teste e a alça na tela)
function Lancador.alcanceNoPlano(v0: number, theta: number): number
	return v0 * v0 * math.sin(2 * theta) / Lancador.G
end

return Lancador
