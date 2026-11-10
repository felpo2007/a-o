--!strict
-- Efeito de explosivos em pessoas e no terreno. Raios letal/de baixas e cratera: PLACEHOLDER de
-- design (D-36) até haver manual de munição; o formato (letal → ferido → nada, cobertura e postura
-- reduzindo a exposição) é o que importa para o jogo e fica travado em teste.
local Explosive = {}

export type Type = {
	id: string,
	name: string,
	lethalM: number, -- dentro: incapacita (energia de tronco >= torsoDownJ)
	casualtyM: number, -- até aqui: chance de ferimento caindo com a distância
	craterM: number, -- raio da cratera no terreno (0 = sem cratera)
	fragJ: number, -- energia típica de um fragmento que fere (J)
	src: string,
}

Explosive.TYPES = {
	mortar_81 = {
		id = "mortar_81",
		name = "81 mm HE",
		lethalM = 8,
		casualtyM = 30,
		craterM = 1.2,
		fragJ = 700,
		src = "PLACEHOLDER",
	},
	mortar_82 = {
		id = "mortar_82",
		name = "82 mm HE",
		lethalM = 8,
		casualtyM = 28,
		craterM = 1.2,
		fragJ = 700,
		src = "PLACEHOLDER",
	},
	naval_5in = {
		id = "naval_5in",
		name = "5 pol. HE",
		lethalM = 15,
		casualtyM = 50,
		craterM = 2.2,
		fragJ = 900,
		src = "PLACEHOLDER",
	},
	bomb_250lb = {
		id = "bomb_250lb",
		name = "bomba de 250 lb",
		lethalM = 20,
		casualtyM = 70,
		craterM = 3.5,
		fragJ = 1000,
		src = "PLACEHOLDER",
	},
	he_90 = {
		id = "he_90",
		name = "90 mm HE (M48A3)",
		lethalM = 6,
		casualtyM = 22,
		craterM = 0.9,
		fragJ = 700,
		src = "PLACEHOLDER",
	},
	heat_106 = {
		id = "heat_106",
		name = "106 mm HEAT (Ontos)",
		lethalM = 4,
		casualtyM = 15,
		craterM = 0.6,
		fragJ = 600,
		src = "PLACEHOLDER",
	},
	pg2 = {
		id = "pg2",
		name = "PG-2 (RPG-2)",
		lethalM = 2,
		casualtyM = 8,
		craterM = 0.3,
		fragJ = 500,
		src = "PLACEHOLDER",
	},
	grenade_us = {
		id = "grenade_us",
		name = "granada de mão (EUA)",
		lethalM = 5,
		casualtyM = 15,
		craterM = 0,
		fragJ = 600,
		src = "PLACEHOLDER",
	},
	grenade_vc = {
		id = "grenade_vc",
		name = "granada de cabo (VC)",
		lethalM = 4,
		casualtyM = 12,
		craterM = 0,
		fragJ = 550,
		src = "PLACEHOLDER",
	},
	rocket_35 = {
		id = "rocket_35",
		name = "3,5 pol. HEAT (M20)",
		lethalM = 2.5,
		casualtyM = 10,
		craterM = 0.4,
		fragJ = 550,
		src = "PLACEHOLDER",
	},
} :: { [string]: Type }

-- Exposição: 1 em pé e à vista; postura e cobertura reduzem (fatores de design).
Explosive.CROUCH = 0.6
Explosive.COVERED = 0.15

-- Resultado para um alvo a `distM`: "lethal" | "wound" | nil, e a energia a aplicar (J).
-- `u` em [0,1) é o sorteio (semente do servidor).
function Explosive.effect(id: string, distM: number, exposure: number, u: number): (string?, number)
	local t = Explosive.TYPES[id]
	if not t then
		return nil, 0
	end
	if distM <= t.lethalM * math.sqrt(exposure) then
		return "lethal", 2000
	end
	if distM > t.casualtyM then
		return nil, 0
	end
	-- chance cai com o quadrado da distância relativa (densidade de fragmentos ~ 1/d²)
	local rel = (distM - t.lethalM) / math.max(t.casualtyM - t.lethalM, 1)
	local p = math.clamp(1 - rel, 0, 1) ^ 2 * exposure
	if u < p then
		return "wound", t.fragJ * (1 - 0.5 * rel)
	end
	return nil, 0
end

-- Orçamento de crateras (Parte 9.6): no máximo `perMinute` por minuto, para limitar replicação.
export type Budget = { perMinute: number, stamps: { number } }

function Explosive.newBudget(perMinute: number): Budget
	return { perMinute = perMinute, stamps = {} }
end

function Explosive.allowCrater(b: Budget, now: number): boolean
	local keep = {}
	for _, t in b.stamps do
		if now - t < 60 then
			table.insert(keep, t)
		end
	end
	b.stamps = keep
	if #keep >= b.perMinute then
		return false
	end
	table.insert(b.stamps, now)
	return true
end

return Explosive
