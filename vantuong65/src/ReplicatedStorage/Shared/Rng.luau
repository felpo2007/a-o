--!strict
-- Gerador pseudoaleatório determinístico (xorshift32). Mesma semente -> mesma sequência no
-- cliente, no servidor e no Lune: é a base da validação de tiros (Parte 7).
local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { s: number }, Rng))

function Rng.new(seed: number): Rng
	local s = bit32.band(math.floor(seed) % 4294967296, 0xFFFFFFFF)
	if s == 0 then
		s = 0x9E3779B9
	end
	return setmetatable({ s = s }, Rng)
end

function Rng.nextU32(self: Rng): number
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x
end

-- [0, 1)
function Rng.next(self: Rng): number
	return self:nextU32() / 4294967296
end

function Rng.range(self: Rng, a: number, b: number): number
	return a + (b - a) * self:next()
end

-- normal padrão (Box-Muller)
function Rng.gauss(self: Rng): number
	local u1 = math.max(self:next(), 1e-12)
	local u2 = self:next()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

return Rng
