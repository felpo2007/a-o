--!strict
-- Balística por projétil (Parte 10.7): gravidade, arrasto G1 pelo coeficiente balístico,
-- variação de velocidade de boca e dispersão angular por semente. Unidades SI (m, s, kg).
-- Determinística: cliente e servidor rodam o mesmo código com a mesma semente (Parte 7).
local Rng = require(script and (script :: any).Parent.Rng or "./Rng") :: any
local Weapons = require(script and (script :: any).Parent.Weapons or "./Weapons") :: any

local Ballistics = {}

Ballistics.G = 9.80665
-- Ar em agosto na planície costeira: ~30 °C ao nível do mar.
Ballistics.RHO = 1.16 -- kg/m³ (ar seco a 30 °C, 1 atm)
Ballistics.SOUND = 349.0 -- m/s a 30 °C (331,3 * sqrt(1 + 30/273,15))
Ballistics.LBIN2_TO_KGM2 = 703.0696 -- lb/in² -> kg/m²

-- Coeficiente de arrasto do projétil-padrão G1 por número de Mach.
-- APROXIMADO (pontos de referência da tabela G1/Ingalls); validar com tabela publicada (Parte 9).
local G1 = {
	{ 0.00, 0.2629 },
	{ 0.50, 0.2032 },
	{ 0.70, 0.2165 },
	{ 0.80, 0.2546 },
	{ 0.90, 0.3415 },
	{ 0.95, 0.4084 },
	{ 1.00, 0.4805 },
	{ 1.05, 0.5427 },
	{ 1.10, 0.5883 },
	{ 1.20, 0.6237 },
	{ 1.30, 0.6342 },
	{ 1.50, 0.6290 },
	{ 1.80, 0.5994 },
	{ 2.00, 0.5794 },
	{ 2.50, 0.5368 },
	{ 3.00, 0.5043 },
}

function Ballistics.cdG1(mach: number): number
	if mach <= G1[1][1] then
		return G1[1][2]
	end
	for i = 2, #G1 do
		local m1, c1 = G1[i - 1][1], G1[i - 1][2]
		local m2, c2 = G1[i][1], G1[i][2]
		if mach <= m2 then
			return c1 + (c2 - c1) * (mach - m1) / (m2 - m1)
		end
	end
	return G1[#G1][2]
end

-- desaceleração por arrasto (m/s²) para velocidade v (m/s)
function Ballistics.dragDecel(v: number, bcG1: number, rho: number?): number
	local bc = bcG1 * Ballistics.LBIN2_TO_KGM2
	return (math.pi / 8) * (rho or Ballistics.RHO) * Ballistics.cdG1(v / Ballistics.SOUND) * v * v / bc
end

function Ballistics.energy(massG: number, v: number): number
	return 0.5 * (massG / 1000) * v * v
end

export type ShotParams = {
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number, -- direção (não precisa ser unitária)
	weaponId: string,
	seed: number,
	maxTime: number?,
	dt: number?,
}

-- velocidade inicial com dispersão (MOA) e variação de velocidade de boca (0,4% 1σ, PLACEHOLDER)
function Ballistics.initialVelocity(p: ShotParams): (number, number, number)
	local wp = Weapons.get(p.weaponId)
	assert(wp, "arma desconhecida: " .. p.weaponId)
	local rng = Rng.new(p.seed)
	local len = math.sqrt(p.dx * p.dx + p.dy * p.dy + p.dz * p.dz)
	local ux, uy, uz = p.dx / len, p.dy / len, p.dz / len
	-- base ortonormal perpendicular à direção
	local ax, ay, az = 0, 1, 0
	if math.abs(uy) > 0.9 then
		ax, ay, az = 1, 0, 0
	end
	local rx, ry, rz = uy * az - uz * ay, uz * ax - ux * az, ux * ay - uy * ax
	local rl = math.sqrt(rx * rx + ry * ry + rz * rz)
	rx, ry, rz = rx / rl, ry / rl, rz / rl
	local qx, qy, qz = uy * rz - uz * ry, uz * rx - ux * rz, ux * ry - uy * rx
	local sigma = math.rad(wp.dispersionMoa / 60) / 2 -- MOA ~ grupo; 1σ ≈ metade
	local e1, e2 = rng:gauss() * sigma, rng:gauss() * sigma
	local vx, vy, vz = ux + rx * e1 + qx * e2, uy + ry * e1 + qy * e2, uz + rz * e1 + qz * e2
	local vl = math.sqrt(vx * vx + vy * vy + vz * vz)
	local speed = wp.muzzleVelocity * (1 + 0.004 * rng:gauss())
	return vx / vl * speed, vy / vl * speed, vz / vl * speed
end

export type Hit = { x: number, y: number, z: number, t: number, speed: number, energy: number, target: any? }

-- Integra a trajetória. `cast(ax,ay,az,bx,by,bz)` testa o segmento e devolve
-- { x, y, z, target } do primeiro impacto ou nil. Devolve o impacto (ou nil) e o tempo voado.
function Ballistics.trace(p: ShotParams, cast: (number, number, number, number, number, number) -> any?): (Hit?, number)
	local wp = Weapons.get(p.weaponId)
	assert(wp, "arma desconhecida")
	local dt = p.dt or (1 / 120)
	local tmax = p.maxTime or 2.5
	local x, y, z = p.ox, p.oy, p.oz
	local vx, vy, vz = Ballistics.initialVelocity(p)
	local t = 0
	-- bala abaixo de 60 m/s não fere mais; a granada de 40 mm sai a 76 m/s e passa disso no ápice
	local vmin = math.min(60, wp.muzzleVelocity * 0.25)
	while t < tmax do
		local v = math.sqrt(vx * vx + vy * vy + vz * vz)
		if v < vmin then
			break
		end
		local a = Ballistics.dragDecel(v, wp.bcG1)
		-- Euler semi-implícito
		vx -= a * vx / v * dt
		vy -= (a * vy / v + Ballistics.G) * dt
		vz -= a * vz / v * dt
		local nx, ny, nz = x + vx * dt, y + vy * dt, z + vz * dt
		local h = cast(x, y, z, nx, ny, nz)
		if h then
			local sp = math.sqrt(vx * vx + vy * vy + vz * vz)
			return {
				x = h.x,
				y = h.y,
				z = h.z,
				t = t + dt,
				speed = sp,
				energy = Ballistics.energy(wp.bulletMassG, sp),
				target = h.target,
			},
				t + dt
		end
		x, y, z = nx, ny, nz
		t += dt
	end
	return nil, t
end

-- Altura (m) do projétil ao passar a `dist` metros, saindo da boca com o ângulo `angle` (rad), sem
-- dispersão; nil se ele não chega lá (perdeu a velocidade). Passo de 1 ms.
local function heightAt(wp: any, angle: number, dist: number): number?
	local dt = 1 / 1000
	local x, y = 0, 0
	local vx, vy = wp.muzzleVelocity * math.cos(angle), wp.muzzleVelocity * math.sin(angle)
	local vmin = math.min(50, wp.muzzleVelocity * 0.2) -- granada de 40 mm: 76 m/s na boca
	while x < dist do
		local v = math.sqrt(vx * vx + vy * vy)
		local a = Ballistics.dragDecel(v, wp.bcG1)
		vx -= a * vx / v * dt
		vy -= (a * vy / v + Ballistics.G) * dt
		local nx = x + vx * dt
		if nx >= dist then
			return y + vy * dt * (dist - x) / (nx - x)
		end
		x, y = nx, y + vy * dt
		if v < vmin then
			return nil
		end
	end
	return y
end
Ballistics.heightAt = heightAt

-- Alcance (m) no chão plano com o ângulo `angle` (rad): onde a altura volta a 0. Passo de 1 ms.
function Ballistics.rangeAt(weaponId: string, angle: number): number
	local wp = Weapons.get(weaponId)
	assert(wp, "arma desconhecida")
	local dt = 1 / 1000
	local x, y = 0, 0
	local vx, vy = wp.muzzleVelocity * math.cos(angle), wp.muzzleVelocity * math.sin(angle)
	for _ = 1, 60000 do
		local v = math.sqrt(vx * vx + vy * vy)
		local a = Ballistics.dragDecel(v, wp.bcG1)
		vx -= a * vx / v * dt
		vy -= (a * vy / v + Ballistics.G) * dt
		local ny = y + vy * dt
		if ny < 0 and vy < 0 then
			return x + vx * dt * y / (y - ny)
		end
		x, y = x + vx * dt, ny
	end
	return x
end

-- Queda (m) a `range` metros com a arma zerada a `zero` metros, tiro horizontal sem dispersão.
-- Para a tabela de validação contra as tabelas de tiro publicadas (Parte 9.11).
function Ballistics.dropAt(weaponId: string, range: number, zero: number): number
	local wp = Weapons.get(weaponId)
	assert(wp, "arma desconhecida")
	return -((heightAt(wp, Ballistics.zeroAngle(weaponId, zero), range)) or -math.huge)
end

-- Ângulo de elevação (rad) da alça zerada a `zero` m: bisseção até a altura 0 nessa distância.
-- Fuzil: até 2°; lançador de granada (lento): até 45° (a alça de escada da M79 vai a 375 m).
local zeroCache: { [string]: number } = {}
function Ballistics.zeroAngle(weaponId: string, zero: number): number
	local key = weaponId .. ":" .. zero
	if zeroCache[key] then
		return zeroCache[key]
	end
	local wp = Weapons.get(weaponId)
	assert(wp, "arma desconhecida")
	local lo, hi = 0, math.rad(if wp.muzzleVelocity < 150 then 45 else 2)
	for _ = 1, 50 do
		local mid = (lo + hi) / 2
		if (heightAt(wp, mid, zero) or -1) > 0 then
			hi = mid
		else
			lo = mid
		end
	end
	zeroCache[key] = (lo + hi) / 2
	return zeroCache[key]
end

return Ballistics
