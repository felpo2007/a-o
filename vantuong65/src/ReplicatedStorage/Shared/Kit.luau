--!strict
-- Equipamento por peso (Parte 11, "Lançamento"): o jogador escolhe carregadores, granadas, fumaça
-- e curativos dentro de um limite em kg. Vale a partir do próximo spawn. Módulo puro.
-- Pesos aproximados (PLACEHOLDER até ficha técnica): carregador de fuzil carregado ~0,75 kg
-- (20 x 7,62x51 ou 30 x 7,62x39), cinta/tambor de metralhadora ~2,9 kg, carregador de pistola
-- ~0,25 kg, granada de 40 mm ~0,23 kg, granada de mão ~0,45 kg (M26), fumaça ~0,54 kg (M18),
-- curativo individual ~0,1 kg. O cantil fica de fora enquanto o jogo não tiver sede/fadiga.
local Kit = {}

Kit.MAG_KG = { rifle = 0.75, mg = 2.9, pistol = 0.25, launcher = 0.23 } :: { [string]: number }
Kit.ITEMS = {
	{ id = "mags", name = "Carregadores", min = 1, max = 10 },
	{ id = "frags", name = "Granadas", kg = 0.45, min = 0, max = 4 },
	{ id = "smokes", name = "Fumaça", kg = 0.54, min = 0, max = 3 },
	{ id = "bandages", name = "Curativos", kg = 0.1, min = 1, max = 6 },
}
-- padrão = o que o jogo já dava por vida (CombatService MAGS, FieldService e Medical)
Kit.DEFAULT_MAGS = { rifle = 6, mg = 2, pistol = 3, launcher = 6 } :: { [string]: number }
Kit.MARGIN_KG = 1.0 -- limite = peso do kit padrão + 1 kg: trocar um item por outro, não somar tudo

export type Kit = { mags: number, frags: number, smokes: number, bandages: number }

function Kit.defaults(kind: string): Kit
	return { mags = Kit.DEFAULT_MAGS[kind] or 3, frags = 2, smokes = 1, bandages = 2 }
end

function Kit.weight(k: Kit, kind: string): number
	return k.mags * (Kit.MAG_KG[kind] or 0.75) + k.frags * 0.45 + k.smokes * 0.54 + k.bandages * 0.1
end

function Kit.limit(kind: string): number
	return Kit.weight(Kit.defaults(kind), kind) + Kit.MARGIN_KG
end

-- Saneia a escolha (vinda do cliente): inteiros nos limites de cada item e peso dentro do limite.
-- Se passar do peso, tira primeiro fumaça, depois granadas, curativos e carregadores.
function Kit.validate(raw: any, kind: string): Kit
	local k = Kit.defaults(kind)
	if type(raw) == "table" then
		for _, it in Kit.ITEMS do
			local v = raw[it.id]
			if type(v) == "number" and v == v then
				(k :: any)[it.id] = math.clamp(math.floor(v), it.min, it.max)
			end
		end
	end
	local limit = Kit.limit(kind)
	for _, id in { "smokes", "frags", "bandages", "mags" } do
		local min = 0
		for _, it in Kit.ITEMS do
			if it.id == id then
				min = it.min
			end
		end
		while Kit.weight(k, kind) > limit + 1e-9 and (k :: any)[id] > min do
			(k :: any)[id] -= 1
		end
	end
	return k
end

return Kit
