--!strict
-- Mercado do dia (plano de volta diária, 2026-11-12, seção 3): 4 skins que mudam à meia-noite UTC e
-- um destaque da semana (segunda 00:00 UTC). O sorteio sai só da data: o mesmo em todos os servidores.
-- Sem pressão falsa: o item volta noutro dia, não há contagem regressiva inventada nem "só hoje"; o
-- mercado só põe em vitrine, com um desconto honesto em créditos ($ do jogo). Em Robux vale o preço
-- de sempre (o mesmo produto ou passe da skin, Shared/Skins).
-- Puro, testado no Lune (tests/luau/campanha.luau).
local Calendario = require(script and (script :: any).Parent.Calendario or "./Calendario") :: any
local Skins = require(script and (script :: any).Parent.Skins or "./Skins") :: any

local Mercado = {}

Mercado.ITEMS_PER_DAY = 4
Mercado.DAY_DISCOUNT = 0.2 -- 20% a menos em $ nos 4 do dia
Mercado.WEEK_DISCOUNT = 0.15 -- 15% a menos em $ no destaque da semana
Mercado.ROBUX_SLOT = 4 -- o 4º item do dia aparece com o botão de Robux (passe ou produto da skin)

export type Item = {
	id: string,
	name: string,
	kind: string,
	price: number,
	currency: string, -- "cr" | "robux"
	productKey: string?,
	owned: boolean,
}

-- skins que entram no sorteio: armas e uniformes; a camuflagem de mato (dá vantagem contra os bots)
-- fica fora da vitrine e continua na loja de sempre
local function pool(kinds: { [string]: boolean }): { string }
	local out = {}
	for _, s in Skins.CATALOG do
		if kinds[s.kind] then
			table.insert(out, s.id)
		end
	end
	table.sort(out)
	return out
end

local function item(id: string, discount: number, robux: boolean): Item?
	local s = Skins.get(id)
	if not s then
		return nil
	end
	if robux then
		return {
			id = s.id,
			name = s.name,
			kind = s.kind,
			price = s.robux,
			currency = "robux",
			productKey = s.robuxKey,
			owned = false,
		}
	end
	return {
		id = s.id,
		name = s.name,
		kind = s.kind,
		price = math.floor(s.price * (1 - discount) / 10 + 0.5) * 10,
		currency = "cr",
		productKey = s.robuxKey,
		owned = false,
	}
end

-- os 4 do dia UTC `day` (Calendario.dayIndex)
function Mercado.rotation(day: number): { Item }
	local out: { Item } = {}
	local ids = Calendario.pick(
		pool({ weapon = true, uniform = true }),
		Mercado.ITEMS_PER_DAY,
		string.format("mercado:%d", day)
	)
	for i, id in ids do
		local it = item(id, Mercado.DAY_DISCOUNT, i == Mercado.ROBUX_SLOT)
		if it then
			table.insert(out, it)
		end
	end
	return out
end

-- o destaque da semana (Calendario.weekIndex): um uniforme, em $ com desconto
function Mercado.featured(week: number): Item?
	local ids = Calendario.pick(pool({ uniform = true }), 1, string.format("destaque:%d", week))
	return if ids[1] then item(ids[1], Mercado.WEEK_DISCOUNT, false) else nil
end

-- preço em $ de hoje para a skin (nil se ela não está no mercado em $ hoje nem é o destaque)
function Mercado.priceToday(id: string, day: number, week: number): number?
	for _, it in Mercado.rotation(day) do
		if it.id == id and it.currency == "cr" then
			return it.price
		end
	end
	local f = Mercado.featured(week)
	if f and f.id == id then
		return f.price
	end
	return nil
end

return Mercado
