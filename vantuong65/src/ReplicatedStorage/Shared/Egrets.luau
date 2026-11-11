--!strict
-- Garças no arrozal (D-76): bandos de garça-vaqueira e garça-branca nos tabuleiros alagados (muda
-- nova ou pousio; no arroz alto elas somem) e uma garça junto de cada búfalo, como na lavoura do
-- delta. Tiro ou explosão perto fazem o bando levantar voo e sumir; ele volta depois de 1–2 min.
-- Como os animais da vila, o voo é pista de onde veio o barulho. Só visual: o cliente põe as
-- garças (Egrets.client), sem física nem rede. Módulo puro: posições em metros.
local RiceField = require(script and (script :: any).Parent.RiceField or "./RiceField") :: any

local Egrets = {}

Egrets.VIEW_M = 150 -- bando aparece até aqui da câmera
Egrets.DROP_M = 190 -- e some além daqui
Egrets.HEAR_SHOT_M = 120 -- tiro assusta até aqui (a galinha ouve a 60 m, o búfalo a 150 m)
Egrets.HEAR_BLAST_M = 300 -- explosão
Egrets.FLIGHT_S = 16 -- tempo de voo até sumir
Egrets.CRUISE_MS = 9 -- velocidade de cruzeiro (garça-vaqueira voa a ~30–40 km/h)
Egrets.CLIMB_M = 14 -- altura de cruzeiro
Egrets.CLIMB_S = 3.5 -- tempo da subida
Egrets.RETURN_S = { 60, 120 } -- volta do bando depois do susto
-- fração dos tabuleiros com bando: no pousio (só água, a garça pesca à vista) mais que na muda
Egrets.FLOCK_SHARE = { fallow = 0.5, young = 0.2, mature = 0 } :: { [string]: number }

-- Quantas garças no tabuleiro de centro (x, z) em studs: 0 no arroz alto; 2–5 nos outros.
function Egrets.flockSize(x: number, z: number): number
	local share = Egrets.FLOCK_SHARE[RiceField.kind(x, z)] or 0
	local h = RiceField.hash(math.floor(x) + 17, math.floor(z) - 29, 5)
	if h >= share * 1000 then
		return 0
	end
	return 2 + h % 4
end

-- Posição da garça i do bando, no plano do tabuleiro (studs, relativo ao centro), e o rumo (rad).
-- O bando fica junto (raio de 6 studs) num ponto do tabuleiro escolhido pelo hash.
function Egrets.spot(x: number, z: number, sx: number, sz: number, i: number): (number, number, number)
	local hx = RiceField.hash(math.floor(x), math.floor(z), 11) / 1000 - 0.5
	local hz = RiceField.hash(math.floor(x), math.floor(z), 13) / 1000 - 0.5
	local cx = hx * math.max(sx - 16, 0)
	local cz = hz * math.max(sz - 16, 0)
	local a = RiceField.hash(math.floor(x) + i, math.floor(z), 17 + i) / 1000 * 2 * math.pi
	local r = 1.5 + RiceField.hash(math.floor(x), math.floor(z) + i, 19 + i) / 1000 * 4.5
	local yaw = RiceField.hash(math.floor(x) + 3 * i, math.floor(z) + 7, 23 + i) / 1000 * 2 * math.pi
	return cx + math.cos(a) * r, cz + math.sin(a) * r, yaw
end

-- Voo depois do susto: deslocamento (m) no tempo t (s) desde a decolagem, ao longo do rumo.
-- Devolve (avanço horizontal, altura). Arranca a 4 m/s e chega ao cruzeiro na subida.
function Egrets.flight(t: number): (number, number)
	t = math.max(t, 0)
	local k = math.clamp(t / Egrets.CLIMB_S, 0, 1)
	local ease = k * k * (3 - 2 * k)
	local alt = Egrets.CLIMB_M * ease
	-- velocidade sobe de 4 ao cruzeiro durante a subida: integral fechada
	local v0, v1 = 4, Egrets.CRUISE_MS
	local along
	if t <= Egrets.CLIMB_S then
		along = v0 * t + (v1 - v0) * t * t / (2 * Egrets.CLIMB_S)
	else
		along = v0 * Egrets.CLIMB_S + (v1 - v0) * Egrets.CLIMB_S / 2 + v1 * (t - Egrets.CLIMB_S)
	end
	return along, alt
end

-- O barulho em (nx, nz) assusta a garça em (x, z)? (metros)
function Egrets.hears(x: number, z: number, nx: number, nz: number, explosion: boolean): boolean
	local d = math.sqrt((x - nx) ^ 2 + (z - nz) ^ 2)
	return d <= (if explosion then Egrets.HEAR_BLAST_M else Egrets.HEAR_SHOT_M)
end

return Egrets
