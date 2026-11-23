--!strict
-- Calendário e sorteio determinísticos da campanha (missões, mercado, passe; plano de volta diária,
-- 2026-11-12). Puro: o mesmo resultado em todos os servidores e no teste do Lune. O dia é UTC
-- (meia-noite UTC renova as ordens do dia e o mercado); a semana começa na segunda 00:00 UTC.
local Calendario = {}

Calendario.DAY = 86400
Calendario.WEEK = 7 * 86400

-- dia UTC desde 1970-01-01 (o mesmo do Commerce.dayIndex)
function Calendario.dayIndex(t: number): number
	return math.floor(t / Calendario.DAY)
end

-- semana que começa na segunda 00:00 UTC (1970-01-01 foi quinta: o dia 4 é a 1ª segunda)
function Calendario.weekIndex(t: number): number
	return math.floor((Calendario.dayIndex(t) + 3) / 7)
end

function Calendario.nextDay(t: number): number
	return (Calendario.dayIndex(t) + 1) * Calendario.DAY
end

function Calendario.nextWeek(t: number): number
	return ((Calendario.weekIndex(t) + 1) * 7 - 3) * Calendario.DAY
end

-- dia da semana: 0 = domingo ... 6 = sábado (no fuso pedido, em horas: -3 = Brasília)
function Calendario.weekday(t: number, tzHours: number?): number
	local local_ = t + (tzHours or 0) * 3600
	return (math.floor(local_ / Calendario.DAY) + 4) % 7
end

-- "AAAA-MM-DD" do dia UTC (algoritmo civil de Howard Hinnant; sem os.date, igual no Lune)
function Calendario.dateString(day: number): string
	local z = day + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	if m <= 2 then
		y += 1
	end
	return string.format("%04d-%02d-%02d", y, m, d)
end

-- hash djb2 de 32 bits (inteiro >= 0; as contas ficam abaixo de 2^53: nada se perde no double)
function Calendario.hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 4294967296
	end
	return h
end

-- sorteia n itens distintos de `list` com a semente (gerador MINSTD, contas exatas em double: igual
-- em todo lugar, sem Random.new)
function Calendario.pick<T>(list: { T }, n: number, seed: string): { T }
	local pool = table.clone(list)
	local state = Calendario.hash(seed) % 2147483646 + 1
	local out: { T } = {}
	for _ = 1, math.min(n, #pool) do
		state = (state * 48271) % 2147483647
		local i = state % #pool + 1
		table.insert(out, pool[i])
		table.remove(pool, i)
	end
	return out
end

return Calendario
