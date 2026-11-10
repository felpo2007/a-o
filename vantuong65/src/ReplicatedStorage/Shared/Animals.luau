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
}

-- Velocidades: galinha corre ~4 m/s (14 km/h); búfalo-do-pântano em trote assustado ~6 m/s
-- (PLACEHOLDER; o galope chega bem acima). Raios de susto de design.
Animals.SPECIES = {
	water_buffalo = { fleeMs = 6, walkMs = 0.4, hearM = 150, fleeS = 10, leashM = 40 },
	chicken = { fleeMs = 4, walkMs = 0.5, hearM = 60, fleeS = 4, leashM = 12 },
} :: { [string]: Species }
Animals.EXPLOSION_MULT = 3 -- explosão assusta a 3x a distância de um tiro

function Animals.new(species: string, x: number, z: number): Animal
	return { species = species, x = x, z = z, homeX = x, homeZ = z, dirX = 0, dirZ = 0, fleeUntil = 0, nextWander = 0 }
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

-- Avança dt segundos. roll em [0,1) escolhe o rumo do pasto. Devolve true se andou.
function Animals.step(a: Animal, dt: number, now: number, roll: number): boolean
	local sp = Animals.SPECIES[a.species]
	if Animals.fleeing(a, now) then
		a.x += a.dirX * sp.fleeMs * dt
		a.z += a.dirZ * sp.fleeMs * dt
		return true
	end
	-- calmo: volta devagar para perto de casa; às vezes muda o rumo do pasto
	local hx, hz = a.homeX - a.x, a.homeZ - a.z
	local hd = math.sqrt(hx * hx + hz * hz)
	if hd > sp.leashM then
		a.dirX, a.dirZ = hx / hd, hz / hd
	elseif now >= a.nextWander then
		local ang = roll * 2 * math.pi
		a.dirX, a.dirZ = math.cos(ang), math.sin(ang)
		a.nextWander = now + 6 + roll * 8
	end
	a.x += a.dirX * sp.walkMs * dt
	a.z += a.dirZ * sp.walkMs * dt
	return true
end

-- Onde nascem: galinhas no quintal de 1 em cada 4 casas (2 por quintal); um búfalo para cada 6
-- casas, no arrozal a ~25 m da casa. rolls: função que devolve um número em [0,1).
-- houses: lista plana x1, z1, x2, z2, ... (metros). Devolve { species, x, z }.
function Animals.spawns(houses: { number }, rolls: () -> number): { { species: string, x: number, z: number } }
	local out = {}
	local n = 0
	for i = 1, #houses, 2 do
		n += 1
		local hx, hz = houses[i], houses[i + 1]
		if rolls() < 0.25 then
			for _ = 1, 2 do
				local a = rolls() * 2 * math.pi
				table.insert(out, { species = "chicken", x = hx + math.cos(a) * 6, z = hz + math.sin(a) * 6 })
			end
		end
		if n % 6 == 0 then
			local a = rolls() * 2 * math.pi
			table.insert(out, { species = "water_buffalo", x = hx + math.cos(a) * 25, z = hz + math.sin(a) * 25 })
		end
	end
	return out
end

return Animals
