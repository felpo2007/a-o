--!strict
-- Animais da vila (Parte 11, "Lançamento"): búfalos e galinhas pastam perto de casa e fogem de
-- tiros e explosões. A fuga é uma pista de detecção: quem vê o bicho correndo sabe de onde veio
-- o barulho. Módulo puro (posições em metros, plano XZ; +X = leste, +Z = sul).
local Animals = {}

export type Species = {
	fleeMs: number, -- velocidade de fuga
	walkMs: number, -- passo pastando
	hearM: number, -- distância em que um tiro assusta
	fleeS: number, -- duração da fuga
	leashM: number, -- raio de pasto em volta de casa
	pauseShare: number, -- chance de parar (pastar, ciscar) quando acaba o trecho de caminhada
	pauseS: { number }, -- duração da parada, mínimo e máximo
}
export type Animal = {
	species: string,
	x: number,
	z: number,
	homeX: number,
	homeZ: number,
	dirX: number,
	dirZ: number,
	fleeUntil: number,
	nextWander: number,
	pauseUntil: number,
}

-- Velocidades: galinha corre ~4 m/s (14 km/h); búfalo-do-pântano em trote assustado ~6 m/s
-- (PLACEHOLDER; o galope chega bem acima). Raios de susto de design.
-- D-77: o búfalo passa a maior parte do tempo parado pastando e anda em trechos curtos; a
-- galinha cisca e anda aos pulinhos. Antes os dois andavam sem parar, como numa esteira.
-- Passo do búfalo pastando ~0,8 m/s (andar de bovino ~1 m/s; PLACEHOLDER).
Animals.SPECIES = {
	water_buffalo = {
		fleeMs = 6,
		walkMs = 0.8,
		hearM = 150,
		fleeS = 10,
		leashM = 40,
		pauseShare = 0.65,
		pauseS = { 8, 22 },
	},
	chicken = { fleeMs = 4, walkMs = 0.5, hearM = 60, fleeS = 4, leashM = 12, pauseShare = 0.5, pauseS = { 2, 7 } },
} :: { [string]: Species }
Animals.EXPLOSION_MULT = 3 -- explosão assusta a 3x a distância de um tiro

function Animals.new(species: string, x: number, z: number): Animal
	return {
		species = species,
		x = x,
		z = z,
		homeX = x,
		homeZ = z,
		dirX = 0,
		dirZ = 0,
		fleeUntil = 0,
		nextWander = 0,
		pauseUntil = 0,
	}
end

-- Barulho em (nx, nz). Devolve true se o animal se assustou (e passa a fugir para longe dele).
function Animals.noise(a: Animal, nx: number, nz: number, explosion: boolean, now: number): boolean
	local sp = Animals.SPECIES[a.species]
	local dx, dz = a.x - nx, a.z - nz
	local d = math.sqrt(dx * dx + dz * dz)
	local hear = sp.hearM * (if explosion then Animals.EXPLOSION_MULT else 1)
	if d > hear then
		return false
	end
	if d < 1e-3 then
		dx, dz, d = 1, 0, 1
	end
	a.dirX, a.dirZ = dx / d, dz / d
	a.fleeUntil = math.max(a.fleeUntil, now + sp.fleeS)
	return true
end

function Animals.fleeing(a: Animal, now: number): boolean
	return now < a.fleeUntil
end

-- Avança dt segundos. roll em [0,1) escolhe parar ou o rumo do pasto. Devolve true se andou
-- (false = parado pastando/ciscando).
function Animals.step(a: Animal, dt: number, now: number, roll: number): boolean
	local sp = Animals.SPECIES[a.species]
	if Animals.fleeing(a, now) then
		a.pauseUntil = 0
		a.x += a.dirX * sp.fleeMs * dt
		a.z += a.dirZ * sp.fleeMs * dt
		return true
	end
	-- calmo: volta devagar para perto de casa; no fim de cada trecho, para ou muda o rumo
	local hx, hz = a.homeX - a.x, a.homeZ - a.z
	local hd = math.sqrt(hx * hx + hz * hz)
	if hd > sp.leashM then
		a.dirX, a.dirZ = hx / hd, hz / hd
		a.pauseUntil = 0
	elseif now < a.pauseUntil then
		return false
	elseif now >= a.nextWander then
		if roll < sp.pauseShare then
			local k = roll / sp.pauseShare
			a.pauseUntil = now + sp.pauseS[1] + k * (sp.pauseS[2] - sp.pauseS[1])
			a.nextWander = a.pauseUntil
			return false
		end
		local ang = roll * 2 * math.pi
		a.dirX, a.dirZ = math.cos(ang), math.sin(ang)
		a.nextWander = now + 3 + roll * 6
	end
	a.x += a.dirX * sp.walkMs * dt
	a.z += a.dirZ * sp.walkMs * dt
	return true
end

-- Andar para a animação do cliente: "run" (fugindo), "walk" ou "idle" (parado).
function Animals.gait(a: Animal, now: number, moved: boolean): string
	if Animals.fleeing(a, now) then
		return "run"
	end
	return if moved then "walk" else "idle"
end

-- Onde nascem (D-74, com os modelos reduzidos): galinhas no quintal de 2 em cada 5 casas, em bando
-- de 3; um búfalo para cada 5 casas, no arrozal a ~25 m da casa. Antes: 2 galinhas em 1 de cada 4
-- quintais e 1 búfalo a cada 6 casas (o mapa parecia vazio). rolls: função que devolve um número
-- em [0,1). houses: lista plana x1, z1, x2, z2, ... (metros). Devolve { species, x, z }.
Animals.CHICKEN_YARDS = 0.4
Animals.CHICKENS_PER_YARD = 3
Animals.HOUSES_PER_BUFFALO = 5
function Animals.spawns(houses: { number }, rolls: () -> number): { { species: string, x: number, z: number } }
	local out = {}
	local n = 0
	for i = 1, #houses, 2 do
		n += 1
		local hx, hz = houses[i], houses[i + 1]
		if rolls() < Animals.CHICKEN_YARDS then
			for _ = 1, Animals.CHICKENS_PER_YARD do
				local a, r = rolls() * 2 * math.pi, 4 + rolls() * 4
				table.insert(out, { species = "chicken", x = hx + math.cos(a) * r, z = hz + math.sin(a) * r })
			end
		end
		if n % Animals.HOUSES_PER_BUFFALO == 0 then
			local a = rolls() * 2 * math.pi
			table.insert(out, { species = "water_buffalo", x = hx + math.cos(a) * 25, z = hz + math.sin(a) * 25 })
		end
	end
	return out
end

-- Manada no arrozal perto de uma vila (D-74): 2 adultos e 1 bezerro (escala 0,6) a poucos metros
-- um do outro, a 50–110 m do centro. isPaddy(x, z) em metros diz se o ponto é arrozal; tenta 40
-- rumos e desiste (lista vazia) se não achar. Devolve { species, x, z, scale }.
function Animals.herd(
	cx: number,
	cz: number,
	rolls: () -> number,
	isPaddy: (number, number) -> boolean
): { { species: string, x: number, z: number, scale: number } }
	for _ = 1, 40 do
		local a, r = rolls() * 2 * math.pi, 50 + rolls() * 60
		local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
		if isPaddy(x, z) then
			local out = {}
			for k = 1, 3 do
				local b = rolls() * 2 * math.pi
				local d = if k == 1 then 0 else 3 + rolls() * 3
				table.insert(out, {
					species = "water_buffalo",
					x = x + math.cos(b) * d,
					z = z + math.sin(b) * d,
					scale = if k == 3 then 0.6 else 1,
				})
			end
			return out
		end
	end
	return {}
end

return Animals
