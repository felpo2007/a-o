--!strict
-- Balística de morteiro (Parte 9.7 e F4): trajetória com arrasto quadrático a ⋅ v², integrada
-- numericamente. O coeficiente k de cada arma é CALIBRADO para que o alcance máximo calculado
-- coincida com o alcance máximo da fonte (velocidade inicial e alcance citados abaixo).
-- Tiro de morteiro é sempre no ramo alto (45°–85°): o elevador só sobe.
local Mortar = {}

Mortar.G = 9.80665
Mortar.MIN_ELEV = math.rad(45)
Mortar.MAX_ELEV = math.rad(85)
Mortar.MILS = 6400 -- milésimos da OTAN por volta (luneta M53 do M29)
-- Cargas incrementais como fração da v0 máxima. PLACEHOLDER (sem tabela de tiro): servem para que
-- distâncias curtas sejam alcançáveis no ramo alto, como no morteiro real.
Mortar.CHARGES = { 0.45, 0.6, 0.75, 0.9, 1.0 }

export type Spec = {
	id: string,
	name: string,
	faction: string,
	v0: number, -- m/s, carga máxima (0 = derivar de kFrom + alcance)
	maxRangeM: number,
	minRangeM: number,
	shellKg: number?,
	kFrom: string?, -- usa o arrasto calibrado de outra arma e deriva a v0
	explosive: string, -- chave em Explosive.TYPES
	src: string,
	k: number?, -- 1/m, calibrado em Mortar.spec()
}

Mortar.TYPES = {
	-- 82-BM-37 (o Type 53 chinês é cópia): v0 211 m/s, alcance 3.040 m, granada 3,05 kg
	-- (research/veiculos/wikipedia_infobox_2026-11-09.json, wiki:82-BM-37).
	-- Alcance mínimo: PLACEHOLDER de design (sem fonte).
	vc_82 = {
		id = "vc_82",
		name = "Morteiro 82 mm (Type 53)",
		faction = "VC",
		v0 = 211,
		maxRangeM = 3040,
		minRangeM = 100,
		shellKg = 3.05,
		explosive = "mortar_82",
		src = "wiki:82-BM-37",
	},
	-- M29 81 mm com HE M43A1B1 (munição da época): alcance 69–3.890 m (Hogg 1987, via
	-- wiki:M29_mortar). Sem v0 publicada: usa o arrasto do 82 mm (calibre e massa parecidos) e
	-- deriva a v0 que dá 3.890 m (D-36).
	us_81 = {
		id = "us_81",
		name = "Morteiro M29 81 mm",
		faction = "US",
		v0 = 0,
		maxRangeM = 3890,
		minRangeM = 69,
		explosive = "mortar_81",
		kFrom = "vc_82",
		src = "wiki:M29_mortar (Hogg 1987, p.665–666)",
	},
} :: { [string]: Spec }

-- simula um disparo em terreno plano (dh = alvo acima da boca, em m); devolve alcance, tempo, apogeu
function Mortar.simulate(v0: number, elev: number, k: number, dh: number?): (number, number, number)
	local dt = 0.02
	local x, y = 0, 0
	local vx, vy = v0 * math.cos(elev), v0 * math.sin(elev)
	local t, apex = 0, 0
	local target = dh or 0
	while t < 200 do
		local v = math.sqrt(vx * vx + vy * vy)
		local ax = -k * v * vx
		local ay = -Mortar.G - k * v * vy
		local nx, ny = x + vx * dt + 0.5 * ax * dt * dt, y + vy * dt + 0.5 * ay * dt * dt
		vx += ax * dt
		vy += ay * dt
		t += dt
		if ny > apex then
			apex = ny
		end
		if vy < 0 and ny <= target then
			-- interpola o cruzamento com a altura do alvo
			local f = (y - target) / math.max(y - ny, 1e-9)
			return x + (nx - x) * f, t - dt + dt * f, apex
		end
		x, y = nx, ny
	end
	return x, t, apex
end

-- maior alcance no ramo alto (45°–85°) para um k
function Mortar.maxRange(v0: number, k: number): number
	local best = 0
	for deg = 45, 85, 1 do
		local r = Mortar.simulate(v0, math.rad(deg), k)
		best = math.max(best, r)
	end
	return best
end

-- acha k tal que o alcance máximo calculado = alcance da fonte (bisseção em escala log)
function Mortar.calibrate(v0: number, maxRangeM: number): number
	local vacuum = v0 * v0 / Mortar.G
	if maxRangeM >= vacuum then
		return 0
	end
	local lo, hi = 1e-7, 1e-2
	for _ = 1, 60 do
		local mid = math.sqrt(lo * hi)
		if Mortar.maxRange(v0, mid) > maxRangeM then
			lo = mid
		else
			hi = mid
		end
	end
	return math.sqrt(lo * hi)
end

-- v0 que dá `maxRangeM` com um arrasto k conhecido (bisseção)
function Mortar.calibrateV0(k: number, maxRangeM: number): number
	local lo, hi = 10, 2000
	for _ = 1, 50 do
		local mid = (lo + hi) / 2
		if Mortar.maxRange(mid, k) > maxRangeM then
			hi = mid
		else
			lo = mid
		end
	end
	return (lo + hi) / 2
end

local calibrated: { [string]: Spec } = {}
function Mortar.spec(id: string): Spec?
	local c = calibrated[id]
	if c then
		return c
	end
	local s = Mortar.TYPES[id]
	if not s then
		return nil
	end
	local copy = table.clone(s)
	if s.kFrom then
		local base = Mortar.spec(s.kFrom)
		assert(base, "kFrom inválido")
		copy.k = base.k
		copy.v0 = Mortar.calibrateV0(base.k :: number, s.maxRangeM)
	else
		copy.k = Mortar.calibrate(s.v0, s.maxRangeM)
	end
	calibrated[id] = copy
	return copy
end

local function solveAt(v0: number, k: number, rangeM: number, dh: number?): (number?, number?)
	local bestDeg, best = 45, -1
	for deg = 45, 85, 1 do
		local r = Mortar.simulate(v0, math.rad(deg), k, dh)
		if r > best then
			best, bestDeg = r, deg
		end
	end
	if rangeM > best or Mortar.simulate(v0, Mortar.MAX_ELEV, k, dh) > rangeM then
		return nil, nil
	end
	local lo, hi = math.rad(bestDeg), Mortar.MAX_ELEV
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		if Mortar.simulate(v0, mid, k, dh) > rangeM then
			lo = mid
		else
			hi = mid
		end
	end
	local elev = (lo + hi) / 2
	local _, tof = Mortar.simulate(v0, elev, k, dh)
	return elev, tof
end

-- Elevação (rad), tempo de voo (s) e carga (índice) para atingir `rangeM` com desnível `dh`
-- (alvo acima = +). Usa a menor carga que alcança, como na prática. nil se fora do alcance.
function Mortar.solve(id: string, rangeM: number, dh: number?): (number?, number?, number?)
	local s = Mortar.spec(id)
	if not s or rangeM < s.minRangeM or rangeM > s.maxRangeM then
		return nil, nil, nil
	end
	for i, f in Mortar.CHARGES do
		local elev, tof = solveAt(s.v0 * f, s.k :: number, rangeM, dh)
		if elev then
			return elev, tof, i
		end
	end
	return nil, nil, nil
end

function Mortar.toMils(rad: number): number
	return rad / (2 * math.pi) * Mortar.MILS
end

return Mortar
